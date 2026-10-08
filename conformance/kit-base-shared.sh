#!/bin/sh
# kit-base-shared.sh — a clone or a teammate gets the kit-base from the remote, VERIFIED before it is used
# (KIT-BASE-SHARED).
#
# THE DEFECT THIS LOCKS: `kit-base` is the merge base every `kit-update --from` needs. Nothing ever RECEIVED
# it: a fresh clone had none (`no 'kit-base' branch`), a teammate's advance stranded everyone else, and the
# only way back was a hand `git fetch origin refs/kit/base:refs/heads/kit-base` — an UNVERIFIED code-
# execution channel, because every `--from` re-runs the chain commits' OWN scripts/incept.sh and
# `refs/kit/base` is outside branch protection. Now `--from` and `--advance-base` IMPORT the remote chain,
# and an imported commit is written only after `verify_chain_commit`: its Kit-Source resolves in --from, and
# EVERY tree entry (mode, blob, path) is an entry of one of the two exports (un-pruned, `--profile <stack>`)
# that Kit-Source's OWN exporter produces. `--publish-base` is the explicit, never-forced publish.
#
# Fixture: a throwaway VENDOR git repo (a clone of this kit) with R0 (the kit as it stands) and R1 (one
# kit-own file edited); a REAL incepted project (from R0); BARE local remotes and clones of the project. The
# vendor is a local path. No network.
#
#   leg  asserts
#   F    incept's next steps name `kit-update --publish-base`
#   S2   a remote without refs/kit/base, and no remote at all: today's refusal text + the publish line, rc 1,
#        no ref written
#   S9   the local base exists, the remote lacks it: `--from` prints the publish notice; rc unchanged
#   P1   `--publish-base` pushes refs/kit/base (+ the chain's own tag); no remote -> rc 1
#   S1   publish, then a FRESH CLONE runs `--from`: it imports, and the report is byte-equal to the original
#        clone's (after the patch path is normalised)
#   S3   a teammate advances and publishes; the other clone pulls and runs `--from`: it fast-forwards, is not
#        refused as STALE, and its base equals the remote's
#   S4   diverged: rc 1, BOTH tips printed, no ref moved
#   S5   FORGED TREE (the load-bearing negative): a pushed chain commit whose scripts/incept.sh is altered, with
#        a GENUINE Kit-Source: refused naming the entry; no kit-base; the altered incept NEVER RAN (a canary)
#   S6   unverifiable: Kit-Source not in --from; no Kit-Source at all — refused, nothing written
#   S7   a symlink entry / a submodule entry in a chain tree — refused
#   S8   tags: the chain's own tag arrives; a lookalike does not; an existing local tag is never moved
#   S10  one negative per attack shape, each pushed as a chain and refused naming why: an extra file in no export; a mode
#        flip; an entry from another release's export; a control-byte path; a two-parent commit; a non-monotonic chain; a
#        corrupt `behind` block (refused at import); a dropped file (the path set is no export's)
#   S11  fail closed, the RUN does not: a valid local base + a forged extension -> a WARNING, nothing written, the run
#        continues on the local base (rc 0); diverged / unrecorded outputs print NO raw ref-writing import command (S4, S6)
#   M1   non-vacuity: `_KU_VERIFY_IMPORT=on` -> `off` in a COPY: the forged chain IMPORTS and its incept RUNS
#   M2   non-vacuity of the ANCHOR: `_KU_ANCHOR=on` -> `off`: a genuine chain of a release the project's history never
#        recorded (refused with the anchor) IMPORTS without it
#
#   sh conformance/kit-base-shared.sh
# Exit: 0 = pass · 1 = regression · 2 = usage/UNVERIFIED. POSIX sh; dash-clean.
# What it changes: nothing in the repo — builds a vendor repo, a project, bare remotes, clones and a mutated
#                  copy of kit-update.sh in a temp dir, removed on exit.
# Guardrails: read-only wrt the kit; temp-only writes; teardown non-fatal. The refusals are fingerprinted (every
#             ref) before and after: a refused import writes NOTHING.
# Runtime: ~4-6 minutes (each full `--from` re-runs a real export+incept for THEIRS and BASE, ~9 s each; each
#          imported chain commit costs two exports, ~1 s each).
#
# NOT REGISTERED IN conformance/verify.sh — same reason as conformance/kit-update-advance.sh: it runs `incept`
# in a fresh export, which refuses on an ADOPTER's tree, and that battery is PORTABLE. It is a kit-CI step
# beside kit-update-advance.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

# shellcheck disable=SC2329  # invoked INDIRECTLY, from the EXIT/INT/TERM trap in check()
_cleanup() { rm -rf "$1" 2>/dev/null || true; }

STACK=typescript-node
ADOPT_DATE=2020-01-02
GIT_C="git -c user.email=t@t -c user.name=t"
KU="$ROOT/scripts/kit-update.sh"
VER=$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)
UP_A=DEVELOPMENT-STANDARDS.md        # R1 edits it (the one change the fake release makes)

ST=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; ST=1; }
sha12() { printf '%s' "$1" | cut -c1-12; }

# ── fixtures ───────────────────────────────────────────────────────────────────────────────────────────
build_vendor() {  # <dir> — R0 = this kit's HEAD, R1 = one edit on top. Sets R0 R1.
  git clone --quiet --no-tags "$ROOT" "$1" >/dev/null 2>&1 || { fail "could not clone the kit into a vendor repo"; return 1; }
  R0=$(git -C "$1" rev-parse HEAD)
  printf '\n## R1 upstream change (kit-base-shared fixture)\n' >> "$1/$UP_A"
  ( cd "$1" && git add -A && $GIT_C commit -qm 'R1: one standards edit (fixture)' ) >/dev/null 2>&1 \
    || { fail "could not commit R1"; return 1; }
  R1=$(git -C "$1" rev-parse HEAD)
}
checkout_at() {  # <vendor> <sha> <dir> — a clone with HEAD detached at <sha>: a "release" to --from
  if git clone --quiet --no-tags "$1" "$3" >/dev/null 2>&1 && git -C "$3" checkout -q --detach "$2" >/dev/null 2>&1; then return 0; fi
  fail "could not check out $2 of the vendor"; return 1
}
build_project() {  # <dir> <src-at-R0> — a REAL project: exported, committed, incepted, committed. incept's output -> <dir>.incept.log
  sh "$2/scripts/adopter-export.sh" "$1" --profile "$STACK" >/dev/null 2>&1 || { fail "adopter-export failed"; return 1; }
  ( cd "$1" && git init -q . && git add -A && $GIT_C commit -qm 'kit export' ) >/dev/null 2>&1 || { fail "could not init the fixture repo"; return 1; }
  ( cd "$1" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B --stack "$STACK" --date "$ADOPT_DATE" ) >"$1.incept.log" 2>&1 \
    || { fail "incept failed on the fixture"; return 1; }
  ( cd "$1" && git add -A && $GIT_C commit -qm 'inception' ) >/dev/null 2>&1 || { fail "could not commit the incepted fixture"; return 1; }
  git -C "$1" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 || { fail "incept did not record refs/heads/kit-base"; return 1; }
}
mk_remote() {  # <project> <bare dir> — a bare copy of the project's branches with NO kit-base refs (no shared base yet)
  git clone -q --bare "$1" "$2" >/dev/null 2>&1 || { fail "could not make the bare remote $2"; return 1; }
  _mr_b=$(git -C "$1" symbolic-ref --short HEAD)
  git -C "$2" symbolic-ref HEAD "refs/heads/$_mr_b"
  for _mr_r in $(git -C "$2" for-each-ref --format='%(refname)' refs/heads/kit-base refs/tags/kit-base/); do
    git -C "$2" update-ref -d "$_mr_r"
  done
}
refs_of() { git -C "$1" show-ref | LC_ALL=C sort; }   # <repo> — every ref, for the "nothing written" proofs

KU_RC=0
ku() {  # <repo> <script> <out> <args…> — rc to $KU_RC, merged output to <out>
  _ku_a=$1; _ku_s=$2; _ku_o=$3; shift 3
  KU_RC=0
  ( cd "$_ku_a" && sh "$_ku_s" --repo "$_ku_a" "$@" ) >"$_ku_o" 2>&1 || KU_RC=$?
}
has() { grep -Eq -- "$2" "$1"; }   # <file> <ERE>

# refuses_with <leg> <repo> <out> <ERE> <script-args…> — rc 1, names <ERE>, and EVERY ref is unchanged
refuses_with() {
  _rw_leg=$1; _rw_r=$2; _rw_o=$3; _rw_re=$4; shift 4
  refs_of "$_rw_r" > "$_rw_o.r0"
  ku "$_rw_r" "$KU" "$_rw_o" "$@"
  refs_of "$_rw_r" > "$_rw_o.r1"
  if [ "$KU_RC" -eq 1 ] && has "$_rw_o" "$_rw_re"; then
    pass "$_rw_leg — rc 1 and names the reason ('$_rw_re')"
  else
    fail "$_rw_leg — expected rc 1 naming '$_rw_re'; got rc=$KU_RC: $(brief "$_rw_o")"
  fi
  if diff "$_rw_o.r0" "$_rw_o.r1" >/dev/null 2>&1 && ! git -C "$_rw_r" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1; then
    pass "$_rw_leg [writes nothing] — every ref is unchanged and there is no kit-base"
  else
    fail "$_rw_leg [writes nothing] — the refused run changed the repo's refs, or a kit-base appeared"
  fi
}

# forge_root <project> <tree> <message-file> -> prints a ROOT commit (no parent) of <tree>, made in <project>'s object store
forge_root() { git -C "$1" -c user.email=t@t -c user.name=t commit-tree "$2" -F "$3"; }
# chain_msg <file> <Kit-Source|-> — a chain commit message; '-' omits the Kit-Source trailer
chain_msg() {
  { printf 'kit-base: pristine Sparkwright export (kit-base-shared fixture)\n\n'
    [ "$2" = - ] || printf 'Kit-Source: %s\n' "$2"
    printf 'Kit-Version: %s\nKit-Behind: 0\n' "$VER"
  } > "$1"
}
# tree_with <project> <base-tree> <mode> <path> <blob> -> a tree = <base-tree> with <path> set to <blob> at <mode>
tree_with() {
  _tw_i="$_t/forge.idx.$$"; rm -f "$_tw_i"
  GIT_INDEX_FILE=$_tw_i git -C "$1" read-tree "$2" || return 1
  GIT_INDEX_FILE=$_tw_i git -C "$1" update-index --add --cacheinfo "$3,$5,$4" || return 1
  GIT_INDEX_FILE=$_tw_i git -C "$1" write-tree
  rm -f "$_tw_i"
}
push_base() {  # <project> <bare remote> <commit> — set the remote's refs/kit/base to <commit> (a forced FIXTURE push)
  git -C "$2" update-ref -d refs/kit/base >/dev/null 2>&1 || :   # delete, then a plain push: the installed kit pre-push hook refuses a forced one
  git -C "$1" push -q "$2" "$3:refs/kit/base" >"$_t/push.err" 2>&1 || { sed -n '1,4p' "$_t/push.err" >&2; return 1; }
}
brief() { grep -e '^kit-' -e '^  [A-Za-z]' "$1" | grep -v -e 'THIS EXECUTES' | sed -n '1,8p' | tr '\n' '|'; }   # <out> — the tool's own lines, not the warning block

mutate_verify() {  # <src> <dst> — the M1 mutant: the greppable switch `_KU_VERIFY_IMPORT=on` -> `off`, ONE line, verified
  [ "$(grep -c '^_KU_VERIFY_IMPORT=on' "$1" || :)" -eq 1 ] || return 1
  sed 's/^_KU_VERIFY_IMPORT=on/_KU_VERIFY_IMPORT=off/' "$1" > "$2" || return 1
  [ "$(grep -c '^_KU_VERIFY_IMPORT=off' "$2" || :)" -eq 1 ] && ! grep -q '^_KU_VERIFY_IMPORT=on' "$2"
}

mutate_anchor() {  # <src> <dst> — the M2 mutant: `_KU_ANCHOR=on` -> `off`, ONE line, verified
  [ "$(grep -c '^_KU_ANCHOR=on' "$1" || :)" -eq 1 ] || return 1
  sed 's/^_KU_ANCHOR=on/_KU_ANCHOR=off/' "$1" > "$2" || return 1
  [ "$(grep -c '^_KU_ANCHOR=off' "$2" || :)" -eq 1 ] && ! grep -q '^_KU_ANCHOR=on' "$2"
}

# the pre-KIT-BASE-SHARED refusal, verbatim (S2 pins it; the ONE addition is the --publish-base line)
expected_refusal() {  # <repo> -> the refusal block as the tool prints it
  cat <<EOF
kit-update: no 'kit-base' branch in $1.
  kit-base is the PRISTINE EXPORT this project was adopted from — the merge base every update
  needs. incept vendors it (branch 'kit-base', tag 'kit-base/v<VER>+<sha12>'). It is missing because
  either (a) it was deleted, or (b) this project was incepted from a kit that predates the
  mechanism. There is NO safe fallback: a guessed base yields a WRONG delta, which is worse
  than no delta. Recover the branch from YOUR OWN reflog (git reflog), or re-adopt.
  whoever holds the base: kit-update --publish-base
  See docs/operations/kit-base.md.
EOF
}

# ══ THE CHECK ═══════════════════════════════════════════════════════════════════════════════════════════
check() {
  _t=$(mktemp -d) || { echo "kit-base-shared: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _t0=$(date +%s)

  build_vendor "$_t/vendor" || return 1
  checkout_at "$_t/vendor" "$R0" "$_t/src0" || return 1
  checkout_at "$_t/vendor" "$R1" "$_t/src1" || return 1
  [ "$R0" != "$R1" ] || { fail "fixture: R0 and R1 are not distinct"; return 1; }
  proj=$_t/proj
  build_project "$proj" "$_t/src0" || return 1
  _br=$(git -C "$proj" symbolic-ref --short HEAD)
  _tag0="kit-base/v$VER+$(sha12 "$R0")"
  git -C "$proj" rev-parse --verify --quiet "refs/tags/$_tag0" >/dev/null 2>&1 || { fail "fixture: incept recorded no tag $_tag0"; return 1; }
  org=$_t/org.git
  mk_remote "$proj" "$org" || return 1
  git -C "$proj" remote add origin "$org" && git -C "$proj" fetch -q origin >/dev/null 2>&1 \
    && git -C "$proj" remote set-head origin -a >/dev/null 2>&1 || { fail "fixture: could not wire origin"; return 1; }

  # F — incept tells the person who ran it to share the base
  if has "$proj.incept.log" 'kit-update\.sh --publish-base'; then
    pass "F [INCEPT-NEXT-STEP] — incept's next steps name 'sh scripts/kit-update.sh --publish-base'"
  else
    fail "F [INCEPT-NEXT-STEP] — incept's output does not name 'kit-update.sh --publish-base'"
  fi

  # S2 — nothing to import: a clone of a remote WITHOUT refs/kit/base, and a clone with NO remote at all
  git clone -q --no-tags "$org" "$_t/c" >/dev/null 2>&1 || { fail "fixture: could not clone the remote"; return 1; }
  refuses_with 'S2 remote-lacks-the-base' "$_t/c" "$_t/s2a" 'no .kit-base. branch' --from "$_t/src0"
  has "$_t/s2a" "kit-update --publish-base" && pass "S2 [PUBLISH-LINE] — the refusal names '--publish-base'" \
    || fail "S2 [PUBLISH-LINE] — the refusal does not name '--publish-base'"
  git -C "$_t/c" remote remove origin >/dev/null 2>&1 || :
  refuses_with 'S2 no-remote-at-all' "$_t/c" "$_t/s2b" 'no .kit-base. branch' --from "$_t/src0"
  sed -n "/^kit-update: no 'kit-base' branch/,\$p" "$_t/s2b" > "$_t/s2b.block"
  expected_refusal "$( CDPATH='' cd "$_t/c" && pwd -P )" > "$_t/s2b.want"   # the tool prints the PHYSICAL path
  if diff "$_t/s2b.want" "$_t/s2b.block" >/dev/null 2>&1; then
    pass "S2 [EXACT-TEXT] — the no-remote refusal is today's text, plus the one --publish-base line"
  else
    fail "S2 [EXACT-TEXT] — the no-remote refusal text changed:"; diff "$_t/s2b.want" "$_t/s2b.block" | head -8 >&2 || :
  fi

  # S9 — the local base exists, the remote lacks it: the report is unchanged and ends with the publish notice
  ku "$proj" "$KU" "$_t/s9" --from "$_t/src0"
  if [ "$KU_RC" -eq 0 ] && has "$_t/s9" "kit-base is not on 'origin' — a teammate's clone cannot run kit-update. Publish it: kit-update --publish-base"; then
    pass "S9 [NOTICE] — the remote lacks the base: --from prints the --publish-base notice and exits 0"
  else
    fail "S9 [NOTICE] — expected rc 0 + the publish notice; rc=$KU_RC: $(tail -n 4 "$_t/s9" | tr '\n' '|')"
  fi

  # P1 — --publish-base pushes the base ref + the chain's own tag; with no remote it says so, rc 1
  ku "$proj" "$KU" "$_t/p1" --publish-base
  if [ "$KU_RC" -eq 0 ] && [ "$(git -C "$org" rev-parse refs/kit/base 2>/dev/null)" = "$(git -C "$proj" rev-parse refs/heads/kit-base)" ] \
     && git -C "$org" rev-parse --verify --quiet "refs/tags/$_tag0" >/dev/null 2>&1 \
     && [ -z "$(git -C "$org" for-each-ref refs/heads/kit-base)" ]; then
    pass "P1 [PUBLISHED] — --publish-base: origin's refs/kit/base is the local tip, the chain's tag is there, and origin has NO refs/heads/kit-base"
  else
    fail "P1 [PUBLISHED] — origin does not carry the base (rc=$KU_RC): $(sed -n '1,6p' "$_t/p1" | tr '\n' '|')"
  fi
  cp -R "$proj" "$_t/p1.nr" && git -C "$_t/p1.nr" remote remove origin >/dev/null 2>&1 || :
  ku "$_t/p1.nr" "$KU" "$_t/p1b" --publish-base
  if [ "$KU_RC" -eq 1 ] && has "$_t/p1b" "no remote 'origin'"; then
    pass "P1 [NO-REMOTE] — --publish-base with no remote says so and exits 1"
  else
    fail "P1 [NO-REMOTE] — expected rc 1 naming the missing remote; rc=$KU_RC: $(sed -n '1,3p' "$_t/p1b" | tr '\n' '|')"
  fi

  # S1 — a FRESH CLONE imports the published base, and its report is the original clone's, byte for byte
  git clone -q --no-tags "$org" "$_t/b" >/dev/null 2>&1 || { fail "fixture: could not clone origin"; return 1; }
  # D1: main leads a report with the clone's pre-push HOOK STATE, which is a property of the clone (a `git clone` carries no
  # installed hook; the original has incept's). The leg's claim is "same delta", not "same hook state": install the SAME hook in
  # the fresh clone (the way an adopter does), so both reports carry the same hook line.
  if [ -f "$proj/.git/hooks/pre-push" ]; then
    cp "$proj/.git/hooks/pre-push" "$_t/b/.git/hooks/pre-push" && chmod +x "$_t/b/.git/hooks/pre-push" || fail "S1 fixture: could not install the hook in the fresh clone"
  fi
  ku "$_t/b" "$KU" "$_t/s1b" --from "$_t/src1"
  ku "$proj" "$KU" "$_t/s1a" --from "$_t/src1"
  _a_rc=$KU_RC
  for _s in s1a s1b; do
    sed -n '/^kit-update: v.*(--from)$/,$p' "$_t/$_s" | sed -e 's#/[^ ]*kit-update-v[^ ]*\.patch#<PATCH>#g' > "$_t/$_s.rep"
  done
  if [ "$_a_rc" -eq 0 ] && has "$_t/s1b" "imported 1 chain commit\(s\) from 'origin'" && [ -s "$_t/s1a.rep" ] && cmp -s "$_t/s1a.rep" "$_t/s1b.rep" \
     && [ "$(git -C "$_t/b" rev-parse refs/heads/kit-base)" = "$(git -C "$proj" rev-parse refs/heads/kit-base)" ] \
     && git -C "$_t/b" rev-parse --verify --quiet "refs/tags/$_tag0" >/dev/null 2>&1; then
    pass "S1 [FRESH-CLONE-IMPORTS] — the clone imported the published base (+ its tag) and its --from report equals the original clone's, byte for byte"
  else
    fail "S1 [FRESH-CLONE-IMPORTS] — the fresh clone did not import, or the reports differ (clone rc=$KU_RC): $(sed -n '1,8p' "$_t/s1b" | tr '\n' '|')"
    diff "$_t/s1a.rep" "$_t/s1b.rep" | head -6 >&2 || :
  fi

  # S3 — a teammate advances and publishes; the other clone pulls and runs --from: fast-forward, never STALE
  _p=$(sed -n 's/^patch: //p' "$_t/s1a" | sed -n '1p')
  if [ -z "$_p" ] || ! ( cd "$proj" && git apply "$_p" && git add -A && $GIT_C commit -qm 'take R1' ) >/dev/null 2>&1; then
    fail "S3 fixture: could not take R1 in the first clone"; return 1
  fi
  git -C "$org" fetch -q "$proj" "HEAD:refs/heads/$_br" >/dev/null 2>&1 && git -C "$proj" fetch -q origin >/dev/null 2>&1 \
    || { fail "S3 fixture: could not sync origin to the first clone's HEAD"; return 1; }
  ku "$proj" "$KU" "$_t/s3adv" --advance-base --from "$_t/src1"
  [ "$KU_RC" -eq 0 ] || { fail "S3 fixture: the first clone's --advance-base failed (rc=$KU_RC): $(sed -n '1,6p' "$_t/s3adv" | tr '\n' '|')"; return 1; }
  git -C "$_t/b" fetch -q origin >/dev/null 2>&1 && git -C "$_t/b" merge -q --ff-only "origin/$_br" >/dev/null 2>&1 \
    || { fail "S3 fixture: the second clone could not pull"; return 1; }
  _b_old=$(git -C "$_t/b" rev-parse refs/heads/kit-base) || { fail "S3 fixture: the second clone has no base to fast-forward (S1 did not import)"; return 1; }
  ku "$_t/b" "$KU" "$_t/s3" --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && has "$_t/s3" "imported 1 chain commit\(s\)" && ! has "$_t/s3" 'STALE BASE' \
     && [ "$(git -C "$_t/b" rev-parse refs/heads/kit-base)" = "$(git -C "$org" rev-parse refs/kit/base)" ] \
     && [ "$(git -C "$_t/b" rev-parse 'refs/heads/kit-base^')" = "$_b_old" ]; then
    pass "S3 [FAST-FORWARD] — after the teammate's advance the clone fast-forwards its base (parent = its old tip), is not refused as STALE, and equals the remote's"
  else
    fail "S3 [FAST-FORWARD] — the second clone did not fast-forward (rc=$KU_RC): $(brief "$_t/s3")"
  fi
  ku "$_t/b" "$KU" "$_t/s3b" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -eq 1 ] && has "$_t/s3b" 'nothing to advance' && [ "$(git -C "$_t/b" rev-parse refs/heads/kit-base)" = "$(git -C "$org" rev-parse refs/kit/base)" ]; then
    pass "S3 [NO-DIVERGENT-ADVANCE] — the second clone's own --advance-base finds the release already recorded (rc 1, nothing written, no rc 3 rejection)"
  else
    fail "S3 [NO-DIVERGENT-ADVANCE] — expected rc 1 'nothing to advance'; rc=$KU_RC: $(sed -n '1,4p' "$_t/s3b" | tr '\n' '|')"
  fi

  # S4 — diverged: this clone's tip and the remote's each have a commit the other lacks
  cp -R "$_t/b" "$_t/b4"
  _d_root=$(git -C "$_t/b4" rev-parse 'refs/heads/kit-base^'); _d_tree=$(git -C "$_t/b4" rev-parse 'refs/heads/kit-base^{tree}')
  _d_fork=$(git -C "$_t/b4" -c user.email=t@t -c user.name=t commit-tree "$_d_tree" -p "$_d_root" -m 'local fork (fixture)')
  git -C "$_t/b4" update-ref refs/heads/kit-base "$_d_fork"
  refs_of "$_t/b4" > "$_t/s4.r0"
  ku "$_t/b4" "$KU" "$_t/s4" --from "$_t/src1"
  refs_of "$_t/b4" > "$_t/s4.r1"
  # M1 (fail closed, the RUN does not): with a valid LOCAL base the divergence is a loud WARNING and the run continues on the
  # local base (here it then stops at its own stale-base gate: the fork carries no Kit-Source, rc 1 — what it did before)
  if [ "$KU_RC" -eq 1 ] && has "$_t/s4" 'DIVERGED' && has "$_t/s4" "$(sha12 "$_d_fork")" \
     && has "$_t/s4" "$(sha12 "$(git -C "$org" rev-parse refs/kit/base)")" && has "$_t/s4" 'WARNING — kit-base was NOT imported' \
     && has "$_t/s4" 'STALE BASE' && diff "$_t/s4.r0" "$_t/s4.r1" >/dev/null 2>&1; then
    pass "S4 [DIVERGED] — BOTH tips printed, a loud WARNING, no ref moved, and the run CONTINUED on the local base (its own stale gate spoke next)"
  else
    fail "S4 [DIVERGED] — expected DIVERGED + both tips + WARNING + continue + no write; rc=$KU_RC: $(brief "$_t/s4")"
  fi
  if ! has "$_t/s4" 'update-ref|:refs/heads/kit-base|branch kit-base|git fetch'; then
    pass "S4 [NO-RAW-IMPORT-LINE] — the diverged output prints no raw ref-writing import command (H1)"
  else
    fail "S4 [NO-RAW-IMPORT-LINE] — the diverged output prints a raw import command"
  fi

  # ── the forged-chain legs: a remote whose refs/kit/base the attacker controls ────────────────────────────
  orgx=$_t/orgx.git
  mk_remote "$proj" "$orgx" || return 1
  git clone -q --no-tags "$orgx" "$_t/g" >/dev/null 2>&1 || { fail "fixture: could not clone the forged-chain remote"; return 1; }
  _rc0=$(git -C "$proj" rev-parse 'refs/heads/kit-base^')        # the genuine R0 chain commit
  _t0tree=$(git -C "$proj" rev-parse "$_rc0^{tree}")
  _imode=$(git -C "$proj" ls-tree "$_rc0" scripts/incept.sh | cut -d' ' -f1)
  [ -n "$_imode" ] || { fail "fixture: the R0 base has no scripts/incept.sh"; return 1; }

  # S5 — the LOAD-BEARING NEGATIVE: a forged scripts/incept.sh in a chain commit with a GENUINE Kit-Source
  canary=$_t/canary
  printf '#!/bin/sh\necho pwned > "%s"\nexit 0\n' "$canary" > "$_t/forged-incept.sh"
  _fblob=$(git -C "$proj" hash-object -w "$_t/forged-incept.sh")
  # forged from the R1 base (the release HEAD of the clone records), so the M1 run reaches the forged incept
  _t1tree=$(git -C "$proj" rev-parse 'refs/heads/kit-base^{tree}')
  _ftree=$(tree_with "$proj" "$_t1tree" "$_imode" scripts/incept.sh "$_fblob") || { fail "S5 fixture: could not build the forged tree"; return 1; }
  chain_msg "$_t/forged.msg" "$R1"
  _fc=$(forge_root "$proj" "$_ftree" "$_t/forged.msg") || { fail "S5 fixture: could not commit the forged chain commit"; return 1; }
  push_base "$proj" "$orgx" "$_fc" || { fail "S5 fixture: could not publish the forged chain"; return 1; }
  refuses_with 'S5 forged-tree' "$_t/g" "$_t/s5" 'scripts/incept\.sh' --from "$_t/src1"
  if has "$_t/s5" "$(sha12 "$_fc")" && has "$_t/s5" 'Nothing was written'; then
    pass "S5 [NAMES-COMMIT] — the refusal names the forged chain commit and says nothing was written"
  else
    fail "S5 [NAMES-COMMIT] — the refusal does not name commit $(sha12 "$_fc") and 'Nothing was written'"
  fi
  if [ ! -e "$canary" ]; then
    pass "S5 [CANARY-ABSENT] — the forged incept never ran (no canary file)"
  else
    fail "S5 [CANARY-ABSENT] — the FORGED scripts/incept.sh RAN (the canary file exists)"
  fi

  # S6 — unverifiable: Kit-Source not in --from / no Kit-Source at all
  chain_msg "$_t/s6a.msg" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  _s6a=$(forge_root "$proj" "$_t0tree" "$_t/s6a.msg"); push_base "$proj" "$orgx" "$_s6a" || fail "S6 fixture: push a"
  refuses_with 'S6a kit-source-not-anchored' "$_t/g" "$_t/s6a" 'not a release this project took' --from "$_t/src0"
  chain_msg "$_t/s6c.msg" "$R1"   # a release YOUR history recorded, but --from (at R0) does not have it in its history
  _s6c=$(forge_root "$proj" "$_t0tree" "$_t/s6c.msg"); push_base "$proj" "$orgx" "$_s6c" || fail "S6 fixture: push c"
  refuses_with 'S6c kit-source-not-in-from' "$_t/g" "$_t/s6c" 'not in the history of --from' --from "$_t/src0"
  chain_msg "$_t/s6b.msg" -
  _s6b=$(forge_root "$proj" "$_t0tree" "$_t/s6b.msg"); push_base "$proj" "$orgx" "$_s6b" || fail "S6 fixture: push b"
  refuses_with 'S6b no-kit-source' "$_t/g" "$_t/s6b" 'no Kit-Source' --from "$_t/src0"
  if ! has "$_t/s6b" 'update-ref|:refs/heads/kit-base|branch kit-base|git fetch' && has "$_t/s6b" 're-publishes from a tree that records .kit-source'; then
    pass "S6 [NO-RAW-IMPORT-LINE] — the unverifiable-legacy refusal prints NO raw ref-writing import command (H1), only the publisher's remedy"
  else
    fail "S6 [NO-RAW-IMPORT-LINE] — the unrecorded refusal prints a raw import command, or lacks the publisher's remedy"
  fi

  # S7 — a symlink entry, and a submodule entry, in a chain tree
  _lblob=$(printf '%s' '/etc/passwd' | git -C "$proj" hash-object -w --stdin)
  _ltree=$(tree_with "$proj" "$_t0tree" 120000 docs/evil-link "$_lblob") || { fail "S7 fixture: symlink tree"; return 1; }
  chain_msg "$_t/s7.msg" "$R0"
  _s7a=$(forge_root "$proj" "$_ltree" "$_t/s7.msg"); push_base "$proj" "$orgx" "$_s7a" || fail "S7 fixture: push a"
  refuses_with 'S7a symlink-entry' "$_t/g" "$_t/s7a" 'symlink' --from "$_t/src0"
  _gtree=$(tree_with "$proj" "$_t0tree" 160000 docs/evil-sub 1111111111111111111111111111111111111111) || { fail "S7 fixture: submodule tree"; return 1; }
  _s7b=$(forge_root "$proj" "$_gtree" "$_t/s7.msg"); push_base "$proj" "$orgx" "$_s7b" || fail "S7 fixture: push b"
  refuses_with 'S7b submodule-entry' "$_t/g" "$_t/s7b" 'submodule' --from "$_t/src0"

  # S10 — ONE NEGATIVE PER ATTACK SHAPE (each a pushed chain the clone must refuse, naming why; none needs an incept)
  _rmode=$(git -C "$proj" ls-tree "$_rc0" DEVELOPMENT-STANDARDS.md | cut -d' ' -f1)
  _rblob=$(git -C "$proj" rev-parse "$_rc0:DEVELOPMENT-STANDARDS.md")
  _eblob=$(printf 'extra\n' | git -C "$proj" hash-object -w --stdin)
  chain_msg "$_t/s10.r0" "$R0"; chain_msg "$_t/s10.r1" "$R1"
  # (a) an extra file that no export carries
  _x=$(tree_with "$proj" "$_t0tree" 100644 docs/kbs-extra.md "$_eblob") && _xc=$(forge_root "$proj" "$_x" "$_t/s10.r0") && push_base "$proj" "$orgx" "$_xc" || fail "S10a fixture"
  refuses_with 'S10a extra-file-in-no-export' "$_t/g" "$_t/s10a" 'kbs-extra\.md' --from "$_t/src0"
  # (b) a mode flip, same blob and path
  _flip=100644; [ "$_imode" != 100644 ] || _flip=100755
  _x=$(tree_with "$proj" "$_t0tree" "$_flip" scripts/incept.sh "$(git -C "$proj" rev-parse "$_rc0:scripts/incept.sh")") && _xc=$(forge_root "$proj" "$_x" "$_t/s10.r0") && push_base "$proj" "$orgx" "$_xc" || fail "S10b fixture"
  refuses_with 'S10b mode-flip' "$_t/g" "$_t/s10b" 'scripts/incept\.sh' --from "$_t/src0"
  # (c) an entry from a DIFFERENT release's export (R0's standards doc inside a chain commit that claims R1)
  _x=$(tree_with "$proj" "$_t1tree" "$_rmode" DEVELOPMENT-STANDARDS.md "$_rblob") && _xc=$(forge_root "$proj" "$_x" "$_t/s10.r1") && push_base "$proj" "$orgx" "$_xc" || fail "S10c fixture"
  refuses_with 'S10c entry-from-another-release' "$_t/g" "$_t/s10c" 'DEVELOPMENT-STANDARDS\.md' --from "$_t/src1"
  # (d) a path with a control byte
  _x=$(tree_with "$proj" "$_t0tree" 100644 "docs/kbs-$(printf '\001')x" "$_eblob") && _xc=$(forge_root "$proj" "$_x" "$_t/s10.r0") && push_base "$proj" "$orgx" "$_xc" || fail "S10d fixture"
  refuses_with 'S10d control-byte-path' "$_t/g" "$_t/s10d" 'control character' --from "$_t/src0"
  # (e) a two-parent commit
  _xc=$(git -C "$proj" -c user.email=t@t -c user.name=t commit-tree "$_t0tree" -p "$_rc0" -p "$_fc" -F "$_t/s10.r0") && push_base "$proj" "$orgx" "$_xc" || fail "S10e fixture"
  refuses_with 'S10e two-parents' "$_t/g" "$_t/s10e" '2 parent' --from "$_t/src0"
  # (f) a chain that runs NEWEST to oldest (both commits genuine)
  _x0=$(forge_root "$proj" "$_t1tree" "$_t/s10.r1")
  _xc=$(git -C "$proj" -c user.email=t@t -c user.name=t commit-tree "$_t0tree" -p "$_x0" -F "$_t/s10.r0") && push_base "$proj" "$orgx" "$_xc" || fail "S10f fixture"
  refuses_with 'S10f non-monotonic' "$_t/g" "$_t/s10f" 'oldest to newest' --from "$_t/src1"
  # (g) a corrupt `behind` block, refused AT IMPORT (the tree is genuine R1)
  { printf 'kit-base: corrupt behind (fixture)\n\nbehind 1111111111111111111111111111111111111111 docs/x.md\n\n'
    printf 'Kit-Source: %s\nKit-Version: %s\nKit-Behind: 1\n' "$R1" "$VER"; } > "$_t/s10.g"
  _xc=$(git -C "$proj" -c user.email=t@t -c user.name=t commit-tree "$_t1tree" -p "$_rc0" -F "$_t/s10.g") && push_base "$proj" "$orgx" "$_xc" || fail "S10g fixture"
  refuses_with 'S10g corrupt-behind-record' "$_t/g" "$_t/s10g" 'corrupt' --from "$_t/src1"
  # (h) a dropped file: every entry is genuine, but the PATH SET is no export's (completeness)
  _ixf=$_t/s10.idx; rm -f "$_ixf"
  GIT_INDEX_FILE=$_ixf git -C "$proj" read-tree "$_t0tree" && GIT_INDEX_FILE=$_ixf git -C "$proj" update-index --force-remove DEVELOPMENT-STANDARDS.md \
    && _x=$(GIT_INDEX_FILE=$_ixf git -C "$proj" write-tree) && _xc=$(forge_root "$proj" "$_x" "$_t/s10.r0") && push_base "$proj" "$orgx" "$_xc" || fail "S10h fixture"
  refuses_with 'S10h dropped-file' "$_t/g" "$_t/s10h" 'path set' --from "$_t/src0"

  # S8 — tags: the chain's own arrive; a lookalike does not; an existing local tag is never moved
  orgt=$_t/orgt.git
  mk_remote "$proj" "$orgt" || return 1
  _tip=$(git -C "$proj" rev-parse refs/heads/kit-base)
  _tag1="kit-base/v$VER+$(sha12 "$R1")"
  git -C "$proj" rev-parse --verify --quiet "refs/tags/$_tag1" >/dev/null 2>&1 || { fail "S8 fixture: the advance made no tag $_tag1"; return 1; }
  git -C "$proj" push -q "$orgt" "$_tip:refs/kit/base" "refs/tags/$_tag0:refs/tags/$_tag0" "refs/tags/$_tag1:refs/tags/$_tag1" >/dev/null 2>&1 \
    || { fail "S8 fixture: could not publish the chain"; return 1; }
  git -C "$orgt" update-ref refs/tags/kit-base/x "$_tip"
  git -C "$orgt" update-ref refs/tags/kit-base/v0+aaaaaaaaaaaa "$_rc0"
  # K1: a tag whose VERSION part carries a quote, `;` and `$` but whose `+<sha12>` is the genuine one — the old shape test
  # (`v*+*`) accepted it, and its name would then be printed in the undo line
  _inj="kit-base/v$VER'x;"'$y'"+$(sha12 "$R0")"
  git -C "$orgt" update-ref "refs/tags/$_inj" "$_rc0"
  git -C "$orgt" -c user.email=t@t -c user.name=t tag -a -m 'annotated lookalike' kit-base/y "$_tip"
  git clone -q --no-tags "$orgt" "$_t/h" >/dev/null 2>&1 || { fail "S8 fixture: clone"; return 1; }
  _hhead=$(git -C "$_t/h" rev-parse HEAD)
  # the anchor (H2) needs R1 in H's .kit-source HISTORY while HEAD says R0 (-> the run stops at its stale gate right after
  # the import, cheap)
  # (H's history already records R1 — the clone is of the project after it took R1 — so one commit puts R0 back on top)
  _ks0=$(git -C "$proj" show "$_rc0:.kit-source")
  ( cd "$_t/h" && printf '%s\n' "$_ks0" > .kit-source && git add -A && $GIT_C commit -qm 'fixture: back to R0' ) >/dev/null 2>&1 \
    || { fail "S8 fixture: could not shape H's .kit-source history"; return 1; }
  _hhead=$(git -C "$_t/h" rev-parse HEAD)
  git -C "$_t/h" config --add remote.origin.fetch '+refs/kit/base:refs/heads/kit-mapped'   # K2: a configured refmap must not apply
  git -C "$_t/h" tag "$_tag1" "$_hhead"      # an EXISTING local tag of a name the remote also carries, pointing elsewhere
  # HEAD:.kit-source is R0 and the imported tip is R1, so the run refuses as STALE right after the import — cheap, and
  # the import has happened by then
  ku "$_t/h" "$KU" "$_t/s8" --from "$_t/src1"
  if [ "$(git -C "$_t/h" rev-parse refs/heads/kit-base)" = "$_tip" ] \
     && [ "$(git -C "$_t/h" rev-parse "refs/tags/$_tag0^{commit}" 2>/dev/null)" = "$_rc0" ] \
     && [ "$(git -C "$_t/h" rev-parse "refs/tags/$_tag1")" = "$_hhead" ] \
     && ! git -C "$_t/h" rev-parse --verify --quiet refs/tags/kit-base/x >/dev/null 2>&1 \
     && ! git -C "$_t/h" rev-parse --verify --quiet refs/tags/kit-base/y >/dev/null 2>&1 \
     && ! git -C "$_t/h" tag -l 'kit-base/*' | grep -qF "x;" && ! grep -qF "x;" "$_t/s8" \
     && ! git -C "$_t/h" rev-parse --verify --quiet refs/heads/kit-mapped >/dev/null 2>&1 \
     && [ -z "$(git -C "$_t/h" for-each-ref refs/kit-import/)" ] \
     && ! git -C "$_t/h" rev-parse --verify --quiet refs/tags/kit-base/v0+aaaaaaaaaaaa >/dev/null 2>&1; then
    pass "S8 [TAGS] — the chain's own tag was created, the lookalikes were not imported, and the existing local tag was not moved"
  else
    fail "S8 [TAGS] — tag import is wrong: $(git -C "$_t/h" tag -l 'kit-base/*' | tr '\n' ' ') (rc=$KU_RC; semicolon-in-output=$(grep -c ';' "$_t/s8" || :) mapped=$(git -C "$_t/h" for-each-ref refs/heads/kit-mapped refs/kit-import/ | wc -l | tr -d ' ') kitbase=$(git -C "$_t/h" rev-parse --verify --quiet refs/heads/kit-base | cut -c1-8) tip=$(printf '%s' "$_tip" | cut -c1-8))"
  fi

  # S11 — the import fails CLOSED, the RUN does not: a clone with a valid LOCAL base, a remote chain that extends it but
  # carries a forged incept -> a loud WARNING, nothing written, the run CONTINUES on the local base (rc 0, the canary absent)
  cp -R "$_t/b" "$_t/b5"
  _b5tip=$(git -C "$_t/b5" rev-parse refs/heads/kit-base)
  _fc2=$(git -C "$proj" -c user.email=t@t -c user.name=t commit-tree "$_ftree" -p "$_b5tip" -F "$_t/forged.msg") && push_base "$proj" "$orgx" "$_fc2" \
    && git -C "$_t/b5" remote set-url origin "$orgx" || fail "S11 fixture"
  ku "$_t/b5" "$KU" "$_t/s11" --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && has "$_t/s11" 'WARNING — kit-base was NOT imported' && has "$_t/s11" 'scripts/incept\.sh' \
     && [ "$(git -C "$_t/b5" rev-parse refs/heads/kit-base)" = "$_b5tip" ] && [ ! -e "$canary" ] && has "$_t/s11" '^kit-update: v.*\(--from\)$'; then
    pass "S11 [FAIL-CLOSED-RUN-CONTINUES] — a forged extension of a valid local base: loud WARNING, nothing written, the run went on against the local base (rc 0)"
  else
    fail "S11 [FAIL-CLOSED-RUN-CONTINUES] — expected rc 0 + WARNING + the report on the local base + no write; rc=$KU_RC: $(brief "$_t/s11")"
  fi

  # A1 — a local kit-base that CAME FROM A REMOTE BRANCH is refused as unverified, before anything is built (the forged
  # chain commit's incept would otherwise run): `git checkout kit-base` of origin/kit-base sets branch.kit-base.remote
  orgb=$_t/orgb.git
  mk_remote "$proj" "$orgb" || return 1
  git -C "$proj" branch kbs-tmp "$_fc" && git -C "$orgb" fetch -q "$proj" kbs-tmp:refs/heads/kit-base >/dev/null 2>&1; git -C "$proj" branch -D kbs-tmp >/dev/null 2>&1 || :
  git clone -q --no-tags "$orgb" "$_t/g2" >/dev/null 2>&1 && git -C "$_t/g2" checkout -q kit-base >/dev/null 2>&1 && git -C "$_t/g2" checkout -q "$_br" >/dev/null 2>&1 \
    || { fail "A1 fixture: could not make a clone whose kit-base came from a remote branch"; return 1; }
  ku "$_t/g2" "$KU" "$_t/a1" --from "$_t/src1"
  if [ "$KU_RC" -eq 1 ] && has "$_t/a1" 'UNVERIFIED' && has "$_t/a1" 'git branch -m kit-base kit-base-unverified' && [ ! -e "$canary" ] \
     && ! has "$_t/a1" 'update-ref|:refs/heads/kit-base|git fetch'; then
    pass "A1 [BASE-FROM-A-REMOTE-BRANCH] — a kit-base that came from a remote branch is refused as UNVERIFIED before any build (the canary is absent), with the verified route and no raw import line"
  else
    fail "A1 [BASE-FROM-A-REMOTE-BRANCH] — expected rc 1 + UNVERIFIED + the verified route + no canary; rc=$KU_RC: $(brief "$_t/a1")"
  fi

  # A2 — `git replace` must not substitute a chain commit's content: replace the tip with a forged-tree commit, run --from;
  # the genuine tip is built (canary absent). M3 (a COPY that no longer exports GIT_NO_REPLACE_OBJECTS) builds the FORGED one.
  cp -R "$_t/b" "$_t/b6" && cp -R "$_t/b" "$_t/b6m"
  _tip6=$(git -C "$_t/b6" rev-parse refs/heads/kit-base); _par6=$(git -C "$_t/b6" rev-parse 'refs/heads/kit-base^')
  for _r6 in b6 b6m; do
    _fb6=$(git -C "$_t/$_r6" hash-object -w "$_t/forged-incept.sh") \
      && _ft6=$(tree_with "$_t/$_r6" "$(git -C "$_t/$_r6" rev-parse "$_tip6^{tree}")" "$_imode" scripts/incept.sh "$_fb6") \
      && _fcB=$(git -C "$_t/$_r6" -c user.email=t@t -c user.name=t commit-tree "$_ft6" -p "$_par6" -F "$_t/forged.msg") \
      && git -C "$_t/$_r6" replace "$_tip6" "$_fcB" || fail "A2 fixture: could not git-replace the tip in $_r6"
  done
  ku "$_t/b6" "$KU" "$_t/a2" --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && [ ! -e "$canary" ]; then
    pass "A2 [REPLACE-IGNORED] — a refs/replace/ ref swapping the tip's tree is ignored: the genuine base is built, the forged incept never ran"
  else
    fail "A2 [REPLACE-IGNORED] — a git-replace'd chain commit was used (rc=$KU_RC, canary present=$([ -e "$canary" ] && echo yes || echo no))"
  fi
  if [ "$(grep -c '^GIT_NO_REPLACE_OBJECTS=1; export GIT_NO_REPLACE_OBJECTS$' "$KU" || :)" -ne 1 ]; then
    fail "M3 — scripts/kit-update.sh must carry exactly ONE greppable 'GIT_NO_REPLACE_OBJECTS=1; export GIT_NO_REPLACE_OBJECTS' line"
  else
    sed 's/^GIT_NO_REPLACE_OBJECTS=1; export GIT_NO_REPLACE_OBJECTS$/unset GIT_NO_REPLACE_OBJECTS/' "$KU" > "$_t/kit-update.mut3.sh"
    ku "$_t/b6m" "$_t/kit-update.mut3.sh" "$_t/a2m" --from "$_t/src1"
    if [ -e "$canary" ]; then
      pass "M3 [A2-NEEDS-THE-ENV] — without GIT_NO_REPLACE_OBJECTS the replaced (forged) tip IS built and its incept RUNS: A2 genuinely needs it"
    else
      fail "M3 [A2-VACUOUS] — without GIT_NO_REPLACE_OBJECTS the forged replacement still did not run: A2 does not need the env"
    fi
    rm -f "$canary"
  fi

  # M2 — the ANCHOR (H2): a chain claiming a GENUINE release this project's own history never recorded. `c` took only R0;
  # the remote's chain ends at R1 (genuine tree, genuine Kit-Source). Refused; with `_KU_ANCHOR=off` (a COPY) it imports.
  orgy=$_t/orgy.git
  mk_remote "$proj" "$orgy" || return 1
  push_base "$proj" "$orgy" "$_tip" || fail "M2 fixture: publish the genuine chain"
  git -C "$_t/c" remote add origin "$orgy" >/dev/null 2>&1 || fail "M2 fixture: wire c"
  refuses_with 'M2 anchor' "$_t/c" "$_t/m2" 'not a release this project took' --from "$_t/src1"
  if ! mutate_anchor "$KU" "$_t/kit-update.mut2.sh"; then
    fail "M2 — could not build the _KU_ANCHOR mutant: scripts/kit-update.sh must carry exactly ONE greppable '_KU_ANCHOR=on' line"
  else
    ku "$_t/c" "$_t/kit-update.mut2.sh" "$_t/m2b" --from "$_t/src1"
    if git -C "$_t/c" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1; then
      pass "M2 [ANCHOR-NEEDS-THE-CHECK] — with the anchor dropped, the genuine-but-never-taken chain IMPORTS: the anchor test genuinely needs it"
    else
      fail "M2 [ANCHOR-VACUOUS] — with the anchor dropped the chain is still refused: the anchor leg does not need the check"
    fi
  fi

  # M1 — NON-VACUITY: with the verification switched OFF (a COPY), the S5 forged chain IMPORTS and its incept RUNS
  if ! mutate_verify "$KU" "$_t/kit-update.mut.sh"; then
    fail "M1 — could not build the _KU_VERIFY_IMPORT mutant: scripts/kit-update.sh must carry exactly ONE greppable '_KU_VERIFY_IMPORT=on' line"
  else
    push_base "$proj" "$orgx" "$_fc" || fail "M1 fixture: re-publish the forged chain"
    ku "$_t/g" "$_t/kit-update.mut.sh" "$_t/m1" --from "$_t/src1"
    if git -C "$_t/g" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 && [ -e "$canary" ]; then
      pass "M1 [S5-NEEDS-THE-CONTROL] — with the verification off, the forged chain is IMPORTED and its incept RUNS: S5 genuinely needs verify_chain_commit"
    else
      fail "M1 [S5-VACUOUS] — with the verification off the forged chain is still refused (or its incept did not run): S5 does not need the control (rc=$KU_RC: $(brief "$_t/m1"))"
    fi
  fi

  _t1=$(date +%s)
  echo "runtime: $((_t1 - _t0)) s"
  if [ "$ST" -eq 0 ]; then
    echo "OK: kit-base-shared — a clone or teammate imports the published kit-base, every chain commit verified against --from"
    echo "    (Kit-Source resolves; every tree entry is an entry of the exports that release's own exporter makes; no"
    echo "    symlink or submodule) before one compare-and-swap writes it; a forged chain never runs and writes nothing."
    echo "    The verification is proven non-vacuous (M1). --publish-base is the explicit, never-forced publish."
    echo "HONEST CEILING: proves the import on a synthetic vendor of two commits and local bare remotes. Hosts other than"
    echo "                GitHub are unmeasured for refs/kit/*; the residuals (a genuine release your history recorded"
    echo "                that the chain still orders plausibly, a misleading message) are in docs/operations/kit-base.md."
  fi
  return "$ST"
}

case "${1:-}" in
  "") ( check ); exit $? ;;
  *) echo "usage: kit-base-shared.sh" >&2; exit 2 ;;
esac
