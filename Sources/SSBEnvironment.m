#import "SSBEnvironment.h"

@implementation SSBEnvironment

static id<SSBEnvironmentProtocol> _sharedEnvironment = nil;

+ (void)initialize {
    if (self == [SSBEnvironment class]) {
        _sharedEnvironment = [[SSBEnvironment alloc] init];
    }
}

+ (id<SSBEnvironmentProtocol>)shared {
    return _sharedEnvironment;
}

+ (void)setShared:(id<SSBEnvironmentProtocol>)shared {
    _sharedEnvironment = shared ?: [[SSBEnvironment alloc] init];
}

- (NSDate *)now {
    return [NSDate date];
}

- (uint32_t)randomUInt32 {
    return arc4random();
}

- (void)randomBytes:(void *)buffer length:(NSUInteger)length {
    arc4random_buf(buffer, length);
}

- (NSURLSession *)URLSession {
    return [NSURLSession sharedSession];
}

- (NSURLSession *)URLSessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    return [NSURLSession sessionWithConfiguration:configuration];
}

- (NSFileManager *)fileManager {
    return [NSFileManager defaultManager];
}

- (NSString *)scuttleDataDirectory {
    NSString *xdgData = NSProcessInfo.processInfo.environment[@"XDG_DATA_HOME"];
    if (xdgData.length > 0) {
        return [xdgData stringByAppendingPathComponent:@"scuttle"];
    }
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [appSupport stringByAppendingPathComponent:@"Scuttle"];
}

- (void)dispatchAfter:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, block);
}

@end

void SSBEnvironmentRandomBytes(void *buffer, size_t length) {
    [[SSBEnvironment shared] randomBytes:buffer length:length];
}
