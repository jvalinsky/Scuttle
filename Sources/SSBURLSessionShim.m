#import "SSBURLSessionCompat.h"

#ifndef __APPLE__

@interface SSBURLSessionDataTaskShim : NSURLSessionDataTask
@property (copy) void (^completionHandler)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error);
@property (copy) NSURLRequest *request;
@end

@implementation SSBURLSessionDataTaskShim

- (void)resume {
    NSLog(@"STUB: NSURLSessionDataTask resume for %@", self.request.URL);
    // In a real implementation, we would perform the request here using NSURLConnection or curl.
    // For now, we just return an error to satisfy the caller.
    if (self.completionHandler) {
        NSError *error = [NSError errorWithDomain:@"SSBURLSessionShim" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"NSURLSession shim not fully implemented."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.completionHandler(nil, nil, error);
        });
    }
}

- (void)cancel {
    NSLog(@"STUB: NSURLSessionDataTask cancel");
}

@end

@implementation NSURLSession

+ (NSURLSession *)sharedSession {
    static NSURLSession *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[NSURLSession alloc] init];
    });
    return shared;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url 
                        completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                            completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    SSBURLSessionDataTaskShim *task = [[SSBURLSessionDataTaskShim alloc] init];
    task.request = request;
    task.completionHandler = completionHandler;
    return task;
}

@end

#endif
