#!/bin/bash
# Batch process upstream runs for ezmon validation
# Usage: ./batch_process.sh [start_run] [end_run]
#
# Processes runs sequentially, waiting for Claude evaluation after each.

set -e

START_RUN="${1:-13}"
END_RUN="${2:-134}"

REPO="matplotlib/matplotlib"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=============================================="
echo "Batch Processing Runs $START_RUN to $END_RUN"
echo "=============================================="
echo ""

# Get the list of runs from our saved data or generate fresh
if [ ! -f /tmp/upstream_runs.txt ]; then
    echo "Generating run list..."
    git fetch upstream --quiet

    # Start from Run 12 commit
    BASE_SHA="cd3685fc75"

    git log --oneline --reverse --first-parent "${BASE_SHA}..upstream/main" | nl -v 13 > /tmp/upstream_runs.txt
fi

# Process each run
for RUN_NUM in $(seq "$START_RUN" "$END_RUN"); do
    echo ""
    echo "=============================================="
    echo "Preparing Run $RUN_NUM"
    echo "=============================================="

    # Get commit info for this run
    # File lines are 1-indexed but run numbers start at 13, so offset = run - 12
    OFFSET=$((RUN_NUM - 12))
    LINE=$(sed -n "${OFFSET}p" /tmp/upstream_runs.txt 2>/dev/null | sed 's/^[[:space:]]*//')

    if [ -z "$LINE" ]; then
        echo "ERROR: Could not find run $RUN_NUM in list"
        continue
    fi

    SHA=$(echo "$LINE" | awk '{print $2}')
    MSG=$(echo "$LINE" | cut -d' ' -f3-)

    # Extract PR number if present
    PR_NUM=""
    if [[ "$MSG" =~ \#([0-9]+) ]]; then
        PR_NUM="${BASH_REMATCH[1]}"
    fi

    # Get full SHA
    FULL_SHA=$(git rev-parse "$SHA" 2>/dev/null || echo "$SHA")

    # Get commit date for workflow lookup
    COMMIT_DATE=$(git show -s --format=%ci "$SHA" 2>/dev/null | cut -d' ' -f1)

    # Find upstream workflow
    WORKFLOW_ID=$(gh api "repos/${REPO}/actions/workflows/tests.yml/runs?branch=main&event=push&created=${COMMIT_DATE}&per_page=100" 2>/dev/null | \
        jq -r --arg sha "$FULL_SHA" '.workflow_runs[] | select(.head_sha == $sha) | .id' | head -1)

    if [ -z "$WORKFLOW_ID" ]; then
        echo "WARNING: No upstream workflow found for run $RUN_NUM ($SHA)"
        echo "Skipping..."
        continue
    fi

    echo "Commit: $SHA"
    echo "Message: $MSG"
    echo "PR: ${PR_NUM:-N/A}"
    echo "Upstream Workflow: $WORKFLOW_ID"
    echo ""

    # Process this run
    "$SCRIPT_DIR/process_run.sh" "$RUN_NUM" "$FULL_SHA" "$WORKFLOW_ID" "$PR_NUM"

    echo ""
    echo "Run $RUN_NUM complete. Moving to next..."
    sleep 2
done

echo ""
echo "=============================================="
echo "Batch Processing Complete"
echo "=============================================="
echo "Processed runs $START_RUN to $END_RUN"
