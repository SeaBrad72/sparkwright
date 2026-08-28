#!/bin/sh
# conformance-mass-budget.sh — ratchet the KIT'S OWN conformance mass so it cannot silently re-bloat,
# and so "extend an existing check" is the cheap path and "add another check" is the expensive one
# (CONFORMANCE-MASS-BUDGET, CUT-A7 of D-240819-2). The measured provocation: +30,981 conformance
# lines and 39 new checks in the 35 days after the design skill's "prefer extending a gate" sentence
# shipped. A preference with no surfaceable answer did not bind; a gate does.
#
#   sh conformance/conformance-mass-budget.sh [--selftest]
# Exit: 0 = within the ratified ceiling (or N/A off-kit) · 1 = over budget / ledger broken · 2 = usage.
# POSIX sh; dash-clean. No git, no base ref, no network: every number is a property of the tree in
# front of it, so the verdict cannot change with the base a runner happened to check out.
#
# ── SCOPE CEILING (say it before anyone infers more). This gate counts exactly three things:
#   (a) total lines of the NON-RECURSIVE conformance/*.sh glob,
#   (b) how many such files there are,
#   (c) the `^check control ` row count of conformance/verify.sh.
# Everything else is OUTSIDE the budget and always was: the .md checklists in conformance/, the
# conformance/ subdirectories (fixtures/, incept-manifests/), scripts/, hooks/, guard-core. It counts
# whether growth was DECLARED, never whether it was WORTHWHILE — the reason cell of an ack is prose a
# ratifier reads, not a machine-checked claim.
#
# ── THE CENSUS IS THIS GATE'S OWN MEASURE. The kit's registered-check count is officially
# unreconciled (verify.sh records "three methods, three answers"). This gate does not reconcile them;
# it DEFINES its census as the `^check control ` row count and says so wherever it prints one. It also
# prints the `^check ` total, because the two populations differ and neither is the other. A TOP-LEVEL
# check wired only in ci.yml is invisible to (c) but fully visible to (a) and (b) — note the
# qualifier: a check living in a conformance/ SUBDIRECTORY is invisible to all three surfaces, which
# is the family-wide convention this glob inherits, not a property of this gate. The cross-method
# reconciliation belongs to CONFORMANCE-MUTATION-COVERAGE-GAP, which still stands.
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

# ── THE CONSTANTS. Two per surface, and they mean different things.
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
# MAX_* is the CURRENT ceiling, and it is not free-standing: this check enforces, on every run,
#       MAX_x == GENESIS_x + Σ(deltas of mass-acks.txt lines scoped to x)
# in BOTH directions and with no slack. An ack no raise consumes is a pre-emptive acknowledgment and
# reds; a raise no ack accounts for is silent growth and reds. So the ceiling is a pure function of a
# reviewable ledger, every movement is a permanent line item, and none of it depends on a diff.
#
# DERIVATION — measured on the post-diff tree of the PR that ships this gate (see the design's §10):
#   files : the measured count, EXACTLY, with ZERO headroom, and that is deliberate. Slack in this
#           surface is a silent budget an adder can spend without an ack, which defeats
#           merge-don't-add precisely where it is supposed to bind. Every new conformance/*.sh
#           therefore costs a ratified raise plus its ack line. Same reasoning for census.
#   lines : the measured total ROUNDED UP to the next 100 (the doc-budget.sh convention), and the
#           exact measured figure is recorded beside it below so the rounding is auditable rather
#           than inferred. This surface is deliberately NOT zero-headroom: line count churns whenever
#           anyone adds a comment or a leg to an EXISTING check, which is the behaviour this gate
#           exists to ENCOURAGE. A zero-headroom line budget would red the cure along with the
#           disease and turn an anti-add ratchet into an anti-edit one. Files and census have no such
#           churn — a file exists or it does not — so they carry no headroom at all.
GENESIS_LINES=51400     # measured 51,312 lines across conformance/*.sh, rounded up to the next 100
MAX_LINES=55100         # 55000 + 43 = 55043, rounded up to the next 100 per the genesis convention above (mass-acks.txt 2026-08-28, `lines`, the export-gate line)
GENESIS_FILES=168       # measured exactly; no headroom by design
MAX_FILES=168
GENESIS_CENSUS=128      # measured exactly; `^check control ` rows in conformance/verify.sh
MAX_CENSUS=128

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
      lines|files|census) : ;;
      *) echo "conformance-mass-budget: FAIL -- mass-acks.txt line $_no names an unknown surface [$(printf '%s' "$_s" | mb_san)] (want one of: lines files census)."
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

# mb_invariant <label> <genesis> <max> <sum>: MAX must EQUAL GENESIS + Σ(scoped ack deltas) — exact
# consumption, no >= slack in either direction. An ack with no matching raise is pre-emptive; a raise
# with no ack is unaccounted. Returns 1 on either.
mb_invariant() {
  _lab=$1; _gen=$2; _mx=$3; _sm=$4; _ibad=0
  _exp=$((_gen + _sm))
  [ "$_mx" -eq "$_exp" ] && return 0
  if [ "$_mx" -lt "$_exp" ]; then
    echo "conformance-mass-budget: FAIL -- MAX_$_lab is $_mx but the ledger says $_gen + ($_sm) = $_exp. An ack that no raise consumes is a PRE-EMPTIVE acknowledgment: it severs the declaration from the growth it is meant to accompany. Raise MAX_$_lab to $_exp in this diff, or drop the ack line."
  else
    echo "conformance-mass-budget: FAIL -- MAX_$_lab is $_mx but the ledger says $_gen + ($_sm) = $_exp. A raise with no matching ack line is unaccounted growth. Add the ack line (<date>${TAB}$_lab${TAB}$((_mx - _exp))${TAB}<reason>) to conformance/mass-acks.txt in this diff, or put MAX_$_lab back to $_exp."
  fi
  _ibad=1
  return "$_ibad"
}

# mb_provenance <LABEL> <genesis> <max> <ledger> <surface>: disclose where this ceiling CAME FROM —
# the genesis figure, how many times it has been raised, and the date of the last raise — then print
# every consumed ack BY NAME. Called on green and on red alike.
mb_provenance() {
  _lab=$1; _gen=$2; _mx=$3; _led=$4; _surf=$5
  _rows=$(mb_ledger_rows "$_led" "$_surf")
  _k=0; _last=none
  if [ -n "$_rows" ]; then
    _k=$(printf '%s\n' "$_rows" | grep -c '')
    _last=$(printf '%s\n' "$_rows" | cut -d' ' -f1 | sort | tail -1)
  fi
  echo "conformance-mass-budget: MAX_$_lab=$_mx (genesis $_gen, raised ${_k}x, last $_last)"
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
    echo "conformance-mass-budget: FAIL -- $_lab $_m/$_mx, over by $((_m - _mx)) $_unit(s). TWO CURES, both deliberate: extend an existing check instead of adding one, or raise MAX_$_lab with a matching ack line in conformance/mass-acks.txt in THIS diff."
    _sbad=1
    return "$_sbad"
  fi
  echo "conformance-mass-budget: $_lab $_m/$_mx ($((_mx - _m)) $_unit(s) free · $(mb_pct "$_m" "$_mx") headroom)"
  return "$_sbad"
}

# mb_verdict <root> <lines_gen> <lines_max> <files_gen> <files_max> <cen_gen> <cen_max>
mb_verdict() {
  _root=$1; _lgen=$2; _lmax=$3; _fgen=$4; _fmax=$5; _cgen=$6; _cmax=$7
  _bad=0

  # ── ARMING FIRST, before any enumeration (vet A1.3). An adopter tree carries neither kit marker;
  # it must never reach the fail-closed refusal below, which is about the KIT's own conformance dir.
  if [ ! -f "$_root/docs/ROADMAP-KIT.md" ] && [ ! -f "$_root/.github/workflows/golden-path.yml" ]; then
    echo "N/A: conformance-mass-budget -- no kit marker present (an adopter tree). This budget ratchets the KIT's own conformance/ mass; an adopter's checks are the adopter's business. Nothing to grade, no remedy to offer; this is not a pass."
    return "$_bad"
  fi

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

  # ── THE INVARIANT, per surface, BEFORE the measurement compare: a ceiling nobody accounted for is
  # not a ceiling. Both directions red — an unconsumed ack is pre-emptive, an unacked raise is silent.
  _lsum=$(mb_ledger_sum "$_led" lines)
  _fsum=$(mb_ledger_sum "$_led" files)
  _csum=$(mb_ledger_sum "$_led" census)
  mb_invariant LINES  "$_lgen" "$_lmax" "$_lsum" || _bad=1
  mb_invariant FILES  "$_fgen" "$_fmax" "$_fsum" || _bad=1
  mb_invariant CENSUS "$_cgen" "$_cmax" "$_csum" || _bad=1

  mb_surface lines  "$_lines" "$_lmax" line || _bad=1
  mb_surface files  "$_files" "$_fmax" file || _bad=1
  mb_surface census "$_cen"   "$_cmax" row  || _bad=1
  echo "conformance-mass-budget: census note -- $_cen \`^check control \` row(s) budgeted; $(mb_count_checks "$_root") \`^check \` row(s) total in verify.sh. These are DIFFERENT populations and this gate budgets the former: the census is THIS GATE'S OWN measure, not the kit's reconciled check count (CONFORMANCE-MUTATION-COVERAGE-GAP owns that). A TOP-LEVEL check wired only in ci.yml is invisible here but visible to the lines and files surfaces; one living in a conformance/ subdirectory is invisible to all three."

  # ── PROVENANCE + the consumed acks BY NAME. A green must never leave an amnesty unread.
  mb_provenance LINES  "$_lgen" "$_lmax" "$_led" lines
  mb_provenance FILES  "$_fgen" "$_fmax" "$_led" files
  mb_provenance CENSUS "$_cgen" "$_cmax" "$_led" census

  if [ "$_bad" -eq 0 ]; then
    echo "conformance-mass-budget: OK -- kit conformance mass within its ratified ceiling. SCOPE CEILING: non-recursive conformance/*.sh only. The .md checklists, conformance/ subdirectories, scripts/, hooks/ and guard-core are OUTSIDE this budget."
  else
    echo "conformance-mass-budget: FAIL -- see above. SCOPE CEILING: non-recursive conformance/*.sh only; .md, subdirectories, scripts/, hooks/ and guard-core are outside this budget."
  fi
  return "$_bad"
}

selftest() {
  sfail=0
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  mb_fixture() {   # <dir> <nfiles> <lines-per-file>
    rm -rf "$1"; mkdir -p "$1/conformance" "$1/docs"
    printf 'kit marker\n' > "$1/docs/ROADMAP-KIT.md"
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
  if mb_verdict "$W/ok" 40 40 4 4 0 0 >/dev/null 2>&1; then
    echo "PASS: selftest -- leg i within-budget tree passes"
  else echo "FAIL: selftest -- leg i within-budget tree wrongly red"; sfail=1; fi

  mb_fixture "$W/grow" 4 11        # +10% lines, no ack, no raise
  if mb_verdict "$W/grow" 40 40 4 4 0 0 >/dev/null 2>&1; then
    echo "FAIL: selftest -- leg ii undeclared growth wrongly green"; sfail=1
  else echo "PASS: selftest -- leg ii undeclared growth reds"; fi

  # leg iii -- the SAME growth, declared by a matching ack AND the matching raise, passes and NAMES it.
  mb_fixture "$W/ack" 4 11
  mb_ack "$W/ack" "2026-08-20\tlines\t+4\tleg-iii-declared-growth"
  if _o=$(mb_verdict "$W/ack" 40 44 4 4 0 0 2>&1); then
    if printf '%s\n' "$_o" | grep -Fq 'leg-iii-declared-growth'; then
      echo "PASS: selftest -- leg iii declared growth passes and names the consumed ack"
    else echo "FAIL: selftest -- leg iii passed SILENTLY: the consumed ack was not named in the output"; sfail=1; fi
  else echo "FAIL: selftest -- leg iii declared growth wrongly red"; sfail=1; fi

  # leg iv -- an ack line WITHOUT the matching raise is PRE-EMPTIVE and reds.
  mb_fixture "$W/preempt" 4 10
  mb_ack "$W/preempt" "2026-08-20\tlines\t+4\tleg-iv-preemptive-ack"
  if _o=$(mb_verdict "$W/preempt" 40 40 4 4 0 0 2>&1); then
    echo "FAIL: selftest -- leg iv pre-emptive ack (no matching raise) wrongly green"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'leg-iv-preemptive-ack'; then
      echo "PASS: selftest -- leg iv pre-emptive ack reds and names the line"
    else echo "FAIL: selftest -- leg iv redded but did not name the offending ack"; sfail=1; fi
  fi

  # leg v -- a RAISE without an ack reds: MAX is a pure function of GENESIS + the ledger.
  mb_fixture "$W/raise" 4 11
  if mb_verdict "$W/raise" 40 44 4 4 0 0 >/dev/null 2>&1; then
    echo "FAIL: selftest -- leg v unacknowledged MAX raise wrongly green"; sfail=1
  else echo "PASS: selftest -- leg v unacknowledged MAX raise reds"; fi

  # leg vi -- A CUT. The gate must not punish removal: mass DOWN, MAX down with it, ledger reconciled.
  # Both sanctioned re-tighten shapes run here, because both are what CUT-AI-GOV-TEMPLATE-THIN owes:
  # the `lines` raise is PRUNED (MAX returns to genesis) and `files` carries an APPENDED negative ack
  # (MAX drops BELOW genesis). Fixture: 3 files x 8 lines = 24 lines, down from the leg-iii tree.
  mb_fixture "$W/cut" 3 8
  mb_ack "$W/cut" "2026-08-21\tfiles\t-1\tleg-vi-cut-removed-a-check"
  if _o=$(mb_verdict "$W/cut" 40 40 4 3 0 0 2>&1); then
    if printf '%s\n' "$_o" | grep -Fq 'leg-vi-cut-removed-a-check'; then
      echo "PASS: selftest -- leg vi a cut (pruned raise + negative ack) passes and names the ack"
    else echo "FAIL: selftest -- leg vi passed but did not name the negative ack"; sfail=1; fi
  else echo "FAIL: selftest -- leg vi wrongly punished a CUT"; sfail=1; fi

  # leg vii -- a MALFORMED ack (wrong field count) is never an acknowledgment, and it is NAMED.
  mb_fixture "$W/malformed" 4 11
  mb_ack "$W/malformed" "2026-08-20\tlines\tleg-vii-malformed-three-fields"
  if _o=$(mb_verdict "$W/malformed" 40 44 4 4 0 0 2>&1); then
    echo "FAIL: selftest -- leg vii malformed ack wrongly laundered the raise"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'leg-vii-malformed-three-fields'; then
      echo "PASS: selftest -- leg vii malformed ack reds and names the line"
    else echo "FAIL: selftest -- leg vii redded but did not name the malformed line"; sfail=1; fi
  fi

  # leg viii -- a REASONLESS ack (4 fields, empty reason) FAILS: an unreasoned amnesty is the defect.
  mb_fixture "$W/reasonless" 4 11
  mb_ack "$W/reasonless" "2026-08-20\tlines\t+4\t"
  if _o=$(mb_verdict "$W/reasonless" 40 44 4 4 0 0 2>&1); then
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
    mb_ack "$W/lz" "2026-08-20\tlines\t$_lz\tleg-xii-leading-zero"
    if _o=$(mb_verdict "$W/lz" 40 48 4 4 0 0 2>&1); then
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
  mb_ack "$W/dup" "2026-08-20\tlines\t+4\tleg-xiii-duplicate-ruling"
  mb_ack "$W/dup" "2026-08-20\tlines\t+4\tleg-xiii-duplicate-ruling"
  if _o=$(mb_verdict "$W/dup" 40 48 4 4 0 0 2>&1); then
    echo "FAIL: selftest -- leg xiii a byte-identical duplicate ack was consumed twice (green)"; sfail=1
  else
    if printf '%s\n' "$_o" | grep -Fq 'EXACT DUPLICATE' && printf '%s\n' "$_o" | grep -Fq 'leg-xiii-duplicate-ruling'; then
      echo "PASS: selftest -- leg xiii exact-duplicate ack is MALFORMED and named"
    else echo "FAIL: selftest -- leg xiii redded, but not as a named exact duplicate"; sfail=1; fi
  fi

  # leg xi -- an ack reason is attacker-influenced prose that reaches a CI log a human reads. It is
  # compared RAW and printed SANITIZED, so no control byte can erase the line and forge a verdict.
  mb_fixture "$W/ctrl" 4 11
  mb_ack "$W/ctrl" "2026-08-20\tlines\t+4\tleg-xi-\033[2Kforged PASS: all green"
  _o=$(mb_verdict "$W/ctrl" 40 44 4 4 0 0 2>&1) || :
  if printf '%s\n' "$_o" | grep -Fq 'leg-xi-' && ! printf '%s\n' "$_o" | LC_ALL=C grep -q "$(printf '\033')"; then
    echo "PASS: selftest -- leg xi control bytes in an ack reason are stripped before printing"
  else echo "FAIL: selftest -- leg xi a raw control byte reached the output (or the ack was not printed)"; sfail=1; fi

  # leg ix -- an UNARMED (adopter-shaped) tree renders N/A rc 0 even when it is wildly over budget.
  mb_fixture "$W/na" 4 99; rm -f "$W/na/docs/ROADMAP-KIT.md"
  if _o=$(mb_verdict "$W/na" 40 40 4 4 0 0 2>&1); then
    if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
       ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
      echo "PASS: selftest -- leg ix unarmed over-budget tree renders N-A under verify.sh's C6 classifier"
    else echo "FAIL: selftest -- leg ix unarmed output is not C6-classifiable as N-A"; sfail=1; fi
  else echo "FAIL: selftest -- leg ix unarmed tree reds instead of standing down"; sfail=1; fi

  # leg x -- an ARMED tree whose enumeration is EMPTY is a FAIL, never a vacuous 0-line pass.
  rm -rf "$W/empty"; mkdir -p "$W/empty/conformance" "$W/empty/docs"
  printf 'kit marker\n' > "$W/empty/docs/ROADMAP-KIT.md"
  if mb_verdict "$W/empty" 40 40 4 4 0 0 >/dev/null 2>&1; then
    echo "FAIL: selftest -- leg x empty enumeration wrongly passes (vacuous 0-line green)"; sfail=1
  else echo "PASS: selftest -- leg x empty enumeration on an armed tree reds"; fi

  [ "$sfail" -eq 0 ] && { echo "OK: conformance-mass-budget selftest"; exit 0; } || { echo "FAIL: conformance-mass-budget selftest"; exit 1; }
}

# ---------------------------------------------------------------------------- dispatch
run() {
  cd "$(dirname "$0")/.."
  mb_verdict . "$GENESIS_LINES" "$MAX_LINES" "$GENESIS_FILES" "$MAX_FILES" "$GENESIS_CENSUS" "$MAX_CENSUS"
}

case "${1:-}" in
  --selftest) selftest ;;
  "")         run ;;
  *)          echo "usage: conformance-mass-budget.sh [--selftest]" >&2; exit 2 ;;
esac
exit $?
