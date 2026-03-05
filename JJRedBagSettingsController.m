#import "JJRedBagSettingsController.h"
#import "JJRedBagManager.h"
#import "JJRedBagGroupSelectController.h"
#import "JJRedBagContactSelectController.h"
#import "JJRedBagMemberSelectController.h"
#import "JJRedBagReceiveGroupController.h"

@interface JJRedBagSettingsController ()
@property (nonatomic, strong) UISwitch *mainSwitch;
@property (nonatomic, strong) UILabel *amountLabel;
@end

@implementation JJRedBagSettingsController

- (instancetype)init {
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
    
    if (@available(iOS 13.0, *)) {
        self.view.tintColor = [UIColor systemRedColor];
    } else {
        self.view.tintColor = [UIColor redColor];
    }
    
    [self setupNavigationBar];
    [self setupHeaderView];
    // [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"JJCell"]; // Removed to support Value1 style
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateAmountLabel];
    [self.tableView reloadData];
}

#pragma mark - UI Setup

- (void)setupNavigationBar {
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSelf)];
    self.navigationItem.rightBarButtonItem = closeItem;
}

- (void)setupHeaderView {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 160)];
    
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
    if (@available(iOS 13.0, *)) {
        iconView.image = [UIImage systemImageNamed:@"envelope.fill"];
    }
    iconView.tintColor = [UIColor systemRedColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.center = CGPointMake(headerView.center.x, 40);
    iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [headerView addSubview:iconView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 75, headerView.bounds.size.width, 25)];
    titleLabel.text = @"JJRedBag v1.0-1";
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        titleLabel.textColor = [UIColor labelColor];
    }
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerView addSubview:titleLabel];
    
    self.amountLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 110, headerView.bounds.size.width, 30)];
    self.amountLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.amountLabel.textColor = [UIColor systemRedColor];
    self.amountLabel.textAlignment = NSTextAlignmentCenter;
    self.amountLabel.userInteractionEnabled = YES;
    self.amountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAmountTap)];
    [self.amountLabel addGestureRecognizer:tap];
    
    [headerView addSubview:self.amountLabel];
    
    self.tableView.tableHeaderView = headerView;
    [self updateAmountLabel];
}

- (void)updateAmountLabel {
    double amount = [JJRedBagManager sharedManager].totalAmount / 100.0;
    self.amountLabel.text = [NSString stringWithFormat:@"为您抢了：%.2f 元", amount];
}

- (void)handleAmountTap {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    double amount = manager.totalAmount / 100.0;
    
    NSString *message = [NSString stringWithFormat:@"恭喜发财！\n\n已为您抢了：%.2f元", amount];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"谢谢作者" style:UIAlertActionStyleDefault handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"直接置零" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        JJRedBagManager *manager = [JJRedBagManager sharedManager];
        manager.totalAmount = 0;
        [manager saveSettings];
        [self updateAmountLabel];
    }]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.amountLabel;
        alert.popoverPresentationController.sourceRect = self.amountLabel.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 9;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    // Section 0: Global
    if (section == 0) return 1;
    
    // Section 1: Mode & Targets
    if (section == 1) {
        NSInteger count = 3; // Mode, Self, Private
        if (manager.grabMode != JJGrabModeNone) {
            if (manager.grabMode == JJGrabModeExclude || manager.grabMode == JJGrabModeOnly || manager.grabMode == JJGrabModeDelay) {
                count++; // Group Select
            }
            if (manager.grabMode == JJGrabModeDelay) {
                count += 2; // OtherGroups, DelayTime
            }
        }
        return count;
    }
    
    // Section 2: Filter & Background
    if (section == 2) {
        NSInteger count = 3;
        if (manager.backgroundGrabEnabled) count++; // 保活模式选择
        if (manager.filterKeywordEnabled) count++;
        return count;
    }
    
    // Section 3: Auto Reply
    if (section == 3) {
        if (!manager.autoReplyEnabled) return 1;
        NSInteger count = 5;
        if (manager.autoReplyDelayEnabled) count++;
        return count;
    }
    
    // Section 4: Notification
    if (section == 4) {
        NSInteger count = 2; // Switch, Local Switch
        if (manager.notificationEnabled) count++; // Target
        return count;
    }
    
    // Section 5: Auto Receive (收款设置)
    if (section == 5) {
        NSInteger count = 2; // 私聊收款, 群聊收款
        if (manager.autoReceiveGroupEnabled) {
            count++; // 群聊收款列表
        }
        count += 2; // 私聊回复, 群聊回复
        if (manager.receiveAutoReplyPrivateEnabled || manager.receiveAutoReplyGroupEnabled) {
            count++; // 回复内容
        }
        count++; // 收款通知
        if (manager.receiveNotificationEnabled) {
            count++; // 收款通知接收人
        }
        count++; // 本地通知
        return count;
    }
    
    // Section 6: 表情包缩放
    if (section == 6) {
        JJRedBagManager *mgr = [JJRedBagManager sharedManager];
        if (mgr.emoticonScaleEnabled) {
            return 2; // 开关 + 缓存管理
        }
        return 1; // 仅开关
    }
    
    // Section 7: 界面优化
    if (section == 7) return 2;
    
    // Section 8: 小游戏作弊
    if (section == 8) {
        JJRedBagManager *mgr = [JJRedBagManager sharedManager];
        if (!mgr.gameCheatEnabled) return 1;
        if (mgr.gameCheatMode == 0) return 2; // 开关 + 模式
        return 5; // 开关 + 模式 + 骰子序列 + 猜拳序列 + 重置进度
    }
    
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = nil;
    if (section == 1) title = @"红包设置";
    if (section == 2) title = @"高级功能";
    if (section == 3) title = @"自动回复";
    if (section == 4) title = @"通知统计";
    if (section == 5) title = @"自动收款";
    if (section == 6) title = @"表情包工具";
    if (section == 7) title = @"界面优化";
    if (section == 8) title = @"小游戏作弊";
    
    if (!title) return nil;
    
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, tableView.bounds.size.width - 40, 32)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    if (@available(iOS 13.0, *)) {
        label.textColor = [UIColor labelColor];
    } else {
        label.textColor = [UIColor blackColor];
    }
    [view addSubview:label];
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0) return 10;
    return 44;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil; // Using viewForHeaderInSection
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"JJCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    }
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    // Reset cell
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.indentationLevel = 0;
    cell.indentationWidth = 0;
    
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    
    // Font setup - 默认子项字体
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"插件主开关";
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.enabled;
        [sw addTarget:self action:@selector(mainSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
    } else if (indexPath.section == 1) {
        [self configureSection1:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 2) {
        [self configureSection2:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 3) {
        [self configureSection3:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 4) {
        [self configureSection4:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 5) {
        [self configureSection5:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 6) {
        [self configureSection6:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 7) {
        [self configureSection7:cell indexPath:indexPath manager:manager];
    } else if (indexPath.section == 8) {
        [self configureSection8:cell indexPath:indexPath manager:manager];
    }
    
    return cell;
}

- (void)configureSection1:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    NSInteger row = indexPath.row;
    
    if (row == 0) {
        cell.textLabel.text = @"⤷ 抢红包模式";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        if (manager.grabMode == JJGrabModeExclude) cell.detailTextLabel.text = @"黑名单模式";
        else if (manager.grabMode == JJGrabModeOnly) cell.detailTextLabel.text = @"白名单模式";
        else if (manager.grabMode == JJGrabModeDelay) cell.detailTextLabel.text = @"延迟抢模式";
        else cell.detailTextLabel.text = @"全自动模式";
        return;
    }
    
    BOOL hasGroupSelect = (manager.grabMode == JJGrabModeExclude || manager.grabMode == JJGrabModeOnly || manager.grabMode == JJGrabModeDelay);
    BOOL isDelayMode = (manager.grabMode == JJGrabModeDelay);
    
    int currentIndex = 1;
    
    if (hasGroupSelect) {
        if (row == currentIndex) {
            cell.textLabel.text = @"⤷ 选群聊列表";
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            NSUInteger count = [self getSelectedGroupCount];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"已选 %lu 个", (unsigned long)count];
            return;
        }
        currentIndex++;
    }
    
    if (isDelayMode) {
        if (row == currentIndex) {
            cell.textLabel.text = @"⤷ 其他群模式";
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.text = manager.delayOtherMode == JJDelayOtherModeNoDelay ? @"无延迟抢" : @"直接不抢";
            return;
        }
        currentIndex++;
        
        if (row == currentIndex) {
            cell.textLabel.text = @"⤷ 延迟抢秒数";
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f 秒", manager.delayTime];
            return;
        }
        currentIndex++;
    }
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 抢自己红包";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.grabSelfEnabled;
        sw.tag = 200;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 抢私聊红包";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.grabPrivateEnabled;
        sw.tag = 201;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
}

- (void)configureSection2:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    NSInteger row = indexPath.row;
    NSInteger currentIndex = 0;
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 后台保活";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.backgroundGrabEnabled;
        sw.tag = 202;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    if (manager.backgroundGrabEnabled) {
        if (row == currentIndex) {
            cell.textLabel.text = @"    ⤷ 保活模式";
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            NSString *modeName = @"省电模式";
            if (manager.backgroundMode == JJBackgroundModeAudio) modeName = @"强力模式";
            cell.detailTextLabel.text = modeName;
            return;
        }
        currentIndex++;
    }
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 摇一摇配置";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.shakeToConfigEnabled;
        sw.tag = 203;
        [sw addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 过滤关键词";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.filterKeywordEnabled;
        [sw addTarget:self action:@selector(filterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    if (row == currentIndex) {
        cell.textLabel.text = @"    ⤷ 关键词列表";
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        if (manager.filterKeywords.count > 0) {
            cell.detailTextLabel.text = [manager.filterKeywords componentsJoinedByString:@", "];
        } else {
            cell.detailTextLabel.text = @"未设置";
        }
    }
}

- (void)configureSection3:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    NSInteger row = indexPath.row;
    
    if (row == 0) {
        cell.textLabel.text = @"⤷ 自动回复开";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.autoReplyEnabled;
        sw.tag = 300;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    
    NSInteger index = row;
    
    if (index == 1) {
        cell.textLabel.text = @"    ⤷ 私聊回复";
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.autoReplyPrivateEnabled;
        sw.tag = 301;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (index == 2) {
        cell.textLabel.text = @"    ⤷ 群聊回复";
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.autoReplyGroupEnabled;
        sw.tag = 302;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (index == 3) {
        cell.textLabel.text = @"    ⤷ 延迟回复";
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.autoReplyDelayEnabled;
        sw.tag = 303;
        [sw addTarget:self action:@selector(autoReplySwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        BOOL showDelayTime = manager.autoReplyDelayEnabled;
        NSInteger contentIndex = showDelayTime ? 5 : 4;
        NSInteger delayIndex = 4;
        
        if (showDelayTime && index == delayIndex) {
            cell.textLabel.text = @"        ⤷ 延迟秒数";
            cell.textLabel.font = [UIFont systemFontOfSize:13];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f 秒", manager.autoReplyDelayTime];
        } else if (index == contentIndex) {
            cell.textLabel.text = @"    ⤷ 回复内容";
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            cell.detailTextLabel.text = (manager.autoReplyContent && manager.autoReplyContent.length > 0) ? manager.autoReplyContent : @"未设置";
        }
    }
}

- (void)configureSection4:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    NSInteger row = indexPath.row;
    int currentIndex = 0;
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 消息通知开";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.notificationEnabled;
        sw.tag = 400;
        [sw addTarget:self action:@selector(notificationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    if (manager.notificationEnabled) {
        if (row == currentIndex) {
            cell.textLabel.text = @"    ⤷ 通知接收人";
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            cell.detailTextLabel.text = (manager.notificationChatName && manager.notificationChatName.length > 0) ? manager.notificationChatName : @"点击设置";
            return;
        }
        currentIndex++;
    }
    
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 弹窗通知开";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.localNotificationEnabled;
        sw.tag = 401;
        [sw addTarget:self action:@selector(notificationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
}

- (void)configureSection5:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    NSInteger row = indexPath.row;
    NSInteger currentIndex = 0;
    
    // 私聊自动收款
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 私聊自动收款";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.autoReceivePrivateEnabled;
        sw.tag = 501;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    // 群聊自动收款
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 群聊自动收款";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.autoReceiveGroupEnabled;
        sw.tag = 502;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    // 群聊收款列表（指定群）
    if (manager.autoReceiveGroupEnabled) {
        if (row == currentIndex) {
            cell.textLabel.text = @"⤷ 指定收款群";
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            NSInteger groupCount = manager.receiveGroups.count;
            cell.detailTextLabel.text = groupCount > 0 ? [NSString stringWithFormat:@"已选%ld个群", (long)groupCount] : @"全部群";
            return;
        }
        currentIndex++;
    }
    
    // 私聊收款回复
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 私聊收款回复";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.receiveAutoReplyPrivateEnabled;
        sw.tag = 503;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    // 群聊收款回复
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 群聊收款回复";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.receiveAutoReplyGroupEnabled;
        sw.tag = 504;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    // 回复内容
    if (manager.receiveAutoReplyPrivateEnabled || manager.receiveAutoReplyGroupEnabled) {
        if (row == currentIndex) {
            cell.textLabel.text = @"⤷ 回复内容";
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.text = manager.receiveAutoReplyContent.length > 0 ? manager.receiveAutoReplyContent : @"点击设置";
            return;
        }
        currentIndex++;
    }
    
    // 收款消息通知
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 收款消息通知";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.receiveNotificationEnabled;
        sw.tag = 505;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    currentIndex++;
    
    // 收款通知接收人
    if (manager.receiveNotificationEnabled) {
        if (row == currentIndex) {
            cell.textLabel.text = @"⤷ 通知接收人";
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.text = manager.receiveNotificationChatName.length > 0 ? manager.receiveNotificationChatName : @"点击设置";
            return;
        }
        currentIndex++;
    }
    
    // 收款弹窗通知
    if (row == currentIndex) {
        cell.textLabel.text = @"⤷ 收款弹窗通知";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.receiveLocalNotificationEnabled;
        sw.tag = 506;
        [sw addTarget:self action:@selector(receiveSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
}

- (void)configureSection6:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    if (indexPath.row == 0) {
        cell.textLabel.text = @"⤷ 表情包缩放";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.emoticonScaleEnabled;
        sw.tag = 600;
        [sw addTarget:self action:@selector(emoticonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row == 1) {
        // 缓存管理行
        NSString *cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"JJEmoticonCache"];
        unsigned long long totalSize = 0;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
        for (NSString *file in files) {
            NSString *fullPath = [cacheDir stringByAppendingPathComponent:file];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            totalSize += [attrs fileSize];
        }
        NSString *sizeStr;
        if (totalSize == 0) {
            sizeStr = @"无缓存";
        } else if (totalSize < 1024) {
            sizeStr = [NSString stringWithFormat:@"%lluB", totalSize];
        } else if (totalSize < 1024 * 1024) {
            sizeStr = [NSString stringWithFormat:@"%.1fKB", totalSize / 1024.0];
        } else {
            sizeStr = [NSString stringWithFormat:@"%.1fMB", totalSize / (1024.0 * 1024.0)];
        }
        cell.textLabel.text = [NSString stringWithFormat:@"    表情缓存：%@", sizeStr];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
}

- (void)configureSection7:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    if (indexPath.row == 0) {
        cell.textLabel.text = @"⤷ 隐藏语音搜索按钮";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.hideVoiceSearchButton;
        sw.tag = 700;
        [sw addTarget:self action:@selector(hideFeatureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"⤷ 隐藏上次分组提示";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.hideLastGroupLabel;
        sw.tag = 701;
        [sw addTarget:self action:@selector(hideFeatureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

- (void)configureSection8:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath manager:(JJRedBagManager *)manager {
    if (indexPath.row == 0) {
        cell.textLabel.text = @"⤷ 小游戏作弊";
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = manager.gameCheatEnabled;
        sw.tag = 800;
        [sw addTarget:self action:@selector(gameCheatSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row == 1) {
        NSString *modeText = (manager.gameCheatMode == 0) ? @"模式1：发送时选择" : @"模式2：预设序列";
        cell.textLabel.text = [NSString stringWithFormat:@"    当前：%@", modeText];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.row == 2) {
        NSString *seq = manager.gameCheatDiceSequence.length > 0 ? manager.gameCheatDiceSequence : @"未设置";
        NSInteger idx = manager.gameCheatDiceIndex;
        NSString *progress = (manager.gameCheatDiceSequence.length > 0) ? 
            [NSString stringWithFormat:@"(%ld/%lu)", (long)idx, (unsigned long)manager.gameCheatDiceSequence.length] : @"";
        cell.textLabel.text = [NSString stringWithFormat:@"    🎲 骰子序列：%@ %@", seq, progress];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.row == 3) {
        NSString *seq = manager.gameCheatRPSSequence.length > 0 ? manager.gameCheatRPSSequence : @"未设置";
        NSInteger idx = manager.gameCheatRPSIndex;
        NSString *progress = (manager.gameCheatRPSSequence.length > 0) ? 
            [NSString stringWithFormat:@"(%ld/%lu)", (long)idx, (unsigned long)manager.gameCheatRPSSequence.length] : @"";
        cell.textLabel.text = [NSString stringWithFormat:@"    ✊ 猜拳序列：%@ %@", seq, progress];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.row == 4) {
        cell.textLabel.text = @"    🔄 重置序列进度";
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self showModeSelector];
            return;
        }
        
        BOOL hasGroupSelect = (manager.grabMode == JJGrabModeExclude || manager.grabMode == JJGrabModeOnly || manager.grabMode == JJGrabModeDelay);
        BOOL isDelayMode = (manager.grabMode == JJGrabModeDelay);
        
        int currentIndex = 1;
        if (hasGroupSelect) {
            if (indexPath.row == currentIndex) {
                [self showGroupSelectForMode:manager.grabMode];
                return;
            }
            currentIndex++;
        }
        if (isDelayMode) {
            if (indexPath.row == currentIndex) {
                [self showDelayOtherModeSelector];
                return;
            }
            currentIndex++;
            if (indexPath.row == currentIndex) {
                [self showDelayTimeInput];
                return;
            }
            currentIndex++;
        }
        
    } else if (indexPath.section == 2) {
        NSInteger currentIndex = 0;
        currentIndex++; // 跳过后台防杀冻(row 0)
        
        if (manager.backgroundGrabEnabled) {
            if (indexPath.row == currentIndex) {
                [self showBackgroundModeSelector];
                return;
            }
            currentIndex++;
        }
        
        currentIndex++; // 跳过摇一摇配置
        currentIndex++; // 跳过过滤关键词
        
        if (manager.filterKeywordEnabled && indexPath.row == currentIndex) {
            [self showKeywordEditor];
        }
    } else if (indexPath.section == 3) {
        NSInteger row = indexPath.row;
        if (manager.autoReplyDelayEnabled) {
            if (row == 4) [self showAutoReplyDelayTimeInput];
            if (row == 5) [self showAutoReplyContentInput];
        } else {
            if (row == 4) [self showAutoReplyContentInput];
        }
    } else if (indexPath.section == 4) {
        if (manager.notificationEnabled && indexPath.row == 1) {
            [self showNotificationContactSelect];
        }
    } else if (indexPath.section == 5) {
        NSInteger currentIndex = 2; // 跳过私聊/群聊开关
        if (manager.autoReceiveGroupEnabled) {
            if (indexPath.row == currentIndex) {
                [self showGroupReceiveSelect];
                return;
            }
            currentIndex++;
        }
        currentIndex += 2; // 跳过私聊/群聊回复开关
        if (manager.receiveAutoReplyPrivateEnabled || manager.receiveAutoReplyGroupEnabled) {
            if (indexPath.row == currentIndex) {
                [self showReceiveReplyContentInput];
                return;
            }
            currentIndex++;
        }
        currentIndex++; // 跳过收款消息通知开关
        if (manager.receiveNotificationEnabled) {
            if (indexPath.row == currentIndex) {
                [self showReceiveNotificationContactSelect];
                return;
            }
        }
    } else if (indexPath.section == 6) {
        if (indexPath.row == 1) {
            // 点击清理缓存
            [self jj_clearEmoticonCache];
        }
    } else if (indexPath.section == 8) {
        if (indexPath.row == 1) {
            [self showGameCheatModeSelector];
        } else if (indexPath.row == 2) {
            [self showGameCheatSequenceInput:YES]; // 骰子
        } else if (indexPath.row == 3) {
            [self showGameCheatSequenceInput:NO]; // 猜拳
        } else if (indexPath.row == 4) {
            [self resetGameCheatProgress];
        }
    }
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
        [self.tableView reloadData];
    }
}

- (void)boolSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 200) manager.grabSelfEnabled = sender.on;
    if (sender.tag == 201) manager.grabPrivateEnabled = sender.on;
    if (sender.tag == 202) {
        manager.backgroundGrabEnabled = sender.on;
        [manager saveSettings];
        [self.tableView reloadData];
        return;
    }
    if (sender.tag == 203) {
        manager.shakeToConfigEnabled = sender.on;
        if (sender.on) {
            [self showShakeHintAlert];
        }
    }
    [manager saveSettings];
}

- (void)filterSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.filterKeywordEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
}

- (void)autoReplySwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 300) {
        manager.autoReplyEnabled = sender.on;
        if (sender.on) {
            if (!manager.autoReplyContent || manager.autoReplyContent.length == 0) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"需自定义自动回复内容，否则不起作用" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [self showAutoReplyContentInput];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    }
    if (sender.tag == 301) manager.autoReplyPrivateEnabled = sender.on;
    if (sender.tag == 302) manager.autoReplyGroupEnabled = sender.on;
    if (sender.tag == 303) manager.autoReplyDelayEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
}

- (void)notificationSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 400) {
        manager.notificationEnabled = sender.on;
        if (sender.on) {
            if (!manager.notificationChatId || manager.notificationChatId.length == 0) {
                manager.notificationChatId = @"filehelper";
                manager.notificationChatName = @"文件传输助手";
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"默认发送至《文件传输助手》" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    }
    if (sender.tag == 401) manager.localNotificationEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
}

- (void)receiveSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 501) manager.autoReceivePrivateEnabled = sender.on;
    if (sender.tag == 502) manager.autoReceiveGroupEnabled = sender.on;
    if (sender.tag == 503) manager.receiveAutoReplyPrivateEnabled = sender.on;
    if (sender.tag == 504) manager.receiveAutoReplyGroupEnabled = sender.on;
    if (sender.tag == 505) manager.receiveNotificationEnabled = sender.on;
    if (sender.tag == 506) manager.receiveLocalNotificationEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
}

- (void)emoticonSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.emoticonScaleEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
    
    if (sender.on) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"表情包缩放功能" 
            message:@"开启后，长按聊天界面的表情包，在菜单中选择「大大小小」，可以选择：\n\n• 放大 1.5x ~ 3.0x\n• 缩小 0.5x ~ 0.75x\n• 自定义倍数\n\n选择后将自动发送调整后的表情包。" 
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)hideFeatureSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (sender.tag == 700) {
        manager.hideVoiceSearchButton = sender.on;
        if (sender.on && !manager.hasShownHideVoiceAlert) {
            manager.hasShownHideVoiceAlert = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"隐藏语音搜索按钮" 
                message:@"开启后将隐藏微信搜索界面底部的「按住语音提问或搜索网络」按钮。\n\n关闭此开关即可恢复显示。" 
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    if (sender.tag == 701) {
        manager.hideLastGroupLabel = sender.on;
        if (sender.on && !manager.hasShownHideGroupAlert) {
            manager.hasShownHideGroupAlert = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"隐藏上次分组提示" 
                message:@"开启后将隐藏发布朋友圈时显示的「上次分组：xxx」提示。\n\n关闭此开关即可恢复显示。" 
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    [manager saveSettings];
    [self.tableView reloadData];
}

- (void)gameCheatSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.gameCheatEnabled = sender.on;
    [manager saveSettings];
    [self.tableView reloadData];
    
    if (sender.on && !manager.hasShownGameCheatAlert) {
        manager.hasShownGameCheatAlert = YES;
        [manager saveSettings];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎮 小游戏作弊" 
            message:@"开启后可对骰子和猜拳进行作弊：\n\n【模式1】发送时选择\n每次发送骰子/猜拳时弹出选择面板，手动选择想要的结果。\n\n【模式2】预设序列\n提前设置结果序列，发送时自动按序列出结果。\n• 骰子：输入1-6的数字，如\"223\"表示依次出2、2、3点\n• 猜拳：1=剪刀 2=石头 3=布，如\"132\"表示依次出剪刀、布、石头\n• 输入0表示该次不作弊（随机）\n• 序列用完后恢复正常发送" 
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)showGameCheatModeSelector {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择作弊模式"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    NSString *mode1Title = (manager.gameCheatMode == 0) ? @"✅ 模式1：发送时选择" : @"模式1：发送时选择";
    NSString *mode2Title = (manager.gameCheatMode == 1) ? @"✅ 模式2：预设序列" : @"模式2：预设序列";
    
    [alert addAction:[UIAlertAction actionWithTitle:mode1Title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        manager.gameCheatMode = 0;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:mode2Title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        manager.gameCheatMode = 1;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showGameCheatSequenceInput:(BOOL)isDice {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSString *title = isDice ? @"设置骰子序列" : @"设置猜拳序列";
    NSString *message = isDice ? 
        @"输入1-6的数字序列，每位代表一次骰子结果。\n输入0表示该次不作弊。\n例：\"22031\"表示依次出2、2、随机、3、1" :
        @"输入1-3的数字序列：1=剪刀 2=石头 3=布\n输入0表示该次不作弊。\n例：\"1302\"表示依次出剪刀、布、随机、石头";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = isDice ? @"如：223016" : @"如：132021";
        tf.text = isDice ? manager.gameCheatDiceSequence : manager.gameCheatRPSSequence;
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *input = alert.textFields.firstObject.text;
        // 过滤非法字符
        NSMutableString *filtered = [NSMutableString string];
        for (NSUInteger i = 0; i < input.length; i++) {
            unichar ch = [input characterAtIndex:i];
            if (isDice) {
                if (ch >= '0' && ch <= '6') [filtered appendFormat:@"%C", ch];
            } else {
                if (ch >= '0' && ch <= '3') [filtered appendFormat:@"%C", ch];
            }
        }
        if (isDice) {
            manager.gameCheatDiceSequence = filtered;
            manager.gameCheatDiceIndex = 0;
        } else {
            manager.gameCheatRPSSequence = filtered;
            manager.gameCheatRPSIndex = 0;
        }
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        if (isDice) {
            manager.gameCheatDiceSequence = @"";
            manager.gameCheatDiceIndex = 0;
        } else {
            manager.gameCheatRPSSequence = @"";
            manager.gameCheatRPSIndex = 0;
        }
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetGameCheatProgress {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置序列进度"
                                                                  message:@"将骰子和猜拳的序列进度都重置为起始位置。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        JJRedBagManager *manager = [JJRedBagManager sharedManager];
        manager.gameCheatDiceIndex = 0;
        manager.gameCheatRPSIndex = 0;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)jj_clearEmoticonCache {
    NSString *cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"JJEmoticonCache"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
    
    if (!files || files.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"当前没有缓存文件" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // 计算大小
    unsigned long long totalSize = 0;
    for (NSString *file in files) {
        NSString *fullPath = [cacheDir stringByAppendingPathComponent:file];
        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        totalSize += [attrs fileSize];
    }
    
    NSString *sizeStr;
    if (totalSize < 1024) {
        sizeStr = [NSString stringWithFormat:@"%lluB", totalSize];
    } else if (totalSize < 1024 * 1024) {
        sizeStr = [NSString stringWithFormat:@"%.1fKB", totalSize / 1024.0];
    } else {
        sizeStr = [NSString stringWithFormat:@"%.1fMB", totalSize / (1024.0 * 1024.0)];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理表情缓存"
                                                                   message:[NSString stringWithFormat:@"共 %lu 个文件，占用 %@\n确定清理？", (unsigned long)files.count, sizeStr]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [fm removeItemAtPath:cacheDir error:nil];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Alerts & Selectors

- (void)showShakeHintAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"开启后，在微信界面摇一摇手机即可快速打开此设置页面。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showBackgroundModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择保活模式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"省电模式（定时刷新）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        manager.backgroundMode = JJBackgroundModeTimer;
        [manager saveSettings];
        [self.tableView reloadData];
        [self showBackgroundModeHint:JJBackgroundModeTimer];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"强力模式（无声音频）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        manager.backgroundMode = JJBackgroundModeAudio;
        [manager saveSettings];
        [self.tableView reloadData];
        [self showBackgroundModeHint:JJBackgroundModeAudio];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showBackgroundModeHint:(JJBackgroundMode)mode {
    NSString *title = nil;
    NSString *message = nil;
    
    switch (mode) {
        case JJBackgroundModeTimer:
            title = @"省电模式";
            message = @"通过定时刷新后台任务保持活跃。\n\n优点：耗电最少\n缺点：系统资源紧张时可能被终止，保活效果一般\n\n适合：对耗电敏感，不要求100%抢到";
            break;
        case JJBackgroundModeAudio:
            title = @"强力模式";
            message = @"通过播放无声音频保持后台运行。\n\n优点：最稳定，几乎不会被系统终止\n缺点：耗电较多，可能导致发热\n\n适合：必须确保后台抢红包成功";
            break;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择抢红包模式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *modes = @[@"全自动模式 (全抢)", @"黑名单模式 (不抢列表)", @"白名单模式 (只抢列表)", @"延迟抢模式"];
    for (int i = 0; i < modes.count; i++) {
        [alert addAction:[UIAlertAction actionWithTitle:modes[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            manager.grabMode = (JJGrabMode)i;
            [manager saveSettings];
            [self.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDelayOtherModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"非列表群处理" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"无延迟抢" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        manager.delayOtherMode = JJDelayOtherModeNoDelay;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"直接不抢" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
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

- (void)showAutoReplyDelayTimeInput {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"回复延迟" message:@"请输入秒数" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.1f", manager.autoReplyDelayTime];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        double val = [alert.textFields.firstObject.text doubleValue];
        if (val < 0) val = 0;
        manager.autoReplyDelayTime = val;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAutoReplyContentInput {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"回复内容" message:@"请输入自动回复内容" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"谢谢老板";
        textField.text = manager.autoReplyContent;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        manager.autoReplyContent = alert.textFields.firstObject.text;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showKeywordEditor {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加过滤关键词" message:@"用逗号分隔" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [manager.filterKeywords componentsJoinedByString:@","];
        textField.placeholder = @"测挂,专属";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        // 支持中文逗号，替换为英文逗号
        text = [text stringByReplacingOccurrencesOfString:@"，" withString:@","];
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

- (void)showDisclaimerAlertWithCompletion:(void(^)(BOOL accepted))completion {
    [[JJRedBagManager sharedManager] showDisclaimerAlertWithCompletion:completion];
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
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收款回复内容" message:@"请输入收款后自动回复内容" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"已收到，谢谢";
        textField.text = manager.receiveAutoReplyContent;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        manager.receiveAutoReplyContent = alert.textFields.firstObject.text;
        [manager saveSettings];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showReceiveNotificationContactSelect {
    JJRedBagContactSelectController *vc = [[JJRedBagContactSelectController alloc] init];
    [vc setValue:@YES forKey:@"isReceiveMode"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSUInteger)getSelectedGroupCount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.grabMode == JJGrabModeExclude) return manager.excludeGroups.count;
    if (manager.grabMode == JJGrabModeOnly) return manager.onlyGroups.count;
    if (manager.grabMode == JJGrabModeDelay) return manager.delayGroups.count;
    return 0;
}

@end
