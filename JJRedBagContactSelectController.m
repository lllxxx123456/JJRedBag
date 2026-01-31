#import "JJRedBagContactSelectController.h"
#import "JJRedBagManager.h"
#import "WeChatHeaders.h"

@interface JJRedBagContactSelectController () <SessionSelectControllerDelegate>
@property (nonatomic, assign) BOOL hasPresented;
@property (nonatomic, assign) BOOL didSelect;
@end

@implementation JJRedBagContactSelectController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.hasPresented = NO;
    self.didSelect = NO;
    
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (!self.hasPresented) {
        self.hasPresented = YES;
        [self showSessionSelect];
    } else {
        // 如果已经present过，且没有选择（即取消了），则返回上一级
        if (!self.didSelect) {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

- (void)showSessionSelect {
    SessionSelectController *selectVC = [[objc_getClass("SessionSelectController") alloc] init];
    selectVC.m_delegate = self;
    selectVC.m_bMultiSelect = NO;
    
    // 使用UINavigationController包装，以便有导航栏
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:selectVC];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - SessionSelectControllerDelegate

- (void)OnSelectSession:(CContact *)contact SessionSelectController:(id)controller {
    if (!contact) return;
    
    self.didSelect = YES;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.notificationChatId = contact.m_nsUsrName;
    manager.notificationChatName = [contact getContactDisplayName];
    [manager saveSettings];
    
    // 关闭选择器
    [controller dismissViewControllerAnimated:YES completion:^{
        // 关闭当前页面返回设置页
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

@end
