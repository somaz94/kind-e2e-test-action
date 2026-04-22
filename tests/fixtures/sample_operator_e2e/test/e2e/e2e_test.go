package e2e

import (
	"os/exec"
	"strings"
	"testing"
)

// TestKindClusterReachable exercises `kubectl` against the kind cluster the
// action created. We intentionally shell out instead of pulling in client-go
// to keep the fixture dependency-free.
func TestKindClusterReachable(t *testing.T) {
	out, err := exec.Command("kubectl", "get", "nodes", "-o", "name").CombinedOutput()
	if err != nil {
		t.Fatalf("kubectl get nodes failed: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "node/") {
		t.Fatalf("expected at least one 'node/*' entry, got: %q", string(out))
	}
}
