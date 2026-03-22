#import "SRPlatformUI.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRProfileHeaderView : NSView
@property (nonatomic, assign) BOOL hidesProfileButton;
@property (nonatomic, assign) BOOL compactMode;

- (void)updateWithIdentity:(NSString *)feedId name:(nullable NSString *)name;
- (void)updateSyncProgress:(float)progress status:(NSString *)status;

@end

NS_ASSUME_NONNULL_END
