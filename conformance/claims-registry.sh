#!/bin/sh
# claims-registry.sh — run every claim's verifier in conformance/claims.tsv; fail on drift OR on a
# silently-dropped headline claim. Generalises badge-version.sh from one claim (badge==VERSION) to
# N. The registry is CONTROL-PLANE: adding / removing / weakening a claim is a ratified act — you
# cannot quietly drop a claim's verifier to make CI green (the H1 integrity property).
#   sh conformance/claims-registry.sh [--selftest]
# Exit: 0 = all claims hold + coverage intact · 1 = drift / unverified / integrity gap · 2 = usage.
# Three-state per verifier (mirrors verify.sh): exit 0 = PASS · exit 2 = UNVERIFIED (could not confirm
# — surfaced, NOT a pass) · other = FAIL (drift). Verifier output is captured and PRINTED on any
# non-pass, so a CI failure shows WHY (not a swallowed >/dev/null). POSIX sh; dash-clean.
# SCHEMA (PR 10): every data row is EXACTLY 4 tab-separated fields — <id> <claim> <verifier> <proof ∈
# {tree,selftest}>. Width + grammar are graded on the RAW line BEFORE dispatch; any other width, or any
# other proof value including empty, is a FAIL that never reaches a shell (see run_registry).
# Verifier contract: a registered verifier MUST emit only STRUCTURAL diagnostics (verdicts, paths,
# identifier NAMES) — never a secret VALUE — because its stdout+stderr is surfaced on a non-pass.
set -eu

REGISTRY="${KIT_CLAIMS:-conformance/claims.tsv}"
# Headline claims that MUST stay registered (no silent drop). Change this set deliberately + ratified.
REQUIRED_IDS="badge-version conformance-ci-wired doc-budget guard-single-source action-pinning security-policy gate-counts cost-governance supply-chain-verify gitlab-adoption doctor operate-loop tier-advice named-adapters actionlint-valid template-detectors-aligned provenance-precondition golden-path-trigger adopter-preflight mode-blind explain feature-flags-ready token-scope author-not-approver verify-enforced runaway-killswitch version-tag-coherent release-tag-on-merge governing-docs-current mirror-immutable-tags mirror-current promotion-contract promotion-readiness proportional-gate non-vacuity-gate eval-harness roster-guard profile-parity poster-parity branch-protection-declared"

TAB=$(printf '\t')

# emit_diag <output>: print captured verifier output indented, so non-pass results are debuggable.
emit_diag() { [ -n "$1" ] && printf '%s\n' "$1" | sed 's/^/    | /' || true; }

# cr_san: strip control bytes from registry text on its way to a screen — a refused row is PRINTED, and
# an ANSI escape in it could erase the line and impersonate a verdict (mb_san's discipline).
cr_san() { LC_ALL=C tr -d '[:cntrl:]'; }

# cr_proof_want <verifier>: the proof DERIVED from FIELD 3 ALONE, on the DISPATCH SHAPE `.sh --selftest`.
# Measured: five rows (doctor, operate-loop, tier-advice, verify-enforced, release-tag-on-merge) carry
# `--selftest` in their claim PROSE and dispatch none — reading the whole line is the false 33/72 that
# the true 28/72 replaces. HONEST CEILING: integrity of DISCLOSURE, not enforcement — no gate consults
# the column, post-grammar it cannot influence execution, and a mention-vs-use fake inside field 3 stays
# constructible with the reviewer as its only detector.
cr_proof_want() { case "$1" in *.sh\ --selftest*) echo selftest ;; *) echo tree ;; esac; }

# run_registry <tsv>: print PASS/UNVERIFIED/FAIL per claim + coverage gaps; return 1 on any non-pass.
run_registry() {
  _reg=$1; _fail=0; _seen=""; _no=0
  [ -f "$_reg" ] || { echo "FAIL: missing registry $_reg"; return 1; }
  while IFS= read -r _ln || [ -n "$_ln" ]; do   # `|| [ -n ]` = process a final line with no trailing newline (no silent skip)
    _no=$((_no + 1))
    case "$_ln" in ''|\#*) continue ;; esac
    # ── WIDTH IS GRADED ON THE RAW LINE, BEFORE ANYTHING IS EXECUTED, and that ordering IS the control.
    # This loop read THREE IFS=TAB variables, so every field past the third was absorbed into $_verifier
    # and handed to `sh -c` as program text (probed live: a 4th field `; echo …` RAN, and the benign
    # `grep -q` shape swallowed a stray operand at rc 0 — fail-OPEN). Refusing any width but 4 closes the
    # CLASS: a 5th column tomorrow rides in exactly as a 4th did. Idiom: mass-budget:332.
    _nt=$(printf '%s' "$_ln" | LC_ALL=C tr -dc "$TAB" | LC_ALL=C wc -c | tr -d ' ')
    [ "$_nt" -eq 3 ] || { echo "FAIL: registry line $_no is MALFORMED: $((_nt + 1)) tab-separated field(s), expected exactly 4 (<id> <claim> <verifier> <proof>). REFUSED BEFORE EXECUTION — a row this parser cannot read is never dispatched to a shell, so a mis-shaped registry can never run something nobody wrote as a verifier: [$(printf '%s' "$_ln" | cr_san)]"; _fail=1; continue; }
    _id=${_ln%%"$TAB"*};      _cr1=${_ln#*"$TAB"}
    _claim=${_cr1%%"$TAB"*};  _cr2=${_cr1#*"$TAB"}
    _verifier=${_cr2%%"$TAB"*}; _proof=${_cr2#*"$TAB"}
    case "$_id" in ''|\#*) continue ;; esac
    if [ -z "$_verifier" ]; then echo "FAIL: claim '$(printf '%s' "$_id" | cr_san)' has no verifier"; _fail=1; continue; fi
    # ── PROOF GRAMMAR, ALSO BEFORE ANY SHELL: ^(tree|selftest)$ or FAIL. An EMPTY proof (the half-updated
    # / mid-`kit-update-merge` skew state) is an explicit FAIL, never a default — a silently-defaulted
    # column discloses nothing and hides the skew. Then THE DERIVATIONAL LINT: the declared value must
    # equal what field 3 derives, which is what keeps the disclosed split honest without a hand re-measure.
    case "$_proof" in tree|selftest) : ;;
      *) echo "FAIL: claim '$(printf '%s' "$_id" | cr_san)' has proof [$(printf '%s' "$_proof" | cr_san)]; want exactly 'tree' or 'selftest'. An empty or off-grammar proof is a FAIL, not a default, and it is graded before the verifier runs so the cell can never become program text."; _fail=1; continue ;;
    esac
    _want=$(cr_proof_want "$_verifier")
    [ "$_proof" = "$_want" ] || { echo "FAIL: claim '$(printf '%s' "$_id" | cr_san)' declares proof '$_proof' but its verifier derives '$_want' — the registry's disclosed tree-vs-selftest split would be a lie. Fix the column, or the verifier."; _fail=1; continue; }
    case " $_seen " in *" $_id "*) echo "FAIL: duplicate claim id '$(printf '%s' "$_id" | cr_san)'"; _fail=1; continue ;; esac
    _seen="$_seen $_id"
    # Capture output + exit code (set -e-safe). Classify three-state; surface diagnostics on non-pass.
    if _out=$(sh -c "$_verifier" 2>&1); then
      echo "PASS: $_id"
    else
      _rc=$?
      if [ "$_rc" = 2 ]; then
        echo "UNVERIFIED: $_id — verifier could not confirm (exit 2): $_verifier"
      else
        echo "FAIL: $_id — verifier reports drift (exit $_rc): $_verifier"
      fi
      emit_diag "$_out"
      _fail=1
    fi
  done < "$_reg"
  for _r in $REQUIRED_IDS; do
    case " $_seen " in *" $_r "*) : ;; *) echo "FAIL: required claim '$_r' missing from registry (silent drop)"; _fail=1 ;; esac
  done
  return $_fail
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)
  # a COMPLETE valid registry: every REQUIRED_ID present with a passing (true) verifier.
  : > "$d/ok.tsv"
  for r in $REQUIRED_IDS; do printf '%s\t%s\ttrue\ttree\n' "$r" "claim $r" >> "$d/ok.tsv"; done
  if run_registry "$d/ok.tsv" >/dev/null 2>&1; then echo "PASS: selftest — complete valid registry passes"; else echo "FAIL: selftest — valid registry wrongly rejected"; sfail=1; fi
  # a FAILING verifier must be caught, and its DIAGNOSTICS surfaced (not swallowed)
  cp "$d/ok.tsv" "$d/bad.tsv"; printf '%s\t%s\t%s\t%s\n' "extra-bad" "drifted" "echo why-it-drifted; exit 1" "tree" >> "$d/bad.tsv"
  bout=$(run_registry "$d/bad.tsv" 2>&1) && { echo "FAIL: selftest — failing verifier not caught"; sfail=1; } || true
  printf '%s\n' "$bout" | grep -q "FAIL: extra-bad" || { echo "FAIL: selftest — failing verifier not labeled FAIL"; sfail=1; }
  printf '%s\n' "$bout" | grep -q "why-it-drifted"  || { echo "FAIL: selftest — verifier diagnostics swallowed (not surfaced)"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — failing verifier detected + diagnostics surfaced"
  # an UNVERIFIED (exit 2) verifier must be labeled UNVERIFIED (not FAIL) AND still fail the registry
  cp "$d/ok.tsv" "$d/unv.tsv"; printf '%s\t%s\t%s\t%s\n' "unv-claim" "unverifiable" "echo cant-confirm; exit 2" "tree" >> "$d/unv.tsv"
  uout=$(run_registry "$d/unv.tsv" 2>&1) && { echo "FAIL: selftest — exit-2 verifier did not fail the registry"; sfail=1; } || true
  printf '%s\n' "$uout" | grep -q "UNVERIFIED: unv-claim" || { echo "FAIL: selftest — exit-2 not labeled UNVERIFIED (three-state collapsed)"; sfail=1; }
  printf '%s\n' "$uout" | grep -q "cant-confirm"          || { echo "FAIL: selftest — UNVERIFIED diagnostics not surfaced"; sfail=1; }
  printf '%s\n' "$uout" | grep -q "FAIL: unv-claim"       && { echo "FAIL: selftest — UNVERIFIED wrongly relabeled FAIL"; sfail=1; } || true
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — exit-2 labeled UNVERIFIED + surfaced + fails registry"
  # a DROPPED required id must be caught (drop gate-counts)
  grep -v '^gate-counts' "$d/ok.tsv" > "$d/drop.tsv"
  if run_registry "$d/drop.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — silent drop not caught"; sfail=1; else echo "PASS: selftest — dropped required claim detected"; fi
  # a DUPLICATE id must be caught
  cp "$d/ok.tsv" "$d/dup.tsv"; printf '%s\t%s\ttrue\ttree\n' "badge-version" "dup" >> "$d/dup.tsv"
  if run_registry "$d/dup.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — duplicate id not caught"; sfail=1; else echo "PASS: selftest — duplicate id detected"; fi
  # an EMPTY verifier must be caught
  cp "$d/ok.tsv" "$d/empty.tsv"; printf '%s\t%s\t\t%s\n' "no-verifier" "missing" "tree" >> "$d/empty.tsv"
  if run_registry "$d/empty.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — empty verifier not caught"; sfail=1; else echo "PASS: selftest — empty verifier detected"; fi

  # ── THE 4-FIELD PROOF COLUMN (PR 10). Every leg below was watched RED against the 3-var parser this
  # slice replaces: the injection row's payload EXECUTED (it created its file and the registry still
  # returned 0 — the security seat's live probe, reproduced here as a permanent regression), and every
  # width / grammar / lint row was accepted in silence.
  # (a) EXECUTION — a 4th field carrying shell text must be refused by WIDTH+GRAMMAR before any `sh -c`.
  #     The oracle is a SIDE EFFECT, not the diagnostic text: the FAIL line quotes the offending row, so
  #     grepping for a token would match the report and pass vacuously either way.
  cp "$d/ok.tsv" "$d/inj.tsv"; printf '%s\t%s\t%s\t%s\n' "inj-claim" "injected" "true" "; touch $d/pwned" >> "$d/inj.tsv"
  iout=$(run_registry "$d/inj.tsv" 2>&1) && { echo "FAIL: selftest — an off-grammar proof field did not fail the registry"; sfail=1; } || true
  if [ -e "$d/pwned" ]; then echo "FAIL: selftest — the proof field REACHED A SHELL (its payload ran): a 4th column is executable program text"; sfail=1; else echo "PASS: selftest — a shell payload in the proof field never reaches sh -c"; fi
  printf '%s\n' "$iout" | grep -q "inj-claim" || { echo "FAIL: selftest — the refused row was not NAMED (an unnamed refusal is unfixable)"; sfail=1; }
  # (b) WIDTH, BOTH DIRECTIONS — 3 fields (the adopter / mid-update skew state) and 5 fields (tomorrow's
  #     extra column) must BOTH fail loudly. Closing the class, not the instance.
  cp "$d/ok.tsv" "$d/narrow.tsv"; printf '%s\t%s\t%s\n' "narrow-claim" "three fields" "true" >> "$d/narrow.tsv"
  nout=$(run_registry "$d/narrow.tsv" 2>&1) && { echo "FAIL: selftest — a 3-field row was accepted (the skew state must be a FAIL, never an empty-proof default)"; sfail=1; } || true
  printf '%s\n' "$nout" | grep -q "expected exactly 4" || { echo "FAIL: selftest — a 3-field row was not refused on WIDTH"; sfail=1; }
  cp "$d/ok.tsv" "$d/wide.tsv"; printf '%s\t%s\t%s\t%s\t%s\n' "wide-claim" "five fields" "true" "tree" "extra" >> "$d/wide.tsv"
  wout=$(run_registry "$d/wide.tsv" 2>&1) && { echo "FAIL: selftest — a 5-field row was accepted (the next column would ride into execution exactly as the 4th did)"; sfail=1; } || true
  printf '%s\n' "$wout" | grep -q "expected exactly 4" || { echo "FAIL: selftest — a 5-field row was not refused on WIDTH"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — a row of any width but 4 is refused before execution"
  # (c) EMPTY PROOF — 4 fields whose last is empty is an explicit FAIL, never a silent default.
  cp "$d/ok.tsv" "$d/skew.tsv"; printf '%s\t%s\t%s\t\n' "skew-claim" "empty proof" "true" >> "$d/skew.tsv"
  if run_registry "$d/skew.tsv" >/dev/null 2>&1; then echo "FAIL: selftest — an EMPTY proof was accepted"; sfail=1; else echo "PASS: selftest — an empty proof is an explicit FAIL"; fi
  # (d) THE DERIVATIONAL LINT — the column must equal what field 3 derives. A row whose verifier
  #     DISPATCHES a --selftest but declares `tree` is a lie, and it is caught by the lint BEFORE the
  #     verifier runs (the fixture verifier exits 0, so execution alone would have passed it).
  printf '#!/bin/sh\nexit 0\n' > "$d/x.sh"
  cp "$d/ok.tsv" "$d/lie.tsv"; printf '%s\t%s\t%s\t%s\n' "lying-claim" "declares tree, dispatches a selftest" "sh $d/x.sh --selftest" "tree" >> "$d/lie.tsv"
  lout=$(run_registry "$d/lie.tsv" 2>&1) && { echo "FAIL: selftest — a proof column contradicting its own verifier was accepted"; sfail=1; } || true
  printf '%s\n' "$lout" | grep -q "derives 'selftest'" || { echo "FAIL: selftest — the lying column was not caught by the derivational lint"; sfail=1; }
  # ...and the honest counterpart passes, so the lint is not simply refusing every selftest row.
  cp "$d/ok.tsv" "$d/hon.tsv"; printf '%s\t%s\t%s\t%s\n' "honest-claim" "declares selftest, dispatches one" "sh $d/x.sh --selftest" "selftest" >> "$d/hon.tsv"
  if run_registry "$d/hon.tsv" >/dev/null 2>&1; then echo "PASS: selftest — a truthfully-declared selftest row passes the lint"; else echo "FAIL: selftest — an honest selftest row was wrongly refused (the lint is refusing everything)"; sfail=1; fi
  # ...and a `--selftest` mention in the CLAIM PROSE is NOT a dispatch: field 3 alone derives the value.
  # (This is the 5-row error that made the split read 33/72 instead of the true 28/72.)
  cp "$d/ok.tsv" "$d/prose.tsv"; printf '%s\t%s\t%s\t%s\n' "prose-claim" "the check is wired and --selftest green" "true" "tree" >> "$d/prose.tsv"
  if run_registry "$d/prose.tsv" >/dev/null 2>&1; then echo "PASS: selftest — a --selftest MENTION in the claim prose does not derive 'selftest'"; else echo "FAIL: selftest — the derivation read the claim prose, not field 3"; sfail=1; fi
  if [ "$sfail" -eq 0 ]; then echo "OK: claims-registry selftest"; exit 0; else echo "FAIL: claims-registry selftest"; exit 1; fi
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: claims-registry.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Claims registry ($REGISTRY):"
if run_registry "$REGISTRY"; then
  echo "OK: every registered headline claim holds; coverage intact"
  exit 0
else
  echo "FAIL: a headline claim drifted, could not be verified, or was dropped (see above)"
  exit 1
fi
