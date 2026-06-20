#!/bin/sh
# Smoke test — post-deploy / boot-time sanity. Hits a RUNNING service and checks the core flow.
# This is NOT the unit/integration suite (in-process) and NOT conformance (kit-contract checks) —
# it proves a live, booted service answers over HTTP. See RUNBOOK §4 (post-deploy gate).
#
# Usage:  BASE_URL=http://localhost:3000 sh scripts/smoke.sh   (BASE_URL defaults to :3000)
# Wire it as `npm run smoke`. Exits non-zero on ANY failed check so CI/post-deploy gates catch it.
#
# ADAPT: replace the example resource (/items) below with one real core-flow resource of your service
# — a POST that writes through your store and a GET that reads it back. Keep the liveness check first.
set -eu

BASE="${BASE_URL:-http://localhost:3000}"
OUT="$(mktemp)"
fail=0

check() { # <desc> <expected-code> <actual-code>
  if [ "$2" = "$3" ]; then printf 'PASS  %s (%s)\n' "$1" "$3"
  else printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3"; fail=1; fi
}

# 1. liveness — the service is up and the health endpoint answers 200.
# `|| code=000` (outside the substitution) keeps set -e from aborting on a connection error AND
# avoids a doubled code: curl already prints `000` to stdout on failure, so the fallback only fires
# if the substitution itself errored — never appending a second value.
code=$(curl -s -o "$OUT" -w '%{http_code}' "$BASE/healthz") || code=000
check "GET /healthz" 200 "$code"

# 2. core flow (write) — POST an example resource; expect 201 Created.
#    ADAPT the path + JSON body to a real resource of your service.
code=$(curl -s -o "$OUT" -w '%{http_code}' -X POST "$BASE/items" \
  -H 'content-type: application/json' -d '{"name":"smoke-test"}') || code=000
check "POST /items -> 201" 201 "$code"

# 3. core flow (read) — GET the resource back; expect 200 OK.
code=$(curl -s -o "$OUT" -w '%{http_code}' "$BASE/items?limit=1") || code=000
check "GET /items -> 200" 200 "$code"

rm -f "$OUT"
if [ "$fail" = 0 ]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL"; exit 1; fi
