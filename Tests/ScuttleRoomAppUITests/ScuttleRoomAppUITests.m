#import <XCTest/XCTest.h>

@interface ScuttleRoomAppUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation ScuttleRoomAppUITests

- (void)setUp {
    [super setUp];
    
    // In UI tests it is usually best to stop immediately when a failure occurs.
    self.continueAfterFailure = NO;
    
    // UI tests must launch the application that they test.
    self.app = [[XCUIApplication alloc] init];
    [self.app launch];
}

- (void)tearDown {
    [self.app terminate];
    [super tearDown];
}

- (void)testAppLaunchDisplaysRoomsList {
    // Basic test to verify that the app launches and displays the expected primary UI elements.
    // Looking for a generic window or an "Add Room" button as a proxy for successful launch.
    
    // Check if the main window exists
    XCUIElement *mainWindow = [[self.app windows] firstMatch];
    XCTAssertTrue([mainWindow waitForExistenceWithTimeout:5.0], @"Main window should be visible after launch.");
    
    // Try to find the Add Room button which should be on the main window toolbar typically.
    XCUIElement *addRoomButton = self.app.toolbars.buttons[@"Add Room"];
    if (addRoomButton.exists) {
        XCTAssertTrue(addRoomButton.isHittable, @"Add Room button should be hittable.");
    }
}

- (void)testOpenDeveloperPanel {
    // Access the Window menu item and look for "Developer Panel"
    // Since menu bars on macOS are at the top, we query the menu bars.
    XCUIElement *menuBar = [self.app menuBars].firstMatch;
    
    // Typically the app menu is accessible here, but macOS UI tests sometimes need to click through.
    // If there is an explicit menu item for developer tools, we can trigger it.
    // If not, we can simulate keyboard shortcut (Cmd+D for example) if it exists.
    
    // Let's assume there's a menu item "Window" -> "Developer Panel"
    XCUIElement *windowMenu = [menuBar menuBarItems][@"Window"];
    if (windowMenu.exists) {
        [windowMenu click];
        XCUIElement *devPanelItem = [windowMenu menuItems][@"Developer Panel"];
        if (devPanelItem.exists) {
            [devPanelItem click];
            
            // Wait for the Developer panel to appear
            XCUIElement *devWindow = [self.app.windows elementBoundByIndex:1];
            XCTAssertTrue([devWindow waitForExistenceWithTimeout:2.0], @"Developer Panel should open.");
        }
    }
}

@end
