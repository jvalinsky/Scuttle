# Linux Dependencies

## Required Libraries

### GNUstep

| Package | Purpose |
|---------|---------|
| `gnustep-base` | Foundation (NSObject, NSArray, NSString, etc.) |
| `gnustep-gui` | AppKit (optional, for GUI) |

```bash
# Debian/Ubuntu
apt install gnustep-base-dev gnustep-gui-dev

# Fedora
dnf install gnustep-base-devel
```

### libdispatch

| Package | Purpose |
|---------|---------|
| `libdispatch` | Grand Central Dispatch |

```bash
# Debian/Ubuntu
apt install libdispatch-dev

# macOS (Homebrew)
brew install libdispatch
```

### OpenSSL

| Package | Purpose |
|---------|---------|
| `libssl-dev` | SSL/TLS, crypto |
| `libcrypto` | Cryptographic functions |

```bash
# Debian/Ubuntu
apt install libssl-dev

# Fedora
dnf install openssl-devel
```

### SQLite3

| Package | Purpose |
|---------|---------|
| `libsqlite3-dev` | Database |

```bash
# Debian/Ubuntu
apt install libsqlite3-dev

# Fedora
dnf install sqlite-devel
```

## Blocks Runtime

Required for Objective-C blocks on Linux:

```bash
# Debian/Ubuntu
apt install libblocksruntime-dev
```

Or build from source:
```bash
git clone https://github.com/nickg/blocksruntime.git
cd blocksruntime
make && make install
```

## Complete Install (Ubuntu/Debian)

```bash
# Install all dependencies
apt update
apt install -y \
    gnustep \
    gnustep-base-dev \
    gnustep-gui-dev \
    libdispatch-dev \
    libssl-dev \
    libsqlite3-dev \
    libblocksruntime-dev \
    clang

# Set up environment
source /usr/share/GNUstep/Makefiles/GNUstep.sh
```

## Complete Install (Fedora)

```bash
dnf install -y \
    gnustep-base-devel \
    gnustep-gui-devel \
    libdispatch-devel \
    openssl-devel \
    sqlite-devel \
    gcc
```

## Library Versions

### Tested Versions

| Library | Version | Notes |
|---------|---------|-------|
| GNUstep | 1.28+ | |
| libdispatch | 0.11+ | |
| OpenSSL | 1.1.x | |
| SQLite | 3.x | |

### macOS (for comparison)

| Framework | Notes |
|-----------|-------|
| Foundation | Built-in |
| Security.framework | Built-in |
| CommonCrypto | Built-in |
| libdispatch | Built-in |
| Network.framework | No Linux equivalent |
