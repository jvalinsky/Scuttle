#import "SRGitNewPRViewController.h"

@interface SRGitNewPRViewController ()
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSPopUpButton *headRepoPopUp;
@property (nonatomic, strong) NSTextField *baseBranchField;
@property (nonatomic, strong) NSTextField *headBranchField;
@property (nonatomic, strong) NSTextView *bodyView;
@property (nonatomic, strong) NSButton *submitButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSTextField *crossRepoNoteLabel;
@property (nonatomic, strong) NSArray<SSBMessage *> *availableRepos;
@end

@implementation SRGitNewPRViewController

- (instancetype)initWithRepoID:(NSString *)repoID client:(SSBRoomClient *)client {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _currentClient = client;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 450)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self loadRepos];
}

- (void)setupUI {
    NSTextField *titleLabel = [NSTextField labelWithString:@"Title:"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];
    
    self.titleField = [[NSTextField alloc] init];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleField];

    NSTextField *headRepoLabel = [NSTextField labelWithString:@"Head Repository (Fork):"];
    headRepoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:headRepoLabel];

    self.headRepoPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.headRepoPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headRepoPopUp];
    
    NSTextField *baseLabel = [NSTextField labelWithString:@"Base Branch:"];
    baseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:baseLabel];
    
    self.baseBranchField = [[NSTextField alloc] init];
    self.baseBranchField.stringValue = @"main";
    self.baseBranchField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.baseBranchField];
    
    NSTextField *headLabel = [NSTextField labelWithString:@"Head Branch:"];
    headLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:headLabel];
    
    self.headBranchField = [[NSTextField alloc] init];
    self.headBranchField.placeholderString = @"feature-branch";
    self.headBranchField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headBranchField];
    
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
    
    self.submitButton = [NSButton buttonWithTitle:@"Create PR" target:self action:@selector(submit:)];
    self.submitButton.bezelStyle = NSBezelStyleRounded;
    self.submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.submitButton];
    
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelButton];

    // Cross-repo PR note
    self.crossRepoNoteLabel = [NSTextField labelWithString:@"Note: Selecting a different head repository will create a cross-repository pull request, which is fully compatible with git-ssb clients."];
    self.crossRepoNoteLabel.font = [NSFont systemFontOfSize:10];
    self.crossRepoNoteLabel.textColor = [NSColor secondaryLabelColor];
    self.crossRepoNoteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.crossRepoNoteLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.crossRepoNoteLabel.maximumNumberOfLines = 0;
    self.crossRepoNoteLabel.preferredMaxLayoutWidth = 410;
    [self.view addSubview:self.crossRepoNoteLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        
        [self.titleField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [self.titleField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.titleField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [headRepoLabel.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:12],
        [headRepoLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [self.headRepoPopUp.topAnchor constraintEqualToAnchor:headRepoLabel.bottomAnchor constant:8],
        [self.headRepoPopUp.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.headRepoPopUp.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [baseLabel.topAnchor constraintEqualToAnchor:self.headRepoPopUp.bottomAnchor constant:12],
        [baseLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        
        [self.baseBranchField.topAnchor constraintEqualToAnchor:baseLabel.bottomAnchor constant:8],
        [self.baseBranchField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.baseBranchField.widthAnchor constraintEqualToConstant:150],
        
        [headLabel.topAnchor constraintEqualToAnchor:self.headRepoPopUp.bottomAnchor constant:12],
        [headLabel.leadingAnchor constraintEqualToAnchor:self.baseBranchField.trailingAnchor constant:20],
        
        [self.headBranchField.topAnchor constraintEqualToAnchor:headLabel.bottomAnchor constant:8],
        [self.headBranchField.leadingAnchor constraintEqualToAnchor:self.baseBranchField.trailingAnchor constant:20],
        [self.headBranchField.widthAnchor constraintEqualToConstant:150],

        [self.crossRepoNoteLabel.topAnchor constraintEqualToAnchor:self.baseBranchField.bottomAnchor constant:12],
        [self.crossRepoNoteLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.crossRepoNoteLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [bodyLabel.topAnchor constraintEqualToAnchor:self.crossRepoNoteLabel.bottomAnchor constant:12],
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

- (void)loadRepos {
    [self.headRepoPopUp removeAllItems];
    
    // Always add the current repo as the first option
    [self.headRepoPopUp addItemWithTitle:@"Current Repository"];
    
    // Query for other git-repo messages that are forks of this one
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"git-repo" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"upstream"], self.repoID ] }
        ]
    };
    
    NSArray<SSBMessage *> *forks = [[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @YES}];
    self.availableRepos = forks;
    
    for (SSBMessage *fork in forks) {
        NSString *name = fork.content[@"name"] ?: @"Unnamed Fork";
        NSString *author = [[SSBFeedStore sharedStore] displayNameForAuthor:fork.author];
        [self.headRepoPopUp addItemWithTitle:[NSString stringWithFormat:@"%@ (by %@)", name, author]];
    }
}

- (void)submit:(id)sender {
    NSString *title = self.titleField.stringValue;
    NSString *body = self.bodyView.string;
    NSString *base = self.baseBranchField.stringValue;
    NSString *head = self.headBranchField.stringValue;
    
    if (title.length == 0 || base.length == 0 || head.length == 0) return;
    
    NSString *selectedHeadRepoID = self.repoID;
    NSInteger selectedIdx = self.headRepoPopUp.indexOfSelectedItem;
    if (selectedIdx > 0 && selectedIdx <= self.availableRepos.count) {
        selectedHeadRepoID = self.availableRepos[selectedIdx - 1].key;
    }
    
    NSDictionary *content = @{
        @"type": @"pull-request",
        @"repo": self.repoID,
        @"baseRepo": self.repoID,
        @"baseBranch": base,
        @"headRepo": selectedHeadRepoID,
        @"headBranch": head,
        @"title": title,
        @"text": body
    };
    
    [self.submitButton setEnabled:NO];
    [self.currentClient publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.submitButton setEnabled:YES];
            if (!error) {
                [self dismissViewController:self];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitPRCreatedNotification" object:nil];
            }
        });
    }];
}

- (void)cancel:(id)sender {
    [self dismissViewController:self];
}

@end
