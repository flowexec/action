# flow CLI GitHub Action

[![GitHub release](https://img.shields.io/github/v/release/jahvon/flow-action)](https://github.com/jahvon/flow-action/releases)
[![GitHub marketplace](https://img.shields.io/badge/marketplace-flow--action-blue?logo=github)](https://github.com/marketplace/actions/flow-action)

Execute [flow](https://github.com/jahvon/flow) workflows in your GitHub Actions.

## Quick Start

```yaml
- uses: jahvon/flow-action@v1
  with:
    executable: 'build app'
```

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
| `secrets` | JSON object of secrets to set in flow vault | `{}` |
| `vault-key` | Vault encryption key (for existing vaults) | |
| `working-directory` | Directory to run flow from | `.` |
| `timeout` | Timeout for executable execution | `30m` |
| `continue-on-error` | Continue workflow if flow executable fails | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `exit-code` | Exit code of the flow executable |
| `output` | Output from the flow executable |
| `execution-time` | Time taken to execute the flow executable |
| `vault-key` | Generated vault encryption key (if vault was created) |

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
        uses: jahvon/flow-action@v1
        with:
          executable: 'build app'

      - name: Run tests
        uses: jahvon/flow-action@v1
        with:
          executable: 'test unit'
```

### Multi-Workspace (Local + Remote)

```yaml
- name: Deploy to staging
  uses: jahvon/flow-action@v1
  with:
    executable: 'deploy staging'
    workspaces: |
      backend: ./backend
      frontend: https://github.com/user/frontend-repo
      shared: https://github.com/user/shared-lib
    clone-token: ${{ secrets.GITHUB_TOKEN }}
```

### With Secrets (Auto-Generated Vault)

```yaml
- name: Deploy with secrets
  uses: jahvon/flow-action@v1
  with:
    executable: 'deploy production'
    secrets: |
      {
        "DATABASE_URL": "${{ secrets.DATABASE_URL }}",
        "API_KEY": "${{ secrets.API_KEY }}"
      }
```

### Cross-Job Vault Sharing

```yaml
jobs:
  setup:
    outputs:
      vault-key: ${{ steps.init.outputs.vault-key }}
    steps:
      - uses: jahvon/flow-action@v1
        id: init
        with:
          executable: 'validate'
          secrets: |
            {"shared-secret": "${{ secrets.SHARED_SECRET }}"}

  deploy:
    needs: setup
    steps:
      - uses: jahvon/flow-action@v1
        with:
          executable: 'deploy production'
          vault-key: ${{ needs.setup.outputs.vault-key }}
          secrets: |
            {"deploy-key": "${{ secrets.DEPLOY_KEY }}"}
```

### Advanced Configuration

```yaml
- name: Complex deployment
  uses: jahvon/flow-action@v1
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
    timeout: '20m'
    secrets: |
      {
        "AWS_ACCESS_KEY": "${{ secrets.AWS_ACCESS_KEY }}",
        "KUBECONFIG": "${{ secrets.KUBECONFIG }}"
      }
```

## Requirements

- Valid flow workspaces and executables in your repository
- GitHub Actions runner (ubuntu-latest or macos-latest)

## Support

- 📖 [flow Documentation](https://flowexec.io/)
- 🐛 [Report Issues](https://github.com/jahvon/flow-action/issues)
