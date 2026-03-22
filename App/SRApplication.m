#import "SRApplication.h"
#import "AppDelegate.h"

@interface SRApplication ()
@property (nonatomic, strong) AppDelegate *bootDelegate;
@end

@implementation SRApplication

- (instancetype)init {
    self = [super init];
    if (self) {
        self.bootDelegate = [[AppDelegate alloc] init];
        self.delegate = self.bootDelegate;
    }
    return self;
}

@end
