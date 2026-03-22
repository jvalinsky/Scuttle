#import "SRQRUtils.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import "SRPlatformLog.h"

@implementation SRQRUtils

+ (nullable NSImage *)generateQRCodeFromString:(NSString *)string size:(CGSize)size {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [self generateQRCodeFromData:data size:size];
}

+ (nullable NSImage *)generateQRCodeFromData:(NSData *)data size:(CGSize)size {
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];

    CIImage *ciImage = filter.outputImage;
    if (!ciImage) return nil;

    // Scale up to requested size.
    CGFloat scaleX = size.width / ciImage.extent.size.width;
    CGFloat scaleY = size.height / ciImage.extent.size.height;
    CIImage *transformed = [ciImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];

    NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage:transformed];
    NSImage *nsImage = [[NSImage alloc] initWithSize:size];
    [nsImage addRepresentation:rep];
    return nsImage;
}

@end

@interface SRScannerViewController ()
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation SRScannerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 480)];
    self.view.wantsLayer = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.statusLabel = [NSTextField labelWithString:@"Starting camera..."];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.alignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];

    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelAction:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-40],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
        [self.cancelButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];

    [self requestCameraAccess];
}

- (void)requestCameraAccess {
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        if (status == AVAuthorizationStatusAuthorized) {
            [self setupCamera];
        } else if (status == AVAuthorizationStatusNotDetermined) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) [self setupCamera];
                    else self.statusLabel.stringValue = @"Camera access denied.";
                });
            }];
        } else {
            self.statusLabel.stringValue = @"Camera access denied. Please enable in Settings.";
        }
    } else {
        [self setupCamera];
    }
}

- (void)setupCamera {
    self.session = [[AVCaptureSession alloc] init];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        self.statusLabel.stringValue = @"No camera found.";
        return;
    }

    NSError *error;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Camera error: %@", error.localizedDescription];
        return;
    }

    [self.session addInput:input];

    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    [self.session addOutput:output];
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    if ([output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
        output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    } else {
        self.statusLabel.stringValue = @"QR scanning unsupported on this camera.";
    }

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.frame = self.view.bounds;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.previewLayer];

    // Bring UI to front.
    [self.statusLabel removeFromSuperview];
    [self.view addSubview:self.statusLabel];
    [self.cancelButton removeFromSuperview];
    [self.view addSubview:self.cancelButton];

    self.statusLabel.stringValue = @"Point camera at QR code";
    [self.session startRunning];
}

- (void)cancelAction:(id)sender {
    [self.session stopRunning];
    [self dismissController:nil];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataObject *metadata in metadataObjects) {
        if ([metadata.type isEqualToString:AVMetadataObjectTypeQRCode]) {
            AVMetadataMachineReadableCodeObject *readable = (AVMetadataMachineReadableCodeObject *)metadata;
            NSString *scannedString = readable.stringValue;
            if (scannedString) {
                [self.session stopRunning];
                [self.delegate scannerDidScanString:scannedString];
                [self dismissController:nil];
                break;
            }
        }
    }
}

@end
