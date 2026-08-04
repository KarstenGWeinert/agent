---
name: nightshift
description: Work through every ready-for-agent ticket on the current repo unattended — sequential per-ticket subagent runs merged into a shared nightshift branch, CI on that branch at the end, and a merge request into main once green. Use when the maintainer wants a backlog of ready-for-agent tickets processed overnight without manual steps.
---

# Nightshift

Process the entire backlog of `ready-for-agent` tickets in the current repository, one after another, without manual intervention. Each ticket is implemented by a subagent on its own branch; a ticket is only integrated into the shared `nightshift` branch once it is solved. When the backlog is exhausted, run CI on `nightshift`, fix what breaks, and open a merge request into `main`.

A nightshift run is scoped to the repository it is invoked in. It never touches `main` directly — pushing to `main` is forbidden; the run ends with a merge request that a human merges.

## 1. Determine the tracker

Read the repository's origin URL (`git remote get-url origin`) to detect which issue tracker the repo lives on:

- Host contains `github.com` → **GitHub tracker** — use the `gh` CLI (`gh issue list`, `gh issue edit`, `gh pr create`, `gh workflow run`, `gh run watch`).
- Host contains `forgejo` → **Forgejo tracker** — use the `fj` CLI (`fj issue search`, `fj issue update`, `fj pr create`, `fj actions dispatch`). See the `forgejo` skill for the Forgejo-specific CLI conventions.

If the origin is neither, stop and report — the tracker is unknown.

## 2. Prepare the integration branch

Ensure the shared integration branch `nightshift` exists:

- If it does not exist, create it from the repo's default branch (`main`).
- If it exists, start from its current head — do not rebase or force-push it. A previous run's unfinished work stays on the branch.
- Never work directly on `nightshift`; it is only ever advanced by merging solved ticket work branches into it.

## 3. Discover the backlog

List all open tickets carrying the `ready-for-agent` label on the current repo:

- GitHub: `gh issue list --label ready-for-agent --state open`.
- Forgejo: `fj issue search` filtered to the same label.

Order the backlog by `createdAt` ascending — oldest first, first-in-first-out. Tickets are picked up in this order and never reordered by priority (no priority taxonomy exists on either tracker). Tickets the run itself relabels are picked up only on a later run.

## 4. Work each ticket sequentially

For each ticket, in order, exactly one at a time:

1. **Create a ticket work branch** from the current head of `nightshift`. Name it after the ticket, e.g. `nightshift/<number>`.
2. **Delegate the ticket to a subagent.** Give the subagent the ticket's full body, comments, and acceptance criteria. Its job: implement the change on the work branch. The ticket is considered **solved** only when **both** hold:
   - every acceptance criterion in the ticket is met, and
   - the repo's checks pass — run the repo's standard test/lint command (e.g. tinytest for R packages; `docker build` lint-style checks where the repo has no unit tests). If the ticket names a specific verification, use that.
3. **Solved → integrate.** Merge the work branch into `nightshift`. Relabel the ticket from `ready-for-agent` to `ready-for-human` (it is now in the integration branch awaiting the human's review of the final merge request).
4. **Failed → skip and report.** If the subagent cannot get the ticket solved (checks stay red, it is blocked, or it exceeds a reasonable effort), do not merge the work branch. Relabel the ticket from `ready-for-agent` to `needs-triage` — it goes back to the triage queue, and the run continues with the next ticket.

The ticket keeps the `ready-for-agent` label while it is being worked — there is no in-progress marker.

## 5. End-of-run CI

When the backlog is exhausted, run CI on the `nightshift` branch using the repo's own pipeline:

- **GitHub:** dispatch the repo's workflow on the `nightshift` ref, e.g. `gh workflow run build.yml --ref nightshift`, then poll with `gh run watch` / `gh run view --json status,conclusion`.
- **Forgejo:** `fj actions dispatch <pipeline>.yml nightshift --repo <owner>/<repo>` — note the dispatch takes the workflow *filename*, and inputs are passed as repeated `key=value` pairs, not JSON (see the vendored `forgejo` skill). Poll until the run concludes.

Wait for the run to finish. If CI fails, fix the problems in additional commits on `nightshift` (never via force-push) and re-run until the branch is green. A manual dispatch skips push-triggered jobs — treat the dispatch result as the signal that the branch is mergeable, and note any jobs the dispatch deliberately skipped.

## 6. Open the merge request into main

Once CI is green, open a merge request from `nightshift` into `main`:

- GitHub: `gh pr create --base main --head nightshift`.
- Forgejo: `fj pr create` with the same base/head.

The merge request body **must** reference every ticket resolved in this run with a closing keyword, e.g. `closes #<number>` on its own line per ticket, so the tracker links (and on GitHub auto-closes) each resolved ticket when a human merges.

The agent does **not** merge into `main` — `main` is protected. The run ends here and reports the merge request URL for the human to review and merge.

## 7. Final report

Report back to the caller:

- Tickets processed (solved and merged into `nightshift`, with ticket numbers)
- Tickets skipped (relabeled `needs-triage`, with ticket numbers and reason)
- CI outcome on `nightshift` and any fixes applied
- The merge request URL into `main` and which tickets it closes

## Constraints

- Never push to or merge into `main`. The run ends with a merge request; a human merges.
- Never work directly on `nightshift` — it only advances by merging solved ticket work branches.
- Never force-push or rebase the `nightshift` branch.
- A single failing ticket never aborts the run — skip it and continue.
- Every comment posted to the tracker during the run must start with the AI disclaimer `> *This was generated by AI during triage.*` (or the repo's established equivalent).
