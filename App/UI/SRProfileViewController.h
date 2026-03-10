@class SRProfileViewController;

@protocol SRProfileViewControllerDelegate <NSObject>
@optional
- (void)profileViewControllerDidRequestBack:(SRProfileViewController *)vc;
@end

@interface SRProfileViewController : NSViewController

@property (nonatomic, weak, nullable) id<SRProfileViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *peerID;
@property (nonatomic, strong, nullable) SSBRoomClient *client;

- (instancetype)initWithPeerID:(NSString *)peerID client:(nullable SSBRoomClient *)client;

@end

NS_ASSUME_NONNULL_END
