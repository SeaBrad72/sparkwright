#!/bin/sh
# app-tracing-wired.sh — lock that the reference app emits OTel-semantic request SPANS AND golden-path
# asserts the span on the booted app + proves it converts through the existing OTLP seam (E5-trace).
# STATIC (no docker); the live proof is the golden-path app-tracing step. SCOPE: proves the reference
# emits OTLP-convertible spans + the proof is wired — NOT that an adopter's app traces (kit-self lock;
# carved from the adopter export, mirrors runtime-security / structured-logging). Basis: the kit's own
# zero-dep OTel idiom (scripts/otel-trace.sh schema + scripts/otlp-export.sh seam). Usage: [--selftest]
set -eu
ROOT="${APP_TRACING_ROOT:-.}"
SERVER="${APP_TRACING_SERVER:-$ROOT/profiles/typescript-node/scaffold/src/server.ts}"
WF="${GOLDEN_PATH_WF:-$ROOT/.github/workflows/golden-path.yml}"
# server.ts must emit an OTel-semantic span: random ids + the otel-trace.sh schema keys.
SERVER_TOKENS="randomBytes trace_id span_id start_unix_nano"

check_server() {  # <server.ts> — emits an OTel-semantic request span
  f=$1; miss=0
  for t in $SERVER_TOKENS; do
    grep -qF -- "$t" "$f" || { echo "FAIL: $f missing app-tracing token: $t"; miss=1; }
  done
  return $miss
}

check_wf() {  # <golden-path.yml> — asserts the span on the booted app + the OTLP-seam conversion
  f=$1; miss=0
  for t in 'app-tracing: OK' '"trace_id"' 'otlp-export.sh' '--dry-run'; do
    grep -qF -- "$t" "$f" || { echo "FAIL: golden-path missing app-tracing assertion: $t"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  printf 'randomBytes trace_id span_id start_unix_nano\n' > "$d/server_ok.ts"
  printf 'randomBytes trace_id span_id\n' > "$d/server_bad.ts"   # missing start_unix_nano
  printf 'app-tracing: OK\n"trace_id"\notlp-export.sh\n--dry-run\n' > "$d/wf_ok.yml"
  printf 'some other step\n' > "$d/wf_bad.yml"
  if check_server "$d/server_ok.ts" >/dev/null 2>&1; then echo "selftest PASS: server all tokens -> PASS"; else echo "selftest FAIL: server_ok wrongly failed"; sf=1; fi
  if check_server "$d/server_bad.ts" >/dev/null 2>&1; then echo "selftest FAIL: missing token NOT caught"; sf=1; else echo "selftest PASS: missing token -> FAIL"; fi
  if check_wf "$d/wf_ok.yml" >/dev/null 2>&1; then echo "selftest PASS: wf asserts -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  if check_wf "$d/wf_bad.yml" >/dev/null 2>&1; then echo "selftest FAIL: wf missing assertion NOT caught"; sf=1; else echo "selftest PASS: wf missing assertion -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: app-tracing selftest"; exit 0; } || { echo "FAIL: app-tracing selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: app-tracing-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors runtime-security): verifies the kit's OWN golden-path pipeline. On an adopter tree
# both kit markers are export-ignored/stripped → nothing to verify → N/A. Fail-closed on the kit:
# ROADMAP-KIT.md remains even if golden-path is deleted, so the [ -f "$WF" ] check below still FAILs.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "app-tracing: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$SERVER" ] || { echo "FAIL: reference server not found: $SERVER"; fail=1; }
[ -f "$WF" ]     || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_server "$SERVER" || fail=1; check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: reference app emits OTel request spans + golden-path asserts them + proves OTLP conversion"; exit 0; }
echo "FAIL: app-tracing under-wired"; exit 1
