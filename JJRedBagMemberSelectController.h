#import <UIKit/UIKit.h>

@interface JJRedBagMemberSelectController : UIViewController

@property (nonatomic, copy) NSString *groupId; // 群ID

- (instancetype)initWithGroupId:(NSString *)groupId;

@end
