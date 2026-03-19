# Plan 09: GNUstep Build System (Linux Port)

**Impact: 10/10** — The foundation for the entire Linux port.
**Difficulty: 8/10** — Requires setting up GNUmakefile, managing dependencies, and cross-platform compilation.

---

## Overview

To compile Scuttle on Linux, we need a build system that interfaces with GNUstep `base` (Foundation) and links against required Linux libraries (`libdispatch`, `libcrypto`, `sqlite3`). We will use the standard `GNUmakefile` format.

---

## Task 9.1: Create GNUmakefile for Core Logic

### Status: ⏳ PENDING

**Priority:** High
**Scope:** Project root
**Estimated complexity:** Medium

### Subtasks
- [ ] Create a `GNUmakefile` in the root directory.
- [ ] Include `$(GNUSTEP_MAKEFILES)/common.make`.
- [ ] Define the tool name (e.g., `scuttle-daemon`).
- [ ] List all files in `Sources/` as `OBJC_FILES` or `C_FILES`.
- [ ] Exclude `SSBKeychain_macOS.m` and include `SSBKeychain_Linux.m`.

### Acceptance Criteria
- [ ] `make` command starts the compilation process on a Linux machine with GNUstep installed.

---

## Task 9.2: Dependency Configuration

### Status: ⏳ PENDING

**Priority:** High
**Scope:** `GNUmakefile`
**Estimated complexity:** Medium

### Subtasks
- [ ] Add flags for `libdispatch` (GCD on Linux).
- [ ] Add flags for `libcrypto` (OpenSSL).
- [ ] Add flags for `sqlite3`.
- [ ] Ensure `gnustep-base` flags are correctly included.

### Acceptance Criteria
- [ ] Linker successfully finds all required libraries on Linux.

---

## Task 9.3: Portable Prefix Header

### Status: ⏳ PENDING

**Priority:** Medium
**Scope:** Build configuration
**Estimated complexity:** Low

### Subtasks
- [ ] Create `Sources/SSBPrefix.h` (if not already existing) to include common shims.
- [ ] Ensure the GNUmakefile uses this prefix header during compilation.

---

## Summary Table

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| 9.1 | Create GNUmakefile | ⏳ Pending | Standard GNUstep build file |
| 9.2 | Dependency Config | ⏳ Pending | Linker and header paths |
| 9.3 | Portable Prefix Header | ⏳ Pending | Global shim injection |
