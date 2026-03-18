# Security Vulnerabilities in Scuttle

## Critical: Private Key in NSUserDefaults

### Location

Found in multiple files:

| File | Line | Issue |
|------|------|-------|
| `App/UI/SRMainSplitViewController.m` | 67 | Reads identity from NSUserDefaults |
| `App/UI/SRMainSplitViewController.m` | 132 | Writes identity to NSUserDefaults |
| `App/UI/SRPreferencesViewController.m` | 255 | Preference storage |
| `App/UI/SRDevPanelViewController.m` | 60 | Development panel |
| `Sources/RoomStorage.m` | 26-64 | Room configuration |

### Problem

```objc
// WRONG: NSUserDefaults is plaintext, easily read by any process
NSData *localSecret = [[NSUserDefaults standardUserDefaults] 
    dataForKey:@"SSBLocalIdentity"];
```

NSUserDefaults stores data in:
- `~/Library/Preferences/com.scuttlebutt.scuttle.plist`
- Unencrypted XML/JSON
- World-readable by default

### Fix

```objc
// CORRECT: Use Keychain
NSData *localSecret = [SSBKeychain loadDataForKey:@"SSBLocalIdentity"];

// If not in Keychain, migrate from NSUserDefaults
if (!localSecret) {
    localSecret = [[NSUserDefaults standardUserDefaults] 
        dataForKey:@"SSBLocalIdentity"];
    if (localSecret) {
        [SSBKeychain saveData:localSecret forKey:@"SSBLocalIdentity"];
        [[NSUserDefaults standardUserDefaults] 
            removeObjectForKey:@"SSBLocalIdentity"];
    }
}
```

## Other Storage Issues

### Room Storage

**File:** `Sources/RoomStorage.m`

Stores room configuration including potentially sensitive data:

```objc
// Lines 26-64
- (instancetype)init {
    NSString *path = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES
    ) firstObject];
    path = [path stringByAppendingPathComponent:@"Scuttle/rooms.json"];
    // Stores in plaintext
}
```

**Fix:** Encrypt sensitive fields or use Keychain for secrets.

## What NOT to Store in NSUserDefaults

| Data Type | Risk | Storage |
|-----------|------|---------|
| Passwords | HIGH | Keychain |
| Private keys | CRITICAL | Keychain |
| API tokens | HIGH | Keychain |
| Session tokens | MEDIUM | Keychain or memory |
| User preferences | LOW | NSUserDefaults OK |
| UI state | LOW | NSUserDefaults OK |
| Cached data | LOW | NSUserDefaults OK |

## Logging Secrets

### Problem

```objc
// BAD - logs sensitive data
NSLog(@"Secret key: %@", secretKey);
os_log("Key: %{public}@", secretKey);  // Still visible in some contexts
```

### Fix

```objc
// GOOD - never log secrets
os_log("Key loaded, length: %d", secretKey.length);

// If debugging is needed:
#ifdef DEBUG
    NSLog(@"Key loaded: %d bytes", secretKey.length);
#endif
```

## Hardcoded Secrets

Search for:
- `APIKey`, `api_key`, `APIToken`
- `password`, `secret`, `credential`
- `Bearer `, `Basic ` in strings

```bash
# Find potential hardcoded secrets
grep -rn "password\|secret\|api.*key\|APIKEY" Sources/ --include="*.m"
```

## Secure Random

### Problem

```c
// BAD - not cryptographically secure
arc4random_uniform(n);
rand();
```

### Fix

```c
// GOOD - use SecRandomCopyBytes or TweetNaCl randombytes
#include "tweetnacl.h"
randombytes(buf, len);

// Or CommonCrypto
SecRandomCopyBytes(kSecRandomDefault, len, buf);
```
