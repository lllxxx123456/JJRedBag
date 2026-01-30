#import "JJRedBagContactSelectController.h"
#import "JJRedBagManager.h"
#import "WeChatHeaders.h"
#import <objc/runtime.h>

@interface JJRedBagContactSelectController () <ContactSelectViewDelegate>
@property (nonatomic, strong) ContactSelectView *selectView;
@property (nonatomic, strong) MMUIViewController *helper;
@end

@implementation JJRedBagContactSelectController

- (instancetype)init {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _helper = [[objc_getClass("MMUIViewController") alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
    
    self.title = @"选择通知对象";
    [self initSelectView];
}

- (void)initSelectView {
    self.selectView = [[objc_getClass("ContactSelectView") alloc] initWithFrame:self.view.bounds delegate:self];
    
    // 0: All, 1: Private, 2: Group? 
    // Usually 0 or something that allows both.
    // m_uiGroupScene seems to control filters.
    // Try to allow searching friends and groups.
    self.selectView.m_uiGroupScene = 0; 
    self.selectView.m_bMultiSelect = NO; // Single select
    [self.selectView initData:0];
    
    self.selectView.m_bShowHistoryGroup = YES;
    self.selectView.m_bShowRadarCreateRoom = NO;
    self.selectView.m_bShowContactTag = NO;
    self.selectView.m_bShowSelectFromGroup = NO;
    
    [self.selectView initView];
    [self.view addSubview:self.selectView];
}

#pragma mark - ContactSelectViewDelegate

- (void)onSelectContact:(CContact *)contact {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    manager.notificationChatId = contact.m_nsUsrName;
    manager.notificationChatName = [contact getContactDisplayName];
    [manager saveSettings];
    
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Forwarding

- (UIViewController *)getViewController {
    return self;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.helper respondsToSelector:aSelector]) {
        return self.helper;
    }
    return [super forwardingTargetForSelector:aSelector];
}

@end
