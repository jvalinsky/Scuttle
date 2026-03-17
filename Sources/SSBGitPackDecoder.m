#import "SSBGitPackDecoder.h"
#import "SSBGitObjectStore.h"
#import <zlib.h>

static const uint32_t kGitPackMagic = 0x5041434b; // "PACK"
static const uint32_t kGitPackVersion = 2;
static const NSUInteger kMaxGitObjectSize = 100 * 1024 * 1024; // 100MB safety limit
static const int kMaxDeltaRecursion = 50;

@implementation SSBGitObject
@end

@interface SSBGitPackDecoder ()
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) const uint8_t *bytes;
@property (nonatomic, assign) NSUInteger length;
@property (nonatomic, assign) uint32_t objectCount;
@end

@implementation SSBGitPackDecoder

- (instancetype)initWithData:(NSData *)data {
    if (self = [super init]) {
        if (data.length < 12 + 20) {
            return nil;
        }
        
        const uint32_t *header = (const uint32_t *)data.bytes;
        uint32_t magic = NSSwapBigIntToHost(header[0]);
        uint32_t version = NSSwapBigIntToHost(header[1]);
        
        if (magic != kGitPackMagic || version != kGitPackVersion) {
            return nil;
        }
        
        _data = data;
        _bytes = data.bytes;
        _length = data.length;
        _objectCount = NSSwapBigIntToHost(header[2]);
    }
    return self;
}

- (nullable SSBGitObject *)objectAtOffset:(uint64_t)offset {
    return [self objectAtOffset:offset recursionDepth:0];
}

- (nullable SSBGitObject *)objectAtOffset:(uint64_t)offset recursionDepth:(int)depth {
    if (depth > kMaxDeltaRecursion || offset >= _length) {
        return nil;
    }
    
    uint64_t currentOffset = offset;
    uint8_t c = _bytes[currentOffset++];
    
    SSBGitObjectType type = (c >> 4) & 7;
    uint64_t size = c & 15;
    uint64_t shift = 4;
    
    while (c & 0x80) {
        if (currentOffset >= _length || shift >= 64) return nil;
        c = _bytes[currentOffset++];
        size += (uint64_t)(c & 0x7f) << shift;
        shift += 7;
    }
    
    if (size > kMaxGitObjectSize) return nil;
    
    if (type == SSBGitObjectTypeOfsDelta || type == SSBGitObjectTypeRefDelta) {
        if (type == SSBGitObjectTypeOfsDelta) {
            if (currentOffset >= _length) return nil;
            c = _bytes[currentOffset++];
            uint64_t baseOffset = c & 127;
            while (c & 128) {
                if (currentOffset >= _length) return nil;
                baseOffset += 1;
                c = _bytes[currentOffset++];
                baseOffset = (baseOffset << 7) + (c & 127);
            }
            if (baseOffset > offset) return nil;
            uint64_t targetOffset = offset - baseOffset;
            
            NSData *deltaData = [self decompressDataAtOffset:&currentOffset expectedSize:size];
            if (!deltaData) return nil;
            
            SSBGitObject *baseObj = [self objectAtOffset:targetOffset recursionDepth:depth + 1];
            if (!baseObj) return nil;
            
            NSData *resolvedData = [self applyDelta:deltaData toBase:baseObj.data];
            if (!resolvedData) return nil;
            
            SSBGitObject *obj = [[SSBGitObject alloc] init];
            obj.type = baseObj.type;
            obj.data = resolvedData;
            return obj;
        } else {
            // REF_DELTA implementation
            if (currentOffset + 20 > _length) return nil;
            NSData *baseSha1Data = [NSData dataWithBytes:(_bytes + currentOffset) length:20];
            currentOffset += 20;
            
            if (!self.objectStore) return nil;
            
            NSMutableString *hexSha1 = [NSMutableString stringWithCapacity:40];
            const uint8_t *shaBytes = baseSha1Data.bytes;
            for (int i = 0; i < 20; i++) {
                [hexSha1 appendFormat:@"%02x", shaBytes[i]];
            }
            
            NSData *deltaData = [self decompressDataAtOffset:&currentOffset expectedSize:size];
            if (!deltaData) return nil;
            
            SSBGitObject *baseObj = [self.objectStore objectForSHA1:hexSha1];
            if (!baseObj) return nil;
            
            NSData *resolvedData = [self applyDelta:deltaData toBase:baseObj.data];
            if (!resolvedData) return nil;
            
            SSBGitObject *obj = [[SSBGitObject alloc] init];
            obj.type = baseObj.type;
            obj.data = resolvedData;
            return obj;
        }
    } else {
        NSData *decompressed = [self decompressDataAtOffset:&currentOffset expectedSize:size];
        if (!decompressed) return nil;
        
        SSBGitObject *obj = [[SSBGitObject alloc] init];
        obj.type = type;
        obj.data = decompressed;
        return obj;
    }
}

- (nullable NSData *)decompressDataAtOffset:(uint64_t *)offset expectedSize:(uint64_t)expectedSize {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    if (inflateInit(&strm) != Z_OK) {
        return nil;
    }
    
    strm.next_in = (Bytef *)(_bytes + *offset);
    strm.avail_in = (uInt)(_length - *offset);
    
    NSMutableData *outData = [NSMutableData dataWithLength:(NSUInteger)expectedSize];
    strm.next_out = outData.mutableBytes;
    strm.avail_out = (uInt)expectedSize;
    
    int ret = inflate(&strm, Z_FINISH);
    
    *offset += strm.total_in;
    inflateEnd(&strm);
    
    if (ret != Z_STREAM_END && ret != Z_OK) {
        return nil;
    }
    
    return outData;
}

- (nullable NSData *)applyDelta:(NSData *)delta toBase:(NSData *)base {
    if (!delta || !base) return nil;
    const uint8_t *deltaBytes = delta.bytes;
    NSUInteger deltaLen = delta.length;
    NSUInteger deltaOffset = 0;
    
    // Read source size
    uint64_t sourceSize = 0;
    uint64_t shift = 0;
    uint8_t c;
    do {
        if (deltaOffset >= deltaLen || shift >= 64) return nil;
        c = deltaBytes[deltaOffset++];
        sourceSize |= (uint64_t)(c & 0x7f) << shift;
        shift += 7;
    } while (c & 0x80);
    
    if (sourceSize != base.length) return nil;
    
    // Read target size
    uint64_t targetSize = 0;
    shift = 0;
    do {
        if (deltaOffset >= deltaLen || shift >= 64) return nil;
        c = deltaBytes[deltaOffset++];
        targetSize |= (uint64_t)(c & 0x7f) << shift;
        shift += 7;
    } while (c & 0x80);
    
    if (targetSize > kMaxGitObjectSize) return nil;
    
    NSMutableData *result = [NSMutableData dataWithCapacity:(NSUInteger)targetSize];
    if (!result) return nil;
    
    while (deltaOffset < deltaLen) {
        c = deltaBytes[deltaOffset++];
        if (c & 0x80) {
            // Copy from base
            uint64_t cp_off = 0;
            uint64_t cp_size = 0;
            if (c & 0x01) { if (deltaOffset >= deltaLen) return nil; cp_off |= deltaBytes[deltaOffset++]; }
            if (c & 0x02) { if (deltaOffset >= deltaLen) return nil; cp_off |= (uint64_t)deltaBytes[deltaOffset++] << 8; }
            if (c & 0x04) { if (deltaOffset >= deltaLen) return nil; cp_off |= (uint64_t)deltaBytes[deltaOffset++] << 16; }
            if (c & 0x08) { if (deltaOffset >= deltaLen) return nil; cp_off |= (uint64_t)deltaBytes[deltaOffset++] << 24; }
            if (c & 0x10) { if (deltaOffset >= deltaLen) return nil; cp_size |= deltaBytes[deltaOffset++]; }
            if (c & 0x20) { if (deltaOffset >= deltaLen) return nil; cp_size |= (uint64_t)deltaBytes[deltaOffset++] << 8; }
            if (c & 0x40) { if (deltaOffset >= deltaLen) return nil; cp_size |= (uint64_t)deltaBytes[deltaOffset++] << 16; }
            if (cp_size == 0) cp_size = 0x10000;
            
            if (cp_off + cp_size > base.length || cp_off + cp_size < cp_off) return nil;
            if (result.length + cp_size > targetSize) return nil;
            [result appendBytes:((const uint8_t *)base.bytes + cp_off) length:(NSUInteger)cp_size];
        } else if (c != 0) {
            // Copy from delta
            if (deltaOffset + c > deltaLen) return nil;
            if (result.length + c > targetSize) return nil;
            [result appendBytes:(deltaBytes + deltaOffset) length:c];
            deltaOffset += c;
        } else {
            return nil; // Unexpected zero
        }
    }
    
    if (result.length != targetSize) return nil;
    return result;
}

@end
