#!/bin/sh
# branch-protection-apply.sh — read the declared required-check contexts (REQUIRED-CHECKS.md) and
# apply them to this repo's live GitHub branch protection (B4, ruling 4). Human-run; never wired
# into CI (it needs admin-authenticated `gh`, the same credential seam branch-protection.sh's live
# leg needs — see that file's header).
#
# DEFAULT IS SHOW-ONLY: with no flag this prints the diff (to-add / already-bound / live-extra) and
# changes nothing.
#   --apply    POSTs only the MISSING contexts via the ADDITIVE
#              repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks/contexts
#              endpoint, after a y/N confirmation. Every other protection setting is untouched.
#   --replace  performs the full-object PUT the kit's own templates used to teach — this REPLACES
#              EVERY protection setting (review requirements, enforce_admins, restrictions), not
#              just contexts, so it sits behind a SECOND, differently-worded, TTY-GATED confirmation
#              that must be typed at an actual interactive terminal (see below). Prefer --apply.
# NEVER emits `--admin` and is not a bypass surface. Scoped precisely to --apply: it can only ADD a
# required check via the additive endpoint, never remove branch protection or merge anything (the
# promotion-contract deny stands). --replace is NOT additive — it is a weakening path that RESETS
# every non-context protection setting to the solo-owner profile: enforce_admins:false ·
# required_approving_review_count:1 · require_code_owner_reviews:false (named again at the
# confirmation prompt and in profiles/<stack>/BRANCH-PROTECTION.md).
#
# CEILING: it binds contexts; it cannot prevent later unbinding (an admin can still remove one by
# hand, or edit the declaration to match a weakened forge state — see branch-protection.sh's own
# ceiling paragraph). Real prevention is org rulesets / Terraform's github_branch_protection
# resource, not this script.
#   usage: sh scripts/branch-protection-apply.sh [--repo=OWNER/REPO] [--branch=NAME]
#            [--declaration=FILE] [--apply | --replace]
#          sh scripts/branch-protection-apply.sh --selftest
#          sh scripts/branch-protection-apply.sh --declaration=FILE --print-parsed   (debug: prints
#            the parsed active-context list, one per line, no gh calls — used by
#            branch-protection.sh's parser-drift-lock selftest cell; not part of the operator flow)
# Exit: 0 = shown/applied/N-A · 1 = FAIL (malformed declaration, refused/failed mutation) ·
#   2 = UNVERIFIED (no gh, no repo context, live fetch failed — NOT a pass) · usage errors also exit 2.
# What it changes: read-only unless --apply or --replace is passed AND its confirmation is answered
#   affirmatively; --apply POSTs only the declared-but-unbound contexts (additive); --replace PUTs
#   the whole protection object (the clobber path). Never touches anything outside branch protection.
# Guardrails: default is show-only (no mutation without an explicit flag AND a confirmation); the
#   additive endpoint is used for --apply so unrelated settings are never touched; --replace requires
#   typing the literal word REPLACE at an actual /dev/tty (a plain pipe/redirect, e.g. `yes REPLACE |`,
#   can never drive it; a pty-allocating driver (expect) still can — tty-gating raises the bar, it is
#   not an authorization control); never emits --admin; --selftest stubs `gh` via PATH (mktemp
#   fixture, trap-cleaned) and makes zero live calls.
# CONTEXT-NAME CHARSET (B4 fix round 1, SEC C-1/H-2/L-2..L-4): every parsed declared context name
# must match ^[A-Za-z0-9][A-Za-z0-9._/-]*$ with length<=100 — identical to (and independently
# selftest-locked against drifting from) conformance/branch-protection.sh's own copy. This charset
# can never carry a JSON metachar, a shell case/glob metachar, or whitespace: the --replace payload
# builder (build_replace_payload, below) is structurally injection-proof as a SECOND, independent
# layer on top of this validation, never a substitute for it.
# GH ENV CONTAINMENT (SEC M-3): every `gh` call below strips GH_HOST, GH_REPO, GH_ENTERPRISE_TOKEN,
# GH_CONFIG_DIR from the subshell before invoking `gh` — a hostile value in any of those could
# redirect the API host, retarget the mutation at a different repo, or swap the config/creds gh
# reads. GH_TOKEN is left untouched and honored (the operator's real credential).
set -eu
set -f   # noglob — every `for x in $LIST` expansion in this file is data, never a filesystem glob.

REPO_OVERRIDE=""
BRANCH=main
DECLARATION="REQUIRED-CHECKS.md"
MODE=dry-run
PRINT_PARSED=0

usage() {
  echo "usage: branch-protection-apply.sh [--repo=OWNER/REPO] [--branch=NAME] [--declaration=FILE] [--apply | --replace | --print-parsed] | --selftest" >&2
}

for a in "$@"; do
  case "$a" in
    --apply) MODE=apply ;;
    --replace) MODE=replace ;;
    --repo=*) REPO_OVERRIDE=${a#--repo=} ;;
    --branch=*) BRANCH=${a#--branch=} ;;
    --declaration=*) DECLARATION=${a#--declaration=} ;;
    --print-parsed) PRINT_PARSED=1 ;;  # read-only debug aid; see the header. No gh calls.
    --selftest) ;;  # dispatched below
    *) usage; exit 2 ;;
  esac
done

# valid_context_name <name> -> 0 if it matches ^[A-Za-z0-9][A-Za-z0-9._/-]*$ and length<=100, else 1.
# Duplicated verbatim from conformance/branch-protection.sh (D4: this script is self-contained, no
# dependency on that file) — branch-protection.sh's own selftest runs a parser-drift-lock cell
# proving the two copies never disagree on a shared fixture battery.
valid_context_name() {
  _vcn=$1
  [ -n "$_vcn" ] || return 1
  [ "${#_vcn}" -le 100 ] || return 1
  case "$_vcn" in
    [A-Za-z0-9]*) : ;;
    *) return 1 ;;
  esac
  case "$_vcn" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

AD_MAX_LINES=100

# ad_read_declaration <file> — self-contained (D4: no dependency on conformance/branch-protection.sh,
# so this script's own conformance stands alone). Same format + same charset/cap/first-fence-only
# rules as that file's read_declaration() (B4 fix round 1: SEC C-1/H-2/L-2..L-4, REV M1).
# Sets: AD_LIST (space-joined VALID, non-duplicate active contexts) AD_PLACEHOLDER (0/count)
# AD_DUP (0/count) AD_DUP_NAME AD_INVALID (0/count) AD_INVALID_NAME AD_TOOMANY (0/1).
ad_read_declaration() {
  _adf=$1
  AD_LIST=""; AD_PLACEHOLDER=0; AD_DUP=0; AD_DUP_NAME=""
  AD_INVALID=0; AD_INVALID_NAME=""; AD_TOOMANY=0
  _ad_in=0; _ad_done=0; _ad_n=0
  while IFS= read -r _adl || [ -n "$_adl" ]; do
    case "$_adl" in
      '```'*)
        [ "$_ad_done" = 1 ] && continue   # a second fence-open after the first block's close is IGNORED
        if [ "$_ad_in" = 0 ]; then _ad_in=1; else _ad_in=0; _ad_done=1; fi
        continue ;;
    esac
    [ "$_ad_in" = 1 ] || continue
    _adt=$(printf '%s' "$_adl" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$_adt" ] && continue
    case "$_adt" in
      '#'*) continue ;;
    esac
    _ad_n=$((_ad_n + 1))
    if [ "$_ad_n" -gt "$AD_MAX_LINES" ]; then AD_TOOMANY=1; continue; fi
    case "$_adt" in
      *'<'*'>'*) AD_PLACEHOLDER=$((AD_PLACEHOLDER + 1)); continue ;;
    esac
    if ! valid_context_name "$_adt"; then
      AD_INVALID=$((AD_INVALID + 1))
      # R-3: sanitize BEFORE capture (mirrors conformance/branch-protection.sh's RD_INVALID_NAME) —
      # a raw control byte (e.g. ESC) in an offending line was measured erasing the FAIL prefix on
      # ANSI terminals; strip control bytes and cap length so every downstream diagnostic inherits
      # the sanitized form.
      [ -n "$AD_INVALID_NAME" ] || AD_INVALID_NAME=$(printf '%s' "$_adt" | tr -d '[:cntrl:]' | cut -c1-80)
      continue
    fi
    if [ -n "$AD_LIST" ] && printf '%s\n' $AD_LIST | grep -qxF -e "$_adt"; then
      AD_DUP=$((AD_DUP + 1)); [ -n "$AD_DUP_NAME" ] || AD_DUP_NAME=$_adt
    else
      AD_LIST="$AD_LIST $_adt"
    fi
  done < "$_adf"
  AD_LIST=$(printf '%s' "$AD_LIST" | sed 's/^ *//')
}

# print_parsed — debug-only (--print-parsed): print the parsed ACTIVE context list, one per line, and
# exit 0. No gh, no network, no mutation-guard checks (a malformed file just prints whatever parsed
# as active, or nothing) — used solely to cross-check against conformance/branch-protection.sh's own
# parser for drift (item 9's selftest cell). Not part of the normal operator flow.
print_parsed() {
  if [ ! -f "$DECLARATION" ]; then exit 0; fi
  ad_read_declaration "$DECLARATION"
  for _pp_c in $AD_LIST; do printf '%s\n' "$_pp_c"; done
  exit 0
}

# extract_contexts <body> — one live required-status-check context per line (rc always 0; empty
# stdout = none/unparsable). jq optional fast path; POSIX sed/tr is the load-bearing path (Δ7).
extract_contexts() {
  if command -v jq >/dev/null 2>&1; then
    if _ecj=$(printf '%s' "$1" | jq -r '.required_status_checks.contexts[]?' 2>/dev/null); then
      if [ -n "$_ecj" ]; then printf '%s\n' "$_ecj"; return 0; fi
    fi
  fi
  printf '%s' "$1" | tr -d '\n' \
    | sed -n 's/.*"contexts"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"\{0,1\}//; s/"\{0,1\}[[:space:]]*$//' \
    | grep -v '^[[:space:]]*$' || true
  return 0
}

# json_list <space-list> -> "a","b","c" on stdout (empty input -> empty output). Callers MUST have
# already run every entry through valid_context_name (build_replace_payload re-validates anyway).
json_list() {
  _jlo=""
  for _jlc in $1; do
    if [ -z "$_jlo" ]; then _jlo="\"$_jlc\""; else _jlo="$_jlo,\"$_jlc\""; fi
  done
  printf '%s' "$_jlo"
}

# build_replace_payload <space-list of contexts> -> the --replace PUT body on stdout; returns 1 and
# prints NOTHING to stdout if any entry fails re-validation. Defense in depth (SEC C-1): every entry
# has ALREADY passed valid_context_name() in ad_read_declaration(), but this function re-validates
# independently before ever touching a string, so a caller mistake can never reach the JSON. Prefers
# jq -n (a real JSON encoder — no manual escaping trusted at all); the POSIX fallback is used only
# when jq is absent, and even there the re-validated charset ([A-Za-z0-9._/-], no
# quote/brace/colon/comma/backslash reachable) makes naive interpolation structurally safe — a
# second, independent layer, never a substitute for the upstream validation.
build_replace_payload() {
  _brp_list=$1
  for _brp_c in $_brp_list; do
    valid_context_name "$_brp_c" || { printf '%s\n' "FAIL: refusing to build the --replace payload — '$_brp_c' failed re-validation" >&2; return 1; }
  done
  if command -v jq >/dev/null 2>&1; then
    _brp_json=$(printf '%s\n' $_brp_list | grep -v '^$' | jq -R . | jq -s -c \
      '{required_status_checks:{strict:true,contexts:.},enforce_admins:false,required_pull_request_reviews:{required_approving_review_count:1,dismiss_stale_reviews:true,require_code_owner_reviews:false},restrictions:null}' 2>/dev/null) || _brp_json=""
    if [ -n "$_brp_json" ]; then printf '%s' "$_brp_json"; return 0; fi
  fi
  printf '{"required_status_checks":{"strict":true,"contexts":[%s]},"enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":false},"restrictions":null}' "$(json_list "$_brp_list")"
}

confirm() {  # <prompt> -> 0 on y/yes (case-insensitive), 1 otherwise. Reads stdin (pipeable).
  printf '%s ' "$1" >&2
  IFS= read -r _cfans || _cfans=""
  case "$_cfans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# confirm_replace — the SECOND, differently-worded, TTY-GATED confirmation (SEC M-1/M-2). Reads
# EXCLUSIVELY from /dev/tty, never stdin: piping input (`yes REPLACE | ...`) can no longer drive
# --replace at all — measured previously doing exactly that. Displays the concrete solo-default
# payload values (SEC M-2/REV H2) before checking for a tty, so the disclosure is seen even on the
# abort path.
confirm_replace() {
  printf '%s\n' "WARNING: --replace performs a full PUT that OVERWRITES every branch-protection setting on" >&2
  printf '%s\n' "  $BRANCH (review requirements, enforce_admins, restrictions) — not just status-check" >&2
  printf '%s\n' "  contexts. The reset values are the solo-owner defaults: enforce_admins:false ·" >&2
  printf '%s\n' "  required_approving_review_count:1 · require_code_owner_reviews:false." >&2
  printf '%s\n' "  Prefer --apply (additive) unless you mean this." >&2
  if ! exec 3<>/dev/tty 2>/dev/null; then
    printf '%s\n' "ABORT: --replace requires an interactive terminal (/dev/tty) for its confirmation — refusing to proceed non-interactively (piping input, e.g. 'yes REPLACE |', can never drive this by design)." >&2
    return 1
  fi
  printf '%s' "Type REPLACE (all caps) to proceed, anything else aborts: " >&3
  IFS= read -r _cfrans <&3 || _cfrans=""
  exec 3<&- 2>/dev/null || true
  [ "$_cfrans" = "REPLACE" ]
}

main() {
  if [ ! -f "$DECLARATION" ]; then
    printf '%s\n' "FAIL: $DECLARATION not found — nothing declared to apply (see templates/REQUIRED-CHECKS-TEMPLATE.md)"
    exit 1
  fi
  ad_read_declaration "$DECLARATION"
  if [ "$AD_TOOMANY" != 0 ]; then
    printf '%s\n' "FAIL: $DECLARATION declares more than $AD_MAX_LINES required-check context line(s) (cap exceeded — DoS bound)"
    exit 1
  fi
  if [ "$AD_INVALID" != 0 ]; then
    printf '%s\n' "FAIL: $DECLARATION declares an invalid required-check context name: $AD_INVALID_NAME (must match ^[A-Za-z0-9][A-Za-z0-9._/-]*\$, length<=100 — GitHub context names containing spaces are NOT declarable in v1; rename the CI job/step to a hyphenated name and re-declare)"
    exit 1
  fi
  if [ "$AD_DUP" != 0 ] || { [ "$AD_PLACEHOLDER" != 0 ] && [ -n "$AD_LIST" ]; }; then
    printf '%s\n' "FAIL: $DECLARATION is malformed (duplicate or placeholder-mixed) — run 'sh conformance/branch-protection.sh --declared-only' for details"
    exit 1
  fi
  if [ "$AD_PLACEHOLDER" != 0 ] && [ -z "$AD_LIST" ]; then
    printf '%s\n' "N/A: $DECLARATION is the pristine stamped template — nothing to apply yet"
    exit 0
  fi
  if [ -z "$AD_LIST" ]; then
    printf '%s\n' "FAIL: $DECLARATION declares zero active required-check contexts"
    exit 1
  fi

  command -v gh >/dev/null 2>&1 || { printf '%s\n' "UNVERIFIED: gh not installed — cannot read or apply live branch protection"; exit 2; }
  REPO="$REPO_OVERRIDE"
  if [ -z "$REPO" ]; then REPO=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true); fi
  [ -n "$REPO" ] || { printf '%s\n' "UNVERIFIED: no GitHub repo context (pass --repo=OWNER/REPO or run inside a GitHub remote)"; exit 2; }

  if BODY=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null); then :; else
    printf '%s\n' "UNVERIFIED: could not fetch live branch protection for $REPO:$BRANCH (no admin rights, no protection configured yet, or a transient error) — three-state, not a pass; if no protection exists on the branch yet, --replace establishes it (see profiles/<stack>/BRANCH-PROTECTION.md)"
    exit 2
  fi
  LIVE=$(extract_contexts "$BODY")

  TOADD=""; BOUND=""
  for _c in $AD_LIST; do
    if printf '%s\n' "$LIVE" | grep -qxF -e "$_c"; then BOUND="$BOUND $_c"; else TOADD="$TOADD $_c"; fi
  done
  EXTRA=""
  for _c in $LIVE; do
    if [ -n "$AD_LIST" ] && printf '%s\n' $AD_LIST | grep -qxF -e "$_c"; then
      :
    else
      EXTRA="$EXTRA $_c"
    fi
  done

  if [ "$MODE" = replace ]; then
    _extra_note="(WILL BE REMOVED by --replace — every setting outside the declaration is reset)"
  else
    _extra_note="(informational only — never applied)"
  fi
  printf '%s\n' "Declaration: $DECLARATION ($REPO:$BRANCH)"
  printf '%s\n' "  to-add:        ${TOADD:-(none)}"
  printf '%s\n' "  already-bound: ${BOUND:-(none)}"
  printf '%s\n' "  live-extra:    ${EXTRA:-(none)} $_extra_note"

  case "$MODE" in
    dry-run)
      if [ -n "$TOADD" ]; then
        printf '%s\n' "Dry-run (default, show-only): re-run with --apply to ADDITIVELY bind:$TOADD"
      else
        printf '%s\n' "Dry-run: nothing to add — every declared context is already bound live."
      fi
      exit 0 ;;
    apply)
      if [ -z "$TOADD" ]; then printf '%s\n' "Nothing to add — every declared context is already bound live."; exit 0; fi
      printf '%s\n' "About to ADDITIVELY POST these missing context(s) to $REPO:$BRANCH:$TOADD"
      confirm "Proceed? [y/N]" || { printf '%s\n' "Aborted — no change made."; exit 1; }
      _pargs=""
      for _c in $TOADD; do _pargs="$_pargs -f contexts[]=$_c"; done
      # shellcheck disable=SC2086  # word-splitting is deliberate: one -f per declared context
      if (unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api -X POST "repos/$REPO/branches/$BRANCH/protection/required_status_checks/contexts" $_pargs) >/dev/null 2>&1; then
        printf '%s\n' "OK: added$TOADD to $REPO:$BRANCH (additive — every other protection setting untouched)"
        exit 0
      fi
      printf '%s\n' "FAIL: the additive POST failed"
      exit 1 ;;
    replace)
      confirm_replace || { printf '%s\n' "Aborted — no change made."; exit 1; }
      PAYLOAD=$(build_replace_payload "$AD_LIST") || exit 1
      if printf '%s' "$PAYLOAD" | (unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input -) >/dev/null 2>&1; then
        printf '%s\n' "OK: replaced $REPO:$BRANCH protection wholesale with the declared contexts (every OTHER setting was reset per the --replace payload above)"
        exit 0
      fi
      printf '%s\n' "FAIL: the full PUT failed"
      exit 1 ;;
  esac
}

selftest() {
  st=0
  _d=""; _ghdir=""; _extradir=""; _ghenvdir=""
  trap 'rm -rf "$_d" "$_ghdir" "$_extradir" "$_ghenvdir" 2>/dev/null || true' EXIT
  _d=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the declaration fixture"; exit 1; }
  printf '```\nci\ncontrol-plane-ratification\n```\n' > "$_d/decl.md"

  # 1. diff computed right — pure function test, no gh at all.
  ad_read_declaration "$_d/decl.md"
  _live=$(extract_contexts '{"required_status_checks":{"contexts":["ci"]}}')
  _toadd=""; _bound=""
  for _c in $AD_LIST; do
    if printf '%s\n' "$_live" | grep -qxF -e "$_c"; then _bound="$_bound $_c"; else _toadd="$_toadd $_c"; fi
  done
  if [ "$_toadd" = " control-plane-ratification" ] && [ "$_bound" = " ci" ]; then
    echo "selftest PASS: diff computed right (to-add + already-bound split correctly)"
  else
    echo "selftest FAIL: diff computed wrong (to-add=[$_toadd] bound=[$_bound])"; st=1
  fi

  _ghdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the gh stub"; exit 1; }
  _log="$_ghdir/log"
  : > "$_log"
  cat > "$_ghdir/gh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$_log"
case "\$*" in
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *) printf '%s' '{"required_pull_request_reviews":{},"required_status_checks":{"contexts":["ci"]}}' ;;
esac
STUB
  chmod +x "$_ghdir/gh"

  # 2. bare (dry-run) invocation must never mutate.
  : > "$_log"
  ( PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" ) >/dev/null 2>&1 || true
  if grep -q -- '-X POST\|-X PUT' "$_log"; then
    echo "selftest FAIL: bare (dry-run) invocation mutated (POST/PUT seen in the gh log)"; st=1
  else
    echo "selftest PASS: no mutation without --apply (dry-run only reads)"
  fi

  # 3. --apply confirmed with 'y' -> the additive POST endpoint is used, never PUT.
  : > "$_log"
  _out=$(printf 'y\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --apply; } 2>&1) || true
  if grep -q -- 'required_status_checks/contexts' "$_log" && grep -q -- '-X POST' "$_log" && ! grep -q -- '-X PUT' "$_log"; then
    echo "selftest PASS: --apply uses the additive endpoint (POST .../contexts), never PUT"
  else
    echo "selftest FAIL: --apply did not use the expected additive endpoint (log: $(cat "$_log" 2>/dev/null))"; st=1
  fi
  printf '%s\n' "$_out" | grep -qF "control-plane-ratification" || { echo "selftest FAIL: --apply output did not name the added context"; st=1; }

  # 4. --apply declined ('n') -> no POST/PUT at all.
  : > "$_log"
  printf 'n\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --apply; } >/dev/null 2>&1 || true
  if grep -q -- '-X POST\|-X PUT' "$_log"; then
    echo "selftest FAIL: declining the --apply confirmation still mutated"; st=1
  else
    echo "selftest PASS: declining the --apply confirmation makes no change"
  fi

  # 5/6. --replace is now TTY-GATED (SEC M-1): this harness has NO controlling tty (verified:
  # `exec 3<>/dev/tty` fails ENXIO in this sandbox, matching CI), so --replace must ABORT no matter
  # what is piped at it — proving `yes REPLACE | ...` can never drive the PUT any more, for either a
  # wrong answer OR the exact right word. The complementary POSITIVE path — a real interactive
  # operator typing REPLACE at an actual terminal proceeds — is NOT mechanically provable in a
  # non-interactive harness; it is asserted by inspection (confirm_replace()'s only behavioral change
  # is the SOURCE of the answer, from stdin to /dev/tty; the `[ "$_cfrans" = "REPLACE" ]` gate itself
  # is unchanged) and must be exercised once manually by a maintainer at a real terminal before
  # relying on --replace in production.
  : > "$_log"
  printf 'y\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace; } >/dev/null 2>&1 || true
  if grep -q -- '-X PUT' "$_log"; then
    echo "selftest FAIL: --replace proceeded with no controlling tty present (piped 'y') — must abort"; st=1
  else
    echo "selftest PASS: --replace aborts with no controlling tty (piped 'y' is never read for the confirmation)"
  fi

  : > "$_log"
  printf 'REPLACE\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace; } >/dev/null 2>&1 || true
  if grep -q -- '-X PUT' "$_log"; then
    echo "selftest FAIL: --replace proceeded via piped stdin 'REPLACE' with no tty present — tty-gating, not stdin-content, must be what blocks it"; st=1
  else
    echo "selftest PASS: piping the literal word REPLACE with no tty still aborts (tty-gating is load-bearing, not the word itself)"
  fi

  # 7. never emits --admin, in any mode exercised above (accumulated log — see below).

  # Live-extra relabeling + payload-values display (SEC M-2/REV H2): a stub gh reporting an
  # undeclared live context ("legacy-check"). Dry-run/--apply keep it "(informational only — never
  # applied)"; --replace relabels it "WILL BE REMOVED by --replace" — the diff print happens BEFORE
  # confirm_replace()'s tty-abort, so both are observable even with no tty.
  _extradir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the extra-context gh stub"; st=1; }
  cat > "$_extradir/gh" <<'STUBX'
#!/bin/sh
case "$*" in
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *) printf '%s' '{"required_pull_request_reviews":{},"required_status_checks":{"contexts":["ci","legacy-check"]}}' ;;
esac
STUBX
  chmod +x "$_extradir/gh"

  _out=$( PATH="$_extradir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" 2>&1 ) || true
  if printf '%s\n' "$_out" | grep -qF -- "legacy-check" && printf '%s\n' "$_out" | grep -qF -- "(informational only — never applied)"; then
    echo "selftest PASS: dry-run live-extra label stays informational-only"
  else
    echo "selftest FAIL: dry-run live-extra label wrong (out=[$_out])"; st=1
  fi

  _out=$( PATH="$_extradir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace 2>&1 ) || true
  if printf '%s\n' "$_out" | grep -qF -- "legacy-check" && printf '%s\n' "$_out" | grep -qF -- "WILL BE REMOVED by --replace"; then
    echo "selftest PASS: --replace relabels live-extra as WILL BE REMOVED"
  else
    echo "selftest FAIL: --replace live-extra relabel missing (out=[$_out])"; st=1
  fi
  if printf '%s\n' "$_out" | grep -qF -- "enforce_admins:false" \
     && printf '%s\n' "$_out" | grep -qF -- "required_approving_review_count:1" \
     && printf '%s\n' "$_out" | grep -qF -- "require_code_owner_reviews:false"; then
    echo "selftest PASS: --replace confirmation displays the concrete solo-default payload values"
  else
    echo "selftest FAIL: --replace confirmation missing the payload-values needle (out=[$_out])"; st=1
  fi

  # SEC M-6: cell 7's --admin grep must run over an ACCUMULATED, never-truncated log covering every
  # invocation above — not just whatever the last cell happened to leave in the per-cell log (the
  # measured vacuity: truncating `$_log` before each cell meant this check only ever inspected the
  # residue of cell 6). Re-run the SAME battery once more against a stub that accumulates into
  # $_alllog (append, never truncated) and grep that instead.
  _alllog="$_ghdir/all-invocations.log"
  : > "$_alllog"
  cat > "$_ghdir/gh" <<STUBALL
#!/bin/sh
printf '%s\n' "\$*" >> "$_alllog"
case "\$*" in
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *) printf '%s' '{"required_pull_request_reviews":{},"required_status_checks":{"contexts":["ci"]}}' ;;
esac
STUBALL
  chmod +x "$_ghdir/gh"
  ( PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" ) >/dev/null 2>&1 || true
  printf 'y\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --apply; } >/dev/null 2>&1 || true
  printf 'n\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --apply; } >/dev/null 2>&1 || true
  printf 'y\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace; } >/dev/null 2>&1 || true
  printf 'REPLACE\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace; } >/dev/null 2>&1 || true
  if grep -q -- '--admin' "$_alllog" 2>/dev/null; then
    echo "selftest FAIL: a gh invocation carried --admin (this script must never emit it) — accumulated log: $(cat "$_alllog" 2>/dev/null)"; st=1
  else
    echo "selftest PASS: no invocation ever emits --admin (checked over the FULL accumulated invocation log)"
  fi

  # GH env containment (SEC M-3): GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/GH_CONFIG_DIR must never reach
  # the gh subprocess; GH_TOKEN must still reach it. Proven with a stub gh that dumps its own env.
  _ghenvdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the GH-env fixture"; st=1; }
  _ghenvlog="$_ghenvdir/env.log"
  : > "$_ghenvlog"
  cat > "$_ghenvdir/gh" <<STUBENV
#!/bin/sh
env | grep '^GH_' | sort >> "$_ghenvlog" 2>/dev/null || true
case "\$*" in
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *"repo view"*) echo "me/repo" ;;
  *) printf '%s' '{"required_pull_request_reviews":{},"required_status_checks":{"contexts":["ci","control-plane-ratification"]}}' ;;
esac
STUBENV
  chmod +x "$_ghenvdir/gh"
  GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=evil-ent-token GH_CONFIG_DIR=/evil-config GH_TOKEN=real-op-token \
    PATH="$_ghenvdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" >/dev/null 2>&1 || true
  if grep -q '^GH_HOST=\|^GH_REPO=\|^GH_ENTERPRISE_TOKEN=\|^GH_CONFIG_DIR=' "$_ghenvlog"; then
    echo "selftest FAIL: a stripped GH_* var reached the gh subprocess (log: $(cat "$_ghenvlog" 2>/dev/null))"; st=1
  else
    echo "selftest PASS: GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/GH_CONFIG_DIR never reach the gh subprocess"
  fi
  if grep -q '^GH_TOKEN=real-op-token' "$_ghenvlog"; then
    echo "selftest PASS: GH_TOKEN (the operator's real credential) still reaches the gh subprocess"
  else
    echo "selftest FAIL: GH_TOKEN was stripped too (it must be honored, not contained) (log: $(cat "$_ghenvlog" 2>/dev/null))"; st=1
  fi

  # Charset validation + injection repro (SEC C-1, defense in depth) — a hostile declared "context"
  # carrying JSON metachars must FAIL at PARSE, well before any payload is ever built.
  _bad_d=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the injection fixture"; st=1; }
  printf '```\nci\n"allow_force_pushes":true\n```\n' > "$_bad_d/inject.md"
  ad_read_declaration "$_bad_d/inject.md"
  if [ "$AD_INVALID" != 0 ] && printf '%s' "$AD_INVALID_NAME" | grep -qF -- 'allow_force_pushes'; then
    echo "selftest PASS: a JSON-metachar-carrying declared line is rejected at parse (C-1), never reaches the payload"
  else
    echo "selftest FAIL: the injection line was not rejected at parse (AD_INVALID=$AD_INVALID AD_LIST=[$AD_LIST])"; st=1
  fi
  rm -rf "$_bad_d" 2>/dev/null || true

  # R-3: the invalid-name FAIL line (main()'s AD_INVALID branch) must never carry a raw control/ESC
  # byte (measured erasing the FAIL prefix on ANSI terminals) — mirrors conformance/branch-
  # protection.sh's own R-3 cell so both parsers' diagnostics stay control-byte-safe together.
  _escbad_d=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the ESC-name fixture"; st=1; }
  printf '```\nci\n\033[31mFAKE\033[0m\n```\n' > "$_escbad_d/esc.md"
  _esc_out=$( sh "$0" --declaration="$_escbad_d/esc.md" 2>&1 ) || true
  _esc_clean=$(printf '%s' "$_esc_out" | tr -d '[:cntrl:]')
  if printf '%s' "$_esc_out" | grep -qF -- "invalid required-check context name" && [ "$_esc_out" = "$_esc_clean" ]; then
    echo "selftest PASS: invalid-name FAIL line carries no raw control/ESC bytes (R-3)"
  else
    echo "selftest FAIL: invalid-name FAIL line still carries raw control bytes (R-3) (out=[$_esc_out])"; st=1
  fi
  rm -rf "$_escbad_d" 2>/dev/null || true
  # build_replace_payload() itself refuses to emit anything for an invalid entry (belt, not just braces).
  if _bp_out=$(build_replace_payload 'ci "x":1' 2>/dev/null); then
    echo "selftest FAIL: build_replace_payload accepted an invalid entry (out=[$_bp_out])"; st=1
  else
    echo "selftest PASS: build_replace_payload refuses to build a payload from an invalid entry"
  fi

  # --print-parsed: the debug surface the parser-drift-lock cell relies on — pure parse, no gh calls.
  : > "$_log"
  _pp=$( PATH="$_ghdir:$PATH" sh "$0" --declaration="$_d/decl.md" --print-parsed 2>&1 )
  if [ "$_pp" = "$(printf 'ci\ncontrol-plane-ratification')" ] && ! grep -q . "$_log" 2>/dev/null; then
    echo "selftest PASS: --print-parsed prints the parsed active list and makes no gh call"
  else
    echo "selftest FAIL: --print-parsed wrong output or touched gh (out=[$_pp] log=[$(cat "$_log" 2>/dev/null)])"; st=1
  fi

  [ "$st" = "0" ] && echo "branch-protection-apply --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) if [ "$PRINT_PARSED" = 1 ]; then print_parsed; fi; main ;;
esac
