#ifndef SSBURLSessionCompat_h
#define SSBURLSessionCompat_h

#import <Foundation/Foundation.h>

#ifdef __APPLE__
// On Apple platforms, NSURLSession is native.
#else

NS_ASSUME_NONNULL_BEGIN

@interface NSURLSessionDataTask : NSObject
- (void)resume;
- (void)cancel;
@property (copy, nullable) NSURLRequest *request;
@end

@interface NSURLSession : NSObject
+ (NSURLSession *)sharedSession;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler;
@end

NS_ASSUME_NONNULL_END

#endif

#endif
