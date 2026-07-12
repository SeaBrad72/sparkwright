# Observability — local trace backend (reference)

This stack emits OTel-semantic spans per request (see `src/server.ts`) that the kit's
`scripts/otlp-export.sh` converts to OTLP/JSON and POSTs to any OTLP backend.

## See your traces locally (Jaeger)

```sh
# 1) Run a local Jaeger (OTLP/HTTP ingest on 4318, query UI/API on 16686)
docker run -d --name jaeger -e COLLECTOR_OTLP_ENABLED=true -p 4318:4318 -p 16686:16686 \
  jaegertracing/all-in-one

# 2) Boot the app, capture its emitted spans, and POST them to Jaeger
docker logs <your-app-container> 2>&1 | grep -F '"trace_id"' > spans.ndjson
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export.sh spans.ndjson

# 3) Find the trace — open the UI at http://localhost:16686, or query the API:
curl "http://localhost:16686/api/traces/<trace_id>"
```

## Use your own backend (vendor-neutral)

The export path speaks standard OTLP/HTTP. Point it at any backend by setting the
endpoint (and auth headers, if any) — Grafana Tempo, Honeycomb, Grafana Cloud, Datadog, etc.:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=https://your-backend.example \
OTEL_EXPORTER_OTLP_HEADERS="x-api-key=..." \
  sh scripts/otlp-export.sh spans.ndjson
```

`otlp-export.sh` never echoes header values and rejects header-injection attempts. The
local Jaeger config above is a dev/CI reference, not a production backend.
