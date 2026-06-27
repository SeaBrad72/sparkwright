#!/bin/sh
# claims-registry.sh — run every claim's verifier in conformance/claims.tsv; fail on drift OR on a
# silently-dropped headline claim. Generalises badge-version.sh from one claim (badge==VERSION) to
# N. The registry is CONTROL-PLANE: adding / removing / weakening a claim is a ratified act — you
# cannot quietly drop a claim's verifier to make CI green (the H1 integrity property).
#   sh conformance/claims-registry.sh [--selftest]
# Exit: 0 = all claims hold + coverage intact · 1 = drift / unverified / integrity gap · 2 = usage.
# Three-state per verifier (mirrors verify.sh): exit 0 = PASS · exit 2 = UNVERIFIED (could not confirm
# — surfaced, NOT a pass) · other = FAIL (drift). Verifier output is captured and PRINTED on any
# non-pass, so a CI failure shows WHY (not a swallowed >/dev/null). POSIX sh; dash-clean.
# Verifier contract: a registered verifier MUST emit only STRUCTURAL diagnostics (verdicts, paths,
# identifier NAMES) — never a secret VALUE — because its stdout+stderr is surfaced on a non-pass.
set -eu

REGISTRY="${KIT_CLAIMS:-conformance/claims.tsv}"
# Headline claims that MUST stay registered (no silent drop). Change this set deliberately + ratified.
REQUIRED_IDS="badge-version conformance-ci-wired doc-budget guard-single-source action-pinning security-policy gate-counts drift-watch cost-governance supply-chain-verify gitlab-adoption doctor operate-loop tier-advice named-adapters actionlint-valid template-detectors-aligned provenance-precondition golden-path adopter-preflight adopter-export mode-blind explain feature-flags-wired feature-flags-ready containment-audit token-scope runtime-security agentops-sensor author-not-approver verify-enforced runaway-killswitch version-tag-coherent orchestrator-loop release-tag-on-merge escalation-seam conflict-safe-integration skill-spine"

TAB=$(printf '\t')

# emit_diag <output>: print captured verifier output indented, so non-pass results are debuggable.
emit_diag() { [ -n "$1" ] && printf '%s\n' "$1" | sed 's/^/    | /' || true; }

# run_registry <tsv>: print PASS/UNVERIFIED/FAIL per claim + coverage gaps; return 1 on any non-pass.
run_registry() {
  _reg=$1; _fail=0; _seen=""
  [ -f "$_reg" ] || { echo "FAIL: missing registry $_reg"; return 1; }
  while IFS="$TAB" read -r _id _claim _verifier || [ -n "$_id" ]; do   # `|| [ -n ]` = process a final line with no trailing newline (no silent skip)
    case "$_id" in ''|\#*) continue ;; esac
    if [ -z "$_verifier" ]; then echo "FAIL: claim '$_id' has no verifier"; _fail=1; continue; fi
    case " $_seen " in *" $_id "*) echo "FAIL: duplicate claim id '$_id'"; _fail=1; continue ;; esac
    _seen="$_seen $_id"
    # Capture output + exit code (set -e-safe). Classify three-state; surface diagnostics on non-pass.
    if _out=$(sh -c "$_verifier" 2>&1); then
      echo "PASS: $_id"
    else
      _rc=$?
      if [ "$_rc" = 2 ]; then
        echo "UNVERIFIED: $_id — verifier could not confirm (exit 2): $_verifier"
      else
        echo "FAIL: $_id — verifier reports drift (exit $_rc): $_verifier"
      fi
      emit_diag "$_out"
      _fail=1
    fi
  done < "$_reg"
  for _r in $REQUIRED_IDS; do
    case " $_seen " in *" $_r "*) : ;; *) echo "FAIL: required claim '$_r' missing from registry (silent drop)"; _fail=1 ;; esac
  done
  return $_fail
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)
  # a COMPLETE valid registry: every REQUIRED_ID present with a passing (true) verifier.
  : > "$d/ok.tsv"
  for r in $REQUIRED_IDS; do printf '%s\t%s\ttrue\n' "$r" "claim $r" >> "$d/ok.tsv"; done
  if run_registry "$d/ok.tsv" >/dev/null 2>&1; then echo "PASS: selftest — complete valid registry passes"; else echo "FAIL: selftest — valid registry wrongly rejected"; sfail=1; fi
  # a FAILING verifier must be caught, and its DIAGNOSTICS surfaced (not swallowed)
  cp "$d/ok.tsv" "$d/bad.tsv"; printf '%s\t%s\t%s\n' "extra-bad" "drifted" "echo why-it-drifted; exit 1" >> "$d/bad.tsv"
  bout=$(run_registry "$d/bad.tsv" 2>&1) && { echo "FAIL: selftest — failing verifier not caught"; sfail=1; } || true
  printf '%s\n' "$bout" | grep -q "FAIL: extra-bad" || { echo "FAIL: selftest — failing verifier not labeled FAIL"; sfail=1; }
  printf '%s\n' "$bout" | grep -q "why-it-drifted"  || { echo "FAIL: selftest — verifier diagnostics swallowed (not surfaced)"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — failing verifier detected + diagnostics surfaced"
  # an UNVERIFIED (exit 2) verifier must be labeled UNVERIFIED (not FAIL) AND still fail the registry
  cp "$d/ok.tsv" "$d/unv.tsv"; printf '%s\t%s\t%s\n' "unv-claim" "unverifiable" "echo cant-confirm; exit 2" >> "$d/unv.tsv"
  uout=$(run_registry "$d/unv.tsv" 2>&1) && { echo "FAIL: selftest — exit-2 verifier did not fail the registry"; sfail=1; } || true
  printf '%s\n' "$uout" | grep -q "UNVERIFIED: unv-claim" || { echo "FAIL: selftest — exit-2 not labeled UNVERIFIED (three-state collapsed)"; sfail=1; }
  printf '%s\n' "$uout" | grep -q "cant-confirm"          || { echo "FAIL: selftest — UNVERIFIED diagnostics not surfaced"; sfail=1; }
  printf '%s\n' "$uout" | grep -q "FAIL: unv-claim"       && { echo "FAIL: selftest — UNVERIFIED wrongly relabeled FAIL"; sfail=1; } || true
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — exit-2 labeled UNVERIFIED + surfaced + fails registry"
  # a DROPPED required id must be caught (drop gate-counts)
  grep -v '^gate-counts' "$d/ok.tsv" > "$d/drop.tsv"
  if run_registry "$d/drop.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — silent drop not caught"; sfail=1; else echo "PASS: selftest — dropped required claim detected"; fi
  # a DUPLICATE id must be caught
  cp "$d/ok.tsv" "$d/dup.tsv"; printf '%s\t%s\ttrue\n' "badge-version" "dup" >> "$d/dup.tsv"
  if run_registry "$d/dup.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — duplicate id not caught"; sfail=1; else echo "PASS: selftest — duplicate id detected"; fi
  # an EMPTY verifier must be caught
  cp "$d/ok.tsv" "$d/empty.tsv"; printf '%s\t%s\t\n' "no-verifier" "missing" >> "$d/empty.tsv"
  if run_registry "$d/empty.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — empty verifier not caught"; sfail=1; else echo "PASS: selftest — empty verifier detected"; fi
  if [ "$sfail" -eq 0 ]; then echo "OK: claims-registry selftest"; exit 0; else echo "FAIL: claims-registry selftest"; exit 1; fi
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: claims-registry.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Claims registry ($REGISTRY):"
if run_registry "$REGISTRY"; then
  echo "OK: every registered headline claim holds; coverage intact"
  exit 0
else
  echo "FAIL: a headline claim drifted, could not be verified, or was dropped (see above)"
  exit 1
fi
