#import "SSBGitObjectStore.h"
#import "SSBBlobStore.h"
#import "SSBGitPackIDXParser.h"

@interface SSBGitObjectStore ()

@property (nonatomic, strong) SSBBlobStore *blobStore;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *packs;
@property (nonatomic, strong) dispatch_queue_t packsQueue;

@end

@implementation SSBGitObjectStore

- (instancetype)initWithBlobStore:(SSBBlobStore *)blobStore {
    if (self = [super init]) {
        _blobStore = blobStore;
        _packs = [NSMutableArray array];
        _packsQueue = dispatch_queue_create("com.scuttlebutt.git.objectstore", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)registerPackBlob:(NSString *)packBlobID idxBlob:(NSString *)idxBlobID {
    if (!packBlobID || !idxBlobID) return;
    
    dispatch_sync(self.packsQueue, ^{
        // Check if we already have it
        for (NSDictionary *dict in self.packs) {
            if ([dict[@"pack"] isEqualToString:packBlobID]) {
                return;
            }
        }
        
        [self.packs addObject:@{
            @"pack": packBlobID,
            @"idx": idxBlobID
        }];
    });
}

- (nullable SSBGitObject *)objectForSHA1:(NSString *)sha1 {
    if (sha1.length != 40) return nil;
    
    __block NSArray *packsCopy;
    dispatch_sync(self.packsQueue, ^{
        packsCopy = [self.packs copy];
    });
    
    for (NSDictionary *packInfo in packsCopy) {
        NSString *idxBlobID = packInfo[@"idx"];
        NSString *idxPath = [self.blobStore localPathForBlobID:idxBlobID];
        
        if (!idxPath) continue;
        
        NSData *idxData = [NSData dataWithContentsOfFile:idxPath options:NSDataReadingMappedIfSafe error:nil];
        if (!idxData) continue;
        
        SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:idxData];
        if (!parser) continue;
        
        uint64_t offset = [parser offsetForHexString:sha1];
        if (offset > 0) {
            NSString *packBlobID = packInfo[@"pack"];
            NSString *packPath = [self.blobStore localPathForBlobID:packBlobID];
            if (!packPath) continue;
            
            NSData *packData = [NSData dataWithContentsOfFile:packPath options:NSDataReadingMappedIfSafe error:nil];
            if (!packData) continue;
            
            SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:packData];
            if (!decoder) continue;
            decoder.objectStore = self;
            
            SSBGitObject *obj = [decoder objectAtOffset:offset];
            if (obj) return obj;
        }
    }
    return nil;
}

- (nullable NSString *)packBlobIDForSHA1:(NSString *)sha1 {
    if (sha1.length != 40) return nil;
    
    __block NSArray *packsCopy;
    dispatch_sync(self.packsQueue, ^{
        packsCopy = [self.packs copy];
    });
    
    for (NSDictionary *packInfo in packsCopy) {
        NSString *idxBlobID = packInfo[@"idx"];
        NSString *idxPath = [self.blobStore localPathForBlobID:idxBlobID];
        if (!idxPath) continue;
        
        NSData *idxData = [NSData dataWithContentsOfFile:idxPath options:NSDataReadingMappedIfSafe error:nil];
        if (!idxData) continue;
        
        SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:idxData];
        if (!parser) continue;
        
        if ([parser offsetForHexString:sha1] > 0) {
            return packInfo[@"pack"];
        }
    }
    return nil;
}

@end
