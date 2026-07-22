#!/bin/sh
# kit-update-merge.sh — THE UPDATE ITSELF: THEIRS, the 3-way merge, and the report it produces.
#
# T3 proved BASE: `incept_old(kit-base)` == the adopter's HEAD, EXACTLY (the identity property, in
# conformance/kit-update-identity.sh). That made the merge WELL-POSED — it did not perform it. This file
# is the other half: the two remaining inputs, the merge, and the honesty of what the tool then SAYS.
#
#   BASE   = incept_old(kit-base)                     <- kit-base's OWN incept   (T3, proven)
#   OURS   = the adopter's HEAD                       <- untouched
#   THEIRS = incept_new(adopter-export(new release))  <- the NEW RELEASE'S OWN exporter + incept
#
# THE ONE RULE THIS FILE EXISTS TO DEFEND: THEIRS is built by RUNNING THE NEW RELEASE'S OWN
# scripts/adopter-export.sh and scripts/incept.sh, with the SAME recorded stamps and the SAME pinned
# --date as BASE. Not a rename table, not a re-implementation of the prune. That is what makes incept's
# transformation CANCEL between the two sides, leaving only genuine kit changes. A hand-maintained table
# would be a second source of truth about incept's behavior and would rot the first time incept changed.
#
# ── WHY THIS CANNOT BE VACUOUS (the point of the whole file) ──────────────────────────────────────────
# An updater that computes NOTHING reports "0 changes" — which reads exactly like the happy no-op. That
# is the failure mode a naive green would hide, so it is the one this check is built to catch:
#
#   * V1  the offered set must be NON-EMPTY for a release that genuinely changed something. A run that
#         found nothing is a FAIL here, never a pass.
#   * V2  the no-op case is asserted SEPARATELY (same release in, "no changes" out) — so "no changes" is
#         only ever green when it is TRUE, and the two cases cannot be confused for one another.
#   * V3  the tool must show its WORK: the entry counts of the three trees it actually built. A tool that
#         computed nothing cannot print three non-zero counts. "0 changes" from empty trees is a FAIL.
#   * V4  a file changed on BOTH sides must NOT appear under `offered` — it must be a CONFLICT. Silently
#         resolving the adopter's edit away would otherwise look like a bigger, better update.
#
#   sh conformance/kit-update-merge.sh
# Exit: 0 = pass · 1 = regression · 2 = usage/UNVERIFIED. POSIX sh; dash-clean.
# What it changes: nothing in the repo — builds a throwaway adopter + a throwaway "new release" in a temp
#                  dir, removed on exit.
# Guardrails: read-only wrt the kit; temp-only writes; teardown non-fatal. Asserts the tool NEVER writes
#             the adopter's worktree or refs (HEAD + refs + `git status` cksummed before and after), and
#             that an empty/absent computation FAILS rather than passing as "no changes".
#
# NOT REGISTERED IN conformance/verify.sh — same reason as conformance/kit-update-identity.sh and
# conformance/kit-base.sh: it runs `incept` inside a fresh export, but an ADOPTER's tree already carries
# ENGINEERING-PRINCIPLES.md, so incept refuses and the check would FAIL for every adopter — and that
# battery is PORTABLE. Its teeth are the four non-vacuity assertions above plus CI wiring.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

# shellcheck disable=SC2329  # invoked INDIRECTLY, from the EXIT/INT/TERM trap in check()
_cleanup() { rm -rf "$1" 2>/dev/null || true; }

STACK=typescript-node
ADOPT_DATE=2020-01-02
GIT_C="git -c user.email=t@t -c user.name=t"

# The two kit-own files the fake release edits. Both ship in the export and neither is renamed by incept,
# so a change to them is a pure upstream kit change — exactly what an update is supposed to offer.
UP_CLEAN=DEVELOPMENT-STANDARDS.md   # upstream only            -> must be OFFERED
UP_BOTH=DEVELOPMENT-PROCESS.md      # upstream AND the adopter -> must be a CONFLICT
MINE=docs/product-notes.md          # adopter-authored only    -> must be named UNTOUCHED

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────────
build_adopter() {  # <dir> — a REAL adopter: exported, committed, incepted, committed.
  sh "$ROOT/scripts/adopter-export.sh" "$1" --profile "$STACK" >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — adopter-export failed; cannot build a fixture adopter" >&2; return 1; }
  ( cd "$1" && git init -q . && git add -A && $GIT_C commit -qm 'kit export' ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — could not init the fixture repo" >&2; return 1; }
  ( cd "$1" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B \
      --stack "$STACK" --date "$ADOPT_DATE" ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — incept failed on the fixture" >&2; return 1; }
  ( cd "$1" && git add -A && $GIT_C commit -qm 'inception' ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — could not commit the incepted fixture" >&2; return 1; }
  git -C "$1" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — incept did not record refs/heads/kit-base" >&2; return 1; }
}

# build_adopter_unpruned <dir> — a LEGACY un-pruned adopter: a project incepted BEFORE prune-at-incept
# (CP-7 recert) shipped, so its tree still carries EVERY stack profile (un-pruned HEAD, kit-base, and
# .kit-manifest). Built by exporting with NO --profile and running incept with its §5a4 prune block
# STRIPPED (so it behaves like the pre-fix incept). This is the fixture the single-profile suite never
# builds; it exercises the T10 MIGRATION — the one-time cleanup kit-update offers such an adopter.
build_adopter_unpruned() {  # <dir>
  sh "$ROOT/scripts/adopter-export.sh" "$1" >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — un-pruned adopter-export failed; cannot build a multi-stack fixture" >&2; return 1; }
  ( cd "$1" && git init -q . && git add -A && $GIT_C commit -qm 'kit export' ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — could not init the un-pruned fixture repo" >&2; return 1; }
  # Simulate a LEGACY adopter (incepted BEFORE prune-at-incept, CP-7 recert): strip incept's §5a4
  # profile-prune block so the fixture keeps ALL profiles — un-pruned HEAD, kit-base, AND .kit-manifest,
  # exactly as a real pre-fix adopter's tree. This is what makes the T10 MIGRATION assertions below
  # non-vacuous: there ARE foreign profiles for the new (pruning) release's kit-update to offer removing.
  awk '/^# --- 5a4\. prune unselected/{s=1} /^# --- 5b0\./{s=0} !s' \
      "$1/scripts/incept.sh" > "$1/scripts/incept.sh.legacy" \
    && mv "$1/scripts/incept.sh.legacy" "$1/scripts/incept.sh" || {
      echo "FAIL: kit-update-merge — could not strip incept's prune block for the legacy fixture" >&2; return 1; }
  # The strip is delimited by two incept.sh comment markers; if the closing `# --- 5b0.` marker is ever
  # renamed the awk over-runs to EOF and could silently mask a regression. Assert the range CLOSED — the
  # 5b0 marker must survive — so a marker rename fails LOUDLY here, not silently downstream.
  grep -q '^# --- 5b0\.' "$1/scripts/incept.sh" || {
    echo "FAIL: kit-update-merge — the prune-block strip over-ran (no '# --- 5b0.' marker left in incept.sh); the §5a4/§5b0 markers may have changed." >&2; return 1; }
  ( cd "$1" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B \
      --stack "$STACK" --date "$ADOPT_DATE" ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — incept failed on the un-pruned fixture" >&2; return 1; }
  ( cd "$1" && git add -A && $GIT_C commit -qm 'inception' ) >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — could not commit the incepted un-pruned fixture" >&2; return 1; }
  git -C "$1" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — incept did not record refs/heads/kit-base (un-pruned)" >&2; return 1; }
}

# The adopter then LIVES in the tree: they author their own file, and they edit one kit doc.
adopter_works() {  # <dir>
  mkdir -p "$(dirname "$1/$MINE")"
  echo '# Product notes (ours)' > "$1/$MINE"
  printf '\n<!-- adopter local note -->\n' >> "$1/$UP_BOTH"
  ( cd "$1" && git add -A && $GIT_C commit -qm 'adopter work' ) >/dev/null 2>&1
}

# A "new release": a CLONE of this kit (so it is a real git repo with a committed HEAD, which is what
# adopter-export needs) plus real kit-own changes and a version bump. `--from` is handed THIS path — a
# local path, so the whole check is offline. No forge, no network, no GitHub-specific anything.
build_release() {  # <dir> <new-version|""(unchanged)>
  git clone --quiet --no-tags "$ROOT" "$1" >/dev/null 2>&1 || {
    echo "FAIL: kit-update-merge — could not clone the kit into a fake release" >&2; return 1; }
  [ -n "${2:-}" ] || return 0            # "" => the SAME release, byte for byte (the no-op case)
  printf '\n## An upstream improvement (fixture)\n' >> "$1/$UP_CLEAN"
  printf '\n## An upstream edit to a doc the adopter also touched (fixture)\n' >> "$1/$UP_BOTH"
  echo "$2" > "$1/VERSION"
  ( cd "$1" && git add -A && $GIT_C commit -qm 'release' ) >/dev/null 2>&1
}

# ── report parsing: the three named categories, read out of the tool's own emitted output ─────────────
# The report is what the adopter actually reads, so the check asserts on the REPORT — not on some internal
# variable. `sed` between the section header and the next blank line.
section() {  # <report-file> <section-key>
  sed -n "/^== $2 /,/^$/p" "$1" | sed -n 's/^  - //p'
}
in_section() { section "$1" "$2" | grep -qxF "$3"; }

# The tool must SAY which merge implementation it took ("merge: <impl> — ...") and it must show that
# implementation's OWN output ("  tree=<oid> files=<N> textual-conflicts=<K>"). Both are parsed here.
merge_impl() {  # <report-file> -> merge-tree | worktree-fallback | ""
  sed -n 's/^merge: \([a-z-]*\).*/\1/p' "$1" | sed -n '1p'
}
merge_field() {  # <report-file> <key: tree|files|textual-conflicts>
  sed -n 's/^  tree=/tree=/p' "$1" | sed -n '1p' | tr ' ' '\n' | sed -n "s/^$2=//p" | sed -n '1p'
}

# host_has_merge_tree <scratch-dir> — can THIS MACHINE's git do `merge-tree --write-tree`?
# A REAL capability probe: run the subcommand, with the exact flags the tool uses, and require a usable
# tree oid back. NEVER a version-string parse — a backport, a wrapper or a stripped build can make version
# and capability disagree (preflight's own honest ceiling says so). It is the same rule the tool follows,
# and it is why this check can compare the two implementations on a modern host and still be honest on an
# old one (where there IS only one implementation, so there is nothing to compare).
host_has_merge_tree() {  # <scratch-dir>
  _c=$1/cap
  mkdir -p "$_c" || return 1
  ( git -c init.defaultBranch=main init -q "$_c" && cd "$_c" && : > f \
      && git add -A && $GIT_C commit -qm probe ) >/dev/null 2>&1 || return 1
  _po=$(git -C "$_c" rev-parse HEAD) || return 1
  _pt=$(git -C "$_c" merge-tree --write-tree --name-only --merge-base="$_po" "$_po" "$_po" 2>/dev/null) || return 1
  git -C "$_c" rev-parse --verify --quiet "$(echo "$_pt" | sed -n '1p')^{tree}" >/dev/null 2>&1
}

# fingerprint <repo> — everything the tool is forbidden to touch: HEAD, every ref, and the worktree state.
fingerprint() {
  echo "HEAD $(git -C "$1" rev-parse HEAD)"
  git -C "$1" show-ref | LC_ALL=C sort
  echo "-- status --"
  git -C "$1" status --porcelain=v1 | LC_ALL=C sort
  echo "-- worktree cksum --"
  ( cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs cksum 2>/dev/null )
  # REF STORAGE, on disk. show-ref reports ref VALUES; this reports the ref FILES. The worktree-fallback
  # merge (T5) creates a worktree and a merge commit — if it ever did so in the ADOPTER's repo instead of
  # the throwaway workbench, it would land here (a new ref file, a rewritten packed-refs) even if the ref
  # values it left behind happened to read the same.
  echo "-- ref storage cksum --"
  ( cd "$1" && find .git/refs .git/packed-refs .git/worktrees -type f -print 2>/dev/null \
      | LC_ALL=C sort | xargs cksum 2>/dev/null )
}

check() {
  _t=$(mktemp -d) || { echo "kit-update-merge: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _p="$_t/proj"
  build_adopter "$_p" || return 1
  adopter_works "$_p"
  _v=$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)
  build_release "$_t/rel" "${_v}-fixture" || return 1

  st=0

  # ── NON-MUTATION — the non-negotiable. Fingerprint BEFORE. ─────────────────────────────────────────
  fingerprint "$_p" > "$_t/fp.before"

  # ── THE RUN ────────────────────────────────────────────────────────────────────────────────────────
  if ! ( cd "$_p" && sh scripts/kit-update.sh --from "$_t/rel" ) >"$_t/report" 2>"$_t/report.err"; then
    echo "FAIL: kit-update-merge — 'kit-update.sh --from <new release>' failed:" >&2
    sed 's/^/    /' "$_t/report" >&2 || :
    sed 's/^/    /' "$_t/report.err" >&2 || :
    return 1
  fi

  fingerprint "$_p" > "$_t/fp.after"
  if diff -u "$_t/fp.before" "$_t/fp.after" >/dev/null 2>&1; then
    echo "PASS: NON-MUTATION — the adopter's HEAD, refs, index and worktree are byte-identical after the run"
  else
    echo "FAIL: NON-MUTATION — kit-update WROTE to the adopter's repo. This is the one thing it must never do:" >&2
    diff -u "$_t/fp.before" "$_t/fp.after" | grep -E '^[+-][^+-]' | head -20 >&2 || :
    st=1
  fi

  # ── V3 — THE TOOL MUST SHOW ITS WORK. Three non-zero tree counts. A tool that computed nothing cannot
  #    print them, and its "0 changes" would otherwise be indistinguishable from an honest no-op. ──────
  _counts=$(sed -n 's/^computed: //p' "$_t/report" | sed -n '1p')
  _nb=$(echo "$_counts" | sed -n 's/.*BASE=\([0-9]*\).*/\1/p')
  _no=$(echo "$_counts" | sed -n 's/.*OURS=\([0-9]*\).*/\1/p')
  _nt=$(echo "$_counts" | sed -n 's/.*THEIRS=\([0-9]*\).*/\1/p')
  if [ -n "${_nb:-}" ] && [ -n "${_no:-}" ] && [ -n "${_nt:-}" ] \
     && [ "$_nb" -gt 0 ] && [ "$_no" -gt 0 ] && [ "$_nt" -gt 0 ]; then
    echo "PASS: non-vacuity [SHOWS-ITS-WORK] — the tool reports three NON-EMPTY trees ($_counts)"
  else
    echo "FAIL: non-vacuity [SHOWS-ITS-WORK] — the tool did not report three non-empty tree counts" >&2
    echo "      (got: '${_counts:-<none>}'). An updater that computed NOTHING reports '0 changes' and" >&2
    echo "      reads exactly like a happy no-op. It must prove it built BASE, OURS and THEIRS." >&2
    st=1
  fi

  # ── V1 — THE OFFERED SET IS NON-EMPTY, and it contains the upstream change. ────────────────────────
  _off=$(section "$_t/report" offered | grep -c . || :)
  if [ "${_off:-0}" -gt 0 ]; then
    echo "PASS: non-vacuity [OFFERED-NON-EMPTY] — a release that genuinely changed something offers $_off file(s)"
  else
    echo "FAIL: non-vacuity [OFFERED-NON-EMPTY] — the release changed kit files and the tool offered NOTHING." >&2
    echo "      '0 changes' from a computation that never happened is the failure this assertion exists for." >&2
    st=1
  fi
  if in_section "$_t/report" offered "$UP_CLEAN"; then
    echo "PASS: offered — the upstream-only change to $UP_CLEAN is offered"
  else
    echo "FAIL: offered — $UP_CLEAN changed upstream, the adopter never touched it, and it was NOT offered." >&2
    st=1
  fi

  # ── V4 — CHANGED ON BOTH SIDES => CONFLICT, and NEVER silently offered. ───────────────────────────
  if in_section "$_t/report" CONFLICT "$UP_BOTH"; then
    echo "PASS: CONFLICT — $UP_BOTH changed on BOTH sides and is reported as a conflict"
  else
    echo "FAIL: CONFLICT — $UP_BOTH changed upstream AND in the adopter's tree; it must be a CONFLICT." >&2
    st=1
  fi
  if in_section "$_t/report" offered "$UP_BOTH"; then
    echo "FAIL: non-vacuity [NEVER-SILENTLY-RESOLVED] — $UP_BOTH was changed on BOTH sides and the tool" >&2
    echo "      OFFERED it anyway. That silently resolves the adopter's edit away — data loss with a" >&2
    echo "      progress bar, and it looks like a bigger, better update." >&2
    st=1
  else
    echo "PASS: non-vacuity [NEVER-SILENTLY-RESOLVED] — a both-sides file is never offered, only conflicted"
  fi

  # ── the adopter's own work is NAMED, not silently ignored ─────────────────────────────────────────
  if in_section "$_t/report" untouched "$MINE"; then
    echo "PASS: untouched — the adopter-authored $MINE is named as untouched"
  else
    echo "FAIL: untouched — $MINE is adopter-authored; the report must NAME it as untouched (silence is" >&2
    echo "      not the same as a promise)." >&2
    st=1
  fi

  # ── THE PATCH — a real, applicable patch at a scratch path outside the repo ────────────────────────
  _patch=$(sed -n 's/^patch: //p' "$_t/report" | sed -n '1p')
  if [ -n "${_patch:-}" ] && [ -s "$_patch" ] && grep -q "$UP_CLEAN" "$_patch"; then
    case "$_patch" in
      "$_p"/*) echo "FAIL: patch — written INSIDE the adopter's repo ('$_patch'). It must go to a scratch path." >&2; st=1 ;;
      *) if ( cd "$_p" && git apply --check "$_patch" ) >/dev/null 2>&1; then
           echo "PASS: patch — a non-empty patch at a scratch path that 'git apply --check' accepts against HEAD"
         else
           echo "FAIL: patch — '$_patch' does not apply cleanly to the adopter's tree ('git apply --check')." >&2
           st=1
         fi ;;
    esac
  else
    echo "FAIL: patch — no non-empty patch containing the offered change was written ('${_patch:-<none>}')." >&2
    st=1
  fi

  # ── THE HONEST CEILING — it must be in the TOOL'S OWN OUTPUT, not only in a doc nobody opens ───────
  _ceil=0
  for _c in 'latest' 'does not apply' 'kit-base' 'EXECUTES'; do
    grep -qi -- "$_c" "$_t/report" || { echo "FAIL: honest ceiling — the tool's output never says '$_c'." >&2; _ceil=1; }
  done
  if [ "$_ceil" -eq 0 ]; then
    echo "PASS: honest ceiling — latest-only, presents-does-not-apply, requires kit-base, and '--from EXECUTES code'"
    echo "      are all in the tool's OWN emitted output"
  else
    echo "      The ceiling has to reach the person pointing this at a URL, at the moment they do it." >&2
    st=1
  fi

  # ── T5 — THE git<2.38 FALLBACK: it must EXIST, be EXERCISED, and AGREE with merge-tree ─────────────
  # scripts/preflight.sh WARNS every adopter on git < 2.38 that kit-update "will use its temporary-worktree
  # fallback" and that the fallback "is still non-mutating". That sentence is a LIE unless three things are
  # true, so all three are asserted — nothing is taken on the tool's word:
  #   (a) the tool SAYS which implementation it took (the adopter cannot verify a path they cannot see);
  #   (b) the fallback really RUNS and really merges (below);
  #   (c) the adopter-visible ANSWER — offered / CONFLICT / untouched — is the SAME either way.
  #
  # WHY (c) ALONE WOULD BE VACUOUS, and what is done about it: offered/CONFLICT/untouched are derived from
  # the BASE/OURS/THEIRS diffs, NOT from the merge — a fallback that merged nothing at all (or was never
  # called, while merge-tree quietly ran anyway) would still produce those three sets. So the merge's OWN
  # output is made observable in the report and asserted directly: the merged tree it built (files=) and
  # the paths git itself could not auto-merge (textual-conflicts=). A fallback that returns garbage, that
  # returns an EMPTY conflict list, or that never runs, goes RED on those.

  # (a) the DEFAULT run must NAME the implementation it took.
  _impl_def=$(merge_impl "$_t/report")
  case "$_impl_def" in
    merge-tree|worktree-fallback)
      echo "PASS: the tool EMITS which merge implementation it took (default run: $_impl_def)" ;;
    *)
      echo "FAIL: the default run never says which merge implementation it used (got '${_impl_def:-<none>}')." >&2
      echo "      An adopter on old git is PROMISED a fallback; they must be able to SEE which path ran." >&2
      st=1 ;;
  esac

  # (b) FORCE the fallback and prove it actually merged.
  if ! ( cd "$_p" && sh scripts/kit-update.sh --from "$_t/rel" --merge-impl worktree ) \
        >"$_t/wt" 2>"$_t/wt.err"; then
    echo "FAIL: fallback — 'kit-update.sh --from <rel> --merge-impl worktree' failed. preflight PROMISES" >&2
    echo "      this path to every adopter on git < 2.38; a promise of a path that does not run is a lie." >&2
    sed 's/^/    /' "$_t/wt" >&2 || :; sed 's/^/    /' "$_t/wt.err" >&2 || :
    st=1
  else
    _impl_wt=$(merge_impl "$_t/wt")
    if [ "${_impl_wt:-}" = worktree-fallback ]; then
      echo "PASS: fallback [ACTUALLY-RAN] — the forced run reports 'merge: worktree-fallback'"
    else
      echo "FAIL: fallback [ACTUALLY-RAN] — --merge-impl worktree reported '${_impl_wt:-<none>}'. A fallback" >&2
      echo "      that is silently skipped while merge-tree runs anyway is the vacuous-green failure class." >&2
      st=1
    fi
    # ITS OWN OUTPUT, not the sets the diffs would have produced anyway: a real merged tree, and a real
    # textual conflict (the fixture edits $UP_BOTH on BOTH sides, so git itself CANNOT auto-merge it).
    _wt_files=$(merge_field "$_t/wt" files)
    _wt_conf=$(merge_field "$_t/wt" textual-conflicts)
    if [ -n "${_wt_files:-}" ] && [ "$_wt_files" -gt 0 ] 2>/dev/null; then
      echo "PASS: fallback [BUILT-A-TREE] — the fallback merged a NON-EMPTY tree ($_wt_files files)"
    else
      echo "FAIL: fallback [BUILT-A-TREE] — no non-empty merged tree reported (files='${_wt_files:-<none>}')." >&2
      st=1
    fi
    if [ -n "${_wt_conf:-}" ] && [ "$_wt_conf" -gt 0 ] 2>/dev/null; then
      echo "PASS: fallback [REALLY-MERGED] — git itself could not auto-merge $_wt_conf path(s) — the 3-way"
      echo "      merge genuinely ran in the fallback (an unexercised fallback reports none)"
    else
      echo "FAIL: fallback [REALLY-MERGED] — the fixture edits $UP_BOTH on BOTH sides, so a real 3-way merge" >&2
      echo "      MUST report a textual conflict. Got textual-conflicts='${_wt_conf:-<none>}' — the merge did" >&2
      echo "      not happen (or its result was thrown away), and the report would still have looked fine." >&2
      st=1
    fi
    # the adopter-visible answer, from the fallback path alone
    if in_section "$_t/wt" offered "$UP_CLEAN" && in_section "$_t/wt" CONFLICT "$UP_BOTH" \
       && in_section "$_t/wt" untouched "$MINE" && ! in_section "$_t/wt" offered "$UP_BOTH"; then
      echo "PASS: fallback — the report it produces is correct on its own terms (offered/CONFLICT/untouched)"
    else
      echo "FAIL: fallback — the fallback's own report is wrong (offered $UP_CLEAN · CONFLICT $UP_BOTH ·" >&2
      echo "      untouched $MINE · never offering a both-sides file)." >&2
      st=1
    fi

    # (c) EQUIVALENCE — same fixture, both implementations, IDENTICAL adopter-visible answer.
    # Only comparable on a host whose git HAS merge-tree; on an old git there is only one path, and
    # inventing a comparison there would be theatre. Probed for real, never inferred from a version.
    if host_has_merge_tree "$_t"; then
      if ! ( cd "$_p" && sh scripts/kit-update.sh --from "$_t/rel" --merge-impl merge-tree ) \
            >"$_t/mt" 2>"$_t/mt.err"; then
        echo "FAIL: --merge-impl merge-tree failed on a host whose git supports it:" >&2
        sed 's/^/    /' "$_t/mt.err" >&2 || :
        st=1
      else
        _impl_mt=$(merge_impl "$_t/mt")
        [ "${_impl_mt:-}" = merge-tree ] || {
          echo "FAIL: --merge-impl merge-tree reported '${_impl_mt:-<none>}'" >&2; st=1; }
        _same=0
        for _s in offered CONFLICT untouched; do
          section "$_t/mt" "$_s" > "$_t/set.mt.$_s"
          section "$_t/wt" "$_s" > "$_t/set.wt.$_s"
          if ! diff -u "$_t/set.mt.$_s" "$_t/set.wt.$_s" > "$_t/setdiff.$_s" 2>&1; then
            echo "FAIL: equivalence — the two merge implementations DISAGREE on the '$_s' set:" >&2
            sed 's/^/      /' "$_t/setdiff.$_s" >&2 || :
            _same=1; st=1
          fi
        done
        _mt_conf=$(merge_field "$_t/mt" textual-conflicts)
        _mt_files=$(merge_field "$_t/mt" files)
        if [ "${_mt_conf:-x}" != "${_wt_conf:-y}" ] || [ "${_mt_files:-x}" != "${_wt_files:-y}" ]; then
          echo "FAIL: equivalence — the two implementations merged DIFFERENTLY: merge-tree" >&2
          echo "      (files=${_mt_files:-?} textual-conflicts=${_mt_conf:-?}) vs worktree-fallback" >&2
          echo "      (files=${_wt_files:-?} textual-conflicts=${_wt_conf:-?})." >&2
          _same=1; st=1
        fi
        if [ "$_same" -eq 0 ]; then
          echo "PASS: equivalence — merge-tree and the worktree fallback produce the SAME offered/CONFLICT/"
          echo "      untouched sets AND the same merged file set ($_mt_files files, $_mt_conf textual conflict(s))"
          echo "      HONEST LIMIT: the merged tree OIDs are NOT compared and are NOT expected to match —"
          echo "      the two engines label conflict hunks differently ('<<<<<<< <oid>' vs '<<<<<<< HEAD')."
        fi
      fi
    else
      echo "SKIP: equivalence — this host's git cannot do 'merge-tree --write-tree' (probed, not assumed),"
      echo "      so there is only ONE implementation here and nothing to compare it against."
    fi

    # (d) THE OLD-GIT SIMULATION — the strongest form of "the fallback ACTUALLY RAN", and the proof that
    # the selection is a real CAPABILITY PROBE. We put a `git` on PATH that is the real git in every
    # respect EXCEPT that `merge-tree` does not exist — which is exactly what git 2.25 (Ubuntu 20.04, the
    # platform this fallback was written for) looks like. Then kit-update is run in its DEFAULT mode, with
    # no flags at all. Two failure classes die here that nothing above can catch:
    #   * A VERSION PARSE instead of a probe: it would read the wrapper's (modern) `git --version`, choose
    #     merge-tree, and the run would FAIL — because the capability is not there. Only an honest probe
    #     of the capability survives.
    #   * A FALLBACK THAT IS MERGE-TREE IN A FALLBACK'S HAT: "silently skipped while merge-tree runs
    #     anyway" is unfalsifiable while merge-tree is available — the emitted label is a CLAIM, not
    #     evidence. Here merge-tree is genuinely gone, so the only way to produce a correct report is to
    #     have genuinely merged without it.
    _bin="$_t/bin"; mkdir -p "$_bin"
    _realgit=$(command -v git)
    cat > "$_bin/git" <<EOF
#!/bin/sh
# a git with NO merge-tree — git < 2.38, simulated
for a in "\$@"; do
  [ "\$a" = merge-tree ] && { echo "git: 'merge-tree' is not a git command" >&2; exit 1; }
done
exec $_realgit "\$@"
EOF
    chmod +x "$_bin/git"
    if ! ( cd "$_p" && PATH="$_bin:$PATH" sh scripts/kit-update.sh --from "$_t/rel" ) \
          >"$_t/old" 2>"$_t/old.err"; then
      echo "FAIL: OLD-GIT — kit-update FAILED on a git without 'merge-tree' (git < 2.38, simulated). That" >&2
      echo "      is the exact platform preflight promises the fallback to. The promise is not kept." >&2
      sed 's/^/    /' "$_t/old.err" >&2 || :
      st=1
    else
      _impl_old=$(merge_impl "$_t/old")
      _old_conf=$(merge_field "$_t/old" textual-conflicts)
      _old_files=$(merge_field "$_t/old" files)
      _oldok=0
      [ "${_impl_old:-}" = worktree-fallback ] || {
        echo "FAIL: OLD-GIT — with merge-tree UNAVAILABLE, the DEFAULT run chose '${_impl_old:-<none>}'." >&2
        echo "      The selection is not probing the capability (a version string is not a capability)." >&2
        _oldok=1; st=1; }
      grep -q 'CANNOT' "$_t/old" || {
        echo "FAIL: OLD-GIT — the tool never says WHY it fell back (the adopter cannot see the probe result)." >&2
        _oldok=1; st=1; }
      [ "${_old_conf:-x}" = "${_wt_conf:-y}" ] && [ "${_old_files:-x}" = "${_wt_files:-y}" ] || {
        echo "FAIL: OLD-GIT — the merge on a merge-tree-less git produced a DIFFERENT result than the same" >&2
        echo "      fallback on this one (files=${_old_files:-?}/${_wt_files:-?} conflicts=${_old_conf:-?}/${_wt_conf:-?})." >&2
        _oldok=1; st=1; }
      if in_section "$_t/old" offered "$UP_CLEAN" && in_section "$_t/old" CONFLICT "$UP_BOTH" \
         && in_section "$_t/old" untouched "$MINE"; then :; else
        echo "FAIL: OLD-GIT — the report produced without merge-tree is WRONG." >&2
        _oldok=1; st=1
      fi
      if [ "$_oldok" -eq 0 ]; then
        echo "PASS: OLD-GIT [PROBE-IS-REAL] — with 'merge-tree' REMOVED from git (2.25 simulated), the"
        echo "      DEFAULT run probes, sees the capability is absent, takes the worktree fallback, SAYS so,"
        echo "      and produces the SAME correct report ($_old_files files, $_old_conf textual conflict(s))."
        echo "      merge-tree cannot have 'run anyway' here — it does not exist."
      fi
    fi

    # NON-MUTATION, on the FALLBACK path specifically. The fallback CHECKS OUT a worktree and COMMITS a
    # merge — the one implementation that could plausibly write somewhere. It must not be here.
    fingerprint "$_p" > "$_t/fp.afterwt"
    if diff -u "$_t/fp.before" "$_t/fp.afterwt" >/dev/null 2>&1; then
      echo "PASS: NON-MUTATION [FALLBACK] — the fallback checks out and commits, and the adopter's HEAD,"
      echo "      refs, ref FILES, index and worktree are still byte-identical"
    else
      echo "FAIL: NON-MUTATION [FALLBACK] — the worktree fallback WROTE to the adopter's repo:" >&2
      diff -u "$_t/fp.before" "$_t/fp.afterwt" | grep -E '^[+-][^+-]' | head -20 >&2 || :
      st=1
    fi
  fi

  # ── V2 — NO-OP HONESTY. The SAME release in => 'no changes' out, said plainly. Asserted SEPARATELY so
  #    that "no changes" can never be green for a run that simply computed nothing (V3 still applies). ─
  build_release "$_t/same" "" || return 1
  if ! ( cd "$_p" && sh scripts/kit-update.sh --from "$_t/same" ) >"$_t/noop" 2>"$_t/noop.err"; then
    echo "FAIL: no-op — kit-update FAILED against the release the adopter is already on:" >&2
    sed 's/^/    /' "$_t/noop" >&2 || :; sed 's/^/    /' "$_t/noop.err" >&2 || :
    st=1
  else
    _noff=$(section "$_t/noop" offered | grep -c . || :)
    _nc=$(sed -n 's/^computed: //p' "$_t/noop" | sed -n '1p')
    _n2=$(echo "$_nc" | sed -n 's/.*THEIRS=\([0-9]*\).*/\1/p')
    if [ "${_noff:-1}" -eq 0 ] && grep -qi 'no changes' "$_t/noop" && [ -n "${_n2:-}" ] && [ "$_n2" -gt 0 ]; then
      echo "PASS: no-op honesty — the same release offers NOTHING, SAYS 'no changes', and still proves it"
      echo "      built a non-empty THEIRS ($_nc) — so 'no changes' means 'nothing changed', not 'nothing ran'"
    else
      echo "FAIL: no-op — updating to the SAME release must report no changes AND say so, while still" >&2
      echo "      proving it computed a non-empty THEIRS. Got: offered=${_noff:-?} theirs=${_n2:-<none>}" >&2
      grep -i 'no changes' "$_t/noop" >/dev/null 2>&1 || echo "      (the words 'no changes' never appear)" >&2
      st=1
    fi
  fi

  # NON-MUTATION, again, after BOTH runs — a tool can be clean once and dirty on the second path.
  fingerprint "$_p" > "$_t/fp.after2"
  if diff -u "$_t/fp.before" "$_t/fp.after2" >/dev/null 2>&1; then
    echo "PASS: NON-MUTATION — still byte-identical after the second (no-op) run"
  else
    echo "FAIL: NON-MUTATION — the adopter's repo changed across the no-op run." >&2
    diff -u "$_t/fp.before" "$_t/fp.after2" | grep -E '^[+-][^+-]' | head -20 >&2 || :
    st=1
  fi

  if [ "$st" -eq 0 ]; then
    echo "OK: kit-update-merge — THEIRS is built by the new release's OWN export+incept, the 3-way merge is"
    echo "    non-mutating, and the report is proven non-vacuous (non-empty offered · both-sides never"
    echo "    silently resolved · three non-empty trees · an honest no-op)"
    echo "    ...and BOTH merge implementations are proven: merge-tree and the git<2.38 worktree fallback"
    echo "    give the SAME answer, the fallback really merges (it is exercised on a git with NO merge-tree"
    echo "    at all), it names the path it took, and it writes nothing of yours either."
    echo "HONEST CEILING: proves the tool PRESENTS a correct delta. It does NOT prove the delta is"
    echo "                semantically desirable, that the adopter's tests pass after applying it, or that"
    echo "                any of it was applied — nothing here applies anything. Applying stays human."
  fi
  return $st
}

# ── T10 — THE LEGACY UN-PRUNED ADOPTER: a one-time MIGRATION to the pruned shape, surgical & non-mutating ─
# CP-7 recert (Option A): incept now PRUNES unselected profiles (a fresh export's un-pruned single project
# ran the emitted whole-tree SAST over foreign scaffolds and reddened the adopter's first CI — the field
# bug). A LEGACY adopter incepted BEFORE that fix still has all profiles on disk (an un-pruned kit-base +
# HEAD + manifest). Their next update to the pruning release must offer a clean ONE-TIME cleanup, NOT a
# guess and NOT data loss. This check builds that legacy fixture (by stripping incept's prune block, above)
# and asserts, TOGETHER:
#   * MIGRATION-REMOVES-FOREIGN — EVERY foreign (non-$STACK) profile file the adopter kept is offered for
#     removal (complete — count matches the manifest), so the cleanup is not partial;
#   * KEPT-PROFILE-PRESERVED — NOT ONE kept path (profiles/$STACK/, ratification.yml, _TEMPLATE.md,
#     .gitignore) is
#     offered — the migration is surgical, never over-pruning the adopter's OWN stack;
#   * ADOPTER-FILE-PRESERVED — an adopter-authored file is never offered for removal;
#   * NON-MUTATION — kit-update writes NOTHING to the adopter's repo;
#   * TEETH — a GENUINE upstream deletion of a KEPT-stack profile file IS still offered (the migration does
#     not blanket-suppress real removals in the adopter's own stack). Distinguished via the manifest/BASE.
check_unpruned() {
  _t=$(mktemp -d) || { echo "kit-update-merge: cannot mktemp (unpruned)" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _p="$_t/proj"
  build_adopter_unpruned "$_p" || return 1
  _v=$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)
  st=0

  # The fixture must ACTUALLY be un-pruned, or every T10 assertion below is vacuous.
  _others=$(git -C "$_p" show kit-base:.kit-manifest 2>/dev/null \
    | sed -n 's#^profiles/\([^/]*\)/.*#\1#p' | LC_ALL=C sort -u | grep -vxF "$STACK" | grep -c . || :)
  if [ "${_others:-0}" -gt 0 ]; then
    echo "PASS: T10 fixture — the adopter kept $_others profile dir(s) beyond '$STACK' (a real multi-stack adopter)"
  else
    echo "FAIL: T10 fixture — the fixture is not actually un-pruned; the T10 assertions would be vacuous." >&2
    return 1
  fi

  # Give the un-pruned adopter an authored file, so the migration below can be proven to preserve it.
  mkdir -p "$_p/$(dirname "$MINE")" && echo '# product notes (ours)' > "$_p/$MINE"
  ( cd "$_p" && git add -A && $GIT_C commit -qm 'adopter work' ) >/dev/null 2>&1 || {
    echo "FAIL: T10 — could not add an adopter-authored file to the un-pruned fixture" >&2; return 1; }

  fingerprint "$_p" > "$_t/fp.before"

  # ── THE MIGRATION (CP-7 recert, Option A): a LEGACY un-pruned adopter (all profiles on disk, incepted
  #    BEFORE prune-at-incept) updating to the now-pruning release is offered a ONE-TIME cleanup — removal
  #    of EXACTLY the foreign (non-$STACK) profiles, the shape incept now produces. It must be SURGICAL:
  #    remove every foreign profile file (complete), NEVER the adopter's OWN stack profile, NEVER an
  #    adopter-authored file. (Pre-CP-7 the invariant was the OPPOSITE — "offer no profile deletions" —
  #    because incept kept all profiles; but that un-pruned single project's whole-tree SAST was the RED
  #    field bug this recert fixes, so keeping it was never actually viable.)
  build_release "$_t/same" "" || return 1
  if ! ( cd "$_p" && sh scripts/kit-update.sh --from "$_t/same" ) >"$_t/noop" 2>"$_t/noop.err"; then
    echo "FAIL: T10 — kit-update FAILED for the un-pruned adopter migration:" >&2
    sed 's/^/    /' "$_t/noop" >&2 || :; sed 's/^/    /' "$_t/noop.err" >&2 || :
    return 1
  fi
  # kept vs foreign, by the SAME filter over the offered set AND the adopter's own manifest.
  # THE KEPT SET. `.gitignore` joined it in v3.171.0 (CP7R5-K4-IGNORE): profiles/.gitignore is a
  # TREE-LEVEL file that must outlive the prune. Omitting it here counts a correctly-KEPT file as a
  # foreign leftover in _foreign_have while it is (correctly) absent from _foreign_off, so the two
  # counts differ by one and MIGRATION-REMOVES-FOREIGN fails with a bogus "incomplete migration".
  # This enumeration is duplicated in conformance/incept-first-run-green.sh — change both together.
  _keptfilter="^profiles/$STACK/|^profiles/$STACK\.md\$|^profiles/ratification\.yml\$|^profiles/_TEMPLATE\.md\$|^profiles/\.gitignore\$"
  _foreign_off=$(section "$_t/noop" offered | grep '^profiles/' | grep -vE "$_keptfilter" | grep -c . || :)
  _kept_off=$(section "$_t/noop" offered | grep -E "$_keptfilter" | grep -c . || :)
  _foreign_have=$(git -C "$_p" show kit-base:.kit-manifest 2>/dev/null \
    | grep '^profiles/' | grep -vE "$_keptfilter" | grep -c . || :)

  # (1) MIGRATION-REMOVES-FOREIGN — every foreign profile file the adopter kept is offered for removal.
  if [ "${_foreign_off:-0}" -gt 0 ] && [ "$_foreign_off" = "$_foreign_have" ]; then
    echo "PASS: T10 [MIGRATION-REMOVES-FOREIGN] — all $_foreign_off foreign-profile file(s) are offered for"
    echo "      removal (the one-time cleanup to the pruned shape incept now produces)"
  else
    echo "FAIL: T10 [MIGRATION-REMOVES-FOREIGN] — offered $_foreign_off foreign-profile file(s) but the adopter" >&2
    echo "      holds $_foreign_have (kit-base:.kit-manifest); the migration is empty or INCOMPLETE." >&2
    st=1
  fi

  # (2) KEPT-PROFILE-PRESERVED — the migration NEVER offers to delete the adopter's OWN stack profile (nor
  #     ratification.yml / _TEMPLATE.md / .gitignore). The surgical half: an over-prune of the adopter's
  #     stack fails here.
  if [ "${_kept_off:-0}" -eq 0 ]; then
    echo "PASS: T10 [KEPT-PROFILE-PRESERVED] — not one kept path (profiles/$STACK/, ratification.yml, _TEMPLATE.md) is offered"
  else
    echo "FAIL: T10 [KEPT-PROFILE-PRESERVED] — $_kept_off kept profile path(s) offered — the migration over-pruned the adopter's OWN stack." >&2
    st=1
  fi

  # (3) ADOPTER-FILE-PRESERVED — an adopter-authored file is NEVER offered for removal.
  if ! in_section "$_t/noop" offered "$MINE"; then
    echo "PASS: T10 [ADOPTER-FILE-PRESERVED] — the adopter-authored $MINE is not offered for removal"
  else
    echo "FAIL: T10 [ADOPTER-FILE-PRESERVED] — the migration offered to delete the adopter-authored $MINE." >&2
    st=1
  fi

  # (4) DELETES-ONLY-FOREIGN — the BOUND (dual-review hardening): the "surgical" claim above spot-checks
  #     specific paths; this bounds it. EVERY file the migration PATCH deletes must be a foreign profile —
  #     nothing kept (profiles/$STACK/, ratification.yml, _TEMPLATE.md) and nothing OUTSIDE profiles/ (a
  #     doc, a root file, an adopter file). Offered MODIFICATIONS (e.g. the STACK-SELECTION.md stub) are
  #     fine — only DELETIONS are bounded, read from the patch's `deleted file mode` markers.
  _mpatch=$(sed -n 's/^patch: //p' "$_t/noop" | sed -n '1p')
  if [ -n "$_mpatch" ] && [ -f "$_mpatch" ]; then
    _deleted=$(awk '/^diff --git a\// { p=$3; sub(/^a\//,"",p) } /^deleted file mode/ { print p }' "$_mpatch")
    _bad_del=$(printf '%s\n' "$_deleted" | grep -vE "^profiles/" | grep -c . || :)
    _kept_del=$(printf '%s\n' "$_deleted" | grep -E "$_keptfilter" | grep -c . || :)
    if [ "${_bad_del:-0}" -eq 0 ] && [ "${_kept_del:-0}" -eq 0 ]; then
      echo "PASS: T10 [DELETES-ONLY-FOREIGN] — every file the migration patch DELETES is a foreign profile (no kept/non-profile deletion)"
    else
      echo "FAIL: T10 [DELETES-ONLY-FOREIGN] — the migration patch deletes $_bad_del non-profile and $_kept_del kept-profile file(s) it must not:" >&2
      printf '%s\n' "$_deleted" | grep -vE "^profiles/" | sed 's/^/      non-profile: /' >&2 || :
      printf '%s\n' "$_deleted" | grep -E "$_keptfilter" | sed 's/^/      kept: /' >&2 || :
      st=1
    fi
  else
    echo "FAIL: T10 [DELETES-ONLY-FOREIGN] — no migration patch to bound (the cleanup should emit one)." >&2
    st=1
  fi

  fingerprint "$_p" > "$_t/fp.after"
  if diff -u "$_t/fp.before" "$_t/fp.after" >/dev/null 2>&1; then
    echo "PASS: T10 NON-MUTATION — the un-pruned adopter's HEAD, refs, index and worktree are byte-identical"
  else
    echo "FAIL: T10 NON-MUTATION — kit-update WROTE to the un-pruned adopter's repo:" >&2
    diff -u "$_t/fp.before" "$_t/fp.after" | grep -E '^[+-][^+-]' | head -20 >&2 || :
    st=1
  fi

  # ── TEETH — a GENUINE upstream deletion of a KEPT ($STACK) profile file is STILL offered. The migration
  #    removes FOREIGN profiles by SHAPE (manifest/BASE), but it must NOT blanket-suppress real deletions in
  #    the profile the adopter actually keeps: if upstream genuinely removes a profiles/$STACK/ file, THEIRS
  #    lacks it and the adopter has it, so it must be offered. A fix that hid THIS would be concealing real
  #    removals in the adopter's own stack (distinguished via the manifest/BASE, not via THEIRS's prune).
  _del=$(git -C "$_p" show kit-base:.kit-manifest 2>/dev/null \
    | grep "^profiles/$STACK/" | LC_ALL=C sort | sed -n '1p')
  if [ -z "$_del" ] || ! git -C "$_p" cat-file -e "HEAD:$_del" 2>/dev/null; then
    echo "FAIL: T10 [GENUINE-DELETION] — could not find a kept-stack profile file to delete ('${_del:-<none>}')." >&2
    st=1
  else
    git clone --quiet --no-tags "$ROOT" "$_t/del" >/dev/null 2>&1 || {
      echo "FAIL: T10 [GENUINE-DELETION] — could not clone a fake release" >&2; return 1; }
    ( cd "$_t/del" && git rm -q "$_del" && echo "${_v}-del" > VERSION \
        && git add -A && $GIT_C commit -qm 'release: genuinely remove a kept-stack profile file' ) >/dev/null 2>&1 || {
      echo "FAIL: T10 [GENUINE-DELETION] — could not build the deleting release" >&2; return 1; }
    if ! ( cd "$_p" && sh scripts/kit-update.sh --from "$_t/del" ) >"$_t/del.out" 2>"$_t/del.err"; then
      echo "FAIL: T10 [GENUINE-DELETION] — kit-update failed against a release that removed a kept-stack profile file:" >&2
      sed 's/^/    /' "$_t/del.err" >&2 || :
      st=1
    else
      _delpatch=$(sed -n 's/^patch: //p' "$_t/del.out" | sed -n '1p')
      if in_section "$_t/del.out" offered "$_del" \
         && [ -n "$_delpatch" ] && [ -f "$_delpatch" ] \
         && grep -q "^diff --git a/$_del" "$_delpatch"; then
        echo "PASS: T10 [GENUINE-DELETION-STILL-OFFERED] — a real upstream removal of the kept-stack file"
        echo "      $_del IS offered, so the migration does not blanket-suppress real deletions in the"
        echo "      adopter's OWN stack (distinguished via the manifest/BASE, not via THEIRS's prune)"
      else
        echo "FAIL: T10 [GENUINE-DELETION-STILL-OFFERED] — a genuine upstream deletion of the kept-stack file" >&2
        echo "      $_del was NOT offered (in patch='${_delpatch:-<none>}'). The migration has over-corrected" >&2
        echo "      into HIDING real deletions in the adopter's OWN stack." >&2
        st=1
      fi
    fi
  fi

  if [ "$st" -eq 0 ]; then
    echo "OK: kit-update-merge [T10] — a LEGACY un-pruned (multi-stack) adopter migrating to the pruning"
    echo "    release is offered removal of EXACTLY the foreign profiles (complete), never its OWN stack"
    echo "    profile nor an adopter-authored file, and a genuine kept-stack deletion is still offered —"
    echo "    non-mutating throughout."
  fi
  return $st
}

case "${1:-}" in
  "")
    _rc=0
    ( check ); _c=$?; [ "$_c" -eq 0 ] || _rc=$_c
    ( check_unpruned ); _u=$?; [ "$_u" -eq 0 ] || _rc=$_u
    exit $_rc ;;
  *) echo "usage: kit-update-merge.sh" >&2; exit 2 ;;
esac
