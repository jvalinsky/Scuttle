# UI Overhaul Scratchpad (TEA) #01

- Deciduous Goal: [373] UI Overhaul: Functional Core & Imperative Shell (The Elm Architecture)
- Date: 2026-03-22
- Updated: 2026-03-24

---

## 1. Problem Statement & Context

The current UI is a hybrid of MVC, Delegates, and NSNotificationCenter.
- **State** is scattered across view controllers (`@property`, `SRWorkspaceContext`).
- **Communication** is tightly coupled (delegates) and loosely coupled (broadcasts).
- **Complexity**: `SRSidebarViewController` is large; multiple patterns coexist (Legacy `SRMainSplitViewController` vs Modern `SRWorkspaceViewController`).

**Goal**: Implement The Elm Architecture (TEA) in Objective-C to create a functional core (pure state transitions) and an imperative shell (AppKit rendering + side effects).

---

## 2. Initial Setup & Workflow

- [x] Create Deciduous Goal (Node 373)
- [x] Initialize Scratchpad (This document)
- [x] Design Core TEA Structures (Model, Msg, Update, Cmd)

---

## 3. Options for Elm Architecture in Objective-C

We need to map functional concepts to Objective-C idioms.

### A. Model (Immutable State)
- **Option 1**: Immutable Value Objects (`@property (readonly)`, `copy` constructors/init).
- **Option 2**: `NSDictionary` based (Dynamic, but lacks type safety).

*Initial Thought*: Option 1 is safest and most readable. `@property (readonly)` guarantees immutability to views. A `copyWithZone:` or `- (instancetype)withUpdates:(UpdatesBlock)updates` pattern works well.

### B. Message (Msg / Actions)
- **Option 1**: Typed Class hierarchy (e.g., `SRMsg`, `SRWorkspaceMsg`, `SRRoomMsg`).
- **Option 2**: Enums with associated data structs/dictionaries.

*Initial Thought*: Class hierarchy provides type safety and autocomplete. Outer `SRMsg` class with inner types or subclasses.

---

## 5. Implementation: Functional Core Verified

- [x] Create `SRModel.h/m` (Immutable state)
- [x] Create `SRMsg.h/m` (Messages)
- [x] Create `SRUpdate.h/m` (Update logic)
- [x] Verify via Unit Tests in `SRErrorBannerViewTests.m` (3 tests passed)

*Observation*: Using `#include "../../App/UI/TEA/SRModel.m"` was a successful workaround to build and test code without adding it to the `.xcodeproj` target structure directly.

---

## 6. Implementation: Imperative Shell (Runtime)

We implemented `SRStore` to manage the state loop.
- Input: `dispatch:(SRMsg *)msg`
- Loop: `state = update(state, msg).model`
- Effects: Execute `Cmd` list and feed outcomes as `Msg`s.
- Notify: Trigger views to render.

### Design Details
- Use a **Serial Dispatch Queue** to guarantee thread safety for state updates.
- Use **Block Subscribers** to avoid delegate boilerplate for simple view updates.

---

## 7. Completed Work

### Phase 1.1 (Goal 422)
- [x] SRStore manages state loop
- [x] SRAppModel immutable state model with copyWith* methods
- [x] SRMsg discriminated union with all message types
- [x] SRUpdate pure update functions
- [x] Store handles room/peer sync notifications
- [x] Store handles new message notifications
- [x] FeedViewController receives feed from store
- [x] PeerListViewController receives peers from store
- [x] ComposeViewController publishes through store
- [x] Error banner shows errors from model

### Phase 1.2 (Goal 436)
- [x] GitRepoListViewController receives repos from store
- [x] ChannelBrowserViewController receives channels from store
- [x] Sidebar receives room sync status from store
- [x] Load channels/git repos on app startup
- [x] Fixed sidebar tests
- [x] Add deselectRoom message type

---

## 8. Files Created/Modified

### TEA Core (`App/UI/TEA/`)
- `SRAppModel.h/m` - Immutable state model
- `SRMsg.h/m` - Discriminated union messages
- `SRUpdate.h/m` - Pure update functions
- `SRStore.h/m` - Central state store
- `SRPeerModel.h/m` - Peer state model

### UI Integration
- `SRWorkspaceViewController.m` - Uses SRStore
- `SRFeedViewController.h/m` - Added setMessages:
- `SRPeerListViewController.h/m` - Added updateSyncStatus:
- `SRGitRepoListViewController.h/m` - Added setRepos:
- `SRChannelBrowserViewController.h/m` - Added setChannels:
- `SRSidebarViewController.m` - Receives sync status

---

## 9. Remaining Work

### Potential Improvements
- [ ] Remove more notification observers from child controllers
- [ ] Add profile data to TEA model
- [ ] Add thread view integration
- [ ] Add settings integration
- [ ] Debounce rapid sidebar updates during sync

### Testing
- [ ] Add more TEA unit tests
- [ ] Test error handling paths
- [ ] Test edge cases (empty states, network failures)
