#import "JJRedBagMemberSelectController.h"
#import "JJRedBagManager.h"
#import "WeChatHeaders.h"
#import <objc/runtime.h>

@interface JJRedBagMemberSelectController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *allMembers;
@property (nonatomic, strong) NSArray *filteredMembers;
@property (nonatomic, strong) NSMutableSet *selectedMembers;
@end

@implementation JJRedBagMemberSelectController

- (instancetype)initWithGroupId:(NSString *)groupId {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _groupId = groupId;
        _selectedMembers = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"选择群成员";
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
    
    [self setupNavigationBar];
    [self setupSearchBar];
    [self setupTableView];
    [self loadMembers];
    [self loadExistingSelection];
}

- (void)setupNavigationBar {
    UIBarButtonItem *doneBtn = [[UIBarButtonItem alloc] initWithTitle:@"确定" style:UIBarButtonItemStyleDone target:self action:@selector(onDone)];
    doneBtn.tintColor = [UIColor systemGreenColor];
    self.navigationItem.rightBarButtonItem = doneBtn;
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    self.searchBar.placeholder = @"搜索群成员";
    self.searchBar.delegate = self;
    if (@available(iOS 13.0, *)) {
        self.searchBar.searchTextField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    }
}

- (void)setupTableView {
    CGFloat topOffset = 50;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, topOffset, self.view.bounds.size.width, self.view.bounds.size.height - topOffset) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (void)loadMembers {
    if (!self.groupId) {
        self.allMembers = @[];
        self.filteredMembers = @[];
        return;
    }
    
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    CContact *groupContact = [contactMgr getContactByName:self.groupId];
    
    if (groupContact && [groupContact respondsToSelector:@selector(m_nsChatRoomMemList)]) {
        NSString *memberList = [groupContact valueForKey:@"m_nsChatRoomMemList"];
        if (memberList) {
            NSArray *memberIds = [memberList componentsSeparatedByString:@";"];
            NSMutableArray *members = [NSMutableArray array];
            for (NSString *memberId in memberIds) {
                if (memberId.length > 0) {
                    CContact *member = [contactMgr getContactByName:memberId];
                    if (member) {
                        [members addObject:member];
                    }
                }
            }
            self.allMembers = members;
            self.filteredMembers = members;
        }
    } else {
        self.allMembers = @[];
        self.filteredMembers = @[];
    }
}

- (void)loadExistingSelection {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSArray *existingMembers = manager.groupReceiveMembers[self.groupId];
    if (existingMembers) {
        [self.selectedMembers addObjectsFromArray:existingMembers];
    }
    [self updateTitle];
}

- (void)updateTitle {
    if (self.selectedMembers.count > 0) {
        self.navigationItem.rightBarButtonItem.title = [NSString stringWithFormat:@"确定(%lu)", (unsigned long)self.selectedMembers.count];
    } else {
        self.navigationItem.rightBarButtonItem.title = @"确定";
    }
}

- (void)onDone {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (self.selectedMembers.count > 0) {
        manager.groupReceiveMembers[self.groupId] = [self.selectedMembers allObjects];
    } else {
        [manager.groupReceiveMembers removeObjectForKey:self.groupId];
    }
    [manager saveSettings];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredMembers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"MemberCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }
    
    CContact *member = self.filteredMembers[indexPath.row];
    cell.textLabel.text = [member getContactDisplayName];
    cell.detailTextLabel.text = member.m_nsUsrName;
    
    BOOL isSelected = [self.selectedMembers containsObject:member.m_nsUsrName];
    cell.accessoryType = isSelected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    CContact *member = self.filteredMembers[indexPath.row];
    NSString *memberId = member.m_nsUsrName;
    
    if ([self.selectedMembers containsObject:memberId]) {
        [self.selectedMembers removeObject:memberId];
    } else {
        [self.selectedMembers addObject:memberId];
    }
    
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateTitle];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredMembers = self.allMembers;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(CContact *contact, NSDictionary *bindings) {
            NSString *name = [contact getContactDisplayName];
            return [name.lowercaseString containsString:searchText.lowercaseString];
        }];
        self.filteredMembers = [self.allMembers filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
