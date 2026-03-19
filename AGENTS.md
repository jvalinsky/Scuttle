# Agent Instructions

**Minimum macOS Version: 13.0 (Ventura)** - This project requires macOS 13 or later.

## Quick Reference

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN DECIDUOUS INTEGRATION -->
## Decision Tracking with deciduous

**IMPORTANT**: This project uses **deciduous** for tracking technical decisions, goals, and architectural changes. Use it to document *why* changes are made, not just *what* was changed.

### Why deciduous?

- Visualizes the "decision tree" of the project.
- Links goals to specific actions and observations.
- Provides context for future agents on the reasoning behind the current architecture.

### Quick Start

**List current nodes:**
```bash
deciduous nodes
```

**Add a new goal or action:**
```bash
deciduous add goal "Title" -d "Description"
deciduous add action "Title" -d "Description" -f "file1.m,file2.h"
```

**Link nodes (e.g., an action to a goal):**
```bash
deciduous link <source_id> <target_id>
```

**Update status:**
```bash
deciduous status <id> active|completed|blocked
```

### Workflow for AI Agents

1. **Review the graph**: Run `deciduous nodes` to understand the current technical context.
2. **Document new goals**: When starting a new major task, add a `goal` node.
3. **Record actions**: As you implement parts of the goal, add `action` nodes and link them to the goal.
4. **Link to code**: Use the `-f` flag to associate specific files with actions.
5. **Update statuses**: Keep the graph accurate as you progress.

### Important Rules

- ✅ Document the **reasoning** (observations) that lead to a decision.
- ✅ Link related nodes to maintain a coherent graph.
- ✅ Use `deciduous` for technical architecture.
- ❌ Do NOT let the graph fall out of sync with your actual work.

<!-- END DECIDUOUS INTEGRATION -->

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
    ```bash
    git pull --rebase
    git push
    git status  # MUST show "up to date with origin"
    ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
