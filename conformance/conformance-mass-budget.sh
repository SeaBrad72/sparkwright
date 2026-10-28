#!/bin/sh
# conformance-mass-budget.sh — ratchet the KIT'S OWN conformance mass so it cannot silently re-bloat,
# and so "extend an existing check" is the cheap path and "add another check" is the expensive one
# (CONFORMANCE-MASS-BUDGET, CUT-A7 of D-240819-2). The measured provocation: +30,981 conformance
# lines and 39 new checks in the 35 days after the design skill's "prefer extending a gate" sentence
# shipped. A preference with no surfaceable answer did not bind; a gate does.
#
#   sh conformance/conformance-mass-budget.sh [--selftest | --list-legs | --grade-cells <n> <workspace|tmpclone> | --grade-cells-listing]
# Exit: 0 = within the ratified ceiling (or N/A off-kit) · 1 = over budget / ledger broken · 2 = usage.
# POSIX sh; dash-clean. No network: every number is a property of the tree in front of it, so the verdict cannot
# change with the base a runner happened to check out. ONE EXCEPTION (SWAS-281): mb_genesis_lock reads the merge-base
# with git, on a pull_request event only, to stop a PR moving its own GENESIS_ lines; elsewhere it prints N/A.
#
# ── SCOPE CEILING (say it before anyone infers more). This gate counts exactly seven things:
#   (a) total lines of the NON-RECURSIVE conformance/*.sh glob,
#   (b) how many such files there are,
#   (c) the `^check control ` row count of conformance/verify.sh,
#   and, since SWAS-281 (CI-TIME-BUDGET, design 2026-10-24-ci-time-budget-design.md), four counts of what CI RUNS, each a property of
#   the tree and each zero-headroom (a rise costs one ack line, like `files` and `census`):
#   (d) `rows`  -- the verify.sh `^check ` rows that are not `control` rows (so (c) and (d) partition the registry),
#   (e) `cells` -- the guard battery's cells: the line count of `agent-autonomy.sh --list-cells` (one line per cell, follows lines
#                  included; the --join's `listed` set is built from that same output, and leg ci-b15 locks that coupling). DIMS-DEPENDENT
#                  (listed 4168 workspace, 4167 tmpclone in CI), so one genesis per variant; graded in the guard-battery join (see MB_CELLS_MODE),
#                  so a LOCAL pre-push does NOT catch a cells rise: CI's join does,
#   (f) `legs`  -- the selftest legs of the literal MB_HEAVY_CHECKS list, each check's own `--list-legs` count,
#   (g) `jobs`  -- the runner jobs one full run starts: `ci-gates.sh --count-legs` (matrix size per job, over every workflow with a
#                  pull_request or push trigger).
#   HOSTED-RUNNER MINUTES ARE NOT BUDGETED HERE and never red anywhere: a +46% swing on one job across three runs was seen on unchanged
#   inputs [attested]. Minutes are a WARN (scripts/ci-time-report.sh, the non-required ci-time-report job). These counts are PROXIES for
#   time: the design's section 8 states their ceiling (a slower cell or row with no count change is not stopped, only annotated).
# Everything else is OUTSIDE the budget and always was: the .md checklists in conformance/, the
# conformance/ subdirectories (fixtures/, incept-manifests/), scripts/, hooks/, guard-core. It counts
# whether growth was DECLARED, never whether it was WORTHWHILE — the reason cell of an ack is prose a
# ratifier reads, not a machine-checked claim.
#
# ── THE CENSUS IS THIS GATE'S OWN MEASURE. The kit's check count is reconciled by the `Scripts:` line
# verify.sh prints beside its Summary (PR 10) — rows · unique scripts · files on disk · files no row
# invokes, at runtime; the earlier "three methods, three answers" note is retired. This gate restates
# none of it: it DEFINES its census as the `^check control ` row count and says so wherever it prints
# one. It also prints the `^check ` total, because the two populations differ and neither is the other. A TOP-LEVEL
# check wired only in ci.yml is invisible to (c) but fully visible to (a) and (b) — note the
# qualifier: a check living in a conformance/ SUBDIRECTORY is invisible to all three surfaces, which
# is the family-wide convention this glob inherits, not a property of this gate. What remains of
# CONFORMANCE-MUTATION-COVERAGE-GAP is coverage, not counting.
#
# ── KIT-SELF, and it is a CATEGORY distinction, not a convenience. This ratchets the KIT's conformance
# directory. An adopter's checks are the adopter's business, and holding them to the kit's numbers
# would be a kit ratchet charged to adopter content — the measured doc-budget incident, where
# unqualified rows redded a brand-new adopter's first `verify.sh --require`. Both verify.sh rows carry
# --kitself AND the check stands down in-script on the same OR-of-markers detector, so neither surface
# alone is the switch. The arming test runs BEFORE any enumeration: an adopter tree must never reach
# the fail-closed empty-enumeration refusal, which is about a broken counter in the kit's own repo.
set -eu

TAB=$(printf '\t')

# ── THE CONSTANTS. ONE per surface — a frozen ORIGIN. The ceiling is not a second constant beside it;
# it is DERIVED from the ledger on every run and printed with its derivation.
#
# GENESIS_* is the founding measurement: the mass of the tree that shipped this gate, measured in its
# own PR (the gate's first real subject is the change that introduces it). ⚠️ GENESIS IS SET ONCE AND
# IS NEVER EDITED AGAIN. It is the fixed origin the whole audit trail hangs off; moving it would
# rewrite history rather than record it. If you find yourself editing a GENESIS line, you want an ack
# line in conformance/mass-acks.txt instead. WHAT ACTUALLY BINDS THAT IMMUTABILITY is not this comment:
# BOTH this file and conformance/mass-acks.txt are control-plane paths, so moving a GENESIS constant —
# or editing the ledger — is a RATIFIED act. The guard refuses the edit outside a dev-clone and
# conformance/agent-boundary.sh reds it as an unratified control-plane change (measured: rc 1 for both
# paths against `--ratified 0`). The honest ceiling: that makes the edit VISIBLE and reviewable, not
# impossible — a ratifier who waves it through still waves it through.
#
# THE CEILING IS WRITTEN DOWN NOWHERE (MASS-CEILING-ADDITIVE, 2026-09-04, ruling D-240903-1). It is
# COMPUTED on every run as
#       MAX_x = GENESIS_x + Σ(deltas of mass-acks.txt lines scoped to x)
# and printed with that derivation beside it. Until this change the same value was ALSO carried as a
# `MAX_x=` literal here and checked against the sum in both directions; the literal was a CACHE of a
# number this script recomputes anyway, and it was the one line every control-plane slice had to edit
# — so of two branches in flight the second to merge always hit a textual conflict on it and rewrote
# the ceiling by hand. Deleting the cache removes the conflict AND the two states the old invariant
# graded: a pre-emptive ack (an ack no raise consumes) and an unacked raise are no longer
# CONSTRUCTIBLE, because there is nothing left that can disagree with the ledger. What replaces the
# invariant is mb_no_literal_max, which reds if a `MAX_<surface>=<digits>` literal is ever written
# back into this file. So the ceiling is a pure function of a reviewable ledger, every movement is a
# permanent line item, and none of it depends on a diff.
# ⚠️ THE HONEST CEILING OF THAT: the ledger is now the ONLY place a ceiling lives — the single source
# of truth, and equally a single point of trust. What holds it is not this comment: mass-acks.txt is a
# control-plane path (the guard refuses the edit outside a dev-clone, agent-boundary.sh reds it as an
# unratified control-plane change), GENESIS stays frozen here, and every consumed row is printed BY
# NAME on every run, green or red. The gate still cannot judge whether an ack is HONEST; the reason
# cell is the ratifier's reading, exactly as before.
#
# ── TWO POPULATIONS, TWO PRICES (MASS-BUDGET-LOGIC-FIXTURE-SPLIT, 2026-08-31). Until this split the
# budget priced a new check PREDICATE and a selftest FIXTURE CELL identically, and it was measured
# that ~44% of all budgeted mass (24,785 of 55,700 lines) was fixture — load-bearing negatives the
# non-vacuity doctrine DEMANDS — charged at the rate the budget exists to make expensive. The ack
# ledger shows the consequence: ~73% of the D-240825-1 raise and ~90% of D-240826-1's +2,553 were
# fixture cells, so three consecutive slices ran at 0-2 lines free and every review round that bought
# a finding its permanent negative triggered owner ack arithmetic. The expensive signal (new check
# logic) drowned in the cheap one. The boundary between the two populations is not invented here: it
# is non-vacuity.sh's selftest marker, copied verbatim into mb_first_marker above.
#
#   logic   — everything strictly BEFORE the selftest marker, plus ALL of a marker-less file.
#             ZERO-HEADROOM beyond the genesis rounding: a raise needs a ratified ack, every time.
#             This is the number the merge-don't-add ratchet was always about.
#   fixture — the marker line and everything after it. BANDED: an inaugural `fixture` ack buys a
#             standing +500, inside which growth needs NO per-slice ack. Exceeding the band reds
#             until the band is re-ratified — topped back to measured+500 at each PUBLISH BOUNDARY
#             (next: Tier 2 close), or earlier if it is exhausted mid-epoch. The trade is deliberate:
#             per-EPOCH visibility instead of per-slice, bought for the reviewer-buys-a-negative path.
#
# ⚠️ THE VIRTUOUS ACT IS AN EXPECTED ACK REASON, AND SAYING SO IS THE POINT. Adding a REAL selftest to
# a check that has none moves that file's marker from "absent" to a line number, which REPRICES all of
# its post-marker mass from `logic` to `fixture` and can move several hundred lines at once. That is
# exactly the act CONFORMANCE-MUTATION-COVERAGE-GAP (PR 10) exists to encourage — the two live
# candidates are kit-update-merge.sh (708 lines) and promotion-readiness.sh (543) — so a `logic` or
# `fixture` ack whose reason is "gave <check> a real selftest" is a GOOD ack, not a laundering, and a
# ratifier should read it as such. The composition report line below makes the repricing legible in
# the same CI summary that ratifier reads.
#
# ── WHAT THE SPLIT DOES NOT DO (say it before anyone infers more). The mutation sweep does NOT police
# this boundary: moving a marker earlier shrinks the mutable region until the sweep reports UNCOVERED,
# which it treats as an honestly-passing state (non-vacuity.sh:218-221,386). What actually bounds
# marker-move repricing is the fixture band capping the gain at <=500 lines per epoch, plus the
# composition line. Logic written BELOW a marker was already un-mutated and is now also mispriced — a
# pre-existing hole this split monetises but does not widen; review remains its only detector.
#
# DERIVATION — measured on the post-diff tree of the PR that ships this gate (see the design's §10):
#   files : the measured count, EXACTLY, with ZERO headroom, and that is deliberate. Slack in this
#           surface is a silent budget an adder can spend without an ack, which defeats
#           merge-don't-add precisely where it is supposed to bind. Every new conformance/*.sh
#           therefore costs ONE ratified ack line in conformance/mass-acks.txt. Same for census.
#   logic /
#   fixture : the measured total ROUNDED UP to the next 100 (the doc-budget.sh convention), with the
#           exact measured figure AND THE VERBATIM MEASUREMENT COMMAND AND HEAD SHA recorded in the
#           REASON CELL of the ack that moves it (A1/C5) so a reviewer can re-derive the number
#           independently instead of accepting the builder's. Line count churns whenever anyone adds a comment or a leg to
#           an EXISTING check, which is the behaviour this gate exists to ENCOURAGE, so neither line
#           surface is exact-measured the way files and census are — a file exists or it does not.
#
# ── THE `lines` SURFACE IS RETIRED (2026-08-31) BUT ITS HISTORY IS VERIFIED FOREVER. GENESIS_LINES is
# FROZEN and the retired ceiling is still DERIVED as GENESIS_LINES + Σ(lines acks) and printed with
# its rows on every run, so the ten historical rows keep being read out; only the MEASUREMENT
# comparison moved to logic/fixture. Retirement itself is enforced by HISTORICAL_LINES_ACKS, a ROW-COUNT PIN — not by a
# date (author-supplied and trivially backdated) and not by the grammar (see mb_ledger_check). The
# count pin is also the only thing that can see a ZERO-SUM PAIR: a +N and a -N `lines` row with
# distinct reasons leaves the arithmetic green while inventing two rulings in the provenance output.
# ⚠️ HONEST CEILING OF THE PIN — it counts ROWS, so its scope is APPEND and ZERO-SUM PAIR, and no more.
# EDITING AN EXISTING historical row is invisible to it: rewrite a reason cell into a different ruling
# and the count is unchanged, the deltas are unchanged, and the derived ceiling is unchanged, so the gate
# stays green while the provenance narrative a ratifier reads has been forged in place. Nothing here
# detects that; the detectors are the diff and the reviewer, exactly as for any other control-plane
# text. Claiming otherwise would be the vacuous-green defect this file exists to refuse.
GENESIS_LINES=51400     # RETIRED 2026-08-31, FROZEN: measured 51,312 lines across conformance/*.sh, rounded up to the next 100. Kept so the ten historical `lines` acks stay arithmetically verified forever.
HISTORICAL_LINES_ACKS=10   # measured at the reviewed head, VERBATIM: grep -v '^#' conformance/mass-acks.txt | grep -c "$(printf '\t')lines$(printf '\t')"   -> 10 at 8c090a2b. A `lines` row count other than this is a FAIL naming the retired surface.
GENESIS_FILES=168       # measured exactly; no headroom by design
GENESIS_CENSUS=128      # measured exactly; `^check control ` rows in conformance/verify.sh

# ── THE SPLIT'S OWN GENESIS. Measured on the post-diff tree of THIS PR — the split's first subject is
# the change that introduces it — with the VERBATIM command and the head SHA recorded per A1/C5, so
# the reviewer seat re-runs it and states the number independently. The command is the same rule
# mb_first_marker applies, written out longhand so re-deriving it needs nothing from this file:
#
#   for f in conformance/*.sh; do LC_ALL=C awk '/^[[:space:]]*selftest[[:space:]]*\(\)/{if(fn==0)fn=NR} /^[[:space:]]*if[[:space:]].*--selftest/&&($0~/\$1/||$0~/\$\{1/){if(ifb==0)ifb=NR} /--selftest\)/{if(arm==0)arm=NR} END{m=0;if(fn>0)m=fn;if(ifb>0&&(m==0||ifb<m))m=ifb;if(m==0&&arm>0)m=arm;if(m>0){print "L",m-1;print "F",NR-(m-1)}else{print "L",NR}}' "$f"; done | LC_ALL=C awk '{t[$1]+=$2} END{print "logic",t["L"]+0,"fixture",t["F"]+0,"total",t["L"]+t["F"]+0}'
#
# Baseline before this diff, at 60e2cd22: logic 30915 · fixture 24785 · total 55700 (the split sums to
# the pre-split gate's own count, which is how the boundary rule was cross-checked in the first place).
GENESIS_LOGIC=31200     # measured 31141 by the VERBATIM command above at HEAD b067d8c5 (the post-diff tree of this PR, this slice's own new gate logic included), rounded up to the next 100 per the genesis convention. ZERO acks: MAX_LOGIC == GENESIS_LOGIC, so every future logic line costs a ratified ack.
GENESIS_FIXTURE=25000   # measured 24969 by the VERBATIM command above at HEAD b067d8c5, rounded up to the next 100. ⚠️ RE-DERIVE, DO NOT ACCEPT, AND NOTE THAT THE TREE MOVED UNDER THESE CONSTANTS: logic·fixture measured 31141·24969 at b067d8c5 (the genesis-setting head), 31174·25052 at beeabb55 (the pre-push fix round), and 31186·25069 at the PR head (this commit, which adds comment and selftest-leg lines the *.sh glob does count); all three fit the ratified ceilings, so genesis is deliberately NOT re-based — re-basing to fit a diff is a silent re-ratification, and the shrinking logic residual is the signal the zero-headroom surface exists to give.

# ── THE FOUR CI-TIME COUNTS (SWAS-281, CI-TIME-BUDGET). Each GENESIS_ is the exact count measured on the head of the PR that introduced
# them (first-live-run dogfood), with ZERO headroom: every rise needs one ack line in conformance/mass-acks.txt, whose reason says what grew
# and why (by convention with a cost estimate from the design's section 1 rates, labelled [E]; the estimate is conduct, not checked).
# ⚠️ GENESIS IS SET ONCE. A PR cannot move its own origin: on a pull_request event mb_genesis_lock compares every GENESIS_ line with the
# merge-base's copy and reds on any difference; the introducing PR is the one stated exception (these four names are absent at its base).
GENESIS_ROWS=20
# THE CELL COUNT IS DIMS-DEPENDENT, so `cells` has ONE GENESIS PER CI VARIANT, recorded with the dims it was measured at; the join passes its variant (`--grade-cells <n> <variant>`).
# MEASURED [M] in CI run 40158226802: job 121066165278 (workspace) printed `agent-autonomy --join: listed cells: 4168`; job 121066165222 (tmpclone) printed `listed cells: 4167`.
# WHY LISTED < EXECUTED: the graded measure is the deduplicated LISTED set (aa_cell_skip indexes one cell per distinct label and counts a repeat of the previous label once, and
# the inner gates of a nested cell are run but never indexed); the join's OK line counts cells EXECUTED (4186 / 4185), 18 more. A first seed from that OK line left 18 free: wrong.
GENESIS_CELLS_WORKSPACE=4168   # dims case0-tmp0-git1-uid00 (the kit checkout under $GITHUB_WORKSPACE); one `cells` ack line raises both ceilings
GENESIS_CELLS_TMPCLONE=4167    # dims case0-tmp1-git1-uid00 (a git clone under /tmp)
GENESIS_LEGS=55   # measured: the label count of this script's own --list-legs on the introducing head (the one heavy check on MB_HEAVY_CHECKS)
GENESIS_JOBS=66   # measured: ci-gates.sh --count-legs total on the introducing head (includes the new ci-time-report job)
# The heavy checks whose selftest legs are budgeted: each must answer `--list-legs` (one label per line) and its own --selftest must run
# exactly those legs (this file's wrapper below does that for itself). SEEDED with this gate alone; the design's rule for growing it is
# "the selftests whose conformance-selftests steps take >= 60 s in the jobs API's per-step times", which needs a live run to measure.
MB_HEAVY_CHECKS="conformance-mass-budget.sh"
# HOW `cells` IS MEASURED (the design's section 2.3 fallback, taken because the listing was MEASURED at ~2 minutes of wall on the introducing head,
# against the design's 30 s bound): `agent-autonomy.sh --list-cells` runs the whole battery script in list mode, which is far too slow for the
# every-push light job, for verify.sh --kitself and for the local core pre-push. So the default run does NOT list: its cells line says N/A (not a pass),
# `--grade-cells <n>` grades a count the caller supplies (the guard-battery join job passes the join's own listed-set size, printed by `agent-autonomy.sh
# --join` after a green join), and `--grade-cells-listing` lists on demand (about 2 minutes; the deliberate local act). Set here unconditionally and from
# argv only, like agent-autonomy.sh's mode, so an environment value is ignored. GENESIS_CELLS is held by the genesis lock on every PR either way.
MB_CELLS_MODE=na

# ── THE GLIDE SEAM (A1/C7b), the D-240828-4 ratchet-never-cut counter: present, and never
# agent-actuated. EMPTY means no target and the report says so. Setting it to a number prints an
# ADVISORY distance line and NOTHING ELSE — it is not a verdict, and making it one is a policy
# decision the OWNER takes by a later one-line change here, with this field as the ready seam. What
# holds that is not this comment: this file is a control-plane path, so the guard refuses the edit
# outside a dev-clone and agent-boundary.sh reds it as an unratified control-plane change. The honest
# ceiling is the same as the one at :50-53 — that makes the edit VISIBLE and reviewable, not
# impossible; a ratifier who waves it through still waves it through.
# MASS-BUDGET-DOWNWARD (2026-09-19): setting LOGIC_GLIDE_TARGET restates, but does not discharge, the panel's mass-budget condition — the glide is ADVISORY and UNENFORCED, and the only control this gate enforces remains unchanged: a raise still costs a ratified ack in conformance/mass-acks.txt.
LOGIC_GLIDE_TARGET=34106

# mb_files_list <root>: print each NON-RECURSIVE <root>/conformance/*.sh path, one per line.
mb_files_list() {
  for _f in "$1"/conformance/*.sh; do
    if [ -f "$_f" ]; then printf '%s\n' "$_f"; fi
  done
  return 0
}

# mb_count_files <root>: how many such files (0 when none).
mb_count_files() { _n=$(mb_files_list "$1" | grep -c '' 2>/dev/null) || _n=0; printf '%s\n' "$_n"; }

# mb_count_lines <root>: total lines across those files (an unterminated final line counts as one,
# matching `awk 'END{print NR}'` — the doc-budget.sh convention).
mb_count_lines() {
  mb_files_list "$1" | LC_ALL=C awk '{ n=0; while ((getline _l < $0) > 0) n++; close($0); t += n } END { print t+0 }'
}

# ── THE LOGIC/FIXTURE BOUNDARY. mb_first_marker is a VERBATIM COPY of conformance/non-vacuity.sh's
# `first_marker` (its lines 61-75 as of 2026-08-31). ⚠️ CROSS-CITE — IF YOU CHANGE ONE, READ THE OTHER:
# the original lives in conformance/non-vacuity.sh and is the kit's tested definition of where check
# LOGIC ends and the selftest ORACLE/FIXTURE region begins; this copy prices the same boundary.
# WHY A COPY AND NOT A SHARED LIB: a new conformance/*.sh costs a ratified `files` ack against zero
# headroom, for ~15 lines (design 4). DISCLOSED DRIFT CEILING: if the original refines its rule the
# two can disagree, and the consequence is a MISPRICED boundary — an accounting error, never a
# weakened gate. leg xvii pins this copy's semantics (fn / positional if-block / case-arm fallback /
# none, plus the fn-beats-an-earlier-arm precedence) with a fixture file per arm, so a silent
# semantic change to the copy reds here rather than quietly repricing the budget.
mb_first_marker() {
  LC_ALL=C awk '
    /^[[:space:]]*selftest[[:space:]]*\(\)/ { if (fn==0) fn=NR }
    /^[[:space:]]*if[[:space:]].*--selftest/ && ($0 ~ /\$1/ || $0 ~ /\$\{1/) { if (ifb==0) ifb=NR }
    /--selftest\)/ { if (arm==0) arm=NR }
    END {
      m=0
      if (fn>0)  m=fn
      if (ifb>0 && (m==0 || ifb<m)) m=ifb
      if (m==0 && arm>0) m=arm     # fallback: no fn / if-block, only a case arm
      print m
    }
  ' "$1"
}

# mb_marker_ok <token>: 0 iff <token> is a well-formed COUNT — a non-negative integer with no leading
# zeros. FAIL-CLOSED GRADING, and it exists for the same measured reason as mb_delta_ok's grammar: an
# empty or non-numeric token reaching the `$((...))` below aborts dash with rc 2 and NO printed
# verdict, which a harness reads as UNVERIFIED rather than FAIL (this file's own :126-131 lesson). A
# measurement this gate cannot trust must become a printed FAIL, never a shell abort and never a 0.
mb_marker_ok() { printf '%s' "$1" | LC_ALL=C grep -qE '^(0|[1-9][0-9]*)$'; }

# mb_split_rows <root>: one row per NON-RECURSIVE <root>/conformance/*.sh file, as
#     <total-lines> <marker-line> <logic-lines> <fixture-lines> <basename>
# on stdout, and a `conformance-mass-budget: FAIL --` line (also on stdout, so it reaches the same CI
# summary) for any file that cannot be MEASURED. Returns 1 if any file was unmeasurable.
# THE RULE: marker > 0  =>  the lines strictly BEFORE it are logic and the rest is fixture;
#           marker == 0 (no oracle region at all) => ALL of it is logic. That default is deliberately
# the CONSERVATIVE direction: 17 of the kit's own checks carry no marker, and pricing them as fixture
# would drop them into the banded surface where they could grow ack-free (leg xvi pins this).
mb_split_rows() {
  _srbad=0
  for _f in "$1"/conformance/*.sh; do
    [ -f "$_f" ] || continue
    # SHAPE-VALIDATE THE NAME BEFORE IT IS PRINTED OR EMITTED AS A FIELD (security vet F-2). These
    # rows are whitespace-separated and are re-parsed downstream, and every FAIL below interpolates
    # the name into a line a human reads: a filename carrying spaces, a newline or a
    # `conformance-mass-budget: FAIL` prefix could forge a row or a verdict. A conformance check is
    # named [A-Za-z0-9._-]+.sh or it is UNMEASURABLE — no enumeration of hostile shapes required.
    # ⚠️ THE RAW NAME IS GRADED, AND BY `case`, AND BOTH HALVES OF THAT ARE THE POINT. Sanitizing
    # first would let mb_san DELETE the offending byte before the whitelist saw it, so a newline- or
    # tab-bearing name would pass as its own merged remnant and be MEASURED under a name that is not
    # its own. And `grep` grades LINE BY LINE, so a two-line name whose second line is well-formed
    # satisfies `grep -q` — the same escape by another route. `case` matches the WHOLE string,
    # newlines included, with no subprocess. Sanitize only on the way to a human's screen.
    _braw=${_f##*/}
    _bn=$(printf '%s' "$_braw" | mb_san)
    case "$_braw" in
      *[!A-Za-z0-9._-]*) _bok=0 ;;
      ?*.sh)             _bok=1 ;;
      *)                 _bok=0 ;;
    esac
    if [ "$_bok" -eq 0 ]; then
      echo "conformance-mass-budget: FAIL -- a conformance/*.sh entry cannot be MEASURED: its basename [$_bn] is not of the form [A-Za-z0-9._-]+.sh (shown sanitized; the RAW name is what was graded). The name is a FIELD in the split rows and is printed into this summary, so an off-shape name is refused rather than parsed."
      _srbad=1; continue
    fi
    if [ ! -r "$_f" ]; then
      echo "conformance-mass-budget: FAIL -- $_bn cannot be MEASURED: it is not readable. An unmeasurable file is never priced at 0 — a broken or hostile mode would otherwise BUY headroom by being broken."
      _srbad=1; continue
    fi
    _tl=$(LC_ALL=C awk 'END { print NR+0 }' "$_f" 2>/dev/null) || _tl=""
    _mk=$(mb_first_marker "$_f" 2>/dev/null) || _mk=""
    if ! mb_marker_ok "$_tl" || [ "$_tl" -eq 0 ]; then
      echo "conformance-mass-budget: FAIL -- $_bn cannot be MEASURED: its line count came back as [$(printf '%s' "$_tl" | mb_san)], which is not a positive integer. A zero-line or uncountable conformance file is a broken counter, not free mass."
      _srbad=1; continue
    fi
    if ! mb_marker_ok "$_mk" || [ "$_mk" -gt "$_tl" ]; then
      echo "conformance-mass-budget: FAIL -- $_bn cannot be MEASURED: the selftest-boundary result came back as [$(printf '%s' "$_mk" | mb_san)] against $_tl line(s). The boundary is graded BEFORE it reaches any arithmetic, so a bad result is a printed FAIL rather than a shell abort with no verdict."
      _srbad=1; continue
    fi
    if [ "$_mk" -gt 0 ]; then _lg=$((_mk - 1)); else _lg=$_tl; fi
    printf '%s %s %s %s %s\n' "$_tl" "$_mk" "$_lg" "$((_tl - _lg))" "$_bn"
  done
  return "$_srbad"
}

# mb_identity_check <logic> <fixture> <total>: the RUNTIME IDENTITY. The split is only an accounting
# of the SAME mass, so logic + fixture must equal what the independent whole-file counter says. This
# was a design-time cross-check promoted to a per-run invariant (A1/C2iii) because it turns every
# measurement fault — including a GENESIS measured with a broken script — into a FAIL for free,
# instead of a plausible-looking number nobody can distinguish from the truth.
mb_identity_check() {
  [ "$(( $1 + $2 ))" -eq "$3" ] && return 0
  echo "conformance-mass-budget: FAIL -- SPLIT IDENTITY broken: logic $1 + fixture $2 = $(( $1 + $2 )), but the independent line counter says $3. The split re-prices existing mass, it never invents or loses any; a mismatch means the measurement is wrong and NO ceiling verdict below it can be trusted."
  return 1
}

# mb_count_data <root> <ext>: total lines across the NON-RECURSIVE <root>/conformance/*.<ext> glob —
# the same scope ceiling as the .sh glob, deliberately (A1/C7a: the visibility line must not re-open
# the subdirectory ambiguity the SCOPE CEILING closes). Report-only; never budgeted.
mb_count_data() {
  for _df in "$1"/conformance/*."$2"; do
    if [ -f "$_df" ]; then printf '%s\n' "$_df"; fi
  done | LC_ALL=C awk '{ n=0; while ((getline _l < $0) > 0) n++; close($0); t += n } END { print t+0 }'
}

# mb_count_census <root>: the `^check control ` row count of <root>/conformance/verify.sh.
mb_count_census() {
  _v="$1/conformance/verify.sh"
  [ -f "$_v" ] || { echo 0; return 0; }
  _n=$(LC_ALL=C grep -c '^check control ' "$_v" 2>/dev/null) || _n=0
  printf '%s\n' "$_n"
}

# mb_count_checks <root>: the `^check ` row count — the WIDER population, printed for disclosure and
# deliberately NOT budgeted. It exists so nobody reads the census above as the kit's check count.
mb_count_checks() {
  _v="$1/conformance/verify.sh"
  [ -f "$_v" ] || { echo 0; return 0; }
  _n=$(LC_ALL=C grep -c '^check ' "$_v" 2>/dev/null) || _n=0
  printf '%s\n' "$_n"
}

# mb_san: strip control bytes from ledger-supplied text on its way to stdout. An ack REASON is
# unratified prose that reaches a CI summary a human reads, so an ANSI escape in it could erase the
# line and impersonate this check's own verdict. Compared RAW, printed SANITIZED — the same
# discipline as conformance/agents-brief.sh's ec_san, and for the same reason.
mb_san() { LC_ALL=C tr -d '[:cntrl:]'; }

# mb_delta_ok <token>: 0 iff <token> is a well-formed ack delta — explicitly signed, non-zero, and
# with NO LEADING ZEROS. THE SINGLE SOURCE for this grammar, and it is single deliberately: the rule
# was duplicated verbatim at the two call sites below and that duplication is exactly what shipped
# the octal defect (a comment was the only thing coupling them). Both the grammar GATE and the guard
# in front of the `$((...))` that consumes the number now ask the same function.
#
# WHY NO LEADING ZEROS — arithmetic safety, not tidiness, and measured rather than hypothetical:
# shell arithmetic reads a leading-zero token as OCTAL, so `+010` contributed 8 and silently laundered
# a written +10 raise into a GREEN run; under dash `+09` is an "Illegal number" that ABORTS the shell
# with rc 2 (read by the harness as UNVERIFIED) after the grammar had already blessed the line, so the
# gate printed no verdict at all. `[1-9][0-9]*` also makes zero inexpressible, which is how the
# non-zero rule is enforced — there is no separate +0/-0 arm to keep in step.
mb_delta_ok() { printf '%s' "$1" | LC_ALL=C grep -qE '^[+-][1-9][0-9]*$'; }

# mb_ledger_check <ledger>: grade the GRAMMAR of every data line. Prints a FAIL line NAMING each
# offending line; returns 1 if any line is ungrammatical. A line that fails here is never an
# acknowledgment — and the raise it was meant to cover therefore reds too (fail-closed by
# construction: a typo must never silently launder growth).
mb_ledger_check() {
  _led=$1; _lbad=0; _no=0; _seen=""
  while IFS= read -r _ln || [ -n "$_ln" ]; do
    _no=$((_no + 1))
    case "$_ln" in ''|\#*) continue ;; esac
    # EXACT DUPLICATE. One ruling recorded twice reads to a human as ONE acknowledgment, but arithmetic
    # would consume it twice — so a byte-identical repeat is MALFORMED and named. The grammar has to
    # say what the ledger MEANS: two genuinely separate movements differ in at least their reason.
    if [ -n "$_seen" ] && printf '%s\n' "$_seen" | LC_ALL=C grep -Fxq -- "$_ln"; then
      echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no is an EXACT DUPLICATE of an earlier line and is NEVER a second acknowledgment: [$(printf '%s' "$_ln" | mb_san)]. One ruling recorded twice reads as one ack to a human but would be summed twice; if these are two genuinely separate movements, give them distinct reasons."
      _lbad=1; continue
    fi
    _seen=$(printf '%s\n%s' "$_seen" "$_ln")
    _nt=$(printf '%s' "$_ln" | LC_ALL=C tr -dc "$TAB" | LC_ALL=C wc -c | tr -d ' ')
    if [ "$_nt" -ne 3 ]; then
      echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no is MALFORMED: $((_nt + 1)) tab-separated field(s), expected exactly 4 (<date> <surface> <delta> <reason>). A malformed line is NEVER an acknowledgment: [$(printf '%s' "$_ln" | mb_san)]"
      _lbad=1; continue
    fi
    _d=${_ln%%"$TAB"*}; _r1=${_ln#*"$TAB"}
    _s=${_r1%%"$TAB"*}; _r2=${_r1#*"$TAB"}
    _dl=${_r2%%"$TAB"*}; _rs=${_r2#*"$TAB"}
    if ! printf '%s' "$_d" | LC_ALL=C grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no has a non-ISO-8601 date field [$(printf '%s' "$_d" | mb_san)] (want YYYY-MM-DD)."
      _lbad=1; continue
    fi
    case "$_s" in
      # `lines` STAYS GRAMMATICAL FOREVER (A1/C4) even though the surface is RETIRED. Rejecting it
      # here would red all ten historical rows and take the WHOLE ledger dark — files and census
      # verification with it. Retirement is enforced by the row-count pin in mb_verdict instead, which
      # is also the only thing that can see a zero-sum +N/-N forgery the arithmetic passes.
      lines|logic|fixture|files|census|rows|cells|legs|jobs) : ;;
      *) echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no names an unknown surface [$(printf '%s' "$_s" | mb_san)] (want one of: logic fixture files census rows cells legs jobs; \`lines\` is RETIRED but stays grammatical for its history)."
         _lbad=1; continue ;;
    esac
    if ! mb_delta_ok "$_dl"; then
      echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no has a malformed delta [$(printf '%s' "$_dl" | mb_san)]. Want an explicitly signed, non-zero integer with NO leading zeros (e.g. +180 or -97): a leading zero is read as octal by shell arithmetic and would silently change the number this ledger says."
      _lbad=1; continue
    fi
    if [ -z "$(printf '%s' "$_rs" | LC_ALL=C tr -d '[:space:]')" ]; then
      echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no is reasonless: the fourth field is empty. An unreasoned acknowledgment is a silent widening, which is the exact defect this ledger exists to make visible."
      _lbad=1; continue
    fi
  done < "$_led"
  return "$_lbad"
}

# mb_ledger_sum <ledger> <surface>: the arithmetic sum of the deltas scoped to <surface>. Assumes the
# grammar already passed (mb_ledger_check runs first); ungrammatical lines are skipped here so a
# malformed line can never contribute a number.
mb_ledger_sum() {
  _led=$1; _want=$2; _sum=0; _sseen=""
  while IFS= read -r _ln || [ -n "$_ln" ]; do
    case "$_ln" in ''|\#*) continue ;; esac
    # Skip an exact duplicate for the same reason mb_ledger_check reds it: it is one acknowledgment.
    if [ -n "$_sseen" ] && printf '%s\n' "$_sseen" | LC_ALL=C grep -Fxq -- "$_ln"; then continue; fi
    _sseen=$(printf '%s\n%s' "$_sseen" "$_ln")
    _nt=$(printf '%s' "$_ln" | LC_ALL=C tr -dc "$TAB" | LC_ALL=C wc -c | tr -d ' ')
    [ "$_nt" -eq 3 ] || continue
    _r1=${_ln#*"$TAB"}; _s=${_r1%%"$TAB"*}; _r2=${_r1#*"$TAB"}; _dl=${_r2%%"$TAB"*}
    [ "$_s" = "$_want" ] || continue
    # The guard that keeps an octal or non-numeric token out of the $((...)) below. Same function as
    # mb_ledger_check's grammar arm — one definition, so the two can no longer drift apart.
    mb_delta_ok "$_dl" || continue
    _sum=$((_sum + _dl))
  done < "$_led"
  printf '%s\n' "$_sum"
}

# mb_ledger_rows <ledger> <surface>: one "<date> <surface> <delta> <reason>" line per scoped ack,
# SANITIZED for printing. This is what makes an amnesty impossible to grant silently.
mb_ledger_rows() {
  _led=$1; _want=$2
  while IFS= read -r _ln || [ -n "$_ln" ]; do
    case "$_ln" in ''|\#*) continue ;; esac
    _nt=$(printf '%s' "$_ln" | LC_ALL=C tr -dc "$TAB" | LC_ALL=C wc -c | tr -d ' ')
    [ "$_nt" -eq 3 ] || continue
    _d=${_ln%%"$TAB"*}; _r1=${_ln#*"$TAB"}
    _s=${_r1%%"$TAB"*}; _r2=${_r1#*"$TAB"}
    _dl=${_r2%%"$TAB"*}; _rs=${_r2#*"$TAB"}
    [ "$_s" = "$_want" ] || continue
    printf '%s %s %s %s' "$_d" "$_s" "$_dl" "$_rs" | mb_san
    printf '\n'
  done < "$_led"
}

# ── mb_invariant IS RETIRED (MASS-CEILING-ADDITIVE, 2026-09-04). It graded `MAX_x == GENESIS_x + Σ`
# in both directions; with the MAX_x literals deleted the ceiling IS that sum, so neither of its two
# states — a pre-emptive ack, an unacked raise — can be constructed any more. Its printed remedy was
# the line an operator pasted into the ledger, and that remedy now lives in mb_surface alone (which
# says "append ONE ack line", because there is no constant left to raise). What replaces the
# invariant as a TEETH-bearing check is mb_no_literal_max below.

# mb_no_literal_max <script-path>: THE SOURCE LOCK. Reds, NAMING the line, if this script (or any
# script handed to it) carries a `MAX_<surface>=<digits>` assignment again. Deleting a cache is only
# durable if putting it back is a FAIL: without this, the next slice that wants a constant beside the
# ledger simply writes one, and the two can disagree again.
# ⚠️ HONEST CEILING: this is a regex over TEXT, so its catch set is exactly the DIRECT literal forms —
# bare (`MAX_LOGIC=33500`), quoted (`MAX_LOGIC="33500"`, `'33500'`), signed (`=+33500`, `=-1`), and any
# of those behind a `readonly`/`export`/`declare`/`local`/`typeset` prefix (one alternation branch;
# leg d-i fixtures the bare, both quoted, signed, `readonly`, `export`, `local` and `typeset` forms).
# It is EVADED by an arithmetic or indirect
# assignment — `MAX_LOGIC=$((33500))`, `=$VAR`, `=$(cat …)`, `${X:=…}`. That evasion is inert rather
# than merely undetected: no code path in this script reads `$MAX_LINES`/`$MAX_FILES`/`$MAX_CENSUS`/
# `$MAX_LOGIC`/`$MAX_FIXTURE` any more, so an assignment in any form changes no verdict; the lock's job
# is to stop a CACHE re-appearing beside the ledger and drifting from it. The second detector is the
# derivation mb_provenance prints on every run, which an evaded literal would contradict on screen.
mb_no_literal_max() {
  _nlm=$1; _nbad=0
  if [ ! -r "$_nlm" ]; then
    echo "conformance-mass-budget: FAIL -- the source lock cannot read [$(printf '%s' "$_nlm" | mb_san)]. An unreadable subject is a printed FAIL, never a silent pass: a lock that cannot see its subject has no teeth."
    return 1
  fi
  _nhits=$(LC_ALL=C grep -nE '^[[:space:]]*(readonly[[:space:]]+|export[[:space:]]+|local[[:space:]]+|typeset[[:space:]]+|declare[[:space:]]+-?[a-z]*[[:space:]]+)?MAX_(LINES|FILES|CENSUS|LOGIC|FIXTURE|ROWS|CELLS|LEGS|JOBS)=[[:space:]]*["'"'"']?[+-]?[0-9]' "$_nlm" || :)
  if [ -n "$_nhits" ]; then
    printf '%s\n' "$_nhits" | while IFS= read -r _nh; do
      echo "conformance-mass-budget: FAIL -- a MAX_ LITERAL IS BACK in $(printf '%s' "${_nlm##*/}" | mb_san), at line $(printf '%s' "$_nh" | mb_san). The ceiling is DERIVED from conformance/mass-acks.txt on every run (GENESIS + the scoped deltas); a constant beside it is a cache that two branches in flight both have to edit, which is the defect MASS-CEILING-ADDITIVE removed. Delete the line and append an ack instead."
    done
    _nbad=1
  fi
  return "$_nbad"
}

# mb_union_attr_ok <root>: the ledger must carry `merge=union` in <root>/.gitattributes. KIT-SELF, and
# it lives HERE rather than in adopter-export-wired.sh (which also reads .gitattributes) because that
# check's subject is the EXPORT CARVE and it runs on adopter trees, where this attribute is none of
# its business. Why it is a gate at all: the ledger is now the only place a ceiling lives, so two
# ratified branches that each append an ack must MERGE, not conflict — without the attribute the
# second to land re-writes the ceiling by hand, which is exactly what this slice removed from the
# script. Union merge cures APPEND conflicts only; two branches editing the SAME row still conflict,
# and should. On two branches appending the BYTE-IDENTICAL line, git resolves the identical change
# once before any merge driver runs, so the line lands once and the ceiling rises once (measured, leg
# d-v); mb_ledger_check's exact-duplicate arm is the detector for a duplicate arriving any other way.
# ⚠️ WHAT IS GRADED IS THE EFFECTIVE ATTRIBUTE, not a line. gitattributes is last-match-wins AND
# pattern-matched, so the value git actually applies is the only honest subject: when git is on PATH
# and <root> is a work tree this asks `git check-attr merge -- conformance/mass-acks.txt` and requires
# the value `union`. The awk below is the FALLBACK for a non-git tree only, and it is BLIND to a GLOB
# row: it keys on `$1 == the path`, so a later `conformance/* -merge` (which never names the ledger)
# leaves it green while the effective attribute is `unset`. Measured, and pinned by leg d-iv's glob arm.
mb_union_attr_ok() {
  _ua="$1/.gitattributes"; _uv=
  if [ -n "$(command -v git 2>/dev/null || :)" ] && git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _uv=$(git -C "$1" check-attr merge -- conformance/mass-acks.txt 2>/dev/null | sed 's/^.*: //')
    [ "$_uv" = union ] && return 0
  elif [ -f "$_ua" ] && LC_ALL=C awk '$1 == "conformance/mass-acks.txt" { if (/merge=union/) f = 1; else if (/(^|[[:space:]])-merge/ || /merge=/) f = 0 } END { exit f ? 0 : 1 }' "$_ua"; then
    return 0
  fi
  echo "conformance-mass-budget: FAIL -- the effective merge attribute of conformance/mass-acks.txt is [${_uv:-not union}], not \`union\` (it is set in .gitattributes). The ledger is the ONLY place a ceiling lives now, so two ratified branches that each APPEND an ack must merge rather than conflict; without the attribute the second one to land rewrites the ceiling by hand. Add the line \`conformance/mass-acks.txt merge=union\` (never at line 1, which is the export-carve anchor). If a union line IS present, check for a LATER line for the same path that OVERRIDES it -- gitattributes is last-match-wins and PATTERN-matched, so a subsequent \`-merge\`/\`merge=<other>\` row, or a GLOB row such as \`conformance/* -merge\` that matches the path WITHOUT naming it, turns union off."
  return 1
}

# mb_provenance <LABEL> <genesis> <max> <ledger> <surface> <sum>: disclose where this ceiling CAME
# FROM. Since MASS-CEILING-ADDITIVE the ceiling is not written down anywhere, so this line PRINTS THE
# ARITHMETIC — genesis, the signed sum, the number of acks and the last date — and then every consumed
# ack BY NAME. A reader must be able to re-add the number from the line itself; a bare ceiling would be
# a constant again, just one whose source nobody can see. Called on green and on red alike.
mb_provenance() {
  _lab=$1; _gen=$2; _mx=$3; _led=$4; _surf=$5; _psum=$6
  _rows=$(mb_ledger_rows "$_led" "$_surf")
  _k=0; _last=none
  if [ -n "$_rows" ]; then
    _k=$(printf '%s\n' "$_rows" | grep -c '')
    _last=$(printf '%s\n' "$_rows" | cut -d' ' -f1 | sort | tail -1)
  fi
  case "$_psum" in -*) _psgn=$_psum ;; *) _psgn="+$_psum" ;; esac
  echo "conformance-mass-budget: MAX_$_lab=$_mx = genesis $_gen + ($_psgn) over $_k ack(s), last $_last"
  if [ -n "$_rows" ]; then
    printf '%s\n' "$_rows" | while IFS= read -r _row; do
      echo "conformance-mass-budget:   ack consumed -- $_row"
    done
  fi
}

# mb_pct <measured> <max>: headroom as a one-decimal percentage of MAX ("n/a" when MAX is 0).
mb_pct() {
  [ "$2" -gt 0 ] || { printf 'n/a\n'; return 0; }
  _t=$(( ($2 - $1) * 1000 / $2 ))
  printf '%s.%s%%\n' "$((_t / 10))" "$((_t % 10))"
}

# mb_surface <label> <measured> <max> <unit>: print the per-surface verdict; return 1 when over budget.
# The green line leads with the ABSOLUTE residual and only then the percentage. That ordering is
# load-bearing: against a five-figure line budget a real 35-line margin renders as "0.0%", which is
# byte-identical to what the deliberately-exact files and census surfaces print — so the percentage
# alone made the one surface that HAS headroom look like the two that have none by design, flatly
# contradicting this file's own header. The residual is the number a reader can act on.
mb_surface() {
  _lab=$1; _m=$2; _mx=$3; _unit=$4; _sbad=0
  if [ "$_m" -gt "$_mx" ]; then
    # ⚠️ THE PRINTED REMEDY MUST ITSELF BE GRAMMATICAL, and this is now the ONLY place the gate prints
    # one (mb_invariant, which used to print the other, is retired with the MAX_ literals). The
    # inherited defect is worth restating because it cost a red to fix a red: the surface token must be
    # LOWERCASE (the allowlist rejects `LOGIC`) and the delta must be EXPLICITLY SIGNED (mb_delta_ok
    # rejects an unsigned one). `_m > _mx` holds in this branch, so the `+` is always right. leg xxvi
    # round-trips this exact string back through mb_ledger_check so prose and grammar cannot drift.
    echo "conformance-mass-budget: FAIL -- $_lab $_m/$_mx, over by $((_m - _mx)) $_unit(s). TWO CURES, both deliberate: extend an existing check instead of adding one, or append ONE ack line (<date>${TAB}${_lab}${TAB}+$((_m - _mx))${TAB}<reason>) to conformance/mass-acks.txt in THIS diff. There is NO constant to raise: the ceiling IS this ledger (genesis + the scoped deltas), so one appended line is the whole act."
    _sbad=1
    return "$_sbad"
  fi
  echo "conformance-mass-budget: $_lab $_m/$_mx ($((_mx - _m)) $_unit(s) free · $(mb_pct "$_m" "$_mx") headroom)"
  return "$_sbad"
}

# mb_sdelta <now> <then>: the signed difference, explicitly signed (+0 for none). Callers grade both
# operands with mb_marker_ok first.
mb_sdelta() {
  _sd=$(($1 - $2))
  if [ "$_sd" -lt 0 ]; then printf '%s\n' "$_sd"; else printf '+%s\n' "$_sd"; fi
}

# mb_unbudgeted <root>: GUARD-ADAPTER-MASS-REPORT (SWAS-147). An ADVISORY report of the growth of the
# surfaces this budget does not count (scripts/ and .claude/hooks/) since the last RECORDED release,
# read from conformance/mass-release-baseline.txt (one TAB line per release, fixed grammar, parsed and
# never sourced). mb_verdict calls it as `( mb_unbudgeted "$_root" ) || :` AFTER its verdict line, so
# nothing in here can reach the gate's rc: not set -e, not an exit, not dash's fatal arithmetic abort.
# Every baseline number is graded with mb_marker_ok before arithmetic; every error path is one N/A line.
mb_unbudgeted() {
  _ur=$1; _ubp="$_ur/conformance/mass-release-baseline.txt"
  _uhd="conformance-mass-budget: unbudgeted surfaces (ADVISORY ONLY — never changes the verdict)"
  if [ ! -r "$_ubp" ]; then echo "$_uhd: N/A (conformance/mass-release-baseline.txt is missing or unreadable)"; return 0; fi
  _ul=$(LC_ALL=C grep -v '^[[:space:]]*#' "$_ubp" | LC_ALL=C grep -v '^[[:space:]]*$' | tail -1) || _ul=""
  if [ -z "$_ul" ]; then echo "$_uhd: N/A (the baseline file has no data line)"; return 0; fi
  _unt=$(printf '%s' "$_ul" | LC_ALL=C tr -dc "$TAB" | LC_ALL=C wc -c | tr -d ' ')
  if [ "$_unt" != 9 ]; then echo "$_uhd: N/A (malformed baseline line: want 10 TAB-separated fields, tag date scripts fixtures hooks + 5 path:size)"; return 0; fi
  IFS=$TAB read -r _utag _udate _ubs _ubf _ubh _ut1 _ut2 _ut3 _ut4 _ut5 <<EOF
$_ul
EOF
  _uok=1
  printf '%s' "$_utag" | LC_ALL=C grep -qE '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || _uok=0
  printf '%s' "$_udate" | LC_ALL=C grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || _uok=0
  for _ux in "$_ubs" "$_ubf" "$_ubh"; do
    mb_marker_ok "$_ux" || _uok=0
    [ "${#_ux}" -le 9 ] || _uok=0   # 9-digit cap: an absurd value must not overflow mb_sdelta
  done
  for _ux in "$_ut1" "$_ut2" "$_ut3" "$_ut4" "$_ut5"; do
    printf '%s' "${_ux%:*}" | LC_ALL=C grep -qE '^[A-Za-z0-9._/-]+$' || _uok=0
    case "$_ux" in *:*) mb_marker_ok "${_ux##*:}" || _uok=0 ;; *) _uok=0 ;; esac
    _usz=${_ux##*:}
    [ "${#_usz}" -le 9 ] || _uok=0
  done
  if [ "$_uok" -ne 1 ]; then echo "$_uhd: N/A (malformed baseline line: a field failed its grammar)"; return 0; fi
  if [ ! -d "$_ur/scripts" ] || [ ! -d "$_ur/.claude/hooks" ]; then echo "$_uhd: N/A (scripts/ or .claude/hooks/ is not a readable directory)"; return 0; fi
  # Measure: TEXT files only (grep -I drops binaries). find without -H skips a symlinked hooks dir, and odd-named files are skipped (both under-report, never fail).
  _urows=$(find "$_ur/scripts" "$_ur/.claude/hooks" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r _uf; do
    _urel=${_uf#"$_ur"/}
    printf '%s' "$_urel" | LC_ALL=C grep -qE '^[A-Za-z0-9._/-]+$' || continue
    LC_ALL=C grep -Iq '' "$_uf" 2>/dev/null || continue
    _un=$(LC_ALL=C awk 'END { print NR+0 }' "$_uf" 2>/dev/null) || continue
    mb_marker_ok "$_un" || continue
    printf '%s %s\n' "$_un" "$_urel"
  done) || _urows=""
  _utot=$(printf '%s\n' "$_urows" | LC_ALL=C awk 'NF == 2 { if ($2 ~ /^scripts\/fixtures\//) f += $1; else if ($2 ~ /^scripts\//) s += $1; else h += $1 } END { print s+0, f+0, h+0 }')
  read -r _ums _umf _umh <<EOF
$_utot
EOF
  for _ux in "$_ums" "$_umf" "$_umh"; do
    mb_marker_ok "$_ux" || { echo "$_uhd: N/A (the measurement came back ungradeable)"; return 0; }
  done
  _utop=$(printf '%s\n' "$_urows" | LC_ALL=C awk 'NF == 2 && $2 !~ /^scripts\/fixtures\//' | LC_ALL=C sort -k1,1nr -k2,2 | head -5)
  _utl=$(printf '%s\n' "$_utop" | while read -r _un _up; do
    [ -n "$_up" ] || continue
    _uthen=""
    for _ux in "$_ut1" "$_ut2" "$_ut3" "$_ut4" "$_ut5"; do
      if [ "${_ux%:*}" = "$_up" ]; then _uthen=${_ux##*:}; fi
    done
    if [ -n "$_uthen" ]; then echo "$_up $_un ($(mb_sdelta "$_un" "$_uthen"))"; else echo "$_up $_un (not in the baseline's top 5)"; fi
  done | LC_ALL=C awk '{ printf "%s%s", (NR > 1 ? " · " : ""), $0 } END { print "" }')
  echo "$_uhd, since $_utag (baseline recorded $_udate):"
  echo "conformance-mass-budget:   scripts/ $_ums line(s) ($(mb_sdelta "$_ums" "$_ubs"))   scripts/fixtures/ $_umf line(s) ($(mb_sdelta "$_umf" "$_ubf"))   .claude/hooks/ $_umh line(s) ($(mb_sdelta "$_umh" "$_ubh"))   [text files only]"
  echo "conformance-mass-budget:   top files: $(printf '%s' "$_utl" | mb_san)"
  _uver=$(head -1 "$_ur/VERSION" 2>/dev/null || :)
  if printf '%s' "$_uver" | LC_ALL=C grep -qE '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then _unt="v$_uver"; else _unt="<tag>"; fi
  _und=$(date +%Y-%m-%d 2>/dev/null || :)
  printf '%s' "$_und" | LC_ALL=C grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || _und="<date>"
  _unl=$(printf '%s\n' "$_utop" | LC_ALL=C awk -v t="$_unt" -v d="$_und" -v s="$_ums" -v f="$_umf" -v h="$_umh" 'BEGIN { OFS = "\t" } NF == 2 { e[++k] = $2 ":" $1 } END { print t, d, s, f, h, e[1], e[2], e[3], e[4], e[5] }')
  echo "conformance-mass-budget:   next-baseline (the release cut appends the text after this label to conformance/mass-release-baseline.txt): $_unl"
  return 0
}

# mb_verdict <root> <lines_gen> <files_gen> <cen_gen> <logic_gen> <fixture_gen> <historical_lines_acks>
# ⚠️ SEVEN ARGUMENTS SINCE MASS-CEILING-ADDITIVE (2026-09-04), down from twelve: the five <max>
# parameters are GONE because there is no ceiling to pass in. Each one is DERIVED below as
# GENESIS + mb_ledger_sum, after mb_ledger_check has graded the grammar — so a caller can no longer
# assert a ceiling the ledger does not support, which is what the retired mb_invariant existed to
# catch. `lines_gen` is still passed so the retired surface's history keeps being read out and
# row-count-pinned; nothing is MEASURED against it any more.
mb_verdict() {
  _root=$1; _lgen=$2; _fgen=$3; _cgen=$4; _ggen=$5; _xgen=$6; _lpin=$7; _cigen=${8:-}
  _bad=0

  # ── ARMING FIRST, before any enumeration (vet A1.3). An adopter tree carries neither kit marker;
  # it must never reach the fail-closed refusal below, which is about the KIT's own conformance dir.
  if [ ! -f "$_root/docs/ROADMAP-KIT.md" ] && [ ! -f "$_root/.github/workflows/golden-path.yml" ]; then
    echo "N/A: conformance-mass-budget -- no kit marker present (an adopter tree). This budget ratchets the KIT's own conformance/ mass; an adopter's checks are the adopter's business. Nothing to grade, no remedy to offer; this is not a pass."
    return "$_bad"
  fi

  # ── THE UNION-MERGE LOCK, kit-self and inside the armed path for exactly that reason: the attribute
  # protects the KIT's ledger, and an adopter tree neither has one nor should be held to it.
  mb_union_attr_ok "$_root" || _bad=1

  _lines=$(mb_count_lines "$_root")
  _files=$(mb_count_files "$_root")
  _cen=$(mb_count_census "$_root")

  # ── FAIL-CLOSED. On an ARMED tree an empty enumeration means the counter, not the tree, is broken.
  if [ "$_files" -eq 0 ] || [ "$_lines" -eq 0 ]; then
    echo "conformance-mass-budget: FAIL -- the enumeration of conformance/*.sh is EMPTY on a KIT-MARKED tree ($_files file(s), $_lines line(s)). A zero-mass reading is a broken counter, never a budget that everything fits inside."
    _bad=1
    return "$_bad"
  fi
  # ── THE LEDGER. On an armed tree its absence is a DEAD INPUT, not a free pass: MAX is defined as a
  # function of it, so a missing ledger makes every constant unverifiable.
  _led="$_root/conformance/mass-acks.txt"
  if [ ! -f "$_led" ]; then
    echo "conformance-mass-budget: FAIL -- conformance/mass-acks.txt is absent on a KIT-MARKED tree. Every MAX is defined as GENESIS + the sum of that file's scoped deltas, so without it no ceiling can be verified. This is a FAILURE, never an N/A."
    _bad=1
    return "$_bad"
  fi
  mb_ledger_check "$_led" || _bad=1

  # ── THE DERIVATION, per surface, BEFORE the measurement compare. The ceiling is not asserted
  # anywhere and is not passed in: it is computed here, from a ledger whose GRAMMAR has just been
  # graded (an ungrammatical line contributes nothing, so a typo can never launder growth). This is
  # what replaced the old two-directional invariant — the two states it graded are unconstructible
  # once there is no second number to disagree with the sum.
  _lsum=$(mb_ledger_sum "$_led" lines)
  _fsum=$(mb_ledger_sum "$_led" files)
  _csum=$(mb_ledger_sum "$_led" census)
  _gsum=$(mb_ledger_sum "$_led" logic)
  _xsum=$(mb_ledger_sum "$_led" fixture)
  _lmax=$((_lgen + _lsum))
  _fmax=$((_fgen + _fsum))
  _cmax=$((_cgen + _csum))
  _gmax=$((_ggen + _gsum))
  _xmax=$((_xgen + _xsum))

  # ── THE RETIREMENT PIN (A1/C3). `lines` is retired, so its ledger population is CLOSED: exactly the
  # historical rows, forever. A count pin rather than a date, because the date field is author-supplied
  # and trivially backdated — and rather than arithmetic, because a ZERO-SUM PAIR (+N and -N with
  # distinct reasons) leaves MAX_LINES == GENESIS_LINES + Σ untouched while forging two rulings into
  # the provenance narrative a ratifier reads. Only counting the rows sees that.
  _lrows=$(mb_ledger_rows "$_led" lines)
  _lcnt=0
  if [ -n "$_lrows" ]; then _lcnt=$(printf '%s\n' "$_lrows" | grep -c ''); fi
  if [ "$_lcnt" -ne "$_lpin" ]; then
    echo "conformance-mass-budget: FAIL -- the \`lines\` surface is RETIRED (2026-08-31, MASS-BUDGET-LOGIC-FIXTURE-SPLIT): its ledger population is CLOSED at $_lpin historical row(s), but mass-acks.txt carries $_lcnt. Mass is now acknowledged as \`logic\` or \`fixture\`; a new \`lines\` row acknowledges a surface nothing is measured against, and a +N/-N PAIR of them would pass the arithmetic while inventing rulings in the provenance output above. If a historical row genuinely must change, HISTORICAL_LINES_ACKS moves with it, in the same ratified diff."
    _bad=1
  fi

  # ── THE SPLIT. Measured per file, fail-closed: any file that cannot be measured is a printed FAIL
  # and its numbers never enter the sums (see mb_split_rows).
  _srrc=0
  _srows=$(mb_split_rows "$_root") || _srrc=1
  [ "$_srrc" -eq 0 ] || _bad=1
  _srfail=$(printf '%s\n' "$_srows" | grep '^conformance-mass-budget:' || :)
  _srdata=$(printf '%s\n' "$_srows" | grep -E '^[0-9]' || :)
  if [ -n "$_srfail" ]; then printf '%s\n' "$_srfail"; fi
  _logic=0; _fixt=0
  if [ -n "$_srdata" ]; then
    _logic=$(printf '%s\n' "$_srdata" | LC_ALL=C awk '{ t += $3 } END { print t+0 }')
    _fixt=$(printf '%s\n' "$_srdata" | LC_ALL=C awk '{ t += $4 } END { print t+0 }')
  fi
  # The identity is only meaningful when EVERY file was measured; with a file rejected above, the
  # whole-tree counter legitimately exceeds the sums and a second red would say nothing new. THE GATE
  # KEYS ON mb_split_rows' RETURN CODE, NOT on grepping its text (security vet F-2): a row that merely
  # LOOKED like a FAIL line would otherwise suppress the identity check — the strongest catch-all here.
  if [ "$_srrc" -eq 0 ]; then
    mb_identity_check "$_logic" "$_fixt" "$_lines" || _bad=1
  fi

  mb_surface logic   "$_logic" "$_gmax" line || _bad=1
  mb_surface fixture "$_fixt"  "$_xmax" line || _bad=1
  mb_surface files   "$_files" "$_fmax" file || _bad=1
  mb_surface census  "$_cen"   "$_cmax" row  || _bad=1

  # ── SWAS-281: the four CI-time counts (rows, cells, legs, jobs), only when the caller passed their four genesis values as the 8th
  # argument. run() always does (leg ci-run locks that); the older selftest legs call this function with seven arguments and are not about
  # these surfaces. The genesis lock follows: on a pull_request a moved GENESIS_ line reds.
  if [ -n "$_cigen" ]; then
    # shellcheck disable=SC2086  # the four numbers are deliberately word-split into four arguments
    mb_ci_surfaces "$_root" "$_led" $_cigen || _bad=1
    mb_genesis_lock "$_root" || _bad=1
  fi

  # ── COMPOSITION (A1/C1). The sweep does NOT police the marker boundary, so a marker move that
  # reprices several hundred lines from logic to fixture has to be READABLE — in this summary, by the
  # same person who ratifies the ack. Report-only; no verdict.
  if [ -n "$_srdata" ]; then
    echo "conformance-mass-budget: composition -- the 5 most fixture-heavy files (fixture/total lines, marker at line):"
    printf '%s\n' "$_srdata" | LC_ALL=C sort -k4,4nr -k5,5 | head -5 | while read -r _t _m _l _x _n; do
      echo "conformance-mass-budget:   $(printf '%s' "$_n" | mb_san) -- $_x/$_t fixture, marker at line $_m"
    done
  fi

  # ── DATA VISIBILITY (A1/C7a). NOT budgeted, and deliberately so: pricing data rows would tax the
  # .tsv extension path the kit made cheap on purpose. But it is also an unwatched .sh -> .tsv
  # migration channel, so the number is printed and the reviewer's honesty job extends to watching it.
  echo "conformance-mass-budget: data (UNCOUNTED, and NON-RECURSIVE conformance/ only — the same scope ceiling as the .sh glob): tsv $(mb_count_data "$_root" tsv) line(s) · txt $(mb_count_data "$_root" txt) line(s). Moving check rows into a data file is a legitimate cheap extension AND an invisible one; this line is the only place it shows."

  # ── THE GLIDE TARGET. Advisory, never a verdict (A1/C7b).
  if [ -z "${LOGIC_GLIDE_TARGET:-}" ]; then
    echo "conformance-mass-budget: glide target: not set (owner's). The logic ceiling ratchets but never cuts on its own; setting a target here is the owner's act, and it would still print advice rather than a verdict."
  elif mb_marker_ok "${LOGIC_GLIDE_TARGET}"; then
    echo "conformance-mass-budget: glide target: ${LOGIC_GLIDE_TARGET} logic line(s); $_logic today, distance $((_logic - LOGIC_GLIDE_TARGET)). ADVISORY ONLY — this line never changes the verdict."
  else
    echo "conformance-mass-budget: FAIL -- LOGIC_GLIDE_TARGET is set to [$(printf '%s' "${LOGIC_GLIDE_TARGET}" | mb_san)], which is not a non-negative integer. An ungradeable target is a printed FAIL, never silently ignored."
    _bad=1
  fi

  echo "conformance-mass-budget: census note -- $_cen \`^check control \` row(s) budgeted; $(mb_count_checks "$_root") \`^check \` row(s) total in verify.sh. These are DIFFERENT populations and this gate budgets the former: the census is THIS GATE'S OWN measure, not the kit's reconciled check count (the reconciliation-of-record is verify.sh's own \`Scripts:\` line, printed beside its Summary: rows, unique scripts, files on disk, files no row invokes). A TOP-LEVEL check wired only in ci.yml is invisible here but visible to the logic, fixture and files surfaces; one living in a conformance/ subdirectory is invisible to all of them."

  # ── PROVENANCE + the consumed acks BY NAME. A green must never leave an amnesty unread. LINES is
  # printed last and flagged RETIRED: its rows are history that stays verified, not a live ceiling.
  mb_provenance LOGIC   "$_ggen" "$_gmax" "$_led" logic   "$_gsum"
  mb_provenance FIXTURE "$_xgen" "$_xmax" "$_led" fixture "$_xsum"
  mb_provenance FILES   "$_fgen" "$_fmax" "$_led" files   "$_fsum"
  mb_provenance CENSUS  "$_cgen" "$_cmax" "$_led" census  "$_csum"
  echo "conformance-mass-budget: the \`lines\` ceiling is RETIRED (2026-08-31) — its genesis is frozen, its ceiling is still DERIVED from its $_lpin closed historical row(s), and it is measured against nothing. The rows below are history:"
  mb_provenance LINES   "$_lgen" "$_lmax" "$_led" lines   "$_lsum"

  if [ "$_bad" -eq 0 ]; then
    echo "conformance-mass-budget: OK -- kit conformance mass within its ratified ceiling. SCOPE CEILING: non-recursive conformance/*.sh only. The .md checklists, conformance/ subdirectories, scripts/, hooks/ and guard-core are OUTSIDE this budget."
  else
    echo "conformance-mass-budget: FAIL -- see above. SCOPE CEILING: non-recursive conformance/*.sh only; .md, subdirectories, scripts/, hooks/ and guard-core are outside this budget."
  fi
  # GUARD-ADAPTER-MASS-REPORT: the LAST act, a subshell, `|| :` — the advisory block cannot move the rc.
  ( mb_unbudgeted "$_root" ) || :
  return "$_bad"
}

# ══ SWAS-281 (CI-TIME-BUDGET): THE FOUR CI-TIME COUNTS ═══════════════════════════════════════════════════════════════════════════════
# Each count is a property of the TREE (no base ref, no clock, no runner), so the verdict cannot move with the runner a job landed on.
# FAIL-CLOSED throughout: a count that cannot be measured is a printed `conformance-mass-budget: FAIL --` line, NEVER 0 (a broken counter
# must not buy headroom by being broken). The printed text names the thing that broke, which may be the BATTERY or a WORKFLOW, not this gate.

# mb_count_rows <root>: the verify.sh `^check ` rows that are not `^check control ` rows (the `census` surface counts those, so the two
# partition the registry and no row is charged twice). COLUMN-0 LOCK: a `check` call indented outside the selftest region would be missed by
# the grep, so it is a FAIL naming the line, EXCEPT a marked replay (`# mb:replay <name>`, judged below, printed as seen). HONEST CEILING: a
# row added by a loop or an UNMARKED helper that CALLS `check` is not seen (a marker is something the author writes, not something the lock
# finds), and a call that does not begin its line with `check` stays invisible, as before. The match is lexical: an obfuscated spelling (for example c""heck inside $(...) or backticks, or a quote-escape trick that hides a ;) evades it on any line, column 0 included; the durable fix is counting the registry's runtime listing (boarded; design section 8).
# A marked replay is judged on kind plus name, not arguments: the lock counts rows, and a replay adds none, so a replay may pass different arguments under an existing row's name (ruled a ceiling, not closed). How many replays a row has is SHOWN on the info line, not graded.
mb_count_rows() {
  _rv="$1/conformance/verify.sh"
  if [ ! -r "$_rv" ]; then
    echo "conformance-mass-budget: FAIL -- rows cannot be MEASURED: conformance/verify.sh is missing or unreadable on a kit-marked tree. An unmeasurable surface is never priced at 0."
    return 1
  fi
  # The lock scans EVERYTHING except the `if [ "${1:-}" = "--selftest" ]` ... `fi` block (the same range verify.sh's own K1 leg strips). It used to
  # stop at mb_first_marker, which on the real file sits at line 554 while the registry rows sit at 1416-2027, so the lock was dead on the real tree.
  # MARKED REPLAYS are seen and judged, not skipped: an indented `check <kind> <name> ...  # mb:replay <name>` is accepted ONLY when the marker
  # name equals the call's own name AND exactly one column-0 `check <kind> <name> ` row exists (the replay re-runs a registry row, it adds none).
  # Any other indented check, and any replay that fails either test, is the same FAIL. The awk prints `BAD <line> <plain|marked>` or `OK` followed
  # by one `<name> <count>` line per replayed name. An UNMARKED helper that calls `check` is still the stated ceiling below.
  _rscan=$(LC_ALL=C awk '
    /^if \[ "\$\{1:-\}" = "--selftest" \]/ { skip = 1 }
    skip { if ($0 ~ /^fi$/) skip = 0; next }
    /^check[ \t]/ { split($0, cf, /[ \t]+/); twin[cf[2] " " cf[3]]++ }   # column 0: cf[1] is the word check
    /^[ \t]+check[ \t]/ {
      if (match($0, /# mb:replay [^ \t]+[ \t]*$/)) {
        mname = substr($0, RSTART + 12, RLENGTH - 12); sub(/[ \t]+$/, "", mname)
        # ONE check only: a second `check` word, or an unquoted ; | && before the marker, is a second command (an uncounted row).
        body = substr($0, 1, RSTART - 1); cw = body; nchk = gsub(/(^|[^A-Za-z0-9_.\/-])check([^A-Za-z0-9_.\/-]|$)/, "&", cw)
        gsub("\"[^\"]*\"", "", body); gsub("\047[^\047]*\047", "", body)
        multi = (nchk > 1 || body ~ /;/ || body ~ /\|/ || body ~ /&&/)
        split($0, rf, /[ \t]+/); nrep++; rl[nrep] = NR; rbad[nrep] = multi; rk[nrep] = rf[3] " " rf[4]; rn[nrep] = rf[4]; rm[nrep] = mname
      } else if (!bad || NR < bad) { bad = NR; why = "plain" }
    }
    END {
      for (i = 1; i <= nrep; i++) {
        if (rm[i] != rn[i] || rbad[i] || twin[rk[i]] != 1) { if (!bad || rl[i] < bad) { bad = rl[i]; why = "marked" } }
        else { if (!(rn[i] in seen)) { seen[rn[i]] = 1; order[++nn] = rn[i] }; cnt[rn[i]]++ }
      }
      if (bad) { print "BAD " bad " " why; exit }
      print "OK"
      for (j = 1; j <= nn; j++) print order[j] " " cnt[order[j]]
    }' "$_rv")
  case "$_rscan" in
    BAD*)
      _rind=$(printf '%s\n' "$_rscan" | awk '{ print $2 }'); _rwhy=$(printf '%s\n' "$_rscan" | awk '{ print $3 }')
      _rnote="Put the registry row at column 0, or count the registry's runtime listing."
      if [ "$_rwhy" = marked ]; then _rnote="Its mb:replay marker is honoured only when the marker name equals the call's own name and exactly one column-0 row of that kind and name exists, and the line is a single check (no second check word, no unquoted ; | &&)."; fi
      echo "conformance-mass-budget: FAIL -- rows cannot be MEASURED: conformance/verify.sh line $(printf '%s' "$_rind" | mb_san) is an INDENTED check call outside the selftest region, which the column-0 row count would not see. $_rnote"
      return 1 ;;
    OK*) ;;
    *)
      echo "conformance-mass-budget: FAIL -- rows cannot be MEASURED: the verify.sh indented-check scan returned no verdict. An unmeasurable surface is never priced at 0."
      return 1 ;;
  esac
  _rrep=$(printf '%s\n' "$_rscan" | awk 'NR > 1 { n += $2; s = s (s == "" ? "" : ", ") $1 " ×" $2 } END { if (n) print n " replay(s) seen and judged: " s }')
  if [ -n "$_rrep" ]; then echo "conformance-mass-budget: rows: $_rrep" >&2; fi
  _rall=$(LC_ALL=C grep -c '^check ' "$_rv" 2>/dev/null) || _rall=0
  _rctl=$(LC_ALL=C grep -c '^check control ' "$_rv" 2>/dev/null) || _rctl=0
  if ! mb_marker_ok "$_rall" || ! mb_marker_ok "$_rctl" || [ "$_rctl" -gt "$_rall" ]; then
    echo "conformance-mass-budget: FAIL -- rows cannot be MEASURED: the verify.sh counts came back as all=[$(printf '%s' "$_rall" | mb_san)] control=[$(printf '%s' "$_rctl" | mb_san)]."
    return 1
  fi
  printf '%s\n' "$((_rall - _rctl))"
}

# mb_count_cells <root>: the line count of `agent-autonomy.sh --list-cells`. ONE LINE PER CELL (a follower's line carries its producer as extra
# fields), and the --join builds its `listed` set from this same output, so the count has one definition and this gate parses nothing of its
# own; leg ci-b15 pins the coupling. The only sanity check is that every line holds a TAB (a stray diagnostic is not a cell).
mb_count_cells() {
  _cs="$1/conformance/agent-autonomy.sh"
  if [ ! -r "$_cs" ]; then
    echo "conformance-mass-budget: FAIL -- cells cannot be MEASURED: conformance/agent-autonomy.sh (the guard battery) is missing on a kit-marked tree."
    return 1
  fi
  _crc=0
  _cout=$( cd "$1" && sh conformance/agent-autonomy.sh --list-cells 2>/dev/null ) || _crc=$?
  if [ "$_crc" -ne 0 ] || [ -z "$_cout" ]; then
    echo "conformance-mass-budget: FAIL -- cells cannot be MEASURED: \`agent-autonomy.sh --list-cells\` (the guard battery's list mode, not this budget) exited $_crc and printed $(printf '%s' "$_cout" | LC_ALL=C awk 'END { print NR }') line(s). An unlistable battery is a FAIL, never 0 cells."
    return 1
  fi
  _cbad=$(printf '%s\n' "$_cout" | LC_ALL=C awk -F "$TAB" 'NF < 2 { print NR; exit }')
  if [ -n "$_cbad" ]; then
    echo "conformance-mass-budget: FAIL -- cells cannot be MEASURED: line $(printf '%s' "$_cbad" | mb_san) of \`agent-autonomy.sh --list-cells\` (the guard battery's list mode) holds no TAB, so it is not a cell."
    return 1
  fi
  # The DEDUPLICATED set, by the join's own pipeline (agent-autonomy.sh builds `listed` as awk '{ print $1 "\t" $2 }' | sort -u): the same
  # derivation the CI path uses (the join prints that set's size), so the two ways to get `cells` cannot disagree. Leg ci-b15 pins the text.
  printf '%s\n' "$_cout" | LC_ALL=C awk -F "$TAB" '{ print $1 "\t" $2 }' | LC_ALL=C sort -u | LC_ALL=C awk 'END { print NR }'
}

# mb_count_legs <root> <list>: the sum of each listed heavy check's `--list-legs` label count. A listed check that is missing, that does not
# answer `--list-legs`, or that prints an off-shape label is a FAIL.
mb_count_legs() {
  _lt=0
  for _lc in $2; do
    case "$_lc" in *[!A-Za-z0-9._-]*|'') echo "conformance-mass-budget: FAIL -- legs cannot be MEASURED: heavy check name [$(printf '%s' "$_lc" | mb_san)] is off-shape."; return 1 ;; esac
    if [ ! -r "$1/conformance/$_lc" ]; then echo "conformance-mass-budget: FAIL -- legs cannot be MEASURED: the listed heavy check $_lc is missing."; return 1; fi
    _lrc=0
    _lo=$( cd "$1" && sh "conformance/$_lc" --list-legs 2>/dev/null ) || _lrc=$?
    if [ "$_lrc" -ne 0 ] || [ -z "$_lo" ]; then
      echo "conformance-mass-budget: FAIL -- legs cannot be MEASURED: the listed heavy check $_lc does not answer --list-legs (exit $_lrc). A check enters the heavy list only with a --list-legs its own --selftest asserts it ran."
      return 1
    fi
    if printf '%s\n' "$_lo" | LC_ALL=C grep -qvE '^[A-Za-z0-9.-]+$'; then
      echo "conformance-mass-budget: FAIL -- legs cannot be MEASURED: $_lc --list-legs printed a label outside [A-Za-z0-9.-]+."
      return 1
    fi
    _lt=$((_lt + $(printf '%s\n' "$_lo" | LC_ALL=C awk 'END { print NR }')))
  done
  printf '%s\n' "$_lt"
}

# mb_list_legs <script>: this gate's own legs, one label per line -- the `leg <label>` of every PASS/FAIL/SKIP line the selftest can print.
mb_list_legs() {
  LC_ALL=C sed -nE -e 's/^.*(PASS|FAIL|SKIP): selftest -- leg ([A-Za-z0-9.-]+) .*$/\2/p' -e 's/^[[:space:]]*cib_(red|green) (ci-[A-Za-z0-9.-]+) .*$/\2/p' "$1" | LC_ALL=C sort -u
}

# mb_legs_crosscheck <listed-file> <ran-file>: both sorted label lists; 0 iff identical. A leg listed but never run, or run but not listed, reds.
mb_legs_crosscheck() {
  _lx=$(LC_ALL=C comm -3 "$1" "$2")
  [ -z "$_lx" ] && return 0
  echo "conformance-mass-budget: FAIL -- the selftest legs and --list-legs disagree (first difference, listed<TAB>ran: $(printf '%s' "$_lx" | head -n 1 | mb_san | tr '\t' '/')). A leg must be listed AND run."
  return 1
}

# mb_count_jobs <root>: `ci-gates.sh --count-legs`'s total (the matrix-aware count of runner jobs over every workflow with a pull_request or
# push trigger). Its refusals (expression matrix, reusable uses: job, workflow_run, an unallowlisted pull_request_target) are forwarded.
mb_count_jobs() {
  if [ ! -r "$1/conformance/ci-gates.sh" ]; then
    echo "conformance-mass-budget: FAIL -- jobs cannot be MEASURED: conformance/ci-gates.sh (the job counter) is missing on a kit-marked tree."
    return 1
  fi
  _jrc=0
  _jo=$( cd "$1" && sh conformance/ci-gates.sh --count-legs . 2>&1 ) || _jrc=$?
  if [ "$_jrc" -ne 0 ]; then
    printf '%s\n' "$_jo" | LC_ALL=C grep -E '^FAIL' | head -n 3 | while IFS= read -r _jl; do
      echo "conformance-mass-budget: FAIL -- jobs cannot be MEASURED (ci-gates.sh --count-legs, not this budget): $(printf '%s' "$_jl" | mb_san)"
    done
    echo "conformance-mass-budget: FAIL -- jobs cannot be MEASURED: ci-gates.sh --count-legs exited $_jrc. A refusal is a FAIL, never 0 jobs."
    return 1
  fi
  _jt=$(printf '%s\n' "$_jo" | LC_ALL=C sed -n 's/^total \([0-9][0-9]*\)$/\1/p' | tail -n 1)
  if ! mb_marker_ok "$_jt" || [ "$_jt" -eq 0 ]; then
    echo "conformance-mass-budget: FAIL -- jobs cannot be MEASURED: ci-gates.sh --count-legs printed no usable total line (got [$(printf '%s' "$_jt" | mb_san)])."
    return 1
  fi
  printf '%s\n' "$_jt"
}

# mb_genesis_lock <root>: a PR cannot move its own origin. On a pull_request event, every `GENESIS_<NAME>=<digits>` line of this script is
# compared with the merge-base's copy; any difference (or a deleted line) reds. The introducing PR is the one stated exception: GENESIS_ROWS,
# _CELLS, _LEGS and _JOBS may be ABSENT at the base, once. On a push, and on a tree with no merge-base, it prints N/A (honest: the lock then
# binds nothing). HONEST CEILING: it pins only the GENESIS_ lines; a PR can still edit the counting logic, so a reviewer must diff the count
# functions on any PR that touches them (conduct, not enforced).
# mb_genesis_forms <script>: the SOURCE LOCK for the origin lines, the twin of mb_no_literal_max. mb_genesis_lock reads only the canonical form
# (`GENESIS_NAME=<digits>` at column 0), so a PR could move an origin by writing it another way (indented, readonly/export/declare, quoted,
# `$((...))`) or by assigning it twice (the later wins). Any GENESIS_ assignment that is not canonical, and any name assigned twice, is a FAIL.
mb_genesis_forms() {
  if [ ! -r "$1" ]; then echo "conformance-mass-budget: FAIL -- the genesis-form lock cannot read [$(printf '%s' "$1" | mb_san)]."; return 1; fi
  _gfo=$(LC_ALL=C awk '
    /^[[:space:]]*(readonly[[:space:]]+|export[[:space:]]+|local[[:space:]]+|typeset[[:space:]]+|declare[[:space:]]+-?[a-z]*[[:space:]]+)?GENESIS_[A-Z_]+=/ {
      if ($0 ~ /^GENESIS_[A-Z_]+=[0-9]+([ \t]|$)/) { n = $0; sub(/=.*/, "", n); if (seen[n]++) print NR ": " n " is assigned twice"; next }
      print NR ": a GENESIS_ assignment that is not the canonical column-0 GENESIS_NAME=<digits> form"
    }' "$1")
  [ -z "$_gfo" ] && return 0
  printf '%s\n' "$_gfo" | head -n 3 | while IFS= read -r _gfl; do
    echo "conformance-mass-budget: FAIL -- genesis-form lock, line $(printf '%s' "$_gfl" | mb_san). An origin is written ONE way (column 0, bare digits, once) so the merge-base genesis lock reads what the gate uses."
  done
  return 1
}
MB_NEW_GENESIS="GENESIS_ROWS GENESIS_CELLS_WORKSPACE GENESIS_CELLS_TMPCLONE GENESIS_LEGS GENESIS_JOBS"
MB_CELLS_VARIANT=workspace   # which cells genesis run() uses; set from argv only (--grade-cells <n> <variant>)
mb_genesis_lock() {
  _gl="conformance-mass-budget: genesis lock"
  case "${GITHUB_EVENT_NAME:-}" in pull_request) : ;; *) echo "$_gl: N/A (not a pull_request event, so there is no merge-base to compare with; this lock then binds nothing)"; return 0 ;; esac
  _gb=${GITHUB_BASE_REF:-}
  if ! printf '%s' "$_gb" | LC_ALL=C grep -qE '^[A-Za-z0-9._/-]+$'; then echo "$_gl: N/A (GITHUB_BASE_REF is empty or off-shape)"; return 0; fi
  if [ -z "$(command -v git 2>/dev/null || :)" ] || ! git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "$_gl: N/A (no git work tree here)"; return 0; fi
  _gref="refs/remotes/origin/$_gb"
  if ! git -C "$1" rev-parse --verify -q "$_gref^{commit}" >/dev/null 2>&1; then echo "$_gl: N/A (the base ref $_gref is not in this checkout)"; return 0; fi
  _gmb=$(git -C "$1" merge-base "$_gref" HEAD 2>/dev/null) || { echo "$_gl: N/A (no merge-base between $_gref and HEAD)"; return 0; }
  _gbase=$(git -C "$1" show "$_gmb:conformance/conformance-mass-budget.sh" 2>/dev/null) || { echo "$_gl: N/A (this script does not exist at the merge-base)"; return 0; }
  _gbp=$(printf '%s\n' "$_gbase" | LC_ALL=C sed -nE 's/^(GENESIS_[A-Z_]+)=([0-9]+).*$/\1=\2/p')
  _ghp=$(LC_ALL=C sed -nE 's/^(GENESIS_[A-Z_]+)=([0-9]+).*$/\1=\2/p' "$1/conformance/conformance-mass-budget.sh")
  _glbad=0
  for _gp in $_ghp; do
    _gn=${_gp%%=*}; _gv=${_gp#*=}
    _gbv=$(printf '%s\n' "$_gbp" | LC_ALL=C sed -n "s/^$_gn=//p")
    if [ -z "$_gbv" ]; then
      case " $MB_NEW_GENESIS " in
        *" $_gn "*) echo "$_gl: $_gn absent at the merge-base (the genesis-setting diff; allowed once, graded by the reviewer re-running the count)"; continue ;;
      esac
      echo "conformance-mass-budget: FAIL -- genesis lock: $_gn is new here and absent at the merge-base. Only the four SWAS-281 genesis names are excused, once; a PR cannot add an origin of its own."
      _glbad=1; continue
    fi
    if [ "$_gbv" != "$_gv" ]; then
      echo "conformance-mass-budget: FAIL -- genesis lock: $_gn is $_gv here but $_gbv at the merge-base. A PR cannot move its own origin: GENESIS is set once; append an ack line to conformance/mass-acks.txt instead."
      _glbad=1
    fi
  done
  for _gp in $_gbp; do
    _gn=${_gp%%=*}
    case " $(printf '%s' "$_ghp" | tr '\n' ' ') " in
      *" $_gn="*) : ;;
      *) echo "conformance-mass-budget: FAIL -- genesis lock: $_gn exists at the merge-base and is deleted here. A PR cannot remove an origin."; _glbad=1 ;;
    esac
  done
  [ "$_glbad" -eq 0 ] || return 1
  echo "$_gl: OK -- every GENESIS_ line is unchanged from the merge-base ($_gmb)"
  return 0
}

# mb_ci_measure <surface> <root>: dispatch to the surface's counter (stdout: the count, or the FAIL text; rc 1 on FAIL).
mb_ci_measure() {
  case "$1" in
    rows)  mb_count_rows "$2" ;;
    cells)
      case "$MB_CELLS_MODE" in
        na)   return 2 ;;
        list) mb_count_cells "$2" ;;
        *)    printf '%s\n' "$MB_CELLS_MODE" ;;
      esac ;;
    legs)  mb_count_legs "$2" "$MB_HEAVY_CHECKS" ;;
    *)     mb_count_jobs "$2" ;;
  esac
}

# mb_ci_surfaces <root> <ledger> <g_rows> <g_cells> <g_legs> <g_jobs>: grade the four counts against GENESIS + the scoped acks, print each
# surface line, its banked SLACK (a negative or positive ack that leaves room must show on every run), and its provenance. rc 1 on any red.
mb_ci_surfaces() {
  # ⚠️ EVERY VARIABLE HERE IS `_ci_`-PREFIXED, deliberately: sh has no locals, and this runs in mb_verdict's shell, which still reads its own
  # _cgen/_csum/_cmax (the census genesis, sum and ceiling) when it prints the CENSUS provenance after this returns.
  _ci_root=$1; _ci_led=$2; _ci_bad=0
  for _ci_item in rows:$3 cells:$4 legs:$5 jobs:$6; do
    _ci_name=${_ci_item%%:*}; _ci_gen=${_ci_item#*:}
    _ci_rc=0; _ci_cnt=$(mb_ci_measure "$_ci_name" "$_ci_root") || _ci_rc=$?
    _ci_sum=$(mb_ledger_sum "$_ci_led" "$_ci_name")
    _ci_max=$((_ci_gen + _ci_sum))
    _ci_up=$(printf '%s' "$_ci_name" | LC_ALL=C tr 'a-z' 'A-Z')
    if [ "$_ci_rc" -eq 2 ]; then
      echo "conformance-mass-budget: $_ci_name N/A in this run (NOT a pass): the guard battery's --list-cells takes ~2 min of wall [M], so the cells count is graded by the guard-battery join job (it passes the join's own listed-set size and its variant: sh conformance/conformance-mass-budget.sh --grade-cells <n> <variant>) or on demand with --grade-cells-listing; GENESIS_CELLS is held by the genesis lock either way."
      mb_provenance "$_ci_up" "$_ci_gen" "$_ci_max" "$_ci_led" "$_ci_name" "$_ci_sum"
      continue
    fi
    if [ "$_ci_rc" -ne 0 ]; then printf '%s\n' "$_ci_cnt"; _ci_bad=1; continue; fi
    case "$_ci_name" in rows) _ci_unit=row ;; cells) _ci_unit=cell ;; legs) _ci_unit=leg ;; *) _ci_unit=job ;; esac
    mb_surface "$_ci_name" "$_ci_cnt" "$_ci_max" "$_ci_unit" || _ci_bad=1
    if [ "$_ci_cnt" -le "$_ci_max" ]; then echo "conformance-mass-budget: slack $_ci_name $((_ci_max - _ci_cnt)) free (ceiling $_ci_max, count $_ci_cnt)"; fi
    mb_provenance "$_ci_up" "$_ci_gen" "$_ci_max" "$_ci_led" "$_ci_name" "$_ci_sum"
  done
  return "$_ci_bad"
}

selftest() {
  sfail=0
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  # ⚠️ THE NUMBERING GAP IS DELIBERATE: legs iv and v ARE RETIRED (MASS-CEILING-ADDITIVE, 2026-09-04).
  # They graded a PRE-EMPTIVE ACK (an ack no raise consumes) and an UNACKNOWLEDGED RAISE. Both states
  # required a MAX_ literal that could disagree with the ledger; the literals are gone and the ceiling
  # IS the sum, so neither state is constructible and a leg asserting it would be vacuous. What stands
  # in their place is the d-series below: the source lock, order independence, the printed derivation,
  # the merge attribute, and the two-branch merge itself.
  # ⚠️ EVERY mb_verdict CALL BELOW TAKES SEVEN ARGUMENTS, NOT TWELVE, and the five it lost were the
  # <max> values. A leg that used to name a ceiling now names a GENESIS, and the ceiling it exercises
  # is whatever this fixture's own ledger derives from it.

  mb_fixture() {   # <dir> <nfiles> <lines-per-file>
    rm -rf "$1"; mkdir -p "$1/conformance" "$1/docs"
    printf 'kit marker\n' > "$1/docs/ROADMAP-KIT.md"
    printf 'conformance/mass-acks.txt merge=union\n' > "$1/.gitattributes"
    printf '# fixture ledger\n' > "$1/conformance/mass-acks.txt"
    _i=1
    while [ "$_i" -le "$2" ]; do
      _j=1; : > "$1/conformance/f$_i.sh"
      while [ "$_j" -le "$3" ]; do printf 'line\n' >> "$1/conformance/f$_i.sh"; _j=$((_j + 1)); done
      _i=$((_i + 1))
    done
  }

  mb_ack() {       # <dir> <line-with-\t-escapes> — append a raw line to the fixture ledger
    printf '%b\n' "$2" >> "$1/conformance/mass-acks.txt"
  }

  mb_fixture "$W/ok" 4 10          # 4 files x 10 lines = 40 lines
  if mb_verdict "$W/ok" 0 4 0 40 0 0 >/dev/null 2>&1; then
    echo "PASS: selftest -- leg i within-budget tree passes"
  else echo "FAIL: selftest -- leg i within-budget tree wrongly red"; sfail=1; fi

  mb_fixture "$W/grow" 4 11        # +10% lines, no ack, no raise
  if mb_verdict "$W/grow" 0 4 0 40 0 0 >/dev/null 2>&1; then
    echo "FAIL: selftest -- leg ii undeclared growth wrongly green"; sfail=1
  else echo "PASS: selftest -- leg ii undeclared growth reds"; fi

  # leg iii -- the SAME growth, declared by a matching ack AND the matching raise, passes and NAMES it.
  mb_fixture "$W/ack" 4 11
  mb_ack "$W/ack" "2026-08-20\tlogic\t+4\tleg-iii-declared-growth"
  if _o=$(mb_verdict "$W/ack" 0 4 0 40 0 0 2>&1); then
    if printf '%s\n' "$_o" | grep -Fq 'leg-iii-declared-growth'; then
      echo "PASS: selftest -- leg iii declared growth passes and names the consumed ack"
    else echo "FAIL: selftest -- leg iii passed SILENTLY: the consumed ack was not named in the output"; sfail=1; fi
  else echo "FAIL: selftest -- leg iii declared growth wrongly red"; sfail=1; fi

  # legs iv and v -- RETIRED 2026-09-04 (MASS-CEILING-ADDITIVE); see the numbering-gap note above.
  # iv graded a PRE-EMPTIVE ack and v an UNACKNOWLEDGED RAISE. Both needed a MAX_ literal that could
  # disagree with the ledger. There is no literal, so there is no disagreement to construct, and a leg
  # that cannot fail is not a leg. The d-series below is what took the teeth over.

  # leg vi -- A CUT. The gate must not punish removal: mass DOWN, MAX down with it, ledger reconciled.
  # Both sanctioned re-tighten shapes run here, because both are what CUT-AI-GOV-TEMPLATE-THIN owes:
  # the `lines` raise is PRUNED (MAX returns to genesis) and `files` carries an APPENDED negative ack
  # (MAX drops BELOW genesis). Fixture: 3 files x 8 lines = 24 lines, down from the leg-iii tree.
  mb_fixture "$W/cut" 3 8
  mb_ack "$W/cut" "2026-08-21\tfiles\t-1\tleg-vi-cut-removed-a-check"
  if _o=$(mb_verdict "$W/cut" 0 4 0 40 0 0 2>&1); then
    if printf '%s\n' "$_o" | grep -Fq 'leg-vi-cut-removed-a-check'; then
      echo "PASS: selftest -- leg vi a cut (pruned raise + negative ack) passes and names the ack"
    else echo "FAIL: selftest -- leg vi passed but did not name the negative ack"; sfail=1; fi
  else echo "FAIL: selftest -- leg vi wrongly punished a CUT"; sfail=1; fi

  # leg vii -- a MALFORMED ack (wrong field count) is never an acknowledgment, and it is NAMED.
  mb_fixture "$W/malformed" 4 11
  mb_ack "$W/malformed" "2026-08-20\tlogic\tleg-vii-malformed-three-fields"
  if _o=$(mb_verdict "$W/malformed" 0 4 0 40 0 0 2>&1); then
    echo "FAIL: selftest -- leg vii malformed ack wrongly laundered the raise"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'leg-vii-malformed-three-fields'; then
      echo "PASS: selftest -- leg vii malformed ack reds and names the line"
    else echo "FAIL: selftest -- leg vii redded but did not name the malformed line"; sfail=1; fi
  fi

  # leg viii -- a REASONLESS ack (4 fields, empty reason) FAILS: an unreasoned amnesty is the defect.
  mb_fixture "$W/reasonless" 4 11
  mb_ack "$W/reasonless" "2026-08-20\tlogic\t+4\t"
  if _o=$(mb_verdict "$W/reasonless" 0 4 0 40 0 0 2>&1); then
    echo "FAIL: selftest -- leg viii reasonless ack wrongly accepted"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'reasonless'; then
      echo "PASS: selftest -- leg viii reasonless ack reds as reasonless"
    else echo "FAIL: selftest -- leg viii redded but not as a reasonless entry"; sfail=1; fi
  fi

  # leg xii -- a LEADING-ZERO delta is MALFORMED, named, and never an acknowledgment. Regression pin
  # for a measured defect: under the old `^[+-][0-9]+$` grammar `+010` was evaluated as OCTAL 8, so a
  # ledger reading "+010" against GENESIS 40 satisfied MAX 48 and the run went GREEN — a written +10
  # laundered as +8. The sibling `+09` did worse: dash aborts on "Illegal number" with rc 2 (read as
  # UNVERIFIED) and the gate printed no verdict at all. Both are pinned; both must be MALFORMED.
  for _lz in '+010' '+09' '-007' '+00'; do
    mb_fixture "$W/lz" 4 11
    mb_ack "$W/lz" "2026-08-20\tlogic\t$_lz\tleg-xii-leading-zero"
    if _o=$(mb_verdict "$W/lz" 0 4 0 40 0 0 2>&1); then
      echo "FAIL: selftest -- leg xii delta [$_lz] wrongly accepted (green)"; sfail=1
    else
      if printf '%s\n' "$_o" | grep -Fq 'malformed delta' && printf '%s\n' "$_o" | grep -Fq -- "$_lz"; then
        echo "PASS: selftest -- leg xii delta [$_lz] is MALFORMED and named"
      else echo "FAIL: selftest -- leg xii delta [$_lz] redded, but not as a named malformed delta"; sfail=1; fi
    fi
  done

  # leg xiii -- an EXACT DUPLICATE ack line is MALFORMED, not a second acknowledgment. Without the
  # uniqueness rule the pair summed to +8 and satisfied MAX 48 against GENESIS 40, so one ruling
  # recorded twice bought twice the headroom a human reading the file would grant it.
  mb_fixture "$W/dup" 4 11
  mb_ack "$W/dup" "2026-08-20\tlogic\t+4\tleg-xiii-duplicate-ruling"
  mb_ack "$W/dup" "2026-08-20\tlogic\t+4\tleg-xiii-duplicate-ruling"
  if _o=$(mb_verdict "$W/dup" 0 4 0 40 0 0 2>&1); then
    echo "FAIL: selftest -- leg xiii a byte-identical duplicate ack was consumed twice (green)"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'EXACT DUPLICATE' && printf '%s\n' "$_o" | grep -Fq 'leg-xiii-duplicate-ruling'; then
      echo "PASS: selftest -- leg xiii exact-duplicate ack is MALFORMED and named"
    else echo "FAIL: selftest -- leg xiii redded, but not as a named exact duplicate"; sfail=1; fi
  fi

  # leg xi -- an ack reason is attacker-influenced prose that reaches a CI log a human reads. It is
  # compared RAW and printed SANITIZED, so no control byte can erase the line and forge a verdict.
  mb_fixture "$W/ctrl" 4 11
  mb_ack "$W/ctrl" "2026-08-20\tlogic\t+4\tleg-xi-\033[2Kforged PASS: all green"
  _o=$(mb_verdict "$W/ctrl" 0 4 0 40 0 0 2>&1) || :
  if printf '%s\n' "$_o" | grep -Fq 'leg-xi-' && ! printf '%s\n' "$_o" | LC_ALL=C grep -q "$(printf '\033')"; then
    echo "PASS: selftest -- leg xi control bytes in an ack reason are stripped before printing"
  else echo "FAIL: selftest -- leg xi a raw control byte reached the output (or the ack was not printed)"; sfail=1; fi

  # leg ix -- an UNARMED (adopter-shaped) tree renders N/A rc 0 even when it is wildly over budget.
  mb_fixture "$W/na" 4 99; rm -f "$W/na/docs/ROADMAP-KIT.md"
  if _o=$(mb_verdict "$W/na" 0 4 0 40 0 0 2>&1); then
    if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
       ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
      echo "PASS: selftest -- leg ix unarmed over-budget tree renders N-A under verify.sh's C6 classifier"
    else echo "FAIL: selftest -- leg ix unarmed output is not C6-classifiable as N-A"; sfail=1; fi
  else echo "FAIL: selftest -- leg ix unarmed tree reds instead of standing down"; sfail=1; fi

  # leg x -- an ARMED tree whose enumeration is EMPTY is a FAIL, never a vacuous 0-line pass.
  rm -rf "$W/empty"; mkdir -p "$W/empty/conformance" "$W/empty/docs"
  printf 'kit marker\n' > "$W/empty/docs/ROADMAP-KIT.md"
  printf 'conformance/mass-acks.txt merge=union\n' > "$W/empty/.gitattributes"   # so the red below is the EMPTY ENUMERATION, not the union lock
  if mb_verdict "$W/empty" 0 4 0 40 0 0 >/dev/null 2>&1; then
    echo "FAIL: selftest -- leg x empty enumeration wrongly passes (vacuous 0-line green)"; sfail=1
  else echo "PASS: selftest -- leg x empty enumeration on an armed tree reds"; fi

  # ── SPLIT-ERA FIXTURE BUILDER. mb_fixture above writes marker-less files, which under the split
  # price ENTIRELY as `logic` (the conservative default, leg xvi). This one writes files with a real
  # oracle boundary, so the two populations can be moved independently by the legs below.
  mb_fixture_mk() { # <dir> <nfiles> <pre-marker-lines> <post-marker-lines-incl-marker> <style>
    rm -rf "$1"; mkdir -p "$1/conformance" "$1/docs"
    printf 'kit marker\n' > "$1/docs/ROADMAP-KIT.md"
    printf 'conformance/mass-acks.txt merge=union\n' > "$1/.gitattributes"
    printf '# fixture ledger\n' > "$1/conformance/mass-acks.txt"
    _i=1
    while [ "$_i" -le "$2" ]; do
      _t="$1/conformance/f$_i.sh"; : > "$_t"
      _j=1; while [ "$_j" -le "$3" ]; do printf 'line\n' >> "$_t"; _j=$((_j + 1)); done
      if [ "$5" != none ]; then
        case "$5" in
          fn)  printf 'selftest() {\n' >> "$_t" ;;
          ifb) printf 'if [ "$1" = --selftest ]; then\n' >> "$_t" ;;
          arm) printf '  --selftest)\n' >> "$_t" ;;
        esac
        _j=1; while [ "$_j" -lt "$4" ]; do printf 'oracle\n' >> "$_t"; _j=$((_j + 1)); done
      fi
      _i=$((_i + 1))
    done
  }

  # leg xiv -- THE SPLIT IS LOAD-BEARING IN THE CHEAP DIRECTION (design 3.3/1). One tree, two equal
  # growths: +6 lines of LOGIC reds against a zero-headroom logic ceiling, while the SAME +6 lines of
  # FIXTURE passes inside the band. If the two surfaces ever collapse back into one number this leg
  # goes red, because a single number cannot answer differently to the same delta.
  mb_fixture_mk "$W/base" 2 10 10 fn                      # logic 20, fixture 20
  mb_ack "$W/base" "2026-08-31\tfixture\t+10\tleg-xiv-inaugural-band"
  if mb_verdict "$W/base" 0 2 0 20 20 0 >/dev/null 2>&1; then
    echo "PASS: selftest -- leg xiv split baseline (logic 20/20, fixture 20/30) passes"
  else echo "FAIL: selftest -- leg xiv split baseline wrongly red"; sfail=1; fi

  mb_fixture_mk "$W/glogic" 2 13 10 fn                    # logic 26 > 20; fixture unchanged
  mb_ack "$W/glogic" "2026-08-31\tfixture\t+10\tleg-xiv-inaugural-band"
  if _o=$(mb_verdict "$W/glogic" 0 2 0 20 20 0 2>&1); then
    echo "FAIL: selftest -- leg xiv logic growth past MAX_LOGIC wrongly green"; sfail=1
  else
    # ⚠️ THE REMEDY TOKEN MOVED 2026-09-04: the cure used to be "raise MAX_LOGIC with a matching ack
    # line"; there is no constant to raise, so the printed cure is ONE appended ack line scoped to the
    # LOWERCASE surface. The leg asserts the new token, and still asserts that fixture is not blamed.
    if printf '%s\n' "$_o" | grep -Fq 'logic 26/20' && printf '%s\n' "$_o" | grep -Fq 'append ONE ack line' &&
       ! printf '%s\n' "$_o" | grep -Fq 'FAIL -- fixture'; then
      echo "PASS: selftest -- leg xiv logic growth reds NAMING logic and offering the one-appended-ack cure (and does not blame fixture)"
    else echo "FAIL: selftest -- leg xiv logic growth redded, but not as a named logic overrun"; sfail=1; fi
  fi

  mb_fixture_mk "$W/gfix" 2 10 13 fn                      # the SAME +6, on fixture, inside the band
  mb_ack "$W/gfix" "2026-08-31\tfixture\t+10\tleg-xiv-inaugural-band"
  if mb_verdict "$W/gfix" 0 2 0 20 20 0 >/dev/null 2>&1; then
    echo "PASS: selftest -- leg xiv the same growth on FIXTURE passes inside the band"
  else echo "FAIL: selftest -- leg xiv fixture growth inside the band wrongly red"; sfail=1; fi

  # leg xv -- THE BAND IS A CEILING, NOT A BLANK CHEQUE (design 3.3/2). Fixture past MAX_FIXTURE reds
  # and names fixture: the per-epoch re-ratification is the price of the per-slice ack it replaces.
  mb_fixture_mk "$W/gfix2" 2 10 25 fn                     # fixture 50 > 30
  mb_ack "$W/gfix2" "2026-08-31\tfixture\t+10\tleg-xv-band-exhausted"
  if _o=$(mb_verdict "$W/gfix2" 0 2 0 20 20 0 2>&1); then
    echo "FAIL: selftest -- leg xv fixture growth past MAX_FIXTURE wrongly green"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'fixture 50/30'; then
      echo "PASS: selftest -- leg xv fixture growth past the band reds NAMING fixture"
    else echo "FAIL: selftest -- leg xv redded, but not as a named fixture overrun"; sfail=1; fi
  fi

  # leg xvi -- A NO-MARKER FILE PRICES AS LOGIC (design 3.3/3), the conservative direction, pinned.
  # 17 of the kit's own checks carry no marker; if they ever priced as fixture they would land in the
  # banded surface and grow ack-free, which is the exact laundering the split must not create.
  mb_fixture "$W/nomark" 2 11                              # 22 marker-less lines
  if _o=$(mb_verdict "$W/nomark" 0 2 0 20 0 0 2>&1); then
    echo "FAIL: selftest -- leg xvi marker-less growth wrongly green"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'logic 22/20' && printf '%s\n' "$_o" | grep -Fq 'fixture 0/0'; then
      echo "PASS: selftest -- leg xvi a marker-less file prices wholly as logic"
    else echo "FAIL: selftest -- leg xvi did not price the marker-less file as logic"; sfail=1; fi
  fi

  # leg xvii -- BOUNDARY SEMANTICS (design 3.3/4), one fixture file per arm of the copied rule. This
  # is what makes the VERBATIM copy of non-vacuity.sh's first_marker safe to hold: a silent semantic
  # change to the copy moves one of these numbers and reds here.
  for _st in fn ifb arm none; do
    mb_fixture_mk "$W/bnd" 1 5 5 "$_st"
    _o=$(mb_verdict "$W/bnd" 0 1 0 100 100 0 2>&1) || :
    case "$_st" in
      none) _wantf='fixture 0/100' ;;
      *)    _wantf='fixture 5/100' ;;
    esac
    if printf '%s\n' "$_o" | grep -Fq 'logic 5/100' && printf '%s\n' "$_o" | grep -Fq "$_wantf"; then
      echo "PASS: selftest -- leg xvii boundary arm [$_st] splits at the expected line"
    else echo "FAIL: selftest -- leg xvii boundary arm [$_st] mis-split (wanted logic 5, $_wantf)"; sfail=1; fi
  done
  # ...and the PRECEDENCE half of the rule: a bare `--selftest)` case arm is a FALLBACK ONLY, so a
  # real selftest() definition LATER in the file still wins and the arm above it prices as logic.
  mb_fixture_mk "$W/prec" 1 5 5 fn
  _pf="$W/prec/conformance/f1.sh"
  { printf '  --selftest)\n'; cat "$_pf"; } > "$_pf.new" && mv "$_pf.new" "$_pf"   # arm at line 1, fn at line 7
  _o=$(mb_verdict "$W/prec" 0 1 0 100 100 0 2>&1) || :
  if printf '%s\n' "$_o" | grep -Fq 'logic 6/100' && printf '%s\n' "$_o" | grep -Fq 'fixture 5/100'; then
    echo "PASS: selftest -- leg xvii a real selftest() beats an earlier bare case arm (arm is fallback only)"
  else echo "FAIL: selftest -- leg xvii the bare case arm wrongly won over a real selftest()"; sfail=1; fi

  # leg xviii -- THE RETIREMENT IS ENFORCED BY A ROW-COUNT PIN, NOT BY ARITHMETIC (design 3.3/5, A1/C3).
  # A NEW `lines` ack, perfectly balanced by a MAX_LINES raise, passes the invariant — and must still
  # red, with a message that NAMES THE RETIRED SURFACE rather than an arithmetic complaint. The leg
  # asserts the message, not merely the rc, because an invariant red here would be the wrong reason.
  mb_fixture_mk "$W/retired" 2 10 10 fn
  mb_ack "$W/retired" "2026-08-31\tlines\t+5\tleg-xviii-appended-lines-ack"
  if _o=$(mb_verdict "$W/retired" 0 2 0 20 20 0 2>&1); then
    echo "FAIL: selftest -- leg xviii an appended lines ack wrongly green"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'RETIRED' &&
       ! printf '%s\n' "$_o" | grep -Fq 'MAX_LINES is' &&
       ! printf '%s\n' "$_o" | grep -Fq 'unknown surface'; then
      echo "PASS: selftest -- leg xviii an appended lines ack reds NAMING the retired surface (not arithmetic, not grammar)"
    else echo "FAIL: selftest -- leg xviii redded, but not as a retired-surface red"; sfail=1; fi
  fi

  # leg xix -- THE ZERO-SUM PAIR (A1/C3), the forgery the arithmetic cannot see: +N and -N `lines`
  # rows with DISTINCT reasons sum to zero, so the invariant stays green while the provenance
  # narrative gains two fabricated rulings. Only the row-count pin catches it.
  mb_fixture_mk "$W/zerosum" 2 10 10 fn
  mb_ack "$W/zerosum" "2026-08-31\tlines\t+5\tleg-xix-zero-sum-first-half"
  mb_ack "$W/zerosum" "2026-08-31\tlines\t-5\tleg-xix-zero-sum-second-half"
  if _o=$(mb_verdict "$W/zerosum" 0 2 0 20 20 0 2>&1); then
    echo "FAIL: selftest -- leg xix a zero-sum lines pair wrongly green (arithmetic alone passes it)"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'RETIRED' && ! printf '%s\n' "$_o" | grep -Fq 'MAX_LINES is'; then
      echo "PASS: selftest -- leg xix a zero-sum lines pair reds on the count pin, with the invariant green"
    else echo "FAIL: selftest -- leg xix redded, but on arithmetic rather than the count pin"; sfail=1; fi
  fi

  # leg xx -- FAIL-CLOSED (i) (A1/C2): the marker result is GRADED before it reaches any `$(( ))`.
  # The gate's own :126-131 lesson is that a dash arithmetic abort exits rc 2 and prints NO verdict,
  # which a harness reads as UNVERIFIED rather than FAIL. Leading zeros are rejected for the same
  # octal reason as mb_delta_ok, from which this grammar is deliberately modelled.
  for _mk in '' 'abc' '1x' '007' '-1' '1 2'; do
    if mb_marker_ok "$_mk"; then
      echo "FAIL: selftest -- leg xx marker result [$_mk] wrongly accepted as well-formed"; sfail=1
    else echo "PASS: selftest -- leg xx marker result [$_mk] is rejected"; fi
  done
  for _mk in '0' '7' '412'; do
    if mb_marker_ok "$_mk"; then echo "PASS: selftest -- leg xx marker result [$_mk] is accepted"
    else echo "FAIL: selftest -- leg xx marker result [$_mk] wrongly rejected"; sfail=1; fi
  done

  # leg xxi -- FAIL-CLOSED (ii) (A1/C2): a file the split cannot MEASURE is a FAIL, never a silent 0.
  # Two shapes: unreadable (mode 000) and zero-line. Both would otherwise contribute 0 lines and buy
  # headroom by being broken. Skipped under a uid that can read anything (root ignores mode 000).
  mb_fixture_mk "$W/unread" 2 10 10 fn
  chmod 000 "$W/unread/conformance/f2.sh" 2>/dev/null || :
  if [ -r "$W/unread/conformance/f2.sh" ]; then
    echo "SKIP: selftest -- leg xxi unreadable arm NOT EXERCISED (this uid reads mode-000 files). A skip is reported as a SKIP: a skip wearing a PASS token is the measured defect PR 12 closed elsewhere in this suite, and it would read here as an unreadable-file guarantee nothing ran to earn."
  else
    if _o=$(mb_verdict "$W/unread" 0 2 0 20 20 0 2>&1); then
      echo "FAIL: selftest -- leg xxi an UNREADABLE conformance file wrongly priced (green)"; sfail=1
    else
      if printf '%s\n' "$_o" | grep -Fq 'f2.sh' && printf '%s\n' "$_o" | grep -Fq 'cannot be MEASURED'; then
        echo "PASS: selftest -- leg xxi an unreadable file reds and is named"
      else echo "FAIL: selftest -- leg xxi redded, but not as a named unmeasurable file"; sfail=1; fi
    fi
  fi
  chmod 644 "$W/unread/conformance/f2.sh" 2>/dev/null || :

  mb_fixture_mk "$W/zeroline" 2 10 10 fn
  : > "$W/zeroline/conformance/f3.sh"
  if _o=$(mb_verdict "$W/zeroline" 0 3 0 20 20 0 2>&1); then
    echo "FAIL: selftest -- leg xxi a ZERO-LINE conformance file wrongly priced (green)"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'f3.sh' && printf '%s\n' "$_o" | grep -Fq 'cannot be MEASURED'; then
      echo "PASS: selftest -- leg xxi a zero-line file reds and is named"
    else echo "FAIL: selftest -- leg xxi zero-line redded, but not as a named unmeasurable file"; sfail=1; fi
  fi

  # leg xxii -- FAIL-CLOSED (iii) (A1/C2): the RUNTIME IDENTITY logic + fixture == the independently
  # counted total. This is the cheap catch-all — every measurement fault, including a wrong GENESIS
  # measured with a broken script, becomes a FAIL for free rather than a plausible-looking number.
  if _o=$(mb_identity_check 10 5 15 2>&1); then
    echo "PASS: selftest -- leg xxii a consistent split satisfies the runtime identity"
  else echo "FAIL: selftest -- leg xxii a consistent split wrongly failed the identity"; sfail=1; fi
  if _o=$(mb_identity_check 10 5 20 2>&1); then
    echo "FAIL: selftest -- leg xxii an INCONSISTENT split wrongly satisfied the identity"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'IDENTITY'; then
      echo "PASS: selftest -- leg xxii an inconsistent split reds on the runtime identity"
    else echo "FAIL: selftest -- leg xxii redded, but not as an identity failure"; sfail=1; fi
  fi

  # ══ THE WIRING LEGS. Both pre-push seats proved by DELETION MUTANT that legs xxii, the composition
  # block and the glide fail-arm were pinned only as FUNCTIONS or not at all: delete the CALL SITE and
  # the suite stayed 41/41 green. A unit leg on mb_identity_check says the function computes; it says
  # NOTHING about whether mb_verdict ever asks it. These legs assert at the mb_verdict level, which is
  # the only level a deletion or a `|| :` neutering has to survive.

  # leg xxiii -- THE IDENTITY IS WIRED. Shadow the MEASUREMENT, not the function: inside a subshell,
  # mb_split_rows is redefined to report a total that undercounts the tree's real wc -l, so the only
  # thing that can red is mb_verdict actually calling mb_identity_check with the independent counter.
  mb_fixture_mk "$W/wire" 2 10 10 fn                      # real tree: 40 lines, logic 20, fixture 20
  if (
       mb_split_rows() { printf '20 11 10 10 f1.sh\n'; return 0; }
       _wo=$(mb_verdict "$W/wire" 0 2 0 20 20 0 2>&1) && exit 1
       printf '%s\n' "$_wo" | grep -Fq 'SPLIT IDENTITY broken'
     ); then
    echo "PASS: selftest -- leg xxiii the runtime identity is WIRED INTO mb_verdict (a shadowed measurement reds)"
  else echo "FAIL: selftest -- leg xxiii mb_verdict did not red on a measurement that violates the identity: the call site is missing or neutered"; sfail=1; fi

  # leg xxiv -- THE COMPOSITION REPORT IS WIRED, and prints a REAL row rather than only a header. A
  # marker-heavy tree makes one file's fixture share predictable, and the leg names it.
  mb_fixture_mk "$W/comp" 1 5 15 fn                        # f1.sh: 20 lines, logic 5, fixture 15
  _o=$(mb_verdict "$W/comp" 0 1 0 100 100 0 2>&1) || :
  if printf '%s\n' "$_o" | grep -Fq 'composition --' &&
     printf '%s\n' "$_o" | grep -Fq 'f1.sh -- 15/20 fixture, marker at line 6'; then
    echo "PASS: selftest -- leg xxiv the composition report is wired and prints a real per-file row"
  else echo "FAIL: selftest -- leg xxiv the composition report is missing, header-only, or mis-attributed"; sfail=1; fi

  # leg xxv -- THE GLIDE ARMS ARE WIRED, both of them. The constant is assigned unconditionally at the
  # top of this file, so a real run can NEVER take its value from the environment — that is the whole
  # point of a control-plane seam. These legs therefore set the variable in a SUBSHELL around the call
  # (the assignment is still overwritten from the environment's point of view in any real run), which
  # exercises the arms in-process without a patched copy and without making the seam env-injectable.
  mb_fixture_mk "$W/glide" 2 10 10 fn
  if (
       LOGIC_GLIDE_TARGET=abc
       _go=$(mb_verdict "$W/glide" 0 2 0 20 20 0 2>&1) && exit 1
       printf '%s\n' "$_go" | grep -Fq 'LOGIC_GLIDE_TARGET is set to [abc]'
     ); then
    echo "PASS: selftest -- leg xxv an ungradeable glide target reds and names the bad value"
  else echo "FAIL: selftest -- leg xxv an ungradeable glide target was silently ignored (or unnamed)"; sfail=1; fi
  if (
       LOGIC_GLIDE_TARGET=10
       _go=$(mb_verdict "$W/glide" 0 2 0 20 20 0 2>&1) || exit 1
       printf '%s\n' "$_go" | grep -Fq 'ADVISORY ONLY'
     ); then
    echo "PASS: selftest -- leg xxv a SET glide target stays ADVISORY (rc 0) — advisory is the ceiling"
  else echo "FAIL: selftest -- leg xxv a set glide target changed the verdict, or dropped its advisory disclaimer"; sfail=1; fi

  # leg xxvi -- THE REMEDY ROUND-TRIP. The line this gate PRINTS as the cure for a red is fed back
  # VERBATIM through the grammar that will judge it. It used to fail on two counts at once — an
  # UPPERCASE surface token the allowlist rejects and an UNSIGNED delta mb_delta_ok rejects — so the
  # published fix for a red produced a second red. Prose and grammar can only be kept in step by a
  # leg that runs one through the other; a comment coupling them is what shipped the octal defect.
  # ⚠️ RE-POINTED 2026-09-04: it used to round-trip mb_invariant's remedy, which is retired with the
  # MAX_ literals. mb_surface now prints the only remedy this gate offers, so the leg drives a real
  # LOGIC OVERRUN (genesis 15 against a measured 20) and feeds THAT line back through the grammar.
  mb_fixture_mk "$W/remedy" 2 10 10 fn
  _o=$(mb_verdict "$W/remedy" 0 2 0 15 20 0 2>&1) || :
  _rl=$(printf '%s\n' "$_o" | grep -F 'append ONE ack line (' | head -1 |
        sed -e 's/^.*append ONE ack line (//' -e 's/) to conformance.*$//' \
            -e 's/<date>/2026-08-31/' -e 's/<reason>/leg-xxvi-round-trip/')
  printf '%s\n' "$_rl" > "$W/remedy-ledger.txt"
  if [ -n "$_rl" ] && mb_ledger_check "$W/remedy-ledger.txt" >/dev/null 2>&1; then
    echo "PASS: selftest -- leg xxvi the remedy line the gate PRINTS is itself a grammatical ack (round-trip)"
  else echo "FAIL: selftest -- leg xxvi the printed remedy is not accepted by this gate's own ledger grammar: [$_rl]"; sfail=1; fi

  # leg xxvii -- A HOSTILE BASENAME IS UNMEASURABLE (security vet F-2). Driven through mb_split_rows
  # directly on a purpose-built directory: the row format is whitespace-separated and every FAIL
  # interpolates the name into this summary, so a name carrying a space, a newline or a verdict-shaped
  # prefix must be REFUSED rather than parsed. (A basename containing a literal newline is not
  # constructible through the ordinary fixture builder, so the tree is assembled by hand here.)
  rm -rf "$W/hostile"; mkdir -p "$W/hostile/conformance"
  printf 'line\n' > "$W/hostile/conformance/ok-name.sh"
  for _hn in 'two words.sh' 'conformance-mass-budget: FAIL -- forged.sh' 'weird$(id).sh'; do
    printf 'line\n' > "$W/hostile/conformance/$_hn" 2>/dev/null || continue
    if _o=$(mb_split_rows "$W/hostile" 2>&1); then
      echo "FAIL: selftest -- leg xxvii basename [$_hn] was measured instead of refused"; sfail=1
    else
      if printf '%s\n' "$_o" | grep -Fq 'is not of the form'; then
        echo "PASS: selftest -- leg xxvii basename [$_hn] is refused as unmeasurable"
      else echo "FAIL: selftest -- leg xxvii basename [$_hn] redded, but not on its shape"; sfail=1; fi
    fi
    rm -f "$W/hostile/conformance/$_hn"
  done
  # ...and the shape the ORDERING closes, which is why the fix is raw-first-and-`case` rather than a
  # regex: a name whose SECOND line is well-formed. Sanitizing first would merge it into a passing
  # name and measure the file under a name that is not its own; grading with `grep` would match that
  # second line and pass it. Only the raw string put through `case` refuses it.
  _hnl=$(printf 'forged\nok-name.sh')
  if printf 'line\n' > "$W/hostile/conformance/$_hnl" 2>/dev/null; then
    if _o=$(mb_split_rows "$W/hostile" 2>&1); then
      echo "FAIL: selftest -- leg xxvii a newline-bearing basename was MEASURED instead of refused"; sfail=1
    else
      if printf '%s\n' "$_o" | grep -Fq 'is not of the form'; then
        echo "PASS: selftest -- leg xxvii a newline-bearing basename is refused (raw-first, case-graded)"
      else echo "FAIL: selftest -- leg xxvii the newline-bearing name redded, but not on its shape"; sfail=1; fi
    fi
    rm -f "$W/hostile/conformance/$_hnl"
  else
    echo "SKIP: selftest -- leg xxvii newline-bearing basename NOT EXERCISED (this filesystem refused to create the name)"
  fi

  # ══ THE DERIVED-CEILING LEGS (MASS-CEILING-ADDITIVE, 2026-09-04). The five MAX_* literals are gone
  # and the ceiling is GENESIS + Σ(ledger) computed on every run, so the states legs iv and v graded
  # (a pre-emptive ack, an unacked raise) are no longer constructible. What replaces them is a lock
  # against the literal coming back, a proof that the ledger's ORDER cannot change the answer, the
  # printed derivation itself, and the merge attribute that makes two branches' acks combine.

  # leg d-i -- THE SOURCE LOCK. A reintroduced `MAX_<surface>=<digits>` assignment reds, NAMING the
  # line, and a literal-free script passes (the lock is load-bearing in both directions).
  _lit="$W/lit.sh"
  { printf '#!/bin/sh\n'; printf 'GENESIS_LOGIC=100\n'; printf 'MAX_'; printf 'LOGIC=33500\n'; } > "$_lit"
  if _o=$(mb_no_literal_max "$_lit" 2>&1); then
    echo "FAIL: selftest -- leg d-i a planted MAX_LOGIC literal was not refused by the source lock"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'MAX_LOGIC=33500' && printf '%s\n' "$_o" | grep -Fq 'line 3'; then
      echo "PASS: selftest -- leg d-i a reintroduced MAX_ literal reds and names the line"
    else echo "FAIL: selftest -- leg d-i redded, but did not name the offending line: [$_o]"; sfail=1; fi
  fi
  # ...and the other DIRECT forms: a lock seeing only the bare one lets `readonly MAX_LOGIC="33500"` in.
  for _lf in 'MAX_LOGIC="33500"' "MAX_LOGIC='33500'" 'readonly MAX_LOGIC=33500' 'export MAX_FIXTURE=+70' 'local MAX_LOGIC=33500' 'typeset MAX_CENSUS=1' '  MAX_LINES=-1'; do
    _lit2="$W/lit2.sh"
    { printf '#!/bin/sh\n'; printf '%s\n' "$_lf"; } > "$_lit2"
    if mb_no_literal_max "$_lit2" >/dev/null 2>&1; then
      echo "FAIL: selftest -- leg d-i the source lock MISSED a direct literal form [$_lf]"; sfail=1
    else echo "PASS: selftest -- leg d-i the source lock catches the direct literal form [$_lf]"; fi
  done
  # ...and the DISCLOSED evasions stay evasions, so the header's catch set cannot silently go wrong.
  for _le in 'MAX_LOGIC=$((33500))' 'MAX_LOGIC=$CACHED' 'MAX_LOGIC=$(cat ceiling)'; do
    _lit3="$W/lit3.sh"
    { printf '#!/bin/sh\n'; printf '%s\n' "$_le"; } > "$_lit3"
    if mb_no_literal_max "$_lit3" >/dev/null 2>&1; then
      echo "PASS: selftest -- leg d-i the DISCLOSED evasion [$_le] passes, as the header says (inert: no code path reads \$MAX_*)"
    else echo "FAIL: selftest -- leg d-i an evasion the header discloses as uncaught was caught -- update the disclosure: [$_le]"; sfail=1; fi
  done
  _cln="$W/clean.sh"
  { printf '#!/bin/sh\n'; printf 'GENESIS_LOGIC=100\n'; printf '# the MAX_LOGIC literal used to live here\n'; } > "$_cln"
  if mb_no_literal_max "$_cln" >/dev/null 2>&1; then
    echo "PASS: selftest -- leg d-i a literal-free script passes the source lock"
  else echo "FAIL: selftest -- leg d-i the source lock reds a literal-free script (vacuously red)"; sfail=1; fi

  # leg d-ii -- ORDER INDEPENDENCE (the row's acceptance criterion). Two acks appended A-then-B and
  # B-then-A are the two trees a union merge can produce; the printed ceiling must be byte-identical.
  mb_fixture_mk "$W/ordA" 2 10 10 fn
  mb_ack "$W/ordA" "2026-09-04\tlogic\t+5\tleg-d-ii-ack-A"
  mb_ack "$W/ordA" "2026-09-04\tlogic\t+7\tleg-d-ii-ack-B"
  mb_fixture_mk "$W/ordB" 2 10 10 fn
  mb_ack "$W/ordB" "2026-09-04\tlogic\t+7\tleg-d-ii-ack-B"
  mb_ack "$W/ordB" "2026-09-04\tlogic\t+5\tleg-d-ii-ack-A"
  _oa=$(mb_verdict "$W/ordA" 0 2 0 20 20 0 2>&1 | grep -F 'MAX_LOGIC=' | head -1) || :
  _ob=$(mb_verdict "$W/ordB" 0 2 0 20 20 0 2>&1 | grep -F 'MAX_LOGIC=' | head -1) || :
  if [ -n "$_oa" ] && [ "$_oa" = "$_ob" ] && printf '%s\n' "$_oa" | grep -Fq 'MAX_LOGIC=32 '; then
    echo "PASS: selftest -- leg d-ii two acks in either order derive the SAME ceiling (MAX_LOGIC=32)"
  else echo "FAIL: selftest -- leg d-ii the ceiling depends on ledger ORDER, or was not derived: A=[$_oa] B=[$_ob]"; sfail=1; fi

  # leg d-iii -- THE DERIVATION IS PRINTED. A reader must be able to re-add the numbers from the line
  # itself; a bare ceiling would be a constant again, just one nobody can see the source of.
  if printf '%s\n' "$_oa" | grep -Fq '= genesis 20 + (+12) over 2 ack(s), last 2026-09-04'; then
    echo "PASS: selftest -- leg d-iii the provenance line prints the full derivation"
  else echo "FAIL: selftest -- leg d-iii the provenance line does not print the derivation genesis + (sum) over N ack(s): [$_oa]"; sfail=1; fi

  # leg d-iv -- THE UNION ATTRIBUTE IS A KIT-SELF LOCK. The ledger is now the ONLY place a ceiling
  # lives, so an armed tree whose .gitattributes does not give it merge=union reds: without the
  # attribute two ratified branches' acks conflict textually and the second one to land rewrites the
  # ceiling by hand, which is the defect this slice exists to close.
  mb_fixture_mk "$W/noattr" 2 10 10 fn
  rm -f "$W/noattr/.gitattributes"
  if _o=$(mb_verdict "$W/noattr" 0 2 0 20 20 0 2>&1); then
    echo "FAIL: selftest -- leg d-iv a tree without the merge=union attribute wrongly passed"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'merge=union' && printf '%s\n' "$_o" | grep -Fq '.gitattributes'; then
      echo "PASS: selftest -- leg d-iv a missing merge=union attribute reds and names .gitattributes"
    else echo "FAIL: selftest -- leg d-iv redded, but not on the missing merge attribute"; sfail=1; fi
  fi
  mb_fixture_mk "$W/withattr" 2 10 10 fn
  if mb_verdict "$W/withattr" 0 2 0 20 20 0 >/dev/null 2>&1; then
    echo "PASS: selftest -- leg d-iv the same tree WITH the attribute passes"
  else echo "FAIL: selftest -- leg d-iv a tree carrying the attribute was still refused"; sfail=1; fi
  # ...and the OVERRIDE. gitattributes is last-match-wins, so a later `-merge`/`merge=text` row for the
  # same path leaves the ledger WITHOUT union while a present-anywhere lock still reads green.
  for _ov in '-merge' 'merge=text'; do
    mb_fixture_mk "$W/override" 2 10 10 fn
    printf 'conformance/mass-acks.txt %s\n' "$_ov" >> "$W/override/.gitattributes"
    if _o=$(mb_verdict "$W/override" 0 2 0 20 20 0 2>&1); then
      echo "FAIL: selftest -- leg d-iv a LATER [$_ov] row disabled union and the tree still passed"; sfail=1
    else
      if printf '%s\n' "$_o" | grep -Fq 'last-match-wins'; then
        echo "PASS: selftest -- leg d-iv a later [$_ov] row overrides union and reds, naming the override"
      else echo "FAIL: selftest -- leg d-iv redded on the [$_ov] override, but not naming it: [$_o]"; sfail=1; fi
    fi
  done

  # leg d-v -- THE ROW'S OWN PROOF, on real git. Two branches each APPEND an ack; both merge orders
  # must exit 0, leave no conflict marker in the ledger, and derive the same ceiling. And union's
  # known failure mode — both sides appending the BYTE-IDENTICAL line — must still be caught, by the
  # ledger's exact-duplicate grammar rather than by the merge. Hermetic: no global/system git config,
  # HOME inside the workdir, the initial branch pinned rather than inherited from the user's default.
  mb_union_merge() {   # <dir> <ack-line-A> <ack-line-B> <first-branch> — merges the OTHER branch in
    _gd=$1; _gla=$2; _glb=$3; _gfirst=$4
    rm -rf "$_gd"; mkdir -p "$_gd/home"
    (
      GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_SYSTEM=/dev/null; GIT_CONFIG_NOSYSTEM=1
      HOME="$_gd/home"; XDG_CONFIG_HOME="$_gd/home"
      export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME
      mb_fixture_mk "$_gd/repo" 2 10 10 fn
      cd "$_gd/repo" || exit 9
      git init -q . >/dev/null 2>&1 || exit 9
      git symbolic-ref HEAD refs/heads/base >/dev/null 2>&1 || exit 9
      git config user.name mass-budget-selftest >/dev/null 2>&1 || exit 9
      git config user.email mb@example.invalid >/dev/null 2>&1 || exit 9
      git add -A >/dev/null 2>&1 || exit 9
      git commit -q -m base >/dev/null 2>&1 || exit 9
      git checkout -q -b brA >/dev/null 2>&1 || exit 9
      printf '%b\n' "$_gla" >> conformance/mass-acks.txt
      git commit -q -am ackA >/dev/null 2>&1 || exit 9
      git checkout -q base >/dev/null 2>&1 || exit 9
      git checkout -q -b brB >/dev/null 2>&1 || exit 9
      printf '%b\n' "$_glb" >> conformance/mass-acks.txt
      git commit -q -am ackB >/dev/null 2>&1 || exit 9
      case "$_gfirst" in
        brA) _gother=brB ;;
        *)   _gother=brA ;;
      esac
      git checkout -q "$_gfirst" >/dev/null 2>&1 || exit 9
      # `cmd; rc=$?` would ABORT the whole suite under `set -e` on a failing merge: no named FAIL, and
      # every later leg silently never runs. A condition context REPORTS the failure instead (the
      # arms below assert on it). Same reason for the trailing `|| :` here and on the calls.
      if git merge -q --no-edit "$_gother" >/dev/null 2>&1; then _mrc=0; else _mrc=$?; fi
      echo "MBMERGE_RC=$_mrc"
      if grep -Fq '<<<<<<<' conformance/mass-acks.txt; then echo "MBCONFLICT=yes"; else echo "MBCONFLICT=no"; fi
      _vo=$(mb_verdict "$_gd/repo" 0 2 0 20 20 0 2>&1) && echo "MBGATE_RC=0" || echo "MBGATE_RC=1"
      printf '%s\n' "$_vo" | grep -F 'MAX_LOGIC=' | head -1 || :
    )
  }
  if [ -z "$(command -v git 2>/dev/null || :)" ]; then
    echo "SKIP: selftest -- leg d-v NOT EXERCISED (git is not on PATH). A skip is reported as a SKIP: a skip wearing a PASS token would read here as a union-merge guarantee nothing ran to earn."
  else
    _mA=$(mb_union_merge "$W/gitAB" "2026-09-04\tlogic\t+5\tleg-d-v-ack-A" "2026-09-04\tlogic\t+7\tleg-d-v-ack-B" brA) || :
    _mB=$(mb_union_merge "$W/gitBA" "2026-09-04\tlogic\t+5\tleg-d-v-ack-A" "2026-09-04\tlogic\t+7\tleg-d-v-ack-B" brB) || :
    _cA=$(printf '%s\n' "$_mA" | grep -F 'MAX_LOGIC=' | head -1)
    _cB=$(printf '%s\n' "$_mB" | grep -F 'MAX_LOGIC=' | head -1)
    if printf '%s\n' "$_mA" | grep -Fq 'MBMERGE_RC=0' && printf '%s\n' "$_mB" | grep -Fq 'MBMERGE_RC=0' &&
       printf '%s\n' "$_mA" | grep -Fq 'MBCONFLICT=no' && printf '%s\n' "$_mB" | grep -Fq 'MBCONFLICT=no'; then
      echo "PASS: selftest -- leg d-v two appended acks merge in BOTH orders with no conflict marker"
    else echo "FAIL: selftest -- leg d-v an appended-ack merge conflicted or failed: A=[$_mA] B=[$_mB]"; sfail=1; fi
    if [ -n "$_cA" ] && [ "$_cA" = "$_cB" ] && printf '%s\n' "$_cA" | grep -Fq 'MAX_LOGIC=32 ' &&
       printf '%s\n' "$_mA" | grep -Fq 'MBGATE_RC=0'; then
      echo "PASS: selftest -- leg d-v both merge orders derive the SAME ceiling on the merged tree"
    else echo "FAIL: selftest -- leg d-v the merged trees disagree on the ceiling, or the gate redded: A=[$_cA] B=[$_cB]"; sfail=1; fi
    # leg d-iv (glob arm) -- THE OVERRIDE ONLY GIT CAN SEE, which is why the lock grades the EFFECTIVE
    # attribute. A later `conformance/* -merge` row never NAMES the ledger, so the path-keyed awk
    # fallback reads it as absent and stays green while git's applied value is `unset`. Needs a real
    # work tree, so it reuses the repo the merge helper just built (hermetic env re-applied).
    printf 'conformance/* -merge\n' >> "$W/gitAB/repo/.gitattributes"
    if _o=$( ( GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_SYSTEM=/dev/null; GIT_CONFIG_NOSYSTEM=1
               HOME="$W/gitAB/home"; XDG_CONFIG_HOME="$W/gitAB/home"
               export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME
               mb_verdict "$W/gitAB/repo" 0 2 0 20 20 0 ) 2>&1 ); then
      echo "FAIL: selftest -- leg d-iv a later GLOB \`conformance/* -merge\` row turned union off and the tree still passed"; sfail=1
    else
      if printf '%s\n' "$_o" | grep -Fq 'effective merge attribute' && printf '%s\n' "$_o" | grep -Fq '[unset]'; then
        echo "PASS: selftest -- leg d-iv a GLOB override reds on the EFFECTIVE attribute, naming its value [unset] (the path-keyed fallback is blind to it)"
      else echo "FAIL: selftest -- leg d-iv redded on the glob override, but not on the effective attribute with its value: [$_o]"; sfail=1; fi
    fi

    # ...and union's SUSPECTED failure mode, MEASURED RATHER THAN ASSUMED — the measurement REFUTED the
    # design (§3.1/§4 predicted "the doubled identical line reds on the exact-duplicate grammar").
    # It never gets that far: when BOTH sides make the byte-identical
    # change, git resolves it as ONE change before any merge driver is consulted, so the merged ledger
    # carries the line ONCE and the ceiling is raised ONCE. That is the safe direction, but it is not
    # what the design said, so the leg pins the BEHAVIOUR rather than the prediction: rc 0, gate GREEN,
    # and the derived ceiling 25 (genesis 20 + 5) — NOT 30. If union ever did double the line the
    # ceiling would read 30 and this leg reds; if the grammar caught it instead the gate rc would be 1
    # and this leg reds. The grammar is still the detector for a duplicate arriving any OTHER way (xiii).
    _mD=$(mb_union_merge "$W/gitdup" "2026-09-04\tlogic\t+5\tleg-d-v-identical" "2026-09-04\tlogic\t+5\tleg-d-v-identical" brA) || :
    if printf '%s\n' "$_mD" | grep -Fq 'MBMERGE_RC=0' && printf '%s\n' "$_mD" | grep -Fq 'MBGATE_RC=0' &&
       printf '%s\n' "$_mD" | grep -Fq 'MAX_LOGIC=25 ' && ! printf '%s\n' "$_mD" | grep -Fq 'MAX_LOGIC=30 '; then
      echo "PASS: selftest -- leg d-v a byte-identical ack on both branches lands ONCE (ceiling 25, not 30): git collapses identical changes before the union driver"
    else echo "FAIL: selftest -- leg d-v the identical ack on both branches did not land exactly once: [$_mD]"; sfail=1; fi
  fi

  # leg xxviii -- MASS-BUDGET-DOWNWARD: THE GLIDE ARM FIRES FOR REAL, on the actual kit tree with the
  # actual ratified target (not a fixture double), so the panel's re-stated condition is provably
  # wired rather than merely selftest-shaped. It pins the ARM, not the literal: asserting 34106 or a
  # frozen residual integer would break on every future logic-count change, which is the vacuity trap
  # this leg exists to avoid.
  _xroot=$(cd "$(dirname "$0")/.." && pwd)
  if [ ! -f "$_xroot/docs/ROADMAP-KIT.md" ] && [ ! -f "$_xroot/.github/workflows/golden-path.yml" ]; then
    echo "SKIP: selftest -- leg xxviii NOT EXERCISED (no kit marker: an adopter tree; the ratified glide target is graded on the kit tree only)"
  else
    _xo=$(mb_verdict "$_xroot" "$GENESIS_LINES" "$GENESIS_FILES" "$GENESIS_CENSUS" \
                      "$GENESIS_LOGIC" "$GENESIS_FIXTURE" "$HISTORICAL_LINES_ACKS" 2>&1) || :
    if printf '%s\n' "$_xo" | grep -Fq 'glide target:' &&
       printf '%s\n' "$_xo" | grep -Fq 'ADVISORY ONLY' &&
       printf '%s\n' "$_xo" | grep -Fq 'distance' &&
       ! printf '%s\n' "$_xo" | grep -Fq "not set (owner's)"; then
      echo "PASS: selftest -- leg xxviii the glide arm fires on the real tree with the ratified target: ADVISORY ONLY + a distance line, never the unset branch"
    else echo "FAIL: selftest -- leg xxviii the real-tree glide arm did not fire as advisory-with-distance: [$_xo]"; sfail=1; fi
  fi

  # legs xxix..xxxiii --GUARD-ADAPTER-MASS-REPORT (SWAS-147): the unbudgeted-surfaces block is ADVISORY.
  mb_ugen() { LC_ALL=C awk -v n="$2" 'BEGIN { for (i = 0; i < n; i++) print "line" }' > "$1"; }
  mb_ufixture() {   # <dir>: an armed kit fixture + scripts/ (5), scripts/fixtures/ (3), hooks (7), a baseline
    mb_fixture "$1" 4 10; mkdir -p "$1/scripts/fixtures" "$1/.claude/hooks"
    mb_ugen "$1/scripts/a.sh" 5; mb_ugen "$1/scripts/fixtures/x.txt" 3; mb_ugen "$1/.claude/hooks/h.sh" 7
    printf '\000\001\002\n' > "$1/scripts/blob.bin"
    printf 'v1.0.0\t2026-01-01\t5\t3\t7\tscripts/a.sh:5\t.claude/hooks/h.sh:7\tscripts/x.sh:1\tscripts/y.sh:1\tscripts/z.sh:1\n' > "$1/conformance/mass-release-baseline.txt"
  }
  mb_rcrun() { _rr=0; mb_verdict "$1" 0 4 0 40 0 0 2>&1 || _rr=$?; printf 'RC=%s\n' "$_rr"; }
  mb_vline() { grep -E '^conformance-mass-budget: (OK|FAIL -- see above)|^RC='; }

  mb_ufixture "$W/u1"
  _u1=$(mb_rcrun "$W/u1"); _u1v=$(printf '%s\n' "$_u1" | mb_vline)
  _ovk=$(printf '%s\n' "$_u1" | grep -n 'conformance-mass-budget: OK' | cut -d: -f1)
  _oun=$(printf '%s\n' "$_u1" | grep -n 'unbudgeted surfaces (ADVISORY ONLY' | cut -d: -f1)
  if printf '%s\n' "$_u1" | grep -Fq 'scripts/ 5 line(s) (+0)   scripts/fixtures/ 3 line(s) (+0)   .claude/hooks/ 7 line(s) (+0)' &&
     printf '%s\n' "$_u1" | grep -Fq 'since v1.0.0 (baseline recorded 2026-01-01)' &&
     printf '%s\n' "$_u1" | grep -Fq 'top files: .claude/hooks/h.sh 7 (+0) · scripts/a.sh 5 (+0)' &&
     printf '%s\n' "$_u1" | grep -Fq 'next-baseline' && [ -n "$_ovk" ] && [ -n "$_oun" ] && [ "$_oun" -gt "$_ovk" ]; then
    echo "PASS: selftest -- leg xxix the block prints AFTER the verdict line: totals (binary skipped, fixtures apart), the top files with deltas, next-baseline"
  else echo "FAIL: selftest -- leg xxix the unbudgeted block is absent or wrong: [$_u1]"; sfail=1; fi

  mb_ugen "$W/u1/scripts/a.sh" 90000
  _u2=$(mb_rcrun "$W/u1"); _u2v=$(printf '%s\n' "$_u2" | mb_vline)
  if [ "$_u2v" = "$_u1v" ] && printf '%s\n' "$_u2" | grep -Fq 'scripts/ 90000 line(s) (+89995)'; then
    echo "PASS: selftest -- leg xxx huge unbudgeted growth is REPORTED and the rc and verdict line are byte-identical"
  else echo "FAIL: selftest -- leg xxx the verdict moved with unbudgeted growth: [$_u1v] vs [$_u2v]"; sfail=1; fi

  _u3ok=1
  for _u3 in 'v1.0.0\t2026-01-01\t5\t3' 'v1.0.0\t2026-01-01\t05\t3\t7\ta.sh:1\tb.sh:1\tc.sh:1\td.sh:1\te.sh:1' 'v1\t2026-01-01\t5\t3\t7\ta.sh:1\tb.sh:1\tc.sh:1\td.sh:1\te.sh:1' 'v1.0.0\t2026-01-01\t5\t3\t7\ta.sh:x\tb.sh:1\tc.sh:1\td.sh:1\te.sh:1' ''; do
    mb_ufixture "$W/u3"; printf '%b\n' "$_u3" > "$W/u3/conformance/mass-release-baseline.txt"
    _o3=$(mb_rcrun "$W/u3"); _v3=$(printf '%s\n' "$_o3" | mb_vline)
    printf '%s\n' "$_o3" | grep -Fq 'unbudgeted surfaces (ADVISORY ONLY — never changes the verdict): N/A (' || _u3ok=0
    [ "$_v3" = "$_u1v" ] || _u3ok=0
  done
  rm -f "$W/u3/conformance/mass-release-baseline.txt"
  _o3=$(mb_rcrun "$W/u3"); _v3=$(printf '%s\n' "$_o3" | mb_vline)
  printf '%s\n' "$_o3" | grep -Fq 'N/A (conformance/mass-release-baseline.txt is missing' || _u3ok=0
  [ "$_v3" = "$_u1v" ] || _u3ok=0
  if [ "$_u3ok" -eq 1 ]; then
    echo "PASS: selftest -- leg xxxi a malformed (short, octal-looking, bad tag, bad size, empty) or missing baseline prints N/A and leaves the rc and verdict line unchanged"
  else echo "FAIL: selftest -- leg xxxi a bad baseline did not print N/A with an unchanged verdict (last: [$_o3])"; sfail=1; fi

  mb_ufixture "$W/u4"
  _u4=$(mb_rcrun "$W/u4"); _u4v=$(printf '%s\n' "$_u4" | mb_vline)
  _u5=$( ( mb_unbudgeted() { exit 7; }; mb_rcrun "$W/u4" ) 2>&1 ); _u5v=$(printf '%s\n' "$_u5" | mb_vline)
  _u6=$( ( mb_unbudgeted() { _z=$((1/0)); }; mb_rcrun "$W/u4" ) 2>&1 ); _u6v=$(printf '%s\n' "$_u6" | mb_vline)
  if [ -n "$_u4v" ] && [ "$_u5v" = "$_u4v" ] && [ "$_u6v" = "$_u4v" ]; then
    echo "PASS: selftest -- leg xxxii mb_unbudgeted shadowed by exit 7 and by illegal arithmetic leaves mb_verdict's rc and OK/FAIL line byte-identical"
  else echo "FAIL: selftest -- leg xxxii a crashing mb_unbudgeted moved the verdict: [$_u4v] / exit7 [$_u5v] / arith [$_u6v]"; sfail=1; fi

  mb_ufixture "$W/u7"; rm -f "$W/u7/docs/ROADMAP-KIT.md"
  _u7=$(mb_rcrun "$W/u7")
  if printf '%s\n' "$_u7" | grep -Fq 'N/A: conformance-mass-budget' && ! printf '%s\n' "$_u7" | grep -Fq 'unbudgeted'; then
    echo "PASS: selftest -- leg xxxiii the block never prints in an adopter tree"
  else echo "FAIL: selftest -- leg xxxiii the block printed (or the gate did not stand down) in an adopter tree: [$_u7]"; sfail=1; fi

  # leg xxxiv -- the baseline data file never ships: export-ignored AND on adopter-export's absence list.
  if [ ! -f "$_xroot/docs/ROADMAP-KIT.md" ] && [ ! -f "$_xroot/.github/workflows/golden-path.yml" ]; then
    echo "SKIP: selftest -- leg xxxiv NOT EXERCISED (no kit marker: an adopter tree carries neither the attribute nor the file)"
  elif grep -Eq '^conformance/mass-release-baseline\.txt[[:space:]]+export-ignore' "$_xroot/.gitattributes" &&
       grep -Eq 'for p in .*conformance/mass-release-baseline\.txt' "$_xroot/scripts/adopter-export.sh"; then
    echo "PASS: selftest -- leg xxxiv the baseline data file is export-ignored and on the adopter-export absence list"
  else echo "FAIL: selftest -- leg xxxiv the baseline data file is not export-ignored or not on the adopter-export absence list"; sfail=1; fi

  # ═══ SWAS-281 (CI-TIME-BUDGET) legs ci-b1 .. ci-b20: the four CI-time counts (rows, cells, legs, jobs), the genesis lock, the ledger grammar ═══
  # Each leg is a design-promised control (design section 9, B-numbers). Mutants are function shadows in a subshell: the production function is
  # replaced by the wrong one and the leg asserts the fixture SEES it (a mutant the fixture cannot see would make the control vacuous).
  unset GITHUB_EVENT_NAME GITHUB_BASE_REF
  _cib_save_heavy=$MB_HEAVY_CHECKS; MB_HEAVY_CHECKS="hv.sh"; _cib_save_cm=$MB_CELLS_MODE; MB_CELLS_MODE=list   # the stub listing stands in for the ~2 min real one
  cib_fix() {   # <dir> <control-rows> <non-control-rows> <cells> <jobs-total>: an armed kit fixture with verify.sh, a cells/jobs/legs stub each
    mb_fixture "$1" 2 5
    : > "$1/conformance/verify.sh"
    _cj=0; while [ "$_cj" -lt "$2" ]; do printf 'check control c%s sh x\n' "$_cj" >> "$1/conformance/verify.sh"; _cj=$((_cj + 1)); done
    _cj=0; while [ "$_cj" -lt "$3" ]; do printf 'check n%s sh x\n' "$_cj" >> "$1/conformance/verify.sh"; _cj=$((_cj + 1)); done
    : > "$1/conformance/cells.out"; _cj=0
    while [ "$_cj" -lt "$4" ]; do printf '%s\tcell %s\n' "$_cj" "$_cj" >> "$1/conformance/cells.out"; _cj=$((_cj + 1)); done
    printf '#!/bin/sh\nif [ "${1:-}" = --list-cells ]; then cat conformance/cells.out; exit "$(cat conformance/cells.rc 2>/dev/null || echo 0)"; fi\nexit 2\n' > "$1/conformance/agent-autonomy.sh"
    printf 'a.yml j 1\ntotal %s\n' "$5" > "$1/conformance/jobs.out"
    printf '#!/bin/sh\nif [ "${1:-}" = --count-legs ]; then cat conformance/jobs.out; exit "$(cat conformance/jobs.rc 2>/dev/null || echo 0)"; fi\nexit 2\n' > "$1/conformance/ci-gates.sh"
    printf 'l1\nl2\nl3\n' > "$1/conformance/legs.out"
    printf '#!/bin/sh\nif [ "${1:-}" = --list-legs ]; then cat conformance/legs.out; exit 0; fi\nexit 2\n' > "$1/conformance/hv.sh"
  }
  cib_v() { mb_verdict "$1" 0 99 999 99999 99999 0 "$2" 2>&1; }   # <dir> "<rows cells legs jobs genesis>" -> output; the caller reads rc
  cib_red() {   # <leg> <dir> <genesis> <needle> <what>: the verdict must be RED and name <needle>
    if _co=$(cib_v "$2" "$3"); then echo "FAIL: selftest -- leg $1 $5 was GREEN: [$_co]"; sfail=1
    elif printf '%s\n' "$_co" | grep -Fq -- "$4"; then echo "PASS: selftest -- leg $1 $5 reds and names [$4]"
    else echo "FAIL: selftest -- leg $1 $5 redded without naming [$4]: [$_co]"; sfail=1; fi
  }
  cib_green() { # <leg> <dir> <genesis> <needle> <what>
    if _co=$(cib_v "$2" "$3") && printf '%s\n' "$_co" | grep -Fq -- "$4"; then echo "PASS: selftest -- leg $1 $5 is green and shows [$4]"
    else echo "FAIL: selftest -- leg $1 $5 was not green with [$4]: [$_co]"; sfail=1; fi
  }

  # ci-b1 -- `rows` counts the non-control rows exactly: +1 reds with the remedy, a matching ack greens, double-charging control rows is seen.
  cib_fix "$W/b1" 3 2 5 3
  cib_green ci-b1 "$W/b1" "2 5 3 3" "rows 2/2" "3 control + 2 non-control rows against genesis 2"
  cib_fix "$W/b1b" 3 3 5 3
  cib_red ci-b1 "$W/b1b" "2 5 3 3" "rows 3/2, over by 1" "a third non-control row without an ack"
  mb_ack "$W/b1b" "2026-10-24\trows\t+1\tleg-ci-b1-declared"
  cib_green ci-b1 "$W/b1b" "2 5 3 3" "leg-ci-b1-declared" "the same row WITH a matching ack"
  if ( mb_count_rows() { LC_ALL=C grep -c '^check ' "$1/conformance/verify.sh"; }; cib_v "$W/b1" "2 5 3 3" ) >/dev/null; then
    echo "FAIL: selftest -- leg ci-b1 MUTANT count-every-check-row (double-charging the control rows) stayed green on the fixture"; sfail=1
  else echo "PASS: selftest -- leg ci-b1 MUTANT count-every-check-row reds on the fixture (the 3 control rows would be charged twice)"; fi

  # ci-b2 -- `cells` fails closed: an exit 1, an empty listing and a malformed line each FAIL naming the battery, never 0.
  cib_fix "$W/b2" 1 2 5 3; printf '1\n' > "$W/b2/conformance/cells.rc"
  cib_red ci-b2 "$W/b2" "2 5 3 3" "agent-autonomy.sh" "a --list-cells that exits 1"
  cib_fix "$W/b2e" 1 2 0 3
  cib_red ci-b2 "$W/b2e" "2 5 3 3" "agent-autonomy.sh" "an empty listing"
  cib_fix "$W/b2m" 1 2 5 3; printf 'no-tab-here\n' >> "$W/b2m/conformance/cells.out"
  cib_red ci-b2 "$W/b2m" "2 5 3 3" "agent-autonomy.sh" "a line with no TAB"
  if ( mb_count_cells() { echo 0; }; cib_v "$W/b2" "2 5 3 3" ) >/dev/null; then
    echo "PASS: selftest -- leg ci-b2 MUTANT treat-a-failed-listing-as-0 would be GREEN where the real gate is red, so the fixture can tell them apart"
  else echo "FAIL: selftest -- leg ci-b2 the failed-listing fixture cannot tell treat-as-0 from fail-closed"; sfail=1; fi

  # ci-b3 -- `cells` counts the listing: N labels read N, one more reds without an ack.
  cib_fix "$W/b3" 1 2 5 3
  cib_green ci-b3 "$W/b3" "2 5 3 3" "cells 5/5" "a 5-label listing against genesis 5"
  cib_fix "$W/b3b" 1 2 6 3
  cib_red ci-b3 "$W/b3b" "2 5 3 3" "cells 6/5, over by 1" "a 6th cell without an ack"

  # ci-b4 -- the cells fallback (listing measured ~2 min against the design's 30 s): the default run lists nothing and says N/A (never a pass, never
  # red); a count supplied by the join job is graded; the CLI refuses a missing, non-numeric or zero count rather than falling back to N/A.
  MB_CELLS_MODE=na
  cib_green ci-b4 "$W/b2" "2 5 3 3" "cells N/A in this run (NOT a pass)" "the default run with an UNLISTABLE battery (nothing is listed)"
  MB_CELLS_MODE=5; cib_green ci-b4 "$W/b3" "2 5 3 3" "cells 5/5" "a supplied count of 5 against genesis 5"
  MB_CELLS_MODE=6; cib_red ci-b4 "$W/b3" "2 5 3 3" "cells 6/5, over by 1" "a supplied count of 6"
  MB_CELLS_MODE=list
  _ca_nl=$(printf '5\n7')
  for _ca in "" "abc" "0" "-3" "4x" "1 2" "$_ca_nl" "12345678901"; do
    if sh "$0" --grade-cells "$_ca" workspace >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b4 --grade-cells [$_ca] was accepted"; sfail=1
    else echo "PASS: selftest -- leg ci-b4 --grade-cells [$_ca] is refused (exit non-zero)"; fi
  done
  for _cv in "" bogus Workspace; do
    if sh "$0" --grade-cells 5 "$_cv" >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b4 --grade-cells 5 with variant [$_cv] was accepted"; sfail=1
    else echo "PASS: selftest -- leg ci-b4 --grade-cells 5 with variant [$_cv] is refused (each variant has its own genesis)"; fi
  done
  if sh "$0" --grade-cells 5 >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b4 --grade-cells 5 with no variant was accepted"; sfail=1
  else echo "PASS: selftest -- leg ci-b4 --grade-cells 5 with no variant is refused"; fi
  if sh "$0" --grade-cells >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b4 --grade-cells with no count was accepted"; sfail=1
  else echo "PASS: selftest -- leg ci-b4 --grade-cells with no count is refused"; fi

  # ci-b5 -- `legs` is graded and honest: a listed check without --list-legs FAILs; a leg run but not listed (and the reverse) FAILs.
  cib_fix "$W/b5" 1 2 5 3
  cib_green ci-b5 "$W/b5" "2 5 3 3" "legs 3/3" "a listed heavy check answering --list-legs (3 labels)"
  printf '#!/bin/sh\nexit 2\n' > "$W/b5/conformance/hv.sh"
  cib_red ci-b5 "$W/b5" "2 5 3 3" "hv.sh" "a listed heavy check with no --list-legs"
  printf 'a\nb\nc\n' > "$W/lg-listed.txt"; printf 'a\nb\nc\nd\n' > "$W/lg-ran-extra.txt"; printf 'a\nb\n' > "$W/lg-ran-short.txt"
  if mb_legs_crosscheck "$W/lg-listed.txt" "$W/lg-listed.txt" >/dev/null 2>&1 &&
     ! mb_legs_crosscheck "$W/lg-listed.txt" "$W/lg-ran-extra.txt" >/dev/null 2>&1 &&
     ! mb_legs_crosscheck "$W/lg-listed.txt" "$W/lg-ran-short.txt" >/dev/null 2>&1; then
    echo "PASS: selftest -- leg ci-b5 a selftest that runs a leg --list-legs omits, or omits a listed leg, reds; an exact match is green"
  else echo "FAIL: selftest -- leg ci-b5 the legs cross-check is wrong in at least one direction"; sfail=1; fi

  # ci-b5w -- the WRAPPER itself (mb_selftest_checked), driven with a stub selftest that runs leg `a` while --list-legs names `a` and `b`: it must
  # red; with the cross-check shadowed to a pass (the wrapper mutant) it would be green, so the fixture can tell them apart.
  # (the stub's output line is spelled in two pieces so mb_list_legs, which scans this file's text, does not list the stub's leg `a`)
  if ( selftest() { echo "PASS: selftest -- le""g a x"; exit 0; }; mb_list_legs() { printf 'a\nb\n'; }; mb_selftest_checked ) >/dev/null 2>&1; then
    echo "FAIL: selftest -- leg ci-b5w the wrapper stayed green with a listed leg that never ran"; sfail=1
  else echo "PASS: selftest -- leg ci-b5w the wrapper reds on a listed leg that never ran"; fi
  if ( selftest() { echo "PASS: selftest -- le""g a x"; exit 0; }; mb_list_legs() { printf 'a\nb\n'; }; mb_legs_crosscheck() { return 0; }; mb_selftest_checked ) >/dev/null 2>&1; then
    echo "PASS: selftest -- leg ci-b5w MUTANT cross-check-always-passes would be GREEN where the real wrapper is red, so the fixture sees it"
  else echo "FAIL: selftest -- leg ci-b5w the wrapper fixture cannot tell the always-pass cross-check from the real one"; sfail=1; fi

  # ci-b6 -- the grammar takes rows/cells/legs/jobs and still rejects a misspelt surface; the existing ledger stays green.
  for _cs in rows cells legs jobs; do
    printf '# l\n2026-10-24\t%s\t+3\tgrammar leg\n' "$_cs" > "$W/g.txt"
    if mb_ledger_check "$W/g.txt" >/dev/null 2>&1; then echo "PASS: selftest -- leg ci-b6 an ack on surface [$_cs] is grammatical"
    else echo "FAIL: selftest -- leg ci-b6 surface [$_cs] was refused by the grammar"; sfail=1; fi
  done
  printf '2026-10-24\tcell\t+3\tmisspelt\n' > "$W/g.txt"
  if mb_ledger_check "$W/g.txt" >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b6 a misspelt surface [cell] was accepted"; sfail=1
  else echo "PASS: selftest -- leg ci-b6 a misspelt surface [cell] is refused"; fi
  if [ -f "$_xroot/conformance/mass-acks.txt" ] && mb_ledger_check "$_xroot/conformance/mass-acks.txt" >/dev/null 2>&1; then
    echo "PASS: selftest -- leg ci-b6 the real ledger still passes the extended grammar"
  elif [ ! -f "$_xroot/conformance/mass-acks.txt" ]; then echo "SKIP: selftest -- leg ci-b6 real ledger NOT EXERCISED (no ledger in this tree)"
  else echo "FAIL: selftest -- leg ci-b6 the real ledger fails the extended grammar"; sfail=1; fi

  # ci-b7 -- no cached ceiling for a new surface: the source lock reds on a MAX_<new surface> literal in each direct form.
  for _lf in 'MAX_CELLS=4186' 'MAX_ROWS="20"' "MAX_LEGS='3'" 'readonly MAX_JOBS=26' 'export MAX_CELLS=+4186'; do
    printf '#!/bin/sh\n%s\n' "$_lf" > "$W/lit4.sh"
    if mb_no_literal_max "$W/lit4.sh" >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b7 the source lock MISSED [$_lf]"; sfail=1
    else echo "PASS: selftest -- leg ci-b7 the source lock catches [$_lf]"; fi
  done

  # ci-b8 -- the genesis is the count on the introducing head, printed with `0 ack(s)` per new surface.
  cib_fix "$W/b8" 1 2 5 3
  _o8=$(cib_v "$W/b8" "2 5 3 3" || true)
  for _s8 in ROWS=2 CELLS=5 LEGS=3 JOBS=3; do
    if printf '%s\n' "$_o8" | grep -Fq "MAX_${_s8%=*}=${_s8#*=} = genesis ${_s8#*=} + (+0) over 0 ack(s)"; then echo "PASS: selftest -- leg ci-b8 MAX_${_s8%=*} prints its genesis ${_s8#*=} and 0 ack(s)"
    else echo "FAIL: selftest -- leg ci-b8 MAX_${_s8%=*} derivation line missing: [$_o8]"; sfail=1; fi
  done

  # ci-b9 -- removal is never punished: one row fewer with no ack is green; a negative ack lowers the ceiling, so growth back reds.
  cib_fix "$W/b9" 1 1 5 3
  cib_green ci-b9 "$W/b9" "2 5 3 3" "rows 1/2" "one row fewer than genesis and no ack"
  mb_ack "$W/b9" "2026-10-24\trows\t-1\tleg-ci-b9-cut"
  cib_green ci-b9 "$W/b9" "2 5 3 3" "rows 1/1" "a negative ack lowers the ceiling to the new count"
  cib_fix "$W/b9b" 1 2 5 3; mb_ack "$W/b9b" "2026-10-24\trows\t-1\tleg-ci-b9-cut"
  cib_red ci-b9 "$W/b9b" "2 5 3 3" "rows 2/1, over by 1" "growth back past a lowered ceiling"

  # ci-b15 -- the cells count is one definition: the listing's line count equals the join's `listed` set on a fixture WITH follows lines,
  # the join's own pipeline text is still in agent-autonomy.sh (so the coupling cannot drift silently), and a count that parses is seen.
  cib_fix "$W/b15" 1 2 4 3
  printf '4\tcell 4\tfollows\t3\n' >> "$W/b15/conformance/cells.out"
  printf '0\tcell 0\n' >> "$W/b15/conformance/cells.out"   # a duplicated line: the join's `sort -u` makes ONE cell of it
  _lc15=$(mb_count_cells "$W/b15"); _jl15=$(awk -F'\t' '{ print $1 "\t" $2 }' "$W/b15/conformance/cells.out" | LC_ALL=C sort -u | awk 'END { print NR }')
  if [ "$_lc15" = 5 ] && [ "$_jl15" = 5 ]; then echo "PASS: selftest -- leg ci-b15 the count (5 of 6 lines: one a follows line, one a duplicate) equals the join's deduplicated listed-set count"
  else echo "FAIL: selftest -- leg ci-b15 count [$_lc15] and the join's listed count [$_jl15] disagree on a follows+duplicate fixture"; sfail=1; fi
  if ( mb_count_cells() { awk 'END { print NR }' "$1/conformance/cells.out"; }; [ "$(mb_count_cells "$W/b15")" = "$_jl15" ] ); then
    echo "FAIL: selftest -- leg ci-b15 MUTANT count-raw-lines agrees with the join, so the duplicate fixture cannot see it"; sfail=1
  else echo "PASS: selftest -- leg ci-b15 MUTANT count-raw-lines miscounts the duplicate fixture (6 against the join's 5) and is seen"; fi
  # Declared deviation (design B15): the byte-identical-across-dims check is replaced by ONE GENESIS PER CI VARIANT, because CI measured 4168
  # (workspace) against 4167 (tmpclone): the listing is not identical across dims, so each variant is graded against its own origin.
  if [ -f "$_xroot/conformance/agent-autonomy.sh" ]; then
    if grep -Fq 'awk -F'"'"'\t'"'"' '"'"'{ print $1 "\t" $2 }'"'"' "$_jr_list" | LC_ALL=C sort -u > "$_jr_d/listed"' "$_xroot/conformance/agent-autonomy.sh"; then
      echo "PASS: selftest -- leg ci-b15 the join still builds its listed set from the --list-cells output by that exact pipeline (the coupling holds)"
    else echo "FAIL: selftest -- leg ci-b15 agent-autonomy.sh --join no longer builds its listed set by the pipeline this leg pins; re-derive the cells definition"; sfail=1; fi
    # ...and the join prints that set's size (the count the CI step after the join hands to --grade-cells), after a green join, from aa_join_main.
    if grep -Fq 'echo "agent-autonomy --join: listed cells: $_jr_ng"' "$_xroot/conformance/agent-autonomy.sh"; then
      echo "PASS: selftest -- leg ci-b15 the join still prints its listed-set size for the --grade-cells step (the line the workflow extracts)"
    else echo "FAIL: selftest -- leg ci-b15 agent-autonomy.sh --join no longer prints 'listed cells: N'; the guard-battery join's --grade-cells step would extract nothing"; sfail=1; fi
  else echo "SKIP: selftest -- leg ci-b15 join coupling NOT EXERCISED (no agent-autonomy.sh in this tree)"; fi

  # ci-b16 -- an indented `check` call outside the selftest region is a FAIL naming the line; at column 0 it is counted.
  cib_fix "$W/b16" 1 2 5 3; printf '  check hidden sh x\n' >> "$W/b16/conformance/verify.sh"
  cib_red ci-b16 "$W/b16" "2 5 3 3" "verify.sh line 4" "an indented check call"
  cib_fix "$W/b16b" 1 2 5 3; printf 'check visible sh x\n' >> "$W/b16b/conformance/verify.sh"
  cib_red ci-b16 "$W/b16b" "2 5 3 3" "rows 3/2" "the same call at column 0 is counted"
  # ...the lock is LIVE on a verify.sh that HAS a selftest block before its registry rows (the real shape): an indented check INSIDE the block is
  # skipped, one AFTER its `fi` reds. (The first version stopped at the selftest marker, so on the real file it scanned nothing.)
  cib_fix "$W/b16c" 1 2 5 3
  { printf 'if [ "${1:-}" = "--selftest" ]; then\n  check inside-selftest sh x\nfi\n'; cat "$W/b16c/conformance/verify.sh"; printf '  check hidden-after-block sh x\n'; } > "$W/b16c/v.new"
  mv "$W/b16c/v.new" "$W/b16c/conformance/verify.sh"
  cib_red ci-b16 "$W/b16c" "2 5 3 3" "verify.sh line 7" "an indented check AFTER a selftest block (the block's own indented check is skipped)"
  cib_fix "$W/b16d" 1 2 5 3
  { printf 'if [ "${1:-}" = "--selftest" ]; then\n  check inside-selftest sh x\nfi\n'; cat "$W/b16d/conformance/verify.sh"; } > "$W/b16d/v.new"
  mv "$W/b16d/v.new" "$W/b16d/conformance/verify.sh"
  cib_green ci-b16 "$W/b16d" "2 5 3 3" "rows 2/2" "an indented check only INSIDE the selftest block"
  # ...a MARKED REPLAY (an indented `check <kind> <name> ...  # mb:replay <name>`) is SEEN and JUDGED: it is accepted only when the marker name is
  # the call's own name and exactly one column-0 row of that kind and name exists. The unmarked b16/b16c cells above stay the negatives.
  cib_fix "$W/b16e" 1 2 5 3; printf '  check control c0 sh x  # mb:replay c0\n' >> "$W/b16e/conformance/verify.sh"
  cib_green ci-b16 "$W/b16e" "2 5 3 3" "rows 2/2" "a marked replay of the one column-0 row c0 (the row count is unchanged)"
  cib_green ci-b16 "$W/b16e" "2 5 3 3" "replay(s) seen and judged: c0 ×1" "the same marked replay, which the lock prints as seen and judged"
  cib_fix "$W/b16f" 1 2 5 3; printf '  check control zz sh x  # mb:replay zz\n' >> "$W/b16f/conformance/verify.sh"
  cib_red ci-b16 "$W/b16f" "2 5 3 3" "honoured only when" "a marked replay with NO column-0 twin"
  cib_fix "$W/b16g" 1 2 5 3; printf '  check control c0 sh x  # mb:replay other\n' >> "$W/b16g/conformance/verify.sh"
  cib_red ci-b16 "$W/b16g" "2 5 3 3" "honoured only when" "a marker name that differs from the call's name"
  cib_fix "$W/b16h" 1 2 5 3; printf 'check control c0 sh x\n  check control c0 sh x  # mb:replay c0\n' >> "$W/b16h/conformance/verify.sh"
  cib_red ci-b16 "$W/b16h" "2 5 3 3" "honoured only when" "a marked replay whose column-0 twin is not unique (two rows)"
  # ...a marked line must be ONE check: a second command on it would add a row the column-0 count never sees (H1); a wrong KIND is no twin (F-1).
  cib_fix "$W/b16i" 1 2 5 3; printf '  check control c0 sh x; check new n sh y  # mb:replay c0\n' >> "$W/b16i/conformance/verify.sh"
  cib_red ci-b16 "$W/b16i" "2 5 3 3" "honoured only when" "a marked replay chained with ; to a second check (an uncounted row)"
  cib_fix "$W/b16j" 1 2 5 3; printf '  check control c0 sh x && check new n sh y  # mb:replay c0\n' >> "$W/b16j/conformance/verify.sh"
  cib_red ci-b16 "$W/b16j" "2 5 3 3" "honoured only when" "a marked replay chained with && to a second check (an uncounted row)"
  cib_fix "$W/b16k" 1 2 5 3; printf '  check other c0 sh x  # mb:replay c0\n' >> "$W/b16k/conformance/verify.sh"
  cib_red ci-b16 "$W/b16k" "2 5 3 3" "honoured only when" "a WRONG-KIND replay (other c0) beside the column-0 control c0 row"
  cib_fix "$W/b16l" 1 2 5 3; printf '  check control c0 sh x > "$out"   # mb:replay c0\n' >> "$W/b16l/conformance/verify.sh"
  cib_green ci-b16 "$W/b16l" "2 5 3 3" "replay(s) seen and judged: c0 ×1" "a marked replay with a quoted > redirect (the real verify.sh shape)"
  # ...the fail-closed arm (F-2): a scan that yields NO verdict is a FAIL naming it, never a count. A PATH-shadowed awk that prints nothing drives it.
  cib_fix "$W/b16n" 1 2 5 3; mkdir "$W/b16n/bin"; printf '#!/bin/sh\nexit 0\n' > "$W/b16n/bin/awk"; chmod +x "$W/b16n/bin/awk"
  if _co=$( PATH="$W/b16n/bin:$PATH"; mb_count_rows "$W/b16n" 2>&1 ); then echo "FAIL: selftest -- leg ci-b16 a scan with no verdict was ACCEPTED: [$_co]"; sfail=1
  elif printf '%s\n' "$_co" | grep -Fq "returned no verdict"; then echo "PASS: selftest -- leg ci-b16 a scan with no verdict reds (rc 1) and names [returned no verdict]"
  else echo "FAIL: selftest -- leg ci-b16 a scan with no verdict redded without naming it: [$_co]"; sfail=1; fi
  if [ -f "$_xroot/docs/ROADMAP-KIT.md" ] || [ -f "$_xroot/.github/workflows/golden-path.yml" ]; then
    if _rr=$(mb_count_rows "$_xroot") && mb_marker_ok "$_rr" && [ "$_rr" -gt 0 ]; then echo "PASS: selftest -- leg ci-b16r the lock is live on the REAL verify.sh and finds no hidden indented row ($_rr non-control rows)"
    else echo "FAIL: selftest -- leg ci-b16r the real verify.sh reds the column-0 lock or yields no rows: [$_rr]"; sfail=1; fi
  else echo "SKIP: selftest -- leg ci-b16r real-tree row lock NOT EXERCISED (no kit marker)"; fi

  # ci-b17 -- `jobs` reads ci-gates.sh --count-legs (its own legs are B4/B17 in ci-gates.sh --selftest): the total is graded, a refusal is a FAIL.
  cib_fix "$W/b17" 1 2 5 3
  cib_green ci-b17 "$W/b17" "2 5 3 3" "jobs 3/3" "the counter's total"
  printf '1\n' > "$W/b17/conformance/jobs.rc"; printf 'FAIL: count-legs -- x.yml job [u] is a reusable-workflow uses: job\n' > "$W/b17/conformance/jobs.out"
  cib_red ci-b17 "$W/b17" "2 5 3 3" "reusable-workflow" "a counter refusal (a FAIL, never 0)"
  cib_fix "$W/b17b" 1 2 5 4
  cib_red ci-b17 "$W/b17b" "2 5 3 3" "jobs 4/3, over by 1" "a fourth runner job"
  if [ -f "$_xroot/docs/ROADMAP-KIT.md" ] || [ -f "$_xroot/.github/workflows/golden-path.yml" ]; then
    if _jo=$(cd "$_xroot" && sh conformance/ci-gates.sh --count-legs "$_xroot" 2>&1) && printf '%s\n' "$_jo" | grep -Eq '^total [0-9]+$'; then
      echo "PASS: selftest -- leg ci-b17 the real tree's workflows all parse and total (count-legs rc 0)"
    else echo "FAIL: selftest -- leg ci-b17 count-legs refused the real tree: [$_jo]"; sfail=1; fi
  else echo "SKIP: selftest -- leg ci-b17 real-tree count NOT EXERCISED (no kit marker)"; fi

  # ci-b18 -- a PR cannot move its own genesis: a changed GENESIS_ reds, an unchanged one is green, the introducing diff is allowed once.
  cib_g() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
  _gdir="$W/b18"; rm -rf "$_gdir"; mkdir -p "$_gdir/conformance"
  printf 'GENESIS_LOGIC=100\nGENESIS_CELLS=10\n' > "$_gdir/conformance/conformance-mass-budget.sh"
  cib_g init -q "$_gdir" && cib_g -C "$_gdir" symbolic-ref HEAD refs/heads/main && cib_g -C "$_gdir" add -A && cib_g -C "$_gdir" commit -q -m base \
    && cib_g -C "$_gdir" update-ref refs/remotes/origin/main HEAD && cib_g -C "$_gdir" checkout -q -b pr
  _gl() { ( GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main; mb_genesis_lock "$_gdir" 2>&1 ); }
  if _o=$(_gl) && printf '%s\n' "$_o" | grep -Fq 'unchanged'; then echo "PASS: selftest -- leg ci-b18 an unchanged genesis is green"
  else echo "FAIL: selftest -- leg ci-b18 an unchanged genesis was not green: [$_o]"; sfail=1; fi
  printf 'GENESIS_LOGIC=100\nGENESIS_CELLS=11\n' > "$_gdir/conformance/conformance-mass-budget.sh"; cib_g -C "$_gdir" commit -q -am move
  if _o=$(_gl); then echo "FAIL: selftest -- leg ci-b18 a PR that moved GENESIS_CELLS 10 -> 11 was green: [$_o]"; sfail=1
  elif printf '%s\n' "$_o" | grep -Fq 'GENESIS_CELLS'; then echo "PASS: selftest -- leg ci-b18 a moved GENESIS_CELLS reds and names it"
  else echo "FAIL: selftest -- leg ci-b18 the red did not name GENESIS_CELLS: [$_o]"; sfail=1; fi
  printf 'GENESIS_LOGIC=100\nGENESIS_CELLS=10\nGENESIS_ROWS=7\n' > "$_gdir/conformance/conformance-mass-budget.sh"; cib_g -C "$_gdir" commit -q -am set
  if _o=$(_gl) && printf '%s\n' "$_o" | grep -Fq 'GENESIS_ROWS absent at the merge-base'; then echo "PASS: selftest -- leg ci-b18 the genesis-setting diff (GENESIS_ROWS absent at base) is allowed once"
  else echo "FAIL: selftest -- leg ci-b18 the introducing diff was refused: [$_o]"; sfail=1; fi
  printf 'GENESIS_LOGIC=100\nGENESIS_CELLS=10\nGENESIS_FIXTURE=5\n' > "$_gdir/conformance/conformance-mass-budget.sh"; cib_g -C "$_gdir" commit -q -am other
  if _o=$(_gl); then echo "FAIL: selftest -- leg ci-b18 a NEW non-CI GENESIS_FIXTURE absent at base was allowed: [$_o]"; sfail=1
  else echo "PASS: selftest -- leg ci-b18 only the four introduced names may be absent at the base; another new GENESIS_ reds"; fi
  printf 'GENESIS_CELLS=10\n' > "$_gdir/conformance/conformance-mass-budget.sh"; cib_g -C "$_gdir" commit -q -am drop
  if _o=$(_gl); then echo "FAIL: selftest -- leg ci-b18 a deleted GENESIS_LOGIC was allowed: [$_o]"; sfail=1
  else echo "PASS: selftest -- leg ci-b18 a GENESIS_ line deleted at head reds"; fi
  if _o=$( GITHUB_EVENT_NAME=push mb_genesis_lock "$_gdir" 2>&1 ) && printf '%s\n' "$_o" | grep -Fq 'N/A'; then echo "PASS: selftest -- leg ci-b18 on a push event the lock prints N/A and does not red"
  else echo "FAIL: selftest -- leg ci-b18 the push-event arm did not N/A: [$_o]"; sfail=1; fi

  # ci-b18f -- the genesis-FORM lock: any GENESIS_ assignment but the canonical column-0 bare-digits one, and any name assigned twice, reds.
  for _gf in '  GENESIS_ROWS=20' 'readonly GENESIS_ROWS=20' 'export GENESIS_ROWS=20' 'GENESIS_ROWS=$((20))' 'GENESIS_ROWS="20"' 'declare -r GENESIS_ROWS=20'; do
    printf '#!/bin/sh\n%s\n' "$_gf" > "$W/gf.sh"
    if mb_genesis_forms "$W/gf.sh" >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b18f the genesis-form lock MISSED [$_gf]"; sfail=1
    else echo "PASS: selftest -- leg ci-b18f the genesis-form lock catches [$_gf]"; fi
  done
  printf '#!/bin/sh\nGENESIS_ROWS=20\nGENESIS_ROWS=21\n' > "$W/gf.sh"
  if mb_genesis_forms "$W/gf.sh" >/dev/null 2>&1; then echo "FAIL: selftest -- leg ci-b18f a name assigned twice (the later wins) was allowed"; sfail=1
  else echo "PASS: selftest -- leg ci-b18f a GENESIS_ name assigned twice reds"; fi
  printf '#!/bin/sh\nGENESIS_ROWS=20   # a comment\n# GENESIS_ROWS=99 in a comment\nGENESIS_CELLS_WORKSPACE=4\n' > "$W/gf.sh"
  if mb_genesis_forms "$W/gf.sh" >/dev/null 2>&1; then echo "PASS: selftest -- leg ci-b18f canonical lines (with a trailing comment, and a comment mention) pass"
  else echo "FAIL: selftest -- leg ci-b18f the form lock reds canonical lines (vacuously red)"; sfail=1; fi

  # ci-b20 -- slack is visible: a banked +10 ack with an unchanged count prints `10 free` on that surface.
  cib_fix "$W/b20" 1 2 5 3; mb_ack "$W/b20" "2026-10-24\trows\t+10\tleg-ci-b20-banked"
  cib_green ci-b20 "$W/b20" "2 5 3 3" "slack rows 10 free" "a +10 ack with an unchanged count"

  # ci-run -- the production run passes the four genesis values AND runs the genesis lock (a mutant that drops either would silently skip the surfaces).
  _runsrc=$(awk '/^run\(\) \{/ { p = 1 } p { print } p && /^}/ { exit }' "$0")
  _verdsrc=$(awk '/^mb_verdict\(\) \{/ { p = 1 } p { print } p && /^}/ { exit }' "$0")
  _runall=1
  for _rn in GENESIS_ROWS GENESIS_CELLS_WORKSPACE GENESIS_CELLS_TMPCLONE GENESIS_LEGS GENESIS_JOBS mb_genesis_forms; do case "$_runsrc" in *"$_rn"*) : ;; *) _runall=0 ;; esac; done
  case "$_runall" in
    1)
      case "$_verdsrc" in *'mb_ci_surfaces'*'mb_genesis_lock'*) echo "PASS: selftest -- leg ci-run run() passes the four CI-time genesis values, and mb_verdict then grades them and runs the genesis lock" ;;
        *) echo "FAIL: selftest -- leg ci-run mb_verdict does not call mb_ci_surfaces and mb_genesis_lock"; sfail=1 ;; esac ;;
    *) echo "FAIL: selftest -- leg ci-run run() does not pass the four CI-time genesis values to mb_verdict (the new surfaces would be skipped)"; sfail=1 ;;
  esac
  MB_HEAVY_CHECKS=$_cib_save_heavy; MB_CELLS_MODE=$_cib_save_cm

  [ "$sfail" -eq 0 ] && { echo "OK: conformance-mass-budget selftest"; exit 0; } || { echo "FAIL: conformance-mass-budget selftest"; exit 1; }
}

# ---------------------------------------------------------------------------- dispatch
run() {
  # THE SOURCE LOCK RUNS FIRST, on this script's OWN path, resolved BEFORE the cd (a bare `$0` would
  # be relative to the old cwd and the lock would then grade nothing — a lock that cannot see its
  # subject is worse than no lock, so mb_no_literal_max reds on an unreadable path rather than passing).
  _self=$(cd "$(dirname "$0")" && pwd)/${0##*/}
  cd "$(dirname "$0")/.."
  _rrc=0
  mb_no_literal_max "$_self" || _rrc=1
  mb_genesis_forms "$_self" || _rrc=1
  case "$MB_CELLS_VARIANT" in tmpclone) _rcg=$GENESIS_CELLS_TMPCLONE ;; *) _rcg=$GENESIS_CELLS_WORKSPACE ;; esac
  mb_verdict . "$GENESIS_LINES" "$GENESIS_FILES" "$GENESIS_CENSUS" \
               "$GENESIS_LOGIC" "$GENESIS_FIXTURE" "$HISTORICAL_LINES_ACKS" \
               "$GENESIS_ROWS $_rcg $GENESIS_LEGS $GENESIS_JOBS" || _rrc=1
  return "$_rrc"
}

# --selftest runs the legs in a subshell and then cross-checks them against --list-legs: a leg listed but never run, or run but not listed,
# reds (the same contract every heavy check on MB_HEAVY_CHECKS owes, SWAS-281 B5). --list-legs prints this script's own leg labels.
mb_selftest_checked() {
  _sw=$(mktemp -d) || { echo "FAIL: conformance-mass-budget selftest -- mktemp failed"; exit 1; }
  _swrc=0
  ( selftest ) > "$_sw/out" 2>&1 || _swrc=$?
  cat "$_sw/out"
  mb_list_legs "$0" > "$_sw/listed"
  LC_ALL=C sed -nE 's/^(PASS|FAIL|SKIP): selftest -- leg ([A-Za-z0-9.-]+) .*$/\2/p' "$_sw/out" | LC_ALL=C sort -u > "$_sw/ran"
  _swx=0
  mb_legs_crosscheck "$_sw/listed" "$_sw/ran" || _swx=1
  rm -rf "$_sw"
  if [ "$_swrc" -ne 0 ] || [ "$_swx" -ne 0 ]; then echo "FAIL: conformance-mass-budget selftest (legs rc=$_swrc, legs cross-check=$_swx)"; exit 1; fi
  exit 0
}

case "${1:-}" in
  --selftest)  mb_selftest_checked ;;
  --list-legs) mb_list_legs "$0"; exit 0 ;;
  --grade-cells)
    # the cells count supplied by the guard-battery join job (its listed-set size). FAIL-CLOSED on a missing, non-numeric or zero value: an
    # empty extraction in the workflow must red, never fall back to N/A.
    # `case`, never `grep -q`: grep grades line by line, so a value like "5<newline>x" would pass; a case pattern sees the WHOLE string.
    _gcbad=0
    [ "$#" -eq 3 ] || _gcbad=1
    case "${2:-}" in ''|0*|*[!0-9]*|??????????*) _gcbad=1 ;; esac
    if [ "$_gcbad" -ne 0 ]; then
      echo "conformance-mass-budget: FAIL -- --grade-cells needs a positive integer (the guard-battery join's listed-cells count) and a variant; got [$(printf '%s' "${2:-}" | mb_san)] [$(printf '%s' "${3:-}" | mb_san)]. An unreadable count is a failure, never N/A." >&2; exit 2
    fi
    case "$3" in workspace|tmpclone) MB_CELLS_VARIANT=$3 ;; *) echo "conformance-mass-budget: FAIL -- --grade-cells variant must be workspace or tmpclone (each has its own genesis: the count is dims-dependent)" >&2; exit 2 ;; esac
    MB_CELLS_MODE=$2; run ;;
  --grade-cells-listing) MB_CELLS_MODE=list; run ;;   # lists on THIS machine's dims, graded against the workspace genesis: a local figure is advisory, CI's per-variant grade is the verdict
  "")          run ;;
  *)           echo "usage: conformance-mass-budget.sh [--selftest | --list-legs | --grade-cells <n> | --grade-cells-listing]" >&2; exit 2 ;;
esac
exit $?
