#import "WeChatHeaders.h"
#import "JJRedBagManager.h"
#import "JJRedBagSettingsController.h"
#import "JJRedBagParam.h"
#import <UserNotifications/UserNotifications.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>

// GIF的UTI标识符（避免依赖MobileCoreServices中已废弃的kUTTypeGIF）
#define kJJUTTypeGIF CFSTR("com.compuserve.gif")

// 缓存WCPayLogicMgr实例（strong引用，微信服务为单例不会造成泄漏）
static id jj_cachedPayLogicMgr = nil;

// 透传触摸的UIWindow：只在有内容的区域响应，其他区域透传
@interface JJPassthroughWindow : UIWindow
@end
@implementation JJPassthroughWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && sub.alpha > 0.01 && sub.userInteractionEnabled &&
            [sub pointInside:[self convertPoint:point toView:sub] withEvent:event]) {
            return YES;
        }
    }
    return NO;
}
@end

// 临时悬浮窗调试（确认问题后删除）
static JJPassthroughWindow *jj_debugWindow = nil;
static UIView *jj_debugContainer = nil;
static UITextView *jj_debugLogView = nil;
static NSMutableString *jj_debugLog = nil;
static BOOL jj_debugVisible = YES;
static UIButton *jj_debugToggleBtn = nil;
static UIWindow *jj_toggleWindow = nil;
static void jj_showDebugWindow(void);

// 调试窗口控制器（必须在jj_showDebugWindow之前定义）
@interface JJDebugHelper : NSObject
+ (instancetype)shared;
@end
@implementation JJDebugHelper
+ (instancetype)shared {
    static JJDebugHelper *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[self alloc] init]; });
    return inst;
}
- (void)jj_copyDebugLog {
    [UIPasteboard generalPasteboard].string = jj_debugLog ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:@"\u65e5\u5fd7\u5df2\u590d\u5236\u5230\u526a\u8d34\u677f" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)jj_closeDebugWindow {
    jj_debugWindow.hidden = YES;
    jj_debugWindow = nil;
    jj_debugContainer = nil; jj_debugLogView = nil; jj_debugVisible = NO;
    if (!jj_toggleWindow) {
        jj_toggleWindow = [[UIWindow alloc] initWithFrame:CGRectMake(5, 70, 60, 28)];
        jj_toggleWindow.windowLevel = 10000001;
        jj_toggleWindow.backgroundColor = [UIColor clearColor];
        jj_toggleWindow.rootViewController = [[UIViewController alloc] init];
        jj_toggleWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
        
        jj_debugToggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        jj_debugToggleBtn.frame = CGRectMake(0, 0, 60, 28);
        jj_debugToggleBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        [jj_debugToggleBtn setTitle:@"Debug" forState:UIControlStateNormal];
        [jj_debugToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        jj_debugToggleBtn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11];
        jj_debugToggleBtn.layer.cornerRadius = 6;
        [jj_debugToggleBtn addTarget:self action:@selector(jj_reopenDebugWindow) forControlEvents:UIControlEventTouchUpInside];
        [jj_toggleWindow.rootViewController.view addSubview:jj_debugToggleBtn];
    }
    jj_toggleWindow.hidden = NO;
}
- (void)jj_reopenDebugWindow {
    jj_toggleWindow.hidden = YES;
    jj_toggleWindow = nil;
    jj_debugVisible = YES;
    jj_showDebugWindow();
}
- (void)jj_clearLog {
    jj_debugLog = [NSMutableString string];
    if (jj_debugLogView) jj_debugLogView.text = @"";
}
- (void)jj_panDebugWindow:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:jj_debugContainer.superview];
    jj_debugContainer.center = CGPointMake(jj_debugContainer.center.x + t.x, jj_debugContainer.center.y + t.y);
    [pan setTranslation:CGPointZero inView:jj_debugContainer.superview];
}
@end

static void jj_dbg(NSString *msg) {
    if (!jj_debugLog) jj_debugLog = [NSMutableString string];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    [jj_debugLog appendFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!jj_debugContainer && jj_debugVisible) jj_showDebugWindow();
        if (jj_debugLogView) {
            jj_debugLogView.text = jj_debugLog;
            [jj_debugLogView scrollRangeToVisible:NSMakeRange(jj_debugLog.length, 0)];
        }
    });
}

static void jj_showDebugWindow(void) {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    
    // 使用独立UIWindow，windowLevel最高，确保在小程序等所有界面都可见可交互
    jj_debugWindow = [[JJPassthroughWindow alloc] initWithFrame:CGRectMake(0, 0, sw, sh)];
    jj_debugWindow.windowLevel = 10000000;
    jj_debugWindow.backgroundColor = [UIColor clearColor];
    jj_debugWindow.userInteractionEnabled = YES;
    
    jj_debugContainer = [[UIView alloc] initWithFrame:CGRectMake(5, 70, sw - 10, 220)];
    jj_debugContainer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    jj_debugContainer.layer.cornerRadius = 10;
    jj_debugContainer.clipsToBounds = YES;
    jj_debugContainer.userInteractionEnabled = YES;
    
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw - 10, 32)];
    titleBar.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    [jj_debugContainer addSubview:titleBar];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 100, 32)];
    title.text = @"Debug";
    title.textColor = [UIColor greenColor];
    title.font = [UIFont fontWithName:@"Menlo-Bold" size:13];
    [titleBar addSubview:title];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(sw - 200, 2, 50, 28);
    [clearBtn setTitle:@"\u6e05\u9664" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor yellowColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [clearBtn addTarget:[JJDebugHelper shared] action:@selector(jj_clearLog) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:clearBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(sw - 140, 2, 50, 28);
    [copyBtn setTitle:@"\u590d\u5236" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [copyBtn addTarget:[JJDebugHelper shared] action:@selector(jj_copyDebugLog) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(sw - 80, 2, 60, 28);
    [closeBtn setTitle:@"\u5173\u95ed" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [closeBtn addTarget:[JJDebugHelper shared] action:@selector(jj_closeDebugWindow) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:closeBtn];
    
    jj_debugLogView = [[UITextView alloc] initWithFrame:CGRectMake(0, 32, sw - 10, 188)];
    jj_debugLogView.backgroundColor = [UIColor clearColor];
    jj_debugLogView.textColor = [UIColor greenColor];
    jj_debugLogView.font = [UIFont fontWithName:@"Menlo" size:10];
    jj_debugLogView.editable = NO;
    if (jj_debugLog) jj_debugLogView.text = jj_debugLog;
    [jj_debugContainer addSubview:jj_debugLogView];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[JJDebugHelper shared] action:@selector(jj_panDebugWindow:)];
    [titleBar addGestureRecognizer:pan];
    
    [jj_debugWindow addSubview:jj_debugContainer];
    jj_debugWindow.hidden = NO;
    jj_debugVisible = YES;
}

// 插件归纳适配
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
- (void)registerSwitchWithTitle:(NSString *)title key:(NSString *)key;
@end

// 初始化
%ctor {
    [JJRedBagManager sharedManager];
    
    // 适配插件归纳
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] registerControllerWithTitle:@"吉酱助手" 
                                                                                version:@"1.0-1" 
                                                                             controller:@"JJRedBagSettingsController"];
        }
    });
}

#pragma mark - 红包消息Hook

// Hook消息接收 - 使用多个入口确保捕获所有消息
%hook CMessageMgr

- (void)OnAddMessageByReceiver:(CMessageWrap *)msgWrap {
    %orig;
    
    if (![[JJRedBagManager sharedManager] enabled]) return;
    
    @try {
        [self jj_handleReceivedMessage:msgWrap];
    } @catch (NSException *exception) {
        // 静默处理
    }
}

// Hook自己发送的消息 - 用于抢自己红包
- (void)OnMessageSentBySender:(CMessageWrap *)msgWrap {
    %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.grabSelfEnabled) return;
    
    @try {
        // 只处理红包消息(类型49)，且必须是群聊中自己发的红包
        if (!msgWrap) return;
        if (msgWrap.m_uiMessageType != 49) return;
        
        NSString *content = msgWrap.m_nsContent;
        if (!content) return;
        
        // 必须包含红包标识
        if ([content rangeOfString:@"wxpay://"].location == NSNotFound) return;
        
        // 必须是发到群聊的红包
        NSString *toUser = msgWrap.m_nsToUsr;
        if (!toUser || [toUser rangeOfString:@"@chatroom"].location == NSNotFound) return;
        
        [self jj_handleReceivedMessage:msgWrap];
    } @catch (NSException *exception) {
        // 静默处理
    }
}

- (void)onNewSyncAddMessage:(CMessageWrap *)msgWrap {
    %orig;
    
    if (![[JJRedBagManager sharedManager] enabled]) return;
    
    @try {
        [self jj_handleReceivedMessage:msgWrap];
    } @catch (NSException *exception) {
        // 静默处理
    }
}

%new
- (void)jj_handleReceivedMessage:(CMessageWrap *)msgWrap {
    if (!msgWrap) return;
    if (![msgWrap isKindOfClass:objc_getClass("CMessageWrap")]) return;
    
    // 消息类型49为应用消息（包括红包和转账）
    if (msgWrap.m_uiMessageType != 49) return;
    
    NSString *content = msgWrap.m_nsContent;
    if (!content) return;
    
    // 获取支付信息
    id rawPayInfo = [msgWrap m_oWCPayInfoItem];
    WCPayInfoItem *payInfo = nil;
    if (rawPayInfo && [rawPayInfo isKindOfClass:objc_getClass("WCPayInfoItem")]) {
        payInfo = (WCPayInfoItem *)rawPayInfo;
    }
    
    // 红包优先检测（红包URL含wxpay://...hongbao，转账含transferconfirm/c2c_transfer）
    BOOL hasHongbaoUrl = ([content rangeOfString:@"wxpay://c2cbizmessagehandler/hongbao"].location != NSNotFound);
    
    if (hasHongbaoUrl) {
        jj_dbg([NSString stringWithFormat:@"[分发] 红包消息 from=%@", msgWrap.m_nsFromUsr]);
        [self jj_processRedBagMessage:msgWrap];
        return;
    }
    
    // Transfer check
    BOOL isTransferMsg = NO;
    if (payInfo) {
        @try {
            BOOL hasTransferId = (payInfo.m_nsTransferID.length > 0);
            BOOL subTypeMatch = (payInfo.m_uiPaySubType == 1);
            BOOL contentMatch = ([content rangeOfString:@"transferconfirm"].location != NSNotFound) ||
                                ([content rangeOfString:@"c2c_transfer"].location != NSNotFound) ||
                                ([content rangeOfString:@"wcpay://c2cbizmessagehandler"].location != NSNotFound);
            isTransferMsg = hasTransferId && (subTypeMatch || contentMatch);
        } @catch (NSException *e) {}
    }
    
    if (isTransferMsg) {
        jj_dbg([NSString stringWithFormat:@"[分发] 转账消息 from=%@", msgWrap.m_nsFromUsr]);
        [self jj_processTransferMessage:msgWrap];
        return;
    }
    
    // 兜底：其他wxpay://消息也当红包处理
    if ([content rangeOfString:@"wxpay://"].location != NSNotFound) {
        jj_dbg([NSString stringWithFormat:@"[分发] wxpay消息(兜底) from=%@", msgWrap.m_nsFromUsr]);
        [self jj_processRedBagMessage:msgWrap];
        return;
    }
}

%new
- (void)jj_processRedBagMessage:(CMessageWrap *)msgWrap {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled) return;
    
    NSString *fromUser = msgWrap.m_nsFromUsr;
    NSString *toUser = msgWrap.m_nsToUsr;
    NSString *content = msgWrap.m_nsContent;
    
    // 获取自己的用户名
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    CContact *selfContact = [contactMgr getSelfContact];
    NSString *selfUserName = [selfContact m_nsUsrName];
    
    // 判断发送者是否是自己
    BOOL isSender = [fromUser isEqualToString:selfUserName];
    
    // 判断是否是群聊中别人发的消息（fromUser包含@chatroom）
    BOOL isGroupReceiver = [fromUser rangeOfString:@"@chatroom"].location != NSNotFound;
    
    // 判断是否是自己在群聊中发的消息
    // 情况1: 自己发的 && toUser是群聊（OnMessageSentBySender回调）
    // 情况2: fromUser是群聊 && realChatUser是自己（onNewSyncAddMessage回调）
    BOOL isGroupSender = NO;
    if (isSender && [toUser rangeOfString:@"@chatroom"].location != NSNotFound) {
        isGroupSender = YES;
    } else if (isGroupReceiver) {
        NSString *realChatUser = msgWrap.m_nsRealChatUsr;
        if ([realChatUser isEqualToString:selfUserName]) {
            isSender = YES;
            isGroupSender = YES;
        }
    }
    
    // 确定是否是群聊
    BOOL isGroup = isGroupReceiver || isGroupSender;
    
    // 确定会话ID
    NSString *chatId = isGroupSender ? toUser : fromUser;
    
    // 检查是否应该抢这个红包（模式判断）
    if (![manager shouldGrabRedBagInChat:chatId isGroup:isGroup]) {
        jj_dbg([NSString stringWithFormat:@"[红包] 跳过(模式不匹配) chatId=%@", chatId]);
        return;
    }
    
    // 私聊红包判断
    if (!isGroup && !manager.grabPrivateEnabled) {
        jj_dbg(@"[红包] 跳过(私聊未启用)");
        return;
    }
    
    // 判断是否应该抢红包
    // 1. 群聊中别人发的红包 -> 直接抢
    // 2. 群聊中自己发的红包 -> 需要开启"抢自己红包"
    // 3. 私聊中别人发的红包 -> 需要开启"抢私聊红包"
    // 4. 私聊中自己发的红包 -> 不抢（自己转给别人的）
    if (isGroupSender && !manager.grabSelfEnabled) {
        return; // 自己在群里发的红包，但没开启抢自己红包
    }
    if (!isGroup && isSender) {
        return; // 私聊中自己发的红包不抢
    }
    
    // 获取nativeUrl - 优先从mWCPayInfoItem获取
    NSString *nativeUrl = nil;
    WCPayInfoItem *payInfo = [msgWrap m_oWCPayInfoItem];
    if (payInfo) {
        nativeUrl = [payInfo m_c2cNativeUrl];
    }
    
    // 如果从payInfo获取失败，从content解析
    if (!nativeUrl || nativeUrl.length == 0) {
        NSDictionary *parsed = [self jj_parseNativeUrl:content];
        nativeUrl = parsed[@"nativeUrl"];
    }
    
    if (!nativeUrl || nativeUrl.length == 0) return;
    
    // 解析标题用于关键词过滤
    NSString *title = [self jj_parseRedBagTitle:content];
    if ([manager shouldFilterByKeyword:title]) {
        return;
    }
    
    // 计算延迟时间
    NSTimeInterval delay = [manager getDelayTimeForChat:chatId];
    
    // 准备参数传递给open方法
    NSMutableDictionary *context = [NSMutableDictionary dictionary];
    context[@"nativeUrl"] = nativeUrl;
    context[@"msgWrap"] = msgWrap;
    context[@"isSelfRedBag"] = @(isGroupSender);
    context[@"isGroup"] = @(isGroup);
    context[@"fromUser"] = fromUser;
    context[@"realChatUser"] = msgWrap.m_nsRealChatUsr ?: @"";
    context[@"content"] = title; // 红包标题
    
    // 执行抢红包
    jj_dbg([NSString stringWithFormat:@"[红包] 检测到红包 delay=%.1fs isGroup=%d isSelf=%d chatId=%@", delay, isGroup, isGroupSender, chatId]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self jj_openRedBagWithContext:context];
    });
}

%new
- (void)jj_openRedBagWithContext:(NSDictionary *)context {
    NSString *nativeUrl = context[@"nativeUrl"];
    CMessageWrap *msgWrap = context[@"msgWrap"];
    BOOL isSelfRedBag = [context[@"isSelfRedBag"] boolValue];
    
    if (!nativeUrl || nativeUrl.length == 0) return;
    
    @try {
        // 解析nativeUrl参数
        NSString *urlToParse = nativeUrl;
        if ([nativeUrl hasPrefix:@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?"]) {
            urlToParse = [nativeUrl substringFromIndex:[@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?" length]];
        }
        
        NSDictionary *nativeUrlDict = [objc_getClass("WCBizUtil") dictionaryWithDecodedComponets:urlToParse separator:@"&"];
        if (!nativeUrlDict) return;
        
        NSString *sendId = nativeUrlDict[@"sendid"];
        NSString *channelId = nativeUrlDict[@"channelid"];
        NSString *msgType = nativeUrlDict[@"msgtype"];
        
        if (!sendId || !channelId) return;
        
        // 构建请求参数
        NSMutableDictionary *reqParams = [NSMutableDictionary dictionary];
        reqParams[@"agreeDuty"] = @"0";
        reqParams[@"channelId"] = channelId ?: @"1";
        reqParams[@"inWay"] = @"0";
        reqParams[@"msgType"] = msgType ?: @"1";
        reqParams[@"nativeUrl"] = nativeUrl;
        reqParams[@"sendId"] = sendId;
        
        // 获取自己的信息
        CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
        CContact *selfContact = [contactMgr getSelfContact];
        
        // 创建红包参数并加入队列
        JJRedBagParam *param = [[JJRedBagParam alloc] init];
        param.msgType = msgType ?: @"1";
        param.sendId = sendId;
        param.channelId = channelId ?: @"1";
        param.nickName = [selfContact getContactDisplayName] ?: @"";
        param.headImg = [selfContact m_nsHeadImgUrl] ?: @"";
        param.nativeUrl = nativeUrl;
        param.sessionUserName = msgWrap.m_nsFromUsr;
        param.sign = nativeUrlDict[@"sign"] ?: @"";
        param.isSelfRedBag = isSelfRedBag;
        
        // 填充上下文信息用于自动回复和通知
        param.isGroup = [context[@"isGroup"] boolValue];
        param.fromUser = context[@"fromUser"];
        param.realChatUser = context[@"realChatUser"];
        param.content = context[@"content"];
        
        [[JJRedBagParamQueue sharedQueue] enqueue:param];
        
        // 保存到Pending字典
        @synchronized ([JJRedBagManager sharedManager].pendingRedBags) {
            [[JJRedBagManager sharedManager].pendingRedBags setObject:param forKey:sendId];
        }
        
        // 使用ReceiverQueryRedEnvelopesRequest方法查询红包状态
        WCRedEnvelopesLogicMgr *logicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                                              getService:objc_getClass("WCRedEnvelopesLogicMgr")];
        if (logicMgr) {
            [logicMgr ReceiverQueryRedEnvelopesRequest:reqParams];
            jj_dbg([NSString stringWithFormat:@"[红包] 已发送查询请求 sendId=%@", sendId]);
        } else {
            jj_dbg(@"[红包] ❌ 无法获取WCRedEnvelopesLogicMgr");
        }
    } @catch (NSException *exception) {
        jj_dbg([NSString stringWithFormat:@"[红包] ❌ openRedBag异常=%@", exception.reason]);
    }
}

%new
- (NSDictionary *)jj_parseNativeUrl:(NSString *)content {
    if (!content) return nil;
    
    @try {
        // 解析XML获取nativeUrl
        NSRange nativeUrlStart = [content rangeOfString:@"<nativeurl><![CDATA["];
        NSRange nativeUrlEnd = [content rangeOfString:@"]]></nativeurl>"];
        
        if (nativeUrlStart.location == NSNotFound || nativeUrlEnd.location == NSNotFound) {
            nativeUrlStart = [content rangeOfString:@"<nativeurl>"];
            nativeUrlEnd = [content rangeOfString:@"</nativeurl>"];
        }
        
        if (nativeUrlStart.location == NSNotFound || nativeUrlEnd.location == NSNotFound) {
            return nil;
        }
        
        NSUInteger start = nativeUrlStart.location + nativeUrlStart.length;
        NSUInteger length = nativeUrlEnd.location - start;
        NSString *nativeUrl = [content substringWithRange:NSMakeRange(start, length)];
        
        return @{@"nativeUrl": nativeUrl ?: @""};
    } @catch (NSException *exception) {
        return nil;
    }
}

%new
- (NSString *)jj_parseRedBagTitle:(NSString *)content {
    if (!content) return @"";
    
    @try {
        // 解析receivertitle标签
        NSRange range1 = [content rangeOfString:@"receivertitle><![CDATA[" options:NSLiteralSearch];
        NSRange range2 = [content rangeOfString:@"]]></receivertitle>" options:NSLiteralSearch];
        
        if (range1.location != NSNotFound && range2.location != NSNotFound) {
            NSRange range3 = NSMakeRange(range1.location + range1.length, range2.location - range1.location - range1.length);
            return [content substringWithRange:range3];
        }
        
        // 回退到title标签
        NSRange titleStart = [content rangeOfString:@"<title><![CDATA["];
        NSRange titleEnd = [content rangeOfString:@"]]></title>"];
        if (titleStart.location != NSNotFound && titleEnd.location != NSNotFound) {
            NSUInteger tStart = titleStart.location + titleStart.length;
            NSUInteger tLength = titleEnd.location - tStart;
            return [content substringWithRange:NSMakeRange(tStart, tLength)];
        }
    } @catch (NSException *exception) {
        // 静默处理
    }
    return @"";
}

%new
- (void)jj_processTransferMessage:(CMessageWrap *)msgWrap {
    @try {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    id rawPayInfo2 = [msgWrap m_oWCPayInfoItem];
    if (!rawPayInfo2 || ![rawPayInfo2 isKindOfClass:objc_getClass("WCPayInfoItem")]) return;
    WCPayInfoItem *payInfo = (WCPayInfoItem *)rawPayInfo2;
    
    // 检查是否已收款
    @try {
        if (payInfo.m_c2cPayReceiveStatus != 0) return;
    } @catch (NSException *e) { return; }
    
    // 检查是否是发给自己的转账
    NSString *selfUserName = msgWrap.m_nsToUsr;
    
    NSString *receiverUsername = nil;
    @try {
        id rawReceiver = [payInfo performSelector:@selector(transfer_receiver_username)];
        if ([rawReceiver isKindOfClass:[NSString class]]) receiverUsername = rawReceiver;
    } @catch (NSException *e) {}
    if (!receiverUsername || receiverUsername.length == 0) {
        @try {
            id rawExclusive = [payInfo performSelector:@selector(exclusive_recv_username)];
            if ([rawExclusive isKindOfClass:[NSString class]] && [rawExclusive length] > 0) receiverUsername = rawExclusive;
        } @catch (NSException *e) {}
    }
    if (!receiverUsername || ![receiverUsername isEqualToString:selfUserName]) return;
    
    NSString *fromUser = msgWrap.m_nsFromUsr;
    BOOL isGroup = [fromUser rangeOfString:@"@chatroom"].location != NSNotFound;
    
    // 检查开关
    if (isGroup) {
        if (!manager.autoReceiveGroupEnabled) return;
        if (manager.receiveGroups.count > 0) {
            if (![manager.receiveGroups containsObject:fromUser]) return;
            NSArray *allowedMembers = manager.groupReceiveMembers[fromUser];
            if (allowedMembers && allowedMembers.count > 0) {
                NSString *payerUsr = nil;
                @try {
                    id rawPayer = [payInfo performSelector:@selector(transfer_payer_username)];
                    if ([rawPayer isKindOfClass:[NSString class]]) payerUsr = rawPayer;
                } @catch (NSException *e) {}
                if (!payerUsr || ![allowedMembers containsObject:payerUsr]) return;
            }
        }
    } else {
        if (!manager.autoReceivePrivateEnabled) return;
    }
    
    // 安全获取字符串属性
    NSString *transferId = @"";
    NSString *transactionId = @"";
    NSString *payerUsername = @"";
    NSString *amountStr = @"0";
    NSString *memo = @"";
    
    @try {
        id rawTransferId = [payInfo performSelector:@selector(m_nsTransferID)];
        if ([rawTransferId isKindOfClass:[NSString class]]) transferId = [rawTransferId copy];
        
        id rawTransactionId = [payInfo performSelector:@selector(m_nsTranscationID)];
        if ([rawTransactionId isKindOfClass:[NSString class]]) transactionId = [rawTransactionId copy];
        
        id rawPayer = [payInfo performSelector:@selector(transfer_payer_username)];
        if ([rawPayer isKindOfClass:[NSString class]]) payerUsername = [rawPayer copy];
        
        // m_total_fee在8.0.69为null，改用m_nsFeeDesc（格式：¥0.01，单位为元）
        // 转换为分存储：¥0.01 → 去¥ → 0.01元 → ×100 → 1分（与totalReceiveAmount单位一致）
        id rawFeeDesc = [payInfo performSelector:@selector(m_nsFeeDesc)];
        if ([rawFeeDesc isKindOfClass:[NSString class]] && [rawFeeDesc length] > 0) {
            NSString *feeStr = (NSString *)rawFeeDesc;
            feeStr = [feeStr stringByReplacingOccurrencesOfString:@"¥" withString:@""];
            feeStr = [feeStr stringByReplacingOccurrencesOfString:@"￥" withString:@""];
            double yuan = [feeStr doubleValue];
            amountStr = [NSString stringWithFormat:@"%lld", (long long)(yuan * 100)];
            jj_dbg([NSString stringWithFormat:@"[金额] feeDesc=%@ → %@分 → %.2f元", rawFeeDesc, amountStr, yuan]);
        }
        
        id rawMemo = [payInfo performSelector:@selector(m_payMemo)];
        if ([rawMemo isKindOfClass:[NSString class]]) memo = [rawMemo copy];
    } @catch (NSException *e) {}
    
    // 获取转账失效时间（必须用valueForKey自动装箱，performSelector对标量值会触发ARC的SIGSEGV）
    unsigned int invalidTime = 0;
    @try {
        NSNumber *rawInvalidTime = [payInfo valueForKey:@"m_uiInvalidTime"];
        if (rawInvalidTime) invalidTime = [rawInvalidTime unsignedIntValue];
    } @catch (NSException *e) {}
    
    long long amountValue = [amountStr longLongValue];
    NSString *fromUserCopy = [fromUser copy];
    BOOL isGroupCopy = isGroup;
    NSString *payerUsernameCopy = [payerUsername copy];
    NSString *transferIdCopy = [transferId copy];
    
    // 构建收款请求参数
    NSMutableDictionary *confirmParams = [NSMutableDictionary dictionary];
    confirmParams[@"transferId"] = transferId;
    confirmParams[@"transactionId"] = transactionId;
    confirmParams[@"fromUser"] = fromUserCopy;
    confirmParams[@"isGroup"] = @(isGroup);
    confirmParams[@"payerUsername"] = payerUsername;
    confirmParams[@"amount"] = amountStr;
    confirmParams[@"memo"] = memo;
    confirmParams[@"selfUser"] = selfUserName;
    
    // dump金额相关属性调试
    static BOOL jj_dumpedFee = NO;
    if (!jj_dumpedFee) {
        jj_dumpedFee = YES;
        @try {
            unsigned int pcount = 0;
            objc_property_t *props = class_copyPropertyList([payInfo class], &pcount);
            for (unsigned int i = 0; i < pcount; i++) {
                NSString *pname = [NSString stringWithUTF8String:property_getName(props[i])];
                if ([[pname lowercaseString] containsString:@"fee"] || [[pname lowercaseString] containsString:@"amount"] || [[pname lowercaseString] containsString:@"money"]) {
                    @try {
                        id val = [payInfo valueForKey:pname];
                        jj_dbg([NSString stringWithFormat:@"[金额] %@=%@", pname, val]);
                    } @catch (NSException *e) {}
                }
            }
            free(props);
        } @catch (NSException *e) {}
    }
    jj_dbg([NSString stringWithFormat:@"[收款] 检测到转账 金额=%@ from=%@", amountStr, fromUserCopy]);
    
    // 直接执行自动收款（不延迟）
    @try {
        WCPayLogicMgr *payLogicMgr = (WCPayLogicMgr *)jj_cachedPayLogicMgr;
        jj_dbg([NSString stringWithFormat:@"[收款] cachedPayLogicMgr=%@", payLogicMgr ? @"有" : @"无"]);
        if (!payLogicMgr) {
            @try {
                payLogicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                               getService:objc_getClass("WCPayLogicMgr")];
                if (payLogicMgr) jj_cachedPayLogicMgr = payLogicMgr;
                jj_dbg([NSString stringWithFormat:@"[收款] MMServiceCenter获取=%@", payLogicMgr ? @"成功" : @"失败"]);
            } @catch (NSException *e) {
                jj_dbg([NSString stringWithFormat:@"[收款] MMServiceCenter异常=%@", e.reason]);
            }
        }
        if (!payLogicMgr) { jj_dbg(@"[收款] ❌ 无法获取WCPayLogicMgr"); return; }
        
        WCPayConfirmTransferRequest *request = [[objc_getClass("WCPayConfirmTransferRequest") alloc] init];
        if (!request) { jj_dbg(@"[收款] ❌ 创建Request失败"); return; }
        request.m_nsTransferID = transferIdCopy;
        request.m_nsFromUserName = payerUsernameCopy;
        request.m_uiInvalidTime = invalidTime;
        request.recv_channel_type = 0;
        request.sub_recv_channel_id = 0;
        if (isGroupCopy) {
            request.group_username = fromUserCopy;
            request.groupType = 1;
        } else {
            request.groupType = 0;
        }
        
        [payLogicMgr ConfirmTransferMoney:request];
        jj_dbg(@"[收款] ✅ ConfirmTransferMoney已调用");
        
        // 更新累计金额
        [[JJRedBagManager sharedManager] setTotalReceiveAmount:[[JJRedBagManager sharedManager] totalReceiveAmount] + amountValue];
        [[JJRedBagManager sharedManager] saveSettings];
        
        JJRedBagManager *mgr = [JJRedBagManager sharedManager];
        
        // 自动回复（使用AddMsg:MsgWrap:发送文本消息）
        BOOL isGroupChat = [confirmParams[@"isGroup"] boolValue];
        if (isGroupChat && mgr.receiveAutoReplyGroupEnabled && mgr.receiveAutoReplyContent.length > 0) {
            jj_dbg([NSString stringWithFormat:@"[回复] 群聊回复 to=%@ content=%@", fromUserCopy, mgr.receiveAutoReplyContent]);
            @try {
                NSString *selfUsr = confirmParams[@"selfUser"];
                CMessageWrap *replyWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
                replyWrap.m_nsContent = mgr.receiveAutoReplyContent;
                replyWrap.m_nsToUsr = fromUserCopy;
                replyWrap.m_nsFromUsr = selfUsr;
                replyWrap.m_uiStatus = 1;
                replyWrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
                [self AddMsg:fromUserCopy MsgWrap:replyWrap];
                jj_dbg(@"[回复] ✅ 群聊回复已发送");
            } @catch (NSException *e) { jj_dbg([NSString stringWithFormat:@"[回复] ❌ 异常=%@", e.reason]); }
        } else if (!isGroupChat && mgr.receiveAutoReplyPrivateEnabled && mgr.receiveAutoReplyContent.length > 0) {
            jj_dbg([NSString stringWithFormat:@"[回复] 私聊回复 to=%@ content=%@", fromUserCopy, mgr.receiveAutoReplyContent]);
            @try {
                NSString *selfUsr = confirmParams[@"selfUser"];
                CMessageWrap *replyWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
                replyWrap.m_nsContent = mgr.receiveAutoReplyContent;
                replyWrap.m_nsToUsr = fromUserCopy;
                replyWrap.m_nsFromUsr = selfUsr;
                replyWrap.m_uiStatus = 1;
                replyWrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
                [self AddMsg:fromUserCopy MsgWrap:replyWrap];
                jj_dbg(@"[回复] ✅ 私聊回复已发送");
            } @catch (NSException *e) { jj_dbg([NSString stringWithFormat:@"[回复] ❌ 异常=%@", e.reason]); }
        } else {
            jj_dbg([NSString stringWithFormat:@"[回复] 跳过 isGroup=%d gReply=%d pReply=%d content=%@",
                isGroupChat, mgr.receiveAutoReplyGroupEnabled, mgr.receiveAutoReplyPrivateEnabled,
                mgr.receiveAutoReplyContent.length > 0 ? mgr.receiveAutoReplyContent : @"空"]);
        }
        
        // 发送通知（使用AddMsg:MsgWrap:）
        if (mgr.receiveNotificationEnabled && mgr.receiveNotificationChatId.length > 0) {
            double amountYuan = amountValue / 100.0;
            NSMutableString *notifyMsg = [NSMutableString string];
            [notifyMsg appendFormat:@"收到一笔转账：\n金额：%.2f元", amountYuan];
            if (memo.length > 0) [notifyMsg appendFormat:@"\n备注：%@", memo];
            jj_dbg([NSString stringWithFormat:@"[通知] to=%@", mgr.receiveNotificationChatId]);
            @try {
                NSString *selfUsr = confirmParams[@"selfUser"];
                CMessageWrap *notifyWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
                notifyWrap.m_nsContent = notifyMsg;
                notifyWrap.m_nsToUsr = mgr.receiveNotificationChatId;
                notifyWrap.m_nsFromUsr = selfUsr;
                notifyWrap.m_uiStatus = 1;
                notifyWrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
                [self AddMsg:mgr.receiveNotificationChatId MsgWrap:notifyWrap];
                jj_dbg(@"[通知] ✅ 通知已发送");
            } @catch (NSException *e) { jj_dbg([NSString stringWithFormat:@"[通知] ❌ 异常=%@", e.reason]); }
        }
        
        // 本地弹窗通知
        if (mgr.receiveLocalNotificationEnabled) {
            [self jj_sendReceiveLocalNotification:confirmParams amount:amountValue];
        }
    } @catch (NSException *e) {
        jj_dbg([NSString stringWithFormat:@"[收款] ❌ 整体异常=%@", e.reason]);
    }
    } @catch (NSException *e) {}
}

%new
- (void)jj_sendReceiveAutoReply:(NSDictionary *)params isGroup:(BOOL)isGroup {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSString *content = manager.receiveAutoReplyContent;
    if (!content || content.length == 0) return;
    
    NSString *toUser = params[@"fromUser"];
    if (!toUser) return;
    
    @try {
        CMessageWrap *wrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
        wrap.m_nsContent = content;
        wrap.m_nsToUsr = toUser;
        wrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
        [self AddMsg:toUser MsgWrap:wrap];
    } @catch (NSException *e) {}
}

%new
- (void)jj_sendReceiveNotification:(NSDictionary *)params amount:(long long)amount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.receiveNotificationChatId || manager.receiveNotificationChatId.length == 0) return;
    
    double amountYuan = amount / 100.0;
    NSString *memo = params[@"memo"] ?: @"";
    
    NSMutableString *msg = [NSMutableString string];
    [msg appendString:@"\u6536\u5230\u4e00\u7b14\u8f6c\u8d26\uff1a\n"];
    [msg appendFormat:@"\u91d1\u989d\uff1a%.2f\u5143\n", amountYuan];
    if (memo.length > 0) {
        [msg appendFormat:@"\u5907\u6ce8\uff1a%@", memo];
    }
    
    @try {
        CMessageWrap *wrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
        wrap.m_nsContent = msg;
        wrap.m_nsToUsr = manager.receiveNotificationChatId;
        wrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
        [self AddMsg:manager.receiveNotificationChatId MsgWrap:wrap];
    } @catch (NSException *e) {}
}

%new
- (void)jj_sendReceiveLocalNotification:(NSDictionary *)params amount:(long long)amount {
    double amountYuan = amount / 100.0;
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"收款通知";
    content.body = [NSString stringWithFormat:@"收到转账 %.2f 元", amountYuan];
    content.sound = [UNNotificationSound defaultSound];
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    NSString *identifier = [NSString stringWithFormat:@"jj_receive_%@", params[@"transferId"]];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}


#pragma mark - 小游戏作弊(骰子/猜拳)

- (void)AddEmoticonMsg:(NSString *)msg MsgWrap:(CMessageWrap *)msgWrap {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.enabled && manager.gameCheatEnabled) {
        if ([msgWrap m_uiMessageType] == 47) {
            unsigned int gameType = [msgWrap m_uiGameType];
            if (gameType == 1 || gameType == 2) {
                if (manager.gameCheatMode == 0) {
                    // 模式1：发送时弹窗选择
                    NSString *title = (gameType == 1) ? @"请选择猜拳结果" : @"请选择骰子点数";
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎮 小游戏作弊"
                                                                                  message:title
                                                                           preferredStyle:UIAlertControllerStyleActionSheet];
                    
                    if (gameType == 1) {
                        // 猜拳：剪刀=1, 石头=2, 布=3
                        NSArray *rpsNames = @[@"✌️ 剪刀", @"✊ 石头", @"🖐 布"];
                        for (int i = 0; i < 3; i++) {
                            int content = i + 1;
                            [alert addAction:[UIAlertAction actionWithTitle:rpsNames[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                                [msgWrap setM_nsEmoticonMD5:[objc_getClass("GameController") getMD5ByGameContent:content]];
                                [msgWrap setM_uiGameContent:content];
                                %orig(msg, msgWrap);
                            }]];
                        }
                    } else {
                        // 骰子：点数1-6对应gameContent 4-9
                        for (int i = 1; i <= 6; i++) {
                            NSString *diceTitle = [NSString stringWithFormat:@"🎲 %d 点", i];
                            int content = i + 3;
                            [alert addAction:[UIAlertAction actionWithTitle:diceTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                                [msgWrap setM_nsEmoticonMD5:[objc_getClass("GameController") getMD5ByGameContent:content]];
                                [msgWrap setM_uiGameContent:content];
                                %orig(msg, msgWrap);
                            }]];
                        }
                    }
                    
                    [alert addAction:[UIAlertAction actionWithTitle:@"随机(不作弊)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                        %orig(msg, msgWrap);
                    }]];
                    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                    
                    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
                    if (alert.popoverPresentationController) {
                        alert.popoverPresentationController.sourceView = topVC.view;
                        alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 1, 1);
                    }
                    [topVC presentViewController:alert animated:YES completion:nil];
                    return;
                } else {
                    // 模式2：预设序列自动发送
                    NSString *sequence = (gameType == 1) ? manager.gameCheatRPSSequence : manager.gameCheatDiceSequence;
                    NSInteger currentIndex = (gameType == 1) ? manager.gameCheatRPSIndex : manager.gameCheatDiceIndex;
                    
                    
                    if (sequence.length > 0 && currentIndex < (NSInteger)sequence.length) {
                        unichar ch = [sequence characterAtIndex:currentIndex];
                        int value = ch - '0';
                        
                        // 更新序列位置
                        if (gameType == 1) { manager.gameCheatRPSIndex = currentIndex + 1; } else { manager.gameCheatDiceIndex = currentIndex + 1; }
                        [manager saveSettings];
                        
                        // 0表示不作弊，正常发送
                        if (value > 0) {
                            int gameContent = 0;
                            if (gameType == 1 && value >= 1 && value <= 3) {
                                gameContent = value; // 猜拳：1=剪刀,2=石头,3=布
                            } else if (gameType == 2 && value >= 1 && value <= 6) {
                                gameContent = value + 3; // 骰子：点数+3
                            }
                            
                            if (gameContent > 0) {
                                [msgWrap setM_nsEmoticonMD5:[objc_getClass("GameController") getMD5ByGameContent:gameContent]];
                                [msgWrap setM_uiGameContent:gameContent];
                            }
                        }
                    }
                    // 序列用完或值为0时，正常发送(不作弊)
                }
            }
        }
    }
    %orig(msg, msgWrap);
}

%end

#pragma mark - WCPayLogicMgr缓存Hook

%hook WCPayLogicMgr

- (instancetype)init {
    id result = %orig;
    jj_cachedPayLogicMgr = result;
    jj_dbg(@"[缓存] WCPayLogicMgr init已缓存");
    return result;
}

- (void)ConfirmTransferMoney:(id)arg1 {
    jj_cachedPayLogicMgr = self;
    %orig;
}

- (void)handleWCPayFacingReceiveMoneyMsg:(id)arg1 msgType:(int)arg2 {
    jj_cachedPayLogicMgr = self;
    %orig;
}

- (void)CheckTransferMoneyStatus:(id)arg1 {
    jj_cachedPayLogicMgr = self;
    %orig;
}

%end

#pragma mark - 添加设置入口

// Hook设置页面
%hook NewSettingViewController

- (void)viewDidLoad {
    %orig;
    
    @try {
        // 添加右上角设置按钮
        UIBarButtonItem *redBagBtn = [[UIBarButtonItem alloc] initWithTitle:@"红包" 
                                                                      style:UIBarButtonItemStylePlain 
                                                                     target:self 
                                                                     action:@selector(jj_openRedBagSettings)];
        
        NSMutableArray *rightItems = [NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems ?: @[]];
        [rightItems addObject:redBagBtn];
        self.navigationItem.rightBarButtonItems = rightItems;
    } @catch (NSException *exception) {
        // 静默处理
    }
}

%new
- (void)jj_openRedBagSettings {
    [[JJRedBagManager sharedManager] showSettingsController];
}

%end

#pragma mark - 后台保活支持

#import <AVFoundation/AVFoundation.h>
static UIBackgroundTaskIdentifier jj_bgTask = UIBackgroundTaskInvalid;
static NSTimer *jj_keepAliveTimer = nil;
static AVAudioPlayer *jj_silentAudioPlayer = nil;

static void jj_startBackgroundKeepAlive(void) {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.backgroundGrabEnabled) return;
    
    UIApplication *app = [UIApplication sharedApplication];
    
    // 结束之前的后台任务
    if (jj_bgTask != UIBackgroundTaskInvalid) {
        [app endBackgroundTask:jj_bgTask];
        jj_bgTask = UIBackgroundTaskInvalid;
    }
    
    // 开始新的后台任务
    jj_bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        if (jj_bgTask != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:jj_bgTask];
            jj_bgTask = UIBackgroundTaskInvalid;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_startBackgroundKeepAlive();
        });
    }];
}

static void jj_startSilentAudio(void) {
    if (jj_silentAudioPlayer && jj_silentAudioPlayer.isPlaying) return;
    
    @try {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        [session setActive:YES error:nil];
        
        // 创建一个极短的静音音频数据
        NSString *silentPath = [[NSBundle mainBundle] pathForResource:@"silent" ofType:@"mp3"];
        NSURL *silentURL = nil;
        
        if (silentPath) {
            silentURL = [NSURL fileURLWithPath:silentPath];
        } else {
            // 如果没有静音文件，创建一个空的音频
            NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"jj_silent.wav"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
                // 创建一个最小的WAV文件头 (44字节头 + 1秒16kHz单声道静音)
                NSMutableData *wavData = [NSMutableData data];
                uint32_t sampleRate = 16000;
                uint32_t dataSize = sampleRate * 2; // 1秒 * 16位
                uint32_t fileSize = 36 + dataSize;
                
                // RIFF header
                [wavData appendBytes:"RIFF" length:4];
                [wavData appendBytes:&fileSize length:4];
                [wavData appendBytes:"WAVE" length:4];
                
                // fmt chunk
                [wavData appendBytes:"fmt " length:4];
                uint32_t fmtSize = 16;
                [wavData appendBytes:&fmtSize length:4];
                uint16_t audioFormat = 1; // PCM
                [wavData appendBytes:&audioFormat length:2];
                uint16_t numChannels = 1;
                [wavData appendBytes:&numChannels length:2];
                [wavData appendBytes:&sampleRate length:4];
                uint32_t byteRate = sampleRate * 2;
                [wavData appendBytes:&byteRate length:4];
                uint16_t blockAlign = 2;
                [wavData appendBytes:&blockAlign length:2];
                uint16_t bitsPerSample = 16;
                [wavData appendBytes:&bitsPerSample length:2];
                
                // data chunk
                [wavData appendBytes:"data" length:4];
                [wavData appendBytes:&dataSize length:4];
                
                // 静音数据
                uint8_t *silence = (uint8_t *)calloc(dataSize, 1);
                [wavData appendBytes:silence length:dataSize];
                free(silence);
                
                [wavData writeToFile:tempPath atomically:YES];
            }
            silentURL = [NSURL fileURLWithPath:tempPath];
        }
        
        if (silentURL) {
            jj_silentAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:silentURL error:nil];
            jj_silentAudioPlayer.numberOfLoops = -1; // 无限循环
            jj_silentAudioPlayer.volume = 0.01; // 极小音量
            [jj_silentAudioPlayer play];
        }
    } @catch (NSException *e) {
        // 静默处理
    }
}

static void jj_stopSilentAudio(void) {
    if (jj_silentAudioPlayer) {
        [jj_silentAudioPlayer stop];
        jj_silentAudioPlayer = nil;
    }
}

static void jj_stopAllBackgroundModes(void) {
    if (jj_keepAliveTimer) {
        [jj_keepAliveTimer invalidate];
        jj_keepAliveTimer = nil;
    }
    if (jj_bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:jj_bgTask];
        jj_bgTask = UIBackgroundTaskInvalid;
    }
    jj_stopSilentAudio();
}

%hook MicroMessengerAppDelegate

- (void)applicationDidEnterBackground:(UIApplication *)application {
    %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.enabled && manager.backgroundGrabEnabled) {
        // 先停止所有
        jj_stopAllBackgroundModes();
        
        // 根据模式启动对应保活方式
        switch (manager.backgroundMode) {
            case JJBackgroundModeTimer:
                // 定时刷新模式
                jj_startBackgroundKeepAlive();
                jj_keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:25.0 repeats:YES block:^(NSTimer *timer) {
                    jj_startBackgroundKeepAlive();
                }];
                [[NSRunLoop mainRunLoop] addTimer:jj_keepAliveTimer forMode:NSRunLoopCommonModes];
                break;
                
            case JJBackgroundModeAudio:
                // 无声音频模式
                jj_startBackgroundKeepAlive();
                jj_startSilentAudio();
                break;
        }
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    %orig;
    
    // 进入前台停止所有后台保活
    jj_stopAllBackgroundModes();
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    // 请求通知权限
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.localNotificationEnabled) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError *error) {}];
    }
}

%end

#pragma mark - Hook红包响应处理

%hook WCRedEnvelopesLogicMgr

- (void)OnWCToHongbaoCommonResponse:(HongBaoRes *)response Request:(HongBaoReq *)request {
    %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled) return;
    
    @try {
        // 解析响应数据
        NSString *responseString = [[NSString alloc] initWithData:response.retText.buffer encoding:NSUTF8StringEncoding];
        NSDictionary *responseDict = [responseString JSONDictionary];
        if (!responseDict) return;
        
        // 处理查询请求的响应 (cgiCmdid == 3)
        if (response.cgiCmdid == 3) {
            JJRedBagParam *param = [[JJRedBagParamQueue sharedQueue] dequeue];
            if (!param) { jj_dbg(@"[红包] 查询响应: 队列为空"); return; }
            
            NSInteger receiveStatus = [responseDict[@"receiveStatus"] integerValue];
            NSInteger hbStatus = [responseDict[@"hbStatus"] integerValue];
            jj_dbg([NSString stringWithFormat:@"[红包] 查询响应 receiveStatus=%ld hbStatus=%ld sendId=%@", (long)receiveStatus, (long)hbStatus, param.sendId]);
            
            if (receiveStatus == 2) {
                if (param.sendId) [manager.pendingRedBags removeObjectForKey:param.sendId];
                jj_dbg(@"[红包] 跳过(已领取)");
                return;
            }
            
            if (hbStatus == 4) {
                if (param.sendId) [manager.pendingRedBags removeObjectForKey:param.sendId];
                jj_dbg(@"[红包] 跳过(已抢完/过期)");
                return;
            }
            
            if (!responseDict[@"timingIdentifier"]) { jj_dbg(@"[红包] ❌ 无timingIdentifier"); return; }
            
            param.timingIdentifier = responseDict[@"timingIdentifier"];
            NSTimeInterval delay = [manager getDelayTimeForChat:param.sessionUserName];
            
            if (delay > 0) {
                unsigned int delayMs = (unsigned int)(delay * 1000);
                JJReceiveRedBagOperation *operation = [[JJReceiveRedBagOperation alloc] initWithRedBagParam:param delay:delayMs];
                [[JJRedBagTaskManager sharedManager] addNormalTask:operation];
                jj_dbg([NSString stringWithFormat:@"[红包] 已加入队列 delay=%ums", delayMs]);
            } else {
                WCRedEnvelopesLogicMgr *logicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                                                      getService:objc_getClass("WCRedEnvelopesLogicMgr")];
                if (logicMgr) {
                    [logicMgr OpenRedEnvelopesRequest:[param toParams]];
                    jj_dbg(@"[红包] ✅ 极速模式已发送拆包请求");
                }
            }
            
        } else {
            // 处理拆开红包的响应 (cgiCmdid 通常为 4, 5, 168 等)
            // 通过sendId匹配上下文
            NSString *sendId = responseDict[@"sendId"];
            if (!sendId) return;
            
            JJRedBagParam *param = nil;
            @synchronized (manager.pendingRedBags) {
                param = [manager.pendingRedBags objectForKey:sendId];
            }
            
            if (!param) return;
            
            // 先移除上下文，避免重复处理
            @synchronized (manager.pendingRedBags) {
                [manager.pendingRedBags removeObjectForKey:sendId];
            }
            
            // 检查是否抢到金额
            long long amount = [responseDict[@"amount"] longLongValue];
            jj_dbg([NSString stringWithFormat:@"[红包] 拆包响应 sendId=%@ amount=%lld", sendId, amount]);
            if (amount > 0) {
                long long totalAmount = [responseDict[@"totalAmount"] longLongValue];
                param.totalAmount = totalAmount;
                
                manager.totalAmount += amount;
                [manager saveSettings];
                
                jj_dbg([NSString stringWithFormat:@"[红包] ✅ 抢到 %.2f元 累计%.2f元", amount/100.0, manager.totalAmount/100.0]);
                
                JJRedBagParam *paramCopy = param;
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        [self jj_sendAutoReply:paramCopy];
                        [self jj_sendNotification:paramCopy amount:amount];
                        [self jj_sendLocalNotification:paramCopy amount:amount];
                    } @catch (NSException *exception) {
                        jj_dbg([NSString stringWithFormat:@"[红包] ❌ 回复/通知异常=%@", exception.reason]);
                    }
                });
            } else {
                jj_dbg(@"[红包] 未抢到(金额=0)");
            }
        }
        
    } @catch (NSException *exception) {
        // 静默处理
    }
}

%new
- (void)jj_sendAutoReply:(JJRedBagParam *)param {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.autoReplyEnabled) return;
    
    // 检查内容
    if (!manager.autoReplyContent || manager.autoReplyContent.length == 0) return;
    
    // 检查私聊/群聊设置
    if (param.isGroup) {
        if (!manager.autoReplyGroupEnabled) return;
    } else {
        if (!manager.autoReplyPrivateEnabled) return;
    }
    
    // 延迟发送
    NSTimeInterval delay = 0.0;
    if (manager.autoReplyDelayEnabled) {
        delay = manager.autoReplyDelayTime;
    }
    
    NSString *replyContent = manager.autoReplyContent;
    NSString *toUser = param.sessionUserName;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self jj_sendMessage:replyContent toUser:toUser];
    });
}

%new
- (void)jj_sendNotification:(JJRedBagParam *)param amount:(long long)amount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.notificationEnabled) return;
    
    NSString *targetUser = manager.notificationChatId;
    if (!targetUser || targetUser.length == 0) return;
    
    // 格式化金额 (分转元)
    double amountYuan = amount / 100.0;
    double totalAmountYuan = param.totalAmount / 100.0;
    
    // 构建通知消息
    NSMutableString *msg = [NSMutableString string];
    [msg appendString:@"又为您抢到一个红包：\n"];
    [msg appendFormat:@"金额：%.2f元\n", amountYuan];
    if (param.totalAmount > 0) {
        [msg appendFormat:@"总金额：%.2f元\n", totalAmountYuan];
    }
    
    // 显示发送者
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    
    if (param.isGroup) {
        // 群聊红包：显示群名和发送者
        CContact *groupContact = [contactMgr getContactByName:param.sessionUserName];
        NSString *groupName = [groupContact getContactDisplayName] ?: @"未知群聊";
        
        if (param.realChatUser && param.realChatUser.length > 0) {
            CContact *senderContact = [contactMgr getContactByName:param.realChatUser];
            NSString *senderName = [senderContact getContactDisplayName] ?: param.realChatUser;
            [msg appendFormat:@"来源：【群】 %@ - %@\n", groupName, senderName];
        } else {
            [msg appendFormat:@"来源：【群】 %@\n", groupName];
        }
    } else {
        CContact *senderContact = [contactMgr getContactByName:param.sessionUserName];
        NSString *senderName = [senderContact getContactDisplayName] ?: @"未知好友";
        [msg appendFormat:@"来源：【私】 %@\n", senderName];
    }
    
    [msg appendFormat:@"时间：%@", [self jj_getCurrentTime]];
    
    [self jj_sendMessage:msg toUser:targetUser];
}

%new
- (void)jj_sendLocalNotification:(JJRedBagParam *)param amount:(long long)amount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.localNotificationEnabled) return;
    
    double amountYuan = amount / 100.0;
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"红包通知";
    content.body = [NSString stringWithFormat:@"本次抢到 %.2f 元", amountYuan];
    content.sound = [UNNotificationSound defaultSound];
    
    // 保存跳转信息
    content.userInfo = @{
        @"jj_redbag_jump": @(YES),
        @"chatName": param.sessionUserName ?: @""
    };
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    
    NSString *identifier = [NSString stringWithFormat:@"jj_redbag_%@", param.sendId];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

%new
- (NSString *)jj_getCurrentTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [formatter stringFromDate:[NSDate date]];
}

%new
- (void)jj_sendMessage:(NSString *)content toUser:(NSString *)toUser {
    if (!content || !toUser) return;
    
    CMessageWrap *msgWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
    if (!msgWrap) return;
    
    // 获取自己
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    CContact *selfContact = [contactMgr getSelfContact];
    
    msgWrap.m_nsFromUsr = [selfContact m_nsUsrName];
    msgWrap.m_nsToUsr = toUser;
    msgWrap.m_nsContent = content;
    msgWrap.m_uiStatus = 1; // 1=Sending
    msgWrap.m_uiMessageType = 1;
    
    // 使用MMNewSessionMgr生成时间戳
    MMNewSessionMgr *sessionMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("MMNewSessionMgr")];
    if (sessionMgr && [sessionMgr respondsToSelector:@selector(GenSendMsgTime)]) {
        msgWrap.m_uiCreateTime = [sessionMgr GenSendMsgTime];
    } else {
        msgWrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
    }
    
    msgWrap.m_uiMesLocalID = (unsigned int)msgWrap.m_uiCreateTime;
    
    CMessageMgr *msgMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CMessageMgr")];
    [msgMgr AddMsg:toUser MsgWrap:msgWrap];
}
%end

#pragma mark - Notification Jump Hook

%hook MicroMessengerAppDelegate

// 适配 iOS 10+ 前台/后台通知点击
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void(^)(void))completionHandler {
    
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    if ([userInfo[@"jj_redbag_jump"] boolValue]) {
        NSString *chatName = userInfo[@"chatName"];
        if (chatName && chatName.length > 0) {
            // 尝试跳转到对应聊天
            dispatch_async(dispatch_get_main_queue(), ^{
                CAppViewControllerManager *mgr = [objc_getClass("CAppViewControllerManager") getAppViewControllerManager];
                if ([mgr respondsToSelector:@selector(jumpToChatRoom:)]) {
                    [mgr jumpToChatRoom:chatName];
                }
            });
        }
    }
    
    %orig;
}

%end

#pragma mark - 添加摇一摇快捷开关

%hook UIWindow

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    %orig;
    
    if (motion == UIEventSubtypeMotionShake) {
        JJRedBagManager *manager = [JJRedBagManager sharedManager];
        if (!manager.shakeToConfigEnabled) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            
            // 如果已经是弹窗，不再重复弹出
            if ([topVC isKindOfClass:[UIAlertController class]]) {
                return;
            }
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"吉酱助手"
                                                                           message:manager.enabled ? @"当前状态：开启" : @"当前状态：关闭"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            NSString *toggleTitle = manager.enabled ? @"关闭抢红包" : @"开启抢红包";
            UIAlertAction *toggleAction = [UIAlertAction actionWithTitle:toggleTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                if (!manager.enabled && !manager.hasShownDisclaimer) {
                    [manager showDisclaimerAlertWithCompletion:nil];
                } else {
                    manager.enabled = !manager.enabled;
                    [manager saveSettings];
                }
            }];
            
            UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"打开设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [manager showSettingsController];
            }];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
            
            [alert addAction:toggleAction];
            [alert addAction:settingsAction];
            [alert addAction:cancelAction];
            
            [topVC presentViewController:alert animated:YES completion:nil];
        });
    }
}

%end

#pragma mark - 表情包放大/缩小功能

static CMessageWrap *jj_currentEmoticonMsgWrap = nil;
static NSString *jj_currentChatUserName = nil;
static UIImage *jj_currentEmoticonImage = nil;
static NSData *jj_currentEmoticonData = nil;
static BOOL jj_currentIsGIF = NO;

// 从响应链查找BaseMsgContentViewController获取当前聊天用户名
static NSString *jj_getChatUserNameFromResponderChain(UIView *fromView) {
    UIResponder *responder = fromView;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)responder;
            // 优先使用getChatUsername（BaseMsgContentViewController的方法）
            if ([vc respondsToSelector:@selector(getChatUsername)]) {
                NSString *userName = [vc performSelector:@selector(getChatUsername)];
                if (userName.length > 0) return userName;
            }
            // 备用：getCurrentChatName
            if ([vc respondsToSelector:@selector(getCurrentChatName)]) {
                NSString *userName = [vc performSelector:@selector(getCurrentChatName)];
                if (userName.length > 0) return userName;
            }
            // 备用：GetCContact
            if ([vc respondsToSelector:@selector(GetCContact)]) {
                CContact *contact = [vc performSelector:@selector(GetCContact)];
                if (contact && contact.m_nsUsrName.length > 0) {
                    return contact.m_nsUsrName;
                }
            }
            // 备用：GetContact
            if ([vc respondsToSelector:@selector(GetContact)]) {
                CContact *contact = [vc performSelector:@selector(GetContact)];
                if (contact && contact.m_nsUsrName.length > 0) {
                    return contact.m_nsUsrName;
                }
            }
        }
        responder = [responder nextResponder];
    }
    return nil;
}


// 判断NSData是否为GIF格式（通过文件头魔数判断）
static BOOL jj_isGIFData(NSData *data) {
    if (!data || data.length < 6) return NO;
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    return (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
            bytes[3] == 0x38 && (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61);
}

// 综合判断表情是否为GIF（结合XML属性 + 文件数据 + 多帧检测）
static BOOL jj_isEmoticonGIF(CMessageWrap *msgWrap, NSData *rawData) {
    // 1. 如果有原始数据，先用文件头魔数判断（最可靠）
    if (rawData && rawData.length > 6) {
        if (jj_isGIFData(rawData)) return YES;
        // 用ImageIO检测帧数（多帧=动图）
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)rawData, NULL);
        if (src) {
            size_t count = CGImageSourceGetCount(src);
            CFRelease(src);
            if (count > 1) return YES;
        }
    }
    
    // 2. 从XML内容判断
    NSString *content = msgWrap.m_nsContent;
    if (content && content.length > 0) {
        // type="2" 表示GIF类型
        if ([content rangeOfString:@"type=\"2\""].location != NSNotFound) return YES;
        // cdnurl中包含.gif
        if ([content rangeOfString:@".gif"].location != NSNotFound) return YES;
        // emoticonType=2
        if ([content rangeOfString:@"emoticonType=\"2\""].location != NSNotFound) return YES;
    }
    
    return NO;
}

// ========== 表情包缓存机制 ==========
// 缓存目录：tmp/JJEmoticonCache/
// 策略：点击"调整大小"时立即抓取并缓存，缩放发送后立即删除

// 获取缓存目录路径
static NSString *jj_emoticonCacheDir(void) {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *cacheDir = [tmpDir stringByAppendingPathComponent:@"JJEmoticonCache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    return cacheDir;
}

// 缓存文件路径（用时间戳命名，避免冲突）
static NSString *jj_currentCachePath = nil;

// 将表情数据写入缓存文件
static BOOL jj_cacheEmoticonData(NSData *data) {
    if (!data || data.length == 0) return NO;
    NSString *fileName = [NSString stringWithFormat:@"emoticon_%u", (unsigned int)[[NSDate date] timeIntervalSince1970]];
    NSString *path = [jj_emoticonCacheDir() stringByAppendingPathComponent:fileName];
    BOOL ok = [data writeToFile:path atomically:YES];
    if (ok) {
        jj_currentCachePath = [path copy];
    }
    return ok;
}

// 从缓存读取表情数据
static NSData *jj_readCachedEmoticonData(void) {
    if (!jj_currentCachePath) return nil;
    return [NSData dataWithContentsOfFile:jj_currentCachePath];
}

// 删除当前缓存文件
static void jj_deleteCachedEmoticon(void) {
    if (jj_currentCachePath) {
        [[NSFileManager defaultManager] removeItemAtPath:jj_currentCachePath error:nil];
        jj_currentCachePath = nil;
    }
}

// 从视图层级中递归查找UIImageView（用于从正在显示的表情中抓取图片）
static UIImageView *jj_findImageViewInView(UIView *view) {
    if (!view) return nil;
    // 优先找直接子视图中的UIImageView
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)subview;
            if (iv.image) return iv;
        }
    }
    // 递归查找
    for (UIView *subview in view.subviews) {
        UIImageView *found = jj_findImageViewInView(subview);
        if (found) return found;
    }
    return nil;
}

// 从EmoticonMessageCellView中抓取当前显示的表情图片数据
// 多策略抓取，确保百分百拿到数据：
// 策略1：从msgWrap.m_dtEmoticonData直接获取（最快）
// 策略2：通过CEmoticonMgr内部API用MD5获取（微信内部缓存，最可靠）
// 策略3：从正在显示的UIImageView中抓取（图片一定在内存中）
// 策略4：通过文件路径读取
static NSData *jj_captureEmoticonFromView(UIView *cellView, CMessageWrap *msgWrap) {
    // === 策略1：从msgWrap.m_dtEmoticonData直接获取 ===
    @try {
        NSData *data = msgWrap.m_dtEmoticonData;
        if (data && [data isKindOfClass:[NSData class]] && data.length > 0) {
            jj_dbg([NSString stringWithFormat:@"[表情策略1] ✅ m_dtEmoticonData=%lu bytes isGIF=%d", (unsigned long)data.length, jj_isGIFData(data)]);
            return data;
        }
        jj_dbg(@"[表情策略1] m_dtEmoticonData=空");
    } @catch (NSException *e) { jj_dbg([NSString stringWithFormat:@"[表情策略1] 异常=%@", e.reason]); }
    
    // === 策略2：通过CEmoticonMgr内部API获取 ===
    NSString *md5 = msgWrap.m_nsEmoticonMD5;
    jj_dbg([NSString stringWithFormat:@"[表情策略2] md5=%@", md5 ?: @"空"]);
    if (md5 && md5.length > 0) {
        // 2a: getEmoticonWrapByMd5
        @try {
            CEmoticonMgr *emoticonMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CEmoticonMgr")];
            BOOL hasMethod = [emoticonMgr respondsToSelector:@selector(getEmoticonWrapByMd5:)];
            jj_dbg([NSString stringWithFormat:@"[表情策略2a] emoticonMgr=%@ hasMethod=%d", emoticonMgr ? @"有" : @"无", hasMethod]);
            if (emoticonMgr && hasMethod) {
                CEmoticonWrap *wrap = [emoticonMgr getEmoticonWrapByMd5:md5];
                jj_dbg([NSString stringWithFormat:@"[表情策略2a] wrap=%@ imageData=%lu", wrap ? NSStringFromClass([wrap class]) : @"nil", (unsigned long)(wrap.m_imageData.length)]);
                if (wrap && wrap.m_imageData && wrap.m_imageData.length > 0) {
                    jj_dbg([NSString stringWithFormat:@"[表情策略2a] ✅ isGIF=%d", jj_isGIFData(wrap.m_imageData)]);
                    return wrap.m_imageData;
                }
            }
        } @catch (NSException *e) { jj_dbg([NSString stringWithFormat:@"[表情策略2a] 异常=%@", e.reason]); }
        
        // 2b: GetEmoticonByMD5
        @try {
            Class emoticonMgrClass = objc_getClass("CEmoticonMgr");
            BOOL hasClassMethod = [emoticonMgrClass respondsToSelector:@selector(GetEmoticonByMD5:)];
            jj_dbg([NSString stringWithFormat:@"[表情策略2b] hasClassMethod=%d", hasClassMethod]);
            if (hasClassMethod) {
                id result = [emoticonMgrClass GetEmoticonByMD5:md5];
                if (result) {
                    if ([result respondsToSelector:@selector(m_imageData)]) {
                        NSData *imgData = [result performSelector:@selector(m_imageData)];
                        if (imgData && [imgData isKindOfClass:[NSData class]] && imgData.length > 0) return imgData;
                    }
                    if ([result isKindOfClass:[UIImage class]]) {
                        NSData *pngData = UIImagePNGRepresentation((UIImage *)result);
                        if (pngData && pngData.length > 0) return pngData;
                    }
                }
            }
        } @catch (NSException *e) {}
    }
    
    // === 策略3：从正在显示的UIImageView中直接抓取 ===
    @try {
        UIView *emoticonView = nil;
        if ([cellView respondsToSelector:@selector(m_emoticonView)]) {
            emoticonView = [cellView performSelector:@selector(m_emoticonView)];
        }
        UIView *searchRoot = emoticonView ?: cellView;
        UIImageView *imageView = jj_findImageViewInView(searchRoot);
        jj_dbg([NSString stringWithFormat:@"[表情策略3] imageView=%@ class=%@", imageView ? @"有" : @"无",
            imageView ? NSStringFromClass([imageView class]) : @"-"]);
        
        if (imageView) {
            BOOL hasAnimatedImage = [imageView respondsToSelector:@selector(animatedImage)];
            BOOL hasAnimatedData = [imageView respondsToSelector:@selector(animatedImageData)];
            jj_dbg([NSString stringWithFormat:@"[表情策略3] animatedImage=%d animatedImageData=%d", hasAnimatedImage, hasAnimatedData]);
            
            @try {
                if (hasAnimatedImage) {
                    id animatedImage = [imageView performSelector:@selector(animatedImage)];
                    jj_dbg([NSString stringWithFormat:@"[表情策略3] animatedImage obj=%@ class=%@",
                        animatedImage ? @"有" : @"nil", animatedImage ? NSStringFromClass([animatedImage class]) : @"-"]);
                    if (animatedImage && [animatedImage respondsToSelector:@selector(animatedImageData)]) {
                        NSData *gifData = [animatedImage performSelector:@selector(animatedImageData)];
                        if (gifData && [gifData isKindOfClass:[NSData class]] && gifData.length > 0 && jj_isGIFData(gifData)) {
                            jj_dbg([NSString stringWithFormat:@"[表情策略3] ✅ GIF from animatedImage %lu bytes", (unsigned long)gifData.length]);
                            return gifData;
                        }
                    }
                }
            } @catch (NSException *e) {}
            
            @try {
                if (hasAnimatedData) {
                    NSData *gifData = [imageView performSelector:@selector(animatedImageData)];
                    if (gifData && [gifData isKindOfClass:[NSData class]] && gifData.length > 0 && jj_isGIFData(gifData)) {
                        jj_dbg([NSString stringWithFormat:@"[表情策略3] ✅ GIF from imageView %lu bytes", (unsigned long)gifData.length]);
                        return gifData;
                    }
                }
            } @catch (NSException *e) {}
            
            @try {
                UIImage *img = imageView.image;
                BOOL imgHasAnimData = [img respondsToSelector:@selector(animatedImageData)];
                NSUInteger imgCount = img.images ? img.images.count : 0;
                jj_dbg([NSString stringWithFormat:@"[表情策略3] image=%@ animData=%d frames=%lu",
                    img ? @"有" : @"nil", imgHasAnimData, (unsigned long)imgCount]);
                if (img && imgHasAnimData) {
                    NSData *gifData = [img performSelector:@selector(animatedImageData)];
                    if (gifData && [gifData isKindOfClass:[NSData class]] && gifData.length > 0 && jj_isGIFData(gifData)) {
                        return gifData;
                    }
                }
            } @catch (NSException *e) {}
            
            // 静态图片
            if (imageView.image) {
                NSData *pngData = UIImagePNGRepresentation(imageView.image);
                jj_dbg([NSString stringWithFormat:@"[表情策略3] 回退静态图 %lu bytes", (unsigned long)pngData.length]);
                if (pngData && pngData.length > 0) return pngData;
            }
        }
    } @catch (NSException *e) {}
    
    // === 策略4：通过文件路径读取 ===
    @try {
        NSString *imgPath = msgWrap.m_nsImgPath;
        NSString *thumbPath = msgWrap.m_nsThumbImgPath;
        jj_dbg([NSString stringWithFormat:@"[表情策略4] imgPath=%@ thumbPath=%@", imgPath ?: @"空", thumbPath ?: @"空"]);
        if (imgPath && imgPath.length > 0) {
            NSData *fileData = [NSData dataWithContentsOfFile:imgPath];
            if (fileData && fileData.length > 0) {
                jj_dbg([NSString stringWithFormat:@"[表情策略4] ✅ imgPath %lu bytes isGIF=%d", (unsigned long)fileData.length, jj_isGIFData(fileData)]);
                return fileData;
            }
        }
    } @catch (NSException *e) {}
    @try {
        NSString *thumbPath = msgWrap.m_nsThumbImgPath;
        if (thumbPath && thumbPath.length > 0) {
            NSData *fileData = [NSData dataWithContentsOfFile:thumbPath];
            if (fileData && fileData.length > 0) return fileData;
        }
    } @catch (NSException *e) {}
    
    // === 策略5：通过MD5在文件系统中搜索 ===
    if (md5 && md5.length > 0) {
        NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        jj_dbg([NSString stringWithFormat:@"[表情策略5] docPath=%@ cachePath=%@", docPath, cachePath]);
        NSArray *searchPaths = @[
            [docPath stringByAppendingPathComponent:[NSString stringWithFormat:@"../tmp/emoticonTmp/%@", md5]],
            [docPath stringByAppendingPathComponent:[NSString stringWithFormat:@"../tmp/emoticonTmp/%@.gif", md5]],
            [docPath stringByAppendingPathComponent:[NSString stringWithFormat:@"Emoticon/%@", md5]],
            [docPath stringByAppendingPathComponent:[NSString stringWithFormat:@"Emoticon/%@.gif", md5]],
            [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Emoticon/%@", md5]],
            [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Emoticon/%@.gif", md5]],
            [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"emoticonTmp/%@", md5]],
            [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"emoticonTmp/%@.gif", md5]],
        ];
        for (NSString *path in searchPaths) {
            @try {
                BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
                if (exists) {
                    NSData *fileData = [NSData dataWithContentsOfFile:path];
                    jj_dbg([NSString stringWithFormat:@"[表情策略5] ✅ 找到文件 %@ %lu bytes", [path lastPathComponent], (unsigned long)fileData.length]);
                    if (fileData && fileData.length > 0) return fileData;
                }
            } @catch (NSException *e) {}
        }
        jj_dbg(@"[表情策略5] 所有路径都未找到文件");
    }
    
    jj_dbg(@"[表情] 所有策略均未获取到数据");
    return nil;
}

// 缩放静态图片（PNG/JPEG）
static NSData *jj_scaleStaticImage(NSData *imageData, CGFloat scaleFactor) {
    if (!imageData) return nil;
    UIImage *image = [UIImage imageWithData:imageData];
    if (!image) return nil;
    
    CGSize newSize = CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor);
    if (newSize.width < 10) newSize.width = 10;
    if (newSize.height < 10) newSize.height = 10;
    
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (!scaledImage) return nil;
    
    // 检测原始格式，优先保持PNG
    const unsigned char *bytes = (const unsigned char *)imageData.bytes;
    BOOL isPNG = (imageData.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 &&
                  bytes[2] == 0x4E && bytes[3] == 0x47);
    
    if (isPNG) {
        return UIImagePNGRepresentation(scaledImage);
    } else {
        return UIImageJPEGRepresentation(scaledImage, 0.9);
    }
}

// 缩放GIF动图（逐帧缩放）
static NSData *jj_scaleGIFImage(NSData *gifData, CGFloat scaleFactor) {
    if (!gifData) return nil;
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)gifData, NULL);
    if (!source) return nil;
    
    size_t frameCount = CGImageSourceGetCount(source);
    if (frameCount == 0) { CFRelease(source); return nil; }
    
    NSMutableData *resultData = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)resultData, kJJUTTypeGIF, frameCount, NULL);
    if (!destination) { CFRelease(source); return nil; }
    
    // 复制GIF全局属性
    NSDictionary *gifProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(source, NULL);
    if (gifProperties) {
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);
    }
    
    for (size_t i = 0; i < frameCount; i++) {
        CGImageRef frameImage = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!frameImage) continue;
        
        // 计算新尺寸
        size_t origW = CGImageGetWidth(frameImage);
        size_t origH = CGImageGetHeight(frameImage);
        size_t newW = (size_t)(origW * scaleFactor);
        size_t newH = (size_t)(origH * scaleFactor);
        if (newW < 10) newW = 10;
        if (newH < 10) newH = 10;
        
        // 缩放帧
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, newW, newH, 8, newW * 4,
                                                  colorSpace, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorSpace);
        
        if (ctx) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            CGContextDrawImage(ctx, CGRectMake(0, 0, newW, newH), frameImage);
            CGImageRef scaledFrame = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            
            if (scaledFrame) {
                // 复制帧属性（包含延迟时间等）
                NSDictionary *frameProps = (__bridge_transfer NSDictionary *)
                    CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
                if (frameProps) {
                    CGImageDestinationAddImage(destination, scaledFrame, (__bridge CFDictionaryRef)frameProps);
                } else {
                    CGImageDestinationAddImage(destination, scaledFrame, NULL);
                }
                CGImageRelease(scaledFrame);
            }
        }
        CGImageRelease(frameImage);
    }
    
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CFRelease(source);
    
    return success ? resultData : nil;
}

// 统一发送缩放后的表情数据（GIF或静态图均走此路径）
// 核心策略：不复用原始MD5，强制微信将缩放后的数据作为全新表情处理
static void jj_sendScaledEmoticonData(NSData *scaledData, NSString *toUserName, BOOL isGIF) {
    if (!scaledData || scaledData.length == 0 || !toUserName) return;
    
    CMessageMgr *msgMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CMessageMgr")];
    if (!msgMgr) return;
    
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    NSString *selfUserName = [[contactMgr getSelfContact] m_nsUsrName];
    
    // 方式1：通过CEmoticonMgr创建消息（推荐，微信会自动处理上传和缓存）
    BOOL sent = NO;
    Class emoticonMgrClass = objc_getClass("CEmoticonMgr");
    if (emoticonMgrClass && [emoticonMgrClass respondsToSelector:@selector(emoticonMsgForImageData:errorMsg:)]) {
        NSString *errorMsg = nil;
        CMessageWrap *newMsgWrap = [emoticonMgrClass emoticonMsgForImageData:scaledData errorMsg:&errorMsg];
        if (newMsgWrap) {
            newMsgWrap.m_nsToUsr = toUserName;
            newMsgWrap.m_nsFromUsr = selfUserName;
            // 不设置m_nsEmoticonMD5，让微信根据新数据重新计算
            [msgMgr AddEmoticonMsg:toUserName MsgWrap:newMsgWrap];
            sent = YES;
        }
    }
    
    // 方式2：手动构建消息（兜底）
    if (!sent) {
        CMessageWrap *newMsgWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:47];
        newMsgWrap.m_nsFromUsr = selfUserName;
        newMsgWrap.m_nsToUsr = toUserName;
        newMsgWrap.m_uiMessageType = 47;
        newMsgWrap.m_uiStatus = 1;
        newMsgWrap.m_dtEmoticonData = scaledData;
        // 不设置m_nsEmoticonMD5，避免微信用缓存覆盖
        newMsgWrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
        newMsgWrap.m_uiMesLocalID = newMsgWrap.m_uiCreateTime;
        [msgMgr AddEmoticonMsg:toUserName MsgWrap:newMsgWrap];
    }
}

// 缩放并发送表情包到当前聊天
// 统一策略：从缓存文件读取 -> 像素级缩放 -> 发送 -> 删除缓存
static void jj_scaleAndSendEmoticon(CGFloat scaleFactor, UIView *sourceView) {
    NSString *toUserName = [jj_currentChatUserName copy];
    CMessageWrap *origMsgWrap = jj_currentEmoticonMsgWrap;
    
    if (!toUserName || toUserName.length == 0 || !origMsgWrap) {
        jj_deleteCachedEmoticon();
        return;
    }
    
    @try {
        // 从缓存文件读取之前抓取的表情数据
        NSData *origData = jj_readCachedEmoticonData();
        if (!origData || origData.length == 0) {
            jj_deleteCachedEmoticon();
            return;
        }
        
        // 用实际数据判断是否GIF
        BOOL isGIF = jj_isGIFData(origData);
        if (!isGIF) {
            // 再用ImageIO检测多帧
            CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)origData, NULL);
            if (src) {
                if (CGImageSourceGetCount(src) > 1) isGIF = YES;
                CFRelease(src);
            }
        }
        
        NSData *scaledData = nil;
        
        if (isGIF) {
            // GIF：逐帧缩放，保留动画
            scaledData = jj_scaleGIFImage(origData, scaleFactor);
            // 如果GIF缩放失败，降级为静态图
            if (!scaledData || scaledData.length == 0) {
                scaledData = jj_scaleStaticImage(origData, scaleFactor);
            }
        } else {
            // 静态图：直接像素缩放
            scaledData = jj_scaleStaticImage(origData, scaleFactor);
        }
        
        // 发送缩放后的数据
        jj_sendScaledEmoticonData(scaledData, toUserName, isGIF);
        
    } @catch (NSException *exception) {
        // 静默处理
    }
    
    // 删除缓存文件
    jj_deleteCachedEmoticon();
    
    // 清理全局状态
    jj_currentEmoticonMsgWrap = nil; jj_currentEmoticonImage = nil;
    jj_currentChatUserName = nil; jj_currentEmoticonData = nil; jj_currentIsGIF = NO;
}

// 保存sourceView的全局变量
static UIView *jj_currentSourceView = nil;

// 显示缩放选择菜单
static void jj_showScaleActionSheet(void) {
    CMessageWrap *msgWrap = jj_currentEmoticonMsgWrap;
    NSString *chatUserName = jj_currentChatUserName;
    if (!msgWrap || !chatUserName) return;
    
    // 从XML中解析原始尺寸
    NSString *content = msgWrap.m_nsContent;
    unsigned int origWidth = 0, origHeight = 0;
    
    if (content) {
        NSRegularExpression *widthRegex = [NSRegularExpression regularExpressionWithPattern:@"width\\s*=\\s*\"(\\d+)\"" options:0 error:nil];
        NSTextCheckingResult *wm = [widthRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
        if (wm && wm.numberOfRanges > 1) origWidth = [[content substringWithRange:[wm rangeAtIndex:1]] intValue];
        
        NSRegularExpression *heightRegex = [NSRegularExpression regularExpressionWithPattern:@"height\\s*=\\s*\"(\\d+)\"" options:0 error:nil];
        NSTextCheckingResult *hm = [heightRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
        if (hm && hm.numberOfRanges > 1) origHeight = [[content substringWithRange:[hm rangeAtIndex:1]] intValue];
    }
    
    // 从缓存文件读取数据判断类型
    NSData *cachedData = jj_readCachedEmoticonData();
    BOOL isGIF = NO;
    BOOL hasRealGIFData = NO;
    
    if (cachedData && cachedData.length > 0) {
        isGIF = jj_isGIFData(cachedData);
        if (!isGIF) {
            // 用ImageIO检测多帧
            CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)cachedData, NULL);
            if (src) {
                if (CGImageSourceGetCount(src) > 1) isGIF = YES;
                CFRelease(src);
            }
        }
        hasRealGIFData = isGIF;
        
        // 如果缓存数据不是GIF，再看XML判断原始类型
        if (!isGIF) {
            isGIF = jj_isEmoticonGIF(msgWrap, cachedData);
        }
    } else {
        // 缓存失败，仅从XML判断
        isGIF = jj_isEmoticonGIF(msgWrap, nil);
    }
    
    // 用缓存数据获取实际像素尺寸（比XML更准确）
    unsigned int realWidth = 0, realHeight = 0;
    if (cachedData && cachedData.length > 0) {
        CGImageSourceRef imgSrc = CGImageSourceCreateWithData((__bridge CFDataRef)cachedData, NULL);
        if (imgSrc) {
            CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(imgSrc, 0, NULL);
            if (props) {
                CFNumberRef w = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
                CFNumberRef h = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
                if (w) CFNumberGetValue(w, kCFNumberIntType, &realWidth);
                if (h) CFNumberGetValue(h, kCFNumberIntType, &realHeight);
                CFRelease(props);
            }
            CFRelease(imgSrc);
        }
    }
    // 优先用实际像素尺寸，回退到XML尺寸
    if (realWidth > 0 && realHeight > 0) {
        origWidth = realWidth;
        origHeight = realHeight;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        
        NSString *typeStr;
        if (isGIF && hasRealGIFData) {
            typeStr = @"GIF动图（可保留动画）";
        } else if (isGIF) {
            typeStr = @"GIF动图（仅获取到静态帧）";
        } else {
            typeStr = @"静态图";
        }
        
        NSString *cacheStatus;
        if (cachedData && cachedData.length > 0) {
            // 显示缓存文件大小
            float sizeKB = cachedData.length / 1024.0;
            if (sizeKB > 1024) {
                cacheStatus = [NSString stringWithFormat:@"[已缓存 %.1fMB]", sizeKB / 1024.0];
            } else {
                cacheStatus = [NSString stringWithFormat:@"[已缓存 %.0fKB]", sizeKB];
            }
        } else {
            cacheStatus = @"[缓存失败]";
        }
        NSString *msg;
        if (origWidth > 0 && origHeight > 0) {
            msg = [NSString stringWithFormat:@"类型：%@\n原始尺寸：%u x %u\n%@\n选择后将直接发送到当前聊天", typeStr, origWidth, origHeight, cacheStatus];
        } else {
            msg = [NSString stringWithFormat:@"类型：%@\n%@\n选择后将直接发送到当前聊天", typeStr, cacheStatus];
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"📐 调整表情大小"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        
        UIView *sv = jj_currentSourceView;
        
        [alert addAction:[UIAlertAction actionWithTitle:@"🔍 放大 3.0x" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { jj_scaleAndSendEmoticon(3.0, sv); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"🔍 放大 2.0x" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { jj_scaleAndSendEmoticon(2.0, sv); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"🔍 放大 1.5x" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { jj_scaleAndSendEmoticon(1.5, sv); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"🔎 缩小 0.75x" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { jj_scaleAndSendEmoticon(0.75, sv); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"🔎 缩小 0.5x" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { jj_scaleAndSendEmoticon(0.5, sv); }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"✏️ 自定义倍数" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"自定义缩放倍数"
                                                                               message:@"请输入倍数（0.1 ~ 5.0）"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.placeholder = @"1.5"; tf.keyboardType = UIKeyboardTypeDecimalPad; tf.text = @"1.5";
            }];
            [inputAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *aa) {
                jj_deleteCachedEmoticon();
            }]];
            [inputAlert addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *aa) {
                CGFloat factor = [inputAlert.textFields.firstObject.text floatValue];
                if (factor < 0.1) factor = 0.1; if (factor > 5.0) factor = 5.0;
                jj_scaleAndSendEmoticon(factor, sv);
            }]];
            UIViewController *top2 = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (top2.presentedViewController) top2 = top2.presentedViewController;
            [top2 presentViewController:inputAlert animated:YES completion:nil];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
            // 取消时也要删除缓存文件
            jj_deleteCachedEmoticon();
            jj_currentEmoticonMsgWrap = nil; jj_currentEmoticonImage = nil;
            jj_currentChatUserName = nil; jj_currentEmoticonData = nil;
            jj_currentIsGIF = NO; jj_currentSourceView = nil;
        }]];
        
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 1, 1);
        }
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

// Hook表情消息Cell - 通过filteredMenuItems添加"调整大小"菜单项
%hook EmoticonMessageCellView

- (id)filteredMenuItems:(id)items {
    id result = %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled) return result;
    if (!manager.emoticonScaleEnabled) return result;
    if (![result isKindOfClass:[NSArray class]]) return result;
    
    NSMutableArray *newItems = [NSMutableArray arrayWithArray:result];
    Class MMMenuItemClass = objc_getClass("MMMenuItem");
    if (MMMenuItemClass) {
        MMMenuItem *scaleItem = nil;
        // 使用svgName版本（8.0.66支持）
        @try {
            scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" svgName:@"icons_outlined_sticker" target:self action:@selector(jj_onEmoticonResize)];
        } @catch (NSException *e) {}
        // 备用：纯文字版本
        if (!scaleItem) {
            @try {
                scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" target:self action:@selector(jj_onEmoticonResize)];
            } @catch (NSException *e) {}
        }
        if (scaleItem) [newItems addObject:scaleItem];
    }
    return newItems;
}

%new
- (void)jj_onEmoticonResize {
    @try {
        jj_dbg(@"[表情] 点击大大小小");
        
        // 通过getMsgCmessageWrap获取CMessageWrap
        CMessageWrap *msgWrap = nil;
        if ([self respondsToSelector:@selector(getMsgCmessageWrap)]) {
            msgWrap = [self performSelector:@selector(getMsgCmessageWrap)];
        }
        // 备用：通过viewModel获取
        if (!msgWrap) {
            id vm = nil;
            if ([self respondsToSelector:@selector(viewModel)]) vm = [self performSelector:@selector(viewModel)];
            if (vm && [vm respondsToSelector:@selector(messageWrap)]) msgWrap = [vm performSelector:@selector(messageWrap)];
        }
        
        jj_dbg([NSString stringWithFormat:@"[表情] msgWrap=%@ content=%@", msgWrap ? @"有" : @"无", msgWrap.m_nsContent.length > 30 ? [msgWrap.m_nsContent substringToIndex:30] : msgWrap.m_nsContent]);
        
        if (!msgWrap || !msgWrap.m_nsContent || msgWrap.m_nsContent.length == 0) return;
        
        // 保存全局状态
        jj_currentEmoticonMsgWrap = msgWrap;
        jj_currentChatUserName = jj_getChatUserNameFromResponderChain(self);
        jj_currentSourceView = self;
        jj_currentEmoticonImage = nil;
        jj_currentEmoticonData = nil;
        jj_currentIsGIF = NO;
        
        jj_dbg([NSString stringWithFormat:@"[表情] chatUser=%@ md5=%@", jj_currentChatUserName ?: @"空", msgWrap.m_nsEmoticonMD5 ?: @"空"]);
        
        // 立即从视图中抓取表情数据并缓存到临时文件
        jj_deleteCachedEmoticon();
        NSData *capturedData = jj_captureEmoticonFromView(self, msgWrap);
        jj_dbg([NSString stringWithFormat:@"[表情] 抓取数据=%@ bytes", capturedData ? @(capturedData.length) : @"nil"]);
        if (capturedData && capturedData.length > 0) {
            jj_cacheEmoticonData(capturedData);
        }
        
        // 关闭当前菜单
        MMMenuController *menuCtrl = [objc_getClass("MMMenuController") sharedMenuController];
        if (menuCtrl) [menuCtrl setMenuVisible:NO animated:YES];
        
        // 延迟显示缩放选择菜单（等菜单关闭动画完成）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_showScaleActionSheet();
        });
    } @catch (NSException *exception) {
        jj_dbg([NSString stringWithFormat:@"[表情] ❌ 异常=%@", exception.reason]);
    }
}

%end

#pragma mark - 界面优化：隐藏搜索页语音按钮

%hook FTSFloatingVoiceInputView

- (void)didMoveToSuperview {
    %orig;
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.enabled && manager.hideVoiceSearchButton) {
        self.hidden = YES;
    }
}

- (void)didMoveToWindow {
    %orig;
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.enabled && manager.hideVoiceSearchButton) {
        self.hidden = YES;
    }
}

- (void)setHidden:(BOOL)hidden {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.enabled && manager.hideVoiceSearchButton) {
        %orig(YES);
    } else {
        %orig;
    }
}

%end


#pragma mark - 界面优化：隐藏朋友圈"上次分组"标签

// 检查当前视图是否在发布朋友圈相关的VC中
static BOOL jj_isInMomentsVC(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        NSString *className = NSStringFromClass([responder class]);
        if ([className isEqualToString:@"WCNewCommitViewController"] ||
            [className isEqualToString:@"WCForwardViewController"]) {
            return YES;
        }
        responder = [responder nextResponder];
    }
    return NO;
}

// 递归查找并隐藏包含"上次分组"的UILabel
static BOOL jj_hideLastGroupLabelInView(UIView *view) {
    if (!view) return NO;
    
    BOOL found = NO;
    
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        NSString *text = label.text;
        if (text && [text hasPrefix:@"上次分组"]) {
            label.hidden = YES;
            label.alpha = 0;
            label.text = @"";
            return YES;
        }
    }
    
    for (UIView *subview in view.subviews) {
        if (jj_hideLastGroupLabelInView(subview)) {
            found = YES;
        }
    }
    
    return found;
}

%hook MMTableViewCell

- (void)layoutSubviews {
    %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.hideLastGroupLabel) return;
    
    if (!jj_isInMomentsVC((UIView *)self)) return;
    
    if (jj_hideLastGroupLabelInView((UIView *)self)) {
        self.hidden = YES;
        self.clipsToBounds = YES;
    }
}

- (void)didMoveToWindow {
    %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.hideLastGroupLabel) return;
    
    if (!self.window) return;
    if (!jj_isInMomentsVC((UIView *)self)) return;
    
    if (jj_hideLastGroupLabelInView((UIView *)self)) {
        self.hidden = YES;
        self.clipsToBounds = YES;
    }
}

%end

#pragma mark - 小程序激励广告跳过/加速

static CGFloat jj_adTimerSpeedMultiplier = 1.0;
static BOOL jj_adSpeedActive = NO;
static NSInteger jj_adToolbarTag = 88990011;
static JJPassthroughWindow *jj_adToolbarWindow = nil;

static void jj_removeAdToolbar(UIViewController *vc) {
    jj_adToolbarWindow.hidden = YES;
    jj_adToolbarWindow = nil;
    jj_adSpeedActive = NO;
    jj_adTimerSpeedMultiplier = 1.0;
}

// 递归查找包含指定文本的MMUILabel
static UILabel *jj_findLabelWithText(UIView *view, NSString *text) {
    if (!view) return nil;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text && [label.text isEqualToString:text]) return label;
    }
    for (UIView *subview in view.subviews) {
        // 跳过工具栏本身
        if (subview.tag == jj_adToolbarTag) continue;
        UILabel *found = jj_findLabelWithText(subview, text);
        if (found) return found;
    }
    return nil;
}

// 模拟点击"关闭"按钮：从label向上遍历找到可点击的父视图并触发
static void jj_triggerCloseAction(UILabel *closeLabel) {
    if (!closeLabel) return;
    UIView *target = closeLabel.superview;
    while (target) {
        // 检查UIControl
        if ([target isKindOfClass:[UIControl class]]) {
            [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
            return;
        }
        // 检查手势识别器
        for (UIGestureRecognizer *gr in target.gestureRecognizers) {
            if ([gr isKindOfClass:[UITapGestureRecognizer class]] && gr.enabled) {
                @try {
                    NSArray *grTargets = [gr valueForKey:@"_targets"];
                    if ([grTargets isKindOfClass:[NSArray class]] && grTargets.count > 0) {
                        id targetActionPair = [grTargets firstObject];
                        id actionTarget = [targetActionPair valueForKey:@"_target"];
                        if (actionTarget) {
                            // 使用ObjC Runtime安全读取_action (SEL类型，KVC无法正确包装)
                            Ivar actionIvar = class_getInstanceVariable(object_getClass(targetActionPair), "_action");
                            if (actionIvar) {
                                ptrdiff_t offset = ivar_getOffset(actionIvar);
                                SEL action = *(SEL *)((uint8_t *)(__bridge void *)targetActionPair + offset);
                                if (action) {
                                    ((void (*)(id, SEL, id))objc_msgSend)(actionTarget, action, gr);
                                    return;
                                }
                            }
                        }
                    }
                } @catch (NSException *e) {}
            }
        }
        target = target.superview;
    }
}

static void jj_addAdToolbar(WAWebViewController *vc) {
    if (jj_adToolbarWindow) return;
    
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat btnW = 60, btnH = 36, spacing = 8, totalW = btnW * 3 + spacing * 2;
    CGFloat startX = (screenW - totalW) / 2.0;
    CGFloat topY = 44;
    
    // 使用独立Window承载工具栏，确保不被广告overlay遮挡
    jj_adToolbarWindow = [[JJPassthroughWindow alloc] initWithFrame:CGRectMake(0, 0, screenW, screenH)];
    jj_adToolbarWindow.windowLevel = 10000002;
    jj_adToolbarWindow.backgroundColor = [UIColor clearColor];
    jj_adToolbarWindow.userInteractionEnabled = YES;
    
    UIView *toolbar = [[UIView alloc] initWithFrame:CGRectMake(startX - 12, topY, totalW + 24, btnH + 16)];
    toolbar.tag = jj_adToolbarTag;
    toolbar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    toolbar.layer.cornerRadius = 12;
    toolbar.layer.masksToBounds = YES;
    
    NSArray *titles = @[@"5x\u52a0\u901f", @"10x\u52a0\u901f", @"\u8df3\u8fc7\u5e7f\u544a"];
    NSArray *colors = @[
        [UIColor systemOrangeColor],
        [UIColor systemRedColor],
        [UIColor systemGreenColor]
    ];
    
    for (int i = 0; i < 3; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(12 + i * (btnW + spacing), 8, btnW, btnH);
        [btn setTitle:titles[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        btn.backgroundColor = colors[i];
        btn.layer.cornerRadius = 8;
        btn.tag = 9900 + i;
        [btn addTarget:vc action:@selector(jj_adSpeedButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [toolbar addSubview:btn];
    }
    
    [jj_adToolbarWindow addSubview:toolbar];
    jj_adToolbarWindow.hidden = NO;
}

// 递归查找包含指定子串的Label
static UILabel *jj_findLabelContaining(UIView *view, NSString *substring) {
    if (!view) return nil;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text && [label.text containsString:substring]) return label;
    }
    for (UIView *subview in view.subviews) {
        if (subview.tag == jj_adToolbarTag) continue;
        UILabel *found = jj_findLabelContaining(subview, substring);
        if (found) return found;
    }
    return nil;
}

%hook WAWebViewController

- (void)viewDidLayoutSubviews {
    %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.adSkipEnabled) return;
    
    // 节流：每0.5秒检测一次，避免频繁递归搜索
    static NSTimeInterval jj_lastAdCheckTime = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - jj_lastAdCheckTime < 0.5) return;
    jj_lastAdCheckTime = now;
    
    // 检测广告倒计时标签是否存在（"X 秒后可获得奖励"）
    UILabel *adLabel = jj_findLabelContaining(self.view, @"\u79d2\u540e\u53ef\u83b7\u5f97\u5956\u52b1");
    if (adLabel && !jj_adToolbarWindow) {
        jj_dbg([NSString stringWithFormat:@"[广告] 检测到倒计时: %@", adLabel.text]);
        jj_addAdToolbar(self);
    }
    
    // 广告自然完成时：自动点击关闭按钮并移除工具栏
    UILabel *doneLabel = jj_findLabelContaining(self.view, @"\u5df2\u83b7\u5f97\u5956\u52b1");
    if (!doneLabel) doneLabel = jj_findLabelContaining(self.view, @"\u5df2\u5b8c\u6210");
    if (!doneLabel) doneLabel = jj_findLabelContaining(self.view, @"\u5df2\u9886\u53d6");
    if (doneLabel) {
        static NSTimeInterval jj_lastAutoCloseTime = 0;
        if (now - jj_lastAutoCloseTime > 2.0) {
            jj_lastAutoCloseTime = now;
            jj_dbg([NSString stringWithFormat:@"[广告] 检测到完成: %@，自动关闭", doneLabel.text]);
            
            // 找overlay并点击关闭按钮
            UIView *overlay = doneLabel.superview;
            while (overlay && overlay != self.view) {
                if (overlay.superview == self.view || overlay.subviews.count >= 3) break;
                overlay = overlay.superview;
            }
            if (overlay && overlay != self.view && overlay.subviews.count > 0) {
                UIView *closeArea = overlay.subviews[0];
                // 触发手势
                for (UIGestureRecognizer *g in closeArea.gestureRecognizers) {
                    if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                        [g setValue:@(UIGestureRecognizerStateEnded) forKey:@"state"];
                        jj_dbg(@"[广告] 自动触发关闭手势");
                    }
                }
                for (UIGestureRecognizer *g in overlay.gestureRecognizers) {
                    if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                        [g setValue:@(UIGestureRecognizerStateEnded) forKey:@"state"];
                    }
                }
                [closeArea accessibilityActivate];
            }
            
            // 同时发送JSBridge事件
            @try {
                SEL bothSel = @selector(sendEventToJSBridgeAndService:Param:);
                SEL bridgeSel = @selector(sendEventToJSBridge:Param:);
                NSDictionary *param = @{@"isEnded": @YES};
                if ([self respondsToSelector:bothSel]) {
                    ((void (*)(id, SEL, id, id))objc_msgSend)(self, bothSel, @"onRewardedVideoAdClose", param);
                } else if ([self respondsToSelector:bridgeSel]) {
                    ((void (*)(id, SEL, id, id))objc_msgSend)(self, bridgeSel, @"onRewardedVideoAdClose", param);
                }
            } @catch (NSException *e) {}
            
            if (jj_adToolbarWindow) jj_removeAdToolbar(self);
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    jj_removeAdToolbar(self);
}

%new
- (void)jj_adSpeedButtonTapped:(UIButton *)sender {
    NSInteger idx = sender.tag - 9900;
    
    if (idx == 2) {
        jj_dbg(@"[广告] 点击跳过广告");
        
        // 找到广告overlay
        UIView *overlay = nil;
        UILabel *adLabel = jj_findLabelContaining(self.view, @"\u79d2\u540e\u53ef\u83b7\u5f97\u5956\u52b1");
        if (!adLabel) adLabel = jj_findLabelContaining(self.view, @"\u5df2\u83b7\u5f97\u5956\u52b1");
        if (!adLabel) adLabel = jj_findLabelContaining(self.view, @"\u5df2\u5b8c\u6210");
        if (adLabel) {
            overlay = adLabel.superview;
            while (overlay && overlay != self.view) {
                if (overlay.superview == self.view || overlay.subviews.count >= 3) break;
                overlay = overlay.superview;
            }
        }
        
        // === 策略1(核心)：模拟点击关闭按钮区域（overlay第一个子视图） ===
        @try {
            if (overlay && overlay != self.view && overlay.subviews.count > 0) {
                UIView *closeArea = overlay.subviews[0];
                jj_dbg([NSString stringWithFormat:@"[广告] 策略1: 关闭区域 class=%@ frame=%.0f,%.0f,%.0f,%.0f",
                    NSStringFromClass([closeArea class]),
                    closeArea.frame.origin.x, closeArea.frame.origin.y,
                    closeArea.frame.size.width, closeArea.frame.size.height]);
                
                // dump手势识别器
                NSArray *gestures = closeArea.gestureRecognizers;
                jj_dbg([NSString stringWithFormat:@"[广告] 关闭区域手势数: %lu", (unsigned long)gestures.count]);
                for (UIGestureRecognizer *g in gestures) {
                    jj_dbg([NSString stringWithFormat:@"[广告] 手势: %@ target=%@",
                        NSStringFromClass([g class]),
                        [g valueForKey:@"_targets"]]);
                }
                // 也dump overlay自身的手势
                NSArray *overlayGestures = overlay.gestureRecognizers;
                jj_dbg([NSString stringWithFormat:@"[广告] overlay手势数: %lu", (unsigned long)overlayGestures.count]);
                for (UIGestureRecognizer *g in overlayGestures) {
                    jj_dbg([NSString stringWithFormat:@"[广告] overlay手势: %@ target=%@",
                        NSStringFromClass([g class]),
                        [g valueForKey:@"_targets"]]);
                }
                
                // 触发手势识别器
                for (UIGestureRecognizer *g in gestures) {
                    if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                        jj_dbg(@"[广告] 策略1: 触发tap手势");
                        // 通过设置state来触发
                        [g setValue:@(UIGestureRecognizerStateEnded) forKey:@"state"];
                    }
                }
                for (UIGestureRecognizer *g in overlayGestures) {
                    if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                        jj_dbg(@"[广告] 策略1: 触发overlay tap手势");
                        [g setValue:@(UIGestureRecognizerStateEnded) forKey:@"state"];
                    }
                }
                
                // 模拟触摸事件：在关闭按钮中心发送touch
                CGPoint center = CGPointMake(CGRectGetMidX(closeArea.frame), CGRectGetMidY(closeArea.frame));
                CGPoint screenPoint = [closeArea.superview convertPoint:center toView:nil];
                jj_dbg([NSString stringWithFormat:@"[广告] 策略1: 模拟点击 screen=(%.0f,%.0f)", screenPoint.x, screenPoint.y]);
                
                // 通过accessibilityActivate尝试
                [closeArea accessibilityActivate];
                
                // 通过hitTest找到响应者并发送touch
                UIView *hitView = [self.view hitTest:[self.view convertPoint:screenPoint fromView:nil] withEvent:nil];
                if (hitView) {
                    jj_dbg([NSString stringWithFormat:@"[广告] 策略1: hitTest命中 %@", NSStringFromClass([hitView class])]);
                    [hitView accessibilityActivate];
                }
            }
        } @catch (NSException *e) {
            jj_dbg([NSString stringWithFormat:@"[广告] 策略1异常: %@", e.reason]);
        }
        
        // === 策略2：通过JSBridge通知小程序广告已完成 ===
        @try {
            SEL bridgeSel = @selector(sendEventToJSBridge:Param:);
            SEL serviceSel = @selector(sendEventToService:Param:);
            SEL bothSel = @selector(sendEventToJSBridgeAndService:Param:);
            
            NSDictionary *rewardParam = @{@"isEnded": @YES, @"errCode": @0, @"errMsg": @"onClose:ok"};
            NSArray *eventNames = @[@"onRewardedVideoAdClose", @"onAdClose", @"rewardedVideoAdClose"];
            
            for (NSString *eventName in eventNames) {
                if ([self respondsToSelector:bothSel]) {
                    ((void (*)(id, SEL, id, id))objc_msgSend)(self, bothSel, eventName, rewardParam);
                } else {
                    if ([self respondsToSelector:bridgeSel])
                        ((void (*)(id, SEL, id, id))objc_msgSend)(self, bridgeSel, eventName, rewardParam);
                    if ([self respondsToSelector:serviceSel])
                        ((void (*)(id, SEL, id, id))objc_msgSend)(self, serviceSel, eventName, rewardParam);
                }
            }
            jj_dbg(@"[广告] 策略2: JSBridge事件已发送");
        } @catch (NSException *e) {}
        
        // === 策略3：调用onGameRewards ===
        @try {
            if ([self respondsToSelector:@selector(onGameRewards)]) {
                [self onGameRewards];
                jj_dbg(@"[广告] 策略3: onGameRewards已调用");
            }
        } @catch (NSException *e) {}
        
        // === 策略4：直接移除广告overlay ===
        @try {
            if (overlay && overlay != self.view) {
                [overlay removeFromSuperview];
                jj_dbg(@"[广告] 策略4: 已移除广告overlay");
            }
        } @catch (NSException *e) {}
        
        jj_removeAdToolbar(self);
        return;
    }
    
    // 加速按钮 (idx 0 = 5x, idx 1 = 10x)
    CGFloat speeds[] = {5.0, 10.0};
    jj_adTimerSpeedMultiplier = speeds[idx];
    jj_adSpeedActive = YES;
    jj_dbg([NSString stringWithFormat:@"[广告] 加速 %.0fx", speeds[idx]]);
    
    // 更新按钮高亮状态
    UIView *toolbar = [self.view viewWithTag:jj_adToolbarTag];
    if (toolbar) {
        for (int i = 0; i < 2; i++) {
            UIButton *btn = [toolbar viewWithTag:9900 + i];
            if (btn) {
                btn.alpha = (i == idx) ? 1.0 : 0.5;
                btn.transform = (i == idx) ? CGAffineTransformMakeScale(1.1, 1.1) : CGAffineTransformIdentity;
            }
        }
    }
}

%end

// Hook NSTimer 实现广告加速（仅在广告播放时生效）
%hook NSTimer

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)t selector:(SEL)s userInfo:(id)ui repeats:(BOOL)r {
    if (jj_adSpeedActive && jj_adTimerSpeedMultiplier > 1.0 && ti > 0) {
        ti = ti / jj_adTimerSpeedMultiplier;
    }
    return %orig(ti, t, s, ui, r);
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)t selector:(SEL)s userInfo:(id)ui repeats:(BOOL)r {
    if (jj_adSpeedActive && jj_adTimerSpeedMultiplier > 1.0 && ti > 0) {
        ti = ti / jj_adTimerSpeedMultiplier;
    }
    return %orig(ti, t, s, ui, r);
}

%end

// Hook CADisplayLink 实现广告加速（部分广告用CADisplayLink做倒计时）
%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *link = %orig;
    if (jj_adSpeedActive && jj_adTimerSpeedMultiplier > 1.0 && link) {
        // preferredFramesPerSecond设为更高值加速回调频率
        link.preferredFramesPerSecond = (NSInteger)(60 * jj_adTimerSpeedMultiplier);
    }
    return link;
}

%end
