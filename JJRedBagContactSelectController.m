#import "JJRedBagContactSelectController.h"
#import "JJRedBagManager.h"
#import "WeChatHeaders.h"

@interface JJRedBagContactSelectController () <SessionSelectControllerDelegate>
@property (nonatomic, assign) BOOL hasPresented;
@property (nonatomic, assign) BOOL didSelect;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@end

@implementation JJRedBagContactSelectController

@synthesize isReceiveMode = _isReceiveMode;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.hasPresented = NO;
    self.didSelect = NO;
    self.title = @"选择通知接收人";
    
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
    
    // 添加loading指示器，避免白屏
    if (@available(iOS 13.0, *)) {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    }
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.loadingIndicator];
    [self.loadingIndicator startAnimating];
    
    // 添加提示标签
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"正在加载联系人...";
    hintLabel.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        hintLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        hintLabel.textColor = [UIColor grayColor];
    }
    hintLabel.font = [UIFont systemFontOfSize:14];
    hintLabel.frame = CGRectMake(0, self.loadingIndicator.frame.origin.y + 50, self.view.bounds.size.width, 30);
    hintLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    hintLabel.tag = 1001;
    [self.view addSubview:hintLabel];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (!self.hasPresented) {
        self.hasPresented = YES;
        // 延迟一点点呈现，让loading先显示
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showSessionSelect];
        });
    } else {
        // 如果已经present过，且没有选择（即取消了），则返回上一级
        if (!self.didSelect) {
            [self.navigationController popViewControllerAnimated:NO];
        }
    }
}

- (void)showSessionSelect {
    @try {
        SessionSelectController *selectVC = [[objc_getClass("SessionSelectController") alloc] init];
        selectVC.m_delegate = self;
        selectVC.m_bMultiSelect = NO;
        
        // 直接push到当前导航栈，避免modal产生的白屏
        if (self.navigationController) {
            [self.loadingIndicator stopAnimating];
            UIView *hintLabel = [self.view viewWithTag:1001];
            hintLabel.hidden = YES;
            [self.navigationController pushViewController:selectVC animated:YES];
        } else {
            // 备用方案：使用modal
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:selectVC];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:^{
                [self.loadingIndicator stopAnimating];
                UIView *hintLabel = [self.view viewWithTag:1001];
                hintLabel.hidden = YES;
            }];
        }
    } @catch (NSException *exception) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - SessionSelectControllerDelegate

- (void)OnSelectSession:(CContact *)contact SessionSelectController:(id)controller {
    if (!contact) return;
    
    self.didSelect = YES;
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    
    if (self.isReceiveMode) {
        // 收款通知接收人
        manager.receiveNotificationChatId = contact.m_nsUsrName;
        manager.receiveNotificationChatName = [contact getContactDisplayName];
    } else {
        // 红包通知接收人
        manager.notificationChatId = contact.m_nsUsrName;
        manager.notificationChatName = [contact getContactDisplayName];
    }
    [manager saveSettings];
    
    // 返回设置页面，弹出两级（SessionSelectController 和 ContactSelectController）
    if (self.navigationController) {
        NSArray *viewControllers = self.navigationController.viewControllers;
        if (viewControllers.count >= 3) {
            UIViewController *targetVC = viewControllers[viewControllers.count - 3];
            [self.navigationController popToViewController:targetVC animated:YES];
        } else {
            [self.navigationController popToRootViewControllerAnimated:YES];
        }
    } else {
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
