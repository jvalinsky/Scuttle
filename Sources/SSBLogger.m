#import "SSBLogger.h"

typedef void (^SSBInternalProtocolTraceSink)(NSDictionary<NSString *, id> *event);

static SSBInternalProtocolTraceSink gSSBProtocolTraceSink = nil;
static dispatch_queue_t gSSBProtocolTraceQueue = nil;

@interface SSBLogger ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, os_log_t> *logs;
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t logQueue;
@end

@implementation SSBLogger

+ (SSBLogger *)shared {
    static SSBLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SSBLogger alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logs = [NSMutableDictionary dictionary];
        _logQueue = dispatch_queue_create("com.scuttlekit.logger", DISPATCH_QUEUE_SERIAL);
        _minimumLevel = SSBLogLevelDebug;
        
        [self createLogsForAllCategories];
    }
    return self;
}

- (void)createLogsForAllCategories {
    NSString *bundleID = @"com.scuttlebutt.room"; // Match existing logging subsystem
    
    for (NSInteger i = 0; i <= SSBLogCategoryAuth; i++) {
        os_log_t log = os_log_create([bundleID UTF8String], [SSBLogCategoryName((SSBLogCategory)i) UTF8String]);
        self.logs[@(i)] = log;
    }
}

- (os_log_t)logForCategory:(SSBLogCategory)category {
    os_log_t log = self.logs[@(category)];
    if (!log) {
        log = OS_LOG_DEFAULT;
    }
    return log;
}

- (void)log:(SSBLogCategory)category level:(SSBLogLevel)level message:(NSString *)message {
    if (level < self.minimumLevel) return;
    
    os_log_t log = [self logForCategory:category];
    
    switch (level) {
        case SSBLogLevelDebug:
            os_log_debug(log, "%{public}@", message);
            break;
        case SSBLogLevelInfo:
            os_log_info(log, "%{public}@", message);
            break;
        case SSBLogLevelWarning:
            os_log(log, "%{public}@", message);
            break;
        case SSBLogLevelError:
            os_log_error(log, "%{public}@", message);
            break;
    }
}

- (void)log:(SSBLogCategory)category level:(SSBLogLevel)level format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self log:category level:level message:message];
}

- (void)debug:(NSString *)message category:(SSBLogCategory)category {
    [self log:category level:SSBLogLevelDebug message:message];
}

- (void)info:(NSString *)message category:(SSBLogCategory)category {
    [self log:category level:SSBLogLevelInfo message:message];
}

- (void)warning:(NSString *)message category:(SSBLogCategory)category {
    [self log:category level:SSBLogLevelWarning message:message];
}

- (void)error:(NSString *)message category:(SSBLogCategory)category {
    [self log:category level:SSBLogLevelError message:message];
}

- (NSString *)stateToString:(NSString *)stateName value:(NSInteger)value {
    return [NSString stringWithFormat:@"%@.%ld", stateName, (long)value];
}

- (void)logStateTransition:(NSString *)stateName from:(NSInteger)from to:(NSInteger)to category:(SSBLogCategory)category {
    [self info:[NSString stringWithFormat:@"🔄 %@: %ld → %ld", stateName, (long)from, (long)to] category:category];
}

@end

@implementation SSBLogger (ProtocolTraceInternal)

+ (void)ssb_setProtocolTraceSink:(SSBInternalProtocolTraceSink)sink {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSSBProtocolTraceQueue = dispatch_queue_create("com.scuttlekit.logger.protocoltrace", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_sync(gSSBProtocolTraceQueue, ^{
        gSSBProtocolTraceSink = [sink copy];
    });
}

+ (SSBInternalProtocolTraceSink)ssb_protocolTraceSink {
    __block SSBInternalProtocolTraceSink sink = nil;
    if (!gSSBProtocolTraceQueue) {
        return nil;
    }

    dispatch_sync(gSSBProtocolTraceQueue, ^{
        sink = gSSBProtocolTraceSink;
    });
    return sink;
}

+ (void)ssb_emitProtocolTraceEvent:(NSDictionary<NSString *,id> *)event {
    if (![event isKindOfClass:[NSDictionary class]] || event.count == 0) {
        return;
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    NSString *message = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : [event description];
    if (message.length > 0) {
        [[SSBLogger shared] debug:message category:SSBLogCategoryNetwork];
    }

    SSBInternalProtocolTraceSink sink = [self ssb_protocolTraceSink];
    if (sink) {
        sink(event);
    }
}

@end
