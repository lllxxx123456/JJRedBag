#import "WeChatHeaders.h"
#import "JJRedBagManager.h"
#import "JJRedBagSettingsController.h"
#import "JJRedBagParam.h"
#import "JJDebugConsole.h"
#import <UserNotifications/UserNotifications.h>
#import <ImageIO/ImageIO.h>
#import <WebKit/WKWebView.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 调试器日志便捷宏：调试器关闭时零开销
#define JJ_LOG(tag, fmt, ...) do { \
    if ([JJDebugConsole isEnabled]) { \
        [[JJDebugConsole shared] logTag:(tag) format:(fmt), ##__VA_ARGS__]; \
    } \
} while (0)

// 反射工具：dump对象所有可读属性，用于调试器观察未知字段
static NSString *jj_dumpProperties(id obj) {
    if (!obj) return @"<nil>";
    NSMutableString *out = [NSMutableString string];
    Class cls = [obj class];
    int depth = 0;
    while (cls && cls != [NSObject class] && depth < 5) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *name = property_getName(props[i]);
            NSString *propName = [NSString stringWithUTF8String:name];
            id v = nil;
            @try { v = [obj valueForKey:propName]; } @catch (NSException *e) { continue; }
            if (v == nil) continue;
            NSString *desc;
            if ([v isKindOfClass:[NSString class]]) {
                NSUInteger len = [(NSString *)v length];
                desc = len > 80 ? [[(NSString *)v substringToIndex:77] stringByAppendingString:@"..."] : v;
            } else if ([v isKindOfClass:[NSNumber class]]) {
                desc = [(NSNumber *)v stringValue];
            } else if ([v isKindOfClass:[NSArray class]]) {
                desc = [NSString stringWithFormat:@"<%@ count=%lu>", NSStringFromClass([v class]), (unsigned long)[(NSArray *)v count]];
            } else if ([v isKindOfClass:[NSDictionary class]]) {
                desc = [NSString stringWithFormat:@"<%@ count=%lu>", NSStringFromClass([v class]), (unsigned long)[(NSDictionary *)v count]];
            } else if ([v isKindOfClass:[NSData class]]) {
                desc = [NSString stringWithFormat:@"<NSData %lu bytes>", (unsigned long)[(NSData *)v length]];
            } else {
                desc = [NSString stringWithFormat:@"<%@>", NSStringFromClass([v class])];
            }
            [out appendFormat:@"%@=%@; ", propName, desc];
        }
        if (props) free(props);
        cls = [cls superclass];
        if (cls == [UIResponder class] || cls == [UIView class] || cls == [UIViewController class]) break;
        depth++;
    }
    return out.length > 0 ? out : @"<no readable properties>";
}

// 反射工具：列出对象类所有 instance method 名（用于探测真实方法名）
static NSString *jj_dumpMethods(Class cls) {
    if (!cls) return @"<nil>";
    NSMutableString *out = [NSMutableString string];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        [out appendFormat:@"%@; ", NSStringFromSelector(sel)];
    }
    if (methods) free(methods);
    return out;
}

#define kJJUTTypeGIF CFSTR("com.compuserve.gif")

// 缓存WCPayLogicMgr实例（strong引用，微信服务为单例不会造成泄漏）
static id jj_cachedPayLogicMgr = nil;
static id jj_cachedServiceCenter = nil;

// 兼容多微信版本的服务中心获取
static id jj_getServiceCenter(void) {
    if (jj_cachedServiceCenter) return jj_cachedServiceCenter;
    
    typedef id (*JJMsgSend)(id, SEL);
    JJMsgSend msgSend = (JJMsgSend)objc_msgSend;
    
    // 策略1：新版微信通过 MMContext.currentContext 获取（它可能就持有 getService:）
    Class mmContextCls = objc_getClass("MMContext");
    if (mmContextCls && [mmContextCls respondsToSelector:@selector(currentContext)]) {
        @try {
            id ctx = msgSend((id)mmContextCls, @selector(currentContext));
            if (ctx && [ctx respondsToSelector:@selector(getService:)]) {
                jj_cachedServiceCenter = ctx;
                return ctx;
            }
        } @catch (NSException *e) {}
    }
    
    // 策略2：经典方式 MMServiceCenter.defaultCenter
    Class cls = objc_getClass("MMServiceCenter");
    if (!cls) cls = objc_getClass("WXServiceCenter");
    if (cls) {
        SEL selectors[] = {
            @selector(defaultCenter),
            @selector(sharedInstance),
            @selector(sharedCenter),
            @selector(center),
            @selector(shared)
        };
        for (int i = 0; i < sizeof(selectors)/sizeof(selectors[0]); i++) {
            if ([cls respondsToSelector:selectors[i]]) {
                @try {
                    id center = msgSend((id)cls, selectors[i]);
                    if (center && [center respondsToSelector:@selector(getService:)]) {
                        jj_cachedServiceCenter = center;
                        return center;
                    }
                } @catch (NSException *e) {}
            }
        }
        
        // 回退：运行时遍历类方法
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(object_getClass(cls), &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL sel = method_getName(methods[i]);
            if (method_getNumberOfArguments(methods[i]) == 2) {
                @try {
                    id result = msgSend((id)cls, sel);
                    if (result && [result respondsToSelector:@selector(getService:)]) {
                        jj_cachedServiceCenter = result;
                        free(methods);
                        return result;
                    }
                } @catch (NSException *e) {}
            }
        }
        if (methods) free(methods);
    }
    
    // 策略3：遍历MMContext的其他上下文方法
    if (mmContextCls) {
        SEL ctxSels[] = {
            @selector(activeUserContext),
            @selector(lastContext),
            @selector(rootContext)
        };
        for (int i = 0; i < sizeof(ctxSels)/sizeof(ctxSels[0]); i++) {
            if ([mmContextCls respondsToSelector:ctxSels[i]]) {
                @try {
                    id ctx = msgSend((id)mmContextCls, ctxSels[i]);
                    if (ctx && [ctx respondsToSelector:@selector(getService:)]) {
                        jj_cachedServiceCenter = ctx;
                        return ctx;
                    }
                } @catch (NSException *e) {}
            }
        }
    }
    
    return nil;
}

static id jj_getService(Class serviceClass) {
    id center = jj_getServiceCenter();
    if (!center || !serviceClass) return nil;
    if ([center respondsToSelector:@selector(getService:)]) {
        return [center getService:serviceClass];
    }
    return nil;
}

static unsigned int jj_generateSendMsgTime(void) {
    MMNewSessionMgr *sessionMgr = (MMNewSessionMgr *)jj_getService(objc_getClass("MMNewSessionMgr"));
    if (sessionMgr && [sessionMgr respondsToSelector:@selector(GenSendMsgTime)]) {
        return [sessionMgr GenSendMsgTime];
    }
    return (unsigned int)[[NSDate date] timeIntervalSince1970];
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
                                                                                version:@"1.1-1" 
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
        [self jj_processTransferMessage:msgWrap];
        return;
    }
    
    // 兜底：其他wxpay://消息也当红包处理
    if ([content rangeOfString:@"wxpay://"].location != NSNotFound) {
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
    CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
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
        return;
    }
    
    // 私聊红包判断
    if (!isGroup && !manager.grabPrivateEnabled) {
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
        CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
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
        WCRedEnvelopesLogicMgr *logicMgr = jj_getService(objc_getClass("WCRedEnvelopesLogicMgr"));
        if (logicMgr) {
            [logicMgr ReceiverQueryRedEnvelopesRequest:reqParams];
        }
    } @catch (NSException *exception) {
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
                    // property dump (no-op in release)
                }
            }
            free(props);
        } @catch (NSException *e) {}
    }
    
    // 直接执行自动收款（不延迟）
    @try {
        WCPayLogicMgr *payLogicMgr = (WCPayLogicMgr *)jj_cachedPayLogicMgr;
        if (!payLogicMgr) {
            @try {
                payLogicMgr = jj_getService(objc_getClass("WCPayLogicMgr"));
                if (payLogicMgr) jj_cachedPayLogicMgr = payLogicMgr;
            } @catch (NSException *e) {
            }
        }
        if (!payLogicMgr) { return; }
        
        WCPayConfirmTransferRequest *request = [[objc_getClass("WCPayConfirmTransferRequest") alloc] init];
        if (!request) { return; }
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
        
        // 更新累计金额
        [[JJRedBagManager sharedManager] setTotalReceiveAmount:[[JJRedBagManager sharedManager] totalReceiveAmount] + amountValue];
        [[JJRedBagManager sharedManager] saveSettings];
        
        JJRedBagManager *mgr = [JJRedBagManager sharedManager];
        
        // 自动回复（使用AddMsg:MsgWrap:发送文本消息）
        BOOL isGroupChat = [confirmParams[@"isGroup"] boolValue];
        if ((isGroupChat && mgr.receiveAutoReplyGroupEnabled) || (!isGroupChat && mgr.receiveAutoReplyPrivateEnabled)) {
            [self jj_sendReceiveAutoReply:confirmParams isGroup:isGroupChat];
        }
        
        // 发送通知（使用AddMsg:MsgWrap:）
        if (mgr.receiveNotificationEnabled && mgr.receiveNotificationChatId.length > 0) {
            [self jj_sendReceiveNotification:confirmParams amount:amountValue];
        }
        
        // 本地弹窗通知
        if (mgr.receiveLocalNotificationEnabled) {
            [self jj_sendReceiveLocalNotification:confirmParams amount:amountValue];
        }
    } @catch (NSException *e) {
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
        wrap.m_nsFromUsr = params[@"selfUser"];
        wrap.m_uiStatus = 1;
        wrap.m_uiCreateTime = jj_generateSendMsgTime();
        wrap.m_uiMesLocalID = wrap.m_uiCreateTime;
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
        wrap.m_nsFromUsr = params[@"selfUser"];
        wrap.m_uiStatus = 1;
        wrap.m_uiCreateTime = jj_generateSendMsgTime();
        wrap.m_uiMesLocalID = wrap.m_uiCreateTime;
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
    
    // 调试器自动显示（功能开启 + 设置为自动显示）
    if (manager.enabled && manager.debugConsoleEnabled && manager.debugConsoleAutoShow) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[JJDebugConsole shared] show];
            [[JJDebugConsole shared] logTag:@"信息" format:@"微信启动，调试器自动显示"];
        });
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
            if (!param) { return; }
            
            NSInteger receiveStatus = [responseDict[@"receiveStatus"] integerValue];
            NSInteger hbStatus = [responseDict[@"hbStatus"] integerValue];
            
            if (receiveStatus == 2) {
                if (param.sendId) [manager.pendingRedBags removeObjectForKey:param.sendId];
                return;
            }
            
            if (hbStatus == 4) {
                if (param.sendId) [manager.pendingRedBags removeObjectForKey:param.sendId];
                return;
            }
            
            if (!responseDict[@"timingIdentifier"]) { return; }
            
            param.timingIdentifier = responseDict[@"timingIdentifier"];
            NSTimeInterval delay = [manager getDelayTimeForChat:param.sessionUserName];
            
            if (delay > 0) {
                unsigned int delayMs = (unsigned int)(delay * 1000);
                JJReceiveRedBagOperation *operation = [[JJReceiveRedBagOperation alloc] initWithRedBagParam:param delay:delayMs];
                [[JJRedBagTaskManager sharedManager] addNormalTask:operation];
            } else {
                WCRedEnvelopesLogicMgr *logicMgr = jj_getService(objc_getClass("WCRedEnvelopesLogicMgr"));
                if (logicMgr) {
                    [logicMgr OpenRedEnvelopesRequest:[param toParams]];
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
            if (amount > 0) {
                long long totalAmount = [responseDict[@"totalAmount"] longLongValue];
                param.totalAmount = totalAmount;
                
                manager.totalAmount += amount;
                [manager saveSettings];
                
                
                JJRedBagParam *paramCopy = param;
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        [self jj_sendAutoReply:paramCopy];
                        [self jj_sendNotification:paramCopy amount:amount];
                        [self jj_sendLocalNotification:paramCopy amount:amount];
                    } @catch (NSException *exception) {
                    }
                });
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
    CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
    
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
+ (unsigned int)jj_generateSendMsgTime {
    MMNewSessionMgr *sessionMgr = jj_getService(objc_getClass("MMNewSessionMgr"));
    if (sessionMgr && [sessionMgr respondsToSelector:@selector(GenSendMsgTime)]) {
        return [sessionMgr GenSendMsgTime];
    }
    return (unsigned int)[[NSDate date] timeIntervalSince1970];
}

%new
- (void)jj_sendMessage:(NSString *)content toUser:(NSString *)toUser {
    if (!content || !toUser) return;
    
    CMessageWrap *msgWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
    if (!msgWrap) return;
    
    // 获取自己
    CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
    CContact *selfContact = [contactMgr getSelfContact];
    
    msgWrap.m_nsFromUsr = [selfContact m_nsUsrName];
    msgWrap.m_nsToUsr = toUser;
    msgWrap.m_nsContent = content;
    msgWrap.m_uiStatus = 1; // 1=Sending
    msgWrap.m_uiMessageType = 1;
    
    // 使用统一的发送时间生成函数
    msgWrap.m_uiCreateTime = jj_generateSendMsgTime();
    
    msgWrap.m_uiMesLocalID = (unsigned int)msgWrap.m_uiCreateTime;
    
    CMessageMgr *msgMgr = jj_getService(objc_getClass("CMessageMgr"));
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
static UIView *jj_currentSourceView = nil;

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

// 获取表情原始数据（通过多种方式尝试）
static NSData *jj_getEmoticonData(CMessageWrap *msgWrap) {
    if (!msgWrap) return nil;
    // 1. 直接从消息获取
    @try {
        NSData *data = msgWrap.m_dtEmoticonData;
        if (data && data.length > 0) return data;
    } @catch (NSException *e) {}
    // 2. 通过MD5从CEmoticonMgr获取
    NSString *md5 = msgWrap.m_nsEmoticonMD5;
    if (md5 && md5.length > 0) {
        @try {
            CEmoticonMgr *emoticonMgr = jj_getService(objc_getClass("CEmoticonMgr"));
            if (emoticonMgr && [emoticonMgr respondsToSelector:@selector(getEmoticonWrapByMd5:)]) {
                CEmoticonWrap *wrap = [emoticonMgr getEmoticonWrapByMd5:md5];
                if (wrap && wrap.m_imageData && wrap.m_imageData.length > 0) return wrap.m_imageData;
            }
        } @catch (NSException *e) {}
        // 3. 通过MD5搜索文件系统
        NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSArray *exts = @[@"", @".gif", @".png", @".jpg"];
        NSArray *dirs = @[
            [docPath stringByAppendingPathComponent:@"../tmp/emoticonTmp"],
            [cachePath stringByAppendingPathComponent:@"emoticonTmp"],
            [docPath stringByAppendingPathComponent:@"Emoticon"],
            [cachePath stringByAppendingPathComponent:@"Emoticon"],
        ];
        for (NSString *dir in dirs) {
            for (NSString *ext in exts) {
                NSString *path = [dir stringByAppendingPathComponent:[md5 stringByAppendingString:ext]];
                if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    NSData *d = [NSData dataWithContentsOfFile:path];
                    if (d && d.length > 0) return d;
                }
            }
        }
    }
    // 4. 通过文件路径属性
    @try {
        NSString *imgPath = msgWrap.m_nsImgPath;
        if (imgPath.length > 0) { NSData *d = [NSData dataWithContentsOfFile:imgPath]; if (d.length > 0) return d; }
        NSString *thumbPath = msgWrap.m_nsThumbImgPath;
        if (thumbPath.length > 0) { NSData *d = [NSData dataWithContentsOfFile:thumbPath]; if (d.length > 0) return d; }
    } @catch (NSException *e) {}
    // 5. 通过getEmoticonImageByMD5获取静态UIImage（最后手段）
    if (md5 && md5.length > 0) {
        @try {
            Class cls = objc_getClass("CEmoticonMgr");
            if ([cls respondsToSelector:@selector(getEmoticonImageByMD5:)]) {
                UIImage *img = [cls getEmoticonImageByMD5:md5];
                if (img) return UIImagePNGRepresentation(img);
            }
        } @catch (NSException *e) {}
    }
    return nil;
}

// 缩放静态图片
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
    const unsigned char *bytes = (const unsigned char *)imageData.bytes;
    BOOL isPNG = (imageData.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47);
    return isPNG ? UIImagePNGRepresentation(scaledImage) : UIImageJPEGRepresentation(scaledImage, 0.9);
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
    NSDictionary *gifProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(source, NULL);
    if (gifProperties) CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);
    for (size_t i = 0; i < frameCount; i++) {
        CGImageRef frameImage = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!frameImage) continue;
        size_t newW = (size_t)(CGImageGetWidth(frameImage) * scaleFactor);
        size_t newH = (size_t)(CGImageGetHeight(frameImage) * scaleFactor);
        if (newW < 10) newW = 10; if (newH < 10) newH = 10;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, newW, newH, 8, newW * 4, cs, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(cs);
        if (ctx) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            CGContextDrawImage(ctx, CGRectMake(0, 0, newW, newH), frameImage);
            CGImageRef scaledFrame = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            if (scaledFrame) {
                NSDictionary *frameProps = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
                CGImageDestinationAddImage(destination, scaledFrame, (__bridge CFDictionaryRef)frameProps);
                CGImageRelease(scaledFrame);
            }
        }
        CGImageRelease(frameImage);
    }
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination); CFRelease(source);
    return success ? resultData : nil;
}

// 缩放并发送表情包：获取原始数据 → 像素缩放 → 作为新表情发送
static void jj_scaleAndSendEmoticon(CGFloat scaleFactor, UIView *sourceView) {
    NSString *toUserName = [jj_currentChatUserName copy];
    CMessageWrap *origMsgWrap = jj_currentEmoticonMsgWrap;
    
    if (!toUserName || toUserName.length == 0 || !origMsgWrap) return;
    
    @try {
        CMessageMgr *msgMgr = jj_getService(objc_getClass("CMessageMgr"));
        if (!msgMgr) return;
        CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
        NSString *selfUserName = [[contactMgr getSelfContact] m_nsUsrName];
        
        // 获取原始表情数据
        NSData *origData = jj_getEmoticonData(origMsgWrap);
        if (!origData || origData.length == 0) return;
        
        // 判断是否GIF并缩放
        BOOL isGIF = jj_isGIFData(origData);
        if (!isGIF) {
            CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)origData, NULL);
            if (src) { if (CGImageSourceGetCount(src) > 1) isGIF = YES; CFRelease(src); }
        }
        
        NSData *scaledData = nil;
        if (isGIF) {
            scaledData = jj_scaleGIFImage(origData, scaleFactor);
            if (!scaledData || scaledData.length == 0) scaledData = jj_scaleStaticImage(origData, scaleFactor);
        } else {
            scaledData = jj_scaleStaticImage(origData, scaleFactor);
        }
        if (!scaledData || scaledData.length == 0) return;
        
        // 用emoticonMsgForImageData发送全新表情（不带原MD5，微信会重新处理）
        Class emoticonMgrClass = objc_getClass("CEmoticonMgr");
        BOOL sent = NO;
        if (emoticonMgrClass && [emoticonMgrClass respondsToSelector:@selector(emoticonMsgForImageData:errorMsg:)]) {
            NSString *errorMsg = nil;
            CMessageWrap *newMsgWrap = [emoticonMgrClass emoticonMsgForImageData:scaledData errorMsg:&errorMsg];
            if (newMsgWrap) {
                newMsgWrap.m_nsToUsr = toUserName;
                newMsgWrap.m_nsFromUsr = selfUserName;
                [msgMgr AddEmoticonMsg:toUserName MsgWrap:newMsgWrap];
                sent = YES;
            }
        }
        // 回退：手动构建
        if (!sent) {
            CMessageWrap *newMsgWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:47];
            newMsgWrap.m_nsFromUsr = selfUserName;
            newMsgWrap.m_nsToUsr = toUserName;
            newMsgWrap.m_uiStatus = 1;
            newMsgWrap.m_dtEmoticonData = scaledData;
            newMsgWrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
            [msgMgr AddEmoticonMsg:toUserName MsgWrap:newMsgWrap];
        }
    } @catch (NSException *exception) {}
    
    // 清理
    jj_currentEmoticonMsgWrap = nil;
    jj_currentChatUserName = nil;
    jj_currentSourceView = nil;
}

// 显示缩放选择菜单
static void jj_showScaleActionSheet(void) {
    CMessageWrap *msgWrap = jj_currentEmoticonMsgWrap;
    NSString *chatUserName = jj_currentChatUserName;
    if (!msgWrap || !chatUserName) return;
    
    // 从XML中解析原始尺寸
    NSString *content = msgWrap.m_nsContent;
    unsigned int origWidth = 0, origHeight = 0;
    
    if (content) {
        NSRegularExpression *wRegex = [NSRegularExpression regularExpressionWithPattern:@"cdnimgwidth=\"(\\d+)\"" options:0 error:nil];
        NSTextCheckingResult *wm = [wRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
        if (wm && wm.numberOfRanges > 1) origWidth = [[content substringWithRange:[wm rangeAtIndex:1]] intValue];
        
        NSRegularExpression *hRegex = [NSRegularExpression regularExpressionWithPattern:@"cdnimgheight=\"(\\d+)\"" options:0 error:nil];
        NSTextCheckingResult *hm = [hRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
        if (hm && hm.numberOfRanges > 1) origHeight = [[content substringWithRange:[hm rangeAtIndex:1]] intValue];
    }
    
    BOOL isGIF = jj_isEmoticonGIF(msgWrap, nil);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        
        NSString *msg;
        if (origWidth > 0 && origHeight > 0) {
            msg = [NSString stringWithFormat:@"%@\n原始尺寸：%u x %u\n选择后将直接发送到当前聊天", isGIF ? @"GIF动图" : @"静态表情", origWidth, origHeight];
        } else {
            msg = [NSString stringWithFormat:@"%@\n选择后将直接发送到当前聊天", isGIF ? @"GIF动图" : @"静态表情"];
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
            [inputAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
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
            jj_currentEmoticonMsgWrap = nil;
            jj_currentChatUserName = nil;
            jj_currentSourceView = nil;
        }]];
        
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 1, 1);
        }
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

static NSString *jj_plusOneUnsupportedReason(CMessageWrap *msgWrap) {
    if (!msgWrap) return @"不支持该消息类型";
    unsigned int msgType = msgWrap.m_uiMessageType;
    NSString *content = msgWrap.m_nsContent ?: @"";
    if (msgType == 50) return @"不支持+1 通话消息";
    if (msgType == 10000) return @"不支持+1 系统消息";
    if (msgType == 10002) return @"不支持+1 撤回消息";
    if (msgType == 49 && [content rangeOfString:@"wxpay://"].location != NSNotFound) return @"不支持+1 支付类消息";
    return nil;
}

static CMessageWrap *jj_clonePlusOneMessageWrap(CMessageWrap *sourceMsgWrap, NSString *fromUser, NSString *toUser) {
    if (!sourceMsgWrap || !toUser || toUser.length == 0) return nil;
    CMessageWrap *newWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:sourceMsgWrap.m_uiMessageType];
    if (!newWrap) return nil;
    
    NSSet *skipKeys = [NSSet setWithArray:@[@"m_nsFromUsr", @"m_nsToUsr", @"m_nsRealChatUsr", @"m_uiStatus", @"m_uiCreateTime", @"m_uiMesLocalID", @"m_n64MesSvrID"]];
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList([sourceMsgWrap class], &propertyCount);
    for (unsigned int i = 0; i < propertyCount; i++) {
        NSString *key = [NSString stringWithUTF8String:property_getName(properties[i])];
        if ([skipKeys containsObject:key]) continue;
        @try {
            id value = [sourceMsgWrap valueForKey:key];
            if (value && value != [NSNull null]) {
                [newWrap setValue:value forKey:key];
            }
        } @catch (NSException *e) {}
    }
    if (properties) free(properties);
    
    unsigned int sendTime = jj_generateSendMsgTime();
    newWrap.m_nsFromUsr = fromUser;
    newWrap.m_nsToUsr = toUser;
    newWrap.m_nsRealChatUsr = nil;
    newWrap.m_uiStatus = 1;
    newWrap.m_uiCreateTime = sendTime;
    newWrap.m_uiMesLocalID = sendTime;
    newWrap.m_n64MesSvrID = 0;
    return newWrap;
}

#pragma mark - 消息+1（复读机）

// 递归查找视图中的 UITableView（用于滚动到聊天底部）
static UITableView *jj_findTableViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITableView class]]) {
        return (UITableView *)view;
    }
    for (UIView *sub in view.subviews) {
        UITableView *found = jj_findTableViewInView(sub);
        if (found) return found;
    }
    return nil;
}

// +1菜单注入必须hook BaseMessageCellView（filteredMenuItems:定义在此类上）
// 如果hook子类CommonMessageCellView会绕过其他插件在BaseMessageCellView上的hook
// 注意：为了避免与 miyou.dylib 等其他插件的 +1 功能冲突，本 hook 遵守以下原则：
// 1. 总开关或 +1 开关关闭时，直接 return %orig，不进入任何自定义逻辑
// 2. 绝不 hook canPerformAction:，让 UIKit 默认处理 jjRedBag_onPlusOne 这个 %new 方法
// 3. 仅在满足显示条件时，复制 result 追加自己的 +1 菜单项，绝不修改 result 原数组
%hook BaseMessageCellView

- (id)filteredMenuItems:(id)items {
    id result = %orig;

    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.plusOneEnabled) return result;
    if (![result isKindOfClass:[NSArray class]]) return result;

    // 根据消息类型检查对应子开关
    CMessageWrap *msgWrap = nil;
    if ([self respondsToSelector:@selector(getMsgCmessageWrap)]) {
        msgWrap = [self performSelector:@selector(getMsgCmessageWrap)];
    }
    if (!msgWrap && [self respondsToSelector:@selector(getMessageWrap)]) {
        msgWrap = [self performSelector:@selector(getMessageWrap)];
    }
    if (!msgWrap) {
        id vm = nil;
        if ([self respondsToSelector:@selector(viewModel)]) vm = [self performSelector:@selector(viewModel)];
        if (vm && [vm respondsToSelector:@selector(messageWrap)]) msgWrap = [vm performSelector:@selector(messageWrap)];
    }
    if (!msgWrap) return result;

    unsigned int msgType = msgWrap.m_uiMessageType;
    BOOL shouldShow = NO;
    if (msgType == 1 && manager.plusOneTextEnabled) shouldShow = YES;
    if (msgType == 47 && manager.plusOneEmoticonEnabled) shouldShow = YES;
    if (msgType == 3 && manager.plusOneImageEnabled) shouldShow = YES;
    if (msgType == 43 && manager.plusOneVideoEnabled) shouldShow = YES;
    if (msgType == 49 && manager.plusOneFileEnabled) shouldShow = YES;
    if (!shouldShow) return result;

    NSMutableArray *newItems = [NSMutableArray arrayWithArray:result];
    // 避免重复添加（其他插件可能已添加）
    for (id existingItem in newItems) {
        if ([existingItem respondsToSelector:@selector(action)] &&
            [existingItem action] == @selector(jjRedBag_onPlusOne)) {
            return newItems;
        }
    }

    id plusOneItem = nil;
    Class MMMenuItemClass = objc_getClass("MMMenuItem");
    if (MMMenuItemClass) {
        @try { plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" svgName:@"icons_outlined_copy" target:self action:@selector(jjRedBag_onPlusOne)]; } @catch (NSException *e) {}
        if (!plusOneItem) { @try { plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" target:self action:@selector(jjRedBag_onPlusOne)]; } @catch (NSException *e) {} }
        if (!plusOneItem) { @try { plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" icon:nil target:self action:@selector(jjRedBag_onPlusOne)]; } @catch (NSException *e) {} }
    }
    if (!plusOneItem) { @try { plusOneItem = [[UIMenuItem alloc] initWithTitle:@"+1" action:@selector(jjRedBag_onPlusOne)]; } @catch (NSException *e) {} }
    if (plusOneItem) [newItems addObject:plusOneItem];
    return newItems;
}

// 注意：不 hook canPerformAction:withSender:，因为 UIKit 对 %new 添加的方法会默认返回 YES
// 并且 hook 此方法会干扰 miyou.dylib 等其他 +1 插件的菜单项显示。
// 菜单项的显示控制完全在 filteredMenuItems: 中完成（不显示就不添加）。

// +1实际操作方法也定义在BaseMessageCellView上
%new
- (void)jjRedBag_onPlusOne {
    @try {
        MMMenuController *menuCtrl = [objc_getClass("MMMenuController") sharedMenuController];
        if (menuCtrl) [menuCtrl setMenuVisible:NO animated:YES];

        CMessageWrap *msgWrap = nil;
        if ([self respondsToSelector:@selector(getMsgCmessageWrap)]) {
            msgWrap = [self performSelector:@selector(getMsgCmessageWrap)];
        }
        if (!msgWrap) {
            id vm = nil;
            if ([self respondsToSelector:@selector(viewModel)]) vm = [self performSelector:@selector(viewModel)];
            if (vm && [vm respondsToSelector:@selector(messageWrap)]) msgWrap = [vm performSelector:@selector(messageWrap)];
        }
        if (!msgWrap) return;

        NSString *chatUserName = jj_getChatUserNameFromResponderChain(self);
        if (!chatUserName || chatUserName.length == 0) return;

        NSString *unsupportedReason = jj_plusOneUnsupportedReason(msgWrap);
        if (unsupportedReason.length > 0) {
            [self jjRedBag_showPlusOneUnsupported:unsupportedReason];
            return;
        }

        id serviceCenter = jj_getServiceCenter();
        if (!serviceCenter) {
            [self jjRedBag_showPlusOneUnsupported:@"服务中心获取失败"];
            return;
        }

        CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
        CContact *selfContact = [contactMgr getSelfContact];
        NSString *selfUserName = selfContact.m_nsUsrName;

        CMessageMgr *msgMgr = jj_getService(objc_getClass("CMessageMgr"));
        if (!msgMgr) return;

        unsigned int msgType = msgWrap.m_uiMessageType;

        // === 文字消息 ===
        if (msgType == 1) {
            NSString *text = msgWrap.m_nsContent;
            if (!text || text.length == 0) {
                [self jjRedBag_showPlusOneUnsupported:@"文本内容为空"];
                return;
            }
            CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(msgWrap, selfUserName, chatUserName);
            if (newWrap) {
                [msgMgr AddMsg:chatUserName MsgWrap:newWrap];
                [self jjRedBag_scrollChatToBottom];
            }
            return;
        }

        // === 表情包消息 ===
        if (msgType == 47) {
            CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(msgWrap, selfUserName, chatUserName);
            if (newWrap) {
                [msgMgr AddEmoticonMsg:chatUserName MsgWrap:newWrap];
                [self jjRedBag_scrollChatToBottom];
            }
            return;
        }

        // === 获取聊天联系人（媒体消息需要） ===
        CContact *chatContact = [contactMgr getContactByName:chatUserName];
        if (!chatContact) {
            [self jjRedBag_showPlusOneUnsupported:@"获取联系人失败"];
            return;
        }

        Class forwardUtilCls = objc_getClass("ForwardMsgUtil");
        if (!forwardUtilCls) {
            [self jjRedBag_showPlusOneUnsupported:@"转发工具不可用"];
            return;
        }

        BOOL sent = NO;

        // === 语音消息(type 34)：优先使用ForwardMsgUtil ===
        if (msgType == 34) {
            SEL fwdSel = NSSelectorFromString(@"ForwardMsg:ToContact:Scene:");
            if ([forwardUtilCls respondsToSelector:fwdSel]) {
                @try {
                    typedef void (*JJFwd)(id, SEL, id, id, unsigned int);
                    ((JJFwd)objc_msgSend)((id)forwardUtilCls, fwdSel, msgWrap, chatContact, (unsigned int)0);
                    sent = YES;
                } @catch (NSException *e) {}
            }
            if (sent) {
                [self jjRedBag_scrollChatToBottom];
                return;
            }
            // ForwardMsgUtil失败则回退到克隆
            CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(msgWrap, selfUserName, chatUserName);
            if (newWrap) {
                @try {
                    [msgMgr AddMsg:chatUserName MsgWrap:newWrap];
                    [self jjRedBag_scrollChatToBottom];
                    sent = YES;
                } @catch (NSException *e) {}
            }
            if (!sent) {
                [self jjRedBag_showPlusOneUnsupported:@"语音消息转发失败"];
            }
            return;
        }

        // === 图片/视频/文件等媒体消息：使用ForwardMsgUtil转发 ===
        // 方式1: ForwardMsg:ToContact:Scene: (微信内部转发，处理所有媒体类型)
        SEL fwdSel = NSSelectorFromString(@"ForwardMsg:ToContact:Scene:");
        if ([forwardUtilCls respondsToSelector:fwdSel]) {
            @try {
                typedef void (*JJFwd)(id, SEL, id, id, unsigned int);
                ((JJFwd)objc_msgSend)((id)forwardUtilCls, fwdSel, msgWrap, chatContact, (unsigned int)0);
                sent = YES;
            } @catch (NSException *e) {}
        }

        // 方式2: ForwardMsgList:ToContact:Scene:
        if (!sent) {
            SEL fwdListSel = NSSelectorFromString(@"ForwardMsgList:ToContact:Scene:");
            if ([forwardUtilCls respondsToSelector:fwdListSel]) {
                @try {
                    typedef void (*JJFwdList)(id, SEL, id, id, unsigned int);
                    ((JJFwdList)objc_msgSend)((id)forwardUtilCls, fwdListSel, @[msgWrap], chatContact, (unsigned int)0);
                    sent = YES;
                } @catch (NSException *e) {}
            }
        }

        // 方式3: 回退到克隆+AddMsg
        if (!sent) {
            CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(msgWrap, selfUserName, chatUserName);
            if (newWrap) {
                @try {
                    [msgMgr AddMsg:chatUserName MsgWrap:newWrap];
                    sent = YES;
                } @catch (NSException *e) {}
            }
        }

        if (sent) {
            [self jjRedBag_scrollChatToBottom];
        } else {
            [self jjRedBag_showPlusOneUnsupported:[NSString stringWithFormat:@"不支持+1（type=%u）", msgType]];
        }
    } @catch (NSException *exception) {}
}

// 发送后自动滚动到聊天底部
%new
- (void)jjRedBag_scrollChatToBottom {
    // 从响应链查找聊天视图控制器
    UIResponder *responder = self;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)responder;
            // 方式1: 尝试直接获取 tableView 属性
            UITableView *tableView = nil;
            @try {
                if ([vc respondsToSelector:@selector(tableView)]) {
                    tableView = [vc performSelector:@selector(tableView)];
                } else if ([vc respondsToSelector:@selector(getTableView)]) {
                    tableView = [vc performSelector:@selector(getTableView)];
                }
            } @catch (NSException *e) {}

            // 方式2: 从 view 的 subviews 中递归查找 UITableView
            if (!tableView || ![tableView isKindOfClass:[UITableView class]]) {
                tableView = jj_findTableViewInView(vc.view);
            }

            if (tableView && [tableView isKindOfClass:[UITableView class]]) {
                NSInteger lastSection = tableView.numberOfSections - 1;
                if (lastSection >= 0) {
                    NSInteger lastRow = [tableView numberOfRowsInSection:lastSection] - 1;
                    if (lastRow >= 0) {
                        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:lastRow inSection:lastSection];
                        @try {
                            [tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
                        } @catch (NSException *e) {}
                    }
                }
            }
            break;
        }
        responder = [responder nextResponder];
    }
}

%new
- (void)jjRedBag_showPlusOneUnsupported:(NSString *)reason {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"+1"
                                                                       message:reason
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

%end

// EmoticonMessageCellView只添加"大大小小"菜单（+1已由BaseMessageCellView统一处理）
%hook EmoticonMessageCellView

- (id)filteredMenuItems:(id)items {
    id result = %orig;

    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.emoticonScaleEnabled) return result;
    if (![result isKindOfClass:[NSArray class]]) return result;

    NSMutableArray *newItems = [NSMutableArray arrayWithArray:result];
    Class MMMenuItemClass = objc_getClass("MMMenuItem");
    id scaleItem = nil;
    if (MMMenuItemClass) {
        @try { scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" svgName:@"icons_outlined_sticker" target:self action:@selector(jj_onEmoticonResize)]; } @catch (NSException *e) {}
        if (!scaleItem) { @try { scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" target:self action:@selector(jj_onEmoticonResize)]; } @catch (NSException *e) {} }
        if (!scaleItem) { @try { scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" icon:nil target:self action:@selector(jj_onEmoticonResize)]; } @catch (NSException *e) {} }
    }
    if (!scaleItem) { @try { scaleItem = [[UIMenuItem alloc] initWithTitle:@"大大小小" action:@selector(jj_onEmoticonResize)]; } @catch (NSException *e) {} }
    if (scaleItem) [newItems addObject:scaleItem];
    return newItems;
}

// 注意：不 hook canPerformAction:，UIKit 对 %new 添加的 jj_onEmoticonResize 会默认返回 YES
// 菜单项是否显示已经在上面的 filteredMenuItems: 中按 emoticonScaleEnabled 判断，不需要再 hook

%new
- (void)jj_onEmoticonResize {
    @try {
        CMessageWrap *msgWrap = nil;
        if ([self respondsToSelector:@selector(getMsgCmessageWrap)]) {
            msgWrap = [self performSelector:@selector(getMsgCmessageWrap)];
        }
        if (!msgWrap) {
            id vm = nil;
            if ([self respondsToSelector:@selector(viewModel)]) vm = [self performSelector:@selector(viewModel)];
            if (vm && [vm respondsToSelector:@selector(messageWrap)]) msgWrap = [vm performSelector:@selector(messageWrap)];
        }
        if (!msgWrap || !msgWrap.m_nsContent || msgWrap.m_nsContent.length == 0) return;
        
        // 保存全局状态（只需要消息和聊天对象，不需要抓取数据）
        jj_currentEmoticonMsgWrap = msgWrap;
        jj_currentChatUserName = jj_getChatUserNameFromResponderChain(self);
        jj_currentSourceView = self;
        
        // 关闭当前菜单
        MMMenuController *menuCtrl = [objc_getClass("MMMenuController") sharedMenuController];
        if (menuCtrl) [menuCtrl setMenuVisible:NO animated:YES];
        
        // 延迟显示缩放选择菜单
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_showScaleActionSheet();
        });
    } @catch (NSException *exception) {}
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


static NSString *jj_momentsOriginalMenuTitle = @"从手机相册选择（原画质）";
static char jj_momentsForceOriginalPickerKey;
// 当前是否处于朋友圈原画质会话中（从 MMImagePickerManager 打开相册时自动标记）
static BOOL jj_momentsOriginalPickerSessionPending = NO;

// 判断朋友圈原画质功能是否开启
static BOOL jj_momentsOriginalQualityFeatureEnabled(void) {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    return manager.enabled && manager.momentsOriginalQualityEnabled;
}

static BOOL jj_isMomentsOriginalPickerOptionObject(id obj) {
    if (!obj) return NO;
    Class optionObjClass = objc_getClass("MMImagePickerManagerOptionObj");
    return optionObjClass && [obj isKindOfClass:optionObjClass];
}

// 判断VC是否在朋友圈发布相关上下文（用于决定是否强制原画质）
static BOOL jj_isMomentsPublishContext(UIViewController *vc) {
    if (!vc) return NO;
    UIViewController *cur = vc;
    int depth = 0;
    while (cur && depth < 8) {
        NSString *clsName = NSStringFromClass([cur class]);
        if ([clsName isEqualToString:@"WCNewCommitViewController"] ||
            [clsName isEqualToString:@"WCTimeLineViewController"] ||
            [clsName isEqualToString:@"ImageSelectorController"] ||
            [clsName isEqualToString:@"MMAssetPickerController"]) {
            return YES;
        }
        cur = cur.presentingViewController ?: cur.parentViewController;
        depth++;
    }
    return NO;
}

static BOOL jj_actionSheetContainsTitle(WCActionSheet *sheet, NSString *title) {
    if (!sheet || title.length == 0) return NO;
    @try {
        unsigned long long count = [sheet numberOfButtons];
        for (unsigned long long i = 0; i < count; i++) {
            id buttonTitle = [sheet buttonTitleAtIndex:(long long)i];
            if ([buttonTitle isKindOfClass:[NSString class]] && [buttonTitle isEqualToString:title]) {
                return YES;
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

static NSInteger jj_momentsAlbumButtonIndex(WCActionSheet *sheet) {
    if (!sheet) return NSNotFound;
    NSInteger fallbackIndex = NSNotFound;
    @try {
        unsigned long long count = [sheet numberOfButtons];
        for (unsigned long long i = 0; i < count; i++) {
            id buttonTitle = [sheet buttonTitleAtIndex:(long long)i];
            if ([buttonTitle isKindOfClass:[NSString class]]) {
                NSString *title = (NSString *)buttonTitle;
                if ([title isEqualToString:@"从手机相册选择"]) {
                    return (NSInteger)i;
                }
                if (fallbackIndex == NSNotFound && [title containsString:@"从手机相册选择"] && ![title containsString:@"原画质"]) {
                    fallbackIndex = (NSInteger)i;
                }
            }
        }
    } @catch (NSException *e) {}
    return fallbackIndex;
}

static void jj_markMomentsOriginalPickerForController(UIViewController *vc, BOOL enabled) {
    if (!vc) return;
    objc_setAssociatedObject(vc, &jj_momentsForceOriginalPickerKey, enabled ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL jj_shouldForceMomentsOriginalPickerForController(UIViewController *vc) {
    if (!vc) return NO;
    NSNumber *flag = objc_getAssociatedObject(vc, &jj_momentsForceOriginalPickerKey);
    return flag && [flag boolValue];
}

static void jj_applyMomentsOriginalPickerOptions(MMImagePickerManagerOptionObj *optionObj) {
    if (!optionObj) return;
    optionObj.canSendOriginalImage = YES;
    optionObj.forceSendOriginalImage = YES;
    optionObj.hideOriginButton = YES;
    optionObj.isOpenSendOriginVideo = YES;
    optionObj.isWAVideoCompressed = NO;
    // videoQualityType: 0=低, 1=高; 强制使用高
    optionObj.videoQualityType = 1;
}

static void jj_prepareOriginalAssetInfosForPicker(MMAssetPickerController *picker) {
    if (!picker) return;
    @try {
        picker.isOriginSelected = YES;
        // 设置内部原图发送标志（容错尝试多个 key 名）
        @try { [picker setValue:@YES forKey:@"_isOriginalImageForSend"]; } @catch (NSException *e) {}
        if ([picker respondsToSelector:@selector(onOriginImageCheckChanged)]) {
            [picker onOriginImageCheckChanged];
        }
        // 触发文件大小重新计算
        if ([picker respondsToSelector:@selector(updateSelectTotalSize)]) {
            [picker updateSelectTotalSize];
        }
        NSArray *assetInfos = picker.selectedAssetInfos;
        if (![assetInfos isKindOfClass:[NSArray class]]) return;
        for (id info in assetInfos) {
            if ([info respondsToSelector:@selector(setIsHDImage:)]) {
                [info setIsHDImage:YES];
            }
            if ([info respondsToSelector:@selector(asset)]) {
                MMAsset *asset = [info asset];
                if (asset && [asset respondsToSelector:@selector(setM_isNeedOriginImage:)]) {
                    asset.m_isNeedOriginImage = YES;
                }
            }
        }
    } @catch (NSException *e) {}
}

// 安全地对 id 目标调用 setter: setter 名+BOOL 参数（通过 NSInvocation，避免 id 下签名错乱）
static void jj_safeSetBoolProperty(id target, SEL sel, BOOL value) {
    if (!target || !sel) return;
    if (![target respondsToSelector:sel]) return;
    @try {
        NSMethodSignature *sig = [target methodSignatureForSelector:sel];
        if (!sig || sig.numberOfArguments < 3) return;
        const char *argType = [sig getArgumentTypeAtIndex:2];
        if (!argType) return;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:target];
        // 兼容 BOOL(c/B)、int(i)、long(l) 等整形参数
        if (argType[0] == 'c' || argType[0] == 'B') {
            BOOL v = value;
            [inv setArgument:&v atIndex:2];
        } else if (argType[0] == 'i') {
            int v = value ? 1 : 0;
            [inv setArgument:&v atIndex:2];
        } else if (argType[0] == 'q' || argType[0] == 'l') {
            long long v = value ? 1 : 0;
            [inv setArgument:&v atIndex:2];
        } else {
            BOOL v = value;
            [inv setArgument:&v atIndex:2];
        }
        [inv invoke];
    } @catch (NSException *e) {}
}

// 核心：遍历上传任务中所有媒体，全部设置为跳过压缩 + 原图标志
static void jj_applyOriginalQualityToUploadTask(id task) {
    if (!task) return;
    @try {
        // 任务级原画质标记（安全调用，避免 id 下签名错乱）
        jj_safeSetBoolProperty(task, @selector(setOriginal:), YES);
        // 遍历 mediaList 逐一设置 skipCompress
        @try {
            NSArray *medias = [task valueForKey:@"mediaList"];
            if ([medias isKindOfClass:[NSArray class]]) {
                for (id media in medias) {
                    jj_safeSetBoolProperty(media, @selector(setSkipCompress:), YES);
                }
            }
        } @catch (NSException *e) {}
    } @catch (NSException *e) {}
}

// 递归隐藏包含"制作视频"文本的按钮/视图，避免遮挡原画质文件大小显示
static void jj_hideMakeVideoButtonInView(UIView *view) {
    if (!view) return;
    for (UIView *sub in view.subviews) {
        // 检查 UIButton（制作视频/模板合成按钮）
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)sub;
            NSString *title = [btn titleForState:UIControlStateNormal];
            if (title && [title containsString:@"制作视频"]) {
                btn.hidden = YES;
                continue;
            }
            // 也检查按钮的类名（_templateComposingButton类型）
            NSString *cls = NSStringFromClass([btn class]);
            if ([cls containsString:@"Template"] || [cls containsString:@"Composing"]) {
                btn.hidden = YES;
                continue;
            }
        }
        // 检查 UILabel
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            if (label.text && [label.text containsString:@"制作视频"]) {
                sub.superview.hidden = YES;
                continue;
            }
        }
        jj_hideMakeVideoButtonInView(sub);
    }
}

static void jj_injectMomentsOriginalMenu(WCTimeLineViewController *vc) {
    if (!jj_momentsOriginalQualityFeatureEnabled() || !vc) return;
    WCActionSheet *sheet = [objc_getClass("WCActionSheet") getCurrentShowingActionSheet];
    if (!sheet) return;
    if (jj_actionSheetContainsTitle(sheet, jj_momentsOriginalMenuTitle)) return;
    NSInteger albumIndex = jj_momentsAlbumButtonIndex(sheet);
    if (albumIndex == NSNotFound) return;
    WCTimeLineViewController *capturedVC = vc;
    WCActionSheet *capturedSheet = sheet;
    [sheet addButtonWithTitle:jj_momentsOriginalMenuTitle eventAction:^{
        WCTimeLineViewController *strongVC = capturedVC;
        WCActionSheet *strongSheet = capturedSheet ?: [objc_getClass("WCActionSheet") getCurrentShowingActionSheet];
        if (!strongVC || !strongSheet) return;
        jj_markMomentsOriginalPickerForController((UIViewController *)strongVC, YES);
        @try {
            NSInteger targetIndex = jj_momentsAlbumButtonIndex(strongSheet);
            if (targetIndex == NSNotFound) targetIndex = albumIndex;
            [strongVC actionSheet:strongSheet clickedButtonAtIndex:(long long)targetIndex];
        } @catch (NSException *e) {
            jj_markMomentsOriginalPickerForController((UIViewController *)strongVC, NO);
        }
    }];
    [sheet reloadInnerView];
}


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

%hook WCTimeLineViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 不再此处重置标志，避免异步图片处理时标志已被清除
    // 标志会在 sendSelectedMedia 后通过 WCNewCommitViewController 重置
    JJ_LOG(@"发布", @"进入朋友圈时间线 WCTimeLineViewController");
}

- (void)showPhotoAlert:(id)arg1 {
    %orig;
    JJ_LOG(@"发布", @"弹出朋友圈相机菜单 showPhotoAlert");
    dispatch_async(dispatch_get_main_queue(), ^{
        jj_injectMomentsOriginalMenu(self);
    });
}

- (void)showUploadOption:(id)arg1 {
    %orig;
    JJ_LOG(@"发布", @"弹出朋友圈上传菜单 showUploadOption");
    dispatch_async(dispatch_get_main_queue(), ^{
        jj_injectMomentsOriginalMenu(self);
    });
}

%end

// Hook朋友圈发布控制器，核心修复：在上传任务派发前强制原画质
%hook WCNewCommitViewController

// 朋友圈发布页面出现时保持会话开启（不做3秒自动重置），确保发布过程中所有
// 图片/视频压缩 hook（VideoEncodeParams、MMImageUtil、MMVideoCompressHelper 等）都能生效
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BOOL on = jj_momentsOriginalQualityFeatureEnabled();
    if (on) jj_momentsOriginalPickerSessionPending = YES;
    JJ_LOG(@"发布", @"进入朋友圈发布页 WCNewCommitViewController  原画质=%@  会话=%@",
           on ? @"ON" : @"OFF",
           jj_momentsOriginalPickerSessionPending ? @"YES" : @"NO");
    // 一次性探测：列出 WCNewCommitViewController 真实方法名，定位上传任务入口
    if ([JJDebugConsole isEnabled]) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            Class cls = objc_getClass("WCNewCommitViewController");
            NSString *all = jj_dumpMethods(cls);
            // 过滤含 "Upload"/"upload"/"task"/"Task"/"send"/"post" 关键词的方法
            NSArray *parts = [all componentsSeparatedByString:@"; "];
            NSMutableArray *filtered = [NSMutableArray array];
            for (NSString *p in parts) {
                if ([p rangeOfString:@"pload" options:NSCaseInsensitiveSearch].length > 0
                    || [p rangeOfString:@"task" options:NSCaseInsensitiveSearch].length > 0
                    || [p rangeOfString:@"send" options:NSCaseInsensitiveSearch].length > 0
                    || [p rangeOfString:@"post" options:NSCaseInsensitiveSearch].length > 0
                    || [p rangeOfString:@"commit" options:NSCaseInsensitiveSearch].length > 0
                    || [p rangeOfString:@"submit" options:NSCaseInsensitiveSearch].length > 0
                    || [p rangeOfString:@"OnDone" options:NSCaseInsensitiveSearch].length > 0) {
                    if (p.length > 0) [filtered addObject:p];
                }
            }
            JJ_LOG(@"发布", @"WCNewCommitViewController 上传相关方法: %@",
                   [filtered componentsJoinedByString:@" | "]);
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    JJ_LOG(@"发布", @"离开朋友圈发布页，6秒后重置会话");
    // 离开发布页面时延迟重置全局标志（不捕获 self，避免 controller 被释放后 block 野指针）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        jj_momentsOriginalPickerSessionPending = NO;
    });
}

// 核心修复：朋友圈发布前处理上传任务，强制所有媒体跳过压缩
- (void)processUploadTask:(id)task {
    BOOL on = jj_momentsOriginalQualityFeatureEnabled();
    @try {
        NSArray *medias = [task respondsToSelector:@selector(mediaList)] ? [task valueForKey:@"mediaList"] : nil;
        JJ_LOG(@"上传", @"processUploadTask: 原画质=%@  task=%@  mediaList数=%lu",
               on ? @"ON" : @"OFF",
               NSStringFromClass([task class]) ?: @"nil",
               (unsigned long)(medias.count));
        NSInteger idx = 0;
        for (id media in medias) {
            NSString *mCls = NSStringFromClass([media class]) ?: @"?";
            id skipC = nil, original = nil, path = nil;
            @try { skipC = [media valueForKey:@"skipCompress"]; } @catch(NSException *e){}
            @try { original = [media valueForKey:@"original"]; } @catch(NSException *e){}
            @try { path = [media valueForKey:@"path"]; } @catch(NSException *e){}
            unsigned long long sz = 0;
            if ([path isKindOfClass:[NSString class]] && [(NSString *)path length] > 0) {
                NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:(NSString *)path error:nil];
                sz = [a[NSFileSize] unsignedLongLongValue];
            }
            JJ_LOG(@"上传", @"  [%ld] %@  skipCompress=%@  original=%@  size=%.2fMB  path=%@",
                   (long)idx, mCls,
                   [skipC boolValue] ? @"YES" : @"NO",
                   [original boolValue] ? @"YES" : @"NO",
                   (double)sz / (1024.0 * 1024.0),
                   (path ?: @"nil"));
            idx++;
        }
    } @catch (NSException *e) {}
    if (on) {
        jj_momentsOriginalPickerSessionPending = YES;
        jj_applyOriginalQualityToUploadTask(task);
        JJ_LOG(@"上传", @"已对 %lu 个媒体应用 skipCompress=YES + setOriginal:YES",
               (unsigned long)[([task valueForKey:@"mediaList"]) count]);
    }
    %orig;
}

// 兜底：更新任务时也强制一次
- (void)commonUpdateWCUploadTask:(id)task {
    %orig;
    BOOL on = jj_momentsOriginalQualityFeatureEnabled();
    if (on) {
        jj_applyOriginalQualityToUploadTask(task);
    }
    if ([JJDebugConsole isEnabled]) {
        JJ_LOG(@"上传", @"commonUpdateWCUploadTask: 原画质=%@  task=%@",
               on ? @"ON" : @"OFF",
               NSStringFromClass([task class]) ?: @"nil");
        JJ_LOG(@"上传", @"  task全属性: %@", jj_dumpProperties(task));
        @try {
            NSArray *medias = nil;
            if ([task respondsToSelector:@selector(mediaList)]) {
                medias = [task valueForKey:@"mediaList"];
            }
            NSInteger idx = 0;
            for (id media in medias) {
                JJ_LOG(@"上传", @"  media[%ld] %@: %@",
                       (long)idx,
                       NSStringFromClass([media class]) ?: @"?",
                       jj_dumpProperties(media));
                idx++;
            }
        } @catch (NSException *e) {}
    }
}

// 用户点击"发布"时同步激活会话（防止先前被重置）
- (void)OnDone {
    BOOL on = jj_momentsOriginalQualityFeatureEnabled();
    if (on) jj_momentsOriginalPickerSessionPending = YES;
    JJ_LOG(@"发布", @"点击『发布』OnDone  原画质=%@", on ? @"ON" : @"OFF");
    %orig;
}

%end

// Hook上传任务本身：setOriginal: 只要功能开启就强制 YES
%hook WCUploadTask

- (void)setOriginal:(BOOL)original {
    BOOL on = jj_momentsOriginalQualityFeatureEnabled();
    JJ_LOG(@"上传", @"WCUploadTask.setOriginal: 原始=%@ → 实际=%@",
           original ? @"YES" : @"NO",
           (on ? @"YES" : (original ? @"YES" : @"NO")));
    if (on) {
        %orig(YES);
    } else {
        %orig;
    }
}

%end

// 关键：从最底层接管 WCUploadMedia.setSkipCompress:
// 不管哪个上游路径（processUploadTask/commonUpdate/直接构造）只要试图给媒体设置 skipCompress=NO，
// 在原画质会话里都强制改回 YES。这是真正的"无死角"hook
%hook WCUploadMedia

- (void)setSkipCompress:(BOOL)skipCompress {
    if (jj_momentsOriginalQualityFeatureEnabled() && jj_momentsOriginalPickerSessionPending) {
        if (!skipCompress) {
            JJ_LOG(@"上传", @"WCUploadMedia.setSkipCompress: 拦截 NO → 强制 YES (type=%d subType=%d)",
                   (int)[[self valueForKey:@"type"] intValue],
                   (int)[[self valueForKey:@"subType"] intValue]);
        }
        %orig(YES);
    } else {
        %orig;
    }
}

%end

// 注意：不再 hook MMVideoCompressHelper.exportVideoFromUrl:，因为已经在更底层的
// VideoEncodeParams.adjustIfNeeded 和 VideoEncodeTask.exportAsynchronouslyWithCompletionHandler:
// 处强制 skipVideoCompress=YES，效果更精确且副作用更小

// 核心压缩点一：视频编码参数级的跳过压缩开关（发布阶段最底层）
// 在朋友圈原画质会话中，强制 skipVideoCompress=YES，让微信走 MMVideoNotCompressTask 分支
%hook VideoEncodeParams

- (void)adjustIfNeeded {
    %orig;
    BOOL active = jj_momentsOriginalQualityFeatureEnabled() && jj_momentsOriginalPickerSessionPending;
    if (active) {
        @try { [self setValue:@YES forKey:@"skipVideoCompress"]; } @catch (NSException *e) {}
    }
    if ([JJDebugConsole isEnabled]) {
        JJ_LOG(@"视频", @"VideoEncodeParams.adjustIfNeeded 会话=%@", active ? @"YES" : @"NO");
        JJ_LOG(@"视频", @"  全属性: %@", jj_dumpProperties(self));
    }
}

- (void)_adjustSizeToStandardForMoments {
    BOOL active = jj_momentsOriginalQualityFeatureEnabled() && jj_momentsOriginalPickerSessionPending;
    JJ_LOG(@"视频", @"VideoEncodeParams._adjustSizeToStandardForMoments  会话=%@", active ? @"YES" : @"NO");
    if (active) {
        @try { [self setValue:@YES forKey:@"skipVideoCompress"]; } @catch (NSException *e) {}
        return;
    }
    %orig;
}

%end

// 核心压缩点二：WCSightVideoCompositor 朋友圈视频合成器入口
// 在启动合成前，强制把 task.params.skipVideoCompress 设为 YES
%hook WCSightVideoCompositor

+ (void)startWithTask:(id)task resultBlock:(id)resultBlock {
    BOOL active = jj_momentsOriginalQualityFeatureEnabled() && jj_momentsOriginalPickerSessionPending;
    JJ_LOG(@"视频", @"WCSightVideoCompositor.startWithTask  task=%@  会话=%@",
           NSStringFromClass([task class]) ?: @"nil", active ? @"YES" : @"NO");
    if (active && task) {
        @try {
            id params = nil;
            if ([task respondsToSelector:@selector(params)]) {
                params = [task performSelector:@selector(params)];
            }
            if (params) {
                @try { [params setValue:@YES forKey:@"skipVideoCompress"]; } @catch (NSException *e) {}
            }
        } @catch (NSException *e) {}
    }
    %orig;
}

%end

// 核心压缩点三：VideoEncodeTask 通用编码任务开始导出前
// 任何从 chat 或 moments 走 VideoEncodeTask 的路径，在朋友圈原画质会话中都跳过压缩
%hook VideoEncodeTask

- (void)exportAsynchronouslyWithCompletionHandler:(id)handler {
    BOOL active = jj_momentsOriginalQualityFeatureEnabled() && jj_momentsOriginalPickerSessionPending;
    @try {
        id params = [self respondsToSelector:@selector(params)] ? [self performSelector:@selector(params)] : nil;
        if (active && params) {
            @try { [params setValue:@YES forKey:@"skipVideoCompress"]; } @catch (NSException *e) {}
        }
        if ([JJDebugConsole isEnabled]) {
            NSNumber *sk = nil;
            @try { sk = [params valueForKey:@"skipVideoCompress"]; } @catch (NSException *e) {}
            id inputPath = nil, outputPath = nil;
            @try { inputPath = [self valueForKey:@"inputPath"]; } @catch (NSException *e) {}
            @try { outputPath = [self valueForKey:@"outputPath"]; } @catch (NSException *e) {}
            JJ_LOG(@"视频", @"VideoEncodeTask 开始导出  skip=%@  in=%@  out=%@",
                   [sk boolValue] ? @"YES" : @"NO",
                   (inputPath ?: @"nil"),
                   (outputPath ?: @"nil"));
        }
    } @catch (NSException *e) {}
    %orig;
}

%end

// 注意：之前在此 hook 的 MMImageUtil.compressJpegImageData:compressQuality: 已移除。
// 原因：强制 quality=1.0 会让本机保存/预览时 JPEG 重编码膨胀到 5.7MB（原 HEIF 仅 1.7MB），
// 且对上传端实际效果极小——微信服务器会再次压缩。保留默认压缩避免本地缓存异常膨胀。

%hook MMImagePickerManager

// 只要功能开启且当前在朋友圈发布上下文中（不限于专用菜单入口），就自动强制原画质
+ (void)showWithOptionObj:(id)arg1 inViewController:(id)arg2 {
    if (jj_momentsOriginalQualityFeatureEnabled() && jj_isMomentsOriginalPickerOptionObject(arg1) && [arg2 isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)arg2;
        if (jj_shouldForceMomentsOriginalPickerForController(vc) || jj_isMomentsPublishContext(vc)) {
            jj_momentsOriginalPickerSessionPending = YES;
            jj_applyMomentsOriginalPickerOptions((MMImagePickerManagerOptionObj *)arg1);
            jj_markMomentsOriginalPickerForController(vc, NO);
            JJ_LOG(@"选图", @"MMImagePickerManager+showWithOptionObj 已启用原画质（来自 vc=%@）",
                   NSStringFromClass([vc class]) ?: @"nil");
        }
    }
    %orig;
}

- (void)showWithOptionObj:(id)arg1 inViewController:(id)arg2 delegate:(id)arg3 {
    if (jj_momentsOriginalQualityFeatureEnabled() && jj_isMomentsOriginalPickerOptionObject(arg1) && [arg2 isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)arg2;
        if (jj_shouldForceMomentsOriginalPickerForController(vc) || jj_isMomentsPublishContext(vc)) {
            jj_momentsOriginalPickerSessionPending = YES;
            jj_applyMomentsOriginalPickerOptions((MMImagePickerManagerOptionObj *)arg1);
            jj_markMomentsOriginalPickerForController(vc, NO);
            JJ_LOG(@"选图", @"MMImagePickerManager-showWithOptionObj 已启用原画质（来自 vc=%@）",
                   NSStringFromClass([vc class]) ?: @"nil");
        }
    }
    %orig;
}

%end

%hook MMAssetPickerController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (jj_momentsOriginalPickerSessionPending) {
        jj_prepareOriginalAssetInfosForPicker(self);
        // 设置内部标志确保原图发送
        @try { [self setValue:@YES forKey:@"_isOriginalImageForSend"]; } @catch (NSException *e) {}
        // 隐藏"制作视频"按钮，避免遮挡原画质文件大小显示
        @try {
            UIButton *btn = [self valueForKey:@"_templateComposingButton"];
            if (btn) btn.hidden = YES;
        } @catch (NSException *e) {}
        // 通用查找兜底（weak self，避免 VC 释放后 block 持有野指针）
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                jj_hideMakeVideoButtonInView(strongSelf.view);
            }
        });
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (jj_momentsOriginalPickerSessionPending) {
        @try {
            UIButton *btn = [self valueForKey:@"_templateComposingButton"];
            if (btn) btn.hidden = YES;
        } @catch (NSException *e) {}
    }
}

- (BOOL)getPickerWAVideoCompressedFromOptionObj {
    if (jj_momentsOriginalPickerSessionPending) {
        return NO;
    }
    return %orig;
}

- (void)sendSelectedMedia {
    JJ_LOG(@"选图", @"MMAssetPickerController.sendSelectedMedia  会话=%@",
           jj_momentsOriginalPickerSessionPending ? @"YES" : @"NO");
    if (jj_momentsOriginalPickerSessionPending) {
        jj_prepareOriginalAssetInfosForPicker(self);
    }
    %orig;
    // 在发送完成后重置标志，允许异步图片处理在标志有效期内完成
    if (jj_momentsOriginalPickerSessionPending) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_momentsOriginalPickerSessionPending = NO;
        });
    }
}

- (void)OnCancel:(id)arg1 {
    jj_momentsOriginalPickerSessionPending = NO;
    jj_markMomentsOriginalPickerForController((UIViewController *)self, NO);
    %orig;
}

- (void)onQuit {
    jj_momentsOriginalPickerSessionPending = NO;
    %orig;
}

%end

// Hook基类MMAssetConfigObject，一次性覆盖所有子类（MMAssetTimeLineConfig/MMAssetNewLifeSelectImageConfig等）
%hook MMAssetConfigObject

- (BOOL)isRetrivingOriginImage {
    if (jj_momentsOriginalPickerSessionPending) return YES;
    return %orig;
}

- (BOOL)isRetrivingOriginEditedImage {
    if (jj_momentsOriginalPickerSessionPending) return YES;
    return %orig;
}

- (BOOL)shouldCompressLongImage {
    if (jj_momentsOriginalPickerSessionPending) return NO;
    return %orig;
}

- (struct CGSize)imageResultSizeForOriginSize:(struct CGSize)arg1 {
    if (jj_momentsOriginalPickerSessionPending) return arg1;
    return %orig;
}

- (struct CGSize)imageSizeLimit {
    if (jj_momentsOriginalPickerSessionPending) {
        struct CGSize maxSize = {99999.0, 99999.0};
        return maxSize;
    }
    return %orig;
}

- (double)compressQuality {
    if (jj_momentsOriginalPickerSessionPending) return 1.0;
    return %orig;
}

- (double)minCompressEarnings {
    if (jj_momentsOriginalPickerSessionPending) return 1.0;
    return %orig;
}

- (unsigned long long)minNoneCompressNormalImageSize {
    if (jj_momentsOriginalPickerSessionPending) return ULLONG_MAX;
    return %orig;
}

- (unsigned long long)minNoneCompressLongImageSize {
    if (jj_momentsOriginalPickerSessionPending) return ULLONG_MAX;
    return %orig;
}

- (BOOL)disableOpportunisticDeliverMode {
    if (jj_momentsOriginalPickerSessionPending) return YES;
    return %orig;
}

%end

#pragma mark - 小程序激励广告跳过/加速

static CGFloat jj_adTimerSpeedMultiplier = 1.0;
static BOOL jj_adSpeedActive = NO;
static NSInteger jj_adToolbarTag = 88990011;

static void jj_removeAdToolbar(UIViewController *vc) {
    UIView *toolbar = [vc.view viewWithTag:jj_adToolbarTag];
    if (toolbar) [toolbar removeFromSuperview];
    jj_adSpeedActive = NO;
    jj_adTimerSpeedMultiplier = 1.0;
}

static void jj_addAdToolbar(WAWebViewController *vc) {
    if ([vc.view viewWithTag:jj_adToolbarTag]) return;
    
    CGFloat screenW = vc.view.bounds.size.width;
    CGFloat btnW = 60, btnH = 36, spacing = 8, totalW = btnW * 3 + spacing * 2;
    CGFloat startX = (screenW - totalW) / 2.0;
    CGFloat topY = 44;
    
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
    
    [vc.view addSubview:toolbar];
    [vc.view bringSubviewToFront:toolbar];
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
    if (adLabel && ![self.view viewWithTag:jj_adToolbarTag]) {
        jj_addAdToolbar(self);
    }
    
    // 广告自然完成时移除工具栏（"已获得奖励"）
    if (!adLabel && [self.view viewWithTag:jj_adToolbarTag]) {
        UILabel *doneLabel = jj_findLabelContaining(self.view, @"\u5df2\u83b7\u5f97\u5956\u52b1");
        if (doneLabel) {
            jj_removeAdToolbar(self);
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
        // 跳过广告
        @try {
            if ([self respondsToSelector:@selector(onGameRewards)]) {
                [self onGameRewards];
            }
        } @catch (NSException *e) {}

        @try {
            SEL bridgeSel = @selector(sendEventToJSBridge:Param:);
            SEL bothSel = @selector(sendEventToJSBridgeAndService:Param:);
            NSDictionary *rewardParam = @{@"isEnded": @YES, @"errCode": @0, @"errMsg": @"onClose:ok"};
            NSArray *eventNames = @[@"onRewardedVideoAdClose", @"onAdClose", @"rewardedVideoAdClose"];
            for (NSString *eventName in eventNames) {
                if ([self respondsToSelector:bothSel]) {
                    ((void (*)(id, SEL, id, id))objc_msgSend)(self, bothSel, eventName, rewardParam);
                } else if ([self respondsToSelector:bridgeSel]) {
                    ((void (*)(id, SEL, id, id))objc_msgSend)(self, bridgeSel, eventName, rewardParam);
                }
            }
        } @catch (NSException *e) {}

        jj_removeAdToolbar(self);
        return;
    }

    // 加速按钮 (idx 0 = 5x, idx 1 = 10x)
    CGFloat speeds[] = {5.0, 10.0};
    jj_adTimerSpeedMultiplier = speeds[idx];
    jj_adSpeedActive = YES;

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

#pragma mark - 网页底部导航栏（返回/前进按钮）

static NSInteger jj_webNavBarTag = 88990033;
static NSInteger jj_webNavBackBtnTag = 88990034;
static NSInteger jj_webNavForwardBtnTag = 88990035;
static NSInteger jj_webNavBackBgTag = 88990036;
static NSInteger jj_webNavFwdBgTag = 88990037;
static NSInteger jj_webNavAccentLineTag = 88990038;

// JJ自定义主题色（青色，与官方蓝/灰色区分）
static UIColor *jj_navAccentColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.35 green:0.85 blue:0.80 alpha:1.0]; // 亮青色（暗色模式）
            }
            return [UIColor colorWithRed:0.10 green:0.60 blue:0.56 alpha:1.0]; // 深青色（浅色模式）
        }];
    }
    return [UIColor colorWithRed:0.10 green:0.60 blue:0.56 alpha:1.0];
}

// 按钮圆角背景色（深浅色自适应）
static UIColor *jj_navBtnBgColor(BOOL enabled) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return enabled ? [UIColor colorWithWhite:1.0 alpha:0.12] : [UIColor colorWithWhite:1.0 alpha:0.05];
            }
            return enabled ? [UIColor colorWithWhite:0.0 alpha:0.06] : [UIColor colorWithWhite:0.0 alpha:0.03];
        }];
    }
    return enabled ? [UIColor colorWithWhite:0.0 alpha:0.06] : [UIColor colorWithWhite:0.0 alpha:0.03];
}

// 获取 VC 的 WKWebView
static WKWebView *jj_getWebView(UIViewController *vc) {
    if (!vc) return nil;
    @try {
        id webView = nil;
        if ([vc respondsToSelector:@selector(webView)]) {
            webView = [vc performSelector:@selector(webView)];
        } else if ([vc respondsToSelector:@selector(m_webView)]) {
            webView = [vc performSelector:@selector(m_webView)];
        }
        if ([webView isKindOfClass:[WKWebView class]]) return (WKWebView *)webView;
    } @catch (NSException *e) {}
    return nil;
}

// 判断原生底部工具栏是否真正可见于屏幕上
static BOOL jj_hasNativeBottomBar(UIViewController *vc) {
    if (!vc) return NO;
    @try {
        // 1. 先查 shouldShowBottom 标志（最权威的指标）
        if ([vc respondsToSelector:@selector(shouldShowBottom)]) {
            NSNumber *val = [vc valueForKey:@"shouldShowBottom"];
            if (!val || ![val boolValue]) return NO; // 明确不显示 → 原生栏不存在
        }
        // 2. 验证 bottomBar 对象是否真正在视图层级中可见
        if ([vc respondsToSelector:@selector(bottomBar)]) {
            UIView *bar = [vc performSelector:@selector(bottomBar)];
            if (bar && bar.superview && bar.window &&
                !bar.hidden && bar.alpha > 0.1 &&
                bar.frame.size.height > 10 && bar.frame.size.width > 10) {
                // 3. 确认 bar 在屏幕可见区域内（未被推到屏幕外）
                CGRect barInWindow = [bar convertRect:bar.bounds toView:nil];
                CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
                if (barInWindow.origin.y < screenH && CGRectGetMaxY(barInWindow) > 0) {
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

// 判断是否是网页URL（排除本地文件和特殊scheme）
static BOOL jj_isWebPageURL(NSURL *url) {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);
}

// 移除自定义导航栏
static void jj_removeWebNavBar(UIViewController *vc) {
    UIView *bar = [vc.view viewWithTag:jj_webNavBarTag];
    if (bar) [bar removeFromSuperview];
}

// 创建或更新底部导航栏
static void jj_updateWebNavBar(UIViewController *vc) {
    WKWebView *webView = jj_getWebView(vc);
    if (!webView) return;

    // 排除非网页内容
    if (!jj_isWebPageURL(webView.URL)) {
        jj_removeWebNavBar(vc);
        return;
    }

    // 如果原生底部工具栏可见，不显示我们的
    if (jj_hasNativeBottomBar(vc)) {
        jj_removeWebNavBar(vc);
        return;
    }

    BOOL canBack = webView.canGoBack;
    BOOL canForward = webView.canGoForward;

    UIView *navBar = [vc.view viewWithTag:jj_webNavBarTag];
    BOOL needCreate = (navBar == nil);

    if (needCreate) {
        CGFloat bottomInset = 0;
        if (@available(iOS 11.0, *)) {
            bottomInset = vc.view.safeAreaInsets.bottom;
        }
        CGFloat barH = 48 + bottomInset;
        CGFloat screenW = vc.view.bounds.size.width;

        navBar = [[UIView alloc] initWithFrame:CGRectMake(0, vc.view.bounds.size.height - barH, screenW, barH)];
        navBar.tag = jj_webNavBarTag;
        navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

        // 毛玻璃背景（深浅色自动切换）
        if (@available(iOS 13.0, *)) {
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.frame = navBar.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [navBar addSubview:blurView];
        } else {
            navBar.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.95];
        }

        // 顶部彩色强调线（青色，2pt，与官方灰色分隔线明显区分）
        UIView *accentLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, 2.0)];
        accentLine.tag = jj_webNavAccentLineTag;
        accentLine.backgroundColor = jj_navAccentColor();
        accentLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [navBar addSubview:accentLine];

        CGFloat btnW = 44, btnH = 36, btnY = 6;
        CGFloat spacing = 16;
        CGFloat groupW = btnW * 2 + spacing;
        CGFloat startX = (screenW - groupW) / 2.0;

        // --- 返回按钮 ---
        UIView *backBg = [[UIView alloc] initWithFrame:CGRectMake(startX, btnY, btnW, btnH)];
        backBg.tag = jj_webNavBackBgTag;
        backBg.layer.cornerRadius = btnH / 2.0;
        backBg.layer.masksToBounds = YES;
        backBg.backgroundColor = jj_navBtnBgColor(YES);
        [navBar addSubview:backBg];

        UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        backBtn.tag = jj_webNavBackBtnTag;
        backBtn.frame = backBg.frame;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
            [backBtn setImage:[UIImage systemImageNamed:@"arrow.left" withConfiguration:config] forState:UIControlStateNormal];
        } else {
            [backBtn setTitle:@"\u25C0" forState:UIControlStateNormal];
            backBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        }
        backBtn.tintColor = jj_navAccentColor();
        [backBtn addTarget:vc action:@selector(jj_webNavBackTapped) forControlEvents:UIControlEventTouchUpInside];
        [navBar addSubview:backBtn];

        // --- 前进按钮 ---
        UIView *fwdBg = [[UIView alloc] initWithFrame:CGRectMake(startX + btnW + spacing, btnY, btnW, btnH)];
        fwdBg.tag = jj_webNavFwdBgTag;
        fwdBg.layer.cornerRadius = btnH / 2.0;
        fwdBg.layer.masksToBounds = YES;
        fwdBg.backgroundColor = jj_navBtnBgColor(YES);
        [navBar addSubview:fwdBg];

        UIButton *fwdBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        fwdBtn.tag = jj_webNavForwardBtnTag;
        fwdBtn.frame = fwdBg.frame;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
            [fwdBtn setImage:[UIImage systemImageNamed:@"arrow.right" withConfiguration:config] forState:UIControlStateNormal];
        } else {
            [fwdBtn setTitle:@"\u25B6" forState:UIControlStateNormal];
            fwdBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        }
        fwdBtn.tintColor = jj_navAccentColor();
        [fwdBtn addTarget:vc action:@selector(jj_webNavForwardTapped) forControlEvents:UIControlEventTouchUpInside];
        [navBar addSubview:fwdBtn];

        // --- JJ 标识（小圆点+文字，表明这是插件功能）---
        UILabel *badge = [[UILabel alloc] init];
        badge.text = @"JJ";
        badge.font = [UIFont systemFontOfSize:8 weight:UIFontWeightBlack];
        badge.textColor = jj_navAccentColor();
        badge.textAlignment = NSTextAlignmentCenter;
        [badge sizeToFit];
        badge.frame = CGRectMake(screenW - badge.frame.size.width - 12, btnY + btnH - badge.frame.size.height, badge.frame.size.width, badge.frame.size.height);
        badge.alpha = 0.5;
        [navBar addSubview:badge];

        [vc.view addSubview:navBar];
        [vc.view bringSubviewToFront:navBar];
    }

    // 更新按钮状态和背景色
    UIButton *backBtn = [navBar viewWithTag:jj_webNavBackBtnTag];
    UIButton *fwdBtn = [navBar viewWithTag:jj_webNavForwardBtnTag];
    UIView *backBg = [navBar viewWithTag:jj_webNavBackBgTag];
    UIView *fwdBg = [navBar viewWithTag:jj_webNavFwdBgTag];

    // 返回按钮始终可用，图标根据状态动态切换
    backBtn.enabled = YES;
    backBtn.alpha = 1.0;
    backBg.backgroundColor = jj_navBtnBgColor(YES);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        if (canBack) {
            [backBtn setImage:[UIImage systemImageNamed:@"arrow.left" withConfiguration:config] forState:UIControlStateNormal];
        } else {
            // 无历史记录 → 显示房子图标（回首页）
            [backBtn setImage:[UIImage systemImageNamed:@"house" withConfiguration:config] forState:UIControlStateNormal];
        }
    }

    fwdBtn.enabled = canForward;
    fwdBtn.alpha = canForward ? 1.0 : 0.3;
    fwdBg.backgroundColor = jj_navBtnBgColor(canForward);

    [vc.view bringSubviewToFront:navBar];
}

%hook MMWebViewController

- (void)viewDidLayoutSubviews {
    %orig;

    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled || !manager.webBackButtonEnabled) return;

    // 节流：每0.5秒检测一次
    static NSTimeInterval jj_lastNavCheckTime = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - jj_lastNavCheckTime < 0.5) return;
    jj_lastNavCheckTime = now;

    jj_updateWebNavBar(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    jj_removeWebNavBar(self);
}

// 深浅色切换时自动更新导航栏外观
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            // 移除旧的，下一次 layout 时会自动用新颜色重建
            jj_removeWebNavBar(self);
        }
    }
}

%new
- (void)jj_webNavBackTapped {
    WKWebView *webView = jj_getWebView(self);
    if (webView && webView.canGoBack) {
        [webView goBack];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_updateWebNavBar(self);
        });
    } else if (webView && webView.URL) {
        // 无历史记录 → 跳转到首页
        NSString *host = webView.URL.host;
        NSString *homeURL;
        if (host && [host containsString:@"xiaofubao.com"]) {
            // 特例：贵州航空食品有限公司 → 指定首页URL
            homeURL = @"https://webapp.xiaofubao.com/card/card_home.shtml?platform=WECHAT_H5&schoolCode=qy119&thirdAppid=wx8fddf03d92fd6fa9";
        } else {
            // 其他网站 → 回域名根路径
            homeURL = [NSString stringWithFormat:@"%@://%@/", webView.URL.scheme, host];
        }
        NSString *js = [NSString stringWithFormat:@"location.replace('%@')", homeURL];
        [webView evaluateJavaScript:js completionHandler:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_updateWebNavBar(self);
        });
    }
}

%new
- (void)jj_webNavForwardTapped {
    WKWebView *webView = jj_getWebView(self);
    if (webView && webView.canGoForward) {
        [webView goForward];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            jj_updateWebNavBar(self);
        });
    }
}

%end

// Hook NSTimer 实现广告加速（仅在广告播放时生效）
%hook NSTimer

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)t selector:(SEL)s userInfo:(id)ui repeats:(BOOL)r {
    if (jj_adSpeedActive && jj_adTimerSpeedMultiplier > 1.0 && ti > 0 && ti <= 2.0) {
        ti = ti / jj_adTimerSpeedMultiplier;
    }
    return %orig(ti, t, s, ui, r);
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)t selector:(SEL)s userInfo:(id)ui repeats:(BOOL)r {
    if (jj_adSpeedActive && jj_adTimerSpeedMultiplier > 1.0 && ti > 0 && ti <= 2.0) {
        ti = ti / jj_adTimerSpeedMultiplier;
    }
    return %orig(ti, t, s, ui, r);
}

%end
