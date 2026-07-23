#!/bin/sh
# model-tiering.sh — KW20(b) claim verifier: the model-tier resolver enforces pins + floors +
# fail-closed, and the policy/resolver are agent-immutable (control-plane).
#
# SCOPE — a green run proves the resolver's DECISION LOGIC is correct + non-vacuous and the guard
# lock is PRESENT. It does NOT prove any harness binds the abstract tier to a real model call
# (that is the per-harness adapter's job, Slice 2 / NATIVE). Necessary, not sufficient.
#
# Usage: sh conformance/model-tiering.sh [--require] | --selftest
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODEL_TIERS_CONFIG="$ROOT/.kit/model-tiers.conf"; export MODEL_TIERS_CONFIG
fail=0

# 1. behavioral teeth: the resolver's own non-vacuity selftest (pins/floors/liveness/fail-closed)
if sh "$ROOT/scripts/model-tier.sh" --selftest >/dev/null 2>&1; then echo "PASS: resolver selftest"
else echo "FAIL: resolver selftest (pins/floors/liveness/fail-closed)"; fail=1; fi

# 2. structural: policy config present + declares the load-bearing keys
for k in TIERS PIN VARIABLE APEX_ELIGIBLE FLOOR_CHANGE_CLASS; do
  if grep -q "^$k=" "$ROOT/.kit/model-tiers.conf" 2>/dev/null; then echo "PASS: config has $k"
  else echo "FAIL: .kit/model-tiers.conf missing $k"; fail=1; fi
done

# 3. completeness lock: the guard actually names the config as control-plane (else Task 2 regressed)
if grep -q 'model-tiers\.conf' "$ROOT/.claude/hooks/guard-core.sh" 2>/dev/null; then echo "PASS: guard locks model-tiers.conf"
else echo "FAIL: guard-core.sh does not lock model-tiers.conf"; fail=1; fi

if [ "$fail" -eq 0 ]; then echo "model-tiering: ALL PASS"; exit 0; else echo "model-tiering: FAILURES"; exit 1; fi
