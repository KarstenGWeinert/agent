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

## Fetching Workflow Logs via API

When building scripts to interact with the API, avoid masking errors and making brittle assumptions about job sequences.

```bash
#!/bin/bash
# Enable pipefail to prevent silent errors if the API request fails before jq/python
set -e -o pipefail

# Get the latest run ID
RUN_ID=$(curl -sf -H "Authorization: token $FORGEJO_TOKEN" "http://forgejo:3000/api/v1/repos/owner/repo/actions/runs?limit=1" | python3 -c "import sys,json; print(json.load(sys.stdin)['workflow_runs'][0]['id'])")

# Fetch job IDs explicitly instead of iterating blindly until 404
curl -sf -H "Authorization: token $FORGEJO_TOKEN" "http://forgejo:3000/api/v1/repos/owner/repo/actions/runs/$RUN_ID/jobs" > jobs.json

# (You can then parse jobs.json to fetch logs for the specific valid job IDs)
```

## Container Registry API

Forgejo provides an OCI-compatible container registry at `forgejo:3000`.

```bash
# Get a short-lived token (requires a user auth that has write:package scope)
TOKEN=$(curl -sf "http://forgejo:3000/v2/token?service=container_registry&scope=repository:owner/repo:pull,push" -u "username:$REGISTRY_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# List tags
curl -sf -H "Authorization: Bearer $TOKEN" "http://forgejo:3000/v2/owner/repo/tags/list"
```

