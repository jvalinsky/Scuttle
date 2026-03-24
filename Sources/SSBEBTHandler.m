#import "SSBEBTHandler.h"
#import "SSBMuxRPCSession.h"
#import "SSBMessageCodec.h"
#import "SSBFeedStore.h"
#import "SSBLogger.h"

@interface SSBEBTHandler ()
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong) NSMapTable<SSBMuxRPCSession *, NSNumber *> *ebtRequestIDsBySession;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *peerEBTState;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *remoteClock;
@end

@implementation SSBEBTHandler

- (instancetype)initWithFeedStore:(SSBFeedStore *)feedStore
                      clientQueue:(dispatch_queue_t)clientQueue {
    self = [super init];
    if (self) {
        _feedStore = feedStore;
        _clientQueue = clientQueue;
        _ebtRequestIDsBySession = [NSMapTable weakToStrongObjectsMapTable];
        _peerEBTState = [NSMutableDictionary dictionary];
        _remoteClock = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)startReplicationWithSession:(SSBMuxRPCSession *)session peerID:(NSString *)peerID {
    if (!session) return;
    
    dispatch_async(self.clientQueue, ^{
        if ([self.ebtRequestIDsBySession objectForKey:session] != nil) return;

        NSDictionary<NSString *, NSNumber *> *rawClock = [self.feedStore localClock];
        NSMutableDictionary<NSString *, NSNumber *> *clock = [NSMutableDictionary dictionaryWithCapacity:rawClock.count + 1];

        // Encode EBT notes with bit-shifting: note = (seq << 1) | receive_flag
        for (NSString *author in rawClock) {
            NSInteger seq = [rawClock[author] integerValue];
            NSInteger note = (seq << 1) | 0; // 0 = we want to receive updates
            clock[author] = @(note);
        }

        if (peerID && !clock[peerID]) {
            clock[peerID] = @((0 << 1) | 0); // seq=0, want to receive
        }
        
        NSDictionary *args = @{@"version": @3, @"format": @"classic"};

        __weak typeof(self) weakSelf = self;
        __weak SSBMuxRPCSession *weakSession = session;
        SSBRPCCallback ebtCallback = ^(id _Nullable response, NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            __strong SSBMuxRPCSession *strongSession = weakSession;
            if (!strongSelf) return;
            if (error) {
                SSBLogError(SSBLogCategorySync, @"EBT Replication stream error: %@", error);
                if (strongSession) {
                    [strongSelf.ebtRequestIDsBySession removeObjectForKey:strongSession];
                }
                return;
            }
            if (!strongSession) return;
            [strongSelf handleMessage:response requestID:0 flags:0 session:strongSession peerID:peerID];
        };

        int32_t requestID = [session sendRequest:@[@"ebt", @"replicate"] args:@[args] type:@"duplex" completion:ebtCallback];
        if (requestID <= 0) {
            SSBLogError(SSBLogCategorySync, @"Failed to start EBT replication request for session %@", session);
            return;
        }
        [self.ebtRequestIDsBySession setObject:@(requestID) forKey:session];

        // Send initial clock
        [session sendData:clock forRequest:requestID isEnd:NO];
        SSBLogInfo(SSBLogCategorySync, @"Started EBT replication with peer %@ (req=%d), clock of %lu feeds", peerID, requestID, (unsigned long)clock.count);
    });
}

- (void)handleMessage:(id)message
            requestID:(int32_t)reqID
                flags:(uint8_t)flags
              session:(SSBMuxRPCSession *)session
               peerID:(NSString *)peerID {
    
    if ([message isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)message;

        // Check if this is an RPC request rather than an EBT payload
        if (dict[@"name"] && dict[@"args"]) {
            NSArray *name = dict[@"name"];
            if ([name isKindOfClass:[NSArray class]] && name.count >= 2 && 
                [name[0] isEqualToString:@"ebt"] && [name[1] isEqualToString:@"replicate"]) {
                [self handleBilateralEBT:dict requestID:reqID session:session peerID:peerID];
            }
            return;
        }

        if (dict[@"author"] && dict[@"sequence"]) {
            // Raw signed value dict
            [self processIncomingMessage:dict fromPeer:peerID];
        } else if (dict[@"key"] && dict[@"value"]) {
            // Legacy {key, value} wrapper
            [self processIncomingMessage:dict fromPeer:peerID];
        } else {
            // Clock update
            [self handleRemoteClockUpdate:dict fromPeer:peerID session:session];
        }
    } else if ([message isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)message;
        // Try to parse as JSON first
        NSError *jsonError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&jsonError];
        if (!jsonError && [parsed isKindOfClass:[NSDictionary class]]) {
            [self handleMessage:parsed requestID:reqID flags:flags session:session peerID:peerID];
        } else {
            [self processIncomingMessage:data fromPeer:peerID];
        }
    }
}

- (void)handleBilateralEBT:(NSDictionary *)req requestID:(int32_t)reqID session:(SSBMuxRPCSession *)session peerID:(NSString *)peerID {
    SSBLogInfo(SSBLogCategorySync, @"Handling bilateral EBT request (ID=%d) from %@", reqID, peerID);

    int32_t responseReqID = -reqID;
    self.peerEBTState[peerID] = [@{
        @"requestID": @(responseReqID),
        @"clock": [NSMutableDictionary dictionary]
    } mutableCopy];

    NSDictionary<NSString *, NSNumber *> *rawClock = [self.feedStore localClock];
    NSMutableDictionary<NSString *, NSNumber *> *clock = [NSMutableDictionary dictionaryWithCapacity:rawClock.count];
    for (NSString *author in rawClock) {
        NSInteger seq = [rawClock[author] integerValue];
        clock[author] = @((seq << 1) | 0); // 0 = want to receive
    }
    if (peerID && !clock[peerID]) {
        clock[peerID] = @((0 << 1) | 0);
    }
    [session sendData:clock forRequest:responseReqID isEnd:NO];
}

- (void)handleRemoteClockUpdate:(NSDictionary *)update fromPeer:(NSString *)peerID session:(SSBMuxRPCSession *)session {
    NSMutableDictionary *targetClock = peerID ? self.peerEBTState[peerID][@"clock"] : self.remoteClock;
    if (!targetClock) targetClock = self.remoteClock;
    
    [update enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [val isKindOfClass:[NSNumber class]]) {
            NSString *author = (NSString *)key;
            NSInteger note = [val integerValue];

            if (note == -1) {
                targetClock[author] = @(-1);
                return;
            }

            NSInteger seq = note >> 1;
            targetClock[author] = @(seq);
            [self.delegate ebtHandler:self didUpdateSyncProgress:0.0 author:author status:[NSString stringWithFormat:@"Receiving: .../%ld", (long)seq]];
        }
    }];

    [self sendPendingMessagesForClock:update toPeer:peerID session:session];
}

- (void)sendPendingMessagesForClock:(NSDictionary *)remoteClock
                              toPeer:(NSString *)peerID
                             session:(SSBMuxRPCSession *)session {
    
    int32_t sendReqID = 0;
    if (peerID && self.peerEBTState[peerID]) {
        sendReqID = [self.peerEBTState[peerID][@"requestID"] intValue];
    } else {
        sendReqID = [[self.ebtRequestIDsBySession objectForKey:session] intValue];
    }
    
    if (sendReqID == 0) return;

    NSDictionary<NSString *, NSNumber *> *localClock = [self.feedStore localClock];
    
    for (NSString *author in remoteClock) {
        id val = remoteClock[author];
        if (![val isKindOfClass:[NSNumber class]]) continue;
        NSInteger note = [val integerValue];
        if (note == -1) continue;

        NSInteger remoteSeq = note >> 1;
        BOOL peerWantsToReceive = (note & 1) == 0;
        if (!peerWantsToReceive) continue;

        NSInteger localSeq = [localClock[author] integerValue];
        if (localSeq <= remoteSeq) continue;

        NSArray<SSBMessage *> *msgs = [self.feedStore messagesForAuthor:author
                                                           fromSequence:remoteSeq + 1
                                                                  limit:localSeq - remoteSeq];
        for (SSBMessage *msg in msgs) {
            NSDictionary *envelope = [self ebtEnvelopeForMessage:msg];
            if (envelope) {
                [session sendData:envelope forRequest:sendReqID isEnd:NO];
            }
        }
    }
}

- (nullable NSDictionary *)ebtEnvelopeForMessage:(SSBMessage *)msg {
    if (!msg.valueJSON) return nil;
    return [NSJSONSerialization JSONObjectWithData:msg.valueJSON options:0 error:nil];
}

- (void)processIncomingMessage:(id)response fromPeer:(NSString *)peerID {
    NSData *rawData = nil;
    NSDictionary *dict = nil;
    
    if ([response isKindOfClass:[NSData class]]) {
        rawData = (NSData *)response;
        dict = [NSJSONSerialization JSONObjectWithData:rawData options:0 error:nil];
    } else if ([response isKindOfClass:[NSDictionary class]]) {
        dict = (NSDictionary *)response;
        // We don't have raw data here, so we'll have to re-encode for verification if needed
    }
    
    if (!dict) return;

    NSDictionary *val;
    NSString *key;
    if (dict[@"author"] && dict[@"sequence"]) {
        val = dict;
        key = [SSBMessageCodec computeMessageKey:val];
    } else if (dict[@"value"]) {
        val = dict[@"value"];
        key = dict[@"key"];
    } else {
        return;
    }

    // Use our new robust verification if we have raw data
    BOOL verified = NO;
    if (rawData) {
        verified = [[SSBMessageCodec sharedCodec] verifyMessageData:rawData error:nil];
    } else {
        verified = [SSBMessageCodec verifyMessage:val];
    }

    if (verified) {
        SSBMessage *msg = [[SSBMessage alloc] init];
        msg.key = key;
        msg.author = val[@"author"];
        msg.sequence = [val[@"sequence"] integerValue];
        msg.previousKey = val[@"previous"];
        msg.claimedTimestamp = [val[@"timestamp"] longLongValue];
        msg.content = val[@"content"];
        msg.contentType = msg.content[@"type"];
        msg.valueJSON = [SSBMessageCodec encodeLegacyValue:val includeSignature:YES];
        
        if ([self.feedStore appendMessage:msg error:nil]) {
            [self.delegate ebtHandler:self didReplicateMessage:val author:msg.author];
        }
    }
}

- (NSDictionary<NSString *, NSNumber *> *)currentClockForPeer:(NSString *)peerID {
    return self.peerEBTState[peerID][@"clock"] ?: @{};
}

@end
