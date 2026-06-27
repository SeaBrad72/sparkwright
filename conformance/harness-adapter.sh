#!/bin/sh
# harness-adapter.sh — composing conformance meta-check (harness-neutrality N2).
# Proves the adapter at adapters/<harness>/ satisfies the boundary contract
# (docs/operations/harness-adapters.md):
#   1. manifest valid (JSON; .harness non-empty; controlPlanePaths non-empty; declared
#      bindingFiles exist; all 5 dimensions declared with a valid level)
#   2. the Kit-enforced FLOOR holds for every dimension (the equal-enforcement guarantee)
#   3. every `native` claim carries a proof that actually passes (the lying-native guard)
#   4. --selftest exercises conformant / malformed / lying-native fixtures
# COMPOSES existing checks (agents-brief, guard-core-sourced, guard-wired, mcp-policy) — never
# reimplements them. THREE-STATE: 0 ok · 1 violation · 2 UNVERIFIED (jq absent / adapter missing);
# 2 escalates to 1 under CI/--require. POSIX sh; dash-clean. Run from the repo root.
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
ADAPTER=""
MODE="run"
while [ $# -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1; shift ;;
    --selftest) MODE="selftest"; shift ;;
    -*) echo "usage: harness-adapter.sh [adapters/<harness>] [--require] | --selftest" >&2; exit 2 ;;
    *) ADAPTER="$1"; shift ;;
  esac
done
[ -n "$ADAPTER" ] || ADAPTER="adapters/claude-code"

DIMS="context-binding command-guard history-protection review-roles mcp-gate orchestration"

unverifiable() {
  if [ "$REQUIRE" = "1" ]; then echo "FAIL: harness-adapter could not verify ($1) — required (CI/--require)."; exit 1; fi
  echo "UNVERIFIED: $1 — (NOT a pass)."; exit 2
}

# floor_holds <dim>: 0 if the Kit-enforced floor for <dim> is present in this repo (reuses checks).
floor_holds() {
  case "$1" in
    context-binding)    sh conformance/agents-brief.sh >/dev/null 2>&1 ;;
    command-guard)      [ -f hooks/pre-push ] && [ -f scripts/kit-guard ] && [ -f conformance/agent-boundary.sh ] && sh conformance/guard-core-sourced.sh >/dev/null 2>&1 ;;
    history-protection) [ -f hooks/pre-push ] ;;
    review-roles)       [ -f conformance/agent-boundary.sh ] && [ -f conformance/branch-protection.sh ] ;;
    mcp-gate)           [ -f scripts/kit-guard ] ;;
    orchestration)      [ -f agents/orchestrator.agent.md ] && [ -f agents/engineer.agent.md ] && [ -f agents/reviewer.agent.md ] && [ -f agents/security.agent.md ] ;;
  esac
}

# native_proof_ok <manifest> <dim>: 0 if the dim's declared native proof passes. A native dim MUST
# carry a proof (a check and/or files); none => not ok (cannot claim native unverified).
native_proof_ok() {
  m=$1; d=$2
  chk=$(jq -r --arg d "$d" '.dimensions[$d].proof.check // empty' "$m")
  # shellcheck disable=SC2086 # intentional word-split: files is a newline-separated list of paths
  files=$(jq -r --arg d "$d" '.dimensions[$d].proof.files[]? // empty' "$m")
  [ -n "$chk" ] || [ -n "$files" ] || return 1
  if [ -n "$chk" ]; then
    # D2 allowlist: execute a proof.check ONLY if it is a bare conformance/*.sh path
    # (no metacharacters, no args, no traversal) that exists. Anything else => not ok, NOT run.
    case "$chk" in
      conformance/*.sh) : ;;
      *) return 1 ;;
    esac
    if printf '%s' "$chk" | grep -Eq '[^A-Za-z0-9._/-]' || printf '%s' "$chk" | grep -q '\.\.'; then
      return 1
    fi
    [ -f "$chk" ] || return 1
    if [ -L "$chk" ]; then return 1; fi   # -f follows symlinks; reject a symlinked check
    sh "$chk" >/dev/null 2>&1 || return 1
  fi
  for f in $files; do [ -e "$f" ] || return 1; done
  return 0
}

run() {
  command -v jq >/dev/null 2>&1 || unverifiable "jq not installed (the manifest is JSON)"
  [ -d "$ADAPTER" ] || unverifiable "adapter dir not found: $ADAPTER"
  m="$ADAPTER/adapter.json"
  [ -f "$m" ] || unverifiable "manifest not found: $m"
  jq -e . "$m" >/dev/null 2>&1 || { echo "FAIL: $m is not valid JSON"; exit 1; }

  fail=0
  harness=$(jq -r '.harness // empty' "$m"); [ -n "$harness" ] || { echo "FAIL: .harness is empty"; fail=1; }
  cp=$(jq '(.controlPlanePaths // []) | length' "$m"); [ "$cp" -gt 0 ] || { echo "FAIL: controlPlanePaths is empty"; fail=1; }
  for bf in $(jq -r '.bindingFiles[]? // empty' "$m"); do
    [ -e "$bf" ] || { echo "FAIL: bindingFile missing: $bf"; fail=1; }
  done

  for d in $DIMS; do
    level=$(jq -r --arg d "$d" '.dimensions[$d].level // "missing"' "$m")
    case "$level" in
      missing) echo "FAIL: dimension '$d' not declared"; fail=1; continue ;;
      n-a)     [ "$d" = "mcp-gate" ] || { echo "FAIL: '$d' may not be n-a (only mcp-gate may)"; fail=1; }; continue ;;
      floor|native) : ;;
      *)       echo "FAIL: '$d' has invalid level '$level'"; fail=1; continue ;;
    esac
    if floor_holds "$d"; then : ; else echo "FAIL: '$d' Kit-enforced floor not satisfied"; fail=1; fi
    if [ "$level" = "native" ]; then
      if native_proof_ok "$m" "$d"; then : ; else echo "FAIL: '$d' declared native but its proof is absent or failing (lying-native)"; fail=1; fi
    fi
  done

  if [ "$fail" = "0" ]; then echo "OK: adapter '$harness' satisfies the boundary contract (floor for every dimension; native proofs verified)"; exit 0; fi
  echo "harness-adapter: FAIL ($ADAPTER)"; exit 1
}

selftest() {
  st=0
  base=$(mktemp -d)   # fixtures left in place (no rm; 7e control-plane guard)
  mkconf() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/adapter.json"; }
  expect() {  # <expected-rc> <adapter-dir> <label>
    e=$1; a=$2; lbl=$3
    ( sh "$0" "$a" ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> rc $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }

  mkconf "$base/ok" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 0 "$base/ok" "conformant (all floor, mcp n-a)"

  mkconf "$base/missing" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/missing" "missing review-roles dimension"

  mkconf "$base/missorch" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"}}}'
  expect 1 "$base/missorch" "missing orchestration dimension"

  mkconf "$base/nocp" '{"harness":"fixture","controlPlanePaths":[],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/nocp" "empty controlPlanePaths"

  mkconf "$base/lie" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"files":["does-not-exist-xyz.txt"]}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/lie" "lying-native (native proof file missing)"

  mkconf "$base/badcheck" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"false"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/badcheck" "lying-native (proof.check exits non-zero)"

  mkconf "$base/noproof" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"native"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/noproof" "native with no proof declared"

  mkconf "$base/badbind" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["nope-not-here.txt"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/badbind" "missing bindingFile"

  # D2: proof.check allowlist — a check with shell metacharacters or outside conformance/
  # must be REJECTED BEFORE EXECUTION (no side effect), not run.
  canary="$base/canary"
  mkconf "$base/metachar" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"conformance/agents-brief.sh; touch __CANARY__"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  sed "s#__CANARY__#$canary#" "$base/metachar/adapter.json" > "$base/metachar/adapter.tmp" && mv "$base/metachar/adapter.tmp" "$base/metachar/adapter.json"
  expect 1 "$base/metachar" "proof.check with metacharacters (lying-native)"
  if [ -e "$canary" ]; then echo "selftest FAIL: metachar proof.check EXECUTED (canary created)"; st=1; else echo "selftest PASS: metachar proof.check not executed"; fi
  mkconf "$base/escape" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"../evil.sh"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/escape" "proof.check outside conformance/ (lying-native)"

  # adapter dir not found -> UNVERIFIED(2) local, FAIL(1) under CI/--require
  # shellcheck disable=SC1007 # CI= is intentional: clears CI in the subshell to test non-CI path
  ( CI= REQUIRE=0 sh "$0" "$base/does-not-exist" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "2" ]; then echo "selftest PASS: missing adapter -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: missing adapter want 2 got $g"; st=1; fi
  ( CI=true sh "$0" "$base/does-not-exist" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "1" ]; then echo "selftest PASS: missing adapter + CI -> exit 1"; else echo "selftest FAIL: missing adapter + CI want 1 got $g"; st=1; fi

  [ "$st" = "0" ] && echo "harness-adapter --selftest: OK"
  return "$st"
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  *) run ;;
esac
