using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

// Integration: the flag seam + telemetry wiring THROUGH the running host.
//
// Unlike the unit tests (Flags/Dispatch in isolation), here the flag registry, the
// instrumented pipeline, and the real HTTP layer are exercised together against a
// WebApplicationFactory<Program> in-memory host in the SAME process — so coverlet
// measures AppServer.cs. Mirrors the go reference integration_test.go and the python
// reference tests/integration/test_greeting.py. The live-flip case is the
// load-bearing proof that the provider seam reaches the REAL endpoint with no restart.

namespace App.Tests;

/// <summary>
/// End-to-end-through-the-host tests for the server spine. Shares the "Flags"
/// collection because they mutate the process-global flag seam + env vars, so they
/// must never run in parallel with the other flag/server suites.
/// </summary>
[Collection("Flags")]
public sealed class GreetingIntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    // The four security headers stamped on EVERY response.
    private static readonly IReadOnlyDictionary<string, string> ExpectedSecurityHeaders =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["X-Content-Type-Options"] = "nosniff",
            ["X-Frame-Options"] = "DENY",
            ["Content-Security-Policy"] = "default-src 'none'",
            ["Referrer-Policy"] = "no-referrer",
        };

    private readonly WebApplicationFactory<Program> factory;

    public GreetingIntegrationTests(WebApplicationFactory<Program> factory) => this.factory = factory;

    private static void ClearGreetingEnv() =>
        Environment.SetEnvironmentVariable("FEATURE_NEW_GREETING", null);

    private async Task<(int Status, string Body, string? ContentType)> GetAsync(string path)
    {
        using var client = this.factory.CreateClient();
        using var resp = await client.GetAsync(path);
        var body = await resp.Content.ReadAsStringAsync();
        return ((int)resp.StatusCode, body, resp.Content.Headers.ContentType?.MediaType);
    }

    private async Task<HttpResponseMessage> SendAsync(
        HttpMethod method, string path, IReadOnlyDictionary<string, string>? headers = null)
    {
        var client = this.factory.CreateClient();
        using var req = new HttpRequestMessage(method, path);
        if (headers is not null)
        {
            foreach (var (name, value) in headers)
            {
                req.Headers.TryAddWithoutValidation(name, value);
            }
        }

        var resp = await client.SendAsync(req);
        client.Dispose();
        return resp;
    }

    private static void AssertSecurityHeadersExactlyOnceAndNeutralServer(HttpResponseMessage resp)
    {
        foreach (var (name, value) in ExpectedSecurityHeaders)
        {
            Assert.True(resp.Headers.TryGetValues(name, out var values), $"missing header {name}");
            var list = values!.ToList();
            Assert.Single(list);
            Assert.Equal(value, list[0]);
        }

        Assert.True(resp.Headers.TryGetValues("Server", out var server));
        var serverList = server!.ToList();
        Assert.Single(serverList);
        Assert.Equal("reference-app", serverList[0]); // no framework/version leak
    }

    [Fact]
    public async Task Greeting_FlagOff_ServesDefault()
    {
        ClearGreetingEnv();
        Flags.ResetProvider();
        try
        {
            var (status, body, ctype) = await this.GetAsync("/greeting");
            Assert.Equal(200, status);
            Assert.Equal("application/json", ctype);
            Assert.Equal("{\"greeting\":\"Hello, world!\"}", body);
        }
        finally
        {
            Flags.ResetProvider();
        }
    }

    [Fact]
    public async Task Greeting_FlagOn_ServesNew()
    {
        Environment.SetEnvironmentVariable("FEATURE_NEW_GREETING", "true");
        Flags.ResetProvider();
        try
        {
            var (status, body, _) = await this.GetAsync("/greeting");
            Assert.Equal(200, status);
            Assert.Equal("{\"greeting\":\"Hello, world! (new)\"}", body);
        }
        finally
        {
            ClearGreetingEnv();
            Flags.ResetProvider();
        }
    }

    [Fact]
    public async Task Healthz_ReturnsOk()
    {
        var (status, body, _) = await this.GetAsync("/healthz");
        Assert.Equal(200, status);
        Assert.Equal("{\"status\":\"ok\"}", body);
    }

    [Fact]
    public async Task Metrics_ExposesPrometheusCounter()
    {
        _ = await this.GetAsync("/greeting"); // record at least one request
        var (status, body, _) = await this.GetAsync("/metrics");
        Assert.Equal(200, status);
        Assert.Contains("http_requests_total", body, StringComparison.Ordinal);
    }

    /// <summary>
    /// ★ ENDPOINT-LEVEL LIVE FLIP — the load-bearing wiring proof. Install the
    /// file-config provider, then rewrite the SAME flag file and observe /greeting
    /// flip on the SAME running host with NO restart. Proves the seam flips the REAL
    /// endpoint, not a side process.
    /// </summary>
    [Fact]
    public async Task Greeting_LiveFlip_OnSameRunningServer()
    {
        ClearGreetingEnv();
        var flagFile = Path.Combine(Path.GetTempPath(), $"flags-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(flagFile, "{\"new_greeting\":false}");
        Flags.SetProvider(new FileConfigProvider(flagFile));
        try
        {
            var (_, bodyOff, _) = await this.GetAsync("/greeting");
            Assert.Equal("{\"greeting\":\"Hello, world!\"}", bodyOff);

            // Rewrite the SAME file — no host restart between these two GETs.
            await File.WriteAllTextAsync(flagFile, "{\"new_greeting\":true}");
            var (_, bodyOn, _) = await this.GetAsync("/greeting");
            Assert.Equal("{\"greeting\":\"Hello, world! (new)\"}", bodyOn);
        }
        finally
        {
            Flags.ResetProvider();
            File.Delete(flagFile);
        }
    }

    [Fact]
    public async Task Get_CarriesSecurityHeadersExactlyOnce_AndNeutralServer()
    {
        using var resp = await this.SendAsync(HttpMethod.Get, "/healthz");
        Assert.Equal(200, (int)resp.StatusCode);
        AssertSecurityHeadersExactlyOnceAndNeutralServer(resp);
    }

    [Theory]
    [InlineData("POST")]
    [InlineData("PUT")]
    [InlineData("DELETE")]
    [InlineData("PATCH")]
    [InlineData("OPTIONS")]
    public async Task NonGet_Returns404_WithSecurityHeaders(string method)
    {
        using var resp = await this.SendAsync(new HttpMethod(method), "/greeting");
        Assert.Equal(404, (int)resp.StatusCode);
        var body = await resp.Content.ReadAsStringAsync();
        Assert.Equal("{\"error\":\"not found\"}", body);
        AssertSecurityHeadersExactlyOnceAndNeutralServer(resp);
    }

    [Fact]
    public async Task Head_Returns404_HeadersWithoutBody()
    {
        using var resp = await this.SendAsync(HttpMethod.Head, "/healthz");
        Assert.Equal(404, (int)resp.StatusCode);
        var body = await resp.Content.ReadAsStringAsync();
        Assert.Equal(string.Empty, body);
        foreach (var name in ExpectedSecurityHeaders.Keys)
        {
            Assert.True(resp.Headers.Contains(name), $"HEAD missing security header {name}");
        }
    }

    // LastSpanRequestId polls the trace file for the emitted span, returning its
    // request_id attribute. Telemetry is emitted AFTER the response is written, so poll.
    private static async Task<string> LastSpanRequestIdAsync(string traceFile)
    {
        var deadline = DateTime.UtcNow.AddSeconds(2);
        while (DateTime.UtcNow < deadline)
        {
            if (File.Exists(traceFile))
            {
                var text = await File.ReadAllTextAsync(traceFile);
                var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
                if (lines.Length > 0)
                {
                    using var doc = JsonDocument.Parse(lines[^1]);
                    if (doc.RootElement.TryGetProperty("attributes", out var attrs) &&
                        attrs.TryGetProperty("request_id", out var id))
                    {
                        return id.GetString() ?? string.Empty;
                    }
                }
            }

            await Task.Delay(10);
        }

        throw new Xunit.Sdk.XunitException("no span was emitted to the trace file within the timeout");
    }

    [Fact]
    public async Task ValidInboundRequestId_IsEchoedIntoSpan()
    {
        var traceFile = Path.Combine(Path.GetTempPath(), $"trace-{Guid.NewGuid():N}.jsonl");
        Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", traceFile);
        try
        {
            const string validId = "abc-123_valid.ID";
            using var resp = await this.SendAsync(
                HttpMethod.Get, "/healthz",
                new Dictionary<string, string> { ["X-Request-Id"] = validId });
            Assert.Equal(200, (int)resp.StatusCode);
            Assert.Equal(validId, await LastSpanRequestIdAsync(traceFile));
        }
        finally
        {
            Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", null);
            if (File.Exists(traceFile))
            {
                File.Delete(traceFile);
            }
        }
    }

    [Fact]
    public async Task OversizedInboundRequestId_IsReplaced()
    {
        var traceFile = Path.Combine(Path.GetTempPath(), $"trace-{Guid.NewGuid():N}.jsonl");
        Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", traceFile);
        try
        {
            var bad = new string('x', 129);
            using var resp = await this.SendAsync(
                HttpMethod.Get, "/healthz",
                new Dictionary<string, string> { ["X-Request-Id"] = bad });
            Assert.Equal(200, (int)resp.StatusCode);
            var minted = await LastSpanRequestIdAsync(traceFile);
            Assert.NotEqual(bad, minted);
            Assert.Equal(32, minted.Length); // 16 random bytes -> 32 hex chars
        }
        finally
        {
            Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", null);
            if (File.Exists(traceFile))
            {
                File.Delete(traceFile);
            }
        }
    }

    [Fact]
    public void ConfigureProvider_WithFlagFile_InstallsLiveProvider()
    {
        var flagFile = Path.Combine(Path.GetTempPath(), $"cfg-{Guid.NewGuid():N}.json");
        File.WriteAllText(flagFile, "{\"new_greeting\":true}");
        Environment.SetEnvironmentVariable("FLAG_FILE", flagFile);
        ClearGreetingEnv();
        try
        {
            AppServer.ConfigureProvider();
            Assert.True(Flags.IsEnabled("new_greeting")); // file provider is live
        }
        finally
        {
            Environment.SetEnvironmentVariable("FLAG_FILE", null);
            Flags.ResetProvider();
            File.Delete(flagFile);
        }
    }

    [Fact]
    public void ConfigureProvider_WithoutFlagFile_LeavesEnvFloor()
    {
        Environment.SetEnvironmentVariable("FLAG_FILE", null);
        ClearGreetingEnv();
        Flags.ResetProvider();
        try
        {
            AppServer.ConfigureProvider();
            Assert.False(Flags.IsEnabled("new_greeting")); // env floor, default OFF
        }
        finally
        {
            Flags.ResetProvider();
        }
    }
}
