# AGENTS.md

Operating instructions for AI agents working in this repository.

## 1. Repository context

- This repo is the `agent` Docker dev-container, hosted on **GitHub**: `KarstenGWeinert/agent`.
- Pull requests go through `gh pr create` — **not** the Forgejo `fj` CLI.
- The `forgejo` skill / `PIPELINE.md` describe the separate `bfett` project on the local Forgejo instance (`http://forgejo:3000`). Do not confuse that workflow with this repo; this repo has no Forgejo pipeline.

## 2. Git rules (critical)

- **Never push to `main`.** It is protected; pushes are rejected. `main` changes only via merged PRs (the human merges).
- Always: feature branch → push → open PR against `main`.
- Conventional commits (`feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, `chore:`) matching repo history.
- Descriptive branch names with prefixes: `fix/`, `docs/`, `ci/`, `rework/`, `chore/`.

## 3. Tokens & auth

- GitHub auth runs through `GH_TOKEN`, provided via `~/.ssh/environment` (injected by sshd on SSH login). It is **not** present in the session environment by default.
- Never echo the token, and never embed it in URLs, commits, or `.git/config`.
- Set `GH_TOKEN` **inline per command** (the environment does not persist between tool calls). If no token is available, ask the user how to authenticate — do not assume a file path.
- Plumbing: `agent.sh` forwards `GITHUB_TOKEN_AGENT`, `GITHUB_TOKEN_NERT`, `FORGEJO_TOKEN` into the container; the entrypoint writes `GH_TOKEN` + `FORGEJO_TOKEN` into each user's `~/.ssh/environment`.

## 4. Build / correction cycle (the intended workflow)

- `.github/workflows/build.yml` builds the Docker image. It is triggered **only manually** via `workflow_dispatch`, and the workflow must exist on `main` to be triggerable.
- The build is **feedback only**: no image is produced or stored on GitHub (cache-only output), and nothing needs to be cleaned up afterwards.
- Loop for Dockerfile work:
  1. Push changes to a feature branch.
  2. `gh workflow run build.yml --ref <branch>`
  3. Poll: `gh run watch` / `gh run view <id> --json status,conclusion`
  4. On failure, read the logs: `gh run view <id> --log-failed`, or download the `docker-build-log` artifact — and **grep** for the relevant error (logs are huge; do not dump them wholesale).
  5. Fix, commit, push, re-run until the build is green.
  6. Open a PR for the fix.
- No agent runs inside CI; corrections happen in this session.

## 5. Dockerfile / build notes

- The image is heavy (R, Python 3.14, Rust/Tokei, Helix, DuckDB, opencode) — a build takes roughly 20–40 minutes. The GHA cache (`type=gha`) persists between runs and makes re-runs faster.
- A line-continuation backslash must be the last character on the line. Historically, stray editor text after a `\` (e.g. `36% used`) broke the Dockerfile parse; keep lines clean.
- The mattpocock engineering skills are cloned from upstream at build time; the `forgejo` skill is vendored under `opencode/skills/forgejo`.
- `.dockerignore` excludes `*.md` (so `README.md`/`AGENTS.md` are not in the Docker build context).
