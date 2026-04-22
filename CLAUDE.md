# CLAUDE.md

<br/>

## Project Structure

- Composite GitHub Action (no Docker image — `runs.using: composite`)
- Replaces the 5-step inline block every kubebuilder operator repo copy-pastes: `setup-go` → install kind → verify kind → `kind create cluster` → `go mod tidy && make test-e2e`
- Defaults match standard kubebuilder scaffolds; all inputs are overridable for non-standard layouts
- Multi-arch kind installer (auto-detects `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`) — reuses kind's official `dl/<version>/kind-<os>-<arch>` URLs
- Built-in failure diagnostics: `kind export logs` + `actions/upload-artifact@v4` run on failure so operators can triage e2e regressions without re-running with added logging

<br/>

## Key Files

- `action.yml` — composite action (**13 inputs**, **2 outputs**). Two `setup-go` steps gated on `go_version` empty/non-empty (both now passthrough `cache_dependency_path` to `actions/setup-go`), followed by install kind → verify → create cluster (with optional `--config` / `--image`) → wait for node readiness (gated on `cluster_ready_timeout` non-empty) → optional `go mod tidy` → e2e command → `if: failure()` kind log export + `if: failure()` artifact upload → summary. All `run:` steps use `working-directory: ${{ inputs.working_directory }}` so subdirectory projects work without extra wiring.
- `tests/fixtures/sample_operator_e2e/` — minimal Go module (`go.mod`, `Makefile` with a `test-e2e` target, `test/e2e/e2e_test.go` shelling out to `kubectl get nodes`). No external Go dependencies — the fixture's job is to prove the cluster the action created is reachable. Used by both `ci.yml` and `use-action.yml`. The `kubectl wait` was moved out of the fixture Makefile into the action itself (`cluster_ready_timeout` input) so the fixture only asserts e2e-level things.
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

- `ci.yml` — `lint` (yamllint + actionlint) + `test-action` (defaults, expect `cluster_name=kind`, `e2e_exit_code=0`) + `test-action-custom` (pinned `kind_version: v0.23.0`, `cluster_name: custom-e2e`, direct `go test ./test/e2e/ -v -count=1` as `e2e_command`) + `test-action-failure` (runs action with `e2e_command: 'false'` under `continue-on-error: true`, asserts outcome=failure, then `actions/download-artifact@v4` pulls the auto-uploaded `kind-logs-failure-e2e-<run_id>-<run_attempt>` and greps for `kubelet.log`) + `ci-result` aggregator.
- `release.yml` — git-cliff release notes + `softprops/action-gh-release@v3` + `somaz94/major-tag-action@v1` for the `v1` sliding tag.
- `use-action.yml` — post-release smoke test. Runs `somaz94/kind-e2e-test-action@v1` against the fixture in two flavours: defaults (expect `cluster_name=kind`) and pinned kind + custom cluster name (expect `cluster_name=smoke-e2e`).
- `gitlab-mirror.yml`, `changelog-generator.yml`, `contributors.yml`, `dependabot-auto-merge.yml`, `issue-greeting.yml`, `stale-issues.yml` — standard repo automation shared with sibling `somaz94/*-action` repos.

<br/>

## Release

Push a `vX.Y.Z` tag → `release.yml` runs → GitHub Release published → `v1` major tag updated → `use-action.yml` smoke-tests the published version against the fixture (both defaults and pinned-kind paths).

<br/>

## Action Inputs

Required: none (fully default-driven for kubebuilder-style projects).

Tuning: `go_version` / `go_version_file`, `working_directory` (default `.`), `cache` (default `true`), `cache_dependency_path` (default `''`), `run_mod_tidy` (default `true`), `kind_version` (default `latest`), `kind_node_image` (default `''`), `kind_config` (default `''`), `cluster_name` (default `kind`), `cluster_ready_timeout` (default `60s`, empty skips), `e2e_command` (default `make test-e2e`), `upload_logs_on_failure` (default `true`).

See [README.md](README.md) for the full table.

<br/>

## Internal Flow

1. **Validate inputs** — either `go_version` or `go_version_file` must be set; `working_directory` must exist; `cluster_name` and `e2e_command` must be non-empty; `kind_config` (when set) must point to an existing file.
2. **`actions/setup-go`** — gated on `go_version` being non-empty. When `working_directory != '.'`, `go-version-file` is rewritten to `${working_directory}/${go_version_file}` so `actions/setup-go` finds the right file from the repo root. `cache_dependency_path` is forwarded verbatim (both gated branches) so mono-repos can point setup-go at the correct `go.sum` without going through `working_directory` rewriting.
3. **Install kind** — `uname -s` + `uname -m` → one of `linux-amd64` / `linux-arm64` / `darwin-amd64` / `darwin-arm64`. Downloads `https://kind.sigs.k8s.io/dl/<kind_version>/kind-<os>-<arch>` (`latest` is a literal kind-published URL segment). `curl -fsSL` so failures surface early; `chmod +x` + `sudo mv` to `/usr/local/bin/kind`.
4. **Verify kind** — `kind version` in its own `::group::` for log hygiene.
5. **Create kind cluster** — `kind create cluster --name <cluster_name>`, plus `--image <kind_node_image>` and/or `--config <kind_config>` when non-empty. kind treats a per-node image inside the config as the source of truth, so when both `kind_node_image` and `kind_config` are set the config wins for any node that declares an image. Follows up with `kubectl cluster-info --context kind-<cluster_name>` as a smoke check. Emits the `cluster_name` output from this step's id.
6. **Wait for node readiness** — gated on `cluster_ready_timeout` being non-empty (default `60s`). Runs `kubectl --context kind-<cluster_name> wait --for=condition=Ready nodes --all --timeout=<cluster_ready_timeout>`. Previously lived in the fixture Makefile; moved into the action so every consumer benefits.
7. **`go mod tidy`** — optional, on by default. Matches the pattern every repo's inline workflow already uses.
8. **E2E command** — `bash -c "$e2e_command"` from `working_directory`. `e2e_exit_code=0` is emitted only on success (the action fails on non-zero exit, matching every inline workflow it replaces).
9. **Export kind logs** (`if: failure() && inputs.upload_logs_on_failure == 'true'`) — runs `kind export logs <dir>` into `${RUNNER_TEMP}/kind-logs-<cluster_name>`. Guards: if the `kind` binary never made it to PATH (install-phase failure) or the cluster never got created, the step logs a `::notice::` and emits an empty `logs_dir` output so the upload step can short-circuit. `set +e` (not `set -e`) so a non-zero `kind export logs` degrades to a `::warning::` rather than masking the original failure.
10. **Upload kind logs artifact** (`if: failure() && inputs.upload_logs_on_failure == 'true' && steps.export_logs.outputs.logs_dir != ''`) — `actions/upload-artifact@v4` uploads `${logs_dir}` as `kind-logs-<cluster_name>-<run_id>-<run_attempt>` with 7-day retention and `if-no-files-found: warn`.
11. **Summary** — a markdown table (working directory / kind version / node image / cluster config / cluster name / cluster ready timeout / e2e command / result) is appended to `$GITHUB_STEP_SUMMARY`.

<br/>

## Composite Output Wiring

Only two outputs, so the common composite-outputs pitfall (top-level `outputs.<name>.value: ${{ steps.<id>.outputs.<name> }}` can only track a single `steps.<id>`) is easy to get right: `cluster_name` is wired to the single `steps.cluster.outputs.cluster_name` and `e2e_exit_code` to `steps.e2e.outputs.e2e_exit_code`. No branching is needed because every success path runs those two step ids.

The failure-path steps (`export_logs`, upload-artifact) do not feed action outputs — the artifact is consumed via `actions/download-artifact` in the caller's next job, not through an output value — so the single-step-id rule is still unbroken.

If you ever add an output whose value depends on a branched step (e.g., a "kind skipped" mode or "logs uploaded" flag), set it inside a single step that handles both branches internally — don't split across `if:`-gated steps.
