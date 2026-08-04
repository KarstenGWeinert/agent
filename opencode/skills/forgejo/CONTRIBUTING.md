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

`fj auth login` opens a browser (not useful headless). Use `fj auth add-key` with the `$FORGEJO_TOKEN` instead:

```bash
cd /repo && echo "$FORGEJO_TOKEN" | fj auth add-key <user>
```

**First use in a fresh environment:** the first `fj` call prints `keys file not found, creating` and then
`401 Unauthorized` until a key is registered. Bootstrap once:

```bash
echo "$FORGEJO_TOKEN" | fj --host http://forgejo:3000 auth add-key kgw-agent
fj --host http://forgejo:3000 whoami   # => "currently signed in to kgw-agent@forgejo:3000"
```

### Common workflows

| Task | Command |
|------|---------|
| View repo | `fj repo view owner/repo` |
| Clone repo | `fj repo clone owner/repo [path]` |
| Create PR | `fj pr create --title "..." --body "..."` |
| Merge PR | `fj pr merge <number>` (humans only — the agent lacks merge access) |
| View PR | `fj pr view <number>` |
| List issues | `fj issue search` |
| Create issue | `fj issue create --title "..." --body "..."` |
| List releases | `fj release list` |
| Create release | `fj release create --tag <tag> --title "..."` |
| List tags | `fj tag list` |
| Create tag | `fj tag create <name> <ref>` |
| Dispatch workflow | `fj actions dispatch pipeline.yml <branch>` |

### Issue and PR body hygiene

Always create issues and PRs through the CLI — `fj issue create`, `fj pr create` — and never hand-assemble JSON payloads with `curl` for create/edit operations. The CLI builds the payload itself; hand-built curl payloads are how escaping/encoding artefacts sneak into bodies (e.g. `invalid character '`' in string escape code`). Raw `curl` is reserved for the infrastructure-only cases in `INFRASTRUCTURE.md` (runner registration, registry tokens, actions logs).


