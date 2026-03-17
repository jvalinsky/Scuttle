#import "SSBDiffEngine.h"

@implementation SSBDiffEdit
@end

@implementation SSBDiffHunk
- (NSString *)hunkHeader {
    return [NSString stringWithFormat:@"@@ -%ld,%ld +%ld,%ld @@", 
            (long)self.startA + 1, (long)self.countA, 
            (long)self.startB + 1, (long)self.countB];
}
@end

@implementation SSBDiffEngine

- (NSArray<SSBDiffHunk *> *)diffString:(NSString *)stringA
                            withString:(NSString *)stringB
                             algorithm:(SSBDiffAlgorithmType)algorithm {
    NSArray<NSString *> *linesA = [stringA componentsSeparatedByString:@"\n"];
    NSArray<NSString *> *linesB = [stringB componentsSeparatedByString:@"\n"];
    
    uint32_t *hashesA = malloc(sizeof(uint32_t) * linesA.count);
    uint32_t *hashesB = malloc(sizeof(uint32_t) * linesB.count);
    
    for (NSUInteger i = 0; i < linesA.count; i++) {
        const char *cLine = [linesA[i] UTF8String];
        hashesA[i] = ssb_diff_hash_line(cLine, strlen(cLine));
    }
    for (NSUInteger i = 0; i < linesB.count; i++) {
        const char *cLine = [linesB[i] UTF8String];
        hashesB[i] = ssb_diff_hash_line(cLine, strlen(cLine));
    }
    
    SSBDiffResult result = ssb_diff(hashesA, (int)linesA.count, hashesB, (int)linesB.count, (SSBDiffAlgorithm)algorithm);
    
    NSMutableArray<SSBDiffEdit *> *allEdits = [NSMutableArray arrayWithCapacity:result.count];
    for (int i = 0; i < result.count; i++) {
        SSBDiffEdit *edit = [[SSBDiffEdit alloc] init];
        edit.type = (SSBDiffEditType)result.edits[i].type;
        edit.lineA = result.edits[i].line_a;
        edit.lineB = result.edits[i].line_b;
        
        if (edit.type == SSBDiffEditTypeDelete || edit.type == SSBDiffEditTypeMatch) {
            edit.lineContent = linesA[edit.lineA];
        } else {
            edit.lineContent = linesB[edit.lineB];
        }
        [allEdits addObject:edit];
    }
    
    ssb_diff_free_result(result);
    free(hashesA);
    free(hashesB);
    
    // Group edits into hunks
    return [self groupEditsIntoHunks:allEdits];
}

- (NSArray<SSBDiffHunk *> *)groupEditsIntoHunks:(NSArray<SSBDiffEdit *> *)edits {
    if (edits.count == 0) return @[];
    
    NSMutableArray<SSBDiffHunk *> *hunks = [NSMutableArray array];
    SSBDiffHunk *currentHunk = nil;
    NSMutableArray<SSBDiffEdit *> *hunkEdits = nil;
    
    for (SSBDiffEdit *edit in edits) {
        if (edit.type != SSBDiffEditTypeMatch) {
            if (!currentHunk) {
                currentHunk = [[SSBDiffHunk alloc] init];
                hunkEdits = [NSMutableArray array];
                currentHunk.startA = (edit.lineA >= 0) ? edit.lineA : 0;
                currentHunk.startB = (edit.lineB >= 0) ? edit.lineB : 0;
            }
            [hunkEdits addObject:edit];
        } else if (currentHunk) {
            currentHunk.edits = hunkEdits;
            [self finalizeHunk:currentHunk];
            [hunks addObject:currentHunk];
            currentHunk = nil;
            hunkEdits = nil;
        }
    }
    
    if (currentHunk) {
        currentHunk.edits = hunkEdits;
        [self finalizeHunk:currentHunk];
        [hunks addObject:currentHunk];
    }
    
    return hunks;
}

- (void)finalizeHunk:(SSBDiffHunk *)hunk {
    NSInteger countA = 0;
    NSInteger countB = 0;
    for (SSBDiffEdit *edit in hunk.edits) {
        if (edit.type == SSBDiffEditTypeDelete || edit.type == SSBDiffEditTypeMatch) countA++;
        if (edit.type == SSBDiffEditTypeAdd || edit.type == SSBDiffEditTypeMatch) countB++;
    }
    hunk.countA = countA;
    hunk.countB = countB;
}

@end
