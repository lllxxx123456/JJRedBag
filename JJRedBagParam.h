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
@property (nonatomic, copy) NSString *timingIdentifier;
@property (assign, nonatomic) BOOL isGroupSender;

// 新增属性用于自动回复和通知
@property (nonatomic, copy) NSString *fromUser;       // 发送者(可能是群ID)
@property (nonatomic, copy) NSString *realChatUser;   // 群聊实际发送者ID
@property (nonatomic, assign) BOOL isGroup;           // 是否为群聊
@property (nonatomic, copy) NSString *content;        // 红包标题/内容

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
