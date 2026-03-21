#import "SSBPlatformUI.h"

@implementation SSBPlatformUI

static id<SSBPlatformUIProtocol> _sharedPlatformUI = nil;

+ (void)initialize {
    if (self == [SSBPlatformUI class]) {
        _sharedPlatformUI = [[SSBPlatformUI alloc] init];
    }
}

+ (id<SSBPlatformUIProtocol>)shared {
    return _sharedPlatformUI;
}

+ (void)setShared:(id<SSBPlatformUIProtocol>)shared {
    _sharedPlatformUI = shared ?: [[SSBPlatformUI alloc] init];
}

- (NSModalResponse)runModalAlert:(NSAlert *)alert {
    return [alert runModal];
}

@end
