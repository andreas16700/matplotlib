# Claude Code Instructions for matplotlib ezmon Data Collection

## Quick Start

**Read the full process document first:**
```
Read /tmp/matplotlib/DATA_COLLECTION_PROCESS.md
```

## What This Is

This is a **matplotlib fork** used to validate **ezmon** (our pytest-testmon fork with NetDB support). We replay upstream CI history and verify ezmon correctly selects tests.

## Current Task

Continue processing workflow runs from the tracking table in `DATA_COLLECTION_PROCESS.md`.

## Key Commands

```bash
# Check current state
git log --oneline -3
gh run list --workflow=tests.yml --limit 3

# See remaining work
git fetch upstream
git log --oneline 9b61b471d0..upstream/main --first-parent | wc -l
```

## Important Files

| File/Directory | Purpose |
|----------------|---------|
| `DATA_COLLECTION_PROCESS.md` | **Main documentation** - process, tracking table |
| `reports/` | **Detailed run reports** - organized in files of 5 runs each |
| `.github/workflows/tests.yml` | Our ezmon-enabled workflow (preserve this!) |
| `scripts/` | Automation scripts |

## Report File Structure

Reports are stored in `reports/` directory, organized by groups of 5:
- `reports/runs_001-005.md` - Runs 1-5 (includes historical Commit 1)
- `reports/runs_006-010.md` - Runs 6-10
- `reports/runs_011-015.md` - Runs 11-15
- `reports/runs_016-020.md` - Runs 16-20
- (continue pattern for future runs)

## Critical: Reset Workflow

When processing each run, you must reset to upstream state. **ALWAYS save our files first:**

```bash
# 1. SAVE before reset (including reports directory!)
cp .github/workflows/tests.yml /tmp/our-tests.yml
cp DATA_COLLECTION_PROCESS.md /tmp/DATA_COLLECTION_PROCESS.md
cp CLAUDE.md /tmp/CLAUDE.md
cp -r reports /tmp/our-reports
cp -r scripts /tmp/our-scripts 2>/dev/null || true

# 2. Reset (this wipes our files!)
git reset --hard $UPSTREAM_SHA

# 3. RESTORE after reset
cp /tmp/our-tests.yml .github/workflows/tests.yml
cp /tmp/DATA_COLLECTION_PROCESS.md DATA_COLLECTION_PROCESS.md
cp /tmp/CLAUDE.md CLAUDE.md
mkdir -p reports && cp -r /tmp/our-reports/* reports/
mkdir -p scripts && cp -r /tmp/our-scripts/* scripts/ 2>/dev/null || true

# 4. Commit and push
git add .github/workflows/tests.yml DATA_COLLECTION_PROCESS.md CLAUDE.md reports/ scripts/
git commit -m "Run N: Match upstream $UPSTREAM_SHA (PR #XXXX) - description"
git push origin main --force
```

## Required Git Diffs in Reports

For EVERY run report, include TWO git diffs:

### 1. Upstream Code Changes Diff
Shows what changed between the previous run and current run:
```bash
git diff $PREVIOUS_UPSTREAM_SHA $CURRENT_UPSTREAM_SHA -- '*.py'
```

### 2. Code Parity Verification Diff
Shows that our commit matches upstream (only infrastructure files should differ):
```bash
git diff $UPSTREAM_SHA $OUR_COMMIT --stat
git diff $UPSTREAM_SHA $OUR_COMMIT --name-only -- '*.py' '*.pyi'  # Should be empty!
```

Include both diffs in the report under:
- **Git Diff (upstream code changes: Run N-1 → Run N)**
- **Git Diff (code parity: our commit vs upstream)**

## Code Parity Verification

**CRITICAL**: Before pushing, ALWAYS verify:
```bash
# These must return 0 / empty:
git diff $UPSTREAM_SHA HEAD -- '*.py' '*.pyi' | wc -l      # Must be 0
git diff $UPSTREAM_SHA HEAD -- lib/matplotlib/ | wc -l     # Must be 0

# Only these files should differ:
git diff $UPSTREAM_SHA HEAD --name-only
# Expected: .github/workflows/tests.yml, CLAUDE.md, DATA_COLLECTION_PROCESS.md, reports/*, scripts/*
```

## Commit Efficiency

**Bundle documentation updates with run commits** to avoid redundant CI runs:
- Do NOT commit report updates separately
- Include report updates in the NEXT run's commit
- This prevents triggering extra workflow runs for doc-only changes

## Comparing Results with Upstream

**Our test matrix (5 variants):**
- macOS: Python 3.11/3.12 on macos-14, Python 3.13 on macos-15
- Linux: Python 3.12 on ubuntu-22.04 (added Run 56)
- Linux ARM: Python 3.12 on ubuntu-24.04-arm (added Run 56-retry)

**Compare matching variants** when checking upstream results:
- macOS variants: `gh api repos/matplotlib/matplotlib/actions/runs/ID/jobs --jq '.jobs[] | select(.name | test("macos")) | {name, conclusion}'`
- Linux variants: `gh api repos/matplotlib/matplotlib/actions/runs/ID/jobs --jq '.jobs[] | select(.name | test("ubuntu")) | {name, conclusion}'`

**Note**: Run 56 is the baseline for ubuntu-22.04. Run 56-retry adds ubuntu-24.04-arm baseline.

## Investigation Requirements

For EVERY run, investigate thoroughly:
1. **Check upstream job results** - compare with our matching platform variants
2. **Investigate any discrepancies** - different test counts, failures, etc.
3. **Check for NetDB race conditions** - compare changed file counts across parallel jobs
4. **Document findings** - include investigation results in reports

## Do NOT

- Modify code in `lib/matplotlib/` beyond what upstream has
- Run `git reset --hard` without saving our files first (including reports/)
- Push without preserving our workflow file, docs, AND reports
- Skip the code parity verification
- Skip including both git diffs in reports
- Forget to save/restore the `reports/` directory during reset
- Commit report updates separately (bundle with next run)
- Compare with non-matching upstream variants (use macOS jobs only)

## Session Initiation

Future sessions should be started with:
```bash
cd /tmp/matplotlib && claude
```

Then say: "Continue the matplotlib ezmon data collection process."
