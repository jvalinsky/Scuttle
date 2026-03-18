# Memory Audit Checklist

Use this checklist when reviewing or auditing Objective-C code for memory management issues.

## Pre-Audit Preparation

- [ ] Enable **ARC** (Automatic Reference Counting) in project
- [ ] Set up **Instruments** with Leaks and Allocation templates
- [ ] Identify all files with blocks (look for `^` and `Block_copy`)

## Step 1: Identify Block Usages

For each .m file, search for:
- Block declarations: `^{`, `^(`, `void (^`
- Block properties: `@property (nonatomic, copy) void (^`
- Async methods: `dispatch_async`, `dispatch_after`, `performSelector`

## Step 2: Check for Retain Cycles

For each block found, verify:

- [ ] Does block capture `self`?
- [ ] If yes, is `__weak typeof(self) weakSelf = self;` used?
- [ ] Is `__strong typeof(weakSelf) strongSelf = weakSelf;` inside block?
- [ ] Is nil check `if (!strongSelf) return;` present?

## Step 3: Verify Delegate Properties

For each delegate property:

- [ ] Is declared as `weak`?
- [ ] Is nullable if optional?
- [ ] Are calls wrapped in `respondsToSelector:` check?

## Step 4: Check Property Attributes

- [ ] Blocks use `copy` attribute: `@property (nonatomic, copy) void (^completion)(id);`
- [ ] Delegates use `weak`: `@property (nonatomic, weak) id<Delegate> delegate;`
- [ ] No `strong` delegates

## Step 5: Runtime Verification

Build and test with:

1. **Instruments Leaks**:
   - Run app, navigate all flows
   - Check for growing memory
   - Look for leaks in block completion paths

2. **Instruments Allocations**:
   - Mark heap at known clean state
   - Navigate screens/flows
   - Compare heap growth

3. **Static Analysis**:
   ```bash
   xcodebuild -scheme Scuttle analyze
   ```
   Look for " retain cycle" warnings.

## Known High-Risk Areas in Scuttle

| File | Risk | Lines |
|------|------|-------|
| `Sources/SSBHTTPAuth.m` | HIGH | 273-304, 331, 484, 499, 561, 678, 808 |
| `Sources/SSBRoomClient.m` | MEDIUM | 733 |
| `Sources/SSBTunnelConnection.m` | LOW | 236 |

## Audit Output Template

```markdown
## File: [filename.m]

### Blocks Found: N

| Line | Captures Self | Weak Pattern | Status |
|------|---------------|---------------|--------|
| 100  | Yes           | Yes           | ✅ OK  |
| 150  | Yes           | No            | ❌ FIX |

### Delegates Found: N

| Property | Weak | Nullable | Status |
|----------|------|----------|--------|
| delegate | Yes  | N/A      | ✅ OK  |

### Action Items
- [ ] Fix line 150: Add weak/strong pattern
```

## Quick Scan Commands

```bash
# Find all blocks that might capture self
grep -n "^.*\^\s*(" Sources/*.m | grep -v weakSelf

# Find potential strong delegates  
grep -n "@property.*delegate" Sources/*.m | grep -v weak

# Find dispatch_async without weakSelf
grep -B5 "dispatch_async" Sources/*.m | grep -v weakSelf
```
