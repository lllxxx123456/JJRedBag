#import "WeChatHeaders.h"
#import "JJRedBagManager.h"
#import "JJRedBagSettingsController.h"
#import "JJRedBagParam.h"
#import <UserNotifications/UserNotifications.h>

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
            [[objc_getClass("WCPluginsMgr") sharedInstance] registerControllerWithTitle:@"JJRedBag" 
                                                                                version:@"1.0-1" 
                                                                             controller:@"JJRedBagSettingsController"];
        }
    });
}

#pragma mark - 红包消息Hook

// Hook消息接收 - 使用OnAddMessageByReceiver
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
    WCPayInfoItem *payInfo = [msgWrap m_oWCPayInfoItem];
    
    // 检查是否为红包消息 - 检查wxpay://
    if ([content rangeOfString:@"wxpay://"].location != NSNotFound) {
        [self jj_processRedBagMessage:msgWrap];
        return;
    }
    
    // 检查是否为转账消息 (m_uiPaySubType: 1=转账, 3=红包等)
    // 同时检查content中是否包含转账相关标识
    if (payInfo) {
        // 转账消息通常m_uiPaySubType为1，或者content中包含wcpay://c2cbizmessagehandler/transferconfirm
        BOOL isTransfer = (payInfo.m_uiPaySubType == 1) || 
                          ([content rangeOfString:@"transferconfirm"].location != NSNotFound) ||
                          ([content rangeOfString:@"c2c_transfer"].location != NSNotFound);
        if (isTransfer && payInfo.m_nsTransferID.length > 0) {
            [self jj_processTransferMessage:msgWrap];
        }
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
    
    // 判断是否是自己在群聊中发的消息（自己发的 && toUser是群聊）
    BOOL isGroupSender = isSender && [toUser rangeOfString:@"@chatroom"].location != NSNotFound;
    
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
        }
    } @catch (NSException *exception) {
        // 静默处理
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
- (void)jj_openRedBagWithNativeUrl:(NSString *)nativeUrl msgWrap:(CMessageWrap *)msgWrap isSelfRedBag:(BOOL)isSelfRedBag {
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
        
        [[JJRedBagParamQueue sharedQueue] enqueue:param];
        
        // 使用ReceiverQueryRedEnvelopesRequest方法查询红包状态
        WCRedEnvelopesLogicMgr *logicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                                              getService:objc_getClass("WCRedEnvelopesLogicMgr")];
        if (logicMgr) {
            [logicMgr ReceiverQueryRedEnvelopesRequest:reqParams];
        }
    } @catch (NSException *exception) {
        // 静默处理
    }
}

%new
- (void)jj_processTransferMessage:(CMessageWrap *)msgWrap {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    WCPayInfoItem *payInfo = [msgWrap m_oWCPayInfoItem];
    if (!payInfo) return;
    
    // 检查是否已收款
    if (payInfo.m_c2cPayReceiveStatus != 0) return;
    
    // 检查是否是发给自己的转账
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    CContact *selfContact = [contactMgr getSelfContact];
    NSString *selfUserName = [selfContact m_nsUsrName];
    
    NSString *receiverUsername = payInfo.transfer_receiver_username;
    if (![receiverUsername isEqualToString:selfUserName]) return;
    
    NSString *fromUser = msgWrap.m_nsFromUsr;
    BOOL isGroup = [fromUser rangeOfString:@"@chatroom"].location != NSNotFound;
    
    // 检查开关
    if (isGroup) {
        if (!manager.autoReceiveGroupEnabled) return;
        
        // 检查是否指定了收款群
        if (manager.receiveGroups.count > 0) {
            if (![manager.receiveGroups containsObject:fromUser]) return;
            
            // 检查是否指定了群成员
            NSArray *allowedMembers = manager.groupReceiveMembers[fromUser];
            if (allowedMembers && allowedMembers.count > 0) {
                NSString *payerUsername = payInfo.transfer_payer_username;
                if (![allowedMembers containsObject:payerUsername]) return;
            }
        }
    } else {
        if (!manager.autoReceivePrivateEnabled) return;
    }
    
    // 在进入异步块之前复制所有需要的值，避免访问已释放的对象
    NSString *transferId = [payInfo.m_nsTransferID copy] ?: @"";
    NSString *transactionId = [payInfo.m_nsTranscationID copy] ?: @"";
    NSString *payerUsername = [payInfo.transfer_payer_username copy] ?: @"";
    NSString *amountStr = [payInfo.m_total_fee copy] ?: @"0";
    NSString *memo = [payInfo.m_payMemo copy] ?: @"";
    long long amountValue = [amountStr longLongValue];
    NSString *fromUserCopy = [fromUser copy];
    
    // 构建收款请求参数
    NSMutableDictionary *confirmParams = [NSMutableDictionary dictionary];
    confirmParams[@"transferId"] = transferId;
    confirmParams[@"transactionId"] = transactionId;
    confirmParams[@"fromUser"] = fromUserCopy;
    confirmParams[@"isGroup"] = @(isGroup);
    confirmParams[@"payerUsername"] = payerUsername;
    confirmParams[@"amount"] = amountStr;
    confirmParams[@"memo"] = memo;
    
    // 执行自动收款
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            WCPayLogicMgr *payLogicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                                          getService:objc_getClass("WCPayLogicMgr")];
            if (payLogicMgr) {
                [payLogicMgr ConfirmTransferMoney:confirmParams];
                
                // 更新累计金额
                [[JJRedBagManager sharedManager] setTotalReceiveAmount:[[JJRedBagManager sharedManager] totalReceiveAmount] + amountValue];
                [[JJRedBagManager sharedManager] saveSettings];
                
                // 发送通知
                JJRedBagManager *mgr = [JJRedBagManager sharedManager];
                if (mgr.receiveNotificationEnabled && mgr.notificationChatId.length > 0) {
                    [self jj_sendReceiveNotification:confirmParams amount:amountValue];
                }
                
                // 本地弹窗通知
                if (mgr.receiveLocalNotificationEnabled) {
                    [self jj_sendReceiveLocalNotification:confirmParams amount:amountValue];
                }
                
                // 自动回复
                BOOL isGroupChat = [confirmParams[@"isGroup"] boolValue];
                if (isGroupChat && mgr.receiveAutoReplyGroupEnabled && mgr.receiveAutoReplyContent.length > 0) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self jj_sendReceiveAutoReply:confirmParams isGroup:YES];
                    });
                } else if (!isGroupChat && mgr.receiveAutoReplyPrivateEnabled && mgr.receiveAutoReplyContent.length > 0) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self jj_sendReceiveAutoReply:confirmParams isGroup:NO];
                    });
                }
            }
        } @catch (NSException *exception) {
            // 静默处理
        }
    });
}

%new
- (void)jj_sendReceiveAutoReply:(NSDictionary *)params isGroup:(BOOL)isGroup {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSString *content = manager.receiveAutoReplyContent;
    if (!content || content.length == 0) return;
    
    NSString *toUser = params[@"fromUser"];
    if (!toUser) return;
    
    CMessageMgr *msgMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CMessageMgr")];
    if (msgMgr) {
        [msgMgr SendTextMessage:content toUsr:toUser];
    }
}

%new
- (void)jj_sendReceiveNotification:(NSDictionary *)params amount:(long long)amount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.receiveNotificationChatId || manager.receiveNotificationChatId.length == 0) return;
    
    double amountYuan = amount / 100.0;
    NSString *memo = params[@"memo"] ?: @"";
    
    NSMutableString *msg = [NSMutableString string];
    [msg appendString:@"收到一笔转账：\n"];
    [msg appendFormat:@"金额：%.2f元\n", amountYuan];
    if (memo.length > 0) {
        [msg appendFormat:@"备注：%@", memo];
    }
    
    CMessageMgr *msgMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CMessageMgr")];
    if (msgMgr) {
        [msgMgr SendTextMessage:msg toUsr:manager.receiveNotificationChatId];
    }
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
#import <CoreLocation/CoreLocation.h>

static UIBackgroundTaskIdentifier jj_bgTask = UIBackgroundTaskInvalid;
static NSTimer *jj_keepAliveTimer = nil;
static AVAudioPlayer *jj_silentAudioPlayer = nil;
static CLLocationManager *jj_locationManager = nil;

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

static void jj_startLocationUpdates(void) {
    if (!jj_locationManager) {
        jj_locationManager = [[CLLocationManager alloc] init];
        jj_locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers; // 低精度省电
        jj_locationManager.distanceFilter = 99999; // 几乎不触发更新
        jj_locationManager.allowsBackgroundLocationUpdates = YES;
        jj_locationManager.pausesLocationUpdatesAutomatically = NO;
    }
    
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = jj_locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    
    if (status == kCLAuthorizationStatusAuthorizedAlways || status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [jj_locationManager startUpdatingLocation];
    }
}

static void jj_stopLocationUpdates(void) {
    if (jj_locationManager) {
        [jj_locationManager stopUpdatingLocation];
        jj_locationManager.allowsBackgroundLocationUpdates = NO;
        jj_locationManager = nil;
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
    jj_stopLocationUpdates();
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
                
            case JJBackgroundModeLocation:
                // 位置服务模式
                jj_startBackgroundKeepAlive();
                jj_startLocationUpdates();
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
            // 从队列中取出参数
            JJRedBagParam *param = [[JJRedBagParamQueue sharedQueue] dequeue];
            if (!param) return;
            
            // 检查是否应该抢红包
            // receiveStatus: 0=未领取, 2=已领取
            // hbStatus: 2=可领取?, 4=过期/领完?
            
            // 如果已经领取过，不需要再抢
            if ([responseDict[@"receiveStatus"] integerValue] == 2) {
                // 如果在pending列表中，移除它，避免重复处理
                if (param.sendId) {
                    [manager.pendingRedBags removeObjectForKey:param.sendId];
                }
                return;
            }
            
            // 红包被抢完
            if ([responseDict[@"hbStatus"] integerValue] == 4) {
                 if (param.sendId) {
                    [manager.pendingRedBags removeObjectForKey:param.sendId];
                }
                return;
            }
            
            // 没有timingIdentifier会被判定为使用外挂
            if (!responseDict[@"timingIdentifier"]) return;
            
            // 设置timingIdentifier
            param.timingIdentifier = responseDict[@"timingIdentifier"];
            
            // 计算延迟时间
            NSTimeInterval delay = [manager getDelayTimeForChat:param.sessionUserName];
            
            if (delay > 0) {
                // 有延迟，走任务队列
                unsigned int delayMs = (unsigned int)(delay * 1000);
                // 创建抢红包操作
                JJReceiveRedBagOperation *operation = [[JJReceiveRedBagOperation alloc] initWithRedBagParam:param delay:delayMs];
                [[JJRedBagTaskManager sharedManager] addNormalTask:operation];
            } else {
                // 极速模式：直接开，不走队列
                WCRedEnvelopesLogicMgr *logicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                                                      getService:objc_getClass("WCRedEnvelopesLogicMgr")];
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
                // 累加金额
                manager.totalAmount += amount;
                [manager saveSettings];
                
                // 复制param的关键信息，避免在异步块中访问可能被释放的对象
                JJRedBagParam *paramCopy = param;
                
                // 抢到红包，执行自动回复和通知
                // 切换到主线程执行UI和消息发送相关操作
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        [self jj_sendAutoReply:paramCopy];
                        [self jj_sendNotification:paramCopy amount:amount];
                        [self jj_sendLocalNotification:paramCopy amount:amount];
                    } @catch (NSException *exception) {
                        // 静默处理
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
    
    // 构建通知消息
    NSMutableString *msg = [NSMutableString string];
    [msg appendString:@"又为您抢到一个红包：\n"];
    [msg appendFormat:@"本次金额：%.2f元\n", amountYuan];
    
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
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"JJ抢红包"
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

static UIView *jj_currentEmoticonView = nil;
static CMessageWrap *jj_currentEmoticonMsgWrap = nil;
static UIImage *jj_currentEmoticonImage = nil;

static UIImageView *jj_findImageViewInView(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            return (UIImageView *)subview;
        }
        for (UIView *subsubview in subview.subviews) {
            if ([subsubview isKindOfClass:[UIImageView class]]) {
                return (UIImageView *)subsubview;
            }
            for (UIView *subsubsubview in subsubview.subviews) {
                if ([subsubsubview isKindOfClass:[UIImageView class]]) {
                    return (UIImageView *)subsubsubview;
                }
            }
        }
    }
    return nil;
}

static void jj_sendScaledEmoticon(UIImage *originalImage, CGFloat scaleFactor) {
    if (!originalImage) {
        jj_currentEmoticonView = nil;
        jj_currentEmoticonMsgWrap = nil;
        jj_currentEmoticonImage = nil;
        return;
    }
    
    CGSize originalSize = originalImage.size;
    CGSize newSize = CGSizeMake(originalSize.width * scaleFactor, originalSize.height * scaleFactor);
    
    CGFloat maxSize = 300.0;
    CGFloat minSize = 20.0;
    
    if (newSize.width > maxSize || newSize.height > maxSize) {
        CGFloat ratio = MIN(maxSize / newSize.width, maxSize / newSize.height);
        newSize.width *= ratio;
        newSize.height *= ratio;
    }
    if (newSize.width < minSize) newSize.width = minSize;
    if (newSize.height < minSize) newSize.height = minSize;
    
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [originalImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (!scaledImage) {
        jj_currentEmoticonView = nil;
        jj_currentEmoticonMsgWrap = nil;
        jj_currentEmoticonImage = nil;
        return;
    }
    
    NSString *chatUsername = nil;
    if (jj_currentEmoticonMsgWrap) {
        chatUsername = [jj_currentEmoticonMsgWrap m_nsFromUsr];
        if (!chatUsername || chatUsername.length == 0) {
            chatUsername = [jj_currentEmoticonMsgWrap m_nsToUsr];
        }
    }
    
    if (!chatUsername || chatUsername.length == 0) {
        jj_currentEmoticonView = nil;
        jj_currentEmoticonMsgWrap = nil;
        jj_currentEmoticonImage = nil;
        return;
    }
    
    NSData *imageData = UIImagePNGRepresentation(scaledImage);
    if (!imageData) {
        imageData = UIImageJPEGRepresentation(scaledImage, 0.9);
    }
    
    if (imageData) {
        CMessageMgr *msgMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CMessageMgr")];
        if (msgMgr && [msgMgr respondsToSelector:@selector(SendImgMessage:toUsrName:thumbImgData:midImgData:imgData:imgInfo:)]) {
            [msgMgr SendImgMessage:nil toUsrName:chatUsername thumbImgData:imageData midImgData:imageData imgData:imageData imgInfo:nil];
        } else if (msgMgr && [msgMgr respondsToSelector:@selector(SendImageMessage:toUsrName:)]) {
            [msgMgr SendImageMessage:imageData toUsrName:chatUsername];
        }
    }
    
    jj_currentEmoticonView = nil;
    jj_currentEmoticonMsgWrap = nil;
    jj_currentEmoticonImage = nil;
}

static void jj_showCustomScaleInput(UIImage *emoticonImage, UIViewController *topVC) {
    UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"自定义缩放比例" 
                                                                        message:@"请输入缩放倍数（0.1-3.0）\n例如：1.2 表示放大到1.2倍\n0.5 表示缩小到一半" 
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"例如：1.5";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = @"1.0";
    }];
    
    [inputAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = inputAlert.textFields.firstObject.text;
        CGFloat scale = [input floatValue];
        if (scale < 0.1) scale = 0.1;
        if (scale > 3.0) scale = 3.0;
        jj_sendScaledEmoticon(emoticonImage, scale);
    }]];
    
    [inputAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        jj_currentEmoticonView = nil;
        jj_currentEmoticonMsgWrap = nil;
        jj_currentEmoticonImage = nil;
    }]];
    
    [topVC presentViewController:inputAlert animated:YES completion:nil];
}

%hook EmoticonMessageCellView

- (void)onLongTouch {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.emoticonScaleEnabled) {
        jj_currentEmoticonView = self;
        
        if ([self respondsToSelector:@selector(getMsgCmessageWrap)]) {
            jj_currentEmoticonMsgWrap = [self performSelector:@selector(getMsgCmessageWrap)];
        } else if ([self respondsToSelector:@selector(wcrefine_getMessageWrap)]) {
            jj_currentEmoticonMsgWrap = [self performSelector:@selector(wcrefine_getMessageWrap)];
        }
        
        UIImageView *imageView = jj_findImageViewInView(self);
        if (imageView && imageView.image) {
            jj_currentEmoticonImage = imageView.image;
        }
    }
    %orig;
}

%end

%hook MMMenuController

- (void)setMenuItems:(NSArray *)items {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.emoticonScaleEnabled && jj_currentEmoticonView && jj_currentEmoticonImage && items.count > 0) {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:items];
        
        Class MMMenuItemClass = objc_getClass("MMMenuItem");
        if (MMMenuItemClass) {
            UIImage *scaleIcon = nil;
            if (@available(iOS 13.0, *)) {
                scaleIcon = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"];
            }
            MMMenuItem *scaleItem = nil;
            if (scaleIcon && [MMMenuItemClass instancesRespondToSelector:@selector(initWithTitle:icon:target:action:)]) {
                scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"调整大小" icon:scaleIcon target:self action:@selector(jj_showScaleOptions)];
            } else {
                scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"调整大小" target:self action:@selector(jj_showScaleOptions)];
            }
            if (scaleItem) [newItems addObject:scaleItem];
        }
        
        %orig(newItems);
    } else {
        %orig;
    }
}

- (void)hideMenu {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (jj_currentEmoticonView == nil) {
            jj_currentEmoticonMsgWrap = nil;
            jj_currentEmoticonImage = nil;
        }
    });
}

%new
- (void)jj_showScaleOptions {
    UIImage *emoticonImage = jj_currentEmoticonImage;
    if (!emoticonImage) return;
    
    Class MMMenuControllerClass = objc_getClass("MMMenuController");
    if (MMMenuControllerClass && [MMMenuControllerClass respondsToSelector:@selector(sharedInstance)]) {
        id menuController = [MMMenuControllerClass sharedInstance];
        if (menuController && [menuController respondsToSelector:@selector(hideMenu)]) {
            [menuController hideMenu];
        }
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        CGSize originalSize = emoticonImage.size;
        NSString *sizeInfo = [NSString stringWithFormat:@"原尺寸：%.0f×%.0f\n最大尺寸：300×300", originalSize.width, originalSize.height];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"调整表情大小" 
                                                                       message:sizeInfo 
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"🔍 放大 1.5 倍" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            jj_sendScaledEmoticon(emoticonImage, 1.5);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"🔎 放大 2.0 倍" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            jj_sendScaledEmoticon(emoticonImage, 2.0);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"🔻 缩小 0.7 倍" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            jj_sendScaledEmoticon(emoticonImage, 0.7);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"🔻 缩小 0.5 倍" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            jj_sendScaledEmoticon(emoticonImage, 0.5);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"✏️ 自定义比例" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            jj_showCustomScaleInput(emoticonImage, topVC);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            jj_currentEmoticonView = nil;
            jj_currentEmoticonMsgWrap = nil;
            jj_currentEmoticonImage = nil;
        }]];
        
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 0, 0);
        }
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

%end
