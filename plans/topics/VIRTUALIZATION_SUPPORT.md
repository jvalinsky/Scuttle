# Virtualization Testing — Next Steps Support

## ✅ Current Accomplishments

### 1. **Entitlements & Code Signing** (`project.yml`)
- Host app `LinuxTestHostApp` is configured with `com.apple.security.virtualization`.
- Code signing identity sets to `"-"` (Ad-Hoc) to comply with macOS entitlement restrictions on bundle testing.

### 2. **Swift Testing Bridge** (`SwiftBridge.swift`)
- Fully implemented class `SRLinuxTestRunner` connecting `LinuxContainer` and `VZVirtualMachineManager`.
- Unpacks OCI images to `EXT4` disk layouts using standard framework protocols.
- Captures `stdout`/`stderr` through explicit `BufferWriter` buffers.

### 3. **Objective-C Compatibility** (`SRLinuxTests.m`)
- Resolved case-sensitivity and bridge-header generation settings (`SWIFT_OBJC_INTERFACE_HEADER_NAME: "VirtualizationTests-Swift.h"`).
- Verified tests compile and reach execution phases correctly on local macOS.

---

## 🚀 Remaining Steps

### 1. **Setup VM Kernels and Initial RAM Disk**
To run the virtual machine safely, you must provide:
- **Mac Linux Kernel** (`vmlinux`):
  Place an uncompressed kernel image for Apple Silicon arm64 at `/usr/local/bin/vmlinux` or standard environment path `LINUX_KERNEL`.
- **Initial Filesystem** (`init.block`):
  Place your initial filesystem loader at `/usr/local/bin/init.block` or set `LINUX_INITFS`.

### 2. **Refine OCI Reference Lookup**
Currently, the test uses `"nixos/nix"` directly, which fails resolving OCI domains on cold boots.
- Update `SRLinuxTests.m` calls to fully descriptive layout refs, for example:
  ```objc
  [self.runner runCommand:@"id" image:@"docker.io/library/debian:latest" ...];
  ```

Once items are placed, you can fully verify end-to-end Containerized testing setups easily via direct Xcode runs.
