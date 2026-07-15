using System.Text.Json;
using Xunit;

namespace App.Tests;

/// <summary>
/// Unit tests for the telemetry primitives (spans, bounded-cardinality metrics,
/// structured logs). The metric-counter tests mutate PROCESS-GLOBAL state (the
/// shared counter maps + OTEL_TRACE_FILE / SERVICE_NAME env vars), so this class
/// shares one xUnit collection to run serially and never race other collections.
/// </summary>
[Collection("Telemetry")]
public class TelemetryTests
{
    public TelemetryTests()
    {
        Telemetry.ResetMetrics();
    }

    // ---- NewSpanIds ----------------------------------------------------

    [Fact]
    public void NewSpanIds_ReturnsHexOfExpectedLength()
    {
        var (traceId, spanId) = Telemetry.NewSpanIds();

        Assert.Equal(32, traceId.Length); // 16 bytes -> 32 hex chars
        Assert.Equal(16, spanId.Length); // 8 bytes -> 16 hex chars
        Assert.Matches("^[0-9a-f]+$", traceId);
        Assert.Matches("^[0-9a-f]+$", spanId);
    }

    [Fact]
    public void NewSpanIds_AreFreshEachCall()
    {
        var (trace1, span1) = Telemetry.NewSpanIds();
        var (trace2, span2) = Telemetry.NewSpanIds();

        Assert.NotEqual(trace1, trace2);
        Assert.NotEqual(span1, span2);
    }

    // ---- BuildSpan -------------------------------------------------------

    [Fact]
    public void BuildSpan_EmitsNanoFieldsAsStrings()
    {
        var span = Telemetry.BuildSpan(
            "GET /healthz", 1_700_000_000_000_000_000L, 1_700_000_000_123_000_000L,
            new Dictionary<string, string>(), 200);

        Assert.IsType<string>(span["start_unix_nano"]);
        Assert.IsType<string>(span["end_unix_nano"]);
        Assert.Equal("1700000000000000000", span["start_unix_nano"]);
        Assert.Equal("1700000000123000000", span["end_unix_nano"]);
    }

    [Theory]
    [InlineData(200, "OK")]
    [InlineData(404, "OK")]
    [InlineData(499, "OK")]
    [InlineData(500, "ERROR")]
    [InlineData(503, "ERROR")]
    public void BuildSpan_StatusCodeBoundaryAt500(int statusCode, string expectedCode)
    {
        var span = Telemetry.BuildSpan("GET /x", 1, 2, new Dictionary<string, string>(), statusCode);

        var status = Assert.IsType<Dictionary<string, object?>>(span["status"]);
        Assert.Equal(expectedCode, status["code"]);
    }

    [Fact]
    public void BuildSpan_IsRootSpan_WithNullParent()
    {
        var span = Telemetry.BuildSpan("GET /x", 1, 2, new Dictionary<string, string>(), 200);

        Assert.True(span.ContainsKey("parent_span_id"));
        Assert.Null(span["parent_span_id"]);
    }

    [Fact]
    public void BuildSpan_CarriesNameAndAttributes()
    {
        var attrs = new Dictionary<string, string> { ["http.method"] = "GET" };
        var span = Telemetry.BuildSpan("GET /healthz", 1, 2, attrs, 200);

        Assert.Equal("GET /healthz", span["name"]);
        Assert.Same(attrs, span["attributes"]);
    }

    [Fact]
    public void BuildSpan_MintsFreshTraceAndSpanIds()
    {
        var span1 = Telemetry.BuildSpan("a", 1, 2, new Dictionary<string, string>(), 200);
        var span2 = Telemetry.BuildSpan("a", 1, 2, new Dictionary<string, string>(), 200);

        Assert.NotEqual(span1["trace_id"], span2["trace_id"]);
        Assert.NotEqual(span1["span_id"], span2["span_id"]);
    }

    // ---- EmitSpan ----------------------------------------------------------

    [Fact]
    public void EmitSpan_WritesJsonLineToTraceFile_WhenEnvSet()
    {
        var path = Path.Combine(Path.GetTempPath(), $"otel-trace-{Guid.NewGuid():N}.ndjson");
        Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", path);
        try
        {
            var span = Telemetry.BuildSpan("GET /x", 1, 2, new Dictionary<string, string>(), 200);
            Telemetry.EmitSpan(span);
            Telemetry.EmitSpan(span);

            var lines = File.ReadAllLines(path);
            Assert.Equal(2, lines.Length);
            using var doc = JsonDocument.Parse(lines[0]);
            Assert.Equal("GET /x", doc.RootElement.GetProperty("name").GetString());
        }
        finally
        {
            Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", null);
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
    }

    [Fact]
    public void EmitSpan_AppendsAcrossCalls()
    {
        var path = Path.Combine(Path.GetTempPath(), $"otel-trace-{Guid.NewGuid():N}.ndjson");
        Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", path);
        try
        {
            File.WriteAllText(path, string.Empty);
            var span = Telemetry.BuildSpan("a", 1, 2, new Dictionary<string, string>(), 200);
            Telemetry.EmitSpan(span);
            Telemetry.EmitSpan(span);
            Telemetry.EmitSpan(span);

            Assert.Equal(3, File.ReadAllLines(path).Length);
        }
        finally
        {
            Environment.SetEnvironmentVariable("OTEL_TRACE_FILE", null);
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
    }

    // ---- RecordMetric / RenderMetrics --------------------------------------

    [Fact]
    public void RecordMetric_KnownMethod_UsesMethodLabel()
    {
        Telemetry.RecordMetric("GET", 200, 12.5);

        var text = Telemetry.RenderMetrics();
        Assert.Contains("http_requests_total{method=\"GET\",status=\"200\"} 1", text);
    }

    [Theory]
    [InlineData("TRACE")]
    [InlineData("get")]
    [InlineData("")]
    [InlineData(null)]
    public void RecordMetric_UnknownOrNonCanonicalMethod_BucketsAsOther(string? method)
    {
        Telemetry.RecordMetric(method, 200, 1.0);

        var text = Telemetry.RenderMetrics();
        Assert.Contains("http_requests_total{method=\"other\",status=\"200\"} 1", text);
    }

    [Fact]
    public void RecordMetric_AccumulatesDuration()
    {
        Telemetry.RecordMetric("GET", 200, 100.0);
        Telemetry.RecordMetric("GET", 200, 250.0);

        var text = Telemetry.RenderMetrics();
        Assert.Contains("http_request_duration_seconds_total 0.35", text);
    }

    [Fact]
    public void RecordMetric_SameKeyIncrementsCount()
    {
        Telemetry.RecordMetric("POST", 201, 1.0);
        Telemetry.RecordMetric("POST", 201, 1.0);
        Telemetry.RecordMetric("POST", 201, 1.0);

        var text = Telemetry.RenderMetrics();
        Assert.Contains("http_requests_total{method=\"POST\",status=\"201\"} 3", text);
    }

    [Fact]
    public void RenderMetrics_ContainsHelpAndTypeLines()
    {
        var text = Telemetry.RenderMetrics();

        Assert.Contains("# HELP http_requests_total", text);
        Assert.Contains("# TYPE http_requests_total counter", text);
        Assert.Contains("# HELP http_request_duration_seconds_total", text);
        Assert.Contains("# TYPE http_request_duration_seconds_total counter", text);
    }

    [Fact]
    public void RenderMetrics_EndsWithTrailingNewline()
    {
        var text = Telemetry.RenderMetrics();

        Assert.EndsWith("\n", text);
    }

    [Fact]
    public void RenderMetrics_EscapesLabelValues()
    {
        // A hostile/unusual method value still can't break a series line — but the
        // bounded-cardinality bucket means anything unknown collapses to "other",
        // which itself needs no escaping. Directly exercise the escape path via a
        // value that DOES land in the known set is impossible (known methods have
        // no special chars), so this asserts the "other" bucket renders safely for
        // an attacker-supplied method containing quote/backslash/newline.
        Telemetry.RecordMetric("GET\"\\\n", 200, 1.0);

        var text = Telemetry.RenderMetrics();
        Assert.Contains("http_requests_total{method=\"other\",status=\"200\"} 1", text);
        Assert.DoesNotContain("GET\"\\", text);
    }

    [Fact]
    public void ResetMetrics_ClearsCounterState()
    {
        Telemetry.RecordMetric("GET", 200, 100.0);
        Telemetry.ResetMetrics();

        var text = Telemetry.RenderMetrics();
        Assert.DoesNotContain("http_requests_total{method=\"GET\"", text);
        Assert.Contains("http_request_duration_seconds_total 0", text);
    }

    // ---- Log ----------------------------------------------------------------

    [Fact]
    public void Log_WritesValidJsonLine_WithTsLevelService()
    {
        Environment.SetEnvironmentVariable("SERVICE_NAME", null);
        var writer = new StringWriter();
        var original = Console.Out;
        Console.SetOut(writer);
        try
        {
            Telemetry.Log(new Dictionary<string, object?> { ["route"] = "/healthz" });
        }
        finally
        {
            Console.SetOut(original);
        }

        var line = writer.ToString().TrimEnd('\r', '\n');
        using var doc = JsonDocument.Parse(line);
        var root = doc.RootElement;

        Assert.Equal("info", root.GetProperty("level").GetString());
        Assert.Equal("reference-app", root.GetProperty("service").GetString());
        Assert.Equal("/healthz", root.GetProperty("route").GetString());
        Assert.True(DateTimeOffset.TryParse(root.GetProperty("ts").GetString(), out _));
    }

    [Fact]
    public void Log_UsesServiceNameEnvVar_WhenSet()
    {
        Environment.SetEnvironmentVariable("SERVICE_NAME", "custom-svc");
        var writer = new StringWriter();
        var original = Console.Out;
        Console.SetOut(writer);
        try
        {
            Telemetry.Log(new Dictionary<string, object?>());
        }
        finally
        {
            Console.SetOut(original);
            Environment.SetEnvironmentVariable("SERVICE_NAME", null);
        }

        var line = writer.ToString().TrimEnd('\r', '\n');
        using var doc = JsonDocument.Parse(line);
        Assert.Equal("custom-svc", doc.RootElement.GetProperty("service").GetString());
    }
}
