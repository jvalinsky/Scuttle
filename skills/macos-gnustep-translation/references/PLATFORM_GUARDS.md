# Platform Guards and Conditional Compilation

## Overview

Platform guards use `#ifdef` to conditionally compile code for macOS vs Linux (GNUstep). This allows a single codebase to work on both platforms.

## Guard Macros

### `__APPLE__`

Defined when compiling on Apple platforms (macOS, iOS, iPadOS, tvOS, watchOS):

```objc
#ifdef __APPLE__
    // macOS/iOS code
#else
    // Linux (GNUstep) code
#endif
```

### `__linux__`

Defined when compiling on Linux:

```objc
#ifdef __linux__
    // Linux-specific code
#endif
```

### `GNUSTEP`

Defined when using GNUstep headers:

```objc
#ifdef GNUSTEP
    // GNUstep-specific code
#endif
```

## Common Guard Patterns

### Pattern 1: Framework Import

```objc
#ifdef __APPLE__
    #import <os/log.h>
    #import <Network/Network.h>
    #import <Security/Security.h>
#else
    #import "SSBLogCompat.h"
    #import "SSBNetworkCompat.h"
    #import "SSBSecurityCompat.h"
#endif
```

### Pattern 2: Entire File

```objc
// Sources/SSBKeychain_macOS.m
#ifdef __APPLE__

@implementation SSBKeychain
// macOS Keychain implementation
@end

#endif
```

```objc
// Sources/SSBKeychain_Linux.m
#ifndef __APPLE__

@implementation SSBKeychain
// Linux file-based implementation
@end

#endif
```

### Pattern 3: Class Method

```objc
@implementation SSBNetwork

+ (NSData *)secureRandomBytes:(NSUInteger)length {
#ifdef __APPLE__
    NSMutableData *data = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(data.mutableBytes, length);
    return data;
#else
    NSMutableData *data = [NSMutableData dataWithLength:length];
    arc4random_buf(data.mutableBytes, length);
    return data;
#endif
}

@end
```

### Pattern 4: Header Declaration

```objc
// SSBNetworkCompat.h
#ifdef __APPLE__
    #import <Network/Network.h>
#else
    typedef id nw_connection_t;
    // ... other type declarations
#endif
```

### Pattern 5: Inline Shim

```objc
#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    #include <openssl/sha.h>
    
    typedef unsigned int CC_LONG;
    #define CC_SHA256_DIGEST_LENGTH 32
    
    static inline unsigned char *CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
        return SHA256(data, len, md);
    }
#endif
```

## Guard Locations in Scuttle

### SSBLogCompat.h

```objc
#ifdef __APPLE__
    #import <os/log.h>
#else
    #import <Foundation/Foundation.h>

    typedef NSString * os_log_t;

    #define os_log_create(subsystem, category) \
        [NSString stringWithFormat:@"%s.%s", subsystem, category]

    #define os_log_info(log, format, ...) \
        NSLog((@"[%@] INFO: " format), log, ##__VA_ARGS__)
    
    // ... other macros
#endif
```

### SSBCommonCryptoCompat.h

```objc
#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    #include <openssl/sha.h>
    #include <openssl/hmac.h>
    
    // OpenSSL shims
#endif
```

### SSBNetworkCompat.h

```objc
#ifdef __APPLE__
    #import <Network/Network.h>
#else
    // Linux type declarations
#endif
```

## GNUmakefile Platform Selection

```makefile
# Include platform-specific files
ifdef LINUX
    scuttle-cli_OBJC_FILES += Sources/SSBKeychain_Linux.m
else
    scuttle-cli_OBJC_FILES += Sources/SSBKeychain_macOS.m
endif
```

## Naming Conventions

### Platform-Specific Files

```
Sources/
├── SSBKeychain.m           # Shared (no guards)
├── SSBKeychain_macOS.m    # macOS only
└── SSBKeychain_Linux.m    # Linux only
```

### Compatibility Headers

```
Sources/
├── SSBLogCompat.h          # Logging shim
├── SSBCommonCryptoCompat.h # Crypto shim
├── SSBNetworkCompat.h      # Network shim types
└── SSBSecurityCompat.h     # Security shim (to create)
```

## Best Practices

### 1. Minimize Guard Locations

```objc
// BAD - too many guards
- (void)doSomething {
#ifdef __APPLE__
    [self doAppleThing];
#endif
#ifdef __APPLE__
    [self doSharedThing];
#endif
#ifndef __APPLE__
    [self doLinuxThing];
#endif
}

// GOOD - fewer, larger guard blocks
- (void)doSomething {
#ifdef __APPLE__
    [self doAppleThing];
    [self doSharedThing];
#else
    [self doLinuxThing];
    [self doSharedThing];
#endif
}
```

### 2. Extract to Separate Methods

```objc
// BAD
- (void)process {
#ifdef __APPLE__
    [self processApple];
#else
    [self processLinux];
#endif
}

// GOOD
- (void)process {
    [self platformProcess];
}

- (void)platformProcess {
#ifdef __APPLE__
    [self processApple];
#else
    [self processLinux];
#endif
}
```

### 3. Use Compatibility Headers

```objc
// BAD - inline guards everywhere
#ifdef __APPLE__
    os_log_info(logger, "message");
#else
    NSLog(@"message");
#endif

// GOOD - use compat header
#import "SSBLogCompat.h"

// Now just use os_log_info everywhere
os_log_info(logger, "message");
```

### 4. Document Platform Requirements

```objc
// CreateFile.m
//
// Platform support:
//   - macOS: Full support via Network.framework
//   - Linux: Stubs only (see SSBNetworkShim.m)

#import "SSBNetworkCompat.h"
```

## Testing Both Platforms

### CI Pipeline

```yaml
# .github/workflows/build.yml
- name: Build macOS
  run: |
    xcodebuild -scheme Scuttle build

- name: Build Linux
  run: |
    source /usr/share/GNUstep/Makefiles/GNUstep.sh
    make LINUX=1
```

### Local Testing

```bash
# macOS
xcodebuild -scheme Scuttle build

# Linux
source /usr/share/GNUstep/Makefiles/GNUstep.sh
make LINUX=1
```

## Common Mistakes

### Mistake 1: Mixing Guards

```objc
// BAD - inconsistent guards
#ifdef __APPLE__
    #import <A.h>
#endif
#ifndef __APPLE__
    #import "A_compat.h"
#endif

// GOOD - consistent
#ifdef __APPLE__
    #import <A.h>
#else
    #import "A_compat.h"
#endif
```

### Mistake 2: Forgetting to Close Guards

```objc
// BAD - missing #endif
#ifdef __APPLE__
    #import <Network/Network.h>
#endif
// ... code ...

// GOOD
#ifdef __APPLE__
    #import <Network/Network.h>
#endif
// ... code ...
```

### Mistake 3: Hardcoding Paths

```objc
// BAD - won't work on Linux
NSString *path = @"/Library/Application Support/Scuttle";

// GOOD - use standard directories
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
NSString *path = [paths.firstObject stringByAppendingPathComponent:@"Scuttle"];
```

## Summary

| Pattern | Use Case |
|---------|----------|
| `#ifdef __APPLE__` | Entire file or large blocks |
| `#ifndef __APPLE__` | Alternative implementations |
| Compatibility headers | Hide platform differences |
| Separate files | Major platform-specific code |
| GNUmakefile conditions | Build system selection |

**Recommendation:** Use compatibility headers to minimize inline guards, and extract platform-specific code to separate files when possible.
