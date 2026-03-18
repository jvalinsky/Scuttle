# Known Issues and Limitations

## Overview

This document tracks platform-specific issues, limitations, and workarounds for the macOS to GNUstep port.

## Critical Issues (Blocking)

### 1. Network.framework Not Implemented

**Severity:** 🔴 Critical

**Issue:** All Network.framework functions are stubs. Real networking (TCP/TLS connections) doesn't work on Linux.

**Affected Code:**
- `SSBRoomClient.m` - Peer connections
- `SSBTunnelConnection.m` - Tunnel connections
- `SSBSecurityFramer.m` - Custom framers
- `SSBMuxRPCFramer.m` - MuxRPC framing

**Workaround:** None for networking. The application can run but cannot connect to peers.

**Status:** Needs socket-based implementation in `SSBNetworkShim.m`

---

### 2. SecRandomCopyBytes Missing Shim

**Severity:** 🟡 Medium

**Issue:** `SecRandomCopyBytes` is not available on Linux. Some files use it directly without fallback.

**Affected Files:**
- `App/Logic/SRRoomManager.m:442`
- `Sources/SSBHTTPInviteServer.m:85`
- `Sources/SSBHTTPAuth.m:156`
- `Sources/SSBMetafeed.m:64,308`
- `Sources/SSBIndexFeed.m:442`

**Current Behavior:** Compilation may fail or use arc4random_buf inconsistently.

**Workaround:** Create `SSBSecurityCompat.h` with SecRandomCopyBytes shim using OpenSSL.

**Status:** Shim not created yet

---

## Medium Issues

### 3. NIB/XIB Not Supported

**Severity:** 🟡 Medium

**Issue:** GNUstep does not support loading NIB/XIB files. All UI must be built programmatically.

**Affected:** Any UI code that uses `loadNibNamed:` or Interface Builder

**Workaround:** Build all UI views in code (see `GNUstepDemo.m`)

**Status:** Scuttle's UI is macOS-only (AppKit)

---

### 4. Coordinate System Difference

**Severity:** 🟢 Low

**Issue:** GNUstep uses bottom-left origin (OpenStep), macOS uses top-left origin.

**Affected:** Any code that calculates positions based on screen coordinates.

**Workaround:**
```objc
// Convert between coordinate systems
NSPoint macOSToGNUstep(NSPoint point, CGFloat windowHeight) {
    return NSMakePoint(point.x, windowHeight - point.y);
}
```

**Status:** Known, no current workaround needed (macOS-only UI)

---

### 5. Auto Layout Partial Support

**Severity:** 🟢 Low

**Issue:** GNUstep's Auto Layout support is incomplete. Some constraint features may not work.

**Affected:** Complex constraint layouts using NSLayoutConstraint

**Workaround:** Use frame-based layout or simpler constraints.

**Status:** Known, may need testing

---

### 6. Graphics Backend Differences

**Severity:** 🟢 Low

**Issue:** GNUstep can use Cairo, Xlib, or Art backends. Rendering may differ.

**Affected:** Custom drawing code, NSImage usage

**Workaround:** Use cross-backend compatible APIs (NSBezierPath, standard fills/strokes)

**Status:** Testing needed

---

## GNUmakefile Issues

### 7. Duplicate File Entry

**Severity:** 🟡 Medium

**Issue:** `GNUmakefile` has `SSBBIPF.m` listed twice:

```makefile
scuttle-cli_OBJC_FILES = \
    ...
    Sources/SSBBIPF.m \    # First occurrence
    ...
    Sources/SSBBIPF.m \    # Duplicate!
```

**Workaround:** Remove duplicate line

**Status:** Needs fix

---

### 8. ScuttleCLI.m Missing

**Severity:** 🟡 Medium

**Issue:** `GNUmakefile` references `Sources/ScuttleCLI.m` which may not exist:

```makefile
scuttle-cli_OBJC_FILES = \
    Sources/ScuttleCLI.m \  # File may not exist
```

**Workaround:** Check if file exists, create stub if needed

**Status:** Needs verification

---

## Missing Documentation

### 9. Build Instructions

**Issue:** No clear build instructions for Linux.

**Needed:**
- Install GNUstep dependencies
- Source GNUstep environment
- Build command
- Run command

**Status:** Documentation needed

---

## Thread Safety Issues (Shared with macOS)

These issues exist on both platforms but may manifest differently:

### 10. SSBRoomClient Mutable Properties

**Severity:** 🟡 Medium

**Issue:** Multiple mutable properties accessed without synchronization.

**Affected:** `activeTunnels`, `pendingPublishQueue`, `remoteClock`, `peerEBTState`

**Status:** Issue exists on both platforms

---

### 11. SSBGitObjectStore Thread Safety

**Severity:** 🟡 Medium

**Issue:** `packs` NSMutableArray accessed without synchronization.

**Status:** Issue exists on both platforms

---

## Performance Considerations

### 12. GCD on Linux

**Issue:** libdispatch on Linux may have different performance characteristics than macOS.

**Affected:** All async operations using GCD

**Workaround:** Monitor performance, adjust queue configurations if needed

---

### 13. File I/O Performance

**Issue:** GNUstep's NSFileManager may be slower for certain operations.

**Affected:** Large file operations, frequent reads/writes

**Workaround:** Batch operations, use appropriate buffering

---

## Compatibility Matrix

| Component | macOS | Linux | Status |
|-----------|-------|-------|--------|
| Foundation | ✅ Full | ✅ Full | Compatible |
| AppKit | ✅ Full | ❌ None | GUI not portable |
| os/log | ✅ Full | ✅ Shim | Compatible |
| CommonCrypto | ✅ Full | ✅ Shim | Compatible |
| Security | ✅ Full | ⚠️ Partial | Keychain: file-based |
| Network.framework | ✅ Full | ❌ None | Needs impl |
| libdispatch | ✅ Full | ✅ Full | Compatible |
| SQLite | ✅ Full | ✅ Full | Compatible |
| TweetNaCl | ✅ Full | ✅ Full | Portable C |
| BLAKE | ✅ Full | ✅ Full | Portable C |

---

## Priority Work Items

### Immediate (Blockers)

1. **Create SecRandomCopyBytes shim** - `SSBSecurityCompat.h`
2. **Implement socket-based networking** - Or document limitation
3. **Fix GNUmakefile duplicates** - Remove duplicate entries

### Short Term (Nice to Have)

4. **Add dispatch_data_get_size shim** - For completeness
5. **Document Linux build process** - Install deps, build, run
6. **Test Auto Layout compatibility** - Ensure constraints work

### Long Term (Enhancements)

7. **Implement full nw_connection_*** - Real networking
8. **Implement nw_listener_*** - Server sockets
9. **Consider libsecret integration** - Production keychain

---

## Reporting Issues

When reporting a platform-specific issue:

1. **Platform:** macOS / Linux (with GNUstep version)
2. **Component:** Framework or file affected
3. **Expected behavior:** What should happen
4. **Actual behavior:** What happens instead
5. **Reproduction steps:** How to trigger the issue
6. **Workaround:** Any temporary fix

---

## Version Information

Record platform version when testing:

```bash
# macOS
sw_vers
xcodebuild -version

# Linux
cat /etc/os-release
gnustep-config --version
dpkg -l | grep gnustep

# GNUmakefile version
grep "GNUmakefile" GNUmakefile
```
