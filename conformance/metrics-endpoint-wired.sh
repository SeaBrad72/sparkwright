#!/bin/sh
# metrics-endpoint-wired.sh — lock that the reference app exposes a Prometheus /metrics endpoint AND
# golden-path asserts it on the booted app (E5-metrics). STATIC (no docker); the live proof is the
# golden-path metrics-endpoint step. SCOPE: proves the reference exposes metrics + the proof is wired —
# NOT that an adopter's app does (kit-self lock; carved from the adopter export, mirrors runtime-security
# / structured-logging / app-tracing). Basis: DEVELOPMENT-STANDARDS.md Factor 14 (telemetry = metrics +
# traces + health, not just logs). Usage: [--selftest]
set -eu
ROOT="${METRICS_ENDPOINT_ROOT:-.}"
SERVER="${METRICS_ENDPOINT_SERVER:-$ROOT/profiles/typescript-node/scaffold/src/server.ts}"
WF="${GOLDEN_PATH_WF:-$ROOT/.github/workflows/golden-path.yml}"

# _strip_js_comments FILE -> stdout with // line comments and /* */ (incl. multi-line) block
# comments removed. A token that appears only inside a comment (a call `//`-commented out) must
# NOT satisfy the lock — the wiring must be LIVE (mirrors agentops-sensor-wired's #-strip, but for
# JS/TS). Do NOT strip `#` — the Prometheus exposition line `# TYPE` starts with `#`, not `//`, and
# is a legit token this lock must keep matching, never a comment to discard. Heuristic, not a real
# parser (no string-literal awareness) — sufficient for a content lock over the kit's own reference
# scaffold.
_strip_js_comments() {
  awk '
    {
      line = $0
      if (in_block) {
        idx = index(line, "*/")
        if (idx == 0) { next }
        line = substr(line, idx + 2)
        in_block = 0
      }
      sub(/\/\/.*/, "", line)
      while (match(line, /\/\*.*\*\//)) {
        line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
      }
      idx2 = index(line, "/*")
      if (idx2 > 0) {
        line = substr(line, 1, idx2 - 1)
        in_block = 1
      }
      print line
    }
  ' "$1"
}

# server.ts must expose /metrics emitting Prometheus exposition (the counter + a '# TYPE' line).
check_server() {  # <server.ts> — exposes a Prometheus /metrics endpoint (LIVE, not commented out)
  f=$1; miss=0
  code=$(_strip_js_comments "$f")
  printf '%s\n' "$code" | grep -qF -- "/metrics" || { echo "FAIL: $f does not expose /metrics (live call, not a comment)"; miss=1; }
  printf '%s\n' "$code" | grep -qF -- "http_requests_total" || { echo "FAIL: $f missing http_requests_total counter (live call, not a comment)"; miss=1; }
  printf '%s\n' "$code" | grep -qF -- "# TYPE" || { echo "FAIL: $f missing Prometheus '# TYPE' exposition"; miss=1; }
  return $miss
}

check_wf() {  # <golden-path.yml> — asserts the /metrics endpoint on the booted app
  f=$1; miss=0
  for t in 'metrics-endpoint: OK' 'http_requests_total' '/metrics'; do
    grep -qF -- "$t" "$f" || { echo "FAIL: golden-path missing metrics-endpoint assertion: $t"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  printf '/metrics http_requests_total # TYPE\n' > "$d/server_ok.ts"
  printf '/metrics # TYPE\n' > "$d/server_bad.ts"   # missing http_requests_total
  printf '// /metrics http_requests_total # TYPE\n' > "$d/server_commented.ts"   # endpoint commented OUT
  printf 'metrics-endpoint: OK\nhttp_requests_total\n/metrics\n' > "$d/wf_ok.yml"
  printf 'some other step\n' > "$d/wf_bad.yml"
  if check_server "$d/server_ok.ts" >/dev/null 2>&1; then echo "selftest PASS: server all tokens -> PASS"; else echo "selftest FAIL: server_ok wrongly failed"; sf=1; fi
  if check_server "$d/server_bad.ts" >/dev/null 2>&1; then echo "selftest FAIL: missing token NOT caught"; sf=1; else echo "selftest PASS: missing token -> FAIL"; fi
  if check_server "$d/server_commented.ts" >/dev/null 2>&1; then echo "selftest FAIL: //-commented-out endpoint NOT caught (a dead endpoint should not satisfy the lock)"; sf=1; else echo "selftest PASS: //-commented-out endpoint -> FAIL"; fi
  # STAYS-GREEN: the '# TYPE' Prometheus exposition token is not a JS comment — the //-strip must
  # not clobber it (it starts with '#', not '//').
  if check_server "$d/server_ok.ts" >/dev/null 2>&1; then echo "selftest PASS: '# TYPE' token survives the //-strip"; else echo "selftest FAIL: '# TYPE' token wrongly clobbered by the //-strip"; sf=1; fi
  if check_wf "$d/wf_ok.yml" >/dev/null 2>&1; then echo "selftest PASS: wf asserts -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  if check_wf "$d/wf_bad.yml" >/dev/null 2>&1; then echo "selftest FAIL: wf missing assertion NOT caught"; sf=1; else echo "selftest PASS: wf missing assertion -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: metrics-endpoint selftest"; exit 0; } || { echo "FAIL: metrics-endpoint selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: metrics-endpoint-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors runtime-security): verifies the kit's OWN golden-path pipeline. On an adopter tree
# both kit markers are export-ignored/stripped → nothing to verify → N/A. Fail-closed on the kit:
# ROADMAP-KIT.md remains even if golden-path is deleted, so the [ -f "$WF" ] check below still FAILs.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "metrics-endpoint: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$SERVER" ] || { echo "FAIL: reference server not found: $SERVER"; fail=1; }
[ -f "$WF" ]     || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_server "$SERVER" || fail=1; check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: reference app exposes a Prometheus /metrics endpoint + golden-path asserts it on the booted app"; exit 0; }
echo "FAIL: metrics-endpoint under-wired"; exit 1
