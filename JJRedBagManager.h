#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, JJGrabMode) {
    JJGrabModeNone = 0,        // 未选择模式
    JJGrabModeExclude = 1,     // 不抢群模式
    JJGrabModeOnly = 2,        // 只抢群模式
    JJGrabModeDelay = 3        // 延迟抢模式
};

typedef NS_ENUM(NSInteger, JJDelayOtherMode) {
    JJDelayOtherModeNoDelay = 0,   // 其余无延迟抢
    JJDelayOtherModeNoGrab = 1     // 其余直接不抢
};

typedef NS_ENUM(NSInteger, JJBackgroundMode) {
    JJBackgroundModeTimer = 0,     // 定时刷新（省电模式）
    JJBackgroundModeAudio = 1      // 无声音频（强力模式）
};

@interface JJRedBagManager : NSObject

@property (nonatomic, assign) BOOL enabled;                    // 总开关
@property (nonatomic, assign) BOOL hasShownDisclaimer;         // 是否已显示免责声明
@property (nonatomic, assign) JJGrabMode grabMode;             // 抢红包模式
@property (nonatomic, assign) JJDelayOtherMode delayOtherMode; // 延迟模式下其余群的处理方式
@property (nonatomic, assign) NSTimeInterval delayTime;        // 延迟时间（秒）

@property (nonatomic, strong) NSMutableArray *excludeGroups;   // 不抢群列表
@property (nonatomic, strong) NSMutableArray *onlyGroups;      // 只抢群列表
@property (nonatomic, strong) NSMutableArray *delayGroups;     // 延迟抢群列表

@property (nonatomic, assign) BOOL filterKeywordEnabled;       // 过滤关键词开关
@property (nonatomic, strong) NSMutableArray *filterKeywords;  // 过滤关键词列表

@property (nonatomic, assign) BOOL grabSelfEnabled;            // 抢自己发的红包
@property (nonatomic, assign) BOOL grabPrivateEnabled;         // 抢私信红包
@property (nonatomic, assign) BOOL backgroundGrabEnabled;      // 后台和锁屏自动抢
@property (nonatomic, assign) JJBackgroundMode backgroundMode; // 后台保活模式
@property (nonatomic, assign) BOOL shakeToConfigEnabled;       // 摇一摇呼出配置开关

// 自动回复设置
@property (nonatomic, assign) BOOL autoReplyEnabled;             // 自动回复总开关
@property (nonatomic, assign) BOOL autoReplyPrivateEnabled;      // 私聊自动回复
@property (nonatomic, assign) BOOL autoReplyGroupEnabled;        // 群聊自动回复
@property (nonatomic, assign) BOOL autoReplyDelayEnabled;        // 延迟回复开关
@property (nonatomic, assign) NSTimeInterval autoReplyDelayTime; // 延迟回复时间(0-30s)
@property (nonatomic, copy) NSString *autoReplyContent;          // 自动回复内容

// 红包通知设置
@property (nonatomic, assign) BOOL notificationEnabled;          // 消息通知总开关 (发消息给指定人)
@property (nonatomic, assign) BOOL localNotificationEnabled;     // 本地通知开关 (弹窗)
@property (nonatomic, copy) NSString *notificationChatId;        // 通知发送到的会话ID
@property (nonatomic, copy) NSString *notificationChatName;      // 通知发送到的会话名称
@property (nonatomic, assign) long long totalAmount;             // 累计抢到金额(分)

@property (nonatomic, strong) NSMutableDictionary *pendingRedBags; // 待处理红包字典 key: sendId

// ========== 自动收款设置 ==========
@property (nonatomic, assign) BOOL autoReceivePrivateEnabled;     // 私聊自动收款
@property (nonatomic, assign) BOOL autoReceiveGroupEnabled;       // 群聊自动收款
@property (nonatomic, strong) NSMutableDictionary *groupReceiveMembers; // 群聊指定收款群员 {groupId: [memberIds]}

// 收款自动回复
@property (nonatomic, assign) BOOL receiveAutoReplyPrivateEnabled;  // 私聊收款后自动回复
@property (nonatomic, assign) BOOL receiveAutoReplyGroupEnabled;    // 群聊收款后自动回复
@property (nonatomic, copy) NSString *receiveAutoReplyContent;      // 收款自动回复内容

// 收款通知
@property (nonatomic, assign) BOOL receiveNotificationEnabled;      // 收款消息通知
@property (nonatomic, assign) BOOL receiveLocalNotificationEnabled; // 收款本地弹窗通知
@property (nonatomic, copy) NSString *receiveNotificationChatId;    // 收款通知发送到的会话ID
@property (nonatomic, copy) NSString *receiveNotificationChatName;  // 收款通知发送到的会话名称
@property (nonatomic, assign) long long totalReceiveAmount;         // 累计收款金额(分)

// 收款群聊列表(独立于抢红包)
@property (nonatomic, strong) NSMutableArray *receiveGroups;        // 收款群聊列表

// ========== 消息+1(复读机)功能 ==========
@property (nonatomic, assign) BOOL plusOneEnabled;                  // 消息+1(复读机)总开关
@property (nonatomic, assign) BOOL plusOneTextEnabled;              // 文字+1
@property (nonatomic, assign) BOOL plusOneEmoticonEnabled;          // 表情包+1
@property (nonatomic, assign) BOOL plusOneImageEnabled;             // 照片+1
@property (nonatomic, assign) BOOL plusOneVideoEnabled;             // 视频+1
@property (nonatomic, assign) BOOL plusOneFileEnabled;              // 文件+1

// ========== 表情包缩放功能 ==========
@property (nonatomic, assign) BOOL emoticonScaleEnabled;            // 表情包缩放功能开关

// ========== 界面优化功能 ==========
@property (nonatomic, assign) BOOL hideVoiceSearchButton;           // 隐藏语音搜索按钮
@property (nonatomic, assign) BOOL hideLastGroupLabel;              // 隐藏上次分组标签
@property (nonatomic, assign) BOOL hasShownHideVoiceAlert;          // 是否已显示隐藏语音搜索说明
@property (nonatomic, assign) BOOL hasShownHideGroupAlert;          // 是否已显示隐藏上次分组说明

// ========== 小游戏作弊功能 ==========
@property (nonatomic, assign) BOOL gameCheatEnabled;                // 小游戏作弊开关
@property (nonatomic, assign) NSInteger gameCheatMode;              // 0=模式1(发送时选择), 1=模式2(预设序列)
@property (nonatomic, copy) NSString *gameCheatDiceSequence;        // 骰子预设序列(如"223"表示依次2,2,3)
@property (nonatomic, copy) NSString *gameCheatRPSSequence;         // 猜拳预设序列(1=剪刀,2=石头,3=布,如"132")
@property (nonatomic, assign) NSInteger gameCheatDiceIndex;         // 骰子当前序列位置
@property (nonatomic, assign) NSInteger gameCheatRPSIndex;          // 猜拳当前序列位置
@property (nonatomic, assign) BOOL hasShownGameCheatAlert;          // 是否已显示游戏作弊说明

// ========== 广告跳过功能 ==========
@property (nonatomic, assign) BOOL adSkipEnabled;                  // 广告跳过开关
@property (nonatomic, assign) BOOL hasShownAdSkipAlert;            // 是否已显示广告跳过说明

+ (instancetype)sharedManager;

- (void)saveSettings;
- (void)loadSettings;

- (BOOL)shouldGrabRedBagInChat:(NSString *)chatId isGroup:(BOOL)isGroup;
- (BOOL)shouldFilterByKeyword:(NSString *)redBagTitle;
- (NSTimeInterval)getDelayTimeForChat:(NSString *)chatId;

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion;
- (void)showSettingsController;

@end
