# Session logs live in an orphaned `session-logs` branch, not in the container or a devcontainer mount

The container has no `devcontainer.json` (persistence runs through `agent.sh`/`docker run`), and this repo's git rules treat branches as either `main` or short-lived feature branches that merge via PR. Session logs would otherwise be lost on container teardown or invisible across clones.

We chose a long-lived **orphaned** branch `session-logs` in the repo, holding one JSON export per session (built from opencode's native `opencode export` data) plus a `cost.csv` ledger, and pushed straight to `origin/session-logs`. The branch is maintained in a git worktree placed **outside** the repo's own working tree (git forbids nested worktrees), so the main checkout stays untouched. Because session logs are plain git history, they survive container rebuilds, are visible to anyone who clones the repo, and need no devcontainer mount or extra volume.

We rejected a `.logs/`-folder-in-container approach (non-persistent, invisible to clones) and a `devcontainer.json` mount (the file does not exist in this repo). The `session-logs` branch deliberately deviates from the feature-branch-via-PR pattern in `AGENTS.md`: it is a log sink, never merged into `main`, and is pushed directly rather than through a pull request.
