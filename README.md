<p align="center"><a href="https://flowexec.io"><img src="https://flowexec.io/_media/logo.png" alt="flow" width="200"/></a></p>

<br>

<p align="center">
    <a href="https://github.com/flowexec/action/releases"><img src="https://img.shields.io/github/v/release/flowexec/action" alt="GitHub release"></a>
    <a href="https://github.com/marketplace/actions/flow-execute"><img src="https://img.shields.io/badge/marketplace-flow--execute-blue?logo=github" alt="Go Reference"></a>
</p>

Execute [flow](https://github.com/flowexec/flow) workflows in your GitHub Actions.

## Quick Start

```yaml
- uses: flowexec/action@v1
  with:
    executable: 'build app'
```

Check out the [flow CI workflow](https://github.com/flowexec/flow/blob/main/.github/workflows/ci.yaml) for examples of how this can be used.

## Inputs

### Required

- `executable` - flow executable ID (VERB NAME) to run (e.g., "validate", "build app", "test unit", "deploy staging")

### Optional

| Input | Description | Default |
|-------|-------------|---------|
| `workspace` | Workspace to use (path or name) | `.` |
| `workspace-name` | Name for the workspace (auto-generated if not provided) | |
| `workspaces` | YAML/JSON map of workspaces (supports local paths and git repositories) | |
| `clone-token` | GitHub token for cloning private repositories | |
| `clone-depth` | Git clone depth for repository cloning | `1` |
| `checkout-path` | Base directory for cloning repositories | `.flow-workspaces` |
| `flow-version` | Version of flow CLI to install | `latest` |
| `params` | Parameters to pass to the executable (`KEY=VALUE` pairs, one per line or comma-separated) | |
| `env` | Environment variables to set during execution (`KEY=VALUE` pairs, one per line) | |
| `secrets` | Secrets to set in flow vault (`KEY=VALUE` pairs, one per line; JSON also accepted) | |
| `vault-key` | Vault encryption key (for existing vaults) | |
| `sync-git` | Pull latest changes for all git-sourced workspaces before syncing | `false` |
| `working-directory` | Directory to run flow from | `.` |
| `timeout` | Timeout for executable execution | `30m` |
| `continue-on-error` | Continue workflow if flow executable fails | `false` |
| `upload` | Upload flow logs as an artifact on failure | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `exit-code` | Exit code of the flow executable |
| `output` | Captured output from the flow executable (when `upload: true`) |
| `vault-key` | Generated vault encryption key (when secrets are configured without a provided key) |
| `error-code` | Machine-readable error code on failure (e.g., `EXECUTION_FAILED`, `TIMEOUT`, `NOT_FOUND`) |

## Examples

### Basic Usage

```yaml
name: Build and Test
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build application
        uses: flowexec/action@v1
        with:
          executable: 'build app'

      - name: Run tests
        uses: flowexec/action@v1
        with:
          executable: 'test unit'
```

### Passing Parameters

```yaml
- name: Run tests with CI mode
  uses: flowexec/action@v1
  with:
    executable: 'test unit'
    params: |
      CI=true
      COVERAGE=true
```

Parameters are passed as `--param KEY=VALUE` flags to the flow executable. You can also use comma-separated format:

```yaml
    params: 'CI=true, COVERAGE=true'
```

### Environment Variables

```yaml
- name: Publish release
  uses: flowexec/action@v1
  with:
    executable: 'publish release'
    params: 'VERSION=1.2.0'
    env: |
      GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
      NPM_TOKEN=${{ secrets.NPM_TOKEN }}
```

### Multi-Workspace (Local + Remote)

```yaml
- name: Deploy to staging
  uses: flowexec/action@v1
  with:
    executable: 'deploy staging'
    workspaces: |
      backend: ./backend
      frontend: https://github.com/user/frontend-repo
      shared: https://github.com/user/shared-lib
    clone-token: ${{ secrets.GITHUB_TOKEN }}
```

### Git-Sourced Workspace Updates

For workspaces cloned from git repositories, use `sync-git` to pull the latest changes before execution:

```yaml
- name: Deploy with latest shared configs
  uses: flowexec/action@v1
  with:
    executable: 'deploy staging'
    workspaces: |
      app: .
      shared:
        repo: https://github.com/myorg/shared-flows
        ref: main
    clone-token: ${{ secrets.GITHUB_TOKEN }}
    sync-git: 'true'
```

### With Secrets (Auto-Generated Vault)

```yaml
- name: Deploy with secrets
  uses: flowexec/action@v1
  with:
    executable: 'deploy production'
    secrets: |
      DATABASE_URL=${{ secrets.DATABASE_URL }}
      API_KEY=${{ secrets.API_KEY }}
```

### Cross-Job Vault Sharing

```yaml
jobs:
  setup:
    outputs:
      vault-key: ${{ steps.init.outputs.vault-key }}
    steps:
      - uses: flowexec/action@v1
        id: init
        with:
          executable: 'validate'
          secrets: |
            SHARED_SECRET=${{ secrets.SHARED_SECRET }}

  deploy:
    needs: setup
    steps:
      - uses: flowexec/action@v1
        with:
          executable: 'deploy production'
          vault-key: ${{ needs.setup.outputs.vault-key }}
          secrets: |
            DEPLOY_KEY=${{ secrets.DEPLOY_KEY }}
```

### Error Handling

Use `continue-on-error` with the `error-code` output to handle failures programmatically:

```yaml
- name: Run migration
  uses: flowexec/action@v1
  id: migrate
  with:
    executable: 'migrate database'
    continue-on-error: 'true'

- name: Handle failure
  if: steps.migrate.outputs.exit-code != '0'
  run: |
    echo "Migration failed with error: ${{ steps.migrate.outputs.error-code }}"
    if [ "${{ steps.migrate.outputs.error-code }}" = "TIMEOUT" ]; then
      echo "Consider increasing the timeout"
    fi
```

### Advanced Configuration

```yaml
- name: Complex deployment
  uses: flowexec/action@v1
  with:
    executable: 'deploy staging'
    workspaces: |
      app: .
      terraform:
        repo: https://github.com/myorg/terraform
        ref: v1.2.0
      k8s:
        repo: https://github.com/myorg/k8s-configs
        ref: staging
    clone-token: ${{ secrets.GITHUB_TOKEN }}
    params: 'ENVIRONMENT=staging, DRY_RUN=false'
    env: |
      AWS_REGION=us-east-1
    timeout: '20m'
    sync-git: 'true'
    secrets: |
      AWS_ACCESS_KEY=${{ secrets.AWS_ACCESS_KEY }}
      KUBECONFIG=${{ secrets.KUBECONFIG }}
```

## Requirements

- Valid flow workspaces and executables in your repository
- GitHub Actions runner (`ubuntu-latest`, `macos-latest`, or `windows-latest`)
