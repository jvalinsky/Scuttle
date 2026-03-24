#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SRChannelBrowserViewController;

@protocol SRChannelBrowserDelegate <NSObject>
@optional
- (void)channelBrowser:(SRChannelBrowserViewController *)vc didSelectChannel:(NSString *)channel;
- (void)channelBrowserDidRequestBack:(SRChannelBrowserViewController *)vc;
@end

@interface SRChannelBrowserViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id<SRChannelBrowserDelegate> delegate;

- (void)setChannels:(NSArray<NSString *> *)channels;

@end

NS_ASSUME_NONNULL_END
