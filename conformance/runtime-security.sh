#!/bin/sh
# runtime-security.sh — lock that the reference app ships security headers AND golden-path asserts
# them on the booted app (E4c). STATIC (no docker); the live proof is the golden-path runtime-security
# step. SCOPE: proves the reference is hardened + the proof is wired — NOT that an adopter's arbitrary
# app is hardened (kit-self lock; carved from the adopter export). Usage: [--selftest]
set -eu
ROOT="${RUNTIME_SECURITY_ROOT:-.}"
SERVER="${RUNTIME_SECURITY_SERVER:-$ROOT/profiles/typescript-node/scaffold/src/server.ts}"
WF="${GOLDEN_PATH_WF:-$ROOT/.github/workflows/golden-path.yml}"
HEADERS="X-Content-Type-Options X-Frame-Options Content-Security-Policy Referrer-Policy"

# _strip_js_comments FILE -> stdout with // line comments and /* */ (incl. multi-line) block
# comments removed. A token that appears only inside a comment (a call `//`-commented out) must
# NOT satisfy the lock — the wiring must be LIVE (mirrors agentops-sensor-wired's #-strip, but for
# JS/TS). Heuristic, not a real parser (no string-literal awareness) — sufficient for a content lock
# over the kit's own reference scaffold.
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

check_server() {  # <server.ts> — sets all four security headers (LIVE, not commented out)
  f=$1; miss=0
  code=$(_strip_js_comments "$f")
  for h in $HEADERS; do
    printf '%s\n' "$code" | grep -qF -- "$h" || { echo "FAIL: $f missing security header (live call, not a comment): $h"; miss=1; }
  done
  return $miss
}

check_wf() {  # <golden-path.yml> — asserts the headers on the booted app
  f=$1; miss=0
  for tok in 'runtime-security: OK' 'x-content-type-options: nosniff' 'x-frame-options: DENY' "content-security-policy: default-src 'none'" 'referrer-policy: no-referrer'; do
    grep -qiF -- "$tok" "$f" || { echo "FAIL: golden-path missing runtime-security assertion: $tok"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  printf 'X-Content-Type-Options X-Frame-Options Content-Security-Policy Referrer-Policy\n' > "$d/server_ok.ts"
  printf 'X-Content-Type-Options X-Frame-Options Content-Security-Policy\n' > "$d/server_bad.ts"   # missing Referrer-Policy
  printf '// X-Content-Type-Options X-Frame-Options Content-Security-Policy Referrer-Policy\n' > "$d/server_commented.ts"   # headers commented OUT
  printf "runtime-security: OK\nx-content-type-options: nosniff\nx-frame-options: DENY\ncontent-security-policy: default-src 'none'\nreferrer-policy: no-referrer\n" > "$d/wf_ok.yml"
  printf 'some other step\n' > "$d/wf_bad.yml"
  if check_server "$d/server_ok.ts" >/dev/null 2>&1; then echo "selftest PASS: server all headers -> PASS"; else echo "selftest FAIL: server_ok wrongly failed"; sf=1; fi
  if check_server "$d/server_bad.ts" >/dev/null 2>&1; then echo "selftest FAIL: missing header NOT caught"; sf=1; else echo "selftest PASS: missing header -> FAIL"; fi
  if check_server "$d/server_commented.ts" >/dev/null 2>&1; then echo "selftest FAIL: //-commented-out headers NOT caught (dead headers should not satisfy the lock)"; sf=1; else echo "selftest PASS: //-commented-out headers -> FAIL"; fi
  if check_wf "$d/wf_ok.yml" >/dev/null 2>&1; then echo "selftest PASS: wf asserts -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  if check_wf "$d/wf_bad.yml" >/dev/null 2>&1; then echo "selftest FAIL: wf missing assertion NOT caught"; sf=1; else echo "selftest PASS: wf missing assertion -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: runtime-security selftest"; exit 0; } || { echo "FAIL: runtime-security selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: runtime-security.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors adopter-export-wired's detector): this verifies the kit's OWN golden-path
# pipeline. On an adopter tree both kit markers are export-ignored/stripped → nothing to verify →
# N/A. Fail-closed on the kit: ROADMAP-KIT.md remains even if golden-path is deleted, so the
# [ -f "$WF" ] check below still FAILs.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "runtime-security: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$SERVER" ] || { echo "FAIL: reference server not found: $SERVER"; fail=1; }
[ -f "$WF" ]     || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_server "$SERVER" || fail=1; check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: reference app ships security headers + golden-path asserts them on the booted app"; exit 0; }
echo "FAIL: runtime-security under-wired"; exit 1
