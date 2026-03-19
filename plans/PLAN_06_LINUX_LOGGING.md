# Plan 06: Linux Logging Compatibility (os/log Shim)

**Impact: 7/10** — Enables compilation on Linux by providing a drop-in replacement for Apple's unified logging.
**Difficulty: 3/10** — Simple preprocessor macros routing to NSLog.

---

## Overview

Scuttle uses `os/log` extensively for structured logging. This is an Apple-only framework. To support Linux without changing ~100 call sites, we will implement a shim that transparently routes these calls to `NSLog` when compiling on non-Apple platforms.

---

## Task 6.1: Create SSBLogCompat.h

### Status: ⏳ PENDING

**Priority:** High
**Scope:** 1 new header file
**Estimated complexity:** Low

### Subtasks
- [ ] Define `SSBLogCompat.h` in `Sources/`.
- [ ] Add `#ifdef __APPLE__` guard to preserve native `os/log.h` usage on macOS/iOS.
- [ ] For non-Apple platforms:
    - [ ] Type-alias `os_log_t` to `id` (or `NSString *`).
    - [ ] Define `os_log_create(subsystem, category)` to return a formatted string identifier.
    - [ ] Implement `os_log_info`, `os_log_error`, and `os_log_debug` macros.
- [ ] Ensure macros handle variadic arguments and strip Apple-specific `%{public}@` tokens if necessary (though `NSLog` may ignore them).

### Acceptance Criteria
- [ ] Header compiles on both macOS and a simulated Linux environment.
- [ ] `os_log_info(log, "test")` expands to a valid `NSLog` call on Linux.

---

## Task 6.2: Integrate Logging Shim

### Status: ⏳ PENDING

**Priority:** Medium
**Scope:** ~15 source files
**Estimated complexity:** Low

### Subtasks
- [ ] Identify all files importing `<os/log.h>`.
- [ ] Replace `#import <os/log.h>` with `#import "SSBLogCompat.h"`.
- [ ] Verify that files using `os_log_t` variables still compile on macOS.

### Acceptance Criteria
- [ ] All files using logging compile successfully on macOS with the new header.
- [ ] No regression in logging output on macOS.

---

## Summary Table

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| 6.1 | Create SSBLogCompat.h | ⏳ Pending | The core macro shim |
| 6.2 | Integrate Logging Shim | ⏳ Pending | Update source file imports |
