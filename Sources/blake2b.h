/*
 * blake2b.h — BLAKE2b-256 (32-byte output), minimal public-domain implementation.
 *
 * Based on RFC 7693 and the reference implementation by Samuel Neves et al.
 * (https://github.com/BLAKE2/BLAKE2). Released to the public domain / CC0.
 *
 * Only the specific variant needed by the SSB feed codecs is exposed:
 *   blake2b256(out, in, inlen) — hash arbitrary bytes to 32-byte digest.
 */

#ifndef BLAKE2B_H
#define BLAKE2B_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Compute the BLAKE2b-256 hash of @p inlen bytes starting at @p in.
 * Writes exactly 32 bytes to @p out.
 *
 * @param out    Output buffer, must be at least 32 bytes.
 * @param in     Input data (may be NULL only when inlen == 0).
 * @param inlen  Number of input bytes.
 * @return 0 on success, -1 on error (bad parameters).
 *
 * Thread-safe: no global mutable state.
 */
int blake2b256(uint8_t out[32], const void *in, size_t inlen);

#ifdef __cplusplus
}
#endif

#endif /* BLAKE2B_H */
