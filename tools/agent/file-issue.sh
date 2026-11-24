#!/usr/bin/env bash
# file-issue.sh TITLE BODY_FILE MILESTONE AFTER_NUMBER [BLOCKER...]
# Files a skein issue as the app, with the labels feature and agent, puts it
# in the Roadmap after the row of AFTER_NUMBER with "Next action: agent",
# and records its blockers. Prints the number. After a batch, run rank.sh
# once rather than renumbering after each issue.
set -euo pipefail
title=$1 body=$2 milestone=$3 after=$4
shift 4
export GH_TOKEN="${GH_TOKEN:-$(bash /c/scratch/github-apps/app-token.sh chasingdaylight)}"
R=chasingdaylight/skein

url=$(gh issue create --repo "$R" --title "$title" --label feature --label agent --milestone "$milestone" --body-file "$body" < /dev/null | tail -1)
number=${url##*/}
for blocker in "$@"; do
  id=$(gh api "repos/$R/issues/$blocker" --jq .id < /dev/null)
  gh api -X POST "repos/$R/issues/$number/dependencies/blocked_by" -F "issue_id=$id" < /dev/null > /dev/null
done

project=$(gh project view 1 --owner chasingdaylight --format json --jq .id < /dev/null)
item=$(gh project item-add 1 --owner chasingdaylight --url "$url" --format json --jq .id < /dev/null)
after_item=$(gh project item-list 1 --owner chasingdaylight --limit 200 --format json --jq ".items[] | select(.content.number == $after) | .id" < /dev/null)
gh api graphql -f query='mutation($p: ID!, $i: ID!, $a: ID!) { updateProjectV2ItemPosition(input: {projectId: $p, itemId: $i, afterId: $a}) { clientMutationId } }' -f p="$project" -f i="$item" -f a="$after_item" < /dev/null > /dev/null

field() { gh project field-list 1 --owner chasingdaylight --format json --jq "$1" < /dev/null; }
next=$(field '.fields[] | select(.name == "Next action") | .id')
agent=$(field '.fields[] | select(.name == "Next action") | .options[] | select(.name == "agent") | .id')
gh project item-edit --id "$item" --project-id "$project" --field-id "$next" --single-select-option-id "$agent" < /dev/null > /dev/null
echo "$number"
