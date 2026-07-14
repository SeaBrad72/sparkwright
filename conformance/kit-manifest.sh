#!/bin/sh
# kit-manifest.sh — every adopter export must STATE what it shipped.
#
# THE CONTRACT: an export carries `.kit-manifest` — the sorted list of every path in it. That list is the
# kit-own file set, recorded as a FACT by the only actor that knows it: the exporter just built the set
# (`git archive` minus export-ignore minus the optional `--profile` prune) and, until now, threw it away.
#
# WHY A RECORDED FACT AND NOT A MARKER (P1.2-pre): the kit's only prior kit-own-vs-adopter mechanism is
# `cp_kit_replace` (scripts/incept.sh:168-174) — a content-grep over FOUR files, at incept time. It is a
# one-shot brownfield clobber-check, not provenance, and ITS MARKER DOES NOT SURVIVE INCEPTION: the kit's
# own ci.yml carries `Kit-own CI` (1 hit), but the profiles/*/ci.yml that incept installs in its place
# carries ZERO. A kit-update built on it would find no marker on the adopter's kit-generated CI, classify
# it adopter-authored, and REFUSE TO EVER UPDATE IT — a silent, plausible, permanent no-op. Inference has
# been tried and it failed. This check locks the fact instead.
#
# CONSUMER: scripts/incept.sh reads this manifest to vendor the pristine tree onto the `kit-base` orphan
# branch (conformance/kit-base.sh). Manifest-scoping is what makes that snapshot brownfield-SAFE: it
# structurally cannot capture adopter-authored files, so a later diff(base, new-export) can never read the
# adopter's own work as "the kit deleted this".
#
# PINNED DECISIONS (both are load-bearing; do not "simplify" them):
#   - The manifest LISTS ITSELF. It is part of the export, and kit-base must be able to carry it forward.
#   - The sort is LC_ALL=C. A locale-dependent order makes the manifest non-reproducible across machines,
#     and this artifact's entire job is to be a stable, comparable fact. It would pass every test on one box.
#
# NOT REGISTERED IN conformance/verify.sh — deliberate, and it travels with kit-base.sh. On an ADOPTER
# this would merely re-export their own repo and check that export against itself: it proves nothing about
# the kit while costing a full export on every run of a PORTABLE battery that adopters (and artifact-gate,
# on the incepted export) run. Same call as green-on-clone.sh — do not "helpfully" add it there.
# HONEST CONSEQUENCE: it is therefore NOT reached by the non-vacuity mutation sweep (whose target_set is
# the verify.sh control set). Its teeth are the --selftest below (wired into ci.yml) plus HAND
# mutation-testing at authoring time — weaker than the sweep, and named as such. Witnessed RED at
# authoring: emitting the manifest BEFORE the profile prune makes it state files the adopter never got.
#
# HONEST CEILING: this proves the manifest MATCHES THE TREE IT SHIPPED WITH. It does NOT prove the export
# contains the right set of files — that is adopter-export's own contract (see adopter-export-wired.sh).
# It also proves nothing about what incept then DOES to those files (rename, scaffold copies, stamps);
# the manifest is necessary, not sufficient, for P1.2's partition.
#
#   sh conformance/kit-manifest.sh            # 0 = every export states its contents, correctly
#   sh conformance/kit-manifest.sh --selftest # fixtures
# Exit: 0 = pass · 1 = regression · 2 = usage/UNVERIFIED. POSIX sh; dash-clean.
# What it changes: nothing in the repo — exports to a temp dir, removed on exit.
# Guardrails: read-only wrt the kit; temp-only writes; teardown is non-fatal (a bare rm under set -eu is a
#             latent flake — P0-FU(a)); refuses to pass on an empty/absent manifest (no vacuous green).
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

_cleanup() { rm -rf "$1" 2>/dev/null || true; }

# ── THE SEAM ──────────────────────────────────────────────────────────────────────────────────────────
# manifest_matches_tree <dir> : does <dir>/.kit-manifest state exactly <dir>'s contents?
# Factored out so --selftest drives THIS EXACT function against tiny fixtures instead of paying for real
# exports. (P1-CI-c: a selftest that re-runs the real thing on every PR gives back everything it saves.)
manifest_matches_tree() {
  _d=$1
  if [ ! -f "$_d/.kit-manifest" ]; then
    echo "FAIL: kit-manifest — no .kit-manifest in the export (the tree does not state what it shipped)" >&2
    return 1
  fi
  if [ ! -s "$_d/.kit-manifest" ]; then
    echo "FAIL: kit-manifest — .kit-manifest is EMPTY (a vacuous manifest is not a manifest)" >&2
    return 1
  fi
  _actual=$(mktemp) || return 1
  _stated=$(mktemp) || { rm -f "$_actual"; return 1; }
  ( cd "$_d" && find . \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort ) > "$_actual"
  LC_ALL=C sort "$_d/.kit-manifest" > "$_stated"

  _rc=0
  if ! diff -u "$_stated" "$_actual" > /dev/null 2>&1; then
    _rc=1
    echo "FAIL: kit-manifest — .kit-manifest does not match the tree it shipped with." >&2
    echo "  '-' = stated in the manifest but NOT on disk · '+' = on disk but NOT stated:" >&2
    diff -u "$_stated" "$_actual" | grep -E '^[+-][^+-]' | head -20 >&2
  fi
  rm -f "$_actual" "$_stated"
  return $_rc
}

check() {
  _t=$(mktemp -d) || { echo "kit-manifest: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064  # intentional: expand $_t now, at trap-set time
  trap "_cleanup '$_t'" EXIT INT TERM

  # (1) the default (un-pruned) export states its contents
  if ! sh "$ROOT/scripts/adopter-export.sh" "$_t/full" >/dev/null 2>&1; then
    echo "FAIL: kit-manifest — adopter-export failed; cannot assess the manifest" >&2
    return 1
  fi
  manifest_matches_tree "$_t/full" || return 1

  # (2) PROFILE-CORRECTNESS — the wrinkle that makes "the tree at version X" non-unique.
  # `--profile go` PRUNES profiles/*; publish-public.sh ships the un-pruned tree. The manifest must
  # describe the tree the ADOPTER got, not the one the mirror carries — else kit-update would compute a
  # delta against a base that never existed on their disk.
  if sh "$ROOT/scripts/adopter-export.sh" "$_t/go" --profile go >/dev/null 2>&1; then
    manifest_matches_tree "$_t/go" || return 1
    if grep -qE '^profiles/typescript-node/' "$_t/go/.kit-manifest" 2>/dev/null; then
      echo "FAIL: kit-manifest — a --profile go export's manifest still lists profiles/typescript-node/" >&2
      echo "       The manifest must describe the PRUNED tree the adopter actually received." >&2
      return 1
    fi
  fi

  echo "OK: kit-manifest — every export states its contents, and a --profile export states its PRUNED contents"
  echo "HONEST CEILING: proves the manifest matches the tree it shipped with — NOT that the export contains"
  echo "                the right file set (adopter-export's own contract), and NOT what incept later does to them."
  return 0
}

# ── ORACLE — everything below the ^selftest() marker. The mutation harness never neuters it, so the
#    oracle's own st=1 accumulator can never be flipped. Fixtures are tiny: they drive the SEAM, not a
#    real export. ──
selftest() {
  st=0
  t=$(mktemp -d) || return 2

  _case() {  # <label> <expected-rc> <dir>
    manifest_matches_tree "$3" >/dev/null 2>&1 && _got=0 || _got=$?
    if [ "$_got" -eq "$2" ]; then
      echo "PASS: selftest — $1 (rc $_got)"
    else
      echo "FAIL: selftest — $1 expected $2 got $_got"; st=1
    fi
  }

  # LIVENESS ANCHOR (positive): a correct manifest passes. If this ever fails, the check is dead.
  mkdir -p "$t/ok/sub"
  : > "$t/ok/a.txt"; : > "$t/ok/sub/b.txt"
  printf '.kit-manifest\na.txt\nsub/b.txt\n' > "$t/ok/.kit-manifest"
  _case "correct manifest passes (liveness anchor)" 0 "$t/ok"

  # NEGATIVE 1 — a file on disk that the manifest does NOT state.
  # This is the one that matters: an UNSTATED file is a file kit-base would not vendor, so kit-update
  # would later see it as adopter-authored and never update it. Exactly the cp_kit_replace failure.
  mkdir -p "$t/unstated"
  : > "$t/unstated/a.txt"; : > "$t/unstated/ghost.txt"
  printf '.kit-manifest\na.txt\n' > "$t/unstated/.kit-manifest"
  _case "file on disk but NOT in the manifest -> RED" 1 "$t/unstated"

  # NEGATIVE 2 — a manifest entry with no file behind it. incept would try to `git add` a path that does
  # not exist; a base built from it would be a lie.
  mkdir -p "$t/phantom"
  : > "$t/phantom/a.txt"
  printf '.kit-manifest\na.txt\nnot-here.txt\n' > "$t/phantom/.kit-manifest"
  _case "manifest entry with no file behind it -> RED" 1 "$t/phantom"

  # NEGATIVE 3 — an ABSENT manifest must not pass. A missing artifact is not a passing one.
  mkdir -p "$t/none"; : > "$t/none/a.txt"
  _case "absent manifest -> RED" 1 "$t/none"

  # NEGATIVE 4 — an EMPTY manifest must not pass. This is the vacuity trap: `diff` of two empty lists is
  # equal, so a naive implementation would call an empty manifest on an empty-looking tree a PASS.
  mkdir -p "$t/empty"; : > "$t/empty/a.txt"; : > "$t/empty/.kit-manifest"
  _case "empty manifest -> RED (vacuity trap)" 1 "$t/empty"

  _cleanup "$t"
  [ "$st" -eq 0 ] && echo "kit-manifest --selftest: OK" || echo "kit-manifest --selftest: FAIL"
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         check;    exit $? ;;
  *) echo "usage: kit-manifest.sh [--selftest]" >&2; exit 2 ;;
esac
