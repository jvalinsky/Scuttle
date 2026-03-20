# Scuttle

Scuttle is a macOS-first Secure Scuttlebutt codebase with a shared Objective-C framework, an AppKit app, GNUstep/Nix build support, protocol experiments, and repo-owned agent tooling.

## Start Here

- Project workflow and agent guardrails: [AGENTS.md](AGENTS.md)
- Documentation map: [docs/README.md](docs/README.md)
- Current roadmap and status: [plans/PLAN_00_MASTER.md](plans/PLAN_00_MASTER.md#executive-summary)
- Decision graph workflow: [CLAUDE.md](CLAUDE.md#decision-graph-workflow)

## Repo Map

- `App/`: macOS app code and shared UI logic
- `Sources/`: framework and protocol implementation
- `Tests/`: XCTest coverage
- `docs/`: documentation, reports, debugging guides, and sneakernet material
- `plans/`: roadmap files and topical plans
- `tools/`: developer support files and auxiliary build entrypoints
- `skills/`: repo-owned skills and references
- `third-party/`: vendored or submodule dependencies

## Build Entry Points

- `project.yml`: Xcode project specification
- `GNUmakefile`: default GNUstep CLI target
- `tools/build/GNUmakefile.gui`: GNUstep GUI target
- `flake.nix`: Nix packages, apps, and checks
- `docker-compose.yml`: local service helpers

## Key References

- Feed format report: [docs/FEED_FORMAT_REPORT.md](docs/FEED_FORMAT_REPORT.md#spec-corrections-vs-this-codebase)
- Git-over-SSB plan: [plans/topics/GIT_SSB_PLAN.md](plans/topics/GIT_SSB_PLAN.md#part-1--the-git-ssb-wire-protocol)
- Buttwoo production plan: [plans/topics/BUTTWOO_PRODUCTION_PLAN.md](plans/topics/BUTTWOO_PRODUCTION_PLAN.md)
- Debug journal: [docs/debugging/debug_journal.md](docs/debugging/debug_journal.md)
- Objective-C review notes: [docs/reports/REVIEW_OBJC_PATTERNS.md](docs/reports/REVIEW_OBJC_PATTERNS.md#critical-issues)
