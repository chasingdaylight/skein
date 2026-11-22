#!/usr/bin/env bash
# land.sh ISSUE LABEL "COMMIT" "PR TITLE" BODY_FILE close|keep PATH...
# Lands a change of an agent's on dev: the checks, a commit of the PATHs
# named (never everything: emanspeaks works in this tree too) on the current
# branch (not dev or main), a pull request into dev with the label, its
# merge, and the issue closed (close) or commented on (keep). Run from a
# branch made for the change; the app's wrappers are outside the repository
# (see CLAUDE.md).
set -euo pipefail
issue=$1 label=$2 message=$3 title=$4 body=$5 close=$6
shift 6
body="$(cd "$(dirname "$body")" && pwd)/$(basename "$body")"
cd "$(dirname "$0")/../.."
export GH_TOKEN="$(bash /c/scratch/github-apps/app-token.sh chasingdaylight)"
Z=${ZIG:-zig}
branch=$(git branch --show-current)
[ "$branch" != dev ] && [ "$branch" != main ] || { echo "land.sh: on $branch; make a branch for the change first"; exit 1; }

"$Z" fmt --check build build.zig src templates tools
"$Z" build
"$Z" build test
./zig-out/bin/skein check
npx --no-install markdownlint-cli2 "**/*.md" 2>&1 | tail -1
npx --no-install cspell --no-progress "**/*.md" ".github/**" "src/**" "build/**" "templates/**" "tools/**" 2>&1 | tail -1

git add -- "$@"
git status --short
bash /c/scratch/github-apps/app-git.sh chasingdaylight commit -q -m "$message" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
bash /c/scratch/github-apps/app-git.sh chasingdaylight push -q -u origin "$branch" 2>&1 | tail -1 || true
url=$(gh pr create --base dev --head "$branch" --title "$title" --body-file "$body" --label "$label" < /dev/null | tail -1)
echo "$url"
gh pr merge "$url" --merge < /dev/null 2>&1 | tail -1
git switch -q dev
bash /c/scratch/github-apps/app-git.sh chasingdaylight pull -q --ff-only
git branch -D "$branch" | tail -1
git fetch -q --prune
if [ "$close" = close ]; then
  gh issue close "$issue" --comment "Landed on dev with #${url##*/}. _Posted by Claude at the request of emanspeaks._" < /dev/null | tail -1
else
  gh issue comment "$issue" --body "Part of this landed on dev with #${url##*/}. _Posted by Claude at the request of emanspeaks._" < /dev/null | tail -1
fi
git log --oneline -1
