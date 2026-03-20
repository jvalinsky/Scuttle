#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages a Unix Domain Socket server that communicates with the git-remote-ssb CLI helper.
@interface SRGitRemoteHelperServer : NSObject

+ (instancetype)sharedServer;

/// Starts the UDS server at the resolved Scuttle runtime socket path.
- (BOOL)start;

/// Stops the server and removes the socket file.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
