#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * SSBEnvironment provides test seams for system boundaries such as time, 
 * randomness, filesystem roots, and keychain access, ensuring 100% code 
 * coverage is possible deterministically.
 */
@protocol SSBEnvironmentProtocol <NSObject>

- (NSDate *)now;
- (uint32_t)randomUInt32;
- (void)randomBytes:(void *)buffer length:(NSUInteger)length;
- (NSURLSession *)URLSession;
- (NSURLSession *)URLSessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
- (NSFileManager *)fileManager;
- (NSString *)scuttleDataDirectory;
- (void)dispatchAfter:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block;

@end

@interface SSBEnvironment : NSObject <SSBEnvironmentProtocol>

@property (class, nonatomic, strong) id<SSBEnvironmentProtocol> shared;

@end

#ifdef __cplusplus
extern "C" {
#endif
    void SSBEnvironmentRandomBytes(void *buffer, size_t length);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
