---
name: macos-gnustep-translation
description: Comprehensive guide for translating macOS-specific Objective-C code to run on Linux using GNUstep, covering Foundation, AppKit, Network.framework, Security.framework, and GCD.
---

# macOS to GNUstep Translation Guide

This skill provides comprehensive guidance for porting macOS-specific Objective-C code to Linux using GNUstep, with detailed coverage of framework compatibility, API differences, and shim implementations.

## When to Use This Skill

Use this skill when you are:
- Porting macOS applications to Linux
- Creating compatibility shims for Apple frameworks
- Understanding API differences between macOS and GNUstep
- Implementing cross-platform Objective-C code
- Debugging platform-specific issues

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS Source Code                         │
│   os/log | CommonCrypto | Security | Network.framework      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Compatibility Layer                         │
│   SSBLogCompat.h | SSBCommonCryptoCompat.h                  │
│   SSBNetworkCompat.h | SSBSecurityCompat.h                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Linux Target                             │
│   GNUstep (Foundation + GUI) | OpenSSL | libdispatch       │
└─────────────────────────────────────────────────────────────┘
```

## Framework Compatibility Summary

| Framework | macOS API | GNUstep Status | Shim File |
|-----------|-----------|----------------|-----------|
| **Logging** | `os/log.h` | ✅ Complete | `SSBLogCompat.h` |
| **Crypto** | `CommonCrypto` | ✅ Complete | `SSBCommonCryptoCompat.h` |
| **Security** | `Keychain` | ✅ Complete | `SSBKeychain_Linux.m` |
| **Security** | `SecRandomCopyBytes` | ⚠️ Missing | Create shim |
| **Network** | `Network.framework` | ⚠️ Stubs | `SSBNetworkCompat.h` + `SSBNetworkShim.m` |
| **Foundation** | Most classes | ✅ Compatible | N/A |
| **AppKit** | Most classes | ✅ Partial | Build UI programmatically |

## Quick Reference

### Platform Guard Pattern

```objc
#ifdef __APPLE__
    #import <os/log.h>
    #import <Network/Network.h>
    #import <Security/Security.h>
#else
    #import "SSBLogCompat.h"
    #import "SSBNetworkCompat.h"
    #import "SSBSecurityCompat.h"
#endif
```

### Platform-Specific Files

```
Sources/
├── SSBKeychain_macOS.m     # macOS Keychain implementation
├── SSBKeychain_Linux.m     # Linux file-based storage
├── SSBNetworkCompat.h      # Network.framework types
└── SSBNetworkShim.m        # Network.framework stubs
```

## Key Differences

### Foundation (90%+ Compatible)

| Class | Compatibility | Notes |
|-------|--------------|-------|
| NSString | ✅ 100% | Same API |
| NSArray/NSDictionary | ✅ 100% | Same API |
| NSData | ✅ 100% | Same API |
| NSFileManager | ✅ 100% | Same API |
| NSThread/NSRunLoop | ✅ 100% | Same API |
| NSDate/NSCalendar | ✅ 100% | Same API |
| NSNotificationCenter | ✅ 100% | Same API |
| NSURLSession | ⚠️ Partial | GNUstep 1.28+ |

### AppKit (60-70% Compatible)

| Class | Compatibility | Notes |
|-------|--------------|-------|
| NSWindow/NSView | ✅ 80% | Different coordinate system |
| NSButton/NSTextField | ✅ 90% | Same API |
| NSTableView | ✅ 85% | Delegate patterns same |
| NSMenu | ✅ 80% | X11 integration differs |
| NSBezierPath | ✅ 90% | Same API |
| NSImage | ✅ 80% | Backend-dependent |
| NIB/XIB Loading | ❌ 0% | Not supported |
| Auto Layout | ⚠️ 60% | Partial support |
| Touch Bar | ❌ 0% | Not applicable |

### Network.framework (0% Compatible - Stubs Only)

All `nw_connection_*`, `nw_listener_*`, and `nw_framer_*` functions are currently stubs. Real socket-based implementation needed for networking.

## Workflow: Port a File to Linux

1. **Identify macOS-only imports**
2. **Add platform guards**
3. **Include compatibility headers**
4. **Handle missing APIs with shims**
5. **Test on Linux with GNUstep**

## Reference Files

- [FOUNDATION_CLASSES.md](references/FOUNDATION_CLASSES.md) - Foundation API compatibility
- [APPKIT_CLASSES.md](references/APPKIT_CLASSES.md) - AppKit API compatibility
- [NETWORK_FRAMEWORK.md](references/NETWORK_FRAMEWORK.md) - Network.framework shims
- [SECURITY_FRAMEWORK.md](references/SECURITY_FRAMEWORK.md) - Security.framework shims
- [GCD_DISPATCH.md](references/GCD_DISPATCH.md) - libdispatch on Linux
- [PLATFORM_GUARDS.md](references/PLATFORM_GUARDS.md) - Conditional compilation patterns
- [SHIM_CREATION_GUIDE.md](references/SHIM_CREATION_GUIDE.md) - Creating new shims
- [KNOWN_ISSUES.md](references/KNOWN_ISSUES.md) - Limitations and workarounds
