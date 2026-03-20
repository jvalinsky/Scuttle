#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBFeedStore.h>

NS_ASSUME_NONNULL_BEGIN

/// Generates metafeed/index messages based on local storage queries.
@interface SSBIndexFeedGenerator : NSObject

- (instancetype)initWithFeedStore:(SSBFeedStore *)feedStore;

/// Generates a list of metafeed/index content dictionaries for messages of a specific type.
/// @param contentType The content type to index (e.g., "post").
/// @param limit Maximum number of messages to index.
- (NSArray<NSDictionary<NSString *, id> *> *)generateIndexForContentType:(NSString *)contentType
                                                                   limit:(NSInteger)limit;

/// Generates a list of metafeed/index content dictionaries for messages from a specific author.
- (NSArray<NSDictionary<NSString *, id> *> *)generateIndexForAuthor:(NSString *)author
                                                              limit:(NSInteger)limit;

@end

NS_ASSUME_NONNULL_END
