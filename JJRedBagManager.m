#import "JJRedBagManager.h"
#import "JJRedBagSettingsController.h"

// 使用沙盒内的 Documents 目录存储配置，避免 /var/mobile/Library/Preferences 无权限或被重置的问题
#define kSettingsPath ([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"jjredbag_settings.plist"])

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
        _backgroundMode = JJBackgroundModeTimer; // 默认定时器模式
        _shakeToConfigEnabled = NO; // 默认关闭
        
        // 自动回复默认设置
        _autoReplyEnabled = NO;
        _autoReplyPrivateEnabled = NO;
        _autoReplyGroupEnabled = NO;
        _autoReplyDelayEnabled = NO;
        _autoReplyDelayTime = 0.0;
        _autoReplyContent = @"";
        
        // 通知默认设置
        _notificationEnabled = NO;
        _notificationChatId = @"";
        _notificationChatName = @"";
        
        _pendingRedBags = [NSMutableDictionary dictionary];
        
        // 自动收款默认设置
        _autoReceivePrivateEnabled = NO;
        _autoReceiveGroupEnabled = NO;
        _groupReceiveMembers = [NSMutableDictionary dictionary];
        _receiveGroups = [NSMutableArray array];
        _receiveAutoReplyPrivateEnabled = NO;
        _receiveAutoReplyGroupEnabled = NO;
        _receiveAutoReplyContent = @"";
        _receiveNotificationEnabled = NO;
        _receiveLocalNotificationEnabled = NO;
        _receiveNotificationChatId = @"";
        _receiveNotificationChatName = @"";
        _totalReceiveAmount = 0;
        
        // 消息+1(复读机)默认设置
        _plusOneEnabled = NO;
        
        // 表情包缩放默认设置
        _emoticonScaleEnabled = NO;
        
        // 界面优化默认设置
        _hideVoiceSearchButton = NO;
        _hideLastGroupLabel = NO;
        _hasShownHideVoiceAlert = NO;
        _hasShownHideGroupAlert = NO;
        
        // 小游戏作弊默认设置
        _gameCheatEnabled = NO;
        _gameCheatMode = 0;
        _gameCheatDiceSequence = @"";
        _gameCheatRPSSequence = @"";
        _gameCheatDiceIndex = 0;
        _gameCheatRPSIndex = 0;
        _hasShownGameCheatAlert = NO;
        _adSkipEnabled = NO;
        _hasShownAdSkipAlert = NO;
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
    settings[@"backgroundMode"] = @(self.backgroundMode);
    settings[@"shakeToConfigEnabled"] = @(self.shakeToConfigEnabled);
    
    // 自动回复
    settings[@"autoReplyEnabled"] = @(self.autoReplyEnabled);
    settings[@"autoReplyPrivateEnabled"] = @(self.autoReplyPrivateEnabled);
    settings[@"autoReplyGroupEnabled"] = @(self.autoReplyGroupEnabled);
    settings[@"autoReplyDelayEnabled"] = @(self.autoReplyDelayEnabled);
    settings[@"autoReplyDelayTime"] = @(self.autoReplyDelayTime);
    settings[@"autoReplyContent"] = self.autoReplyContent ?: @"";
    
    // 通知
    settings[@"notificationEnabled"] = @(self.notificationEnabled);
    settings[@"localNotificationEnabled"] = @(self.localNotificationEnabled);
    settings[@"notificationChatId"] = self.notificationChatId ?: @"";
    settings[@"notificationChatName"] = self.notificationChatName ?: @"";
    settings[@"totalAmount"] = @(self.totalAmount);
    
    // 自动收款
    settings[@"autoReceivePrivateEnabled"] = @(self.autoReceivePrivateEnabled);
    settings[@"autoReceiveGroupEnabled"] = @(self.autoReceiveGroupEnabled);
    settings[@"groupReceiveMembers"] = self.groupReceiveMembers ?: @{};
    settings[@"receiveGroups"] = self.receiveGroups ?: @[];
    settings[@"receiveAutoReplyPrivateEnabled"] = @(self.receiveAutoReplyPrivateEnabled);
    settings[@"receiveAutoReplyGroupEnabled"] = @(self.receiveAutoReplyGroupEnabled);
    settings[@"receiveAutoReplyContent"] = self.receiveAutoReplyContent ?: @"";
    settings[@"receiveNotificationEnabled"] = @(self.receiveNotificationEnabled);
    settings[@"receiveLocalNotificationEnabled"] = @(self.receiveLocalNotificationEnabled);
    settings[@"receiveNotificationChatId"] = self.receiveNotificationChatId ?: @"";
    settings[@"receiveNotificationChatName"] = self.receiveNotificationChatName ?: @"";
    settings[@"totalReceiveAmount"] = @(self.totalReceiveAmount);
    
    // 消息+1(复读机)
    settings[@"plusOneEnabled"] = @(self.plusOneEnabled);
    
    // 表情包缩放
    settings[@"emoticonScaleEnabled"] = @(self.emoticonScaleEnabled);
    
    // 界面优化
    settings[@"hideVoiceSearchButton"] = @(self.hideVoiceSearchButton);
    settings[@"hideLastGroupLabel"] = @(self.hideLastGroupLabel);
    settings[@"hasShownHideVoiceAlert"] = @(self.hasShownHideVoiceAlert);
    settings[@"hasShownHideGroupAlert"] = @(self.hasShownHideGroupAlert);
    
    // 小游戏作弊
    settings[@"gameCheatEnabled"] = @(self.gameCheatEnabled);
    settings[@"gameCheatMode"] = @(self.gameCheatMode);
    settings[@"gameCheatDiceSequence"] = self.gameCheatDiceSequence ?: @"";
    settings[@"gameCheatRPSSequence"] = self.gameCheatRPSSequence ?: @"";
    settings[@"gameCheatDiceIndex"] = @(self.gameCheatDiceIndex);
    settings[@"gameCheatRPSIndex"] = @(self.gameCheatRPSIndex);
    settings[@"hasShownGameCheatAlert"] = @(self.hasShownGameCheatAlert);
    settings[@"adSkipEnabled"] = @(self.adSkipEnabled);
    settings[@"hasShownAdSkipAlert"] = @(self.hasShownAdSkipAlert);
    
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
        self.backgroundMode = [settings[@"backgroundMode"] integerValue];
        if (settings[@"shakeToConfigEnabled"]) {
            self.shakeToConfigEnabled = [settings[@"shakeToConfigEnabled"] boolValue];
        } else {
            self.shakeToConfigEnabled = NO; // 默认值
        }
        
        // 自动回复
        self.autoReplyEnabled = [settings[@"autoReplyEnabled"] boolValue];
        self.autoReplyPrivateEnabled = [settings[@"autoReplyPrivateEnabled"] boolValue];
        self.autoReplyGroupEnabled = [settings[@"autoReplyGroupEnabled"] boolValue];
        self.autoReplyDelayEnabled = [settings[@"autoReplyDelayEnabled"] boolValue];
        self.autoReplyDelayTime = [settings[@"autoReplyDelayTime"] doubleValue];
        self.autoReplyContent = settings[@"autoReplyContent"] ?: @"";
        
        // 通知
        self.notificationEnabled = [settings[@"notificationEnabled"] boolValue];
        self.localNotificationEnabled = [settings[@"localNotificationEnabled"] boolValue];
        self.notificationChatId = settings[@"notificationChatId"] ?: @"";
        self.notificationChatName = settings[@"notificationChatName"] ?: @"";
        self.totalAmount = [settings[@"totalAmount"] longLongValue];
        
        // 自动收款
        self.autoReceivePrivateEnabled = [settings[@"autoReceivePrivateEnabled"] boolValue];
        self.autoReceiveGroupEnabled = [settings[@"autoReceiveGroupEnabled"] boolValue];
        self.groupReceiveMembers = [settings[@"groupReceiveMembers"] mutableCopy] ?: [NSMutableDictionary dictionary];
        self.receiveGroups = [settings[@"receiveGroups"] mutableCopy] ?: [NSMutableArray array];
        self.receiveAutoReplyPrivateEnabled = [settings[@"receiveAutoReplyPrivateEnabled"] boolValue];
        self.receiveAutoReplyGroupEnabled = [settings[@"receiveAutoReplyGroupEnabled"] boolValue];
        self.receiveAutoReplyContent = settings[@"receiveAutoReplyContent"] ?: @"";
        self.receiveNotificationEnabled = [settings[@"receiveNotificationEnabled"] boolValue];
        self.receiveLocalNotificationEnabled = [settings[@"receiveLocalNotificationEnabled"] boolValue];
        self.receiveNotificationChatId = settings[@"receiveNotificationChatId"] ?: @"";
        self.receiveNotificationChatName = settings[@"receiveNotificationChatName"] ?: @"";
        self.totalReceiveAmount = [settings[@"totalReceiveAmount"] longLongValue];
        
        // 消息+1(复读机)
        self.plusOneEnabled = [settings[@"plusOneEnabled"] boolValue];
        
        // 表情包缩放
        self.emoticonScaleEnabled = [settings[@"emoticonScaleEnabled"] boolValue];
        
        // 界面优化
        self.hideVoiceSearchButton = [settings[@"hideVoiceSearchButton"] boolValue];
        self.hideLastGroupLabel = [settings[@"hideLastGroupLabel"] boolValue];
        self.hasShownHideVoiceAlert = [settings[@"hasShownHideVoiceAlert"] boolValue];
        self.hasShownHideGroupAlert = [settings[@"hasShownHideGroupAlert"] boolValue];
        
        // 小游戏作弊
        self.gameCheatEnabled = [settings[@"gameCheatEnabled"] boolValue];
        self.gameCheatMode = [settings[@"gameCheatMode"] integerValue];
        self.gameCheatDiceSequence = settings[@"gameCheatDiceSequence"] ?: @"";
        self.gameCheatRPSSequence = settings[@"gameCheatRPSSequence"] ?: @"";
        self.gameCheatDiceIndex = [settings[@"gameCheatDiceIndex"] integerValue];
        self.gameCheatRPSIndex = [settings[@"gameCheatRPSIndex"] integerValue];
        self.hasShownGameCheatAlert = [settings[@"hasShownGameCheatAlert"] boolValue];
        self.adSkipEnabled = [settings[@"adSkipEnabled"] boolValue];
        self.hasShownAdSkipAlert = [settings[@"hasShownAdSkipAlert"] boolValue];
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                       message:@"本插件仅供学习和娱乐使用。\n\n使用本插件可能导致微信账号被封禁等风险，风险需由您自行承担。\n\n作者不对任何后果负责。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"我已知晓并承担风险 (3)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            self.hasShownDisclaimer = YES;
            self.enabled = YES;
            [self saveSettings];
            if (completion) completion(YES);
        }];
        confirmAction.enabled = NO;
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"那我不用了" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            if (completion) completion(NO);
        }];
        
        [alert addAction:confirmAction];
        [alert addAction:cancelAction];
        
        UIViewController *topVC = [self topViewController];
        [topVC presentViewController:alert animated:YES completion:nil];
        
        // 倒计时逻辑
        __block int countdown = 3;
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            countdown--;
            if (countdown > 0) {
                [confirmAction setValue:[NSString stringWithFormat:@"我已知晓并承担风险 (%d)", countdown] forKey:@"title"];
            } else {
                [confirmAction setValue:@"我已知晓并承担风险" forKey:@"title"];
                confirmAction.enabled = YES;
                [timer invalidate];
            }
        }];
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
        navVC.modalPresentationStyle = UIModalPresentationPageSheet; // 支持右滑返回
        
        UIViewController *topVC = [self topViewController];
        [topVC presentViewController:navVC animated:YES completion:nil];
    });
}

@end
