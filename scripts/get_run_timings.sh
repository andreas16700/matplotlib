#!/bin/bash
# Fetch timing data for multiple workflow runs efficiently
# Usage: ./get_run_timings.sh RUN_ID1 RUN_ID2 ...

REPO="andreas16700/matplotlib"

# For REST API approach - batch fetch job data
fetch_jobs_batch() {
    local runs=("$@")
    local results="["
    local first=true

    for run_id in "${runs[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            results+=","
        fi

        # Fetch jobs for this run
        jobs_json=$(gh api "repos/$REPO/actions/runs/$run_id/jobs" --jq '{
            run_id: .jobs[0].run_id,
            jobs: [.jobs[] | {
                name: .name,
                started_at: .started_at,
                completed_at: .completed_at,
                conclusion: .conclusion,
                steps: [.steps[] | select(.name == "Run tests (pytest + ezmon NetDB)") | {
                    name: .name,
                    started_at: .started_at,
                    completed_at: .completed_at
                }]
            }]
        }')
        results+="$jobs_json"
    done

    results+="]"
    echo "$results"
}

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 RUN_ID1 [RUN_ID2 ...]"
    echo "Example: $0 21503377339 21503780051 21504067462 21504227586"
    exit 1
fi

echo "Fetching timing data for ${#@} runs..."
raw_data=$(fetch_jobs_batch "$@")

# Process with jq - using proper jq function syntax
echo "$raw_data" | jq -r '
    def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    def duration:
        if .[0] and .[1] then (.[1] | parse_time) - (.[0] | parse_time)
        else null end;
    def fmt_time:
        if . then "\(. / 60 | floor)m\(. % 60)s"
        else "N/A" end;

    .[] |
    "### Run \(.run_id)\n",
    "| Variant | Total | Test Step |",
    "|---------|-------|-----------|",
    (.jobs[] |
        ([.started_at, .completed_at] | duration) as $total |
        (if .steps[0] then [.steps[0].started_at, .steps[0].completed_at] | duration else null end) as $test |
        "| \(.name | gsub(" \\(ezmon\\)"; "")) | \($total | fmt_time) | \($test | fmt_time) |"
    ),
    ""
'
