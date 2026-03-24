#import "SRFeedViewController.h"
#import "SRFeedItem.h"
#import "SRStyle.h"
#import "SRKeyboardShortcuts.h"
#import "../../Sources/SSBLogger.h"
#import "../../Sources/SSBNetwork.h"
#import <SSBNetwork/SSBBlobStore.h>
#import "../Logic/SRNotificationNames.h"

@interface SRFeedViewController ()
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSCollectionViewDiffableDataSource<NSString *, NSString *> *dataSource;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBMessage *> *messagesByKey;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
/// Badge shown in the top-left when viewing a single author's feed that has been lipmaa-verified.
@property (nonatomic, strong) NSTextField *integrityBadge;
/// Set of author IDs whose feeds have passed lipmaa integrity checks.
@property (nonatomic, strong) NSMutableSet<NSString *> *verifiedAuthors;
@property (nonatomic, strong) NSMutableArray *observerTokens;
@end

@implementation SRFeedViewController

- (void)dealloc {
    // Remove block-based observers (stored as opaque tokens)
    for (id token in self.observerTokens) {
        [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
    // Remove target-action observers registered directly on self
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.view = self.scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.messagesByKey = [NSMutableDictionary dictionary];
    self.verifiedAuthors = [NSMutableSet set];
    self.observerTokens = [NSMutableArray array];

    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = [SRStyle spacingXL];
    layout.sectionInset = NSEdgeInsetsMake([SRStyle spacingXL], [SRStyle spacingXL], [SRStyle spacingXL], [SRStyle spacingXL]);

    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate = self;
    self.collectionView.selectable = YES;
    [self.collectionView registerClass:[SRFeedItem class] forItemWithIdentifier:@"FeedItem"];

    __weak typeof(self) weakSelf = self;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
                                                                 object:self.scrollView
                                                                  queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(NSNotification * _Nonnull note) {
        [weakSelf.collectionView.collectionViewLayout invalidateLayout];
    }];
    [self.observerTokens addObject:token];
    self.scrollView.postsBoundsChangedNotifications = YES;

    self.scrollView.documentView = self.collectionView;
    [self.collectionView setAccessibilityLabel:@"Feed"];
    [self.collectionView setAccessibilityRole:NSAccessibilityListRole];

    // Configure diffable data source — owns cell provision, no dataSource delegate needed.
    self.dataSource = [[NSCollectionViewDiffableDataSource alloc]
        initWithCollectionView:self.collectionView
                  itemProvider:^NSCollectionViewItem *(NSCollectionView *cv, NSIndexPath *ip, NSString *msgKey) {
                      SRFeedItem *item = [cv makeItemWithIdentifier:@"FeedItem" forIndexPath:ip];
                      item.client = weakSelf.currentClient;
                      item.representedObject = weakSelf.messagesByKey[msgKey];
                      item.owner = weakSelf;
                      return item;
                  }];

    self.backButton = [NSButton buttonWithTitle:@"Show All Messages" target:self action:@selector(showAllAction:)];
    self.backButton.toolTip = @"Clear feed filter and show all messages";
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

    // Integrity badge — shown when a GabbyGrove/Bamboo author's feed is lipmaa-verified.
    self.integrityBadge = [NSTextField labelWithString:@"Verified"];
    self.integrityBadge.font = [NSFont boldSystemFontOfSize:10];
    self.integrityBadge.textColor = [NSColor systemGreenColor];
    self.integrityBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.integrityBadge.hidden = YES;
    [self.view addSubview:self.integrityBadge];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],

        [self.progressIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.progressIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.integrityBadge.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:14],
        [self.integrityBadge.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20]
    ]];

    [self refreshFeed];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFeed) name:SRNewMessageNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(feedIntegrityDidUpdate:)
                                                 name:SRFeedIntegrityDidUpdateNotification
                                               object:nil];
}

- (void)feedIntegrityDidUpdate:(NSNotification *)note {
    NSString *author = note.userInfo[@"author"];
    BOOL verified = [note.userInfo[@"verified"] boolValue];
    if (verified) {
        [self.verifiedAuthors addObject:author];
    } else {
        [self.verifiedAuthors removeObject:author];
    }
    // Refresh the badge if we are currently showing this author's feed.
    if (self.filterAuthor && [self.filterAuthor isEqualToString:author]) {
        self.integrityBadge.stringValue = verified ? @"Verified" : @"Unverified";
        self.integrityBadge.textColor = verified ? [NSColor systemGreenColor] : [NSColor systemOrangeColor];
        self.integrityBadge.hidden = NO;
    }
}

#pragma mark - Data loading

- (void)refreshFeed {
    NSString *filterAuthor = self.filterAuthor;
    NSString *filterChannel = self.filterChannel;
    NSString *filterSearch = self.filterSearch;
    SRFeedType feedType = self.feedType;
    BOOL hidesBackButton = self.hidesBackButton;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<SSBMessage *> *newMessages = [NSMutableArray array];
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
            // Update the integrity badge for the displayed author.
            if (strongSelf.filterAuthor) {
                BOOL verified = [strongSelf.verifiedAuthors containsObject:strongSelf.filterAuthor];
                strongSelf.integrityBadge.stringValue = verified ? @"Verified" : @"Unverified";
                strongSelf.integrityBadge.textColor = verified ? [NSColor systemGreenColor] : [NSColor systemOrangeColor];
                strongSelf.integrityBadge.hidden = NO;
            } else {
                strongSelf.integrityBadge.hidden = YES;
            }
            [strongSelf applySnapshotWithMessages:newMessages];
            strongSelf.emptyLabel.hidden = (newMessages.count > 0);
            strongSelf.backButton.hidden = !showBackButton;
            [strongSelf.progressIndicator stopAnimation:nil];
        });
    });
}

- (void)setMessages:(NSArray<SSBMessage *> *)messages {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applySnapshotWithMessages:messages];
        self.emptyLabel.hidden = (messages.count > 0);
        [self.progressIndicator stopAnimation:nil];
    });
}

- (void)applySnapshotWithMessages:(NSArray<SSBMessage *> *)messages {
    [self.messagesByKey removeAllObjects];
    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [snapshot appendSectionsWithIdentifiers:@[@"main"]];
    
    NSMutableArray<NSString *> *msgKeys = [NSMutableArray array];
    for (SSBMessage *msg in messages) {
        self.messagesByKey[msg.key] = msg;
        [msgKeys addObject:msg.key];
    }
    [snapshot appendItemsWithIdentifiers:msgKeys intoSectionWithIdentifier:@"main"];
    [self.dataSource applySnapshot:snapshot animatingDifferences:YES];
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
    SSBLogInfo(SSBLogCategoryUI, @"loadFeedForAuthor: %@ client=%@ connected=%d",
               [author substringToIndex:MIN(8, author.length)],
               client ? @"yes" : @"no",
               client.isConnected);

    if (!client) {
        SSBLogError(SSBLogCategoryUI, @"   No client provided!");
        self.emptyLabel.stringValue = @"Not connected to server";
        self.emptyLabel.hidden = NO;
        return;
    }

    if (!client.isConnected) {
        SSBLogError(SSBLogCategoryUI, @"   Client not connected! Checking host: %@", client.host);
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
            SSBLogError(SSBLogCategoryUI, @"   Profile fetch error: %@", error.localizedDescription);
        } else if (response) {
            SSBLogInfo(SSBLogCategoryUI, @"   Profile fetched: %@", response);
            if ([response isKindOfClass:[NSDictionary class]]) {
                NSString *name = response[@"name"];
                NSString *image = response[@"image"];
                if ([name isKindOfClass:[NSString class]] || [image isKindOfClass:[NSString class]]) {
                    [[SSBFeedStore sharedStore] setDisplayName:name image:image forAuthor:author];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:SRProfileUpdatedNotification object:author];
                        [weakSelf refreshFeed];
                    });
                }
            }
        } else {
            SSBLogWarning(SSBLogCategoryUI, @"   No profile response");
        }
    }];

    // Fetch history
    [client fetchFeedForPeer:author limit:limit completion:^(id _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.progressIndicator stopAnimation:nil];
        });

        if (error) {
            SSBLogError(SSBLogCategoryUI, @"   Feed fetch error: %@", error.localizedDescription);
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
            SSBLogInfo(SSBLogCategoryUI, @"   Feed fetched successfully");
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
            SSBLogWarning(SSBLogCategoryUI, @"   No response (peer may have no messages)");
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

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath) return;
    NSString *msgKey = [self.dataSource itemIdentifierForIndexPath:indexPath];
    SSBMessage *msg = self.messagesByKey[msgKey];
    if (msg && [self.delegate respondsToSelector:@selector(feedViewController:didSelectMessageThread:)]) {
        [self.delegate feedViewController:self didSelectMessageThread:msg];
    }
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
    NSString *msgKey = [self.dataSource itemIdentifierForIndexPath:indexPath];
    SSBMessage *msg = self.messagesByKey[msgKey];
    if (!msg) return NSMakeSize(collectionView.bounds.size.width - 40, 120);

    NSString *text = msg.content[@"text"] ?: @"(No text)";

    CGFloat width = collectionView.bounds.size.width - 80; // 20 section inset * 2 + cell padding etc
    if (width < 100) width = 100;

    NSRect rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];

    CGFloat height = ceil(rect.size.height) + 100; // padding for avatar, buttons, and display name
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

#pragma mark - Keyboard navigation (J/K/L/R)

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
    if (chars.length == 0) { [super keyDown:event]; return; }

    unichar ch = [chars characterAtIndex:0];
    NSInteger itemCount = (NSInteger)[self.dataSource snapshot].numberOfItems;
    if (itemCount == 0) { [super keyDown:event]; return; }

    NSIndexPath *current = self.collectionView.selectionIndexPaths.anyObject;
    NSInteger idx = current ? (NSInteger)current.item : -1;

    if (ch == SRFeedShortcutNextItem) {
        [self moveFocusToIndex:MIN(idx + 1, itemCount - 1)];
    } else if (ch == SRFeedShortcutPrevItem) {
        [self moveFocusToIndex:MAX(idx - 1, 0)];
    } else if ((ch == SRFeedShortcutLike || ch == SRFeedShortcutReply || ch == SRFeedShortcutOpen) && idx >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForItem:idx inSection:0];
        NSString *key = [self.dataSource itemIdentifierForIndexPath:ip];
        SSBMessage *msg = self.messagesByKey[key];
        if (!msg) { [super keyDown:event]; return; }

        if (ch == SRFeedShortcutLike) {
            if ([self.delegate respondsToSelector:@selector(feedViewController:didLikeMessage:)]) {
                [self.delegate feedViewController:self didLikeMessage:msg];
            }
        } else {
            if ([self.delegate respondsToSelector:@selector(feedViewController:didSelectMessageThread:)]) {
                [self.delegate feedViewController:self didSelectMessageThread:msg];
            }
        }
    } else {
        [super keyDown:event];
    }
}

- (void)moveFocusToIndex:(NSInteger)idx {
    if (idx < 0) return;
    NSIndexPath *ip = [NSIndexPath indexPathForItem:idx inSection:0];
    [self.collectionView selectItemsAtIndexPaths:[NSSet setWithObject:ip]
                                 scrollPosition:NSCollectionViewScrollPositionNearestHorizontalEdge];
    [self.collectionView scrollToItemsAtIndexPaths:[NSSet setWithObject:ip]
                                    scrollPosition:NSCollectionViewScrollPositionNearestHorizontalEdge];
}

@end
