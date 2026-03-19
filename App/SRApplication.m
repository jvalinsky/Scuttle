#import "SRApplication.h"
#import "AppDelegate.h"

static void SRAppendStartupLog(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = @"/tmp/scuttleroomapp-startup.log";
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

@interface SRApplication ()
@property (nonatomic, strong) AppDelegate *bootDelegate;
@end

@implementation SRApplication

- (instancetype)init {
    self = [super init];
    if (self) {
        SRAppendStartupLog(@"SRApplication init");
        self.bootDelegate = [[AppDelegate alloc] init];
        self.delegate = self.bootDelegate;
        SRAppendStartupLog(@"SRApplication installed AppDelegate");
    }
    return self;
}

@end
