#!/bin/sh
# Why this gate: sparkwright explain threat-model
# threat-obligation.sh — HITL obligation: a change-set touching a sensitive/regulated-data
# surface MUST carry a filled THREAT-MODEL record, else FAIL. Diff-level (vs readiness.sh privacy-ready's
# project-level declaration) — they compose, not collide.
#
# SURFACE (HITL-1 + HITL-5): the SENSITIVE half (`*secret*`/`*auth*`/`*password*`/`*payment*`/
# `migrations/`/`.env`) shipped in HITL-1; the REGULATED-DATA half (pii · gdpr · patient · cardholder ·
# phi · ssn · personal-data) is HITL-5 and is APPENDED, never merged — see $THREAT_LEGACY_GLOBS /
# $THREAT_REGULATED_GLOBS below for why the split is a correctness device and where the measured
# false-positive cost of the second half is recorded.
#
# RENAMES ARE FOLLOWED (H1): the engine's derivation passes `--no-renames`, so a file MOVED off a
# sensitive/regulated path still triggers on its SOURCE path. Before that, git's default rename detection
# emitted only the DESTINATION and a `git mv` in the same PR silently derived N/A — measured, an edit to
# `svc2/pii/export.py` FAILed in place and the same edit moved to `svc2/core/export.py` (R098) read N/A.
#
# SCOPE (honest ceiling): green = a THREAT-MODEL record EXISTS and is FILLED for a triggered change —
# NOT that it is fresh-for-this-change, nor that the threat analysis is sound (review backstops).
# N-A = the change-set touches no sensitive surface (trigger-absence), exactly like readiness.sh privacy-ready.
# The regulated half adds a ceiling of its own: it is a PATH heuristic, so a file holding PII under a
# neutral name (`src/models/user.rb`) is still N/A. readiness.sh privacy-ready's project-level declaration and
# review are what cover that — this gate is diff-relative and name-based, and claims nothing more.
#
# Usage:
#   sh conformance/threat-obligation.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/threat-obligation.sh --changed FILE  (fixture path list; honored ONLY under
#                                                         --selftest / the KIT_OBL_TEST env flag — ignored in production)
#   sh conformance/threat-obligation.sh --selftest
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` is the correct idiom: it clears CDPATH for this one command so
# a user's CDPATH cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Tell the engine it is being SOURCED (not executed directly), so its --selftest dispatch stays inert
# here: without this, `sh threat-obligation.sh --selftest` would run the LIB's selftest (the sourced
# lib sees $1=--selftest) instead of this obligation's 9-leg selftest. Value is 'yes' (NOT '=1') so the
# non-vacuity sweep — which neuters a pre-marker <var>=1 — cannot flip it; this line carries no mutable
# idiom, so run_threat_obligation stays the (idiomless) mutation region and this file's verdict is
# unchanged. A $0-basename guard would not survive the sweep renaming the lib's copy to .nv-mut-*.
OBL_LIB_SOURCED=yes
. "$DIR/conformance/obligation-lib.sh"

# The obligation: sensitive-surface globs + THREAT-MODEL record.
#
# THE SURFACE IS TWO CONSTANTS CONCATENATED, and that is a correctness device rather than tidiness.
# HITL-5's requirement is that adding the regulated-data half be MONOTONE — nothing that triggered
# before may stop triggering. Written as one edited string, "I appended and changed nothing" is a claim
# a reviewer has to verify by eye against git history. Written as $THREAT_LEGACY_GLOBS (byte-identical
# to the shipped HITL-1 surface) plus $THREAT_REGULATED_GLOBS, monotonicity is STRUCTURAL — the old
# surface still exists as its own value — and it is also proved BEHAVIOURALLY twice: the coverage leg
# probes all six legacy globs, and the load-bearing negative runs a regulated path against
# $THREAT_LEGACY_GLOBS alone and requires it to come back N/A.
THREAT_LEGACY_GLOBS='*secret*|*auth*|*password*|*payment*|*migrations/*|*.env'

# HITL-5 — THE REGULATED-DATA HALF. This check's title has always said "sensitive/regulated-data"; only
# the sensitive half was enforced, and readiness.sh privacy-ready does not close the gap because it is
# DECLARATION-triggered (a project that never wrote a `Data classification:` line stays N/A while a PR
# introduces PII handling). POSTURE IS FAIL-SAFE, owner-ratified: for regulated data over-triggering
# beats under-triggering, because PHI/PII shipping unreviewed is categorically worse than one
# unnecessary threat model.
#
# WHY THE SHAPE IS WHAT IT IS — measured, not chosen. `obl_detect` matches with POSIX `case`, which is
# CASE-SENSITIVE, and acronyms are conventionally uppercase, so a lowercase-only glob would be a false
# NEGATIVE on exactly the highest-consequence files (`PHI_export.ts`, `PII_handler.py`). Hence the
# bracket casing. Against that, `phi` and `ssn` are SEGMENT-ANCHORED rather than bare substrings: a bare
# `*phi*` measured 982 hits on a 162k-file corpus (graphics.py, sphinxext.py, morphism.ts — 0.6% of every
# file in a typical tree) and a bare `*ssn*` measured 21 (getElementsByClassName.js — cla-ssn-ame). LEG 8
# holds those four decoys N/A forever.
#
# THE CASING IS NOW APPLIED TO EVERY LETTER OF SIX OF THE SEVEN TOKENS, and it was not before — that
# inconsistency was a live false NEGATIVE rather than a style blemish. `patient` and `cardholder` shipped
# cased on their FIRST LETTER ONLY (`*[Pp]atient*`) and `personal-data` shipped uncased, so the argument
# in the paragraph above was applied to four tokens of seven. Measured against the surface as it shipped:
# `data/PATIENT_EXPORT.csv`, `db/CARDHOLDER_DATA.sql` and `export/Personal-Data/dump.csv` were all N/A
# while `src/PHI_EXPORT.ts` red-ed — and ALL-CAPS is a live convention for exactly this file class (SQL
# exports, migration dumps). The repair is OWNER-RATIFIED, and it was RE-MEASURED on the corpus below
# before shipping rather than inherited: `*[Pp][Aa][Tt][Ii][Ee][Nn][Tt]*` -> 0 hits,
# `*[Cc][Aa][Rr][Dd][Hh][Oo][Ll][Dd][Ee][Rr]*` -> 0, `*/[Pp]ersonal-[Dd]ata/*` -> 0, and the regulated
# half's TOTAL is 11 both before and after the swap. On real trees the widening is free. The probe table
# in LEG 9 carries the three ALL-CAPS paths (so the casing itself is load-bearing, not just the token),
# while LEG 7 keeps the lowercase forms — both directions stay proven.
#
# THE RESIDUAL FALSE POSITIVES, RE-MEASURED ON THIS BUILD rather than inherited — a 243,157-path corpus
# of real project trees, matched with `case` (the engine's own matcher). Every number in this comment is
# from that one corpus, re-run for this commit; a reviewer's larger 266,727-path corpus scored `pii` one
# higher, which is why the corpus is named beside each figure rather than left implicit. Two of the
# numbers this surface was ratified on did NOT reproduce, and understating a gate's cost is the same
# defect as overstating it:
#  - `*[Pp][Ii][Ii]*` -> 8 hits, NOT the 0 the design table recorded. That 0 was measured for the BARE
#    token `pii` (which does still measure 0 here); the bracket casing was added afterwards and never
#    re-measured, and it admits all eight case permutations. Every hit is the camelCase collision
#    `…OpenApiIn…` — `a-p-i-I-n` contains `piI`. The class is real and common in TS/Java identifiers
#    (`apiId`, `apiIndex`, `openApiInput`), so it is not a corpus artifact.
#  - `*-[Pp][Hh][Ii]*` -> 3 hits, ALL of the same shape: `about-philosophy.tsx`,
#    `transform-philosophy.tsx`, `rendering-philosophy.md`. The separator anchors the LEFT side only, so
#    `-phi` also matches `-philosophy`/`-phil`. Segment-anchoring cut the 982 to 3, not to 0.
# ACCEPTED, with the scale stated so the trade is auditable rather than asserted: 11 hits in 243,157
# paths is 0.005%, against 482 hits for the ALREADY-SHIPPED `*auth*` (which matches this kit's own
# `conformance/author-not-approver-wired.sh`, and 23 `oauth` paths) and 179 for `*secret*` on the same
# corpus — both measured on the same run. The regulated half is ~44x quieter than one glob
# this gate has shipped since HITL-1, which is what makes the fail-safe posture affordable.
# THE NARROWER `pii` ALTERNATIVE (`*pii*|*PII*|*Pii*`, re-measured at 0 hits) is deliberately NOT taken —
# it is under-triggering on the highest-consequence file class, the direction the ratified posture
# forbids — but its case is stronger than the raw counts suggest, so it is recorded here and BOARDED for
# the owner rather than argued away: all EIGHT `*[Pp][Ii][Ii]*` hits are vendored `node_modules` paths
# (svix's `eventTypeImportOpenApiIn.*`), which a repo that gitignores its dependencies never puts in a
# diff, so this DIFF-RELATIVE gate's real cost from `pii` is nearer zero than 8 — whereas 2 of the 3
# `*-[Pp][Hh][Ii]*` hits sit in `src/app/…` and would appear in a diff.
THREAT_REGULATED_GLOBS='*[Pp][Ii][Ii]*|*[Gg][Dd][Pp][Rr]*|*[Pp][Aa][Tt][Ii][Ee][Nn][Tt]*|*[Cc][Aa][Rr][Dd][Hh][Oo][Ll][Dd][Ee][Rr]*|*/[Pp][Hh][Ii]/*|*[Pp][Hh][Ii]_*|*_[Pp][Hh][Ii]*|*-[Pp][Hh][Ii]*|*/[Ss][Ss][Nn]/*|*[Ss][Ss][Nn]_*|*_[Ss][Ss][Nn]*|*-[Ss][Ss][Nn]*|*/[Pp]ersonal-[Dd]ata/*'

# HONEST CEILING of the regulated half: it is a PATH heuristic and nothing more. `src/models/user.rb`
# holding PII with no telltale token in its name is still N/A, and anchoring `phi`/`ssn` widens that
# recall gap deliberately in exchange for the 982 false positives above. What closes the residual is the
# project-level declaration gate (readiness.sh privacy-ready) and review — not this glob list.
# AND THE VOCABULARY IS EXACTLY SEVEN TOKENS — pii · gdpr · patient · cardholder · phi · ssn ·
# personal-data — so the misses are NAMED here rather than left to be inferred from the phrase "path
# heuristic". `medical/`, `biometric`, `passport`, `iban`, `tax_id`, `nhs_number`, `dob` and `mrn` all
# derive N/A on this gate, as does every other regulated-data token nobody thought of. Stated because a
# ceiling that only says "it is a heuristic" reads as comfortable; a ceiling that lists what it does not
# catch reads as a boundary. Widening the vocabulary is a RATIFIED decision, not a builder's — the same
# rule that left THREAT-PERSONAL-DATA-FULL-CASING boarded rather than taken.
# AND THE CASING IS STILL NOT UNIFORM — stated here because the paragraph above would otherwise read as
# a claim that it is. Six of the seven tokens are cased on every letter; `personal-data` is cased per
# WORD (`*/[Pp]ersonal-[Dd]ata/*`), so an ALL-CAPS directory — `data/PERSONAL-DATA/dump.csv` — is still
# N/A. That is the string the owner ratified, taken as ratified. The full-bracket alternative measures 0
# hits on the same 243,157-path corpus, so closing that last gap is free; it is BOARDED rather than
# taken, because widening a security surface past what was ratified is not a call this file makes on its
# own — which is the whole reason the four-of-seven inconsistency above was left for the owner too.
#
# THE SURFACE STRING IS THE SINGLE SOURCE OF TRUTH for the coverage leg: every glob in it must appear in
# $THREAT_GLOB_PROBES with a probe path, and every probe must be proved to sit on the glob it is named
# against (see LEG 9). A glob added here without its probe reds; a probe naming a glob that is not here
# reds; a glob deleted reds on the count lock.
THREAT_SURFACE_GLOBS="$THREAT_LEGACY_GLOBS$OBL_GLOB_SEP$THREAT_REGULATED_GLOBS"

# The `--` before "$@" is LOAD-BEARING, not decoration: it closes this check's own definition, and the
# engine refuses the six gate-defining arguments after it. Without it a caller could append
# `--stub-pattern …` and switch Signal 2 off from the command line — the engine's first-assignment-wins
# rule cannot defend an argument this file never sets (measured before the fix: the bare command FAILed,
# the same command with `--stub-pattern '\[zzz'` PASSed). LEG 6 below is the proof; delete the `--` and it
# reds. The fixture flags in "$@" (--changed/--root/--force-uncertain) still parse — the sentinel fences
# only the six.
run_threat_obligation() {   # args: forwarded (--changed FILE | none)
  obligation_gate \
    --name "threat-model" \
    --surface-globs "$THREAT_SURFACE_GLOBS" \
    --record "THREAT-MODEL.md" \
    --template-marker "templates/THREAT-MODEL-TEMPLATE.md" \
    -- \
    "$@"
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/threat-st.XXXXXX")"; trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0
  # LEG 1 (liveness/negative): sensitive surface touched, NO record -> RED
  printf 'src/auth/login.js\n' > "$_tmp/changed"
  if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: sensitive surface with no THREAT-MODEL did not FAIL"; rc=1
  fi
  # LEG 2 (positive): no sensitive surface -> green (N-A)
  printf 'docs/README.md\n' > "$_tmp/changed"
  if ! run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: non-sensitive change did not pass (N-A)"; rc=1
  fi
  # LEG 3 (fail-safe, simulated): --force-uncertain simulates the uncertain band (the derived path has no
  # per-file uncertain heuristic; the REAL uncertain trigger is a derive-failure — LEG 4). NO record -> RED
  printf 'config/settings.yaml\n' > "$_tmp/changed"
  if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" --force-uncertain >/dev/null 2>&1; then
    echo "SELFTEST FAIL: uncertain surface with no record did not FAIL (fail-safe broken)"; rc=1
  fi
  # LEG 4 (REAL derive-failure, C1/H1): a change-set that CANNOT be derived (no resolvable base) must fail
  # CLOSED — route to uncertain and require the record. Throwaway repo with NO origin/main and NO 'main'
  # branch, so both merge-base probes fail: a REAL derive-failure, not the --force-uncertain simulation.
  _dr="$_tmp/derive"; mkdir -p "$_dr"
  git -C "$_dr" init -q >/dev/null 2>&1
  git -C "$_dr" config user.email obl@test.local
  git -C "$_dr" config user.name obl-test
  : > "$_dr/file.txt"; git -C "$_dr" add file.txt; git -C "$_dr" commit -qm init >/dev/null 2>&1
  git -C "$_dr" branch -m obl-st-nobase >/dev/null 2>&1   # rename so neither 'main' nor 'master' resolves
  if ( cd "$_dr" && run_threat_obligation --root "$_dr" ) >/dev/null 2>&1; then
    echo "SELFTEST FAIL: underivable change-set (no resolvable base) did not FAIL (derive fail-open)"; rc=1
  fi
  # LEG 5 (L1 regression guard, false-positive): sensitive surface touched, a GENUINELY-FILLED record whose
  # only brackets are markdown links / citations ([STRIDE], [design doc](…), [1]) — NO template stubs, NO
  # banner -> must be treated as FILLED and PASS. The pre-fix arbitrary-`[...]` >=3 count wrongly FAILed such
  # a record as an unfilled placeholder; this leg kills a regression of that exact false-positive.
  # REBUILT FROM THE SHIPPED TEMPLATE (OBLIGATION-RECORD-FLOOR). The old fixture was hand-written and only
  # 3 non-blank lines long, so the engine's new substance floor correctly reds it — an INTENDED regression,
  # not breakage. Rebuilding rather than padding matters: a hand-written fixture cannot COUPLE this check
  # to the artifact it must accept (the gap that let an inert `[describe:` stub ship green through HITL-4's
  # first review round), whereas a template-derived one reds here the day the template outgrows the engine.
  printf 'src/auth/login.js\n' > "$_tmp/changed"
  _tpl="$DIR/templates/THREAT-MODEL-TEMPLATE.md"
  if [ ! -f "$_tpl" ] || [ ! -s "$_tpl" ]; then
    echo "SELFTEST FAIL: templates/THREAT-MODEL-TEMPLATE.md is missing or empty — the filled-record leg cannot run"; rc=1
  else
    # fill_threat(): the shipped template, guidance banner deleted and every bracketed stub substituted.
    # ONE GENERIC bracket pattern, NOT the engine's own stub vocabulary — an oracle that recognises only
    # the tokens it already knows cannot detect a template that adopts a NEW one (a11y LEG 6's lesson).
    fill_threat() {
      grep -v '^> \*\*Template\.\*\*' "$_tpl" \
        | sed 's/\[[^]]*\]/analyzed: spoofing mitigated by MFA, Jane Roe 2026-07-24/g'
    }
    # The link/citation prose is APPENDED AFTER the substitution — that is the whole point of this leg, so
    # those three brackets must survive fill_threat(). Dropping it would silently delete the L1 guard.
    { fill_threat
      printf '\nAssets analyzed per [STRIDE]; rationale in the [design doc](https://x/y).\nSpoofing mitigated by MFA and token validation; see ref [1]. Data classification: confidential (customer PII).\n'
    } > "$_tmp/THREAT-MODEL.md"
    if ! run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      echo "SELFTEST FAIL: filled THREAT-MODEL with markdown links/citations was wrongly FAILed as a placeholder"; rc=1
    fi
  fi
  # LEG 6 (THE `--` SENTINEL — this wrapper's half of it). The engine's first-assignment-wins rule can only
  # defend an argument THIS FILE SETS, and it does not set --stub-pattern. Measured on the true production
  # path before the sentinel: `sh conformance/threat-obligation.sh` FAILed and the same command with
  # `--stub-pattern '\[zzz'` appended PASSed — Signal 2 switched off from the command line. The fix is half
  # here (the `--` that closes run_threat_obligation's own definition) and half in the engine, so the proof
  # must live HERE: an engine-only leg cannot see this file forgetting its sentinel.
  # THREE assertions, because "still FAILs" alone proves nothing if the decoy was inert:
  #  (i)   liveness — the bare wrapper FAILs on this record (the DEFAULT threat vocabulary catches it);
  #  (ii)  potency  — the decoy pattern really would flip it, shown against the engine with NO sentinel;
  #  (iii) the sentinel — the same decoy appended to the WRAPPER is ignored, so the verdict is unchanged.
  # The fixture is derived from $OBL_MIN_SUBSTANCE_LINES (the sourced engine's constant), never hardcoded,
  # so a retune of the floor moves it instead of invalidating it.
  printf 'src/auth/login.js\n' > "$_tmp/changed"
  { echo '# Threat Model'
    echo '| Summary  | [summary] |'
    echo '| Threat   | [threat] |'
    echo '| Boundary | [boundary 1] |'
    _i=5; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_tmp/THREAT-MODEL.md"
  _noop='\[zzz-no-such-stub-token'
  if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: a THREAT-MODEL left as template stubs PASSed the bare wrapper — the sentinel leg below would be vacuous"; rc=1
  fi
  if ! obligation_gate --name t --surface-globs '*auth*' --record THREAT-MODEL.md --template-marker T \
       --stub-pattern "$_noop" --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: the decoy --stub-pattern does not disable Signal 2 for this record — the sentinel leg below would be vacuous"; rc=1
  fi
  _msg="$(run_threat_obligation --stub-pattern "$_noop" --changed "$_tmp/changed" --root "$_tmp" 2>&1 || true)"
  case "$_msg" in
    *"PASS:"*) echo "SELFTEST FAIL: a caller-appended --stub-pattern disabled Signal 2 through this wrapper — its obligation_gate call is missing the '--' sentinel: $_msg"; rc=1 ;;
  esac
  # …and the wrapper's OWN definition still governs everything else on that same run: its record name and
  # its template marker must still be the ones the author is pointed at.
  case "$_msg" in
    *"THREAT-MODEL.md"*"templates/THREAT-MODEL-TEMPLATE.md"*) ;;
    *) echo "SELFTEST FAIL: the wrapper's own record/template-marker did not survive the sentinel — it said: $_msg"; rc=1 ;;
  esac
  # ---------------------------------------------------------------------------------------------
  # LEGS 7-9 (HITL-5) ALL RUN WITH THE RECORD ABSENT. Legs 5 and 6 leave a THREAT-MODEL.md behind in
  # $_tmp, so this line makes what follows independent of whatever the previous leg happened to write.
  # WHAT IT ACTUALLY BUYS, built rather than asserted (an earlier draft of this comment claimed it stops
  # leg 8 going "green for free" and leg 7 being inverted; the mutants falsify that):
  #  - delete this line ALONE and the selftest still prints OK — leg 6 leaves a STUB record, which a
  #    triggering path still FAILs on, so legs 7-9 keep discriminating. The line was UNASSERTED.
  #  - delete it AND break the surface (one glob's casing regressed) and the selftest still KILLS, twice
  #    over — the membership walk and the liveness assertion both fire. It hides no real defect.
  #  - replace it with a genuinely FILLED record — the shape a future edit to leg 6 could produce — and
  #    the selftest goes LOUD RED (all eight leg-7 paths report "did not FAIL"), never silently green.
  # So it prevents a SPURIOUS RED, not a silent green, and it is cheap determinism rather than a control.
  # The assertion below is what makes the line itself asserted: remove the `rm` and this reds immediately,
  # which is the property the prose alone was standing in for.
  rm -f "$_tmp/THREAT-MODEL.md"
  [ ! -f "$_tmp/THREAT-MODEL.md" ] || { echo "SELFTEST FAIL: legs 7-9 must run with the record absent"; rc=1; }
  # LEG 7 (HITL-5, THE RC-LOCK ITEM): a change-set touching REGULATED DATA — the half of this check's own
  # title that shipped unenforced in HITL-1 — must demand a threat model. readiness.sh privacy-ready does NOT cover
  # this: that gate is DECLARATION-triggered, so a project that never wrote a `Data classification:` line
  # stays N/A even while a PR is introducing PII handling. These are the row's own acceptance examples.
  # ONE DEVIATION FROM THE BOARDED EXAMPLE LIST, measured rather than assumed: the row listed
  # `src/billing/card_vault.java`, which matches NO glob in this surface (the regulated token is
  # `cardholder`, and `card_vault` does not contain it) — verified against the full 19-glob string before
  # this leg was written. Shipping it here would have produced a leg that reds on a correct
  # implementation, i.e. pressure to widen a security glob to fit a bad fixture. Replaced with a path
  # that genuinely carries the token.
  for _p in src/models/patient_record.rb src/pii/ssn_handler.py services/gdpr/export.ts \
            src/billing/cardholder_vault.java app/phi/records.go src/PHI_export.ts \
            src/PII_handler.py data/personal-data/export.csv; do
    printf '%s\n' "$_p" > "$_tmp/changed"
    if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: regulated-data path %s with no THREAT-MODEL did not FAIL — HITL-5 is unenforced\n' "$_p"; rc=1
    fi
  done
  # LEG 8 (THE MEASURED FALSE-POSITIVE GUARD): the decoys that decided the SHAPE of the regulated globs.
  # A bare `*phi*` matched 982 paths in a 162k-file corpus (graphics.py, sphinxext.py, morphism.ts) and a
  # bare `*ssn*` matched 21 (getElementsByClassName.js — cla-ssn-ame), which is why `phi` and `ssn` are
  # SEGMENT-ANCHORED while `pii`/`gdpr`/`patient`/`cardholder` are bare substrings. These four fixtures
  # are what stops a future "simplify the globs" edit from re-introducing that: each reds here the moment
  # an anchor is dropped. Runs with the record still absent, so the only way to return 0 is a genuine N/A.
  for _p in lib/graphics.py doc/sphinxext.py src/morphism.ts src/getElementsByClassName.js; do
    printf '%s\n' "$_p" > "$_tmp/changed"
    if ! run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: %s is not regulated data but triggered the threat obligation — an anchor was dropped from a phi/ssn glob\n' "$_p"; rc=1
    fi
  done
  # LEG 9 (PER-GLOB COVERAGE + MONOTONICITY). Without this, only the globs legs 1/7 happen to exercise are
  # proven and the rest can be DELETED with the selftest still printing OK — the defect a11y-obligation.sh
  # LEG 5 was built for, measured there as 15 of 16 globs unproven. Threat's globs cannot use a11y's
  # DERIVED probes: half of them are bare substrings (*auth*) and half carry bracket expressions
  # (*[Pp][Ii][Ii]*), and a probe derived from a bracket expression would have to contain the literal
  # brackets, which the glob does not match. So the probes are DECLARED, and the declaration is locked
  # from BOTH sides so it cannot fall behind the surface:
  #   (a) every glob in $THREAT_SURFACE_GLOBS must appear in the table  -> a new glob cannot ship unprobed;
  #   (b) every glob in the table must appear in the surface            -> a deleted glob reds here;
  #   (c) the surface must parse to exactly $THREAT_SURFACE_GLOB_COUNT  -> an EXTERNALLY DECLARED number
  #       the code cannot satisfy by construction (a11y's LEG 5 lesson: a floor let 26 globs be deleted).
  # Each pair is asserted TWICE, and (ii) is what stops (i) being borrowed from a neighbouring glob:
  #   (i)  through the wrapper, whole surface in force      -> RED
  #   (ii) straight to the engine with ONLY that one glob   -> RED  (the probe really is on THAT glob)
  # (ii) is also the MONOTONICITY proof for the six legacy globs: each is still individually live.
  THREAT_SURFACE_GLOB_COUNT=19   # alternations in $THREAT_SURFACE_GLOBS (declared, not computed)
  # One probe per glob. WHY A TABLE AND NOT THE BOARD'S EXAMPLE LIST — measured, path by path, against
  # each glob individually: those eight example paths reach only SEVEN distinct globs of the nineteen.
  # Six of the thirteen regulated globs get nothing — five were never given an example at all
  # (`*_[Pp][Hh][Ii]*`, `*-[Pp][Hh][Ii]*`, `*/[Ss][Ss][Nn]/*`, `*_[Ss][Ss][Nn]*`, `*-[Ss][Ss][Nn]*`) and
  # the sixth, `*[Cc][Aa][Rr][Dd][Hh][Oo][Ll][Dd][Ee][Rr]*`, was given one that matches nothing — and of
  # the six LEGACY globs only `*auth*` is touched anywhere else in this selftest. Eleven of nineteen
  # would have shipped unproven and silently deletable. That is the gap this table closes.
  # THREE PROBES ARE DELIBERATELY ALL-CAPS (`data/PATIENT_EXPORT.csv`, `db/CARDHOLDER_DATA.sql`,
  # `export/Personal-Data/dump.csv`). Those three globs shipped cased on their first letter only, or not
  # at all, and each of these paths measured N/A against that surface — so the probes assert the CASING,
  # not merely the token: revert any of the three to `*[Pp]atient*`/`*[Cc]ardholder*`/`*/personal-data/*`
  # and its row reds here. The lowercase forms of the same three tokens stay covered by LEG 7
  # (`patient_record.rb`, `cardholder_vault.java`, `personal-data/export.csv`), so neither direction is
  # traded for the other.
  # WHAT A DECLARED TABLE CANNOT DO — the analogue of the "a mistyped glob self-validates" residual that
  # uat-obligation.sh states for DERIVED probes, and stated here for the same reason: a lock that reads as
  # proving the surface correct while proving only that it is self-consistent is the defect this file's own
  # SCOPE paragraph forbids. A glob and the probe row declared against it can be reverted TOGETHER, as a
  # PAIR, and the whole selftest stays green. MEASURED on this build: narrowing
  # `*[Pp][Aa][Tt][Ii][Ee][Nn][Tt]*` back to `*[Pp]atient*` AND its probe back to `data/patient_export.csv`
  # returns rc=0 — while on the TRUE PRODUCTION path `data/PATIENT_EXPORT.csv` reads "N/A: no threat-model
  # surface touched", i.e. the ALL-CAPS regression this table exists to hold is silently reintroduced.
  # Mutating either HALF alone reds loudly (measured: the glob alone fires both the membership walk and the
  # liveness assertion), and DELETING a glob with its row reds on the count lock — so it is specifically a
  # coordinated SUBSTITUTION that survives. This is unclosable by any fixture scheme (the fixtures are
  # authored in the same commit as the surface), it is NOT a defect to be built around, and REVIEW is the
  # backstop: a diff that edits a glob and its probe row in one commit is exactly what a reviewer reads.
  # Each probe is written to match its OWN glob and no other; verified pairwise (each of the 19 probes
  # against all 19 globs) when the cased probes were introduced. That uniqueness is a readability
  # property, NOT a proven one: assertion (ii) runs the probe against its glob ALONE, which proves the
  # probe is ON that glob, and would still pass for a probe that also matches a neighbour.
  # SPACE-separated, read with the DEFAULT IFS (not a literal tab): `read -r _g _p` assigns the whole
  # remainder of the line to the last variable, so a probe path is never truncated, and the table cannot
  # be silently broken by any tool that normalises whitespace. No glob or probe here contains a space.
  THREAT_GLOB_PROBES='*secret* src/config/secrets.ts
*auth* src/auth/login.js
*password* src/user/password_reset.py
*payment* src/payments/charge.go
*migrations/* db/migrations/001_init.sql
*.env config/staging.env
*[Pp][Ii][Ii]* src/PII_handler.py
*[Gg][Dd][Pp][Rr]* services/gdpr/export.ts
*[Pp][Aa][Tt][Ii][Ee][Nn][Tt]* data/PATIENT_EXPORT.csv
*[Cc][Aa][Rr][Dd][Hh][Oo][Ll][Dd][Ee][Rr]* db/CARDHOLDER_DATA.sql
*/[Pp][Hh][Ii]/* app/phi/records.go
*[Pp][Hh][Ii]_* src/PHI_export.ts
*_[Pp][Hh][Ii]* src/exporters/redact_phi.go
*-[Pp][Hh][Ii]* etl/anonymize-phi.py
*/[Ss][Ss][Nn]/* app/ssn/lookup.rb
*[Ss][Ss][Nn]_* src/util/ssn_mask.py
*_[Ss][Ss][Nn]* src/util/mask_ssn.go
*-[Ss][Ss][Nn]* jobs/redact-ssn.rb
*/[Pp]ersonal-[Dd]ata/* export/Personal-Data/dump.csv'
  printf '%s\n' "$THREAT_GLOB_PROBES" > "$_tmp/probes"
  # (a) + the two assertions, walking the TABLE.
  _pr_count=0
  while read -r _g _p; do
    [ -n "$_g" ] || continue
    _pr_count=$((_pr_count + 1))
    # (b) the glob this probe is named against must actually be IN the shipped surface.
    case "$OBL_GLOB_SEP$THREAT_SURFACE_GLOBS$OBL_GLOB_SEP" in
      *"$OBL_GLOB_SEP$_g$OBL_GLOB_SEP"*) ;;
      *) printf 'SELFTEST FAIL: probe table names glob %s, which is NOT in THREAT_SURFACE_GLOBS — the glob was deleted or renamed and its file class is now silently ungated\n' "$_g"; rc=1 ;;
    esac
    printf '%s\n' "$_p" > "$_tmp/changed"
    if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: surface glob dead — %s (probe %s) touched with no THREAT-MODEL did not FAIL\n' "$_g" "$_p"; rc=1
    fi
    if obligation_gate --name t --surface-globs "$_g" --record THREAT-MODEL.md --template-marker T \
         --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: probe %s is not on glob %s at all — its RED above was borrowed from another glob, so that glob is unproven\n' "$_p" "$_g"; rc=1
    fi
  done < "$_tmp/probes"
  # (a) family-completeness in the other direction, plus (c) the exact count lock. Both are needed: the
  # count alone cannot tell a swap from a match, and the membership walk alone cannot see an ADDED glob.
  _obl_glob_scan '' "$THREAT_SURFACE_GLOBS" || true
  _sg_count="${OBL_GLOBS_SEEN:-0}"
  [ "$_pr_count" = "$_sg_count" ] || {
    printf 'SELFTEST FAIL: %s probes for %s surface globs — the table and THREAT_SURFACE_GLOBS have come apart (a glob added with no probe would ship UNPROVEN; a probe with no glob means the glob was deleted). The membership message above names which\n' \
      "$_pr_count" "$_sg_count"; rc=1; }
  [ "$_sg_count" = "$THREAT_SURFACE_GLOB_COUNT" ] || {
    printf 'SELFTEST FAIL: %s surface globs parsed, expected exactly %s — a glob was added or removed without updating THREAT_SURFACE_GLOB_COUNT\n' \
      "$_sg_count" "$THREAT_SURFACE_GLOB_COUNT"; rc=1; }
  # THE LOAD-BEARING NEGATIVE for HITL-5. Everything above proves the regulated paths RED; none of it
  # proves the REGULATED GLOBS are what makes them red — legs 7's fixtures would look identical if some
  # pre-existing glob happened to catch them. Run one regulated path against $THREAT_LEGACY_GLOBS (the
  # byte-identical HITL-1 surface) and require it to come back N/A: that is the gap HITL-5 closes, shown
  # rather than asserted, and it reds if the regulated globs are ever folded into the legacy constant.
  printf 'src/PII_handler.py\n' > "$_tmp/changed"
  if ! obligation_gate --name t --surface-globs "$THREAT_LEGACY_GLOBS" --record THREAT-MODEL.md \
       --template-marker T --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: a regulated path already RED-ed on the pre-HITL-5 surface — leg 7 proves nothing about the regulated globs"; rc=1
  fi
  unset KIT_OBL_TEST   # defence in depth: if this file is ever SOURCED rather than run, the fixture-flag
                       # escape hatch must not survive into the caller's environment.
  [ "$rc" = 0 ] && printf 'OK (threat-obligation: 9 legs; all %s surface globs probed both through the wrapper and alone, the regulated-data half proved absent from the pre-HITL-5 surface, and the four measured phi/ssn decoys held N/A)\n' \
    "$THREAT_SURFACE_GLOB_COUNT"
  return $rc
}

# dispatch — BELOW the selftest() definition so the function is defined before it is called
# (POSIX sh executes top-to-bottom; a forward reference to selftest fails with 'command not found').
# The non-vacuity marker is the selftest() line above, so the check-logic region (run_threat_obligation)
# is still mutated; this dispatch sits after the marker and is emitted verbatim by the sweep.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
run_threat_obligation "$@"; exit $?
