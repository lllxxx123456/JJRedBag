#import "JJDebugConsole.h"
#import "JJRedBagManager.h"
#import <objc/runtime.h>

static const NSInteger kJJConsoleMaxLogs = 600;           // 日志最大条数
static const CGFloat kJJConsoleExpandedWidthRatio = 0.92; // 展开宽度比例
static const CGFloat kJJConsoleExpandedHeightRatio = 0.45;// 展开高度比例
static const CGFloat kJJConsoleMinBallSize = 52.0;        // 最小化按钮直径

#pragma mark - 穿透窗口 / 容器视图

// 自定义 UIWindow：空白区域（非子控件）点击穿透到下层（微信主窗口）
@interface JJConsoleWindow : UIWindow
@end

@implementation JJConsoleWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // 如果命中了自身（window 或 rootVC.view 的空白区域），穿透
    if (hit == self) return nil;
    // rootViewController.view 作为容器，如果命中它本身（非子控件），也穿透
    if (self.rootViewController && hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// 容器视图：同样在空白区域穿透
@interface JJConsoleContainerView : UIView
@end

@implementation JJConsoleContainerView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

#pragma mark - 控制器

@interface JJConsoleViewController : UIViewController
@property (nonatomic, strong) UIView *panel;         // 展开面板
@property (nonatomic, strong) UIView *titleBar;      // 标题栏（拖动区）
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextView *textView;  // 日志文本视图
@property (nonatomic, strong) UIView *buttonBar;     // 按钮栏
@property (nonatomic, strong) UIButton *ball;        // 最小化按钮
@property (nonatomic, assign) BOOL minimized;
@property (nonatomic, assign) CGPoint ballCenter;    // 最小化按钮上次位置
@property (nonatomic, assign) CGPoint panelOrigin;   // 面板上次位置
@end

@implementation JJConsoleViewController

- (void)loadView {
    JJConsoleContainerView *container = [[JJConsoleContainerView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    container.backgroundColor = [UIColor clearColor];
    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    [self setupPanel];
    [self setupBall];
    self.minimized = NO;
    self.ball.hidden = YES;
}

- (void)setupPanel {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat w = sw * kJJConsoleExpandedWidthRatio;
    CGFloat h = sh * kJJConsoleExpandedHeightRatio;
    CGFloat x = (sw - w) / 2.0;
    CGFloat y = sh * 0.12;

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
    self.panel.layer.cornerRadius = 10;
    self.panel.layer.masksToBounds = YES;
    self.panel.layer.borderWidth = 0.5;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    [self.view addSubview:self.panel];

    // 标题栏
    self.titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 32)];
    self.titleBar.backgroundColor = [UIColor colorWithRed:0.10 green:0.15 blue:0.22 alpha:1.0];
    [self.panel addSubview:self.titleBar];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, w - 20, 32)];
    self.titleLabel.text = @"JJ 调试器";
    self.titleLabel.textColor = [UIColor colorWithRed:0.9 green:0.9 blue:1.0 alpha:1.0];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.titleBar addSubview:self.titleLabel];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanelPan:)];
    [self.titleBar addGestureRecognizer:pan];

    // 按钮栏
    CGFloat barH = 36;
    self.buttonBar = [[UIView alloc] initWithFrame:CGRectMake(0, h - barH, w, barH)];
    self.buttonBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    [self.panel addSubview:self.buttonBar];

    NSArray *titles = @[@"复制", @"清除", @"最小化", @"关闭"];
    NSArray *selectors = @[ NSStringFromSelector(@selector(onCopy)),
                            NSStringFromSelector(@selector(onClear)),
                            NSStringFromSelector(@selector(onMinimize)),
                            NSStringFromSelector(@selector(onClose)) ];
    CGFloat btnW = w / titles.count;
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(btnW * i, 0, btnW, barH);
        [btn setTitle:titles[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:13];
        [btn addTarget:self action:NSSelectorFromString(selectors[i]) forControlEvents:UIControlEventTouchUpInside];
        if (i > 0) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(btnW * i, 6, 0.5, barH - 12)];
            sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3];
            [self.buttonBar addSubview:sep];
        }
        [self.buttonBar addSubview:btn];
    }

    // 日志文本视图
    CGFloat tvY = 32;
    CGFloat tvH = h - tvY - barH;
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(0, tvY, w, tvH)];
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.textContainerInset = UIEdgeInsetsMake(6, 8, 6, 8);
    self.textView.text = @"";
    [self.panel addSubview:self.textView];

    self.panelOrigin = self.panel.frame.origin;
}

- (void)setupBall {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    self.ball = [UIButton buttonWithType:UIButtonTypeCustom];
    self.ball.frame = CGRectMake(sw - kJJConsoleMinBallSize - 12, sh * 0.35, kJJConsoleMinBallSize, kJJConsoleMinBallSize);
    self.ball.backgroundColor = [UIColor colorWithRed:0.18 green:0.45 blue:0.85 alpha:0.88];
    self.ball.layer.cornerRadius = kJJConsoleMinBallSize / 2.0;
    self.ball.layer.borderWidth = 1.0;
    self.ball.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    [self.ball setTitle:@"JJ" forState:UIControlStateNormal];
    [self.ball setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.ball.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.ball addTarget:self action:@selector(onExpand) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onBallPan:)];
    [self.ball addGestureRecognizer:pan];

    [self.view addSubview:self.ball];
    self.ballCenter = self.ball.center;
}

#pragma mark - 手势

- (void)onPanelPan:(UIPanGestureRecognizer *)g {
    static CGPoint startOrigin;
    if (g.state == UIGestureRecognizerStateBegan) {
        startOrigin = self.panel.frame.origin;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:self.view];
        CGRect f = self.panel.frame;
        f.origin.x = startOrigin.x + t.x;
        f.origin.y = startOrigin.y + t.y;
        // 限制不出屏
        CGSize sz = self.view.bounds.size;
        f.origin.x = MAX(-f.size.width + 60, MIN(sz.width - 60, f.origin.x));
        f.origin.y = MAX(0, MIN(sz.height - 60, f.origin.y));
        self.panel.frame = f;
    } else if (g.state == UIGestureRecognizerStateEnded) {
        self.panelOrigin = self.panel.frame.origin;
    }
}

- (void)onBallPan:(UIPanGestureRecognizer *)g {
    static CGPoint startCenter;
    if (g.state == UIGestureRecognizerStateBegan) {
        startCenter = self.ball.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:self.view];
        CGPoint c = CGPointMake(startCenter.x + t.x, startCenter.y + t.y);
        CGSize sz = self.view.bounds.size;
        c.x = MAX(kJJConsoleMinBallSize/2.0, MIN(sz.width - kJJConsoleMinBallSize/2.0, c.x));
        c.y = MAX(kJJConsoleMinBallSize/2.0, MIN(sz.height - kJJConsoleMinBallSize/2.0, c.y));
        self.ball.center = c;
    } else if (g.state == UIGestureRecognizerStateEnded) {
        self.ballCenter = self.ball.center;
    }
}

#pragma mark - 按钮事件

- (void)onCopy {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
    [self flashTitle:@"已复制"];
}

- (void)onClear {
    self.textView.text = @"";
    [[JJDebugConsole shared] clear];
    [self flashTitle:@"已清空"];
}

- (void)onMinimize {
    self.panel.hidden = YES;
    self.ball.hidden = NO;
    self.minimized = YES;
}

- (void)onExpand {
    self.panel.hidden = NO;
    self.ball.hidden = YES;
    self.minimized = NO;
}

- (void)onClose {
    [[JJDebugConsole shared] hide];
}

- (void)flashTitle:(NSString *)msg {
    NSString *origin = @"JJ 调试器";
    self.titleLabel.text = [NSString stringWithFormat:@"%@  ·  %@", origin, msg];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.titleLabel.text = origin;
    });
}

@end

#pragma mark - JJDebugConsole

@interface JJDebugConsole ()
@property (nonatomic, strong) JJConsoleWindow *window;
@property (nonatomic, strong) JJConsoleViewController *vc;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *logs; // @[{@"tag":..., @"msg":..., @"ts":...}]
@property (nonatomic, assign) BOOL visible;
@end

@implementation JJDebugConsole

+ (instancetype)shared {
    static JJDebugConsole *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[JJDebugConsole alloc] init];
    });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _logs = [NSMutableArray array];
    }
    return self;
}

+ (BOOL)isEnabled {
    JJRedBagManager *m = [JJRedBagManager sharedManager];
    if (!m.enabled) return NO;
    // debugConsoleEnabled 通过 KVC 读取，兼容运行时属性扩展
    @try {
        NSNumber *v = [m valueForKey:@"debugConsoleEnabled"];
        return [v boolValue];
    } @catch (NSException *e) { return NO; }
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window) {
            self.window.hidden = NO;
            self.visible = YES;
            return;
        }
        [self buildWindow];
        self.visible = YES;
    });
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.window.hidden = YES;
        self.visible = NO;
    });
}

- (void)toggle {
    if (self.visible) { [self hide]; } else { [self show]; }
}

- (void)clear {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logs removeAllObjects];
        self.vc.textView.attributedText = [[NSAttributedString alloc] initWithString:@""];
    });
}

- (void)log:(NSString *)tag message:(NSString *)message {
    if (!message) return;
    NSString *safeTag = tag ?: @"信息";
    NSDate *now = [NSDate date];
    NSDictionary *entry = @{ @"tag": safeTag, @"msg": message, @"ts": now };
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logs addObject:entry];
        while (self.logs.count > kJJConsoleMaxLogs) {
            [self.logs removeObjectAtIndex:0];
        }
        if (self.window && !self.window.hidden) {
            [self appendEntry:entry];
        }
    });
}

- (void)logTag:(NSString *)tag format:(NSString *)format, ... {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:tag message:msg];
}

#pragma mark - 私有

- (void)buildWindow {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
            }
        }
        if (scene) {
            self.window = [[JJConsoleWindow alloc] initWithWindowScene:scene];
        }
    }
    if (!self.window) {
        self.window = [[JJConsoleWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    self.window.backgroundColor = [UIColor clearColor];
    self.window.windowLevel = UIWindowLevelAlert + 100;
    self.window.hidden = NO;

    self.vc = [[JJConsoleViewController alloc] init];
    self.window.rootViewController = self.vc; // 触发 loadView → 使用 JJConsoleContainerView

    // 把现有日志重绘一次
    [self redrawAllLogs];
}

- (UIColor *)colorForTag:(NSString *)tag {
    if ([tag isEqualToString:@"选图"]) return [UIColor colorWithRed:0.40 green:0.70 blue:1.00 alpha:1.0];
    if ([tag isEqualToString:@"上传"]) return [UIColor colorWithRed:0.40 green:0.90 blue:0.55 alpha:1.0];
    if ([tag isEqualToString:@"压缩"]) return [UIColor colorWithRed:1.00 green:0.75 blue:0.30 alpha:1.0];
    if ([tag isEqualToString:@"视频"]) return [UIColor colorWithRed:1.00 green:0.60 blue:0.90 alpha:1.0];
    if ([tag isEqualToString:@"网络"]) return [UIColor colorWithRed:0.80 green:0.60 blue:1.00 alpha:1.0];
    if ([tag isEqualToString:@"错误"]) return [UIColor colorWithRed:1.00 green:0.40 blue:0.40 alpha:1.0];
    if ([tag isEqualToString:@"发布"]) return [UIColor colorWithRed:1.00 green:0.90 blue:0.50 alpha:1.0];
    return [UIColor colorWithWhite:0.85 alpha:1.0];
}

- (NSAttributedString *)formattedEntry:(NSDictionary *)entry {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *ts = [df stringFromDate:entry[@"ts"]];
    NSString *tag = entry[@"tag"] ?: @"信息";
    NSString *msg = entry[@"msg"] ?: @"";

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    UIFont *font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];

    NSString *prefix = [NSString stringWithFormat:@"%@  ", ts];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:prefix attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.55 alpha:1.0],
        NSFontAttributeName: font
    }]];
    NSString *tagStr = [NSString stringWithFormat:@"[%@] ", tag];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:tagStr attributes:@{
        NSForegroundColorAttributeName: [self colorForTag:tag],
        NSFontAttributeName: font
    }]];
    NSString *msgStr = [NSString stringWithFormat:@"%@\n", msg];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:msgStr attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.92 alpha:1.0],
        NSFontAttributeName: font
    }]];
    return attr;
}

- (void)appendEntry:(NSDictionary *)entry {
    NSMutableAttributedString *existing = [[NSMutableAttributedString alloc] initWithAttributedString:(self.vc.textView.attributedText ?: [[NSAttributedString alloc] init])];
    [existing appendAttributedString:[self formattedEntry:entry]];
    self.vc.textView.attributedText = existing;
    // 滚到底部
    NSRange r = NSMakeRange(existing.length, 0);
    [self.vc.textView scrollRangeToVisible:r];
}

- (void)redrawAllLogs {
    NSMutableAttributedString *buf = [[NSMutableAttributedString alloc] init];
    for (NSDictionary *e in self.logs) {
        [buf appendAttributedString:[self formattedEntry:e]];
    }
    self.vc.textView.attributedText = buf;
    NSRange r = NSMakeRange(buf.length, 0);
    [self.vc.textView scrollRangeToVisible:r];
}

@end
