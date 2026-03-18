---
name: macos-security
description: macOS security best practices for Scuttle including Keychain usage, secure storage, cryptographic APIs, and common vulnerability patterns.
---

# macOS Security for Scuttle

This skill provides expertise in macOS security patterns including Keychain usage, secure storage, and identifying security vulnerabilities.

## When to Use This Skill

Use this skill when you are:
- Working with Keychain APIs
- Storing credentials or secrets
- Implementing cryptographic operations
- Reviewing code for security vulnerabilities
- Fixing security issues found in code review

## Key Issues in Scuttle

### Critical: Secrets in NSUserDefaults

**Found in:**
- `App/UI/SRMainSplitViewController.m` lines 67, 132
- `App/UI/SRPreferencesViewController.m` line 255
- `App/UI/SRDevPanelViewController.m` line 60
- `Sources/RoomStorage.m` lines 26-64

**Problem:**
```objc
// WRONG - NSUserDefaults is plaintext, world-readable
NSData *localSecret = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
```

**Fix:** Use Keychain:
```objc
// CORRECT - Keychain is encrypted
NSData *localSecret = [SSBKeychain loadDataForKey:@"SSBLocalIdentity"];
```

### Medium: Keychain Accessibility

**File:** `Sources/SSBKeychain.m` line 51

Uses `kSecAttrAccessibleWhenUnlocked` (correct, was previously `kSecAttrAccessibleAfterFirstUnlock`)

## Keychain Patterns

### Basic Operations

```objc
// Store data
+ (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    
    // Delete existing first
    SecItemDelete((__bridge CFDictionaryRef)query);
    
    // Add data
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

// Load data
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

// Delete data
+ (BOOL)deleteDataForKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}
```

### Accessibility Options

| Constant | When Accessible | Use Case |
|----------|-----------------|----------|
| `kSecAttrAccessibleWhenUnlocked` | User session active | Most secrets |
| `kSecAttrAccessibleAfterFirstUnlock` | After first unlock | Background daemons |
| `kSecAttrAccessibleWhenPasscodeSet` | Device has passcode | Mobile |
| `kSecAttrAccessibleThisDeviceOnly` | Same device only | Device-bound keys |

## Cryptographic APIs

### Ed25519 (Signing)

```objc
// Sources/SSBMessageCodec.m
- (NSData *)signContent:(NSData *)content withKey:(NSData *)secretKey {
    unsigned char sm[128];
    unsigned long long smlen;
    
    int ret = crypto_sign_ed25519(sm, &smlen, content.bytes, 
                                   content.length, secretKey.bytes);
    if (ret != 0) return nil;
    
    return [NSData dataWithBytes:smlen length:smlen];
}
```

### BLAKE Hashing

```objc
// Sources/SSBGabbyGrove.m
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t digest[32];
    blake2b256(digest, data.bytes, data.length);
    return [NSData dataWithBytes:digest length:32];
}
```

## Security Checklist

- [ ] Never store secrets in NSUserDefaults
- [ ] Use Keychain for all credentials
- [ ] Use `kSecAttrAccessibleWhenUnlocked` for private keys
- [ ] Use `_Atomic` or queues for cryptographic state
- [ ] Zero out sensitive data after use
- [ ] Never log secrets

## Reference Files

- [KEYCHAIN_PATTERNS.md](references/KEYCHAIN_PATTERNS.md) - Keychain usage
- [SECURITY_VULNERABILITIES.md](references/SECURITY_VULNERABILITIES.md) - Known issues
- [CRYPTO_API.md](references/CRYPTO_API.md) - Cryptographic operations
- [DATA_PROTECTION.md](references/DATA_PROTECTION.md) - Accessibility flags
