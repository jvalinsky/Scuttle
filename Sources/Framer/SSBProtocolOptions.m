#import "SSBProtocolOptions.h"
#import <objc/runtime.h>

static const void *SSBProtocolOptionsKey = &SSBProtocolOptionsKey;

@implementation SSBProtocolOptions

- (instancetype)initWithNetworkIdentifier:(NSData *)networkIdentifier
                           localSecretKey:(NSData *)localSecretKey
                          remotePublicKey:(NSData *)remotePublicKey {
    self = [super init];
    if (self) {
        _networkIdentifier = [networkIdentifier copy];
        _localSecretKey = [localSecretKey copy];
        _remotePublicKey = [remotePublicKey copy];
    }
    return self;
}

- (void)applyToProtocolOptions:(nw_protocol_options_t)options {
    // We attach the options to the protocol_options wrapper using objc_setAssociatedObject.
    // In a pure C API, we'd use nw_protocol_options_set_... but NWFramer currently 
    // requires associated objects for custom Swift/ObjC objects on generic options.
    objc_setAssociatedObject(options, SSBProtocolOptionsKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (nullable SSBProtocolOptions *)optionsFromProtocolOptions:(nw_protocol_options_t)options {
    return objc_getAssociatedObject(options, SSBProtocolOptionsKey);
}

@end