#import "SRGitDiffViewController.h"
#import "../../Sources/SSBDiffEngine.h"
#import "../../Sources/SSBGitObjectStore.h"

@interface SRGitDiffViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSSegmentedControl *algorithmControl;
@property (nonatomic, copy, nullable) NSString *currentSha1;
@property (nonatomic, strong, nullable) SSBGitRepo *currentRepo;
@end

@implementation SRGitDiffViewController

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
}

- (void)setupUI {
    self.algorithmControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Myers", @"Histogram"]
                                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                    target:self
                                                                    action:@selector(algorithmChanged:)];
    self.algorithmControl.selectedSegment = 0;
    self.algorithmControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.algorithmControl];

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.textView.editable = NO;
    self.textView.font = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont userFixedPitchFontOfSize:11];
    self.textView.autoresizingMask = NSViewWidthSizable;
    self.scrollView.documentView = self.textView;

    [NSLayoutConstraint activateConstraints:@[
        [self.algorithmControl.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.algorithmControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.algorithmControl.bottomAnchor constant:10],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)algorithmChanged:(id)sender {
    if (self.currentSha1 && self.currentRepo) {
        [self loadDiffForCommit:self.currentSha1 repo:self.currentRepo];
    }
}

- (void)loadDiffForCommit:(NSString *)sha1 repo:(SSBGitRepo *)repo {
    self.currentSha1 = sha1;
    self.currentRepo = repo;
    
    SSBGitObject *commitObj = [repo.objectStore objectForSHA1:sha1];
    if (!commitObj || commitObj.type != SSBGitObjectTypeCommit) {
        self.textView.string = @"Error: Could not load commit.";
        return;
    }
    
    NSString *content = [[NSString alloc] initWithData:commitObj.data encoding:NSUTF8StringEncoding];
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    NSString *parentSha1 = nil;
    for (NSString *line in lines) {
        if ([line hasPrefix:@"parent "]) {
            parentSha1 = [line substringFromIndex:7];
            break;
        }
    }
    
    if (!parentSha1) {
        self.textView.string = content; // Initial commit
        return;
    }
    
    SSBGitObject *parentObj = [repo.objectStore objectForSHA1:parentSha1];
    if (!parentObj) {
        self.textView.string = content;
        return;
    }
    
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    SSBDiffAlgorithmType algo = (self.algorithmControl.selectedSegment == 0) ? SSBDiffAlgorithmTypeMyers : SSBDiffAlgorithmTypeHistogram;
    
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:[[NSString alloc] initWithData:parentObj.data encoding:NSUTF8StringEncoding]
                                            withString:content
                                             algorithm:algo];
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    
    // Add Metadata Header
    NSString *commitMsg = @"";
    NSString *author = @"";
    NSString *date = @"";
    for (NSString *line in lines) {
        if ([line hasPrefix:@"author "]) author = [line substringFromIndex:7];
        else if ([line hasPrefix:@"committer "]) {} // Skip committer for now
        else if (line.length == 0) {
            NSUInteger idx = [lines indexOfObject:line];
            if (idx + 1 < lines.count) {
                commitMsg = [lines[idx + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            break;
        }
    }
    
    NSDictionary *msgAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSDictionary *metaAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", commitMsg] attributes:msgAttr]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Authored by %@\n", author] attributes:metaAttr]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n------------------------------------------------------------\n\n" attributes:metaAttr]];

    for (SSBDiffHunk *hunk in hunks) {
        NSDictionary *headerAttr = @{
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            NSFontAttributeName: [NSFont fontWithName:@"Menlo-Bold" size:11] ?: [NSFont boldSystemFontOfSize:11]
        };
        [as appendAttributedString: [[NSAttributedString alloc] initWithString:[hunk hunkHeader] attributes:headerAttr]];
        [as appendAttributedString: [[NSAttributedString alloc] initWithString:@"\n"]];
        
        for (SSBDiffEdit *edit in hunk.edits) {
            NSColor *bgColor = [NSColor clearColor];
            NSString *prefix = @" ";
            if (edit.type == SSBDiffEditTypeAdd) {
                bgColor = [NSColor colorWithDeviceRed:0.0 green:1.0 blue:0.0 alpha:0.1];
                prefix = @"+";
            } else if (edit.type == SSBDiffEditTypeDelete) {
                bgColor = [NSColor colorWithDeviceRed:1.0 green:0.0 blue:0.0 alpha:0.1];
                prefix = @"-";
            }
            
            NSDictionary *lineAttr = @{
                NSBackgroundColorAttributeName: bgColor,
                NSForegroundColorAttributeName: [NSColor labelColor]
            };
            NSString *line = [NSString stringWithFormat:@"%@%@\n", prefix, edit.lineContent];
            [as appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:lineAttr]];
        }
    }
    
    [self.textView.textStorage setAttributedString:as];
}

@end
