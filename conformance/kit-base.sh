#!/bin/sh
# kit-base.sh — after incept, the adopter's repo HOLDS the pristine tree it received.
#
# THE CONTRACT: incept vendors the received export onto an orphan branch `kit-base`, tagged
# `kit-base/v<VERSION>`. That branch is the MERGE BASE every kit->adopter update pipe needs: the answer to
# "what tree did this adopter actually receive?". Without it, kit-update (P1.2) has nothing to diff against
# — the public mirror carries ONE commit (v3.122.0) while the kit is at 3.131.0, so a base cannot be
# fetched per-version, and an adopter's --profile export is not even the same tree the mirror ships.
#
# WHY VENDORED, NOT FETCHED: if the adopter HOLDS the tree they received, the mirror need only carry the
# CURRENT release. Per-version tag archaeology — and the nine unpublished historical versions — stop
# mattering entirely. The base is also immutable by construction (a git commit in a repo they own),
# works offline, and is automatically profile-correct: it IS what they got.
#
# WHY MANIFEST-SCOPED (the data-loss guard — this is the most important line in this file):
#   Snapshotting the raw WORKTREE would capture adopter-authored files in a brownfield repo. A later
#   diff(kit-base, new-export) would then read those files as "THE KIT DELETED THESE" — and kit-update
#   would propose DELETING THE ADOPTER'S OWN WORK. Scoping the snapshot to .kit-manifest makes that
#   structurally impossible: only paths the exporter said it shipped can ever enter the base.
#
# WHY PRE-INCEPT, NOT POST-INCEPT: the base is the RAW export, so the kit delta is
# diff(export@old, export@new) — pure kit change, no inception noise. And it keeps incept OFF the adopter's
# tree, which is the part that actually matters: incept REFUSES to re-run (scripts/incept.sh), and it
# overwrites CLAUDE.md from the project template unconditionally, which would destroy an adopter's charter
# prose. NEVER RE-RUN INCEPT AGAINST AN ADOPTER'S WORKING TREE.
#
# CORRECTION (P1.2/T3 — this comment used to end "any design that needs incept replayed against a new
# version is dead on arrival"; that was FALSE, and it was about to cost us the whole update mechanism).
# Replaying incept ON THE ADOPTER is dead on arrival. Replaying it in a TEMP DIR, over the vendored
# kit-base, with the inception inputs the project recorded, is not merely alive — it is the design:
#     BASE = incept_old(kit-base)  ->  reconstructs an unmodified adopter's HEAD EXACTLY (477/477 entries,
#                                      mode+sha+path; conformance/kit-update-identity.sh).
# What made it reproducible is `incept --date` (the adoption date is pinned, not stamped as "today") plus
# CLAUDE.md §3 recording EVERY inception input — stack, CI platform, DB archetype and the rest — so the
# replay is fed facts rather than guesses. The narrow true claim is the one above: incept never touches the
# adopter's tree. Do not rip the replay out on the strength of the sentence that used to live here.
#
# NOT REGISTERED IN conformance/verify.sh — deliberate. This check runs `incept` inside a fresh export,
# but an ADOPTER's tree already carries ENGINEERING-PRINCIPLES.md, so incept refuses (scripts/incept.sh:195)
# and the check would FAIL on every adopter — and that battery is PORTABLE (adopters run it; artifact-gate
# and cf-green-on-clone run it on the INCEPTED export). Same call as release-tagged.sh / board-drift.sh.
# HONEST CONSEQUENCE, stated rather than glossed: it is therefore NOT reached by the non-vacuity mutation
# sweep (whose target_set is the verify.sh control set). Its teeth are the --selftest below (wired into
# ci.yml) plus HAND mutation-testing at authoring time — a weaker guarantee than the sweep, and named as
# such. Witnessed RED at authoring: dropping the manifest-scoping leaks an adopter file into the base.
#
# HONEST CEILING: proves the base equals the export AS INCEPT RECEIVED IT. It does NOT prove the adopter
# still has it later (they can delete a branch). It does NOT exercise brownfield adoption end-to-end
# (Phase 2 / P2.2) — only that brownfield files CANNOT LEAK IN. It proves nothing about the merge itself;
# computing and presenting the delta is P1.2.
#
#   sh conformance/kit-base.sh            # 0 = incept records a faithful, worktree-safe base
#   sh conformance/kit-base.sh --selftest # fixtures
# Exit: 0 = pass · 1 = regression · 2 = usage/UNVERIFIED. POSIX sh; dash-clean.
# What it changes: nothing in the repo — exports/incepts into a temp dir, removed on exit.
# Guardrails: read-only wrt the kit; temp-only writes; teardown is non-fatal (P0-FU(a): a bare rm under
#             set -eu is a latent flake); refuses to pass when the base is absent (no vacuous green).
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

_cleanup() { rm -rf "$1" 2>/dev/null || true; }

# ── THE SEAM ──────────────────────────────────────────────────────────────────────────────────────────
# base_is_faithful <repo> : does <repo> carry a kit-base whose tree is EXACTLY what .kit-manifest stated?
# Driven directly by --selftest against tiny fixtures, so the fixtures never pay for a real export+incept.
base_is_faithful() {
  _r=$1
  if ! git -C "$_r" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1; then
    echo "FAIL: kit-base — no refs/heads/kit-base (the adopter has NO record of the tree they received)" >&2
    return 1
  fi
  _stated=$(mktemp) || return 1
  _inbase=$(mktemp) || { rm -f "$_stated"; return 1; }
  # What the exporter SAID it shipped (the manifest, carried into the base itself) ...
  git -C "$_r" show kit-base:.kit-manifest 2>/dev/null | LC_ALL=C sort > "$_stated" || {
    echo "FAIL: kit-base — the base does not even carry .kit-manifest (it cannot describe itself)" >&2
    rm -f "$_stated" "$_inbase"; return 1; }
  # ... versus what is ACTUALLY in the base.
  git -C "$_r" ls-tree -r --name-only kit-base | LC_ALL=C sort > "$_inbase"

  _rc=0
  if [ ! -s "$_inbase" ]; then
    echo "FAIL: kit-base — the base is EMPTY (an empty base is not a base)" >&2; _rc=1
  elif ! diff -u "$_stated" "$_inbase" >/dev/null 2>&1; then
    _rc=1
    echo "FAIL: kit-base — the base does not match the manifest it was built from." >&2
    echo "  '-' = the exporter shipped it but the base LACKS it · '+' = in the base but NEVER SHIPPED" >&2
    echo "  (a '+' line is the data-loss case: an adopter-authored file leaked into the base, and a later" >&2
    echo "   diff(base, new-export) would read it as 'the kit deleted this')" >&2
    diff -u "$_stated" "$_inbase" | grep -E '^[+-][^+-]' | head -20 >&2
  fi
  rm -f "$_stated" "$_inbase"
  return $_rc
}

check() {
  _t=$(mktemp -d) || { echo "kit-base: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _p="$_t/proj"

  sh "$ROOT/scripts/adopter-export.sh" "$_p" >/dev/null 2>&1 || {
    echo "FAIL: kit-base — adopter-export failed; cannot assess the base" >&2; return 1; }

  # An adopter-authored file, present BEFORE incept. It must NEVER enter the base.
  echo 'print("my app")' > "$_p/their_app.py"

  ( cd "$_p" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || {
    echo "FAIL: kit-base — could not init the fixture repo" >&2; return 1; }

  # C1 REGRESSION COVERAGE (review #318): a huge fraction of developers set a global core.excludesFile.
  # `git add -A` (no -f) honours it, silently dropping matching kit files from the base while incept still
  # reports success. This fixture RECREATES that environment — ignore `*.md` — so the check runs in the
  # world adopters actually have, not a pristine temp repo. With the `-Af` fix the .md files stay; regress
  # to `-A` and base_is_faithful goes RED (README.md et al. stated in the manifest, absent from the base).
  printf '*.md\n' > "$_t/excludes"
  ( cd "$_p" && git config core.excludesFile "$_t/excludes" )

  # Pin the adopter's HEAD + branch BEFORE incept. Note what is NOT asserted and why: `git status` MUST
  # differ across incept — mutating the tree is incept's whole job. The narrow, meaningful claim is that
  # the KIT-BASE write is invisible to the adopter's working state: it must not move HEAD, must not switch
  # the branch, and must produce an ORPHAN (a base with a parent would drag the adopter's history in).
  _head_before=$( cd "$_p" && git rev-parse HEAD )
  _branch_before=$( cd "$_p" && git rev-parse --abbrev-ref HEAD )

  ( cd "$_p" && sh scripts/incept.sh --noninteractive --name Probe --intent-owner Probe \
      --stack typescript-node --no-db ) >/dev/null 2>&1 || {
    echo "FAIL: kit-base — incept failed on the fixture" >&2; return 1; }

  base_is_faithful "$_p" || return 1

  if [ "$( cd "$_p" && git rev-parse HEAD )" != "$_head_before" ]; then
    echo "FAIL: kit-base — recording the base MOVED the adopter's HEAD" >&2; return 1
  fi
  if [ "$( cd "$_p" && git rev-parse --abbrev-ref HEAD )" != "$_branch_before" ]; then
    echo "FAIL: kit-base — recording the base SWITCHED the adopter's branch (it must be invisible)" >&2; return 1
  fi
  if [ "$( cd "$_p" && git rev-list --count kit-base )" != "1" ]; then
    echo "FAIL: kit-base — kit-base is NOT an orphan (it has parents; it must be a standalone snapshot)" >&2
    return 1
  fi

  # The adopter's own file must not be in the base — the data-loss guard, on the REAL path.
  if git -C "$_p" ls-tree -r --name-only kit-base | grep -qx 'their_app.py'; then
    echo "FAIL: kit-base — an ADOPTER-AUTHORED file (their_app.py) leaked into the base." >&2
    echo "       A later diff(base, new-export) would read it as 'the kit deleted this' and kit-update" >&2
    echo "       would propose DELETING THE ADOPTER'S OWN WORK." >&2
    return 1
  fi

  # The STACK must be recorded. It was the ONE inception input nothing wrote down — and kit-update needs
  # it to prune a new export to the same profile before comparing it against kit-base (an un-pruned export
  # would otherwise read as "the kit added eight profiles").
  if ! grep -q '^\- \*\*Stack profile\*\* (§2): typescript-node' "$_p/CLAUDE.md" 2>/dev/null; then
    echo "FAIL: kit-base — incept did not stamp the stack profile into CLAUDE.md" >&2
    echo "       (the project cannot say which profile it was built from; kit-update cannot shape a delta)" >&2
    return 1
  fi

  # The tag must bind the base to the version it came from.
  _ver=$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)
  if ! git -C "$_p" rev-parse --verify --quiet "refs/tags/kit-base/v${_ver}" >/dev/null 2>&1; then
    echo "FAIL: kit-base — no tag kit-base/v${_ver}; the base is not bound to a kit version" >&2
    return 1
  fi

  # C4 (review #318): base_is_faithful compares the PATH SET only. Prove CONTENT too, on a sample, so a
  # corrupted or dereferenced copy is caught — not just a missing/extra path. The base is the PRE-incept
  # snapshot, so its kit-own blobs must byte-match a fresh pristine export of the same version.
  _pri="$_t/pristine"
  if sh "$ROOT/scripts/adopter-export.sh" "$_pri" >/dev/null 2>&1; then
    for _cf in conformance/verify.sh scripts/incept.sh README.md; do
      [ -f "$_pri/$_cf" ] || continue
      git -C "$_p" show "kit-base:$_cf" > "$_t/blob" 2>/dev/null || {
        echo "FAIL: kit-base — $_cf is in the manifest but has no blob in the base" >&2; return 1; }
      if ! cmp -s "$_t/blob" "$_pri/$_cf"; then
        echo "FAIL: kit-base — content of $_cf in the base differs from a fresh export (corrupt/dereferenced copy)" >&2
        return 1
      fi
    done
  fi

  # --- S1 (BLOCKER, review #318): a symlink in the manifest must NEVER exfiltrate an external file into
  # the base. Plant a secret OUTSIDE the export, name a symlink to it in the manifest, run incept, and
  # assert the sentinel appears in NO ref. The fix refuses the whole base on a symlink; this proves it.
  _s2="$_t/exfil"
  if sh "$ROOT/scripts/adopter-export.sh" "$_s2" >/dev/null 2>&1; then
    printf 'TOP-SECRET-SENTINEL-9f3a\n' > "$_t/secret_outside.txt"
    ( cd "$_s2" && ln -s "$_t/secret_outside.txt" exfil_link && printf 'exfil_link\n' >> .kit-manifest \
        && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
        && sh scripts/incept.sh --noninteractive --name X --intent-owner X --stack typescript-node --no-db ) \
        >/dev/null 2>&1 || true
    if git -C "$_s2" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 \
       && git -C "$_s2" grep -qI 'TOP-SECRET-SENTINEL-9f3a' kit-base -- 2>/dev/null; then
      echo "FAIL: kit-base — a symlinked manifest entry EXFILTRATED an external file into the base." >&2
      echo "       Content from outside the export is now in a committed git ref (review #318 S1)." >&2
      return 1
    fi
  fi

  # --- S2 (MAJOR, review #318): a pre-existing kit-base ref must NOT be clobbered. Build a fresh export,
  # plant a kit-base branch of our own, run incept, and assert it still points where WE put it.
  _s3="$_t/noclobber"
  if sh "$ROOT/scripts/adopter-export.sh" "$_s3" >/dev/null 2>&1; then
    ( cd "$_s3" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
        && git branch kit-base HEAD ) >/dev/null 2>&1 || true
    _pre=$( cd "$_s3" && git rev-parse kit-base 2>/dev/null )
    ( cd "$_s3" && sh scripts/incept.sh --noninteractive --name X --intent-owner X --stack typescript-node --no-db ) \
        >/dev/null 2>&1 || true
    _post=$( cd "$_s3" && git rev-parse kit-base 2>/dev/null )
    if [ -n "$_pre" ] && [ "$_pre" != "$_post" ]; then
      echo "FAIL: kit-base — incept CLOBBERED a pre-existing 'kit-base' branch (review #318 S2)." >&2
      echo "       Silent, after-GC-unrecoverable data loss on a ref the adopter already owned." >&2
      return 1
    fi
  fi

  echo "OK: kit-base — faithful, version-bound base; no adopter file leaked in; symlink exfil refused; existing ref not clobbered"
  echo "HONEST CEILING: proves the base equals the export AS INCEPT RECEIVED IT. Not that the adopter still"
  echo "                has it later; not brownfield end-to-end (P2.2); nothing about the merge itself (P1.2)."
  return 0
}

# ── ORACLE — below the ^selftest() marker; the mutation harness never neuters it. ──
selftest() {
  st=0
  t=$(mktemp -d) || return 2

  _mkrepo() {  # <dir> — a repo whose kit-base is built from an explicit file list
    mkdir -p "$1" && ( cd "$1" && git init -q . )
  }
  _mkbase() {  # <dir> <manifest-content | __NOMANIFEST__> <files-to-put-IN-the-base...>
    _d=$1; _mani=$2; shift 2
    _s=$(mktemp -d)
    # C2 (review #318): a sentinel builds a base with NO .kit-manifest, so NEG-4 actually reaches the
    # "base cannot describe itself" guard instead of passing via the file-list diff (a vacuous fixture).
    [ "$_mani" = "__NOMANIFEST__" ] || printf '%s\n' "$_mani" > "$_s/.kit-manifest"
    # NB: never re-create .kit-manifest in this loop — `: >` would TRUNCATE the content just written.
    for _f in "$@"; do
      [ "$_f" = ".kit-manifest" ] && continue
      mkdir -p "$_s/$(dirname "$_f")"; touch "$_s/$_f"
    done
    # The temp index path must NOT EXIST: git reads an existing EMPTY file as a CORRUPT index.
    _idx=$(mktemp) && rm -f "$_idx"
    _gd=$( cd "$_d" && pwd )/.git
    # -Af: force past any core.excludesFile on the CI runner, so the fixture is environment-independent
    # (the same C1 defect the real path had; a runner ignoring *.txt would otherwise empty these bases).
    ( cd "$_s" && GIT_DIR="$_gd" GIT_INDEX_FILE="$_idx" GIT_WORK_TREE="$_s" git add -Af . )
    _tr=$(GIT_DIR="$_gd" GIT_INDEX_FILE="$_idx" git write-tree)
    _cm=$(GIT_DIR="$_gd" git -c user.email=t@t -c user.name=t commit-tree "$_tr" -m base)
    GIT_DIR="$_gd" git update-ref refs/heads/kit-base "$_cm"
    rm -f "$_idx"; rm -rf "$_s"
  }
  _case() {  # <label> <expected-rc> <repo>
    base_is_faithful "$3" >/dev/null 2>&1 && _got=0 || _got=$?
    if [ "$_got" -eq "$2" ]; then echo "PASS: selftest — $1 (rc $_got)"
    else echo "FAIL: selftest — $1 expected $2 got $_got"; st=1; fi
  }

  # LIVENESS ANCHOR (positive): a base that matches its manifest passes. If this fails, the check is dead.
  _mkrepo "$t/ok"
  _mkbase "$t/ok" '.kit-manifest
a.txt
sub/b.txt' .kit-manifest a.txt sub/b.txt
  _case "base matching its manifest passes (liveness anchor)" 0 "$t/ok"

  # NEGATIVE 1 — THE DATA-LOSS CASE. An adopter file is in the base but was never shipped.
  # If this ever stops being RED, kit-update can propose deleting the adopter's own work.
  _mkrepo "$t/leak"
  _mkbase "$t/leak" '.kit-manifest
a.txt' .kit-manifest a.txt their_app.py
  _case "adopter file leaked INTO the base -> RED (data-loss guard)" 1 "$t/leak"

  # NEGATIVE 2 — the kit shipped a file the base lacks: the base is an incomplete record, so kit-update
  # would treat a kit-own file as adopter-authored and never update it (the cp_kit_replace failure mode).
  _mkrepo "$t/short"
  _mkbase "$t/short" '.kit-manifest
a.txt
missing.txt' .kit-manifest a.txt
  _case "base MISSING a shipped file -> RED" 1 "$t/short"

  # NEGATIVE 3 — no kit-base at all must not pass. An absent base is not a passing one.
  _mkrepo "$t/nobase"
  _case "no kit-base branch -> RED" 1 "$t/nobase"

  # NEGATIVE 4 — a base with NO .kit-manifest cannot describe itself. Uses the __NOMANIFEST__ sentinel so
  # the base genuinely lacks the file and the case reaches the "cannot describe itself" guard (base_is_
  # faithful's `git show kit-base:.kit-manifest` fails) — NOT the file-list diff. Previously this fixture
  # passed via the diff while that guard stayed dead-untested (review #318 C2, the vacuous-anchor pattern).
  _mkrepo "$t/nomani"
  _mkbase "$t/nomani" '__NOMANIFEST__' a.txt
  _case "base without .kit-manifest -> RED (reaches the self-description guard)" 1 "$t/nomani"

  _cleanup "$t"
  [ "$st" -eq 0 ] && echo "kit-base --selftest: OK" || echo "kit-base --selftest: FAIL"
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         check;    exit $? ;;
  *) echo "usage: kit-base.sh [--selftest]" >&2; exit 2 ;;
esac
