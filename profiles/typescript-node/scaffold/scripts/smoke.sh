#!/bin/sh
# Smoke test — post-deploy / boot-time sanity. Hits a RUNNING service and checks the core flow.
# This is NOT the unit/integration suite (in-process) and NOT conformance (kit-contract checks) —
# it proves a live, booted service answers over HTTP. See RUNBOOK §4 (post-deploy gate).
#
# Usage:  BASE_URL=http://localhost:3000 sh scripts/smoke.sh   (BASE_URL defaults to :3000)
# Wire it as `npm run smoke`. Exits non-zero on ANY failed check so CI/post-deploy gates catch it.
#
# Check 2 is a FEATURE-FLAG kill-switch proof: GET /greeting must reflect the flag state this
# process was booted with. smoke reads its OWN FEATURE_NEW_GREETING to compute the expected body,
# so a single run validates "the endpoint honours the configured flag". The golden-path workflow
# runs this twice — once flag-OFF (kill-switch greeting), once flag-ON (new greeting) — to prove
# both branches end-to-end. See docs/operations/feature-flags.md.
#
# ADAPT: replace the example /items resource below with one real core-flow resource of your service
# — a POST that writes through your store and a GET that reads it back. Keep liveness + the flag
# check first (or swap the flag check for one of your own flags).
set -eu

BASE="${BASE_URL:-http://localhost:3000}"
OUT="$(mktemp)"
fail=0

check() { # <desc> <expected-code> <actual-code>
  if [ "$2" = "$3" ]; then printf 'PASS  %s (%s)\n' "$1" "$3"
  else printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3"; fail=1; fi
}

# 1. liveness — the service is up and the health endpoint answers 200.
# `|| code=000` keeps set -e from aborting on a connection error (curl already prints 000 to stdout
# on failure, so the fallback fires only if the substitution itself errored — no doubled value).
code=$(curl -s -o "$OUT" -w '%{http_code}' "$BASE/healthz") || code=000
check "GET /healthz" 200 "$code"

# 2. feature-flag kill-switch proof — GET /greeting reflects FEATURE_NEW_GREETING this run was given.
#    Strict 'true' parse mirrors src/flags.ts: only the exact string "true" expects the new greeting.
if [ "${FEATURE_NEW_GREETING:-}" = "true" ]; then
  expected_greeting='Hello, world! (new)'
else
  expected_greeting='Hello, world!'
fi
code=$(curl -s -o "$OUT" -w '%{http_code}' "$BASE/greeting") || code=000
check "GET /greeting" 200 "$code"
if grep -qF "$expected_greeting" "$OUT" && ! { [ "${FEATURE_NEW_GREETING:-}" != "true" ] && grep -qF '(new)' "$OUT"; }; then
  printf 'PASS  /greeting reflects flag state (FEATURE_NEW_GREETING=%s)\n' "${FEATURE_NEW_GREETING:-unset}"
else
  printf 'FAIL  /greeting did not reflect flag state (FEATURE_NEW_GREETING=%s; body: %s)\n' "${FEATURE_NEW_GREETING:-unset}" "$(cat "$OUT")"; fail=1
fi

# 3. core flow (write) — POST an example resource; expect 201 Created.
#    ADAPT the path + JSON body to a real resource of your service, or remove if you have none.
# code=$(curl -s -o "$OUT" -w '%{http_code}' -X POST "$BASE/items" \
#   -H 'content-type: application/json' -d '{"name":"smoke-test"}') || code=000
# check "POST /items -> 201" 201 "$code"

# 4. core flow (read) — GET the resource back; expect 200 OK.
# code=$(curl -s -o "$OUT" -w '%{http_code}' "$BASE/items?limit=1") || code=000
# check "GET /items -> 200" 200 "$code"

rm -f "$OUT"
if [ "$fail" = 0 ]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL"; exit 1; fi
