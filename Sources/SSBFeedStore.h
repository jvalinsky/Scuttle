#import <Foundation/Foundation.h>
#import "SSBBFE.h"
#import "SSBMessage.h"

NS_ASSUME_NONNULL_BEGIN

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

/// Returns YES if the given feed ID has been tombstoned by a metafeed/tombstone message.
/// Used by EBT clock generation to signal "do not want" for revoked feeds.
- (BOOL)isTombstoned:(NSString *)feedID;

/// Returns the message at the lipmaa-linked predecessor sequence for the given author and sequence.
/// Returns nil if the message is not stored or the format does not support lipmaa links.
- (nullable SSBMessage *)lipmaaMessageForAuthor:(NSString *)author
                                       sequence:(NSInteger)sequence
                                         format:(SSBBFEFeedFormat)format;

/// Returns the set of all device feed IDs registered under the given root metafeed ID.
/// These are feeds recorded by add/derived metafeed messages with purpose SSBMetafeedPurposeV1.
- (NSArray<NSString *> *)deviceFeedIDsForMetafeedID:(NSString *)metafeedID;

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
