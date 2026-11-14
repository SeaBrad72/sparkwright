#!/bin/sh
# prepush-lane.sh — the pre-push CI-parity lane (PREPUSH-CI-PARITY): the ci.yml SCANNER and
# CLASSIFIER, the TWO-STAGE CENSUS, the TWIN-TABLE READER, and the scrubbed serial RUNNER (the dash
# PATH shim, the work root, the ceiling/budget/floor, the listing, the heavy arms, the verdict).
#
# What it changes: NOTHING in the repo. It reads .github/workflows/ci.yml (or --ci-file / KIT_CI_FILE,
#   which must resolve under the repo root) and runs what it derived; its only writes are inside its own
#   mktemp work root, removed best-effort at exit (a leg asserts `git status --porcelain` and
#   `git for-each-ref refs/` are byte-identical across a run).
# Guardrails: the lane executes only what the closed grammar derived, and only as a FIXED argv built with
#   `set --` under `set -f` and an explicit IFS. It NEVER `eval`s or `sh -c`s text read from ci.yml, never
#   applies a job/step `env:` (design §3.1, security C15), and refuses a --ci-file outside the repo root
#   (rc 2); a malformed/unparseable ci.yml is UNVERIFIED, never a best-effort derivation. L4 DISCLOSURE:
#   the runtime guard judges the TOP-LEVEL command only — it never sees the invocations this lane would
#   spawn; the grammar below, not the guard, is what bounds them.
#
# DESIGN OF RECORD: docs/architecture/2026-09-17-prepush-ci-parity-design.md §3.1 (grammar,
# disqualifiers, buckets + precedence, KIT_CI_FILE), §3.7 (work root), §6 (controls), §7 (ceiling).
#
# BUCKETS, in precedence order: context -> heavy -> core-selftest -> untouched-selftest -> core-live.
#   `heavy` is CI JOB PLACEMENT (cf-*, non-vacuity, artifact-gate*, bootstrap, repo-ownership) PLUS any
#   invocation carrying a twin-table `heavy` row. `--derive` prints the SCANNER's answer, and the selftest
#   split is not one of its answers: "touched" is a property of the WORKING TREE, not of ci.yml, and making
#   --derive/--census depend on the tree would make the census verdict move with the listing. THE RUN
#   splits it — a run report prints `core-selftest` / `untouched-selftest`, never the merged label.
#
# JOB-CONDITIONAL — SETTLED: design §3.1 as amended by §10 on 2026-09-17 (the task-1 review round).
#   A job-level conditional `if:` DERIVES, carrying the over-run note. The ruling, as implemented:
#     · a STEP-level `if:` disqualifies the step — always (it gates THAT invocation);
#     · a JOB-level `if: false` disqualifies the job (CI never runs it, so deriving it would invent an
#       invocation CI does not have — the §3.1 `exclude`-twin clause);
#     · any OTHER job-level `if:` does NOT disqualify: it changes WHETHER CI reached the step, never WHAT
#       the step ran. The lane therefore OVER-runs a skipped job — the safe direction — and says so per
#       derived line (`CI-conditional job (if: …)`), which is §7's "says so per step".
#   Every other §3.1 disqualifier (`defaults:`, `container:`, `services:`, `strategy:`/matrix,
#   `continue-on-error:`, a sensitive or `${{ }}`-bearing `env:`) still disqualifies at BOTH levels,
#   because each changes what the invocation IS. MEASURED at this head: 229 derived (131 selftest · 86
#   core-live · 12 heavy) + 31 context — unchanged by the H1/M2/L5 fixes (`--derive` is byte-identical).
#
# WHAT IS PRINTED (tab-separated). FIVE fixed fields, then ZERO TO TWO optional NOTE fields:
#   1 bucket · 2 job · 3 step-line-no · 4 basename · 5 argv (space-joined, may be empty)
#   The notes are SELF-LABELLED and matched by their label PREFIX, never by field index — most derived
#   lines carry neither note, so field 6 is whichever note is present. Fixed RELATIVE order (env note
#   before conditional note) when both are present:
#   · `job env not applied: NAME[, NAME…]` — every literal, non-sensitive env name in scope, WORKFLOW,
#     job and step alike (env is never applied at ANY level, C15); the field keeps its `job env` label
#     whatever the scope of the name.
#   · `CI-conditional job (if: <expr>) — the lane may OVER-run it` — see JOB-CONDITIONAL above. <expr> is
#     the job `if:` value with any trailing YAML `#` comment and any tab stripped, so it cannot split a field.
#   A downstream reader splits on TAB, takes fields 1-5 positionally, and tests any further field against
#   those two prefixes.   context  <job> <line>  <basename|-> <reason>   (context lines carry no notes)
# Header lines start with `#`. A context line is printed only for a run: step (or block scalar) whose
# text MENTIONS `conformance/` — a `run: npm ci` is not the lane's business and is silently ignored.
#
# THREE PASSES over the workflow: the regular-file roster, then a PRE-SCAN for document-level keys
# (a top-level `defaults:`/`env:` binds the whole file wherever it sits — even after `jobs:`), then
# the emitting scan. A step key (`run:`/`if:`/`shell:`/`working-directory:`/`env:`) counts only at
# the step's own key indent: anything deeper is an action input under `with:`, not the step.
#
# THE TWO-STAGE CENSUS (--census; design §3.1/§3.2, security C6/C13/C19/C20). KIT-SELF ONLY — on a
# tree carrying neither kit marker (docs/ROADMAP-KIT.md, .github/workflows/golden-path.yml — the same
# detector green-on-clone.sh uses) it prints `N/A: census is kit-self (…)` and exits 0.
#   DENOMINATOR (tokenizer-INDEPENDENT, deliberately LOOSER than the grammar's basename charset): every
#     mention of conformance/[A-Za-z0-9._-]+\.sh on a non-comment, non-`name:` line, one entry per mention
#     with its line number — so an off-convention basename lands UNACCOUNTED (named), not invisible.
#   NUMERATOR: the derived invocations above.
#   ACCOUNTING: a mention is accounted only if (a) an invocation was DERIVED at that line with that
#     basename, or (b) a `twin`/`exclude` row of the SAME basename whose `ci-shape` is a SUBSTRING of that
#     physical line. Basename alone NEVER accounts (C19); a `heavy` row accounts NOTHING. A stale row
#     (ci-shape matching no denominator line), a malformed row, or a `heavy` row without an integer
#     budget-s is a census RED.
# THE TWIN TABLE: conformance/prepush-twins.tsv — its own header states the column contract.
#   `read_twins` grammar-checks EVERY row at read time and exposes the valid rows downstream (task 3's
#   runner) in the SAME seven tab-separated fields: basename·kind·ci-shape·local-argv·expect-rc·budget-s·
#   reason. A `twin` row's local-argv is judged by THE SCANNER'S OWN validator (the row is rendered as a
#   synthetic `sh conformance/<local-argv>` step and fed through the grammar above — there is no second
#   validator), after the closed placeholder set {listing} {branch} {base-board} {head} is neutralised;
#   any other `{`, or a `$`, backtick, quote or backslash, reds the census and the row is NEVER executed.
#   Placeholders are substituted into POSITIONAL PARAMETERS (`set --`), never into a string: see
#   subst_argv() — a branch named `x;$(touch …)` yields one literal token. ph_pass prints ONE TOKEN PER
#   LINE, so the contract assumes no substituted value contains a NEWLINE (git refnames forbid control
#   bytes; {listing}/{base-board} are lane-derived paths) — task 3's runner refuses one explicitly.
#
# Usage: sh conformance/prepush-lane.sh [--require | --best-effort]
#          [--green-on-clone | --exports | --non-vacuity <basename> | --slow | --warranted]
#          [--base <ref>] [--ci-file <path>] [--verbose]     # NO MODE FLAG = THE RUN
#        sh conformance/prepush-lane.sh --derive | --census [--ci-file <path>] | --selftest | --help
#        sh conformance/prepush-lane.sh --plan [--base <ref>]                      # the touched-readers selection; executes nothing
#        sh conformance/prepush-lane.sh --refresh-times [--ci-file <path>]         # pull CI step/job times and 30-day reds with gh (read-only)
#        sh conformance/prepush-lane.sh --log-report [--base <ref>]                # read-only: the run log's wall times and the merged-PR share; executes nothing, no network
# THE RUN LOG (SWAS-568, docs/plans/2026-11-12-prepush-run-log-568-plan.md): every run appends a start and an end record to $HOME/.local/state/sparkwright/prepush/<root-commit>/runs.log
#   (the live log plus three rotated files of about 1 MB each), so the wall time, the units and their peak RSS can be measured. A per-user measurement cache, never evidence: no switch turns it
#   off, it records no free text and no absolute path (core-selftest units carry their repo-relative target; floor_mb is a digits-only env bound), a write failure is dropped (never a verdict change), and the run never reads it. See the section `THE RUN LOG` below.
# THE TOUCHED-READERS ARM (SWAS-468 and its delta) closes the DEFAULT run: it fills PREPUSH_READERS_BUDGET_S (raise-only, default 300 s) with the
#   CI-derived checks, red-history checks first, then by measured time, and prints the rest as a `CI-ONLY (paste into the PR):` block with each
#   line's red cost and any TIMEOUT-RISK. SWAS-840 adds the NAMED readers (a derived check whose own script text, comment-stripped, names a touched path literally: it starts regardless of the fill
#   while it fits the cap) and the printed readers cap (TR_CAP, 600 s; the arm never runs past it). See the section `TOUCHED READERS` below for the tiers, the time table and its sources.
# THE TOUCHED SELFTESTS (SWAS-811, docs/architecture/2026-11-10-prepush-names-every-selftest-811-design.md): every listed top-level conformance/*.sh, scripts/*.sh or
#   hooks/pre-push whose comment-stripped text names --selftest is run by ONE call per target (`sh conformance/selftest-hermetic.sh <path>`, both faces): unmeasured targets first, then by
#   ascending measured time. SWAS-840 (docs/plans/2026-11-12-prepush-selftest-budget-840-plan.md): no budget cuts a target. PREPUSH_SELFTEST_BUDGET_S (raise-only, default 300 s) is only a printed
#   label (`over the 300 s budget: run anyway`); a call is bounded by ST_CEIL (3600 s, a plain constant), and a kill at it reads UNVERIFIED, never OK and never CI-bound. A target already killed
#   at the ceiling on these bytes (a censored row of ST_CEIL + 1 s or more) is named UNVERIFIED with no call. The `# touched-selftest roster: N (run: K, CI-bound: M, named: X, unmeasured: U)`
#   line counts them. Measured face seconds are kept per BLOB sha in the times state (a cache, never evidence): edited bytes are unmeasured again. On an adopter tree a touched scripts/ or
#   hooks/pre-push selftest is named, not run (kit tree only).
# THE DEFAULT RUN (no --warranted; PREPUSH-CORE-DEFAULT) proves the change's OWN surface, in this order:
#   the scoped lint of the listing's shell files (shellcheck.sh --listed; the full lock stays in CI) ->
#   the secret scan of <merge-base>..HEAD (`core-secretscan`: secret-scan-wired.sh --range, the PR-range scan
#   CI runs; gitleaks absent is UNVERIFIED and blocks, never a skip) -> the touched selftests (selftest-hermetic, one call per touched target) -> the board gates (when BACKLOG.md is touched) ->
#   the twins. It does NOT run the ~80 CI-derived core-live checks: it counts them in one `core-live: N …
#   NOT run` note. CI runs every one of them; `--warranted` runs them locally. Bucket derivation
#   (--derive, --census, the `buckets:` line) is unchanged — only which buckets EXECUTE differs. The OK
#   verdict STATES ITS SCOPE: `PARITY-CORE: OK (own surface — N CI-derived core-live check(s) not run; …)` on
#   a default run, `PARITY-CORE: OK (K arm(s) from cache, not executed this run)` when --warranted took arms
#   from the cache; FAIL/UNVERIFIED and an unqualified --warranted OK are unchanged.
# THE --warranted CACHE (PREPUSH-CORE-DEFAULT): an arm that PASSED is recorded under
#   $HOME/.local/state/sparkwright/prepush/<root-commit>/passed, keyed by a cksum of `git ls-tree -r HEAD`
#   minus the bookkeeping paths (BACKLOG.md, CHANGELOG.md, docs/reviews|plans|architecture/); the next
#   --warranted run on the same tree prints `SKIP … passed at <head> on this tree` for it. TWO KEYS: core-live
#   arms key on the FULL tree (whitespace-clean, owner-step-markers, check-links, roadmap-current,
#   decision-id-live and citation-* grade BACKLOG.md/CHANGELOG.md/docs/, so a bookkeeping-only commit re-runs
#   them); the heavy arms key on the tree minus those bookkeeping paths and say so on their SKIP line. A FAIL
#   (or a tool-absent `SKIP` output) is never recorded; any uncommitted/untracked change, an unusable/foreign/
#   world-writable state dir, or PREPUSH_NO_CACHE=1 means no cache (one note, every arm runs). Never the
#   default run, never the board gates. A LOCAL CONVENIENCE, NEVER EVIDENCE: per-user, forgeable, unread by CI.
# --warranted (PREPUSH-BATTERY-CHANGE-SCOPED, R-C11 condition 6): runs the CI-derived core-live checks (a
#   superset of the pre-PREPUSH-CORE-DEFAULT default) and then exactly the CLOSED,
#   listing-derived set of Tier-2 arms (warranted_derive) serially, in the fixed order
#   claims -> non-vacuity <b>.sh... -> green-on-clone. It takes NO operand, has NO environment
#   toggle, is rc 2 beside ANY single heavy-arm flag (in either order), and is unreachable from the
#   pre-push dial — the router forwards it as a fixed token, exactly like the other heavy flags.
#   Before each arm the memory floor is re-read (heavy_allowed) and a concurrency guard (heavy_busy)
#   refuses the arm if another heavy-shaped process (green-on-clone.sh, non-vacuity.sh,
#   adopter-export, claims-registry.sh, or `verify.sh --require`) is already running, excluding the
#   lane's own descendants. HONEST CEILINGS (R-C11 condition 5, disclosed not closed): (a) the
#   check-then-run is a RACE — another heavy process can start in the window between the check and
#   the exec; (b) a local user can cause a refusal (a denial of service) merely by running a process
#   whose command line contains one of the five listed strings; (c) the guard is NAME-BASED and
#   reads only what `ps` shows it — a restricted `ps` (another user's processes, a container
#   boundary) leaves it blind to heavy work it cannot see.
# THE HEAVY-ARM LOCK (SWAS-278b, design 2026-10-17-guard-dev-clone-prepush-design.md §6.2): the heavy phase of a run — core-selftest
#   (the default run too), core-live and every Tier-2 arm — holds ONE kernel flock on $HOME/.local/state/sparkwright/heavy-arm.lock,
#   taken before the first heavy unit and released after the last. A second run WAITS (polls every 15 s, prints the holder every 5 min)
#   within one 5400 s budget per run, then every remaining heavy unit is UNVERIFIED, never OK. flock(1), else /usr/bin/perl; neither,
#   a symlinked or foreign-owned lock path or an unsafe state dir is UNVERIFIED too. The lock is never broken or deleted; children run
#   with descriptor 9 closed; there is no ancestor re-entry and no environment knob. heavy_busy stays as a second check.
#   The --warranted cache honours only records its OWN tree produced (field 4 = the physical root; the SKIP line names it) and is off
#   when `git ls-files -v` shows a tag other than H, core.sparseCheckout is on, or a configured clean/smudge/process filter is applied to a tracked path
#   (`git check-attr`; a filter configured but applied by no path — a host-wide git-lfs — leaves it on; a check-attr that fails or prints an unreadable stream turns it off).
# Board gates (PREPUSH-BOARD-GATES-PARITY): when the listing contains BACKLOG.md the core also runs the
#   live conformance/backlog-*.sh / board-*.sh / roadmap-current.sh `check control` rows of verify.sh (no
#   --selftest) as `core-board` rows, derived from the registry; a FAIL fails PARITY-CORE, and zero derived
#   rows, or a registry row naming a board script that was not derived, is a FAIL.
#   Otherwise: `skipped: board gates — BACKLOG.md not in the diff`.
# Exit: 0 = PARITY-CORE: OK (or any verdict under --best-effort) / derived / census clean · 1 = a
#       core FAIL or UNVERIFIED, a census red, or a --selftest failure · 2 = --help (the kit's usage
#       convention), two heavy arms (--warranted included), --require with --best-effort, an unknown
#       flag (never forwarded), a --base outside the closed charset or naming no commit, a --ci-file
#       outside the repo root or
#       naming nothing, or any other usage error. POSIX sh; dash-clean.
set -eu

TAB=$(printf '\t')
CI_DEFAULT=".github/workflows/ci.yml"

usage() {
  sed -n '/^# Usage:/,/^#       naming nothing/p' "$0" | sed 's/^# \{0,1\}//'
  echo "See the header of $0 for the grammar, the buckets and the honest ceiling."
}

die2() { printf 'prepush-lane: %s\n' "$1" >&2; exit 2; }

# --------------------------------------------------------------- work root (design §3.7, minimal)
WORK=""
# SWAS-428: the live arm's process group dies with the lane (a terminal Ctrl-C reaches only the lane's own group now).
cleanup() {
  trap '' INT TERM HUP   # a second signal (a TERM storm) must not re-enter this body and abandon the kill half-done
  arm_trap_kill
  pool_interrupt_u       # SWAS-868: units finished but not yet printed are listed UNV
  rl_end INTERRUPTED -   # SWAS-568: a run that ends here without a verdict is logged INTERRUPTED (rc unknown); a no-op once the end record is written
  hl_release; [ -n "$WORK" ] && rm -rf "$WORK" 2>/dev/null; return 0   # best-effort: a trap that
}                                                                      # FAILS would override exit 0
trap 'cleanup' EXIT
# INT/TERM must EXIT (security L4): a handler that merely returns 0 resumes the script with its work
# root already deleted. 130/143 are the conventional signal rcs; EXIT then re-cleans harmlessly.
trap 'cleanup; exit 130' INT; trap 'cleanup; exit 143' TERM; trap 'cleanup; exit 129' HUP

# repo root, physical. Every path below is relative to it.
root_or_die() {
  _r=$(git rev-parse --show-toplevel 2>/dev/null) || die2 "not a git repository"
  ROOT=$(cd "$_r" && pwd -P) || die2 "cannot resolve the repo root"
}

# TWO RULES, deliberately SEPARATE (reviewer I-3). CONTAINMENT ("the file may not sit outside the
# root") binds in EVERY mode and runs before anything else. EXISTENCE ("the file is there") is a
# property of the tree being scanned, so it is deferred to the point of USE — --census applies its
# kit-self N/A first, and an adopter export with no .github/workflows/ci.yml is N/A rc 0, not rc 2.
#
# ci_path <path> -> the path RELATIVE to $ROOT, or rc 2 (CONTAINMENT only). Realpaths the directory
# (pwd -P) so a symlink or a `..` escape cannot leave the root (design §3.1 KIT_CI_FILE, security C8).
ci_path() {
  case $1 in
    /*) _a=$1 ;;
     *) _a=$ROOT/$1 ;;
  esac
  _d=$(dirname "$_a")
  _b=$(basename "$_a")
  _d=$(cd "$_d" 2>/dev/null && pwd -P) || die2 "--ci-file: no such directory: $(dirname "$_a")"
  _a=$_d/$_b
  case $_a in
    "$ROOT"/*) ;;
    *) die2 "--ci-file resolves outside the repo root: $_a" ;;
  esac
  printf '%s\n' "${_a#"$ROOT"/}"
}

# ci_exists_or_die <rel> — the EXISTENCE rule. A path that names NOTHING is a usage error (rc 2),
# like a missing directory; UNVERIFIED (rc 1) is reserved for a file that EXISTS but cannot be
# parsed (a symlink, a directory, a malformed body).
ci_exists_or_die() {
  [ -e "$ROOT/$1" ] || [ -L "$ROOT/$1" ] || die2 "--ci-file: no such file: $ROOT/$1"
}

# resolve_ci <path> -> rel, or rc 2 — both rules, for the modes that scan immediately (--derive).
resolve_ci() { _p=$(ci_path "$1") || exit $?; ci_exists_or_die "$_p"; printf '%s\n' "$_p"; }

# --------------------------------------------------------------------------------- the derivation
derive() {
  _ci=$1
  printf '# ci-file: %s\n' "$_ci"
  [ "$_ci" = "$CI_DEFAULT" ] || printf '# UNVERIFIED: derived from a non-CI file\n'
  if [ ! -f "$ROOT/$_ci" ] || [ -L "$ROOT/$_ci" ]; then
    printf '# UNVERIFIED: unparseable ci.yml (not a regular file)\n'; return 1
  fi
  if ! grep -q '^jobs:[ 	]*$' "$ROOT/$_ci"; then
    printf '# UNVERIFIED: unparseable ci.yml (no top-level jobs: block)\n'; return 1
  fi
  if grep -q "^[ ]*$TAB" "$ROOT/$_ci"; then
    printf '# UNVERIFIED: unparseable ci.yml (tab in indentation)\n'; return 1
  fi
  WORK=${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/prepush-XXXXXX")}
  # the existence oracle: REGULAR files only (-type f excludes symlinks), non-recursive.
  find conformance -maxdepth 1 -type f -name '*.sh' -print > "$WORK/scripts" 2>/dev/null || :
  # three passes: the file roster, then the pre-scan for document-level keys, then the emitting scan.
  LC_ALL=C awk "$SENSFN$AWKPROG" "$WORK/scripts" "$ROOT/$_ci" "$ROOT/$_ci"
}

# The §3.1 SENSITIVE-NAME oracle, factored out because BOTH awk programs below need it (the scanner
# judges a ci.yml `env:` name; read_twins judges an `env` ROW's NAME=value). One list, two readers.
# shellcheck disable=SC2016  # the awk program is DATA: nothing in it may expand in the shell.
SENSFN='
function sens(n,  u) { u=toupper(n)
  return (index(u,"TOKEN") || index(u,"SECRET") || index(u,"PASSWORD") ||
    u ~ /^(PATH|IFS|HOME|TMPDIR|BASH_ENV|ENV|CDPATH|LANG|NODE_OPTIONS|PYTHONPATH|PERL5OPT|RUBYOPT|HERMETIC_BASE)$/ ||
    u ~ /^(LD_|DYLD_|GIT_|GH_|KIT_|LC_|XDG_|SSH_|BOARD_CLAIM_|PREPUSH_)/) }
'

# The scanner. Reads the regular-file roster first (FNR==NR), then the workflow.
# shellcheck disable=SC2016  # the awk program is DATA: nothing in it may expand in the shell.
AWKPROG='
BEGIN { SEP=sprintf("%c",28); SQ=sprintf("%c",39); DQ=sprintf("%c",34); TB=sprintf("%c",9)
        jni=-1; jchild=-1; sdi=-1; skey=-1; envlvl=-1; insteps=0; instep=0; inblk=0 }
function trim(s) { sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
function ind(s,  i) { if (s ~ /^[ \t]*$/) return -1; i=match(s,/[^ ]/); return i-1 }
function key(s,  p) { p=index(s,":"); return p ? substr(s,1,p) : s }
function val(v) {
  return (v ~ /^[A-Za-z0-9._\/=-]+$/ && v !~ /(^|\/)\.\.(\/|$)/ && substr(v,1,1) != "/" && substr(v,1,1) != "~") }
function tokok(t,  q,e,p) {
  q=substr(t,1,1); e=substr(t,length(t),1)
  if ((q==SQ || q==DQ) && length(t) >= 2 && e==q) { t=substr(t,2,length(t)-2); if (index(t,q)) return 0 }
  if (t ~ /^--[a-z0-9-]+$/) return 1
  if (t ~ /^--[a-z0-9-]+=/) { p=index(t,"="); return val(substr(t,p+1)) }
  if (substr(t,1,1)=="-") return 0   # a BARE operand may not start with `-`: only the two --flag
  return val(t) }                    # forms above are accepted (the --base rule shape of design 3.1)
# unq — strip the ONE balanced quote pair tokok admits (M2): tokok validates the INNER value, so the raw token would hand the check literal quote characters the shell would never have passed on.
function unq(t,  q,e) { q=substr(t,1,1); e=substr(t,length(t),1)
  return ((q==SQ || q==DQ) && length(t) >= 2 && e==q) ? substr(t,2,length(t)-2) : t }
# parse <run value> -> 1 and sets g_base/g_argv, or 0 and sets g_r. The closed grammar, design 3.1.
function parse(s,  n,i,a,q,e) {
  sub(/\r$/,"",s); s=trim(s)
  if (index(s,"${{")) { g_r="carries a ${{ }} expression"; return 0 }
  if (index(s,TB))    { g_r="tab inside the run value"; return 0 }
  q=substr(s,1,1); e=substr(s,length(s),1)
  if ((q==SQ || q==DQ) && length(s) >= 2 && e==q) s=trim(substr(s,2,length(s)-2))
  n=split(s,a," ")
  if (n < 2 || a[1] != "sh") { g_r="not a bare `sh conformance/<x>.sh` invocation"; return 0 }
  if (a[2] !~ /^conformance\/[a-z0-9-]+\.sh$/) { g_r="script path outside the closed charset: " a[2]; return 0 }
  if (!(a[2] in SCR)) { g_r="no such regular file: " a[2]; return 0 }
  g_base=substr(a[2],13); sub(/\.sh$/,"",g_base); g_argv=""
  for (i=3; i<=n; i++) {
    if (!tokok(a[i])) { g_r="operand outside the closed charset: " a[i]; return 0 }
    g_argv = g_argv (g_argv=="" ? "" : " ") unq(a[i]) }
  return 1 }
function heavy(j) {
  return (j ~ /^cf-/ || j ~ /^artifact-gate/ || j=="non-vacuity" || j=="bootstrap" || j=="repo-ownership") }
function srec(ok,ln,b,a,r,m) {   # a context record is kept only when the text MENTIONED conformance/
  if (!ok && !m) return
  sn++; sb[sn] = ok SEP ln SEP b SEP a SEP r }
function dset(sc,r) { if (sc=="job") { if (jdisq=="") jdisq=r }
                      else if (sc=="workflow") { if (wdisq=="") wdisq=r }
                      else { if (sdisq=="") sdisq=r } }
function addl(a,b) { return (b=="" ? a : (a=="" ? b : a ", " b)) }
function addenv(sc,n) { if (sc=="job") jenv=addl(jenv,n)
                        else if (sc=="workflow") wenvn=addl(wenvn,n)
                        else senv=addl(senv,n) }
# pscx — a MULTI-LINE PLAIN SCALAR `run:` (H1). YAML folds a deeper continuation line into the SAME
# scalar, so `run: sh conformance/x.sh` + `  --dir /etc` is ONE command: deriving the first physical line alone would run a TRUNCATED invocation and report it OK. The WHOLE step is context.
function pscx(  pf) { if (psi>0) { split(sb[psi],pf,SEP)
    sb[psi]="0" SEP pf[2] SEP "-" SEP "" SEP "multi-line plain scalar" }
  psi=0 }
# PRE-SCAN pass (the SECOND read of the workflow, before any emission): document-level keys bind the
# whole file wherever they sit, so `defaults:`/`env:` placed AFTER jobs: must still disqualify jobs
# that a single forward pass would already have flushed.
function prescan(  l,t2,i2,n2) {
  l=$0; sub(/\r$/,"",l)
  if (l ~ /^[ \t]*$/) return
  t2=trim(l); if (substr(t2,1,1)=="#") return
  i2=ind(l)
  if (i2==0) { wenv=0
    if (t2 ~ /^defaults:/) dset("workflow","workflow-level defaults:")
    else if (t2 ~ /^env:/) wenv=1
    return }
  if (!wenv) return
  n2=key(t2); sub(/:$/,"",n2)
  if (index(l,"${{")) dset("workflow","workflow env value carries a ${{ }} expression: " n2)
  else if (sens(n2)) dset("workflow","workflow env carries a sensitive name: " n2)
  else addenv("workflow",n2) }
function closeblk(  i,f) {
  if (blkbad != "") srec(0,blkline,"-","","block scalar is not all-conforming: " blkbad,blkm)
  else if (blkn==0) srec(0,blkline,"-","","empty block scalar",blkm)
  else for (i=1; i<=blkn; i++) { split(bb[i],f,SEP); srec(1,f[1],f[2],f[3],"",1) }
  inblk=0; blkn=0; blkbad="" }
function sflush(  i,f) {
  for (i=1; i<=sn; i++) { split(sb[i],f,SEP)
    if (f[1]=="1" && sdisq != "") { f[1]="0"; f[3]="-"; f[4]=""; f[5]=sdisq }
    jn++; jb[jn] = f[1] SEP f[2] SEP f[3] SEP f[4] SEP f[5] SEP senv }
  sn=0; sdisq=""; senv=""; instep=0 }
function jflush(  i,f,bk,nt,d) {
  if (inblk) closeblk()
  sflush()
  d = (wdisq != "" ? wdisq : jdisq)
  for (i=1; i<=jn; i++) { split(jb[i],f,SEP)
    if (f[1]=="1" && d != "") { f[1]="0"; f[3]="-"; f[4]=""; f[5]=d }
    if (f[1]=="0") { printf "context\t%s\t%s\t%s\t%s\n", job, f[2], f[3], f[5]; continue }
    bk = heavy(job) ? "heavy" : (f[4] ~ /(^| )--selftest( |$)/ ? "selftest" : "core-live")
    nt = addl(addl(wenvn,jenv),f[6])          # workflow, job, step names alike: env is NEVER applied
    nt = (nt=="" ? "" : "\tjob env not applied: " nt)
    if (jcond != "") nt = nt "\tCI-conditional job (if: " jcond ") — the lane may OVER-run it"
    printf "%s\t%s\t%s\t%s\t%s%s\n", bk, job, f[2], f[3], f[4], nt }
  jn=0; jdisq=""; jenv=""; jcond=""; envlvl=-1 }
FNR==1 { nfile++ }
nfile==1 { SCR[$0]=1; next }    # pass 1: the regular-file roster
nfile==2 { prescan(); next }    # pass 2: document-level keys
{                               # pass 3: the emitting scan
  line=$0; sub(/\r$/,"",line)
  if (inblk) {
    if (line ~ /^[ \t]*$/) next
    if (ind(line) > blkind) {
      t=trim(line)
      if (substr(t,1,1)=="#") next
      if (index(line,"conformance/")) blkm=1
      if (blkbad=="") { if (parse(line)) { blkn++; bb[blkn]=FNR SEP g_base SEP g_argv }
                        else blkbad=g_r }
      next }
    closeblk() }
  if (line ~ /^[ \t]*$/) next
  t=trim(line); if (substr(t,1,1)=="#") next
  i=ind(line)
  if (i==0 && t ~ /^jobs:[ \t]*$/) { jflush(); injobs=1; jni=-1; job=""; next }
  if (i==0) { if (injobs) { jflush(); injobs=0 } next }
  if (!injobs) next
  if (jni<0) jni=i
  if (i<jni) { jflush(); injobs=0; next }
  dash = (t ~ /^- / || t=="-")
  # H1, BEFORE any flush: ANY line after a plain-scalar `run:` that is deeper than the step key is the
  # SECOND LINE of that scalar — a `- `-led one included (Psych folds it); a sibling step or key never is.
  if (pscont) { pscont=0; if (i>skey) { pscx(); next } }
  if (i==jni && !dash) { jflush(); job=key(t); sub(/:$/,"",job)
                         jchild=-1; insteps=0; sdi=-1; envlvl=-1; next }
  if (jchild<0 && i>jni) jchild=i
  if (i==jchild && !dash) {
    sflush(); insteps=0; envlvl=-1
    if (t ~ /^steps:/) { insteps=1; sdi=-1 }
    # A JOB-level `if:` is NOT a blanket disqualifier — see the JOB-CONDITIONAL note in the header.
    # `if: false` (the enumerated never-runs token, normalised like verify-enforced-wired.sh::jobif)
    # IS: CI never runs it, so deriving it would invent an invocation CI does not have.
    else if (t ~ /^if:/) { v2=substr(t,4); gsub(/[ \t]/,"",v2); gsub(SQ,"",v2); gsub(DQ,"",v2)
                           if (tolower(v2)=="false") dset("job","job if: false")
                           else { jcond=trim(substr(t,4))          # strip a trailing YAML comment and
                                  sub(/[ \t]+#.*$/,"",jcond)       # any tab: the note is ONE field
                                  gsub(/\t/," ",jcond); jcond=trim(jcond) } }
    else if (t ~ /^(defaults|container|services|strategy|continue-on-error):/) dset("job","job key " key(t))
    else if (t ~ /^env:/) { envlvl=i; envscope="job" }
    next }
  if (envlvl>=0 && i>envlvl) {
    nm=key(t); sub(/:$/,"",nm)
    if (index(line,"${{")) dset(envscope, envscope " env value carries a ${{ }} expression: " nm)
    else if (sens(nm)) dset(envscope, envscope " env carries a sensitive name: " nm)
    else addenv(envscope, nm)
    next }
  if (envlvl>=0 && i<=envlvl) envlvl=-1
  if (!insteps) next
  if (dash && (sdi<0 || i<=sdi)) { sflush(); sdi=i; instep=1; skey = (t ~ /^- /) ? i+2 : -1 }
  if (!instep) next
  # A lone `-` OPENS the step but carries no key: leave skey unset so the FIRST real key line (at its
  # own, deeper indent) sets it — defaulting skey to the dash indent would drop that key silently.
  if (t=="-") next
  k=t; sub(/^- /,"",k); ki = (t ~ /^- /) ? i+2 : i
  # A FLOW-MAPPING step (`- {run: …}`) is outside the block-mapping grammar: it derives nothing, and
  # without this it would EMIT nothing either, vanishing silently on an adopter tree (no census) — L5.
  if (substr(k,1,1)=="{") { if (index(line,"conformance/")) srec(0,FNR,"-","","flow-mapping step",1)
                            next }
  # A step key is judged ONLY at the key indent of that step: a `run:`/`shell:` nested deeper is an
  # action input under `with:` (or any other mapping), never the command of the step (design §3.1).
  if (skey<0) skey=ki
  if (ki != skey) next
  if (k ~ /^env:/) { envlvl=ki; envscope="step"; next }
  if (k ~ /^(if|working-directory|shell|continue-on-error):/) { dset("step","step key " key(k)); next }
  if (k ~ /^run:/) {
    v=k; sub(/^run:[ \t]*/,"",v); m = index(line,"conformance/") ? 1 : 0
    if (v ~ /^[|>][-+]?[ \t]*$/) {
      inblk=1; blkind=ki; blkline=FNR; blkn=0; blkm=0
      blkbad = (substr(v,1,1)==">" ? "folded scalar" : "") }
    else { pn0=sn
           if (parse(v)) srec(1,FNR,g_base,g_argv,"",m); else srec(0,FNR,"-","",g_r,m)
           pscont=1; psi=(sn>pn0 ? sn : 0) }   # arm the continuation test for the NEXT line
    next }
}
END { jflush() }
'

# =========================================================== the twin table + the two-stage census
TWINS_REL="conformance/prepush-twins.tsv"

# read_twins: validates EVERY row of the twin table at read time. Valid rows land in $WORK/twins.ok
# in the SAME seven tab-separated fields the table carries (the shape task 3's runner consumes);
# every malformed row lands in $WORK/twins.err as `<line>: <reason>` and reds the census. Nothing is
# ever executed here. The `env` NAME is judged by the SAME sens() oracle the scanner uses.
# shellcheck disable=SC2016  # the awk program is DATA: nothing in it may expand in the shell.
TWPROG='
BEGIN { FS="\t"; SQ=sprintf("%c",39); DQ=sprintf("%c",34); BT=sprintf("%c",96)
        split("listing branch base-board head",PH," ")
        # ENT: every conformance/*.sh entry of ANY kind. CIT: the CI file text. CIOK=0 (unreadable) never carves.
        while ((getline ln < ENTRIES) > 0) ENT[ln]=1
        while ((getline ln < HEADLS) > 0) HD[ln]=1      # HD: what HEAD tracks under conformance/
        ln = ""; CIOK = (CIF != "" && (getline ln < CIF) >= 0); CIT = ""
        if (CIOK) { CIT = ln; while ((getline ln < CIF) > 0) CIT = CIT "\n" ln } }
# dupph — a token may carry a placeholder AT MOST ONCE. This is a CONSERVATIVE AUTHORING RESTRICTION,
# not a correctness guard: ph_pass re-scans the remainder after each substitution, so a repeat would in
# fact be substituted correctly. The restriction keeps the argv of a row READABLE AS WRITTEN — one
# occurrence per placeholder per token, so the token a reviewer sees in the table has the same shape
# as the token the runner executes. (No apostrophes in this awk program: it is a single-quoted string.)
# Widening the rule later is safe; narrowing it once rows exist is not.
function dupph(s,   n,i,j,tok,p,c,r) {
  n=split(s,tok," ")
  for (i=1;i<=n;i++) for (j=1;j<=4;j++) {
    p="{" PH[j] "}"; c=0; r=tok[i]
    while (index(r,p)) { c++; r=substr(r,index(r,p)+length(p)); if (c>1) return 1 }
  }
  return 0 }
NR==FNR { SCR[$0]=1; next }
/^[ \t]*$/ { next }
/^#/ { next }
{
  e=""; b=$1; k=$2; shp=$3; la=$4; xrc=$5; bs=$6; rsn=$7
  miss = !(("conformance/" b ".sh") in SCR); cv = 0
  if (NF != 7) e="expected 7 tab-separated fields, got " NF
  else if (b !~ /^[a-z0-9-]+$/) e="basename outside [a-z0-9-]+: " b
  else if (k !~ /^(twin|exclude|heavy|env)$/) e="unknown kind: " k
  else if (xrc != "" && xrc !~ /^[0-9]+$/) e="expect-rc is not an integer: " xrc
  else if (k=="twin" && (shp=="" || la=="")) e="a twin row needs a ci-shape and a local-argv"
  else if (k=="exclude" && (shp=="" || rsn=="")) e="an exclude row needs a ci-shape and a reason"
  else if (k=="heavy" && bs !~ /^[0-9]+$/) e="a heavy row needs an integer budget-s: [" bs "]"
  else if (k=="env" && la !~ /^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._\/=-]+$/) e="an env row needs a local-argv NAME=value: [" la "]"
  else if (k=="env" && sens(substr(la,1,index(la,"=")-1))) e="an env row may not carry a sensitive name: " substr(la,1,index(la,"=")-1)
  else if (k=="twin" && dupph(la)) e="local-argv repeats a placeholder within one token (at most one occurrence per token): " la
  else if (k=="twin") { t=la
    gsub(/\{listing\}|\{branch\}|\{base-board\}|\{head\}/,"placeholder",t)
    if (index(t,"{") || index(t,"}") || index(t,"$") || index(t,SQ) || index(t,DQ) || index(t,BT) || index(t,"\\"))
      e="local-argv carries a forbidden character, or a placeholder outside {listing} {branch} {base-board} {head}: " la }
  # THE CARVE, decided LAST: only a row that passed EVERY test above, off the kit tree, whose script is truly
  # absent (no file, no symlink, no directory) and which the CI file of this tree never names. Anything else is an error.
  if (e == "" && miss) {
    if (OFFKIT && CIOK && !(("conformance/" b ".sh") in ENT) && !(("conformance/" b ".sh") in HD) && !index(CIT, "conformance/" b ".sh")) cv = 1
    else e="not a regular file under the repo root: conformance/" b ".sh"
  }
  if (e != "") print FNR ": " e > ERR; else if (cv) print $0 > CARVED; else print $0 > OK
}
'
# off_kit — THE one kit-marker test (census and the twin reader both call it): a tree carrying neither
# marker is not the kit. Both markers are control-plane and export-ignored, so an adopter tree lacks both.
off_kit() { [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; }
# read_twins also CARVES (off the kit tree only): a row whose ONLY defect is a script this tree does not
# carry goes to $WORK/twins.carved — counted and noted by the run, never to twins.ok, never executed.
# read_twins [ci-file] — the CI file the lane derives from is DATA for the carve test; none given (census) = no carve.
read_twins() {
  : > "$WORK/twins.ok"; : > "$WORK/twins.err"; : > "$WORK/twins.carved"
  [ -f "$TWINS_REL" ] || return 0
  _off=0; ! off_kit || _off=1
  # FAIL CLOSED: if the working-tree listing or HEAD listing cannot be built, nothing carves.
  find conformance -maxdepth 1 -name '*.sh' > "$WORK/twins.entries" 2>/dev/null || { : > "$WORK/twins.entries"; _off=0; }
  git ls-tree --name-only HEAD conformance/ > "$WORK/twins.head" 2>/dev/null || { : > "$WORK/twins.head"; _off=0; }
  LC_ALL=C awk -v OK="$WORK/twins.ok" -v ERR="$WORK/twins.err" -v CARVED="$WORK/twins.carved" -v OFFKIT="$_off" \
    -v ENTRIES="$WORK/twins.entries" -v HEADLS="$WORK/twins.head" -v CIF="${1:-}" "$SENSFN$TWPROG" "$WORK/scripts" "$TWINS_REL"
}
# carved_note — one honest line when rows were carved: the count, never the rows.
carved_note() {
  [ -s "$WORK/twins.carved" ] || return 0
  printf '# twin rows carved: %s (their scripts are kit-only and not in this tree)\n' \
    "$(wc -l < "$WORK/twins.carved" | tr -d ' ')"
}

fld() { printf '%s\n' "$2" | cut -f"$1"; }
neutralise() { printf '%s\n' "$1" | sed -e 's/{listing}/placeholder/g' -e 's/{branch}/placeholder/g' \
  -e 's/{base-board}/placeholder/g' -e 's/{head}/placeholder/g'; }

# twin_exec_check — a `twin` row's local-argv is judged by THE SCANNER'S OWN validator, not a second
# one: each row is rendered as a synthetic `sh conformance/<local-argv>` step of a throwaway workflow
# (placeholders neutralised first) and fed through the very awk program --derive uses. A row that does
# not come back DERIVED, with its own basename, is refused: reported, dropped from twins.ok, never run.
twin_exec_check() {
  { printf 'name: twin-grammar\njobs:\n  t:\n    steps:\n'
    while IFS= read -r _row; do
      if [ "$(fld 2 "$_row")" = twin ]
      then printf '      - run: sh conformance/%s\n' "$(neutralise "$(fld 4 "$_row")")"
      else printf '      - run: sh conformance/__not-a-twin-row__.sh\n'   # a filler: keeps the
      fi                                                                 # step line number = 4 + row
    done < "$WORK/twins.ok"
  } > "$WORK/tg.yml"
  LC_ALL=C awk "$SENSFN$AWKPROG" "$WORK/scripts" "$WORK/tg.yml" "$WORK/tg.yml" > "$WORK/tg.out" || :
  _i=0; : > "$WORK/twins.keep"
  while IFS= read -r _row; do
    _i=$((_i+1))
    if [ "$(fld 2 "$_row")" = twin ] &&
       ! grep -q "^[a-z-]*$TAB""t$TAB$((4+_i))$TAB$(fld 1 "$_row")$TAB" "$WORK/tg.out"; then
      printf '%s: twin row is NOT EXECUTABLE under the §3.1 grammar (refused, never run): %s\n' \
        "$(fld 1 "$_row")" "$(fld 4 "$_row")" >> "$WORK/twins.err"
      continue
    fi
    printf '%s\n' "$_row" >> "$WORK/twins.keep"
  done < "$WORK/twins.ok"
  cat "$WORK/twins.keep" > "$WORK/twins.ok"
}

# The accounting. THREE inputs: the seeded twin rows, the --derive output, the workflow itself.
# shellcheck disable=SC2016  # the awk program is DATA: nothing in it may expand in the shell.
CENPROG='
BEGIN { FS="\t"; ns=0; nh=0; n=0; nd=0; nt=0; nx=0; nu=0; nst=0 }
FNR==1 { nfile++ }
nfile==1 { if ($0 ~ /^#/) next
           if ($2=="heavy") { nh++; HB[++nhb]=$1; next }
           if ($2=="twin" || $2=="exclude") { ns++; SB[ns]=$1; SK[ns]=$2; SH[ns]=$3; SR[ns]=$7; U[ns]=0 }
           next }
nfile==2 { if ($0 ~ /^#/ || $1=="context") next; D[$3 SUBSEP $4]=1; DB[$4]=1; next }
{                                       # the DENOMINATOR: tokenizer-independent, by construction
  l=$0; sub(/\r$/,"",l); t=l; sub(/^[ \t]+/,"",t)
  if (substr(t,1,1)=="#") next
  if (t ~ /^-[ ]*name:/ || t ~ /^name:/) next
  s=l
  while (match(s,/conformance\/[A-Za-z0-9._-]+\.sh/)) {
    m=substr(s,RSTART,RLENGTH); s=substr(s,RSTART+RLENGTH)
    b=substr(m,13); sub(/\.sh$/,"",b); n++
    if ((FNR SUBSEP b) in D) { nd++; printf "%s\t%s\tderived\n", FNR, b; continue }
    hit=0
    for (i=1; i<=ns; i++) if (SB[i]==b && SH[i] != "" && index(l,SH[i])) { U[i]=1; hit=i; break }
    if (hit && SK[hit]=="twin")   { nt++; printf "%s\t%s\ttwin:%s\n", FNR, b, SB[hit]; continue }
    if (hit)                      { nx++; printf "%s\t%s\texclude:%s\n", FNR, b, SR[hit]; continue }
    nu++; printf "%s\t%s\tUNACCOUNTED\n", FNR, b
  }
}
END {
  for (i=1; i<=ns; i++) if (!U[i])
    { nst++; printf "# STALE ROW: %s %s — its ci-shape matches no denominator line: %s\n", SB[i], SK[i], SH[i] }
  # A `heavy` row annotates an invocation IN THE NUMERATOR (design §3.2). A row whose basename no
  # longer derives from ci.yml annotates nothing — and would leave the --slow arm silently INERT.
  for (i=1; i<=nhb; i++) if (!(HB[i] in DB))
    { nst++; printf "# STALE HEAVY ROW: %s — its check no longer derives from ci.yml, so --slow would be inert\n", HB[i] }
  printf "# census: %d mentions · %d derived · %d twin · %d exclude · %d UNACCOUNTED · %d heavy rows · %d stale rows\n",
    n, nd, nt, nx, nu, nh, nst
  if (nu > 0 || nst > 0) exit 1
}
'
census() {
  # CONTAINMENT first, in EVERY mode: off-kit the N/A below would else swallow it (rc 0, not rc 2).
  # EXISTENCE is deferred past the N/A — an off-kit tree with no ci.yml at all is N/A, not an error.
  _rel=$(ci_path "$1") || exit $?
  # KIT-SELF ONLY (C13) — the SAME two markers green-on-clone.sh reads, same OR-of-markers shape;
  # golden-path.yml is control-plane + export-ignored, so it cannot be spoofed.
  if off_kit; then
    echo "N/A: census is kit-self (this tree carries neither kit marker: docs/ROADMAP-KIT.md, .github/workflows/golden-path.yml)"
    return 0
  fi
  ci_exists_or_die "$_rel"
  WORK=${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/prepush-XXXXXX")}
  derive "$_rel" > "$WORK/derive.out" || { cat "$WORK/derive.out"; return 1; }
  sed -n '/^#/p' "$WORK/derive.out"
  read_twins
  twin_exec_check
  # the seed line keeps the awk file counter honest when the table is absent or wholly malformed.
  { echo '# seeded'; cat "$WORK/twins.ok"; } > "$WORK/cen.twins"
  _crc=0
  LC_ALL=C awk "$CENPROG" "$WORK/cen.twins" "$WORK/derive.out" "$ROOT/$_rel" || _crc=$?
  if [ -s "$WORK/twins.err" ]; then
    sed 's/^/# TWIN-TABLE MALFORMED: /' "$WORK/twins.err"; _crc=1
  fi
  return "$_crc"
}

# subst_argv <local-argv> — THE one code path that turns a twin row's argv into the argv task 3 will
# execute. It word-splits under `set -f` with an explicit IFS, substitutes the four closed placeholders
# into POSITIONAL PARAMETERS, and prints ONE TOKEN PER LINE. No eval, no re-splitting of a substituted
# value: a branch named `x;$(touch /tmp/pwned)` becomes ONE literal token and runs nothing (§3.2, C2).
PH_LISTING=""; PH_BRANCH=""; PH_BASE_BOARD=""; PH_HEAD=""
# ph_pass — ONE left-to-right pass: the EARLIEST placeholder in the UNSCANNED remainder is replaced and
# the cursor moves past the substituted text, never re-scanned. So a value that itself looks like a
# placeholder (PH_BRANCH='v{head}') stays literal — no second-order expansion (§3.2, C2).
ph_pass() { _r=$1; _o=""
  while :; do
    _bn=""; _bp=""
    for _ph in listing branch base-board head; do
      case $_r in *"{$_ph}"*) _pre=${_r%%"{$_ph}"*} ;; *) continue ;; esac
      if [ -z "$_bn" ] || [ "${#_pre}" -lt "${#_bp}" ]; then _bn=$_ph; _bp=$_pre; fi
    done
    [ -n "$_bn" ] || break
    case $_bn in
      listing) _v=$PH_LISTING ;; branch) _v=$PH_BRANCH ;;
      base-board) _v=$PH_BASE_BOARD ;; head) _v=$PH_HEAD ;;
    esac
    _o=$_o$_bp$_v; _r=${_r#*"{$_bn}"}
  done
  printf '%s\n' "$_o$_r"
}
subst_argv() {
  _sa=$1; _oifs=$IFS; set -f; IFS=' '
  # shellcheck disable=SC2086  # deliberate: the closed-charset argv is split into ARGV, never eval'd.
  set -- $_sa
  IFS=$_oifs; set +f
  for _t in "$@"; do ph_pass "$_t"; done
}

# ============================================================================= THE RUNNER (task 3)
# The DEFAULT mode (`sh conformance/prepush-lane.sh` — what `sparkwright prepush` invokes) runs the change's
# OWN surface (scoped shellcheck, touched selftests, board gates, twins; PREPUSH-CORE-DEFAULT) and the
# CI-derived core-live checks only under --warranted. Everything it EXECUTES comes from what the scanner
# derived, and nothing else: serially, under a dash PATH shim, in a scrubbed environment,
# inside one work root, a per-invocation wall-clock ceiling and a free-memory floor (design §3.3/§3.4/
# §3.7). The `selftest` bucket the SCANNER prints is a run-time question, so it is SPLIT HERE by the
# touched set and the merged label never appears in a run report: `core-selftest` (one call per touched target to
# selftest-hermetic.sh, SWAS-811 — both faces, never re-implemented) and `untouched-selftest` (listed,
# not run). The ONLY `&`s in this file are in run_bg (the scrubbed subshell, backgrounded so a trapped INT/TERM
# interrupts the `wait` at once) and inside run_timed (the arm, in its own process group, and its watchdog), plus, at J >= 2 only, in pool_start (a pooled unit's subshell, SWAS-868).
# Each `wait` keeps execution strictly serial at J = 1; selftest_bounded_fanout proves it by OBSERVATION.
# SWAS-868 (THE POOL, docs/plans/2026-11-13-prepush-parallel-pool-868-plan.md): at J >= 2 (J is DERIVED from this machine, never set; see pool_j) the core-selftest candidates and, under --warranted, the core-live checks run
#   at most J at a time, each in its own scratch dirs and control dir, from the `( ... ) &` in pool_start; each unit is decided at its reap and recorded in queue order; every rc FAIL and every ceiling kill that passes the
#   half-ceiling rule runs once more, serially, and a serial pass reads RACE, never a silent OK. The touched readers, the board gates, the twins and the heavy arms stay serial. J = 1 (cores, memory or perl unreadable) is today's lane.
# THE CEILING KILL (SWAS-428, docs/architecture/2026-10-28-prepush-orphan-428-design.md): an arm runs in a process group of its own (a
#   perl setpgrp wrapper), and a ceiling hit snapshots the descendants, TERMs and CONTs the group, waits up to 5 s, re-snapshots, KILLs the
#   group and the pids still in the lineage, and CONFIRMS. A kill it cannot confirm reads UNVERIFIED. A terminal Ctrl-C or a TERM to the
#   lane kills the live arm's group too. HONEST CEILINGS, stated and not closed: (1) a descendant that double-forks into a NEW group after
#   the snapshot is not reached; (2) pid reuse is narrowed by the re-snapshot, not closed (milliseconds between it and the KILL);
#   (3) a signal in the first milliseconds, before the wrapper's setpgrp, finds no group; (4) SIGKILL cannot be trapped: the watchdog polls the
#   lane pid once a second and kills the arm if the lane alone died, but a SIGKILL to the lane's whole GROUP takes the watchdog with it (running
#   it in a group of its own would need a second wrapper per arm: judged too heavy for a case a person has to type), and the arm then runs on;
#   (4b) the kill state lives in $WORK/ctl and an arm's TMPDIR is $WORK/tmp, so an arm cannot forge it by convention, not by a sandbox;
#   (4c) the trap re-entry mutant is not graded; SWAS-467 owns it (K10 stays: a TERM storm still ends in the KILL);
#   (4d) a pgid is signalled only if it is not the lane's own group or its PARENT's group; a pgid read from a file only if its pid is a descendant of the lane;
#   (4e) SWAS-868: a co-running arm can write to another pooled unit's output and control files while that unit runs, up to its reap (for example append `TARGET: <path> (both faces)` or rewrite a kill note). The pool reads everything at the
#   unit's reap, which closes the window AFTER the reap, not before it. The rc value is read by the parent; what produces it is not contained: a co-runner can also reach another unit's scratch dirs (u<n>/tmp, empty, gh) and so
#   influence its exit status, and can plant a symlink at the next u<n> before pool_dirs makes it. A co-runner can also strip another core-live unit's SKIP line, so a skipped check is cached as a pass under --warranted. The local lane is a
#   fast pre-check; CI's per-job runners are the binding grade. Also disclosed: pid reuse is narrowed by the poll bound, not closed; in a Linux container /proc/meminfo and getconf
#   report the host, not the cgroup limit, so an OOM kill (rc 137 with no wd.fired) reads as an rc FAIL and goes to the serial confirm; U (POOL_U_MB) is an [estimate]; the lane's own selftest as a pooled unit nests its J = 2 cells under the outer pool; (5) an arm that opens /dev/tty itself is a background-group member and would stop on SIGTTIN: the kill sends
#   CONT right after TERM, so it wakes and dies, and a prompt never reaches the user; (6) with no /usr/bin/perl the arms are NOT
#   process-grouped: today's direct-child kill runs, the lane says so once per run, and every ceiling FAIL line reads "tree NOT
#   contained". The dash claims were probed on one machine's /bin/dash; CI grades the ubuntu dash.
#
# `conformance/ci-classify-changes.sh` (docs_classify, reco) is the LANE'S OWN helper, not a derived
# invocation (reviewer M-4): the lane calls it directly, so it runs OUTSIDE the scrub, the dash shim and
# the ceiling, by design — it is CI's own classifier (D-240903-3), asked the same question CI asks, and
# it must be answered BEFORE any bucket or work root exists to run it in. Likewise twin_na (SWAS-163) sources
# `conformance/backlog-lib.sh` (resolve_backend) in a subshell, outside the scrub: this tree's own code, which the
# twins already run, so it grants no new capability.
RUN_HB=""; RUN_SPLIT=0; RUN_RC=0; RUN_S=0; VERBOSE=0; BEST=0; HEAVY=""; HEAVY_ARG=""; WARRANTED=0; BASE="origin/main"
BASE_SHA=""; DOCS_ONLY=false; DASH=""; SHIMDIR=""; CEIL=120; FLOOR=6144; FREE=""
# SWAS-428: each arm runs in a process group of its own (the perl setpgrp wrapper), so a ceiling kill reaches the whole tree.
# Plain assignments (no environment knob); the selftest overrides them in a COPY of the lane. ARM_PERL is called by absolute path, never through PATH.
ARM_PERL=/usr/bin/perl
ARM_GRACE_S=5; ARM_CONFIRM_S=5; LANE_PGID=""; LANE_PPGID=""; SR_PID=""; ARM_NOTE=""; ARM_CEIL_TXT=""
ARGVLOG=""; UNV=""; MB=""; FAILS=0; RAN=0; HCEIL=3600; SELFCEIL=3600
# SWAS-868 (P2, the bounded pool): POOL_J is the final fan-out (1 = today's serial lane). It is DERIVED by pool_j from this machine and never set: no environment or argv name feeds it. POOL_IN is 1 while the pool phase
# decides and records; POOL_LATE is 1 for a unit reaped under the blocking wait (its clock is not trusted). U_CTL, U_OUT, U_CRASH and UNIT_DIR name one unit's own control dir, output, crash-hit file and scratch dirs
# (empty = the single-unit defaults under $WORK); only the pool and its serial tail set them.
POOL_JF=1; POOL_J=1; POOL_C=""; POOL_F=""; POOL_WHY=""; POOL_IN=0; POOL_ON=0; POOL_LATE=0; POOL_USE=0; PQ=""; PQ_M=0; PQ_U=0; CL_Q=""; RACE_N=0; RI_OKV=OK; ST_KIND=""; ST_SS=""
U_CTL=""; U_OUT=""; U_CRASH=""; UNIT_DIR=""; CL_FEED=""
_st_lab=""; RI_KIND=""; RI_C=1; RI_NM=""; RI_RX=""; RI_CX=""; _st_tl=0   # read by the pool's save/restore before every decision has set them (set -u)
# POOL_U_MB: the memory one pooled unit is assumed to take [estimate]. A committed constant, never derived from the run log.
POOL_U_MB=1536
# SWAS-811: the touched-selftest budget (PREPUSH_SELFTEST_BUDGET_S may only raise it) and the counts the roster line prints.
# SWAS-840 (P1 of SWAS-858): the budget no longer selects. It is printed, and a target whose prior time passes it is run anyway and labelled. What bounds a call is ST_CEIL, the runaway ceiling per
# target: a plain assignment (no environment or argv name; a selftest scales it in a lane COPY), not coupled to SELFCEIL. A kill at it reads UNVERIFIED, never OK and never named CI-bound.
ST_BUDGET_DEFAULT=300
ST_CEIL=3600
STBUD=300; ST_N=0; ST_K=0; ST_U=0; ST_NM=0; ST_EX=0; ST_SC=""; ST_OB=0; ST_H=0
CRASH=0; CRASH_LIST=""; CRASH_EV=""; CRASH_TXT=""; CRASH_LINE=""; CRASH_BYLINE=0   # SWAS-600: the crashed-unit counter, its names, and the evidence of the unit just run
# SELFCEIL (reviewer I-1): the ceiling of the core arms that are not one hermetic call per target (shellcheck, parse-lint, secret-scan, the board gates). Since SWAS-811 each
# core-selftest call has its own ceiling (ST_CEIL since SWAS-840), not this one. The reasoning below is the original one: a face that runs BOTH hermeticity
# faces is not bounded by the 120 s per-check core
# ceiling; "add a heavy row" is the wrong remedy (it is the core, not a heavy invocation), so its overrun
# names PREPUSH_CEILING_S instead. It is the HEAVY default (3600 s) because its cost is not a constant:
# selftest-hermetic derives its OWN target set from its roster, and on this branch that was 4 targets /
# 2013 s measured unbounded — the 900 s and 1800 s constants before it were KILLS, censored measurements.

# LOCAL_DEFER_SELFTESTS (SWAS-442, design 2026-10-26-verify-selftest-wall-design.md §3.7, owner Q1): the aggregate-sized hermetic targets
# whose two faces the LOCAL pre-push does not run. ONE literal entry, matched whole against the listing (never a pattern): verify.sh's
# --selftest nests a full aggregate run (about 87 min a face on a plain run, [E] from a measured 5216 s), far past SELFCEIL, so running it
# here only turned PARITY-CORE into FAIL. CI's H2 step binds both faces; the verdict names it NOT ENFORCED locally and never claims it ran.
LOCAL_DEFER_SELFTESTS='conformance/verify.sh'
SELF_NE=0; SELF_NE_LIST=""
note() { printf '# %s\n' "$1"; }
unv()  { [ -n "$UNV" ] || UNV=$1; }      # the FIRST reason wins: it is the one that stopped the run

# raise_only <env-value> <default> <name> — the D-240811-2.1 asymmetry: the environment may only RAISE a
# bound, and only with digits. Anything else is IGNORED LOUDLY (stderr) and the default stands, so a typo
# can never quietly buy a run more rope than the design gave it.
raise_only() {
  case ${1-} in
    '') printf '%s\n' "$2"; return 0 ;;
    *[!0-9]*) printf 'prepush-lane: IGNORED: %s is not numeric: [%s] — using %s\n' "$3" "$1" "$2" >&2 ;;
    *) if [ "$1" -gt "$2" ]; then printf '%s\n' "$1"; return 0; fi
       printf 'prepush-lane: IGNORED: %s may only RAISE (%s <= %s) — using %s\n' "$3" "$1" "$2" "$2" >&2 ;;
  esac
  printf '%s\n' "$2"
}

# mem_free_mb — MemAvailable (Linux) or free+inactive+speculative pages (macOS: sysctl gives the
# total, vm_stat the page size and the reclaimable classes). Unreadable prints nothing, deliberately.
mem_free_mb() {
  if [ -r /proc/meminfo ]; then
    LC_ALL=C awk '/^MemAvailable:/ { print int($2/1024); exit }' /proc/meminfo
  elif command -v vm_stat >/dev/null 2>&1; then
    _ps=$(vm_stat | sed -n '1s/.*page size of \([0-9]*\) bytes.*/\1/p')
    vm_stat | LC_ALL=C awk -v ps="${_ps:-4096}" \
      '/^Pages (free|inactive|speculative)/ { gsub(/[.,]/,"",$NF); f += $NF } END { print int(f*ps/1048576) }'
  fi
}
# mem_guard <free-mb> <floor-mb> -> 0 met · 1 below the floor · 2 UNREADABLE — its own answer, because it must REFUSE a heavy arm (§3.7), never be read as "probably fine".
mem_guard() {
  case ${1-} in '' | *[!0-9]*) return 2 ;; esac
  [ "$1" -ge "$2" ] || return 1
}

# --------------------------------------------------------------- the work root, the shim, the base
work_init() {
  _par=${TMPDIR:-/tmp}; _par=${_par%/}
  WORK=${WORK:-$(mktemp -d "$_par/prepush-XXXXXX")}
  TMPDIR=$WORK; export TMPDIR                        # the LANE's own TMPDIR is the work root; an ARM gets $WORK/tmp (scrubbed_run)
  ARGVLOG=$WORK/argv.log; : > "$ARGVLOG"; mkdir -p "$WORK/empty" "$WORK/gh" "$WORK/tmp"
  # SWAS-428: the kill state (pgids, markers, notes) lives in $WORK/ctl, which no arm is handed: an arm that forged it could aim the lane's kill.
  ( umask 077; mkdir -p "$WORK/ctl" ); chmod 700 "$WORK/ctl"
  note "work root: $WORK (TMPDIR for every invocation; removed best-effort at exit)"
  _st=$(find "$_par" -maxdepth 1 -type d -name 'prepush-*' ! -name "${WORK##*/}" 2>/dev/null |
        sort | tr '\n' ' ') || _st=""
  [ -z "$_st" ] || note "stale work roots from earlier runs (remove when idle): $_st"
}

# --base (design §3.3, security C21): charset, no leading `-`, no `..`, and it must RESOLVE to a
# commit — validated BEFORE it reaches git as an operand, so `--base --output=x` is rc 2, not a write.
base_check() {
  case $BASE in
    -*) die2 "--base may not start with a dash: $BASE" ;;
    *..*) die2 "--base may not contain '..': $BASE" ;;
  esac
  base_ok "$BASE" || die2 "--base outside the closed charset [A-Za-z0-9._/-]+: $BASE"
  BASE_SHA=$(git rev-parse --verify --end-of-options "$BASE^{commit}" 2>/dev/null) ||
    die2 "--base does not resolve to a commit: $BASE"
  note "base: $BASE ($BASE_SHA)"
}

# The listing, verbatim from design §3.3: the committed delta against the merge-base PLUS untracked files
# (an untracked new check must not escape the docs-only classifier — the fail-safe direction). `-z`, so a
# path containing a NEWLINE cannot split into two: record count != line count, and the run is UNVERIFIED naming the offender (git quotes it safely).
listing_derive() {
  _mb=$(git merge-base "$BASE_SHA" HEAD 2>/dev/null) || { unv "no merge-base with $BASE"; return 0; }
  MB=$_mb                                          # carried out for the secret-scan range arm
  { git diff -z --name-only --no-renames "$_mb" HEAD; git ls-files -z --others --exclude-standard; } \
    > "$WORK/listing.z"
  tr '\0' '\n' < "$WORK/listing.z" | LC_ALL=C sort -u > "$WORK/listing"
  # The records are NUL-separated, so the stream carries NO newline at all unless a PATH does.
  if [ "$(tr -dc '\n' < "$WORK/listing.z" | wc -c | tr -d ' ')" -ne 0 ]; then
    _bad=$({ git diff --name-only --no-renames "$_mb" HEAD; git ls-files --others --exclude-standard; } |
           grep '\\n' | sed -n 1p) || _bad=""
    unv "newline in a listed path: ${_bad:-<unprintable>}"; return 0
  fi
  note "listing: $(grep -c '' < "$WORK/listing" || :) path(s) vs merge-base $_mb"
}

# docs-only by the SAME classifier CI uses (D-240903-3). Absent (an adopter export) => false, this predicate's own fail-safe: unknown means run everything.
docs_classify() {
  DOCS_ONLY=false
  [ -f conformance/ci-classify-changes.sh ] || return 0
  if sh conformance/ci-classify-changes.sh "$WORK/listing" 2>/dev/null | grep -qx 'docs_only=true'
  then DOCS_ONLY=true; fi
  note "docs-only: $DOCS_ONLY"
}

# The dash PATH shim (§3.4): a 0700 dir under the work root holding EXACTLY `sh`, which execs the resolved
# dash — so a child that re-invokes `sh` resolves dash too, not only the outermost process. kit-guard's SHIM_BINS carries no `sh`, so this shim can never shadow a guard shim.
shim_init() {
  DASH=$(command -v dash 2>/dev/null) || DASH=""
  if [ -z "$DASH" ]; then
    note "shell: UNVERIFIED (install dash: brew install dash)"
    unv "no dash: the lane never substitutes the operator's shell and calls the result parity"
    return 0
  fi
  SHIMDIR=$WORK/shim; mkdir -p "$SHIMDIR"; chmod 0700 "$SHIMDIR"
  printf '#!/bin/sh\nexec %s "$@"\n' "$DASH" > "$SHIMDIR/sh"; chmod 0755 "$SHIMDIR/sh"
  note "shell: dash $DASH (PATH shim $SHIMDIR, holding exactly \`sh\`)"
}

# ---- SWAS-868: J, the pool's fan-out, derived from this machine alone (cores and free memory by absolute path; no environment, argv or PATH feed) ----
pool_cores() { /usr/bin/getconf _NPROCESSORS_ONLN 2>/dev/null || :; }
pool_free_mb() {
  if [ -r /proc/meminfo ]; then
    LC_ALL=C /usr/bin/awk '/^MemAvailable:/ { print int($2/1024); exit }' /proc/meminfo
  elif [ -x /usr/bin/vm_stat ]; then
    /usr/bin/vm_stat 2>/dev/null | LC_ALL=C /usr/bin/awk '
      NR == 1 { if (match($0, /page size of [0-9]+ bytes/)) s = substr($0, RSTART + 13, RLENGTH - 19) + 0 }
      /^Pages (free|inactive|speculative)/ { v = $NF; gsub(/[.,]/, "", v); f += v }
      END { if (s == 0) s = 4096; print int(f * s / 1048576) }'
  fi
}
# pool_j — sets POOL_J (>= 1): J = min(C - 1, floor((F - FLOOR) / U)). J is 1, with a stated reason, when cores or free memory are unreadable or there is no perl (the arms are then not process-grouped).
pool_j() {
  _pj_j=1; POOL_WHY=""; POOL_C=""; POOL_F=""
  if ! arm_perl_ok; then POOL_WHY="no $ARM_PERL, so the arms are not process-grouped"   # PLPERL
  else
    POOL_C=$(pool_cores 2>/dev/null) || POOL_C=""
    POOL_F=$(pool_free_mb 2>/dev/null) || POOL_F=""
    case $POOL_C in ''|*[!0-9]*|0*) POOL_WHY="cores unreadable" ;; esac
    case $POOL_F in ''|*[!0-9]*|0[0-9]*) POOL_WHY="${POOL_WHY:+$POOL_WHY; }free memory unreadable" ;; esac
  fi
  if [ -z "$POOL_WHY" ]; then
    _pj_j=$((POOL_C - 1))   # PLJCLAMP
    _pj_m=$(( (POOL_F - FLOOR) / POOL_U_MB ))
    [ "$_pj_m" -ge "$_pj_j" ] || _pj_j=$_pj_m   # PLJMIN
    [ "$_pj_j" -ge 1 ] || _pj_j=1   # PLJONE
  fi
  POOL_J=$_pj_j   # PLJSET
}
pool_note() {
  if [ -n "$POOL_WHY" ]; then note "pool: J=$POOL_J ($POOL_WHY; derived, never set)"; return 0; fi
  note "pool: J=$POOL_J (cores $POOL_C, free $POOL_F MB, floor $FLOOR MB, U $POOL_U_MB MB [estimate]; derived, never set)"
}

bounds_init() {
  CEIL=$(raise_only "${PREPUSH_CEILING_S-}" 120 PREPUSH_CEILING_S)
  FLOOR=$(raise_only "${PREPUSH_MEM_FLOOR_MB-}" 6144 PREPUSH_MEM_FLOOR_MB)
  case ${PREPUSH_SELFTEST_BUDGET_S-} in
    0[0-9]*) printf 'prepush-lane: IGNORED: PREPUSH_SELFTEST_BUDGET_S has a leading zero: [%s] — using %s\n' "$PREPUSH_SELFTEST_BUDGET_S" "$ST_BUDGET_DEFAULT" >&2; STBUD=$ST_BUDGET_DEFAULT ;;   # STZERO
    *) STBUD=$(raise_only "${PREPUSH_SELFTEST_BUDGET_S-}" "$ST_BUDGET_DEFAULT" PREPUSH_SELFTEST_BUDGET_S) ;;   # STDIAL
  esac
  command -v sleep >/dev/null 2>&1 || unv "no timeout facility"
  LANE_PGID=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ') || LANE_PGID=""
  LANE_PPGID=$(ps -o pgid= -p "$PPID" 2>/dev/null | tr -d ' ') || LANE_PPGID=""   # the group of whoever launched the lane: never ours to signal
  _bi_mode="process-group watchdog"
  if ! arm_perl_ok; then
    _bi_mode="direct-child watchdog (no $ARM_PERL)"
    note "NOTE: no $ARM_PERL: arms are not process-grouped; a ceiling kill reaches the direct child only"
  fi
  FREE=$(mem_free_mb 2>/dev/null) || FREE=""
  [ "$CEIL" -le "$SELFCEIL" ] || SELFCEIL=$CEIL     # raise-only, and never BELOW the core ceiling
  note "ceiling: ${CEIL}s/invocation (core-selftest: budget ${STBUD} s, printed, not a cutoff; runaway ceiling ${ST_CEIL} s per target · other core arms ${SELFCEIL}s · heavy arms ${HCEIL}s or their budget-s) · memory floor: ${FLOOR} MB · free: ${FREE:-unreadable} MB · ceiling kill: ${_bi_mode}"
  mem_guard "${FREE-}" "$FLOOR" ||
    note "WARNING: free memory is not above the floor — the core is cheap and still runs; a heavy arm would be refused"
  pool_j; pool_note   # SWAS-868: the provisional J (no lock yet); the start record logs it
}
# heavy_allowed <arm> — the floor is re-read before EVERY heavy arm (§3.7); unreadable REFUSES.
heavy_allowed() {
  FREE=$(mem_free_mb 2>/dev/null) || FREE=""
  _mg=0; mem_guard "${FREE-}" "$FLOOR" || _mg=$?
  [ "$_mg" -ne 2 ] || { note "UNVERIFIED: cannot read free memory — the $1 arm is refused"
                        unv "cannot read free memory"; return 1; }
  [ "$_mg" -ne 1 ] || { note "REFUSED: free memory ${FREE} MB is below the ${FLOOR} MB floor — the $1 arm is refused"
                        unv "free memory below the floor"; return 1; }
}

# ---- SWAS-278b: the machine-wide heavy-arm lock (design docs/architecture/2026-10-17-guard-dev-clone-prepush-design.md §6.2) ----
# A kernel advisory lock (flock) on $HOME/.local/state/sparkwright/heavy-arm.lock, held ONCE per run over the heavy phase:
# core-selftest (the default run too), core-live, claims, non-vacuity, green-on-clone and the single heavy flags. The kernel drops
# it when the last descriptor closes, a SIGKILLed holder included, so nothing is ever broken, aged or deleted. Back ends: flock(1)
# at /usr/bin/flock or /bin/flock (Linux; never through PATH) or `cd / && env -i /usr/bin/perl` (macOS; no PERL5OPT, PERL5LIB, PERLLIB,
# PERL_USE_UNSAFE_INC or cwd reaches it: true BY CONSTRUCTION of cd / and env -i, stated as a ceiling, not tested per route); neither -> UNVERIFIED. A symlinked or foreign-owned lock
# path, or an unsafe state dir -> UNVERIFIED, nothing deleted. ONE run-level wait budget; no environment knob (these are plain
# assignments, so an inherited HL_* name is overwritten; the selftest sets them inside its own subshells). NO ancestor re-entry
# (rev 2.2): a nested run waits, or is a selftest under its own HOME. The holder note is DISPLAY ONLY, sanitised on write and read.
# Not a security control: a forged or stuck lock costs a wait, then UNVERIFIED, never a false OK. Cooperative, per user.
HL_BUDGET=5400; HL_POLL=15; HL_NOTE_S=300; HL_PERL=/usr/bin/perl; HL_FLOCKS="/usr/bin/flock /bin/flock"
HL_STATE=none; HL_WHY=""; HL_TOOL=""; HL_FLOCK=""; HL_TRC=""; HL_DIR=""; HL_FILE=""; HL_HOLDER=""
# Post-open re-check ceiling (honest): after the open, only the PATH is re-tested (symlink, owner). Descriptor/path identity is not
# checkable portably (-ef /dev/fd/9 never matches on macOS, measured), so a same-uid process that swaps the path inside that window is
# not seen. The effect is a wait or an UNVERIFIED verdict, never a false OK: the lock is cooperative and per user.
# hl_clean <s> — only [A-Za-z0-9._/:-], at most 200 bytes, NO newline (GNU cut always appends one, BSD cut only when it truncates).
hl_clean() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._/:-' '_' | LC_ALL=C cut -c1-200 | LC_ALL=C tr -d '\n'; }
# numeric uid on both sides: a name compare can be fooled by a shadowing user name, and ls prints a number when a uid has no name
hl_owner() { ls -ldn "$1" 2>/dev/null | LC_ALL=C awk '{ print $3 }'; }
hl_owner_ok() { _hme=$(id -u 2>/dev/null) || _hme=""; _hown=$(hl_owner "$1"); [ -n "$_hme" ] && [ "$_hown" = "$_hme" ]; }
# flock(1) is looked for at fixed absolute paths ONLY, never through PATH (a planted `flock` on PATH is not run).
hl_tool() {
  HL_TOOL=""; HL_FLOCK=""
  for _hf in $HL_FLOCKS; do
    if [ -x "$_hf" ]; then HL_FLOCK=$_hf; HL_TOOL=flock; break; fi
  done
  [ -n "$HL_TOOL" ] && return 0
  if [ -x "$HL_PERL" ]; then HL_TOOL=perl
  else HL_WHY="neither flock(1) nor $HL_PERL is available"; return 1; fi
}
# hl_open — open descriptor 9 on the lock file after the safety checks; rc 0, or rc 1 with HL_WHY.
hl_open() {
  HL_WHY=""
  hl_tool || return 1
  case ${HOME-} in /?*) ;; *) HL_WHY="HOME is unset or not absolute"; return 1 ;; esac
  HL_DIR=$HOME/.local/state/sparkwright; HL_FILE=$HL_DIR/heavy-arm.lock; HL_HOLDER=$HL_DIR/heavy-arm.holder
  if [ ! -e "$HL_DIR" ] && [ ! -L "$HL_DIR" ]; then
    ( umask 077; mkdir -p "$HL_DIR" ) 2>/dev/null || { HL_WHY="the state dir cannot be created"; return 1; }
  fi
  _hls=$(ls -ld "$HL_DIR" 2>/dev/null) || { HL_WHY="the state dir cannot be inspected"; return 1; }
  case ${_hls%% *} in
    d????[!w]??[!w]*) ;;
    *) HL_WHY="the state dir is not a plain directory, or is group/world-writable"; return 1 ;;
  esac
  hl_owner_ok "$HL_DIR" || { HL_WHY="the state dir is not owned by the current user"; return 1; }
  [ ! -L "$HL_FILE" ] || { HL_WHY="the lock path is a symlink (never followed, never deleted)"; return 1; }
  if [ -e "$HL_FILE" ]; then
    [ -f "$HL_FILE" ] || { HL_WHY="the lock path is not a regular file"; return 1; }
    hl_owner_ok "$HL_FILE" || { HL_WHY="the lock file is owned by another user"; return 1; }
  fi
  ( umask 077; exec 9>>"$HL_FILE" ) 2>/dev/null || { HL_WHY="the lock file cannot be opened"; return 1; }
  _hum=$(umask); umask 077
  exec 9>>"$HL_FILE"
  umask "$_hum"
  # the same checks again on the path (the window is disclosed, design §11). `-ef /dev/fd/9` was MEASURED unusable: on macOS it never
  # equals the path, so descriptor/path identity is not a portable check and is not made.
  if [ -L "$HL_FILE" ] || ! hl_owner_ok "$HL_FILE"; then
    exec 9>&-
    HL_WHY="the lock path changed while it was being opened"; return 1
  fi
  return 0
}
# hl_try — ONE non-blocking attempt on descriptor 9: rc 0 got it · 1 busy · 2 the helper failed.
hl_try() {
  _htr=0
  case $HL_TOOL in
    flock) "$HL_FLOCK" -n 9 || _htr=$? ;;
    perl)  ( cd / && exec /usr/bin/env -i "$HL_PERL" -MFcntl=:flock -e 'open(my $f, ">&=", 9) or exit 3; flock($f, LOCK_EX|LOCK_NB) or exit 1' ) || _htr=$? ;;
    *) return 2 ;;
  esac
  case $_htr in 0) return 0 ;; 1) return 1 ;; *) HL_TRC=$_htr; return 2 ;; esac
}
# hl_holder_text — the holder note, one sanitised field per line in, one line out (display only).
hl_holder_text() {
  if [ ! -f "$HL_HOLDER" ] || [ -L "$HL_HOLDER" ]; then printf 'unknown (no holder note)'; return 0; fi
  _hp=$(hl_clean "$(LC_ALL=C sed -n 1p "$HL_HOLDER" 2>/dev/null)"); _ht=$(hl_clean "$(LC_ALL=C sed -n 2p "$HL_HOLDER" 2>/dev/null)")
  _hu=$(hl_clean "$(LC_ALL=C sed -n 3p "$HL_HOLDER" 2>/dev/null)"); _hs=$(hl_clean "$(LC_ALL=C sed -n 4p "$HL_HOLDER" 2>/dev/null)")
  printf 'pid %s tree %s unit %s since %s' "${_hp:--}" "${_ht:--}" "${_hu:--}" "${_hs:--}"
}
# hl_note_write <unit> — the display-only holder note (temp file + mv, noclobber, sanitised, LC_ALL=C TZ=UTC0).
hl_note_write() {
  _hnt=$HL_HOLDER.$$
  rm -f "$_hnt" 2>/dev/null || :
  if ( set -C; umask 077
       { hl_clean "$$"; echo; hl_clean "${ROOT-unknown}"; echo; hl_clean "$1"; echo; LC_ALL=C TZ=UTC0 date '+%Y-%m-%dT%H:%M:%SZ'; } > "$_hnt" ) 2>/dev/null
  then
    # a holder path that is a symlink, or exists and is not a regular file, is left alone (mv would write INTO a directory it names)
    if [ -L "$HL_HOLDER" ] || { [ -e "$HL_HOLDER" ] && [ ! -f "$HL_HOLDER" ]; }; then rm -f "$_hnt" 2>/dev/null || :
    else mv -f "$_hnt" "$HL_HOLDER" 2>/dev/null || rm -f "$_hnt" 2>/dev/null || :; fi
  else rm -f "$_hnt" 2>/dev/null || :; fi
  return 0
}
# hl_waited — the seconds since hl_acquire began, for the run log's lock_wait_s (SWAS-568); called only after _hat is set.
hl_waited() { HL_WAIT_S=$(( $(date +%s) - _hat )); return 0; }
hl_fail() {
  HL_STATE=failed; exec 9>&-
  note "UNVERIFIED: heavy-arm lock — $1; the heavy units are not run"
  unv "heavy-arm lock: $1"
  return 0
}
# hl_acquire <unit> — rc 0 held (idempotent), rc 1 not held (UNV set). The ONLY wait of the run: a failure is remembered, so every
# later unit fails fast instead of waiting again.
hl_acquire() {
  case $HL_STATE in held) return 0 ;; failed) return 1 ;; esac
  hl_open || { hl_fail "$HL_WHY"; return 1; }
  _hat=$(date +%s); _hatn=$_hat; _hafirst=1; _hawaited=0
  while :; do
    _har=0; hl_try || _har=$?
    [ "$_har" -ne 0 ] || break
    if [ "$_har" -ne 1 ]; then hl_waited; hl_fail "the lock helper failed (rc ${HL_TRC:-$_har})"; return 1; fi
    if [ $(( $(date +%s) - _hat )) -ge "$HL_BUDGET" ]; then
      hl_waited; hl_fail "the lock stayed busy for the ${HL_BUDGET}s run budget (holder: $(hl_holder_text))"; return 1
    fi
    if [ "$_hafirst" -eq 1 ] || [ $(( $(date +%s) - _hatn )) -ge "$HL_NOTE_S" ]; then
      note "heavy-arm lock: busy (held by $(hl_holder_text)) — waiting for the $1 unit, polling every ${HL_POLL}s, run budget ${HL_BUDGET}s"
      _hafirst=0; _hatn=$(date +%s)
    fi
    _hawaited=1; sleep "$HL_POLL"
  done
  hl_waited
  HL_STATE=held
  if [ "$_hawaited" -eq 1 ]; then
    note "heavy-arm lock: acquired after $(( $(date +%s) - _hat ))s for the $1 unit"
    FREE=$(mem_free_mb 2>/dev/null) || FREE=""     # the floor is re-read AFTER a wait: the reading from before it is stale
    _hamg=0; mem_guard "${FREE-}" "${FLOOR-6144}" || _hamg=$?
    [ "$_hamg" -eq 0 ] || note "WARNING: free memory ${FREE:-unreadable} MB is below the ${FLOOR-6144} MB floor after the wait — a Tier-2 arm would be refused"
  else
    note "heavy-arm lock: acquired for the $1 unit (held until the run's last heavy unit ends)"
  fi
  hl_note_write "$1"
  return 0
}
# hl_need <unit> — the call every heavy unit makes first: rc 0 the lock is held, rc 1 the unit must not run.
hl_need() {
  hl_acquire "$1" && return 0
  note "UNVERIFIED: heavy-arm lock not held — the $1 unit is not run"
  return 1
}
# hl_release — the holder note goes first (while the lock is still ours), then the descriptor closes. The lock file is never deleted.
hl_release() {
  [ "$HL_STATE" = held ] || return 0
  rm -f "$HL_HOLDER" 2>/dev/null || :
  exec 9>&-
  HL_STATE=released
  return 0
}

# ====================================================================== THE RUN LOG (SWAS-568)
# Plan: docs/plans/2026-11-12-prepush-run-log-568-plan.md; design 2026-11-12-ci-local-parity-nightly-design.md (P0, section 3.6, errata C1). A per-user MEASUREMENT CACHE, never evidence:
# one runs.log beside the times table, in $HOME/.local/state/sparkwright/prepush/<root-commit>/, two records per run (start, end), one per line, ASCII, space-separated key=value. The keys
# are literal text in two fixed printf formats. NO free text: each value is a closed enum, a digit string, a sha or a capped token that passed rl_val (floor_mb is a digits-only env bound, the
# raise-only PREPUSH_MEM_FLOOR_MB), and the free-text sources the lane holds (UNV reasons, paths, the branch, the --base text, the ci-file path, output) have no field. There is NO switch:
# PREPUSH_NO_CACHE does not reach it (a selftest isolates it by HOME). It is written by ONE printf per record (rl_emit), a failure of which is dropped and never a verdict change, and the run
# path never reads it (only --log-report does). Rotation keeps the live log plus three rotated files of about 1 MB each (the card's own cap: the one place data is dropped, by mv overwrite).
# The 16 KB cap applies to the u= list only (units past it are counted in trunc=). A SIGKILLed run leaves a start with no end: --log-report counts it as incomplete.
# Grammar v1:
#   v1 start run=<R> ts=<E> head=<H40> base=<H40|-> row=<ROW|-> mode=<M> ci=<default|other> lane=<T> os=<darwin|linux|other> j=<N: the provisional J> free_mb=<N|-> floor_mb=<N> listing=<N|-> brule=<C>
#   v1 end   run=<R> ts=<E> verdict=<OK|FAIL|UNVERIFIED|PLAN|INTERRUPTED> rc=<N|-> wall_s=<N> lock=<held|failed|none> lock_wait_s=<N|-> ran=<N> fails=<N> crash=<N> u=<U>[,<U>...] [trunc=<N>] jf=<N: the final J> race=<N>
#   (SWAS-868: verdict RACE in U = a unit that failed in the pool and passed serially; jf= and race= are additive.)
#   R = <epoch>-<pid>; mode = default|warranted|green-on-clone|exports|slow|non-vacuity|plan; lane = a checksum of the checkout path, not the path itself (tells clones apart); row = HEAD's Kit-Row
#   trailer; brule = the clauses of the design's rule (3.3) that would fire (battery_rule): none, or a,b-partial,c,d,e joined; U = <bucket>:<name>:<verdict>:<secs>:<rss_kb> (a repeated name
#   gets #2, #3; verdict OK|FAIL|UNV|CRASH|SKIP|NA|CIB|RACE; no unit argv; rss_kb is `-` when unavailable); rc is `-` for INTERRUPTED (a trap does not know it).
# HONEST LABEL for rss_kb [measured, sampled]: the arm group's summed RSS (ps -o rss, KB), sampled once a second by the watchdog; it misses spikes shorter than a tick and descendants that left
# the group; the arm can forge it (ctl is reachable), which is acceptable for a measurement. With no /usr/bin/perl there is no group, so `-`.
RL_ON=0; RL_FILE=""; RL_RUN=""; RL_T0=0; RL_U=""; RL_TRUNC=0; RL_ENDED=0; RL_SEEN=""; RL_UMAX=16384
# the card's 1 MB cap: a plain assignment (no knob); a selftest scales it in a lane COPY
RL_CAP=1048576
RUN_RSS="-"; HL_WAIT_S="-"
# rl_val <class> <value> — the value when it holds only its class's bytes and fits the class's cap, else `-` (the basename_ok idiom: whole-string tr -cd, newline-safe).
rl_val() {
  case $1 in
    num) _rv_cs='0-9'; _rv_n=12 ;;
    sha) _rv_cs='0-9a-f'; _rv_n=40 ;;
    row) _rv_cs='A-Z0-9-'; _rv_n=32 ;;
    brule) _rv_cs='a-z,-'; _rv_n=40 ;;
    base) _rv_cs='a-z0-9.-'; _rv_n=64 ;;
    path) _rv_cs='A-Za-z0-9._/-'; _rv_n=128 ;;
    *) printf '%s' -; return 0 ;;
  esac
  if [ -z "$2" ] || [ "${#2}" -gt "$_rv_n" ]; then printf '%s' -; return 0; fi
  if [ "$1" = row ]; then   # a row id starts with a letter or a digit, never `-`
    case $2 in
      -*) printf '%s' -; return 0 ;;
    esac
  fi
  if [ "$(printf '%s' "$2" | LC_ALL=C tr -cd "$_rv_cs")" = "$2" ]; then printf '%s' "$2"; else printf '%s' -; fi
  return 0
}
# rl_name <bucket> <name> — a unit name: a repo-relative path for core-selftest, else a basename; anything else (a leading slash, a `..`) is `-`.
rl_name() {
  case $1 in
    core-selftest) _rn_v=$(rl_val path "$2") ;;
    *) _rn_v=$(rl_val base "$2") ;;
  esac
  case $_rn_v in
    /*|*..*) _rn_v=- ;;
  esac
  printf '%s' "$_rn_v"
}
# rl_bucket <bucket> — the unit's bucket, from a closed list.
rl_bucket() {
  case $1 in
    core-live|core-selftest|core-shellcheck|core-parselint|core-secretscan|core-board|twin|heavy|touched-readers) printf '%s' "$1" ;;
    *) printf '%s' other ;;
  esac
}
rl_off() { RL_ON=0; note "run log: off — $1"; return 0; }
# rl_file_ok <path> — rc 0 when the path is absent, or is a regular, non-symlink file owned by the current user (numeric uid, as the lock's own check).
rl_file_ok() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  [ ! -L "$1" ] && [ -f "$1" ] && hl_owner_ok "$1"
}
# rl_init — find and check the state dir with the leaf rules of tr_state (HOME absolute, a plain dir, not group/world-writable, owned by the numeric uid, rwx), and the log and its three
# rotated files if present (regular, no symlink, ours). Anything else turns the log off with ONE note: unlike tr_refuse it NEVER calls unv.
rl_init() {
  RL_ON=0; RL_FILE=""
  case ${HOME-} in
    /?*) ;;
    *) rl_off "HOME is unset or not absolute"; return 0 ;;
  esac
  _ri_r=$(git rev-list --max-parents=0 HEAD 2>/dev/null | sed -n 1p) || _ri_r=""
  case $_ri_r in
    ''|*[!0-9a-f]*) rl_off "no root commit"; return 0 ;;
  esac
  _ri_d=$HOME/.local/state/sparkwright/prepush/$_ri_r
  if [ ! -e "$_ri_d" ] && [ ! -L "$_ri_d" ]; then
    ( umask 077; mkdir -p "$_ri_d" ) 2>/dev/null || { rl_off "the state dir cannot be created"; return 0; }
  fi
  _ri_l=$(ls -ld "$_ri_d" 2>/dev/null) || { rl_off "the state dir cannot be inspected"; return 0; }
  case ${_ri_l%% *} in
    d????[!w]??[!w]*) ;;
    *) rl_off "the state dir is not a plain directory, or is group/world-writable"; return 0 ;;
  esac
  hl_owner_ok "$_ri_d" || { rl_off "the state dir is not owned by the current user"; return 0; }
  if [ ! -r "$_ri_d" ] || [ ! -w "$_ri_d" ] || [ ! -x "$_ri_d" ]; then rl_off "the state dir is unreadable"; return 0; fi
  for _ri_s in "" .1 .2 .3; do
    rl_file_ok "$_ri_d/runs.log$_ri_s" || { rl_off "runs.log$_ri_s is not a regular file of the current user"; return 0; }
  done
  RL_FILE=$_ri_d/runs.log; RL_ON=1
  return 0
}
# rl_emit <line> — ONE printf per record; a failure is dropped, never a verdict change (no unv: the log is a measurement, not evidence). The file is re-checked first (a link planted since rl_init).
rl_emit() {
  [ "$RL_ON" -eq 1 ] || return 0
  rl_file_ok "$RL_FILE" || return 0
  ( umask 077; printf '%s\n' "$1" >> "$RL_FILE" ) 2>/dev/null || :   # RLWRITE
  return 0
}
# rl_rotate — at the cap, runs.log.2 -> .3, .1 -> .2, runs.log -> .1: three files are kept and the oldest is dropped by mv overwrite (the card's own 1 MB cap; every mv best-effort).
rl_rotate() {
  [ -f "$RL_FILE" ] || return 0
  _rr_sz=$(wc -c < "$RL_FILE" 2>/dev/null | tr -d ' ') || _rr_sz=0
  case $_rr_sz in
    ''|*[!0-9]*) _rr_sz=0 ;;
  esac
  [ "$_rr_sz" -ge "$RL_CAP" ] || return 0
  mv -f "$RL_FILE.2" "$RL_FILE.3" 2>/dev/null || :   # RLROT
  mv -f "$RL_FILE.1" "$RL_FILE.2" 2>/dev/null || :   # RLROT
  mv -f "$RL_FILE" "$RL_FILE.1" 2>/dev/null || :   # RLROT
  return 0
}
# rl_mode — the mode from the parsed flags, never their operands.
rl_mode() {
  if [ "$PLAN" -eq 1 ]; then printf '%s' plan; return 0; fi
  if [ "$WARRANTED" -eq 1 ]; then printf '%s' warranted; return 0; fi
  case $HEAVY in
    green-on-clone|exports|slow|non-vacuity) printf '%s' "$HEAVY" ;;
    *) printf '%s' default ;;
  esac
}
rl_os() {
  case $(uname -s 2>/dev/null) in
    Darwin) printf '%s' darwin ;;
    Linux) printf '%s' linux ;;
    *) printf '%s' other ;;
  esac
}
# br_norm — stdin: `git diff --raw -z` with its NULs turned into \001 (callers: tr '\0' '\001'), so a newline inside a record stays INSIDE it. The records are read BY POSITION, strictly in
# pairs (an odd one is the header `:mode mode sha sha S`, an even one the path), never by a leading `:`. Prints `<A|D|M|T><TAB><path>` (a mode change on M reads T). Anything it cannot
# trust (a record holding a newline, a header of another shape, an odd count) prints `E<TAB>-`, which battery_rule reads as clause e: unknown fires.
br_norm() {
  LC_ALL=C awk '
    BEGIN { RS = "\001" }
    index($0, "\n") { bad = 1; next }   # RLNL
    NR % 2 == 1 { if ($0 !~ /^:[0-7]+ [0-7]+ [0-9a-f]+ [0-9a-f]+ [A-Z]$/) { bad = 1; next }
                  split($0, f, " "); st = f[5]; if (st == "M" && substr(f[1], 2) != f[2]) st = "T"; next }
    { print st "\t" $0 }
    END { if (bad || NR % 2) print "E\t-" }'
}
# battery_rule — stdin: one `<A|D|M|T><TAB><path>` per line. Prints the clauses of the design's rule (section 3.3, as errata C1 gives it) that would fire, comma-joined in a fixed order, or
# `none`: (a) .claude/ or hooks/ touched; (b) conformance/agent-autonomy*.sh, labelled partial until P4 names the sourced and fixture paths; (c) an added, deleted or re-moded path under
# scripts/, conformance/, hooks/ or .claude/; (d) .github/workflows/ or .kit/; (e) an empty listing. It only RECORDS: P0 runs no battery. P4 reuses this one function.
battery_rule() {
  LC_ALL=C awk -F'\t' '
    { n++; st = $1; p = $2
      if (st == "E") e = 1
      if (p ~ /^(\.claude|hooks)\//) a = 1
      if (p ~ /^conformance\/agent-autonomy[a-z0-9._-]*\.sh$/) b = 1
      if ((st == "A" || st == "D" || st == "T") && p ~ /^(scripts|conformance|hooks|\.claude)\//) c = 1   # RLCC
      if (p ~ /^(\.github\/workflows|\.kit)\//) d = 1 }
    END {
      if (n == 0) e = 1
      o = ""
      if (a) o = o ",a"
      if (b) o = o ",b-partial"
      if (c) o = o ",c"
      if (d) o = o ",d"
      if (e) o = o ",e"
      print (o == "" ? "none" : substr(o, 2)) }'
}
# rl_brule — battery_rule over the run's own listing: the committed delta against the merge-base plus the untracked files (counted as added). No merge-base or listing is clause e.
rl_brule() {
  if [ -z "$MB" ] || [ ! -f "$WORK/listing" ]; then printf '%s' e; return 0; fi
  {
    git diff -z --raw --no-renames "$MB" HEAD 2>/dev/null | tr '\0' '\001' | br_norm
    git ls-files -z --others --exclude-standard 2>/dev/null | tr '\0' '\001' |
      LC_ALL=C awk 'BEGIN { RS = "\001" } index($0, "\n") { e = 1; next } { print "A\t" $0 } END { if (e) print "E\t-" }'
  } | battery_rule
}
# rl_start <ci-file> — the start record, once, after the listing is known. Every value passes rl_val or is a closed enum.
rl_start() {
  rl_init
  [ "$RL_ON" -eq 1 ] || return 0
  RL_T0=$(date +%s); RL_RUN=$(rl_val num "$RL_T0")-$(rl_val num "$$")
  RL_U=""; RL_TRUNC=0; RL_ENDED=0; RL_SEEN=""
  rl_rotate
  _rl_head=$(rl_val sha "$(git rev-parse HEAD 2>/dev/null || :)")
  _rl_base=$(rl_val sha "$BASE_SHA")   # RLBASE
  _rl_row0=$(git log -1 --format='%(trailers:key=Kit-Row,valueonly)' HEAD 2>/dev/null | sed -n 1p) || _rl_row0=""
  _rl_row=$(rl_val row "$_rl_row0")   # RLROW
  _rl_lane=$(rl_val num "$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)")   # RLLANE
  _rl_ci=other; [ "$1" != "$CI_DEFAULT" ] || _rl_ci=default
  _rl_n=$(rl_val num "$(grep -c '' "$WORK/listing" 2>/dev/null || :)")
  _rl_j=$(rl_val num "$POOL_J")   # RLJ
  rl_emit "$(printf 'v1 start run=%s ts=%s head=%s base=%s row=%s mode=%s ci=%s lane=%s os=%s j=%s free_mb=%s floor_mb=%s listing=%s brule=%s' \
    "$RL_RUN" "$(rl_val num "$RL_T0")" "$_rl_head" "$_rl_base" "$_rl_row" "$(rl_mode)" "$_rl_ci" "$_rl_lane" "$(rl_os)" "$_rl_j" "$(rl_val num "$FREE")" "$(rl_val num "$FLOOR")" "$_rl_n" "$(rl_val brule "$(rl_brule)")")"
  return 0
}
# rl_u <bucket> <name> <verdict> [run] — one unit, called wherever a verdict row is printed. With `run` its secs and sampled RSS are the unit just run's (RUN_S, RUN_RSS), else 0 and `-`.
# The units pile up in a shell VARIABLE (never a $WORK file: an arm can reach $WORK). A unit past the 16 KB cap is counted in trunc=, not written.
rl_u() {
  [ "$RL_ON" -eq 1 ] || return 0
  _ru_b=$(rl_bucket "$1"); _ru_n=$(rl_name "$1" "$2")
  case $3 in
    OK|FAIL|UNV|CRASH|SKIP|NA|CIB|RACE) _ru_v=$3 ;;
    *) _ru_v=- ;;
  esac
  _ru_s=0; _ru_r=-
  if [ "${4-}" = run ]; then _ru_s=$(rl_val num "$RUN_S"); _ru_r=$(rl_val num "$RUN_RSS"); fi
  _ru_k=$_ru_b:$_ru_n
  _ru_c=$(printf '%s' "$RL_SEEN" | grep -cxF -e "$_ru_k" || :)
  RL_SEEN="$RL_SEEN$_ru_k$NL"
  [ "${_ru_c:-0}" -eq 0 ] || _ru_n="$_ru_n#$((_ru_c + 1))"
  _ru_e=$_ru_b:$_ru_n:$_ru_v:$_ru_s:$_ru_r
  if [ $(( ${#RL_U} + ${#_ru_e} + 1 )) -gt "$RL_UMAX" ]; then RL_TRUNC=$((RL_TRUNC + 1)); return 0; fi
  RL_U=${RL_U:+$RL_U,}$_ru_e
  return 0
}
# rl_end <verdict> <rc|-> — the end record, once. verdict() writes it with the word and rc it prints and returns; cleanup writes INTERRUPTED.
rl_end() {
  [ "$RL_ON" -eq 1 ] && [ "$RL_ENDED" -eq 0 ] || return 0
  RL_ENDED=1
  case $1 in
    OK|FAIL|UNVERIFIED|PLAN|INTERRUPTED) _re_v=$1 ;;
    *) _re_v=UNVERIFIED ;;
  esac
  case $HL_STATE in
    held|released) _re_l=held ;;
    failed) _re_l=failed ;;
    *) _re_l=none ;;
  esac
  _re_now=$(date +%s)
  _re_t=""; [ "$RL_TRUNC" -eq 0 ] || _re_t=" trunc=$RL_TRUNC"
  _re_jf=$(rl_val num "$POOL_JF")   # RLJF: the J the run actually used (1 unless the pool ran); POOL_J stays what ri_wd reads
  rl_emit "$(printf 'v1 end run=%s ts=%s verdict=%s rc=%s wall_s=%s lock=%s lock_wait_s=%s ran=%s fails=%s crash=%s u=%s%s jf=%s race=%s' \
    "$RL_RUN" "$(rl_val num "$_re_now")" "$_re_v" "$(rl_val num "$2")" "$(rl_val num "$((_re_now - RL_T0))")" "$_re_l" "$(rl_val num "$HL_WAIT_S")" \
    "$(rl_val num "$RAN")" "$(rl_val num "$FAILS")" "$(rl_val num "$CRASH")" "${RL_U:--}" "$_re_t" "$_re_jf" "$(rl_val num "$RACE_N")")"
  return 0
}
# rl_rss_tick <pgid> — ONE sample of the arm group's summed RSS (`ps -o rss`, KB); the largest is kept in $WORK/ctl/rss.peak. Called by the watchdog's once-a-second tick; best-effort.
rl_rss_tick() {
  _rk_c=${U_CTL:-$WORK/ctl}   # SWAS-868: a pooled unit samples into its own control dir
  [ ! -L "$_rk_c/rss.peak" ] || return 0   # an arm that planted a link here is never read or written through
  _rk_t=$(ps -A -o pgid= -o rss= 2>/dev/null | LC_ALL=C awk -v g="$1" '$1 == g { s += $2 } END { print s + 0 }') || return 0
  case $_rk_t in
    ''|*[!0-9]*) return 0 ;;
  esac
  _rk_p=0
  [ ! -f "$_rk_c/rss.peak" ] || _rk_p=$(cat "$_rk_c/rss.peak" 2>/dev/null) || _rk_p=0
  case $_rk_p in
    ''|*[!0-9]*) _rk_p=0 ;;
  esac
  [ "$_rk_t" -le "$_rk_p" ] || printf '%s\n' "$_rk_t" > "$_rk_c/rss.peak" 2>/dev/null || :
  return 0
}
# rl_rss_read — sets RUN_RSS from the unit's sample file (digits only, at most 12), else `-` (no process group, no sample, or a unit shorter than one tick).
rl_rss_read() {
  RUN_RSS=-
  _rd_c=${U_CTL:-$WORK/ctl}
  [ -f "$_rd_c/rss.peak" ] && [ ! -L "$_rd_c/rss.peak" ] || return 0
  _rd_v=$(sed -n 1p "$_rd_c/rss.peak" 2>/dev/null) || _rd_v=""
  RUN_RSS=$(rl_val num "$_rd_v")
  return 0
}
# ---- --log-report: read-only; executes nothing and makes no network call (no gh, no fetch: local refs only; its git calls run with GIT_NO_LAZY_FETCH=1, which an older git ignores). It never
# prints a zero for missing data: it prints `unavailable: <why>`. It reads a log only from a state dir that passes rl_init's folder check, and accepts a record only if every value matches the v1 grammar.
# shellcheck disable=SC2016  # the awk program is DATA: nothing in it may expand in the shell.
LRPROG='
function kv(line, a,  n, i, p, t) {
  split("", a); n = split(line, t, " ")
  for (i = 3; i <= n; i++) { p = index(t[i], "="); if (p > 1) a[substr(t[i], 1, p - 1)] = substr(t[i], p + 1) }
  return n }
function sortn(v, n,  i, j, x) {
  for (i = 2; i <= n; i++) { x = v[i]; for (j = i - 1; j >= 1 && v[j] > x; j--) v[j + 1] = v[j]; v[j + 1] = x } }
function pct(v, n, p) { return v[int((p * n + 99) / 100)] }
function gk(r, kind) { return (kind == 1 ? M[r] : B[r]) }
function okf(k, re) { return ((k in f) && f[k] ~ re) }
function oku(s,  m, j, y) {
  if (s == "-") return 1
  m = split(s, y, ",")
  for (j = 1; j <= m; j++) if (y[j] !~ "^[a-z-]+:[-A-Za-z0-9._/#]+:(OK|FAIL|UNV|CRASH|SKIP|NA|CIB|RACE):[0-9]+:([0-9]+|-)$") return 0
  return 1 }
function okstart(n) {
  return (n == 16 && okf("run", "^[0-9]+-[0-9]+$") && okf("ts", "^[0-9]+$") && okf("head", "^[0-9a-f]+$") && length(f["head"]) == 40 \
    && okf("base", "^([0-9a-f]+|-)$") && (f["base"] == "-" || length(f["base"]) == 40) && okf("row", "^([A-Z0-9][-A-Z0-9]*|-)$") \
    && okf("mode", "^(default|warranted|green-on-clone|exports|slow|non-vacuity|plan)$") && okf("ci", "^(default|other)$") && okf("lane", "^[0-9]+$") \
    && okf("os", "^(darwin|linux|other)$") && okf("j", "^[0-9]+$") && okf("free_mb", "^([0-9]+|-)$") && okf("floor_mb", "^[0-9]+$") \
    && okf("listing", "^([0-9]+|-)$") && okf("brule", "^[a-z,-]+$")) }
function okend(n,  e) {
  e = 13 + (("trunc" in f) ? 1 : 0) + (("race" in f) ? 1 : 0) + (("jf" in f) ? 1 : 0)   # RLOKEND
  return (n == e && (!("trunc" in f) || okf("trunc", "^[0-9]+$")) && (!("race" in f) || okf("race", "^[0-9]+$")) && (!("jf" in f) || okf("jf", "^[0-9]+$")) && okf("run", "^[0-9]+-[0-9]+$") && okf("ts", "^[0-9]+$") \
    && okf("verdict", "^(OK|FAIL|UNVERIFIED|PLAN|INTERRUPTED)$") && okf("rc", "^([0-9]+|-)$") && okf("wall_s", "^([0-9]+|-)$") \
    && okf("lock", "^(held|failed|none)$") && okf("lock_wait_s", "^([0-9]+|-)$") && okf("ran", "^[0-9]+$") && okf("fails", "^[0-9]+$") \
    && okf("crash", "^[0-9]+$") && ("u" in f) && oku(f["u"])) }
function grp(label, kind,  r, g, n, G, tmp, any) {
  split("", G)
  for (r in E) if ((r in S) && (r in W)) G[gk(r, kind)] = 1
  any = 0
  for (g in G) { n = 0; split("", tmp)
    for (r in E) if ((r in S) && (r in W) && gk(r, kind) == g) tmp[++n] = W[r]
    sortn(tmp, n); any = 1
    printf "# wall_s by %s %s: n=%d p50=%d p90=%d [M]\n", label, (g == "" ? "?" : g), n, pct(tmp, n, 50), pct(tmp, n, 90) }
  if (!any) printf "# wall_s by %s: unavailable: no run has both a start and an end record\n", label }
{ if ($1 != "v1" || ($2 != "start" && $2 != "end")) { bad++; next }
  nt = kv($0, f); r = f["run"]
  if (($2 == "start" && !okstart(nt)) || ($2 == "end" && !okend(nt))) { bad++; next }
  if ($2 == "start") {
    if (r in S) { bad++; next }
    S[r] = 1; starts++; M[r] = f["mode"]; B[r] = (f["brule"] == "none" ? "none" : "any"); next }
  if (r in E) { bad++; next }
  E[r] = 1; ends++; V[f["verdict"]]++
  if (f["wall_s"] ~ /^[0-9]+$/) W[r] = f["wall_s"] + 0
  if (f["lock_wait_s"] ~ /^[0-9]+$/) { lw += f["lock_wait_s"]; lwn++ }
  if (f["lock"] == "failed") lf++
  if (("jf" in f) && f["jf"] + 0 >= 2) pj++
  if ("race" in f) rcn += f["race"] + 0
  nu = split(f["u"], U, ",")
  for (i = 1; i <= nu; i++) {
    if (split(U[i], x, ":") != 5) continue
    nm = x[2]; sub("#[0-9]+$", "", nm); k = x[1] ":" nm
    if (x[5] ~ /^[0-9]+$/ && (!(k in RM) || x[5] + 0 > RM[k])) RM[k] = x[5] + 0 } }
END {
  if (starts == 0) { printf "# run log: unavailable: no start record could be read (%d malformed line(s) skipped)\n", bad + 0; exit }
  inc = 0; for (r in S) if (!(r in E)) inc++
  printf "# runs: %d started, %d ended, %d incomplete (no end record: killed, or still running); %d malformed line(s) skipped [M]\n", starts, ends + 0, inc, bad + 0
  vs = ""; for (v in V) vs = vs " " v "=" V[v]
  if (vs == "") print "# verdicts: unavailable: no run has ended"; else printf "# verdicts:%s\n", vs
  grp("mode", 1); grp("battery rule", 2)
  printf "# pool runs [M]: jf >= 2 in %d of %d ended run(s); RACE units %d (a unit that failed in parallel and passed serially)\n", pj + 0, ends + 0, rcn + 0
  if (lwn == 0) print "# lock wait: unavailable: no run took the heavy-arm lock"
  else printf "# lock wait: %d s in total over %d run(s) that took the lock; the lock failed in %d run(s) [M]\n", lw, lwn, lf + 0
  mx = 0; mk = ""; nk = 0
  for (k in RM) { nk++; if (RM[k] > mx) { mx = RM[k]; mk = k } }
  if (nk == 0) print "# unit peak RSS: unavailable: no unit carried a sample (a - means no process group, or a unit shorter than one tick)"
  else {
    printf "# unit peak RSS [M, sampled]: the arm group summed RSS, sampled once a second; it misses spikes shorter than a tick and descendants that left the group. U = %d KB (%s) over %d unit(s)\n", mx, mk, nk
    for (t = 1; t <= 5; t++) { bk = ""; bv = -1
      for (k in RM) if (!(k in P) && RM[k] > bv) { bv = RM[k]; bk = k }
      if (bk == "") break
      P[bk] = 1; printf "#   %s %d KB\n", bk, bv } } }'
# shellcheck disable=SC2016
LSPROG='
{ n++
  if ($0 != "none") any++
  m = split($0, t, ",")
  for (i = 1; i <= m; i++) c[t[i]]++ }
END {
  printf "# merged-PR share as of local %s %s (n=%d first-parent commit(s) in the last 30 days; a squash merge is assumed to be one PR) [M]:\n", ref, sha, n
  printf "# guard-touching share (clause a: .claude/ or hooks/ changed): %d/%d [M]\n", c["a"] + 0, n
  printf "# battery-rule share (any of a-e; clause b is partial until P4 names the sourced and fixture paths): %d/%d [M]\n", any + 0, n
  printf "# per clause: a=%d b-partial=%d c=%d d=%d e=%d\n", c["a"] + 0, c["b-partial"] + 0, c["c"] + 0, c["d"] + 0, c["e"] + 0 }'
# lr_runs — the log's own numbers, from runs.log and its rotated files (oldest first). A malformed or repeated line is skipped and counted, never trusted.
lr_runs() {
  case ${HOME-} in
    /?*) ;;
    *) note "run log: unavailable: HOME is unset or not absolute"; return 0 ;;
  esac
  _lr_r=$(git rev-list --max-parents=0 HEAD 2>/dev/null | sed -n 1p) || _lr_r=""
  case $_lr_r in
    ''|*[!0-9a-f]*) note "run log: unavailable: no root commit"; return 0 ;;
  esac
  _lr_d=$HOME/.local/state/sparkwright/prepush/$_lr_r
  if [ -L "$_lr_d" ] || [ ! -d "$_lr_d" ] || ! hl_owner_ok "$_lr_d"; then
    note "run log: unavailable: no run log yet for this repository (each pre-push run writes one)"; return 0
  fi
  _lr_l=$(ls -ld "$_lr_d" 2>/dev/null) || _lr_l=""
  case ${_lr_l%% *} in
    d????[!w]??[!w]*) ;;
    *) note "run log: unavailable: the state dir is not a plain directory, or is group/world-writable"; return 0 ;;
  esac
  set --
  for _lr_s in .3 .2 .1 ""; do
    if [ -f "$_lr_d/runs.log$_lr_s" ] && rl_file_ok "$_lr_d/runs.log$_lr_s"; then
      [ -r "$_lr_d/runs.log$_lr_s" ] || { note "run log: unavailable: a log file cannot be read"; return 0; }
      set -- "$@" "$_lr_d/runs.log$_lr_s"
    fi
  done
  if [ "$#" -eq 0 ]; then note "run log: unavailable: no readable runs.log in the state dir"; return 0; fi
  LC_ALL=C awk "$LRPROG" "$@"
}
# lr_poolk — SWAS-868: `@pool-k units: <N>`, the @pool-k rows in the times table (the units the pool has sent back to serial). Read only by --log-report, never by a run. A missing table, or one that fails tr_state's safety check, is
# `unavailable: <why>`, never 0; an existing table with no @pool-k row is 0. A row whose blob is not 40 or 64 hex digits is skipped, and a key counts once.
lr_poolk() {
  case ${HOME-} in
    /?*) ;;
    *) note "@pool-k units: unavailable: HOME is unset or not absolute"; return 0 ;;
  esac
  _lp_r=$(git rev-list --max-parents=0 HEAD 2>/dev/null | sed -n 1p) || _lp_r=""
  case $_lp_r in
    ''|*[!0-9a-f]*) note "@pool-k units: unavailable: no root commit"; return 0 ;;
  esac
  _lp_d=$HOME/.local/state/sparkwright/prepush/$_lp_r
  if [ -L "$_lp_d" ] || [ ! -d "$_lp_d" ] || ! hl_owner_ok "$_lp_d"; then note "@pool-k units: unavailable: no state dir for this repository yet"; return 0; fi
  _lp_l=$(ls -ld "$_lp_d" 2>/dev/null) || _lp_l=""
  case ${_lp_l%% *} in
    d????[!w]??[!w]*) ;;
    *) note "@pool-k units: unavailable: the state dir is not a plain directory, or is group/world-writable"; return 0 ;;
  esac
  if [ ! -e "$_lp_d/times.tsv" ] && [ ! -L "$_lp_d/times.tsv" ]; then note "@pool-k units: unavailable: no times table yet"; return 0; fi
  if [ ! -f "$_lp_d/times.tsv" ] || [ -L "$_lp_d/times.tsv" ] || [ ! -r "$_lp_d/times.tsv" ]; then note "@pool-k units: unavailable: times.tsv is not a readable regular file"; return 0; fi
  _lp_n=$(LC_ALL=C awk -F'\t' '$1 == "@pool-k" && $2 != "" && $3 ~ /^[0-9a-f]+$/ && (length($3) == 40 || length($3) == 64) { k[$2] = 1 } END { n = 0; for (x in k) n++; print n }' "$_lp_d/times.tsv" 2>/dev/null) || _lp_n=""   # RLPKN
  case $_lp_n in
    ''|*[!0-9]*) note "@pool-k units: unavailable: the times table cannot be read"; return 0 ;;
  esac
  note "@pool-k units: $_lp_n"   # RLPK
}
# lr_share — the guard-touching and battery-rule shares over the first-parent history of the local base ref for the last 30 days (one squash merge is assumed to be one PR).
lr_share() {
  # no lazy fetch from a partial clone's promisor remote: this report makes no network call (an older git ignores GIT_NO_LAZY_FETCH, so there the guarantee is the report's own commands only)
  GIT_NO_LAZY_FETCH=1; export GIT_NO_LAZY_FETCH
  _ls_s=$(git rev-parse --verify --end-of-options "$BASE^{commit}" 2>/dev/null) || {
    note "merged-PR share: unavailable: $BASE does not resolve to a commit locally (this report fetches nothing)"
    return 0
  }
  _ls_l=$(git rev-list --first-parent --since='30 days ago' "$_ls_s" 2>/dev/null) || _ls_l=""
  if [ -z "$_ls_l" ]; then
    note "merged-PR share: unavailable: no first-parent commit in the last 30 days at local $BASE"
    return 0
  fi
  printf '%s\n' "$_ls_l" | while IFS= read -r _ls_c; do
    git diff-tree -r --raw --no-renames --no-commit-id --root -z -m "$_ls_c" 2>/dev/null | tr '\0' '\001' | br_norm | battery_rule
  done | LC_ALL=C awk -v ref="$BASE" -v sha="$(printf '%s' "$_ls_s" | cut -c1-12)" "$LSPROG"
}
log_report() {
  case $BASE in
    -*|*..*) die2 "--base may not start with a dash or contain '..': $BASE" ;;
  esac
  base_ok "$BASE" || die2 "--base outside the closed charset [A-Za-z0-9._/-]+: $BASE"
  note "prepush run log: a measurement cache, declared by the lane, never evidence (per-user and forgeable; a record proves nothing ran). This report executes nothing and makes no network call."
  lr_runs
  lr_poolk
  lr_share
  return 0
}

# ------------------------------------------------------------------- the scrubbed, bounded execution
# unset_pfx <PREFIX> — unset every EXPORTED name under it. A blanket, not a list: a list of names
# fails open on the first name nobody thought of (§3.4, security C16). DISCLOSURE (M-3): a name
# delivered as a TEMPORARY PREFIX on the call, not through the process environment, is absent from `env` and would survive this — immune as called (every scrubbed name is inherited), stated anyway.
unset_pfx() {
  for _v in $(env | LC_ALL=C awk -v p="$1" -F= 'index($1,p)==1 && $1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ {print $1}')
  do unset "$_v" 2>/dev/null || :; done
}
# SWAS-428 (design docs/architecture/2026-10-28-prepush-orphan-428-design.md): an arm runs in a PROCESS GROUP OF ITS OWN, and the ceiling kills the group.
# arm_perl_ok — the group wrapper is /usr/bin/perl (absolute path, a fixed `-e` program, no module, the PERL* library names scrubbed).
arm_perl_ok() { [ -x "$ARM_PERL" ]; }
# arm_nap — a short pause (fractional where sleep allows it).
arm_nap() { sleep 0.2 2>/dev/null || sleep 1; }
# arm_note_w <line> — the outcome of a kill, to the file the caller named in ARM_NOTE (a file: run_timed runs inside a subshell, a variable would not get out).
arm_note_w() { printf '%s\n' "$1" > "${ARM_NOTE:-/dev/null}"; }
# arm_pgid_ok <pgid> — the ONE gate before any group signal: refuses empty, not all digits, <= 1 (`kill -- -1` reaches every process the user owns) and the lane's OWN group.
arm_pgid_ok() {
  _ap=${1-}; _ap_why=""
  case $_ap in ''|*[!0-9]*) _ap_why="not a number" ;; esac
  case $_ap in 0?*) _ap_why="leading zero" ;; esac   # `017570` passes a digits test and a string compare, then names the lane's own group
  [ -n "$_ap_why" ] || [ "$_ap" -gt 1 ] || _ap_why="at most 1"
  [ -n "$LANE_PGID" ] || LANE_PGID=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ') || LANE_PGID=""
  [ -n "$_ap_why" ] || [ -n "$LANE_PGID" ] || _ap_why="the lane's own pgid is unreadable"
  [ -n "$_ap_why" ] || [ "$_ap" != "$LANE_PGID" ] || _ap_why="the lane's own group"
  [ -n "$LANE_PPGID" ] || LANE_PPGID=$(ps -o pgid= -p "$PPID" 2>/dev/null | tr -d ' ') || LANE_PPGID=""
  [ -n "$_ap_why" ] || [ -z "$LANE_PPGID" ] || [ "$_ap" != "$LANE_PPGID" ] || _ap_why="the lane's parent group"
  [ -n "$_ap_why" ] || return 0
  arm_note_w "REFUSED $(hl_clean "${_ap:--}") $(hl_clean "$_ap_why")"
  return 1
}
# arm_read_pgid <file> — prints the pgid in a file that holds exactly ONE line of digits; rc 1 (and nothing) otherwise.
arm_read_pgid() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(grep -c '' < "$1")" = 1 ] || return 1
  _arp=$(sed -n 1p "$1")
  case $_arp in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$_arp"
}
# arm_ps <phase> — the process table, `pid ppid pgid` per line (POSIX -o fields only). The phase names WHICH reading it is, so the selftest can override one.
arm_ps() { ps -A -o pid= -o ppid= -o pgid= 2>/dev/null; }
# arm_desc <leader> — stdin is a table; prints `pid pgid` for every descendant of the leader (by ppid, transitively), the leader excluded.
arm_desc() {
  LC_ALL=C awk -v r="$1" '{ p[$1] = $2; g[$1] = $3 }
    END { m[r] = 1
          do { ch = 0; for (x in p) if (!(x in m) && (p[x] in m)) { m[x] = 1; ch = 1 } } while (ch)
          for (x in m) if (x != r) print x, g[x] }'
}
# arm_killset <pgid> <first-snapshot> <second-table> — the pids OUTSIDE the group that are still in the arm's lineage: descended from a first-snapshot
# pid (or the leader), or re-parented to pid 1 with the SAME pgid as in the first snapshot. A pid that died and was reused fails all three.
arm_killset() {
  printf '%s\n' "$3" | S1=$2 LC_ALL=C awk -v g="$1" '
    BEGIN { n = split(ENVIRON["S1"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], f, " "); if (f[1] != "") { in1[f[1]] = 1; pg1[f[1]] = f[2] } } }
    function lin(x) { return (p[x] in in1) || p[x] == g || (p[x] == 1 && (x in in1) && q[x] == pg1[x]) }
    { p[$1] = $2; q[$1] = $3 }
    END { for (x in p) if (q[x] != g && lin(x)) print x }'
}
# arm_survivors <pgid> [pid…] — what of the group and the listed pids is still alive (one per line). The confirm calls THIS, and the selftest overrides it.
arm_survivors() {
  _as_g=$1; shift
  if kill -s 0 -- "-$_as_g" 2>/dev/null; then
    _as_m=$(arm_ps members | LC_ALL=C awk -v g="$_as_g" '$3 == g { print $1 }')
    if [ -n "$_as_m" ]; then printf '%s\n' "$_as_m"; else printf '%s\n' "-$_as_g"; fi
  fi
  for _as_p in "$@"; do
    if kill -s 0 "$_as_p" 2>/dev/null; then printf '%s\n' "$_as_p"; fi
  done
  return 0
}
# arm_sig <signal> <pgid> / arm_sigp <signal> <pid> — the two signal acts (arm_kill calls them after arm_pgid_ok).
arm_sig() { kill -s "$1" -- "-$2" 2>/dev/null || :; }
arm_sigp() { kill -s "$1" "$2" 2>/dev/null || :; }
# arm_wait_gone <seconds> <pgid> [pid…] — rc 0 as soon as nothing is left, rc 1 when the deadline passes first.
arm_wait_gone() {
  _aw_dl=$(( $(date +%s) + $1 )); shift
  while :; do
    arm_nap
    [ -n "$(arm_survivors "$@")" ] || return 0
    [ "$(date +%s)" -lt "$_aw_dl" ] || return 1
  done
}
# arm_kill <pgid> — the whole kill, for the ceiling, the post-exit leftovers and the INT/TERM trap: refuse a dangerous pgid; snapshot the descendants
# (they may have made groups of their own); TERM then CONT the group and those pids (CONT wakes a member stopped on /dev/tty); wait up to ARM_GRACE_S;
# re-snapshot and KILL the group plus the pids still in the lineage; confirm. rc 0 gone and confirmed · rc 1 refused or NOT confirmed.
# A second word `leader` (ceiling and trap only, where the leader is unreaped so its pid cannot be reused) also signals and confirms the LEADER by pid:
# an arm leader that moved itself into another group (setpgrp) is in no group of ours, and the group acts alone would call it gone.
# The outcome goes to $ARM_NOTE: `OK pgid ngroup nescaped kill-fired` · `NOTCONF pgid ngroup nescaped kill-fired pid…` · `REFUSED pgid why`.
arm_kill() {
  _ak_g=${1-}; _ak_ld=""
  arm_pgid_ok "$_ak_g" || return 1
  [ "${2-}" != leader ] || _ak_ld=$_ak_g
  _ak_t=$(arm_ps first)
  _ak_s1=$(printf '%s\n' "$_ak_t" | arm_desc "$_ak_g")
  _ak_ng=$(printf '%s\n' "$_ak_t" | LC_ALL=C awk -v g="$_ak_g" '$3 == g { n++ } END { print n + 0 }')
  _ak_pl=$(printf '%s\n' "$_ak_s1" | LC_ALL=C awk -v g="$_ak_g" 'NF && $2 != g { print $1 }')
  _ak_ne=$(printf '%s\n' "$_ak_pl" | LC_ALL=C awk 'NF { n++ } END { print n + 0 }')
  arm_sig TERM "$_ak_g"; for _ak_p in $_ak_pl $_ak_ld; do arm_sigp TERM "$_ak_p"; done
  arm_sig CONT "$_ak_g"; for _ak_p in $_ak_pl $_ak_ld; do arm_sigp CONT "$_ak_p"; done
  _ak_set=""; _ak_kf=0
  if ! arm_wait_gone "$ARM_GRACE_S" "$_ak_g" $_ak_pl $_ak_ld; then
    _ak_kf=1
    _ak_set=$(arm_killset "$_ak_g" "$_ak_s1" "$(arm_ps second)")
    arm_sig KILL "$_ak_g"
    for _ak_p in $_ak_set $_ak_ld; do arm_sigp KILL "$_ak_p"; done
    arm_wait_gone "$ARM_CONFIRM_S" "$_ak_g" $_ak_set $_ak_ld || :
  fi
  _ak_left=$(arm_survivors "$_ak_g" $_ak_set $_ak_ld | tr '\n' ' ' | sed 's/ *$//')
  if [ -z "$_ak_left" ]; then arm_note_w "OK $_ak_g $_ak_ng $_ak_ne $_ak_kf"; return 0; fi
  arm_note_w "NOTCONF $_ak_g $_ak_ng $_ak_ne $_ak_kf $_ak_left"
  return 1
}
# arm_group_alive <pgid> — a group with live members, after the leader has been reaped and no ceiling kill ran.
arm_group_alive() { [ ! -e "${U_CTL:-$WORK/ctl}/wd.fired" ] && kill -s 0 -- "-$1" 2>/dev/null; }
# arm_note_apply <ceiling|left> <label> — print and apply the note file run_timed wrote: a NOTE line, UNV on a refusal or an unconfirmed kill,
# and (ceiling) the text report_inv appends to the FAIL line in ARM_CEIL_TXT.
arm_note_apply() {
  _an_f=${U_CTL:-$WORK/ctl}/kill.note; [ "$1" != left ] || _an_f=${U_CTL:-$WORK/ctl}/left.note
  _an_lb=$2
  if [ -L "$_an_f" ]; then   # a state file that is a symlink is never read
    note "NOTE: $_an_lb: a kill-state file is a symlink and was not read; the arm's tree is NOT contained"
    unv "$_an_lb: kill-state file is a symlink"; return 0
  fi
  [ -s "$_an_f" ] || return 0
  _an_l=$(sed -n 1p "$_an_f"); _an_s=${_an_l%% *}; _an_r=${_an_l#"$_an_s"}; _an_r=${_an_r# }
  case $_an_s in
    NOGROUP) ARM_CEIL_TXT="tree NOT contained (no $ARM_PERL: direct child only)"; return 0 ;;
    REFUSED)
      _an_v=${_an_r%% *}; _an_w=$(printf '%s' "${_an_r#* }" | tr _ ' ')
      note "NOTE: arm pgid $_an_v refused ($_an_w); the arm's tree is NOT contained"
      ARM_CEIL_TXT="arm pgid $_an_v refused ($_an_w); tree NOT contained"
      unv "$_an_lb: arm pgid refused ($_an_w); its tree is NOT contained"; return 0 ;;
  esac
  set -f; set -- $_an_r; set +f
  _an_g=${1-}; _an_ng=${2-0}; _an_ne=${3-0}; _an_kf=${4-0}; if [ "$#" -ge 4 ]; then shift 4; else shift "$#"; fi
  _apl=$(printf '%s' "$*" | sed 's/ /, /g')
  _an_kt="TERM+CONT"; [ "$_an_kf" != 1 ] || _an_kt="TERM+CONT, KILL after $ARM_GRACE_S s"   # says KILL only if the KILL really fired
  case "$_an_s:$_an_f" in
    OK:*/kill.note) ARM_CEIL_TXT="process group $_an_g + $_an_ne escaped descendant(s): $_an_kt, confirmed gone" ;;
    NOTCONF:*/kill.note)
      ARM_CEIL_TXT="process group $_an_g + $_an_ne escaped descendant(s): $_an_kt, NOT confirmed gone: pid $_apl still alive"
      unv "$_an_lb: ceiling kill NOT confirmed gone: pid $_apl" ;;
    OK:*) note "NOTE: $_an_lb left $((_an_ng + _an_ne)) process(es) in its group after exit; killed (confirmed gone)" ;;
    NOTCONF:*)
      note "NOTE: $_an_lb left $((_an_ng + _an_ne)) process(es) in its group after exit; killed, NOT confirmed gone: pid $_apl"
      unv "$_an_lb: leftover kill NOT confirmed gone: pid $_apl" ;;
  esac
  return 0
}
# arm_trap_kill — the INT/TERM trap's half: kill the live arm's group (the pgid file run_timed wrote, read through the same gate), then the
# scrubbed_run subshell. Without perl the arms have no group of their own, so only the subshell is stopped, and it says so.
arm_trap_kill() {
  [ -n "$WORK" ] || return 0
  if [ -f "$WORK/ctl/arm.pgid" ]; then
    _at_g=$(arm_read_pgid "$WORK/ctl/arm.pgid") || _at_g=""
    # a pgid read from a FILE is signalled only if that pid is proven, in the current table, to be a descendant of this lane
    if arm_descends "$_at_g"; then ARM_NOTE=$WORK/ctl/trap.note arm_kill "$_at_g" leader || :
    else printf 'REFUSED %s not_a_proven_descendant\n' "$(hl_clean "${_at_g:--}")" > "$WORK/ctl/trap.note"; fi
    rm -f "$WORK/ctl/arm.pgid"   # only AFTER the kill: a re-entered trap must still find it
    [ ! -s "$WORK/ctl/trap.note" ] || printf '# interrupted: arm kill: %s\n' "$(sed -n 1p "$WORK/ctl/trap.note")" >&2
  elif [ -n "$SR_PID" ] && ! arm_perl_ok; then
    printf '# interrupted: no %s, so the running arm is NOT process-grouped and is not killed\n' "$ARM_PERL" >&2
  fi
  arm_pid_term "$(arm_read_pgid "$WORK/ctl/wd.pid" 2>/dev/null)"   # the watchdog, by the pid run_timed recorded
  arm_pid_term "$SR_PID"
  pool_trap_kill   # PLTRAP
  return 0
}
# arm_descends <pid> — rc 0 iff the pid is a descendant of the lane ($$) in the CURRENT process table (ppid chain, bounded).
arm_descends() {
  case ${1-} in ''|*[!0-9]*) return 1 ;; esac
  arm_ps desc | LC_ALL=C awk -v t="$1" -v r="$$" '{ p[$1] = $2 } END { x = t; n = 0; while ((x in p) && n++ < 4096) { if (p[x] == r) exit 0; x = p[x] } exit 1 }'
}
# arm_pid_term <pid> — TERM a pid that is all digits and > 1; anything else signals nothing.
arm_pid_term() { case ${1-} in ''|*[!0-9]*) return 0 ;; esac; [ "$1" -gt 1 ] || return 0; kill -s TERM "$1" 2>/dev/null || :; }
# run_timed <ceiling> <argv…> — runs the argv as an ARM in its own process group (perl setpgrp, then exec) under a watchdog. Two background jobs
# live here, and the header's "the only `&`" claim names them (reviewer M-1): the arm, and the watchdog. The `wait` keeps execution strictly serial.
# On expiry the watchdog writes $WORK/ctl/wd.fired and runs arm_kill (TERM+CONT, grace, re-snapshot, KILL, confirm); the parent then WAITS for it
# (a parent that cut the grace short would never let the KILL fire). After a NORMAL exit a group that still has members is killed the same way.
# No perl: today's direct-child watchdog (TERM, 5 s, KILL), the group acts disabled, and the FAIL line says "tree NOT contained".
run_timed() {
  _tc=$1; shift
  _rtc=${U_CTL:-$WORK/ctl}   # PLCTL
  rm -f "$_rtc/wd.fired" "$_rtc/kill.note" "$_rtc/left.note" "$_rtc/arm.pgid" "$_rtc/wd.pid"
  rm -f "$_rtc/rss.peak"
  _grp=0; ! arm_perl_ok || _grp=1; _lpid=$$
  # The program resets INT and QUIT (a background job starts with them IGNORED, and exec keeps that), then makes the group and execs the argv.
  if [ "$_grp" -eq 1 ]; then
    "$ARM_PERL" -e '$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0) or exit 125; exec {$ARGV[0]} @ARGV or exit 126' -- "$@" & _pid=$!
    printf '%s\n' "$_pid" > "$_rtc/arm.pgid"
  else "$@" & _pid=$!; fi
  ( _i=0
    while [ "$_i" -lt "$_tc" ]; do
      sleep 1; kill -0 "$_pid" 2>/dev/null || exit 0
      kill -0 "$_lpid" 2>/dev/null || { arm_orphaned "$_grp" "$_pid"; exit 0; }
      # SWAS-568: the ceiling counts loop passes, not wall time, so each sample (one ps) stretches every ceiling by about 1-5% [E]; the loop is not changed for it.
      [ "$_grp" -ne 1 ] || rl_rss_tick "$_pid"   # RLRSS
      _i=$((_i+1))
    done
    : > "$_rtc/wd.fired"
    if [ "$_grp" -eq 1 ]; then ARM_NOTE=$_rtc/kill.note arm_kill "$_pid" leader || :
    else printf 'NOGROUP\n' > "$_rtc/kill.note"; kill -TERM "$_pid" 2>/dev/null || :; sleep 5; kill -KILL "$_pid" 2>/dev/null || :; fi ) & _wd=$!
  printf '%s\n' "$_wd" > "$_rtc/wd.pid"
  _rc=0; wait "$_pid" || _rc=$?
  if [ -e "$_rtc/wd.fired" ]; then wait "$_wd" || :
  else kill -TERM "$_wd" 2>/dev/null || :; wait "$_wd" 2>/dev/null || :; fi   # reaped here: bash would otherwise print "Terminated" into the arm's output
  if [ "$_grp" -eq 1 ] && arm_group_alive "$_pid"; then ARM_NOTE=$_rtc/left.note arm_kill "$_pid" || :; fi
  rm -f "$_rtc/arm.pgid" "$_rtc/wd.pid"
  return "$_rc"
}
# arm_orphaned <grouped 0|1> <arm pid> — the lane died (SIGKILL cannot be trapped) while the arm ran: the watchdog, still alive, kills the arm.
arm_orphaned() {
  if [ "$1" -eq 1 ]; then ARM_NOTE=${U_CTL:-$WORK/ctl}/kill.note arm_kill "$2" leader || :; else kill -TERM "$2" 2>/dev/null || :; fi
}
# qtok <token> — the executed-argv log is an EVIDENCE artifact, so it must stay unambiguous even if
# the grammar's charset ever widens (reviewer M-6): a token outside the closed charset is printed in
# single quotes (an embedded `'` as `'\''`), so a token containing a space, a tab or a newline can
# never read as two tokens. With unq() in place (security M2) no derived token reaches the else arm —
# a quoted token DID before that fix, carrying its quote characters into both the log and the argv.
qtok() { case $1 in *[!A-Za-z0-9._/=-]*|'') printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
                    *) printf '%s' "$1" ;; esac; }
# run_inv <ceiling> <argv…> — the argv logged one QUOTED token per line-entry, then executed scrubbed
# subshell with the shim first on PATH and stdin closed. Sets RUN_RC / RUN_S; output in $WORK/out.
run_inv() {
  _cl=$1; shift
  inv_log "$@"
  _t0=$(date +%s); RUN_RC=0; ARM_CEIL_TXT=""
  if [ "$RUN_SPLIT" -eq 1 ]; then   # SWAS-163: a board-bound twin keeps stderr apart (hooks/pre-push's discriminant reads stderr alone)
    run_bg "$_cl" "$@" > "${U_OUT:-$WORK/out}" 2> "$WORK/err" < /dev/null || RUN_RC=$?
    cat "$WORK/err" >> "${U_OUT:-$WORK/out}"   # CRSPLIT
  else run_bg "$_cl" "$@" > "${U_OUT:-$WORK/out}" 2>&1 < /dev/null || RUN_RC=$?; fi
  RUN_S=$(( $(date +%s) - _t0 ))
  inv_finish
}
# inv_log <argv...> — sets _al (the argv, one quoted token each) and appends it to the executed-argv log (SWAS-868: split out of run_inv, the pool logs at dispatch).
inv_log() {
  _al=""; for _t in "$@"; do _al="$_al $(qtok "$_t")"; done
  printf '%s\n' "${_al# }" >> "$ARGVLOG"
}
# inv_finish — what follows a run: the sampled RSS and the kill notes (the pool calls it at the unit's reap, with _al, RUN_RC and RUN_S set).
inv_finish() {
  rl_rss_read   # SWAS-568: the sampled peak RSS of this unit's arm group, for the run log
  arm_note_apply ceiling "${_al# }"; arm_note_apply left "${_al# }"
}
# run_bg — scrubbed_run as the lane's one background job, and a `wait` on it (SWAS-428, design item B1): a shell runs a trap only BETWEEN foreground
# commands, but a trapped signal interrupts `wait` at once, so a TERM to the lane reaches cleanup (and the arm's group) while the arm is still running.
run_bg() {
  scrubbed_run "$@" & SR_PID=$!
  _rb=0; wait "$SR_PID" || _rb=$?
  SR_PID=""
  return "$_rb"
}
# scrubbed_run <ceiling> <argv…> — the scrubbed subshell run_inv executes (the body, factored out so the split-stderr path shares it).
scrubbed_run() {
  _cl=$1; shift
  (
    _kgl=${KIT_GUARD_LOG-}; _hb=$RUN_HB
    unset_pfx GH_; unset_pfx GIT_; unset_pfx KIT_; unset_pfx BOARD_CLAIM_; unset_pfx PREPUSH_
    unset_pfx JIRA_   # SWAS-186: the tracker-contract twin's legacy credential pair (JIRA_EMAIL/JIRA_TOKEN); nothing else needs a JIRA_ name
    unset SSH_AUTH_SOCK SSH_ASKPASS BASH_ENV ENV CDPATH NODE_OPTIONS PYTHONPATH PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC RUBYOPT \
          HERMETIC_BASE IFS 2>/dev/null || :
    HOME=${UNIT_DIR:-$WORK}/empty; GH_CONFIG_DIR=${UNIT_DIR:-$WORK}/gh; TMPDIR=${UNIT_DIR:-$WORK}/tmp; LC_ALL=C   # SWAS-428: an arm's TMPDIR is not the work root itself; `$TMPDIR/..` still reaches `$WORK/ctl`, so nothing there is trusted alone (see STCEIL). SWAS-868: a pooled unit's dirs are its own
    GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_SYSTEM=/dev/null; GIT_OPTIONAL_LOCKS=0   # PL4: after unset_pfx GIT_, so it survives it; an optional index refresh never writes under a co-runner
    [ -z "$SHIMDIR" ] || PATH=$SHIMDIR:$PATH
    export HOME GH_CONFIG_DIR TMPDIR LC_ALL GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_OPTIONAL_LOCKS PATH
    [ -z "$_kgl" ] || { KIT_GUARD_LOG=$_kgl; export KIT_GUARD_LOG; }
    [ -z "$_hb" ] || { HERMETIC_BASE=$_hb; export HERMETIC_BASE; }
    run_timed "$_cl" "$@"
  ) 9>&-   # SWAS-278b: the heavy-arm lock's descriptor is closed for every child, so a child that outlives the lane cannot hold the lock
}
# crash_sig_of <rc> - SWAS-600: rc above 128 is a signal death. Prints the signal NAME and returns 0 when it is a crash (SEGV BUS ILL ABRT FPE SYS TRAP); returns 1 for any other status, for TERM INT HUP KILL, and when kill -l cannot name it. Names, never numbers: BUS is 10 on macOS and 7 on Linux.
crash_sig_of() {
  case ${1-} in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 128 ] || return 1
  _cs_n=$(kill -l $(($1 - 128)) 2>/dev/null) || return 1
  _cs_n=${_cs_n#SIG}
  case $_cs_n in
    SEGV|BUS|ILL|ABRT|FPE|SYS|TRAP) printf '%s\n' "$_cs_n"; return 0 ;;
  esac
  return 1
}
# crash_line_in <file> - SWAS-600: does a captured output hold a shell's crash line? WHOLE-LINE match under LC_ALL=C grep -E, two forms (dash: the bare line; bash 3.2: <file>: line N: <pid> <text>[ <cmd>]). Prose, a table row and a quoted source line do not match. rc 0 found (CRASH_LINE, CRASH_TXT set), 1 none, 2 the scan could not run (a grep rc other than 0 or 1, a signal, or a hit file that cannot be written) - never clean. CEILING, stated: the bash-form prefix is a bare token, so a crash line whose script path contains whitespace does not match; the exit-status evidence still covers a top-level crash.
crash_line_in() {
  CRASH_LINE=""; CRASH_TXT=""
  _cl_x1="'"   # CRX1
  _cl_x2='"'   # CRX2
  _cl_x3='|'   # CRX3
  _cl_s='(Segmentation fault|Bus error|Illegal instruction|Abort trap|Aborted|Floating point exception|Bad system call|Trace/BPT trap|Trace/breakpoint trap)'   # CRSET
  _cl_pre='[^[:space:]'$_cl_x1$_cl_x2'`'$_cl_x3']+'   # CRPRE
  _cl_d='^[[:space:]]*'$_cl_s'(: [0-9]+)?( \(core dumped\))?[[:space:]]*$'
  _cl_b='^'$_cl_pre': line [0-9]+: +[0-9]+ '$_cl_s'(: [0-9]+)?( +\(core dumped\))?( .*)?$'   # CRBASH
  # a failed redirect must never read as "no hit" (bash 3.2 gives rc 1 for it)
  ( : > "${U_CRASH:-$WORK/crash.hit}" ) 2>/dev/null || return 2   # CRHIT
  _cl_r=0
  LC_ALL=C grep -E -e "$_cl_d" -e "$_cl_b" "$1" > "${U_CRASH:-$WORK/crash.hit}" 2>/dev/null || _cl_r=$?   # CRLINE
  case $_cl_r in
    0) ;;
    1) return 1 ;;
    *) return 2 ;;   # CRFAIL
  esac
  CRASH_LINE=$(sed -n 1p "${U_CRASH:-$WORK/crash.hit}") || return 2
  for _cl_n in 'Segmentation fault' 'Bus error' 'Illegal instruction' 'Abort trap' 'Aborted' 'Floating point exception' 'Bad system call' 'Trace/BPT trap' 'Trace/breakpoint trap'; do
    case $CRASH_LINE in
      *"$_cl_n"*) CRASH_TXT=$_cl_n; break ;;
    esac
  done
  return 0
}
# crash_ev_run - SWAS-600: did the run just made (RUN_RC, $WORK/out) crash? rc 0: yes, CRASH_EV names the evidence (the rc form wins when both show); rc 1: no; rc 2: the output scan could not run.
crash_ev_run() {
  CRASH_EV=""; CRASH_BYLINE=0
  if _ce_s=$(crash_sig_of "$RUN_RC"); then CRASH_EV="$_ce_s, rc $RUN_RC"; return 0; fi   # CRRC
  _ce_r=0; crash_line_in "${U_OUT:-$WORK/out}" || _ce_r=$?   # CRLINE2
  case $_ce_r in
    0) CRASH_EV="$CRASH_TXT line"; CRASH_BYLINE=1; return 0 ;;
    1) return 1 ;;
  esac
  return 2
}
# report_inv <bucket> <label> <expect-rc> <ceiling> — one line per invocation; a failing invocation's
# output is printed IN FULL (never tail'd), indented so it can never be mistaken for a report line.
report_inv() { ri_decide "$@"; ri_record "$@"; }
# SWAS-868: report_inv is split into the DECISION (ri_decide: no output, no counter, no log) and the RECORD (ri_record). The pool decides a unit at its reap and records in queue order; the serial paths call both in a row.
# ri_wd — at J >= 2 a ceiling reading also needs the watchdog's own marker (P-1): a fast rc 124 under a late clock is no kill. At J = 1 nothing is added.
ri_wd() { [ "$POOL_J" -lt 2 ] || { [ "$POOL_LATE" -eq 0 ] && [ -e "${U_CTL:-$WORK/ctl}/wd.fired" ]; }; }   # PLWD
# ri_decide <bucket> <label> <expect-rc> <ceiling> — sets RI_KIND (crash|ok|unvsec|ceil|fail) and what the row needs (RI_C, RI_NM, RI_RX, RI_CX, CRASH_EV, CRASH_BYLINE).
ri_decide() {
  RI_KIND=""; RI_C=1; RI_NM=${2% }; RI_RX=""; RI_CX=""
  # SWAS-600: a crashed process is not a verdict. The ceiling test is computed first (its row stays a FAIL); otherwise the crash branch runs BEFORE the early OK return and before FAILS++.
  _ri_ceil=0
  case $RUN_RC in
    124|137|143) [ "$RUN_S" -lt "$4" ] || ! ri_wd || _ri_ceil=1 ;;
  esac
  if [ "$_ri_ceil" -eq 0 ]; then
    RI_C=0; crash_ev_run || RI_C=$?
    if [ "$RI_C" -ne 1 ]; then
      RI_KIND=crash
      # line-only evidence does not name the unit's own exit status, so a status that is not the expected one is named beside it
      if [ "$RI_C" -eq 0 ] && [ "$CRASH_BYLINE" -eq 1 ] && [ "$RUN_RC" -ne "$3" ]; then RI_RX="; unit rc=$RUN_RC, expected $3"; RI_NM="$RI_NM [rc $RUN_RC]"; fi   # CRRCX
      [ "$RI_C" -eq 0 ] || RI_NM="$RI_NM [scan failed]"
      return 0
    fi
  fi
  if [ "$RUN_RC" -eq "$3" ]; then RI_KIND=ok; return 0; fi
  # UNVERIFIED (rc 2 from the secret-scan range arm = gitleaks absent): the scan did NOT run, which is not a
  # FAIL and never an OK. It sets the lane's UNV, so the verdict is UNVERIFIED and the rc non-zero.
  if [ "$RUN_RC" -eq 2 ] && [ "$1" = core-secretscan ]; then RI_KIND=unvsec; return 0; fi
  RI_KIND=fail
  if [ "$_ri_ceil" -eq 1 ]; then
    RI_KIND=ceil; _ri_cr=0; crash_line_in "${U_OUT:-$WORK/out}" || _ri_cr=$?
    [ "$_ri_cr" -ne 0 ] || RI_CX="; crash line also present ($CRASH_TXT)"   # SWAS-600: the row stays a FAIL (FAILS, not CRASH) and names the crash beside it
  fi
  return 0
}
# ri_record <bucket> <label> <expect-rc> <ceiling> — the row, the counters and the log line for the decision ri_decide just made (or the pool restored).
ri_record() {
  RAN=$((RAN+1))
  case $RI_KIND in
    crash)
      if [ "$RI_C" -eq 0 ]; then
        printf '  UNVERIFIED  %-12s %-46s crashed (%s): a crashed process is not a verdict%s\n' "$1" "$2" "$CRASH_EV" "$RI_RX"   # CRROW
      else
        printf '  UNVERIFIED  %-12s %-46s crash scan could not run: no verdict is claimed\n' "$1" "$2"
      fi
      CRASH=$((CRASH+1)); CRASH_LIST="${CRASH_LIST:+$CRASH_LIST, }$RI_NM"   # CRCOUNT
      rl_u "$1" "${2%% *}" CRASH run   # RLRI
      LC_ALL=C sed 's/^/        | /' "${U_OUT:-$WORK/out}" 2>/dev/null || cat "${U_OUT:-$WORK/out}" || :
      return 0 ;;
    ok)
      printf '  OK    %-18s %-46s %4ss\n' "$1" "$2" "$RUN_S"
      rl_u "$1" "${2%% *}" "$RI_OKV" run   # RLRI
      return 0 ;;
    unvsec)
      printf '  UNVERIFIED  %-12s %-46s\n' "$1" "$2"; unv "secret-scan did not run: gitleaks absent or the scan could not run (UNVERIFIED; install gitleaks, CI runs the pinned scan)"
      rl_u "$1" "${2%% *}" UNV run   # RLRI
      LC_ALL=C sed 's/^/        | /' "${U_OUT:-$WORK/out}" 2>/dev/null || :; return 0 ;;
    ceil)
      FAILS=$((FAILS+1))
      _rm='raise PREPUSH_CEILING_S'; [ "$1" != heavy ] || _rm='add a heavy row with the measured budget or raise the ceiling'
      rl_u "$1" "${2%% *}" FAIL run   # RLRI
      printf '  FAIL  %-18s %-46s %4ss  exceeded ceiling — %s%s%s\n' "$1" "$2" "$RUN_S" "$_rm" "${ARM_CEIL_TXT:+; $ARM_CEIL_TXT}" "$RI_CX"; return 0 ;;
  esac
  FAILS=$((FAILS+1))
  printf '  FAIL  %-18s %-46s %4ss  rc=%s (expected %s)\n' "$1" "$2" "$RUN_S" "$RUN_RC" "$3"
  rl_u "$1" "${2%% *}" FAIL run   # RLRI
  # A check's output is ARBITRARY BYTES. Under a UTF-8 locale `sed` refuses (or, on macOS, ABORTS) on
  # an illegal sequence — found by the first live run, which died before its verdict. Byte semantics,
  # and a raw fallback: no report FORMATTING failure may ever cost the run its verdict line.
  LC_ALL=C sed 's/^/        | /' "${U_OUT:-$WORK/out}" 2>/dev/null || cat "${U_OUT:-$WORK/out}" || :
}
# exec_check <bucket> <basename> <argv-string> <expect-rc> <ceiling> — the ONE path that turns a
# derived line into an argv: word-split under `set -f` into POSITIONAL PARAMETERS, never a string.
exec_check() {
  _bk=$1; _b=$2; _as=$3; _x=$4; _cl=$5
  _oi=$IFS; set -f; IFS=' '
  # shellcheck disable=SC2086  # deliberate: the closed-charset argv becomes ARGV, never eval'd.
  set -- $_as
  IFS=$_oi; set +f
  run_inv "$_cl" sh "conformance/$_b.sh" "$@"
  report_inv "$_bk" "$_b $_as" "$_x" "$_cl"
}

# touched_roster — the ONE roster rule within the lane (SWAS-811): selftest-hermetic's own (conformance/*.sh scripts/*.sh hooks/pre-push whose comment-stripped text
# names --selftest), applied to the LISTING and written to $WORK/q.troster, one path per line. A name that cannot become argv is kept: local_defer_scan names it.
touched_roster() {
  : > "$WORK/q.troster"
  while IFS= read -r _st_f; do
    case $_st_f in
      */*/*) continue ;;   # STNEST
      */.*) continue ;;   # the roster's own glob never matches a dot-file
      conformance/*.sh|scripts/*.sh|hooks/pre-push) ;;
      *) continue ;;
    esac
    [ -f "$_st_f" ] || continue
    sed 's/#.*//' "$_st_f" | grep -q -e '--selftest' || continue   # STCOMM
    printf '%s\n' "$_st_f" >> "$WORK/q.troster"
  done < "$WORK/listing"
}
# local_defer_scan — sets SELF_NE/SELF_NE_LIST from the LISTING (exact whole-line match per listed entry), and writes the OTHER touched roster targets (a closed path
# charset, so they can become argv) to $WORK/herm.targets.
local_defer_scan() {
  SELF_NE=0; SELF_NE_LIST=""; : > "$WORK/herm.targets"
  for _e in $LOCAL_DEFER_SELFTESTS; do
    grep -qxF -e "$_e" "$WORK/listing" 2>/dev/null || continue
    SELF_NE=$((SELF_NE+1)); SELF_NE_LIST="${SELF_NE_LIST:+$SELF_NE_LIST, }$_e"; rl_u core-selftest "$_e" CIB
  done
  touched_roster
  while IFS= read -r _st_f; do
    case " $LOCAL_DEFER_SELFTESTS " in *" $_st_f "*) continue ;; esac   # STDEFER
    # a roster target whose name cannot become argv is NOT dropped silently: the clause names it as CI-bound (never claimed as run)
    case $_st_f in *[!A-Za-z0-9._/-]*)   # STCHARSET
      SELF_NE=$((SELF_NE+1)); SELF_NE_LIST="${SELF_NE_LIST:+$SELF_NE_LIST, }$(printf '%s' "$_st_f" | LC_ALL=C tr -c '[:print:]' '?') (name outside the argv charset; CI binds it)"; rl_u core-selftest "$_st_f" CIB; continue ;; esac
    printf '%s\n' "$_st_f" >> "$WORK/herm.targets"
  done < "$WORK/q.troster"
}

# excl_check — selftest-hermetic validates conformance/hermetic-exclusions.txt on every call (reviewer 3: an exclusions-only diff must not
# widen the bypass unvalidated). When the listed target is the ONLY touched selftest no call is made, so a touched exclusions file is
# validated here by the same rule (every non-comment line is <name><TAB><reason>). Prints a FAIL line and counts it; rc 0 always.
excl_check() {
  grep -qxF -e 'conformance/hermetic-exclusions.txt' "$WORK/listing" 2>/dev/null || return 0
  [ -f conformance/hermetic-exclusions.txt ] || return 0
  while IFS= read -r _xl; do
    case $_xl in ''|\#*) continue ;; esac
    _xr=${_xl#*"$TAB"}
    if [ "$_xr" = "$_xl" ] || [ -z "$_xr" ]; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-selftest "conformance/hermetic-exclusions.txt entry '$_xl' carries no <TAB>reason — an unreasoned exclusion is a silent bypass"
      rl_u core-selftest conformance/hermetic-exclusions.txt FAIL
      return 0
    fi
  done < conformance/hermetic-exclusions.txt
}

# ---- SWAS-811: the touched selftests, one hermetic call per target, bounded by the runaway ceiling (ST_CEIL, SWAS-840), never silent -----------------------------------------------------------
# st_blob <path> — the blob sha of the target's bytes AS HEAD HAS THEM (face (b) grades HEAD): the key of its recorded time, never its path (an edited script is unmeasured
# again). Empty when HEAD has no such blob; the caller then treats the target as unmeasured and records nothing.
st_blob() { git rev-parse --verify -q "HEAD:$1" 2>/dev/null || :; }   # STBLOB
# st_okn <n> — rc 0 iff <n> is a plain number a time row may hold: 0, or 1-7 digits with no leading zero. Anything else is no time at all.
st_okn() { printf '%s\n' "$1" | grep -qxE '0|[1-9][0-9]{0,6}'; }   # STOKN
# st_look <blob> — sets _st_ms/_st_s/_st_kc from the times state: a measured row (`@selftest`) or a censored one (`@selftest-k`, a kill at the runaway ceiling (ST_CEIL): the time is a floor),
# whichever is the larger; a value that is no plain number is no time (unmeasured).
st_look() {
  _st_ms=0; _st_s=0; _st_kc=0
  tr_look @selftest "$1"; _st_m=$L_SEC; tr_look @selftest-k "$1"; _st_k=$L_SEC
  st_okn "$_st_m" || _st_m=""
  st_okn "$_st_k" || _st_k=""
  if [ -n "$_st_k" ] && { [ -z "$_st_m" ] || [ "$_st_k" -ge "$_st_m" ]; }; then _st_ms=1; _st_s=$_st_k; _st_kc=1
  elif [ -n "$_st_m" ]; then _st_ms=1; _st_s=$_st_m; fi
}
# st_secs <out-file> — the face seconds of a clean run, read from hermetic's own PASS lines, `(<n> s)`; the sum, or nothing unless exactly two faces printed one.
st_secs() {
  LC_ALL=C sed -n 's/^  PASS: face ([ab]) .* (\([0-9][0-9]*\) s) battery: .*$/\1/p' "$1" |
    LC_ALL=C awk '{ s += $1; n++ } END { if (n == 2) print s }'
}
# st_named <path> — rc 0 iff the run's OWN output names the target: its anchored TARGET line, or an anchored EXCLUDED disposition (ST_EX=1). A target's output reaches
# the lane only indented, on a red, so an anchored line is hermetic's own.
st_named() {
  grep -qxF -e "TARGET: $1 (both faces)" "${U_OUT:-$WORK/out}" 2>/dev/null && return 0   # STTARGET
  P="  EXCLUDED: ${1##*/} — " LC_ALL=C awk 'index($0, ENVIRON["P"]) == 1 { f = 1 } END { exit !f }' "${U_OUT:-$WORK/out}" 2>/dev/null && { ST_EX=1; return 0; }   # STEXCL
  return 1
}
# st_scan — classify the roster targets that can become argv; sets ST_SC to the candidates (`measured<TAB>seconds<TAB>path<TAB>blob<TAB>censored`: unmeasured first, then
# ascending seconds; censored is 1 when the time is a floor from a kill at the runaway ceiling (ST_CEIL), and the blob field may be empty, which `fld` keeps), ST_U and ST_NM (the entries
# named but neither run nor CI-bound). On an adopter tree a scripts/ or hooks/ target is named, not run; a target git cannot show in <merge-base>..HEAD is a FAIL (face (b) grades HEAD).
st_scan() {
  ST_SC=""; ST_U=0; ST_NM=0; _st_tl=0
  git diff --name-only --no-renames "$MB" HEAD > "$WORK/q.committed" 2>/dev/null || : > "$WORK/q.committed"
  while IFS= read -r _st_t; do
    if off_kit; then   # STOFF
      case $_st_t in
        scripts/*|hooks/*)
          note "core-selftest: $_st_t — NOT run locally (kit tree only); your CI grades it only if you wire selftest-hermetic --touched"; ST_NM=$((ST_NM+1)); continue ;;
      esac
      _st_b=${_st_t#conformance/}
      if ! grep -qxF -e "${_st_b%.sh}" "$WORK/q.sel" 2>/dev/null; then   # an adopter keeps today's set (the derived, listed conformance/ selftests), and NAMES the rest
        note "core-selftest: $_st_t — NOT run locally (not derived from your ci.yml)"; ST_NM=$((ST_NM+1)); continue   # STNOTDER
      fi
    fi
    if ! grep -qxF -e "$_st_t" "$WORK/q.committed"; then   # STCOMMIT
      RAN=$((RAN+1)); FAILS=$((FAILS+1)); ST_NM=$((ST_NM+1)); printf '  FAIL  %-18s %s\n' core-selftest "$_st_t: uncommitted — commit before the lane"; rl_u core-selftest "$_st_t" FAIL; continue
    fi
    [ "$_st_tl" -eq 1 ] || { tr_times_init || TR_TAB=""; _st_tl=1; }
    _st_bl=$(st_blob "$_st_t"); _st_ms=0; _st_s=0; _st_kc=0
    [ -z "$_st_bl" ] || st_look "$_st_bl"
    [ "$_st_ms" -eq 1 ] || ST_U=$((ST_U+1))
    ST_SC="$ST_SC$_st_ms$TAB$_st_s$TAB$_st_t$TAB$_st_bl$TAB$_st_kc$NL"
  done < "$WORK/herm.targets"
  ST_SC=$(printf '%s' "$ST_SC" | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2n -k3,3)   # STSORT
}
# st_one <candidate line> — run ONE target (both faces) and reconcile what came back: a clean run that neither printed its TARGET line nor an EXCLUDED disposition is a FAIL.
# SWAS-840: nothing is cut by a budget. Before each call the lane prints the target's prior time ([measured], a [measured floor: killed] row, or unmeasured), and when that time passes
# the 300 s budget it says `over the 300 s budget: run anyway` (a label, counted in ST_OB). What bounds a call is ST_CEIL. A kill at it is read from the watchdog's own evidence and reads
# UNVERIFIED (never OK, never named CI-bound, never a FAIL); its time is recorded as a censored row (`@selftest-k`, max(ceiling + 1 s, the prior time)). A censored row of at least
# ST_CEIL + 1 s names the target UNVERIFIED on the same bytes with no call; a lower floor (every row the old 300 s budget left) is printed and the target runs. The heavy-arm lock is
# taken lazily, just before the first real call.
st_one() {
  _st_ms=$(fld 1 "$1"); _st_s=$(fld 2 "$1"); _st_p=$(fld 3 "$1"); _st_bl=$(fld 4 "$1"); _st_kc=$(fld 5 "$1")
  _st_b12=$(printf '%s' "$_st_bl" | cut -c1-12)
  if [ "$_st_kc" -eq 1 ] && [ "$_st_s" -ge $((ST_CEIL + 1)) ]; then   # STHUNG
    RAN=$((RAN+1)); ST_NM=$((ST_NM+1)); ST_H=$((ST_H+1))
    printf '  UNVERIFIED  %-12s %s\n' core-selftest "$_st_p: killed at >=$_st_s s at $_st_b12 on these bytes [measured floor]; to get out: edit the target, or delete its @selftest-k row in times.tsv, or defer it by a reviewed PR (PREPUSH_NO_CACHE=1 runs it for this run only)"
    unv "core-selftest $_st_p: killed at >=$_st_s s on these bytes"   # STHUNGUNV
    rl_u core-selftest "$_st_p" UNV
    return 0
  fi
  if [ "$_st_lk" -eq 0 ]; then
    _st_lk=1; hl_need core-selftest || _st_lk=2   # STLOCK
    [ "$_st_lk" -eq 1 ] || { RAN=$((RAN+1)); printf '  UNVERIFIED  %-12s %s\n' core-selftest "the heavy-arm lock is not held: the touched selftests are not run"; rl_u core-selftest "$_st_p" UNV; }
  fi
  if [ "$_st_lk" -ne 1 ]; then ST_NM=$((ST_NM+1)); note "core-selftest: $_st_p — NOT run (the heavy-arm lock is not held)"; return 0; fi
  _st_ov=""
  if [ "$_st_ms" -eq 1 ] && [ "$_st_s" -gt "$STBUD" ]; then _st_ov="; over the ${STBUD} s budget: run anyway"; ST_OB=$((ST_OB+1)); fi   # STOVER
  if [ "$_st_ms" -eq 0 ]; then _st_pr="unmeasured (no recorded time at $_st_b12)"
  elif [ "$_st_kc" -eq 1 ]; then _st_pr="prior $_st_s s at $_st_b12 [measured floor: killed]"
  else _st_pr="prior $_st_s s at $_st_b12 [measured]"; fi
  note "core-selftest: $_st_p — $_st_pr$_st_ov"
  _st_cl=$ST_CEIL
  RUN_HB=$BASE; run_inv "$_st_cl" sh conformance/selftest-hermetic.sh "$_st_p"; RUN_HB=""
  ST_EX=0
  # The kill is read from the WATCHDOG's own evidence (run_timed leaves $WORK/ctl/wd.fired when the ceiling fired), not from an exit status: the hermetic harness traps TERM
  # and INT and exits 130 itself, so an rc test (124, 137, 143) misses the very run this exists for. The marker is reachable from a target (`$TMPDIR/../ctl`), so it is not
  # trusted alone: the run must also have lasted the whole ceiling, which the watchdog guarantees and which makes forging the marker pointless (a forger spends the ceiling).
  # twin: st_decide's PSCEIL line is the pool's copy of this decision (and PSNAMED of STNAMED below); change both together
  if [ "$RUN_RC" -ne 0 ] && [ -e "${U_CTL:-$WORK/ctl}/wd.fired" ] && [ "$RUN_S" -ge "$_st_cl" ]; then   # STCEIL
    _st_n=$((_st_cl + 1)); [ "$_st_ms" -eq 0 ] || [ "$_st_s" -le "$_st_n" ] || _st_n=$_st_s
    [ -z "$_st_bl" ] || tr_record @selftest-k "$_st_bl" "$_st_n"   # STREC
    RAN=$((RAN+1)); ST_NM=$((ST_NM+1)); ST_H=$((ST_H+1))
    printf '  UNVERIFIED  %-12s %s\n' core-selftest "$_st_p: killed at the ${ST_CEIL} s runaway ceiling, not proven locally [measured $RUN_S s]${ARM_CEIL_TXT:+; $ARM_CEIL_TXT}"
    unv "core-selftest $_st_p: killed at the ${ST_CEIL} s runaway ceiling"   # STUNV
    rl_u core-selftest "$_st_p" UNV run   # RLUNV
    return 0
  fi
  if [ "$RUN_RC" -eq 0 ] && ! st_named "$_st_p"; then   # STNAMED
    ST_K=$((ST_K+1)); RAN=$((RAN+1)); FAILS=$((FAILS+1)); printf '  FAIL  %-18s %s\n' core-selftest "$_st_p: neither run nor named"; rl_u core-selftest "$_st_p" FAIL; return 0
  fi
  if [ "$ST_EX" -eq 0 ]; then ST_K=$((ST_K+1)); else ST_NM=$((ST_NM+1)); fi
  _st_f0=$FAILS; _st_c0=$CRASH; _st_lab="$_st_p (both faces)"
  [ "$ST_EX" -eq 0 ] || _st_lab="$_st_p (excluded with a reason: not run)"
  report_inv core-selftest "$_st_lab" 0 "$_st_cl"
  { [ "$RUN_RC" -eq 0 ] && [ "$FAILS" -eq "$_st_f0" ] && [ "$CRASH" -eq "$_st_c0" ]; } || return 0
  _st_ss=$(st_secs "${U_OUT:-$WORK/out}"); { [ -z "$_st_ss" ] || [ -z "$_st_bl" ]; } || tr_record @selftest "$_st_bl" "$_st_ss"
  note "core-selftest: $_st_p took $RUN_S s [measured, this run]"
  return 0
}
# selftest_arm — the touched selftests of the default run: scan, run each candidate (the heavy-arm lock is taken lazily by the first), validate a touched exclusions file when
# no call completed, then print the roster line, the over-budget line and the CI-bound note. Every roster entry ends in one of three counts: run (K), CI-bound (M) or named (X: kit-tree-only,
# not derived from the adopter's ci.yml, excluded, uncommitted, a target UNVERIFIED at the runaway ceiling, or not run because the lock was not held). EDGE: a verify.sh listed without --selftest text is in M but not in N.
selftest_arm() {
  ST_N=$(grep -c '' < "$WORK/q.troster" || :); ST_K=0; ST_OB=0; ST_H=0
  st_scan
  _st_lk=0
  # SWAS-868: the pool site (J >= 2 only; pool_arm leaves ST_SC empty when it ran the queue)
  [ "$POOL_J" -lt 2 ] || pool_arm   # PLSITE
  while [ -n "$ST_SC" ]; do   # popped from a VARIABLE: no file or descriptor a child could reach
    _st_l=${ST_SC%%"$NL"*}
    case $ST_SC in
      *"$NL"*) ST_SC=${ST_SC#*"$NL"} ;;
      *) ST_SC="" ;;
    esac
    st_one "$_st_l"
  done
  [ "$ST_K" -ne 0 ] || excl_check   # STEXCL2
  note "touched-selftest roster: $ST_N (run: $ST_K, CI-bound: $SELF_NE, named: $ST_NM, unmeasured: $ST_U)"
  note "touched-selftest over budget: $ST_OB run, $ST_H UNVERIFIED at the ceiling"
  _st_tail="CI's H2 lane grades the faces"; ! off_kit || _st_tail="your CI step that runs it grades them"
  [ "$SELF_NE" -eq 0 ] || note "core-selftest: $SELF_NE touched selftest(s) NOT ENFORCED locally — CI binds them: $SELF_NE_LIST ($_st_tail; this run never claims they ran; the other touched targets are graded explicitly, so an untracked touched selftest script fails here — commit before running the lane)"
}

# ================================================================================ SWAS-868: THE BOUNDED POOL (P2 of the local-parity design, PR 1)
# One pool at the selftest_arm site: the core-selftest candidates and, under --warranted, the core-live checks run at most POOL_J at a time, each in its own scratch dirs and control dir (u<n>); the lock is taken once
# (only when J >= 2 and at least two units are runnable) and J is recomputed after it. A unit is decided at its REAP (read into parent variables), recorded in QUEUE order. After the pool drains, each rc FAIL, each
# ceiling kill that passes the half-ceiling test, and each unit held by a live @pool-k row runs ONCE more, serially, with fresh dirs (t<n>): a serial pass after a pool FAIL reads RACE, a serial FAIL stays FAIL.
# The touched readers, the board gates, the twins and the heavy arms stay serial and untouched. J = 1 never enters this section (selftest_arm calls pool_arm only when POOL_J >= 2).
# Per-unit state lives in shell variables PV_<name>_<n> (pv_set/pv_get; n and name are lane constants, never input).
pv_set() { eval "PV_$2_$1=\$3"; }
pv_get() { eval "printf '%s' \"\${PV_$2_$1-}\""; }
# the globals a unit's decision sets, saved at its reap and restored at its record: short name and global
POOL_VARS='rc:RUN_RC s:RUN_S rss:RUN_RSS ctx:ARM_CEIL_TXT rik:RI_KIND ric:RI_C rinm:RI_NM rirx:RI_RX ricx:RI_CX cev:CRASH_EV cby:CRASH_BYLINE ctxt:CRASH_TXT stk:ST_KIND stex:ST_EX stss:ST_SS stlab:_st_lab'
pool_save() { for _pv in $POOL_VARS; do eval "pv_set \"\$1\" \"\${_pv%%:*}\" \"\${${_pv#*:}-}\""; done; }   # `-`: a global the unit's decision never set (a cl unit has no _st_lab, CRASH_EV may be unset) saves as empty, never a set -u death
pool_load() { for _pv in $POOL_VARS; do eval "${_pv#*:}=\$(pv_get \"\$1\" \"\${_pv%%:*}\")"; done; }
pool_t1() { date +%s; }   # PLT1
pool_half() { [ -n "$1" ] && [ $(( $1 * 2 )) -lt "$2" ]; }   # the half-ceiling rule: a MEASURED time (never a pool row) under half the ceiling
st_hungp() { [ "$_st_kc" -eq 1 ] && [ "$_st_s" -ge $((ST_CEIL + 1)) ]; }
pq_line() { printf '%s\n' "$PQ" | sed -n "${1}p"; }
pq_f() { fld "$2" "$(pq_line "$1")"; }
cl_key() { printf '%s' "$1${2:+ $2}"; }
pool_key() { _pk_l=$(pq_line "$1"); if [ "$(fld 5 "$_pk_l")" = st ]; then fld 6 "$_pk_l"; else cl_key "$(fld 6 "$_pk_l")" "$(fld 8 "$_pk_l")"; fi; }
pool_dirs() { ( umask 077; mkdir -p "$WORK/$1/tmp" "$WORK/$1/empty" "$WORK/$1/gh" "$WORK/ctl/$1" ); }   # <tag>: a unit's own scratch dirs and control dir (0700)
# pool_unit_row — appends the unit described by _pu_* to _pq_raw: ms os label kind target blob argv kc hsec held stale nms ns (the first three are the sort keys). A live @pool-k row for the SAME blob holds the unit for the tail;
# a row for another blob is stale (the unit was edited): the run retires it unless it kills the unit in the pool again.
pool_unit_row() {
  _pu_held=0; _pu_stale=0; _pu_key=$_pu_tgt; [ "$_pu_kind" = st ] || _pu_key=$(cl_key "$_pu_tgt" "$_pu_arg")
  _pu_pk=$(tr_pk_blob "$_pu_key")   # PLPKLOOK
  if [ -n "$_pu_pk" ]; then
    if [ -n "$_pu_bl" ] && [ "$_pu_pk" = "$_pu_bl" ]; then _pu_held=1; else _pu_stale=1; fi
  fi
  _pq_raw="$_pq_raw$_pu_ms$TAB$_pu_os$TAB$_pu_lab$TAB$_pu_kind$TAB$_pu_tgt$TAB$_pu_bl$TAB$_pu_arg$TAB$_pu_kc$TAB$_pu_h$TAB$_pu_held$TAB$_pu_stale$TAB$_pu_nms$TAB$_pu_ns$NL"
}
pool_unit_st() {   # <ST_SC candidate line>
  _st_ms=$(fld 1 "$1"); _st_s=$(fld 2 "$1"); _st_p=$(fld 3 "$1"); _st_bl=$(fld 4 "$1"); _st_kc=$(fld 5 "$1")
  if st_hungp; then return 0; fi
  _pu_kind=st; _pu_lab=$_st_p; _pu_tgt=$_st_p; _pu_bl=$_st_bl; _pu_arg=""; _pu_kc=$_st_kc; _pu_nms=$_st_ms; _pu_ns=$_st_s
  _pu_ms=$_st_ms; _pu_os=0; _pu_h=""
  if [ "$_st_ms" -eq 1 ]; then _pu_os=$_st_s; [ "$_st_kc" -ne 0 ] || _pu_h=$_st_s
  elif [ -n "$_st_bl" ]; then tr_look @pool "$_st_bl"; [ -z "$L_SEC" ] || { _pu_ms=1; _pu_os=$L_SEC; }; fi
  pool_unit_row
}
pool_unit_cl() {   # <basename> <argv>
  _pu_key=$(cl_key "$1" "$2"); _pu_ms=0; _pu_os=0
  tr_look "$1" "$2"; _pu_h=$L_SEC
  tr_look @pool "$_pu_key"; _pu_pl=$L_SEC
  [ -z "$_pu_h$_pu_pl" ] || { _pu_ms=1; _pu_os=${_pu_h:-$_pu_pl}; }
  _pu_bl=$(st_blob "conformance/$1.sh")   # PLCLBLOB
  _pu_kind=cl; _pu_lab="$1 $2"; _pu_tgt=$1; _pu_arg=$2; _pu_kc=0; _pu_nms=0; _pu_ns=0
  pool_unit_row
}
# pool_queue — PQ (numbered lines: the unmeasured units first, then descending seconds, ties by label), PQ_M, PQ_U (the units not held for the tail) and CL_Q (the core-live units left after the --warranted cache skips, in q.order order).
pool_queue() {
  PQ=""; PQ_M=0; PQ_U=0; CL_Q=""; _pq_raw=""
  if [ "$_st_tl" -ne 1 ]; then _pq_u=$UNV; tr_times_init || TR_TAB=""; UNV=$_pq_u; _st_tl=1; fi   # a refused state dir stays what it is at J = 1: no UNV from a time table the serial core-live loop never reads
  if [ "$WARRANTED" -eq 1 ]; then
    while IFS= read -r _r <&3; do
      _rb=${_r%%"$TAB"*}; _ra=${_r#*"$TAB"}
      if cache_skip core-live "$_rb" "$_ra"; then continue; fi
      CL_Q="$CL_Q$_rb$TAB$_ra$NL"
      pool_unit_cl "$_rb" "$_ra"
    done 3< "$WORK/q.order"
  fi
  _pq_s=$ST_SC
  while [ -n "$_pq_s" ]; do
    _pq_l=${_pq_s%%"$NL"*}
    case $_pq_s in *"$NL"*) _pq_s=${_pq_s#*"$NL"} ;; *) _pq_s="" ;; esac
    pool_unit_st "$_pq_l"
  done
  PQ=$(printf '%s' "$_pq_raw" | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2nr -k3,3 | LC_ALL=C awk '{ print NR "\t" $0 }')   # PLSORT
  PQ_M=$(printf '%s\n' "$PQ" | grep -c . || :)
  PQ_U=$(printf '%s\n' "$PQ" | LC_ALL=C awk -F'\t' 'NF >= 11 && $11 == 0 { n++ } END { print n + 0 }')
}
pool_arm() {
  pool_queue
  POOL_USE=0
  if [ "$POOL_J" -ge 2 ] && [ "$PQ_U" -ge 2 ]; then   # PLUSE
    if hl_need core-pool; then
      pool_j; POOL_USE=1; [ "$POOL_J" -ge 2 ] || POOL_USE=0   # PLUSE2
      pool_note
    fi
  fi
  if [ "$POOL_USE" -eq 1 ]; then POOL_JF=$POOL_J; pool_go; ST_SC=""; return 0; fi
  pool_serial
}
# pool_serial — the lane did not take the queue (fewer than two runnable units, a failed lock, or J = 1 after the lock): the core-live checks run serially here, as run_core's loop would have run them; the selftests stay in ST_SC for selftest_arm's own loop.
pool_serial() {
  [ "$WARRANTED" -eq 1 ] || return 0
  printf '%s' "$CL_Q" > "$WORK/cl.q"   # read from a file, as run_core's loop reads q.order (a heredoc-fed loop with break broke CI's semgrep parse)
  while IFS= read -r _r <&3; do
    [ -n "$_r" ] || continue
    _rb=${_r%%"$TAB"*}; _ra=${_r#*"$TAB"}
    hl_need core-live || { RAN=$((RAN+1)); printf '  UNVERIFIED  %-12s %s\n' core-live "the heavy-arm lock is not held: the remaining core-live checks are not run"; rl_u core-live lock UNV; break; }
    exec_cached core-live "$_rb" "$_ra" 0 "$CEIL"
  done 3< "$WORK/cl.q"
}
pool_go() {
  POOL_ON=1
  pool_hung_rows
  pool_loop
  pool_tail   # PLTAIL
  pool_times_end
}
pool_hung_rows() {   # the targets already killed at the ceiling on these bytes: named UNVERIFIED with no call (st_one's STHUNG rule), before the pool starts
  _ph_s=$ST_SC
  while [ -n "$_ph_s" ]; do
    _ph_l=${_ph_s%%"$NL"*}
    case $_ph_s in *"$NL"*) _ph_s=${_ph_s#*"$NL"} ;; *) _ph_s="" ;; esac
    _st_ms=$(fld 1 "$_ph_l"); _st_s=$(fld 2 "$_ph_l"); _st_p=$(fld 3 "$_ph_l"); _st_bl=$(fld 4 "$_ph_l"); _st_kc=$(fld 5 "$_ph_l")
    st_hungp || continue
    _st_b12=$(printf '%s' "$_st_bl" | cut -c1-12)
    RAN=$((RAN+1)); ST_NM=$((ST_NM+1)); ST_H=$((ST_H+1))
    printf '  UNVERIFIED  %-12s %s\n' core-selftest "$_st_p: killed at >=$_st_s s at $_st_b12 on these bytes [measured floor]; to get out: edit the target, or delete its @selftest-k row in times.tsv, or defer it by a reviewed PR (PREPUSH_NO_CACHE=1 runs it for this run only)"
    unv "core-selftest $_st_p: killed at >=$_st_s s on these bytes"
    rl_u core-selftest "$_st_p" UNV
  done
}
pool_loop() {
  POOL_IN=1; _pl_next=1; _pl_run=""; _pl_nrun=0; _pl_pr=1; _pl_done=0; _pl_note=$(date +%s)
  while [ "$_pl_pr" -le "$PQ_M" ]; do   # PLLAST
    while [ "$_pl_next" -le "$PQ_M" ] && [ "$_pl_nrun" -lt "$POOL_J" ]; do   # PLGUARD
      if [ "$(pq_f "$_pl_next" 11)" = 1 ]; then pv_set "$_pl_next" state held
      else pool_start "$_pl_next"; _pl_run="$_pl_run $_pl_next"; _pl_nrun=$((_pl_nrun+1)); fi
      _pl_next=$((_pl_next+1))
    done
    if [ -n "$_pl_run" ]; then
      sleep 1; _pl_left=""; _pl_now=$(date +%s)
      for _pl_n in $_pl_run; do
        if pool_done "$_pl_n" "$_pl_now"; then pool_reap "$_pl_n"; _pl_nrun=$((_pl_nrun-1)); _pl_done=$((_pl_done+1))
        else _pl_left="$_pl_left $_pl_n"; fi
      done
      _pl_run=$_pl_left
    fi
    pool_flush
    if [ $(( $(date +%s) - _pl_note )) -ge 60 ]; then note "pool: $_pl_done of $PQ_M done"; _pl_note=$(date +%s); fi
  done
}
pool_flush() {   # record, in queue order, every unit up to the first one still running
  while [ "$_pl_pr" -le "$PQ_M" ]; do   # PLLAST
    case $(pv_get "$_pl_pr" state) in
      rec) pool_record "$_pl_pr" ;;
      defer|held) : ;;
      *) return 0 ;;
    esac
    _pl_pr=$((_pl_pr+1))
  done
}
pool_start() {   # <n> — dispatch queue unit n in its own dirs, descriptor 9 closed
  _ps_n=$1; _ps_l=$(pq_line "$_ps_n"); _ps_k=$(fld 5 "$_ps_l"); _ps_t=$(fld 6 "$_ps_l"); _ps_a=$(fld 8 "$_ps_l")
  pool_dirs "u$_ps_n"
  if [ "$_ps_k" = st ]; then
    set -- sh conformance/selftest-hermetic.sh "$_ps_t"; _ps_cl=$ST_CEIL; _ps_hb=$BASE
  else
    # the closed-charset argv, single-spaced, becomes ARGV one word at a time (no IFS assignment, no eval)
    set --; _ps_x=$_ps_a
    while [ -n "$_ps_x" ]; do
      _ps_w=${_ps_x%% *}; [ -z "$_ps_w" ] || set -- "$@" "$_ps_w"
      case $_ps_x in *" "*) _ps_x=${_ps_x#* } ;; *) _ps_x="" ;; esac
    done
    set -- sh "conformance/$_ps_t.sh" "$@"; _ps_cl=$CEIL; _ps_hb=""
  fi
  inv_log "$@"; pv_set "$_ps_n" al "${_al# }"; pv_set "$_ps_n" ceil "$_ps_cl"
  pv_set "$_ps_n" bound "$(( _ps_cl + _ps_cl / 10 + 30 ))"   # the poll bound: ceiling x 1.1 + 30 s (the watchdog counts passes, and its ps stretches wall time)
  pv_set "$_ps_n" t0 "$(date +%s)"
  ( U_CTL=$WORK/ctl/u$_ps_n
    U_OUT=$WORK/u$_ps_n/out
    U_CRASH=$WORK/ctl/u$_ps_n/crash.hit
    UNIT_DIR=$WORK/u$_ps_n   # PLUDIR
    RUN_HB=$_ps_hb
    scrubbed_run "$_ps_cl" "$@" ) 9>&- > "$WORK/u$_ps_n/out" 2>&1 < /dev/null &
  pv_set "$_ps_n" pid "$!"
  pv_set "$_ps_n" state run
}
# pool_done <n> <now> — rc 0 when the unit's worker has exited: kill -0 fails, or ps shows a zombie (dash does not reap before `wait`, so kill -0 keeps succeeding on an exited child). Past the poll bound the unit is
# taken by a blocking wait and its clock is not trusted (late): its rc 124/137/143 then reads FAIL, never a ceiling kill. Disclosed: pid reuse is narrowed by the bound, not closed.
pool_done() {
  _pd_pid=$(pv_get "$1" pid)
  kill -0 "$_pd_pid" 2>/dev/null || return 0
  _pd_st=$(ps -o stat= -p "$_pd_pid" 2>/dev/null | tr -d ' ')
  case $_pd_st in
    Z*) return 0 ;;   # PLZ
  esac
  [ $(( $2 - $(pv_get "$1" t0) )) -gt "$(pv_get "$1" bound)" ] || return 1
  pv_set "$1" late 1; return 0
}
pool_reap() {   # <n> — take the worker's rc, read what it left into parent variables and decide, now (Q-3), then mark it reaped
  _pr_n=$1; _pr_rc=0; _pr_pid=$(pv_get "$_pr_n" pid)
  case $_pr_pid in ''|*[!0-9]*) return 0 ;; esac
  [ "$(pv_get "$_pr_n" late)" = 1 ] || pv_set "$_pr_n" t1 "$(pool_t1)"
  wait "$_pr_pid" || _pr_rc=$?
  [ "$(pv_get "$_pr_n" late)" != 1 ] || pv_set "$_pr_n" t1 "$(pool_t1)"
  pool_decide "$_pr_n" "$_pr_rc"
  : > "$WORK/ctl/u$_pr_n/reaped"
}
# pool_decide <n> <rc> — everything that reads the unit's own files happens here, against its own OUT, CTL and CRASH_HIT, into parent variables; only the print, unv, the counters and rl_u wait for queue order.
pool_decide() {
  _pd_n=$1; _pd_l=$(pq_line "$_pd_n")
  _pd_k=$(fld 5 "$_pd_l"); _pd_t=$(fld 6 "$_pd_l"); _pd_a=$(fld 8 "$_pd_l"); _pd_b=$(fld 7 "$_pd_l"); _pd_h=$(fld 10 "$_pd_l"); _pd_lab=$(fld 4 "$_pd_l")
  _pd_c=$(pv_get "$_pd_n" ceil)
  U_CTL=$WORK/ctl/u$_pd_n; U_OUT=$WORK/u$_pd_n/out; U_CRASH=$U_CTL/crash.hit; UNIT_DIR=$WORK/u$_pd_n
  POOL_LATE=$(pv_get "$_pd_n" late); POOL_LATE=${POOL_LATE:-0}
  RUN_RC=$2; ARM_CEIL_TXT=""; RUN_S=$(( $(pv_get "$_pd_n" t1) - $(pv_get "$_pd_n" t0) ))
  _al=$(pv_get "$_pd_n" al); _pd_u=$UNV; UNV=""
  inv_finish > "$UNIT_DIR/fin.out"
  pv_set "$_pd_n" unvn "$UNV"; UNV=$_pd_u
  pv_set "$_pd_n" fin "$(cat "$UNIT_DIR/fin.out")"
  RI_KIND=""; ST_KIND=""; ST_EX=0; ST_SS=""; _pd_s=rec
  if [ "$_pd_k" = st ]; then
    _st_p=$_pd_t; _st_bl=$_pd_b; _st_cl=$_pd_c
    st_decide "$_pd_t" "$_pd_c" "$_pd_t"
    case $ST_KIND in
      neither) _pd_s=defer ;;
      ceil) _pd_s=rec; pool_half "$_pd_h" "$_pd_c" && _pd_s=defer ;;   # PLHALF
      *) case $RI_KIND in fail) _pd_s=defer ;; esac ;;   # PLDEFER
    esac
  else
    ri_decide core-live "$_pd_lab" 0 "$_pd_c"
    case $RI_KIND in
      fail) _pd_s=defer ;;   # PLDEFER
      ceil) _pd_s=rec; pool_half "$_pd_h" "$_pd_c" && _pd_s=defer ;;   # PLHALF
    esac
    pv_set "$_pd_n" cskip 0; ! grep -q '^SKIP' "$U_OUT" 2>/dev/null || pv_set "$_pd_n" cskip 1
  fi
  # times at J >= 2: a clean run only orders the next queue (@pool); a kill the half test does not re-run leaves @pool-k. No @selftest-k and no @selftest row from the pool (P-6).
  if [ "$_pd_s" = rec ]; then
    if [ "$ST_KIND" = ceil ] || [ "$RI_KIND" = ceil ]; then pool_pk_write "$_pd_n"; fi
  fi
  if [ "$RI_KIND" = ok ] && [ "$ST_KIND" != ceil ] && [ "$ST_KIND" != neither ]; then
    _pd_pk=$_pd_b; [ "$_pd_k" = st ] || _pd_pk=$(cl_key "$_pd_t" "$_pd_a")
    [ -z "$_pd_pk" ] || tr_record @pool "$_pd_pk" "$RUN_S"
  fi
  pv_set "$_pd_n" state "$_pd_s"   # PLSTATE
  pool_save "$_pd_n"
  U_CTL=""; U_OUT=""; U_CRASH=""; UNIT_DIR=""; POOL_LATE=0
}
# st_decide <path> <ceiling> <label> — the DECISION half of a target's tail (st_one's, for the pool and PL14b): no output, no counter, no record. Sets ST_KIND (ceil | neither | run), ST_EX, ST_SS and, for run, ri_decide's answer.
st_decide() {
  ST_KIND=""; ST_EX=0; ST_SS=""; _st_cl=$2
  # twin: st_one's STCEIL and STNAMED lines are the serial copy of these two decisions; change both together
  if [ "$RUN_RC" -ne 0 ] && [ -e "${U_CTL:-$WORK/ctl}/wd.fired" ] && [ "$POOL_LATE" -eq 0 ] && [ "$RUN_S" -ge "$_st_cl" ]; then ST_KIND=ceil; return 0; fi   # PSCEIL
  if [ "$RUN_RC" -eq 0 ] && ! st_named "$1"; then ST_KIND=neither; return 0; fi   # PSNAMED
  ST_KIND=run; _st_lab="$1 (both faces)"
  [ "$ST_EX" -eq 0 ] || _st_lab="$1 (excluded with a reason: not run)"
  ri_decide core-selftest "$_st_lab" 0 "$_st_cl"
  [ "$RI_KIND" != ok ] || ST_SS=$(st_secs "${U_OUT:-$WORK/out}")
  return 0
}
pool_st_prior() {   # the prior-time note a target prints before its row (st_one's note, in queue order)
  _st_b12=$(printf '%s' "$_st_bl" | cut -c1-12)
  _st_ov=""
  if [ "$_st_ms" -eq 1 ] && [ "$_st_s" -gt "$STBUD" ]; then _st_ov="; over the ${STBUD} s budget: run anyway"; ST_OB=$((ST_OB+1)); fi   # PSOVER
  if [ "$_st_ms" -eq 0 ]; then _st_pr="unmeasured (no recorded time at $_st_b12)"
  elif [ "$_st_kc" -eq 1 ]; then _st_pr="prior $_st_s s at $_st_b12 [measured floor: killed]"
  else _st_pr="prior $_st_s s at $_st_b12 [measured]"; fi
  note "core-selftest: $_st_p — $_st_pr$_st_ov"
}
# st_apply — the effects of st_decide's verdict (the row, the counters, the log, the times): the pool's twin of st_one's tail. POOL_IN is 1 for the pool's own records (no time rows), 0 for the serial tail (today's rows).
st_apply() {
  case $ST_KIND in
    ceil)
      _st_n=$((_st_cl + 1)); [ "$_st_ms" -eq 0 ] || [ "$_st_s" -le "$_st_n" ] || _st_n=$_st_s
      [ -z "$_st_bl" ] || [ "$POOL_IN" -eq 1 ] || tr_record @selftest-k "$_st_bl" "$_st_n"   # PSREC
      RAN=$((RAN+1)); ST_NM=$((ST_NM+1)); ST_H=$((ST_H+1))
      printf '  UNVERIFIED  %-12s %s\n' core-selftest "$_st_p: killed at the ${ST_CEIL} s runaway ceiling, not proven locally [measured $RUN_S s]${ARM_CEIL_TXT:+; $ARM_CEIL_TXT}"
      unv "core-selftest $_st_p: killed at the ${ST_CEIL} s runaway ceiling"   # PSUNV
      rl_u core-selftest "$_st_p" UNV run   # PSRLUNV
      return 0 ;;
    neither)
      ST_K=$((ST_K+1)); RAN=$((RAN+1)); FAILS=$((FAILS+1)); printf '  FAIL  %-18s %s\n' core-selftest "$_st_p: neither run nor named"; rl_u core-selftest "$_st_p" FAIL; return 0 ;;
  esac
  if [ "$ST_EX" -eq 0 ]; then ST_K=$((ST_K+1)); else ST_NM=$((ST_NM+1)); fi
  ri_record core-selftest "$_st_lab" 0 "$_st_cl"
  [ "$RI_KIND" = ok ] || return 0
  [ -z "$ST_SS" ] || [ -z "$_st_bl" ] || [ "$POOL_IN" -eq 1 ] || tr_record @selftest "$_st_bl" "$ST_SS"
  note "core-selftest: $_st_p took $RUN_S s [measured, this run]"
  return 0
}
pool_cl_cache() {   # <basename> <argv> <skip-like 0|1> — exec_cached's tail: a PASS (not a tool-absent SKIP) is recorded in the --warranted cache
  [ "$CACHE_OK" -eq 1 ] && [ "$RI_KIND" = ok ] && [ "$3" != 1 ] || return 0
  cache_record core-live "core-live $1 $2"
  return 0
}
pool_record() {   # <n> — the unit's decision, in queue order: notes, UNV, row, counters, log
  _pc_n=$1; _pc_l=$(pq_line "$_pc_n")
  _pc_k=$(fld 5 "$_pc_l"); _pc_t=$(fld 6 "$_pc_l"); _pc_a=$(fld 8 "$_pc_l"); _pc_lab=$(fld 4 "$_pc_l"); _pc_c=$(pv_get "$_pc_n" ceil)
  pool_load "$_pc_n"
  U_CTL=$WORK/ctl/u$_pc_n; U_OUT=$WORK/u$_pc_n/out; U_CRASH=$U_CTL/crash.hit; UNIT_DIR=$WORK/u$_pc_n
  _pc_f=$(pv_get "$_pc_n" fin); [ -z "$_pc_f" ] || printf '%s\n' "$_pc_f"
  _pc_u=$(pv_get "$_pc_n" unvn); [ -z "$_pc_u" ] || unv "$_pc_u"
  if [ "$_pc_k" = st ]; then
    _st_p=$_pc_t; _st_bl=$(fld 7 "$_pc_l"); _st_kc=$(fld 9 "$_pc_l"); _st_ms=$(fld 13 "$_pc_l"); _st_s=$(fld 14 "$_pc_l"); _st_cl=$_pc_c
    pool_st_prior; st_apply   # PLREC
  else
    ri_record core-live "$_pc_lab" 0 "$_pc_c"
    pool_cl_cache "$_pc_t" "$_pc_a" "$(pv_get "$_pc_n" cskip)"
  fi
  pv_set "$_pc_n" pr 1
  U_CTL=""; U_OUT=""; U_CRASH=""; UNIT_DIR=""
}
pool_pk_write() {   # <n> — a pooled kill with no half-test re-run: @pool-k <key> <blob> (replacing that key's one row), so the next run holds the unit for the serial tail
  _pw_b=$(pq_f "$1" 7); [ -n "$_pw_b" ] || return 0
  tr_rewrite @pool-k "$(pool_key "$1")" "$_pw_b"; pv_set "$1" pkw 1
}
pool_tail() {   # after the pool drains: each deferred or held unit runs ONCE at J = 1, in queue order, with fresh dirs
  POOL_IN=0; _pt_i=0
  while [ "$_pt_i" -lt "$PQ_M" ]; do
    _pt_i=$((_pt_i+1))
    case $(pv_get "$_pt_i" state) in defer|held) pool_tail_one "$_pt_i" ;; esac
  done
}
pool_tail_one() {
  _pt_n=$1; _pt_l=$(pq_line "$_pt_n"); _pt_was=$(pv_get "$_pt_n" state)
  _pt_k=$(fld 5 "$_pt_l"); _pt_t=$(fld 6 "$_pt_l"); _pt_a=$(fld 8 "$_pt_l"); _pt_lab=$(fld 4 "$_pt_l")
  pool_dirs "t$_pt_n"
  U_CTL=$WORK/ctl/t$_pt_n; U_OUT=$WORK/t$_pt_n/out; U_CRASH=$U_CTL/crash.hit; UNIT_DIR=$WORK/t$_pt_n
  POOL_IN=0; POOL_LATE=0; ST_KIND=""; ST_EX=0; ST_SS=""; RI_KIND=""
  if [ "$_pt_k" = st ]; then
    _st_p=$_pt_t; _st_bl=$(fld 7 "$_pt_l"); _st_kc=$(fld 9 "$_pt_l"); _st_ms=$(fld 13 "$_pt_l"); _st_s=$(fld 14 "$_pt_l"); _st_cl=$ST_CEIL
    RUN_HB=$BASE; run_inv "$_st_cl" sh conformance/selftest-hermetic.sh "$_st_p"; RUN_HB=""
    st_decide "$_st_p" "$_st_cl" "$_st_p"
  else
    set --; _pt_x=$_pt_a   # the same word-by-word split as pool_start (no IFS assignment)
    while [ -n "$_pt_x" ]; do
      _pt_w=${_pt_x%% *}; [ -z "$_pt_w" ] || set -- "$@" "$_pt_w"
      case $_pt_x in *" "*) _pt_x=${_pt_x#* } ;; *) _pt_x="" ;; esac
    done
    run_inv "$CEIL" sh "conformance/$_pt_t.sh" "$@"
    ST_KIND=run; ri_decide core-live "$_pt_lab" 0 "$CEIL"
  fi
  _pt_pass=0; [ "$ST_KIND" = run ] && [ "$RI_KIND" = ok ] && _pt_pass=1   # PLRACE
  if [ "$_pt_was" = defer ] && [ "$_pt_pass" -eq 1 ]; then
    RI_OKV=RACE; RACE_N=$((RACE_N+1)); note "RACE: ${_pt_lab% } failed in parallel, passed serially"
  fi
  _pt_kill=0; [ "$ST_KIND" = ceil ] && _pt_kill=1; [ "$ST_KIND" = run ] && [ "$RI_KIND" = ceil ] && _pt_kill=1
  if [ "$_pt_k" = st ]; then
    pool_st_prior; st_apply
  else
    _pt_sk=0; ! grep -q '^SKIP' "$U_OUT" 2>/dev/null || _pt_sk=1
    ri_record core-live "$_pt_lab" 0 "$CEIL"; pool_cl_cache "$_pt_t" "$_pt_a" "$_pt_sk"
  fi
  RI_OKV=OK
  [ "$_pt_kill" -eq 0 ] || pool_pk_write "$_pt_n"   # a unit killed by the serial run too is held for the tail next time
  _pt_key=$(pool_key "$_pt_n"); pv_set "$_pt_n" pr 1   # PLTAILREC
  U_CTL=""; U_OUT=""; U_CRASH=""; UNIT_DIR=""
}
pool_times_end() {   # an edited unit's stale @pool-k row is retired unless this run killed the unit again (it was rewritten); rows of units this run did not touch are never swept
  _pe_i=0
  while [ "$_pe_i" -lt "$PQ_M" ]; do
    _pe_i=$((_pe_i+1))
    [ "$(pq_f "$_pe_i" 12)" = 1 ] && [ "$(pv_get "$_pe_i" pkw)" != 1 ] || continue
    tr_rewrite @pool-k "$(pool_key "$_pe_i")" -
  done
}
pool_interrupt_u() {   # called by cleanup before rl_end INTERRUPTED: a unit finished but not yet printed is listed UNV
  [ "$POOL_ON" -eq 1 ] || return 0
  _pi_n=0
  while [ "$_pi_n" -lt "$PQ_M" ]; do
    _pi_n=$((_pi_n+1))
    case $(pv_get "$_pi_n" state) in rec|defer) ;; *) continue ;; esac
    [ "$(pv_get "$_pi_n" pr)" != 1 ] || continue
    _pi_l=$(pq_line "$_pi_n"); RUN_S=$(pv_get "$_pi_n" s); RUN_RSS=$(pv_get "$_pi_n" rss); RUN_S=${RUN_S:-0}; RUN_RSS=${RUN_RSS:--}
    if [ "$(fld 5 "$_pi_l")" = st ]; then rl_u core-selftest "$(fld 6 "$_pi_l")" UNV run; else rl_u core-live "$(fld 6 "$_pi_l")" UNV run; fi
  done
}
# ---- the interrupt (P-17): every pooled unit's group, watchdog and worker, one shared grace and one confirm ----
pool_pgids() {   # one validated, proven-descendant arm pgid per line, for every pool and tail control dir that still holds one
  for _pg_d in "$WORK"/ctl/u* "$WORK"/ctl/t*; do
    [ -d "$_pg_d" ] || continue
    _pg_g=$(arm_read_pgid "$_pg_d/arm.pgid" 2>/dev/null) || continue
    arm_descends "$_pg_g" || continue
    ARM_NOTE=$_pg_d/trap.note arm_pgid_ok "$_pg_g" || continue
    printf '%s\n' "$_pg_g"
  done
}
pool_kill_all() {   # _pk_all (pool_pgids' answer, taken BEFORE any worker is signalled: a unit whose worker is gone is re-parented and no longer proves to descend from the lane)
  [ -n "$_pk_all" ] || return 0
  _pk_t=$(arm_ps first)
  for _pk_g in $_pk_all; do
    pv_set "$_pk_g" s1 "$(printf '%s\n' "$_pk_t" | arm_desc "$_pk_g")"
    pv_set "$_pk_g" pl "$(pv_get "$_pk_g" s1 | LC_ALL=C awk -v g="$_pk_g" 'NF && $2 != g { print $1 }')"
    arm_sig TERM "$_pk_g"; arm_sigp TERM "$_pk_g"
    for _pk_p in $(pv_get "$_pk_g" pl); do arm_sigp TERM "$_pk_p"; done
    arm_sig CONT "$_pk_g"; arm_sigp CONT "$_pk_g"
    for _pk_p in $(pv_get "$_pk_g" pl); do arm_sigp CONT "$_pk_p"; done
  done
  _pk_dl=$(( $(date +%s) + ARM_GRACE_S ))   # PLGRACE
  while :; do
    arm_nap; _pk_left=0
    # shellcheck disable=SC2046  # deliberate: the saved pid list is split into one argument per pid (digits only, from arm_desc)
    for _pk_g in $_pk_all; do [ -z "$(arm_survivors "$_pk_g" "$_pk_g" $(pv_get "$_pk_g" pl))" ] || _pk_left=1; done
    [ "$_pk_left" -eq 1 ] || break
    [ "$(date +%s)" -lt "$_pk_dl" ] || break
  done
  [ "$_pk_left" -eq 1 ] || return 0
  _pk_t=$(arm_ps second)
  for _pk_g in $_pk_all; do
    pv_set "$_pk_g" ks "$(arm_killset "$_pk_g" "$(pv_get "$_pk_g" s1)" "$_pk_t")"
    arm_sig KILL "$_pk_g"; arm_sigp KILL "$_pk_g"
    for _pk_p in $(pv_get "$_pk_g" ks); do arm_sigp KILL "$_pk_p"; done
  done
  _pk_dl=$(( $(date +%s) + ARM_CONFIRM_S ))
  while :; do
    arm_nap; _pk_left=0
    # shellcheck disable=SC2046  # deliberate: the saved pid list is split into one argument per pid (digits only, from arm_killset)
    for _pk_g in $_pk_all; do [ -z "$(arm_survivors "$_pk_g" "$_pk_g" $(pv_get "$_pk_g" ks))" ] || _pk_left=1; done
    [ "$_pk_left" -eq 1 ] || break
    [ "$(date +%s)" -lt "$_pk_dl" ] || break
  done
  return 0
}
pool_trap_kill() {
  [ "$POOL_ON" -eq 1 ] || return 0
  _pk_all=$(pool_pgids)
  for _pk_d in "$WORK"/ctl/u* "$WORK"/ctl/t*; do
    [ -d "$_pk_d" ] || continue
    _pk_w=$(arm_read_pgid "$_pk_d/wd.pid" 2>/dev/null) || continue   # the watchdog, by the pid run_timed recorded
    arm_descends "$_pk_w" || continue   # S-3: a pid read from a file is signalled only if it is a proven descendant of the lane, as pool_pgids does
    arm_pid_term "$_pk_w"
  done
  _pk_n=0
  while [ "$_pk_n" -lt "$PQ_M" ]; do _pk_n=$((_pk_n+1)); arm_pid_term "$(pv_get "$_pk_n" pid)"; done   # each unit's worker
  pool_kill_all   # PLKILL
  return 0
}

# -------------------------------------------------------------------------------- the bucket split
is_heavy_row() { grep -q "^$1$TAB""heavy$TAB" "$WORK/twins.ok" 2>/dev/null; }
# ORDERING ONLY, never membership: the cheap doc/board/governance locks first, so a typo-class red
# lands in seconds; everything else keeps ci.yml order. Adding or removing a name here changes WHEN
# a check runs, never WHETHER it runs.
FAST_FIRST='whitespace-clean doc-markers check-links citation-live citation-history decision-id-live roadmap-current runbook-current governing-docs-current doc-budget conformance-mass-budget'
split_buckets() {
  : > "$WORK/q.live"; : > "$WORK/q.sel"; : > "$WORK/q.unt"; : > "$WORK/q.heavy"
  while IFS= read -r _l; do
    case $_l in '#'*|"context$TAB"*) continue ;; esac
    _bk=${_l%%"$TAB"*}; _b=$(fld 4 "$_l"); _a=$(fld 5 "$_l")
    if [ "$_bk" = heavy ] || is_heavy_row "$_b"
    then printf '%s\t%s\n' "$_b" "$_a" >> "$WORK/q.heavy"; continue; fi
    if [ "$_bk" = selftest ]; then
      if grep -qx "conformance/$_b.sh" "$WORK/listing"
      then printf '%s\n' "$_b" >> "$WORK/q.sel"; else printf '%s\n' "$_b" >> "$WORK/q.unt"; fi
      continue
    fi
    printf '%s\t%s\n' "$_b" "$_a" >> "$WORK/q.live"
  done < "$WORK/derive.out"
  : > "$WORK/q.order"
  for _b in $FAST_FIRST; do grep "^$_b$TAB" "$WORK/q.live" >> "$WORK/q.order" 2>/dev/null || :; done
  while IFS= read -r _r; do
    case " $FAST_FIRST " in *" ${_r%%"$TAB"*} "*) continue ;; esac
    printf '%s\n' "$_r" >> "$WORK/q.order"
  done < "$WORK/q.live"
  note "buckets: $(grep -c '' < "$WORK/q.order" || :) core-live · $(grep -c '' < "$WORK/q.sel" || :) core-selftest · $(grep -c '' < "$WORK/q.unt" || :) untouched-selftest · $(grep -c '' < "$WORK/q.heavy" || :) heavy (not run without its flag) · $(grep -c "$TAB""twin$TAB" "$WORK/twins.ok" || :) twin"
}

# ph_newline_ok <values…> — ph_pass prints ONE TOKEN PER LINE, so a newline in a substituted value
# would split one token into two. Refused explicitly, never executed (task-2 reviewer note).
ph_newline_ok() {
  for _v in "$@"; do case $_v in *"
"*) return 1 ;; esac; done
}
# run_shellcheck_scoped — PREPUSH-CORE-DEFAULT: the default's stand-in for the full shellcheck lock (which
# stays in CI and in --warranted's core-live set): `shellcheck.sh --listed <listing>` lints only the
# listing's files that are in the lock's own scope. A FIXED argv through run_inv/report_inv — never eval,
# never `sh -c`. Runs only when the listing names shell (`*.sh`, scripts/kit-guard, hooks/pre-push — the
# lock's scope); a tree without conformance/shellcheck.sh is named, not failed. A SKIP (no shellcheck
# installed) is reported as a SKIP, never as a clean OK.
run_shellcheck_scoped() {
  _sc=0
  while IFS= read -r _p; do
    case $_p in *.sh|scripts/kit-guard|hooks/pre-push) _sc=1; break ;; esac
  done < "$WORK/listing"
  [ "$_sc" -eq 1 ] || { note "skipped: scoped shellcheck — the listing names no shell file"; return 0; }
  if ! grep -qxF 'conformance/shellcheck.sh' "$WORK/scripts" 2>/dev/null; then
    note "skipped: scoped shellcheck — conformance/shellcheck.sh is not a regular file in this tree"; return 0
  fi
  run_inv "$SELFCEIL" sh conformance/shellcheck.sh --listed "$WORK/listing"
  report_inv core-shellcheck "shellcheck --listed (scoped to the listing)" 0 "$SELFCEIL"
  if grep -q '^SKIP:' "$WORK/out" 2>/dev/null; then
    note "core-shellcheck: SKIPPED, not clean — shellcheck is not installed here (CI runs the full lock)"
  fi
}
# run_parselint_scoped — SWAS-236: CI's SAST-parse step reds on a parse error in any conformance/sast-parse-files.txt
# file; shell-parse-lint.sh is the local matcher for it. Lints only the listing ∩ that list (one POSIX awk, entries
# normalised: a CRLF or trailing-blank entry must not match nothing and fail OPEN). A FIXED argv, never eval.
run_parselint_scoped() {
  _pl=conformance/sast-parse-files.txt
  if [ -f "$_pl" ] && grep -qxF 'conformance/shell-parse-lint.sh' "$WORK/scripts" 2>/dev/null; then
    LC_ALL=C awk 'NR==FNR { sub(/[ \t\r]+$/, ""); sub(/^[ \t]+/, ""); sub(/^(\.\/)+/, ""); if ($0 == "" || $0 ~ /^[ \t]*#/) next; w[$0] = 1; next } ($0 in w)' "$_pl" "$WORK/listing" > "$WORK/parselint.list"
  else : > "$WORK/parselint.list"; fi
  [ -s "$WORK/parselint.list" ] || { note "skipped: SAST-parse lint — the listing names no $_pl file"; return 0; }
  run_inv "$SELFCEIL" sh conformance/shell-parse-lint.sh --list "$WORK/parselint.list"
  report_inv core-parselint "shell-parse-lint (touched sast-parse files)" 0 "$SELFCEIL"
  [ "$RUN_RC" -eq 0 ] || note "core-parselint: put esac (and each arm) on its own line; CI's semgrep SAST-parse step stays the net"
}
# run_secretscan_scoped — SWAS-175: the pre-push turn runs the SAME scan CI runs on a pull request, over the
# committed range <merge-base>..HEAD (`secret-scan-wired.sh --range`; a finding is reported BEFORE the push).
# A FIXED argv through run_inv/report_inv — never eval. Blocking: gitleaks absent is UNVERIFIED (report_inv),
# not a skip. No merge-base: the range cannot be derived, so nothing runs and the row is UNVERIFIED.
run_secretscan_scoped() {
  if [ -z "$MB" ]; then
    RAN=$((RAN+1)); printf '  UNVERIFIED  %-12s %s\n' core-secretscan "no merge-base: the PR range is underivable, no scan ran"
    unv "secret-scan range underivable (no merge-base)"; rl_u core-secretscan gitleaks UNV; return 0
  fi
  if ! grep -qxF 'conformance/secret-scan-wired.sh' "$WORK/scripts" 2>/dev/null; then
    RAN=$((RAN+1)); printf '  UNVERIFIED  %-12s %s\n' core-secretscan "conformance/secret-scan-wired.sh is not a regular file in this tree: the scan cannot run"
    unv "secret-scan checker absent (conformance/secret-scan-wired.sh)"; rl_u core-secretscan gitleaks UNV; return 0
  fi
  run_inv "$SELFCEIL" sh conformance/secret-scan-wired.sh --range "$MB"
  report_inv core-secretscan "gitleaks range scan ($MB..HEAD)" 0 "$SELFCEIL"
}
# ---- PREPUSH-CORE-DEFAULT: the --warranted tree-key cache (design §3 item 3, §5) ----------------------
# A CONVENIENCE FOR THE PERSON RUNNING THE LANE, NEVER EVIDENCE: it is local, per-user and forgeable (a
# 32-bit cksum key, a plain file under $HOME), CI never reads it, and a SKIP line is not a pass. It applies
# ONLY to --warranted's arms — each core-live check and each warranted heavy arm — never to the default
# run, never to the board gates (they are cheap). After an arm PASSES the lane
# records `<tree-key> TAB <arm label> TAB <head>` in $HOME/.local/state/sparkwright/prepush/<root-commit>/
# passed (outside the repo: the lane still writes nothing in it) as `key TAB label TAB head TAB <producer root>` (SWAS-278b: the
# physical tree that ran it; a run honours only its OWN. Field 4 is provenance, not authentication: any same-uid process can write it);
# a later --warranted run on the same tree
# prints `SKIP … passed at <head> on this tree` instead of running that arm. A FAIL is never recorded, and
# neither is an arm whose output has a line starting `SKIP` (a tool-absent SKIP-pass is not a pass).
# TWO KEYS, both a cksum of `git ls-tree -r HEAD`:
#   core-live arms   = the FULL tree. Several core-live checks GRADE the bookkeeping paths — whitespace-clean,
#               owner-step-markers, check-links, roadmap-current, decision-id-live, citation-* read BACKLOG.md,
#               CHANGELOG.md and docs/ — so a bookkeeping-only commit must re-run them.
#   heavy arms (claims, non-vacuity, green-on-clone) = the tree MINUS BACKLOG.md, CHANGELOG.md and
#               docs/reviews|plans|architecture/ — their cost is minutes-to-half-an-hour and they do not grade
#               those paths — and their SKIP line says so: "(bookkeeping paths not compared; CI grades them)".
#   dirty tree = the keys cover HEAD only, so ANY uncommitted or untracked change (`git status --porcelain
#               --untracked-files=all` prints anything) BYPASSES the cache for the run (one note).
#   no cache  = (one `cache: off` note, every arm runs) PREPUSH_NO_CACHE=1 · HOME unset/relative · the state
#               dir cannot be created, is not a directory, is a symlink, is group/world-writable, is not
#               owned by the current user, or is unreadable · the `passed` file is not a readable regular file.
# The file is never sourced or eval'd: lookups are exact field equality (awk, via ENVIRON — no -v decoding),
# and an arm label carrying a tab or newline is never cached.
CACHE_OK=0; CACHE_FILE=""; CACHE_KEY_FULL=""; CACHE_KEY_BK=""; CACHE_HEAD=""; CACHE_SKIPS=0; CORE_N=0; TN=0
cache_off() { CACHE_OK=0; note "cache: off — $1 (every --warranted arm runs)"; }
# cache_cksum — stdin -> `<crc>-<len>` on stdout (empty on failure).
cache_cksum() {
  _cc=$(cksum) || return 0
  _cc1=${_cc%% *}; _cc2=${_cc#* }; _cc2=${_cc2%% *}
  case $_cc1$_cc2 in ''|*[!0-9]*) return 0 ;; esac
  printf '%s-%s\n' "$_cc1" "$_cc2"
}
# cache_filter_applied — rc 0: no configured filter is applied to a tracked path (the cache may stay on); rc 1: cache_off was called.
# A filter.* key alone proves nothing (git-lfs installs a SYSTEM-level filter.lfs.* on many hosts and applies it to no path); the tree is
# changed only by a configured clean/smudge/process driver that a path's `filter` attribute NAMES, so that is what is looked for.
cache_filter_applied() {
  _fr=0; git config --get-regexp '^filter\.' > "$WORK/cache.fl" 2>/dev/null || _fr=$?
  if [ "$_fr" -gt 1 ]; then cache_off "the filter.* keys cannot be read"; return 1; fi
  [ "$_fr" -eq 0 ] || return 0
  # the configured driver NAMES: filter.<name>.(clean|smudge|process); a subsection name is case-sensitive, so it is kept as written
  LC_ALL=C awk '{ k = $1; sub(/^filter\./, "", k); if (sub(/\.(clean|smudge|process)$/, "", k)) print k }' "$WORK/cache.fl" > "$WORK/cache.fn" ||
    { cache_off "the configured filter names cannot be read"; return 1; }
  [ -s "$WORK/cache.fn" ] || return 0
  git ls-files -z > "$WORK/cache.lz" 2>/dev/null || { cache_off "git ls-files -z failed (check-attr cannot be run)"; return 1; }
  git check-attr --stdin -z filter < "$WORK/cache.lz" > "$WORK/cache.at" 2>/dev/null ||
    { cache_off "git check-attr failed (the filter attributes cannot be read)"; return 1; }
  # fail closed on a stream that is not exactly one `path NUL attr NUL value NUL` triple per tracked path
  _pn=$(tr -cd '\000' < "$WORK/cache.lz" | wc -c | tr -d ' '); _an=$(tr -cd '\000' < "$WORK/cache.at" | wc -c | tr -d ' ')
  case $_pn$_an in ''|*[!0-9]*) cache_off "git check-attr output cannot be counted"; return 1 ;; esac
  if [ "$_an" -ne $((_pn * 3)) ]; then cache_off "git check-attr output is not one path/attribute/value triple per tracked path"; return 1; fi
  # a value line equal to a configured name: a SUPERSET of the applied set (a path that spells a name, or contains a newline, only over-matches), so it fails closed
  tr '\000' '\n' < "$WORK/cache.at" > "$WORK/cache.av"
  _gr=0; grep -qxFf "$WORK/cache.fn" "$WORK/cache.av" 2>/dev/null || _gr=$?
  if [ "$_gr" -gt 1 ]; then cache_off "the filter attribute values cannot be compared"; return 1; fi
  if [ "$_gr" -eq 0 ]; then cache_off "a configured filter is applied to tracked paths (a clean/smudge filter changes what the tree contains)"; return 1; fi
  return 0
}
cache_init() {
  CACHE_OK=0
  [ "$WARRANTED" -eq 1 ] || return 0
  if [ "${PREPUSH_NO_CACHE-}" = 1 ]; then cache_off "PREPUSH_NO_CACHE=1"; return 0; fi
  case ${HOME-} in /?*) ;; *) cache_off "HOME is unset or not absolute"; return 0 ;; esac
  # SWAS-278b (design 6.3): three things hide tree content from the HEAD-only keys. Checked BEFORE `git status`, which they can distort.
  git --no-optional-locks ls-files -v > "$WORK/cache.lv" 2>/dev/null || { cache_off "git ls-files -v failed"; return 0; }
  if LC_ALL=C awk 'substr($0, 1, 2) != "H " { f = 1 } END { exit !f }' "$WORK/cache.lv"; then
    cache_off "git ls-files -v shows a tag other than H (skip-worktree or assume-unchanged entries hide tree content from the key)"; return 0
  fi
  _spr=0; _sp=$(git config --bool --get core.sparseCheckout 2>/dev/null) || _spr=$?
  if [ "$_spr" -gt 1 ]; then cache_off "core.sparseCheckout cannot be read"; return 0; fi
  if [ "$_sp" = true ]; then cache_off "core.sparseCheckout is on (the keys cover the committed tree, not the checked-out one)"; return 0; fi
  cache_filter_applied || return 0
  cache_label_ok "$ROOT" || { cache_off "the tree path holds a tab or newline (it is the producer column)"; return 0; }
  # ANY output at all (modified, staged, or untracked — every file, not collapsed dirs) means the HEAD-only
  # keys do not describe the tree under test. --no-optional-locks: a read must not write .git/index.
  git --no-optional-locks status --porcelain --untracked-files=all > "$WORK/cache.st" 2>/dev/null ||
    { cache_off "git status failed"; return 0; }
  [ ! -s "$WORK/cache.st" ] || { cache_off "uncommitted or untracked changes (the keys cover HEAD only)"; return 0; }
  git ls-tree -r HEAD > "$WORK/cache.lt" 2>/dev/null || { cache_off "no HEAD tree"; return 0; }
  CACHE_KEY_FULL=$(cache_cksum < "$WORK/cache.lt")
  CACHE_KEY_BK=$(LC_ALL=C awk -F'\t' '{ p = $2
    if (p == "BACKLOG.md" || p == "CHANGELOG.md" || index(p, "docs/reviews/") == 1 ||
        index(p, "docs/plans/") == 1 || index(p, "docs/architecture/") == 1) next
    print }' "$WORK/cache.lt" | cache_cksum)
  if [ -z "$CACHE_KEY_FULL" ] || [ -z "$CACHE_KEY_BK" ]; then cache_off "no usable tree key"; return 0; fi
  _rc0=$(git rev-list --max-parents=0 HEAD 2>/dev/null | sed -n 1p)
  case $_rc0 in ''|*[!0-9a-f]*) cache_off "no root commit"; return 0 ;; esac
  CACHE_HEAD=$(git rev-parse HEAD 2>/dev/null | cut -c1-12)
  _sd=$HOME/.local/state/sparkwright/prepush/$_rc0
  if [ ! -e "$_sd" ] && [ ! -L "$_sd" ]; then
    ( umask 077; mkdir -p "$_sd" ) 2>/dev/null || { cache_off "the state dir cannot be created"; return 0; }
  fi
  # Only the leaf is checked: parent dirs and POSIX ACLs are NOT — acceptable, because the cache is a
  # convenience for the person running the lane, never evidence.
  _ls=$(ls -ld "$_sd" 2>/dev/null) || { cache_off "the state dir cannot be inspected"; return 0; }
  _perm=${_ls%% *}; _own=$(printf '%s\n' "$_ls" | awk '{ print $3 }'); _me=$(id -un 2>/dev/null) || _me=""
  # `d` first: a symlink (`l`) or a plain file (`-`) fails here; the 6th and 9th chars are group/world write.
  case $_perm in d????[!w]??[!w]*) ;; *) cache_off "the state dir is not a plain directory, or is group/world-writable"; return 0 ;; esac
  if [ -z "$_me" ] || [ "$_own" != "$_me" ]; then cache_off "the state dir is not owned by the current user"; return 0; fi
  if [ ! -r "$_sd" ] || [ ! -w "$_sd" ] || [ ! -x "$_sd" ]; then cache_off "the state dir is unreadable"; return 0; fi
  CACHE_FILE=$_sd/passed
  if [ -e "$CACHE_FILE" ] || [ -L "$CACHE_FILE" ]; then
    if [ ! -f "$CACHE_FILE" ] || [ -L "$CACHE_FILE" ] || [ ! -r "$CACHE_FILE" ]; then
      cache_off "the passed file is not a readable regular file"; return 0
    fi
  fi
  CACHE_OK=1
  note "cache: on — state $_sd (a local convenience, never evidence; PREPUSH_NO_CACHE=1 turns it off)"
}
# cache_label_ok <label> — a label with a tab or newline would corrupt the record: never cached.
cache_label_ok() { case $1 in *"$TAB"*|*"
"*) return 1 ;; esac; return 0; }
# cache_skip <bucket> <basename> <argv> — rc 0 and a SKIP line when this arm already passed on this tree.
cache_skip() {
  [ "$CACHE_OK" -eq 1 ] || return 1
  [ -f "$CACHE_FILE" ] || return 1
  _cs_l="$1 $2 $3"; cache_label_ok "$_cs_l" || return 1
  cache_key_for "$1"
  # SWAS-278b (design 6.3): a record is honoured only when its producer (field 4) is THIS tree's own physical root.
  _cs_s=$(K=$_ckey L=$_cs_l P=$ROOT awk -F'\t' '$1 == ENVIRON["K"] && $2 == ENVIRON["L"] && $4 == ENVIRON["P"] { print $3; exit }' "$CACHE_FILE" 2>/dev/null) || _cs_s=""
  case $_cs_s in ''|*[!0-9a-f]*) return 1 ;; esac
  _cs_x=""; [ "$1" = core-live ] || _cs_x=" (bookkeeping paths not compared; CI grades them)"
  printf '  SKIP  %-18s %-46s — passed at %s on this tree (producer %s)%s\n' "$1" "$2${3:+ $3}" "$_cs_s" "$ROOT" "$_cs_x"
  rl_u "$1" "$2" SKIP
  CACHE_SKIPS=$((CACHE_SKIPS+1))
  return 0
}
# cache_key_for <bucket> — sets _ckey: core-live arms key on the FULL tree, heavy arms on the bookkeeping-free one.
cache_key_for() { if [ "$1" = core-live ]; then _ckey=$CACHE_KEY_FULL; else _ckey=$CACHE_KEY_BK; fi; }
# cache_record <bucket> <label> — replace this arm's record with the bucket's current key (one record per
# arm), atomically.
cache_record() {
  cache_label_ok "$2" || return 0
  cache_key_for "$1"
  _cr_t=$CACHE_FILE.$$
  { if [ -f "$CACHE_FILE" ]; then L=$2 P=$ROOT awk -F'\t' '$2 != ENVIRON["L"] || $4 != ENVIRON["P"]' "$CACHE_FILE" || :; fi
    printf '%s\t%s\t%s\t%s\n' "$_ckey" "$2" "$CACHE_HEAD" "$ROOT"; } > "$_cr_t" 2>/dev/null &&
    mv -f "$_cr_t" "$CACHE_FILE" 2>/dev/null || rm -f "$_cr_t" 2>/dev/null
  return 0
}
# exec_cached <bucket> <basename> <argv> <expect-rc> <ceiling> — exec_check, then record the arm iff it
# PASSED (FAILS did not move) AND its output has no line starting `SKIP` (a tool-absent SKIP-pass is rc 0
# but proved nothing). A failing arm is never recorded.
exec_cached() {
  _ec_f=$FAILS; _ec_c=$CRASH
  exec_check "$@"
  [ "$CACHE_OK" -eq 1 ] && [ "$FAILS" -eq "$_ec_f" ] && [ "$CRASH" -eq "$_ec_c" ] || return 0   # CRCACHE
  if grep -q '^SKIP' "${U_OUT:-$WORK/out}" 2>/dev/null; then return 0; fi
  cache_record "$1" "$1 $2 $3"
  return 0
}
# run_core — the DEFAULT (no --warranted) runs the change's OWN surface: scoped shellcheck, the touched
# selftests, then (in run_lane) the board gates and the twins. The CI-derived core-live checks run only
# under --warranted (a superset of the old default); CI runs every one of them either way.
run_core() {
  CORE_N=$(grep -c '' < "$WORK/q.order" || :)    # read BEFORE any child runs: the verdict's scope text uses it
  if [ "$WARRANTED" -eq 1 ]; then
    cache_init
    [ "$POOL_J" -lt 2 ] || { : > "$WORK/q.none"; CL_FEED=$WORK/q.none; }   # SWAS-868: at J >= 2 the core-live checks join the pool at the selftest_arm site (pool_arm reads q.order itself)
    while IFS= read -r _r <&3; do
      _rb=${_r%%"$TAB"*}; _ra=${_r#*"$TAB"}
      if cache_skip core-live "$_rb" "$_ra"; then continue; fi
      hl_need core-live || { RAN=$((RAN+1)); printf '  UNVERIFIED  %-12s %s\n' core-live "the heavy-arm lock is not held: the remaining core-live checks are not run"; rl_u core-live lock UNV; break; }
      exec_cached core-live "$_rb" "$_ra" 0 "$CEIL"
    done 3< "${CL_FEED:-$WORK/q.order}"
  else
    note "core-live: $CORE_N CI-derived checks NOT run by default — --warranted runs them; CI runs every one"
    run_shellcheck_scoped
  fi
  run_parselint_scoped
  run_secretscan_scoped
  local_defer_scan
  selftest_arm   # STARM
  if [ -s "$WORK/q.unt" ]; then
    note "untouched-selftest: $(grep -c '' < "$WORK/q.unt" || :) derived --selftest invocations NOT run (--all is the scheduled sweep)"
    [ "$VERBOSE" -eq 0 ] || sed 's/^/#   /' "$WORK/q.unt"
  fi
}
# ---- PREPUSH-BOARD-GATES-PARITY (design docs/architecture/2026-09-29-prepush-board-gates-parity-design.md) ----
# board_derive — write $WORK/board.rows (`name<TAB>script-basename<TAB>args`, one row per line) from the
# `check control` rows of conformance/verify.sh whose script is conformance/backlog-*.sh or
# conformance/board-*.sh (or exactly conformance/roadmap-current.sh) and whose args carry no --selftest: the LIVE board gates CI reaches only through
# `verify.sh --require`. Derived, never hand-listed, so a new board gate joins by being registered.
# `--adopter` is METADATA-ONLY in verify.sh (it runs the command; it never skips), so it is dropped here
# and the command runs exactly as the registry states it. A row whose script or args leave the closed
# charset is written with script `!` and REFUSED at run time (FAIL, never executed). Only grep/read/case/tr.
board_derive() {
  : > "$WORK/board.rows"
  [ -f conformance/verify.sh ] || return 0
  grep -E '^check control [^ ]+ +(--adopter +)?sh conformance/((backlog|board)-|roadmap-current\.sh( |$))' conformance/verify.sh 2>/dev/null |
  while read -r _c _k _bn _rest; do
    set -f; set -- $_rest; set +f
    [ "${1-}" != --adopter ] || shift
    [ "${1-}" = sh ] || continue
    [ "$#" -ge 2 ] || continue
    _bs=$2; shift 2
    _live=1; _ok=1
    for _t in "$@"; do
      case $_t in --selftest*) _live=0 ;; esac
      case $_t in *..*|/*) _ok=0 ;; esac
      [ "$(printf '%s' "$_t" | LC_ALL=C tr -cd 'A-Za-z0-9._/=-')" = "$_t" ] || _ok=0
    done
    [ "$_live" -eq 1 ] || continue
    _bs=${_bs#conformance/}; _bs=${_bs%.sh}
    basename_ok "$_bs" || _bs='!'
    basename_ok "$_bn" || _bn='(unsafe-name)'
    [ "$_ok" -eq 1 ] || _bs='!'
    printf '%s\t%s\t%s\n' "$_bn" "$_bs" "$*"
  done > "$WORK/board.rows"
  # Underived-row detector (security L-1): every non-selftest `check` line naming a board script must have
  # become a row (derived or refused); a surplus is an off-shape registration, surfaced as one `!` row.
  _reg=$(grep -E '^check ' conformance/verify.sh | grep -E 'conformance/((backlog|board)-|roadmap-current\.sh( |$))' | grep -vcE '(^|[[:space:]])--selftest' || :)
  _got=$(wc -l < "$WORK/board.rows" | tr -d ' ')
  [ "$_reg" -le "$_got" ] || printf '(underived-registry-row)\t!\t\n' >> "$WORK/board.rows"
}
# run_board — the core board-gate arm. Triggered by the lane's OWN listing containing BACKLOG.md; each
# derived gate is a `core-board` table row, a FAIL fails PARITY-CORE (FAILS), and the gate's own output is
# printed by report_inv. Zero derived rows while BACKLOG.md is in the listing is a FAIL: a silently empty
# set is the vacuous green this arm exists to remove. Ceiling: SELFCEIL, not the 120 s core ceiling —
# backlog-current takes ~2 min locally and a kill would read as a red board.
run_board() {
  if ! grep -qxF 'BACKLOG.md' "$WORK/listing" 2>/dev/null; then
    note "skipped: board gates — BACKLOG.md not in the diff (expected $ET_BOARD)"; return 0
  fi
  board_derive
  if [ ! -s "$WORK/board.rows" ]; then
    RAN=$((RAN+1)); FAILS=$((FAILS+1))
    printf '  FAIL  %-18s %s\n' core-board "no board gate derived from conformance/verify.sh although BACKLOG.md is in the diff"
    rl_u core-board board-gates FAIL
    return 0
  fi
  while IFS="$TAB" read -r _bn _bb _ba <&3; do
    if [ "$_bn" = '(underived-registry-row)' ]; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-board "$_bn a board-gate registry row was not derived — check its shape"
      rl_u core-board underived-registry-row FAIL
      continue
    fi
    if [ "$_bb" = '!' ]; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-board "$_bn REFUSED: script or argv outside the closed charset (never executed)"
      rl_u core-board "$_bn" FAIL
      continue
    fi
    if ! grep -qxF "conformance/$_bb.sh" "$WORK/scripts" 2>/dev/null; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-board "$_bn ($_bb.sh) not a regular file in conformance/ (never executed)"
      rl_u core-board "$_bn" FAIL
      continue
    fi
    _oi=$IFS; set -f; IFS=' '
    # shellcheck disable=SC2086  # deliberate: the closed-charset argv becomes ARGV, never eval'd.
    set -- $_ba
    IFS=$_oi; set +f
    run_inv "$SELFCEIL" sh "conformance/$_bb.sh" "$@" 3<&-
    report_inv core-board "$_bn ($_bb.sh${_ba:+ $_ba})" 0 "$SELFCEIL"
  done 3< "$WORK/board.rows"
}
# twin_na <row> <rc> (SWAS-163) — 0 only for a board-bound twin whose ONLY failure is NOT ENFORCED on a
# hosted-tracker tree: a closed two-name list, the row's own NOT ENFORCED rc, a hosted backend read by the
# one resolver (sets TWIN_BE), and hooks/pre-push's M-1 discriminant over the captured output. rc 0 is never here.
twin_na() {
  case "$1:$2" in loop-state:1|backlog-presence:3) ;; *) return 1 ;; esac
  TWIN_BE=$( exec 2>/dev/null; . conformance/backlog-lib.sh; resolve_backend . ) || TWIN_BE=""
  case $TWIN_BE in ''|md|unrecognized:*) return 1 ;; esac
  # loop-state: STDERR alone, minus its epilogue (the hook's stream); backlog-presence prints its notice on stdout, so it reads both.
  _tp='/^$/d'; _tf=$WORK/out; [ "$1" != loop-state ] || { _tp='/^loop-state: FAIL /,$d'; _tf=$WORK/err; }
  _tn_all=$(LC_ALL=C sed "$_tp" "$_tf" | LC_ALL=C grep -v '^[[:space:]]*$') || :
  [ -n "$_tn_all" ] && [ -z "$(printf '%s\n' "$_tn_all" | LC_ALL=C grep -v 'NOT ENFORCED' || :)" ]
}
# The twin rows: the local argv of a CI shape the grammar refuses. Each one prints its row's REASON,
# because a twin is a CLAIM about equivalence and the reader must be able to judge it.
run_twins() {
  PH_LISTING=$WORK/listing; PH_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  # reviewer M-5: on a DETACHED HEAD `--abbrev-ref HEAD` is the literal string `HEAD`, which is what
  # {branch} then substitutes. Disclosed rather than guessed: a twin whose local argv asks a check
  # about "the branch" may legitimately red there, because in that state there is no branch to ask
  # about — the honest answer is the row's red, not a lane-invented refname.
  [ "$PH_BRANCH" != HEAD ] || note "detached HEAD: {branch} substitutes the literal \`HEAD\` — a twin row that asks a check about the branch may red for that reason alone"
  PH_HEAD=$(git rev-parse HEAD 2>/dev/null || echo HEAD); PH_BASE_BOARD=$WORK/base-board.md
  git show "$BASE_SHA:BACKLOG.md" > "$PH_BASE_BOARD" 2>/dev/null || : > "$PH_BASE_BOARD"
  if ! ph_newline_ok "$PH_LISTING" "$PH_BRANCH" "$PH_BASE_BOARD" "$PH_HEAD"; then
    unv "newline in a substituted value"
    note "REFUSED: a {listing}/{branch}/{base-board}/{head} value contains a newline — no twin row is executed"
    return 0
  fi
  while IFS= read -r _row <&4; do
    [ "$(fld 2 "$_row")" = twin ] || continue
    _tb=$(fld 1 "$_row"); _tx=$(fld 5 "$_row")
    set --
    while IFS= read -r _tk; do set -- "$@" "$_tk"; done <<TWEOF
$(subst_argv "$(fld 4 "$_row")")
TWEOF
    _script=$1; shift
    # SWAS-278a R2 (and security L1): the tracker-contract twin is credential-free only because its --conf names a file that does NOT exist.
    # If that file exists at run time, in any tree the twin runs in, the row would read it as a conf and could reach the credential library:
    # refuse the row, named, UNVERIFIED, never run.
    _cfp=''; _cpv=''
    for _ca in "$@"; do if [ "$_cpv" = --conf ]; then _cfp=$_ca; fi; _cpv=$_ca; done
    case $_cfp in
      credential-free.conf|*/credential-free.conf)
        if [ -e "$_cfp" ] || [ -L "$_cfp" ]; then
          unv "twin $_tb: its credential-free conf $_cfp EXISTS in this tree - the row is refused and not run"
          note "REFUSED: twin $_tb names $_cfp as its credential-free conf, and that file exists: a conf that exists is read, and could reach the credential library. Delete $_cfp; the row stays unrun (UNVERIFIED)"
          continue
        fi ;;
    esac
    case $_tb in loop-state|backlog-presence) RUN_SPLIT=1 ;; esac
    run_inv "$CEIL" sh "conformance/$_script" "$@"; RUN_SPLIT=0
    # SWAS-600: a crash is never read as the NOT ENFORCED N/A
    _tw_c=0; crash_ev_run || _tw_c=$?   # CRTWIN
    if [ "$_tw_c" -eq 1 ] && twin_na "$_tb" "$RUN_RC"; then
      RAN=$((RAN+1)); TN=$((TN+1)); rl_u twin "$_tb" NA; basename_ok "$TWIN_BE" || TWIN_BE='(unsafe-name)'
      printf "  N/A   %s  NOT ENFORCED only (backend '%s') — CI binds the row leg through tracker-board-gates where that context is required on the base; not verifiable locally\n" "$_tb" "$TWIN_BE"
    else report_inv twin "$_tb $(fld 4 "$_row")" "${_tx:-0}" "$CEIL"; fi
    note "  twin reason: $(fld 7 "$_row")"
  done 4< "$WORK/twins.ok"
}
# Tier 2 — never without its flag (§3.3, ruling §4.2), always behind the memory floor, each arm
# calling only the check that already exists. `--slow` runs the `heavy` ROWS inside their budget-s;
# a job-placement heavy invocation with no row has no measured budget and is named, not run.
run_heavy() {
  [ -n "$HEAVY" ] || return 0
  hl_need "$HEAVY" || return 0
  heavy_allowed "$HEAVY" || return 0
  case $HEAVY in
    green-on-clone) exec_check heavy green-on-clone '' 0 "$HCEIL" ;;
    exports)        exec_check heavy adopter-export-claims '' 0 "$HCEIL" ;;
    non-vacuity)    exec_check heavy non-vacuity "--only $HEAVY_ARG" 0 "$HCEIL" ;;
    slow)
      while IFS= read -r _row <&5; do
        [ "$(fld 2 "$_row")" = heavy ] || continue
        _hb=$(fld 1 "$_row"); _hbud=$(fld 6 "$_row")
        while IFS= read -r _r <&6; do
          [ "${_r%%"$TAB"*}" = "$_hb" ] || continue
          exec_check heavy "$_hb" "${_r#*"$TAB"}" 0 "$_hbud"
        done 6< "$WORK/q.heavy"
      done 5< "$WORK/twins.ok" ;;
  esac
}

# ---- PREPUSH-BATTERY-CHANGE-SCOPED (design §3.1/§3.2; amends C11 per R-C11) --------------------
# expected times — MEASURED 2026-09-27 on the owner's dev machine (TRACKER-DRIFT-SCHEDULED-WIRING);
# estimates, never a budget or gate.
ET_CLAIMS="~29m (local; ~1m in CI)"; ET_NONVAC="~1m"; ET_GOC="~27m"; ET_BOARD="~2m"

# printable_safe <s> — true if <s> is safe to echo verbatim (printable ASCII, no control bytes).
# Used ONLY to decide whether a REJECTED non-vacuity basename may be named in a skip line — R-C11
# condition 1 forbids ever forwarding it, but naming it in a note is not forwarding it.
printable_safe() { printf '%s' "$1" | LC_ALL=C grep -qx '[ -~]*'; }

# basename_ok <s> — the ONE byte-semantic charset predicate for a conformance/*.sh basename (S1,
# security fix), used at EVERY site that judges it: the derivation, the run-time re-check, and the
# typed --non-vacuity flag. A shell `case` glob class like `[!a-z0-9.-]*` is LOCALE-DEPENDENT — under
# a UTF-8 locale (e.g. LANG=en_US.UTF-8 on macOS /bin/sh, bash 3.2) it passes multi-byte characters
# (é, ß, a curly-quote) that a byte-semantic reader (dash, or the same check under LC_ALL=C) would
# reject, so the run-time behaviour of the derivation and the flag disagreed with each other on
# exactly those inputs. `LC_ALL=C grep -qxE` is byte-semantic regardless of the caller's locale. The
# leading-dash and empty refusals are preserved: the first character class already excludes both.
# Both twins use the whole-string `tr -cd` form rather than `grep -qxE` because `grep -x` matches
# PER LINE — a value with an embedded newline (e.g. `printf 'ok\n;id x'`) would pass if any one of
# its lines matched the charset, letting a newline-smuggled payload reach a caller downstream
# (R-C11 c1 regression, security). `tr -cd` strips everything outside the charset from the WHOLE
# string (newline included, since it is not in either charset), so comparing the result back to the
# original `$1` refuses any input containing a byte the charset doesn't allow, anywhere in the
# string — including a newline. The leading-dash and empty refusals are preserved explicitly since
# `tr -cd` alone would accept a lone "-" or leading "-something" that's otherwise in-charset.
basename_ok() {
	case $1 in '' | -*) return 1 ;; esac
	[ "$(printf '%s' "$1" | LC_ALL=C tr -cd 'a-z0-9.-')" = "$1" ]
}
# base_ok <s> — the TWIN of basename_ok for --base's charset ([A-Za-z0-9._/-]+): same locale class,
# same byte-semantic fix, same rationale. Unlike basename_ok, base_ok's charset itself includes
# `-` with no first-character restriction, so only the empty refusal is added explicitly here.
base_ok() {
	[ -n "$1" ] || return 1
	[ "$(printf '%s' "$1" | LC_ALL=C tr -cd 'A-Za-z0-9._/-')" = "$1" ]
}

# warranted_derive — the CLOSED derivation of which Tier-2 arms THIS listing warrants (design §3.1).
# Writes $WORK/warranted (one `warranted: <arm>` line per arm, in the FIXED run order
# claims -> non-vacuity <b>.sh... (deduped, sorted) -> green-on-clone) and $WORK/skipped (one
# `skipped: <arm> — <reason> (expected ~<t>)` line per non-warranted arm). `exports`/`slow`/the
# container arm are NEVER derived here (R-C11 condition 6) — they keep their own recommendation
# lines below, unchanged, because they are CI's arms, never `--warranted`'s.
#
# Rules (design §3.1):
#   · non-vacuity <b>: an edited/untracked `conformance/<b>.sh` whose basename passes EXACTLY the
#     `--non-vacuity` flag's closed charset ([a-z0-9.-]+, non-empty, no leading dash — R-C11 cond.1)
#     AND is a `^check ` row's script target in conformance/verify.sh. A charset failure is skipped
#     and NEVER enters the registered-check test; a charset pass that is not a check row is skipped
#     naming the exit-2 the flag would hit today.
#   · green-on-clone: the listing touches conformance/ or scripts/, OR is not export-ignored-only
#     (the identical ci-classify-changes.sh --export-ignored-only test used below for --exports).
#   · claims: the listing touches conformance/claims.tsv, or an edited conformance/<x>.sh appears in
#     claims.tsv's field-3 verifier column (read for MATCHING only — never executed, R-C11 cond.2).
#   · docs-only ($DOCS_ONLY = true): nothing warranted; claims and green-on-clone are skipped
#     `— docs-only delta`.
#
# HONEST CEILING (design §6): this is a PATH heuristic, not a guarantee. A diff can red a check it
# never touches (the #705 cross-slice N-3 collision was exactly that; CI is the backstop, not this
# derivation). The claims trigger follows edits to a VERIFIER, not a file a verifier merely reads
# (README, VERSION…) — CI's cf-claims covers those. The expected-time table is one machine's
# measurement, dated, and is never a budget or a gate.
warranted_derive() {
  : > "$WORK/warranted"; : > "$WORK/skipped"
  if [ "$DOCS_ONLY" = true ]; then
    printf 'skipped: claims — docs-only delta (expected %s)\n' "$ET_CLAIMS" >> "$WORK/skipped"
    printf 'skipped: green-on-clone — docs-only delta (expected %s)\n' "$ET_GOC" >> "$WORK/skipped"
    return 0
  fi

  # claims
  _cw=0
  rm -f "$WORK/.claims_matched"
  if grep -qx 'conformance/claims.tsv' "$WORK/listing"; then _cw=1
  else
    if [ -f conformance/claims.tsv ]; then
      # R-C11 c2 (matching only, never forwarded): the basename reaches awk through the ENVIRONMENT,
      # not `-v` — `-v name=value` backslash-DECODES its value (so a committed
      # `conformance/agent\055autonomy.sh` decoded to `conformance/agent-autonomy.sh` and false-matched
      # the real verifier). ENVIRON carries the raw string, no escape processing.
      sed -n 's|^conformance/\(.*\)\.sh$|\1|p' "$WORK/listing" | while IFS= read -r _cb; do
        if t="conformance/$_cb.sh" awk -F'\t' \
             'BEGIN{t=ENVIRON["t"]} !/^#/{n=split($3,a,/[ \t]+/); for(i=1;i<=n;i++) if(a[i]==t) f=1} END{exit !f}' \
             conformance/claims.tsv
        then : > "$WORK/.claims_matched"
        fi
      done
    fi
    if [ -f "$WORK/.claims_matched" ]; then _cw=1; fi
  fi
  if [ "$_cw" -eq 1 ]; then printf 'warranted: claims\n' >> "$WORK/warranted"
  else printf 'skipped: claims — the listing touches neither conformance/claims.tsv nor a verifier it names (expected %s)\n' "$ET_CLAIMS" >> "$WORK/skipped"
  fi

  # non-vacuity, one per edited/untracked conformance/*.sh basename, deduped + sorted
  sed -n 's|^conformance/\(.*\)\.sh$|\1|p' "$WORK/listing" | LC_ALL=C sort -u | while IFS= read -r _b; do
    if ! basename_ok "$_b"; then
      if printable_safe "$_b"; then _pb=$_b; else _pb='(unprintable)'; fi
      printf 'skipped: non-vacuity %s — basename outside the closed charset (expected %s)\n' "$_pb" "$ET_NONVAC" >> "$WORK/skipped"
      continue
    fi
    _vkrows=conformance/verify.sh   # SWAS-607: the kit-self rows live in verify-kitself.rows on a kit tree; both are the registry
    if [ -f conformance/verify-kitself.rows ]; then _vkrows="conformance/verify.sh conformance/verify-kitself.rows"; fi
    # shellcheck disable=SC2086
    if awk -v t="conformance/$_b.sh" \
         '$1=="check"{for(i=2;i<=NF;i++) if($i==t) f=1} END{exit !f}' \
         $_vkrows 2>/dev/null
    then printf 'warranted: non-vacuity %s.sh\n' "$_b" >> "$WORK/warranted"
    else printf 'skipped: non-vacuity %s — not a verify.sh check row (non-vacuity --only would exit 2) (expected %s)\n' "$_b" "$ET_NONVAC" >> "$WORK/skipped"
    fi
  done

  # green-on-clone
  if grep -qE '^(conformance/|scripts/)' "$WORK/listing"; then
    printf 'warranted: green-on-clone\n' >> "$WORK/warranted"
  elif [ -f conformance/ci-classify-changes.sh ] &&
       ! sh conformance/ci-classify-changes.sh --export-ignored-only "$WORK/listing" 2>/dev/null |
         grep -qx 'export_ignored_only=true'; then
    printf 'warranted: green-on-clone\n' >> "$WORK/warranted"
  else
    printf 'skipped: green-on-clone — the listing touches neither conformance/ nor scripts/, and is export-ignored-only (expected %s)\n' "$ET_GOC" >> "$WORK/skipped"
  fi
}

# print_warranted — the warranted-set announcement (R-C11 c3: printed ONCE, before the first arm
# runs). `reco()` and `run_warranted()` both need it; a shared, idempotent printer means neither
# duplicates the other's lines (design: "T1's reco lines already print it, so reuse them").
_WARRANTED_PRINTED=0
print_warranted() {
  [ "$_WARRANTED_PRINTED" -eq 0 ] || return 0
  _WARRANTED_PRINTED=1
  warranted_derive
  note "warranted (--warranted runs exactly this set, serially, in this order):"
  if [ -s "$WORK/warranted" ]; then
    while IFS= read -r _w; do note "  $_w"; done < "$WORK/warranted"
  else
    note "  none warranted by this listing"
  fi
  if [ -s "$WORK/skipped" ]; then
    while IFS= read -r _s; do note "  $_s"; done < "$WORK/skipped"
  fi
}

# heavy_busy <arm-note-name> — R-C11 c4, the concurrency guard. Refuses (over-denies) when `ps`
# cannot be read at all, and refuses when a process matching the CLOSED, fixed-string list below is
# found running and is NOT the lane itself or one of its own descendants (walked by ppid up to 1).
# An ANCESTOR of the lane that matches the closed list (e.g. `sh conformance/verify.sh --require`,
# which is exactly how CI's `check control` row runs this very selftest) is NOT a descendant, so it
# counts as busy and the arm is REFUSED — deliberately: an enclosing heavy arm really does hold
# memory the concurrency guard exists to protect, so ancestor-busy is over-deny BY DESIGN, not a bug.
# Prints only the PID and the lane's OWN literal for the matched name — never the raw command line —
# and never signals anything it finds (no `kill`, ever).
heavy_busy() {
  _hb_arm=$1
  _hb_lane=$$
  : > "$WORK/ps.raw"
  if ! ps -Ao pid=,ppid=,args= > "$WORK/ps.raw" 2>/dev/null || [ ! -s "$WORK/ps.raw" ]; then
    note "UNVERIFIED: cannot enumerate processes (ps) — the $_hb_arm arm is refused"
    unv "cannot enumerate processes for the concurrency guard"
    return 1
  fi
  while read -r _hb_pid _hb_ppid _hb_cmd; do
    case $_hb_pid in ''|*[!0-9]*) continue ;; esac
    case $_hb_ppid in ''|*[!0-9]*) continue ;; esac
    _hb_name=""
    case $_hb_cmd in
      *green-on-clone.sh*)  _hb_name="green-on-clone.sh" ;;
      *non-vacuity.sh*)     _hb_name="non-vacuity.sh" ;;
      *adopter-export*)     _hb_name="adopter-export" ;;
      *claims-registry.sh*) _hb_name="claims-registry.sh" ;;
    esac
    # R6: a fixed-string test, not a quoted-glob `case` pattern (`*"verify.sh --require"*`) — grep -qF
    # matches the two-word literal without relying on case's quote-inside-glob idiom. LC_ALL=C so a
    # locale-invalid byte elsewhere in a `ps` row (e.g. a stray non-UTF-8 byte in an unrelated
    # process's argv) cannot make grep fail to match the literal (security: under-deny).
    if [ -z "$_hb_name" ] && printf '%s' "$_hb_cmd" | LC_ALL=C grep -qF -- 'verify.sh --require'; then
      _hb_name="verify.sh --require"
    fi
    [ -n "$_hb_name" ] || continue
    # exclude the lane itself and its own descendants: walk the ppid chain up to pid 1.
    _hb_p=$_hb_pid; _hb_desc=0; _hb_hops=0
    while :; do
      [ "$_hb_p" != "$_hb_lane" ] || { _hb_desc=1; break; }
      [ "$_hb_p" != 1 ] || break
      _hb_hops=$((_hb_hops+1)); [ "$_hb_hops" -le 4096 ] || break   # a cycle-defence bound, never real
      _hb_np=$(LC_ALL=C awk -v p="$_hb_p" '$1==p{print $2; exit}' "$WORK/ps.raw")
      case $_hb_np in ''|*[!0-9]*) break ;; esac
      [ "$_hb_np" != "$_hb_p" ] || break
      _hb_p=$_hb_np
    done
    [ "$_hb_desc" -eq 0 ] || continue
    note "REFUSED: another heavy arm is running (pid $_hb_pid, $_hb_name) — the $_hb_arm arm is refused; re-run when it finishes"
    unv "another heavy arm is running"
    return 1
  done < "$WORK/ps.raw"
  return 0
}

# run_warranted — R-C11 c6/c3: with --warranted, run EXACTLY the derived set, serially, in the fixed
# order the derivation wrote it, each arm through exec_check/run_inv only (no new exec path). A red
# arm counts in FAILS and the next arm still runs (never `&`, never concurrent).
run_warranted() {
  [ "$WARRANTED" -eq 1 ] || return 0
  print_warranted
  # S2 (security fix, the one fail-open path): arms run with TMPDIR=$WORK, so an arm could APPEND to
  # $WORK/warranted mid-loop — a `while read … < file` loop that kept reading the live file would then
  # run MORE than print_warranted just printed. Snapshot the set into a shell variable BEFORE the first
  # arm runs, and iterate the SNAPSHOT via a heredoc (no subshell, so FAILS/UNV set inside the loop
  # still survive): never read a TMPDIR-exposed file again once a child has run. (Disclosure:
  # `run_heavy slow`'s `twins.ok`/`q.heavy` reads, and `$WORK/argv.log`'s post-arms display-only read
  # (~:1136 area), are the pre-existing same class — unchanged here.)
  [ -s "$WORK/warranted" ] || return 0
  _rw_snapshot=$(cat "$WORK/warranted")
  while IFS= read -r _w; do
    _arm=${_w#warranted: }
    case $_arm in
      claims)
        if cache_skip heavy claims-registry ''; then continue; fi
        hl_need warranted-claims || continue
        heavy_allowed warranted-claims || continue
        heavy_busy warranted-claims || continue
        exec_cached heavy claims-registry '' 0 "$HCEIL"
        ;;
      "non-vacuity "*)
        _nb=${_arm#non-vacuity }; _nb=${_nb%.sh}
        # defence in depth (T1 already filtered at derivation time): re-check the closed charset.
        if ! basename_ok "$_nb"; then
          note "UNVERIFIED: a warranted non-vacuity basename failed the closed charset on re-check — never forwarded: $_nb"
          unv "warranted non-vacuity basename outside the closed charset"
          continue
        fi
        if cache_skip heavy non-vacuity "--only $_nb.sh"; then continue; fi
        hl_need warranted-non-vacuity || continue
        heavy_allowed warranted-non-vacuity || continue
        heavy_busy warranted-non-vacuity || continue
        exec_cached heavy non-vacuity "--only $_nb.sh" 0 "$HCEIL"
        ;;
      green-on-clone)
        if cache_skip heavy green-on-clone ''; then continue; fi
        hl_need warranted-green-on-clone || continue
        heavy_allowed warranted-green-on-clone || continue
        heavy_busy warranted-green-on-clone || continue
        exec_cached heavy green-on-clone '' 0 "$HCEIL"
        ;;
      *)
        note "UNVERIFIED: an unrecognised warranted line is never executed: $_w"
        unv "unrecognised warranted line"
        ;;
    esac
  done <<RWEOF
$_rw_snapshot
RWEOF
}

# ===================================================================== TOUCHED READERS (SWAS-468)
# Design of record: docs/architecture/2026-10-28-prepush-touched-readers-468-design.md as amended by ...-468-delta.md (the reader scan is dropped:
# 232 of 232 checks read dynamically [M]). A new arm of the DEFAULT run, `touched-readers`: it fills a 300 s budget with the CI-derived checks,
# those with a RED HISTORY first, then the rest by measured time, and prints what did not run as a pasteable CI-ONLY block with each check's red
# cost. `--plan` prints the same selection and executes nothing. It adds NO capability: it only runs derived argv, through
# run_inv (the scrub, the dash shim, the ceiling). Everything below is its own section; run_timed, the orphan code and the heavy arms are untouched.
#   Fail-closed: no --derive output, an unreadable listing or a refused state dir makes the ARM UNVERIFIED. A check over its limit (max(120 s, 1.5 x its
#   measured time)) is LISTED CI-GRADED, never a FAIL. The red history LEARNS: `--refresh-times` ingests the recent failed CI steps (gh, read-only).
#   THE TIME TABLE: $HOME/.local/state/sparkwright/prepush/<root-commit>/times.tsv, a cache and never evidence, six tab fields:
#   basename · argv · seconds · reds · source (local|ci|red) · epoch. A `red` row carries a failed-step count and the last-red epoch (counted for 30 days).
#   `@job` rows (name · wall s · timeout-minutes) and one `@green` row (job-seconds of the last green PR run) ride in the same columns.
#   A local row beats a CI row beats a built-in SEED row for the time; the red count is the max over all sources.
#   Children run with TMPDIR=$WORK, so everything the run loop reads AFTER its first child (the order, the table, the lists) lives in shell variables.
TR_BUDGET_DEFAULT=300
TR_CEIL_MIN=120
TR_UNKNOWN_S=30
TR_RED_S=2592000
# SWAS-840 (errata C1 of the local-parity design): a higher, printed cap on the arm. TR_CAP is a plain assignment (no environment or argv name; a selftest scales it in a lane COPY). The arm's effective
# cap (TR_CAPE) is max(TR_CAP, the fill budget), so a raised fill is never clipped. A NAMED reader (a derived check whose own script text, comment-stripped, names a listed path literally) starts
# regardless of the fill and of its measured time while its prediction fits the cap left; every unit is charged against the cap with the measured wall, and no unit starts past it.
TR_CAP=600
TR_TIMES=""; TR_BUDGET=300; TR_CAPE=600; TR_TAB=""; TR_ORD=""; TR_HV=""; TR_CX=""; TR_CXJ=""; TR_TJ=""; TR_CIL=""
TS_T=0; TR_RUNN=0; TR_USED=0; TR_CIN=0
L_SEC=""; L_RED=0; L_SRC=""
PLAN=0
NL='
'

# shellcheck disable=SC2016  # the awk program is DATA: nothing in it may expand in the shell.
TRTAB='
BEGIN { OFS = "\t" }
FILENAME == SEEDF { k = $1 SUBSEP $2; keys[k] = 1; kb[k] = $1; ka[k] = $2; ssec[k] = $3; sred[k] = $4; next }
$1 ~ /^@/ { if ($1 == "@reader-k" && NOW - $6 > REDS) next; mk = $1 SUBSEP $2; mrow[mk] = $3 OFS $4 OFS $5; mb[mk] = $1; mn[mk] = $2; next }
{ k = $1 SUBSEP $2; keys[k] = 1; kb[k] = $1; ka[k] = $2
  if ($5 == "local") { if (!(k in lsec) || $3 + 0 > lsec[k]) lsec[k] = $3 + 0; if ($4 + 0 > lred[k]) lred[k] = $4 + 0 }
  else if ($5 == "ci") { csec[k] = $3 + 0; cred[k] = $4 + 0 }
  else if ($5 == "red") { if (NOW - $6 <= REDS && $4 + 0 > rrd[k]) rrd[k] = $4 + 0 } }
END {
  for (k in keys) {
    if (k in lsec) { sec = lsec[k]; src = "local" }
    else if (k in csec) { sec = csec[k]; src = "ci" }
    else if (k in ssec) { sec = ssec[k]; src = "seed" }
    else { sec = ""; src = "red" }
    red = 0; if ((k in cred) && cred[k] > red) red = cred[k]; if ((k in sred) && sred[k] + 0 > red) red = sred[k] + 0; if ((k in lred) && lred[k] > red) red = lred[k]; if ((k in rrd) && rrd[k] > red) red = rrd[k]
    print kb[k], ka[k], (sec == "" ? "" : int(sec)), red, src }
  for (mk in mrow) print mb[mk], mn[mk], mrow[mk] }
'
# shellcheck disable=SC2016
TRNAMES='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function unq(s) { gsub(/^["\047]|["\047]$/, "", s); return s }
function ind(s) { match(s, /[^ ]/); return RSTART - 1 }
/^jobs:/ { injobs = 1; next }
!injobs { next }
{ i = ind($0); t = trim($0) }
inb && (t == "" || i > rind) { if (t != "") print "S\t" NR "\t" cur; next }
{ inb = 0 }
i == 2 && t ~ /^[A-Za-z0-9_-]+:$/ { job = substr(t, 1, length(t) - 1); jd[job] = job; next }
i == 4 && t ~ /^name:/ { v = trim(substr(t, 6)); jd[job] = unq(v); next }
i == 4 && t ~ /^timeout-minutes:/ { jt[job] = trim(substr(t, 17)) + 0; next }
t ~ /^-( |$)/ { cur = ""; sind = i + 2 }
{ u = t; sub(/^- /, "", u) }
u ~ /^name:/ && (t ~ /^- / ? i + 2 : i) == sind { cur = unq(trim(substr(u, 6))) }
u ~ /^run:/ { print "S\t" NR "\t" cur; if (trim(substr(u, 5)) ~ /^[|>][-+]?$/) { inb = 1; rind = (t ~ /^- / ? i + 2 : i) } }
END { for (j in jd) print "J\t" j "\t" jd[j] "\t" jt[j] + 0 }
'
# the built-in SEED rows: a first cut from the design's measured table (basename, argv, seconds, reds30). A local or CI row replaces them.
tr_seed() {
  printf 'agent-autonomy\t--selftest\t129\t2\n'
  printf 'prepush-lane\t--census\t21\t2\n'
  printf 'citation-live\t\t10\t0\n'
  printf 'conformance-mass-budget\t\t48\t0\n'
}

# ---- the time table --------------------------------------------------------------------------------
tr_refuse() { note "times: refused — $1"; unv "touched-readers: the state dir is refused ($1)"; return 1; }
# tr_state — sets TR_TIMES (a path, or empty = no persisted table); rc 1 = the state dir was refused (UNV set). The --warranted cache's leaf rules.
tr_state() {
  TR_TIMES=""
  if [ "${PREPUSH_NO_CACHE-}" = 1 ]; then note "times: no persisted table (PREPUSH_NO_CACHE=1); seed rows only"; return 0; fi
  case ${HOME-} in /?*) ;; *) tr_refuse "HOME is unset or not absolute"; return 1 ;; esac
  _r0=$(git rev-list --max-parents=0 HEAD 2>/dev/null | sed -n 1p)
  case $_r0 in ''|*[!0-9a-f]*) tr_refuse "no root commit"; return 1 ;; esac
  _sd=$HOME/.local/state/sparkwright/prepush/$_r0
  if [ ! -e "$_sd" ] && [ ! -L "$_sd" ]; then ( umask 077; mkdir -p "$_sd" ) 2>/dev/null || { tr_refuse "the state dir cannot be created"; return 1; }; fi
  _ls=$(ls -ld "$_sd" 2>/dev/null) || { tr_refuse "the state dir cannot be inspected"; return 1; }
  case ${_ls%% *} in d????[!w]??[!w]*) ;; *) tr_refuse "the state dir is not a plain directory, or is group/world-writable"; return 1 ;; esac
  _own=$(ls -ldn "$_sd" 2>/dev/null | LC_ALL=C awk '{ print $3 }'); _me=$(id -u 2>/dev/null) || _me=""
  if [ -z "$_me" ] || [ "$_own" != "$_me" ]; then tr_refuse "the state dir is not owned by the current user"; return 1; fi
  if [ ! -r "$_sd" ] || [ ! -w "$_sd" ] || [ ! -x "$_sd" ]; then tr_refuse "the state dir is unreadable"; return 1; fi
  if [ -e "$_sd/times.tsv" ] || [ -L "$_sd/times.tsv" ]; then
    if [ ! -f "$_sd/times.tsv" ] || [ -L "$_sd/times.tsv" ] || [ ! -r "$_sd/times.tsv" ]; then tr_refuse "times.tsv is not a readable regular file"; return 1; fi
  fi
  TR_TIMES=$_sd/times.tsv
  note "times: state $_sd (a cache, never evidence)"
}
# tr_times_init — merge the seed rows with the persisted table into $WORK/tr.tab: basename argv seconds reds30 source stale.
tr_times_init() {
  tr_state || return 1
  tr_seed > "$WORK/tr.seed"
  _tf=/dev/null; if [ -n "$TR_TIMES" ] && [ -f "$TR_TIMES" ]; then _tf=$TR_TIMES; fi
  TR_TAB=$(LC_ALL=C awk -F'\t' -v SEEDF="$WORK/tr.seed" -v NOW="$(date +%s)" -v REDS="$TR_RED_S" "$TRTAB" "$WORK/tr.seed" "$_tf" 2>/dev/null) ||
    { unv "touched-readers: the time table cannot be read"; return 1; }
}
# tr_look <basename> <argv> — sets L_SEC (empty = unknown) L_RED L_SRC from the merged table (a variable, see the section header).
tr_look() {
  _lk=$(B=$1 A=$2 LC_ALL=C awk -F'\t' '$1 == ENVIRON["B"] && $2 == ENVIRON["A"] { print $3 "\t" $4 "\t" $5; exit }' <<EOF
$TR_TAB
EOF
  ) || _lk=""
  L_SEC=""; L_RED=0; L_SRC=""
  [ -n "$_lk" ] || return 0
  L_SEC=$(fld 1 "$_lk"); L_RED=$(fld 2 "$_lk"); L_SRC=$(fld 3 "$_lk")
  case $L_SEC in ''|*[!0-9]*) L_SEC="" ;; esac
  case $L_RED in ''|*[!0-9]*) L_RED=0 ;; esac
}
# tr_record <basename> <argv> <seconds> — append a local row, keep the last 3 local rows per check (the max of them is the time used).
tr_record() {
  [ -n "$TR_TIMES" ] || return 0
  _rt=$(mktemp "$TR_TIMES.XXXXXX") || return 0
  { if [ -f "$TR_TIMES" ]; then cat "$TR_TIMES"; fi; printf '%s\t%s\t%s\t0\tlocal\t%s\n' "$1" "$2" "$3" "$(date +%s)"; } |
    LC_ALL=C awk -F'\t' '{ row[NR] = $0; k = $1 SUBSEP $2; if ($5 == "local") tot[k]++ }
      END { for (r = 1; r <= NR; r++) { split(row[r], f, "\t"); k = f[1] SUBSEP f[2]
              if (f[5] == "local") { idx[k]++; if (tot[k] - idx[k] >= 3) continue }
              print row[r] } }' > "$_rt" 2>/dev/null
  if [ -s "$_rt" ] && mv -f "$_rt" "$TR_TIMES" 2>/dev/null; then :; else rm -f "$_rt" 2>/dev/null; fi
  return 0
}
# tr_rewrite <tag> <key> <blob|-> — SWAS-868: replace (blob) or remove (`-`) the ONE local row for a tag and key; every other row is kept (mktemp + mv, as tr_record). The @pool-k lifecycle needs it: tr_record only appends.
tr_rewrite() {
  [ -n "$TR_TIMES" ] || return 0
  _rw=$(mktemp "$TR_TIMES.XXXXXX") || return 0
  if ! { if [ -f "$TR_TIMES" ]; then cat "$TR_TIMES"; fi; } | T=$1 K=$2 LC_ALL=C awk -F'\t' '!($1 == ENVIRON["T"] && $2 == ENVIRON["K"])' > "$_rw" 2>/dev/null; then rm -f "$_rw" 2>/dev/null; return 0; fi
  [ "$3" = - ] || printf '%s\t%s\t%s\t0\tlocal\t%s\n' "$1" "$2" "$3" "$(date +%s)" >> "$_rw"
  if mv -f "$_rw" "$TR_TIMES" 2>/dev/null; then :; else rm -f "$_rw" 2>/dev/null; fi
  return 0
}
# tr_pk_blob <key> — the blob of the @pool-k row for a key, from the merged table; a value that is not 40 or 64 hex digits (the blob sits in the seconds field, which tr_look would drop as a non-number) reads as no row.
tr_pk_blob() {
  _pk=$(K=$1 LC_ALL=C awk -F'\t' '$1 == "@pool-k" && $2 == ENVIRON["K"] { print $3; exit }' <<EOF
$TR_TAB
EOF
  ) || _pk=""
  case $_pk in
    *[!0-9a-f]*) _pk="" ;;
  esac
  case ${#_pk} in 40|64) ;; *) _pk="" ;; esac
  printf '%s' "$_pk"
}
# tr_cost <job> — the red cost, from the table: the job's measured wall until it reds and the job-minutes of the last green full PR run.
tr_cost() {
  _cs=""; tr_look @job "$1"; _jw=$L_SEC; tr_look @green all; _gs=$L_SEC
  [ -z "$_jw" ] || _cs="~$(( (_jw + 30) / 60 )) min to red"
  [ -z "$_gs" ] || _cs="${_cs:+$_cs · }~$(( (_gs + 30) / 60 )) job-min per red"
  if [ -z "$_cs" ]; then printf 'cost unmeasured'; else printf '%s [M]' "$_cs"; fi
}
tr_ci() {   # tr_ci <label> <job> <why> — one CI-GRADED line for the paste block
  TR_CIL="$TR_CIL$(printf 'CI-GRADED: %s (%s · %s)' "$1" "$3" "$(tr_cost "$2")")$NL"; TR_CIN=$((TR_CIN+1))
}

# ---- selection, order, run -------------------------------------------------------------------------
# tr_select <listing> — walk $WORK/derive.out: the runnable candidates become TR_ORD (11 tab fields: tier · key · label · basename · argv · job ·
# seconds · reds · source · named-reader flag · floor flag, sorted), the heavy ones TR_HV, one row per context job TR_CX, every candidate's job TR_TJ. All variables: see the section header.
tr_select() {
  _sl=$1; _rec=""; TR_HV=""; TR_CX=""; TR_CXJ=""; TR_TJ=""; _seen=$NL
  TS_T=0
  # the literal names a NAMED reader may mention (SWAS-840): each listed path, and the basename of a listed conformance/ or scripts/ path. Kept in a shell VARIABLE and matched through the
  # environment (the st_named idiom): nothing read after the first child lives in $WORK. DISCLOSED ceilings of the rule: a name reached through a variable is not found, and a name that sits
  # after a `#` inside an expansion or a string (`${x#…}`, "a # b") is comment-stripped and under-matches; CI grades both.
  _pat=""
  while IFS= read -r _tp; do
    [ -n "$_tp" ] || continue
    _pat="$_pat$_tp$NL"
    case $_tp in conformance/*|scripts/*) _pat="$_pat${_tp##*/}$NL" ;; esac
  done < "$_sl"
  while IFS= read -r _l <&8; do
    case $_l in '#'*|'') continue ;; esac
    _bk=${_l%%"$TAB"*}; _job=$(fld 2 "$_l")
    if [ "$_bk" = context ]; then
      case $TR_CXJ in *"$NL$_job$NL"*) ;; *) TR_CXJ="$TR_CXJ$NL$_job$NL"; TR_CX="$TR_CX$_job$TAB$(fld 3 "$_l")$TAB$(fld 5 "$_l")$NL" ;; esac
      TR_TJ="$TR_TJ$_job$NL"
      continue
    fi
    _b=$(fld 4 "$_l"); _a=$(fld 5 "$_l"); _lab="$_b${_a:+ $_a}"
    case $_seen in *"$NL$_lab$NL"*) continue ;; esac
    _seen="$_seen$_lab$NL"
    tr_look "$_b" "$_a"
    # a named reader killed at the cap leaves a floor (`@reader-k`, clamped to the cap, dropped by tr_times_init after 30 days): when it is above the time on record the next run predicts from it
    # and prints it as a floor (>=N s)
    _fl=0; _xs=$L_SEC; _xr=$L_RED; _xo=$L_SRC; tr_look @reader-k "$_lab"
    if [ -n "$L_SEC" ] && { [ -z "$_xs" ] || [ "$L_SEC" -gt "$_xs" ]; }; then _xs=$L_SEC; _fl=1; _xo=local; fi
    L_SEC=$_xs; L_RED=$_xr; L_SRC=$_xo
    # a basename-wide heavy twin row prices the bare battery, not this invocation: an EXACT-invocation time row within the budget lifts it (S7, design 3a)
    _hv=0; if [ "$_bk" = heavy ]; then _hv=1; elif is_heavy_row "$_b" && { [ -z "$L_SEC" ] || [ "$L_SEC" -gt "$TR_BUDGET" ]; }; then _hv=1; fi
    if [ "$_hv" -eq 1 ]; then TR_HV="$TR_HV$_lab$TAB$_job$NL"; continue; fi
    if [ "$_bk" = selftest ] && grep -qxF -e "conformance/$_b.sh" "$_sl"; then continue; fi
    if [ "$_b" = prepush-lane ] && [ "$_a" = --selftest ]; then tr_ci "$_lab" "$_job" "the lane's own selftest is long; it runs here when the lane is touched"; continue; fi
    [ -s "$_sl" ] || continue     # nothing listed: nothing to push, nothing to run
    TR_TJ="$TR_TJ$_job$NL"
    _nm=0
    if [ -f "conformance/$_b.sh" ] && sed 's/#.*//' "conformance/$_b.sh" | PAT=$_pat LC_ALL=C awk 'BEGIN { n = split(ENVIRON["PAT"], p, "\n") } { for (i = 1; i <= n; i++) if (p[i] != "" && index($0, p[i])) { f = 1; exit } } END { exit !f }'; then _nm=1; fi   # TRNAMED
    if [ "$L_RED" -ge 1 ]; then _tier=1; _key=$((100000 - L_RED))
    else _tier=2; _key=${L_SEC:-$TR_UNKNOWN_S}; fi
    TS_T=$((TS_T+1))
    _rec="$_rec$_tier$TAB$_key$TAB$_lab$TAB$_b$TAB$_a$TAB$_job$TAB$L_SEC$TAB$L_RED$TAB$L_SRC$TAB$_nm$TAB$_fl$NL"
  done 8< "$WORK/derive.out"
  TR_ORD=$(printf '%s' "$_rec" | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2n -k3,3)
}
# tr_srcw <source> — the source of a time, in the words the over-cap line prints: measured (local, CI or a red row), seed or unmeasured.
tr_srcw() { case ${1-} in local|ci|red) printf measured ;; seed) printf seed ;; *) printf unmeasured ;; esac; }
# tr_exec — walk the order under the budget. A tier-1 (red history) check starts whatever its recorded time says (a forged row cannot push it out);
# any other starts only if its prediction fits what is left. The budget is charged with MEASURED wall, never with predictions.
# SWAS-840: every NAMED reader (field 10; not a red-history one, which keeps the tier-1 rule) takes the CAP path, never the fill: it starts while its prediction fits the cap left, its ceiling is cut to the
# cap left, and it is charged against the cap and not the fill, so it only ADDS units. Named readers keep their tier-2 ORDER (there is no tier ahead of red history). Tier 1 is exempt from the
# cap's prediction test (a forged time row must not push a red check out) and is cut only by its ceiling. Every unit is charged against the cap with the measured wall, no unit starts past it
# (or with a 0 s ceiling), and a unit's ceiling is cut to the cap left: the arm never runs past the cap.
# P2 WARNING: a longest-first reorder or a pool must not let named readers drain the cap ahead of the fill units; charge them in a separate pass or keep the named share bounded.
# A named reader killed at its ceiling leaves a floor (`@reader-k`: ceiling + 1 s, clamped to the cap + 1 s so a reader killed at the full cap is listed over it next time, expiring after 30 days), so the next run predicts from it and lists it over the cap as `measured >=N s`.
tr_exec() {
  _rem=$TR_BUDGET; _caprem=$TR_CAPE; _lk=0; _ordl=$TR_ORD     # popped line by line from a VARIABLE: no descriptor or file a child could reach
  while [ -n "$_ordl" ]; do
    _l=${_ordl%%"$NL"*}
    case $_ordl in *"$NL"*) _ordl=${_ordl#*"$NL"} ;; *) _ordl="" ;; esac
    _tier=$(fld 1 "$_l"); _lab=$(fld 3 "$_l"); _b=$(fld 4 "$_l"); _a=$(fld 5 "$_l"); _job=$(fld 6 "$_l")
    _sec=$(fld 7 "$_l"); _src=$(fld 9 "$_l"); _nm=$(fld 10 "$_l"); _fl=$(fld 11 "$_l")
    _pf=""; _pw=""; if [ "$_fl" = 1 ]; then _pf='>='; _pw="; a kill left this floor: re-run with PREPUSH_NO_CACHE=1 for one run, or delete the @reader-k row for it in times.tsv"; fi
    case $_tier in 1) _tn=red-history ;; *) _tn=measured ;; esac
    if [ "$_tier" != 1 ] && [ "$_nm" = 1 ]; then _tn='named reader'; fi   # TRTAG
    _pred=${_sec:-$TR_UNKNOWN_S}
    _go=0; _ncf=0
    if [ "$_tier" = 1 ]; then _go=0; [ "$_rem" -le 0 ] || _go=1
    else [ "$_rem" -le 0 ] || [ "$_pred" -gt "$_rem" ] || _go=1; fi
    if [ "$_nm" = 1 ] && [ "$_tier" != 1 ]; then   # TRNAMEGO
      if [ "$_caprem" -gt 0 ] && [ "$_pred" -le "$_caprem" ]; then _go=1; _ncf=1   # TRCAP
      else tr_ci "$_lab" "$_job" "over the ${TR_CAPE} s readers cap: measured ${_pf}${_pred} s, ${_caprem} s left [$(tr_srcw "$_src")]$_pw"; continue; fi
    fi
    if [ "$_go" -eq 0 ]; then tr_ci "$_lab" "$_job" "budget spent: predicted ${_pred} s [${_src:-unknown}]"; continue; fi
    if [ "$_ncf" -eq 0 ] && { [ "$_caprem" -le 0 ] || { [ "$_tier" != 1 ] && [ "$_pred" -gt "$_caprem" ]; }; }; then
      tr_ci "$_lab" "$_job" "over the ${TR_CAPE} s readers cap: measured ${_pf}${_pred} s, ${_caprem} s left [$(tr_srcw "$_src")]$_pw"; continue
    fi
    _cl=$TR_CEIL_MIN
    if [ -n "$_sec" ] && [ $((_sec * 3 / 2)) -gt "$_cl" ]; then _cl=$((_sec * 3 / 2)); fi
    _lim=$_rem; if [ "$_ncf" -eq 1 ] || [ "$_caprem" -lt "$_lim" ]; then _lim=$_caprem; fi
    _cap=0; if [ "$_cl" -gt "$_lim" ]; then _cl=$_lim; _cap=1; fi
    if [ "$PLAN" -eq 1 ]; then
      _cut=""; if [ "$_ncf" -eq 0 ] && [ "$_rem" -lt "$_pred" ]; then _cut=" CUT: only ${_rem} s of the budget is left"; fi
      printf '  PLAN  %-18s %-46s ~%4ss  [%s]%s%s\n' touched-readers "$_lab" "$_pred" "$_tn" "" "$_cut"
      TR_RUNN=$((TR_RUNN+1)); TR_USED=$((TR_USED + _pred))
      if [ "$_ncf" -eq 0 ]; then _rem=$((_rem - _pred)); if [ "$_rem" -lt 0 ]; then _rem=0; fi; fi
      _caprem=$((_caprem - _pred)); if [ "$_caprem" -lt 0 ]; then _caprem=0; fi
      continue
    fi
    if [ "$_lk" -eq 0 ]; then
      hl_need touched-readers || { RAN=$((RAN+1)); printf '  UNVERIFIED  %-12s %s\n' touched-readers "the heavy-arm lock is not held: the touched readers are not run"; rl_u touched-readers lock UNV; return 0; }
      _lk=1
    fi
    _oi=$IFS; set -f; IFS=' '
    # shellcheck disable=SC2086  # deliberate: the closed-charset argv becomes ARGV, never eval'd.
    set -- $_a
    IFS=$_oi; set +f
    run_inv "$_cl" sh "conformance/$_b.sh" "$@"
    if [ "$_ncf" -eq 0 ]; then _rem=$((_rem - RUN_S)); if [ "$_rem" -lt 0 ]; then _rem=0; fi; fi
    _caprem=$((_caprem - RUN_S)); if [ "$_caprem" -lt 0 ]; then _caprem=0; fi
    TR_USED=$((TR_USED + RUN_S)); TR_RUNN=$((TR_RUNN+1))
    case $RUN_RC in
      0) _tr_c=0; crash_ev_run || _tr_c=$?
         if [ "$_tr_c" -ne 1 ]; then report_inv touched-readers "$_lab" 0 "$_cl"   # SWAS-600: a crash-demoted reader reads UNVERIFIED, takes no OK row and seeds no time
         else RAN=$((RAN+1)); printf '  OK    %-18s %-46s %4ss  [%s]\n' touched-readers "$_lab" "$RUN_S" "$_tn"; rl_u touched-readers "$_b" OK run; tr_record "$_b" "$_a" "$RUN_S"; fi ;;
      124|137|143)
        if [ "$_cap" -eq 1 ] && [ "$_ncf" -eq 0 ] && [ "$RUN_S" -ge "$_cl" ]; then tr_ci "$_lab" "$_job" "budget spent: only ${_cl} s of the budget was left (killed at ${RUN_S} s)"   # TRBS
        elif [ "$RUN_S" -ge "$_cl" ]; then tr_ci "$_lab" "$_job" "local ceiling hit at ${RUN_S} s${ARM_CEIL_TXT:+; $ARM_CEIL_TXT}"; [ "$_ncf" -eq 0 ] || { _fv=$((_cl + 1)); [ "$_fv" -le $((TR_CAPE + 1)) ] || _fv=$((TR_CAPE + 1)); tr_record @reader-k "$_lab" "$_fv"; }   # TRREC
        else report_inv touched-readers "$_lab" 0 "$_cl"; fi ;;
      *) report_inv touched-readers "$_lab" 0 "$_cl" ;;
    esac
  done
}
# tr_list_rest — the heavy-bucket candidates and the context mentions are always listed (never run here); a context row is one per job (L2).
tr_list_rest() {
  while IFS= read -r _hv; do [ -z "$_hv" ] || tr_ci "$(fld 1 "$_hv")" "$(fld 2 "$_hv")" "heavy bucket: CI job placement, never run in the default"; done <<EOF
$TR_HV
EOF
  while IFS= read -r _cx; do
    [ -z "$_cx" ] || tr_ci "$(fld 1 "$_cx") — context step" "$(fld 1 "$_cx")" "context at line $(fld 2 "$_cx"): $(fld 3 "$_cx") — not runnable here"
  done <<EOF
$TR_CX
EOF
}
# tr_timeout_risk — TIMEOUT-RISK for a touched job whose last measured wall is at least 80% of its timeout-minutes (L2). Run in $( ), prints only.
tr_timeout_risk() {
  printf '%s' "$TR_TJ" | LC_ALL=C sort -u | while IFS= read -r _j; do
    tr_look @job "$_j"
    [ -n "$L_SEC" ] && [ "$L_RED" -gt 0 ] || continue
    if [ $((L_SEC * 100)) -ge $((L_RED * 60 * 80)) ]; then
      printf 'TIMEOUT-RISK: %s — last wall %s of %s min [M, %s]\n' "$_j" "$(LC_ALL=C awk -v s="$L_SEC" 'BEGIN { printf "%.1f", s / 60 }')" "$L_RED" "${L_SRC:-table}"
    fi
  done
}
# tr_arm <ci-file> — the arm. rc 0 always; a failing check sets FAILS, a refused precondition sets UNV.
tr_arm() {
  if [ "$PLAN" -eq 0 ] && { [ "$WARRANTED" -eq 1 ] || [ -n "$HEAVY" ]; }; then
    note "touched-readers: not run beside --warranted or a heavy arm (they run the core-live checks themselves)"; return 0
  fi
  [ -z "$UNV" ] || { note "touched-readers: not run — the run is already UNVERIFIED"; return 0; }
  if ! grep -q '^# ci-file:' "$WORK/derive.out" 2>/dev/null || [ ! -f "$WORK/listing" ]; then
    note "touched-readers: UNVERIFIED — no --derive output, or no readable listing"
    unv "touched-readers: no --derive output, or an unreadable listing"; return 0
  fi
  tr_times_init || return 0
  TR_BUDGET=$(raise_only "${PREPUSH_READERS_BUDGET_S-}" "$TR_BUDGET_DEFAULT" PREPUSH_READERS_BUDGET_S)
  TR_CAPE=$TR_CAP; [ "$TR_BUDGET" -le "$TR_CAPE" ] || TR_CAPE=$TR_BUDGET   # the cap is never below the fill: a raised fill is not clipped
  TR_CIL=""; TR_RUNN=0; TR_USED=0; TR_CIN=0
  tr_select "$WORK/listing"
  note "touched-readers: $TS_T candidate(s), red history first, then by measured time · budget ${TR_BUDGET}s (the fill) · cap ${TR_CAPE}s [printed]$([ "$PLAN" -eq 0 ] || printf ' · PLAN, nothing is executed')"
  tr_exec
  tr_list_rest
  _trl=$(tr_timeout_risk)
  if [ "$PLAN" -eq 1 ]; then note "touched-readers: $TR_RUNN would run (~${TR_USED}s predicted) · $TR_CIN CI-graded"
  else note "touched-readers: $TR_RUNN run (${TR_USED} s [M local]) · $TR_CIN CI-graded"; fi
  if [ -n "$TR_CIL" ] || [ -n "$_trl" ]; then printf 'CI-ONLY (paste into the PR):\n%s' "$TR_CIL"; [ -z "$_trl" ] || printf '%s\n' "$_trl"
  else printf 'CI-ONLY: none — %s derived check(s) ran above\n' "$TR_RUNN"; fi
  return 0
}
# tr_refresh <ci-file> — `--refresh-times`: pull CI step walls, job walls (+ timeout-minutes), the last green PR run's job-seconds and, so the red history
# LEARNS, the recent FAILED runs' failed steps (gh, read-only, gh's own auth) into the CI and red rows of the time table. A failed step maps to its
# invocation by step NAME against the working-tree ci.yml; a red row holds the failure count and the last-red epoch (counted for 30 days).
tr_refresh() {
  command -v gh >/dev/null 2>&1 || { note "times: gh not found — local rows only"; return 0; }
  tr_state || return 1
  [ -n "$TR_TIMES" ] || { note "times: no persisted table (PREPUSH_NO_CACHE=1) — nothing to refresh"; return 0; }
  _rel=$(ci_path "$1") || exit $?; ci_exists_or_die "$_rel"
  WORK=${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/prepush-XXXXXX")}
  derive "$_rel" > "$WORK/derive.out" || { sed -n '/^#/p' "$WORK/derive.out"; return 1; }
  LC_ALL=C awk "$TRNAMES" "$ROOT/$_rel" > "$WORK/tr.names" 2>/dev/null || { note "times: ci.yml step names cannot be read"; return 1; }
  _jq_steps='.jobs[] | .name as $j | .steps[] | select(.started_at != null and .completed_at != null) | [$j, .name, ((.completed_at|fromdate) - (.started_at|fromdate))] | @tsv'
  _jq_jobs='.jobs[] | select(.started_at != null and .completed_at != null) | [.name, ((.completed_at|fromdate) - (.started_at|fromdate))] | @tsv'
  _jq_fail='.jobs[] | .steps[] | select(.conclusion == "failure") | .name'
  # only THIS repo's own runs count: a push to main, or a pull_request whose head repo is this repo (a fork PR's step names must not add red rows)
  _own='(.event == "push" and .head_branch == "main") or (.event == "pull_request" and .head_repository.full_name == .repository.full_name)'
  _runs='repos/{owner}/{repo}/actions/workflows/ci.yml/runs'
  _now=$(date +%s); _gf=0
  _d30=$(date -u -r "$((_now - TR_RED_S))" +%Y-%m-%d 2>/dev/null || date -u -d "@$((_now - TR_RED_S))" +%Y-%m-%d 2>/dev/null) || _d30=""
  _push=$(gh api "$_runs?status=success&event=push&branch=main&per_page=1" --jq '.workflow_runs[0].id' 2>/dev/null) || _gf=1
  _prr=$(gh api "$_runs?status=success&event=pull_request&per_page=30" --jq "[.workflow_runs[] | select($_own)][0].id" 2>/dev/null) || _gf=1
  case $_push$_prr$_d30 in *null*) _gf=1 ;; esac
  [ -n "$_push" ] && [ -n "$_prr" ] && [ -n "$_d30" ] || _gf=1
  gh api "$_runs?status=failure&created=%3E%3D$_d30&per_page=100" --paginate --jq ".workflow_runs[] | select($_own) | [.id, (.created_at|fromdate)] | @tsv" > "$WORK/tr.gh.bad" 2>/dev/null || _gf=1
  gh api "repos/{owner}/{repo}/actions/runs/$_push/jobs" --paginate --jq "$_jq_steps" > "$WORK/tr.gh.steps" 2>/dev/null || _gf=1
  gh api "repos/{owner}/{repo}/actions/runs/$_push/jobs" --paginate --jq "$_jq_jobs" > "$WORK/tr.gh.jobs" 2>/dev/null || _gf=1
  gh api "repos/{owner}/{repo}/actions/runs/$_prr/jobs" --paginate --jq "$_jq_jobs" > "$WORK/tr.gh.green" 2>/dev/null || _gf=1
  [ -s "$WORK/tr.gh.steps" ] && [ -s "$WORK/tr.gh.jobs" ] && [ -s "$WORK/tr.gh.green" ] || _gf=1
  : > "$WORK/tr.gh.fail"
  while IFS="$TAB" read -r _bid _bts <&7; do
    gh api "repos/{owner}/{repo}/actions/runs/$_bid/jobs" --paginate --jq "$_jq_fail" > "$WORK/tr.gh.one" 2>/dev/null || _gf=1
    while IFS= read -r _bn; do printf '%s\t%s\n' "$_bn" "$_bts"; done < "$WORK/tr.gh.one" >> "$WORK/tr.gh.fail"
  done 7< "$WORK/tr.gh.bad"
  # M1: any gh failure or empty/null answer KEEPS the old CI and red rows (a failure must not wipe the red history) and is rc 1
  [ "$_gf" -eq 0 ] || { note "times: gh failed or returned nothing — the old CI and red rows are KEPT, not refreshed"; return 1; }
  _derive=$WORK/derive.out
  {
    LC_ALL=C awk -F'\t' -v NOW="$_now" -v NAMES="$WORK/tr.names" -v STEPS="$WORK/tr.gh.steps" -v JOBS="$WORK/tr.gh.jobs" -v GREEN="$WORK/tr.gh.green" -v FAIL="$WORK/tr.gh.fail" -v UNM="$WORK/tr.unm" '
      BEGIN { OFS = "\t"
        while ((getline l < NAMES) > 0) { split(l, f, "\t"); if (f[1] == "S") sname[f[2]] = f[3]; else if (f[1] == "J") { jdisp[f[2]] = f[3]; jto[f[2]] = f[4] } }
        while ((getline l < STEPS) > 0) { split(l, f, "\t"); if (!(f[2] in ssec) || f[3] + 0 > ssec[f[2]]) ssec[f[2]] = f[3] + 0 }
        while ((getline l < JOBS) > 0) { split(l, f, "\t"); if (!(f[1] in jwall) || f[2] + 0 > jwall[f[1]]) jwall[f[1]] = f[2] + 0 }
        while ((getline l < GREEN) > 0) { split(l, f, "\t"); gsum += f[2] + 0; gseen = 1 }
        while ((getline l < FAIL) > 0) { split(l, f, "\t"); fails[f[1]]++; if (f[2] + 0 > lastred[f[1]]) lastred[f[1]] = f[2] + 0 } }
      $1 == "context" || /^#/ { next }
      { nm = sname[$3]; if (nm == "") next
        mapped[nm] = 1
        if (nm in ssec) print $4, $5, int(ssec[nm]), 0, "ci", NOW
        if (nm in fails) print $4, $5, 0, fails[nm], "red", lastred[nm] }
      END { for (nm in fails) if (!(nm in mapped)) un++
            print un + 0 > UNM
            for (j in jdisp) { w = (jdisp[j] in jwall) ? jwall[jdisp[j]] : ((j in jwall) ? jwall[j] : ""); if (w != "") print "@job", j, int(w), int(jto[j]), "ci", NOW }
            if (gseen) print "@green", "all", int(gsum), 0, "ci", NOW }' "$_derive"
  } > "$WORK/tr.newci"
  _rt=$(mktemp "$TR_TIMES.XXXXXX") || return 1
  { if [ -f "$TR_TIMES" ]; then LC_ALL=C awk -F'\t' '$5 != "ci" && $5 != "red"' "$TR_TIMES"; fi; cat "$WORK/tr.newci"; } > "$_rt"
  if ! mv -f "$_rt" "$TR_TIMES"; then rm -f "$_rt"; return 1; fi
  note "times: refreshed $(grep -c '' < "$WORK/tr.newci" || :) CI row(s) into $TR_TIMES (steps map by NAME against the working-tree ci.yml); $(cat "$WORK/tr.unm" 2>/dev/null || echo '?') failed step name(s) mapped to no invocation"
}

# The recommendation block: which Tier-2 arm THIS listing warrants. Recommend-only, by ruling §4.2 —
# the lane names the arm and the operator runs it (or `--warranted` runs exactly the derived set).
reco() {
  print_warranted
  note "recommendation (exports/slow/the container arm are CI's; never in --warranted, R-C11 condition 6):"
  if [ "$DOCS_ONLY" = true ]; then note "  none — the delta is docs-only (D-240903-3)"; return 0; fi
  _any=0
  if [ -f conformance/ci-classify-changes.sh ] &&
     ! sh conformance/ci-classify-changes.sh --export-ignored-only "$WORK/listing" 2>/dev/null |
       grep -qx 'export_ignored_only=true'; then
    note "  --exports — the delta is not export-ignored-only"; _any=1; fi
  while IFS= read -r _row <&7; do
    [ "$(fld 2 "$_row")" = heavy ] || continue
    if grep -q "^conformance/$(fld 1 "$_row")" "$WORK/listing"; then
      note "  --slow — the listing touches the heavy-row check $(fld 1 "$_row") or its fixtures"; _any=1; fi
  done 7< "$WORK/twins.ok"
  if grep -qE '^(hooks/|\.git|scripts/kit-guard$|scripts/board-claim\.sh$)' "$WORK/listing"; then
    note "  PREPUSH-CONTAINER-ARM (a git-shaped delta) — NAMED, NOT RUN: the container arm is a separate row (design §3.5)"; _any=1; fi
  [ "$_any" -eq 1 ] || note "  none"
}

# ok_verdict — the OK line STATES ITS SCOPE (an agent reading a bare OK as "CI will pass" is the failure this
# prevents): a default run names how many CI-derived core-live checks it did not run; a --warranted run names
# how many arms it took from the cache instead of executing. FAIL/UNVERIFIED lines and an unqualified
# --warranted OK are unchanged. Never `RESULT:`; the caller prints it as the LAST line.
ok_verdict() {
  _tnc=""; [ "$TN" -eq 0 ] || _tnc="$TN board-bound twin(s) NOT ENFORCED locally — CI binds them"   # SWAS-163
  [ "$SELF_NE" -eq 0 ] || _tnc="${_tnc:+$_tnc; }$SELF_NE touched selftest(s) NOT ENFORCED locally — CI binds them: $SELF_NE_LIST"   # SWAS-442
  [ "$RACE_N" -eq 0 ] || _tnc="${_tnc:+$_tnc; }$RACE_N RACE"   # SWAS-868 S-4: a unit that failed in parallel and passed serially is named on the OK line (RACE_N is 0 at J = 1)
  if [ "$WARRANTED" -eq 0 ] && [ "$CORE_N" -gt 0 ]; then
    printf 'PARITY-CORE: OK (own surface — %s CI-derived core-live check(s) not run; --warranted and CI run them%s)\n' "$CORE_N" "${_tnc:+; $_tnc}"
  elif [ "$WARRANTED" -eq 1 ] && [ "$CACHE_SKIPS" -gt 0 ]; then
    printf 'PARITY-CORE: OK (%s arm(s) from cache, not executed this run%s)\n' "$CACHE_SKIPS" "${_tnc:+; $_tnc}"
  elif [ -n "$_tnc" ]; then printf 'PARITY-CORE: OK (%s)\n' "$_tnc"
  else printf 'PARITY-CORE: OK\n'; fi
}

verdict() {
  [ "$VERBOSE" -eq 0 ] || { note "executed argv ($RAN invocation(s), log $ARGVLOG):"
                            sed 's/^/#   /' "$ARGVLOG"; }
  note "work root: $WORK (removed best-effort at exit)"
  # SWAS-784: the git toplevel this run grades (the lane refuses nothing, but the tree it read is now visible)
  _tr=${ROOT:-unknown}; case $_tr in *[[:cntrl:]]*) _tr='<unprintable path>' ;; esac   # a control character in the path would forge a line
  note "tree: $_tr"   # TREELINE
  _rc=0; _vw=OK
  # SWAS-600: the printed order is UNV, then CRASH, then FAILS
  if [ "$CRASH" -gt 0 ]; then   # CRVERD
    _vx=""; [ "$FAILS" -eq 0 ] || _vx="; plus $FAILS failing unit(s)"
    _v="PARITY-CORE: UNVERIFIED (${UNV:+$UNV; plus }$CRASH unit(s) crashed: $CRASH_LIST$_vx)"; _rc=1; _vw=UNVERIFIED
  elif [ -n "$UNV" ]; then _v="PARITY-CORE: UNVERIFIED ($UNV)"; _rc=1; _vw=UNVERIFIED
  elif [ "$FAILS" -gt 0 ]; then _v="PARITY-CORE: FAIL"; _rc=1; _vw=FAIL
  else _v=$(ok_verdict); fi
  printf '%s\n' "$_v"                       # THE LAST LINE, always, and never `RESULT:`
  [ "$BEST" -eq 0 ] || _rc=0                # --best-effort moves the rc, never the verdict line
  rl_end "$_vw" "$_rc"                      # SWAS-568: the end record carries the word and rc just printed and returned
  return "$_rc"
}

# The run, in order: bounds, base, listing, classification, shell, derivation, table, buckets,
# execution, heavy arm, recommendation, verdict. An UNVERIFIED precondition STOPS execution — a lane
# that ran half its core under the wrong shell would be worse than one that says it did not run.
run_lane() {
  _ci=$1
  # M1: a non-default --ci-file / KIT_CI_FILE is NOT parity — CI does not run what it derives. `derive`
  # printed the UNVERIFIED header; the VERDICT owes the same answer, so it is the FIRST unv reason and
  # the lane does NOT run (an UNVERIFIED precondition stops execution, exactly like a missing dash).
  [ "$_ci" = "$CI_DEFAULT" ] || unv "derived from a non-CI file: $_ci"
  work_init; bounds_init; base_check; listing_derive; docs_classify; shim_init
  rl_start "$_ci"   # RLSTART
  derive "$_ci" > "$WORK/derive.out" 2>&1 || { sed -n '/^#/p' "$WORK/derive.out"
                                               unv "unparseable ci.yml"; verdict; return $?; }
  sed -n '/^#/p' "$WORK/derive.out"
  read_twins "$_ci"; twin_exec_check; carved_note
  [ ! -s "$WORK/twins.err" ] || { sed 's/^/# TWIN-TABLE MALFORMED: /' "$WORK/twins.err"
                                  unv "the twin table is malformed — run --census"; }
  split_buckets
  if [ -n "$UNV" ]; then note "NOT RUN: $UNV"; verdict; return $?; fi
  if [ "$PLAN" -eq 1 ]; then          # SWAS-468: the plan prints the touched-readers selection and executes nothing
    tr_arm "$_ci"; printf 'PLAN: nothing was executed\n'; [ -z "$UNV" ] || { note "UNVERIFIED: $UNV"; rl_end PLAN 1; return 1; }; rl_end PLAN 0; return 0
  fi
  run_core; run_board; run_twins; run_heavy; run_warranted; tr_arm "$_ci"; hl_release; reco
  verdict
}

# ------------------------------------------------------------------------------------ entry point
main() {
  # NO ARGUMENT is THE RUN (`sparkwright prepush`); --help is rc 2 — the kit's usage convention,
  # locked live by conformance/sparkwright-verbs.sh ("`prepush --help` exits 2 through the router").
  _mode=""; _ci=${KIT_CI_FILE:-$CI_DEFAULT}; _strict=0; _ci_given=0
  [ -z "${KIT_CI_FILE:-}" ] || _ci_given=1
  while [ $# -gt 0 ]; do
    case $1 in
      --derive|--census|--selftest|--refresh-times|--log-report) [ -z "$_mode" ] || die2 "one mode per invocation"; _mode=$1 ;;
      --plan) PLAN=1 ;;                           # SWAS-468: print the touched-readers selection, execute nothing
      --ci-file) [ $# -ge 2 ] || die2 "--ci-file needs a path"; _ci=$2; _ci_given=1; shift ;;
      --base) [ $# -ge 2 ] || die2 "--base needs a ref"; BASE=$2; shift ;;
      --require) _strict=1 ;;                     # the explicit spelling of the DEFAULT: a no-op
      --best-effort) BEST=1 ;;
      --verbose) VERBOSE=1 ;;
      # exactly ONE heavy arm per invocation (§3.3, security C11) — two is a usage error, not a guess.
      # --warranted is a heavy arm for this purpose too (R-C11 c6): it and any single-arm flag are
      # mutually exclusive, in EITHER order — the SAME die2 shape, checked from both sides below.
      --green-on-clone|--exports|--slow) [ -z "$HEAVY" ] || die2 "one heavy arm per invocation (already: --$HEAVY)"
                                         [ "$WARRANTED" -eq 0 ] || die2 "one heavy arm per invocation (already: --warranted)"
                                         HEAVY=${1#--} ;;
      --non-vacuity) [ -z "$HEAVY" ] || die2 "one heavy arm per invocation (already: --$HEAVY)"
                     [ "$WARRANTED" -eq 0 ] || die2 "one heavy arm per invocation (already: --warranted)"
                     [ $# -ge 2 ] || die2 "--non-vacuity needs a check basename"
                     # a LEADING dash is refused first (reviewer I-3): `-rf` is inside [a-z0-9.-]
                     # but would be forwarded to non-vacuity as a FLAG, not a basename.
                     basename_ok "$2" || die2 "--non-vacuity basename outside [a-z0-9.-]+, and never starting with a dash: $2"
                     HEAVY=non-vacuity; HEAVY_ARG=${2%.sh}.sh; shift ;;
      # --warranted takes NO operand (R-C11 c6) and has NO environment toggle — this flag is the
      # only way to set WARRANTED anywhere in this file.
      --warranted) [ -z "$HEAVY" ] || die2 "one heavy arm per invocation (already: --$HEAVY)"
                   [ "$WARRANTED" -eq 0 ] || die2 "one heavy arm per invocation (already: --warranted)"
                   WARRANTED=1 ;;
      --help|-h) usage; exit 2 ;;
      *) die2 "unknown argument: $1 (never forwarded)" ;;
    esac
    shift
  done
  [ "$_strict" -eq 0 ] || [ "$BEST" -eq 0 ] || die2 "--require and --best-effort are contradictory"
  [ -n "$_mode" ] || _mode=--run
  [ "$PLAN" -eq 0 ] || { [ "$_mode" = --run ] && [ -z "$HEAVY" ] && [ "$WARRANTED" -eq 0 ]; } || die2 "--plan takes no mode and no heavy arm"
  case $_mode in
    --selftest) selftest; exit $? ;;
    --run)      root_or_die; cd "$ROOT"
                [ "$_ci_given" -eq 1 ] || [ -e "$CI_DEFAULT" ] || [ -L "$CI_DEFAULT" ] ||
                  die2 "this tree has no GitHub Actions CI file ($CI_DEFAULT). The pre-push lane derives its checks from GitHub Actions only, so it checks nothing here; run sh conformance/verify.sh before you push."
                _rel=$(resolve_ci "$_ci") || exit $?
                run_lane "$_rel" ;;
    --census)   root_or_die; cd "$ROOT"
                census "$_ci" ;;
    --refresh-times) root_or_die; cd "$ROOT"
                tr_refresh "$_ci" ;;
    --log-report) root_or_die; cd "$ROOT"
                log_report ;;
    # NOTE: resolve_ci runs in a command substitution, so its `exit 2` ends only that SUBSHELL —
    # the rc must be propagated explicitly here or a rejected --ci-file would fall through as rc 1.
    --derive)   root_or_die; cd "$ROOT"
                _rel=$(resolve_ci "$_ci") || exit $?
                derive "$_rel" ;;
  esac
}

# ============================================================================================
# --selftest — every leg BELOW this marker (the non-vacuity sweep mutates only lines ABOVE it).
selftest() {
  SF=0
  LANE=$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")
  KROOT=$(git rev-parse --show-toplevel 2>/dev/null && :) || KROOT=""
  # every fixture repo is born under ONE lane work root (design §3.7), removed by the EXIT trap.
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/prepush-XXXXXX"); export TMPDIR="$WORK"
  # PREPUSH-CORE-DEFAULT cache: NO leg may touch the real $HOME, and the --warranted legs of other
  # concerns must never SKIP off a record another fixture left (fixture root commits can collide within one
  # second). So HOME is a temp dir and the cache is OFF for every leg; the cache_* legs turn it back on
  # explicitly (PREPUSH_NO_CACHE=0) with their own HOME.
  HOME=$WORK/home; mkdir -p "$HOME"; export HOME; PREPUSH_NO_CACHE=1; export PREPUSH_NO_CACHE
  # SWAS-278b fix round (CI #880): a runner's SYSTEM git config (ubuntu ships git-lfs filter.lfs.* in /etc/gitconfig) must never reach a
  # fixture, and neither may its global config (HOME is scrubbed, but a runner exports XDG_CONFIG_HOME, whose git/config git also reads).
  # Both scopes are closed here for every fixture. The one cell that wants a system-like key supplies its own file (GIT_CONFIG_SYSTEM)
  # and unsets NOSYSTEM for that run only.
  GIT_CONFIG_NOSYSTEM=1; GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
  # SWAS-868 (P-7): J is derived from the machine (pool_j), so a leg that runs the lane must not depend on the host. LANE_J1 and LANE_J2 are COPIES of the lane with two function overrides
  # (pool_cores and pool_free_mb, never an environment knob): J is 1 in the first and 2 in the second. LANE is LANE_J1 from here on, so every older leg (rn, rnl, rnh, cr, trmut, lane_mut, k5_run and the
  # lane copies they make) runs at J = 1 and never nests a pool. LANE_REAL is the lane itself, for the legs that read its text; the pool legs pass LANE_J2 (or TRSRC=$LANE_J2) explicitly.
  LANE_REAL=$LANE; LANE_J1=$WORK/lane-j1.sh; LANE_J2=$WORK/lane-j2.sh
  lane_mut "$LANE_J1" '' 'pool_cores() { echo 1; }; pool_free_mb() { echo 99999; }' > /dev/null
  lane_mut "$LANE_J2" '' 'pool_cores() { echo 3; }; pool_free_mb() { echo 99999; }' > /dev/null
  LANE=$LANE_J1
  # THE ROSTER, in order; each name is a leg's function name verbatim (a missing one is a `not found`).
  for _leg in grammar continuation block_scalar disqualifiers env_not_applied doc_level ci_file \
              census_unbucketed census_denominator census_negative twin_stale twin_cishape \
              heavy_rows twin_grammar injection scrub docs_only rename newline newline_charset base \
              ceiling budget \
              floor argv core_selftest local_defer troster tname tbudget heavy_needs_flag dash verdict shim bounded_fanout no_write \
              no_exec_of_context core_live_default shellcheck_scoped secretscan_scoped parselint_scoped twin_not_enforced twin_carve \
              cache_skip_same_tree cache_code_change cache_bookkeeping cache_heavy_bookkeeping \
              cache_dirty_bypass cache_skip_output_never \
              cache_fail_never cache_unusable_dir cache_state_dir_modes cache_opt_out \
              warranted_nonvac_registered warranted_nonvac_unregistered \
              warranted_nonvac_nowordsplit_noglob \
              warranted_charset warranted_goc_scripts warranted_goc_export_ignored \
              warranted_claims warranted_docs_only warranted_exports_never \
              warranted_export_ignored_runs_nothing \
              warranted_claims_exact_match warranted_conflict warranted_operand warranted_serial \
              warranted_fail_continues warranted_busy_hit warranted_busy_own_descendant \
              warranted_busy_ancestor warranted_busy_numeric_ignored \
              warranted_busy_ps_fail warranted_floor_refuses_all warranted_router_dial \
              board_gate_fails board_gate_passes board_gate_skipped board_gate_zero_rows \
              board_gate_derivation_pin board_gate_underived board_gate_refused \
              board_gate_symlink board_gate_literal board_gate_selftest_prefix \
              lock_acquire_release lock_acquire_e2e lock_phase_e2e lock_light_unlocked lock_wait lock_wait_e2e \
              lock_kill9 lock_stale_note lock_budget_end lock_budget_runlevel lock_dir_unsafe lock_floor_reread \
              lock_symlink lock_foreign_owner lock_holder_sanitised lock_home_scoped lock_no_tool lock_race \
              lock_child_fd lock_ancestor_note lock_perl_env lock_flock_shim lock_owner_real lock_holder_symlink \
              cache_producer_skip_line cache_producer_other_tree cache_off_index_tags cache_off_sparse_filter \
              cache_filter_applied lock_kill_zero \
              tripwire_lane tripwire_positive tripwire_scrub_mutant tripwire_conf_exists tripwire_old_argv \
              orphan_ceiling orphan_unconfirmed orphan_trap orphan_leftover orphan_noperl orphan_guard orphan_parent orphan_leader orphan_reuse orphan_perl_env \
              touched_failclosed tr8_gate tr8_gitlab touched_replay touched_budget touched_output touched_refresh \
              preflight_case_variant crash tree \
              runlog_lines runlog_fields runlog_complete runlog_secret runlog_rotate runlog_unsafe runlog_interrupt runlog_rss runlog_brule runlog_report runlog_unread \
              pool_unsettable pool_dirs pool_order pool_race pool_ceiling pool_equal pool_log pool_fd pool_late pool_records pool_pk pool_forge pool_half pool_noperl pool_reap pool_readers pool_report
  do _leg_t0=$(date +%s); "selftest_$_leg"; echo "# leg $_leg $(( $(date +%s) - _leg_t0 ))"; done
  [ "$SF" -eq 0 ] && { echo "prepush-lane --selftest: OK"; return 0; }
  echo "prepush-lane --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: see the marker above) ---------------
sfx() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (want [$2] got [$3])"; SF=1; fi; }
dump() { printf '%s\n' "$DVOUT" | sed 's/^/      /'; }
want() { if printf '%s\n' "$DVOUT" | grep -q "$2"; then echo "PASS: $1"; else echo "FAIL: $1 — no line matching /$2/"; SF=1; dump; fi; }
wantnot() { if printf '%s\n' "$DVOUT" | grep -q "$2"; then echo "FAIL: $1 — matched /$2/"; SF=1; dump; else echo "PASS: $1"; fi; }
ctxcount() { printf '%s\n' "$DVOUT" | grep -c '^context'"$TAB" || :; }
mkrepo() {   # a self-contained fixture repo: the lane resolves ITS root, so KIT_CI_FILE stays honest
  _d=$(mktemp -d "${TMPDIR:-/tmp}/fx-XXXXXX"); mkdir -p "$_d/.github/workflows" "$_d/conformance"
  for _n in alpha beta verify secret-scan-wired; do printf '#!/bin/sh\nexit 0\n' > "$_d/conformance/$_n.sh"; done
  ln -s alpha.sh "$_d/conformance/link.sh"   # the existence oracle must refuse a SYMLINK
  # the kit marker (green-on-clone.sh's own OR-of-markers): --census is KIT-SELF only; --derive is not.
  mkdir -p "$_d/docs"; : > "$_d/docs/ROADMAP-KIT.md"
  ( cd "$_d" && git init -q ); printf '%s\n' "$_d"
}
# tw <basename> <kind> <ci-shape> <local-argv> <expect-rc> <budget-s> <reason> — append a twin row to the CURRENT fixture repo's table (tabs built here, so a leg never embeds one).
tw() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$d/conformance/prepush-twins.tsv"; }
# cs <repo> [args...] -> DVOUT/DVRC for a --census run
cs() { _r=$1; shift; DVOUT=$( cd "$_r" && sh "$LANE" --census "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }
# mkci <<'YAML' … YAML -> $d, a fresh fixture repo whose ci.yml BODY starts at line 2 (`name: fx`).
mkci() { d=$(mkrepo); { printf 'name: fx\n'; cat; } > "$d/.github/workflows/ci.yml"; }
# mkcin <run-text…> — a one-job fixture with ONE STEP PER ARGUMENT, first step at body line 5, so
# every `${TAB}j1${TAB}5${TAB}` assertion reads the same as the equivalent mkci heredoc. mkci1 is the
# one-step case. Shared by the legs that differ only in those lines: a fixture is not an assertion.
mkcin() { d=$(mkrepo); { printf 'name: fx\njobs:\n  j1:\n    steps:\n'
  for _s in "$@"; do printf '      - run: %s\n' "$_s"; done; } > "$d/.github/workflows/ci.yml"; }
mkci1() { mkcin "$1"; }
# jd <job-name> <job-level-key> — APPEND a job carrying one key and one `sh conformance/alpha.sh` step.
jd() { printf '  %s:\n    %s\n    steps:\n      - run: sh conformance/alpha.sh\n' "$1" "$2" >> "$d/.github/workflows/ci.yml"; }
# dv <repo> [args...] -> DVOUT/DVRC
dv() { _r=$1; shift; DVOUT=$( cd "$_r" && sh "$LANE" --derive "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }

selftest_grammar() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: sh conformance/alpha.sh --selftest
      - run: 'sh conformance/beta.sh --dir . profiles/x'
      - run: sh conformance/alpha.sh --head ${{ github.sha }}
      - run: sh conformance/alpha.sh; echo done
      - run: sh conformance/alpha.sh --x `id`
      - run: sh conformance/alpha.sh /etc/passwd
      - run: sh conformance/alpha.sh ~/x
      - run: sh conformance/alpha.sh ../secrets
      - run: sh conformance/Alpha.sh
      - run: sh conformance/sub/alpha.sh
      - run: sh conformance/nosuch.sh
      - run: sh conformance/link.sh
      - run: sh conformance/alpha.sh -rf
      - uses: some/action@v1
        with:
          run: sh conformance/verify.sh
      - run: sh conformance/beta.sh
        with:
          shell: bash
      -
        run: sh conformance/alpha.sh
      - run: sh conformance/beta.sh --x
YAML
  dv "$d"
  sfx "grammar: rc 0" 0 "$DVRC"
  want "grammar: a plain --selftest invocation derives"    "^selftest${TAB}j1${TAB}5${TAB}alpha${TAB}--selftest$"
  want "grammar: a quoted whole value derives its argv"    "^core-live${TAB}j1${TAB}6${TAB}beta${TAB}--dir \. profiles/x$"
  want "grammar: \${{ }} is context"                        "context.*expression"
  # 8 `;` · 9 backtick · 10 absolute · 11 `~` · 12 `..` operand — each refused, none executed
  for _l in 8 9 10 11 12; do want "grammar: line $_l is context" "^context${TAB}j1${TAB}$_l${TAB}"; done
  want "grammar: an uppercase basename is context"          "^context${TAB}j1${TAB}13${TAB}.*closed charset"
  want "grammar: a slashed basename is context"             "^context${TAB}j1${TAB}14${TAB}.*closed charset"
  want "grammar: a missing script is context"               "^context${TAB}j1${TAB}15${TAB}.*no such regular file"
  want "grammar: a SYMLINK script is context (regular files only)" "^context${TAB}j1${TAB}16${TAB}.*no such regular file: conformance/link\.sh"
  want "grammar: a bare operand may not start with a dash" "^context${TAB}j1${TAB}17${TAB}.*closed charset: -rf"
  wantnot "grammar: a run: under with: is an action input, never a step run" "${TAB}verify${TAB}"
  wantnot "grammar: a shell: under with: does not disqualify the step"      "^context${TAB}j1${TAB}21"
  want "grammar: a step whose own run: sits at the step key indent derives" "^core-live${TAB}j1${TAB}21${TAB}beta${TAB}$"
  want "grammar: a lone \`-\` step opener does not swallow its run:" "^core-live${TAB}j1${TAB}25${TAB}alpha${TAB}$"
  want "grammar: the step AFTER a lone-\`-\` step still derives" "^core-live${TAB}j1${TAB}26${TAB}beta${TAB}--x$"
  sfx "grammar: exactly eleven context lines" 11 "$(ctxcount)"
}

# H1: a MULTI-LINE PLAIN SCALAR run:. YAML folds the continuation into ONE command, so deriving the
# first physical line alone runs a TRUNCATED invocation and reports it OK. Both shapes — an operand
# continuation and an `&&` continuation — are context, and the folded mention is UNACCOUNTED.
selftest_continuation() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: sh conformance/alpha.sh
          --dir /etc
      - run: sh conformance/beta.sh
          && sh conformance/alpha.sh
      - run: sh conformance/alpha.sh --selftest
      - {run: sh conformance/beta.sh, if: false}
      - run: sh conformance/beta.sh
          - --dir /etc
YAML
  dv "$d"
  want "continuation: a FLOW-MAPPING step is context, never silently dropped (L5)" "^context${TAB}j1${TAB}10${TAB}-${TAB}flow-mapping step$"
  want "continuation: an operand continuation makes the WHOLE step context" "^context${TAB}j1${TAB}5${TAB}-${TAB}multi-line plain scalar$"
  want "continuation: an \`&&\` continuation likewise"                       "^context${TAB}j1${TAB}7${TAB}-${TAB}multi-line plain scalar$"
  wantnot "continuation: no TRUNCATED invocation is derived"                "${TAB}alpha${TAB}$"
  want "continuation: a \`- \`-led DEEPER line folds too — Psych reads \`beta.sh - --dir /etc\` (I1)" "^context${TAB}j1${TAB}11${TAB}-${TAB}multi-line plain scalar$"
  wantnot "continuation: the dash-led fold derives no truncated argv"       "${TAB}beta${TAB}$"
  want "continuation: a one-line plain scalar is untouched (no over-trigger)" "^selftest${TAB}j1${TAB}9${TAB}alpha${TAB}--selftest$"
  cs "$d"; sfx "continuation: the census reds on the folded step" 1 "$DVRC"
  want "continuation: and the folded mention is UNACCOUNTED" "^5${TAB}alpha${TAB}UNACCOUNTED$"
  want "continuation: the dash-led fold is UNACCOUNTED too"  "^11${TAB}beta${TAB}UNACCOUNTED$"
}

selftest_block_scalar() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: |
          sh conformance/alpha.sh --selftest
          sh conformance/beta.sh
      - run: |
          cd sub
          sh conformance/alpha.sh
      - run: |
          sh conformance/alpha.sh --dir . \
            --extra
      - run: >
          sh conformance/alpha.sh
      - run: |
          echo "running conformance/alpha.sh"
          cat <<EOF
          EOF
      - run: |
          set +e
          sh conformance/alpha.sh
          rc=$?
YAML
  dv "$d"
  want "block: an all-conforming block derives every line (1/2)" "^selftest${TAB}j1${TAB}6${TAB}alpha${TAB}--selftest$"
  want "block: an all-conforming block derives every line (2/2)" "^core-live${TAB}j1${TAB}7${TAB}beta${TAB}$"
  want "block: a cd line makes the WHOLE step context"           "^context${TAB}j1${TAB}8${TAB}-${TAB}block scalar is not all-conforming"
  want "block: a trailing backslash makes the step context"      "^context${TAB}j1${TAB}11${TAB}-${TAB}block scalar"
  want "block: a folded scalar is always context"                "^context${TAB}j1${TAB}14${TAB}-${TAB}block scalar is not all-conforming: folded scalar"
  want "block: a heredoc/echo mention is context"                "^context${TAB}j1${TAB}16${TAB}-${TAB}block scalar"
  want "block: a set +e wrapper is context"                      "^context${TAB}j1${TAB}20${TAB}-${TAB}block scalar"
  wantnot "block: no line of a refused block is ever derived"    "${TAB}alpha${TAB}--dir"
  sfx "block: exactly five context lines" 5 "$(ctxcount)"
}

selftest_disqualifiers() {
  # The STEP-level disqualifiers need three steps in one job, so that job stays a heredoc; each JOB-level
  # one is the same four lines around a single key, so `jd` writes them — asserted by JOB NAME, never by line number, which is exactly why the shared builder is safe here.
  mkci <<'YAML'
jobs:
  j-steps:
    steps:
      - if: always()
        run: sh conformance/alpha.sh
      - working-directory: sub
        run: sh conformance/alpha.sh
      - shell: bash
        run: sh conformance/alpha.sh
YAML
  jd j-iffalse 'if: false'
  jd j-ifexpr "if: github.event_name == 'pull_request'  # only on PRs"
  jd j-defaults 'defaults: {run: {shell: bash}}'
  jd j-matrix 'strategy: {matrix: {shard: [1, 2]}}'
  jd j-services 'services: {postgres: {image: postgres:16}}'
  jd cf-heavy 'strategy: {matrix: {shard: [1]}}'
  dv "$d"
  want "disq: job if: false is context"          "^context${TAB}j-iffalse${TAB}.*job if: false"
  want "disq: a job if: EXPRESSION derives, disclosed as CI-conditional" "^core-live${TAB}j-ifexpr${TAB}.*${TAB}alpha${TAB}${TAB}CI-conditional job (if: github.event_name"
  wantnot "disq: a job if: expression is not silently dropped" "^context${TAB}j-ifexpr${TAB}"
  want "disq: a job defaults: block is context"  "^context${TAB}j-defaults${TAB}.*job key defaults:"
  want "disq: a matrix strategy is context"      "^context${TAB}j-matrix${TAB}.*job key strategy:"
  want "disq: a services: block is context"      "^context${TAB}j-services${TAB}.*job key services:"
  want "disq: a step if: is context"             "^context${TAB}j-steps${TAB}.*step key if:"
  want "disq: working-directory: is context"     "^context${TAB}j-steps${TAB}.*step key working-directory:"
  want "disq: shell: is context"                 "^context${TAB}j-steps${TAB}.*step key shell:"
  wantnot "disq: a trailing YAML comment is stripped from the disclosed if:" "only on PRs"
  want "disq: PRECEDENCE — matrix inside a cf-* job is context, not heavy" "^context${TAB}cf-heavy${TAB}"
  wantnot "disq: PRECEDENCE — the cf-* job yields no heavy row"            "^heavy${TAB}cf-heavy"
  # The shipped adopter profile: its verify.sh step sits in a job carrying `services:` — a §3.1 disqualifier — so the honest verdict is CONTEXT (judgment call, reported to the reviewer).
  if [ -n "$KROOT" ] && [ -f "$KROOT/profiles/typescript-node/ci.yml" ]; then
    dv "$KROOT" --ci-file profiles/typescript-node/ci.yml
    # The point of this leg is "the shipped profile's verify.sh step is CONTEXT, never a local twin" — NOT which disqualifier names it:
    # services: detection itself is proven on the j-services fixture above. Since ADOPTER-KIT-SELFTESTS-ON-CHANGE the step's
    # `${KIT_CHANGED:+…}` operand is refused earlier (closed charset), so either reason is the honest context verdict.
    if printf '%s\n' "$DVOUT" | grep -Eq "^context${TAB}ci${TAB}[0-9]+${TAB}.*(job key services:|operand outside the closed charset)"; then echo "PASS: disq: the adopter profile verify.sh step is context (services: or the closed-charset operand rule)"
    else echo "FAIL: disq: the adopter profile verify.sh step is not context — no job-ci context line citing services: or the closed charset"; SF=1; dump; fi
    wantnot "disq: the adopter profile verify.sh step is never derived as a core-live twin" "^core-live${TAB}ci${TAB}[0-9]*${TAB}verify${TAB}"
    # the premise the comment above states: the profile job still carries services:
    if grep -Eq '^[[:space:]]+services:' "$KROOT/profiles/typescript-node/ci.yml"; then echo "PASS: disq: the adopter profile job still carries services:"
    else echo "FAIL: disq: the adopter profile no longer carries services: — re-read this leg's premise"; SF=1; fi
  fi
}

# env is NEVER applied at ANY level (design §3.1, C15): a literal, non-sensitive workflow/job/step env leaves the step derivable and its names DISCLOSED, never exported.
selftest_env_not_applied() {
  mkci <<'YAML'
env:
  DOCKER_TAG: v1
jobs:
  j1:
    env:
      DATABASE_URL: postgres://localhost/app
    steps:
      - env:
          GH_TOKEN: abc
        run: sh conformance/alpha.sh
      - env:
          BUILD_ID: 7
        run: sh conformance/beta.sh
  j2:
    env:
      SOMETHING: ${{ github.ref }}
    steps:
      - run: sh conformance/alpha.sh
YAML
  dv "$d"
  want "env: a sensitive step env name is context"  "^context${TAB}j1${TAB}.*sensitive name: GH_TOKEN"
  want "env: literal workflow + job + step env names disclosed, none applied" "^core-live${TAB}j1${TAB}14${TAB}beta${TAB}${TAB}job env not applied: DOCKER_TAG, DATABASE_URL, BUILD_ID$"
  want "env: a \${{ }} job env value is context"     "^context${TAB}j2${TAB}.*expression: SOMETHING"
}

# Document-level keys bind the WHOLE file wherever they sit — hence the pre-scan pass.
selftest_doc_level() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: sh conformance/alpha.sh
  j2:
    steps:
      - run: sh conformance/beta.sh
defaults:
  run:
    shell: bash
YAML
  dv "$d"
  want "doc: a defaults: AFTER jobs: disqualifies an ALREADY-FLUSHED job" "^context${TAB}j1${TAB}.*workflow-level defaults:"
  wantnot "doc: a late defaults: leaves nothing derived" "^core-live${TAB}j"
  mkci <<'YAML'
env:
  GH_TOKEN: abc
jobs:
  j1:
    steps:
      - run: sh conformance/alpha.sh
YAML
  dv "$d"
  want "doc: a sensitive WORKFLOW env disqualifies every step" "^context${TAB}j1${TAB}.*workflow env carries a sensitive name: GH_TOKEN"
  wantnot "doc: a sensitive workflow env leaves nothing derived" "^core-live${TAB}j"
}

selftest_ci_file() {
  one_step
  cp "$d/.github/workflows/ci.yml" "$d/.github/workflows/other.yml"
  dv "$d" --ci-file /etc/hosts; sfx "ci-file: a path outside the repo root is rc 2" 2 "$DVRC"
  dv "$d" --ci-file ../../../../etc/hosts; sfx "ci-file: a .. escape is rc 2" 2 "$DVRC"
  # the ROOT RULE holds in EVERY mode: --census off-kit must not let its N/A swallow an outside path.
  rm -f "$d/docs/ROADMAP-KIT.md"
  cs "$d" --ci-file /etc/hosts; sfx "ci-file: --census off-kit still refuses a path outside the root (rc 2)" 2 "$DVRC"
  cs "$d"; sfx "ci-file: --census off-kit is N/A rc 0 for a path INSIDE the root" 0 "$DVRC"
  want "ci-file: the off-kit census says N/A" "^N/A: census is kit-self"
  # An adopter export (or a GitLab adopter) has NO ci.yml at all: the kit-self N/A must land BEFORE the existence rule, so this is rc 0, not rc 2.
  rm -f "$d/.github/workflows/ci.yml"
  cs "$d"; sfx "ci-file: --census off-kit with NO default ci.yml is N/A rc 0" 0 "$DVRC"
  want "ci-file: the no-ci.yml off-kit census still says N/A" "^N/A: census is kit-self"
  cp "$d/.github/workflows/other.yml" "$d/.github/workflows/ci.yml"
  : > "$d/docs/ROADMAP-KIT.md"
  dv "$d" --ci-file .github/workflows/nope.yml; sfx "ci-file: a path naming NOTHING under the root is a usage error (rc 2)" 2 "$DVRC"
  dv "$d" --ci-file .github/workflows/other.yml; sfx "ci-file: a non-default file under the root still derives (rc 0)" 0 "$DVRC"
  want "ci-file: a non-default file is marked UNVERIFIED" "^# UNVERIFIED: derived from a non-CI file$"
  want "ci-file: the header names the file"               "^# ci-file: \.github/workflows/other\.yml$"
  DVOUT=$( cd "$d" && KIT_CI_FILE=.github/workflows/other.yml sh "$LANE" --derive 2>&1 ) && DVRC=0 || DVRC=$?
  want "ci-file: KIT_CI_FILE is honoured"                 "^# ci-file: \.github/workflows/other\.yml$"
  dv "$d"; wantnot "ci-file: the default file is NOT marked UNVERIFIED" "^# UNVERIFIED"
  printf 'name: fx\nsteps: []\n' > "$d/.github/workflows/bad.yml"
  dv "$d" --ci-file .github/workflows/bad.yml; sfx "ci-file: a workflow with no jobs: block is UNVERIFIED (rc 1)" 1 "$DVRC"
  want "ci-file: the UNVERIFIED reason is named" "unparseable ci.yml"
  # --help is rc 2 — the kit's usage convention (sparkwright-verbs.sh locks it live through the router). The usage block is SED-EXTRACTED from this file's header: its anchors bind.
  DVOUT=$(sh "$LANE" --help 2>&1) && DVRC=0 || DVRC=$?
  sfx "ci-file: --help exits 2 (the kit's usage convention)" 2 "$DVRC"
  wantnot "ci-file: --help prints the usage block, not the script body" "^set -eu$"
  want "ci-file: --help prints the usage line" "^Usage: sh conformance/prepush-lane\.sh"
  # NO ARGUMENT is THE RUN (task 3): `sparkwright prepush` takes no mode flag. Only --help is rc 2.
  commit_fx; rn "$d"; want "ci-file: no argument RUNS and ends on the verdict" "^PARITY-CORE: "
  # M1: in RUN mode the UNVERIFIED header owes a matching VERDICT — the LAST line, and nothing ran.
  rn "$d" --ci-file .github/workflows/other.yml
  sfx "ci-file: a non-default file in a RUN is UNVERIFIED on the LAST line" "PARITY-CORE: UNVERIFIED (derived from a non-CI file: .github/workflows/other.yml)" "$(lastline)"
  wantnot "ci-file: and the non-CI derivation is never executed" "^  OK  "
  # liveness anchor: the kit's own ci.yml. Kit-self only; N/A elsewhere.
  if [ -n "$KROOT" ] && grep -q '^# Kit-own CI' "$KROOT/$CI_DEFAULT" 2>/dev/null; then
    dv "$KROOT"
    sfx "ci-file: the kit's real ci.yml derives (rc 0)" 0 "$DVRC"
    _n=$(printf '%s\n' "$DVOUT" | grep -cv '^#' || :)
    if [ "$_n" -ge 200 ]; then echo "PASS: ci-file: the real ci.yml yields $_n lines (>= 200)"
    else echo "FAIL: ci-file: the real ci.yml yielded only $_n lines (< 200)"; SF=1; fi
  else
    echo "PASS: ci-file: N/A — not the kit tree (the >= 200 liveness anchor is kit-self only)"
  fi
}

# --- task 2: the two-stage census and the twin table ------------------------------------------
# A "new step in no bucket" is a mention the lane neither DERIVES nor has a row for: here a conforming
# invocation a step `if:` pushes into context. The same step WITHOUT it derives — both directions, one leg.
selftest_census_unbucketed() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: sh conformance/alpha.sh --selftest
      - if: always()
        run: sh conformance/beta.sh --new-flag
YAML
  cs "$d"; sfx "census: a conforming step in NO bucket, with no row, reds the census" 1 "$DVRC"
  want "census: the unbucketed mention is NAMED"    "^7${TAB}beta${TAB}UNACCOUNTED$"
  want "census: the derived mention is accounted"   "^5${TAB}alpha${TAB}derived$"
  want "census: the summary counts both directions" "^# census: 2 mentions · 1 derived .* 1 UNACCOUNTED"
  mkcin 'sh conformance/alpha.sh --selftest' 'sh conformance/beta.sh --new-flag'
  cs "$d"; sfx "census: the SAME step without the disqualifier derives and the census is clean" 0 "$DVRC"
  # liveness: the kit's own ci.yml against the SHIPPED table. Kit-self only.
  if [ -n "$KROOT" ] && grep -q '^# Kit-own CI' "$KROOT/$CI_DEFAULT" 2>/dev/null; then
    cs "$KROOT"; sfx "census: the kit's real ci.yml + the shipped table is clean (rc 0)" 0 "$DVRC"
    want "census: the live summary is printed" "^# census: [0-9]* mentions"
  else
    echo "PASS: census: N/A — not the kit tree (the live-census anchor is kit-self only)"
  fi
}

# The denominator does NOT depend on the tokenizer: an unparseable mention is still counted, and so is a basename outside [a-z0-9-]+ (for which no row can even be written).
selftest_census_denominator() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: |
          cd sub
          sh conformance/alpha.sh
YAML
  cs "$d"; sfx "census/denominator: an unparseable shape (cd-prefixed block) still reds" 1 "$DVRC"
  want "census/denominator: the unparseable mention is named" "^7${TAB}alpha${TAB}UNACCOUNTED$"
  mkci1 'sh conformance/Foo_bar.v2.sh'
  cs "$d"; sfx "census/denominator: an off-convention basename reds" 1 "$DVRC"
  want "census/denominator: the off-convention basename is named" "^5${TAB}Foo_bar\.v2${TAB}UNACCOUNTED$"
}

selftest_census_negative() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      # a comment mentioning conformance/beta.sh must not count
      - name: this step name mentions conformance/beta.sh too
        run: sh conformance/alpha.sh
YAML
  cs "$d"; sfx "census/negative: a comment-only and a name:-only mention are not counted (rc 0)" 0 "$DVRC"
  want "census/negative: exactly ONE mention is counted"  "^# census: 1 mentions · 1 derived"
  wantnot "census/negative: nothing is unaccounted"       "${TAB}UNACCOUNTED$"
}

selftest_twin_stale() {
  one_step
  tw alpha twin 'sh conformance/alpha.sh --gone-from-ci' 'alpha.sh --selftest' 0 '' ''
  cs "$d"; sfx "twin/stale: a row whose ci-shape matches no denominator line reds" 1 "$DVRC"
  want "twin/stale: the stale row is named" "^# STALE ROW: alpha twin"
}

# Accounting is by SHAPE (C19): a SECOND, differently-shaped invocation of a twinned check must surface rather than hide behind the first row's basename.
selftest_twin_cishape() {
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: 'if sh conformance/alpha.sh; then echo ok; fi'
      - run: |
          out=$(sh conformance/alpha.sh --x)
YAML
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh --selftest' 0 '' ''
  cs "$d"; sfx "twin/ci-shape: a twinned basename in a SECOND shape reds" 1 "$DVRC"
  want "twin/ci-shape: the covered shape is accounted by the row" "^5${TAB}alpha${TAB}twin:alpha$"
  want "twin/ci-shape: the uncovered shape is UNACCOUNTED"        "^7${TAB}alpha${TAB}UNACCOUNTED$"
}

selftest_heavy_rows() {
  one_step
  tw alpha heavy '' '' '' '' 'slow, but nobody measured it'
  cs "$d"; sfx "heavy: a heavy row without budget-s reds" 1 "$DVRC"
  want "heavy: the malformed row is named" "TWIN-TABLE MALFORMED: .*needs an integer budget-s"
  mkcin 'sh conformance/alpha.sh' 'sh conformance/alpha.sh; echo also-here'
  tw alpha heavy '' '' '' 600 'measured 300s x 2'
  cs "$d"; sfx "heavy: a heavy row NEVER accounts a mention" 1 "$DVRC"
  want "heavy: its derived invocation stays in the numerator" "^5${TAB}alpha${TAB}derived$"
  want "heavy: the context mention is still UNACCOUNTED"      "^6${TAB}alpha${TAB}UNACCOUNTED$"
  want "heavy: the row is counted as heavy, subtracting nothing" "· 1 heavy rows"
  # M-4: a heavy row annotates an invocation IN the numerator; one whose check no longer derives annotates nothing and would leave --slow inert — a census red, named.
  one_step
  tw beta heavy '' '' '' 60 'fixture: a heavy row for a check ci.yml no longer runs'
  cs "$d"; sfx "heavy: a heavy row whose check no longer derives reds the census" 1 "$DVRC"
  want "heavy: the stale heavy row is named" "^# STALE HEAVY ROW: beta"
}

selftest_twin_grammar() {
  mkci1 "'if sh conformance/alpha.sh; then echo ok; fi'"
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh --x $(id)'   0 '' ''
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh --x `id`'    0 '' ''
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh "--x"'       0 '' ''
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh --b {nope}'  0 '' ''
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh /etc/passwd' 0 '' ''
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh --a {branch}.{branch}' 0 '' ''
  cs "$d"; sfx "twin/grammar: a table of refused rows reds" 1 "$DVRC"
  want "twin/grammar: a \$( row is refused"        'MALFORMED.*forbidden character.*\$(id)'
  want "twin/grammar: a backtick row is refused"   'MALFORMED.*forbidden character.*`id`'
  want "twin/grammar: a quoted row is refused"     'MALFORMED.*forbidden character.*"--x"'
  # the MECHANISM'S OWN wording: a widened gsub is caught a layer later, in words this does NOT match.
  want "twin/grammar: a placeholder outside the closed set is refused" 'MALFORMED.*placeholder outside .*{nope}'
  want "twin/grammar: a row the SCANNER refuses is reported not executable" 'MALFORMED: alpha: twin row is NOT EXECUTABLE.*alpha\.sh /etc/passwd'
  # A repeated placeholder must be refused at READ time: neutralised, the row sails through the executable check and would then run with a literal `{branch}`.
  want "twin/grammar: a token repeating a placeholder is MALFORMED" 'MALFORMED.*repeats a placeholder within one token.*{branch}\.{branch}'
  wantnot "twin/grammar: the repeating row accounts nothing" "${TAB}alpha${TAB}twin:"
  mkci1 "'if sh conformance/alpha.sh --head x; then echo ok; fi'"
  tw alpha twin 'if sh conformance/alpha.sh' 'alpha.sh --head {head}' 0 '' ''
  cs "$d"; sfx "twin/grammar: a row inside the grammar AND the closed placeholder set passes (rc 0)" 0 "$DVRC"
  want "twin/grammar: the valid row accounts its mention" "^5${TAB}alpha${TAB}twin:alpha$"
}

# The SAME code path task 3's runner uses: placeholders into POSITIONAL PARAMETERS, never a string.
selftest_injection() {
  PH_BRANCH="x;\$(touch $WORK/pwned)"; _inj=$(subst_argv 'alpha.sh --branch {branch}'); PH_BRANCH=""
  sfx "injection: the argv is exactly three tokens" 3 "$(printf '%s\n' "$_inj" | wc -l | tr -d ' ')"
  if printf '%s\n' "$_inj" | grep -qxF "x;\$(touch $WORK/pwned)"
  then echo "PASS: injection: the hostile branch is ONE LITERAL token"
  else echo "FAIL: injection: the hostile branch did not survive as one literal token"; SF=1
       printf '%s\n' "$_inj" | sed 's/^/      /'; fi
  if [ -e "$WORK/pwned" ]
  then echo "FAIL: injection: the substituted command RAN — $WORK/pwned exists"; SF=1
  else echo "PASS: injection: nothing executed (no pwned file)"; fi
  # SINGLE PASS: a value that itself looks like a placeholder is NOT expanded a second time.
  PH_BRANCH='v{head}'; PH_HEAD=HD
  _inj=$(subst_argv '{branch}'); PH_BRANCH=""; PH_HEAD=""
  sfx "injection: a value containing a placeholder is one literal token" 'v{head}' "$_inj"
  sfx "injection: and it is exactly ONE token" 1 "$(printf '%s\n' "$_inj" | wc -l | tr -d ' ')"
}

# --- task 3: the runner (scrub, shim, bounds, listing, flags, verdict) ------------------------
# Every run leg drives a FIXTURE repo with FIXTURE checks under the lane's work root, never the kit's real checks (the only live anchors are --derive/--census, above).
commit_fx() { ( cd "$d" && git add -A && git -c user.email=f@x -c user.name=f commit -qm fx ) >/dev/null; }
mkchk() { printf '#!/bin/sh\n%s\n' "$2" > "$d/conformance/$1.sh"; }
# rn <repo> [args…] -> DVOUT/DVRC for a RUN. `--base HEAD` keeps a fixture off origin/main; a later --base in [args…] wins, which is how the base legs drive the validator.
rn() { _r=$1; shift; DVOUT=$( cd "$_r" && sh "$LANE" --base HEAD "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }
env_rn() { _r=$1; _e=$2; _v=$3; shift 3
  DVOUT=$( cd "$_r" && export "$_e=$_v" && sh "$LANE" --base HEAD "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }
lastline() { printf '%s\n' "$DVOUT" | sed -n '$p'; }
workroot() { printf '%s\n' "$DVOUT" | sed -n 's/^# work root: \([^ ]*\) .*/\1/p' | sed -n 1p; }
one_step() { mkci1 'sh conformance/alpha.sh'; }

# need_cls <leg> — the docs-only legs must use CI'S OWN classifier (D-240903-3), so it is copied into the fixture; rc 1 (N/A, off the kit tree) stands the leg down rather than asserting nothing.
need_cls() { [ -n "$KROOT" ] && [ -f "$KROOT/conformance/ci-classify-changes.sh" ] ||
    { echo "PASS: $1: N/A — ci-classify-changes.sh is not in this tree"; return 1; }
  cp "$KROOT/conformance/ci-classify-changes.sh" "$d/conformance/"; }
# §3.4, and M-5: `adopter-told` twins only because every child's TMPDIR is this run's work root.
selftest_scrub() {
  # Every BLANKET unset_pfx is probed by a name NOTHING else in the lane assigns (reviewer I-2): GIT_*
  # through GIT_SSH_COMMAND/GIT_DIR, never through GIT_CONFIG_GLOBAL — the scrub ASSIGNS that one two
  # lines later, so it survives the prefix-unset being deleted outright and proves nothing.
  one_step; mkchk alpha 'printf "gh=[%s] ssh=[%s] kit=[%s] gsc=[%s] gdir=[%s] bc=[%s] pp=[%s] jira=[%s%s] gcg=[%s] lc=[%s] home=[%s] tmp=[%s] gol=[%s]\n" "${GH_TOKEN-}" "${SSH_AUTH_SOCK-}" "${KIT_NOSE-}" "${GIT_SSH_COMMAND-}" "${GIT_DIR-}" "${BOARD_CLAIM_X-}" "${PREPUSH_X-}" "${JIRA_EMAIL-}" "${JIRA_TOKEN-}" "${GIT_CONFIG_GLOBAL-}" "${LC_ALL-}" "$HOME" "$TMPDIR" "${GIT_OPTIONAL_LOCKS-}" > "$PWD/env.out"'
  commit_fx
  # GIT_DIR is paired with GIT_WORK_TREE so the LANE's own git still works: unpaired, it points the lane itself at another repo — a different question (rc 2, "not a git repository").
  DVOUT=$( cd "$d" && GH_TOKEN=tok SSH_AUTH_SOCK=/tmp/s KIT_NOSE=1 GIT_SSH_COMMAND='ssh -i /k' GIT_DIR=$d/.git GIT_WORK_TREE=$d BOARD_CLAIM_X=1 PREPUSH_X=1 JIRA_EMAIL=e@x JIRA_TOKEN=jt sh "$LANE" --base HEAD --warranted 2>&1 )  # --warranted: the probe is a core-live check
  _wr=$(workroot); _env=$(cat "$d/env.out" 2>/dev/null || echo MISSING)
  sfx "scrub: every scrubbed prefix is empty, HOME is under the work root, LC_ALL is C, and GIT_OPTIONAL_LOCKS is 0 (PL4: set after the GIT_ prefix is unset, so it survives it)" "gh=[] ssh=[] kit=[] gsc=[] gdir=[] bc=[] pp=[] jira=[] gcg=[/dev/null] lc=[C] home=[$_wr/empty] tmp=[$_wr/tmp] gol=[0]" "$_env"
  # PL4 mutant: the assignment deleted (the export then marks an unset name: the arm sees nothing)
  trmut pl4 -e '/^    GIT_CONFIG_GLOBAL=\/dev\/null; /s/; GIT_OPTIONAL_LOCKS=0//'
  [ -z "$TRM" ] || { rm -f "$d/env.out"; DVOUT=$( cd "$d" && sh "$TRM" --base HEAD --warranted 2>&1 ) || :
    sfx "PL4 mutant: with the assignment gone the arm reads gol=[] (the cell is RED)" "yes" "$(grep -q 'gol=\[\]$' "$d/env.out" 2>/dev/null && echo yes || echo no)"; }
}

selftest_docs_only() {
  one_step; mkchk alpha 'exit 0'; need_cls docs-only || return 0
  commit_fx; : > "$d/notes.md"; rn "$d"; sfx "docs-only: rc 0" 0 "$DVRC"
  want "docs-only: the classifier (D-240903-3) says docs-only" "^# docs-only: true$"
  want "docs-only: and nothing heavy is recommended" "none — the delta is docs-only"
  # PREPUSH-CORE-DEFAULT: core-live runs only under --warranted, so the "docs-only never skips the core"
  # half of this leg's intent is proven there (docs-only warrants nothing heavy, the core still runs).
  rn "$d" --warranted; sfx "docs-only: --warranted rc 0" 0 "$DVRC"
  want "docs-only: the core still runs (under --warranted)" "^  OK    core-live "
}

# --no-renames reproduces the SOURCE path, so a rename of a check to .md is not docs-only.
selftest_rename() {
  one_step; mkchk alpha 'exit 0'; need_cls rename || return 0
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD ); mkdir -p "$d/docs"
  ( cd "$d" && git mv conformance/beta.sh docs/x.md ); commit_fx; rn "$d" --base "$_b0"
  want "rename: a rename of a .sh to a .md is NOT docs-only" "^# docs-only: false$"
  want "rename: the source path is in the listing"           "^# listing: 2 path"
}

selftest_newline() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  # --warranted: the core-live set is what the UNVERIFIED stop must keep from running (the default no longer runs it).
  _nl=$(printf 'bad\nname'); : > "$d/$_nl.md"; rn "$d" --warranted; rm -f "$d/$_nl.md"; sfx "newline: a listed path with a newline is non-zero" 1 "$DVRC"
  want "newline: UNVERIFIED NAMING the offending path (git's own quoting prints it safely)" '^PARITY-CORE: UNVERIFIED (newline in a listed path: "bad.nname\.md")$'
  wantnot "newline: nothing was executed" "^  OK  "
  _r=0; ph_newline_ok "/a/b" "feat/x" || _r=$?; sfx "newline: clean substituted values pass" 0 "$_r"
  _r=0; ph_newline_ok "/a/b" "$_nl"   || _r=$?; sfx "newline: a substituted value with a newline is refused (ph_pass prints one token per line)" 1 "$_r"
}

# R-C11 c1 regression (security fix, this fix round): basename_ok/base_ok must refuse an embedded
# newline, not just match one LINE of a multi-line value (a per-line `grep -qx` would pass a value
# like `printf 'ok\n-rf'` if ANY one of its lines matched the charset). Locks the fix at three sites:
# the two typed flags that call the predicates through die2, and a direct call to each predicate
# itself (the same pattern selftest_newline uses above for ph_newline_ok).
selftest_newline_charset() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  _nlb=$(printf 'a\n-rf')
  rn "$d" --non-vacuity "$_nlb"
  sfx "newline-charset: --non-vacuity with an embedded newline is rc 2" 2 "$DVRC"
  want "newline-charset: --non-vacuity names the closed charset refusal" \
    '^prepush-lane: --non-vacuity basename outside \[a-z0-9\.-\]+, and never starting with a dash:'

  _nlr=$(printf 'HEAD\n-x')
  DVOUT=$( cd "$d" && sh "$LANE" --base "$_nlr" 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "newline-charset: --base with an embedded newline is rc 2" 2 "$DVRC"
  want "newline-charset: --base names the closed charset refusal" \
    '^prepush-lane: --base outside the closed charset \[A-Za-z0-9\._/-\]+:'

  _r=0; basename_ok "$(printf 'ok\n;id x')" || _r=$?
  sfx "newline-charset: basename_ok direct-call refuses an embedded newline" 1 "$_r"
  _r=0; base_ok "$(printf 'HEAD\nmain')" || _r=$?
  sfx "newline-charset: base_ok direct-call refuses an embedded newline" 1 "$_r"
}

selftest_base() {
  one_step; mkchk alpha 'exit 0'; commit_fx; rn "$d" --base --output=x; sfx "base: a leading dash is rc 2, never a git operand" 2 "$DVRC"
  rn "$d" --base 'a..b';     sfx "base: a '..' ref is rc 2" 2 "$DVRC"
  rn "$d" --base 'x;id';     sfx "base: a ref outside the closed charset is rc 2" 2 "$DVRC"
  rn "$d" --base nosuchref;  sfx "base: a ref that is no commit is rc 2" 2 "$DVRC"
  rn "$d"; want "base: a valid base is named with its commit" "^# base: HEAD ([0-9a-f]"
}

# The ceiling's detection half (§3.7): a heavy row's budget-s IS its ceiling, and exceeding it names the remedy rather than reporting an opaque rc.
selftest_ceiling() {
  one_step; mkchk alpha 'sleep 5'; tw alpha heavy '' '' '' 1 'fixture: a one-second budget'
  commit_fx; rn "$d" --slow; sfx "ceiling: an invocation over its budget is non-zero" 1 "$DVRC"
  want "ceiling: the FAIL names the remedy" "exceeded ceiling — add a heavy row with the measured budget or raise the ceiling"
  sfx "ceiling: the verdict is FAIL" "PARITY-CORE: FAIL" "$(lastline)"
}

selftest_budget() {
  one_step; mkchk alpha 'exit 0'; commit_fx; env_rn "$d" PREPUSH_CEILING_S 5; want "budget: a LOWER ceiling is ignored loudly, and the default stands" "IGNORED: PREPUSH_CEILING_S may only RAISE (5 <= 120) — using 120"
  env_rn "$d" PREPUSH_CEILING_S abc; want "budget: a non-numeric ceiling is ignored loudly" "IGNORED: PREPUSH_CEILING_S is not numeric"
  env_rn "$d" PREPUSH_CEILING_S 300; want "budget: a HIGHER ceiling is honoured" "^# ceiling: 300s/invocation"
}

selftest_floor() {
  _r=0; mem_guard '' 6144  || _r=$?; sfx "floor: an unreadable reading is its own answer" 2 "$_r"
  _r=0; mem_guard abc 6144 || _r=$?; sfx "floor: a non-numeric reading is unreadable, never 'fine'" 2 "$_r"
  _r=0; mem_guard 100 6144 || _r=$?; sfx "floor: below the floor" 1 "$_r"
  _r=0; mem_guard 9999 6144 || _r=$?; sfx "floor: met" 0 "$_r"
  one_step; mkchk alpha 'exit 0'; commit_fx; env_rn "$d" PREPUSH_MEM_FLOOR_MB 3
  want "floor: the env may only RAISE the floor" "IGNORED: PREPUSH_MEM_FLOOR_MB may only RAISE"
  env_rn "$d" PREPUSH_MEM_FLOOR_MB 99999999 --green-on-clone; want "floor: an unmet floor REFUSES the heavy arm" "the green-on-clone arm is refused"
  # PREPUSH-CORE-DEFAULT: core-live is --warranted-only, and --warranted cannot ride with a heavy flag, so
  # "a refused heavy arm does not stop the rest of the run" is proven on a remaining DEFAULT arm: the
  # touched-selftest face (a stub hermetic, as in selftest_core_selftest).
  mkcin 'sh conformance/gamma.sh --selftest'
  mkchk selftest-hermetic 'echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _flb=$(git -C "$d" rev-parse HEAD); mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx   # SWAS-811: committed and capable, so it is a roster target
  env_rn "$d" PREPUSH_MEM_FLOOR_MB 99999999 --base "$_flb" --green-on-clone
  want "floor: the arm is still refused on this fixture"      "the green-on-clone arm is refused"
  want "floor: and the rest of the default still runs (core-selftest)" "^  OK    core-selftest "
}

selftest_argv() {
  one_step; mkchk alpha 'exit 0'; commit_fx; rn "$d" --require; sfx "argv: --require is the explicit spelling of the default" 0 "$DVRC"
  rn "$d" --require --best-effort; sfx "argv: --require with --best-effort is rc 2" 2 "$DVRC"
  rn "$d" --green-on-clone --exports; sfx "argv: two heavy arms in one invocation is rc 2" 2 "$DVRC"
  want "argv: the reason is named" "one heavy arm per invocation"
  rn "$d" --bogus; sfx "argv: an unknown flag is rc 2" 2 "$DVRC"; want "argv: and it is never forwarded" "never forwarded"
  rn "$d" --non-vacuity 'a;id';    sfx "argv: a --non-vacuity operand outside the charset is rc 2" 2 "$DVRC"
  rn "$d" --non-vacuity -rf;       sfx "argv: a --non-vacuity operand with a LEADING DASH is rc 2, never a forwarded flag" 2 "$DVRC"
}

# I-1: the core-selftest FACE — one call to selftest-hermetic.sh --touched under HERMETIC_BASE, with the
# split labels actually EMITTED. The hermetic script is a FIXTURE STUB recording its argv and
# HERMETIC_BASE (the real one is far too heavy, and would make this a live anchor). `gamma` is written
# AFTER commit_fx, so it is UNTRACKED and in the listing = touched; `beta` is committed and untouched.
selftest_core_selftest() {
  mkcin 'sh conformance/gamma.sh --selftest' 'sh conformance/beta.sh --selftest'
  mkchk selftest-hermetic 'printf "base=[%s] argv=[%s]\n" "${HERMETIC_BASE-}" "$*" > "$PWD/herm.out"; echo "TARGET: $1 (both faces)"'
  commit_fx; _csb=$(git -C "$d" rev-parse HEAD); mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx   # SWAS-811: the roster needs the touched script committed and capable
  rn "$d" --base "$_csb" --verbose; sfx "core-selftest: rc 0" 0 "$DVRC"
  want "core-selftest: the touched face RUNS and is labelled core-selftest" "^  OK    core-selftest *conformance/gamma\.sh (both faces)"
  want "core-selftest: the untouched invocations are LISTED, not run" "^# untouched-selftest: 1 derived --selftest invocations NOT run"
  wantnot "core-selftest: the MERGED scanner label never appears in a run report" "^  OK    selftest "
  wantnot "core-selftest: and the core-selftest face does not run the untouched one (only the touched-readers arm may, by its measured budget; SWAS-468)" "^  OK    core-selftest .*beta"
  want "core-selftest: beta appears only under touched-readers (the arm's budget, not the core-selftest face)" "^  OK    touched-readers  *beta --selftest "
  sfx "core-selftest: the hermetic call got the ONE touched path under HERMETIC_BASE=the base" "base=[$_csb] argv=[conformance/gamma.sh]" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  want "core-selftest: the ceiling line prints the selftest budget (a label, not a cutoff, SWAS-840) and the runaway ceiling, not SELFCEIL" "^# ceiling: 120s/invocation (core-selftest: budget 300 s, printed, not a cutoff; runaway ceiling 3600 s per target · other core arms 3600s · heavy arms 3600s"
}

# SWAS-442 (C6): verify.sh's hermetic faces are CI-bound locally, and the verdict never claims they ran. The hermetic script is again a
# recording stub. The fixture commits verify.sh (and gamma) AFTER the base commit, so both are in the listing (`--base <the sha between the commits>`; a later --base wins; the base charset has no `~`).
selftest_local_defer() {
  _ldclause='1 touched selftest(s) NOT ENFORCED locally — CI binds them: conformance/verify.sh'
  # LD1-LD3: verify.sh is the only touched selftest -> the stub is never called, the clause and the H2 note are printed
  mkcin 'sh conformance/verify.sh --selftest'
  mkchk selftest-hermetic 'printf "argv=[%s]\n" "$*" > "$PWD/herm.out"; echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkchk verify 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx; rn "$d" --base "$_ldb"; sfx "local-defer: a touched verify.sh alone is rc 0" 0 "$DVRC"
  sfx "local-defer: and the hermetic lane is NOT called for it (no faces run)" "MISSING" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  sfx "local-defer: the verdict is an OK that carries the NOT ENFORCED clause naming verify.sh" "yes" "$(lastline | grep -e '^PARITY-CORE: OK (' | grep -qF -e "${_ldclause})" && echo yes || echo no)"
  want "local-defer: the run says CI's H2 lane grades it" "^# core-selftest: .*NOT ENFORCED locally.*conformance/verify\.sh.*H2 lane"
  wantnot "local-defer: no core-selftest OK line claims a face ran" "^  OK    core-selftest "
  # LD4-LD5 (the load-bearing negative): a non-listed target touched beside verify.sh still runs its faces, and verify.sh is not among them
  mkcin 'sh conformance/verify.sh --selftest' 'sh conformance/gamma.sh --selftest'
  mkchk selftest-hermetic 'printf "argv=[%s]\n" "$*" > "$PWD/herm.out"; echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkchk verify 'case ${1-} in --selftest) exit 0 ;; esac'; mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx
  rn "$d" --base "$_ldb"; sfx "local-defer: verify.sh plus a non-listed target is rc 0" 0 "$DVRC"
  sfx "local-defer: the non-listed target's faces RUN, as the only explicit target" "argv=[conformance/gamma.sh]" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  want "local-defer: that run is labelled core-selftest" "^  OK    core-selftest "
  sfx "local-defer: and the clause is still printed" "yes" "$(lastline | grep -qF -e "$_ldclause" && echo yes || echo no)"
  # LD4b (fix round I-1; SWAS-811: one call per target): TWO other touched targets reach the hermetic lane as TWO calls, one path each, sorted — never one joined string
  mkcin 'sh conformance/verify.sh --selftest' 'sh conformance/gamma.sh --selftest' 'sh conformance/delta.sh --selftest'
  mkchk selftest-hermetic 'printf "argv=[%s]\n" "$*" >> "$PWD/herm.out"; echo "TARGET: $1 (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkchk verify 'case ${1-} in --selftest) exit 0 ;; esac'
  mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; mkchk delta 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx; rn "$d" --base "$_ldb"
  sfx "local-defer: two other touched targets arrive as two calls, one path each" "argv=[conformance/delta.sh] argv=[conformance/gamma.sh]" "$(tr '\n' ' ' < "$d/herm.out" 2>/dev/null | sed 's/ $//' || echo MISSING)"
  # LD4c: the argv is counted, not just printed (a joined string would be ONE argument)
  mkchk selftest-hermetic 'printf "n=%s\n" "$#" >> "$PWD/herm.out"; echo "TARGET: $1 (both faces)"'
  rm -f "$d/herm.out"; rn "$d" --base "$_ldb"
  sfx "local-defer: and each call counts exactly 1 argument" "n=1 n=1" "$(tr '\n' ' ' < "$d/herm.out" 2>/dev/null | sed 's/ $//' || echo MISSING)"
  # LD6: only a non-listed target touched -> one call for it, by its own path, and no clause
  mkcin 'sh conformance/gamma.sh --selftest'
  mkchk selftest-hermetic 'printf "argv=[%s]\n" "$*" > "$PWD/herm.out"; echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx; rn "$d" --base "$_ldb"
  sfx "local-defer: a non-listed target alone is called by its own path" "argv=[conformance/gamma.sh]" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  sfx "local-defer: and prints no clause" "no" "$(lastline | grep -qF -e 'NOT ENFORCED locally' && echo yes || echo no)"
  # LD8 (L2): a path that merely CONTAINS the listed name (a nested copy, a backup) is not the listed target: the other target is still called by its path, no clause
  mkcin 'sh conformance/gamma.sh --selftest'
  mkchk selftest-hermetic 'printf "argv=[%s]\n" "$*" > "$PWD/herm.out"; echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkdir -p "$d/docs/conformance"; printf '#!/bin/sh\n' > "$d/docs/conformance/verify.sh"
  printf '#!/bin/sh\n' > "$d/conformance/verify.sh.bak"; mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx; rn "$d" --base "$_ldb"
  sfx "local-defer: a nested or suffixed verify.sh is not the listed target: the other target is still called by its path" "argv=[conformance/gamma.sh]" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  sfx "local-defer: and prints no clause (the match is the whole line)" "no" "$(lastline | grep -qF -e 'NOT ENFORCED locally' && echo yes || echo no)"
  # LD9 (L1): an other touched target whose name cannot be argv is NAMED in the clause, never silently dropped
  mkcin 'sh conformance/verify.sh --selftest'
  mkchk selftest-hermetic 'printf "argv=[%s]\n" "$*" > "$PWD/herm.out"; echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkchk verify 'case ${1-} in --selftest) exit 0 ;; esac'
  printf '#!/bin/sh\ncase ${1-} in --selftest) exit 0 ;; esac\n' > "$d/conformance/odd name.sh"; commit_fx; rn "$d" --base "$_ldb"
  sfx "local-defer: with only an out-of-charset other target, no hermetic call is made" "MISSING" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  sfx "local-defer: the clause names that path as CI-bound" "yes" "$(lastline | grep -qF -e 'conformance/odd name.sh (name outside the argv charset; CI binds it)' && echo yes || echo no)"
  # LD10 (M-1): verify.sh alone must not let a reasonless hermetic-exclusions entry slip past (the lane's own validation is skipped with no call)
  mkcin 'sh conformance/verify.sh --selftest'
  mkchk selftest-hermetic 'echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; _ldb=$(git -C "$d" rev-parse HEAD); mkchk verify 'case ${1-} in --selftest) exit 0 ;; esac'
  printf 'anything.sh\n' > "$d/conformance/hermetic-exclusions.txt"; commit_fx; rn "$d" --base "$_ldb"
  sfx "local-defer: a reasonless exclusions entry beside a touched verify.sh is rc 1" 1 "$DVRC"
  want "local-defer: and the FAIL names the entry" "^  FAIL  core-selftest .*hermetic-exclusions.txt entry 'anything.sh'"
  printf 'anything.sh\tfixture: dispositioned\n' > "$d/conformance/hermetic-exclusions.txt"; commit_fx; rn "$d" --base "$_ldb"
  sfx "local-defer: the same file with a reason is rc 0" 0 "$DVRC"
  # LD7: the exemption is a literal one-entry list, never a pattern
  _ldn=$(grep -c -e "^LOCAL_DEFER_SELFTESTS='conformance/verify\.sh'" "$LANE" || :)
  sfx "local-defer: the exemption is the literal one-entry list" 1 "$_ldn"
}

# SWAS-811 (design docs/architecture/2026-11-10-prepush-names-every-selftest-811-design.md, controls R1-R6 and R8-R19): the touched selftests are run one call per target, inside a wall
# budget, or named — never silent. Every cell drives a kit-tree fixture whose hermetic script is a recording STUB (the real one is far too heavy) and carries ONE named mutant: a sed on a
# COPY of the lane (trmut) that must turn the same scenario RED. The mutation targets are the `# ST…` tags in the lane's own text. A budget small enough to test is a SCALED lane copy
# (the touched-budget cells' idiom: a sed on ST_BUDGET_DEFAULT), never an environment or argv knob.
# stfx <stub-body> [path…] -> $d, _stb: the stub runs <stub-body>; each capable <path> (its own bytes, so its own blob sha) is COMMITTED after the base commit _stb, so the listing is
# the delta against _stb and every path is committed.
stfx() {
  _sb=$1; shift
  one_step; mkchk selftest-hermetic "$_sb"; commit_fx; _stb=$(git -C "$d" rev-parse HEAD)
  for _sp in "$@"; do
    mkdir -p "$d/${_sp%/*}"; printf '#!/bin/sh\n# %s\ncase ${1-} in --selftest) exit 0 ;; esac\n' "$_sp" > "$d/$_sp"
  done
  # with no path there is nothing to commit, and `git commit` then exits 1: under `set -e` that ended the whole selftest silently (R8 and R19 call stfx with no path)
  [ "$#" -eq 0 ] || commit_fx
}
# hm — what the recording stub saw, one `argv=[…]` per call, or MISSING when it was never called.
hm() { if [ -f "$d/herm.out" ]; then tr '\n' ' ' < "$d/herm.out" | sed 's/ $//'; else echo MISSING; fi; }
# strun <home> <lane> [VAR=value…] — a RUN of $d against the delta _stb with the cache ON in <home> (the recorded times live there) -> DVOUT/DVRC.
strun() { _sh=$1; _sl=$2; shift 2; DVOUT=$( cd "$d" && env HOME="$_sh" PREPUSH_NO_CACHE=0 "$@" sh "$_sl" --base "$_stb" 2>&1 ) && DVRC=0 || DVRC=$?; }
# stt <home> <blob>=<seconds>… — the times state of <home>: one `@selftest` row per blob (or key) -> where the lane under test looks.
stt() {
  _sth=$1; shift; : > "$WORK/trtab.rows"
  for _stk in "$@"; do printf '@selftest\t%s\t%s\t0\tlocal\t%s\n' "${_stk%%=*}" "${_stk#*=}" "$(date +%s)" >> "$WORK/trtab.rows"; done
  trtab "$_sth"
}
STREC='printf "argv=[%s]\n" "$*" >> "$PWD/herm.out"; echo "TARGET: $1 (both faces)"'
STSLEEP='printf "argv=[%s]\n" "$*" >> "$PWD/herm.out"; sleep 6'
STTRAP='trap "exit 130" TERM INT; printf "argv=[%s]\n" "$*" >> "$PWD/herm.out"; sleep 6 & wait $!'
STFORGE=': > "$TMPDIR/../ctl/wd.fired"; exit 1'
# R1-R4, R6, R8, R11, R15: what is on the roster, and what happens to each entry.
selftest_troster() {
  # R1 — a scripts-only diff (the 192a shape): ONE core-selftest row, ONE call for the script, a roster line
  stfx "$STREC" scripts/x.sh; rn "$d" --base "$_stb"
  sfx "roster/R1: rc 0" 0 "$DVRC"
  want "roster/R1: a scripts-only diff gets ONE core-selftest row for the script" "^  OK    core-selftest *scripts/x\.sh (both faces)"
  sfx "roster/R1: the hermetic lane got the one path, as one call" "argv=[scripts/x.sh]" "$(hm)"
  want "roster/R1: the roster line counts it" "^# touched-selftest roster: 1 (run: 1, CI-bound: 0, named: 0, unmeasured: 1)"
  trmut r1 -e '/^  selftest_arm   # STARM$/s/.*/  if [ -s "$WORK\/q.sel" ]; then selftest_arm; fi/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; rnl "$TRM" "$d" --base "$_stb"
    sfx "roster/R1 mutant: gated on q.sel again, the script's selftest is neither run nor named (the cell is RED)" MISSING "$(hm)"; }
  # R2 — hooks/pre-push is on the roster too
  stfx "$STREC" hooks/pre-push; rn "$d" --base "$_stb"
  want "roster/R2: a hooks/pre-push selftest gets its own core-selftest row" "^  OK    core-selftest *hooks/pre-push (both faces)"
  sfx "roster/R2: and its own call" "argv=[hooks/pre-push]" "$(hm)"
  trmut r2 -e 's/|hooks\/pre-push) ;;$/) ;;/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; rnl "$TRM" "$d" --base "$_stb"
    sfx "roster/R2 mutant: with hooks/pre-push off the roster its selftest is neither run nor named (the cell is RED)" MISSING "$(hm)"; }
  # R3 — a --selftest named only in a comment is not a roster entry
  stfx "$STREC" scripts/y.sh; printf '#!/bin/sh\n# supports --selftest\nexit 0\n' > "$d/scripts/y.sh"; commit_fx; rn "$d" --base "$_stb"
  want "roster/R3: a comment-only --selftest is not on the roster" "^# touched-selftest roster: 0 (run: 0, CI-bound: 0, named: 0, unmeasured: 0)"
  sfx "roster/R3: and no call is made" MISSING "$(hm)"
  trmut r3 -e '/# STCOMM$/s|sed [^ ]* |cat |'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R3 mutant: without the comment-strip the script is on the roster (the cell is RED)" "^# touched-selftest roster: 0 "; }
  # R4 — only the top level: scripts/sub/z.sh is off the roster
  stfx "$STREC" scripts/sub/z.sh; rn "$d" --base "$_stb"
  want "roster/R4: a nested script is not on the roster" "^# touched-selftest roster: 0 (run: 0"
  sfx "roster/R4: and no call is made" MISSING "$(hm)"
  trmut r4 -e '/^      \*\/\*\/\*) continue ;;   # STNEST$/d'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R4 mutant: with the nesting arm gone the nested script is on the roster (the cell is RED)" "^# touched-selftest roster: 0 "; }
  # R6 — verify.sh is named CI-bound with its job and never called; the other target is run
  stfx "$STREC" scripts/x.sh conformance/verify.sh; rn "$d" --base "$_stb"
  want "roster/R6: verify.sh is named CI-bound, with its job" "^# core-selftest: .*NOT ENFORCED locally.*conformance/verify\.sh.*H2 lane"
  sfx "roster/R6: only the other target is called" "argv=[scripts/x.sh]" "$(hm)"
  want "roster/R6: the roster line counts both" "^# touched-selftest roster: 2 (run: 1, CI-bound: 1, named: 0, unmeasured: 1)"
  trmut r6 -e '/# STDEFER$/d'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; rnl "$TRM" "$d" --base "$_stb"
    sfx "roster/R6 mutant: without the defer exclusion verify.sh is called too (the cell is RED)" differs "$([ "$(hm)" = 'argv=[scripts/x.sh]' ] && echo same || echo differs)"; }
  # R8 — an untracked capable script is a FAIL, not a call (face (b) grades HEAD)
  stfx "$STREC"; mkdir -p "$d/scripts"; printf '#!/bin/sh\ncase ${1-} in --selftest) exit 0 ;; esac\n' > "$d/scripts/u.sh"
  rn "$d" --base "$_stb"
  sfx "roster/R8: an uncommitted target is rc 1" 1 "$DVRC"
  want "roster/R8: the row says commit before the lane" "^  FAIL  core-selftest *scripts/u\.sh: uncommitted — commit before the lane"
  sfx "roster/R8: and the stub was never called" MISSING "$(hm)"
  trmut r8 -e '/# STCOMMIT$/s/if .*; then/if false; then/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R8 mutant: every listed path read as committed, the untracked script is called (the cell is RED)" "uncommitted — commit before the lane"; }
  # R11 — a capable path outside the argv charset is named CI-bound, never run, never a FAIL
  stfx "$STREC" 'conformance/odd name.sh'; rn "$d" --base "$_stb"
  sfx "roster/R11: rc 0" 0 "$DVRC"
  want "roster/R11: the path is named CI-bound" "^# core-selftest: .*conformance/odd name\.sh (name outside the argv charset; CI binds it)"
  sfx "roster/R11: and never called" MISSING "$(hm)"
  wantnot "roster/R11: and no FAIL" "^  FAIL  "
  trmut r11 -e '/# STCHARSET$/s/\*\[!A-Za-z0-9._\/-]\*/__never__/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; rnl "$TRM" "$d" --base "$_stb"
    sfx "roster/R11 mutant: without the charset arm the odd path reaches the hermetic call (the cell is RED)" differs "$([ "$(hm)" = MISSING ] && echo same || echo differs)"; }
  # R15 — an adopter tree (no kit marker): a touched scripts/ selftest is named, not run
  stfx "$STREC" scripts/x.sh; ( cd "$d" && git rm -q docs/ROADMAP-KIT.md ); commit_fx; rn "$d" --base "$_stb"
  sfx "roster/R15: rc 0" 0 "$DVRC"
  want "roster/R15: the script is named as kit-tree-only" "^# core-selftest: scripts/x\.sh — NOT run locally (kit tree only); your CI grades it only if you wire selftest-hermetic --touched"
  sfx "roster/R15: and not run" MISSING "$(hm)"
  want "roster/R15: the roster line counts it as named (N = run + CI-bound + named)" "^# touched-selftest roster: 1 (run: 0, CI-bound: 0, named: 1, unmeasured: 0)"
  trmut r15 -e '/# STOFF$/s/if .*; then/if false; then/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; rnl "$TRM" "$d" --base "$_stb"
    sfx "roster/R15 mutant: without the off_kit gate an adopter run calls the script (the cell is RED)" differs "$([ "$(hm)" = MISSING ] && echo same || echo differs)"; }
  # R15b — an adopter tree: a touched, capable conformance/*.sh that ci.yml does not derive is NAMED, never dropped
  stfx "$STREC" conformance/foo.sh; ( cd "$d" && git rm -q docs/ROADMAP-KIT.md ); commit_fx; rn "$d" --base "$_stb"
  sfx "roster/R15b: rc 0" 0 "$DVRC"
  want "roster/R15b: the script is named as not derived from the adopter's ci.yml" "^# core-selftest: conformance/foo\.sh — NOT run locally (not derived from your ci.yml)"
  sfx "roster/R15b: and not run" MISSING "$(hm)"
  want "roster/R15b: the roster line counts it as named" "^# touched-selftest roster: 1 (run: 0, CI-bound: 0, named: 1, unmeasured: 0)"
  trmut r15b -e '/# STNOTDER$/s/^.*$/        continue/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R15b mutant: the bare continue drops it silently (the cell is RED)" "not derived from your ci.yml"; }
}
# R5, R9, R10, R12, R19: what comes back from a call, and the cases that make no call.
selftest_tname() {
  # R5 — a stub that exits 0 and prints no TARGET line: neither run nor named
  stfx 'exit 0' scripts/x.sh; rn "$d" --base "$_stb"
  sfx "roster/R5: a clean exit with no TARGET line is rc 1" 1 "$DVRC"
  want "roster/R5: and the row says neither run nor named" "^  FAIL  core-selftest *scripts/x\.sh: neither run nor named"
  trmut r5 -e '/# STNAMED$/s/if .*; then/if false; then/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R5 mutant: without the reconciliation the silent run reads OK (the cell is RED)" "neither run nor named"; }
  # R10 — an EXCLUDED disposition is accepted
  stfx 'printf "  EXCLUDED: x.sh — fixture\n"' scripts/x.sh; rn "$d" --base "$_stb"
  sfx "roster/R10: an excluded target is rc 0" 0 "$DVRC"
  want "roster/R10: the row says it was excluded, not run" "^  OK    core-selftest *scripts/x\.sh (excluded with a reason: not run)"
  wantnot "roster/R10: and it is no FAIL" "neither run nor named"
  trmut r10 -e '/# STEXCL$/d'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    want "roster/R10 mutant: accepting TARGET alone fails the excluded target (the cell is RED)" "^  FAIL  core-selftest *scripts/x\.sh: neither run nor named"; }
  # R12 — a TARGET line indented (as a target's own output reaches the lane) does not count
  stfx 'echo "    TARGET: scripts/x.sh (both faces)"' scripts/x.sh; rn "$d" --base "$_stb"
  want "roster/R12: an indented TARGET line is not counted" "^  FAIL  core-selftest *scripts/x\.sh: neither run nor named"
  trmut r12 -e '/# STTARGET$/s/-qxF/-qF/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R12 mutant: an unanchored match counts the indented line (the cell is RED)" "neither run nor named"; }
  # R12b — an EXCLUDED line indented (a target's own output) does not count either
  stfx 'echo "    EXCLUDED: x.sh — r"' scripts/x.sh; rn "$d" --base "$_stb"
  want "roster/R12b: an indented EXCLUDED line is not counted" "^  FAIL  core-selftest *scripts/x\.sh: neither run nor named"
  trmut r12b -e '/# STEXCL$/s/== 1/> 0/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R12b mutant: index(...) > 0 counts the indented line (the cell is RED)" "neither run nor named"; }
  # R9 — the lock is not held: UNVERIFIED, and the stub is never called
  hlfx; chmod 777 "$_ld"; stfx "$STREC" scripts/x.sh; rnh "$_lh" "$d" --base "$_stb"
  sfx "roster/R9: an unheld lock is rc 1" 1 "$DVRC"
  want "roster/R9: the row is UNVERIFIED, naming the lock" "^  UNVERIFIED  core-selftest .*lock is not held"
  want "roster/R9: and the unrun target's path is listed" "^# core-selftest: scripts/x\.sh — NOT run (the heavy-arm lock is not held)"
  sfx "roster/R9: and the stub was never called" MISSING "$(hm)"
  want "roster/R9: the unrun target is counted as named" "^# touched-selftest roster: 1 (run: 0, CI-bound: 0, named: 1, unmeasured: 1)"
  trmut r9 -e '/# STLOCK$/s/hl_need core-selftest/true/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; DVOUT=$( cd "$d" && HOME=$_lh sh "$TRM" --base "$_stb" 2>&1 ) || :
    wantnot "roster/R9 mutant: with the lock never asked the unheld lock goes unnoticed (the cell is RED)" "^  UNVERIFIED  core-selftest "; }
  # R19 — a reasonless exclusions entry with no capable script: the lane's own validation still runs, and no call is made
  stfx "$STREC"; printf 'anything.sh\n' > "$d/conformance/hermetic-exclusions.txt"; commit_fx; rn "$d" --base "$_stb"
  sfx "roster/R19: a reasonless exclusions entry is rc 1" 1 "$DVRC"
  want "roster/R19: the FAIL names the entry" "^  FAIL  core-selftest .*hermetic-exclusions.txt entry 'anything.sh'"
  sfx "roster/R19: with no call made" MISSING "$(hm)"
  trmut r19 -e '/# STEXCL2$/d'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --base "$_stb"
    wantnot "roster/R19 mutant: with zero targets the exclusions file goes unvalidated (the cell is RED)" "hermetic-exclusions.txt entry"; }
}
# SWAS-840 (P1 of SWAS-858): the touched-selftest wall budget no longer selects. R13 to R18 are rewritten as B1 to B7 and B10 (B8, B9, B11 and B12, the readers half, are in selftest_touched_budget).
# Every admitted target RUNS: a prior time over the 300 s budget only adds a printed label. A hang is bounded by ST_CEIL (3600 s, a plain constant: a cell scales it in a lane COPY, never through an
# environment or argv knob) and reads UNVERIFIED, never OK and never named CI-bound. The time state is keyed by blob (R13b, R16).
# sttk <home> <blob>=<seconds>… — like stt, but one censored `@selftest-k` row per blob (the floor a kill leaves).
sttk() {
  _sth=$1; shift; : > "$WORK/trtab.rows"
  for _stk in "$@"; do printf '@selftest-k\t%s\t%s\t0\tlocal\t%s\n' "${_stk%%=*}" "${_stk#*=}" "$(date +%s)" >> "$WORK/trtab.rows"; done
  trtab "$_sth"
}
selftest_tbudget() {
  # B1 (rewrites R13) — a measured time over the budget RUNS: the three card targets are all called, each line carrying its prior time and the over-budget label
  stfx "$STREC" conformance/inception-done.sh scripts/preflight.sh conformance/incept-first-run-green.sh
  _b1=$(git -C "$d" rev-parse HEAD:conformance/inception-done.sh); _b2=$(git -C "$d" rev-parse HEAD:scripts/preflight.sh); _b3=$(git -C "$d" rev-parse HEAD:conformance/incept-first-run-green.sh)
  _h=$WORK/st-h1; stt "$_h" "$_b1=400" "$_b2=400" "$_b3=400"; strun "$_h" "$LANE"
  sfx "B1: rc 0" 0 "$DVRC"
  sfx "B1: all three targets were called (measured time, then path)" "argv=[conformance/incept-first-run-green.sh] argv=[conformance/inception-done.sh] argv=[scripts/preflight.sh]" "$(hm)"
  want "B1: inception-done says its prior time and that it runs over the budget" "^# core-selftest: conformance/inception-done\.sh — prior 400 s at [0-9a-f]\{12\} \[measured\]; over the 300 s budget: run anyway"
  want "B1: so does preflight" "^# core-selftest: scripts/preflight\.sh — prior 400 s at [0-9a-f]\{12\} \[measured\]; over the 300 s budget: run anyway"
  want "B1: so does incept-first-run-green" "^# core-selftest: conformance/incept-first-run-green\.sh — prior 400 s at [0-9a-f]\{12\} \[measured\]; over the 300 s budget: run anyway"
  wantnot "B1: and nothing is named CI-bound for the budget" "budget reached"
  want "B1: the roster counts all three as run" "^# touched-selftest roster: 3 (run: 3, CI-bound: 0, named: 0, unmeasured: 0)"
  want "B1: and the over-budget line counts them" "^# touched-selftest over budget: 3 run, 0 UNVERIFIED at the ceiling"
  want "B1: each clean run prints the seconds it took" "^# core-selftest: scripts/preflight\.sh took [0-9]* s \[measured, this run\]"
  # B2 — the budget and the runaway ceiling are printed, and the over-budget label is the only thing the budget does
  want "B2: the ceiling note prints the budget (not a cutoff) and the runaway ceiling" "^# ceiling: 120s/invocation (core-selftest: budget 300 s, printed, not a cutoff; runaway ceiling 3600 s per target"
  trmut b1 -e '/# STOVER$/s/.*/  if [ "$_st_ms" -eq 1 ] \&\& [ "$_st_s" -gt "$STBUD" ]; then note "core-selftest: $_st_p named, not run (over budget)"; return 0; fi   # STOVER/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_b1=400" "$_b2=400" "$_b3=400"; strun "$_h" "$TRM"
    sfx "B1 mutant: with the budget skip restored the 400 s targets are named, not run (the cell is RED)" MISSING "$(hm)"; }
  trmut b2 -e '/# STOVER$/d'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_b1=400" "$_b2=400" "$_b3=400"; strun "$_h" "$TRM"
    wantnot "B2 mutant: with the over-budget line dropped the label is gone (the cell is RED)" "over the 300 s budget"; }
  # R13b — a time row that is no plain number (a leading zero) is no time: the script is unmeasured (and runs)
  stfx "$STREC" scripts/x.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _h=$WORK/st-h13; stt "$_h" "$_bx=0400"; strun "$_h" "$LANE"
  sfx "roster/R13b: a 0400 row is unmeasured, so the script runs" "argv=[scripts/x.sh]" "$(hm)"
  want "roster/R13b: and the prior line says it is unmeasured" "^# core-selftest: scripts/x\.sh — unmeasured"
  trmut r13b -e '/^  st_okn "\$_st_m" || _st_m=""$/d'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_bx=0400"; strun "$_h" "$TRM"
    wantnot "roster/R13b mutant: without the number check 0400 reads as a measured time (the cell is RED)" "scripts/x\.sh — unmeasured"; }
  # B6 (rewrites R14) — a budget below the default is ignored, with one note, and a 280 s target carries no over-budget label (the budget only labels)
  rm -f "$d/herm.out"; stt "$_h" "$_bx=280"; strun "$_h" "$LANE" PREPUSH_SELFTEST_BUDGET_S=10
  want "B6: a lower budget is ignored loudly, and the default stands" "IGNORED: PREPUSH_SELFTEST_BUDGET_S may only RAISE (10 <= 300) — using 300"
  sfx "B6: one note" 1 "$(printf '%s\n' "$DVOUT" | grep -c 'IGNORED: PREPUSH_SELFTEST_BUDGET_S' || :)"
  sfx "B6: and the 280 s target ran" "argv=[scripts/x.sh]" "$(hm)"
  wantnot "B6: and it carries no over-budget label" "over the [0-9]* s budget"
  trmut b6 -e '/# STDIAL$/s/\$(raise_only .*)/${PREPUSH_SELFTEST_BUDGET_S:-300}/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_bx=280"; strun "$_h" "$TRM" PREPUSH_SELFTEST_BUDGET_S=10
    want "B6 mutant: accepting the lower budget labels the 280 s target over a 10 s budget (the cell is RED)" "over the 10 s budget: run anyway"; }
  # B6b (rewrites R14b) — a leading-zero budget is refused loudly too (the default applies): 0400 must not read as 400 here and as octal there
  rm -f "$d/herm.out"; stt "$_h" "$_bx=350"; strun "$_h" "$LANE" PREPUSH_SELFTEST_BUDGET_S=0400
  want "B6b: a leading-zero budget is ignored loudly" "IGNORED: PREPUSH_SELFTEST_BUDGET_S has a leading zero: \[0400\] — using 300"
  want "B6b: the default applies, so the 350 s target is labelled over the 300 s budget" "scripts/x\.sh — prior 350 s at [0-9a-f]\{12\} \[measured\]; over the 300 s budget: run anyway"
  sfx "B6b: and it ran" "argv=[scripts/x.sh]" "$(hm)"
  trmut b6b -e '/# STZERO$/d'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_bx=350"; strun "$_h" "$TRM" PREPUSH_SELFTEST_BUDGET_S=0400
    wantnot "B6b mutant: without the leading-zero arm 0400 is taken as 400 and the 350 s target carries no label (the cell is RED)" "over the [0-9]* s budget: run anyway"; }
  # R16 — a time recorded for another blob is ignored: an edited script is unmeasured again
  stfx "$STREC" scripts/x.sh; _ob=$(git -C "$d" rev-parse HEAD:scripts/x.sh); printf '# edit\n' >> "$d/scripts/x.sh"; commit_fx
  _h=$WORK/st-h16; stt "$_h" "$_ob=400" "scripts/x.sh=400"; strun "$_h" "$LANE"
  sfx "roster/R16: the stale time is ignored: the edited script runs" "argv=[scripts/x.sh]" "$(hm)"
  want "roster/R16: and it reads as unmeasured" "^# core-selftest: scripts/x\.sh — unmeasured"
  wantnot "roster/R16: and no stale time is shown" "prior 400 s"
  trmut r16 -e '/# STBLOB$/s|git rev-parse --verify -q "HEAD:$1"|printf %s "$1"|'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_ob=400" "scripts/x.sh=400"; strun "$_h" "$TRM"
    want "roster/R16 mutant: keyed by path alone the stale time applies (the cell is RED)" "^# core-selftest: scripts/x\.sh — prior 400 s"; }
  # B3 (rewrites R17) — a target killed at the runaway ceiling reads UNVERIFIED: never OK, never a FAIL, never named CI-bound, a censored time recorded against its blob, and the next target is still called
  # (a lane copy with ST_CEIL=2; the stub logs each call, then sleeps past it)
  _sc=$WORK/lane-st-ceil2.sh; sed 's/^ST_CEIL=3600$/ST_CEIL=2/' "$LANE" > "$_sc"
  sfx "B3: the ST_CEIL=2 lane copy differs" differs "$(cmp -s "$LANE" "$_sc" && echo same || echo differs)"
  stfx "$STSLEEP" scripts/x.sh scripts/y.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _by=$(git -C "$d" rev-parse HEAD:scripts/y.sh)
  _rc0=$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)
  _h=$WORK/st-h3; stt "$_h"; strun "$_h" "$_sc"; _tt=$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv
  sfx "B3: rc 1" 1 "$DVRC"
  want "B3: the killed target reads UNVERIFIED, naming the runaway ceiling and the seconds it ran" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling, not proven locally \[measured [0-9]* s\]"
  wantnot "B3: and it is no FAIL" "^  FAIL  "
  wantnot "B3: and it is not named CI-bound" "budget reached"
  sfx "B3: the verdict is UNVERIFIED" "PARITY-CORE: UNVERIFIED" "$(lastline | cut -c1-23)"
  sfx "B3: the second target is still called (a kill spends nothing)" "argv=[scripts/x.sh] argv=[scripts/y.sh]" "$(hm)"
  want "B3: the roster counts both as named" "^# touched-selftest roster: 2 (run: 0, CI-bound: 0, named: 2, unmeasured: 2)"
  want "B3: and the over-budget line counts them as UNVERIFIED at the ceiling" "^# touched-selftest over budget: 0 run, 2 UNVERIFIED at the ceiling"
  sfx "B3: a censored time of at least ceiling + 1 s is recorded against the killed blob" yes "$([ "$(awk -F'\t' -v b="$_bx" '$1 == "@selftest-k" && $2 == b { print $3 }' "$_tt" 2>/dev/null | sed -n 1p)" -ge 3 ] 2>/dev/null && echo yes || echo no)"
  TRSRC=$_sc trmut b3a -e '/# STUNV$/d'
  [ -z "$TRM" ] || { _h=$WORK/st-h3a; stt "$_h"; strun "$_h" "$TRM"
    sfx "B3 mutant: with the kill read as no UNVERIFIED the run is rc 0 (the cell is RED)" 0 "$DVRC"; }
  TRSRC=$_sc trmut b3b -e '/# STUNV$/s/   # STUNV$/; _st_lk=2   # STUNV/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; _h=$WORK/st-h3b; stt "$_h"; strun "$_h" "$TRM"
    sfx "B3 mutant: with a kill spending the run the second target is not called (the cell is RED)" "argv=[scripts/x.sh]" "$(hm)"; }
  TRSRC=$_sc trmut b3c -e '/# STREC$/d'
  [ -z "$TRM" ] || { _h=$WORK/st-h3c; stt "$_h"; strun "$_h" "$TRM"
    sfx "B3 mutant: skipping the record leaves no time against the blob (the cell is RED)" "" "$(awk -F'\t' -v b="$_bx" '$1 == "@selftest-k" && $2 == b { print $3 }' "$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null)"; }
  # B3m (rewrites R17d) — a MEASURED target killed at the ceiling reads the same way, never a FAIL whose remedy names PREPUSH_CEILING_S
  stfx "$STSLEEP" scripts/x.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _rc0=$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)
  _h=$WORK/st-h3m; stt "$_h" "$_bx=1"; strun "$_h" "$_sc"
  want "B3m: a measured target killed at the ceiling reads UNVERIFIED" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling"
  wantnot "B3m: and it is no FAIL" "^  FAIL  "
  sfx "B3m: the censored row is at least ceiling + 1 s" yes "$([ "$(awk -F'\t' -v b="$_bx" '$1 == "@selftest-k" && $2 == b { print $3 }' "$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null | sed -n 1p)" -ge 3 ] 2>/dev/null && echo yes || echo no)"
  TRSRC=$_sc trmut b3m -e '/# STCEIL$/s/if \[ "\$RUN_RC" -ne 0 \]/if [ "$_st_ms" -eq 0 ] \&\& [ "$RUN_RC" -ne 0 ]/'
  [ -z "$TRM" ] || { _h=$WORK/st-h3n; stt "$_h" "$_bx=1"; strun "$_h" "$TRM"
    want "B3m mutant: unmeasured-only handling turns the measured kill into a FAIL (the cell is RED)" "^  FAIL  core-selftest "; }
  # B3e (rewrites R17e) — the real harness traps TERM and INT and exits 130 itself: the kill is still read from the watchdog's own evidence, not from an exit status
  stfx "$STTRAP" scripts/x.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _rc0=$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)
  _h=$WORK/st-h3e; stt "$_h"; strun "$_h" "$_sc"
  want "B3e: a target that traps TERM and exits 130 reads UNVERIFIED at the ceiling" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling"
  wantnot "B3e: and it is no FAIL" "^  FAIL  "
  sfx "B3e: and a censored time is recorded against its blob" yes "$([ "$(awk -F'\t' -v b="$_bx" '$1 == "@selftest-k" && $2 == b { print $3 }' "$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null | sed -n 1p)" -ge 3 ] 2>/dev/null && echo yes || echo no)"
  TRSRC=$_sc trmut b3e -e '/# STCEIL$/s/if .*; then/if [ "$RUN_RC" -eq 143 ]; then/'
  [ -z "$TRM" ] || { _h=$WORK/st-h3f; stt "$_h"; strun "$_h" "$TRM"
    want "B3e mutant: keyed on rc 143 the exit-130 kill reads as a FAIL (the cell is RED)" "^  FAIL  core-selftest "; }
  # R17f — a target that forges the watchdog's marker at once (it can reach $TMPDIR/../ctl) and fails is still a FAIL, with no censored row: the run did not last the ceiling
  # (a 5 s lane copy: the forger waits for the watchdog's first one-second tick, so its wall time can read 2 s, which would equal a 2 s ceiling)
  _s5=$WORK/lane-st-ceil5.sh; sed 's/^ST_CEIL=3600$/ST_CEIL=5/' "$LANE" > "$_s5"
  sfx "roster/R17f: the 5 s lane copy differs" differs "$(cmp -s "$LANE" "$_s5" && echo same || echo differs)"
  stfx "$STFORGE" scripts/x.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _rc0=$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)
  _h=$WORK/st-h17h; stt "$_h"; strun "$_h" "$_s5"
  want "roster/R17f: a forged marker on a fast failure still reads FAIL" "^  FAIL  core-selftest "
  sfx "roster/R17f: and no censored row is recorded" "" "$(awk -F'\t' -v b="$_bx" '$1 == "@selftest-k" && $2 == b { print $3 }' "$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null)"
  TRSRC=$_s5 trmut r17f -e '/# STCEIL$/s/ \&\& \[ "\$RUN_S" -ge "\$_st_cl" \]//'
  [ -z "$TRM" ] || { _h=$WORK/st-h17i; stt "$_h"; strun "$_h" "$TRM"
    want "roster/R17f mutant: without the time conjunct the forged marker reads UNVERIFIED at the ceiling (the cell is RED)" "scripts/x\.sh: killed at the 5 s runaway ceiling"; }
  # B4 — a target already hung on these bytes (a censored row of at least ST_CEIL + 1 s for its blob) is named UNVERIFIED with no call; a lower floor (every row today's 300 s budget left) runs
  stfx "$STREC" scripts/x.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh)
  _h=$WORK/st-h4; sttk "$_h" "$_bx=3601"; strun "$_h" "$LANE"
  sfx "B4: a 3601 s floor is rc 1" 1 "$DVRC"
  want "B4: the target is named UNVERIFIED, killed at a floor on these bytes, with the cure" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at >=3601 s at [0-9a-f]\{12\} on these bytes \[measured floor\]; to get out: edit the target, or delete its @selftest-k row in times.tsv, or defer it by a reviewed PR (PREPUSH_NO_CACHE=1 runs it for this run only)"
  sfx "B4: and it was not called" MISSING "$(hm)"
  sfx "B4: the verdict is UNVERIFIED" "PARITY-CORE: UNVERIFIED" "$(lastline | cut -c1-23)"
  rm -f "$d/herm.out"; sttk "$_h" "$_bx=301"; strun "$_h" "$LANE"
  sfx "B4: a 301 s floor (today's budget kill) is printed as a floor and the target runs" "argv=[scripts/x.sh]" "$(hm)"
  want "B4: the prior line says it is a floor" "^# core-selftest: scripts/x\.sh — prior 301 s at [0-9a-f]\{12\} \[measured floor: killed\]"
  sfx "B4: and the run is rc 0" 0 "$DVRC"
  trmut b4a -e '/# STHUNG$/s/ && \[ "\$_st_s" -ge \$((ST_CEIL + 1)) \]//'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; sttk "$_h" "$_bx=301"; strun "$_h" "$TRM"
    sfx "B4 mutant: with the threshold compare dropped the 301 s floor skips the target (the cell is RED)" MISSING "$(hm)"; }
  trmut b4b -e '/# STHUNGUNV$/d'
  [ -z "$TRM" ] || { sttk "$_h" "$_bx=3601"; strun "$_h" "$TRM"
    sfx "B4 mutant: with the skip read as no UNVERIFIED the run is rc 0 (the cell is RED)" 0 "$DVRC"; }
  # B7 — the run log is fed: the hung unit is an UNV unit with its seconds, and RL3's completeness holds (one unit per verdict row)
  stfx "$STSLEEP" scripts/preflight.sh; _h=$WORK/st-h7; stt "$_h"; strun "$_h" "$_sc"
  _rl=$(rlf "$_h" "$d")/runs.log; _e=$(grep '^v1 end ' "$_rl" | sed -n 1p); _rows=$(printf '%s\n' "$DVOUT" | grep -Ec '^  (OK|FAIL|UNVERIFIED|SKIP|N/A) ' || :)
  sfx "B7: the hung unit is in the log as an UNV unit with its seconds" 1 "$(rlk "$_e" u | tr ',' '\n' | grep -c '^core-selftest:scripts/preflight\.sh:UNV:[0-9]*:' || :)"
  sfx "B7: and the units listed equal the verdict rows printed" "$_rows" "$(rlk "$_e" u | tr ',' '\n' | grep -c . || :)"
  TRSRC=$_sc trmut b7 -e '/# RLUNV$/d'
  [ -z "$TRM" ] || { _h2=$WORK/st-h7m; stt "$_h2"; strun "$_h2" "$TRM"
    _e2=$(grep '^v1 end ' "$(rlf "$_h2" "$d")/runs.log" | sed -n 1p)
    sfx "B7 mutant: with rl_u gone from the hang branch the unit is not logged (the cell is RED)" 0 "$(rlk "$_e2" u | tr ',' '\n' | grep -c '^core-selftest:scripts/preflight\.sh:UNV:' || :)"; }
  # B5 (rewrites F1 and R18) — no sum cut: a 280 s and a 50 s target are both called, the quicker first
  stfx "$STREC" scripts/a.sh scripts/b.sh; _ba=$(git -C "$d" rev-parse HEAD:scripts/a.sh); _bb=$(git -C "$d" rev-parse HEAD:scripts/b.sh)
  _h=$WORK/st-h18; stt "$_h" "$_ba=280" "$_bb=50"; strun "$_h" "$LANE"
  sfx "B5: both targets are called, the quicker first (the 280 s one is no longer cut by the 250 s left)" "argv=[scripts/b.sh] argv=[scripts/a.sh]" "$(hm)"
  wantnot "B5: and nothing is named against a budget left" "s left"
  trmut b5 -e '/# STSORT$/s/-k1,1n -k2,2n -k3,3/-k3,3/'
  [ -z "$TRM" ] || { rm -f "$d/herm.out"; stt "$_h" "$_ba=280" "$_bb=50"; strun "$_h" "$TRM"
    sfx "B5 mutant: admitted in listing order, a.sh runs first (the cell is RED)" "argv=[scripts/a.sh] argv=[scripts/b.sh]" "$(hm)"; }
  # B10 — the two new bounds are plain constants: exactly one literal line each, and neither reads the environment (the LD7 idiom: a grep over this file)
  sfx "B10: exactly one ST_CEIL=3600 line" 1 "$(grep -c -e '^ST_CEIL=3600$' "$LANE" || :)"
  sfx "B10: exactly one TR_CAP=600 line" 1 "$(grep -c -e '^TR_CAP=600$' "$LANE" || :)"
  sfx "B10: and neither line reads a PREPUSH_ name" 0 "$(grep -c -e '^ST_CEIL=.*PREPUSH_' -e '^TR_CAP=.*PREPUSH_' "$LANE" || :)"
  sfx "B10: ST_CEIL is assigned on exactly one line start (it counts every line-start assignment, at any indent; one inside a longer line is not seen)" 1 "$(grep -cE '^[[:space:]]*ST_CEIL=' "$LANE" || :)"
  sfx "B10: TR_CAP is assigned on exactly one line start (the same count)" 1 "$(grep -cE '^[[:space:]]*TR_CAP=' "$LANE" || :)"
  trmut b10b -e 's/^  TR_CAPE=\$TR_CAP; /  TR_CAP=$TR_CAPE; /'
  [ -z "$TRM" ] || sfx "B10 mutant: a second assignment of TR_CAP is counted (the cell is RED)" 2 "$(grep -cE '^[[:space:]]*TR_CAP=' "$TRM" || :)"
  trmut b10 -e 's/^TR_CAP=600$/TR_CAP=${PREPUSH_READERS_CAP_S:-600}/'
  [ -z "$TRM" ] || { sfx "B10 mutant: with an env read there is no literal TR_CAP=600 line (the cell is RED)" 0 "$(grep -c -e '^TR_CAP=600$' "$TRM" || :)"
    sfx "B10 mutant: and the env read is found" 1 "$(grep -c -e '^TR_CAP=.*PREPUSH_' "$TRM" || :)"; }
}

# M-3, the NEGATIVE half of "heavy is never run without its flag": both routes into the bucket (cf-* job placement AND a twin-table `heavy` row) yield no OK line and no executed-argv entry.
selftest_heavy_needs_flag() {
  mkci <<'YAML'
jobs:
  cf-x:
    steps:
      - run: sh conformance/alpha.sh
  j1:
    steps:
      - run: sh conformance/beta.sh
YAML
  mkchk alpha 'echo RAN-ALPHA'; mkchk beta 'echo RAN-BETA'
  tw beta heavy '' '' '' 60 'fixture: a heavy row for an otherwise core-live check'
  commit_fx; rn "$d" --verbose; sfx "heavy/flag: with no heavy arm the run is OK" 0 "$DVRC"
  want "heavy/flag: BOTH routes land in the heavy bucket"       "^# buckets: 0 core-live .* 2 heavy (not run without its flag)"
  wantnot "heavy/flag: no heavy invocation is reported OK"      "^  OK    heavy "
  wantnot "heavy/flag: the job-placement heavy check never ran" "^#   sh conformance/alpha\.sh"
  wantnot "heavy/flag: the heavy-ROW check never ran"           "^#   sh conformance/beta\.sh"
  sfx "heavy/flag: the executed-argv log is empty (the always-on secret-scan row aside)" "0" "$(printf '%s\n' "$DVOUT" | grep '^#   sh conformance/' | grep -vc 'secret-scan-wired' || :)"
}

# dash absent: UNVERIFIED, non-zero — the lane never substitutes the operator's shell and calls the result parity. The PATH here is the real one minus every directory holding a dash.
selftest_dash() {
  one_step; mkchk alpha 'exit 0'; commit_fx; _nd=$WORK/nodash; mkdir -p "$_nd"
  for _f in /bin/* /usr/bin/*
  do case ${_f##*/} in dash) ;; *) ln -s "$_f" "$_nd/${_f##*/}" 2>/dev/null || : ;; esac; done
  # --warranted on both runs: core-live is what an UNVERIFIED stop must keep from running under the operator's
  # shell; the default no longer runs it, so a default run would prove "nothing ran" vacuously.
  DVOUT=$( cd "$d" && PATH=$_nd sh "$LANE" --base HEAD --warranted 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "dash: absent dash is non-zero by default" 1 "$DVRC"
  want "dash: the shell face is UNVERIFIED with the install hint" "^# shell: UNVERIFIED (install dash: brew install dash)$"
  wantnot "dash: and nothing ran under the operator's shell" "^  OK  "
  DVOUT=$( cd "$d" && PATH=$_nd sh "$LANE" --base HEAD --warranted --best-effort 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "dash: --best-effort moves the rc" 0 "$DVRC"
  sfx "dash: but never the verdict line" "PARITY-CORE: UNVERIFIED (no dash: the lane never substitutes the operator's shell and calls the result parity)" "$(lastline)"
}

selftest_verdict() {
  one_step; mkchk alpha 'exit 0'; commit_fx; rn "$d"
  sfx "verdict: the LAST line is the verdict, and a default OK states its scope" "PARITY-CORE: OK (own surface — 1 CI-derived core-live check(s) not run; --warranted and CI run them)" "$(lastline)"
  wantnot "verdict: the lane never imitates verify.sh's RESULT: line" "RESULT:"
  # PREPUSH-CORE-DEFAULT: the failing/garbled invocations are CORE-LIVE checks, which only --warranted runs.
  mkchk alpha 'exit 3'; commit_fx; rn "$d"
  sfx "verdict: the default run does NOT run the failing core-live check (it is CI's and --warranted's)" "PARITY-CORE: OK (own surface — 1 CI-derived core-live check(s) not run; --warranted and CI run them)" "$(lastline)"
  rn "$d" --warranted; sfx "verdict: a failing invocation is FAIL" "PARITY-CORE: FAIL" "$(lastline)"
  sfx "verdict: and rc 1" 1 "$DVRC"; want "verdict: the failing rc is named" "rc=3 (expected 0)"
  # REGRESSION (first live run): a failing check whose output is not valid UTF-8 made BSD sed abort mid-report and the run died BEFORE its verdict. The verdict must always print.
  mkchk alpha 'dd if=/dev/urandom bs=4096 count=32 2>/dev/null; printf "bad \303\050 byte\n"; exit 4'
  commit_fx; rn "$d" --warranted
  sfx "verdict: a failing check with non-UTF-8 output still reaches its verdict" "PARITY-CORE: FAIL" "$(lastline)"
}

# SWAS-163 — a board-bound twin whose ONLY failure is NOT ENFORCED reads N/A on a hosted-tracker tree, and nowhere else.
# twfx <backend> <loop-state-extra-line-or-empty> <loop-state-rc> <backlog-presence-rc> [<beta-rc>] — a fixture whose twin
# checks are STUBS printing a chosen output and exiting a chosen rc (a vacuous stub could not red a mutant). Three twins:
# loop-state, backlog-presence (the lane's closed list) and beta (not on it). The fixture carries the real resolver.
twfx() {
  mkcin 'if sh conformance/loop-state.sh; then echo ok; fi' 'if sh conformance/backlog-presence.sh; then echo ok; fi' \
        'if sh conformance/beta.sh; then echo ok; fi' 'sh conformance/alpha.sh'
  cp "$KROOT/conformance/backlog-lib.sh" "$d/conformance/backlog-lib.sh"; printf 'Backlog backend: %s\n' "$1" > "$d/CLAUDE.md"
  [ "$1" != none ] || printf 'no backend field here\n' > "$d/CLAUDE.md"
  tw loop-state twin 'if sh conformance/loop-state.sh' 'loop-state.sh' 0 '' 'fixture'
  tw backlog-presence twin 'if sh conformance/backlog-presence.sh' 'backlog-presence.sh' 0 '' 'fixture'
  tw beta twin 'if sh conformance/beta.sh' 'beta.sh' 0 '' 'fixture'
  # like the real check: the scope line (and any $6 stray line) on STDOUT; every refusal reason and the epilogue on STDERR
  mkchk loop-state 'echo "loop-state: scope check N/A (no scope declared)"; '"${6:+echo \"$6\"; }"'{ '"${2:+echo \"$2\"; }"'echo "loop-state: row check NOT ENFORCED: backend x — fixture"; echo "loop-state: FAIL — h does not carry a valid Entry Declaration."; echo "  boilerplate"; } >&2; exit '"$3"
  mkchk backlog-presence 'echo "backlog-presence: NOT ENFORCED: backend x — fixture"; exit '"$4"
  mkchk beta "exit ${5:-0}"
  commit_fx; rn "$d" ${TWARG-}
}
selftest_twin_not_enforced() {
  _two="PARITY-CORE: OK (own surface — 1 CI-derived core-live check(s) not run; --warranted and CI run them; 2 board-bound twin(s) NOT ENFORCED locally — CI binds them)"
  twfx jira '' 1 3   # L1 jira, pure
  want "twin-na/L1: loop-state reads N/A, naming the backend" "^  N/A   loop-state  NOT ENFORCED only (backend 'jira') — CI binds the row leg"
  want "twin-na/L1: backlog-presence reads N/A" "^  N/A   backlog-presence  NOT ENFORCED only (backend 'jira')"
  wantnot "twin-na/L1: neither is a FAIL" "FAIL  twin"
  sfx "twin-na/L1: the default OK states the scope, exactly" "$_two" "$(lastline)"; sfx "twin-na/L1: rc 0" 0 "$DVRC"
  twfx jira 'loop-state: no parseable Kit-Class trailer' 1 3   # L2 combined refusal
  want "twin-na/L2: a combined refusal keeps loop-state FAIL" "FAIL  twin  *loop-state"
  want "twin-na/L2: the pure backlog-presence row still reads N/A" "^  N/A   backlog-presence"
  sfx "twin-na/L2: FAIL" "PARITY-CORE: FAIL" "$(lastline)"; sfx "twin-na/L2: rc 1" 1 "$DVRC"
  twfx jira '' 1 3 5   # L3 another row fails
  want "twin-na/L3: the unrelated twin FAILs" "FAIL  twin  *beta"; want "twin-na/L3: the N/A rows are still N/A" "^  N/A   loop-state"
  sfx "twin-na/L3: N/A masks nothing" "PARITY-CORE: FAIL" "$(lastline)"
  for _be in md frobnitz; do   # L4 md, L5 unrecognized
    twfx "$_be" '' 1 3
    want "twin-na/$_be: loop-state stays FAIL" "FAIL  twin  *loop-state"; want "twin-na/$_be: backlog-presence stays FAIL" "FAIL  twin  *backlog-presence"
    wantnot "twin-na/$_be: no N/A" "^  N/A"; sfx "twin-na/$_be: FAIL" "PARITY-CORE: FAIL" "$(lastline)"
  done
  twfx jira '' 0 0   # L6 rc 0 with a waiver-style NOT ENFORCED line: a plain pass
  want "twin-na/L6: rc 0 is a plain OK" "OK    twin  *loop-state"; wantnot "twin-na/L6: never N/A" "^  N/A"
  sfx "twin-na/L6: no twin clause in the verdict" "PARITY-CORE: OK (own surface — 1 CI-derived core-live check(s) not run; --warranted and CI run them)" "$(lastline)"
  twfx jira '' 1 2   # L7 backlog-presence NOT ENFORCED text with rc 2 (not its NOT ENFORCED partition)
  want "twin-na/L7: the wrong rc stays FAIL" "FAIL  twin  *backlog-presence"; sfx "twin-na/L7: one N/A only" "1" "$(printf '%s\n' "$DVOUT" | grep -c '^  N/A')"
  # the discriminant reads loop-state's STDERR alone (the hook's stream): a stdout-only stray line blocks nothing, a stderr reason does
  twfx jira '' 1 3 0 'loop-state: Kit-Class does not equal the derived class (stdout only)'
  want "twin-na/stdout-stray: a stdout-only stray line does not block N/A" "^  N/A   loop-state"
  twfx jira 'loop-state: Kit-Class does not equal the derived class (stderr)' 1 3
  want "twin-na/stderr-reason: the same line on STDERR keeps loop-state FAIL" "FAIL  twin  *loop-state"
  wantnot "twin-na/stderr-reason: and loop-state is not N/A" "^  N/A   loop-state"
  twfx none '' 1 3   # a tree declaring NO backend: undeclared is not hosted
  want "twin-na/no-field: loop-state stays FAIL" "FAIL  twin  *loop-state"; wantnot "twin-na/no-field: no N/A" "^  N/A"
  TWARG=--warranted; twfx jira '' 1 3; TWARG=   # the --warranted variant with no cache skips
  sfx "twin-na/warranted: the OK carries the twin clause alone" "PARITY-CORE: OK (2 board-bound twin(s) NOT ENFORCED locally — CI binds them)" "$(lastline)"
}

# SWAS-714: off the kit tree a twin row whose script is absent is CARVED (counted, never run); every other defect, and the
# same absent script ON the kit tree, stays MALFORMED. cvfx <off|kit> — two absent-script exclude rows that ci.yml never
# names; `off` drops the kit marker. cvrow <name> <kind> — append one exclude-shaped row for conformance/<name>.sh.
cvfx() {
  one_step; cvrow ghost1 exclude; cvrow ghost2 exclude
  [ "$1" != off ] || rm -f "$d/docs/ROADMAP-KIT.md"
  commit_fx
}
cvrow() { tw "$1" "$2" "sh conformance/$1.sh" "$1.sh" '' '' 'fixture: kit-only'; }
# cvoff — a fresh off-kit one-step fixture (the caller adds rows, then commit_fx).
cvoff() { one_step; rm -f "$d/docs/ROADMAP-KIT.md"; }
# cvmut <dir> <mutant-lane> — the MUTANT lane run on a cell's fixture; DVOUT/DVRC as rn.
cvmut() { DVOUT=$( cd "$1" && sh "$2" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?; }
selftest_twin_carve() {
  # C1 — adopter shape: carved, noted once with the count, nothing run, no UNVERIFIED
  cvfx off; _c1=$d; rn "$d" --verbose
  sfx "carve/C1: the run is rc 0" 0 "$DVRC"
  want "carve/C1: the note counts the two carved rows" '^# twin rows carved: 2 (their scripts are kit-only and not in this tree)$'
  wantnot "carve/C1: the table is not malformed" "TWIN-TABLE MALFORMED"
  wantnot "carve/C1: and the verdict is not UNVERIFIED" "^PARITY-CORE: UNVERIFIED"
  wantnot "carve/C1: neither carved basename appears anywhere in the run output (argv log, buckets)" 'ghost[12]'
  # the work files are gone after a run, so read them from a direct call of the same two functions
  _w=$( _cw=""; cd "$_c1" && _cw=$(mktemp -d "${TMPDIR:-/tmp}/cv-XXXXXX") && WORK=$_cw && find conformance -maxdepth 1 -type f -name '*.sh' > "$WORK/scripts" &&
        read_twins "$CI_DEFAULT" && twin_exec_check && cat "$WORK/twins.ok" "$WORK/tg.yml" && printf 'carved=%s\n' "$(wc -l < "$WORK/twins.carved" | tr -d ' ')"
        [ -z "$_cw" ] || rm -rf "$_cw" )
  DVOUT=$_w
  want "carve/C1: the direct read carved two rows" '^carved=2$'
  wantnot "carve/C1: and neither reached twins.ok or the twin-exec synthetic workflow" 'ghost[12]'
  # C2 — kit shape: today's red, kept
  cvfx kit; _c2=$d; rn "$d"
  want "carve/C2: on the kit tree an absent script is MALFORMED" "TWIN-TABLE MALFORMED: .*not a regular file under the repo root: conformance/ghost1\\.sh"
  want "carve/C2: and the verdict is UNVERIFIED" '^PARITY-CORE: UNVERIFIED (the twin table is malformed'
  wantnot "carve/C2: nothing is carved on the kit tree" "twin rows carved"
  # C3 — off-kit, any other defect stays malformed (a 6-field row; a basename outside the charset)
  cvoff; _c3=$d
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' ghost1 exclude 'sh conformance/ghost1.sh' '' '' 'six fields' >> "$d/conformance/prepush-twins.tsv"
  tw Ghost_2 exclude 'sh conformance/ghost2.sh' '' '' '' 'bad basename'; commit_fx; rn "$d"
  want "carve/C3: a 6-field row off-kit is MALFORMED" "TWIN-TABLE MALFORMED: .*expected 7 tab-separated fields, got 6"
  want "carve/C3: a bad basename off-kit is MALFORMED" "TWIN-TABLE MALFORMED: .*basename outside"
  want "carve/C3: and the verdict is UNVERIFIED" '^PARITY-CORE: UNVERIFIED (the twin table is malformed'
  # C4 — carve ONLY the reason: an absent script AND an unknown kind is malformed, not carved
  cvoff; _c4=$d; cvrow ghost1 bogus; commit_fx; rn "$d"
  want "carve/C4: an absent script with an unknown kind is MALFORMED" "TWIN-TABLE MALFORMED: .*unknown kind: bogus"
  wantnot "carve/C4: and it is not carved" "twin rows carved"
  # C5 — a symlink is not absent: it stays MALFORMED
  cvoff; _c5=$d; cvrow ghost1 exclude; commit_fx; ln -s alpha.sh "$d/conformance/ghost1.sh"; rn "$d"   # uncommitted: HEAD does not track it
  want "carve/C5: a symlinked script off-kit is MALFORMED" "TWIN-TABLE MALFORMED: .*not a regular file under the repo root: conformance/ghost1\\.sh"
  wantnot "carve/C5: and it is not carved" "twin rows carved"
  # C6 — CI still runs it: an absent script this tree own ci.yml names stays MALFORMED
  mkci1 'sh conformance/ghost1.sh'; rm -f "$d/docs/ROADMAP-KIT.md"; _c6=$d; cvrow ghost1 exclude; commit_fx; rn "$d"
  want "carve/C6: an absent script the CI file names is MALFORMED" "TWIN-TABLE MALFORMED: .*not a regular file under the repo root: conformance/ghost1\\.sh"
  wantnot "carve/C6: and it is not carved" "twin rows carved"
  # C7 — committed in HEAD, then gone from the working tree (sparse checkout, skip-worktree, unstaged delete): NOT absent
  cvoff; _c7=$d; mkchk ghost1 'exit 0'; cvrow ghost1 exclude; commit_fx; rm -f "$d/conformance/ghost1.sh"; rn "$d"
  want "carve/C7: a script HEAD tracks but the working tree lacks is MALFORMED" "TWIN-TABLE MALFORMED: .*not a regular file under the repo root: conformance/ghost1\\.sh"
  wantnot "carve/C7: and it is not carved" "twin rows carved"
  # Each mutant must red its own cell AND still print the exact carved count, so a broken awk cannot pass as no-MALFORMED.
  # M1 — the marker test dropped: the carve applies on the kit tree too (C2 reds)
  trmut m1 -e 's/^off_kit() {.*/off_kit() { true; }/'
  [ -z "$TRM" ] || { cvmut "$_c2" "$TRM"
    wantnot "carve/M1 mutant: with the marker test dropped the kit tree no longer reads MALFORMED (C2 is RED)" "TWIN-TABLE MALFORMED"
    want "carve/M1 mutant: and it carved both rows" '^# twin rows carved: 2 (their'; }
  # M2 — the carve widened to every reason: C3's malformed rows are carved away (C3 reds)
  trmut m2 -e 's/^  if (e != "") print FNR ": " e > ERR; else if (cv) print/  if (e != "" \&\& !OFFKIT) print FNR ": " e > ERR; else if (cv || e != "") print/'
  [ -z "$TRM" ] || { cvmut "$_c3" "$TRM"
    wantnot "carve/M2 mutant: with the carve widened the malformed rows vanish (C3 is RED)" "TWIN-TABLE MALFORMED"
    want "carve/M2 mutant: and it carved both malformed rows" '^# twin rows carved: 2 (their'; }
  # M3 — the carve returns before the later tests (C4 reds)
  trmut m3 -e 's/^  if (e == "" && miss) {/  if (miss) {/' \
           -e 's/^  if (e != "") print FNR ": " e > ERR; else if (cv) print \$0 > CARVED;/  if (cv) print $0 > CARVED; else if (e != "") print FNR ": " e > ERR;/'
  [ -z "$TRM" ] || { cvmut "$_c4" "$TRM"
    wantnot "carve/M3 mutant: carving before the later tests lets the unknown kind through (C4 is RED)" "TWIN-TABLE MALFORMED"
    want "carve/M3 mutant: and it carved the row" '^# twin rows carved: 1 (their'; }
  # M4 — absence weakened to "not a regular file": the symlink is carved (C5 reds)
  trmut m4 -e 's/in ENT) &&/in SCR) \&\&/'
  [ -z "$TRM" ] || { cvmut "$_c5" "$TRM"
    wantnot "carve/M4 mutant: a symlink read as absent is carved (C5 is RED)" "TWIN-TABLE MALFORMED"
    want "carve/M4 mutant: and it carved the row" '^# twin rows carved: 1 (their'; }
  # M5 — the CI-mention test dropped: a script CI still names is carved (C6 reds)
  trmut m5 -e 's/ \&\& !index(CIT, "conformance\/" b "\.sh")//'
  [ -z "$TRM" ] || { cvmut "$_c6" "$TRM"
    wantnot "carve/M5 mutant: a script the CI file names is carved (C6 is RED)" "TWIN-TABLE MALFORMED"
    want "carve/M5 mutant: and it carved the row" '^# twin rows carved: 1 (their'; }
  # M6 — the HEAD test dropped: a script HEAD tracks but the working tree lacks is carved (C7 reds)
  trmut m6 -e 's/ && !(("conformance\/" b "\.sh") in HD)//'
  [ -z "$TRM" ] || { cvmut "$_c7" "$TRM"
    wantnot "carve/M6 mutant: a HEAD-tracked script missing from the tree is carved (C7 is RED)" "TWIN-TABLE MALFORMED"
    want "carve/M6 mutant: and it carved the row" '^# twin rows carved: 1 (their'; }
}

selftest_shim() {
  one_step; mkchk alpha '{ command -v sh; ls "$(dirname "$(command -v sh)")"; ls -ld "$(dirname "$(command -v sh)")"; cat "$(command -v sh)"; } > "$PWD/shim.out" 2>&1'
  commit_fx; rn "$d" --warranted; want "shim: the report header names the resolved dash" "^# shell: dash /"   # --warranted: the probe is a core-live check
  _wr=$(workroot); DVOUT=$(cat "$d/shim.out" 2>/dev/null || echo MISSING)
  sfx "shim: a child's \`sh\` resolves to the shim under the work root" "$_wr/shim/sh" "$(sed -n 1p "$d/shim.out")"
  sfx "shim: the shim dir holds EXACTLY sh" "sh" "$(sed -n 2p "$d/shim.out")"
  want "shim: the shim dir is 0700" "^drwx------"; want "shim: and its sh execs the resolved dash" "^exec .*dash "
}

# SERIAL at J = 1, BOUNDED at J >= 2, by OBSERVATION, not by grep: two invocations that log their own start and end must not interleave at J = 1. (M-1: run_timed backgrounds the invocation itself AND a watchdog, then `wait`s — the `wait` is the serialization, so only an observation can prove it.)
selftest_bounded_fanout() {
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  mkchk alpha 'echo a-start >> "$PWD/ser.out"; sleep 2; echo a-end >> "$PWD/ser.out"'
  mkchk beta  'echo b-start >> "$PWD/ser.out"; sleep 1; echo b-end >> "$PWD/ser.out"'
  commit_fx; rn "$d" --warranted   # the two probes are core-live checks: only --warranted runs them; rn is LANE_J1
  sfx "no-fanout: at J = 1 the invocations never overlap" "a-start a-end b-start b-end" "$(tr '\n' ' ' < "$d/ser.out" | sed 's/ $//')"
  # PL1 (SWAS-868): four probes each create live.<n>, hold 3 s, append the count of live.* to cnt, hold again, then remove the marker. 2 <= max(cnt) <= J on LANE_J2, and 1 on LANE_J1.
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh' 'sh conformance/gamma.sh'
  for _n in alpha beta gamma; do mkchk "$_n" 'touch "$PWD/live.$$"; sleep 2; ls "$PWD" | grep -c "^live\." >> "$PWD/cnt"; sleep 2; rm -f "$PWD/live.$$"'; done
  commit_fx
  pl_mx() { sort -n "$d/cnt" 2>/dev/null | tail -n 1; }
  rnl "$LANE_J1" "$d" --warranted
  sfx "PL1: at J = 1 the three probes never overlap (the highest live count is 1)" 1 "$(pl_mx)"
  rm -f "$d/cnt"; rnl "$LANE_J2" "$d" --warranted
  want "PL1: the J = 2 lane says so" "^# pool: J=2 "
  sfx "PL1: at J = 2 the probes overlap and never exceed J (2 <= the highest live count <= 2)" ok "$([ "$(pl_mx)" -ge 2 ] 2>/dev/null && [ "$(pl_mx)" -le 2 ] 2>/dev/null && echo ok || echo "highest=$(pl_mx)")"
  TRSRC=$LANE_J2 trmut pl1a -e '/# PLJCLAMP$/s/POOL_C - 1/POOL_C + 1/'
  [ -z "$TRM" ] || { rm -f "$d/cnt"; rnl "$TRM" "$d" --warranted
    sfx "PL1 mutant: with the cores clamp + 1 the lane runs more than J at once (the cell is RED)" yes "$([ "$(pl_mx)" -gt 2 ] 2>/dev/null && echo yes || echo no)"; }
  TRSRC=$LANE_J2 trmut pl1b -e '/# PLGUARD$/s/-lt "\$POOL_J"/-le "$POOL_J"/'
  [ -z "$TRM" ] || { rm -f "$d/cnt"; rnl "$TRM" "$d" --warranted
    sfx "PL1 mutant: with the dispatch guard -lt read as -le the lane runs J + 1 at once (the cell is RED)" yes "$([ "$(pl_mx)" -gt 2 ] 2>/dev/null && echo yes || echo no)"; }
}

selftest_no_write() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  _s1=$( cd "$d" && git status --porcelain && git for-each-ref refs/ ); rn "$d"
  _s2=$( cd "$d" && git status --porcelain && git for-each-ref refs/ )
  sfx "no-write: git status and refs/ are byte-identical across a default run" "$_s1" "$_s2"
  # PREPUSH-CORE-DEFAULT: the default no longer executes core-live, so the writer-capable path is --warranted.
  # The --warranted half runs with the CACHE ON (a temp HOME): the one place the lane records state, which
  # must land under HOME and nowhere in the repo.
  _h=$(mktemp -d "${TMPDIR:-/tmp}/fx-home-XXXXXX"); cr
  _s3=$( cd "$d" && git status --porcelain && git for-each-ref refs/ )
  sfx "no-write: and across a --warranted run with the cache ON (core-live executed, a pass recorded)" "$_s1" "$_s3"
  _pf=$(ls "$_h"/.local/state/sparkwright/prepush/*/passed 2>/dev/null | sed -n 1p)
  sfx "no-write: the record landed under the temp HOME, not in the repo" yes "$([ -n "$_pf" ] && [ -f "$_pf" ] && echo yes || echo no)"
  # SWAS-568 (RL11): the run log and the report write nothing in the repo either
  _rf=$(ls "$_h"/.local/state/sparkwright/prepush/*/runs.log 2>/dev/null | sed -n 1p)
  sfx "no-write: the run log landed under the temp HOME too" yes "$([ -n "$_rf" ] && [ -f "$_rf" ] && echo yes || echo no)"
  DVOUT=$( cd "$d" && HOME=$_h sh "$LANE" --log-report --base HEAD 2>&1 ) || :
  _s4=$( cd "$d" && git status --porcelain && git for-each-ref refs/ )
  sfx "no-write: and across a --log-report run (status and refs byte-identical)" "$_s1" "$_s4"
}

selftest_no_exec_of_context() {
  mkcin 'sh conformance/alpha.sh; echo NEEDLE-NOT-RUN' 'sh conformance/beta.sh --ok'
  mkchk alpha 'exit 0'; mkchk beta 'exit 0'; commit_fx; rn "$d" --warranted --verbose   # core-live runs only under --warranted
  want "no-exec: --verbose echoes the executed-argv log" "^#   sh conformance/beta\.sh --ok$"; wantnot "no-exec: no token from a context line is ever executed" "NEEDLE-NOT-RUN"
  sfx "no-exec: exactly one invocation ran (the always-on secret-scan row aside)" "1" "$(printf '%s\n' "$DVOUT" | grep '^#   sh conformance/' | grep -vc 'secret-scan-wired' || :)"
  # M2: a QUOTED operand reaches the check UNQUOTED — shell-equivalent argv, not literal quote bytes.
  mkcin "sh conformance/beta.sh '--flag'"; commit_fx; rn "$d" --warranted --verbose
  want "no-exec/argv: a quoted operand is executed without its quotes" "^#   sh conformance/beta\.sh --flag$"
  # M-6: the log's honesty does not depend on today's charset. qtok is the quoting the log applies.
  sfx "no-exec/log: a closed-charset token is logged bare"        "--ok" "$(qtok '--ok')"
  sfx "no-exec/log: a token with a SPACE is logged quoted"        "'a b'" "$(qtok 'a b')"
  sfx "no-exec/log: an embedded quote cannot close the quoting"   "'a'\\''b'" "$(qtok "a'b")"
}

# PREPUSH-CORE-DEFAULT (design §8): the CI-derived core-live set is ABSENT from the default run and PRESENT
# under --warranted. The probe is a marker file the check writes: absence is observed, not inferred from a
# report line. Reverting run_core to run core-live unconditionally reds the default half; making --warranted
# skip it reds the second half.
selftest_core_live_default() {
  one_step; mkchk alpha 'echo RAN-ALPHA > "$PWD/live.out"'; commit_fx
  rn "$d" --verbose; sfx "core-live/default: rc 0" 0 "$DVRC"
  want "core-live/default: the NOT-run note says how many were left to --warranted and CI" "^# core-live: 1 CI-derived checks NOT run by default"
  want "core-live/default: the bucket derivation is unchanged (it is still counted as core-live)" "^# buckets: 1 core-live "
  wantnot "core-live/default: no core-live invocation is reported OK" "^  OK    core-live "
  wantnot "core-live/default: and the check is not in the executed-argv log" "^#   sh conformance/alpha\.sh$"
  sfx "core-live/default: the check never ran (its marker file is absent)" no "$([ -e "$d/live.out" ] && echo yes || echo no)"
  rn "$d" --warranted --verbose; sfx "core-live/warranted: rc 0" 0 "$DVRC"
  want "core-live/warranted: the SAME check runs and is reported OK" "^  OK    core-live *alpha "
  wantnot "core-live/warranted: and the NOT-run note is absent" "^# core-live: .* NOT run"
  sfx "core-live/warranted: its marker file exists" yes "$([ -e "$d/live.out" ] && echo yes || echo no)"
}

# PREPUSH-CORE-DEFAULT (design §8): the default's shellcheck sees ONLY the listing's shell files. A dirty file
# COMMITTED before the base is in collect()'s scope but not in the listing; a dirty file created after is both.
# Needs a real shellcheck: without one the leg says SKIP out loud (never a vacuous pass).
selftest_shellcheck_scoped() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "SKIP: shellcheck-scoped: shellcheck is not installed — the scoped-lint legs were NOT exercised here (CI exercises them)"; return 0
  fi
  if [ -z "$KROOT" ] || [ ! -f "$KROOT/conformance/shellcheck.sh" ]; then
    echo "SKIP: shellcheck-scoped: conformance/shellcheck.sh is not in this tree — legs NOT exercised"; return 0
  fi
  one_step; cp "$KROOT/conformance/shellcheck.sh" "$d/conformance/"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$d/conformance/dirtyu.sh"   # SC3014, committed => UNLISTED
  commit_fx
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$d/conformance/dirtyl.sh"   # SC3014, untracked => LISTED
  rn "$d"
  sfx "shellcheck-scoped: a LISTED dirty shell file FAILS the default run (rc 1)" 1 "$DVRC"
  want "shellcheck-scoped: the failing row is the scoped core-shellcheck arm" "^  FAIL  core-shellcheck "
  want "shellcheck-scoped: shellcheck's own finding names the listed file" "^        | In conformance/dirtyl\.sh line"
  wantnot "shellcheck-scoped: and never the unlisted dirty file" "dirtyu\.sh"
  rm -f "$d/conformance/dirtyl.sh"
  printf '#!/bin/sh\nx="hello"\nprintf "%%s\\n" "$x"\n' > "$d/conformance/cleanl.sh"                   # untracked => LISTED, clean
  rn "$d"
  sfx "shellcheck-scoped: an UNLISTED dirty file does not fail the default run (rc 0)" 0 "$DVRC"
  want "shellcheck-scoped: the scoped arm ran and is OK" "^  OK    core-shellcheck "
  rm -f "$d/conformance/cleanl.sh"; : > "$d/notes.txt"
  rn "$d"
  want "shellcheck-scoped: a listing with no shell file skips the arm, naming why" "^# skipped: scoped shellcheck — the listing names no shell file"
  wantnot "shellcheck-scoped: and no core-shellcheck row is reported" "core-shellcheck"
}

# SWAS-175: the default run scans <merge-base>..HEAD through `secret-scan-wired.sh --range`. The fixture carries
# the REAL checker and a STUB gitleaks (GITLEAKS_BIN) that records its argv, so the range reaches the scanner
# exactly as CI hands it over. A finding is a FAIL naming the arm; the checker's rc 2 (gitleaks absent) renders
# UNVERIFIED and BLOCKS (verdict UNVERIFIED, rc 1) -- never a skip, never an OK.
selftest_secretscan_scoped() {
  if [ -z "$KROOT" ] || [ ! -f "$KROOT/conformance/secret-scan-wired.sh" ]; then
    echo "SKIP: secretscan-scoped: conformance/secret-scan-wired.sh is not in this tree — legs NOT exercised"; return 0
  fi
  one_step; cp "$KROOT/conformance/secret-scan-wired.sh" "$d/conformance/"; commit_fx
  _gb=$WORK/gl-stub; _ga=$WORK/gl-argv; _hd=$(git -C "$d" rev-parse HEAD)
  stub_gl() { printf '#!/bin/sh\nif [ "$1" = version ]; then echo 8.24.3; exit 0; fi\nprintf "%%s\\n" "$@" > %s\nexit %s\n' "$_ga" "$1" > "$_gb"; chmod +x "$_gb"; rm -f "$_ga"; }
  stub_gl 0; env_rn "$d" GITLEAKS_BIN "$_gb"
  sfx "secretscan-scoped: a clean range scan is OK (rc 0)" 0 "$DVRC"
  want "secretscan-scoped: the core-secretscan row is OK" "^  OK    core-secretscan "
  sfx "secretscan-scoped: the scanner got exactly --log-opts=<merge-base>..HEAD" "--log-opts=$_hd..HEAD" "$(grep -e '^--log-opts=' "$_ga" || :)"
  stub_gl 1; env_rn "$d" GITLEAKS_BIN "$_gb"
  sfx "secretscan-scoped: a finding FAILS the default run (rc 1)" 1 "$DVRC"
  want "secretscan-scoped: the failing row is core-secretscan" "^  FAIL  core-secretscan "
  mkchk secret-scan-wired 'exit 2'; commit_fx; rn "$d"
  sfx "secretscan-scoped: gitleaks absent (checker rc 2) BLOCKS the default run (rc 1)" 1 "$DVRC"
  want "secretscan-scoped: the row is UNVERIFIED, not FAIL and not OK" "^  UNVERIFIED  core-secretscan "
  wantnot "secretscan-scoped: and never an OK row" "^  OK    core-secretscan "
  sfx "secretscan-scoped: the verdict is UNVERIFIED naming the cause" "PARITY-CORE: UNVERIFIED (secret-scan did not run: gitleaks absent or the scan could not run (UNVERIFIED; install gitleaks, CI runs the pinned scan))" "$(lastline)"
  rm -f "$d/conformance/secret-scan-wired.sh"; commit_fx; rn "$d"
  sfx "secretscan-scoped: an ABSENT checker BLOCKS too (rc 1), never a skip note" 1 "$DVRC"
  want "secretscan-scoped: the absent-checker row is UNVERIFIED" "^  UNVERIFIED  core-secretscan .*not a regular file"
}

# SWAS-236: the default run lints the touched files that are ALSO on the sast-parse list through the real
# shell-parse-lint.sh (CI's SAST-parse net, caught before the push). The fixture carries the REAL lint at
# <fixture>/conformance/ (it derives its ROOT from its own directory) and its own list. The keywords are
# assembled from pieces so this file never carries a one-line case of its own.
selftest_parselint_scoped() {
  if [ -z "$KROOT" ] || [ ! -f "$KROOT/conformance/shell-parse-lint.sh" ]; then
    echo "SKIP: parselint-scoped: conformance/shell-parse-lint.sh is not in this tree — legs NOT exercised"; return 0
  fi
  one_step; cp "$KROOT/conformance/shell-parse-lint.sh" "$d/conformance/"; mkdir -p "$d/scripts"
  _kc=ca; _ks=se; _ke=es; _kx=ac
  _one() { printf '#!/bin/sh\n%s%s "$1" in a) echo a ;; *) echo b ;; %s%s\n' "$_kc" "$_ks" "$_ke" "$_kx" > "$d/$1"; }
  printf '%s\n' "scripts/planted.sh" > "$d/conformance/sast-parse-files.txt"; commit_fx
  _one scripts/planted.sh; rn "$d"
  sfx "parselint-scoped: a LISTED touched file with a one-line case FAILS the default run (rc 1)" 1 "$DVRC"
  want "parselint-scoped: the failing row is core-parselint" "^  FAIL  core-parselint "
  want "parselint-scoped: the lint names the file:line" "scripts/planted\.sh:2: a one-line case statement"
  want "parselint-scoped: and the cure is printed" "put esac (and each arm) on its own line"
  printf '#!/bin/sh\n%s%s "$1" in\n  a) echo a ;;\n  *) echo b ;;\n%s%s\n' "$_kc" "$_ks" "$_ke" "$_kx" > "$d/scripts/planted.sh"; rn "$d"
  sfx "parselint-scoped: the same file split across lines passes (rc 0)" 0 "$DVRC"
  want "parselint-scoped: the row is OK" "^  OK    core-parselint "
  rm -f "$d/scripts/planted.sh"; _one scripts/unlisted.sh; rn "$d"
  sfx "parselint-scoped: a one-line case in an UNLISTED file does not fail (rc 0)" 0 "$DVRC"
  want "parselint-scoped: scope: the skip note names why" "^# skipped: SAST-parse lint — the listing names no conformance/sast-parse-files\.txt file"
  wantnot "parselint-scoped: scope: and no core-parselint row" "core-parselint"
  rm -f "$d/scripts/unlisted.sh"; : > "$d/notes.txt"; rn "$d"
  want "parselint-scoped: nothing touched: the skip note" "^# skipped: SAST-parse lint"
  wantnot "parselint-scoped: nothing touched: no core-parselint row" "core-parselint"
  rm -f "$d/notes.txt"
  # fail-open guard: a CRLF entry, a trailing-blank entry and an indented '#' line must each still lint the file
  printf 'scripts/planted.sh\r\n   # an indented comment\n\n' > "$d/conformance/sast-parse-files.txt"; commit_fx
  _one scripts/planted.sh; rn "$d"
  want "parselint-scoped: a CRLF list entry still FAILS the file" "^  FAIL  core-parselint "
  wantnot "parselint-scoped: and never skips as N/A" "skipped: SAST-parse lint"
  printf 'scripts/planted.sh  \t\n\n' > "$d/conformance/sast-parse-files.txt"; rn "$d"
  want "parselint-scoped: a trailing-blank list entry still FAILS the file" "^  FAIL  core-parselint "
  wantnot "parselint-scoped: and never skips as N/A (blanks)" "skipped: SAST-parse lint"
  printf './scripts/planted.sh\n' > "$d/conformance/sast-parse-files.txt"; rn "$d"
  want "parselint-scoped: a ./-prefixed list entry still FAILS the file" "^  FAIL  core-parselint "
  printf '  \tscripts/planted.sh\n' > "$d/conformance/sast-parse-files.txt"; rn "$d"
  want "parselint-scoped: a leading-blank list entry still FAILS the file" "^  FAIL  core-parselint "
}

# --- PREPUSH-CORE-DEFAULT: the --warranted tree-key cache -------------------------------------------
# cfx — a fixture whose core-live check `alpha` appends a line to $_m/count (OUTSIDE the repo, so the probe
# itself never dirties the tree) and a private HOME $_h. cr — a --warranted run with the cache ON
# (PREPUSH_NO_CACHE=${CRNC:-0}) against that HOME. nruns — how many times the check actually ran.
cfx() {
  one_step; _m=$(mktemp -d "${TMPDIR:-/tmp}/fx-mk-XXXXXX"); _h=$(mktemp -d "${TMPDIR:-/tmp}/fx-home-XXXXXX")
  mkchk alpha "echo ran >> $_m/count; ${1:-exit 0}"; commit_fx
}
cr() { DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=${CRNC:-0} sh "$LANE" --base HEAD --warranted 2>&1 ) && DVRC=0 || DVRC=$?; }
nruns() { if [ -f "$_m/count" ]; then wc -l < "$_m/count" | tr -d ' '; else echo 0; fi; }

# (a) a recorded pass SKIPs on the same tree. RED without the cache: the second run executes (count 2).
selftest_cache_skip_same_tree() {
  cfx; cr; sfx "cache/same-tree: first run rc 0" 0 "$DVRC"
  sfx "cache/same-tree: the first run executed the check" 1 "$(nruns)"
  want "cache/same-tree: it is reported OK, not skipped" "^  OK    core-live *alpha "
  want "cache/same-tree: the cache announces itself" "^# cache: on — state "
  cr; sfx "cache/same-tree: second run rc 0" 0 "$DVRC"
  sfx "cache/same-tree: the second run did NOT execute the check" 1 "$(nruns)"
  want "cache/same-tree: it is a SKIP naming the head it passed at" "^  SKIP  core-live *alpha .*passed at [0-9a-f][0-9a-f]* on this tree"
  wantnot "cache/same-tree: and no OK line for it" "^  OK    core-live "
  sfx "cache/same-tree: an all-SKIP run's verdict is OK and states the cache" "PARITY-CORE: OK (1 arm(s) from cache, not executed this run)" "$(lastline)"
  wantnot "cache/same-tree: a core-live SKIP line carries no bookkeeping caveat" "^  SKIP  core-live .*bookkeeping paths not compared"
}

# (b) a code change re-runs, then SKIPs again. RED if the key ignored code (count stays 1) or never
# re-recorded (the third run would re-execute: count 3).
selftest_cache_code_change() {
  cfx; cr; cr; sfx "cache/code: precondition — one execution across two runs" 1 "$(nruns)"
  printf '# edit\n' >> "$d/conformance/beta.sh"; commit_fx
  cr; sfx "cache/code: a commit touching a non-bookkeeping file re-runs the check" 2 "$(nruns)"
  want "cache/code: reported OK again" "^  OK    core-live *alpha "
  cr; sfx "cache/code: and the new tree SKIPs on the next run" 2 "$(nruns)"
}

# (c) TWO KEYS. A bookkeeping-only commit RE-RUNS a core-live arm (several core-live checks grade those
# paths) but still SKIPs a heavy arm, whose SKIP line says the bookkeeping paths were not compared. RED if
# core-live were keyed minus bookkeeping (the check would SKIP: count stays 1), or if the heavy arm were keyed
# on the full tree (it would re-run: hcount 4, no caveat text).
selftest_cache_bookkeeping() {
  cfx; cr; sfx "cache/bookkeeping: precondition — ran once" 1 "$(nruns)"
  mkdir -p "$d/docs/reviews" "$d/docs/plans" "$d/docs/architecture"
  printf 'b\n' > "$d/BACKLOG.md"; printf 'c\n' > "$d/CHANGELOG.md"
  printf 'r\n' > "$d/docs/reviews/x.md"; printf 'p\n' > "$d/docs/plans/x.md"; printf 'a\n' > "$d/docs/architecture/x.md"
  commit_fx
  cr; sfx "cache/bookkeeping: a bookkeeping-only COMMIT re-runs the core-live arm" 2 "$(nruns)"
  want "cache/bookkeeping: reported OK, not SKIP" "^  OK    core-live *alpha "
  wantnot "cache/bookkeeping: and no core-live SKIP" "^  SKIP  core-live "
  printf 'more\n' >> "$d/docs/plans/x.md"
  cr; sfx "cache/bookkeeping: uncommitted bookkeeping dirt now BYPASSES the cache (runs again)" 3 "$(nruns)"
  want "cache/bookkeeping: with the dirty-tree note" "^# cache: off — uncommitted or untracked changes"
}
# (c2) the heavy half, with claims-registry and green-on-clone STUBBED as the other --warranted legs do (a
# ps stub for the concurrency guard; the memory floor still needs >=6144 MB free on the host). The listing
# (vs _b0) warrants claims + green-on-clone; hcount counts their executions.
selftest_cache_heavy_bookkeeping() {
  cfx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry "echo c >> $_m/hcount"; mkchk green-on-clone "echo g >> $_m/hcount"
  : > "$d/conformance/claims.tsv"; commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX"); printf '#!/bin/sh\necho "1 0 init"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  _hr() { DVOUT=$( cd "$d" && PATH="$_pd:$PATH" HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base "$_b0" --warranted 2>&1 ) && DVRC=0 || DVRC=$?; }
  _hn() { if [ -f "$_m/hcount" ]; then wc -l < "$_m/hcount" | tr -d ' '; else echo 0; fi; }
  _hr; sfx "cache/heavy: first run rc 0" 0 "$DVRC"
  sfx "cache/heavy: both stubbed heavy arms executed" 2 "$(_hn)"
  # (CHANGELOG.md, not BACKLOG.md: a BACKLOG.md in the listing would trigger the board-gate arm, off topic here.)
  printf 'r\n' > "$d/CHANGELOG.md"; mkdir -p "$d/docs/reviews"; printf 'r\n' > "$d/docs/reviews/y.md"; commit_fx
  _hr; sfx "cache/heavy: second run rc 0" 0 "$DVRC"
  sfx "cache/heavy: a bookkeeping-only commit does NOT re-run the heavy arms" 2 "$(_hn)"
  want "cache/heavy: claims SKIPs, saying the bookkeeping paths were not compared" "^  SKIP  heavy  *claims-registry .*passed at [0-9a-f][0-9a-f]* on this tree (producer [^)]*) (bookkeeping paths not compared; CI grades them)$"
  want "cache/heavy: green-on-clone SKIPs the same way" "^  SKIP  heavy  *green-on-clone .*(bookkeeping paths not compared; CI grades them)$"
  sfx "cache/heavy: the core-live arm (full key) DID re-run" 2 "$(nruns)"
  sfx "cache/heavy: the verdict counts the two cached arms" "PARITY-CORE: OK (2 arm(s) from cache, not executed this run)" "$(lastline)"
  printf 'x\n' >> "$d/conformance/beta.sh"; commit_fx
  _hr; sfx "cache/heavy: a code change re-runs the heavy arms" 4 "$(_hn)"
  rm -rf "$_pd"
}

# (d) any uncommitted or untracked change bypasses the cache with one note. RED without the dirty test: the
# key (HEAD only) matches, the run SKIPs and never sees the stray file (count 1).
selftest_cache_dirty_bypass() {
  cfx; cr; sfx "cache/dirty: precondition — ran once" 1 "$(nruns)"
  printf 'x\n' > "$d/stray.txt"
  cr; sfx "cache/dirty: a dirty tree re-runs the check" 2 "$(nruns)"
  want "cache/dirty: with one note naming why" "^# cache: off — uncommitted or untracked changes"
  wantnot "cache/dirty: and nothing is skipped" "^  SKIP  "
  rm -f "$d/stray.txt"; mkdir -p "$d/newdir"; printf 'y\n' > "$d/newdir/f"
  cr; sfx "cache/dirty: a file inside a new untracked directory also bypasses" 3 "$(nruns)"
}

# (d2) a tool-absent SKIP-pass is rc 0 but proved nothing: never recorded. RED if recorded (count stays 1).
selftest_cache_skip_output_never() {
  cfx 'echo "SKIP: sometool not installed"'; cr; sfx "cache/skip-output: rc 0" 0 "$DVRC"
  cr; sfx "cache/skip-output: a check that printed SKIP runs again (it was not recorded)" 2 "$(nruns)"
  wantnot "cache/skip-output: never a cache SKIP line" "^  SKIP  "
}

# (e) a FAIL is never recorded. RED if a failing arm were recorded: the second run SKIPs (count 1).
selftest_cache_fail_never() {
  cfx 'exit 1'; cr; sfx "cache/fail: a failing check is FAIL, rc 1" 1 "$DVRC"
  cr; sfx "cache/fail: the next run runs it AGAIN (the fail was not recorded)" 2 "$(nruns)"
  wantnot "cache/fail: never a SKIP" "^  SKIP  "
  _rc1=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p )
  sfx "cache/fail: no passed file was written for a failing arm" no "$([ -e "$_h/.local/state/sparkwright/prepush/$_rc1/passed" ] && echo yes || echo no)"
}

# (f) an unusable state dir -> run every arm with a note; a valid one still works. RED if the lane trusted a
# file / world-writable dir (the second run would SKIP: count stays) or died on mkdir failure (rc != 0).
selftest_cache_unusable_dir() {
  cfx; mkdir -p "$_h/.local/state/sparkwright"; : > "$_h/.local/state/sparkwright/prepush"
  cr; sfx "cache/unusable: a FILE where the state dir must go -> still rc 0" 0 "$DVRC"
  want "cache/unusable: the no-cache note" "^# cache: off — the state dir cannot be created"
  cr; sfx "cache/unusable: so every run executes the check" 2 "$(nruns)"
  rm -f "$_h/.local/state/sparkwright/prepush"
  _rc1=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p )
  mkdir -p "$_h/.local/state/sparkwright/prepush/$_rc1"; chmod 777 "$_h/.local/state/sparkwright/prepush/$_rc1"
  cr; sfx "cache/unusable: a world-writable state dir is refused (the check ran)" 3 "$(nruns)"
  want "cache/unusable: the note names the permission rule" "^# cache: off — the state dir is not a plain directory, or is group/world-writable"
  chmod 700 "$_h/.local/state/sparkwright/prepush/$_rc1"
  cr; sfx "cache/unusable: the same dir at 0700 is accepted (runs and records)" 4 "$(nruns)"
  cr; sfx "cache/unusable: and then SKIPs" 4 "$(nruns)"
}

# (f2) a SYMLINKED state dir and a mode-000 state dir -> cache off with a note, the check runs. RED if the
# lane followed the symlink (it would write `passed` into the target and the second run would SKIP) or trusted
# an unreadable dir (it would die or silently skip).
selftest_cache_state_dir_modes() {
  cfx; _rc1=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p )
  _sp=$_h/.local/state/sparkwright/prepush; mkdir -p "$_sp"
  _t=$(mktemp -d "${TMPDIR:-/tmp}/fx-tgt-XXXXXX"); ln -s "$_t" "$_sp/$_rc1"
  cr; sfx "cache/symlink: a symlinked state dir -> still rc 0" 0 "$DVRC"
  want "cache/symlink: the no-cache note" "^# cache: off — the state dir is not a plain directory"
  cr; sfx "cache/symlink: every run executes the check" 2 "$(nruns)"
  sfx "cache/symlink: nothing was written through the link" no "$([ -e "$_t/passed" ] && echo yes || echo no)"
  rm -f "$_sp/$_rc1"
  if [ "$(id -u)" = 0 ]; then
    echo "SKIP: cache/chmod000: running as root — mode 000 does not stop root, so the leg was NOT exercised"; return 0
  fi
  mkdir -p "$_sp/$_rc1"; chmod 000 "$_sp/$_rc1"
  cr; sfx "cache/chmod000: an unreadable state dir -> still rc 0" 0 "$DVRC"
  want "cache/chmod000: the no-cache note" "^# cache: off — the state dir is unreadable"
  sfx "cache/chmod000: and the check ran" 3 "$(nruns)"
  chmod 700 "$_sp/$_rc1"
}

# (g) PREPUSH_NO_CACHE=1 -> every arm runs, nothing is written. RED if the opt-out were ignored (count 1).
selftest_cache_opt_out() {
  cfx; CRNC=1; cr; cr; CRNC=0
  sfx "cache/opt-out: with PREPUSH_NO_CACHE=1 both runs execute the check" 2 "$(nruns)"
  want "cache/opt-out: with one note" "^# cache: off — PREPUSH_NO_CACHE=1"
  # (the heavy-arm lock legitimately creates $HOME/.local/state/sparkwright/, and the run log (SWAS-568, no switch) the prepush/<root> dir; the cache's own `passed` file must be absent)
  sfx "cache/opt-out: and no cache state was written under HOME" no "$(ls "$_h"/.local/state/sparkwright/prepush/*/passed >/dev/null 2>&1 && echo yes || echo no)"
  _rc1=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p )
  sfx "cache/opt-out: the root dir holds exactly the run log (no passed, no times.tsv)" "runs.log" "$(ls -A "$_h/.local/state/sparkwright/prepush/$_rc1" | tr '\n' ' ' | sed 's/ $//')"
}

# --- PREPUSH-BATTERY-CHANGE-SCOPED (T1: the derivation + skip lines) -------------------------
selftest_warranted_nonvac_registered() {
  one_step; mkchk alpha 'exit 0'
  printf 'check control alpha-check   sh conformance/alpha.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  printf 'exit 1\n' >> "$d/conformance/alpha.sh"; commit_fx
  rn "$d" --base "$_b0"
  want "warranted: a REGISTERED edited check enters the warranted set (anchor)" "warranted: non-vacuity alpha\.sh$"
}

selftest_warranted_nonvac_unregistered() {
  one_step; mkchk foo 'exit 0'; commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  printf 'exit 1\n' >> "$d/conformance/foo.sh"; commit_fx
  rn "$d" --base "$_b0"
  wantnot "warranted: an UNREGISTERED edited check never enters the warranted set" "warranted: non-vacuity foo"
  want "warranted: it is skipped, naming the exit-2 the flag would hit" "skipped: non-vacuity foo — not a verify\.sh check row (non-vacuity --only would exit 2)"

  # a sibling REGISTERED row exists (foo-bar); a DOTTED basename must never false-match it via a
  # loose regex (R-C11 cond.1/2: fixed-string field comparison, never an ERE where "." is a wildcard).
  one_step; mkchk foo-bar 'exit 0'
  printf 'check control foo-bar-check   sh conformance/foo-bar.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b1=$( cd "$d" && git rev-parse HEAD )
  printf '#!/bin/sh\nexit 0\n' > "$d/conformance/foo.bar.sh"
  commit_fx
  rn "$d" --base "$_b1"
  wantnot "warranted: exact matching — a dotted basename never false-matches a dashed sibling row (R-C11 cond.2)" "warranted: non-vacuity foo\.bar\.sh$"
  want "warranted: it is skipped as unregistered, not falsely warranted" "skipped: non-vacuity foo\.bar — not a verify\.sh check row"
}

selftest_warranted_charset() {
  one_step
  # register a check row for the SAME basename the charset would reject, so the "not warranted"
  # assertion proves the charset test runs BEFORE the row test (never reaching it at all).
  printf 'check control rf-check   sh conformance/-rf.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  printf '#!/bin/sh\nexit 0\n' > "$d/conformance/-rf.sh"; commit_fx
  rn "$d" --base "$_b0"
  wantnot "warranted: a basename outside the closed charset never enters the warranted set (R-C11 cond.1)" "warranted: non-vacuity -rf"
  want "warranted: it is skipped, naming the closed charset (never forwarded)" "skipped: non-vacuity -rf — basename outside the closed charset"
  wantnot "warranted: the charset rejection never falls through to the row test, even when a row exists for it" "skipped: non-vacuity -rf — not a verify\.sh check row"
}

selftest_warranted_nonvac_nowordsplit_noglob() {
  one_step; mkchk agent-autonomy 'exit 0'
  printf 'check control agent-autonomy-check   sh conformance/agent-autonomy.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  # an edited basename with an embedded SPACE must stay ONE listing entry (never word-split into a
  # registered sibling name), and a LITERAL glob token must never pathname-expand against the repo
  # root (R-C11 cond.1: fixed contract "line-wise, never $(...) word-split/globbed").
  printf '#!/bin/sh\nexit 0\n' > "$d/conformance/zz agent-autonomy.sh"
  printf '#!/bin/sh\nexit 0\n' > "$d/conformance/*.sh"
  commit_fx
  rn "$d" --base "$_b0"
  wantnot "warranted: a space-bearing basename is never word-split into a registered sibling" "warranted: non-vacuity agent-autonomy\.sh$"
  sfx "warranted: exactly two non-vacuity lines total, one per literal listing entry (no split, no expansion)" \
    "2" "$(printf '%s\n' "$DVOUT" | grep -c 'non-vacuity' || :)"
}

selftest_warranted_goc_scripts() {
  one_step; commit_fx; mkdir -p "$d/scripts"; printf 'x\n' > "$d/scripts/x.sh"
  rn "$d"
  want "warranted: a scripts/-only listing warrants green-on-clone" "warranted: green-on-clone$"
}

selftest_warranted_goc_export_ignored() {
  one_step; commit_fx; need_cls goc-export-ignored || return 0
  printf 'extra.txt export-ignore\n' > "$d/.gitattributes"; commit_fx
  : > "$d/extra.txt"
  rn "$d"
  want "warranted: docs-only is false (extra.txt is not .md)" "^# docs-only: false$"
  wantnot "warranted: green-on-clone is NOT warranted for an export-ignored-only, non-conformance/scripts delta" "warranted: green-on-clone$"
  want "warranted: it is skipped, naming export-ignored-only" "skipped: green-on-clone — the listing touches neither conformance/ nor scripts/, and is export-ignored-only"
}

selftest_warranted_claims() {
  one_step; commit_fx
  : > "$d/conformance/claims.tsv"
  rn "$d"
  want "warranted: an edited claims.tsv warrants claims" "warranted: claims$"

  one_step
  printf 'id\tclaim\tverifier\tproof\nx\ty\tsh conformance/beta.sh\ttree\n' > "$d/conformance/claims.tsv"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  printf 'exit 1\n' >> "$d/conformance/beta.sh"; commit_fx
  rn "$d" --base "$_b0"
  want "warranted: an edited verifier named in claims.tsv's field 3 warrants claims (read for matching only)" "warranted: claims$"
}

selftest_warranted_docs_only() {
  one_step; need_cls warranted-docs-only || return 0
  commit_fx
  : > "$d/notes.md"
  rn "$d"
  want "warranted: a docs-only listing warrants nothing" "none warranted by this listing$"
  want "warranted: claims is skipped, docs-only, with an expected time" "skipped: claims — docs-only delta (expected"
  want "warranted: green-on-clone is skipped, docs-only, with an expected time" "skipped: green-on-clone — docs-only delta (expected"
}

selftest_warranted_exports_never() {
  one_step; commit_fx; need_cls warranted-exports-never || return 0
  : > "$d/random-code.txt"
  rn "$d"
  want "warranted: --exports is still recommended by name when its trigger fires" "^#   --exports — the delta is not export-ignored-only$"
  wantnot "warranted: but exports never enters the warranted set (R-C11 condition 6)" "^#   warranted: exports$"
}

# R2(iii): a listing that warrants NO arm — a non-doc, export-ignored-only path (not the docs-only
# case above) — must run ZERO heavy invocations under --warranted.
selftest_warranted_export_ignored_runs_nothing() {
  one_step; commit_fx; need_cls warranted-export-ignored-runs-nothing || return 0
  printf 'extra.txt export-ignore\n' > "$d/.gitattributes"; commit_fx
  : > "$d/extra.txt"
  # PREPUSH_MEM_FLOOR_MB is RAISE-ONLY (see FLOOR's raise_only above): setting it to 1 here was a
  # no-op that misleadingly implied the floor could be lowered for the test — this leg still depends
  # on >=6144 MB free on the host, same as the ceiling leg below.
  DVOUT=$( cd "$d" && sh "$LANE" --base HEAD --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  want "warranted/export-ignored: nothing warranted by this listing" "none warranted by this listing$"
  sfx "warranted/export-ignored: zero heavy invocations under --warranted" \
    "0" "$(printf '%s\n' "$DVOUT" | grep -cE '^#   sh conformance/(claims-registry|non-vacuity|green-on-clone)\.sh' || :)"
  sfx "warranted/export-ignored: rc 0" 0 "$DVRC"
}

# --- PREPUSH-BATTERY-CHANGE-SCOPED (T2: --warranted + the concurrency guard) -------------------

# Step 0 (ii): the claims-loop match must reach awk through the ENVIRONMENT, never `-v` (which
# backslash-DECODES its value) — a committed `conformance/agent\055autonomy.sh` must never
# false-match the registered verifier `conformance/agent-autonomy.sh`. Anchor first (the real,
# edited verifier DOES warrant claims), then four never-match siblings.
selftest_warranted_claims_exact_match() {
  one_step; mkchk agent-autonomy 'exit 0'
  printf 'id\tclaim\tverifier\tproof\nx\ty\tsh conformance/agent-autonomy.sh\ttree\n' > "$d/conformance/claims.tsv"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  printf 'exit 1\n' >> "$d/conformance/agent-autonomy.sh"
  commit_fx
  rn "$d" --base "$_b0"
  want "warranted/claims-exact: the real verifier, edited, warrants claims (anchor)" "warranted: claims$"

  for _sib in agent-autonomy-x.sh agent.autonomy.sh 'x|.*.sh' 'agent\055autonomy.sh'; do
    one_step; mkchk agent-autonomy 'exit 0'
    printf 'id\tclaim\tverifier\tproof\nx\ty\tsh conformance/agent-autonomy.sh\ttree\n' > "$d/conformance/claims.tsv"
    commit_fx; _b1=$( cd "$d" && git rev-parse HEAD )
    : > "$d/conformance/$_sib"
    commit_fx
    rn "$d" --base "$_b1"
    wantnot "warranted/claims-exact: conformance/$_sib never false-matches the registered verifier (R-C11 cond.2)" "warranted: claims$"
  done
}

selftest_warranted_conflict() {
  one_step; commit_fx
  rn "$d" --warranted --green-on-clone
  sfx "warranted/conflict: --warranted then a heavy flag is rc 2" 2 "$DVRC"
  rn "$d" --green-on-clone --warranted
  sfx "warranted/conflict: a heavy flag then --warranted is rc 2 (reverse order)" 2 "$DVRC"
  rn "$d" --warranted --exports
  sfx "warranted/conflict: --warranted + --exports is rc 2" 2 "$DVRC"
  rn "$d" --warranted --slow
  sfx "warranted/conflict: --warranted + --slow is rc 2" 2 "$DVRC"
  rn "$d" --warranted --non-vacuity alpha
  sfx "warranted/conflict: --warranted + --non-vacuity is rc 2" 2 "$DVRC"
}

selftest_warranted_operand() {
  one_step; commit_fx
  rn "$d" --warranted foo
  sfx "warranted/operand: --warranted takes no operand; a trailing token is rc 2" 2 "$DVRC"
  want "warranted/operand: never forwarded" "never forwarded"
}

# c: a fixture listing warranting two arms (claims + non-vacuity beta), both stubbed — both run,
# in the fixed order, through exec_check only.
selftest_warranted_serial() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 0'; mkchk non-vacuity 'exit 0'; mkchk green-on-clone 'exit 0'
  printf 'id\tclaim\tverifier\tproof\nx\ty\tsh conformance/nowhere.sh\ttree\n' > "$d/conformance/claims.tsv"
  printf 'exit 1\n' >> "$d/conformance/beta.sh"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  printf '#!/bin/sh\necho "1 0 init"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  # PREPUSH_MEM_FLOOR_MB is RAISE-ONLY: this leg still depends on >=6144 MB free on the host.
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  sfx "warranted/serial: rc 0 (both stubbed arms exit 0)" 0 "$DVRC"
  want "warranted/serial: claims runs, fixed empty argv" "^#   sh conformance/claims-registry\.sh$"
  want "warranted/serial: non-vacuity beta runs, exact argv" "^#   sh conformance/non-vacuity\.sh --only beta\.sh$"
  # R2(ii): assert the ENTIRE executed heavy argv sequence by EXACT EQUALITY (sfx), not a grep that
  # only samples two of the three warranted lines — a stray `exec_check heavy green-on-clone` added
  # AFTER the loop would append a fourth line here and this must red.
  sfx "warranted/serial: the exact executed heavy argv sequence, fixed order, no extra arm" \
    "$(printf '#   sh conformance/claims-registry.sh\n#   sh conformance/non-vacuity.sh --only beta.sh\n#   sh conformance/green-on-clone.sh')" \
    "$(printf '%s\n' "$DVOUT" | grep -E '^#   sh conformance/(claims-registry|non-vacuity|green-on-clone)\.sh')"
}

# d: a red stubbed arm -> verdict FAIL, and the next arm still runs.
selftest_warranted_fail_continues() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 1'; mkchk green-on-clone 'exit 0'
  printf 'exit 1\n' >> "$d/conformance/beta.sh"
  : > "$d/conformance/claims.tsv"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  printf '#!/bin/sh\necho "1 0 init"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  sfx "warranted/fail: rc 1" 1 "$DVRC"
  want "warranted/fail: the verdict line reads FAIL" "^PARITY-CORE: FAIL$"
  want "warranted/fail: the next arm still ran after a red arm" "^#   sh conformance/green-on-clone\.sh$"
}

# e: the guard HIT — a foreign process (not a descendant of the lane) whose command line contains
# `green-on-clone.sh` refuses that arm, UNVERIFIED, naming only the pid and the lane's own literal.
selftest_warranted_busy_hit() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 0'
  : > "$d/conformance/claims.tsv"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  # S3: the shim row's command column carries a CANARY that is not one of the closed-list literals
  # ("RAWCMD-9f3e1"), so `wantnot "sleep 20"` (which nothing in this fixture ever prints, mutant or
  # not) is replaced by a real proof that the REFUSED note never echoes the raw command line.
  printf '#!/bin/sh\necho "4242424 1 sh conformance/green-on-clone.sh --x RAWCMD-9f3e1"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  # PREPUSH_MEM_FLOOR_MB is RAISE-ONLY: this leg still depends on >=6144 MB free on the host.
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  want "warranted/busy: the arm is REFUSED, naming the pid and the lane's own literal" \
    '^# REFUSED: another heavy arm is running (pid [0-9][0-9]*, green-on-clone\.sh)'
  wantnot "warranted/busy: never the raw command line" "RAWCMD-9f3e1"
  sfx "warranted/busy: verdict is UNVERIFIED" \
    "PARITY-CORE: UNVERIFIED (another heavy arm is running)" "$(printf '%s\n' "$DVOUT" | tail -1)"
  sfx "warranted/busy: rc 1" 1 "$DVRC"
}

# f: the negative of (e) — a run with NO foreign heavy-shaped process proceeds: each real stub arm's
# OWN invocation matches one of the five closed-list names (non-vacuity.sh in particular), and by
# construction (serial, waited) that never causes a later arm to see it as still "busy".
selftest_warranted_busy_own_descendant() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 0'; mkchk non-vacuity 'exit 0'; mkchk green-on-clone 'exit 0'
  printf 'exit 1\n' >> "$d/conformance/beta.sh"
  : > "$d/conformance/claims.tsv"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  printf '#!/bin/sh\necho "5555555 $PPID sh conformance/non-vacuity.sh"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  # PREPUSH_MEM_FLOOR_MB is RAISE-ONLY: this leg still depends on >=6144 MB free on the host.
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  wantnot "warranted/busy-own: no arm's own invocation is ever mistaken for a foreign busy process" "^# REFUSED: another heavy arm is running"
  want "warranted/busy-own: claims ran"       "^#   sh conformance/claims-registry\.sh$"
  want "warranted/busy-own: non-vacuity ran"  "^#   sh conformance/non-vacuity\.sh --only beta\.sh$"
  want "warranted/busy-own: green-on-clone ran" "^#   sh conformance/green-on-clone\.sh$"
  sfx "warranted/busy-own: rc 0 (all three stubbed arms exit 0, none refused)" 0 "$DVRC"
}

# f2: an ANCESTOR of the lane matching the closed list is busy — over-deny BY DESIGN (an enclosing
# heavy arm, e.g. CI's `check control` row running this very selftest under `verify.sh --require`,
# really does hold memory). The fixture row's ppid chain never reaches the lane's own pid, so the
# descendant-skip does not fire, and the arm is REFUSED exactly as a foreign, unrelated process is.
selftest_warranted_busy_ancestor() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 0'
  : > "$d/conformance/claims.tsv"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  printf '#!/bin/sh\necho "4242425 1 sh conformance/verify.sh --require"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  # PREPUSH_MEM_FLOOR_MB is RAISE-ONLY: this leg still depends on >=6144 MB free on the host.
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  want "warranted/busy-ancestor: an ancestor matching the list is REFUSED (over-deny by design)" \
    '^# REFUSED: another heavy arm is running (pid 4242425, verify\.sh --require)'
  sfx "warranted/busy-ancestor: rc 1" 1 "$DVRC"
}

# f3: a non-numeric pid field is ignored, never refused — pins the `^[0-9]+$` validation.
selftest_warranted_busy_numeric_ignored() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 0'; mkchk green-on-clone 'exit 0'
  : > "$d/conformance/claims.tsv"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  printf '#!/bin/sh\necho "abc 1 sh conformance/green-on-clone.sh"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  wantnot "warranted/busy-numeric: a non-numeric pid row is never refused" "^# REFUSED: another heavy arm is running"
  want "warranted/busy-numeric: claims ran" "^#   sh conformance/claims-registry\.sh$"
  sfx "warranted/busy-numeric: rc 0" 0 "$DVRC"
}

# g: a `ps` failure over-denies — the arm is refused, UNVERIFIED.
selftest_warranted_busy_ps_fail() {
  one_step; commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkdir -p "$d/scripts"; printf 'x\n' > "$d/scripts/x.sh"; commit_fx
  _pf=$(mktemp -d "${TMPDIR:-/tmp}/fx-psfail-XXXXXX")
  printf '#!/bin/sh\nexit 1\n' > "$_pf/ps"; chmod +x "$_pf/ps"
  DVOUT=$( cd "$d" && PATH="$_pf:$PATH" sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pf"
  want "warranted/ps-fail: a ps failure refuses the arm, UNVERIFIED (over-deny)" \
    '^# UNVERIFIED: cannot enumerate processes (ps) — the .* arm is refused$'
  sfx "warranted/ps-fail: verdict is UNVERIFIED" \
    "PARITY-CORE: UNVERIFIED (cannot enumerate processes for the concurrency guard)" "$(printf '%s\n' "$DVOUT" | tail -1)"
}

# R2(i), SECURITY R-C11 (b): a `--warranted` leg with the memory floor set impossibly high must
# refuse EVERY arm — deleting the three `heavy_allowed warranted-*` calls (one per arm) must red
# this, since without them every stubbed arm would run despite the floor.
selftest_warranted_floor_refuses_all() {
  one_step; mkchk beta 'exit 0'
  printf 'check control beta-check   sh conformance/beta.sh\n' >> "$d/conformance/verify.sh"
  commit_fx; _b0=$( cd "$d" && git rev-parse HEAD )
  mkchk claims-registry 'exit 0'; mkchk non-vacuity 'exit 0'; mkchk green-on-clone 'exit 0'
  printf 'exit 1\n' >> "$d/conformance/beta.sh"
  : > "$d/conformance/claims.tsv"
  commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX")
  # same heavy-free `ps` shim as the serial leg: if a mutant drops the floor check, this leg must
  # not fall through to a busy check that reads the HOST's real process list.
  printf '#!/bin/sh\necho "1 0 init"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" PREPUSH_MEM_FLOOR_MB=99999999 sh "$LANE" --base "$_b0" --warranted --verbose 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  sfx "warranted/floor: zero heavy invocations when the floor refuses every arm" \
    "0" "$(printf '%s\n' "$DVOUT" | grep -cE '^#   sh conformance/(claims-registry|non-vacuity|green-on-clone)\.sh' || :)"
  sfx "warranted/floor: verdict is UNVERIFIED (free memory below the floor)" \
    "PARITY-CORE: UNVERIFIED (free memory below the floor)" "$(printf '%s\n' "$DVOUT" | tail -1)"
  sfx "warranted/floor: rc 1" 1 "$DVRC"
}

# h: no flag -> nothing heavy runs; hooks/pre-push carries no --warranted; the router forwards it as
# a fixed token (rc 2 beside a heavy flag, exactly as calling the lane directly).
selftest_warranted_router_dial() {
  one_step; commit_fx; mkdir -p "$d/scripts"; printf 'x\n' > "$d/scripts/x.sh"
  mkchk green-on-clone 'exit 0'
  commit_fx
  rn "$d" --verbose
  wantnot "warranted/router: with no flag, nothing heavy runs" "^#   sh conformance/green-on-clone\.sh$"
  if [ -n "$KROOT" ] && [ -f "$KROOT/hooks/pre-push" ]; then
    if grep -q -- '--warranted' "$KROOT/hooks/pre-push"
    then echo "FAIL: warranted/router: hooks/pre-push contains --warranted"; SF=1
    else echo "PASS: warranted/router: hooks/pre-push contains no --warranted"
    fi
  else
    echo "N/A: warranted/router: hooks/pre-push not present in this checkout"
  fi
  if [ -n "$KROOT" ] && [ -f "$KROOT/scripts/sparkwright" ]; then
    _rrout=$( cd "$KROOT" && sh scripts/sparkwright prepush --warranted --green-on-clone 2>&1 ) && _rrc=0 || _rrc=$?
    sfx "warranted/router: through the router, --warranted + a heavy flag is rc 2" 2 "$_rrc"
    if printf '%s\n' "$_rrout" | grep -q 'already: --warranted'
    then echo "PASS: warranted/router: the rc-2 text names already: --warranted"
    else echo "FAIL: warranted/router: the rc-2 text does not name already: --warranted"; SF=1
    fi
  else
    echo "N/A: warranted/router: scripts/sparkwright not present in this checkout"
  fi
}

# PREPUSH-BOARD-GATES-PARITY (design §4). The fixture's backlog-current.sh is a STUB standing in for the
# real gate (which needs the kit's own libs): it reds on a board carrying a dangling Disposition pointer
# (a SUBSTANCE failure the real gate still FAILs on; a missing `L1 retro` marker is now only a WARN there,
# so it no longer stands in for a red). The defect class of #718 is "a board defect the lane must catch". Every leg is a sandboxed fixture repo under the selftest's own TMPDIR; BACKLOG.md
# is written AFTER commit_fx so it is untracked and therefore IN the lane's listing.
bg_fixture() {   # bg_fixture <board-text> — a fixture whose registry has ONE live board row and one --selftest row
  one_step; commit_fx
  printf 'check control backlog-current  sh conformance/backlog-current.sh --selftest\ncheck control backlog-current-run  --adopter sh conformance/backlog-current.sh .\n' > "$d/conformance/verify.sh"
  mkchk backlog-current '[ "${1-}" = . ] || { echo "backlog-current FIXTURE: argv lost"; exit 1; }; ! grep -q "DANGLING-ROW" BACKLOG.md || { echo "backlog-current FIXTURE: a Done row carries a dangling Disposition pointer"; exit 1; }'
  printf '%s\n' "$1" > "$d/BACKLOG.md"
}
# LEG 1, the load-bearing negative: a failing board in the listing FAILS the lane, naming the gate.
selftest_board_gate_fails() {
  bg_fixture '| `X-1` | Done | Disposition: row `DANGLING-ROW` |'; rn "$d"
  sfx "board/fails: rc 1" 1 "$DVRC"
  want "board/fails: the row is in the core-board bucket and names the registry check" "^  FAIL  core-board *backlog-current-run "
  want "board/fails: the gate's own failure text is shown in the detail lines" "^        | backlog-current FIXTURE: a Done row carries a dangling Disposition pointer"
  sfx "board/fails: PARITY-CORE: FAIL" "PARITY-CORE: FAIL" "$(lastline)"
}
# LEG 2: the same fixture with a passing board is OK — and the --selftest row is NOT run.
selftest_board_gate_passes() {
  bg_fixture '| `X-1` | Done | **L1 retro.** kept |'; rn "$d"
  sfx "board/passes: rc 0" 0 "$DVRC"
  want "board/passes: the live board row is OK in core-board" "^  OK    core-board *backlog-current-run "
  sfx "board/passes: exactly one core-board row (the --selftest registry row is excluded)" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^  [A-Z]* *core-board ' || :)"
  sfx "board/passes: PARITY-CORE: OK (scope stated)" "PARITY-CORE: OK (own surface — 1 CI-derived core-live check(s) not run; --warranted and CI run them)" "$(lastline)"
}
# LEG 3: no BACKLOG.md in the listing -> the skipped line, and no board gate runs (even a failing one).
selftest_board_gate_skipped() {
  bg_fixture '| `X-1` | Done | no marker here |'; rm -f "$d/BACKLOG.md"; rn "$d"
  sfx "board/skipped: rc 0" 0 "$DVRC"
  want "board/skipped: the skipped line names the reason" "^# skipped: board gates — BACKLOG.md not in the diff (expected ~"
  wantnot "board/skipped: no board gate ran" "core-board"
}
# LEG 4, non-vacuity of the derivation: BACKLOG.md in the listing but a registry with NO live board row is a FAIL, never a silent green.
selftest_board_gate_zero_rows() {
  one_step; commit_fx
  printf 'check control backlog-presence  sh conformance/backlog-presence.sh --selftest\ncheck control other  sh conformance/alpha.sh\n' > "$d/conformance/verify.sh"
  printf '| `X-1` | Done | x |\n' > "$d/BACKLOG.md"; rn "$d"
  sfx "board/zero-rows: rc 1" 1 "$DVRC"
  want "board/zero-rows: a FAIL row in core-board says nothing was derived" "^  FAIL  core-board .*no board gate derived"
  sfx "board/zero-rows: PARITY-CORE: FAIL" "PARITY-CORE: FAIL" "$(lastline)"
}
# LEG 5, the pin: on the REAL verify.sh the derivation names exactly these rows, in registry order. It moves if a board gate is added or removed, which is the prompt to look.
selftest_board_gate_derivation_pin() {
  if [ -z "$KROOT" ] || [ ! -f "$KROOT/conformance/verify.sh" ]; then echo "N/A: board/pin: no conformance/verify.sh in this checkout"; return 0; fi
  ( cd "$KROOT" && board_derive )
  sfx "board/pin: the derived board rows on the real registry" "roadmap-current backlog-adapters board-parser-drift-run backlog-current-run" "$(cut -f1 "$WORK/board.rows" | tr '\n' ' ' | sed 's/ $//')"
  sfx "board/pin: no underived-registry-row on the real registry" 0 "$(grep -c 'underived-registry-row' "$WORK/board.rows" || :)"
  sfx "board/pin: backlog-current-run keeps its registry argv (.), --adopter stripped" "backlog-current	." "$(grep '^backlog-current-run	' "$WORK/board.rows" | cut -f2,3)"
}
# LEG A (security L-1): a board script registered OFF-SHAPE (not `sh conformance/…`) is never silently dropped — the detector FAILS.
selftest_board_gate_underived() {
  bg_fixture '| `X-1` | Done | **L1 retro.** kept |'
  printf 'check control board-y  bash conformance/board-y.sh\n' >> "$d/conformance/verify.sh"; mkchk board-y 'exit 0'; rn "$d"
  sfx "board/underived: rc 1" 1 "$DVRC"
  want "board/underived: the extra row names (underived-registry-row) and says why" "^  FAIL  core-board *(underived-registry-row) a board-gate registry row was not derived"
  sfx "board/underived: PARITY-CORE: FAIL" "PARITY-CORE: FAIL" "$(lastline)"
}
# LEG B (reviewer M-2): a row whose argv leaves the closed charset is REFUSED and its stub is never executed.
selftest_board_gate_refused() {
  bg_fixture '| `X-1` | Done | **L1 retro.** kept |'
  printf 'check control backlog-x sh conformance/backlog-x.sh $(touch pwned)\n' >> "$d/conformance/verify.sh"
  mkchk backlog-x 'touch pwned-marker'; rn "$d"
  sfx "board/refused: rc 1" 1 "$DVRC"
  want "board/refused: FAIL core-board naming REFUSED" "^  FAIL  core-board *backlog-x REFUSED"
  sfx "board/refused: the stub never ran" no "$([ -e "$d/pwned-marker" ] && echo yes || echo no)"
  sfx "board/refused: the substitution never ran" no "$([ -e "$d/pwned" ] && echo yes || echo no)"
}
# LEG C (security L-2): a derived script that is a SYMLINK is off the lane's regular-file roster: FAIL, never executed.
selftest_board_gate_symlink() {
  bg_fixture '| `X-1` | Done | **L1 retro.** kept |'
  mkchk real 'touch symlink-ran'; rm -f "$d/conformance/backlog-current.sh"; ln -s real.sh "$d/conformance/backlog-current.sh"; rn "$d"
  sfx "board/symlink: rc 1" 1 "$DVRC"
  want "board/symlink: FAIL names the roster rule" "^  FAIL  core-board *backlog-current-run .*not a regular file in conformance/"
  sfx "board/symlink: the target never ran" no "$([ -e "$d/symlink-ran" ] && echo yes || echo no)"
}
# LEG D (reviewer M-1): the BACKLOG.md trigger is a LITERAL whole-line match — `BACKLOGxmd` must not trigger the arm.
selftest_board_gate_literal() {
  bg_fixture '| `X-1` | Done | no marker here |'; rm -f "$d/BACKLOG.md"; printf 'x\n' > "$d/BACKLOGxmd"; rn "$d"
  sfx "board/literal: rc 0" 0 "$DVRC"
  want "board/literal: the skipped line" "^# skipped: board gates — BACKLOG.md not in the diff"
  wantnot "board/literal: no board gate ran" "core-board"
}
# LEG E (security fix round 2): the derivation and the detector agree that `--selftest=1` is a selftest
# token. A `--selftest=1` row must neither run nor mask an off-shape sibling in the detector count.
selftest_board_gate_selftest_prefix() {
  one_step; commit_fx
  printf 'check control board-a  sh conformance/board-a.sh --selftest=1\ncheck control board-b  bash conformance/board-b.sh\n' > "$d/conformance/verify.sh"
  mkchk board-a 'touch board-a-ran'; mkchk board-b 'exit 0'
  printf '| `X-1` | Done | x |\n' > "$d/BACKLOG.md"; rn "$d"
  sfx "board/selftest-prefix: rc 1" 1 "$DVRC"
  want "board/selftest-prefix: the off-shape sibling is caught as (underived-registry-row)" "^  FAIL  core-board *(underived-registry-row) a board-gate registry row was not derived"
  sfx "board/selftest-prefix: the --selftest=1 row's stub never ran" no "$([ -e "$d/board-a-ran" ] && echo yes || echo no)"
}

# --- SWAS-278b: the machine-wide heavy-arm lock (design 6.2) and the cache producer rule (6.3) ---------
# The lock cells drive hl_acquire / hl_need / hl_try in SUBSHELLS with a short budget and poll (plain shell variables, no env knob), a fixture
# holder that `exec sleep`s on the lock (SIGKILL on its pid drops it), and shadowed hl_owner / mem_free_mb functions; the e2e cells run the lane.
now_s() { date +%s; }
# hlfx — a fresh HOME for one lock leg: sets _lh (HOME), _ld (the state dir), _ll (the lock file).
hlfx() {
  _lh=$(mktemp -d "${TMPDIR:-/tmp}/fx-lk-XXXXXX"); _ld=$_lh/.local/state/sparkwright; _ll=$_ld/heavy-arm.lock
  mkdir -p "$_ld"; chmod 700 "$_ld"
}
# hl_run <home> <budget> <poll> <unit> — hl_acquire in a subshell; prints its notes, then rc/state/UNV/seconds waited and the holder note's first line.
hl_run() {
  ( set +e; HOME=$1; HL_BUDGET=$2; HL_POLL=$3; HL_STATE=none; UNV=""
    _s0=$(now_s); _r=0; hl_acquire "$4" || _r=$?
    printf 'rc=%s state=%s unv=[%s] waited=%s\n' "$_r" "${HL_STATE-}" "$UNV" "$(( $(now_s) - _s0 ))"
    [ ! -f "$1/.local/state/sparkwright/heavy-arm.holder" ] || printf 'note1=%s\n' "$(sed -n 1p "$1/.local/state/sparkwright/heavy-arm.holder")" ) 2>&1
}
# hl_holder <home> <seconds> [note-pid] — a process that HOLDS the lock for <seconds>; sets HPID. exec sleep: the pid IS the holder.
hl_holder() {
  _hrdy=$1/ready; rm -f "$_hrdy"
  ( set +e; HOME=$1; HL_WHY=""; hl_open || exit 7; hl_try || exit 8
    printf '%s\n/fixture/tree\nfixture-unit\n2026-01-01T00:00:00Z\n' "${3:-4242}" > "$1/.local/state/sparkwright/heavy-arm.holder"
    : > "$_hrdy"; exec sleep "$2" ) 2>/dev/null &
  HPID=$!; _i=0
  while [ ! -e "$_hrdy" ] && [ "$_i" -lt 100 ]; do
    hl_kill "$HPID" -0 || break
    sleep 0.1 2>/dev/null || sleep 1; _i=$((_i+1))
  done
}
# hl_kill <pid> [signal] — the ONLY way a selftest cell signals a process. A pid that is empty, not all digits, or numerically 0 or 1 is
# REFUSED (rc 1, nothing signalled): `kill 0` TERMs the caller's whole process group and `kill -1` every process the user may signal.
# Otherwise it returns kill's own rc, so `hl_kill "$p" -0` is a liveness probe.
# One line on purpose: selftest_lock_kill_zero reads these three definitions out of this file by their first line.
hl_kill() { case ${1:-} in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 1 ] 2>/dev/null || return 1; kill ${2:+"$2"} "$1" 2>/dev/null; }
# hl_wait <pid> — wait for a pid that is a real number; an empty or non-numeric one is skipped (a bare `wait` would wait for every child).
hl_wait() { case ${1:-} in ''|*[!0-9]*) return 0 ;; esac; wait "$1" 2>/dev/null || :; }
hl_holder_stop() { hl_kill "${HPID:-}" || :; hl_wait "${HPID:-}"; HPID=; }
# hl_free <home> — rc 0 when the lock is FREE (a fresh open file description can take it), 1 busy, 7 cannot open.
hl_free() { ( set +e; HOME=$1; HL_WHY=""; hl_open || exit 7; hl_try ) >/dev/null 2>&1; }
# nopath <cmd> — a directory of symlinks to /bin/* and /usr/bin/* minus <cmd> (selftest_dash's trick).
nopath() {
  _np=$(mktemp -d "${TMPDIR:-/tmp}/fx-np-XXXXXX")
  for _f in /bin/* /usr/bin/*; do case ${_f##*/} in "$1") ;; *) ln -s "$_f" "$_np/${_f##*/}" 2>/dev/null || : ;; esac; done
  printf '%s\n' "$_np"
}
# lkfx <stub-body> — a one-selftest fixture whose core-selftest stub runs <stub-body>; `gamma` is capable and committed after the base commit _lkb, so it is TOUCHED
# (SWAS-811: the roster grades committed paths; a run uses `--base "$_lkb"`).
lkfx() {
  mkcin 'sh conformance/gamma.sh --selftest'
  mkchk selftest-hermetic "$1; echo \"TARGET: conformance/gamma.sh (both faces)\""
  commit_fx; _lkb=$(git -C "$d" rev-parse HEAD); mkchk gamma 'case ${1-} in --selftest) exit 0 ;; esac'; commit_fx
}
# rnh <home> <repo> [args…] — a RUN with an explicit HOME -> DVOUT/DVRC.
rnh() { _hh=$1; _r=$2; shift 2; DVOUT=$( cd "$_r" && HOME=$_hh sh "$LANE" --base HEAD "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }

# K1
selftest_lock_acquire_release() {
  hlfx
  _o=$( ( set +e; HOME=$_lh; HL_BUDGET=5; HL_POLL=1; HL_STATE=none; UNV=""
          _r=0; hl_acquire core-selftest || _r=$?
          printf 'rc=%s state=%s\n' "$_r" "${HL_STATE-}"
          if [ -f "$_ld/heavy-arm.holder" ]; then printf 'note-present unit=%s\n' "$(sed -n 3p "$_ld/heavy-arm.holder")"; else echo note-absent; fi
          if hl_free "$_lh"; then echo busy-check=FREE; else echo busy-check=held; fi
          hl_release || :
          printf 'after state=%s\n' "${HL_STATE-}"
          if [ -f "$_ld/heavy-arm.holder" ]; then echo note2-present; else echo note2-absent; fi
          if hl_free "$_lh"; then echo free-check=free; else echo free-check=BUSY; fi ) 2>&1 ) || :
  DVOUT=$_o
  want "lock/acquire: the first heavy unit takes the lock" "^rc=0 state=held$"
  want "lock/acquire: the holder note names the unit" "^note-present unit=core-selftest$"
  want "lock/acquire: while held, a second open file description cannot take it (the lock is real)" "^busy-check=held$"
  want "lock/release: the holder note is cleared" "^note2-absent$"
  want "lock/release: and the lock is free again" "^free-check=free$"
}
# K1, end to end: the stub sees the note and a closed descriptor 9 DURING the unit; the lock is free and the note gone AFTER the run.
selftest_lock_acquire_e2e() {
  hlfx
  lkfx 'cat "'"$_ld"'/heavy-arm.holder" > "$PWD/holder.seen" 2>&1; if ( : >&9 ) 2>/dev/null; then echo open > "$PWD/fd9.seen"; else echo closed > "$PWD/fd9.seen"; fi'
  rnh "$_lh" "$d" --base "$_lkb"; sfx "lock/e2e: rc 0" 0 "$DVRC"
  want "lock/e2e: the run says it took the lock" "^# heavy-arm lock: acquired for the core-selftest unit"
  sfx "lock/e2e: the holder note named the unit during the run" "core-selftest" "$(sed -n 3p "$d/holder.seen" 2>/dev/null || echo MISSING)"
  sfx "lock/e2e: the unit ran with descriptor 9 closed" closed "$(cat "$d/fd9.seen" 2>/dev/null || echo MISSING)"
  sfx "lock/e2e: the holder note is gone after the run" no "$([ -e "$_ld/heavy-arm.holder" ] && echo yes || echo no)"
  _r=0; hl_free "$_lh" || _r=$?; sfx "lock/e2e: and the lock is free after the run" 0 "$_r"
  sfx "lock/e2e: the state dir holds nothing but the lock file and the prepush dir (the run log lives there, SWAS-568; the lane's own other writes stay in its work root)" "heavy-arm.lock prepush" "$(ls -A "$_ld" | tr '\n' ' ' | sed 's/ $//')"
  sfx "lock/e2e: and the prepush root dir holds exactly the run log" "runs.log" "$(ls -A "$_ld/prepush/$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)" | tr '\n' ' ' | sed 's/ $//')"
  sfx "lock/e2e: the lock file is kept (never deleted)" yes "$([ -f "$_ll" ] && echo yes || echo no)"
}
# One acquisition per run, held across core-live and the Tier-2 arms.
selftest_lock_phase_e2e() {
  hlfx; one_step; mkchk beta 'exit 0'
  mkchk alpha 'cat "'"$_ld"'/heavy-arm.holder" > "$PWD/holder.seen" 2>&1'
  mkchk claims-registry 'exit 0'; mkchk green-on-clone 'exit 0'
  commit_fx; _b0=$(cd "$d" && git rev-parse HEAD)
  : > "$d/conformance/claims.tsv"; commit_fx
  _pd=$(mktemp -d "${TMPDIR:-/tmp}/fx-ps-XXXXXX"); printf '#!/bin/sh\necho "1 0 init"\n' > "$_pd/ps"; chmod +x "$_pd/ps"
  DVOUT=$( cd "$d" && PATH="$_pd:$PATH" HOME=$_lh sh "$LANE" --base "$_b0" --warranted 2>&1 ) && DVRC=0 || DVRC=$?
  rm -rf "$_pd"
  sfx "lock/phase: rc 0" 0 "$DVRC"
  sfx "lock/phase: the first heavy unit of a --warranted run is core-live" "core-live" "$(sed -n 3p "$d/holder.seen" 2>/dev/null || echo MISSING)"
  sfx "lock/phase: ONE acquisition per run, whatever the number of units" 1 "$(printf '%s\n' "$DVOUT" | grep -c 'heavy-arm lock: acquired' || :)"
  want "lock/phase: the Tier-2 arms ran under it" "OK    heavy  *green-on-clone"
}
# nothing heavy in the default run -> the lock is never touched.
selftest_lock_light_unlocked() {
  one_step; mkchk alpha 'exit 0'; commit_fx; _h2=$(mktemp -d "${TMPDIR:-/tmp}/fx-home-XXXXXX")
  rnh "$_h2" "$d"; sfx "lock/light: rc 0" 0 "$DVRC"
  sfx "lock/light: a default run with no heavy unit takes no lock (no lock file)" no "$([ -e "$_h2/.local/state/sparkwright/heavy-arm.lock" ] && echo yes || echo no)"
}
# K2
selftest_lock_wait() {
  hlfx; hl_holder "$_lh" 3
  _o=$(hl_run "$_lh" 30 1 core-selftest) || :; hl_holder_stop; DVOUT=$_o
  want "lock/wait: the second run acquires once the holder lets go" "^rc=0 state=held "
  want "lock/wait: it printed who held it" "held by pid 4242 tree /fixture/tree unit fixture-unit since 2026-01-01T00:00:00Z"
  _w=$(printf '%s\n' "$_o" | sed -n 's/.*waited=\([0-9]*\)$/\1/p')
  sfx "lock/wait: and it really waited for the holder" yes "$([ "${_w:-0}" -ge 1 ] && echo yes || echo no)"
}
# K2, end to end (the poll is 15 s: this leg costs 15 s).
selftest_lock_wait_e2e() {
  hlfx; lkfx 'date +%s > "$PWD/ran.at"'
  _t0=$(now_s); hl_holder "$_lh" 12
  rnh "$_lh" "$d" --base "$_lkb"; hl_holder_stop
  sfx "lock/wait-e2e: rc 0" 0 "$DVRC"
  want "lock/wait-e2e: the run said it was waiting, naming the holder" "heavy-arm lock: busy (held by pid 4242"
  _ra=$(cat "$d/ran.at" 2>/dev/null || echo 0)
  sfx "lock/wait-e2e: the core-selftest unit ran only after the holder let go" yes "$([ $((_ra - _t0)) -ge 3 ] && echo yes || echo no)"
}
# K3
selftest_lock_kill9() {
  hlfx; hl_holder "$_lh" 60
  _o=$(hl_run "$_lh" 1 1 x) || :; DVOUT=$_o; want "lock/kill9: precondition — the live holder blocks" "^rc=1 "
  hl_kill "${HPID:-}" -KILL || :; hl_wait "${HPID:-}"; HPID=
  _o=$(hl_run "$_lh" 3 1 x) || :; DVOUT=$_o
  want "lock/kill9: the kernel dropped the lock with the holder, and the waiter acquires" "^rc=0 state=held "
}
# K4
selftest_lock_stale_note() {
  hlfx; printf '99999999\n/gone/tree\nold-unit\n2020-01-01T00:00:00Z\n' > "$_ld/heavy-arm.holder"
  _o=$(hl_run "$_lh" 5 1 core-selftest) || :; DVOUT=$_o
  want "lock/stale-note: a dead holder's note with the lock free acquires at once" "^rc=0 state=held unv=\[\] waited=[01]$"
  wantnot "lock/stale-note: and the note is replaced" "^note1=99999999$"
}
# K5
selftest_lock_budget_end() {
  hlfx; hl_holder "$_lh" 60
  _o=$(hl_run "$_lh" 2 1 core-selftest) || :; hl_holder_stop; DVOUT=$_o
  want "lock/budget: a live holder past the budget is UNVERIFIED, never OK" "^rc=1 state=failed unv=\[heavy-arm lock: "
  want "lock/budget: the notes say so" "UNVERIFIED: heavy-arm lock"
  wantnot "lock/budget: never an OK" "^rc=0 "
}
# K6
selftest_lock_budget_runlevel() {
  hlfx; hl_holder "$_lh" 60
  _o=$( ( set +e; HOME=$_lh; HL_BUDGET=3; HL_POLL=1; HL_STATE=none; UNV=""
          _a=$(now_s); hl_need core-live >/dev/null 2>&1 || :; _b=$(now_s)
          hl_need warranted-claims 2>&1 || :; hl_need warranted-green-on-clone >/dev/null 2>&1 || :; _c=$(now_s)
          echo "first=$((_b-_a)) rest=$((_c-_b))" ) 2>&1 ) || :; hl_holder_stop; DVOUT=$_o
  _f=$(printf '%s\n' "$_o" | sed -n 's/^first=\([0-9]*\) .*/\1/p'); _t=$(printf '%s\n' "$_o" | sed -n 's/.* rest=\([0-9]*\)$/\1/p')
  sfx "lock/runlevel: the first unit waits the whole budget" yes "$([ "${_f:-0}" -ge 3 ] && echo yes || echo no)"
  sfx "lock/runlevel: every later unit fails fast (one wait per run, not one per unit)" yes "$([ "${_t:-9}" -lt 2 ] && echo yes || echo no)"
  want "lock/runlevel: each skipped unit is named" "UNVERIFIED: heavy-arm lock not held — the warranted-claims unit is not run"
}
# K7
selftest_lock_dir_unsafe() {
  hlfx; chmod 777 "$_ld"
  _o=$(hl_run "$_lh" 1 1 x) || :; DVOUT=$_o
  want "lock/dir: a world-writable state dir is UNVERIFIED" "^rc=1 .*group/world-writable"
  hlfx
  _o=$( hl_owner() { echo some-other-user; }; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/dir: a foreign-owned state dir is UNVERIFIED" "^rc=1 .*not owned by the current user"
  hlfx; chmod 777 "$_ld"; lkfx 'touch "$PWD/unit-ran"'
  rnh "$_lh" "$d" --base "$_lkb"
  sfx "lock/dir-e2e: the run is rc 1" 1 "$DVRC"
  want "lock/dir-e2e: the verdict is UNVERIFIED naming the lock" "^PARITY-CORE: UNVERIFIED (heavy-arm lock: "
  sfx "lock/dir-e2e: and the heavy unit did not run" no "$([ -e "$d/unit-ran" ] && echo yes || echo no)"
}
# K8
selftest_lock_floor_reread() {
  hlfx; hl_holder "$_lh" 3
  _o=$( ( set +e; mem_free_mb() { echo 100; }; HOME=$_lh; HL_BUDGET=30; HL_POLL=1; HL_STATE=none; UNV=""; FLOOR=6144; FREE=99999
          hl_acquire core-selftest || :
          echo "free-after=$FREE" ) 2>&1 ) || :; hl_holder_stop; DVOUT=$_o
  want "lock/floor: after a wait the free-memory reading is taken again" "^free-after=100$"
  want "lock/floor: and a reading below the floor is named" "WARNING: free memory 100 MB is below the 6144 MB floor"
  hlfx
  _o=$( ( set +e; mem_free_mb() { echo 100; }; HOME=$_lh; HL_BUDGET=30; HL_POLL=1; HL_STATE=none; UNV=""; FLOOR=6144; FREE=99999
          hl_acquire core-selftest || :
          echo "free-after=$FREE" ) 2>&1 ) || :; DVOUT=$_o
  want "lock/floor: with no wait the earlier reading stands" "^free-after=99999$"
}
# K13
selftest_lock_symlink() {
  hlfx; _tg=$(mktemp -d "${TMPDIR:-/tmp}/fx-tg-XXXXXX"); printf 'keep\n' > "$_tg/target"; ln -s "$_tg/target" "$_ll"
  _o=$(hl_run "$_lh" 1 1 x) || :; DVOUT=$_o
  want "lock/symlink: a symlinked lock file is UNVERIFIED" "^rc=1 .*symlink"
  sfx "lock/symlink: the link is still there" yes "$([ -L "$_ll" ] && echo yes || echo no)"
  sfx "lock/symlink: and its target is untouched" keep "$(cat "$_tg/target")"
  lkfx 'touch "$PWD/unit-ran"'
  rnh "$_lh" "$d" --base "$_lkb"
  sfx "lock/symlink-e2e: the run is rc 1" 1 "$DVRC"
  want "lock/symlink-e2e: UNVERIFIED naming the lock" "^PARITY-CORE: UNVERIFIED (heavy-arm lock: "
  sfx "lock/symlink-e2e: the unit did not run" no "$([ -e "$d/unit-ran" ] && echo yes || echo no)"
  sfx "lock/symlink-e2e: and nothing was deleted" yes "$([ -L "$_ll" ] && [ -f "$_tg/target" ] && echo yes || echo no)"
}
# K14
selftest_lock_foreign_owner() {
  hlfx; : > "$_ll"
  _o=$( hl_owner() {
          if [ "${1##*/}" = heavy-arm.lock ]; then echo some-other-user; else ls -ldn "$1" | awk '{ print $3 }'; fi
        }
        hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/owner: a lock file owned by another user is UNVERIFIED" "^rc=1 .*owned by another user"
  sfx "lock/owner: and it is not deleted" yes "$([ -f "$_ll" ] && echo yes || echo no)"
}
# K15
selftest_lock_holder_sanitised() {
  hlfx; _x=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "x" }')
  printf '4242\n/t/a\033[31mb%s\nunit\n2026-01-01T00:00:00Z\n' "$_x" > "$_ld/heavy-arm.holder"
  _t=$( set +e; HOME=$_lh; HL_HOLDER=$_ld/heavy-arm.holder; hl_holder_text )
  sfx "lock/sanitised: a hostile note prints only [A-Za-z0-9._/:-] and spaces" 0 "$(printf '%s' "$_t" | LC_ALL=C grep -c '[^A-Za-z0-9._/: -]' || :)"
  sfx "lock/sanitised: no field exceeds 200 bytes" ok "$(printf '%s\n' "$_t" | awk '{ for (i = 1; i <= NF; i++) if (length($i) > 200) bad = 1 } END { print bad ? "long" : "ok" }')"
  rm -f "$_ld/heavy-arm.holder"
  _o=$( ( set +e; ROOT=$(printf '/t/a\nb\033[31m/c%s' "$_x"); HOME=$_lh; HL_BUDGET=1; HL_POLL=1; HL_STATE=none; UNV=""
          hl_acquire core-selftest >/dev/null 2>&1
          printf 'lines=%s\n' "$(grep -c '' "$_ld/heavy-arm.holder")"
          printf 'bad=%s\n' "$(LC_ALL=C grep -c '[^A-Za-z0-9._/:-]' "$_ld/heavy-arm.holder" || :)" ) 2>&1 ) || :; DVOUT=$_o
  want "lock/sanitised: the note the lane writes keeps four lines whatever the tree path holds" "^lines=4$"
  want "lock/sanitised: and carries no byte outside the charset" "^bad=0$"
}
# K16
selftest_lock_home_scoped() {
  hlfx; _la=$_lh; hl_holder "$_la" 30; hlfx
  _o=$(hl_run "$_lh" 0 1 x) || :; hl_holder_stop; DVOUT=$_o
  want "lock/home: a run under another HOME has its own lock file and does not contend" "^rc=0 state=held "
}
# K17
selftest_lock_no_tool() {
  hlfx
  _o=$( HL_FLOCKS=/nonexistent/flock; HL_PERL=/nonexistent/perl; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/no-tool: neither flock(1) nor perl -> UNVERIFIED, never an unlocked run" "^rc=1 .*neither flock(1) nor /nonexistent/perl"
  # Sec-L6: flock is looked for at fixed absolute paths only, never through PATH (a planted `flock` on PATH is not used)
  _fs=$(mktemp -d "${TMPDIR:-/tmp}/fx-fl-XXXXXX"); printf '#!/bin/sh\necho planted > "%s/planted"\nexit 0\n' "$_fs" > "$_fs/flock"; chmod +x "$_fs/flock"
  _o=$( PATH=$_fs:$PATH; HL_FLOCKS=/nonexistent/flock; HL_PERL=/nonexistent/perl; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/no-tool: a flock planted on PATH does not count" "^rc=1 .*neither flock(1) nor"
  sfx "lock/no-tool: and it was never run" no "$([ -e "$_fs/planted" ] && echo yes || echo no)"
}
# Sec-L4: the owner test is numeric and unshadowed — root's / is not ours unless we are root.
selftest_lock_owner_real() {
  if [ "$(id -u)" = 0 ]; then echo "SKIP: lock/owner-real: running as root — / IS ours; leg NOT exercised"; return 0; fi
  _r=0; hl_owner_ok / || _r=$?; sfx "lock/owner-real: a directory owned by root is not ours (no shadowing)" 1 "$_r"
  hlfx; _r=0; hl_owner_ok "$_ld" || _r=$?; sfx "lock/owner-real: and our own directory is" 0 "$_r"
}
# Sec-L3: a holder note path that is a symlink to a directory is never written through.
selftest_lock_holder_symlink() {
  hlfx; _tg=$(mktemp -d "${TMPDIR:-/tmp}/fx-tg-XXXXXX"); ln -s "$_tg" "$_ld/heavy-arm.holder"
  _o=$(hl_run "$_lh" 1 1 x) || :; DVOUT=$_o
  want "lock/holder-symlink: the lock is still taken" "^rc=0 state=held "
  sfx "lock/holder-symlink: nothing was written into the link's target directory" "" "$(ls -A "$_tg")"
  sfx "lock/holder-symlink: and the link itself is untouched" yes "$([ -L "$_ld/heavy-arm.holder" ] && echo yes || echo no)"
  sfx "lock/holder-symlink: no temp note is left behind" "heavy-arm.holder heavy-arm.lock" "$(ls -A "$_ld" | tr '\n' ' ' | sed 's/ $//')"
}
# K18
selftest_lock_race() {
  _bad=0; _round=0
  while [ "$_round" -lt 8 ]; do
    _round=$((_round+1)); hlfx; _go=$_lh/go; _pids=""
    for _n in 1 2 3 4; do
      ( set +e; HOME=$_lh; HL_WHY=""; hl_open || exit 7
        while [ ! -e "$_go" ]; do :; done
        if hl_try; then echo won > "$_lh/res.$_n"; exec sleep 5; else echo lost > "$_lh/res.$_n"; fi ) 2>/dev/null &
      _pids="$_pids $!"
    done
    sleep 0.5; : > "$_go"; _i=0
    while [ "$(ls "$_lh"/res.* 2>/dev/null | wc -l | tr -d ' ')" -lt 4 ] && [ "$_i" -lt 60 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i+1)); done
    _w=$(cat "$_lh"/res.* 2>/dev/null | grep -c '^won$' || :)
    [ "$_w" = 1 ] || _bad=$((_bad+1))
    # the pids are collected from `$!`; each goes through the guard one at a time, so an empty list or a stray 0 signals nothing
    for _kp in $_pids; do hl_kill "$_kp" || :; done; wait 2>/dev/null || :
  done
  sfx "lock/race: in 8 rounds of four simultaneous acquirers exactly one holds the lock every time" 0 "$_bad"
}
# K19
selftest_lock_child_fd() {
  hlfx; lkfx 'sleep 25 & echo $! > "$PWD/daemon.pid"'
  rnh "$_lh" "$d" --base "$_lkb"; sfx "lock/child-fd: rc 0" 0 "$DVRC"
  _r=0; hl_free "$_lh" || _r=$?
  sfx "lock/child-fd: a child left running by a unit does not keep the lock held" 0 "$_r"
  hl_kill "$(cat "$d/daemon.pid" 2>/dev/null || :)" || :
}
# K20
selftest_lock_ancestor_note() {
  for _np in 1 "$PPID" "$$"; do
    hlfx; hl_holder "$_lh" 60 "$_np"
    _o=$(hl_run "$_lh" 2 1 x) || :; hl_holder_stop; DVOUT=$_o
    want "lock/ancestor: a note naming pid $_np does not let the run skip the wait" "^rc=1 state=failed "
  done
}
# K21
selftest_lock_perl_env() {
  [ -x /usr/bin/perl ] || { echo "SKIP: lock/perl-env: /usr/bin/perl is absent — leg NOT exercised"; return 0; }
  hlfx; _pl=$WORK/perllib-$$; mkdir -p "$_pl"; _mk=$_lh/loaded
  printf 'package fixture;\nopen(my $m, ">>", $ENV{FIXTURE_MARK}) or die;\nprint $m "loaded\\n";\nclose $m;\n1;\n' > "$_pl/fixture.pm"
  ( PERL5LIB=$_pl PERL5OPT=-Mfixture FIXTURE_MARK=$_mk /usr/bin/perl -e 1 ) >/dev/null 2>&1 || :
  sfx "lock/perl-env: control — the fixture module loads when PERL5OPT reaches perl" yes "$([ -s "$_mk" ] && echo yes || echo no)"
  rm -f "$_mk"
  _o=$( HL_FLOCKS=/nonexistent/flock; PERL5LIB=$_pl; PERL5OPT=-Mfixture; FIXTURE_MARK=$_mk; export PERL5LIB PERL5OPT FIXTURE_MARK; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/perl-env: the lock is still taken through perl" "^rc=0 state=held "
  sfx "lock/perl-env: and the fixture PERL5OPT module was NOT loaded" no "$([ -e "$_mk" ] && echo yes || echo no)"
  # Sec-L1: the helper runs from / under `env -i`: PERL_USE_UNSAFE_INC (a '.' in @INC) never reaches it. PERLIO's layer loading is not relied on either way; env -i drops every PERL* variable by construction.
  hlfx; _cw=$(mktemp -d "${TMPDIR:-/tmp}/fx-cw-XXXXXX"); mkdir -p "$_cw/PerlIO"; _mk2=$_lh/loaded2
  printf 'package PerlIO::fixture;\nopen(my $m, ">>", $ENV{FIXTURE_MARK}) or die;\nprint $m "loaded\\n";\nclose $m;\nsub PUSHED { -1 }\n1;\n' > "$_cw/PerlIO/fixture.pm"
  # POSITIVE control (the cell is not vacuous): the same environment and cwd, with a perl run that does NOT go through the helper,
  # loads the cwd module (PERL5OPT names it; PERL_USE_UNSAFE_INC puts '.' in @INC).
  # The second half below is a REGRESSION cell, not a negative for `cd /` or `env -i`: its only loader is PERL5OPT, which any
  # unset of PERL5OPT would also close. What tells `cd / && env -i` from an unset is the wrapper cell after it.
  # CEILING, stated and not tested: that `env -i` and `cd /` close PERL_USE_UNSAFE_INC, PERLIO and every other PERL* route is true
  # BY CONSTRUCTION (nothing is passed in, nothing is read from the cwd); no cell exercises each of those routes.
  ( cd "$_cw" && PERL_USE_UNSAFE_INC=1 PERL5OPT=-MPerlIO::fixture FIXTURE_MARK=$_mk2 /usr/bin/perl -e 1 ) >/dev/null 2>&1 || :
  sfx "lock/perl-env: control — without the helper's cd / and env -i the cwd module loads" yes "$([ -s "$_mk2" ] && echo yes || echo no)"
  rm -f "$_mk2"
  _o=$( cd "$_cw" && HL_FLOCKS=/nonexistent/flock; PERL_USE_UNSAFE_INC=1; PERL5OPT=-MPerlIO::fixture; FIXTURE_MARK=$_mk2; export PERL_USE_UNSAFE_INC PERL5OPT FIXTURE_MARK; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/perl-env: the lock is still taken with those set" "^rc=0 state=held "
  sfx "lock/perl-env: regression — and the cwd module was NOT loaded" no "$([ -e "$_mk2" ] && echo yes || echo no)"
  # What only `cd / && env -i` does: a wrapper standing in for perl records the cwd and environment the helper hands it, then runs the real perl.
  hlfx; _ww=$_lh/perlwrap; _wc=$_lh/wrap.cwd; _we=$_lh/wrap.env
  printf '#!/bin/sh\npwd -P > "%s"\nenv > "%s"\nexec /usr/bin/perl "$@"\n' "$_wc" "$_we" > "$_ww"; chmod +x "$_ww"
  _o=$( cd "$_cw" && HL_FLOCKS=/nonexistent/flock; HL_PERL=$_ww; PERL_USE_UNSAFE_INC=1; PERL5OPT=-MPerlIO::fixture; PERLIO=:crlf; FIXTURE_MARK=$_mk2; export PERL_USE_UNSAFE_INC PERL5OPT PERLIO FIXTURE_MARK; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/perl-env: the lock is taken through the wrapper" "^rc=0 state=held "
  sfx "lock/perl-env: the helper runs perl from /, not from the caller's cwd" "/" "$(cat "$_wc" 2>/dev/null || echo MISSING)"
  sfx "lock/perl-env: and hands it no PERL5OPT, PERL_USE_UNSAFE_INC, PERLIO or FIXTURE_MARK (env -i)" 0 "$(grep -c '^\(PERL5OPT\|PERL_USE_UNSAFE_INC\|PERLIO\|FIXTURE_MARK\)=' "$_we" 2>/dev/null || :)"
  sfx "lock/perl-env: the wrapper really ran (its env record exists)" yes "$([ -f "$_we" ] && echo yes || echo no)"
}
# The Linux back end: the lane calls flock(1) as `flock -n 9`; its rc 1 is busy, any other nonzero rc is a helper failure.
selftest_lock_flock_shim() {
  hlfx; _fs=$(mktemp -d "${TMPDIR:-/tmp}/fx-fl-XXXXXX")
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/argv"\nexit "${FLOCK_RC:-0}"\n' "$_fs" > "$_fs/flock"; chmod +x "$_fs/flock"
  _o=$( HL_FLOCKS=$_fs/flock; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/flock: flock(1) rc 0 is the lock" "^rc=0 state=held "
  sfx "lock/flock: the lane calls it as 'flock -n 9'" "-n 9" "$(cat "$_fs/argv" 2>/dev/null || echo MISSING)"
  hlfx; _o=$( HL_FLOCKS=$_fs/flock; FLOCK_RC=1; export FLOCK_RC; hl_run "$_lh" 1 1 x ) || :; DVOUT=$_o
  want "lock/flock: flock(1) rc 1 is busy -> UNVERIFIED after the budget" "^rc=1 state=failed .*stayed busy"
  hlfx; _o=$( HL_FLOCKS=$_fs/flock; FLOCK_RC=64; export FLOCK_RC; hl_run "$_lh" 30 1 x ) || :; DVOUT=$_o
  want "lock/flock: any other rc is a helper failure at once, not a wait" "^rc=1 state=failed .*helper failed (rc 64)"
}
# K22 (SWAS-278b fix round 2, CI #880 non-vacuity): a pid that is empty, 0, 1, signed or not a number must never reach `kill`: `kill 0`
# TERMs the caller's WHOLE process group (the CI step's shell, an adopter's own pre-push). The helpers under test are read out of this file.
selftest_lock_kill_zero() {
  _kd=$(grep -E '^(hl_kill|hl_wait|hl_holder_stop)\(\)' "$LANE")
  # (a) SAFE: `kill` is shadowed by a function that only prints its argv, so no signal is ever sent, whatever the helpers do.
  _kb='kill() { echo "KILL-CALLED $*"; }
HPID=""; hl_holder_stop; HPID=; hl_holder_stop
for _p in "" 0 00 000 1 01 -1 abc "2 3" "4;5"; do hl_kill "$_p"; hl_kill "$_p" -KILL; done
hl_kill 4242 -0; echo done'
  DVOUT=$(sh -c "$_kd
$_kb" 2>&1) || :
  want "lock/kill-zero: a real pid still reaches kill, with its signal" "^KILL-CALLED -0 4242$"
  sfx "lock/kill-zero: and nothing else does (empty, 0, 00, 1, 01, -1, a word, a list)" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^KILL-CALLED' || :)"
  # (b) the real thing, in a process group of its own: a sentinel in the SAME group must survive the helpers with HPID empty.
  _pg=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
  _cp=$(perl -e 'setpgrp(0,0) or die "setpgrp: $!"; exec @ARGV or die "exec: $!"' sh -c 'ps -o pgid= -p $$' 2>/dev/null | tr -d ' ') || _cp=""
  if [ -z "$_cp" ] || [ -z "$_pg" ] || [ "$_cp" = "$_pg" ]; then
    echo "SKIP: lock/kill-zero: no perl setpgrp isolation here — the real-sentinel half NOT exercised (the shadowed-kill half above ran)"; return 0
  fi
  # a setpgrp that fails here dies BEFORE anything runs (its message is in DVOUT) and the two cells below FAIL loudly: never run un-isolated, never a silent pass
  DVOUT=$(perl -e 'setpgrp(0,0) or die "setpgrp: $!"; exec @ARGV or die "exec: $!"' sh -c "$_kd
sleep 30 & sp=\$!
HPID=; hl_holder_stop; echo stop-survived
if kill -0 \"\$sp\" 2>/dev/null; then echo sentinel-alive; else echo sentinel-dead; fi
kill \"\$sp\" 2>/dev/null; :" 2>&1) || :
  want "lock/kill-zero: the shell that stopped an empty HPID is still running" "^stop-survived$"
  want "lock/kill-zero: and a sentinel in its process group is still alive" "^sentinel-alive$"
}

# --- the cache producer rule and the new off switches (design 6.3) ---
# crd <dir> — a --warranted run with the cache ON in <dir>, against the leg's HOME.
crd() { DVOUT=$( cd "$1" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD --warranted 2>&1 ) && DVRC=0 || DVRC=$?; }
# K9
selftest_cache_producer_skip_line() {
  cfx; cr; cr; _pp=$(cd "$d" && pwd -P)
  want "cache/producer: the SKIP line names the producer tree" "^  SKIP  core-live *alpha .*passed at [0-9a-f][0-9a-f]* on this tree (producer $_pp)$"
}
# K10
selftest_cache_producer_other_tree() {
  cfx; cr; sfx "cache/other: precondition — the producer ran it once" 1 "$(nruns)"
  _c=$(mktemp -d "${TMPDIR:-/tmp}/fx-clone-XXXXXX")/c; git clone -q "$d" "$_c" 2>/dev/null
  crd "$_c"; sfx "cache/other: a record produced in another tree is NOT honoured (the check runs)" 2 "$(nruns)"
  wantnot "cache/other: no SKIP off another tree's record" "^  SKIP  "
  crd "$_c"; sfx "cache/other: the clone then skips off its OWN record" 2 "$(nruns)"
  cr; sfx "cache/other: and the first tree still skips off its own (records are per producer)" 2 "$(nruns)"
}
# K11
selftest_cache_off_index_tags() {
  cfx; cr; sfx "cache/tags: precondition — ran once" 1 "$(nruns)"
  ( cd "$d" && git update-index --skip-worktree conformance/beta.sh ); printf '# hidden\n' >> "$d/conformance/beta.sh"
  cr; sfx "cache/tags: a skip-worktree entry turns the cache off (the check runs)" 2 "$(nruns)"
  want "cache/tags: with one note" "^# cache: off — git ls-files -v shows a tag other than H"
  ( cd "$d" && git update-index --no-skip-worktree conformance/beta.sh && git checkout -q -- conformance/beta.sh && git update-index --assume-unchanged conformance/beta.sh )
  printf '# hidden\n' >> "$d/conformance/beta.sh"
  cr; sfx "cache/tags: an assume-unchanged entry does too" 3 "$(nruns)"
  ( cd "$d" && git update-index --no-assume-unchanged conformance/beta.sh && git checkout -q -- conformance/beta.sh )
  cr; sfx "cache/tags: with the flags cleared the same tree skips again" 3 "$(nruns)"
}
# K12
selftest_cache_off_sparse_filter() {
  cfx; cr; sfx "cache/sparse: precondition — ran once" 1 "$(nruns)"
  ( cd "$d" && git config core.sparseCheckout true )
  cr; sfx "cache/sparse: core.sparseCheckout on turns the cache off" 2 "$(nruns)"
  want "cache/sparse: with one note" "^# cache: off — core.sparseCheckout is on"
  ( cd "$d" && git config --unset core.sparseCheckout && git config filter.fx.clean cat )
  cr; sfx "cache/filter: a configured but UNAPPLIED filter leaves the cache on (the same tree skips)" 2 "$(nruns)"
  printf '* filter=fx\n' > "$d/.git/info/attributes"   # info/attributes is untracked: it applies the filter without dirtying the tree
  cr; sfx "cache/filter: a filter APPLIED to tracked paths turns it off" 3 "$(nruns)"
  want "cache/filter: with one note" "^# cache: off — a configured filter is applied to tracked paths"
  rm -f "$d/.git/info/attributes"; ( cd "$d" && git config --unset filter.fx.clean )
  cr; sfx "cache/filter: with both cleared the same tree skips again" 3 "$(nruns)"
}

# --- the applied-filter rule (SWAS-278b fix round, CI #880) ---
# crs — a --warranted run with the cache ON whose git sees a SYSTEM config file ($_sys): the faithful reproduction of a runner's /etc/gitconfig
# (GIT_CONFIG_SYSTEM points git at the file; the selftest-wide GIT_CONFIG_NOSYSTEM is unset for this run only).
crs() { DVOUT=$( cd "$d" && unset GIT_CONFIG_NOSYSTEM && GIT_CONFIG_SYSTEM=$_sys && export GIT_CONFIG_SYSTEM && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD --warranted 2>&1 ) && DVRC=0 || DVRC=$?; }
# crg — the same run with a `git` shim first on PATH ($_gs/git, from mkgitshim).
crg() { DVOUT=$( cd "$d" && PATH=$_gs:$PATH HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD --warranted 2>&1 ) && DVRC=0 || DVRC=$?; }
# mkgitshim <dir> <what check-attr does> — a git wrapper that logs its argv and replaces ONLY `check-attr`; every other subcommand is the real git.
mkgitshim() {
  _rg=$(command -v git)
  { printf '#!/bin/sh\n'; printf 'echo "$*" >> "%s/log"\n' "$1"
    printf 'case $1 in check-attr) cat > /dev/null; %s ;; esac\n' "$2"
    printf 'exec "%s" "$@"\n' "$_rg"; } > "$1/git"; chmod +x "$1/git"
}
# K13
selftest_cache_filter_applied() {
  cfx; cr; sfx "cache/applied: precondition — ran once" 1 "$(nruns)"
  _sys=$(mktemp -d "${TMPDIR:-/tmp}/fx-sys-XXXXXX")/gitconfig
  printf '[filter "lfs"]\n\tclean = git-lfs clean -- %%f\n\tsmudge = git-lfs smudge -- %%f\n\tprocess = git-lfs filter-process\n\trequired = true\n' > "$_sys"
  _o=$( cd "$d" && unset GIT_CONFIG_NOSYSTEM && GIT_CONFIG_SYSTEM=$_sys && export GIT_CONFIG_SYSTEM && git config --get filter.lfs.process ) || _o=MISSING
  sfx "cache/applied: precondition — git reads the runner-like system filter key" "git-lfs filter-process" "$_o"
  crs; sfx "cache/applied: a SYSTEM-level filter no tracked path uses leaves the cache on (the check is skipped)" 1 "$(nruns)"
  want "cache/applied: and it is a SKIP line" "^  SKIP  core-live *alpha .*passed at "
  wantnot "cache/applied: with no cache-off note" "^# cache: off"
  printf '* filter=lfs\n' > "$d/.git/info/attributes"
  crs; sfx "cache/applied: the same system filter APPLIED to tracked paths turns it off" 2 "$(nruns)"
  want "cache/applied: with one note" "^# cache: off — a configured filter is applied to tracked paths"
  rm -f "$d/.git/info/attributes"
  ( cd "$d" && git config filter.fx.clean cat ); printf 'conformance/beta.sh filter=fx\n' > "$d/.gitattributes"; commit_fx
  cr; sfx "cache/applied: a COMMITTED .gitattributes applying a configured filter runs the check" 3 "$(nruns)"
  want "cache/applied: and turns the cache off" "^# cache: off — a configured filter is applied to tracked paths"
  printf 'conformance/beta.sh filter=ghost\n' > "$d/.gitattributes"; commit_fx
  cr; cr; sfx "cache/applied: an attribute naming a filter with NO configured driver is not applied (one run, then it skips)" 4 "$(nruns)"
  # fail closed: check-attr itself fails, or prints a stream that is not one path/attr/value triple per tracked path
  _gs=$(mktemp -d "${TMPDIR:-/tmp}/fx-gs-XXXXXX"); mkgitshim "$_gs" 'exit 128'
  crg; sfx "cache/applied: check-attr FAILING turns the cache off (the check runs)" 5 "$(nruns)"
  want "cache/applied: with a note naming check-attr" "^# cache: off — .*check-attr"
  _g=0; grep -q '^check-attr ' "$_gs/log" 2>/dev/null || _g=$?
  sfx "cache/applied: non-vacuity — the shim really saw check-attr" 0 "$_g"
  _gs=$(mktemp -d "${TMPDIR:-/tmp}/fx-gs-XXXXXX"); mkgitshim "$_gs" 'printf "p\\0filter\\0"; exit 0'
  crg; sfx "cache/applied: an unparseable check-attr stream turns the cache off (the check runs)" 6 "$(nruns)"
  want "cache/applied: with a note naming check-attr" "^# cache: off — .*check-attr"
}

# --- SWAS-278a plan task 0: the tracker-credential tripwire (design 3.6, "G1 and the credential: measured at plan task 0") ---
# The pre-push runs a clone's OWN code, so the lane must never reach a tracker credential. This fixture is a tree that declares
# the Jira backend, pins a host nobody owns, and carries RECORDERS for the credential library's store call and for the adapter,
# plus a recording shim on PATH for every secret-store or network binary the kit names. The canary credentials sit in the
# caller's environment. The lane (default, then --warranted) must leave every recorder log empty. The positive control proves
# the recorders CAN be hit; the mutant proves the scrub is what keeps the canaries out.
tw_fx() {   # sets d (the fixture tree) and _tw (the recorder dir); rc 1 = no kit tree to take the real twin row from
  [ -n "$KROOT" ] && [ -f "$KROOT/conformance/tracker-contract.sh" ] && [ -f "$KROOT/conformance/prepush-twins.tsv" ] &&
    [ -f "$KROOT/scripts/tracker-cred.sh" ] && [ -f "$KROOT/scripts/tracker-conf.sh" ] || return 1
  d=$(mkrepo); _tw=$(mktemp -d "${TMPDIR:-/tmp}/fx-tw-XXXXXX"); mkdir -p "$d/scripts" "$d/.kit" "$_tw/bin"
  cp "$KROOT/conformance/tracker-contract.sh" "$d/conformance/tracker-contract.sh"
  cp "$KROOT/scripts/tracker-conf.sh" "$d/scripts/tracker-conf.sh"
  # the REAL twin row, whatever its argv is today: cutting that row's reach is what turns this fixture green.
  grep "^tracker-contract${TAB}" "$KROOT/conformance/prepush-twins.tsv" > "$d/conformance/prepush-twins.tsv"
  # the credential library is the real one, with its store binary pointed at a recorder in FOUND mode (it answers like a stored item).
  cat > "$_tw/security-rec" <<'TWSEC'
#!/bin/sh
printf '%s\n' "$*" >> "$(dirname "$0")/sec.log"
printf '    "acct"\074blob\076="stored@example.com"\n'
exit 0
TWSEC
  chmod +x "$_tw/security-rec"
  sed -e "s|^_TCR_SEC_BIN=.*|_TCR_SEC_BIN=$_tw/security-rec|" "$KROOT/scripts/tracker-cred.sh" > "$d/scripts/tracker-cred.sh"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/jira.log"\nexit 1\n' "$_tw" > "$d/scripts/tracker-jira.sh"
  for _n in security op secret-tool gh git-credential-osxkeychain curl; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >> "%s/shim.log"\nexit 1\n' "$_n" "$_tw" > "$_tw/bin/$_n"; chmod +x "$_tw/bin/$_n"
  done
  # a check that records any canary credential it can see: the scrub's own witness (the twin, post-cut, never reads one).
  printf '#!/bin/sh\n[ -z "${KIT_TRACKER_USER-}${KIT_TRACKER_TOKEN-}${JIRA_EMAIL-}${JIRA_TOKEN-}" ] || echo seen >> "%s/env.log"\nexit 0\n' "$_tw" > "$d/conformance/envprobe.sh"
  printf 'Backlog backend: Jira (project TRIP, conf .kit/tracker.conf)\n' > "$d/CLAUDE.md"
  printf 'version=1\nbackend=jira\nbase_url=https://tripwire.invalid\nflavour=cloud\nauth=basic\nproject=TRIP\n' > "$d/.kit/tracker.conf"
  { printf 'name: fx\njobs:\n  j1:\n    steps:\n'
    printf '      - name: Tracker-contract UNVERIFIED without creds (honest non-pass)\n'
    printf "        run: 'if sh conformance/tracker-contract.sh; then echo \"ERROR: expected UNVERIFIED (exit 2), got a pass\"; exit 1; else test \$? -eq 2; fi'\n"
    printf '      - name: witness\n        run: sh conformance/envprobe.sh\n'
  } > "$d/.github/workflows/ci.yml"
  commit_fx
}
# tw_run <lane> [lane args…] -> DVOUT/DVRC, with the canary credentials in the environment and the shims first on PATH.
tw_run() {
  _tl=$1; shift
  DVOUT=$( cd "$d" && PATH="$_tw/bin:$PATH" KIT_TRACKER_USER=canary@example.com KIT_TRACKER_TOKEN=canary-token JIRA_EMAIL=canary@example.com JIRA_TOKEN=canary-token sh "$_tl" --base HEAD "$@" 2>&1 ) && DVRC=0 || DVRC=$?
}
# tw_logs -> one line per recorder that was hit; empty when none was.
tw_logs() { for _f in sec jira shim env; do [ -s "$_tw/$_f.log" ] && { printf '%s.log:' "$_f"; tr '\n' '|' < "$_tw/$_f.log"; echo; }; done; return 0; }
selftest_tripwire_lane() {
  tw_fx || { echo "PASS: tripwire/lane: N/A - no kit tree to take the real twin row from"; return 0; }
  _row=$(grep "^tracker-contract${TAB}" "$KROOT/conformance/prepush-twins.tsv" | cut -f4)
  _cf=$(printf '%s\n' "$_row" | sed -n 's/^.*--conf \([^ ]*\)$/\1/p')
  sfx "tripwire/lane: the twin row names a --conf path, and that path is not a file in the kit tree (an existing conf would end the credential-free argv)" "named-and-absent" \
    "$([ -n "$_cf" ] && [ ! -e "$KROOT/$_cf" ] && echo named-and-absent || echo "row=[$_row]")"
  tw_run "$LANE"
  sfx "tripwire/default: every recorder log is empty after the default run" "" "$(tw_logs)"
  tw_run "$LANE" --warranted
  want "tripwire/warranted: the tracker-contract twin ran, rc 2 as the row expects (the leg is not vacuous)" "^  OK    twin  *tracker-contract tracker-contract\\.sh --conf "
  want "tripwire/warranted: and so did the witness check" "^  OK    core-live  *envprobe"
  sfx "tripwire/warranted: every recorder log is empty after --warranted (no store call, no adapter call, no secret-store or network binary, no canary credential in a child)" "" "$(tw_logs)"
}
selftest_tripwire_positive() {
  tw_fx || { echo "PASS: tripwire/positive: N/A - no kit tree to take the real twin row from"; return 0; }
  # the same fixture tree, tracker-contract.sh run directly with the default conf: nothing scrubs and nothing is cut.
  ( cd "$d" && PATH="$_tw/bin:$PATH" sh conformance/tracker-contract.sh ) >/dev/null 2>&1 || :
  sfx "tripwire/positive: run unscrubbed on the fixture, tracker-contract.sh reaches the library's store call (the recorder is hit)" yes "$([ -s "$_tw/sec.log" ] && echo yes || echo no)"
  sfx "tripwire/positive: and then the adapter (the recorder is hit)" yes "$([ -s "$_tw/jira.log" ] && echo yes || echo no)"
  ( cd "$d" && KIT_TRACKER_TOKEN=canary-token sh conformance/envprobe.sh ) >/dev/null 2>&1 || :
  sfx "tripwire/positive: the witness records a canary credential when nothing scrubs it" yes "$([ -s "$_tw/env.log" ] && echo yes || echo no)"
  ( PATH="$_tw/bin:$PATH" curl --version ) >/dev/null 2>&1 || :
  sfx "tripwire/positive: a shimmed binary on PATH records its call" yes "$([ -s "$_tw/shim.log" ] && echo yes || echo no)"
}
# MUTANT: the lane without its KIT_ and JIRA_ unset must turn the tripwire red (the witness sees the canaries).
selftest_tripwire_scrub_mutant() {
  tw_fx || { echo "PASS: tripwire/mutant: N/A - no kit tree to take the real twin row from"; return 0; }
  _lm=$WORK/lane-no-kit-jira-scrub.sh
  sed -e 's/unset_pfx KIT_; //' -e '/^    unset_pfx JIRA_/d' "$LANE" > "$_lm"
  sfx "tripwire/mutant: the mutation changed the lane, kept the other unsets, and removed the JIRA_ line" "differs,1,0" \
    "$(cmp -s "$LANE" "$_lm" && echo same || echo differs),$(grep -c '^    unset_pfx GH_; unset_pfx GIT_; unset_pfx BOARD_CLAIM_; unset_pfx PREPUSH_$' "$_lm" || :),$(grep -c '^    unset_pfx JIRA_' "$_lm" || :)"
  tw_run "$_lm" --warranted
  sfx "tripwire/mutant: with the scrub dropped the witness records the canary, so the tripwire leg is RED" yes "$([ -s "$_tw/env.log" ] && echo yes || echo no)"
  : > "$_tw/env.log"; tw_run "$LANE" --warranted
  sfx "tripwire/mutant: and the real lane, run on the same fixture, leaves the witness silent (the canary was in the environment)" no "$([ -s "$_tw/env.log" ] && echo yes || echo no)"
}

# R2 (security L1): a credential-free conf that EXISTS at run time is read as a conf, so the twin is refused, named and UNVERIFIED, never run.
selftest_tripwire_conf_exists() {
  tw_fx || { echo "PASS: tripwire/conf-exists: N/A - no kit tree to take the real twin row from"; return 0; }
  # the planted conf points at the pinned host: if the twin ran, the library's store recorder and the adapter would be hit.
  cp "$d/.kit/tracker.conf" "$d/.kit/credential-free.conf"; commit_fx
  tw_run "$LANE" --warranted
  want "tripwire/conf-exists: the twin is refused by name" "^# REFUSED: twin tracker-contract names .kit/credential-free.conf as its credential-free conf, and that file exists"
  wantnot "tripwire/conf-exists: and it did not run" "^  OK    twin  *tracker-contract"
  sfx "tripwire/conf-exists: the verdict is UNVERIFIED, rc 1" "1" "$DVRC"
  want "tripwire/conf-exists: UNVERIFIED names the twin" "UNVERIFIED (twin tracker-contract: its credential-free conf"
  sfx "tripwire/conf-exists: and no recorder was hit" "" "$(tw_logs)"
  # MUTANT: the refusal removed from a lane copy -> the twin runs and the store recorder is hit, so the leg above is load-bearing.
  _lm=$WORK/lane-no-conf-refusal.sh
  sed -e '/^        if \[ -e "\$_cfp" \] || \[ -L "\$_cfp" \]; then$/s/.*/        if false; then/' "$LANE" > "$_lm"
  sfx "tripwire/conf-exists mutant: the mutation changed the lane" differs "$(cmp -s "$LANE" "$_lm" && echo same || echo differs)"
  tw_run "$_lm" --warranted
  sfx "tripwire/conf-exists mutant: without the refusal the planted conf reaches the store recorder (the leg is RED)" yes "$([ -s "$_tw/sec.log" ] && echo yes || echo no)"
}
# STANDING MUTANT: the old argv (no --conf) restored in the twin row must hit the store recorder, so the tripwire can see the regression.
selftest_tripwire_old_argv() {
  tw_fx || { echo "PASS: tripwire/old-argv: N/A - no kit tree to take the real twin row from"; return 0; }
  sed 's/tracker-contract\.sh --conf \.kit\/credential-free\.conf/tracker-contract.sh/' "$d/conformance/prepush-twins.tsv" > "$d/conformance/twins.new"
  mv "$d/conformance/twins.new" "$d/conformance/prepush-twins.tsv"; commit_fx
  tw_run "$LANE" --warranted
  sfx "tripwire/old-argv: with the old argv the twin reaches the library's store recorder" yes "$([ -s "$_tw/sec.log" ] && echo yes || echo no)"
  sfx "tripwire/old-argv: and then the adapter recorder" yes "$([ -s "$_tw/jira.log" ] && echo yes || echo no)"
}

# ===================================================================================================
# SWAS-468 — the touched-readers arm (design 2026-10-28-prepush-touched-readers-468-design.md as amended by the delta; cells TR8-TR13, TR15, LEARN).
# Every cell drives a FIXTURE repo through `--plan` (reads, never executes) or a real default run, and every cell is bound to a
# MUTANT: a sed on a COPY of the lane (the tripwire legs' idiom) that must turn the same scenario RED. A mutation that changes nothing fails its leg.
trmut() {   # trmut <name> <sed-arg…> -> TRM = a mutated copy of ${TRSRC:-$LANE}, or empty (with a FAIL) when the mutation changed nothing
  _mn=$1; shift; TRM=$WORK/lane-mut-$_mn.sh
  sed "$@" "${TRSRC:-$LANE}" > "$TRM"
  if cmp -s "${TRSRC:-$LANE}" "$TRM"; then echo "FAIL: $_mn: the mutation did not change the lane"; SF=1; TRM=""; fi
  TRSRC=""; return 0
}
selftest_touched_failclosed() {
  # the per-arm rule: no --derive output at all is UNVERIFIED (a lane copy whose derive step writes nothing)
  one_step; mkchk alpha 'exit 0'; commit_fx; mkchk gamma 'exit 0'
  _ed=$WORK/lane-emptyderive.sh
  sed 's#^  derive "\$_ci" > "\$WORK/derive.out" 2>&1 || { sed -n#  { find conformance -maxdepth 1 -type f -name "*.sh" -print > "$WORK/scripts"; : > "$WORK/derive.out"; } || { sed -n#' "$LANE" > "$_ed"
  sfx "TR9: the empty-derive lane copy differs" differs "$(cmp -s "$LANE" "$_ed" && echo same || echo differs)"
  DVOUT=$( cd "$d" && sh "$_ed" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "TR9: an empty --derive makes the arm UNVERIFIED, rc 1" 1 "$DVRC"
  want "TR9: and the verdict names it" '^PARITY-CORE: UNVERIFIED (touched-readers: no --derive output'
  TRSRC=$_ed trmut tr9c -e 's/^  if ! grep -q ..# ci-file:.* 2>\/dev\/null || \[ ! -f "\$WORK\/listing" \]; then$/  if false; then/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$d" && sh "$TRM" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
    wantnot "TR9 mutant: the empty-derive guard removed -> no UNVERIFIED (the cell is RED)" '^PARITY-CORE: UNVERIFIED (touched-readers'; }
}

# tr8_gate <root> — prints kit | offkit | spoofed. The marker test is off_kit (it reads the CURRENT directory, so cd);
# the anchor is the kit CI's own first line, the census liveness leg's test: no markers but the anchor present = spoofed.
tr8_gate() {
  _g=$1
  if ! ( cd "$_g" && off_kit ); then echo kit; return 0; fi
  if grep -q '^# Kit-own CI' "$_g/$CI_DEFAULT" 2>/dev/null; then echo spoofed; else echo offkit; fi
}
# tr8_noci <root> — rc 0 when the tree is off-kit AND has no default CI file (a GitLab adopter): TR8 then N/As.
# The existence test mirrors the lane's own (-e or -L), so a dangling symlink is not "no CI file".
tr8_noci() {
  _nr=$1
  [ "$(tr8_gate "$_nr")" = offkit ] || return 1
  [ -e "$_nr/$CI_DEFAULT" ] || [ -L "$_nr/$CI_DEFAULT" ] || return 0
  return 1
}
selftest_tr8_gitlab() {
  # cell 1: the refusal sentence, on a tree with .github/workflows but no ci.yml, and on a tree with no .github/ at all
  _g1=$(mkrepo); _g2=$(mkrepo); rm -r "$_g2/.github"
  for _t in "$_g1" "$_g2"; do
    DVOUT=$( cd "$_t" && unset KIT_CI_FILE && sh "$LANE" 2>&1 ) && DVRC=0 || DVRC=$?
    sfx "GL1: no default CI file and no --ci-file is rc 2" 2 "$DVRC"
    want "GL1: and it says plainly there is no GitHub Actions CI file" 'no GitHub Actions CI file'
  done
  DVOUT=$( cd "$_g1" && unset KIT_CI_FILE && sh "$LANE" --ci-file nope.yml 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "GL1: an explicit --ci-file naming nothing is rc 2" 2 "$DVRC"
  want "GL1: and it keeps today's message" 'ci-file: no such file'
  wantnot "GL1: without the new sentence" 'no GitHub Actions CI file'
  # cell 2: tr8_noci graded directly on three fixtures
  _n1=$(mktemp -d "${TMPDIR:-/tmp}/tr8n-XXXXXX"); _n2=$(mktemp -d "${TMPDIR:-/tmp}/tr8n-XXXXXX"); _n3=$(mktemp -d "${TMPDIR:-/tmp}/tr8n-XXXXXX")
  mkdir -p "$_n2/${CI_DEFAULT%/*}"; printf 'name: fx\n' > "$_n2/$CI_DEFAULT"
  mkdir -p "$_n3/docs"; : > "$_n3/docs/ROADMAP-KIT.md"
  sfx "GL2: off-kit with no CI file is yes" yes "$(tr8_noci "$_n1" && echo yes || echo no)"
  sfx "GL2: off-kit with a CI file is no" no "$(tr8_noci "$_n2" && echo yes || echo no)"
  sfx "GL2: a kit-marker tree with no CI file is no" no "$(tr8_noci "$_n3" && echo yes || echo no)"
  # MUTANTS GL1/GL3: the mutated helper's own text is extracted from a lane copy and run.
  trmut gl1 -e 's/^  \[ -e "\$_nr\/\$CI_DEFAULT" \].*$/  return 0/'
  [ -z "$TRM" ] || { sed -n '/^tr8_noci() {$/,/^}$/p' "$TRM" > "$WORK/tr8noci-a.sh"
    _res=$( . "$WORK/tr8noci-a.sh"; tr8_noci "$_n2" && echo yes || echo no )
    sfx "GL mutant M-GL1: the CI-file test removed -> off-kit with a CI file reads yes (the cell is RED)" yes "$_res"; }
  trmut gl3 -e 's/^  \[ "\$(tr8_gate "\$_nr")" = offkit \].*$/  :/'
  [ -z "$TRM" ] || { sed -n '/^tr8_noci() {$/,/^}$/p' "$TRM" > "$WORK/tr8noci-b.sh"
    _res=$( . "$WORK/tr8noci-b.sh"; tr8_noci "$_n3" && echo yes || echo no )
    sfx "GL mutant M-GL3: the off-kit test removed -> the kit-marker tree reads yes (the cell is RED)" yes "$_res"; }
  # MUTANTS GL2/GL2b: main is not selftest-only code, so the whole mutated copy runs in the fixture.
  trmut gl2 -e 's/^                \[ "\$_ci_given" -eq 1 \] || \[ -e "\$CI_DEFAULT" \].*$/                true ||/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$_g1" && unset KIT_CI_FILE && sh "$TRM" 2>&1 ) && DVRC=0 || DVRC=$?
    wantnot "GL mutant M-GL2: the default check removed -> no new sentence (the cell is RED)" 'no GitHub Actions CI file'
    sfx "GL mutant M-GL2: and it still stops with rc 2" 2 "$DVRC"
    want "GL mutant M-GL2: and it reaches resolve_ci's message" 'ci-file: no such file'; }
  trmut gl2b -e 's/_ci=\$2; _ci_given=1; shift/_ci=$2; shift/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$_g1" && unset KIT_CI_FILE && sh "$TRM" --ci-file nope.yml 2>&1 ) && DVRC=0 || DVRC=$?
    want "GL mutant M-GL2b: _ci_given never set by the flag -> the soft sentence (the cell is RED)" 'no GitHub Actions CI file'; }
}
selftest_tr8_gate() {
  _ga=$(mktemp -d "${TMPDIR:-/tmp}/tr8g-XXXXXX"); _gk=$(mktemp -d "${TMPDIR:-/tmp}/tr8g-XXXXXX"); _gs=$(mktemp -d "${TMPDIR:-/tmp}/tr8g-XXXXXX")
  for _r in "$_ga" "$_gk" "$_gs"; do mkdir -p "$_r/${CI_DEFAULT%/*}"; printf 'name: fx\n' > "$_r/$CI_DEFAULT"; done
  mkdir -p "$_gk/docs"; : > "$_gk/docs/ROADMAP-KIT.md"
  printf '# Kit-own CI - spoofed\nname: fx\n' > "$_gs/$CI_DEFAULT"
  sfx "TR8 gate: no marker and no anchor reads offkit" offkit "$(tr8_gate "$_ga")"
  sfx "TR8 gate: a kit marker reads kit" kit "$(tr8_gate "$_gk")"
  sfx "TR8 gate: no marker but the kit CI anchor reads spoofed" spoofed "$(tr8_gate "$_gs")"
  # MUTANTS: the mutated helper's own text is extracted from a lane copy and run.
  trmut tr8ga -e 's/^  if ! ( cd .* off_kit ); then echo kit; return 0; fi$/  if false; then echo kit; return 0; fi/'
  [ -z "$TRM" ] || { sed -n '/^tr8_gate() {$/,/^}$/p' "$TRM" > "$WORK/tr8gate-a.sh"
    _res=$( . "$WORK/tr8gate-a.sh"; tr8_gate "$_gk" )
    sfx "TR8 gate mutant M-TR8a: the marker test made false -> the kit fixture no longer reads kit (the cell is RED)" differs "$([ "$_res" = kit ] && echo same || echo differs)"; }
  trmut tr8gb -e "s/^  if grep -q '^# Kit-own CI'.*\$/  echo offkit/"
  [ -z "$TRM" ] || { sed -n '/^tr8_gate() {$/,/^}$/p' "$TRM" > "$WORK/tr8gate-b.sh"
    _res=$( . "$WORK/tr8gate-b.sh"; tr8_gate "$_gs" )
    sfx "TR8 gate mutant M-TR8b: the anchor test removed -> the spoofed fixture no longer reads spoofed (the cell is RED)" differs "$([ "$_res" = spoofed ] && echo same || echo differs)"; }
}

selftest_touched_replay() {
  [ -f "$KROOT/conformance/agent-autonomy.sh" ] && [ -f "$KROOT/conformance/citation-live.sh" ] && [ -f "$KROOT/conformance/prepush-lane.sh" ] ||
    { echo "PASS: TR8: N/A - not the kit tree"; return 0; }
  _pb=$(git -C "$KROOT" rev-parse HEAD~1 2>/dev/null) || { echo "PASS: TR8: N/A - no parent commit to take a listing from"; return 0; }
  DVOUT=$( cd "$KROOT" && unset KIT_CI_FILE && sh "$LANE" --plan --base "$_pb" 2>&1 ) && DVRC=0 || DVRC=$?
  if tr8_noci "$KROOT"; then
    sfx "TR8: a tree with no GitHub CI file refuses the plan, rc 2" 2 "$DVRC"
    want "TR8: and says there is no GitHub Actions CI file" 'no GitHub Actions CI file'
    echo "PASS: TR8: N/A - no GitHub CI file to plan from (the lane derives from .github/workflows/ci.yml only)"
    return 0
  fi
  sfx "TR8: the plan on the real tree is rc 0" 0 "$DVRC"
  [ "$DVRC" -ne 0 ] || echo "PASS: TR8: measured on this tree [M] — $(printf '%s\n' "$DVOUT" | sed -n 's/^# touched-readers: \([0-9]* candidate.*\) · budget.*$/\1/p')"
  case $(tr8_gate "$KROOT") in
    kit) ;;
    offkit)   # rc 0 above is the twin-table assertion (a MALFORMED row makes --plan return 1); the greps are a belt
      wantnot "TR8 off the kit tree: no malformed twin table" '^# TWIN-TABLE MALFORMED'
      wantnot "TR8 off the kit tree: no UNVERIFIED parity verdict" '^PARITY-CORE: UNVERIFIED'
      sfx "TR8 off the kit tree: the shipped twin table is present" yes "$([ -f "$KROOT/$TWINS_REL" ] && echo yes || echo no)"
      echo "PASS: TR8 (a)-(c) and its mutant: N/A - not the kit tree (they plan kit-only CI steps: agent-autonomy --selftest, prepush-lane --census, citation-live)"
      return 0 ;;
    *) echo "FAIL: TR8: the kit markers are gone but the CI file is the kit's own (# Kit-own CI)"; SF=1; return 0 ;;
  esac
  want "TR8 (a) under an EMPTY table: S7 in agent-autonomy --selftest runs" '^  PLAN  touched-readers  *agent-autonomy --selftest '
  want "TR8 (b) under an EMPTY table: the prepush-twins census runs" '^  PLAN  touched-readers  *prepush-lane --census '
  want "TR8 (c) under an EMPTY table: citation-live runs" '^  PLAN  touched-readers  *citation-live '
  _h=$WORK/tr8home; _rc0=$(git -C "$KROOT" rev-list --max-parents=0 HEAD | sed -n 1p); _sd=$_h/.local/state/sparkwright/prepush/$_rc0; ( umask 077; mkdir -p "$_sd" )
  _now=$(date +%s)
  { printf 'agent-autonomy\t--selftest\t97\t2\tci\t%s\n' "$_now"; printf 'prepush-lane\t--census\t21\t2\tci\t%s\n' "$_now"
    printf 'citation-live\t\t3\t0\tci\t%s\n' "$_now"; printf 'conformance-mass-budget\t\t62\t0\tci\t%s\n' "$_now"; } > "$_sd/times.tsv"
  DVOUT=$( cd "$KROOT" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --plan --base "$_pb" 2>&1 ) && DVRC=0 || DVRC=$?
  want "TR8 (a) under the #914 table with reds30: S7 runs, in the red-history tier" '^  PLAN  touched-readers  *agent-autonomy --selftest .*\[red-history\]'
  want "TR8 (b) under the #914 table: the census runs, in the red-history tier"     '^  PLAN  touched-readers  *prepush-lane --census .*\[red-history\]'
  want "TR8 (c) under the #914 table: citation-live runs" '^  PLAN  touched-readers  *citation-live '
  wantnot "TR8 (a): and S7 is not cut short of its time (the budget is not spent on 100 cheap checks first)" '^  PLAN  touched-readers  *agent-autonomy --selftest .*CUT:'
  sfx "TR8 (a): and S7, in the red-history tier, is the first plan line" same "$(printf '%s\n' "$DVOUT" | grep '^  PLAN  touched-readers' | sed -n 1p | grep -q 'agent-autonomy --selftest' && echo same || echo differs)"
  trmut tr8a -e 's/-k1,1n -k2,2n -k3,3/-k2,2n -k3,3/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$KROOT" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --plan --base "$_pb" 2>&1 ) && DVRC=0 || DVRC=$?
    sfx "TR8 mutant: fastest-first ordering -> S7 is left behind the cheap checks, no longer the first plan line (the cell is RED)" differs "$(printf '%s\n' "$DVOUT" | grep '^  PLAN  touched-readers' | sed -n 1p | grep -q 'agent-autonomy --selftest' && echo same || echo differs)"; }
}

trtab() {   # trtab <home> <printf-rows-file-content already written to $WORK/trtab.rows> — put the rows where the lane under test looks
  _rc0=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p ); _sd=$1/.local/state/sparkwright/prepush/$_rc0
  ( umask 077; mkdir -p "$_sd" ); cp "$WORK/trtab.rows" "$_sd/times.tsv"
}
selftest_touched_budget() {
  _sc=$WORK/lane-scaled-a.sh; _sb=$WORK/lane-scaled-b.sh
  sed -e 's/^TR_CEIL_MIN=120$/TR_CEIL_MIN=2/' -e 's/^TR_BUDGET_DEFAULT=300$/TR_BUDGET_DEFAULT=4/' "$LANE" > "$_sc"
  sed -e 's/^TR_CEIL_MIN=120$/TR_CEIL_MIN=10/' -e 's/^TR_BUDGET_DEFAULT=300$/TR_BUDGET_DEFAULT=4/' "$LANE" > "$_sb"
  sfx "TR-scale: the scaled lane copies differ" differs "$(cmp -s "$LANE" "$_sc" || cmp -s "$LANE" "$_sb" && echo same || echo differs)"
  # TR10 — a check killed at the ceiling is LISTED, neither FAIL nor UNVERIFIED
  mkcin 'sh conformance/slow.sh'; commit_fx; mkchk slow 'sleep 8'
  _now=$(date +%s); printf 'slow\t\t1\t0\tlocal\t%s\n' "$_now" > "$WORK/trtab.rows"; _h=$WORK/trbh0; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_sc" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "TR10: a check killed at the local ceiling is listed CI-GRADED with the ceiling" '^CI-GRADED: slow (local ceiling hit at [0-9]* s'
  wantnot "TR10: and it is not a FAIL" '^  FAIL  '
  sfx "TR10: and the verdict is not UNVERIFIED or FAIL (rc 0)" 0 "$DVRC"
  TRSRC=$_sc trmut tr10 -e 's/if \[ "\$RUN_S" -ge "\$_cl" \]; then tr_ci/if [ "$RUN_S" -lt 0 ]; then tr_ci/'
  [ -z "$TRM" ] || { _h=$WORK/trbh0b; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
    want "TR10 mutant: the kill read as a FAIL (the cell is RED)" '^  FAIL  touched-readers'; }
  # TR11 — the budget is charged with MEASURED wall: a check predicted at 1 s that takes 3 s leaves too little for the next, predicted at 2 s
  mkcin 'sh conformance/ba.sh' 'sh conformance/bb.sh'; commit_fx; mkchk ba 'sleep 3'; mkchk bb 'exit 0'
  _h=$WORK/trbh; _now=$(date +%s)
  { printf 'ba\t\t1\t0\tlocal\t%s\n' "$_now"; printf 'bb\t\t2\t0\tlocal\t%s\n' "$_now"; } > "$WORK/trtab.rows"; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_sb" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "TR11: the first check ran" '^  OK    touched-readers  *ba '
  want "TR11: the second is listed, the budget spent by the first measured 3 s (not its predicted 1 s)" '^CI-GRADED: bb (budget spent'
  _rc0=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p )
  sfx "TR-record: the measured wall of the check that ran is appended as a local row (the next run's time)" "local" "$(awk -F'\t' '$1 == "ba" && $3 + 0 >= 3 { r = $5 } END { print r }' "$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null)"
  TRSRC=$_sb trmut tr11 -e 's/_rem=\$((_rem - RUN_S))/_rem=$((_rem - _pred))/'
  [ -z "$TRM" ] || { _h=$WORK/trbh2; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
    want "TR11 mutant: charging the prediction lets the second run (the cell is RED)" '^  OK    touched-readers  *bb '; }
  # TR15 — a forged 9999 s row: a red-history check still runs; any other is LISTED, visibly
  mkcin 'sh conformance/fa.sh' 'sh conformance/fc.sh'; commit_fx; mkchk fa 'exit 0'; mkchk fc 'exit 0'
  { printf 'fa\t\t9999\t1\tlocal\t%s\n' "$_now"; printf 'fc\t\t9999\t0\tlocal\t%s\n' "$_now"; } > "$WORK/trtab.rows"; _h=$WORK/trbh3; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_sb" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "TR15: the red-history check with a forged 9999 s row still runs, in tier 1" '^  OK    touched-readers  *fa .*\[red-history\]'
  want "TR15: the other check with a forged row is listed, visibly, with the predicted time" '^CI-GRADED: fc (budget spent: predicted 9999 s'
  TRSRC=$_sb trmut tr15 -e 's/^    if \[ "\$_tier" = 1 \]; then _go=0;/    if false; then _go=0;/'
  [ -z "$TRM" ] || { _h=$WORK/trbh4; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
    wantnot "TR15 mutant: a forged row drops the red-history check silently (the cell is RED)" '^  OK    touched-readers  *fa '; }
  # a tier-1 check cut by the budget says "budget spent", not "ceiling hit"
  mkcin 'sh conformance/sl.sh'; commit_fx; mkchk sl 'sleep 8'
  printf 'sl\t\t1\t1\tlocal\t%s\n' "$_now" > "$WORK/trtab.rows"; _h=$WORK/trbh6; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_sb" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "TR10b: a red-history check killed by the shrunk budget is listed as budget spent" '^CI-GRADED: sl (budget spent: only 4 s of the budget was left'
  # M3: a child that edits the lane's own scratch files cannot change the run order or the table
  mkcin 'sh conformance/ma.sh' 'sh conformance/mb.sh'; commit_fx
  mkchk ma 'printf junk > "$TMPDIR/tr.ord"; printf junk > "$TMPDIR/tr.tab"; rm -f "$TMPDIR"/tr.*; exit 0'; mkchk mb 'exit 0'
  { printf 'ma\t\t1\t0\tlocal\t%s\n' "$_now"; printf 'mb\t\t2\t0\tlocal\t%s\n' "$_now"; printf '@job\tj1\t3600\t0\tci\t%s\n' "$_now"; } > "$WORK/trtab.rows"; _h=$WORK/trbh7; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_sb" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "M3: after a child edits the scratch files the run order is unchanged (ma then mb, both OK)" "ma mb" "$(printf '%s\n' "$DVOUT" | sed -n 's/^  OK    touched-readers  *\(m[ab]\) .*$/\1/p' | tr '\n' ' ' | sed 's/ $//')"
  # TR9b — a refused state dir is UNVERIFIED, never a silent fallback
  _h=$WORK/trbh5; trtab "$_h"; chmod 777 "$_sd"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  chmod 700 "$_sd"
  want "TR9b: a group/world-writable state dir makes the arm UNVERIFIED" '^PARITY-CORE: UNVERIFIED (touched-readers: the state dir is refused'
  # B8 (SWAS-840, P1 of SWAS-858) — a NAMED reader: a derived check whose own script text, comment-stripped, names a listed path literally runs regardless of the 300 s fill (and of its measured time),
  # while it fits the readers cap; a check with the same 400 s row that does not name it, or names it only in a comment, is CI-graded as before
  mkci <<'YAML'
jobs:
  j1:
    steps:
      - run: sh conformance/rdr.sh --selftest
      - run: sh conformance/plain.sh
      - run: sh conformance/rdc.sh
YAML
  mkchk rdr ': scripts/preflight.sh'; mkchk plain 'exit 0'; mkchk rdc '# only a comment names scripts/preflight.sh
exit 0'
  commit_fx; mkdir -p "$d/scripts"; printf '#!/bin/sh\nexit 0\n' > "$d/scripts/preflight.sh"
  _now=$(date +%s); _h=$WORK/trb8
  { printf 'rdr\t--selftest\t400\t0\tlocal\t%s\n' "$_now"; printf 'plain\t\t400\t0\tlocal\t%s\n' "$_now"; printf 'rdc\t\t400\t0\tlocal\t%s\n' "$_now"; } > "$WORK/trtab.rows"; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "B8: rc 0" 0 "$DVRC"
  want "B8: a check naming the touched path runs over the 300 s fill, tagged a named reader" '^  OK    touched-readers  *rdr --selftest .*\[named reader\]'
  want "B8: a non-naming check with the same 400 s row is CI-graded, budget spent" '^CI-GRADED: plain (budget spent: predicted 400 s'
  want "B8: a check that names the path only in a comment is not a named reader" '^CI-GRADED: rdc (budget spent: predicted 400 s'
  trmut b8a -e '/# TRNAMED$/s/then _nm=1;/then _nm=0;/'
  [ -z "$TRM" ] || { _h=$WORK/trb8a; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    want "B8 mutant: with the named-reader test off the naming check is CI-graded (the cell is RED)" '^CI-GRADED: rdr --selftest (budget spent'; }
  trmut b8b -e '/# TRNAMED$/s|sed [^ ]* |cat |'
  [ -z "$TRM" ] || { _h=$WORK/trb8b; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    want "B8 mutant: with the comment-strip gone the comment-only check runs (the cell is RED)" '^  OK    touched-readers  *rdc '; }
  # B12 — --plan prints the fill and the cap, and tags the named reader
  _h=$WORK/trb12; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD --plan 2>&1 ) && DVRC=0 || DVRC=$?
  want "B12: the readers note prints the fill and the cap" '^# touched-readers: .* · budget 300s (the fill) · cap 600s \[printed\]'
  want "B12: --plan tags the named reader" '^  PLAN  touched-readers  *rdr --selftest .*\[named reader\]'
  trmut b12 -e '/# TRTAG$/d'
  [ -z "$TRM" ] || { _h=$WORK/trb12m; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD --plan 2>&1 ) || :
    wantnot "B12 mutant: with the tag dropped the plan no longer names the reader (the cell is RED)" '\[named reader\]'; }
  # B9 (errata C1) — the readers cap: a lane copy with TR_CAP=5 and a 2 s fill; two named readers recorded at 4 s each: the first runs, the second does not fit the cap left and is CI-graded
  _s9=$WORK/lane-cap5.sh; sed -e 's/^TR_CAP=600$/TR_CAP=5/' -e 's/^TR_BUDGET_DEFAULT=300$/TR_BUDGET_DEFAULT=2/' "$LANE" > "$_s9"
  sfx "B9: the cap-scaled lane copy differs" differs "$(cmp -s "$LANE" "$_s9" && echo same || echo differs)"
  mkcin 'sh conformance/rd1.sh' 'sh conformance/rd2.sh'; mkchk rd1 'sleep 2; : scripts/preflight.sh'; mkchk rd2 'sleep 2; : scripts/preflight.sh'
  commit_fx; mkdir -p "$d/scripts"; printf '#!/bin/sh\nexit 0\n' > "$d/scripts/preflight.sh"
  { printf 'rd1\t\t4\t0\tlocal\t%s\n' "$_now"; printf 'rd2\t\t4\t0\tlocal\t%s\n' "$_now"; } > "$WORK/trtab.rows"; _h=$WORK/trb9; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_s9" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "B9: the first named reader runs inside the cap" '^  OK    touched-readers  *rd1 .*\[named reader\]'
  want "B9: the second does not fit the cap left and is CI-graded over the cap" '^CI-GRADED: rd2 (over the 5 s readers cap: measured 4 s, [0-9]* s left \[measured\]'
  _u=$(printf '%s\n' "$DVOUT" | sed -n 's/^# touched-readers: [0-9]* run (\([0-9]*\) s.*$/\1/p')
  sfx "B9: the seconds the arm charged stay within the cap" yes "$([ "${_u:-99}" -le 5 ] && echo yes || echo no)"
  TRSRC=$_s9 trmut b9 -e '/# TRCAP$/s/if .*; then/if true; then/'
  [ -z "$TRM" ] || { _h=$WORK/trb9m; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    wantnot "B9 mutant: with the cap check removed the second reader is not held to the cap (the cell is RED)" 'over the 5 s readers cap'; }
  # B13 (review M1) — EVERY named reader takes the cap path, never the fill: a copy with a 2 s fill and a 10 s cap; a named reader recorded at 1 s that runs 3 s reads OK, tagged a named reader
  _s1=$WORK/lane-cap10.sh; sed -e 's/^TR_CAP=600$/TR_CAP=10/' -e 's/^TR_BUDGET_DEFAULT=300$/TR_BUDGET_DEFAULT=2/' "$LANE" > "$_s1"
  sfx "B13: the cap-scaled lane copy differs" differs "$(cmp -s "$LANE" "$_s1" && echo same || echo differs)"
  mkcin 'sh conformance/rdk.sh'; mkchk rdk 'sleep 3; : scripts/preflight.sh'
  commit_fx; mkdir -p "$d/scripts"; printf '#!/bin/sh\nexit 0\n' > "$d/scripts/preflight.sh"
  printf 'rdk\t\t1\t0\tlocal\t%s\n' "$_now" > "$WORK/trtab.rows"; _h=$WORK/trb13; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_s1" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "B13: the named reader runs past the 2 s fill under the cap and reads OK, tagged a named reader" '^  OK    touched-readers  *rdk .*\[named reader\]'
  wantnot "B13: and it is never read as budget spent" 'budget spent: only'
  TRSRC=$_s1 trmut b13 -e '/# TRNAMEGO$/s/if .*; then/if [ "$_go" -eq 0 ] \&\& [ "$_nm" = 1 ]; then/'
  [ -z "$TRM" ] || { _h=$WORK/trb13m; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    want "B13 mutant: with the old branch the fill cuts the named reader's ceiling (the cell is RED)" '^CI-GRADED: rdk (budget spent: only'; }
  # B14 (review m1) — a named reader killed at its ceiling leaves a floor: the next run predicts it and lists it over the cap as a floor (a copy with a 2 s fill and a 4 s cap)
  _s2=$WORK/lane-cap4.sh; sed -e 's/^TR_CAP=600$/TR_CAP=4/' -e 's/^TR_BUDGET_DEFAULT=300$/TR_BUDGET_DEFAULT=2/' "$LANE" > "$_s2"
  sfx "B14: the 4 s cap copy differs" differs "$(cmp -s "$LANE" "$_s2" && echo same || echo differs)"
  mkcin 'sh conformance/rdf.sh'; mkchk rdf 'sleep 10; : scripts/preflight.sh'
  commit_fx; mkdir -p "$d/scripts"; printf '#!/bin/sh\nexit 0\n' > "$d/scripts/preflight.sh"
  printf 'rdf\t\t1\t0\tlocal\t%s\n' "$_now" > "$WORK/trtab.rows"; _h=$WORK/trb14; trtab "$_h"
  _rc0=$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_s2" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "B14: the first run kills it at the cap and lists it as a ceiling hit" '^CI-GRADED: rdf (local ceiling hit at'
  sfx "B14: the kill leaves a floor row of ceiling + 1 s = 5, which the clamp to cap + 1 s keeps (the full cap is 4)" 5 "$(awk -F'\t' '$1 == "@reader-k" && $2 == "rdf" { print $3 }' "$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null | sed -n '$p')"
  TRSRC=$_s2 trmut b14a -e '/# TRREC$/s/\[ "\$_ncf" -eq 0 \] || { _fv=/[ 1 -eq 1 ] || { _fv=/'
  [ -z "$TRM" ] || { _h2=$WORK/trb14a; trtab "$_h2"; DVOUT=$( cd "$d" && HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    sfx "B14 mutant: with the recording off no floor row is left (the cell is RED)" "" "$(awk -F'\t' '$1 == "@reader-k" { print $3 }' "$_h2/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null)"; }
  TRSRC=$_s2 trmut b14b -e '/# TRREC$/s/-le \$((TR_CAPE + 1)) \] || _fv=\$((TR_CAPE + 1));/-le 0 ] || _fv=$TR_CAPE;/'
  [ -z "$TRM" ] || { _h2=$WORK/trb14b; trtab "$_h2"; DVOUT=$( cd "$d" && HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    sfx "B14 mutant: with the old clamp to the full cap the floor is 4 and the reader would run and be killed again (the cell is RED)" 4 "$(awk -F'\t' '$1 == "@reader-k" && $2 == "rdf" { print $3 }' "$_h2/.local/state/sparkwright/prepush/$_rc0/times.tsv" 2>/dev/null | sed -n '$p')"; }
  # the next runs: a fast stub (uncommitted, so the listing is unchanged), the floor the first run actually wrote (home $_h), then a floor 31 days old
  mkchk rdf ': scripts/preflight.sh'
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_s2" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "B14: the floor the kill wrote lists the reader over the cap next time, as a local floor, naming the way out" '^CI-GRADED: rdf (over the 4 s readers cap: measured >=5 s, 4 s left \[measured\]; a kill left this floor: re-run with PREPUSH_NO_CACHE=1 for one run, or delete the @reader-k row for it in times.tsv'
  { printf 'rdf\t\t1\t0\tlocal\t%s\n' "$_now"; printf '@reader-k\trdf\t5\t0\tlocal\t%s\n' "$((_now - 31 * 86400))"; } > "$WORK/trtab.rows"; _h=$WORK/trb14d; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_s2" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  wantnot "B14: a floor 31 days old no longer lists the reader over the cap" 'over the 4 s readers cap'
  want "B14: and the reader runs again" '^  OK    touched-readers  *rdf '
  TRSRC=$_s2 trmut b14c -e 's/if (\$1 == "@reader-k" && NOW - \$6 > REDS) next; //'
  [ -z "$TRM" ] || { _h2=$WORK/trb14e; trtab "$_h2"; DVOUT=$( cd "$d" && HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    want "B14 mutant: with no expiry the 31-day-old floor still lists the reader over the cap (the cell is RED)" 'over the 4 s readers cap'; }
  # B15 (security) — a clipped, non-named reader that exits 143 by itself, early, is a FAIL, never "budget spent" (the kill is read from the time, as for the ceiling)
  mkcin 'sh conformance/ex.sh'; mkchk ex 'exit 143'; commit_fx; : > "$d/x.md"
  printf 'ex\t\t1\t0\tlocal\t%s\n' "$_now" > "$WORK/trtab.rows"; _h=$WORK/trb15; trtab "$_h"
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_sb" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "B15: an early exit 143 under a clipped ceiling reads FAIL" '^  FAIL  touched-readers'
  wantnot "B15: and it is not named budget spent" 'budget spent: only'
  TRSRC=$_sb trmut b15 -e '/# TRBS$/s/ \&\& \[ "\$RUN_S" -ge "\$_cl" \]//'
  [ -z "$TRM" ] || { _h=$WORK/trb15m; trtab "$_h"; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :
    want "B15 mutant: without the time conjunct the early exit reads budget spent (the cell is RED)" '^CI-GRADED: ex (budget spent: only'; }
  # B11 — the lane's own selftest as an UNTOUCHED reader stays CI-graded, and its reason says it is long
  mkcin 'sh conformance/prepush-lane.sh --selftest'; mkchk prepush-lane 'exit 0'; commit_fx; : > "$d/x.md"
  rn "$d"
  want "B11: the lane's own selftest stays CI-graded and its reason says it is long and runs when the lane is touched" "^CI-GRADED: prepush-lane --selftest (the lane.s own selftest is long; it runs here when the lane is touched"
  wantnot "B11: and no kit timing reaches the output" "852 s"
  wantnot "B11: and no CI run id reaches the output" "43228653287"
  trmut b11 -e 's/the lane.s own selftest is long; it runs here when the lane is touched/CI binds it/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d"; wantnot "B11 mutant: with the reason text gone the line is the old reason (the cell is RED)" 'selftest is long'; }
}

selftest_touched_output() {
  mkci <<'YAML'
jobs:
  guard-delta:
    steps:
      - run: |
          git fetch
          sh conformance/alpha.sh --grade-cells
      - run: sh conformance/beta.sh; echo done
  other:
    steps:
      - run: sh conformance/alpha.sh
  third:
    steps:
      - run: sh conformance/gamma.sh
YAML
  mkchk beta 'touch ran.marker'; commit_fx; mkchk gamma 'exit 0'
  _h=$WORK/trout; _now=$(date +%s)
  { printf '@job\tguard-delta\t6368\t0\tci\t%s\n' "$_now"; printf '@job\tother\t1140\t20\tci\t%s\n' "$_now"
    printf '@job\tthird\t600\t20\tci\t%s\n' "$_now"; printf '@green\tall\t21780\t0\tci\t%s\n' "$_now"; } > "$WORK/trtab.rows"; trtab "$_h"
  _o=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --base HEAD 2>&1 ) && _r=0 || _r=$?; DVOUT=$_o
  sfx "TR12: the run is rc 0" 0 "$_r"
  sfx "TR12: a context mention is never executed" "" "$(ls "$d/ran.marker" 2>/dev/null)"
  sfx "TR12: two basename-less context steps of one job are listed ONCE" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^CI-GRADED: guard-delta' || :)"
  want "TR13: a guard-delta-shaped context prints CI-GRADED with its cost (job wall to red, job-min per red)" '^CI-GRADED: guard-delta.*~106 min to red.*~363 job-min per red'
  want "TR13: a job at 19 of 20 min prints TIMEOUT-RISK" '^TIMEOUT-RISK: other .*19.0 of 20 min'
  wantnot "TR13: a job at 10 of 20 min does not" '^TIMEOUT-RISK: third '
  want "TR12: the paste block is headed" '^CI-ONLY (paste into the PR):'
  trmut tr12 -e 's/\*"\$NL\$_job\$NL"\*) ;;/__never__) ;;/'
  [ -z "$TRM" ] || { _o=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :; DVOUT=$_o
    sfx "TR12 mutant: duplicate rows per job (the cell is RED)" 2 "$(printf '%s\n' "$DVOUT" | grep -c '^CI-GRADED: guard-delta' || :)"; }
  trmut tr13a -e 's/\[ \$((L_SEC \* 100)) -ge /[ $((L_SEC * 100)) -lt /'
  [ -z "$TRM" ] || { _o=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :; DVOUT=$_o
    want "TR13 mutant: the threshold inverted -> the calm job is flagged (the cell is RED)" '^TIMEOUT-RISK: third '; }
  trmut tr13b -e 's/^  while IFS= read -r _cx; do$/  while false; do/'
  [ -z "$TRM" ] || { _o=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$TRM" --base HEAD 2>&1 ) || :; DVOUT=$_o
    wantnot "TR13 mutant: the context listing dropped (the cell is RED)" '^CI-GRADED: guard-delta'; }
}

selftest_touched_refresh() {
  mkci <<'YAML'
jobs:
  job-a:
    timeout-minutes: 20
    steps:
      - name: My step
        run: sh conformance/alpha.sh
      - name: Other step
        run: sh conformance/beta.sh
YAML
  commit_fx; _g=$WORK/fakegh; mkdir -p "$_g"
  cat > "$_g/gh" <<'GH'
#!/bin/sh
case "$*" in
  *status=failure*) printf '333\t%s\n' "$(date +%s)" ;;
  *event=push*) echo 111 ;;
  *event=pull_request*) echo 222 ;;
  *runs/333/*) printf 'Other step\n' ;;
  *runs/111/*'.steps[]'*) printf 'job-a\tMy step\t97\n' ;;
  *runs/111/*) printf 'job-a\t1140\n' ;;
  *runs/222/*) printf 'job-a\t21780\n' ;;
esac
GH
  chmod 755 "$_g/gh"; _h=$WORK/trref
  DVOUT=$( cd "$d" && PATH=$_g:$PATH HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --refresh-times 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "refresh: rc 0" 0 "$DVRC"
  _rc0=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p ); _t=$_h/.local/state/sparkwright/prepush/$_rc0/times.tsv
  sfx "refresh: the step row carries the CI wall" "alpha		97	0	ci" "$(awk -F'\t' '$1=="alpha" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }' "$_t" 2>/dev/null)"
  sfx "refresh: a failed step becomes a RED row (count, source red) for its invocation, mapped by step name" "beta		0	1	red" "$(awk -F'\t' '$1=="beta" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }' "$_t" 2>/dev/null)"
  # the red history LEARNS: beta had no red row and no seed, and is now tier 1; alpha is not
  : > "$d/x.md"      # untracked = in the listing, so the plan has something to order
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --plan --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "LEARN: a check with no prior red row that failed once in CI is in tier 1 (red-history)" '^  PLAN  touched-readers  *beta .*\[red-history\]'
  want "LEARN: and the check that never failed is not" '^  PLAN  touched-readers  *alpha .*\[measured\]'
  trmut learn -e 's/^  while IFS="\$TAB" read -r _bid _bts <&7; do$/  while false; do/'
  [ -z "$TRM" ] || { _h2=$WORK/trref2; DVOUT=$( cd "$d" && PATH=$_g:$PATH HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$TRM" --refresh-times 2>&1 ) || :
    DVOUT=$( cd "$d" && HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$LANE" --plan --base HEAD 2>&1 ) || :
    wantnot "LEARN mutant: the failed-job ingestion dropped -> beta stays measured (the cell is RED)" '^  PLAN  touched-readers  *beta .*\[red-history\]'; }
  trmut learn2 -e 's/if (nm in fails) print/if (0) print/'
  [ -z "$TRM" ] || { _h2=$WORK/trref3; DVOUT=$( cd "$d" && PATH=$_g:$PATH HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$TRM" --refresh-times 2>&1 ) || :
    DVOUT=$( cd "$d" && HOME=$_h2 PREPUSH_NO_CACHE=0 sh "$LANE" --plan --base HEAD 2>&1 ) || :
    wantnot "LEARN mutant 2: the failed step never becomes a red row -> beta stays measured (the cell is RED)" '^  PLAN  touched-readers  *beta .*\[red-history\]'; }
  # AGEING: a red row older than 30 days is not tier 1; a fresh one is
  _h3=$WORK/trage; _old=$(( $(date +%s) - 31 * 86400 )); _new=$(( $(date +%s) - 29 * 86400 ))
  printf 'beta\t\t0\t3\tred\t%s\n' "$_old" > "$WORK/trtab.rows"; trtab "$_h3"
  DVOUT=$( cd "$d" && HOME=$_h3 PREPUSH_NO_CACHE=0 sh "$LANE" --plan --base HEAD 2>&1 ) || :
  want "AGE: a red row 31 days old is not tier 1" '^  PLAN  touched-readers  *beta .*\[measured\]'
  printf 'beta\t\t0\t3\tred\t%s\n' "$_new" > "$WORK/trtab.rows"; trtab "$_h3"
  DVOUT=$( cd "$d" && HOME=$_h3 PREPUSH_NO_CACHE=0 sh "$LANE" --plan --base HEAD 2>&1 ) || :
  want "AGE: and one 29 days old is" '^  PLAN  touched-readers  *beta .*\[red-history\]'
  printf 'beta\t\t0\t3\tred\t%s\n' "$_old" > "$WORK/trtab.rows"; trtab "$_h3"
  trmut age -e 's/NOW - \$6 <= REDS && //'
  [ -z "$TRM" ] || { DVOUT=$( cd "$d" && HOME=$_h3 PREPUSH_NO_CACHE=0 sh "$TRM" --plan --base HEAD 2>&1 ) || :
    want "AGE mutant: no age filter -> a 31-day-old red row is tier 1 (the cell is RED)" '^  PLAN  touched-readers  *beta .*\[red-history\]'; }
  # M1: a failing gh KEEPS the old rows and is rc 1 (a failure must not wipe the red history)
  _gb=$WORK/badgh; mkdir -p "$_gb"; printf '#!/bin/sh\nexit 1\n' > "$_gb/gh"; chmod 755 "$_gb/gh"
  printf 'beta\t\t0\t2\tred\t%s\n' "$(date +%s)" > "$WORK/trtab.rows"; _h4=$WORK/trkeep; trtab "$_h4"
  _t4=$_h4/.local/state/sparkwright/prepush/$_rc0/times.tsv
  DVOUT=$( cd "$d" && PATH=$_gb:$PATH HOME=$_h4 PREPUSH_NO_CACHE=0 sh "$LANE" --refresh-times 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "M1: a failing gh is rc 1" 1 "$DVRC"
  sfx "M1: and the old red row is KEPT (count still 2)" "beta		0	2	red" "$(awk -F'\t' '$1=="beta" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }' "$_t4" 2>/dev/null)"
  want "M1: and says so" '^# times: gh failed or returned nothing'
  trmut m1 -e 's/^  \[ "\$_gf" -eq 0 \] || { note "times: gh failed.*$/  :/'
  [ -z "$TRM" ] || { trtab "$_h4"; DVOUT=$( cd "$d" && PATH=$_gb:$PATH HOME=$_h4 PREPUSH_NO_CACHE=0 sh "$TRM" --refresh-times 2>&1 ) && DVRC=0 || DVRC=$?
    sfx "M1 mutant: the guard dropped -> the failure wipes the red row and exits 0 (the cell is RED)" "0|" "$DVRC|$(awk -F'\t' '$1=="beta" { print $4 }' "$_t4" 2>/dev/null)"; }
  sfx "refresh: the job row carries the wall and the job's timeout-minutes" "@job	job-a	1140	20	ci" "$(awk -F'\t' '$1=="@job" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }' "$_t" 2>/dev/null)"
  sfx "refresh: the green row carries the job-seconds of the last green PR run" "@green	all	21780	0	ci" "$(awk -F'\t' '$1=="@green" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }' "$_t" 2>/dev/null)"
  DVOUT=$( cd "$d" && PATH=/usr/bin:/bin HOME=$_h PREPUSH_NO_CACHE=0 sh "$LANE" --refresh-times 2>&1 ) && DVRC=0 || DVRC=$?
  if command -v gh >/dev/null 2>&1 && [ -x /usr/bin/gh ] || [ -x /bin/gh ]; then echo "PASS: refresh: gh present at a fixed path; the no-gh note is not exercised here"
  else want "refresh: with no gh the run says so in one note" '^# times: gh not found'; fi
  # M2: a step's name applies to EVERY line inside its multi-line `run: |` block; a failed name that maps to no invocation is counted
  mkci <<'YAML'
jobs:
  job-b:
    steps:
      - name: Blk step
        run: |
          sh conformance/alpha.sh
          sh conformance/beta.sh
YAML
  commit_fx; _g2=$WORK/fakegh2; mkdir -p "$_g2"
  sed -e "s/Other step/Blk step\\\\nGhost step/" -e "s/job-a/job-b/g" -e "s/My step/Blk step/g" "$_g/gh" > "$_g2/gh"; chmod 755 "$_g2/gh"
  _h5=$WORK/trblk; DVOUT=$( cd "$d" && PATH=$_g2:$PATH HOME=$_h5 PREPUSH_NO_CACHE=0 sh "$LANE" --refresh-times 2>&1 ) && DVRC=0 || DVRC=$?
  _rc0=$( cd "$d" && git rev-list --max-parents=0 HEAD | sed -n 1p ); _t5=$_h5/.local/state/sparkwright/prepush/$_rc0/times.tsv
  sfx "M2: BOTH lines of the block get the step's red row" "alpha beta" "$(awk -F'\t' '$5 == "red" { print $1 }' "$_t5" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
  want "M2: and the failed step name that maps to no invocation is counted" '1 failed step name(s) mapped to no invocation'
}

# --- SWAS-428: the ceiling kills the arm's WHOLE process group, and an interrupted lane kills its live arm ---------------------
# Every fixture arm spawns `sleep` grandchildren of a FINITE length (at most 120 s), so a cell that fails leaks for minutes at worst; each cell reaps what
# it recorded. The seams are FUNCTION OVERRIDES appended to a COPY of the lane (arm_survivors, arm_ps, kill), never environment knobs: a probe
# function below runs in that copy in place of main. A mutant is the same copy with ONE sed edit; it must turn its cell RED, for its named cause.
# lane_mut <out> <sed-script|''> [override-text] — writes the copy; prints `differs` if the sed edit changed the lane, else `same`.
lane_mut() {
  _lm_s=${LM_SRC:-$LANE}   # SWAS-868: the source is LANE (LANE_J1 inside the selftest); a pool cell sets LM_SRC=$LANE_J2 for one call, in a command substitution
  if [ -n "$2" ]; then sed -e "$2" "$_lm_s" > "$1.tmp"; else cp "$_lm_s" "$1.tmp"; fi
  if cmp -s "$_lm_s" "$1.tmp"; then _lm_r=same; else _lm_r=differs; fi
  sed '$d' "$1.tmp" > "$1"; rm -f "$1.tmp"
  [ -z "${3-}" ] || printf '%s\n' "$3" >> "$1"
  printf 'main "$@"\n' >> "$1"
  printf '%s\n' "$_lm_r"
}
# rnl <lane-copy> <repo> [args…] -> DVOUT/DVRC, like rn but through a lane copy.
rnl() { _l=$1; _r=$2; shift 2; DVOUT=$( cd "$_r" && sh "$_l" --base HEAD "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }
# has <regex> -> yes|no over DVOUT.
has() { if printf '%s\n' "$DVOUT" | grep -q -e "$1"; then echo yes; else echo no; fi; }
# k_alive <pid-file> -> how many recorded pids are still alive. k_reap <pid-file> — kill what a failed cell left (digits, > 1 only).
k_alive() {
  _ka=0; [ -f "$1" ] || { echo 0; return 0; }
  for _kq in $(cat "$1"); do
    case $_kq in ''|*[!0-9]*) continue ;; esac
    if kill -0 "$_kq" 2>/dev/null; then _ka=$((_ka+1)); fi
  done
  echo "$_ka"
}
k_reap() {   # the loop variable is NOT _kp: the cells keep their own survivor in _kp across a reap (the old K6b leak)
  [ -f "$1" ] || return 0
  for _kq in $(cat "$1"); do hl_kill "$_kq" -KILL || :; done
  return 0
}
# k_stop <pid> — kill and reap a cell's own background sleeper quietly (bash would print "Killed: 9" for it).
k_stop() { { hl_kill "$1" -KILL; wait "$1"; } 2>/dev/null || :; }
# orph_fx <arm body> <budget-s> -> $d: a --slow fixture whose heavy check `alpha` runs the body with that ceiling.
orph_fx() { one_step; mkchk alpha "$1"; tw alpha heavy '' '' '' "$2" 'fixture: a ceiling-hit arm'; commit_fx; }
# the three arm shapes: a grandchild, a TERM-ignoring grandchild, a grandchild in a group of its own (all record their pids in $PWD/k.pids)
K_BODY='( sleep 100 & echo $! >> "$PWD/k.pids"; wait ) &
echo $! >> "$PWD/k.pids"
wait'
K_BODY_IGN='( trap "" TERM; sleep 100 & echo $! >> "$PWD/k.pids"; wait ) &
echo $! >> "$PWD/k.pids"
wait'
K_BODY_ESC='/usr/bin/perl -e "setpgrp(0,0); exec @ARGV" sleep 100 &
echo $! >> "$PWD/k.pids"
sleep 1
ps -o pgid= -p $! | tr -d " " > "$PWD/esc.pgid"
ps -o pgid= -p $$ | tr -d " " > "$PWD/arm.pgid"
wait'

# K1/K2/K3 (C1-C3): a ceiling hit leaves no recorded descendant alive, however it hides. M-428a/b1/b2/c each turn their cell red.
selftest_orphan_ceiling() {
  _m=$WORK/lane-428.sh
  orph_fx "$K_BODY" 2; rn "$d" --slow
  want "orphan/K1: the ceiling FAIL says the group was killed, TERM+CONT then KILL, confirmed gone" "exceeded ceiling.*process group [0-9]* + [0-9]* escaped descendant(s): TERM+CONT, confirmed gone"
  wantnot "orphan/K1: and no KILL is claimed when none fired (TERM was enough)" "exceeded ceiling.*KILL after"
  sfx "orphan/K1: a grandchild and its subshell are dead after the ceiling" 0 "$(k_alive "$d/k.pids")"; k_reap "$d/k.pids"
  sfx "orphan/M-428a: the mutation (signal the direct child, not the group) changed the lane" differs "$(lane_mut "$_m" 's|kill -s "\$1" -- "-\$2"|kill -s "$1" "$2"|')"
  orph_fx "$K_BODY" 2; rnl "$_m" "$d" --slow
  sfx "orphan/M-428a: signalling the direct child only leaves the grandchild alive, so K1 is RED" yes "$([ "$(k_alive "$d/k.pids")" -gt 0 ] && echo yes || echo no)"; k_reap "$d/k.pids"
  # K2: a member that ignores TERM dies on the KILL
  orph_fx "$K_BODY_IGN" 2; rn "$d" --slow
  sfx "orphan/K2: a TERM-ignoring grandchild is dead after the KILL" 0 "$(k_alive "$d/k.pids")"
  want "orphan/K2: and the FAIL line says KILL fired and confirmed gone" "exceeded ceiling.*TERM+CONT, KILL after 5 s, confirmed gone"; k_reap "$d/k.pids"
  sfx "orphan/M-428b1: the mutation (no KILL step) changed the lane" differs "$(lane_mut "$_m" 's#^    arm_sig KILL "\$_ak_g"$#    :#;s#^    for _ak_p in \$_ak_set \$_ak_ld; do arm_sigp KILL "\$_ak_p"; done$#    :#')"
  orph_fx "$K_BODY_IGN" 2; rnl "$_m" "$d" --slow
  sfx "orphan/M-428b1: with no KILL the TERM-ignorer lives, so K2 is RED" yes "$([ "$(k_alive "$d/k.pids")" -gt 0 ] && echo yes || echo no)"; k_reap "$d/k.pids"
  sfx "orphan/M-428b2: the mutation (the parent does not wait for a fired watchdog) changed the lane" differs "$(lane_mut "$_m" 's#^  if \[ -e "\$_rtc/wd.fired" \]; then wait "\$_wd" || :$#  if false; then :#')"
  orph_fx "$K_BODY_IGN" 2; rnl "$_m" "$d" --slow
  sfx "orphan/M-428b2: the parent kills the watchdog mid-grace, so the TERM-ignorer lives and K2 is RED" yes "$([ "$(k_alive "$d/k.pids")" -gt 0 ] && echo yes || echo no)"; k_reap "$d/k.pids"
  # K3: a grandchild that made its OWN group (a nested lane does exactly this) is reached by the ppid snapshot
  if [ ! -x /usr/bin/perl ]; then echo "SKIP: orphan/K3: /usr/bin/perl is absent — the escaped-group cell NOT exercised"; return 0; fi
  orph_fx "$K_BODY_ESC" 2; rn "$d" --slow
  sfx "orphan/K3: the fixture grandchild really is in a group of its own" differ "$([ "$(cat "$d/esc.pgid" 2>/dev/null)" != "$(cat "$d/arm.pgid" 2>/dev/null)" ] && echo differ || echo same)"
  sfx "orphan/K3: the escaped grandchild is dead after the ceiling" 0 "$(k_alive "$d/k.pids")"; k_reap "$d/k.pids"
  sfx "orphan/M-428c: the mutation (no ppid snapshot) changed the lane" differs "$(lane_mut "$_m" 's#^  _ak_s1=.*$#  _ak_s1=""#')"
  orph_fx "$K_BODY_ESC" 2; rnl "$_m" "$d" --slow
  sfx "orphan/M-428c: without the snapshot the escaped grandchild lives, so K3 is RED" yes "$([ "$(k_alive "$d/k.pids")" -gt 0 ] && echo yes || echo no)"; k_reap "$d/k.pids"
}

# K4 (C4): a survivor the confirm can see is NEVER read as confirmed gone, and the verdict is UNVERIFIED (the override is a function appended to a lane copy).
selftest_orphan_unconfirmed() {
  sleep 110 & _kp=$!
  _m=$WORK/lane-428d.sh; _ov="arm_survivors() { echo $_kp; }; ARM_GRACE_S=1; ARM_CONFIRM_S=1"
  lane_mut "$_m" '' "$_ov" > /dev/null
  orph_fx 'sleep 60' 2; rnl "$_m" "$d" --slow
  want "orphan/K4: the ceiling FAIL names the survivor and says NOT confirmed gone" "exceeded ceiling.*NOT confirmed gone: pid $_kp still alive"
  sfx "orphan/K4: a ceiling hit with a survivor reads UNVERIFIED, not FAIL" "PARITY-CORE: UNVERIFIED" "$(lastline | cut -c1-23)"
  sfx "orphan/K4: rc 1" 1 "$DVRC"
  sfx "orphan/M-428d: the mutation (hard-code confirmed gone) changed the lane" differs "$(lane_mut "$_m" 's#, NOT confirmed gone: pid \$_apl still alive#, confirmed gone#' "$_ov")"
  rnl "$_m" "$d" --slow
  sfx "orphan/M-428d: the FAIL line no longer says NOT confirmed gone, so K4 is RED" no "$(has 'exceeded ceiling.*NOT confirmed gone')"
  k_stop "$_kp"
}

# K5 (C5, design item B1): a TERM to the LANE pid ONLY (never the group) while an arm runs. The ceiling is 300 s, so the watchdog cannot be what passes it:
# within about 8 s the lane must exit 143 and the arm's group and grandchild must be gone. k5_run sets K5R to `ok` or `red: <why>`.
# k5_run <lane> [term|storm|kill] — term: one TERM to the lane pid; storm: two TERMs 0.3 s apart over a TERM-ignoring grandchild (the KILL must still happen,
# S-M2); kill: SIGKILL to the lane pid (the watchdog notices and kills the arm, R-M2). A red run names its reasons in K5R.
k5_run() {
  _mode=${2:-term}; _sig=TERM; _rcw=143; _max=8; _ign=""
  [ "$_mode" != storm ] || { _ign='trap "" TERM; '; _max=14; }
  [ "$_mode" != kill ] || { _sig=KILL; _rcw=137; }
  one_step; mkchk alpha 'echo $$ > "$PWD/arm.pid"
( '"$_ign"'sleep 110 & echo $! > "$PWD/gc.pid"; wait ) &
wait'
  commit_fx; _own=$(ps -o pgid= -p "$$" | tr -d ' ')
  ( cd "$d" && PREPUSH_CEILING_S=300 && export PREPUSH_CEILING_S && exec sh "$1" --base HEAD --warranted ) > "$WORK/k5.out" 2>&1 &
  _lp=$!; _dl=$(( $(now_s) + 25 ))
  while [ ! -s "$d/gc.pid" ] && [ "$(now_s)" -lt "$_dl" ]; do sleep 1; done
  if [ ! -s "$d/gc.pid" ]; then K5R="red: the arm never started"; hl_kill "$_lp" -KILL || :; return 0; fi
  _ap=$(cat "$d/arm.pid"); _gc=$(cat "$d/gc.pid"); _pg=$(ps -o pgid= -p "$_ap" 2>/dev/null | tr -d ' ')
  sleep 1; kill -s "$_sig" "$_lp" 2>/dev/null || :; _t0=$(now_s); _dl=$(( _t0 + 12 + _max - 8 )); K5R=""
  if [ "$_mode" = storm ]; then sleep 0.3 2>/dev/null || sleep 1; kill -s TERM "$_lp" 2>/dev/null || :; fi
  while :; do
    _ls=$(ps -o stat= -p "$_lp" 2>/dev/null | tr -d ' '); _gs=$(ps -o stat= -p "$_gc" 2>/dev/null | tr -d ' ')
    _gm=$(ps -A -o pid= -o pgid= 2>/dev/null | awk -v g="$_pg" '$2 == g { n++ } END { print n + 0 }')
    case $_ls in ''|Z*) _lgone=1 ;; *) _lgone=0 ;; esac
    case $_gs in ''|Z*) _ggone=1 ;; *) _ggone=0 ;; esac
    if [ "$_lgone" -eq 1 ] && [ "$_ggone" -eq 1 ] && [ "$_gm" -eq 0 ]; then break; fi
    [ "$(now_s)" -lt "$_dl" ] || break
    sleep 1
  done
  _el=$(( $(now_s) - _t0 ))
  [ "$_lgone" -eq 1 ] || K5R="$K5R lane-alive"
  [ "$_ggone" -eq 1 ] || K5R="$K5R grandchild-alive"
  [ "$_gm" -eq 0 ] || K5R="$K5R group-alive($_gm member(s), pgid $_pg)"
  [ "$_pg" != "$_own" ] || K5R="$K5R arm-not-in-its-own-group"
  [ "$_el" -le "$_max" ] || K5R="$K5R took-${_el}s"
  # reap what a red run left (by PID: the arm's group may be the selftest's own, and must never be signalled)
  hl_kill "$_ap" -KILL || :; hl_kill "$_gc" -KILL || :
  _dl=$(( $(now_s) + 3 ))
  while [ "$(now_s)" -lt "$_dl" ]; do
    _ls=$(ps -o stat= -p "$_lp" 2>/dev/null | tr -d ' '); case $_ls in ''|Z*) break ;; esac; sleep 1
  done
  _lrc=0; case $_ls in ''|Z*) { wait "$_lp"; } 2>/dev/null || _lrc=$? ;; *) hl_kill "$_lp" -KILL || :; { wait "$_lp"; } 2>/dev/null || :; _lrc=killed ;; esac
  [ "$_lrc" = "$_rcw" ] || K5R="$K5R lane-rc=$_lrc"
  if [ -z "$K5R" ]; then K5R=ok; else K5R="red:$K5R"; fi
}
# k5_has <regex> -> yes|no over K5R: a mutant must be red for its NAMED cause, not merely red (a run whose arm never started is red for neither).
k5_has() { if printf '%s' "$K5R" | grep -q -e "$1"; then echo yes; else echo no; fi; }
selftest_orphan_trap() {
  _m=$WORK/lane-428e.sh
  k5_run "$LANE"; sfx "orphan/K5: TERM to the lane pid alone ends the lane (rc 143) and kills the arm's group and grandchild within 8 s" ok "$K5R"
  # e1 swaps the background run for a foreground one; `SR_PID=$$` is only there so the following `wait` has a (non-child) operand and returns 127 at once, as a no-op.
  sfx "orphan/M-428e1: the mutation (scrubbed_run in the foreground again) changed the lane" differs "$(lane_mut "$_m" 's#^  scrubbed_run "\$@" & SR_PID=\$!$#  scrubbed_run "$@" || :; SR_PID=$$#')"
  k5_run "$_m"; sfx "orphan/M-428e1: with the trap deferred behind the foreground run, the lane is still alive, so K5 is RED for lane-alive" yes "$(k5_has 'lane-alive')"
  # e2 and l also drop the watchdog's lane-pid poll: with it the watchdog would rescue the arm after a second, which is the point of R-M2 but masks the trap's own kill
  sfx "orphan/M-428e2: the mutation (cleanup skips the arm kill; no lane-pid poll) changed the lane" differs "$(lane_mut "$_m" 's#^  arm_trap_kill$#  :#;/^      kill -0 "\$_lpid" 2>\/dev\/null || { arm_orphaned/d')"
  k5_run "$_m"; sfx "orphan/M-428e2: with no arm kill in the trap, the arm lives, so K5 is RED for group-alive or grandchild-alive" yes "$(k5_has 'group-alive\|grandchild-alive')"
  # S-M2: a TERM storm over a TERM-ignoring grandchild. The first handler must finish its KILL; a nested one must not abandon it.
  k5_run "$LANE" storm; sfx "orphan/K10: two TERMs 0.3 s apart still end in a KILL: lane rc 143, TERM-ignoring grandchild and group gone" ok "$K5R"
  # The trap re-entry mutant is not graded; SWAS-467 owns it. K10 above stays: a TERM storm still ends in the KILL.
  # R-M2: SIGKILL cannot be trapped, but the watchdog polls the lane pid and kills the arm when the lane alone died
  k5_run "$LANE" kill; sfx "orphan/K11: SIGKILL to the lane pid alone: the watchdog kills the arm's group within 8 s" ok "$K5R"
  sfx "orphan/M-428m: the mutation (no lane-pid poll in the watchdog) changed the lane" differs "$(lane_mut "$_m" '/^      kill -0 "\$_lpid" 2>\/dev\/null || { arm_orphaned/d')"
  k5_run "$_m" kill; sfx "orphan/M-428m: with no poll the arm runs on with a 300 s ceiling, so K11 is RED for grandchild-alive" yes "$(k5_has 'grandchild-alive')"
}

# K6/K6b (C6): an arm that exits 0 and leaves a process behind: killed and NAMED (a NOTE, not a FAIL); an unconfirmed kill is UNVERIFIED.
selftest_orphan_leftover() {
  _lb='sleep 100 & echo $! > "$PWD/k.pids"
exit 0'
  _m=$WORK/lane-428f.sh
  orph_fx "$_lb" 30; rn "$d" --slow
  sfx "orphan/K6: an arm that exits 0 is still rc 0" 0 "$DVRC"
  want "orphan/K6: the lane names the leftover and says it was killed" "^# NOTE: .* left [0-9]* process(es) in its group after exit; killed (confirmed gone)"
  sfx "orphan/K6: the leftover is dead" 0 "$(k_alive "$d/k.pids")"; k_reap "$d/k.pids"
  sfx "orphan/M-428f: the mutation (no post-exit check) changed the lane" differs "$(lane_mut "$_m" 's#^  if \[ "\$_grp" -eq 1 \] && arm_group_alive "\$_pid"; then#  if false; then#')"
  orph_fx "$_lb" 30; rnl "$_m" "$d" --slow
  sfx "orphan/M-428f: with no post-exit check the leftover lives, so K6 is RED" yes "$([ "$(k_alive "$d/k.pids")" -gt 0 ] && echo yes || echo no)"; k_reap "$d/k.pids"
  # K6b: the same arm with an unconfirmable kill
  sleep 110 & _kp=$!
  _ov="arm_survivors() { echo $_kp; }; ARM_GRACE_S=1; ARM_CONFIRM_S=1"
  lane_mut "$WORK/lane-428g0.sh" '' "$_ov" > /dev/null
  orph_fx "$_lb" 30; rnl "$WORK/lane-428g0.sh" "$d" --slow
  want "orphan/K6b: the NOTE says NOT confirmed gone, naming the pid" "^# NOTE: .*NOT confirmed gone: pid $_kp"
  sfx "orphan/K6b: the verdict is UNVERIFIED" "PARITY-CORE: UNVERIFIED" "$(lastline | cut -c1-23)"
  k_reap "$d/k.pids"
  sfx "orphan/M-428g: the mutation (no UNV on an unconfirmed post-exit kill) changed the lane" differs "$(lane_mut "$_m" 's#unv "\$_an_lb: leftover kill NOT confirmed gone: pid \$_apl"#:#' "$_ov")"
  orph_fx "$_lb" 30; rnl "$_m" "$d" --slow
  sfx "orphan/M-428g: without the UNV the verdict is not UNVERIFIED, so K6b is RED" no "$([ "$(lastline | cut -c1-23)" = 'PARITY-CORE: UNVERIFIED' ] && echo yes || echo no)"
  k_reap "$d/k.pids"; k_stop "$_kp"
}

# K7 (C9): with no perl the arms are not process-grouped; the lane says so ONCE, every ceiling FAIL says the tree is NOT contained, and nothing over-claims.
selftest_orphan_noperl() {
  _m=$WORK/lane-428h.sh
  sfx "orphan/K7: the fixture override (a missing perl) changed the lane" differs "$(lane_mut "$_m" 's|^ARM_PERL=.*$|ARM_PERL=/nonexistent/perl|')"
  orph_fx 'sleep 6' 2; rnl "$_m" "$d" --slow
  want "orphan/K7: the ceiling FAIL says the tree is NOT contained" "exceeded ceiling.*tree NOT contained (no /nonexistent/perl: direct child only)"
  wantnot "orphan/K7: and never claims confirmed gone" "confirmed gone"
  sfx "orphan/K7: the lane says so exactly once per run" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^# NOTE: no /nonexistent/perl: arms are not process-grouped' || :)"
  orph_fx 'sleep 100 & echo $! > "$PWD/k.pids"
exit 0' 30; rnl "$_m" "$d" --slow
  wantnot "orphan/K7: the post-exit check does not run (no leftover NOTE)" "left [0-9]* process"; k_reap "$d/k.pids"
  sfx "orphan/M-428h: the mutation (group acts left on in the fallback) changed the lane" differs "$(lane_mut "$WORK/lane-428h2.sh" 's|^ARM_PERL=.*$|ARM_PERL=/nonexistent/perl|;s#^    if \[ "\$_grp" -eq 1 \]; then ARM_NOTE=#    if true; then ARM_NOTE=#')"
  orph_fx 'sleep 6' 2; rnl "$WORK/lane-428h2.sh" "$d" --slow
  sfx "orphan/M-428h: the fallback then claims confirmed gone for a group that never existed, so K7 is RED" yes "$(has 'exceeded ceiling.*confirmed gone')"
}

# K8 (C10): a pgid that is empty, not a number, <= 1 or the lane's OWN group never reaches `kill`. The probe runs in a lane copy, with `kill` recording its calls.
probe_k8() {
  set +e
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-k8-XXXXXX"); mkdir -p "$WORK/ctl"; ARM_NOTE=$WORK/ctl/kill.note; : > "$WORK/kills"; ARM_GRACE_S=1; ARM_CONFIRM_S=1
  kill() { echo "$*" >> "$WORK/kills"; }
  _own=$(ps -o pgid= -p "$$" | tr -d ' ')
  for _v in '' abc 0 1 -5 "$_own" "0$_own"; do
    rm -f "$ARM_NOTE"; _r=0; arm_kill "$_v" || _r=$?
    printf 'v=[%s] rc=%s note=[%s]\n' "$_v" "$_r" "$(sed -n 1p "$ARM_NOTE" 2>/dev/null)"
  done
  UNV=""; arm_note_apply ceiling probe > /dev/null 2>&1; printf 'unv=[%s]\n' "$UNV"
  printf '1234\n5678\n' > "$WORK/arm.pgid"; printf 'multi=[%s]\n' "$(arm_read_pgid "$WORK/arm.pgid" || echo refused)"
  printf '4242\n' > "$WORK/arm.pgid"; printf 'single=[%s]\n' "$(arm_read_pgid "$WORK/arm.pgid" || echo refused)"
  ln -s "$WORK/arm.pgid" "$WORK/arm.lnk"; printf 'link=[%s]\n' "$(arm_read_pgid "$WORK/arm.lnk" || echo refused)"
  printf 'abc\n' > "$WORK/arm.nan"; printf 'nan=[%s]\n' "$(arm_read_pgid "$WORK/arm.nan" || echo refused)"
  printf 'kills=%s\n' "$(wc -l < "$WORK/kills" | tr -d ' ')"
}
k8_check() {   # <label-prefix> -> the K8 assertions over DVOUT
  _own=$(ps -o pgid= -p "$$" | tr -d ' ')
  for _v in "" abc 0 1 -5 "$_own" "0$_own"; do want "$1: pgid [$_v] is refused" "^v=\[$_v\] rc=1 note=\[REFUSED"; done
  want "$1: a refusal sets UNV" "^unv=\[.\+\]"
  want "$1: a two-line arm.pgid file is refused" "^multi=\[refused\]$"
  want "$1: a one-line arm.pgid file is read" "^single=\[4242\]$"
  want "$1: a SYMLINKED arm.pgid file is refused" "^link=\[refused\]$"
  want "$1: a file that is not a number is refused" "^nan=\[refused\]$"
  want "$1: no signal was sent for any refused pgid" "^kills=0$"
}
selftest_orphan_guard() {
  _m=$WORK/lane-428i.sh
  lane_mut "$_m" '' 'probe_k8; exit 0' > /dev/null; DVOUT=$(sh "$_m" 2>&1) || :; k8_check "orphan/K8"
  sfx "orphan/M-428i: the mutation (drop the <= 1 test) changed the lane" differs "$(lane_mut "$_m" '/_ap_why="at most 1"/d' 'probe_k8; exit 0')"
  DVOUT=$(sh "$_m" 2>&1) || :
  sfx "orphan/M-428i: pgid 1 is no longer refused, so K8 is RED" no "$(has '^v=\[1\] rc=1 note=\[REFUSED')"
  sfx "orphan/M-428j: the mutation (drop the own-group test) changed the lane" differs "$(lane_mut "$_m" "/_ap_why=\"the lane's own group\"/d;/the lane.s parent group/d" 'probe_k8; exit 0')"   # the probe shares its parent's group, so the parent test would still refuse: both are dropped
  DVOUT=$(sh "$_m" 2>&1) || :
  sfx "orphan/M-428j: the lane's own pgid is no longer refused, so K8 is RED" no "$(has "^v=\[$_own\] rc=1 note=\[REFUSED")"
  # S-L1 / S-L3: the leading-zero, symlink and not-a-number guards each have a mutant that reds
  sfx "orphan/M-428n: the mutation (drop the leading-zero test) changed the lane" differs "$(lane_mut "$_m" '/_ap_why="leading zero"/d' 'probe_k8; exit 0')"
  DVOUT=$(sh "$_m" 2>&1) || :
  sfx "orphan/M-428n: 0<own pgid> is no longer refused, so K8 is RED" no "$(has "^v=\[0$_own\] rc=1 note=\[REFUSED")"
  sfx "orphan/M-428o: the mutation (drop the symlink test) changed the lane" differs "$(lane_mut "$_m" 's#^  \[ -f "\$1" \] && \[ ! -L "\$1" \] || return 1$#  [ -f "$1" ] || return 1#' 'probe_k8; exit 0')"
  DVOUT=$(sh "$_m" 2>&1) || :
  sfx "orphan/M-428o: a symlinked arm.pgid is now read, so K8 is RED" no "$(has '^link=\[refused\]$')"
  sfx "orphan/M-428p: the mutation (drop the not-a-number test) changed the lane" differs "$(lane_mut "$_m" "s#^  case \\\$_arp in ''|\\*\\[!0-9\\]\\*) return 1 ;; esac\$#  :#" 'probe_k8; exit 0')"
  DVOUT=$(sh "$_m" 2>&1) || :
  sfx "orphan/M-428p: a non-numeric arm.pgid is now read, so K8 is RED" no "$(has '^nan=\[refused\]$')"
}

# K14: the group of the lane's PARENT is never signalled. The probe runs in a group of its own (perl setpgrp, then exec), so its parent's group is not its own.
probe_k8b() {
  set +e
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-k14-XXXXXX"); mkdir -p "$WORK/ctl"; ARM_NOTE=$WORK/ctl/kill.note; : > "$WORK/kills"; ARM_GRACE_S=1; ARM_CONFIRM_S=1
  kill() { echo "$*" >> "$WORK/kills"; }
  _pp=$(ps -o pgid= -p "$PPID" | tr -d ' '); _own=$(ps -o pgid= -p "$$" | tr -d ' ')
  printf 'pp=[%s] own=[%s]\n' "$_pp" "$_own"
  _r=0; arm_kill "$_pp" || _r=$?
  printf 'v=[%s] rc=%s note=[%s]\n' "$_pp" "$_r" "$(sed -n 1p "$ARM_NOTE" 2>/dev/null)"
  printf 'kills=%s\n' "$(wc -l < "$WORK/kills" | tr -d ' ')"
}
selftest_orphan_parent() {
  _m=$WORK/lane-428t.sh
  if [ ! -x /usr/bin/perl ]; then echo "SKIP: orphan/K14: /usr/bin/perl is absent — the parent-group cell NOT exercised"; return 0; fi
  lane_mut "$_m" '' 'probe_k8b; exit 0' > /dev/null
  DVOUT=$(/usr/bin/perl -e 'setpgrp(0,0); exec @ARGV or exit 126' sh "$_m" 2>&1) || :
  _pp=$(printf '%s\n' "$DVOUT" | sed -n 's/^pp=\[\([0-9]*\)\] .*/\1/p'); _po=$(printf '%s\n' "$DVOUT" | sed -n 's/^pp=\[[0-9]*\] own=\[\([0-9]*\)\]$/\1/p')
  sfx "orphan/K14: the probe's own group is not its parent's (the cell is not vacuous)" differ "$([ -n "$_pp" ] && [ -n "$_po" ] && [ "$_pp" != "$_po" ] && echo differ || echo same)"
  want "orphan/K14: the parent's pgid is refused" "^v=\[$_pp\] rc=1 note=\[REFUSED"
  want "orphan/K14: and no signal was sent" "^kills=0$"
  sfx "orphan/M-428t: the mutation (drop the parent-group test) changed the lane" differs "$(lane_mut "$_m" '/the lane.s parent group/d' 'probe_k8b; exit 0')"
  DVOUT=$(/usr/bin/perl -e 'setpgrp(0,0); exec @ARGV or exit 126' sh "$_m" 2>&1) || :
  sfx "orphan/M-428t: the parent's pgid is no longer refused, so K14 is RED" no "$(has "^v=\[$_pp\] rc=1 note=\[REFUSED")"
}

# S-M1: an arm LEADER that moves itself into another group (here: the lane's own) is in no group of ours; the leader is signalled and confirmed by pid.
# R-M1: a background job starts with INT ignored and exec keeps that; the wrapper resets it, so the arm can be interrupted.
selftest_orphan_leader() {
  _m=$WORK/lane-428q.sh
  if [ ! -x /usr/bin/perl ]; then echo "SKIP: orphan/K12: /usr/bin/perl is absent — the leader and INT cells NOT exercised"; return 0; fi
  _lb='echo $$ > "$PWD/k.pids"
exec /usr/bin/perl -e "setpgrp(0,getpgrp(getppid())); sleep 12"'
  orph_fx "$_lb" 2; _t0=$(now_s); rn "$d" --slow; _el=$(( $(now_s) - _t0 ))
  sfx "orphan/K12: a leader that joined another group is killed at the ceiling (the run took under 9 s, not the arm's 12)" yes "$([ "$_el" -lt 9 ] && echo yes || echo no)"
  want "orphan/K12: and the ceiling FAIL line is there" "exceeded ceiling"
  sfx "orphan/K12: the leader is dead" 0 "$(k_alive "$d/k.pids")"; k_reap "$d/k.pids"
  sfx "orphan/M-428r: the mutation (the leader is not signalled by pid) changed the lane" differs "$(lane_mut "$_m" 's#^  \[ "\${2-}" != leader \] || _ak_ld=\$_ak_g$#  :#')"
  orph_fx "$_lb" 2; _t0=$(now_s); rnl "$_m" "$d" --slow; _el=$(( $(now_s) - _t0 ))
  sfx "orphan/M-428r: the leader outside any group of ours runs its 12 s, so K12 is RED" yes "$([ "$_el" -ge 9 ] && echo yes || echo no)"; k_reap "$d/k.pids"
  # R-M1: INT must not be ignored in the arm (it sends itself INT: an ignored one survives and writes the marker)
  orph_fx 'kill -s INT $$
echo ignored > "$PWD/int.out"' 30; rn "$d" --slow
  sfx "orphan/K13: an INT to the arm is not ignored (the arm died before its marker)" no "$([ -e "$d/int.out" ] && echo yes || echo no)"
  sfx "orphan/M-428s: the mutation (INT and QUIT not reset in the wrapper) changed the lane" differs "$(lane_mut "$_m" 's#\$SIG{INT}=\$SIG{QUIT}="DEFAULT"; ##')"
  orph_fx 'kill -s INT $$
echo ignored > "$PWD/int.out"' 30; rnl "$_m" "$d" --slow
  sfx "orphan/M-428s: the inherited ignore survives the exec, so the marker is written and K13 is RED" yes "$([ -e "$d/int.out" ] && echo yes || echo no)"
}

# K9 (C11): the KILL goes only to a pid still in the lineage; a first-snapshot pid that is now somebody else's is not signalled.
probe_k9() {
  set +e
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-k9-XXXXXX"); mkdir -p "$WORK/ctl"; ARM_NOTE=$WORK/ctl/kill.note; ARM_GRACE_S=1; ARM_CONFIRM_S=1
  kill() { echo "$*" >> "$WORK/kills"; }
  arm_survivors() { echo 5002; }
  arm_ps() { case $1 in first) printf '5000 1 5000\n5001 5000 5000\n5002 5000 5002\n' ;; second) printf '5002 %s %s\n' "$K9PP" "$K9PG" ;; esac; }
  : > "$WORK/kills"; K9PP=777; K9PG=777; arm_kill 5000 > /dev/null 2>&1; sed 's/^/F /' "$WORK/kills"
  : > "$WORK/kills"; K9PP=5000; K9PG=5002; arm_kill 5000 > /dev/null 2>&1; sed 's/^/L /' "$WORK/kills"
}
selftest_orphan_reuse() {
  _m=$WORK/lane-428k.sh
  lane_mut "$_m" '' 'probe_k9; exit 0' > /dev/null; DVOUT=$(sh "$_m" 2>&1) || :
  want "orphan/K9: the first-snapshot pid outside the group gets the TERM" "^F -s TERM 5002$"
  want "orphan/K9: the group still gets the KILL" "^F -s KILL -- -5000$"
  wantnot "orphan/K9: a pid that is now someone else's (foreign ppid and pgid) gets NO KILL" "^F -s KILL 5002$"
  want "orphan/K9: control — the same pid, still in the lineage, DOES get the KILL" "^L -s KILL 5002$"
  sfx "orphan/M-428k: the mutation (KILL the first snapshot as-is) changed the lane" differs "$(lane_mut "$_m" 's#return (p\[x\] in in1).*$#return 1 }#' 'probe_k9; exit 0')"
  DVOUT=$(sh "$_m" 2>&1) || :
  sfx "orphan/M-428k: the reused pid is now signalled, so K9 is RED" yes "$(has '^F -s KILL 5002$')"
}

# C7: the perl wrapper takes no code from the environment. An arm reports what it can see of the three perl library names; the lane scrubs them.
selftest_orphan_perl_env() {
  _m=$WORK/lane-428c7.sh
  one_step; mkchk alpha 'printf "[%s][%s][%s]\n" "${PERL5LIB-}" "${PERLLIB-}" "${PERL_USE_UNSAFE_INC-}" > "$PWD/penv.out"'; commit_fx
  DVOUT=$( cd "$d" && PERL5LIB=/x PERLLIB=/y PERL_USE_UNSAFE_INC=1 sh "$LANE" --base HEAD --warranted 2>&1 ) || :
  sfx "orphan/C7: an arm sees none of PERL5LIB, PERLLIB, PERL_USE_UNSAFE_INC" "[][][]" "$(cat "$d/penv.out" 2>/dev/null || echo MISSING)"
  sfx "orphan/C7: the mutation (PERLLIB left out of the unset list) changed the lane" differs "$(lane_mut "$_m" 's# PERLLIB PERL_USE_UNSAFE_INC# PERL_USE_UNSAFE_INC#')"
  rm -f "$d/penv.out"; DVOUT=$( cd "$d" && PERL5LIB=/x PERLLIB=/y PERL_USE_UNSAFE_INC=1 sh "$_m" --base HEAD --warranted 2>&1 ) || :
  sfx "orphan/C7: with PERLLIB left in, an arm sees it, so the cell is RED" "[][/y][]" "$(cat "$d/penv.out" 2>/dev/null || echo MISSING)"
}

# SWAS-468: scripts/preflight.sh's case-variant cell, run as a lane arm, must not depend on WHICH sh it runs under. The cell needs `pwd -P` to keep a
# case-variant spelling, which bash does and dash (the lane's PATH shim) does not: on a case-insensitive filesystem the string-compare mutant is then equivalent.
# The cell is N/A on a case-sensitive filesystem (preflight skips there too). SWAS-487: the arms run ONLY that cell (`--selftest --selftest-cell case-variant`), not the whole
# selftest five times; the full selftest stays graded by CI's own step and by selftest-hermetic. pf_arm <preflight root> runs the cell as a lane arm: $d/pf.out, $d/pf.rc.
pf_arm() {
  one_step; mkchk alpha "o=\$PWD; cd \"$1\" && sh scripts/preflight.sh --selftest --selftest-cell case-variant > \"\$o/pf.out\" 2>&1; echo \$? > \"\$o/pf.rc\""; commit_fx
  env_rn "$d" PREPUSH_CEILING_S 900 --warranted
}
# pf_live <label> <output file>: cell mode must have RUN the cell (exactly one owns_itself [case-variant-cd] line). Without it an arm that ran nothing would read as a mutant kill (no "survived" line).
pf_live() {
  sfx "preflight/CV/live: $1 runs the case-variant cell (one owns_itself line)" 1 "$(grep -c 'owns_itself \[case-variant-cd\]' "$2" 2>/dev/null || :)"
}
# pf_copy <dir> <sed expr> -> prints differs|same: a copy of scripts/ + the hook under <dir>, its preflight.sh mutated by the expression.
pf_copy() {
  mkdir -p "$1/hooks"; cp -R "$KROOT/scripts" "$1/scripts"; cp "$KROOT/hooks/pre-push" "$1/hooks/pre-push"
  sed "$2" "$KROOT/scripts/preflight.sh" > "$1/scripts/preflight.sh"
  if cmp -s "$KROOT/scripts/preflight.sh" "$1/scripts/preflight.sh"; then echo same; else echo differs; fi
}
pf_bash_half() {   # decided by the sh on PATH, which is what preflight's probe and mutant run use (not /bin/sh)
  if [ -z "$(sh -c 'echo ${BASH_VERSION:-}' 2>/dev/null)" ]; then echo "N/A: preflight/CV: the sh on PATH is not bash ($(command -v sh 2>/dev/null || echo none)), the bash-kill half does not apply"; return 0; fi
  _brc=0; ( cd "$KROOT" && /bin/sh scripts/preflight.sh --selftest --selftest-cell case-variant ) > "$WORK/pf-bash.out" 2>&1 || _brc=$?
  sfx "preflight/CV: the preflight case-variant cell exits 0 under /bin/sh (bash)" 0 "$_brc"
  pf_live "the bash half" "$WORK/pf-bash.out"
  sfx "preflight/CV: under /bin/sh (bash) the owns-itself-string-compare mutant is still KILLED" 1 "$(grep -c '^PASS: mutant owns-itself-string-compare is killed' "$WORK/pf-bash.out" 2>/dev/null || :)"
  sfx "preflight/CV: and under /bin/sh no SKIP line and no NOTE are printed" 0 "$(grep -cE '^(SKIP owns|NOTE: preflight selftest)' "$WORK/pf-bash.out" 2>/dev/null || :)"
}
selftest_preflight_case_variant() {
  _pc=$(mktemp -d); mkdir "$_pc/ab"
  [ -d "$_pc/AB" ] || { rm -rf "$_pc"; echo "N/A: preflight/CV — this filesystem is case-sensitive, where preflight's case-variant cell skips itself"; return 0; }
  rm -rf "$_pc"; _sk='SKIP owns-itself-string-compare: this sh canonicalises case-variant pwd -P (dash); coverage WEAK here'
  _w0=$(now_s); pf_arm "$KROOT"; echo "# preflight/CV: the dash lane arm took $(( $(now_s) - _w0 )) s"
  sfx "preflight/CV: the real preflight case-variant cell exits 0 as a lane arm under the dash shim" 0 "$(cat "$d/pf.rc" 2>/dev/null || echo none)"
  pf_live "the real arm" "$d/pf.out"
  grep '^FAIL' "$d/pf.out" 2>/dev/null | sed 's/^/      /' || :
  sfx "preflight/CV: under dash the case-variant mutant is a VISIBLE SKIP line, not a PASS" 1 "$(grep -cxF "$_sk" "$d/pf.out" 2>/dev/null || :)"
  sfx "preflight/CV: and the SKIP is counted in a NOTE line before the unchanged OK line" 1 "$(grep -cxF 'NOTE: preflight selftest: 1 SKIP (coverage WEAK)' "$d/pf.out" 2>/dev/null || :)"
  pf_bash_half
  # face (a): a PATH whose sh is dash -> the half prints N/A and runs no assert
  mkdir -p "$WORK/nobash"; printf '#!/bin/sh\nexec /bin/dash "$@"\n' > "$WORK/nobash/sh"; chmod +x "$WORK/nobash/sh"; _fa=$( PATH="$WORK/nobash:$PATH"; pf_bash_half 2>&1 )
  sfx "preflight/CV/face-a: a non-bash sh on PATH prints the N/A line and runs no bash-kill assert (no PASS or FAIL)" "1,0" "$(printf '%s\n' "$_fa" | grep -c '^N/A: preflight/CV: the sh on PATH is not bash'),$(printf '%s\n' "$_fa" | grep -c '^\(PASS\|FAIL\)')"
  sfx "preflight/CV/M-cvskip: the mutation (the probe deleted: the kill always runs) changed preflight" differs "$(pf_copy "$WORK/pfmut" '/MUT-CVSKIP/s/\[ "\$_cvp" = "\$_cvc" \]/false/')"
  pf_arm "$WORK/pfmut"
  sfx "preflight/CV/M-cvskip: without the probe the mutant survives under dash, so the preflight selftest is RED" 1 "$(grep -c '^FAIL: mutant owns-itself-string-compare survived' "$d/pf.out" 2>/dev/null || :)"
  # I1 (fail-open): a probe that answers NOTHING must run the kill, not SKIP on ""="". The first copy empties the probe; the second also drops the -n guard.
  sfx "preflight/CV/M-cvempty: the mutation (the probe prints nothing) changed preflight" differs "$(pf_copy "$WORK/pfmut2" "/MUT-CVPROBE/s/sh -c '[^']*'/sh -c :/")"
  pf_arm "$WORK/pfmut2"
  pf_live "the M-cvempty arm" "$d/pf.out"
  sfx "preflight/CV/I1: an empty probe runs the kill (no SKIP line)" 0 "$(grep -cxF "$_sk" "$d/pf.out" 2>/dev/null || :)"
  sfx "preflight/CV/M-cvnonempty: the mutation (the -n guard dropped, probe empty) changed preflight" differs "$(pf_copy "$WORK/pfmut3" "/MUT-CVPROBE/s/sh -c '[^']*'/sh -c :/;/MUT-CVSKIP/s/\[ -n \"\\\$_cvp\" \] && //")"
  pf_arm "$WORK/pfmut3"
  sfx "preflight/CV/M-cvnonempty: without the guard an empty probe SKIPs (fail-open), so I1 is RED" 1 "$(grep -cxF "$_sk" "$d/pf.out" 2>/dev/null || :)"
  # SWAS-487 M-cvsel: a dispatch that runs no cell prints no owns_itself line and exits 0 with no "survived" line; only the liveness assert (pf_live) can see it.
  sfx "preflight/CV/M-cvsel: the mutation (the dispatch runs no cell) changed preflight" differs "$(pf_copy "$WORK/pfmut4" '/MUT-CVSEL/s/st_case_variant/:/')"
  pf_arm "$WORK/pfmut4"
  sfx "preflight/CV/M-cvsel: a dispatch that runs nothing leaves no owns_itself line (exit 0, no survived line), so the liveness assert is RED" 0 "$(grep -c 'owns_itself \[case-variant-cd\]' "$d/pf.out" 2>/dev/null || :)"
  echo "# preflight/CV: the whole cell (five arms, three mutant copies, M-cvsel) took $(( $(now_s) - _w0 )) s"
}

# ===================================================================================================
# SWAS-600 - a check killed by a crash signal reads UNVERIFIED, never a verdict (design 2026-10-31-dash-segv-600-design.md, errata E2 and E3).
# Fixture crash lines are built with printf from parts (no whole-line literal in this file), and every crash cell runs inside crash_cells so the group's OWN printed output can be
# rescanned for a crash line (control 7). A mutant is a lane copy (lane_mut) with ONE tagged line rewritten; its crash functions are extracted to <copy>.fn and sourced in a subshell.
crash_fns() {   # <lane copy> — its crash functions (and the two that call them) to <copy>.fn
  sed -n -e '/^crash_sig_of() {/,/^}/p' -e '/^crash_line_in() {/,/^}/p' -e '/^crash_ev_run() {/,/^}/p' -e '/^report_inv() /p' -e '/^ri_wd() /p' -e '/^ri_decide() {/,/^}/p' -e '/^ri_record() {/,/^}/p' "$1" > "$1.fn"
}
crash_scan_with() {   # <fn-file> <data-file> — that copy's crash_line_in over the data file, in a subshell; prints its rc
  # shellcheck disable=SC1090  # sources a mutant copy's extracted crash functions (the path is built at run time)
  ( . "$1"; _sc_r=0; crash_line_in "$2" || _sc_r=$?; echo "$_sc_r" )
}
crash_scan_bash() {   # <fn-file> <data-file> — the same under bash (a failed redirect on an external command is rc 1 there and rc 2 under dash); prints its rc
  WORK=$WORK bash -c '. "$1"; _sc_r=0; crash_line_in "$2" || _sc_r=$?; echo "$_sc_r"' crash "$1" "$2" 2>/dev/null
}
crash_c1() {   # control 1 - the rc evidence wins
  one_step; mkchk alpha 'kill -s SEGV $$'; commit_fx
  rn "$d" --warranted
  want "crash/1: a unit killed by SEGV reads UNVERIFIED naming the rc evidence" "^  UNVERIFIED  core-live  *alpha .*crashed (SEGV, rc 139): a crashed process is not a verdict"
  wantnot "crash/1: and never a FAIL row" "^  FAIL  "
  sfx "crash/1: the final line names the crashed unit" "PARITY-CORE: UNVERIFIED (1 unit(s) crashed: alpha)" "$(lastline)"
  sfx "crash/1: rc 1" 1 "$DVRC"
  _m=$WORK/lane-600a.sh
  sfx "crash/1m: the mutation (the rc test dropped) changed the lane" differs "$(lane_mut "$_m" '/# CRRC$/s/^\( *\).*/\1:/')"
  rnl "$_m" "$d" --warranted
  wantnot "crash/1m: without the rc test no row names the rc evidence, so crash/1 has teeth" "crashed (SEGV, rc 139)"
}
crash_c2() {   # control 2 - a crash line at rc 0
  one_step; mkchk alpha 'printf "%s %s\n" Segmentation "fault: 11"'; commit_fx; rn "$d" --warranted
  want "crash/2: a crash line in a unit that exits 0 reads UNVERIFIED naming the line" "^  UNVERIFIED  core-live  *alpha .*crashed (Segmentation fault line): a crashed process is not a verdict"
  wantnot "crash/2: and never an OK row" "^  OK    core-live "
  wantnot "crash/2: an expected status adds no rc note" "unit rc="
  sfx "crash/2: the final line names the crashed unit" "PARITY-CORE: UNVERIFIED (1 unit(s) crashed: alpha)" "$(lastline)"
  _m=$WORK/lane-600b.sh
  sfx "crash/2m: the mutation (the line scan dropped) changed the lane" differs "$(lane_mut "$_m" '/# CRLINE2$/s/^\( *\).*/\1_ce_r=1/')"
  rnl "$_m" "$d" --warranted
  want "crash/2m: without the scan the unit reads OK, so crash/2 has teeth" "^  OK    core-live  *alpha "
}
crash_c2p() {   # control 2, the real shape: a crashed FIRST pipeline stage exits 0 and only the parent shell's line shows it
  _p=$WORK/crash.probe; : > "$_p"
  if command -v dash >/dev/null 2>&1; then dash -c "dash -c 'kill -s SEGV \$\$' | cat" > "$_p" 2>&1 || :; fi
  _r=0; crash_line_in "$_p" || _r=$?
  if [ "$_r" -ne 0 ]; then echo "SKIP: crash/2p: this dash prints no line for a crashed first pipeline stage - the pipeline variant was NOT exercised"; return 0; fi
  one_step; mkchk alpha "sh -c 'kill -s SEGV \$\$' | cat"; commit_fx; rn "$d" --warranted
  want "crash/2p: a crashed first pipeline stage (the unit exits 0) reads UNVERIFIED by the parent shell's line" "^  UNVERIFIED  core-live  *alpha .*crashed (Segmentation fault line)"
}
crash_c2r() {   # a failing unit with a planted crash line: line-only evidence must not hide the unit's own status
  one_step; mkchk alpha 'printf "%s %s\n" Segmentation "fault: 11"; exit 3'; commit_fx; rn "$d" --warranted
  want "crash/2r: the row names the unit's own status beside the line evidence" "^  UNVERIFIED  core-live  *alpha .*crashed (Segmentation fault line): a crashed process is not a verdict; unit rc=3, expected 0"
  sfx "crash/2r: the final line names the status too" "PARITY-CORE: UNVERIFIED (1 unit(s) crashed: alpha [rc 3])" "$(lastline)"
  _m=$WORK/lane-600h.sh
  sfx "crash/2rm: the mutation (the status note dropped) changed the lane" differs "$(lane_mut "$_m" '/# CRRCX$/s/^\( *\).*/\1:/')"
  rnl "$_m" "$d" --warranted
  wantnot "crash/2rm: without the note the row hides the status, so crash/2r has teeth" "unit rc=3"
}
crash_c345() {   # controls 3, 4 and 5 - the two forms, what is not a crash, and the scan that fails closed
  _qd=$WORK/cq.dash; _qb=$WORK/cq.bash; _qc=$WORK/cq.clean
  printf '%s %s\n' Segmentation 'fault: 11' > "$_qd"   # CQ3
  printf '%s: line %s: %s %s %s  %s\n' x.sh 4 123 Segmentation 'fault: 11' cmd > "$_qb"
  { printf '%s: %s\n' Terminated 15; printf '%s: %s\n' Killed 9
    printf '%s %s %s\n' 'the lane reads' Segmentation 'fault: 11 in prose'
    printf '`%s: line %s: %s %s %s  %s`\n' x.sh 4 123 Segmentation 'fault: 11' cmd
    printf '| %s | %s %s |\n' row Segmentation 'fault: 11'
    printf '  printf "x" # %s %s\n' Segmentation 'fault: 11'
    printf "'%s: line %s: %s %s %s  %s\n" x.sh 4 123 Segmentation 'fault: 11' cmd
    printf '"%s: line %s: %s %s %s  %s\n' x.sh 4 123 Segmentation 'fault: 11' cmd
    printf '| %s: line %s: %s %s %s |\n' x.sh 4 123 Segmentation 'fault: 11'
    printf '|%s: line %s: %s %s %s |\n' x.sh 4 123 Segmentation 'fault: 11'; } > "$_qc"
  _r=0; crash_line_in "$_qd" || _r=$?; sfx "crash/3: the dash form is found" 0 "$_r"
  sfx "crash/3: and its phrase is named" "Segmentation fault" "$CRASH_TXT"
  _r=0; crash_line_in "$_qb" || _r=$?; sfx "crash/3: the bash-parent form is found" 0 "$_r"
  _r=0; crash_line_in "$_qc" || _r=$?
  sfx "crash/4: Terminated, Killed, prose, a backticked line, table rows, lines led by a quote or a pipe, and a quoted source line are not crashes" 1 "$_r"
  _m=$WORK/lane-600c.sh
  for _xc in 1 2 3; do
    sfx "crash/4x$_xc: the mutation (prefix exclusion $_xc dropped) changed the lane" differs "$(lane_mut "$_m" "/# CRX$_xc\$/s/^\\( *\\).*/\\1_cl_x$_xc=/")"
    crash_fns "$_m"; sfx "crash/4x$_xc: with that exclusion dropped a line led by it reads as a crash, so crash/4 has teeth" 0 "$(crash_scan_with "$_m.fn" "$_qc")"
  done
  # crash/R1: a hit file that cannot be written is rc 2, never clean (under bash 3.2 the failed redirect alone reads rc 1)
  cp "$LANE" "$WORK/lane-600r.sh"; crash_fns "$WORK/lane-600r.sh"
  rm -rf "$WORK/crash.hit"; mkdir "$WORK/crash.hit"
  sfx "crash/R1: a hit file that cannot be written is rc 2, never clean" 2 "$(_r=0; crash_line_in "$_qd" || _r=$?; echo "$_r")"
  if command -v bash >/dev/null 2>&1; then
    sfx "crash/R1: and the same under bash" 2 "$(crash_scan_bash "$WORK/lane-600r.sh.fn" "$_qd")"
    sfx "crash/R1m: the mutation (the hit-file test dropped) changed the lane" differs "$(lane_mut "$_m" '/# CRHIT$/s/^\( *\).*/\1:/')"
    crash_fns "$_m"; sfx "crash/R1m: without the test a failed redirect reads clean under bash, so crash/R1 has teeth" 1 "$(crash_scan_bash "$_m.fn" "$_qd")"
  else echo "SKIP: crash/R1 under bash - no bash here; the bash-only half was NOT exercised"; fi
  rmdir "$WORK/crash.hit"
  sfx "crash/3m: the mutation (the bash form dropped) changed the lane" differs "$(lane_mut "$_m" '/# CRBASH$/s/^\( *\).*/\1_cl_b=NOMATCHXQ/')"
  crash_fns "$_m"; sfx "crash/3m: with the bash form dropped the bash-parent line goes unseen, so crash/3 has teeth" 1 "$(crash_scan_with "$_m.fn" "$_qb")"
  sfx "crash/4a: the mutation (TERM added to the set) changed the lane" differs "$(lane_mut "$_m" '/# CRSET$/s/(Segmentation fault|/(Terminated|Segmentation fault|/')"
  crash_fns "$_m"; sfx "crash/4a: with TERM in the set a deliberate Terminated line reads as a crash, so crash/4 has teeth" 0 "$(crash_scan_with "$_m.fn" "$_qc")"
  sfx "crash/4b: the mutation (the bash-form prefix loosened to .+) changed the lane" differs "$(lane_mut "$_m" '/# CRPRE$/s/^\( *\).*/\1_cl_pre=.+/')"
  crash_fns "$_m"; sfx "crash/4b: with the prefix loosened a quoted line reads as a crash, so crash/4 has teeth" 0 "$(crash_scan_with "$_m.fn" "$_qc")"
  # control 5: a grep that exits 2 ONLY when its pattern holds the crash set; every other call reaches the real grep
  _qs=$WORK/cq.stub; mkdir -p "$_qs"; _qg=$(command -v grep)
  printf '#!/bin/sh\nfor _a in "$@"; do\n  case $_a in\n    *Segmentation*) exit 2 ;;\n  esac\ndone\nexec %s "$@"\n' "$_qg" > "$_qs/grep"; chmod +x "$_qs/grep"
  sfx "crash/5: liveness - the stub passes any other pattern through (rc 1, not 2)" 1 "$( PATH="$_qs:$PATH"; _sr=0; grep -q zzzzz "$_qd" || _sr=$?; echo "$_sr" )"
  sfx "crash/5: a crash scan whose grep cannot run is rc 2, never clean" 2 "$( PATH="$_qs:$PATH"; _sr=0; crash_line_in "$_qd" || _sr=$?; echo "$_sr" )"
  DVOUT=$( PATH="$_qs:$PATH"; cp "$_qd" "$WORK/out"; RUN_RC=0; RUN_S=0; RAN=0; FAILS=0; CRASH=0; CRASH_LIST=""; report_inv core-live "alpha " 0 120; echo "CRASH=$CRASH LIST=$CRASH_LIST" )
  want "crash/5: a unit whose scan cannot run reads UNVERIFIED, never OK" "^  UNVERIFIED  core-live  *alpha .*crash scan could not run: no verdict is claimed"
  want "crash/5: and it is counted as a crash, with the scan-failed suffix" "^CRASH=1 LIST=alpha \[scan failed\]$"
  sfx "crash/5m: the mutation (the scan's failure read as clean) changed the lane" differs "$(lane_mut "$_m" '/# CRFAIL$/s/^\( *\)\*.*/\1*) return 1 ;;/')"
  crash_fns "$_m"
  # shellcheck disable=SC1090  # sources a mutant copy's extracted crash functions (the path is built at run time)
  DVOUT=$( PATH="$_qs:$PATH"; . "$_m.fn"; cp "$_qd" "$WORK/out"; RUN_RC=0; RUN_S=0; RAN=0; FAILS=0; CRASH=0; CRASH_LIST=""; report_inv core-live "alpha " 0 120; echo "CRASH=$CRASH LIST=$CRASH_LIST" )
  wantnot "crash/5m: with the failure read as clean a forced scan failure no longer reads UNVERIFIED, so crash/5 has teeth" "crash scan could not run"
}
crash_c6() {   # controls 6a and 6b - the crash does not cut the run, and the final line orders UNV, CRASH, FAILS
  mkcin 'sh conformance/beta.sh'; mkchk beta 'exit 0'; mkchk secret-scan-wired 'kill -s SEGV $$'; commit_fx; : > "$d/notes.txt"
  rn "$d"
  want "crash/6a: the crashed secret-scan row reads UNVERIFIED by the rc" "^  UNVERIFIED  core-secretscan .*crashed (SEGV, rc 139)"
  want "crash/6a: and the run goes on - a passing touched reader still ran" "^  OK    touched-readers  *beta "
  want "crash/6a: the final line names the crashed unit" "^PARITY-CORE: UNVERIFIED (1 unit(s) crashed: gitleaks range scan ("
  _m=$WORK/lane-600d.sh
  sfx "crash/6am: the mutation (the crash routed through unv) changed the lane" differs "$(lane_mut "$_m" '/# CRCOUNT$/s/^\( *\).*/\1unv "crashed: $2"/')"
  rnl "$_m" "$d"
  wantnot "crash/6am: through unv() the touched-readers arm is cut, so crash/6a has teeth" "^  OK    touched-readers"
  # 6b: exact final lines. A crash beside a failing unit names both; a prior UNVERIFIED reason leads; --best-effort moves the rc only
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'; mkchk alpha 'kill -s SEGV $$'; mkchk beta 'exit 3'; commit_fx
  rn "$d" --warranted
  sfx "crash/6b: a crash beside a failing unit - the final line names both" "PARITY-CORE: UNVERIFIED (1 unit(s) crashed: alpha; plus 1 failing unit(s))" "$(lastline)"
  sfx "crash/6b: rc 1" 1 "$DVRC"
  rn "$d" --warranted --best-effort
  sfx "crash/6b: --best-effort moves the rc only" "0|PARITY-CORE: UNVERIFIED (1 unit(s) crashed: alpha; plus 1 failing unit(s))" "$DVRC|$(lastline)"
  DVOUT=$( UNV="no dash: fixture"; CRASH=1; CRASH_LIST=alpha; FAILS=0; VERBOSE=0; BEST=0; RAN=1; ARGVLOG=/dev/null; verdict 2>&1 ) || :
  sfx "crash/6b: a prior UNVERIFIED reason leads the line" "PARITY-CORE: UNVERIFIED (no dash: fixture; plus 1 unit(s) crashed: alpha)" "$(lastline)"
  sfx "crash/6bm: the mutation (a failing unit outranks a crash) changed the lane" differs "$(lane_mut "$_m" '/# CRVERD$/s/"\$CRASH" -gt 0 \]/"$CRASH" -gt 0 ] \&\& [ "$FAILS" -eq 0 ]/')"
  rnl "$_m" "$d" --warranted
  sfx "crash/6bm: with FAIL outranking the crash the line reads FAIL, so crash/6b has teeth" "PARITY-CORE: FAIL" "$(lastline)"
}
crash_c8() {   # control 8 - a crash-demoted PASS is never written to the --warranted pass cache
  cfx 'printf "%s %s\n" Segmentation "fault: 11"'; cr; cr
  sfx "crash/8: a crash-demoted pass is not cached - the second run executes the check again" 2 "$(nruns)"
  wantnot "crash/8: and no SKIP row stands in for it" "^  SKIP  core-live"
  want "crash/8: the row is the crash" "^  UNVERIFIED  core-live  *alpha .*crashed (Segmentation fault line)"
  _lm8=$WORK/lane-600e.sh   # not _m: cfx owns that name
  sfx "crash/8m: the mutation (the cache guard removed) changed the lane" differs "$(lane_mut "$_lm8" '/# CRCACHE$/s/ && \[ "\$CRASH" -eq "\$_ec_c" \]//')"
  cfx 'printf "%s %s\n" Segmentation "fault: 11"'
  DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_lm8" --base HEAD --warranted 2>&1 ) || :; DVOUT=$( cd "$d" && HOME=$_h PREPUSH_NO_CACHE=0 sh "$_lm8" --base HEAD --warranted 2>&1 ) || :
  sfx "crash/8m: with the guard removed the crash-demoted pass is cached and the second run SKIPs, so crash/8 has teeth" 1 "$(nruns)"
}
crash_c9() {   # control 9 (the split-stderr twin) and the N/A bypass
  [ -n "$KROOT" ] && [ -f "$KROOT/conformance/backlog-lib.sh" ] || { echo "SKIP: crash/9: no backlog-lib.sh to build the twin fixture from - the cell was NOT exercised"; return 0; }
  twfx jira '' 0 0
  mkchk loop-state 'printf "%s %s\n" Segmentation "fault: 11" >&2; exit 0'; commit_fx; rn "$d"
  want "crash/9: a split-stderr twin whose crash line is on stderr alone reads UNVERIFIED" "^  UNVERIFIED  twin  *loop-state .*crashed (Segmentation fault line)"
  wantnot "crash/9: and never an OK row" "^  OK    twin  *loop-state"
  _m=$WORK/lane-600f.sh
  sfx "crash/9m: the mutation (stderr dropped from the capture) changed the lane" differs "$(lane_mut "$_m" '/# CRSPLIT$/d')"
  rnl "$_m" "$d"
  want "crash/9m: with only stdout scanned the twin reads OK, so crash/9 has teeth" "^  OK    twin  *loop-state"
  # the N/A bypass: a hosted-tracker twin at rc 1 whose only stderr is NOT ENFORCED would read N/A beside a crash line on stdout
  twfx jira '' 1 0
  mkchk loop-state 'printf "%s %s\n" Segmentation "fault: 11"; { echo "loop-state: row check NOT ENFORCED: backend x - fixture"; echo "loop-state: FAIL - h does not carry a valid Entry Declaration."; } >&2; exit 1'; commit_fx; rn "$d"
  want "crash/9b: a NOT-ENFORCED twin with a crash line on stdout reads UNVERIFIED, never N/A" "^  UNVERIFIED  twin  *loop-state .*crashed (Segmentation fault line)"
  wantnot "crash/9b: and no N/A row" "^  N/A   loop-state"
  sfx "crash/9bm: the mutation (the crash check before the N/A test removed) changed the lane" differs "$(lane_mut "$_m" '/# CRTWIN$/s/^\( *\).*/\1_tw_c=1/')"
  rnl "$_m" "$d"
  want "crash/9bm: without the check the twin reads N/A, so crash/9b has teeth" "^  N/A   loop-state"
}
crash_c11() {   # control 11 and the ceiling case
  one_step; mkchk alpha 'echo plain failure; exit 1'; commit_fx; rn "$d" --warranted
  want "crash/11: a real failure with no crash line still reads FAIL" "^  FAIL  core-live "
  wantnot "crash/11: and never a crash row" "crashed ("
  sfx "crash/11: the final line is FAIL" "PARITY-CORE: FAIL" "$(lastline)"
  one_step; mkchk alpha 'printf "%s %s\n" Segmentation "fault: 11"; sleep 5'; tw alpha heavy '' '' '' 1 'fixture: a one-second budget'; commit_fx; rn "$d" --slow
  want "crash/12: a unit over its ceiling stays a FAIL and names the crash line beside it" "^  FAIL  heavy .*exceeded ceiling.*; crash line also present (Segmentation fault)"
  sfx "crash/12: the verdict is FAIL, counted in FAILS and not in CRASH" "PARITY-CORE: FAIL" "$(lastline)"
}
crash_cells() { crash_c1; crash_c2; crash_c2p; crash_c2r; crash_c345; crash_c6; crash_c8; crash_c9; crash_c11; }
selftest_crash() {   # control 7 (errata E3): the crash cells run into a file, the file is printed, and the SAME file is rescanned
  _cq=$WORK/crash.cells
  crash_cells > "$_cq" 2>&1 || :
  cat "$_cq"
  _r=0; crash_line_in "$_cq" || _r=$?
  sfx "crash/7: the crash cells' own printed output holds no crash line" 1 "$_r"
  _n=$(grep -c '^PASS' "$_cq" || :)
  if [ "$_n" -ge 45 ]; then echo "PASS: crash/7: the rescanned output is the real one ($_n PASS lines, at least 45)"
  else echo "FAIL: crash/7: the rescanned output holds only $_n PASS lines, want at least 45 (an empty capture would pass vacuously)"; SF=1; fi
  # crash/7m: one crash cell edited (in a lane copy) to print its built crash line on a PASS - the same rescan must find it
  _m=$WORK/lane-600g.sh
  sfx "crash/7m: the mutation (a cell prints its crash line) changed the lane" differs "$(lane_mut "$_m" '/# CQ3$/s/> "\$_qd"/| tee "$_qd"/')"
  _fn=$(sed -n '/^crash_c345() {/,/^}/p' "$_m")
  ( eval "$_fn"; crash_c345 ) > "$WORK/crash.cells.m" 2>&1 || :
  _r=0; crash_line_in "$WORK/crash.cells.m" || _r=$?
  sfx "crash/7m: with one cell printing its crash line the rescan finds it, so crash/7 has teeth" 0 "$_r"
}

# SWAS-784: the run prints `# tree: <root>` after `# work root:`, naming the git toplevel it grades (it refuses nothing: grading another repo's ci.yml is its job in an adopter's own repo).
selftest_tree() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  rn "$d" --warranted
  want "tree/1: the run prints the tree it grades (the fixture's physical root)" "^# tree: $(cd "$d" && pwd -P)\$"
  _m=$WORK/lane-784.sh
  sfx "tree/1m: the mutation (the tree line dropped) changed the lane" differs "$(lane_mut "$_m" '/# TREELINE$/d')"
  rnl "$_m" "$d" --warranted
  wantnot "tree/1m: without the line no tree is named, so tree/1 has teeth" "^# tree: "
}

# ===================================================================================================
# SWAS-568 - the pre-push run log (plan docs/plans/2026-11-12-prepush-run-log-568-plan.md section 5, cells RL1-RL12; design 2026-11-12-ci-local-parity-nightly-design.md P0, errata C1).
# Every cell drives a FIXTURE repo under a PRIVATE HOME (the log has no switch: a selftest isolates it by HOME, as every leg does) and every cell is bound to a MUTANT: a sed on a COPY of the
# lane (trmut) on the `# RL...` tags in the lane's own text, which must turn the same scenario RED. The log is a measurement cache, never evidence: no cell reads it as proof of a run.
RLS_RE='^v1 start run=[0-9]+-[0-9]+ ts=[0-9]+ head=[0-9a-f]{40} base=([0-9a-f]{40}|-) row=([A-Z0-9][A-Z0-9-]{0,31}|-) mode=(default|warranted|green-on-clone|exports|slow|non-vacuity|plan) ci=(default|other) lane=[0-9]+ os=(darwin|linux|other) j=[0-9]+ free_mb=([0-9]+|-) floor_mb=[0-9]+ listing=([0-9]+|-) brule=[a-z,-]+$'
RLE_RE='^v1 end run=[0-9]+-[0-9]+ ts=[0-9]+ verdict=(OK|FAIL|UNVERIFIED|PLAN|INTERRUPTED) rc=([0-9]+|-) wall_s=([0-9]+|-) lock=(held|failed|none) lock_wait_s=([0-9]+|-) ran=[0-9]+ fails=[0-9]+ crash=[0-9]+ u=[^ ]+( trunc=[0-9]+)? jf=[0-9]+ race=[0-9]+$'
rlh() { _rlh_d=$(mktemp -d "${TMPDIR:-/tmp}/fx-rlh-XXXXXX"); printf '%s\n' "$_rlh_d"; }   # a private HOME
rlf() { _rlf_r=$(git -C "$2" rev-list --max-parents=0 HEAD | sed -n 1p); printf '%s\n' "$1/.local/state/sparkwright/prepush/$_rlf_r"; }   # <home> <repo> -> the state dir of that repo
rlc() { _rlc_n=$(grep -Ec -e "$2" "$1" 2>/dev/null || :); printf '%s\n' "${_rlc_n:-0}"; }   # <file> <ERE> -> how many lines match (0 when the file is absent)
rlk() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | sed -n 1p; }   # <record line> <key> -> its value
rlw() { printf '%s\n' "$(lastline)" | sed -n 's/^PARITY-CORE: \([A-Z]*\).*$/\1/p'; }   # the verdict word of the last stdout line
# rnlh <home> <lane> <repo> [args...] -> DVOUT/DVRC, a RUN through <lane> under <home>
rnlh() { _rn_h=$1; _rn_l=$2; _rn_r=$3; shift 3; DVOUT=$( cd "$_rn_r" && HOME=$_rn_h sh "$_rn_l" --base HEAD "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }
# RL1 - exactly one start and one end record per run, matching the v1 grammar, sharing one run id.
selftest_runlog_lines() {
  one_step; mkchk alpha 'exit 0'; commit_fx; _h=$(rlh); rnh "$_h" "$d" --warranted; _lg=$(rlf "$_h" "$d")/runs.log
  sfx "runlog/RL1: a run writes exactly one start record" 1 "$(rlc "$_lg" '^v1 start ')"
  sfx "runlog/RL1: and exactly one end record" 1 "$(rlc "$_lg" '^v1 end ')"
  sfx "runlog/RL1: the start record matches the v1 grammar" 1 "$(rlc "$_lg" "$RLS_RE")"
  sfx "runlog/RL1: and the end record does" 1 "$(rlc "$_lg" "$RLE_RE")"
  sfx "runlog/RL1: both carry the same run id" 1 "$(sed -n 's/^v1 [a-z]* run=\([^ ]*\) .*$/\1/p' "$_lg" | sort -u | grep -c . || :)"
  trmut rl1 -e '/# RLSTART$/d'
  [ -z "$TRM" ] || { _h=$(rlh); rnlh "$_h" "$TRM" "$d" --warranted
    sfx "runlog/RL1 mutant: with the start call gone no record is written (the cell is RED)" 0 "$(rlc "$(rlf "$_h" "$d")/runs.log" '^v1 ')"; }
}
# RL2 - the fields: head, row, mode, the resolved base sha (never the --base text), the verdict and rc the run printed and returned.
selftest_runlog_fields() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  ( cd "$d" && git -c user.email=f@x -c user.name=f commit -q --allow-empty -m rl -m 'Kit-Row: SWAS-568' && git branch rlbase HEAD ) >/dev/null
  _hd=$(git -C "$d" rev-parse HEAD); _h=$(rlh); rnh "$_h" "$d" --warranted --base rlbase; _lg=$(rlf "$_h" "$d")/runs.log
  _s=$(grep '^v1 start ' "$_lg" | sed -n 1p); _e=$(grep '^v1 end ' "$_lg" | sed -n 1p)
  sfx "runlog/RL2: head is the fixture's HEAD" "$_hd" "$(rlk "$_s" head)"
  sfx "runlog/RL2: row is HEAD's Kit-Row trailer" SWAS-568 "$(rlk "$_s" row)"
  sfx "runlog/RL2: mode is warranted under --warranted" warranted "$(rlk "$_s" mode)"
  sfx "runlog/RL2: base is the resolved sha even when --base names a branch" "$_hd" "$(rlk "$_s" base)"
  sfx "runlog/RL2: verdict and rc equal the last stdout line and the exit status" "$(rlw)|$DVRC" "$(rlk "$_e" verdict)|$(rlk "$_e" rc)"
  trmut rl2 -e '/# RLBASE$/s/^\( *_rl_base=\).*$/\1$BASE/'
  [ -z "$TRM" ] || { _h2=$(rlh); rnlh "$_h2" "$TRM" "$d" --warranted --base rlbase
    sfx "runlog/RL2 mutant: base= taken from the --base text is not the sha (the cell is RED)" differs "$([ "$(rlk "$(grep '^v1 start ' "$(rlf "$_h2" "$d")/runs.log" | sed -n 1p)" base)" = "$_hd" ] && echo same || echo differs)"; }
  mkchk alpha 'exit 3'; commit_fx; _h=$(rlh); rnh "$_h" "$d" --warranted; _e=$(grep '^v1 end ' "$(rlf "$_h" "$d")/runs.log" | sed -n 1p)
  sfx "runlog/RL2: a failing run logs FAIL, rc 1 and one failing unit" "FAIL|1|1" "$(rlk "$_e" verdict)|$(rlk "$_e" rc)|$(rlk "$_e" fails)"
  sfx "runlog/RL2: and the verdict word is the one the run printed" "FAIL" "$(rlw)"
}
# RL3 - one unit per verdict row, and `ran` counts them.
selftest_runlog_complete() {
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'; mkchk alpha 'exit 0'; mkchk beta 'exit 3'; commit_fx
  _h=$(rlh); rnh "$_h" "$d" --warranted; _lg=$(rlf "$_h" "$d")/runs.log; _e=$(grep '^v1 end ' "$_lg" | sed -n 1p)
  _rows=$(printf '%s\n' "$DVOUT" | grep -Ec '^  (OK|FAIL|UNVERIFIED|SKIP|N/A) ' || :)
  sfx "runlog/RL3: the units listed equal the verdict rows printed" "$_rows" "$(rlk "$_e" u | tr ',' '\n' | grep -c . || :)"
  sfx "runlog/RL3: and ran counts the same invocations" "$_rows" "$(rlk "$_e" ran)"
  trmut rl3 -e '/# RLRI$/d'
  [ -z "$TRM" ] || { _h2=$(rlh); rnlh "$_h2" "$TRM" "$d" --warranted
    _e2=$(grep '^v1 end ' "$(rlf "$_h2" "$d")/runs.log" | sed -n 1p)
    sfx "runlog/RL3 mutant: with rl_u gone from report_inv the units no longer match the rows (the cell is RED)" differs "$([ "$(rlk "$_e2" u | tr ',' '\n' | grep -c . || :)" = "$_rows" ] && echo same || echo differs)"; }
}
# RL4 - a planted secret (one [a-z0-9] token, so it passes every charset) in an env var, GH_TOKEN, KIT_CI_FILE, the --base branch, HOME, the root path and a Kit-Row is never in the log.
selftest_runlog_secret() {
  _pl=zq7x3k9plantv
  one_step; mkchk alpha 'exit 0'; commit_fx
  ( cd "$d" && git -c user.email=f@x -c user.name=f commit -q --allow-empty -m rl -m "Kit-Row: $_pl" && git branch "br-$_pl" HEAD ) >/dev/null
  mv "$d" "$WORK/root-$_pl"; d=$WORK/root-$_pl; cp "$d/.github/workflows/ci.yml" "$d/.github/workflows/ci-$_pl.yml"
  _h=$WORK/h-$_pl; mkdir -p "$_h"
  DVOUT=$( cd "$d" && RLPLANT_X=$_pl GH_TOKEN=$_pl HOME=$_h sh "$LANE" --base "br-$_pl" --warranted 2>&1 ) && DVRC=0 || DVRC=$?
  want "runlog/RL4 control: the plant is on stdout (the base and tree lines)" "^# base: br-$_pl "
  want "runlog/RL4 control: and the tree line" "^# tree: .*root-$_pl\$"
  DVOUT=$( cd "$d" && RLPLANT_X=$_pl GH_TOKEN=$_pl KIT_CI_FILE=.github/workflows/ci-$_pl.yml HOME=$_h sh "$LANE" --base "br-$_pl" 2>&1 ) && DVRC=0 || DVRC=$?
  want "runlog/RL4 control: and the ci-file line" "^# ci-file: .github/workflows/ci-$_pl.yml\$"
  _sd=$(rlf "$_h" "$d")
  sfx "runlog/RL4 control: both runs wrote their records (the log exists)" 4 "$(rlc "$_sd/runs.log" '^v1 ')"
  sfx "runlog/RL4: the plant is nowhere in the log" 0 "$(cat "$_sd"/runs.log* 2>/dev/null | grep -cF -e "$_pl" || :)"
  trmut rl4a -e '/# RLLANE$/s/^.*$/  _rl_lane=$ROOT/'
  [ -z "$TRM" ] || { _h2=$WORK/h2-$_pl; mkdir -p "$_h2"; rnlh "$_h2" "$TRM" "$d"
    sfx "runlog/RL4 mutant: lane= taken from the root path leaks the plant (the cell is RED)" yes "$([ "$(cat "$(rlf "$_h2" "$d")"/runs.log* 2>/dev/null | grep -cF -e "$_pl" || :)" -gt 0 ] && echo yes || echo no)"; }
  trmut rl4b -e '/# RLROW$/s/^.*$/  _rl_row=$_rl_row0/'
  [ -z "$TRM" ] || { _h3=$WORK/h3-$_pl; mkdir -p "$_h3"; rnlh "$_h3" "$TRM" "$d"
    sfx "runlog/RL4 mutant: row= without its charset check leaks a lowercase Kit-Row (the cell is RED)" yes "$([ "$(cat "$(rlf "$_h3" "$d")"/runs.log* 2>/dev/null | grep -cF -e "$_pl" || :)" -gt 0 ] && echo yes || echo no)"; }
}
# RL5 - rotation keeps three files (the card's own 1 MB cap, scaled in a lane COPY, never a knob).
selftest_runlog_rotate() {
  _sc=$WORK/lane-rl5.sh; sed 's/^RL_CAP=1048576$/RL_CAP=300/' "$LANE" > "$_sc"
  sfx "runlog/RL5: the scaled lane copy differs" differs "$(cmp -s "$LANE" "$_sc" && echo same || echo differs)"
  one_step; mkchk alpha 'exit 0'; commit_fx; _h=$(rlh); _i=0
  while [ "$_i" -lt 4 ]; do rnlh "$_h" "$_sc" "$d"; _i=$((_i+1)); done
  _sd=$(rlf "$_h" "$d")
  sfx "runlog/RL5: the first rotated file exists" yes "$([ -f "$_sd/runs.log.1" ] && echo yes || echo no)"
  sfx "runlog/RL5: and the third" yes "$([ -f "$_sd/runs.log.3" ] && echo yes || echo no)"
  sfx "runlog/RL5: no fourth is ever made" no "$([ -e "$_sd/runs.log.4" ] && echo yes || echo no)"
  sfx "runlog/RL5: the live log stays under twice the cap" yes "$([ "$(wc -c < "$_sd/runs.log" | tr -d ' ')" -lt 600 ] && echo yes || echo no)"
  TRSRC=$_sc trmut rl5 -e '/# RLROT$/d'
  [ -z "$TRM" ] || { _h2=$(rlh); _i=0; while [ "$_i" -lt 4 ]; do rnlh "$_h2" "$TRM" "$d"; _i=$((_i+1)); done
    sfx "runlog/RL5 mutant: with the rotation gone the live log grows past twice the cap (the cell is RED)" yes "$([ "$(wc -c < "$(rlf "$_h2" "$d")/runs.log" | tr -d ' ')" -ge 600 ] && echo yes || echo no)"; }
}
# RL6 - an unsafe state dir or log turns the log off with ONE note, writes nothing through a link, and never moves the verdict or the rc; a write failure is dropped, never an unv.
selftest_runlog_unsafe() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  _h0=$(rlh); rnh "$_h0" "$d"; _cl=$(lastline); _cr=$DVRC
  _h=$(rlh); _sd=$(rlf "$_h" "$d"); mkdir -p "$_sd"; chmod 777 "$_sd"; rnh "$_h" "$d"
  sfx "runlog/RL6: a group/world-writable state dir leaves the verdict and the rc as they were" "$_cl|$_cr" "$(lastline)|$DVRC"
  sfx "runlog/RL6: and says so once" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^# run log: off' || :)"
  sfx "runlog/RL6: and writes nothing into it" 0 "$(ls -A "$_sd" | wc -l | tr -d ' ')"
  _h=$(rlh); _sd=$(rlf "$_h" "$d"); mkdir -p "$_sd"; chmod 700 "$_sd"; _tg=$WORK/rl6-target; printf 'keep\n' > "$_tg"; ln -s "$_tg" "$_sd/runs.log"; rnh "$_h" "$d"
  sfx "runlog/RL6: a symlinked log leaves the verdict and the rc as they were" "$_cl|$_cr" "$(lastline)|$DVRC"
  sfx "runlog/RL6: and nothing is written through the link" keep "$(cat "$_tg")"
  sfx "runlog/RL6: with one note" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^# run log: off' || :)"
  _h=$(rlh); _sd=$(rlf "$_h" "$d"); mkdir -p "$_sd/runs.log"; chmod 700 "$_sd"; rnh "$_h" "$d"
  sfx "runlog/RL6: a log that is a directory leaves the verdict and the rc as they were" "$_cl|$_cr" "$(lastline)|$DVRC"
  sfx "runlog/RL6: with one note" 1 "$(printf '%s\n' "$DVOUT" | grep -c '^# run log: off' || :)"
  _h=$(rlh); _sd=$(rlf "$_h" "$d"); mkdir -p "$_sd"; chmod 700 "$_sd"
  _o=$( cd "$d"; hl_owner() { echo some-other-user; }; HOME=$_h; RL_ON=1; rl_init; printf 'on=%s\n' "$RL_ON" ) || :; DVOUT=$_o
  want "runlog/RL6: a foreign-owned state dir turns the log off" "^on=0$"
  want "runlog/RL6: with the note naming the owner" "^# run log: off — the state dir is not owned by the current user"
  if [ "$(id -u)" = 0 ]; then echo "SKIP: runlog/RL6: running as root - mode 444 does not stop root, so the write-failure cell was NOT exercised"; return 0; fi
  _h=$(rlh); _sd=$(rlf "$_h" "$d"); mkdir -p "$_sd"; chmod 700 "$_sd"; : > "$_sd/runs.log"; chmod 444 "$_sd/runs.log"; rnh "$_h" "$d"
  sfx "runlog/RL6: a log that cannot be written leaves the verdict and the rc as they were" "$_cl|$_cr" "$(lastline)|$DVRC"
  trmut rl6 -e '/# RLWRITE$/s/|| :/|| unv "run log write failed"/'
  [ -z "$TRM" ] || { rnlh "$_h" "$TRM" "$d"
    sfx "runlog/RL6 mutant: a write failure that calls unv moves the verdict (the cell is RED)" differs "$([ "$(lastline)|$DVRC" = "$_cl|$_cr" ] && echo same || echo differs)"; }
}
# RL7 - a TERM mid-unit ends the log with INTERRUPTED; a KILL to the lane alone leaves a start with no end, which --log-report counts as incomplete.
selftest_runlog_interrupt() {
  _oh=$HOME; _h=$(rlh); HOME=$_h; export HOME; k5_run "$LANE"; HOME=$_oh; export HOME
  sfx "runlog/RL7: a TERM to the lane ends it as the orphan cell expects" ok "$K5R"
  _lg=$(rlf "$_h" "$d")/runs.log
  sfx "runlog/RL7: the interrupted run left an end record with verdict INTERRUPTED" 1 "$(rlc "$_lg" '^v1 end .* verdict=INTERRUPTED ')"
  sfx "runlog/RL7: and the record matches the grammar" 1 "$(rlc "$_lg" "$RLE_RE")"
  _h2=$(rlh); HOME=$_h2; export HOME; k5_run "$LANE" kill; HOME=$_oh; export HOME
  DVOUT=$( cd "$d" && HOME=$_h2 sh "$LANE" --log-report --base HEAD 2>&1 ) || :
  want "runlog/RL7: a KILL to the lane alone is counted by --log-report as one incomplete run" "^# runs: 1 started, 0 ended, 1 incomplete"
}
# RL8 - the sampled peak RSS: a unit holding about 64 MB reads at least 40000 KB; no process group reads `-`; the sampler line deleted reads `-`.
selftest_runlog_rss() {
  [ -x /usr/bin/perl ] || { echo "SKIP: runlog/RL8: /usr/bin/perl is absent - there is no process group, so the sampler was NOT exercised here"; return 0; }
  one_step; mkchk alpha "/usr/bin/perl -e 'my \$x = q(a) x 67108864; sleep 3'"; commit_fx
  _h=$(rlh); rnh "$_h" "$d" --warranted; _e=$(grep '^v1 end ' "$(rlf "$_h" "$d")/runs.log" | sed -n 1p)
  _kb=$(rlk "$_e" u | tr ',' '\n' | sed -n 's/^core-live:alpha:OK:[0-9]*:\([0-9-]*\)$/\1/p')
  sfx "runlog/RL8: a unit holding about 64 MB reads at least 40000 KB" yes "$([ "${_kb:--}" != - ] && [ "${_kb:-0}" -ge 40000 ] && echo yes || echo no)"
  trmut rl8 -e '/# RLRSS$/d'
  [ -z "$TRM" ] || { _h2=$(rlh); rnlh "$_h2" "$TRM" "$d" --warranted; _e2=$(grep '^v1 end ' "$(rlf "$_h2" "$d")/runs.log" | sed -n 1p)
    _kb2=$(rlk "$_e2" u | tr ',' '\n' | sed -n 's/^core-live:alpha:OK:[0-9]*:\([0-9-]*\)$/\1/p')
    sfx "runlog/RL8 mutant: with the sampler line gone the unit reads - (the cell is RED)" no "$([ "${_kb2:--}" != - ] && [ "${_kb2:-0}" -ge 40000 ] && echo yes || echo no)"; }
  trmut rl8n -e 's|^ARM_PERL=.*$|ARM_PERL=/nonexistent/perl|'
  [ -z "$TRM" ] || { _h3=$(rlh); rnlh "$_h3" "$TRM" "$d" --warranted; _e3=$(grep '^v1 end ' "$(rlf "$_h3" "$d")/runs.log" | sed -n 1p)
    sfx "runlog/RL8: with no process group the unit reads - (unavailable: no process group)" "-" "$(rlk "$_e3" u | tr ',' '\n' | sed -n 's/^core-live:alpha:OK:[0-9]*:\([0-9-]*\)$/\1/p')"; }
}
# RL9 - the battery-rule probe: one listing per clause gives its letter, docs-only gives none; clause (b) is labelled partial until P4 names the sourced and fixture paths; a run logs it from the real listing.
selftest_runlog_brule() {
  brl() { printf '%b' "$1" | battery_rule; }
  sfx "runlog/RL9: .claude/ is clause a" a "$(brl 'M\t.claude/settings.json\n')"
  sfx "runlog/RL9: hooks/ is clause a" a "$(brl 'M\thooks/pre-push\n')"
  sfx "runlog/RL9: the battery's own script is clause b, labelled partial" b-partial "$(brl 'M\tconformance/agent-autonomy.sh\n')"
  sfx "runlog/RL9: an added scripts/ file is clause c" c "$(brl 'A\tscripts/new.sh\n')"
  sfx "runlog/RL9: a deleted conformance/ file is clause c" c "$(brl 'D\tconformance/old.sh\n')"
  sfx "runlog/RL9: a mode change under scripts/ is clause c" c "$(brl 'T\tscripts/x.sh\n')"
  sfx "runlog/RL9: an edit to an existing scripts/ file is none" none "$(brl 'M\tscripts/x.sh\n')"
  sfx "runlog/RL9: .github/workflows/ is clause d" d "$(brl 'M\t.github/workflows/ci.yml\n')"
  sfx "runlog/RL9: .kit/ is clause d" d "$(brl 'M\t.kit/tracker.conf\n')"
  sfx "runlog/RL9: an empty listing is clause e" e "$(brl '')"
  sfx "runlog/RL9: a docs-only listing is none" none "$(brl 'M\tdocs/x.md\n')"
  sfx "runlog/RL9: clauses join in a fixed order" "a,c" "$(brl 'A\thooks/x\n')"
  trmut rl9 -e '/# RLCC$/s/^.*$/    # RLCC/'
  [ -z "$TRM" ] || { sed -n '/^battery_rule() {$/,/^}$/p' "$TRM" > "$WORK/rl9.fn"
    _r=$( . "$WORK/rl9.fn"; printf 'A\tscripts/new.sh\n' | battery_rule )
    sfx "runlog/RL9 mutant: with clause c dropped an added scripts/ file reads none (the cell is RED)" differs "$([ "$_r" = c ] && echo same || echo differs)"; }
  # a path holding a newline and a fake header must not drop the next real path, and must fire e (unknown fires)
  _nlr=$( printf ':100644 100644 aaa bbb M\000x\n:100644 100644 aaa bbb D\000:000000 100644 aaa bbb A\000scripts/y.sh\000' | tr '\000' '\001' | br_norm | battery_rule )
  sfx "runlog/RL9: a newline in a path fires e and the next real path is still read (c)" "c,e" "$_nlr"
  trmut rl9n -e '/# RLNL$/d'
  [ -z "$TRM" ] || { sed -n '/^br_norm() {$/,/^}$/p' "$TRM" > "$WORK/rl9n.fn"; sed -n '/^battery_rule() {$/,/^}$/p' "$TRM" >> "$WORK/rl9n.fn"
    _r=$( . "$WORK/rl9n.fn"; printf ':100644 100644 aaa bbb M\000x\n:100644 100644 aaa bbb D\000:000000 100644 aaa bbb A\000scripts/y.sh\000' | tr '\000' '\001' | br_norm | battery_rule )
    sfx "runlog/RL9 mutant: with the newline test gone the newline path no longer fires e (the cell is RED)" differs "$([ "$_r" = "c,e" ] && echo same || echo differs)"; }
  one_step; mkchk alpha 'exit 0'; commit_fx; mkdir -p "$d/hooks"; : > "$d/hooks/x"
  _h=$(rlh); rnh "$_h" "$d"; _s=$(grep '^v1 start ' "$(rlf "$_h" "$d")/runs.log" | sed -n 1p)
  sfx "runlog/RL9: a run logs the clauses of its own listing (an untracked hooks/ file is a and c)" "a,c" "$(rlk "$_s" brule)"
}
# RL10 - --log-report: the guard-touching share over the first-parent history (here 3 of 10), from local refs only (a gh stub is never called), and an empty log prints unavailable.
selftest_runlog_report() {
  d=$(mkrepo); printf 'r\n' > "$d/README"
  ( cd "$d" && git add README && git -c user.email=f@x -c user.name=f commit -qm root ) >/dev/null
  _n=0
  for _k in docs hooks docs docs hooks docs docs hooks docs; do
    _n=$((_n+1))
    case $_k in
      hooks) mkdir -p "$d/hooks"; printf '%s\n' "$_n" > "$d/hooks/pre-push"; _f=hooks/pre-push ;;
      *) mkdir -p "$d/docs"; printf '%s\n' "$_n" > "$d/docs/n$_n.md"; _f=docs/n$_n.md ;;
    esac
    ( cd "$d" && git add "$_f" && git -c user.email=f@x -c user.name=f commit -qm "c$_n" ) >/dev/null
  done
  _h=$(rlh); _gd=$WORK/gh-stub; mkdir -p "$_gd"; printf '#!/bin/sh\n: > "%s/called"\nexit 1\n' "$_gd" > "$_gd/gh"; chmod +x "$_gd/gh"
  DVOUT=$( cd "$d" && PATH="$_gd:$PATH" HOME=$_h sh "$LANE" --log-report --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "runlog/RL10: the report is rc 0" 0 "$DVRC"
  want "runlog/RL10: the guard-touching share is 3 of 10" "^# guard-touching share .*: 3/10 "
  want "runlog/RL10: the battery-rule share is 3 of 10 too (every hooks/ change fires clause a)" "^# battery-rule share .*: 3/10 "
  want "runlog/RL10: it says as of which local ref and commit" "as of local HEAD [0-9a-f]\{12\}"
  want "runlog/RL10: an empty log prints unavailable, never a zero" "^# run log: unavailable"
  sfx "runlog/RL10: and no gh call was made" no "$([ -e "$_gd/called" ] && echo yes || echo no)"
  DVOUT=$( cd "$d" && HOME=$_h sh "$LANE" --log-report 2>&1 ) && DVRC=0 || DVRC=$?
  want "runlog/RL10: a base that does not resolve locally is unavailable, with no fetch" "^# merged-PR share: unavailable: origin/main does not resolve"
}
# RL11 (selftest_no_write, above, carries the repo-untouched assertions) and RL12 - the run path never reads runs.log: a garbage log changes neither the verdict nor the rc, and --log-report skips and counts what is malformed.
selftest_runlog_unread() {
  one_step; mkchk alpha 'exit 0'; commit_fx
  _h0=$(rlh); rnh "$_h0" "$d"; _cl=$(lastline); _cr=$DVRC
  _h=$(rlh); _sd=$(rlf "$_h" "$d"); mkdir -p "$_sd"; chmod 700 "$_sd"
  { printf 'v1 start run=1-1 verdict=OK \001 $(touch %s/pwned) ; PARITY-CORE: OK\n' "$WORK"; printf '%0100d\n' 0; printf 'v1 end run=zz u=\n'; } > "$_sd/runs.log"
  rnh "$_h" "$d"
  sfx "runlog/RL12: a garbage log changes neither the verdict nor the rc" "$_cl|$_cr" "$(lastline)|$DVRC"
  sfx "runlog/RL12: and nothing in it was run" no "$([ -e "$WORK/pwned" ] && echo yes || echo no)"
  DVOUT=$( cd "$d" && HOME=$_h sh "$LANE" --log-report --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "runlog/RL12: --log-report skips and counts the malformed lines" "; 3 malformed line(s) skipped"
}

# ===================================================================================================
# SWAS-868 (P2 of the local-parity design, PR 1) - the bounded pool. Plan docs/plans/2026-11-13-prepush-parallel-pool-868-plan.md section 2/T1: cells PL1 (selftest_bounded_fanout, above), PL2-PL21, PLR, RL13.
# Every pool cell runs a fixture through LANE_J2 (J is 2) and carries a MUTANT: a sed on a COPY of the lane (trmut with TRSRC=$LANE_J2, or lane_mut with LM_SRC) on the `# PL...` / `# PS...` tags in the lane's own text.
# plr <home> <lane> [args...] — a RUN of $d against the delta _stb with the cache ON in <home> -> DVOUT/DVRC.
plr() { _plh=$1; _pll=$2; shift 2; DVOUT=$( cd "$d" && env HOME="$_plh" PREPUSH_NO_CACHE=0 sh "$_pll" --base "$_stb" "$@" 2>&1 ) && DVRC=0 || DVRC=$?; }
pl_end() { grep '^v1 end ' "$(rlf "$1" "$d")/runs.log" | sed -n 1p; }   # <home> -> its first end record
pl_units() { rlk "$1" u | tr ',' '\n' | awk -F: '{ print $1 ":" $2 ":" $3 }' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }   # <end record> -> sorted bucket:name:verdict
pl_times() { printf '%s\n' "$1/.local/state/sparkwright/prepush/$(git -C "$d" rev-list --max-parents=0 HEAD | sed -n 1p)/times.tsv"; }   # <home> -> its times table
pl_pkrows() { awk -F'\t' '$1 == "@pool-k" { print $2 " " $3 }' "$(pl_times "$1")" 2>/dev/null || :; }   # <home> -> one "key blob" per @pool-k row
pl_ncount() { grep -c -e "$2" "$1" 2>/dev/null || :; }
pl_racefx() {   # alpha holds `busy` until beta has checked it; beta fails if it sees `busy`: in parallel beta fails, alone it passes
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  mkchk alpha ': > "$PWD/busy"; : > "$PWD/a.started"; _i=0; while [ ! -e "$PWD/b.checked" ] && [ "$_i" -lt 100 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i+1)); done; rm -f "$PWD/busy"'
  mkchk beta '_i=0; while [ ! -e "$PWD/a.started" ] && [ "$_i" -lt 100 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i+1)); done; : > "$PWD/b.checked"; [ ! -e "$PWD/busy" ] || exit 1'
  commit_fx
}
pl_racerm() { rm -f "$d/busy" "$d/a.started" "$d/b.checked"; }
# pl_eqrun <label> <lane-a> <lane-b> [args...] — the same fixture through two lanes under their own HOMEs: verdict line, rc and sorted units must be equal
pl_eqrun() {
  _pel=$1; _pla=$2; _plb=$3; shift 3
  _pha=$(rlh); plr "$_pha" "$_pla" "$@"; PL_DVA=$DVOUT; _pva=$(lastline); _pra=$DVRC; _pua=$(pl_units "$(pl_end "$_pha")")
  _phb=$(rlh); plr "$_phb" "$_plb" "$@"; _pvb=$(lastline); _prb=$DVRC; _pub=$(pl_units "$(pl_end "$_phb")")
  sfx "$_pel: the verdict line is the same at J = 1 and J = 2" "$_pva" "$_pvb"
  sfx "$_pel: and the rc" "$_pra" "$_prb"
  sfx "$_pel: and the sorted units" "$_pua" "$_pub"
  PL_EQU=$_pub
}
# PL2 - J is never settable
selftest_pool_unsettable() {
  one_step; mkchk alpha 'exit 0'; commit_fx; _pp=PREPUSH_
  DVOUT=$( cd "$d" && env POOL_J=9 KIT_POOL_J=9 "${_pp}J=9" "${_pp}POOL_J=9" "${_pp}POOL_U_MB=1" sh "$LANE_J2" --base HEAD 2>&1 ) && DVRC=0 || DVRC=$?
  want "PL2a: J-shaped environment names leave the derived J alone" "^# pool: J=2 "
  DVOUT=$( cd "$d" && sh "$LANE_J2" --base HEAD --j 9 2>&1 ) && DVRC=0 || DVRC=$?
  sfx "PL2a: --j 9 is a usage error, rc 2" 2 "$DVRC"
  _sub="  POOL_J=\${${_pp}J:-\$_pj_j}   # PLJSET"
  TRSRC=$LANE_J2 trmut pl2a -e "/# PLJSET\$/s/.*/$_sub/"
  [ -z "$TRM" ] || { DVOUT=$( cd "$d" && env "${_pp}J=9" sh "$TRM" --base HEAD 2>&1 ) || :
    wantnot "PL2a mutant: with J read from the environment the name moves it (the cell is RED)" "^# pool: J=2 "; }
  if [ "$(uname -s)" = Darwin ]; then
    _pb2=$WORK/pl2b-bin; mkdir -p "$_pb2"
    printf '#!/bin/sh\nprintf "Mach Virtual Memory Statistics: (page size of 4096 bytes)\\nPages free: 99999999999.\\n"\n' > "$_pb2/vm_stat"
    printf '#!/bin/sh\necho 99999999999\n' > "$_pb2/awk"; chmod +x "$_pb2/vm_stat" "$_pb2/awk"
    _jr=$( PATH="$_pb2:$PATH"; pool_cores() { echo 64; }; pool_j; echo "$POOL_J" ) || _jr=err
    sfx "PL2b: with 64 cores and a planted vm_stat/awk the J stays under 63 (the absolute-path memory read decides)" yes "$([ "$_jr" -lt 63 ] 2>/dev/null && echo yes || echo "J=$_jr")"
    _jm=$( PATH="$_pb2:$PATH"; pool_cores() { echo 64; }; pool_free_mb() { mem_free_mb; }; pool_j; echo "$POOL_J" ) || _jm=err
    sfx "PL2b mutant: with pool_free_mb reading through PATH the planted memory gives J = 63 (the cell is RED)" 63 "$_jm"
  else echo "PL2b: not graded on Linux (reads /proc/meminfo)"; fi
  sfx "PL2c: exactly one POOL_U_MB=1536 line" 1 "$(grep -c '^POOL_U_MB=1536$' "$LANE_REAL" || :)"
  _pf=$(sed -n '/^pool_cores() {/,/^}/p;/^pool_free_mb() {/,/^}/p' "$LANE_REAL")
  sfx "PL2c: getconf, vm_stat and awk are called by absolute path" yes "$([ "$(printf '%s\n' "$_pf" | grep -c '/usr/bin/getconf' || :)" -ge 1 ] && [ "$(printf '%s\n' "$_pf" | grep -c '/usr/bin/vm_stat' || :)" -ge 1 ] && [ "$(printf '%s\n' "$_pf" | grep -c '/usr/bin/awk' || :)" -ge 1 ] && echo yes || echo no)"
  sfx "PL2c: pool_j reads no environment name" 0 "$(sed -n '/^pool_j() {/,/^}/p' "$LANE_REAL" | grep -c -e 'PREPUSH_' -e 'KIT_' -e 'ENVIRON' || :)"
  trmut pl2c -e "s/^POOL_U_MB=1536\$/POOL_U_MB=\${${_pp}POOL_U_MB:-1536}/"
  [ -z "$TRM" ] || sfx "PL2c mutant: with an environment read there is no literal POOL_U_MB=1536 line (the cell is RED)" 0 "$(grep -c '^POOL_U_MB=1536$' "$TRM" || :)"
  echo "PASS: PL2d: the review read (J has no environment, argv or PATH feed) is the reviewer's, not a cell's"
}
# PL3 - per-unit dirs
selftest_pool_dirs() {
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  for _n in alpha beta; do mkchk "$_n" 'printf "%s\n%s\n%s\n" "$TMPDIR" "$HOME" "$GH_CONFIG_DIR" > "$PWD/dirs.'"$_n"'"; sleep 1'; done
  commit_fx; rnl "$LANE_J2" "$d" --warranted
  sfx "PL3: two pooled probes see six distinct dirs (TMPDIR, HOME, GH_CONFIG_DIR each)" 6 "$(cat "$d/dirs.alpha" "$d/dirs.beta" 2>/dev/null | sort -u | grep -c . || :)"
  TRSRC=$LANE_J2 trmut pl3 -e '/# PLUDIR$/d'
  [ -z "$TRM" ] || { rm -f "$d/dirs.alpha" "$d/dirs.beta"; rnl "$TRM" "$d" --warranted
    sfx "PL3 mutant: with the unit dir not handed over both probes share the work root's dirs (the cell is RED)" 3 "$(cat "$d/dirs.alpha" "$d/dirs.beta" 2>/dev/null | sort -u | grep -c . || :)"; }
}
# PL5 - longest first
selftest_pool_order() {
  stfx "$STREC" scripts/u.sh scripts/s5.sh scripts/s3.sh scripts/s1.sh
  _b5=$(git -C "$d" rev-parse HEAD:scripts/s5.sh); _b3=$(git -C "$d" rev-parse HEAD:scripts/s3.sh); _b1=$(git -C "$d" rev-parse HEAD:scripts/s1.sh)
  _h=$WORK/pl5-h
  pl_ord() { printf '%s\n' "$DVOUT" | sed -n 's/^#   sh conformance\/selftest-hermetic\.sh scripts\/\([a-z0-9]*\)\.sh$/\1/p' | tr '\n' ' ' | sed 's/ $//'; }
  stt "$_h" "$_b5=5" "$_b3=3" "$_b1=1"; plr "$_h" "$LANE_J2" --verbose
  sfx "PL5: the queue is the unmeasured unit first, then descending seconds" "u s5 s3 s1" "$(pl_ord)"
  TRSRC=$LANE_J2 trmut pl5a -e '/# PLSORT$/s/-k2,2nr/-k2,2n/'
  [ -z "$TRM" ] || { stt "$_h" "$_b5=5" "$_b3=3" "$_b1=1"; plr "$_h" "$TRM" --verbose; sfx "PL5 mutant: ascending seconds (the cell is RED)" differs "$([ "$(pl_ord)" = 'u s5 s3 s1' ] && echo same || echo differs)"; }
  TRSRC=$LANE_J2 trmut pl5b -e '/# PLSORT$/s/-k1,1n/-k1,1nr/'
  [ -z "$TRM" ] || { stt "$_h" "$_b5=5" "$_b3=3" "$_b1=1"; plr "$_h" "$TRM" --verbose; sfx "PL5 mutant: unmeasured last (the cell is RED)" differs "$([ "$(pl_ord)" = 'u s5 s3 s1' ] && echo same || echo differs)"; }
}
# PL6, PL7 - RACE never masks a real FAIL; a race reads RACE
selftest_pool_race() {
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'; mkchk alpha 'sleep 1; exit 1'; mkchk beta 'sleep 1; exit 0'; commit_fx
  rnl "$LANE_J2" "$d" --warranted
  want "PL6: an always-failing probe reads FAIL after the serial confirm" "^  FAIL  core-live *alpha .*rc=1 (expected 0)"
  wantnot "PL6: and no RACE is claimed" "RACE"
  sfx "PL6: the verdict is FAIL" "PARITY-CORE: FAIL" "$(lastline)"
  TRSRC=$LANE_J2 trmut pl6 -e '/# PLRACE$/s/.*/  _pt_pass=1   # PLRACE/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --warranted; want "PL6 mutant: with the confirm's result ignored the failure reads as a race (the cell is RED)" "RACE"; }
  pl_racefx; _h=$(rlh); rnlh "$_h" "$LANE_J2" "$d" --warranted
  want "PL7: a race reads RACE" "^# RACE: beta failed in parallel, passed serially"
  sfx "PL7: the verdict is OK and names the race (S-4)" "PARITY-CORE: OK (1 RACE)" "$(lastline)"
  PL_RH=$_h; PL_RD=$d; PL_RDV=$DVOUT   # PL10 and PL15 read this run (one J = 2 race run that really raced, asserted by three cells)
  sfx "PL7: u= holds RACE for it" 1 "$(rlk "$(pl_end "$_h")" u | tr ',' '\n' | grep -c '^core-live:beta:RACE:' || :)"
  TRSRC=$LANE_J2 trmut pl7 -e '/# PLTAIL$/s/.*/  :   # PLTAIL/'
  [ -z "$TRM" ] || { pl_racerm; rnl "$TRM" "$d" --warranted; wantnot "PL7 mutant: with the confirm skipped no RACE is found (the cell is RED)" "RACE"; }
}
# k5p_run <lane> — a TERM to the LANE pid only while two pooled arms run, each with a TERM-ignoring grandchild (only the KILL ends it): lane rc 143, every group and grandchild gone within 9 s. Sets K5R.
k5p_run() {
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  for _n in alpha beta; do mkchk "$_n" 'echo $$ > "$PWD/arm.'"$_n"'"
( trap "" TERM; sleep 110 & echo $! > "$PWD/gc.'"$_n"'"; wait ) &
wait'; done
  commit_fx; K5R=""
  ( cd "$d" && PREPUSH_CEILING_S=300 && export PREPUSH_CEILING_S && exec sh "$1" --base HEAD --warranted ) > "$WORK/k5p.out" 2>&1 &
  _lp=$!; _dl=$(( $(now_s) + 40 ))
  while { [ ! -s "$d/gc.alpha" ] || [ ! -s "$d/gc.beta" ]; } && [ "$(now_s)" -lt "$_dl" ]; do sleep 1; done
  if [ ! -s "$d/gc.alpha" ] || [ ! -s "$d/gc.beta" ]; then K5R="red: the arms never started"; hl_kill "$_lp" -KILL || :; return 0; fi
  _aa=$(cat "$d/arm.alpha"); _ab=$(cat "$d/arm.beta"); _ga=$(cat "$d/gc.alpha"); _gb=$(cat "$d/gc.beta")
  _pa=$(ps -o pgid= -p "$_aa" 2>/dev/null | tr -d ' '); _pb3=$(ps -o pgid= -p "$_ab" 2>/dev/null | tr -d ' ')
  sleep 1; kill -s TERM "$_lp" 2>/dev/null || :; _t0=$(now_s); _dl=$(( _t0 + 9 ))
  while :; do
    _na=0
    for _pp2 in "$_lp" "$_ga" "$_gb"; do _ps2=$(ps -o stat= -p "$_pp2" 2>/dev/null | tr -d ' '); case $_ps2 in ''|Z*) ;; *) _na=$((_na+1)) ;; esac; done
    _nm=$(ps -A -o pid= -o pgid= 2>/dev/null | awk -v a="$_pa" -v b="$_pb3" '($2 == a || $2 == b) { n++ } END { print n + 0 }')
    [ $((_na + _nm)) -gt 0 ] || break
    [ "$(now_s)" -lt "$_dl" ] || break
    sleep 1
  done
  _el=$(( $(now_s) - _t0 ))
  [ $((_na + _nm)) -eq 0 ] || K5R="$K5R alive($_na process(es), $_nm group member(s))"
  [ "$_el" -le 7 ] || K5R="$K5R took-${_el}s"   # the lane copies scale the kill grace to 4 s: one shared grace ends in about 5-6 s, a per-unit serial grace in about 9-10 s
  for _pp2 in "$_aa" "$_ab" "$_ga" "$_gb"; do hl_kill "$_pp2" -KILL || :; done
  _ls=$(ps -o stat= -p "$_lp" 2>/dev/null | tr -d ' '); _lrc=0
  case $_ls in ''|Z*) { wait "$_lp"; } 2>/dev/null || _lrc=$? ;; *) hl_kill "$_lp" -KILL || :; { wait "$_lp"; } 2>/dev/null || :; _lrc=killed ;; esac
  [ "$_lrc" = 143 ] || K5R="$K5R lane-rc=$_lrc"
  if [ -z "$K5R" ]; then K5R=ok; else K5R="red:$K5R"; fi
}
# PL8 - a ceiling kill under the pool; K5 under the pool
selftest_pool_ceiling() {
  _c2=$WORK/lane-j2-st2.sh; sed 's/^ST_CEIL=3600$/ST_CEIL=2/' "$LANE_J2" > "$_c2"
  sfx "PL8: the ST_CEIL=2 J=2 lane copy differs" differs "$(cmp -s "$LANE_J2" "$_c2" && echo same || echo differs)"
  _g3=$WORK/lane-j2-g3.sh; sed 's/^ARM_GRACE_S=5; ARM_CONFIRM_S=5;/ARM_GRACE_S=4; ARM_CONFIRM_S=4;/' "$LANE_J2" > "$_g3"
  sfx "PL8: the grace-4 J=2 lane copy differs" differs "$(cmp -s "$LANE_J2" "$_g3" && echo same || echo differs)"
  _pb='case $1 in
scripts/x.sh)
'"$K_BODY"'
;;
*) echo "TARGET: $1 (both faces)" ;;
esac'
  stfx "$_pb" scripts/x.sh scripts/y.sh
  plr "$WORK/pl8-h" "$_c2"
  want "PL8: the hung pooled target reads UNVERIFIED at the runaway ceiling, its kill confirmed gone" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling.*confirmed gone"
  want "PL8: the other target reads OK" "^  OK    core-selftest *scripts/y\.sh"
  sfx "PL8: the hung target's grandchildren are gone" 0 "$(k_alive "$d/k.pids")"; k_reap "$d/k.pids"
  TRSRC=$_c2 trmut pl8a -e '/# PLCTL$/s/.*/  _rtc=$WORK\/ctl   # PLCTL/'
  [ -z "$TRM" ] || { stfx "$_pb" scripts/x.sh scripts/y.sh; plr "$WORK/pl8-h2" "$TRM"; k_reap "$d/k.pids"
    wantnot "PL8 mutant: with the kill state shared in the work root's ctl the pooled kill is not read as a ceiling kill (the cell is RED)" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling"; }
  k5p_run "$_g3"; sfx "PL8 K5: a TERM to the lane pid alone ends it (rc 143) and kills both pooled groups and their TERM-ignoring grandchildren within one shared grace (7 s at a 4 s grace)" ok "$K5R"
  TRSRC=$_g3 trmut pl8b -e '/# PLTRAP$/s/.*/  :   # PLTRAP/' -e '/^      kill -0 "\$_lpid" 2>\/dev\/null || { arm_orphaned/d'
  [ -z "$TRM" ] || { k5p_run "$TRM"; sfx "PL8 K5 mutant: a trap that reads only the one legacy control dir leaves the pooled arms alive (the cell is RED)" yes "$(k5_has 'alive')"; }
  TRSRC=$_g3 trmut pl8c -e '/# PLKILL$/s/.*/  for _g in $_pk_all; do arm_kill "$_g" leader || :; done   # PLKILL/' -e '/^      kill -0 "\$_lpid" 2>\/dev\/null || { arm_orphaned/d'
  [ -z "$TRM" ] || { k5p_run "$TRM"; sfx "PL8 K5 mutant: a per-unit serial grace takes over 7 s at a 4 s grace (the cell is RED)" yes "$(k5_has 'took-')"; }
}
# PL9 - the verdict equals J = 1
selftest_pool_equal() {
  _pb='case $1 in
scripts/bad.sh) echo "TARGET: $1 (both faces)"; exit 1 ;;
scripts/crash.sh) kill -s SEGV $$ ;;
scripts/excl.sh) printf "  EXCLUDED: excl.sh — fixture\n" ;;
scripts/hang.sh) sleep 30 ;;
*) echo "TARGET: $1 (both faces)" ;;
esac'
  # PL9b shares this run (Architect, route b): the J = 1 lane here is a copy whose pool entry points log their names to $PWD/pool.calls, so the same run proves PL9's equality AND that J = 1 never enters pool code.
  _j1=$WORK/lane-j1-st2.sh; _j2=$WORK/lane-j2-st2.sh
  pl_wrap "$LANE_J1" "$_j1"; sed 's/^ST_CEIL=3600$/ST_CEIL=2/' "$LANE_J2" > "$_j2"
  sfx "PL9b: the call-logging J = 1 copy differs from the lane" differs "$(cmp -s "$LANE_J1" "$_j1" && echo same || echo differs)"
  stfx "$_pb" scripts/bad.sh scripts/crash.sh scripts/excl.sh scripts/hang.sh scripts/ok.sh
  rm -f "$d/pool.calls"; pl_eqrun "PL9 default run" "$_j1" "$_j2"; _pu1=$PL_EQU
  sfx "PL9b: at J = 1 no pool function was called (the call log is empty)" "" "$(cat "$d/pool.calls" 2>/dev/null || :)"
  sfx "PL9b: and the J = 1 output has exactly one # pool: line" 1 "$(printf '%s\n' "$PL_DVA" | grep -c '^# pool: ' || :)"
  # control: the same logging on the J = 2 lane DOES log, so an empty log is not an unwired probe; the mutant routes J = 1 through the pool
  pl_wrap "$LANE_J2" "$WORK/lane-j2-calls.sh"; rm -f "$d/pool.calls"; plr "$(rlh)" "$WORK/lane-j2-calls.sh"
  sfx "PL9b: control - at J = 2 the pool functions are logged" yes "$([ -s "$d/pool.calls" ] && echo yes || echo no)"
  TRSRC=$_j1 trmut pl9b -e '/# PLSITE$/s/-lt 2/-lt 1/' -e '/# PLUSE$/s/-ge 2/-ge 1/' -e '/# PLUSE2$/s/.*/  :   # PLUSE2/'
  [ -z "$TRM" ] || { rm -f "$d/pool.calls"; plr "$(rlh)" "$TRM"
    sfx "PL9b mutant: with J = 1 routed through the pool the call log is not empty (the cell is RED)" yes "$([ -s "$d/pool.calls" ] && echo yes || echo no)"; }
  TRSRC=$_j2 trmut pl9 -e '/# PLLAST$/s/-le "\$PQ_M"/-lt "$PQ_M"/'
  [ -z "$TRM" ] || { _hm=$(rlh); plr "$_hm" "$TRM"
    sfx "PL9 mutant: with the last queued unit dropped the units differ from J = 1 (the cell is RED)" differs "$([ "$(pl_units "$(pl_end "$_hm")")" = "$_pu1" ] && echo same || echo differs)"; }
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'; mkchk alpha 'exit 0'; mkchk beta 'exit 3'; commit_fx; _stb=$(git -C "$d" rev-parse HEAD)
  pl_eqrun "PL9 --warranted run" "$LANE_J1" "$LANE_J2" --warranted
}
# PL9b - J = 1 is IDENTICAL to today's lane, proved STRUCTURALLY, not textually (Architect, route b): at J = 1 the lane never enters pool code. pl_wrap makes a copy (ST_CEIL=2) of a lane whose pool entry points
# (pool_arm, pool_loop, pool_start, pool_reap, pool_tail_one) each append their name to $PWD/pool.calls; the legs run inside selftest_pool_equal, on PL9's own run.
pl_wrap() {
  sed -e 's/^ST_CEIL=3600$/ST_CEIL=2/' -e 's/^pool_arm() {/pool_arm() { echo pool_arm >> "$PWD\/pool.calls";/' -e 's/^pool_loop() {/pool_loop() { echo pool_loop >> "$PWD\/pool.calls";/' \
      -e 's/^pool_start() {/pool_start() { echo pool_start >> "$PWD\/pool.calls";/' -e 's/^pool_reap() {/pool_reap() { echo pool_reap >> "$PWD\/pool.calls";/' \
      -e 's/^pool_tail_one() {/pool_tail_one() { echo pool_tail_one >> "$PWD\/pool.calls";/' "$1" > "$2"
}

# PL10 - the log
selftest_pool_log() {
  [ -x /usr/bin/perl ] || { echo "SKIP: PL10: /usr/bin/perl is absent - the pooled rss_kb was NOT exercised"; return 0; }
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  mkchk alpha "/usr/bin/perl -e 'my \$x = q(a) x 67108864; sleep 2'"; mkchk beta 'sleep 2'; commit_fx
  _h=$(rlh); rnlh "$_h" "$LANE_J2" "$d" --warranted; _lg=$(rlf "$_h" "$d")/runs.log
  _s=$(grep '^v1 start ' "$_lg" | sed -n 1p); _e=$(grep '^v1 end ' "$_lg" | sed -n 1p)
  sfx "PL10: the start record carries the provisional J" 2 "$(rlk "$_s" j)"
  sfx "PL10: the end record carries the final J and the race count" "2|0" "$(rlk "$_e" jf)|$(rlk "$_e" race)"
  sfx "PL10: the start record matches the v1 grammar" 1 "$(rlc "$_lg" "$RLS_RE")"
  sfx "PL10: and the end record" 1 "$(rlc "$_lg" "$RLE_RE")"
  _kb=$(rlk "$_e" u | tr ',' '\n' | sed -n 's/^core-live:alpha:OK:[0-9]*:\([0-9-]*\)$/\1/p'); _kc=$(rlk "$_e" u | tr ',' '\n' | sed -n 's/^core-live:beta:OK:[0-9]*:\([0-9-]*\)$/\1/p')
  sfx "PL10: every pooled unit's rss_kb is a number, at least 40000 for the 64 MB holder" yes "$([ "${_kb:--}" != - ] && [ "${_kb:-0}" -ge 40000 ] && [ "${_kc:--}" != - ] && echo yes || echo no)"
  _hr=$PL_RH   # the race run of PL7 (a J = 2 run that really raced); its log is read here
  DVOUT=$( cd "$PL_RD" && HOME=$_hr sh "$LANE_J2" --log-report --base HEAD 2>&1 ) || :
  want "PL10: --log-report counts the run as ended" "^# runs: 1 started, 1 ended, 0 incomplete"
  want "PL10: --log-report reads jf and RACE" "^# pool runs .*jf >= 2 in 1 of 1 ended run.*RACE units 1"
  TRSRC=$LANE_J2 trmut pl10a -e '/# RLJ$/s/.*/  _rl_j=1   # RLJ/'
  [ -z "$TRM" ] || { _h2=$(rlh); rnlh "$_h2" "$TRM" "$d" --warranted
    sfx "PL10 mutant: with j=1 restored the start record does not carry the provisional J (the cell is RED)" differs "$([ "$(rlk "$(grep '^v1 start ' "$(rlf "$_h2" "$d")/runs.log" | sed -n 1p)" j)" = 2 ] && echo same || echo differs)"; }
  TRSRC=$LANE_J2 trmut pl10b -e 's/okf("j", "^.0-9.+\$")/okf("j", "^1\$")/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$PL_RD" && HOME=$_hr sh "$TRM" --log-report --base HEAD 2>&1 ) || :; wantnot "PL10 mutant: with the ^1$ regex restored a J = 2 start record is malformed (the cell is RED)" "^# runs: 1 started, 1 ended"; }
  TRSRC=$LANE_J2 trmut pl10c -e '/# RLOKEND$/s/.*/  e = (("trunc" in f) ? 14 : 13)   # RLOKEND/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$PL_RD" && HOME=$_hr sh "$TRM" --log-report --base HEAD 2>&1 ) || :; wantnot "PL10 mutant: with race= and jf= refused without trunc= the end record is malformed (the cell is RED)" "^# runs: 1 started, 1 ended"; }
}
# PL11 - fd 9
selftest_pool_fd() {
  _pl=$LANE; LANE=$LANE_J2; selftest_lock_child_fd; LANE=$_pl
  hlfx
  stfx 'if ( : >&9 ) 2>/dev/null; then echo open > "$PWD/fd9.$(basename "$1")"; else echo closed > "$PWD/fd9.$(basename "$1")"; fi; echo "TARGET: $1 (both faces)"' scripts/p.sh scripts/q.sh
  plr "$_lh" "$LANE_J2"
  want "PL11: the pool took the lock" "^# heavy-arm lock: acquired for the core-pool unit"
  sfx "PL11: both pooled units ran with descriptor 9 closed" "closed closed" "$(cat "$d/fd9.p.sh" "$d/fd9.q.sh" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
  TRSRC=$LANE_J2 trmut pl11 -e 's/) 9>&-/)/'
  [ -z "$TRM" ] || { rm -f "$d/fd9.p.sh" "$d/fd9.q.sh"; hlfx; plr "$_lh" "$TRM"
    sfx "PL11 mutant: with 9>&- removed a pooled unit holds the lock's descriptor (the cell is RED)" yes "$(grep -q open "$d/fd9.p.sh" 2>/dev/null && echo yes || echo no)"; }
}
# PL14, PL14b - a fast rc 124 under a late clock; the wd.fired conjunct at function level
selftest_pool_late() {
  _c5=$WORK/lane-j2-ceil5.sh; sed 's/ 120 PREPUSH_CEILING_S)/ 5 PREPUSH_CEILING_S)/' "$LANE_J2" > "$_c5"
  sfx "PL14: the CEIL=5 lane copy differs" differs "$(cmp -s "$LANE_J2" "$_c5" && echo same || echo differs)"
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'; mkchk alpha 'sleep 2'
  mkchk beta '_u=$(dirname "$TMPDIR"); : > "$_u/../ctl/${_u##*/}/wd.fired"; sleep 1; exit 124'; commit_fx
  rnl "$_c5" "$d" --warranted
  want "PL14: a fast rc 124 with a forged marker reads FAIL by its rc, not as a ceiling kill" "^  FAIL  core-live *beta .*rc=124 (expected 0)"
  wantnot "PL14: and never exceeded ceiling" "exceeded ceiling"
  TRSRC=$_c5 trmut pl14 -e '/# PLT1$/s/.*/pool_t1() { echo $(( $(date +%s) + 30 )); }   # PLT1/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --warranted; want "PL14 mutant: with a late clock the fast exit reads as a ceiling kill (the cell is RED)" "exceeded ceiling"; }
  # PL14c (R1-3): a unit's own seconds survive until its row is printed. `alpha` hangs and is killed at the 4 s ceiling (queued first); `zeta` exits at once but its row waits behind alpha. zeta's row must show its OWN
  # seconds, not alpha's (the lane copy's ceiling is 4 s); the mutant drops s:RUN_S from the saved variables, so zeta's row shows the last decided unit's seconds.
  _c4=$WORK/lane-j2-ceil4.sh; sed 's/ 120 PREPUSH_CEILING_S)/ 4 PREPUSH_CEILING_S)/' "$LANE_J2" > "$_c4"
  mkcin 'sh conformance/alpha.sh' 'sh conformance/zeta.sh'; mkchk alpha 'sleep 100 & wait'; mkchk zeta 'exit 0'; commit_fx
  pl_zs() { printf '%s\n' "$DVOUT" | sed -n 's/^  OK    core-live .*zeta .* \([0-9][0-9]*\)s$/\1/p' | sed -n 1p; }
  rnl "$_c4" "$d" --warranted
  sfx "PL14c: the quick unit's row shows its own seconds (2 or fewer), though it waited behind a 4 s kill" yes "$([ "$(pl_zs)" -le 2 ] 2>/dev/null && echo yes || echo "zeta=$(pl_zs)")"
  TRSRC=$_c4 trmut pl14c -e 's/ s:RUN_S / /'
  [ -z "$TRM" ] || { rnl "$TRM" "$d" --warranted; sfx "PL14c mutant: without s:RUN_S saved the waiting row shows another unit's seconds (the cell is RED)" yes "$([ "$(pl_zs)" -ge 4 ] 2>/dev/null && echo yes || echo no)"; }
  # PL14b: ri_decide and st_decide at function level, J = 2, no wd.fired
  _m=$WORK/lane-pl14b.sh; lane_mut "$_m" '' '' > /dev/null
  pl14fn() { sed -n -e '/^ri_wd() /p' -e '/^ri_decide() {/,/^}/p' -e '/^crash_sig_of() {/,/^}/p' -e '/^crash_line_in() {/,/^}/p' -e '/^crash_ev_run() {/,/^}/p' -e '/^st_decide() {/,/^}/p' "$1" > "$1.fn"; }
  pl14run() {   # <fn-file> <touch wd.fired: 0|1> -> "<ri kind>/<st kind>"
    _ec=$(mktemp -d "${TMPDIR:-/tmp}/fx-ec-XXXXXX"); : > "$_ec/out"; [ "$2" -eq 0 ] || : > "$_ec/wd.fired"
    # shellcheck source=/dev/null  # sources a lane copy's extracted decide functions (the path is built at run time)
    ( . "$1"; POOL_J=2; POOL_LATE=0; U_CTL=$_ec; U_OUT=$_ec/out; U_CRASH=$_ec/crash.hit; RUN_RC=124; RUN_S=10; _st_ms=1; _st_s=1; _st_kc=0; _st_bl=""
      ri_decide core-live "x " 0 5; _k1=$RI_KIND; st_decide scripts/x.sh 5 "scripts/x.sh (both faces)"; echo "$_k1/$ST_KIND" )
  }
  pl14fn "$_m"
  sfx "PL14b: at J = 2 with no wd.fired a rc 124 past the ceiling reads fail, and the target tail reads run (an rc FAIL), not the STCEIL UNV" "fail/run" "$(pl14run "$_m.fn" 0)"
  sfx "PL14b: control - with the marker present both read ceiling kills" "ceil/ceil" "$(pl14run "$_m.fn" 1)"
  trmut pl14b1 -e '/# PLWD$/s/.*/ri_wd() { :; }   # PLWD/'
  [ -z "$TRM" ] || { pl14fn "$TRM"; sfx "PL14b mutant: with the conjunct dropped from ri_decide it reads ceil (the cell is RED)" ceil "$(pl14run "$TRM.fn" 0 | cut -d/ -f1)"; }
  trmut pl14b2 -e '/# PSCEIL$/s| \&\& \[ -e "[^"]*wd\.fired" \]||'
  [ -z "$TRM" ] || { pl14fn "$TRM"; sfx "PL14b mutant: with the conjunct dropped from the target tail it reads ceil (the cell is RED)" ceil "$(pl14run "$TRM.fn" 0 | cut -d/ -f2)"; }
}
# PL15, PL16 - one record per unit; the first queued UNV reason wins
selftest_pool_records() {
  d=$PL_RD; _h=$PL_RH; _e=$(pl_end "$_h")   # PL7's race run (a FAIL in the pool, a pass serially)
  _rows=$(printf '%s\n' "$PL_RDV" | grep -Ec '^  (OK|FAIL|UNVERIFIED|SKIP|N/A) ' || :)
  sfx "PL15: after a FAIL, PASS sequence the rows, ran and the units are one each" "$_rows|$_rows" "$(rlk "$_e" ran)|$(rlk "$_e" u | tr ',' '\n' | grep -c . || :)"
  sfx "PL15: and no unit is numbered #2" 0 "$(rlk "$_e" u | grep -c '#2' || :)"
  TRSRC=$LANE_J2 trmut pl15a -e '/# PLDEFER$/s/_pd_s=defer/_pd_s=rec/'
  [ -z "$TRM" ] || { pl_racerm; rnl "$TRM" "$d" --warranted; want "PL15 mutant: with the pool FAIL recorded early no race is found (the cell is RED)" "^  FAIL  core-live *beta"; }
  _c2=$WORK/lane-j2-st2.sh; sed 's/^ST_CEIL=3600$/ST_CEIL=2/' "$LANE_J2" > "$_c2"
  _pb='case $1 in
scripts/x.sh) m=$PWD/once.x; if [ ! -e "$m" ]; then : > "$m"; echo "TARGET: $1 (both faces)"; exit 1; fi; sleep 100 & wait ;;
*) echo "TARGET: $1 (both faces)" ;;
esac'
  stfx "$_pb" scripts/p.sh scripts/x.sh; _h=$(rlh); plr "$_h" "$_c2"
  want "PL15: a pool FAIL then a serial hang stays UNVERIFIED" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling"
  wantnot "PL15: and is never a RACE" "RACE"
  sfx "PL15: one UNV unit in the log" 1 "$(rlk "$(pl_end "$_h")" u | tr ',' '\n' | grep -c '^core-selftest:scripts/x\.sh:UNV:' || :)"
  TRSRC=$_c2 trmut pl15b -e '/# PLRACE$/s/.*/  _pt_pass=1   # PLRACE/'
  [ -z "$TRM" ] || { stfx "$_pb" scripts/p.sh scripts/x.sh; plr "$(rlh)" "$TRM"; want "PL15 mutant: a serial UNV mapped to a pass claims a RACE (the cell is RED)" "RACE"; }
  # PL16: x (queued first) ignores TERM and dies last; y (queued second) is reaped first; the verdict names x
  _pb='case $1 in
scripts/x.sh) trap "" TERM; sleep 100 & wait ;;
*) sleep 100 & wait ;;
esac'
  _c2g=$WORK/lane-j2-st2g.sh; sed 's/^ARM_GRACE_S=5; ARM_CONFIRM_S=5;/ARM_GRACE_S=2; ARM_CONFIRM_S=2;/' "$_c2" > "$_c2g"   # x (TERM ignored) then dies at about 4.5 s, y at about 2.3 s
  stfx "$_pb" scripts/x.sh scripts/y.sh; plr "$(rlh)" "$_c2g"
  sfx "PL16: the first-queued unit's UNV reason wins" "PARITY-CORE: UNVERIFIED (core-selftest scripts/x.sh: killed at the 2 s runaway ceiling)" "$(lastline)"
  TRSRC=$_c2g trmut pl16 -e '/# PLSTATE$/s/   # PLSTATE$/; [ "$ST_KIND" != ceil ] || unv "core-selftest $_pd_t: killed at reap"   # PLSTATE/'
  [ -z "$TRM" ] || { stfx "$_pb" scripts/x.sh scripts/y.sh; plr "$(rlh)" "$TRM"; wantnot "PL16 mutant: with unv called at reap the first-reaped reason leads (the cell is RED)" "UNVERIFIED (core-selftest scripts/x.sh: killed at the 2 s"; }
}
# PL17 - the @pool-k lifecycle
_pkb='case $1 in
scripts/x.sh) printf "%s\n" "$(basename "$(dirname "$TMPDIR")")" >> "$PWD/where.x"
  if [ ! -e "$PWD/once.x" ]; then : > "$PWD/once.x"; sleep 100 & wait; fi
  printf "  PASS: face (a) x (3 s) battery: ok\n  PASS: face (b) x (4 s) battery: ok\n"; echo "TARGET: $1 (both faces)" ;;
*) echo "TARGET: $1 (both faces)" ;;
esac'
pl17_seq() {   # <lane> <runs> <home>: runs 1-3 on the same bytes (run 1 kills x once), run 4 edits x and kills it again, run 5 edits it and runs clean
  stfx "$_pkb" scripts/p.sh scripts/q.sh scripts/x.sh
  _bx1=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _bx2=""; _bx3=""
  : > "$WORK/trtab.rows"; printf '@pool-k\tscripts/y.sh\t%040d\t0\tlocal\t%s\n' 7 "$(date +%s)" >> "$WORK/trtab.rows"
  # PL17_SEEDX=1: x already holds a live @pool-k row for these bytes (and its kill-once marker is set), so ONE run reaches the tail path a mutant must break
  [ "${PL17_SEEDX-}" != 1 ] || { printf '@pool-k\tscripts/x.sh\t%s\t0\tlocal\t%s\n' "$_bx1" "$(date +%s)" >> "$WORK/trtab.rows"; : > "$d/once.x"; }
  trtab "$3"
  _prn=0
  while [ "$_prn" -lt "$2" ]; do
    _prn=$((_prn+1))
    # the schedule PL17_S has one op per run: r = run again, e = edit x and re-arm its kill (it is killed again), c = edit x (it then runs clean)
    case $(printf '%s' "$PL17_S" | cut -c"$_prn") in
      e) rm -f "$d/once.x"; printf '# edit %s\n' "$_prn" >> "$d/scripts/x.sh"; commit_fx; _bx2=$(git -C "$d" rev-parse HEAD:scripts/x.sh) ;;
      c) printf '# edit %s\n' "$_prn" >> "$d/scripts/x.sh"; commit_fx; _bx3=$(git -C "$d" rev-parse HEAD:scripts/x.sh) ;;
    esac
    plr "$3" "$1"
    _plw=$(tail -n 1 "$d/where.x" | cut -c1); PL_WHERE="$PL_WHERE$_plw"
    [ -z "${PL17_HOOK-}" ] || "$PL17_HOOK" "$_prn" "$3"
  done
}
# the checks after each run of the main PL17 sequence (r r r e c): one sequence of five runs asserts runs 1, 2, 4 and 5
pl17_hook() {
  case $1 in
    1) want "PL17 run 1: the pooled kill reads UNVERIFIED at the runaway ceiling" "^  UNVERIFIED  core-selftest *scripts/x\.sh: killed at the 2 s runaway ceiling"
       sfx "PL17 run 1: exactly one @pool-k row for x, with its blob" "scripts/x.sh $_bx1" "$(pl_pkrows "$2" | grep '^scripts/x\.sh ')"
       sfx "PL17 run 1: and no @selftest-k floor" 0 "$(awk -F'\t' '$1 == "@selftest-k"' "$(pl_times "$2")" | grep -c . || :)"
       sfx "PL17 run 1: y's row (a unit this run does not touch) was kept" 1 "$(pl_pkrows "$2" | grep -c '^scripts/y\.sh ' || :)" ;;
    2) sfx "PL17 run 2: x runs in the serial tail (run 1 in the pool, run 2 in the tail), passes, writes today's @selftest row and keeps its @pool-k row" "ut|1|1" "$PL_WHERE|$(pl_pkrows "$2" | grep -c "^scripts/x\.sh $_bx1\$" || :)|$(awk -F'\t' -v b="$_bx1" '$1 == "@selftest" && $2 == b' "$(pl_times "$2")" | grep -c . || :)" ;;
    4) sfx "PL17 run 4: after an edit x is killed in the pool again and the table holds exactly one row for it, with the new blob" "1|scripts/x.sh $_bx2" "$(pl_pkrows "$2" | grep -c '^scripts/x\.sh ' || :)|$(pl_pkrows "$2" | grep '^scripts/x\.sh ')" ;;
    5) sfx "PL17 run 5: x's row is retired and y's row is untouched (no sweep)" "0|1" "$(pl_pkrows "$2" | grep -c '^scripts/x\.sh ' || :)|$(pl_pkrows "$2" | grep -c '^scripts/y\.sh ' || :)" ;;
  esac
}
selftest_pool_pk() {
  _c2=$WORK/lane-j2-pk.sh; sed 's/^ST_CEIL=3600$/ST_CEIL=2/' "$LANE_J2" > "$_c2"
  # one sequence of five runs (r r r e c) with the checks after runs 1, 2, 4 and 5 (pl17_hook); the mutants below run only as many runs as they need
  _h=$WORK/pl17-h; PL_WHERE=""; PL17_S=rrrec; PL17_HOOK=pl17_hook; pl17_seq "$_c2" 5 "$_h"; PL17_HOOK=""
  sfx "PL17: x ran in the pool, then the tail twice, then the pool twice" "uttuu" "$PL_WHERE"
  TRSRC=$_c2 trmut pl17a -e '/# PSREC$/s/ || \[ "\$POOL_IN" -eq 1 \]//'
  [ -z "$TRM" ] || { _h=$WORK/pl17-ma; PL17_S=r; pl17_seq "$TRM" 1 "$_h"
    sfx "PL17 mutant: with STREC active at J >= 2 a pooled kill leaves a @selftest-k floor (the cell is RED)" yes "$([ "$(awk -F'\t' '$1 == "@selftest-k"' "$(pl_times "$_h")" | grep -c . || :)" -ge 1 ] && echo yes || echo no)"; }
  TRSRC=$_c2 trmut pl17b -e '/# PLTAILREC$/s/   # PLTAILREC$/; tr_rewrite @pool-k "$_pt_key" -   # PLTAILREC/'
  # control for the two seeded mutants below (pl17b, pl17e): on the CORRECT lane the seeded x is held, runs in the tail and keeps its row, so a seed that failed to take cannot pass them vacuously
  _h=$WORK/pl17-mc0; PL_WHERE=""; PL17_S=r; PL17_SEEDX=1; pl17_seq "$_c2" 1 "$_h"; PL17_SEEDX=0
  sfx "PL17 control: the seeded x runs in the tail and keeps its one row (the seed took)" "t|1" "$PL_WHERE|$(pl_pkrows "$_h" | grep -c '^scripts/x\.sh ' || :)"
  # x is seeded with a live row, so one run holds it for the tail (where it passes clean); the row must survive that clean tail run (the correct lane: 1 row, the mutant: 0)
  [ -z "$TRM" ] || { _h=$WORK/pl17-mb; PL_WHERE=""; PL17_S=r; PL17_SEEDX=1; pl17_seq "$TRM" 1 "$_h"; PL17_SEEDX=0
    sfx "PL17 mutant: with @pool-k cleared on a clean tail run the row is gone after it (the cell is RED)" 0 "$(pl_pkrows "$_h" | grep -c '^scripts/x\.sh ' || :)"; }
  _ov='tr_rewrite() { [ -n "$TR_TIMES" ] || return 0; [ "$3" = - ] || tr_record "$1" "$2" "$3"; return 0; }'
  _m=$WORK/lane-pl17c.sh; LM_SRC=$_c2 lane_mut "$_m" '' "$_ov" > /dev/null
  _h=$WORK/pl17-mc; PL_WHERE=""; PL17_S=re; pl17_seq "$_m" 2 "$_h"   # kill, edit, kill again: two rows for x if tr_rewrite appends
  sfx "PL17 mutant: with tr_rewrite an append run 2 holds two rows for x (the cell is RED)" 2 "$(pl_pkrows "$_h" | grep -c '^scripts/x\.sh ' || :)"
  _ov='tr_rewrite() { [ -n "$TR_TIMES" ] || return 0; _t=$(mktemp "$TR_TIMES.XXXXXX") || return 0; awk -F"\t" "\$1 != \"@pool-k\"" "$TR_TIMES" > "$_t"; [ "$3" = - ] || printf "%s\t%s\t%s\t0\tlocal\t%s\n" "$1" "$2" "$3" "$(date +%s)" >> "$_t"; mv -f "$_t" "$TR_TIMES"; }'
  LM_SRC=$_c2 lane_mut "$_m" '' "$_ov" > /dev/null
  _h=$WORK/pl17-md; PL_WHERE=""; PL17_S=r; pl17_seq "$_m" 1 "$_h"   # the first pool kill already sweeps y's row
  sfx "PL17 mutant: with a sweep of untouched rows y's row is gone after the first rewrite (the cell is RED)" 0 "$(pl_pkrows "$_h" | grep -c '^scripts/y\.sh ' || :)"
  TRSRC=$_c2 trmut pl17e -e '/# PLPKLOOK$/s/.*/    tr_look @pool-k "$_pu_key"; _pu_pk=$L_SEC   # PLPKLOOK/'
  [ -z "$TRM" ] || { _h=$WORK/pl17-me; PL_WHERE=""; PL17_S=r; PL17_SEEDX=1; pl17_seq "$TRM" 1 "$_h"; PL17_SEEDX=0
    sfx "PL17 mutant: reading the row through tr_look (it drops a non-number) holds nothing, so the seeded x runs in the pool (the cell is RED)" u "$PL_WHERE"; }
  # the core-live variant: @pool-k <basename+argv> <script blob>
  _c1=$WORK/lane-j2-cl2.sh; sed 's/ 120 PREPUSH_CEILING_S)/ 2 PREPUSH_CEILING_S)/' "$LANE_J2" > "$_c1"
  pl17cl() {   # <lane> <home> <runs>
    mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh' 'sh conformance/gamma.sh'
    mkchk alpha 'basename "$(dirname "$TMPDIR")" >> "$PWD/where.alpha"; if [ ! -e "$PWD/once.alpha" ]; then : > "$PWD/once.alpha"; sleep 100 & wait; fi'
    mkchk beta 'exit 0'; mkchk gamma 'exit 0'; commit_fx; _stb=$(git -C "$d" rev-parse HEAD)
    _ca1=$(git -C "$d" rev-parse HEAD:conformance/alpha.sh); _cn=0; PL_WHERE=""
    # seed mode: alpha holds a row whose blob is forty zeros (no real script has it), its kill-once marker set; one run then shows whether an edit-proof blob keeps it held
    [ "${4-}" != seed ] || { printf '@pool-k\talpha\t%040d\t0\tlocal\t%s\n' 0 "$(date +%s)" > "$WORK/trtab.rows"; trtab "$2"; : > "$d/once.alpha"; }
    while [ "$_cn" -lt "$3" ]; do
      _cn=$((_cn+1))
      [ "$_cn" -ne 3 ] || { printf '# edit\n' >> "$d/conformance/alpha.sh"; commit_fx; }
      plr "$2" "$1" --warranted; PL_WHERE="$PL_WHERE$(tail -n 1 "$d/where.alpha" | cut -c1)"
    done
  }
  _h=$WORK/pl17-cl; pl17cl "$_c1" "$_h" 3
  sfx "PL17 core-live: killed in the pool, then held in the tail while the script is unchanged, then in the pool after an edit" "utu" "$PL_WHERE"
  sfx "PL17 core-live: the edit retired the row" 0 "$(pl_pkrows "$_h" | grep -c '^alpha ' || :)"
  TRSRC=$_c1 trmut pl17f -e '/# PLCLBLOB$/s/.*/  _pu_bl=0000000000000000000000000000000000000000   # PLCLBLOB/'
  [ -z "$TRM" ] || { _h=$WORK/pl17-clm; pl17cl "$TRM" "$_h" 1 seed
    sfx "PL17 core-live mutant: a row without the script blob (the seeded zeros match it) keeps alpha held, so the row is not retired (the cell is RED)" 1 "$(pl_pkrows "$_h" | grep -c '^alpha ' || :)"; }
}
# PL18 - a forged TARGET after the reap
selftest_pool_forge() {
  # x is an OK unit decided at its reap and recorded straight from the pool (no tail); z waits for x's `reaped` marker (20 s bound, else exit 2: the cell then FAILs as vacuous) and appends a crash line (built with printf from parts) to x's u1/out
  _fb='case $1 in
scripts/x.sh) echo "TARGET: $1 (both faces)" ;;
scripts/a.sh)
  _i=0; while [ ! -e "$TMPDIR/../../ctl/u2/reaped" ] && [ "$_i" -lt 200 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i+1)); done
  [ -e "$TMPDIR/../../ctl/u2/reaped" ] || exit 2
  printf "%s %s\n" Segmentation "fault: 11" >> "$TMPDIR/../../u2/out"
  echo "TARGET: $1 (both faces)" ;;
esac'
  # the forger a.sh is queued FIRST (u1, label order) and the victim x.sh second (u2): x's record waits in pool_flush behind the still-running forger, so the forgery always lands before x is recorded
  stfx "$_fb" scripts/x.sh scripts/a.sh; plr "$(rlh)" "$LANE_J2"
  want "PL18: the crash line forged into x's output after the reap does not change its OK (it was decided at the reap)" "^  OK    core-selftest *scripts/x\.sh"
  wantnot "PL18: and x is not read as crashed" "scripts/x\.sh.*crashed"
  want "PL18: the forger ran to the end (the cell is not vacuous)" "^  OK    core-selftest *scripts/a\.sh"
  TRSRC=$LANE_J2 trmut pl18 -e '/# PLREC$/s/pool_st_prior; st_apply/st_decide "$_st_p" "$_st_cl" "$_st_p"; pool_st_prior; st_apply/'
  [ -z "$TRM" ] || { stfx "$_fb" scripts/x.sh scripts/a.sh; plr "$(rlh)" "$TRM"; want "PL18 mutant: re-deciding at the record reads the forged line, so x reads UNVERIFIED (crashed) (the cell is RED)" "^  UNVERIFIED  core-selftest *scripts/x\.sh.*crashed"; }
}
# PL19 - the half-ceiling rule
selftest_pool_half() {
  _c10=$WORK/lane-j2-st3.sh; sed 's/^ST_CEIL=3600$/ST_CEIL=3/' "$LANE_J2" > "$_c10"   # a 3 s ceiling: 1 s is under half of it, 2 s is not
  _pb='case $1 in
scripts/x.sh) if [ ! -e "$PWD/once.x" ]; then : > "$PWD/once.x"; sleep 100 & wait; fi; echo "TARGET: $1 (both faces)" ;;
*) echo "TARGET: $1 (both faces)" ;;
esac'
  stfx "$_pb" scripts/p.sh scripts/x.sh; _bx=$(git -C "$d" rev-parse HEAD:scripts/x.sh); _h=$WORK/pl19-h; stt "$_h" "$_bx=1"; plr "$_h" "$_c10"
  want "PL19 (i): a unit measured at 1 s of 10 killed in the pool re-runs serially and reads its serial verdict" "^  OK    core-selftest *scripts/x\.sh"
  sfx "PL19 (i): a half-test re-run that passes writes no @pool-k" 0 "$(pl_pkrows "$_h" | grep -c . || :)"
  TRSRC=$_c10 trmut pl19a -e '/# PLHALF$/s/\&\& _pd_s=defer/\&\& _pd_s=rec/'
  [ -z "$TRM" ] || { stfx "$_pb" scripts/p.sh scripts/x.sh; stt "$_h" "$_bx=1"; plr "$_h" "$TRM"; wantnot "PL19 (i) mutant: with no re-run the kill stays UNV (the cell is RED)" "^  OK    core-selftest *scripts/x\.sh"; }
  _pb='printf "argv=[%s]\n" "$1" >> "$PWD/herm.out"; sleep 100 & wait'
  stfx "$_pb" scripts/x.sh scripts/y.sh; _by=$(git -C "$d" rev-parse HEAD:scripts/y.sh); stt "$_h" "$_by=2"; plr "$_h" "$_c10"
  sfx "PL19 (ii): an unmeasured unit and one measured at 2 s of 3 are each called once and read UNV" "argv=[scripts/x.sh] argv=[scripts/y.sh]|2" "$(hm | sed 's/argv=\[scripts\/y.sh\] argv=\[scripts\/x.sh\]/argv=[scripts\/x.sh] argv=[scripts\/y.sh]/')|$(printf '%s\n' "$DVOUT" | grep -c '^  UNVERIFIED  core-selftest .*killed at the 3 s' || :)"
  TRSRC=$_c10 trmut pl19b -e '/# PLHALF$/s/pool_half "\$_pd_h" "\$_pd_c"/true/'
  [ -z "$TRM" ] || { stfx "$_pb" scripts/x.sh scripts/y.sh; stt "$_h" "$_by=2"; plr "$_h" "$TRM"
    sfx "PL19 (ii) mutant: with the half test dropped each is called twice (the cell is RED)" 4 "$(grep -c '^argv=' "$d/herm.out" 2>/dev/null || :)"; }
}
# PL20 - no perl: J = 1 with a note
selftest_pool_noperl() {
  _np=$WORK/lane-j2-noperl.sh; sed 's|^ARM_PERL=.*$|ARM_PERL=/nonexistent/perl|' "$LANE_J2" > "$_np"
  one_step; mkchk alpha 'exit 0'; commit_fx; rnl "$_np" "$d"
  want "PL20: with no perl J is 1 and the note says why" "^# pool: J=1 (no /nonexistent/perl"
  TRSRC=$_np trmut pl20 -e '/# PLPERL$/s/if ! arm_perl_ok; then/if false; then/'
  [ -z "$TRM" ] || { rnl "$TRM" "$d"; wantnot "PL20 mutant: with the perl test removed J is not 1 (the cell is RED)" "^# pool: J=1 "; }
}
# PL21 - reap latency, dash and bash
selftest_pool_reap() {
  # the lane copy scales the ceiling to 5 s and the poll bound's constant to 6 s (bound = 5 + 0 + 6 = 11 s, not 35 s), so the mutant waits about 10 s instead of 35
  _c5=$WORK/lane-j2-ceil5b.sh; sed -e 's/ 120 PREPUSH_CEILING_S)/ 5 PREPUSH_CEILING_S)/' -e 's|_ps_cl / 10 + 30|_ps_cl / 10 + 6|' "$LANE_J2" > "$_c5"
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  mkchk alpha 'sleep 1; date +%s > "$PWD/end.alpha"'; mkchk beta 'sleep 1; date +%s > "$PWD/end.beta"'; commit_fx
  pl_lag() {   # <shell> <lane> -> seconds from the last unit's own end to the lane's end
    rm -f "$d/end.alpha" "$d/end.beta"; ( cd "$d" && "$1" "$2" --base HEAD --warranted ) > /dev/null 2>&1 || :
    _pe=$(cat "$d/end.alpha" "$d/end.beta" 2>/dev/null | sort -n | tail -n 1); echo $(( $(now_s) - ${_pe:-0} ))
  }
  for _sh in dash bash; do
    command -v "$_sh" > /dev/null 2>&1 || { echo "FAIL: PL21: no $_sh here, so the real-reap leg is not graded under $_sh"; SF=1; continue; }
    sfx "PL21: under $_sh a 1 s pooled unit is reaped well inside 7 s of its end (the scaled poll bound is 11 s)" yes "$([ "$(pl_lag "$_sh" "$_c5")" -le 7 ] && echo yes || echo no)"
  done
  # FUNCTION LEVEL (the PL14b idiom): pool_done's liveness test is lifted out of a lane copy and run in a subshell of each shell, with `kill` overridden to succeed (a zombie that kill -0 still sees) and `ps` overridden to print Z.
  # The overrides exist only inside this cell's own `-c` script; the shipped function is untouched. Platform-independent: no real zombie is needed, so the Z arm is graded wherever dash or bash is installed.
  pl21fn() { [ -n "$1" ] || return 0; sed -n -e '/^pv_set() /p' -e '/^pv_get() /p' -e '/^pool_done() {/,/^}/p' "$1" > "$1.fn21" 2>/dev/null || :; }
  pl21run() {   # <shell> <fn-file> -> done | alive
    "$1" -c '. "$1"; PV_pid_1=4242; PV_t0_1=100; PV_bound_1=1000; kill() { return 0; }; ps() { echo Z; }; command -v pool_done >/dev/null || { echo error; exit 0; }; if pool_done 1 101; then echo done; else echo alive; fi' x "$2" 2>/dev/null || echo error
  }
  trmut pl21z -e '/# PLZ$/s/Z\*)/ZZZ_NEVER)/'
  pl21fn "$TRM"   # an empty TRM (trmut already printed its FAIL) leaves an unreadable file, which the checks below FAIL on
  _m21=$WORK/lane-pl21.sh; lane_mut "$_m21" '' '' > /dev/null; pl21fn "$_m21"
  sfx "PL21: the lifted function file holds pool_done" 1 "$(grep -c '^pool_done() {' "$_m21.fn21" 2>/dev/null || :)"
  sfx "PL21 mutant: the lifted mutant file holds pool_done with the Z arm renamed" 1 "$(grep -c 'ZZZ_NEVER) return 0' "$TRM.fn21" 2>/dev/null || :)"
  for _sh in dash bash; do
    command -v "$_sh" > /dev/null 2>&1 || { echo "FAIL: PL21: no $_sh here, so the Z arm is not graded under $_sh"; SF=1; continue; }
    sfx "PL21: under $_sh the exited-but-unreaped unit (kill -0 succeeds, ps says Z) reads DONE" 'done' "$(pl21run "$_sh" "$_m21.fn21")"
    sfx "PL21 mutant under $_sh: KILLED - without the Z arm the same unit reads ALIVE, so the cell is RED" 'alive' "$(pl21run "$_sh" "$TRM.fn21")"
  done
}
# PLR - the touched readers stay exactly as at J = 1
selftest_pool_readers() {
  # two touched selftest targets (scripts/p.sh, q.sh) make PQ_U = 2, so the J = 2 run really takes the pool (two # pool: lines, the second after the lock) before the readers run
  mkcin 'sh conformance/ra.sh' 'sh conformance/rb.sh' 'sh conformance/rc.sh'; mkchk ra 'exit 0'; mkchk rb 'exit 0'; mkchk rc 'exit 0'; mkchk selftest-hermetic "$STREC"; commit_fx; _stb=$(git -C "$d" rev-parse HEAD)
  mkdir -p "$d/scripts"; for _sp in p q; do printf '#!/bin/sh\n# %s\ncase ${1-} in --selftest) exit 0 ;; esac\n' "$_sp" > "$d/scripts/$_sp.sh"; done; commit_fx
  _now=$(date +%s); printf 'ra\t\t2\t0\tlocal\t%s\nrb\t\t3\t0\tlocal\t%s\nrc\t\t400\t0\tlocal\t%s\n' "$_now" "$_now" "$_now" > "$WORK/trtab.rows"
  pl_rdr() { printf '%s\n' "$DVOUT" | grep -E '^(  (OK|FAIL|UNVERIFIED) +touched-readers|CI-GRADED|CI-ONLY|# touched-readers)' | sed -e 's/  *[0-9][0-9]*s  / Ns  /' -e 's/[0-9][0-9]* s/N s/g'; }
  pl_rd() { _hh2=$WORK/plr-$2; trtab "$_hh2"; DVOUT=$( cd "$d" && HOME=$_hh2 PREPUSH_NO_CACHE=0 sh "$1" --base "$_stb" 2>&1 ) || :; PL_R=$(pl_rdr); }   # sets PL_R (the reader lines) and leaves the whole output in DVOUT
  pl_rd "$LANE_J1" j1; _r1=$PL_R; pl_rd "$LANE_J2" j2; _r2=$PL_R
  sfx "PLR: the J = 2 run really took the pool (two # pool: lines, the second after the lock)" 2 "$(printf '%s\n' "$DVOUT" | grep -c '^# pool: J=2 ' || :)"
  want "PLR: and the lock was taken for the pool" "^# heavy-arm lock: acquired for the core-pool unit"
  sfx "PLR: the reader rows, their order and the CI-GRADED lines equal J = 1's" "$_r1" "$_r2"
  sfx "PLR: and the leg is not vacuous (two OK reader rows, ra and rb, and the CI-GRADED line for rc)" 3 "$(printf '%s\n' "$_r2" | grep -c -e '^  OK    touched-readers' -e '^CI-GRADED: rc' || :)"
  TRSRC=$LANE_J2 trmut plr -e 's/^  tr_exec$/  tr_exec; tr_exec/'
  [ -z "$TRM" ] || sfx "PLR mutant: a reader run twice reads differently (the cell is RED; the plan's reader-in-the-pool mutant needs SWAS-872's code)" differs "$(pl_rd "$TRM" jm; [ "$PL_R" = "$_r1" ] && echo same || echo differs)"
}
# RL13 - @pool-k units: N
selftest_pool_report() {
  one_step; mkchk alpha 'exit 0'; commit_fx; _h=$(rlh); _sd=$(rlf "$_h" "$d"); ( umask 077; mkdir -p "$_sd" )
  pl_rep() { DVOUT=$( cd "$d" && HOME=$_h sh "$LANE_J2" --log-report --base HEAD 2>&1 ) || :; }
  printf '@pool-k\tscripts/x.sh\t%040d\t0\tlocal\t1\n@pool-k\tscripts/y.sh\t%040d\t0\tlocal\t1\n@pool\t%040d\t5\t0\tlocal\t1\n' 1 2 3 > "$_sd/times.tsv"
  pl_rep; want "RL13: two @pool-k rows and one @pool row print 2" "^# @pool-k units: 2\$"
  printf '@pool\t%040d\t5\t0\tlocal\t1\n' 3 > "$_sd/times.tsv"; pl_rep; want "RL13: a table with none prints 0" "^# @pool-k units: 0\$"
  rm -f "$_sd/times.tsv"; pl_rep; want "RL13: no table prints unavailable, never 0" "^# @pool-k units: unavailable: "
  wantnot "RL13: and never a 0" "^# @pool-k units: 0"
  printf '@pool-k\tscripts/x.sh\t%040d\t0\tlocal\t1\n@pool-k\tscripts/z.sh\tNOT-A-BLOB\t0\tlocal\t1\n' 1 > "$_sd/times.tsv"; pl_rep
  want "RL13: a malformed @pool-k row in times.tsv is skipped by the count" "^# @pool-k units: 1\$"
  stfx "$STREC" scripts/x.sh; _hn=$(rlh); plr "$_hn" "$LANE_J2"; _cl=$(lastline); _cr=$DVRC
  _sd2=$(rlf "$_h" "$d"); ( umask 077; mkdir -p "$_sd2" ); printf '@pool-k\tscripts/x.sh\tNOT-A-BLOB\t0\tlocal\t1\n' > "$_sd2/times.tsv"; plr "$_h" "$LANE_J2"
  sfx "RL13: a malformed @pool-k row in times.tsv changes no run verdict" "$_cl|$_cr" "$(lastline)|$DVRC"
  printf '@pool-k\tscripts/x.sh\t%040d\t0\tlocal\t1\n' 1 > "$_sd/times.tsv"
  TRSRC=$LANE_J2 trmut rl13a -e '/# RLPK$/d'
  [ -z "$TRM" ] || { DVOUT=$( cd "$d" && HOME=$_h sh "$TRM" --log-report --base HEAD 2>&1 ) || :; wantnot "RL13 mutant: with the line dropped nothing is printed (the cell is RED)" "@pool-k units"; }
  TRSRC=$LANE_J2 trmut rl13b -e '/# RLPKN$/s/.*/  _lp_n=0   # RLPKN/'
  [ -z "$TRM" ] || { DVOUT=$( cd "$d" && HOME=$_h sh "$TRM" --log-report --base HEAD 2>&1 ) || :; wantnot "RL13 mutant: with N always 0 a table holding a row prints 0 (the cell is RED)" "^# @pool-k units: 1\$"; }
}

main "$@"
