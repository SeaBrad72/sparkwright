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
#              Default profile = SOLO. It ALSO pins the repository's merge methods to squash-only
#              (a second call, PATCH repos/{owner}/{repo}, under the same confirmation, both
#              profiles).
#   --team     (only with --replace; any other use exits 2) writes the TEAM profile instead of the
#              solo one: enforce_admins:true · required_approving_review_count:1 ·
#              dismiss_stale_reviews:true · require_last_push_approval:true ·
#              require_code_owner_reviews:true. THE TRAP: with enforce_admins:true an admin can no
#              longer merge their own PR — a second person with write access must approve every PR;
#              alone, this locks you out until you --replace back to solo. --team WARNs (never
#              refuses) when the repo has no second collaborator with write access, or a CODEOWNERS
#              login has only a pending invitation; an unreadable collaborator/invitation list is
#              said, not silent.
# NEVER emits `--admin` and is not a bypass surface. Scoped precisely to --apply: it can only ADD a
# required check via the additive endpoint, never remove branch protection or merge anything (the
# promotion-contract deny stands). --replace is NOT additive — it RESETS every non-context
# protection setting to the chosen profile. SOLO (the default; a weakening path):
# enforce_admins:false · required_approving_review_count:1 · dismiss_stale_reviews:true ·
# require_last_push_approval:true · require_code_owner_reviews:false; TEAM (--team) as above. Both are
# named again at the confirmation prompt and in profiles/<stack>/BRANCH-PROTECTION.md. The two review
# flags are not cosmetic defaults: since REVIEW-LANE-WAITING-IS-GREEN (2026-09-05) they carry the
# properties review-lane's deleted attestation leg used to read out of the forge, and
# conformance/branch-protection.sh FAILs without them. The merge-method pin
# (allow_squash_merge:true · allow_merge_commit:false · allow_rebase_merge:false — a fixed literal
# body, no interpolation) NARROWS what the repo allows; re-allow a method in the repo's Settings.
# TWO CALLS, NOT ATOMIC: the protection PUT runs first, then the merge-method PATCH. If the PATCH
# fails after the PUT landed the run exits 1 and says which half landed — it never claims success.
#
# CEILING: it binds contexts; it cannot prevent later unbinding (an admin can still remove one by
# hand, or edit the declaration to match a weakened forge state — see branch-protection.sh's own
# ceiling paragraph). Real prevention is org rulesets / Terraform's github_branch_protection
# resource, not this script.
#   usage: sh scripts/branch-protection-apply.sh [--repo=OWNER/REPO] [--branch=NAME]
#            [--declaration=FILE] [--apply | --replace [--team]]
#          sh scripts/branch-protection-apply.sh --selftest
#          sh scripts/branch-protection-apply.sh --declaration=FILE --print-parsed   (debug: prints
#            the parsed active-context list, one per line, no gh calls — used by
#            branch-protection.sh's parser-drift-lock selftest cell; not part of the operator flow)
# Exit: 0 = shown/applied/N-A · 1 = FAIL (malformed declaration, refused/failed mutation) ·
#   2 = UNVERIFIED (no gh, no repo context, live fetch failed — NOT a pass) · usage errors also exit 2.
# What it changes: read-only unless --apply or --replace is passed AND its confirmation is answered
#   affirmatively; --apply POSTs only the declared-but-unbound contexts (additive); --replace PUTs
#   the whole protection object (the clobber path) and then PATCHes the repo's merge-method settings
#   to squash-only. Never touches anything outside branch protection and those three merge-method flags.
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
TEAM=0

usage() {
  echo "usage: branch-protection-apply.sh [--repo=OWNER/REPO] [--branch=NAME] [--declaration=FILE] [--apply | --replace [--team] | --print-parsed] | --selftest" >&2
}

for a in "$@"; do
  case "$a" in
    --apply) MODE=apply ;;
    --replace) MODE=replace ;;
    --team) TEAM=1 ;;
    --repo=*) REPO_OVERRIDE=${a#--repo=} ;;
    --branch=*) BRANCH=${a#--branch=} ;;
    --declaration=*) DECLARATION=${a#--declaration=} ;;
    --print-parsed) PRINT_PARSED=1 ;;  # read-only debug aid; see the header. No gh calls.
    --selftest) ;;  # dispatched below
    *) usage; exit 2 ;;
  esac
done
if [ "$TEAM" = 1 ] && [ "$MODE" != replace ] && [ "${1:-}" != "--selftest" ]; then
  echo "branch-protection-apply.sh: --team requires --replace (it selects the profile --replace writes; it is meaningless on its own or with --apply)" >&2
  exit 2
fi

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
# K8 — fetch_live_protection <repo> <branch>: the live GET, with THREE outcomes instead of two.
# Until now every non-zero `gh api` collapsed to UNVERIFIED rc 2 — including the forge's 404
# "Branch not protected", which is exactly the state `--replace` exists to leave. The bootstrap
# profiles/<stack>/BRANCH-PROTECTION.md promises was therefore unreachable on a fresh repo.
#   0 = protection exists (body on stdout)
#   4 = the branch is NOT PROTECTED
#   2 = anything else (403, rate limit, network)
# The 4 is matched on the forge's RESPONSE TEXT, never on rc alone: a 403 or a transient must
# never be read as "unprotected" and let a full-object PUT through. If GitHub rewords the message
# this degrades to 2 (UNVERIFIED) — fail-closed by construction, never to a false bootstrap.
fetch_live_protection() {
  _flp_err=$(mktemp) || return 2
  if _flp_body=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api "repos/$1/branches/$2/protection" 2>"$_flp_err"); then
    rm -f "$_flp_err"; printf '%s' "$_flp_body"; return 0
  fi
  _flp_msg=$(cat "$_flp_err" 2>/dev/null) || _flp_msg=""
  rm -f "$_flp_err"
  case "$_flp_body$_flp_msg" in
    *"Branch not protected"*) return 4 ;;
    *) return 2 ;;
  esac
}

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
#
# build_replace_payload <space-list> [solo|team] — ONE builder, parameterised by profile (default solo,
# whose output is byte-identical to the pre-team builder). The only profile-dependent values are the
# two booleans below, taken from internal literals — never from input. Any other profile name returns 1.
build_replace_payload() {
  _brp_list=$1
  case "${2:-solo}" in
    solo) _brp_ea=false; _brp_co=false ;;
    team) _brp_ea=true; _brp_co=true ;;
    *) printf '%s\n' "FAIL: refusing to build the --replace payload — unknown profile '${2:-}'" >&2; return 1 ;;
  esac
  for _brp_c in $_brp_list; do
    valid_context_name "$_brp_c" || { printf '%s\n' "FAIL: refusing to build the --replace payload — '$_brp_c' failed re-validation" >&2; return 1; }
  done
  if command -v jq >/dev/null 2>&1; then
    _brp_json=$(printf '%s\n' $_brp_list | grep -v '^$' | jq -R . | jq -s -c --argjson ea "$_brp_ea" --argjson co "$_brp_co" \
      '{required_status_checks:{strict:true,contexts:.},enforce_admins:$ea,required_pull_request_reviews:{required_approving_review_count:1,dismiss_stale_reviews:true,require_last_push_approval:true,require_code_owner_reviews:$co},restrictions:null}' 2>/dev/null) || _brp_json=""
    if [ -n "$_brp_json" ]; then printf '%s' "$_brp_json"; return 0; fi
  fi
  printf '{"required_status_checks":{"strict":true,"contexts":[%s]},"enforce_admins":%s,"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true,"require_code_owner_reviews":%s},"restrictions":null}' "$(json_list "$_brp_list")" "$_brp_ea" "$_brp_co"
}

# build_merge_payload — the merge-method PATCH body: a FIXED LITERAL, no interpolation of any kind.
build_merge_payload() {
  printf '%s' '{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false}'
}

# MM_JQ — reads the three TOP-LEVEL merge fields with gh's built-in jq (S-1). A text scan of the repo JSON
# took the first occurrence of each key, which a `template_repository` object (listed BEFORE the top-level
# keys, repeating them) would shadow: a false squash-only. jq's `.allow_*` is the top-level field, always.
MM_JQ='[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge]|map(tostring)|join(" ")'

# parse_merge_methods <"true false false"-style output of MM_JQ> -> squash-only | the allowed methods
# (comma-joined, squash,merge,rebase order) | unknown (not exactly three true/false words — null/absent
# fields, an unreadable token, an empty read). Duplicated in conformance/branch-protection.sh (this script
# is self-contained); that file's selftest diffs the two copies.
parse_merge_methods() {
  set -- $1
  [ "$#" = 3 ] || { printf '%s' "unknown"; return 0; }
  _pmm_out=""
  for _pmm_p in "squash:$1" "merge:$2" "rebase:$3"; do
    case "${_pmm_p#*:}" in
      true) _pmm_out="$_pmm_out,${_pmm_p%%:*}" ;;
      false) : ;;
      *) printf '%s' "unknown"; return 0 ;;
    esac
  done
  _pmm_out=${_pmm_out#,}
  case "$_pmm_out" in
    "") printf '%s' "unknown" ;;
    squash) printf '%s' "squash-only" ;;
    *) printf '%s' "$_pmm_out" ;;
  esac
}

# valid_repo <OWNER/REPO> — ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$, and neither half is `.` or `..` (R-4/S-4:
# the value is interpolated into the API path of every call, including the two writes).
valid_repo() {
  case "$1" in */*/*|*/|/*|"") return 1 ;; */*) : ;; *) return 1 ;; esac
  case "$1" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
  case "/$1/" in */./*|*/../*) return 1 ;; esac
  return 0
}

# valid_branch <name> — refuses empty, a leading `-`, `..`, and any of ? # % * [ \ whitespace/control bytes:
# the name is interpolated into the protection path. Duplicated in conformance/branch-protection.sh.
valid_branch() {
  case "$1" in ""|-*|*..*|*[\?#%*\[\\]*|*[[:space:][:cntrl:]]*) return 1 ;; esac
  return 0
}

# gh_quiet <args...> — one `gh` call with the GH env containment (SEC M-3) applied.
gh_quiet() { (unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh "$@"); }

# fetch_merge_methods <repo> -> the parsed merge methods on stdout (unknown on any read failure).
fetch_merge_methods() {
  if _fmm_body=$(gh_quiet api "repos/$1" --jq "$MM_JQ" 2>/dev/null); then parse_merge_methods "$_fmm_body"; else printf '%s' "unknown"; fi
}

# do_replace <repo> <branch> <solo|team> <contexts> — the post-confirmation write path: the protection
# PUT, then the merge-method PATCH. Returns 0 only when BOTH landed; otherwise 1, naming which half did.
do_replace() {
  _dr_repo=$1; _dr_branch=$2; _dr_profile=$3
  _dr_payload=$(build_replace_payload "$4" "$_dr_profile") || return 1
  if ! printf '%s' "$_dr_payload" | gh_quiet api -X PUT "repos/$_dr_repo/branches/$_dr_branch/protection" --input - >/dev/null 2>&1; then
    printf '%s\n' "FAIL: the full PUT did not report success — run show-only (no flag) to read the live state; the merge-method PATCH was not attempted"
    return 1
  fi
  if ! build_merge_payload | gh_quiet api -X PATCH "repos/$_dr_repo" --input - >/dev/null 2>&1; then
    printf '%s\n' "FAIL: PARTIAL — the protection PUT LANDED on $_dr_repo:$_dr_branch ($_dr_profile profile), but the merge-method PATCH FAILED: merge methods are UNCHANGED. Re-run --replace, or set 'Allow squash merging' only in the repo's Settings."
    return 1
  fi
  printf '%s\n' "OK: replaced $_dr_repo:$_dr_branch protection wholesale with the declared contexts and the $_dr_profile profile (every OTHER setting was reset per the --replace payload above), and pinned the merge methods to squash-only"
  return 0
}

# co_logins <dir> — the @login owners named in the tree's CODEOWNERS (one per line, sorted, unique).
# `@org/team` handles are skipped: an invitation can only be pending for an individual account.
co_logins() {
  for _col_f in "$1/.github/CODEOWNERS" "$1/CODEOWNERS" "$1/docs/CODEOWNERS"; do
    [ -f "$_col_f" ] || continue
    sed 's/#.*//' "$_col_f" | tr -s ' \t' '\n\n' | grep '^@[A-Za-z0-9-]*$' | sed 's/^@//'
  done | sort -u
}

# team_preflight <repo> <dir> — --team only. WARNs, never refuses (the owner may be inviting the second
# person next; the WARN is the trap stated before it springs). Unreadable is said, not silent.
team_preflight() {
  if _tpf_c=$(gh_quiet api --paginate "repos/$1/collaborators" --jq '.[] | select(.permissions.push == true or .permissions.admin == true) | .login' 2>/dev/null); then
    _tpf_n=$(printf '%s\n' "$_tpf_c" | grep -c . || true)
    if [ "$_tpf_n" -lt 2 ]; then
      printf '%s\n' "WARN: no second collaborator with write access on $1 ($_tpf_n found) — with enforce_admins:true nobody can merge your PRs until a second person with write access exists."
    fi
  else
    printf '%s\n' "WARN: could not read collaborators on $1 with this token — cannot tell whether a second person with write access exists (the lock-out trap below applies if there is none)."
  fi
  if _tpf_i=$(gh_quiet api --paginate "repos/$1/invitations" --jq '.[].invitee.login' 2>/dev/null); then
    for _tpf_l in $(co_logins "$2"); do
      if printf '%s\n' "$_tpf_i" | grep -qixF -e "$_tpf_l"; then
        printf '%s\n' "WARN: CODEOWNERS names $_tpf_l but that account has only a PENDING invitation to $1 — their review can never satisfy code-owner review until they accept."
      fi
    done
  else
    printf '%s\n' "WARN: could not read invitations on $1 with this token — cannot tell whether a CODEOWNERS login is still only invited."
  fi
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
confirm_replace() {  # [solo|team] [current merge methods]
  _cr_profile=${1:-solo}
  printf '%s\n' "WARNING: --replace performs a full PUT that OVERWRITES every branch-protection setting on" >&2
  printf '%s\n' "  $BRANCH (review requirements, enforce_admins, restrictions) — not just status-check" >&2
  if [ "$_cr_profile" = team ]; then
    printf '%s\n' "  contexts. Profile: TEAM profile. The reset values are: enforce_admins:true ·" >&2
    printf '%s\n' "  required_approving_review_count:1 · dismiss_stale_reviews:true ·" >&2
    printf '%s\n' "  require_last_push_approval:true · require_code_owner_reviews:true." >&2
  else
    printf '%s\n' "  contexts. Profile: SOLO profile. The reset values are the solo-owner defaults: enforce_admins:false ·" >&2
    printf '%s\n' "  required_approving_review_count:1 · dismiss_stale_reviews:true ·" >&2
    printf '%s\n' "  require_last_push_approval:true · require_code_owner_reviews:false." >&2
  fi
  printf '%s\n' "  The review flags are what carry review-lane's retired attestation leg since" >&2
  printf '%s\n' "  REVIEW-LANE-WAITING-IS-GREEN (2026-09-05); conformance/branch-protection.sh FAILs without them." >&2
  if [ "$_cr_profile" = team ]; then
    printf '%s\n' "  THE TRAP: with enforce_admins:true an admin can no longer merge their own PR. A second person" >&2
    printf '%s\n' "  with write access must approve every PR. If you are alone, this locks you out until you --replace back to solo." >&2
  fi
  printf '%s\n' "  It ALSO pins the repo's merge methods (a second call, PATCH repos/${REPO:-OWNER/REPO}): current=${2:-unknown}" >&2
  printf '%s\n' "  -> target=squash-only (allow_squash_merge:true · allow_merge_commit:false · allow_rebase_merge:false)." >&2
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

  if BODY=$(fetch_live_protection "$REPO" "$BRANCH"); then LIVE_RC=0; else LIVE_RC=$?; fi
  if [ "$LIVE_RC" = 4 ]; then
    # K8: ONLY --replace consumes the not-protected outcome. --apply is additive and has nothing to
    # add TO, and the dry-run has nothing to read — both keep UNVERIFIED rc 2, naming the remedy.
    if [ "$MODE" = replace ]; then
      BODY=""
      printf '%s\n' "NOT PROTECTED: $REPO:$BRANCH carries no branch protection yet — --replace will ESTABLISH it from the declaration below. The typed confirmation still applies."
    else
      printf '%s\n' "UNVERIFIED: $REPO:$BRANCH is not protected yet, so there is nothing live to read and the additive path has nothing to add to — three-state, not a pass. Re-run with --replace to ESTABLISH protection from the declaration (see profiles/<stack>/BRANCH-PROTECTION.md)"
      exit 2
    fi
  elif [ "$LIVE_RC" != 0 ]; then
    printf '%s\n' "UNVERIFIED: could not fetch live branch protection for $REPO:$BRANCH (no admin rights, or a transient error) — three-state, not a pass; if no protection exists on the branch yet, --replace establishes it (see profiles/<stack>/BRANCH-PROTECTION.md)"
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
  if [ "$MODE" != apply ]; then
    MM_CURRENT=$(fetch_merge_methods "$REPO")
    printf '%s\n' "  merge-methods: current=$MM_CURRENT target=squash-only (pinned by --replace, both profiles; show-only never changes it)"
  fi

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
      PROFILE=solo; [ "$TEAM" = 1 ] && PROFILE=team
      _dd=$(dirname -- "$DECLARATION"); _top=$(git -C "$_dd" rev-parse --show-toplevel 2>/dev/null) || _top=$_dd
      [ "$PROFILE" = team ] && team_preflight "$REPO" "$_top"
      confirm_replace "$PROFILE" "$MM_CURRENT" || { printf '%s\n' "Aborted — no change made."; exit 1; }
      do_replace "$REPO" "$BRANCH" "$PROFILE" "$AD_LIST" || exit 1
      exit 0 ;;
  esac
}

validate_args() {
  if [ -n "$REPO_OVERRIDE" ] && ! valid_repo "$REPO_OVERRIDE"; then
    echo "branch-protection-apply.sh: invalid --repo (must be OWNER/REPO, characters A-Za-z0-9._- only, no . or .. segment)" >&2; exit 2
  fi
  if ! valid_branch "$BRANCH"; then
    echo "branch-protection-apply.sh: invalid --branch (empty, leading '-', '..', whitespace, or one of ? # % * [ backslash is refused)" >&2; exit 2
  fi
}

selftest() {
  st=0
  _d=""; _ghdir=""; _extradir=""; _ghenvdir=""; _tp=""
  trap 'rm -rf "$_d" "$_ghdir" "$_extradir" "$_ghenvdir" "$_tp" 2>/dev/null || true' EXIT
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

  # 5b/5c/5d (K8). The forge's NOT-PROTECTED 404 used to collapse into UNVERIFIED rc 2 alongside
  # every other failure, so --replace could never bootstrap a fresh repo — the exact thing
  # profiles/<stack>/BRANCH-PROTECTION.md tells the adopter to do at step 4 of inception.
  # POSITIVE: 404 + --replace reaches the bootstrap disclosure AND confirm_replace's warning (the
  # tty gate above still blocks the PUT — this harness has no tty, and the fixture never types
  # REPLACE). NEGATIVES, both load-bearing: a 403 must NOT be read as "unprotected" (or a transient
  # forge error would open a full-object PUT path), and --apply on a 404 must stay UNVERIFIED and
  # name --replace as the remedy.
  _np=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the not-protected gh stub"; exit 1; }
  _nplog="$_np/log"; : > "$_nplog"
  cat > "$_np/gh" <<STUBNP
#!/bin/sh
printf '%s\n' "\$*" >> "$_nplog"
case "\$*" in
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *) printf '%s\n' "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
esac
STUBNP
  chmod +x "$_np/gh"
  _fb=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the forbidden gh stub"; exit 1; }
  _fblog="$_fb/log"; : > "$_fblog"
  cat > "$_fb/gh" <<STUBFB
#!/bin/sh
printf '%s\n' "\$*" >> "$_fblog"
case "\$*" in
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *) printf '%s\n' "gh: HTTP 403: Resource not accessible by integration" >&2; exit 1 ;;
esac
STUBFB
  chmod +x "$_fb/gh"

  : > "$_nplog"
  _npout=$(printf 'y\n' | { PATH="$_np:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace; } 2>&1) || true
  if printf '%s\n' "$_npout" | grep -qF "NOT PROTECTED:" \
     && printf '%s\n' "$_npout" | grep -qF "WARNING: --replace performs a full PUT" \
     && ! grep -q -- '-X PUT' "$_nplog"; then
    echo "selftest PASS: K8 — not-protected + --replace reaches the bootstrap disclosure (and the tty gate still blocks the PUT)"
  else
    echo "selftest FAIL: K8 — not-protected + --replace did not reach the disclosure, or it mutated (out: $_npout)"; st=1
  fi

  : > "$_fblog"
  if _fbout=$(printf 'y\n' | { PATH="$_fb:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace; } 2>&1); then _fbrc=0; else _fbrc=$?; fi
  if [ "$_fbrc" = 2 ] \
     && printf '%s\n' "$_fbout" | grep -qF "UNVERIFIED:" \
     && ! printf '%s\n' "$_fbout" | grep -qF "NOT PROTECTED:" \
     && ! grep -q -- '-X PUT' "$_fblog"; then
    echo "selftest PASS: K8 — a 403 stays UNVERIFIED rc 2; the replace arm is never reached (fail-closed on rc alone)"
  else
    echo "selftest FAIL: K8 — a 403 was not treated as UNVERIFIED (rc=$_fbrc, out: $_fbout)"; st=1
  fi

  : > "$_nplog"
  if _apout=$(printf 'y\n' | { PATH="$_np:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --apply; } 2>&1); then _aprc=0; else _aprc=$?; fi
  if [ "$_aprc" = 2 ] \
     && printf '%s\n' "$_apout" | grep -qF "UNVERIFIED:" \
     && printf '%s\n' "$_apout" | grep -qF -- "--replace" \
     && ! grep -q -- '-X POST' "$_nplog"; then
    echo "selftest PASS: K8 — not-protected + --apply stays UNVERIFIED rc 2 and names --replace as the remedy"
  else
    echo "selftest FAIL: K8 — not-protected + --apply did not stay UNVERIFIED naming --replace (rc=$_aprc, out: $_apout)"; st=1
  fi
  rm -rf "$_np" "$_fb" 2>/dev/null || true

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
     && printf '%s\n' "$_out" | grep -qF -- "dismiss_stale_reviews:true" \
     && printf '%s\n' "$_out" | grep -qF -- "require_last_push_approval:true" \
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
  printf 'REPLACE\n' | { PATH="$_ghdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl.md" --replace --team; } >/dev/null 2>&1 || true
  ( PATH="$_ghdir:$PATH"; do_replace me/repo main team "ci" ) >/dev/null 2>&1 || true
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

  # ── PROTECTION-TEAM-PROFILE (design 2026-10-03 §4). Every cell below drives gh through a PATH stub;
  # none touches the network. do_replace() is the post-confirmation write path and is called
  # IN-PROCESS (the confirmation itself is tty-gated and cannot be driven from a harness).
  _tp=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the team-profile stub"; exit 1; }
  _tplog="$_tp/log"
  cat > "$_tp/gh" <<'STUBTP'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/log"
env | grep '^GH_' | sort >> "$STUB_DIR/env.log" 2>/dev/null || true
case "$*" in
  *"-X PUT"*) cat > "$STUB_DIR/put.body"; exit "${STUB_PUT_RC:-0}" ;;
  *"-X PATCH"*) cat > "$STUB_DIR/patch.body"; exit "${STUB_PATCH_RC:-0}" ;;
  *"-X POST"*) exit 0 ;;
  *"/collaborators"*) [ -z "${STUB_COLLAB_FAIL:-}" ] || exit 1; for l in ${STUB_COLLAB:-}; do echo "$l"; done ;;
  *"/invitations"*) [ -z "${STUB_INVITES_FAIL:-}" ] || exit 1; for l in ${STUB_INVITES:-}; do echo "$l"; done ;;
  *"branches/main/protection"*) printf '%s' '{"required_pull_request_reviews":{},"required_status_checks":{"contexts":["ci"]}}' ;;
  *"--jq"*) printf '%s\n' "${STUB_MM:-true true true}" ;;
  *) printf '%s' '{"full_name":"me/repo"}' ;;
esac
STUBTP
  chmod +x "$_tp/gh"
  _solo_lit='{"required_status_checks":{"strict":true,"contexts":["ci","control-plane-ratification"]},"enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true,"require_code_owner_reviews":false},"restrictions":null}'
  _team_lit='{"required_status_checks":{"strict":true,"contexts":["ci","control-plane-ratification"]},"enforce_admins":true,"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true,"require_code_owner_reviews":true},"restrictions":null}'
  _merge_lit='{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false}'

  # T1. the team payload carries the five team values; T2. the solo payload is byte-identical to the
  # pre-team builder's output. Both with jq (the encoder) and with jq forced to fail (POSIX fallback).
  _p=$(build_replace_payload "ci control-plane-ratification" team 2>/dev/null) || _p=""
  if [ "$_p" = "$_team_lit" ]; then echo "selftest PASS: --team payload carries the five team values (jq path)"; else echo "selftest FAIL: --team payload wrong (got [$_p])"; st=1; fi
  _p=$(jq() { return 1; }; build_replace_payload "ci control-plane-ratification" team 2>/dev/null) || _p=""
  if [ "$_p" = "$_team_lit" ]; then echo "selftest PASS: --team payload carries the five team values (POSIX fallback path)"; else echo "selftest FAIL: --team fallback payload wrong (got [$_p])"; st=1; fi
  _p=$(build_replace_payload "ci control-plane-ratification" solo 2>/dev/null) || _p=""
  _p2=$(build_replace_payload "ci control-plane-ratification" 2>/dev/null) || _p2=""
  if [ "$_p" = "$_solo_lit" ] && [ "$_p2" = "$_solo_lit" ]; then echo "selftest PASS: solo payload is byte-identical to the pre-team payload (explicit and default profile)"; else echo "selftest FAIL: solo payload drifted (got [$_p] / [$_p2])"; st=1; fi
  _p=$(jq() { return 1; }; build_replace_payload "ci control-plane-ratification" 2>/dev/null) || _p=""
  if [ "$_p" = "$_solo_lit" ]; then echo "selftest PASS: solo payload byte-identical on the POSIX fallback path too"; else echo "selftest FAIL: solo fallback payload drifted (got [$_p])"; st=1; fi
  if build_replace_payload "ci" bogus >/dev/null 2>&1; then echo "selftest FAIL: an unknown profile built a payload"; st=1; else echo "selftest PASS: an unknown profile refuses to build a payload"; fi

  # T3. --team is accepted only with --replace.
  _o=$(sh "$0" --team --repo=me/repo --declaration="$_d/decl.md" 2>&1) && _rc=0 || _rc=$?
  if [ "$_rc" = 2 ] && printf '%s\n' "$_o" | grep -qF -- "--team requires --replace"; then echo "selftest PASS: --team without --replace exits 2 naming the rule"; else echo "selftest FAIL: --team alone (rc=$_rc, out=$_o)"; st=1; fi
  _o=$(sh "$0" --team --apply --repo=me/repo --declaration="$_d/decl.md" 2>&1) && _rc=0 || _rc=$?
  if [ "$_rc" = 2 ] && printf '%s\n' "$_o" | grep -qF -- "--team requires --replace"; then echo "selftest PASS: --team with --apply exits 2 naming the rule"; else echo "selftest FAIL: --team --apply (rc=$_rc, out=$_o)"; st=1; fi

  # T4. the merge-method PATCH body is the exact fixed literal.
  _p=$(build_merge_payload 2>/dev/null) || _p=""
  if [ "$_p" = "$_merge_lit" ]; then echo "selftest PASS: the merge-method PATCH payload is the exact squash-only literal"; else echo "selftest FAIL: merge payload wrong (got [$_p])"; st=1; fi

  # T5. show-only prints current vs target merge methods.
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" sh "$0" --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF -- "merge-methods: current=squash,merge,rebase target=squash-only"; then echo "selftest PASS: show-only prints the merge-method diff (current vs target)"; else echo "selftest FAIL: show-only lacks the merge-method diff (out=$_o)"; st=1; fi

  # T6. do_replace: PUT then PATCH on success; the PATCH body is the literal; the PUT body is the profile's.
  : > "$_tplog"; rm -f "$_tp/put.body" "$_tp/patch.body"
  _o=$( ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; export STUB_DIR; do_replace me/repo main team "ci control-plane-ratification" ) 2>&1 ) && _rc=0 || _rc=$?
  if [ "$_rc" = 0 ] && [ "$(cat "$_tp/put.body" 2>/dev/null)" = "$_team_lit" ] && [ "$(cat "$_tp/patch.body" 2>/dev/null)" = "$_merge_lit" ] \
     && grep -n -e '-X PUT' -e '-X PATCH' "$_tplog" | head -n 1 | grep -qF -- '-X PUT' && grep -qF -- "-X PATCH repos/me/repo" "$_tplog"; then
    echo "selftest PASS: do_replace PUTs the team payload then PATCHes the squash-only literal"
  else
    echo "selftest FAIL: do_replace success path (rc=$_rc, out=$_o, log=$(cat "$_tplog" 2>/dev/null))"; st=1
  fi
  # T7. a PATCH failure AFTER a PUT success exits 1, names the half that landed, never claims success.
  : > "$_tplog"
  _o=$( ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; STUB_PATCH_RC=1; export STUB_DIR STUB_PATCH_RC; do_replace me/repo main solo "ci" ) 2>&1 ) && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ] && printf '%s\n' "$_o" | grep -qF "PUT LANDED" && printf '%s\n' "$_o" | grep -qF "PATCH FAILED" && ! printf '%s\n' "$_o" | grep -q '^OK:'; then
    echo "selftest PASS: PATCH failure after PUT success exits 1 naming which half landed (no success claim)"
  else
    echo "selftest FAIL: partial-landing report (rc=$_rc, out=$_o)"; st=1
  fi
  # T7b. a PUT failure never attempts the PATCH.
  : > "$_tplog"
  _o=$( ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; STUB_PUT_RC=1; export STUB_DIR STUB_PUT_RC; do_replace me/repo main solo "ci" ) 2>&1 ) && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ] && ! grep -qF -- "-X PATCH" "$_tplog" && printf '%s\n' "$_o" | grep -qF "did not report success" && ! printf '%s\n' "$_o" | grep -qF "nothing landed"; then echo "selftest PASS: a failed PUT exits 1, never attempts the PATCH, and does not claim nothing landed (S-5)"; else echo "selftest FAIL: PUT-failure path (rc=$_rc, log=$(cat "$_tplog" 2>/dev/null))"; st=1; fi
  # T7c. GH env containment reaches the new calls (PUT and PATCH).
  : > "$_tp/env.log"
  ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=x GH_CONFIG_DIR=/evil GH_TOKEN=real; export STUB_DIR GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR GH_TOKEN; do_replace me/repo main solo "ci" ) >/dev/null 2>&1 || true
  if ! grep -q '^GH_HOST=\|^GH_REPO=\|^GH_ENTERPRISE_TOKEN=\|^GH_CONFIG_DIR=' "$_tp/env.log" && grep -q '^GH_TOKEN=real' "$_tp/env.log"; then
    echo "selftest PASS: GH env containment holds for the PUT and the PATCH (GH_TOKEN still honoured)"
  else
    echo "selftest FAIL: GH env containment on do_replace (log: $(cat "$_tp/env.log" 2>/dev/null))"; st=1
  fi

  # T8. the --team confirmation names the profile, the exact values, and the trap; solo does not carry the trap.
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_COLLAB="a b" sh "$0" --team --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF "TEAM profile" && printf '%s\n' "$_o" | grep -qF "enforce_admins:true" \
     && printf '%s\n' "$_o" | grep -qF "require_code_owner_reviews:true" && printf '%s\n' "$_o" | grep -qF "can no longer merge their own PR" \
     && printf '%s\n' "$_o" | grep -qF "locks you out until you --replace back to solo" && printf '%s\n' "$_o" | grep -qF "allow_merge_commit:false"; then
    echo "selftest PASS: --team confirmation names the profile, the exact values, the trap, and the merge-method pin"
  else
    echo "selftest FAIL: --team confirmation text (out=$_o)"; st=1
  fi
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" sh "$0" --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF "SOLO profile" && ! printf '%s\n' "$_o" | grep -qF "locks you out" && printf '%s\n' "$_o" | grep -qF "allow_merge_commit:false"; then
    echo "selftest PASS: solo --replace names its profile, carries no team trap, and still shows the merge-method pin"
  else
    echo "selftest FAIL: solo --replace confirmation (out=$_o)"; st=1
  fi

  # T9. --team WARNs (never refuses): no second write collaborator; a CODEOWNERS login with only a
  # pending invitation; unreadable collaborators/invitations say so. The WARNs print BEFORE the tty gate.
  mkdir -p "$_d/.github"
  printf '* @SeaBrad72 @reviewer-login @acme/team\n' > "$_d/.github/CODEOWNERS"
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_COLLAB="SeaBrad72" STUB_INVITES="reviewer-login" sh "$0" --team --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF "WARN: no second collaborator with write access" \
     && printf '%s\n' "$_o" | grep -qF "WARN: CODEOWNERS names reviewer-login but that account has only a PENDING invitation" \
     && ! printf '%s\n' "$_o" | grep -qF "WARN: CODEOWNERS names SeaBrad72" && ! printf '%s\n' "$_o" | grep -qF "acme/team"; then
    echo "selftest PASS: --team WARNs on a lone write collaborator and on a pending-invitation CODEOWNER (and only that one)"
  else
    echo "selftest FAIL: --team collaborator/invitation WARNs (out=$_o)"; st=1
  fi
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_COLLAB="SeaBrad72 reviewer-login" STUB_INVITES="" sh "$0" --team --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if ! printf '%s\n' "$_o" | grep -qF "WARN:"; then echo "selftest PASS: --team is silent when a second write collaborator exists and nothing is pending"; else echo "selftest FAIL: spurious WARN (out=$_o)"; st=1; fi
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_COLLAB_FAIL=1 STUB_INVITES_FAIL=1 sh "$0" --team --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF "WARN: could not read collaborators" && printf '%s\n' "$_o" | grep -qF "WARN: could not read invitations"; then
    echo "selftest PASS: unreadable collaborators/invitations are said, not silent"
  else
    echo "selftest FAIL: unreadable collaborators/invitations (out=$_o)"; st=1
  fi
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_COLLAB="SeaBrad72" sh "$0" --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if ! printf '%s\n' "$_o" | grep -qF "WARN:"; then echo "selftest PASS: the collaborator check runs for --team only (solo --replace stays quiet)"; else echo "selftest FAIL: solo --replace carried a team WARN (out=$_o)"; st=1; fi
  # S-1: show-only reads the TOP-LEVEL merge fields (the stub prints what gh --jq would).
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_MM="true true false" sh "$0" --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF "merge-methods: current=squash,merge target=squash-only"; then echo "selftest PASS: show-only reads merge methods through the top-level jq read"; else echo "selftest FAIL: merge-method read (out=$_o)"; st=1; fi
  # R-4/S-4: --repo and --branch that could redirect the API path are refused (rc 2) before any gh call.
  for _bad in 'a/b/c' 'ab' '../x' 'x/..' 'a/b?x' 'a b/c' '/b' 'a/'; do
    : > "$_tplog"
    _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" sh "$0" --repo="$_bad" --declaration="$_d/decl.md" 2>&1) && _rc=0 || _rc=$?
    if [ "$_rc" = 2 ] && printf '%s\n' "$_o" | grep -qF "invalid --repo" && ! grep -q . "$_tplog"; then echo "selftest PASS: --repo='$_bad' refused (rc 2, no gh call)"; else echo "selftest FAIL: --repo='$_bad' (rc=$_rc, out=$_o)"; st=1; fi
  done
  for _bad in 'a..b' 'x?y' 'x#y' '-rf' 'a b' ''; do
    : > "$_tplog"
    _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" sh "$0" --repo=me/repo --branch="$_bad" --declaration="$_d/decl.md" 2>&1) && _rc=0 || _rc=$?
    if [ "$_rc" = 2 ] && printf '%s\n' "$_o" | grep -qF "invalid --branch" && ! grep -q . "$_tplog"; then echo "selftest PASS: --branch='$_bad' refused (rc 2, no gh call)"; else echo "selftest FAIL: --branch='$_bad' (rc=$_rc, out=$_o)"; st=1; fi
  done
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" sh "$0" --repo=me/repo --branch=release/1.x --declaration="$_d/decl.md" 2>&1) && _rc=0 || _rc=$?
  if [ "$_rc" = 0 ]; then echo "selftest PASS: an ordinary branch name (release/1.x) is accepted"; else echo "selftest FAIL: release/1.x refused (rc=$_rc, out=$_o)"; st=1; fi
  # The confirmation prints the real PATCH target, not a placeholder.
  _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" sh "$0" --replace --repo=me/repo --declaration="$_d/decl.md" 2>&1) || true
  if printf '%s\n' "$_o" | grep -qF "PATCH repos/me/repo" && ! printf '%s\n' "$_o" | grep -qF "OWNER/REPO"; then echo "selftest PASS: the confirmation names the real PATCH target"; else echo "selftest FAIL: confirmation target (out=$_o)"; st=1; fi
  # R-7: CODEOWNERS is found from the git top-level, not the declaration's own directory.
  if command -v git >/dev/null 2>&1; then
    _gt=$(mktemp -d) && git init -q "$_gt" 2>/dev/null && mkdir -p "$_gt/sub" "$_gt/.github" \
      && cp "$_d/decl.md" "$_gt/sub/decl.md" && printf '* @reviewer-login\n' > "$_gt/.github/CODEOWNERS"
    _o=$(PATH="$_tp:$PATH" STUB_DIR="$_tp" STUB_COLLAB="a b" STUB_INVITES="reviewer-login" sh "$0" --team --replace --repo=me/repo --declaration="$_gt/sub/decl.md" 2>&1) || true
    if printf '%s\n' "$_o" | grep -qF "WARN: CODEOWNERS names reviewer-login"; then echo "selftest PASS: CODEOWNERS is located from the git top-level"; else echo "selftest FAIL: CODEOWNERS not found from a subdirectory declaration (out=$_o)"; st=1; fi
    rm -rf "$_gt" 2>/dev/null || true
  fi
  rm -rf "$_tp" 2>/dev/null || true

  [ "$st" = "0" ] && echo "branch-protection-apply --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) validate_args; if [ "$PRINT_PARSED" = 1 ]; then print_parsed; fi; main ;;
esac
