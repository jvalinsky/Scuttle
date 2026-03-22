#import <Cocoa/Cocoa.h>
#import "SRWorkspaceTypes.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SRStripDelegate <NSObject>
- (void)stripDidSelectContext:(SRWorkspaceContext)context;
@end

@interface SRStripViewController : NSViewController

@property (nonatomic, weak) id<SRStripDelegate> delegate;
@property (nonatomic, assign) SRWorkspaceContext selectedContext;

@end

NS_ASSUME_NONNULL_END
