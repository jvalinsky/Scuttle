#import "SRComposeViewController.h"
#import "../Logic/SRRoomManager.h"
#import <SSBNetwork/SSBRoomClient.h>

@interface SRComposeViewController ()
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSTextField *cwField;
@property (nonatomic, strong) NSButton *publishButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@end

@implementation SRComposeViewController

- (void)loadView {
    NSView *view = [[NSView alloc] init];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    view.layer.cornerRadius = 8;
    view.layer.borderWidth = 1;
    view.layer.borderColor = [NSColor separatorColor].CGColor;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(syncStatusDidUpdate:) 
                                                 name:@"SRRoomSyncStatusChangedNotification" 
                                               object:nil];
}

- (void)setupUI {
    self.cwField = [[NSTextField alloc] init];
    self.cwField.placeholderString = @"Content Warning (optional)";
    self.cwField.translatesAutoresizingMaskIntoConstraints = NO;
    self.cwField.bezelStyle = NSTextFieldSquareBezel;
    [self.view addSubview:self.cwField];
    
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.textView.editable = YES;
    self.textView.selectable = YES;
    self.textView.richText = NO;
    self.textView.font = [NSFont systemFontOfSize:13];
    self.textView.textContainerInset = NSMakeSize(8, 8);
    self.scrollView.documentView = self.textView;
    
    self.publishButton = [NSButton buttonWithTitle:@"Publish" target:self action:@selector(publishAction:)];
    self.publishButton.bezelStyle = NSBezelStyleRounded;
    self.publishButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.publishButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.cwField.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [self.cwField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.cwField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.cwField.bottomAnchor constant:8],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.publishButton.topAnchor constant:-8],
        
        [self.publishButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.publishButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12]
    ]];
}

- (void)publishAction:(id)sender {
    NSString *text = self.textView.string;
    NSString *cw = self.cwField.stringValue;
    if (text.length == 0) return;
    
    if (self.onPublish) {
        self.onPublish(text, cw.length > 0 ? cw : nil, self.replyToKey);
    }
    
    [self clear];
}

- (void)clear {
    self.textView.string = @"";
    self.cwField.stringValue = @"";
    self.replyToKey = nil;
}

- (void)syncStatusDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *status = userInfo[@"status"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Disable publish if syncing or queued
        BOOL isSyncing = [status containsString:@"Syncing"] || [status containsString:@"Queued"];
        self.publishButton.enabled = !isSyncing;
        
        if ([status containsString:@"Queued"]) {
            self.publishButton.title = [NSString stringWithFormat:@"Publish (%@)", status];
        } else if (isSyncing) {
            self.publishButton.title = @"Syncing...";
        } else {
            self.publishButton.title = @"Publish";
        }
    });
}

@end