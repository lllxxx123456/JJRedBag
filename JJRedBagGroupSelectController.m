#import "JJRedBagGroupSelectController.h"
#import "WeChatHeaders.h"

@interface JJRedBagGroupSelectController ()
@property (nonatomic, assign) JJGrabMode mode;
@property (nonatomic, strong) NSMutableArray *allGroups;
@property (nonatomic, strong) NSMutableArray *selectedGroups;
@end

@implementation JJRedBagGroupSelectController

- (instancetype)initWithMode:(JJGrabMode)mode {
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
        _mode = mode;
        _allGroups = [NSMutableArray array];
        _selectedGroups = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    switch (self.mode) {
        case JJGrabModeExclude:
            self.title = @"选择不抢群";
            self.selectedGroups = [[JJRedBagManager sharedManager].excludeGroups mutableCopy];
            break;
        case JJGrabModeOnly:
            self.title = @"选择只抢群";
            self.selectedGroups = [[JJRedBagManager sharedManager].onlyGroups mutableCopy];
            break;
        case JJGrabModeDelay:
            self.title = @"选择延迟抢群";
            self.selectedGroups = [[JJRedBagManager sharedManager].delayGroups mutableCopy];
            break;
        default:
            break;
    }
    
    if (!self.selectedGroups) {
        self.selectedGroups = [NSMutableArray array];
    }
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" 
                                                                              style:UIBarButtonItemStyleDone 
                                                                             target:self 
                                                                             action:@selector(saveSelection)];
    
    [self loadGroups];
}

- (void)loadGroups {
    // 获取微信群聊列表
    @try {
        CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
        if (contactMgr) {
            NSArray *groups = [contactMgr getContactsWithGroupScene:2];
            if (!groups) {
                groups = [contactMgr getAllGroups];
            }
            if (!groups) {
                // 尝试其他方法获取群聊
                groups = [contactMgr getGroupContacts];
            }
            
            for (CContact *contact in groups) {
                if ([contact isKindOfClass:objc_getClass("CContact")]) {
                    NSString *userName = nil;
                    NSString *nickName = nil;
                    
                    if ([contact respondsToSelector:@selector(m_nsUsrName)]) {
                        userName = [contact m_nsUsrName];
                    }
                    if ([contact respondsToSelector:@selector(m_nsNickName)]) {
                        nickName = [contact m_nsNickName];
                    }
                    
                    if (userName && [userName hasSuffix:@"@chatroom"]) {
                        [self.allGroups addObject:@{
                            @"userName": userName ?: @"",
                            @"nickName": nickName ?: @"未命名群聊"
                        }];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // 静默处理
    }
    
    // 如果没有获取到群聊，添加提示
    if (self.allGroups.count == 0) {
        [self.allGroups addObject:@{
            @"userName": @"",
            @"nickName": @"暂未获取到群聊，请使用FLEX抓取"
        }];
    }
    
    [self.tableView reloadData];
}

- (void)saveSelection {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    switch (self.mode) {
        case JJGrabModeExclude:
            manager.excludeGroups = self.selectedGroups;
            break;
        case JJGrabModeOnly:
            manager.onlyGroups = self.selectedGroups;
            break;
        case JJGrabModeDelay:
            manager.delayGroups = self.selectedGroups;
            break;
        default:
            break;
    }
    
    [manager saveSettings];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.allGroups.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"选择群聊（点击选中/取消）";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"已选择 %lu 个群聊", (unsigned long)self.selectedGroups.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GroupCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }
    
    NSDictionary *group = self.allGroups[indexPath.row];
    NSString *userName = group[@"userName"];
    NSString *nickName = group[@"nickName"];
    
    cell.textLabel.text = nickName;
    cell.detailTextLabel.text = userName;
    cell.detailTextLabel.textColor = [UIColor grayColor];
    
    if ([self.selectedGroups containsObject:userName]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *group = self.allGroups[indexPath.row];
    NSString *userName = group[@"userName"];
    
    if (userName.length == 0) return;
    
    if ([self.selectedGroups containsObject:userName]) {
        [self.selectedGroups removeObject:userName];
    } else {
        [self.selectedGroups addObject:userName];
    }
    
    [tableView reloadData];
}

@end
