#import <XCTest/XCTest.h>
#import "SRStyle.h"

@interface SRStyleTests : XCTestCase
@end

@implementation SRStyleTests

- (void)testFontTokensNonNil {
    XCTAssertNotNil([SRStyle headlineLargeFont]);
    XCTAssertNotNil([SRStyle headlineFont]);
    XCTAssertNotNil([SRStyle bodyFont]);
    XCTAssertNotNil([SRStyle captionFont]);
    XCTAssertNotNil([SRStyle caption2Font]);
    XCTAssertNotNil([SRStyle monoSmallFont]);
    XCTAssertNotNil([SRStyle monoMediumFont]);
}

- (void)testFontSizes {
    XCTAssertEqual([SRStyle headlineLargeFont].pointSize, 16.0);
    XCTAssertEqual([SRStyle headlineFont].pointSize, 13.0);
    XCTAssertEqual([SRStyle bodyFont].pointSize, 13.0);
    XCTAssertEqual([SRStyle captionFont].pointSize, 11.0);
    XCTAssertEqual([SRStyle caption2Font].pointSize, 10.0);
}

- (void)testSpacingTokens {
    XCTAssertEqual([SRStyle spacingXS], 4.0);
    XCTAssertEqual([SRStyle spacingSM], 8.0);
    XCTAssertEqual([SRStyle spacingMD], 12.0);
    XCTAssertEqual([SRStyle spacingLG], 16.0);
    XCTAssertEqual([SRStyle spacingXL], 20.0);
    XCTAssertEqual([SRStyle spacingXXL], 32.0);
}

- (void)testCornerRadiusTokens {
    XCTAssertEqual([SRStyle cornerRadiusSmall], 4.0);
    XCTAssertEqual([SRStyle cornerRadiusMedium], 8.0);
    XCTAssertEqual([SRStyle cornerRadiusLarge], 12.0);
    XCTAssertEqual([SRStyle cornerRadiusRound], 16.0);
}

- (void)testAvatarSizeTokens {
    XCTAssertEqual([SRStyle avatarSizeSmall], 28.0);
    XCTAssertEqual([SRStyle avatarSizeMedium], 32.0);
    XCTAssertEqual([SRStyle avatarSizeLarge], 48.0);
}

- (void)testColorTokensNonNil {
    XCTAssertNotNil([SRStyle cardBackgroundColor]);
    XCTAssertNotNil([SRStyle cardBorderColor]);
    XCTAssertNotNil([SRStyle surfaceColor]);
    XCTAssertNotNil([SRStyle accentColor]);
    XCTAssertNotNil([SRStyle dangerColor]);
    XCTAssertNotNil([SRStyle warningColor]);
    XCTAssertNotNil([SRStyle successColor]);
}

- (void)testStyleCardView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [SRStyle styleCardView:view];
    XCTAssertTrue(view.wantsLayer);
    XCTAssertEqual(view.layer.cornerRadius, 8.0);
}

- (void)testCreateAvatarView {
    NSView *view = [SRStyle createAvatarViewWithSize:20.0 hash:12345];
    XCTAssertNotNil(view);
    XCTAssertTrue(view.wantsLayer);
}

@end
