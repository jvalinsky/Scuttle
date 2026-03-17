#import "SRGitNewIssueViewController.h"

@interface SRGitNewIssueViewController ()
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextView *bodyView;
@property (nonatomic, strong) NSButton *submitButton;
@property (nonatomic, strong) NSButton *cancelButton;
@end

@implementation SRGitNewIssueViewController

- (instancetype)initWithRepoID:(NSString *)repoID client:(SSBRoomClient *)client {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _currentClient = client;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
}

- (void)setupUI {
    NSTextField *titleLabel = [NSTextField labelWithString:@"Title:"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];
    
    self.titleField = [[NSTextField alloc] init];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleField];
    
    NSTextField *bodyLabel = [NSTextField labelWithString:@"Description:"];
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bodyLabel];
    
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    
    self.bodyView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = self.bodyView;
    
    self.submitButton = [NSButton buttonWithTitle:@"Submit" target:self action:@selector(submit:)];
    self.submitButton.bezelStyle = NSBezelStyleRounded;
    self.submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.submitButton];
    
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        
        [self.titleField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [self.titleField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.titleField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [bodyLabel.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:12],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        
        [scroll.topAnchor constraintEqualToAnchor:bodyLabel.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:self.submitButton.topAnchor constant:-20],
        
        [self.submitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.submitButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20],
        
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.submitButton.leadingAnchor constant:-12],
        [self.cancelButton.centerYAnchor constraintEqualToAnchor:self.submitButton.centerYAnchor]
    ]];
}

- (void)submit:(id)sender {
    NSString *title = self.titleField.stringValue;
    NSString *body = self.bodyView.string;
    
    if (title.length == 0) return;
    
    NSDictionary *content = @{
        @"type": @"issue",
        @"repo": self.repoID,
        @"title": title,
        @"text": body,
        @"open": @YES
    };
    
    [self.submitButton setEnabled:NO];
    [self.currentClient publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.submitButton setEnabled:YES];
            if (!error) {
                [self dismissViewController:self];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitIssueCreatedNotification" object:nil];
            }
        });
    }];
}

- (void)cancel:(id)sender {
    [self dismissViewController:self];
}

@end
