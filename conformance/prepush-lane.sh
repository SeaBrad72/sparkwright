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
# THE DEFAULT RUN (no --warranted; PREPUSH-CORE-DEFAULT) proves the change's OWN surface, in this order:
#   the scoped lint of the listing's shell files (shellcheck.sh --listed; the full lock stays in CI) ->
#   the touched selftests (selftest-hermetic --touched) -> the board gates (when BACKLOG.md is touched) ->
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
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK" 2>/dev/null; return 0; }   # best-effort: a trap that
trap 'cleanup' EXIT                                                    # FAILS would override exit 0
# INT/TERM must EXIT (security L4): a handler that merely returns 0 resumes the script with its work
# root already deleted. 130/143 are the conventional signal rcs; EXIT then re-cleans harmlessly.
trap 'cleanup; exit 130' INT; trap 'cleanup; exit 143' TERM

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
        split("listing branch base-board head",PH," ") }
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
  if (NF != 7) e="expected 7 tab-separated fields, got " NF
  else if (b !~ /^[a-z0-9-]+$/) e="basename outside [a-z0-9-]+: " b
  else if (!(("conformance/" b ".sh") in SCR)) e="not a regular file under the repo root: conformance/" b ".sh"
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
  if (e != "") print FNR ": " e > ERR; else print $0 > OK
}
'
read_twins() {
  : > "$WORK/twins.ok"; : > "$WORK/twins.err"
  [ -f "$TWINS_REL" ] || return 0
  LC_ALL=C awk -v OK="$WORK/twins.ok" -v ERR="$WORK/twins.err" "$SENSFN$TWPROG" \
    "$WORK/scripts" "$TWINS_REL"
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
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
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
# touched set and the merged label never appears in a run report: `core-selftest` (one call to
# selftest-hermetic.sh --touched — both faces, never re-implemented) and `untouched-selftest` (listed,
# not run). The ONLY `&`s in this file are BOTH inside run_timed, and only on the no-timeout(1) path: its
# watchdog, AND the guarded invocation itself (`"$@" & … wait "$_pid"`), backgrounded so the watchdog can
# reach it. That `wait` keeps execution strictly serial; selftest_no_fanout proves it by OBSERVATION.
#
# `conformance/ci-classify-changes.sh` (docs_classify, reco) is the LANE'S OWN helper, not a derived
# invocation (reviewer M-4): the lane calls it directly, so it runs OUTSIDE the scrub, the dash shim and
# the ceiling, by design — it is CI's own classifier (D-240903-3), asked the same question CI asks, and
# it must be answered BEFORE any bucket or work root exists to run it in.
RUN_HB=""; RUN_RC=0; RUN_S=0; VERBOSE=0; BEST=0; HEAVY=""; HEAVY_ARG=""; WARRANTED=0; BASE="origin/main"
BASE_SHA=""; DOCS_ONLY=false; DASH=""; SHIMDIR=""; TIMEOUT_BIN=""; CEIL=120; FLOOR=6144; FREE=""
ARGVLOG=""; UNV=""; FAILS=0; RAN=0; HCEIL=3600; SELFCEIL=3600
# SELFCEIL (reviewer I-1): the core-selftest face is ONE call to selftest-hermetic.sh --touched running
# BOTH hermeticity faces over the whole touched set, so it is not bounded by the 120 s per-check core
# ceiling; "add a heavy row" is the wrong remedy (it is the core, not a heavy invocation), so its overrun
# names PREPUSH_CEILING_S instead. It is the HEAVY default (3600 s) because its cost is not a constant:
# selftest-hermetic derives its OWN target set from its roster, and on this branch that was 4 targets /
# 2013 s measured unbounded — the 900 s and 1800 s constants before it were KILLS, censored measurements.
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
  TMPDIR=$WORK; export TMPDIR                        # every child's TMPDIR is this run's work root
  ARGVLOG=$WORK/argv.log; : > "$ARGVLOG"; mkdir -p "$WORK/empty" "$WORK/gh"
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

bounds_init() {
  CEIL=$(raise_only "${PREPUSH_CEILING_S-}" 120 PREPUSH_CEILING_S)
  FLOOR=$(raise_only "${PREPUSH_MEM_FLOOR_MB-}" 6144 PREPUSH_MEM_FLOOR_MB)
  TIMEOUT_BIN=$(command -v timeout 2>/dev/null) || TIMEOUT_BIN=$(command -v gtimeout 2>/dev/null) ||
    TIMEOUT_BIN=""
  if [ -z "$TIMEOUT_BIN" ] && ! command -v sleep >/dev/null 2>&1; then unv "no timeout facility"; fi
  FREE=$(mem_free_mb 2>/dev/null) || FREE=""
  [ "$CEIL" -le "$SELFCEIL" ] || SELFCEIL=$CEIL     # raise-only, and never BELOW the core ceiling
  note "ceiling: ${CEIL}s/invocation (core-selftest ${SELFCEIL}s · heavy arms ${HCEIL}s or their budget-s) · memory floor: ${FLOOR} MB · free: ${FREE:-unreadable} MB · timeout: ${TIMEOUT_BIN:-watchdog}"
  mem_guard "${FREE-}" "$FLOOR" ||
    note "WARNING: free memory is not above the floor — the core is cheap and still runs; a heavy arm would be refused"
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

# ------------------------------------------------------------------- the scrubbed, bounded execution
# unset_pfx <PREFIX> — unset every EXPORTED name under it. A blanket, not a list: a list of names
# fails open on the first name nobody thought of (§3.4, security C16). DISCLOSURE (M-3): a name
# delivered as a TEMPORARY PREFIX on the call, not through the process environment, is absent from `env` and would survive this — immune as called (every scrubbed name is inherited), stated anyway.
unset_pfx() {
  for _v in $(env | LC_ALL=C awk -v p="$1" -F= 'index($1,p)==1 && $1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ {print $1}')
  do unset "$_v" 2>/dev/null || :; done
}
# run_timed <ceiling> <argv…> — timeout(1)/gtimeout when present, else a background watchdog. On the
# watchdog path there are TWO background jobs, and the header's "the only `&`" claim names both
# (reviewer M-1): the watchdog itself, AND the guarded invocation, which is backgrounded (`"$@" &`)
# precisely so the lane can `wait` on it and still kill it — it is the one job that runs a derived
# argv, and the `wait` keeps execution strictly serial. HONEST CEILING (reviewer M-2): the watchdog
# signals the DIRECT CHILD only — TERM, then KILL after a one-second grace, so a child that ignores
# TERM is still stopped; its GRANDCHILDREN are not in the lane's process group and may outlive it.
# timeout(1), when present, has the same reach. A check that daemonizes is outside this bound.
# AND (L3) the watchdog signals by PID: between the child exiting and the `kill`, the OS could have recycled that PID. Named, not closed (needs a process group or pidfd, neither POSIX); timeout(1) is clean.
run_timed() {
  _tc=$1; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_tc" "$@"; return $?; fi
  "$@" & _pid=$!
  ( _i=0
    while [ "$_i" -lt "$_tc" ]; do sleep 1; kill -0 "$_pid" 2>/dev/null || exit 0; _i=$((_i+1)); done
    kill -TERM "$_pid" 2>/dev/null || :
    sleep 1; kill -KILL "$_pid" 2>/dev/null || : ) & _wd=$!
  _rc=0; wait "$_pid" || _rc=$?
  kill -TERM "$_wd" 2>/dev/null || :
  return "$_rc"
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
  _al=""; for _t in "$@"; do _al="$_al $(qtok "$_t")"; done
  printf '%s\n' "${_al# }" >> "$ARGVLOG"
  _t0=$(date +%s); RUN_RC=0
  (
    _kgl=${KIT_GUARD_LOG-}; _hb=$RUN_HB
    unset_pfx GH_; unset_pfx GIT_; unset_pfx KIT_; unset_pfx BOARD_CLAIM_; unset_pfx PREPUSH_
    unset SSH_AUTH_SOCK SSH_ASKPASS BASH_ENV ENV CDPATH NODE_OPTIONS PYTHONPATH PERL5OPT RUBYOPT \
          HERMETIC_BASE IFS 2>/dev/null || :
    HOME=$WORK/empty; GH_CONFIG_DIR=$WORK/gh; TMPDIR=$WORK; LC_ALL=C
    GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_SYSTEM=/dev/null
    [ -z "$SHIMDIR" ] || PATH=$SHIMDIR:$PATH
    export HOME GH_CONFIG_DIR TMPDIR LC_ALL GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM PATH
    [ -z "$_kgl" ] || { KIT_GUARD_LOG=$_kgl; export KIT_GUARD_LOG; }
    [ -z "$_hb" ] || { HERMETIC_BASE=$_hb; export HERMETIC_BASE; }
    run_timed "$_cl" "$@"
  ) > "$WORK/out" 2>&1 < /dev/null || RUN_RC=$?
  RUN_S=$(( $(date +%s) - _t0 ))
}
# report_inv <bucket> <label> <expect-rc> <ceiling> — one line per invocation; a failing invocation's
# output is printed IN FULL (never tail'd), indented so it can never be mistaken for a report line.
report_inv() {
  RAN=$((RAN+1))
  if [ "$RUN_RC" -eq "$3" ]; then printf '  OK    %-18s %-46s %4ss\n' "$1" "$2" "$RUN_S"; return 0; fi
  FAILS=$((FAILS+1))
  case $RUN_RC in
    124|137|143) [ "$RUN_S" -lt "$4" ] || {
        _rm='raise PREPUSH_CEILING_S'; [ "$1" != heavy ] || _rm='add a heavy row with the measured budget or raise the ceiling'
        printf '  FAIL  %-18s %-46s %4ss  exceeded ceiling — %s\n' "$1" "$2" "$RUN_S" "$_rm"; return 0; } ;;
  esac
  printf '  FAIL  %-18s %-46s %4ss  rc=%s (expected %s)\n' "$1" "$2" "$RUN_S" "$RUN_RC" "$3"
  # A check's output is ARBITRARY BYTES. Under a UTF-8 locale `sed` refuses (or, on macOS, ABORTS) on
  # an illegal sequence — found by the first live run, which died before its verdict. Byte semantics,
  # and a raw fallback: no report FORMATTING failure may ever cost the run its verdict line.
  LC_ALL=C sed 's/^/        | /' "$WORK/out" 2>/dev/null || cat "$WORK/out" || :
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
# ---- PREPUSH-CORE-DEFAULT: the --warranted tree-key cache (design §3 item 3, §5) ----------------------
# A CONVENIENCE FOR THE PERSON RUNNING THE LANE, NEVER EVIDENCE: it is local, per-user and forgeable (a
# 32-bit cksum key, a plain file under $HOME), CI never reads it, and a SKIP line is not a pass. It applies
# ONLY to --warranted's arms — each core-live check and each warranted heavy arm — never to the default
# run, never to the board gates (they are cheap). After an arm PASSES the lane
# records `<tree-key> TAB <arm label> TAB <head>` in $HOME/.local/state/sparkwright/prepush/<root-commit>/
# passed (outside the repo: the lane still writes nothing in it); a later --warranted run on the same tree
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
CACHE_OK=0; CACHE_FILE=""; CACHE_KEY_FULL=""; CACHE_KEY_BK=""; CACHE_HEAD=""; CACHE_SKIPS=0; CORE_N=0
cache_off() { CACHE_OK=0; note "cache: off — $1 (every --warranted arm runs)"; }
# cache_cksum — stdin -> `<crc>-<len>` on stdout (empty on failure).
cache_cksum() {
  _cc=$(cksum) || return 0
  _cc1=${_cc%% *}; _cc2=${_cc#* }; _cc2=${_cc2%% *}
  case $_cc1$_cc2 in ''|*[!0-9]*) return 0 ;; esac
  printf '%s-%s\n' "$_cc1" "$_cc2"
}
cache_init() {
  CACHE_OK=0
  [ "$WARRANTED" -eq 1 ] || return 0
  if [ "${PREPUSH_NO_CACHE-}" = 1 ]; then cache_off "PREPUSH_NO_CACHE=1"; return 0; fi
  case ${HOME-} in /?*) ;; *) cache_off "HOME is unset or not absolute"; return 0 ;; esac
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
  _cs_s=$(K=$_ckey L=$_cs_l awk -F'\t' '$1 == ENVIRON["K"] && $2 == ENVIRON["L"] { print $3; exit }' "$CACHE_FILE" 2>/dev/null) || _cs_s=""
  case $_cs_s in ''|*[!0-9a-f]*) return 1 ;; esac
  _cs_x=""; [ "$1" = core-live ] || _cs_x=" (bookkeeping paths not compared; CI grades them)"
  printf '  SKIP  %-18s %-46s — passed at %s on this tree%s\n' "$1" "$2${3:+ $3}" "$_cs_s" "$_cs_x"
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
  { if [ -f "$CACHE_FILE" ]; then L=$2 awk -F'\t' '$2 != ENVIRON["L"]' "$CACHE_FILE" || :; fi
    printf '%s\t%s\t%s\n' "$_ckey" "$2" "$CACHE_HEAD"; } > "$_cr_t" 2>/dev/null &&
    mv -f "$_cr_t" "$CACHE_FILE" 2>/dev/null || rm -f "$_cr_t" 2>/dev/null
  return 0
}
# exec_cached <bucket> <basename> <argv> <expect-rc> <ceiling> — exec_check, then record the arm iff it
# PASSED (FAILS did not move) AND its output has no line starting `SKIP` (a tool-absent SKIP-pass is rc 0
# but proved nothing). A failing arm is never recorded.
exec_cached() {
  _ec_f=$FAILS
  exec_check "$@"
  [ "$CACHE_OK" -eq 1 ] && [ "$FAILS" -eq "$_ec_f" ] || return 0
  if grep -q '^SKIP' "$WORK/out" 2>/dev/null; then return 0; fi
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
    while IFS= read -r _r <&3; do
      _rb=${_r%%"$TAB"*}; _ra=${_r#*"$TAB"}
      if cache_skip core-live "$_rb" "$_ra"; then continue; fi
      exec_cached core-live "$_rb" "$_ra" 0 "$CEIL"
    done 3< "$WORK/q.order"
  else
    note "core-live: $CORE_N CI-derived checks NOT run by default — --warranted runs them; CI runs every one"
    run_shellcheck_scoped
  fi
  if [ -s "$WORK/q.sel" ]; then
    RUN_HB=$BASE; run_inv "$SELFCEIL" sh conformance/selftest-hermetic.sh --touched; RUN_HB=""
    # The count is the HERMETIC LANE'S OWN (its `TARGET:` lines), not this lane's q.sel: it re-derives
    # the set from its roster, so q.sel would misdescribe the subject that was actually run.
    report_inv core-selftest "selftest-hermetic --touched ($(LC_ALL=C grep -c '^TARGET: ' "$WORK/out" || :) targets by its own derivation, both faces)" 0 "$SELFCEIL"
  fi
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
    return 0
  fi
  while IFS="$TAB" read -r _bn _bb _ba <&3; do
    if [ "$_bn" = '(underived-registry-row)' ]; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-board "$_bn a board-gate registry row was not derived — check its shape"
      continue
    fi
    if [ "$_bb" = '!' ]; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-board "$_bn REFUSED: script or argv outside the closed charset (never executed)"
      continue
    fi
    if ! grep -qxF "conformance/$_bb.sh" "$WORK/scripts" 2>/dev/null; then
      RAN=$((RAN+1)); FAILS=$((FAILS+1))
      printf '  FAIL  %-18s %s\n' core-board "$_bn ($_bb.sh) not a regular file in conformance/ (never executed)"
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
    run_inv "$CEIL" sh "conformance/$_script" "$@"
    report_inv twin "$_tb $(fld 4 "$_row")" "${_tx:-0}" "$CEIL"
    note "  twin reason: $(fld 7 "$_row")"
  done 4< "$WORK/twins.ok"
}
# Tier 2 — never without its flag (§3.3, ruling §4.2), always behind the memory floor, each arm
# calling only the check that already exists. `--slow` runs the `heavy` ROWS inside their budget-s;
# a job-placement heavy invocation with no row has no measured budget and is named, not run.
run_heavy() {
  [ -n "$HEAVY" ] || return 0
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
    if awk -v t="conformance/$_b.sh" \
         '$1=="check"{for(i=2;i<=NF;i++) if($i==t) f=1} END{exit !f}' \
         conformance/verify.sh 2>/dev/null
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
        heavy_allowed warranted-non-vacuity || continue
        heavy_busy warranted-non-vacuity || continue
        exec_cached heavy non-vacuity "--only $_nb.sh" 0 "$HCEIL"
        ;;
      green-on-clone)
        if cache_skip heavy green-on-clone ''; then continue; fi
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
  if [ "$WARRANTED" -eq 0 ] && [ "$CORE_N" -gt 0 ]; then
    printf 'PARITY-CORE: OK (own surface — %s CI-derived core-live check(s) not run; --warranted and CI run them)\n' "$CORE_N"
  elif [ "$WARRANTED" -eq 1 ] && [ "$CACHE_SKIPS" -gt 0 ]; then
    printf 'PARITY-CORE: OK (%s arm(s) from cache, not executed this run)\n' "$CACHE_SKIPS"
  else printf 'PARITY-CORE: OK\n'; fi
}

verdict() {
  [ "$VERBOSE" -eq 0 ] || { note "executed argv ($RAN invocation(s), log $ARGVLOG):"
                            sed 's/^/#   /' "$ARGVLOG"; }
  note "work root: $WORK (removed best-effort at exit)"
  _rc=0
  if [ -n "$UNV" ]; then _v="PARITY-CORE: UNVERIFIED ($UNV)"; _rc=1
  elif [ "$FAILS" -gt 0 ]; then _v="PARITY-CORE: FAIL"; _rc=1
  else _v=$(ok_verdict); fi
  printf '%s\n' "$_v"                       # THE LAST LINE, always, and never `RESULT:`
  [ "$BEST" -eq 0 ] || _rc=0                # --best-effort moves the rc, never the verdict line
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
  derive "$_ci" > "$WORK/derive.out" 2>&1 || { sed -n '/^#/p' "$WORK/derive.out"
                                               unv "unparseable ci.yml"; verdict; return $?; }
  sed -n '/^#/p' "$WORK/derive.out"
  read_twins; twin_exec_check
  [ ! -s "$WORK/twins.err" ] || { sed 's/^/# TWIN-TABLE MALFORMED: /' "$WORK/twins.err"
                                  unv "the twin table is malformed — run --census"; }
  split_buckets
  if [ -n "$UNV" ]; then note "NOT RUN: $UNV"; verdict; return $?; fi
  run_core; run_board; run_twins; run_heavy; run_warranted; reco
  verdict
}

# ------------------------------------------------------------------------------------ entry point
main() {
  # NO ARGUMENT is THE RUN (`sparkwright prepush`); --help is rc 2 — the kit's usage convention,
  # locked live by conformance/sparkwright-verbs.sh ("`prepush --help` exits 2 through the router").
  _mode=""; _ci=${KIT_CI_FILE:-$CI_DEFAULT}; _strict=0
  while [ $# -gt 0 ]; do
    case $1 in
      --derive|--census|--selftest) [ -z "$_mode" ] || die2 "one mode per invocation"; _mode=$1 ;;
      --ci-file) [ $# -ge 2 ] || die2 "--ci-file needs a path"; _ci=$2; shift ;;
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
  case $_mode in
    --selftest) selftest; exit $? ;;
    --run)      root_or_die; cd "$ROOT"
                _rel=$(resolve_ci "$_ci") || exit $?
                run_lane "$_rel" ;;
    --census)   root_or_die; cd "$ROOT"
                census "$_ci" ;;
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
  # THE ROSTER, in order; each name is a leg's function name verbatim (a missing one is a `not found`).
  for _leg in grammar continuation block_scalar disqualifiers env_not_applied doc_level ci_file \
              census_unbucketed census_denominator census_negative twin_stale twin_cishape \
              heavy_rows twin_grammar injection scrub docs_only rename newline newline_charset base \
              ceiling budget \
              floor argv core_selftest heavy_needs_flag dash verdict shim no_fanout no_write \
              no_exec_of_context core_live_default shellcheck_scoped \
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
              board_gate_symlink board_gate_literal board_gate_selftest_prefix
  do "selftest_$_leg"; done
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
  for _n in alpha beta verify; do printf '#!/bin/sh\nexit 0\n' > "$_d/conformance/$_n.sh"; done
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
  one_step; mkchk alpha 'printf "gh=[%s] ssh=[%s] kit=[%s] gsc=[%s] gdir=[%s] bc=[%s] pp=[%s] gcg=[%s] lc=[%s] home=[%s] tmp=[%s]\n" "${GH_TOKEN-}" "${SSH_AUTH_SOCK-}" "${KIT_NOSE-}" "${GIT_SSH_COMMAND-}" "${GIT_DIR-}" "${BOARD_CLAIM_X-}" "${PREPUSH_X-}" "${GIT_CONFIG_GLOBAL-}" "${LC_ALL-}" "$HOME" "$TMPDIR" > "$PWD/env.out"'
  commit_fx
  # GIT_DIR is paired with GIT_WORK_TREE so the LANE's own git still works: unpaired, it points the lane itself at another repo — a different question (rc 2, "not a git repository").
  DVOUT=$( cd "$d" && GH_TOKEN=tok SSH_AUTH_SOCK=/tmp/s KIT_NOSE=1 GIT_SSH_COMMAND='ssh -i /k' GIT_DIR=$d/.git GIT_WORK_TREE=$d BOARD_CLAIM_X=1 PREPUSH_X=1 sh "$LANE" --base HEAD --warranted 2>&1 )  # --warranted: the probe is a core-live check
  _wr=$(workroot); _env=$(cat "$d/env.out" 2>/dev/null || echo MISSING)
  sfx "scrub: every scrubbed prefix is empty, HOME is under the work root, LC_ALL is C" "gh=[] ssh=[] kit=[] gsc=[] gdir=[] bc=[] pp=[] gcg=[/dev/null] lc=[C] home=[$_wr/empty] tmp=[$_wr]" "$_env"
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
  commit_fx; mkchk gamma 'exit 0'
  env_rn "$d" PREPUSH_MEM_FLOOR_MB 99999999 --green-on-clone
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
  mkchk selftest-hermetic 'printf "base=[%s] argv=[%s]\n" "${HERMETIC_BASE-}" "$*" > "$PWD/herm.out"; echo "TARGET: conformance/gamma.sh (both faces)"'
  commit_fx; mkchk gamma 'exit 0'; rn "$d" --verbose; sfx "core-selftest: rc 0" 0 "$DVRC"
  want "core-selftest: the touched face RUNS and is labelled core-selftest" "^  OK    core-selftest *selftest-hermetic --touched (1 targets by its own derivation, both faces)"
  want "core-selftest: the untouched invocations are LISTED, not run" "^# untouched-selftest: 1 derived --selftest invocations NOT run"
  wantnot "core-selftest: the MERGED scanner label never appears in a run report" "^  OK    selftest "
  wantnot "core-selftest: and no untouched --selftest is executed" "^#   sh conformance/beta\.sh"
  sfx "core-selftest: the hermetic call got --touched under HERMETIC_BASE=the base" "base=[HEAD] argv=[--touched]" "$(cat "$d/herm.out" 2>/dev/null || echo MISSING)"
  want "core-selftest: its ceiling is the named SELFCEIL, not the 120s core ceiling" "^# ceiling: 120s/invocation (core-selftest 3600s · heavy arms 3600s"
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
  sfx "heavy/flag: the executed-argv log is empty" "0" "$(printf '%s\n' "$DVOUT" | grep -c '^#   sh conformance/' || :)"
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

selftest_shim() {
  one_step; mkchk alpha '{ command -v sh; ls "$(dirname "$(command -v sh)")"; ls -ld "$(dirname "$(command -v sh)")"; cat "$(command -v sh)"; } > "$PWD/shim.out" 2>&1'
  commit_fx; rn "$d" --warranted; want "shim: the report header names the resolved dash" "^# shell: dash /"   # --warranted: the probe is a core-live check
  _wr=$(workroot); DVOUT=$(cat "$d/shim.out" 2>/dev/null || echo MISSING)
  sfx "shim: a child's \`sh\` resolves to the shim under the work root" "$_wr/shim/sh" "$(sed -n 1p "$d/shim.out")"
  sfx "shim: the shim dir holds EXACTLY sh" "sh" "$(sed -n 2p "$d/shim.out")"
  want "shim: the shim dir is 0700" "^drwx------"; want "shim: and its sh execs the resolved dash" "^exec .*dash "
}

# SERIAL by OBSERVATION, not by grep: two invocations that log their own start and end must not interleave. (M-1: run_timed backgrounds the invocation itself AND a watchdog, then `wait`s — the `wait` is the serialization, so only an observation can prove it.)
selftest_no_fanout() {
  mkcin 'sh conformance/alpha.sh' 'sh conformance/beta.sh'
  mkchk alpha 'echo a-start >> "$PWD/ser.out"; sleep 2; echo a-end >> "$PWD/ser.out"'
  mkchk beta  'echo b-start >> "$PWD/ser.out"; sleep 1; echo b-end >> "$PWD/ser.out"'
  commit_fx; rn "$d" --warranted   # the two probes are core-live checks: only --warranted runs them
  sfx "no-fanout: the invocations never overlap" "a-start a-end b-start b-end" "$(tr '\n' ' ' < "$d/ser.out" | sed 's/ $//')"
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
}

selftest_no_exec_of_context() {
  mkcin 'sh conformance/alpha.sh; echo NEEDLE-NOT-RUN' 'sh conformance/beta.sh --ok'
  mkchk alpha 'exit 0'; mkchk beta 'exit 0'; commit_fx; rn "$d" --warranted --verbose   # core-live runs only under --warranted
  want "no-exec: --verbose echoes the executed-argv log" "^#   sh conformance/beta\.sh --ok$"; wantnot "no-exec: no token from a context line is ever executed" "NEEDLE-NOT-RUN"
  sfx "no-exec: exactly one invocation ran" "1" "$(printf '%s\n' "$DVOUT" | grep -c '^#   sh conformance/' || :)"
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
  want "cache/heavy: claims SKIPs, saying the bookkeeping paths were not compared" "^  SKIP  heavy  *claims-registry .*passed at [0-9a-f][0-9a-f]* on this tree (bookkeeping paths not compared; CI grades them)$"
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
  sfx "cache/opt-out: and nothing was written under HOME" no "$([ -e "$_h/.local" ] && echo yes || echo no)"
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

main "$@"
