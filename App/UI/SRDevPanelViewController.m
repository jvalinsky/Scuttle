#import "SRDevPanelViewController.h"
#import "../../Sources/SSBNetwork.h"

@interface SRDevPanelViewController ()
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *pubkeyLabel;
@property (nonatomic, strong) NSTextField *statsLabel;
@end

@implementation SRDevPanelViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.pubkeyLabel = [NSTextField labelWithString:@"Public Key: Loading..."];
    self.pubkeyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pubkeyLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [self.view addSubview:self.pubkeyLabel];
    
    self.statsLabel = [NSTextField labelWithString:@"Stats: Loading..."];
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statsLabel];
    
    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [self.view addSubview:scrollView];
    
    self.logView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    self.logView.editable = NO;
    self.logView.verticallyResizable = YES;
    self.logView.autoresizingMask = NSViewWidthSizable;
    self.logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    scrollView.documentView = self.logView;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.pubkeyLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [self.pubkeyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.pubkeyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.statsLabel.topAnchor constraintEqualToAnchor:self.pubkeyLabel.bottomAnchor constant:10],
        [self.statsLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        
        [scrollView.topAnchor constraintEqualToAnchor:self.statsLabel.bottomAnchor constant:20],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20]
    ]];
    
    [self refreshData];
}

- (void)refreshData {
    NSData *localSecret = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
    if (localSecret && localSecret.length >= 64) {
        NSData *pkData = [localSecret subdataWithRange:NSMakeRange(32, 32)];
        NSString *pubkey = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        self.pubkeyLabel.stringValue = [NSString stringWithFormat:@"Public Key: %@", pubkey];
    }
    
    NSInteger totalMsgs = [[SSBFeedStore sharedStore] totalMessageCount];
    self.statsLabel.stringValue = [NSString stringWithFormat:@"Total Messages: %ld", (long)totalMsgs];
    
    NSArray<SSBMessage *> *recent = [[SSBFeedStore sharedStore] recentMessagesWithLimit:20];
    NSMutableString *jsonDump = [NSMutableString string];
    [jsonDump appendString:@"--- LAST 20 MESSAGES ---\n\n"];
    
    for (SSBMessage *msg in recent) {
        [jsonDump appendFormat:@"Key: %@\nAuthor: %@\nSequence: %ld\nContent: ", msg.key, msg.author, (long)msg.sequence];
        if (msg.content) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:msg.content options:NSJSONWritingPrettyPrinted error:nil];
            NSString *contentStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [jsonDump appendString:contentStr ?: @"Error encoding JSON"];
        } else {
            [jsonDump appendString:@"(None)"];
        }
        [jsonDump appendString:@"\n\n------------------------\n\n"];
    }
    
    self.logView.string = jsonDump;
}

@end
