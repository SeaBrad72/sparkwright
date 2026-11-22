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
#              just contexts, so it sits behind ONE TTY-GATED confirmation (type REPLACE) that must
#              be typed at an actual interactive terminal (see below); --apply has its own y/N.
#              Prefer --apply.
#              Default profile = SOLO. It ALSO pins the repository's merge methods to squash-only
#              (a second call, PATCH repos/{owner}/{repo}, under the same confirmation, both
#              profiles).
#              Without --team it picks between TWO profiles (SWAS-901): SOLO-AGENT (enforce_admins:true · required_approving_review_count:0 ·
#              dismiss_stale_reviews:true · require_last_push_approval:false · require_code_owner_reviews:false) only when GitHub itself
#              says the default branch reads solo (.kit/dials.conf MERGE_RELATIONSHIP=solo, no Governance team line) AND REQUIRED-CHECKS.md lists
#              solo-go-bound AND .github/workflows/solo-go.yml and the go-bound verb are installed there; the check `solo-go-bound`, run from the
#              base, then stands in for the approval one account cannot give. Any other case, a failed read or a --branch that is not the
#              default branch included, writes the SOLO profile below byte for byte. Show-only prints `review-count: live=<n> target=<0|1>`.
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
# GH ENV (SEC M-3, narrowed by SWAS-198 — see DECISIONS.md D-241015-2): the environment is NOT a trust
# boundary here (PATH, HOME and XDG_CONFIG_HOME still steer `gh`, measured). Every `gh` call below strips
# GH_HOST, GH_REPO, GH_ENTERPRISE_TOKEN and GITHUB_ENTERPRISE_TOKEN as stale-state hygiene: a value
# exported for another project must not silently retarget a protection write (--repo= names a repo
# explicitly). GH_TOKEN, GITHUB_TOKEN and GH_CONFIG_DIR select the operator's ACCOUNT and are honored
# (as `gh` and `sparkwright doctor` honor them). The acting identity is printed to stderr first
# (gh_identity_line), so a wrong account is visible before any lookup, listing or prompt.
set -eu
set -f   # noglob — every `for x in $LIST` expansion in this file is data, never a filesystem glob.

# SWAS-945: every gh call below sets its own trust store inside the macOS agent sandbox (scripts/gh-tls.sh; one probe, in main, before the first gh call).
# A missing library means no probe: today's behaviour.
_bpa_ghtls=$(dirname -- "$0")/gh-tls.sh
# shellcheck source=scripts/gh-tls.sh
if [ -f "$_bpa_ghtls" ]; then . "$_bpa_ghtls"; fi

REPO_OVERRIDE=""
BRANCH=main
DECLARATION="REQUIRED-CHECKS.md"
MODE=dry-run
PRINT_PARSED=0
PRINT_PAYLOAD=""
TEAM=0
PICK_WHY=""
PICK_TEAM_WARN=0

usage() {
  echo "usage: branch-protection-apply.sh [--repo=OWNER/REPO] [--branch=NAME] [--declaration=FILE] [--apply | --replace [--team] | --print-parsed | --print-payload=<solo|team|solo-agent>] | --selftest" >&2
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
    --print-payload=*) PRINT_PAYLOAD=${a#--print-payload=} ;;  # read-only debug aid: the --replace body for a profile. No gh calls.
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

# print_payload — debug-only (--print-payload=<solo|team|solo-agent>): print that profile's --replace body for the declared contexts and
# exit. No gh call and no mutation; the selftest compares it with frozen literals (SWAS-901).
print_payload() {
  [ -f "$DECLARATION" ] || exit 1
  ad_read_declaration "$DECLARATION"
  build_replace_payload "$AD_LIST" "$PRINT_PAYLOAD" || exit 1
  printf '\n'
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
  if _flp_body=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh api "repos/$1/branches/$2/protection" 2>"$_flp_err"); then
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
    solo) _brp_ea=false; _brp_co=false; _brp_rc=1; _brp_lp=true ;;
    team) _brp_ea=true; _brp_co=true; _brp_rc=1; _brp_lp=true ;;
    solo-agent) _brp_ea=true; _brp_co=false; _brp_rc=0; _brp_lp=false ;;   # SWAS-901: no approval (solo-go-bound stands in), admins enforced
    *) printf '%s\n' "FAIL: refusing to build the --replace payload — unknown profile '${2:-}'" >&2; return 1 ;;
  esac
  for _brp_c in $_brp_list; do
    valid_context_name "$_brp_c" || { printf '%s\n' "FAIL: refusing to build the --replace payload — '$_brp_c' failed re-validation" >&2; return 1; }
  done
  # SWAS-901 E6 S-3/R2-1/R3-1: in solo-agent EVERY required check is a `checks` entry and `contexts` is ABSENT: the body carries `checks` only, because the server treats `contexts` and `checks` as oneOf alternatives and refuses a body with both (measured at SWAS-915's live L1 on 2026-11-15, SWAS-919), and
  # solo-go-bound is PINNED to the GitHub Actions app (app_id 15368) so no other app's same-named check satisfies it. Built in the shell (values are charset-validated above).
  _brp_rsc="\"contexts\":[$(json_list "$_brp_list")]"
  if [ "${2:-solo}" = solo-agent ]; then
    _brp_chk=""
    for _brp_c in $_brp_list; do
      if [ "$_brp_c" != solo-go-bound ]; then _brp_chk="${_brp_chk:+$_brp_chk,}{\"context\":\"$_brp_c\"}"; fi
    done
    _brp_rsc="\"checks\":[${_brp_chk:+$_brp_chk,}{\"context\":\"solo-go-bound\",\"app_id\":15368}]"   # MUT-BA-CHK
  elif command -v jq >/dev/null 2>&1; then
    _brp_json=$(printf '%s\n' $_brp_list | grep -v '^$' | jq -R . | jq -s -c --argjson ea "$_brp_ea" --argjson co "$_brp_co" --argjson rc "$_brp_rc" --argjson lp "$_brp_lp" \
      '{required_status_checks:{strict:true,contexts:.},enforce_admins:$ea,required_pull_request_reviews:{required_approving_review_count:$rc,dismiss_stale_reviews:true,require_last_push_approval:$lp,require_code_owner_reviews:$co},restrictions:null}' 2>/dev/null) || _brp_json=""
    if [ -n "$_brp_json" ]; then printf '%s' "$_brp_json"; return 0; fi
  fi
  printf '{"required_status_checks":{"strict":true,%s},"enforce_admins":%s,"required_pull_request_reviews":{"required_approving_review_count":%s,"dismiss_stale_reviews":true,"require_last_push_approval":%s,"require_code_owner_reviews":%s},"restrictions":null}' "$_brp_rsc" "$_brp_ea" "$_brp_rc" "$_brp_lp" "$_brp_co"
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

# gh_quiet <args...> — one `gh` call with the stale-state strip (SEC M-3, narrowed) applied.
gh_quiet() { (unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh "$@"); }

# valid_login <login> — ^[A-Za-z0-9-]{1,39}$ with the class spelled out (no locale range): only a
# well-formed login is ever echoed, so a hostile or garbled `api user` reply cannot reach the terminal.
valid_login() {
  case "$1" in
    ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
  esac
  [ "${#1}" -le 39 ]
}

# gh_identity_line — name the account the next `gh` calls act as, on STDERR (never stdout, never the rc).
# Credential source only; token values are never printed. Under CI no API call is made and no login is named.
gh_identity_line() {
  if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then _gil_src="token in environment"; else _gil_src="gh stored login"; fi
  if [ -n "${CI:-}" ]; then
    # Under CI "none" means no token in the environment (a stored gh login on a self-hosted runner is not detected).
    [ "$_gil_src" = "token in environment" ] || _gil_src="none"
    printf '%s\n' "acting gh identity: not read in CI (credential: $_gil_src)" >&2
    return 0
  fi
  if _gil_login=$(gh_quiet api user --jq .login 2>/dev/null) && valid_login "$_gil_login"; then
    printf '%s\n' "acting gh identity: $_gil_login (credential: $_gil_src)" >&2
  else
    printf '%s\n' "acting gh identity: not resolved (credential: $_gil_src; gh api user failed, so the next calls will likely fail too)" >&2
  fi
}

# SWAS-901: the picker for --replace's third profile, `solo-agent` (approvals 0, last_push false, enforce_admins true: `solo-go-bound`, run
# from the base branch, stands in for the approval one account cannot give). It is chosen only when the TARGET's default branch reads solo
# and all three probes hold on that same branch; every other case, an unreadable one included, reads the solo profile byte for byte.
# ba_forge_file <repo> <branch> <path> -> the file at the branch tip on stdout; rc 0 = printed, 1 = absent (the forge's 404), 2 = anything else
# (a failed read, a directory, a symlink). Two reads: the entry's type must be `file`, then its raw bytes.
ba_forge_file() {
  _bff_err=$(mktemp) || return 2
  if ! _bff_t=$(gh_quiet api "repos/$1/contents/$3?ref=$2" --jq '[.type,.path] | @tsv' 2>"$_bff_err"); then
    _bff_m=$(cat "$_bff_err" 2>/dev/null) || _bff_m=""
    rm -f "$_bff_err"
    case "$_bff_m" in
      *"Not Found"*|*"HTTP 404"*) return 1 ;;
    esac
    return 2
  fi
  rm -f "$_bff_err"
  [ "$_bff_t" = "$(printf 'file\t%s' "$3")" ] || return 2   # a regular file AT the requested path (a symlinked directory answers with another path) # MUT-BA-PATH
  gh_quiet api -H 'Accept: application/vnd.github.raw' "repos/$1/contents/$3?ref=$2" 2>/dev/null || return 2
}

# ba_rel_from_text <dial read rc> <dial text> <CLAUDE.md read rc> <CLAUDE.md text> -> `solo` | `team`: the grammar of promotion-verify.sh's
# pv_rel_from_tip, re-stated (that script cannot be sourced): the last MERGE_RELATIONSHIP line wins and its first word must be `solo`; a Governance
# `team` field line overrides it (solo alone grants nothing); a dial or CLAUDE.md read that failed, or is not a regular file, reads team. T14 diffs them.
ba_rel_from_text() {
  [ "$1" = 0 ] || { echo team; return 0; }
  _brt_line=$(printf '%s\n' "$2" | grep -E '^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=' | tail -n 1 || true)
  _brt_val=$(printf '%s' "$_brt_line" | sed -E "s/^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=[[:space:]]*//; s/#.*\$//; s/[\"']//g; s/[[:space:]].*\$//")
  [ "$_brt_val" = solo ] || { echo team; return 0; }
  if [ "$3" != 0 ] && [ "$3" != 1 ]; then echo team; return 0; fi
  if [ "$3" = 0 ]; then
    _brt_n=$(printf '%s\n' "$4" | grep -c -e '^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team):' || true)
    if [ "${_brt_n:-0}" -ge 1 ]; then
      _brt_vals=$(printf '%s\n' "$4" | sed -n 's#^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team): \([^[:space:]]*\).*$#\1#p')
      if printf '%s\n' "$_brt_vals" | grep -qx team; then echo team; return 0; fi
    fi
  fi
  echo solo
}

# ba_pick_profile -> sets PROFILE (solo | solo-agent) and PICK_WHY. Only called without --team.
ba_pick_profile() {
  PROFILE=solo; PICK_WHY=""
  _bp_def=$(gh_quiet api "repos/$REPO" --jq .default_branch 2>/dev/null | tr -d '[:cntrl:]' | cut -c1-100) || _bp_def=""
  if [ -z "$_bp_def" ]; then PICK_WHY="the default branch could not be read (an unreadable forge reads the solo profile)"; return 0; fi
  if [ "$BRANCH" != "$_bp_def" ]; then PICK_WHY="--branch is not the default branch ($_bp_def)"; return 0; fi
  # E6 R2-5: the tip is resolved ONCE and every read below is at that sha, so a push between two reads cannot mix two trees.
  _bp_tip=$(gh_quiet api "repos/$REPO/commits/$BRANCH" --jq .sha 2>/dev/null | tr -d '[:cntrl:]' | cut -c1-40) || _bp_tip=""
  if ! printf '%s' "$_bp_tip" | grep -qE '^[0-9a-f]{40}$'; then PICK_WHY="the default branch's tip could not be resolved (an unreadable forge reads the solo profile)"; return 0; fi
  _bp_drc=0; _bp_dial=$(ba_forge_file "$REPO" "$_bp_tip" .kit/dials.conf) || _bp_drc=$?
  _bp_crc=0; _bp_cl=$(ba_forge_file "$REPO" "$_bp_tip" CLAUDE.md) || _bp_crc=$?
  if [ "$(ba_rel_from_text "$_bp_drc" "$_bp_dial" "$_bp_crc" "$_bp_cl")" != solo ]; then PICK_WHY="the default branch does not read solo"; PICK_TEAM_WARN=1; return 0; fi   # MUT-BA-TEAMWARN
  _bp_rct=$(ba_forge_file "$REPO" "$_bp_tip" REQUIRED-CHECKS.md) || _bp_rct=""
  _bp_wft=$(ba_forge_file "$REPO" "$_bp_tip" .github/workflows/solo-go.yml) || _bp_wft=""
  _bp_pvt=$(ba_forge_file "$REPO" "$_bp_tip" scripts/promotion-verify.sh) || _bp_pvt=""
  _bp_local="$AD_LIST"; _bp_tf=$(mktemp) || { PICK_WHY="no scratch file for the forge copy of REQUIRED-CHECKS.md"; return 0; }
  printf '%s\n' "$_bp_rct" > "$_bp_tf"; ad_read_declaration "$_bp_tf"; _bp_forge="$AD_LIST"; rm -f "$_bp_tf"; AD_LIST="$_bp_local"
  printf '%s\n' $_bp_local | grep -qxF solo-go-bound || { PICK_WHY="the local declaration does not list solo-go-bound"; return 0; }
  printf '%s\n' $_bp_forge | grep -qx solo-go-bound || { PICK_WHY="REQUIRED-CHECKS.md on the default branch does not list solo-go-bound"; return 0; }
  printf '%s\n' "$_bp_wft" | grep -qF 'COPY & ADAPT' || { PICK_WHY="the solo-go workflow is not installed on the default branch"; return 0; }
  printf '%s\n' "$_bp_pvt" | grep -qF '# KIT-MODE: go-bound' || { PICK_WHY="scripts/promotion-verify.sh on the default branch has no go-bound verb"; return 0; }
  PROFILE=solo-agent
  PICK_WHY="the default branch reads solo, and solo-go-bound is declared, installed and read by the verbs"
}

# fetch_merge_methods <repo> -> the parsed merge methods on stdout (unknown on any read failure).
fetch_merge_methods() {
  if _fmm_body=$(gh_quiet api "repos/$1" --jq "$MM_JQ" 2>/dev/null); then parse_merge_methods "$_fmm_body"; else printf '%s' "unknown"; fi
}

# do_replace <repo> <branch> <solo|team> <contexts> — the post-confirmation write path: the protection
# PUT, then the merge-method PATCH. Returns 0 only when BOTH landed; otherwise 1, naming which half did.
do_replace() {
  _dr_repo=$1; _dr_branch=$2; _dr_profile=$3
  _dr_payload=$(build_replace_payload "$4" "$_dr_profile") || return 1
  # gh's stderr is kept (the PUT's stdout stays discarded): a free private repository's 403 says why there, and the
  # FAIL line used to drop it. The text is gh's own, so control bytes are stripped and it is capped before it prints.
  if ! _dr_err=$(printf '%s' "$_dr_payload" | gh_quiet api -X PUT "repos/$_dr_repo/branches/$_dr_branch/protection" --input - 2>&1 >/dev/null); then
    _dr_err=$(printf '%s' "$_dr_err" | tr '\n' ' ' | tr -d '[:cntrl:]' | cut -c1-200)
    printf '%s\n' "FAIL: the full PUT did not report success — run show-only (no flag) to read the live state and confirm what it holds; the merge-method PATCH was not attempted${_dr_err:+; gh said: $_dr_err}"
    return 1   # MUT-BA-PUTSTOP
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

# confirm_replace — the one TTY-GATED confirmation of --replace (type REPLACE; --apply's y/N is separate) (SEC M-1/M-2). Reads
# EXCLUSIVELY from /dev/tty, never stdin: piping input (`yes REPLACE | ...`) can no longer drive
# --replace at all — measured previously doing exactly that. Displays the concrete solo-default
# payload values (SEC M-2/REV H2) before checking for a tty, so the disclosure is seen even on the
# abort path.
confirm_replace() {  # [solo|team] [current merge methods]
  _cr_profile=${1:-solo}
  printf '%s\n' "WARNING: --replace performs a full PUT that OVERWRITES every branch-protection setting on" >&2
  printf '%s\n' "  $BRANCH (review requirements, enforce_admins, restrictions) — not just status-check" >&2
  if [ "$_cr_profile" = solo-agent ]; then
    printf '%s\n' "  contexts. Profile: SOLO-AGENT profile. The reset values are: enforce_admins:true ·" >&2
    printf '%s\n' "  required_approving_review_count:0 · dismiss_stale_reviews:true ·" >&2
    printf '%s\n' "  require_last_push_approval:false · require_code_owner_reviews:false." >&2
    printf '%s\n' "  solo-go-bound now reads your recorded GO in place of an approval: it refuses a head with no recorded GO, and the agent merges on that GO." >&2
    printf '%s\n' "  That GO is self-asserted and a note the agent records satisfies it; a fabricated GO is not caught server-side; an admin can still edit protection." >&2
  elif [ "$_cr_profile" = team ]; then
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
    printf '%s\n' "FAIL: $DECLARATION not found — nothing declared to apply (see templates/REQUIRED-CHECKS-TEMPLATE.md). No change was made."
    exit 1
  fi
  ad_read_declaration "$DECLARATION"
  if [ "$AD_TOOMANY" != 0 ]; then
    printf '%s\n' "FAIL: $DECLARATION declares more than $AD_MAX_LINES required-check context line(s) (cap exceeded — DoS bound). No change was made."
    exit 1
  fi
  if [ "$AD_INVALID" != 0 ]; then
    printf '%s\n' "FAIL: $DECLARATION declares an invalid required-check context name: $AD_INVALID_NAME (must match ^[A-Za-z0-9][A-Za-z0-9._/-]*\$, length<=100 — GitHub context names containing spaces are NOT declarable in v1; rename the CI job/step to a hyphenated name and re-declare). No change was made."
    exit 1
  fi
  if [ "$AD_DUP" != 0 ] || { [ "$AD_PLACEHOLDER" != 0 ] && [ -n "$AD_LIST" ]; }; then
    printf '%s\n' "FAIL: $DECLARATION is malformed (duplicate or placeholder-mixed) — run 'sh conformance/branch-protection.sh --declared-only' for details. No change was made."
    exit 1
  fi
  if [ "$AD_PLACEHOLDER" != 0 ] && [ -z "$AD_LIST" ]; then
    printf '%s\n' "N/A: $DECLARATION is the pristine stamped template — nothing to apply yet. No change was made."
    exit 0
  fi
  if [ -z "$AD_LIST" ]; then
    printf '%s\n' "FAIL: $DECLARATION declares zero active required-check contexts. No change was made."
    exit 1
  fi

  command -v gh >/dev/null 2>&1 || { printf '%s\n' "UNVERIFIED: gh not installed — cannot read or apply live branch protection. No change was made."; exit 2; }
  # SWAS-945: every gh call in this script strips these four (SEC M-3, SWAS-198), so the probe's gh does too.
  unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
  if command -v kit_gh_tls_pin >/dev/null 2>&1; then kit_gh_tls_pin; fi   # SWAS-945: the probe, once, before the first gh call
  gh_identity_line
  REPO="$REPO_OVERRIDE"
  if [ -z "$REPO" ]; then REPO=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true); fi
  [ -n "$REPO" ] || { printf '%s\n' "UNVERIFIED: no GitHub repo context for the gh identity above (pass --repo=OWNER/REPO, or use an account that can read this repo). No change was made."; exit 2; }
  valid_repo "$REPO" || { printf '%s\n' "UNVERIFIED: gh reported a repository name that is not OWNER/REPO (characters A-Za-z0-9._- only, no . or .. segment) — refusing to build API paths from it. No change was made."; exit 2; }

  if BODY=$(fetch_live_protection "$REPO" "$BRANCH"); then LIVE_RC=0; else LIVE_RC=$?; fi
  if [ "$LIVE_RC" = 4 ]; then
    # K8: ONLY --replace consumes the not-protected outcome. --apply is additive and has nothing to
    # add TO, and the dry-run has nothing to read — both keep UNVERIFIED rc 2, naming the remedy.
    if [ "$MODE" = replace ]; then
      BODY=""
      printf '%s\n' "NOT PROTECTED: $REPO:$BRANCH carries no branch protection yet — --replace will ESTABLISH it from the declaration below. The typed confirmation still applies."
    else
      printf '%s\n' "UNVERIFIED: $REPO:$BRANCH is not protected yet, so there is nothing live to read and the additive path has nothing to add to — three-state, not a pass. Re-run with --replace to ESTABLISH protection from the declaration (see profiles/<stack>/BRANCH-PROTECTION.md). No change was made."
      exit 2
    fi
  elif [ "$LIVE_RC" != 0 ]; then
    printf '%s\n' "UNVERIFIED: could not fetch live branch protection for $REPO:$BRANCH (no admin rights, or a transient error) — three-state, not a pass; if no protection exists on the branch yet, --replace establishes it (see profiles/<stack>/BRANCH-PROTECTION.md). No change was made."
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
    PROFILE=solo; [ "$TEAM" = 1 ] && PROFILE=team
    PICK_WHY="--team names the team profile"
    [ "$TEAM" = 1 ] || ba_pick_profile
    _bp_live=$(printf '%s' "$BODY" | tr -d ' \t\n' | sed -n 's/.*"required_approving_review_count":\([0-9][0-9]*\).*/\1/p' | head -n 1)
    _bp_tgt=1; [ "$PROFILE" != solo-agent ] || _bp_tgt=0
    printf '%s\n' "  review-count: live=${_bp_live:-absent} target=$_bp_tgt (profile=$PROFILE: $PICK_WHY)"
    if [ "$PICK_TEAM_WARN" = 1 ]; then
      printf '%s\n' "WARN: the default branch does not read solo, but --team is absent, so --replace writes the SOLO profile (enforce_admins:false). For a team repository run --replace --team. A solo repository reads team until its .kit/dials.conf PR merges; until then, --replace (solo) is right for a solo project."
    fi
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
      confirm "Proceed? [y/N]" || { printf '%s\n' "Aborted. No change was made."; exit 1; }
      _pargs=""
      for _c in $TOADD; do _pargs="$_pargs -f contexts[]=$_c"; done
      # shellcheck disable=SC2086  # word-splitting is deliberate: one -f per declared context
      if (unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh api -X POST "repos/$REPO/branches/$BRANCH/protection/required_status_checks/contexts" $_pargs) >/dev/null 2>&1; then
        printf '%s\n' "OK: added$TOADD to $REPO:$BRANCH (additive — every other protection setting untouched)"
        exit 0
      fi
      printf '%s\n' "FAIL: the additive POST failed"
      exit 1 ;;
    replace)
      _dd=$(dirname -- "$DECLARATION"); _top=$(git -C "$_dd" rev-parse --show-toplevel 2>/dev/null) || _top=$_dd
      [ "$PROFILE" = team ] && team_preflight "$REPO" "$_top"
      confirm_replace "$PROFILE" "$MM_CURRENT" || { printf '%s\n' "Aborted. No change was made."; exit 1; }
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
  _d=""; _ghdir=""; _extradir=""; _ghenvdir=""; _tp=""; _ng=""
  trap 'rm -rf "$_d" "$_ghdir" "$_extradir" "$_ghenvdir" "$_tp" "${_ng:-}" 2>/dev/null || true' EXIT
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
  *"api user"*) echo stub-login ;;
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
  # SWAS-907 C3: every exit in main before do_replace says the run wrote nothing. The three exits an operator meets mid-Inception, each driven for real:
  # a non-admin token (the stub's 403 read: _fbout above), --apply on a repository that is not protected yet (_apout above), and no gh on PATH.
  if [ "$_fbrc" = 2 ] && printf '%s\n' "$_fbout" | grep -qE '^(UNVERIFIED|FAIL):.*No change was made\.$'; then
    echo "selftest PASS: SWAS-907 — a non-admin (403) live read exits 2 and says 'No change was made.'"
  else
    echo "selftest FAIL: SWAS-907 — the non-admin live-read exit does not say 'No change was made.' (rc=$_fbrc, out: $_fbout)"; st=1
  fi
  if [ "$_aprc" = 2 ] && printf '%s\n' "$_apout" | grep -qE '^(UNVERIFIED|FAIL):.*No change was made\.$'; then
    echo "selftest PASS: SWAS-907 — not-protected + --apply exits 2 and says 'No change was made.'"
  else
    echo "selftest FAIL: SWAS-907 — the not-protected --apply exit does not say 'No change was made.' (rc=$_aprc, out: $_apout)"; st=1
  fi
  _ng=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the no-gh PATH"; exit 1; }
  _shbin=$(command -v sh)
  for _ngt in sed tr cut grep cat dirname mktemp head; do
    _ngp=$(command -v "$_ngt" 2>/dev/null || true)
    case "$_ngp" in /*) ln -s "$_ngp" "$_ng/$_ngt" ;; esac
  done
  if _ngout=$(env PATH="$_ng" "$_shbin" "$0" --repo=me/repo --declaration="$_d/decl.md" 2>&1); then _ngrc=0; else _ngrc=$?; fi
  if [ "$_ngrc" = 2 ] && printf '%s\n' "$_ngout" | grep -qE '^UNVERIFIED: gh not installed.*No change was made\.$'; then
    echo "selftest PASS: SWAS-907 — no gh on PATH exits 2 and says 'No change was made.'"
  else
    echo "selftest FAIL: SWAS-907 — the no-gh exit does not say 'No change was made.' (rc=$_ngrc, out: $_ngout)"; st=1
  fi
  rm -rf "$_np" "$_fb" "$_ng" 2>/dev/null || true

  # 7. never emits --admin, in any mode exercised above (accumulated log — see below).

  # Live-extra relabeling + payload-values display (SEC M-2/REV H2): a stub gh reporting an
  # undeclared live context ("legacy-check"). Dry-run/--apply keep it "(informational only — never
  # applied)"; --replace relabels it "WILL BE REMOVED by --replace" — the diff print happens BEFORE
  # confirm_replace()'s tty-abort, so both are observable even with no tty.
  _extradir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the extra-context gh stub"; st=1; }
  cat > "$_extradir/gh" <<'STUBX'
#!/bin/sh
case "$*" in
  *"api user"*) echo stub-login ;;
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
  *"api user"*) echo stub-login ;;
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

  # GH env containment (SEC M-3, narrowed by SWAS-198): GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/
  # GITHUB_ENTERPRISE_TOKEN must never reach the gh subprocess (stale-state hygiene); GH_TOKEN and
  # GH_CONFIG_DIR (which pick the operator's account) must reach it. Proven with a stub gh that dumps
  # its own env under a `== ARGS: <args>` header per call, so each env block is tied to its call.
  # Every cell that expects the non-CI identity read sets CI='' (ci.yml runs this with CI=true).
  _ghenvdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the GH-env fixture"; st=1; }
  _ghenvlog="$_ghenvdir/env.log"
  : > "$_ghenvlog"
  cat > "$_ghenvdir/gh" <<STUBENV
#!/bin/sh
printf '== ARGS: %s\n' "\$*" >> "$_ghenvlog"
env | grep -e '^GH_' -e '^GITHUB_ENTERPRISE_TOKEN=' | sed 's/^\([A-Za-z_]*TOKEN\)=.*/\1=<set>/' | sort >> "$_ghenvlog" 2>/dev/null || true
case "\$*" in
  *"api user"*) [ -z "\${STUB_USER_FAIL:-}" ] || exit 1; echo "\${STUB_USER_OUT:-stub-login}" ;;
  *"-X POST"*|*"-X PUT"*) exit 0 ;;
  *"repo view"*) echo "\${STUB_REPO_OUT:-me/repo}" ;;
  *) printf '%s' '{"required_pull_request_reviews":{},"required_status_checks":{"contexts":["ci","control-plane-ratification"]}}' ;;
esac
STUBENV
  chmod +x "$_ghenvdir/gh"
  # blk <log> <header-needle> — the env block(s) recorded under the call(s) whose header holds the needle.
  blk() { awk -v h="$2" '/^== ARGS: /{p=(index($0,h)>0)} p' "$1"; }
  # redact — failure diagnostics show variable NAMES only (an ambient credential must never be echoed).
  redact() { sed 's/^\([A-Za-z_][A-Za-z_]*\)=.*/\1=<withheld>/'; }
  _evil_env() { env GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=evil-ent-token GITHUB_ENTERPRISE_TOKEN=evil-gh-ent GH_CONFIG_DIR=/op-config GH_TOKEN=real-op-token "$@"; }
  : > "$_ghenvlog"
  _evil_env CI='' PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" >"$_ghenvdir/out" 2>"$_ghenvdir/err" && _idrc=0 || _idrc=$?
  # A1. GH_CONFIG_DIR is the operator's account selector and reaches gh (like GH_TOKEN).
  _ncall=$(grep -c '^== ARGS: ' "$_ghenvlog" || true)
  _ncfg=$(grep -c '^GH_CONFIG_DIR=/op-config' "$_ghenvlog" || true)
  if [ "$_ncall" -gt 0 ] && [ "$_ncall" = "$_ncfg" ]; then
    echo "selftest PASS: GH_CONFIG_DIR (the operator's account selector) reaches EVERY gh call ($_ncfg of $_ncall)"
  else
    echo "selftest FAIL: GH_CONFIG_DIR was stripped (log: $(redact < "$_ghenvlog"))"; st=1
  fi
  # A2. the four stale-state variables never reach gh, one assertion apiece.
  for _sv in GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
    if grep -q "^$_sv=" "$_ghenvlog"; then
      echo "selftest FAIL: $_sv reached the gh subprocess (log: $(redact < "$_ghenvlog"))"; st=1
    else
      echo "selftest PASS: $_sv never reaches the gh subprocess"
    fi
  done
  # A3. GH_TOKEN still reaches gh.
  if grep -q '^GH_TOKEN=<set>' "$_ghenvlog"; then
    echo "selftest PASS: GH_TOKEN (the operator's real credential) still reaches the gh subprocess"
  else
    echo "selftest FAIL: GH_TOKEN was stripped too (it must be honored, not contained) (log: $(redact < "$_ghenvlog"))"; st=1
  fi
  # A2b. the --apply POST carries the same containment (its own inline unset list).
  : > "$_ghenvlog"
  printf '```\nci\nnew-check\n```\n' > "$_d/decl-new.md"
  printf 'y\n' | { _evil_env CI='' PATH="$_ghenvdir:$PATH" sh "$0" --repo=me/repo --declaration="$_d/decl-new.md" --apply; } >/dev/null 2>&1 || true
  _pb=$(blk "$_ghenvlog" "-X POST")
  if [ -n "$_pb" ] && ! printf '%s\n' "$_pb" | grep -q -e '^GH_HOST=' -e '^GH_REPO=' -e '^GH_ENTERPRISE_TOKEN=' -e '^GITHUB_ENTERPRISE_TOKEN=' \
     && printf '%s\n' "$_pb" | grep -q '^GH_CONFIG_DIR=/op-config'; then
    echo "selftest PASS: the --apply POST strips the four stale-state variables and honours GH_CONFIG_DIR"
  else
    echo "selftest FAIL: --apply POST env containment (block: $(printf '%s\n' "$_pb" | redact))"; st=1
  fi
  # A5. CI='' and no --repo: the identity line is on stderr only, comes before `repo view` in the call
  # order, and precedes the first to-add line in the merged output.
  : > "$_ghenvlog"
  _evil_env CI='' PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" >"$_ghenvdir/out" 2>"$_ghenvdir/err" && _idrc=0 || _idrc=$?
  _merged=$(_evil_env CI='' PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" 2>&1) || true
  _un=$(grep -n '^== ARGS: api user' "$_ghenvlog" | head -n 1 | cut -d: -f1)
  _rv=$(grep -n '^== ARGS: repo view' "$_ghenvlog" | head -n 1 | cut -d: -f1)
  _il=$(printf '%s\n' "$_merged" | grep -n 'acting gh identity:' | head -n 1 | cut -d: -f1)
  _ta=$(printf '%s\n' "$_merged" | grep -n 'to-add:' | head -n 1 | cut -d: -f1)
  if grep -qF 'acting gh identity: stub-login (credential: token in environment)' "$_ghenvdir/err" \
     && ! grep -qF 'acting gh identity' "$_ghenvdir/out" \
     && [ -n "$_un" ] && [ -n "$_rv" ] && [ "$_un" -lt "$_rv" ] \
     && [ -n "$_il" ] && [ -n "$_ta" ] && [ "$_il" -lt "$_ta" ]; then
    echo "selftest PASS: the acting gh identity is named on stderr, before repo view and before any listing"
  else
    echo "selftest FAIL: identity line placement (err=[$(cat "$_ghenvdir/err")] api-user@$_un repo-view@$_rv line@$_il to-add@$_ta)"; st=1
  fi
  # A8. the identity read happened and is contained.
  _ub=$(blk "$_ghenvlog" "api user")
  if [ -n "$_ub" ] && ! printf '%s\n' "$_ub" | grep -q -e '^GH_HOST=' -e '^GH_REPO=' -e '^GH_ENTERPRISE_TOKEN=' -e '^GITHUB_ENTERPRISE_TOKEN='; then
    echo "selftest PASS: the identity read ran (api user) with the stale-state variables stripped"
  else
    echo "selftest FAIL: no api user call, or it carried a stripped variable (block: $(printf '%s\n' "$_ub" | redact))"; st=1
  fi
  # A6. a failed identity read says so and moves neither stdout nor the exit code.
  cp "$_ghenvdir/out" "$_ghenvdir/out.ok"; _okrc=$_idrc
  _evil_env CI='' STUB_USER_FAIL=1 PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" >"$_ghenvdir/out" 2>"$_ghenvdir/err" && _idrc=0 || _idrc=$?
  if grep -qF 'acting gh identity: not resolved (credential: token in environment;' "$_ghenvdir/err" \
     && cmp -s "$_ghenvdir/out" "$_ghenvdir/out.ok" && [ "$_idrc" = "$_okrc" ]; then
    echo "selftest PASS: an unreadable identity says 'not resolved' and never moves stdout or the exit code"
  else
    echo "selftest FAIL: failed identity read (err=[$(cat "$_ghenvdir/err")] rc=$_idrc vs $_okrc)"; st=1
  fi
  # L2. a malformed login (space, control byte, over 39 characters) is never echoed: it reads 'not resolved'.
  _long=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  for _ml in 'bad login' 'x;rm' "$_long"; do
    _evil_env CI='' STUB_USER_OUT="$_ml" PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" >/dev/null 2>"$_ghenvdir/err" || true
    if grep -qF 'acting gh identity: not resolved' "$_ghenvdir/err" && ! grep -qF -e "$_ml" "$_ghenvdir/err"; then
      echo "selftest PASS: a malformed login is never echoed (L2)"
    else
      echo "selftest FAIL: malformed login reached the terminal (err=[$(cat "$_ghenvdir/err")])"; st=1
    fi
  done
  # L3. a repo name gh reports that is not OWNER/REPO is UNVERIFIED (rc 2) before any protection call.
  : > "$_ghenvlog"
  _o=$(_evil_env CI='' STUB_REPO_OUT='../x' PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" 2>&1) && _rc=0 || _rc=$?
  if [ "$_rc" = 2 ] && printf '%s\n' "$_o" | grep -qF 'UNVERIFIED: gh reported a repository name that is not OWNER/REPO' && ! grep -qF 'branches/main/protection' "$_ghenvlog"; then
    echo "selftest PASS: an invalid repo name from gh is UNVERIFIED rc 2 with no protection call (L3)"
  else
    echo "selftest FAIL: invalid gh repo name (rc=$_rc out=[$_o])"; st=1
  fi
  # A7. under CI only the credential source is named: no API call, no login.
  : > "$_ghenvlog"
  _evil_env CI=true PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" >/dev/null 2>"$_ghenvdir/err" || true
  _noc=$(env CI=true GH_TOKEN='' GITHUB_TOKEN='' PATH="$_ghenvdir:$PATH" sh "$0" --declaration="$_d/decl.md" 2>&1 >/dev/null) || true
  if grep -qF 'acting gh identity: not read in CI (credential: token in environment)' "$_ghenvdir/err" \
     && ! grep -qF 'stub-login' "$_ghenvdir/err" && ! grep -q '^== ARGS: api user' "$_ghenvlog" \
     && printf '%s\n' "$_noc" | grep -qF 'acting gh identity: not read in CI (credential: none)'; then
    echo "selftest PASS: under CI the identity line names only the credential source (no API call, no login)"
  else
    echo "selftest FAIL: CI identity line (err=[$(cat "$_ghenvdir/err")] none=[$_noc])"; st=1
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
printf '== ARGS: %s\n' "$*" >> "$STUB_DIR/env.log"
env | grep -e '^GH_' -e '^GITHUB_ENTERPRISE_TOKEN=' | sed 's/^\([A-Za-z_]*TOKEN\)=.*/\1=<set>/' | sort >> "$STUB_DIR/env.log" 2>/dev/null || true
case "$*" in
  *"api user"*) echo stub-login ;;
  *"-X PUT"*) cat > "$STUB_DIR/put.body"; [ -z "${STUB_PUT_ERR:-}" ] || printf '%s\n' "$STUB_PUT_ERR" >&2; exit "${STUB_PUT_RC:-0}" ;;
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
  # T7e (SWAS-901 R3-1). the solo-agent profile's failed PUT stops before the merge-method PATCH too. The mutant is a sed copy of do_replace
  # whose stop after the failed PUT is gone; it is sourced inside the cell's subshell, and the cell must then FAIL.
  _f_t7e() {   # [<file holding a do_replace to use instead of the real one>]
    : > "$_tplog"
    # shellcheck source=/dev/null  # the mutant's do_replace, written by the T7em run below
    _o=$( ( if [ -n "${1:-}" ]; then . "$1"; fi; PATH="$_tp:$PATH"; STUB_DIR="$_tp"; STUB_PUT_RC=1; export STUB_DIR STUB_PUT_RC; do_replace me/repo main solo-agent "ci solo-go-bound" ) 2>&1 ) && _rc=0 || _rc=$?
    [ "$_rc" = 1 ] && ! grep -qF -- "-X PATCH" "$_tplog" && printf '%s\n' "$_o" | grep -qF "did not report success"
  }
  if _f_t7e; then echo "selftest PASS: T7e: a failed solo-agent PUT exits 1 and never attempts the merge-method PATCH"; else echo "selftest FAIL: T7e: solo-agent PUT-failure path (log=$(cat "$_tplog" 2>/dev/null))"; st=1; fi
  _t7m="$_tp/do_replace-mut.sh"; sed -n '/^do_replace() {$/,/^}$/p' "$0" | sed '/MUT-BA-PUTSTOP$/s/return 1/:/' > "$_t7m"
  if [ ! -s "$_t7m" ] || sed -n '/^do_replace() {$/,/^}$/p' "$0" | cmp -s - "$_t7m"; then echo "selftest FAIL: T7em: the mutant changed nothing"; st=1
  elif _f_t7e "$_t7m"; then echo "selftest FAIL: T7em: a do_replace that goes on to the PATCH after a failed PUT -- the mutant SURVIVED"; st=1
  else echo "selftest PASS: T7em: a do_replace that goes on to the PATCH after a failed PUT (the mutant is killed)"; fi
  # T7d (SWAS-212). a PUT refused with the upgrade text puts gh's stderr on the FAIL line, stripped of control bytes and
  # capped; the PATCH is still not attempted, and the rc is still 1.
  : > "$_tplog"
  _esc=$(printf '\033'); _long=$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80)
  _upg="gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)"
  _o=$( ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; STUB_PUT_RC=1; STUB_PUT_ERR="${_esc}[31m$_upg $_long$_long$_long"; export STUB_DIR STUB_PUT_RC STUB_PUT_ERR; do_replace me/repo main solo "ci" ) 2>&1 ) && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ] && printf '%s\n' "$_o" | grep -qF "; gh said: [31m$_upg" && ! printf '%s' "$_o" | grep -q "$_esc" \
     && [ "$(printf '%s\n' "$_o" | head -n 1 | sed 's/^.*; gh said: //' | wc -c | tr -d ' ')" -le 202 ] && ! grep -qF -- "-X PATCH" "$_tplog"; then
    echo "selftest PASS: a refused PUT prints gh's stderr on the FAIL line, control bytes stripped and capped"
  else
    echo "selftest FAIL: PUT stderr on the FAIL line (rc=$_rc, out=$_o)"; st=1
  fi
  # a silent PUT failure keeps the line exactly as before (no dangling 'gh said')
  _o=$( ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; STUB_PUT_RC=1; export STUB_DIR STUB_PUT_RC; do_replace me/repo main solo "ci" ) 2>&1 ) && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ] && ! printf '%s\n' "$_o" | grep -qF "gh said"; then echo "selftest PASS: a PUT that says nothing adds no 'gh said' text"; else echo "selftest FAIL: silent PUT failure line (rc=$_rc, out=$_o)"; st=1; fi
  # T7c (A4). GH env containment reaches the new calls (PUT and PATCH): under each call's header the
  # four stale-state variables are absent, GH_CONFIG_DIR and GH_TOKEN reach gh.
  : > "$_tp/env.log"
  ( PATH="$_tp:$PATH"; STUB_DIR="$_tp"; GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=x GITHUB_ENTERPRISE_TOKEN=y GH_CONFIG_DIR=/op-config GH_TOKEN=real; export STUB_DIR GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR GH_TOKEN; do_replace me/repo main solo "ci" ) >/dev/null 2>&1 || true
  for _call in "-X PUT" "-X PATCH"; do
    _cb=$(blk "$_tp/env.log" "$_call")
    if [ -n "$_cb" ] && ! printf '%s\n' "$_cb" | grep -q -e '^GH_HOST=' -e '^GH_REPO=' -e '^GH_ENTERPRISE_TOKEN=' -e '^GITHUB_ENTERPRISE_TOKEN=' \
       && printf '%s\n' "$_cb" | grep -q '^GH_CONFIG_DIR=/op-config' && printf '%s\n' "$_cb" | grep -q '^GH_TOKEN=<set>'; then
      echo "selftest PASS: GH env containment holds for the $_call (stale-state stripped, GH_CONFIG_DIR and GH_TOKEN honoured)"
    else
      echo "selftest FAIL: GH env containment on do_replace $_call (block: $(printf '%s\n' "$_cb" | redact))"; st=1
    fi
  done

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

  # ── SWAS-901 slice B (B2): the third profile, `solo-agent`. A stub forge serves the target's default branch and its files (a 404 for an
  # absent one, a 500 for a failed read); the picker may choose it only when the default branch reads solo AND all three probes hold
  # (REQUIRED-CHECKS.md lists solo-go-bound, the workflow is installed, the verbs carry the go-bound marker). Anything else, a failed read
  # included, reads the solo profile byte for byte. The payload is driven through --print-payload (no gh call), the picker through the
  # show-only line. Each mutant is a sed COPY of this script; `cmp` proves the sed applied. No cell can reach a PUT: --replace is tty-gated.
  _bf=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the solo-agent fixtures"; exit 1; }
  printf '```\nci\nsolo-go-bound\n```\n' > "$_bf/decl-sg.md"
  _ba_script="$0"
  _SGD='MERGE_RELATIONSHIP=solo'; _SGC='# COPY & ADAPT'; _SGP='# KIT-MODE: go-bound'
  _SGR="$(printf '```\nci\nsolo-go-bound\n```')"; _SGR0="$(printf '```\nci\n```')"
  _ba_fx() {   # <name> <dial|-> <CLAUDE.md|-> <REQUIRED-CHECKS.md|-> <workflow|-> <promotion-verify.sh|-> [<file whose read fails>]
    _bfd="$_bf/$1"; rm -rf "$_bfd"; mkdir -p "$_bfd/files/.kit" "$_bfd/files/.github/workflows" "$_bfd/files/scripts"
    if [ "$2" != - ]; then printf '%s\n' "$2" > "$_bfd/files/.kit/dials.conf"; fi
    if [ "$3" != - ]; then printf '%s\n' "$3" > "$_bfd/files/CLAUDE.md"; fi
    if [ "$4" != - ]; then printf '%s\n' "$4" > "$_bfd/files/REQUIRED-CHECKS.md"; fi
    if [ "$5" != - ]; then printf '%s\n' "$5" > "$_bfd/files/.github/workflows/solo-go.yml"; fi
    if [ "$6" != - ]; then printf '%s\n' "$6" > "$_bfd/files/scripts/promotion-verify.sh"; fi
    if [ -n "${7:-}" ]; then : > "$_bfd/fail-$7"; fi
    printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci"]}}' > "$_bfd/prot.json"
    printf '%s' 1111111111111111111111111111111111111111 > "$_bfd/tipsha"
    : > "$_bfd/log"
    printf '%s\n' '#!/bin/sh' 'd=$(dirname "$0"); a="$*"; printf "%s\n" "$a" >> "$d/log"' 'case "$a" in' \
      '  *"api user"*) echo stub-login ;;' \
      '  *"-X POST"*|*"-X PUT"*|*"-X PATCH"*) exit 0 ;;' \
      '  *"--jq .default_branch"*) echo main ;;' \
      '  *"--jq .sha"*) cat "$d/tipsha" ;;' \
      '  *contents/*)' \
      '    p=${a#*contents/}; p=${p%%\?*}' \
      '    if [ -f "$d/fail-${p##*/}" ]; then echo "gh: HTTP 500" >&2; exit 1; fi' \
      '    if [ ! -f "$d/files/$p" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi' \
      '    case "$a" in' \
      '      *"@tsv"*) if [ -f "$d/redirect-${p##*/}" ]; then printf "file\t%s\n" "elsewhere/${p##*/}"; else printf "file\t%s\n" "$p"; fi ;;' \
      '      *) cat "$d/files/$p" ;;' \
      '    esac ;;' \
      '  *"branches/main/protection"*) cat "$d/prot.json" ;;' \
      '  *) echo true true true ;;' \
      'esac' > "$_bfd/gh"
    chmod +x "$_bfd/gh"
  }
  _ba_run() {   # <fixture> [args] -> _bo (the output of one run of the script under test against that forge)
    _bfx="$1"; shift
    _bo=$(PATH="$_bf/$_bfx:$PATH" sh "$_ba_script" --repo=me/repo --declaration="$_bf/decl-sg.md" "$@" 2>&1) || true
  }
  _ba_pick() { _bpn="$1"; _bpe="$2"; shift 2; _ba_run "$_bpn" "$@"; printf '%s\n' "$_bo" | grep -qF "(profile=$_bpe:"; }   # <fixture> <profile> [args]
  _ba_cell() { if "$2" "$1"; then echo "selftest PASS: $1: $3"; else echo "selftest FAIL: $1: $3"; st=1; fi; }   # <label> <cell fn> <desc>
  _ba_mut() {   # <label> <sed> <cell fn> <desc>: the cell must FAIL against the sed copy
    _bm="$_bf/mut-$1.sh"; sed "$2" "$0" > "$_bm"
    if cmp -s "$0" "$_bm"; then echo "selftest FAIL: $1: the mutant changed nothing"; st=1; return 0; fi
    _ba_script="$_bm"
    if "$3" "m$1"; then echo "selftest FAIL: $1: $4 -- the mutant SURVIVED"; st=1; else echo "selftest PASS: $1: $4 (the mutant is killed)"; fi
    _ba_script="$0"
  }
  _f_t11() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; _ba_pick "$1" solo-agent && printf '%s\n' "$_bo" | grep -qF 'review-count: live=1 target=0'; }
  _f_t11b() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" -; _ba_pick "$1" solo; }
  _f_t11c() { _ba_fx "$1" "$_SGD" - "$_SGR" - "$_SGP"; _ba_pick "$1" solo; }
  _f_t11d() { _ba_fx "$1" "$_SGD" - "$_SGR0" "$_SGC" "$_SGP"; _ba_pick "$1" solo; }
  _f_t12a() { _ba_fx "$1" - - "$_SGR" "$_SGC" "$_SGP"; _ba_pick "$1" solo; }
  _f_t12b() { _ba_fx "$1" MERGE_RELATIONSHIP=team - "$_SGR" "$_SGC" "$_SGP"; _ba_pick "$1" solo; }
  _f_t12c() { _ba_fx "$1" "$_SGD" '- **Governance** (§ solo/team): team — non-author approval' "$_SGR" "$_SGC" "$_SGP"; _ba_pick "$1" solo; }
  _f_t12d() { _ba_fx "$1" "$_SGD" 'notes' "$_SGR" "$_SGC" "$_SGP" CLAUDE.md; _ba_pick "$1" solo; }
  _f_t12e() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; _ba_pick "$1" solo --branch=release/1.x; }
  _f_t12f() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; : > "$_bf/$1/redirect-dials.conf"; _ba_pick "$1" solo; }   # the forge answers the dial's request with ANOTHER path (a symlinked directory): not that file
  _ba_cell T11 _f_t11 "the dial reads solo and all three probes hold: the solo-agent profile, review-count live=1 target=0"
  _ba_mut T11m 's@^  PROFILE=solo-agent$@  PROFILE=solo@' _f_t11 "a picker that never picks solo-agent fails the liveness cell"
  _ba_cell T11b _f_t11b "the verbs do not carry the go-bound marker: the solo profile"
  _ba_mut T11bm '/KIT-MODE: go-bound.*PICK_WHY/d' _f_t11b "without probe (iii) the missing marker still picks solo-agent"
  _ba_cell T11c _f_t11c "the workflow is not installed on the default branch: the solo profile"
  _ba_mut T11cm '/COPY & ADAPT.*PICK_WHY/d' _f_t11c "without probe (ii) the missing workflow still picks solo-agent"
  _ba_cell T11d _f_t11d "the forge copy of REQUIRED-CHECKS.md does not list solo-go-bound: the solo profile"
  _ba_mut T11dm '/-qx solo-go-bound.*PICK_WHY/d' _f_t11d "without probe (i) an undeclared context still picks solo-agent"
  _ba_cell T12a _f_t12a "an undeclared default branch (no dial): the solo profile"
  _ba_cell T12b _f_t12b "MERGE_RELATIONSHIP=team: the solo profile"
  _ba_cell T12c _f_t12c "a Governance team line over a solo dial: the solo profile"
  _ba_mut T12cm '/grep -qx team; then echo team/d' _f_t12c "without the Governance override a team line cannot hold back solo-agent"
  _ba_cell T12d _f_t12d "a CLAUDE.md read that fails (a 500) reads solo, never absent: the solo profile"
  _ba_mut T12dm '/^  if \[ "\$3" != 0 \] && \[ "\$3" != 1 \]; then echo team; return 0; fi$/d' _f_t12d "reading a failed CLAUDE.md as no Governance line grants solo-agent"
  _ba_mut T12am '/^  if \[ "\$(ba_rel_from_text/d' _f_t12a "without the relationship test an undeclared default branch gets solo-agent"
  # SWAS-907 Q3 (RB-26): when the picker reads team and --team is absent, one WARN says so. It changes no profile. Silent when the forge reads solo, or --team is given.
  _swarn='WARN: the default branch does not read solo, but --team is absent'
  _f_t13w() { _ba_fx "$1" MERGE_RELATIONSHIP=team - "$_SGR" "$_SGC" "$_SGP"; _ba_run "$1"; printf '%s\n' "$_bo" | grep -qF "$_swarn" && printf '%s\n' "$_bo" | grep -qF '(profile=solo:'; }
  _f_t13s() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; _ba_run "$1"; ! printf '%s\n' "$_bo" | grep -qF "$_swarn"; }
  _f_t13t() { _ba_fx "$1" MERGE_RELATIONSHIP=team - "$_SGR" "$_SGC" "$_SGP"; _ba_run "$1" --replace --team; ! printf '%s\n' "$_bo" | grep -qF "$_swarn"; }
  _ba_cell T13w _f_t13w "the forge reads team and --team is absent: one WARN, and the profile stays solo"
  _ba_cell T13s _f_t13s "the forge reads solo: no team WARN"
  _ba_cell T13t _f_t13t "--replace --team on a team-reading forge: no WARN (the picker is not consulted)"
  _ba_mut T13wm '/# MUT-BA-TEAMWARN$/s/PICK_TEAM_WARN=1/PICK_TEAM_WARN=0/' _f_t13w "a picker that never raises the flag prints no WARN"
  _ba_mut T12bm '/^  if \[ "\$(ba_rel_from_text/d' _f_t12b "without the relationship test a team default branch gets solo-agent"
  _ba_cell T12f _f_t12f "a forge entry whose path is not the requested path (a symlinked directory) is not that file: the solo profile"
  _ba_mut T12fm '/MUT-BA-PATH$/d' _f_t12f "accepting any path lets a symlinked .kit grant solo-agent"
  _f_t12g() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; _ba_pick "$1" solo-agent && ! grep -q 'ref=main' "$_bf/$1/log" && grep -q 'ref=1111111111111111111111111111111111111111' "$_bf/$1/log"; }   # E6 R2-5: every forge read is at ONE resolved tip sha
  _ba_cell T12g _f_t12g "the default branch's tip is resolved once and every file read is at that sha, never the moving branch name"
  _ba_mut T12gm 's/ba_forge_file "\$REPO" "\$_bp_tip"/ba_forge_file "$REPO" "$BRANCH"/g' _f_t12g "reading each file at the branch name lets a push between two reads mix two trees"
  _ba_cell T12e _f_t12e "--branch is not the default branch: the solo profile"
  _ba_mut T12em '/"\$BRANCH" != "\$_bp_def"/d' _f_t12e "without the default-branch test another branch gets solo-agent"
  _p3='"ci","solo-go-bound"'
  _sa_lit="{\"required_status_checks\":{\"strict\":true,\"checks\":[{\"context\":\"ci\"},{\"context\":\"solo-go-bound\",\"app_id\":15368}]},\"enforce_admins\":true,\"required_pull_request_reviews\":{\"required_approving_review_count\":0,\"dismiss_stale_reviews\":true,\"require_last_push_approval\":false,\"require_code_owner_reviews\":false},\"restrictions\":null}"
  _tm_lit="{\"required_status_checks\":{\"strict\":true,\"contexts\":[$_p3]},\"enforce_admins\":true,\"required_pull_request_reviews\":{\"required_approving_review_count\":1,\"dismiss_stale_reviews\":true,\"require_last_push_approval\":true,\"require_code_owner_reviews\":true},\"restrictions\":null}"
  _so_lit="{\"required_status_checks\":{\"strict\":true,\"contexts\":[$_p3]},\"enforce_admins\":false,\"required_pull_request_reviews\":{\"required_approving_review_count\":1,\"dismiss_stale_reviews\":true,\"require_last_push_approval\":true,\"require_code_owner_reviews\":false},\"restrictions\":null}"
  _ba_pl() { sh "$_ba_script" --declaration="$_bf/decl-sg.md" --print-payload="$1" 2>/dev/null; }
  _f_t11e() { [ "$(_ba_pl solo-agent)" = "$_sa_lit" ]; }
  _f_t13() { [ "$(_ba_pl team)" = "$_tm_lit" ] && [ "$(_ba_pl solo)" = "$_so_lit" ]; }
  _f_t13b() { _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; _ba_run "$1" --replace --team; ! grep -qF 'contents/' "$_bf/$1/log" && ! grep -qF -e '-X PUT' "$_bf/$1/log"; }
  _ba_cell T11e _f_t11e "the solo-agent payload: count 0, last_push false, enforce_admins true, strict, the other contexts, and solo-go-bound pinned to the Actions app (15368)"
  _ba_mut T11ep 's/15368/1/g' _f_t11e "an unpinned solo-go-bound lets any app's same-named check satisfy it"
  _ba_mut T11cx '/MUT-BA-CHK$/s/="\\"checks/="\\"contexts\\":[],\\"checks/' _f_t11e "a solo-agent body that sends contexts beside checks is refused by GitHub's oneOf (measured, SWAS-915 L1)"
  _ba_mut T11fm '/MUT-BA-CHK$/s/\\"checks\\".*]"/"/' _f_t11e "a solo-agent body that drops the checks array leaves no required check, solo-go-bound included"
  _ba_mut T11em 's@solo-agent) _brp_ea=true; _brp_co=false; _brp_rc=0;@solo-agent) _brp_ea=true; _brp_co=false; _brp_rc=1;@' _f_t11e "a solo-agent payload that keeps the review count at 1 locks the agent out"
  _ba_cell T13 _f_t13 "the team and solo payloads are byte-equal to their frozen literals"
  _ba_mut T13m 's@team) _brp_ea=true; _brp_co=true; _brp_rc=1;@team) _brp_ea=true; _brp_co=true; _brp_rc=0;@' _f_t13 "a team payload with count 0 drifts from its literal"
  _ba_cell T13b _f_t13b "--replace --team reads nothing from the repository's files (no contents call) and cannot reach a PUT"
  _ba_mut T13bm 's@^ *\[ "\$TEAM" = 1 \] || ba_pick_profile$@  ba_pick_profile@' _f_t13b "a picker that also runs for --team reads the forge for it"
  _ba_rel_rows() {   # the shared reader battery: <dial|-> <CLAUDE.md|-> <expected solo|team>, one row per call to the callback $1
    "$1" 'MERGE_RELATIONSHIP=solo' - solo
    "$1" - - team
    "$1" 'MERGE_RELATIONSHIP=team' - team
    "$1" 'MERGE_RELATIONSHIP=soloish' - team
    "$1" 'MERGE_RELATIONSHIP=solo' '- **Governance** (§ solo/team): team — x' team
    "$1" 'MERGE_RELATIONSHIP=solo' '- **Governance** (§ solo/team): solo — x' solo
    "$1" 'MERGE_RELATIONSHIP=solo # note' - solo
    "$1" "$(printf 'MERGE_RELATIONSHIP=solo\nMERGE_RELATIONSHIP=team')" - team
    "$1" 'MERGE_RELATIONSHIP="solo"' - solo
    "$1" 'MERGE_RELATIONSHIP=solo' "$(printf -- '- **Governance** (§ solo/team): solo\n- **Governance** (§ solo/team): team')" team
    "$1" 'MERGE_RELATIONSHIP=solo' LINK team
  }
  _ba_row_a() {   # in-process: ba_rel_from_text against the expected word (LINK: a CLAUDE.md that is not a regular file reads rc 2)
    _bra=0; _brc=0; if [ "$1" = - ]; then _bra=1; fi; if [ "$2" = - ]; then _brc=1; fi; if [ "$2" = LINK ]; then _brc=2; fi
    if [ "$(ba_rel_from_text "$_bra" "$1" "$_brc" "$2")" != "$3" ]; then _rowbad="$_rowbad [$1|$2 want $3]"; fi
  }
  _ba_row_b() {   # the verb's own reader (promotion-verify.sh go-bound reads `na` exactly when the base is not solo) against the same word
    _brg="$_bf/rel-$_rown"; _rown=$((_rown + 1)); rm -rf "$_brg"; mkdir -p "$_brg"
    ( cd "$_brg" && git init -q && git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m base \
        && if [ "$1" != - ]; then mkdir -p .kit && printf '%s\n' "$1" > .kit/dials.conf && git add .kit/dials.conf; fi \
        && if [ "$2" = LINK ]; then ln -s elsewhere CLAUDE.md && git add CLAUDE.md; elif [ "$2" != - ]; then printf '%s\n' "$2" > CLAUDE.md && git add CLAUDE.md; fi \
        && git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m rel \
        && git update-ref refs/kit/solo-go-default HEAD ) >/dev/null 2>&1
    _brs=$(git -C "$_brg" rev-parse HEAD 2>/dev/null) || _brs=""
    _brx=$(cd "$(dirname "$0")" && pwd)/promotion-verify.sh
    _brv=$(cd "$_brg" && sh "$_brx" go-bound --approved-sha "$_brs" --pr 7 --base-ref main --default-branch main 2>/dev/null) || _brv=""
    if [ "$_brv" = "go-bound: na" ]; then _brw=team; else _brw=solo; fi
    if [ "$_brw" != "$3" ]; then _rowbad="$_rowbad [verb $1|$2 gave $_brw, want $3]"; fi
  }
  _t14_quiet=0
  _f_t14() {   # any disagreement is a failure, and so is a battery that did not run all its rows (a vacuous pass)
    _rowbad=""; _rown=0; _ba_rel_rows _ba_row_a; _ba_rel_rows _ba_row_b
    if [ "$_rown" != 11 ]; then _rowbad="$_rowbad [only $_rown verb rows ran]"; fi
    if [ -n "$_rowbad" ] && [ "$_t14_quiet" = 0 ]; then echo "selftest NOTE: T14 rows that disagree:$_rowbad"; fi
    [ -z "$_rowbad" ]
  }
  _t14m() {   # run the battery against a sed copy's ba_rel_from_text, then put the real one back
    _bmf="$_bf/relfn-real.sh"; sed -n '/^ba_rel_from_text() {$/,/^}$/p' "$0" > "$_bmf"
    _bmm="$_bf/relfn-mut.sh"; sed -n '/^ba_rel_from_text() {$/,/^}$/p' "$0" | sed "$1" > "$_bmm"
    if cmp -s "$_bmf" "$_bmm" || [ ! -s "$_bmf" ]; then echo "selftest FAIL: T14m: the mutant changed nothing"; st=1; return 0; fi
    # shellcheck source=/dev/null  # a function file this cell just wrote
    . "$_bmm"
    _t14_quiet=1
    if _f_t14; then echo "selftest FAIL: T14m: $2 -- the mutant SURVIVED"; st=1; else echo "selftest PASS: T14m: $2 (the mutant is killed)"; fi
    _t14_quiet=0
    # shellcheck source=/dev/null  # the real function, put back
    . "$_bmf"
  }
  _ba_cell T14 _f_t14 "reader parity: ba_rel_from_text and the verb's own reader agree with one battery of dial and Governance rows"
  _t14m 's@^  \[ "\$_brt_val" = solo \] || { echo team; return 0; }$@  [ "$_brt_val" = solo ] || [ "$_brt_val" = team ] || { echo team; return 0; }@' "a reader that lets MERGE_RELATIONSHIP=team fall through reads solo"
  _t14m 's@^  if \[ "\$3" != 0 \] && \[ "\$3" != 1 \]; then echo team; return 0; fi$@  :@' "a reader that treats a non-regular CLAUDE.md as no Governance line reads solo"
  _f_t14b() {   # --replace without a terminal discloses the solo-agent values AND the ceiling, then stops (ABORT with no tty, or the prompt's own abort with one), with no PUT
    _ba_fx "$1" "$_SGD" - "$_SGR" "$_SGC" "$_SGP"; _ba_run "$1" --replace
    printf '%s\n' "$_bo" | grep -qF 'SOLO-AGENT profile' && printf '%s\n' "$_bo" | grep -qF 'enforce_admins:true' \
      && printf '%s\n' "$_bo" | grep -qF 'required_approving_review_count:0' && printf '%s\n' "$_bo" | grep -qF 'require_last_push_approval:false' \
      && printf '%s\n' "$_bo" | grep -qF 'solo-go-bound now reads your recorded GO in place of an approval' \
      && printf '%s\n' "$_bo" | grep -qF 'self-asserted and a note the agent records satisfies it' \
      && printf '%s\n' "$_bo" | grep -qF 'a fabricated GO is not caught server-side' && printf '%s\n' "$_bo" | grep -qF 'an admin can still edit protection' \
      && ! printf '%s\n' "$_bo" | grep -qF 'no admin can bypass' \
      && ! grep -qF -e '-X PUT' "$_bf/$1/log"   # nothing after the prompt is asserted: with a tty present the prompt's own write/read decides the exit, and that is ambient
  }
  _ba_cell T14b _f_t14b "--replace on a solo-agent target discloses the values, the swap and the ceiling, and reaches no PUT"
  _ba_mut T14bm '/solo-go-bound now reads your recorded GO/d' _f_t14b "a confirmation without the swap sentence hides what the check now stands in for"
  _ba_mut T14cm '/self-asserted and a note the agent records satisfies it/d' _f_t14b "a confirmation without the ceiling hides that a recorded note is the whole check"
  # T16 (SWAS-901 R3-3): declaration-reader parity. The picker's ad_read_declaration, the verifier's read_declaration and the verb's pv_gb_declared
  # (through go-bound: `na` exactly when the base is not solo and solo-go-bound is NOT declared) must all read the FIRST fenced block only.
  _bpx="$(cd "$(dirname "$0")/.." && pwd)/conformance/branch-protection.sh"; _bpfn="$_bf/bpfn.sh"
  sed -n '/^RD_MAX_LINES=/p;/^valid_context_name() {$/,/^}$/p;/^read_declaration() {$/,/^}$/p' "$_bpx" > "$_bpfn" 2>/dev/null || true
  _dc_rows() {   # <callback>: a declaration text and whether it declares solo-go-bound
    "$1" "$(printf '```\nci\n```\n\n```\nsolo-go-bound\n```')" no
    "$1" "$(printf '```\nci\nsolo-go-bound\n```\n\n```\nother\n```')" yes
  }
  _dc_note() { _dcn=$((_dcn + 1)); if [ "$1" != "$2" ]; then _dcbad="$_dcbad [$3: want $2, got $1]"; fi; }   # <got> <want> <reader>
  _dc_a() {   # the picker's reader, in-process
    printf '%s\n' "$1" > "$_bf/dc-a.md"; ad_read_declaration "$_bf/dc-a.md"
    if printf '%s\n' $AD_LIST | grep -qxF solo-go-bound; then _dcw=yes; else _dcw=no; fi; _dc_note "$_dcw" "$2" picker
  }
  _dc_b() {   # the verifier's reader, sourced from its own file into a subshell
    printf '%s\n' "$1" > "$_bf/dc-b.md"
    # shellcheck source=/dev/null  # the verifier's three functions, extracted above
    _dcw=$( ( . "$_bpfn"; read_declaration "$_bf/dc-b.md"; if printf '%s\n' $RD_LIST | grep -qxF solo-go-bound; then echo yes; else echo no; fi ) 2>/dev/null ) || _dcw=""
    _dc_note "$_dcw" "$2" verifier
  }
  _dc_c() {   # the verb's reader, through go-bound against a base commit that carries that REQUIRED-CHECKS.md and no solo dial
    _dcg="$_bf/dc-c"; rm -rf "$_dcg"; mkdir -p "$_dcg"; printf '%s\n' "$1" > "$_dcg/REQUIRED-CHECKS.md"
    ( cd "$_dcg" && git init -q && git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m base \
        && git add REQUIRED-CHECKS.md && git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m rc \
        && git update-ref refs/kit/solo-go-default HEAD ) >/dev/null 2>&1
    _dcs=$(git -C "$_dcg" rev-parse HEAD 2>/dev/null) || _dcs=""
    _dcx=$(cd "$(dirname "$0")" && pwd)/promotion-verify.sh
    _dcv=$(cd "$_dcg" && sh "$_dcx" go-bound --approved-sha "$_dcs" --pr 7 --base-ref main --default-branch main 2>/dev/null) || _dcv=""
    if [ "$_dcv" = "go-bound: na" ]; then _dcw=no; else _dcw=yes; fi; _dc_note "$_dcw" "$2" verb
  }
  _f_t16() {   # all three readers agree with the expected answer on every row, and every reader ran on every row
    _dcbad=""; _dcn=0; _dc_rows _dc_a; _dc_rows _dc_b; _dc_rows _dc_c
    if [ "$_dcn" != 6 ]; then _dcbad="$_dcbad [only $_dcn reads ran]"; fi
    if [ -n "$_dcbad" ] && [ "$_t14_quiet" = 0 ]; then echo "selftest NOTE: T16 readers that disagree:$_dcbad"; fi
    [ -z "$_dcbad" ]
  }
  _t16m() {   # run the battery against a sed copy's ad_read_declaration, then put the real one back
    _dmf="$_bf/adfn-real.sh"; sed -n '/^ad_read_declaration() {$/,/^}$/p' "$0" > "$_dmf"
    _dmm="$_bf/adfn-mut.sh"; sed "$1" "$_dmf" > "$_dmm"
    if cmp -s "$_dmf" "$_dmm" || [ ! -s "$_dmf" ]; then echo "selftest FAIL: T16m: the mutant changed nothing"; st=1; return 0; fi
    # shellcheck source=/dev/null  # a function file this cell just wrote
    . "$_dmm"
    _t14_quiet=1
    if _f_t16; then echo "selftest FAIL: T16m: $2 -- the mutant SURVIVED"; st=1; else echo "selftest PASS: T16m: $2 (the mutant is killed)"; fi
    _t14_quiet=0
    # shellcheck source=/dev/null  # the real function, put back
    . "$_dmf"
  }
  _ba_cell T16 _f_t16 "declaration-reader parity: the picker, the verifier and the verb all read the first fenced block only"
  _t16m 's@else _ad_in=0; _ad_done=1; fi@else _ad_in=0; fi@' "a picker reader that reads every block takes a second block's solo-go-bound"
  rm -rf "$_bf" 2>/dev/null || true

  [ "$st" = "0" ] && echo "branch-protection-apply --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) validate_args; if [ "$PRINT_PARSED" = 1 ]; then print_parsed; fi; if [ -n "$PRINT_PAYLOAD" ]; then print_payload; fi; main ;;
esac
