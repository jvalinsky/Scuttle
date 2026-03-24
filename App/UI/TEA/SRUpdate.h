#import <Foundation/Foundation.h>
#import "SRAppModel.h"
#import "SRMsg.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Command Types

typedef NS_ENUM(NSInteger, SRCmdType) {
    SRCmdTypeNone,
    // Rooms
    SRCmdTypeLoadRooms,
    SRCmdTypeConnectRoom,
    SRCmdTypeDisconnectRoom,
    // Feed
    SRCmdTypeLoadFeed,
    SRCmdTypeLoadMoreFeed,
    SRCmdTypePublishMessage,
    // Peers
    SRCmdTypeLoadPeers,
    SRCmdTypeConnectToPeer,
    // Git
    SRCmdTypeLoadGitRepos,
    // Subscriptions
    SRCmdTypeSubscribeRoomStatus,
    SRCmdTypeSubscribePeers,
    SRCmdTypeSubscribeFeed,
};

#pragma mark - Command

@interface SRCmd : NSObject
@property (nonatomic, readonly) SRCmdType cmdType;
@property (nonatomic, readonly, nullable) id payload;

+ (instancetype)none;
+ (instancetype)loadRooms;
+ (instancetype)connectRoom:(RoomConfig *)room;
+ (instancetype)disconnectRoom:(nullable RoomConfig *)room;
+ (instancetype)loadFeed:(NSString *)roomHost;
+ (instancetype)loadMoreFeed:(NSString *)roomHost beforeSeq:(NSInteger)seq;
+ (instancetype)publishMessage:(NSDictionary *)content replyTo:(nullable NSString *)replyKey cw:(nullable NSString *)cw;
+ (instancetype)loadPeers:(NSString *)roomHost;
+ (instancetype)connectToPeer:(NSString *)peerID;
+ (instancetype)loadGitRepos;
+ (instancetype)subscribeRoomStatus:(NSString *)roomHost;
+ (instancetype)subscribePeers:(NSString *)roomHost;
+ (instancetype)subscribeFeed:(NSString *)roomHost;
@end

#pragma mark - Update Result

@interface SRUpdateResult : NSObject
@property (nonatomic, readonly) SRAppModel *model;
@property (nonatomic, readonly) NSArray<SRCmd *> *commands;

- (instancetype)initWithModel:(SRAppModel *)model commands:(NSArray<SRCmd *> *)commands;

+ (instancetype)resultWithModel:(SRAppModel *)model;
+ (instancetype)resultWithModel:(SRAppModel *)model cmd:(SRCmd *)cmd;
+ (instancetype)resultWithModel:(SRAppModel *)model cmds:(NSArray<SRCmd *> *)cmds;
@end

#pragma mark - Update (Pure Functions)

@interface SRUpdate : NSObject

+ (SRUpdateResult *)updateWithModel:(SRAppModel *)model msg:(SRMsg *)msg;

@end

NS_ASSUME_NONNULL_END
