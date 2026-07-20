#!/bin/sh
# incept.sh — Inception bootstrap (DEVELOPMENT-PROCESS.md §3 / START-HERE.md).
# Transforms a freshly-cloned Sparkwright kit into a configured, Inception-complete
# project, in place. Interactive by default; --noninteractive for automation/CI.
#
#   sh scripts/incept.sh [--name N] [--intent-owner O] [--stack S] [--team solo|team] \
#                        [--backlog md|github|jira|ado|linear|gitlab] \
#                        [--ci github|gitlab] [--harness claude-code[,generic,...]] \
#                        [--operator-fluency novice|adjacent|practitioner] \
#                        [--mode lean|enterprise] [--date YYYY-MM-DD] [--noninteractive]
#
# --date pins the stamped **Created:** date (default: today). Reproducible-reconstruction seam for
# `kit-update`: re-running incept over the vendored kit-base must reproduce the adopter's ADOPTION
# date, not today's, or the diff shows a phantom conflict in files nobody touched.
#
# It frees the root Claude-Code memory slot (CLAUDE.md = kit principles) by renaming the
# principles doc to ENGINEERING-PRINCIPLES.md and rewriting the principles-sense references,
# then stamps the PROJECT's CLAUDE.md/RUNBOOK.md/BACKLOG.md/ADR-000 and wires the profile CI.
# What it changes: Rewrites the cloned kit IN PLACE — renames CLAUDE.md -> ENGINEERING-PRINCIPLES.md, stamps the project CLAUDE.md/RUNBOOK.md/BACKLOG.md/ADR-000, wires the profile CI, and (non-DB) strips the kit:db-backed CI region + .db-backed marker.
# Guardrails: Run on a fresh clone; interactive by default (--noninteractive for CI); the DB-region strip refuses an open-ended range (both markers required) so it can never wipe gates to EOF.
set -eu

# --- DB-archetype curation (KW3) — defined FIRST so the internal `__db-curate` seam needs none of the
#     inception preamble (adapters registry, preflight, safety guards). The ts-node profile ships the
#     `kit:db-backed` CI region (Postgres service + DATABASE_URL) + a scaffold/.db-backed marker ACTIVE
#     because its default reference archetype is DB-backed. A NON-DB archetype (--no-db) strips both so
#     first-run-green stays honest — no idle database service, and the detector marks db-postgres N/A. ---
strip_db_region() {  # FILE — delete the `# >>> kit:db-backed` … `# <<< kit:db-backed` region in-place; no-op if absent
  [ -f "$1" ] || return 0
  # GUARD (Security-Medium): a `sed '/start/,/end/d'` range with NO closing match deletes to EOF — which
  # would silently wipe EVERY gate below the region (sast/secret/agent-trace/provenance), leaving a
  # gateless-but-green CI. Only strip when BOTH markers are present; otherwise no-op, loudly.
  grep -q '# >>> kit:db-backed' "$1" || return 0   # no opening marker — nothing to strip
  grep -q '# <<< kit:db-backed' "$1" || { echo "warn: kit:db-backed closing marker missing in $1 — leaving CI untouched (refusing an open-ended range that would wipe gates to EOF)" >&2; return 0; }
  sed '/# >>> kit:db-backed/,/# <<< kit:db-backed/d' "$1" > "$1.kwtmp" && mv "$1.kwtmp" "$1"
}
curate_db_backed() {  # MODE(1|0) — 0=non-DB: strip the CI region(s) + marker + DB env lines + the DR drill; 1=DB-backed: keep
  [ "${1:-1}" = 0 ] || return 0
  strip_db_region .github/workflows/ci.yml
  strip_db_region .gitlab-ci.yml
  rm -f .db-backed
  # CP-3: a non-DB archetype must not LOOK like a data project. Two leftovers made a stateless CLI
  # fail conformance/dr-ready.sh with "data project has no BIA / no RUNBOOK DR section":
  #   1. .env.example still carried the COMMENTED `# DATABASE_URL=` / `# REDIS_URL=` backing-service
  #      lines, and has_data_surface() (dr-ready.sh:30) greps .env.example UNANCHORED — so the
  #      comment ALONE raised the obligation.
  #   2. the profile scaffold's scripts/dr-drill.sh was copied into a project with no database.
  # We remove the false SIGNAL, never the detector: has_data_surface is conservative BY DESIGN
  # ("a MISS escalates, never exempts"), and anchoring its grep to uncommented assignments would let
  # a real DB project with a commented DATABASE_URL escape DR entirely — a fail-open.
  if [ -f .env.example ]; then
    sed '/^# Backing services/d; /^# DATABASE_URL=/d; /^# REDIS_URL=/d' .env.example > .env.example.kwtmp \
      && mv .env.example.kwtmp .env.example
    # I1 (K12 sibling): the three stripped lines are .env.example's EOF, sitting below a blank
    # separator — deleting them orphans that blank as the new EOF (`git diff --check`: "new blank
    # line at EOF"), so the adopter's first `git add -A` import is dirty. Re-emit only through the
    # last non-blank line (the same idiom adopter-export.sh uses for the CLAUDE.md carve). Runs on
    # the ADOPTER's .env.example, never on kit source. Idempotent on an already-clean file.
    awk 'NF{p=NR} {a[NR]=$0} END{for(i=1;i<=p;i++) print a[i]}' .env.example > .env.example.kwtmp \
      && mv .env.example.kwtmp .env.example
  fi
  rm -f scripts/dr-drill.sh
  echo "non-DB archetype: stripped the kit:db-backed CI region + the .db-backed marker + the DB/Redis .env.example lines + scripts/dr-drill.sh"
}
# Internal/testing seam: run ONLY the DB curation on the cwd, then exit (test-incept-postgres.sh drives this).
if [ "${1:-}" = "__db-curate" ]; then curate_db_backed "${2:-1}"; exit 0; fi

NAME="${INCEPT_NAME:-}"; OWNER="${INCEPT_INTENT_OWNER:-}"
STACK="${INCEPT_STACK:-typescript-node}"; BACKLOG="${INCEPT_BACKLOG:-md}"; INTERACTIVE=1
# A stack chosen via INCEPT_STACK is deliberate too — only an un-set stack is a silent default.
[ -n "${INCEPT_STACK:-}" ] && STACK_EXPLICIT=1 || STACK_EXPLICIT=0
# CP-4 (security): the flag is the ONLY opt-in — never an ambient env var. Literal 0, not
# ${...:-0}, so a hostile/leftover ALLOW_NESTED in the environment cannot skip the ownership gate.
ALLOW_NESTED=0
# KW5: solo/team governance fork (mirrors STACK/STACK_EXPLICIT). Default solo (announced below).
# A team chosen via INCEPT_TEAM is deliberate too — only an un-set team is a silent default.
TEAM="${INCEPT_TEAM:-solo}"
[ -n "${INCEPT_TEAM:-}" ] && TEAM_EXPLICIT=1 || TEAM_EXPLICIT=0
TEAM_MODES="solo team"
CI="${INCEPT_CI:-github}"
HARNESS="${INCEPT_HARNESS:-claude-code}"        # default keeps today's experience identical
FLUENCY="${INCEPT_OPERATOR_FLUENCY:-}"          # empty = undeclared (nudge); else stamped
OPERATOR_FLUENCIES="novice adjacent practitioner"
MODE="${INCEPT_PROCESS_MODE:-}"
PROCESS_MODES="lean enterprise"
# KW3: the ts-node default archetype is DB-backed (=1). --no-db (or INCEPT_DB_BACKED=0) strips the
# profile's kit:db-backed CI region + the scaffold/.db-backed marker for a non-DB archetype.
DB_BACKED="${INCEPT_DB_BACKED:-1}"
# P1.2: the stamped date. Empty = "stamp today" (the default every adopter has always had).
# `kit-update` reconstructs the adopter's base tree by re-running incept over the vendored kit-base
# — that reconstruction runs TODAY, but the adopter's real tree carries their ADOPTION date, so an
# unpinned stamp would fabricate a conflict in CLAUDE.md / ADR-000-stack.md (files nobody touched).
# A FLAG, never an env var: an ambient INCEPT_DATE would let a decoy redirect a control-plane stamp.
DATE_PIN=''
# Canonical named backlog backends (one source of truth — conformance/backlog-adapters.sh
# asserts this set agrees with DEVELOPMENT-PROCESS.md §6 and docs/work-tracking/adapters.md).
BACKLOG_BACKENDS="md github jira ado linear gitlab"
# CI platforms with a shipped reference pipeline. The contract is the gate-ids (the platform
# is open — see docs/operations/ci-platforms.md); these are the two with a worked reference.
CI_PLATFORMS="github gitlab"
# Valid harness adapters = the adapters/ registry (one source of truth; each has an adapter.json).
HARNESS_ADAPTERS=$(for _d in adapters/*/; do [ -f "${_d}adapter.json" ] && printf '%s ' "$(basename "$_d")" || true; done)
[ -n "$HARNESS_ADAPTERS" ] || { echo "incept: no adapters/ registry found (adapters/<harness>/adapter.json). Aborting." >&2; exit 1; }
# Valid stacks = the profiles/ registry (one source of truth; each shipped stack has a profiles/<stack>/
# directory). DERIVED, never a hardcoded list that would drift. This is the reject-by-default set for
# --stack: the value is stamped into CLAUDE.md via a `#`-delimited sed program (and kit-update replays
# incept with the stack read back out of an adopter-controlled CLAUDE.md), so an unvalidated stack is a
# sed-injection / arbitrary-file-write sink — it MUST be validated exactly as --ci/--harness/--team are.
STACK_PROFILES=$(for _d in profiles/*/; do [ -d "$_d" ] && printf '%s ' "$(basename "$_d")" || true; done)
[ -n "$STACK_PROFILES" ] || { echo "incept: no profiles/ registry found (profiles/<stack>/). Aborting." >&2; exit 1; }

# reqval: a value-taking flag must have a value (else dash's `shift 2` would fail
# under set -e/-u and abort with a confusing error instead of a clean exit 2).
reqval() { [ "$1" -ge 2 ] || { echo "incept: $2 requires a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) reqval $# --name; NAME="$2"; shift 2 ;;
    --intent-owner) reqval $# --intent-owner; OWNER="$2"; shift 2 ;;
    --stack) reqval $# --stack; STACK="$2"; STACK_EXPLICIT=1; shift 2 ;;
    --team) reqval $# --team; TEAM="$2"; TEAM_EXPLICIT=1; shift 2 ;;
    --backlog) reqval $# --backlog; BACKLOG="$2"; shift 2 ;;
    --ci) reqval $# --ci; CI="$2"; shift 2 ;;
    --harness) reqval $# --harness; HARNESS="$2"; shift 2 ;;
    --operator-fluency) reqval $# --operator-fluency; FLUENCY="$2"; shift 2 ;;
    --mode) reqval $# --mode; MODE="$2"; shift 2 ;;
    # `reqval` checks ARITY, not EMPTINESS: `--date ""` satisfies it, and an empty DATE_PIN skips the
    # `[ -n "$DATE_PIN" ]` validation below and falls open to TODAY with rc=0. That is a fail-open in the
    # exact seam that exists to PREVENT a false alarm: kit-update passes the adoption date it parsed out
    # of CLAUDE.md, so an empty parse (missing field, reformatted doc, a grep that missed) would silently
    # stamp today and fabricate a phantom conflict in CLAUDE.md + ADR-000-stack.md. Refuse, loudly.
    --date) reqval $# --date; [ -n "$2" ] || { echo "incept: --date requires a non-empty YYYY-MM-DD value" >&2; exit 2; }; DATE_PIN="$2"; shift 2 ;;
    --no-db) DB_BACKED=0; shift ;;
    --allow-nested) ALLOW_NESTED=1; shift ;;
    --noninteractive) INTERACTIVE=0; shift ;;
    -h|--help) echo "usage: incept.sh [--name N] [--intent-owner O] [--stack S] [--team solo|team] [--backlog md|github|jira|ado|linear|gitlab] [--ci github|gitlab] [--harness claude-code[,generic,...]] [--operator-fluency novice|adjacent|practitioner] [--mode lean|enterprise] [--date YYYY-MM-DD] [--no-db] [--noninteractive]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- CP-4: repository ownership is a hard precondition -------------------------------------
# `git rev-parse --is-inside-work-tree` answers "is there a repo ABOVE me?" — not "is THIS dir the
# root of its own repo?". The two diverge only when nested, which is why every non-nested test
# agrees and why the kit once wrote a pre-push hook into a stranger's repository.
#
# BOTH sides of the compare must be PHYSICAL paths: `--show-toplevel` is symlink-resolved, `$PWD`
# is not. On macOS /tmp -> /private/tmp, so a logical compare FALSE-REFUSES under /tmp while
# passing on Linux CI. Normalizing both sides is the only compare that cannot drift.
#
# CP-11 closes the git-dir-CONTAINMENT gap: GIT_DIR/GIT_WORK_TREE env redirects are hard-refused, and
# submodule / `git worktree add` trees are refused unless gated behind --allow-nested. Residual (named,
# not absorbed): core.hooksPath, GIT_OBJECT_DIRECTORY, insteadOf — the git dir stays inside the cwd, so
# containment passes; out of CP-11 scope. See CP-11 design §6.
owning_repo_root() {  # <dir> -> stdout: physical toplevel, or empty when <dir> is in no repo
  ( CDPATH='' cd "$1" 2>/dev/null || exit 0
    _t=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    CDPATH='' cd "$_t" 2>/dev/null && pwd -P )
}
owns_itself() {  # <dir> -> 0 iff <dir> is its own repo root, or is in no repo at all
  # "Cannot determine" must REFUSE, never proceed (the kit's default). Compute the physical cwd FIRST:
  # a dir we cannot even cd into is not "in no repo -> fine", it is unknown -> refuse. Unreachable from
  # today's call sites (all pass "$PWD"/"$ROOT"), but the wrong default is worth closing.
  _phys=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_phys" ] || return 1
  _own=$(owning_repo_root "$1")
  [ -n "$_own" ] || return 0
  [ "$_own" = "$_phys" ]
}

# --- CP-11: git-dir redirection is a hard precondition (closes CP-4 §6) --------------------
# CP-4 proves toplevel==pwd, but `--show-toplevel` reports the cwd even when GIT_DIR/GIT_WORK_TREE, a
# submodule, or a `git worktree add` tree redirect the git dir ELSEWHERE (measured). The hook then lands
# in a repo the operator does not own (env) or a shared/other .git (structural). Invariant: the git dir
# that will receive the write lives INSIDE the tree I own. BOTH sides physical (the /tmp symlink landmine).
git_env_redirected() { [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; }
git_dir_outside() {  # <dir> -> 0 (true) iff the physical git-common-dir is NOT inside <dir>
  _cwd=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 0
  _gcd=$( CDPATH='' cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null ) || return 1
  [ -n "$_gcd" ] || return 1
  _gcd_phys=$( CDPATH='' cd "$1" 2>/dev/null && CDPATH='' cd "$_gcd" 2>/dev/null && pwd -P ) || return 0
  case "$_gcd_phys/" in "$_cwd"/*) return 1 ;; *) return 0 ;; esac
}

if git_env_redirected; then
  echo "" >&2
  echo "ERROR: your git environment redirects git away from this directory." >&2
  [ -n "${GIT_DIR:-}" ]       && echo "  GIT_DIR=$GIT_DIR" >&2
  [ -n "${GIT_WORK_TREE:-}" ] && echo "  GIT_WORK_TREE=$GIT_WORK_TREE" >&2
  echo "  incept would git-init and install the pre-push hook there, outside your product." >&2
  echo "  Nothing has been written. Clear the redirect and re-run:" >&2
  echo "    env -u GIT_DIR -u GIT_WORK_TREE sh scripts/incept.sh ..." >&2
  exit 1
elif git_dir_outside "$PWD" && [ "${ALLOW_NESTED:-0}" -eq 0 ]; then
  _gcd_raw=$( git rev-parse --git-common-dir 2>/dev/null )
  _gcd_show=$( CDPATH='' cd "${_gcd_raw:-.}" 2>/dev/null && pwd -P )
  [ -n "$_gcd_show" ] || _gcd_show=$_gcd_raw
  echo "" >&2
  echo "ERROR: this directory's git dir lives outside it (nested dir, submodule, or linked worktree)." >&2
  echo "  git dir: $_gcd_show  — the pre-push hook would land in that shared/other repo." >&2
  echo "  If this is intentional, re-run with:  sh scripts/incept.sh --allow-nested ..." >&2
  exit 1
fi

# CP-4: assert ownership BEFORE ANY MUTATION — before the scaffold copy, before `git init`, before
# the pre-push hook. Nested in a foreign worktree, incept skipped `git init` (the PARENT satisfied
# --is-inside-work-tree) and installed the guard into the PARENT's .git/hooks/. "Fails, but only
# after it wrote the hook" is not a fix; placement here is the fix.
if ! owns_itself "$PWD" && [ "${ALLOW_NESTED:-0}" -eq 0 ]; then
  _parent=$(owning_repo_root "$PWD")
  echo "" >&2
  echo "ERROR: this directory is not the root of its own git repository." >&2
  echo "  cwd:      $(pwd -P)" >&2
  echo "  owned by: $_parent  (git toplevel)" >&2
  echo "" >&2
  echo "Incept would skip 'git init' and install the pre-push hook into" >&2
  echo "$_parent/.git/hooks/ — outside your product. Nothing has been written." >&2
  echo "" >&2
  echo "If this nesting is intentional (e.g. a monorepo package), re-run with:" >&2
  echo "  sh scripts/incept.sh --allow-nested ..." >&2
  exit 1
fi

# escape a string for safe use as a sed REPLACEMENT. Escapes & / \ AND the `#` delimiter every `sedi`
# stamp below uses: without `#`, a `#`-bearing value terminates the `s#..#..#` program and the trailing
# text is read as sed COMMANDS (e.g. `w <path>` = arbitrary file write). Escaping `#` closes EVERY
# `#`-delimited stamp sink at once, not just one call site (T9 — defense in depth with --stack validation).
esc() { printf '%s' "$1" | sed 's/[&/#\\]/\\&/g'; }
# portable in-place sed: last positional arg is the FILE (POSIX; no bash ${@: -1})
sedi() {
  last=
  for last in "$@"; do :; done
  sed -i.bak "$@" && rm -f "${last}.bak"
}
# Inception replaces the kit's OWN reference/dogfooding files (expected in a greenfield kit copy) but
# must NEVER clobber a genuine adopter file in a brownfield merge. A kit-own file is identified by a
# marker; an ABSENT destination is also safe to write. (go/no-go #2 — a bare cp silently overwrote an
# adopter's CI/CODEOWNERS.) Brownfield adopters merge per docs/adoption/brownfield.md.
cp_kit_replace() {  # <src> <dst> <kit-own-marker-ERE>
  if [ ! -f "$2" ] || grep -qE "$3" "$2" 2>/dev/null; then
    cp "$1" "$2"
  else
    echo "warning: $2 exists and is not a kit reference file — NOT overwritten (brownfield-safe). Merge $1 into it per docs/adoption/brownfield.md." >&2
  fi
}

warn_codeowners_placeholder() {  # <dst> — G11: a copied CODEOWNERS with @your-org/* blocks merges if owner-review is on before it's hand-edited
  if [ -f "$1" ] && grep -q '@your-org' "$1" 2>/dev/null; then
    echo "warning: $1 contains @your-org/* placeholder teams — replace them with REAL teams/users" >&2
    echo "         BEFORE enabling branch protection (require_code_owner_reviews), or EVERY merge" >&2
    echo "         will block (the placeholder owners don't exist). See docs/operations/review-lane.md." >&2
  fi
}

# 9f: fail fast if universal prerequisites are missing — jq is hard-required by the
# guard and conformance, so proceeding would only defer a cryptic failure.
_pf_nested=""
[ "${ALLOW_NESTED:-0}" -eq 1 ] && _pf_nested="--allow-nested"
# shellcheck disable=SC2086  # $_pf_nested is a deliberate single optional flag, not a word list
if [ -f scripts/preflight.sh ] && ! sh scripts/preflight.sh $_pf_nested >/dev/null 2>&1; then
  echo "incept: missing prerequisites. Run 'sh scripts/preflight.sh' for the list + install hints. Aborting." >&2
  exit 1
fi

# --- safety guards ---
[ -f ENGINEERING-PRINCIPLES.md ] && { echo "error: ENGINEERING-PRINCIPLES.md exists — already incepted. Aborting." >&2; exit 1; }
{ [ -f CLAUDE.md ] && grep -q "Engineering Principles & Definition of Done" CLAUDE.md; } || {
  echo "error: not an un-incepted Sparkwright kit (principles CLAUDE.md not found). Aborting." >&2; exit 1; }

# --- INCEPT-CONTAIN: refuse a tree that carries kit-internal artifacts --------------------------
# incept transforms a CLEAN adopter distribution: adopter-export.sh (git archive --worktree-attributes)
# strips every export-ignored path, so an adopter tree carries NO kit internals. The kit's OWN dev repo
# and a raw `git clone` of it DO. Refuse BEFORE any mutation and redirect to the export path. This is a
# PROPERTY check (tree has kit internals), not an identity check (dev-repo vs clone are byte-identical).
# Soundness: every marker below is export-ignored in .gitattributes, so a clean export can never trip
# this — locked by conformance/incept-containment.sh (refusal-set ⊆ export-ignored). Sibling: CP-11
# (GIT_DIR/GIT_WORK_TREE redirect). KEEP KIT_INTERNAL_MARKERS ON ONE LINE — the lock greps this line.
# Markers MUST be glob-free and match [A-Za-z0-9._/-] only: the unquoted `for` word-split below relies
# on no pathname expansion, and the soundness lock's ERE escaper covers exactly this character class.
KIT_INTERNAL_MARKERS='SPARKWRIGHT-CONSOLIDATED-BACKLOG.md docs/ROADMAP-KIT.md docs/superpowers .superpowers .publish-identifiers docs/governance/meta-control-log.md'
for _m in $KIT_INTERNAL_MARKERS; do   # values are glob-free literals; `set -eu` word-split is safe
  [ -e "$_m" ] || continue
  echo "" >&2
  echo "ERROR: this tree contains Sparkwright kit-internal files ($_m)." >&2
  echo "incept transforms a clean adopter distribution — not the kit source or a raw clone." >&2
  echo "Produce one, then incept inside it:" >&2
  echo "  sh scripts/adopter-export.sh <dest-dir>   &&   cd <dest-dir> && sh scripts/incept.sh ..." >&2
  echo "Nothing has been written." >&2
  exit 1
done

# brownfield safety: warn (never modify) if a .claude/ exists without the kit guard wired.
if [ -f .claude/settings.json ] && ! grep -q 'guard\.sh' .claude/settings.json; then
  echo "warning: .claude/settings.json present but the kit guard is not registered." >&2
  echo "         If this is an existing repo, MERGE .claude/ per docs/adoption/brownfield.md" >&2
  echo "         (add, do not overwrite) before running agents. Continuing without touching .claude/." >&2
fi

# --- P1.2-pre: CAPTURE the pristine export, before any mutation --------------------------------------
# Split in time, deliberately: CAPTURE here (the tree is still pristine, but there may be NO git repo yet
# — the documented adopter path starts from a plain directory and §5b0 below is where `git init` runs),
# then COMMIT the orphan branch after §5b0. The obvious implementation — "snapshot to an orphan branch
# before mutating" — CANNOT work: the repo you would snapshot into does not exist yet, and by the time it
# does, the pristine tree is gone. Reordering §5b0 earlier was rejected: it would move a `git init` that
# five guard clauses and the CP-4 ownership gate are sequenced around.
#
# SCOPED TO .kit-manifest, NOT THE WORKTREE — this is the data-loss guard. A brownfield worktree contains
# adopter-authored files; capturing them would make a later diff(kit-base, new-export) read them as "the
# kit deleted these", and kit-update would propose DELETING THE ADOPTER'S OWN WORK. Only paths the
# exporter said it shipped can enter the base.
KIT_BASE_STAGE=""
# S1: is the relative path <arg>, or ANY of its ancestor components, a symlink? Walks each prefix
# (a/b/c -> a, a/b, a/b/c) and tests it. POSIX; no realpath/readlink dependency. Returns 0 iff a symlink
# is found anywhere on the path — the caller then refuses the whole base.
_kb_path_has_symlink() {
  # Walk prefixes via parameter expansion — NOT IFS splitting (semgrep p/default flags ifs-tampering,
  # and it runs on the emitted artifact; CP-8b's lesson). a/b/c -> a, a/b, a/b/c.
  _kb_rest=$1; _kb_acc=""
  while [ -n "$_kb_rest" ]; do
    _kb_seg=${_kb_rest%%/*}
    case "$_kb_rest" in */*) _kb_rest=${_kb_rest#*/} ;; *) _kb_rest="" ;; esac
    [ -n "$_kb_seg" ] || continue
    if [ -z "$_kb_acc" ]; then _kb_acc=$_kb_seg; else _kb_acc="$_kb_acc/$_kb_seg"; fi
    [ -L "$_kb_acc" ] && return 0
  done
  return 1
}
capture_kit_base() {
  if [ ! -f .kit-manifest ]; then
    echo "notice: no .kit-manifest — this export predates the kit-base mechanism." >&2
    echo "        NOT recording a base. 'kit-update' will be UNAVAILABLE for this project." >&2
    echo "        Re-export with a current kit to get one. See docs/operations/kit-base.md." >&2
    return 0
  fi
  # SECURITY: the manifest tells a privileged tool what to stage. Treat it as UNTRUSTED INPUT even though
  # we wrote it — an absolute path, a '..' segment, or a leading '-' (option injection) must never be
  # followed. Refuse the whole base rather than partially trust it; fail SAFE (no base), never fail open.
  if LC_ALL=C grep -qE '^/|(^|/)\.\.(/|$)|^-' .kit-manifest; then
    echo "warning: .kit-manifest contains an absolute path, a '..' segment, or a leading '-'." >&2
    echo "         REFUSING to record a kit-base from it. 'kit-update' will be unavailable." >&2
    return 0
  fi
  KIT_BASE_STAGE=$(mktemp -d) || { KIT_BASE_STAGE=""; return 0; }
  # C3: clean the staging dir on ANY exit between here and commit_kit_base (input validation, preflight,
  # an interactive Ctrl-C). commit_kit_base removes it on the success path; this catches every other one.
  # shellcheck disable=SC2064
  trap 'rm -rf "$KIT_BASE_STAGE" 2>/dev/null || true' EXIT INT TERM
  while IFS= read -r _kbp; do
    [ -n "$_kbp" ] || continue
    # S1 (security BLOCKER, review #318): a symlink — or a path whose ANY ancestor is a symlink — makes
    # the copy below read a file OUTSIDE the export and bake its content into a committed, pushed git ref.
    # The literal-text guard above cannot see it (the path text is clean; the filesystem resolves it out).
    # The kit ships ZERO symlinks, so refuse the ENTIRE base on the first one — fail CLOSED, no base — and
    # never copy through it. This is belt to the export side's braces (it no longer emits symlinks).
    if _kb_path_has_symlink "$_kbp"; then
      echo "warning: .kit-manifest entry '$_kbp' is, or traverses, a symlink." >&2
      echo "         REFUSING to record a kit-base (it could copy a file from outside the export into your" >&2
      echo "         git history). 'kit-update' will be unavailable. See docs/operations/kit-base.md." >&2
      rm -rf "$KIT_BASE_STAGE" 2>/dev/null || true; KIT_BASE_STAGE=""
      return 0
    fi
    [ -f "$_kbp" ] || continue
    mkdir -p "$KIT_BASE_STAGE/$(dirname "$_kbp")" 2>/dev/null || continue
    # cp -P: NEVER dereference. Defense in depth — even if a symlink slipped past the check above, its
    # content can never be materialized into the base (the link itself would be copied, not its target).
    cp -P "$_kbp" "$KIT_BASE_STAGE/$_kbp" 2>/dev/null || true
  done < .kit-manifest
}
capture_kit_base

# --- collect inputs ---
if [ "$INTERACTIVE" -eq 1 ]; then
  [ -n "$NAME" ]  || { printf 'Project name: '; read -r NAME; }
  [ -n "$OWNER" ] || { printf 'Intent owner: '; read -r OWNER; }
  printf 'Stack [%s] (compare: docs/STACK-SELECTION.md): ' "$STACK"; read -r _s || true; [ -n "${_s:-}" ] && { STACK="$_s"; STACK_EXPLICIT=1; }
  printf 'Backlog backend (md/github/jira/ado/linear/gitlab) [%s]: ' "$BACKLOG"; read -r _b || true; [ -n "${_b:-}" ] && BACKLOG="$_b"
  printf 'CI platform (github/gitlab) [%s]: ' "$CI"; read -r _c || true; [ -n "${_c:-}" ] && CI="$_c"
  printf 'Harness(es), comma-separated, of: %s [%s]: ' "$HARNESS_ADAPTERS" "$HARNESS"; read -r _h || true; [ -n "${_h:-}" ] && HARNESS="$_h"
  printf 'Operator fluency (novice/adjacent/practitioner) [skip to decide later]: '; read -r _f || true; [ -n "${_f:-}" ] && FLUENCY="$_f"
  printf 'Process mode (lean/enterprise) [lean]: '; read -r _m || true; [ -n "${_m:-}" ] && MODE="$_m"
  printf 'Governance (solo/team) [%s] (docs/operations/review-lane.md): ' "$TEAM"; read -r _tm || true; [ -n "${_tm:-}" ] && { TEAM="$_tm"; TEAM_EXPLICIT=1; }
fi
[ -n "$NAME" ]  || { echo "error: --name required" >&2; exit 2; }
[ -n "$OWNER" ] || { echo "error: --intent-owner required" >&2; exit 2; }
case " $BACKLOG_BACKENDS " in *" $BACKLOG "*) : ;; *) echo "error: unknown --backlog '$BACKLOG' (one of: $BACKLOG_BACKENDS)" >&2; exit 2 ;; esac
case " $CI_PLATFORMS " in *" $CI "*) : ;; *) echo "error: unknown --ci '$CI' (one of: $CI_PLATFORMS)" >&2; exit 2 ;; esac
case " $TEAM_MODES " in *" $TEAM "*) : ;; *) echo "error: unknown --team '$TEAM' (one of: $TEAM_MODES)" >&2; exit 2 ;; esac
# --stack is reject-by-default against the profiles/ registry, refused EARLY (before any file mutation).
# SECURITY: unvalidated, the value flows into a `#`-delimited `sedi` stamp (arbitrary-file-write via sed
# `w`) and kit-update replays it from an adopter-controlled CLAUDE.md. esc() also escapes `#` now — belt
# and braces — but the registry check is the real boundary. A value starting with `-` lands here too (it
# is consumed as the --stack VALUE, not a flag) and is refused unless it names a shipped profile.
case " $STACK_PROFILES " in *" $STACK "*) : ;; *) echo "error: unknown --stack '$STACK' (one of: $STACK_PROFILES)" >&2; exit 2 ;; esac
HARNESS_LIST=$(printf '%s' "$HARNESS" | tr ',' ' ')
for _h in $HARNESS_LIST; do
  case " $HARNESS_ADAPTERS " in *" $_h "*) : ;; *) echo "error: unknown --harness '$_h' (one of: $HARNESS_ADAPTERS)" >&2; exit 2 ;; esac
done
# GitLab CI ships only for stacks with a reference pipeline (typescript-node today). Refuse EARLY
# (before any file changes) rather than silently writing no CI file and dead-ending at the
# Inception-Done gate. GitHub ships a pipeline for every service stack.
if [ "$CI" = "gitlab" ] && [ ! -f "profiles/${STACK}/ci.gitlab-ci.yml" ]; then
  _gl=$(ls profiles/*/ci.gitlab-ci.yml 2>/dev/null | sed 's#profiles/##; s#/ci.gitlab-ci.yml##' | tr '\n' ' ')
  echo "error: --ci gitlab is not yet available for stack '${STACK}' (no profiles/${STACK}/ci.gitlab-ci.yml)." >&2
  echo "       Use --ci github (ships for every service stack), or add profiles/${STACK}/ci.gitlab-ci.yml." >&2
  echo "       GitLab references today: ${_gl:-none}." >&2
  exit 2
fi

# RATIFY-PARITY: the §13 control-plane-ratification gate installs (github CI) from the single
# stack-neutral source profiles/ratification.yml. Refuse EARLY — before any working-tree mutation —
# if it is missing, so a broken distribution fails clean instead of leaving a half-initialized tree.
# A kit that lost its governance source must never silently produce an ungoverned project. Scoped to
# --ci github (the gate is GitHub-specific); a valid kit/export always ships the source, so a real
# adopter never hits this. The install site (github case) re-checks and fails closed too (defence-in-depth).
if [ "$CI" = "github" ] && [ ! -f profiles/ratification.yml ]; then
  echo "error: profiles/ratification.yml is MISSING — cannot install the §13 control-plane-ratification gate." >&2
  echo "       This is a broken kit distribution; refusing to produce an ungoverned project. Nothing has been written." >&2
  exit 1
fi
if [ -n "$FLUENCY" ]; then
  case " $OPERATOR_FLUENCIES " in *" $FLUENCY "*) : ;; *) echo "error: unknown --operator-fluency '$FLUENCY' (one of: $OPERATOR_FLUENCIES)" >&2; exit 2 ;; esac
fi
[ -n "$MODE" ] || MODE="lean"
# Deprecation: prototype/team are the former names of the lean ceremony tier (ceremony only;
# solo-vs-team governance is the separate enforce_admins / review-lane.md axis).
case "$MODE" in prototype|team) echo "notice: --mode '$MODE' is deprecated; using 'lean' (ceremony only -- solo-vs-team governance is the separate enforce_admins / review-lane.md axis)" >&2; MODE="lean" ;; esac
case " $PROCESS_MODES " in *" $MODE "*) : ;; *) echo "error: unknown --mode '$MODE' (one of: $PROCESS_MODES)" >&2; exit 2 ;; esac
# --date is strictly YYYY-MM-DD. Not cosmetic: the value is interpolated into the `sedi` replacement
# below, so an unvalidated string is a sed-expression injection surface (and a garbage stamp).
#
# The SHAPE glob alone is not enough — `[0-1][0-9]-[0-3][0-9]` accepts 2026-00-00 and 2026-13-32, which
# are not dates. The charset is sed-safe either way, so this is not a security hole; it is a promise the
# flag makes and must keep, since the value it stamps is what kit-update later reads back. So: shape
# first (which also bounds the charset to digits + '-'), then the month and day RANGES, expressed as
# case globs a POSIX `case` can state exactly.
# Honest ceiling: this is a calendar-SHAPE check, not a calendar. 2026-02-31 has a valid month and a
# valid day and is accepted; catching that needs a real date library, and the stamp is a label, not an
# instant. The classes that mattered — empty, unpadded, out-of-range, and anything sed-active — are shut.
if [ -n "$DATE_PIN" ]; then
  case "$DATE_PIN" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "error: --date must be YYYY-MM-DD (got '$DATE_PIN')" >&2; exit 2 ;;
  esac
  _dp_m=${DATE_PIN#*-}; _dp_m=${_dp_m%%-*}   # MM
  _dp_d=${DATE_PIN##*-}                      # DD
  case "$_dp_m" in
    0[1-9]|1[0-2]) : ;;
    *) echo "error: --date month must be 01-12 (got '$_dp_m' in '$DATE_PIN')" >&2; exit 2 ;;
  esac
  case "$_dp_d" in
    0[1-9]|[12][0-9]|3[01]) : ;;
    *) echo "error: --date day must be 01-31 (got '$_dp_d' in '$DATE_PIN')" >&2; exit 2 ;;
  esac
fi

# 9g: never SILENTLY default the stack — make the default choice explicit + pointed.
if [ "$STACK_EXPLICIT" -eq 0 ]; then
  echo "notice: no --stack given — using '$STACK'. Choose deliberately (fit AND maturity): docs/STACK-SELECTION.md" >&2
fi
# KW5: never SILENTLY default the solo/team governance fork — announce it (SoD stays server-side).
[ "$TEAM_EXPLICIT" -eq 1 ] || echo "notice: no --team given — using 'solo' (enforce_admins:false + admin-merge). Team scale? pass --team team + flip enforce_admins:true. See docs/operations/review-lane.md + START-HERE 'Solo / lite track'." >&2
# KW5: deploy-target is BYO (no default) — nudge a deliberate, fit-driven choice.
echo "notice: choose your deploy target deliberately — docs/adoption/DEPLOYMENT-ENVIRONMENT.md (cards + fit rubric); record fit + maturity in RUNBOOK §4 (linted by conformance/deploy-decision-integrity.sh)." >&2
# KW9-B: surface harness FIT + honest MATURITY — the harness is a concretization axis (instance #3).
# Choose by fit, not by "it's the default"; and disclose that only claude-code is a VERIFIED harness
# (the kit self-hosts on it) while gemini/codex/cursor are EXPERIMENTAL (declared, not exercised —
# unproven, not "supported"). Always emitted → non-interactive-safe. Mirrors the KW5 deploy nudge +
# KW4-L1's stack fit-vs-maturity disclosure. Cards + fit rubric: docs/operations/harness-adapters.md.
echo "notice: target harness(es) = '${HARNESS}'. Confirm this is the BEST-FIT harness (fit-derived, not the default). Only 'claude-code' is a VERIFIED harness (kit self-hosts on it); 'gemini'/'codex'/'cursor' are EXPERIMENTAL (declared against the boundary contract, not exercised end-to-end — unproven, not 'supported'). Record WHY it fits (cite a fit dimension) in CLAUDE.md §harness-neutrality — linted by conformance/harness-decision-integrity.sh. Cards + fit rubric: docs/operations/harness-adapters.md." >&2
# K4/AC1: disclose the enforcement CEILING for hookless harnesses — a maturity label
# ("experimental") is not a capability statement. A harness whose adapter declares
# command-guard != "native" has NO inline PreToolUse-equivalent interception, so
# control-plane enforcement is post-hoc (pre-push + CI), not pre-exec. Data-driven
# from adapter.json (single source; fleet-general); fail-safe toward MORE disclosure.
_ceiling_harnesses=''
for _h in $HARNESS_LIST; do
  _lvl=$(jq -r '.dimensions["command-guard"].level // "floor"' "adapters/${_h}/adapter.json" 2>/dev/null || echo floor)
  [ "$_lvl" = "native" ] || _ceiling_harnesses="${_ceiling_harnesses:+$_ceiling_harnesses, }${_h}"
done
[ -z "$_ceiling_harnesses" ] || echo "notice: enforcement ceiling — harness(es) '${_ceiling_harnesses}' have NO inline PreToolUse-equivalent interception (no pre-exec deny). Control-plane enforcement is limited to the local pre-push hook + the CI agent-boundary gate (post-hoc, not pre-exec). See docs/operations/harness-adapters.md (the ceiling, stated plainly)." >&2
[ -n "$FLUENCY" ] || echo "notice: operator fluency not declared. New to enterprise SDLC? read ONBOARDING.md. Already fluent? pass --operator-fluency practitioner. Leaving the field for you to fill in CLAUDE.md." >&2

DATE=$(esc "${DATE_PIN:-$(date +%Y-%m-%d)}")
VER=$(cat VERSION 2>/dev/null || echo "unknown")
ENAME=$(esc "$NAME"); EOWNER=$(esc "$OWNER")

# --- 1. free the root memory slot ---
# Use `git mv` only when CLAUDE.md is actually TRACKED. In the literal quickstart (copy the
# kit into a fresh `git init` repo, run incept before committing), CLAUDE.md is untracked and
# `git mv` aborts with exit 128 — fall back to a plain `mv` (nothing is committed, so no
# history is lost). Covers tracked / untracked-in-worktree / non-git alike.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1; then
  git mv CLAUDE.md ENGINEERING-PRINCIPLES.md
else
  mv CLAUDE.md ENGINEERING-PRINCIPLES.md
fi
sedi 's/| \*\*`CLAUDE.md`\*\* (this) |/| **`ENGINEERING-PRINCIPLES.md`** (this) |/' ENGINEERING-PRINCIPLES.md

# --- 2. rewrite principles-sense references (project-sense CLAUDE.md refs stay) ---
sedi -e 's/and `CLAUDE.md` (principles + Definition of Done)/and `ENGINEERING-PRINCIPLES.md` (principles + Definition of Done)/' \
     -e 's/The authoritative checklist is in \*\*`CLAUDE.md`\*\*/The authoritative checklist is in **`ENGINEERING-PRINCIPLES.md`**/' \
     -e 's#Definition-of-Done "CI/CD" check, `CLAUDE.md`)#Definition-of-Done "CI/CD" check, `ENGINEERING-PRINCIPLES.md`)#' \
     DEVELOPMENT-STANDARDS.md
sedi -e 's/and `CLAUDE.md` (authoritative principles + Definition of Done)/and `ENGINEERING-PRINCIPLES.md` (authoritative principles + Definition of Done)/' \
     -e 's/When they overlap, `CLAUDE.md` is authoritative/When they overlap, `ENGINEERING-PRINCIPLES.md` is authoritative/' \
     DEVELOPMENT-PROCESS.md
sedi 's/| \*\*`CLAUDE.md`\*\* | Principles + Definition of Done. Authoritative. |/| **`ENGINEERING-PRINCIPLES.md`** | Principles + Definition of Done. Authoritative. |/' README.md
sedi 's/`CLAUDE.md` (principles + Definition of Done)/`ENGINEERING-PRINCIPLES.md` (principles + Definition of Done)/' START-HERE.md
sedi 's/the principles (`CLAUDE.md`)/the principles (`ENGINEERING-PRINCIPLES.md`)/' ONBOARDING.md
sedi 's#`DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md`#`DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `ENGINEERING-PRINCIPLES.md`#' MAINTAINING.md
sedi 's/\*\*Principles + Definition of Done:\*\* `CLAUDE.md`/**Principles + Definition of Done:** `ENGINEERING-PRINCIPLES.md`/' templates/PROJECT-CLAUDE-TEMPLATE.md

# --- 3. stamp the project CLAUDE.md ---
cp templates/PROJECT-CLAUDE-TEMPLATE.md CLAUDE.md
sedi -e "s/\*\*Project:\*\* \[name\]/**Project:** ${ENAME}/" \
     -e "s/\*\*Intent owner:\*\* \[who owns the why\]/**Intent owner:** ${EOWNER}/" \
     -e "s#\*\*Status:\*\* \[Inception / Active / Maintenance / Paused\]#**Status:** Inception#" \
     -e "s/\*\*Created:\*\* \[date\]/**Created:** ${DATE}/" \
     -e "s#\*\*Kit version adopted:\*\* \[vX.Y.Z.*\]#**Kit version adopted:** v${VER}#" \
     CLAUDE.md
if [ -n "$FLUENCY" ]; then
  # Capitalize first letter for the human-facing value (Novice/Adjacent/Practitioner)
  FCAP=$(printf '%s' "$FLUENCY" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$FLUENCY" | cut -c2-)
  sedi "s#\*\*Operator fluency\*\* (§onboarding): \[Novice / Adjacent / Practitioner\]#**Operator fluency** (§onboarding): ${FCAP}#" CLAUDE.md
fi
# stamp the target harness(es)
sedi "s#\*\*Target harness(es)\*\* (§harness-neutrality): \[claude-code\]#**Target harness(es)** (§harness-neutrality): $(esc "$HARNESS")#" CLAUDE.md
# KW9-B: personalize the Harness fit rationale placeholder with the chosen harness while KEEPING it an
# explicit UNFILLED decision — the body stays bracketed AND retains the "why this harness fits" sentinel,
# so conformance/harness-decision-integrity.sh reads it as N/A (not yet decided) until the human writes
# the real fit reason. Mirrors the harness stamp above + KW4-L1's stack fit-vs-maturity disclosure. No-op
# if the template lacks the §harness-neutrality fit-rationale slot.
sedi "s#\[why this harness fits#[$(esc "$HARNESS") — why this harness fits#" CLAUDE.md
# S1: stamp the process mode (lowercase — matches the flag values, PROCESS_MODES, and the template field)
sedi "s#\*\*Process mode\*\* (§ ceremony): \[lean / enterprise\]#**Process mode** (§ ceremony): $(esc "$MODE")#" CLAUDE.md
# KW5: stamp the governance (solo/team) choice — records the fork so it's a ratified decision, not a
# silent default (mirrors the process-mode stamp). No-op if the template lacks the §3 governance slot.
sedi "s#\*\*Governance\*\* (§ solo/team): \[solo / team\]#**Governance** (§ solo/team): $(esc "$TEAM")#" CLAUDE.md
# KW6-A: stamp the backlog backend — the operator ALREADY chose it (prompt above / --backlog), but the
# answer never reached CLAUDE.md §3, so conformance/backlog-current.sh read the raw choice-list
# placeholder as *undeclared* → N/A → the board gate silently never ran. Record the chosen token
# (md/github/jira/ado/linear/gitlab) so it's a ratified decision, mirroring the four stamps above.
# Replaces ONLY the bracketed choice-list — the trailing `— [link] (mapping: …)` annotation is preserved
# ([^]]* stops at the first ], so [link] is untouched) and the human still fills in the link. No-op if
# the template lacks the §3 backlog slot; idempotent (the anchor requires `[` right after the field).
sedi "s#\*\*Backlog backend\*\* (§6): \[[^]]*\]#**Backlog backend** (§6): $(esc "$BACKLOG")#" CLAUDE.md
# P1.2-pre: stamp the STACK — the one inception input that nothing recorded. incept stamped seven answers
# (project, owner, date, kit version, fluency, harness, process mode, governance, backlog) and never the
# stack, so a project could not say which profile it was built from. That is a cold-resume hole on its own,
# and it is load-bearing for kit-update: a new export must be pruned to the SAME profile before it can be
# compared against kit-base (an un-pruned export would read as "the kit added eight profiles").
# Replaces ONLY the bracketed choice-list; idempotent; no-op if the template lacks the §3 slot.
sedi "s#\*\*Stack profile\*\* (§2): \[[^]]*\]#**Stack profile** (§2): $(esc "$STACK")#" CLAUDE.md
# P1.2 (T3b): stamp the LAST TWO inception inputs nothing recorded — the CI PLATFORM and the DB ARCHETYPE.
# Same reason as the stack stamp above, and the same mechanism. kit-update reconstructs the adopter's base
# by REPLAYING incept over kit-base with the inputs this project recorded; anything not recorded has to be
# INFERRED from the tree, and inference is where a wrong base comes from. It is not hypothetical: `--ci
# gitlab` leaves the exported kit-own .github/workflows/ci.yml exactly where it is, so "a GitHub workflow
# exists ⇒ --ci github" misreads EVERY GitLab adopter — and a wrong base cries CONFLICT on kit files the
# adopter never touched. Record the FACT so nothing downstream has to guess it.
# Both replace ONLY the bracketed choice-list (the trailing prose annotation survives); both are idempotent
# (the anchor requires the `[` right after the field); both no-op if the template lacks the §3 slot — an
# adopter incepted BEFORE these slots existed reconstructs identically, because their kit-base carries the
# same slot-less template AND the same slot-less incept. Locked by conformance/incept-first-run-green.sh.
sedi "s#\*\*CI platform\*\* (§14): \[[^]]*\]#**CI platform** (§14): $(esc "$CI")#" CLAUDE.md
# The stamped token is the FLAG the operator chose (db-backed / no-db), not a fact re-derived from the
# tree: --no-db's effects (CI region, marker, .env.example lines, dr-drill.sh) are a strict SUBSET of what
# an adopter may later edit by hand, so only the input itself is a reliable record of the input.
if [ "$DB_BACKED" = 1 ]; then _dbarch=db-backed; else _dbarch=no-db; fi
sedi "s#\*\*DB archetype\*\* (§ archetype): \[[^]]*\]#**DB archetype** (§ archetype): ${_dbarch}#" CLAUDE.md

# --- 3a. S1: mode-driven curation — surfacing/scaffolding only; NEVER an enforcement input. ---
curate_for_mode() {  # $1 = mode
  case "$1" in
    lean)
      if [ ! -f docs/conditional-obligations.md ]; then
        mkdir -p docs
        cat > docs/conditional-obligations.md <<'EOF'
# Conditional obligations (process mode: lean)

These gates are **enforced automatically when their trigger appears** — you do not opt in or out.
Your project starts on the floor; each below activates the moment you add its trigger.

| Control | Applies IF | Enforced by |
|---|---|---|
| Threat model / privacy review | you declare Confidential/Restricted data (CLAUDE.md §3) | conformance/privacy-ready.sh |
| Eval gate + AI System Card | you add an `evals/` dir or declare `AI feature: yes` | conformance/eval-ready.sh |
| Agent-ops trace posture | you declare `Agentic: yes` | conformance/agentops-ready.sh |
| Accessibility sign-off | you ship a user-facing UI | a11y gate (DEVELOPMENT-STANDARDS §14) |
| Deployable / resilience / DR | you add a Dockerfile or deploy workflow / durable data | deployable-ready, resilience-ready, dr-ready |
| Container supply-chain (image SBOM + provenance) | you add a Dockerfile | conformance/container-supply-chain.sh |

The floor (lint · type · test+coverage · build · secret-scan · deps · SBOM · branch-protection · builder≠reviewer) applies in EVERY mode and is never waived.

Ask *why* any of these matters: `sparkwright explain <control>` (or see docs/why-gates.md).
EOF
      fi
      ;;
    enterprise)
      mkdir -p docs/governance
      for _t in THREAT-MODEL PRIVACY-REVIEW AI-SYSTEM-CARD AI-POLICY AI-TRANSPARENCY-SIGNOFF A11Y-SIGNOFF BIA UAT-SIGNOFF WAIVER-REGISTER; do
        _src="templates/${_t}-TEMPLATE.md"; [ -f "$_src" ] || _src="templates/${_t}.md"  # WAIVER-REGISTER ships as WAIVER-REGISTER.md (no -TEMPLATE suffix)
        _dst="docs/governance/${_t}.md"
        [ -f "$_src" ] && [ ! -f "$_dst" ] && cp "$_src" "$_dst"
      done
      [ -f docs/governance/README.md ] || cat > docs/governance/README.md <<'EOF'
# Governance apparatus (process mode: enterprise)

These templates are stamped ready-to-fill. They are SURFACING, not enforcement — each gate still
keys on its detected trigger (data classification, AI feature, UI, data service). Delete the ones
your project genuinely does not need; fill the rest and move/reference them where each conformance
check looks (see each `conformance/*-ready.sh` header).
EOF
      ;;
  esac
}
curate_for_mode "$MODE"

# --- 4. RUNBOOK / BACKLOG / ADR-000 ---
[ -f RUNBOOK.md ] || { cp templates/RUNBOOK-TEMPLATE.md RUNBOOK.md; sedi "s/\[Project Name\]/${ENAME}/g" RUNBOOK.md; }
[ -f SECURITY.md ] || cp templates/SECURITY-TEMPLATE.md SECURITY.md
# .env.example — the committed env template the DoD + RUNBOOK require (never a real .env).
if [ ! -f .env.example ]; then
  cat > .env.example <<'ENVEOF'
# Environment variables — TEMPLATE. Copy to `.env` (gitignored) and fill real values.
# Document each in RUNBOOK.md §1 and the profile's "Environments this stack needs".
# NEVER commit real secrets (DEVELOPMENT-STANDARDS.md §2).

# App (set PORT to match your service/compose — e.g. 3000 node, 8000 python, 8080 go/rust)
PORT=8080

# Secrets — replace placeholders with strong values kept out of git
APP_SECRET=replace-me

# Backing services — uncomment what your stack/archetype needs (see compose.yaml)
# DATABASE_URL=postgres://app:app@localhost:5432/app
# REDIS_URL=redis://localhost:6379
ENVEOF
  # Stamp a stack-appropriate default PORT so .env.example matches the scaffold/docs (go/no-go #4:
  # the ts-node scaffold + docs use 3000; a hardcoded 8080 made the documented `curl :3000` fail).
  case "$STACK" in
    python)  _port=8000 ;;
    go|rust) _port=8080 ;;
    *)       _port=3000 ;;
  esac
  sedi "s/^PORT=8080/PORT=${_port}/" .env.example
  echo "wrote .env.example (PORT=${_port} for ${STACK}; copy to a gitignored .env and fill values — see RUNBOOK §1)"
fi
# Ensure real .env files are never committed — the template above tells the user to create one,
# so guarantee the ignore rule exists (not all stack scaffolds carry it). Idempotent.
if [ ! -f .gitignore ] || ! grep -qE '^\.env' .gitignore 2>/dev/null; then
  printf '\n# Local env files — never commit real secrets (.env.example IS the committed template)\n.env\n.env.*\n!.env.example\n' >> .gitignore
  echo "ensured .env is gitignored (real secrets stay out of git)"
fi
case "$BACKLOG" in
  md) [ -f BACKLOG.md ] || { cp templates/BACKLOG-TEMPLATE.md BACKLOG.md; sedi "s/\[Project Name\]/${ENAME}/g" BACKLOG.md; } ;;
  jira)
    [ -f JIRA-SETUP.md ] || { cp templates/JIRA-SETUP-TEMPLATE.md JIRA-SETUP.md; sedi "s/\[Project Name\]/${ENAME}/g" JIRA-SETUP.md; }
    echo "note: backlog backend 'jira' selected — JIRA-SETUP.md written; configure it, then verify with 'sh conformance/tracker-contract.sh'. Declare the backend in CLAUDE.md §3." ;;
  *)
    [ -f TRACKER-SETUP.md ] || { cp templates/TRACKER-SETUP-TEMPLATE.md TRACKER-SETUP.md; sedi "s/\[Project Name\]/${ENAME}/g; s/\[BACKEND\]/${BACKLOG}/g" TRACKER-SETUP.md; }
    echo "note: backlog backend '$BACKLOG' selected (convention-tier) — TRACKER-SETUP.md written; map it via docs/work-tracking/adapters.md. Declare it in CLAUDE.md §3." ;;
esac
mkdir -p docs/architecture
[ -f docs/architecture/ADR-000-stack.md ] || { cp docs/ADR-000-EXAMPLE.md docs/architecture/ADR-000-stack.md; sedi "s/\[YYYY-MM-DD\]/${DATE}/g" docs/architecture/ADR-000-stack.md; }

# --- 5. wire CI from the chosen profile (platform-specific path/reference) ---
# The contract is the gate-ids; the platform is open (docs/operations/ci-platforms.md).
# github → .github/workflows/ci.yml ; gitlab → .gitlab-ci.yml at the repo root.
case "$CI" in
  github)
    mkdir -p .github/workflows
    # RATIFY-PARITY: the §13 control-plane-ratification gate is STACK-NEUTRAL (runs only conformance/*.sh),
    # so it installs for EVERY stack from ONE shared source — UNCONDITIONALLY, not gated on the profile's
    # ci.yml or on a per-stack copy (it used to live under profiles/typescript-node/, so 9 stacks silently
    # got no gate). CP-9: it ships as its OWN workflow — it must re-run on `pull_request_review` (an
    # approval IS the ratification signal) and a review must re-run THAT and nothing else; separate file =
    # structural containment. FAIL-LOUD if the source is gone: a kit that lost its governance source must
    # not silently produce an ungoverned adopter. (conformance/ratification-parity.sh locks this.)
    if [ -f profiles/ratification.yml ]; then
      cp_kit_replace profiles/ratification.yml .github/workflows/ratification.yml 'COPY & ADAPT|Sparkwright'
    else
      echo "incept: profiles/ratification.yml is MISSING — cannot install the §13 control-plane-ratification gate." >&2
      echo "        This is a broken kit distribution; refusing to produce an ungoverned project. Aborting." >&2
      exit 1
    fi
    if [ -f "profiles/${STACK}/ci.yml" ]; then
      cp_kit_replace "profiles/${STACK}/ci.yml" .github/workflows/ci.yml 'Kit-own CI|Sparkwright'
      [ -f "profiles/${STACK}/CODEOWNERS" ] && cp_kit_replace "profiles/${STACK}/CODEOWNERS" .github/CODEOWNERS 'COPY & ADAPT|@your-org' && warn_codeowners_placeholder .github/CODEOWNERS
    else
      echo "note: no profiles/${STACK}/ci.yml — add a CI workflow satisfying DEVELOPMENT-STANDARDS.md §14 (conformance/ci-gates.sh checks it)."
    fi
    ;;
  gitlab)
    if [ -f "profiles/${STACK}/ci.gitlab-ci.yml" ]; then
      cp_kit_replace "profiles/${STACK}/ci.gitlab-ci.yml" .gitlab-ci.yml 'Sparkwright'
      # GitLab reads CODEOWNERS from root, .gitlab/, or docs/ — .gitlab/ mirrors .github/.
      [ -f "profiles/${STACK}/CODEOWNERS" ] && { mkdir -p .gitlab; cp_kit_replace "profiles/${STACK}/CODEOWNERS" .gitlab/CODEOWNERS 'COPY & ADAPT|@your-org'; } && warn_codeowners_placeholder .gitlab/CODEOWNERS
    else
      echo "note: no profiles/${STACK}/ci.gitlab-ci.yml — add a .gitlab-ci.yml satisfying DEVELOPMENT-STANDARDS.md §14 (conformance/ci-gates.sh checks it; see docs/operations/ci-platforms.md)."
    fi
    ;;
esac

# --- 5a. copy a reference eval harness if the profile ships one (currently ml) ---
# Platform-independent; brownfield-safe (never clobber an existing evals/). The shipped runner
# is a deterministic offline scorer — swap in your model/judge per evals/rubric.md.
if [ -d "profiles/${STACK}/evals" ] && [ ! -d evals ]; then
  cp -R "profiles/${STACK}/evals" evals
  echo "copied reference eval harness: evals/ (deterministic offline scorer; the drop-in CI runs it as gate-eval — see evals/rubric.md)"
fi

# --- 5a2. copy the profile's starter scaffold so the drop-in CI is green on the empty project ---
# Brownfield-safe: each file is copied ONLY where absent (never clobbers existing app source).
# See profiles/${STACK}/scaffold/README.md for any one-time lockfile/wrapper step.
if [ -d "profiles/${STACK}/scaffold" ]; then
  ( cd "profiles/${STACK}/scaffold" && find . -type f ) | while IFS= read -r rel; do
    rel=${rel#./}
    # .gitignore is MERGED below (the project already has a root .gitignore), not copied here.
    if [ "$rel" = ".gitignore" ]; then continue; fi
    # Never copy stray build artifacts (a dirty dev tree may have them; they are gitignored but
    # `find` still sees them). Keeps an incepted project clean — no node_modules/coverage/pyc/etc.
    case "$rel" in
      node_modules/*|*/node_modules/*|dist/*|*/dist/*|build/*|*/build/*|coverage/*|*/coverage/*|\
      target/*|*/target/*|bin/*|*/bin/*|obj/*|*/obj/*|__pycache__/*|*/__pycache__/*|\
      .pytest_cache/*|*/.pytest_cache/*|.gradle/*|*/.gradle/*|.coverage|*.pyc) continue ;;
    esac
    if [ ! -e "$rel" ]; then
      mkdir -p "$(dirname "$rel")"
      cp "profiles/${STACK}/scaffold/$rel" "$rel"
    fi
  done
  # Merge the scaffold's ignore rules into the project .gitignore so the first `git add -A`
  # does not stage build artifacts (node_modules/target/bin/...). Idempotent.
  sgi="profiles/${STACK}/scaffold/.gitignore"
  if [ -f "$sgi" ]; then
    [ -f .gitignore ] || : > .gitignore
    # `|| [ -n "$pat" ]` processes a final line with no trailing newline (robust to any scaffold).
    while IFS= read -r pat || [ -n "$pat" ]; do
      case "$pat" in ''|\#*) continue ;; esac
      grep -qxF "$pat" .gitignore 2>/dev/null || printf '%s\n' "$pat" >> .gitignore
    done < "$sgi"
  fi
  echo "copied starter scaffold from profiles/${STACK}/scaffold/ (brownfield-safe) + merged its .gitignore rules"
  # Stack-specific one-time step to make the first CI push green (exact command, not a generic hint).
  case "$STACK" in
    python)      echo "  first-green step: uv lock && git add uv.lock && git commit -m 'lock deps'" ;;
    java-spring) echo "  first-green step: mvn wrapper:wrapper && git add mvnw .mvn && git commit -m 'add maven wrapper'" ;;
    kotlin)      echo "  first-green step: gradle wrapper && git add gradlew gradle && git commit -m 'add gradle wrapper'" ;;
    dotnet)      echo "  first-green step: dotnet restore (writes packages.lock.json) && git add '**/packages.lock.json' && git commit -m 'lock deps'" ;;
    go|rust)     echo "  no lockfile step — this scaffold is dependency-free and clone-green." ;;
  esac
  echo "  run it: see profiles/${STACK}/scaffold/README.md → 'See it run' (start the app, curl /healthz)"
else
  echo "warning: no starter scaffold for '${STACK}' — incept copied its CI but no app source, so CI will be RED until you add code. Non-service stacks (ml / data-engineering / terraform) ship a CI contract you populate, not a /healthz starter (see profiles/${STACK}.md §2)."
fi

# --- 5a2b. KW3 DB-archetype curation: a non-DB archetype (--no-db) strips the kit:db-backed CI region
#     (Postgres service + DATABASE_URL) from the emitted workflow AND removes the copied .db-backed
#     marker, so the drop-in CI ships no idle database service. DB-backed (the ts-node default) keeps
#     both. Runs after the CI + scaffold copy so both the workflow file and the marker are in place. ---
curate_db_backed "$DB_BACKED"

# --- 5a3. point at the profile's COPY-&-ADAPT container references (do NOT auto-copy) ---
# The profile's Dockerfile + compose.yaml are explicitly "COPY & ADAPT" references written for a
# real app (e.g. a cmd/server entrypoint, a DB-backed service) — NOT drop-in artifacts for the
# minimal /healthz starter. Auto-copying them would make `docker build` / `docker compose up` fail
# until adapted, so incept leaves them in the profile and the image-supply-chain CI gates are
# conditional on a Dockerfile existing (they skip until you add one). See profiles/${STACK}/ +
# the "Environments this stack needs" section in profiles/${STACK}.md / docs/STACK-SELECTION.md.
if [ -f "profiles/${STACK}/Dockerfile" ] || [ -f "profiles/${STACK}/compose.yaml" ]; then
  echo "note: containerize when ready — adapt profiles/${STACK}/Dockerfile + compose.yaml to your app, then the image-build CI gates activate (they skip until a Dockerfile is present)."
fi

# --- 5b0. ensure a git repo exists so the runtime guard can be installed (F6) ---
# The documented adopter path (adopter-export.sh → incept) starts from a plain directory, not a
# repo, so the pre-push hook below has nowhere to install and the summary would claim a guard that
# never landed. Initialize a repo here — announced — but ONLY when there is none: a brownfield
# adopter who ran incept inside an existing repo is left completely untouched (the is-inside-work-tree
# check is false only when there is no repo, so this never re-inits or clobbers an existing one).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init >/dev/null 2>&1 && echo "initialized a git repo (git init) so the runtime guard can be installed"
fi

# --- P1.2-pre: COMMIT the captured base onto the `kit-base` orphan branch ------------------------------
# The second half of the capture/commit split above: a repo is now guaranteed. This is the MERGE BASE
# every kit->adopter update pipe needs — the answer to "what tree did this adopter receive?". It is
# immutable by construction (a commit in a repo they own), works offline, and is automatically
# profile-correct (it IS what they got). Locked by conformance/kit-base.sh.
#
# NEVER TOUCHES THE WORKTREE OR THE ADOPTER'S INDEX: built through a TEMPORARY index with GIT_WORK_TREE
# pointed at the staging dir. No checkout, no stash, no `git add` against the real index. `git status` is
# byte-identical before and after.
commit_kit_base() {
  [ -n "$KIT_BASE_STAGE" ] && [ -d "$KIT_BASE_STAGE" ] || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  _kb_gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0

  # S2 (review #318): NEVER clobber an adopter's existing ref. On re-adoption or a prior kit-base install
  # the adopter may already have a `kit-base` branch or a `kit-base/v<VER>` tag; overwriting it is silent,
  # after-GC-unrecoverable data loss on a namespace we do not own. Refuse and say so.
  if GIT_DIR="$_kb_gd" git rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1; then
    echo "warning: a 'kit-base' branch already exists — NOT overwriting it (brownfield-safe)." >&2
    echo "         'kit-update' will use the existing base. Delete it first to re-record." >&2
    rm -rf "$KIT_BASE_STAGE" 2>/dev/null || true; return 0
  fi

  # The temp index path must NOT EXIST: git reads an existing EMPTY file as a CORRUPT index
  # ("index file smaller than expected"), not an empty one. mktemp creates it, so remove it.
  _kb_idx=$(mktemp) && rm -f "$_kb_idx" || return 0

  # The kit-base commit carries a KIT identity, supplied explicitly — NOT the adopter's. Two reasons:
  #   (1) a fresh `git init` adopter (the documented path) may have NO user.name/user.email configured,
  #       so a bare `git commit-tree` would FAIL — which is exactly what CI (no ambient identity) caught,
  #       and what a real adopter would hit. (2) This is the kit's snapshot, not the adopter's work, so
  #       it should not be attributed to them. Deterministic identity also keeps the commit reproducible.
  # C1 (review #318): `git add -Af` — force past core.excludesFile / info/exclude / .gitignore. The
  #   manifest is AUTHORITATIVE: every path we staged must be committed. A bare `git add -A` honours the
  #   adopter's ignore config and would SILENTLY DROP kit files (a global `*.md` ignore dropped 190),
  #   producing a base that reports success while being wrong — with no 3-way anchor for those files later.
  if ( cd "$KIT_BASE_STAGE" && GIT_DIR="$_kb_gd" GIT_INDEX_FILE="$_kb_idx" \
         GIT_WORK_TREE="$KIT_BASE_STAGE" git add -Af . ) 2>/dev/null &&
     _kb_tree=$(GIT_DIR="$_kb_gd" GIT_INDEX_FILE="$_kb_idx" git write-tree 2>/dev/null) &&
     _kb_cmt=$(GIT_DIR="$_kb_gd" GIT_AUTHOR_NAME='Sparkwright kit-base' GIT_AUTHOR_EMAIL='kit-base@sparkwright.local' \
         GIT_COMMITTER_NAME='Sparkwright kit-base' GIT_COMMITTER_EMAIL='kit-base@sparkwright.local' \
         git commit-tree "$_kb_tree" \
         -m "kit-base: pristine Sparkwright export v${VER} (the tree this project was adopted from)" 2>/dev/null) &&
     GIT_DIR="$_kb_gd" git update-ref refs/heads/kit-base "$_kb_cmt" '' 2>/dev/null; then
    # Create-only tag (no -f): S2 already refused if the branch existed; guard the tag independently.
    if GIT_DIR="$_kb_gd" git rev-parse --verify --quiet "refs/tags/kit-base/v${VER}" >/dev/null 2>&1; then :; else
      GIT_DIR="$_kb_gd" git tag "kit-base/v${VER}" "$_kb_cmt" >/dev/null 2>&1 || true
    fi
    echo "recorded kit-base: the pristine v${VER} export you adopted from (branch 'kit-base', tag 'kit-base/v${VER}')"
    echo "  It is the merge base 'kit-update' will diff against. Do not delete it. See docs/operations/kit-base.md."
  else
    echo "warning: could not record the kit-base branch — 'kit-update' will be unavailable for this project." >&2
  fi
  rm -f "$_kb_idx" 2>/dev/null || true
  rm -rf "$KIT_BASE_STAGE" 2>/dev/null || true
}
commit_kit_base

# --- 5b. install the runtime-guard git pre-push hook (default-on, brownfield-safe) ---
# Git hooks are not version-controlled, so incept installs the reference per-clone.
# Never clobber an existing hook (same discipline as the .claude/ brownfield path).
# GUARD_STEP carries the TRUTHFUL summary line for whichever path we take (mirrors the
# ${PROTECT_HINT} heredoc-variable pattern) so the next-steps summary can never claim an install
# that did not happen. Default = the honest "not installed" recovery; each branch overrides it.
GUARD_STEP="Runtime guard NOT installed — no git repo could be initialized. Run 'git init', then re-run 'sh scripts/incept.sh' to install it."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -f hooks/pre-push ]; then
    HOOK_DST=$(git rev-parse --git-path hooks/pre-push)
    # CP-4/D3: --git-path yields a path relative to the cwd (".git/hooks/pre-push", or
    # "../.git/hooks/pre-push" under --allow-nested). Absolutize it so every message below — and the
    # GUARD_STEP summary in particular — names the file ACTUALLY written, wherever it landed.
    _hook_dir=$(dirname "$HOOK_DST")
    if [ -d "$_hook_dir" ]; then
      HOOK_DST="$( CDPATH='' cd "$_hook_dir" && pwd -P )/$(basename "$HOOK_DST")"
    fi
    if [ -e "$HOOK_DST" ]; then
      echo "note: $HOOK_DST already exists — NOT overwriting (brownfield-safe). To chain the kit"
      echo "      guard, call 'sh \"$PWD/hooks/pre-push\"' from your existing hook, or replace it."
      GUARD_STEP="Local runtime guard NOT overwritten — $HOOK_DST already existed (brownfield-safe). Chain the kit guard from your existing hook, or replace it (see the note above)."
    else
      mkdir -p "$(dirname "$HOOK_DST")"
      if cp hooks/pre-push "$HOOK_DST" && chmod +x "$HOOK_DST"; then
        echo "installed runtime guard: $HOOK_DST (blocks force-push/push-to-main; bypass: git push --no-verify)"
        # CP-4/D3: DERIVED, never hardcoded. This line is the one the adopter actually reads (the
        # honest echo above scrolls past), and it used to claim ".git/hooks/pre-push" no matter where
        # the hook really landed. Under --allow-nested it now self-documents the parent path.
        GUARD_STEP="Local runtime guard installed at $HOOK_DST (force-push/push-to-main; bypass: --no-verify)."
      else
        echo "WARNING: could NOT install the runtime guard at $HOOK_DST (cp/chmod failed — check permissions/disk)." >&2
        GUARD_STEP="Runtime guard NOT installed — could not write $HOOK_DST (cp/chmod failed; check permissions). Re-run 'sh scripts/incept.sh' after fixing."
      fi
    fi
  else
    GUARD_STEP="Runtime guard NOT installed — hooks/pre-push not found in the kit tree. Re-export the kit (adopter-export.sh) to restore it, then re-run 'sh scripts/incept.sh'."
  fi
fi

# --- 5c. verify each selected harness adapter against the boundary contract (real project; non-fatal) ---
for _h in $HARNESS_LIST; do
  if sh conformance/harness-adapter.sh "adapters/${_h}" >/dev/null 2>&1; then
    echo "harness adapter '${_h}': conforms to the boundary contract."
  else
    echo "WARNING: harness adapter '${_h}' does NOT yet conform — close the gaps before you build:" >&2
    echo "         run 'sh conformance/harness-adapter.sh adapters/${_h}' for the specifics." >&2
    echo "         (The Inception-Done gate will block until it conforms.)" >&2
  fi
done

# --- 6. next steps (the judgment incept does NOT automate) ---
# Branch-protection guidance is platform-specific: branch-protection.sh / BRANCH-PROTECTION.md
# use the GitHub API; on GitLab the protected-branches equivalent is adopter-owned (honest
# coupling note — see docs/operations/ci-platforms.md).
case "$CI" in
  github) PROTECT_HINT="Protect main NOW — run the gh-api command in profiles/${STACK}/BRANCH-PROTECTION.md; verify with: sh conformance/branch-protection.sh" ;;
  gitlab) PROTECT_HINT="Protect main NOW — in GitLab: Settings → Repository → Protected branches (require merge request + pipeline success + an approval rule). branch-protection.sh uses the GitHub API; the GitLab equivalent is adopter-owned — see docs/operations/ci-platforms.md." ;;
esac
cat <<EOF

✅ Inception scaffolding complete for "${NAME}" (kit v${VER}, stack ${STACK}, CI ${CI}, mode ${MODE}, governance ${TEAM}).
Note: the kit's principles doc moved to ENGINEERING-PRINCIPLES.md; this new CLAUDE.md is YOUR project guide (charter, config, roles).

Do the judgment steps incept does NOT automate (see START-HERE.md):
  1. Write the charter prose in CLAUDE.md (problem, vision, success metrics, scope).
  2. Record the real stack decision in docs/architecture/ADR-000-stack.md.
  3. ${PROTECT_HINT}
  4. Declare per-project config in CLAUDE.md §3 (autonomy tiers, SLO, review routing, WIP).
  5. Assign roles in CLAUDE.md §4.
  6. ${GUARD_STEP}
     Other runtimes: pipe proposed commands through scripts/kit-guard (docs/operations/runtime-guards.md).

Verify: sh conformance/inception-done.sh
EOF
