# Infrastructure & Platform

## Host Configuration

- **Host:** `http://forgejo:3000`
- **Host resolution:** `forgejo` resolves via Docker DNS, not `/etc/hosts`
- **Network Isolation:** The CI runner container runs on `dev-network` (custom Docker bridge), not `--network host`.

> **Security Note:** Authentication tokens and repository contents are currently transmitted in plaintext over HTTP. Consider configuring TLS termination on the local Forgejo instance (via Caddy, Traefik, or Nginx) and enforcing `https://` to secure credentials across the network.

## Runner Management

```bash
# List runners registered for a repo
curl -sf -H "Authorization: token $FORGEJO_TOKEN" "http://forgejo:3000/api/v1/repos/owner/repo/actions/runners"

# Get a runner registration token
curl -sf -H "Authorization: token $FORGEJO_TOKEN" "http://forgejo:3000/api/v1/repos/owner/repo/actions/runners/registration-token"
```

Runners can be registered at repo, org, or instance level. Repo-level runners appear in the endpoint above; instance-level runners require `read:admin` scope.

### `fj` CLI Actions Management

| Task | Command |
|------|---------|
| Actions tasks | `fj actions tasks` |
| Actions secrets | `fj actions secrets list/create/delete` |
| Actions variables | `fj actions variables list/create/delete` |
| Dispatch workflow | `fj actions dispatch <filename> <ref>` |

> `actions dispatch` takes the workflow **filename** (e.g. `pipeline.yml`), not the workflow's
> `name:` (e.g. `Pipeline`). A wrong value returns `500` with an empty message on Forgejo 16.0.2
> (should be `404`; still not fixed).

## Fetching Workflow Logs

On Forgejo 16.0.2 the REST API exposes Actions logs and jobs (they were absent on 15.0.2):
`GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs` lists the jobs of a run,
`GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs` returns a single job's plaintext log, and
`GET /repos/{owner}/{repo}/actions/runs/{run_id}/logs` streams a zip of every job's logs in a run.
`fj actions` has no logs subcommand (only `tasks`, `variables`, `secrets`, `dispatch`) — use curl.

```bash
# Run list (newest first):
fj --host http://forgejo:3000 actions tasks --repo kgw/bfett

# Job list of a run (get the run_id from the tasks output):
curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
  "http://forgejo:3000/api/v1/repos/<owner>/<repo>/actions/runs/<run_id>/jobs"

# Plaintext log of a single job:
curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
  "http://forgejo:3000/api/v1/repos/<owner>/<repo>/actions/jobs/<job_id>/logs"

# Zip of all job logs in a run:
curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
  "http://forgejo:3000/api/v1/repos/<owner>/<repo>/actions/runs/<run_id>/logs" -o run-logs.zip
```

The Web-UI route (`/actions/runs/<run_id>/jobs/<job_id>/attempt/<attempt>/logs`) still works with
Basic-Auth (username + `$FORGEJO_TOKEN`) as a fallback; the API-token header alone is not accepted there.

## Container Registry API

Forgejo provides an OCI-compatible container registry at `forgejo:3000`.

```bash
# Get a short-lived token (requires a user auth that has write:package scope)
TOKEN=$(curl -sf "http://forgejo:3000/v2/token?service=container_registry&scope=repository:owner/repo:pull,push" -u "username:$REGISTRY_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# List tags
curl -sf -H "Authorization: Bearer $TOKEN" "http://forgejo:3000/v2/owner/repo/tags/list"
```

