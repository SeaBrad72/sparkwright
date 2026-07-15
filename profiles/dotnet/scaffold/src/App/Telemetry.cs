using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace App;

// Pure telemetry primitives — spans, bounded-cardinality Prometheus metrics, and
// correlated JSON logs. The importable core the app host calls per request.
//
// Mirrors the go/python references (telemetry.go / telemetry.py): OTel-semantic
// spans in the exact scripts/otel-trace.sh schema, Prometheus text exposition, and
// structured logs — deliberately dependency-light (BCL-only) and free of any
// socket/handler code so the logic is unit-tested here and the I/O surface (the
// host) is wired separately. Sinks are chosen by env, exactly like the reference:
// spans go to OTEL_TRACE_FILE if set (append) else stdout; logs carry SERVICE_NAME
// (default "reference-app").
public static class Telemetry
{
    // KnownMethods is the bounded label set. An unknown (or non-canonical) method is
    // bucketed as "other" so a hostile caller cannot explode Prometheus series
    // cardinality (path is intentionally NEVER a label).
    private static readonly HashSet<string> KnownMethods = new(StringComparer.Ordinal)
    {
        "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
    };

    // Module-level counter state, guarded by MetricsLock. Reset via ResetMetrics()
    // for lifecycle/test isolation.
    private static readonly object MetricsLock = new();
    private static readonly Dictionary<(string Method, int Status), long> RequestsTotal = new();
    private static double durationSecondsTotal;

    /// <summary>Returns a fresh (traceId, spanId): 16-byte and 8-byte cryptographic hex.</summary>
    public static (string TraceId, string SpanId) NewSpanIds() =>
        (RandomHex(16), RandomHex(8));

    private static string RandomHex(int byteCount)
    {
        var bytes = RandomNumberGenerator.GetBytes(byteCount);
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    /// <summary>
    /// Builds an OTel-semantic span dict in the reference otel-trace.sh schema.
    ///
    /// *_unix_nano are emitted as decimal STRINGS (OTLP/JSON represents them as
    /// strings, avoiding the float precision loss unix nanos, ~1.8e18, would incur).
    /// status.code is ERROR for &gt;= 500, else OK. A fresh trace/span id is minted
    /// and parent_span_id is null (root span); the host correlates via attributes.
    /// </summary>
    public static Dictionary<string, object?> BuildSpan(
        string name,
        long startUnixNano,
        long endUnixNano,
        IReadOnlyDictionary<string, string> attributes,
        int statusCode)
    {
        var (traceId, spanId) = NewSpanIds();
        var code = statusCode >= 500 ? "ERROR" : "OK";
        return new Dictionary<string, object?>
        {
            ["trace_id"] = traceId,
            ["span_id"] = spanId,
            ["parent_span_id"] = null,
            ["name"] = name,
            ["start_unix_nano"] = startUnixNano.ToString(CultureInfo.InvariantCulture),
            ["end_unix_nano"] = endUnixNano.ToString(CultureInfo.InvariantCulture),
            ["attributes"] = attributes,
            ["status"] = new Dictionary<string, object?> { ["code"] = code },
        };
    }

    /// <summary>
    /// Writes the span as one JSON line to OTEL_TRACE_FILE (append) if set, else
    /// stdout. Degrades silently on any sink error — telemetry must never break the
    /// request path it observes.
    /// </summary>
    public static void EmitSpan(IReadOnlyDictionary<string, object?> span)
    {
        string line;
        try
        {
            line = JsonSerializer.Serialize(span);
        }
        catch (NotSupportedException)
        {
            return;
        }

        var sink = Environment.GetEnvironmentVariable("OTEL_TRACE_FILE");
        if (!string.IsNullOrEmpty(sink))
        {
            TryAppendLine(sink, line);
            return;
        }

        Console.WriteLine(line);
    }

#pragma warning disable CA1031 // Do not catch general exception types — telemetry must never break the request path.
    private static void TryAppendLine(string path, string line)
    {
        try
        {
            File.AppendAllText(path, line + "\n", Encoding.UTF8);
        }
        catch (Exception)
        {
            // Sink unavailable (missing dir, permissions, disk full, ...) — swallow.
        }
    }
#pragma warning restore CA1031

    /// <summary>
    /// Increments the request counter for (methodLabel, status) and adds to the
    /// duration total. methodLabel is the method when in KnownMethods, else "other"
    /// (bounded cardinality). The shared counter state is guarded by MetricsLock.
    /// </summary>
    public static void RecordMetric(string? method, int status, double latencyMs)
    {
        var label = method is not null && KnownMethods.Contains(method) ? method : "other";
        var key = (label, status);
        lock (MetricsLock)
        {
            RequestsTotal[key] = RequestsTotal.GetValueOrDefault(key) + 1;
            durationSecondsTotal += latencyMs / 1000.0;
        }
    }

    /// <summary>
    /// Escapes a Prometheus label value per the text exposition spec (\, ", \n).
    /// Defensive: an unusual value can never break a series line or inject one.
    /// </summary>
    private static string EscapeLabelValue(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
             .Replace("\"", "\\\"", StringComparison.Ordinal)
             .Replace("\n", "\\n", StringComparison.Ordinal);

    /// <summary>
    /// Renders the two counters as Prometheus text exposition (trailing newline).
    /// Series are emitted in a stable (method, status) order so the output is
    /// deterministic despite Dictionary's unordered enumeration.
    /// </summary>
    public static string RenderMetrics()
    {
        KeyValuePair<(string Method, int Status), long>[] entries;
        double duration;
        lock (MetricsLock)
        {
            entries = RequestsTotal.ToArray();
            duration = durationSecondsTotal;
        }

        Array.Sort(entries, (a, b) =>
        {
            var byMethod = string.CompareOrdinal(a.Key.Method, b.Key.Method);
            return byMethod != 0 ? byMethod : a.Key.Status.CompareTo(b.Key.Status);
        });

        var sb = new StringBuilder();
        sb.Append("# HELP http_requests_total Total number of HTTP requests handled.\n");
        sb.Append("# TYPE http_requests_total counter\n");
        foreach (var entry in entries)
        {
            sb.Append("http_requests_total{method=\"")
              .Append(EscapeLabelValue(entry.Key.Method))
              .Append("\",status=\"")
              .Append(entry.Key.Status.ToString(CultureInfo.InvariantCulture))
              .Append("\"} ")
              .Append(entry.Value.ToString(CultureInfo.InvariantCulture))
              .Append('\n');
        }

        sb.Append("# HELP http_request_duration_seconds_total ")
          .Append("Total accumulated request duration in seconds.\n");
        sb.Append("# TYPE http_request_duration_seconds_total counter\n");
        sb.Append("http_request_duration_seconds_total ")
          .Append(duration.ToString("G", CultureInfo.InvariantCulture))
          .Append('\n');

        return sb.ToString();
    }

    /// <summary>Clears the module-level counter state (lifecycle/test helper).</summary>
    public static void ResetMetrics()
    {
        lock (MetricsLock)
        {
            RequestsTotal.Clear();
            durationSecondsTotal = 0.0;
        }
    }

    /// <summary>
    /// Emits one structured JSON log line to stdout: ts (RFC3339 UTC), level "info",
    /// service (SERVICE_NAME env, default "reference-app"), plus the merged fields.
    ///
    /// Never pass request bodies, headers, or PII/secrets in fields.
    /// </summary>
    public static void Log(IReadOnlyDictionary<string, object?> fields)
    {
        var service = Environment.GetEnvironmentVariable("SERVICE_NAME");
        if (string.IsNullOrEmpty(service))
        {
            service = "reference-app";
        }

        var record = new Dictionary<string, object?>
        {
            ["ts"] = DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            ["level"] = "info",
            ["service"] = service,
        };
        foreach (var (key, value) in fields)
        {
            record[key] = value;
        }

        Console.WriteLine(JsonSerializer.Serialize(record));
    }
}
