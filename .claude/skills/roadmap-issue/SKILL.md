---
name: roadmap-issue
description: File skein issues at their place in the skein Roadmap project, keep its Rank in order, set whose action is next, and read the board to find the next item. Use when filing issues, after reordering, or when choosing what to work next.
---

# Issues and the Roadmap

The order of all work is the GitHub Project "Skein Roadmap" (chasingdaylight, project 1): the first row that is not done is next.

- **The board:** `bash tools/agent/board.sh` lists the rows not done, in order, with their status and next action.
- **Filing:** write the body to a file, ending with `_Filed by Claude at the request of emanspeaks._`, then `bash tools/agent/file-issue.sh "Title" BODY_FILE "MILESTONE" AFTER_NUMBER [BLOCKER...]`. It files the issue as the app with the labels `feature` and `agent`, puts it after the row of `AFTER_NUMBER`, sets "Next action: agent", and records blocked-by links. Use the milestone of the issue it follows. For other labels (`housekeeping`, `backlog`), `gh issue edit N --add-label`.
- **Rank:** after a batch of filings or moves, run `bash tools/agent/rank.sh` once; it renumbers only the rows whose Rank is wrong, 15 to a request.
- **Whose action is next:** emanspeaks is the assignee only when he must answer or do something an agent cannot; then the label `agent` comes off and "Next action" is his. When he has answered everything on an issue, unassign him, add `agent`, and set "Next action: agent" (`next-action.sh` in the cesium workspace's `roadmap-project` skill does it for the whole project). A design question for him is labeled `question` and assigned to him, with the options laid out and no recommendation unless one is obvious.
- **Rate limits:** if the app's GraphQL quota runs out, emanspeaks has allowed his own `gh` sign-in for board edits (not for issues or pull requests).

Never write emanspeaks's first name; `@emanspeaks` only to ask for his input.
