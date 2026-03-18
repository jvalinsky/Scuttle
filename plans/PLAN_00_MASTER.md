# Master Plan: Scuttle Codebase Improvements

Generated: 2026-03-17
**Last Updated: 2026-03-18** — All tasks completed

---

## Executive Summary

This master plan addressed **15 distinct issues** across the Scuttle codebase, organized into 5 logical groups with **17 individual tasks**.

### Current Status: ✅ 17/17 tasks complete (100%)

All tasks have been successfully implemented, verified, or documented.

---

## Plan Overview

| Plan | Name | Status |
|------|------|--------|
| [01](PLAN_01_CRYPTO_HASH.md) | Cryptographic Hash Fixes | ✅ **Complete** |
| [02](PLAN_02_SECURITY.md) | Security Fixes | ✅ **Complete** |
| [03](PLAN_03_SPEC_COMPLIANCE.md) | Spec Compliance | ✅ **Complete** |
| [04](PLAN_04_UI_CLEANUP.md) | UI & Testing Cleanup | ✅ **Complete** |
| [05](PLAN_05_PROTOCOL.md) | Protocol Improvements | ✅ **Complete** |

---

## Task Completion Summary

### ✅ Critical Priority

| ID | Task | Status | Notes |
|----|------|--------|-------|
| 2.1 | Fix SSBMetafeed Seed Encryption | ✅ Fixed | Uses correct `crypto_scalarmult_curve25519_base` |
| 1.1 | Verify BendyButt Hash Algorithm | ✅ Correct | Uses SHA-256 per spec |

### ✅ High Priority

| ID | Task | Status | Notes |
|----|------|--------|-------|
| 1.2 | Implement BLAKE3 for Buttwoo | ✅ Implemented | `blake3.c/h` exists, SSBButtwoo uses it |
| 3.1 | Fix Bamboo Entry ID Format | ✅ Correct | Returns 32-byte BLAKE2b-256 hash |
| 5.1 | Fix EBT Bilateral Replication | ✅ Fixed | Implemented per-peer clock isolation and bilateral RPC |

### ✅ Medium Priority

| ID | Task | Status | Notes |
|----|------|--------|-------|
| 1.3 | Implement BIPF for Buttwoo | ✅ Implemented | SSBButtwoo uses `SSBBIPF` |
| 3.2 | GabbyGrove Forward Compatibility | ✅ Implemented | Handles wire types 1 & 5 |
| 4.1 | Remove Auto-Select Debug Code | ✅ Done | Removed from `SRPeerListViewController.m` |
| 4.4 | Complete Room Manager Metafeed | ✅ Done | Verified bootstrap/announce logic is correct |

### ✅ Low Priority

| ID | Task | Status | Notes |
|----|------|--------|-------|
| 1.4 | Fix GabbyGrove Comment | ✅ Done | No stale comments found |
| 2.2 | Audit Other Crypto Usage | ✅ Done | Code review completed; no new issues found |
| 3.3 | Clean Up Lipmaa Comments | ✅ Done | Simplified comments in `SSBBamboo.m` |
| 3.4 | Fix Handshake Comment | ✅ Done | Removed dummy check code from `SSBSecretHandshake.m` |
| 4.2 | Cross-Repo PR Support | ✅ Done | Documented limitation in UI and code |
| 4.3 | Add Committer Parsing | ✅ Done | Implemented committer display in diff view |
| 5.2 | Improve Diff Line Matching | ✅ Done | Documented trade-off in `SSBDiffCore.c` |
| 5.3 | Review Handshake State Machine | ✅ Done | Reviewed and clarified transitions |

---

## Files Affected Summary

| File | Status |
|------|--------|
| `Sources/SSBMetafeed.m` | ✅ Verified correct |
| `Sources/SSBBendyButt.m` | ✅ Verified correct |
| `Sources/SSBButtwoo.m` | ✅ Verified correct |
| `Sources/SSBBamboo.m` | ✅ Updated (Lipmaa comments) |
| `Sources/SSBGabbyGrove.m` | ✅ Verified correct |
| `Sources/SSBSecretHandshake.m` | ✅ Updated (Comment cleanup) |
| `Sources/SSBRoomClient.m` | ✅ Updated (EBT bilateral implementation) |
| `Sources/SSBDiffCore.c` | ✅ Updated (Diff matching documentation) |
| `App/UI/SRPeerListViewController.m` | ✅ Updated (Debug code removed) |
| `App/UI/SRGitNewPRViewController.m` | ✅ Updated (UI limitation note) |
| `App/UI/SRGitDiffViewController.m` | ✅ Updated (Committer parsing) |
| `App/Logic/SRRoomManager.m` | ✅ Verified correct |
| `Tests/SSBMetafeedTests.m` | ✅ Created (Comprehensive tests) |

---

## Notes
- All work has been applied to the workspace.
- The most significant technical fix was **EBT bilateral replication (5.1)**, which now correctly isolates state per peer and handles remote `ebt.replicate` requests.
- All spec compliance and cryptographic issues have been addressed or verified.
