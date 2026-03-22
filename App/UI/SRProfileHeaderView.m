#import "SRProfileHeaderView.h"
#import <QuartzCore/QuartzCore.h>
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "SRStyle.h"
#import <SSBNetwork/SSBSecretStore.h>
#import <SSBNetwork/SSBFeedStore.h>
#import "SRPlatformLog.h"

static os_log_t profile_header_log;

@interface SRProfileHeaderView ()
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *idLabel;
@property (nonatomic, strong) NSButton *profileButton;
@property (nonatomic, strong) NSProgressIndicator *syncProgressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, copy) NSString *feedId;

// Stats Row
@property (nonatomic, strong) NSStackView *statsStackView;
@property (nonatomic, strong) NSTextField *messagesLabel;
@property (nonatomic, strong) NSTextField *followingLabel;
@property (nonatomic, strong) NSTextField *followersLabel;

// Dynamic Height Constraints
@property (nonatomic, strong) NSLayoutConstraint *regularBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *compactBottomConstraint;

// Conditional Layout Support
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *regularConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *compactConstraints;

// Aesthetic Elements
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@end

@implementation SRProfileHeaderView

+ (void)initialize {
    if (self == [SRProfileHeaderView class]) {
        profile_header_log = os_log_create("com.scuttlebutt.app", "ProfileHeader");
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 16;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        
        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer insertSublayer:_gradientLayer atIndex:0];

        [self setupUI];
        [self viewDidChangeEffectiveAppearance];
        [self loadLocalIdentity];
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(loadLocalIdentity) 
                                                     name:SRLocalIdentityGeneratedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleProfileUpdated:)
                                                     name:SRProfileUpdatedNotification
                                                   object:nil];
    }
    return self;
}

- (void)layout {
    [super layout];
    self.gradientLayer.frame = NSRectToCGRect(self.bounds);
    self.avatarView.layer.cornerRadius = self.avatarView.bounds.size.height / 2.0;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.layer.borderColor = [[NSColor separatorColor] colorWithAlphaComponent:0.3].CGColor;
    if (self.feedId.length <= 10) {
        self.layer.backgroundColor = [SRStyle surfaceColor].CGColor;
    }
    if (self.feedId.length > 0) {
        NSUInteger hash = [self.feedId hash];
        self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.65 alpha:1.0].CGColor;
    }
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
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Prevent stretching by layout system
    [_avatarView setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_avatarView setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [_avatarView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_avatarView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    
    [self addSubview:_avatarView];

    _nameLabel = [NSTextField labelWithString:@""];
    _nameLabel.font = [NSFont boldSystemFontOfSize:18]; // Larger for profile
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_nameLabel];

    _idLabel = [NSTextField labelWithString:@""];
    _idLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
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

    // Stats Labels
    _messagesLabel = [self createStatsLabel];
    _followingLabel = [self createStatsLabel];
    _followersLabel = [self createStatsLabel];

    _statsStackView = [[NSStackView alloc] init];
    _statsStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _statsStackView.spacing = 16;
    _statsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_statsStackView];

    [_statsStackView addArrangedSubview:_messagesLabel];
    [_statsStackView addArrangedSubview:_followingLabel];
    [_statsStackView addArrangedSubview:_followersLabel];

    [self updateStatsWithMessages:0 following:0 followers:0]; // Initial mockup

    // General Always-Active Safety Clamps
    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.widthAnchor constraintEqualToConstant:64],
        [_avatarView.heightAnchor constraintEqualToConstant:64],
        [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:_avatarView.bottomAnchor constant:16],
        [_syncProgressBar.widthAnchor constraintEqualToConstant:100],
        [_syncProgressBar.heightAnchor constraintEqualToConstant:6]
    ]];

    // --- Regular Mode (Centered) Constraints ---
    _regularConstraints = @[
        [_avatarView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_avatarView.topAnchor constraintEqualToAnchor:self.topAnchor constant:24],

        [_nameLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_nameLabel.topAnchor constraintEqualToAnchor:_avatarView.bottomAnchor constant:12],
        [_nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:16],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

        [_idLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_idLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],
        [_idLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:16],
        [_idLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

        [_statsStackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_statsStackView.topAnchor constraintEqualToAnchor:_idLabel.bottomAnchor constant:16],

        [_statusLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_statsStackView.bottomAnchor constant:8],

        [_syncProgressBar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_syncProgressBar.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],

        [_profileButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_profileButton.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        
        [self.heightAnchor constraintEqualToConstant:220]
    ];

    _regularBottomConstraint = [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:_statusLabel.bottomAnchor constant:16];

    // --- Compact Mode (Left-Aligned Sidebar) Constraints ---
    _compactConstraints = @[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_avatarView.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:16],
        [_nameLabel.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:4],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

        [_idLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_idLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],
        [_idLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor]
    ];

    _compactBottomConstraint = [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:_idLabel.bottomAnchor constant:16];

    // Default Activation
    [NSLayoutConstraint activateConstraints:_regularConstraints];
    _regularBottomConstraint.active = YES;
}

- (NSTextField *)createStatsLabel {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    label.textColor = [NSColor labelColor];
    return label;
}

- (void)updateStatsWithMessages:(NSInteger)messages following:(NSInteger)following followers:(NSInteger)followers {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.messagesLabel.stringValue = [NSString stringWithFormat:@"%ld Messages", (long)messages];
        self.followingLabel.stringValue = [NSString stringWithFormat:@"%ld Following", (long)following];
        self.followersLabel.stringValue = [NSString stringWithFormat:@"%ld Followers", (long)followers];
    });
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
    NSData *savedIdentity = SSBLoadIdentitySecret();
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

    // Generate aesthetically rich gradient based on identity string
    if (feedId.length > 10) {
        NSUInteger hash = [feedId hash];
        CGFloat hue1 = (CGFloat)(hash % 360) / 360.0;
        CGFloat hue2 = (CGFloat)((hash + 40) % 360) / 360.0; // 40 deg offset
        
        NSColor *color1 = [NSColor colorWithHue:hue1 saturation:0.65 brightness:0.85 alpha:0.9];
        NSColor *color2 = [NSColor colorWithHue:hue2 saturation:0.75 brightness:0.55 alpha:0.9];
        
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.gradientLayer.colors = @[(__bridge id)color1.CGColor, (__bridge id)color2.CGColor];
        [CATransaction commit];
        
        // Ensure titles look great on color
        self.nameLabel.textColor = [NSColor whiteColor];
        self.idLabel.textColor = [[NSColor whiteColor] colorWithAlphaComponent:0.7];
    } else {
        self.gradientLayer.colors = nil;
        self.layer.backgroundColor = [SRStyle surfaceColor].CGColor;
    }

    if (name.length > 0) {
        self.nameLabel.stringValue = name;
    } else {
        self.nameLabel.stringValue = [feedId substringToIndex:MIN(feedId.length, 12)];
    }
    self.idLabel.stringValue = feedId;

    NSUInteger hash = [feedId hash];
    self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.65 alpha:1.0].CGColor;

    [self loadStatsForFeedId:feedId];
}

- (void)loadStatsForFeedId:(NSString *)feedId {
    if (!feedId) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        SSBFeedStore *store = [SSBFeedStore sharedStore];
        SSBFeedState *state = [store feedStateForAuthor:feedId];
        NSInteger messageCount = state ? state.maxSequence : 0;

        // "Following" is available for the local user (authors we follow).
        // For remote peers it's not queryable without processing their contact messages.
        NSData *localSecret = SSBLoadIdentitySecret();
        NSString *localFeedId = localSecret ? SSBPublicIDFromSecret(localSecret) : nil;
        NSInteger followingCount = [feedId isEqualToString:localFeedId] ? (NSInteger)[store followedAuthors].count : 0;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.feedId isEqualToString:feedId]) return;
            [self updateStatsWithMessages:messageCount following:followingCount followers:0];
        });
    });
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
                        os_log_info(profile_header_log, "Alias registered successfully: %{public}@", response);
                    }
                });
            }];
        }
    }
}

- (void)setCompactMode:(BOOL)compactMode {
    _compactMode = compactMode;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSLayoutConstraint deactivateConstraints:self.regularConstraints];
        [NSLayoutConstraint deactivateConstraints:self.compactConstraints];
        self.regularBottomConstraint.active = NO;
        self.compactBottomConstraint.active = NO;

        if (compactMode) {
            self.statsStackView.hidden = YES;
            self.statusLabel.hidden = YES;
            self.syncProgressBar.hidden = YES;
            self.profileButton.hidden = YES;
            
            self.nameLabel.alignment = NSTextAlignmentLeft;
            self.idLabel.alignment = NSTextAlignmentLeft;

            [NSLayoutConstraint activateConstraints:self.compactConstraints];
            self.compactBottomConstraint.active = YES;
        } else {
            self.statsStackView.hidden = NO;
            self.profileButton.hidden = NO;
            
            self.nameLabel.alignment = NSTextAlignmentCenter;
            self.idLabel.alignment = NSTextAlignmentCenter;

            [NSLayoutConstraint activateConstraints:self.regularConstraints];
            self.regularBottomConstraint.active = YES;
        }
    });
}

@end
