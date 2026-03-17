#ifndef SSB_DIFF_CORE_H
#define SSB_DIFF_CORE_H

#include <stdint.h>
#include <stdlib.h>

typedef enum {
    SSB_DIFF_ALGORITHM_MYERS,
    SSB_DIFF_ALGORITHM_PATIENCE,
    SSB_DIFF_ALGORITHM_HISTOGRAM,
    SSB_DIFF_ALGORITHM_MINIMAL
} SSBDiffAlgorithm;

typedef enum {
    SSB_EDIT_MATCH,
    SSB_EDIT_ADD,
    SSB_EDIT_DELETE
} SSBEditType;

typedef struct {
    SSBEditType type;
    int line_a; // 0-indexed line in string A (if applicable)
    int line_b; // 0-indexed line in string B (if applicable)
} SSBEdit;

typedef struct {
    SSBEdit *edits;
    int count;
} SSBDiffResult;

/// Computes the diff between two arrays of line hashes.
SSBDiffResult ssb_diff(const uint32_t *hashes_a, int count_a,
                       const uint32_t *hashes_b, int count_b,
                       SSBDiffAlgorithm algo);

/// Frees the memory allocated for a diff result.
void ssb_diff_free_result(SSBDiffResult result);

/// Computes a 32-bit FNV-1a hash for a line of text.
uint32_t ssb_diff_hash_line(const char *line, size_t length);

#endif
