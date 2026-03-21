# git-SSB for Scuttle — Implementation Plan

Research synthesised from four parallel agents covering the git-SSB protocol
(ssb-git-repo, ssb-git, git-ssb-web), pack-file internals (pull-git-pack,
pull-git-packidx-parser), Network.framework framer patterns, and macOS GUI APIs.

---

## Part 1 — The git-SSB Wire Protocol

### 1.1 Repository Identity

A repo is anchored by a single SSB feed message:

```json
{
  "type": "git-repo",
  "name": "my-repo"
}
```

The **message ID** of that message (`%abc…sha256`) becomes the permanent repository
identifier used everywhere else — in URLs, in cross-references, and in all subsequent
`git-update` messages. Optional fields: `upstream` (fork parent MsgId), `recps` (feed
IDs for private/encrypted repo).

### 1.2 Push Representation — `git-update`

Every `git push` publishes one `git-update` message on the author's SSB feed.
SSB messages are capped at **8192 bytes** of JSON — pack files would never fit inside
a message, so all binary git data is stored in the **blob store** (up to 5 MB each)
and only referenced from the message.

Two push strategies exist:

#### Path A — Object-per-blob (small pushes, `update()`)
Each git object (blob, tree, commit, tag) is uploaded as an individual SSB blob.
The message carries an `objects` array of metadata:

```json
{
  "type": "git-update",
  "repo": "%repoMsgId.sha256",
  "refs": { "refs/heads/main": "<40-hex-git-sha1>", "refs/heads/old": null },
  "head": "refs/heads/main",
  "objects": [
    { "type": "commit", "length": 234, "sha1": "<hex>", "link": "&blobId.sha256" },
    { "type": "tree",   "length":  56, "sha1": "<hex>", "link": "&blobId.sha256" },
    { "type": "blob",   "length": 1234,"sha1": "<hex>", "link": "&blobId.sha256" }
  ]
}
```

#### Path B — Pack-per-blob (larger pushes, `uploadPack()`)
The git pack protocol runs locally; the resulting `.pack` and `.idx` files are each
stored as one blob. The message carries `packs`/`indexes` arrays:

```json
{
  "type": "git-update",
  "repo": "%repoMsgId.sha256",
  "refs": { "refs/heads/main": "<40-hex>" },
  "packs":   [{ "link": "&packBlobId.sha256" }],
  "indexes": [{ "link": "&idxBlobId.sha256" }],
  "commits": [{ "sha1": "<hex>", "title": "…", "body": "…", "parents": ["<hex>"] }],
  "commits_more": 0,
  "tags": [],
  "object_ids": ["<hex>", "…"],
  "repoBranch": ["%prevUpdateMsgId.sha256"],
  "refsBranch": ["%concurrentUpdateMsgId.sha256"]
}
```

Metadata-only fields (`commits`, `tags`, `object_ids`) are for display in feed
readers — they don't contain actual git content. Empty pack/index blobs are
recognised by two sentinel blob IDs and silently dropped.

### 1.3 Ref Tracking

Refs live in the `refs` map on each `git-update`. Current state is reconstructed
by replaying history in **reverse chronological order** and taking the first (most
recent) value seen for each ref. `null` values mean deletion.

Causal ordering uses two arrays:
- `repoBranch` — MsgIds of prior `git-update` messages whose pack objects this
  push depends on (DAG edge for object availability).
- `refsBranch` — MsgIds of concurrent `git-update` messages not yet in `repoBranch`
  (DAG edge for ref merge ordering, handles simultaneous pushes).

`HEAD` (the default branch) is recorded in the `head` field as a symbolic ref string.

### 1.4 Binary Encoding

All git object data is stored as **raw binary** in SSB blobs — never base64-encoded
in the JSON message itself. The blob identifier (`&<base64-sha256>.sha256`) uses
SSB's standard blob-link format. The git SHA1 and SSB blob hash are entirely
independent: the git SHA1 is SHA1 over the git object header+content; the blob ID
is SHA256 over the raw bytes.

### 1.5 Issues and Pull Requests

These are standard SSB feed messages — no separate storage mechanism.

| UI concept       | `type` field       | Key fields |
|------------------|--------------------|------------|
| Open issue       | `issue`            | `repo`, `title`, `text`, `open: true` |
| Issue state edit | `issue-edit`       | `root` (issue MsgId), `open`, `title` |
| Open PR          | `pull-request`     | `repo`, `baseRepo`, `baseBranch`, `headRepo`, `headBranch`, `title`, `text` |
| Comment          | `post`             | `root` (issue/PR MsgId), `branch`, `text` |
| Dig / upvote     | `vote`             | `vote: { link: repoMsgId, value: 1 }` |

Comments are threaded via `root` (the anchor issue/PR message) and `branch` (the
most recent prior post in the thread, for causal ordering).

### 1.6 Permission Model

Only the feed that published the `git-repo` message can push (`sbot.id == repo.feed`
guard in the original JS). Cloning and fetching are world-readable. Private repos
encrypt the `git-repo` and all `git-update` messages using `recps` (recipient list).

### 1.7 Pack Index Format

`.idx` files use the **v2 format**:
- 8-byte magic/version header (`0xff744f63 00000002`)
- 256×4-byte fanout table (cumulative count of objects with first byte ≤ N)
- N×20-byte SHA1 entries, sorted
- N×4-byte CRC32 entries
- N×4-byte 31-bit offsets (high bit set → index into large-offset table)
- M×8-byte large-offset entries
- 20-byte pack SHA1 + 20-byte idx SHA1 trailer

Binary search using the fanout table gives O(log n) object lookup. Multiple pack
blobs are merged into one stream on fetch using `pull-git-pack-concat` (checksums
are not re-verified during concatenation).

---

## Part 2 — Network.framework and Transport

### 2.1 No New Framers Needed

The existing Scuttle framer stack already handles everything git-SSB needs at the
transport layer:

```
TCP
 └── SSBSecurityFramer    (SHS handshake → Box Stream encryption)
       └── SSBMuxRPCFramer  (9-byte header: flags | bodyLen | requestNumber)
```

git-SSB is a **consumer** of this stack, not an extension to it.

### 2.2 How the Existing Stack Works (relevant details)

**SSBSecurityFramer** (`Sources/SSBSecurityFramer.m`)
- Uses `nw_framer_set_input_handler` / `nw_framer_set_output_handler`
- SHS runs inline at framer start: 4 synchronous request/response messages at fixed
  sizes (64, 64, 112, 80 bytes). Returns `nw_framer_start_result_will_mark_ready`
  and calls `nw_framer_mark_ready` after successful SHS.
- Outbound data arriving before `mark_ready` is buffered in `outputBuffer` and
  flushed after.
- Box Stream uses the `while(true)` loop pattern: parse 34-byte header →
  extract body length → parse body → decrypt → deliver → repeat until insufficient
  bytes remain.
- A zero-body-length packet is the SSB "goodbye" signal.

**SSBMuxRPCFramer** (`Sources/SSBMuxRPCFramer.m`)
- Input: parse 9-byte header (1 + 4 + 4), deliver body with `Flags` and
  `RequestNumber` as framer message metadata.
- Output: pass-through — `SSBMuxRPCMessage.serialize` pre-pends the 9-byte header
  before data enters the framer.

**Assembly** (`Sources/SSBTunnelConnection.m` lines 150–162)
- `nw_protocol_stack_prepend_application_protocol` called twice: Security framer
  first, MuxRPC framer second (last prepend = outermost from app's view).

### 2.3 git-SSB Transport Primitives in Scuttle

The components git-SSB needs are already present:

| Need | Existing API |
|------|-------------|
| Fetch a blob by `&hash.sha256` | `SSBRoomClient.fetchBlob:completion:` |
| Store a blob locally | `SSBBlobStore` |
| Stream messages from a feed | `SSBMuxRPCSession` → `createHistoryStream` |
| Discover `git-update` messages | `SSBFeedStore` query + `SSBQueryEngine` |
| Peer-to-peer muxrpc session | `SSBTunnelConnection` + `SSBMuxRPCSession` |

A git-SSB feature adds **zero new Network.framework code**. The framer stack is
fully reusable as-is.

### 2.4 New ObjC Layers Needed

```
SSBGitRepo       — maps a repo MsgId to its git-update message chain;
                   resolves refs; dispatches blob fetches for objects/packs
SSBGitObjectStore — local cache: SSBBlobStore-backed, keyed by git SHA1;
                   wraps blob fetch + pack-index lookup
SSBGitPackDecoder — streaming pack-file decoder (PACK v2 format):
                   reads 4-byte magic, 4-byte version, 4-byte count, then
                   objects (type/size varint, zlib-compressed data)
SSBGitPackIDXParser — v2 .idx parser (fanout, SHA entries, offsets)
SSBGitIssueStore — queries feed store for issue/issue-edit/post messages
                   rooted to a repo
SSBGitPRStore    — same for pull-request messages
```

The pack decoder is the most complex piece. Git's PACK v2 format:
- 4-byte magic `PACK`
- 4-byte version (2)
- 4-byte object count
- N objects, each: type/size varint header + (for deltas: base reference) +
  zlib-compressed data. Object types: commit=1, tree=2, blob=3, tag=4,
  ofs_delta=6, ref_delta=7
- 20-byte SHA1 trailing checksum

zlib decompression: use `libz` (available in macOS SDK, no extra dependency).

---

## Part 3 — macOS GUI Plan

### 3.1 Overall Layout

The git browser is a **new top-level section** in the existing
`SRMainSplitViewController` three-column layout:

```
┌──────────────────┬────────────────────────────┬────────────────────────────┐
│  Sidebar         │  Middle column             │  Detail                    │
│  ─────────────   │  ──────────────────────    │  ──────────────────────    │
│  • Feed          │  (context-dependent)       │  (context-dependent)       │
│  • Channels      │                            │                            │
│  ▶ Git Repos     │                            │                            │
│    My repos      │                            │                            │
│    Following     │                            │                            │
│    Activity      │                            │                            │
└──────────────────┴────────────────────────────┴────────────────────────────┘
```

### 3.2 View Inventory

#### Global git views (middle column)

**G1 — Git Activity Feed**
- `NSTableView` with custom `NSTableCellView` per row
- Row types: push event, issue opened, PR opened, comment
- Each row: relative timestamp (left), type badge (coloured label), author
  avatar (32×32 pt `NSImageView`), summary text, repo name (linked)
- Infinite scroll via `createHistoryStream` with `live: true`
- macOS component: `NSTableView` with `NSTableViewDiffableDataSource` (macOS 12+)

**G2 — My Repos list** and **G3 — Following Repos list**
- `NSTableView`, one row per repo: repo name, author name, last push
  relative date, open issue count badge, dig count

#### Repository view (replaces middle+detail when a repo is selected)

The repo context uses a secondary `NSSplitViewController` embedded in the detail
column, split into a **commit/file list** pane and a **detail** pane.

A **segmented control** in the toolbar (or a tab bar) switches between the five
main sections:

**R1 — Code (file tree + file viewer)**

Middle pane: `NSOutlineView` showing the working tree of the selected branch.
- Branch/tag selector: `NSPopUpButton` above the outline view
- Rows: type icon (file/folder/submodule) + name + last-commit subject + date
- Folders are expandable via standard `NSOutlineView` disclosure triangles
- Data source: `SSBGitRepo` resolves the root tree object, lazily fetches
  sub-trees on expand

Detail pane:
- Source files: `NSTextView` with `NSLayoutManager` syntax highlighting
  (token-regex approach; reuse `SRMarkdownParser` style for `.md` files)
- README auto-rendered: `WKWebView` loaded with generated HTML
  (Markdown → HTML via `SRMarkdownParser`, injected CSS for dark/light mode)
- Breadcrumb path: `NSPathControl` above the text view

**R2 — Activity (push feed for this repo)**
- `NSTableView` listing `git-update` messages filtered to this repo
- Each row: author avatar, "pushed to refs/heads/X", N commits summary,
  relative timestamp

**R3 — Commits**
- `NSTableView` paginated list (load 25 at a time, "Load more" row at bottom)
- Each row: abbreviated SHA1 (monospace 10pt), commit title (linked), author
  name, relative date
- Clicking a row navigates to R3-Detail (commit diff view) in the detail pane

**R3-Detail — Commit diff**
- Header: full commit message, author + date, committer + date, parent links
- File-change summary: list of changed files with `+N -M` badges
- Unified diff: `NSTextView` with:
  - Fixed-pitch font (SF Mono or Menlo)
  - `NSRegularExpression`-based attributed-string colouring: `+` lines in
    green (system green, opacity 0.15 background), `-` lines in red
  - Non-contiguous layout mode for large diffs
  - Hunk headers (`@@ -a,b +c,d @@`) in gray italic

**R4 — Issues**
- Left pane: `NSTableView` with open/closed/all `NSSegmentedControl` filter
  - Each row: issue title, author, relative date, open (green) / closed (red) badge
  - "New Issue" toolbar button (disabled if not repo owner)
- Detail pane: issue thread view
  - Header: title (`NSTextField`, editable by opener), status badge, author + date
  - Thread: `NSTableView` of activity items (each a custom `NSTableCellView`):
    - `post` → avatar + name + markdown body (`WKWebView` per cell or
      attributed string for short bodies)
    - `issue-edit` → italic state-change label ("cel closed this issue")
    - `git-update` mention → commit reference chip (short hash + title)
  - Footer: `NSTextView` compose area + Submit button (hidden if not logged in)
  - Close/Reopen button in header toolbar area

**R5 — Pull Requests**
Same structure as R4 Issues, with two differences:
- PR header shows merge direction: "X wants to merge `headBranch` → `baseBranch`"
  with fork context if cross-repo
- PR detail has a three-tab `NSTabView` (or `NSSegmentedControl` + swap):
  - **Discussion** — same thread view as issues
  - **Commits** — `NSTableView` of commits between head and base
  - **Files** — changed-files list (`NSOutlineView` grouped by file) with inline
    unified diffs (same `NSTextView` renderer as R3-Detail)
- "Merge instructions" panel: `NSTextField` monospace showing the CLI commands

#### User profile view

- Header: 64×64 pt `NSImageView` (avatar), display name, feed ID (`NSTextField`
  non-editable monospace), "Follow / Unfollow" button
- `NSSegmentedControl`: Activity | Repos | Repos Dug
- Middle: `NSTableView` populated per tab

### 3.3 Navigation Model

Navigation is **selection-driven**: selecting a row in any list pushes the
appropriate view into the next column. The existing `SRMainSplitViewController`
already orchestrates this pattern.

Cross-entity navigation:
- Clicking an author name → pushes user profile view into detail column
- Clicking a repo name in activity feed → selects repo in middle repos list
- Clicking a commit SHA in an issue thread → navigates to commit diff view
- Pasting any `%MsgId`, `@FeedId`, or `ssb://` URL into a search field →
  resolves and navigates directly (mirrors git-ssb-web's search-as-navigation)
- Repo URL field (read-only `NSTextField`): `ssb://%msgId.sha256` for sharing

### 3.4 New ObjC UI Classes Needed

```
SRGitSidebarViewController       — sidebar section with My/Following/Activity items
SRGitRepoListViewController      — NSTableView of repos (G2/G3)
SRGitActivityViewController       — NSTableView feed (G1)
SRGitRepoViewController           — container: toolbar tab + embedded split view
SRGitFileTreeViewController       — NSOutlineView + branch picker (R1 left)
SRGitFileViewController           — NSTextView / WKWebView file detail (R1 right)
SRGitCommitLogViewController      — NSTableView of commits (R3 left)
SRGitDiffViewController           — commit diff NSTextView view (R3 right)
SRGitIssueListViewController      — NSTableView + filter control (R4/R5 left)
SRGitIssueDetailViewController    — thread NSTableView + compose footer (R4 right)
SRGitPRDetailViewController       — R5 right: tabs for Discussion/Commits/Files
SRGitUserViewController           — user profile view
SRGitThreadItemView               — NSTableCellView for a single thread entry
                                    (post / state-change / commit-mention)
```

### 3.5 AppKit vs SwiftUI

The codebase is **pure Objective-C / AppKit** (no Swift files). All new UI
code should follow the same pattern:

- `NSOutlineView` for file tree (no SwiftUI `OutlineGroup` equivalent of
  comparable flexibility)
- `NSTableView` for all list/log views
- `NSTextView` with custom `NSLayoutManager` for diff highlighting
- `WKWebView` for rendered Markdown
- `NSSplitViewController` (already used by `SRMainSplitViewController`) for layout

---

## Part 4 — Data Flow Summary

```
git push ssb://...
  │
  ▼
SSBGitRepo.uploadPack:
  ├─ stream pack bytes → SSBBlobStore.addBlob → blob ID (&…sha256)
  ├─ stream idx bytes  → SSBBlobStore.addBlob → blob ID
  └─ publish git-update message { repo, refs, packs:[{link}], indexes:[{link}], … }
       ↓ SSB gossip replicates message + blobs to peers

git fetch / clone:
  ├─ SSBGitRepo.syncHistory — replay git-update messages in reverse-chrono
  │   to rebuild current refs map
  ├─ for each pack blob in git-update.packs:
  │     SSBRoomClient.fetchBlob → SSBBlobStore → raw .pack bytes
  ├─ parse pack index (.idx) via SSBGitPackIDXParser for O(log n) SHA lookup
  ├─ decode pack objects via SSBGitPackDecoder (varint headers + zlib)
  └─ concatenate multiple packs via in-memory merge (pull-git-pack-concat logic)

UI displaying a file:
  ├─ SSBGitRepo.refsForRepo → current SHA1 for selected branch
  ├─ SSBGitObjectStore.objectForSHA1: → check local cache first
  │   → if miss: lookup pack index → fetch pack blob → decompress object
  ├─ for tree entries: recursively fetch sub-trees on expand
  └─ for blob entries: stream raw bytes → SRGitFileViewController
```

---

## Part 5 — Phased Implementation

### ✅ Phase 1 — Data layer (no UI)
1. `SSBGitRepo.h/m` — `git-repo` and `git-update` message publish/query using
   existing `SSBFeedStore` + `SSBQueryEngine`; ref reconstruction
2. `SSBGitPackIDXParser.h/m` — v2 `.idx` parser (C struct over mmap'd blob bytes)
3. `SSBGitPackDecoder.h/m` — PACK v2 streaming decoder, libz for inflate
4. `SSBGitObjectStore.h/m` — SHA1-keyed local cache wrapping `SSBBlobStore`
5. `SSBGitIssueStore.h/m` — issue/issue-edit/post query by repo
6. `SSBGitPRStore.h/m` — pull-request/post query by repo
7. Unit tests for all data-layer classes

### ✅ Phase 2 — Repo list and activity feed
8. `SRGitSidebarViewController` — sidebar item
9. `SRGitRepoListViewController` + `SRGitActivityViewController`
10. Wire into `SRMainSplitViewController`

### ✅ Phase 3 — Code browser (file tree + viewer)
11. `SRGitFileTreeViewController` (NSOutlineView, branch picker)
12. `SRGitFileViewController` (syntax highlight + Markdown render)

### ✅ Phase 4 — Commit log and diffs
13. `SRGitCommitLogViewController`
14. `SRGitDiffViewController` (attributed-string diff renderer)

### ✅ Phase 5 — Issues and Pull Requests
15. `SRGitIssueListViewController` + `SRGitIssueDetailViewController`
16. `SRGitPRDetailViewController` + `SRGitThreadItemView`
17. New issue/PR compose forms

### ✅ Phase 6 — Push support (git-receive-pack)
18. Implement write path: blob upload + `git-update` publish via `SSBGitRepo`
19. Wire into git remote helper subprocess or in-process equivalent

---

## Appendix — Key Constants

```objc
// Message types
static NSString * const kSSBGitRepoType   = @"git-repo";
static NSString * const kSSBGitUpdateType = @"git-update";
static NSString * const kSSBIssueType     = @"issue";
static NSString * const kSSBIssueEditType = @"issue-edit";
static NSString * const kSSBPRType        = @"pull-request";

// Empty-pack sentinel blob IDs (filter these on push)
static NSString * const kSSBGitEmptyPackId =
    @"&47hwmsDkBO4rXpJgiKY4dfJDoGB7oL/7wiimQsZL5wI=.sha256";
static NSString * const kSSBGitEmptyIdxId  =
    @"&JuEIZDf1XX38OXLTVlS8HCSXCD073j2AQP7ejQbgepc=.sha256";

// SSB limits
static const NSUInteger kSSBMessageMaxBytes = 8192;
static const NSUInteger kSSBBlobMaxBytes    = 5 * 1024 * 1024;

// Pack v2 magic
static const uint32_t kGitPackMagic   = 0x5041434b; // "PACK"
static const uint32_t kGitPackVersion = 2;
static const uint32_t kGitIdxMagic    = 0xff744f63; // v2 idx
static const uint32_t kGitIdxVersion  = 2;
```
