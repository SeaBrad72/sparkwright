#!/bin/sh
# assurance-tiers.sh — drift-guard (Slice 11d): the compliance crosswalk states each Containment-arc
# control at its REAL responsibility tier, and they cannot silently revert. Asserts, per control
# (matched by a row-label regex), that its crosswalk row carries the expected tier token
# (Kit-enforced / Kit-assisted). This verifies the tiers are STATED (documentation drift), NOT that
# they are "true" — enforcement reality lives in the controls themselves (11a/b/c).
#
#   sh conformance/assurance-tiers.sh [crosswalk-path]   (default: docs/enterprise/compliance-crosswalk.md)
#   sh conformance/assurance-tiers.sh --selftest
# Exit: 0 = all tiers stated correctly · 1 = a row missing or at the wrong tier. POSIX sh; dash-clean.
set -eu

check_file() {
  cw="$1"
  if [ ! -f "$cw" ]; then echo "FAIL: crosswalk not found ($cw)"; return 1; fi
  fail=0
  # assert_tier <row-label-regex> <expected-tier> <human-name>
  assert_tier() {
    _lab="$1"; _tier="$2"; _name="$3"
    _row=$(grep -iE "$_lab" "$cw" | head -1 || true)
    if [ -z "$_row" ]; then
      echo "FAIL: no crosswalk row for $_name (/$_lab/)"; fail=1; return 0
    fi
    if printf '%s' "$_row" | grep -qF "$_tier"; then
      echo "PASS: $_name -> $_tier"
    else
      echo "FAIL: $_name must be '$_tier' — its crosswalk row carries a different tier (drift / silent revert?)"; fail=1
    fi
  }
  assert_tier 'MCP capability gate'        'Kit-enforced' 'MCP capability gate'
  assert_tier 'network-egress allowlist'   'Kit-assisted' 'network egress allowlist'
  assert_tier 'sandboxed filesystem'       'Kit-assisted' 'sandboxed filesystem'
  assert_tier 'scoped short-lived tokens'  'Kit-assisted' 'scoped short-lived tokens'
  assert_tier 'separate prod credentials'  'Kit-assisted' 'separate prod credentials'
  if [ "$fail" -ne 0 ]; then echo "assurance-tiers: FAIL ($cw)"; return 1; fi
  echo "assurance-tiers: OK — arc controls stated at their real tier ($cw)"
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)
  hdr='| Kit control | Where | SOC 2 | ISO | SSDF | Evidence | Responsibility |'

  good="$base/good.md"
  {
    printf '%s\n' "$hdr"
    printf '| Agent/runtime MCP capability gate (deny-by-default) | x | x | x | x | ev | Kit-enforced |\n'
    printf '| Agent/runtime platform boundary · network-egress allowlist | x | x | x | x | ev | Kit-assisted |\n'
    printf '| Agent/runtime platform boundary · sandboxed filesystem | x | x | x | x | ev | Kit-assisted |\n'
    printf '| Agent/runtime platform boundary · scoped short-lived tokens | x | x | x | x | ev | Kit-assisted |\n'
    printf '| Agent/runtime platform boundary · separate prod credentials (SoD) | x | x | x | x | ev | Kit-assisted |\n'
  } > "$good"
  if check_file "$good" >/dev/null 2>&1; then echo "selftest PASS: correct tiers -> OK"; else echo "selftest FAIL: correct tiers should pass"; st=1; fi

  rev="$base/reverted.md"
  sed 's/network-egress allowlist | x | x | x | x | ev | Kit-assisted/network-egress allowlist | x | x | x | x | ev | Org-owned/' "$good" > "$rev"
  if check_file "$rev" >/dev/null 2>&1; then echo "selftest FAIL: reverted egress (Org-owned) should FAIL"; st=1; else echo "selftest PASS: reverted egress -> FAIL"; fi

  miss="$base/missing.md"
  grep -v 'MCP capability gate' "$good" > "$miss"
  if check_file "$miss" >/dev/null 2>&1; then echo "selftest FAIL: missing MCP row should FAIL"; st=1; else echo "selftest PASS: missing MCP row -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "assurance-tiers --selftest: FAIL" >&2; return 1; fi
  echo "assurance-tiers --selftest: OK (correct/reverted/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) check_file "${1:-docs/enterprise/compliance-crosswalk.md}"; exit $? ;;
esac
