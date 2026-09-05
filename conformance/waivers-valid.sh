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
#   usage: sh conformance/waivers-valid.sh [REGISTER.md] | --active <gate> [REGISTER.md] | --selftest
# `--active <gate>` is the READ arm the board-bound gates consult (BOARD-ROW-IDENTIFIER §3.5a):
# rc 0 = a ratified, filled, unexpired waiver for <gate> exists (`<owner><TAB><expires>` on stdout),
# rc 1 = no such waiver, rc 2 = usage. It grades a row through the SAME wv_row_ok the full run uses.
# Portable POSIX sh; dates anchored to noon UTC (DST-safe) via GNU `date -d` or BSD `date -j -f`.
# See docs/adoption/brownfield.md §5.
set -eu

# Default-deny: only these gates may be waived. Everything else (incl. secret-scan /
# branch-protection and any unknown/typo/spoofed name) is rejected.
# `board-governance` (BOARD-ROW-IDENTIFIER §3.5a) is the hosted-tracker gap: the kit's board-bound
# gates read BACKLOG.md only, so on a github/jira/ado/linear/gitlab backend they report NOT
# ENFORCED. This register is the kit's EXISTING governed-exception mechanism, so the gap gets a
# ladder here rather than a second mechanism — with the 90-day maximum and the renew-by-new-row
# rule unchanged, which is the honest cadence for a control that does not exist yet
# (`TRACKER-BACKED-GOVERNANCE` closes it). The non-negotiable pair below is untouched.
WAIVABLE="coverage sbom provenance dependency-vuln a11y container-image board-governance"
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

# wv_row_ok ROW -> 0 valid / 1 invalid (prints findings), for ONE data row of the Active table.
# EXTRACTED from validate_register's loop body unchanged, so the `--active` read arm cannot grade a
# waiver by a second, weaker standard than the one the full run enforces. Validation is not
# re-implemented anywhere: both callers land here.
# Reads `today`/`tnum` from the caller (both set them before the first call) and leaves the parsed
# fields — gate, g, owner, opened, expires, remediation, ratified — set for the caller to read.
wv_row_ok() {
    row="$1"
    case "$row" in
      __MALFORMED__*) echo "FAIL: malformed waiver row (missing leading '|'): ${row#__MALFORMED__}"; return 1 ;;
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
      echo "FAIL: waiver gate '$gate' contains non-ASCII characters (possible homoglyph) — rejected"; return 1
    fi
    g=$(gnorm "$gate")
    if ! is_clean_gate "$g"; then
      echo "FAIL: waiver gate '$gate' is not a clean single token (markup/comment/whitespace/extra tokens) — rejected"; return 1
    fi
    ng_hit=0
    for ng in $NONNEGOTIABLE; do [ "$g" = "$ng" ] && ng_hit=1; done
    if [ "$ng_hit" = "1" ]; then
      echo "FAIL: waiver targets NON-NEGOTIABLE gate '$gate' — never waivable"; return 1
    fi
    case " $WAIVABLE " in
      *" $g "*) : ;;
      *) echo "FAIL: waiver gate '$gate' is not a waivable gate (allow-list: $WAIVABLE)"; return 1 ;;
    esac

    # --- required fields ---
    if [ -z "$owner" ] || [ -z "$opened" ] || [ -z "$expires" ] || [ -z "$remediation" ] || [ -z "$ratified" ]; then
      echo "FAIL: waiver '$label' is missing a required field (owner/opened/expires/remediation/ratified-by)"; return 1
    fi
    # --- dates ---
    if ! is_date "$opened" || ! is_date "$expires"; then
      echo "FAIL: waiver '$label' has a non-YYYY-MM-DD date (opened='$opened' expires='$expires')"; return 1
    fi
    rfail=0
    # OPENED MAY NOT BE IN THE FUTURE (security S-M1). Without this the 90-day maximum is NOMINAL:
    # `Opened 2099-01-01 · Expires 2099-03-01` is a 59-day span that passes every date check and
    # stays unexpired for seventy-odd years — a permanent waiver wearing a time-box. A waiver is a
    # record of a decision that WAS taken; a decision cannot have been taken tomorrow.
    onum=$(printf '%s' "$opened" | tr -d -)
    [ "$onum" -gt "$tnum" ] && { echo "FAIL: waiver '$label' has Opened $opened in the FUTURE (today $today UTC) — a future Opened makes the ${MAX_DAYS}d maximum nominal; date it when it was ratified"; rfail=1; }
    enum=$(printf '%s' "$expires" | tr -d -)
    [ "$enum" -lt "$tnum" ] && { echo "FAIL: waiver '$label' EXPIRED on $expires (today $today UTC) — renew or remove"; rfail=1; }
    oe=$(to_epoch "$opened" || true); ee=$(to_epoch "$expires" || true)
    if [ -n "$oe" ] && [ -n "$ee" ]; then
      span=$(( (ee - oe) / 86400 ))
      if [ "$span" -lt 0 ]; then
        echo "FAIL: waiver '$label' has Expires ($expires) before Opened ($opened)"; rfail=1
      elif [ "$span" -gt "$MAX_DAYS" ]; then
        echo "FAIL: waiver '$label' lifetime ${span}d exceeds ${MAX_DAYS}d max (opened $opened, expires $expires)"; rfail=1
      fi
    else
      echo "FAIL: waiver '$label' has unparseable dates"; rfail=1
    fi
    return "$rfail"
}

# validate_register FILE -> 0 valid / 1 invalid (prints findings). Current-shell fail accumulator.
validate_register() {
  reg=$1; today=$(date -u +%Y-%m-%d); tnum=$(printf '%s' "$today" | tr -d -); vfail=0
  # EVERY RETURN REMOVES $tmp (security NEW-L-1 / reviewer r8). This used to leak one temp file per
  # call, which was ~once per run when the only caller was the standalone check. It is not that any
  # more: `active_waiver` calls this on EVERY non-md run of all three board-bound gates, so a
  # tracker adopter's CI leaked a file per gate per push, and this repo's own history has a
  # 294 GB conformance-tempfile incident behind the rule. Mirrors active_waiver's own aw_tmp
  # cleanup below.
  tmp=$(mktemp 2>/dev/null || printf '/tmp/wv.%s' "$$")
  extract_rows "$reg" > "$tmp"
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "waivers-valid: register present but no active waivers — OK ($reg)"; return 0
  fi
  while IFS= read -r vrow; do
    [ -n "$vrow" ] || continue
    wv_row_ok "$vrow" || vfail=1
  done < "$tmp"
  rm -f "$tmp"
  [ "$vfail" -eq 0 ] && echo "waivers-valid: OK — all active waivers are waivable-gate, owned, in-date, within ${MAX_DAYS}d ($reg). NOTE: attests register hygiene, not that the waived gate still runs in CI."
  return "$vfail"
}

# active_waiver GATE [REGISTER] -> rc 0 iff the register holds a RATIFIED, FILLED, UNEXPIRED row
# for GATE; prints `<owner><TAB><expires>`. rc 1 otherwise (including: no register at all — absence
# is not a waiver). THE ONE CONSUMER SEAM: the three board-bound gates ask this, and nothing else,
# before turning a NOT ENFORCED verdict into green-with-notice.
# It grades a row through wv_row_ok — the SAME checks the full run enforces — plus ONE rule the
# full run does not have: a bracketed [placeholder] in Owner or Ratified-by is refused. That rule
# exists because `incept --backlog jira` STAMPS this row with `[owner]`/`[security-owner]` so the
# adopter meets the gap on day zero; validate_register only tests those cells for non-emptiness, so
# without this the stamp itself would buy the green it is supposed to ask a human for. The narrower
# scope (two cells, not seven) is deliberate: a Reason or Remediation cell may legitimately carry
# brackets (a citation, a `[link]`).
# IT IS REGISTER-SCOPED, NOT ROW-SCOPED (security S-L2). The whole register must validate before
# ANY row in it can be active: a file the full run REJECTS — a malformed row, a smuggled
# `secret-scan` line, a row with no leading pipe — is not a register in good standing, and reading
# one valid row out of a broken file is exactly the partial-trust a default-deny register refuses.
# One malformed row therefore withdraws every waiver in the file until it is fixed, which is the
# fail-closed direction.
# OUTPUT IS TAB-SEPARATED, `<owner><TAB><expires>` (reviewer r4). It used to be `owner · expires`,
# and every caller had to split on a MIDDLE DOT — a multi-byte character that can also appear inside
# an owner cell, so the split was ambiguous on exactly the input it was parsing.
# CEILING, restated rather than softened: this proves a human WROTE a name and a date. It does not
# prove the owner and the ratifier are different people — the register's own ceiling — and a waived
# gate is still NOT ENFORCED, which is why the gates keep printing that phrase.
active_waiver() {
  aw_want=$(gnorm "${1:-}")
  aw_reg="${2:-./WAIVER-REGISTER.md}"
  is_clean_gate "$aw_want" || return 1
  [ -f "$aw_reg" ] || return 1
  # THE WHOLE-REGISTER PRECONDITION (S-L2), before any row is considered.
  validate_register "$aw_reg" >/dev/null 2>&1 || return 1
  today=$(date -u +%Y-%m-%d); tnum=$(printf '%s' "$today" | tr -d -)
  aw_tmp=$(mktemp 2>/dev/null || printf '/tmp/wva.%s' "$$")
  extract_rows "$aw_reg" > "$aw_tmp"
  aw_hit=1
  while IFS= read -r aw_row; do
    [ -n "$aw_row" ] || continue
    wv_row_ok "$aw_row" >/dev/null 2>&1 || continue
    [ "$g" = "$aw_want" ] || continue
    case "$owner$ratified" in *'['*']'*) continue ;; esac
    # STRIP C0/DEL from both values before they leave this function (security S-L1). The register is
    # repo text; these two cells are echoed into a CI log by three gates, where a byte at a
    # line-start is a workflow command. Same rule as loop-state's ls_safe, applied at the source so
    # no caller has to remember it.
    printf '%s\t%s\n' \
      "$(printf '%s' "$owner"   | LC_ALL=C tr -d '\000-\037\177')" \
      "$(printf '%s' "$expires" | LC_ALL=C tr -d '\000-\037\177')"
    aw_hit=0
    break
  done < "$aw_tmp"
  rm -f "$aw_tmp"
  return "$aw_hit"
}

selftest() {
  st=0; d=$(mktemp -d 2>/dev/null || printf '/tmp/wvst.%s' "$$"); mkdir -p "$d"
  # TODAY-RELATIVE DATES, and this is not cosmetic (security S-M1). Every fixture here used to be
  # dated 2099, which is precisely the shape the future-Opened rule now refuses — the suite would
  # have been proving the rule wrong on twenty rows. Anchoring to today also kills the 2099 fixture
  # as a copy-paste source: the next author who greps this file for a valid row finds a real one.
  # GNU then BSD, matching to_epoch's own dialect pair.
  day() { date -u -d "$1 days" +%Y-%m-%d 2>/dev/null || date -u -v"$1"d +%Y-%m-%d; }
  D0=$(day +0); D60=$(day +60); D90=$(day +90); D91=$(day +91)
  DP1=$(day -1); DP2=$(day -2); DP10=$(day -10); DP100=$(day -100)
  mk() { printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n%s\n' "$2" > "$d/$1"; }
  expect() { validate_register "$d/$1" >/dev/null 2>&1 && g=0 || g=$?; if [ "$g" = "$2" ]; then echo "selftest PASS: $3"; else echo "selftest FAIL: $3 (want $2 got $g)"; st=1; fi; }
  mk valid   "| coverage | legacy at 41% | @jdoe | $D0 | $D60 | ratchet to 80 | @sec |"
  expect valid 0 "valid waiver -> OK"
  mk expired "| coverage | x | @jdoe | $DP100 | $DP10 | y | @sec |"
  expect expired 1 "expired waiver -> FAIL"
  mk over90  "| coverage | x | @jdoe | $D0 | $D91 | y | @sec |"
  expect over90 1 "91-day lifetime (DST boundary) -> FAIL"
  mk exact90 "| coverage | x | @jdoe | $D0 | $D90 | y | @sec |"
  expect exact90 0 "exactly 90-day lifetime -> OK"
  mk negspan "| coverage | x | @jdoe | $DP1 | $DP2 | y | @sec |"
  expect negspan 1 "Expires before Opened -> FAIL"
  # S-M1: a FUTURE Opened is refused. `Opened 2099-01-01 · Expires 2099-03-01` is a 59-day span
  # that passes every other date check and stays unexpired for seventy years — the 90-day maximum
  # made nominal. THE LOAD-BEARING NEGATIVE for that rule; delete the rule and this leg reds.
  mk future "| coverage | x | @jdoe | 2099-01-01 | 2099-03-01 | y | @sec |"
  expect future 1 "Opened in the FUTURE -> FAIL (the 90-day cap is not nominal)"
  mk missing "| coverage | x | | $D0 | $D60 | y | @sec |"
  expect missing 1 "missing field (owner) -> FAIL"
  # --- adversarial: every spelling of a non-negotiable gate must FAIL (default-deny) ---
  mk nn1 "| secret-scan | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nn1 1 "secret-scan -> FAIL"
  mk nn2 "| SECRET-SCAN | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nn2 1 "SECRET-SCAN (case) -> FAIL"
  mk nn3 "| **secret-scan** | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nn3 1 "**secret-scan** (markdown) -> FAIL"
  mk nn4 "| secret_scan | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nn4 1 "secret_scan (separator swap) -> FAIL"
  mk nn5 "| branch-protection | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nn5 1 "branch-protection -> FAIL"
  mk nn6 "| $(printf '\xd1\x95')ecret-scan | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nn6 1 "homoglyph secret-scan (non-ASCII) -> FAIL"
  mk unknown "| made-up-gate | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect unknown 1 "unknown gate (not waivable) -> FAIL"
  # --- parser smuggling: a row with Gate+Reason words, and a row missing the leading pipe ---
  mk smuggle "| coverage | mentions Gate and Reason words | @jdoe | $DP100 | $DP10 | y | @sec |"
  expect smuggle 1 "row containing Gate+Reason text still validated (expired) -> FAIL"
  mk nopipe "secret-scan | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect nopipe 1 "row missing leading pipe -> FAIL (not silently dropped)"
  mk comment "| coverage<!--a-->secret-scan<!--b--> | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect comment 1 "html-comment-embedded gate -> FAIL (not normalized into allow-list)"
  # no separator row: header present, data rows must NOT be silently dropped
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n| secret-scan | x | @jdoe | %s | %s | y | @sec |\n' "$D0" "$D60" > "$d/nosep"
  expect nosep 1 "no separator row -> data flagged malformed -> FAIL"
  # data row ABOVE the separator must not be ignored
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n| secret-scan | x | @jdoe | %s | %s | y | @sec |\n|--|--|--|--|--|--|--|\n' "$D0" "$D60" > "$d/databefore"
  expect databefore 1 "data row above separator -> FAIL (not skipped)"
  # dash-leading gate must NOT be mistaken for a separator row and dropped
  mk dashgate "| -secret-scan | x | @jdoe | $D0 | $D60 | y | @sec |"
  expect dashgate 1 "dash-leading gate (-secret-scan) -> FAIL (not eaten as separator)"
  # Exploit C: a malicious dash-leading row hidden NEXT TO a valid row must still FAIL
  mk dashhide "| coverage | ok | @jdoe | $D0 | $D60 | ratchet | @sec |
| -secret-scan | hidden | @jdoe | $D0 | $D60 | y | @sec |"
  expect dashhide 1 "hidden dash-leading secret-scan beside a valid row -> FAIL"
  # GFM alignment-colon separator must be accepted (and a hidden secret-scan behind it still FAIL)
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|:--|:--:|--:|--|--|--|--|\n| coverage | ok | @jdoe | %s | %s | ratchet | @sec |\n' "$D0" "$D60" > "$d/gfmsep"
  expect gfmsep 0 "GFM colon-alignment separator + valid row -> OK"
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|:--|:--:|--:|--|--|--|--|\n| secret-scan | x | @jdoe | %s | %s | y | @sec |\n' "$D0" "$D60" > "$d/gfmnn"
  expect gfmnn 1 "GFM colon separator + secret-scan row -> FAIL"
  # no register -> N/A pass
  if main "$d/does-not-exist.md" >/dev/null 2>&1; then echo "selftest PASS: no register -> N/A pass"; else echo "selftest FAIL: no register should N/A-pass"; st=1; fi

  # --- --active <gate>: THE READ ARM (BOARD-ROW-IDENTIFIER §3.5a) ------------------------------
  # The three board-bound gates ask this arm whether a RATIFIED, DATED, UNEXPIRED waiver renders
  # their NOT ENFORCED verdict green-with-notice. It is the only thing standing between "a human
  # signed for this gap" and a silent green, so every way of NOT having one is a leg.
  expect_active() {  # <file> <gate> <want-rc> <label>
    _ea=$(active_waiver "$2" "$d/$1" 2>&1) && _er=0 || _er=$?
    if [ "$_er" = "$3" ]; then echo "selftest PASS: $4"
    else echo "selftest FAIL: $4 (want rc $3 got $_er, out=<$_ea>)"; st=1; fi
  }
  mk bg_ok "| board-governance | the kit reads BACKLOG.md only | @jdoe | $D0 | $D60 | adopt TRACKER-BACKED-GOVERNANCE | @sec |"
  expect_active bg_ok board-governance 0 "--active: a valid unexpired board-governance waiver -> rc 0"
  # TAB-SEPARATED, two fields (reviewer r4). The old `owner · expires` form made every caller split
  # on a middle dot that can itself appear in an owner cell. Assert the SHAPE, not just the content.
  _ea=$(active_waiver board-governance "$d/bg_ok" 2>&1) || true
  case "$_ea" in
    "@jdoe$(printf '\t')$D60") echo "selftest PASS: --active emits exactly '<owner>TAB<expires>'" ;;
    *) echo "selftest FAIL: --active must print '<owner>TAB<expires>', got <$_ea>"; st=1 ;;
  esac
  # S-L1: C0/DEL in the Owner cell must not reach the caller — three gates echo this into a CI log,
  # where a byte at a line-start is a workflow command. Mutant: drop the tr and this leg reds.
  mk bg_ctl "| board-governance | x | @jd$(printf '\033')oe | $D0 | $D60 | y | @sec |"
  _ea=$(active_waiver board-governance "$d/bg_ctl" 2>&1) || true
  case "$_ea" in
    *"$(printf '\033')"*) echo "selftest FAIL: --active leaked a C0 byte from the Owner cell"; st=1 ;;
    "@jdoe$(printf '\t')$D60") echo "selftest PASS: --active strips C0/DEL from owner before emitting it" ;;
    *) echo "selftest FAIL: --active mangled a control-bearing owner cell, got <$_ea>"; st=1 ;;
  esac
  # THE LOAD-BEARING NEGATIVE for the bridge: incept STAMPS this row with two bracketed
  # placeholders, so an unfilled stamp must not buy a green. `validate_register` does not reject a
  # placeholder (it only tests non-empty) — the --active arm does, and this is that leg.
  mk bg_ph "| board-governance | the kit reads BACKLOG.md only | [owner] | $D0 | $D60 | adopt TRACKER-BACKED-GOVERNANCE | [security-owner] |"
  expect_active bg_ph board-governance 1 "--active: a [placeholder] owner/ratifier -> rc 1 (a stamp is not a ratification)"
  mk bg_exp "| board-governance | x | @jdoe | $DP100 | $DP10 | y | @sec |"
  expect_active bg_exp board-governance 1 "--active: an EXPIRED waiver -> rc 1"
  mk bg_future "| board-governance | x | @jdoe | 2099-01-01 | 2099-03-01 | y | @sec |"
  expect_active bg_future board-governance 1 "--active: a FUTURE-Opened waiver -> rc 1 (S-M1 reaches the read arm too)"
  expect_active valid board-governance 1 "--active: a row for ANOTHER gate (coverage) -> rc 1"
  expect_active bg_ok coverage 1 "--active: asked for coverage, only a board-governance row -> rc 1"
  # S-L2: --active is REGISTER-scoped, not row-scoped. A register the full run REJECTS is not in
  # good standing, and reading one valid row out of a broken file is partial trust a default-deny
  # register refuses. Mutant: drop the validate_register precondition and this leg reds.
  mk bg_broken "| board-governance | the kit reads BACKLOG.md only | @jdoe | $D0 | $D60 | adopt TRACKER-BACKED-GOVERNANCE | @sec |
secret-scan | smuggled | @jdoe | $D0 | $D60 | y | @sec |"
  expect_active bg_broken board-governance 1 "--active: a VALID row inside a register the full run rejects -> rc 1 (register-scoped)"
  if active_waiver board-governance "$d/does-not-exist.md" >/dev/null 2>&1; then
    echo "selftest FAIL: --active on an absent register must be rc 1 (no waiver), never rc 0"; st=1
  else echo "selftest PASS: --active: no register at all -> rc 1 (absence is not a waiver)"; fi
  # r1: this leg used to point at bg_ok, which carries NO secret-scan row — so it passed because the
  # gate was absent, not because it was refused, and deleting the non-negotiable rule left it green.
  # It now asks a register that DOES carry a secret-scan row. (That register also fails the full run,
  # which is the correct compound answer: a smuggled non-negotiable row poisons the whole file.)
  mk bg_ss "| board-governance | ok | @jdoe | $D0 | $D60 | y | @sec |
| secret-scan | x | @jdoe | $D0 | $D60 | y | @sec |"
  if active_waiver secret-scan "$d/bg_ss" >/dev/null 2>&1; then
    echo "selftest FAIL: --active resolved a NON-NEGOTIABLE gate that IS present in the register"; st=1
  else echo "selftest PASS: --active: a PRESENT secret-scan row is still refused (non-vacuous)"; fi
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
  # --active <gate> [REGISTER.md] : the READ arm. 0 = a ratified, filled, unexpired waiver exists
  # (its `<owner><TAB><expires>` on stdout) · 1 = no such waiver · 2 = usage. Callers treat ANY
  # non-zero as "no waiver", so a missing gate argument can never read as a green.
  --active)
    if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
      echo "usage: sh conformance/waivers-valid.sh --active <gate> [REGISTER.md]" >&2; exit 2
    fi
    active_waiver "$2" "${3:-./WAIVER-REGISTER.md}"; exit $? ;;
  *) main "$@"; exit $? ;;
esac
