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
      --stack typescript-node --no-db ) >"$_t/first.out" 2>&1 || {
    echo "FAIL: kit-base — incept failed on the fixture" >&2; return 1; }
  # CONCORDANCE greenfield ALLOW: a first incept (no prior base) never meets the foreign-base refusal.
  if grep -q 'FOREIGN BASE' "$_t/first.out"; then
    echo "FAIL: kit-base — a GREENFIELD first incept printed the foreign-base refusal" >&2; return 1
  fi

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
  # KIT-UPDATE-BASE-ADVANCES: the export carries .kit-source, so the base carries Kit-Source/Kit-Version
  # trailers equal to it, and the tag is `kit-base/v<VER>+<sha12>` pointing at kit-base.
  _src_sha=$(sed -n 's/^commit //p' "$_p/.kit-source" 2>/dev/null)
  if [ "${#_src_sha}" -ne 40 ]; then
    echo "FAIL: kit-base — the export carries no well-formed .kit-source (commit line)" >&2; return 1
  fi
  _tag="kit-base/v${_ver}+$(printf '%s' "$_src_sha" | cut -c1-12)"
  if [ "$(git -C "$_p" rev-parse --verify --quiet "refs/tags/${_tag}^{commit}" 2>/dev/null)" != "$(git -C "$_p" rev-parse kit-base)" ]; then
    echo "FAIL: kit-base — no tag ${_tag} pointing at kit-base; the base is not bound to a kit commit" >&2
    return 1
  fi
  if [ "$(git -C "$_p" log -1 --format=%B kit-base | sed -n 's/^Kit-Source: //p')" != "$_src_sha" ] \
     || [ "$(git -C "$_p" log -1 --format=%B kit-base | sed -n 's/^Kit-Version: //p')" != "$_ver" ]; then
    echo "FAIL: kit-base — the base commit lacks Kit-Source/Kit-Version trailers equal to .kit-source" >&2
    return 1
  fi
  if ! git -C "$_p" show kit-base:.kit-source >/dev/null 2>&1; then
    echo "FAIL: kit-base — .kit-source is not carried in the base tree" >&2; return 1
  fi
  # LEGACY leg: an export WITHOUT .kit-source keeps today's message and the plain `kit-base/v<VER>` tag.
  _lg="$_t/legacy"
  # an export failure here is a FAIL, never a skip (a skipped leg would read green having proven nothing).
  if ! sh "$ROOT/scripts/adopter-export.sh" "$_lg" >/dev/null 2>&1; then
    echo "FAIL: kit-base — the legacy leg's own export failed (not a skip)" >&2; return 1
  fi
  ( cd "$_lg" && rm -f .kit-source && grep -vx '\.kit-source' .kit-manifest > .km && mv .km .kit-manifest \
      && grep -v ' \.kit-source$' .kit-digests > .kd && mv .kd .kit-digests \
      && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
      && sh scripts/incept.sh --noninteractive --name L --intent-owner L --stack typescript-node --no-db ) \
      >/dev/null 2>&1 || true
  if ! git -C "$_lg" rev-parse --verify --quiet "refs/tags/kit-base/v${_ver}" >/dev/null 2>&1 \
     || [ -n "$(git -C "$_lg" tag -l "kit-base/v${_ver}+*")" ] \
     || git -C "$_lg" log -1 --format=%B kit-base | grep -q '^Kit-Source:'; then
    echo "FAIL: kit-base — a legacy export (no .kit-source) must keep tag kit-base/v${_ver} and no trailer" >&2
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

# ── KIT-BASE-MANIFEST-CONCORDANCE ─────────────────────────────────────────────────────────────────────────
# A second incept over a directory that already holds a `kit-base` must compare the base it would record with
# the one that is there, BEFORE it mutates anything. One load-bearing negative per control:
#   REFUSE        a foreign base (another stack's export) and no flag: rc 1, names kit-update --from first, then both
#                 flags; nothing mutated; the tip unchanged.
#   TREE-IDENTITY the same stack and the same file list but one doc's bytes differ: also refused (a path-set
#                 predicate passes it). The refusal's own counts prove the path sets are equal.
#   REPLACE       --kit-base-replace renames the old base and its colliding tag aside; nothing is deleted.
#   KEEP          --kit-base-keep is today's behaviour, now opt-in and loud.
#   BOTH          both flags together are a usage error (rc 2) before any mutation.
#   ALLOW         the same export re-incepted proceeds, tip unchanged, no refusal text.
_kbm_out=''
_kbm_wipe() {  # <dir> — empty a work tree but keep .git (a "trial" directory that is about to be reused)
  for _kw in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ "${_kw##*/}" = .git ] && continue
    if [ -e "$_kw" ] || [ -L "$_kw" ]; then rm -rf "$_kw"; fi
  done
}
_kbm_commit() {  # <dir> <message>
  ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2" ) >/dev/null 2>&1
}
_kbm_incept() {  # <dir> <stack> [flags...] — output in $_kbm_out; returns incept's own rc
  _ki_d=$1; _ki_s=$2; shift 2
  ( cd "$_ki_d" && sh scripts/incept.sh --noninteractive --name Probe --intent-owner Probe \
      --stack "$_ki_s" --no-db "$@" ) >"$_kbm_out" 2>&1
}
_kbm_reuse() {  # <dir> <scratch> — wipe <dir> (keep .git), drop a FRESH export in, commit it
  rm -rf "$2"
  sh "$ROOT/scripts/adopter-export.sh" "$2" >/dev/null 2>&1 || return 1
  _kbm_wipe "$1"
  cp -R "$2/." "$1/" && _kbm_commit "$1" 'second export'
}
_kbm_seed() {  # <dir> <scratch> [doc] — a repo that was exported, committed and incepted for typescript-node
  sh "$ROOT/scripts/adopter-export.sh" "$1" >/dev/null 2>&1 || return 1
  [ -z "${3:-}" ] || printf '\n<!-- trial edit -->\n' >> "$1/$3"
  ( cd "$1" && git init -q . ) >/dev/null 2>&1 && _kbm_commit "$1" init && _kbm_incept "$1" typescript-node
}
_kbm_tip() { git -C "$1" rev-parse --verify --quiet refs/heads/kit-base 2>/dev/null || echo none; }
_kbm_fail() { echo "FAIL: kit-base [concordance] — $1" >&2; sed 's/^/    | /' "$_kbm_out" >&2 || :; return 1; }

check_concordance() {
  _t=$(mktemp -d "${TMPDIR:-/tmp}/kbm.XXXXXX") || { echo "kit-base: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _kbm_out="$_t/out"
  _ver=$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)

  _kbm_seed "$_t/seed" "$_t/x" || _kbm_fail "could not seed a typescript-node trial" || return 1
  _old=$(_kbm_tip "$_t/seed")
  [ "$_old" != none ] || _kbm_fail "the seed recorded no kit-base (a vacuous fixture)" || return 1
  cp -R "$_t/seed" "$_t/foreign" && cp -R "$_t/seed" "$_t/same" || return 1
  _kbm_reuse "$_t/foreign" "$_t/x1" || _kbm_fail "could not reuse the trial for a python export" || return 1
  # An export is stack-neutral: incepting it with --stack python records a different (pruned) base than the
  # typescript-node one already there. That is the K3 shape (a trial of one stack, then another).

  # REFUSE — rc 1, the upgrade route first, both flags named, the owner's decision stated, no mutation.
  cp -R "$_t/foreign" "$_t/refuse" || return 1
  _rc=0; _kbm_incept "$_t/refuse" python || _rc=$?
  [ "$_rc" -eq 1 ] || _kbm_fail "REFUSE: a foreign base with no flag must exit 1 (got $_rc)" || return 1
  grep -q 'FOREIGN BASE' "$_kbm_out" || _kbm_fail "REFUSE: the refusal does not say FOREIGN BASE" || return 1
  _l_up=$(grep -n 'kit-update --from' "$_kbm_out" | sed -n '1p' | sed 's/:.*//')
  _l_fb=$(grep -n 'FOREIGN BASE' "$_kbm_out" | sed -n '1p' | sed 's/:.*//')
  _l_keep=$(grep -n -e '--kit-base-keep' "$_kbm_out" | sed -n '1p' | sed 's/:.*//')
  _l_rep=$(grep -n -e '--kit-base-replace' "$_kbm_out" | sed -n '1p' | sed 's/:.*//')
  # A1 holds literally: the upgrade route is on the refusal's FIRST line (the one that says FOREIGN BASE), before both flags
  if [ -z "$_l_up" ] || [ -z "$_l_fb" ] || [ -z "$_l_keep" ] || [ -z "$_l_rep" ] || [ "$_l_up" != "$_l_fb" ] || [ "$_l_up" -ge "$_l_keep" ]; then
    _kbm_fail "REFUSE: expected 'kit-update --from' on the FIRST refusal line, before both flags (up=$_l_up first=$_l_fb keep=$_l_keep replace=$_l_rep)" || return 1
  fi
  grep -qi "owner" "$_kbm_out" || _kbm_fail "REFUSE: the message does not say the choice is the owner's" || return 1
  [ ! -e "$_t/refuse/ENGINEERING-PRINCIPLES.md" ] || _kbm_fail "REFUSE: incept MUTATED the tree before refusing" || return 1
  [ "$(_kbm_tip "$_t/refuse")" = "$_old" ] || _kbm_fail "REFUSE: the kit-base tip moved" || return 1
  echo "PASS: kit-base [concordance REFUSE] — a foreign base is refused before any mutation, naming kit-update --from first, then both flags"

  # TREE-IDENTITY — same stack, same path set, one doc's bytes differ in the BASE: also refused.
  _kbm_seed "$_t/m2" "$_t/x" DEVELOPMENT-STANDARDS.md || _kbm_fail "could not seed the byte-edited trial" || return 1
  _old2=$(_kbm_tip "$_t/m2")
  _kbm_reuse "$_t/m2" "$_t/x2" || _kbm_fail "could not reuse the byte-edited trial" || return 1
  _rc=0; _kbm_incept "$_t/m2" typescript-node || _rc=$?
  [ "$_rc" -eq 1 ] || _kbm_fail "TREE-IDENTITY: same stack and file list, different bytes must be refused (got rc $_rc)" || return 1
  grep -q '0 added, 1 modified, 0 deleted' "$_kbm_out" \
    || _kbm_fail "TREE-IDENTITY: the path sets must be EQUAL (0 added, 1 modified, 0 deleted) or this leg proves nothing" || return 1
  [ "$(_kbm_tip "$_t/m2")" = "$_old2" ] || _kbm_fail "TREE-IDENTITY: the kit-base tip moved" || return 1
  echo "PASS: kit-base [concordance TREE-IDENTITY] — an equal path set with one differing doc is refused (a path-set predicate would pass it)"

  # REPLACE — the old base and its colliding tag are renamed aside, never deleted; the new base is the python export.
  cp -R "$_t/foreign" "$_t/replace" || return 1
  _tag_old=$(git -C "$_t/replace" tag -l 'kit-base/*' | sed -n '1p')
  _rc=0; _kbm_incept "$_t/replace" python --kit-base-replace || _rc=$?
  [ "$_rc" -eq 0 ] || _kbm_fail "REPLACE: --kit-base-replace must exit 0 (got $_rc)" || return 1
  git -C "$_t/replace" show kit-base:.kit-manifest 2>/dev/null | grep -q '^profiles/python/' \
    || _kbm_fail "REPLACE: the new kit-base does not carry profiles/python" || return 1
  _aside="kit-base-replaced-$(printf '%s' "$_old" | cut -c1-12)"
  [ "$(git -C "$_t/replace" rev-parse --verify --quiet "refs/heads/$_aside" 2>/dev/null)" = "$_old" ] \
    || _kbm_fail "REPLACE: the old tip is not preserved at $_aside" || return 1
  [ -n "$_tag_old" ] && [ "$(git -C "$_t/replace" rev-parse --verify --quiet "refs/tags/${_tag_old}^{commit}" 2>/dev/null)" = "$(_kbm_tip "$_t/replace")" ] \
    || _kbm_fail "REPLACE: the colliding tag '$_tag_old' does not resolve into the NEW chain" || return 1
  [ "$(git -C "$_t/replace" rev-parse --verify --quiet "refs/tags/kit-base-replaced/${_tag_old#kit-base/}^{commit}" 2>/dev/null)" = "$_old" ] \
    || _kbm_fail "REPLACE: the old tag was not renamed aside to kit-base-replaced/..." || return 1
  echo "PASS: kit-base [concordance REPLACE] — old base kept at $_aside, colliding tag renamed aside, new base is the python export"

  # REPLACE-BLOCKED — a kit-base-replaced/<name> tag already exists, so a kit-base/<name> tag cannot move aside: the replace is
  # UNDONE and fails loudly, never half-moved (old tip and tag where they were, no aside branch).
  cp -R "$_t/foreign" "$_t/blocked" || return 1
  git -C "$_t/blocked" tag "kit-base-replaced/${_tag_old#kit-base/}" "$(git -C "$_t/blocked" rev-parse HEAD)" || return 1
  _rc=0; _kbm_incept "$_t/blocked" python --kit-base-replace || _rc=$?
  [ "$_rc" -ne 0 ] || _kbm_fail "REPLACE-BLOCKED: a replace that could not move a tag must fail, not report success" || return 1
  [ "$(_kbm_tip "$_t/blocked")" = "$_old" ] || _kbm_fail "REPLACE-BLOCKED: the old kit-base tip is not back where it was" || return 1
  [ "$(git -C "$_t/blocked" rev-parse --verify --quiet "refs/tags/${_tag_old}^{commit}" 2>/dev/null)" = "$_old" ] \
    || _kbm_fail "REPLACE-BLOCKED: the old tag '$_tag_old' is not back on the old tip" || return 1
  [ -z "$(git -C "$_t/blocked" for-each-ref 'refs/heads/kit-base-replaced-*')" ] \
    || _kbm_fail "REPLACE-BLOCKED: an aside branch was left behind (half-moved)" || return 1
  grep -q "kit-base-replaced/${_tag_old#kit-base/}" "$_kbm_out" || _kbm_fail "REPLACE-BLOCKED: the failure does not name the tag that blocked it" || return 1
  echo "PASS: kit-base [concordance REPLACE-BLOCKED] — a blocked tag move undoes the replace and fails, naming the tag"

  # HOOKS — the temp-index add that hashes the stage runs no git hook and no configured filter of the repo (a post-index-change
  # hook or a clean filter planted in an adopter's repo must not fire when incept only COMPARES bases).
  cp -R "$_t/foreign" "$_t/hooked" || return 1
  mkdir -p "$_t/hooked/.git/hooks"
  printf '#!/bin/sh\necho fired > "%s/hook.fired"\n' "$_t" > "$_t/hooked/.git/hooks/post-index-change"
  chmod +x "$_t/hooked/.git/hooks/post-index-change"
  printf '#!/bin/sh\necho fired > "%s/filter.fired"\ncat\n' "$_t" > "$_t/clean.sh"
  chmod +x "$_t/clean.sh"
  git -C "$_t/hooked" config filter.kbm.clean "$_t/clean.sh"
  printf '* filter=kbm\n' > "$_t/hooked/.git/info/attributes"
  _rc=0; _kbm_incept "$_t/hooked" python || _rc=$?
  [ "$_rc" -eq 1 ] || _kbm_fail "HOOKS: the foreign-base refusal must still be reached (got $_rc)" || return 1
  [ ! -e "$_t/hook.fired" ] || _kbm_fail "HOOKS: a git hook fired during the base comparison" || return 1
  [ ! -e "$_t/filter.fired" ] || _kbm_fail "HOOKS: a configured clean filter fired during the base comparison" || return 1
  echo "PASS: kit-base [concordance HOOKS] — the base comparison fires no hook and no clean filter"

  # KEEP — today's behaviour, loud: rc 0, tip untouched, kit-update's refusal named.
  cp -R "$_t/foreign" "$_t/keep" || return 1
  _rc=0; _kbm_incept "$_t/keep" python --kit-base-keep || _rc=$?
  [ "$_rc" -eq 0 ] || _kbm_fail "KEEP: --kit-base-keep must exit 0 (got $_rc)" || return 1
  [ "$(_kbm_tip "$_t/keep")" = "$_old" ] || _kbm_fail "KEEP: the kit-base tip moved" || return 1
  grep -q 'FOREIGN BASE' "$_kbm_out" || _kbm_fail "KEEP: the warning does not name kit-update's FOREIGN BASE refusal" || return 1
  echo "PASS: kit-base [concordance KEEP] — --kit-base-keep keeps the foreign base and says kit-update will refuse it"

  # BOTH — a usage error, before any mutation.
  cp -R "$_t/foreign" "$_t/both" || return 1
  _rc=0; _kbm_incept "$_t/both" python --kit-base-keep --kit-base-replace || _rc=$?
  [ "$_rc" -eq 2 ] || _kbm_fail "BOTH: the two flags together must exit 2 (got $_rc)" || return 1
  [ ! -e "$_t/both/ENGINEERING-PRINCIPLES.md" ] || _kbm_fail "BOTH: incept mutated before the usage error" || return 1
  echo "PASS: kit-base [concordance BOTH] — keep and replace together are a usage error"

  # ALLOW — the same export re-incepted: no flag, tip unchanged, no refusal.
  _kbm_reuse "$_t/same" "$_t/x3" || _kbm_fail "could not reuse the trial for the same export" || return 1
  _rc=0; _kbm_incept "$_t/same" typescript-node || _rc=$?
  [ "$_rc" -eq 0 ] || _kbm_fail "ALLOW: re-incepting the same export must exit 0 (got $_rc)" || return 1
  [ "$(_kbm_tip "$_t/same")" = "$_old" ] || _kbm_fail "ALLOW: the kit-base tip moved" || return 1
  if grep -q 'FOREIGN BASE' "$_kbm_out"; then _kbm_fail "ALLOW: the refusal text appeared for an identical export" || return 1; fi
  echo "PASS: kit-base [concordance ALLOW] — the same export re-incepted proceeds and the base is unchanged (tag v${_ver})"
  echo "OK: kit-base [concordance] — refuse, tree identity, replace, keep, both, allow"
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
  "")
    _rc=0
    ( check ); _c=$?; [ "$_c" -eq 0 ] || _rc=$_c
    ( check_concordance ); _k=$?; [ "$_k" -eq 0 ] || _rc=$_k
    exit $_rc ;;
  *) echo "usage: kit-base.sh [--selftest]" >&2; exit 2 ;;
esac
