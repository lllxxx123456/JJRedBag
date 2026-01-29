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

+ (instancetype)sharedManager;

- (void)saveSettings;
- (void)loadSettings;

- (BOOL)shouldGrabRedBagInChat:(NSString *)chatId isGroup:(BOOL)isGroup;
- (BOOL)shouldFilterByKeyword:(NSString *)redBagTitle;
- (NSTimeInterval)getDelayTimeForChat:(NSString *)chatId;

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion;
- (void)showSettingsController;

@end
