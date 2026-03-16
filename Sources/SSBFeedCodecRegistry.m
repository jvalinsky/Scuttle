#import "SSBFeedCodecRegistry.h"

@implementation SSBFeedCodecRegistry {
    NSMutableDictionary<NSNumber *, id<SSBFeedCodec>> *_codecs;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedRegistry {
    static SSBFeedCodecRegistry *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSBFeedCodecRegistry alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _codecs = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.scuttlebutt.codec-registry", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)registerCodec:(id<SSBFeedCodec>)codec {
    dispatch_barrier_async(_queue, ^{
        self->_codecs[@(codec.feedFormat)] = codec;
    });
}

- (nullable id<SSBFeedCodec>)codecForFeedFormat:(SSBBFEFeedFormat)format {
    __block id<SSBFeedCodec> codec;
    dispatch_sync(_queue, ^{
        codec = self->_codecs[@(format)];
    });
    return codec;
}

@end
