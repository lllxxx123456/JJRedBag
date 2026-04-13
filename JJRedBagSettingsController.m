#import "JJRedBagSettingsController.h"
#import "JJRedBagManager.h"
#import "JJRedBagGroupSelectController.h"
#import "JJRedBagContactSelectController.h"
#import "JJRedBagMemberSelectController.h"
#import "JJRedBagReceiveGroupController.h"
#import "WeChatHeaders.h"

typedef NS_ENUM(NSInteger, JJSubPageType) {
    JJSubPageRedBag = 0, JJSubPageAdvanced, JJSubPageAutoReply, JJSubPageNotify,
    JJSubPageReceive, JJSubPageEmoticon, JJSubPageUI, JJSubPageGameCheat, JJSubPageAdSkip
};

@interface JJSubSettingsController : UITableViewController
@property (nonatomic, assign) JJSubPageType pageType;
- (instancetype)initWithPageType:(JJSubPageType)type title:(NSString *)title;
@end

@interface JJRedBagSettingsController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *amountLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@end

@implementation JJRedBagSettingsController

- (instancetype)init {
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) style = UITableViewStyleInsetGrouped;
    if (self = [super initWithStyle:style]) { self.title = @"吉酱助手"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.tintColor = [UIColor systemRedColor];
    } else { self.view.tintColor = [UIColor redColor]; }
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSelf)];
    self.navigationItem.rightBarButtonItem = closeItem;
    [self setupHeaderView];
    [self setupFooterView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateAmountLabel];
    [self.tableView reloadData];
}

- (void)setupHeaderView {
    CGFloat w = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 190)];
    self.avatarView = [[UIImageView alloc] initWithFrame:CGRectMake((w-70)/2, 20, 70, 70)];
    self.avatarView.layer.cornerRadius = 35;
    self.avatarView.layer.masksToBounds = YES;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.userInteractionEnabled = YES;
    self.avatarView.layer.borderWidth = 2.0;
    if (@available(iOS 13.0, *)) self.avatarView.layer.borderColor = [UIColor quaternaryLabelColor].CGColor;
    self.avatarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self loadAvatar];
    UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)];
    [self.avatarView addGestureRecognizer:avatarTap];
    [header addSubview:self.avatarView];
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, w, 24)];
    self.nameLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) self.nameLabel.textColor = [UIColor labelColor];
    self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.nameLabel];
    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(0, 126, w, 18)];
    ver.text = @"v1.1-1";
    ver.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    ver.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) ver.textColor = [UIColor secondaryLabelColor];
    ver.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:ver];
    self.amountLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 150, w, 24)];
    self.amountLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.amountLabel.textColor = [UIColor systemRedColor];
    self.amountLabel.textAlignment = NSTextAlignmentCenter;
    self.amountLabel.userInteractionEnabled = YES;
    self.amountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAmountTap)];
    [self.amountLabel addGestureRecognizer:tap];
    [header addSubview:self.amountLabel];
    self.tableView.tableHeaderView = header;
    [self updateAmountLabel];
}

- (void)setupFooterView {
    CGFloat w = self.view.bounds.size.width;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 60)];
    UILabel *dev = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, w, 20)];
    dev.text = @"Developed by JiJiang778";
    dev.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    dev.textAlignment = NSTextAlignmentCenter;
    dev.textColor = [UIColor colorWithRed:0.35 green:0.55 blue:0.95 alpha:1.0];
    dev.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [footer addSubview:dev];
    self.tableView.tableFooterView = footer;
}

- (void)loadAvatar {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *customPath = [doc stringByAppendingPathComponent:@"jjredbag_avatar.png"];
    NSString *cachedPath = [doc stringByAppendingPathComponent:@"jjredbag_wechat_avatar.png"];
    UIImage *custom = [UIImage imageWithContentsOfFile:customPath];
    UIImage *cached = custom ? nil : [UIImage imageWithContentsOfFile:cachedPath];
    
    // 优先级：自定义头像 > 缓存微信头像 > 占位符
    if (custom) { self.avatarView.image = custom; }
    else if (cached) { self.avatarView.image = cached; }
    else { self.avatarView.image = [self placeholderAvatar]; }
    
    // 加载缓存昵称
    NSString *cachedNick = [[NSUserDefaults standardUserDefaults] stringForKey:@"jj_cached_nickname"];
    self.nameLabel.text = (cachedNick.length > 0) ? cachedNick : @"吉酱助手";
    
    // 后台尝试获取最新微信头像和昵称
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @try {
            CContactMgr *cm = nil;
            @try { cm = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")]; } @catch (NSException *e) {}
            if (!cm) return;
            CContact *me = [cm getSelfContact];
            if (!me) return;
            
            NSString *nick = me.m_nsNickName;
            if (nick.length > 0) {
                [[NSUserDefaults standardUserDefaults] setObject:nick forKey:@"jj_cached_nickname"];
                dispatch_async(dispatch_get_main_queue(), ^{ self.nameLabel.text = nick; });
            }
            
            if (!custom) {
                NSString *url = me.m_nsHeadImgUrl;
                if (url.length > 0) {
                    NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
                    if (d) {
                        UIImage *img = [UIImage imageWithData:d];
                        if (img) {
                            [d writeToFile:cachedPath atomically:YES];
                            dispatch_async(dispatch_get_main_queue(), ^{ self.avatarView.image = img; });
                        }
                    }
                }
            }
        } @catch (NSException *e) {}
    });
}

- (UIImage *)placeholderAvatar {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(70,70), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {0.35,0.55,0.95,1.0, 0.55,0.35,0.95,1.0};
    CGFloat locs[] = {0.0, 1.0};
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, colors, locs, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(70,70), 0);
    CGGradientRelease(grad); CGColorSpaceRelease(space);
    NSDictionary *a = @{NSFontAttributeName:[UIFont systemFontOfSize:26 weight:UIFontWeightBold], NSForegroundColorAttributeName:[UIColor whiteColor]};
    NSString *t = @"\u5409\u9171"; CGSize ts = [t sizeWithAttributes:a];
    [t drawAtPoint:CGPointMake((70-ts.width)/2,(70-ts.height)/2) withAttributes:a];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext(); return img;
}

- (void)avatarTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u4ece\u76f8\u518c\u9009\u62e9" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIImagePickerController *pk = [[UIImagePickerController alloc] init];
        pk.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        pk.delegate = self; pk.allowsEditing = YES;
        [self presentViewController:pk animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u6062\u590d\u9ed8\u8ba4" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [[NSFileManager defaultManager] removeItemAtPath:[doc stringByAppendingPathComponent:@"jjredbag_avatar.png"] error:nil];
        [self loadAvatar];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.avatarView; alert.popoverPresentationController.sourceRect = self.avatarView.bounds; }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if (img) { self.avatarView.image = img;
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [UIImagePNGRepresentation(img) writeToFile:[doc stringByAppendingPathComponent:@"jjredbag_avatar.png"] atomically:YES];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (section==0)?1:7; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return (section==0)?8:16; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return nil; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return (indexPath.section==0)?50:56; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"\u63d2\u4ef6\u4e3b\u5f00\u5173";
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        if (@available(iOS 13.0, *)) cell.textLabel.textColor = [UIColor labelColor];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [JJRedBagManager sharedManager].enabled;
        if (@available(iOS 13.0, *)) sw.onTintColor = [UIColor systemRedColor];
        [sw addTarget:self action:@selector(mainSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSArray *titles = @[@"\u7ea2\u5305\u8bbe\u7f6e", @"\u9ad8\u7ea7\u529f\u80fd", @"\u81ea\u52a8\u6536\u6b3e", @"\u804a\u5929\u5de5\u5177", @"\u754c\u9762\u4f18\u5316", @"\u6e38\u620f\u4f5c\u5f0a", @"\u5e7f\u544a\u8df3\u8fc7"];
    NSArray *subs = @[@"\u62a2\u7ea2\u5305\u3001\u56de\u590d\u3001\u901a\u77e5", @"\u4fdd\u6d3b\u3001\u6447\u4e00\u6447\u914d\u7f6e", @"\u81ea\u52a8\u786e\u8ba4\u8f6c\u8d26\u6536\u6b3e", @"\u6d88\u606f+1\u3001\u8868\u60c5\u7f29\u653e", @"\u9690\u85cf\u591a\u4f59\u754c\u9762\u5143\u7d20", @"\u9ab0\u5b50\u731c\u62f3\u7ed3\u679c\u63a7\u5236", @"\u5c0f\u7a0b\u5e8f\u6fc0\u52b1\u5e7f\u544a"];
    NSInteger r = indexPath.row;
    cell.textLabel.text = titles[r];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = subs[r];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    BOOL pluginEnabled = [JJRedBagManager sharedManager].enabled;
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = pluginEnabled ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
        cell.detailTextLabel.textColor = pluginEnabled ? [UIColor secondaryLabelColor] : [UIColor quaternaryLabelColor];
    }
    if (!pluginEnabled) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    if (@available(iOS 13.0, *)) {
        NSArray *icons = @[@"envelope.fill", @"gearshape.2.fill", @"yensign.circle.fill", @"face.smiling.fill", @"paintbrush.fill", @"gamecontroller.fill", @"forward.fill"];
        NSArray *clrs = @[[UIColor systemRedColor],[UIColor systemOrangeColor],[UIColor systemPurpleColor],[UIColor systemPinkColor],[UIColor systemTealColor],[UIColor systemIndigoColor],[UIColor systemYellowColor]];
        UIColor *bgColor = pluginEnabled ? clrs[r] : [UIColor tertiarySystemFillColor];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(0,0,30,30)];
        bg.backgroundColor = bgColor; bg.layer.cornerRadius = 7; bg.layer.masksToBounds = YES;
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(5,5,20,20)];
        iv.image = [UIImage systemImageNamed:icons[r]]; iv.tintColor = pluginEnabled ? [UIColor whiteColor] : [UIColor tertiaryLabelColor]; iv.contentMode = UIViewContentModeScaleAspectFit;
        [bg addSubview:iv];
        UIGraphicsBeginImageContextWithOptions(bg.bounds.size, NO, 0);
        [bg.layer renderInContext:UIGraphicsGetCurrentContext()];
        cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    if (![JJRedBagManager sharedManager].enabled) return;
    NSArray *titles = @[@"\u7ea2\u5305\u8bbe\u7f6e", @"\u9ad8\u7ea7\u529f\u80fd", @"\u81ea\u52a8\u6536\u6b3e", @"\u804a\u5929\u5de5\u5177", @"\u754c\u9762\u4f18\u5316", @"\u6e38\u620f\u4f5c\u5f0a", @"\u5e7f\u544a\u8df3\u8fc7"];
    NSArray *pageTypes = @[@(JJSubPageRedBag), @(JJSubPageAdvanced), @(JJSubPageReceive), @(JJSubPageEmoticon), @(JJSubPageUI), @(JJSubPageGameCheat), @(JJSubPageAdSkip)];
    JJSubSettingsController *vc = [[JJSubSettingsController alloc] initWithPageType:(JJSubPageType)[pageTypes[indexPath.row] integerValue] title:titles[indexPath.row]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)mainSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.on && !manager.hasShownDisclaimer) {
        sender.on = NO;
        [self showDisclaimerAlertWithCompletion:^(BOOL accepted) {
            if (accepted) { manager.enabled = YES; [manager saveSettings]; [self.tableView reloadData]; }
        }];
    } else { manager.enabled = sender.on; [manager saveSettings]; [self.tableView reloadData]; }
}

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion {
    [[JJRedBagManager sharedManager] showDisclaimerAlertWithCompletion:completion];
}

- (void)updateAmountLabel {
    double amount = [JJRedBagManager sharedManager].totalAmount / 100.0;
    self.amountLabel.text = [NSString stringWithFormat:@"\u5df2\u4e3a\u60a8\u62a2\u4e86\uff1a%.2f \u5143", amount];
}

- (void)handleAmountTap {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    double amount = manager.totalAmount / 100.0;
    NSString *message = [NSString stringWithFormat:@"\u606d\u559c\u53d1\u8d22\uff01\n\n\u5df2\u4e3a\u60a8\u62a2\u4e86\uff1a%.2f\u5143", amount];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u8c22\u8c22\u4f5c\u8005" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u76f4\u63a5\u7f6e\u96f6" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        JJRedBagManager *mgr = [JJRedBagManager sharedManager]; mgr.totalAmount = 0; [mgr saveSettings]; [self updateAmountLabel];
    }]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.amountLabel; alert.popoverPresentationController.sourceRect = self.amountLabel.bounds; }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

@end


@implementation JJSubSettingsController

- (instancetype)initWithPageType:(JJSubPageType)type title:(NSString *)title {
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) style = UITableViewStyleInsetGrouped;
    if (self = [super initWithStyle:style]) { self.pageType = type; self.title = title; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) { self.view.backgroundColor = [UIColor systemGroupedBackgroundColor]; self.view.tintColor = [UIColor systemRedColor]; }
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    switch (self.pageType) {
        case JJSubPageRedBag: {
            NSInteger count = 3;
            if (manager.grabMode != JJGrabModeNone) {
                if (manager.grabMode == JJGrabModeExclude || manager.grabMode == JJGrabModeOnly || manager.grabMode == JJGrabModeDelay) count++;
                if (manager.grabMode == JJGrabModeDelay) count += 2;
            }
            count++; // 过滤关键词开关
            if (manager.filterKeywordEnabled) count++; // 关键词列表
            count += 2; // 自动回复 + 通知统计
            return count;
        }
        case JJSubPageAdvanced: {
            NSInteger count = 3;
            if (manager.backgroundGrabEnabled) count++;
            return count;
        }
        case JJSubPageAutoReply: {
            if (!manager.autoReplyEnabled) return 1;
            NSInteger count = 5;
            if (manager.autoReplyDelayEnabled) count++;
            return count;
        }
        case JJSubPageNotify: {
            NSInteger count = 2;
            if (manager.notificationEnabled) count++;
            return count;
        }
        case JJSubPageReceive: {
            NSInteger count = 2;
            if (manager.autoReceiveGroupEnabled) count++;
            count += 2;
            if (manager.receiveAutoReplyPrivateEnabled || manager.receiveAutoReplyGroupEnabled) count++;
            count++;
            if (manager.receiveNotificationEnabled) count++;
            count++;
            return count;
        }
        case JJSubPageEmoticon: {
            NSInteger count = 2; // +1开关 + 表情缩放开关
            if (manager.plusOneEnabled) count += 5; // 5个子开关：文字/表情包/照片/视频/文件
            if (manager.emoticonScaleEnabled) count++; // 表情缓存
            return count;
        }
        case JJSubPageUI: return 2;
        case JJSubPageGameCheat: {
            if (!manager.gameCheatEnabled) return 1;
            if (manager.gameCheatMode == 0) return 2;
            return 5;
        }
        case JJSubPageAdSkip: return 1;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 20; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return nil; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (@available(iOS 13.0, *)) { cell.textLabel.textColor = [UIColor labelColor]; cell.detailTextLabel.textColor = [UIColor secondaryLabelColor]; }
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    switch (self.pageType) {
        case JJSubPageRedBag:    [self configureRedBag:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageAdvanced:  [self configureAdvanced:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageAutoReply: [self configureAutoReply:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageNotify:    [self configureNotify:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageReceive:   [self configureReceive:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageEmoticon:  [self configureEmoticon:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageUI:        [self configureUIPage:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageGameCheat: [self configureGameCheat:cell row:indexPath.row mgr:manager]; break;
        case JJSubPageAdSkip:    [self configureAdSkip:cell row:indexPath.row mgr:manager]; break;
    }
    return cell;
}

- (void)configureRedBag:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    if (row == 0) {
        cell.textLabel.text = @"\u62a2\u7ea2\u5305\u6a21\u5f0f";
        if (m.grabMode == JJGrabModeExclude) cell.detailTextLabel.text = @"\u9ed1\u540d\u5355\u6a21\u5f0f";
        else if (m.grabMode == JJGrabModeOnly) cell.detailTextLabel.text = @"\u767d\u540d\u5355\u6a21\u5f0f";
        else if (m.grabMode == JJGrabModeDelay) cell.detailTextLabel.text = @"\u5ef6\u8fdf\u62a2\u6a21\u5f0f";
        else cell.detailTextLabel.text = @"\u5168\u81ea\u52a8\u6a21\u5f0f";
        return;
    }
    BOOL hasGS = (m.grabMode == JJGrabModeExclude || m.grabMode == JJGrabModeOnly || m.grabMode == JJGrabModeDelay);
    BOOL isDM = (m.grabMode == JJGrabModeDelay);
    int ci = 1;
    if (hasGS) {
        if (row == ci) { cell.textLabel.text = @"\u9009\u7fa4\u804a\u5217\u8868"; cell.detailTextLabel.text = [NSString stringWithFormat:@"\u5df2\u9009 %lu \u4e2a", (unsigned long)[self getSelectedGroupCount]]; return; }
        ci++;
    }
    if (isDM) {
        if (row == ci) { cell.textLabel.text = @"\u5176\u4ed6\u7fa4\u6a21\u5f0f"; cell.detailTextLabel.text = m.delayOtherMode == JJDelayOtherModeNoDelay ? @"\u65e0\u5ef6\u8fdf\u62a2" : @"\u76f4\u63a5\u4e0d\u62a2"; return; }
        ci++;
        if (row == ci) { cell.textLabel.text = @"\u5ef6\u8fdf\u62a2\u79d2\u6570"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f \u79d2", m.delayTime]; return; }
        ci++;
    }
    if (row == ci) {
        cell.textLabel.text = @"\u62a2\u81ea\u5df1\u7ea2\u5305";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.grabSelfEnabled; sw.tag = 200;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u62a2\u79c1\u804a\u7ea2\u5305";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.grabPrivateEnabled; sw.tag = 201;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u8fc7\u6ee4\u5173\u952e\u8bcd";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.filterKeywordEnabled;
        [sw addTarget:self action:@selector(filterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (m.filterKeywordEnabled && row == ci) {
        cell.textLabel.text = @"\u5173\u952e\u8bcd\u5217\u8868"; cell.detailTextLabel.text = m.filterKeywords.count > 0 ? [m.filterKeywords componentsJoinedByString:@", "] : @"\u672a\u8bbe\u7f6e"; return;
    }
    if (m.filterKeywordEnabled) ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u81ea\u52a8\u56de\u590d";
        cell.detailTextLabel.text = m.autoReplyEnabled ? @"\u5df2\u5f00\u542f" : @"\u672a\u5f00\u542f";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return;
    }
    ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u901a\u77e5\u7edf\u8ba1";
        cell.detailTextLabel.text = m.notificationEnabled ? @"\u5df2\u5f00\u542f" : @"\u672a\u5f00\u542f";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
}

- (void)configureAdvanced:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    NSInteger ci = 0;
    if (row == ci) {
        cell.textLabel.text = @"\u540e\u53f0\u4fdd\u6d3b";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.backgroundGrabEnabled; sw.tag = 202;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (m.backgroundGrabEnabled) {
        if (row == ci) { cell.textLabel.text = @"\u4fdd\u6d3b\u6a21\u5f0f"; cell.detailTextLabel.text = (m.backgroundMode == JJBackgroundModeAudio) ? @"\u5f3a\u529b\u6a21\u5f0f" : @"\u7701\u7535\u6a21\u5f0f"; return; }
        ci++;
    }
    if (row == ci) {
        cell.textLabel.text = @"\u6447\u4e00\u6447\u914d\u7f6e";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.shakeToConfigEnabled; sw.tag = 203;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u7f51\u9875\u5bfc\u822a\u680f";
        cell.detailTextLabel.text = m.webBackButtonEnabled ? @"\u5df2\u5f00\u542f" : @"\u672a\u5f00\u542f";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.webBackButtonEnabled; sw.tag = 204;
        [sw addTarget:self action:@selector(webBackButtonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
}

- (void)configureAutoReply:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    if (row == 0) {
        cell.textLabel.text = @"\u81ea\u52a8\u56de\u590d";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.autoReplyEnabled; sw.tag = 300;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    if (row == 1) {
        cell.textLabel.text = @"\u79c1\u804a\u56de\u590d";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.autoReplyPrivateEnabled; sw.tag = 301;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == 2) {
        cell.textLabel.text = @"\u7fa4\u804a\u56de\u590d";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.autoReplyGroupEnabled; sw.tag = 302;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == 3) {
        cell.textLabel.text = @"\u5ef6\u8fdf\u56de\u590d";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.autoReplyDelayEnabled; sw.tag = 303;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        BOOL showDT = m.autoReplyDelayEnabled;
        NSInteger ci = showDT ? 5 : 4;
        if (showDT && row == 4) { cell.textLabel.text = @"\u5ef6\u8fdf\u79d2\u6570"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f \u79d2", m.autoReplyDelayTime]; }
        else if (row == ci) { cell.textLabel.text = @"\u56de\u590d\u5185\u5bb9"; cell.detailTextLabel.text = (m.autoReplyContent && m.autoReplyContent.length > 0) ? m.autoReplyContent : @"\u672a\u8bbe\u7f6e"; }
    }
}

- (void)configureNotify:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    int ci = 0;
    if (row == ci) {
        cell.textLabel.text = @"\u6d88\u606f\u901a\u77e5";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.notificationEnabled; sw.tag = 400;
        [sw addTarget:self action:@selector(notificationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (m.notificationEnabled) {
        if (row == ci) { cell.textLabel.text = @"\u901a\u77e5\u63a5\u6536\u4eba"; cell.detailTextLabel.text = (m.notificationChatName && m.notificationChatName.length > 0) ? m.notificationChatName : @"\u70b9\u51fb\u8bbe\u7f6e"; return; }
        ci++;
    }
    if (row == ci) {
        cell.textLabel.text = @"\u5f39\u7a97\u901a\u77e5";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.localNotificationEnabled; sw.tag = 401;
        [sw addTarget:self action:@selector(notificationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

- (void)configureReceive:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    NSInteger ci = 0;
    if (row == ci) {
        cell.textLabel.text = @"\u79c1\u804a\u6536\u6b3e";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.autoReceivePrivateEnabled; sw.tag = 501;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u7fa4\u804a\u6536\u6b3e";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.autoReceiveGroupEnabled; sw.tag = 502;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (m.autoReceiveGroupEnabled) {
        if (row == ci) { cell.textLabel.text = @"\u6307\u5b9a\u6536\u6b3e\u7fa4"; NSInteger gc = m.receiveGroups.count; cell.detailTextLabel.text = gc > 0 ? [NSString stringWithFormat:@"\u5df2\u9009%ld\u4e2a\u7fa4", (long)gc] : @"\u5168\u90e8\u7fa4"; return; }
        ci++;
    }
    if (row == ci) {
        cell.textLabel.text = @"\u79c1\u804a\u6536\u6b3e\u56de\u590d";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.receiveAutoReplyPrivateEnabled; sw.tag = 503;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (row == ci) {
        cell.textLabel.text = @"\u7fa4\u804a\u6536\u6b3e\u56de\u590d";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.receiveAutoReplyGroupEnabled; sw.tag = 504;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (m.receiveAutoReplyPrivateEnabled || m.receiveAutoReplyGroupEnabled) {
        if (row == ci) { cell.textLabel.text = @"\u56de\u590d\u5185\u5bb9"; cell.detailTextLabel.text = m.receiveAutoReplyContent.length > 0 ? m.receiveAutoReplyContent : @"\u70b9\u51fb\u8bbe\u7f6e"; return; }
        ci++;
    }
    if (row == ci) {
        cell.textLabel.text = @"\u6536\u6b3e\u6d88\u606f\u901a\u77e5";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.receiveNotificationEnabled; sw.tag = 505;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return;
    }
    ci++;
    if (m.receiveNotificationEnabled) {
        if (row == ci) { cell.textLabel.text = @"\u901a\u77e5\u63a5\u6536\u4eba"; cell.detailTextLabel.text = m.receiveNotificationChatName.length > 0 ? m.receiveNotificationChatName : @"\u70b9\u51fb\u8bbe\u7f6e"; return; }
        ci++;
    }
    if (row == ci) {
        cell.textLabel.text = @"\u6536\u6b3e\u5f39\u7a97\u901a\u77e5";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.receiveLocalNotificationEnabled; sw.tag = 506;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

- (void)configureEmoticon:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    NSInteger r = 0;
    // row 0: +1总开关
    if (row == r) {
        cell.textLabel.text = @"\u6d88\u606f+1\uff08\u590d\u8bfb\u673a\uff09";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.plusOneEnabled; sw.tag = 610;
        [sw addTarget:self action:@selector(plusOneSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    r++;
    // +1子开关（仅在总开关开启时显示）
    if (m.plusOneEnabled) {
        NSArray *subTitles = @[@"  \u251c \u6587\u5b57+1", @"  \u251c \u8868\u60c5\u5305+1", @"  \u251c \u7167\u7247+1", @"  \u251c \u89c6\u9891+1", @"  \u2514 \u6587\u4ef6+1"];
        NSArray *subTags = @[@(611), @(612), @(613), @(614), @(615)];
        NSArray *subValues = @[@(m.plusOneTextEnabled), @(m.plusOneEmoticonEnabled), @(m.plusOneImageEnabled), @(m.plusOneVideoEnabled), @(m.plusOneFileEnabled)];
        for (NSInteger i = 0; i < 5; i++) {
            if (row == r + i) {
                cell.textLabel.text = subTitles[i];
                cell.textLabel.font = [UIFont systemFontOfSize:15];
                UISwitch *sw = [[UISwitch alloc] init]; sw.on = [subValues[i] boolValue]; sw.tag = [subTags[i] integerValue];
                [sw addTarget:self action:@selector(plusOneSubSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return;
            }
        }
        r += 5;
    }
    // 表情缩放开关
    if (row == r) {
        cell.textLabel.text = @"\u8868\u60c5\u5305\u7f29\u653e";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.emoticonScaleEnabled; sw.tag = 600;
        [sw addTarget:self action:@selector(emoticonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    r++;
    // 表情缓存（仅在表情缩放开启时显示）
    if (m.emoticonScaleEnabled && row == r) {
        NSString *cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"JJEmoticonCache"];
        unsigned long long totalSize = 0;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
        for (NSString *file in files) { NSDictionary *attrs = [fm attributesOfItemAtPath:[cacheDir stringByAppendingPathComponent:file] error:nil]; totalSize += [attrs fileSize]; }
        NSString *sizeStr;
        if (totalSize == 0) sizeStr = @"\u65e0\u7f13\u5b58";
        else if (totalSize < 1024) sizeStr = [NSString stringWithFormat:@"%lluB", totalSize];
        else if (totalSize < 1024*1024) sizeStr = [NSString stringWithFormat:@"%.1fKB", totalSize/1024.0];
        else sizeStr = [NSString stringWithFormat:@"%.1fMB", totalSize/(1024.0*1024.0)];
        cell.textLabel.text = [NSString stringWithFormat:@"\u8868\u60c5\u7f13\u5b58\uff1a%@", sizeStr];
        cell.textLabel.textColor = [UIColor systemBlueColor];
    }
}

- (void)configureUIPage:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    if (row == 0) {
        cell.textLabel.text = @"\u9690\u85cf\u8bed\u97f3\u641c\u7d22";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.hideVoiceSearchButton; sw.tag = 700;
        [sw addTarget:self action:@selector(hideFeatureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == 1) {
        cell.textLabel.text = @"\u9690\u85cf\u5206\u7ec4\u63d0\u793a";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.hideLastGroupLabel; sw.tag = 701;
        [sw addTarget:self action:@selector(hideFeatureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

- (void)configureGameCheat:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    if (row == 0) {
        cell.textLabel.text = @"\u5c0f\u6e38\u620f\u4f5c\u5f0a";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.gameCheatEnabled; sw.tag = 800;
        [sw addTarget:self action:@selector(gameCheatSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == 1) {
        NSString *mt = (m.gameCheatMode == 0) ? @"\u53d1\u9001\u65f6\u9009\u62e9" : @"\u9884\u8bbe\u5e8f\u5217";
        cell.textLabel.text = [NSString stringWithFormat:@"\u5f53\u524d\u6a21\u5f0f\uff1a%@", mt];
    } else if (row == 2) {
        NSString *seq = m.gameCheatDiceSequence.length > 0 ? m.gameCheatDiceSequence : @"\u672a\u8bbe\u7f6e";
        NSString *prog = (m.gameCheatDiceSequence.length > 0) ? [NSString stringWithFormat:@"(%ld/%lu)", (long)m.gameCheatDiceIndex, (unsigned long)m.gameCheatDiceSequence.length] : @"";
        cell.textLabel.text = [NSString stringWithFormat:@"\u9ab0\u5b50\u5e8f\u5217\uff1a%@ %@", seq, prog];
    } else if (row == 3) {
        NSString *seq = m.gameCheatRPSSequence.length > 0 ? m.gameCheatRPSSequence : @"\u672a\u8bbe\u7f6e";
        NSString *prog = (m.gameCheatRPSSequence.length > 0) ? [NSString stringWithFormat:@"(%ld/%lu)", (long)m.gameCheatRPSIndex, (unsigned long)m.gameCheatRPSSequence.length] : @"";
        cell.textLabel.text = [NSString stringWithFormat:@"\u731c\u62f3\u5e8f\u5217\uff1a%@ %@", seq, prog];
    } else if (row == 4) {
        cell.textLabel.text = @"\u91cd\u7f6e\u5e8f\u5217\u8fdb\u5ea6"; cell.textLabel.textColor = [UIColor systemRedColor];
    }
}

- (void)configureAdSkip:(UITableViewCell *)cell row:(NSInteger)row mgr:(JJRedBagManager *)m {
    if (row == 0) {
        cell.textLabel.text = @"\u5e7f\u544a\u8df3\u8fc7";
        UISwitch *sw = [[UISwitch alloc] init]; sw.on = m.adSkipEnabled; sw.tag = 900;
        [sw addTarget:self action:@selector(adSkipSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

#pragma mark - Did Select Row
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSInteger row = indexPath.row;
    if (self.pageType == JJSubPageRedBag) {
        if (row == 0) { [self showModeSelector]; return; }
        BOOL hasGS = (manager.grabMode == JJGrabModeExclude || manager.grabMode == JJGrabModeOnly || manager.grabMode == JJGrabModeDelay);
        BOOL isDM = (manager.grabMode == JJGrabModeDelay);
        int ci = 1;
        if (hasGS) { if (row == ci) { [self showGroupSelectForMode:manager.grabMode]; return; } ci++; }
        if (isDM) { if (row == ci) { [self showDelayOtherModeSelector]; return; } ci++; if (row == ci) { [self showDelayTimeInput]; return; } ci++; }
        ci += 2; // 跳过抢自己红包和抢私聊红包开关
        ci++; // 跳过过滤关键词开关
        if (manager.filterKeywordEnabled && row == ci) { [self showKeywordEditor]; return; }
        if (manager.filterKeywordEnabled) ci++;
        if (row == ci) {
            JJSubSettingsController *vc = [[JJSubSettingsController alloc] initWithPageType:JJSubPageAutoReply title:@"\u81ea\u52a8\u56de\u590d"];
            [self.navigationController pushViewController:vc animated:YES]; return;
        }
        ci++;
        if (row == ci) {
            JJSubSettingsController *vc = [[JJSubSettingsController alloc] initWithPageType:JJSubPageNotify title:@"\u901a\u77e5\u7edf\u8ba1"];
            [self.navigationController pushViewController:vc animated:YES]; return;
        }
    } else if (self.pageType == JJSubPageAdvanced) {
        NSInteger ci = 1;
        if (manager.backgroundGrabEnabled) { if (row == ci) { [self showBackgroundModeSelector]; return; } ci++; }
    } else if (self.pageType == JJSubPageAutoReply) {
        if (manager.autoReplyDelayEnabled) { if (row == 4) [self showAutoReplyDelayTimeInput]; if (row == 5) [self showAutoReplyContentInput]; }
        else { if (row == 4) [self showAutoReplyContentInput]; }
    } else if (self.pageType == JJSubPageNotify) {
        if (manager.notificationEnabled && row == 1) { [self showNotificationContactSelect]; }
    } else if (self.pageType == JJSubPageReceive) {
        NSInteger ci = 2;
        if (manager.autoReceiveGroupEnabled) { if (row == ci) { [self showGroupReceiveSelect]; return; } ci++; }
        ci += 2;
        if (manager.receiveAutoReplyPrivateEnabled || manager.receiveAutoReplyGroupEnabled) { if (row == ci) { [self showReceiveReplyContentInput]; return; } ci++; }
        ci++;
        if (manager.receiveNotificationEnabled) { if (row == ci) { [self showReceiveNotificationContactSelect]; return; } }
    } else if (self.pageType == JJSubPageEmoticon) {
        if (row == 2) { [self jj_clearEmoticonCache]; }
    } else if (self.pageType == JJSubPageGameCheat) {
        if (row == 1) [self showGameCheatModeSelector];
        else if (row == 2) [self showGameCheatSequenceInput:YES];
        else if (row == 3) [self showGameCheatSequenceInput:NO];
        else if (row == 4) [self resetGameCheatProgress];
    }
}

#pragma mark - Switch Handlers
- (void)boolSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (sender.tag == 200) m.grabSelfEnabled = sender.on;
    if (sender.tag == 201) m.grabPrivateEnabled = sender.on;
    if (sender.tag == 202) { m.backgroundGrabEnabled = sender.on; [m saveSettings]; [self.tableView reloadData]; return; }
    if (sender.tag == 203) { m.shakeToConfigEnabled = sender.on; if (sender.on) [self showShakeHintAlert]; }
    [m saveSettings];
}

- (void)filterSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager]; m.filterKeywordEnabled = sender.on; [m saveSettings]; [self.tableView reloadData];
}

- (void)autoReplySwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (sender.tag == 300) {
        m.autoReplyEnabled = sender.on;
        if (sender.on && (!m.autoReplyContent || m.autoReplyContent.length == 0)) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u63d0\u793a" message:@"\u9700\u81ea\u5b9a\u4e49\u81ea\u52a8\u56de\u590d\u5185\u5bb9\uff0c\u5426\u5219\u4e0d\u8d77\u4f5c\u7528" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self showAutoReplyContentInput]; }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    if (sender.tag == 301) m.autoReplyPrivateEnabled = sender.on;
    if (sender.tag == 302) m.autoReplyGroupEnabled = sender.on;
    if (sender.tag == 303) m.autoReplyDelayEnabled = sender.on;
    [m saveSettings]; [self.tableView reloadData];
}

- (void)notificationSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (sender.tag == 400) {
        m.notificationEnabled = sender.on;
        if (sender.on && (!m.notificationChatId || m.notificationChatId.length == 0)) {
            m.notificationChatId = @"filehelper"; m.notificationChatName = @"\u6587\u4ef6\u4f20\u8f93\u52a9\u624b";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u63d0\u793a" message:@"\u9ed8\u8ba4\u53d1\u9001\u81f3\u300a\u6587\u4ef6\u4f20\u8f93\u52a9\u624b\u300b" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    if (sender.tag == 401) m.localNotificationEnabled = sender.on;
    [m saveSettings]; [self.tableView reloadData];
}

- (void)receiveSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (sender.tag == 501) m.autoReceivePrivateEnabled = sender.on;
    if (sender.tag == 502) m.autoReceiveGroupEnabled = sender.on;
    if (sender.tag == 503) m.receiveAutoReplyPrivateEnabled = sender.on;
    if (sender.tag == 504) m.receiveAutoReplyGroupEnabled = sender.on;
    if (sender.tag == 505) m.receiveNotificationEnabled = sender.on;
    if (sender.tag == 506) m.receiveLocalNotificationEnabled = sender.on;
    [m saveSettings]; [self.tableView reloadData];
    
    if ((sender.tag == 501 || sender.tag == 502) && sender.on) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"jj_shown_receive_cache_hint"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"jj_shown_receive_cache_hint"];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u81ea\u52a8\u6536\u6b3e\u63d0\u793a" message:@"\u9996\u6b21\u4f7f\u7528\u81ea\u52a8\u6536\u6b3e\u529f\u80fd\u524d\uff0c\u8bf7\u5148\u624b\u52a8\u64cd\u4f5c\u4e00\u6b21\u4ee5\u6fc0\u6d3b\u7f13\u5b58\uff1a\n\n\u2022 \u624b\u52a8\u786e\u8ba4\u4e00\u7b14\u8f6c\u8d26\u6536\u6b3e\n\u2022 \u6216\u6253\u5f00\u4efb\u610f\u4e00\u6761\u8f6c\u8d26\u8be6\u60c5\u9875\n\n\u4e4b\u540e\u5373\u53ef\u5168\u81ea\u52a8\u6536\u6b3e\uff0c\u65e0\u9700\u91cd\u590d\u64cd\u4f5c\u3002" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)plusOneSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager]; m.plusOneEnabled = sender.on; [m saveSettings]; [self.tableView reloadData];
    if (sender.on && ![[NSUserDefaults standardUserDefaults] boolForKey:@"jj_shown_plusone_alert2"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"jj_shown_plusone_alert2"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u6d88\u606f+1\uff08\u590d\u8bfb\u673a\uff09" message:@"\u5f00\u542f\u540e\uff0c\u957f\u6309\u804a\u5929\u6d88\u606f\u65f6\u83dc\u5355\u4e2d\u4f1a\u51fa\u73b0\u300c+1\u300d\u6309\u94ae\u3002\n\n\u53ef\u5728\u4e0b\u65b9\u5b50\u5f00\u5173\u4e2d\u9009\u62e9\u542f\u7528\u54ea\u4e9b\u6d88\u606f\u7c7b\u578b\u7684+1\u529f\u80fd\u3002\n\n\u5f00\u5173\u5207\u6362\u540e\u65e0\u9700\u91cd\u542f\u5fae\u4fe1\uff0c\u7acb\u5373\u751f\u6548\u3002" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)plusOneSubSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (sender.tag == 611) m.plusOneTextEnabled = sender.on;
    if (sender.tag == 612) m.plusOneEmoticonEnabled = sender.on;
    if (sender.tag == 613) m.plusOneImageEnabled = sender.on;
    if (sender.tag == 614) m.plusOneVideoEnabled = sender.on;
    if (sender.tag == 615) m.plusOneFileEnabled = sender.on;
    [m saveSettings]; [self.tableView reloadData];
}

- (void)emoticonSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager]; m.emoticonScaleEnabled = sender.on; [m saveSettings]; [self.tableView reloadData];
    if (sender.on && ![[NSUserDefaults standardUserDefaults] boolForKey:@"jj_shown_emoticon_alert"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"jj_shown_emoticon_alert"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u8868\u60c5\u5305\u7f29\u653e\u529f\u80fd" message:@"\u5f00\u542f\u540e\uff0c\u957f\u6309\u804a\u5929\u754c\u9762\u7684\u8868\u60c5\u5305\uff0c\u5728\u83dc\u5355\u4e2d\u9009\u62e9\u300c\u5927\u5927\u5c0f\u5c0f\u300d\uff0c\u53ef\u4ee5\u9009\u62e9\uff1a\n\n\u2022 \u653e\u5927 1.5x ~ 3.0x\n\u2022 \u7f29\u5c0f 0.5x ~ 0.75x\n\u2022 \u81ea\u5b9a\u4e49\u500d\u6570\n\n\u9009\u62e9\u540e\u5c06\u81ea\u52a8\u53d1\u9001\u8c03\u6574\u540e\u7684\u8868\u60c5\u5305\u3002" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)hideFeatureSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (sender.tag == 700) {
        m.hideVoiceSearchButton = sender.on;
        if (sender.on && !m.hasShownHideVoiceAlert) {
            m.hasShownHideVoiceAlert = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u9690\u85cf\u8bed\u97f3\u641c\u7d22" message:@"\u5f00\u542f\u540e\u5c06\u9690\u85cf\u5fae\u4fe1\u641c\u7d22\u754c\u9762\u5e95\u90e8\u7684\u300c\u6309\u4f4f\u8bed\u97f3\u63d0\u95ee\u6216\u641c\u7d22\u7f51\u7edc\u300d\u6309\u94ae\u3002\n\n\u5173\u95ed\u6b64\u5f00\u5173\u5373\u53ef\u6062\u590d\u663e\u793a\u3002" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    if (sender.tag == 701) {
        m.hideLastGroupLabel = sender.on;
        if (sender.on && !m.hasShownHideGroupAlert) {
            m.hasShownHideGroupAlert = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u9690\u85cf\u5206\u7ec4\u63d0\u793a" message:@"\u5f00\u542f\u540e\u5c06\u9690\u85cf\u53d1\u5e03\u670b\u53cb\u5708\u65f6\u663e\u793a\u7684\u300c\u4e0a\u6b21\u5206\u7ec4\uff1axxx\u300d\u63d0\u793a\u3002\n\n\u5173\u95ed\u6b64\u5f00\u5173\u5373\u53ef\u6062\u590d\u663e\u793a\u3002" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    [m saveSettings]; [self.tableView reloadData];
}

- (void)gameCheatSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager]; m.gameCheatEnabled = sender.on; [m saveSettings]; [self.tableView reloadData];
    if (sender.on && !m.hasShownGameCheatAlert) {
        m.hasShownGameCheatAlert = YES; [m saveSettings];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u5c0f\u6e38\u620f\u4f5c\u5f0a" message:@"\u5f00\u542f\u540e\u53ef\u5bf9\u9ab0\u5b50\u548c\u731c\u62f3\u8fdb\u884c\u4f5c\u5f0a\uff1a\n\n\u3010\u6a21\u5f0f1\u3011\u53d1\u9001\u65f6\u9009\u62e9\n\u6bcf\u6b21\u53d1\u9001\u9ab0\u5b50/\u731c\u62f3\u65f6\u5f39\u51fa\u9009\u62e9\u9762\u677f\u3002\n\n\u3010\u6a21\u5f0f2\u3011\u9884\u8bbe\u5e8f\u5217\n\u63d0\u524d\u8bbe\u7f6e\u7ed3\u679c\u5e8f\u5217\uff0c\u53d1\u9001\u65f6\u81ea\u52a8\u6309\u5e8f\u5217\u51fa\u7ed3\u679c\u3002\n\u2022 \u9ab0\u5b50\uff1a\u8f93\u51651-6\u7684\u6570\u5b57\n\u2022 \u731c\u62f3\uff1a1=\u526a\u5200 2=\u77f3\u5934 3=\u5e03\n\u2022 \u8f93\u51650\u8868\u793a\u8be5\u6b21\u4e0d\u4f5c\u5f0a\n\u2022 \u5e8f\u5217\u7528\u5b8c\u540e\u6062\u590d\u6b63\u5e38" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)adSkipSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager]; m.adSkipEnabled = sender.on; [m saveSettings]; [self.tableView reloadData];
    if (sender.on && !m.hasShownAdSkipAlert) {
        m.hasShownAdSkipAlert = YES; [m saveSettings];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u5e7f\u544a\u8df3\u8fc7" message:@"\u5f00\u542f\u540e\uff0c\u5c0f\u7a0b\u5e8f\u6fc0\u52b1\u5e7f\u544a\u9875\u9762\u4f1a\u663e\u793a\u52a0\u901f\u6309\u94ae\uff1a\n\n\u2022 1x\uff1a\u6b63\u5e38\u901f\u5ea6\n\u2022 5x\uff1a5\u500d\u901f\u64ad\u653e\n\u2022 10x\uff1a10\u500d\u901f\u64ad\u653e\n\u2022 \u8df3\u8fc7\uff1a\u76f4\u63a5\u83b7\u53d6\u5956\u52b1\n\n\u6ce8\u610f\uff1a\u90e8\u5206\u5e7f\u544a\u53ef\u80fd\u4f1a\u670d\u52a1\u7aef\u9a8c\u8bc1\uff0c\u5efa\u8bae\u4f18\u5148\u4f7f\u7528\u52a0\u901f\u6a21\u5f0f\u3002" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)webBackButtonSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *m = [JJRedBagManager sharedManager]; m.webBackButtonEnabled = sender.on; [m saveSettings]; [self.tableView reloadData];
    if (sender.on && !m.hasShownWebBackAlert) {
        m.hasShownWebBackAlert = YES; [m saveSettings];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u7f51\u9875\u5bfc\u822a\u680f" message:@"\u5f00\u542f\u540e\uff0c\u5f53\u7f51\u9875\u65e0\u539f\u751f\u5e95\u90e8\u5de5\u5177\u680f\u65f6\uff0c\u4f1a\u81ea\u52a8\u5728\u9875\u9762\u5e95\u90e8\u663e\u793a\u5bfc\u822a\u680f\uff0c\u5305\u542b\u8fd4\u56de\u548c\u524d\u8fdb\u6309\u94ae\u3002\n\n\u9002\u7528\u573a\u666f\uff1a\u661f\u6807\u7f51\u9875\u3001\u516c\u4f17\u53f7\u6587\u7ae0\u5185\u94fe\u63a5\u7b49\u65e0\u5bfc\u822a\u63a7\u4ef6\u7684\u7f51\u9875\u3002\n\n\u6309\u94ae\u72b6\u6001\u4f1a\u6839\u636e\u7f51\u9875\u5386\u53f2\u8bb0\u5f55\u52a8\u6001\u66f4\u65b0\u3002" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Alert Methods
- (void)showShakeHintAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u63d0\u793a" message:@"\u5f00\u542f\u540e\uff0c\u5728\u5fae\u4fe1\u754c\u9762\u6447\u4e00\u6447\u624b\u673a\u5373\u53ef\u5feb\u901f\u6253\u5f00\u6b64\u8bbe\u7f6e\u9875\u9762\u3002" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showBackgroundModeSelector {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u9009\u62e9\u4fdd\u6d3b\u6a21\u5f0f" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u7701\u7535\u6a21\u5f0f\uff08\u5b9a\u65f6\u5237\u65b0\uff09" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        m.backgroundMode = JJBackgroundModeTimer; [m saveSettings]; [self.tableView reloadData]; [self showBackgroundModeHint:JJBackgroundModeTimer];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u5f3a\u529b\u6a21\u5f0f\uff08\u65e0\u58f0\u97f3\u9891\uff09" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        m.backgroundMode = JJBackgroundModeAudio; [m saveSettings]; [self.tableView reloadData]; [self showBackgroundModeHint:JJBackgroundModeAudio];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.view; alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0); alert.popoverPresentationController.permittedArrowDirections = 0; }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showBackgroundModeHint:(JJBackgroundMode)mode {
    NSString *title = nil, *msg = nil;
    if (mode == JJBackgroundModeTimer) { title = @"\u7701\u7535\u6a21\u5f0f"; msg = @"\u901a\u8fc7\u5b9a\u65f6\u5237\u65b0\u540e\u53f0\u4efb\u52a1\u4fdd\u6301\u6d3b\u8dc3\u3002\n\n\u4f18\u70b9\uff1a\u8017\u7535\u6700\u5c11\n\u7f3a\u70b9\uff1a\u7cfb\u7edf\u8d44\u6e90\u7d27\u5f20\u65f6\u53ef\u80fd\u88ab\u7ec8\u6b62\n\n\u9002\u5408\uff1a\u5bf9\u8017\u7535\u654f\u611f"; }
    else { title = @"\u5f3a\u529b\u6a21\u5f0f"; msg = @"\u901a\u8fc7\u64ad\u653e\u65e0\u58f0\u97f3\u9891\u4fdd\u6301\u540e\u53f0\u8fd0\u884c\u3002\n\n\u4f18\u70b9\uff1a\u6700\u7a33\u5b9a\n\u7f3a\u70b9\uff1a\u8017\u7535\u8f83\u591a\n\n\u9002\u5408\uff1a\u786e\u4fdd\u540e\u53f0\u62a2\u7ea2\u5305\u6210\u529f"; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u77e5\u9053\u4e86" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showModeSelector {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u9009\u62e9\u62a2\u7ea2\u5305\u6a21\u5f0f" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *modes = @[@"\u5168\u81ea\u52a8\u6a21\u5f0f (\u5168\u62a2)", @"\u9ed1\u540d\u5355\u6a21\u5f0f (\u4e0d\u62a2\u5217\u8868)", @"\u767d\u540d\u5355\u6a21\u5f0f (\u53ea\u62a2\u5217\u8868)", @"\u5ef6\u8fdf\u62a2\u6a21\u5f0f"];
    for (int i = 0; i < modes.count; i++) {
        [alert addAction:[UIAlertAction actionWithTitle:modes[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.grabMode = (JJGrabMode)i; [m saveSettings]; [self.tableView reloadData]; }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.view; alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0); alert.popoverPresentationController.permittedArrowDirections = 0; }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDelayOtherModeSelector {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u975e\u5217\u8868\u7fa4\u5904\u7406" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u65e0\u5ef6\u8fdf\u62a2" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.delayOtherMode = JJDelayOtherModeNoDelay; [m saveSettings]; [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u76f4\u63a5\u4e0d\u62a2" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { m.delayOtherMode = JJDelayOtherModeNoGrab; [m saveSettings]; [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.view; alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0); alert.popoverPresentationController.permittedArrowDirections = 0; }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDelayTimeInput {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u8bbe\u7f6e\u5ef6\u8fdf\u65f6\u95f4" message:@"\u8bf7\u8f93\u5165\u79d2\u6570 (\u652f\u6301\u5c0f\u6570)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"1.0"; tf.keyboardType = UIKeyboardTypeDecimalPad; tf.text = [NSString stringWithFormat:@"%.1f", m.delayTime]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { double v = [alert.textFields.firstObject.text doubleValue]; if (v<0)v=0; m.delayTime = v; [m saveSettings]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAutoReplyDelayTimeInput {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u56de\u590d\u5ef6\u8fdf" message:@"\u8bf7\u8f93\u5165\u79d2\u6570" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.keyboardType = UIKeyboardTypeDecimalPad; tf.text = [NSString stringWithFormat:@"%.1f", m.autoReplyDelayTime]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { double v = [alert.textFields.firstObject.text doubleValue]; if (v<0)v=0; m.autoReplyDelayTime = v; [m saveSettings]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAutoReplyContentInput {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u56de\u590d\u5185\u5bb9" message:@"\u8bf7\u8f93\u5165\u81ea\u52a8\u56de\u590d\u5185\u5bb9" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"\u8c22\u8c22\u8001\u677f"; tf.text = m.autoReplyContent; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.autoReplyContent = alert.textFields.firstObject.text; [m saveSettings]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showKeywordEditor {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u6dfb\u52a0\u8fc7\u6ee4\u5173\u952e\u8bcd" message:@"\u7528\u9017\u53f7\u5206\u9694" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [m.filterKeywords componentsJoinedByString:@","]; tf.placeholder = @"\u6d4b\u6302,\u4e13\u5c5e"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u4fdd\u5b58" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = [alert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"\uff0c" withString:@","];
        NSArray *raw = [text componentsSeparatedByString:@","];
        NSMutableArray *clean = [NSMutableArray array];
        for (NSString *s in raw) { NSString *tr = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (tr.length > 0) [clean addObject:tr]; }
        m.filterKeywords = clean; [m saveSettings]; [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showGroupSelectForMode:(JJGrabMode)mode {
    JJRedBagGroupSelectController *vc = [[JJRedBagGroupSelectController alloc] initWithMode:mode];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showNotificationContactSelect {
    JJRedBagContactSelectController *vc = [[JJRedBagContactSelectController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showGroupReceiveSelect {
    JJRedBagReceiveGroupController *vc = [[JJRedBagReceiveGroupController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showReceiveReplyContentInput {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u6536\u6b3e\u56de\u590d\u5185\u5bb9" message:@"\u8bf7\u8f93\u5165\u6536\u6b3e\u540e\u81ea\u52a8\u56de\u590d\u5185\u5bb9" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"\u5df2\u6536\u5230\uff0c\u8c22\u8c22"; tf.text = m.receiveAutoReplyContent; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.receiveAutoReplyContent = alert.textFields.firstObject.text; [m saveSettings]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showReceiveNotificationContactSelect {
    JJRedBagContactSelectController *vc = [[JJRedBagContactSelectController alloc] init];
    vc.isReceiveMode = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showGameCheatModeSelector {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u9009\u62e9\u4f5c\u5f0a\u6a21\u5f0f" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *m1 = (m.gameCheatMode == 0) ? @"\u2705 \u6a21\u5f0f1\uff1a\u53d1\u9001\u65f6\u9009\u62e9" : @"\u6a21\u5f0f1\uff1a\u53d1\u9001\u65f6\u9009\u62e9";
    NSString *m2 = (m.gameCheatMode == 1) ? @"\u2705 \u6a21\u5f0f2\uff1a\u9884\u8bbe\u5e8f\u5217" : @"\u6a21\u5f0f2\uff1a\u9884\u8bbe\u5e8f\u5217";
    [alert addAction:[UIAlertAction actionWithTitle:m1 style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.gameCheatMode = 0; [m saveSettings]; [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:m2 style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.gameCheatMode = 1; [m saveSettings]; [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.view; alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1); }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showGameCheatSequenceInput:(BOOL)isDice {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    NSString *title = isDice ? @"\u8bbe\u7f6e\u9ab0\u5b50\u5e8f\u5217" : @"\u8bbe\u7f6e\u731c\u62f3\u5e8f\u5217";
    NSString *msg = isDice ? @"\u8f93\u51651-6\u7684\u6570\u5b57\u5e8f\u5217\uff0c0\u8868\u793a\u4e0d\u4f5c\u5f0a\u3002\n\u4f8b\uff1a\"22031\"" : @"1=\u526a\u5200 2=\u77f3\u5934 3=\u5e03\uff0c0\u8868\u793a\u4e0d\u4f5c\u5f0a\u3002\n\u4f8b\uff1a\"1302\"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = isDice ? @"\u5982\uff1a223016" : @"\u5982\uff1a132021"; tf.text = isDice ? m.gameCheatDiceSequence : m.gameCheatRPSSequence; tf.keyboardType = UIKeyboardTypeNumberPad; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *input = alert.textFields.firstObject.text;
        NSMutableString *filtered = [NSMutableString string];
        for (NSUInteger i = 0; i < input.length; i++) { unichar ch = [input characterAtIndex:i]; if (isDice) { if (ch>='0'&&ch<='6') [filtered appendFormat:@"%C",ch]; } else { if (ch>='0'&&ch<='3') [filtered appendFormat:@"%C",ch]; } }
        if (isDice) { m.gameCheatDiceSequence = filtered; m.gameCheatDiceIndex = 0; } else { m.gameCheatRPSSequence = filtered; m.gameCheatRPSIndex = 0; }
        [m saveSettings]; [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u6e05\u7a7a" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        if (isDice) { m.gameCheatDiceSequence = @""; m.gameCheatDiceIndex = 0; } else { m.gameCheatRPSSequence = @""; m.gameCheatRPSIndex = 0; }
        [m saveSettings]; [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetGameCheatProgress {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u91cd\u7f6e\u5e8f\u5217\u8fdb\u5ea6" message:@"\u5c06\u9ab0\u5b50\u548c\u731c\u62f3\u7684\u5e8f\u5217\u8fdb\u5ea6\u90fd\u91cd\u7f6e\u4e3a\u8d77\u59cb\u4f4d\u7f6e\u3002" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u786e\u8ba4\u91cd\u7f6e" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        JJRedBagManager *m = [JJRedBagManager sharedManager]; m.gameCheatDiceIndex = 0; m.gameCheatRPSIndex = 0; [m saveSettings]; [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)jj_clearEmoticonCache {
    NSString *cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"JJEmoticonCache"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
    if (!files || files.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u63d0\u793a" message:@"\u5f53\u524d\u6ca1\u6709\u7f13\u5b58\u6587\u4ef6" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"\u597d\u7684" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    unsigned long long totalSize = 0;
    for (NSString *file in files) { NSDictionary *attrs = [fm attributesOfItemAtPath:[cacheDir stringByAppendingPathComponent:file] error:nil]; totalSize += [attrs fileSize]; }
    NSString *sizeStr;
    if (totalSize < 1024) sizeStr = [NSString stringWithFormat:@"%lluB", totalSize];
    else if (totalSize < 1024*1024) sizeStr = [NSString stringWithFormat:@"%.1fKB", totalSize/1024.0];
    else sizeStr = [NSString stringWithFormat:@"%.1fMB", totalSize/(1024.0*1024.0)];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"\u6e05\u7406\u8868\u60c5\u7f13\u5b58" message:[NSString stringWithFormat:@"\u5171 %lu \u4e2a\u6587\u4ef6\uff0c\u5360\u7528 %@\n\u786e\u5b9a\u6e05\u7406\uff1f", (unsigned long)files.count, sizeStr] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u6e05\u7406" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [fm removeItemAtPath:cacheDir error:nil]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSUInteger)getSelectedGroupCount {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (m.grabMode == JJGrabModeExclude) return m.excludeGroups.count;
    if (m.grabMode == JJGrabModeOnly) return m.onlyGroups.count;
    if (m.grabMode == JJGrabModeDelay) return m.delayGroups.count;
    return 0;
}

@end
