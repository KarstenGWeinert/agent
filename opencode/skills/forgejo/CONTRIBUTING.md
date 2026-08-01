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

## `fj` CLI (Forgejo CLI v0.5.0)

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

### Common workflows

| Task | Command |
|------|---------|
| View repo | `fj repo view owner/repo` |
| Clone repo | `fj repo clone owner/repo [path]` |
| Create PR | `fj pr create --title "..." --body "..."` |
| Merge PR | `fj pr merge <number>` |
| View PR | `fj pr view <number>` |
| List issues | `fj issue search` |
| Create issue | `fj issue create --title "..." --body "..."` |
| List releases | `fj release list` |
| Create release | `fj release create --tag <tag> --title "..."` |
| List tags | `fj tag list` |
| Create tag | `fj tag create <name> <ref>` |
| Dispatch workflow | `fj actions dispatch pipeline.yml <branch>` |


