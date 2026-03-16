#import <Foundation/Foundation.h>
#import "SSBBFE.h"

NS_ASSUME_NONNULL_BEGIN

/// Represents a single SSB message in any supported feed format.
@interface SSBMessage : NSObject
@property (nonatomic, copy) NSString *key;           // %hash.sha256 or %hash.bbmsg-v1, etc.
@property (nonatomic, copy) NSString *author;        // @pubkey.ed25519, @pubkey.bbfeed-v1, etc.
@property (nonatomic, assign) NSInteger sequence;
@property (nonatomic, copy, nullable) NSString *previousKey;
@property (nonatomic, assign) int64_t claimedTimestamp; // author's timestamp (ms)
@property (nonatomic, assign) int64_t receivedAt;       // local store time (ms)
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, copy, nullable) NSString *contentType; // "post", "contact", "metafeed/index", etc.
@property (nonatomic, copy) NSData *valueJSON;          // canonical signed value bytes (wire format)
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id> *content; // parsed content dict
/// Feed format for this message. Defaults to SSBBFEFeedFormatClassic (0).
@property (nonatomic, assign) SSBBFEFeedFormat feedFormat;
@end

/// Represents the local state of a feed (for replication).
@interface SSBFeedState : NSObject
@property (nonatomic, copy) NSString *author;
@property (nonatomic, assign) NSInteger maxSequence;
@property (nonatomic, copy, nullable) NSString *maxKey;
/// Feed format for this state entry. Defaults to SSBBFEFeedFormatClassic (0).
@property (nonatomic, assign) SSBBFEFeedFormat feedFormat;
@end

/// Local SQLite-backed feed store for SSB messages.
@interface SSBFeedStore : NSObject

/// Shared store instance (uses ~/Library/Application Support/ScuttleKit/feeds.db).
+ (instancetype)sharedStore;

/// Initialize with a specific database path.
- (instancetype)initWithPath:(NSString *)dbPath;

/// Appends a message to the store. Validates sequence/previous chain.
/// Returns YES on success, NO if validation fails or duplicate.
- (BOOL)appendMessage:(SSBMessage *)message error:(NSError **)error;

/// Returns the current feed state for an author, or nil if no messages stored.
- (nullable SSBFeedState *)feedStateForAuthor:(NSString *)author;

/// Returns the current local clock (max sequence for each author we follow or own).
- (NSDictionary<NSString *, NSNumber *> *)localClock;

/// Returns messages for a given author, starting at sequence, up to limit.
/// Used for serving createHistoryStream requests.
- (NSArray<SSBMessage *> *)messagesForAuthor:(NSString *)author
                                fromSequence:(NSInteger)startSeq
                                       limit:(NSInteger)limit;

/// Returns the latest N messages across all feeds (Global).
- (NSArray<SSBMessage *> *)recentMessagesWithLimit:(NSInteger)limit;

/// Returns the latest N messages across all followed feeds, for timeline display.
- (NSArray<SSBMessage *> *)timelineWithLimit:(NSInteger)limit;

/// Returns the latest N messages for a specific author (reverse chronological).
- (NSArray<SSBMessage *> *)feedForAuthor:(NSString *)author limit:(NSInteger)limit;

/// Returns messages of a specific content type across all feeds.
- (NSArray<SSBMessage *> *)messagesOfType:(NSString *)contentType limit:(NSInteger)limit;

/// Returns the latest N messages stored for a given feed format (e.g. index or metafeed messages).
- (NSArray<SSBMessage *> *)messagesForFeedFormat:(SSBBFEFeedFormat)format limit:(NSInteger)limit;

#pragma mark - Subset Queries (SIP 3)

/// Executes an ssb-ql-0 query and returns matching messages.
/// @param query The ssb-ql-0 query dictionary.
/// @param options Query options: @"pageSize" (NSNumber), @"descending" (NSNumber), @"startFrom" (NSNumber/seq).
- (NSArray<SSBMessage *> *)querySubset:(NSDictionary<NSString *, id> *)query
                               options:(NSDictionary<NSString *, id> *)options;

#pragma mark - Follow Graph

/// Records that we follow or unfollow a given author.
- (void)setFollowing:(BOOL)following forAuthor:(NSString *)author atSequence:(NSInteger)seq;

/// Records that we block or unblock a given author.
- (void)setBlocked:(BOOL)blocked forAuthor:(NSString *)author atSequence:(NSInteger)seq;

/// Returns YES if we are following the given author.
- (BOOL)isFollowing:(NSString *)author;

/// Returns YES if we have blocked the given author.
- (BOOL)isBlocked:(NSString *)author;

/// Returns the set of all authors we follow.
- (NSArray<NSString *> *)followedAuthors;

/// Returns the set of all unique channel names found in 'post' messages.
- (NSArray<NSString *> *)allChannels;

/// Searches for messages containing the given text in their content.
- (NSArray<SSBMessage *> *)searchMessages:(NSString *)searchText limit:(NSInteger)limit;

/// Returns the total number of stored messages.
- (NSInteger)totalMessageCount;

/// Returns a dictionary of author -> message count for visualization.
- (NSDictionary<NSString *, NSNumber *> *)storageStatistics;

#pragma mark - Profiles

/// Updates the display name and/or image for a given feed ID.
- (void)setDisplayName:(nullable NSString *)name image:(nullable NSString *)image forAuthor:(NSString *)author;

/// Returns the display name for a given author, or the author ID if none set.
- (NSString *)displayNameForAuthor:(NSString *)author;

/// Wipes all data from the store and resets the database file.
- (void)wipeDatabase;

@end

NS_ASSUME_NONNULL_END
