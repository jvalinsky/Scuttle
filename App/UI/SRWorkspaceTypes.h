#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SRWorkspaceContext) {
    SRWorkspaceContextFeeds = 0,
    SRWorkspaceContextGit,
    SRWorkspaceContextNetwork,
    SRWorkspaceContextSettings
};

typedef NS_ENUM(NSInteger, SRDestination) {
    SRDestinationHome = 0,
    SRDestinationChannels,
    SRDestinationRepos,
    SRDestinationPeers
};
