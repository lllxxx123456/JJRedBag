#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>

// 微信基础类声明

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
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
@property (nonatomic, copy) NSString *m_fee_type;
@property (nonatomic, copy) NSString *transfer_payer_username;
@property (nonatomic, copy) NSString *transfer_receiver_username;
@property (nonatomic, copy) NSString *exclusive_recv_username;
@property (nonatomic, copy) NSString *transfer_attach;
@property (nonatomic, copy) NSString *routeInfo;
@property (nonatomic, assign) unsigned int has_transfer_address;
@property (nonatomic, assign) unsigned int m_c2cPayReceiveStatus;
@property (nonatomic, assign) unsigned int m_c2cPayBubbleType;
@property (nonatomic, assign) int bubble_click_flag;
@property (nonatomic, assign) unsigned int m_uiInvalidTime;
@property (nonatomic, assign) unsigned int m_uiBeginTransferTime;
@property (nonatomic, assign) unsigned int m_uiEffectiveDate;
@property (nonatomic, assign) unsigned int m_templateID;
@property (nonatomic, assign) unsigned int m_sceneId;
@property (nonatomic, assign) unsigned int m_c2c_msg_subtype;
@property (nonatomic, copy) NSString *m_payMemo;
@property (nonatomic, copy) NSString *m_nsPayMsgID;
@property (nonatomic, copy) NSString *m_receiverTitle;
@property (nonatomic, copy) NSString *m_senderTitle;
@property (nonatomic, copy) NSString *m_hintText;
@property (nonatomic, copy) NSString *m_receiverDesc;
@property (nonatomic, copy) NSString *m_senderDesc;
@property (nonatomic, copy) NSString *m_c2cUrl;
@property (nonatomic, copy) NSString *m_c2cIconUrl;
@end

@interface CMessageWrap : NSObject
@property (nonatomic, copy) NSString *m_nsFromUsr;
@property (nonatomic, copy) NSString *m_nsToUsr;
@property (nonatomic, copy) NSString *m_nsRealChatUsr;
@property (nonatomic, copy) NSString *m_nsContent;
@property (nonatomic, assign) unsigned int m_uiMessageType;
@property (nonatomic, assign) unsigned int m_uiStatus;
@property (nonatomic, assign) unsigned int m_uiCreateTime;
@property (nonatomic, assign) unsigned int m_uiMesLocalID;
@property (nonatomic, assign) long long m_n64MesSvrID;
@property (nonatomic, strong) WCPayInfoItem *m_oWCPayInfoItem;
@property (nonatomic, copy) NSString *m_nsEmoticonMD5;
@property (nonatomic, copy) NSString *m_nsThumbImgPath;
@property (nonatomic, copy) NSString *m_nsImgPath;
@property (nonatomic, strong) NSData *m_dtEmoticonData;
@property (nonatomic, assign) unsigned int m_uiGameType;
@property (nonatomic, assign) unsigned int m_uiGameContent;
- (id)initWithMsgType:(long long)arg1;
+ (BOOL)isSenderFromMsgWrap:(id)msgWrap;
@end

@interface GameController : NSObject
+ (NSString *)getMD5ByGameContent:(int)content;
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

@interface WCBizUtil : NSObject
+ (id)dictionaryWithDecodedComponets:(NSString *)str separator:(NSString *)sep;
@end

@interface CMessageMgr : NSObject
- (void)AddMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)AddEmoticonMsg:(NSString *)userName MsgWrap:(CMessageWrap *)msgWrap;
- (void)OnAddMessageByReceiver:(id)arg1;
- (void)onNewSyncAddMessage:(id)arg1;
- (void)SendTextMessage:(NSString *)text toUsr:(NSString *)usr;
- (void)batchForwardMessage:(id)msgList toUserArray:(id)userArray;
// JJRedBag插件方法
- (void)jj_handleReceivedMessage:(CMessageWrap *)msgWrap;
- (void)jj_processRedBagMessage:(CMessageWrap *)msgWrap;
- (void)jj_processTransferMessage:(CMessageWrap *)msgWrap;
- (NSDictionary *)jj_parseNativeUrl:(NSString *)content;
- (NSString *)jj_parseRedBagTitle:(NSString *)content;
- (void)jj_openRedBagWithContext:(NSDictionary *)context;
- (void)jj_sendReceiveAutoReply:(NSDictionary *)params isGroup:(BOOL)isGroup;
- (void)jj_sendReceiveNotification:(NSDictionary *)params amount:(long long)amount;
- (void)jj_sendReceiveLocalNotification:(NSDictionary *)params amount:(long long)amount;
@end

@interface WCRedEnvelopesLogicMgr (JJRedBag)
- (void)jj_sendAutoReply:(id)param;
- (void)jj_sendNotification:(id)param amount:(long long)amount;
- (void)jj_sendLocalNotification:(id)param amount:(long long)amount;
+ (unsigned int)jj_generateSendMsgTime;
- (NSString *)jj_getCurrentTime;
- (void)jj_sendMessage:(NSString *)content toUser:(NSString *)toUser;
@end

// 转账收款请求对象
@interface WCPayConfirmTransferRequest : NSObject
@property (nonatomic, copy) NSString *m_nsTransferID;
@property (nonatomic, copy) NSString *m_nsFromUserName;
@property (nonatomic, assign) unsigned int m_uiInvalidTime;
@property (nonatomic, copy) NSString *group_username;
@property (nonatomic, assign) int groupType;
@property (nonatomic, assign) int recv_channel_type;
@property (nonatomic, assign) int sub_recv_channel_id;
@property (nonatomic, copy) NSString *m_nsTransferAttach;
@property (nonatomic, copy) NSString *bind_serial;
@end

@interface WCPayLogicMgr : NSObject
- (void)ConfirmTransferMoney:(id)arg1;
- (void)handleWCPayFacingReceiveMoneyMsg:(id)arg1 msgType:(int)arg2;
- (void)CheckTransferMoneyStatus:(id)arg1;
- (void)OnGetNewXmlMsg:(id)arg1 Type:(id)arg2 MsgWrap:(id)arg3;
@end

@interface CAppViewControllerManager : NSObject
+ (instancetype)getAppViewControllerManager;
- (void)jumpToChatRoom:(NSString *)usrName;
@end

@interface MMNewSessionMgr : NSObject
- (unsigned int)GenSendMsgTime;
@end

@interface MMTableViewInfo : NSObject
- (UITableView *)getTableView;
@end

@interface MMTableViewCell : UITableViewCell
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

// AppDelegate
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
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

@interface CommonMessageCellView : UIView
@property (readonly, nonatomic) id viewModel;
- (id)operationMenuItems;
- (id)filteredMenuItems:(id)items;
- (void)onLongTouch;
- (struct CGRect)showRectForMenuController;
- (id)getViewController;
- (id)getMsgCmessageWrap;
- (void)jj_onPlusOne;
- (void)jj_showPlusOneUnsupported:(NSString *)reason;
@end

@interface CommonMessageViewModel : NSObject
@property (nonatomic, strong) CMessageWrap *messageWrap;
@property (nonatomic, strong) CContact *contact;
@property (nonatomic, strong) CContact *chatContact;
@end

@interface MMEmoticonView : UIView
@end

@interface EmoticonMessageViewModel : CommonMessageViewModel
@end

@interface EmoticonMessageCellView : CommonMessageCellView
@property (readonly, nonatomic) EmoticonMessageViewModel *viewModel;
@property (nonatomic, strong) MMEmoticonView *m_emoticonView;
- (id)operationMenuItems;
- (id)filteredMenuItems:(id)items;
- (void)onLongTouch;
@end

@interface BaseMsgContentViewController : UIViewController
- (NSString *)getChatUsername;
- (id)GetContact;
- (id)GetCContact;
- (void)SendEmoticonMesssageToolView:(id)arg1;
@end

@interface CEmoticonWrap : NSObject
@property (nonatomic) unsigned int m_uiType;
@property (nonatomic) unsigned int m_uiGameType;
@property (retain, nonatomic) NSString *m_nsAppID;
@property (retain, nonatomic) NSString *m_nsThumbImgPath;
@property (retain, nonatomic) NSData *m_imageData;
@property (nonatomic) unsigned int m_extFlag;
@end

@interface CEmoticonMgr : NSObject
+ (id)GetEmoticonByMD5:(id)md5;
+ (id)getEmoticonImageByMD5:(id)md5;
+ (id)emoticonMsgForImageData:(id)data errorMsg:(id *)errorMsg;
- (id)getEmoticonWrapByMd5:(id)md5;
@end

@interface MMMenuController : UIViewController
@property (nonatomic, strong) NSArray *menuItems;
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, getter=isMenuVisible) BOOL menuVisible;
+ (id)sharedMenuController;
- (void)setMenuItems:(NSArray *)items;
- (void)setMenuVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setTargetRect:(CGRect)rect inView:(UIView *)view;
@end

// 微信自定义Label
@interface MMUILabel : UILabel
@end

// 转账收款状态页面控制器
@interface WCPayTransferMoneyStatusViewController : UIViewController
- (void)OnConfirmTransferMoneyBtnDone;
@end

// 微信自定义按钮
@interface FixTitleColorButton : UIButton
@end

// 小程序WebView控制器
@interface WAWebViewController : UIViewController
@property (nonatomic, assign) BOOL m_isFinishLoaded;
@property (nonatomic, assign) NSInteger preloadFinishTimeInMs;
- (void)onGameRewards;
- (BOOL)canShowGameRewardsItem;
- (void)finishLoadAction;
@end

// 搜索界面语音输入浮窗
@interface FTSFloatingVoiceInputView : UIView
@end

// 转发/分享视图控制器（发布朋友圈等）
@interface WCForwardViewController : UIViewController
@end

@interface MMMenuItem : UIMenuItem
@property (nonatomic, strong) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, copy) id actionBlock;
@property (nonatomic, assign) NSInteger menuType;
@property (nonatomic, strong) UIImage *iconImage;
@property (nonatomic, strong) UIColor *titleColor;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) id userInfo;
- (id)initWithTitle:(id)title target:(id)target action:(SEL)action;
- (id)initWithTitle:(id)title icon:(id)icon target:(id)target action:(SEL)action;
- (id)initWithTitle:(id)title svgName:(id)svgName target:(id)target action:(SEL)action;
- (id)initWithType:(NSInteger)type target:(id)target action:(SEL)action;
@end
