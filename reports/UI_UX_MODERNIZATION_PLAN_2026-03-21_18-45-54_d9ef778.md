# ScuttleRoom UI/UX Modernization Plan

> Generated: 2026-03-21 18:45:54
> Git commit: d9ef778

## Context

The ScuttleRoom macOS app has 33 programmatic Objective-C view controllers with functional but unpolished UI. Styling is hardcoded across every file (fonts, colors, spacing, radii). The app lacks modern macOS conventions: no unified toolbar style, modal preferences instead of tabbed Settings, no keyboard shortcuts, basic sidebar without sections, and flat feed cards without depth or hover states. This plan modernizes the UI/UX following Apple HIG for macOS 13+ while keeping everything in Objective-C with programmatic Auto Layout.

---

## Phase 1: Style Foundation (no existing files changed)

Create a centralized design token system so all subsequent phases draw from one source of truth.

### New: `App/UI/SRStyle.h` / `SRStyle.m`

| Category | Tokens |
|----------|--------|
| **Typography** | `headlineLargeFont` (bold 16), `headlineFont` (bold 13), `bodyFont` (13), `captionFont` (11), `caption2Font` (10), `monoSmallFont` (mono 9), `monoMediumFont` (mono 11) |
| **Spacing** | `spacingXS` (4), `spacingSM` (8), `spacingMD` (12), `spacingLG` (16), `spacingXL` (20), `spacingXXL` (32) |
| **Radii** | `cornerRadiusSmall` (4), `cornerRadiusMedium` (8), `cornerRadiusLarge` (12), `cornerRadiusRound` (16) |
| **Avatars** | `avatarSizeSmall` (28), `avatarSizeMedium` (32), `avatarSizeLarge` (48) |
| **Colors** | `cardBackgroundColor`, `cardBorderColor`, `surfaceColor`, `accentColor`, `dangerColor`, `warningColor`, `successColor` - all semantic, dark-mode-aware |
| **Shadows** | `cardShadow` (subtle), `elevatedShadow` (popovers) |
| **Convenience** | `+styleCardView:`, `+styleAvatarView:size:hash:`, `+createAvatarWithSize:hash:` |

### New: `App/UI/SRAnimations.h` / `SRAnimations.m`

- `+fadeInView:duration:` / `+fadeOutView:duration:`
- `+crossfadeFromView:toView:duration:`
- `+slideInView:fromDirection:`
- `+animateLayoutChange:inView:`

All use `NSAnimationContext` with `CAMediaTimingFunction` ease-in-out.

### New skill: `.claude/commands/ui-phase.md`

A skill to execute one UI phase at a time: takes phase number, applies `SRStyle` migration to the target files, builds, and runs visual verification. Keeps iterations focused.

### Add to `project.yml`
Add new `.h/.m` files to the `ScuttleRoomApp` target sources.

---

## Phase 2: Window, Toolbar, and Menu Bar

### `App/AppDelegate.m`
- Add `titlebarAppearsTransparent = YES`
- Set `toolbarStyle = NSWindowToolbarStyleUnified`
- Set `contentMinSize = NSMakeSize(900, 600)`
- Enable `tabbingMode = NSWindowTabbingModeAutomatic`
- Rename "Preferences..." to "Settings..." (macOS 13+ convention)
- Add menus: **File** (New Post Cmd+N, Close Cmd+W), **View** (Toggle Sidebar Cmd+Opt+S, Toggle Peers Cmd+Opt+P, Enter Full Screen), **Navigate** (Back Cmd+[, Home Cmd+1, Channels Cmd+2, Repos Cmd+3), **Window** (standard), **Help** (Keyboard Shortcuts Cmd+?)

### `App/UI/SRMainSplitViewController.m`
- Add `NSToolbarSidebarTrackingSeparatorItemIdentifier` to track sidebar divider
- Add `NSToolbarToggleSidebarItemIdentifier` as first toolbar item
- Set `isBordered = YES` on all custom toolbar items (modern bordered style)
- Add "Toggle Peers" toolbar item with `sidebar.right` SF Symbol
- Group compose + refresh as leading items, search centered, settings + feed toggle trailing

---

## Phase 3: Sidebar Modernization

### `App/UI/SRSidebarViewController.m`
Replace `NSTableView` with `NSOutlineView` for proper collapsible sections:

| Section | Icon | Contents |
|---------|------|----------|
| **Rooms** | `network` | Each room with connection dot (green/gray), name |
| **Channels** | `number` | Subscribed channels with `#` prefix |
| **Repositories** | `chevron.left.forwardslash.chevron.right` | Git repos |

- Source list style, medium row size
- Collapsible section headers
- Green/gray SF Symbol dot for room connection status
- Keep profile header at top, sync status + join/scan at bottom

### New: `App/UI/SRSidebarItem.h` / `SRSidebarItem.m`
Model object with `type` (header/room/channel/repo), `title`, `representedObject`, `children`, `expandable`.

---

## Phase 4: Feed Cards

### `App/UI/SRFeedItem.m`
- Replace hardcoded styling with `[SRStyle styleCardView:self.view]`
- Replace flat border with subtle `[SRStyle cardShadow]`
- Use `NSVisualEffectView` (`NSVisualEffectMaterialContentBackground`) as card background
- Add hover effect via `NSTrackingArea` (subtle brightness change on mouseEntered/Exited)
- Action buttons: `NSBezelStyleAccessoryBarAction` with SF Symbols, show label on hover
- Add reply count badge and like count next to action buttons
- Content warning: disclosure triangle style instead of flat button
- Timestamps: `NSRelativeDateTimeFormatter` ("2m ago" style)

### `App/UI/SRFeedViewController.m`
- Update `sizeForItemAtIndexPath:` to use `SRStyle` spacing tokens
- Add "New posts available" banner at top when new messages arrive during scroll
- Subtle fade-in for new diffable data source items

---

## Phase 5: Compose View

### `App/UI/SRComposeViewController.m`
- Resizable height: min 80pt, max 300pt (replace fixed 120pt)
- Add formatting toolbar strip (`NSStackView`): Bold, Italic, Link, Mention (@), Channel (#) -- small icon buttons
- CW field: orange left-border accent (3pt bar) for visual distinction
- Prominent publish button with `keyEquivalent = "\r"`
- Character count label (right-aligned, bottom)
- "Replying to @author" banner with dismiss X when `replyToKey` is set

---

## Phase 6: Settings Overhaul

Replace monolithic preferences with tabbed Settings window.

### New: `App/UI/SRSettingsWindowController.h/.m`
- `NSTabViewController` with `NSTabViewControllerTabStyleToolbar` (macOS System Settings style)
- Replaces `SRPreferencesWindowController` singleton pattern

### New tab view controllers:

| Tab | File | Contents |
|-----|------|----------|
| **General** | `SRSettingsGeneralViewController.h/.m` | Display name, room management, notifications |
| **Identity** | `SRSettingsIdentityViewController.h/.m` | Profile header, backup seed, recover, rotate key, manage devices |
| **Storage** | `SRSettingsStorageViewController.h/.m` | Storage usage viz (migrate `SRStorageUsageView`), wipe database, cache |
| **Advanced** | `SRSettingsAdvancedViewController.h/.m` | Developer panel, debug logging, reset identity (red, bottom) |

### `App/AppDelegate.m`
- Wire "Settings..." menu item to new `SRSettingsWindowController`

---

## Phase 7: Profile View

### `App/UI/SRProfileHeaderView.m`
- Avatar size: `avatarSizeLarge` (48pt) in profile context
- Add avatar image loading from About message blob refs
- Add bio/description label under name
- `SRProfileHeaderStyle` enum: compact (sidebar), standard (home), expanded (profile)

### `App/UI/SRProfileViewController.m`
- Modernize back button: `NSBezelStyleAccessoryBar` (replace deprecated `TexturedRounded`)
- Follow: filled blue when not following, outlined when following
- Block: red tint, confirmation sheet before action
- Add stats row: "N posts | N following | N followers"

---

## Phase 8: Navigation Transitions

### `App/UI/SRContentContainerViewController.m`
- Push: crossfade with `NSAnimationContext` (0.25s, ease-in-out)
- Pop: reverse crossfade
- Add breadcrumb bar at top when stack depth > 1: "Home > Profile > Thread" with clickable segments

---

## Phase 9: Peer List

### `App/UI/SRPeerListViewController.m`
- Row height: 52pt (up from 44pt)
- Display name prominent, peer ID in caption font below
- Follow status: SF Symbol badges (`person.fill.checkmark` / `person.fill.xmark`)
- Mini progress ring (CAShapeLayer) instead of bar indicator
- Filter/search field at top

---

## Phase 10: Thread View

### `App/UI/SRThreadViewController.m`
- Migrate to `NSCollectionViewDiffableDataSource`
- Root message: full-width card
- Replies: 40pt left indent + thin vertical connecting line (2pt, secondaryLabelColor)
- Inline reply compose at bottom of thread
- Modernized back button

---

## Phase 11: Keyboard Shortcuts & Accessibility

### New: `App/UI/SRKeyboardShortcuts.h/.m`
Centralized shortcut registry with discoverable overlay (Cmd+?).

| Shortcut | Action |
|----------|--------|
| Cmd+N | Focus compose |
| Cmd+R | Refresh feed |
| Cmd+1/2/3 | Navigate Home/Channels/Repos |
| Cmd+[ | Back |
| Cmd+Opt+S | Toggle sidebar |
| Cmd+Opt+P | Toggle peer list |
| Cmd+K | Quick switcher overlay |
| J/K | Next/prev post |
| L | Like focused post |
| R | Reply to focused post |

### Accessibility pass (all files)
- `setAccessibilityLabel:` on avatars, status dots, action buttons
- `setAccessibilityRole:` on card views (`NSAccessibilityGroupRole`)
- Proper `accessibilityChildren` ordering in feed items
- VoiceOver descriptions for storage visualization

---

## Phase 12: Notification Banners

### `App/UI/SRErrorBannerView.m` (refactor in place)
- Add banner types: error (red), warning (orange), success (green), info (blue)
- `NSVisualEffectView` with tinted material for softer look
- Auto-dismiss: 5s for non-errors, persistent for errors
- Slide-down/up animation
- Queue multiple banners

---

## New Skill: `.claude/commands/ui-phase.md`

A skill to execute individual UI phases:
- Takes a phase number argument
- Applies the changes for that phase using `SRStyle` tokens
- Runs `/build-test` to verify compilation
- Lists modified files for visual review

This keeps each phase as a discrete, testable unit of work.

---

## Execution Order

Structure first, then visual polish, then cross-cutting.

| Order | Phase | Focus |
|-------|-------|-------|
| 1st | Phase 1 | Style Foundation (prerequisite for all) |
| 2nd | Phase 2 | Window, Toolbar, Menu Bar |
| 3rd | Phase 3 | Sidebar (NSOutlineView rewrite) |
| 4th | Phase 6 | Settings (tabbed NSTabViewController) |
| 5th | Phase 4 | Feed Cards |
| 6th | Phase 5 | Compose View |
| 7th | Phase 7 | Profile View |
| 8th | Phase 8 | Navigation Transitions |
| 9th | Phase 9 | Peer List |
| 10th | Phase 10 | Thread View |
| 11th | Phase 12 | Notification Banners |
| 12th | Phase 11 | Keyboard Shortcuts & Accessibility |

Each phase = one commit.

---

## Test Updates Per Phase

Existing test files use private access categories, mock objects, notification expectations, and explicit lifecycle calls (`loadView`/`viewDidLoad`). All test updates follow these established patterns.

### Phase 1: Style Foundation
**New:** `Tests/ScuttleRoomApp/SRStyleTests.m`
- Verify all font tokens return non-nil fonts with expected sizes
- Verify all spacing/radius tokens return expected CGFloat values
- Verify all color tokens return non-nil NSColor
- Verify `+styleCardView:` applies layer properties (cornerRadius, shadow)
- Verify `+styleAvatarView:size:hash:` applies correct corner radius and background color
- Verify colors respond to appearance changes (create NSAppearance contexts for light/dark)

**New:** `Tests/ScuttleRoomApp/SRAnimationsTests.m`
- Verify animation methods don't crash on nil views
- Verify fade in/out sets correct alpha values after completion
- Verify crossfade properly manages view hierarchy

### Phase 2: Window, Toolbar, Menu Bar
**Update:** `Tests/ScuttleRoomApp/SRRoomManagerTests.m`
- Tests reference `SRMainSplitViewController` toolbar -- update toolbar item identifier assertions to match new identifiers (`NSToolbarSidebarTrackingSeparatorItemIdentifier`, `NSToolbarToggleSidebarItemIdentifier`, bordered items)
- Add tests for new menu items: verify File, View, Navigate, Window, Help menus exist with expected items

**Update:** `Tests/ScuttleRoomAppUITests/ScuttleRoomAppUITests.m`
- `testAppLaunchDisplaysRoomsList`: update "Add Room" button query if toolbar layout changed
- Add `testMenuBarItems`: verify new menu structure (File > New Post, View > Toggle Sidebar, etc.)
- Add `testKeyboardShortcutsOpenSettings`: Cmd+, opens settings window

### Phase 3: Sidebar (NSOutlineView rewrite)
**Update:** `Tests/ScuttleRoomApp/SRRoomManagerTests.m`
- Tests that validate sidebar behavior (room selection notifications, sidebar cell contents) must switch from NSTableView assertions to NSOutlineView assertions
- Update any `numberOfRows` checks to use `outlineView:numberOfChildrenOfItem:` pattern
- Add test for section expand/collapse state

**New:** `Tests/ScuttleRoomApp/SRSidebarItemTests.m`
- Test `SRSidebarItem` model: type enum, children array, expandable flag
- Test section building: rooms section populates from RoomConfig array
- Test channel section populates from feed store channels

### Phase 4: Feed Cards
**Update:** `Tests/ScuttleRoomApp/SRFeedItemTests.m`
- Existing tests cover blob ID extraction and mention parsing -- these stay unchanged
- Add tests for `NSRelativeDateTimeFormatter` timestamp rendering
- Add test: verify `SRStyle` is applied (card view has expected cornerRadius, shadow)
- Add test: hover tracking area is installed after `loadView`
- Add test: reply count and like count labels are present and hidden by default

**Update:** `Tests/ScuttleRoomApp/SRRoomManagerTests.m`
- Feed-related delegate tests: update any hardcoded layout size expectations to use `SRStyle` token values

### Phase 5: Compose View
**Update:** `Tests/ScuttleRoomApp/SRRoomManagerTests.m`
- Compose tests: update assertions for new view hierarchy (formatting toolbar stack view, character count label, reply banner)
- Verify publish button `keyEquivalent` is `"\r"`
- Verify CW field has orange accent subview

### Phase 6: Settings Overhaul
**New:** `Tests/ScuttleRoomApp/SRSettingsWindowControllerTests.m`
- Verify tab count = 4 (General, Identity, Storage, Advanced)
- Verify tab style = `NSTabViewControllerTabStyleToolbar`
- Verify each tab instantiates the correct view controller class
- Verify singleton behavior matches old `SRPreferencesWindowController` pattern

**New:** `Tests/ScuttleRoomApp/SRSettingsTabTests.m`
- For each tab VC: verify `loadView` succeeds, expected subviews exist
- `SRSettingsGeneralViewController`: display name field, room list present
- `SRSettingsIdentityViewController`: backup/recover/rotate buttons present
- `SRSettingsStorageViewController`: storage usage view present, wipe button present
- `SRSettingsAdvancedViewController`: reset identity button present, styled red

**Update:** `Tests/ScuttleRoomApp/SRRoomManagerTests.m`
- Replace any references to `SRPreferencesWindowController` with `SRSettingsWindowController`

**Update:** `Tests/ScuttleRoomAppUITests/ScuttleRoomAppUITests.m`
- `testOpenDeveloperPanel`: update navigation path if Developer Panel moves to Advanced tab

### Phase 7: Profile View
**Update:** `Tests/ScuttleRoomApp/SRRoomManagerTests.m`
- Profile delegate tests: update assertions for new button styles (follow filled/outlined, block red)
- Add test for stats row labels ("N posts | N following | N followers")
- Verify `SRProfileHeaderStyle` enum produces correct avatar sizes

### Phase 8: Navigation Transitions
**Update:** `Tests/ScuttleRoomApp/SRContentContainerViewControllerTests.m`
- Existing push/pop tests verify child VC management -- keep, but add runloop pump for animation completion
- Add test: breadcrumb bar appears when stack depth > 1
- Add test: breadcrumb bar hidden when stack depth = 1
- Add test: breadcrumb segments match pushed VC titles

### Phase 9: Peer List
**New:** `Tests/ScuttleRoomApp/SRPeerListViewControllerTests.m`
- Verify row height = 52
- Verify search/filter field exists at top
- Verify peer cell displays name prominently, ID in caption font
- Verify follow status badge uses correct SF Symbol

### Phase 10: Thread View
**New:** `Tests/ScuttleRoomApp/SRThreadViewControllerTests.m`
- Verify uses `NSCollectionViewDiffableDataSource` (not legacy data source)
- Verify reply cells have 40pt left indent
- Verify inline reply compose view exists at bottom
- Verify back button uses modern bezel style

### Phase 11: Keyboard Shortcuts & Accessibility
**New:** `Tests/ScuttleRoomApp/SRKeyboardShortcutsTests.m`
- Verify shortcut registry contains all expected shortcuts
- Verify shortcut overlay view controller loads without crash
- Verify menu items have correct key equivalents

**Update:** All existing test files
- Add accessibility assertions where UI elements are validated: `XCTAssertNotNil([view accessibilityLabel])` for avatars, action buttons, status indicators

### Phase 12: Notification Banners
**Update:** `Tests/ScuttleRoomApp/SRErrorBannerViewTests.m`
- Existing tests: show/hide visibility, message label, close button -- update for new API
- Add test for each banner type (error/warning/success/info) with correct background material
- Add test for auto-dismiss timer (verify banner hides after timeout using `XCTestExpectation`)
- Add test for banner queue (show 2 banners, verify first shows, dismiss, second shows)

---

## Verification

**Per phase:**
1. `/build-test` -- zero warnings, all tests pass (including updated tests)
2. Launch app, verify modified views in both light and dark mode
3. Test navigation flow: sidebar room select -> feed loads -> click peer -> profile pushes -> back pops -> settings opens/tabs switch

**After all phases:**
- Grep `App/UI/*.m` for remaining hardcoded font/color/spacing not using `SRStyle`
- VoiceOver walkthrough of entire app
- Full keyboard-only navigation test
- Run full test suite: unit tests + UI tests with no failures

---

## Files Summary

### New source files (12)
- `App/UI/SRStyle.h/.m`
- `App/UI/SRAnimations.h/.m`
- `App/UI/SRSidebarItem.h/.m`
- `App/UI/SRKeyboardShortcuts.h/.m`
- `App/UI/SRSettingsWindowController.h/.m`
- `App/UI/SRSettingsGeneralViewController.h/.m`
- `App/UI/SRSettingsIdentityViewController.h/.m`
- `App/UI/SRSettingsStorageViewController.h/.m`
- `App/UI/SRSettingsAdvancedViewController.h/.m`
- `.claude/commands/ui-phase.md`

### New test files (8)
- `Tests/ScuttleRoomApp/SRStyleTests.m`
- `Tests/ScuttleRoomApp/SRAnimationsTests.m`
- `Tests/ScuttleRoomApp/SRSidebarItemTests.m`
- `Tests/ScuttleRoomApp/SRSettingsWindowControllerTests.m`
- `Tests/ScuttleRoomApp/SRSettingsTabTests.m`
- `Tests/ScuttleRoomApp/SRPeerListViewControllerTests.m`
- `Tests/ScuttleRoomApp/SRThreadViewControllerTests.m`
- `Tests/ScuttleRoomApp/SRKeyboardShortcutsTests.m`

### Modified source files (15+)
- `App/AppDelegate.m` (window, menu, settings wiring)
- `App/UI/SRMainSplitViewController.m` (toolbar)
- `App/UI/SRSidebarViewController.m` (outline view rewrite)
- `App/UI/SRFeedItem.m` (card styling)
- `App/UI/SRFeedViewController.m` (layout tokens)
- `App/UI/SRComposeViewController.m` (resizable, toolbar)
- `App/UI/SRProfileViewController.m` (buttons, stats)
- `App/UI/SRProfileHeaderView.m` (style enum, avatar images)
- `App/UI/SRContentContainerViewController.m` (animations, breadcrumb)
- `App/UI/SRPeerListViewController.m` (row styling)
- `App/UI/SRThreadViewController.m` (diffable, threading lines)
- `App/UI/SRErrorBannerView.m` (banner types, animation)
- `App/UI/SRPreferencesWindowController.m` (deprecated, references removed)
- `App/UI/SRPreferencesViewController.m` (deprecated, references removed)
- `project.yml` (new source + test files)

### Modified test files (6)
- `Tests/ScuttleRoomApp/SRRoomManagerTests.m` (toolbar, sidebar, feed, compose, profile, settings changes)
- `Tests/ScuttleRoomApp/SRFeedItemTests.m` (new card styling, timestamps, hover)
- `Tests/ScuttleRoomApp/SRErrorBannerViewTests.m` (banner types, auto-dismiss, queue)
- `Tests/ScuttleRoomApp/SRContentContainerViewControllerTests.m` (animations, breadcrumb)
- `Tests/ScuttleRoomAppUITests/ScuttleRoomAppUITests.m` (menu bar, settings navigation)
- `Tests/ScuttleRoomApp/SRMarkdownParserTests.m` (no changes expected, but verify no regressions)
