#import "SRGitFileViewController.h"
#import "../../Sources/SSBGitObjectStore.h"
#import <WebKit/WebKit.h>

@interface SRGitFileViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) WKWebView *webView;
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
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webView.hidden = YES;
    [self.view addSubview:self.webView];
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
    
    if ([name.lowercaseString hasSuffix:@".md"]) {
        self.scrollView.hidden = YES;
        self.webView.hidden = NO;
        // In a real app, we'd use SRMarkdownParser to generate HTML
        NSString *html = [NSString stringWithFormat:@"<html><body><pre>%@</pre></body></html>", content];
        [self.webView loadHTMLString:html baseURL:nil];
    } else {
        self.webView.hidden = YES;
        self.scrollView.hidden = NO;
        self.textView.string = content;
    }
}

@end
