#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// JJ 悬浮调试器：可拖动、可最小化、可复制、可清除，
// 空白区域点击穿透到底层（不阻挡微信正常交互），日志分类着色
@interface JJDebugConsole : NSObject

+ (instancetype)shared;

@property (nonatomic, assign, readonly) BOOL visible;

// 打开/关闭悬浮窗
- (void)show;
- (void)hide;
- (void)toggle;

// 清空日志
- (void)clear;

// 日志追加（tag 建议用："选图"/"上传"/"压缩"/"视频"/"网络"/"错误"/"信息" 等短词，会按 tag 着色）
- (void)log:(NSString *)tag message:(NSString *)message;
- (void)logTag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

// 便捷方法：是否启用（开关 + 总开关）
+ (BOOL)isEnabled;

@end
