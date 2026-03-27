#import "WeChatHeaders.h"
#import "JJRedBagManager.h"
#import "JJRedBagSettingsController.h"
#import "JJRedBagParam.h"
#import <UserNotifications/UserNotifications.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>

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

static CMessageWrap *jj_clonePlusOneMessageWrap(CMessageWrap *sourceMsgWrap, NSString *fromUser, NSString *toUser);

// 缩放并发送表情包：克隆原始消息（和+1完全一样），修改XML中的width/height实现缩放
static void jj_scaleAndSendEmoticon(CGFloat scaleFactor, UIView *sourceView) {
    NSString *toUserName = [jj_currentChatUserName copy];
    CMessageWrap *origMsgWrap = jj_currentEmoticonMsgWrap;
    
    if (!toUserName || toUserName.length == 0 || !origMsgWrap) return;
    
    @try {
        CMessageMgr *msgMgr = jj_getService(objc_getClass("CMessageMgr"));
        if (!msgMgr) return;
        
        CContactMgr *contactMgr = jj_getService(objc_getClass("CContactMgr"));
        NSString *selfUserName = [[contactMgr getSelfContact] m_nsUsrName];
        
        // 和+1复读完全相同：克隆原始消息
        CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(origMsgWrap, selfUserName, toUserName);
        if (!newWrap) return;
        
        // 修改XML中的width/height实现缩放
        NSString *content = newWrap.m_nsContent;
        if (content && content.length > 0) {
            NSMutableString *newContent = [content mutableCopy];
            
            // 替换 cdnimgwidth="xxx" 为缩放后的值
            NSRegularExpression *wRegex = [NSRegularExpression regularExpressionWithPattern:@"cdnimgwidth=\"(\\d+)\"" options:0 error:nil];
            NSTextCheckingResult *wMatch = [wRegex firstMatchInString:newContent options:0 range:NSMakeRange(0, newContent.length)];
            if (wMatch && wMatch.numberOfRanges > 1) {
                unsigned int origW = [[newContent substringWithRange:[wMatch rangeAtIndex:1]] intValue];
                unsigned int newW = (unsigned int)(origW * scaleFactor);
                if (newW < 10) newW = 10;
                [newContent replaceCharactersInRange:[wMatch range] withString:[NSString stringWithFormat:@"cdnimgwidth=\"%u\"", newW]];
            }
            
            // 替换 cdnimgheight="xxx" 为缩放后的值
            NSRegularExpression *hRegex = [NSRegularExpression regularExpressionWithPattern:@"cdnimgheight=\"(\\d+)\"" options:0 error:nil];
            NSTextCheckingResult *hMatch = [hRegex firstMatchInString:newContent options:0 range:NSMakeRange(0, newContent.length)];
            if (hMatch && hMatch.numberOfRanges > 1) {
                unsigned int origH = [[newContent substringWithRange:[hMatch rangeAtIndex:1]] intValue];
                unsigned int newH = (unsigned int)(origH * scaleFactor);
                if (newH < 10) newH = 10;
                [newContent replaceCharactersInRange:[hMatch range] withString:[NSString stringWithFormat:@"cdnimgheight=\"%u\"", newH]];
            }
            
            newWrap.m_nsContent = newContent;
        }
        
        [msgMgr AddEmoticonMsg:toUserName MsgWrap:newWrap];
        
    } @catch (NSException *exception) {}
    
    // 清理
    jj_currentEmoticonMsgWrap = nil;
    jj_currentChatUserName = nil;
    jj_currentSourceView = nil;
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

%hook CommonMessageCellView

- (id)filteredMenuItems:(id)items {
    id result = %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled) return result;
    if (![result isKindOfClass:[NSArray class]]) return result;
    
    if (!manager.plusOneEnabled) return result;
    
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
    if (!msgWrap) return result; // 获取不到消息不显示+1
    
    unsigned int msgType = msgWrap.m_uiMessageType;
    // 只有对应子开关开启时才显示+1
    BOOL shouldShow = NO;
    if (msgType == 1 && manager.plusOneTextEnabled) shouldShow = YES;
    if (msgType == 47 && manager.plusOneEmoticonEnabled) shouldShow = YES;
    if (msgType == 3 && manager.plusOneImageEnabled) shouldShow = YES;
    if (msgType == 43 && manager.plusOneVideoEnabled) shouldShow = YES;
    if (msgType == 49 && manager.plusOneFileEnabled) shouldShow = YES;
    if (!shouldShow) return result;
    
    NSMutableArray *newItems = [NSMutableArray arrayWithArray:result];
    id plusOneItem = nil;
    Class MMMenuItemClass = objc_getClass("MMMenuItem");
    if (MMMenuItemClass) {
        @try {
            plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" svgName:@"icons_outlined_copy" target:self action:@selector(jj_onPlusOne)];
        } @catch (NSException *e) {}
        if (!plusOneItem) {
            @try {
                plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" target:self action:@selector(jj_onPlusOne)];
            } @catch (NSException *e) {}
        }
        if (!plusOneItem) {
            @try {
                plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" icon:nil target:self action:@selector(jj_onPlusOne)];
            } @catch (NSException *e) {}
        }
    }
    // 最终回退：使用标准UIMenuItem
    if (!plusOneItem) {
        @try {
            plusOneItem = [[UIMenuItem alloc] initWithTitle:@"+1" action:@selector(jj_onPlusOne)];
        } @catch (NSException *e) {}
    }
    if (plusOneItem) {
        if (newItems.count >= 1) {
            [newItems insertObject:plusOneItem atIndex:1];
        } else {
            [newItems addObject:plusOneItem];
        }
    }
    return newItems;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(jj_onPlusOne)) {
        JJRedBagManager *m = [JJRedBagManager sharedManager];
        if (!m.plusOneEnabled) return NO;
        CMessageWrap *msgWrap = nil;
        if ([self respondsToSelector:@selector(getMsgCmessageWrap)]) msgWrap = [self performSelector:@selector(getMsgCmessageWrap)];
        if (!msgWrap && [self respondsToSelector:@selector(getMessageWrap)]) msgWrap = [self performSelector:@selector(getMessageWrap)];
        if (!msgWrap) {
            id vm = nil;
            if ([self respondsToSelector:@selector(viewModel)]) vm = [self performSelector:@selector(viewModel)];
            if (vm && [vm respondsToSelector:@selector(messageWrap)]) msgWrap = [vm performSelector:@selector(messageWrap)];
        }
        if (!msgWrap) return NO;
        unsigned int t = msgWrap.m_uiMessageType;
        if (t == 1) return m.plusOneTextEnabled;
        if (t == 47) return m.plusOneEmoticonEnabled;
        if (t == 3) return m.plusOneImageEnabled;
        if (t == 43) return m.plusOneVideoEnabled;
        if (t == 49) return m.plusOneFileEnabled;
        return NO;
    }
    return %orig;
}

%new
- (void)jj_onPlusOne {
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
            [self jj_showPlusOneUnsupported:unsupportedReason];
            return;
        }
        
        id serviceCenter = jj_getServiceCenter();
        if (!serviceCenter) {
            [self jj_showPlusOneUnsupported:@"服务中心获取失败"];
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
                [self jj_showPlusOneUnsupported:@"文本内容为空"];
                return;
            }
            CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(msgWrap, selfUserName, chatUserName);
            if (newWrap) {
                [msgMgr AddMsg:chatUserName MsgWrap:newWrap];
            }
            return;
        }
        
        // === 表情包消息 ===
        if (msgType == 47) {
            CMessageWrap *newWrap = jj_clonePlusOneMessageWrap(msgWrap, selfUserName, chatUserName);
            if (newWrap) {
                [msgMgr AddEmoticonMsg:chatUserName MsgWrap:newWrap];
            }
            return;
        }
        
        // === 图片/视频/文件等媒体消息：使用ForwardMsgUtil转发 ===
        CContact *chatContact = [contactMgr getContactByName:chatUserName];
        if (!chatContact) {
            [self jj_showPlusOneUnsupported:@"获取联系人失败"];
            return;
        }
        
        Class forwardUtilCls = objc_getClass("ForwardMsgUtil");
        if (!forwardUtilCls) {
            [self jj_showPlusOneUnsupported:@"转发工具不可用"];
            return;
        }
        
        BOOL sent = NO;
        
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
        
        if (!sent) {
            [self jj_showPlusOneUnsupported:[NSString stringWithFormat:@"不支持+1（type=%u）", msgType]];
        }
    } @catch (NSException *exception) {}
}

%new
- (void)jj_showPlusOneUnsupported:(NSString *)reason {
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

// Hook表情消息Cell - 通过filteredMenuItems添加"调整大小"菜单项
%hook EmoticonMessageCellView

- (id)filteredMenuItems:(id)items {
    id result = %orig;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled) return result;
    if (![result isKindOfClass:[NSArray class]]) return result;
    
    NSMutableArray *newItems = [NSMutableArray arrayWithArray:result];
    Class MMMenuItemClass = objc_getClass("MMMenuItem");
    
    // 检查+1是否已由父类hook添加，避免重复
    if (manager.plusOneEnabled && manager.plusOneEmoticonEnabled) {
        BOOL hasPlusOne = NO;
        for (id item in newItems) {
            if ([item respondsToSelector:@selector(title)] && [[item title] isEqualToString:@"+1"]) {
                hasPlusOne = YES;
                break;
            }
        }
        if (!hasPlusOne) {
            id plusOneItem = nil;
            if (MMMenuItemClass) {
                @try {
                    plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" svgName:@"icons_outlined_copy" target:self action:@selector(jj_onPlusOne)];
                } @catch (NSException *e) {}
                if (!plusOneItem) {
                    @try {
                        plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" target:self action:@selector(jj_onPlusOne)];
                    } @catch (NSException *e) {}
                }
                if (!plusOneItem) {
                    @try {
                        plusOneItem = [[MMMenuItemClass alloc] initWithTitle:@"+1" icon:nil target:self action:@selector(jj_onPlusOne)];
                    } @catch (NSException *e) {}
                }
            }
            if (!plusOneItem) {
                @try {
                    plusOneItem = [[UIMenuItem alloc] initWithTitle:@"+1" action:@selector(jj_onPlusOne)];
                } @catch (NSException *e) {}
            }
            if (plusOneItem) {
                if (newItems.count >= 1) {
                    [newItems insertObject:plusOneItem atIndex:1];
                } else {
                    [newItems addObject:plusOneItem];
                }
            }
        }
    }
    
    // 大大小小菜单项（仅在表情缩放开关开启时添加）
    if (manager.emoticonScaleEnabled) {
        id scaleItem = nil;
        if (MMMenuItemClass) {
            @try {
                scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" svgName:@"icons_outlined_sticker" target:self action:@selector(jj_onEmoticonResize)];
            } @catch (NSException *e) {}
            if (!scaleItem) {
                @try {
                    scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" target:self action:@selector(jj_onEmoticonResize)];
                } @catch (NSException *e) {}
            }
            if (!scaleItem) {
                @try {
                    scaleItem = [[MMMenuItemClass alloc] initWithTitle:@"大大小小" icon:nil target:self action:@selector(jj_onEmoticonResize)];
                } @catch (NSException *e) {}
            }
        }
        if (!scaleItem) {
            @try {
                scaleItem = [[UIMenuItem alloc] initWithTitle:@"大大小小" action:@selector(jj_onEmoticonResize)];
            } @catch (NSException *e) {}
        }
        if (scaleItem) [newItems addObject:scaleItem];
    }
    return newItems;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(jj_onPlusOne)) {
        return [[JJRedBagManager sharedManager] plusOneEnabled];
    }
    if (action == @selector(jj_onEmoticonResize)) {
        return [[JJRedBagManager sharedManager] emoticonScaleEnabled];
    }
    return %orig;
}

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
