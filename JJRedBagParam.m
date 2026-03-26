#import "JJRedBagParam.h"
#import "WeChatHeaders.h"

#pragma mark - JJRedBagParam

@implementation JJRedBagParam

- (NSDictionary *)toParams {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (self.msgType) params[@"msgType"] = self.msgType;
    if (self.sendId) params[@"sendId"] = self.sendId;
    if (self.channelId) params[@"channelId"] = self.channelId;
    if (self.nickName) params[@"nickName"] = self.nickName;
    if (self.headImg) params[@"headImg"] = self.headImg;
    if (self.nativeUrl) params[@"nativeUrl"] = self.nativeUrl;
    if (self.sessionUserName) params[@"sessionUserName"] = self.sessionUserName;
    if (self.timingIdentifier) params[@"timingIdentifier"] = self.timingIdentifier;
    return params;
}

@end

#pragma mark - JJRedBagParamQueue

@interface JJRedBagParamQueue ()
@property (strong, nonatomic) NSMutableArray *queue;
@end

@implementation JJRedBagParamQueue

+ (instancetype)sharedQueue {
    static JJRedBagParamQueue *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[JJRedBagParamQueue alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _queue = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)enqueue:(JJRedBagParam *)param {
    @synchronized (self.queue) {
        [self.queue addObject:param];
    }
}

- (JJRedBagParam *)dequeue {
    @synchronized (self.queue) {
        if (self.queue.count == 0) {
            return nil;
        }
        JJRedBagParam *first = self.queue.firstObject;
        [self.queue removeObjectAtIndex:0];
        return first;
    }
}

- (JJRedBagParam *)peek {
    @synchronized (self.queue) {
        return self.queue.firstObject;
    }
}

- (BOOL)isEmpty {
    @synchronized (self.queue) {
        return self.queue.count == 0;
    }
}

@end

#pragma mark - JJReceiveRedBagOperation

@interface JJReceiveRedBagOperation ()

@property (assign, nonatomic, getter=isExecuting) BOOL executing;
@property (assign, nonatomic, getter=isFinished) BOOL finished;
@property (strong, nonatomic) JJRedBagParam *redBagParam;
@property (assign, nonatomic) unsigned int delayMs;

@end

@implementation JJReceiveRedBagOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (instancetype)initWithRedBagParam:(JJRedBagParam *)param delay:(unsigned int)delayMs {
    if (self = [super init]) {
        _redBagParam = param;
        _delayMs = delayMs;
    }
    return self;
}

- (void)start {
    if (self.isCancelled) {
        self.finished = YES;
        self.executing = NO;
        return;
    }
    
    self.executing = YES;
    self.finished = NO;
    [self main];
}

- (void)main {
    if (self.delayMs > 0) {
        [NSThread sleepForTimeInterval:self.delayMs / 1000.0];
    }
    
    if (self.isCancelled) {
        self.finished = YES;
        self.executing = NO;
        return;
    }
    
    WCRedEnvelopesLogicMgr *logicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] 
                                          getService:objc_getClass("WCRedEnvelopesLogicMgr")];
    if (logicMgr) {
        [logicMgr OpenRedEnvelopesRequest:[self.redBagParam toParams]];
    }
    
    self.finished = YES;
    self.executing = NO;
}

- (void)cancel {
    [super cancel];
    self.finished = YES;
    self.executing = NO;
}

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isAsynchronous {
    return YES;
}

@end

#pragma mark - JJRedBagTaskManager

@interface JJRedBagTaskManager ()

@property (strong, nonatomic) NSOperationQueue *normalTaskQueue;
@property (strong, nonatomic) NSOperationQueue *serialTaskQueue;

@end

@implementation JJRedBagTaskManager

+ (instancetype)sharedManager {
    static JJRedBagTaskManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[JJRedBagTaskManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        _serialTaskQueue = [[NSOperationQueue alloc] init];
        _serialTaskQueue.maxConcurrentOperationCount = 1;
        
        _normalTaskQueue = [[NSOperationQueue alloc] init];
        _normalTaskQueue.maxConcurrentOperationCount = 5;
    }
    return self;
}

- (void)addNormalTask:(JJReceiveRedBagOperation *)task {
    [self.normalTaskQueue addOperation:task];
}

- (void)addSerialTask:(JJReceiveRedBagOperation *)task {
    [self.serialTaskQueue addOperation:task];
}

- (BOOL)serialQueueIsEmpty {
    return self.serialTaskQueue.operations.count == 0;
}

@end
