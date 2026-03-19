#import "SSBURLSessionCompat.h"

#ifndef __APPLE__

@implementation NSURLSessionDataTask
- (void)resume { }
- (void)cancel { }
@end

@interface SSBURLSessionDataTaskShim : NSURLSessionDataTask
@property (copy) void (^completionHandler)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error);
@property (copy) NSURLRequest *request;
@end

@implementation SSBURLSessionDataTaskShim

- (void)resume {
    NSLog(@"STUB: NSURLSessionDataTask resume for %@", self.request.URL);
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
                        completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    SSBURLSessionDataTaskShim *task = [[SSBURLSessionDataTaskShim alloc] init];
    task.request = request;
    task.completionHandler = completionHandler;
    return task;
}

@end

#endif
