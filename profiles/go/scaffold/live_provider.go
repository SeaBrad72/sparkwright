package main

// Reference LIVE flag provider — a file-config FlagProvider that reflects changes
// WITHOUT a restart (Go profile).
//
// This is the reference implementation of the live slot in the flags seam: it
// re-reads a JSON flag file on every resolution, so rewriting the file flips
// behaviour in the SAME running process (a live runtime flip, not the env floor's
// restart-to-toggle). A SaaS provider (OpenFeature / Unleash / LaunchDarkly) is an
// adopter-pluggable alternative implementing the same FlagProvider — swap it in
// via SetProvider() with no change to callers of IsEnabled().
//
// TRUST BOUNDARY: path is APP-CONFIGURED (an operator-controlled deploy artifact),
// NOT end-user input. The file CONTENT is still treated as untrusted (it can be
// corrupted/tampered), so resolution is fully fail-safe and injection-safe:
//
//   - fail-safe: a missing / unreadable / unparseable / oversized / DEEPLY-NESTED
//     file, a non-object payload (array/null/scalar), a non-bool value, or a flag
//     absent from the file all fall back to the registry default (OFF). Resolution
//     never panics and never enables on ANY file content. The byte cap is enforced
//     via io.LimitReader (TOCTOU-safe: it bounds the read regardless of a racing
//     stat), so a huge/tampered file can never be slurped into memory — stronger
//     than a stat-only cap. A deeply-nested payload is rejected by encoding/json's
//     own nesting-depth limit (the scanner errors before recursing onto the stack),
//     so a tamperer cannot turn "flip a flag" into "crash the resolver" — the DoS
//     class the Python Slice-2 review caught (there a RecursionError); regression-
//     locked by TestFileProviderFailSafe/deeply-nested.
//   - no injection: forbiddenKeys (__proto__/constructor/prototype and dunder-ish
//     keys) are rejected outright; only the SPECIFIC flag key is read — the parsed
//     JSON is NEVER spread/merged into anything.
//   - strict coercion: only the JSON boolean true enables (a "true" string, 1, etc.
//     stay OFF — mirrors the env floor's strict == "true").
//
// PERFORMANCE CAVEAT: this provider does a SYNCHRONOUS file read on EVERY
// IsEnabled call. That is fine for a kill-switch and for the shipped default (the
// env floor does no FS read at all), but a profile/adopter that wires the file
// provider onto a HOT request path should add an mtime-gated cache.

import (
	"encoding/json"
	"io"
	"os"
	"strings"
)

// maxFileBytes caps the flag file read at 1 MiB. A flag file is tiny (a handful
// of booleans); 1 MiB is very generous. The cap bounds memory so an oversized or
// tampered file can never be slurped in.
const maxFileBytes = 1 << 20

// forbiddenKeys are names that must never be resolved from file data
// (builtin-shadowing / prototype-pollution vectors).
var forbiddenKeys = map[string]bool{
	"__proto__":   true,
	"constructor": true,
	"prototype":   true,
}

// fileConfigProvider re-reads a JSON file per IsEnabled call (the live flip).
type fileConfigProvider struct {
	path string
}

// FileConfigProvider returns a provider whose IsEnabled re-reads path per call,
// so rewriting the file flips behaviour with no restart. Content is untrusted.
func FileConfigProvider(path string) FlagProvider {
	return fileConfigProvider{path: path}
}

// IsEnabled resolves name from the file, fully fail-safe: any error, oversize,
// non-object, missing key, non-bool, or forbidden key falls back to the registry
// default (OFF). It never panics.
func (p fileConfigProvider) IsEnabled(name string) bool {
	fallback := registryDefault(name)

	// Reject dunder-ish / pollution keys outright — never resolved from file data.
	if forbiddenKeys[name] || (strings.HasPrefix(name, "__") && strings.HasSuffix(name, "__")) {
		return fallback
	}

	data, ok := readCapped(p.path)
	if !ok {
		return fallback
	}

	// Decode into raw messages so we read ONLY the specific key — the untrusted
	// object is never spread/merged into anything. A non-object payload
	// (array/scalar) fails to decode -> fallback. (JSON null decodes to a nil map,
	// which then reports the key absent -> fallback.)
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(data, &obj); err != nil {
		return fallback
	}
	raw, present := obj[name]
	if !present {
		return fallback
	}

	// Strict: only a JSON boolean enables. A "true" string, 1, null, or object
	// fails to unmarshal into bool -> fallback; only literal true returns true.
	var value bool
	if err := json.Unmarshal(raw, &value); err != nil {
		return fallback
	}
	return value
}

// readCapped opens path and reads at most maxFileBytes, rejecting anything larger.
// The io.LimitReader(f, maxFileBytes+1) bound is TOCTOU-safe: it caps the bytes
// pulled into memory regardless of a racing stat/rewrite. Returns (nil, false) on
// any error or oversize — the caller treats that as fail-safe OFF.
func readCapped(path string) ([]byte, bool) {
	// #nosec G304 -- path is an app-configured operator artifact, not end-user
	// input; its CONTENT is treated as untrusted and the read is byte-capped below.
	f, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer func() { _ = f.Close() }()

	data, err := io.ReadAll(io.LimitReader(f, maxFileBytes+1))
	if err != nil {
		return nil, false
	}
	if len(data) > maxFileBytes {
		return nil, false
	}
	return data, true
}
