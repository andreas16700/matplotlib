#!/bin/bash
# Process a single upstream run for ezmon validation
# Usage: ./process_run.sh <run_number> <upstream_sha> <workflow_id> [pr_number]
#
# This script:
# 1. Resets to upstream commit
# 2. Restores our workflow + docs
# 3. Adjusts workflow matrix if needed (Run 90+ adds py3.14)
# 4. Verifies code parity
# 5. Commits and pushes
# 6. Waits for workflow completion
# 7. Waits for Claude to evaluate results

set -e

RUN_NUM="${1:?Usage: $0 <run_number> <upstream_sha> <workflow_id> [pr_number]}"
UPSTREAM_SHA="${2:?Usage: $0 <run_number> <upstream_sha> <workflow_id> [pr_number]}"
UPSTREAM_WORKFLOW_ID="${3:?Usage: $0 <run_number> <upstream_sha> <workflow_id> [pr_number]}"
PR_NUM="${4:-}"

REPO="matplotlib/matplotlib"
OUR_REPO="andreas16700/matplotlib"

# Run 90 is where macOS-15 adds Python 3.14
MATRIX_CHANGE_RUN=90

echo "=============================================="
echo "Processing Run $RUN_NUM"
echo "=============================================="
echo "Upstream SHA: $UPSTREAM_SHA"
echo "Upstream Workflow: $UPSTREAM_WORKFLOW_ID"
[ -n "$PR_NUM" ] && echo "PR: #$PR_NUM"
echo ""

# Step 1: Save our files
echo "[1/7] Saving our files..."
cp .github/workflows/tests.yml /tmp/our-tests.yml
cp DATA_COLLECTION_PROCESS.md /tmp/DATA_COLLECTION_PROCESS.md
cp CLAUDE.md /tmp/CLAUDE.md
rm -rf /tmp/our-scripts && cp -r scripts /tmp/our-scripts

# Step 2: Reset to upstream
echo "[2/7] Resetting to upstream $UPSTREAM_SHA..."
git fetch upstream --quiet
git reset --hard "$UPSTREAM_SHA"

# Step 3: Restore our files
echo "[3/7] Restoring our files..."
mkdir -p .github/workflows
cp /tmp/our-tests.yml .github/workflows/tests.yml
cp /tmp/DATA_COLLECTION_PROCESS.md DATA_COLLECTION_PROCESS.md
cp /tmp/CLAUDE.md CLAUDE.md
cp -r /tmp/our-scripts scripts

# Step 4: Adjust workflow matrix if needed
echo "[4/7] Checking workflow matrix..."
if [ "$RUN_NUM" -ge "$MATRIX_CHANGE_RUN" ]; then
    echo "  Run $RUN_NUM >= $MATRIX_CHANGE_RUN: Adding Python 3.14 to macOS-15"
    # Check if py3.14 already in workflow
    if ! grep -q "python-version: '3.14'" .github/workflows/tests.yml; then
        # Add py3.14 to macOS-15
        sed -i.bak '/os: macos-15/,/python-version:/{s/python-version: .3\.13./python-version: "3.13"\n          - os: macos-15\n            python-version: "3.14"/}' .github/workflows/tests.yml
        rm -f .github/workflows/tests.yml.bak
        echo "  Added Python 3.14 to macOS-15 matrix"
    else
        echo "  Python 3.14 already present"
    fi
else
    echo "  Run $RUN_NUM < $MATRIX_CHANGE_RUN: Using standard matrix (3.11, 3.12, 3.13)"
fi

# Step 5: Verify code parity
echo "[5/7] Verifying code parity..."
DIFF_FILES=$(git diff "$UPSTREAM_SHA" --name-only | sort)
EXPECTED_FILES=$(echo -e ".github/workflows/tests.yml\nCLAUDE.md\nDATA_COLLECTION_PROCESS.md\nscripts/fetch_main_workflows.sh\nscripts/process_run.sh" | sort)

# Also check for deleted workflow files (they won't show in diff since they're in upstream)
EXTRA_DIFF=$(git diff "$UPSTREAM_SHA" --name-only | grep -v "^\.github/workflows/\|^CLAUDE\.md$\|^DATA_COLLECTION_PROCESS\.md$\|^scripts/" || true)

if [ -n "$EXTRA_DIFF" ]; then
    echo "ERROR: Unexpected file differences detected!"
    echo "Expected only: .github/workflows/*, CLAUDE.md, DATA_COLLECTION_PROCESS.md, scripts/*"
    echo "Found extra: $EXTRA_DIFF"
    exit 1
fi

echo "  Code parity verified. Only expected files differ:"
git diff "$UPSTREAM_SHA" --name-only | head -10
echo ""

# Step 6: Commit and push
echo "[6/7] Committing and pushing..."
COMMIT_MSG="Run $RUN_NUM: Match upstream $UPSTREAM_SHA"
[ -n "$PR_NUM" ] && COMMIT_MSG="$COMMIT_MSG (PR #$PR_NUM)"

git add -A
git commit -m "$COMMIT_MSG

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

git push origin main --force

# Get our workflow run ID
sleep 5  # Wait for GitHub to register the push
OUR_WORKFLOW_ID=$(gh run list --workflow=tests.yml --limit 1 --json databaseId --jq '.[0].databaseId')
echo "  Our workflow triggered: $OUR_WORKFLOW_ID"
echo "  URL: https://github.com/$OUR_REPO/actions/runs/$OUR_WORKFLOW_ID"

# Step 7: Wait for workflow completion
echo "[7/7] Waiting for workflow to complete..."
echo "  This may take 20-40 minutes..."
gh run watch "$OUR_WORKFLOW_ID" --exit-status || true

# Get final status
OUR_STATUS=$(gh run view "$OUR_WORKFLOW_ID" --json conclusion --jq '.conclusion')

echo ""
echo "=============================================="
echo "Run $RUN_NUM Complete"
echo "=============================================="
echo ""
echo "Our workflow: https://github.com/$OUR_REPO/actions/runs/$OUR_WORKFLOW_ID"
echo "Our status: $OUR_STATUS"
echo ""
echo "Upstream workflow: https://github.com/$REPO/actions/runs/$UPSTREAM_WORKFLOW_ID"
echo ""
echo "=============================================="
echo "WAITING FOR CLAUDE TO EVALUATE"
echo "=============================================="
echo ""
echo "Claude should now:"
echo "1. Compare our results with upstream"
echo "2. Evaluate test selections/deselections"
echo "3. Write report to DATA_COLLECTION_PROCESS.md"
echo "4. Type 'continue' to proceed to next run"
echo ""
echo "Run details saved to: /tmp/run_${RUN_NUM}_info.txt"

# Save run info for Claude
cat > "/tmp/run_${RUN_NUM}_info.txt" << EOF
Run: $RUN_NUM
Upstream SHA: $UPSTREAM_SHA
Upstream Workflow: $UPSTREAM_WORKFLOW_ID
PR: ${PR_NUM:-N/A}
Our Workflow: $OUR_WORKFLOW_ID
Our Status: $OUR_STATUS
EOF

# Wait for input
read -p "Type 'continue' when ready to proceed: " INPUT
if [ "$INPUT" != "continue" ]; then
    echo "Aborted by user"
    exit 1
fi

echo "Continuing to next run..."
