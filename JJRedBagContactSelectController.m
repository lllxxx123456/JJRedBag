#import "JJRedBagContactSelectController.h"
#import "JJRedBagManager.h"
#import "WeChatHeaders.h"

@interface JJRedBagContactSelectController () <SessionSelectControllerDelegate>
@end

@implementation JJRedBagContactSelectController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
    
    // 延迟执行以确保视图加载完成
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showSessionSelect];
    });
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
