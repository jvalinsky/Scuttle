# Retain Cycles: Patterns and Fixes

## What is a Retain Cycle?

A retain cycle occurs when two objects hold strong references to each other, preventing deallocation. In Objective-C, blocks retain objects they capture. If `self` retains a block, and that block captures `self` strongly, you have a cycle.

## Problematic Patterns

### 1. Direct Self Capture in Block

**WRONG** - `SSBHTTPAuth.m lines 273-304`:
```objc
void (^signAndComplete)(void) = ^{
    dispatch_async(self.authQueue, ^{  // self retained by block
        NSString *signatureMessage = [self signatureMessageWithServerId:self.serverId
                                                                clientId:clientId
                                                    ...];
    };
};
```

**FIX** - Use weak/strong pattern:
```objc
__weak typeof(self) weakSelf = self;
void (^signAndComplete)(void) = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    dispatch_async(strongSelf.authQueue, ^{
        NSString *signatureMessage = [strongSelf signatureMessageWithServerId:strongSelf.serverId
                                                                       clientId:clientId
                                                           ...];
    });
};
```

### 2. Recursive Block Pattern

**WRONG** - `SSBRoomClient.m startReceivingMessages`:
```objc
- (void)startReceivingMessages {
    nw_connection_receive_message(self.connection, ^(...) {
        ...
        [self startReceivingMessages];  // Recursive, plus strong capture
    });
}
```

**FIX** - Already fixed with proper weak/strong pattern in codebase.

### 3. Property Assignment Inside Block

**WRONG** - `SSBRoomClient.m line 733`:
```objc
self.ebtRequestID = [session sendRequest:@[@"ebt", @"replicate"] args:@[args] type:@"duplex" completion:^(id err) {
    // Inside this block, should use strongSelf.ebtRequestID
}];
```

**FIX**:
```objc
__weak typeof(self) weakSelf = self;
self.ebtRequestID = [session sendRequest:@[@"ebt", @"replicate"] args:@[args] type:@"duplex" completion:^(id err) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    strongSelf.ebtRequestID = nil;  // Use strongSelf
}];
```

## Files with Issues

| File | Lines | Issue |
|------|-------|-------|
| `Sources/SSBHTTPAuth.m` | 273-304, 331, 484, 499, 561, 678, 808 | Direct self capture in dispatch_async blocks |
| `Sources/SSBRoomClient.m` | 733 | self.ebtRequestID inside callback |
| `Sources/SSBTunnelConnection.m` | 236 | self instead of strongSelf |

## Files with Correct Patterns

| File | Lines | Pattern |
|------|-------|---------|
| `Sources/SSBRoomClient.m` | 90-96, 155-180, 186-222, 241-282, 721-740 | Proper weak/strong |
| `Sources/SSBTunnelConnection.m` | 53-75, 97-108, 167-199, 226-247, 251-292 | Proper weak/strong |
| `Sources/SSBBlobStore.m` | 121-148 | Proper weak/strong |
| `Sources/App/UI/SRFeedViewController.m` | 56-65, 151-191, 260-280 | Proper weak/strong |
