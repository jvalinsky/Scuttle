#import "SRPlatformUI.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRComposeViewController : NSViewController

@property (nonatomic, copy, nullable) NSString *replyToKey;
@property (nonatomic, copy, nullable) void (^onPublish)(NSString *text, NSString * _Nullable contentWarning, NSString * _Nullable replyToKey);

- (void)clear;

@end

NS_ASSUME_NONNULL_END