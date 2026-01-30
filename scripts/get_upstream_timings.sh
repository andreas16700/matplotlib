#!/bin/bash
# Fetch timing data for upstream workflow runs by commit SHA
# Usage: ./get_upstream_timings.sh COMMIT_SHA

UPSTREAM_REPO="matplotlib/matplotlib"

if [ $# -eq 0 ]; then
    echo "Usage: $0 COMMIT_SHA"
    exit 1
fi

COMMIT_SHA="$1"

# Find the workflow run for this commit on main branch (push event)
echo "Finding upstream run for commit $COMMIT_SHA..."

# Get all runs and find the one matching our commit
RUN_INFO=$(gh api "repos/$UPSTREAM_REPO/actions/runs?branch=main&event=push&per_page=100" \
    --jq ".workflow_runs[] | select(.head_sha | startswith(\"$COMMIT_SHA\")) | {id, name, status, conclusion, head_sha}")

if [ -z "$RUN_INFO" ]; then
    # Try searching in older runs
    RUN_INFO=$(gh api "repos/$UPSTREAM_REPO/actions/runs?branch=main&event=push&per_page=100&page=2" \
        --jq ".workflow_runs[] | select(.head_sha | startswith(\"$COMMIT_SHA\")) | {id, name, status, conclusion, head_sha}")
fi

if [ -z "$RUN_INFO" ]; then
    echo "No upstream run found for commit $COMMIT_SHA"
    exit 1
fi

RUN_ID=$(echo "$RUN_INFO" | jq -r '.id')
echo "Found run ID: $RUN_ID"

# Get job details
gh api "repos/$UPSTREAM_REPO/actions/runs/$RUN_ID/jobs?per_page=100" --jq '
    def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    def duration:
        if .[0] and .[1] then (.[1] | parse_time) - (.[0] | parse_time)
        else null end;
    def fmt_time:
        if . then "\(. / 60 | floor)m\(. % 60)s"
        else "N/A" end;

    .jobs[] |
    select(.name | test("Python.*on (macos|ubuntu)")) |
    {
        name: .name,
        conclusion: .conclusion,
        total_sec: ([.started_at, .completed_at] | duration),
        test_step: (
            [.steps[] | select(.name | test("pytest|Run tests"))] |
            if length > 0 then
                .[0] | {
                    duration_sec: ([.started_at, .completed_at] | duration)
                }
            else null end
        )
    } |
    "\(.name): total=\(.total_sec | fmt_time), test=\(if .test_step then .test_step.duration_sec | fmt_time else "N/A" end), result=\(.conclusion)"
'
