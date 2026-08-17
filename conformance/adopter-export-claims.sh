#!/bin/sh
# adopter-export-claims.sh — the EXPORTED tree's own claims-registry proof, UN-NESTED.
# NON-VACUITY-SHARD2-FLOOR (2026-08-15).
#
# WHY THIS FILE EXISTS — the same defect class, and the same cure, as green-on-clone.sh.
# This proof used to run NESTED inside conformance/adopter-export-wired.sh's block (c). Measured on an
# instrumented run of that check's --selftest (2026-08-15, cold+warm, raw traces under the probe):
#
#   COST    — the two nested claims-registry runs cost 134.0s (the kit-marked export) + 181.6s (the raw
#             worktree-attributes export) of a 326.6s --selftest: 96.7%. `non-vacuity` MUTATION-TESTS
#             adopter-export-wired.sh and judges it with THREE runs of its selftest, so the shard-2 floor
#             was ~3x316s. That file's own comment block states the law it had broken: "a proof nested
#             inside a mutation-tested check is paid for ONCE PER MUTANT ... DO NOT re-nest it."
#   POLARITY — worse, the second nested run PROVED NOTHING. On the raw export the S3b claims carve is
#             deliberately SKIPPED (an unmarked tree is a foreign tree), so all 72 claims run and the
#             carve-class verifiers fail BY CONSTRUCTION. That failure was swallowed by a fixture whose
#             only assertion was "this tree fails the lock somehow" — 181.6s buying a tautology.
#
# So the proof moves here, and its second face is UPGRADED rather than preserved: face-r is asserted as
# an EXPECTED FAILURE THAT MUST NAME A CARVE-CLASS CLAIM. That single assertion proves two live things
# at once — the orphaned-claim detector still fires, and the carve is still load-bearing.
#
# ── THE TWO FACES ───────────────────────────────────────────────────────────────────────────────────
#   FACE 0 — the KIT-MARKED profile export (`adopter-export.sh <dest> --profile typescript-node`), the
#            tree a real adopter receives. Its own claims-registry MUST PASS. This is the orphaned-/
#            maintainer-only-claim guard the nested run was really providing: add a claim whose verifier
#            needs an export-ignored file, forget to carve it, and this face goes RED here instead of in
#            the adopter's first CI run.
#   FACE r — the RAW worktree-attributes export: archive HEAD honouring .gitattributes (so BOTH kit
#            markers are stripped), then run adopter-export.sh FROM that tree. Being unmarked, the carve
#            is skipped and every carved claim ships. Its registry MUST FAIL, and the failure MUST NAME
#            at least one carve-class claim. An unexpected PASS is a FAIL of this check (the carve stopped
#            mattering, or the detector went dark); a failure naming ZERO carve-class claims is also a
#            FAIL (it failed for some unrelated reason, so it no longer demonstrates the carve).
#
# ── THE CARVE SET IS DERIVED, NEVER DECLARED ────────────────────────────────────────────────────────
# The carve list is read as (kit claims.tsv ids) MINUS (face-0 export claims.tsv ids) — measured from the
# artifacts themselves. There is deliberately NO second copy of adopter-export.sh's list here: a declared
# copy drifts silently the day a claim is added to the carve, and a check whose reference list has
# drifted grades against a fiction. An EMPTY derived set is a FAIL, not a shrug — with nothing carved
# there is no carve to prove load-bearing, and face-r's whole assertion would be vacuous.
#
# ── HONEST CEILINGS, STATED FIRST ───────────────────────────────────────────────────────────────────
#   * FACE r NAMES AT LEAST ONE, NOT ALL. The assertion is an intersection test, so a carve entry that
#     stops failing on the raw export is invisible here. Set-equality was rejected: the raw export's
#     failure set legitimately varies with the runner (a verifier can also fail for an environmental
#     reason there), and a check that reds on that noise gets waived, which is worse.
#   * THIS CHECK GRADES VERDICTS, NOT VERIFIERS. It runs claims-registry.sh and reads its verdict lines;
#     whether a given verifier is itself honest is that verifier's own problem (and claims-registry.sh's
#     --selftest is what proves the registry can fail at all).
#   * COST IS REAL AND VISIBLE. The live run is ~200-355s measured (two full exports + two registry
#     runs, one of them the uncarved 72-claim set incl. repo-ownership's four nested exports). It runs
#     in its OWN parallel CI job so it is never the critical path, and the `verify.sh` control row is
#     the CHEAP --selftest form on purpose — a live-form row would charge cf-verify-enforced and every
#     local `verify.sh --require` the full both-faces cost, reversing this slice's sign.
#   * THE build_faces FAIL BRANCH IS COVERED BY THE COMPOSITE MUTANT ONLY. Its FAIL-path rc
#     assignment has no isolating selftest fixture (shimming a broken export script onto PATH was
#     judged not worth the leg); a build failure still renders FAIL-never-pass, the safe direction.
#   * ARMING IS CWD-RELATIVE, run-from-the-repo-root is an invariant this check cannot self-enforce:
#     invoked elsewhere it N/As (all three wirings invoke from the root; verify.sh renders N-A, never
#     PASS, so no gate goes falsely green — but a hand run from a subdirectory proves nothing).
#
# ── ARMING (fail-closed; the shared kit-marker pattern) ─────────────────────────────────────────────
# Exporting the kit is a KIT-TREE activity. On a kit tree (docs/ROADMAP-KIT.md or
# .github/workflows/golden-path.yml present) the check runs both faces for real. With NEITHER marker
# present (an adopter tree, and every exported tree — both markers are export-ignored) it renders an
# honest line-anchored `N/A:` and exits 0. That N/A is also RECURSION-SAFETY: this check's own copy
# inside an export must stand down, or exporting would never terminate.
#
# WIRED (pair pointers): conformance/verify.sh `check control adopter-export-claims-selftest` (the
# --selftest form, which is also what enrols this file in non-vacuity.sh's mutation sweep) ·
# .github/workflows/ci.yml `cf-export-claims` (the LIVE both-faces proof, one parallel job, adjudicated
# by the `conformance` aggregator) · ci.yml `conformance-selftests` (--selftest) ·
# .github/workflows/drift-watch.yml (the weekly LIVE re-run, so the Monday aggregate keeps this proof).
# Usage: sh conformance/adopter-export-claims.sh [--selftest]   (run from the repo root)
# Exit: 0 = both faces at their true polarities (or N/A off a kit tree) · 1 = a face is wrong · 2 = bad
#       usage. POSIX sh; dash-clean.
set -eu

SELFTEST=no
case "${1:-}" in
  "") : ;;
  --selftest) SELFTEST=yes ;;
  *) echo "usage: adopter-export-claims.sh [--selftest]" >&2; exit 2 ;;
esac

SEP=$(printf '\302\267')          # U+00B7 MIDDLE DOT, the summary separator used kit-wide

# ── claim_ids <tsv> : print the id column of every non-comment, non-blank registry row. A missing file
#    prints nothing and is NOT an error here — the callers grade the resulting COUNT, which is the
#    figure a reader can check.
claim_ids() {
  [ -f "$1" ] || return 0
  awk -F'\t' '$0 !~ /^#/ && NF > 0 && $1 != "" { print $1 }' "$1"
}

# ── count_lines <text> : the number of non-blank lines in <text> (0 for the empty string, which `wc -l`
#    on a here-string would report as 1 on some shells).
count_lines() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n+0 }'; }

# ── registry_out <tree> : THE SEAM. Run the tree's OWN conformance/claims-registry.sh inside it and echo
#    the combined output; the registry's exit code is this function's. Factored out so --selftest can
#    drive the EXACT seam against tiny fixtures instead of paying for two real registry runs (the whole
#    point of the un-nesting: the selftest runs on every PR and inside every mutant).
registry_out() { ( cd "$1" && sh conformance/claims-registry.sh 2>&1 ); }

# ── failing_ids <registry-output> : the claim ids the registry named as non-passing. claims-registry.sh
#    prints `FAIL: <id> - ...` / `UNVERIFIED: <id> - ...` one per non-passing claim; its structural
#    failures (a missing registry, a duplicate id) print a non-id second word, which simply never
#    intersects the carve set.
failing_ids() { printf '%s\n' "$1" | awk '$1 == "FAIL:" || $1 == "UNVERIFIED:" { print $2 }'; }

# ── carve_set <kit-claims-tsv> <face-0 tree> : the DERIVED carve list — every claim id the kit registers
#    that the kit-marked export does NOT. Derived from the two artifacts, never declared here.
carve_set() {
  _cs_kept=" $(claim_ids "$2/conformance/claims.tsv" | tr '\n' ' ') "
  for _cs_id in $(claim_ids "$1"); do
    case "$_cs_kept" in
      *" $_cs_id "*) : ;;
      *) printf '%s\n' "$_cs_id" ;;
    esac
  done
}

# ── intersect <newline-list A> <newline-list B> : the members of A that are also in B, in A's order.
intersect() {
  _ix_b=" $(printf '%s\n' "$2" | tr '\n' ' ') "
  for _ix_a in $(printf '%s\n' "$1"); do
    case "$_ix_b" in
      *" $_ix_a "*) printf '%s\n' "$_ix_a" ;;
    esac
  done
}

# ── THE VERDICT ENGINE ──────────────────────────────────────────────────────────────────────────────
# Takes the two BUILT faces as arguments, so the whole judgment is exercisable by --selftest against
# fixtures costing milliseconds. Every exit is driven by the single `_bad` accumulator, so the mutation
# sweep has one unambiguous fail-path token to neuter. FIGURES ARE PRINTED ON EVERY ARMED PATH (both
# claim counts + the derived carve size), because a verdict whose inputs are invisible cannot be checked.
ae_verdict() {  # <armed 0|1> <kit-claims-tsv> <face-0 tree> <face-r tree>
  _armed=$1; _kt=$2; _t0=$3; _tr=$4
  _bad=0

  # ── THE ADOPTER FACE, unconditional (see the arming note in the header). Also recursion-safety.
  if [ "$_armed" -eq 0 ]; then
    echo "N/A: adopter-export-claims -- no kit marker present (an adopter tree, or an exported tree), and the adopter-export mechanism is the kit's own. There is nothing to grade here and no remedy to offer; this is not a pass."
    return "$_bad"
  fi

  _n0=$(count_lines "$(claim_ids "$_t0/conformance/claims.tsv")")
  _nr=$(count_lines "$(claim_ids "$_tr/conformance/claims.tsv")")
  _nk=$(count_lines "$(claim_ids "$_kt")")
  _carve=$(carve_set "$_kt" "$_t0")
  _nc=$(count_lines "$_carve")
  printf 'adopter-export-claims: figures -- face-0 %d claim(s) %s face-r %d claim(s) %s carve set %d claim(s) (derived: %d kit claim(s) minus the %d the kit-marked export kept)\n' \
    "$_n0" "$SEP" "$_nr" "$SEP" "$_nc" "$_nk" "$_n0"

  # ── THE DERIVATION MUST BE ALIVE. With an empty carve set face-r's assertion below could only ever be
  # vacuous, so a dead derivation is a FAIL in its own right rather than a silently weakened proof.
  if [ "$_nc" -eq 0 ]; then
    echo "adopter-export-claims: FAIL -- the derived carve set is EMPTY ($_nk kit claim(s), $_n0 kept by the kit-marked export). Either the S3b carve in scripts/adopter-export.sh stopped carving, or the two claims.tsv files are no longer comparable — face-r's proof would be vacuous, so this is a failure."
    _bad=1
  fi

  # ── FACE 0 — the tree a real adopter receives. Its registry MUST PASS.
  _rc0=0; _out0=$(registry_out "$_t0") || _rc0=$?
  if [ "$_rc0" -eq 0 ]; then
    echo "adopter-export-claims: face-0 PASS -- the KIT-MARKED export's own claims-registry passes ($_n0 claim(s) $SEP rc 0)"
  else
    echo "adopter-export-claims: FAIL -- face-0, the KIT-MARKED export's own claims-registry does NOT pass ($_n0 claim(s) $SEP rc $_rc0). This is the orphaned maintainer-only claim guard: carve the claim in scripts/adopter-export.sh, or fix its verifier so it holds on an export. Claim(s) named: $(failing_ids "$_out0" | tr '\n' ' ')"
    printf '%s\n' "$_out0" | sed 's/^/    | /'
    _bad=1
  fi

  # ── FACE r — the raw, unmarked export. Its registry MUST FAIL, NAMING a carve-class claim.
  _rcr=0; _outr=$(registry_out "$_tr") || _rcr=$?
  if [ "$_rcr" -eq 0 ]; then
    echo "adopter-export-claims: FAIL -- face-r, the RAW worktree-attributes export's claims-registry UNEXPECTEDLY PASSED ($_nr claim(s) $SEP rc 0). It fails BY CONSTRUCTION today (the S3b carve is skipped on an unmarked tree, so the carve-class verifiers run and red). A pass here means the carve stopped being load-bearing or the orphan detector went dark — re-derive this proof before relaxing it."
    _bad=1
  else
    _named=$(intersect "$(failing_ids "$_outr")" "$_carve")
    _nn=$(count_lines "$_named")
    if [ "$_nn" -eq 0 ]; then
      echo "adopter-export-claims: FAIL -- face-r failed (rc $_rcr $SEP $_nr claim(s)) but named ZERO carve-class claims, so it no longer demonstrates that the carve is load-bearing. Named: $(failing_ids "$_outr" | tr '\n' ' ') $SEP carve set: $(printf '%s' "$_carve" | tr '\n' ' ')"
      printf '%s\n' "$_outr" | sed 's/^/    | /'
      _bad=1
    else
      echo "adopter-export-claims: face-r EXPECTED-FAIL -- the RAW export's claims-registry fails naming $_nn carve-class claim(s) ($_nr claim(s) $SEP rc $_rcr $SEP named: $(printf '%s' "$_named" | tr '\n' ' ')). The orphan detector fires AND the carve is load-bearing."
    fi
  fi

  if [ "$_bad" -eq 0 ]; then
    echo "adopter-export-claims: OK -- both export faces hold at their true polarities (face-0 passes $SEP face-r fails naming a carve-class claim). Verdicts only: this never claims a verifier is itself honest."
  fi
  return "$_bad"
}

# ── commit_tree <tree> : an exported tree is a git repo on an adopter's first push, and several
#    verifiers read git state (`git archive HEAD`, `git ls-files`). gc.auto=0 because a detached auto-gc
#    still writing into .git races the teardown `rm` into ENOTEMPTY and reddens a PASSING check.
commit_tree() {
  ( cd "$1" && git init -q && git add -A \
    && git -c gc.auto=0 -c user.email=ci@kit -c user.name=ci commit -qm export >/dev/null 2>&1 )
}

# ── build_faces <workdir> : build the two faces. 0 = both built (at <workdir>/face0 and
#    <workdir>/facer), non-zero = a build failed (the caller reports that as a FAIL, never a pass).
build_faces() {
  _bw=$1
  mkdir -p "$_bw/raw" "$_bw/facer"
  # FACE 0 — byte-for-byte what adopter-export-wired.sh's block (c) builds.
  ( sh scripts/adopter-export.sh "$_bw/face0" --profile typescript-node >/dev/null 2>&1 ) || return 1
  commit_tree "$_bw/face0" || return 1
  # FACE r — the raw archive of HEAD honouring the worktree's .gitattributes (so BOTH kit markers are
  # stripped, exactly as the export-ignore set intends), then an export FROM that unmarked tree.
  # adopter-export.sh is re-copied from the worktree so the run exercises THIS tree's script, not HEAD's.
  _ar=$(mktemp) || return 1
  ( git archive --worktree-attributes HEAD ) > "$_ar" || { rm -f "$_ar"; return 1; }
  tar -x -C "$_bw/raw" < "$_ar" || { rm -f "$_ar"; return 1; }
  rm -f "$_ar"
  # If this copy fails, face-r would silently exercise HEAD's script instead of the worktree's —
  # fail the build instead (the caller renders a build failure as FAIL, never a pass).
  cp scripts/adopter-export.sh "$_bw/raw/scripts/adopter-export.sh" 2>/dev/null || return 1
  commit_tree "$_bw/raw" || return 1
  ( cd "$_bw/raw" && sh scripts/adopter-export.sh "$_bw/facer/exp" >/dev/null 2>&1 ) || return 1
  commit_tree "$_bw/facer/exp" || return 1
  return 0
}

run() {
  _a=0
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then _a=1; fi
  # Stand down BEFORE building anything: an adopter tree must cost nothing, and an exported tree must
  # terminate. The verdict engine owns the N/A sentence (one place renders it, one place is graded).
  if [ "$_a" -eq 0 ]; then
    ae_verdict 0 "" "" ""
    return $?
  fi
  _w=$(mktemp -d)
  _rc=0
  if build_faces "$_w"; then
    ae_verdict 1 conformance/claims.tsv "$_w/face0" "$_w/facer/exp" || _rc=$?
  else
    echo "adopter-export-claims: FAIL -- could not build the two export faces (adopter-export.sh, git archive, or the throwaway commit failed). Nothing was judged, so this is a failure and not a pass."
    _rc=1
  fi
  # Teardown must NEVER decide the verdict: a detached git gc from the throwaway commits can race
  # `rm -rf` into ENOTEMPTY under CI load (green locally, red on a loaded runner). The assertions above
  # ARE the verdict; a leaked temp dir on an ephemeral runner is harmless.
  rm -rf "$_w" 2>/dev/null || true
  return "$_rc"
}

# ---------------------------------------------------------------------------- selftest
# MECHANISM-ONLY AND CHEAP, BY DESIGN — this is the entire point of the un-nesting. The selftest runs on
# every PR and THREE TIMES per mutation-sweep judgment, so it must never run a real registry: it drives
# the same seam (registry_out) against fixture trees whose claims-registry.sh is four lines of canned
# output. The LIVE both-faces proof runs in cf-export-claims and weekly in drift-watch. Every negative
# leg flows through the `_bad` accumulator above, which is what makes the composite mutant KILLABLE.
selftest() {
  # The gc guard lives HERE and at the tail dispatch, never above the marker: lines strictly BEFORE the
  # marker are the mutation region, so an export placed up there is neutered inside every mutant (the
  # anti-`git gc` race protection would be off exactly when a flake reads as a false KILL). The
  # --selftest arm exits before the tail, hence both sites.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=gc.auto
  export GIT_CONFIG_VALUE_0=0
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM
  TAB=$(printf '\t')

  ae_fx() {  # <dir> <registry-body> <claim-id>... — a tree shaped like an export: a claims.tsv and a
             # claims-registry.sh whose verdict lines are canned. That is all the seam reads.
    _fd=$1; _fb=$2; shift 2
    rm -rf "$_fd"; mkdir -p "$_fd/conformance"
    : > "$_fd/conformance/claims.tsv"
    for _fi in "$@"; do printf '%s%sa claim%strue\n' "$_fi" "$TAB" "$TAB" >> "$_fd/conformance/claims.tsv"; done
    printf '#!/bin/sh\n%s\n' "$_fb" > "$_fd/conformance/claims-registry.sh"
  }
  ae_kit() {  # <file> <claim-id>... — a stand-in for the kit's OWN claims.tsv (the carve derivation's
              # left-hand side)
    _kf=$1; shift
    : > "$_kf"
    for _ki in "$@"; do printf '%s%sa claim%strue\n' "$_ki" "$TAB" "$TAB" >> "$_kf"; done
  }
  ae_out() { ae_verdict "$1" "$2" "$3" "$4" 2>&1; }
  ae_expect() {  # <label> <want-rc> <armed> <kit-tsv> <face-0> <face-r>
    _rc=0; _o=$(ae_out "$3" "$4" "$5" "$6") || _rc=$?
    if [ "$_rc" = "$2" ]; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (want rc $2, got $_rc)"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  ae_says() {  # <label> <needle> <armed> <kit-tsv> <face-0> <face-r>
    _o=$(ae_out "$3" "$4" "$5" "$6") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (missing '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }

  ae_kit "$W/kit.tsv" alpha beta drift-watch golden-path
  ae_fx "$W/f0"    'echo "PASS: alpha"; echo "PASS: beta"; exit 0' alpha beta
  ae_fx "$W/fr"    'echo "FAIL: drift-watch -- verifier reports drift (exit 1): sh conformance/drift-watch-wired.sh"; exit 1' alpha beta drift-watch golden-path

  # ── THE POSITIVE ORACLE — face-0 PASSES and face-r fails NAMING a carve-class claim. Without it an
  # always-red mutant would satisfy every negative leg below.
  ae_expect "the two faces at their TRUE polarities pass the check" 0 1 "$W/kit.tsv" "$W/f0" "$W/fr"
  ae_says "and face-0's verdict is named" "face-0" 1 "$W/kit.tsv" "$W/f0" "$W/fr"
  ae_says "and face-r's expected-FAIL is named" "face-r" 1 "$W/kit.tsv" "$W/f0" "$W/fr"
  ae_says "and the carve-class claim it named is printed" "drift-watch" 1 "$W/kit.tsv" "$W/f0" "$W/fr"
  ae_says "and face-0's claim COUNT is printed" "face-0 2 claim(s)" 1 "$W/kit.tsv" "$W/f0" "$W/fr"
  ae_says "and face-r's claim COUNT is printed" "face-r 4 claim(s)" 1 "$W/kit.tsv" "$W/f0" "$W/fr"
  ae_says "and the DERIVED carve set size is printed" "carve set 2 claim(s)" 1 "$W/kit.tsv" "$W/f0" "$W/fr"

  # ── A PLANTED FAILING VERIFIER ON FACE 0 MUST RED, naming the face and the claim. This is the
  # orphaned-maintainer-only-claim guard the nested run provided; it is the leg that proves it survived.
  ae_fx "$W/f0bad" 'echo "FAIL: badge-version -- verifier reports drift (exit 1): sh conformance/badge-version.sh"; exit 1' alpha beta
  ae_expect "a planted failing verifier on face-0 REDS the check" 1 1 "$W/kit.tsv" "$W/f0bad" "$W/fr"
  ae_says "and the failing FACE is named" "face-0" 1 "$W/kit.tsv" "$W/f0bad" "$W/fr"
  ae_says "and the failing CLAIM is named" "badge-version" 1 "$W/kit.tsv" "$W/f0bad" "$W/fr"

  # ── THE EXPECTED-FAIL FACE, PROVEN BOTH WAYS (1/2): an UNEXPECTED PASS must RED. An expected-FAIL
  # assertion that greened on a pass would be an inverted proof — the exact hazard of asserting failure.
  ae_fx "$W/frok" 'echo "PASS: everything"; exit 0' alpha beta drift-watch golden-path
  ae_expect "face-r PASSING unexpectedly REDS the check" 1 1 "$W/kit.tsv" "$W/f0" "$W/frok"
  ae_says "and says the carve/orphan-detector premise no longer holds" "UNEXPECTEDLY PASSED" 1 "$W/kit.tsv" "$W/f0" "$W/frok"

  # ── THE EXPECTED-FAIL FACE, PROVEN BOTH WAYS (2/2): a failure naming ZERO carve-class claims REDS.
  # Without this leg "face-r fails somehow" would be accepted — which is precisely the tautology the
  # nested version was buying for 181.6s.
  ae_fx "$W/frnc" 'echo "FAIL: alpha -- verifier reports drift (exit 1): sh conformance/alpha.sh"; exit 1' alpha beta drift-watch golden-path
  ae_expect "face-r failing for a NON-carve reason REDS the check" 1 1 "$W/kit.tsv" "$W/f0" "$W/frnc"
  ae_says "and says zero carve-class claims were named" "ZERO carve-class" 1 "$W/kit.tsv" "$W/f0" "$W/frnc"

  # ── AN EMPTY DERIVED CARVE SET REDS: with nothing carved there is no carve to prove load-bearing.
  ae_fx "$W/f0all" 'echo "PASS: everything"; exit 0' alpha beta drift-watch golden-path
  ae_expect "an EMPTY derived carve set REDS the check" 1 1 "$W/kit.tsv" "$W/f0all" "$W/fr"
  ae_says "and names the dead derivation" "carve set is EMPTY" 1 "$W/kit.tsv" "$W/f0all" "$W/fr"

  # ── UNARMED -> N/A + rc 0, driven through the REAL script in a marker-less directory. This is the
  # ADOPTER FACE and the recursion stop: it must cost nothing and must build no export.
  mkdir -p "$W/na"
  _narc=0; _naout=$( cd "$W/na" && sh "$_self" 2>&1 ) || _narc=$?
  if [ "$_narc" = 0 ]; then echo "PASS: selftest -- an adopter tree (no kit marker) renders rc 0"
  else echo "FAIL: selftest -- an adopter tree did not render rc 0 (got $_narc)"; printf '%s\n' "$_naout" | sed 's/^/    /'; sfail=1; fi
  if printf '%s\n' "$_naout" | grep -qF 'N/A: adopter-export-claims'; then
    echo "PASS: selftest -- and says N/A in the line-anchored idiom"
  else echo "FAIL: selftest -- the adopter face did not render the N/A idiom"; printf '%s\n' "$_naout" | sed 's/^/    /'; sfail=1; fi

  # The predicate below is COPIED VERBATIM from verify.sh's is_self_skip (C6). If that idiom ever
  # changes, this leg is what tells us this check silently started rendering PASS instead of N-A.
  if printf '%s\n' "$_naout" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
     ! printf '%s\n' "$_naout" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
    echo "PASS: selftest -- the N/A output renders N-A under verify.sh's C6 classifier (never PASS)"
  else
    echo "FAIL: selftest -- the N/A output does NOT satisfy verify.sh's is_self_skip predicate"
    printf '%s\n' "$_naout" | sed 's/^/    /'; sfail=1
  fi

  if [ "$sfail" = 0 ]; then
    echo "OK: adopter-export-claims selftest (both faces asserted at their true polarities, the"
    echo "                       expected-FAIL face proven in BOTH directions, the derived carve set"
    echo "                       proven load-bearing, and the adopter N-A face pinned to verify.sh's"
    echo "                       own classifier -- no registry was run)"
    exit 0
  fi
  echo "FAIL: adopter-export-claims selftest"; exit 1
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
# The live path commits throwaway trees; see the note in selftest() for why this sits below the marker.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=gc.auto
export GIT_CONFIG_VALUE_0=0
run; exit $?
