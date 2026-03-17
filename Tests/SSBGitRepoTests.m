#import <XCTest/XCTest.h>
#import "SSBGitRepo.h"
#import "SSBFeedStore.h"
#import "SSBGitObjectStore.h"
#import "SSBBlobStore.h"

@interface SSBGitRepoTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, strong) SSBGitObjectStore *objectStore;
@property (nonatomic, strong) SSBGitRepo *repo;
@end

@implementation SSBGitRepoTests

- (void)setUp {
    [super setUp];
    
    // In a real test, we would use an in-memory db or a test path.
    NSString *dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.feedStore = [[SSBFeedStore alloc] initWithPath:dbPath];
    self.objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:[SSBBlobStore sharedStore]];
    self.repo = [[SSBGitRepo alloc] initWithRepoID:@"%testrepo.sha256" feedStore:self.feedStore objectStore:self.objectStore];
}

- (void)tearDown {
    [self.feedStore wipeDatabase];
    [super tearDown];
}

- (void)testCurrentRefsEmpty {
    NSDictionary *refs = [self.repo currentRefs];
    XCTAssertEqual(refs.count, 0, @"Expected no refs for an empty repo");
}

- (void)testUpdateMessagesEmpty {
    NSArray *updates = [self.repo updateMessages];
    XCTAssertEqual(updates.count, 0, @"Expected no update messages");
}

@end
