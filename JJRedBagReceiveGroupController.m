#import "JJRedBagReceiveGroupController.h"
#import "JJRedBagManager.h"
#import "JJRedBagMemberSelectController.h"
#import "JJRedBagGroupSelectController.h"
#import "WeChatHeaders.h"
#import <objc/runtime.h>

@interface JJRedBagReceiveGroupController ()
@property (nonatomic, strong) NSArray *groups;
@end

@implementation JJRedBagReceiveGroupController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"收款群设置";
    
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addGroup)];
    self.navigationItem.rightBarButtonItem = addBtn;
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadGroups];
    [self.tableView reloadData];
}

- (void)loadGroups {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    self.groups = manager.receiveGroups ?: @[];
}

- (void)addGroup {
    JJRedBagGroupSelectController *vc = [[JJRedBagGroupSelectController alloc] initWithMode:JJGrabModeOnly];
    vc.isReceiveMode = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.groups.count == 0 ? 1 : self.groups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    
    if (self.groups.count == 0) {
        cell.textLabel.text = @"未设置收款群（接收全部群转账）";
        cell.textLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    NSString *groupId = self.groups[indexPath.row];
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    CContact *contact = [contactMgr getContactByName:groupId];
    
    cell.textLabel.text = contact ? [contact getContactDisplayName] : groupId;
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = [UIColor labelColor];
    } else {
        cell.textLabel.textColor = [UIColor blackColor];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    NSArray *members = manager.groupReceiveMembers[groupId];
    if (members && members.count > 0) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"已选%lu人", (unsigned long)members.count];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (self.groups.count == 0) return;
    
    NSString *groupId = self.groups[indexPath.row];
    JJRedBagMemberSelectController *vc = [[JJRedBagMemberSelectController alloc] initWithGroupId:groupId];
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.groups.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        JJRedBagManager *manager = [JJRedBagManager sharedManager];
        NSString *groupId = self.groups[indexPath.row];
        
        [manager.receiveGroups removeObject:groupId];
        [manager.groupReceiveMembers removeObjectForKey:groupId];
        [manager saveSettings];
        
        [self loadGroups];
        [self.tableView reloadData];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"点击群可设置指定收款群成员";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"不设置群时接收全部群转账\n设置群后只接收指定群的转账\n设置群成员后只接收该群指定成员的转账";
}

@end
