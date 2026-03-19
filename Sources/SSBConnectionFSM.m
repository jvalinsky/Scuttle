#import "SSBConnectionFSM.h"
#import "SSBLogCompat.h"

static os_log_t fsm_log;

@interface SSBConnectionFSM ()
@property (nonatomic, readwrite) SSBConnectionState currentState;
@end

@implementation SSBConnectionFSM

+ (void)initialize {
    if (self == [SSBConnectionFSM class]) {
        fsm_log = os_log_create("com.scuttlebutt.network", "ConnectionFSM");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentState = SSBConnectionStateInit;
    }
    return self;
}

- (void)advanceState {
    if (self.currentState == SSBConnectionStateError || self.currentState == SSBConnectionStateClosed) {
        return;
    }

    SSBConnectionState nextState;
    switch (self.currentState) {
        case SSBConnectionStateInit:
            nextState = SSBConnectionStateSHSHelloSent;
            break;
        case SSBConnectionStateSHSHelloSent:
            nextState = SSBConnectionStateSHSHelloReceived;
            break;
        case SSBConnectionStateSHSHelloReceived:
            nextState = SSBConnectionStateSHSAuthSent;
            break;
        case SSBConnectionStateSHSAuthSent:
            nextState = SSBConnectionStateSHSAuthReceived;
            break;
        case SSBConnectionStateSHSAuthReceived:
            nextState = SSBConnectionStateSHSAcceptSent;
            break;
        case SSBConnectionStateSHSAcceptSent:
            nextState = SSBConnectionStateSHSAcceptReceived;
            break;
        case SSBConnectionStateSHSAcceptReceived:
            nextState = SSBConnectionStateBoxStream;
            break;
        case SSBConnectionStateBoxStream:
            return;
        default:
            NSAssert(NO, @"advanceState called from unexpected state %ld", (long)self.currentState);
            return;
    }

    SSBConnectionState oldState = self.currentState;
    _currentState = nextState;
    os_log_info(fsm_log, "State advanced: %ld -> %ld", (long)oldState, (long)_currentState);

    if (_currentState == SSBConnectionStateBoxStream) {
        if ([self.delegate respondsToSelector:@selector(connectionFSMDidTransitionToBoxStream:)]) {
            [self.delegate connectionFSMDidTransitionToBoxStream:self];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(connectionFSMDidRequestParse:)]) {
            [self.delegate connectionFSMDidRequestParse:self];
        }
    }
}

- (void)transitionToError:(NSError *)error {
    self.currentState = SSBConnectionStateError;
    if ([self.delegate respondsToSelector:@selector(connectionFSM:didEncounterError:)]) {
        [self.delegate connectionFSM:self didEncounterError:error];
    }
}

@end
