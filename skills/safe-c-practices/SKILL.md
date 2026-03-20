---
name: safe-c-practices
description: Expertise in writing, auditing, and verifying secure C code. Use when working with C files to prevent memory leaks, buffer overflows, and other security vulnerabilities.
---

# Safe C Practices for Scuttle

This skill provides expertise in writing, auditing, and verifying secure C code. It is specifically tailored for systems programming where memory management, buffer safety, and integer arithmetic are critical for preventing exploits and crashes.

## When to Use This Skill

Use this skill whenever you are:
- Writing new C code or modifying existing `.c` and `.h` files.
- Auditing existing C code for potential security vulnerabilities or memory leaks.
- Implementing low-level parsers (e.g., Git PACK files, MuxRPC framing).
- Verifying C implementations using static or dynamic analysis tools.

## Workflows

### 1. Secure C Audit Workflow
When asked to review or audit C code, follow this multi-step process:
1.  **Map Allocations**: Identify all calls to `malloc`, `calloc`, `realloc`, and their corresponding `free`. Trace all paths to ensure no leaks or double-frees.
2.  **Trace Buffer Inputs**: For every buffer, identify its source and size. Verify that all writes to the buffer are explicitly bounds-checked.
3.  **Identify Dangerous Functions**: Scan for banned functions like `strcpy`, `strcat`, `sprintf`, and `gets`.
4.  **Audit Integer Math**: Check all arithmetic used for array indexing or memory allocation sizes for potential overflow or underflow.
5.  **Verify Error Handling**: Ensure every error path correctly releases all resources (memory, file descriptors) using a consistent cleanup pattern.

Reference the [CHECKLIST.md](references/CHECKLIST.md) for a granular audit protocol.

### 2. Implementation Guide
When writing new C code, adhere to these mandates:
- **Resource Management**: Always use the `goto cleanup` pattern for resource management to avoid leaks in error paths.
- **Initialization**: Always initialize pointers to `NULL` and variables to a safe default.
- **Safety Over Speed**: Prefer `snprintf` over `sprintf`, and `strncat` over `strcat`.
- **Fixed-Width Types**: Use `<stdint.h>` types (e.g., `uint32_t`, `int64_t`) for all data structures and size calculations.
- **Explicit Checks**: Always check the return value of `malloc` and other resource-allocating functions.

See [DANGEROUS_FUNCTIONS.md](references/DANGEROUS_FUNCTIONS.md) for safer alternatives.

## Verification & Testing

Always verify C code using the following tools when available in the environment:
1.  **Static Analysis**: Run `cppcheck --enable=all` or `scan-build` if part of the build system.
2.  **Dynamic Analysis**: Enable AddressSanitizer (ASan) and UndefinedBehaviorSanitizer (UBSan) during testing by adding `-fsanitize=address,undefined` to compiler flags.
3.  **Fuzzing**: For complex parsers, consider writing a small `libFuzzer` target to test with randomized inputs.

Detailed tool usage is documented in [TOOL_GUIDE.md](references/TOOL_GUIDE.md).
