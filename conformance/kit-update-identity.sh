#!/bin/sh
# kit-update-identity.sh — THE IDENTITY PROPERTY: the load-bearing proof of `kit-update`'s design.
#
#   For an adopter who has changed NOTHING, `incept_old(kit-base)` must equal their HEAD tree EXACTLY.
#
# WHY THIS EXISTS — the coordinate-system problem. An adopter's tree is not a COPY of the kit export;
# it is `incept(export)` — a TRANSFORMATION. incept RENAMES CLAUDE.md -> ENGINEERING-PRINCIPLES.md,
# rewrites cross-references in six more kit files, RE-CREATES CLAUDE.md as an adopter-owned project doc
# from a template, and wires stack-specific CI + scaffold. So `kit-base` (the pristine export, vendored
# by incept) and the adopter's worktree live in DIFFERENT COORDINATE SYSTEMS. Diffing them directly is
# meaningless: it reports a conflict on every file incept touched and it proposes restoring the kit's
# CLAUDE.md OVER THE ADOPTER'S PROJECT DOC, at the same path.
#
# We do not reverse the transformation and we do not RE-DESCRIBE it. We RE-APPLY it, so it cancels:
#   BASE = incept(kit-base), run with KIT-BASE'S OWN scripts/incept.sh (the incept the adopter used).
# A hand-maintained rename/ownership table would be a SECOND source of truth about incept's behavior and
# it would rot the first time incept changed. Each side runs through the incept that belongs to it.
#
# WHY IT CANNOT BE VACUOUS: a broken reconstruction cannot accidentally satisfy an EQUALITY. A dead code
# path yields an EMPTY tree, not an EQUAL one. The four NEGATIVES below prove the comparison has teeth:
# drop --date (the phantom-date conflict), reconstruct with the WRONG stack, skip incept entirely (the
# naive design this whole task refutes), and — N4 — flip a recorded STAMP the tree's own evidence
# contradicts, which fires only if the reconstruction actually BELIEVES THE RECORD rather than sniffing
# the tree. Each MUST produce a non-empty diff.
#
# NOT REGISTERED IN conformance/verify.sh — same reason as conformance/kit-base.sh: it runs `incept`
# inside a fresh export, but an ADOPTER's tree already carries ENGINEERING-PRINCIPLES.md, so incept
# refuses and the check would FAIL on every adopter — and that battery is PORTABLE. Its teeth are this
# file's own negatives (which are part of the single `check`, not an optional --selftest) plus CI wiring.
#
# HONEST CEILING: proves BASE and HEAD are the SAME TREE — i.e. the two are representable in ADOPTER
# COORDINATES, so a 3-way merge against them is well-posed. It proves NOTHING about whether a merge of
# a new release into them is semantically DESIRABLE, and nothing about the adopter's tests passing
# afterwards. THEIRS + the merge + the report are P1.2 proper (T4).
#
#   sh conformance/kit-update-identity.sh
# Exit: 0 = pass · 1 = regression · 2 = usage/UNVERIFIED. POSIX sh; dash-clean.
# What it changes: nothing in the repo — exports/incepts into a temp dir, removed on exit.
# Guardrails: read-only wrt the kit; temp-only writes; teardown non-fatal; an EMPTY reconstruction is a
#             FAIL, never a pass (an empty tree is not an equal tree).
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

# shellcheck disable=SC2329  # invoked INDIRECTLY, from the EXIT/INT/TERM trap in check()
_cleanup() { rm -rf "$1" 2>/dev/null || true; }

STACK=typescript-node
ADOPT_DATE=2020-01-02

# ── the comparison ────────────────────────────────────────────────────────────────────────────────────
# listing_head <repo>  — the adopter's committed tree, as "<mode> <sha> <path>".
# listing_dir  <dir>   — a reconstructed directory, as "<mode> <sha> <path>", hashed EXACTLY the way the
#                        adopter's own commit was made (`git add -A` in a repo rooted at that dir, so the
#                        SAME .gitignore + the SAME core.excludesFile apply to both sides). Comparing
#                        git object ids compares CONTENT AND FILE MODE — an exec-bit drift is caught too.
listing_head() {
  git -C "$1" ls-tree -r HEAD | sed 's/^\([0-7]*\) blob \([0-9a-f]*\)	/\1 \2 /' | LC_ALL=C sort
}
listing_dir() {
  ( cd "$1" && { [ -d .git ] || git init -q . ; } \
      && git add -A . >/dev/null 2>&1 \
      && git ls-files -s ) \
    | sed 's/^\([0-7]*\) \([0-9a-f]*\) [0-9]*	/\1 \2 /' | LC_ALL=C sort
}

# diff_base_vs_head <base-dir> <repo> <label> — prints the diff; rc 0 iff IDENTICAL.
# An EMPTY base is a FAIL, not a pass: "no files" would otherwise compare "equal" against nothing.
diff_base_vs_head() {
  _bd=$1; _rp=$2; _lb=$3
  _a=$(mktemp) || return 2
  _b=$(mktemp) || { rm -f "$_a"; return 2; }
  listing_dir "$_bd" > "$_a" 2>/dev/null || :
  listing_head "$_rp" > "$_b"
  _rc=0
  if [ ! -s "$_a" ]; then
    echo "  [$_lb] reconstruction is EMPTY (0 files) — an empty tree is NOT an equal tree" >&2
    _rc=1
  elif ! diff -u "$_a" "$_b" >/dev/null 2>&1; then
    _rc=1
    diff -u "$_a" "$_b" | grep -E '^[+-][^+-]' | head -25 || :
  fi
  rm -f "$_a" "$_b"
  return $_rc
}

# ── the fixture: a REAL adopter (the kit's own repo is NOT one — it has no kit-base) ──────────────────
build_adopter() {  # <dir>
  sh "$ROOT/scripts/adopter-export.sh" "$1" --profile "$STACK" >/dev/null 2>&1 || {
    echo "FAIL: kit-update-identity — adopter-export failed; cannot build a fixture adopter" >&2; return 1; }
  ( cd "$1" && git init -q . && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm 'kit export' ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-identity — could not init the fixture repo" >&2; return 1; }
  ( cd "$1" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B \
      --stack "$STACK" --date "$ADOPT_DATE" ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-identity — incept failed on the fixture" >&2; return 1; }
  ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm 'inception' ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-identity — could not commit the incepted fixture" >&2; return 1; }
  # incept must have recorded the base ITSELF (we never create it here — that would fake the premise).
  git -C "$1" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 || {
    echo "FAIL: kit-update-identity — incept did not record refs/heads/kit-base (no base to reconstruct from)" >&2
    return 1; }
  _v=$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)
  git -C "$1" rev-parse --verify --quiet "refs/tags/kit-base/v${_v}" >/dev/null 2>&1 || {
    echo "FAIL: kit-update-identity — incept did not tag kit-base/v${_v}" >&2; return 1; }
}

# materialize <repo> <dir> — the RAW kit-base tree, un-incepted. The negatives drive incept themselves.
materialize() { mkdir -p "$2" && git -C "$1" archive kit-base | tar -x -C "$2"; }

check() {
  _t=$(mktemp -d) || { echo "kit-update-identity: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _p="$_t/proj"
  build_adopter "$_p" || return 1

  st=0

  # ── POSITIVE — THE IDENTITY PROPERTY, through the REAL code path (scripts/kit-update.sh). ───────────
  if ! ( cd "$_p" && sh scripts/kit-update.sh --reconstruct-base "$_t/base" ) >"$_t/rb.log" 2>&1; then
    echo "FAIL: kit-update-identity — 'kit-update.sh --reconstruct-base' failed:" >&2
    sed 's/^/    /' "$_t/rb.log" >&2 || :
    return 1
  fi
  if diff_base_vs_head "$_t/base" "$_p" IDENTITY; then
    echo "PASS: identity — incept_old(kit-base) == the adopter's HEAD tree, EXACTLY (empty diff)"
  else
    echo "FAIL: identity — the reconstruction is NOT the adopter's HEAD tree (lines above: '-' = only in" >&2
    echo "      the reconstruction, '+' = only in HEAD). A wrong base silently produces a wrong delta." >&2
    st=1
  fi

  # ── NEGATIVES — the comparison must have TEETH. Each mutates the reconstruction ONE way; each must be
  #    NON-EMPTY. If any of these reports 'identical', the comparison is broken and the green is a lie. ─
  _neg() {  # <label> <dir> <why-it-must-be-red>
    if diff_base_vs_head "$2" "$_p" "$1" >/dev/null 2>&1; then
      echo "FAIL: NON-VACUITY [$1] — a WRONG reconstruction still compared IDENTICAL to HEAD." >&2
      echo "      $3" >&2
      echo "      The comparison cannot see this class of error, so the identity green proves nothing." >&2
      st=1
    else
      echo "PASS: non-vacuity [$1] — a wrong reconstruction produces a NON-EMPTY diff ($3)"
    fi
  }

  # N1 — DROP --date. The phantom-date conflict: the reconstruction runs TODAY, the adopter's tree carries
  # their ADOPTION date, so an unpinned stamp fabricates a conflict in CLAUDE.md + ADR-000 — files nobody
  # touched. This is the entire reason `incept --date` exists.
  materialize "$_p" "$_t/n1"
  ( cd "$_t/n1" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B --stack "$STACK" ) \
    >/dev/null 2>&1 || :
  _neg NO-DATE "$_t/n1" "an unpinned **Created:** stamps TODAY, not the adoption date"

  # N2 — WRONG STACK. The profile drives the emitted CI, the scaffold, and the .env.example PORT; a
  # --profile export carries only ONE profile, so the wrong stack silently wires nothing.
  materialize "$_p" "$_t/n2"
  ( cd "$_t/n2" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B --stack go \
      --date "$ADOPT_DATE" ) >/dev/null 2>&1 || :
  _neg WRONG-STACK "$_t/n2" "the wrong profile emits a different CI + scaffold"

  # N3 — NO INCEPT AT ALL: the naive 'diff the raw export against the adopter' design this task refutes.
  # The rename (CLAUDE.md -> ENGINEERING-PRINCIPLES.md) and the template substitution MUST show up.
  materialize "$_p" "$_t/n3"
  _neg NO-INCEPT "$_t/n3" "the raw export is in KIT coordinates — the rename + template substitution show"

  # N4 (T3b) — THE STAMP IS READ, NOT RE-DERIVED FROM THE TREE. The positive above cannot see this: for
  # this fixture the recorded stamp and the tree's evidence AGREE (github), so an updater that ignored the
  # stamp entirely and sniffed the tree would produce the SAME base and stay green forever.
  #
  # So: flip the recorded **CI platform** stamp to `gitlab` in the fixture's WORKING TREE only. HEAD is
  # untouched — the tree's evidence still shouts "github" (the exported kit-own .github/workflows/ci.yml is
  # right there, and `--ci gitlab` is exactly the case that leaves it in place). Now the FACT and the
  # EVIDENCE disagree, and they predict different trees:
  #     reads the STAMP     -> wires GitLab CI  -> NON-EMPTY diff vs HEAD  (this negative FIRES)
  #     infers from the TREE-> wires GitHub CI  -> reproduces HEAD exactly (this negative goes SILENT)
  # A silent N4 therefore means kit-update stopped believing the record — the precise regression T3b
  # exists to prevent, and the one an all-agreeing fixture can never reveal.
  sed 's#^- \*\*CI platform\*\* (§14): github#- **CI platform** (§14): gitlab#' "$_p/CLAUDE.md" > "$_t/cm.n4" \
    && cp "$_t/cm.n4" "$_p/CLAUDE.md"
  if ! grep -q '^- \*\*CI platform\*\* (§14): gitlab' "$_p/CLAUDE.md"; then
    echo "FAIL: [STAMP-READ] setup — could not flip the **CI platform** stamp in the fixture's CLAUDE.md." >&2
    echo "      Either incept stopped stamping it, or the §3 field/section ref moved. Either way the" >&2
    echo "      reconstruction is now reading an input nothing records — fix that, do not relax this." >&2
    st=1
  elif ! ( cd "$_p" && sh scripts/kit-update.sh --reconstruct-base "$_t/n4" ) >"$_t/n4.log" 2>&1; then
    # Distinguished from a silent negative on purpose: a CRASH here is a setup failure, not a proof.
    echo "FAIL: [STAMP-READ] setup — kit-update failed outright on the flipped stamp:" >&2
    sed 's/^/    /' "$_t/n4.log" >&2 || :
    st=1
  else
    _neg STAMP-READ "$_t/n4" "the recorded CI-platform STAMP — not the tree's evidence — wires the base"
  fi
  git -C "$_p" checkout -- CLAUDE.md >/dev/null 2>&1 || :   # restore the fixture for anything added later

  if [ "$st" -eq 0 ]; then
    echo "OK: kit-update-identity — the reconstruction is exact, and the comparison is proven non-vacuous"
    echo "HONEST CEILING: proves BASE and HEAD are the SAME TREE (adopter coordinates), so a 3-way merge"
    echo "                against them is well-posed. NOT that any merge is semantically desirable, and"
    echo "                NOT that the adopter's tests pass after applying anything. That is T4."
  fi
  return $st
}

case "${1:-}" in
  "") check; exit $? ;;
  *) echo "usage: kit-update-identity.sh" >&2; exit 2 ;;
esac
