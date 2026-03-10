#import "SRFeedViewController.h"
#import "../../Sources/SSBNetwork.h"

@interface SRFeedItem : NSCollectionViewItem
@property (nonatomic, strong) NSTextField *authorLabel;
@property (nonatomic, strong) NSTextField *contentLabel;
@property (nonatomic, strong) NSTextField *cwLabel;
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSButton *showCWButton;
@property (nonatomic, strong) NSButton *replyButton;
@property (nonatomic, strong) NSButton *likeButton;
@end

@implementation SRFeedItem

- (void)loadView {
    self.view = [[NSView alloc] init];
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    self.view.layer.cornerRadius = 8;
    self.view.layer.borderWidth = 1;
    self.view.layer.borderColor = [NSColor separatorColor].CGColor;
    
    _avatarView = [[NSView alloc] init];
    _avatarView.wantsLayer = YES;
    _avatarView.layer.cornerRadius = 16;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_avatarView];
    
    _authorLabel = [NSTextField labelWithString:@""];
    _authorLabel.font = [NSFont boldSystemFontOfSize:12];
    _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_authorLabel];
    
    _cwLabel = [NSTextField labelWithString:@""];
    _cwLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    _cwLabel.textColor = [NSColor systemOrangeColor];
    _cwLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _cwLabel.hidden = YES;
    [self.view addSubview:_cwLabel];
    
    _showCWButton = [NSButton buttonWithTitle:@"Show Content" target:self action:@selector(toggleCW:)];
    _showCWButton.bezelStyle = NSBezelStyleInline;
    _showCWButton.controlSize = NSControlSizeSmall;
    _showCWButton.translatesAutoresizingMaskIntoConstraints = NO;
    _showCWButton.hidden = YES;
    [self.view addSubview:_showCWButton];
    
    _contentLabel = [NSTextField labelWithString:@""];
    _contentLabel.font = [NSFont systemFontOfSize:13];
    _contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _contentLabel.maximumNumberOfLines = 0;
    _contentLabel.cell.lineBreakMode = NSLineBreakByWordWrapping;
    [self.view addSubview:_contentLabel];
    
    _replyButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrowshape.turn.up.left" accessibilityDescription:@"Reply"] target:self action:@selector(replyAction:)];
    _replyButton.bordered = NO;
    _replyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_replyButton];
    
    _likeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"heart" accessibilityDescription:@"Like"] target:self action:@selector(likeAction:)];
    _likeButton.bordered = NO;
    _likeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_likeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_avatarView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [_avatarView.widthAnchor constraintEqualToConstant:32],
        [_avatarView.heightAnchor constraintEqualToConstant:32],
        
        [_authorLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:10],
        [_authorLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [_authorLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        
        [_cwLabel.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_cwLabel.topAnchor constraintEqualToAnchor:_authorLabel.bottomAnchor constant:4],
        
        [_showCWButton.leadingAnchor constraintEqualToAnchor:_cwLabel.trailingAnchor constant:8],
        [_showCWButton.centerYAnchor constraintEqualToAnchor:_cwLabel.centerYAnchor],
        
        [_contentLabel.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_contentLabel.topAnchor constraintEqualToAnchor:_authorLabel.bottomAnchor constant:4], // Will adjust if CW shown
        [_contentLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [_contentLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-32],
        
        [_replyButton.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_replyButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        
        [_likeButton.leadingAnchor constraintEqualToAnchor:_replyButton.trailingAnchor constant:16],
        [_likeButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]
    ]];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    if ([representedObject isKindOfClass:[SSBMessage class]]) {
        SSBMessage *msg = (SSBMessage *)representedObject;
        self.authorLabel.stringValue = msg.author;
        
        NSString *cw = msg.content[@"contentWarning"];
        if (cw.length > 0) {
            self.cwLabel.stringValue = [NSString stringWithFormat:@"CW: %@", cw];
            self.cwLabel.hidden = NO;
            self.showCWButton.hidden = NO;
            self.contentLabel.hidden = YES;
        } else {
            self.cwLabel.hidden = YES;
            self.showCWButton.hidden = YES;
            self.contentLabel.hidden = NO;
            self.contentLabel.stringValue = msg.content[@"text"] ?: @"(No text)";
        }
        
        NSUInteger hash = [msg.author hash];
        self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
    }
}

- (void)toggleCW:(id)sender {
    SSBMessage *msg = (SSBMessage *)self.representedObject;
    self.contentLabel.stringValue = msg.content[@"text"] ?: @"(No text)";
    self.contentLabel.hidden = NO;
    self.showCWButton.hidden = YES;
}

- (void)replyAction:(id)sender {
    // Notify delegate
}

- (void)likeAction:(id)sender {
    // Notify delegate
}

@end

@interface SRFeedViewController ()
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSArray<SSBMessage *> *messages;
@end

@implementation SRFeedViewController

- (void)loadView {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.view = self.scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12;
    layout.sectionInset = NSEdgeInsetsMake(20, 20, 20, 20);
    
    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.selectable = YES;
    [self.collectionView registerClass:[SRFeedItem class] forItemWithIdentifier:@"FeedItem"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(viewDidResize:) 
                                                 name:NSViewFrameDidChangeNotification 
                                               object:self.scrollView];
    self.scrollView.postsBoundsChangedNotifications = YES;
    
    self.scrollView.documentView = self.collectionView;
    
    [self refreshFeed];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFeed) name:@"SRNewMessageNotification" object:nil];
}

- (void)refreshFeed {
    if (self.filterAuthor) {
        self.messages = [[SSBFeedStore sharedStore] feedForAuthor:self.filterAuthor limit:100];
    } else {
        self.messages = [[SSBFeedStore sharedStore] recentMessagesWithLimit:100];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

- (void)loadFeedForAuthor:(NSString *)author client:(SSBRoomClient *)client {
    self.filterAuthor = author;
    [self refreshFeed];
    
    // Fetch profile (about)
    [client fetchProfileForPeer:author completion:^(id _Nullable response, NSError * _Nullable error) {
        if (!error && [response isKindOfClass:[NSDictionary class]]) {
            // Room servers sometimes return just the about msg or a list
            // For now we just log it, but ideally we'd update a profile view
            NSLog(@"[FeedVC] Profile for %@: %@", author, response);
        }
    }];
    
    // Fetch history
    __weak typeof(self) weakSelf = self;
    [client fetchFeedForPeer:author limit:50 completion:^(id _Nullable response, NSError * _Nullable error) {
        if (!error && [response isKindOfClass:[NSDictionary class]]) {
            NSDictionary *val = response[@"value"];
            if ([SSBMessageCodec verifyMessage:val]) {
                SSBMessage *msg = [[SSBMessage alloc] init];
                msg.key = response[@"key"];
                msg.author = val[@"author"];
                msg.sequence = [val[@"sequence"] integerValue];
                msg.content = val[@"content"];
                msg.valueJSON = [SSBMessageCodec encodeLegacyValue:val includeSignature:YES];
                
                [[SSBFeedStore sharedStore] appendMessage:msg error:nil];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf refreshFeed];
                });
            }
        }
    }];
}

- (void)viewDidResize:(NSNotification *)notification {
    [self.collectionView.collectionViewLayout invalidateLayout];
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.messages.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    SRFeedItem *item = [collectionView makeItemWithIdentifier:@"FeedItem" forIndexPath:indexPath];
    item.representedObject = self.messages[indexPath.item];
    return item;
}

#pragma mark - NSCollectionViewDelegateFlowLayout

- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return NSMakeSize(collectionView.bounds.size.width - 40, 100); // Dynamic height would be better
}

@end