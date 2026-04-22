# CLAUDE.md

<br/>

## Project Structure

- Composite GitHub Action (no Docker image — `runs.using: composite`)
- Replaces the 5-step inline block every kubebuilder operator repo copy-pastes: `setup-go` → install kind → verify kind → `kind create cluster` → `go mod tidy && make test-e2e`
- Defaults match standard kubebuilder scaffolds; all inputs are overridable for non-standard layouts
- Multi-arch kind installer (auto-detects `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`) — reuses kind's official `dl/<version>/kind-<os>-<arch>` URLs

<br/>

## Key Files

- `action.yml` — composite action (**9 inputs**, **2 outputs**). Two `setup-go` steps gated on `go_version` empty/non-empty, followed by install kind → verify → create cluster → optional `go mod tidy` → e2e command → summary. All `run:` steps use `working-directory: ${{ inputs.working_directory }}` so subdirectory projects work without extra wiring.
- `tests/fixtures/sample_operator_e2e/` — minimal Go module (`go.mod`, `Makefile` with a `test-e2e` target, `test/e2e/e2e_test.go` shelling out to `kubectl get nodes`). No external Go dependencies — the fixture's job is to prove the cluster the action created is reachable. Used by both `ci.yml` and `use-action.yml`.
- `cliff.toml` — git-cliff config for release notes.
- `Makefile` — `lint` (dockerized yamllint), `test` (runs the fixture locally; needs a pre-existing kind cluster + docker + kubectl), `fixtures`, `clean`.

<br/>

## Build & Test

There is no local "build" — composite actions execute on the GitHub Actions runner.

```bash
make lint         # yamllint action.yml + workflows + fixtures
make test         # runs `make test-e2e` inside tests/fixtures/sample_operator_e2e (needs a kind cluster already up)
make fixtures     # list fixture files (sanity check)
make clean        # remove Go test caches inside the fixture
```

Local `make test` requires `kind create cluster` to have been run first (the fixture's `test-e2e` target pre-flights `kind get clusters`). `make lint` only needs Docker.

<br/>

## Workflows

- `ci.yml` — `lint` (yamllint + actionlint) + `test-action` (defaults, expect `cluster_name=kind`, `e2e_exit_code=0`) + `test-action-custom` (pinned `kind_version: v0.23.0`, `cluster_name: custom-e2e`, direct `go test ./test/e2e/ -v -count=1` as `e2e_command`) + `ci-result` aggregator.
- `release.yml` — git-cliff release notes + `softprops/action-gh-release@v3` + `somaz94/major-tag-action@v1` for the `v1` sliding tag.
- `use-action.yml` — post-release smoke test. Runs `somaz94/kind-e2e-test-action@v1` against the fixture in two flavours: defaults (expect `cluster_name=kind`) and pinned kind + custom cluster name (expect `cluster_name=smoke-e2e`).
- `gitlab-mirror.yml`, `changelog-generator.yml`, `contributors.yml`, `dependabot-auto-merge.yml`, `issue-greeting.yml`, `stale-issues.yml` — standard repo automation shared with sibling `somaz94/*-action` repos.

<br/>

## Release

Push a `vX.Y.Z` tag → `release.yml` runs → GitHub Release published → `v1` major tag updated → `use-action.yml` smoke-tests the published version against the fixture (both defaults and pinned-kind paths).

<br/>

## Action Inputs

Required: none (fully default-driven for kubebuilder-style projects).

Tuning: `go_version` / `go_version_file`, `working_directory` (default `.`), `cache` (default `true`), `run_mod_tidy` (default `true`), `kind_version` (default `latest`), `kind_node_image` (default `''`), `cluster_name` (default `kind`), `e2e_command` (default `make test-e2e`).

See [README.md](README.md) for the full table.

<br/>

## Internal Flow

1. **Validate inputs** — either `go_version` or `go_version_file` must be set; `working_directory` must exist; `cluster_name` and `e2e_command` must be non-empty.
2. **`actions/setup-go`** — gated on `go_version` being non-empty. When `working_directory != '.'`, `go-version-file` is rewritten to `${working_directory}/${go_version_file}` so `actions/setup-go` finds the right file from the repo root.
3. **Install kind** — `uname -s` + `uname -m` → one of `linux-amd64` / `linux-arm64` / `darwin-amd64` / `darwin-arm64`. Downloads `https://kind.sigs.k8s.io/dl/<kind_version>/kind-<os>-<arch>` (`latest` is a literal kind-published URL segment). `curl -fsSL` so failures surface early; `chmod +x` + `sudo mv` to `/usr/local/bin/kind`.
4. **Verify kind** — `kind version` in its own `::group::` for log hygiene.
5. **Create kind cluster** — `kind create cluster --name <cluster_name>`, plus `--image <kind_node_image>` when non-empty. Follows up with `kubectl cluster-info --context kind-<cluster_name>` as a smoke check. Emits the `cluster_name` output from this step's id.
6. **`go mod tidy`** — optional, on by default. Matches the pattern every repo's inline workflow already uses.
7. **E2E command** — `bash -c "$e2e_command"` from `working_directory`. `e2e_exit_code=0` is emitted only on success (the action fails on non-zero exit, matching every inline workflow it replaces).
8. **Summary** — a markdown table (working directory / kind version / node image / cluster name / e2e command / result) is appended to `$GITHUB_STEP_SUMMARY`.

<br/>

## Composite Output Wiring

This action only has two outputs, so the common composite-outputs pitfall (top-level `outputs.<name>.value: ${{ steps.<id>.outputs.<name> }}` can only track a single `steps.<id>`) is easy to get right: `cluster_name` is wired to the single `steps.cluster.outputs.cluster_name` and `e2e_exit_code` to `steps.e2e.outputs.e2e_exit_code`. No branching is needed because every code path runs the same `cluster` and `e2e` step ids.

If you ever add an output whose value depends on a branched step (e.g., a "kind skipped" mode), set it inside a single step that handles both branches internally — don't split across `if:`-gated steps.
