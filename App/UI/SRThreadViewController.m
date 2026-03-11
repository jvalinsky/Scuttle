#import "SRThreadViewController.h"
#import "SRFeedViewController.h"
#import "SRFeedItem.h"
#import <SSBNetwork/SSBThread.h>

@interface SRThreadViewController ()
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSArray<SSBMessage *> *threadMessages;
@property (nonatomic, strong) NSButton *backButton;
@end

@implementation SRThreadViewController

- (instancetype)initWithRootMessage:(SSBMessage *)message {
    self = [super init];
    if (self) {
        _rootMessage = message;
    }
    return self;
}

- (void)loadView {
    NSView *container = [[NSView alloc] init];
    
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.scrollView];
    
    self.backButton = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarGoBackTemplate] target:self action:@selector(backAction:)];
    self.backButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.backButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backButton.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [self.backButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.backButton.bottomAnchor constant:12],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    
    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8;
    layout.sectionInset = NSEdgeInsetsMake(12, 40, 40, 40); // Indent replies?
    
    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.collectionView registerClass:[SRFeedItem class] forItemWithIdentifier:@"ThreadItem"];
    
    self.scrollView.documentView = self.collectionView;
    
    [self loadThread];
}

- (void)loadThread {
    NSDictionary *query = @{@"path": @[@"content", @"root"], @"op": @"eq", @"value": self.rootMessage.key};
    NSArray *replies = [[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @NO}];
    
    NSMutableArray *allMessages = [NSMutableArray arrayWithObject:self.rootMessage];
    [allMessages addObjectsFromArray:replies];
    
    // Use SSBThread to linearize
    SSBThread *thread = [[SSBThread alloc] initWithRoot:self.rootMessage messages:allMessages];
    self.threadMessages = [thread linearize];
    
    [self.collectionView reloadData];
}

- (void)backAction:(id)sender {
    if ([self.delegate respondsToSelector:@selector(threadViewControllerDidRequestBack:)]) {
        [self.delegate threadViewControllerDidRequestBack:self];
    }
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.threadMessages.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    SRFeedItem *item = [collectionView makeItemWithIdentifier:@"ThreadItem" forIndexPath:indexPath];
    item.representedObject = self.threadMessages[indexPath.item];
    item.owner = self;
    return item;
}

- (void)itemDidRequestLike:(SRFeedItem *)item {
    SSBMessage *msg = (SSBMessage *)item.representedObject;
    if ([self.delegate respondsToSelector:@selector(threadViewController:didLikeMessage:)]) {
        [self.delegate threadViewController:self didLikeMessage:msg];
    }
}

- (void)itemDidRequestReply:(SRFeedItem *)item {
    SSBMessage *msg = (SSBMessage *)item.representedObject;
    if ([self.delegate respondsToSelector:@selector(threadViewController:didReplyToMessage:)]) {
        [self.delegate threadViewController:self didReplyToMessage:msg];
    }
}

#pragma mark - NSCollectionViewDelegateFlowLayout

- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    SSBMessage *msg = self.threadMessages[indexPath.item];
    NSString *text = msg.content[@"text"] ?: @"(No text)";
    
    CGFloat width = collectionView.bounds.size.width - 120; // Extra padding for thread view
    if (width < 100) width = 100;
    
    NSRect rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];
    
    CGFloat height = ceil(rect.size.height) + 80;
    if (height < 100) height = 100;
    
    return NSMakeSize(collectionView.bounds.size.width - 80, height);
}

@end
