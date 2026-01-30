#!/bin/bash
# Get run comparison data: our timings + upstream status
# Usage: ./get_run_comparison.sh OUR_RUN_ID UPSTREAM_COMMIT_SHA

OUR_REPO="andreas16700/matplotlib"
UPSTREAM_REPO="matplotlib/matplotlib"

if [ $# -lt 2 ]; then
    echo "Usage: $0 OUR_RUN_ID UPSTREAM_COMMIT_SHA"
    exit 1
fi

OUR_RUN_ID="$1"
COMMIT_SHA="$2"

echo "### Run Comparison"
echo ""
echo "**Our Run**: [$OUR_RUN_ID](https://github.com/$OUR_REPO/actions/runs/$OUR_RUN_ID)"
echo ""

# Get upstream combined status
UPSTREAM_STATUS=$(gh api "repos/$UPSTREAM_REPO/commits/$COMMIT_SHA/status" --jq '.state')

# Get details on what might have failed
FAILED_CONTEXTS=$(gh api "repos/$UPSTREAM_REPO/commits/$COMMIT_SHA/status" --jq '[.statuses[] | select(.state == "failure" or .state == "error") | .context] | join(", ")')

echo "**Upstream CI**: $UPSTREAM_STATUS"
if [ -n "$FAILED_CONTEXTS" ]; then
    echo "  - Failed: $FAILED_CONTEXTS"
fi
echo ""

# Get our job details
echo "| Variant | Our Total | Our Test | Our Result |"
echo "|---------|-----------|----------|------------|"

gh api "repos/$OUR_REPO/actions/runs/$OUR_RUN_ID/jobs?per_page=100" --jq '
    def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    def duration(a; b):
        if a and b then ((b | parse_time) - (a | parse_time))
        else null end;
    def fmt: if . then "\(. / 60 | floor)m\(. % 60)s" else "N/A" end;

    .jobs[] |
    select(.name | test("Python.*on (macos|ubuntu)"; "i")) |
    duration(.started_at; .completed_at) as $total |
    ([.steps[] | select(.name | test("Run tests"))] | .[0]) as $test_step |
    duration($test_step.started_at; $test_step.completed_at) as $test_dur |
    "| \(.name | gsub(" \\(ezmon\\)"; "")) | \($total | fmt) | \($test_dur | fmt) | \(.conclusion) |"
'
