#import "SRGitFileTreeViewController.h"
#import "../../Sources/SSBGitObjectStore.h"

@interface SRGitFileTreeItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *sha1;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, strong, nullable) NSArray<SRGitFileTreeItem *> *children;
@end

@implementation SRGitFileTreeItem
@end

@interface SRGitFileTreeViewController ()
@property (nonatomic, strong) NSPopUpButton *branchPicker;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSArray<SRGitFileTreeItem *> *rootItems;
@end

@implementation SRGitFileTreeViewController

- (instancetype)initWithRepo:(SSBGitRepo *)repo {
    if ((self = [super init])) {
        _repo = repo;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self loadBranches];
}

- (void)setupUI {
    self.branchPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.branchPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.branchPicker.target = self;
    self.branchPicker.action = @selector(branchChanged:);
    [self.view addSubview:self.branchPicker];
    
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.outlineView = [[NSOutlineView alloc] init];
    self.outlineView.delegate = self;
    self.outlineView.dataSource = self;
    self.outlineView.headerView = nil;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"FileColumn"];
    [self.outlineView addTableColumn:column];
    self.outlineView.outlineTableColumn = column;
    
    self.scrollView.documentView = self.outlineView;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.branchPicker.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.branchPicker.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.branchPicker.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.branchPicker.bottomAnchor constant:10],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)loadBranches {
    NSDictionary *refs = [self.repo currentRefs];
    [self.branchPicker removeAllItems];
    
    for (NSString *ref in [refs.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [self.branchPicker addItemWithTitle:ref];
    }
    
    if (self.branchPicker.numberOfItems > 0) {
        [self.branchPicker selectItemAtIndex:0];
        [self branchChanged:self.branchPicker];
    }
}

- (void)branchChanged:(id)sender {
    NSString *ref = self.branchPicker.selectedItem.title;
    NSString *sha1 = [self.repo currentRefs][ref];
    if (sha1) {
        [self loadTreeForCommit:sha1];
    }
}

- (void)loadTreeForCommit:(NSString *)commitSha1 {
    SSBGitObject *commitObj = [self.repo.objectStore objectForSHA1:commitSha1];
    if (commitObj && commitObj.type == SSBGitObjectTypeCommit) {
        // Parse commit to find tree SHA1
        // Commit format: "tree <sha1>\nparent <sha1>\n..."
        NSString *content = [[NSString alloc] initWithData:commitObj.data encoding:NSUTF8StringEncoding];
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        if (lines.count > 0 && [lines[0] hasPrefix:@"tree "]) {
            NSString *treeSha1 = [lines[0] substringFromIndex:5];
            [self loadRootTree:treeSha1];
        }
    }
}

- (void)loadRootTree:(NSString *)treeSha1 {
    self.rootItems = [self itemsForTreeSHA1:treeSha1];
    [self.outlineView reloadData];
}

- (NSArray<SRGitFileTreeItem *> *)itemsForTreeSHA1:(NSString *)treeSha1 {
    SSBGitObject *treeObj = [self.repo.objectStore objectForSHA1:treeSha1];
    if (!treeObj || treeObj.type != SSBGitObjectTypeTree) return @[];
    
    NSMutableArray *items = [NSMutableArray array];
    NSData *data = treeObj.data;
    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    NSUInteger offset = 0;
    
    while (offset < len) {
        // Mode (space) Name (null) 20-byte binary SHA1
        NSUInteger spaceIdx = offset;
        while (spaceIdx < len && bytes[spaceIdx] != ' ') spaceIdx++;
        if (spaceIdx >= len) break;
        
        NSString *mode = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(offset, spaceIdx - offset)] encoding:NSUTF8StringEncoding];
        offset = spaceIdx + 1;
        
        NSUInteger nullIdx = offset;
        while (nullIdx < len && bytes[nullIdx] != 0) nullIdx++;
        if (nullIdx >= len) break;
        
        NSString *name = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(offset, nullIdx - offset)] encoding:NSUTF8StringEncoding];
        offset = nullIdx + 1;
        
        if (offset + 20 > len) break;
        NSData *sha1Data = [data subdataWithRange:NSMakeRange(offset, 20)];
        offset += 20;
        
        NSMutableString *hex = [NSMutableString stringWithCapacity:40];
        const uint8_t *shaBytes = sha1Data.bytes;
        for (int i = 0; i < 20; i++) [hex appendFormat:@"%02x", shaBytes[i]];
        
        SRGitFileTreeItem *item = [[SRGitFileTreeItem alloc] init];
        item.name = name;
        item.sha1 = hex;
        item.isDirectory = [mode hasPrefix:@"40"]; // 40000 for directory
        [items addObject:item];
    }
    
    return [items sortedArrayUsingComparator:^NSComparisonResult(SRGitFileTreeItem *obj1, SRGitFileTreeItem *obj2) {
        if (obj1.isDirectory != obj2.isDirectory) {
            return obj1.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        return [obj1.name compare:obj2.name];
    }];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (item == nil) return self.rootItems.count;
    SRGitFileTreeItem *treeItem = (SRGitFileTreeItem *)item;
    if (!treeItem.isDirectory) return 0;
    
    if (treeItem.children == nil) {
        treeItem.children = [self itemsForTreeSHA1:treeItem.sha1];
    }
    return treeItem.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (item == nil) return self.rootItems[index];
    SRGitFileTreeItem *treeItem = (SRGitFileTreeItem *)item;
    return treeItem.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    SRGitFileTreeItem *treeItem = (SRGitFileTreeItem *)item;
    return treeItem.isDirectory;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [self.outlineView selectedRow];
    if (row < 0) return;
    
    SRGitFileTreeItem *item = [self.outlineView itemAtRow:row];
    if (!item.isDirectory) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitFileSelectedNotification"
                                                            object:nil
                                                          userInfo:@{
                                                              @"sha1": item.sha1,
                                                              @"name": item.name
                                                          }];
    }
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"FileCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
        cell.identifier = @"FileCell";
        
        NSImageView *iv = [[NSImageView alloc] init];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:iv];
        cell.imageView = iv;
        
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:tf];
        cell.textField = tf;
        
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16],
            [iv.heightAnchor constraintEqualToConstant:16],
            
            [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    
    SRGitFileTreeItem *treeItem = (SRGitFileTreeItem *)item;
    cell.textField.stringValue = treeItem.name;
    
    if (treeItem.isDirectory) {
        cell.imageView.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil];
    } else {
        cell.imageView.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    }
    
    return cell;
}

@end
