#!/bin/bash
# Fetch CircleCI timing data for matplotlib upstream by commit SHA
# Usage: ./get_circleci_timings.sh COMMIT_SHA

if [ $# -eq 0 ]; then
    echo "Usage: $0 COMMIT_SHA"
    exit 1
fi

COMMIT_SHA="$1"
PROJECT="gh/matplotlib/matplotlib"

# Find pipeline by commit
echo "Finding CircleCI pipeline for commit $COMMIT_SHA..."

# Get pipelines and find matching one
PIPELINE_ID=$(curl -s "https://circleci.com/api/v2/project/$PROJECT/pipeline?branch=main" | \
    jq -r --arg sha "$COMMIT_SHA" '.items[] | select(.vcs.revision | startswith($sha)) | .id' | head -1)

if [ -z "$PIPELINE_ID" ] || [ "$PIPELINE_ID" = "null" ]; then
    echo "Pipeline not found in recent pipelines, searching older..."
    # Try with more pages - CircleCI keeps data for a while
    for page in $(seq 1 10); do
        PIPELINE_ID=$(curl -s "https://circleci.com/api/v2/project/$PROJECT/pipeline?branch=main&page-token=$page" | \
            jq -r --arg sha "$COMMIT_SHA" '.items[] | select(.vcs.revision | startswith($sha)) | .id' | head -1)
        if [ -n "$PIPELINE_ID" ] && [ "$PIPELINE_ID" != "null" ]; then
            break
        fi
    done
fi

if [ -z "$PIPELINE_ID" ] || [ "$PIPELINE_ID" = "null" ]; then
    echo "No pipeline found for commit $COMMIT_SHA"
    exit 1
fi

echo "Found pipeline: $PIPELINE_ID"

# Get workflow for this pipeline
WORKFLOW_ID=$(curl -s "https://circleci.com/api/v2/pipeline/$PIPELINE_ID/workflow" | \
    jq -r '.items[0].id')

echo "Workflow: $WORKFLOW_ID"

# Get jobs for this workflow
echo ""
echo "| Job | Duration | Status |"
echo "|-----|----------|--------|"

curl -s "https://circleci.com/api/v2/workflow/$WORKFLOW_ID/job" | \
    jq -r '.items[] |
        select(.name | test("test"; "i")) |
        "| \(.name) | \(if .started_at and .stopped_at then
            ((.stopped_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) -
             (.started_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) |
            "\(. / 60 | floor)m\(. % 60)s"
        else "N/A" end) | \(.status) |"'
