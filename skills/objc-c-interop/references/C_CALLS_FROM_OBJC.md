# Calling C from Objective-C

## Direct Import Pattern

In Objective-C (.m files), you can directly import C headers:

```objc
#import "tweetnacl.h"
#import "blake2b.h"
#import "SSBDiffCore.h"
```

No bridging header needed because:
- These are pure C headers
- .m files support both ObjC and C syntax

## Example: TweetNaCl

```objc
// Sources/SSBMessageCodec.m
#import "tweetnacl.h"

@implementation SSBMessageCodec

- (NSData *)signContent:(NSData *)content withKey:(NSData *)secretKey {
    // Allocate signature buffer (64 bytes for Ed25519)
    unsigned char *signature = malloc(64);
    if (!signature) return nil;
    
    unsigned long long signatureLen;
    
    // Call C function
    int result = crypto_sign_ed25519(signature, &signatureLen,
                                      content.bytes, content.length,
                                      secretKey.bytes);
    
    if (result != 0) {
        free(signature);
        return nil;
    }
    
    NSData *sigData = [NSData dataWithBytesNoCopy:signature 
                                           length:signatureLen
                                     freeWhenDone:YES];
    return sigData;
}

@end
```

## Example: BLAKE2b

```objc
// Sources/SSBGabbyGrove.m
#import "blake2b.h"

+ (nullable NSData *)blake2b256:(NSData *)data {
    // Stack allocation for hash output
    uint8_t hash[32];
    
    int result = blake2b256(hash, data.bytes, data.length);
    if (result != 0) return nil;
    
    return [NSData dataWithBytes:hash length:32];
}
```

## Example: BLAKE3

```objc
// Sources/SSBButtwoo.m
#import "blake3.h"

- (NSData *)messageKeyForSequence:(uint32_t)seq 
                          author:(NSData *)author {
    uint8_t key[32];
    
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, author.bytes, author.length);
    
    uint8_t seqBE[4];
    seqBE[0] = (seq >> 24) & 0xFF;
    seqBE[1] = (seq >> 16) & 0xFF;
    seqBE[2] = (seq >> 8) & 0xFF;
    seqBE[3] = seq & 0xFF;
    blake3_hasher_update(&hasher, seqBE, 4);
    
    blake3_hasher_final(&hasher, key);
    
    return [NSData dataWithBytes:key length:32];
}
```

## Pattern Summary

| C Library | Import | Usage |
|-----------|--------|-------|
| TweetNaCl | `#import "tweetnacl.h"` | crypto_sign, crypto_box |
| BLAKE2b | `#import "blake2b.h"` | blake2b256 |
| BLAKE3 | `#import "blake3.h"` | blake3_hasher |
| SSBDiffCore | `#import "SSBDiffCore.h"` | ssb_diff |

## Notes

1. **Order matters**: Import C headers before ObjC classes that use them
2. **No namespace**: C functions are global, use prefixes to avoid conflicts
3. **Error handling**: Always check return values from C functions
4. **Memory**: Match all allocations with frees
