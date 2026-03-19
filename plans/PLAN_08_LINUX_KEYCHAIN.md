# Plan 08: Linux Keychain Implementation

**Impact: 8/10** — Required for identity persistence on Linux.
**Difficulty: 6/10** — Requires implementing a secure POSIX-compliant file storage backend.

---

## Overview

The `SSBKeychain` class currently uses Apple's `Security.framework`. On Linux, we will implement a POSIX-compliant backend that stores keys in `~/.config/scuttle/` with strict `0600` permissions. This avoids a D-Bus dependency (libsecret) while maintaining high security.

---

## Task 8.1: Implementation Split (Refactor)

### Status: ⏳ PENDING

**Priority:** Medium
**Scope:** File system
**Estimated complexity:** Low

### Subtasks
- [ ] Rename `Sources/SSBKeychain.m` to `Sources/SSBKeychain_macOS.m`.
- [ ] Ensure `SSBKeychain.h` remains the common interface.

### Acceptance Criteria
- [ ] Xcode project updated to use `SSBKeychain_macOS.m`.
- [ ] Existing functionality on macOS is unchanged.

---

## Task 8.2: Implement SSBKeychain_Linux.m

### Status: ⏳ PENDING

**Priority:** High
**Scope:** 1 new source file
**Estimated complexity:** Medium

### Subtasks
- [ ] Create `Sources/SSBKeychain_Linux.m`.
- [ ] Implement `loadIdentitySecret`, `saveIdentitySecret:`, etc.
- [ ] Use `NSHomeDirectory()` and `stringByAppendingPathComponent:` to build the path to `~/.config/scuttle/`.
- [ ] Use `NSFileManager` to create the directory if missing.

### Acceptance Criteria
- [ ] Implementation follows the `SSBKeychain` interface exactly.
- [ ] Logic compiles under GNUstep.

---

## Task 8.3: Secure Permission Handling

### Status: ⏳ PENDING

**Priority:** High
**Scope:** `Sources/SSBKeychain_Linux.m`
**Estimated complexity:** Medium

### Subtasks
- [ ] Use `setAttributes:ofItemAtPath:error:` to set `NSFilePosixPermissions` to `0600` (read/write user only) for the secret file.
- [ ] Ensure the parent directory (`~/.config/scuttle/`) is set to `0700`.
- [ ] Add error checking to ensure keys are never written to a world-readable file.

### Acceptance Criteria
- [ ] Files created on Linux have `rw-------` permissions.
- [ ] Directories created on Linux have `rwx------` permissions.

---

## Summary Table

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| 8.1 | Implementation Split | ⏳ Pending | Prepare for platform-specific files |
| 8.2 | Implement SSBKeychain_Linux.m | ⏳ Pending | Core persistence logic |
| 8.3 | Secure Permission Handling | ⏳ Pending | Security hardening |
