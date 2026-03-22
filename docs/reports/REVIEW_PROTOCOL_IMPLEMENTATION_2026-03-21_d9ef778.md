# Protocol Implementation Review — Senior ObjC/macOS Engineering Critique

**Date:** 2026-03-21
**Commit:** `d9ef778` (Create Virtualization Support Plan)
**Scope:** 16+ protocol definitions, ~30 concrete implementations, 13 delegate protocols across SSBNetwork framework and ScuttleRoomApp

---

## What's Done Well

**Transport abstraction is textbook.** The `SSBTransportConnection` / `SSBTransportListener` / `SSBTransportBackend` trinity is a clean, well-layered abstraction that mirrors Apple's own Network.framework design idioms. Protocol-returning factory methods on `SSBTransportBackend` allow transparent backend swapping (Apple vs. Linux) — this is exactly how Apple engineers platform abstraction in frameworks like AVFoundation.

**Feed codec registry is excellent.** `SSBFeedCodec` + `SSBFeedCodecRegistry` with `+load`-based self-registration is a proven Cocoa pattern. The protocol surface is tight (two properties, two methods), and the registry uses reader-writer dispatch for thread safety. This will scale cleanly as new feed formats appear.

**`SSBEnvironment` as a test seam is well-conceived.** Wrapping time, randomness, filesystem, and dispatch into a replaceable protocol is the right approach for deterministic testing. The `class` property `shared` is idiomatic for singleton injection.

**`SSBSecretStore` abstraction is clean.** Two implementations (Keychain, File) behind a minimal protocol, with free functions for convenience access — appropriate layering.

**Consistent `weak` delegate properties.** Every delegate across the codebase is correctly `weak`, avoiding retain cycles. No exceptions found.

**`NS_ASSUME_NONNULL_BEGIN/END` everywhere.** Nullability annotations are consistent across all headers — critical for Swift interop and static analysis.

---

## Issues & Critique

### 1. `SSBConnectionFSMDelegate` Methods Are `@required` But Called With `respondsToSelector:`

**File:** `Sources/SSBConnectionFSM.h:19-26`, `Sources/SSBConnectionFSM.m:66-80`

The protocol declares all three methods without `@optional`, meaning they are `@required`. Yet the implementation guards every call with `respondsToSelector:`. Pick one:

- If methods are truly required: **drop the `respondsToSelector:` checks.** The compiler already enforces conformance. The checks add dead code and mask conformance bugs.
- If methods should be optional: **add `@optional`.** But then you need the guards.

This inconsistency is a code smell that suggests the contract is ambiguous. A senior reviewer would flag this in any Apple PR.

### 2. Delegate Methods Use `(id)` Instead of the Concrete Type

**Files:** `SSBConnectionFSM.h:21-23`, `SSBRoomClient.h:14-32`

```objc
- (void)connectionFSMDidRequestParse:(id)fSM;           // should be SSBConnectionFSM *
- (void)roomClientDidConnect:(id)client;                 // should be SSBRoomClient *
```

Every delegate method passes `(id)` instead of the concrete class type. This is a significant anti-pattern:

- **Loses type safety.** The delegate implementor gets no compiler help — they can message any selector on `id` without warnings.
- **Breaks Xcode autocomplete and refactoring.** Jump-to-definition, rename, and callers analysis all fail on `id`.
- **Violates Apple convention.** Every Apple delegate protocol uses the concrete type: `tableView:(NSTableView *)tableView`, `connection:(NSURLConnection *)connection`, etc. This is not optional style — it's the established contract.
- **Hurts Swift bridging.** `id` imports as `Any` in Swift, requiring force-casts everywhere.

**Fix:** Replace `(id)` with the actual class type in every delegate method. Use `@class` forward declarations where needed to avoid circular imports.

### 3. `SSBRoomClientDelegate` Is Monolithic — 10 Optional Methods

**File:** `Sources/SSBRoomClient.h:11-33`

This delegate handles connection lifecycle, sync status, replication progress, tunnel establishment, diagnostics logging, and publish queue results — all in one protocol. This violates the Single Responsibility Principle and creates problems:

- **Adopters must understand the entire surface.** A UI layer that only cares about sync progress still sees tunnel and replication methods.
- **Testing complexity.** Mock delegates must stub or ignore methods from unrelated concerns.
- **Future growth risk.** As room protocol evolves, this will only grow larger.

**Recommendation:** Split into focused protocols or use protocol composition:

```objc
@protocol SSBRoomClientConnectionDelegate    // connect, ping, error
@protocol SSBRoomClientSyncDelegate          // syncStatus, localFeedSync, publishQueue
@protocol SSBRoomClientReplicationDelegate   // replicateMessages, updateEndpoints
@protocol SSBRoomClientTunnelDelegate        // establishTunnel
```

Then compose: `id<SSBRoomClientConnectionDelegate, SSBRoomClientSyncDelegate>` where needed.

### 4. `SSBRoomClient` Is a God Object

**File:** `Sources/SSBRoomClient.h` (162 lines of header), `Sources/SSBRoomClient.m` (1700+ lines estimated)

The class has **30+ private properties** and **25+ public methods** spanning:
- Connection lifecycle (`connect`, `disconnect`, `ping`, `announce`)
- Feed replication (`fetchFeedForPeer:`, `replicateFromPeer:`, `verifyFeedIntegrity:`)
- Message publishing (`publishPostWithText:`, `publishLocalMessageWithContent:`, `publishContact:`, `publishBlock:`)
- Blob management (`fetchBlob:`, `hasBlob:`)
- Room metadata (`fetchRoomMetadataWithCompletion:`, `subscribeToEndpoints`)
- Invite management (`redeemInvite:`)
- Alias management (`registerAlias:`, `revokeAlias:`)
- Identity management (`resetLocalIdentity`, `generateLocalIdentity`)
- MuxRPC dispatch (`sendRPCRequest:args:type:completion:`)
- Subset queries (`getSubset:options:completion:`)

This is far too much for one class. It makes the codebase fragile: changes to blob handling can break tunnel logic through shared mutable state. Extract into composable subsystems (e.g., `SSBRoomReplicator`, `SSBRoomPublisher`, `SSBBlobManager`) that the client coordinates.

### 5. `SSBHTTPAuth` Mixes Concerns — Server and Client Logic in One Class

**File:** `Sources/SSBHTTPAuth.h:50-140`

The class simultaneously acts as:
- An auth **server** (nonce generation, solution verification, token issuance)
- An auth **client** (challenge solving, login flows)
- A **singleton** (`+sharedAuth`) despite being initialized with per-instance server credentials

This violates separation of concerns and makes the class hard to reason about. A server instance shouldn't have client methods, and vice versa. The singleton + instance initializer duality is especially concerning — it suggests the design evolved organically without a clear ownership model.

### 6. Free Functions in `SSBSecretStore.h` Bypass the Protocol

**File:** `Sources/SSBSecretStore.h:20-37`

There are 18 free functions (`SSBLoadIdentitySecret`, `SSBSaveMetafeedSeed`, etc.) that presumably call through `SSBSharedSecretStore()` internally. This creates a shadow API that:

- **Circumvents the abstraction.** Code calling `SSBLoadIdentitySecret()` is coupled to the global store and can't be redirected for testing.
- **Splits discoverability.** Consumers must know to look for both the protocol API and the free functions.
- **Makes migration harder.** If you ever need to change the backing store, you must audit every free function call site.

These should be methods on a class or category, not free functions, or at minimum should accept an `id<SSBSecretStore>` parameter.

### 7. `SSBHTTPInviteServer` Header Exposes Internal Implementation Details

**File:** `Sources/SSBHTTPInviteServer.h:66-78`

The public header exposes:
- `httpSession` (read-only `NSURLSession`)
- `handleGetJoinWithInviteCode:acceptJSON:submissionURL:`
- `handlePostClaimWithBody:`
- `renderHTMLForValidInvite:submissionURL:`
- `renderHTMLForInvalidInvite:error:`

These are HTTP request handler internals that should be in a private header or class extension, not the public API. External consumers should only see `generateInviteCode`, `claimInvite:`, `validateInviteCode:`, etc.

### 8. No `NS_DESIGNATED_INITIALIZER` on Most Classes

**File:** Multiple — `SSBRoomClient.h`, `SSBHTTPAuth.h`, `SSBHTTPInviteServer.h`, `SSBConnectionFSM.h`

Only `SSBTransportEndpoint` properly marks `NS_DESIGNATED_INITIALIZER` and disables `init` with `NS_UNAVAILABLE`. Other classes with complex initializers (SSBRoomClient, SSBHTTPAuth, SSBHTTPInviteServer) don't follow this pattern, which means:

- Subclasses can accidentally call `[super init]` instead of the proper initializer
- `[[SSBRoomClient alloc] init]` compiles without warning but creates an unusable instance

### 9. Block-Based Callbacks Mixed With Delegate Pattern

**File:** `Sources/SSBRoomClient.h:69-93`

SSBRoomClient uses **both** delegates (for ongoing events) **and** completion blocks (for one-shot operations). This is actually fine and follows Apple convention (NSURLSession does this). However, the issue is that there's no clear documentation or convention about which pattern is used when, and some methods like `publishLocalMessageWithContent:` have **both** a synchronous error-returning variant and an async completion block variant with no guidance on which to prefer.

### 10. `SSBPlatformUIProtocol` Is Too Narrow

**File:** `Sources/SSBPlatformUI.h:6-10`

The protocol has a single method `runModalAlert:` that returns `NSModalResponse`. This is extremely narrow — it will need to grow for every new UI interaction the framework needs. Consider whether this should be a more general "present and await" pattern, or whether the framework should use blocks/callbacks instead of blocking modal returns (which tie up the main thread).

### 11. `SRScannerDelegate` Has No Error Callback

**File:** `App/Logic/SRQRUtils.h:16-18`

The protocol only reports success (`scannerDidScanString:`). There's no method for:
- Camera authorization failure
- Scanner hardware unavailability
- Session runtime errors

The delegate adopter has no way to know if scanning failed silently. Apple's own capture delegate protocols include error callbacks.

### 12. Inconsistent Nullability on Delegate Properties

Some delegates are `nullable`:
```objc
@property (nonatomic, weak, nullable) id<SSBHTTPAuthDelegate> delegate;        // SSBHTTPAuth.h:52
@property (nonatomic, weak, nullable) id<SRThreadViewControllerDelegate> delegate;  // SRThreadViewController.h:19
```

Others are implicitly non-null (inside `NS_ASSUME_NONNULL` blocks) but semantically optional:
```objc
@property (nonatomic, weak) id<SSBRoomClientDelegate> delegate;    // SSBRoomClient.h:38
@property (nonatomic, weak) id<SRScannerDelegate> delegate;        // SRQRUtils.h:21
```

Delegates should always be `nullable` — a delegate is by definition optional. Declaring them as non-null inside `NS_ASSUME_NONNULL` creates a contract mismatch: the property starts as `nil` but the header says it shouldn't be.

---

## Maintainability & Extensibility Assessment

### Strengths
- **Protocol-first design** makes the transport and codec layers genuinely extensible
- **Self-registering codecs** via `+load` means adding a new feed format requires zero boilerplate in the registry
- **Environment injection** enables deterministic testing

### Risks
- **SSBRoomClient monolith** is the biggest extensibility bottleneck — every new room feature adds more methods and state to one class
- **`id` typing in delegates** will compound maintenance burden as the codebase grows — every refactor requires manual tracing instead of compiler-assisted navigation
- **Mixed server/client logic** in SSBHTTPAuth will make it hard to deploy the auth layer independently (e.g., using the client auth without the server side)
- **Free function proliferation** in SSBSecretStore will resist refactoring — call sites are invisible to protocol-level tooling

---

## Recommended Fix Priority

| Priority | Issue | Effort | Risk |
|----------|-------|--------|------|
| 1 | Fix `(id)` → concrete types in delegate methods | Low | None |
| 2 | Add `nullable` to all delegate properties | Trivial | None |
| 3 | Mark `NS_DESIGNATED_INITIALIZER` / `NS_UNAVAILABLE` | Low | None |
| 4 | Resolve `@required` vs `respondsToSelector:` in FSM delegate | Trivial | None |
| 5 | Add error callback to `SRScannerDelegate` | Low | Low |
| 6 | Split `SSBRoomClientDelegate` into focused protocols | Medium | Low |
| 7 | Move `SSBHTTPInviteServer` internals to private header | Low | Low |
| 8 | Refactor `SSBSecretStore` free functions to protocol methods | Medium | Medium |
| 9 | Split `SSBHTTPAuth` into server/client classes | Medium | Medium |
| 10 | Decompose `SSBRoomClient` into subsystems | High | Medium |
