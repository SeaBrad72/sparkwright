#!/bin/sh
# claims-registry.sh — run every claim's verifier in conformance/claims.tsv; fail on drift OR on a
# silently-dropped headline claim. Generalises badge-version.sh from one claim (badge==VERSION) to
# N. The registry is CONTROL-PLANE: adding / removing / weakening a claim is a ratified act — you
# cannot quietly drop a claim's verifier to make CI green (the H1 integrity property).
#   sh conformance/claims-registry.sh [--selftest]
# Exit: 0 = all claims hold or verified nothing here + coverage intact · 1 = drift / unverified / integrity gap · 2 = usage.
# Four verdicts per verifier (mirrors verify.sh): exit 0 = PASS, or N-A when its output DECLARES it verified nothing here (the
# is_self_skip twin below; N-A never reads as holding and is named in the closing line) · exit 2 = UNVERIFIED (could not confirm
# — surfaced, NOT a pass) · other = FAIL (drift). On the kit's own tree an N-A outside NA_ALLOWED (two entries: the guard battery's CI
# deferral, and feature-flags-ready, which has no flag surface to grade on the kit tree) is a FAIL. Verifier output is captured and PRINTED on any
# non-pass, so a CI failure shows WHY (not a swallowed >/dev/null). POSIX sh; dash-clean.
# SCHEMA (PR 10): every data row is EXACTLY 4 tab-separated fields — <id> <claim> <verifier> <proof ∈
# {tree,selftest}>. Width + grammar are graded on the RAW line BEFORE dispatch; any other width, or any
# other proof value including empty, is a FAIL that never reaches a shell (see run_registry).
# Verifier contract: a registered verifier MUST emit only STRUCTURAL diagnostics (verdicts, paths,
# identifier NAMES) — never a secret VALUE — because its stdout+stderr is surfaced on a non-pass.
set -eu

# The registry path is FIXED. It used to read ${KIT_CLAIMS:-…}, which let the environment choose a file whose field 3 this script
# then ran as shell (SWAS-24). No variable, flag or argument replaces it; --selftest drives run_registry with fixture paths directly.
REGISTRY=conformance/claims.tsv
# Headline claims that MUST stay registered (no silent drop). Change this set deliberately + ratified.
REQUIRED_IDS="guard-single-source action-pinning security-policy gate-counts cost-governance supply-chain-verify gitlab-adoption named-adapters actionlint-valid template-detectors-aligned provenance-precondition adopter-preflight mode-blind explain feature-flags-ready token-scope author-not-approver verify-enforced runaway-killswitch version-tag-coherent release-tag-on-merge mirror-immutable-tags promotion-contract promotion-readiness proportional-gate non-vacuity-gate roster-guard branch-protection-declared"

# N-A ALLOWLIST (SWAS-24). On the KIT's own tree (see cr_kit_tree) a row may read N-A only when BOTH its id and the start of its N/A
# line match an entry here. One entry per line, `<id>|<reason prefix>`. Fixed in this script and assigned unconditionally, like
# REQUIRED_IDS: never read from the environment, no KIT_ prefix. Adding an entry is a ratified change. The reason is matched as a
# PREFIX so the `(inputs identical to <ref>)` tail of the guard battery's deferral line may vary.
# Two entries, each with its reason:
#   agent-autonomy-alias: the guard battery is deferred to CI job guard-battery (agent-autonomy.sh), so the bare run verifies nothing.
#   feature-flags-ready:  the kit tree has no feature-flag surface (no flags module, no FEATURE_ convention); the claim is about
#                         ADOPTER trees, so on the kit's own tree this verifier correctly skips itself. Measured on the kit tree.
NA_ALLOWED='agent-autonomy-alias|N/A: agent-autonomy deferred to CI job guard-battery
feature-flags-ready|N/A: . has no feature-flag surface'

TAB=$(printf '\t')
DOT=$(printf '\302\267')   # U+00B7 MIDDLE DOT, the kit-wide summary separator

# cr_kit_tree: 0 on the kit's own tree. The same marker pair verify.sh --kitself and doctor's _pg_kit_tree use; an exported tree
# carries neither, so it stays neutral with no flag. Paths are cwd-relative (callers run from the repo root).
cr_kit_tree() { [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; }

# cr_na_allowed <id> <first N/A line>: 0 when NA_ALLOWED holds an entry whose id matches exactly and whose reason prefixes the line.
cr_na_allowed() {
  while IFS= read -r _na_e; do
    [ -n "$_na_e" ] || continue
    # id compared exactly; the reason by prefix (so a longer id never rides on a shorter entry)
    [ "$1" = "${_na_e%%|*}" ] || continue
    case "$2" in "${_na_e#*|}"*) return 0 ;; esac
  done <<EOF
$NA_ALLOWED
EOF
  return 1
}

# TWIN of verify.sh's is_self_skip, copied verbatim (verify.sh runs code at load, so it cannot be sourced). The selftest locks the
# two bodies byte-identical (cr_twin_lock); change both together.
is_self_skip() {  # <captured-output> — 0 when the child DECLARED it verified nothing here
  printf '%s\n' "$1" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' || return 1
  # ZERO-COUNT REFINEMENT (VERIFY-SKIP-IDIOM-RESIDUAL, face ii): a verdict line that SELF-REPORTS zero
  # verified items suppresses nothing — `OK (0 profile(s) … checked)` is a skip wearing a verdict, and
  # C6's own rule ("N-A means this check verified NOTHING here") says so. Dropped BEFORE the verdict
  # test, so a run with a zero-count line AND a real one still passes on the real one.
  # THE KEY IS THE WHOLE SENTENCE SHAPE, not a bare `(0 `: MEASURED, conformance/*.sh emits `(0 ` on 37
  # lines — `(0 rows)`, `(0 find spawns…)`, `(0 foreign lines…)`, `(0 files)`, `(0 occurrence(s))` — and
  # a loose key would demote every row that prints one. ZERO of the 37 match this key. That tightness is
  # also what protects mechanism 3: a false N-A here would inflate the very `na` the CI walks' floor reads.
  ! printf '%s\n' "$1" | grep -Ev '\(0 [A-Za-z-]+\(s\)[^)]*checked' \
    | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'
}

# cr_na_raw <captured-output>: the first line the self-skip idiom matched, as emitted.
cr_na_raw() {
  printf '%s\n' "$1" | grep -Ei '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' | head -n 1 || true
}

# cr_show <line>: a verifier's line on its way to a screen: every byte outside printable ASCII (control bytes, and the bytes of
# any multibyte character such as a bidi override) shown as `?`, cut to 200 bytes.
cr_show() { printf '%s' "$1" | LC_ALL=C tr -c '\040-\176' '?' | LC_ALL=C cut -c1-200; }

# emit_diag <output>: print captured verifier output indented, so non-pass results are debuggable.
emit_diag() { [ -n "$1" ] && printf '%s\n' "$1" | sed 's/^/    | /' || true; }

# cr_san: strip control bytes from registry text on its way to a screen — a refused row is PRINTED, and
# an ANSI escape in it could erase the line and impersonate a verdict (mb_san's discipline).
cr_san() { LC_ALL=C tr -d '[:cntrl:]'; }

# cr_proof_want <verifier>: the proof DERIVED from FIELD 3 ALONE, on the DISPATCH SHAPE `.sh --selftest`.
# Measured: two rows (verify-enforced, release-tag-on-merge) carry `--selftest` in their claim PROSE and
# dispatch none (three more did until they were removed: doctor and operate-loop by SWAS-626, tier-advice by SWAS-619) —
# reading the whole line is the false 33/72 that the true 28/72 replaces. HONEST CEILING: integrity of DISCLOSURE, not enforcement — no gate consults
# the column, post-grammar it cannot influence execution, and a mention-vs-use fake inside field 3 stays
# constructible with the reviewer as its only detector.
cr_proof_want() { case "$1" in *.sh\ --selftest*) echo selftest ;; *) echo tree ;; esac; }

# rv_run <verifier>: run a verifier ONCE per run_registry pass and set rv_rc / rv_out. A verifier string that already ran in
# this pass reuses its recorded exit code and output (SWAS-201; the wiring check backs three claims). The memo
# is shell variables in this process and nothing else: no file, no environment variable, no flag, so no input from outside the
# run can forge a recorded result. The key is the exact field-3 string. The indexed names are built from a counter this function
# owns; the stored values are never re-parsed (eval sees `\$1` and `\$rv_out`, not their contents).
rv_run() {
  _rv_i=1; _rv_k=''
  while [ "$_rv_i" -le "$_rv_n" ]; do
    eval "_rv_k=\${_rv_key_$_rv_i}"
    if [ "$_rv_k" = "$1" ]; then
      eval "rv_rc=\${_rv_rc_$_rv_i}; rv_out=\${_rv_out_$_rv_i}"
      return 0
    fi
    _rv_i=$((_rv_i + 1))
  done
  if rv_out=$(sh -c "$1" 2>&1); then rv_rc=0; else rv_rc=$?; fi
  _rv_n=$((_rv_n + 1))
  eval "_rv_key_$_rv_n=\$1; _rv_rc_$_rv_n=\$rv_rc; _rv_out_$_rv_n=\$rv_out"
  return 0
}

# run_registry <tsv>: print PASS / N-A / UNVERIFIED / FAIL per claim + coverage gaps, then the closing count line
# `claims: <P> pass · <N> N-A · <U> unverified · <F> fail` (each row is counted once, so P+N+U+F is the row count plus any
# coverage gaps) and, when N > 0, the N-A ids. Returns 1 on any FAIL or UNVERIFIED; an N-A row alone does not fail it, except on the
# kit's own tree, where an N-A outside NA_ALLOWED is a FAIL (counted in F, not N). The counts are left in _cp/_cn/_cu/_cf for cr_report.
run_registry() {
  _reg=$1; _fail=0; _seen=""; _no=0; _rv_n=0
  _cp=0; _cn=0; _cu=0; _cf=0; _nids=""   # the closing line's counts; read by cr_report (this function is never run in a subshell there)
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
    [ "$_nt" -eq 3 ] || { echo "FAIL: registry line $_no is MALFORMED: $((_nt + 1)) tab-separated field(s), expected exactly 4 (<id> <claim> <verifier> <proof>). REFUSED BEFORE EXECUTION — a row this parser cannot read is never dispatched to a shell, so a mis-shaped registry can never run something nobody wrote as a verifier: [$(printf '%s' "$_ln" | cr_san)]"; _fail=1; _cf=$((_cf + 1)); continue; }
    _id=${_ln%%"$TAB"*};      _cr1=${_ln#*"$TAB"}
    _claim=${_cr1%%"$TAB"*};  _cr2=${_cr1#*"$TAB"}
    _verifier=${_cr2%%"$TAB"*}; _proof=${_cr2#*"$TAB"}
    case "$_id" in ''|\#*) continue ;; esac
    if [ -z "$_verifier" ]; then echo "FAIL: claim '$(printf '%s' "$_id" | cr_san)' has no verifier"; _fail=1; _cf=$((_cf + 1)); continue; fi
    # ── PROOF GRAMMAR, ALSO BEFORE ANY SHELL: ^(tree|selftest)$ or FAIL. An EMPTY proof (the half-updated
    # / mid-`kit-update-merge` skew state) is an explicit FAIL, never a default — a silently-defaulted
    # column discloses nothing and hides the skew. Then THE DERIVATIONAL LINT: the declared value must
    # equal what field 3 derives, which is what keeps the disclosed split honest without a hand re-measure.
    case "$_proof" in tree|selftest) : ;;
      *) echo "FAIL: claim '$(printf '%s' "$_id" | cr_san)' has proof [$(printf '%s' "$_proof" | cr_san)]; want exactly 'tree' or 'selftest'. An empty or off-grammar proof is a FAIL, not a default, and it is graded before the verifier runs so the cell can never become program text."; _fail=1; _cf=$((_cf + 1)); continue ;;
    esac
    _want=$(cr_proof_want "$_verifier")
    [ "$_proof" = "$_want" ] || { echo "FAIL: claim '$(printf '%s' "$_id" | cr_san)' declares proof '$_proof' but its verifier derives '$_want' — the registry's disclosed tree-vs-selftest split would be a lie. Fix the column, or the verifier."; _fail=1; _cf=$((_cf + 1)); continue; }
    case " $_seen " in *" $_id "*) echo "FAIL: duplicate claim id '$(printf '%s' "$_id" | cr_san)'"; _fail=1; _cf=$((_cf + 1)); continue ;; esac
    _seen="$_seen $_id"
    # Capture output + exit code (set -e-safe). Classify three-state; surface diagnostics on non-pass.
    rv_run "$_verifier"
    if [ "$rv_rc" = 0 ]; then
      if is_self_skip "$rv_out"; then
        # The verifier exited 0 but DECLARED it verified nothing here: that is N-A, never PASS (the kit's C6 vocabulary).
        _nraw=$(cr_na_raw "$rv_out")
        # THE KIT-TREE FLOOR: on the kit's own tree only an NA_ALLOWED deferral may be N-A; anything else is a FAIL, counted once (F).
        if cr_kit_tree && ! cr_na_allowed "$_id" "$_nraw"; then
          echo "FAIL: $(printf '%s' "$_id" | cr_san) — N-A on the kit's own tree: $(cr_show "$_nraw")"
          _fail=1; _cf=$((_cf + 1))
        else
          echo "N-A: $(printf '%s' "$_id" | cr_san) — $(cr_show "$_nraw")"
          _cn=$((_cn + 1)); _nids="$_nids $(printf '%s' "$_id" | cr_san)"
        fi
      else
        echo "PASS: $_id"
        _cp=$((_cp + 1))
      fi
    else
      if [ "$rv_rc" = 2 ]; then
        echo "UNVERIFIED: $_id — verifier could not confirm (exit 2): $_verifier"
        _cu=$((_cu + 1))
      else
        echo "FAIL: $_id — verifier reports drift (exit $rv_rc): $_verifier"
        _cf=$((_cf + 1))
      fi
      emit_diag "$rv_out"
      _fail=1
    fi
  done < "$_reg"
  for _r in $REQUIRED_IDS; do
    case " $_seen " in *" $_r "*) : ;; *) echo "FAIL: required claim '$_r' missing from registry (silent drop)"; _fail=1; _cf=$((_cf + 1)) ;; esac
  done
  printf 'claims: %d pass %s %d N-A %s %d unverified %s %d fail\n' "$_cp" "$DOT" "$_cn" "$DOT" "$_cu" "$DOT" "$_cf"
  [ "$_cn" -eq 0 ] || echo "N-A ids (verified nothing here, not shown as holding):$_nids"
  return $_fail
}

# cr_report <tsv>: run_registry plus the closing sentence. The OK sentence says "holds" outright only when no row read N-A.
cr_report() {
  if run_registry "$1"; then
    if [ "$_cn" -eq 0 ]; then
      echo "OK: every registered headline claim holds; coverage intact"
    else
      echo "OK: every registered headline claim holds or verified nothing here; the N-A ids are listed above; coverage intact"
    fi
    return 0
  fi
  echo "FAIL: a headline claim drifted, could not be verified, or was dropped (see above)"
  return 1
}

# cr_twin_body <file>: the lines of is_self_skip() in <file>, from its opening line to the first closing brace at column 0.
cr_twin_body() { awk '/^is_self_skip\(\) *\{/ { f = 1 } f { print } f && /^}$/ { exit }' "$1"; }

# cr_twin_lock <file-a> <file-b>: 0 only when both bodies are readable, at least 3 lines, and byte-identical. An empty extraction
# (a renamed function, an unreadable file) is a refusal, never a match of two empties. Nothing is eval'd.
cr_twin_lock() {
  [ -r "$1" ] || { echo "unreadable: $1"; return 1; }
  [ -r "$2" ] || { echo "unreadable: $2"; return 1; }
  _tl_a=$(cr_twin_body "$1"); _tl_b=$(cr_twin_body "$2")
  [ "$(printf '%s\n' "$_tl_a" | wc -l | tr -d ' ')" -ge 3 ] || { echo "no is_self_skip body (3+ lines) in $1"; return 1; }
  [ "$(printf '%s\n' "$_tl_b" | wc -l | tr -d ' ')" -ge 3 ] || { echo "no is_self_skip body (3+ lines) in $2"; return 1; }
  [ "$_tl_a" = "$_tl_b" ] || { echo "is_self_skip bodies differ: $1 vs $2"; return 1; }
  return 0
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
  cp "$d/ok.tsv" "$d/dup.tsv"; printf '%s\t%s\ttrue\ttree\n' "gate-counts" "dup" >> "$d/dup.tsv"
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
  # (e) THE IN-RUN MEMO (SWAS-201). A verifier string that already ran in this pass is not run again, yet every row it covers still
  #     prints its own verdict under its own id, and a non-pass still prints its diagnostics on every row. The oracle is a side
  #     effect (an append to a marker file), not the output text. A row with a different verifier string still runs.
  cp "$d/ok.tsv" "$d/memo.tsv"
  for m in a b c; do printf '%s\t%s\t%s\t%s\n' "memo-$m" "shared verifier $m" "echo ran >> $d/memo-marker" "tree" >> "$d/memo.tsv"; done
  printf '%s\t%s\t%s\t%s\n' "memo-d" "a different verifier" "echo ran >> $d/memo-marker-d" "tree" >> "$d/memo.tsv"
  mout=$(run_registry "$d/memo.tsv" 2>&1) || { echo "FAIL: selftest — the memo fixture registry was rejected"; sfail=1; }
  [ "$(wc -l < "$d/memo-marker" 2>/dev/null | tr -d ' ')" = 1 ] || { echo "FAIL: selftest — a verifier shared by three rows did not run exactly once"; sfail=1; }
  [ "$(wc -l < "$d/memo-marker-d" 2>/dev/null | tr -d ' ')" = 1 ] || { echo "FAIL: selftest — a row with a different verifier string did not run"; sfail=1; }
  [ "$(printf '%s\n' "$mout" | grep -c '^PASS: memo-')" = 4 ] || { echo "FAIL: selftest — a memoised row did not print its own PASS line under its own id"; sfail=1; }
  cp "$d/ok.tsv" "$d/memof.tsv"
  for m in x y z; do printf '%s\t%s\t%s\t%s\n' "memo-$m" "shared failing verifier $m" "echo ran >> $d/memo-marker-f; echo shared-diag; exit 1" "tree" >> "$d/memof.tsv"; done
  fout=$(run_registry "$d/memof.tsv" 2>&1) && { echo "FAIL: selftest — a shared failing verifier did not fail the registry"; sfail=1; } || true
  [ "$(wc -l < "$d/memo-marker-f" 2>/dev/null | tr -d ' ')" = 1 ] || { echo "FAIL: selftest — a shared failing verifier did not run exactly once"; sfail=1; }
  [ "$(printf '%s\n' "$fout" | grep -c '^FAIL: memo-')" = 3 ] || { echo "FAIL: selftest — a memoised failing verifier did not print a FAIL line on each row it covers"; sfail=1; }
  [ "$(printf '%s\n' "$fout" | grep -c '^    | shared-diag$')" = 3 ] || { echo "FAIL: selftest — a memoised failure's diagnostic was not printed on each row it covers"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — a repeated verifier runs once, and every row it covers keeps its own verdict and diagnostics"

  # ── THE N-A VERDICT (SWAS-24). A verifier that exits 0 but DECLARES it verified nothing reads N-A, never PASS. The cells run
  # cr_report inside a chosen directory, because the kit-tree floor reads the cwd's marker files: nokit has neither marker, kitd has
  # docs/ROADMAP-KIT.md, kitg has .github/workflows/golden-path.yml. Fixture verifiers are absolute / self-contained.
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  mkdir -p "$d/nokit" "$d/kitd/docs" "$d/kitg/.github/workflows"
  : > "$d/kitd/docs/ROADMAP-KIT.md"; : > "$d/kitg/.github/workflows/golden-path.yml"
  nreq=$(printf '%s\n' $REQUIRED_IDS | wc -l | tr -d ' ')
  # mkrow <out> <id> <verifier>: ok.tsv with one row's verifier replaced (ENVIRON, so no escape processing of the text).
  mkrow() { V=$3 I=$2 awk -F'\t' 'BEGIN { OFS = "\t" } $1 == ENVIRON["I"] { $3 = ENVIRON["V"] } { print }' "$d/ok.tsv" > "$1"; }
  # inrun <dir> <tsv>: cr_report from inside <dir>; rc is the report's.
  inrun() { ( cd "$1" && cr_report "$2" 2>&1 ); }
  DEFER='printf "N/A: agent-autonomy deferred to CI job guard-battery (inputs identical to abc123)\n"'
  # 1. a self-skip on a tree without kit markers: N-A, not PASS, rc 0.
  mkrow "$d/na1.tsv" gate-counts "printf 'N/A: nothing to verify here\n'"
  rc=0; o=$(inrun "$d/nokit" "$d/na1.tsv") || rc=$?
  [ "$rc" = 0 ] || { echo "FAIL: selftest — an N-A on an unmarked tree did not exit 0 (rc $rc)"; sfail=1; }
  printf '%s\n' "$o" | grep -q '^N-A: gate-counts — N/A: nothing to verify here$' || { echo "FAIL: selftest — a self-skip did not render 'N-A: <id> — <line>'"; sfail=1; }
  printf '%s\n' "$o" | grep -q '^PASS: gate-counts' && { echo "FAIL: selftest — a self-skip still rendered PASS"; sfail=1; } || true
  # 2. N/A beside a real OK line stays PASS (a partial skip verified something).
  mkrow "$d/na2.tsv" gate-counts "printf 'N/A: one profile\nOK: checked 3\n'"
  o=$(inrun "$d/nokit" "$d/na2.tsv") || true
  printf '%s\n' "$o" | grep -q '^PASS: gate-counts' || { echo "FAIL: selftest — N/A beside a real OK line was demoted from PASS"; sfail=1; }
  # 3. the zero-count refinement: an OK line that reports zero checked suppresses nothing.
  mkrow "$d/na3.tsv" gate-counts "printf 'N/A: no profiles\nOK (0 profile(s) checked)\n'"
  o=$(inrun "$d/nokit" "$d/na3.tsv") || true
  printf '%s\n' "$o" | grep -q '^N-A: gate-counts' || { echo "FAIL: selftest — 'OK (0 profile(s) checked)' beside N/A did not read N-A (zero-count refinement lost)"; sfail=1; }
  # 4. the closing line counts and names the N-A, and the OK sentence uses the 'or verified nothing here' form.
  rc=0; o=$(inrun "$d/nokit" "$d/na1.tsv") || rc=$?
  want=$(printf 'claims: %d pass %s 1 N-A %s 0 unverified %s 0 fail' "$((nreq - 1))" "$DOT" "$DOT" "$DOT")
  printf '%s\n' "$o" | grep -qxF "$want" || { echo "FAIL: selftest — the closing line did not read [$want]"; sfail=1; }
  printf '%s\n' "$o" | grep -q '^N-A ids .*: gate-counts$' || { echo "FAIL: selftest — the closing line did not name the N-A id"; sfail=1; }
  printf '%s\n' "$o" | grep -qF 'holds or verified nothing here; the N-A ids are listed above' || { echo "FAIL: selftest — the OK sentence did not use the N-A form"; sfail=1; }
  o=$(inrun "$d/nokit" "$d/ok.tsv") || true
  printf '%s\n' "$o" | grep -qxF 'OK: every registered headline claim holds; coverage intact' || { echo "FAIL: selftest — an all-PASS run lost its plain OK sentence"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — a self-skip reads N-A (not PASS), partial skips stay PASS, the zero-count refinement holds, the closing line counts and names it"
  # 5. the kit-tree floor, each marker alone arming it.
  cp "$d/ok.tsv" "$d/aa.tsv"; V=$DEFER; printf '%s\t%s\t%s\t%s\n' agent-autonomy-alias "the guard battery" "$V" tree >> "$d/aa.tsv"
  cp "$d/ok.tsv" "$d/aaother.tsv"; printf '%s\t%s\t%s\t%s\n' agent-autonomy-alias "the guard battery" "printf 'N/A: some other reason\n'" tree >> "$d/aaother.tsv"
  mkrow "$d/otherid.tsv" gate-counts "$DEFER"
  for kd in kitd kitg; do
    rc=0; o=$(inrun "$d/$kd" "$d/aa.tsv") || rc=$?
    [ "$rc" = 0 ] || { echo "FAIL: selftest — [$kd] the allowed deferral on the kit tree did not exit 0 (rc $rc)"; sfail=1; }
    printf '%s\n' "$o" | grep -q '^N-A: agent-autonomy-alias — N/A: agent-autonomy deferred' || { echo "FAIL: selftest — [$kd] the allowed deferral did not render N-A"; sfail=1; }
    rc=0; o=$(inrun "$d/$kd" "$d/aaother.tsv") || rc=$?
    [ "$rc" = 1 ] || { echo "FAIL: selftest — [$kd] the allowed id with another N/A reason did not exit 1 (rc $rc)"; sfail=1; }
    rc=0; o=$(inrun "$d/$kd" "$d/otherid.tsv") || rc=$?
    [ "$rc" = 1 ] || { echo "FAIL: selftest — [$kd] another id reading N-A on the kit tree did not exit 1 (rc $rc)"; sfail=1; }
    printf '%s\n' "$o" | grep -q '^FAIL: gate-counts' || { echo "FAIL: selftest — [$kd] the refused N-A did not name its id"; sfail=1; }
    printf '%s\n' "$o" | grep -q '^N-A: gate-counts' && { echo "FAIL: selftest — [$kd] a refused N-A was also counted as an N-A row"; sfail=1; } || true
    want=$(printf 'claims: %d pass %s 0 N-A %s 0 unverified %s 1 fail' "$((nreq - 1))" "$DOT" "$DOT" "$DOT")
    printf '%s\n' "$o" | grep -qxF "$want" || { echo "FAIL: selftest — [$kd] P+N+U+F did not equal the row count once (want [$want])"; sfail=1; }
    rc=0; o=$(inrun "$d/$kd" "$d/ok.tsv") || rc=$?
    [ "$rc" = 0 ] || { echo "FAIL: selftest — [$kd] an all-PASS registry on the kit tree did not exit 0 (rc $rc)"; sfail=1; }
  done
  # the second entry: feature-flags-ready has no flag surface on the kit tree, so its skip line is allowed there (by id AND reason).
  mkrow "$d/ffok.tsv" feature-flags-ready "printf 'N/A: . has no feature-flag surface (no flags module) — skipping\n'"
  mkrow "$d/ffbad.tsv" feature-flags-ready "printf 'N/A: some other reason\n'"
  rc=0; o=$(inrun "$d/kitd" "$d/ffok.tsv") || rc=$?
  [ "$rc" = 0 ] || { echo "FAIL: selftest — the feature-flags-ready skip on the kit tree did not exit 0 (rc $rc)"; sfail=1; }
  printf '%s\n' "$o" | grep -q '^N-A: feature-flags-ready' || { echo "FAIL: selftest — the allowed feature-flags-ready skip did not render N-A"; sfail=1; }
  rc=0; o=$(inrun "$d/kitg" "$d/ffbad.tsv") || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: selftest — feature-flags-ready with another N/A reason on the kit tree did not exit 1 (rc $rc)"; sfail=1; }
  # a reason that only STARTS like the id (a longer id) never rides on a shorter entry
  mkrow "$d/ffid.tsv" gate-counts "printf 'N/A: . has no feature-flag surface\n'"
  rc=0; o=$(inrun "$d/kitd" "$d/ffid.tsv") || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: selftest — another id carrying the feature-flags-ready reason was allowed (rc $rc)"; sfail=1; }
  # every byte outside printable ASCII is shown as '?': a bidi override (U+202E), built at runtime from octal escapes
  mkrow "$d/bidi.tsv" gate-counts "printf 'N/A: x\342\200\256y\n'"
  o=$(inrun "$d/nokit" "$d/bidi.tsv") || true
  ln=$(printf '%s\n' "$o" | grep '^N-A: gate-counts — ')
  [ "$ln" = "N-A: gate-counts — N/A: x???y" ] || { echo "FAIL: selftest — a multibyte bidi override in an N/A line was not shown as ???"; sfail=1; }
  rc=0; o=$(inrun "$d/nokit" "$d/otherid.tsv") || rc=$?
  [ "$rc" = 0 ] || { echo "FAIL: selftest — the same N-A on an unmarked tree must stay rc 0 (rc $rc)"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — on a kit-marked tree only the NA_ALLOWED (id, reason) may read N-A; each marker alone arms the floor; an unmarked tree stays neutral"
  # NA_ALLOWED is not read from the environment: a hostile value in the environment changes nothing (real script, kit-marked dir).
  mkdir -p "$d/rtk/conformance" "$d/rtk/docs"; : > "$d/rtk/docs/ROADMAP-KIT.md"; cp "$d/otherid.tsv" "$d/rtk/conformance/claims.tsv"
  rc=0; o=$( cd "$d/rtk" && env NA_ALLOWED='gate-counts|N/A' sh "$_self" 2>&1 ) || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: selftest — an NA_ALLOWED value in the environment was honoured (rc $rc)"; sfail=1; }
  # 6. an N-A beside a FAIL is rc 1; an UNVERIFIED row is counted in the closing line.
  cp "$d/na1.tsv" "$d/nafail.tsv"; printf '%s\t%s\t%s\t%s\n' extra-bad drifted "exit 1" tree >> "$d/nafail.tsv"; printf '%s\t%s\t%s\t%s\n' unv-claim unverifiable "exit 2" tree >> "$d/nafail.tsv"
  rc=0; o=$(inrun "$d/nokit" "$d/nafail.tsv") || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: selftest — an N-A beside a FAIL did not exit 1 (rc $rc)"; sfail=1; }
  printf '%s\n' "$o" | grep -qE " 1 N-A $DOT 1 unverified $DOT 1 fail\$" || { echo "FAIL: selftest — the closing line did not count N-A, unverified and fail"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — N-A plus a FAIL exits 1 and the closing line counts the unverified row"
  # 7. the twin lock: identical passes; one byte of drift reds; both renamed reds (empty extraction refused); an unreadable file reds.
  vsh=$(dirname "$_self")/verify.sh
  cr_twin_lock "$vsh" "$_self" >/dev/null || { echo "FAIL: selftest — the live is_self_skip twin differs from verify.sh's (or verify.sh is unreadable)"; sfail=1; }
  cr_twin_body "$_self" > "$d/twin-a"; { echo "# header"; cat "$d/twin-a"; } > "$d/twin-a.sh"
  cr_twin_body "$_self" | sed 's/SKIP:/SKIq:/' > "$d/twin-b"; { echo "# header"; cat "$d/twin-b"; } > "$d/twin-b.sh"
  cr_twin_lock "$d/twin-a.sh" "$d/twin-a.sh" >/dev/null || { echo "FAIL: selftest — twin lock refused two identical bodies"; sfail=1; }
  cr_twin_lock "$d/twin-a.sh" "$d/twin-b.sh" >/dev/null && { echo "FAIL: selftest — twin lock passed one byte of drift"; sfail=1; } || true
  sed 's/^is_self_skip/is_self_skip_x/' "$d/twin-a.sh" > "$d/twin-r1.sh"; cp "$d/twin-r1.sh" "$d/twin-r2.sh"
  cr_twin_lock "$d/twin-r1.sh" "$d/twin-r2.sh" >/dev/null && { echo "FAIL: selftest — twin lock passed two files whose function is renamed (empty extraction)"; sfail=1; } || true
  cr_twin_lock "$d/no-such-verify.sh" "$d/twin-a.sh" >/dev/null && { echo "FAIL: selftest — twin lock passed an unreadable file"; sfail=1; } || true
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — the is_self_skip twin is locked to verify.sh (drift, rename and unreadable all red)"
  # 8. KIT_CLAIMS is ignored: the real script reads conformance/claims.tsv only; the hostile registry's command never runs.
  mkdir -p "$d/rt/conformance"; cp "$d/ok.tsv" "$d/rt/conformance/claims.tsv"
  printf '%s\t%s\t%s\t%s\n' hostile "runs a command" "touch $d/sentinel" tree > "$d/hostile.tsv"
  rc=0; o=$( cd "$d/rt" && env KIT_CLAIMS="$d/hostile.tsv" sh "$_self" 2>&1 ) || rc=$?
  [ ! -e "$d/sentinel" ] || { echo "FAIL: selftest — KIT_CLAIMS chose a registry whose command RAN"; sfail=1; }
  printf '%s\n' "$o" | grep -qF 'Claims registry (conformance/claims.tsv):' || { echo "FAIL: selftest — the registry path followed the environment"; sfail=1; }
  [ "$rc" = 0 ] || { echo "FAIL: selftest — the fixed registry was not the one graded (rc $rc)"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — KIT_CLAIMS is ignored; the fixed registry is graded and no hostile command runs"
  # 9. a long N/A line is cut to 200 bytes; a control byte in it is shown as '?'.
  mkrow "$d/long.tsv" gate-counts "printf 'N/A: %0300d\n' 0"
  o=$(inrun "$d/nokit" "$d/long.tsv") || true
  ln=$(printf '%s\n' "$o" | grep '^N-A: gate-counts — ')
  msg=${ln#"N-A: gate-counts — "}
  [ "$(printf '%s' "$msg" | wc -c | tr -d ' ')" = 200 ] || { echo "FAIL: selftest — a long N/A line was not cut to 200 bytes"; sfail=1; }
  mkrow "$d/ctl.tsv" gate-counts "printf 'N/A: a\001b\033c\n'"
  o=$(inrun "$d/nokit" "$d/ctl.tsv") || true
  ln=$(printf '%s\n' "$o" | grep '^N-A: gate-counts — ')
  [ "$ln" = "N-A: gate-counts — N/A: a?b?c" ] || { echo "FAIL: selftest — control bytes in an N/A line were not shown as '?'"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — an N/A line is cut to 200 bytes with control bytes shown as '?'"
  if [ "$sfail" -eq 0 ]; then echo "OK: claims-registry selftest"; exit 0; else echo "FAIL: claims-registry selftest"; exit 1; fi
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: claims-registry.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Claims registry ($REGISTRY):"
if cr_report "$REGISTRY"; then exit 0; else exit 1; fi
