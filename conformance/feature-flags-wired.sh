#!/bin/sh
# feature-flags-wired.sh — regression-lock for the E2 feature-flag reference + its golden-path proof.
# Asserts the kill-switch vertical is wired end-to-end so it cannot silently rot: the flag registry,
# the flagged endpoint, the flag-aware smoke check, and the golden-path two-boot flip drill. This
# locks the WIRING; the BEHAVIOUR (the greeting really flips) is proven by golden-path RUNNING smoke.
# Usage: sh conformance/feature-flags-wired.sh [--selftest]
set -eu

SCAFFOLD="${FF_SCAFFOLD:-profiles/typescript-node/scaffold}"
WF="${FF_WF:-.github/workflows/golden-path.yml}"

check_wired() {  # <scaffold-dir> <workflow-file>
  sc=$1; wf=$2; miss=0
  # Strip line comments from the workflow before token-matching, so a token that appears only in a
  # comment (or a commented-out step) cannot satisfy the lock — the wiring must be LIVE. (The R1
  # lesson: a line-grep must not pass on inert text; mirrors ci-selftest-coverage's comment-strip.)
  wf_code=$(sed 's/#.*//' "$wf" 2>/dev/null || true)
  [ -f "$sc/src/flags.ts" ] || { echo "FAIL: missing $sc/src/flags.ts (flag registry)"; miss=1; }
  grep -qF -- '/greeting' "$sc/src/server.ts" 2>/dev/null || { echo "FAIL: $sc/src/server.ts has no /greeting endpoint"; miss=1; }
  grep -qF -- '/greeting' "$sc/scripts/smoke.sh" 2>/dev/null || { echo "FAIL: $sc/scripts/smoke.sh does not check /greeting"; miss=1; }
  grep -qF -- 'FEATURE_NEW_GREETING' "$sc/scripts/smoke.sh" 2>/dev/null || { echo "FAIL: $sc/scripts/smoke.sh does not read FEATURE_NEW_GREETING"; miss=1; }
  printf '%s\n' "$wf_code" | grep -qF -- 'FEATURE_NEW_GREETING=true' || { echo "FAIL: $wf has no live flag-ON boot (FEATURE_NEW_GREETING=true)"; miss=1; }
  printf '%s\n' "$wf_code" | grep -qF -- 'scripts/smoke.sh' || { echo "FAIL: $wf does not run scripts/smoke.sh"; miss=1; }
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0; d=$(mktemp -d)
  # OK fixture: all tokens present.
  mkdir -p "$d/sc/src" "$d/sc/scripts"
  printf 'export const FLAGS = {};\n' > "$d/sc/src/flags.ts"
  printf 'if (req.url === "/greeting") {}\n' > "$d/sc/src/server.ts"
  printf 'curl "$BASE/greeting"\nFEATURE_NEW_GREETING\n' > "$d/sc/scripts/smoke.sh"
  printf 'docker run -e FEATURE_NEW_GREETING=true img\nsh scripts/smoke.sh\n' > "$d/ok.yml"
  if check_wired "$d/sc" "$d/ok.yml" >/dev/null 2>&1; then echo "PASS: selftest complete fixture wired"; else echo "FAIL: selftest complete fixture wrongly failed"; sfail=1; fi
  # BAD fixture: workflow missing the flag-ON boot (the drill removed) -> must FAIL.
  printf 'docker run img\nsh scripts/smoke.sh\n' > "$d/bad.yml"
  if check_wired "$d/sc" "$d/bad.yml" >/dev/null 2>&1; then echo "FAIL: selftest missing flip-step not detected"; sfail=1; else echo "PASS: selftest missing flip-step detected"; fi
  # BAD fixture 2: the flip tokens present ONLY in comments -> must FAIL (the comment-strip de-vacuums).
  printf '# docker run -e FEATURE_NEW_GREETING=true img\n# sh scripts/smoke.sh\n' > "$d/commented.yml"
  if check_wired "$d/sc" "$d/commented.yml" >/dev/null 2>&1; then echo "FAIL: selftest commented-out flip not detected"; sfail=1; else echo "PASS: selftest commented-out flip detected"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: feature-flags-wired selftest"; exit 0; } || { echo "FAIL: feature-flags-wired selftest"; exit 1; }
fi

# Kit-self (mirrors adopter-export-wired's detector): this verifies the kit's OWN golden-path
# pipeline. On an adopter tree both kit markers are export-ignored/stripped → nothing to verify →
# N/A. Fail-closed on the kit: ROADMAP-KIT.md remains even if golden-path is deleted, so the
# [ -f "$WF" ] check below still FAILs.
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "feature-flags-wired: N/A — kit-self check (golden-path is the kit's own pipeline; not applicable outside the kit repo)"; exit 0; fi
[ -f "$WF" ] || { echo "FAIL: golden-path workflow not found: $WF"; exit 1; }
if check_wired "$SCAFFOLD" "$WF"; then echo "OK: feature-flag reference + golden-path flip wired"; exit 0; else echo "FAIL: feature-flag vertical under-wired"; exit 1; fi
