#!/bin/sh
# license-check.sh — stack-neutral license-policy gate over a CycloneDX SBOM (SP-1).
# Flags denylisted (strong-copyleft) licenses as a VIOLATION; counts undetermined /
# NOASSERTION components and points to the per-stack upgrade ladder. Reuses gate-sbom
# output — no per-stack license tool. sh + jq (jq is a hard-required kit prerequisite).
#
# HONESTY: green = the DECLARED licenses passed the policy AND undetermined ones were
# surfaced — NOT that licenses are legally cleared. The SBOM has blind spots
# (NOASSERTION / incomplete fields); for higher fidelity see the per-stack upgrade
# ladder in docs/operations/security-scanning.md. Necessary, not sufficient.
#
# Default deny (anchored SPDX prefixes, strong copyleft): AGPL, GPL, SSPL, OSL, EUPL,
# CC-BY-NC. NOTE the anchor excludes LGPL (weak copyleft) by design. Override with
# --policy <file> (newline list of anchored regex patterns; '#' lines ignored).
#
# Usage:
#   sh scripts/license-check.sh --sbom <file> [--policy <file>] [--strict] [--stdout]
#   sh scripts/license-check.sh --selftest
# Exit: 0 = clean (or only-undetermined, non-strict) · 1 = a denylisted license (or
#       undetermined under --strict) · 2 = bad usage / unreadable SBOM.
set -eu

SBOM=""; POLICY=""; STRICT=0
DEFAULT_DENY='^(AGPL|GPL|SSPL|OSL|EUPL|CC-BY-NC)'

deny_regex() {
  if [ -n "$POLICY" ] && [ -f "$POLICY" ]; then
    # join non-comment, non-blank lines with '|'
    _r=$(grep -vE '^[[:space:]]*(#|$)' "$POLICY" | paste -sd '|' -)
    [ -n "$_r" ] && { printf '%s' "$_r"; return; }
  fi
  printf '%s' "$DEFAULT_DENY"
}

# analyze <sbom> <deny-regex>: emits a summary JSON {violations:[{name,lic}], undetermined, total}.
# Conservative for a flagging gate: collects EVERY license entry on a component (not just
# licenses[0]) and splits SPDX expressions on parens / AND / OR into tokens; a component is a
# VIOLATION if ANY token is denylisted (so `A AND GPL`, `MIT OR GPL`, multi-entry arrays, and
# parenthesised expressions all flag — err toward surfacing, never hide a copyleft obligation).
analyze() {
  jq --arg deny "$2" '
    def flat($s): ($s | gsub("[()]"; " ") | split("[[:space:]]+"; "")
                   | map(select(length > 0 and . != "AND" and . != "OR")));
    [ .components[]?
      | { name: (.name // "?"),
          lics: [ .licenses[]? | (.license.id // .license.name // .expression) | select(. != null) ] }
      | . + { toks: ([ .lics[] | flat(.) ] | add // []) }
      | . + { status:
          ( if (.lics | length) == 0 then "undetermined"
            elif (.toks | length) > 0 and ([ .toks[] | select(. != "NOASSERTION") ] | length) == 0 then "undetermined"
            elif ([ .toks[] | select(test($deny)) ] | length) > 0 then "violation"
            else "ok" end ) }
    ] as $c
    | { violations: [ $c[] | select(.status == "violation") | { name, lic: (.toks | join(" ")) } ],
        undetermined: ([ $c[] | select(.status == "undetermined") ] | length),
        total: ($c | length) }
  ' "$1"
}

run() {
  [ -n "$SBOM" ] || { echo "license-check: --sbom <file> required" >&2; exit 2; }
  [ -f "$SBOM" ] || { echo "license-check: SBOM not found: $SBOM" >&2; exit 2; }
  # Fail closed on input that isn't a CycloneDX SBOM — a license gate that "passes" because it
  # couldn't read its input is worse than useless. (Non-JSON or valid-JSON-without-.components.)
  jq -e 'has("components")' "$SBOM" >/dev/null 2>&1 || { echo "license-check: not a CycloneDX SBOM (no .components) — $SBOM" >&2; exit 2; }
  _deny=$(deny_regex)
  _sum=$(analyze "$SBOM" "$_deny") || { echo "license-check: could not parse SBOM (not CycloneDX JSON?)" >&2; exit 2; }
  _v=$(printf '%s' "$_sum" | jq '.violations | length')
  _u=$(printf '%s' "$_sum" | jq '.undetermined')
  _t=$(printf '%s' "$_sum" | jq '.total')
  printf 'license-check: %s component(s) scanned · %s policy violation(s) · %s undetermined\n' "$_t" "$_v" "$_u"
  [ "$_t" -eq 0 ] && printf '  WARN: 0 components in the SBOM — an empty scan is not a clearance (check gate-sbom ran).\n'
  if [ "$_v" -gt 0 ]; then
    printf '%s' "$_sum" | jq -r '.violations[] | "  VIOLATION: \(.name) — \(.lic) (denylisted)"'
  fi
  if [ "$_u" -gt 0 ]; then
    printf '  REVIEW: %s component(s) have undetermined licenses the SBOM can'\''t clear — flagged for review.\n' "$_u"
    printf '          For higher-fidelity license detection on this stack, see\n'
    printf '          docs/operations/security-scanning.md -> per-stack upgrade.\n'
  fi
  if [ "$_v" -gt 0 ]; then echo "license-check: FAIL (denylisted license present)"; exit 1; fi
  if [ "$_u" -gt 0 ] && [ "$STRICT" -eq 1 ]; then echo "license-check: FAIL (undetermined under --strict)"; exit 1; fi
  echo "license-check: OK (no denylisted licenses; undetermined surfaced for review). NOTE: declared licenses only — not a legal clearance."
  exit 0
}

selftest() {
  st_fail=0
  fx="$(dirname "$0")/fixtures/sbom/sample-cyclonedx.json"
  _deny="$DEFAULT_DENY"
  out=$(analyze "$fx" "$_deny")
  _names=$(printf '%s' "$out" | jq -c '[.violations[].name] | sort')
  # 3 violations: beta (plain GPL), epsilon (Apache AND GPL — conjunctive), zeta (multi-entry MIT+GPL)
  [ "$(printf '%s' "$out" | jq '.violations | length')" = "3" ] || { echo "selftest FAIL: expected 3 violations (got $(printf '%s' "$out" | jq '.violations|length'))"; st_fail=1; }
  [ "$_names" = '["beta","epsilon","zeta"]' ] || { echo "selftest FAIL: violations should be beta/epsilon/zeta, got $_names"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq '.undetermined')" = "1" ] || { echo "selftest FAIL: expected 1 undetermined (gamma)"; st_fail=1; }
  # LGPL (delta) must NOT be flagged — anchored regex excludes weak copyleft (H1/H2 regression-lock)
  [ "$(printf '%s' "$out" | jq -r '[.violations[].name] | index("delta")')" = "null" ] || { echo "selftest FAIL: LGPL delta wrongly flagged"; st_fail=1; }
  # end-to-end exit code: default run over the fixture FAILs (GPL present)
  # Use a subshell with explicit globals to avoid POSIX prefix-assignment scoping issues
  if ( SBOM="$fx"; STRICT=0; POLICY=""; run >/dev/null 2>&1 ); then
    echo "selftest FAIL: fixture run should exit 1 (GPL)"; st_fail=1
  else
    :
  fi
  if [ "$st_fail" -ne 0 ]; then echo "license-check --selftest: FAIL" >&2; return 1; fi
  echo "license-check --selftest: OK (GPL flagged, LGPL not, undetermined counted, fixture FAILs)"
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --sbom) SBOM=${2:?}; shift 2 ;;
    --policy) POLICY=${2:?}; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --stdout) shift ;;
    --selftest) selftest; exit $? ;;
    *) echo "usage: license-check.sh --sbom <file> [--policy <file>] [--strict] | --selftest" >&2; exit 2 ;;
  esac
done
run
