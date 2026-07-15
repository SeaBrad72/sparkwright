using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;

namespace App;

// App server spine — wires the flags + telemetry modules into the running host.
//
// The fuller counterpart to Health: a terminal request pipeline that serves the real
// endpoints (/healthz, /metrics, /greeting, 404), stamps security headers on EVERY
// response, and emits per-request telemetry (a structured log, a bounded-cardinality
// metric, and an OTel-semantic span). Mirrors the go reference server.go and the
// python reference src/app/server.py.
//
// Routing is done here (method + path), NOT via ASP.NET endpoint routing: the
// contract requires any non-GET to yield a hardened JSON 404 (not the framework's
// 405), and HEAD to return headers with no body — the same method-agnostic posture as
// the go/python references. Health.Status()'s pure core is called (not
// re-implemented); the flag seam + telemetry primitives are assembled here — the ONE
// place the profile wires them. Program.cs stays the thin socket-binding boot
// (excluded from coverage); this handler logic is covered by the integration + e2e
// suites (the host runs in-process via WebApplicationFactory).
public static partial class AppServer
{
    // Stamped on every response — a hardened baseline for a JSON/text API that serves
    // no markup: block sniffing/framing, deny all subresources, leak no referrer.
    private static readonly IReadOnlyDictionary<string, string> SecurityHeaders =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["X-Content-Type-Options"] = "nosniff",
            ["X-Frame-Options"] = "DENY",
            ["Content-Security-Policy"] = "default-src 'none'",
            ["Referrer-Policy"] = "no-referrer",
        };

    // The compact 404 body, precomputed (a fixed constant).
    private static readonly byte[] NotFoundBody =
        Encoding.UTF8.GetBytes("{\"error\":\"not found\"}");

    // Honor an inbound X-Request-Id ONLY if it is a safe, bounded token; else mint one.
    // Bounding the length + charset rejects malformed/oversized ids defensively — an
    // unbounded inbound header must never flow into a log/span attribute verbatim.
    [GeneratedRegex("^[A-Za-z0-9._-]{1,128}$")]
    private static partial Regex RequestIdRegex();

    // Compact JSON (no inter-token spaces) — matches the go/python reference bytes. The
    // fixed single-key payloads carry no HTML metacharacters, so the default encoder
    // never escapes and the bytes match the reference server EXACTLY.
    private static readonly JsonSerializerOptions CompactJson = new(JsonSerializerDefaults.Web);

    private static byte[] Json(IReadOnlyDictionary<string, string> payload) =>
        JsonSerializer.SerializeToUtf8Bytes(payload, CompactJson);

    /// <summary>
    /// Route the request (query stripped) -> (status, contentType, body). Only GET is
    /// routed; every other method (incl. HEAD) falls through to a hardened JSON 404 so
    /// it too carries security headers + telemetry via the pipeline.
    /// </summary>
    public static (int Status, string ContentType, byte[] Body) Dispatch(string method, string path)
    {
        if (!string.Equals(method, "GET", StringComparison.Ordinal))
        {
            return (404, "application/json", NotFoundBody);
        }

        switch (path)
        {
            case "/healthz":
                return (200, "application/json", Json((IReadOnlyDictionary<string, string>)Health.Status()));
            case "/metrics":
                return (200, "text/plain; version=0.0.4", Encoding.UTF8.GetBytes(Telemetry.RenderMetrics()));
            case "/greeting":
                var greeting = Flags.IsEnabled("new_greeting") ? "Hello, world! (new)" : "Hello, world!";
                return (200, "application/json",
                    Json(new Dictionary<string, string>(StringComparer.Ordinal) { ["greeting"] = greeting }));
            default:
                return (404, "application/json", NotFoundBody);
        }
    }

    /// <summary>Return a validated inbound X-Request-Id, or a freshly minted random id.</summary>
    public static string ResolveRequestId(string? inbound)
    {
        if (inbound is not null && RequestIdRegex().IsMatch(inbound))
        {
            return inbound;
        }

        var (traceId, _) = Telemetry.NewSpanIds(); // 16 random bytes -> 32 hex chars (no uuid dep)
        return traceId;
    }

    /// <summary>
    /// The terminal request handler: route + write + per-request telemetry, for ANY
    /// method. Security headers + the neutral Server header are stamped in ONE place so
    /// even a 404 / non-GET / HEAD carries them exactly once. Telemetry is emitted
    /// AFTER the response is written (mirroring the reference res.finish posture).
    /// </summary>
    public static async Task HandleAsync(HttpContext context)
    {
        var startNano = UnixNanoNow();
        var startTimestamp = System.Diagnostics.Stopwatch.GetTimestamp();

        var method = context.Request.Method;
        var path = context.Request.Path.HasValue ? context.Request.Path.Value! : "/";
        var requestId = ResolveRequestId(context.Request.Headers["X-Request-Id"]);

        var (status, contentType, body) = Dispatch(method, path);

        var response = context.Response;
        foreach (var (name, value) in SecurityHeaders)
        {
            response.Headers[name] = value; // indexer assignment => exactly once
        }

        response.Headers["Server"] = "reference-app"; // no framework/version leak
        response.StatusCode = status;
        response.ContentType = contentType;

        var withBody = !string.Equals(method, "HEAD", StringComparison.Ordinal);
        response.ContentLength = withBody ? body.Length : 0;
        if (withBody)
        {
            await response.Body.WriteAsync(body);
        }

        var elapsed = System.Diagnostics.Stopwatch.GetElapsedTime(startTimestamp);
        var latencyMs = elapsed.TotalMilliseconds;
        var spanName = method + " " + path; // query stripped (cardinality + secret hygiene)
        var rawTarget = path + context.Request.QueryString.Value;

        // NOTE: `path` below is the request target INCLUDING any query string. The
        // reference app's routes carry no secrets, but an adopter whose query params can
        // carry tokens/secrets MUST redact it before logging (the span name strips it).
        Telemetry.Log(new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["request_id"] = requestId,
            ["method"] = method,
            ["path"] = rawTarget,
            ["status"] = status,
            ["latency_ms"] = latencyMs,
        });
        Telemetry.RecordMetric(method, status, latencyMs);
        Telemetry.EmitSpan(Telemetry.BuildSpan(
            spanName,
            startNano,
            startNano + (long)elapsed.TotalMilliseconds * 1_000_000L,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["http.request.method"] = method,
                ["http.response.status_code"] = status.ToString(CultureInfo.InvariantCulture),
                ["request_id"] = requestId,
            },
            status));
    }

    /// <summary>
    /// FLAG_FILE boot gate (the load-bearing live-flip wiring): when FLAG_FILE is set,
    /// install the file-config live provider so the running host's /greeting reflects
    /// live file flips with no restart. Unset -> the env floor (default). Called once
    /// at boot (Program.cs); kept here so the wiring is unit-testable.
    /// </summary>
    public static void ConfigureProvider()
    {
        var flagFile = Environment.GetEnvironmentVariable("FLAG_FILE");
        if (!string.IsNullOrEmpty(flagFile))
        {
            Flags.SetProvider(new FileConfigProvider(flagFile));
        }
    }

    private static long UnixNanoNow()
    {
        var now = DateTimeOffset.UtcNow;
        return (now.UtcTicks - DateTimeOffset.UnixEpoch.UtcTicks) * 100L; // 1 tick = 100 ns
    }
}
