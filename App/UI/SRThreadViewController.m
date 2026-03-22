#import "SRThreadViewController.h"
#import "SRFeedItem.h"
#import "SRStyle.h"
#import "SRNotificationBannerView.h"
#import "../Logic/SRNotificationNames.h"
#import <SSBNetwork/SSBThread.h>
#import <SSBNetwork/SSBBlobStore.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBMessageCodec.h>

@interface SRThreadViewController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSCollectionViewDiffableDataSource<NSString *, NSString *> *dataSource;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBMessage *> *messagesByKey;
@property (nonatomic, strong) NSArray<SSBMessage *> *threadMessages;

// Back button
@property (nonatomic, strong) NSButton *backButton;

// Inline reply compose bar
@property (nonatomic, strong) NSView *composeBar;
@property (nonatomic, strong) NSTextField *composeField;
@property (nonatomic, strong) NSButton *sendButton;

@end

@implementation SRThreadViewController

- (instancetype)initWithRootMessage:(SSBMessage *)message client:(nullable SSBRoomClient *)client {
    self = [super init];
    if (self) {
        _rootMessage = message;
        _client = client;
        _messagesByKey = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)loadView {
    NSView *container = [[NSView alloc] init];

    // Back button
    self.backButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left"
                                                           accessibilityDescription:@"Back"]
                                         target:self
                                         action:@selector(backAction:)];
    self.backButton.bezelStyle = NSBezelStyleRegularSquare;
    self.backButton.bordered = NO;
    self.backButton.wantsLayer = YES;
    self.backButton.layer.backgroundColor = [[NSColor controlColor] colorWithAlphaComponent:0.5].CGColor;
    self.backButton.layer.cornerRadius = 14;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backButton setAccessibilityLabel:@"Back to feed"];
    [container addSubview:self.backButton];

    // Scroll view + collection view
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.scrollView];

    // Inline compose bar
    self.composeBar = [[NSView alloc] init];
    self.composeBar.wantsLayer = YES;
    self.composeBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    self.composeBar.layer.borderWidth = 1;
    self.composeBar.layer.borderColor = [NSColor separatorColor].CGColor;
    self.composeBar.layer.cornerRadius = [SRStyle cornerRadiusMedium];
    self.composeBar.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.composeBar];

    self.composeField = [[NSTextField alloc] init];
    self.composeField.placeholderString = NSLocalizedString(@"Reply…", nil);
    self.composeField.translatesAutoresizingMaskIntoConstraints = NO;
    self.composeField.bordered = NO;
    self.composeField.backgroundColor = [NSColor clearColor];
    self.composeField.font = [SRStyle bodyFont];
    self.composeField.delegate = self;
    [self.composeField setAccessibilityLabel:@"Reply text"];
    [self.composeBar addSubview:self.composeField];

    self.sendButton = [NSButton buttonWithTitle:NSLocalizedString(@"Send", nil)
                                         target:self
                                         action:@selector(sendReply:)];
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.controlSize = NSControlSizeSmall;
    self.sendButton.keyEquivalent = @"\r";
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton setAccessibilityLabel:@"Send reply"];
    [self.composeBar addSubview:self.sendButton];

    [NSLayoutConstraint activateConstraints:@[
        // Back button
        [self.backButton.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [self.backButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [self.backButton.widthAnchor constraintEqualToConstant:28],
        [self.backButton.heightAnchor constraintEqualToConstant:28],

        // Compose bar at bottom
        [self.composeBar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:[SRStyle spacingLG]],
        [self.composeBar.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-[SRStyle spacingLG]],
        [self.composeBar.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-[SRStyle spacingLG]],
        [self.composeBar.heightAnchor constraintEqualToConstant:40],

        // Compose field inside bar
        [self.composeField.leadingAnchor constraintEqualToAnchor:self.composeBar.leadingAnchor constant:10],
        [self.composeField.centerYAnchor constraintEqualToAnchor:self.composeBar.centerYAnchor],
        [self.composeField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-8],

        // Send button inside bar
        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.composeBar.trailingAnchor constant:-8],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.composeBar.centerYAnchor],

        // Scroll view fills between back button and compose bar
        [self.scrollView.topAnchor constraintEqualToAnchor:self.backButton.bottomAnchor constant:12],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.composeBar.topAnchor constant:-8],
    ]];

    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8;
    layout.sectionInset = NSEdgeInsetsMake(12, 12, 12, 12);

    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[SRFeedItem class] forItemWithIdentifier:@"ThreadItem"];

    __weak typeof(self) weakSelf = self;
    self.dataSource = [[NSCollectionViewDiffableDataSource alloc]
                       initWithCollectionView:self.collectionView
                       itemProvider:^NSCollectionViewItem *(NSCollectionView *cv, NSIndexPath *ip, NSString *key) {
        SRFeedItem *item = [cv makeItemWithIdentifier:@"ThreadItem" forIndexPath:ip];
        item.representedObject = weakSelf.messagesByKey[key];
        item.client = weakSelf.client;
        item.owner = weakSelf;
        item.isReply = (ip.item > 0);
        return item;
    }];

    self.scrollView.documentView = self.collectionView;

    [self loadThread];

    // Refresh thread when new messages arrive
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNewMessage:)
                                                 name:SRNewMessageNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadThread {
    NSDictionary *query = @{@"path": @[@"content", @"root"], @"op": @"eq", @"value": self.rootMessage.key};
    NSArray *replies = [[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @NO}];

    NSMutableArray *allMessages = [NSMutableArray arrayWithObject:self.rootMessage];
    [allMessages addObjectsFromArray:replies];

    SSBThread *thread = [[SSBThread alloc] initWithRoot:self.rootMessage messages:allMessages];
    NSArray<SSBMessage *> *linearized = [thread linearize];

    NSMutableDictionary *byKey = [NSMutableDictionary dictionaryWithCapacity:linearized.count];
    for (SSBMessage *msg in linearized) {
        byKey[msg.key] = msg;
    }
    self.messagesByKey = byKey;
    self.threadMessages = linearized;

    NSArray<NSString *> *keys = [linearized valueForKey:@"key"];

    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [snapshot appendSectionsWithIdentifiers:@[@"main"]];
    [snapshot appendItemsWithIdentifiers:keys intoSectionWithIdentifier:@"main"];
    [self.dataSource applySnapshot:snapshot animatingDifferences:YES];
}

- (void)handleNewMessage:(NSNotification *)note {
    // Reload if the new message references our root thread
    SSBMessage *msg = note.object;
    if ([msg isKindOfClass:[SSBMessage class]]) {
        NSString *root = msg.content[@"root"];
        if ([root isEqualToString:self.rootMessage.key] ||
            [msg.key isEqualToString:self.rootMessage.key]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self loadThread];
            });
        }
    }
}

#pragma mark - Actions

- (void)backAction:(id)sender {
    if ([self.delegate respondsToSelector:@selector(threadViewControllerDidRequestBack:)]) {
        [self.delegate threadViewControllerDidRequestBack:self];
    }
}

- (void)sendReply:(id)sender {
    NSString *text = [self.composeField.stringValue
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) return;
    if (!self.client) {
        [SRNotificationBannerView showInView:self.view message:NSLocalizedString(@"Not connected to a room", nil) type:SRNotificationTypeWarning];
        return;
    }

    // Disable while sending
    self.sendButton.enabled = NO;
    self.composeField.enabled = NO;

    NSString *rootKey = self.rootMessage.key;
    NSString *branchKey = self.threadMessages.lastObject.key ?: rootKey;
    NSDictionary *content = [SSBMessageCodec replyContentWithText:text
                                                             root:rootKey
                                                           branch:branchKey
                                                          channel:nil
                                                   contentWarning:nil
                                                         mentions:nil
                                                            recps:nil];

    [self.client publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.sendButton.enabled = YES;
            self.composeField.enabled = YES;
            if (error) {
                [SRNotificationBannerView showInView:self.view
                                            message:error.localizedDescription
                                               type:SRNotificationTypeError];
            } else {
                self.composeField.stringValue = @"";
                [[NSNotificationCenter defaultCenter] postNotificationName:SRNewMessageNotification object:msg];
            }
        });
    }];
}

#pragma mark - SRFeedItemOwner

- (void)itemDidRequestLike:(SRFeedItem *)item {
    SSBMessage *msg = (SSBMessage *)item.representedObject;
    if ([self.delegate respondsToSelector:@selector(threadViewController:didLikeMessage:)]) {
        [self.delegate threadViewController:self didLikeMessage:msg];
    }
}

- (void)itemDidRequestReply:(SRFeedItem *)item {
    // Focus inline compose, pre-select context
    [self.view.window makeFirstResponder:self.composeField];
}

#pragma mark - NSCollectionViewDelegateFlowLayout

- (NSSize)collectionView:(NSCollectionView *)collectionView
                  layout:(NSCollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *key = [self.dataSource itemIdentifierForIndexPath:indexPath];
    SSBMessage *msg = self.messagesByKey[key];
    NSString *text = msg.content[@"text"] ?: @"(No text)";

    CGFloat width = collectionView.bounds.size.width - 120;
    if (width < 100) width = 100;

    NSRect rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];

    CGFloat height = ceil(rect.size.height) + 80;
    if (height < 100) height = 100;

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

    return NSMakeSize(collectionView.bounds.size.width - 24, height);
}

@end
