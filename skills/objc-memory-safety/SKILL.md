---
name: objc-memory-safety
description: Identify and fix Objective-C memory management issues including retain cycles, weak/strong reference patterns, and ARC best practices.
---

# Objective-C Memory Safety for Scuttle

This skill provides expertise in detecting and fixing Objective-C memory management issues, with a focus on retain cycles in blocks and proper weak/strong reference patterns.

## When to Use This Skill

Use this skill when you are:
- Writing new Objective-C code with blocks or closures
- Reviewing code for potential retain cycles
- Fixing memory leaks identified by Instruments
- Working with network callbacks or async operations
- Modifying delegate patterns

## Key Issues in Scuttle

### Critical: Retain Cycles Found

**SSBHTTPAuth.m** - Multiple blocks capturing `self` strongly:
- Lines 273-304: `signAndComplete` block directly captures `self`
- Lines 331, 484, 499, 561, 678, 808: Similar patterns

**SSBRoomClient.m line 733**: Inside callback block, `self.ebtRequestID` accessed without weak/strong

**SSBTunnelConnection.m line 236**: Uses `self` inside block that already has `strongSelf`

### Good Patterns Already in Codebase

**SSBRoomClient.m lines 90-96** - Correct weak/strong pattern:
```objc
__weak typeof(self) weakSelf = self;
_rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
    [weakSelf sendRPCMessage:message];
};
```

**SSBRoomClient.m lines 155-180** - Complete weak/strong dance:
```objc
__weak typeof(self) weakSelf = self;
nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    // ... use strongSelf
});
```

## Workflow: Fix Retain Cycle

1. **Identify block**: Find `^{` or `^(` that captures `self`
2. **Check property**: Verify delegate properties use `weak` (they should)
3. **Add weak/strong**:
   ```objc
   __weak typeof(self) weakSelf = self;
   [someAsyncThingWithBlock:^(id result) {
       __strong typeof(weakSelf) strongSelf = weakSelf;
       if (!strongSelf) return;
       [strongSelf doSomething];
   }];
   ```
4. **Verify delegate**: Ensure `@property (nonatomic, weak) id<SomeDelegate> delegate;`
5. **Test**: Run Instruments Leaks or Allocation instrument

## Reference Files

- [RETAIN_CYCLES.md](references/RETAIN_CYCLES.md) - Detailed patterns and fixes
- [WEAK_STRONG_PATTERNS.md](references/WEAK_STRONG_PATTERNS.md) - Correct usage examples
- [DELEGATE_PATTERNS.md](references/DELEGATE_PATTERNS.md) - Weak delegate best practices
- [MEMORY_AUDIT_CHECKLIST.md](references/MEMORY_AUDIT_CHECKLIST.md) - Audit protocol
