using System.Text;
using Xunit;

// UTF-8 without a BOM — a leading BOM is not valid JSON per RFC 8259 and is not what
// an operator's flag file looks like.

namespace App.Tests;

/// <summary>
/// Unit tests for the reference LIVE file-config provider — the tamper-safe,
/// fail-safe-OFF kill switch. Shares the "Flags" collection because the live-flip
/// test installs a provider into the process-global seam.
/// </summary>
[Collection("Flags")]
public class LiveProviderTests : IDisposable
{
    private readonly string tempFile;

    public LiveProviderTests()
    {
        tempFile = Path.Combine(Path.GetTempPath(), $"flags-{Guid.NewGuid():N}.json");
    }

    public void Dispose()
    {
        if (File.Exists(tempFile))
        {
            File.Delete(tempFile);
        }
        GC.SuppressFinalize(this);
    }

    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    private void WriteFile(string contents) => File.WriteAllText(tempFile, contents, Utf8NoBom);

    [Fact]
    public void LiveFlip_RewritingFile_FlipsWithoutRestart_ViaSeam()
    {
        Environment.SetEnvironmentVariable("FEATURE_NEW_GREETING", null);
        WriteFile("{\"new_greeting\": true}");
        Flags.SetProvider(new FileConfigProvider(tempFile));
        try
        {
            Assert.True(Flags.IsEnabled("new_greeting"));

            // Rewrite the file mid-process — no restart, no SetProvider re-call.
            WriteFile("{\"new_greeting\": false}");
            Assert.False(Flags.IsEnabled("new_greeting"));
        }
        finally
        {
            Flags.ResetProvider();
        }
    }

    [Fact]
    public void JsonBooleanTrue_Enables()
    {
        WriteFile("{\"new_greeting\": true}");
        Assert.True(new FileConfigProvider(tempFile).IsEnabled("new_greeting"));
    }

    [Theory]
    [InlineData("{\"new_greeting\": false}")]   // explicit false
    [InlineData("{\"new_greeting\": \"true\"}")] // string, not bool -> OFF
    [InlineData("{\"new_greeting\": 1}")]        // number -> OFF
    [InlineData("{\"new_greeting\": null}")]     // null -> OFF
    [InlineData("{\"other\": true}")]            // missing key -> OFF
    [InlineData("{}")]                            // empty object -> OFF
    [InlineData("[1, 2, 3]")]                    // non-object (array) -> OFF
    [InlineData("true")]                          // non-object (scalar) -> OFF
    [InlineData("null")]                          // non-object (null) -> OFF
    [InlineData("{ not valid json")]             // malformed -> OFF
    public void NonEnablingContent_ResolvesOff(string contents)
    {
        WriteFile(contents);
        Assert.False(new FileConfigProvider(tempFile).IsEnabled("new_greeting"));
    }

    [Fact]
    public void MissingFile_ResolvesOff()
    {
        var provider = new FileConfigProvider(Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.json"));
        Assert.False(provider.IsEnabled("new_greeting"));
    }

    [Theory]
    [InlineData("__proto__")]
    [InlineData("constructor")]
    [InlineData("prototype")]
    [InlineData("__dunder__")]
    public void ForbiddenKeys_RejectedOutright(string key)
    {
        // Even when the file explicitly sets the forbidden key true, it never resolves on.
        WriteFile($"{{\"{key}\": true}}");
        Assert.False(new FileConfigProvider(tempFile).IsEnabled(key));
    }

    [Fact]
    public void OversizedFile_RejectedByByteCap()
    {
        // Valid JSON that enables the flag, but padded past the 1 MiB cap -> rejected -> OFF.
        var padding = new string('x', (1 << 20) + 1024);
        WriteFile($"{{\"new_greeting\": true, \"pad\": \"{padding}\"}}");
        Assert.False(new FileConfigProvider(tempFile).IsEnabled("new_greeting"));
    }

    [Fact]
    public void DeeplyNestedPayload_DoesNotCrash_ResolvesOff()
    {
        // A deeply-nested payload trips System.Text.Json's max-depth guard (JsonException).
        // The provider must catch it and fail safe, not crash the resolver (a DoS of the kill switch).
        var depth = 500;
        var sb = new StringBuilder();
        sb.Append("{\"new_greeting\":");
        for (var i = 0; i < depth; i++)
        {
            sb.Append('[');
        }
        sb.Append('1');
        for (var i = 0; i < depth; i++)
        {
            sb.Append(']');
        }
        sb.Append('}');
        WriteFile(sb.ToString());

        Assert.False(new FileConfigProvider(tempFile).IsEnabled("new_greeting"));
    }
}
