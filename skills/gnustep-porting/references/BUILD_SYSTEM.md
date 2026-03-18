# GNUstep Build System

## Project Structure

```
Scuttle/
├── GNUmakefile              # Main build file
├── Sources/                 # Source files
│   ├── SSBMessage.m
│   ├── SSBFeedStore.m
│   └── ...
└── obj/                    # Build output
```

## GNUmakefile

```makefile
# Main GNUmakefile
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = ScuttleDaemon

# Source files
ScuttleDaemon_OBJC_FILES = \
    Sources/SSBMessage.m \
    Sources/SSBFeedStore.m \
    Sources/SSBBlobStore.m

# C files (if any)
ScuttleDaemon_C_FILES = \
    Sources/tweetnacl.c \
    Sources/blake2b.c \
    Sources/blake3.c \
    Sources/SSBDiffCore.c

# Compiler flags
ADDITIONAL_OBJCFLAGS += \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -I$(GNUSTEP_USER_ROOT)/include

# Linker flags
ADDITIONAL_LDFLAGS += \
    -L$(GNUSTEP_USER_ROOT)/lib \
    -lgnustep-base \
    -lgnustep-gui \
    -ldispatch \
    -lssl \
    -lcrypto \
    -lsqlite3 \
    -lblocksruntime

include $(GNUSTEP_MAKEFILES)/tool.make
```

## Platform-Specific Files

### File Naming Convention

```
Sources/
├── SSBKeychain.m           # Shared
├── SSBKeychain_macOS.m     # macOS specific
├── SSBKeychain_Linux.m     # Linux specific
```

### Conditional Include in GNUmakefile

```makefile
ifdef LINUX
    ScuttleDaemon_OBJC_FILES += Sources/SSBKeychain_Linux.m
else
    ScuttleDaemon_OBJC_FILES += Sources/SSBKeychain_macOS.m
endif
```

## Building

### On Linux

```bash
# Set up GNUstep
source /usr/share/GNUstep/Makefiles/GNUstep.sh

# Build
make

# Or with custom flags
make LINUX=1
```

## Key Settings

### ARC Support

```makefile
ADDITIONAL_OBJCFLAGS += -fobjc-arc
```

Note: Requires GNUstep to be built with ARC support, or use `-fno-objc-arc` and manage retain/release manually.

### Block Support

```makefile
ADDITIONAL_LDFLAGS += -lblocksruntime
```

Blocks require:
1. Compiler flag: `-fblocks`
2. Runtime library: `-lblocksruntime`
3. Header: `<Block.h>` (from blocksruntime)

## Error Handling

### Common Errors

**"Cannot find Foundation/Foundation.h"**
```bash
# Install GNUstep
apt install gnustep-base-dev
```

**"library not found -lgnustep"**
```bash
# Set GNUstep paths
export GNUSTEP_MAKEFILES=/usr/share/GNUstep/Makefiles
export GNUSTEP_ROOT=/usr/share/GNUstep
```

**"undefined reference to _Block_copy"**
```bash
# Add blocks runtime
ADDITIONAL_LDFLAGS += -lblocksruntime
```
