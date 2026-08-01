# CI/CD Pipeline Guide

## Pipeline Architecture

The project uses a multi-job pipeline (`.forgejo/workflows/pipeline.yml`):

| Stage | Job | Runs condition |
|-------|-----|----------------|
| **build** | `docker build -t <image>:${{ forgejo.sha }} .` | always |
| **test** | `test_package("<name>")` via tinytest | needs build |
| **test-app** | `test_package("<name>.app")` via tinytest | needs build |
| **push** | `docker push forgejo:3000/<owner>/<repo>:${{ forgejo.sha }}` | needs test jobs + branch is `dev` or `main` |
| **deploy** | `docker run` with volume/port mounts + health checks | needs push + branch `dev` or `main` |

### Testing in CI

Tests are run inside the built image with:
```r
library(tinytest)
r <- test_package("<name>")
```
Exits with status 1 on any failure.

### Immutable Tags & Building

Avoid relying on mutable, floating tags (`latest`, `main`) which require forcing cache layer drops (`docker rmi -f`). Instead, build and tag with the immutable Git commit SHA:

```yaml
- name: Build
  run: docker build -t forgejo:3000/<owner>/<repo>:${{ forgejo.sha }} .
```

### Container Registry Auth & Push

> **Important:** The auto-generated `$FORGEJO_TOKEN` has repository-level write access but **lacks `write:package` scope**.
> You must use a dedicated token with `write:package` scope stored as a secret (e.g., `REGISTRY_TOKEN`).

```yaml
- name: Login to container registry
  run: echo "${{ secrets.REGISTRY_TOKEN }}" | docker login forgejo:3000 -u <user> --password-stdin
  
- name: Push image
  run: docker push forgejo:3000/<owner>/<repo>:${{ forgejo.sha }}
```

### Deployment & Health Checks

Containers started by deploy steps without `--network dev-network` land on the default bridge and are unreachable from the runner via `localhost:hostPort`. 

Do not use `docker exec` to test reachability from *inside* the container, as it will yield false positives. Test the endpoint from *outside* the target container on the network:

```yaml
# Run an ephemeral curl container on the same network to test reachability
docker run --network dev-network --rm curlimages/curl curl -sf http://<service>-${{ forgejo.sha }}:3838
```

## Forgejo Actions Guidelines

### Prefer Forgejo-native variables

**Always prefer `FORGEJO_*` / `forgejo.*` over `GITHUB_*` / `github.*` in new workflows.**

| Context expression | Env var | Purpose |
|---|---|---|
| `${{ forgejo.ref_name }}` | `$FORGEJO_REF_NAME` | Current branch or tag name |
| `${{ forgejo.repository }}` | `$FORGEJO_REPOSITORY` | `owner/repo` |
| `${{ forgejo.actor }}` | `$FORGEJO_ACTOR` | User who triggered the run |
| `${{ forgejo.sha }}` | `$FORGEJO_SHA` | Commit SHA that triggered the run |
| `${{ forgejo.server_url }}` | `$FORGEJO_SERVER_URL` | Forgejo instance URL |
| `${{ forgejo.workspace }}` | `$FORGEJO_WORKSPACE` | Default working directory on the runner |
| `${{ secrets.GITHUB_TOKEN }}` | `$FORGEJO_TOKEN` | Auto-generated auth token (masked in logs) |

