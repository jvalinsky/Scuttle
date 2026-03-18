# Creating Compatibility Shims

## Overview

When macOS-specific APIs are not available on Linux, create compatibility shims. This guide walks through the process using examples from Scuttle.

## When to Create a Shim

Create a shim when:
1. macOS framework is unavailable on Linux (e.g., Network.framework)
2. Function behavior differs significantly (e.g., Keychain vs file storage)
3. Constant definitions are missing (e.g., error codes)

**Don't create a shim when:**
- GNUstep provides the same API (Foundation classes are 90%+ compatible)
- A simple `#ifdef` suffices for one-off differences

## Shim Types

### Type 1: Header-Only Shim

For types and macros that can be defined inline:

```c
// SSBLogCompat.h
#ifdef __APPLE__
    #import <os/log.h>
#else
    #import <Foundation/Foundation.h>
    
    typedef NSString * os_log_t;
    #define os_log_create(subsystem, category) [NSString stringWithFormat:@"%s.%s", subsystem, category]
    #define os_log_info(log, format, ...) NSLog((@"[%@] " format), log, ##__VA_ARGS__)
#endif
```

### Type 2: Header + Implementation

For functions requiring actual implementation:

```
// Header: SSBSecurityCompat.h
// Implementation: SSBSecurityCompat.m (GNUmakefile includes this on Linux)
```

### Type 3: Platform-Specific Files

For completely different implementations:

```
// Sources/SSBKeychain_macOS.m (included on macOS)
// Sources/SSBKeychain_Linux.m (included on Linux)
```

## Step-by-Step: Creating a Shim

### Step 1: Identify the API

List the specific functions, types, and constants needed:

```objc
// macOS API you need
SecRandomCopyBytes(SecRandomRef rnd, size_t count, uint8_t *bytes);
errSecSuccess
errSecItemNotFound
```

### Step 2: Create the Header

```c
// Sources/SSBSecurityCompat.h
#ifndef SSBSecurityCompat_h
#define SSBSecurityCompat_h

#ifdef __APPLE__
    #import <Security/Security.h>
#else
    // Linux (GNUstep) implementation
    #import <Foundation/Foundation.h>
    #include <openssl/rand.h>
    
    // Type aliases
    typedef int32_t OSStatus;
    
    // Error constants
    enum {
        errSecSuccess = 0,
        errSecItemNotFound = -25300,
        errSecDuplicateItem = -25299,
        errSecAuthFailed = -25290
    };
    
    // Function declaration
    OSStatus SecRandomCopyBytes(void *bytes, size_t count);
#endif

#endif
```

### Step 3: Create the Implementation (if needed)

```c
// Sources/SSBSecurityCompat.m
#ifndef __APPLE__

#import "SSBSecurityCompat.h"

OSStatus SecRandomCopyBytes(void *bytes, size_t count) {
    if (RAND_bytes(bytes, count) == 1) {
        return errSecSuccess;
    }
    return errSecAuthFailed;
}

#endif
```

### Step 4: Create a Stub File (if needed)

For complex APIs that can't be simply shimmed:

```objc
// Sources/SSBSecurityCompatStub.m
#ifndef __APPLE__

// Stub implementations that log and return sensible defaults
// Real implementation would require significant work

void *nw_connection_create(void *endpoint, void *parameters) {
    NSLog(@"STUB: nw_connection_create - networking not implemented");
    return NULL;
}

#endif
```

### Step 5: Update GNUmakefile

```makefile
# Add implementation for Linux
ifdef LINUX
    scuttle-cli_OBJC_FILES += Sources/SSBSecurityCompat.m
endif
```

### Step 6: Update Source Files

```objc
// Before
#ifdef __APPLE__
    SecRandomCopyBytes(buffer, length);
#else
    arc4random_buf(buffer, length);  // Inconsistent with macOS
#endif

// After
#import "SSBSecurityCompat.h"

SecRandomCopyBytes(buffer, length);  // Works on both platforms
```

## Example: Complete Shim Creation

### Scenario: Creating dispatch_data_get_size shim

**Problem:** `dispatch_data_get_size()` is not defined in libdispatch on Linux.

### Step 1: Check if it exists

```bash
# macOS
grep -r "dispatch_data_get_size" /usr/include/dispatch/*.h

# Linux - check libdispatch headers
grep -r "dispatch_data_get_size" /usr/include/dispatch/*.h
# Result: Not found on Linux
```

### Step 2: Create Shim

```c
// Add to SSBNetworkCompat.h
#ifndef __APPLE__
// dispatch_data_t is NSData-compatible on GNUstep
typedef NSData * dispatch_data_t;

// Shim for dispatch_data_get_size
static inline size_t dispatch_data_get_size(dispatch_data_t data) {
    return data.length;
}
#endif
```

### Step 3: Test

```objc
dispatch_data_t data = dispatch_data_create(bytes, length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
size_t size = dispatch_data_get_size(data);  // Works on both platforms
```

## Shim Patterns

### Pattern 1: Type Alias

```c
// Convert macOS types to Linux types
typedef NSData * dispatch_data_t;
typedef NSString * os_log_t;
typedef id nw_connection_t;
```

### Pattern 2: Macro Redefinition

```c
// Redirect to compatible function
#define os_log_create(subsystem, category) [NSString stringWithFormat:@"%s.%s", subsystem, category]
#define kSecAttrAccessibleWhenUnlocked @""  // Dummy for compilation
```

### Pattern 3: Inline Function

```c
// Implement functionality inline
static inline OSStatus SecRandomCopyBytes(void *bytes, size_t count) {
    arc4random_buf(bytes, count);
    return 0;
}
```

### Pattern 4: Wrapper Class

```objc
// For complex APIs, wrap in Objective-C class
@interface SSBPlatformNetwork : NSObject
+ (nw_connection_t)createConnection:(NSString *)host port:(uint16_t)port;
+ (void)sendData:(NSData *)data onConnection:(nw_connection_t)conn;
@end
```

### Pattern 5: Stub with Logging

```c
// For unimplemented features, log and fail gracefully
void complex_function(...) {
    NSLog(@"STUB: complex_function - not implemented on Linux");
    // Return sensible default or call alternative
}
```

## Error Handling

### Return Sensible Defaults

```c
// Don't crash on Linux - return safe defaults
nw_connection_t nw_connection_create(...) {
    return NULL;  // Safe default
}

BOOL nw_connection_start(...) {
    return;  // No-op
}
```

### Log for Debugging

```c
void unimplemented_function(...) {
    NSLog(@"WARNING: unimplemented_function called - feature may not work on Linux");
}
```

### Provide Alternatives

```c
OSStatus SecRandomCopyBytes(void *bytes, size_t count) {
#ifdef __APPLE__
    return SecRandomCopyBytes(kSecRandomDefault, count, bytes);
#else
    // Use OpenSSL as alternative
    if (RAND_bytes(bytes, count) != 1) {
        return errSecAuthFailed;
    }
    return errSecSuccess;
#endif
}
```

## Testing Shims

### Unit Tests

```objc
- (void)testSecRandomCopyBytesShim {
    uint8_t buffer[32];
    OSStatus status = SecRandomCopyBytes(buffer, sizeof(buffer));
    
    XCTAssertEqual(status, errSecSuccess);
    XCTAssertTrue(buffer[0] != 0 || buffer[1] != 0);  // Check randomness
}
```

### Integration Tests

```bash
# Test on Linux
source /usr/share/GNUstep/Makefiles/GNUstep.sh
make LINUX=1 test

# Test on macOS
xcodebuild test
```

### Smoke Tests

```objc
// Test that shim compiles and runs
- (void)testShimSmokeTest {
    // Should not crash
    os_log_t log = os_log_create("test", "smoke");
    os_log_info(log, "Test message");
    
    uint8_t buf[16];
    SecRandomCopyBytes(buf, sizeof(buf));
}
```

## Documenting Shims

### Header Comments

```c
// SSBSecurityCompat.h
//
// Compatibility shim for Security.framework
//
// macOS: Uses native Security.framework
// Linux: Uses OpenSSL for crypto, file-based storage for Keychain
//
// Created: 2026-03
// Status: Complete
```

### Inline Documentation

```c
// Shim for dispatch_data_get_size
// On Linux, dispatch_data_t is typedef'd to NSData
// so we can use NSData.length directly
static inline size_t dispatch_data_get_size(dispatch_data_t data) {
    return data.length;
}
```

## Summary Checklist

- [ ] Identify all needed APIs (functions, types, constants)
- [ ] Determine shim type (header-only, header+impl, or stub)
- [ ] Create header file with `#ifdef __APPLE__` guards
- [ ] Create implementation file if needed
- [ ] Update GNUmakefile to include Linux-specific files
- [ ] Update source files to include compat header
- [ ] Write tests for shim functionality
- [ ] Document expected behavior on both platforms
- [ ] Test on both macOS and Linux

## Existing Shims in Scuttle

| Shim | Type | Status |
|------|------|--------|
| `SSBLogCompat.h` | Header | ✅ Complete |
| `SSBCommonCryptoCompat.h` | Header | ✅ Complete |
| `SSBNetworkCompat.h` | Header | ⚠️ Types only |
| `SSBNetworkShim.m` | Stub | ⚠️ Stubs only |
| `SSBKeychain_macOS.m` | Platform file | ✅ Complete |
| `SSBKeychain_Linux.m` | Platform file | ✅ Complete |
| `SSBSecurityCompat.h` | Header | ❌ Needs creation |
