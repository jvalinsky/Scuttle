#import <XCTest/XCTest.h>
#import "SSBSecretStore.h"

@interface SSBSecretStoreTests : XCTestCase
@end

@implementation SSBSecretStoreTests

- (void)testFileSecretStoreRoundTripsData {
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    SSBFileSecretStore *store = [[SSBFileSecretStore alloc] initWithBaseDirectory:tempRoot];

    NSData *payload = [@"secret-payload" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([store saveData:payload forKey:@"identity.secret"]);

    NSData *loaded = [store loadDataForKey:@"identity.secret"];
    XCTAssertEqualObjects(loaded, payload);

    XCTAssertTrue([store deleteDataForKey:@"identity.secret"]);
    XCTAssertNil([store loadDataForKey:@"identity.secret"]);
    XCTAssertTrue([store clearAll]);
}

- (void)testFileSecretStoreWritesPrivatePermissions {
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    SSBFileSecretStore *store = [[SSBFileSecretStore alloc] initWithBaseDirectory:tempRoot];

    XCTAssertTrue([store saveData:[@"x" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"permissions.test"]);

    NSString *path = [tempRoot stringByAppendingPathComponent:@"permissions.test"];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *permissions = attributes[NSFilePosixPermissions];

    XCTAssertEqual(permissions.unsignedShortValue, (unsigned short)0600);
    XCTAssertTrue([store clearAll]);
}

@end
