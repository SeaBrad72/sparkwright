using System.Text.Json;

namespace App;

// Reference LIVE flag provider — a file-config FlagProvider that reflects changes
// WITHOUT a restart (dotnet profile).
//
// This is the reference implementation of the live slot in the flags seam: it
// re-reads a JSON flag file on every resolution, so rewriting the file flips
// behaviour in the SAME running process (a live runtime flip, not the env floor's
// restart-to-toggle). A SaaS provider (OpenFeature / Unleash / LaunchDarkly) is an
// adopter-pluggable alternative implementing the same FlagProvider — swap it in via
// Flags.SetProvider() with no change to callers of Flags.IsEnabled().
//
// TRUST BOUNDARY: the path is APP-CONFIGURED (an operator-controlled deploy
// artifact), NOT end-user input. The file CONTENT is still treated as untrusted (it
// can be corrupted/tampered), so resolution is fully fail-safe and injection-safe:
//
//   - fail-safe: a missing / unreadable / unparseable / oversized / DEEPLY-NESTED
//     file, a non-object payload (array/null/scalar), a non-bool value, or a flag
//     absent from the file all fall back to the registry default (OFF). Resolution
//     never throws and never enables on ANY file content. The byte cap is enforced
//     via a bounded read (TOCTOU-safe: it caps the bytes pulled into memory
//     regardless of a racing stat/rewrite), so a huge/tampered file can never be
//     slurped in. A deeply-nested payload trips System.Text.Json's max-depth guard
//     (a JsonException, caught here) — a tamperer cannot turn "flip a flag" into
//     "crash the resolver" (the DoS class the Slice-2 python review caught, there a
//     RecursionError).
//   - no injection: forbidden keys (__proto__/constructor/prototype and dunder-ish
//     keys) are rejected outright; only the SPECIFIC flag key is read — the parsed
//     JSON is NEVER spread/merged into anything.
//   - strict coercion: only the JSON boolean true enables (a "true" string, 1, etc.
//     stay OFF — mirrors the env floor's strict == "true").
//
// PERFORMANCE CAVEAT: this provider does a SYNCHRONOUS file read on EVERY IsEnabled
// call. That is fine for a kill-switch and for the shipped default (the env floor
// does no FS read at all), but a profile/adopter that wires the file provider onto a
// HOT request path should add an mtime-gated cache.

/// <summary>
/// A file-config <see cref="FlagProvider"/> that re-reads a JSON file per call so a
/// rewrite flips behaviour with no restart. File content is untrusted; resolution is
/// fully fail-safe OFF.
/// </summary>
public sealed class FileConfigProvider : FlagProvider
{
    // 1 MiB cap. A flag file is tiny (a handful of booleans); 1 MiB is very generous.
    // The cap bounds memory so an oversized or tampered file can never be slurped in.
    private const int MaxFileBytes = 1 << 20;

    // Names that must never be resolved from file data (builtin-shadowing / pollution vectors).
    private static readonly HashSet<string> ForbiddenKeys =
        new(StringComparer.Ordinal) { "__proto__", "constructor", "prototype" };

    private readonly string path;

    /// <summary>Create a provider whose IsEnabled re-reads <paramref name="path"/> per call.</summary>
    public FileConfigProvider(string path) => this.path = path;

    /// <summary>
    /// Resolve name from the file, fully fail-safe: any error, oversize, non-object,
    /// missing key, non-bool, or forbidden key falls back to the registry default (OFF).
    /// </summary>
    public bool IsEnabled(string name)
    {
        var fallback = Flags.RegistryDefault(name);

        // Reject dunder-ish / pollution keys outright — never resolved from file data.
        if (ForbiddenKeys.Contains(name) ||
            (name.StartsWith("__", StringComparison.Ordinal) && name.EndsWith("__", StringComparison.Ordinal)))
        {
            return fallback;
        }

        if (!TryReadCapped(this.path, out var data))
        {
            return fallback;
        }

        try
        {
            using var doc = JsonDocument.Parse(data);
            // Only a JSON object can carry flags; arrays/null/scalars fall back.
            if (doc.RootElement.ValueKind != JsonValueKind.Object)
            {
                return fallback;
            }
            // Read the SPECIFIC key — never spread the untrusted object anywhere.
            if (!doc.RootElement.TryGetProperty(name, out var value))
            {
                return fallback;
            }
            // Strict: only a JSON boolean true enables (a "true" string, 1, etc. stay OFF).
            return value.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            // Malformed or deeply-nested (max-depth) payload -> OFF, never throw, never enable.
            return fallback;
        }
    }

    // TryReadCapped reads at most MaxFileBytes, rejecting anything larger. The bound is
    // TOCTOU-safe: it caps the bytes pulled into memory regardless of a racing rewrite.
    // Returns false on any I/O error or oversize — the caller treats that as fail-safe OFF.
#pragma warning disable CA1031 // Do not catch general exception types — fail-safe requires swallowing ALL I/O faults.
    private static bool TryReadCapped(string path, out byte[] data)
    {
        data = Array.Empty<byte>();
        try
        {
            using var stream = new FileStream(
                path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

            var buffer = new byte[MaxFileBytes + 1];
            var total = 0;
            int read;
            while (total < buffer.Length &&
                   (read = stream.Read(buffer, total, buffer.Length - total)) > 0)
            {
                total += read;
            }

            if (total > MaxFileBytes)
            {
                return false;
            }

            data = buffer.AsSpan(0, total).ToArray();
            return true;
        }
        catch (Exception)
        {
            // missing / unreadable / locked / any I/O fault -> fail-safe OFF.
            return false;
        }
    }
#pragma warning restore CA1031
}
