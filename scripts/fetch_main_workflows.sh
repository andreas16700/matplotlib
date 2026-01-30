#!/bin/bash
# Fetch upstream workflow runs on main branch with macOS job details
# Usage: ./fetch_main_workflows.sh [start_sha]
#
# This script finds all commits on main after the given SHA and their
# corresponding push workflow runs, including macOS job matrix details.

START_SHA="${1:-cd3685fc75}"  # Default: Run 12

REPO="matplotlib/matplotlib"

echo "=== Fetching Upstream Main Workflow Runs (macOS only) ==="
echo "Starting after: $START_SHA"
echo "Repository: $REPO"
echo ""

# Ensure we have latest upstream
git fetch upstream --quiet 2>/dev/null || true

# Count total commits
TOTAL=$(git log --oneline --first-parent "${START_SHA}..upstream/main" | wc -l | tr -d ' ')
echo "Total commits to process: $TOTAL"
echo ""

# Header
echo "| Run | Commit | PR/Description | Workflow | macOS-14 | macOS-15 | Overall |"
echo "|-----|--------|----------------|----------|----------|----------|---------|"

COUNTER=13  # Starting from Run 13 (after Run 12)

# Function to format job status
format_job() {
    local name="$1"
    local status="$2"
    local pyver=$(echo "$name" | grep -oE '3\.[0-9]+' || echo "?")
    local icon
    case "$status" in
        success) icon="✅" ;;
        failure) icon="❌" ;;
        skipped) icon="⏭" ;;
        cancelled) icon="⚠️" ;;
        *) icon="?" ;;
    esac
    echo -n "py${pyver}${icon} "
}

export -f format_job

git log --oneline --reverse --first-parent "${START_SHA}..upstream/main" | while read -r SHA MSG; do
    # Get full SHA
    FULL_SHA=$(git rev-parse "$SHA" 2>/dev/null || echo "$SHA")

    # Get commit date for API search
    COMMIT_DATE=$(git show -s --format=%ci "$SHA" 2>/dev/null | cut -d' ' -f1)

    # Extract PR number if present
    if [[ "$MSG" =~ \#([0-9]+) ]]; then
        PR_NUM="${BASH_REMATCH[1]}"
        PR_LINK="[#${PR_NUM}](https://github.com/${REPO}/pull/${PR_NUM})"
    else
        PR_LINK="-"
    fi

    # Truncate message
    SHORT_MSG="${MSG:0:40}"
    if [ ${#MSG} -gt 40 ]; then
        SHORT_MSG="${SHORT_MSG}..."
    fi

    # Find push workflow run for this commit
    WORKFLOW_ID=$(gh api "repos/${REPO}/actions/workflows/tests.yml/runs?branch=main&event=push&created=${COMMIT_DATE}&per_page=100" 2>/dev/null | \
        jq -r --arg sha "$FULL_SHA" '.workflow_runs[] | select(.head_sha == $sha) | .id' | head -1)

    if [ -n "$WORKFLOW_ID" ]; then
        # Get workflow conclusion
        WORKFLOW_CONCLUSION=$(gh api "repos/${REPO}/actions/runs/${WORKFLOW_ID}" 2>/dev/null | jq -r '.conclusion')

        case "$WORKFLOW_CONCLUSION" in
            "success") OVERALL="✅" ;;
            "failure") OVERALL="❌" ;;
            "cancelled") OVERALL="⚠️" ;;
            *) OVERALL="?" ;;
        esac

        WORKFLOW_LINK="[${WORKFLOW_ID}](https://github.com/${REPO}/actions/runs/${WORKFLOW_ID})"

        # Get macOS jobs as JSON
        JOBS_JSON=$(gh api "repos/${REPO}/actions/runs/${WORKFLOW_ID}/jobs?per_page=100" 2>/dev/null)

        # Parse macOS-14 jobs using jq to format
        MACOS14_JOBS=$(echo "$JOBS_JSON" | jq -r '
            .jobs[] | select(.name | contains("macos-14")) |
            "py" + (.name | capture("(?<v>3\\.[0-9]+)") | .v) +
            (if .conclusion == "success" then "✅"
             elif .conclusion == "failure" then "❌"
             elif .conclusion == "skipped" then "⏭"
             elif .conclusion == "cancelled" then "⚠️"
             else "?" end)
        ' 2>/dev/null | tr '\n' ' ')

        # Parse macOS-15 jobs
        MACOS15_JOBS=$(echo "$JOBS_JSON" | jq -r '
            .jobs[] | select(.name | contains("macos-15")) |
            "py" + (.name | capture("(?<v>3\\.[0-9]+)") | .v) +
            (if .conclusion == "success" then "✅"
             elif .conclusion == "failure" then "❌"
             elif .conclusion == "skipped" then "⏭"
             elif .conclusion == "cancelled" then "⚠️"
             else "?" end)
        ' 2>/dev/null | tr '\n' ' ')

        # Default to "-" if no jobs found
        [ -z "$MACOS14_JOBS" ] && MACOS14_JOBS="-"
        [ -z "$MACOS15_JOBS" ] && MACOS15_JOBS="-"

    else
        WORKFLOW_LINK="Not found"
        MACOS14_JOBS="-"
        MACOS15_JOBS="-"
        OVERALL="?"
    fi

    COMMIT_LINK="[\`${SHA}\`](https://github.com/${REPO}/commit/${FULL_SHA})"

    echo "| $COUNTER | $COMMIT_LINK | $PR_LINK $SHORT_MSG | $WORKFLOW_LINK | $MACOS14_JOBS| $MACOS15_JOBS| $OVERALL |"

    COUNTER=$((COUNTER + 1))
done

echo ""
echo "=== Legend ==="
echo "✅ = success, ❌ = failure, ⚠️ = cancelled, ⏭ = skipped, ? = unknown"
echo ""
echo "=== Next Steps ==="
echo "For each run, verify code parity before testing:"
echo "1. git reset --hard <commit_sha>"
echo "2. Restore our workflow + docs"
echo "3. Verify: git diff <commit_sha> --name-only (should only show our 3 files)"
echo "4. Push and compare with upstream workflow results"
