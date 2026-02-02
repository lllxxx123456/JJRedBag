#import <UIKit/UIKit.h>
#import "JJRedBagManager.h"

@interface JJRedBagGroupSelectController : UIViewController

@property (nonatomic, assign) BOOL isReceiveMode; // 是否为收款模式

- (instancetype)initWithMode:(JJGrabMode)mode;

@end
