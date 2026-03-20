# Dangerous Functions & Safer Alternatives

Avoid these legacy C functions as they are prone to buffer overflows and other vulnerabilities.

| Banned Function | Safer Alternative | Why? |
| :--- | :--- | :--- |
| `strcpy` | `strncpy` or `strlcpy` | `strcpy` does not check the destination buffer size. |
| `strcat` | `strncat` or `strlcat` | `strcat` can easily overrun the destination buffer. |
| `sprintf` | `snprintf` | `sprintf` has no bounds checking. `snprintf` requires a buffer size. |
| `gets` | `fgets` | `gets` is impossible to use safely and was removed from the C11 standard. |
| `scanf` | `fgets` + `sscanf` | `scanf` with `%s` can overflow. Use explicit width specifiers if needed. |

## Usage Notes

### `strncpy` vs `strlcpy`
- **`strncpy(dest, src, n)`**: Note that if `src` is longer than `n`, `dest` will **NOT** be null-terminated. You must manually set `dest[n-1] = '\0'`.
- **`strlcpy(dest, src, n)`**: Preferred (if available, e.g., on BSD/macOS). It always null-terminates and returns the total length of the string it tried to create.

### `snprintf`
- Always check the return value. If the return value is `>= buffer_size`, the output was truncated.

### `malloc` vs `calloc`
- Prefer `calloc` for arrays or structs when you want the memory to be zero-initialized, which helps prevent reading uninitialized memory.
