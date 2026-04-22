# sample_operator_e2e (fixture)

Minimal Go module used by `ci.yml` to exercise `somaz94/kind-e2e-test-action`.

- `go.mod` — single-module, no external deps.
- `Makefile` — `test-e2e` target. Pre-flight checks `kind` + an existing kind cluster, runs `kubectl cluster-info`/`get nodes`/`wait`, and finally runs `go test ./test/e2e/ -v -count=1`. This mirrors the shape of `make test-e2e` in real kubebuilder operators — the action is responsible for creating the cluster, the fixture is responsible for asserting it's usable.
- `test/e2e/e2e_test.go` — single placeholder Go test that shells out to `kubectl get nodes` and asserts at least one node exists. No external Go dependencies.
