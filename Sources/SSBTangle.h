#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBTangleType) {
    SSBTangleTypeSingleAuthor,
    SSBTangleTypeMultiAuthor
};

@interface SSBTangleData : NSObject
@property (nonatomic, copy, nullable) NSString *root;
@property (nonatomic, copy, nullable) NSArray<NSString *> *previous;
@end

@interface SSBTangle : NSObject

#pragma mark - Creation & Parsing

+ (nullable SSBTangleData *)tangleDataWithRoot:(nullable NSString *)root
                                       previous:(nullable NSArray<NSString *> *)previous;

+ (nullable SSBTangleData *)parseTangleData:(NSString *)tangleName
                                 fromContent:(NSDictionary<NSString *, id> *)content;

#pragma mark - Validation

+ (BOOL)validateMessage:(SSBMessage *)message
                inTangle:(NSString *)tangleName
             allMessages:(NSDictionary<NSString *, SSBMessage *> *)allMessages;

+ (BOOL)validateClassicFeedMessage:(SSBMessage *)message
                        allMessages:(NSDictionary<NSString *, SSBMessage *> *)allMessages;

#pragma mark - Graph Operations

+ (NSArray<SSBMessage *> *)topologicalSort:(NSArray<SSBMessage *> *)messages
                                  tangleName:(NSString *)tangleName
                                tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

+ (NSArray<NSArray<NSString *> *> *)detectForksInTangle:(NSString *)tangleName
                                               messages:(NSArray<SSBMessage *> *)messages
                                          tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

+ (NSArray<NSString *> *)findTipsInTangle:(NSString *)tangleName
                                  messages:(NSArray<SSBMessage *> *)messages
                             tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

+ (BOOL)isMessage:(NSString *)messageId
      connectedTo:(NSString *)targetId
          inTangle:(NSString *)tangleName
          messages:(NSArray<SSBMessage *> *)messages
     tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

#pragma mark - Classic Feed (Single Author)

+ (SSBTangleType)tangleTypeForMessages:(NSArray<SSBMessage *> *)messages
                              tangleName:(NSString *)tangleName
                            tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

+ (nullable NSString *)findRootForTangle:(NSString *)tangleName
                                 messages:(NSArray<SSBMessage *> *)messages
                            tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

+ (nullable NSArray<NSString *> *)previousForNewMessageInTangle:(NSString *)tangleName
                                                        messages:(NSArray<SSBMessage *> *)messages
                                                   tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap;

#pragma mark - Helpers

+ (NSDictionary<NSString *, SSBTangleData *> *)tangleDataMapForMessages:(NSArray<SSBMessage *> *)messages;

+ (nullable NSString *)extractMessageIdFromKey:(NSString *)key;

+ (NSArray<NSString *> *)filterValidMessageIds:(NSArray<NSString *> *)ids
                                    allMessages:(NSDictionary<NSString *, SSBMessage *> *)allMessages;

@end

NS_ASSUME_NONNULL_END
