using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

// E2E: a full user journey against the assembled service.
//
// Liveness -> the greeting feature -> a not-found route, proving end-to-end behaviour
// in-suite. DISTINCT from post-deploy scripts/smoke.sh (which proves a deployed
// container is alive); this is the runnable in-process oracle. Mirrors the go
// reference e2e_test.go and the python reference tests/e2e/test_journey.py.

namespace App.Tests;

/// <summary>
/// A single happy-path journey through the running host. Shares the "Flags"
/// collection so it never races the flag/server suites over the process-global seam.
/// </summary>
[Collection("Flags")]
public sealed class JourneyE2eTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> factory;

    public JourneyE2eTests(WebApplicationFactory<Program> factory) => this.factory = factory;

    private async Task<(int Status, string Body)> GetAsync(HttpClient client, string path)
    {
        using var resp = await client.GetAsync(path);
        return ((int)resp.StatusCode, await resp.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task ServiceJourney_LivenessThenGreetingThen404()
    {
        Environment.SetEnvironmentVariable("FEATURE_NEW_GREETING", null);
        Flags.ResetProvider();
        using var client = this.factory.CreateClient();
        try
        {
            var (liveStatus, liveBody) = await this.GetAsync(client, "/healthz");
            Assert.Equal(200, liveStatus);
            Assert.Equal("{\"status\":\"ok\"}", liveBody);

            var (greetStatus, greetBody) = await this.GetAsync(client, "/greeting");
            Assert.Equal(200, greetStatus);
            Assert.StartsWith("{\"greeting\":\"Hello, world!", greetBody, StringComparison.Ordinal);

            var (missStatus, missBody) = await this.GetAsync(client, "/nope");
            Assert.Equal(404, missStatus);
            Assert.Equal("{\"error\":\"not found\"}", missBody);
        }
        finally
        {
            Flags.ResetProvider();
        }
    }
}
