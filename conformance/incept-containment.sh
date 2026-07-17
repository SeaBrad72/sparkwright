#!/bin/sh
# incept-containment.sh — INCEPT-CONTAIN. Proves scripts/incept.sh REFUSES (before any mutation)
# a tree carrying kit-internal markers — the kit's own dev repo or a raw clone — and still
# PROCEEDS on a clean export. Locks the SOUNDNESS invariant: every marker in incept's refusal set
# is export-ignored in .gitattributes, so a clean export can never be falsely refused.
#   usage: sh conformance/incept-containment.sh --selftest
set -euf
cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd -P)

[ "${1:-}" = "--selftest" ] || { echo "usage: $0 --selftest" >&2; exit 2; }
st=0

# escape ERE metacharacters in a literal string (marker names contain '.' and '/')
ere() { printf '%s' "$1" | sed 's/[].[^$*\/]/\\&/g'; }

# The refusal set, read from incept.sh — the single source of truth (the exact one-line assignment).
MARKERS=$(sed -n "s/^KIT_INTERNAL_MARKERS='\\(.*\\)'.*/\\1/p" scripts/incept.sh)

# --- soundness: non-empty (a guard that can refuse nothing is vacuous) ---
if [ -n "$MARKERS" ]; then
  echo "selftest PASS: parsed $(printf '%s' "$MARKERS" | wc -w | tr -d ' ') kit-internal markers from incept.sh"
else
  echo "selftest FAIL: no KIT_INTERNAL_MARKERS parsed from incept.sh (vacuous — refuses nothing)"; st=1
fi

# --- soundness: every marker is export-ignored (a clean export can never carry it) ---
for m in $MARKERS; do
  if grep -Eq "^$(ere "$m")/?[[:space:]]+export-ignore" .gitattributes; then
    echo "selftest PASS: marker '$m' is export-ignored (soundness — export can't carry it)"
  else
    echo "selftest FAIL: marker '$m' NOT export-ignored — a clean export could carry it and be falsely refused"; st=1
  fi
done

# --- fixtures: an export-shaped tree (markers stripped), incept.sh overlaid from the worktree ---
build_export() {  # -> stdout: fresh export tree, or empty on failure
  _d=$(mktemp -d) || return 1
  ( cd "$REPO_ROOT" && git archive HEAD ) | ( cd "$_d" && tar -xf - ) || return 1
  cp "$REPO_ROOT/scripts/incept.sh" "$_d/scripts/incept.sh" || return 1   # test the version under change
  [ -f "$_d/CLAUDE.md" ] && [ -f "$_d/scripts/incept.sh" ] || return 1     # setup anchor, fail loud
  [ ! -e "$_d/SPARKWRIGHT-CONSOLIDATED-BACKLOG.md" ] || return 1           # export must be clean
  printf '%s\n' "$_d"
}
run_incept() {  # <tree> -> sets RC, OUT
  _t="$1"
  if OUT=$( cd "$_t" && sh scripts/incept.sh --name Probe --intent-owner p --stack typescript-node \
       --backlog md --ci github --noninteractive 2>&1 ); then RC=0; else RC=$?; fi
}

# --- per-marker: planting any ONE marker makes incept REFUSE before mutation ---
for m in $MARKERS; do
  t=$(build_export) || { echo "selftest FAIL: fixture setup for '$m' (fail-closed)"; st=1; continue; }
  mkdir -p "$t/$(dirname "$m")" 2>/dev/null || true
  : > "$t/$m"                                   # [ -e ] is type-agnostic; a plain file suffices
  run_incept "$t"
  if [ "$RC" != 0 ] && printf '%s' "$OUT" | grep -q "kit-internal"; then
    if [ -f "$t/CLAUDE.md" ] && [ ! -e "$t/ENGINEERING-PRINCIPLES.md" ]; then
      echo "selftest PASS: marker '$m' present -> incept REFUSES before any mutation"
    else
      echo "selftest FAIL: marker '$m' -> refused, but the tree was already mutated"; st=1
    fi
  else
    echo "selftest FAIL: marker '$m' present -> incept did NOT refuse (rc=$RC)"; st=1
  fi
  rm -rf "$t"
done

# --- anti-vacuity: a CLEAN export (no markers) must still PROCEED (rc 0) ---
t=$(build_export) || { echo "selftest FAIL: clean-export fixture setup"; st=1; }
if [ -n "${t:-}" ]; then
  run_incept "$t"
  if [ "$RC" = 0 ]; then
    echo "selftest PASS: clean export (no markers) -> incept PROCEEDS (rc 0)"
  else
    echo "selftest FAIL: clean export REFUSED (rc=$RC) — over-broad guard breaks real adopters"
    printf '%s\n' "$OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$t"
fi

# --- brownfield-safe: generic pre-existing files (NOT kit-named) must NOT be refused ---
t=$(build_export) || { echo "selftest FAIL: brownfield fixture setup"; st=1; }
if [ -n "${t:-}" ]; then
  : > "$t/CHANGELOG.md"; : > "$t/BACKLOG.md"; mkdir -p "$t/docs/architecture"
  run_incept "$t"
  if [ "$RC" = 0 ]; then
    echo "selftest PASS: brownfield generic files (CHANGELOG/BACKLOG/docs-architecture) -> NOT falsely refused"
  else
    echo "selftest FAIL: generic non-kit files falsely refused (rc=$RC) — brownfield adopter blocked"; st=1
  fi
  rm -rf "$t"
fi

# --- STANDING self-negative: neuter the guard (empty its marker set) in a fixture copy of incept.sh;
#     a marker-bearing tree must THEN proceed — proving the per-marker refusals above are caused BY the
#     guard (load-bearing), not by something else in incept. (The non-vacuity sweep SKIPS this driver-style
#     check — subject incept.sh is external — so this internal self-negative is the standing proof.) ---
t=$(build_export) || { echo "selftest FAIL: self-negative fixture setup"; st=1; }
if [ -n "${t:-}" ]; then
  # empty the one-line marker set -> the guard's for-loop has zero iterations -> guard inert
  sed "s/^KIT_INTERNAL_MARKERS='.*/KIT_INTERNAL_MARKERS=''/" "$t/scripts/incept.sh" > "$t/scripts/incept.sh.neut" \
    && mv "$t/scripts/incept.sh.neut" "$t/scripts/incept.sh"
  : > "$t/SPARKWRIGHT-CONSOLIDATED-BACKLOG.md"   # a marker the REAL guard would refuse
  run_incept "$t"
  if [ "$RC" = 0 ]; then
    echo "selftest PASS: guard neutered (empty marker set) -> marker-bearing tree PROCEEDS — refusal is attributable to the guard (load-bearing)"
  else
    echo "selftest FAIL: tree still refused with the guard neutered (rc=$RC) — the per-marker refusals are NOT attributable to the guard"; st=1
  fi
  rm -rf "$t"
fi

[ "$st" = 0 ] && echo "incept-containment --selftest: OK" || echo "incept-containment --selftest: FAIL"
exit "$st"
