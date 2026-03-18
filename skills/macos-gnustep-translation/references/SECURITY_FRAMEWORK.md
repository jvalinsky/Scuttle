# Security.framework Compatibility

## Overview

Apple's Security.framework provides:
1. **Keychain** - Secure credential storage
2. **SecRandomCopyBytes** - Cryptographic random number generation

**Status:**
- Keychain: ✅ Complete (file-based alternative for Linux)
- SecRandomCopyBytes: ⚠️ Missing shim

## Keychain

### macOS Implementation

**File:** `Sources/SSBKeychain_macOS.m`

Uses Apple's Security.framework:

```objc
#ifdef __APPLE__
#import <Security/Security.h>

+ (NSMutableDictionary *)baseQuery {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = @"com.scuttlebutt.identity";
    return query;
}

+ (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    
    SecItemDelete((__bridge CFDictionaryRef)query);
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

+ (nullable NSData *)loadDataForKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    
    if (status == errSecSuccess && result) {
        return (__bridge_transfer NSData *)result;
    }
    return nil;
}
#endif
```

### Linux Implementation

**File:** `Sources/SSBKeychain_Linux.m`

Uses file-based storage with restrictive permissions:

```objc
#ifndef __APPLE__

@implementation SSBKeychain

+ (NSString *)baseConfigPath {
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scuttle"];
    [[NSFileManager defaultManager] createDirectoryAtPath:configPath 
                              withIntermediateDirectories:YES 
                                               attributes:@{NSFilePosixPermissions: @(0700)} 
                                                    error:nil];
    return configPath;
}

+ (BOOL)saveData:(NSData *)data toFile:(NSString *)filename {
    NSString *path = [[self baseConfigPath] stringByAppendingPathComponent:filename];
    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:nil];
    if (success) {
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)} 
                                         ofItemAtPath:path 
                                                error:nil];
    }
    return success;
}

+ (nullable NSData *)loadDataFromFile:(NSString *)filename {
    NSString *path = [[self baseConfigPath] stringByAppendingPathComponent:filename];
    return [NSData dataWithContentsOfFile:path];
}

+ (BOOL)deleteFile:(NSString *)filename {
    NSString *path = [[self baseConfigPath] stringByAppendingPathComponent:filename];
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

@end

#endif
```

### Files Stored

| File | Content | Permissions |
|------|---------|-------------|
| `identity.secret` | Ed25519 secret key (64 bytes) | 0600 |
| `network.key` | Network encryption key | 0600 |
| `metafeed.seed` | Metafeed seed data | 0600 |
| `metafeed.root_id` | Metafeed root ID string | 0600 |
| `metafeed.announced` | Announcement status | 0600 |
| `msg_count` | Published message count | 0600 |

### Storage Location

```
~/.config/scuttle/
├── identity.secret    # Private key (0600)
├── network.key       # Network key (0600)
├── metafeed.seed     # Metafeed seed (0600)
├── metafeed.root_id  # Metafeed root (0600)
└── metafeed.announced # Announcement flag (0600)
```

## SecRandomCopyBytes

### What's Needed

**File to Create:** `Sources/SSBSecurityCompat.h`

```c
#ifndef SSBSecurityCompat_h
#define SSBSecurityCompat_h

#ifdef __APPLE__
    #import <Security/Security.h>
#else
    #import <Foundation/Foundation.h>
    #include <openssl/rand.h>

    // OSStatus constants
    enum {
        errSecSuccess = 0,
        errSecAuthFailed = -25290,
        errSecItemNotFound = -25300,
        errSecDuplicateItem = -25299,
        errSecItemNotFound = -25300
    };
    typedef int32_t OSStatus;

    // SecRandomCopyBytes shim using OpenSSL
    static inline OSStatus SecRandomCopyBytes(void *bytes, size_t count) {
        if (RAND_bytes(bytes, count) == 1) {
            return errSecSuccess;
        }
        return errSecAuthFailed;
    }
#endif

#endif
```

### Usage in Scuttle

**Files using SecRandomCopyBytes:**

| File | Line | Usage |
|------|------|-------|
| `App/Logic/SRRoomManager.m` | 442 | Nonce generation |
| `Sources/SSBHTTPInviteServer.m` | 85 | Random index |
| `Sources/SSBHTTPAuth.m` | 156 | Nonce generation |
| `Sources/SSBMetafeed.m` | 64, 308 | Seed/key generation |
| `Sources/SSBIndexFeed.m` | 442 | Nonce generation |

### Current Pattern (macOS only)

```objc
#ifdef __APPLE__
    uint8_t nonce[32];
    SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce), nonce);
#else
    // Currently no fallback - would use arc4random_buf
#endif
```

### Recommended Fix

After creating `SSBSecurityCompat.h`, update files:

```objc
#import "SSBSecurityCompat.h"

// Now works on both platforms
uint8_t nonce[32];
SecRandomCopyBytes(nonce, sizeof(nonce));
```

## Security Considerations

### macOS Keychain

- Encrypted storage via Keychain
- Hardware-backed (Secure Enclave on newer Macs)
- Access control (`kSecAttrAccessibleWhenUnlocked`)

### Linux File-Based

- Relies on filesystem permissions
- `~/.config/scuttle/` with `0700` permissions
- Only owner can read/write
- No hardware backing

### Alternative for Production Linux

For production use, consider:

1. **GNOME Keyring** - Desktop integration
2. **libsecret** - D-Bus secret service
3. **SoftHSM** - Software HSM
4. **Linux keyring** - kernel keyctl interface

## Error Handling

### macOS Keychain Errors

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | errSecSuccess | Success |
| -25290 | errSecAuthFailed | Authentication failed |
| -25299 | errSecDuplicateItem | Item already exists |
| -25300 | errSecItemNotFound | Item not found |

### Linux File Errors

| Error | Meaning |
|-------|---------|
| nil return | File doesn't exist |
| Write fails | Permission denied or disk full |

## Summary

| Component | macOS | Linux | Status |
|-----------|-------|-------|--------|
| Keychain Storage | Security.framework | File-based | ✅ Complete |
| SecRandomCopyBytes | Security.framework | OpenSSL | ⚠️ Needs shim |
| Access Control | kSecAttrAccessible* | chmod 0600 | ✅ Sufficient |
| Hardware Backing | Secure Enclave | None | N/A |

## Recommendations

1. **Create** `SSBSecurityCompat.h` with `SecRandomCopyBytes` shim
2. **Update** files using `SecRandomCopyBytes` to include compat header
3. **Consider** libsecret integration for production deployments
4. **Document** security assumptions for Linux platform
