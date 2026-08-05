# Agent Dev-Container Context

The `agent` Docker dev-container: a bundled toolchain (R, Python, DuckDB, Helix, opencode) plus vendored agent skills that the container's users invoke against GitHub and the local Forgejo instance.

## Language

**Session-Log**:
A per-session JSON export (conversation history plus token and cost figures) produced from opencode's own `opencode export` data. One file per session, written into the `session-logs` branch.
_Avoid_: transcript dump, log file

**`session-logs` branch**:
A long-lived orphaned branch in this repo that holds every session-log JSON and the `cost.csv` ledger. It is not a feature branch and does not merge into `main`; it is pushed straight to `origin/session-logs`.
_Avoid_: log branch, metrics branch, feature branch

**`cost.csv`**:
A CSV ledger, one row per exported session (timestamp, session id, model, input/output/reasoning/cache-read tokens, cost). Its session ids double as the "already backed up" marker that makes `log-sessions` idempotent.
_Avoid_: expense report, cost table

**Nightshift run**:
A single unattended pass over the current repository's entire `ready-for-agent` backlog, from invocation to a merge request into `main`.
_Avoid_: batch, night job, backlog processing

**Ready-for-agent ticket**:
An issue that has been fully triaged and specified, carrying the `ready-for-agent` label and ready for an AFK agent to implement.
_Avoid_: actionable issue, spec ticket

**Ticket work branch**:
The branch a subagent implements a single ticket on, cut from `nightshift` and named after the ticket.
_Avoid_: feature branch, ticket branch

**Integration branch** (`nightshift`):
The shared branch that all solved ticket work branches merge into; CI runs against it and it is the head of the merge request into `main`.
_Avoid_: working branch, night branch

**Subagent**:
The delegated agent that implements one ticket on its ticket work branch; it is responsible for solving the ticket, not for the run's overall flow.

**Solved ticket**:
A ticket whose acceptance criteria are all met and whose repo checks pass; a solved ticket is merged into `nightshift` and relabeled `ready-for-human`.

**Failed ticket**:
A ticket the subagent could not solve; it is not merged, relabeled back to `needs-triage`, and reported.

**Tracker**:
The issue tracker a repo lives on, derived from the repo's origin URL (`github.com` → GitHub/`gh`, `forgejo` host → Forgejo/`fj`).
_Avoid_: backend, system

**Triage label**:
One of the seven canonical issue-tracker labels — `bug`/`enhancement` (category) and `needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix` (state) — that triage assigns and nightshift consumes. Label strings equal the role names on both trackers.
_Avoid_: tag, milestone

**End-of-run CI**:
The repo's own pipeline, dispatched on the `nightshift` ref after the backlog is exhausted; a manual dispatch skips push-triggered jobs.

**Merge request**:
The PR/MR from `nightshift` into `main` that ends a run; its body closes each resolved ticket with a keyword like `closes #<number>`. A human merges it — agents never push to `main`.
_Avoid_: PR, pull request (use the tracker's own term: PR on GitHub, MR on Forgejo)
