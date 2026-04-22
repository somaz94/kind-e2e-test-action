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

- One action, whole kind-based e2e flow: `setup-go` → download kind → `kind create cluster` → optional `go mod tidy` → e2e command
- Defaults match the standard kubebuilder layout (`go.mod`, `make test-e2e`, latest kind, cluster name `kind`) — zero config for most repos
- Tunable: pinned `kind_version`, explicit `kind_node_image`, custom `cluster_name`, custom `e2e_command`, pinned `go_version`, subdirectory `working_directory`
- Multi-arch: detects `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64` automatically when downloading the kind binary
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

With all defaults it runs: `setup-go` from `go.mod` → install latest kind → `kind create cluster --name kind` → `go mod tidy` → `make test-e2e`.

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
| `run_mod_tidy` | When `true`, run `go mod tidy` before the e2e command. | No | `true` |
| `kind_version` | kind release to install. `latest` or a version tag like `v0.23.0`. | No | `latest` |
| `kind_node_image` | Node image passed to `kind create cluster --image`. Empty means use kind's default for the installed release. | No | `''` |
| `cluster_name` | Name passed to `kind create cluster --name`. | No | `kind` |
| `e2e_command` | E2E command executed from `working_directory`. | No | `make test-e2e` |

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

1. **Validate inputs** — `go_version` or `go_version_file` must be set; `working_directory` must exist; `cluster_name` and `e2e_command` must be non-empty.
2. **`actions/setup-go`** — either from `go_version_file` (default) or `go_version` (when explicitly set). Go module/build cache controlled by `cache`.
3. **Install kind** — detects OS/arch (`linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`) and downloads `https://kind.sigs.k8s.io/dl/<version>/kind-<os>-<arch>` (`latest` is a literal URL segment kind publishes). Placed at `/usr/local/bin/kind`.
4. **Verify kind** — `kind version` for a visible version stamp in the log.
5. **Create kind cluster** — `kind create cluster --name <cluster_name>` (plus `--image <kind_node_image>` when set). Follows up with `kubectl cluster-info --context kind-<cluster_name>` as a smoke check. Exposes `cluster_name` output.
6. **`go mod tidy`** — optional, matches the pattern every repo's inline workflow already uses.
7. **E2E command** — `bash -c "$e2e_command"` run from `working_directory`. Exit code emitted as the `e2e_exit_code` output.
8. **Summary** — a markdown table (working directory / kind version / node image / cluster name / e2e command / result) is appended to `$GITHUB_STEP_SUMMARY`.

<br/>

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
