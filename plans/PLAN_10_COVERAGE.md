# Plan 10: Full 100% Coverage

Generated: 2026-03-20

---

## Executive Summary

Achieve 100% merged line and function/block coverage for the three shipped macOS targets: `SSBNetwork.framework`, `ScuttleRoomApp.app`, and `git-remote-ssb`. The coverage gate script and all three test targets already exist; the gap is test content — `SSBNetwork.framework` is at ~48%, `ScuttleRoomApp.app` has one smoke-test file, and `git-remote-ssb` coverage is unaudited.

---

## Current State (as of 2026-03-20)

### Infrastructure — Already Complete

| Item | Status | Location |
|------|--------|----------|
| `ScuttleRoomAppTests` target + scheme | ✅ exists | `project.yml` |
| `GitRemoteSSBTests` target + scheme | ✅ exists | `project.yml` |
| `SSBGitRemoteCore` static library (thin-main split) | ✅ exists | `Sources/SSBGitRemoteCore.c/h` |
| Coverage gate script | ✅ written, **untracked** | `tools/check_coverage.py` |
| Shipped-target scoping by target name | ✅ in script | filters on `SSBNetwork.framework`, `ScuttleRoomApp.app`, `git-remote-ssb` |
| Existing internal seams | ✅ multiple | `SSBTransportConnection/Listener/Backend`, `SSBFeedCodec`, `SSBSecretStore`, `SSBEnvironmentProtocol`, `SSBPlatformUIProtocol`, `SSBRoomClientDelegate` |

### Gaps

| Area | Gap |
|------|-----|
| `SSBNetwork.framework` | ~48.35% line coverage |
| `ScuttleRoomAppTests` | 1 file (`ScuttleRoomAppHostSmokeTests.m`); 44 app source files uncovered |
| `GitRemoteSSBTests` | 12 tests; branch coverage unaudited |
| `check_coverage.py` | Untracked — not yet committed |
| `SRContentContainerViewControllerTests.m` | In `Tests/` (SSBNetworkTests bundle), not `Tests/ScuttleRoomApp/` |
| Seams missing | Clock, RNG, scheduler/timers, URL/session transport, filesystem roots, subprocess launch, AppKit presenters |

### Active/Pending Graph Nodes

- Node 220 (active goal): Protocol audit and integration hardening
- Node 224 (active action): Stabilize baseline protocol suites and introduce room/transport test seams
- Node 240 (completed action): Design 100% Coverage Architecture
- Node 229/230 (pending): Merged coverage gate architecture wired but blocked by legacy suite failures

---

## Phase 0: Commit Infrastructure

**Prerequisite — no code changes, pure housekeeping.**

- [ ] Commit `tools/check_coverage.py`
- [ ] Move `Tests/SRContentContainerViewControllerTests.m` into `Tests/ScuttleRoomApp/` so it runs under `ScuttleRoomAppTests`, not `SSBNetworkTests`
- [ ] Verify all three schemes build and test green with `xcodegen -s project.yml && tools/check_coverage.py` (expect failures only from coverage gap, not from missing infrastructure)

---

## Phase 1: Stabilize Failing Baselines

Fix test suites that are currently broken so the merged gate can produce a clean run.

### 1.1 Framework Suites

- [ ] **SSBFeedStoreTests** — identify and fix shared-state coupling (temp directory / DB isolation)
- [ ] **SSBMessageCodecExtendedTests** — identify root failure; likely missing fixtures or codec registration
- [ ] **SSBMetafeedTests** — fix after seed-encryption work if still failing
- [ ] **SSBURITests** — fix parsing edge cases that regressed
- [ ] **SSBNetworkShimLinuxTests** — conditionally skip or guard on Darwin to keep suite green on CI

### 1.2 Isolation Standards

Apply consistently across all test files:

- Unique `NSTemporaryDirectory()` per test (use `NSUUID`)
- Teardown removes temp directories and temp databases
- No global/shared `SSBLog`, `SSBBlobStore`, `SSBFeedStore`, or `SSBSecretStore` singletons across tests
- Keychain tests: skip gracefully when sandbox blocks writes (already done in `SSBSecretStoreTests`; replicate pattern)

---

## Phase 2: Missing Internal Seams

Add seams needed to drive uncovered branches without sleeps or real I/O. All seams are internal-only; no public API changes.

| Seam | Where needed | Pattern |
|------|-------------|---------|
| Clock / wall time | `SSBRoomClient` reconnect, `SSBHTTPAuth` timeout | Protocol property injected at init |
| RNG | `SSBRandom`, invite/session ID generation | Protocol with `secureRandomBytes:` |
| Dispatch queue / timer | Retry schedulers in `SSBRoomClient`, `SSBTunnelConnection` | Protocol wrapping `dispatch_after` |
| URL session transport | `SSBHTTPAuth`, `SSBHTTPInviteServer`, HTTPS invite resolution | Already has `SSBURLSessionShim`; verify fully injectable |
| Filesystem roots | `SSBLog`, `SSBBlobStore`, blob path resolution | Constructor parameter, no singleton path |
| Subprocess launch | `SRGitRemoteHelperServer` | Protocol wrapping `NSTask` launch |
| AppKit presenter | Alert, status-item, window activation | Expand `SSBPlatformUIProtocol` / inject in controllers |

---

## Phase 3: Framework Coverage by Subsystem

Target: **SSBNetwork.framework** from 48.35% → 100%.

Work subsystem by subsystem so each merge is meaningful.

### 3.1 Storage / Index / Query

Files: `SSBLog.m`, `SSBBlobStore.m`, `SSBPrefixIndex.m`, `SSBJITDB.m`, `SSBQueryEngine.m`, `SSBFeedStore.m`, `SSBFeedStoreQuery.m`

- Log persistence: append, read, close/reopen, corruption detection
- Blob fetch states: missing, pending, fetching, fetched, error
- Prefix-index: encode/decode/filter, range queries, edge-of-range
- JITDB: index lifecycle, eviction, cache hit/miss
- Query evaluation: `AND`, `OR`, `NOT`, offset/limit, `ORDER BY`
- Feed-store quarantine: hold, dependency release, subset queries, tombstones
- Lipmaa skip-chain: direct lookup and skip hop

### 3.2 Identity / Auth / Invite

Files: `SSBRandom.m`, `SSBKeychain.m`, `SSBKeychain_macOS.m`, `SSBSecretStore.m`, `SSBHTTPAuth.m`, `SSBHTTPInviteServer.m`, `RoomInviteHandler.m`, `RoomStorage.m`, `SSBURI.m`

- Random generation: delegate to RNG seam; test both success and seeded values
- Keychain helpers: set/get/delete with fake keychain seam; test error paths
- HTTP auth token: create, sign, verify, expiry
- HTTP auth solution: correct and tampered cases
- Invite create/validate/claim/revoke/list: round-trip, expiry, already-claimed
- HTTPS invite resolution: redirect, alias, malformed, 404
- URI parse: all SSB URI types, malformed inputs, query-string edge cases

### 3.3 Feed / Tangle / Message

Files: `SSBMessage.m`, `SSBMessageCodec.m`, `SSBBendyButt.m`, `SSBBamboo.m`, `SSBButtwoo.m`, `SSBGabbyGrove.m`, `SSBMetafeed.m`, `SSBIndexFeed.m`, `SSBIndexFeedGenerator.m`, `SSBBFE.m`, `SSBBIPF.m`, `SSBTangle.m`, `SSBThread.m`, `SSBDiffEngine.m`

- Tangle: parse, validate, topological sort, fork detection, tip finding
- Thread linearization and filtering
- BFE encode/decode: all type variants, round-trip, invalid format rejection
- Bamboo: entry ID, lipmaa, proof serialization
- Bendy Butt: payload validation, encrypted inner payload, wrong-key rejection
- GabbyGrove: forward-compat wire types 1 and 5
- Metafeed: subfeed add/tombstone, seed encrypt/decrypt round-trip
- IndexFeed: generate, append, validate
- DiffEngine: unified diff, hunk merge, conflict detection

### 3.4 Protocol — Room / Tunnel / Transport

Files: `SSBRoomClient.m`, `SSBTunnelConnection.m`, `SSBTransport.m`, `SSBSecurityFramer.m`, `SSBMuxRPC.m`, `SSBMuxRPCFramer.m`, `SSBMuxRPCSession.m`, `SSBBoxStream.m`, `SSBSecretHandshake.m`, `SSBConnectionFSM.m`, `SSBNetworkShim.m`

Use the existing in-process loopback harnesses (`SSBTransportTests`, `SSBRoomProtocolBugfixTests`). Extend until every public method and error callback is exercised:

- Room client: publish queue flush, blob fetch, profile fetch, server-initiated handlers, reconnect scheduling, integrity verification, tunnel-ready reporting
- Tunnel connection: pending-message drain, incoming-buffer edge cases, framer integrity failure
- MuxRPC: request-ID collision routing (regression from node 186), EndErr 0-byte drop fix (node 218)
- Security framer: nonce exhaustion, bad MAC, wrong app-key rejection
- Box stream: encrypt/decrypt round-trip, partial read, stream close
- Secret handshake: server and client sides, wrong network key, wrong server key
- Connection FSM: every state transition, including error and cancel edges
- Network shim: per-connection framer pipeline, state_failed handling

### 3.5 Git Cluster

Files: `SSBGitRepo.m`, `SSBGitObjectStore.m`, `SSBGitPackDecoder.m`, `SSBGitPackIDXParser.m`, `SSBGitIssueStore.m`, `SSBGitPRStore.m`

- Repo/object store: add, fetch, pack, conflict, tombstone, reconstruct
- Pack decoder: delta resolution, thin pack, corrupt pack
- IDX parser: v1 and v2 index, large offset table
- Issue/PR store: create, update, close, list, conflict merge

---

## Phase 4: ScuttleRoomApp Coverage

Target: **ScuttleRoomApp.app** from ~0% → 100%.

Use `ScuttleRoomAppTests` as a host-app unit bundle (already wired). Add fakes and seams as needed; no UI automation.

### 4.1 Bootstrap / Services

Files: `AppDelegate.m`, `SRApplication.m`, `main.m`, `SRRoomManager.m`, `SRDeviceManager.m`, `SRGitRemoteHelperServer.m`, `SRPlatformNotifications.m`, `SRPlatformUI.m`, `SRNotificationNames.m`, `RoomStorage.m` (app side), `SRQRUtils.m`

- `AppDelegate`: `applicationDidFinishLaunching`, `applicationShouldTerminate`, `applicationOpenURLs`, window-restore handlers
- `SRRoomManager`: room join/connect/disconnect, peer sync propagation, status-item update
- `SRDeviceManager`: device pairing lifecycle, QR generation/scan
- `SRGitRemoteHelperServer`: start/stop, socket ready callback, subprocess failure
- Platform notifications: post, observe, deregister with fake `NSNotificationCenter`
- Platform UI: alert, confirmation, status-item with injected `SSBPlatformUIProtocol` fake

### 4.2 Controller Families

Use a shared AppKit harness (`NSViewController` host, fake navigation delegate, fake room manager) across all controller tests.

**Shell / Navigation**
- `SRMainSplitViewController`, `SRSidebarViewController`, `SRContentContainerViewController`, `SRHomeViewController`
- Happy path: view load, item select, push/pop, safe-area inset
- Failure path: empty state, error-banner presentation

**Social / Feed**
- `SRFeedViewController`, `SRFeedItem`, `SRChannelBrowserViewController`, `SRComposeViewController`, `SRThreadViewController`, `SRProfileViewController`, `SRProfileHeaderView`
- Feed load, item render, compose submit, thread expand, profile load, empty/error states

**Identity / Settings**
- `SRPreferencesViewController`, `SRPreferencesWindowController`, `SRSeedBackupViewController`, `SRSeedRecoveryViewController`, `SRDevicePairingViewController`, `SRDevPanelViewController`
- Preferences save, seed display/hide, recovery enter/verify, reset flow, dev-panel identity display

**Git UI**
- `SRGitRepoListViewController`, `SRGitRepoViewController`, `SRGitActivityViewController`
- `SRGitCommitLogViewController`, `SRGitDiffViewController`, `SRGitFileTreeViewController`, `SRGitFileViewController`
- `SRGitIssueListViewController`, `SRGitIssueDetailViewController`, `SRGitNewIssueViewController`
- `SRGitPRListViewController`, `SRGitPRDetailViewController`, `SRGitNewPRViewController`
- `SRMarkdownParser`, `SRErrorBannerView`, `SRPeerListViewController`
- Repo list load, commit history, diff rendering, file tree, issue/PR CRUD, error banners

### 4.3 Seam Requirements for App Tests

- `SRRoomManager` fake: controllable room state, attendants list, peer sync signals
- `SRDeviceManager` fake: device list, pairing callbacks
- `SSBSecretStore` fake: deterministic identity, no keychain access
- `NSTask` fake (subprocess launch seam): for `SRGitRemoteHelperServer`
- `SSBPlatformUIProtocol` fake: capture alert/confirmation calls without UI
- `NSNotificationCenter` test instance: isolated per test

---

## Phase 5: git-remote-ssb Coverage

Target: **git-remote-ssb** → 100%.

Infrastructure is done: `SSBGitRemoteCore` static lib, `GitRemoteSSBTests` target, 12 existing tests.

### 5.1 Extend Unit Tests in `GitRemoteSSBTests`

- Socket-path resolution: all environment-variable combinations, missing vars, override via `--socket` flag
- Command parsing: `list`, `fetch`, `push`, unknown command, empty input, extra whitespace
- LIST request formatting: with and without `for-push` capability
- FETCH request: multi-ref, degenerate (zero refs), SHA validation
- PUSH request: fast-forward, forced push flag, multiple refs
- Malformed response handling: truncated line, non-hex SHA, unexpected status
- Partial read/write loops: simulate short reads with fake fd pipe, short write retry
- Pack/index streaming: fake socket server sending a valid pack, corrupt pack header
- Subprocess failure: `git` not found, non-zero exit

### 5.2 End-to-End Integration Test

- One test that runs the instrumented `git-remote-ssb` binary against a fake Unix-socket server
- Server: sends valid `list` response, valid pack for `fetch`, ACK for `push`
- Verifies thin `main` wrapper reaches 100% (it is 5 lines; just needs to run)

---

## Phase 6: Dead Code Elimination

- After adding seams, any branch still at 0% coverage is dead compiled code
- Remove it, fold it into a reachable path, or move it out of shipped targets
- Do **not** add `// NOLINT` or exclusion comments; the strict gate is the enforcement mechanism

---

## Acceptance Criteria

1. `tools/check_coverage.py` exits 0
2. All three schemes (`SSBNetwork`, `ScuttleRoomApp`, `git-remote-ssb`) green
3. Merged coverage report: 100.00% line and 100.00% function/block for all three shipped targets
4. No coverage exclusions in shipped production code
5. CI (`macos-build.yml`) runs the coverage gate, not just a build check

---

## File Checklist

### Commit First (Phase 0)

- `tools/check_coverage.py` (untracked)
- Move `Tests/SRContentContainerViewControllerTests.m` → `Tests/ScuttleRoomApp/`

### New Test Files (Phases 3–5)

Framework tests go in `Tests/` and are picked up by `SSBNetworkTests`.
App tests go in `Tests/ScuttleRoomApp/` and are picked up by `ScuttleRoomAppTests`.
Git-remote tests go in `Tests/GitRemoteSSB/`.

Suggested new files:

| File | Phase |
|------|-------|
| `Tests/SSBLogTests.m` | 3.1 |
| `Tests/SSBQueryEngineTests.m` | 3.1 |
| `Tests/SSBHTTPAuthTests.m` | 3.2 |
| `Tests/SSBHTTPInviteServerTests.m` | 3.2 |
| `Tests/SSBTangleTests.m` | 3.3 |
| `Tests/SSBThreadTests.m` | 3.3 |
| `Tests/SSBSecretHandshakeTests.m` | 3.4 |
| `Tests/SSBGitIssueStoreTests.m` | 3.5 |
| `Tests/SSBGitPRStoreTests.m` | 3.5 |
| `Tests/ScuttleRoomApp/SRAppDelegateTests.m` | 4.1 |
| `Tests/ScuttleRoomApp/SRRoomManagerTests.m` | 4.1 |
| `Tests/ScuttleRoomApp/SRDeviceManagerTests.m` | 4.1 |
| `Tests/ScuttleRoomApp/SRGitRemoteHelperServerTests.m` | 4.1 |
| `Tests/ScuttleRoomApp/SRFeedViewControllerTests.m` | 4.2 |
| `Tests/ScuttleRoomApp/SRGitUITests.m` | 4.2 |
| `Tests/ScuttleRoomApp/SRIdentityControllerTests.m` | 4.2 |
| `Tests/ScuttleRoomApp/SRNavigationTests.m` | 4.2 |

### Existing Files to Expand

- `Tests/SSBFeedStoreTests.m` — fix and expand
- `Tests/SSBMessageCodecExtendedTests.m` — fix and expand
- `Tests/SSBMetafeedTests.m` — fix and expand
- `Tests/SSBURITests.m` — fix and expand
- `Tests/SSBMuxRPCSessionTests.m` — add EndErr/collision cases (nodes 186, 218)
- `Tests/SSBRoomProtocolBugfixTests.m` — extend room client path coverage
- `Tests/SSBTransportTests.m` — extend transport/framer paths
- `Tests/GitRemoteSSB/GitRemoteSSBTests.m` — add cases for all missing branches

---

## Assumptions

- "Shipped code" = compiled into macOS `SSBNetwork`, `ScuttleRoomApp`, or `git-remote-ssb` targets; excludes `SSBKeychain_Linux.m`, demo files, `GNUmakefile` targets
- Host-based unit tests are the default; no Xcode UI automation
- Small internal refactors for testability are allowed; runtime behavior must be preserved
- Keychain access continues to skip gracefully when sandbox blocks writes
- `SRContentContainerViewController.m` is currently compiled into **both** `SSBNetworkTests` (via `App/UI/SRContentContainerViewController.m` inclusion) and `ScuttleRoomApp`; moving its test file to `Tests/ScuttleRoomApp/` keeps coverage tracking correct
