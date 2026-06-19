#!/bin/sh
# claims-registry.sh — run every claim's verifier in conformance/claims.tsv; fail on drift OR on a
# silently-dropped headline claim. Generalises badge-version.sh from one claim (badge==VERSION) to
# N. The registry is CONTROL-PLANE: adding / removing / weakening a claim is a ratified act — you
# cannot quietly drop a claim's verifier to make CI green (the H1 integrity property).
#   sh conformance/claims-registry.sh [--selftest]
# Exit: 0 = all claims hold + coverage intact · 1 = drift / integrity gap · 2 = usage. POSIX sh; dash-clean.
set -eu

REGISTRY="${KIT_CLAIMS:-conformance/claims.tsv}"
# Headline claims that MUST stay registered (no silent drop). Change this set deliberately + ratified.
REQUIRED_IDS="badge-version conformance-ci-wired doc-budget guard-single-source action-pinning security-policy gate-counts drift-watch cost-governance supply-chain-verify"

TAB=$(printf '\t')

# run_registry <tsv>: print PASS/FAIL per claim + coverage gaps; return 1 on any failure.
run_registry() {
  _reg=$1; _fail=0; _seen=""
  [ -f "$_reg" ] || { echo "FAIL: missing registry $_reg"; return 1; }
  while IFS="$TAB" read -r _id _claim _verifier || [ -n "$_id" ]; do   # `|| [ -n ]` = process a final line with no trailing newline (no silent skip)
    case "$_id" in ''|\#*) continue ;; esac
    if [ -z "$_verifier" ]; then echo "FAIL: claim '$_id' has no verifier"; _fail=1; continue; fi
    case " $_seen " in *" $_id "*) echo "FAIL: duplicate claim id '$_id'"; _fail=1; continue ;; esac
    _seen="$_seen $_id"
    if sh -c "$_verifier" >/dev/null 2>&1; then
      echo "PASS: $_id"
    else
      echo "FAIL: $_id — verifier reports drift: $_verifier"; _fail=1
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
  # a FAILING verifier must be caught
  cp "$d/ok.tsv" "$d/bad.tsv"; printf '%s\t%s\tfalse\n' "extra-bad" "drifted" >> "$d/bad.tsv"
  if run_registry "$d/bad.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — failing verifier not caught"; sfail=1; else echo "PASS: selftest — failing verifier detected"; fi
  # a DROPPED required id must be caught (drop the last line = gate-counts)
  grep -v '^gate-counts' "$d/ok.tsv" > "$d/drop.tsv"
  if run_registry "$d/drop.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — silent drop not caught"; sfail=1; else echo "PASS: selftest — dropped required claim detected"; fi
  # a DUPLICATE id must be caught
  cp "$d/ok.tsv" "$d/dup.tsv"; printf '%s\t%s\ttrue\n' "badge-version" "dup" >> "$d/dup.tsv"
  if run_registry "$d/dup.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — duplicate id not caught"; sfail=1; else echo "PASS: selftest — duplicate id detected"; fi
  # an EMPTY verifier must be caught
  cp "$d/ok.tsv" "$d/empty.tsv"; printf '%s\t%s\t\n' "no-verifier" "missing" >> "$d/empty.tsv"
  if run_registry "$d/empty.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — empty verifier not caught"; sfail=1; else echo "PASS: selftest — empty verifier detected"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: claims-registry selftest"; exit 0; } || { echo "FAIL: claims-registry selftest"; exit 1; }
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
  echo "FAIL: a headline claim drifted or was dropped (see above)"
  exit 1
fi
