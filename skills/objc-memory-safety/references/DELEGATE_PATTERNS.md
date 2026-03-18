# Delegate Patterns in Objective-C

## Weak Delegates: The Standard

Delegates should ALWAYS be weak to prevent retain cycles:

```objc
// Correct - weak delegate
@property (nonatomic, weak, nullable) id<SSBRoomClientDelegate> delegate;
```

## Scuttle's Delegate Declarations

All delegates in Scuttle correctly use `weak`:

| File | Line | Declaration |
|------|------|-------------|
| `Sources/SSBRoomClient.h` | 37 | `@property (nonatomic, weak) id<SSBRoomClientDelegate> delegate;` |
| `Sources/SSBHTTPAuth.h` | 52 | `@property (nonatomic, weak, nullable) id<SSBHTTPAuthDelegate> delegate;` |
| `Sources/SSBConnectionFSM.h` | 31 | `@property (nonatomic, weak) id<SSBConnectionFSMDelegate> delegate;` |
| `App/UI/SRFeedViewController.h` | - | `@property (nonatomic, weak) id<SRFeedViewControllerDelegate> delegate;` |
| `App/UI/SRProfileViewController.h` | - | `@property (nonatomic, weak) id<SRProfileViewControllerDelegate> delegate;` |

## Common Delegate Mistakes

### Mistake 1: Strong Delegate

```objc
// WRONG - creates retain cycle if delegate holds strong ref back
@property (nonatomic, strong) id<MyDelegate> delegate;

// CORRECT
@property (nonatomic, weak) id<MyDelegate> delegate;
```

### Mistake 2: Forgetting Nullable

For delegates that may not be set:

```objc
// CORRECT - optional delegate
@property (nonatomic, weak, nullable) id<MyDelegate> delegate;
```

### Mistake 3: Not Checking Before Calling

```objc
// WRONG - may crash if delegate is nil
[self.delegate didFinishWithResult:result];

// CORRECT - check first
if ([self.delegate respondsToSelector:@selector(didFinishWithResult:)]) {
    [self.delegate didFinishWithResult:result];
}
```

## Delegate Call Patterns in Scuttle

### SSBRoomClient Delegate Calls

```objc
// Sources/SSBRoomClient.m - Always check before calling
if ([self.delegate respondsToSelector:@selector(roomClient:didReceiveMessage:)]) {
    [self.delegate roomClient:self didReceiveMessage:message];
}
```

### Network Delegate Pattern

```objc
// Network callbacks that need delegation
__weak typeof(self) weakSelf = self;
nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    if (state == nw_connection_state_ready) {
        if ([strongSelf.delegate respondsToSelector:@selector(roomClientDidConnect:)]) {
            [strongSelf.delegate roomClientDidConnect:strongSelf];
        }
    }
});
```

## Block-Based Callbacks vs Delegates

Use weak/strong for BOTH:

```objc
// Block callback - also needs weak/strong
@property (nonatomic, copy) void (^completionHandler)(id result);

// Delegate - already uses weak by default
@property (nonatomic, weak) id<SomeDelegate> delegate;
```
