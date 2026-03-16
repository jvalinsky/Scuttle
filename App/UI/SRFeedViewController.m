#import "SRFeedViewController.h"
#import "SRFeedItem.h"
#import "../../Sources/SSBLogger.h"
#import "../../Sources/SSBNetwork.h"
#import <SSBNetwork/SSBBlobStore.h>
#import "../Logic/SRNotificationNames.h"

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
    self.emptyLabel.alignment = NSTextAlignmentCenter;
    self.emptyLabel.maximumNumberOfLines = 0;
    self.emptyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.emptyLabel.preferredMaxLayoutWidth = 300;
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
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],
        
        [self.progressIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.progressIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    
    [self refreshFeed];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFeed) name:SRNewMessageNotification object:nil];
}

- (void)refreshFeed {
    NSString *filterAuthor = self.filterAuthor;
    NSString *filterChannel = self.filterChannel;
    NSString *filterSearch = self.filterSearch;
    SRFeedType feedType = self.feedType;
    BOOL hidesBackButton = self.hidesBackButton;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *newMessages = [NSMutableArray array];
        BOOL showBackButton = NO;

        if (filterAuthor) {
            [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] feedForAuthor:filterAuthor limit:50]];
            showBackButton = !hidesBackButton;
        } else if (filterChannel) {
            NSDictionary *query = @{@"path": @[@"content", @"channel"], @"op": @"eq", @"value": filterChannel};
            [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @YES, @"pageSize": @100}]];
            showBackButton = !hidesBackButton;
        } else if (filterSearch) {
            [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] searchMessages:filterSearch limit:100]];
            showBackButton = !hidesBackButton;
        } else {
            if (feedType == SRFeedTypeTimeline) {
                [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] timelineWithLimit:50]];
            } else {
                [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] recentMessagesWithLimit:50]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.messages = newMessages;
            strongSelf.emptyLabel.hidden = (newMessages.count > 0);
            strongSelf.backButton.hidden = !showBackButton;
            [strongSelf.collectionView reloadData];
            [strongSelf.progressIndicator stopAnimation:nil];
        });
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
    SSBLogInfo(SSBLogCategoryUI, @"📥 loadFeedForAuthor: %@ client=%@ connected=%d", 
               [author substringToIndex:MIN(8, author.length)], 
               client ? @"yes" : @"no", 
               client.isConnected);
    
    if (!client) {
        SSBLogError(SSBLogCategoryUI, @"   ❌ No client provided!");
        self.emptyLabel.stringValue = @"Not connected to server";
        self.emptyLabel.hidden = NO;
        return;
    }
    
    if (!client.isConnected) {
        SSBLogError(SSBLogCategoryUI, @"   ❌ Client not connected! Checking host: %@", client.host);
        self.emptyLabel.stringValue = @"Not connected to server";
        self.emptyLabel.hidden = NO;
        return;
    }
    
    self.filterAuthor = author;
    self.filterChannel = nil;
    self.currentClient = client;
    
    BOOL isFollowing = [[SSBFeedStore sharedStore] isFollowing:author];
    NSInteger limit = isFollowing ? 50 : 15;
    SSBLogInfo(SSBLogCategoryUI, @"   isFollowing=%d limit=%ld", isFollowing, (long)limit);
    
    [self refreshFeed];
    [self.progressIndicator startAnimation:nil];
    
    // Fetch profile (about)
    __weak typeof(self) weakSelf = self;
    [client fetchProfileForPeer:author completion:^(id _Nullable response, NSError * _Nullable error) {
        if (error) {
            SSBLogError(SSBLogCategoryUI, @"   ❌ Profile fetch error: %@", error.localizedDescription);
        } else if (response) {
            SSBLogInfo(SSBLogCategoryUI, @"   ✅ Profile fetched: %@", response);
            if ([response isKindOfClass:[NSDictionary class]]) {
                NSString *name = response[@"name"];
                NSString *image = response[@"image"];
                if ([name isKindOfClass:[NSString class]] || [image isKindOfClass:[NSString class]]) {
                    [[SSBFeedStore sharedStore] setDisplayName:name image:image forAuthor:author];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"SRProfileUpdatedNotification" object:author];
                        [weakSelf refreshFeed];
                    });
                }
            }
        } else {
            SSBLogWarning(SSBLogCategoryUI, @"   ⚠️ No profile response");
        }
    }];
    
    // Fetch history
    [client fetchFeedForPeer:author limit:limit completion:^(id _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.progressIndicator stopAnimation:nil];
        });
        
        if (error) {
            SSBLogError(SSBLogCategoryUI, @"   ❌ Feed fetch error: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *errStr = error.localizedDescription.lowercaseString;
                if ([errStr containsString:@"could not find"] || 
                    [errStr containsString:@"no messages"] || 
                    [errStr containsString:@"stream is closed"] || 
                    [errStr containsString:@"unexpected end"] ||
                    [errStr containsString:@"not connected"]) {
                    weakSelf.emptyLabel.stringValue = @"No messages found";
                } else {
                    weakSelf.emptyLabel.stringValue = [NSString stringWithFormat:@"Error loading feed:\n%@", error.localizedDescription];
                }
                weakSelf.emptyLabel.hidden = NO;
            });
        } else if (response && [response isKindOfClass:[NSDictionary class]]) {
            SSBLogInfo(SSBLogCategoryUI, @"   ✅ Feed fetched successfully");
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
        } else {
            SSBLogWarning(SSBLogCategoryUI, @"   ⚠️ No response (peer may have no messages)");
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.emptyLabel.stringValue = @"No messages found";
                weakSelf.emptyLabel.hidden = NO;
            });
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
    item.client = self.currentClient;
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
    
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    if (blobID) {
        NSString *localPath = [[SSBBlobStore sharedStore] localPathForBlobID:blobID];
        CGFloat imageHeight = 300;
        if (localPath) {
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:localPath];
            if (image && image.size.width > 0) {
                CGFloat maxWidth = width + 14;
                CGFloat aspectRatio = image.size.height / image.size.width;
                imageHeight = MIN(maxWidth * aspectRatio, 300);
            }
        }
        height += imageHeight + 16;
    }
    
    return NSMakeSize(collectionView.bounds.size.width - 40, height);
}

@end