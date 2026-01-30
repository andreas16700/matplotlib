# ezmon Data Collection Process for matplotlib

> **IMPORTANT**: This document describes the systematic process for collecting test selection accuracy data. Follow this process exactly when resuming work in a new session.

## Objective

Validate ezmon's test selection accuracy by:
1. Matching each upstream workflow run exactly
2. Running our test workflow with ezmon on equivalent code
3. Comparing our test results with upstream's CI results
4. Documenting any discrepancies, especially **false negatives** (tests that should have run but didn't)

---

## Environment & Setup

### Repositories

| Repository | Purpose | URL |
|------------|---------|-----|
| **matplotlib fork** | Our fork with ezmon workflow | [andreas16700/matplotlib](https://github.com/andreas16700/matplotlib) |
| **matplotlib upstream** | Official matplotlib repo | [matplotlib/matplotlib](https://github.com/matplotlib/matplotlib) |
| **pytest-testmon fork (ezmon)** | Our testmon fork with NetDB | [andreas16700/pytest-testmon](https://github.com/andreas16700/pytest-testmon) |

### Working Directories

| Path | Purpose |
|------|---------|
| `/tmp/matplotlib` | **Primary working directory** for data collection. This clone is configured with the upstream remote and our workflow. |
| `~/pytest-super/matplotlib` | Secondary copy (may have outdated docs). **Use `/tmp/matplotlib` for active work.** |
| `~/pytest-super/pytest-testmon` | The ezmon plugin source code (pytest-testmon fork) |

### Initial Setup (if `/tmp/matplotlib` doesn't exist)

```bash
# Clone our fork
cd /tmp
git clone https://github.com/andreas16700/matplotlib.git
cd matplotlib

# Add upstream remote
git remote add upstream https://github.com/matplotlib/matplotlib.git
git fetch upstream
```

### Our Workflow Configuration

The file `.github/workflows/tests.yml` in our fork:
- Installs ezmon from `git+https://github.com/andreas16700/pytest-testmon.git@main`
- Uses NetDB for fingerprint storage (no local `.testmondata` files)
- Runs with `--ezmon --ezmon-no-reorder -n auto`

**Test Matrix (5 variants):**

| OS | Python | Notes |
|----|--------|-------|
| macos-14 | 3.11 | Apple Silicon, matches upstream |
| macos-14 | 3.12 | Apple Silicon, matches upstream |
| macos-15 | 3.13 | Apple Silicon, matches upstream |
| ubuntu-22.04 | 3.12 | Linux x86_64 (baseline: Run 56) |
| ubuntu-24.04-arm | 3.12 | Linux ARM64 (baseline: Run 56-retry) |

**Note**: Linux variants were added at Run 56. Windows was attempted but failed due to DLL loading issues with editable installs (upstream doesn't test Windows either).

### Verifying Codebase Parity

Before each run, verify:
1. Our code matches upstream at the target commit (except workflow file)
2. Our workflow file uses ezmon and correct macOS matrix
3. Our documentation (this file) is preserved

```bash
# Check diff between our HEAD and upstream commit (should only show workflow + docs)
git diff HEAD upstream/<sha> --name-only
```

---

## ⚠️ PARAMOUNT: Code Parity Requirement

> **THIS IS THE MOST CRITICAL REQUIREMENT OF THE ENTIRE PROCESS**

For valid comparison, we MUST test **exactly the same code** as upstream. This means:

### Understanding Upstream Workflow Runs

For each commit merged to main, upstream typically has **TWO** workflow runs:

1. **PR Workflow** (`pull_request` event)
   - Runs on the PR branch HEAD (e.g., `fix-tightbox` branch)
   - Runs BEFORE the merge
   - Tests code that does NOT include other changes merged to main
   - **DO NOT compare to this workflow**

2. **Push Workflow** (`push` event)
   - Runs on the merge commit on `main` branch
   - Runs AFTER the merge
   - Tests the exact code state we should replicate
   - **THIS is the workflow we compare to**

### How to Find the Correct Upstream Workflow

```bash
# For a merge commit SHA, find the push workflow on main:
gh api "repos/matplotlib/matplotlib/actions/workflows/tests.yml/runs?branch=main&per_page=50" \
  | jq -r '.workflow_runs[] | select(.head_sha == "<MERGE_SHA>") | {id, head_sha, event, conclusion}'
```

### Verifying Code Parity (MANDATORY for every run)

After resetting to upstream and restoring our files, verify:

```bash
# 1. Get the commit our workflow will test
OUR_COMMIT=$(git rev-parse HEAD)

# 2. Get what upstream's push workflow tested
UPSTREAM_SHA="<merge_commit_sha>"

# 3. Diff should show ONLY our workflow and docs
git diff $UPSTREAM_SHA $OUR_COMMIT --stat

# Expected output (ONLY these files):
#  .github/workflows/tests.yml | ...
#  DATA_COLLECTION_PROCESS.md  | ...
#  CLAUDE.md                   | ...
#  3 files changed, ...

# 4. If ANY other files differ, STOP and investigate
```

### Why PR Workflows Have Different Code

When a PR is opened, it's based on main at that point in time. While the PR is open, other PRs may merge to main. The PR workflow tests the PR branch, which doesn't have those other changes. Only after merge does the code include everything.

Example:
```
main:     A -- B -- C -- D (merge of PR #123)
                    \
PR #123:             X -- Y (PR branch, based on C, doesn't have D's changes)
```

- PR workflow tests: C + X + Y (missing D)
- Push workflow tests: D (includes A, B, C, X, Y merged)

### Correct Upstream Workflow for Comparison

| Scenario | Compare To |
|----------|------------|
| Merge commit `abc123` on main | Push workflow on `abc123` with `event: push` |
| NOT the PR workflow | PR workflow tests different code state |

---

## Key Insight: Workflow Runs = First-Parent Commits

**Critical**: Upstream workflow runs are triggered by commits to main. Each first-parent commit on main represents one workflow run:

```
Merge base (9b61b471d0)
    │
    ├── Run 1: ea40d72fb0 (Merge PR #30657)
    ├── Run 2: cfccd8a13c (Merge PR #28831)
    ├── Run 3: bd2f744f0e (Merge PR #30667)
    │   ...
    └── Run N: <latest>
```

**Our strategy**: For each upstream workflow run, make our fork match the exact code state that upstream tested, then run our workflow.

### Why Cherry-Picking Individual Commits Failed

We initially tried cherry-picking individual commits from PRs one at a time. This was wrong because:
1. Upstream workflow runs test the state AFTER a merge, not intermediate states
2. Cherry-picking individual commits creates states that upstream never tested
3. This led to test failures due to version mismatches (e.g., EngFormatter `'1 _'` errors)

## Known Limitations

### GitHub Workflow Logs Expire

GitHub only retains workflow logs for ~90 days. For older commits:
- The workflow run page shows pass/fail status but "logs have expired"
- We cannot see detailed test output
- **Strategy**: Process commits promptly and capture all data while logs are fresh

---

## Critical Alert Conditions

### 🚨 STOP AND INVESTIGATE IMMEDIATELY if:

1. **Test failed on upstream but PASSED on our fork**
   - This is a MAJOR red flag indicating a potential false negative
   - ezmon may have incorrectly deselected a test that should have run
   - Document the test name, what code changed, and why ezmon missed it

2. **Test failed on upstream but was DESELECTED on our fork**
   - Same severity - ezmon should have selected this test
   - Analyze the dependency chain to understand why it was missed

3. **Plugin crashes or errors during test run**
   - Fix the plugin bug first
   - Run plugin test suite before continuing
   - Document the fix in the commit report

---

## Workflow Run Tracking Table

| # | Upstream SHA | Type | PR | Upstream macOS Status | Our Run | Report |
|---|--------------|------|-----|----------------------|---------|--------|
| 1 | `ea40d72fb0` | Merge | [#30657](https://github.com/matplotlib/matplotlib/pull/30657) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21350378747) | [Report](#run-1-ea40d72fb0) |
| 2 | `cfccd8a13c` | Merge | [#28831](https://github.com/matplotlib/matplotlib/pull/28831) | ✅ (tests) / ❌ (docs) | [❌ Failed](https://github.com/andreas16700/matplotlib/actions/runs/21350615668) | [Report](#run-2-cfccd8a13c) |
| 3 | `bd2f744f0e` | Merge | [#30667](https://github.com/matplotlib/matplotlib/pull/30667) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21352658801) | [Report](#run-3-bd2f744f0e) |
| 4 | `36a6259397` | Merge | [#30668](https://github.com/matplotlib/matplotlib/pull/30668) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21352844524) | [Report](#run-4-36a6259397) |
| 5 | `72660082c6` | Merge | [#30672](https://github.com/matplotlib/matplotlib/pull/30672) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21353000933) | [Report](#run-5-72660082c6) |
| 6 | `86a476d26a` | Merge | [#30640](https://github.com/matplotlib/matplotlib/pull/30640) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21371940872) | [Report](#run-6-86a476d26a) |
| 7 | `efc43d1abf` | Merge | [#30684](https://github.com/matplotlib/matplotlib/pull/30684) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21372256919) | [Report](#run-7-efc43d1abf) |
| 8 | `9eb0cf9aba` | Merge | [#30687](https://github.com/matplotlib/matplotlib/pull/30687) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21372452279) | [Report](#run-8-9eb0cf9aba) |
| 9 | `e0f0ded0d1` | Merge | [#30686](https://github.com/matplotlib/matplotlib/pull/30686) | ❌ infra | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21375615874) | [Report](#run-9-e0f0ded0d1) |
| 10 | `4cf7021e32` | Merge | [#30698](https://github.com/matplotlib/matplotlib/pull/30698) | ❌ infra | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21375903812) | [Report](#run-10-4cf7021e32) |
| 11 | `73ef257477` | Direct | [#30624](https://github.com/matplotlib/matplotlib/pull/30624) | ⚠️ partial | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21376261640) | [Report](#run-11-73ef257477) |
| 12 | `cd3685fc75` | Direct | [#30316](https://github.com/matplotlib/matplotlib/pull/30316) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21376466609) | [Report](#run-12-cd3685fc75) |
| 13 | `c5ffd6c8ad` | Merge | [#30696](https://github.com/matplotlib/matplotlib/pull/30696) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21420564689) | [Report](#run-13-c5ffd6c8ad) |
| 14 | `78617c1dbb` | Merge | [#30511](https://github.com/matplotlib/matplotlib/pull/30511) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21421454027) | [Report](#run-14-78617c1dbb) |
| 15 | `8e7ad1643b` | Merge | [#30708](https://github.com/matplotlib/matplotlib/pull/30708) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21422409403) | [Report](#run-15-8e7ad1643b) |
| 16 | `53a5bc6c1e` | Merge | [#29989](https://github.com/matplotlib/matplotlib/pull/29989) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21422893968) | [Report](#run-16-53a5bc6c1e) |
| 17 | `94def4ee50` | Merge | [#30697](https://github.com/matplotlib/matplotlib/pull/30697) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21423395083) | [Report](#run-17-94def4ee50) |
| 18 | `28780cb39c` | Merge | [#30565](https://github.com/matplotlib/matplotlib/pull/30565) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21424513082) | [Report](#run-18-28780cb39c) |
| 19 | `ac6730773b` | Merge | [#30560](https://github.com/matplotlib/matplotlib/pull/30560) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21425120947) | [Report](#run-19-ac6730773b) |
| 20 | `677a2ea0ee` | Merge | [#30690](https://github.com/matplotlib/matplotlib/pull/30690) | ⚪ cancelled | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21425866663) | [Report](#run-20-677a2ea0ee) |
| 21 | `419eb3e265` | Merge | [#30714](https://github.com/matplotlib/matplotlib/pull/30714) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21425973829) | [Report](#run-21-419eb3e265) |
| 22 | `db83efff4d` | Merge | [#30723](https://github.com/matplotlib/matplotlib/pull/30723) | ⚪ docs only | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21427583511) | [Report](#run-22-db83efff4d) |
| 23 | `1ab3332e4e` | Direct | [#30736](https://github.com/matplotlib/matplotlib/pull/30736) | ⚪ logs expired | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21427747323) | [Report](#run-23-1ab3332e4e) |
| 24 | `5ee6560e65` | Merge | [#30741](https://github.com/matplotlib/matplotlib/pull/30741) | ⚪ logs expired | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21427941992) | [Report](#run-24-5ee6560e65) |
| 25 | `a00d606d59` | Direct | [#30665](https://github.com/matplotlib/matplotlib/pull/30665) | ⚪ docs only | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21428115596) | [Report](#run-25-a00d606d59) |
| 26 | `e99d98b2f2` | Direct | [#30759](https://github.com/matplotlib/matplotlib/pull/30759) | ⚪ C++ only | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21428254200) | [Report](#run-26-e99d98b2f2) |
| 27 | `bdace080e8` | Merge | [#30761](https://github.com/matplotlib/matplotlib/pull/30761) | ⚪ docs only | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21428431630) | [Report](#run-27-bdace080e8) |
| 28 | `91b8a0747d` | Merge | [#30699](https://github.com/matplotlib/matplotlib/pull/30699) | ⚪ docs only | ⏭️ Skipped | [Report](#run-28-91b8a0747d) |
| 29 | `0a9f2d5be9` | Merge | [#30753](https://github.com/matplotlib/matplotlib/pull/30753) | ⚪ config only | ⏭️ Skipped | [Report](#run-29-0a9f2d5be9) |
| 30 | `dedfe9be48` | Merge | [#30774](https://github.com/matplotlib/matplotlib/pull/30774) | ⚪ docstring | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21428559537) | [Report](#run-30-dedfe9be48) |
| 31 | `b94feab659` | Merge | [#30776](https://github.com/matplotlib/matplotlib/pull/30776) | ⚪ docstring | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21437705894) | [Report](#run-31-b94feab659) |
| 32 | `9280b47cd3` | Merge | [#30783](https://github.com/matplotlib/matplotlib/pull/30783) | ⚪ docstring | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21437865746) | [Report](#run-32-9280b47cd3) |
| 33 | `50fea43863` | Merge | [#30733](https://github.com/matplotlib/matplotlib/pull/30733) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21438066872) | [Report](#run-33-50fea43863) |
| 34 | `fd2c89775d` | Merge | [#30784](https://github.com/matplotlib/matplotlib/pull/30784) | ⚪ docstring | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21448047314) | [Report](reports/runs_031-035.md) |
| 35 | `76327b5011` | Direct | [#29494](https://github.com/matplotlib/matplotlib/pull/29494) | ⚪ workflow | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21448375827) | [Report](reports/runs_031-035.md) |
| 36 | `9a2f807495` | Merge | [#30788](https://github.com/matplotlib/matplotlib/pull/30788) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21448941318) | [Report](reports/runs_036-040.md) |
| 37 | `fac0b89826` | Direct | [#30782](https://github.com/matplotlib/matplotlib/pull/30782) | ⚪ docs | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21449270425) | [Report](reports/runs_036-040.md) |
| 38 | `7a7a38882b` | Direct | [#30756](https://github.com/matplotlib/matplotlib/pull/30756) | ✅ macOS ok | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21449495760) | [Report](reports/runs_036-040.md) |
| 39 | `dcff41fa3b` | Direct | [#30766](https://github.com/matplotlib/matplotlib/pull/30766) | ✅ macOS ok | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21450642267) | [Report](reports/runs_036-040.md) |
| 40 | `6cb93cd066` | Merge | [#30799](https://github.com/matplotlib/matplotlib/pull/30799) | ✅ macOS ok | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21450950187) | [Report](reports/runs_036-040.md) |
| 41 | `7bf7e47891` | Direct | [#30780](https://github.com/matplotlib/matplotlib/pull/30780) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21451243955) | [Report](reports/runs_041-045.md) |
| 42 | `3323161b83` | Merge | [#30763](https://github.com/matplotlib/matplotlib/pull/30763) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21452371823) | [Report](reports/runs_041-045.md) |
| 43 | `7ebaad8484` | Direct | [#30760](https://github.com/matplotlib/matplotlib/pull/30760) | ⚠️ infra | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21452678947) | [Report](reports/runs_041-045.md) |
| 44 | `de6e548360` | Merge | [#30810](https://github.com/matplotlib/matplotlib/pull/30810) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21453047351) | [Report](reports/runs_041-045.md) |
| 45 | `9bc1621230` | Merge | [#30812](https://github.com/matplotlib/matplotlib/pull/30812) | ⚪ docs | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21453306137) | [Report](reports/runs_041-045.md) |
| 46 | `95487d41fe` | Merge | [#30705](https://github.com/matplotlib/matplotlib/pull/30705) | ❌ failure | [❌ Failed](https://github.com/andreas16700/matplotlib/actions/runs/21453644302) | [Report](reports/runs_046-050.md) |
| 47 | `89aa37129f` | Merge | [#30813](https://github.com/matplotlib/matplotlib/pull/30813) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21454692209) | [Report](reports/runs_046-050.md) |
| 48 | `ac2fc0e9c9` | Merge | [#30814](https://github.com/matplotlib/matplotlib/pull/30814) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21455793679) | [Report](reports/runs_046-050.md) |
| 49 | `1ee5922c1a` | Merge | [#30816](https://github.com/matplotlib/matplotlib/pull/30816) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21456011650) | [Report](reports/runs_046-050.md) |
| 50 | `6c2d9e81df` | Merge | [#30817](https://github.com/matplotlib/matplotlib/pull/30817) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21456283736) | [Report](reports/runs_046-050.md) |
| 51 | `702c669fb7` | Merge | [#30820](https://github.com/matplotlib/matplotlib/pull/30820) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21456520055) | [Report](reports/runs_051-055.md) |
| 52 | `08236aed74` | Direct | [#30052](https://github.com/matplotlib/matplotlib/pull/30052) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21456803019) | [Report](reports/runs_051-055.md) |
| 53 | `fdf8995b53` | Merge | [#30822](https://github.com/matplotlib/matplotlib/pull/30822) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21457698583) | [Report](reports/runs_051-055.md) |
| 54 | `94055bc337` | Merge | [#30750](https://github.com/matplotlib/matplotlib/pull/30750) | ⚪ cancelled | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21457982713) | [Report](reports/runs_051-055.md) |
| 55 | `caaa636635` | Merge | [#30835](https://github.com/matplotlib/matplotlib/pull/30835) | ⚪ cancelled | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21458912691) | [Report](reports/runs_051-055.md) |
| 66-base | `b70e3246b1` | Baseline | - | - | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21501730675) | [Report](reports/runs_066-070.md) |
| 67 | `3782e61b6f` | Merge | [#30869](https://github.com/matplotlib/matplotlib/pull/30869) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21503377339) | [Report](reports/runs_066-070.md) |
| 68 | `90748a5669` | Direct | [#30856](https://github.com/matplotlib/matplotlib/pull/30856) | ⚪ docs | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21503780051) | [Report](reports/runs_066-070.md) |
| 69 | `3ba3d6f0ab` | Direct | [#30847](https://github.com/matplotlib/matplotlib/pull/30847) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21504067462) | [Report](reports/runs_066-070.md) |
| 70 | `57ad96d45c` | Merge | [#30600](https://github.com/matplotlib/matplotlib/pull/30600) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21504227586) | [Report](reports/runs_066-070.md) |
| 71 | `7b64c5584d` | Merge | [#29966](https://github.com/matplotlib/matplotlib/pull/29966) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21504605067) | [Report](reports/runs_071-075.md) |
| 72 | `00881824d1` | Merge | [#30737](https://github.com/matplotlib/matplotlib/pull/30737) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21505560463) | [Report](reports/runs_071-075.md) |
| 73 | `bbf01d4216` | Direct | [#30821](https://github.com/matplotlib/matplotlib/pull/30821) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21506619301) | [Report](reports/runs_071-075.md) |
| 74 | `15697eab45` | Merge | [#30591](https://github.com/matplotlib/matplotlib/pull/30591) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21508796836) | [Report](reports/runs_071-075.md) |
| 75 | `7bbe3b7e19` | Merge | [#30867](https://github.com/matplotlib/matplotlib/pull/30867) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21509694124) | [Report](reports/runs_071-075.md) |
| 76 | `0dc49d9794` | Merge | [#30907](https://github.com/matplotlib/matplotlib/pull/30907) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21510040163) | [Report](reports/runs_076-080.md) |
| 77 | `776b24910f` | Merge | [#30914](https://github.com/matplotlib/matplotlib/pull/30914) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21510605288) | [Report](reports/runs_076-080.md) |
| 78 | `b9aaca35cb` | Merge | [#30919](https://github.com/matplotlib/matplotlib/pull/30919) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21510840723) | [Report](reports/runs_076-080.md) |
| 79 | `0bf4d39580` | Direct | [#30916](https://github.com/matplotlib/matplotlib/pull/30916) | ✅ success | [✅ Passed](https://github.com/andreas16700/matplotlib/actions/runs/21511645297) | [Report](reports/runs_076-080.md) |

### Pending Runs (80-172)

> **Note**: ~93 runs remain to be processed. Run 66 re-established baseline after plugin architecture changes.

| Run | Commit | Description |
|-----|--------|-------------|
| 80 | next | Pending |
| ... | ... | ... |

Full run list: `git log --oneline --reverse 9b61b471d0..upstream/main --first-parent`

---

### Discarded Runs 6-12 (Codebase Parity Not Verified)

**Reason for discard**: These runs were executed without proper verification of codebase parity with upstream. Moving to historical section and re-running from Run 5 with force-all-tests to establish proper baseline.

**NetDB identifiers to remove** (format: `REPO_ID/JOB_ID/RUN_ID`):
```
# Run 6: 86a476d26a (PR #30640)
andreas16700/matplotlib/macos-14-py3.11/21355641000
andreas16700/matplotlib/macos-14-py3.12/21355641000
andreas16700/matplotlib/macos-15-py3.13/21355641000

# Run 7: efc43d1abf (PR #30684)
andreas16700/matplotlib/macos-14-py3.11/21355761143
andreas16700/matplotlib/macos-14-py3.12/21355761143
andreas16700/matplotlib/macos-15-py3.13/21355761143

# Run 8: 9eb0cf9aba (PR #30687)
andreas16700/matplotlib/macos-14-py3.11/21355895956
andreas16700/matplotlib/macos-14-py3.12/21355895956
andreas16700/matplotlib/macos-15-py3.13/21355895956

# Run 9: e0f0ded0d1 (PR #30686)
andreas16700/matplotlib/macos-14-py3.11/21355999546
andreas16700/matplotlib/macos-14-py3.12/21355999546
andreas16700/matplotlib/macos-15-py3.13/21355999546

# Run 10: 4cf7021e32 (PR #30698)
andreas16700/matplotlib/macos-14-py3.11/21356094774
andreas16700/matplotlib/macos-14-py3.12/21356094774
andreas16700/matplotlib/macos-15-py3.13/21356094774

# Run 11: 73ef257477 (PR #30624)
andreas16700/matplotlib/macos-14-py3.11/21356245393
andreas16700/matplotlib/macos-14-py3.12/21356245393
andreas16700/matplotlib/macos-15-py3.13/21356245393

# Run 12: cd3685fc75 (PR #30316)
andreas16700/matplotlib/macos-14-py3.11/21360264635
andreas16700/matplotlib/macos-14-py3.12/21360264635
andreas16700/matplotlib/macos-15-py3.13/21360264635
```

| # | Upstream SHA | Type | PR | Upstream Status | Our Run | Notes |
|---|--------------|------|-----|-----------------|---------|-------|
| 6 | `86a476d26a` | Merge | [#30640](https://github.com/matplotlib/matplotlib/pull/30640) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21355641000) | CI config (0 tests) - DISCARDED |
| 7 | `efc43d1abf` | Merge | [#30684](https://github.com/matplotlib/matplotlib/pull/30684) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21355761143) | README (0 tests) - DISCARDED |
| 8 | `9eb0cf9aba` | Merge | [#30687](https://github.com/matplotlib/matplotlib/pull/30687) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21355895956) | Docs (0 tests) - DISCARDED |
| 9 | `e0f0ded0d1` | Merge | [#30686](https://github.com/matplotlib/matplotlib/pull/30686) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21355999546) | Docs (0 tests) - DISCARDED |
| 10 | `4cf7021e32` | Merge | [#30698](https://github.com/matplotlib/matplotlib/pull/30698) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21356094774) | pyproject.toml (0 tests) - DISCARDED |
| 11 | `73ef257477` | Direct | [#30624](https://github.com/matplotlib/matplotlib/pull/30624) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21356245393) | Test tolerances (207 tests) - DISCARDED |
| 12 | `cd3685fc75` | Direct | [#30316](https://github.com/matplotlib/matplotlib/pull/30316) | ✅ success | [Run](https://github.com/andreas16700/matplotlib/actions/runs/21360264635) | Baseline attempt (EngFormatter fails) - DISCARDED |

---

### Historical Data (Cherry-Pick Strategy - Deprecated)

_These runs used the old cherry-pick strategy and may not exactly match upstream state._

| # | Fork SHA | Upstream SHA | PR | Report |
|---|----------|--------------|-----|--------|
| 1 | `d620e17f88` | `185b4fae5d` | [#29989](https://github.com/matplotlib/matplotlib/pull/29989) | [Report](#commit-1-185b4fae5d) |

---

## Automation Scripts

We have automation scripts in the `scripts/` directory to streamline the data collection process.

### Available Scripts

| Script | Purpose |
|--------|---------|
| `scripts/fetch_main_workflows.sh` | Fetch upstream workflow data for all runs |
| `scripts/process_run.sh` | Process a single run (reset, restore, verify, commit, push, wait) |
| `scripts/batch_process.sh` | Batch process multiple runs sequentially |

### Using the Automation

**Single Run Processing:**
```bash
./scripts/process_run.sh <run_number> <upstream_sha> <workflow_id> [pr_number]

# Example:
./scripts/process_run.sh 14 c5ffd6c8ad 18932418832 30696
```

**Batch Processing:**
```bash
# Process runs 13 through 134 (waits for Claude evaluation after each)
./scripts/batch_process.sh 13 134

# Process specific range
./scripts/batch_process.sh 20 30
```

### What the Scripts Do

1. **Save our files** (workflow, docs, CLAUDE.md, scripts)
2. **Reset to upstream commit** via `git reset --hard`
3. **Restore our files** from /tmp backup
4. **Adjust workflow matrix** if needed (Run 90+ adds Python 3.14 to macOS-15)
5. **Verify code parity** - only expected files should differ
6. **Commit and push** to trigger workflow
7. **Wait for workflow completion**
8. **Wait for Claude evaluation** - script pauses for manual analysis

### Matrix Change at Run 90

Starting at Run 90 (commit `d4ff5fadc5`), upstream added Python 3.14 to macOS-15. The `process_run.sh` script automatically adjusts our workflow matrix for runs >= 90.

---

## Manual Process (Alternative)

If not using the automation scripts, follow these manual steps:

### Step 1: Identify Next Upstream Commit

```bash
# List upstream first-parent commits after merge base
git log --oneline --reverse 9b61b471d0..upstream/main --first-parent | head -20

# Get specific run number N
git log --oneline --reverse 9b61b471d0..upstream/main --first-parent | sed -n 'Np'
```

### Step 2: Analyze the Upstream Commit

```bash
UPSTREAM_SHA=<sha>

# Get commit details
git show --stat $UPSTREAM_SHA

# If it's a merge, see what commits it includes
git log --oneline $UPSTREAM_SHA^1..$UPSTREAM_SHA^2 2>/dev/null || echo "Not a merge"

# Check upstream's test matrix at this commit
git show $UPSTREAM_SHA:.github/workflows/tests.yml | grep -A 60 "matrix:" | grep -E "macos|python-version"
```

### Step 3: Match Our Fork to Upstream State

**Reset to exact upstream state, keeping our files:**

```bash
# 1. SAVE our files before reset (CRITICAL - don't skip this!)
cp .github/workflows/tests.yml /tmp/our-tests.yml
cp DATA_COLLECTION_PROCESS.md /tmp/DATA_COLLECTION_PROCESS.md
cp CLAUDE.md /tmp/CLAUDE.md 2>/dev/null || true
cp -r scripts /tmp/our-scripts

# 2. Reset to upstream commit (this wipes our files!)
git reset --hard $UPSTREAM_SHA

# 3. RESTORE our files
cp /tmp/our-tests.yml .github/workflows/tests.yml
cp /tmp/DATA_COLLECTION_PROCESS.md DATA_COLLECTION_PROCESS.md
cp /tmp/CLAUDE.md CLAUDE.md 2>/dev/null || true
cp -r /tmp/our-scripts scripts

# 4. Check if upstream's macOS matrix changed at this commit
git show $UPSTREAM_SHA:.github/workflows/tests.yml | grep -A 80 "matrix:" | grep -E "macos-1[45]"
# If matrix differs from our workflow, update .github/workflows/tests.yml accordingly

# 5. Commit
git add .github/workflows/tests.yml DATA_COLLECTION_PROCESS.md CLAUDE.md scripts/
git commit -m "Run N: Match upstream $UPSTREAM_SHA (PR #XXXX) - <brief description>"
```

**Files we preserve across resets:**
| File | Purpose | Location during reset |
|------|---------|----------------------|
| `.github/workflows/tests.yml` | Our ezmon workflow | `/tmp/our-tests.yml` |
| `DATA_COLLECTION_PROCESS.md` | Tracking & reports | `/tmp/DATA_COLLECTION_PROCESS.md` |
| `CLAUDE.md` | Session onboarding | `/tmp/CLAUDE.md` |
| `scripts/` | Automation scripts | `/tmp/our-scripts/` |

**Backup to persistent location** (survives /tmp clearing):
```bash
cp DATA_COLLECTION_PROCESS.md CLAUDE.md ~/pytest-super/matplotlib/
```

### Step 4: Push and Wait for Workflow

```bash
git push origin main --force

gh run list --workflow=tests.yml --limit 1
gh run watch <run_id> --exit-status
```

### Step 5: Get Test Selection Results

```bash
gh run view <run_id> --log | grep -E "(selected|deselected|passed|failed|ezmon:)"
```

### Step 6: Compare with Upstream

Find upstream's workflow run for this commit and compare results.

### Step 7: Document Results

Add entry to tracking table and create detailed report.

---

## Detailed Report Template

### Commit N: `<upstream_sha>` - "<commit message>"

**Metadata**

| Item | Link |
|------|------|
| Fork Commit | [`<fork_sha>`](https://github.com/andreas16700/matplotlib/commit/<fork_sha>) |
| Upstream Commit | [`<upstream_sha>`](https://github.com/matplotlib/matplotlib/commit/<upstream_sha>) |
| Upstream Merge | [`<merge_sha>`](https://github.com/matplotlib/matplotlib/commit/<merge_sha>) |
| PR | [#XXXX](https://github.com/matplotlib/matplotlib/pull/XXXX) |

**Workflow Runs** (Apple Silicon only)

| Variant | Our Run | Upstream Run | Notes |
|---------|---------|--------------|-------|
| _Fill in variants that exist at this commit_ | | | |

**Files Changed**
```
path/to/file1.py (N lines added, M deleted)
path/to/file2.py (N lines added, M deleted)
```

**Test Selection Results**

| Python | Selected | Deselected | Passed | Failed | Skipped |
|--------|----------|------------|--------|--------|---------|
| 3.11 | ? | ? | ? | ? | ? |
| 3.12 | ? | ? | ? | ? | ? |

**Tests Selected**
- `test_module::test_name` - PASSED/FAILED/SKIPPED

**Comparison with Upstream**

| Python | Upstream Result | Our Result | Match? |
|--------|-----------------|------------|--------|
| 3.11 | ? tests, ? failures | ? selected, ? passed | ✅/❌ |
| 3.12 | ? tests, ? failures | ? selected, ? passed | ✅/❌ |

**Analysis**
- Why were these tests selected?
- Were the correct tests selected based on code changes?
- Any false positives (tests that didn't need to run)?
- Any false negatives (tests that should have run but didn't)?

**Plugin Bug Fixes** (if any)
- Issue: <description>
- Fix: <commit SHA in pytest-testmon repo>
- Tests run before continuing: ✅/❌

---


## Detailed Run Reports

Reports are organized in separate files by groups of 5 runs:

| File | Runs | Description |
|------|------|-------------|
| [reports/runs_001-005.md](reports/runs_001-005.md) | 1-5 | Initial runs including historical Commit 1 |
| [reports/runs_006-010.md](reports/runs_006-010.md) | 6-10 | Infrastructure issues period (Runs 8-10) |
| [reports/runs_011-015.md](reports/runs_011-015.md) | 11-15 | Post-baseline runs |
| [reports/runs_016-020.md](reports/runs_016-020.md) | 16-20 | Backend fixes (TK, Qt, macOS thread safety) |
| [reports/runs_021-025.md](reports/runs_021-025.md) | 21-25 | Core API changes, plugin retry fix |
| [reports/runs_026-030.md](reports/runs_026-030.md) | 26-30 | Docs/infrastructure changes |
| [reports/runs_031-035.md](reports/runs_031-035.md) | 31-35 | Mixed code and docstring changes |
| [reports/runs_036-040.md](reports/runs_036-040.md) | 36-40 | Qt F11 fix, legend PatchCollection, colorbar alignment |
| [reports/runs_041-045.md](reports/runs_041-045.md) | 41-45 | legend.linewidth, axis3d tight bbox fix |
| [reports/runs_046-050.md](reports/runs_046-050.md) | 46-50 | **Run 46 VALIDATION SUCCESS** - rcParam test failure match |
| [reports/runs_051-055.md](reports/runs_051-055.md) | 51-55 | imshow animated fix, HiDPI loop fix, scatter args |

### Report Format

Each report includes:
1. **Metadata** - Links to upstream commit, PR, workflows
2. **Git Diff (upstream code changes)** - What Python files changed between runs
3. **Git Diff (code parity)** - Verification that our commit matches upstream (only infrastructure files differ)
4. **Test Selection Results** - ezmon output per Python version
5. **Analysis** - Interpretation of results, false negative assessment

---

## Current Status

- **Workflow runs processed**: 67
- **Total upstream runs since merge base**: ~172
- **Remaining runs**: ~100
- **False negatives detected**: 0
- **Validation successes**: Run 46 (test_rcparam_stubs failure matches upstream)
- **Baselines established**:
  - Run 12: macOS variants (forced full test run with `--ezmon-noselect`)
  - Run 56: Linux ubuntu-22.04 (first run, baseline)
  - Run 56-retry: Linux ubuntu-24.04-arm (first run, baseline)
  - **Run 66-baseline**: All 5 variants re-baselined with `--ezmon-noselect` after plugin architecture changes (collection-time tracking instead of AST parsing). Run ID: [21501730675](https://github.com/andreas16700/matplotlib/actions/runs/21501730675)
- **Next action**: Push Run 56-retry (adds ARM Linux), then continue 57-135
- **Known issue**: Run 40 revealed NetDB race condition in parallel job execution (documented)
- **Platform expansion**: Run 56 adds Linux CI coverage (Windows removed - DLL issues with editable installs)
- **Note**: Runs 8-11 had upstream macOS infrastructure issues
- **Correction**: Previous "Runs 34-38" were incorrectly numbered - actually Runs 131-135. Now corrected.
- **Plugin fix**: Run 21 required retry fix for HTTP 520 errors (Cloudflare transient failures)

---

## Configuration

### Merge Base
- **Commit**: `9b61b471d0`
- **Message**: "Merge pull request #30655 from rcomer/cs-draw"
- **Date**: 2025-10-17

### Commands Reference

```bash
# Count remaining workflow runs
git log --oneline 9b61b471d0..upstream/main --first-parent | wc -l

# List next 10 runs to process
git log --oneline --reverse 9b61b471d0..upstream/main --first-parent | head -10

# Check what a merge includes
git log --oneline <merge>^1..<merge>^2

# Check upstream test matrix at a commit
git show <sha>:.github/workflows/tests.yml | grep -A 60 "matrix:"
```

---

## Resuming in a New Claude Session

> **START HERE**: If you're a new Claude session continuing this work, follow these steps exactly.

### Quick Start for New Sessions

**1. Initiate session from the correct directory:**
```bash
cd /tmp/matplotlib && claude
```

**2. First message to Claude:**
```
Continue the matplotlib ezmon data collection process.
Read /tmp/matplotlib/DATA_COLLECTION_PROCESS.md first.
```

### What This Project Is

We're validating **ezmon** (our fork of pytest-testmon) by:
- Replaying matplotlib's upstream CI history on our fork
- Comparing test results to verify ezmon selects the right tests
- Documenting any **false negatives** (tests that should have run but didn't)

**Why this matters**: ezmon uses code fingerprinting to skip unchanged tests. If it incorrectly skips a test that would have failed, that's a critical bug. We're using matplotlib (~10,000 tests) as a real-world validation corpus.

### Key Context for Claude

1. **Working directory**: `/tmp/matplotlib` (NOT `~/pytest-super/matplotlib` which has outdated docs)

2. **Our fork vs upstream**:
   - We maintain codebase parity with upstream matplotlib
   - Only differences: our workflow file (`.github/workflows/tests.yml`) and this doc
   - Our workflow uses ezmon instead of running all tests

3. **The process** (for each upstream workflow run):
   - Reset to upstream commit state
   - Keep our workflow file and docs
   - Push to trigger our CI
   - Compare results with upstream's CI
   - Document in this file

4. **Critical validation criteria**:
   - If upstream had a test failure, we MUST also catch it
   - If we pass but upstream failed (same test, same code), that's a **false negative** - STOP and investigate

5. **For each run, thoroughly analyze**:
   - What files changed (git diff)
   - What modules depend on those files
   - Whether ezmon's test selection is appropriate
   - Link to actual upstream workflow runs (not just PRs)

### Current State Checklist

When resuming, verify:
```bash
cd /tmp/matplotlib
git remote -v                    # Should show origin (andreas16700) and upstream (matplotlib)
git fetch upstream
git log --oneline -3             # Check current HEAD
gh run list --workflow=tests.yml --limit 3  # Check recent workflow runs
```

### If `/tmp/matplotlib` Doesn't Exist

The `/tmp` directory may be cleared on reboot. Recreate:
```bash
cd /tmp
git clone https://github.com/andreas16700/matplotlib.git
cd matplotlib
git remote add upstream https://github.com/matplotlib/matplotlib.git
git fetch upstream
```

Then check the tracking table in this doc to see current progress and continue from there.
