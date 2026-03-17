# Secure C Audit Checklist

Use this checklist during the `Plan` and `Validate` phases of any task involving C code.

## 1. Memory Management
- [ ] **Initialization**: Are all pointers initialized to `NULL`?
- [ ] **Return Checks**: Is the return value of `malloc`/`calloc`/`realloc` checked for `NULL`?
- [ ] **Memory Leaks**: Is there a `free` for every `malloc` on all execution paths (including error paths)?
- [ ] **Use-After-Free**: Is the pointer set to `NULL` immediately after `free`?
- [ ] **Double-Free**: Is there any path where `free` could be called twice on the same pointer?
- [ ] **Realloc Safety**: If `realloc` fails, is the original pointer still tracked to avoid a leak? (e.g., `tmp = realloc(p, size); if (!tmp) ...`)

## 2. Buffer Safety
- [ ] **Bounds Checking**: Is the destination buffer size explicitly checked before writing?
- [ ] **Null Termination**: Is the resulting string guaranteed to be null-terminated in all cases?
- [ ] **Off-by-One**: Does the size check account for the null terminator? (e.g., `if (len < MAX_SIZE)`)
- [ ] **Input Source**: Is the input size sourced from an untrusted peer or file? If so, is it validated against a hard maximum?

## 3. Integer Safety
- [ ] **Arithmetic Overflow**: Can `a + b` or `a * b` overflow when calculating allocation sizes or array indices?
- [ ] **Signedness**: Are you comparing a signed integer with an unsigned one? (e.g., `if (signed_len < unsigned_buffer_size)`)
- [ ] **Underflow**: Can `a - b` underflow if `b > a` when dealing with buffer offsets?

## 4. Error Handling & Cleanup
- [ ] **Cleanup Pattern**: Is the `goto cleanup;` pattern used consistently for resource release?
- [ ] **Error Propagation**: Do all internal functions return an error code or status that is checked by the caller?
- [ ] **Consistent State**: Is the object or system left in a valid, consistent state if an operation fails midway?

## 5. Dangerous Functions
- [ ] **Banned Functions**: Have all instances of `strcpy`, `strcat`, `sprintf`, `gets`, and `scanf` been replaced with safer versions? (See [DANGEROUS_FUNCTIONS.md](DANGEROUS_FUNCTIONS.md))
