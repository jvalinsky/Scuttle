include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = scuttle-cli

scuttle-cli_OBJC_FILES = \
    Sources/ScuttleCLI.m \
    Sources/SSBKeychain_Linux.m \
    Sources/SSBFeedStore.m \
    Sources/SSBRoomClient.m \
    Sources/RoomInviteHandler.m \
    Sources/RoomStorage.m \
    Sources/SSBBlobStore.m \
    Sources/SSBLog.m \
    Sources/SSBLogger.m \
    Sources/SSBSecretHandshake.m \
    Sources/SSBMessageCodec.m \
    Sources/SSBBIPF.m \
    Sources/SSBMuxRPC.m \
    Sources/SSBMuxRPCFramer.m \
    Sources/SSBMuxRPCSession.m \
    Sources/SSBSecurityFramer.m \
    Sources/SSBConnectionFSM.m \
    Sources/SSBTunnelConnection.m \
    Sources/SSBTangle.m \
    Sources/SSBJITDB.m \
    Sources/SSBStateMachine.m \
    Sources/SSBQueryEngine.m \
    Sources/SSBIndexFeed.m \
    Sources/SSBIndexFeedGenerator.m \
    Sources/SSBMetafeed.m \
    Sources/SSBButtwoo.m \
    Sources/SSBBendyButt.m \
    Sources/SSBBFE.m \
    Sources/SSBMessage.m \
    Sources/SSBBamboo.m \
    Sources/SSBBencode.m \
    Sources/SSBBitset.m \
    Sources/SSBBoxStream.m \
    Sources/SSBDiffEngine.m \
    Sources/SSBPrefixIndex.m \
    Sources/SSBURI.m \
    Sources/SSBThread.m \
    Sources/SSBFeedCodecRegistry.m \
    Sources/SSBGitRepo.m \
    Sources/SSBGitObjectStore.m \
    Sources/SSBGitPackDecoder.m \
    Sources/SSBGitPackIDXParser.m \
    Sources/SSBGitIssueStore.m \
    Sources/SSBGitPRStore.m \
    Sources/SSBNetworkShim.m \
    Sources/SSBURLSessionShim.m \
    App/Logic/SRNotificationNames.m

scuttle-cli_C_FILES = \
    Sources/tweetnacl.c \
    Sources/blake2b.c \
    Sources/blake3.c \
    Sources/randombytes.c \
    Sources/SSBDiffCore.c

# 2026: Enable modern Objective-C features
ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -I./Sources -I./App/Logic
ADDITIONAL_LDFLAGS += -ldispatch -lobjc -lcrypto -lsqlite3 -lz

include $(GNUSTEP_MAKEFILES)/tool.make
