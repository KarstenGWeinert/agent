---
name: log-sessions
description: Back up every not-yet-saved session of the current repository into the long-lived orphaned `session-logs` branch — one native `opencode export` JSON per session plus a `cost.csv` token/cost ledger — and print a cost summary in the chat. Idempotent: a session already recorded in `cost.csv` is skipped. Use when the maintainer invokes `/log-sessions`.
---

# Log Sessions

Export every opencode session of the current repository that has not yet been backed up, into the long-lived orphaned `session-logs` branch on `origin`, as one JSON file per session plus a `cost.csv` ledger, then print a token/cost summary in the chat.

`session-logs` is a log sink: an orphaned branch with no `main` parent, maintained in a git worktree placed **outside** the repo's own working tree (git forbids nested worktrees), committed to and pushed straight to `origin/session-logs`. It is never merged into `main` and is not a feature branch — the normal branch-via-PR rules in `AGENTS.md` do not apply to it.

The run is idempotent: a session whose id already appears in `cost.csv` is already backed up and is skipped. A session closed before a fresh `/new` is caught by the next `/log-sessions` invocation, because every invocation covers *all* sessions that are not yet recorded.

## 1. Identify the repository root

Determine the repo's root path and name:

- Repo root: `git rev-parse --show-toplevel`.
- Repo name (for the worktree path and optional stats check): `basename "$(git remote get-url origin)" .git`.

A session belongs to the current repo when its `directory` equals this root path.

## 2. Discover the repository's sessions

List all sessions and keep only those of the current repo:

```sh
opencode session list --format json
```

The output is a JSON array; each element has `id`, `title`, `created`, `updated`, `projectId`, and `directory`. Select the elements whose `directory` equals the repo root from step 1. Order them by `created` ascending (oldest first) — oldest sessions are backed up first.

## 3. Ensure the `session-logs` worktree (outside the repo)

The worktree must live **outside** the repo's own working tree — use e.g. `/tmp/session-logs-<repo>` (repo name from step 1, so different repos do not collide). Inspect the current state:

```sh
git worktree list
git ls-remote --heads origin session-logs
```

Then:

- **Worktree already exists and is attached to `session-logs`:** use it. Before appending, sync it with the remote truth so concurrent runs never fork history:
  ```sh
  git fetch origin session-logs
  git -C /tmp/session-logs-<repo> reset --hard origin/session-logs
  ```
- **Branch exists on origin but no worktree yet:** attach one tracking the branch:
  ```sh
  git worktree add --track -b session-logs /tmp/session-logs-<repo> origin/session-logs
  ```
  If a local `session-logs` branch already exists, attach the existing branch instead: `git worktree add /tmp/session-logs-<repo> session-logs`.
- **Branch exists nowhere (neither origin nor local):** create the orphaned branch from nothing — no `main` parent:
  ```sh
  git worktree add --orphan -b session-logs /tmp/session-logs-<repo>
  ```
  In the new worktree, commit a bare-bones first commit and publish the branch: write `cost.csv` containing exactly the header row below (and a `sessions/.gitkeep` if you want the directory tracked), `git add -A`, commit, then `git push -u origin session-logs`.

If `git worktree add` refuses because a `session-logs` branch already exists locally, fall back to `git worktree add /tmp/session-logs-<repo> session-logs` and continue. Never create the worktree inside the repo's own working tree.

## 4. Read the ledger of already-backed-up sessions

Read `cost.csv` from the worktree (step 3). It is the idempotency marker: the set of ids in its `session_id` column are already backed up and must be skipped. If the file is missing, treat the set as empty — the header is written on the first commit.

## 5. Export each new session

For every session found in step 2 whose id is **not** in the ledger set, in order:

1. Export the session with opencode's native exporter:
   ```sh
   opencode export <sessionID> > /tmp/session-logs-<repo>/sessions/<sessionID>.json
   ```
   The output is a JSON object with a top-level `messages` array and an `info` key carrying `id`, `title`, `directory`, `model` (object with `id` and `providerID`), `cost` (float), `tokens` (object with `input`, `output`, `reasoning`, and `cache` → `{read, write}`), and `time` (`{created, updated}` in ms epoch). Use exactly this data — no bespoke SQLite handling, no devcontainer mount, no cost recomputation.
2. Append exactly one row to `/tmp/session-logs-<repo>/cost.csv` with these columns in this exact order:
   ```csv
   timestamp, session_id, model, tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, cost
   ```
   - `timestamp`: the session's creation time as ISO-8601, derived from `info.time.created` (ms epoch).
   - `session_id`: `info.id` — this doubles as the "already backed up" marker.
   - `model`: `info.model.id`.
   - `tokens_input` / `tokens_output` / `tokens_reasoning`: `info.tokens.input` / `output` / `reasoning`.
   - `tokens_cache_read`: `info.tokens.cache.read`.
   - `cost`: `info.cost` (dollars).

Keep the values unquoted where they are plain integers/floats/ids; if a value could contain a comma, quote it with double quotes per CSV rules.

## 6. Commit and push to `origin/session-logs`

When all new sessions are exported:

```sh
git -C /tmp/session-logs-<repo> add sessions/ cost.csv
git -C /tmp/session-logs-<repo> commit -m "log-sessions: backup <n> session(s)"
git -C /tmp/session-logs-<repo> push origin session-logs
```

Push directly — `session-logs` is a log sink and never goes through a pull request, and it is never merged into `main`. If nothing new was exported (the ledger already contains every session of the repo), make no commit and report that the run was a no-op.

## 7. Print the token/cost summary in the chat

For the sessions exported in this run, print a per-session breakdown and totals, using the `info` figures captured in step 5:

- Per session: session id, model, input/output/reasoning/cache-read tokens, and cost.
- Totals across the run: number of sessions exported, total input, output, reasoning, and cache-read tokens, and total cost.

Optionally cross-check the totals with `opencode stats --project <repo-name>` (project name = repo name from step 1). If the run was a no-op, say so and state that every session of the current repo is already backed up.

## Constraints

- Never touch `main`; never merge `session-logs` into `main`. The branch is a log sink, pushed straight to `origin/session-logs`.
- Never re-export a session whose id is already in `cost.csv` — the run is idempotent.
- Data source is the native `opencode export` output. No bespoke SQLite reads, no devcontainer mount, no cost recomputation, no single-session export.
- The worktree must live outside the repo's own working tree (e.g. `/tmp/session-logs-<repo>`); never attach it inside the repo checkout.
- Never delete, rebase, or force-push the `session-logs` branch — it accumulates history and other invocations depend on it.
- Each exported session produces exactly one JSON file under `sessions/` and exactly one `cost.csv` row.
