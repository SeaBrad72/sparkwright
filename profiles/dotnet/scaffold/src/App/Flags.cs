namespace App;

// Feature-flag registry + resolver SEAM — the kit's kill-switch (dotnet profile).
//
// A typed flag module whose default is OFF, so an unset / unknown / malformed value
// can never silently enable a feature (fail-safe). This module is a PROVIDER SEAM
// (the shape the whole profile fan-out replicates):
//
//   - the FLOOR provider (envProvider) is env-driven and restart-to-toggle —
//     dark-launch + a real kill-switch, but NOT a live runtime flip;
//   - a pluggable live slot (SetProvider) accepts any FlagProvider — e.g. the
//     reference file-config live provider (FileConfigProvider, flips WITHOUT a
//     restart) or an adopter's SaaS provider (OpenFeature/Unleash/LaunchDarkly)
//     implementing the same interface.
//
// The public API stays IsEnabled(name) and delegates to whichever provider is
// active. Adding a flag = one entry in Registry (the single place to enumerate live
// flags, so retiring one is a known list, not a code hunt).

/// <summary>
/// The seam contract every provider (env floor, file-config, SaaS) implements.
/// Public so an adopter can plug in their own provider. Deliberately NOT named
/// <c>IFlagProvider</c> — the STACK-PARITY gate greps for the literal token
/// <c>FlagProvider</c>.
/// </summary>
#pragma warning disable CA1715 // Identifiers should have correct prefix — parity gate requires the exact name "FlagProvider".
public interface FlagProvider
#pragma warning restore CA1715
{
    /// <summary>Resolve a flag by name; fail-safe OFF on anything ambiguous.</summary>
    bool IsEnabled(string name);
}

/// <summary>Feature-flag registry + provider seam. Default OFF; strict; fail-safe.</summary>
public static class Flags
{
    // The single typed registry — the one place flags are enumerated. Default OFF:
    // a name absent here (or stored false) can never resolve truthy.
    internal static readonly IReadOnlyDictionary<string, bool> Registry =
        new Dictionary<string, bool>(StringComparer.Ordinal) { ["new_greeting"] = false };

    // envProvider is the env floor — the default active provider. The literal token
    // "envProvider" must appear in non-comment code (STACK-PARITY parity gate).
    internal static readonly FlagProvider envProvider = new EnvProvider();

    // The pluggable seam. Default = the env floor; a live provider is installed by
    // SetProvider(). Guarded by a lock because SetProvider/ResetProvider/IsEnabled
    // touch this shared static from multiple threads (integration tests hit it
    // concurrently). A null active provider (defensive) resolves OFF, never throws.
    private static readonly object ProviderLock = new();
    private static FlagProvider? activeProvider = envProvider;

    /// <summary>snake_case flag -> FEATURE_-prefixed SCREAMING_SNAKE env var name.</summary>
    internal static string EnvName(string name) => "FEATURE_" + name.ToUpperInvariant();

    /// <summary>
    /// Own-key-only, strict-boolean fallback. A name that is not a registry key
    /// (incl. dunder-ish collisions like __class__/constructor) must NOT resolve
    /// truthy — fail-safe OFF, not open. Only a registry key stored exactly true enables.
    /// </summary>
    internal static bool RegistryDefault(string name) =>
        Registry.TryGetValue(name, out var value) && value;

    /// <summary>Install a live provider into the seam (e.g. the file-config live provider).</summary>
    public static void SetProvider(FlagProvider? provider)
    {
        lock (ProviderLock)
        {
            activeProvider = provider;
        }
    }

    /// <summary>Restore the env floor as the active provider.</summary>
    public static void ResetProvider()
    {
        lock (ProviderLock)
        {
            activeProvider = envProvider;
        }
    }

    /// <summary>Public API — delegates to the active provider under the lock; null -> OFF.</summary>
    public static bool IsEnabled(string name)
    {
        FlagProvider? provider;
        lock (ProviderLock)
        {
            provider = activeProvider;
        }
        return provider?.IsEnabled(name) ?? false;
    }

    /// <summary>
    /// The FLOOR provider: env-driven, restart-to-toggle, fail-safe OFF. True ONLY
    /// when the env var is exactly "true"; otherwise the registry default (OFF).
    /// "TRUE"/"1"/"yes" do NOT enable (strict parse).
    /// </summary>
    private sealed class EnvProvider : FlagProvider
    {
        public bool IsEnabled(string name)
        {
            var raw = Environment.GetEnvironmentVariable(EnvName(name));
            return raw is null ? RegistryDefault(name) : raw == "true";
        }
    }
}
