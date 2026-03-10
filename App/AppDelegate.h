#import <Cocoa/Cocoa.h>
#import "../Sources/SSBNetwork.h"

@interface PeerCellView : NSTableCellView
@property (strong) NSView *avatarView;
@property (strong) NSTextField *pubKeyLabel;
@end

@interface MetaCardView : NSView
@property (strong) NSTextField *titleLabel;
@property (strong) NSTextField *valueLabel;
@end

@interface FeedItemView : NSView
- (instancetype)initWithMessage:(NSDictionary *)msg;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, SSBRoomClientDelegate, NSTableViewDelegate, NSTableViewDataSource>

@property (strong) NSWindow *window;
@property (strong) NSMutableDictionary<NSString *, SSBRoomClient *> *clients;
@property (strong) NSArray<RoomConfig *> *rooms;
@property (strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *roomEndpoints;
@property (strong) NSMutableArray<NSString *> *connectedRoomHosts;
@property (strong) NSTableView *tableView;

// Detail View Components
@property (strong) NSView *detailView;
@property (strong) NSTextField *detailTitleLabel;
@property (strong) NSTextField *detailStatusLabel;
@property (strong) NSStackView *metaStackFrame;
@property (strong) NSView *avatarView;
@property (strong) NSTextField *identityLabel;
@property (strong) NSTextView *logTextView;
@property (strong) MetaCardView *latencyCard;
@property (strong) MetaCardView *protocolCard;

// Feed Preview
@property (strong) NSScrollView *feedScrollView;
@property (strong) NSStackView *feedStackView;

// Compose & Timeline
@property (strong) NSTextView *composeTextView;
@property (strong) NSButton *publishButton;
@property (strong) NSSegmentedControl *viewSelector;
@property (strong) NSTextField *feedCountLabel;

@property (strong) NSButton *disconnectButton;
@property (strong) NSButton *reconnectButton;
@property (strong) NSButton *removeRoomButton;
@property (strong) NSTextField *connectionStatusLabel;
@property (strong) NSView *statusDot;

@end
