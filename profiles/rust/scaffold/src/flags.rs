//! Feature-flag registry + resolver SEAM — the kit's kill-switch (Rust profile).
//!
//! A typed, std-only flag module whose default is OFF, so an unset / unknown /
//! malformed value can never silently enable a feature (fail-safe). This module is
//! a PROVIDER SEAM (the shape the whole profile fan-out replicates):
//!
//!   - the FLOOR provider ([`env_provider`]) is env-driven and restart-to-toggle —
//!     dark-launch + a real kill-switch, but NOT a live runtime flip;
//!   - a pluggable live slot ([`set_provider`]) accepts any [`FlagProvider`] — e.g.
//!     the reference file-config live provider (`live_provider`, flips WITHOUT a
//!     restart) or an adopter's SaaS provider (OpenFeature/Unleash/LaunchDarkly)
//!     implementing the same trait.
//!
//! The public API stays [`is_enabled`] and delegates to whichever provider is
//! active. Adding a flag = one entry in [`FLAGS`] (the single place to enumerate
//! live flags, so retiring one is a known list, not a code hunt).

use std::sync::{OnceLock, RwLock};

/// The single typed registry — the one place flags are enumerated. Default OFF: a
/// name absent here (or stored `false`) can never resolve truthy.
const FLAGS: &[(&str, bool)] = &[("new_greeting", false)];

/// The seam contract every provider (env floor, file-config, SaaS) implements.
/// Exported so an adopter can plug in their own provider.
pub trait FlagProvider {
    fn is_enabled(&self, name: &str) -> bool;
}

/// Maps a snake_case flag to a `FEATURE_`-prefixed SCREAMING_SNAKE env var:
/// `new_greeting` -> `FEATURE_NEW_GREETING`.
fn env_name(name: &str) -> String {
    format!("FEATURE_{}", name.to_ascii_uppercase())
}

/// The own-key-only, strict-boolean fallback. A name that is not a registry key
/// (incl. dunder-ish collisions like `__class__`/`constructor`) must NOT resolve
/// truthy — fail-safe OFF, not open. Only a registry key whose stored value is
/// exactly `true` enables. Shared with the live file provider.
pub(crate) fn registry_default(name: &str) -> bool {
    FLAGS
        .iter()
        .find(|(key, _)| *key == name)
        .map(|(_, value)| *value)
        .unwrap_or(false)
}

/// The FLOOR provider: env-driven, restart-to-toggle, fail-safe OFF. True ONLY
/// when the env var is exactly `"true"`; otherwise the registry default (OFF).
/// `"TRUE"`/`"1"`/`"yes"` do NOT enable (strict parse).
pub struct EnvProvider;

impl FlagProvider for EnvProvider {
    fn is_enabled(&self, name: &str) -> bool {
        match std::env::var(env_name(name)) {
            Ok(raw) => raw == "true",
            Err(_) => registry_default(name),
        }
    }
}

/// The env floor — the default active provider. Named for the seam contract so a
/// caller can construct the floor explicitly.
pub fn env_provider() -> EnvProvider {
    EnvProvider
}

/// The pluggable seam slot. Default = the env floor; a live provider is installed
/// by [`set_provider`]. An `RwLock` guards the shared slot because
/// `set_provider`/`reset_provider`/`is_enabled` touch it from multiple threads
/// (integration tests hit it concurrently); reads run concurrently.
fn active_provider() -> &'static RwLock<Box<dyn FlagProvider + Send + Sync>> {
    static SLOT: OnceLock<RwLock<Box<dyn FlagProvider + Send + Sync>>> = OnceLock::new();
    SLOT.get_or_init(
        || RwLock::new(Box::new(env_provider()) as Box<dyn FlagProvider + Send + Sync>),
    )
}

/// Installs a live provider into the seam (e.g. the file-config live provider). A
/// poisoned lock is tolerated — the install is skipped and resolution keeps
/// failing safe.
pub fn set_provider(provider: Box<dyn FlagProvider + Send + Sync>) {
    if let Ok(mut slot) = active_provider().write() {
        *slot = provider;
    }
}

/// Restores the env floor as the active provider.
pub fn reset_provider() {
    if let Ok(mut slot) = active_provider().write() {
        *slot = Box::new(env_provider());
    }
}

/// The public API — delegates to the active provider under a read lock. A poisoned
/// lock resolves OFF rather than panicking (fail-safe).
pub fn is_enabled(name: &str) -> bool {
    match active_provider().read() {
        Ok(slot) => slot.is_enabled(name),
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Serializes tests that mutate process-global state (the env var + the shared
    // provider slot) so parallel test threads don't interfere. Poison-tolerant.
    static GUARD: Mutex<()> = Mutex::new(());

    fn lock() -> std::sync::MutexGuard<'static, ()> {
        GUARD.lock().unwrap_or_else(|e| e.into_inner())
    }

    struct AlwaysOn;
    impl FlagProvider for AlwaysOn {
        fn is_enabled(&self, _name: &str) -> bool {
            true
        }
    }

    #[test]
    fn env_name_prefixes_and_uppercases() {
        assert_eq!(env_name("new_greeting"), "FEATURE_NEW_GREETING");
    }

    #[test]
    fn registry_default_off_and_own_key_only() {
        assert!(!registry_default("new_greeting")); // registry stores false
        assert!(!registry_default("unknown_flag")); // not a key -> OFF
        assert!(!registry_default("__class__")); // dunder-ish collision -> OFF
    }

    #[test]
    fn default_resolves_off() {
        let _g = lock();
        std::env::remove_var("FEATURE_NEW_GREETING");
        reset_provider();
        assert!(!is_enabled("new_greeting"));
    }

    #[test]
    fn env_floor_strict_true_only() {
        let _g = lock();
        let p = env_provider();
        for value in ["TRUE", "True", "1", "yes", "false", "", " true"] {
            std::env::set_var("FEATURE_NEW_GREETING", value);
            assert!(
                !p.is_enabled("new_greeting"),
                "value {value:?} must not enable"
            );
        }
        std::env::set_var("FEATURE_NEW_GREETING", "true");
        assert!(p.is_enabled("new_greeting"));
        std::env::remove_var("FEATURE_NEW_GREETING");
    }

    #[test]
    fn env_floor_own_key_only_default() {
        let _g = lock();
        // With no env override, an unknown flag falls to the registry default —
        // which is own-key-only, so it never enables. (An explicit env override is
        // the operator's dark-launch opt-in and is exercised separately.)
        std::env::remove_var("FEATURE_UNKNOWN_FLAG");
        let p = env_provider();
        assert!(!p.is_enabled("unknown_flag"));
    }

    #[test]
    fn provider_swap_and_reset() {
        let _g = lock();
        std::env::remove_var("FEATURE_NEW_GREETING");
        reset_provider();
        assert!(!is_enabled("new_greeting"));

        set_provider(Box::new(AlwaysOn));
        assert!(is_enabled("new_greeting"));
        assert!(is_enabled("anything")); // the live provider is authoritative

        reset_provider();
        assert!(!is_enabled("new_greeting"));
    }
}
