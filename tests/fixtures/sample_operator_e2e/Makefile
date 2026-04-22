.PHONY: test-e2e

test-e2e:
	@command -v kind >/dev/null 2>&1 || { echo "kind not installed"; exit 1; }
	@kind get clusters | grep -q . || { echo "no kind cluster running"; exit 1; }
	kubectl cluster-info
	kubectl get nodes
	kubectl wait --for=condition=Ready nodes --all --timeout=60s
	go test ./test/e2e/ -v -count=1
