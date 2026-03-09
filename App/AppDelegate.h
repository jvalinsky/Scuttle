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

@interface AppDelegate : NSObject <NSApplicationDelegate, SSBRoomClientDelegate, NSTableViewDelegate, NSTableViewDataSource>

@property (strong) NSWindow *window;
@property (strong) SSBRoomClient *client;
@property (strong) NSArray<NSString *> *endpoints;
@property (strong) NSTableView *tableView;

// Detail View Components
@property (strong) NSView *detailView;
@property (strong) NSTextField *detailTitleLabel;
@property (strong) NSTextField *detailStatusLabel;
@property (strong) NSStackView *metaStackFrame;
@property (strong) MetaCardView *latencyCard;
@property (strong) MetaCardView *protocolCard;

@end
