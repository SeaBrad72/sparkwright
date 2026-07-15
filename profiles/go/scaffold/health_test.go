package main

import "testing"

// TestHealth exercises the pure health core in isolation. The routing/server
// assertions that used to live here moved to server_test.go + the integration
// suite when health.go was slimmed to just Health() (the cap6 locked file).
func TestHealth(t *testing.T) {
	got := Health()
	if got["status"] != "ok" {
		t.Fatalf("Health()[status] = %q, want %q", got["status"], "ok")
	}
	if len(got) != 1 {
		t.Fatalf("Health() returned %d keys, want 1", len(got))
	}
}
