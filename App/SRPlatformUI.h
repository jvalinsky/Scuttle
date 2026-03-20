#ifdef __APPLE__
#import <Cocoa/Cocoa.h>
#else
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface NSImage (SRPlatformSymbols)
+ (NSImage *)imageWithSystemSymbolName:(NSString *)symbolName accessibilityDescription:(nullable NSString *)description;
@end
#endif
