#!/bin/sh
# containment-audit.sh — boot the reference `agent` sandbox and PROVE it contains (E4a).
#
# Behavioural proof (NOT attestation) of three controls the shipped compose `agent` service
# enforces: FS-scope (read_only root + work-tree-only mount), egress (network_mode: none),
# caps (cap_drop: [ALL] + no-new-privileges). Each NEGATIVE probe (a forbidden op MUST fail
# with the right error) is paired with a POSITIVE control (an allowed op MUST succeed) so a
# dead or broken container cannot vacuously pass.
#
# SCOPE: proves the SHIPPED reference container actually contains. It does NOT prove the
# adopter wired it into their deployment (that stays the RUNBOOK attestation in
# conformance/containment-ready.sh) — the kit proves its artifact; the adopter attests theirs.
#
# Usage:
#   sh scripts/containment-audit.sh [project-dir]   (default .; needs docker + an `agent` service)
#   sh scripts/containment-audit.sh --selftest       (static usage check; no docker)
# Exit: 0 all probes hold (or docker absent + not required) · 1 a breach / broken container.
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require)  REQUIRE=1 ;;
    --selftest) echo "containment-audit --selftest: OK (usage parse; behavioural proof runs in golden-path CI)"; exit 0 ;;
    -*) echo "usage: containment-audit.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *)  DIR="$a" ;;
  esac
done

# docker + compose present?
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: docker/compose unavailable and a behavioural containment proof is required (CI/--require)."; exit 1
  fi
  echo "SKIP: docker/compose unavailable — cannot boot the sandbox to probe it (run in CI for the real proof)."; exit 0
fi

# An `agent` service to audit?
COMPOSE=""
for f in "$DIR/compose.yaml" "$DIR/compose.yml" "$DIR/docker-compose.yaml" "$DIR/docker-compose.yml"; do
  [ -f "$f" ] && { COMPOSE="$f"; break; }
done
[ -n "$COMPOSE" ] || { echo "FAIL: no compose file in $DIR — nothing to audit."; exit 1; }
grep -Eq '^[[:space:]]*agent:' "$COMPOSE" || { echo "FAIL: no \`agent\` service in $COMPOSE — nothing to audit."; exit 1; }

cleanup() { ( cd "$DIR" && docker compose --profile agent down --remove-orphans >/dev/null 2>&1 ) || true; }
trap cleanup EXIT INT TERM

echo "containment-audit: building the agent sandbox in $DIR ..."
( cd "$DIR" && docker compose --profile agent build agent ) || { echo "FAIL: agent sandbox build failed."; exit 1; }

# The in-container probe matrix. Prints one marker line per probe; exits non-zero on any breach.
# Markers are load-bearing (containment-audit-wired.sh greps them): POS/NEG <control>.
PROBE='
fail=0
# FS POSITIVE controls (prove the container is ALIVE + the boundary, not a broken harness, blocks)
if echo x > /work/.ca_probe 2>/dev/null && rm -f /work/.ca_probe 2>/dev/null; then echo "POS fs-work: PASS"; else echo "POS fs-work: FAIL"; fail=1; fi
if echo x > /tmp/.ca_probe 2>/dev/null; then echo "POS fs-tmp: PASS"; rm -f /tmp/.ca_probe; else echo "POS fs-tmp: FAIL"; fail=1; fi
# FS NEGATIVE: read-only root
if echo x > /ca_probe 2>/dev/null; then echo "NEG fs-root: FAIL (root writable)"; rm -f /ca_probe; fail=1; else echo "NEG fs-root: PASS (root read-only)"; fi
if echo x > /etc/ca_probe 2>/dev/null; then echo "NEG fs-etc: FAIL (/etc writable)"; rm -f /etc/ca_probe; fail=1; else echo "NEG fs-etc: PASS (/etc read-only)"; fi
# Host-unreachable NEGATIVE: no host secrets/socket mounted
if [ -e /var/run/docker.sock ] || [ -e /root/.aws ] || [ -e /root/.ssh ] || [ -e "$HOME/.aws" ] || [ -e "$HOME/.ssh" ]; then echo "NEG host: FAIL (host path reachable)"; fail=1; else echo "NEG host: PASS (host unreachable)"; fi
# Egress NEGATIVE: outbound connect must fail (node is guaranteed in the builder stage; IP avoids DNS)
ev=$(node -e "var s=require(\"net\").connect(443,\"1.1.1.1\");s.setTimeout(5000);s.on(\"connect\",function(){console.log(\"CONNECTED\");process.exit(0)});s.on(\"timeout\",function(){console.log(\"BLOCKED-timeout\");process.exit(3)});s.on(\"error\",function(e){console.log(\"BLOCKED-\"+e.code);process.exit(3)});" 2>&1) || true
case "$ev" in
  *CONNECTED*) echo "NEG egress: FAIL (network reachable: $ev)"; fail=1 ;;
  *BLOCKED*)   echo "NEG egress: PASS ($ev)" ;;
  *)           echo "NEG egress: FAIL (inconclusive: $ev)"; fail=1 ;;
esac
# Caps NEGATIVE: a CAP-gated op must fail (mknod needs CAP_MKNOD). Fail-closed if the tool is absent.
if ! command -v mknod >/dev/null 2>&1; then echo "NEG caps: FAIL (mknod absent — cannot probe; fail-closed)"; fail=1;
elif mknod /tmp/.ca_dev c 1 3 2>/dev/null; then echo "NEG caps: FAIL (mknod succeeded — caps not dropped)"; rm -f /tmp/.ca_dev; fail=1;
else echo "NEG caps: PASS (mknod denied — caps dropped)"; fi
exit $fail
'

echo "containment-audit: probing the booted sandbox ..."
out=$( cd "$DIR" && docker compose --profile agent run --rm -T agent sh -c "$PROBE" 2>&1 ) && rc=0 || rc=$?
echo "$out"

# Anti-vacuous gate: the run must exit 0 AND every control marker must be PASS in the output
# (so an empty/short-circuited run cannot pass on exit code alone).
miss=0
for m in "POS fs-work: PASS" "POS fs-tmp: PASS" "NEG fs-root: PASS" "NEG fs-etc: PASS" "NEG host: PASS" "NEG egress: PASS" "NEG caps: PASS"; do
  printf '%s\n' "$out" | grep -qF -- "$m" || { echo "containment-audit: MISSING expected PASS marker: $m"; miss=1; }
done

if [ "$rc" -eq 0 ] && [ "$miss" -eq 0 ]; then
  echo "containment-audit: OK — FS-scope / egress / caps all PROVEN (each negative paired with a positive control)."
  exit 0
fi
echo "FAIL: containment audit — the sandbox did not contain (rc=$rc, missing-markers=$miss). See probe lines above."
exit 1
