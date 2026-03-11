#import "SRFeedViewController.h"
#import "SRFeedItem.h"
#import "../../Sources/SSBNetwork.h"

@interface SRFeedViewController () <NSCollectionViewDelegateFlowLayout>
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSArray<SSBMessage *> *messages;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
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
    
    self.backButton = [NSButton buttonWithTitle:@"Show All Messages" target:self action:@selector(showAllAction:)];
    self.backButton.bezelStyle = NSBezelStyleRounded;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.backButton.hidden = YES;
    [self.view addSubview:self.backButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.backButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20]
    ]];
    
    self.emptyLabel = [NSTextField labelWithString:@"No messages found"];
    self.emptyLabel.font = [NSFont systemFontOfSize:16];
    self.emptyLabel.textColor = [NSColor tertiaryLabelColor];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    
    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.controlSize = NSControlSizeRegular;
    self.progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.view addSubview:self.progressIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        
        [self.progressIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.progressIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    
    [self refreshFeed];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFeed) name:@"SRNewMessageNotification" object:nil];
}

- (void)refreshFeed {
    NSMutableArray *newMessages = [NSMutableArray array];
    
    if (self.filterAuthor) {
        [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] feedForAuthor:self.filterAuthor limit:50]];
        self.backButton.hidden = NO;
    } else if (self.filterChannel) {
        NSDictionary *query = @{@"path": @[@"content", @"channel"], @"op": @"eq", @"value": self.filterChannel};
        [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @YES, @"pageSize": @100}]];
        self.backButton.hidden = NO;
    } else if (self.filterSearch) {
        [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] searchMessages:self.filterSearch limit:100]];
        self.backButton.hidden = NO;
    } else {
        if (self.feedType == SRFeedTypeTimeline) {
            [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] timelineWithLimit:50]];
        } else {
            [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] recentMessagesWithLimit:50]];
        }
        self.backButton.hidden = YES;
    }
    
    self.messages = newMessages;
    self.emptyLabel.hidden = (newMessages.count > 0);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

- (void)loadFeedForChannel:(NSString *)channel {
    self.filterChannel = channel;
    self.filterAuthor = nil;
    self.filterSearch = nil;
    [self refreshFeed];
}

- (void)loadFeedWithSearch:(NSString *)searchText {
    self.filterSearch = searchText;
    self.filterAuthor = nil;
    self.filterChannel = nil;
    [self refreshFeed];
}

- (void)showAllAction:(id)sender {
    self.filterAuthor = nil;
    self.filterChannel = nil;
    [self refreshFeed];
}

- (void)loadFeedForAuthor:(NSString *)author client:(SSBRoomClient *)client {
    self.filterAuthor = author;
    self.filterChannel = nil;
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

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath && indexPath.item < self.messages.count) {
        SSBMessage *msg = self.messages[indexPath.item];
        if ([self.delegate respondsToSelector:@selector(feedViewController:didSelectMessageThread:)]) {
            [self.delegate feedViewController:self didSelectMessageThread:msg];
        }
    }
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.messages.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    SRFeedItem *item = [collectionView makeItemWithIdentifier:@"FeedItem" forIndexPath:indexPath];
    item.representedObject = self.messages[indexPath.item];
    item.owner = self;
    return item;
}

- (void)itemDidRequestLike:(SRFeedItem *)item {
    SSBMessage *msg = (SSBMessage *)item.representedObject;
    if ([self.delegate respondsToSelector:@selector(feedViewController:didLikeMessage:)]) {
        [self.delegate feedViewController:self didLikeMessage:msg];
    }
}

- (void)itemDidRequestReply:(SRFeedItem *)item {
    SSBMessage *msg = (SSBMessage *)item.representedObject;
    if ([self.delegate respondsToSelector:@selector(feedViewController:didReplyToMessage:)]) {
        [self.delegate feedViewController:self didReplyToMessage:msg];
    }
}

#pragma mark - NSCollectionViewDelegateFlowLayout

- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    SSBMessage *msg = self.messages[indexPath.item];
    NSString *text = msg.content[@"text"] ?: @"(No text)";
    
    CGFloat width = collectionView.bounds.size.width - 80; // 20 section inset * 2 + cell padding etc
    if (width < 100) width = 100;
    
    NSRect rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];
    
    CGFloat height = ceil(rect.size.height) + 100; // More padding for avatar, buttons, and display name
    if (height < 120) height = 120;
    
    return NSMakeSize(collectionView.bounds.size.width - 40, height);
}

@end