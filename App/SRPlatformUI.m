#import "SRPlatformUI.h"

#ifndef __APPLE__
@implementation NSImage (SRPlatformSymbols)

+ (NSImage *)imageWithSystemSymbolName:(NSString *)symbolName accessibilityDescription:(NSString *)description {
    (void)description;

    NSImage *image = nil;
    if (symbolName.length > 0) {
        image = [NSImage imageNamed:symbolName];
    }
    if (!image) {
        image = [NSImage imageNamed:@"NSApplicationIcon"];
    }
    if (!image) {
        image = [[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)];
    }
    return image;
}

@end
#endif
