#import <XCTest/XCTest.h>
#import "SSBMessageCodec.h"
#import "../Sources/tweetnacl.h"

@interface SSBMessageCodec (TestAccess)
+ (nullable NSString *)encodeLegacyValueToString:(NSDictionary *)value includeSignature:(BOOL)includeSig;
@end

@interface SSBProtocolVerificationTests : XCTestCase
@end

@implementation SSBProtocolVerificationTests

- (void)testVerifyMessageWithNonStandardKeyOrder {
    unsigned char pk[32];
    unsigned char sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    
    NSData *publicKeyData = [NSData dataWithBytes:pk length:32];
    NSData *secretKeyData = [NSData dataWithBytes:sk length:64];
    
    NSString *author = [NSString stringWithFormat:@"@%@.ed25519", [publicKeyData base64EncodedStringWithOptions:0]];
    
    NSDictionary *content = @{@"type": @"post", @"text": @"Hello"};
    
    NSDictionary *standardMsg = [SSBMessageCodec createSignedMessageWithContent:content author:author sequence:1 previousKey:nil secretKey:secretKeyData];
    NSData *standardData = [SSBMessageCodec encodeLegacyValue:standardMsg includeSignature:YES];
    
    XCTAssertTrue([[SSBMessageCodec sharedCodec] verifyMessageData:standardData error:nil], @"Standard order should verify");
    
    // Now manually swap "author" and "sequence" in the JSON string
    // Standard order from encodeLegacyValueToString: previous, author, sequence, timestamp, hash, content, signature
    // We'll swap "author" and "sequence".
    
    NSString *standardStr = [[NSString alloc] initWithData:standardData encoding:NSUTF8StringEncoding];
    
    // Find the sequence and author lines
    // "previous": null,
    // "author": "@...",
    // "sequence": 1,
    
    // This is brittle but works for this controlled test
    NSString *authorLine = [NSString stringWithFormat:@"  \"author\": \"%@\",", author];
    NSString *seqLine = @"  \"sequence\": 1,";
    
    NSString *swappedStr = [standardStr stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%@\n%@", authorLine, seqLine]
                                                              withString:[NSString stringWithFormat:@"%@\n%@", seqLine, authorLine]];
    
    NSData *swappedData = [swappedStr dataUsingEncoding:NSUTF8StringEncoding];
    
    // THIS SHOULD FAIL with current implementation because it re-encodes into standard order
    // But wait! If we re-encode into standard order, and the original signature was for standard order, 
    // it will actually SUCCEED verification even if the input was out of order!
    // BECAUSE we re-canonicalize it.
    
    XCTAssertTrue([[SSBMessageCodec sharedCodec] verifyMessageData:swappedData error:nil], 
                  @"Current implementation is TOO tolerant because it re-canonicalizes everything into standard order, masking the original order.");
    
    // THE REAL PROBLEM: What if the signature was created for the NON-standard order?
    // We will manually sign a non-standard order string.
    
    NSString *nonStandardMsg = [NSString stringWithFormat:@"{\n"
    "  \"previous\": null,\n"
    "  \"sequence\": 1,\n" // sequence before author
    "  \"author\": \"%@\",\n"
    "  \"timestamp\": 1514517067954,\n"
    "  \"hash\": \"sha256\",\n"
    "  \"content\": {\n"
    "    \"type\": \"post\",\n"
    "    \"text\": \"Non-standard order\"\n"
    "  }\n"
    "}", author];
    
    NSString *sig = [SSBMessageCodec signString:nonStandardMsg withSecretKey:secretKeyData];
    NSString *nonStandardFull = [nonStandardMsg stringByReplacingOccurrencesOfString:@"\n}" withString:[NSString stringWithFormat:@",\n  \"signature\": \"%@\"\n}", sig]];
    
    NSData *nonStandardData = [nonStandardFull dataUsingEncoding:NSUTF8StringEncoding];
    
    // This should now SUCCEED with the fix
    XCTAssertTrue([[SSBMessageCodec sharedCodec] verifyMessageData:nonStandardData error:nil], 
                   @"Verification should succeed for non-standard order if we use original bytes.");
}

@end
