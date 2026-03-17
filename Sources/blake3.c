/*
 * blake3.c — BLAKE3-256, minimal scalar implementation.
 * Supports inputs up to 8192 bytes (8 × 1024-byte chunks).
 *
 * Based on the BLAKE3 specification (https://github.com/BLAKE3-team/BLAKE3-specs)
 * and the public-domain reference implementation by the BLAKE3 team.
 * Released to the public domain / CC0.
 */

#include "blake3.h"

#include <string.h>

/* ── Domain-separation flags ─────────────────────────────────────────────── */

#define CHUNK_START (1u)
#define CHUNK_END   (2u)
#define PARENT      (4u)
#define ROOT        (8u)

/* ── Sizes ───────────────────────────────────────────────────────────────── */

#define BLOCK_LEN  64u    /* bytes per compression block                    */
#define CHUNK_LEN  1024u  /* bytes per chunk                                */
#define MAX_CHUNKS 8u     /* 8192 / 1024 — matches Buttwoo kMaxMessageSize  */

/* ── Initialisation vector (= SHA-256 initial hash values) ───────────────── */

static const uint32_t IV[8] = {
    0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u, 0xA54FF53Au,
    0x510E527Fu, 0x9B05688Cu, 0x1F83D9ABu, 0x5BE0CD19u
};

/* ── Message permutation schedule (7 rounds) ─────────────────────────────── */

static const uint8_t SIGMA[7][16] = {
    { 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15},
    { 2,  6,  3, 10,  7,  0,  4, 13,  1, 11, 12,  5,  9, 14, 15,  8},
    { 3,  4, 10, 12, 13,  2,  7, 14,  6,  5,  9,  0, 11, 15,  8,  1},
    {10,  7, 12,  9, 14,  3, 13, 15,  4,  0, 11,  2,  5,  8,  1,  6},
    {12, 13,  9, 11, 15, 10, 14,  8,  7,  2,  5,  3,  0,  1,  6,  4},
    { 9, 14, 11,  5,  8, 12, 15,  1, 13,  3,  0, 10,  2,  6,  4,  7},
    {11, 15,  5,  0,  1,  9,  8,  6, 14, 10,  2, 12,  3,  4,  7, 13},
};

/* ── Quarter-round G function (BLAKE3 uses 32-bit rotations 16, 12, 8, 7) ── */

#define ROR32(x, n) (((uint32_t)(x) >> (n)) | ((uint32_t)(x) << (32u - (n))))

#define G(a, b, c, d, mx, my)      \
    (a) += (b) + (mx);             \
    (d)  = ROR32((d) ^ (a), 16);   \
    (c) += (d);                    \
    (b)  = ROR32((b) ^ (c), 12);   \
    (a) += (b) + (my);             \
    (d)  = ROR32((d) ^ (a),  8);   \
    (c) += (d);                    \
    (b)  = ROR32((b) ^ (c),  7)

/* ── Compression function ────────────────────────────────────────────────── */
/*
 * Runs one BLAKE3 compression and writes the 8-word chaining value:
 *   out_cv[i] = state[i] XOR state[i+8],  i = 0..7
 */
static void compress(const uint32_t cv[8],
                     const uint8_t  block[BLOCK_LEN],
                     uint64_t       counter,
                     uint32_t       block_len,
                     uint32_t       flags,
                     uint32_t       out_cv[8])
{
    /* Decode 16 message words (little-endian) */
    uint32_t m[16];
    for (int i = 0; i < 16; i++) {
        const uint8_t *p = block + 4 * i;
        m[i] = (uint32_t)p[0]
             | ((uint32_t)p[1] <<  8)
             | ((uint32_t)p[2] << 16)
             | ((uint32_t)p[3] << 24);
    }

    /* Initialise 16-word state */
    uint32_t v[16] = {
        cv[0], cv[1], cv[2],  cv[3],
        cv[4], cv[5], cv[6],  cv[7],
        IV[0], IV[1], IV[2],  IV[3],
        (uint32_t)(counter & 0xFFFFFFFFu),
        (uint32_t)(counter >> 32),
        block_len,
        flags
    };

    /* 7 rounds: column mixing + diagonal mixing */
    for (int r = 0; r < 7; r++) {
        const uint8_t *s = SIGMA[r];
        G(v[ 0], v[ 4], v[ 8], v[12], m[s[ 0]], m[s[ 1]]);
        G(v[ 1], v[ 5], v[ 9], v[13], m[s[ 2]], m[s[ 3]]);
        G(v[ 2], v[ 6], v[10], v[14], m[s[ 4]], m[s[ 5]]);
        G(v[ 3], v[ 7], v[11], v[15], m[s[ 6]], m[s[ 7]]);
        G(v[ 0], v[ 5], v[10], v[15], m[s[ 8]], m[s[ 9]]);
        G(v[ 1], v[ 6], v[11], v[12], m[s[10]], m[s[11]]);
        G(v[ 2], v[ 7], v[ 8], v[13], m[s[12]], m[s[13]]);
        G(v[ 3], v[ 4], v[ 9], v[14], m[s[14]], m[s[15]]);
    }

    /* XOR upper half into lower half → chaining value */
    for (int i = 0; i < 8; i++) {
        out_cv[i] = v[i] ^ v[i + 8];
    }
}

/* ── Helper: write 8 uint32 words to a 32-byte buffer (little-endian) ─────── */

static void words_to_bytes(const uint32_t words[8], uint8_t out[32])
{
    for (int i = 0; i < 8; i++) {
        out[4*i + 0] = (uint8_t)( words[i]        & 0xFFu);
        out[4*i + 1] = (uint8_t)((words[i] >>  8) & 0xFFu);
        out[4*i + 2] = (uint8_t)((words[i] >> 16) & 0xFFu);
        out[4*i + 3] = (uint8_t)((words[i] >> 24) & 0xFFu);
    }
}

/* ── Hash one chunk (0..1024 bytes) ─────────────────────────────────────── */
/*
 * input_len: 0..CHUNK_LEN bytes for this chunk.
 * chunk_counter: 0-based index of this chunk in the overall input.
 * extra_flags: pass ROOT when this is the only chunk (single-chunk input).
 * out_cv: receives the 32-byte chaining value.
 */
static void hash_chunk(const uint8_t *input,
                        size_t         input_len,
                        uint64_t       chunk_counter,
                        uint32_t       extra_flags,
                        uint8_t        out_cv[32])
{
    uint32_t cv[8];
    memcpy(cv, IV, sizeof(cv));

    uint32_t block_flags = CHUNK_START;
    size_t   offset      = 0;

    /*
     * Process blocks one at a time.  Use do-while so that zero-length input
     * still produces one empty block (required by the spec).
     */
    do {
        uint8_t  block[BLOCK_LEN];
        uint32_t blen = (uint32_t)(input_len - offset);
        if (blen > BLOCK_LEN) blen = BLOCK_LEN;

        memset(block, 0, BLOCK_LEN);
        if (blen > 0) memcpy(block, input + offset, blen);

        offset += blen;

        /* The last block of the chunk gets CHUNK_END and any extra flags */
        if (offset == input_len) {
            block_flags |= CHUNK_END | extra_flags;
        }

        uint32_t new_cv[8];
        compress(cv, block, chunk_counter, blen, block_flags, new_cv);
        memcpy(cv, new_cv, sizeof(cv));

        /* CHUNK_START applies only to the first block */
        block_flags &= ~CHUNK_START;

    } while (offset < input_len);

    words_to_bytes(cv, out_cv);
}

/* ── Hash one parent node (merges two 32-byte chaining values) ───────────── */
/*
 * extra_flags: pass ROOT when this merge produces the tree root.
 */
static void hash_parent(const uint8_t left_cv[32],
                         const uint8_t right_cv[32],
                         uint32_t      extra_flags,
                         uint8_t       out_cv[32])
{
    uint8_t block[BLOCK_LEN];
    memcpy(block,      left_cv,  32);
    memcpy(block + 32, right_cv, 32);

    uint32_t cv[8];
    memcpy(cv, IV, sizeof(cv));

    uint32_t new_cv[8];
    compress(cv, block, 0, BLOCK_LEN, PARENT | extra_flags, new_cv);
    words_to_bytes(new_cv, out_cv);
}

/* ── Public API ──────────────────────────────────────────────────────────── */

int blake3_256(uint8_t out[32], const void *in, size_t inlen)
{
    if (!out)               return -1;
    if (inlen > 0 && !in)  return -1;
    if (inlen > MAX_CHUNKS * CHUNK_LEN) return -1;

    const uint8_t *data = (const uint8_t *)in;

    /* Number of chunks: at least 1 (spec requires one empty chunk for empty input) */
    size_t num_chunks = (inlen == 0) ? 1 : (inlen + CHUNK_LEN - 1) / CHUNK_LEN;

    /* ── Hash each chunk ─────────────────────────────────────────────────── */

    uint8_t chunk_cvs[MAX_CHUNKS][32];

    for (size_t i = 0; i < num_chunks; i++) {
        const uint8_t *chunk_start = data + i * CHUNK_LEN;
        size_t chunk_len = (i * CHUNK_LEN < inlen) ? inlen - i * CHUNK_LEN : 0;
        if (chunk_len > CHUNK_LEN) chunk_len = CHUNK_LEN;

        /* For empty input, chunk_start == data (possibly NULL); hash_chunk handles blen==0 */
        uint32_t extra = (num_chunks == 1) ? ROOT : 0u;
        hash_chunk(chunk_start, chunk_len, (uint64_t)i, extra, chunk_cvs[i]);
    }

    /* Single chunk: output is the chunk chaining value (ROOT flag already set) */
    if (num_chunks == 1) {
        memcpy(out, chunk_cvs[0], 32);
        return 0;
    }

    /* ── Build Merkle tree bottom-up ─────────────────────────────────────── */
    /*
     * At each level, adjacent CVs are merged into parent nodes.
     * An odd trailing CV carries up unchanged to the next level.
     * The very last merge (when count reaches 2) sets the ROOT flag.
     */
    uint8_t level[MAX_CHUNKS][32];
    memcpy(level, chunk_cvs, num_chunks * 32);
    size_t count = num_chunks;

    while (count > 1) {
        uint8_t next[MAX_CHUNKS][32];
        size_t  next_count = 0;
        size_t  pairs      = count / 2;

        /* is_last_level: after this pass only one CV will remain */
        int is_last_level = (count == 2);

        for (size_t i = 0; i < pairs; i++) {
            uint32_t xflags = is_last_level ? ROOT : 0u;
            hash_parent(level[2*i], level[2*i + 1], xflags, next[next_count++]);
        }

        /* Odd trailing CV carries up without merging */
        if (count & 1u) {
            memcpy(next[next_count++], level[count - 1], 32);
        }

        memcpy(level, next, next_count * 32);
        count = next_count;
    }

    memcpy(out, level[0], 32);
    return 0;
}
