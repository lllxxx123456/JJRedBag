#import "JJRedBagSettingsController.h"
#import "JJRedBagManager.h"
#import "JJRedBagGroupSelectController.h"

@interface JJRedBagSettingsController ()
@property (nonatomic, strong) UISwitch *mainSwitch;
@end

@implementation JJRedBagSettingsController

- (instancetype)init {
    // 使用 iOS 13+ 的 InsetGrouped 风格，自带卡片效果，完美适配深色模式
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) {
        style = UITableViewStyleInsetGrouped;
    }
    if (self = [super initWithStyle:style]) {
        self.title = @"JJRedBag";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置主题色
    if (@available(iOS 13.0, *)) {
        self.view.tintColor = [UIColor systemRedColor];
    } else {
        self.view.tintColor = [UIColor redColor];
    }
    
    // 导航栏设置
    [self setupNavigationBar];
    
    // 头部视图
    [self setupHeaderView];
    
    // 注册Cell
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"JJCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    // 刷新头部状态
    [self updateHeaderStatus];
}

#pragma mark - UI Setup

- (void)setupNavigationBar {
    // 右上角关闭按钮
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSelf)];
    self.navigationItem.rightBarButtonItem = closeItem;
    
    // 导航栏外观
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
}

- (void)setupHeaderView {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 140)];
    
    // 顶部 Logo/Icon 区域
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    if (@available(iOS 13.0, *)) {
        iconView.image = [UIImage systemImageNamed:@"envelope.fill"]; // 使用系统图标
    }
    iconView.tintColor = [UIColor systemRedColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.center = CGPointMake(headerView.center.x, 50);
    iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [headerView addSubview:iconView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 90, headerView.bounds.size.width, 30)];
    titleLabel.text = @"JJRedBag";
    titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    
    if (@available(iOS 13.0, *)) {
        titleLabel.textColor = [UIColor labelColor];
    } else {
        titleLabel.textColor = [UIColor blackColor];
    }
    
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerView addSubview:titleLabel];
    
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, headerView.bounds.size.width, 20)];
    versionLabel.text = @"v1.0.1 仅供娱乐";
    versionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    
    if (@available(iOS 13.0, *)) {
        versionLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        versionLabel.textColor = [UIColor grayColor];
    }
    
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerView addSubview:versionLabel];
    
    self.tableView.tableHeaderView = headerView;
}

- (void)updateHeaderStatus {
    // 可以在这里更新头部状态，如果需要的话
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (section == 0) {
        return 1; // 总开关
    } else if (section == 1) {
        if (!manager.enabled) return 0; // 关闭时隐藏设置
        // 模式设置
        if (manager.grabMode == JJGrabModeDelay) return 4;
        return 2;
    } else if (section == 2) {
        if (!manager.enabled) return 0; // 关闭时隐藏设置
        // 其他/过滤设置
        return 4; // 关键词过滤, 编辑关键词, 抢自己, 抢私聊
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    if (section == 1) return @"模式设置";
    if (section == 2) return @"高级设置";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 使用 Value1 样式 (左边标题，右边详情/箭头)
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"JJCell"];
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        cell.textLabel.textColor = [UIColor blackColor];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    
    if (indexPath.section == 0) {
        // 总开关
        cell.textLabel.text = @"开启抢红包";
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.enabled;
        [sw addTarget:self action:@selector(mainSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        self.mainSwitch = sw;
        
    } else if (indexPath.section == 1) {
        // 模式设置
        if (indexPath.row == 0) {
            cell.textLabel.text = @"抢红包模式";
            if (manager.grabMode == JJGrabModeExclude) cell.detailTextLabel.text = @"黑名单模式 (不抢)";
            else if (manager.grabMode == JJGrabModeOnly) cell.detailTextLabel.text = @"白名单模式 (只抢)";
            else if (manager.grabMode == JJGrabModeDelay) cell.detailTextLabel.text = @"延迟模式";
            else cell.detailTextLabel.text = @"全抢模式";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"群聊管理";
            NSUInteger count = [self getSelectedGroupCount];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"已选 %lu 个群", (unsigned long)count];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"非列表群处理";
            cell.detailTextLabel.text = manager.delayOtherMode == JJDelayOtherModeNoDelay ? @"无延迟抢" : @"不抢";
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"延迟时间";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f 秒", manager.delayTime];
        }
        
    } else if (indexPath.section == 2) {
        // 高级设置
        if (indexPath.row == 0) {
            cell.textLabel.text = @"关键词过滤";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.filterKeywordEnabled;
            [sw addTarget:self action:@selector(filterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"编辑关键词";
            cell.detailTextLabel.text = manager.filterKeywords.count > 0 ? [NSString stringWithFormat:@"%lu 个", (unsigned long)manager.filterKeywords.count] : @"未设置";
            if (!manager.filterKeywordEnabled) {
                if (@available(iOS 13.0, *)) {
                    cell.textLabel.textColor = [UIColor tertiaryLabelColor];
                    cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
                } else {
                    cell.textLabel.textColor = [UIColor lightGrayColor];
                    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
                }
                cell.userInteractionEnabled = NO;
            }
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"抢自己的红包";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.grabSelfEnabled;
            sw.tag = 200;
            [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"抢私聊红包";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.grabPrivateEnabled;
            sw.tag = 201;
            [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    if (indexPath.section == 1) {
        if (indexPath.row == 0) [self showModeSelector];
        else if (indexPath.row == 1) [self showGroupSelectForMode:manager.grabMode];
        else if (indexPath.row == 2) [self showDelayOtherModeSelector];
        else if (indexPath.row == 3) [self showDelayTimeInput];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 1) [self showKeywordEditor];
    }
}

#pragma mark - Logic Helpers

- (NSUInteger)getSelectedGroupCount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.grabMode == JJGrabModeExclude) return manager.excludeGroups.count;
    if (manager.grabMode == JJGrabModeOnly) return manager.onlyGroups.count;
    if (manager.grabMode == JJGrabModeDelay) return manager.delayGroups.count;
    return 0;
}

#pragma mark - Actions

- (void)mainSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    if (sender.on && !manager.hasShownDisclaimer) {
        sender.on = NO;
        [self showDisclaimerAlertWithCompletion:^(BOOL accepted) {
            if (accepted) {
                manager.enabled = YES;
                [manager saveSettings];
                [self.tableView reloadData];
            }
        }];
    } else {
        manager.enabled = sender.on;
        [manager saveSettings];
        // 重新加载以显示/隐藏其他选项
        [self.tableView reloadData];
    }
}

- (void)filterSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.filterKeywordEnabled = sender.on;
    [manager saveSettings];
    // 刷新"编辑关键词"行的状态
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:2]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)otherSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 200) manager.grabSelfEnabled = sender.on;
    if (sender.tag == 201) manager.grabPrivateEnabled = sender.on;
    [manager saveSettings];
}

#pragma mark - Alerts

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                   message:@"本插件仅供学习和娱乐使用。\n\n使用本插件可能导致微信账号被封禁等风险，风险需由您自行承担。\n\n作者不对任何后果负责。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (completion) completion(NO);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"我已知晓并承担风险" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        JJRedBagManager *manager = [JJRedBagManager sharedManager];
        manager.hasShownDisclaimer = YES;
        if (completion) completion(YES);
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择模式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    void (^handler)(JJGrabMode) = ^(JJGrabMode mode) {
        manager.grabMode = mode;
        [manager saveSettings];
        [self.tableView reloadData];
    };
    
    [alert addAction:[UIAlertAction actionWithTitle:@"黑名单模式 (不抢选中的群)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { handler(JJGrabModeExclude); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"白名单模式 (只抢选中的群)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { handler(JJGrabModeOnly); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"延迟模式 (选中的群延迟抢)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { handler(JJGrabModeDelay); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"全抢模式 (所有群都抢)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { handler(JJGrabModeNone); }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // 适配 iPad
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showGroupSelectForMode:(JJGrabMode)mode {
    JJRedBagGroupSelectController *vc = [[JJRedBagGroupSelectController alloc] initWithMode:mode];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDelayOtherModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"非延迟列表群的处理" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"无延迟抢" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        manager.delayOtherMode = JJDelayOtherModeNoDelay;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"不抢" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        manager.delayOtherMode = JJDelayOtherModeNoGrab;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDelayTimeInput {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置延迟时间" message:@"请输入秒数 (支持小数)" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"1.0";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.1f", manager.delayTime];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields.firstObject;
        double val = [field.text doubleValue];
        if (val < 0) val = 0;
        manager.delayTime = val;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showKeywordEditor {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"编辑关键词" message:@"用逗号分隔，包含任一关键词的红包将不抢" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"测挂,专属";
        textField.text = [manager.filterKeywords componentsJoinedByString:@","];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        NSArray *raw = [text componentsSeparatedByString:@","];
        NSMutableArray *clean = [NSMutableArray array];
        for (NSString *s in raw) {
            NSString *trimmed = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) [clean addObject:trimmed];
        }
        manager.filterKeywords = clean;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
