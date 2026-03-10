#import "SSBQueryEngine.h"

@implementation SSBQueryEngine

+ (BOOL)isValidQuery:(NSDictionary<NSString *, id> *)query {
    if (!query) return NO;
    
    id author = query[@"author"];
    id type = query[@"type"];
    id isPrivate = query[@"private"];
    
    // author MUST be a valid string (feed ID)
    if (![author isKindOfClass:[NSString class]] || [(NSString *)author length] == 0) {
        return NO;
    }
    
    // private MUST be a boolean
    if (![isPrivate isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    
    BOOL privateVal = [isPrivate boolValue];
    
    // type can be a string or null
    if (type != nil && ![type isEqual:[NSNull null]] && ![type isKindOfClass:[NSString class]]) {
        return NO;
    }
    
    // If private: true then type MUST be null
    if (privateVal && type != nil && ![type isEqual:[NSNull null]]) {
        return NO;
    }
    
    return YES;
}

+ (BOOL)evaluateQuery:(NSDictionary<NSString *, id> *)query againstMessage:(NSDictionary<NSString *, id> *)message {
    if (![self isValidQuery:query]) return NO;
    
    NSString *queryAuthor = query[@"author"];
    id queryType = query[@"type"];
    BOOL queryPrivate = [query[@"private"] boolValue];
    
    NSString *msgAuthor = message[@"author"];
    id msgContent = message[@"content"];
    
    // Match author
    if (![queryAuthor isEqualToString:msgAuthor]) {
        return NO;
    }
    
    // Detect privacy
    BOOL msgIsPrivate = NO;
    if ([msgContent isKindOfClass:[NSString class]]) {
        NSString *contentStr = (NSString *)msgContent;
        if ([contentStr hasSuffix:@".box"] || [contentStr hasSuffix:@".box2"]) {
            msgIsPrivate = YES;
        }
    }
    
    if (queryPrivate != msgIsPrivate) {
        return NO;
    }
    
    // Match type (if queryPrivate is false)
    if (!queryPrivate && queryType != nil && ![queryType isEqual:[NSNull null]]) {
        NSString *msgType = [msgContent isKindOfClass:[NSDictionary class]] ? msgContent[@"type"] : nil;
        if (![queryType isEqualToString:msgType]) {
            return NO;
        }
    }
    
    return YES;
}

+ (NSDictionary<NSString *, id> *)sqlFragmentForQuery:(NSDictionary<NSString *, id> *)query {
    if (![self isValidQuery:query]) return @{};
    
    NSString *queryAuthor = query[@"author"];
    id queryType = query[@"type"];
    BOOL queryPrivate = [query[@"private"] boolValue];
    
    NSMutableArray<NSString *> *clauses = [NSMutableArray array];
    NSMutableArray *params = [NSMutableArray array];
    
    [clauses addObject:@"author = ?"];
    [params addObject:queryAuthor];
    
    [clauses addObject:@"is_private = ?"];
    [params addObject:@(queryPrivate ? 1 : 0)];
    
    if (!queryPrivate && queryType != nil && ![queryType isEqual:[NSNull null]]) {
        [clauses addObject:@"content_type = ?"];
        [params addObject:queryType];
    }
    
    NSString *sql = [clauses componentsJoinedByString:@" AND "];
    
    return @{
        @"sql": sql,
        @"params": params
    };
}

@end