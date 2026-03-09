#import "SSBConnectionFSM.h"

@interface SSBConnectionFSM ()
@property (nonatomic, readwrite) SSBConnectionState currentState;
@end

@implementation SSBConnectionFSM

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
    
    SSBConnectionState oldState = self.currentState;
    _currentState++;
    NSLog(@"[FSM] State advanced: %ld -> %ld", (long)oldState, (long)self.currentState);
    
    if (self.currentState == SSBConnectionStateBoxStream) {
        NSLog(@"[FSM] Notifying delegate of BoxStream transition...");
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
