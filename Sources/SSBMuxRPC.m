#import "SSBMuxRPC.h"

@implementation SSBMuxRPCMessage

- (instancetype)initWithFlags:(SSBMuxRPCFlags)flags requestNumber:(int32_t)reqNum body:(NSData *)body {
    self = [super init];
    if (self) {
        _flags = flags;
        _requestNumber = reqNum;
        _body = body ?: [NSData data];
    }
    return self;
}

- (NSData *)serialize {
    NSMutableData *packet = [NSMutableData dataWithCapacity:9 + self.body.length];
    
    // 1-byte flags
    uint8_t flags = self.flags;
    [packet appendBytes:&flags length:1];
    
    // 4-byte body length (big-endian)
    uint32_t len = CFSwapInt32HostToBig((uint32_t)self.body.length);
    [packet appendBytes:&len length:4];
    
    // 4-byte request number (big-endian)
    uint32_t reqNum = CFSwapInt32HostToBig((uint32_t)self.requestNumber);
    [packet appendBytes:&reqNum length:4];
    
    // Body bytes
    if (self.body.length > 0) {
        [packet appendData:self.body];
    }
    
    return packet;
}

+ (uint32_t)parseHeader:(NSData *)headerData outFlags:(SSBMuxRPCFlags *)outFlags outRequestNumber:(int32_t *)outReqNum {
    if (headerData.length < 9) return 0;
    
    const uint8_t *bytes = headerData.bytes;
    
    if (outFlags) *outFlags = bytes[0];
    
    uint32_t len = 0;
    memcpy(&len, bytes + 1, 4);
    len = CFSwapInt32BigToHost(len);
    
    if (outReqNum) {
        uint32_t reqNum = 0;
        memcpy(&reqNum, bytes + 5, 4);
        *outReqNum = (int32_t)CFSwapInt32BigToHost(reqNum);
    }
    
    return len;
}

@end
