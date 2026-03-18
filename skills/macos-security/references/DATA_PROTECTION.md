# Data Protection

## macOS Keychain Accessibility

### Constants

| Constant | When Accessible | Use Case |
|----------|-----------------|----------|
| `kSecAttrAccessibleWhenUnlocked` | User session active, screen unlocked | Most secrets (RECOMMENDED) |
| `kSecAttrAccessibleAfterFirstUnlock` | After first unlock, even if locked later | Background services |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | Device has passcode | Mobile (iOS) |
| `kSecAttrAccessibleThisDeviceOnly` | Same device, any state | Device-bound secrets |

### Current Scuttle Usage

```objc
// Sources/SSBKeychain.m line 51
query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;
```

This is CORRECT - private keys should only be accessible when the user is present.

## Why kSecAttrAccessibleWhenUnlocked

### Risks of AfterFirstUnlock

Using `kSecAttrAccessibleAfterFirstUnlock` (the previous Scuttle bug):

1. Background processes can read the key
2. Screen-locked Mac is vulnerable
3. Sleep mode doesn't protect
4. Any unsigned code can access

### When to Use Each

| Accessibility | Use For |
|--------------|---------|
| `WhenUnlocked` | Private keys, identity secrets |
| `AfterFirstUnlock` | Cache tokens, non-critical data |
| `ThisDeviceOnly` | Data that shouldn't leave device |

## File Protection (NSFileProtection)

For files containing sensitive data:

```objc
// Set file protection
NSError *error;
[[NSFileManager defaultManager] 
    setAttributes:@{NSFileProtectionKey: NSFileProtectionComplete}
    ofItemAtPath:path
    error:&error];
```

### Options

| Constant | Behavior |
|----------|----------|
| `NSFileProtectionComplete` | Encrypted, locked when device locked |
| `NSFileProtectionCompleteUnlessOpen` | Encrypted, but accessible when open |
| `NSFileProtectionNone` | No protection |

## NSUserDefaults

NOT SECURE for secrets:

- Stored in `~/Library/Preferences/`
- Plist format (XML or binary)
- World-readable by default
- Not encrypted

## Best Practices Summary

1. **Use Keychain** for all secrets with `kSecAttrAccessibleWhenUnlocked`
2. **Never use NSUserDefaults** for credentials
3. **Set file protection** for sensitive files
4. **Zero memory** after using sensitive data
5. **Don't log** secrets
6. **Use secure random** for key generation
