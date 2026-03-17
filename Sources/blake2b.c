/*
 * blake2b.c — BLAKE2b-256, per RFC 7693.
 *
 * Based on the reference implementation by Samuel Neves, Jean-Philippe
 * Aumasson, Luca Henzen, Willi Meier, and Raphael Phan.
 * https://github.com/BLAKE2/BLAKE2/blob/master/ref/blake2b-ref.c
 *
 * Released to the public domain / CC0.
 */

#include "blake2b.h"

#include <string.h>

/* ── Types ───────────────────────────────────────────────────────────────── */

typedef struct {
    uint64_t h[8];      /* chaining values                */
    uint64_t t[2];      /* counter (bytes consumed)       */
    uint8_t  buf[128];  /* input buffer (one block = 128 bytes) */
    size_t   buflen;    /* bytes currently in buf         */
    uint8_t  outlen;    /* requested digest length        */
    uint8_t  last;      /* flag: this is the last block   */
} blake2b_state;

/* ── Constants ───────────────────────────────────────────────────────────── */

static const uint64_t IV[8] = {
    UINT64_C(0x6a09e667f3bcc908),
    UINT64_C(0xbb67ae8584caa73b),
    UINT64_C(0x3c6ef372fe94f82b),
    UINT64_C(0xa54ff53a5f1d36f1),
    UINT64_C(0x510e527fade682d1),
    UINT64_C(0x9b05688c2b3e6c1f),
    UINT64_C(0x1f83d9abfb41bd6b),
    UINT64_C(0x5be0cd19137e2179),
};

static const uint8_t SIGMA[12][16] = {
    {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 },
    { 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4 },
    {  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8 },
    {  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13 },
    {  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9 },
    { 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11 },
    { 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10 },
    {  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5 },
    { 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0 },
    {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 },
};

/* ── Helpers ──────────────────────────────────────────────────────────────── */

static inline uint64_t rotr64(uint64_t x, int n) {
    return (x >> n) | (x << (64 - n));
}

static inline uint64_t load64_le(const uint8_t *p) {
    uint64_t v;
    memcpy(&v, p, 8);
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    v = __builtin_bswap64(v);
#endif
    return v;
}

/* ── G mixing function ───────────────────────────────────────────────────── */

#define G(r, i, a, b, c, d)                        \
    do {                                            \
        (a) += (b) + m[SIGMA[(r)][(i)*2+0]];       \
        (d)  = rotr64((d) ^ (a), 32);              \
        (c) += (d);                                 \
        (b)  = rotr64((b) ^ (c), 24);              \
        (a) += (b) + m[SIGMA[(r)][(i)*2+1]];       \
        (d)  = rotr64((d) ^ (a), 16);              \
        (c) += (d);                                 \
        (b)  = rotr64((b) ^ (c), 63);              \
    } while (0)

/* ── Compression ─────────────────────────────────────────────────────────── */

static void compress(blake2b_state *S, const uint8_t block[128]) {
    uint64_t m[16];
    uint64_t v[16];
    int r;

    for (int i = 0; i < 16; i++) {
        m[i] = load64_le(block + i * 8);
    }

    for (int i = 0; i < 8; i++) {
        v[i]     = S->h[i];
        v[i + 8] = IV[i];
    }

    v[12] ^= S->t[0];
    v[13] ^= S->t[1];
    if (S->last) {
        v[14] ^= UINT64_C(0xffffffffffffffff);
    }

    for (r = 0; r < 12; r++) {
        G(r, 0, v[ 0], v[ 4], v[ 8], v[12]);
        G(r, 1, v[ 1], v[ 5], v[ 9], v[13]);
        G(r, 2, v[ 2], v[ 6], v[10], v[14]);
        G(r, 3, v[ 3], v[ 7], v[11], v[15]);
        G(r, 4, v[ 0], v[ 5], v[10], v[15]);
        G(r, 5, v[ 1], v[ 6], v[11], v[12]);
        G(r, 6, v[ 2], v[ 7], v[ 8], v[13]);
        G(r, 7, v[ 3], v[ 4], v[ 9], v[14]);
    }

    for (int i = 0; i < 8; i++) {
        S->h[i] ^= v[i] ^ v[i + 8];
    }
}

/* ── Initialization ───────────────────────────────────────────────────────── */

static int blake2b_init(blake2b_state *S, uint8_t outlen) {
    if (outlen == 0 || outlen > 64) {
        return -1;
    }

    memset(S, 0, sizeof(*S));

    for (int i = 0; i < 8; i++) {
        S->h[i] = IV[i];
    }

    /* XOR parameter block word 0 into h[0].
     * For BLAKE2b-256 with no key (key_len=0), fanout=1, max_depth=1:
     *   bytes [outlen, 0, 1, 1, 0, 0, 0, 0] in little-endian form.
     */
    S->h[0] ^= (uint64_t)outlen
             | ((uint64_t)0    << 8)   /* key_len = 0 */
             | ((uint64_t)1    << 16)  /* fanout  = 1 */
             | ((uint64_t)1    << 24); /* max_depth= 1 */

    S->outlen = outlen;
    return 0;
}

/* ── Update ───────────────────────────────────────────────────────────────── */

static int blake2b_update(blake2b_state *S, const void *in, size_t inlen) {
    const uint8_t *p = (const uint8_t *)in;

    if (inlen == 0) {
        return 0;
    }

    while (inlen > 0) {
        size_t space = sizeof(S->buf) - S->buflen;
        size_t fill  = inlen < space ? inlen : space;

        memcpy(S->buf + S->buflen, p, fill);
        S->buflen += fill;
        p         += fill;
        inlen     -= fill;

        if (S->buflen == sizeof(S->buf) && inlen > 0) {
            /* Buffer is full and there is more data — compress now. */
            S->t[0] += sizeof(S->buf);
            if (S->t[0] < sizeof(S->buf)) {
                S->t[1]++;
            }
            S->last = 0;
            compress(S, S->buf);
            S->buflen = 0;
        }
    }

    return 0;
}

/* ── Finalize ─────────────────────────────────────────────────────────────── */

static int blake2b_final(blake2b_state *S, uint8_t *out) {
    uint8_t tmp[64] = { 0 };

    /* Update counter for remaining bytes. */
    S->t[0] += (uint64_t)S->buflen;
    if (S->t[0] < (uint64_t)S->buflen) {
        S->t[1]++;
    }

    /* Pad buffer with zeros. */
    memset(S->buf + S->buflen, 0, sizeof(S->buf) - S->buflen);
    S->last = 1;
    compress(S, S->buf);

    /* Serialize h[0..3] (for 32-byte output) in little-endian. */
    for (int i = 0; i < 8; i++) {
        tmp[i * 8 + 0] = (uint8_t)(S->h[i] >>  0);
        tmp[i * 8 + 1] = (uint8_t)(S->h[i] >>  8);
        tmp[i * 8 + 2] = (uint8_t)(S->h[i] >> 16);
        tmp[i * 8 + 3] = (uint8_t)(S->h[i] >> 24);
        tmp[i * 8 + 4] = (uint8_t)(S->h[i] >> 32);
        tmp[i * 8 + 5] = (uint8_t)(S->h[i] >> 40);
        tmp[i * 8 + 6] = (uint8_t)(S->h[i] >> 48);
        tmp[i * 8 + 7] = (uint8_t)(S->h[i] >> 56);
    }

    memcpy(out, tmp, S->outlen);
    memset(tmp, 0, sizeof(tmp)); /* wipe */

    return 0;
}

/* ── Public API ───────────────────────────────────────────────────────────── */

int blake2b256(uint8_t out[32], const void *in, size_t inlen) {
    blake2b_state S;

    if (!out) {
        return -1;
    }
    if (!in && inlen != 0) {
        return -1;
    }

    if (blake2b_init(&S, 32) != 0) {
        return -1;
    }

    if (blake2b_update(&S, in, inlen) != 0) {
        return -1;
    }

    return blake2b_final(&S, out);
}
