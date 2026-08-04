---
name: setup-repo
description: Bootstrap a repository for triage-driven agent work — the replacement for `/setup-matt-pocock-skills`. Use when a repo is missing `docs/agents/issue-tracker.md`, when the triage labels (`ready-for-agent`, `needs-triage`, `bug`, `enhancement`, `ready-for-human`, `wontfix`, `needs-info`) are absent, when a skill says to run `/setup-matt-pocock-skills`, or when the tracker or triage label vocabulary "should have been provided".
---

# Setup Repo

Set a repository up so triage, ticketing, and nightshift work can run on it. This is the local stand-in for the upstream `/setup-matt-pocock-skills` command: detect the issue tracker, ensure the triage labels exist, and write `docs/agents/issue-tracker.md` so the tracker-aware skills (`triage`, `to-spec`, `to-tickets`, `wayfinder`, `code-review`) can find the tracker and its label vocabulary.

This is v1 — deliberately narrow. Later versions may grow (CI config, branch protection, wayfinder map bootstrap, and so on). Keep additions scoped; do not let this skill become a grab-bag.

## 1. Detect the tracker

Derive the tracker from the repository's origin URL (`git remote get-url origin`):

- Host contains `github.com` → **GitHub tracker** — use the `gh` CLI.
- Host contains `forgejo` → **Forgejo tracker** — use the `fj` CLI; always pass `--host http://forgejo:3000` (it defaults to HTTPS and will fail with SSL errors).
- If the origin is neither, stop and report — the tracker is unknown.

Read the `forgejo` skill's `CONTRIBUTING.md` for Forgejo specifics (auth bootstrap, host flag, merge rights). GitHub auth runs through `GH_TOKEN`; the forgejo skill documents `fj auth add-key` with `$FORGEJO_TOKEN`.

## 2. Ensure the triage labels

The canonical seven-label set. On both trackers the label strings equal the canonical role names, so there is no mapping to look up:

| Role | Label | Color | Description |
|------|-------|-------|-------------|
| category | `bug` | `D73A4A` | Something is broken |
| category | `enhancement` | `A2EEEF` | New feature or improvement |
| state | `needs-triage` | `FBCA04` | Maintainer needs to evaluate |
| state | `needs-info` | `5319E7` | Waiting on reporter for more information |
| state | `ready-for-agent` | `0E8A16` | Fully specified, ready for an AFK agent |
| state | `ready-for-human` | `1D76DB` | Needs human implementation |
| state | `wontfix` | `FFFFFF` | Will not be actioned |

Create whatever is missing on the repo's tracker. Forgejo:

```bash
fj --host http://forgejo:3000 repo labels <owner>/<repo> create bug D73A4A -d "Something is broken"
# one per label; `fj --host http://forgejo:3000 repo labels <owner>/<repo> view` shows what exists
```

GitHub (use `--force` so color and description are normalized if a label already exists):

```bash
gh label create bug --color D73A4A --description "Something is broken" --force
# one per label; `gh label list` shows what exists
```

## 3. Write `docs/agents/issue-tracker.md`

If the file does not exist, create it from the template below, filling in the repo's actual tracker and CLI. This is the file the tracker-aware skills look for at runtime; it is a **repo artifact** — it belongs in the repo's working tree (committed when the repo's convention calls for it), not in a dev-container image.

```markdown
# Issue Tracker Configuration

## Tracker

<GitHub → `gh` | Forgejo → `fj`, with `--host http://forgejo:3000`>

This repo's issue tracker is derived from its origin URL. Detail on Forgejo
operations lives in the `forgejo` skill's `CONTRIBUTING.md`.

## Triage label vocabulary

Seven canonical labels; label strings equal the role names on both trackers.

- `bug` / `enhancement` — category roles
- `needs-triage` / `needs-info` — triage states
- `ready-for-agent` / `ready-for-human` — hand-off states
- `wontfix` — rejected

See the `setup-repo` skill for the full color/description table and bootstrap
commands.

## Issue and PR workflows

- View an issue: `gh issue view <n>` / `fj issue view <n>`
- List issues: `gh issue list` / `fj issue search`
- Comments: `gh issue view <n> --comments` / `fj issue view <n> comments`
- Post issue/PR bodies via the CLI — never hand-assembled curl JSON

## Wayfinding operations

- The map is a single issue labelled `wayfinder:map`.
- Map tickets are child issues of the map; a ticket's id is its identity.
- Blocking edges use the tracker's native blocking/sub-issue links.
- Frontier = open child tickets whose blockers are all resolved.
```

Do not overwrite the file if it already exists and matches the repo — it is owned by the repo, and local edits to it are intentional.
