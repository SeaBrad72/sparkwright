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

check_server() {  # <server.ts> — sets all four security headers
  f=$1; miss=0
  for h in $HEADERS; do
    grep -qF -- "$h" "$f" || { echo "FAIL: $f missing security header: $h"; miss=1; }
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
  printf "runtime-security: OK\nx-content-type-options: nosniff\nx-frame-options: DENY\ncontent-security-policy: default-src 'none'\nreferrer-policy: no-referrer\n" > "$d/wf_ok.yml"
  printf 'some other step\n' > "$d/wf_bad.yml"
  if check_server "$d/server_ok.ts" >/dev/null 2>&1; then echo "selftest PASS: server all headers -> PASS"; else echo "selftest FAIL: server_ok wrongly failed"; sf=1; fi
  if check_server "$d/server_bad.ts" >/dev/null 2>&1; then echo "selftest FAIL: missing header NOT caught"; sf=1; else echo "selftest PASS: missing header -> FAIL"; fi
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
