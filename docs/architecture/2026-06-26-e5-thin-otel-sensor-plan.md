# E5-thin — OTel-shaped orchestrator trace → real scorecard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the operate-loop sensor on real, non-fixture data — a reference orchestrator stand-in emits an OTel-shaped span tree that flows through a thin adapter into the unchanged scorecard, and (opt-in) exports to any OTLP backend.

**Architecture:** Four new zero-dep sh+jq reference scripts (emitter / stand-in / adapter / OTLP exporter) off one pluggable sink; the proven `agent-scorecard.sh` is untouched. A control-plane conformance lock + golden-path behaviour job prove the emit→score loop runs non-vacuously. AMBER slice: agent-editable scripts/docs land on the feature branch directly; the control-plane changes + version finishing are materialised by `apply.py` (built and dry-run on a clone, applied by the human).

**Tech Stack:** POSIX sh, `jq`, `curl`, `/dev/urandom` (ids), `date` (timestamps), GitHub Actions (golden-path proof), Python 3 (apply.py).

## Global Constraints

- **Zero new runtime dependencies** — sh + jq + curl only (mirror `scripts/agent-trace.sh`). No OTel SDK.
- **Never hand-build JSON in sh** — always `jq -n`. Untrusted attribute/name values must not break the envelope.
- **Filename path-safety** — any `run.id`/span name used in a path is slugged `tr -c 'A-Za-z0-9._-' '_'` (mirror `agent-trace.sh:187`).
- **No apostrophes inside single-quoted jq programs** (sh-quoting trap that has bitten prior slices).
- **Portable timestamps/ids** — macOS `date` has no `%N`; provide a fallback. `/dev/urandom`+`od` for ids.
- **Span shape is OTel-semantic** — `trace_id`, `span_id`, `parent_span_id`, `name`, `start_unix_nano`, `end_unix_nano`, `attributes` (object), `status.code` (`OK`/`ERROR`). One span per NDJSON line.
- **`agent-scorecard.sh` is UNCHANGED** — verified by its existing `--selftest` still passing.
- **Honest claim** — "OTel-shaped" + "produces/POSTs valid OTLP", NOT "proven against a live vendor backend".
- **Version finishing is folded into `apply.py`** — VERSION 3.50.0 → **3.51.0**, README badge, CHANGELOG, ROADMAP.
- **Control-plane edits** (`conformance/**`, `.github/workflows/**`, `conformance/claims.tsv`, `conformance/verify.sh`) happen ONLY via `apply.py`; the agent dry-runs it on a clone with `KIT_GUARD_SELFEDIT=1`.

---

## File Structure

| File | Responsibility | Control-plane? |
|------|----------------|----------------|
| `scripts/otel-trace.sh` | OTel-shaped span emitter; pluggable sink; `--selftest` | No (agent-editable) |
| `scripts/orchestrator-trace-demo.sh` | Labelled stand-in emitting root + 3 child spans (incl. one denied) | No |
| `scripts/otel-to-scorecard.sh` | Adapter: OTel spans → MP-3a records; `--selftest` | No |
| `scripts/otlp-export.sh` | NDJSON → OTLP/JSON resourceSpans → POST `$OTEL_EXPORTER_OTLP_ENDPOINT`; `--selftest` | No |
| `scripts/fixtures/otel-trace-sample.ndjson` | Fixture for adapter + exporter selftests | No |
| `docs/operations/agentic-ops.md` | Extended: OTLP integration section + env vars | No |
| `conformance/agentops-sensor-wired.sh` | Behaviour lock (3 selftests + golden-path job present) | **Yes → apply.py** |
| `conformance/claims.tsv` | New `agentops-sensor` claim row | **Yes → apply.py** |
| `conformance/verify.sh` | `check control agentops-sensor …` line | **Yes → apply.py** |
| `.github/workflows/golden-path.yml` | `agentops-sensor` job (non-vacuous proof) | **Yes → apply.py** |
| `.github/workflows/drift-watch.yml` | already runs `verify.sh --require` — no edit unless it enumerates | **Yes → apply.py if needed** |
| `scripts/doctor.sh` | optional `--full` info line for the sensor | **Yes → apply.py if edited** |
| `VERSION`, `README.md`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md` | release finishing | No (but written by apply.py) |

**Tasks 1–5** build the agent-editable scripts/docs on the feature branch (TDD via `--selftest`, real commits). **Task 6** authors `apply.py` in scratchpad (control-plane + version finishing). **Task 7** dry-runs + full verify on a clone. Review + human apply follow the plan.

---

### Task 1: OTel-shaped span emitter (`scripts/otel-trace.sh`)

**Files:**
- Create: `scripts/otel-trace.sh`
- Test: in-script `--selftest`

**Interfaces:**
- Produces (consumed by Tasks 2–4):
  - `otel-trace.sh new-trace` → prints a new 32-hex `trace_id`.
  - `otel-trace.sh span --trace ID --name NAME [--parent SPAN_ID] [--attr k=v ...] [--status OK|ERROR] [--start NANO] [--end NANO] [--sink FILE]` → emits one OTel span line to the sink (default `$OTEL_TRACE_FILE` or stdout), prints the new `span_id`.
  - Env `OTEL_TRACE_FILE` = default sink path.

- [ ] **Step 1: Write the failing selftest**

Append a `selftest()` to the script (write the dispatch first so `--selftest` routes). Assertions:

```sh
selftest() {
  st_fail=0
  tid=$(new_trace)
  [ "$(printf '%s' "$tid" | wc -c | tr -d ' ')" = "32" ] || { echo "FAIL: trace_id not 32 hex"; st_fail=1; }
  sink=$(mktemp)
  root=$(OTEL_TRACE_FILE="$sink" emit_span "$tid" "orchestrator-run" "" "OK" "" "" "agent.id=orchestrator")
  child=$(OTEL_TRACE_FILE="$sink" emit_span "$tid" "agent:engineer" "$root" "OK" "" "" "agent.id=engineer")
  # one span per line
  [ "$(wc -l < "$sink" | tr -d ' ')" = "2" ] || { echo "FAIL: expected 2 span lines"; st_fail=1; }
  # OTel-semantic keys present on line 1
  for k in trace_id span_id parent_span_id name start_unix_nano end_unix_nano attributes status; do
    [ "$(head -1 "$sink" | jq -e "has(\"$k\")")" = "true" ] || { echo "FAIL: missing key $k"; st_fail=1; }
  done
  # parent linkage: child.parent_span_id == root span_id; root parent is null
  [ "$(head -1 "$sink" | jq -r '.parent_span_id')" = "null" ] || { echo "FAIL: root parent not null"; st_fail=1; }
  [ "$(tail -1 "$sink" | jq -r '.parent_span_id')" = "$root" ] || { echo "FAIL: child not linked to root"; st_fail=1; }
  [ "$(tail -1 "$sink" | jq -r '.attributes["agent.id"]')" = "engineer" ] || { echo "FAIL: attr lost"; st_fail=1; }
  rm -f "$sink"
  [ "$st_fail" -eq 0 ] || { echo "otel-trace --selftest: FAIL" >&2; return 1; }
  echo "otel-trace --selftest: OK (ids, span lines, OTel keys, parent linkage, attrs)"; return 0
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh scripts/otel-trace.sh --selftest`
Expected: FAIL (functions not defined).

- [ ] **Step 3: Implement the emitter**

```sh
#!/bin/sh
# otel-trace.sh — zero-dep OTel-shaped span emitter (E5-thin sensor).
# Emits one OTel-semantic span per NDJSON line to a pluggable sink. Fields map
# 1:1 to OTLP (scripts/otlp-export.sh wraps them). NOT a gate — a reference
# adapter, like scripts/agent-trace.sh. sh + jq.
set -eu

# portable: 16/8-byte random hex id (trace=32 hex, span=16 hex)
rand_hex() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }
new_trace() { rand_hex 16; }

# portable unix-nanos: prefer date +%s%N (GNU); fall back to seconds * 1e9 (macOS/BSD)
now_nano() {
  _n=$(date +%s%N 2>/dev/null)
  case "$_n" in *N|"") printf '%s000000000' "$(date +%s)";; *) printf '%s' "$_n";; esac
}

# emit_span TRACE NAME PARENT STATUS START END [attr=k=v ...]  -> prints span_id, writes a line
emit_span() {
  _trace="$1"; _name="$2"; _parent="$3"; _status="${4:-OK}"; _start="${5:-}"; _end="${6:-}"; shift 6 || shift $#
  _sid=$(rand_hex 8)
  [ -n "$_start" ] || _start=$(now_nano)
  [ -n "$_end" ] || _end=$(now_nano)
  # build the attributes object from remaining k=v args (jq, never hand-built)
  _attrs='{}'
  for kv in "$@"; do
    _k=${kv%%=*}; _v=${kv#*=}
    _attrs=$(printf '%s' "$_attrs" | jq --arg k "$_k" --arg v "$_v" '.[$k]=$v')
  done
  _line=$(jq -nc \
    --arg t "$_trace" --arg s "$_sid" --arg p "$_parent" --arg n "$_name" \
    --argjson st "$_start" --argjson en "$_end" \
    --argjson attrs "$_attrs" --arg code "$_status" '
    { trace_id:$t, span_id:$s,
      parent_span_id: (if $p=="" then null else $p end),
      name:$n, start_unix_nano:$st, end_unix_nano:$en,
      attributes:$attrs, status:{code:$code} }')
  if [ -n "${OTEL_TRACE_FILE:-}" ]; then printf '%s\n' "$_line" >> "$OTEL_TRACE_FILE"; else printf '%s\n' "$_line"; fi
  printf '%s' "$_sid"
}

# --- selftest() from Step 1 goes here ---

# --- dispatch ---
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  new-trace)  new_trace; echo; exit 0 ;;
  span)
    shift
    _trace=""; _name=""; _parent=""; _status="OK"; _start=""; _end=""; set --  # collect attrs in $@ below
    # re-parse: see arg loop
    ;;
esac
```

For the `span` subcommand arg-parse (flags `--trace/--name/--parent/--attr/--status/--start/--end/--sink`), mirror the `while [ $# -gt 0 ]` loop in `scripts/agent-trace.sh:21-35`; collect repeated `--attr k=v` into positional args passed to `emit_span`; `--sink` sets `OTEL_TRACE_FILE`. Keep it apostrophe-free inside jq.

- [ ] **Step 4: Run selftest, verify it passes**

Run: `sh scripts/otel-trace.sh --selftest`
Expected: `otel-trace --selftest: OK (...)`. Also run `sh conformance/shellcheck.sh scripts/otel-trace.sh` (or the repo's shellcheck step) — zero warnings.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/otel-trace.sh
git add scripts/otel-trace.sh
git commit -m "feat(e5-thin): zero-dep OTel-shaped span emitter with pluggable sink"
```

---

### Task 2: Orchestrator stand-in (`scripts/orchestrator-trace-demo.sh`)

**Files:**
- Create: `scripts/orchestrator-trace-demo.sh`
- Create (fixture, frozen output for later selftests): `scripts/fixtures/otel-trace-sample.ndjson`

**Interfaces:**
- Produces: `orchestrator-trace-demo.sh [--out FILE]` → writes a 4-span NDJSON trace (root + engineer + reviewer + a **denied** gate span) and prints the path. Consumed by Tasks 3/4 + the golden-path job.

- [ ] **Step 1: Write the failing selftest**

```sh
selftest() {
  out=$(mktemp)
  main --out "$out" >/dev/null
  st_fail=0
  [ "$(wc -l < "$out" | tr -d ' ')" = "4" ] || { echo "FAIL: expected 4 spans"; st_fail=1; }
  # exactly one root (null parent), three children
  [ "$(jq -s '[.[]|select(.parent_span_id==null)]|length' "$out")" = "1" ] || { echo "FAIL: not exactly 1 root"; st_fail=1; }
  # the denied span carries the kit.denied signal (the contract the adapter reads)
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$out")" = "1" ] || { echo "FAIL: no denied span"; st_fail=1; }
  rm -f "$out"
  [ "$st_fail" -eq 0 ] || { echo "orchestrator-trace-demo --selftest: FAIL" >&2; return 1; }
  echo "orchestrator-trace-demo --selftest: OK (root+3 children, one denied)"; return 0
}
```

- [ ] **Step 2: Run it, verify it fails** — `sh scripts/orchestrator-trace-demo.sh --selftest` → FAIL.

- [ ] **Step 3: Implement the stand-in**

```sh
#!/bin/sh
# orchestrator-trace-demo.sh — REFERENCE STAND-IN for the E3 orchestrator (E5-thin).
# Emits one representative orchestrator trace: a root span with three child spans
# (engineer, reviewer, and a guard-DENIED gate). This is the shape E3a will emit;
# E3a REPLACES this script's body with the real fan-out loop. Not a gate.
set -eu
here=$(dirname "$0")
emit() { sh "$here/otel-trace.sh" span "$@"; }

main() {
  OUT=""
  while [ $# -gt 0 ]; do case "$1" in --out) OUT="$2"; shift 2;; *) shift;; esac; done
  tid=$(sh "$here/otel-trace.sh" new-trace)
  : "${OUT:=$(mktemp)}"
  : > "$OUT"
  export OTEL_TRACE_FILE="$OUT"
  root=$(emit --trace "$tid" --name orchestrator-run --status OK --attr "agent.id=orchestrator")
  emit --trace "$tid" --parent "$root" --name "agent:engineer" --status OK  --attr "agent.id=engineer" --attr "steps=4" >/dev/null
  emit --trace "$tid" --parent "$root" --name "agent:reviewer" --status OK  --attr "agent.id=reviewer" --attr "steps=2" >/dev/null
  # a guard-denied gate step — the non-vacuous signal the scorecard must reflect
  emit --trace "$tid" --parent "$root" --name "gate:guard"   --status ERROR --attr "agent.id=engineer" --attr "kit.denied=true" >/dev/null
  printf '%s\n' "$OUT"
}

case "${1:-}" in --selftest) selftest; exit $? ;; *) main "$@" ;; esac
```

> ★ **Owner decision point (per spec §7):** the **denied signal** is the `kit.denied=true` span attribute (OTel has no native "denied"). Bradley may instead key it off a status convention. The default above is complete and runnable; change only the attribute name/convention here and in Task 3's adapter if overriding.

- [ ] **Step 4: Generate the frozen fixture + run selftest**

```bash
sh scripts/orchestrator-trace-demo.sh --out scripts/fixtures/otel-trace-sample.ndjson
sh scripts/orchestrator-trace-demo.sh --selftest
```
Expected: selftest OK; fixture file has 4 span lines.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/orchestrator-trace-demo.sh
git add scripts/orchestrator-trace-demo.sh scripts/fixtures/otel-trace-sample.ndjson
git commit -m "feat(e5-thin): reference orchestrator stand-in emitting an OTel span tree"
```

---

### Task 3: Adapter — OTel spans → MP-3a records (`scripts/otel-to-scorecard.sh`)

**Files:**
- Create: `scripts/otel-to-scorecard.sh`

**Interfaces:**
- Consumes: an OTel NDJSON trace (Task 1 shape).
- Produces: `otel-to-scorecard.sh TRACE.ndjson [--stdout|--out DIR]` → an MP-3a **records array** (JSON) the unchanged `agent-scorecard.sh` consumes. Each **child** span → one record `{ "agent.id", "run.id", start, end, outcome, "review.rounds", steps:[{outcome,retries}] }`.

**The MP-3a contract the scorecard reads** (from `agent-scorecard.sh`): groups by `.["agent.id"]`; `denial` reads `.steps[].outcome=="denied"`; `errrate` reads run-level `.outcome=="error"|"blocked"`; `retry` reads `.steps[].retries`; `reviews` reads `.["review.rounds"]`.

- [ ] **Step 1: Write the failing selftest** (uses the Task 2 fixture)

```sh
selftest() {
  fix="$(dirname "$0")/fixtures/otel-trace-sample.ndjson"
  out=$(map_trace "$fix")
  st_fail=0
  # child spans only (root excluded): 3 records
  [ "$(printf '%s' "$out" | jq 'length')" = "3" ] || { echo "FAIL: expected 3 records"; st_fail=1; }
  # the denied span -> a record whose steps carry outcome "denied"
  [ "$(printf '%s' "$out" | jq '[.[]|select(.steps[].outcome=="denied")]|length')" -ge 1 ] || { echo "FAIL: denied not mapped"; st_fail=1; }
  # every record has the scorecard's required fields
  for k in '"agent.id"' '"outcome"' '"steps"' '"start"'; do
    [ "$(printf '%s' "$out" | jq "all(has($k))")" = "true" ] || { echo "FAIL: missing $k"; st_fail=1; }
  done
  # (the REAL scorecard end-to-end proof lives in Step 4, not the selftest)
  [ "$st_fail" -eq 0 ] || { echo "otel-to-scorecard --selftest: FAIL" >&2; return 1; }
  echo "otel-to-scorecard --selftest: OK (3 child records, denied mapped, required fields)"; return 0
}
```

- [ ] **Step 2: Run it, verify it fails** — FAIL.

- [ ] **Step 3: Implement the adapter**

```sh
#!/bin/sh
# otel-to-scorecard.sh — adapter: OTel NDJSON spans -> MP-3a records for agent-scorecard.sh.
# Each CHILD span (parent_span_id != null) becomes one per-agent run record. The
# proven scorecard is UNCHANGED; this script is the documented OTel->scorecard mapping.
# sh + jq. No JSON hand-built.
set -eu

# map_trace FILE -> prints a JSON array of MP-3a records
map_trace() {
  # ── ★ Owner decision point (spec §7): status.code + kit.denied -> MP-3a outcome ──
  # default mapping:
  #   run-level .outcome : ERROR -> "error", else "ok"
  #   step .outcome      : kit.denied==true -> "denied"; else mirror run outcome
  jq -s '
    [ .[] | select(.parent_span_id != null)
      | (.attributes["kit.denied"] == "true") as $denied
      | (if .status.code == "ERROR" then "error" else "ok" end) as $run
      | {
          "agent.id": (.attributes["agent.id"] // "unknown"),
          "run.id": .span_id,
          start: (.start_unix_nano|tostring), end: (.end_unix_nano|tostring),
          outcome: $run,
          "review.rounds": ((.attributes["review.rounds"] // "0")|tonumber? // 0),
          steps: [ { outcome: (if $denied then "denied" else $run end),
                     retries: ((.attributes.retries // "0")|tonumber? // 0) } ]
        } ]' "$1"
}

selftest() { : ; }  # from Step 1

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -*|"") echo "usage: otel-to-scorecard.sh TRACE.ndjson [--stdout]" >&2; exit 2 ;;
  *) map_trace "$1" ;;
esac
```

- [ ] **Step 4: Run selftest + prove the loop against the REAL scorecard**

```bash
sh scripts/otel-to-scorecard.sh --selftest
# end-to-end smoke: emit -> adapt -> score, assert a denial_rate>0 card
t=$(sh scripts/orchestrator-trace-demo.sh)
mkdir -p /tmp/e5tr && sh scripts/otel-to-scorecard.sh "$t" | jq -c '.[]' > /tmp/e5tr/recs.json
# agent-scorecard reads a traces DIR of MP-3a traces; write each record as a trace file
i=0; while read -r r; do echo "$r" > "/tmp/e5tr/$i.json"; i=$((i+1)); done < /tmp/e5tr/recs.json
sh scripts/agent-scorecard.sh --traces /tmp/e5tr --min-runs 1 --stdout | jq -e '[.[]|select(.metrics.denial_rate>0)]|length>=1'
```
Expected: selftest OK; the final `jq -e` exits 0 (a real card shows `denial_rate>0` derived from the emitted denied span). This is exactly the golden-path assertion, run locally.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/otel-to-scorecard.sh
git add scripts/otel-to-scorecard.sh
git commit -m "feat(e5-thin): OTel->MP-3a adapter; scorecard unchanged, denied mapped"
```

---

### Task 4: OTLP reference exporter (`scripts/otlp-export.sh`)

**Files:**
- Create: `scripts/otlp-export.sh`

**Interfaces:**
- Consumes: an OTel NDJSON trace (Task 1 shape).
- Produces: `otlp-export.sh TRACE.ndjson [--dry-run]` → a schema-valid OTLP/JSON `resourceSpans` document on stdout; POSTs to `$OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces` unless `--dry-run`/no endpoint. `--selftest` validates the envelope shape (no network).

- [ ] **Step 1: Write the failing selftest**

```sh
selftest() {
  fix="$(dirname "$0")/fixtures/otel-trace-sample.ndjson"
  doc=$(to_otlp "$fix")
  st_fail=0
  # OTLP envelope shape
  [ "$(printf '%s' "$doc" | jq -e 'has("resourceSpans")')" = "true" ] || { echo "FAIL: no resourceSpans"; st_fail=1; }
  n=$(printf '%s' "$doc" | jq '[.resourceSpans[0].scopeSpans[0].spans[]]|length')
  [ "$n" = "4" ] || { echo "FAIL: expected 4 OTLP spans, got $n"; st_fail=1; }
  # OTLP camelCase keys + string nanos + KV-array attributes
  sp=$(printf '%s' "$doc" | jq '.resourceSpans[0].scopeSpans[0].spans[0]')
  for k in traceId spanId name startTimeUnixNano endTimeUnixNano attributes status; do
    [ "$(printf '%s' "$sp" | jq -e "has(\"$k\")")" = "true" ] || { echo "FAIL: OTLP key $k"; st_fail=1; }
  done
  [ "$(printf '%s' "$sp" | jq -r '.startTimeUnixNano|type')" = "string" ] || { echo "FAIL: nanos must be string in OTLP"; st_fail=1; }
  [ "$(printf '%s' "$sp" | jq -e '.attributes|type=="array"')" = "true" ] || { echo "FAIL: OTLP attributes must be KV array"; st_fail=1; }
  [ "$st_fail" -eq 0 ] || { echo "otlp-export --selftest: FAIL" >&2; return 1; }
  echo "otlp-export --selftest: OK (valid OTLP/JSON envelope; no network)"; return 0
}
```

- [ ] **Step 2: Run it, verify it fails** — FAIL.

- [ ] **Step 3: Implement the exporter**

```sh
#!/bin/sh
# otlp-export.sh — opt-in reference exporter: kit NDJSON spans -> OTLP/JSON ->
# POST $OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces. Proves the integration is REAL;
# the live vendor backend (endpoint+auth) is the adopter's. sh + jq + curl.
set -eu

# to_otlp FILE -> OTLP/JSON resourceSpans doc (camelCase, string nanos, KV-array attrs)
to_otlp() {
  jq -s '
    def kv: to_entries | map({key:.key, value:{stringValue:(.value|tostring)}});
    { resourceSpans: [ {
        resource: { attributes: [ {key:"service.name", value:{stringValue:"sparkwright"}} ] },
        scopeSpans: [ {
          scope: { name: "sparkwright.agentops" },
          spans: [ .[] | {
            traceId: .trace_id, spanId: .span_id,
            parentSpanId: (.parent_span_id // ""),
            name: .name,
            startTimeUnixNano: (.start_unix_nano|tostring),
            endTimeUnixNano: (.end_unix_nano|tostring),
            attributes: (.attributes | kv),
            status: { code: (if .status.code=="ERROR" then 2 else 1 end) }
          } ]
        } ]
      } ] }' "$1"
}

main() {
  DRY=0; TRACE=""
  while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1; shift;; -*) echo "unknown flag $1" >&2; exit 2;; *) TRACE="$1"; shift;; esac; done
  [ -n "$TRACE" ] || { echo "usage: otlp-export.sh TRACE.ndjson [--dry-run]" >&2; exit 2; }
  doc=$(to_otlp "$TRACE")
  if [ "$DRY" -eq 1 ] || [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]; then
    printf '%s\n' "$doc"
    [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ] && echo "otlp-export: no \$OTEL_EXPORTER_OTLP_ENDPOINT — printed payload, did not POST" >&2
    return 0
  fi
  # opt-in POST; headers via $OTEL_EXPORTER_OTLP_HEADERS ("k=v,k=v"); never echo secrets
  _hdrs=""
  if [ -n "${OTEL_EXPORTER_OTLP_HEADERS:-}" ]; then
    OLDIFS=$IFS; IFS=','; for h in $OTEL_EXPORTER_OTLP_HEADERS; do _hdrs="$_hdrs -H ${h%%=*}:${h#*=}"; done; IFS=$OLDIFS
  fi
  # shellcheck disable=SC2086
  printf '%s' "$doc" | curl -sS -X POST -H 'Content-Type: application/json' $_hdrs \
    --data-binary @- "${OTEL_EXPORTER_OTLP_ENDPOINT%/}/v1/traces"
}

case "${1:-}" in --selftest) selftest; exit $? ;; *) main "$@" ;; esac
```

- [ ] **Step 4: Run selftest + dry-run** — `sh scripts/otlp-export.sh --selftest` → OK; `sh scripts/otlp-export.sh scripts/fixtures/otel-trace-sample.ndjson --dry-run | jq -e .resourceSpans` exits 0. Shellcheck clean.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/otlp-export.sh
git add scripts/otlp-export.sh
git commit -m "feat(e5-thin): opt-in OTLP reference exporter (NDJSON -> OTLP/JSON -> POST)"
```

---

### Task 5: Integration docs (`docs/operations/agentic-ops.md`)

**Files:**
- Modify: `docs/operations/agentic-ops.md` (append a section)

- [ ] **Step 1: Append the integration section**

Add a `## Enterprise observability — OTLP export` section documenting: the emit→adapt→score loop (`orchestrator-trace-demo.sh` → `otel-to-scorecard.sh` → `agent-scorecard.sh`); the opt-in export path (`otel-trace.sh` NDJSON → `otlp-export.sh` → any OTLP backend); the standard env vars `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`; the honest ceiling (valid OTLP produced + POSTed; live vendor backend is the adopter's); and the note that `orchestrator-trace-demo.sh` is a **stand-in E3a replaces**. Cross-link the design doc.

- [ ] **Step 2: Link-check + commit**

```bash
sh conformance/check-links.sh
git add docs/operations/agentic-ops.md
git commit -m "docs(e5-thin): OTLP enterprise-integration section in agentic-ops"
```

---

### Task 6: Control-plane materialiser (`apply.py`, in scratchpad)

**Files (written by apply.py when the human runs it):**
- Create: `conformance/agentops-sensor-wired.sh`
- Modify: `conformance/claims.tsv` (+1 row), `conformance/verify.sh` (+1 `check control` line)
- Modify: `.github/workflows/golden-path.yml` (+`agentops-sensor` job)
- Modify (version finishing): `VERSION`, `README.md`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`
- The script itself lives at `scratchpad/e5-thin/apply.py` (NOT committed to the repo tree by the agent).

- [ ] **Step 1: Author `conformance/agentops-sensor-wired.sh`** (as a heredoc inside apply.py). It must (mirror `conformance/runtime-security.sh` structure):
  - run `sh scripts/otel-trace.sh --selftest`, `sh scripts/orchestrator-trace-demo.sh --selftest`, `sh scripts/otel-to-scorecard.sh --selftest`, `sh scripts/otlp-export.sh --selftest` — all must pass;
  - assert the four scripts exist and are executable;
  - assert `.github/workflows/golden-path.yml` contains a job named `agentops-sensor` that runs `orchestrator-trace-demo.sh` and `otel-to-scorecard.sh` and `agent-scorecard.sh` (grep the job block);
  - support `--selftest` (renderer-only) per the repo convention;
  - claim id: `agentops-sensor`.

- [ ] **Step 2: Author the `agentops-sensor` golden-path job** (heredoc). Mirror the `containment-audit` job structure (`.github/workflows/golden-path.yml:112`). Steps: checkout; run the emit→adapt→score loop; assert non-vacuous:

```yaml
  agentops-sensor:
    # E5-thin — PROVE the operate-loop sensor runs on REAL emitted data (not a fixture):
    # emit an OTel trace from the orchestrator stand-in, adapt it, score it, and assert
    # the scorecard's denial_rate reflects the emitted DENIED span (a dead emitter can't).
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3
      - name: emit -> adapt -> score, assert non-vacuous denial_rate
        run: |
          t=$(sh scripts/orchestrator-trace-demo.sh)
          d=$(mktemp -d)
          i=0; sh scripts/otel-to-scorecard.sh "$t" | jq -c '.[]' | while read -r r; do echo "$r" > "$d/$i.json"; i=$((i+1)); done
          sh scripts/agent-scorecard.sh --traces "$d" --min-runs 1 --stdout > sc.json
          jq -e '[.[]|select(.metrics.denial_rate>0)]|length>=1' sc.json >/dev/null \
            || { echo "agentops-sensor: scorecard did not reflect the emitted denied span (vacuous)"; cat sc.json; exit 1; }
          echo "agentops-sensor: OK — real emit->adapt->score loop, denial_rate derived from emitted span"
```
Also add `scripts/otel-trace.sh`, `scripts/orchestrator-trace-demo.sh`, `scripts/otel-to-scorecard.sh`, `scripts/agent-scorecard.sh` to the golden-path `on: pull_request/push: paths:` filter (lines 6 & 8) so the job triggers.

- [ ] **Step 3: Author the claims.tsv row + verify.sh line** (string-insert in apply.py):
  - `claims.tsv` append: `agentops-sensor\tthe operate-loop sensor emits an OTel-shaped trace + a real scorecard derives from it (golden-path agentops-sensor job; scripts/otel-trace.sh + otel-to-scorecard.sh)\tsh conformance/agentops-sensor-wired.sh`
  - `verify.sh`: insert after the `runtime-security` line (`:79`): `check control agentops-sensor    sh conformance/agentops-sensor-wired.sh`

- [ ] **Step 4: Author the version finishing** (apply.py edits — the durable fix):
  - `VERSION`: `3.50.0` → `3.51.0`
  - `README.md`: bump the version badge `3.50.0` → `3.51.0`
  - `CHANGELOG.md`: prepend a `## [3.51.0]` entry (E5-thin: OTel-shaped sensor + OTLP export seam; honest-ceiling wording)
  - `docs/ROADMAP-KIT.md`: mark E5-thin done; advance the "NEXT" pointer to E3a; update the Last-Updated line.

- [ ] **Step 5: apply.py hygiene** — preserve file modes (`0755` for the new `.sh`), idempotent string-inserts (assert anchor present exactly once before inserting), `NoReturn` on failure paths. Mirror prior `*apply.py` in the slice scratchpads.

---

### Task 7: Dry-run on a clone, full verify, hand off

- [ ] **Step 1: Clone the branch + dry-run apply.py**

```bash
tmp=$(mktemp -d); git clone . "$tmp/clone"
cd "$tmp/clone" && git checkout feat/e5-thin-otel-sensor
KIT_GUARD_SELFEDIT=1 python3 /path/to/scratchpad/e5-thin/apply.py
```

- [ ] **Step 2: Full conformance on the clone**

```bash
sh conformance/verify.sh --require        # expect agentops-sensor PASS + 0 failed
sh conformance/agentops-sensor-wired.sh   # standalone PASS
sh conformance/agentops-sensor-wired.sh --selftest
sh conformance/shellcheck.sh              # zero warnings on the 4 new scripts
sh conformance/claims-registry.sh         # new claim verified
sh conformance/ci-selftest-coverage.sh    # the global invariant still holds (one selftest path)
sh conformance/adopter-export-wired.sh    # if the lock reads an export-ignored path, carve it (mirror feature-flags-wired)
```
Expected: all PASS; `verify.sh --require` shows `agentops-sensor PASS` and `0 failed`. Confirm `agent-scorecard.sh --selftest` still passes (no regression). Confirm `VERSION`==`3.51.0`==badge.

> **Carve check (REUSABLE LESSON from E2):** if `agentops-sensor-wired.sh` ends up reading an export-ignored path (`golden-path.yml`, `ROADMAP-KIT.md`), it MUST be carved in BOTH loops of `scripts/adopter-export.sh` + asserted by `adopter-export-wired.sh`, or the adopter export goes RED. Verify on the clone with `sh scripts/adopter-export.sh /tmp/exp && (cd /tmp/exp && sh conformance/verify.sh --require)`.

- [ ] **Step 3: Dual review** — dispatch `reviewer` (builder≠reviewer) on the branch diff + scratchpad apply.py, and `security-reviewer` (themes: filename path-safety on `run.id`/span names; jq-built JSON; `$OTEL_EXPORTER_OTLP_HEADERS` injection/secret-echo; the `kit.denied` trust boundary). Resolve to APPROVE.

- [ ] **Step 4: Hand off to Bradley** (per `[[merge-tag-authority]]`):

> Branch green + dual-approved. Run: `KIT_GUARD_SELFEDIT=1 python3 scratchpad/e5-thin/apply.py` → `git add -A && git commit` → push → PR → (CI incl. golden-path `agentops-sensor` green) → `gh pr merge --squash --admin --delete-branch` → tag `v3.51.0` on the merge commit. apply.py already did the VERSION/README/CHANGELOG/ROADMAP finishing, so there is no separate finishing step to skip.

---

## Self-Review (against the spec)

- **§2 goal (real non-fixture loop):** Tasks 2+3+6 emit→adapt→score; golden-path asserts non-vacuous. ✓
- **§3 integration lens / §4 exporter:** Task 4 (otlp-export) + Task 5 (docs). ✓
- **§4 components:** otel-trace (T1), stand-in (T2), adapter (T3), exporter (T4), lock+claim (T6). Scorecard untouched (T7 selftest). ✓
- **§5 span shape + portability:** T1 emitter (OTel keys, portable nanos/ids). ✓
- **§7 owner mapping point:** flagged in T2 + T3 with a complete runnable default. ✓
- **§8 conformance:** T6 lock + golden-path job + verify wiring; T7 carve check. ✓
- **§9 honest ceiling:** exporter dry-run/selftest only (no live backend); stand-in labelled; min-runs keeps classification fail-safe. ✓
- **§10 release / version-finishing in apply.py:** T6 Step 4 + T7 hand-off. ✓
- **§11 testing/review:** four selftests + golden-path + dual review (T7). ✓

**Placeholder scan:** the only deferred item is the **owner mapping decision** (T2/T3) — and a complete default is provided, so the plan is runnable as-is. No other TBDs.

**Type/name consistency:** `kit.denied`, `agent.id`, `denial_rate`, `agentops-sensor`, `otel-to-scorecard.sh`, `orchestrator-trace-demo.sh` used consistently across tasks.
