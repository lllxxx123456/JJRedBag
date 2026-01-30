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
@property (nonatomic, assign) BOOL shakeToConfigEnabled;       // 摇一摇呼出配置开关

// 自动回复设置
@property (nonatomic, assign) BOOL autoReplyEnabled;             // 自动回复总开关
@property (nonatomic, assign) BOOL autoReplyPrivateEnabled;      // 私聊自动回复
@property (nonatomic, assign) BOOL autoReplyGroupEnabled;        // 群聊自动回复
@property (nonatomic, assign) BOOL autoReplyDelayEnabled;        // 延迟回复开关
@property (nonatomic, assign) NSTimeInterval autoReplyDelayTime; // 延迟回复时间(0-30s)
@property (nonatomic, copy) NSString *autoReplyContent;          // 自动回复内容

// 红包通知设置
@property (nonatomic, assign) BOOL notificationEnabled;          // 通知功能总开关
@property (nonatomic, copy) NSString *notificationChatId;        // 通知发送到的会话ID
@property (nonatomic, copy) NSString *notificationChatName;      // 通知发送到的会话名称(用于显示)

@property (nonatomic, strong) NSMutableDictionary *pendingRedBags; // 待处理红包字典 key: sendId

+ (instancetype)sharedManager;

- (void)saveSettings;
- (void)loadSettings;

- (BOOL)shouldGrabRedBagInChat:(NSString *)chatId isGroup:(BOOL)isGroup;
- (BOOL)shouldFilterByKeyword:(NSString *)redBagTitle;
- (NSTimeInterval)getDelayTimeForChat:(NSString *)chatId;

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion;
- (void)showSettingsController;

@end
