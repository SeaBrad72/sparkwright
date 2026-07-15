package main

// Feature-flag registry + resolver SEAM — the kit's kill-switch (Go profile).
//
// A typed, stdlib-only flag module whose default is OFF, so an unset / unknown /
// malformed value can never silently enable a feature (fail-safe). This module is a
// PROVIDER SEAM (the shape the whole profile fan-out replicates):
//
//   - the FLOOR provider (envProvider) is env-driven and restart-to-toggle —
//     dark-launch + a real kill-switch, but NOT a live runtime flip;
//   - a pluggable live slot (SetProvider) accepts any FlagProvider — e.g. the
//     reference file-config live provider (live_provider.go, flips WITHOUT a
//     restart) or an adopter's SaaS provider (OpenFeature/Unleash/LaunchDarkly)
//     implementing the same interface.
//
// The public API stays IsEnabled(name) and delegates to whichever provider is
// active. Adding a flag = one entry in flags (the single place to enumerate live
// flags, so retiring one is a known list, not a code hunt).

import (
	"os"
	"strings"
	"sync"
)

// flags is the single typed registry — the one place flags are enumerated.
// Default OFF: a name absent here (or stored false) can never resolve truthy.
var flags = map[string]bool{"new_greeting": false}

// FlagProvider is the seam contract every provider (env floor, file-config, SaaS)
// implements. Exported so an adopter can plug in their own provider.
type FlagProvider interface {
	IsEnabled(name string) bool
}

// envName maps a snake_case flag to a FEATURE_-prefixed SCREAMING_SNAKE env var:
// new_greeting -> FEATURE_NEW_GREETING.
func envName(name string) string {
	return "FEATURE_" + strings.ToUpper(name)
}

// registryDefault is the own-key-only, strict-boolean fallback. A name that is
// not a registry key (incl. dunder-ish collisions like __class__/constructor)
// must NOT resolve truthy — fail-safe OFF, not open. Only a registry key whose
// stored value is exactly true enables.
func registryDefault(name string) bool {
	v, ok := flags[name]
	return ok && v
}

// envFlagProvider is the FLOOR provider: env-driven, restart-to-toggle, fail-safe
// OFF. True ONLY when the env var is exactly "true"; otherwise the registry
// default (OFF). "TRUE"/"1"/"yes" do NOT enable (strict parse).
type envFlagProvider struct{}

func (envFlagProvider) IsEnabled(name string) bool {
	raw, ok := os.LookupEnv(envName(name))
	if !ok {
		return registryDefault(name)
	}
	return raw == "true"
}

// envProvider is the env floor — the default active provider installed below.
var envProvider FlagProvider = envFlagProvider{}

// The pluggable seam. Default = the env floor; a live provider is installed by
// SetProvider(). Guarded by a RWMutex because SetProvider/ResetProvider/IsEnabled
// touch this shared package var from multiple goroutines (integration tests).
var (
	providerMu     sync.RWMutex
	activeProvider = envProvider
)

// SetProvider installs a live provider into the seam (e.g. the file-config live
// provider). A nil provider is tolerated and fails safe OFF at resolution time.
func SetProvider(provider FlagProvider) {
	providerMu.Lock()
	defer providerMu.Unlock()
	activeProvider = provider
}

// ResetProvider restores the env floor as the active provider.
func ResetProvider() {
	providerMu.Lock()
	defer providerMu.Unlock()
	activeProvider = envProvider
}

// IsEnabled is the public API — delegates to the active provider under a read
// lock. A nil active provider (defensive) resolves OFF rather than panicking.
func IsEnabled(name string) bool {
	providerMu.RLock()
	provider := activeProvider
	providerMu.RUnlock()
	if provider == nil {
		return false
	}
	return provider.IsEnabled(name)
}
