#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Defines the various states of an SSB Connection as it goes through the handshake and into Box Stream
typedef NS_ENUM(NSInteger, SSBConnectionState) {
    SSBConnectionStateInit = 0,
    SSBConnectionStateSHSHelloSent,
    SSBConnectionStateSHSHelloReceived,
    SSBConnectionStateSHSAuthSent,
    SSBConnectionStateSHSAuthReceived,
    SSBConnectionStateSHSAcceptSent,
    SSBConnectionStateSHSAcceptReceived,
    SSBConnectionStateBoxStream,
    SSBConnectionStateError,
    SSBConnectionStateClosed
};

@protocol SSBConnectionFSMDelegate <NSObject>
/// Called when the state machine determines data needs to be parsed for the current protocol state
- (void)connectionFSMDidRequestParse:(id)fSM;
/// Called when the handshake completes successfully and Box Stream starts
- (void)connectionFSMDidTransitionToBoxStream:(id)fSM;
/// Called when a fatal error occurs in protocol state
- (void)connectionFSM:(id)fSM didEncounterError:(NSError *)error;
@end

@interface SSBConnectionFSM : NSObject

@property (nonatomic, readonly) SSBConnectionState currentState;
@property (nonatomic, weak) id<SSBConnectionFSMDelegate> delegate;

- (instancetype)init;

/// Advances the state machine, typically called after a successful cryptographic step
- (void)advanceState;

/// Transitions the FSM into an error state
- (void)transitionToError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
