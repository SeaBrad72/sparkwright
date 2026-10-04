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

# _hli_marker_pin_ok <file>: T3 (SEMGREP-BASH-PARSE-KIT-WIDE close fix 2) — a CLOSED-WORLD pin,
# replacing the former _hli_nosemgrep_count_ok/_hli_bare_ok pair (which enumerated spellings and so
# could never be complete: each new marker form needed its own leg). Instead this pins the EXACT
# byte-for-byte record of every `nosem`-bearing line and its immediately governed next line — any
# addition, removal, widening, case change, or homoglyph substitution touching those lines changes
# the record and reds. `-A1` includes the governed next line because a scoped marker's rule id can
# sit on the line it precedes (this codebase's convention); the caller asserts the pin on the whole
# 2-line group, not the marker line alone.
#
# Case-folding gap: semgrep's own marker regex is caseless, but it ALSO folds U+017F LATIN SMALL
# LETTER LONG S (ſ) to `s` — a spelling `grep -i` does not fold. `-e "$_hmp_ls"` (built via printf,
# never a literal, so the byte survives editor/locale mangling) closes that one gap explicitly;
# `-e 'nosem'` catches every ASCII-case spelling via `-i`. Never route grep's output through
# `$(...)` — that drops embedded NULs a hostile marker line could carry; always `cmp` files/pipes.
#
# The record is embedded as a quoted heredoc (no parameter/command expansion) below and written to an
# hli_mktempd file before comparison. REGEN one-liner (run from the repo root, after `.` sourcing this
# file so $CORE is set, or point it at any guard core):
#   LC_ALL=C grep -a -i -A1 -e 'nosem' -e "$(printf 'no\305\277em')" .claude/hooks/guard-core.sh
# A legitimate marker change (adding/removing/relocating a nosemgrep suppression in the guard core)
# edits the heredoc below in the SAME PR, by design — this pin cannot be satisfied by an unreviewed
# drift.
_hli_marker_pin_ok() { # <core> <record> -> rc0 iff every nosem-bearing line + its governed next line equals the record, byte for byte
  _hmp_ls=$(printf 'no\305\277em')   # U+017F LONG S: semgrep's caseless regex folds it to `s`; grep -i cannot
  LC_ALL=C grep -a -i -A1 -e 'nosem' -e "$_hmp_ls" "$1" | cmp -s - "$2"
}

# _hli_write_marker_record <outfile>: materializes the recorded 8 lines (3 nosem-bearing markers +
# their governed next line each, grep-separator `--` included) via a QUOTED heredoc — no
# parameter/command expansion, so the literal `$IFS`/`$_ha_ofs` text below is never evaluated. Callers
# write this into an hli_mktempd file (never a dev-clone/tracked path) before comparing.
_hli_write_marker_record() {
  cat > "$1" <<'HLI_MARKER_RECORD_EOF'
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  _ha_ofs=$IFS; IFS='
--
      # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
      IFS=$_ha_ofs
--
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  IFS=$_ha_ofs
HLI_MARKER_RECORD_EOF
}

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
  _rc=0
  if scan_repo .; then
    echo "OK: no tracked control-plane or secret file is hardlink-aliased (all nlink==1)"
  else
    _rc=1
  fi
  _hli_rdir=$(hli_mktempd); _hli_rrec="$_hli_rdir/record"
  _hli_write_marker_record "$_hli_rrec"
  if _hli_marker_pin_ok "$CORE" "$_hli_rrec"; then
    echo "OK: the guard core's nosemgrep-family marker lines match the recorded closed-world pin"
  else
    echo "FAIL: the guard core's nosemgrep-family marker lines drifted from the recorded pin (regen: see conformance/hardlink-integrity.sh comment above _hli_write_marker_record)" >&2
    _rc=1
  fi
  rm -rf "$_hli_rdir"
  return $_rc
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

  # T3 (SEMGREP-BASH-PARSE-KIT-WIDE close fix 2): the closed-world marker pin, via the SAME
  # _hli_marker_pin_ok/_hli_write_marker_record the real scan (run()) asserts — so every anchor below
  # is load-bearing against the real check, not a duplicated inline comparison.
  _hli_pdir=$(hli_mktempd); hli_keep "$_hli_pdir"; _hli_prec="$_hli_pdir/record"
  _hli_write_marker_record "$_hli_prec"
  if _hli_marker_pin_ok "$CORE" "$_hli_prec"; then
    echo "selftest PASS: the guard core's nosemgrep-family marker lines match the recorded closed-world pin"
  else
    echo "selftest FAIL: the guard core's nosemgrep-family marker lines drifted from the recorded pin"; st=1
  fi

  # Locate the FIRST rule-scoped marker line BY CONTENT (never a hard-coded line number — the file
  # moves). This is the line the 8 negative anchors below mutate.
  _hli_mline=$(grep -n 'nosemgrep: bash\.lang\.security\.ifs-tampering\.ifs-tampering' "$CORE" | head -1 | cut -d: -f1)
  if [ -z "$_hli_mline" ]; then
    echo "selftest FAIL: could not locate the rule-scoped marker line by content — the 8 anchors below are unbound"; st=1
  else
    _hli_mcontent=$(sed -n "${_hli_mline}p" "$CORE")
    _hli_adir=$(hli_mktempd); hli_keep "$_hli_adir"

    # Anchor 1: an appended bare `# nosemgrep`.
    _hli_a1="$_hli_adir/a1-appended-bare.sh"; cp "$CORE" "$_hli_a1"; printf '%s\n' '# nosemgrep' >> "$_hli_a1"
    # Anchor 2: the marker line -> `  # nosemgrep # nosemgrep: other.rule`.
    _hli_a2="$_hli_adir/a2-doubled.sh"; sed "${_hli_mline}s/.*/  # nosemgrep # nosemgrep: other.rule/" "$CORE" > "$_hli_a2"
    # Anchor 3: the marker line -> `  # nosemgrep: other.rule` (rule id swapped).
    _hli_a3="$_hli_adir/a3-swapped-rule.sh"; sed "${_hli_mline}s/.*/  # nosemgrep: other.rule/" "$CORE" > "$_hli_a3"
    # Anchor 4: the marker line removed.
    _hli_a4="$_hli_adir/a4-removed.sh"; sed "${_hli_mline}d" "$CORE" > "$_hli_a4"
    # Anchor 5: the marker line -> `  # NOSEMGREP: <the real rule id>` (case-widened, same rule id).
    _hli_a5="$_hli_adir/a5-uppercased.sh"; sed "${_hli_mline}s/.*/  # NOSEMGREP: bash.lang.security.ifs-tampering.ifs-tampering/" "$CORE" > "$_hli_a5"
    # Anchor 6: an appended `  # noſemgrep` — the U+017F LONG S byte built via printf, never a literal.
    _hli_ls=$(printf 'no\305\277em')
    _hli_a6="$_hli_adir/a6-longs.sh"; cp "$CORE" "$_hli_a6"; printf '  # %sgrep\n' "$_hli_ls" >> "$_hli_a6"
    # Anchor 7: the marker line dropped from its governed spot and the IDENTICAL line re-inserted
    # elsewhere (top of file) — same byte content, wrong position, so its governed next line differs.
    _hli_a7="$_hli_adir/a7-relocated.sh"
    { printf '%s\n' "$_hli_mcontent"; sed "${_hli_mline}d" "$CORE"; } > "$_hli_a7"
    # Anchor 8: an APPENDED `  # NOSEMGREP` (uppercase, no removal/substitution of the original
    # marker). Anchors 4/5 both drop the original lowercase line, so a pin that reds only because a
    # line vanished (never because `-i` actually matched the added uppercase text) would still pass
    # this anchor if `-i` were silently dropped. This anchor keeps the original 3 marker blocks intact
    # and adds a 4th uppercase-only match, so it is load-bearing specifically for `-i`.
    _hli_a8="$_hli_adir/a8-appended-upper.sh"; cp "$CORE" "$_hli_a8"; printf '  # NOSEMGREP\n' >> "$_hli_a8"

    _hli_aok=1
    for _hli_apair in \
      "$_hli_a1:appended bare # nosemgrep" \
      "$_hli_a2:doubled marker (# nosemgrep # nosemgrep: other.rule)" \
      "$_hli_a3:rule id swapped to other.rule" \
      "$_hli_a4:marker line removed" \
      "$_hli_a5:case-widened to # NOSEMGREP: <real rule id>" \
      "$_hli_a6:appended long-s noſemgrep" \
      "$_hli_a7:marker relocated (dropped + re-inserted elsewhere)" \
      "$_hli_a8:appended uppercase # NOSEMGREP (no removal — anchors -i itself)" \
    ; do
      _hli_af=${_hli_apair%%:*}; _hli_alabel=${_hli_apair#*:}
      if cmp -s "$CORE" "$_hli_af"; then
        echo "selftest FAIL: anchor [$_hli_alabel] expression matched NOTHING — the anchor is unbound"; st=1; _hli_aok=0
      elif _hli_marker_pin_ok "$_hli_af" "$_hli_prec"; then
        echo "selftest FAIL: the marker pin failed to notice anchor [$_hli_alabel]"; st=1; _hli_aok=0
      else
        echo "selftest PASS: the marker pin would flag anchor [$_hli_alabel] (negative anchor)"
      fi
    done
    [ "$_hli_aok" = 1 ] || st=1

    # Non-vacuity: neutering the pin's comparator (cmp -s -> true) must make a mutated anchor WRONGLY
    # pass — proving `cmp -s` is the load-bearing comparator, not merely present. Defined as a
    # separate, deliberately-neutered function (never edits the real _hli_marker_pin_ok) so this probe
    # cannot itself mask a real regression.
    _hli_marker_pin_neutered() {
      _hmpn_ls=$(printf 'no\305\277em')
      LC_ALL=C grep -a -i -A1 -e 'nosem' -e "$_hmpn_ls" "$1" | { cmp -s - "$2" || true; }
    }
    if _hli_marker_pin_neutered "$_hli_a4" "$_hli_prec"; then
      echo "selftest PASS: neutering the pin's cmp makes a dropped-marker anchor wrongly pass (non-vacuity confirmed — cmp -s is load-bearing)"
    else
      echo "selftest FAIL: neutering the pin's cmp did not make the anchor wrongly pass — the non-vacuity probe proves nothing"; st=1
    fi
  fi

  # T3 glob-named hardlink case (SEMGREP-BASH-PARSE-KIT-WIDE slice 1 §"hardening"). The REAL mechanism
  # this leg pins: `_hardlink_alias_hit`'s enumeration loop runs under `set -f`, so a hardlink alias
  # whose NAME carries glob metacharacters (`pr[o]jects`, `.env.exampl[e]`) is classified by its OWN
  # literal path. Without `set -f`, an unquoted pathname expansion of that literal can land on a
  # DIFFERENT, real sibling file and be classified in the literal's place — and that substitution can
  # land on a classifier's NEGATIVE arm (the `.claude/projects` / `.claude/plans` relief arm, or the
  # `.env.example` template exemption) or on an earlier `continue` gate (a device mismatch on `stat`),
  # discarding the literal alias entirely. That turns a real hardlink alias to a control-plane/secret
  # file into a false ALLOW — not merely a misattributed deny reason. This leg proves the guard is
  # load-bearing by miss/hit: the HEAD core must HIT both constructions (literal name echoed); a
  # scratch copy with `set -f` neutered (the seat's sed, guarded by `cmp` so an unbound mutant reds,
  # plus an `sh -n` parse gate) must MISS both (rc 1).
  #   - C3 (secret template exemption): `.env.exampl[e]` hardlinked; a REAL `.env.example` sits beside
  #     it. An unguarded expansion of the literal resolves to `.env.example`, which _is_secret_hit's
  #     template exemption allows.
  #   - C2 (CP relief arm): `.claude/pr[o]jects/x` hardlinked; a REAL `.claude/projects/x` sits beside
  #     it. An unguarded expansion resolves to `.claude/projects/x`, which is_control_plane_path's
  #     relief arm allows.
  _hli_msd=$(hli_mktempd); hli_keep "$_hli_msd"; _hli_mscore="$_hli_msd/core-noglobstripped.sh"
  sed '/^_hardlink_alias_hit() {$/,/^}$/s/^  set -f$/  :/' "$CORE" > "$_hli_mscore"
  if cmp -s "$CORE" "$_hli_mscore"; then
    echo "selftest FAIL: the set -f mutant expression matched NOTHING — the glob-guard leg is unbound"; st=1
  elif ! sh -n "$_hli_mscore" >/dev/null 2>&1; then
    echo "selftest FAIL: the set -f mutant copy of the guard core fails to parse (sh -n)"; st=1
  else
    _hli_c3=$(hli_mktempd); hli_keep "$_hli_c3"
    printf 'SECRET=1\n' > "$_hli_c3/.env.exampl[e]"
    ln "$_hli_c3/.env.exampl[e]" "$_hli_c3/outer.txt"
    printf 'KEY=\n' > "$_hli_c3/.env.example"

    _hli_c2=$(hli_mktempd); hli_keep "$_hli_c2"
    mkdir -p "$_hli_c2/.claude/pr[o]jects" "$_hli_c2/.claude/projects"
    printf 'x\n' > "$_hli_c2/.claude/pr[o]jects/x"
    ln "$_hli_c2/.claude/pr[o]jects/x" "$_hli_c2/outer.txt"
    printf 'memory\n' > "$_hli_c2/.claude/projects/x"

    # shellcheck disable=SC1090  # sourcing the core (or its set -f mutant) is the point of this leg
    _hli_hc3=$( ( . "$CORE"; _hardlink_alias_hit_secret "$_hli_c3/outer.txt" "$_hli_c3" ) ) && _hli_hc3_rc=0 || _hli_hc3_rc=$?
    # shellcheck disable=SC1090  # sourcing the core (or its set -f mutant) is the point of this leg
    _hli_hc2=$( ( . "$CORE"; _hardlink_alias_hit_cp "$_hli_c2/outer.txt" "$_hli_c2" ) ) && _hli_hc2_rc=0 || _hli_hc2_rc=$?
    # shellcheck disable=SC1090  # sourcing the core (or its set -f mutant) is the point of this leg
    _hli_mc3=$( ( . "$_hli_mscore"; _hardlink_alias_hit_secret "$_hli_c3/outer.txt" "$_hli_c3" ) ) && _hli_mc3_rc=0 || _hli_mc3_rc=$?
    # shellcheck disable=SC1090  # sourcing the core (or its set -f mutant) is the point of this leg
    _hli_mc2=$( ( . "$_hli_mscore"; _hardlink_alias_hit_cp "$_hli_c2/outer.txt" "$_hli_c2" ) ) && _hli_mc2_rc=0 || _hli_mc2_rc=$?

    _hli_head_ok=1
    [ "$_hli_hc3_rc" = 0 ] || _hli_head_ok=0
    [ "$_hli_hc2_rc" = 0 ] || _hli_head_ok=0
    case "$_hli_hc3" in *'.env.exampl[e]') ;; *) _hli_head_ok=0 ;; esac
    case "$_hli_hc2" in *'.claude/pr[o]jects/x') ;; *) _hli_head_ok=0 ;; esac
    if [ "$_hli_head_ok" = 1 ]; then
      echo "selftest PASS: head core HITS both glob-named constructions (C3 secret-template, C2 cp-relief-arm) with the literal alias name"
    else
      echo "selftest FAIL: head core did not hit both glob-named constructions as expected: c3 rc=$_hli_hc3_rc out=[$_hli_hc3] c2 rc=$_hli_hc2_rc out=[$_hli_hc2]"; st=1
    fi
    if [ "$_hli_mc3_rc" != 0 ] && [ "$_hli_mc2_rc" != 0 ]; then
      echo "selftest PASS: the set -f mutant MISSES both constructions (rc 1, false ALLOW) — the glob guard is load-bearing"
    else
      echo "selftest FAIL: the set -f mutant unexpectedly hit: c3 rc=$_hli_mc3_rc out=[$_hli_mc3] c2 rc=$_hli_mc2_rc out=[$_hli_mc2]"; st=1
    fi
  fi

  if [ "$st" = 0 ]; then
    echo "OK: hardlink-integrity selftest — clean passes, a hardlinked tracked CP file is caught, an ordinary hardlink is not over-red, the nlink test is load-bearing, the fixture temp dirs are trap-reclaimed, the nosemgrep-family marker lines are pinned closed-world against 8 negative anchors, and the glob-named miss/hit split holds"
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
