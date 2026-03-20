#import "SRPlatformUI.h"
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRQRUtils : NSObject

/// Generate a QR code image from the given string.
+ (nullable NSImage *)generateQRCodeFromString:(NSString *)string size:(CGSize)size;

/// Generate a QR code image from raw data (e.g., for binary Bamboo messages).
+ (nullable NSImage *)generateQRCodeFromData:(NSData *)data size:(CGSize)size;

@end

@protocol SRScannerDelegate <NSObject>
- (void)scannerDidScanString:(NSString *)string;
@end

@interface SRScannerViewController : NSViewController <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, weak) id<SRScannerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
