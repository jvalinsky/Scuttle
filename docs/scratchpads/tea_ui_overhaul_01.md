# UI Overhaul Scratchpad (TEA) #01

- Deciduous Goal: [373] UI Overhaul: Functional Core & Imperative Shell (The Elm Architecture)
- Date: 2026-03-22

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
- [ ] Design Core TEA Structures (Model, Msg, Update, Cmd)

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

## 6. Next Component: Imperative Shell (Runtime)

We need `SRStore` to manage the state loop.
- Input: `dispatch:(SRMsg *)msg`
- Loop: `state = update(state, msg).model`
- Effects: Execute `Cmd` list and feed outcomes as `Msg`s.
- Notify: Trigger views to render.

### Design Details
- Use a **Serial Dispatch Queue** to guarantee thread safety for state updates.
- Use **Block Subscribers** to avoid delegate boilerplate for simple view updates.

---

## 7. Next Steps

1.  Implement `SRStore.h/m`.
2.  Wire up `SRWorkspaceViewController` to use the Store.
3.  Add view updates/rendering cycle.

