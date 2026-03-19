#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Scuttle Headless Daemon starting on Linux...");
        
        // Test GCD
        dispatch_queue_t queue = dispatch_queue_create("com.scuttle.test", DISPATCH_QUEUE_SERIAL);
        
        dispatch_async(queue, ^{
            NSLog(@"Hello from background queue! GCD is working.");
        });
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"Timer fired on main queue. Scuttle logic is ready for porting.");
            exit(0);
        });
        
        NSLog(@"Entering runloop...");
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
