// SRNotificationNames.h
// Centralized notification name constants and userInfo key constants.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when a room is selected. userInfo key: SRRoomManagerRoomSelectedKey -> RoomConfig *
extern NSString * const SRRoomManagerRoomSelectedNotification;
extern NSString * const SRRoomManagerRoomSelectedKey;

/// Posted when a new message is received or published. userInfo key: SRNewMessageKey -> SSBMessage *
extern NSString * const SRNewMessageNotification;
extern NSString * const SRNewMessageKey;

/// Posted when a new local identity is generated. No userInfo.
extern NSString * const SRLocalIdentityGeneratedNotification;

/// Posted when a room sync status changes. userInfo: @"status", @"progress", optionally @"author"
extern NSString * const SRRoomSyncStatusChangedNotification;

/// Posted after a lipmaa integrity check completes for a GabbyGrove/Bamboo feed.
/// userInfo: @"author" (NSString feed ID), @"verified" (NSNumber BOOL)
extern NSString * const SRFeedIntegrityDidUpdateNotification;

NS_ASSUME_NONNULL_END
