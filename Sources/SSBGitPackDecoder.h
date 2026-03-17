#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBGitObjectType) {
    SSBGitObjectTypeCommit = 1,
    SSBGitObjectTypeTree = 2,
    SSBGitObjectTypeBlob = 3,
    SSBGitObjectTypeTag = 4,
    SSBGitObjectTypeOfsDelta = 6,
    SSBGitObjectTypeRefDelta = 7
};

@interface SSBGitObject : NSObject
@property (nonatomic, assign) SSBGitObjectType type;
@property (nonatomic, strong) NSData *data;
@end

@class SSBGitObjectStore;

/// Decodes git PACK v2 files and extracts objects by offset.
@interface SSBGitPackDecoder : NSObject

@property (nonatomic, weak, nullable) SSBGitObjectStore *objectStore;

/// Initialize with raw .pack file data.
/// Returns nil if the magic/version header is invalid.
- (nullable instancetype)initWithData:(NSData *)data;

/// Extracts and decompresses the object at the given offset.
/// This method will also recursively resolve OFS_DELTA and REF_DELTA objects.
- (nullable SSBGitObject *)objectAtOffset:(uint64_t)offset;

@end

NS_ASSUME_NONNULL_END
