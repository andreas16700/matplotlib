#!/bin/bash
# Compare per-job timing data between our fork and upstream
# Usage: ./compare_jobs.sh OUR_RUN_ID UPSTREAM_COMMIT_SHA

OUR_REPO="andreas16700/matplotlib"
UPSTREAM_REPO="matplotlib/matplotlib"

if [ $# -lt 2 ]; then
    echo "Usage: $0 OUR_RUN_ID UPSTREAM_COMMIT_SHA"
    exit 1
fi

OUR_RUN_ID="$1"
COMMIT_SHA="$2"

# Find upstream workflow run
UPSTREAM_RUN_ID=$(gh api "repos/$UPSTREAM_REPO/actions/workflows/tests.yml/runs?branch=main&per_page=100" \
    --jq ".workflow_runs[] | select(.head_sha | startswith(\"$COMMIT_SHA\")) | .id" | head -1)

if [ -z "$UPSTREAM_RUN_ID" ]; then
    echo "Upstream run not found for $COMMIT_SHA"
    exit 1
fi

echo "**Our Run**: [$OUR_RUN_ID](https://github.com/$OUR_REPO/actions/runs/$OUR_RUN_ID)"
echo "**Upstream Run**: [$UPSTREAM_RUN_ID](https://github.com/$UPSTREAM_REPO/actions/runs/$UPSTREAM_RUN_ID)"
echo ""

# Get our job data
OUR_JOBS=$(gh api "repos/$OUR_REPO/actions/runs/$OUR_RUN_ID/jobs?per_page=100" --jq '
    def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    def duration(a; b): if a and b then ((b | parse_time) - (a | parse_time)) else null end;
    [.jobs[] |
    select(.name | test("Python.*on (macos|ubuntu)"; "i")) |
    duration(.started_at; .completed_at) as $total |
    ([.steps[] | select(.name | test("Run tests"))] | .[0]) as $test_step |
    duration($test_step.started_at; $test_step.completed_at) as $test_dur |
    {
        name: (.name | gsub(" \\(ezmon\\)"; "")),
        total: $total,
        test: $test_dur,
        conclusion: .conclusion
    }]
')

# Get upstream job data
UPSTREAM_JOBS=$(gh api "repos/$UPSTREAM_REPO/actions/runs/$UPSTREAM_RUN_ID/jobs?per_page=100" --jq '
    def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    def duration(a; b): if a and b then ((b | parse_time) - (a | parse_time)) else null end;
    [.jobs[] |
    select(.name | test("Python.*on (macos|ubuntu)"; "i")) |
    duration(.started_at; .completed_at) as $total |
    ([.steps[] | select(.name | test("Run pytest"))] | .[0]) as $test_step |
    duration($test_step.started_at; $test_step.completed_at) as $test_dur |
    {
        name: .name,
        total: $total,
        test: $test_dur,
        conclusion: .conclusion
    }]
')

# Normalize names for matching
normalize_name() {
    echo "$1" | sed 's/Python /py/g; s/ on /-/g; s/ (ezmon)//g'
}

echo "| Variant | Our Total | Our Test | Our Result | Upstream Total | Upstream Test | Upstream Result |"
echo "|---------|-----------|----------|------------|----------------|---------------|-----------------|"

# Output combined data using jq
echo "$OUR_JOBS" | jq -r --argjson up "$UPSTREAM_JOBS" '
    def fmt: if . then "\(. / 60 | floor)m\(. % 60)s" else "N/A" end;
    def norm: gsub("Python "; "py") | gsub(" on "; "-") | gsub(" \\(.*\\)"; "");

    .[] | . as $our |
    ($up | map(select((.name | norm) == ($our.name | norm))) | .[0]) as $match |
    "| \($our.name) | \($our.total | fmt) | \($our.test | fmt) | \($our.conclusion) | \(if $match then ($match.total | fmt) else "N/A" end) | \(if $match then ($match.test | fmt) else "N/A" end) | \(if $match then $match.conclusion else "N/A" end) |"
'
