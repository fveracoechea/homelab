# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

Exception: the baby-shower app's tickets and wayfinder map live on `fveracoechea/baby-shower` (the app repo). The wayfinding operations below apply there too — substitute the repo name.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## Wayfinding operations

How this repo expresses wayfinder maps, tickets, blocking, and frontier queries on GitHub.

- **Map**: an issue labelled `wayfinder:map`. **Tickets**: child issues of the map, each labelled `wayfinder:research` / `wayfinder:prototype` / `wayfinder:grilling` / `wayfinder:task`.
- **Parent/child**: GitHub native sub-issues via GraphQL — `gh api graphql -f query='mutation { addSubIssue(input: {issueId: "<map node id>", subIssueId: "<child node id>"}) { subIssue { number } } }'`. Node ids come from `gh api graphql -f query='query { repository(owner:"fveracoechea", name:"homelab") { issues(first:20) { nodes { number id databaseId } } } }'`.
- **Blocking**: GitHub native issue dependencies via REST — `gh api -X POST repos/fveracoechea/homelab/issues/<blocked number>/dependencies/blocked_by -F issue_id=<blocker databaseId>` (integer `databaseId`, not the issue number). Renders as "Blocked by" in the GitHub UI.
- **Frontier query** (open, unblocked, unclaimed children of map `<n>`): list the map's sub-issues via GraphQL `issue(number:<n>) { subIssues(first:50) { nodes { number state assignees(first:1) { nodes { login } } blockedBy(first:10) { nodes { number state } } } } }` and keep nodes that are OPEN, have no assignees, and whose `blockedBy` nodes are all CLOSED.
- **Claim a ticket**: `gh issue edit <number> --add-assignee fveracoechea` — an open, unassigned ticket is unclaimed.
- **Resolve a ticket**: `gh issue comment <number> --body "<resolution>"`, then `gh issue close <number>`, then append one line (ticket name as link + one-line gist) to the map body's **Decisions so far** via `gh issue edit <map number> --body-file ...`.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
