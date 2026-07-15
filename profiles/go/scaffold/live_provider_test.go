package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeFlagFile writes content to a fresh file in the test's temp dir and
// returns its path.
func writeFlagFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "flags.json")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write flag file: %v", err)
	}
	return path
}

// TestFileProviderLiveFlip proves a rewrite of the file flips resolution in the
// SAME process, with no restart (the live-flip contract).
func TestFileProviderLiveFlip(t *testing.T) {
	path := writeFlagFile(t, `{"new_greeting": true}`)
	p := FileConfigProvider(path)

	if !p.IsEnabled("new_greeting") {
		t.Fatal("expected true from initial file content")
	}
	// Rewrite the same path: the provider must observe the flip on the next call.
	if err := os.WriteFile(path, []byte(`{"new_greeting": false}`), 0o600); err != nil {
		t.Fatalf("rewrite: %v", err)
	}
	if p.IsEnabled("new_greeting") {
		t.Fatal("expected false after live rewrite")
	}
}

// TestFileProviderStrictBool proves ONLY a JSON boolean true enables; a "true"
// string, 1, or false all resolve OFF (fail-safe registry default).
func TestFileProviderStrictBool(t *testing.T) {
	cases := []struct {
		name    string
		content string
		want    bool
	}{
		{"boolean true enables", `{"new_greeting": true}`, true},
		{"boolean false stays off", `{"new_greeting": false}`, false},
		{"string true stays off", `{"new_greeting": "true"}`, false},
		{"numeric one stays off", `{"new_greeting": 1}`, false},
		{"null value stays off", `{"new_greeting": null}`, false},
		{"object value stays off", `{"new_greeting": {"x": true}}`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			p := FileConfigProvider(writeFlagFile(t, tc.content))
			if got := p.IsEnabled("new_greeting"); got != tc.want {
				t.Fatalf("IsEnabled = %v, want %v", got, tc.want)
			}
		})
	}
}

// TestFileProviderMissingKey proves a flag absent from the file falls back to
// the registry default (OFF).
func TestFileProviderMissingKey(t *testing.T) {
	p := FileConfigProvider(writeFlagFile(t, `{"other_flag": true}`))
	if p.IsEnabled("new_greeting") {
		t.Fatal("absent key must fall back to registry default (off)")
	}
}

// TestFileProviderFailSafe proves every corrupt/hostile input resolves OFF and
// never panics: missing file, malformed JSON, and non-object payloads.
func TestFileProviderFailSafe(t *testing.T) {
	t.Run("missing file", func(t *testing.T) {
		p := FileConfigProvider(filepath.Join(t.TempDir(), "absent.json"))
		if p.IsEnabled("new_greeting") {
			t.Fatal("missing file must resolve off")
		}
	})
	t.Run("malformed json", func(t *testing.T) {
		p := FileConfigProvider(writeFlagFile(t, `{"new_greeting": tru`))
		if p.IsEnabled("new_greeting") {
			t.Fatal("malformed json must resolve off")
		}
	})
	t.Run("array payload", func(t *testing.T) {
		p := FileConfigProvider(writeFlagFile(t, `[true]`))
		if p.IsEnabled("new_greeting") {
			t.Fatal("array payload must resolve off")
		}
	})
	t.Run("scalar payload", func(t *testing.T) {
		p := FileConfigProvider(writeFlagFile(t, `42`))
		if p.IsEnabled("new_greeting") {
			t.Fatal("scalar payload must resolve off")
		}
	})
	t.Run("null payload", func(t *testing.T) {
		p := FileConfigProvider(writeFlagFile(t, `null`))
		if p.IsEnabled("new_greeting") {
			t.Fatal("null payload must resolve off")
		}
	})
	t.Run("deeply-nested payload", func(t *testing.T) {
		// The DoS class the Python Slice-2 review caught: a tampered file whose deep
		// nesting crashes the resolver (there a RecursionError; in Go a stack overflow
		// is UNRECOVERABLE — recover() cannot catch it). encoding/json's scanner errors
		// on excessive nesting before recursing, so this must resolve OFF and the test
		// process must SURVIVE (reaching the assertion at all is the no-crash proof).
		depth := 200000
		nested := strings.Repeat("[", depth) + strings.Repeat("]", depth)
		p := FileConfigProvider(writeFlagFile(t, `{"new_greeting": `+nested+`}`))
		if p.IsEnabled("new_greeting") {
			t.Fatal("deeply-nested payload must resolve off")
		}
	})
	t.Run("unreadable directory path", func(t *testing.T) {
		// A directory opens but cannot be read as a file (EISDIR) -> off.
		p := FileConfigProvider(t.TempDir())
		if p.IsEnabled("new_greeting") {
			t.Fatal("directory path must resolve off")
		}
	})
}

// TestFileProviderForbiddenKeys proves pollution/dunder keys are rejected
// outright and never resolved from file data, even when the file says true.
func TestFileProviderForbiddenKeys(t *testing.T) {
	forbidden := []string{"__proto__", "constructor", "prototype", "__class__", "__init__"}
	for _, key := range forbidden {
		t.Run(key, func(t *testing.T) {
			// A file that maliciously sets the forbidden key true must NOT enable it.
			p := FileConfigProvider(writeFlagFile(t, `{"`+key+`": true}`))
			if p.IsEnabled(key) {
				t.Fatalf("forbidden key %q was resolved from file data", key)
			}
		})
	}
}

// TestFileProviderOversizedRejected proves a file over the byte cap is rejected
// before it can influence resolution (TOCTOU-safe, bounds memory) -> OFF.
func TestFileProviderOversizedRejected(t *testing.T) {
	path := filepath.Join(t.TempDir(), "huge.json")
	// Build a valid-looking JSON object padded past the 1 MiB cap; the cap must
	// reject it BEFORE any parse, so the true value inside can never take effect.
	pad := make([]byte, maxFileBytes+1)
	for i := range pad {
		pad[i] = ' '
	}
	body := `{"new_greeting": true,` + string(pad) + `"x": true}`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	p := FileConfigProvider(path)
	if p.IsEnabled("new_greeting") {
		t.Fatal("oversized file must be rejected and resolve off")
	}
}

// TestFileProviderUnderCapStillReads proves the cap does not reject a normal,
// under-cap file (guards against an over-eager cap).
func TestFileProviderUnderCapStillReads(t *testing.T) {
	p := FileConfigProvider(writeFlagFile(t, `{"new_greeting": true}`))
	if !p.IsEnabled("new_greeting") {
		t.Fatal("an under-cap file must still be read")
	}
}
