# Keychain Patterns

## Basic Keychain Operations

### Creating Base Query

```objc
// Sources/SSBKeychain.m lines 21-26
+ (NSMutableDictionary *)baseQuery {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = @"com.scuttlebutt.identity";
    return query;
}
```

### Saving Data

```objc
+ (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
    // Delete existing item first
    NSMutableDictionary *deleteQuery = [self baseQuery];
    deleteQuery[(__bridge id)kSecAttrAccount] = key;
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
    
    // Create new query
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}
```

### Loading Data

```objc
+ (nullable NSData *)loadDataForKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    
    if (status == errSecSuccess && result != NULL) {
        return (__bridge_transfer NSData *)result;
    }
    return nil;
}
```

### Deleting Data

```objc
+ (BOOL)deleteDataForKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}
```

## Scuttle Usage

### Store Identity

```objc
// Store secret key
[SSBKeychain saveData:secretKey forKey:@"SSBIdentitySecret"];
```

### Load Identity

```objc
// Load secret key
NSData *secretKey = [SSBKeychain loadDataForKey:@"SSBIdentitySecret"];
```

## Common Errors

### Error: Duplicate Item

```objc
// OSStatus: -25299 (errSecDuplicateItem)
// Fix: Delete existing item before adding new one
SecItemDelete(query);
SecItemAdd(query, NULL);
```

### Error: Item Not Found

```objc
// OSStatus: -25300 (errSecItemNotFound)
// Fix: Check return value, handle nil case
```

### Error: Accessibility Mismatch

```objc
// OSStatus: -25290 (errSecAuthFailed)
// Fix: Ensure device is unlocked when accessing
```

## Best Practices

1. **Always delete before adding** to avoid duplicate errors
2. **Use `kSecAttrAccessibleWhenUnlocked`** for private keys
3. **Check return values** - don't assume success
4. **Use `__bridge_transfer`** to manage CF/ARC memory
5. **Log errors** for debugging but never log actual secret data
