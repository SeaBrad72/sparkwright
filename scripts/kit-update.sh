#!/bin/sh
# kit-update.sh — bring an adopted project up to a newer Sparkwright release.
#
#   sh scripts/kit-update.sh --from <git-url|local-path> [--repo <path>]   # the update: report + patch
#   sh scripts/kit-update.sh --reconstruct-base <dir>    [--repo <path>]   # just BASE (the merge base)
#
# It REPORTS. It does not APPLY: it prints what a new release would change, writes a patch to a scratch
# path, and leaves every decision — and every write — to you. Nothing here writes to the adopter's repo.
#
# ── THE IDEA (read this before changing anything below) ───────────────────────────────────────────────
# An adopter's tree is NOT a copy of the kit export. It is `incept(export)` — a TRANSFORMATION. incept
# RENAMES CLAUDE.md -> ENGINEERING-PRINCIPLES.md, rewrites cross-references in six more kit files,
# RE-CREATES CLAUDE.md as an adopter-owned project doc from a template, and wires the stack's CI +
# scaffold. So `kit-base` (the pristine export, vendored on an orphan branch at inception) and the
# adopter's worktree live in DIFFERENT COORDINATE SYSTEMS.
#
# Diffing them directly is meaningless: it reports a conflict on every file incept touched, and it
# proposes restoring the KIT's CLAUDE.md over the ADOPTER's project doc — at the same path. That is not
# a merge, it is data loss with a progress bar.
#
# We do not reverse the transformation and we do not RE-DESCRIBE it. We RE-APPLY it, so it cancels:
#
#   BASE   = incept(kit-base)                 <- run with KIT-BASE'S OWN scripts/incept.sh
#   OURS   = the adopter's HEAD               <- untouched
#   THEIRS = incept(export(new release))      <- run with the NEW RELEASE'S OWN scripts
#
# Each side runs through the incept that BELONGS to it, with the SAME recorded stamps and the SAME pinned
# --date, so the transformation CANCELS and only genuine kit changes survive. NEVER hand-maintain a
# rename/ownership table and NEVER re-implement the export/prune: either would be a second source of truth
# about incept's behavior and would rot the first time incept changed. Re-running the real scripts IS the
# design.
#
# THE PROOF THAT THIS IS RIGHT — the IDENTITY PROPERTY (conformance/kit-update-identity.sh):
#   for an adopter who changed NOTHING, incept_old(kit-base) == their HEAD, EXACTLY (empty diff).
# A missed rename, an unpinned date, a wrong prune or a missing stamp all fail it LOUDLY. And it cannot
# be satisfied by a dead code path: an updater that does nothing produces an EMPTY tree, not an EQUAL
# one. That asymmetry is what makes the green non-vacuous.
#
# ── READ THE FACT; REFUSE, NEVER GUESS ───────────────────────────────────────────────────────────────
# A WRONG base silently produces a WRONG delta — strictly worse than no delta at all, because the adopter
# would trust it. So EVERY input this needs is RECORDED: incept stamps all of them into CLAUDE.md §3, and
# this reads them. Nothing is defaulted. In particular an absent adoption date must NEVER become "today" —
# that is the exact fail-open `incept --date` was built to prevent (it exits 2 on an empty value; we rely
# on that rather than working around it).
#
# INFERENCE IS THE FALLBACK, NOT THE DESIGN. Two inputs (the CI platform, the DB archetype) were stamped
# only from T3b onward, so a tree incepted before that carries no record and evidence is all there is. For
# those — and ONLY those — we derive from the two trees, and we SAY SO in the output: an inference is
# announced as an inference, never printed as a fact. Where it cannot decide, it refuses.
#
# ── THE HONEST CEILING (it is PRINTED on every --from run, not just written here — see the tail) ──────
# LATEST ONLY · IT PRESENTS, IT DOES NOT APPLY · IT NEEDS AN INTACT kit-base · AND `--from` IS UNTRUSTED
# INPUT WHOSE CODE THIS TOOL EXECUTES. The last one is not a footnote: building THEIRS means running the
# new release's OWN adopter-export.sh and incept.sh. That is inherent to the design (and to adoption —
# running a kit's incept is the normal path), but the user deserves to be told at the moment they aim it.
#
# Exit: 0 ok · 1 runtime/refusal · 2 usage. POSIX sh; dash-clean.
# What it changes: nothing in the adopter's repo — it writes ONLY the <dir> you name (--reconstruct-base,
#                  which must be empty/absent and OUTSIDE any git repo), temp dirs it removes, and a patch
#                  file at a scratch path it prints.
# Guardrails: NON-MUTATING — reads the adopter via `git archive`/`git fetch` into a THROWAWAY workbench
#             repo; never writes their worktree, index, refs, objects or config. The merge is
#             `git merge-tree --write-tree` (no checkout at all) where the git can do it, and otherwise
#             plain `git merge` in a temporary worktree OF THE WORKBENCH — non-mutating either way, and
#             the tool PRINTS which one ran. The choice is a runtime CAPABILITY PROBE, not a version
#             parse. Refuses (loudly, naming the missing thing) rather than defaulting. An EMPTY
#             computation — including an empty merged tree — is a hard failure, never a quiet "0 changes".
set -eu

USAGE='usage: kit-update.sh --from <git-url|local-path> [--repo <path>] [--merge-impl auto|merge-tree|worktree]
       kit-update.sh --reconstruct-base <dir> [--repo <path>]'
usage() { echo "$USAGE" >&2; exit 2; }

die() { echo "kit-update: $*" >&2; exit 1; }

# --merge-impl: which 3-way merge implementation to use. `auto` (the default) PROBES the capability and
# falls back — see merge3() below. The explicit values exist so the fallback can be exercised and compared
# ON A MODERN GIT (conformance/kit-update-merge.sh runs the same fixture through both and requires the
# same answer): a fallback nobody can run is a promise nobody can check. A FLAG, never an ambient env var —
# the environment does not get to decide how your merge is computed.
MERGE_MODE=auto
REPO=""; OUT=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --from requires a git url or a local path" >&2; exit 2; }; FROM=$2; shift 2 ;;
    --reconstruct-base) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --reconstruct-base requires a directory" >&2; exit 2; }; OUT=$2; shift 2 ;;
    --repo) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --repo requires a path" >&2; exit 2; }; REPO=$2; shift 2 ;;
    --merge-impl)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --merge-impl requires a value (auto|merge-tree|worktree)" >&2; exit 2; }
      case "$2" in
        auto|merge-tree|worktree) MERGE_MODE=$2 ;;
        *) echo "kit-update: --merge-impl must be one of: auto (probe, default) | merge-tree | worktree" >&2; exit 2 ;;
      esac
      shift 2 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    *) echo "kit-update: unknown arg: $1" >&2; usage ;;
  esac
done
[ -n "$OUT" ] || [ -n "$FROM" ] || usage
[ -z "$OUT" ] || [ -z "$FROM" ] || { echo "kit-update: --from and --reconstruct-base are different jobs — pass one." >&2; exit 2; }

[ -n "$REPO" ] || REPO=$PWD
REPO=$( CDPATH='' cd "$REPO" 2>/dev/null && pwd -P ) || die "--repo: no such directory"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "'$REPO' is not a git repository. kit-update works on the adopter's OWN repo (the one incept ran in)."
REPO=$( CDPATH='' cd "$( git -C "$REPO" rev-parse --show-toplevel )" && pwd -P )

# ── the two hard preconditions, each refused BY NAME (a wrong base is worse than no base) ─────────────

# 1. THE BASE ITSELF. Absent = the adopter deleted the ref, or they incepted from a kit that predates the
#    kit-base mechanism. Either way there is NOTHING to reconstruct from and no honest fallback exists:
#    "the tree at version X" is not even unique (the public mirror ships UN-pruned; this adopter's export
#    was pruned to one profile). Say which, and what it means.
git -C "$REPO" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1 || {
  echo "kit-update: no 'kit-base' branch in $REPO." >&2
  echo "  kit-base is the PRISTINE EXPORT this project was adopted from — the merge base every update" >&2
  echo "  needs. incept vendors it (branch 'kit-base', tag 'kit-base/v<VER>'). It is missing because" >&2
  echo "  either (a) it was deleted, or (b) this project was incepted from a kit that predates the" >&2
  echo "  mechanism. There is NO safe fallback: a guessed base yields a WRONG delta, which is worse" >&2
  echo "  than no delta. Recover the branch (git reflog / a clone that still has it), or re-adopt." >&2
  echo "  See docs/operations/kit-base.md." >&2
  exit 1
}

# 2. THE STAMPS. CLAUDE.md §3 is where incept recorded every inception input.
CM="$REPO/CLAUDE.md"
[ -f "$CM" ] || die "no CLAUDE.md in $REPO — the project's inception stamps (§3) live there; without them the base cannot be reconstructed."

# A §3 config-list stamp: "- **<Field>** (§x): <value> — <template annotation…>". incept replaced ONLY the
# bracketed choice-list, so the trailing prose survives — take the FIRST token, never the whole line.
stamp_list() {  # <sed-escaped field prefix>
  sed -n "s/^- \*\*$1\*\*[^:]*: *//p" "$CM" | sed -n '1p' | cut -d' ' -f1
}
# A header stamp: "**<Field>:** <value>" — the value IS the rest of the line (a project name has spaces).
stamp_head() {  # <field>
  sed -n "s/^\*\*$1:\*\* *//p" "$CM" | sed -n '1p' | sed 's/[[:space:]]*$//'
}
# Unfilled template slots still carry their bracketed placeholder — that is NOT a value.
filled() { case "${1:-}" in ''|\[*) return 1 ;; *) return 0 ;; esac; }

NAME=$(stamp_head 'Project')
OWNER=$(stamp_head 'Intent owner')
DATE=$(stamp_head 'Created')
STACK=$(stamp_list 'Stack profile')
BACKLOG=$(stamp_list 'Backlog backend')
MODE=$(stamp_list 'Process mode')
TEAM=$(stamp_list 'Governance')
HARNESS=$(stamp_list 'Target harness(es)')
FLUENCY=$(stamp_list 'Operator fluency')   # OPTIONAL — incept leaves it unstamped when undeclared.
# T3b: the last two inception inputs, now RECORDED. Not in the mandatory `miss` list below: a tree incepted
# BEFORE these slots existed carries no stamp, and refusing it would break every existing adopter. They get
# the announced legacy fallback instead (see below) — absent, never silently defaulted.
CIP=$(stamp_list 'CI platform')
DBA=$(stamp_list 'DB archetype')

miss=''
filled "$NAME"    || miss="$miss\n  - **Project:** — incept requires --name; without it the reconstruction cannot be stamped."
filled "$OWNER"   || miss="$miss\n  - **Intent owner:** — incept requires --intent-owner."
filled "$DATE"    || miss="$miss\n  - **Created:** — the ADOPTION DATE. It must NOT fall back to today: the reconstruction runs\n      TODAY while your tree carries your adoption date, so an unpinned stamp fabricates a conflict in\n      CLAUDE.md + ADR-000-stack.md — files nobody touched."
filled "$STACK"   || miss="$miss\n  - **Stack profile** (§2) — the profile drives the emitted CI, the scaffold, and the export prune."
filled "$BACKLOG" || miss="$miss\n  - **Backlog backend** (§6) — it decides which tracker doc incept wrote."
filled "$MODE"    || miss="$miss\n  - **Process mode** (§ ceremony) — lean vs enterprise scaffolds different governance docs."
filled "$TEAM"    || miss="$miss\n  - **Governance** (§ solo/team)."
filled "$HARNESS" || miss="$miss\n  - **Target harness(es)** (§harness-neutrality)."
if [ -n "$miss" ]; then
  echo "kit-update: CLAUDE.md is missing inception stamps needed to reconstruct the base:" >&2
  # shellcheck disable=SC2059  # $miss is our own assembled message, not user input
  printf "$miss\n" >&2
  echo "  REFUSING to guess. A wrong base silently produces a wrong delta — worse than no delta, because" >&2
  echo "  you would trust it. Restore the stamps in CLAUDE.md §3 (they are what incept wrote) and re-run." >&2
  exit 1
fi

# ── THE CI PLATFORM + THE DB ARCHETYPE: read the FACT; infer only as an announced LEGACY fallback ──────
# These are the last two inception inputs incept learned to stamp (T3b). Where the stamp is present it is
# the SOURCE OF TRUTH and nothing is derived: a stamp is what the operator actually chose, evidence is only
# what the tree looks like today — and the tree can be edited.
#
# The fallback below exists for exactly one population: adopters incepted BEFORE the stamps existed. For
# them there IS no record, so evidence is all there is. It is INFERENCE and it is ANNOUNCED as inference —
# never presented as a fact, never silent. (And it can be wrong: see the CI note.) When it cannot decide,
# it REFUSES; it never defaults.
INFERRED=''

if filled "$CIP"; then
  case "$CIP" in
    github|gitlab) CI=$CIP ;;
    *) die "CLAUDE.md §3 stamps an unknown **CI platform**: '$CIP' (incept wires one of: github, gitlab). Refusing to guess which pipeline this project was incepted with." ;;
  esac
else
  # LEGACY INFERENCE — pre-stamp tree. incept writes .github/workflows/ci.yml under --ci github and
  # .gitlab-ci.yml under --ci gitlab. But the EXPORT ships .github/workflows/ EMPTY (ci.yml is export-ignored,
  # P0-FU) — so a github-workflow FILE is not positive evidence either way, and .gitlab-ci.yml
  # (which ONLY incept --ci gitlab creates) must be tested FIRST. This is precisely why the stamp exists.
  if git -C "$REPO" cat-file -e "HEAD:.gitlab-ci.yml" 2>/dev/null; then
    CI=gitlab
  elif git -C "$REPO" cat-file -e "HEAD:.github/workflows/ci.yml" 2>/dev/null; then
    CI=github
  else
    echo "kit-update: cannot determine the CI platform this project was incepted with." >&2
    echo "  CLAUDE.md §3 has no **CI platform** stamp (this project predates it), and neither" >&2
    echo "  .gitlab-ci.yml nor .github/workflows/ci.yml is in HEAD — so there is neither a record nor" >&2
    echo "  evidence. Guessing would wire the wrong pipeline into the base and every CI file would read" >&2
    echo "  as a conflict. Add '- **CI platform** (§14): github' (or gitlab) to CLAUDE.md §3 and re-run." >&2
    exit 1
  fi
  if [ "$CI" = gitlab ]; then _why='.gitlab-ci.yml is in HEAD (only --ci gitlab creates it)'
  else _why='no .gitlab-ci.yml, and a GitHub workflow is in HEAD'; fi
  INFERRED="${INFERRED}    ci=$CI  <- INFERRED ($_why), NOT recorded
"
fi

if filled "$DBA"; then
  case "$DBA" in
    db-backed) DB_FLAG='' ;;
    no-db)     DB_FLAG='--no-db' ;;
    *) die "CLAUDE.md §3 stamps an unknown **DB archetype**: '$DBA' (incept records one of: db-backed, no-db). Refusing to guess." ;;
  esac
else
  # LEGACY INFERENCE — pre-stamp tree. incept --no-db REMOVES the scaffold's .db-backed marker. So: the
  # profile SHIPPED a marker (evidence: it is in kit-base) but the adopter's HEAD has none => they ran
  # --no-db. HONEST LIMIT: it cannot distinguish "--no-db at inception" from "the adopter deleted the
  # marker later", and for a profile that never shipped a marker it can see --no-db at all. Inference.
  DB_FLAG=''
  if git -C "$REPO" cat-file -e "kit-base:profiles/${STACK}/scaffold/.db-backed" 2>/dev/null \
     && ! git -C "$REPO" cat-file -e "HEAD:.db-backed" 2>/dev/null; then
    DB_FLAG='--no-db'
  fi
  if [ -n "$DB_FLAG" ]; then _dbw=no-db; else _dbw=db-backed; fi
  INFERRED="${INFERRED}    db=$_dbw  <- INFERRED from the .db-backed marker, NOT recorded
"
fi

if [ -n "$INFERRED" ]; then
  echo "kit-update: NOTE — this project was incepted before CLAUDE.md §3 stamped every inception input." >&2
  echo "  The values below were INFERRED from evidence in the tree. They are not facts, they are the best" >&2
  echo "  reading of what the tree looks like TODAY — and the tree can have been edited since inception:" >&2
  printf '%s' "$INFERRED" >&2
  echo "  If either is wrong, the base is wrong, and kit files nobody touched will read as CONFLICTS." >&2
  echo "  Record them once and this note goes away — add them to CLAUDE.md §3 (they are what incept now" >&2
  echo "  writes): '- **CI platform** (§14): <github|gitlab>' and '- **DB archetype** (§ archetype): <db-backed|no-db>'." >&2
fi

stamps_line() {
  echo "    name='$NAME' owner='$OWNER' stack=$STACK team=$TEAM backlog=$BACKLOG ci=$CI mode=$MODE harness=$HARNESS date=$DATE${DB_FLAG:+ $DB_FLAG}"
}

# run_incept <dir> <whose-incept-is-this> — re-run the incept THAT DIR SHIPS, with the recorded stamps.
# BOTH sides go through this ONE function: that is what makes the transformation cancel. The date is
# PINNED (the flag exists for exactly this call). An empty stamp is passed through empty and incept exits
# 2 — a loud refusal, not a silent "today". We do not work around that.
#
# $MODE is READ AND PASSED THROUGH, never branched on: kit-update does not know or care what the process
# mode means — it reproduces the inception the adopter actually performed. (conformance/mode-enforcement-
# blind.sh asserts no script conditions on it.)
run_incept() {  # <dir> <label>
  _d=$1; _lbl=$2
  set -- --noninteractive --name "$NAME" --intent-owner "$OWNER" --stack "$STACK" \
         --team "$TEAM" --backlog "$BACKLOG" --ci "$CI" --harness "$HARNESS" --mode "$MODE" \
         --date "$DATE"
  [ -n "$DB_FLAG" ] && set -- "$@" "$DB_FLAG"
  filled "$FLUENCY" && set -- "$@" --operator-fluency "$(printf '%s' "$FLUENCY" | tr '[:upper:]' '[:lower:]')"
  _log=$(mktemp) || die "mktemp failed"
  if ! ( cd "$_d" && sh scripts/incept.sh "$@" ) >"$_log" 2>&1; then
    echo "kit-update: re-running ${_lbl}'s own incept FAILED:" >&2
    sed 's/^/    /' "$_log" >&2 || :
    rm -f "$_log"
    die "$_lbl could not be built. Without all three sides there is no merge — no delta will be computed."
  fi
  rm -f "$_log"
}

# build_base <dir> — MATERIALIZE kit-base and RE-RUN ITS OWN incept.
# `git archive` (read-only) — never `git worktree add`/`checkout`, which would write refs and admin files
# into the adopter's repo.
build_base() {
  git -C "$REPO" archive kit-base | tar -x -C "$1" \
    || die "could not materialize the kit-base tree into '$1'"
  run_incept "$1" 'kit-base'
}

# adopter_manifest — the FILE SET the adopter ACTUALLY received, as the exporter recorded it at export
# time. This is the AUTHORITY on THEIRS's shape, and it is why we do not GUESS. `adopter-export --profile`
# is OPTIONAL: a single-stack adopter prunes to one profile, but a multi-stack org (the kit's stated
# consumer) legitimately keeps ALL ten. The manifest is vendored inside kit-base (P1.2-pre-a), so the fact
# is recorded — read it. Falls back to the working-tree .kit-manifest only if kit-base carries none (an
# older base); REFUSES if neither exists, because a guessed shape produces spurious DELETIONS of files the
# adopter never touched — data loss with a progress bar, the exact failure this tool exists to prevent.
adopter_manifest() {
  if git -C "$REPO" show kit-base:.kit-manifest 2>/dev/null; then return 0; fi
  if [ -f "$REPO/.kit-manifest" ]; then cat "$REPO/.kit-manifest"; return 0; fi
  return 1
}

# ══ JOB 1 — --reconstruct-base: just BASE, for inspection and for conformance/kit-update-identity.sh ══
if [ -n "$OUT" ]; then
  # The output dir must be empty AND outside any git repo: incept's CP-4 ownership gate refuses to run
  # nested (rightly), and a dir inside the adopter's tree would be a mutation.
  if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
    die "--reconstruct-base '$OUT' exists and is not empty — refusing to clobber."
  fi
  mkdir -p "$OUT" || die "could not create '$OUT'"
  OUT=$( CDPATH='' cd "$OUT" && pwd -P )
  case "$OUT/" in
    "$REPO"/*) die "--reconstruct-base '$OUT' is INSIDE the adopter repo. The reconstruction must never be written into your tree — choose a path outside it." ;;
  esac
  if _owner=$( CDPATH='' cd "$OUT" && git rev-parse --show-toplevel 2>/dev/null ); then
    [ -n "$_owner" ] && die "--reconstruct-base '$OUT' is inside the git repo at '$_owner'. incept refuses to run nested (it would install its hook into that repo). Choose a path outside any repo."
  fi
  build_base "$OUT"
  echo "reconstructed BASE at: $OUT"
  if [ -n "$INFERRED" ]; then
    echo "  incept_old(kit-base) with the stamps this project recorded — EXCEPT the inferred value(s) noted above:"
  else
    echo "  incept_old(kit-base) with the stamps this project recorded (every input is a FACT, nothing inferred):"
  fi
  stamps_line
  echo "  For an unmodified adopter this tree is IDENTICAL to HEAD — that identity is the proof the"
  echo "  reconstruction is right (conformance/kit-update-identity.sh). Your repo was not touched."
  exit 0
fi

# ══ JOB 2 — --from: THE UPDATE. BASE + OURS + THEIRS, a 3-way merge, and a report. ═══════════════════

TMP=$(mktemp -d) || die "mktemp failed"
# shellcheck disable=SC2064  # expand TMP now: at trap time it is exactly this run's dir
trap "rm -rf '$TMP' 2>/dev/null || true" EXIT INT TERM

# ── THE WARNING BEFORE THE ACT — `--from` is untrusted input and we are about to EXECUTE code from it ──
# Not a footnote at the bottom of a report they have already acted on: it is printed BEFORE the clone,
# naming the source, while they can still stop.
echo "kit-update: --from '$FROM'"
echo "  ! THIS EXECUTES CODE FROM THAT SOURCE. Building THEIRS means running the new release's OWN"
echo "    scripts/adopter-export.sh and scripts/incept.sh — that is the whole design (re-running the real"
echo "    scripts is what makes incept's transformation cancel), and it is also what adoption always was:"
echo "    running a kit's incept.sh. But point this ONLY at a source you trust as much as your own repo."
echo ""

git clone --quiet --no-tags "$FROM" "$TMP/new" >/dev/null 2>&1 \
  || die "could not clone --from '$FROM'. It must be a git repository (a URL or a local path) with a committed HEAD: THEIRS is built by running THAT release's own adopter-export.sh, which archives HEAD."
[ -f "$TMP/new/scripts/adopter-export.sh" ] && [ -f "$TMP/new/scripts/incept.sh" ] \
  || die "'$FROM' has no scripts/adopter-export.sh + scripts/incept.sh — it is not a Sparkwright kit. Refusing to diff your project against something that is not the kit it was adopted from."

NEWVER=$(cat "$TMP/new/VERSION" 2>/dev/null || echo unknown)
BASEVER=$(git -C "$REPO" show kit-base:VERSION 2>/dev/null || echo unknown)

# ── THE THREE SIDES ───────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/base"
build_base "$TMP/base"

# THEIRS — the NEW RELEASE'S OWN exporter + incept, with the SAME stamps and the SAME pinned date as BASE.
# Never a re-implementation of either. The ONE thing we must not guess is the SHAPE. THEIRS must be pruned
# to the SAME shape the adopter actually received — which their .kit-manifest RECORDS — NOT blindly to
# $STACK. Guessing "pruned to $STACK" hands a multi-stack adopter, who legitimately kept every profile, a
# patch DELETING all the profiles they kept: an unchanged un-pruned adopter would be offered ~143 spurious
# deletions and `git apply --check` would pass. So read the fact and match it.
MANIFEST=$(adopter_manifest) || MANIFEST=''
[ -n "$MANIFEST" ] || die "cannot read this project's .kit-manifest (neither 'kit-base:.kit-manifest' nor a working-tree .kit-manifest). It is the RECORD of which files — and which profiles — this project received, and thus the authority on the shape THEIRS must be pruned to. Without it the shape can only be GUESSED, and a wrong shape emits deletions of files nobody touched. Recover kit-base (it vendors the manifest) or restore .kit-manifest."
# The prunable unit is a profile DIRECTORY (profiles/<name>/...). incept does not rename profiles/, so a
# manifest path is the adopter's actual profile path. If the manifest lists ANY profile DIR beyond the
# adopter's own stack, they kept it (an un-pruned / multi-stack adopter) -> export THEIRS with NO --profile
# so it carries every profile they kept. Otherwise they pruned to one profile -> reproduce that exactly.
# (profiles/*.md docs and non-profile _TEMPLATE paths are NOT dirs, so they never confuse this.)
KEPT_OTHER=$(printf '%s\n' "$MANIFEST" | sed -n 's#^profiles/\([^/]*\)/.*#\1#p' \
  | LC_ALL=C sort -u | grep -vxF "$STACK" | grep -c . || :)
if [ "${KEPT_OTHER:-0}" -gt 0 ]; then
  THEIRS_SHAPE="un-pruned (adopter-export, no --profile) — .kit-manifest records $KEPT_OTHER profile dir(s) beyond '$STACK', so this adopter kept them"
  sh "$TMP/new/scripts/adopter-export.sh" "$TMP/theirs" >"$TMP/exp.log" 2>&1 \
    || { sed 's/^/    /' "$TMP/exp.log" >&2 || :; die "the new release's own adopter-export.sh failed (un-pruned, matching this adopter's manifest shape)."; }
else
  THEIRS_SHAPE="pruned to '$STACK' (adopter-export --profile $STACK) — .kit-manifest records only that profile"
  sh "$TMP/new/scripts/adopter-export.sh" "$TMP/theirs" --profile "$STACK" >"$TMP/exp.log" 2>&1 \
    || { sed 's/^/    /' "$TMP/exp.log" >&2 || :; die "the new release's own adopter-export.sh failed (stack '$STACK'). If that release dropped this profile, there is no honest THEIRS to build."; }
fi
run_incept "$TMP/theirs" 'the new release'

# ── THE WORKBENCH — a THROWAWAY repo. Every object we create lands HERE, never in the adopter's repo. ─
# OURS is FETCHED (read-only on their side), so it is their EXACT HEAD tree — not a re-hash. BASE and
# THEIRS are directories, so they are hashed by the same route the identity proof uses (git init + add -A
# in the dir itself, so the same .gitignore applies), then fetched in.
W="$TMP/w"
git -c init.defaultBranch=main init -q "$W" >/dev/null 2>&1 || die "could not create the temp workbench"

fetch_commit() {  # <src-repo-or-dir> -> commit oid in the workbench
  git -C "$W" fetch --no-tags -q "$1" HEAD >/dev/null 2>&1 || return 1
  git -C "$W" rev-parse FETCH_HEAD
}
commit_dir() {  # <dir> -> commit oid in the workbench (the dir is git-init'd IN PLACE; it is our temp dir)
  ( cd "$1" && git -c init.defaultBranch=main init -q . && git add -A \
      && git -c user.email=kit-update@local -c user.name=kit-update commit -qm snapshot ) >/dev/null 2>&1 \
    || return 1
  fetch_commit "$1"
}

C_BASE=$(commit_dir "$TMP/base")   || die "could not snapshot the reconstructed BASE"
C_THEIRS=$(commit_dir "$TMP/theirs") || die "could not snapshot THEIRS"
C_OURS=$(fetch_commit "$REPO")     || die "could not read your HEAD (read-only) into the workbench"

# ── NON-VACUITY, ENFORCED IN THE TOOL ITSELF ──────────────────────────────────────────────────────────
# An updater that computed NOTHING reports "0 changes" — which reads exactly like a happy no-op. So an
# empty side is a HARD FAILURE here, and the three counts are PRINTED: a run that built nothing cannot
# show its work.
n_entries() { git -C "$W" ls-tree -r --name-only "$1" | grep -c . || :; }
N_BASE=$(n_entries "$C_BASE"); N_OURS=$(n_entries "$C_OURS"); N_THEIRS=$(n_entries "$C_THEIRS")
for _pair in "BASE:$N_BASE" "OURS:$N_OURS" "THEIRS:$N_THEIRS"; do
  case "$_pair" in
    *:0|*:) die "the ${_pair%%:*} tree came out EMPTY. That is a broken computation, not an empty update — and it would have printed as '0 changes', which you would have believed. Refusing." ;;
  esac
done

# ── THE MERGE — TWO implementations behind ONE contract ───────────────────────────────────────────────
# The CONTRACT (all either implementation owes the rest of this script):
#   in:  <base> <ours> <theirs> commits, in the throwaway workbench $W
#   out: $MERGED_TREE = the merged TREE oid   ·   $TMP/conflicts = the paths git could not auto-merge
#   and, above all: NOTHING of the adopter's is written. Ever. By either path.
#
# Why two: `git merge-tree --write-tree` is the RIGHT tool — it computes the merged tree in the object
# store with NO worktree and NO checkout, so the adopter's tree cannot be touched even by accident. But it
# landed in git 2.38 (2022-10-02), and Ubuntu 20.04 still ships git 2.25. scripts/preflight.sh WARNS those
# adopters and PROMISES them "the temporary-worktree fallback", "still non-mutating". merge3_worktree() is
# that promise, kept: a real, complete second implementation, on plumbing every git has had for a decade.
wgit() { git -C "$W" -c user.email=kit-update@local -c user.name=kit-update "$@"; }

# IMPLEMENTATION 1 — merge-tree (preferred). rc 0 = clean, 1 = conflicts, >1 = error. stdout: line 1 = the
# merged tree oid; then (with --name-only) the conflicted paths, a blank line, then messages.
merge3_merge_tree() {  # <base> <ours> <theirs>
  _rc=0   # RESET, deliberately: merge3() may call this and then the fallback, and a stale _rc from a
          # previous call would be read as this call's result.
  _mt=$(git -C "$W" merge-tree --write-tree --name-only --merge-base="$1" "$2" "$3") || _rc=$?
  [ "$_rc" -le 1 ] || { echo "$_mt" | sed 's/^/    /' >&2; return 1; }
  MERGED_TREE=$(echo "$_mt" | sed -n '1p')
  echo "$_mt" | sed -n '2,/^$/p' | grep -v '^$' > "$TMP/conflicts" || :
  [ -n "$MERGED_TREE" ]
}

# IMPLEMENTATION 2 — the git<2.38 fallback: the SAME 3-way, performed by plain `git merge` in a TEMPORARY
# worktree of the THROWAWAY WORKBENCH. Read that twice: the worktree it checks out and the merge commit it
# writes are the WORKBENCH's ($TMP, deleted on exit) — never the adopter's. The adopter's repo is not even
# reachable from here: $W was populated by a read-only `git fetch` long before this runs. That is what
# makes "the fallback is still non-mutating" TRUE and not just reassuring.
#
# THE GRAFT — the one thing that is not obvious. BASE, OURS and THEIRS were fetched from three UNRELATED
# repos, so they share NO history: a plain `git merge` of them does not do the wrong 3-way, it refuses
# outright ("fatal: refusing to merge unrelated histories"). So we give OURS and THEIRS a COMMON PARENT
# whose tree IS BASE. Then git's own merge-base computation lands on exactly the base we mean, and the
# merge it performs IS the 3-way we asked for — same three trees, same three-way, no invention. (We do NOT
# reach for --allow-unrelated-histories: that would merge with an EMPTY base and report every kit file as
# a conflict — a wrong answer, delivered confidently.)
merge3_worktree() {  # <base> <ours> <theirs>
  _tb=$(wgit rev-parse "$1^{tree}")   || return 1
  _to=$(wgit rev-parse "$2^{tree}")   || return 1
  _tt=$(wgit rev-parse "$3^{tree}")   || return 1
  _gb=$(wgit commit-tree "$_tb" -m 'kit-update: BASE (graft)')       || return 1
  _go=$(wgit commit-tree "$_to" -p "$_gb" -m 'kit-update: OURS')     || return 1
  _gt=$(wgit commit-tree "$_tt" -p "$_gb" -m 'kit-update: THEIRS')   || return 1

  # Give the workbench a BORN HEAD and make the grafts REACHABLE before checking anything out. Both are
  # belt-and-braces for the platform this fallback exists for and that CI cannot run (git 2.25): a repo
  # whose HEAD is unborn is the kind of edge an old `git worktree add` can refuse, and dangling
  # commit-tree objects are exactly what a stray `gc --auto` is entitled to prune. One ref costs nothing
  # and removes both questions. (The ref is the WORKBENCH's, in $TMP — not the adopter's.)
  wgit update-ref refs/heads/main "$_go" || return 1

  _wd="$TMP/mergewt"
  wgit worktree add --detach "$_wd" "$_go" >"$TMP/wt.log" 2>&1 \
    || { sed 's/^/    /' "$TMP/wt.log" >&2 || :; return 1; }

  _rc=0
  git -C "$_wd" -c user.email=kit-update@local -c user.name=kit-update \
      merge --no-edit "$_gt" >"$TMP/merge.log" 2>&1 || _rc=$?
  [ "$_rc" -le 1 ] || { sed 's/^/    /' "$TMP/merge.log" >&2 || :; return 1; }

  if [ "$_rc" -eq 1 ]; then
    # CONFLICTS. The unmerged index stages name them; the worktree files carry the markers. `git add -A`
    # then stages exactly that content, so `write-tree` yields a tree with the conflict markers IN it —
    # which is what merge-tree --write-tree produces too, and what the contract above promises.
    git -C "$_wd" -c core.quotepath=false ls-files -u | cut -f2- | LC_ALL=C sort -u > "$TMP/conflicts"
    # rc 1 with NO unmerged path is not a conflict — it is `git merge` failing for some other reason. Do
    # not read it as "merged cleanly, no conflicts": that would be a fabricated clean answer.
    [ -s "$TMP/conflicts" ] || { sed 's/^/    /' "$TMP/merge.log" >&2 || :; return 1; }
    git -C "$_wd" add -A >/dev/null 2>&1 || return 1
    MERGED_TREE=$(git -C "$_wd" write-tree) || return 1
  else
    : > "$TMP/conflicts"
    MERGED_TREE=$(git -C "$_wd" rev-parse 'HEAD^{tree}') || return 1
  fi
  [ -n "$MERGED_TREE" ]
}

# THE PROBE — a CAPABILITY probe, never a version-string parse. preflight reports a git VERSION because a
# version is all it can see at prereq time, and its own honest ceiling says so: a backport, a distro patch,
# a wrapper or a stripped build can make version and capability disagree in BOTH directions. Here we can do
# better than a version, so we must: RUN the exact subcommand with the exact flags, on a case that is
# trivially clean (merge BASE into BASE with BASE as the base), and require a usable tree oid back. If any
# part of that is unavailable — old git, no --write-tree, no --merge-base, a wrapper that swallows it — the
# probe fails and the fallback runs. We never conclude "this git can do it" from a number.
probe_merge_tree() {  # <a commit that exists in the workbench>
  _pout=$(git -C "$W" merge-tree --write-tree --name-only --merge-base="$1" "$1" "$1" 2>/dev/null) || return 1
  _poid=$(echo "$_pout" | sed -n '1p')
  [ -n "$_poid" ] || return 1
  git -C "$W" rev-parse --verify --quiet "$_poid^{tree}" >/dev/null 2>&1
}

# THE SELECTION — and it is EMITTED (see the report): an adopter who was promised a fallback must be able
# to SEE which path actually ran. A silent selection is unfalsifiable.
MERGE_IMPL=''; MERGE_WHY=''
merge3() {  # <base> <ours> <theirs>
  case "$MERGE_MODE" in
    worktree)
      MERGE_IMPL=worktree-fallback; MERGE_WHY='forced by --merge-impl worktree'
      merge3_worktree "$@"; return $? ;;
    merge-tree)
      MERGE_IMPL=merge-tree; MERGE_WHY='forced by --merge-impl merge-tree'
      merge3_merge_tree "$@"; return $? ;;
  esac
  # auto: PROBE, then fall back ON FAILURE — including a failure AFTER a successful probe. The fallback is
  # a complete implementation, not a degraded one, so an answer computed the other way beats no answer.
  if probe_merge_tree "$1"; then
    MERGE_IMPL=merge-tree; MERGE_WHY="probed: this git CAN do 'git merge-tree --write-tree'"
    merge3_merge_tree "$@" && return 0
    echo "kit-update: 'git merge-tree --write-tree' probed OK but FAILED on the real merge — falling back" >&2
    echo "  to the temporary-worktree implementation (the same 3-way, also non-mutating)." >&2
    MERGE_WHY="probed OK but FAILED on the real merge — fell back"
  else
    MERGE_WHY="probed: this git CANNOT do 'git merge-tree --write-tree' (it landed in git 2.38)"
  fi
  MERGE_IMPL=worktree-fallback
  merge3_worktree "$@"
}

: > "$TMP/conflicts"
merge3 "$C_BASE" "$C_OURS" "$C_THEIRS" \
  || die "the 3-way merge itself failed ($MERGE_IMPL). No delta is reported: a partial answer here would be worse than none."

# NON-VACUITY, ON THE MERGE ITSELF. Everything downstream (offered/CONFLICT/untouched) is derived from the
# BASE/OURS/THEIRS diffs — so a merge that silently produced NOTHING would still print a complete, plausible
# report, and the merge would be decoration. It is not allowed to be: the merged tree must EXIST, resolve,
# and be non-empty, and its size + the count of paths git could not auto-merge are PRINTED. A merge that
# never happened cannot show them.
git -C "$W" rev-parse --verify --quiet "$MERGED_TREE^{tree}" >/dev/null 2>&1 \
  || die "the $MERGE_IMPL merge returned '$MERGED_TREE', which is not a tree. Refusing to print a report whose merge did not happen."
N_MERGED=$(git -C "$W" ls-tree -r --name-only "$MERGED_TREE" | grep -c . || :)
[ "${N_MERGED:-0}" -gt 0 ] \
  || die "the $MERGE_IMPL merge produced an EMPTY tree. That is a broken computation, not a clean merge."
N_TCONF=$(grep -c . < "$TMP/conflicts" || :)

case "$MERGE_IMPL" in
  merge-tree) MERGE_DESC="'git merge-tree --write-tree' — the merged tree is computed in the object store, with NO checkout anywhere (git >= 2.38)" ;;
  *)          MERGE_DESC="plain 'git merge' in a TEMPORARY worktree of the throwaway workbench (works on ANY git — the fallback for git < 2.38). Still nothing of YOURS is touched: that worktree is the workbench's, not your repo's" ;;
esac

# ── THE THREE CATEGORIES ──────────────────────────────────────────────────────────────────────────────
# upstream = what the kit changed;  mine = what I changed.  Both are computed against the SAME BASE, in
# ADOPTER COORDINATES, which is the whole point of the reconstruction.
git -C "$W" diff --name-only "$C_BASE" "$C_THEIRS" | LC_ALL=C sort > "$TMP/upstream"
git -C "$W" diff --name-only "$C_BASE" "$C_OURS"   | LC_ALL=C sort > "$TMP/mine"
LC_ALL=C sort "$TMP/conflicts" -o "$TMP/conflicts"

# CONFLICT = changed on BOTH sides. Deliberately WIDER than git's own conflict list (which is a subset:
# git will happily auto-merge two edits to different hunks of the same file). We do NOT silently resolve
# the adopter's edit away — a file they touched and the kit touched is THEIRS TO DECIDE, always.
comm -12 "$TMP/upstream" "$TMP/mine" > "$TMP/both"
LC_ALL=C sort -u "$TMP/both" "$TMP/conflicts" > "$TMP/conflict"
# offered   = upstream-only  (they never touched it -> it applies cleanly)
comm -23 "$TMP/upstream" "$TMP/conflict" > "$TMP/offered"
# untouched = mine-only      (NAMED, so silence is never mistaken for a promise)
comm -13 "$TMP/upstream" "$TMP/mine" > "$TMP/untouched"

n() { grep -c . < "$1" || :; }
N_OFF=$(n "$TMP/offered"); N_CON=$(n "$TMP/conflict"); N_UNT=$(n "$TMP/untouched")

# ── THE PATCH — at a SCRATCH path, outside the repo. They apply it, with their own tools. ─────────────
PATCH=''
if [ "$N_OFF" -gt 0 ]; then
  _pd=$(mktemp -d) || die "mktemp failed"
  PATCH="$_pd/kit-update-v${NEWVER}.patch"
  # On the offered paths OURS == BASE by construction, so BASE->THEIRS is exactly OURS->THEIRS there:
  # the patch applies to their working tree as-is, and it carries NOTHING that is in conflict.
  # `git diff` has no --pathspec-from-file, so the pathspec is built one line at a time — never by word-
  # splitting a variable, which would corrupt any path containing a space.
  diff_offered() {
    set -- --binary "$C_BASE" "$C_THEIRS" --
    while IFS= read -r _path; do
      [ -n "$_path" ] && set -- "$@" ":(literal)$_path"
    done < "$TMP/offered"
    git -C "$W" diff "$@"
  }
  diff_offered > "$PATCH" || die "could not write the patch"
fi

# ── THE REPORT ────────────────────────────────────────────────────────────────────────────────────────
echo "kit-update: v$BASEVER (adopted)  ->  v$NEWVER (--from)"
echo "computed: BASE=$N_BASE files, OURS=$N_OURS files, THEIRS=$N_THEIRS files"
echo "  BASE   = incept_old(kit-base), rebuilt with your recorded stamps"
stamps_line
echo "  OURS   = your HEAD, read-only"
echo "  THEIRS = incept_new(adopter-export(--from)) — that release's OWN scripts, same stamps, same pinned date"
echo "           shape: $THEIRS_SHAPE"
# WHICH MERGE RAN — said out loud. There are two implementations and the choice is made for you, at run
# time, by a capability probe; you get to see which one answered, and what it actually produced.
echo "merge: $MERGE_IMPL — $MERGE_DESC"
echo "  tree=$MERGED_TREE files=$N_MERGED textual-conflicts=$N_TCONF  (selected: $MERGE_WHY)"
echo ""

if [ "$C_BASE" = "$C_THEIRS" ] || git -C "$W" diff --quiet "$C_BASE" "$C_THEIRS"; then
  echo "no changes: the release at --from is identical to the one you adopted, in your coordinates."
  echo "  (BASE and THEIRS are the same $N_THEIRS-file tree — nothing to offer. This is a real no-op, not"
  echo "   an empty computation: all three trees were built, and their sizes are printed above.)"
  echo ""
fi

sect() {  # <key> <count> <caption>
  echo "== $1 ($2) — $3 =="
  [ "$2" -gt 0 ] && sed 's/^/  - /' "$TMP/$4"
  echo ""
}
sect offered   "$N_OFF" "kit changes that apply cleanly — you have not touched these files" offered
sect CONFLICT  "$N_CON" "changed BOTH upstream and by you — yours to decide, NEVER resolved silently" conflict
sect untouched "$N_UNT" "yours; this update proposes nothing for them" untouched

if [ -n "$PATCH" ]; then
  echo "patch: $PATCH"
  echo "  the OFFERED changes only. Review it, then apply it with your own tools:  git apply '$PATCH'"
else
  echo "patch: (none — nothing is offered)"
fi
echo ""

# ── THE HONEST CEILING — printed, every run, in the tool's own output ────────────────────────────────
echo "HONEST CEILING — what this tool does NOT do:"
echo "  * LATEST ONLY. --from carries whatever that source's HEAD is; the public mirror carries only the"
echo "    current release. This cannot move you to an intermediate version."
echo "  * IT PRESENTS, IT DOES NOT APPLY. Nothing above was written to your repo — not one byte. Every"
echo "    hunk is your decision, and the patch is a suggestion at a scratch path."
echo "  * IT REQUIRES AN INTACT kit-base. The whole delta is computed against incept_old(kit-base). Lose"
echo "    that branch and there is no honest base — and a wrong base is worse than none."
echo "  * --from IS UNTRUSTED INPUT AND THIS TOOL EXECUTES CODE FROM IT (that release's own"
echo "    adopter-export.sh and incept.sh, above). Point it only at a source you trust."
echo "  * A CONFLICT is not a defect — it is the tool refusing to overwrite you. Nothing above was merged"
echo "    into your files; the merge was computed in a throwaway repo and read back."
echo "  * TWO MERGE ENGINES, AND THEY ARE NOT BYTE-IDENTICAL. Which one ran is printed above. They agree"
echo "    on the ANSWER you act on — which files are offered, which conflict, which are yours — and that"
echo "    is asserted in conformance. They can differ INSIDE a conflicted file: the two label conflict"
echo "    hunks differently ('<<<<<<< <commit-oid>' vs '<<<<<<< HEAD'), and on exotic histories (rename"
echo "    detection, directory/file collisions) merge-ort and merge-recursive can resolve differently."
echo "    Neither writes to your repo, and neither of them applies anything."
echo "  * EXPECT CLAUDE.md. incept STAMPS the kit version into your project doc, so a version bump changes"
echo "    it on the kit's side EVERY release: offered while you have not touched it, a CONFLICT the moment"
echo "    you have. That is the design working (it is YOUR doc), not a fault — usually you want only the"
echo "    '**Kit version adopted:**' line."
