#!/bin/sh
# containment-audit-wired.sh — regression-lock for the E4a containment-audit (behavioural proof
# that the reference `agent` sandbox actually contains). Asserts the runner + its golden-path job
# + the negative/positive probe PAIRING can't silently rot. Static (no docker) — the live proof
# is the golden-path `containment-audit` job. Usage: [--selftest]
set -eu
AUDIT="${CONTAINMENT_AUDIT:-scripts/containment-audit.sh}"
WF="${GOLDEN_PATH_WF:-.github/workflows/golden-path.yml}"
GUARD="${GUARD_CORE:-.claude/hooks/guard-core.sh}"

check_script() {  # <audit-file> — every containment NEGATIVE probe AND the tmpfs POSITIVE liveness anchor (no vacuous pass)
  f=$1; miss=0
  for tok in \
    'POS fs-tmp' 'POS fs-work' \
    'NEG fs-root' 'NEG fs-etc' 'NEG host' 'NEG egress' 'NEG caps' \
    'docker compose --profile agent run'; do
    grep -qF -- "$tok" "$f" || { echo "FAIL: containment-audit runner missing: $tok"; miss=1; }
  done
  return $miss
}

check_job() {  # <workflow-file>
  f=$1; miss=0
  for tok in 'containment-audit:' 'sh scripts/containment-audit.sh'; do
    grep -qF -- "$tok" "$f" || { echo "FAIL: golden-path missing containment-audit wiring: $tok"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d)
  # complete runner fixture (tmpfs positive anchor + all negatives + the run invocation)
  printf 'POS fs-tmp\nPOS fs-work\nNEG fs-root\nNEG fs-etc\nNEG host\nNEG egress\nNEG caps\ndocker compose --profile agent run\n' > "$d/ok.sh"
  # neg-only runner (no positive liveness anchor) -> must be caught (vacuous-pass guard)
  printf 'NEG fs-root\nNEG fs-etc\nNEG host\nNEG egress\nNEG caps\ndocker compose --profile agent run\n' > "$d/negonly.sh"
  printf 'containment-audit:\nsh scripts/containment-audit.sh\n' > "$d/ok.yml"
  printf 'some-other-job:\n' > "$d/bad.yml"
  if check_script "$d/ok.sh" >/dev/null 2>&1; then echo "PASS: selftest complete runner"; else echo "FAIL: selftest complete runner wrongly failed"; exit 1; fi
  if check_script "$d/negonly.sh" >/dev/null 2>&1; then echo "FAIL: selftest neg-only runner not caught (vacuous-pass hole)"; exit 1; else echo "PASS: selftest neg-only runner caught"; fi
  if check_job "$d/ok.yml" >/dev/null 2>&1; then echo "PASS: selftest job wired"; else echo "FAIL: selftest job wired wrongly failed"; exit 1; fi
  if check_job "$d/bad.yml" >/dev/null 2>&1; then echo "FAIL: selftest missing job not detected"; exit 1; else echo "PASS: selftest missing job detected"; fi
  echo "OK: containment-audit-wired selftest"; exit 0
fi

# Kit-self (mirrors adopter-export-wired's detector): this verifies the kit's OWN golden-path
# pipeline. On an adopter tree both kit markers are export-ignored/stripped → nothing to verify →
# N/A. Fail-closed on the kit: ROADMAP-KIT.md remains even if golden-path is deleted, so the
# [ -f "$WF" ] check below still FAILs.
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "containment-audit-wired: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$AUDIT" ] || { echo "FAIL: containment-audit runner not found: $AUDIT"; fail=1; }
sh -n "$AUDIT" 2>/dev/null || { echo "FAIL: containment-audit runner does not parse: $AUDIT"; fail=1; }
[ -f "$WF" ]    || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_script "$AUDIT" || fail=1; check_job "$WF" || fail=1; }
# the runner must be control-plane protected (an agent must not be able to weaken the gate)
grep -qF -- 'scripts/containment-audit.sh|*/scripts/containment-audit.sh' "$GUARD" || { echo "FAIL: scripts/containment-audit.sh not control-plane in $GUARD"; fail=1; }
[ "$fail" = 0 ] && { echo "OK: containment-audit wired (runner + golden-path job + probe pairing + control-plane)"; exit 0; }
echo "FAIL: containment-audit under-wired"; exit 1
