#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SSBPlatformUIProtocol <NSObject>

- (NSModalResponse)runModalAlert:(NSAlert *)alert;

@end

@interface SSBPlatformUI : NSObject <SSBPlatformUIProtocol>

@property (class, nonatomic, strong) id<SSBPlatformUIProtocol> shared;

@end

NS_ASSUME_NONNULL_END
