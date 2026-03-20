#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBDiffCore.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBDiffAlgorithmType) {
    SSBDiffAlgorithmTypeMyers = SSB_DIFF_ALGORITHM_MYERS,
    SSBDiffAlgorithmTypePatience = SSB_DIFF_ALGORITHM_PATIENCE,
    SSBDiffAlgorithmTypeHistogram = SSB_DIFF_ALGORITHM_HISTOGRAM,
    SSBDiffAlgorithmTypeMinimal = SSB_DIFF_ALGORITHM_MINIMAL
};

typedef NS_ENUM(NSInteger, SSBDiffEditType) {
    SSBDiffEditTypeMatch = SSB_EDIT_MATCH,
    SSBDiffEditTypeAdd = SSB_EDIT_ADD,
    SSBDiffEditTypeDelete = SSB_EDIT_DELETE
};

@interface SSBDiffEdit : NSObject
@property (nonatomic, assign) SSBDiffEditType type;
@property (nonatomic, copy) NSString *lineContent;
@property (nonatomic, assign) NSInteger lineA;
@property (nonatomic, assign) NSInteger lineB;
@end

@interface SSBDiffHunk : NSObject
@property (nonatomic, assign) NSInteger startA;
@property (nonatomic, assign) NSInteger countA;
@property (nonatomic, assign) NSInteger startB;
@property (nonatomic, assign) NSInteger countB;
@property (nonatomic, strong) NSArray<SSBDiffEdit *> *edits;
- (NSString *)hunkHeader;
@end

@interface SSBDiffEngine : NSObject
- (NSArray<SSBDiffHunk *> *)diffString:(NSString *)stringA
                            withString:(NSString *)stringB
                             algorithm:(SSBDiffAlgorithmType)algorithm;
@end

NS_ASSUME_NONNULL_END
