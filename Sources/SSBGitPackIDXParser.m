#import "SSBGitPackIDXParser.h"

static const uint32_t kGitIdxMagic = 0xff744f63;
static const uint32_t kGitIdxVersion = 2;

@interface SSBGitPackIDXParser ()
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) const uint8_t *bytes;
@property (nonatomic, assign) NSUInteger length;
@property (nonatomic, assign) uint32_t objectCount;
@end

@implementation SSBGitPackIDXParser

- (instancetype)initWithData:(NSData *)data {
    if (self = [super init]) {
        if (data.length < 8 + 256 * 4 + 40) {
            return nil;
        }
        
        const uint32_t *header = (const uint32_t *)data.bytes;
        uint32_t magic = NSSwapBigIntToHost(header[0]);
        uint32_t version = NSSwapBigIntToHost(header[1]);
        
        if (magic != kGitIdxMagic || version != kGitIdxVersion) {
            return nil;
        }
        
        _data = data;
        _bytes = data.bytes;
        _length = data.length;
        
        // The last entry in the fanout table (index 255) contains the total object count
        const uint32_t *fanout = (const uint32_t *)(_bytes + 8);
        _objectCount = NSSwapBigIntToHost(fanout[255]);
        
        // Minimal validation of total size
        // 8 header + 1024 fanout + N*20 SHA1 + N*4 CRC + N*4 Offset + 40 trailers
        // N * (20 + 4 + 4) = N * 28. uint32_t max * 28 fits in NSUInteger on 64-bit.
        NSUInteger minRequired = 1032 + _objectCount * 28 + 40;
        if (_length < minRequired) {
            return nil;
        }
    }
    return self;
}

- (uint64_t)offsetForSHA1:(NSData *)sha1 {
    if (sha1.length != 20 || _objectCount == 0) {
        return 0;
    }
    
    const uint8_t *searchBytes = sha1.bytes;
    uint8_t firstByte = searchBytes[0];
    
    const uint32_t *fanout = (const uint32_t *)(_bytes + 8);
    
    uint32_t startIdx = (firstByte == 0) ? 0 : NSSwapBigIntToHost(fanout[firstByte - 1]);
    uint32_t endIdx = NSSwapBigIntToHost(fanout[firstByte]);
    
    if (startIdx == endIdx) {
        return 0; // Not found
    }
    
    const uint8_t *sha1Table = _bytes + 1032;
    
    // Binary search
    uint32_t left = startIdx;
    uint32_t right = endIdx - 1;
    uint32_t foundIdx = UINT32_MAX;
    
    while (left <= right) {
        uint32_t mid = left + (right - left) / 2;
        const uint8_t *midSha1 = sha1Table + (mid * 20);
        int cmp = memcmp(searchBytes, midSha1, 20);
        
        if (cmp == 0) {
            foundIdx = mid;
            break;
        } else if (cmp < 0) {
            if (mid == 0) break;
            right = mid - 1;
        } else {
            left = mid + 1;
        }
    }
    
    if (foundIdx == UINT32_MAX) {
        return 0;
    }
    
    // Read offset
    const uint8_t *offsetTable = sha1Table + (_objectCount * 20) + (_objectCount * 4);
    uint32_t offset32 = NSSwapBigIntToHost(*(const uint32_t *)(offsetTable + (foundIdx * 4)));
    
    if (offset32 & 0x80000000) {
        // Large offset
        uint32_t largeOffsetIdx = offset32 & 0x7fffffff;
        const uint8_t *largeOffsetTable = offsetTable + (_objectCount * 4);
        
        // Ensure we don't read out of bounds
        NSUInteger largeOffsetPos = (largeOffsetTable - _bytes) + (largeOffsetIdx * 8);
        if (largeOffsetPos + 8 > _length - 40) {
            return 0; // Invalid idx file
        }
        
        uint64_t offset64 = NSSwapBigLongLongToHost(*(const uint64_t *)(_bytes + largeOffsetPos));
        return offset64;
    }
    
    return offset32;
}

- (uint64_t)offsetForHexString:(NSString *)hexString {
    if (hexString.length != 40) return 0;
    
    NSMutableData *data = [NSMutableData dataWithCapacity:20];
    for (int i = 0; i < 40; i += 2) {
        NSString *byteString = [hexString substringWithRange:NSMakeRange(i, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        unsigned int byteValue;
        [scanner scanHexInt:&byteValue];
        uint8_t b = (uint8_t)byteValue;
        [data appendBytes:&b length:1];
    }
    return [self offsetForSHA1:data];
}

@end
