#!/bin/sh
# kit-update-advance.sh — THE kit-base CHAIN: `--advance-base`, the stale-base refusal, the pristine-chain
# classification, and the vendor-commit grouping of `kit-update --from` (KIT-UPDATE-BASE-ADVANCES).
#
# THE DEFECT THIS LOCKS: `kit-base` was written once, at inception, and never again. After an update
# merged, every file it applied differed from BASE on the adopter's side too, so it read as "changed BOTH"
# (CONFLICT) forever, and its NEWER upstream content was never offered again (measured on a real adopter:
# 71 CONFLICT, 1 offered). Now `kit-base` is a CHAIN of the releases the adopter took, `--advance-base`
# appends the one HEAD just took, and "kit-pristine" means "equal to ANY release in the chain".
#
# Fixture: a throwaway VENDOR git repo (a clone of this kit, so it is a real repo with history) with three
# commits R0 (the kit as it stands), R1 and R2 — each editing kit-own files incept does not rename. VERSION
# never changes: that is the point (two pre-release commits of one VERSION). Two real adopters are exported
# and incepted from R0, built the way kit-update-merge.sh builds its fixture: F1 (records `.kit-source`)
# and F2 (a LEGACY tree: no `.kit-source`, no trailer — the shape of an adopter that took updates before
# the chain existed).
#
#   leg  asserts
#   A1   positive: take R1, `--advance-base`, re-run against R2 -> offered = exactly R2's new paths; the R1
#        paths are `current`; none of R1's paths is a CONFLICT
#   A2   negative: an adopter-edited file that R2 also changes is a CONFLICT, never offered
#   A3   distinct: two updates of one VERSION carry different @sha labels and tags, in a two-commit chain
#   A4   stale refusal: HEAD's `.kit-source` ahead of the kit-base tip -> `--from` exits 1 and prints the
#        `--advance-base` command (and writes nothing)
#   A5   legacy migration (the coldtest shape): R1 taken without an advance, R2 partly taken; `--at R1` then
#        `--at R2` -> the R1-stranded file is OFFERED, nothing already taken is a CONFLICT; the pre-advance
#        run prints the STALE-BASE notice
#   A6   declined hunk: an R1 file the adopter declined is re-offered against R2 (declining is not permanent)
#   A7   non-mutation: `--advance-base` moves only refs/heads/kit-base plus ONE new tag; HEAD, index, config,
#        worktree and every other ref are byte-identical; the new commit's parent is the old tip
#   A8   refusals: unreachable sha, a sha already in the chain, a malformed sha, `--at` while HEAD has
#        `.kit-source`, no `--at` on a legacy tree, no kit-base: each exits 1, names the reason, writes nothing
#   A9   grouping: a vendor commit touching >1 reported path is flagged "land together", and the
#        incept-derived .github/workflows/ci.yml is attributed to profiles/<stack>/ci.yml by matching lines
#   A11  stranded grouping: on the migrated legacy adopter, a file pristine at an OLDER chain release is
#        walked from that release's Kit-Source and attributed to the vendor commit that changed it (the tip's
#        own range is empty); the header names both ranges; generated records get their own line
#   A12  pin note: a path decided by an OLDER chain release carries "(pristine at <sha12> ...)"; a file you
#        deleted that an older release did not have is marked "(re-add"
#   A13  chain walk stops early: a fixture whose only undecided paths are adopter-owned rebuilds 0 older bases
#   A14  more refusals: a tag that exists, a tag name git refuses (nothing moved: the one-transaction proof), a
#        dangling object that is not in --from's history, an out-of-order --at, a base AHEAD of HEAD, an
#        ambient GIT_INDEX_FILE
#   A10  non-vacuity: the pristine-chain walk of a COPY of kit-update.sh is mutated to tip-only (the one
#        greppable line `_KU_CHAIN_WALK=all` -> `tip`); the A5 and A6 assertions must then FAIL on it. A
#        walk that never reaches an older release fails here, so A5/A6 cannot be green by accident. The
#        same family: `_KU_BEHIND=on` -> `off` (the advance records 0 behind, as before KIT-UPDATE-PARTIAL-
#        ADOPTION) must FAIL A15 and A17.
#
# KIT-UPDATE-PARTIAL-ADOPTION (the advance records what HEAD actually TOOK, per path; the base is published):
#   A15  PARTIAL-TAKE: R1 changes several kit files; the adopter keeps one (a conflicting edit, or just leaves it).
#        The advance writes `Kit-Behind: 1` + exactly one `behind <chain commit> <path>` line and NO tag; the next
#        `--from` at the same release lists that path in CONFLICT (or offers it alone) and nothing else
#   A16  FULL-TAKE (negative control): all taken -> `Kit-Behind: 0`, the tag, a clean next run
#   A17  FINISH: after A15, take the remainder -> a re-advance at R1 writes a child commit, `Kit-Behind: 0`, the
#        tag; a second one is refused (complete / nothing new taken / release in the chain but not at the tip)
#   A18  MERGED-COUNTS-AS-TAKEN: a hand-merged text file (merge-file no-op) is taken; a binary is taken only on
#        byte equality
#   A19  UNDO-STALE: the documented undo, then the STALE refusal names the advance (run by the agent) as the cure,
#        and the cure writes the partial record
#   A20  PUBLISH: a local bare `origin`: the advance pushes kit-base + the tag; `--no-push` keeps it local; a
#        diverged origin is rc 3 (local write stands, nothing forced); HEAD off origin/HEAD refuses before a write
#
#   sh conformance/kit-update-advance.sh
# Exit: 0 = pass · 1 = regression · 2 = usage/UNVERIFIED. POSIX sh; dash-clean.
# What it changes: nothing in the repo — builds a vendor repo, two adopters and a mutated copy of
#                  kit-update.sh in a temp dir, removed on exit. (`--advance-base`, the tool's only writer,
#                  writes only the throwaway adopters here: refs/heads/kit-base, one tag per advance, and the
#                  objects behind that commit.)
# Guardrails: read-only wrt the kit; temp-only writes; teardown non-fatal. The refusals and the stale-base
#             stop are fingerprinted (HEAD, every ref, index, config, worktree, object count) before and after.
# Runtime: ~6-8 minutes (each `--from` run re-runs a real export+incept for THEIRS and BASE, ~9 s each; the
#          pristine-chain walk adds one more per older chain commit). Fixtures are reused across the legs.
#
# NOT REGISTERED IN conformance/verify.sh — same reason as conformance/kit-update-merge.sh: it runs `incept`
# in a fresh export, but an ADOPTER's tree already carries ENGINEERING-PRINCIPLES.md, so incept refuses and
# the check would FAIL for every adopter, and that battery is PORTABLE. It is a kit-CI step beside
# kit-update-merge.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

# shellcheck disable=SC2329  # invoked INDIRECTLY, from the EXIT/INT/TERM trap in check()
_cleanup() { rm -rf "$1" 2>/dev/null || true; }

STACK=typescript-node
ADOPT_DATE=2020-01-02
GIT_C="git -c user.email=t@t -c user.name=t"
KU="$ROOT/scripts/kit-update.sh"
VER=$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)

# The kit-own files the fake releases edit. All ship in the export; none is renamed by incept.
UP_A=DEVELOPMENT-STANDARDS.md        # R1 AND R2 (taken at R1, then STRANDED when R2 changes it)
UP_D=docs/adoption/brownfield.md     # R1 only   (declined in F1 -> must be re-offered)
UP_CI=profiles/$STACK/ci.yml         # R1 only   (the RAW path of the CI workflow)
UP_CIOUT=.github/workflows/ci.yml    # R1 only   (incept-DERIVED from UP_CI: not byte-equal to it)
UP_X=docs/operations/doctor.md       # R2 only
UP_P=DEVELOPMENT-PROCESS.md          # R2; the adopter edits it in F1 (-> CONFLICT)
UP_NEW=docs/adoption/kuba-fixture-readd.md   # ADDED by R1 (taken, then deleted by the adopter -> a re-add)

ST=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; ST=1; }

# ── report parsing: the named sections, read out of the tool's own output ──────────────────────────────
section() {  # <report-file> <section-key>
  sed -n "/^== $2 /,/^\$/p" "$1" | sed -n 's/^  - //p'
}
in_section() { section "$1" "$2" | grep -qxF "$3"; }
header_line() { sed -n 's/^kit-update: \(v.*(--from)\)$/\1/p' "$1" | sed -n '1p'; }
sha12() { printf '%s' "$1" | cut -c1-12; }

# ── fixtures ───────────────────────────────────────────────────────────────────────────────────────────
# build_vendor <dir> — R0 = this kit's HEAD; R1, R2 = real commits on top. Sets R0 R1 R2 (40-hex).
build_vendor() {
  git clone --quiet --no-tags "$ROOT" "$1" >/dev/null 2>&1 || { fail "could not clone the kit into a vendor repo"; return 1; }
  R0=$(git -C "$1" rev-parse HEAD)
  printf '\n## R1 upstream change (fixture)\n' >> "$1/$UP_A"
  printf '\n<!-- R1 upstream change (fixture) -->\n' >> "$1/$UP_D"
  printf '\n# R1 kuba fixture line\n' >> "$1/profiles/$STACK/ci.yml"
  printf '# kuba fixture: a file R1 adds\n' > "$1/$UP_NEW"
  ( cd "$1" && git add -A && $GIT_C commit -qm 'R1: standards + brownfield + the profile CI (fixture)' ) >/dev/null 2>&1 \
    || { fail "could not commit R1"; return 1; }
  R1=$(git -C "$1" rev-parse HEAD)
  printf '\n## R2 upstream change (fixture)\n' >> "$1/$UP_A"
  printf '\n## R2 upstream change (fixture)\n' >> "$1/$UP_P"
  printf '\n<!-- R2 upstream change (fixture) -->\n' >> "$1/$UP_X"
  ( cd "$1" && git add -A && $GIT_C commit -qm 'R2: standards + process + doctor (fixture)' ) >/dev/null 2>&1 \
    || { fail "could not commit R2"; return 1; }
  R2=$(git -C "$1" rev-parse HEAD)
}

# checkout_at <vendor> <sha> <dir> — a clone of the vendor with HEAD detached at <sha>: a "release" to --from.
checkout_at() {
  if git clone --quiet --no-tags "$1" "$3" >/dev/null 2>&1 && git -C "$3" checkout -q --detach "$2" >/dev/null 2>&1; then
    return 0
  fi
  fail "could not check out $2 of the vendor"; return 1
}

# build_adopter <dir> <src-at-R0> <legacy:0|1> — a REAL adopter: exported, committed, incepted, committed.
# legacy=1 strips `.kit-source` from the export (and its manifest/digest lines) BEFORE inception, so the
# kit-base it records is the pre-chain shape: no Kit-Source trailer, tag kit-base/v<VER>.
build_adopter() {
  sh "$2/scripts/adopter-export.sh" "$1" --profile "$STACK" >/dev/null 2>&1 \
    || { fail "adopter-export failed; cannot build a fixture adopter"; return 1; }
  if [ "$3" = 1 ]; then
    rm -f "$1/.kit-source"
    sed '/^\.kit-source$/d' "$1/.kit-manifest" > "$1/.kit-manifest.new" && mv "$1/.kit-manifest.new" "$1/.kit-manifest"
    sed '/ \.kit-source$/d' "$1/.kit-digests" > "$1/.kit-digests.new" && mv "$1/.kit-digests.new" "$1/.kit-digests"
  fi
  ( cd "$1" && git init -q . && git add -A && $GIT_C commit -qm 'kit export' ) >/dev/null 2>&1 \
    || { fail "could not init the fixture repo"; return 1; }
  ( cd "$1" && sh scripts/incept.sh --noninteractive --name Flow --intent-owner B \
      --stack "$STACK" --date "$ADOPT_DATE" ) >/dev/null 2>&1 \
    || { fail "incept failed on the fixture"; return 1; }
  ( cd "$1" && git add -A && $GIT_C commit -qm 'inception' ) >/dev/null 2>&1 \
    || { fail "could not commit the incepted fixture"; return 1; }
  git -C "$1" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 \
    || { fail "incept did not record refs/heads/kit-base"; return 1; }
}

# ku <adopter> <script> <out> <args…> — run a kit-update script against an adopter; rc to $KU_RC, output to <out>.
KU_RC=0
ku() {
  _ku_a=$1; _ku_s=$2; _ku_o=$3; shift 3
  KU_RC=0
  ( cd "$_ku_a" && sh "$_ku_s" --repo "$_ku_a" "$@" ) >"$_ku_o" 2>&1 || KU_RC=$?
}

# take <adopter> <report> <label> [git-apply-args…] — apply the report's patch (minus the given excludes) and commit.
take() {
  _tk_a=$1; _tk_r=$2; _tk_l=$3; shift 3
  _tk_p=$(sed -n 's/^patch: //p' "$_tk_r" | sed -n '1p')
  [ -n "$_tk_p" ] && [ -f "$_tk_p" ] || { fail "$_tk_l: the report names no patch file to take"; return 1; }
  ( cd "$_tk_a" && git apply "$@" "$_tk_p" && git add -A && $GIT_C commit -qm "$_tk_l" ) >/dev/null 2>&1 \
    || { fail "$_tk_l: could not apply + commit the patch"; return 1; }
}

# fingerprint <repo> <all|other> — what a refusal / the advance is forbidden to touch.
# `all`   = every ref + object count (a refusal writes NOTHING). `other` = everything EXCEPT kit-base refs
# and objects (the advance may write exactly those).
fingerprint() {
  echo "HEAD $(git -C "$1" rev-parse HEAD 2>/dev/null || echo unborn)"
  if [ "$2" = all ]; then
    git -C "$1" show-ref | LC_ALL=C sort
    echo "objects $(find "$1/.git/objects" -type f | grep -c . || :)"
  else
    git -C "$1" show-ref | grep -v ' refs/heads/kit-base$' | grep -v ' refs/tags/kit-base/' | LC_ALL=C sort
  fi
  echo "-- status --"; git -C "$1" status --porcelain=v1 | LC_ALL=C sort
  echo "-- index+config cksum --"; cksum "$1/.git/index" "$1/.git/config" 2>/dev/null || :
  echo "-- worktree cksum --"
  ( cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs cksum 2>/dev/null )
  echo "-- ref files --"
  ( cd "$1" && find .git/refs .git/packed-refs -type f -print 2>/dev/null | grep -v 'refs/heads/kit-base$' \
      | grep -v 'refs/tags/kit-base/' | LC_ALL=C sort | xargs cksum 2>/dev/null )
}

# refuses <leg> <adopter> <reason-ERE> <out> <script-args…> — the run must exit 1, name the reason, write NOTHING.
refuses() {
  _rf_leg=$1; _rf_a=$2; _rf_re=$3; _rf_o=$4; shift 4
  fingerprint "$_rf_a" all > "$_rf_o.fp0"
  ku "$_rf_a" "$KU" "$_rf_o" "$@"
  fingerprint "$_rf_a" all > "$_rf_o.fp1"
  if [ "$KU_RC" -eq 1 ] && grep -Eqi -- "$_rf_re" "$_rf_o"; then
    pass "$_rf_leg — exit 1, names the reason ('$_rf_re')"
  else
    fail "$_rf_leg — expected exit 1 naming '$_rf_re'; got rc=$KU_RC: $(sed -n '1,4p' "$_rf_o" | tr '\n' '|')"
  fi
  if diff -u "$_rf_o.fp0" "$_rf_o.fp1" >/dev/null 2>&1; then
    pass "$_rf_leg [writes nothing] — HEAD, every ref, index, config, worktree and the object count are unchanged"
  else
    fail "$_rf_leg [writes nothing] — the refused run changed the adopter's repo"
    diff -u "$_rf_o.fp0" "$_rf_o.fp1" | grep -E '^[+-][^+-]' | head -8 >&2 || :
  fi
}

# ── the assertions A5 / A6 are ALSO run against the mutant (A10), so they are functions of a report ─────
# a5_holds <report>: the R1-stranded file is offered; the never-taken R2 file is offered; nothing the
# adopter already took is a CONFLICT; the taken R1 files are `current`.
a5_holds() {
  in_section "$1" offered "$UP_A" && in_section "$1" offered "$UP_X" \
    && in_section "$1" current "$UP_P" && in_section "$1" current "$UP_D" && in_section "$1" current "$UP_CIOUT" \
    && ! in_section "$1" CONFLICT "$UP_A" && ! in_section "$1" CONFLICT "$UP_P" \
    && ! in_section "$1" CONFLICT "$UP_D" && ! in_section "$1" CONFLICT "$UP_CIOUT"
}
# a6_holds <report>: the declined R1 file is offered again, and is not a CONFLICT.
a6_holds() {
  in_section "$1" offered "$UP_D" && ! in_section "$1" CONFLICT "$UP_D"
}

# a9_check <report> — the grouping section: "land together" + attribution of the incept-derived CI workflow.
a9_check() {
  _g=$(sed -n '/^== grouped by vendor change/,/^$/p' "$1")
  _blk=$(printf '%s\n' "$_g" | awk '/^  \* [0-9a-f]+ R1: /{p=1;next} /^  \* /{p=0} /^  not attributable/{p=0} p')
  if [ -z "$_blk" ]; then
    fail "A9 grouping — no commit block for R1 in the grouping section"
    printf '%s\n' "$_g" | head -12 >&2 || :
    return 0
  fi
  if printf '%s\n' "$_blk" | grep -q 'land together'; then
    pass "A9 [LAND-TOGETHER] — the R1 vendor commit changed several reported paths and is flagged"
  else
    fail "A9 [LAND-TOGETHER] — R1 changed $UP_A, $UP_D and $UP_CI but is not flagged 'land together'"
  fi
  if printf '%s\n' "$_blk" | grep -qF -- "- $UP_CI (direct)"; then
    pass "A9 [DIRECT] — the raw-export path $UP_CI maps to itself"
  else
    fail "A9 [DIRECT] — $UP_CI is not listed as a direct path under R1"
  fi
  if printf '%s\n' "$_blk" | grep -qF -- "- $UP_CIOUT (attributed by matching lines"; then
    pass "A9 [ATTRIBUTED] — the incept-derived $UP_CIOUT is attributed to R1 by matching lines, labelled as inference"
  else
    fail "A9 [ATTRIBUTED] — $UP_CIOUT (incept-derived) was not attributed to the R1 commit by matching lines"
  fi
}

# a11_check <report> <R1> <R2> — the migrated legacy adopter: tip = R2's chain commit, UP_A is pristine at the
# OLDER R1 chain commit and R2 (the tip's own range R2..R2 is empty) is what changed it. The grouping must
# walk UP_A from R1 (its deciding commit's Kit-Source), say so in the header, attribute it to the R2 commit,
# and list the generated records on their own line instead of "not attributable".
a11_check() {
  _g=$(sed -n '/^== grouped by vendor change/,/^$/p' "$1")
  _blk=$(printf '%s\n' "$_g" | awk '/^  \* [0-9a-f]+ R2: /{p=1;next} /^  \* /{p=0} /^  [^ ]/{p=0} p')
  if printf '%s\n' "$_blk" | grep -qF -- "- $UP_A (direct)"; then
    pass "A11 [STRANDED-ATTRIBUTED] — $UP_A, pristine at the older R1 release, is attributed to the R2 vendor commit that changed it"
  else
    fail "A11 [STRANDED-ATTRIBUTED] — the stranded $UP_A is not attributed to R2:"
    printf '%s\n' "$_g" | head -14 >&2 || :
  fi
  if printf '%s\n' "$_g" | sed -n '1p' | grep -qF -- "$(sha12 "$2").. for" \
     && printf '%s\n' "$_g" | sed -n '1p' | grep -q 'pristine at an older release'; then
    pass "A11 [RANGES-SAID] — the section header names the older range walked"
  else
    fail "A11 [RANGES-SAID] — the header does not name the older range: $(printf '%s\n' "$_g" | sed -n '1p')"
  fi
  if printf '%s\n' "$_g" | grep -q '^  generated by the export (no commit changes them directly)' \
     && ! printf '%s\n' "$_g" | sed -n '/not attributable/,$p' | grep -q -e '\.kit-source' -e '\.kit-digests' -e '\.kit-manifest'; then
    pass "A11 [GENERATED-LINE] — the generated records have their own line and are not 'not attributable'"
  else
    fail "A11 [GENERATED-LINE] — generated records are missing their own line (or still listed as not attributable)"
  fi
}

# mutate_chain_walk <src> <dst> — the A10 mutant: tip-only pristine-chain walk. Honest: exactly ONE line is
# changed, and the change is verified (the line is present once in the original, absent in the copy).
mutate_chain_walk() {
  [ "$(grep -c '^_KU_CHAIN_WALK=all' "$1" || :)" -eq 1 ] || return 1
  sed 's/^_KU_CHAIN_WALK=all/_KU_CHAIN_WALK=tip/' "$1" > "$2" || return 1
  [ "$(grep -c '^_KU_CHAIN_WALK=tip' "$2" || :)" -eq 1 ] && ! grep -q '^_KU_CHAIN_WALK=all' "$2"
}

# mutate_behind <src> <dst> — the A15/A17 mutant (KIT-UPDATE-PARTIAL-ADOPTION): the advance records 0 behind, as it
# did before per-path provenance (the greppable line `_KU_BEHIND=on` -> `off`). Exactly ONE line changes, verified.
mutate_behind() {
  [ "$(grep -c '^_KU_BEHIND=on' "$1" || :)" -eq 1 ] || return 1
  sed 's/^_KU_BEHIND=on/_KU_BEHIND=off/' "$1" > "$2" || return 1
  [ "$(grep -c '^_KU_BEHIND=off' "$2" || :)" -eq 1 ] && ! grep -q '^_KU_BEHIND=on' "$2"
}

# mutate_strict <src> <dst> — the A21 mutant (`_KU_BEHIND_STRICT=on` -> `off`): the behind parser stops checking that a
# named commit is on the chain. Exactly ONE line changes, verified.
mutate_strict() {
  [ "$(grep -c '^_KU_BEHIND_STRICT=on' "$1" || :)" -eq 1 ] || return 1
  sed 's/^_KU_BEHIND_STRICT=on/_KU_BEHIND_STRICT=off/' "$1" > "$2" || return 1
  [ "$(grep -c '^_KU_BEHIND_STRICT=off' "$2" || :)" -eq 1 ] && ! grep -q '^_KU_BEHIND_STRICT=on' "$2"
}

# forge_tip <adopter> <behind block, '' for none> <Kit-Behind value> — rewrite the kit-base TIP commit (same tree, same
# parent, same Kit-Source/Kit-Version) with a forged record, and point kit-base at it. Only the fixture does this.
forge_tip() {
  _fg_tree=${4:-$(git -C "$1" rev-parse 'kit-base^{tree}')}   # an optional 4th argument: a forged TREE
  _fg_par=$(git -C "$1" rev-parse 'kit-base^')
  _fg_src=$(tip_trailer "$1" Kit-Source); _fg_ver=$(tip_trailer "$1" Kit-Version)
  { printf 'kit-base: forged (fixture)\n\n'
    [ -z "$2" ] || printf '%s\n\n' "$2"
    printf 'Kit-Source: %s\nKit-Version: %s\nKit-Behind: %s\n' "$_fg_src" "$_fg_ver" "$3"
  } > "$_t/forge.msg"
  _fg_new=$(git -C "$1" -c user.email=t@t -c user.name=t commit-tree "$_fg_tree" -p "$_fg_par" -F "$_t/forge.msg") || return 1
  git -C "$1" update-ref refs/heads/kit-base "$_fg_new"
}

# ── the per-path provenance record, read back out of the adopter's kit-base tip ────────────────────────────
tip_trailer() {  # <adopter> <Key> -> the tip's trailer value ('' when absent)
  git -C "$1" log -1 --format="%(trailers:key=$2,valueonly)" refs/heads/kit-base | sed -n '1p' | tr -d '[:space:]'
}
behind_lines() {  # <adopter> -> "<chain commit> <path>" per behind line of the tip's message, sorted
  git -C "$1" log -1 --format=%B refs/heads/kit-base | sed -n 's/^behind //p' | LC_ALL=C sort
}
tag_count() { git -C "$1" tag -l 'kit-base/*' | grep -c . || :; }
count_of() { sed -n "s/^== $2 (\([0-9]*\)) .*/\1/p" "$1" | sed -n '1p'; }   # <report> <section> -> the section's header count

# flow_partial <script> <adopter: adopted at R0, nothing taken> <out-prefix> — the A15 (pristine half) and A17 flow, run
# QUIETLY so the same flow can also run against the A10-family mutant. Take R1 except $UP_D -> advance -> `--from` again
# (A15), then take the remainder -> re-advance at R1 -> a second re-advance is refused (A17). Sets FP_15 / FP_17 (1 =
# the leg's claim held) and FP_WHY (why it did not).
FP_15=0; FP_17=0; FP_NOTE=0; FP_WHY=''
flow_partial() {
  _fs=$1; _fa=$2; _fo=$3; FP_15=0; FP_17=0; FP_NOTE=0; FP_WHY=''
  # the first report is b0's own (`$_t/r1.b0`, run once): every adopter here is an untouched copy of b0, so its patch
  # (OURS -> R1 on every offered path) is the same for all of them — no need to pay for the same two incepts again
  _fpatch=$(sed -n 's/^patch: //p' "$_t/r1.b0" | sed -n '1p')
  if ! ( cd "$_fa" && git apply --exclude="$UP_D" "$_fpatch" && git add -A && $GIT_C commit -qm 'take R1 except the brownfield doc' ) >/dev/null 2>&1; then
    FP_WHY='could not take R1 minus the brownfield doc'; return 0
  fi
  _fold=$(git -C "$_fa" rev-parse refs/heads/kit-base)
  ku "$_fa" "$_fs" "$_fo.adv" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -ne 0 ]; then FP_WHY="the advance failed (rc=$KU_RC): $(sed -n '1,3p' "$_fo.adv" | tr '\n' '|')"; return 0; fi
  if [ "$(tip_trailer "$_fa" Kit-Behind)" = 1 ] && [ "$(behind_lines "$_fa")" = "$_fold $UP_D" ] && [ "$(tag_count "$_fa")" -eq 1 ]; then
    ku "$_fa" "$_fs" "$_fo.r2" --from "$_t/src1"
    if [ "$KU_RC" -eq 0 ] && [ "$(section "$_fo.r2" offered)" = "$UP_D" ] && [ "$(count_of "$_fo.r2" CONFLICT)" = 0 ] \
       && grep -q 'PARTIAL — 1 file(s) behind' "$_fo.r2"; then
      FP_15=1
    else
      FP_WHY="the next --from (same R1) does not offer exactly $UP_D with 0 CONFLICT and a PARTIAL line"
    fi
  else
    FP_WHY="the advance did not record Kit-Behind: 1 with exactly 'behind <old tip> $UP_D' and no tag (Kit-Behind='$(tip_trailer "$_fa" Kit-Behind)', tags=$(tag_count "$_fa"))"
  fi
  # A17 — take the remainder the run offered, then re-advance at the SAME release
  _fpatch=$(sed -n 's/^patch: //p' "$_fo.r2" 2>/dev/null | sed -n '1p')
  if [ -n "$_fpatch" ] && [ -f "$_fpatch" ]; then
    ( cd "$_fa" && git apply "$_fpatch" && git add -A && $GIT_C commit -qm 'take the remainder of R1' ) >/dev/null 2>&1 || :
    # the record is now out of date by the paths just taken: --from says so (R-2), before the re-advance records them
    ku "$_fa" "$_fs" "$_fo.r3" --from "$_t/src1"
    if grep -q '^NOTE: 1 behind path(s) already equal the tip' "$_fo.r3"; then FP_NOTE=1; fi
  fi
  _fold2=$(git -C "$_fa" rev-parse refs/heads/kit-base)
  ku "$_fa" "$_fs" "$_fo.fin" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && [ "$(tip_trailer "$_fa" Kit-Behind)" = 0 ] && [ -z "$(behind_lines "$_fa")" ] \
     && [ "$(git -C "$_fa" rev-parse 'kit-base^')" = "$_fold2" ] \
     && git -C "$_fa" rev-parse --verify --quiet "refs/tags/kit-base/v$VER+$(sha12 "$R1")" >/dev/null 2>&1; then
    fingerprint "$_fa" all > "$_fo.fp0"
    ku "$_fa" "$_fs" "$_fo.again" --advance-base --from "$_t/src1"
    fingerprint "$_fa" all > "$_fo.fp1"
    if [ "$KU_RC" -eq 1 ] && diff -u "$_fo.fp0" "$_fo.fp1" >/dev/null 2>&1; then FP_17=1
    else FP_WHY="${FP_WHY:+$FP_WHY; }a second re-advance on the complete tip was not refused rc 1 writing nothing (rc=$KU_RC)"; fi
  else
    FP_WHY="${FP_WHY:+$FP_WHY; }the re-advance at R1 did not write a child commit with Kit-Behind: 0 and the R1 tag (rc=$KU_RC, Kit-Behind='$(tip_trailer "$_fa" Kit-Behind)')"
  fi
}

# ══ THE CHECK ═══════════════════════════════════════════════════════════════════════════════════════════
check() {
  _t=$(mktemp -d) || { echo "kit-update-advance: cannot mktemp" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "_cleanup '$_t'" EXIT INT TERM
  _t0=$(date +%s)

  build_vendor "$_t/vendor" || return 1
  checkout_at "$_t/vendor" "$R0" "$_t/src0" || return 1
  checkout_at "$_t/vendor" "$R1" "$_t/src1" || return 1
  # fixture self-check (non-vacuity of the fixture): the three shas differ and the edited files really ship.
  [ "$R0" != "$R1" ] && [ "$R1" != "$R2" ] || { fail "fixture: the vendor commits are not distinct"; return 1; }
  for _f in "$UP_A" "$UP_D" "$UP_CI" "$UP_X" "$UP_P"; do
    git -C "$_t/src0" cat-file -e "$R0:$_f" 2>/dev/null || { fail "fixture: $_f is not in the kit"; return 1; }
  done

  # ───────────────────────────── F1: an adopter that RECORDS `.kit-source` (A1 A2 A3 A4 A6 A7 A8 A9) ─────
  a1=$_t/a1
  build_adopter "$a1" "$_t/src0" 0 || return 1
  printf '\n<!-- adopter local note -->\n' >> "$a1/$UP_P"
  ( cd "$a1" && git add -A && $GIT_C commit -qm 'adopter edits the process doc' ) >/dev/null 2>&1 || { fail "F1: adopter edit"; return 1; }
  [ "$(git -C "$a1" show HEAD:.kit-source)" = "$(printf 'commit %s\nversion %s' "$R0" "$VER")" ] \
    || { fail "fixture: F1's HEAD does not record .kit-source = R0"; return 1; }

  # U1: R0 -> R1.
  ku "$a1" "$KU" "$_t/rep1" --from "$_t/src1"
  if [ "$KU_RC" -ne 0 ]; then fail "U1 — '--from <R1>' failed (rc=$KU_RC): $(sed -n '1,5p' "$_t/rep1" | tr '\n' '|')"; return 1; fi
  a9_check "$_t/rep1"
  _h1=$(header_line "$_t/rep1")
  # take R1 EXCEPT the brownfield doc (A6: a declined hunk)
  take "$a1" "$_t/rep1" 'take R1 (declined brownfield)' --exclude="$UP_D" || return 1

  # A4 — HEAD's .kit-source (R1) is ahead of the kit-base tip (R0): --from must refuse and name the command.
  fingerprint "$a1" all > "$_t/a4.fp0"
  ku "$a1" "$KU" "$_t/a4" --from "$_t/vendor"
  fingerprint "$a1" all > "$_t/a4.fp1"
  if [ "$KU_RC" -eq 1 ] && grep -q -- "--advance-base --from" "$_t/a4" && grep -qi 'stale' "$_t/a4"; then
    pass "A4 [STALE-REFUSAL] — HEAD records R1, kit-base tip is R0: --from exits 1, says STALE and prints the --advance-base command"
  else
    fail "A4 [STALE-REFUSAL] — expected exit 1 + 'stale' + the '--advance-base --from' command; rc=$KU_RC: $(sed -n '1,4p' "$_t/a4" | tr '\n' '|')"
  fi
  if diff -u "$_t/a4.fp0" "$_t/a4.fp1" >/dev/null 2>&1; then
    pass "A4 [writes nothing] — the stale-base refusal changed nothing"
  else
    fail "A4 [writes nothing] — the stale-base refusal changed the adopter's repo"
  fi

  # A7 — the advance: exactly kit-base + one tag move; everything else byte-identical.
  git -C "$a1" show-ref | LC_ALL=C sort > "$_t/a7.refs0"
  fingerprint "$a1" other > "$_t/a7.fp0"
  OLD_TIP=$(git -C "$a1" rev-parse refs/heads/kit-base)
  ku "$a1" "$KU" "$_t/adv1" --advance-base --from "$_t/vendor"
  fingerprint "$a1" other > "$_t/a7.fp1"
  git -C "$a1" show-ref | LC_ALL=C sort > "$_t/a7.refs1"
  if [ "$KU_RC" -ne 0 ]; then
    fail "A7 — '--advance-base --from <vendor>' failed (rc=$KU_RC): $(sed -n '1,6p' "$_t/adv1" | tr '\n' '|')"
  else
    NEW_TIP=$(git -C "$a1" rev-parse refs/heads/kit-base)
    _removed=$(comm -23 "$_t/a7.refs0" "$_t/a7.refs1" | grep -c . || :)
    _added=$(comm -13 "$_t/a7.refs0" "$_t/a7.refs1" | grep -c . || :)
    _newtags=$(comm -13 "$_t/a7.refs0" "$_t/a7.refs1" | grep -c ' refs/tags/kit-base/' || :)
    if diff -u "$_t/a7.fp0" "$_t/a7.fp1" >/dev/null 2>&1 && [ "$NEW_TIP" != "$OLD_TIP" ] \
       && [ "$_removed" -eq 1 ] && [ "$_added" -eq 1 ] && [ "$_newtags" -eq 0 ] \
       && [ "$(git -C "$a1" rev-parse "kit-base^")" = "$OLD_TIP" ]; then
      pass "A7 [NON-MUTATION] — kit-base moved (parent = the old tip), NO tag appeared (the take was partial); HEAD, index, config, worktree and every other ref are byte-identical"
    else
      fail "A7 [NON-MUTATION] — the advance changed more (or less) than kit-base alone (removed=$_removed added=$_added newtags=$_newtags)"
      diff -u "$_t/a7.fp0" "$_t/a7.fp1" | grep -E '^[+-][^+-]' | head -8 >&2 || :
    fi
    _trailer=$(git -C "$a1" log -1 --format='%(trailers:key=Kit-Source,valueonly)' kit-base | sed -n '1p')
    if [ "$_trailer" = "$R1" ] && [ "$(git -C "$a1" show kit-base:.kit-source)" = "$(printf 'commit %s\nversion %s' "$R1" "$VER")" ]; then
      pass "A7 [RECORDS-R1] — the new kit-base commit carries Kit-Source: R1 and a tree whose .kit-source is R1"
    else
      fail "A7 [RECORDS-R1] — the new kit-base commit does not record R1 (trailer='$_trailer')"
    fi
    if [ "$(tip_trailer "$a1" Kit-Behind)" = 1 ] && [ "$(behind_lines "$a1")" = "$OLD_TIP $UP_D" ]; then
      pass "A7 [PARTIAL-RECORD] — F1 declined $UP_D: the commit carries Kit-Behind: 1 and exactly one 'behind <old tip> $UP_D' line"
    else
      fail "A7 [PARTIAL-RECORD] — expected Kit-Behind: 1 and 'behind $OLD_TIP $UP_D'; got '$(tip_trailer "$a1" Kit-Behind)' / '$(behind_lines "$a1")'"
    fi
    if grep -q 'stays local' "$_t/adv1"; then
      pass "A7 [PUBLISH-LOCAL] — no remote to publish to: the advance says kit-base stays local and exits 0"
    else
      fail "A7 [PUBLISH-LOCAL] — the advance does not say 'kit-base stays local' when there is no remote"
    fi
  fi

  # A8 (on F1, after the advance) — already in the chain; --at while HEAD records .kit-source.
  refuses 'A8 sha-already-in-the-chain' "$a1" 'already in the kit-base chain' "$_t/a8a" --advance-base --from "$_t/vendor"
  refuses 'A8 --at-with-.kit-source'    "$a1" 'only accepted when HEAD has no .kit-source' "$_t/a8b" --advance-base --from "$_t/vendor" --at "$R0"

  # U2: R1 (the base, now) -> R2.
  ku "$a1" "$KU" "$_t/rep2" --from "$_t/vendor"
  if [ "$KU_RC" -ne 0 ]; then fail "U2 — '--from <R2>' failed after the advance (rc=$KU_RC): $(sed -n '1,5p' "$_t/rep2" | tr '\n' '|')"; return 1; fi
  _h2=$(header_line "$_t/rep2")

  # A1 — offered = exactly R2's new paths (+ the generated .kit-source/.kit-digests records); R1's are current.
  _extra=$(section "$_t/rep2" offered | grep -vxF -e "$UP_A" -e "$UP_X" -e "$UP_D" -e .kit-source -e .kit-digests | grep -c . || :)
  if in_section "$_t/rep2" offered "$UP_A" && in_section "$_t/rep2" offered "$UP_X" && [ "$_extra" -eq 0 ]; then
    pass "A1 [OFFERED-EXACT] — offered = R2's new paths ($UP_A, $UP_X) + the declined $UP_D + the generated records; nothing else"
  else
    fail "A1 [OFFERED-EXACT] — offered is not exactly R2's new paths ($_extra unexpected):"
    section "$_t/rep2" offered | sed 's/^/      /' >&2 || :
  fi
  if in_section "$_t/rep2" current "$UP_CI" && in_section "$_t/rep2" current "$UP_CIOUT"; then
    pass "A1 [CURRENT] — the R1 files the adopter took ($UP_CI, $UP_CIOUT) are listed as current"
  else
    fail "A1 [CURRENT] — R1's applied files are not under 'current'"
  fi
  _bad=0
  for _f in "$UP_A" "$UP_CI" "$UP_CIOUT" .kit-source; do
    ! in_section "$_t/rep2" CONFLICT "$_f" || { fail "A1 [NO-STALE-CONFLICT] — R1-applied $_f is reported CONFLICT (the defect)"; _bad=1; }
  done
  [ "$_bad" -eq 0 ] && pass "A1 [NO-STALE-CONFLICT] — none of the paths R1 applied is a CONFLICT"

  # A2 — the adopter-edited file R2 also changes stays a CONFLICT, never offered.
  if in_section "$_t/rep2" CONFLICT "$UP_P" && ! in_section "$_t/rep2" offered "$UP_P"; then
    pass "A2 [EDITED-STAYS-CONFLICT] — $UP_P (adopter-edited, R2 changes it) is a CONFLICT and not offered"
  else
    fail "A2 [EDITED-STAYS-CONFLICT] — $UP_P must be a CONFLICT and never offered"
  fi

  # A3 — two updates of one VERSION are distinguishable: labels, tags, chain.
  _e1="v$VER@$(sha12 "$R0") (kit-base) -> v$VER@$(sha12 "$R1") (--from)"
  _e2="v$VER@$(sha12 "$R1") (kit-base) -> v$VER@$(sha12 "$R2") (--from)"
  _tags=$(git -C "$a1" tag -l 'kit-base/*' | LC_ALL=C sort | tr '\n' ' ')
  # F1 declined $UP_D at R1, so its R1 advance is PARTIAL: it moves kit-base alone — a tag always names a release FULLY taken
  _etags=$(printf 'kit-base/v%s+%s\n' "$VER" "$(sha12 "$R0")" | tr '\n' ' ')
  if [ "$_h1" = "$_e1" ] && [ "$_h2" = "$_e2" ] && [ "$_h1" != "$_h2" ] \
     && [ "$_tags" = "$_etags" ] && [ "$(git -C "$a1" rev-list --count kit-base)" -eq 2 ]; then
    pass "A3 [DISTINCT] — one VERSION, two updates: labels '$_h1' / '$_h2' (the partial R1 advance made no tag: $_tags), a two-commit chain"
  else
    fail "A3 [DISTINCT] — labels/tags/chain wrong. headers: '$_h1' | '$_h2' (want '$_e1' | '$_e2'); tags: '$_tags' (want '$_etags')"
  fi

  # A6 — the declined hunk is offered again (and is not a CONFLICT).
  if a6_holds "$_t/rep2"; then
    pass "A6 [DECLINED-RE-OFFERED] — $UP_D, declined at R1, is offered again against R2 (declining is not permanent)"
  else
    fail "A6 [DECLINED-RE-OFFERED] — the declined $UP_D is not re-offered (or is a CONFLICT)"
  fi

  # A13 + base-ahead — a3 = F1 at a two-commit chain whose ONLY path differing from both the tip base and the
  # new release is ADOPTER-OWNED (the process-doc edit undone, R1's declined brownfield change applied).
  a3=$_t/a3
  cp -R "$a1" "$a3"
  ( cd "$a3" && sed '$d' "$UP_P" | sed '$d' > "$UP_P.new" && mv "$UP_P.new" "$UP_P" \
      && printf '\n<!-- R1 upstream change (fixture) -->\n' >> "$UP_D" \
      && printf '# adopter notes\n' > docs/adopter-notes.md \
      && git add -A && $GIT_C commit -qm 'adopter: only an own file differs from the base' ) >/dev/null 2>&1 \
    || { fail "A13 fixture: could not prepare a3"; return 1; }
  ku "$a3" "$KU" "$_t/rep3" --from "$_t/vendor"
  if [ "$KU_RC" -ne 0 ]; then fail "A13 — '--from' on a3 failed (rc=$KU_RC): $(sed -n '1,5p' "$_t/rep3" | tr '\n' '|')"; return 1; fi
  if grep -qF 'chain: kit-base records 2 release(s); 0 older one(s) rebuilt' "$_t/rep3" && in_section "$_t/rep3" offered "$UP_A"; then
    pass "A13 [WALK-STOPS-EARLY] — only an adopter-owned path was undecided: 0 older bases rebuilt, and the update is still offered"
  else
    fail "A13 [WALK-STOPS-EARLY] — an adopter-owned file kept the chain walk going: $(grep '^chain:' "$_t/rep3")"
  fi
  # base AHEAD of HEAD: HEAD records R0 (an older chain commit), the tip records R1
  ( cd "$a3" && printf 'commit %s\nversion %s\n' "$R0" "$VER" > .kit-source && git add -A && $GIT_C commit -qm 'HEAD records R0' ) >/dev/null 2>&1 \
    || { fail "A14 fixture: could not rewrite a3's .kit-source"; return 1; }
  refuses 'A14 base-ahead-of-HEAD' "$a3" 'AHEAD of HEAD' "$_t/a14f" --from "$_t/vendor"

  # ───────────────────────────── F2: a LEGACY adopter, the coldtest shape (A5, A8) ──────────────────────
  a2=$_t/a2
  build_adopter "$a2" "$_t/src0" 1 || return 1
  if git -C "$a2" cat-file -e 'HEAD:.kit-source' 2>/dev/null \
     || [ -n "$(git -C "$a2" log -1 --format='%(trailers:key=Kit-Source,valueonly)' kit-base)" ] \
     || ! git -C "$a2" rev-parse --verify --quiet "refs/tags/kit-base/v$VER" >/dev/null 2>&1; then
    fail "fixture: F2 is not a LEGACY tree (it must have no .kit-source, no Kit-Source trailer, and the plain kit-base/v$VER tag)"; return 1
  fi
  # R1 taken with NO advance (the patch minus the .kit-source it would add — that file did not exist then)
  ku "$a2" "$KU" "$_t/l1" --from "$_t/src1"
  [ "$KU_RC" -eq 0 ] || { fail "F2 U1 — '--from <R1>' failed on the legacy adopter (rc=$KU_RC)"; return 1; }
  take "$a2" "$_t/l1" 'take R1 (no advance)' --exclude=.kit-source || return 1

  # A8 on the legacy tree: no --at, malformed, unreachable. (Each: exit 1, reason, nothing written.)
  refuses 'A8 legacy-needs---at'   "$a2" 'HEAD has no \.kit-source' "$_t/a8c" --advance-base --from "$_t/vendor"
  refuses 'A8 malformed-sha'       "$a2" 'malformed' "$_t/a8d" --advance-base --from "$_t/vendor" --at 'not-a-sha'
  refuses 'A8 too-short-sha'       "$a2" 'malformed' "$_t/a8e" --advance-base --from "$_t/vendor" --at abc12
  refuses 'A8 unreachable-sha'     "$a2" 'unreachable' "$_t/a8f" --advance-base --from "$_t/vendor" --at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  _nokb=$_t/nokb; git init -q "$_nokb" >/dev/null 2>&1 || :
  refuses 'A8 no-kit-base'         "$_nokb" "no 'kit-base' branch" "$_t/a8g" --advance-base --from "$_t/vendor" --at "$R1"

  # A14 — the write-side refusals (each: exit 1, names the reason, and NOTHING moved).
  _tag1="kit-base/v$VER+$(sha12 "$R1")"
  git -C "$a2" tag "$_tag1" kit-base
  refuses 'A14 tag-already-exists' "$a2" 'already exists' "$_t/a14a" --advance-base --from "$_t/vendor" --at "$R1"
  git -C "$a2" tag -d "$_tag1" >/dev/null 2>&1 || :
  # a vendor commit whose VERSION makes a tag name git refuses: the refusal comes BEFORE any ref moves
  git clone --quiet --no-tags -- "$_t/vendor" "$_t/vbad" >/dev/null 2>&1 || { fail "fixture: cannot clone the bad-VERSION vendor"; return 1; }
  printf '1..2\n' > "$_t/vbad/VERSION"
  ( cd "$_t/vbad" && git add -A && $GIT_C commit -qm 'R3: a VERSION that is not a valid tag component (fixture)' ) >/dev/null 2>&1 \
    || { fail "fixture: cannot commit the bad-VERSION release"; return 1; }
  R3=$(git -C "$_t/vbad" rev-parse HEAD)
  refuses 'A14 bad-tag-name' "$a2" 'not a valid' "$_t/a14b" --advance-base --from "$_t/vbad" --at "$R3"
  # a DANGLING commit: a local-path clone copies the object, but it is not in --from's history
  _dang=$(git -C "$_t/vendor" -c user.email=t@t -c user.name=t commit-tree "$R2^{tree}" -p "$R2" -m dangling 2>/dev/null) \
    || { fail "fixture: cannot create a dangling commit"; return 1; }
  git clone --quiet --no-tags -- "$_t/vendor" "$_t/dchk" >/dev/null 2>&1 || :
  if git -C "$_t/dchk" cat-file -e "$_dang^{commit}" 2>/dev/null; then
    refuses 'A14 dangling-not-history' "$a2" 'not in the history|unreachable' "$_t/a14c" --advance-base --from "$_t/vendor" --at "$_dang"
  else
    echo "SKIP: A14 dangling-not-history — this git's local clone does not copy unreachable objects (the leg would be vacuous)"
  fi
  # an ambient git locator would redirect the writer's git: refused at entry
  KU_RC=0
  ( cd "$a2" && GIT_INDEX_FILE="$_t/not-an-index" sh "$KU" --repo "$a2" --advance-base --from "$_t/vendor" --at "$R1" ) >"$_t/a14d" 2>&1 || KU_RC=$?
  if [ "$KU_RC" -eq 1 ] && grep -q 'GIT_INDEX_FILE' "$_t/a14d"; then
    pass "A14 [AMBIENT-GIT-ENV] — an exported GIT_INDEX_FILE is refused (exit 1, names it) before anything runs"
  else
    fail "A14 [AMBIENT-GIT-ENV] — expected exit 1 naming GIT_INDEX_FILE; rc=$KU_RC: $(sed -n '1,3p' "$_t/a14d" | tr '\n' '|')"
  fi

  # R2: the pre-advance run (the stranded shape) — STALE-BASE notice; then take ONLY the process doc.
  ku "$a2" "$KU" "$_t/l2" --from "$_t/vendor"
  [ "$KU_RC" -eq 0 ] || { fail "F2 U2 — '--from <R2>' failed on the legacy adopter before the advance (rc=$KU_RC)"; return 1; }
  if grep -q 'STALE-BASE' "$_t/l2" && grep -q -- '--advance-base' "$_t/l2" && grep -q -- '--at' "$_t/l2"; then
    pass "A5 [LEGACY-STALE-NOTICE] — a legacy run where applied files already equal --from prints STALE-BASE naming --advance-base --at"
  else
    fail "A5 [LEGACY-STALE-NOTICE] — no STALE-BASE notice (naming --advance-base --at) on the legacy stranded shape"
  fi
  take "$a2" "$_t/l2" 'take R2 partly (process doc only)' --include="$UP_P" || return 1

  # the migration: --at R1 (12-hex, resolved to 40 in the clone) then --at R2 (40-hex)
  ku "$a2" "$KU" "$_t/mig1" --advance-base --from "$_t/vendor" --at "$(sha12 "$R1")"
  [ "$KU_RC" -eq 0 ] || { fail "A5 — '--advance-base --at R1' failed (rc=$KU_RC): $(sed -n '1,6p' "$_t/mig1" | tr '\n' '|')"; return 1; }
  if grep -q 'ASSERTED' "$_t/mig1"; then
    pass "A5 [ASSERTED] — a legacy --at is announced as ASSERTED, not recorded"
  else
    fail "A5 [ASSERTED] — the legacy advance never says the sha is ASSERTED"
  fi
  ku "$a2" "$KU" "$_t/mig2" --advance-base --from "$_t/vendor" --at "$R2"
  [ "$KU_RC" -eq 0 ] || { fail "A5 — '--advance-base --at R2' failed (rc=$KU_RC): $(sed -n '1,6p' "$_t/mig2" | tr '\n' '|')"; return 1; }
  if [ "$(git -C "$a2" rev-list --count kit-base)" -eq 3 ]; then
    pass "A5 [CHAIN] — adoption -> R1 -> R2: a three-commit chain"
  else
    fail "A5 [CHAIN] — the migrated chain is not three commits"
  fi

  # A14 out-of-order: the tip now records R2; recording the OLDER R0 afterwards would invert the chain
  refuses 'A14 out-of-order' "$a2" 'out of order' "$_t/a14e" --advance-base --from "$_t/vendor" --at "$R0"
  # A17 — R1 is in the chain but the tip records R2: a re-advance is only for the TIP's release
  refuses 'A17 release-in-chain-not-at-tip' "$a2" 'not the tip' "$_t/a17t" --advance-base --from "$_t/vendor" --at "$R1"

  # the third run, against the migrated chain
  ku "$a2" "$KU" "$_t/l3" --from "$_t/vendor"
  if [ "$KU_RC" -ne 0 ]; then fail "A5 — '--from' after the migration failed (rc=$KU_RC): $(sed -n '1,5p' "$_t/l3" | tr '\n' '|')"; return 1; fi
  if a5_holds "$_t/l3"; then
    pass "A5 [STRANDED-OFFERED] — after --at R1 / --at R2: the R1-stranded $UP_A and the never-taken $UP_X are OFFERED; the taken files are current; nothing already taken is a CONFLICT"
  else
    fail "A5 [STRANDED-OFFERED] — the migrated adopter's run is wrong (stranded not offered, or a taken file reads CONFLICT):"
    for _s in offered current CONFLICT; do echo "   == $_s" >&2; section "$_t/l3" "$_s" | sed 's/^/      /' >&2 || :; done
  fi

  # A12 — the pin note: UP_A is decided by the OLDER R1 release and says so
  if grep -qF -- "pristine at $(sha12 "$R1") — an older release you took" "$_t/l3" && grep -q 'deliberate pin' "$_t/l3"; then
    pass "A12 [PIN-NOTE] — the stranded $UP_A is marked 'pristine at $(sha12 "$R1")' with the deliberate-pin caution"
  else
    fail "A12 [PIN-NOTE] — no '(pristine at $(sha12 "$R1") — an older release you took ...)' note on the offered stranded path"
  fi

  # A11 — the stranded file's grouping: walked from the release that DECIDED it, not only from the tip.
  a11_check "$_t/l3" "$R1" "$R2"

  # ───────────────────────────── A10 — the walk is load-bearing: mutate it, A5/A6 must FAIL ─────────────
  # Since KIT-UPDATE-PARTIAL-ADOPTION the advance records per path what HEAD did not take, so on a chain written by
  # TODAY's tool the stranded (A5) and declined (A6) files are rescued by the BEHIND record and the walk is not what
  # decides them. The walk is still load-bearing for every chain the PRE-provenance tool wrote (a base that over-claims:
  # a release recorded whole, no Kit-Behind). So the mutant runs on copies of a2/a1 whose advances are re-done by the
  # `_KU_BEHIND=off` tool (the A15/A17 mutant, below): the real tool must hold A5/A6 there, the tip-only walk must not.
  if ! mutate_chain_walk "$KU" "$_t/kit-update.mut.sh" || ! mutate_behind "$KU" "$_t/kit-update.mut2.sh"; then
    fail "A10 — could not build the mutants: scripts/kit-update.sh must carry exactly ONE greppable '_KU_CHAIN_WALK=all' line and ONE '_KU_BEHIND=on' line"
  else
    a2o=$_t/a2o; cp -R "$a2" "$a2o"
    git -C "$a2o" update-ref refs/heads/kit-base "$(git -C "$a2o" rev-list --first-parent refs/heads/kit-base | tail -n 1)"
    ku "$a2o" "$_t/kit-update.mut2.sh" "$_t/o1" --advance-base --from "$_t/vendor" --at "$(sha12 "$R1")"
    _o1=$KU_RC
    ku "$a2o" "$_t/kit-update.mut2.sh" "$_t/o2" --advance-base --from "$_t/vendor" --at "$R2"
    _o2=$KU_RC
    a1o=$_t/a1o; cp -R "$a1" "$a1o"
    git -C "$a1o" update-ref refs/heads/kit-base "$(git -C "$a1o" rev-list --first-parent refs/heads/kit-base | tail -n 1)"
    ku "$a1o" "$_t/kit-update.mut2.sh" "$_t/o3" --advance-base --from "$_t/vendor"
    _o3=$KU_RC
    if [ "$_o1" -ne 0 ] || [ "$_o2" -ne 0 ] || [ "$_o3" -ne 0 ] || [ "$(tip_trailer "$a2o" Kit-Behind)" != 0 ] || [ "$(tip_trailer "$a1o" Kit-Behind)" != 0 ]; then
      fail "A10 — could not rebuild the pre-provenance chains (rc $_o1/$_o2/$_o3; they must record 0 behind)"
    else
      ku "$a2o" "$KU" "$_t/real5" --from "$_t/vendor"; _r5=$KU_RC
      ku "$a1o" "$KU" "$_t/real6" --from "$_t/vendor"; _r6=$KU_RC
      ku "$a2o" "$_t/kit-update.mut.sh" "$_t/mut5" --from "$_t/vendor"; _m5=$KU_RC
      ku "$a1o" "$_t/kit-update.mut.sh" "$_t/mut6" --from "$_t/vendor"; _m6=$KU_RC
      if [ "$_r5" -ne 0 ] || [ "$_r6" -ne 0 ] || [ "$_m5" -ne 0 ] || [ "$_m6" -ne 0 ] \
         || ! grep -q '^computed: ' "$_t/mut5" || ! grep -q '^computed: ' "$_t/mut6"; then
        fail "A10 — a run on the pre-provenance chains did not reach a report (rc $_r5/$_r6 real, $_m5/$_m6 mutant): it must fail on the ASSERTIONS, not by crashing"
      else
        if a5_holds "$_t/real5" && a6_holds "$_t/real6"; then
          pass "A10 [WALK-RESCUES-AN-OVERCLAIMING-CHAIN] — on a chain written without the behind record, the real walk still holds A5 (stranded) and A6 (declined)"
        else
          fail "A10 [WALK-RESCUES-AN-OVERCLAIMING-CHAIN] — the real tool no longer rescues the stranded/declined files on a pre-provenance chain"
        fi
        if a5_holds "$_t/mut5"; then
          fail "A10 [A5-VACUOUS] — A5 still HOLDS on a tip-only walk: A5 does not need the chain walk, so it proves nothing"
        else
          pass "A10 [A5-NEEDS-THE-WALK] — with the walk limited to the tip, A5 FAILS (the stranded file reads untouched)"
        fi
        if a6_holds "$_t/mut6"; then
          fail "A10 [A6-VACUOUS] — A6 still HOLDS on a tip-only walk: A6 does not need the chain walk, so it proves nothing"
        else
          pass "A10 [A6-NEEDS-THE-WALK] — with the walk limited to the tip, A6 FAILS (the declined hunk reads untouched)"
        fi
      fi
    fi
  fi

  # A12 re-add — F1 deletes the file R1 added (absent at the ADOPTION release too): offered again, marked a re-add
  ( cd "$a1" && git rm -q "$UP_NEW" && $GIT_C commit -qm 'adopter deletes the file R1 added' ) >/dev/null 2>&1 \
    || { fail "A12 fixture: could not delete $UP_NEW in F1"; return 1; }
  ku "$a1" "$KU" "$_t/rep4" --from "$_t/vendor"
  if [ "$KU_RC" -ne 0 ]; then fail "A12 — '--from' after the deletion failed (rc=$KU_RC)"; return 1; fi
  if in_section "$_t/rep4" offered "$UP_NEW" && grep -qF '(re-add' "$_t/rep4"; then
    pass "A12 [RE-ADD] — the file you deleted that the adoption release lacked is offered again and marked a re-add"
  else
    fail "A12 [RE-ADD] — $UP_NEW is not offered as a marked re-add"
  fi

  # ═══ KIT-UPDATE-PARTIAL-ADOPTION (A15–A20): the advance records what HEAD actually took, per path ═════════════
  # b0 = an adopter at R0 with nothing taken; every leg below works on its own copy of it. R1 (src1) is "the
  # release": it changes $UP_A, $UP_D, $UP_CI (+ the derived CI workflow), adds $UP_NEW, and moves the records.
  b0=$_t/b0
  build_adopter "$b0" "$_t/src0" 0 || return 1
  _tagR1="kit-base/v$VER+$(sha12 "$R1")"
  ku "$b0" "$KU" "$_t/r1.b0" --from "$_t/src1"   # ONE run: the offered patch every untouched copy of b0 takes (flow_partial, A16)
  [ "$KU_RC" -eq 0 ] || { fail "A15 fixture — b0's --from <R1> failed (rc=$KU_RC): $(sed -n '1,5p' "$_t/r1.b0" | tr '\n' '|')"; return 1; }

  # A15 [PARTIAL-TAKE, conflict half] — the adopter keeps an edit on $UP_D that conflicts with R1's change to it.
  bA=$_t/bA; cp -R "$b0" "$bA"
  ( cd "$bA" && printf '\n<!-- adopter local note -->\n' >> "$UP_D" && git add -A && $GIT_C commit -qm 'adopter edits the brownfield doc' ) >/dev/null 2>&1 \
    || { fail "A15 fixture: could not edit $UP_D in bA"; return 1; }
  ku "$bA" "$KU" "$_t/pa1" --from "$_t/src1"
  if [ "$KU_RC" -ne 0 ] || ! in_section "$_t/pa1" CONFLICT "$UP_D"; then fail "A15 fixture — bA's first run must report $UP_D as a CONFLICT (rc=$KU_RC)"; return 1; fi
  take "$bA" "$_t/pa1" 'take R1 (the brownfield doc conflicts, so it is not in the patch)' || return 1
  _bA_old=$(git -C "$bA" rev-parse refs/heads/kit-base)
  ku "$bA" "$KU" "$_t/pa2" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && [ "$(tip_trailer "$bA" Kit-Behind)" = 1 ] && [ "$(behind_lines "$bA")" = "$_bA_old $UP_D" ] \
     && [ "$(tag_count "$bA")" -eq 1 ] && [ "$(git -C "$bA" show kit-base:.kit-source)" = "$(printf 'commit %s\nversion %s' "$R1" "$VER")" ]; then
    pass "A15 [PARTIAL-RECORD] — two of three taken, one kept: Kit-Behind: 1, exactly 'behind <old tip> $UP_D', NO tag, and the tree is still R1's raw export"
  else
    fail "A15 [PARTIAL-RECORD] — expected Kit-Behind: 1 with only $UP_D behind and no new tag; rc=$KU_RC Kit-Behind='$(tip_trailer "$bA" Kit-Behind)' behind='$(behind_lines "$bA")' tags=$(tag_count "$bA")"
  fi
  ku "$bA" "$KU" "$_t/pa3" --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && [ "$(section "$_t/pa3" CONFLICT)" = "$UP_D" ] && [ "$(count_of "$_t/pa3" offered)" = 0 ] \
     && grep -q 'PARTIAL — 1 file(s) behind (listed under offered/CONFLICT)' "$_t/pa3"; then
    pass "A15 [REMAINDER-IS-CONFLICT] — the next --from at the same release lists $UP_D in CONFLICT and nothing else (offered 0), labelled PARTIAL"
  else
    fail "A15 [REMAINDER-IS-CONFLICT] — the kept file is not exactly the CONFLICT remainder: offered=$(count_of "$_t/pa3" offered) CONFLICT='$(section "$_t/pa3" CONFLICT | tr '\n' ' ')'"
  fi
  # A17 [NO-PROGRESS] — nothing new was taken since: the re-advance is refused, writing nothing
  refuses 'A17 no-progress' "$bA" 'nothing new was taken' "$_t/pa4" --advance-base --from "$_t/src1"

  # A19 [UNDO-STALE] — the documented undo (kit-base back to the old tip), then the STALE refusal names the cure,
  # and the cure writes the partial record again
  git -C "$bA" update-ref refs/heads/kit-base "$_bA_old"
  refuses 'A19 undo-then-stale' "$bA" 'STALE BASE' "$_t/pa5" --from "$_t/src1"
  if grep -q -- "--advance-base --from" "$_t/pa5" && grep -qi 'agent' "$_t/pa5"; then
    pass "A19 [CURE-NAMES-THE-AGENT] — the STALE refusal prints the --advance-base command and says the agent runs it"
  else
    fail "A19 [CURE-NAMES-THE-AGENT] — the STALE cure does not print '--advance-base --from' and name the agent"
  fi
  ku "$bA" "$KU" "$_t/pa6" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && [ "$(tip_trailer "$bA" Kit-Behind)" = 1 ] && [ "$(behind_lines "$bA")" = "$_bA_old $UP_D" ] && [ "$(tag_count "$bA")" -eq 1 ]; then
    pass "A19 [CURE-WRITES-PARTIAL] — after the undo, the cure advance records the same partial release (Kit-Behind: 1, no tag)"
  else
    fail "A19 [CURE-WRITES-PARTIAL] — the cure after the undo did not write the partial record (rc=$KU_RC, Kit-Behind='$(tip_trailer "$bA" Kit-Behind)')"
  fi

  # A15 (pristine half) + A17 [FINISH] — one flow, run QUIETLY (the mutant below runs it too)
  bB=$_t/bB; cp -R "$b0" "$bB"
  flow_partial "$KU" "$bB" "$_t/fp"
  if [ "$FP_15" -eq 1 ]; then
    pass "A15 [REMAINDER-IS-OFFERED] — with $UP_D left pristine: Kit-Behind: 1 / no tag, and the next --from offers $UP_D alone (0 CONFLICT)"
  else
    fail "A15 [REMAINDER-IS-OFFERED] — $FP_WHY"
  fi
  if [ "$FP_17" -eq 1 ]; then
    pass "A17 [FINISH] — taking the remainder and re-advancing at R1 writes a child commit with Kit-Behind: 0 and creates the R1 tag; a second re-advance is refused rc 1, writing nothing"
  else
    fail "A17 [FINISH] — $FP_WHY"
  fi
  if [ "$FP_NOTE" -eq 1 ]; then
    pass "A17 [TAKEN-REMAINDER-NOTE] — after the remainder is taken but before the re-advance, --from notes that 1 behind path already equals the tip's release"
  else
    fail "A17 [TAKEN-REMAINDER-NOTE] — --from does not say a behind path already equals the tip's release (run --advance-base first)"
  fi
  # R-3: NEXT names the advance only when there is something to record (a newer release, or a tip still partial)
  if grep -q '^NEXT (the agent, after this update' "$_t/pa1" && grep -q '^NEXT (the agent, after this update' "$_t/pa3" \
     && grep -q '^NEXT (the agent, after this update' "$_t/fp.r2"; then
    pass "A15 [NEXT-NAMES-THE-AGENT] — a report on a newer release, and a report on a PARTIAL tip, each end by naming the advance as the agent's step"
  else
    fail "A15 [NEXT-NAMES-THE-AGENT] — a --from report that has something to record does not carry the NEXT (the agent …) line"
  fi

  # A16 [FULL-TAKE] (negative control) — all taken: Kit-Behind: 0, the tag, and a clean next run
  bC=$_t/bC; cp -R "$b0" "$bC"
  take "$bC" "$_t/r1.b0" 'take all of R1' || return 1
  bF=$_t/bF; cp -R "$bC" "$bF"     # A20's copy: the whole release taken, nothing advanced yet
  ku "$bC" "$KU" "$_t/fc2" --advance-base --from "$_t/src1"
  _rc16=$KU_RC
  ku "$bC" "$KU" "$_t/fc3" --from "$_t/src1"
  if [ "$_rc16" -eq 0 ] && [ "$(tip_trailer "$bC" Kit-Behind)" = 0 ] && [ -z "$(behind_lines "$bC")" ] \
     && git -C "$bC" rev-parse --verify --quiet "refs/tags/$_tagR1" >/dev/null 2>&1 \
     && [ "$KU_RC" -eq 0 ] && [ "$(count_of "$_t/fc3" offered)" = 0 ] && [ "$(count_of "$_t/fc3" CONFLICT)" = 0 ] \
     && ! grep -q 'PARTIAL' "$_t/fc3"; then
    pass "A16 [FULL-TAKE] — all of R1 taken: Kit-Behind: 0, no behind lines, the R1 tag exists, and the next --from is offered 0 / CONFLICT 0 with no PARTIAL line"
  else
    fail "A16 [FULL-TAKE] — rc=$_rc16 Kit-Behind='$(tip_trailer "$bC" Kit-Behind)' offered=$(count_of "$_t/fc3" offered) CONFLICT=$(count_of "$_t/fc3" CONFLICT)"
  fi
  if grep -q '^NEXT: none — kit-base is current' "$_t/fc3" && ! grep -q '^NEXT (the agent' "$_t/fc3"; then
    pass "A16 [NEXT-NONE] — --from at the tip's own release, tip complete: the report ends 'NEXT: none — kit-base is current.'"
  else
    fail "A16 [NEXT-NONE] — a report with nothing to record must say 'NEXT: none', not name an advance"
  fi

  # A18 [MERGED-COUNTS-AS-TAKEN] — a vendor whose R1 changes $UP_D (text) and two BINARY files. The adopter hand-merged
  # $UP_D (R1's hunk is in OURS beside an adopter edit: the merge-file no-op test says taken), took binary A byte-for-byte
  # (equal: taken), and kept its own binary B (merge-file cannot merge binaries; unequal: behind).
  vb=$_t/vb
  git clone --quiet --no-tags "$ROOT" "$vb" >/dev/null 2>&1 || { fail "A18 fixture: could not clone the binary vendor"; return 1; }
  printf 'bin-a-v0\000\001\002\n' > "$vb/docs/adoption/kuba-bin-a.dat"
  printf 'bin-b-v0\000\001\002\n' > "$vb/docs/adoption/kuba-bin-b.dat"
  ( cd "$vb" && git add -A && $GIT_C commit -qm 'B0: two binary files (fixture)' ) >/dev/null 2>&1 || { fail "A18 fixture: B0"; return 1; }
  VB0=$(git -C "$vb" rev-parse HEAD)
  printf 'bin-a-v1\000\003\n' > "$vb/docs/adoption/kuba-bin-a.dat"
  printf 'bin-b-v1\000\003\n' > "$vb/docs/adoption/kuba-bin-b.dat"
  printf '\n<!-- R1 upstream change (fixture) -->\n' >> "$vb/$UP_D"
  ( cd "$vb" && git add -A && $GIT_C commit -qm 'B1: the binaries change, and the brownfield doc (fixture)' ) >/dev/null 2>&1 || { fail "A18 fixture: B1"; return 1; }
  checkout_at "$vb" "$VB0" "$_t/srcb0" || return 1
  checkout_at "$vb" "$(git -C "$vb" rev-parse HEAD)" "$_t/srcb1" || return 1
  bD=$_t/bD
  build_adopter "$bD" "$_t/srcb0" 0 || return 1
  [ -f "$bD/docs/adoption/kuba-bin-a.dat" ] && [ -f "$bD/docs/adoption/kuba-bin-b.dat" ] || { fail "A18 fixture: the binary files did not ship in the export"; return 1; }
  ( cd "$bD" && { printf '<!-- adopter prologue -->\n'; cat "$UP_D"; } > "$UP_D.new" && mv "$UP_D.new" "$UP_D" \
      && printf 'bin-b-adopter\000\011\n' > docs/adoption/kuba-bin-b.dat && git add -A && $GIT_C commit -qm 'adopter edits the doc and binary B' ) >/dev/null 2>&1 \
    || { fail "A18 fixture: adopter edits"; return 1; }
  ku "$bD" "$KU" "$_t/pd1" --from "$_t/srcb1"
  [ "$KU_RC" -eq 0 ] || { fail "A18 fixture — bD's run failed (rc=$KU_RC): $(sed -n '1,5p' "$_t/pd1" | tr '\n' '|')"; return 1; }
  take "$bD" "$_t/pd1" 'take what is offered (binary A)' || return 1
  ( cd "$bD" && printf '\n<!-- R1 upstream change (fixture) -->\n' >> "$UP_D" && git add -A && $GIT_C commit -qm 'adopter hand-merges the doc' ) >/dev/null 2>&1 \
    || { fail "A18 fixture: hand-merge"; return 1; }
  _bD_old=$(git -C "$bD" rev-parse refs/heads/kit-base)
  ku "$bD" "$KU" "$_t/pd2" --advance-base --from "$_t/srcb1"
  if [ "$KU_RC" -eq 0 ] && [ "$(tip_trailer "$bD" Kit-Behind)" = 1 ] && [ "$(behind_lines "$bD")" = "$_bD_old docs/adoption/kuba-bin-b.dat" ]; then
    pass "A18 [MERGED-COUNTS-AS-TAKEN] — the hand-merged $UP_D (merge-file no-op) and the byte-equal binary A are taken; only the divergent binary B is behind"
  else
    fail "A18 [MERGED-COUNTS-AS-TAKEN] — expected exactly 'behind <old tip> docs/adoption/kuba-bin-b.dat'; rc=$KU_RC Kit-Behind='$(tip_trailer "$bD" Kit-Behind)' behind='$(behind_lines "$bD" | tr '\n' ' ')'"
  fi

  # A20 [PUBLISH] — a local BARE repo as `origin` (no network). bF = R1 fully taken, not yet advanced.
  _org=$_t/origin.git
  git clone -q --bare "$b0" "$_org" >/dev/null 2>&1 || { fail "A20 fixture: could not make the bare origin"; return 1; }
  if ! { git -C "$bF" remote add origin "$_org" && git -C "$bF" fetch -q origin >/dev/null 2>&1 \
         && git -C "$bF" remote set-head origin -a >/dev/null 2>&1; }; then fail "A20 fixture: could not wire origin"; return 1; fi
  _brn=$(git -C "$bF" symbolic-ref --short HEAD)
  _bF_old=$(git -C "$bF" rev-parse refs/heads/kit-base)
  # The adopter has the kit's REAL pre-push hook installed (the way an adopter installs it: the tracked hooks/pre-push
  # copied into .git/hooks): it grades every refs/heads/* push except main/master, so a push of refs/heads/kit-base would
  # be refused. The base is published to the NON-BRANCH ref refs/kit/base. A clone made from b0 carries kit-base as a
  # branch on origin: drop it, so the legs below prove origin never gets refs/heads/kit-base from the tool.
  if ! { cp "$bF/hooks/pre-push" "$bF/.git/hooks/pre-push" && chmod +x "$bF/.git/hooks/pre-push" \
         && git -C "$_org" update-ref -d refs/heads/kit-base && git -C "$_org" update-ref refs/kit/base "$_bF_old" \
         && git -C "$bF" update-ref -d refs/remotes/origin/kit-base; }; then   # (the clone's stale remote-tracking kit-base would read as a base that came from a remote branch — KIT-BASE-SHARED A1)
    fail "A20 fixture: could not install the real hook / prepare origin's refs/kit/base"; return 1
  fi
  # the hook only WARNS ("observe") by default; an adopter that enforces it (a dial in .kit/dials.conf, or the env) has the
  # push REFUSED — the env may only escalate, so enforce it for this section's runs (measured: a refs/heads/kit-base push
  # fails "does not carry a valid Entry Declaration"; a refs/kit/base push passes)
  KIT_PUSH_DECL=enforce; export KIT_PUSH_DECL
  # (a) HEAD is ahead of origin/HEAD (the update is not merged-and-pulled): refused before any write
  refuses 'A20 head-off-the-shared-line' "$bF" 'is not reachable from' "$_t/pp1" --advance-base --from "$_t/src1"
  if grep -q 'Check out the default branch and pull, then re-run' "$_t/pp1"; then
    pass "A20 [PULL-HINT] — the refusal says to check out the default branch and pull, then re-run"
  else
    fail "A20 [PULL-HINT] — the head-off-the-shared-line refusal does not say what to do"
  fi
  # --remote is a plain name: an option-shaped or spaced value is refused (rc 2), nothing written, nothing pushed
  for _rv in '-oProxyCommand=x' 'a b'; do
    fingerprint "$bF" all > "$_t/pr.fp0"; git -C "$_org" show-ref > "$_t/pr.org0" 2>&1 || :
    ku "$bF" "$KU" "$_t/pr.out" --advance-base --from "$_t/src1" --remote "$_rv"
    fingerprint "$bF" all > "$_t/pr.fp1"; git -C "$_org" show-ref > "$_t/pr.org1" 2>&1 || :
    if [ "$KU_RC" -eq 2 ] && diff -u "$_t/pr.fp0" "$_t/pr.fp1" >/dev/null 2>&1 && diff -u "$_t/pr.org0" "$_t/pr.org1" >/dev/null 2>&1; then
      pass "A20 [REMOTE-REFUSED] — --remote '$_rv' exits 2; nothing was written and origin is untouched"
    else
      fail "A20 [REMOTE-REFUSED] — --remote '$_rv' was not refused cleanly (rc=$KU_RC)"
    fi
  done
  # (b) --no-push: the local write happens, origin is untouched
  ku "$bF" "$KU" "$_t/pp2" --advance-base --from "$_t/src1" --no-push
  if [ "$KU_RC" -eq 0 ] && [ "$(git -C "$bF" rev-parse refs/heads/kit-base)" != "$_bF_old" ] \
     && [ "$(git -C "$_org" rev-parse refs/kit/base)" = "$_bF_old" ] && [ -z "$(git -C "$_org" tag -l 'kit-base/*' | grep -v "^kit-base/v$VER+$(sha12 "$R0")\$" || :)" ]; then
    pass "A20 [NO-PUSH] — --no-push writes the local advance and leaves origin's kit-base and tags untouched"
  else
    fail "A20 [NO-PUSH] — --no-push did not keep the advance local (rc=$KU_RC)"
  fi
  git -C "$bF" update-ref refs/heads/kit-base "$_bF_old" && git -C "$bF" tag -d "$_tagR1" >/dev/null 2>&1 || :
  # (c) merged-and-pulled (origin/HEAD == HEAD): the advance publishes kit-base and its tag
  if ! { git -C "$_org" fetch -q "$bF" "HEAD:refs/heads/$_brn" >/dev/null 2>&1 && git -C "$bF" fetch -q origin >/dev/null 2>&1; }; then
    fail "A20 fixture: could not sync origin to HEAD"; return 1
  fi
  # two LOCAL kit-base/* tags that are not this tool's: one pointing OFF the chain, one ON it under a name that is not
  # `v<ver>+<sha12 of the tagged commit's Kit-Source>` — neither may be published
  git -C "$bF" tag kit-base/x "$(git -C "$bF" rev-parse HEAD)"
  git -C "$bF" tag kit-base/v0+aaaaaaaaaaaa "$_bF_old"
  ku "$bF" "$KU" "$_t/pp3" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -eq 0 ] && [ "$(git -C "$bF" ls-remote origin refs/kit/base | cut -f1)" = "$(git -C "$bF" rev-parse refs/heads/kit-base)" ] \
     && [ "$(git -C "$_org" rev-parse "refs/tags/$_tagR1^{commit}")" = "$(git -C "$bF" rev-parse refs/heads/kit-base)" ] \
     && [ -z "$(git -C "$bF" ls-remote origin refs/heads/kit-base)" ] \
     && [ -z "$(git -C "$_org" tag -l kit-base/x 'kit-base/v0+*')" ]; then
    pass "A20 [PUBLISHED] — with the real pre-push hook installed, a complete advance pushes: origin's refs/kit/base is the new tip, origin resolves the $_tagR1 tag, origin has NO refs/heads/kit-base, and neither the off-chain tag kit-base/x nor the mis-named on-chain tag was pushed"
  else
    fail "A20 [PUBLISHED] — origin does not carry the new kit-base and tag (rc=$KU_RC): $(sed -n '1,8p' "$_t/pp3" | tr '\n' '|')"
  fi
  # a fresh clone gets the base back with the printed one-liner (the AUTOMATIC fetch-on-missing is KIT-BASE-SHARED)
  _fresh=$_t/fresh; git init -q "$_fresh" >/dev/null 2>&1 || :
  if git -C "$_fresh" fetch -q "$_org" refs/kit/base:refs/heads/kit-base >/dev/null 2>&1 \
     && [ "$(git -C "$_fresh" rev-parse refs/heads/kit-base)" = "$(git -C "$bF" rev-parse refs/heads/kit-base)" ]; then
    pass "A20 [FETCH-BACK] — 'git fetch origin refs/kit/base:refs/heads/kit-base' gives a fresh clone the published base"
  else
    fail "A20 [FETCH-BACK] — a fresh clone cannot fetch refs/kit/base back into refs/heads/kit-base"
  fi
  # (d) a teammate advanced origin's kit-base: rejected -> rc 3, the local write stands, nothing forced
  git -C "$bF" update-ref refs/heads/kit-base "$_bF_old" && git -C "$bF" tag -d "$_tagR1" >/dev/null 2>&1 || :
  git -C "$_org" tag -d "$_tagR1" >/dev/null 2>&1 || :
  _mate=$(git -C "$_org" -c user.email=t@t -c user.name=t commit-tree "$_bF_old^{tree}" -p "$_bF_old" -m 'teammate advance') \
    || { fail "A20 fixture: could not make the teammate commit"; return 1; }
  git -C "$_org" update-ref refs/kit/base "$_mate"
  ku "$bF" "$KU" "$_t/pp4" --advance-base --from "$_t/src1"
  if [ "$KU_RC" -eq 3 ] && [ "$(git -C "$_org" rev-parse refs/kit/base)" = "$_mate" ] \
     && [ -z "$(git -C "$_org" tag -l "$_tagR1")" ] \
     && [ "$(git -C "$bF" rev-parse "refs/heads/kit-base^")" = "$_bF_old" ] && git -C "$bF" rev-parse --verify --quiet "refs/tags/$_tagR1" >/dev/null 2>&1 \
     && grep -q -e '\[rejected\]' -e 'non-fast-forward' "$_t/pp4" && grep -q 'a teammate advanced refs/kit/base' "$_t/pp4"; then
    pass "A20 [REJECTED-RC3] — a diverged origin refs/kit/base: rc 3, says rejected, the local advance + tag stand, origin is not forced and takes nothing (atomic)"
  else
    fail "A20 [REJECTED-RC3] — expected rc 3 / local write kept / origin untouched; rc=$KU_RC: $(sed -n '1,10p' "$_t/pp4" | tr '\n' '|')"
  fi

  unset KIT_PUSH_DECL

  # A21 [CORRUPT-RECORD] — the behind block is read out of HISTORY: a forged or damaged one must refuse the run as a
  # corrupt base (rc 1, naming "corrupt", nothing moved), for `--from` AND `--advance-base`. bK = a copy of the partial
  # fixture bA whose tip commit is rewritten (same tree, same parent) with each forged record in turn.
  bK=$_t/bK; cp -R "$bA" "$bK"
  _kold=$(git -C "$bK" rev-parse 'kit-base^')
  _kfar=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  _kup=$(printf '%s' "$_kold" | tr 'a-f' 'A-F')
  _kone="behind $_kold $UP_D"
  forge_case() {  # <label> <behind block> <Kit-Behind value>
    forge_tip "$bK" "$2" "$3" || { fail "A21 fixture: could not forge '$1'"; return 0; }
    refuses "A21 $1 (--from)" "$bK" 'corrupt' "$_t/k.from" --from "$_t/src1"
    refuses "A21 $1 (--advance-base)" "$bK" 'corrupt' "$_t/k.adv" --advance-base --from "$_t/src1"
  }
  forge_case 'a-sha-not-on-the-chain'  "behind $_kfar $UP_D" 1
  forge_case 'a-short-sha'             "behind $(printf '%s' "$_kold" | cut -c1-7) $UP_D" 1
  forge_case 'an-uppercase-sha'        "behind $_kup $UP_D" 1
  forge_case 'a-dotdot-path'           "behind $_kold ../x" 1
  forge_case 'a-dot-git-path'          "behind $_kold .git/config" 1
  forge_case 'an-absolute-path'        "behind $_kold /etc/passwd" 1
  forge_case 'the-same-path-twice'     "$_kone
$_kone" 2
  forge_case 'a-count-that-disagrees'  "$_kone" 2
  forge_case 'a-non-numeric-count'     "$_kone" x1
  # a SYMLINKED parent: the forged tip's tree makes docs/operations a symlink, and its behind record names a file under
  # it — taking that file would read/write THROUGH the link, so the effective base refuses before any rm/extract
  _ksi=$_t/ks.index
  _ksb=$(printf '%s' /nonexistent-kupa-link-target | git -C "$bK" hash-object -w --stdin)
  if GIT_INDEX_FILE=$_ksi git -C "$bK" read-tree "$(git -C "$bK" rev-parse 'kit-base^{tree}')" >/dev/null 2>&1 \
     && GIT_INDEX_FILE=$_ksi git -C "$bK" rm -r -q --cached docs/operations >/dev/null 2>&1 \
     && GIT_INDEX_FILE=$_ksi git -C "$bK" update-index --add --cacheinfo "120000,$_ksb,docs/operations" >/dev/null 2>&1; then
    _kst=$(GIT_INDEX_FILE=$_ksi git -C "$bK" write-tree)
    forge_tip "$bK" "behind $_kold docs/operations/doctor.md" 1 "$_kst" || fail "A21 fixture: could not forge the symlinked-parent tip"
    refuses 'A21 a-symlinked-parent-directory (--from)' "$bK" 'corrupt' "$_t/k.sym" --from "$_t/src1"
  else
    fail "A21 fixture: could not build the symlinked-parent tree"
  fi
  # non-vacuity: the _KU_BEHIND_STRICT=off mutant drops the chain-membership check, so the forged-sha case is no longer
  # refused AS corrupt (it dies later, trying to build the unknown commit)
  if ! mutate_strict "$KU" "$_t/kit-update.mut3.sh"; then
    fail "A21 — could not build the _KU_BEHIND_STRICT mutant: scripts/kit-update.sh must carry exactly ONE greppable '_KU_BEHIND_STRICT=on' line"
  else
    forge_tip "$bK" "behind $_kfar $UP_D" 1
    ku "$bK" "$_t/kit-update.mut3.sh" "$_t/k.mut" --from "$_t/src1"
    if [ "$KU_RC" -eq 1 ] && grep -qi 'corrupt' "$_t/k.mut"; then
      fail "A21 [STRICT-VACUOUS] — with the chain-membership check dropped, a forged sha is STILL refused as corrupt: A21 does not need the check"
    else
      pass "A21 [STRICT-NEEDS-THE-CHAIN-CHECK] — with the chain-membership check dropped, the forged-sha record is no longer refused as corrupt (rc $KU_RC)"
    fi
  fi
  # ── the A10 mutant family: `_KU_BEHIND=off` (the advance records 0 behind, as before) must FAIL A15 and A17 ──
  if ! mutate_behind "$KU" "$_t/kit-update.mut2.sh"; then
    fail "A10 — could not build the _KU_BEHIND mutant: scripts/kit-update.sh must carry exactly ONE greppable '_KU_BEHIND=on' line"
  else
    bM=$_t/bM; cp -R "$b0" "$bM"
    flow_partial "$_t/kit-update.mut2.sh" "$bM" "$_t/mutp"
    if [ "$FP_15" -eq 1 ]; then
      fail "A10 [A15-VACUOUS] — A15 still HOLDS when the advance records 0 behind: A15 does not need the provenance, so it proves nothing"
    else
      pass "A10 [A15-NEEDS-THE-PROVENANCE] — with the advance recording 0 behind, A15 FAILS (the kept file is hidden: $FP_WHY)"
    fi
    if [ "$FP_17" -eq 1 ]; then
      fail "A10 [A17-VACUOUS] — A17 still HOLDS when the advance records 0 behind: A17 does not need the partial record"
    else
      pass "A10 [A17-NEEDS-THE-PARTIAL-RECORD] — with the advance recording 0 behind, A17 FAILS (a complete tip cannot be finished)"
    fi
  fi

  _t1=$(date +%s)
  echo "runtime: $((_t1 - _t0)) s"
  if [ "$ST" -eq 0 ]; then
    echo "OK: kit-update-advance — kit-base is a chain: --advance-base writes only kit-base + one tag, a stale base is refused,"
    echo "    'pristine' means equal to ANY release the adopter took (declined and stranded files are re-offered, applied"
    echo "    files are current, edited files stay CONFLICT), vendor commits are grouped with the incept-derived CI"
    echo "    attributed by matching lines, and the whole thing is proven non-vacuous (a tip-only walk fails A5 and A6)."
    echo "    A partly taken release is recorded as such (Kit-Behind + per-path behind lines, no tag), re-offered by --from,"
    echo "    finishable by a re-advance, and published to a bare origin (rc 3 when rejected) — and the record is non-vacuous."
    echo "HONEST CEILING: proves the report + the base writer on a synthetic vendor of three commits. It does not prove"
    echo "                the real coldtest numbers (measured separately), nor that any patch was applied by anyone."
  fi
  return "$ST"
}

case "${1:-}" in
  "") ( check ); exit $? ;;
  *) echo "usage: kit-update-advance.sh" >&2; exit 2 ;;
esac
