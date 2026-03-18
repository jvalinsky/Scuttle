# Weak/Strong Reference Patterns

## The Weak-Strong Dance

The standard pattern for avoiding retain cycles in blocks:

```objc
__weak typeof(self) weakSelf = self;
[asyncOperationWithBlock:^(id result) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    // Now use strongSelf instead of self
    [strongSelf handleResult:result];
}];
```

## When to Use Each Pattern

### Pattern 1: Fire-and-Forget (No Return Value Needed)

Use when the block doesn't need to return anything to the caller.

```objc
__weak typeof(self) weakSelf = self;
[networkClient fetchData:^(NSData *data) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    [strongSelf updateUIWithData:data];
}];
```

### Pattern 2: Completion Handler (Return Value Needed)

Use when block has a parameter that caller needs.

```objc
__weak typeof(self) weakSelf = self;
[service fetchUserWithCompletion:^(SSBUser *user, NSError *err) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    if (err) {
        [strongSelf handleError:err];
    } else {
        completion(user);  // Return to original caller
    }
}];
```

### Pattern 3: Property Assignment

Use when assigning to a property inside the block.

```objc
__weak typeof(self) weakSelf = self;
self.connection = [self createConnectionWithHandler:^(id data) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    strongSelf.latestData = data;  // Use strongSelf for property
    [strongSelf didReceiveData];
}];
```

### Pattern 4: Delegation

Use when calling delegate methods from within a block.

```objc
__weak typeof(self) weakSelf = self;
[parser parseData:data completion:^(id result) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    if ([strongSelf.delegate respondsToSelector:@selector(parserDidFinish:)]) {
        [strongSelf.delegate parserDidFinish:result];
    }
}];
```

## Common Mistakes

### Mistake 1: Forgetting the Strong Check

```objc
// BAD - if weakSelf becomes nil, crash or unexpected behavior
__weak typeof(self) weakSelf = self;
[block:^{
    [weakSelf doSomething];  // May be nil
}];

// GOOD - explicit nil check
__weak typeof(self) weakSelf = self;
[block:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf doSomething];
}];
```

### Mistake 2: Using __block Instead of weak

```objc
// BAD - __block doesn't prevent retain
__block typeof(self) blockSelf = self;
[block:^{
    [blockSelf doSomething];  // Still retained
}];

// GOOD - weak prevents retain
__weak typeof(self) weakSelf = self;
```

### Mistake 3: Not Using Weak in Nested Blocks

```objc
// BAD - inner block captures weakSelf strongly
__weak typeof(self) weakSelf = self;
[firstBlock:^{
    [secondBlock:^{
        [weakSelf doSomething];  // Creates strong reference
    }];
}];

// GOOD - use strongSelf in inner block
__weak typeof(self) weakSelf = self;
[firstBlock:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [secondBlock:^{
        [strongSelf doSomething];
    }];
}];
```

## Network Framework Specific

Apple's Network.framework (nw_connection) callbacks require special attention:

```objc
// Correct pattern for Network.framework
__weak typeof(self) weakSelf = self;
nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    if (state == nw_connection_state_ready) {
        [strongSelf handleReady];
    }
});
```
