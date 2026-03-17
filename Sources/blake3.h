/*
 * blake3.h — BLAKE3-256 (32-byte output), minimal scalar implementation.
 *
 * Supports inputs up to 8192 bytes (matches Buttwoo kMaxMessageSize).
 * Based on the BLAKE3 specification: https://github.com/BLAKE3-team/BLAKE3-specs
 * Released to the public domain / CC0.
 *
 * Only the specific variant needed by the Buttwoo feed codec is exposed:
 *   blake3_256(out, in, inlen) — hash arbitrary bytes to 32-byte digest.
 */

#ifndef BLAKE3_H
#define BLAKE3_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Compute the BLAKE3-256 hash of @p inlen bytes starting at @p in.
 * Writes exactly 32 bytes to @p out.
 *
 * @param out    Output buffer, must be at least 32 bytes.
 * @param in     Input data (may be NULL only when inlen == 0).
 * @param inlen  Number of input bytes (max 8192).
 * @return 0 on success, -1 on error (bad parameters or inlen > 8192).
 *
 * Thread-safe: no global mutable state.
 */
int blake3_256(uint8_t out[32], const void *in, size_t inlen);

#ifdef __cplusplus
}
#endif

#endif /* BLAKE3_H */
