#import "SRProfileHeaderView.h"
#import "../Logic/SRRoomManager.h"

@interface SRProfileHeaderView ()
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *idLabel;
@property (nonatomic, strong) NSButton *profileButton;
@property (nonatomic, copy) NSString *feedId;
@end

@implementation SRProfileHeaderView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
        [self loadLocalIdentity];
    }
    return self;
}

- (void)setupUI {
    _avatarView = [[NSView alloc] init];
    _avatarView.wantsLayer = YES;
    _avatarView.layer.cornerRadius = 16;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_avatarView];

    _nameLabel = [NSTextField labelWithString:@""];
    _nameLabel.font = [NSFont boldSystemFontOfSize:13];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_nameLabel];

    _idLabel = [NSTextField labelWithString:@""];
    _idLabel.font = [NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightRegular];
    _idLabel.textColor = [NSColor secondaryLabelColor];
    _idLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _idLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self addSubview:_idLabel];

    _profileButton = [NSButton buttonWithTitle:@"Set Profile" target:self action:@selector(setProfileAction:)];
    _profileButton.bezelStyle = NSBezelStyleInline;
    _profileButton.controlSize = NSControlSizeSmall;
    _profileButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_profileButton];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:32],
        [_avatarView.heightAnchor constraintEqualToConstant:32],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:8],
        [_nameLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:_profileButton.leadingAnchor constant:-4],

        [_idLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_idLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
        [_idLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

        [_profileButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_profileButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [self.heightAnchor constraintEqualToConstant:56]
    ]];
}

- (void)loadLocalIdentity {
    NSData *savedIdentity = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
    if (savedIdentity && savedIdentity.length >= 64) {
        NSData *pkData = [savedIdentity subdataWithRange:NSMakeRange(32, 32)];
        NSString *feedId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        [self updateWithIdentity:feedId name:nil];
    } else {
        self.nameLabel.stringValue = @"No Identity";
        self.idLabel.stringValue = @"";
    }
}

- (void)updateWithIdentity:(NSString *)feedId name:(nullable NSString *)name {
    self.feedId = feedId;

    if (name.length > 0) {
        self.nameLabel.stringValue = name;
    } else {
        self.nameLabel.stringValue = [feedId substringToIndex:MIN(feedId.length, 12)];
    }
    self.idLabel.stringValue = feedId;

    NSUInteger hash = [feedId hash];
    self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
}

- (void)setProfileAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Profile";
    alert.informativeText = @"Set your display name and description.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, 60)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    nameField.placeholderString = @"Display Name";
    NSTextField *descField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    descField.placeholderString = @"Description";
    [stack addArrangedSubview:nameField];
    [stack addArrangedSubview:descField];
    alert.accessoryView = stack;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *name = nameField.stringValue;
        NSString *desc = descField.stringValue;
        if (name.length == 0 && desc.length == 0) return;

        SSBRoomClient *client = [SRRoomManager sharedManager].clients.allValues.firstObject;
        if (!client) return;

        NSDictionary *content = [SSBMessageCodec aboutContentForFeed:self.feedId
                                                               name:name.length > 0 ? name : nil
                                                        description:desc.length > 0 ? desc : nil];
        NSError *error = nil;
        [client publishLocalMessageWithContent:content error:&error];

        if (!error && name.length > 0) {
            [self updateWithIdentity:self.feedId name:name];
        }
    }
}

@end
