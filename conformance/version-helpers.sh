#!/bin/sh
# version-helpers.sh — shared semver comparison (POSIX sh; SOURCE this, or run --selftest).
# Used by meta-control-fresh.sh and version-tag-coherent.sh. Comparison via `sort -V` (version sort,
# so 1.10.0 > 1.9.0). Callers validate X.Y.Z before comparing; these assume normalized-ish input.
ver_norm() { printf '%s' "$1" | sed 's/^v//'; }
# ver_ge A B : true (0) iff A >= B
ver_ge() {
  _a=$(ver_norm "$1"); _b=$(ver_norm "$2")
  [ "$_a" = "$_b" ] && return 0
  [ "$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | tail -1)" = "$_a" ]
}
# ver_gt A B : true (0) iff A > B
ver_gt() {
  _a=$(ver_norm "$1"); _b=$(ver_norm "$2")
  [ "$_a" = "$_b" ] && return 1
  [ "$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | tail -1)" = "$_a" ]
}
case "$0" in *version-helpers*)
  if [ "${1:-}" = "--selftest" ]; then
    vf=0
    _ck() { if eval "$1"; then echo "PASS: $2"; else echo "version-helpers --selftest: FAIL ($2)"; vf=1; fi; }
    _ck 'ver_ge 1.0.0 1.0.0' "ge equal"
    _ck 'ver_ge 1.2.0 1.1.9' "ge greater"
    _ck '! ver_ge 1.0.0 1.0.1' "ge lesser=false"
    _ck 'ver_ge v2.0.0 1.9.9' "ge strips v"
    _ck 'ver_gt 1.0.1 1.0.0' "gt greater"
    _ck '! ver_gt 1.0.0 1.0.0' "gt equal=false"
    _ck '! ver_gt 1.0.0 2.0.0' "gt lesser=false"
    _ck 'ver_gt 1.10.0 1.9.0' "gt numeric 10>9 (not lexical)"
    _ck 'ver_ge 1.10.0 1.9.0' "ge numeric 10>9 (not lexical)"
    [ "$vf" = 0 ] && { echo "version-helpers --selftest: OK"; exit 0; } || exit 1
  fi
  ;;
esac
