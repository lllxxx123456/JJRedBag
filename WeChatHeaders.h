#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>

// 微信基础类声明

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

@interface MMContext : NSObject
+ (id)currentContext;
- (MMServiceCenter *)serviceCenter;
@end

@interface CContact : NSObject
@property (nonatomic, copy) NSString *m_nsUsrName;
@property (nonatomic, copy) NSString *m_nsNickName;
@property (nonatomic, copy) NSString *m_nsHeadImgUrl;
@property (nonatomic, copy) NSString *m_nsRemark;
- (NSString *)getContactDisplayName;
- (BOOL)isChatroom;
- (BOOL)isBrandContact;
@end

@interface CContactMgr : NSObject
- (CContact *)getContactByName:(NSString *)userName;
- (CContact *)getSelfContact;
- (NSArray *)getContactList:(unsigned int)arg1 contactType:(unsigned int)arg2;
- (NSArray *)getContactsWithGroupScene:(int)scene;
- (NSArray *)getAllGroups;
- (NSArray *)getGroupContacts;
@end

@interface WCPayInfoItem : NSObject
@property (nonatomic, copy) NSString *m_c2cNativeUrl;
@property (nonatomic, copy) NSString *m_c2cSignature;
@property (nonatomic, assign) unsigned int m_uiPaySubType;
@property (nonatomic, copy) NSString *m_nsFeeDesc;
@property (nonatomic, copy) NSString *m_nsTransferID;
@property (nonatomic, copy) NSString *m_nsTranscationID;
@property (nonatomic, copy) NSString *m_total_fee;
@property (nonatomic, copy) NSString *transfer_payer_username;
@property (nonatomic, copy) NSString *transfer_receiver_username;
@property (nonatomic, assign) unsigned int m_c2cPayReceiveStatus;
@property (nonatomic, assign) unsigned int m_uiInvalidTime;
@property (nonatomic, assign) unsigned int m_uiBeginTransferTime;
@property (nonatomic, copy) NSString *m_payMemo;
@end

@interface CMessageWrap : NSObject
@property (nonatomic, copy) NSString *m_nsFromUsr;
@property (nonatomic, copy) NSString *m_nsToUsr;
@property (nonatomic, copy) NSString *m_nsRealChatUsr; // 群聊发送者
@property (nonatomic, copy) NSString *m_nsContent;
@property (nonatomic, assign) unsigned int m_uiMessageType;
@property (nonatomic, assign) unsigned int m_uiStatus;
@property (nonatomic, assign) unsigned int m_uiCreateTime;
@property (nonatomic, assign) unsigned int m_uiMesLocalID;
@property (nonatomic, assign) long long m_n64MesSvrID;
@property (nonatomic, strong) WCPayInfoItem *m_oWCPayInfoItem;
- (id)initWithMsgType:(long long)arg1;
+ (BOOL)isSenderFromMsgWrap:(id)msgWrap;
@end

@interface WCRedEnvelopesLogicMgr : NSObject
// 红包请求方法
- (void)OpenRedEnvelopesRequest:(id)arg1;
- (void)ReceiverQueryRedEnvelopesRequest:(id)arg1;
- (void)QueryRedEnvelopesDetailRequest:(id)arg1;
- (void)OpenOpenIMRedEnvelopesRequest:(id)arg1;
- (void)ReceiverQueryOpenIMRedEnvelopesRequest:(id)arg1;
- (void)GenRedEnvelopesPayRequest:(id)arg1;
// 红包响应回调
- (void)OnWCToHongbaoCommonResponse:(id)arg1 Request:(id)arg2;
- (void)OnWCToHongbaoCommonErrorResponse:(id)arg1 Request:(id)arg2;
- (void)OnWCToOpenIMHongbaoCommonResponse:(id)arg1 Request:(id)arg2;
- (void)OpenRedEnvelopesWithResponseDic:(id)arg1 withSign:(id)arg2;
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
// 消息添加
- (void)AddMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)AddLocalMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)AddEmoticonMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)onRevokeMsg:(CMessageWrap *)msgWrap;
// 消息接收 - FLEX确认存在
- (void)OnAddMessageByReceiver:(id)arg1;
- (void)onNewSyncAddMessage:(id)arg1;
// 异步消息处理
- (void)AsyncOnAddMsg:(id)arg1 MsgWrap:(id)arg2;
- (void)AsyncOnAddMsgForSession:(id)arg1 MsgWrap:(id)arg2;
- (void)AsyncOnAddMsgForSession:(id)arg1 MsgWrap:(id)arg2 NewMsgArriveNotify:(BOOL)arg3;
- (void)AsyncOnPreAddMsg:(id)arg1 MsgWrap:(id)arg2;
// JJRedBag插件添加的方法
- (void)jj_handleReceivedMessage:(CMessageWrap *)msgWrap;
- (void)jj_processRedBagMessage:(CMessageWrap *)msgWrap;
- (NSDictionary *)jj_parseNativeUrl:(NSString *)content;
- (NSString *)jj_parseRedBagTitle:(NSString *)content;
- (void)jj_openRedBagWithContext:(NSDictionary *)context;
- (void)jj_openRedBagWithNativeUrl:(NSString *)nativeUrl msgWrap:(CMessageWrap *)msgWrap isSelfRedBag:(BOOL)isSelfRedBag;
- (void)SendTextMessage:(NSString *)text toUsr:(NSString *)usr;
- (void)SendImgMessage:(id)arg1 toUsrName:(NSString *)userName thumbImgData:(NSData *)thumbData midImgData:(NSData *)midData imgData:(NSData *)imgData imgInfo:(id)imgInfo;
- (void)SendImageMessage:(NSData *)imageData toUsrName:(NSString *)userName;
- (void)jj_processTransferMessage:(CMessageWrap *)msgWrap;
- (void)jj_sendReceiveAutoReply:(NSDictionary *)params isGroup:(BOOL)isGroup;
- (void)jj_sendReceiveNotification:(NSDictionary *)params amount:(long long)amount;
- (void)jj_sendReceiveLocalNotification:(NSDictionary *)params amount:(long long)amount;
@end

@interface WCPayLogicMgr : NSObject
- (void)ConfirmTransferMoney:(id)arg1;
- (void)handleWCPayFacingReceiveMoneyMsg:(id)arg1 msgType:(int)arg2;
@end

@interface WCRedEnvelopesLogicMgr (JJRedBag)
- (void)jj_sendAutoReply:(id)param;
- (void)jj_sendNotification:(id)param amount:(long long)amount;
- (void)jj_sendLocalNotification:(id)param amount:(long long)amount;
- (NSString *)jj_getCurrentTime;
- (void)jj_sendMessage:(NSString *)content toUser:(NSString *)toUser;
@end

@interface CAppViewControllerManager : NSObject
+ (instancetype)getAppViewControllerManager;
- (void)jumpToChatRoom:(NSString *)usrName;
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
- (unsigned int)GenSendMsgTime;
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

@interface MMUIViewController : UIViewController
@end

@protocol ContactSelectViewDelegate <NSObject>
@optional
- (void)onSelectContact:(CContact *)contact;
- (void)onMultiSelectGroupCancel;
- (void)onMultiSelectGroupReturn:(NSArray *)arg1;
@end

@interface ContactsDataLogic : NSObject
@end

@protocol SessionSelectControllerDelegate <NSObject>
@optional
- (void)OnSelectSession:(CContact *)contact SessionSelectController:(id)controller;
- (void)OnSelectSessions:(NSArray<CContact *> *)sessions SessionSelectController:(id)controller;
@end

@interface SessionSelectController : MMUIViewController
@property (nonatomic, weak) id<SessionSelectControllerDelegate> m_delegate;
@property (nonatomic, assign) BOOL m_bMultiSelect;
@end

@interface ContactSelectView : UIView
@property (nonatomic, assign) BOOL m_bMultiSelect;
@property (nonatomic, assign) unsigned int m_uiGroupScene;
@property (nonatomic, assign) BOOL m_bShowHistoryGroup;
@property (nonatomic, assign) BOOL m_bShowRadarCreateRoom;
@property (nonatomic, assign) BOOL m_bShowContactTag;
@property (nonatomic, assign) BOOL m_bShowSelectFromGroup;
@property (nonatomic, strong) NSMutableDictionary *m_dicMultiSelect;
@property (nonatomic, strong) NSDictionary *m_dicExistContact;
@property (nonatomic, strong) NSDictionary *m_dicDisabledContact;
@property (nonatomic, strong) ContactsDataLogic *m_contactsDataLogic;

- (id)initWithFrame:(CGRect)frame delegate:(id)delegate;
- (void)initData:(unsigned int)arg1;
- (void)initView;
- (void)addSelect:(id)arg1;
- (void)removeSelect:(id)arg1;
- (BOOL)isSelected:(id)arg1;
- (NSUInteger)getTotalSelectCount;
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

// 表情包相关类
@interface MMEmoticonView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@end

@interface EmoticonMessageCellView : UIView
@property (nonatomic, strong) MMEmoticonView *emoticonView;
- (CMessageWrap *)getMessageWrap;
@end

@interface MMMenuController : UIViewController
@property (nonatomic, strong) NSArray *menuItems;
@property (nonatomic, weak) UIView *targetView;
+ (instancetype)sharedInstance;
- (void)setMenuItems:(NSArray *)items;
- (void)showMenuWithTargetRect:(CGRect)rect inView:(UIView *)view;
- (void)hideMenu;
@end

@interface MMMenuItem : NSObject
@property (nonatomic, strong) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, copy) id actionBlock;
@property (nonatomic, assign) NSInteger menuType;
@property (nonatomic, strong) UIImage *iconImage;
@property (nonatomic, strong) UIColor *titleColor;
@property (nonatomic, copy) NSString *subtitle;
- (instancetype)initWithTitle:(id)title target:(id)target action:(SEL)action;
- (instancetype)initWithTitle:(id)title icon:(id)icon target:(id)target action:(SEL)action;
- (instancetype)initWithType:(NSInteger)type target:(id)target action:(SEL)action;
@end
