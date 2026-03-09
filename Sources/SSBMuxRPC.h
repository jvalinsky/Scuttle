#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(uint8_t, SSBMuxRPCFlags) {
    SSBMuxRPCFlagTypeBinary = 0x00,
    SSBMuxRPCFlagTypeString = 0x01,
    SSBMuxRPCFlagTypeJSON   = 0x02,
    SSBMuxRPCFlagEndErr     = 0x04,
    SSBMuxRPCFlagStream     = 0x08
};

/// Represents a single multiplexed RPC message header
@interface SSBMuxRPCMessage : NSObject

@property (nonatomic, assign) SSBMuxRPCFlags flags;
@property (nonatomic, assign) int32_t requestNumber;
@property (nonatomic, strong) NSData *body;

- (instancetype)initWithFlags:(SSBMuxRPCFlags)flags requestNumber:(int32_t)reqNum body:(NSData *)body;

/// Serializes the 9-byte header and body into a raw packet ready for Box Stream encryption
- (NSData *)serialize;

/// Attempts to parse a 9-byte header from the provided data. Returns the body length if successful, or 0 if incomplete.
+ (uint32_t)parseHeader:(NSData *)headerData outFlags:(SSBMuxRPCFlags *)outFlags outRequestNumber:(int32_t *)outReqNum;

@end

NS_ASSUME_NONNULL_END
