# AppKit Classes Compatibility

## Overview

GNUstep's GUI library provides **60-70% compatibility** with Apple's AppKit. Key differences include:
- **Coordinate system**: Bottom-left origin (OpenStep) vs top-left (macOS)
- **NIB/XIB**: Not supported - must build UI programmatically
- **Auto Layout**: Partial support
- **Graphics backends**: Cairo, Xlib, or Art

## Coordinate System Difference

### macOS (Top-Left Origin)
```
(0,0) ────────► x
  │
  │
  ▼ y
```

### GNUstep (Bottom-Left Origin)
```
  y ▲
    │
    │
    └──────────► x
(0,0)
```

### Converting Coordinates

```objc
// macOS to GNUstep
NSPoint macOSPoint = NSMakePoint(x, y);
NSPoint gnustepPoint = NSMakePoint(x, windowHeight - y);

// Using NSView bounds
NSPoint convertPoint = [view convertPoint:point fromView:nil];
```

## NSApplication

**Compatibility:** ✅ 80%

```objc
// Singleton
+ (NSApplication *)sharedApplication;
extern NSApplication *NSApp;

// Run loop
- (void)run;
- (void)stop:(id)sender;
@property (readonly) BOOL isRunning;

// Windows
@property (readonly) NSWindow *keyWindow;
@property (readonly) NSWindow *mainWindow;

// Delegate methods (same as macOS)
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
```

### Application Pattern

```objc
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setDelegate:[[MyDelegate alloc] init]];
        return NSApplicationMain(argc, argv);
    }
}
```

## NSWindow

**Compatibility:** ✅ 80%

```objc
// Init (same as macOS)
- (instancetype)initWithContentRect:(NSRect)contentRect 
                         styleMask:(NSWindowStyleMask)styleMask 
                           backing:(NSBackingStoreType)backing 
                             defer:(BOOL)flag;

// Content
- (void)setContentView:(NSView *)aView;
- (NSView *)contentView;

// Window management
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)close;
- (void)miniaturize:(id)sender;
- (void)zoom:(id)sender;

// Title
- (void)setTitle:(NSString *)aString;
- (NSString *)title;
```

### Style Masks

```objc
// Same as macOS
NSWindowStyleMaskTitled
NSWindowStyleMaskClosable  
NSWindowStyleMaskMiniaturizable
NSWindowStyleMaskResizable
```

## NSView

**Compatibility:** ✅ 80%

```objc
// Init
- (instancetype)initWithFrame:(NSRect)frameRect;

// Hierarchy
- (void)addSubview:(NSView *)aView;
- (void)removeFromSuperview;

// Frame and bounds
- (void)setFrame:(NSRect)frameRect;
- (NSRect)frame;
- (void)setBounds:(NSRect)boundsRect;
- (NSRect)bounds;

// Drawing
- (void)drawRect:(NSRect)dirtyRect;
- (void)setNeedsDisplay:(BOOL)flag;

// Coordinate conversion
- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)aView;
- (NSPoint)convertPoint:(NSPoint)point toView:(NSView *)aView;
```

### Resizing Masks

```objc
// Same as macOS
NSViewNotSizable;
NSViewWidthSizable;
NSViewHeightSizable;
NSViewMinXMargin;
NSViewMaxXMargin;
NSViewMinYMargin;
NSViewMaxYMargin;
```

## NSButton

**Compatibility:** ✅ 90%

```objc
// Init
- (instancetype)initWithFrame:(NSRect)frameRect;
- (instancetype)initWithTitle:(NSString *)title target:(id)target action:(SEL)action;

// Title and state
- (void)setTitle:(NSString *)aString;
- (NSString *)title;
- (void)setState:(NSInteger)value;
- (NSInteger)state;

// Button type
- (void)setButtonType:(NSButtonType)type;

// Target/Action
- (void)setTarget:(id)anObject;
- (void)setAction:(SEL)aSelector;
```

## NSTextField

**Compatibility:** ✅ 90%

```objc
// Init
- (instancetype)initWithFrame:(NSRect)frameRect;

// Text content
- (void)setStringValue:(NSString *)aString;
- (NSString *)stringValue;

// Formatting
- (void)setFont:(NSFont *)font;
- (void)setTextColor:(NSColor *)color;
- (void)setAlignment:(NSTextAlignment)alignment;

// Editing
- (void)setEditable:(BOOL)flag;
- (void)setSelectable:(BOOL)flag;
- (void)setBezeled:(BOOL)flag;
- (void)setDrawsBackground:(BOOL)flag;
```

## NSTableView

**Compatibility:** ✅ 85%

```objc
// Init
- (instancetype)initWithFrame:(NSRect)frameRect;

// Columns
- (void)addTableColumn:(NSTableColumn *)column;
- (NSArray *)tableColumns;

// Data source (same protocols as macOS)
- (void)setDataSource:(id)aSource;
- (void)setDelegate:(id)anObject;

// Selection
@property (readonly) NSInteger selectedRow;
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;

// Reloading
- (void)reloadData;
```

### Data Source Protocol (Same as macOS)

```objc
@protocol NSTableViewDataSource <NSObject>
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
@optional
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row;
@end
```

## NSMenu / NSMenuItem

**Compatibility:** ✅ 80%

```objc
// NSMenu
- (instancetype)initWithTitle:(NSString *)title;
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)keySequence;
- (void)setSubmenu:(NSMenu *)submenu forItem:(NSMenuItem *)item;

// NSMenuItem
+ (NSMenuItem *)separatorItem;
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)keyEquivalent;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
```

### Menu Bar Setup

```objc
- (void)setupMenuBar {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
    
    // File menu
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [fileItem setTitle:@"File"];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [fileItem setSubmenu:fileMenu];
    [mainMenu addItem:fileItem];
    
    [NSApp setMainMenu:mainMenu];
}
```

## NSBezierPath

**Compatibility:** ✅ 90%

```objc
// Creation
+ (NSBezierPath *)bezierPath;
+ (NSBezierPath *)bezierPathWithRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect;

// Path construction
- (void)moveToPoint:(NSPoint)point;
- (void)lineToPoint:(NSPoint)point;
- (void)closePath;

// Drawing
- (void)stroke;
- (void)fill;

// Styling
- (void)setLineWidth:(CGFloat)lineWidth;
- (void)setStrokeColor:(NSColor *)color;
- (void)setFillColor:(NSColor *)color;
```

## NSImage

**Compatibility:** ✅ 80%

```objc
// Creation
- (instancetype)initWithSize:(NSSize)size;
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (instancetype)initWithNamed:(NSString *)name;

// Drawing
- (void)drawAtPoint:(NSPoint)point;
- (void)drawInRect:(NSRect)rect;

// Properties
- (NSSize)size;
- (void)setSize:(NSSize)aSize;
```

## NSGraphicsContext

**Compatibility:** ✅ 80%

```objc
// Current context
+ (NSGraphicsContext *)currentContext;
+ (void)setCurrentContext:(NSGraphicsContext *)context;

// State management
- (void)saveGraphicsState;
- (void)restoreGraphicsState;

// CGContext access
- (CGContextRef)CGContext;
```

## Auto Layout (Constraints)

**Compatibility:** ⚠️ 60%

```objc
// Enable
[view setTranslatesAutoresizingMaskIntoConstraints:NO];

// Create constraints
NSLayoutConstraint *constraint = [NSLayoutConstraint 
    constraintWithItem:label
             attribute:NSLayoutAttributeLeading
             relatedBy:NSLayoutRelationEqual
                toItem:superview
             attribute:NSLayoutAttributeLeading
            multiplier:1.0
              constant:10.0];
[constraint setActive:YES];

// Visual format language
NSArray *constraints = [NSLayoutConstraint 
    constraintsWithVisualFormat:@"H:|-(10)-[label]-(10)-|"
                        options:0
                        metrics:nil
                          views:@{@"label": label}];
[superview addConstraints:constraints];
```

## NOT Supported

| Feature | Notes |
|---------|-------|
| NIB/XIB Loading | Must build UI programmatically |
| Touch Bar | Not applicable on Linux |
| Visual Effect Views | Not implemented |
| Drag & Drop (advanced) | Basic support only |
| Some TextKit features | Partial implementation |

## Summary

| Class | Compatibility | Notes |
|-------|--------------|-------|
| NSApplication | ✅ 80% | Same API |
| NSWindow | ✅ 80% | Coordinate system differs |
| NSView | ✅ 80% | Coordinate system differs |
| NSButton | ✅ 90% | Same API |
| NSTextField | ✅ 90% | Same API |
| NSTableView | ✅ 85% | Same protocols |
| NSMenu | ✅ 80% | X11 integration differs |
| NSBezierPath | ✅ 90% | Same API |
| NSImage | ✅ 80% | Backend-dependent |
| NSLayoutConstraint | ⚠️ 60% | Partial support |
| NIB/XIB | ❌ 0% | Not supported |
