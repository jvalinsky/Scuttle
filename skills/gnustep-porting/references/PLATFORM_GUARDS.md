# Platform Guards

## Common Guard Patterns

### Framework Imports

```objc
// macOS: Use Apple framework
// Linux: Use GNUstep
#ifdef __APPLE__
    #import <os/log.h>
    #import <Security/Security.h>
    #import <CommonCrypto/CommonCrypto.h>
#else
    #import <Foundation/Foundation.h>
    // GNUstep doesn't have os/log, use NSLog
#endif
```

### Class Availability

```objc
#ifdef __APPLE__
    @interface SSBPlatform : NSObject
    + (NSString *)uniqueIdentifier;
    @end
#else
    @interface SSBPlatform : NSObject
    + (NSString *)uniqueIdentifier;
    @end
#endif
```

### Method Availability

```objc
- (void)doSomething {
#ifdef __APPLE__
    // Use Apple-specific API
    NSXPCConnection *connection = [[NSXPCConnection alloc] init];
#else
    // Use GNUstep alternative
    // Or fall back to basic implementation
#endif
}
```

### Block Availability

```objc
#ifdef __APPLE__
    // Blocks work normally with ARC
    void (^block)(void) = ^{ NSLog(@"test"); };
#else
    // GNUstep supports blocks with -fobjc-arc and libblocksruntime
    void (^block)(void) = ^{ NSLog(@"test"); };
#endif
```

## Common Mismatches

### NSLog vs os_log

```objc
#ifdef __APPLE__
    static os_log_t logger = os_log_create("com.scuttlebutt", "debug");
    os_log_debug("%{public}@", message);
#else
    NSLog(@"%@", message);
#endif
```

### Keychain vs File

```objc
#ifdef __APPLE__
    // Use Security.framework
    SecItemAdd(query, NULL);
#else
    // Use encrypted file or custom implementation
    [self saveToSecureFile:data];
#endif
```

### Network Framework

```objc
#ifdef __APPLE__
    // Use Network.framework
    nw_connection_t conn = nw_connection_create(...);
#else
    // Use BSD sockets or libuv
    int sock = socket(AF_INET, SOCK_STREAM, 0);
#endif
```

## Guard Best Practices

1. **Use `__APPLE__`** for Apple platforms (macOS, iOS)
2. **Put guards at file level** when entire file is platform-specific
3. **Keep guards minimal** - extract to separate methods when possible
4. **Test both paths** - don't let platform code rot

## Files with Platform Guards

| File | Purpose |
|------|---------|
| `Sources/SSBLogCompat.h` | Logging shim |
| `Sources/SSBCommonCryptoCompat.h` | Crypto shim |
| `Sources/SSBKeychain.m` | Platform-specific |
