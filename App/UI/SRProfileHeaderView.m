#import "SRProfileHeaderView.h"
#import "../Logic/SRRoomManager.h"
#import <SSBNetwork/SSBKeychain.h>

@interface SRProfileHeaderView ()
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *idLabel;
@property (nonatomic, strong) NSButton *profileButton;
@property (nonatomic, strong) NSProgressIndicator *syncProgressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, copy) NSString *feedId;
@end

@implementation SRProfileHeaderView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
        [self loadLocalIdentity];
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(loadLocalIdentity) 
                                                     name:@"SRLocalIdentityGeneratedNotification" 
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleProfileUpdated:)
                                                     name:@"SRProfileUpdatedNotification"
                                                   object:nil];
    }
    return self;
}

- (void)handleProfileUpdated:(NSNotification *)notification {
    NSString *author = notification.object;
    if ([author isKindOfClass:[NSString class]] && [author isEqualToString:self.feedId]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *name = [[SSBFeedStore sharedStore] displayNameForAuthor:author];
            if (![name isEqualToString:author]) {
                [self updateWithIdentity:author name:name];
            }
        });
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

    _syncProgressBar = [[NSProgressIndicator alloc] init];
    _syncProgressBar.style = NSProgressIndicatorStyleBar;
    _syncProgressBar.controlSize = NSControlSizeSmall;
    _syncProgressBar.minValue = 0;
    _syncProgressBar.maxValue = 1.0;
    _syncProgressBar.doubleValue = 0;
    _syncProgressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _syncProgressBar.hidden = YES;
    [self addSubview:_syncProgressBar];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:10];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_statusLabel];

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
        
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_idLabel.leadingAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_idLabel.bottomAnchor constant:4],
        
        [_syncProgressBar.leadingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor constant:8],
        [_syncProgressBar.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_syncProgressBar.widthAnchor constraintEqualToConstant:100],
        [_syncProgressBar.heightAnchor constraintEqualToConstant:6],

        [_profileButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_profileButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
}

- (void)updateSyncProgress:(float)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = status;
        self.statusLabel.hidden = NO;
        if (progress < 1.0) {
            self.syncProgressBar.hidden = NO;
            self.syncProgressBar.doubleValue = progress;
        } else {
            self.syncProgressBar.hidden = YES;
        }
    });
}

- (void)setHidesProfileButton:(BOOL)hidesProfileButton {
    _hidesProfileButton = hidesProfileButton;
    self.profileButton.hidden = hidesProfileButton;
}

- (void)loadLocalIdentity {
    NSData *savedIdentity = [SSBKeychain loadIdentitySecret];
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
    if (!self.feedId) {
        [self loadLocalIdentity];
    }
    
    if (!self.feedId) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Identity Missing";
        alert.informativeText = @"Your SSB identity is still being generated. Please wait a moment and try again.";
        [alert runModal];
        return;
    }

    SSBRoomClient *client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    BOOL supportAlias = [client.roomFeatures containsObject:@"alias"] && client.isInternalUser;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Profile";
    alert.informativeText = @"Set your display name and description.";
    if (supportAlias) {
        alert.informativeText = [alert.informativeText stringByAppendingString:@" You can also set a short Alias for this room."];
    }
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, supportAlias ? 92 : 60)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    nameField.placeholderString = @"Display Name";
    NSTextField *descField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    descField.placeholderString = @"Description";
    NSTextField *aliasField = nil;
    if (supportAlias) {
        aliasField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        aliasField.placeholderString = @"Room Alias (e.g. alice)";
    }

    [stack addArrangedSubview:nameField];
    [stack addArrangedSubview:descField];
    if (aliasField) [stack addArrangedSubview:aliasField];
    
    alert.accessoryView = stack;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *name = nameField.stringValue;
        NSString *desc = descField.stringValue;
        NSString *alias = aliasField.stringValue;
        
        if (name.length == 0 && desc.length == 0 && alias.length == 0) return;

        if (!client) return;

        if (name.length > 0 || desc.length > 0) {
            NSDictionary *content = [SSBMessageCodec aboutContentForFeed:self.feedId
                                                                   name:name.length > 0 ? name : nil
                                                            description:desc.length > 0 ? desc : nil];
            NSError *error = nil;
            [client publishLocalMessageWithContent:content error:&error];

            if (!error && name.length > 0) {
                [self updateWithIdentity:self.feedId name:name];
            }
        }
        
        if (alias.length > 0 && supportAlias) {
            [client registerAlias:alias completion:^(id _Nullable response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        NSAlert *fail = [[NSAlert alloc] init];
                        fail.messageText = @"Alias Registration Failed";
                        fail.informativeText = error.localizedDescription;
                        [fail runModal];
                    } else {
                        // Success, could update UI or show a toast
                        NSLog(@"Alias registered successfully: %@", response);
                    }
                });
            }];
        }
    }
}

@end
