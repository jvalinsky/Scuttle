#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRComposeViewController : NSViewController

@property (nonatomic, copy, nullable) void (^onPublish)(NSString *text, NSString * _Nullable contentWarning);

@end

NS_ASSUME_NONNULL_END