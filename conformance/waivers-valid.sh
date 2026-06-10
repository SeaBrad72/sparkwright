#!/bin/sh
# waivers-valid.sh — validate a brownfield WAIVER-REGISTER.md (governed exceptions to the
# CI gates). A waiver is the honest alternative to faking green; this proves the register is
# well-formed, owned, time-boxed, and not abused. It attests REGISTER HYGIENE — it does NOT
# prove the waived gate is still running in CI (pair it with the gate's own conformance check).
#
# FAILS (fail-closed) if any active waiver is:
#   - on a gate NOT in the waivable allow-list (default-deny — this rejects every spelling of
#     the non-negotiable gates secret-scan / branch-protection: case, markdown, homoglyph, …),
#   - expired (Expires < today),
#   - longer than the 90-day max lifetime, or has Expires < Opened,
#   - missing a required field, or has a malformed / unparsed row.
# N/A-pass when no register exists (greenfield needs none) — adoption-conditional.
#   usage: sh conformance/waivers-valid.sh [REGISTER.md] | --selftest
# Portable POSIX sh; dates anchored to noon UTC (DST-safe) via GNU `date -d` or BSD `date -j -f`.
# See docs/adoption/brownfield.md §5.
set -eu

# Default-deny: only these gates may be waived. Everything else (incl. secret-scan /
# branch-protection and any unknown/typo/spoofed name) is rejected.
WAIVABLE="coverage sbom provenance dependency-vuln a11y container-image"
NONNEGOTIABLE="secret-scan branch-protection"
MAX_DAYS=90

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
is_date() { printf '%s' "$1" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; }
has_nonascii() { printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; }
# normalize a gate cell: lowercase, strip markdown emphasis, trim non-alnum edges. Does NOT
# remove html-comment CONTENTS (that would let `coverage<!--x-->secret-scan` collapse to
# `coverage`); residual junk like `<`, spaces, or comment markers leaves the token non-clean
# and is rejected by the `^[a-z0-9-]+$` check at the call site (positive validation).
gnorm() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/^[^a-z0-9]*//' -e 's/[^a-z0-9]*$//'
}
is_clean_gate() { printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; }
# epoch at noon UTC for a YYYY-MM-DD (DST-safe whole-day math); GNU then BSD.
to_epoch() {
  date -u -d "$1 12:00:00" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %T" "$1 12:00:00" +%s 2>/dev/null
}

# Emit data rows of the "## Active waivers" table ONLY — structurally: everything after the
# `|---|` separator within the section. A non-blank line that contains a pipe but does not
# start with one is a malformed row -> emit a sentinel so validation fails closed.
extract_rows() {
  awk '
    /^##[[:space:]]+Active waivers/ { insec=1; afterhdr=0; hdrseen=0; next }
    /^##[[:space:]]/ { insec=0 }
    !insec { next }
    /^\|([[:space:]]*:?-+:?[[:space:]]*\|)+[[:space:]]*$/ { afterhdr=1; next }   # separator: EVERY cell is dashes/colons (GFM alignment ok); a data row gate of -secret-scan has letters so it is NOT a separator
    # exactly one header row is allowed before the separator; consume it.
    !afterhdr && /^\|/ && !hdrseen { hdrseen=1; next }
    # ANY other table-shaped line before the separator (extra header, data above the
    # separator, or — if no separator ever appears — every data row) is MALFORMED: fail closed.
    !afterhdr && (/^\|/ || (NF>0 && /\|/)) { print "__MALFORMED__" $0; next }
    afterhdr && /^\|/ { print; next }                       # data row (after separator)
    afterhdr && NF>0 && /\|/ { print "__MALFORMED__" $0 }    # data row missing leading pipe
  ' "$1"
}

# validate_register FILE -> 0 valid / 1 invalid (prints findings). Current-shell fail accumulator.
validate_register() {
  reg=$1; today=$(date -u +%Y-%m-%d); tnum=$(printf '%s' "$today" | tr -d -); vfail=0
  tmp=$(mktemp 2>/dev/null || printf '/tmp/wv.%s' "$$")
  extract_rows "$reg" > "$tmp"
  if [ ! -s "$tmp" ]; then
    echo "waivers-valid: register present but no active waivers — OK ($reg)"; return 0
  fi
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in
      __MALFORMED__*) echo "FAIL: malformed waiver row (missing leading '|'): ${row#__MALFORMED__}"; vfail=1; continue ;;
    esac
    gate=$(trim "$(printf '%s' "$row" | awk -F'|' '{print $2}')")
    owner=$(trim "$(printf '%s' "$row" | awk -F'|' '{print $4}')")
    opened=$(trim "$(printf '%s' "$row" | awk -F'|' '{print $5}')")
    expires=$(trim "$(printf '%s' "$row" | awk -F'|' '{print $6}')")
    remediation=$(trim "$(printf '%s' "$row" | awk -F'|' '{print $7}')")
    ratified=$(trim "$(printf '%s' "$row" | awk -F'|' '{print $8}')")
    label="${gate:-<no-gate>}"

    # --- gate validity FIRST (most security-relevant; default-deny allow-list) ---
    if has_nonascii "$gate"; then
      echo "FAIL: waiver gate '$gate' contains non-ASCII characters (possible homoglyph) — rejected"; vfail=1; continue
    fi
    g=$(gnorm "$gate")
    if ! is_clean_gate "$g"; then
      echo "FAIL: waiver gate '$gate' is not a clean single token (markup/comment/whitespace/extra tokens) — rejected"; vfail=1; continue
    fi
    ng_hit=0
    for ng in $NONNEGOTIABLE; do [ "$g" = "$ng" ] && ng_hit=1; done
    if [ "$ng_hit" = "1" ]; then
      echo "FAIL: waiver targets NON-NEGOTIABLE gate '$gate' — never waivable"; vfail=1; continue
    fi
    case " $WAIVABLE " in
      *" $g "*) : ;;
      *) echo "FAIL: waiver gate '$gate' is not a waivable gate (allow-list: $WAIVABLE)"; vfail=1; continue ;;
    esac

    # --- required fields ---
    if [ -z "$owner" ] || [ -z "$opened" ] || [ -z "$expires" ] || [ -z "$remediation" ] || [ -z "$ratified" ]; then
      echo "FAIL: waiver '$label' is missing a required field (owner/opened/expires/remediation/ratified-by)"; vfail=1; continue
    fi
    # --- dates ---
    if ! is_date "$opened" || ! is_date "$expires"; then
      echo "FAIL: waiver '$label' has a non-YYYY-MM-DD date (opened='$opened' expires='$expires')"; vfail=1; continue
    fi
    enum=$(printf '%s' "$expires" | tr -d -)
    [ "$enum" -lt "$tnum" ] && { echo "FAIL: waiver '$label' EXPIRED on $expires (today $today UTC) — renew or remove"; vfail=1; }
    oe=$(to_epoch "$opened" || true); ee=$(to_epoch "$expires" || true)
    if [ -n "$oe" ] && [ -n "$ee" ]; then
      span=$(( (ee - oe) / 86400 ))
      if [ "$span" -lt 0 ]; then
        echo "FAIL: waiver '$label' has Expires ($expires) before Opened ($opened)"; vfail=1
      elif [ "$span" -gt "$MAX_DAYS" ]; then
        echo "FAIL: waiver '$label' lifetime ${span}d exceeds ${MAX_DAYS}d max (opened $opened, expires $expires)"; vfail=1
      fi
    else
      echo "FAIL: waiver '$label' has unparseable dates"; vfail=1
    fi
  done < "$tmp"
  [ "$vfail" -eq 0 ] && echo "waivers-valid: OK — all active waivers are waivable-gate, owned, in-date, within ${MAX_DAYS}d ($reg). NOTE: attests register hygiene, not that the waived gate still runs in CI."
  return "$vfail"
}

selftest() {
  st=0; d=$(mktemp -d 2>/dev/null || printf '/tmp/wvst.%s' "$$"); mkdir -p "$d"
  mk() { printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n%s\n' "$2" > "$d/$1"; }
  expect() { validate_register "$d/$1" >/dev/null 2>&1 && g=0 || g=$?; if [ "$g" = "$2" ]; then echo "selftest PASS: $3"; else echo "selftest FAIL: $3 (want $2 got $g)"; st=1; fi; }
  mk valid   '| coverage | legacy at 41% | @jdoe | 2099-01-01 | 2099-03-01 | ratchet to 80 | @sec |'
  expect valid 0 "valid waiver -> OK"
  mk expired '| coverage | x | @jdoe | 2020-01-01 | 2020-02-01 | y | @sec |'
  expect expired 1 "expired waiver -> FAIL"
  mk over90  '| coverage | x | @jdoe | 2099-01-01 | 2099-04-02 | y | @sec |'
  expect over90 1 "91-day lifetime (DST boundary) -> FAIL"
  mk exact90 '| coverage | x | @jdoe | 2099-01-01 | 2099-04-01 | y | @sec |'
  expect exact90 0 "exactly 90-day lifetime -> OK"
  mk negspan '| coverage | x | @jdoe | 2099-12-31 | 2099-01-01 | y | @sec |'
  expect negspan 1 "Expires before Opened -> FAIL"
  mk missing '| coverage | x | | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect missing 1 "missing field (owner) -> FAIL"
  # --- adversarial: every spelling of a non-negotiable gate must FAIL (default-deny) ---
  mk nn1 '| secret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect nn1 1 "secret-scan -> FAIL"
  mk nn2 '| SECRET-SCAN | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect nn2 1 "SECRET-SCAN (case) -> FAIL"
  mk nn3 '| **secret-scan** | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect nn3 1 "**secret-scan** (markdown) -> FAIL"
  mk nn4 '| secret_scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect nn4 1 "secret_scan (separator swap) -> FAIL"
  mk nn5 '| branch-protection | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect nn5 1 "branch-protection -> FAIL"
  mk nn6 "| $(printf '\xd1\x95')ecret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |"
  expect nn6 1 "homoglyph secret-scan (non-ASCII) -> FAIL"
  mk unknown '| made-up-gate | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect unknown 1 "unknown gate (not waivable) -> FAIL"
  # --- parser smuggling: a row with Gate+Reason words, and a row missing the leading pipe ---
  mk smuggle '| coverage | mentions Gate and Reason words | @jdoe | 2020-01-01 | 2020-02-01 | y | @sec |'
  expect smuggle 1 "row containing Gate+Reason text still validated (expired) -> FAIL"
  mk nopipe 'secret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect nopipe 1 "row missing leading pipe -> FAIL (not silently dropped)"
  mk comment '| coverage<!--a-->secret-scan<!--b--> | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect comment 1 "html-comment-embedded gate -> FAIL (not normalized into allow-list)"
  # no separator row: header present, data rows must NOT be silently dropped
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n| secret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |\n' > "$d/nosep"
  expect nosep 1 "no separator row -> data flagged malformed -> FAIL"
  # data row ABOVE the separator must not be ignored
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n| secret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |\n|--|--|--|--|--|--|--|\n' > "$d/databefore"
  expect databefore 1 "data row above separator -> FAIL (not skipped)"
  # dash-leading gate must NOT be mistaken for a separator row and dropped
  mk dashgate '| -secret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect dashgate 1 "dash-leading gate (-secret-scan) -> FAIL (not eaten as separator)"
  # Exploit C: a malicious dash-leading row hidden NEXT TO a valid row must still FAIL
  mk dashhide '| coverage | ok | @jdoe | 2099-01-01 | 2099-03-01 | ratchet | @sec |
| -secret-scan | hidden | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |'
  expect dashhide 1 "hidden dash-leading secret-scan beside a valid row -> FAIL"
  # GFM alignment-colon separator must be accepted (and a hidden secret-scan behind it still FAIL)
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|:--|:--:|--:|--|--|--|--|\n| coverage | ok | @jdoe | 2099-01-01 | 2099-03-01 | ratchet | @sec |\n' > "$d/gfmsep"
  expect gfmsep 0 "GFM colon-alignment separator + valid row -> OK"
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|:--|:--:|--:|--|--|--|--|\n| secret-scan | x | @jdoe | 2099-01-01 | 2099-02-01 | y | @sec |\n' > "$d/gfmnn"
  expect gfmnn 1 "GFM colon separator + secret-scan row -> FAIL"
  # no register -> N/A pass
  if main "$d/does-not-exist.md" >/dev/null 2>&1; then echo "selftest PASS: no register -> N/A pass"; else echo "selftest FAIL: no register should N/A-pass"; st=1; fi
  [ "$st" = "0" ] && echo "waivers-valid --selftest: OK"
  return "$st"
}

main() {
  reg="${1:-./WAIVER-REGISTER.md}"
  if [ ! -f "$reg" ]; then
    echo "waivers-valid: no $reg — N/A (greenfield / no governed exceptions)."; return 0
  fi
  validate_register "$reg"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) main "$@"; exit $? ;;
esac
