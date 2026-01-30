#import "JJRedBagSettingsController.h"
#import "JJRedBagManager.h"
#import "JJRedBagGroupSelectController.h"
#import "JJRedBagContactSelectController.h"

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
    versionLabel.text = @"v1.0-1 仅供娱乐";
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
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (section == 0) {
        return 1; // 总开关
    } else if (section == 1) {
        if (!manager.enabled) return 0;
        if (manager.grabMode == JJGrabModeDelay) return 4;
        return 2;
    } else if (section == 2) {
        // 自动回复
        if (!manager.enabled) return 0;
        if (!manager.autoReplyEnabled) return 1;
        // 开启后: Switch, Private, Group, DelaySwitch, [DelayTime], Content
        NSUInteger count = 5;
        if (manager.autoReplyDelayEnabled) count++;
        return count;
    } else if (section == 3) {
        // 通知
        if (!manager.enabled) return 0;
        if (!manager.notificationEnabled) return 1;
        return 2; // Switch, Target
    } else if (section == 4) {
        // 其他设置
        if (!manager.enabled) return 0;
        NSUInteger count = 5;
        if (manager.filterKeywordEnabled) count++;
        return count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = nil;
    if (section == 1) title = @"模式设置";
    else if (section == 2) title = @"自动回复";
    else if (section == 3) title = @"红包通知";
    else if (section == 4) title = @"其他设置";
    
    if (!title) return nil;
    
    UIView *headerView = [[UIView alloc] init];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 5, tableView.bounds.size.width - 32, 30)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    if (@available(iOS 13.0, *)) {
        label.textColor = [UIColor secondaryLabelColor];
    } else {
        label.textColor = [UIColor grayColor];
    }
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0) return 20.0f; // 顶部留空
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (!manager.enabled) return 0.01f;
    
    return 40.0f; // 加大标题高度
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
        // 自动回复设置
        NSInteger row = indexPath.row;
        // 如果没有开启延迟，跳过延迟时间行
        if (!manager.autoReplyDelayEnabled && row > 3) {
            row++;
        }
        
        if (row == 0) {
            cell.textLabel.text = @"自动回复";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.autoReplyEnabled;
            sw.tag = 300;
            [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 1) {
            cell.textLabel.text = @"私聊自动回复";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.autoReplyPrivateEnabled;
            sw.tag = 301;
            [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 2) {
            cell.textLabel.text = @"群聊自动回复";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.autoReplyGroupEnabled;
            sw.tag = 302;
            [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 3) {
            cell.textLabel.text = @"延迟回复";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.autoReplyDelayEnabled;
            sw.tag = 303;
            [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 4) {
            cell.textLabel.text = @"延迟时间";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f 秒", manager.autoReplyDelayTime];
        } else if (row == 5) {
            cell.textLabel.text = @"回复内容";
            cell.detailTextLabel.text = (manager.autoReplyContent && manager.autoReplyContent.length > 0) ? manager.autoReplyContent : @"未设置";
        }
    } else if (indexPath.section == 3) {
        // 红包通知设置
        if (indexPath.row == 0) {
            cell.textLabel.text = @"已抢红包通知";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.notificationEnabled;
            sw.tag = 400;
            [sw addTarget:self action:@selector(notificationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"通知对象";
            cell.detailTextLabel.text = (manager.notificationChatName && manager.notificationChatName.length > 0) ? manager.notificationChatName : @"未设置";
        }
    } else if (indexPath.section == 4) {
        // 其他设置
        // 映射 indexPath.row 到实际功能
        // 如果开启了关键词过滤: 0=switch, 1=edit, 2=self, 3=private, 4=bg, 5=shake
        // 如果关闭了关键词过滤: 0=switch, 1=self, 2=private, 3=bg, 4=shake
        
        NSInteger row = indexPath.row;
        if (!manager.filterKeywordEnabled && row > 0) {
            row++; // 跳过编辑行
        }
        
        if (row == 0) {
            cell.textLabel.text = @"关键词过滤";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.filterKeywordEnabled;
            [sw addTarget:self action:@selector(filterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 1) {
            cell.textLabel.text = @"编辑关键词";
            cell.detailTextLabel.text = manager.filterKeywords.count > 0 ? [NSString stringWithFormat:@"%lu 个", (unsigned long)manager.filterKeywords.count] : @"未设置";
        } else if (row == 2) {
            cell.textLabel.text = @"抢自己的红包";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.grabSelfEnabled;
            sw.tag = 200;
            [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 3) {
            cell.textLabel.text = @"抢私聊红包";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.grabPrivateEnabled;
            sw.tag = 201;
            [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 4) {
            cell.textLabel.text = @"后台和锁屏自动抢";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.backgroundGrabEnabled;
            sw.tag = 202;
            [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (row == 5) {
            cell.textLabel.text = @"摇一摇呼出配置";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = manager.shakeToConfigEnabled;
            sw.tag = 203;
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
        NSInteger row = indexPath.row;
        if (!manager.autoReplyDelayEnabled && row > 3) {
            row++;
        }
        
        if (row == 4) [self showAutoReplyDelayTimeInput];
        else if (row == 5) [self showAutoReplyContentInput];
    } else if (indexPath.section == 3) {
        if (indexPath.row == 1) [self showNotificationContactSelect];
    } else if (indexPath.section == 4) {
        NSInteger row = indexPath.row;
        if (!manager.filterKeywordEnabled && row > 0) row++;
        
        if (row == 1) [self showKeywordEditor];
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
    
    // 动态插入或删除"编辑关键词"行
    NSIndexPath *editRowIndexPath = [NSIndexPath indexPathForRow:1 inSection:4];
    if (sender.on) {
        [self.tableView insertRowsAtIndexPaths:@[editRowIndexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView deleteRowsAtIndexPaths:@[editRowIndexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)otherSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 200) manager.grabSelfEnabled = sender.on;
    if (sender.tag == 201) manager.grabPrivateEnabled = sender.on;
    if (sender.tag == 202) manager.backgroundGrabEnabled = sender.on;
    if (sender.tag == 203) manager.shakeToConfigEnabled = sender.on;
    [manager saveSettings];
}

- (void)autoReplySwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 300) manager.autoReplyEnabled = sender.on;
    if (sender.tag == 301) manager.autoReplyPrivateEnabled = sender.on;
    if (sender.tag == 302) manager.autoReplyGroupEnabled = sender.on;
    if (sender.tag == 303) {
        manager.autoReplyDelayEnabled = sender.on;
        [manager saveSettings];
        
        // 动态插入或删除"延迟时间"行
        // section 2
        // 如果开启延迟: Switch(0), Private(1), Group(2), DelaySwitch(3), DelayTime(4), Content(5)
        // 如果关闭延迟: Switch(0), Private(1), Group(2), DelaySwitch(3), Content(4)
        
        NSIndexPath *delayTimePath = [NSIndexPath indexPathForRow:4 inSection:2];
        if (sender.on) {
            [self.tableView insertRowsAtIndexPaths:@[delayTimePath] withRowAnimation:UITableViewRowAnimationFade];
        } else {
            [self.tableView deleteRowsAtIndexPaths:@[delayTimePath] withRowAnimation:UITableViewRowAnimationFade];
        }
        return;
    }
    
    [manager saveSettings];
    [self.tableView reloadData]; // 刷新以更新依赖项显隐 (虽然目前除了delay外没有其他强依赖需要reload，但保持一致)
}

- (void)notificationSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 400) manager.notificationEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
}

#pragma mark - Alerts

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                   message:@"本插件仅供学习和娱乐使用。\n\n使用本插件可能导致微信账号被封禁等风险，风险需由您自行承担。\n\n作者不对任何后果负责。"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"我已知晓并承担风险 (3)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        JJRedBagManager *manager = [JJRedBagManager sharedManager];
        manager.hasShownDisclaimer = YES;
        manager.enabled = YES;
        [manager saveSettings];
        if (completion) completion(YES);
    }];
    confirmAction.enabled = NO;
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"那我不用了" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (completion) completion(NO);
    }];
    
    [alert addAction:confirmAction];
    [alert addAction:cancelAction];
    
    
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
