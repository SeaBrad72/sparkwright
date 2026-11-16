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
#     that rendering are one control, and the count is checked here or nowhere. (SWAS-901: ONE tree may run at a count of 0, `OK-solo`: it
#     declares MERGE_RELATIONSHIP=solo in a regular dial file with no Governance team line, lists solo-go-bound, carries the installed workflow and
#     the go-bound verb, and has solo-go-bound live, with enforce_admins true; the check run from the base then stands in for the approval. Every
#     other tree keeps the arms below byte for byte; a solo tree at count 1 gets an ADVISORY that the agent cannot merge.) It ALSO compares the
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
#   usage: sh conformance/branch-protection.sh [BRANCH] [--repo=OWNER/REPO] [--require] [--raw]
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
# GH ENV (B4 fix round 1, SEC M-3, narrowed by SWAS-198 — see DECISIONS.md D-241015-2): the
# environment is NOT a trust boundary here (PATH, HOME and XDG_CONFIG_HOME still steer `gh`, measured).
# Every `gh` call below strips GH_HOST, GH_REPO, GH_ENTERPRISE_TOKEN and GITHUB_ENTERPRISE_TOKEN as
# stale-state hygiene: a value exported for another project must not silently retarget the read
# (--repo= names a repo explicitly). GH_TOKEN, GITHUB_TOKEN and GH_CONFIG_DIR select the operator's
# ACCOUNT and are honored (as `gh` and `sparkwright doctor` honor them). The acting identity is printed
# to stderr first (gh_identity_line), so a wrong account is visible before any lookup or verdict.
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
GOV_FIELD='^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team):'
read_governance() {
  GOV_MODE=undeclared; GOV_NOTE=""
  [ -f "$1" ] || return 0
  _rg_n=$(grep -c -e "$GOV_FIELD" "$1" || true)
  [ "$_rg_n" -ge 1 ] || return 0
  _rg_vals=$(sed -n 's#^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team): \([^[:space:]]*\).*$#\1#p' "$1")
  [ "$_rg_n" = 1 ] || GOV_NOTE="ambiguous: $_rg_n field lines"
  for _rg_v in $_rg_vals; do
    [ "$_rg_v" = team ] && { GOV_MODE=team; return 0; }
  done
  [ "$_rg_n" = 1 ] && [ "$_rg_vals" = solo ] && GOV_MODE=solo
  return 0
}

# go_act_review <root> — 0 when <root>/.kit/dials.conf carries `GO_ACT=review` (SWAS-727; parsed, never sourced; the last
# line wins and the first word is the value, like the other dial readers). Any other value, an absent file or a symlink is no.
go_act_review() {
  [ -f "$1/.kit/dials.conf" ] && [ ! -L "$1/.kit/dials.conf" ] || return 1
  _gar=$(grep -E '^[[:space:]]*GO_ACT[[:space:]]*=' "$1/.kit/dials.conf" 2>/dev/null | tail -n1 \
    | sed -E 's/^[[:space:]]*GO_ACT[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g; s/[[:space:]].*$//')
  [ "$_gar" = review ]
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

# valid_repo <OWNER/REPO> — ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$, and neither half is `.` or `..` (R-4/S-4:
# the value is interpolated into the API path of every call, including the two writes).
valid_repo() {
  case "$1" in */*/*|*/|/*|"") return 1 ;; */*) : ;; *) return 1 ;; esac
  case "$1" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
  case "/$1/" in */./*|*/../*) return 1 ;; esac
  return 0
}

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
  if _gil_login=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh api user --jq .login 2>/dev/null) && valid_login "$_gil_login"; then
    printf '%s\n' "acting gh identity: $_gil_login (credential: $_gil_src)" >&2
  else
    printf '%s\n' "acting gh identity: not resolved (credential: $_gil_src; gh api user failed, so the next calls will likely fail too)" >&2
  fi
}

REQUIRE="${REQUIRE:-0}"
RAW=0
BRANCH=main
REPO_ARG=""
REPO_SET=0
DECLARED_ONLY=0
DECLARATION="REQUIRED-CHECKS.md"
DECL_EXPLICIT=0
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --raw) RAW=1 ;;   # emit the un-escalated three-state (0/1/2), overriding ONLY the ambient-CI auto-escalation below; an explicit --require alongside --raw still escalates
    --declared-only) DECLARED_ONLY=1 ;;
    --repo=*) REPO_ARG=${a#--repo=}; REPO_SET=1 ;;
    --selftest) ;;  # dispatched below
    -*) printf '%s\n' "usage: branch-protection.sh [BRANCH] [--repo=OWNER/REPO] [--require] [--raw] | --declared-only [FILE] | --selftest" >&2; exit 2 ;;
    *) if [ "$DECLARED_ONLY" = 1 ]; then DECLARATION="$a"; DECL_EXPLICIT=1; else BRANCH="$a"; fi ;;
  esac
done
# --repo names the LIVE leg's repo; the offline leg has none. Checked after the loop so the order of the
# two flags never matters (the tail dispatch reads only $1).
if [ "$REPO_SET" = 1 ] && [ "$DECLARED_ONLY" = 1 ]; then
  printf '%s\n' "branch-protection.sh: --repo is a live-leg flag and cannot be combined with --declared-only (the offline leg has no repo)" >&2; exit 2
fi
if [ "$REPO_SET" = 1 ] && ! valid_repo "$REPO_ARG"; then
  printf '%s\n' "branch-protection.sh: invalid --repo (must be OWNER/REPO, characters A-Za-z0-9._- only, no . or .. segment)" >&2; exit 2
fi
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

# bp_rsc_text <body> — SWAS-901 E6 R3-2/R4-1: the text of the FIRST required_status_checks object, on one line: from its `{` to the first `}` that is
# followed by a key (no checks entry's `}` is). The ONE cut every read of that object goes through (the contexts, the checks and the app pin), so
# a "context", "contexts" or app_id text anywhere else in the body binds nothing.
bp_rsc_text() {
  printf '%s' "$1" | tr -d '\n' | awk '{ i = index($0, "\"required_status_checks\""); if (i) print substr($0, i) }' | sed 's/^[^{]*{//; s/}[[:space:]]*,[[:space:]]*".*$//'   # MUT-BPSCOPE
}

# extract_live_contexts <body> — one required-status-check context per line on stdout (rc always 0;
# empty stdout means none present or the body was unparsable). jq is an OPTIONAL fast path (Δ7): the
# live side is GitHub's JSON, so unlike the declaration side a hard jq dependency would add a new
# UNVERIFIED axis for adopters without it — POSIX sed/tr is the load-bearing path.
extract_live_contexts() {
  if command -v jq >/dev/null 2>&1; then
    if _elc_j=$(printf '%s' "$1" | jq -r '.required_status_checks.contexts[]?' 2>/dev/null); then
      if [ -n "$_elc_j" ]; then printf '%s\n' "$_elc_j" | sort -u; return 0; fi
    fi
  fi
  # E6 R2-1: a `checks` entry names a required context too (the solo-agent body has ONLY `checks`); GitHub's own answer lists both.
  # E6 R3-2: but only INSIDE the required_status_checks object (bp_rsc_text).
  _elc_o=$(bp_rsc_text "$1")
  _elc_s=$(printf '%s' "$_elc_o" | sed -n 's/.*"checks"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')
  {
    printf '%s' "$_elc_o" \
      | sed -n 's/.*"contexts"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*"\{0,1\}//; s/"\{0,1\}[[:space:]]*$//' \
      | grep -v '^[[:space:]]*$' || true
    printf '%s' "$_elc_s" | grep -o '"context"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"//; s/"$//' || true   # MUT-BPCHK
  } | sort -u
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

# read_merge_relationship <root> — SWAS-901: sets REL_MODE to `solo` or `team` from the TREE's own files (the grammar of the verbs' reader, and
# go_act_review's file hygiene): `solo` only when <root>/.kit/dials.conf is a regular file that is not a symlink, its last MERGE_RELATIONSHIP line
# says solo, and CLAUDE.md carries no Governance `team` line. Every other case, an unreadable one included, is team. GOV_MODE/GOV_NOTE are restored.
REL_MODE=team; REL_TIPERR=0
# bp_tip_blob <root> <path> -> the file as the default branch's TIP holds it (refs/remotes/origin/$BRANCH, as the verbs and the picker read it, never the
# checked-out tree a PR controls); rc 0 = printed, 1 = absent, 2 = not a regular file or unreadable, 3 = the ref itself is missing (fetch origin <branch>).
bp_tip_blob() {
  git -C "$1" rev-parse -q --verify "refs/remotes/origin/$BRANCH^{commit}" >/dev/null 2>&1 || return 3
  _btb_e=$(git -C "$1" ls-tree --full-tree "refs/remotes/origin/$BRANCH" -- "$2" 2>/dev/null | head -n 1) || return 2
  [ -n "$_btb_e" ] || return 1
  if [ "${_btb_e%% *}" != 100644 ] && [ "${_btb_e%% *}" != 100755 ]; then return 2; fi   # MUT-BPREG
  _btb_o=${_btb_e#* }; _btb_o=${_btb_o#* }; _btb_o=${_btb_o%%"$(printf '\t')"*}
  git -C "$1" cat-file blob "$_btb_o" 2>/dev/null || return 2
}
read_merge_relationship() {
  REL_MODE=team; REL_TIPERR=0
  _rmr_dr=0; _rmr_d=$(bp_tip_blob "$1" .kit/dials.conf) || _rmr_dr=$?
  if [ "$_rmr_dr" = 3 ]; then REL_TIPERR=1; fi
  [ "$_rmr_dr" = 0 ] || return 0
  _rmr_v=$(printf '%s\n' "$_rmr_d" | grep -E '^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=' | tail -n1 \
    | sed -E 's/^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g; s/[[:space:]].*$//') || _rmr_v=""
  [ "$_rmr_v" = solo ] || return 0
  _rmr_cr=0; _rmr_c=$(bp_tip_blob "$1" CLAUDE.md) || _rmr_cr=$?
  if [ "$_rmr_cr" = 2 ]; then return 0; fi   # a CLAUDE.md that is not a regular file reads Governance team, as the verbs read it # MUT-BPGOV
  _rmr_g=undeclared
  if [ "$_rmr_cr" = 0 ]; then
    _rmr_gm=$GOV_MODE; _rmr_gn=$GOV_NOTE; _rmr_tf=$(mktemp) || return 0
    printf '%s\n' "$_rmr_c" > "$_rmr_tf"; read_governance "$_rmr_tf"; _rmr_g=$GOV_MODE; GOV_MODE=$_rmr_gm; GOV_NOTE=$_rmr_gn; rm -f "$_rmr_tf"
  fi
  if [ "$_rmr_g" != team ]; then REL_MODE=solo; fi
  return 0
}

# bp_solo_agent_ok <body> — 0 only when the solo-agent state is complete: solo-go-bound is declared in REQUIRED-CHECKS.md, is a LIVE required
# check, and the tree carries the installed workflow and the verbs' go-bound marker. Otherwise 1, with SA_MISSING naming the first missing piece.
bp_solo_agent_ok() {
  SA_MISSING=""
  if [ ! -f "$DECLARATION" ]; then SA_MISSING="there is no declaration file ($DECLARATION)"; return 1; fi
  read_declaration "$DECLARATION"
  printf '%s\n' $RD_LIST | grep -qxF solo-go-bound || { SA_MISSING="solo-go-bound is not declared in $DECLARATION"; return 1; }
  extract_live_contexts "$1" | grep -qxF solo-go-bound || { SA_MISSING="solo-go-bound is not a live required check on $BRANCH"; return 1; }
  bp_rsc_text "$1" | tr -d ' \t' | grep -qE '"context":"solo-go-bound","app_id":15368[,}]' || { SA_MISSING="solo-go-bound is not pinned to the GitHub Actions app (app_id 15368), so another app's same-named check could satisfy it"; return 1; }   # MUT-BPPIN
  if [ -f "$REPO_ROOT/.github/workflows/solo-go.yml" ] && grep -qF 'COPY & ADAPT' "$REPO_ROOT/.github/workflows/solo-go.yml"; then :; else SA_MISSING="the solo-go workflow is not installed in this tree (.github/workflows/solo-go.yml)"; return 1; fi
  if [ -f "$REPO_ROOT/scripts/promotion-verify.sh" ] && grep -qF '# KIT-MODE: go-bound' "$REPO_ROOT/scripts/promotion-verify.sh"; then :; else SA_MISSING="this tree's merge verbs have no go-bound verb"; return 1; fi
  return 0
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
    # SWAS-901: the ONE tree that may run with approvals=0 declares solo AND has the check that stands in for the approval (see bp_solo_agent_ok).
    # Every other tree keeps the arms below byte for byte; a symlinked or unreadable dial file reads team.
    SA_OK=0; SA_MISSING=""
    read_merge_relationship "$REPO_ROOT"
    if [ "$REL_MODE" = solo ] && bp_solo_agent_ok "$body"; then SA_OK=1; fi
    # E6 R2-2: a missing origin/<branch> ref cannot say whether the tree is solo; where the checked-out tree CLAIMS solo, that is UNVERIFIED (name the fetch), never the team ZERO text
    if [ "${_bp_rc_count:-9}" = 0 ] && [ "$REL_TIPERR" = 1 ] && grep -qE '^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=[[:space:]]*"?solo' "$REPO_ROOT/.kit/dials.conf" 2>/dev/null; then unverifiable "cannot read origin/$BRANCH: git fetch origin $BRANCH (a zero-approval state is judged by the dial and CLAUDE.md on that tip, never by the checked-out tree)"; fi   # MUT-BPTIPERR
    if [ "${_bp_rc_count:-9}" = 0 ] && [ "$REL_MODE" = solo ]; then
      if [ "$SA_OK" = 1 ]; then
        printf '%s\n' "OK-solo: approvals=0 — solo-go-bound reads the recorded GO in place of a review"
      else
        printf '%s\n' "FAIL: $BRANCH sets required_approving_review_count=0 on a tree that declares solo, but the solo-agent state is incomplete: $SA_MISSING. With zero approvals only solo-go-bound can hold a merge, so it must be declared, installed and live before the count drops. Cure (an admin act, done by a human): sh scripts/branch-protection-apply.sh --replace, which chooses the profile from the forge itself."; ok=1  # MUT-BPSOLO
      fi
    elif [ -z "$_bp_rc_count" ]; then
      printf '%s\n' "FAIL: $BRANCH does not declare required_approving_review_count — the merge of an unratified control-plane PR is blocked by that count, and the control-plane-ratification check is GREEN while waiting BECAUSE of it (DEVELOPMENT-PROCESS.md §13). Absent, nothing blocks. Fix it (an admin act, done by a human) in the Settings UI (Branches → edit the rule → 'Require a pull request before merging' → approvals 1 or more), not with branch-protection-apply.sh --apply, which only adds status-check contexts. branch-protection-apply.sh --replace also sets it, but rewrites the whole rule to a profile: the default (solo) turns enforce_admins and code-owner review off and pins the repo's merge methods to squash-only; on a team repo use --replace --team."; ok=1  # MUT-BPCOUNT
    elif [ "$_bp_rc_count" -lt 1 ]; then
      printf '%s\n' "FAIL: $BRANCH sets required_approving_review_count=$_bp_rc_count — a review requirement of ZERO. The required_pull_request_reviews block being PRESENT means nothing on its own; with a count of 0 an unratified control-plane PR merges with a GREEN ratification check (that check explains the wait, it does not block it). Fix it (an admin act, done by a human) with the admin PATCH (not branch-protection-apply.sh --apply, which only adds status-check contexts): gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F required_approving_review_count=1, or the Settings UI (Branches → edit the rule → 'Require approvals', 1 or more). branch-protection-apply.sh --replace also sets it, but rewrites the whole rule to a profile: the default (solo) turns enforce_admins and code-owner review off and pins the repo's merge methods to squash-only; on a team repo use --replace --team."; ok=1  # MUT-BPCOUNT
    fi
    if [ "${_bp_rc_count:-0}" = 1 ] && [ "$REL_MODE" = solo ]; then printf '%s\n' "ADVISORY: solo-declared but approvals=1 — the agent cannot merge on a recorded GO while one approval is required; run sh scripts/branch-protection-apply.sh --replace (an admin act at a terminal) once solo-go-bound is declared, installed and live."; fi
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
    # count arms above no longer end in `Run: ... --apply` either (SWAS-164): the count-below-1 arm
    # names the same admin PATCH, the count-absent arm (no review count, usually no reviews block at
    # all) leads with the Settings UI, and both name `--replace` with its rewrite-to-a-profile caveat. Only the
    # declared-context arm keeps `--apply`, because adding contexts is what it does. The two flag arms below lead with the
    # Settings UI when the reviews block is absent (SWAS-812).
    _bp_rc_flat=$(printf '%s' "$body" | tr -d ' \t\n')
    # ONE-ACT GO (SWAS-727): when this tree's dial file sets GO_ACT=review, an APPROVED review on the head IS the merge GO, and
    # this setting is what lets a later push retire it. The assertion above is unconditional (it already was); the FAIL says why
    # it matters more under `review`. The reader is the dial file's own, parsed and never sourced.
    _bp_goact=""
    if go_act_review "$REPO_ROOT"; then
      _bp_goact=" This tree's .kit/dials.conf sets GO_ACT=review: there an APPROVED review on the head is the merge GO, so a push that does not dismiss it leaves the GO standing on a head nobody approved."
    fi
    # SWAS-812: with no reviews block at all, a PATCH of one key may have nothing to patch, so the two cures below lead with
    # the Settings UI there (the count-absent arm's shape); with the block present they stay the admin PATCH, byte for byte.
    _bp_rv_absent=0; printf '%s' "$body" | grep -q '"required_pull_request_reviews"' || _bp_rv_absent=1  # MUT-BPSIB
    if [ "$_bp_rv_absent" = 1 ]; then
      _bp_ds_cure="Fix it (an admin act, done by a human) in the Settings UI (Branches → edit the rule → 'Require a pull request before merging' → 'Dismiss stale pull request approvals when new commits are pushed'), not with branch-protection-apply.sh --apply, which only adds status-check contexts. Once the rule requires pull requests, the admin PATCH sets it alone: gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F dismiss_stale_reviews=true. branch-protection-apply.sh --replace also sets it, but rewrites the whole rule to a profile: the default (solo) turns enforce_admins and code-owner review off and pins the repo's merge methods to squash-only; on a team repo use --replace --team."
      _bp_lp_cure="Fix it (an admin act, done by a human) in the Settings UI (Branches → edit the rule → 'Require a pull request before merging' → 'Require approval of the most recent reviewable push'), not with branch-protection-apply.sh --apply, which only adds status-check contexts. Once the rule requires pull requests, the admin PATCH sets it alone: gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F require_last_push_approval=true. branch-protection-apply.sh --replace also sets it, but rewrites the whole rule to a profile: the default (solo) turns enforce_admins and code-owner review off and pins the repo's merge methods to squash-only; on a team repo use --replace --team."
    else
      _bp_ds_cure="Fix it with the admin PATCH (NOT branch-protection-apply.sh --apply, which only adds status-check contexts): gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F dismiss_stale_reviews=true — or the Settings UI, Branches, edit the rule, 'Dismiss stale pull request approvals when new commits are pushed'."
      _bp_lp_cure="Fix it with the admin PATCH (NOT branch-protection-apply.sh --apply, which only adds status-check contexts): gh api -X PATCH repos/OWNER/REPO/branches/$BRANCH/protection/required_pull_request_reviews -F require_last_push_approval=true — or the Settings UI, Branches, edit the rule, 'Require approval of the most recent reviewable push'."
    fi
    printf '%s' "$_bp_rc_flat" | grep -q '"dismiss_stale_reviews":true' \
      || { printf '%s\n' "FAIL: $BRANCH does not set dismiss_stale_reviews to true — since REVIEW-LANE-WAITING-IS-GREEN (2026-09-05) this setting is what binds an approval to the exact head (review-lane no longer re-reads the forge to compare the approval's commit.oid). Without it an approval given before a fix push survives that push, and a tree nobody looked at merges on a review of a different tree. ${_bp_ds_cure}${_bp_goact}"; ok=1; }
    _bp_sa=0; [ "${_bp_rc_count:-9}" = 0 ] && [ "$SA_OK" = 1 ] && _bp_sa=1
    if [ "$_bp_sa" = 1 ] && [ "$(bp_enforce_admins "$_bp_rc_flat")" != true ]; then printf '%s\n' "FAIL: the solo-agent state needs enforce_admins on: the solo-agent profile sets enforce_admins:true (Q6), but $BRANCH has it off, so an admin could merge past solo-go-bound. Cure (an admin act, done by a human): sh scripts/branch-protection-apply.sh --replace."; ok=1; fi  # MUT-BPSOLO
    printf '%s' "$_bp_rc_flat" | grep -q '"require_last_push_approval":true' \
      || [ "$_bp_sa" = 1 ] \
      || { printf '%s\n' "FAIL: $BRANCH does not set require_last_push_approval to true — since REVIEW-LANE-WAITING-IS-GREEN (2026-09-05) this setting replaces review-lane's deleted rl_role_swap heuristic, which guessed at the role swap by matching an approver's forge login against the head commit's author/committer identity. As a server-side rule it is stronger and it is the only control left for the property: without it whoever pushed the head can approve their own push. ${_bp_lp_cure}"; ok=1; }
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
  # A free private repository's 403 carries GitHub's own upgrade text in the body (gh prints it on stdout): name the
  # cause in doctor's wording (scripts/doctor.sh, mirror-locked by the selftest) so nobody chases a missing admin right.
  if printf '%s' "$body" | grep -qF 'or make this repository public to enable this feature'; then   # MUT-BPPLAN
    unverifiable "protection endpoint returned non-200 on ${REPO:-?}: this plan cannot enforce protection on a private repository (a public repository or a paid plan can)"
  fi
  unverifiable "protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on ${REPO:-?}"
}

# gather_team_state — the live-leg reads classify() judges beyond the protection body: the tree's declared
# governance mode, the repo's merge methods (`gh api repos/OWNER/REPO`; unknown when the token cannot read
# the three fields), and which CODEOWNERS logins have only a pending invitation (`.../invitations`;
# INVITES_STATE=unreadable when the token cannot read it). Read-only GETs; GH env containment applies.
gather_team_state() {
  read_governance "$REPO_ROOT/CLAUDE.md"
  if _gts_repo=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh api "repos/$REPO" --jq "$MM_JQ" 2>/dev/null); then
    MERGE_METHODS=$(parse_merge_methods "$_gts_repo")
  else
    MERGE_METHODS=unknown
  fi
  if _gts_inv=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh api --paginate "repos/$REPO/invitations" --jq '.[].invitee.login' 2>/dev/null); then
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
  gh_identity_line
  REPO="$REPO_ARG"
  if [ -z "$REPO" ]; then REPO=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true); fi
  [ -n "$REPO" ] || unverifiable "no GitHub repo context for the gh identity above (pass --repo=OWNER/REPO, or use an account that can read this repo)"
  valid_repo "$REPO" || unverifiable "gh reported a repository name that is not OWNER/REPO (characters A-Za-z0-9._- only, no . or .. segment), so no API path is built from it"
  PROT=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null) && rc=0 || rc=$?
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
  # SWAS-920: every classify cell below that does not build its own tree runs with REPO_ROOT = _bphroot, a fixture git repo with no dial and
  # no Governance line (it reads team), so the real tree's merge relationship (a solo-declared adopter's included) never reaches a cell.
  _bphroot=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the hermetic team root"; st=1; }
  git init -q "$_bphroot" 2>/dev/null || true
  cls() {  # expect_rc require rc body label [declaration-file]
    e=$1; req=$2; r=$3; b=$4; lbl=$5; d=${6:-/nonexistent-required-checks-$$}
    ( REQUIRE="$req"; REPO=selftest; DECLARATION="$d"; REPO_ROOT="$_bphroot"; classify "$r" "$b" ) >/dev/null 2>&1 && g=0 || g=$?
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
  trap 'rm -rf "$_bpdir" "$_ghdir" "$_ghenvdir" "$_bphroot" 2>/dev/null || true' EXIT
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
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="$d"; REPO_ROOT="$_bphroot"; classify "$r" "$b" ) 2>&1 ) && g=0 || g=$?   # MUT-BPHROOT
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

  # ── SWAS-727 (test 14): dismiss_stale_reviews OFF is a FAIL in every mode (it already was: REVIEW-LANE-WAITING-IS-GREEN), and
  # under GO_ACT=review the FAIL also says why it matters most. The design said "print-only when the dial is absent"; this tree
  # asserts it unconditionally, so the cell pins that the assertion was NOT weakened as well as that the reason text appears.
  _goon="$_bpdir/goact-on"; mkdir -p "$_goon/.kit"; printf 'GO_ACT=review\nGO_GIVERS=owner-login\n' > "$_goon/.kit/dials.conf"
  _gooff="$_bpdir/goact-off"; mkdir -p "$_gooff/.kit"; printf 'MERGE_RELATIONSHIP=team\n' > "$_gooff/.kit/dials.conf"
  _gosep="$_bpdir/goact-sep"; mkdir -p "$_gosep/.kit"; printf 'GO_ACT=separate\n' > "$_gosep/.kit/dials.conf"
  gact() {  # want-the-GO_ACT-sentence(yes|no) root label
    out=$( ( REQUIRE=0; REPO=selftest; REPO_ROOT="$2"; DECLARATION="/nonexistent-required-checks-$$"
             classify 0 '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":false,"require_last_push_approval":true},"required_status_checks":{}}' ) 2>&1 ) && g=0 || g=$?
    has=no; printf '%s\n' "$out" | grep -qF -e 'GO_ACT=review: there an APPROVED review' && has=yes
    if [ "$g" = 1 ] && printf '%s\n' "$out" | grep -qF -e 'does not set dismiss_stale_reviews' && [ "$has" = "$1" ]; then
      echo "selftest PASS: $3 -> exit $g"
    else
      echo "selftest FAIL: $3 want rc=1 + sentence=$1 got rc=$g sentence=$has out=[$out]"; st=1
    fi
  }
  gact yes "$_goon" "dismiss_stale_reviews off + GO_ACT=review -> FAIL, naming why it matters under the one-act GO"
  gact no "$_gooff" "dismiss_stale_reviews off + the dial absent -> still FAIL (not weakened), without the GO_ACT sentence"
  gact no "$_gosep" "dismiss_stale_reviews off + GO_ACT=separate -> still FAIL, without the GO_ACT=review sentence"
  gact no "$_bpdir/no-such-root" "dismiss_stale_reviews off + no dial file at all -> still FAIL"

  # ── SWAS-901 slice B (T15a-f): the solo-agent state. A tree that declares MERGE_RELATIONSHIP=solo (a regular dial file, no Governance
  # team override), lists solo-go-bound in REQUIRED-CHECKS.md, carries the installed workflow and the verbs' go-bound marker, and whose
  # protection has solo-go-bound live may run with approvals=0, last_push=false and enforce_admins=true. Every other tree keeps today's
  # verdicts, byte for byte. A mutant is a sed copy of THIS script: its read_merge_relationship, bp_solo_agent_ok and classify are
  # extracted and sourced inside the cell's subshell (classify is only ever run in one), and the cell must then FAIL.
  # SWAS-901 E6 S-4/R1: the dial and CLAUDE.md are read from the default branch's TIP (refs/remotes/origin/<branch>), never the checked-out tree, and a
  # symlink or other non-regular entry reads team, so each fixture is a git repository with that ref; the workflow, the verbs' marker and
  # REQUIRED-CHECKS.md are still read from the tree.
  _sa_git() { git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -C "$_sar" "$@"; }
  _sa_mk() {  # <name> <tip dial: solo|team|link|none> <tip CLAUDE.md: none|link|team> [<dial the working tree has AFTER the tip: solo|team>] -> a tree root under $_bpdir
    _sar="$_bpdir/$1"; rm -rf "$_sar"; mkdir -p "$_sar/.kit" "$_sar/.github/workflows" "$_sar/scripts"; git init -q "$_sar"
    if [ "$2" = link ]; then ln -s MERGE_RELATIONSHIP=solo "$_sar/.kit/dials.conf"; elif [ "$2" != none ]; then printf 'MERGE_RELATIONSHIP=%s\n' "$2" > "$_sar/.kit/dials.conf"; fi
    if [ "$3" = link ]; then ln -s x "$_sar/CLAUDE.md"; elif [ "$3" = team ]; then printf -- '- **Governance** (§ solo/team): team\n' > "$_sar/CLAUDE.md"; fi
    : > "$_sar/f"; _sa_git add -A; _sa_git commit -q -m tip; _sa_git update-ref refs/remotes/origin/main HEAD
    if [ -n "${4:-}" ]; then printf 'MERGE_RELATIONSHIP=%s\n' "$4" > "$_sar/.kit/dials.conf"; _sa_git add -A; _sa_git commit -q -m tree; fi
    printf '```\nci\nsolo-go-bound\n```\n' > "$_sar/REQUIRED-CHECKS.md"
    printf '# COPY & ADAPT\n' > "$_sar/.github/workflows/solo-go.yml"
    printf '# KIT-MODE: go-bound\n' > "$_sar/scripts/promotion-verify.sh"
  }
  _sa_src=""
  _sa_chk() {  # <expect rc> <needle> <root> <count> <last_push> <enforce_admins> <contexts json> [nopin] -> 0 when rc and needle match
    _sack=',"checks":[{"context":"solo-go-bound","app_id":15368}]'; if [ "${8:-}" = nopin ] || [ "${8:-}" = stray ]; then _sack=''; fi
    if [ "${8:-}" = pin153680 ]; then _sack=',"checks":[{"context":"solo-go-bound","app_id":153680}]'; fi   # R5-1: a longer app id has 15368 as a prefix
    if [ "${8:-}" = strayunpin ]; then _sack=',"checks":[{"context":"solo-go-bound"}]'; fi   # R4-1: unpinned INSIDE the object, the pinned text outside it
    _sarsc="\"contexts\":$7$_sack"
    if [ "$7" = CHECKS ]; then _sarsc='"strict":true,"checks":[{"context":"ci"},{"context":"solo-go-bound","app_id":15368}]'; fi   # a body with ONLY checks[] (E6 R2-1)
    _sab="{\"required_pull_request_reviews\":{\"required_approving_review_count\":$4,\"dismiss_stale_reviews\":true,\"require_last_push_approval\":$5},\"required_status_checks\":{$_sarsc},\"enforce_admins\":{\"enabled\":$6}}"
    if [ "${8:-}" = stray ] || [ "${8:-}" = strayunpin ]; then   # E6 R3-2: the pinned solo-go-bound text sits in "context" keys OUTSIDE required_status_checks, before it and after it
      _sast='[{"context":"solo-go-bound","app_id":15368}]'; _sab="{\"statuses\":$_sast,${_sab#\{}"; _sab="${_sab%\}},\"restrictions\":{\"checks\":$_sast}}"
    fi
    # shellcheck source=/dev/null  # the mutant's extracted functions, written by _sa_mut below
    out=$( ( if [ -n "$_sa_src" ]; then . "$_sa_src"; fi; REQUIRE=0; REPO=selftest; REPO_ROOT="$3"; DECLARATION="$3/REQUIRED-CHECKS.md"; classify 0 "$_sab" ) 2>&1 ) && g=0 || g=$?
    [ "$g" = "$1" ] && printf '%s\n' "$out" | grep -qF -e "$2"
  }
  _sa_ctx='["ci","solo-go-bound"]'
  _sa_mk sa-ok solo none; _sa_mk sa-team team none; _sa_mk sa-link link none; _sa_mk sa-clink solo link; _sa_mk sa-tip team none solo
  _sa_mk sa-noref solo none; _sa_git update-ref -d refs/remotes/origin/main   # a checkout that never fetched origin's default branch
  _sa_ta() { _sa_chk 0 'OK-solo: approvals=0' "$_bpdir/sa-ok" 0 false true "$_sa_ctx"; }
  _sa_tb() { _sa_chk 1 'is not a live required check' "$_bpdir/sa-ok" 0 false true '["ci"]'; }
  _sa_tc() { _sa_chk 1 'a review requirement of ZERO' "$_bpdir/sa-team" 0 false true "$_sa_ctx"; }
  _sa_td() { _sa_chk 0 'ADVISORY: solo-declared but approvals=1' "$_bpdir/sa-ok" 1 true true "$_sa_ctx"; }
  _sa_te() { _sa_chk 1 'a review requirement of ZERO' "$_bpdir/sa-link" 0 false true "$_sa_ctx"; }
  _sa_tf() { _sa_chk 1 'sets enforce_admins:true (Q6)' "$_bpdir/sa-ok" 0 false false "$_sa_ctx"; }
  _sa_cell() { if "$2"; then echo "selftest PASS: $1: $3"; else echo "selftest FAIL: $1: $3"; st=1; fi; }
  _sa_mut() {  # <label> <sed> <cell> <desc>
    _sam="$_bpdir/sa-mut-$1.sh"; sed "$2" "$0" > "$_sam.full"
    if cmp -s "$0" "$_sam.full"; then echo "selftest FAIL: $1: the mutant changed nothing"; st=1; return 0; fi
    : > "$_sam"; for _saf in bp_rsc_text extract_live_contexts bp_tip_blob read_merge_relationship bp_solo_agent_ok classify; do sed -n "/^$_saf() {\$/,/^}\$/p" "$_sam.full" >> "$_sam"; done
    _sa_src="$_sam"
    if "$3"; then echo "selftest FAIL: $1: $4 -- the mutant SURVIVED"; st=1; else echo "selftest PASS: $1: $4 (the mutant is killed)"; fi
    _sa_src=""
  }
  _sa_cell T15a _sa_ta "a solo tree with every piece, approvals=0, last_push=false, enforce_admins=true: OK-solo, rc 0"
  _sa_mut T15am '/OK-solo: approvals=0/s/^.*$/        :/' _sa_ta "a verifier that never prints the solo line fails the liveness cell"
  _sa_cell T15b _sa_tb "solo-go-bound declared but not a live required check: FAIL naming it"
  _sa_mut T15bm '/extract_live_contexts "\$1" | grep -qxF solo-go-bound/d' _sa_tb "without the live-context leg a missing check still reads solo-agent"
  _sa_cell T15c _sa_tc "a team tree with count 0: today's FAIL text (a review requirement of ZERO)"
  _sa_mut T15cm 's/ && \[ "\$REL_MODE" = solo \]; then$/; then/' _sa_tc "accepting count 0 on a team tree changes the FAIL text"
  _sa_cell T15d _sa_td "a solo tree at approvals=1: OK plus an ADVISORY that the agent cannot merge"
  _sa_mut T15dm '/solo-declared but approvals=1/d' _sa_td "without the advisory a locked-out solo tree reads clean"
  _sa_cell T15e _sa_te "a symlinked dial file reads team (S-3): count 0 is today's FAIL"
  _sa_mut T15em '/MUT-BPREG$/d' _sa_te "reading a symlink's target text as the file lets a link grant solo-agent"
  _sa_tg() { _sa_chk 1 'not pinned to the GitHub Actions app' "$_bpdir/sa-ok" 0 false true "$_sa_ctx" nopin; }
  _sa_th() { _sa_chk 1 'a review requirement of ZERO' "$_bpdir/sa-clink" 0 false true "$_sa_ctx"; }
  _sa_ti() { _sa_chk 1 'a review requirement of ZERO' "$_bpdir/sa-tip" 0 false true "$_sa_ctx"; }
  _sa_cell T15g _sa_tg "solo-go-bound live but not pinned to the Actions app (app_id 15368): FAIL naming the pin"
  _sa_mut T15gm '/MUT-BPPIN$/d' _sa_tg "without the pin leg another app's same-named check reads solo-agent"
  _sa_tj() { _sa_chk 0 'OK-solo: approvals=0' "$_bpdir/sa-ok" 0 false true CHECKS; }
  _sa_tk() { _sa_chk 2 'cannot read origin/main: git fetch origin main' "$_bpdir/sa-noref" 0 false true "$_sa_ctx" && ! printf '%s\n' "$out" | grep -qF 'a review requirement of ZERO'; }
  _sa_cell T15j _sa_tj "a solo-agent body that carries ONLY checks[] (no contexts key) is read, so every declared context is still asserted live"
  _sa_mut T15jm '/MUT-BPCHK$/d' _sa_tj "without the checks[] read a body in the solo-agent shape reads every context as unbound"
  _sa_cell T15k _sa_tk "a solo-declared tree whose origin/<branch> ref is missing reads UNVERIFIED naming the fetch, never the team ZERO FAIL"
  _sa_mut T15km '/MUT-BPTIPERR$/d' _sa_tk "restoring the team fallback blames a missing ref on the review count"
  _sa_cell T15h _sa_th "a symlinked CLAUDE.md reads Governance team (R1): count 0 is today's FAIL"
  _sa_mut T15hm '/MUT-BPGOV$/d' _sa_th "reading a symlinked CLAUDE.md as no Governance line grants solo-agent"
  _sa_cell T15i _sa_ti "the dial in the checked-out tree says solo but the default branch's tip says team (S-4): count 0 is today's FAIL"
  _sa_mut T15im 's@refs/remotes/origin/\$BRANCH@HEAD@g' _sa_ti "reading the checked-out tree instead of the default tip lets a PR grant itself solo-agent"
  _sa_cell T15f _sa_tf "the solo-agent state with enforce_admins false: FAIL (the profile writes true)"
  _sa_mut T15fm '/\[ "\$_bp_sa" = 1 \] && \[ "\$(bp_enforce_admins/d' _sa_tf "without the enforce leg an admin bypass reads solo-agent"
  # E6 R3-2/R9: a "context" key outside required_status_checks binds nothing (the POSIX reader is forced: jq is shadowed to fail, so the
  # scoped sed path is the one under test), and a context named in both contexts[] and checks[] reads once.
  _sa_tl() { ( jq() { return 1; }; _sa_chk 1 'is not a live required check' "$_bpdir/sa-ok" 0 false true '["ci"]' stray ); }
  _sa_tn() {
    _sa_nb='{"required_status_checks":{"strict":true,"contexts":["ci","solo-go-bound"],"checks":[{"context":"ci"},{"context":"solo-go-bound","app_id":15368}]}}'
    # shellcheck source=/dev/null  # the mutant's extracted functions, written by _sa_mut
    [ "$( ( jq() { return 1; }; if [ -n "$_sa_src" ]; then . "$_sa_src"; fi; extract_live_contexts "$_sa_nb" ) | grep -c '^ci$' )" = 1 ]
  }
  _sa_cell T15l _sa_tl "a pinned solo-go-bound \"context\" key before and after required_status_checks (not inside it) does not bind: FAIL not a live required check"
  _sa_mut T15lm '/MUT-BPSCOPE$/s/^.*$/  printf "%s" "$1"/' _sa_tl "the unscoped read counts any \"context\" key in the body as a required check"
  _sa_tp() { _sa_chk 1 'not pinned to the GitHub Actions app' "$_bpdir/sa-ok" 0 false true "$_sa_ctx" strayunpin; }
  _sa_cell T15p _sa_tp "an UNPINNED solo-go-bound inside required_status_checks with the pinned text only outside it: FAIL naming the pin (R4-1)"
  _sa_mut T15pm '/MUT-BPPIN$/s/bp_rsc_text "\$1"/printf "%s" "$1"/' _sa_tp "an unscoped pin grep reads a pin written outside the object as the check's own"
  _sa_tq() { _sa_chk 1 'not pinned to the GitHub Actions app' "$_bpdir/sa-ok" 0 false true "$_sa_ctx" pin153680; }
  _sa_cell T15q _sa_tq "solo-go-bound pinned to app_id 153680 (15368 only as a prefix): FAIL naming the pin (R5-1)"
  _sa_mut T15qm '/MUT-BPPIN$/s/15368\[,}\]/15368/' _sa_tq "a pin match with no end anchor reads another app's id as the Actions app"
  _sa_cell T15n _sa_tn "a context named in both contexts[] and checks[] reads once"
  _sa_mut T15nm '/^  } | sort -u$/s/sort -u/cat/' _sa_tn "without sort -u a doubly named context reads twice"

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

  # GH env (SEC M-3, narrowed by SWAS-198): GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/GITHUB_ENTERPRISE_TOKEN
  # must never reach the gh subprocess (stale-state hygiene); GH_TOKEN and GH_CONFIG_DIR (which pick the
  # operator's account) must reach it. Proven with a stub gh that dumps its OWN environment under a
  # `== ARGS: <args>` header per call, so each env block is tied to its call. Every cell that expects the
  # non-CI identity read sets CI='' (ci.yml runs this selftest with CI=true).
  _ghenvdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the GH-env fixture"; st=1; }
  _ghenvlog="$_ghenvdir/env.log"
  : > "$_ghenvlog"
  cat > "$_ghenvdir/gh" <<STUB
#!/bin/sh
printf '== ARGS: %s\n' "\$*" >> "$_ghenvlog"
env | grep -e '^GH_' -e '^GITHUB_ENTERPRISE_TOKEN=' | sed 's/^\([A-Za-z_]*TOKEN\)=.*/\1=<set>/' | sort >> "$_ghenvlog" 2>/dev/null || true
case "\$*" in
  *"api user"*) [ -z "\${STUB_USER_FAIL:-}" ] || exit 1; echo "\${STUB_USER_OUT:-stub-login}" ;;
  *"repo view"*) echo "\${STUB_REPO_OUT:-me/repo}" ;;
  *"branches/main/protection"*) [ -z "\${STUB_PROT_FAIL:-}" ] || exit 1; printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' ;;
  *) printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{"contexts":[]}}' ;;
esac
STUB
  chmod +x "$_ghenvdir/gh"
  # blk <log> <header-needle> — the env block(s) recorded under the call(s) whose header holds the needle.
  blk() { awk -v h="$2" '/^== ARGS: /{p=(index($0,h)>0)} p' "$1"; }
  # redact — failure diagnostics show variable NAMES only (an ambient credential must never be echoed).
  redact() { sed 's/^\([A-Za-z_][A-Za-z_]*\)=.*/\1=<withheld>/'; }
  _evil_env() { env GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=evil-ent-token GITHUB_ENTERPRISE_TOKEN=evil-gh-ent GH_CONFIG_DIR=/op-config GH_TOKEN=real-op-token "$@"; }
  : > "$_ghenvlog"
  _evil_env CI='' PATH="$_ghenvdir:$PATH" sh "$0" --raw >"$_ghenvdir/out" 2>"$_ghenvdir/err" && _idrc=0 || _idrc=$?
  # C1 (= A1+A2+A3). GH_CONFIG_DIR reaches gh; the four stale-state variables never do; GH_TOKEN does.
  _ncall=$(grep -c '^== ARGS: ' "$_ghenvlog" || true)
  _ncfg=$(grep -c '^GH_CONFIG_DIR=/op-config' "$_ghenvlog" || true)
  if [ "$_ncall" -gt 0 ] && [ "$_ncall" = "$_ncfg" ]; then
    echo "selftest PASS: GH_CONFIG_DIR (the operator's account selector) reaches EVERY gh call ($_ncfg of $_ncall)"
  else
    echo "selftest FAIL: GH_CONFIG_DIR was stripped (log: $(redact < "$_ghenvlog"))"; st=1
  fi
  for _sv in GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
    if grep -q "^$_sv=" "$_ghenvlog"; then
      echo "selftest FAIL: $_sv reached the gh subprocess (log: $(redact < "$_ghenvlog"))"; st=1
    else
      echo "selftest PASS: $_sv never reaches the gh subprocess"
    fi
  done
  if grep -q '^GH_TOKEN=<set>' "$_ghenvlog"; then
    echo "selftest PASS: GH_TOKEN (the operator's real credential) still reaches the gh subprocess"
  else
    echo "selftest FAIL: GH_TOKEN was stripped too (it must be honored, not contained) (log: $(redact < "$_ghenvlog"))"; st=1
  fi
  # The identity read and every later call (repo view, the protection GET) are contained too.
  _ub=$(blk "$_ghenvlog" "api user")
  if [ -n "$_ub" ] && ! printf '%s\n' "$_ub" | grep -q -e '^GH_HOST=' -e '^GH_REPO=' -e '^GH_ENTERPRISE_TOKEN=' -e '^GITHUB_ENTERPRISE_TOKEN='; then
    echo "selftest PASS: the identity read ran (api user) with the stale-state variables stripped"
  else
    echo "selftest FAIL: no api user call, or it carried a stripped variable (block: $(printf '%s\n' "$_ub" | redact))"; st=1
  fi
  # C5. the identity is on stderr only, before repo view, and moves neither stdout nor the exit code.
  _un=$(grep -n '^== ARGS: api user' "$_ghenvlog" | head -n 1 | cut -d: -f1)
  _rv=$(grep -n '^== ARGS: repo view' "$_ghenvlog" | head -n 1 | cut -d: -f1)
  cp "$_ghenvdir/out" "$_ghenvdir/out.ok"; _okrc=$_idrc
  if grep -qF 'acting gh identity: stub-login (credential: token in environment)' "$_ghenvdir/err" \
     && ! grep -qF 'acting gh identity' "$_ghenvdir/out" \
     && [ -n "$_un" ] && [ -n "$_rv" ] && [ "$_un" -lt "$_rv" ]; then
    echo "selftest PASS: the acting gh identity is named on stderr only, before repo view"
  else
    echo "selftest FAIL: identity line placement (err=[$(cat "$_ghenvdir/err")] api-user@$_un repo-view@$_rv)"; st=1
  fi
  _evil_env CI='' STUB_USER_FAIL=1 PATH="$_ghenvdir:$PATH" sh "$0" --raw >"$_ghenvdir/out" 2>"$_ghenvdir/err" && _idrc=0 || _idrc=$?
  if grep -qF 'acting gh identity: not resolved (credential: token in environment;' "$_ghenvdir/err" \
     && cmp -s "$_ghenvdir/out" "$_ghenvdir/out.ok" && [ "$_idrc" = "$_okrc" ]; then
    echo "selftest PASS: an unreadable identity says 'not resolved' and never moves stdout or the exit code"
  else
    echo "selftest FAIL: failed identity read (err=[$(cat "$_ghenvdir/err")] rc=$_idrc vs $_okrc)"; st=1
  fi
  # L2. a malformed login (space, control byte, over 39 characters) is never echoed: it reads 'not resolved'.
  _long=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  for _ml in 'bad login' 'x;rm' "$_long"; do
    _evil_env CI='' STUB_USER_OUT="$_ml" PATH="$_ghenvdir:$PATH" sh "$0" --raw >/dev/null 2>"$_ghenvdir/err" || true
    if grep -qF 'acting gh identity: not resolved' "$_ghenvdir/err" && ! grep -qF -e "$_ml" "$_ghenvdir/err"; then
      echo "selftest PASS: a malformed login is never echoed (L2)"
    else
      echo "selftest FAIL: malformed login reached the terminal (err=[$(cat "$_ghenvdir/err")])"; st=1
    fi
  done
  # L3. a repo name gh reports that is not OWNER/REPO is UNVERIFIED (rc 2) before any protection call.
  : > "$_ghenvlog"
  out=$(_evil_env CI='' STUB_REPO_OUT='../x' PATH="$_ghenvdir:$PATH" sh "$0" 2>&1) && g=0 || g=$?
  if [ "$g" = 2 ] && printf '%s\n' "$out" | grep -qF 'UNVERIFIED: gh reported a repository name that is not OWNER/REPO' && ! grep -qF 'branches/main/protection' "$_ghenvlog"; then
    echo "selftest PASS: an invalid repo name from gh is UNVERIFIED rc 2 with no protection call (L3)"
  else
    echo "selftest FAIL: invalid gh repo name (rc=$g out=[$out])"; st=1
  fi
  # C2. --repo=OWNER/REPO replaces `repo view`; the protection GET targets that repo; api user comes first.
  : > "$_ghenvlog"
  _evil_env CI='' PATH="$_ghenvdir:$PATH" sh "$0" --raw --repo=me/repo >/dev/null 2>&1 || true
  _un=$(grep -n '^== ARGS: api user' "$_ghenvlog" | head -n 1 | cut -d: -f1)
  _gt=$(grep -n '^== ARGS: api repos/me/repo/branches/main/protection' "$_ghenvlog" | head -n 1 | cut -d: -f1)
  if ! grep -q '^== ARGS: repo view' "$_ghenvlog" && [ -n "$_un" ] && [ -n "$_gt" ] && [ "$_un" -lt "$_gt" ]; then
    echo "selftest PASS: --repo=me/repo skips repo view and reads repos/me/repo/branches/main/protection after the identity read"
  else
    echo "selftest FAIL: --repo handling (api-user@$_un protection-get@$_gt log: $(redact < "$_ghenvlog"))"; st=1
  fi
  # C3. an invalid --repo is refused (rc 2, the specific wording) before ANY gh call.
  for _bad in 'a/b/c' '../x' 'a/..' './x' 'a b/c' '/x' 'x/' ''; do
    : > "$_ghenvlog"
    out=$(CI='' PATH="$_ghenvdir:$PATH" sh "$0" --repo="$_bad" 2>&1) && g=0 || g=$?
    if [ "$g" = 2 ] && printf '%s\n' "$out" | grep -qF "invalid --repo" && ! grep -q . "$_ghenvlog"; then
      echo "selftest PASS: --repo='$_bad' refused (rc 2, no gh call)"
    else
      echo "selftest FAIL: --repo='$_bad' want rc 2 + 'invalid --repo' + no gh call, got rc=$g out=[$out]"; st=1
    fi
  done
  # C4. valid_repo parity: both copies, extracted from their files, give the same verdicts on one vector set.
  _vr_a=$(sed -n '/^valid_repo() {/,/^}/p' "$0")
  _vr_b=$(sed -n '/^valid_repo() {/,/^}/p' "$REPO_ROOT/scripts/branch-protection-apply.sh")
  _vr_bad=0
  for _vv in 'me/repo' 'a.b/c-d_e' 'ab' 'a/b/c' '../x' 'a/..' './x' 'a/.' 'a b/c' '/x' 'x/' 'a?b/c' ''; do
    _va=$( eval "$_vr_a"; if valid_repo "$_vv"; then echo valid; else echo invalid; fi )
    _vb=$( eval "$_vr_b"; if valid_repo "$_vv"; then echo valid; else echo invalid; fi )
    [ "$_va" = "$_vb" ] || { echo "selftest FAIL: valid_repo drift on '$_vv' (check=$_va apply=$_vb)"; st=1; _vr_bad=1; }
  done
  _va=$( eval "$_vr_a"; if valid_repo me/repo && ! valid_repo ../x; then echo anchored; fi )
  if [ "$_vr_bad" = 0 ] && [ "$_va" = anchored ]; then echo "selftest PASS: valid_repo gives the same verdicts in both scripts (and is not vacuous)"; else echo "selftest FAIL: valid_repo parity or anchors"; st=1; fi
  # C6. --repo is a live-leg flag: with --declared-only it is a usage error, in EITHER order, before any gh call.
  for _pair in '--declared-only --repo=me/repo' '--repo=me/repo --declared-only'; do
    : > "$_ghenvlog"
    # shellcheck disable=SC2086  # the two flags are deliberately word-split
    out=$(CI='' PATH="$_ghenvdir:$PATH" sh "$0" $_pair 2>&1) && g=0 || g=$?
    if [ "$g" = 2 ] && printf '%s\n' "$out" | grep -qF -e "cannot be combined with --declared-only" && ! grep -q . "$_ghenvlog"; then
      echo "selftest PASS: '$_pair' refused (rc 2, no gh call)"
    else
      echo "selftest FAIL: '$_pair' want rc 2 naming --repo and no gh call, got rc=$g out=[$out]"; st=1
    fi
  done
  # C7. under CI only the credential source is named (no API call, no login) and the escalation is unchanged:
  # an unreadable protection endpoint is rc 1 under CI, rc 2 without it.
  : > "$_ghenvlog"
  out=$(_evil_env CI=true STUB_PROT_FAIL=1 PATH="$_ghenvdir:$PATH" sh "$0" --repo=me/repo 2>"$_ghenvdir/err") && g=0 || g=$?
  _ci_api=$(grep -c '^== ARGS: api user' "$_ghenvlog" || true)
  _noc=$(env CI=true GH_TOKEN='' GITHUB_TOKEN='' PATH="$_ghenvdir:$PATH" sh "$0" --repo=me/repo 2>&1 >/dev/null) || true
  out2=$(_evil_env CI='' STUB_PROT_FAIL=1 PATH="$_ghenvdir:$PATH" sh "$0" --repo=me/repo 2>/dev/null) && g2=0 || g2=$?
  if [ "$g" = 1 ] && [ "$g2" = 2 ] && printf '%s\n' "$out" | grep -qF 'FAIL: branch-protection could not verify' \
     && printf '%s\n' "$out2" | grep -qF 'UNVERIFIED:' && grep -qF 'acting gh identity: not read in CI (credential: token in environment)' "$_ghenvdir/err" \
     && ! grep -qF 'stub-login' "$_ghenvdir/err" && [ "$_ci_api" = 0 ] \
     && printf '%s\n' "$_noc" | grep -qF 'acting gh identity: not read in CI (credential: none)'; then
    echo "selftest PASS: under CI the identity line names only the credential source (no API call, no login); escalation unchanged"
  else
    echo "selftest FAIL: CI identity line or escalation (rc=$g/$g2 err=[$(cat "$_ghenvdir/err")] none=[$_noc])"; st=1
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
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; GOV_MODE="$gov"; MERGE_METHODS="$mm"; INVITES_STATE=ok; PENDING_OWNERS="$pend"; REPO_ROOT="$_bphroot"; classify 0 "$b" ) 2>&1 ) && g=0 || g=$?   # MUT-BPHROOT
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  clst_not() {  # needle-must-be-absent variant: expect_rc needle require gov mm pend body label
    e=$1; needle=$2; req=$3; gov=$4; mm=$5; pend=$6; b=$7; lbl=$8
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; GOV_MODE="$gov"; MERGE_METHODS="$mm"; INVITES_STATE=ok; PENDING_OWNERS="$pend"; REPO_ROOT="$_bphroot"; classify 0 "$b" ) 2>&1 ) && g=0 || g=$?
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
  out=$( ( REQUIRE=0; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; GOV_MODE=solo; MERGE_METHODS=squash-only; INVITES_STATE=unreadable; PENDING_OWNERS=""; REPO_ROOT="$_bphroot"; classify 0 "$_SOLO_LIVE" ) 2>&1 ) && g=0 || g=$?
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
  for _dl in parse_merge_methods co_logins valid_branch valid_repo; do
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
  *"api user"*) echo stub-login ;;
  *"repo view"*) echo "me/repo" ;;
  *"/invitations"*) [ -z "${STUB_INVITES_FAIL:-}" ] || exit 1; for l in ${STUB_INVITES:-}; do echo "$l"; done ;;
  *"branches/main/protection"*) printf '%s' "$STUB_PROTECTION"; exit "${STUB_PROT_RC:-0}" ;;
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

  # ── SWAS-212: a free private repository's 403 names its cause. Real gh prints the message in the JSON body on
  # stdout, which run() captures; the cause is doctor's wording (scripts/doctor.sh), pinned on both sides below.
  _bp_plan='this plan cannot enforce protection on a private repository (a public repository or a paid plan can)'
  bp_up() { printf '%s' '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'; }
  clsd 2 "UNVERIFIED: protection endpoint returned non-200 on selftest: $_bp_plan" 0 1 "$(bp_up)" "/nonexistent-required-checks-$$" "upgrade-text 403 -> UNVERIFIED naming the plan cause (SWAS-212)"
  clsd 1 "FAIL: branch-protection could not verify (protection endpoint returned non-200 on selftest: $_bp_plan)" 1 1 "$(bp_up)" "/nonexistent-required-checks-$$" "upgrade-text 403 + --require -> FAIL, still naming the plan cause"
  out=$( ( REQUIRE=0; REPO=selftest; DECLARATION="/nonexistent-required-checks-$$"; REPO_ROOT="$_bphroot"; classify 1 '{"message":"Must have admin rights to Repository."}' ) 2>&1 ) && g=0 || g=$?
  if [ "$g" = 2 ] && printf '%s\n' "$out" | grep -qF 'non-200 (token may lack repo-admin' && ! printf '%s\n' "$out" | grep -qF -e "$_bp_plan"; then
    echo "selftest PASS: a plain 403 keeps the generic cause (rc alone is not the upgrade signal)"
  else
    echo "selftest FAIL: plain 403 cause (rc=$g out=[$out])"; st=1
  fi
  e2e "upgrade-text 403 through run(): the plan cause reaches stdout" 2 "$_bp_plan" "$(bp_up)" "$_RJ_SQ" STUB_PROT_RC=1
  # mutant: the recognition dropped (the anchor never matches) -> the positive cell above must red
  sed '/# MUT-BPPLAN$/s/or make this repository public to enable this feature/@@never-matches@@/' "$0" > "$_e2e/conformance/branch-protection.sh"
  if cmp -s "$0" "$_e2e/conformance/branch-protection.sh"; then
    echo "selftest FAIL: the MUT-BPPLAN mutant did not apply"; st=1
  else
    out=$( ( PATH="$_e2e/bin:$PATH"; STUB_PROTECTION="$(bp_up)"; STUB_REPOJSON="$_RJ_SQ"; STUB_PROT_RC=1; export STUB_PROTECTION STUB_REPOJSON STUB_PROT_RC; env CI='' REQUIRE=0 sh "$_e2e/conformance/branch-protection.sh" ) 2>&1 ) || true
    if printf '%s\n' "$out" | grep -qF -e "$_bp_plan" || ! printf '%s\n' "$out" | grep -qF 'non-200 (token may lack repo-admin'; then echo "selftest FAIL: the MUT-BPPLAN mutant survived or crashed (it must fall back to the generic cause) (the plan-cause cell would stay green)"; st=1; else echo "selftest PASS: the MUT-BPPLAN mutant is caught (the plan cause vanishes, the positive cell reds)"; fi
  fi
  cp "$0" "$_e2e/conformance/branch-protection.sh"
  # mirror lock: the cause wording is doctor's, and inception-done keys on it. Both producers must carry the whole phrase.
  if [ -f "$REPO_ROOT/scripts/doctor.sh" ]; then
    if grep -qF -e "$_bp_plan" "$REPO_ROOT/scripts/doctor.sh" && grep -qF -e "$_bp_plan" "$REPO_ROOT/conformance/inception-done.sh" && grep -E '^[[:space:]]+unverifiable "' "$0" | grep -qF -e "$_bp_plan"; then
      echo "selftest PASS: the plan-cause phrase is verbatim in doctor.sh, inception-done.sh and this script's unverifiable call (mirror lock)"
    else
      echo "selftest FAIL: the plan-cause wording drifted between scripts/doctor.sh and conformance/branch-protection.sh (inception-done keys on it too) — update ALL sides"; st=1
    fi
  else
    echo "selftest n/a: mirror lock skipped — scripts/doctor.sh absent on this tree"
  fi

  # ── SWAS-164: the two review-count FAILs name a cure that works. `--apply` only adds status-check contexts and
  # touches no review setting, so ending these lines `Run: ... --apply` sent an adopter to a command that succeeds and
  # leaves the gate red. Both bodies are real 200s (the arms sit inside the HTTP 200 branch), so the cells use classify().
  bp_cabs() { printf '%s' '{"required_status_checks":{}}'; }
  bp_c0() { printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":0,"dismiss_stale_reviews":true,"require_last_push_approval":true},"required_status_checks":{}}'; }
  _bp_old='Run: sh scripts/branch-protection-apply.sh --apply'
  clsd 1 "in the Settings UI (Branches → edit the rule → 'Require a pull request before merging' → approvals 1 or more)" 0 0 "$(bp_cabs)" "/nonexistent-required-checks-$$" "count ABSENT (no reviews block) -> FAIL whose cure leads with the Settings UI (SWAS-164)"
  clsd 1 "gh api -X PATCH repos/OWNER/REPO/branches/main/protection/required_pull_request_reviews -F required_approving_review_count=1" 0 0 "$(bp_c0)" "/nonexistent-required-checks-$$" "count of ZERO -> FAIL whose cure is the admin PATCH (SWAS-164)"
  clst_not 1 "$_bp_old" 0 undeclared unknown "" "$(bp_cabs)" "count ABSENT -> the FAIL never ends 'Run: ... --apply' (that command touches no review setting)"
  clst_not 1 "$_bp_old" 0 undeclared unknown "" "$(bp_c0)" "count of ZERO -> the FAIL never ends 'Run: ... --apply' (that command touches no review setting)"
  # mutant: both endings restored to the old `Run: ... --apply` -> each negative cell must red
  sed '/# MUT-BPCOUNT$/s|Fix it [^"]*"; ok=1|'"$_bp_old"'"; ok=1|' "$0" > "$_e2e/conformance/branch-protection.sh"
  if cmp -s "$0" "$_e2e/conformance/branch-protection.sh"; then
    echo "selftest FAIL: the MUT-BPCOUNT mutant did not apply"; st=1
  elif ! sh -n "$_e2e/conformance/branch-protection.sh" 2>/dev/null; then
    echo "selftest FAIL: the MUT-BPCOUNT mutant does not parse"; st=1
  else
    _bp_mut_ok=1
    for _bp_mf in bp_cabs bp_c0; do
      out=$( ( PATH="$_e2e/bin:$PATH"; STUB_PROTECTION="$($_bp_mf)"; STUB_REPOJSON="$_RJ_SQ"; export STUB_PROTECTION STUB_REPOJSON; env CI='' REQUIRE=0 sh "$_e2e/conformance/branch-protection.sh" ) 2>&1 ) || true
      printf '%s\n' "$out" | grep -qF -e "$_bp_old" || _bp_mut_ok=0
    done
    if [ "$_bp_mut_ok" = 1 ]; then echo "selftest PASS: the MUT-BPCOUNT mutant is caught (the old ending returns, both negative cells would red)"; else echo "selftest FAIL: the MUT-BPCOUNT mutant did not restore the old ending on both arms (the negative cells would stay green)"; st=1; fi
  fi
  cp "$0" "$_e2e/conformance/branch-protection.sh"

  # ── SWAS-920: the classify cells that expect team text set their own merge relationship (a fixture root with no dial and no
  # Governance line), never the real tree's, so a solo-declared adopter's own CI reads the same verdicts. The cell runs two of them
  # (clsd, clst) with the AMBIENT tree solo-declared (a git repo whose default-branch tip carries MERGE_RELATIONSHIP=solo); the mutant
  # (a sed copy, cmp-proven, its clsd and clst sourced) restores the real-tree read and must red it.
  _sa_mk ha-solo solo none
  _ha_src=""
  _ha_run() {  # 0 when both team-expecting cells still PASS while REPO_ROOT is the solo-declared tree
    # shellcheck source=/dev/null  # the mutant's extracted clsd and clst, written by the mutant block below
    _hao=$( ( REPO_ROOT="$_bpdir/ha-solo"; cd "$REPO_ROOT"; if [ -n "$_ha_src" ]; then . "$_ha_src"; fi
      clsd 1 "gh api -X PATCH repos/OWNER/REPO/branches/main/protection/required_pull_request_reviews -F required_approving_review_count=1" 0 0 "$(bp_c0)" "/nonexistent-required-checks-$$" "ha-clsd"
      clst 1 "a review requirement of ZERO" 0 undeclared unknown "" "$(bp_c0)" "ha-clst" ) 2>&1 ) || true
    printf '%s\n' "$_hao" | grep -qF 'selftest FAIL' && return 1
    [ "$(printf '%s\n' "$_hao" | grep -cF 'selftest PASS')" = 2 ]
  }
  if _ha_run; then echo "selftest PASS: SWAS-920: the team-expecting cells pass from inside a solo-declared tree (the selftest sets its own relationship)"; else echo "selftest FAIL: SWAS-920: a team-expecting cell read the real tree's solo relationship (out=[$_hao])"; st=1; fi
  _ham="$_bpdir/ha-mut.sh"; sed '/# MUT-BPHROOT$/s/REPO_ROOT="\$_bphroot"; //' "$0" > "$_ham.full"
  if cmp -s "$0" "$_ham.full"; then
    echo "selftest FAIL: SWAS-920: the MUT-BPHROOT mutant changed nothing"; st=1
  else
    : > "$_ham"; for _haf in clsd clst; do sed -n "/^  $_haf() {/,/^  }\$/p" "$_ham.full" >> "$_ham"; done
    _ha_src="$_ham"
    if _ha_run; then echo "selftest FAIL: SWAS-920: the MUT-BPHROOT mutant SURVIVED (restoring the real-tree read did not red the cell)"; st=1; else echo "selftest PASS: SWAS-920: restoring the real-tree read reds the cell (the mutant is killed)"; fi
    _ha_src=""
  fi

  # ── SWAS-812: the dismiss-stale and last-push FAILs lead with a cure that works when the reviews block is absent. With no
  # block a PATCH of one key may have nothing to patch, so those two lines lead with the Settings UI there (as SWAS-164's
  # count-absent line does); with the block present they stay the admin PATCH, byte for byte. Real 200 bodies, so classify().
  bp_nods() { printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1,"require_last_push_approval":true},"required_status_checks":{}}'; }
  bp_nolp() { printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true},"required_status_checks":{}}'; }
  _bp_sib_lead='Fix it with the admin PATCH (NOT branch-protection-apply.sh --apply, which only adds status-check contexts): gh api -X PATCH repos/OWNER/REPO/branches/main/protection/required_pull_request_reviews'
  _bp_sib_ds_abs="in the Settings UI (Branches → edit the rule → 'Require a pull request before merging' → 'Dismiss stale pull request approvals when new commits are pushed')"
  _bp_sib_lp_abs="in the Settings UI (Branches → edit the rule → 'Require a pull request before merging' → 'Require approval of the most recent reviewable push')"
  _bp_sib_ds_old="$_bp_sib_lead -F dismiss_stale_reviews=true — or the Settings UI"
  _bp_sib_lp_old="$_bp_sib_lead -F require_last_push_approval=true — or the Settings UI"
  clsd 1 "$_bp_sib_ds_abs" 0 0 "$(bp_cabs)" "/nonexistent-required-checks-$$" "dismiss_stale_reviews with NO reviews block -> FAIL whose cure leads with the Settings UI path to that box (SWAS-812)"
  clsd 1 "$_bp_sib_lp_abs" 0 0 "$(bp_cabs)" "/nonexistent-required-checks-$$" "require_last_push_approval with NO reviews block -> FAIL whose cure leads with the Settings UI path to that box (SWAS-812)"
  clsd 1 "$_bp_sib_ds_old" 0 0 "$(bp_nods)" "/nonexistent-required-checks-$$" "dismiss_stale_reviews missing, block PRESENT -> FAIL whose cure stays the admin PATCH (SWAS-812)"
  clsd 1 "$_bp_sib_lp_old" 0 0 "$(bp_nolp)" "/nonexistent-required-checks-$$" "require_last_push_approval missing, block PRESENT -> FAIL whose cure stays the admin PATCH (SWAS-812)"
  clst_not 1 "Once the rule requires pull requests" 0 undeclared unknown "" "$(bp_nods)" "dismiss_stale_reviews missing, block PRESENT -> the FAIL never carries the block-absent wording (SWAS-812)"
  clst_not 1 "Once the rule requires pull requests" 0 undeclared unknown "" "$(bp_nolp)" "require_last_push_approval missing, block PRESENT -> the FAIL never carries the block-absent wording (SWAS-812)"
  clst_not 1 "Fix it with the admin PATCH (NOT branch-protection-apply.sh --apply" 0 undeclared unknown "" "$(bp_cabs)" "NO reviews block -> neither flag line leads with the bare admin PATCH (SWAS-812)"
  # mutant: the absent flag pinned to 0 -> both lines print the block-present lead on a block-less body; each line asserted on its own
  sed '/# MUT-BPSIB$/s/.*/    _bp_rv_absent=0/' "$0" > "$_e2e/conformance/branch-protection.sh"
  if cmp -s "$0" "$_e2e/conformance/branch-protection.sh"; then
    echo "selftest FAIL: the MUT-BPSIB mutant did not apply"; st=1
  elif ! sh -n "$_e2e/conformance/branch-protection.sh" 2>/dev/null; then
    echo "selftest FAIL: the MUT-BPSIB mutant does not parse"; st=1
  else
    out=$( ( PATH="$_e2e/bin:$PATH"; STUB_PROTECTION="$(bp_cabs)"; STUB_REPOJSON="$_RJ_SQ"; export STUB_PROTECTION STUB_REPOJSON; env CI='' REQUIRE=0 sh "$_e2e/conformance/branch-protection.sh" ) 2>&1 ) || true
    _bp_sib_ok=1
    printf '%s\n' "$out" | grep -qF -e "$_bp_sib_ds_old" || _bp_sib_ok=0
    printf '%s\n' "$out" | grep -qF -e "$_bp_sib_lp_old" || _bp_sib_ok=0
    if [ "$_bp_sib_ok" = 1 ]; then echo "selftest PASS: the MUT-BPSIB mutant is caught (both lines print the old lead on a block-less body, the absent cells would red)"; else echo "selftest FAIL: the MUT-BPSIB mutant did not restore the old lead on both lines (the absent cells would stay green)"; st=1; fi
  fi
  cp "$0" "$_e2e/conformance/branch-protection.sh"

  [ "$st" = "0" ] && echo "branch-protection --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --declared-only) declared_only; exit $? ;;
  *) run ;;
esac
