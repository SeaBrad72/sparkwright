package main

import (
	"os"
	"testing"
)

// unsetForTest clears an env var for the duration of the current test body.
// Callers first register a t.Setenv so the harness restores the original on
// cleanup; this then removes it so the "unset" code path is exercised.
func unsetForTest(key string) error {
	return os.Unsetenv(key)
}

// TestRegistryDefaultOff proves the shipped default is OFF: the one registered
// flag resolves false and an unknown name resolves false (fail-safe, not open).
func TestRegistryDefault(t *testing.T) {
	cases := []struct {
		name string
		flag string
		want bool
	}{
		{"registered flag defaults off", "new_greeting", false},
		{"unknown name is off", "not_a_flag", false},
		{"dunder-ish collision is off", "__class__", false},
		{"builtin-ish collision is off", "constructor", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := registryDefault(tc.flag); got != tc.want {
				t.Fatalf("registryDefault(%q) = %v, want %v", tc.flag, got, tc.want)
			}
		})
	}
}

// TestEnvName proves the snake_case -> FEATURE_SCREAMING_SNAKE mapping.
func TestEnvName(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"new_greeting", "FEATURE_NEW_GREETING"},
		{"x", "FEATURE_X"},
	}
	for _, tc := range cases {
		if got := envName(tc.in); got != tc.want {
			t.Errorf("envName(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// TestEnvProviderStrictParse proves the env floor enables ONLY on the exact
// string "true"; TRUE/1/yes/empty do NOT enable; unset falls to the registry.
func TestEnvProviderStrictParse(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		set  bool
		want bool
	}{
		{"exact true enables", "true", true, true},
		{"uppercase TRUE stays off", "TRUE", true, false},
		{"numeric 1 stays off", "1", true, false},
		{"yes stays off", "yes", true, false},
		{"empty stays off", "", true, false},
		{"unset falls to registry default (off)", "", false, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.set {
				t.Setenv(envName("new_greeting"), tc.raw)
			} else {
				// Ensure the var is absent for this subtest.
				t.Setenv(envName("new_greeting"), "sentinel")
				if err := unsetForTest(envName("new_greeting")); err != nil {
					t.Fatalf("unset: %v", err)
				}
			}
			if got := envProvider.IsEnabled("new_greeting"); got != tc.want {
				t.Fatalf("envProvider.IsEnabled = %v, want %v", got, tc.want)
			}
		})
	}
}

// TestEnvProviderUnknownName proves an env override on a NON-registry name never
// enables via the floor's unset path (own-key-only through registryDefault).
func TestEnvProviderUnknownName(t *testing.T) {
	if envProvider.IsEnabled("not_a_flag") {
		t.Fatal("unknown flag enabled via env floor")
	}
}

// TestPublicIsEnabledDelegates proves the public API delegates to the active
// provider (env floor by default) and honours a strict "true".
func TestPublicIsEnabledDelegates(t *testing.T) {
	t.Setenv(envName("new_greeting"), "true")
	if !IsEnabled("new_greeting") {
		t.Fatal("IsEnabled should reflect the env floor")
	}
}

// TestSetAndResetProvider proves the seam is pluggable and resets to the floor.
func TestSetAndResetProvider(t *testing.T) {
	t.Cleanup(ResetProvider)
	SetProvider(stubProvider{result: true})
	if !IsEnabled("new_greeting") {
		t.Fatal("installed provider not consulted")
	}
	if !IsEnabled("anything") {
		t.Fatal("installed provider should answer for any name")
	}
	ResetProvider()
	// After reset, the floor governs: no env set -> off.
	if err := unsetForTest(envName("new_greeting")); err != nil {
		t.Fatalf("unset: %v", err)
	}
	if IsEnabled("new_greeting") {
		t.Fatal("ResetProvider did not restore the env floor")
	}
}

// TestSetProviderNilFailsSafe proves a nil provider never panics and resolves OFF.
func TestSetProviderNilFailsSafe(t *testing.T) {
	t.Cleanup(ResetProvider)
	SetProvider(nil)
	if IsEnabled("new_greeting") {
		t.Fatal("nil provider must fail safe OFF")
	}
}

// stubProvider is a trivial in-memory provider for seam tests.
type stubProvider struct{ result bool }

func (s stubProvider) IsEnabled(string) bool { return s.result }
