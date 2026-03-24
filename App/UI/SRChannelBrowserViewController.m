#import "SRChannelBrowserViewController.h"
#import "../../Sources/SSBFeedStore.h"

@interface SRChannelBrowserViewController ()
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSArray<NSString *> *channels;
@property (nonatomic, strong) NSButton *backButton;
@end

@implementation SRChannelBrowserViewController

- (void)loadView {
    NSView *container = [[NSView alloc] init];
    container.wantsLayer = YES;
    container.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    
    self.backButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Back"] target:self action:@selector(backAction:)];
    self.backButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.backButton];
    
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.headerView = nil;
    self.tableView.backgroundColor = [NSColor clearColor];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"ChannelColumn"];
    [self.tableView addTableColumn:column];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.scrollView.documentView = self.tableView;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.backButton.bottomAnchor constant:12],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    
    [self.backButton.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor constant:12].active = YES;
    
    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshChannels];
}

- (void)viewDidChangeEffectiveAppearance {
    self.view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
}

- (void)refreshChannels {
    self.channels = [[SSBFeedStore sharedStore] allChannels];
    [self.tableView reloadData];
}

- (void)setChannels:(NSArray<NSString *> *)channels {
    self.channels = channels;
    [self.tableView reloadData];
}

- (void)backAction:(id)sender {
    if ([self.delegate respondsToSelector:@selector(channelBrowserDidRequestBack:)]) {
        [self.delegate channelBrowserDidRequestBack:self];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.channels.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ChannelCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        cell.identifier = @"ChannelCell";
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:tf];
        cell.textField = tf;
        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    cell.textField.stringValue = [@"#" stringByAppendingString:self.channels[row]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0) {
        if ([self.delegate respondsToSelector:@selector(channelBrowser:didSelectChannel:)]) {
            [self.delegate channelBrowser:self didSelectChannel:self.channels[row]];
        }
    }
}

@end
