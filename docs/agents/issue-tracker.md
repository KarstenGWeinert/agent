# Issue Tracker Configuration

## Tracker

This repo (`KarstenGWeinert/agent`) lives on GitHub; operate it with `gh`. GitHub auth runs through `GH_TOKEN`, injected into `~/.ssh/environment` on SSH login — see `AGENTS.md`. The container also targets the local Forgejo instance (`http://forgejo:3000`) for other projects; that workflow is documented in the `forgejo` skill's `CONTRIBUTING.md`.

## Triage label vocabulary

Seven canonical labels; label strings equal the role names on both trackers.

- `bug` / `enhancement` — category roles
- `needs-triage` / `needs-info` — triage states
- `ready-for-agent` / `ready-for-human` — hand-off states
- `wontfix` — rejected

See the `setup-repo` skill for the full color/description table and bootstrap commands.

## Issue and PR workflows

- View an issue: `gh issue view <n>`
- List issues: `gh issue list`
- Comments: `gh issue view <n> --comments`
- View a PR: `gh pr view <n>`
- Post issue/PR bodies via the CLI — never hand-assembled curl JSON

## Wayfinding operations

- The map is a single issue labelled `wayfinder:map`.
- Map tickets are child issues of the map; a ticket's id is its identity.
- Blocking edges use the tracker's native blocking/sub-issue links.
- Frontier = open child tickets whose blockers are all resolved.
