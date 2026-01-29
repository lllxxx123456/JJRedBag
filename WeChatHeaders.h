#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 微信基础类声明

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

@interface CContact : NSObject
- (NSString *)m_nsUsrName;
- (NSString *)m_nsNickName;
- (NSString *)m_nsHeadImgUrl;
- (NSString *)getContactDisplayName;
- (BOOL)isChatroom;
- (BOOL)isGroup;
@end

@interface CContactMgr : NSObject
- (CContact *)getContactByName:(NSString *)userName;
- (CContact *)getSelfContact;
- (NSArray *)getContactsWithGroupScene:(int)scene;
- (NSArray *)getAllGroups;
- (NSArray *)getGroupContacts;
- (id)getGroupCardMemberList:(id)arg1;
- (BOOL)isChatRoomMember:(id)arg1;
@end

@interface WCPayInfoItem : NSObject
@property (nonatomic, copy) NSString *m_c2cNativeUrl;
@property (nonatomic, copy) NSString *m_c2cSignature;
@end

@interface CMessageWrap : NSObject
@property (nonatomic, copy) NSString *m_nsFromUsr;
@property (nonatomic, copy) NSString *m_nsToUsr;
@property (nonatomic, copy) NSString *m_nsContent;
@property (nonatomic, assign) unsigned int m_uiMessageType;
@property (nonatomic, assign) unsigned int m_uiStatus;
@property (nonatomic, assign) int m_nMsgCreateTime;
@property (nonatomic, strong) WCPayInfoItem *m_oWCPayInfoItem;
- (NSString *)m_nsFromUsr;
- (NSString *)m_nsToUsr;
- (NSString *)m_nsContent;
- (unsigned int)m_uiMessageType;
- (WCPayInfoItem *)m_oWCPayInfoItem;
@end

@interface WCRedEnvelopesLogicMgr : NSObject
- (void)OpenRedEnvelopesRequest:(id)arg1;
- (void)ReceiverQueryRedEnvelopesRequest:(id)arg1;
@end

@interface WCRedEnvelopesControlMgr : NSObject
- (void)startReceiveRedEnvelopesLogic:(id)arg1 Data:(id)arg2;
- (void)startReceiveRedEnvelopesLogic:(id)arg1 Data:(id)arg2 Scene:(unsigned int)arg3;
- (void)startOpenRedEnvelopesDetail:(id)arg1 sendId:(id)arg2 hbKind:(int)arg3 receiveId:(id)arg4;
- (void)startSystemMessageControlLogic:(id)arg1 NativeUrl:(id)arg2 messageWrap:(id)arg3;
@end

@interface WCBizUtil : NSObject
+ (id)dictionaryWithDecodedComponets:(NSString *)str separator:(NSString *)sep;
@end

@interface CMessageMgr : NSObject
- (void)AddLocalMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)AddEmoticonMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)onRevokeMsg:(CMessageWrap *)msgWrap;
- (void)OnAddMessageByReceiver:(id)arg1;
- (void)onNewSyncAddMessage:(id)arg1;
- (id)getRedPacketMessageInSession:(id)arg1 NewerThan:(id)arg2;
@end

@interface WCRedEnvelopesReceiveHomeView : UIView
@property (nonatomic, weak) id delegate;
@end

@interface WCRedEnvelopesReceiveControlLogic : NSObject
@property (nonatomic, strong) NSDictionary *m_dicBaseInfo;
@property (nonatomic, copy) NSString *m_nsNativeUrl;
- (void)OnReceiveOpenRedEnvelopes:(NSDictionary *)info;
- (void)OnReceiveQueryRedEnvelopes:(NSDictionary *)info;
- (void)OpenRedEnvelopes;
- (void)queryRedEnvelopes;
@end

@interface MMNewSessionMgr : NSObject
@end

@interface MMMsgLogicManager : NSObject
@end

@interface WeixinContentLogicController : NSObject
@property (nonatomic, strong) CContact *m_contact;
@end

@interface MMTableViewInfo : NSObject
- (UITableView *)getTableView;
@end

@interface MMTableViewCellInfo : NSObject
+ (instancetype)switchCellForSel:(SEL)sel target:(id)target title:(NSString *)title on:(BOOL)on;
+ (instancetype)normalCellForSel:(SEL)sel target:(id)target title:(NSString *)title accessoryType:(long long)type;
+ (instancetype)normalCellForSel:(SEL)sel target:(id)target title:(NSString *)title rightValue:(NSString *)value accessoryType:(long long)type;
@end

@interface MMTableViewSectionInfo : NSObject
+ (instancetype)sectionInfoHeader:(NSString *)header;
+ (instancetype)sectionInfoDefaut;
- (void)addCell:(MMTableViewCellInfo *)cellInfo;
@end

@interface NewSettingViewController : UIViewController
@property (nonatomic, strong) MMTableViewInfo *m_tableViewInfo;
- (void)reloadTableData;
@end

// 抢红包相关的数据结构
@interface WCRedEnvelopesControlData : NSObject
@property (nonatomic, copy) NSString *m_oSelectedMessageWrap;
@property (nonatomic, copy) NSString *m_nativeUrl;
@property (nonatomic, strong) NSDictionary *m_baseInfo;
@property (nonatomic, copy) NSString *m_sendId;
@property (nonatomic, copy) NSString *m_channelId;
@property (nonatomic, copy) NSString *m_msgType;
@end

// AppDelegate
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

// 后台任务
@interface MMBackgroundTaskMgr : NSObject
+ (instancetype)sharedInstance;
- (void)startBackgroundTask;
- (void)endBackgroundTask;
@end

// 通知
@interface MMNotificationCenterUtil : NSObject
+ (void)postNotificationName:(NSString *)name userInfo:(NSDictionary *)info;
@end

// NSDictionary安全取值扩展
@interface NSDictionary (SafeValue)
- (NSString *)stringForKey:(id)key;
@end

// 红包请求/响应类
@interface SKBuiltinBuffer_t : NSObject
@property (retain, nonatomic) NSData *buffer;
@end

@interface HongBaoRes : NSObject
@property (retain, nonatomic) SKBuiltinBuffer_t *retText;
@property (nonatomic) int cgiCmdid;
@end

@interface HongBaoReq : NSObject
@property (retain, nonatomic) SKBuiltinBuffer_t *reqText;
@end

// NSString JSON扩展
@interface NSString (SBJSON)
- (id)JSONDictionary;
@end
