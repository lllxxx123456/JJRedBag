#import "JJRedBagSettingsController.h"
#import "JJRedBagManager.h"
#import "JJRedBagGroupSelectController.h"

#define JJ_THEME_COLOR [UIColor colorWithRed:255/255.0 green:76/255.0 blue:76/255.0 alpha:1.0]
#define JJ_THEME_GRADIENT_START [UIColor colorWithRed:255/255.0 green:100/255.0 blue:100/255.0 alpha:1.0]
#define JJ_THEME_GRADIENT_END [UIColor colorWithRed:255/255.0 green:60/255.0 blue:80/255.0 alpha:1.0]
#define JJ_BG_COLOR [UIColor colorWithRed:248/255.0 green:248/255.0 blue:250/255.0 alpha:1.0]
#define JJ_CARD_COLOR [UIColor whiteColor]
#define JJ_TEXT_PRIMARY [UIColor colorWithRed:30/255.0 green:30/255.0 blue:40/255.0 alpha:1.0]
#define JJ_TEXT_SECONDARY [UIColor colorWithRed:130/255.0 green:130/255.0 blue:140/255.0 alpha:1.0]

@interface JJRedBagSettingsController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UISwitch *mainSwitch;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation JJRedBagSettingsController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"JJ抢红包";
    self.view.backgroundColor = JJ_BG_COLOR;
    self.tableView.backgroundColor = JJ_BG_COLOR;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    [self setupNavigationBar];
    [self setupHeaderView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateStatusLabel];
    [self.tableView reloadData];
}

- (void)setupNavigationBar {
    // 关闭按钮 - iOS 13+使用SF Symbols，低版本使用文字
    if (@available(iOS 13.0, *)) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(dismissSelf)];
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(dismissSelf)];
    }
    self.navigationItem.rightBarButtonItem.tintColor = JJ_TEXT_SECONDARY;
    
    // 导航栏外观 - iOS 13+
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = JJ_BG_COLOR;
        appearance.shadowColor = [UIColor clearColor];
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: JJ_TEXT_PRIMARY, NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]};
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    } else {
        self.navigationController.navigationBar.barTintColor = JJ_BG_COLOR;
        self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: JJ_TEXT_PRIMARY, NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]};
        self.navigationController.navigationBar.shadowImage = [[UIImage alloc] init];
    }
}

- (void)setupHeaderView {
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 200)];
    self.headerView.backgroundColor = [UIColor clearColor];
    
    // 渐变背景卡片
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(16, 16, self.view.bounds.size.width - 32, 168)];
    cardView.backgroundColor = JJ_CARD_COLOR;
    cardView.layer.cornerRadius = 20;
    cardView.layer.shadowColor = [UIColor colorWithRed:255/255.0 green:76/255.0 blue:76/255.0 alpha:0.3].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 8);
    cardView.layer.shadowRadius = 20;
    cardView.layer.shadowOpacity = 1.0;
    [self.headerView addSubview:cardView];
    
    // 渐变图层
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = cardView.bounds;
    gradient.colors = @[(id)JJ_THEME_GRADIENT_START.CGColor, (id)JJ_THEME_GRADIENT_END.CGColor];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 1);
    gradient.cornerRadius = 20;
    [cardView.layer insertSublayer:gradient atIndex:0];
    
    // 红包图标
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 24, 50, 50)];
    iconLabel.text = @"🧧";
    iconLabel.font = [UIFont systemFontOfSize:40];
    [cardView addSubview:iconLabel];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(84, 28, 200, 28)];
    titleLabel.text = @"JJ抢红包";
    titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    [cardView addSubview:titleLabel];
    
    // 版本
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(84, 56, 200, 20)];
    versionLabel.text = @"v1.0.0";
    versionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    versionLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    [cardView addSubview:versionLabel];
    
    // 状态标签
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 95, cardView.bounds.size.width - 100, 24)];
    self.statusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    [cardView addSubview:self.statusLabel];
    [self updateStatusLabel];
    
    // 主开关
    self.mainSwitch = [[UISwitch alloc] init];
    self.mainSwitch.frame = CGRectMake(cardView.bounds.size.width - 75, 95, 51, 31);
    self.mainSwitch.onTintColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    self.mainSwitch.thumbTintColor = [UIColor whiteColor];
    self.mainSwitch.on = [JJRedBagManager sharedManager].enabled;
    [self.mainSwitch addTarget:self action:@selector(mainSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [cardView addSubview:self.mainSwitch];
    
    // 提示文字
    UILabel *tipLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 130, cardView.bounds.size.width - 48, 30)];
    tipLabel.text = @"仅供娱乐 · 请勿依赖 · 风险自担";
    tipLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    tipLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    tipLabel.textAlignment = NSTextAlignmentCenter;
    [cardView addSubview:tipLabel];
    
    self.tableView.tableHeaderView = self.headerView;
}

- (void)updateStatusLabel {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.enabled) {
        self.statusLabel.text = @"✓ 抢红包功能已开启";
    } else {
        self.statusLabel.text = @"○ 抢红包功能已关闭";
    }
    self.mainSwitch.on = manager.enabled;
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
    switch (section) {
        case 0: // 抢红包模式
            if (manager.grabMode == JJGrabModeDelay) return 4;
            return 2;
        case 1: // 过滤设置
            return 2;
        case 2: // 其他设置
            return 3;
        default: return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 56;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 50;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 10;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 50)];
    headerView.backgroundColor = [UIColor clearColor];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(32, 20, 200, 24)];
    titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    titleLabel.textColor = JJ_TEXT_SECONDARY;
    
    NSArray *titles = @[@"抢红包模式", @"过滤设置", @"其他设置"];
    NSArray *icons = @[@"🎯", @"🔍", @"⚙️"];
    titleLabel.text = [NSString stringWithFormat:@"%@  %@", icons[section], titles[section]];
    
    [headerView addSubview:titleLabel];
    return headerView;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [[UIView alloc] init];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    // 创建卡片容器
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(16, 2, tableView.bounds.size.width - 32, 52)];
    cardView.backgroundColor = JJ_CARD_COLOR;
    cardView.tag = 100;
    
    // 根据位置设置圆角
    NSInteger rowCount = [self tableView:tableView numberOfRowsInSection:indexPath.section];
    if (rowCount == 1) {
        cardView.layer.cornerRadius = 16;
    } else if (indexPath.row == 0) {
        cardView.layer.cornerRadius = 16;
        cardView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (indexPath.row == rowCount - 1) {
        cardView.layer.cornerRadius = 16;
        cardView.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    
    // 添加阴影
    if (indexPath.row == 0) {
        cardView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.06].CGColor;
        cardView.layer.shadowOffset = CGSizeMake(0, 4);
        cardView.layer.shadowRadius = 12;
        cardView.layer.shadowOpacity = 1.0;
    }
    
    [cell.contentView addSubview:cardView];
    
    // 标题标签
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, cardView.bounds.size.width - 120, 52)];
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    titleLabel.textColor = JJ_TEXT_PRIMARY;
    [cardView addSubview:titleLabel];
    
    // 详情标签
    UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 150, 0, 80, 52)];
    detailLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    detailLabel.textColor = JJ_TEXT_SECONDARY;
    detailLabel.textAlignment = NSTextAlignmentRight;
    [cardView addSubview:detailLabel];
    
    // 箭头图标
    UIImageView *arrowView = [[UIImageView alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 36, 18, 16, 16)];
    if (@available(iOS 13.0, *)) {
        arrowView.image = [UIImage systemImageNamed:@"chevron.right"];
    } else {
        arrowView.image = nil;
    }
    arrowView.tintColor = JJ_TEXT_SECONDARY;
    arrowView.contentMode = UIViewContentModeScaleAspectFit;
    
    // 开关
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 65, 11, 51, 31)];
    sw.onTintColor = JJ_THEME_COLOR;
    
    // 分隔线
    if (indexPath.row < rowCount - 1) {
        UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(20, 51, cardView.bounds.size.width - 40, 0.5)];
        separator.backgroundColor = [UIColor colorWithWhite:0 alpha:0.05];
        [cardView addSubview:separator];
    }
    
    // 配置内容
    switch (indexPath.section) {
        case 0: // 抢红包模式
            switch (indexPath.row) {
                case 0:
                    titleLabel.text = @"抢红包模式";
                    if (manager.grabMode == JJGrabModeExclude) detailLabel.text = @"不抢群";
                    else if (manager.grabMode == JJGrabModeOnly) detailLabel.text = @"只抢群";
                    else detailLabel.text = @"延迟抢";
                    [cardView addSubview:arrowView];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
                case 1:
                    titleLabel.text = @"选择群聊";
                    detailLabel.text = [NSString stringWithFormat:@"%lu个", (unsigned long)[self getSelectedGroupCount]];
                    [cardView addSubview:arrowView];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
                case 2:
                    titleLabel.text = @"其余群处理";
                    detailLabel.text = manager.delayOtherMode == JJDelayOtherModeNoDelay ? @"无延迟抢" : @"不抢";
                    [cardView addSubview:arrowView];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
                case 3:
                    titleLabel.text = @"延迟时间";
                    detailLabel.text = [NSString stringWithFormat:@"%.1f秒", manager.delayTime];
                    [cardView addSubview:arrowView];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
            }
            break;
            
        case 1: // 过滤设置
            switch (indexPath.row) {
                case 0:
                    titleLabel.text = @"关键词过滤";
                    sw.on = manager.filterKeywordEnabled;
                    sw.tag = 100;
                    [sw addTarget:self action:@selector(filterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                    [cardView addSubview:sw];
                    break;
                case 1:
                    titleLabel.text = @"编辑关键词";
                    detailLabel.text = manager.filterKeywords.count > 0 ? [NSString stringWithFormat:@"%lu个", (unsigned long)manager.filterKeywords.count] : @"未设置";
                    [cardView addSubview:arrowView];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
            }
            break;
            
        case 2: // 其他设置
            switch (indexPath.row) {
                case 0:
                    titleLabel.text = @"抢自己的红包";
                    sw.on = manager.grabSelfEnabled;
                    sw.tag = 200;
                    [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                    [cardView addSubview:sw];
                    break;
                case 1:
                    titleLabel.text = @"抢私聊红包";
                    sw.on = manager.grabPrivateEnabled;
                    sw.tag = 201;
                    [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                    [cardView addSubview:sw];
                    break;
                case 2:
                    titleLabel.text = @"后台/锁屏抢";
                    sw.on = manager.backgroundGrabEnabled;
                    sw.tag = 202;
                    [sw addTarget:self action:@selector(otherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                    [cardView addSubview:sw];
                    break;
            }
            break;
    }
    
    return cell;
}

- (NSUInteger)getSelectedGroupCount {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (manager.grabMode == JJGrabModeExclude) return manager.excludeGroups.count;
    if (manager.grabMode == JJGrabModeOnly) return manager.onlyGroups.count;
    if (manager.grabMode == JJGrabModeDelay) return manager.delayGroups.count;
    return 0;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    switch (indexPath.section) {
        case 0:
            switch (indexPath.row) {
                case 0: [self showModeSelector]; break;
                case 1: [self showGroupSelectForMode:manager.grabMode]; break;
                case 2: [self showDelayOtherModeSelector]; break;
                case 3: [self showDelayTimeInput]; break;
            }
            break;
        case 1:
            if (indexPath.row == 1) [self showKeywordEditor];
            break;
    }
}

#pragma mark - Actions

- (void)mainSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    if (sender.on && !manager.hasShownDisclaimer) {
        sender.on = NO;
        [manager showDisclaimerAlertWithCompletion:^(BOOL accepted) {
            if (accepted) {
                sender.on = YES;
                [self updateStatusLabel];
            }
        }];
    } else {
        manager.enabled = sender.on;
        [manager saveSettings];
        [self updateStatusLabel];
    }
}

- (void)filterSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.filterKeywordEnabled = sender.on;
    [manager saveSettings];
}

- (void)otherSwitchChanged:(UISwitch *)sender {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    switch (sender.tag) {
        case 200: manager.grabSelfEnabled = sender.on; break;
        case 201: manager.grabPrivateEnabled = sender.on; break;
        case 202: manager.backgroundGrabEnabled = sender.on; break;
    }
    [manager saveSettings];
}

- (void)showModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择抢红包模式"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *excludeAction = [UIAlertAction actionWithTitle:@"🚫 不抢群模式" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        manager.grabMode = JJGrabModeExclude;
        [manager saveSettings];
        [self.tableView reloadData];
    }];
    
    UIAlertAction *onlyAction = [UIAlertAction actionWithTitle:@"✅ 只抢群模式" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        manager.grabMode = JJGrabModeOnly;
        [manager saveSettings];
        [self.tableView reloadData];
    }];
    
    UIAlertAction *delayAction = [UIAlertAction actionWithTitle:@"⏱️ 延迟抢模式" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        manager.grabMode = JJGrabModeDelay;
        [manager saveSettings];
        [self.tableView reloadData];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:excludeAction];
    [alert addAction:onlyAction];
    [alert addAction:delayAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showGroupSelectForMode:(JJGrabMode)mode {
    JJRedBagGroupSelectController *groupVC = [[JJRedBagGroupSelectController alloc] initWithMode:mode];
    [self.navigationController pushViewController:groupVC animated:YES];
}

- (void)showDelayOtherModeSelector {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"其余群处理方式"
                                                                   message:@"选择延迟抢群之外的群如何处理"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *noDelayAction = [UIAlertAction actionWithTitle:@"⚡ 其余无延迟抢" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        manager.delayOtherMode = JJDelayOtherModeNoDelay;
        [manager saveSettings];
        [self.tableView reloadData];
    }];
    
    UIAlertAction *noGrabAction = [UIAlertAction actionWithTitle:@"🚫 其余直接不抢" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        manager.delayOtherMode = JJDelayOtherModeNoGrab;
        [manager saveSettings];
        [self.tableView reloadData];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:noDelayAction];
    [alert addAction:noGrabAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDelayTimeInput {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置延迟时间"
                                                                   message:@"请输入延迟抢红包的时间（秒）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"延迟秒数";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.1f", manager.delayTime];
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *text = alert.textFields.firstObject.text;
        NSTimeInterval delay = [text doubleValue];
        if (delay > 0) {
            manager.delayTime = delay;
            [manager saveSettings];
            [self.tableView reloadData];
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:confirmAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showKeywordEditor {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSString *currentKeywords = [manager.filterKeywords componentsJoinedByString:@","];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"编辑过滤关键词"
                                                                   message:@"多个关键词用逗号分隔\n包含这些关键词的红包将不抢"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"例如: 专属,测试,内部";
        textField.text = currentKeywords;
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *text = alert.textFields.firstObject.text;
        NSArray *keywords = [text componentsSeparatedByString:@","];
        NSMutableArray *validKeywords = [NSMutableArray array];
        for (NSString *keyword in keywords) {
            NSString *trimmed = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [validKeywords addObject:trimmed];
            }
        }
        manager.filterKeywords = validKeywords;
        [manager saveSettings];
        [self.tableView reloadData];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:confirmAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
