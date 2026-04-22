# kind-e2e-test-action

[![CI](https://github.com/somaz94/kind-e2e-test-action/actions/workflows/ci.yml/badge.svg)](https://github.com/somaz94/kind-e2e-test-action/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Latest Tag](https://img.shields.io/github/v/tag/somaz94/kind-e2e-test-action)](https://github.com/somaz94/kind-e2e-test-action/tags)
[![Top Language](https://img.shields.io/github/languages/top/somaz94/kind-e2e-test-action)](https://github.com/somaz94/kind-e2e-test-action)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Kind%20E2E%20Test%20Action-blue?logo=github)](https://github.com/marketplace/actions/kind-e2e-test-action)

A composite GitHub Action that installs [kind](https://kind.sigs.k8s.io/), creates a kind cluster, and runs a Go end-to-end test command — in a single step.

It replaces the five-step inline block every kubebuilder repo tends to copy (`setup-go` → install kind → verify kind → `kind create cluster` → `go mod tidy && make test-e2e`).

<br/>

## Features

- One action, whole kind-based e2e flow: `setup-go` → download kind → `kind create cluster` → wait for node readiness → optional `go mod tidy` → e2e command
- Defaults match the standard kubebuilder layout (`go.mod`, `make test-e2e`, latest kind, cluster name `kind`) — zero config for most repos
- Tunable: pinned `kind_version`, explicit `kind_node_image`, `kind_config` for multi-node / port-mapping clusters, custom `cluster_name`, `cluster_ready_timeout`, custom `e2e_command`, pinned `go_version`, subdirectory `working_directory`, `cache_dependency_path` passthrough for mono-repos
- Multi-arch: detects `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64` automatically when downloading the kind binary
- Automatic failure diagnostics: on action failure, runs `kind export logs` and uploads the directory as a workflow artifact (`kind-logs-<cluster_name>-<run_id>-<run_attempt>`, 7-day retention) — can be disabled via `upload_logs_on_failure: false`
- Writes a per-run summary table to `$GITHUB_STEP_SUMMARY`
- Exposes `cluster_name` and `e2e_exit_code` outputs for downstream steps

<br/>

## Requirements

- **Runner OS**: `ubuntu-latest` is the tested target (kind needs a working Docker daemon; GitHub's hosted Ubuntu runners ship one). Self-hosted runners need Docker/containerd available.
- **Caller must run `actions/checkout`** before this action so that `working_directory` contains the Go module.
- **`make` / Go toolchain** available in the repo when using the default `e2e_command: make test-e2e`. Override `e2e_command` if you invoke the e2e suite differently.

<br/>

## Quick Start

Drop this into `.github/workflows/test-e2e.yml` of any kubebuilder-style repo:

```yaml
name: E2E Tests

on:
  push:
    branches: [main]
    paths-ignore:
      - '.github/workflows/**'
      - '**/*.md'
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  test-e2e:
    name: Run on Ubuntu
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: somaz94/kind-e2e-test-action@v1
```

With all defaults it runs: `setup-go` from `go.mod` → install latest kind → `kind create cluster --name kind` → `kubectl wait --for=condition=Ready nodes --all --timeout=60s` → `go mod tidy` → `make test-e2e`. On failure, kind logs are exported and uploaded as a workflow artifact.

<br/>

## Usage

### Pin the kind version

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    kind_version: v0.23.0
```

<br/>

### Pin both the kind release and the node image

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    kind_version: v0.23.0
    kind_node_image: kindest/node:v1.30.0
```

<br/>

### Use a custom cluster name and e2e command

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    cluster_name: acme-e2e
    e2e_command: 'go test ./test/e2e/ -v -ginkgo.v'
```

<br/>

### Kubebuilder project in a subdirectory

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    working_directory: operator
    go_version_file: go.mod
```

<br/>

### Pin the Go version explicitly

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    go_version: '1.22'
```

<br/>

### Multi-node cluster via `kind_config`

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    kind_config: ./test/e2e/kind-multi-node.yaml
```

Example `kind-multi-node.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

<br/>

### Longer readiness wait (slow images) or skip it entirely

```yaml
# raise the timeout
- uses: somaz94/kind-e2e-test-action@v1
  with:
    cluster_ready_timeout: 3m

# or skip the wait (the action moves straight to go mod tidy + e2e)
- uses: somaz94/kind-e2e-test-action@v1
  with:
    cluster_ready_timeout: ''
```

<br/>

### Mono-repo with go.sum outside `working_directory`

```yaml
- uses: actions/checkout@v6
- uses: somaz94/kind-e2e-test-action@v1
  with:
    working_directory: services/api
    cache_dependency_path: services/api/go.sum
```

<br/>

### Disable failure log upload

```yaml
- uses: somaz94/kind-e2e-test-action@v1
  with:
    upload_logs_on_failure: 'false'
```

<br/>

### Consume the outputs

```yaml
- id: e2e
  uses: somaz94/kind-e2e-test-action@v1

- name: Report
  if: always()
  run: |
    echo "cluster_name=${{ steps.e2e.outputs.cluster_name }}"
    echo "e2e_exit_code=${{ steps.e2e.outputs.e2e_exit_code }}"
```

<br/>

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `go_version_file` | Path to `go.mod` (or another file) used by `actions/setup-go` as `go-version-file`. Ignored when `go_version` is set. | No | `go.mod` |
| `go_version` | Explicit Go version (e.g., `1.22`). Takes precedence over `go_version_file` when non-empty. | No | `''` |
| `working_directory` | Directory to run all commands in (Go module root). | No | `.` |
| `cache` | Enable Go module/build cache in `actions/setup-go`. | No | `true` |
| `cache_dependency_path` | Passthrough to `actions/setup-go` `cache-dependency-path`. Leave empty to rely on setup-go's default (`go.sum` next to `go.mod`). Handy for mono-repos. | No | `''` |
| `run_mod_tidy` | When `true`, run `go mod tidy` before the e2e command. | No | `true` |
| `kind_version` | kind release to install. `latest` or a version tag like `v0.23.0`. | No | `latest` |
| `kind_node_image` | Node image passed to `kind create cluster --image`. Empty means use kind's default for the installed release. Ignored for nodes that set an image inside `kind_config`. | No | `''` |
| `kind_config` | Path to a kind cluster config YAML passed as `kind create cluster --config`. Empty means single-node default cluster. | No | `''` |
| `cluster_name` | Name passed to `kind create cluster --name`. | No | `kind` |
| `cluster_ready_timeout` | Timeout for `kubectl wait --for=condition=Ready nodes --all --timeout=<value>` after cluster creation. Empty skips the wait. | No | `60s` |
| `e2e_command` | E2E command executed from `working_directory`. | No | `make test-e2e` |
| `upload_logs_on_failure` | When `true`, on action failure run `kind export logs` and upload the directory as a workflow artifact (`kind-logs-<cluster_name>-<run_id>-<run_attempt>`, 7-day retention). | No | `true` |

<br/>

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | Name of the kind cluster that was created (echo of the `cluster_name` input). |
| `e2e_exit_code` | Exit code of the e2e command. Always `0` when the action succeeds (the action fails otherwise). |

<br/>

## Permissions

The action itself needs no special permissions beyond what `actions/checkout` and `actions/setup-go` require. A typical caller:

```yaml
permissions:
  contents: read
```

<br/>

## How It Works

1. **Validate inputs** — `go_version` or `go_version_file` must be set; `working_directory` must exist; `cluster_name` and `e2e_command` must be non-empty; `kind_config` (when set) must point to an existing file.
2. **`actions/setup-go`** — either from `go_version_file` (default) or `go_version` (when explicitly set). Go module/build cache controlled by `cache`; `cache_dependency_path` is passed through verbatim to `actions/setup-go`.
3. **Install kind** — detects OS/arch (`linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`) and downloads `https://kind.sigs.k8s.io/dl/<version>/kind-<os>-<arch>` (`latest` is a literal URL segment kind publishes). Placed at `/usr/local/bin/kind`.
4. **Verify kind** — `kind version` for a visible version stamp in the log.
5. **Create kind cluster** — `kind create cluster --name <cluster_name>` (plus `--image <kind_node_image>` and/or `--config <kind_config>` when set). Follows up with `kubectl cluster-info --context kind-<cluster_name>` as a smoke check. Exposes `cluster_name` output.
6. **Wait for node readiness** (unless `cluster_ready_timeout` is empty) — `kubectl wait --for=condition=Ready nodes --all --timeout=<cluster_ready_timeout>`. Fail-fast on slow images or misconfigured multi-node clusters.
7. **`go mod tidy`** — optional, matches the pattern every repo's inline workflow already uses.
8. **E2E command** — `bash -c "$e2e_command"` run from `working_directory`. Exit code emitted as the `e2e_exit_code` output.
9. **Summary** — a markdown table (working directory / kind version / node image / config / cluster name / ready timeout / e2e command / result) is appended to `$GITHUB_STEP_SUMMARY`.
10. **Failure diagnostics** (when `upload_logs_on_failure: true`, skipped on success) — `kind export logs` dumps container / kubelet / containerd logs for every node, then `actions/upload-artifact@v4` uploads the directory as `kind-logs-<cluster_name>-<run_id>-<run_attempt>` (7-day retention). Gracefully skipped if the cluster never finished creating.

<br/>

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
