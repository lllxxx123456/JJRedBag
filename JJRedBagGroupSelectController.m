#import "JJRedBagGroupSelectController.h"
#import "WeChatHeaders.h"
#import <objc/runtime.h>

@interface JJRedBagGroupSelectController () <ContactSelectViewDelegate>
@property (nonatomic, assign) JJGrabMode mode;
@property (nonatomic, strong) ContactSelectView *selectView;
@property (nonatomic, strong) MMUIViewController *helper;
@end

@implementation JJRedBagGroupSelectController

- (instancetype)initWithMode:(JJGrabMode)mode {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _mode = mode;
        // 初始化一个 MMUIViewController 实例用于消息转发，因为 ContactSelectView 可能依赖它的一些方法
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
    
    [self setupTitle];
    [self initSelectView];
    [self updateRightBarButtonWithCount:[self getInitialCount]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)setupTitle {
    if (self.isReceiveMode) {
        self.title = @"选择收款群";
        return;
    }
    switch (self.mode) {
        case JJGrabModeExclude: self.title = @"选择不抢群"; break;
        case JJGrabModeOnly: self.title = @"选择只抢群"; break;
        case JJGrabModeDelay: self.title = @"选择延迟抢群"; break;
        default: self.title = @"选择群聊"; break;
    }
}

- (void)initSelectView {
    // 使用 ContactSelectView
    self.selectView = [[objc_getClass("ContactSelectView") alloc] initWithFrame:self.view.bounds delegate:self];
    
    // 设置模式为群聊选择
    self.selectView.m_uiGroupScene = 5; 
    self.selectView.m_bMultiSelect = YES;
    [self.selectView initData:5];
    
    // 隐藏不需要的选项
    self.selectView.m_bShowHistoryGroup = NO;
    self.selectView.m_bShowRadarCreateRoom = NO;
    self.selectView.m_bShowContactTag = NO;
    self.selectView.m_bShowSelectFromGroup = NO;
    
    [self.selectView initView];
    [self.view addSubview:self.selectView];
    
    // 恢复已选中的联系人
    [self loadExistingSelection];
}

- (void)loadExistingSelection {
    NSArray *currentList = [self getCurrentList];
    if (currentList.count == 0) return;
    
    CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
    if (!contactMgr) return;
    
    for (NSString *userName in currentList) {
        CContact *contact = [contactMgr getContactByName:userName];
        if (contact) {
            [self.selectView addSelect:contact];
        }
    }
}

- (NSArray *)getCurrentList {
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (self.isReceiveMode) {
        return manager.receiveGroups;
    }
    switch (self.mode) {
        case JJGrabModeExclude: return manager.excludeGroups;
        case JJGrabModeOnly: return manager.onlyGroups;
        case JJGrabModeDelay: return manager.delayGroups;
        default: return @[];
    }
}

- (NSUInteger)getInitialCount {
    return [[self getCurrentList] count];
}

- (void)updateRightBarButtonWithCount:(NSUInteger)count {
    NSString *title = count > 0 ? [NSString stringWithFormat:@"确定(%lu)", (unsigned long)count] : @"确定";
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleDone target:self action:@selector(onDone)];
    btn.tintColor = [UIColor systemGreenColor];
    self.navigationItem.rightBarButtonItem = btn;
}

- (void)onDone {
    // 获取选中的用户名列表
    NSArray *selectedUserNames = [self.selectView.m_dicMultiSelect allKeys];
    
    JJRedBagManager *manager = [JJRedBagManager sharedManager];
    if (self.isReceiveMode) {
        manager.receiveGroups = [selectedUserNames mutableCopy];
    } else {
        switch (self.mode) {
            case JJGrabModeExclude: manager.excludeGroups = [selectedUserNames mutableCopy]; break;
            case JJGrabModeOnly: manager.onlyGroups = [selectedUserNames mutableCopy]; break;
            case JJGrabModeDelay: manager.delayGroups = [selectedUserNames mutableCopy]; break;
            default: break;
        }
    }
    
    [manager saveSettings];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - ContactSelectViewDelegate

- (void)onSelectContact:(CContact *)contact {
    // 当选择发生变化时，更新右上角的计数
    [self updateRightBarButtonWithCount:[self.selectView.m_dicMultiSelect count]];
}

- (void)onMultiSelectGroupCancel {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Forwarding

- (UIViewController *)getViewController {
    return self;
}

// 消息转发给 MMUIViewController，处理一些 ContactSelectView 可能调用的内部方法
- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.helper respondsToSelector:aSelector]) {
        return self.helper;
    }
    return [super forwardingTargetForSelector:aSelector];
}

@end
