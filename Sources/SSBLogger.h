#import <Foundation/Foundation.h>
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBLogLevel) {
    SSBLogLevelDebug = 0,
    SSBLogLevelInfo = 1,
    SSBLogLevelWarning = 2,
    SSBLogLevelError = 3
};

typedef NS_ENUM(NSInteger, SSBLogCategory) {
    SSBLogCategoryGeneral = 0,
    SSBLogCategoryUI = 1,
    SSBLogCategorySync = 2,
    SSBLogCategoryNetwork = 3,
    SSBLogCategoryFeed = 4,
    SSBLogCategoryProfile = 5,
    SSBLogCategoryReplication = 6,
    SSBLogCategoryDatabase = 7,
    SSBLogCategoryAuth = 8
};

static inline NSString *SSBLogCategoryName(SSBLogCategory cat) {
    switch (cat) {
        case SSBLogCategoryGeneral: return @"General";
        case SSBLogCategoryUI: return @"UI";
        case SSBLogCategorySync: return @"Sync";
        case SSBLogCategoryNetwork: return @"Network";
        case SSBLogCategoryFeed: return @"Feed";
        case SSBLogCategoryProfile: return @"Profile";
        case SSBLogCategoryReplication: return @"Replication";
        case SSBLogCategoryDatabase: return @"Database";
        case SSBLogCategoryAuth: return @"Auth";
        default: return @"Unknown";
    }
}

@interface SSBLogger : NSObject

@property (class, nonatomic, readonly) SSBLogger *shared;
@property (nonatomic, assign) SSBLogLevel minimumLevel;

- (os_log_t)logForCategory:(SSBLogCategory)category;
- (void)log:(SSBLogCategory)category level:(SSBLogLevel)level message:(NSString *)message;
- (void)log:(SSBLogCategory)category level:(SSBLogLevel)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(3, 4);

- (void)debug:(NSString *)message category:(SSBLogCategory)category;
- (void)info:(NSString *)message category:(SSBLogCategory)category;
- (void)warning:(NSString *)message category:(SSBLogCategory)category;
- (void)error:(NSString *)message category:(SSBLogCategory)category;

- (NSString *)stateToString:(NSString *)stateName value:(NSInteger)value;
- (void)logStateTransition:(NSString *)stateName from:(NSInteger)from to:(NSInteger)to category:(SSBLogCategory)category;

@end

// Convenience macros with built-in category
#define SSBLogDebug(cat, msg, ...) [[SSBLogger shared] log:cat level:SSBLogLevelDebug message:[NSString stringWithFormat:msg, ##__VA_ARGS__]]
#define SSBLogInfo(cat, msg, ...) [[SSBLogger shared] log:cat level:SSBLogLevelInfo message:[NSString stringWithFormat:msg, ##__VA_ARGS__]]
#define SSBLogWarning(cat, msg, ...) [[SSBLogger shared] log:cat level:SSBLogLevelWarning message:[NSString stringWithFormat:msg, ##__VA_ARGS__]]
#define SSBLogError(cat, msg, ...) [[SSBLogger shared] log:cat level:SSBLogLevelError message:[NSString stringWithFormat:msg, ##__VA_ARGS__]]

// Convenience macros for common categories
#define SSBLogUI(msg, ...) SSBLogDebug(SSBLogCategoryUI, msg, ##__VA_ARGS__)
#define SSBLogSync(msg, ...) SSBLogDebug(SSBLogCategorySync, msg, ##__VA_ARGS__)
#define SSBLogProfile(msg, ...) SSBLogDebug(SSBLogCategoryProfile, msg, ##__VA_ARGS__)
#define SSBLogFeed(msg, ...) SSBLogDebug(SSBLogCategoryFeed, msg, ##__VA_ARGS__)
#define SSBLogNetwork(msg, ...) SSBLogDebug(SSBLogCategoryNetwork, msg, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
