#import <Foundation/Foundation.h>
#import "SSBMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSBThread : NSObject

@property (nonatomic, readonly) SSBMessage *root;
@property (nonatomic, readonly) NSArray<SSBMessage *> *messages;

- (instancetype)initWithRoot:(SSBMessage *)root messages:(NSArray<SSBMessage *> *)messages;

/// Linearizes the thread according to SIP-010.
/// Sorts messages topologically based on `root` and `branch` (or `tangles` object),
/// resolving ties using `claimedTimestamp`.
- (NSArray<SSBMessage *> *)linearize;

/// Filters out messages from blocked authors
- (NSArray<SSBMessage *> *)linearizeFilteredByBlockedAuthors:(NSSet<NSString *> *)blockedAuthors;

@end

NS_ASSUME_NONNULL_END