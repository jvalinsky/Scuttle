#import "SRGitFileViewController.h"
#import "../../Sources/SSBGitObjectStore.h"

@interface SRGitFileViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@end

@implementation SRGitFileViewController

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
}

- (void)setupUI {
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = YES;
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:self.scrollView];
    
    self.textView = [[NSTextView alloc] initWithFrame:self.scrollView.bounds];
    self.textView.editable = NO;
    self.textView.font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont userFixedPitchFontOfSize:12];
    self.scrollView.documentView = self.textView;
}

- (void)loadFileWithSHA1:(NSString *)sha1 name:(NSString *)name objectStore:(SSBGitObjectStore *)objectStore {
    SSBGitObject *obj = [objectStore objectForSHA1:sha1];
    if (!obj || obj.type != SSBGitObjectTypeBlob) {
        self.textView.string = @"Error: Could not load file.";
        return;
    }
    
    NSString *content = [[NSString alloc] initWithData:obj.data encoding:NSUTF8StringEncoding];
    if (!content) {
        // Binary file?
        self.textView.string = @"[Binary File]";
        return;
    }
    
    self.scrollView.hidden = NO;
    self.textView.string = content;
}

@end
