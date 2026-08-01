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
> `name:` (e.g. `Pipeline`). On Forgejo 15.0.2 a wrong value returns `500` with an empty message
> (should be `404`; fixed upstream).

## Fetching Workflow Logs

On Forgejo 15.0.2 there is **no API route** for job logs: `/api/v1/repos/{owner}/{repo}/actions/runs/{run_id}/jobs`
returns `404 page not found` (Swagger lists under `/actions/` only `runners`, `runs`, `runs/{run_id}`, `secrets`,
`tasks`, `variables`, `workflows/.../dispatches`), and the run-detail endpoint carries no job/log data.
`fj actions` has no logs subcommand (only `tasks`, `variables`, `secrets`, `dispatch`).

Working path: list runs via `fj`, then fetch the log through the Web-UI route with Basic-Auth
(API-token header alone is not accepted on Web-UI routes).

```bash
# Run list (newest first):
fj --host http://forgejo:3000 actions tasks --repo kgw/bfett

# Logs of a job. Determine job_id: the run page
#   http://forgejo:3000/<owner>/<repo>/actions/runs/<run_id>
# redirects (307) to /jobs/<job_id>/attempt/<attempt>
curl -s -u "kgw-agent:$FORGEJO_TOKEN" \
  "http://forgejo:3000/<owner>/<repo>/actions/runs/<run_id>/jobs/<job_id>/attempt/<attempt>/logs"
```

> **Forgejo ≥ v16.0.0** adds proper REST log endpoints (PR #12666): `GET /repos/{owner}/{repo}/actions/runs/{run_id}/logs`
> streams a zip of all job logs in a run, `GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs` returns a single job's
> plaintext log. Prefer those after an upgrade. A job-listing endpoint (`/actions/runs/{run_id}/jobs`) is not yet
> available upstream (issue #13076).

## Container Registry API

Forgejo provides an OCI-compatible container registry at `forgejo:3000`.

```bash
# Get a short-lived token (requires a user auth that has write:package scope)
TOKEN=$(curl -sf "http://forgejo:3000/v2/token?service=container_registry&scope=repository:owner/repo:pull,push" -u "username:$REGISTRY_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# List tags
curl -sf -H "Authorization: Bearer $TOKEN" "http://forgejo:3000/v2/owner/repo/tags/list"
```

