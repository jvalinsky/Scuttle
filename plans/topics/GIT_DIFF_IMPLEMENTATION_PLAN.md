# Git Diff Implementation Plan for Scuttle

This document outlines the strategy for implementing a native, multi-algorithm git diff engine in C and Objective-C for the Scuttle project.

---

## 1. Background & Algorithms

The Scuttle project requires a robust diffing utility to display changes between commits in the `SRGitDiffViewController`. We will support four key algorithms:

| Algorithm | Best For | Description |
|-----------|----------|-------------|
| **Myers** | Default | Balanced speed and minimality (standard). |
| **Patience** | Source Code | Best for avoiding "accidental" matches of common lines like `}`. |
| **Histogram**| Source Code | Robust, fast, and highly human-readable for code. |
| **Minimal** | Small Patches | Prioritizes shortest edit script at high compute cost. |

---

## 2. Technical Architecture

### 2.1 C Core (`Sources/SSBDiffCore.h/c`)
A pure C implementation ensures maximum performance and portability.

**Key Components:**
1.  **Line Hashing**: Convert input lines (strings) into 32-bit hashes (`uint32_t`) to accelerate comparisons.
2.  **Edit Script Representation**:
    ```c
    typedef enum { SSB_EDIT_MATCH, SSB_EDIT_ADD, SSB_EDIT_DELETE } SSBEditType;
    typedef struct {
        SSBEditType type;
        int line_a; // 0-indexed line in string A
        int line_b; // 0-indexed line in string B
    } SSBEdit;
    ```
3.  **Modular Engine**: A dispatcher function `ssb_diff(hashes_a, count_a, hashes_b, count_b, algorithm)` that returns an array of `SSBEdit` structs.

### 2.2 Objective-C Wrapper (`Sources/SSBDiffEngine.h/m`)
A high-level wrapper to bridge the C core with the Scuttle UI.

**Data Models:**
- `SSBDiffEdit`: Represents a single line change (Add, Remove, or Match/Context).
- `SSBDiffHunk`: A group of contiguous edits with header information (e.g., `@@ -1,4 +1,6 @@`).

**Interface:**
```objc
@interface SSBDiffEngine : NSObject
/// Computes the diff between two strings using the specified algorithm.
- (NSArray<SSBDiffHunk *> *)diffString:(NSString *)stringA 
                            withString:(NSString *)stringB 
                             algorithm:(SSBDiffAlgorithm)algorithm;
@end
```

---

## 3. Implementation Steps

### ✅ Phase 1: Core Logic (Sources/)
1.  Create `SSBDiffCore.h/c` with the hashing utility and the skeleton for the four algorithms.
2.  Implement the **Myers** algorithm (standard greedy SES).
3.  Implement the **Histogram** algorithm (least-frequent common line splitting).
4.  Implement the **Patience** algorithm (unique-line LIS backbone).

### ✅ Phase 2: ObjC Integration (Sources/)
1.  Create `SSBDiffEngine.h/m` and its associated data models.
2.  Add logic to split strings into lines and handle hashing before calling the C core.
3.  Implement "Hunk Grouping" (grouping contiguous edits and adding context lines).

### ✅ Phase 3: UI Integration (App/UI/)
1.  Update `SRGitDiffViewController.m` to use `SSBDiffEngine`.
2.  Implement the unified diff renderer in `NSTextView`:
    - Green background for additions (`+`).
    - Red background for deletions (`-`).
    - Blue/Gray for hunk headers (`@@`).
3.  Add a segmented control to the UI to allow users to switch algorithms (Myers vs. Histogram).

---

## 4. Verification & Performance

1.  **Unit Tests (`Tests/SSBDiffEngineTests.m`)**:
    - Test edge cases: empty files, identical files, complete rewrites.
    - Compare outputs between different algorithms for readability.
2.  **Threading**: All diffing operations MUST be performed on a background queue (e.g., `dispatch_async(dispatch_get_global_queue(...))`) to prevent UI hangs on large files.
3.  **Memory Management**: Ensure raw C buffers for hashes and edit scripts are properly freed or wrapped in `NSData` to avoid leaks.
