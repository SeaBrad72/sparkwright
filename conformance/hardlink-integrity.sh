#!/bin/sh
# hardlink-integrity.sh — conformance gate (GUARD-CP-HARDLINK-ALIAS §2e). REDS if any TRACKED
# working-tree control-plane OR secret file has a hard-link count > 1, i.e. a second directory entry
# aliases the same inode. Names the offending file and its aliases so the fix is unambiguous.
#
# WHY THIS EXISTS. The runtime tool-route check (guard_check_path/guard_check_read) refuses to
# edit/read THROUGH a hardlink to a control-plane or secret file, but the COMMAND route stays a
# disclosed ceiling (`cp -l`/`install`-link/indirection create a link the argv scan does not catch).
# This gate BACKSTOPS the command-route creation on the one axis a commit-time gate can see: a
# hardlink to a *tracked control-plane* target, however it was created, shows the target with
# nlink>1. It uses git's own file list, so `.git/objects` (legitimately internally-hardlinked on a
# local clone) is never in scope and cannot false-red.
#
#   sh conformance/hardlink-integrity.sh            # scan the tracked working tree (the real run)
#   sh conformance/hardlink-integrity.sh --selftest # mutation-proof it has teeth
#
# ★ HONEST CEILING — read before trusting a green. This gate is BLIND to the UNTRACKED secret: a
# `.env` is normally gitignored, so it is not in `git ls-files` and never stat-ed here. The
# persistent secret cloak (`benign`->`.env`, `.env.example`->`.env`) is therefore NOT detected by
# this gate — its only defense is the tool-route runtime secret-inode check (design §2b/§4, vet
# MEDIUM-2). Do not read a green here as "no secret cloak present". Submodule CP files are likewise
# out of `git ls-files` scope (vet LOW-3). It backstops TRACKED control-plane nlink>1 only.
#
# What it changes: nothing — read-only; stats tracked control-plane/secret files.
# Guardrails: read-only; git ls-files + stat; no writes, no network.
# Exit: 0 = clean (or N/A: not a git repo) · 1 = a tracked CP/secret file has nlink>1 · 2 = usage.
# POSIX sh; dash-clean.
set -eu
# Resolve THIS script absolutely BEFORE the cd below — afterwards a relative $0 no longer resolves, so
# the --selftest legs that re-read/re-run this file (the nlink mutant, the trap probe) must use this.
HLI_SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/$(basename "$0")
cd "$(dirname "$0")/.." 2>/dev/null || true

# The classifiers (is_control_plane_path, _is_secret_path) and the portable stat helpers (_nlink_of,
# _devino_of) are the guard core's SINGLE SOURCE OF TRUTH — reused, never reinvented, so this gate
# cannot drift from what the runtime denies. KIT_HLI_CORE lets the --selftest mutant point a relocated
# copy at the same core by absolute path (its $0-relative sourcing would not otherwise resolve).
CORE="${KIT_HLI_CORE:-.claude/hooks/guard-core.sh}"
[ -f "$CORE" ] || { echo "hardlink-integrity: missing guard core ($CORE)" >&2; exit 2; }
# shellcheck disable=SC1090  # $CORE is the guard core (fixed default; KIT_HLI_CORE override for the selftest mutant) — non-constant to shellcheck, existence-checked above
case "$CORE" in /*) . "$CORE" ;; *) . "./$CORE" ;; esac

# scan_repo <dir> : rc0 = clean; rc1 = at least one tracked control-plane/secret file with nlink>1
# (each printed verbatim to stderr with its aliases). The _rc=1 accumulator is the load-bearing FAIL
# idiom the --selftest mutant neuters (remove the nlink test -> a hardlinked CP file passes -> RED).
scan_repo() {
  _dir=$1
  _rc=0
  _files=$( cd "$_dir" 2>/dev/null && git ls-files 2>/dev/null ) || {
    echo "N/A: $_dir is not a git repository (nothing tracked to scan)"; return 0; }
  _ofs=$IFS; IFS='
'
  for _f in $_files; do
    [ -n "$_f" ] || continue
    _p="$_dir/$_f"
    [ -f "$_p" ] || continue
    is_control_plane_path "$_f" || _is_secret_path "$_f" || continue
    _nl=$(_nlink_of "$_p") || continue          # unreadable count => not an integrity finding; skip
    [ "$_nl" -le 1 ] 2>/dev/null && continue     # nlink==1 => no alias (the load-bearing test)
    _di=$(_devino_of "$_p") || _di='0 0'; _ino=${_di##* }
    _al=$( cd "$_dir" 2>/dev/null && find . -xdev -inum "$_ino" -print 2>/dev/null | tr '\n' ' ' )
    echo "FAIL: tracked control-plane/secret file is hardlink-aliased: $_f (nlink=$_nl; names sharing its inode: $_al)" >&2
    _rc=1
  done
  IFS=$_ofs
  return $_rc
}

run() {
  if scan_repo .; then
    echo "OK: no tracked control-plane or secret file is hardlink-aliased (all nlink==1)"
    return 0
  fi
  return 1
}

# hli_mktempd — a fixture temp dir that HONOURS $TMPDIR. ⚠️ Measured on darwin: a bare `mktemp -d`
# with no template IGNORES $TMPDIR entirely (it lands in _CS_DARWIN_USER_TEMP_DIR), so the selftest's
# fixtures escaped any leg-private scope and a leak count taken there read 0 whether or not anything
# leaked. An EXPLICIT template is what makes the leak measurable at all (vet condition 6).
# ⚠️ hli_keep is called AT THE CALL SITE, never inside this function: every caller wraps it in a
# command substitution, which is a SUBSHELL — an accumulator appended in here would be discarded and
# the trap would reclaim nothing while the probe below reported a leak (measured during the build).
hli_mktempd() { mktemp -d "${TMPDIR:-/tmp}/hli.XXXXXX"; }

# RIDER (GUARD-HL-REVIEW-FASTFOLLOW): the --selftest built four fixture trees and LEAKED all four on
# every run (measured: 4) — and it runs in verify.sh and twice in CI, which is the kit's disk-safety
# failure shape at small scale. Accumulate every fixture dir and reclaim it on EXIT/INT/TERM. Only
# hli_mktempd's own output ever enters the list, and each entry is existence-checked before removal.
HLI_TRASH=''
hli_keep() { [ -n "${1:-}" ] && HLI_TRASH="$HLI_TRASH $1"; return 0; }
# `return 0` is load-bearing: an entry already removed makes the final && chain return 1, and a trap
# whose last status is non-zero turns a fully passing run into exit 1 (measured — 6 green legs, rc 1).
hli_cleanup() { for _t in $HLI_TRASH; do [ -n "$_t" ] && [ -d "$_t" ] && rm -rf "$_t"; done; return 0; }
trap hli_cleanup EXIT INT TERM

# --- selftest (the NON-VACUITY oracle; everything at/after this marker is emitted verbatim by the
#     mutation harness, so its st=1 accumulator can never be neutered). Placed AFTER the run/scan
#     logic on purpose (design §2e) so non-vacuity.sh's first_marker lands BELOW the check body. ---
selftest() {
  st=0
  _git() { git -c user.email=t@example.com -c user.name=tester -c commit.gpgsign=false "$@"; }

  # A clean tree: a tracked control-plane file with nlink==1 -> scan_repo reports clean (rc0).
  _cdir=$(hli_mktempd); hli_keep "$_cdir"
  mkdir -p "$_cdir/.claude"
  printf '{}\n' > "$_cdir/.claude/settings.json"
  ( cd "$_cdir" && git init -q . && git add -A && _git commit -qm init )
  if scan_repo "$_cdir" >/dev/null 2>&1; then
    echo "selftest PASS: clean tree (tracked CP file, nlink==1) -> reports clean"
  else
    echo "selftest FAIL: clean tree wrongly flagged (false positive)"; st=1
  fi

  # A DIRTY tree: a tracked control-plane file HARDLINKED (nlink>1) -> scan_repo MUST report dirty.
  _ddir=$(hli_mktempd); hli_keep "$_ddir"
  mkdir -p "$_ddir/.claude"
  printf '{}\n' > "$_ddir/.claude/settings.json"
  ln "$_ddir/.claude/settings.json" "$_ddir/alias.txt"      # a second directory entry => nlink==2
  ( cd "$_ddir" && git init -q . && git add -A && _git commit -qm init )
  if scan_repo "$_ddir" >/dev/null 2>&1; then
    echo "selftest FAIL: hardlinked tracked CP file NOT flagged (VACUOUS — the check has no teeth)"; st=1
  else
    echo "selftest PASS: hardlinked tracked CP file flagged dirty (positive liveness)"
  fi

  # A DIRTY-but-ORDINARY tree: a tracked ORDINARY file with nlink>1 -> scan_repo reports CLEAN (the
  # gate flags CP/secret aliasing only, not every nlink>1). Pins it does not over-red on pnpm-shaped
  # ordinary hardlinks.
  _odir=$(hli_mktempd); hli_keep "$_odir"
  printf 'x\n' > "$_odir/a.txt"; ln "$_odir/a.txt" "$_odir/b.txt"
  ( cd "$_odir" && git init -q . && git add -A && _git commit -qm init )
  if scan_repo "$_odir" >/dev/null 2>&1; then
    echo "selftest PASS: ordinary hardlinked file -> reports clean (no over-red)"
  else
    echo "selftest FAIL: ordinary hardlinked file wrongly flagged (over-red)"; st=1
  fi

  # MUTANT (design §2e): remove the nlink test from a COPY of THIS script and re-scan the dirty tree.
  # The mutated copy must WRONGLY report clean — proving the nlink test is load-bearing. If it still
  # reports dirty, the test proves nothing (the mechanism is always-red for some other reason).
  _mcd=$(hli_mktempd); hli_keep "$_mcd"; _mc="$_mcd/hli-mutant.sh"
  # Neuter the nlink guard: force the "nlink<=1 => skip" test to always skip (never accumulate).
  sed 's/\[ "\$_nl" -le 1 \] 2>\/dev\/null && continue/true \&\& continue/' "$HLI_SELF" > "$_mc"
  if cmp -s "$HLI_SELF" "$_mc"; then
    echo "selftest FAIL: mutant expression matched NOTHING — the nlink-test leg is unbound"; st=1
  else
    _core_abs=$(cd "$(dirname "$CORE")" 2>/dev/null && pwd -P)/$(basename "$CORE")
    if KIT_HLI_CORE="$_core_abs" sh "$_mc" --scan "$_ddir" >/dev/null 2>&1; then
      echo "selftest PASS: mutant (nlink test removed) reports the dirty tree CLEAN (leg is load-bearing)"
    else
      echo "selftest FAIL: mutant still flagged the dirty tree — the nlink test is not the teeth"; st=1
    fi
  fi

  # RIDER (GUARD-HL-REVIEW-FASTFOLLOW): the fixture trees above must be RECLAIMED, not leaked. This
  # selftest runs in verify.sh and twice in CI, and an unreclaimed mktemp -d per run is the kit's
  # disk-safety failure shape at small scale. MEASURE it rather than assert it: re-run THIS selftest as
  # a CHILD under a LEG-PRIVATE TMPDIR (vet condition 6 — a scope nothing else writes) and count what
  # survives the child's EXIT trap. KIT_HLI_NO_TRAPPROBE stops the recursion at depth 1.
  if [ -z "${KIT_HLI_NO_TRAPPROBE:-}" ]; then
    _tp=$(mktemp -d "${TMPDIR:-/tmp}/hlitrap.XXXXXX"); hli_keep "$_tp"
    TMPDIR="$_tp" KIT_HLI_NO_TRAPPROBE=1 sh "$HLI_SELF" --selftest >/dev/null 2>&1 || :
    _left=$(find "$_tp" -mindepth 1 -maxdepth 1 -type d -name 'hli.*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${_left:-9}" = 0 ]; then
      echo "selftest PASS: the EXIT trap reclaims every fixture temp dir (0 left in a leg-private TMPDIR)"
    else
      echo "selftest FAIL: $_left temp dir(s) leaked from a child selftest run — the EXIT trap is missing or incomplete"; st=1
    fi
    # NON-VACUITY: strip the trap from a COPY and re-run the same probe. The leak MUST reappear, or the
    # count above is measuring nothing (a probe that can never see a leak is a green that proves nothing).
    _tp2=$(mktemp -d "${TMPDIR:-/tmp}/hlitrap.XXXXXX"); hli_keep "$_tp2"; _tm="$_tp2/hli-notrap.sh"
    sed '/^trap hli_cleanup EXIT INT TERM$/d' "$HLI_SELF" > "$_tm"
    if cmp -s "$HLI_SELF" "$_tm"; then
      echo "selftest FAIL: the trap-removal expression matched NOTHING — the leak probe is unbound"; st=1
    else
      _tp3=$(mktemp -d "${TMPDIR:-/tmp}/hlitrap.XXXXXX"); hli_keep "$_tp3"
      _core_abs2=$(cd "$(dirname "$CORE")" 2>/dev/null && pwd -P)/$(basename "$CORE")
      TMPDIR="$_tp3" KIT_HLI_NO_TRAPPROBE=1 KIT_HLI_CORE="$_core_abs2" sh "$_tm" --selftest >/dev/null 2>&1 || :
      _left2=$(find "$_tp3" -mindepth 1 -maxdepth 1 -type d -name 'hli.*' 2>/dev/null | wc -l | tr -d ' ')
      if [ "${_left2:-0}" -ge 1 ] 2>/dev/null; then
        echo "selftest PASS: without the trap the same probe sees $_left2 leaked dir(s) — the leak assertion is load-bearing"
      else
        echo "selftest FAIL: removing the trap leaked nothing ($_left2) — the leak assertion proves nothing"; st=1
      fi
    fi
  fi

  if [ "$st" = 0 ]; then
    echo "OK: hardlink-integrity selftest — clean passes, a hardlinked tracked CP file is caught, an ordinary hardlink is not over-red, the nlink test is load-bearing, and the fixture temp dirs are trap-reclaimed"
    return 0
  fi
  echo "FAIL: hardlink-integrity selftest"
  return 1
}

case "${1:-}" in
  --selftest)  selftest; exit $? ;;
  --scan)      scan_repo "${2:-.}"; exit $? ;;   # internal: used by the --selftest mutant
  "")          run; exit $? ;;
  *)           echo "usage: hardlink-integrity.sh [--selftest]" >&2; exit 2 ;;
esac
