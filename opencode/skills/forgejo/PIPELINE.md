# CI/CD Pipeline Guide

## Pipeline Architecture (bfett project)

The project uses a multi-job pipeline (`.forgejo/workflows/pipeline.yml`):

| Stage | Job | Runs condition |
|-------|-----|----------------|
| **build** | `docker build -t bfett:${{ forgejo.sha }} .` | always |
| **test-bfett** | `test_package("bfett")` via tinytest | needs build |
| **test-bfett-app** | `test_package("bfett.app")` via tinytest | needs build |
| **push** | `docker push forgejo:3000/kgw-agent/bfett:${{ forgejo.sha }}` | needs test jobs + branch is `dev` or `main` |
| **deploy** | `docker run` with volume/port mounts + health checks | needs push + branch `dev` or `main` |

### Testing in CI

Tests are run inside the built image with:
```r
library(tinytest)
r <- test_package("bfett")
```
Exits with status 1 on any failure.

### Immutable Tags & Building

Avoid relying on mutable, floating tags (`latest`, `main`) which require forcing cache layer drops (`docker rmi -f`). Instead, build and tag with the immutable Git commit SHA:

```yaml
- name: Build
  run: docker build -t forgejo:3000/kgw-agent/bfett:${{ forgejo.sha }} .
```

### Container Registry Auth & Push

> **Important:** The auto-generated `$FORGEJO_TOKEN` has repository-level write access but **lacks `write:package` scope**.
> You must use a dedicated token with `write:package` scope stored as a secret (e.g., `REGISTRY_TOKEN`).

```yaml
- name: Login to container registry
  run: echo "${{ secrets.REGISTRY_TOKEN }}" | docker login forgejo:3000 -u <user> --password-stdin
  
- name: Push image
  run: docker push forgejo:3000/kgw-agent/bfett:${{ forgejo.sha }}
```

### Deployment & Health Checks

Containers started by deploy steps without `--network dev-network` land on the default bridge and are unreachable from the runner via `localhost:hostPort`. 

Do not use `docker exec` to test reachability from *inside* the container, as it will yield false positives. Test the endpoint from *outside* the target container on the network:

```yaml
# Run an ephemeral curl container on the same network to test reachability
docker run --network dev-network --rm curlimages/curl curl -sf http://bfett-${{ forgejo.sha }}:3838
```

## Manual Dispatch

The pipeline declares `on.workflow_dispatch`, so it can be triggered by hand:

```bash
fj --host http://forgejo:3000 actions dispatch pipeline.yml dev --repo kgw/bfett
```

`fj actions dispatch` takes the workflow **filename** as its first argument (e.g. `pipeline.yml`),
**not** the workflow's `name:` field (e.g. `Pipeline`). The value is passed verbatim as the
`workflowfilename` path parameter of `POST /api/v1/repos/{owner}/{repo}/actions/workflows/{workflowfilename}/dispatches`,
which matches the file under `.forgejo/workflows/`.

> **Gotcha:** on Forgejo 15.0.2 an unknown workflow file (or unknown ref) returns
> `500 Internal Server Error` with an empty body instead of `404 Not Found`
> (the error mapping is fixed upstream). Pass the correct filename to avoid the misleading 500.

A manual `workflow_dispatch` run skips the `test-transform` job, because that job is gated on
`forgejo.event_name == 'push'`.

## Forgejo Actions Guidelines

### Prefer Forgejo-native variables

**Always prefer `FORGEJO_*` / `forgejo.*` over `GITHUB_*` / `github.*` in new workflows.**

| Context expression | Env var | Purpose |
|---|---|---|
| `${{ forgejo.ref_name }}` | `$FORGEJO_REF_NAME` | Current branch or tag name |
| `${{ forgejo.repository }}` | `$FORGEJO_REPOSITORY` | `owner/repo` (e.g. `kgw-agent/bfett`) |
| `${{ forgejo.actor }}` | `$FORGEJO_ACTOR` | User who triggered the run |
| `${{ forgejo.sha }}` | `$FORGEJO_SHA` | Commit SHA that triggered the run |
| `${{ forgejo.server_url }}` | `$FORGEJO_SERVER_URL` | Forgejo instance URL |
| `${{ forgejo.workspace }}` | `$FORGEJO_WORKSPACE` | Default working directory on the runner |
| `${{ secrets.GITHUB_TOKEN }}` | `$FORGEJO_TOKEN` | Auto-generated auth token (masked in logs) |

