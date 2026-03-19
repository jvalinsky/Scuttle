#ifndef SSBURLSessionCompat_h
#define SSBURLSessionCompat_h

#import <Foundation/Foundation.h>

#ifdef __APPLE__
// On Apple platforms, NSURLSession is native.
#else

NS_ASSUME_NONNULL_BEGIN

/**
 * 2026 Linux/GNUstep Compatibility Shim for NSURLSession.
 * GNUstep Base often lacks NSURLSession or has an incomplete implementation.
 */

@interface NSURLSessionDataTask : NSObject
- (void)resume;
- (void)cancel;
@end

@interface NSURLSession : NSObject
+ (NSURLSession *)sharedSession;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url 
                        completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                            completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
@end

NS_ASSUME_NONNULL_END

#endif /* __APPLE__ */

#endif /* SSBURLSessionCompat_h */
