# GNUstep Linux Port — Hypotheses & Results Scratchpad

**Status:** In Progress (2026-03-23)
**Branch:** claude/ssb-room-docker-debug-0AFz4
**Deciduous:** See nodes 1, 9 and connected subgraph

---

## Overview

We are porting Scuttle (an Objective-C SSB client) from macOS to Linux using GNUstep.
The build system (`GNUmakefile`) compiles `scuttle-cli` — a headless CLI for identity
management, room connection, and feed replication.

This document tracks porting hypotheses, test results, and debugging notes as we
validate the CLI against a live `go-ssb-room` Docker instance.

---

## Infrastructure Status

| Component | Status | Notes |
|-----------|--------|-------|
| `GNUmakefile` | ✅ Exists | Compiles `scuttle-cli` with GNUstep |
| `docker-compose.yml` | ✅ Updated | Adds GNUstep build container |
| `tmp-room/Dockerfile` | ✅ Created | Production go-ssb-room image |
| `tmp-room/Dockerfile.dev` | ✅ Created | Dev/debug image with healthcheck |
| `docker/Dockerfile.gnustep` | ✅ Created | Ubuntu 22.04 + GNUstep + OpenSSL |
| `SSBLogCompat.h` | ✅ Exists | `os/log` → `NSLog` shim |
| `SSBCommonCryptoCompat.h` | ✅ Exists | `CommonCrypto` → OpenSSL shim |
| `SSBKeychain_Linux.m` | ✅ Exists | POSIX file-based keychain |
| Debug harness | ✅ Created | `tools/debug/ssb-room-harness.sh` |

---

## Hypothesis Log

### H-001: GNUstep libdispatch dispatch_data_t API differences

**Hypothesis:** GNUstep's `libdispatch` implementation may differ from Apple's in
`dispatch_data_t` handling. Specifically, `dispatch_data_apply` callback signature
or `dispatch_data_create_map` behavior may differ.

**Files at Risk:** `SSBBoxStream.m`, `SSBMuxRPCFramer.m`, `SSBTransport.m`

**Test:**
```bash
grep -r "dispatch_data" Sources/ --include="*.m" | head -20
```

**Status:** UNTESTED — Need to attempt Linux build to observe actual failures.

**Resolution Path:**
- If `dispatch_data_apply` fails: wrap in `#ifdef __APPLE__` and use `NSData` on Linux
- If `dispatch_data_create_map` fails: replace with `[NSData dataWithBytes:ptr length:len]`

---

### H-002: NSURLSession availability on GNUstep

**Hypothesis:** `NSURLSession` is partially implemented in GNUstep base but may lack
`dataTaskWithRequest:completionHandler:` or have different behavior for HTTPS.

**Files at Risk:** `SSBURLSessionShim.m`, `RoomInviteHandler.m`

**Test:**
```bash
grep -r "NSURLSession" Sources/ App/ --include="*.m" | head -10
```

**Status:** UNTESTED

**Resolution Path:**
- If `NSURLSession` missing: use `NSURLConnection` (older API, still in GNUstep)
- Or: use `libcurl` with a thin ObjC wrapper class

---

### H-003: `@autoreleasepool` with ARC on GNUstep

**Hypothesis:** ARC + `@autoreleasepool` on GNUstep may behave differently in
concurrent dispatch contexts. GNUstep uses a slightly different ARC runtime.

**Files at Risk:** All dispatch_async blocks

**Test:** Run `scuttle-cli whoami` under Valgrind on Linux, check for leaks.

**Status:** UNTESTED

**Resolution Path:**
- Ensure all `dispatch_async` blocks have explicit `@autoreleasepool`
- Avoid `__weak` references across dispatch queues (use `__block __strong`)

---

### H-004: `os_log` variadic format strings on GNUstep

**Hypothesis:** The `SSBLogCompat.h` shim uses `NSLog` for non-Apple platforms.
The Apple-style `%{public}@` and `%{private}@` format specifiers in existing
`os_log_*` calls will be passed literally to `NSLog`, causing garbled output.

**Files at Risk:** Any file using `os_log_info(log, "%{public}@ connected", peer)`

**Test:**
```bash
grep -r '%{public}' Sources/ --include="*.m" | wc -l
grep -r '%{private}' Sources/ --include="*.m" | wc -l
```

**Status:** UNTESTED — Check counts and decide if shim needs stripping.

**Resolution Path:**
- Option A: Enhance `SSBLogCompat.h` macros to strip `%{public}` tokens via
  a compile-time format transformation (complex, may not be necessary)
- Option B: Accept garbled format but still functional output (simple, acceptable)
- Option C: Replace `%{public}@` with `%@` in source files that need Linux support

---

### H-005: SecretHandshake HMAC-SHA512-256 on OpenSSL

**Hypothesis:** The SSB Secret Handshake uses HMAC-SHA512-256 (SHA-512 truncated to
256 bits). Apple's `CommonCrypto` has `kCCHmacAlgSHA512`. OpenSSL's EVP interface
supports this but requires `EVP_sha512_256()` which may not be available in older
OpenSSL versions (< 1.1.1).

**Files at Risk:** `SSBSecretHandshake.m`, `SSBCommonCryptoCompat.h`

**Test:**
```bash
openssl version  # Check version in Docker container
grep -n "hmac\|HMAC\|SHA512" Sources/SSBCommonCryptoCompat.h
grep -n "CCHmac\|kCCHmacAlg" Sources/SSBSecretHandshake.m
```

**Status:** UNTESTED — Critical for SHS success on Linux.

**Resolution Path:**
- If `EVP_sha512_256()` unavailable: implement manually (run SHA-512, truncate to 32 bytes)
- The SSB network key auth uses HMAC-SHA512-256 specifically — must be exact

---

### H-006: TweetNaCl thread safety on Linux

**Hypothesis:** `tweetnacl.c` uses no global state (pure function), so it should
be thread-safe. However, `randombytes()` in `randombytes.c` reads from `/dev/urandom`
and may need a file descriptor per-thread under high load.

**Files at Risk:** `randombytes.c`, `tweetnacl.c`

**Test:** Run multiple parallel handshakes (stress test) and check for bad crypto.

**Status:** LOW PRIORITY — Not blocking initial port.

**Resolution Path:**
- If needed: use `getrandom(2)` syscall directly instead of `/dev/urandom` fd

---

### H-007: SQLite3 WAL mode on Linux

**Hypothesis:** `SSBFeedStore` uses SQLite3 in WAL (Write-Ahead Logging) mode.
This should work on Linux but the default `sqlite3.h` path on Ubuntu differs from macOS.

**Files at Risk:** `SSBFeedStore.m`, `SSBJITDB.m`

**Test:**
```bash
find /usr -name "sqlite3.h" 2>/dev/null
dpkg -l libsqlite3-dev  # In GNUstep Docker container
```

**Status:** SHOULD WORK — `libsqlite3-dev` included in Dockerfile.gnustep.

---

### H-008: Objective-C blocks with GNUstep runtime

**Hypothesis:** Scuttle uses blocks extensively (`^{ ... }`). GNUstep supports
blocks via `libBlocksRuntime`, which should be auto-linked with `clang -fblocks`.
The `GNUmakefile` includes `-fblocks`.

**Files at Risk:** All `.m` files with `^{...}` blocks

**Test:** Compile a simple test with `clang -fblocks -lobjc -o test test.m`

**Status:** SHOULD WORK — `-fblocks` is in `ADDITIONAL_OBJCFLAGS`.

---

### H-009: go-ssb-room version compatibility

**Hypothesis:** go-ssb-room v1.3.x changed the `tunnel.endpoints` API vs earlier
versions. Our `SSBRoomClient` may be targeting the older API.

**Files at Risk:** `SSBRoomClient.m` (endpoint discovery section)

**Test:**
```bash
# Check what version we built
docker compose exec ssb-room go-ssb-room --version 2>/dev/null || true
# Compare API in go-ssb-room source vs what SSBRoomClient expects
grep -n "tunnel.endpoints\|tunnel.connect\|room.metadata" Sources/SSBRoomClient.m | head -20
```

**Status:** UNTESTED — Check after room is running.

---

## Build Test Results Log

Record actual build/test results here as experiments are run.

### Run 1 — DATE: TBD
- Environment: `docker/Dockerfile.gnustep` (Ubuntu 22.04)
- Command: `make`
- Result: TBD
- Errors: TBD
- Notes: TBD

### Run 2 — DATE: TBD
- Environment: Same
- Command: `tools/debug/ssb-room-harness.sh test-identity`
- Result: TBD
- Errors: TBD
- Notes: TBD

---

## Next Steps

1. **Start the Docker room:**
   ```bash
   docker compose up ssb-room -d
   docker compose ps
   ```

2. **Attempt build in GNUstep container:**
   ```bash
   docker compose --profile debug run --rm scuttle-build bash
   . /usr/share/GNUstep/Makefiles/GNUstep.sh
   make 2>&1 | tee /workspace/plans/topics/build-output.txt
   ```

3. **Record first errors** in this file under "Build Test Results Log"

4. **Map errors to hypotheses** above and mark as CONFIRMED/REJECTED

5. **Fix each in order of severity** (SHS crypto first, then transport, then UI)

---

## Related Files

| File | Role |
|------|------|
| `GNUmakefile` | Build system — compile `scuttle-cli` |
| `Sources/SSBLogCompat.h` | Logging shim (H-004) |
| `Sources/SSBCommonCryptoCompat.h` | Crypto shim (H-005) |
| `Sources/SSBKeychain_Linux.m` | Keychain impl |
| `Sources/SSBURLSessionShim.m` | URL session shim (H-002) |
| `docker/Dockerfile.gnustep` | Build environment |
| `tools/debug/ssb-room-harness.sh` | Integration test harness |

---

## Reference: GNUstep Compatibility Matrix

| macOS API | GNUstep Equivalent | Status |
|-----------|-------------------|--------|
| `os/log.h` | `NSLog` via shim | ✅ Shim exists |
| `CommonCrypto` | OpenSSL via shim | ✅ Shim exists |
| `Security.framework` | File-based keychain | ✅ Linux impl exists |
| `NSURLSession` | GNUstep NSURLSession | ⚠️ Partial - check H-002 |
| `dispatch_data_t` | libdispatch | ⚠️ Check H-001 |
| `NSRunLoop` | GNUstep NSRunLoop | ✅ Should work |
| `@autoreleasepool` | GNUstep ARC | ✅ Should work (H-003) |
| `NSTask` | GNUstep NSTask | ✅ Not used in CLI |
