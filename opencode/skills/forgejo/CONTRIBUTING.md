# Contributing Guide

## Local Forgejo Environment

- **Host:** `http://forgejo:3000` 
- **Git config:** `~/.gitconfig` has `gh` as credential helper for GitHub (not forgejo)

### Secure Git Cloning

Do not embed your token directly in the clone URL, as it will be saved in plaintext in your `.git/config` file. Instead, pass it securely via the `http.extraHeader` config:

```bash
git -c http.extraHeader="Authorization: Basic <base64-encoded-token>" clone http://forgejo:3000/{owner}/{repo}
```

## Git Workflow

- **Conventional commits:** `feat:`, `fix:`, `refactor:`, `doc:`, etc.
- **Push:** `git push -u origin <branch>`
- **PRs:** Use `fj pr create` (not `gh`)
- Git remote `origin` should point to `http://forgejo:3000/owner/repo`
- `fj` CLI can infer host/repo from the local git remote

### Merge rights (the agent does not merge)

`kgw-agent` has **no merge access** on `main`: `fj pr merge` fails with `405 Method Not Allowed` /
`User not allowed to merge PR`. Merges onto `main` are done by a human (user `nert`).

- Create the PR, but **do not merge it yourself**.
- After creating a PR: wait for human review/merge before continuing (e.g. wait for the pipeline deploy to run,
  only then re-dispatch the workflow).
- `fj pr status <nr>` shows who/when merged (e.g. `Merged by nert ...`).

## `fj` CLI (Forgejo CLI v0.6.0)

Before making any raw curl/API call, check if `fj` can do the job first. 

Always pass `--host http://forgejo:3000` (explicit `http://` — it defaults to HTTPS and will fail with SSL errors).

```bash
fj --host http://forgejo:3000 <command>
```

### Authentication

`fj auth login` opens a browser (not useful headless). Use `fj auth add-token` with the `$FORGEJO_TOKEN` instead:

```bash
echo "$FORGEJO_TOKEN" | fj auth add-token
```

Note: `add-key` is an alias for `add-token`, but any positional argument is treated as the *token value*,
overriding stdin. If you write `echo "$FORGEJO_TOKEN" | fj auth add-token kgw-agent`, the username
`kgw-agent` ends up stored as the token — not the value from stdin. Always pipe without a positional arg.

**First use in a fresh environment:** the first `fj` call prints `keys file not found, creating` and then
`401 Unauthorized` until a key is registered. Bootstrap once:

```bash
echo "$FORGEJO_TOKEN" | fj --host http://forgejo:3000 auth add-token
fj --host http://forgejo:3000 whoami   # => "currently signed in to kgw-agent@forgejo:3000"
```

### Common workflows

| Task | Command |
|------|---------|
| View repo | `fj repo view owner/repo` |
| Clone repo | `fj repo clone owner/repo [path]` |
| Create PR | `fj pr create --base <BASE> --head <HEAD> [TITLE] --body "..."` — title is positional, no `--title` flag |
| Merge PR | `fj pr merge <number>` (humans only — the agent lacks merge access) |
| View PR | `fj pr view <number>` |
| List issues | `fj issue search` |
| Create issue | `fj issue create [TITLE] --body "..."` — title is positional, no `--title` flag |
| View repo labels | `fj repo labels <owner>/<repo> view` |
| Add label to issue | `fj issue edit <number> labels --add <label>` |
| Remove label from issue | `fj issue edit <number> labels --rm <label>` |
| List releases | `fj release list` |
| Create release | `fj release create --tag <tag> --title "..."` |
| List tags | `fj tag list` |
| Create tag | `fj tag create <name> <ref>` |
| Dispatch workflow | `fj actions dispatch pipeline.yml <branch>` |

### Issue labels

`fj issue create` **cannot** set labels — labels are added *after* creation:

- Add: `fj issue edit <number> labels --add <label>`
- Remove: `fj issue edit <number> labels --rm <label>`
- List labels: `fj issue view <number>` shows the labels on an issue; `fj repo labels <owner>/<repo> view` shows the repo's full set
- Manage label definitions: `fj repo labels <repo> create <name> <color> -d "<desc>"` (also `edit`, `delete`)

Labels are matched by **name**. The canonical triage set (`ready-for-agent`, `needs-triage`, `bug`,
`enhancement`, `refactor`, `ready-for-human`, `wontfix`, `needs-info`) is defined by the `setup-repo`
skill — see that skill for the full vocabulary.

### Issue and PR body hygiene

Always create issues and PRs through the CLI — `fj issue create`, `fj pr create` — and never hand-assemble JSON payloads with `curl` for create/edit operations (adding comments via curl is the one exception; see the curl cookbook below). The CLI builds the payload itself; hand-built curl payloads are how escaping/encoding artefacts sneak into bodies (e.g. `invalid character '`' in string escape code`). Raw `curl` is reserved for the infrastructure-only cases in `INFRASTRUCTURE.md` (runner registration, registry tokens, actions logs) and the documented fallback workflows below.

### Gotchas

- **`--body` vs `--body-file`:** `--body` breaks on shell-special characters (backticks, parentheses, umlauts). For bodies with special characters, write the body to a temp file and pass `--body-file <file>`.
- **`-R` / `--cwd`:** `-R, --remote <REMOTE>` is a *local git remote name*, not a repo path. Running e.g. `fj -R kgw/bfett ...` outside a repo directory fails with `no repo info`. Either pass `--cwd` or run inside the repo directory.
- **Labels:** `fj issue create` has no `--labels` option — labels cannot be set at creation. See the "Issue labels" section above for the full workflow.
- **Issue comments:** `fj issue view <id>` does **not** show comments by default. Use subcommands: `fj issue view <id> comments` (list comments), `fj issue view <id> comment` / `fj issue view <id> body` (show individual comment/body), `fj issue view <id> assignees`. The `fj` CLI has no subcommand to *create* a comment — use the curl fallback below for that.

### Curl fallback cookbook

**Use `fj` whenever possible.** The curl patterns below are a fallback for when `fj auth add-token` is broken (401 errors), for reading comments (`fj issue view` hides them by default), or for adding comments (no `fj` subcommand exists yet).

Replace `{owner}/{repo}` with the actual values (e.g. `kgw-agent/bfett`).

**View an issue:**
```bash
curl -H "Authorization: token $FORGEJO_TOKEN" \
  "http://forgejo:3000/api/v1/repos/{owner}/{repo}/issues/{id}"
```

**View issue comments:**
```bash
curl -H "Authorization: token $FORGEJO_TOKEN" \
  "http://forgejo:3000/api/v1/repos/{owner}/{repo}/issues/{id}/comments"
```

**Add a comment:**
```bash
curl -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body":"comment text"}' \
  "http://forgejo:3000/api/v1/repos/{owner}/{repo}/issues/{id}/comments"
```

**Update labels:**
```bash
curl -X PUT \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"labels":[1,2]}' \
  "http://forgejo:3000/api/v1/repos/{owner}/{repo}/issues/{id}/labels"
```

**Create an issue:**
```bash
curl -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Title","body":"Body"}' \
  "http://forgejo:3000/api/v1/repos/{owner}/{repo}/issues"
```

**Body-escaping note:** For complex bodies (backticks, parentheses, umlauts, newlines), inline `-d` with single-quoted JSON will break. Use `--data-raw` with a heredoc, or write the body to a file and pass `-d @<file>`:
```bash
curl -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  --data-raw @- "http://forgejo:3000/api/v1/repos/{owner}/{repo}/issues" <<'EOF'
{"title":"Title","body":"Complex body with `backticks` and (parens)"}
EOF
```


