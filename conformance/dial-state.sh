#!/bin/sh
# dial-state.sh — the enforcement-dial presence+values lock (DIAL-DELIVERY Δ-A, design §5;
# ruling D-240811-2.1).
#
# WHAT IT LOCKS. `.kit/dials.conf` decides whether `git push` is REFUSED for a head carrying no
# valid Entry Declaration (KIT_PUSH_DECL), a change-set with no branch-scoped design GO
# (KIT_PUSH_GO), or a tree whose living-document citations have decayed (KIT_PUSH_CITE, the sixth
# dial — ruling D-240815-2d). Absence reads as OBSERVE — which is exactly right on an adopter export (first run
# is never red) and exactly WRONG on the kit's own tree, where it would make one deleted file a
# silent, complete disarm of every dial this file locks. So on the kit tree the file's PRESENCE and its VALUES are
# asserted, fail-closed: a missing file, a missing key, or a value that is not the ruled one is a
# FAIL with the reason named.
#
# SCOPE — KIT-TREE ONLY, and the export's absence is DESIGNED, not a defect. `.kit/dials.conf` is
# `export-ignore`d, so an adopter tree legitimately has none. N/A is keyed on the un-spoofable kit
# marker set the other kit-self checks use (docs/ROADMAP-KIT.md / .github/workflows/golden-path.yml,
# both export-ignored): N/A only when NEITHER is present — i.e. FAIL-CLOSED on the kit, where
# deleting one marker cannot switch the lock off. Also registered `--kitself` in verify.sh.
#
# HONEST CEILING (owner-lens finding 2, stated where the check lives): THIS REDS A COMMITTED DISARM
# ONLY. A working-tree mutation through the measured cd-basename residual
# (GUARD-BASENAME-AFTER-CD-BYPASS — `cd .kit && … > dials.conf`, boarded with its own slice) appears
# in no PR diff and CI checks out a clean tree, so this lock cannot see it. The front-door control is
# the guard's three matcher sites (agent-autonomy.sh asserts all of them, including that residual as
# a disclosed ALLOW); this lock is the backstop for the thing a diff CAN show.
#
# NOT CLAIMED: that the dials are the RIGHT policy (that is the sitting's ruling, D-240811-2.1), that
# the hook is installed (guard-wired.sh's rung), or that anyone cannot use --no-verify. The pre-push
# leg is a speed bump, not a boundary.
#
# Usage: sh conformance/dial-state.sh [--selftest]
# Exit: 0 = the ruled dial state is present (or N/A off the kit tree) · 1 = missing/mis-valued
#       · 2 = bad usage. POSIX sh.
set -eu

CONF=".kit/dials.conf"
# The ruled dial state, one NAME=VALUE per line. Adding a dial here without its reader would lock
# declared-but-unread state, so Δ-B/Δ-C extend this WITH their readers (design §3) — and so does the
# fifth key, KIT_PUSH_CITE, which lands in the same slice as the hooks/pre-push leg that reads it.
REQUIRED='KIT_PUSH_DECL=enforce
KIT_PUSH_GO=enforce
KIT_SCOPE_MODE=enforce
RELEASE_TAG_PROVENANCE=enforce
KIT_PUSH_CITE=enforce'

# dial_value <name> — the conf's value for <name>, or empty. PARSE, never source (the roster.conf
# contract, mirrored by guard-core's kit_dial_mode reader this lock backstops).
dial_value() {
  grep -E "^[[:space:]]*${1}[[:space:]]*=" "$CONF" 2>/dev/null | tail -n1 \
    | sed -E "s/^[[:space:]]*${1}[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//"
}

run() {
  rc=0
  # KIT-SELF scope: N/A only when NEITHER kit marker is present (fail-closed on the kit tree).
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "dial-state: N/A — kit-self check (.kit/dials.conf is export-ignored; an adopter tree carries no dial file and reads OBSERVE by design. To opt in, create it — see docs/adoption/brownfield.md)"
    return 0
  fi
  # SYMLINK REFUSED BEFORE ANYTHING IS READ (review round 1). `[ -f ]` and `[ -r ]` FOLLOW links, so
  # a `.kit/dials.conf` pointing anywhere else would parse clean and pass this lock while the values
  # that actually decide pushes live off-tree, outside the diff a reviewer reads — the same
  # judge-the-resolved-target reasoning the guard's own alias handling uses. The tracked dial file is
  # a regular file; anything else is refused with its own reason, never silently followed.
  if [ -L "$CONF" ]; then
    echo "FAIL: $CONF is a SYMLINK. The dial file must be a regular tracked file: a link parses clean here while the values that decide pushes live off-tree and outside the reviewed diff. Replace it: git checkout HEAD -- $CONF"
    return 1
  fi
  if [ ! -f "$CONF" ] || [ ! -r "$CONF" ]; then
    echo "FAIL: $CONF is missing or unreadable on the kit tree — absence reads as OBSERVE, so this would silently disarm every dial the 2026-08-11 sitting flipped (D-240811-2.1). Restore it: git checkout HEAD -- $CONF"
    return 1
  fi
  printf '%s\n' "$REQUIRED" | while IFS= read -r _req; do
    [ -n "$_req" ] || continue
    _name=${_req%%=*}; _want=${_req#*=}
    _got=$(dial_value "$_name")
    if [ -z "$_got" ]; then
      echo "FAIL: $CONF carries no $_name key — a dial with no entry reads as OBSERVE (want $_name=$_want)"
      echo "DIAL-STATE-FAIL"
    elif [ "$_got" != "$_want" ]; then
      echo "FAIL: $CONF has $_name=$_got, want $_name=$_want (only the exact string 'enforce' enforces; anything else observes)"
      echo "DIAL-STATE-FAIL"
    fi
  done > "$_OUT"
  # The while loop runs in a SUBSHELL (pipeline), so its rc cannot come back through a variable —
  # the verdict travels through the captured output instead. A sentinel line, not a line COUNT: the
  # reasons are multi-line and a count would silently mis-read.
  grep -q '^DIAL-STATE-FAIL$' "$_OUT" && rc=1
  grep -v '^DIAL-STATE-FAIL$' "$_OUT" || true
  [ "$rc" -eq 0 ] && echo "PASS: $CONF carries the ruled dial state (KIT_PUSH_DECL=enforce, KIT_PUSH_GO=enforce, KIT_SCOPE_MODE=enforce, RELEASE_TAG_PROVENANCE=enforce, KIT_PUSH_CITE=enforce) — a committed disarm reds here; a working-tree one does not (see the ceiling in this file's header)"
  return $rc
}

_OUT=$(mktemp)
trap 'rm -f "$_OUT"' EXIT INT TERM

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)

  ds_tree "$W/good" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "liveness anchor: the ruled conf passes" 0 "$W/good"

  ds_tree "$W/gone" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  rm -f "$W/gone/.kit/dials.conf"
  ds_expect "mutant 1: the conf DELETED reds (fail-closed on absence)" 1 "$W/gone"

  ds_tree "$W/flip" 'KIT_PUSH_DECL=observe' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 2: a value flipped to observe reds" 1 "$W/flip"

  ds_tree "$W/drop" 'KIT_PUSH_DECL=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 3: a required key DELETED reds" 1 "$W/drop"

  # ...and each mutant must be named, not merely counted — an operator who cannot see WHICH dial
  # slipped has to re-derive it.
  ds_expect_says "the flipped-value reason names the dial and both values" 'KIT_PUSH_DECL=observe' "$W/flip"
  ds_expect_says "the missing-key reason names the absent dial" 'no KIT_PUSH_GO key' "$W/drop"
  ds_expect_says "the absent-file reason names the restore command" 'git checkout HEAD --' "$W/gone"

  # mutant 5 (review round 1): a SYMLINKED conf reds. `[ -f ]`/`[ -r ]` follow links, so without the
  # explicit -L refusal a link to a ruled-looking file elsewhere passes this lock while the dial
  # state that decides pushes sits off-tree, invisible to the reviewed diff.
  ds_tree "$W/link" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  mv "$W/link/.kit/dials.conf" "$W/link/.kit/elsewhere.conf"
  ln -s elsewhere.conf "$W/link/.kit/dials.conf"
  ds_expect "mutant 5: a SYMLINKED conf reds even though it parses clean" 1 "$W/link"
  ds_expect_says "the symlink reason says SYMLINK" 'is a SYMLINK' "$W/link"

  # The SECOND dial is graded too (a lock reading only the first key would pass every case above).
  ds_tree "$W/flip2" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=observe' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 4: the SECOND dial flipped to observe reds" 1 "$W/flip2"

  # The THIRD dial, KIT_SCOPE_MODE (Δ-B), is graded on BOTH faces (F3): without these two legs,
  # deleting `KIT_SCOPE_MODE=enforce` from REQUIRED leaves the whole selftest GREEN — silently
  # unlocking the new dial, the class the file header forbids.
  ds_tree "$W/scopeflip" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=observe' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 6: KIT_SCOPE_MODE flipped to observe reds" 1 "$W/scopeflip"
  ds_tree "$W/scopedrop" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 7: the KIT_SCOPE_MODE key DELETED reds" 1 "$W/scopedrop"

  # The FOURTH dial, RELEASE_TAG_PROVENANCE (Δ-C), on BOTH faces for the same F3 reason: without
  # these two legs, deleting `RELEASE_TAG_PROVENANCE=enforce` from REQUIRED leaves the whole selftest
  # GREEN — silently unlocking the new dial, the class this file's header forbids.
  ds_tree "$W/provflip" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=observe' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 8: RELEASE_TAG_PROVENANCE flipped to observe reds" 1 "$W/provflip"
  ds_tree "$W/provdrop" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'KIT_PUSH_CITE=enforce'
  ds_expect "mutant 9: the RELEASE_TAG_PROVENANCE key DELETED reds" 1 "$W/provdrop"
  ds_expect_says "the missing-provenance-key reason names the absent dial" 'no RELEASE_TAG_PROVENANCE key' "$W/provdrop"

  # The FIFTH key, KIT_PUSH_CITE (the sixth dial, ruling D-240815-2d), on BOTH faces for the same F3
  # reason: without these two legs, deleting `KIT_PUSH_CITE=enforce` from REQUIRED leaves the whole
  # selftest GREEN — silently unlocking the new dial, the class this file's header forbids. It is the
  # FIFTH KEY and the SIXTH DIAL: the sitting decided five conf-carried dials plus LOOP_STATE_MODE,
  # which is the ADOPTER's by ruling and deliberately never appears in this file — it lives in the
  # emitted adopter workflow, where it has defaulted to `enforce` since 2026-08-30. That flip
  # changes nothing here: the dial is still not conf-carried, and no key for it belongs in
  # .kit/dials.conf.
  ds_tree "$W/citeflip" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce' 'KIT_PUSH_CITE=observe'
  ds_expect "mutant 10: KIT_PUSH_CITE flipped to observe reds" 1 "$W/citeflip"
  ds_expect_says "the flipped-cite reason names the dial and both values" 'KIT_PUSH_CITE=observe' "$W/citeflip"
  ds_tree "$W/citedrop" 'KIT_PUSH_DECL=enforce' 'KIT_PUSH_GO=enforce' 'KIT_SCOPE_MODE=enforce' 'RELEASE_TAG_PROVENANCE=enforce'
  ds_expect "mutant 11: the KIT_PUSH_CITE key DELETED reds" 1 "$W/citedrop"
  ds_expect_says "the missing-cite-key reason names the absent dial" 'no KIT_PUSH_CITE key' "$W/citedrop"

  # Scope: an adopter-shaped tree (no kit markers, no conf) is N/A — and the N/A is DISCLOSED.
  ds_natree "$W/adopter"
  ds_expect "an adopter-shaped tree (no kit markers, no conf) is N/A rc 0" 0 "$W/adopter"
  ds_expect_says "the adopter N/A is disclosed as kit-self" 'N/A — kit-self check' "$W/adopter"

  # ...and the scope guard is NOT an always-N/A: ONE marker present is enough to hold the tree to
  # the lock (fail-closed — deleting a marker must not switch the check off).
  mkdir -p "$W/onemarker/docs"; : > "$W/onemarker/docs/ROADMAP-KIT.md"
  ds_expect "one kit marker + no conf still REDs (the guard is not always-N/A)" 1 "$W/onemarker"

  rm -rf "$W"
  [ "$sfail" -eq 0 ] && { echo "dial-state --selftest: OK (anchor + 11 value/presence/symlink mutants + reason-text + scope both ways)"; return 0; }
  echo "dial-state --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker, so fixture builders and kill logic sit in the protected oracle region) ---
ds_tree() { # <dir> <conf-line>... — a KIT-MARKED tree carrying .kit/dials.conf
  mkdir -p "$1/docs" "$1/.kit"
  : > "$1/docs/ROADMAP-KIT.md"
  _d=$1; shift
  printf '%s\n' "$@" > "$_d/.kit/dials.conf"
}
ds_natree() { # <dir> — an adopter-shaped tree: no kit markers, no conf
  mkdir -p "$1"
}
ds_expect() { # <label> <want-rc> <dir>
  _rc=0; _out=$( cd "$3" && sh "$_self" 2>&1 ) || _rc=$?
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want rc $2, got $_rc)"; echo "  got: $_out"; sfail=1; fi
}
ds_expect_says() { # <label> <needle> <dir>
  _out=$( cd "$3" && sh "$_self" 2>&1 ) || :
  if printf '%s' "$_out" | grep -qF -- "$2"; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (missing '$2')"; echo "  got: $_out"; sfail=1; fi
}

# ---------------------------------------------------------------------------- dispatch
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") run; exit $? ;;
  *) echo "usage: dial-state.sh [--selftest]" >&2; exit 2 ;;
esac
