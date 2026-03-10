#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// SSBQueryEngine implements the ssb-ql-0 query language (SIP-003).
/// It can evaluate queries against message objects or generate SQL fragments.
@interface SSBQueryEngine : NSObject

/// Validates if a dictionary is a valid ssb-ql-0 query.
+ (BOOL)isValidQuery:(NSDictionary<NSString *, id> *)query;

/// Evaluates an ssb-ql-0 query against a message dictionary.
/// @param query The ssb-ql-0 query.
/// @param message The message value dictionary (containing 'author', 'content', etc.)
+ (BOOL)evaluateQuery:(NSDictionary<NSString *, id> *)query againstMessage:(NSDictionary<NSString *, id> *)message;

/// Generates a SQL WHERE clause fragment and parameter list for a given ssb-ql-0 query.
/// Returns a tuple-like dictionary with @"sql" and @"params".
+ (NSDictionary<NSString *, id> *)sqlFragmentForQuery:(NSDictionary<NSString *, id> *)query;

@end

NS_ASSUME_NONNULL_END