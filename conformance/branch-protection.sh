#!/bin/sh
# branch-protection.sh — verify `main` is actually protected on the remote, AND that the required
# status-check CONTEXTS match what REQUIRED-CHECKS.md declares (DEVELOPMENT-STANDARDS.md §14 /
# DEVELOPMENT-PROCESS.md §12). Split at the credential seam (B4):
#   OFFLINE leg (--declared-only [FILE]): parses REQUIRED-CHECKS.md — no `gh`, no network. Registered
#     in verify.sh and swept by non-vacuity.sh.
#   LIVE leg (default, no flag): the three-state remote check below. It asserts the REVIEW
#     REQUIREMENT IS REAL — `required_pull_request_reviews.required_approving_review_count >= 1`, not
#     merely that the settings block exists (an empty block requires nothing). That number is what
#     blocks an unratified control-plane merge, and since 2026-08-28 the `control-plane-ratification`
#     check renders WAITING as GREEN because of it (RATIFICATION-WAITING-IS-GREEN) — so this gate and
#     that rendering are one control, and the count is checked here or nowhere. It ALSO compares the
#     live `required_status_checks.contexts` against the declaration: a declared-but-unbound context FAILs
#     by name; a live-but-undeclared context is an ADVISORY (never fatal, never buries the existing
#     code-owner ADVISORY below it); no declaration file present -> behaves exactly as before
#     (byte-compatible rc for inception-done's --raw consumption).
#     PROTECTION-TEAM-PROFILE (2026-10-03): it ALSO prints one `settings:` line on every 200 —
#     `settings: enforce_admins=<true|false> code_owner_reviews=<true|false> approvals=<n|absent>
#     last_push=<true|false> dismiss_stale=<true|false> merge_methods=<squash-only|squash,merge,rebase|…|unknown>`
#     — so a solo→team flip is PROVEN by the output, not assumed from a UI click; and a `governance:` line
#     naming the mode this tree DECLARES (CLAUDE.md's `**Governance** (§ solo/team): <mode>` line, read
#     strictly: team | solo | undeclared). When the tree declares TEAM, the live leg FAILs — naming the
#     setting and the cure `sh scripts/branch-protection-apply.sh --replace --team` — if enforce_admins is
#     not true, require_code_owner_reviews is not true, or the merge methods are readable and not
#     squash-only. Merge methods UNREADABLE with the token on a team tree (the CI PAT cannot read them,
#     measured) are a loud ADVISORY — the squash-only pin is UNVERIFIED on <repo> — never a red, so a team
#     adopter's CI is not red on every PR; the settings line still says merge_methods=unknown. A solo or undeclared tree
#     keeps today's verdicts (the settings line is informational; non-squash merge methods are an
#     ADVISORY). A CODEOWNERS login with only a PENDING invitation is a WARN (their review can never
#     satisfy code-owner review); unreadable invitations print `invitations: not readable with this
#     token`. --declared-only and the offline leg are unchanged.
# THREE-STATE contract (the live leg):
#   exit 0  — verified protected (PR reviews + status checks required, declared contexts all bound)
#   exit 1  — verified NOT protected / a required setting or a declared context missing (FAIL)
#   exit 2  — COULD NOT VERIFY (no gh, unauthenticated, or no GitHub remote) — NOT a pass.
# A silent pass when unverifiable is false assurance; this returns a distinct status.
# Escalation: in CI (CI env set) or with --require, "could not verify" becomes exit 1 —
# in a gate the check MUST be runnable. Requires `gh` authenticated to verify.
# Guardrails: --raw returns the un-escalated three-state (0/1/2), overriding ONLY the CI-triggered
#   auto-escalation below (the `[ "$RAW" = 0 ]` line) — an explicit --require passed alongside --raw
#   still escalates (that is NOT overridden by --raw; only the ambient-CI auto-escalation is), so a
#   policy-applying caller (inception-done) can tell "unverifiable" (2) from "verified-unprotected" (1).
#   usage: sh conformance/branch-protection.sh [BRANCH] [--require] [--raw]
#          sh conformance/branch-protection.sh --declared-only [FILE]   (offline; no gh; no network)
#          sh conformance/branch-protection.sh --selftest
# NOTE (T4-B1 -> REQUIRED-CONTEXT-SET-LOCK, 2026-08-28): the LIVE leg is NOT in verify.sh (it needs a
# token that can read protection, which the least-privilege CI token cannot). Since 2026-08-28 it RUNS
# ON EVERY PR AND WEEKLY in .github/workflows/branch-protection-live.yml under a fine-grained
# Administration:read-only PAT (secret KIT_PROTECTION_READ), as required context `branch-protection-live`;
# secret absent/expired -> rc 2 -> --require -> RED, never a pass. The OFFLINE --declared-only leg IS
# registered in verify.sh — declaration integrity needs no creds.
# CEILING (B4): detection, not prevention — an admin who removes a bound context can also edit the
# declaration; real prevention is org rulesets / IaC (Terraform's github_branch_protection resource,
# named again in scripts/branch-protection-apply.sh). Continuous DETECTION since 2026-08-28: an unbound
# or renamed context reds the next PR before it merges; nothing here can stop the unbinding itself
# (approach C in the design is the ruleset that would). `enforce_admins:false`, measured live: every required context
# is admin-bypassable by the kit's own prescribed solo merge path (`gh pr merge --admin`). The
# offline leg proves declaration INTEGRITY, never forge state. The apply script binds contexts; it
# cannot prevent later unbinding.
# GH ENV CONTAINMENT (B4 fix round 1, SEC M-3): every `gh` call below strips GH_HOST, GH_REPO,
# GH_ENTERPRISE_TOKEN, GH_CONFIG_DIR from the subshell before invoking `gh` — a hostile value in any
# of those could redirect the API host, retarget the mutation at a different repo, or swap the
# config/creds gh reads. GH_TOKEN is left untouched and honored (the operator's real credential).
# CONTEXT-NAME CHARSET (B4 fix round 1, SEC C-1/H-2/L-2..L-4): every parsed declared context name
# must match ^[A-Za-z0-9][A-Za-z0-9._/-]*$ with length<=100, checked identically here and in
# scripts/branch-protection-apply.sh (see valid_context_name() in both — item 9's selftest cell
# proves the two copies never drift). This is the ONLY charset that can never carry a JSON metachar,
# a shell case/glob metachar, or whitespace — closing the string-concat JSON-injection class at the
# parser, not just at the body builder, and closing the `*`-glob / word-split class `set -f` (below)
# closes structurally. GitHub context names containing spaces are NOT declarable in v1: fail-closed
# with a message naming the offending line, never a silent split (see the FAIL text below).
set -eu
set -f   # noglob — every `for x in $LIST` expansion in this file is data, never a filesystem glob;
         # a declared or live context containing `*`/`?`/`[` must never turn into a directory listing.

# REPO_ROOT — resolved once from $0, used to (a) find the DEFAULT REQUIRED-CHECKS.md regardless of
# the caller's CWD (SEC H-3: an explicit --declared-only FILE argument stays caller-relative; only
# the unspecified default resolves here) and (b) detect a kit-shaped tree for the presence rule in
# declared_only() (SEC H-4). Falls back to "." if resolution fails (never fatal here).
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH
# cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || REPO_ROOT=.

# is_kit_tree — DETECTED trigger, mirrors the OR-of-markers kit-self detector in
# meta-control-fresh.sh / adopter-export-wired.sh (un-spoofable: golden-path.yml is control-plane +
# export-ignored). NOT a declared-mode read.
is_kit_tree() {
  [ -f "$REPO_ROOT/docs/ROADMAP-KIT.md" ] || [ -f "$REPO_ROOT/.github/workflows/golden-path.yml" ]
}

# resolve_backend (§backend seam, TBG-*) is sourced, never re-derived (RD-4: one resolver, not two).
[ -f "$REPO_ROOT/conformance/backlog-lib.sh" ] && . "$REPO_ROOT/conformance/backlog-lib.sh"

# vacuous_tracker_check <tree-dir> — RD-4 (design A1 §9): a REQUIRED-CHECKS.md declaring the exact
# active line `tracker-board-gates` while <tree-dir>'s resolved backlog backend is `md` (or the tree
# carries no .kit/tracker.conf at all) would be a required context that is ALWAYS GREEN — the
# trusted job (profiles/adopter-tracker-gates.yml `resolve` step) exits/skips before it ever runs on
# an md tree, so a branch-protection rule requiring it blocks nothing. Reads $RD_LIST, already set by
# the caller's read_declaration() — this is never a second parser. Prints the FAIL line and returns 1
# on the vacuous shape; returns 0 (silent) otherwise, INCLUDING when `tracker-board-gates` is absent
# from RD_LIST (a blanket ban on the name is not the point — only the always-green shape is).
vacuous_tracker_check() {
  _vtc_tree=$1
  case " $RD_LIST " in
    *' tracker-board-gates '*) : ;;
    *) return 0 ;;
  esac
  # RT5-Q3: seam_backend must exist after sourcing the lib above — fail closed (never silently
  # pass a check this function could not actually run) if the source failed or the function is
  # missing for any other reason.
  if ! command -v seam_backend >/dev/null 2>&1; then
    printf '%s\n' "FAIL: tracker-board-gates is declared required but this tree's backlog backend is md — the trusted job skips on md, so the context would be always-green; remove it from REQUIRED-CHECKS.md and from branch protection (see RUNBOOK, reverting a tracker)"
    return 1
  fi
  # RT5-Q1: mirror the trusted job's OWN skip rule (profiles/adopter-tracker-gates.yml `resolve`
  # step) rather than re-deriving it from CLAUDE.md alone — the job skips on the CONF's `backend=`,
  # read via the tree's OWN scripts/tracker-conf.sh, not on CLAUDE.md's declaration. Vacuous when
  # ANY of: the conf is absent; the conf's own reader returns `md` OR fails to run at all (fail
  # closed, mirroring the job's own conf-absent/skip path); OR CLAUDE.md itself resolves to `md`
  # (a second, independent signal — CLAUDE.md is what a human/agent reads as the declared backend).
  # Read through the seam's public accessor (seam_backend, backlog-lib.sh) rather than calling
  # resolve_backend directly — a pure wrapper, same output, but keeps every backend read routed
  # through the one seam (board-parser-drift.sh's DERIVED-CONSUMER(RESOLVE-BACKEND) check).
  _vtc_conf="$_vtc_tree/.kit/tracker.conf"
  _vtc_vacuous=0
  if [ ! -f "$_vtc_conf" ]; then
    _vtc_vacuous=1
  elif [ -f "$_vtc_tree/scripts/tracker-conf.sh" ]; then
    if _vtc_confbackend=$(sh "$_vtc_tree/scripts/tracker-conf.sh" get backend "$_vtc_conf" 2>/dev/null); then
      [ "$_vtc_confbackend" = "md" ] && _vtc_vacuous=1
    else
      _vtc_vacuous=1
    fi
  else
    _vtc_vacuous=1
  fi
  _vtc_backend=$(SEAM_ROOT="$_vtc_tree" seam_backend 2>/dev/null || true)
  [ "$_vtc_backend" = "md" ] && _vtc_vacuous=1
  if [ "$_vtc_vacuous" = 1 ]; then
    printf '%s\n' "FAIL: tracker-board-gates is declared required but this tree's backlog backend is md — the trusted job skips on md, so the context would be always-green; remove it from REQUIRED-CHECKS.md and from branch protection (see RUNBOOK, reverting a tracker)"
    return 1
  fi
  return 0
}

# ── PROTECTION-TEAM-PROFILE: state classify() reads. run() assigns every one of these itself; they are
# reset here UNCONDITIONALLY so an ambient environment variable can never pre-set a governance mode,
# a merge-method read or an invitation state (an env var must never be able to force a pass).
GOV_MODE=undeclared; GOV_NOTE=""; MERGE_METHODS=unknown; INVITES_STATE=""; PENDING_OWNERS=""

# read_governance <CLAUDE.md> — set GOV_MODE (and GOV_NOTE) from the tree's `**Governance** (§ solo/team): <mode>`
# FIELD lines (scripts/incept.sh stamps one; the value is followed by the template's prose). Only ANCHORED field
# lines count — a bullet/bare line that BEGINS with the field — so a prose mention of the phrase is ignored. The
# value's FIRST word must be exactly `team` or `solo`. One field line: that mode, else undeclared (absent file,
# no field, the unfilled `[solo / team]` placeholder, another case or word). More than one field line is
# AMBIGUOUS: `team` if ANY says team (fail toward the stricter reading), else undeclared; GOV_NOTE says so, so
# the choice is visible on the governance: line.
GOV_FIELD='^[-*+ ]*\*\*Governance\*\* (§ solo/team):'
read_governance() {
  GOV_MODE=undeclared; GOV_NOTE=""
  [ -f "$1" ] || return 0
  _rg_n=$(grep -c -e "$GOV_FIELD" "$1" || true)
  [ "$_rg_n" -ge 1 ] || return 0
  _rg_vals=$(sed -n 's#^[-*+ ]*\*\*Governance\*\* (§ solo/team): \([^ ]*\).*$#\1#p' "$1")
  [ "$_rg_n" = 1 ] || GOV_NOTE="ambiguous: $_rg_n field lines"
  for _rg_v in $_rg_vals; do
    [ "$_rg_v" = team ] && { GOV_MODE=team; return 0; }
  done
  [ "$_rg_n" = 1 ] && [ "$_rg_vals" = solo ] && GOV_MODE=solo
  return 0
}

# MM_JQ — reads the three TOP-LEVEL merge fields with gh's built-in jq (S-1). A text scan of the repo JSON
# took the first occurrence of each key, which a `template_repository` object (listed BEFORE the top-level
# keys, repeating them) would shadow: a false squash-only. jq's `.allow_*` is the top-level field, always.
MM_JQ='[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge]|map(tostring)|join(" ")'

# parse_merge_methods <"true false false"-style output of MM_JQ> -> squash-only | the allowed methods
# (comma-joined, squash,merge,rebase order) | unknown (not exactly three true/false words — null/absent
# fields, an unreadable token, an empty read). Duplicated in scripts/branch-protection-apply.sh (that script
# is self-contained); this file's selftest diffs the two copies.
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

# valid_branch <name> — refuses empty, a leading `-`, `..`, and any of ? # % * [ \ whitespace/control bytes:
# the name is interpolated into the protection path. Duplicated in scripts/branch-protection-apply.sh.
valid_branch() {
  case "$1" in ""|-*|*..*|*[\?#%*\[\\]*|*[[:space:][:cntrl:]]*) return 1 ;; esac
  return 0
}

# bp_flag <whitespace-stripped body> <key> -> true | false (absent reads as false, exactly like the
# review-flag arms: a missing key is not "on").
bp_flag() {
  if printf '%s' "$1" | grep -q "\"$2\":true"; then printf '%s' true; else printf '%s' false; fi
}

# bp_enforce_admins <whitespace-stripped body> -> true | false. GitHub nests it as
# "enforce_admins":{"url":…,"enabled":<bool>}; the bare "enforce_admins":<bool> shape is read too.
bp_enforce_admins() {
  _bea=$(printf '%s' "$1" | sed -n 's/.*"enforce_admins":{[^}]*"enabled":\([a-z]*\).*/\1/p')
  [ -n "$_bea" ] || _bea=$(printf '%s' "$1" | sed -n 's/.*"enforce_admins":\([a-z]*\).*/\1/p')
  if [ "$_bea" = true ]; then printf '%s' true; else printf '%s' false; fi
}

# co_logins <dir> — the @login owners named in the tree's CODEOWNERS (one per line, sorted, unique);
# `@org/team` handles are skipped (an invitation can only be pending for an individual account).
co_logins() {
  for _col_f in "$1/.github/CODEOWNERS" "$1/CODEOWNERS" "$1/docs/CODEOWNERS"; do
    [ -f "$_col_f" ] || continue
    sed 's/#.*//' "$_col_f" | tr -s ' \t' '\n\n' | grep '^@[A-Za-z0-9-]*$' | sed 's/^@//'
  done | sort -u
}

REQUIRE="${REQUIRE:-0}"
RAW=0
BRANCH=main
DECLARED_ONLY=0
DECLARATION="REQUIRED-CHECKS.md"
DECL_EXPLICIT=0
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --raw) RAW=1 ;;   # emit the un-escalated three-state (0/1/2), overriding ONLY the ambient-CI auto-escalation below; an explicit --require alongside --raw still escalates
    --declared-only) DECLARED_ONLY=1 ;;
    --selftest) ;;  # dispatched below
    -*) printf '%s\n' "usage: branch-protection.sh [BRANCH] [--require] [--raw] | --declared-only [FILE] | --selftest" >&2; exit 2 ;;
    *) if [ "$DECLARED_ONLY" = 1 ]; then DECLARATION="$a"; DECL_EXPLICIT=1; else BRANCH="$a"; fi ;;
  esac
done
valid_branch "$BRANCH" || { printf '%s\n' "branch-protection.sh: invalid branch name (empty, '..', whitespace, or one of ? # % * [ backslash is refused)" >&2; exit 2; }
[ "$DECL_EXPLICIT" = 1 ] || DECLARATION="$REPO_ROOT/REQUIRED-CHECKS.md"
[ "$RAW" = 0 ] && [ -n "${CI:-}" ] && REQUIRE=1   # CI makes the gate runnable — UNLESS --raw asked for the raw state

# Unverifiable: exit 2 normally; exit 1 (FAIL) under CI/--require (a gate must be runnable).
unverifiable() {
  if [ "$REQUIRE" = "1" ]; then
    printf '%s\n' "FAIL: branch-protection could not verify ($1) and verification is required (CI/--require)."
    exit 1
  fi
  printf '%s\n' "UNVERIFIED: $1 — run in CI or authenticate gh. (NOT a pass.)"
  exit 2
}

have_gh() {
  [ "${BP_FORCE_NO_GH:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1
}

# valid_context_name <name> -> 0 if it matches ^[A-Za-z0-9][A-Za-z0-9._/-]*$ and length<=100, else 1.
# This exact charset can never contain a quote/brace/colon/comma (JSON injection), a glob metachar
# (`*`, `?`, `[`), a leading `-` (a case pattern or a CLI flag could notice), or whitespace (breaks
# "for x in $LIST" word-splitting and printf sweeps). Duplicated verbatim in
# scripts/branch-protection-apply.sh (D4: that script is self-contained) — a selftest cell (below)
# proves the two copies stay identical.
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

RD_MAX_LINES=100

# read_declaration <file> — parse the fenced ```...``` block: one context per line. Stops at the
# FIRST block's CLOSE (REV M1) — a second fence-open afterward is ignored, never merged into the
# context set (the measured bug: a usage-example block read as more declared contexts). A
# `#`-prefixed line is a comment/conditional (ignored). A line containing an angle-bracket
# placeholder (e.g. <your-check-name>) marks the file PRISTINE — neither an active context nor, on
# its own, an error. Every candidate line is charset-validated (valid_context_name, above) and the
# block is capped at RD_MAX_LINES candidate lines (SEC L-2: a DoS bound on parse cost — a huge
# declaration can no longer inflate iteration cost downstream). POSIX only (no jq): this side is our
# own trivially-greppable format (Δ7).
# Sets on return (never exits): RD_LIST (space-joined VALID, non-duplicate active contexts, may be
# empty), RD_PLACEHOLDER (0 or count), RD_DUP (0 or count), RD_DUP_NAME (first duplicate, if any),
# RD_INVALID (0 or count of charset-rejected candidate lines), RD_INVALID_NAME (the first rejected
# line, VERBATIM — always named in the FAIL message, never silently dropped), RD_TOOMANY (0 or 1:
# the RD_MAX_LINES candidate-line cap was hit).
read_declaration() {
  _rdf=$1
  RD_LIST=""; RD_PLACEHOLDER=0; RD_DUP=0; RD_DUP_NAME=""
  RD_INVALID=0; RD_INVALID_NAME=""; RD_TOOMANY=0
  _rd_in=0; _rd_done=0; _rd_n=0
  while IFS= read -r _rdl || [ -n "$_rdl" ]; do
    case "$_rdl" in
      '```'*)
        [ "$_rd_done" = 1 ] && continue   # a second fence-open after the first block's close is IGNORED
        if [ "$_rd_in" = 0 ]; then _rd_in=1; else _rd_in=0; _rd_done=1; fi
        continue ;;
    esac
    [ "$_rd_in" = 1 ] || continue
    _rdt=$(printf '%s' "$_rdl" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$_rdt" ] && continue
    case "$_rdt" in
      '#'*) continue ;;
    esac
    _rd_n=$((_rd_n + 1))
    if [ "$_rd_n" -gt "$RD_MAX_LINES" ]; then RD_TOOMANY=1; continue; fi
    case "$_rdt" in
      *'<'*'>'*) RD_PLACEHOLDER=$((RD_PLACEHOLDER + 1)); continue ;;
    esac
    if ! valid_context_name "$_rdt"; then
      RD_INVALID=$((RD_INVALID + 1))
      # R-3: sanitize BEFORE it is ever captured, not at each print site — every FAIL/ADVISORY
      # diagnostic that names RD_INVALID_NAME (declared_only() and classify()'s skip-ladder) then
      # inherits the sanitized form for free. A raw control byte (e.g. ESC) in an offending line
      # was measured erasing the FAIL prefix on ANSI terminals; strip control bytes and cap length.
      [ -n "$RD_INVALID_NAME" ] || RD_INVALID_NAME=$(printf '%s' "$_rdt" | tr -d '[:cntrl:]' | cut -c1-80)
      continue
    fi
    if [ -n "$RD_LIST" ] && printf '%s\n' $RD_LIST | grep -qxF -e "$_rdt"; then
      RD_DUP=$((RD_DUP + 1)); [ -n "$RD_DUP_NAME" ] || RD_DUP_NAME=$_rdt
    else
      RD_LIST="$RD_LIST $_rdt"
    fi
  done < "$_rdf"
  RD_LIST=$(printf '%s' "$RD_LIST" | sed 's/^ *//')
}

# extract_live_contexts <body> — one required-status-check context per line on stdout (rc always 0;
# empty stdout means none present or the body was unparsable). jq is an OPTIONAL fast path (Δ7): the
# live side is GitHub's JSON, so unlike the declaration side a hard jq dependency would add a new
# UNVERIFIED axis for adopters without it — POSIX sed/tr is the load-bearing path.
extract_live_contexts() {
  if command -v jq >/dev/null 2>&1; then
    if _elc_j=$(printf '%s' "$1" | jq -r '.required_status_checks.contexts[]?' 2>/dev/null); then
      if [ -n "$_elc_j" ]; then printf '%s\n' "$_elc_j"; return 0; fi
    fi
  fi
  printf '%s' "$1" | tr -d '\n' \
    | sed -n 's/.*"contexts"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"\{0,1\}//; s/"\{0,1\}[[:space:]]*$//' \
    | grep -v '^[[:space:]]*$' || true
  return 0
}

# declared_only — the OFFLINE declaration-integrity leg (Δ2): no gh, no network, ever. Reads
# $DECLARATION. Exit 0 = well-formed (or legitimately N/A) · 1 = FAIL (malformed declaration, or an
# absent declaration on a kit-shaped tree — SEC H-4: the kit must carry its own).
declared_only() {
  _dof="$DECLARATION"
  if [ ! -f "$_dof" ]; then
    if is_kit_tree; then
      printf '%s\n' "FAIL: $_dof not found — the kit must carry its own declaration (docs/ROADMAP-KIT.md or .github/workflows/golden-path.yml present in this tree; deleting REQUIRED-CHECKS.md can no longer green this check)"
      exit 1
    fi
    printf '%s\n' "N/A: $_dof not found in this tree — nothing declared to verify (this leg is opt-in, BACKLOG-pattern; stamp one via incept, or copy templates/REQUIRED-CHECKS-TEMPLATE.md)"
    exit 0
  fi
  read_declaration "$_dof"
  if [ "$RD_TOOMANY" != 0 ]; then
    printf '%s\n' "FAIL: $_dof declares more than $RD_MAX_LINES required-check context line(s) (cap exceeded — DoS bound)"
    exit 1
  fi
  if [ "$RD_INVALID" != 0 ]; then
    printf '%s\n' "FAIL: $_dof declares an invalid required-check context name: $RD_INVALID_NAME (must match ^[A-Za-z0-9][A-Za-z0-9._/-]*\$, length<=100 — GitHub context names containing spaces are NOT declarable in v1; rename the CI job/step to a hyphenated name and re-declare)"
    exit 1
  fi
  if [ "$RD_DUP" != 0 ]; then
    printf '%s\n' "FAIL: $_dof declares a duplicate required-check context: $RD_DUP_NAME"
    exit 1
  fi
  set -- $RD_LIST; _don=$#
  if [ "$RD_PLACEHOLDER" != 0 ] && [ "$_don" = 0 ]; then
    printf '%s\n' "N/A: $_dof is the pristine stamped template (placeholder present, no active context declared yet) — replace the placeholder with your CI's real check name(s)"
    exit 0
  fi
  if [ "$RD_PLACEHOLDER" != 0 ] && [ "$_don" -gt 0 ]; then
    printf '%s\n' "FAIL: $_dof mixes the unedited placeholder with $_don active declared context(s) — remove the placeholder line once real contexts are added"
    exit 1
  fi
  if [ "$_don" = 0 ]; then
    printf '%s\n' "FAIL: $_dof declares zero active required-check contexts (empty declaration, not the pristine template)"
    exit 1
  fi
  vacuous_tracker_check "$(dirname -- "$_dof")" || exit 1
  printf '%s\n' "OK: $_dof declares $_don required-check context(s):$RD_LIST"
  # ★ SAY WHAT THIS GREEN DOES NOT COVER (round 1, finding 2): this leg reads a FILE and cannot see the
  # live setting that blocks a merge — and that setting is load-bearing for a SIBLING check's colour.
  # A maintainer reading "OK" here must not conclude the requirement is in place.
  printf '%s\n' "NOTE: declaration integrity only. required_approving_review_count (>=1) is a LIVE-LEG check — run this script with no flag (needs gh + admin) to verify the review requirement that actually blocks an unratified control-plane merge."
  exit 0
}

# judge_team_profile <whitespace-stripped body> <approvals|absent> — PROTECTION-TEAM-PROFILE (design 2026-10-03).
# Print what was READ — always, on every 200 — so the flip from solo to team is provable from the output instead
# of assumed from a UI click; then judge it against the tree's DECLARED governance mode (CLAUDE.md, read
# strictly; absent/odd = undeclared). Absent keys read as false, exactly like the review-flag arms. Sets the
# global classify() owns: ok (1 on a FAIL).
judge_team_profile() {
  _jt_ea=$(bp_enforce_admins "$1"); _jt_co=$(bp_flag "$1" require_code_owner_reviews)
  _jt_mm=${MERGE_METHODS:-unknown}; _jt_gov=${GOV_MODE:-undeclared}
  printf '%s\n' "settings: enforce_admins=$_jt_ea code_owner_reviews=$_jt_co approvals=$2 last_push=$(bp_flag "$1" require_last_push_approval) dismiss_stale=$(bp_flag "$1" dismiss_stale_reviews) merge_methods=$_jt_mm"
  printf '%s\n' "governance: $_jt_gov (CLAUDE.md Governance line${GOV_NOTE:+; $GOV_NOTE})"
  _jt_cure="sh scripts/branch-protection-apply.sh --replace --team"
  if [ "$_jt_gov" = team ]; then
    [ "$_jt_ea" = true ] || { printf '%s\n' "FAIL: CLAUDE.md declares governance team but enforce_admins is not true on $BRANCH — an admin can still merge past every required check and review (gh pr merge --admin). Cure (an admin act; read its confirmation, it locks you out if you are alone): $_jt_cure"; ok=1; }
    [ "$_jt_co" = true ] || { printf '%s\n' "FAIL: CLAUDE.md declares governance team but require_code_owner_reviews is not true on $BRANCH — a CODEOWNER's review is not required, so builder ≠ sole reviewer does not hold on protected paths. Cure: $_jt_cure"; ok=1; }
    case "$_jt_mm" in
      squash-only) : ;;
      unknown) printf '%s\n' "ADVISORY: merge methods are not readable with this token — the squash-only pin is UNVERIFIED on ${REPO:-?} (team declaration); an admin can confirm it with sh scripts/branch-protection-apply.sh (show-only prints merge-methods: current=…)" ;;
      *) printf '%s\n' "FAIL: CLAUDE.md declares governance team but the repo's merge methods are not squash-only (allowed: $_jt_mm) on ${REPO:-?} — the kit's merge standard is squash. Cure: $_jt_cure"; ok=1 ;;
    esac
  else
    case "$_jt_mm" in
      squash-only|unknown) : ;;
      *) printf '%s\n' "ADVISORY: merge methods allowed on ${REPO:-?} are $_jt_mm — the kit's standard is squash-only; pin it with sh scripts/branch-protection-apply.sh --replace (informational on a $_jt_gov tree)." ;;
    esac
  fi
  # L 80: a CODEOWNERS login with only a PENDING invitation can never satisfy code-owner review.
  if [ "${INVITES_STATE:-}" = unreadable ]; then
    printf '%s\n' "invitations: not readable with this token"
  else
    for _jt_po in ${PENDING_OWNERS:-}; do
      printf '%s\n' "WARN: CODEOWNERS names $_jt_po but that account has only a PENDING invitation to ${REPO:-?} — their review can never satisfy code-owner review until they accept."
    done
  fi
}

# classify RC BODY — decide PASS/FAIL/UNVERIFIED from the HTTP outcome, NOT body substrings.
# Only a genuine HTTP 200 (gh exit 0) is allowed to reach the required-settings check, so a
# non-200 ERROR body that merely *names* the settings can never read as protected.
classify() {
  rc=$1; body=$2
  if [ "$rc" = "0" ]; then
    # HTTP 200: this IS the live protection config — verify the required settings are present.
    ok=0
    printf '%s' "$body" | grep -q '"required_pull_request_reviews"' || { printf '%s\n' "FAIL: required PR reviews not enabled on $BRANCH"; ok=1; }
    # ★★ THE COUNT, NOT JUST THE BLOCK (RATIFICATION-WAITING-IS-GREEN, round 1, finding 2).
    # `required_pull_request_reviews: {}` is PRESENT and requires NOTHING, and this gate green-lit it.
    # Since 2026-08-28 `control-plane-ratification` renders WAITING as GREEN precisely because this
    # count blocks server-side (DEVELOPMENT-PROCESS.md §13, THREAT-MODEL.md T6, REQUIRED-CHECKS.md all
    # name it) — a gate not checking the setting its sibling depends on is an unverified assumption.
    # No jq (this leg must run on a bare runner): strip whitespace, take the digits.
    _bp_rc_count=$(printf '%s' "$body" | tr -d ' \t\n' \
      | sed -n 's/.*"required_approving_review_count":\([0-9][0-9]*\).*/\1/p' | head -n 1)
    if [ -z "$_bp_rc_count" ]; then
      printf '%s\n' "FAIL: $BRANCH does not declare required_approving_review_count — the merge of an unratified control-plane PR is blocked by that count, and the control-plane-ratification check is GREEN while waiting BECAUSE of it (DEVELOPMENT-PROCESS.md §13). Absent, nothing blocks. Run: sh scripts/branch-protection-apply.sh --apply"; ok=1
    elif [ "$_bp_rc_count" -lt 1 ]; then
      printf '%s\n' "FAIL: $BRANCH sets required_approving_review_count=$_bp_rc_count — a review requirement of ZERO. The required_pull_request_reviews block being PRESENT means nothing on its own; with a count of 0 an unratified control-plane PR merges with a GREEN ratification check (that check explains the wait, it does not block it). Run: sh scripts/branch-protection-apply.sh --apply"; ok=1
    fi
    # ★★ THE TWO SETTINGS THAT CARRY review-lane's RETIRED ATTESTATION LEG
    # (REVIEW-LANE-WAITING-IS-GREEN, 2026-09-05). Until then `conformance/review-lane.sh` read the
    # forge's review list itself and returned WAITING — rc 1, which a CI job renders RED — until a
    # non-author approval sat on the graded head. The leg is deleted, and these two server-side
    # settings are what hold the properties it checked. THE SETTINGS ARE THE CONTROL; this arm is what
    # makes their absence visible, so absent must red exactly like false: a
    # `required_pull_request_reviews` block that merely omits a key is the shape a half-configured
    # protection rule returns, and reading "not false" as "on" would be a silent downgrade of the very
    # control that replaced a check. Same parse style as the count above — whitespace stripped, no jq,
    # because this leg must run on a bare runner.
    #
    # ⚠️ THE REMEDY IS NOT `--apply`, AND SAYING SO WOULD BE WORSE THAN SAYING NOTHING (security M-1,
    # fix round 1). `scripts/branch-protection-apply.sh --apply` POSTs to the ADDITIVE
    # `.../required_status_checks/contexts` endpoint — it adds contexts and touches no review setting,
    # so an operator following it would run a command, see it succeed, re-run this gate and still be
    # red, with nothing telling them why. The honest remedies are the admin PATCH below (one setting,
    # nothing else overwritten) or the Settings UI. `--replace` would also work, but it is a full PUT
    # that resets every other protection setting, so it is not what this line recommends. The
    # pre-existing count arms above keep their own `--apply` line: that one is about establishing
    # protection on a fresh repo, which is `--replace`'s job and their own history.
    _bp_rc_flat=$(printf '%s' "$body" | tr -d ' \t\n')
    printf '%s' "$_bp_rc_flat" | grep -q '"dismiss_stale_reviews":true' \
      || { printf '%s\n' "FAIL: $BRANCH does not set dismiss_stale_reviews to true — since REVIEW-LANE-WAITING-IS-GREEN (2026-09-05) this setting is what binds an approval to the exact head (review-lane no longer re-reads the forge to compare the approval's commit.oid). Without it an approval given before a fix push survives that push, and a tree nobody looked at merges on a review of a different tree. Fix it with the admin PATCH (NOT branch-protection-apply.sh --apply, which only adds status-check contexts): gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F dismiss_stale_reviews=true — or the Settings UI, Branches, edit the rule, 'Dismiss stale pull request approvals when new commits are pushed'."; ok=1; }
    printf '%s' "$_bp_rc_flat" | grep -q '"require_last_push_approval":true' \
      || { printf '%s\n' "FAIL: $BRANCH does not set require_last_push_approval to true — since REVIEW-LANE-WAITING-IS-GREEN (2026-09-05) this setting replaces review-lane's deleted rl_role_swap heuristic, which guessed at the role swap by matching an approver's forge login against the head commit's author/committer identity. As a server-side rule it is stronger and it is the only control left for the property: without it whoever pushed the head can approve their own push. Fix it with the admin PATCH (NOT branch-protection-apply.sh --apply, which only adds status-check contexts): gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F require_last_push_approval=true — or the Settings UI, Branches, edit the rule, 'Require approval of the most recent reviewable push'."; ok=1; }
    printf '%s' "$body" | grep -q '"required_status_checks"' || { printf '%s\n' "FAIL: required status checks not enabled on $BRANCH"; ok=1; }
    # advisory (non-fatal): CODEOWNER-review enforcement is recommended but not required by this gate
    # (an adopter who never fills CODEOWNERS can leave builder=reviewer paths under-covered — §12).
    [ "${GOV_MODE:-undeclared}" = team ] || printf '%s' "$body" | grep -q '"require_code_owner_reviews":[[:space:]]*true' || printf '%s\n' "ADVISORY: require_code_owner_reviews is not enabled on $BRANCH — CODEOWNER review is recommended so builder ≠ sole reviewer holds on protected paths (DEVELOPMENT-PROCESS.md §12)."
    judge_team_profile "$_bp_rc_flat" "${_bp_rc_count:-absent}"
    # Declared-contexts comparison (B4, D1). SEC H-3/REV M3: this never skips SILENTLY any more — an
    # absent declaration, a pristine template, or a malformed one (dup/placeholder-mixed/bad-charset/
    # too-many) always prints a one-line disclosure; a malformed declaration ESCALATES to FAIL under
    # CI/--require (a gate must be runnable, and a malformed declaration is not "nothing to check").
    if [ ! -f "$DECLARATION" ]; then
      printf '%s\n' "ADVISORY: declared-context comparison SKIPPED (no $DECLARATION in this tree)"
    else
      read_declaration "$DECLARATION"
      # RD-4: a declared-but-vacuous tracker-board-gates FAILs here unconditionally (never advisory,
      # never gated by --require) — the live leg must surface it exactly like the offline leg does.
      vacuous_tracker_check "$(dirname -- "$DECLARATION")" || ok=1
      set -- $RD_LIST; _cls_don=$#
      _cls_skip=""; _cls_malformed=0
      if [ "$RD_TOOMANY" != 0 ]; then
        _cls_skip="$DECLARATION exceeds the $RD_MAX_LINES declared-line cap"; _cls_malformed=1
      elif [ "$RD_INVALID" != 0 ]; then
        _cls_skip="$DECLARATION declares an invalid required-check context name: $RD_INVALID_NAME"; _cls_malformed=1
      elif [ "$RD_DUP" != 0 ]; then
        _cls_skip="$DECLARATION declares a duplicate required-check context: $RD_DUP_NAME"; _cls_malformed=1
      elif [ "$RD_PLACEHOLDER" != 0 ] && [ "$_cls_don" -gt 0 ]; then
        _cls_skip="$DECLARATION mixes the unedited placeholder with active declared context(s)"; _cls_malformed=1
      elif [ "$RD_PLACEHOLDER" != 0 ] && [ "$_cls_don" = 0 ]; then
        _cls_skip="$DECLARATION is the pristine stamped template"; _cls_malformed=0
      elif [ "$_cls_don" = 0 ]; then
        # R-1: a declaration present, zero placeholders, zero active contexts (an empty or
        # de-fenced ```...``` block) is malformed exactly like declared_only()'s own "zero active"
        # FAIL (above) — the live leg must not silently green this by falling through to the
        # empty-RD_LIST comparison below (which would report OK, having nothing to compare).
        _cls_skip="$DECLARATION declares zero active required-check contexts"; _cls_malformed=1
      fi

      if [ -n "$_cls_skip" ]; then
        if [ "$_cls_malformed" = 1 ] && [ "$REQUIRE" = "1" ]; then
          printf '%s\n' "FAIL: declared-context comparison SKIPPED because $_cls_skip (escalated: CI/--require)"
          ok=1
        else
          printf '%s\n' "ADVISORY: declared-context comparison SKIPPED ($_cls_skip)"
        fi
      else
        _cls_live=$(extract_live_contexts "$body")
        _cls_missing=""
        for _cls_c in $RD_LIST; do
          printf '%s\n' "$_cls_live" | grep -qxF -e "$_cls_c" || _cls_missing="$_cls_missing $_cls_c"
        done
        if [ -n "$_cls_missing" ]; then
          printf '%s\n' "FAIL: required-check context(s) declared in $DECLARATION but not live on $BRANCH:$_cls_missing — run: sh scripts/branch-protection-apply.sh --apply"
          ok=1
        fi
        _cls_extra=""
        for _cls_c in $_cls_live; do
          if [ -n "$RD_LIST" ] && printf '%s\n' $RD_LIST | grep -qxF -e "$_cls_c"; then
            :
          else
            _cls_extra="$_cls_extra $_cls_c"
          fi
        done
        [ -n "$_cls_extra" ] && printf '%s\n' "ADVISORY: live status check(s) not declared in $DECLARATION (informational, never fatal):$_cls_extra"
      fi
    fi
    [ "$ok" -eq 0 ] && printf '%s\n' "OK: $BRANCH on ${REPO:-?} is protected (PR reviews + status checks required)."
    exit "$ok"
  fi
  # Non-200. A definitive "no protection" (404) is a real FAIL; anything else (403 admin-rights,
  # 401, rate-limit, empty/transient body) is NOT determinable here -> UNVERIFIED (never a pass).
  if printf '%s' "$body" | grep -q 'Branch not protected'; then
    printf '%s\n' "FAIL: $BRANCH on ${REPO:-?} has no branch protection."; exit 1
  fi
  unverifiable "protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on ${REPO:-?}"
}

# gather_team_state — the live-leg reads classify() judges beyond the protection body: the tree's declared
# governance mode, the repo's merge methods (`gh api repos/OWNER/REPO`; unknown when the token cannot read
# the three fields), and which CODEOWNERS logins have only a pending invitation (`.../invitations`;
# INVITES_STATE=unreadable when the token cannot read it). Read-only GETs; GH env containment applies.
gather_team_state() {
  read_governance "$REPO_ROOT/CLAUDE.md"
  if _gts_repo=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api "repos/$REPO" --jq "$MM_JQ" 2>/dev/null); then
    MERGE_METHODS=$(parse_merge_methods "$_gts_repo")
  else
    MERGE_METHODS=unknown
  fi
  if _gts_inv=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api --paginate "repos/$REPO/invitations" --jq '.[].invitee.login' 2>/dev/null); then
    INVITES_STATE=ok; PENDING_OWNERS=""
    for _gts_l in $(co_logins "$REPO_ROOT"); do
      if printf '%s\n' "$_gts_inv" | grep -qixF -e "$_gts_l"; then PENDING_OWNERS="$PENDING_OWNERS $_gts_l"; fi
    done
  else
    INVITES_STATE=unreadable; PENDING_OWNERS=""
  fi
}

run() {
  have_gh || unverifiable "gh not installed"
  REPO=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  [ -n "$REPO" ] || unverifiable "no GitHub repo context"
  PROT=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null) && rc=0 || rc=$?
  [ "$rc" = 0 ] && gather_team_state
  classify "$rc" "$PROT"
}

selftest() {
  st=0
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  out=$(CI= REQUIRE=0 BP_FORCE_NO_GH=1 sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ]; then echo "selftest PASS: no-gh local -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: no-gh local should be exit 2 (got $rc)"; st=1; fi
  printf '%s' "$out" | grep -q UNVERIFIED || { echo "selftest FAIL: missing UNVERIFIED message"; st=1; }
  out=$(CI=true BP_FORCE_NO_GH=1 sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: no-gh + CI -> exit 1 (FAIL escalation)"; else echo "selftest FAIL: no-gh+CI should be exit 1 (got $rc)"; st=1; fi
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  out=$(CI= BP_FORCE_NO_GH=1 sh "$0" --require 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: no-gh + --require -> exit 1"; else echo "selftest FAIL: no-gh+--require should be exit 1 (got $rc)"; st=1; fi
  out=$(CI=true BP_FORCE_NO_GH=1 sh "$0" --raw 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q UNVERIFIED && ! printf '%s' "$out" | grep -q '^usage:'; then
    echo "selftest PASS: --raw ignores CI escalation -> exit 2 (UNVERIFIED)"
  else
    echo "selftest FAIL: --raw under CI should be UNVERIFIED exit 2 (got rc=$rc, out=$out)"; st=1
  fi
  # HTTP-status-based parse, tested IN-PROCESS via classify() (no production-reachable stub
  # seam — an env var must never be able to force a pass). classify() calls exit, so each
  # case runs in a subshell that also sets the REQUIRE level for the unverifiable path.
  # DECLARATION defaults to a path that can never exist, so these six PRE-B4 cells keep their
  # pre-B4 behaviour untouched even though the kit's own REQUIRED-CHECKS.md now sits at repo root.
  cls() {  # expect_rc require rc body label [declaration-file]
    e=$1; req=$2; r=$3; b=$4; lbl=$5; d=${6:-/nonexistent-required-checks-$$}
    ( REQUIRE="$req"; REPO=selftest; DECLARATION="$d"; classify "$r" "$b" ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> exit $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  cls 0 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{}}' "200 + both settings + a review count of 1"
  cls 1 0 0 '{}' "200 + missing settings"
  # ★ THE COUNT CELLS (review round 1, finding 2). A count of 0 is a review requirement that requires
  # nothing, and the green-while-waiting ratification rendering leans on this exact number.
  cls 1 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{}}' "200 + review count of ZERO -> FAIL (nothing would block an unratified CP merge)"
  cls 1 0 0 '{"required_pull_request_reviews":{},"required_status_checks":{}}' "200 + reviews block PRESENT but no count at all -> FAIL (presence is not a requirement)"
  cls 0 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":2,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{}}' "200 + a count above 1 -> PASS (the gate asserts a floor, not an exact value)"
  cls 0 0 0 '{"required_pull_request_reviews": { "required_approving_review_count" : 1 , "dismiss_stale_reviews" : true , "require_last_push_approval" : true },"required_status_checks":{}}' "the count parses through arbitrary JSON whitespace"
  # ★★ THE TWO SETTINGS THAT REPLACED review-lane's ATTESTATION LEG (REVIEW-LANE-WAITING-IS-GREEN,
  # 2026-09-05). That leg read the forge to prove the approval sat on THIS head and did not come from
  # the identity that wrote it; it is deleted, and these two server-side settings are what carry those
  # properties now. This gate is therefore the ONLY thing standing between "the settings are off" and
  # "an unattested PR merges green" — so absent reds exactly like false. Absence is the dangerous case:
  # a `required_pull_request_reviews` block that simply omits a key is the shape GitHub returns for a
  # protection rule nobody finished configuring.
  cls 1 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":false,"require_last_push_approval":true},"required_status_checks":{}}' "dismiss_stale_reviews FALSE -> FAIL (a stale approval would survive a fix push)"
  cls 1 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"require_last_push_approval":true},"required_status_checks":{}}' "dismiss_stale_reviews ABSENT -> FAIL (absent is not true)"
  cls 1 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":false},"required_status_checks":{}}' "require_last_push_approval FALSE -> FAIL (the pusher could approve their own push)"
  cls 1 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true},"required_status_checks":{}}' "require_last_push_approval ABSENT -> FAIL (absent is not true)"
  cls 0 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{}}' "all three review settings + a count of 1 -> PASS"
  # (the whitespace-tolerance cell above now carries all three settings spaced out, so the new arms'
  #  parse is covered by the same case that covers the count's — one fixture, three assertions.)
  cls 1 0 1 '{"message":"Branch not protected","status":"404"}' "404 not-protected"
  cls 2 0 1 '{"message":"Must have admin rights to Repository."}' "403 admin-rights -> UNVERIFIED"
  cls 1 1 1 '{"message":"Must have admin rights to Repository."}' "403 admin + CI/require -> FAIL"
  cls 2 0 1 '{"message":"validation failed","errors":["required_pull_request_reviews","required_status_checks"]}' "non-200 spoof body -> UNVERIFIED (not a false pass)"

  # ── B4: declared-contexts comparison + the offline --declared-only leg. Fixtures live in a
  # mktemp dir, trap-cleaned; never a committed fixture (which would poison the self-scanning gates).
  _bpdir=""; _ghdir=""; _ghenvdir=""
  trap 'rm -rf "$_bpdir" "$_ghdir" "$_ghenvdir" 2>/dev/null || true' EXIT
  _bpdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for declared-context fixtures"; st=1; }
  printf '# fixture\n\n```\nci\ncontrol-plane-ratification\n```\n' > "$_bpdir/good.md"
  printf '```\nci\nci\n```\n' > "$_bpdir/dup.md"
  printf '```\n<your-check-name>\n```\n' > "$_bpdir/pristine.md"
  printf '```\n<your-check-name>\nci\n```\n' > "$_bpdir/mixed.md"
  printf '```\n```\n' > "$_bpdir/empty.md"
  # B4 fix round 1: charset / DoS / second-fence fixtures (SEC C-1/H-2/L-2..L-4, REV M1).
  printf '```\n"allow_force_pushes":true\n```\n' > "$_bpdir/inject.md"          # C-1: JSON-metachar/quote injection attempt
  printf '```\nci\n*\n```\n' > "$_bpdir/glob.md"                                 # bare glob declared
  printf '```\nbuild and test\n```\n' > "$_bpdir/spacey.md"                      # space-containing name (v1: not declarable)
  printf '```\n-bad-context\n```\n' > "$_bpdir/dash.md"                          # leading dash
  printf '```\nci\tbad\n```\n' > "$_bpdir/ctrl.md"                               # control char (embedded tab)
  printf '```\nci\n\033[31mFAKE\033[0m\n```\n' > "$_bpdir/esc.md"                # R-3: raw ESC/ANSI sequence in the context name
  { printf '```\n'; _i=1; while [ "$_i" -le 101 ]; do printf 'ctx-%s\n' "$_i"; _i=$((_i + 1)); done; printf '```\n'; } > "$_bpdir/toomany.md"
  printf '```\nci\ncontrol-plane-ratification\n```\n\nExample usage:\n```\nusage-example-context\n```\n' > "$_bpdir/twofence.md"

  clsd() {  # expect_rc needle require rc body declaration-file label — classify() WITH a real declaration
    e=$1; needle=$2; req=$3; r=$4; b=$5; d=$6; lbl=$7
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="$d"; classify "$r" "$b" ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  clsd 1 "FAIL: required-check context(s) declared" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":["ci"]}}' \
    "$_bpdir/good.md" "declared-missing context (control-plane-ratification) -> FAIL naming it"
  clsd 1 "run: sh scripts/branch-protection-apply.sh --apply" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":["ci"]}}' \
    "$_bpdir/good.md" "declared-missing FAIL appends the remedy (REV L3)"
  clsd 1 "FAIL: required-check context(s) declared" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/good.md" "live contexts:[] with active declared contexts -> FAIL"
  clsd 0 "ADVISORY: live status check(s) not declared" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":["ci","control-plane-ratification","extra-check"]}}' \
    "$_bpdir/good.md" "live \\ declared -> ADVISORY, non-fatal (still exit 0)"
  clsd 0 "OK: main on selftest is protected" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":["ci","control-plane-ratification"]}}' \
    "$_bpdir/good.md" "conformant declaration + matching live -> OK"
  # SEC H-3/REV M3: skip disclosure — every skip route prints a line; malformed escalates under --require.
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/dup.md" "malformed (duplicate) declaration, no --require -> ADVISORY disclosure, non-fatal"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/dup.md" "malformed (duplicate) declaration + --require -> escalates to FAIL"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/mixed.md" "malformed (placeholder-mixed) declaration, no --require -> ADVISORY disclosure"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/mixed.md" "malformed (placeholder-mixed) declaration + --require -> escalates to FAIL"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/inject.md" "malformed (bad-charset) declaration + --require -> escalates to FAIL"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/pristine.md" "pristine template -> ADVISORY disclosure, NEVER escalates (not malformed)"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/pristine.md" "pristine template + --require -> still ADVISORY, never FAIL"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/does-not-exist-clsd.md" "absent declaration + --require -> still ADVISORY, never FAIL"
  # R-1: declared, zero placeholders, zero active contexts (empty/de-fenced block) — the sixth skip
  # route. Must disclose like every other malformed case, and escalate to FAIL under --require;
  # previously this fell through the ladder silently and read as OK (nothing to compare).
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/empty.md" "empty/de-fenced (zero active contexts) declaration, no --require -> ADVISORY disclosure (R-1)"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/empty.md" "empty/de-fenced (zero active contexts) declaration + --require -> escalates to FAIL (R-1)"

  clsdo() {  # expect_rc needle file label — declared_only() direct
    e=$1; needle=$2; f=$3; lbl=$4
    out=$( ( DECLARATION="$f"; declared_only ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  clsdo 1 "duplicate required-check context" "$_bpdir/dup.md" "duplicate declared context -> FAIL naming it"
  clsdo 1 "mixes the unedited placeholder" "$_bpdir/mixed.md" "placeholder mixed with active contexts -> FAIL"
  clsdo 1 "declares zero active" "$_bpdir/empty.md" "empty (not pristine) declaration -> FAIL"
  clsdo 0 "declares 2 required-check context(s)" "$_bpdir/good.md" "well-formed declaration -> OK naming the count"
  clsdo 1 "allow_force_pushes" "$_bpdir/inject.md" "JSON-metachar/quote injection attempt -> FAIL naming it (C-1)"
  clsdo 1 "*" "$_bpdir/glob.md" "bare glob '*' declared -> FAIL naming it"
  clsdo 1 "build and test" "$_bpdir/spacey.md" "space-containing context name -> FAIL naming it (v1: not declarable)"
  clsdo 1 "-bad-context" "$_bpdir/dash.md" "leading-dash context name -> FAIL naming it"
  clsdo 1 "invalid required-check context name" "$_bpdir/ctrl.md" "control char (embedded tab) in context name -> FAIL"
  clsdo 1 "cap exceeded" "$_bpdir/toomany.md" "more than 100 declared context lines -> FAIL (DoS bound)"
  clsdo 0 "declares 2 required-check context(s)" "$_bpdir/twofence.md" "second fence-open ignored (usage-example never merges in) -> OK naming 2"

  # ── RD-4 (T5): a declared-but-vacuous `tracker-board-gates` must FAIL — the trusted job skips on
  # an md tree, so the required context would be always-green. Trees carry their OWN
  # REQUIRED-CHECKS.md (so `dirname` of the DECLARATION file resolves to the tree vacuous_tracker_check reads).
  _rd4md="$_bpdir/rd4-md"; mkdir -p "$_rd4md"
  printf 'Backlog backend: md\n' > "$_rd4md/CLAUDE.md"
  printf '```\nci\ntracker-board-gates\n```\n' > "$_rd4md/REQUIRED-CHECKS.md"
  _rd4trk="$_bpdir/rd4-trk"; mkdir -p "$_rd4trk/.kit" "$_rd4trk/scripts"
  printf 'Backlog backend: jira\n' > "$_rd4trk/CLAUDE.md"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net/jira\nproject=AB\n' > "$_rd4trk/.kit/tracker.conf"
  cp "$REPO_ROOT/scripts/tracker-conf.sh" "$_rd4trk/scripts/tracker-conf.sh"
  printf '```\nci\ntracker-board-gates\n```\n' > "$_rd4trk/REQUIRED-CHECKS.md"
  _rd4cmt="$_bpdir/rd4-cmt"; mkdir -p "$_rd4cmt"
  printf 'Backlog backend: md\n' > "$_rd4cmt/CLAUDE.md"
  printf '```\nci\n# tracker-board-gates (commented, not active)\n```\n' > "$_rd4cmt/REQUIRED-CHECKS.md"
  clsdo 1 "tracker-board-gates is declared required but this tree's backlog backend is md" \
    "$_rd4md/REQUIRED-CHECKS.md" "RD-4: md tree + declared tracker-board-gates -> FAIL"
  clsdo 0 "declares 2 required-check context(s)" \
    "$_rd4trk/REQUIRED-CHECKS.md" "RD-4: tracker tree (valid conf) + declared tracker-board-gates -> OK unchanged"
  clsdo 0 "declares 1 required-check context(s)" \
    "$_rd4cmt/REQUIRED-CHECKS.md" "RD-4: md tree + a COMMENTED mention (not an active line) -> OK, no FAIL"

  # RT5-Q2: pin each arm against the JOB's own conf-backend skip rule, not CLAUDE.md alone.
  # Arm 1 — CLAUDE.md declares a hosted tracker (linear) but NO conf at all -> FAIL (conf-absent
  # mirrors the job's own "no .kit/tracker.conf on base" skip route).
  _rd4lin="$_bpdir/rd4-linear-noconf"; mkdir -p "$_rd4lin/scripts"
  cp "$REPO_ROOT/scripts/tracker-conf.sh" "$_rd4lin/scripts/tracker-conf.sh"
  printf 'Backlog backend: linear\n' > "$_rd4lin/CLAUDE.md"
  printf '```\nci\ntracker-board-gates\n```\n' > "$_rd4lin/REQUIRED-CHECKS.md"
  clsdo 1 "tracker-board-gates is declared required but this tree's backlog backend is md" \
    "$_rd4lin/REQUIRED-CHECKS.md" "RT5-Q2 arm 1: CLAUDE.md=linear + no conf -> FAIL"
  # Arm 2 — CLAUDE.md declares jira but the CONF's own backend= is md -> FAIL (the job reads the
  # conf, not CLAUDE.md, to decide skip=true; a stale/mismatched CLAUDE.md must not launder this).
  _rd4mismatch="$_bpdir/rd4-jira-confmd"; mkdir -p "$_rd4mismatch/.kit" "$_rd4mismatch/scripts"
  printf 'Backlog backend: jira\n' > "$_rd4mismatch/CLAUDE.md"
  printf 'version=1\nbackend=md\nbase_url=https://ex.atlassian.net/jira\nproject=AB\n' > "$_rd4mismatch/.kit/tracker.conf"
  cp "$REPO_ROOT/scripts/tracker-conf.sh" "$_rd4mismatch/scripts/tracker-conf.sh"
  printf '```\nci\ntracker-board-gates\n```\n' > "$_rd4mismatch/REQUIRED-CHECKS.md"
  clsdo 1 "tracker-board-gates is declared required but this tree's backlog backend is md" \
    "$_rd4mismatch/REQUIRED-CHECKS.md" "RT5-Q2 arm 2: CLAUDE.md=jira + conf backend=md -> FAIL"
  # Arm 3 — CLAUDE.md declares jira AND the conf's own backend= is jira -> OK (the existing tracker
  # leg above, rd4trk, IS this arm; re-asserted here by name for RT5-Q2's record).
  clsdo 0 "declares 2 required-check context(s)" \
    "$_rd4trk/REQUIRED-CHECKS.md" "RT5-Q2 arm 3: CLAUDE.md=jira + conf backend=jira -> OK (the existing tracker leg)"

  # RT5-Q3: if seam_backend is not defined after sourcing the lib (any reason — the source
  # failed, the lib moved, etc.), vacuous_tracker_check must FAIL CLOSED, never silently pass a
  # check it could not actually run. Unset it in a subshell (never affecting the outer script's
  # own copy) on the otherwise-valid tracker tree (rd4trk) — a shape that would OK without this
  # guard, so a real FAIL here proves the fail-closed path, not the ordinary md/conf-absent path.
  _q3out=$( ( DECLARATION="$_rd4trk/REQUIRED-CHECKS.md"; unset -f seam_backend; declared_only ) 2>&1 ) && _q3rc=0 || _q3rc=$?
  if [ "$_q3rc" = 1 ] && printf '%s\n' "$_q3out" | grep -qF "tracker-board-gates is declared required but this tree's backlog backend is md"; then
    echo "selftest PASS: RT5-Q3: seam_backend undefined -> FAIL closed, never a silent pass -> exit $_q3rc"
  else
    echo "selftest FAIL: RT5-Q3: seam_backend undefined -> want FAIL closed, got rc=$_q3rc out=[$_q3out]"; st=1
  fi

  # RD-4 through the LIVE leg's classify() comparison path too (inception-done's existing call is
  # the live leg, not --declared-only — RD-4 must surface there as a real FAIL, not an ADVISORY).
  clsd 1 "tracker-board-gates is declared required but this tree's backlog backend is md" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":["ci","tracker-board-gates"]}}' \
    "$_rd4md/REQUIRED-CHECKS.md" "RD-4 via classify() (the live leg): md tree, both contexts bound -> FAIL anyway (vacuous, never advisory)"

  # kit self-check (Verify §): the kit's own tree is `md` and must NEVER declare
  # `tracker-board-gates` in its own REQUIRED-CHECKS.md, or this leg would FAIL on the kit itself.
  clsdo 0 "" "$REPO_ROOT/REQUIRED-CHECKS.md" "the kit's own REQUIRED-CHECKS.md (md tree) -> still OK (does not declare tracker-board-gates)"

  # R-3: the invalid-name FAIL line must never carry a raw control/ESC byte (measured erasing the
  # FAIL prefix on ANSI terminals). Assert the sanitized form directly rather than trusting a visual
  # read: stripping control bytes from the actual output must be a no-op if it was already clean.
  _esc_out=$( ( DECLARATION="$_bpdir/esc.md"; declared_only ) 2>&1 ) || true
  _esc_clean=$(printf '%s' "$_esc_out" | tr -d '[:cntrl:]')
  if printf '%s' "$_esc_out" | grep -qF -- "invalid required-check context name" && [ "$_esc_out" = "$_esc_clean" ]; then
    echo "selftest PASS: invalid-name FAIL line carries no raw control/ESC bytes (R-3)"
  else
    echo "selftest FAIL: invalid-name FAIL line still carries raw control bytes (R-3) (out=[$_esc_out])"; st=1
  fi

  clsdo_root() {  # expect_rc needle root file label — declared_only() with a REPO_ROOT override too
    e=$1; needle=$2; root=$3; f=$4; lbl=$5
    out=$( ( REPO_ROOT="$root"; DECLARATION="$f"; declared_only ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  # HERMETIC kit-tree fixture (B4 round 3, the B3 hermeticity lesson recurring): the ambient
  # $REPO_ROOT is kit-shaped in the dev repo but carries NEITHER marker in a built export (both
  # docs/ROADMAP-KIT.md and .github/workflows/golden-path.yml are export-ignored), so asserting
  # this cell against $REPO_ROOT passed here and silently flipped to the N/A branch inside the
  # export artifact (measured: CI's artifact-gate got rc=0 "N/A" where FAIL was required). Plant a
  # throwaway root that carries ONLY the marker is_kit_tree() reads, independent of which tree this
  # selftest happens to run inside — production is_kit_tree()/declared_only() are unchanged; only
  # this cell's evidence source moves.
  _bpkitroot="$_bpdir/kitroot"
  mkdir -p "$_bpkitroot/docs"
  : > "$_bpkitroot/docs/ROADMAP-KIT.md"
  clsdo_root 1 "the kit must carry its own declaration" "$_bpkitroot" "$_bpdir/nonexistent-kit.md" "kit-tree, absent declaration -> FAIL (SEC H-4)"
  clsdo_root 0 "N/A" "$_bpdir" "$_bpdir/nonexistent-adopter.md" "adopter/export tree (no kit markers), absent declaration -> N/A"

  # --declared-only must NEVER touch gh/network — prove it with a PATH-stub gh that records
  # any invocation (argument-borne PATH manipulation, no env-forced stub of the check itself).
  _ghdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the gh-stub fixture"; st=1; }
  printf '#!/bin/sh\necho called >> "%s/called"\nexit 0\n' "$_ghdir" > "$_ghdir/gh"
  chmod +x "$_ghdir/gh"
  ( PATH="$_ghdir:$PATH" sh "$0" --declared-only "$_bpdir/good.md" ) >/dev/null 2>&1 || true
  if [ -f "$_ghdir/called" ]; then
    echo "selftest FAIL: --declared-only invoked gh (network path touched)"; st=1
  else
    echo "selftest PASS: --declared-only never touches gh/network"
  fi

  # Parser-drift lock (SEC L-1/REV): read_declaration() here and ad_read_declaration() in
  # scripts/branch-protection-apply.sh must NEVER disagree on the same fixture — the two copies of
  # valid_context_name() (and the surrounding parse) must never drift (the B3 mirror lesson).
  # scripts/branch-protection-apply.sh --print-parsed is a read-only debug surface for exactly this
  # cross-check (no gh, no mutation, plain output of its own parsed active-context list).
  _pdb_files="$_bpdir/good.md $_bpdir/dup.md $_bpdir/pristine.md $_bpdir/mixed.md $_bpdir/empty.md $_bpdir/inject.md $_bpdir/glob.md $_bpdir/spacey.md $_bpdir/dash.md $_bpdir/ctrl.md $_bpdir/esc.md $_bpdir/toomany.md $_bpdir/twofence.md"
  _pdb_bad=0
  for _pdb_f in $_pdb_files; do
    read_declaration "$_pdb_f"
    _pdb_a=$(printf '%s\n' $RD_LIST | sort)
    _pdb_b=$(sh "$REPO_ROOT/scripts/branch-protection-apply.sh" --declaration="$_pdb_f" --print-parsed 2>/dev/null | sort)
    if [ "$_pdb_a" != "$_pdb_b" ]; then
      echo "selftest FAIL: parser drift on $_pdb_f — branch-protection.sh=[$_pdb_a] apply.sh=[$_pdb_b]"
      st=1; _pdb_bad=1
    fi
  done
  [ "$_pdb_bad" = 0 ] && echo "selftest PASS: both parsers agree across the fixture battery (no drift)"

  # GH env containment (SEC M-3): GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/GH_CONFIG_DIR must never reach
  # the gh subprocess (a hostile value could redirect the API host, retarget the repo, or swap
  # creds/config); GH_TOKEN must still reach it (the operator's real credential). Proven with a stub
  # gh that dumps its OWN environment — this environment has no controlling tty and CI has no reason
  # to spoof GH_HOST, so this is the assert-the-unset path the design anticipates as an alternative to
  # "still hits the stub" (a stub has no real host to differentiate against).
  _ghenvdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the GH-env fixture"; st=1; }
  _ghenvlog="$_ghenvdir/env.log"
  : > "$_ghenvlog"
  cat > "$_ghenvdir/gh" <<STUB
#!/bin/sh
env | grep '^GH_' | sort >> "$_ghenvlog" 2>/dev/null || true
case "\$*" in
  *"repo view"*) echo "me/repo" ;;
  *) printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' ;;
esac
STUB
  chmod +x "$_ghenvdir/gh"
  GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=evil-ent-token GH_CONFIG_DIR=/evil-config GH_TOKEN=real-op-token \
    PATH="$_ghenvdir:$PATH" sh "$0" --raw >/dev/null 2>&1 || true
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

  # ── PROTECTION-TEAM-PROFILE (design 2026-10-03 §4): the settings line, the declared governance
  # mode, and the team-declared FAILs. classify() reads GOV_MODE / MERGE_METHODS / INVITES_STATE /
  # PENDING_OWNERS, which run() always assigns itself (never from the environment); the cells set them
  # in the subshell exactly as run() would.
  _rv='"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true'
  _TEAM_LIVE='{'"$_rv"',"require_code_owner_reviews":true},"required_status_checks":{"contexts":[]},"enforce_admins":{"url":"u","enabled":true}}'
  _SOLO_LIVE='{'"$_rv"',"require_code_owner_reviews":false},"required_status_checks":{"contexts":[]},"enforce_admins":{"url":"u","enabled":false}}'
  _TEAM_NOCO='{'"$_rv"',"require_code_owner_reviews":false},"required_status_checks":{"contexts":[]},"enforce_admins":{"url":"u","enabled":true}}'
  clst() {  # expect_rc needle require gov merge-methods pending-owners body label
    e=$1; needle=$2; req=$3; gov=$4; mm=$5; pend=$6; b=$7; lbl=$8
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; GOV_MODE="$gov"; MERGE_METHODS="$mm"; INVITES_STATE=ok; PENDING_OWNERS="$pend"; classify 0 "$b" ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  clst_not() {  # needle-must-be-absent variant: expect_rc needle require gov mm pend body label
    e=$1; needle=$2; req=$3; gov=$4; mm=$5; pend=$6; b=$7; lbl=$8
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; GOV_MODE="$gov"; MERGE_METHODS="$mm"; INVITES_STATE=ok; PENDING_OWNERS="$pend"; classify 0 "$b" ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && ! printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e and no '$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  _CURE="sh scripts/branch-protection-apply.sh --replace --team"
  clst 0 "settings: enforce_admins=true code_owner_reviews=true approvals=1 last_push=true dismiss_stale=true merge_methods=squash-only" 0 team squash-only "" "$_TEAM_LIVE" "team declared + team live + squash-only -> PASS, the settings line reads what it saw"
  clst 1 "enforce_admins" 0 team squash-only "" "$_SOLO_LIVE" "team declared + solo live (enforce_admins false) -> FAIL naming enforce_admins"
  clst 1 "$_CURE" 0 team squash-only "" "$_SOLO_LIVE" "team declared + solo live -> the FAIL names the cure verb"
  clst 1 "require_code_owner_reviews" 0 team squash-only "" "$_TEAM_NOCO" "team declared + code-owner review off -> FAIL naming it"
  clst 1 "merge methods" 0 team "squash,merge,rebase" "" "$_TEAM_LIVE" "team declared + merge commits allowed -> FAIL naming the merge methods"
  clst 1 "$_CURE" 0 team squash,merge "" "$_TEAM_LIVE" "team declared + non-squash merge methods -> the FAIL names the cure verb"
  clst 0 "ADVISORY: merge methods are not readable with this token — the squash-only pin is UNVERIFIED on selftest (team declaration); an admin can confirm it with sh scripts/branch-protection-apply.sh (show-only prints merge-methods: current=…)" 0 team unknown "" "$_TEAM_LIVE" "team declared + merge methods unreadable -> a loud ADVISORY, rc 0 (owner ruling: the CI PAT cannot read them)"
  clst 0 "ADVISORY: merge methods are not readable with this token — the squash-only pin is UNVERIFIED on selftest (team declaration); an admin can confirm it with sh scripts/branch-protection-apply.sh (show-only prints merge-methods: current=…)" 1 team unknown "" "$_TEAM_LIVE" "team declared + merge methods unreadable + --require/CI -> still the ADVISORY at rc 0 (never red on every PR)"
  clst_not 0 "ADVISORY: merge methods are not readable" 0 team squash-only "" "$_TEAM_LIVE" "team declared + readable squash-only -> no unreadable-ADVISORY"
  clst_not 0 "ADVISORY: merge methods are not readable" 0 solo unknown "" "$_TEAM_LIVE" "solo declared + unreadable merge methods -> unchanged (no ADVISORY, settings line says unknown)"
  clst 1 "FAIL: CLAUDE.md declares governance team but require_code_owner_reviews" 0 team unknown "" "$_TEAM_NOCO" "team declared + unreadable merge methods + code-owner off -> still a hard FAIL (rc 1)"
  clst 1 "enforce_admins" 0 team unknown "" "$_SOLO_LIVE" "team declared + a verified FAIL outranks an unreadable merge-method read (rc 1)"
  clst 0 "merge_methods=unknown" 0 team unknown "" "$_TEAM_LIVE" "an unreadable merge-method read shows merge_methods=unknown on the settings line"
  clst_not 1 "ADVISORY: require_code_owner_reviews" 0 team squash-only "" "$_TEAM_NOCO" "team declared + code-owner off -> the FAIL says it; the ADVISORY is skipped (R-7)"
  clst 0 "OK:" 0 solo squash-only "" "$_TEAM_LIVE" "solo declared + team live -> PASS"
  clst 0 "settings: enforce_admins=false code_owner_reviews=false approvals=1 last_push=true dismiss_stale=true merge_methods=squash-only" 0 undeclared squash-only "" "$_SOLO_LIVE" "undeclared + solo live -> today's PASS verdict plus the settings line"
  clst 0 "OK:" 0 solo "squash,merge,rebase" "" "$_SOLO_LIVE" "solo declared + merge commits allowed -> still PASS"
  clst 0 "ADVISORY: merge methods" 0 solo "squash,merge,rebase" "" "$_SOLO_LIVE" "solo declared + non-squash merge methods -> an ADVISORY naming it"
  clst 0 "ADVISORY: merge methods" 0 undeclared "squash,merge,rebase" "" "$_SOLO_LIVE" "undeclared + non-squash merge methods -> an ADVISORY naming it"
  clst_not 0 "ADVISORY: merge methods" 0 solo squash-only "" "$_SOLO_LIVE" "squash-only -> no merge-method ADVISORY"
  clst_not 0 "ADVISORY: merge methods" 0 undeclared unknown "" "$_SOLO_LIVE" "unknown merge methods on an undeclared tree -> no merge-method ADVISORY (the line says unknown)"
  clst 0 "WARN: CODEOWNERS names reviewer-login but that account has only a PENDING invitation" 0 team squash-only "reviewer-login" "$_TEAM_LIVE" "a pending CODEOWNERS invitation -> WARN naming the login (non-fatal)"
  out=$( ( REQUIRE=0; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; GOV_MODE=solo; MERGE_METHODS=squash-only; INVITES_STATE=unreadable; PENDING_OWNERS=""; classify 0 "$_SOLO_LIVE" ) 2>&1 ) && g=0 || g=$?
  if [ "$g" = 0 ] && printf '%s\n' "$out" | grep -qF "invitations: not readable with this token"; then echo "selftest PASS: unreadable invitations are said, never silent"; else echo "selftest FAIL: unreadable invitations (rc=$g out=[$out])"; st=1; fi
  # the existing 200-body cells carry no settings of their own: they must not have changed rc under the new defaults.
  clst 0 "OK:" 0 undeclared unknown "" '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{}}' "defaults (undeclared, merge methods unknown) keep today's PASS"

  # read_governance: the strict read of the tree's CLAUDE.md Governance line. Anything but exactly
  # `team` / `solo` as the first word of the value is "undeclared" — never a guess.
  _gv="$_bpdir/gov"; mkdir -p "$_gv"
  gov_cell() {  # want label line...   (writes the lines to a CLAUDE.md and reads it)
    want=$1; lbl=$2; shift 2
    : > "$_gv/CLAUDE.md"; for _gl in "$@"; do printf '%s\n' "$_gl" >> "$_gv/CLAUDE.md"; done
    got=$( ( read_governance "$_gv/CLAUDE.md"; printf '%s' "${GOV_MODE:-}" ) 2>/dev/null ) || got="ERR"
    if [ "$got" = "$want" ]; then echo "selftest PASS: read_governance $lbl -> $want"; else echo "selftest FAIL: read_governance $lbl want '$want' got '$got'"; st=1; fi
  }
  gov_cell team "stamped bullet (team + the template's trailing prose)" '- **Governance** (§ solo/team): team — solo = admin-merge; team = non-author approval'
  gov_cell solo "stamped bullet (solo)" '- **Governance** (§ solo/team): solo — solo = admin-merge; team = non-author approval'
  gov_cell team "bare value, no bullet, end of line" '**Governance** (§ solo/team): team'
  gov_cell undeclared "unfilled placeholder [solo / team]" '- **Governance** (§ solo/team): [solo / team] — solo = admin-merge'
  gov_cell undeclared "a value that merely starts with team" '- **Governance** (§ solo/team): teamwork'
  gov_cell undeclared "wrong case" '- **Governance** (§ solo/team): Team'
  gov_cell undeclared "garbage value" '- **Governance** (§ solo/team): hybrid'
  gov_cell team "two field lines solo+team (ambiguous: fail toward strict -> team)" '- **Governance** (§ solo/team): solo' '- **Governance** (§ solo/team): team'
  gov_cell undeclared "two field lines both solo (ambiguous, no team -> undeclared)" '- **Governance** (§ solo/team): solo' '**Governance** (§ solo/team): solo'
  gov_cell team "one real field line + a prose mention of the phrase (prose is ignored)" 'We discuss **Governance** (§ solo/team): solo elsewhere' '- **Governance** (§ solo/team): team'
  gov_cell solo "one real solo field line + a prose mention that says team (prose is ignored)" 'We discuss **Governance** (§ solo/team): team elsewhere' '- **Governance** (§ solo/team): solo'
  gov_cell undeclared "no Governance line at all" '# Project' 'nothing here'
  gov_cell undeclared "Governance named inside prose, not as the field" 'We discuss **Governance** (§ solo/team): team elsewhere, mid-sentence'
  : > "$_gv/CLAUDE.md"; printf '%s\n%s\n' '- **Governance** (§ solo/team): solo' '- **Governance** (§ solo/team): team' >> "$_gv/CLAUDE.md"
  got=$( ( read_governance "$_gv/CLAUDE.md"; printf '%s' "${GOV_NOTE:-}" ) 2>/dev/null ) || got="ERR"
  if [ "$got" = "ambiguous: 2 field lines" ]; then echo "selftest PASS: read_governance names the ambiguity (2 field lines) so it is visible"; else echo "selftest FAIL: read_governance ambiguity note got '$got'"; st=1; fi
  got=$( ( read_governance "$_gv/does-not-exist"; printf '%s' "${GOV_MODE:-}" ) 2>/dev/null ) || got="ERR"
  if [ "$got" = "undeclared" ]; then echo "selftest PASS: read_governance absent file -> undeclared"; else echo "selftest FAIL: read_governance absent file got '$got'"; st=1; fi

  # parse_merge_methods: the three TOP-LEVEL repo fields as `gh api --jq` prints them
  # (`[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge]|map(tostring)|join(" ")`) -> squash-only |
  # the allowed list | unknown. Reading them with jq (not a text scan) is what keeps a `template_repository`
  # object, which repeats the keys BEFORE the top-level ones, from being read instead (S-1).
  mm_cell() {  # want label fields
    got=$(parse_merge_methods "$3" 2>/dev/null) || got="ERR"
    if [ "$got" = "$1" ]; then echo "selftest PASS: parse_merge_methods $2 -> $1"; else echo "selftest FAIL: parse_merge_methods $2 want '$1' got '$got'"; st=1; fi
  }
  mm_cell squash-only "squash only" 'true false false'
  mm_cell squash,merge,rebase "all three allowed" 'true true true'
  mm_cell squash,merge "squash + merge commit" 'true true false'
  mm_cell unknown "fields null (token cannot read them)" 'null null null'
  mm_cell unknown "one field null" 'true false null'
  mm_cell unknown "two fields only" 'true false'
  mm_cell unknown "garbage" 'yes no maybe'
  mm_cell unknown "empty" ''
  if command -v jq >/dev/null 2>&1; then
    # S-1 against a real jq: a template_repository (squash-only) BEFORE top-level keys that allow merge commits.
    got=$(printf '%s' '{"template_repository":{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false},"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":false}' \
      | jq -r '[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge]|map(tostring)|join(" ")' 2>/dev/null) || got=""
    got=$(parse_merge_methods "$got" 2>/dev/null) || got="ERR"
    if [ "$got" = "squash,merge" ]; then echo "selftest PASS: S-1 the jq filter reads the top-level fields, never a template_repository's"; else echo "selftest FAIL: S-1 template_repository shadowed the top-level fields (got '$got')"; st=1; fi
  fi

  # Drift locks: the helpers duplicated into the self-contained apply script must stay identical.
  for _dl in parse_merge_methods co_logins valid_branch; do
    _dl_a=$(sed -n "/^$_dl() {/,/^}/p" "$0")
    _dl_b=$(sed -n "/^$_dl() {/,/^}/p" "$REPO_ROOT/scripts/branch-protection-apply.sh")
    if [ -n "$_dl_a" ] && [ "$_dl_a" = "$_dl_b" ]; then echo "selftest PASS: $_dl() is identical in both scripts (no drift)"; else echo "selftest FAIL: $_dl() drifted between branch-protection.sh and branch-protection-apply.sh"; st=1; fi
  done

  # R-4/S-4: a branch argument that could redirect the API path is refused (rc 2) before any gh call.
  for _bb in 'a..b' 'x?y' 'x#y' 'a b'; do   # (a leading '-' is already a usage error, rc 2)
    out=$(CI='' sh "$0" "$_bb" 2>&1) && g=0 || g=$?
    if [ "$g" = 2 ] && printf '%s\n' "$out" | grep -qF "invalid branch"; then echo "selftest PASS: branch '$_bb' refused (rc 2)"; else echo "selftest FAIL: branch '$_bb' want rc 2 + 'invalid branch' got rc=$g out=[$out]"; st=1; fi
  done

  # End to end through run() with gh stubbed via PATH, in a fixture TREE (REPO_ROOT derives from $0, so
  # the script is copied in beside a CLAUDE.md and a CODEOWNERS).
  _e2e="$_bpdir/e2e"; mkdir -p "$_e2e/conformance" "$_e2e/.github" "$_e2e/bin"
  cp "$0" "$_e2e/conformance/branch-protection.sh"
  printf '%s\n' '- **Governance** (§ solo/team): team — solo = admin-merge' > "$_e2e/CLAUDE.md"
  printf '* @SeaBrad72 @reviewer-login @acme/reviewers\n' > "$_e2e/.github/CODEOWNERS"
  cat > "$_e2e/bin/gh" <<'STUBE2E'
#!/bin/sh
case "$*" in
  *"repo view"*) echo "me/repo" ;;
  *"/invitations"*) [ -z "${STUB_INVITES_FAIL:-}" ] || exit 1; for l in ${STUB_INVITES:-}; do echo "$l"; done ;;
  *"branches/main/protection"*) printf '%s' "$STUB_PROTECTION" ;;
  *) [ -z "${STUB_REPO_FAIL:-}" ] || exit 1; printf '%s' "$STUB_REPOJSON" ;;
esac
STUBE2E
  chmod +x "$_e2e/bin/gh"
  e2e() {  # lbl want-rc needle protection repojson [VAR=val...]   -> runs the fixture tree's script under the stub
    lbl=$1; want=$2; needle=$3; prot=$4; repoj=$5; shift 5
    out=$( ( PATH="$_e2e/bin:$PATH"; STUB_PROTECTION="$prot"; STUB_REPOJSON="$repoj"; export STUB_PROTECTION STUB_REPOJSON; env CI='' REQUIRE=0 "$@" sh "$_e2e/conformance/branch-protection.sh" ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$want" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then echo "selftest PASS: e2e $lbl -> exit $g"; else echo "selftest FAIL: e2e $lbl want rc=$want needle='$needle' got rc=$g out=[$out]"; st=1; fi
  }
  _RJ_SQ='true false false'
  _RJ_ALL='true true true'
  _RJ_TMPL='true true false'   # what jq prints for the TOP-LEVEL fields when a template_repository says squash-only (S-1)
  e2e "team declared + team live + squash-only" 0 "merge_methods=squash-only" "$_TEAM_LIVE" "$_RJ_SQ"
  e2e "team declared + solo live" 1 "$_CURE" "$_SOLO_LIVE" "$_RJ_SQ"
  e2e "team declared + merge commits allowed" 1 "merge methods" "$_TEAM_LIVE" "$_RJ_ALL"
  e2e "team declared + top-level merge commits allowed (a template_repository must not mask it)" 1 "merge methods" "$_TEAM_LIVE" "$_RJ_TMPL"
  e2e "team declared + repo JSON unreadable" 0 "ADVISORY: merge methods are not readable with this token — the squash-only pin is UNVERIFIED on me/repo (team declaration)" "$_TEAM_LIVE" "" STUB_REPO_FAIL=1
  e2e "pending CODEOWNERS invitation (and a team handle is ignored)" 0 "WARN: CODEOWNERS names reviewer-login" "$_TEAM_LIVE" "$_RJ_SQ" STUB_INVITES=reviewer-login
  e2e "team declared + code-owner off: the FAIL says it, the ADVISORY is skipped (R-7)" 1 "FAIL: CLAUDE.md declares governance team but require_code_owner_reviews" "$_TEAM_NOCO" "$_RJ_SQ"
  e2e "invitations unreadable" 0 "invitations: not readable with this token" "$_TEAM_LIVE" "$_RJ_SQ" STUB_INVITES_FAIL=1
  printf '%s\n' '- **Governance** (§ solo/team): solo — solo = admin-merge' > "$_e2e/CLAUDE.md"
  e2e "solo declared + team live + merge commits allowed" 0 "ADVISORY: merge methods" "$_TEAM_LIVE" "$_RJ_ALL"
  rm -f "$_e2e/CLAUDE.md"
  e2e "no CLAUDE.md (kit tree / pre-incept) -> undeclared, solo protection passes" 0 "settings: enforce_admins=false" "$_SOLO_LIVE" "$_RJ_ALL"

  [ "$st" = "0" ] && echo "branch-protection --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --declared-only) declared_only; exit $? ;;
  *) run ;;
esac
