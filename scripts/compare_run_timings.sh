#!/bin/bash
# Compare timing data between our fork and upstream for a given commit
# Usage: ./compare_run_timings.sh OUR_RUN_ID UPSTREAM_COMMIT_SHA

OUR_REPO="andreas16700/matplotlib"
UPSTREAM_REPO="matplotlib/matplotlib"

if [ $# -lt 2 ]; then
    echo "Usage: $0 OUR_RUN_ID UPSTREAM_COMMIT_SHA"
    echo "Example: $0 21503377339 3782e61b6f"
    exit 1
fi

OUR_RUN_ID="$1"
COMMIT_SHA="$2"

echo "=== Comparing Run Timings ==="
echo "Our Run: $OUR_RUN_ID"
echo "Upstream Commit: $COMMIT_SHA"
echo ""

# Function to extract job timings
extract_timings() {
    local repo="$1"
    local run_id="$2"

    gh api "repos/$repo/actions/runs/$run_id/jobs?per_page=100" --jq '
        def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
        def duration:
            if .[0] and .[1] then (.[1] | parse_time) - (.[0] | parse_time)
            else null end;

        [.jobs[] |
        select(.name | test("Python.*on (macos|ubuntu)"; "i")) |
        {
            name: (.name | gsub(" \\(ezmon\\)"; "") | gsub("Tests \\("; "") | gsub("\\)$"; "")),
            conclusion: .conclusion,
            total_sec: ([.started_at, .completed_at] | duration),
            test_step_sec: (
                [.steps[] | select(.name | test("pytest|Run tests"; "i"))] |
                if length > 0 then
                    .[0] | ([.started_at, .completed_at] | duration)
                else null end
            )
        }]
    '
}

# Get our timings
echo "Fetching our run data..."
OUR_DATA=$(extract_timings "$OUR_REPO" "$OUR_RUN_ID")

# Find upstream run
echo "Finding upstream run..."
UPSTREAM_RUN_ID=$(gh api "repos/$UPSTREAM_REPO/actions/runs?branch=main&event=push&per_page=100" \
    --jq ".workflow_runs[] | select(.head_sha | startswith(\"$COMMIT_SHA\")) | .id" | head -1)

if [ -z "$UPSTREAM_RUN_ID" ]; then
    # Try page 2
    UPSTREAM_RUN_ID=$(gh api "repos/$UPSTREAM_REPO/actions/runs?branch=main&event=push&per_page=100&page=2" \
        --jq ".workflow_runs[] | select(.head_sha | startswith(\"$COMMIT_SHA\")) | .id" | head -1)
fi

if [ -z "$UPSTREAM_RUN_ID" ]; then
    echo "No upstream run found for $COMMIT_SHA"
    echo ""
    echo "Our timings only:"
    echo "$OUR_DATA" | jq -r '
        def fmt(s): if s then "\(s / 60 | floor)m\(s % 60)s" else "N/A" end;
        .[] | "| \(.name) | \(.total_sec | fmt) | \(.test_step_sec | fmt) | \(.conclusion) |"
    '
    exit 0
fi

echo "Upstream Run ID: $UPSTREAM_RUN_ID"
echo ""

# Get upstream timings
echo "Fetching upstream run data..."
UPSTREAM_DATA=$(extract_timings "$UPSTREAM_REPO" "$UPSTREAM_RUN_ID")

# Combine and format
echo ""
echo "| Variant | Ours Total | Ours Test | Upstream Total | Upstream Test | Match |"
echo "|---------|------------|-----------|----------------|---------------|-------|"

# Join the data
echo "$OUR_DATA" | jq -r --argjson upstream "$UPSTREAM_DATA" '
    def fmt(s): if s then "\(s / 60 | floor)m\(s % 60)s" else "N/A" end;
    def normalize_name: gsub("Python "; "py") | gsub(" on "; "-");

    .[] as $our |
    ($upstream | map(select((.name | normalize_name) == ($our.name | normalize_name))) | .[0]) as $up |
    "| \($our.name) | \($our.total_sec | fmt) | \($our.test_step_sec | fmt) | \(if $up then $up.total_sec | fmt else "N/A" end) | \(if $up then $up.test_step_sec | fmt else "N/A" end) | \(if $up then (if $our.conclusion == $up.conclusion then "✅" else "⚠️" end) else "-" end) |"
'
