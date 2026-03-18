---
name: gnustep-porting
description: Porting Objective-C code from macOS to Linux using GNUstep, including platform guards, compatibility shims, build system setup, and dependency management.
---

# GNUstep Porting for Scuttle

This skill provides expertise in porting Objective-C code from macOS to Linux using GNUstep, including platform compatibility shims, build system configuration, and dependency management.

## When to Use This Skill

Use this skill when you are:
- Porting macOS-specific code to Linux
- Creating compatibility shims for Apple frameworks
- Setting up GNUstep build configuration
- Adding platform guards (#ifdef __APPLE__)
- Managing cross-platform dependencies

## Porting Architecture

```
┌─────────────────────────────────────────┐
│           macOS (Source)                │
│   os/log, CommonCrypto, Security.framework │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         Compatibility Shims             │
│   SSBLogCompat.h, SSBCommonCryptoCompat.h │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│            Linux (Target)               │
│   GNUstep, OpenSSL, libdispatch         │
└─────────────────────────────────────────┘
```

## Existing Shims

### SSBLogCompat.h

**File:** `Sources/SSBLogCompat.h`

```c
#ifdef __APPLE__
    #import <os/log.h>
#else
    #import <Foundation/Foundation.h>

    typedef NSString * os_log_t;
    
    #define os_log_create(subsystem, category) \
        [NSString stringWithFormat:@"%s.%s", subsystem, category]
    
    #define os_log_info(log, format, ...) \
        NSLog((@"[%@] INFO: " format), log, ##__VA_ARGS__)
    
    #define os_log_error(log, format, ...) \
        NSLog((@"[%@] ERROR: " format), log, ##__VA_ARGS__)
    
    #define os_log_debug(log, format, ...) \
        NSLog((@"[%@] DEBUG: " format), log, ##__VA_ARGS__)
#endif
```

### SSBCommonCryptoCompat.h

**File:** `Sources/SSBCommonCryptoCompat.h`

```c
#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    #import <Foundation/Foundation.h>
    #include <openssl/sha.h>
    #include <openssl/hmac.h>
    #include <openssl/evp.h>

    typedef unsigned int CC_LONG;
    #define CC_SHA256_DIGEST_LENGTH 32

    static inline unsigned char * CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
        return SHA256((const unsigned char *)data, len, md);
    }

    static inline void CCHmac(CCHmacAlgorithm alg, const void *key, size_t keyLength,
                              const void *data, size_t dataLength, void *macOut) {
        // OpenSSL HMAC implementation
    }
#endif
```

## Platform Guards

### Conditional Compilation

```objc
#ifdef __APPLE__
    #import <os/log.h>
    #import <Security/Security.h>
#else
    #import <Foundation/Foundation.h>
#endif
```

### Platform-Specific Files

```
Sources/
├── SSBKeychain.m           (macOS - current)
├── SSBKeychain_macOS.m     (macOS - future)
├── SSBKeychain_Linux.m    (Linux - planned)
```

## Build System

### GNUmakefile

**File:** `GNUmakefile`

```makefile
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = ScuttleDaemon
ScuttleDaemon_OBJC_FILES = Sources/SSBMessage.m Sources/SSBFeedStore.m

# Objective-C features
ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks

# Linux dependencies
ADDITIONAL_LDFLAGS += -ldispatch -lobjc -lssl -lcrypto -lsqlite3

include $(GNUSTEP_MAKEFILES)/tool.make
```

### Dependencies

| Library | Purpose | Package |
|---------|---------|---------|
| gnustep-base | Foundation | libgnustep-base-dev |
| libdispatch | GCD | libdispatch-dev |
| OpenSSL | Crypto | libssl-dev |
| sqlite3 | Database | libsqlite3-dev |

## Reference Files

- [PLATFORM_GUARDS.md](references/PLATFORM_GUARDS.md) - Conditional compilation patterns
- [EXISTING_SHIMS.md](references/EXISTING_SHIMS.md) - Current compatibility shims
- [BUILD_SYSTEM.md](references/BUILD_SYSTEM.md) - GNUstep configuration
- [DEPENDENCIES.md](references/DEPENDENCIES.md) - Linux dependencies
