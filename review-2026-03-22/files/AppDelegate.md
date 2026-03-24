# AppDelegate.m — Review Notes

[← Index](../index.md)

**Path:** `App/AppDelegate.m`
**Findings:** [H1](#h1) [H2](#h2)

---

## H1

**No-op `@try/@catch` re-throws exception** · [→ High findings](../high.md#h1)

Lines 56–63 in `applicationDidFinishLaunching:`.

```objc
@try {
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [self bringToFront:nil];
} @catch (NSException *exception) {
    @throw exception;   // ← no-op catch
}
```

None of these AppKit calls are documented to throw Objective-C exceptions under normal conditions. The catch block is dead code that signals intent to handle errors but does nothing. Remove the `@try/@catch` wrapper entirely.

---

## H2

**Window brought to front 6 times** · [→ High findings](../high.md#h2)

Lines 56–77. `makeKeyAndOrderFront:`, `orderFrontRegardless`, and `bringToFront:` appear in both the (to-be-removed) try block and in the `dispatch_async` block that loads `mainVC`. At the point of the try block, `window.contentViewController` is still a bare `[[NSViewController alloc] init]` placeholder — there is nothing meaningful to bring forward. The async block is the appropriate and sufficient place to show the window.

**Additional note:** `orderFrontRegardless` is an unusual choice for a normal app launch; `makeKeyAndOrderFront:` is the standard call. `orderFrontRegardless` bypasses the normal activation order and can steal focus from other apps unexpectedly.

---

## Other Observations

- `applicationWillFinishLaunching:` is empty (line 36–37). Fine for now, but consider removing it to reduce boilerplate if it's not needed.
- `- (instancetype)init` body is empty (lines 29–34). Can be removed — the compiler will synthesise a default init.
- The `#ifdef __APPLE__` guards around `NSStatusItem` (lines 14–18) suggest multi-platform aspirations, but the implementation file already contains macOS-only APIs throughout. The guards provide no practical benefit.
