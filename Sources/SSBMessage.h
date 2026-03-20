#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBBFE.h>

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

NS_ASSUME_NONNULL_END
