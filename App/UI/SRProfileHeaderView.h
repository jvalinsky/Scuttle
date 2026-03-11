#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRProfileHeaderView : NSView
@property (nonatomic, assign) BOOL hidesProfileButton;
- (void)updateWithIdentity:(NSString *)feedId name:(nullable NSString *)name;
- (void)updateSyncProgress:(float)progress status:(NSString *)status;

@end

NS_ASSUME_NONNULL_END
