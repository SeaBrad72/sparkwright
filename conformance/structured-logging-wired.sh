#!/bin/sh
# structured-logging-wired.sh — lock that the reference app emits STRUCTURED JSON request logs AND
# golden-path asserts the structured line on the booted app (E5-log). STATIC (no docker); the live
# proof is the golden-path structured-logging step. SCOPE: proves the reference logs structured + the
# proof is wired — NOT that an adopter's arbitrary app logs structured (kit-self lock; carved from the
# adopter export, mirrors runtime-security). Basis: DEVELOPMENT-STANDARDS.md §3 Observability
# (structured logging; every entry carries ts, level, fields, request/correlation id, service).
# Usage: [--selftest]
set -eu
ROOT="${STRUCTURED_LOGGING_ROOT:-.}"
SERVER="${STRUCTURED_LOGGING_SERVER:-$ROOT/profiles/typescript-node/scaffold/src/server.ts}"
WF="${GOLDEN_PATH_WF:-$ROOT/.github/workflows/golden-path.yml}"
# server.ts must emit a structured request log: mint/honor a request id + log latency via JSON.stringify.
SERVER_TOKENS="randomUUID requestId latencyMs JSON.stringify"

check_server() {  # <server.ts> — emits a structured request log line
  f=$1; miss=0
  for t in $SERVER_TOKENS; do
    grep -qF -- "$t" "$f" || { echo "FAIL: $f missing structured-logging token: $t"; miss=1; }
  done
  return $miss
}

check_wf() {  # <golden-path.yml> — asserts the structured line on the booted app
  f=$1; miss=0
  for t in 'structured-logging: OK' '"requestId"' 'latencyMs'; do
    grep -qF -- "$t" "$f" || { echo "FAIL: golden-path missing structured-logging assertion: $t"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  printf 'randomUUID requestId latencyMs JSON.stringify\n' > "$d/server_ok.ts"
  printf 'randomUUID requestId JSON.stringify\n' > "$d/server_bad.ts"   # missing latencyMs
  printf 'structured-logging: OK\n"requestId"\nlatencyMs\n' > "$d/wf_ok.yml"
  printf 'some other step\n' > "$d/wf_bad.yml"
  if check_server "$d/server_ok.ts" >/dev/null 2>&1; then echo "selftest PASS: server all tokens -> PASS"; else echo "selftest FAIL: server_ok wrongly failed"; sf=1; fi
  if check_server "$d/server_bad.ts" >/dev/null 2>&1; then echo "selftest FAIL: missing token NOT caught"; sf=1; else echo "selftest PASS: missing token -> FAIL"; fi
  if check_wf "$d/wf_ok.yml" >/dev/null 2>&1; then echo "selftest PASS: wf asserts -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  if check_wf "$d/wf_bad.yml" >/dev/null 2>&1; then echo "selftest FAIL: wf missing assertion NOT caught"; sf=1; else echo "selftest PASS: wf missing assertion -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: structured-logging selftest"; exit 0; } || { echo "FAIL: structured-logging selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: structured-logging-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors runtime-security): verifies the kit's OWN golden-path pipeline. On an adopter tree
# both kit markers are export-ignored/stripped → nothing to verify → N/A. Fail-closed on the kit:
# ROADMAP-KIT.md remains even if golden-path is deleted, so the [ -f "$WF" ] check below still FAILs.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "structured-logging: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$SERVER" ] || { echo "FAIL: reference server not found: $SERVER"; fail=1; }
[ -f "$WF" ]     || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_server "$SERVER" || fail=1; check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: reference app emits structured request logs + golden-path asserts them on the booted app"; exit 0; }
echo "FAIL: structured-logging under-wired"; exit 1
