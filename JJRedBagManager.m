#import "JJRedBagManager.h"
#import "JJRedBagSettingsController.h"

#define kSettingsPath @"/var/mobile/Library/Preferences/com.jj.redbag.plist"

@implementation JJRedBagManager

+ (instancetype)sharedManager {
    static JJRedBagManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[JJRedBagManager alloc] init];
        [manager loadSettings];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        _enabled = NO;
        _hasShownDisclaimer = NO;
        _grabMode = JJGrabModeNone;
        _delayOtherMode = JJDelayOtherModeNoDelay;
        _delayTime = 1.0;
        _excludeGroups = [NSMutableArray array];
        _onlyGroups = [NSMutableArray array];
        _delayGroups = [NSMutableArray array];
        _filterKeywordEnabled = NO;
        _filterKeywords = [NSMutableArray array];
        _grabSelfEnabled = NO;
        _grabPrivateEnabled = NO;
        _backgroundGrabEnabled = NO;
    }
    return self;
}

- (void)saveSettings {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    settings[@"enabled"] = @(self.enabled);
    settings[@"hasShownDisclaimer"] = @(self.hasShownDisclaimer);
    settings[@"grabMode"] = @(self.grabMode);
    settings[@"delayOtherMode"] = @(self.delayOtherMode);
    settings[@"delayTime"] = @(self.delayTime);
    settings[@"excludeGroups"] = self.excludeGroups ?: @[];
    settings[@"onlyGroups"] = self.onlyGroups ?: @[];
    settings[@"delayGroups"] = self.delayGroups ?: @[];
    settings[@"filterKeywordEnabled"] = @(self.filterKeywordEnabled);
    settings[@"filterKeywords"] = self.filterKeywords ?: @[];
    settings[@"grabSelfEnabled"] = @(self.grabSelfEnabled);
    settings[@"grabPrivateEnabled"] = @(self.grabPrivateEnabled);
    settings[@"backgroundGrabEnabled"] = @(self.backgroundGrabEnabled);
    
    [settings writeToFile:kSettingsPath atomically:YES];
}

- (void)loadSettings {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:kSettingsPath];
    if (settings) {
        self.enabled = [settings[@"enabled"] boolValue];
        self.hasShownDisclaimer = [settings[@"hasShownDisclaimer"] boolValue];
        self.grabMode = [settings[@"grabMode"] integerValue];
        self.delayOtherMode = [settings[@"delayOtherMode"] integerValue];
        self.delayTime = [settings[@"delayTime"] doubleValue] ?: 1.0;
        self.excludeGroups = [settings[@"excludeGroups"] mutableCopy] ?: [NSMutableArray array];
        self.onlyGroups = [settings[@"onlyGroups"] mutableCopy] ?: [NSMutableArray array];
        self.delayGroups = [settings[@"delayGroups"] mutableCopy] ?: [NSMutableArray array];
        self.filterKeywordEnabled = [settings[@"filterKeywordEnabled"] boolValue];
        self.filterKeywords = [settings[@"filterKeywords"] mutableCopy] ?: [NSMutableArray array];
        self.grabSelfEnabled = [settings[@"grabSelfEnabled"] boolValue];
        self.grabPrivateEnabled = [settings[@"grabPrivateEnabled"] boolValue];
        self.backgroundGrabEnabled = [settings[@"backgroundGrabEnabled"] boolValue];
    }
}

- (BOOL)shouldGrabRedBagInChat:(NSString *)chatId isGroup:(BOOL)isGroup {
    if (!self.enabled) return NO;
    
    // 私信红包处理
    if (!isGroup) {
        return self.grabPrivateEnabled;
    }
    
    // 群红包处理
    switch (self.grabMode) {
        case JJGrabModeExclude:
            // 不抢群模式：排除列表中的群不抢
            return ![self.excludeGroups containsObject:chatId];
            
        case JJGrabModeOnly:
            // 只抢群模式：只抢列表中的群
            return [self.onlyGroups containsObject:chatId];
            
        case JJGrabModeDelay:
            // 延迟抢模式：延迟群有延迟，其余看配置
            if ([self.delayGroups containsObject:chatId]) {
                return YES; // 延迟抢
            } else {
                return self.delayOtherMode == JJDelayOtherModeNoDelay;
            }
            
        default:
            return YES;
    }
}

- (BOOL)shouldFilterByKeyword:(NSString *)redBagTitle {
    if (!self.filterKeywordEnabled || !redBagTitle || redBagTitle.length == 0) {
        return NO;
    }
    
    for (NSString *keyword in self.filterKeywords) {
        if ([redBagTitle containsString:keyword]) {
            return YES; // 包含关键词，过滤掉不抢
        }
    }
    return NO;
}

- (NSTimeInterval)getDelayTimeForChat:(NSString *)chatId {
    if (self.grabMode == JJGrabModeDelay && [self.delayGroups containsObject:chatId]) {
        return self.delayTime;
    }
    return 0;
}

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"温馨提示"
                                                                       message:@"仅供娱乐使用\n\n封号与否和本插件无关\n\n请认真考虑是否开启功能"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"我已了解，开启功能" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.hasShownDisclaimer = YES;
            self.enabled = YES;
            [self saveSettings];
            if (completion) completion(YES);
        }];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            if (completion) completion(NO);
        }];
        
        [alert addAction:confirmAction];
        [alert addAction:cancelAction];
        
        UIViewController *topVC = [self topViewController];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

- (UIViewController *)topViewController {
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    return [self topViewControllerWithRootViewController:rootVC];
}

- (UIViewController *)topViewControllerWithRootViewController:(UIViewController *)rootVC {
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabVC = (UITabBarController *)rootVC;
        return [self topViewControllerWithRootViewController:tabVC.selectedViewController];
    } else if ([rootVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navVC = (UINavigationController *)rootVC;
        return [self topViewControllerWithRootViewController:navVC.visibleViewController];
    } else if (rootVC.presentedViewController) {
        return [self topViewControllerWithRootViewController:rootVC.presentedViewController];
    }
    return rootVC;
}

- (void)showSettingsController {
    dispatch_async(dispatch_get_main_queue(), ^{
        JJRedBagSettingsController *settingsVC = [[JJRedBagSettingsController alloc] init];
        UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        navVC.modalPresentationStyle = UIModalPresentationFullScreen;
        
        UIViewController *topVC = [self topViewController];
        [topVC presentViewController:navVC animated:YES completion:nil];
    });
}

@end
