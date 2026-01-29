#import <Foundation/Foundation.h>

// 红包参数类
@interface JJRedBagParam : NSObject

@property (strong, nonatomic) NSString *msgType;
@property (strong, nonatomic) NSString *sendId;
@property (strong, nonatomic) NSString *channelId;
@property (strong, nonatomic) NSString *nickName;
@property (strong, nonatomic) NSString *headImg;
@property (strong, nonatomic) NSString *nativeUrl;
@property (strong, nonatomic) NSString *sessionUserName;
@property (strong, nonatomic) NSString *sign;
@property (strong, nonatomic) NSString *timingIdentifier;
@property (assign, nonatomic) BOOL isGroupSender;

- (NSDictionary *)toParams;

@end

// 红包参数队列
@interface JJRedBagParamQueue : NSObject

+ (instancetype)sharedQueue;
- (void)enqueue:(JJRedBagParam *)param;
- (JJRedBagParam *)dequeue;
- (JJRedBagParam *)peek;
- (BOOL)isEmpty;

@end

// 抢红包操作
@interface JJReceiveRedBagOperation : NSOperation

- (instancetype)initWithRedBagParam:(JJRedBagParam *)param delay:(unsigned int)delayMs;

@end

// 红包任务管理器
@interface JJRedBagTaskManager : NSObject

+ (instancetype)sharedManager;
- (void)addNormalTask:(JJReceiveRedBagOperation *)task;
- (void)addSerialTask:(JJReceiveRedBagOperation *)task;
- (BOOL)serialQueueIsEmpty;

@end
