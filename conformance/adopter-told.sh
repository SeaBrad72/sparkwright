#!/bin/sh
# adopter-told.sh — C7 ADOPTER-TOLD-LOOP-GATES-ARE-ENFORCED. The shipped prose must not tell an
# adopter that a gate is ENFORCED when nothing in what they receive enforces it.
#
# THE DEFECT IT CLOSES (design 2026-08-14-c7-adopter-told-design.md §2.4/§2.5). Three shipped sites
# asserted "Gate-checked on the PR head commit by `conformance/loop-state.sh`" with no delivery
# qualifier, while the gate an ADOPTER receives is an observe-mode check-run that posts `neutral`
# until they flip `LOOP_STATE_MODE` (ratified: D-240811-2). Twelve further lines named a checker that
# reaches no adopter-runnable pipeline at all. A prose-only fix would be the gate-not-note
# anti-pattern this kit exists to kill, so the fix ships WITH the check that holds it.
#
# REMEDY-AGNOSTIC BY CONSTRUCTION. It asserts a CONSISTENCY between two artifacts the kit already
# ships — the prose and the wiring — and never prescribes which one moves. Wire the gate later and
# the claim goes green; qualify the claim instead and it goes green; flip a dial's default and the
# classification flips at its source. Nothing here has to be edited for any of those.
#
# ── WHAT IT DOES ────────────────────────────────────────────────────────────────────────────────
#   1. Builds a REAL adopter export (scripts/adopter-export.sh, ~0.4 s) into a temp dir. Modelling
#      the export instead of building it was rejected: four post-archive transforms mutate exported
#      content, so a model is a second thing to keep true.
#   2. Classifies every `conformance/*.sh` into three reach sets, computed from the EXPORT:
#        HARD-REACHABLE  invoked on a non-comment line of a shipped pipeline (profiles/*/ci.yml,
#                        profiles/*/ci.gitlab-ci.yml, profiles/ratification.yml) OR carrying a LIVE
#                        row in the export's conformance/verify.sh (a `check` row that is neither
#                        `--kitself` nor `--selftest`-only).
#        DIAL-REACHABLE  reached ONLY by a run-line in profiles/adopter-gates.yml — the
#                        Inception-installed workflow — AND only while that workflow's emitted
#                        LOOP_STATE_MODE reads `observe`. Since 2026-08-30 it ships `enforce`
#                        (LOOP-STATE-ADOPTER-ENFORCE), so those run-lines are HARD-reachable and
#                        the dial set is normally EMPTY. The axis is not dead: it is read from the
#                        emitted default (at_emitted_mode), so an adopter who opts back out to
#                        `observe` re-arms the qualifier demand automatically, and an absent or
#                        unparseable default fail-safes to `observe` (the demanding answer).
#        UNREACHABLE     neither.
#   3. Greps the export's `.md` corpus for CLAIM LINES — a claim verb (`gate-checked`, `locked by`,
#      `enforced by`, `verified by`, `gated by`, case-insensitive) on a line that also names a
#      `conformance/*.sh` — and judges each named script:
#        UNREACHABLE     -> RED, unless the line carries the kit-tree token (below).
#        DIAL-REACHABLE  -> RED unless the line also carries a DELIVERY qualifier (`observe` or
#                        `LOOP_STATE_MODE`, same line). An enforcement claim over a gate whose only
#                        adopter reach is observe-dialed must disclose the dial. Under the shipped
#                        `enforce` default nothing is dial-reachable, so the claim is simply true
#                        and the qualifier is not demanded — disclosing a dial that is not deciding
#                        anything would be its own kind of false statement.
#        HARD-REACHABLE  -> green.
#      THE KIT-TREE TOKEN DOES NOT EXEMPT. The literal phrase `the kit's own CI` switches that
#      line's judged set to the KIT-REACHABLE set (the kit's .github/workflows/*.yml run-lines + the
#      kit's own verify.sh live registry). A claim that lies about KIT wiring still reds.
#
# ── PINNED PARSE, AND WHAT IT CANNOT SEE (read before trusting a green) ──────────────────────────
#   · LINE GRANULARITY. One unreachable-and-unqualified ref reds the line; one qualifier greens every
#     ref on it. Coarse in both directions, deliberately: a per-clause parser over prose is a
#     sentence-splitter nobody can review. A reviewer must therefore treat an ADDED qualifier token
#     in a diff as a claim to check, not a formatting change.
#   · TRANSITIVE INVOCATION IS OUT OF MODEL. A script executed only from inside another gate is not
#     "reachable" here. The direction is safe (fewer reachable => more reds), never green-while-dark.
#   · INVOCATION, NOT MENTION. A reach only counts from `sh <path>` / `bash <path>` on a non-comment
#     line. A path named in an `env:`/`with:`/comment contributes nothing — again the safe direction.
#   · THE VERB LEXICON IS NO LONGER A BARE ENUMERATION (ADOPTER-TOLD-LEXICON-RESIDUAL, 2026-08-31).
#     It was: a claim phrased outside CLAIM_VERBS escaped silently, at a miss rate measured ~11.8% on
#     the export corpus (not the ~5% once recorded here) — 14 out-of-lexicon claim-shaped lines over
#     16 distinct verbs. TWO LISTS now close that class BY CONSTRUCTION for the passive `-ed by` shape:
#     a ref-bearing line whose verb is in NEITHER CLAIM_VERBS nor NONCLAIM_VERBS REDS naming the verb.
#     ⚠️ FALSE POSITIVES ARE NO LONGER IMPOSSIBLE. That sentence used to be true of this whole check
#     and it is now true only of the reachability arms: the lexicon arm BLOCKS on an unclassified verb,
#     so a new English verb over a check reference reds until someone classifies it. That is the trade
#     the row bought — a loud unknown instead of a silent miss — and it is one word of remedy.
#   · HONEST CEILING, RESTATED. The shape set is ONE SHAPE DEEP. "the gate KEEPS this honest" carries
#     no `-ed by` and still escapes. The verb table is now checked both ways; the SHAPE is not.
#   · REFS ARE EXTRACTED IN TWO SHAPES: `conformance/<name>.sh`, and a backticked BARE BASENAME that
#     RESOLVES against the export's own conformance/ directory. The bare form was the second unnamed
#     hole — ``proven by `egress-policy.sh` `` named a real check and was invisible to a
#     `conformance/`-anchored extractor regardless of verb. Requiring resolution is what stops an
#     arbitrary `foo.sh` in prose from being conjured into a claim.
#   · THE LEXICON ARM ONLY IS SCOPED TO LIVING DOCS. CHANGELOG.md, meta-control-log.md and dated
#     records (the citation-history.sh / citation-live.sh `is_dated` precedent, over-reach included)
#     are exempt from the REWORD demand. The three reachability arms stay ARMED there: reporting that
#     a named gate is not wired is a fact about today's tree, not a demand to rewrite history.
#     MEASURED AT BUILD, 2026-08-31: 64 claim line(s) over 208 exported .md file(s) (the 60/211 once
#     recorded here was stale) — 74 before disposition, 0 out-of-lexicon and 0 unreachable after it.
#     NONCLAIM_VERBS holds 27 entries, every one OBSERVED in that corpus (see its own note).
#   · THE DELIVERY QUALIFIER IS PRESENCE-CHECKED, NOT TRUTH-CHECKED. `observe` on the line satisfies
#     it; whether the surrounding sentence uses it honestly is review-seat territory.
#   · IT JUDGES EXPORT TIME, NOT AN ADOPTER'S LIVE TREE. The dial is theirs (D-240811-2), and what
#     they actually enforce after Inception is unobservable from here.
#   · IT JUDGES COMMITTED HEAD. `adopter-export.sh` archives HEAD, so an uncommitted working-tree
#     edit is invisible. In CI, `actions/checkout` on a `pull_request` event checks out the MERGE
#     REF by default, so what is graded is the merge RESULT of the PR into its base — not the PR head
#     commit. That is the right tree to grade (it is what lands), but it is not the SHA the PR page
#     shows, and a base-branch prose change can therefore move this check's verdict.
#
# ── ARMING (fail-closed; the C3/C5 pattern) ──────────────────────────────────────────────────────
# An adopter tree has no committed kit HEAD to export, so the check self-N/As there — keyed on the
# un-spoofable kit-marker pair (docs/ROADMAP-KIT.md, .github/workflows/golden-path.yml; both
# export-ignored). N/A ONLY when NEITHER is present: ONE marker holds the tree to the lock. On an
# ARMED tree an export or parse failure is a FAIL, never an N/A — a presence check that can silently
# disarm is the exact concealment class this slice exists to resolve, one layer down.
#
# Usage: sh conformance/adopter-told.sh [--selftest]
#        sh conformance/adopter-told.sh --from-export <dir> [--kit-root <dir>]   (fixture seam)
# The --from-export seam skips the export build and judges a prepared tree; it exists so the selftest
# legs are hermetic and cheap. CI and verify.sh invoke the no-argument form, which always builds a
# real export. Exit: 0 = every claim consistent (or N/A off the kit tree) · 1 = an inconsistent claim,
# a failed export, or a floor violation · 2 = bad usage. POSIX sh; dash-clean.
set -eu

CLAIM_VERBS='gate-checked|locked by|enforced by|verified by|gated by|validated by|linted by|attested by|proven by|denied by|checked by'
# ── THE TWO-LIST DETECTOR (ADOPTER-TOLD-LEXICON-RESIDUAL) ───────────────────────────────────────
# CLAIM_VERBS alone was an ENUMERATION on the honesty side: a claim phrased outside it escaped, and
# nothing said so. The cure is not a longer enumeration — it is making the OUT-OF-LEXICON case LOUD.
# A line naming a conformance check AND carrying a passive verb of the shape below must have that verb
# in EXACTLY ONE of the two lists. In neither -> RED naming the verb; the author adds it to CLAIM_VERBS
# (and then answers for the reachability of what the line names), or to NONCLAIM_VERBS (declaring on
# the record that it makes no enforcement claim), or rewords. Closed BY CONSTRUCTION for this shape.
PASSIVE_SHAPE='[A-Za-z]+ed by|proven by'
# ⚠️ EVERY ENTRY BELOW WAS OBSERVED ON A REAL REF-BEARING LINE IN THE EXPORT CORPUS. Four candidates
# from the design's illustrative list (`caught by`, `measured by`, `replaced by`, `written by`) were
# REMOVED at review: none occurs over a check reference in the corpus, so each pre-silenced a verb the
# detector has never met. `caught by` is the sharp one — CLAIM-shaped, so allowlisting it in advance
# would have exempted the exact sentence this row exists to catch. Entries are earned by measurement.
NONCLAIM_VERBS='unaffected by|generated by|subsumed by|unnamed by|uncovered by|bounded by|pinned by|masked by|led by|fed by|reached by|sourced by|invoked by|referenced by|carried by|named by|printed by|followed by|replayed by|signed by|touched by|worsened by|closed by|covered by|judged by|fenced by|satisfied by'
KIT_TOKEN="the kit's own CI"
# WORD-ANCHORED (security LOW-2): a bare `observe` alternative also matched "observed"/"observer",
# so a sentence merely *reporting* an observation satisfied the dial disclosure. The text is padded
# with a space on each side before matching, so the non-word guards also cover line start/end.
DELIVERY_TOKENS='LOOP_STATE_MODE|[^A-Za-z]observe[^A-Za-z]'
# LIVE FLOORS (fail-closed AND legible). Measured on the export at the C7 build: 211 `.md` files and
# 137 `check` rows. Set well under those so ordinary growth/pruning never trips them, and far enough
# above zero that a gutted corpus or an unparseable registry FAILs by name instead of passing over
# nothing. ⚠️ The design pinned a registry floor of ">=150 (205 today)"; the 205 figure was FALSIFIED
# at build — the export's verify.sh carries 137 `check` rows — so the floor is 100.
# FIXTURE MODE drops both to 3, not to 1, and the 3 is load-bearing: at 1 the only fixture that could
# breach a floor was an EMPTY one, which also emptied the claim domain — so both floor legs passed
# through the downstream empty-domain branch and neither floor comparison was ever the cause (a
# tautological label, caught by both review seats). At 3 each floor leg breaches ONE floor while the
# other inputs stay live, so the leg can only pass via its own branch.
MD_FLOOR=150
ROW_FLOOR=100

FROM_EXPORT=""
KIT_ROOT="."
FIXTURE=no
# ⚠️ SELFTEST/FIXTURE ARE DELIBERATELY NOT `=1` FLAGS. non-vacuity.sh's composite mutant neuters every
# `<var>=1` before the selftest marker to `<var>=0`; with `SELFTEST=1` here, the mutant rerouted
# `--selftest` into the LIVE run, which is green on the kit tree — so the mutant SURVIVED and this
# check shipped a green nobody had proven could go red (reproduced by the reviewer with the kit's own
# oracle). A non-numeric sentinel is outside both mutation idioms, so the dispatch survives the mutant
# and the oracle reaches the legs it is supposed to grade. Do not "tidy" these back to 1/0.
SELFTEST=no
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest)    SELFTEST=yes; shift ;;
    --from-export) [ -n "${2:-}" ] || { echo "adopter-told: --from-export requires a directory" >&2; exit 2; }
                   FROM_EXPORT=$2; FIXTURE=yes; shift 2 ;;
    --kit-root)    [ -n "${2:-}" ] || { echo "adopter-told: --kit-root requires a directory" >&2; exit 2; }
                   KIT_ROOT=$2; shift 2 ;;
    *) echo "usage: adopter-told.sh [--selftest] [--from-export <dir> [--kit-root <dir>]]" >&2; exit 2 ;;
  esac
done
[ "$FIXTURE" = yes ] && { MD_FLOOR=3; ROW_FLOOR=3; }

# at_invoked <file> — the conformance scripts INVOKED on non-comment lines of a pipeline file.
at_invoked() {
  [ -f "$1" ] || return 0
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null \
    | grep -oE '(sh|bash)[[:space:]]+conformance/[A-Za-z0-9_.-]+\.sh' \
    | grep -oE 'conformance/[A-Za-z0-9_.-]+\.sh' || true
}

# at_live_rows <verify.sh> — scripts with a LIVE `check` row (neither --kitself nor --selftest-only).
at_live_rows() {
  [ -f "$1" ] || return 0
  grep '^check ' "$1" 2>/dev/null \
    | grep -v -e '--kitself' -e '--selftest' \
    | grep -oE 'conformance/[A-Za-z0-9_.-]+\.sh' || true
}

# at_emitted_mode <adopter-gates.yml> — the LOOP_STATE_MODE the adopter's workflow SHIPS.
#
# Prints exactly `enforce` or `observe` and always returns 0. FAIL-SAFE DIRECTION IS `observe`:
# a missing file, a missing env block, or a value this reader does not recognise all answer
# `observe`, which is the DEMANDING answer for the claim corpus — an unreadable dial must never be
# read as "the gate is enforcing, so the prose need not disclose anything". COMMENT-STRIPPED for
# the same reason adopter-gates-parity strips: this workflow's header discusses both words at
# length, and a raw grep would be satisfied by prose.
at_emitted_mode() {  # <adopter-gates.yml>
  [ -f "$1" ] || { printf 'observe\n'; return 0; }
  _em=$(grep -v '^[[:space:]]*#' "$1" 2>/dev/null \
        | grep -oE 'LOOP_STATE_MODE:[[:space:]]*[A-Za-z]+' | head -1)
  case "$_em" in
    *enforce) printf 'enforce\n' ;;
    *)        printf 'observe\n' ;;
  esac
}

# at_reach_sets <export-dir> <kit-dir> <workdir> — writes hard/dial/kit reach sets. rc 1 on a floor
# violation, which is a FAIL and never a quiet pass: an empty reach set would green every claim.
at_reach_sets() {
  _ex=$1; _kt=$2; _w=$3
  : > "$_w/hard"; : > "$_w/dial"; : > "$_w/kit"
  for _f in "$_ex"/profiles/*/ci.yml "$_ex"/profiles/*/ci.gitlab-ci.yml "$_ex"/profiles/ratification.yml; do
    at_invoked "$_f" >> "$_w/hard"
  done
  at_live_rows "$_ex/conformance/verify.sh" >> "$_w/hard"
  # THE DIALED WORKFLOW'S RUN-LINES LAND IN HARD OR IN DIAL DEPENDING ON WHAT IT SHIPS. Since
  # 2026-08-30 the emitted default is `enforce` (LOOP-STATE-ADOPTER-ENFORCE), so those run-lines
  # are HARD reach and an enforcement claim over them is simply true — demanding a dial qualifier
  # would force the corpus to disclose a dial that is not deciding anything. Under `observe` the
  # old demand is exactly right. Reading the default rather than hardcoding either answer is what
  # makes a future flip in EITHER direction move this check automatically.
  # `$_w/agates` is kept separately because the axis-alive anchor below must see the run-line
  # wherever it was routed — otherwise flipping to enforce would silently kill that anchor.
  at_invoked "$_ex/profiles/adopter-gates.yml" > "$_w/agates"
  AT_EMITTED_MODE=$(at_emitted_mode "$_ex/profiles/adopter-gates.yml")
  if [ "$AT_EMITTED_MODE" = enforce ]; then
    cat "$_w/agates" >> "$_w/hard"
  else
    cat "$_w/agates" >> "$_w/dial"
  fi
  for _f in "$_kt"/.github/workflows/*.yml; do
    at_invoked "$_f" >> "$_w/kit"
  done
  at_live_rows "$_kt/conformance/verify.sh" >> "$_w/kit"
  sort -u "$_w/hard" -o "$_w/hard"; sort -u "$_w/dial" -o "$_w/dial"; sort -u "$_w/kit" -o "$_w/kit"
  # a script reached BOTH hard and dial is hard — the dial set is "only reach is the dialed workflow"
  comm -23 "$_w/dial" "$_w/hard" > "$_w/dial.only" && mv "$_w/dial.only" "$_w/dial"

  # ⚠️ NOT `$(grep -c … || echo 0)`. `grep -c` PRINTS 0 and exits 1 on zero matches, so the `|| echo 0`
  # captured "0\n0"; `[ "0\n0" -lt N ]` is a usage error, the `if` swallowed it, and the floor branch
  # was SKIPPED on exactly the input it exists for. Both review seats found this independently. grep
  # already emits the count, so the guard only has to cover a missing/unreadable file (empty output).
  _rows=$(grep -c '^check ' "$_ex/conformance/verify.sh" 2>/dev/null) || :
  _rows=${_rows:-0}
  if [ "$_rows" -lt "$ROW_FLOOR" ]; then
    echo "FAIL: the export's conformance/verify.sh carries $_rows 'check' row(s), under the floor of $ROW_FLOOR — the reachable set is derived from that registry, so an unparseable or gutted one would green every claim in the corpus. Refusing to judge over it."
    return 1
  fi
  # AXIS-ALIVE ANCHOR. Re-based 2026-08-30: it used to assert that loop-state was in the DIAL set,
  # which stopped being true the moment the emitted default flipped to enforce (the run-line is
  # now HARD reach). What it actually needs to prove is that the run-line is still FOUND — if the
  # workflow moved, was renamed, or no longer parses, both the dial axis and the enforce routing
  # above go silently dead and every claim over this gate greens for the wrong reason. So the
  # anchor now reads the pre-routing set.
  if ! grep -qxF 'conformance/loop-state.sh' "$_w/agates"; then
    echo "FAIL: the reach computation found no conformance/loop-state.sh run-line in profiles/adopter-gates.yml — that anchor is what keeps the emitted-default axis alive. Its absence means the workflow moved, was renamed, or no longer parses, and every claim over that gate would be judged against an empty set."
    return 1
  fi
  return 0
}

# at_judge <export-dir> <workdir> — grade the .md corpus. rc 1 on any RED or a corpus floor breach.
at_judge() {
  _ex=$1; _w=$2; _rc=0; _red=0; _unreach=0; _mode=0; _kittok=0; _lex=0; _lines=0
  ( cd "$_ex" && find . -type f -name '*.md' ) > "$_w/md" 2>/dev/null || :
  _n=$(grep -c . "$_w/md" 2>/dev/null) || :        # same dead-zero trap as the registry count above
  _n=${_n:-0}
  if [ "$_n" -lt "$MD_FLOOR" ]; then
    echo "FAIL: the export carries $_n Markdown file(s), under the floor of $MD_FLOOR — a corpus that small means the export failed, was pruned, or was pointed at the wrong tree, and a green over it would prove nothing."
    return 1
  fi
  while IFS= read -r _m; do
    [ -n "$_m" ] || continue
    _rel=${_m#./}
    # DATED-RECORD FLAG — it gates the NEW lexicon arm ONLY, and that scope is the whole point. A
    # dated record is supposed to say what was true on its date, so demanding a REWORD falsifies it;
    # but the three PRE-EXISTING arms are not reword demands — they report that a named check is not
    # wired, a fact about TODAY'S tree, as worth knowing in a dated document as in a living one. An
    # earlier draft `continue`d the whole file and so DISARMED those three over every dated record.
    # Predicate follows the citation-history.sh / citation-live.sh `is_dated` precedent, ⚠️ INCLUDING
    # ITS OVER-REACH (a basename like `2026-plan.md` is dated wherever it lives) — disclosed, not
    # cured; matching the precedent beats a private improvement. On today's export the flag is set
    # for NOTHING (both kinds are already export-ignored): it is a rule about document KIND.
    _dated=0
    case "$_rel" in
      CHANGELOG.md|*/CHANGELOG.md|meta-control-log.md|*/meta-control-log.md) _dated=1 ;;
      docs/architecture/20*|docs/plans/20*|docs/plans/brief-*) _dated=1 ;;
      *) case "${_rel##*/}" in 20[0-9][0-9]-*.md|brief-*.md) _dated=1 ;; esac ;;
    esac
    grep -inE "$CLAIM_VERBS|$PASSIVE_SHAPE" "$_ex/$_m" 2>/dev/null > "$_w/hits" || continue
    while IFS= read -r _hit; do
      _lno=${_hit%%:*}; _text=${_hit#*:}
      # REF EXTRACTION, TWO SHAPES. The `conformance/…` anchor was the second unnamed hole: a
      # backticked BARE BASENAME (``proven by `egress-policy.sh` ``) named the same check and was
      # invisible. A basename counts only when it RESOLVES against the export's own conformance/
      # directory, so an arbitrary `foo.sh` in prose is not conjured into a claim.
      { printf '%s\n' "$_text" | grep -oE 'conformance/[A-Za-z0-9_.-]+\.sh'
        printf '%s\n' "$_text" | grep -oE '`[A-Za-z0-9_.-]+\.sh`' | tr -d '`' \
          | while IFS= read -r _bn; do
              [ -f "$_ex/conformance/$_bn" ] && printf 'conformance/%s\n' "$_bn"
            done
      } 2>/dev/null | sort -u > "$_w/refs" || :
      [ -s "$_w/refs" ] || continue
      # THE OUT-OF-LEXICON ARM, and it is checked BOTH WAYS. Every passive verb on a ref-bearing line
      # must be in exactly one list. Unknown -> RED naming the verb; the remedy is a one-word edit to
      # whichever list is honest, and that edit is then a reviewable claim rather than a silent miss.
      _unk=""
      for _v in $(printf '%s\n' "$_text" | grep -oE "$PASSIVE_SHAPE" | tr ' ' '~' | sort -u); do
        _vv=$(printf '%s' "$_v" | tr '~' ' ')
        printf '%s\n' "$_vv" | grep -qxiE "$CLAIM_VERBS" && continue
        printf '%s\n' "$_vv" | grep -qxiE "$NONCLAIM_VERBS" && continue
        _unk="${_unk:+$_unk, }\"$_vv\""
      done
      # ONLY THIS ARM IS SCOPED TO LIVING DOCS — it is the one that demands a REWORD. The reachability
      # arms below stay armed everywhere, dated records included.
      [ "$_dated" = 1 ] && _unk=""
      if [ -n "$_unk" ]; then
        echo "FAIL[lexicon]: $_rel:$_lno names a conformance check with the passive verb(s) $_unk, which are in NEITHER lexicon. The verb lexicon is how this check tells an enforcement CLAIM from a description, so an unclassified verb is an unjudged line. Add the verb to CLAIM_VERBS (and then answer for what the line names being reachable), or to NONCLAIM_VERBS if it makes no enforcement claim, or reword."
        _lex=$((_lex + 1)); _red=$((_red + 1)); _rc=1; continue
      fi
      # Below this point the line's verbs are all classified. Only a CLAIM verb earns a reachability
      # judgement; a purely NONCLAIM line has now been positively dispositioned and is done.
      printf '%s\n' "$_text" | grep -qiE "$CLAIM_VERBS" || continue
      _lines=$((_lines + 1))
      _kt=0; printf '%s\n' "$_text" | grep -qF "$KIT_TOKEN" && _kt=1
      _dv=0; printf '%s\n' "$_text" | grep -qiE "$DELIVERY_TOKENS" && _dv=1
      while IFS= read -r _ref; do
        if [ "$_kt" = 1 ]; then
          grep -qxF "$_ref" "$_w/kit" && continue
          echo "FAIL[kit-token]: $_rel:$_lno claims $_ref while carrying the \"$KIT_TOKEN\" qualifier, but NOTHING in the kit's own workflows or verify.sh live registry runs it. The token narrows the claim to the kit tree; it does not excuse one."
          _kittok=$((_kittok + 1)); _red=$((_red + 1)); _rc=1; continue
        fi
        grep -qxF "$_ref" "$_w/hard" && continue
        if grep -qxF "$_ref" "$_w/dial"; then
          [ "$_dv" = 1 ] && continue
          echo "FAIL[mode]: $_rel:$_lno makes an enforcement claim over $_ref, whose ONLY adopter reach is the observe-dialed profiles/adopter-gates.yml — and the line discloses no delivery qualifier. Say so on this line (name \`observe\` or \`LOOP_STATE_MODE\`), or wire the gate hard."
          _mode=$((_mode + 1)); _red=$((_red + 1)); _rc=1; continue
        fi
        echo "FAIL[unreachable]: $_rel:$_lno claims $_ref, which NO shipped pipeline invokes and which has no live row in the export's verify.sh — an adopter reading this line is told a gate holds that nothing in their tree runs. Wire it, qualify the line (\"$KIT_TOKEN\"), or reword the claim into an instruction."
        _unreach=$((_unreach + 1)); _red=$((_red + 1)); _rc=1
      done < "$_w/refs"
    done < "$_w/hits"
  done < "$_w/md"
  if [ "$_lines" -eq 0 ]; then
    echo "FAIL: ZERO claim lines matched across $_n Markdown file(s) — the corpus grep or the verb lexicon is dead, and a green over an empty domain asserts nothing."
    return 1
  fi
  if [ "$_rc" = 0 ]; then
    echo "adopter-told: OK ($_lines claim line(s) over $_n exported .md file(s); every named conformance check is reachable in what the adopter receives, or the line discloses the dial, or it is narrowed to the kit's own CI and true there)"
  else
    echo "adopter-told: FAIL ($_red inconsistent claim(s) over $_lines claim line(s): $_unreach unreachable, $_mode undisclosed-dial, $_kittok false kit-tree narrowing, $_lex out-of-lexicon verb(s))"
  fi
  return $_rc
}

run() {
  # ARMING — N/A only when NEITHER kit marker is present. Fail-closed on the kit tree.
  if [ "$FIXTURE" = no ] \
     && [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "N/A: adopter-told — kit-self check. It builds an adopter export from the kit's committed HEAD to compare shipped prose against shipped wiring; an incepted tree is the RESULT of that export and has no kit HEAD to archive. To opt in, run it against a kit checkout."
    return 0
  fi
  _w=$(mktemp -d) || { echo "FAIL: adopter-told could not create a work directory"; return 1; }
  # Cleanup is unconditional AND the rc is preserved: a swallowed failure here would be the same
  # silent-disarm class the check exists to close.
  trap 'rm -rf "$_w"' EXIT INT TERM

  if [ "$FIXTURE" = yes ]; then
    _ex=$FROM_EXPORT
    if [ ! -d "$_ex" ]; then echo "FAIL: --from-export '$_ex' is not a directory"; return 1; fi
  else
    _ex="$_w/export"
    if ! _out=$(sh scripts/adopter-export.sh "$_ex" 2>&1); then
      echo "FAIL: the adopter export could not be built on an ARMED (kit-marked) tree, so the shipped prose could not be compared against the shipped wiring. This is a FAILURE, never an N/A — a check that quietly stands down when its own input is missing is the concealment class this lock exists to close."
      printf '%s\n' "$_out" | sed 's/^/       /'
      return 1
    fi
  fi

  at_reach_sets "$_ex" "$KIT_ROOT" "$_w" || return 1
  at_judge "$_ex" "$_w" || return 1
  return 0
}

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)

  # LIVENESS ANCHOR / positive: a claim naming a HARD-reachable script passes. Without this leg an
  # always-red mutant would satisfy every negative below.
  at_fix "$W/good"
  at_claim "$W/good" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  at_expect "liveness anchor: a claim naming a hard-reachable check passes" 0 "$W/good"

  # SEEDED FALSE CLAIM (the row's own non-vacuity AC) — and the red is CAUSED by the seeded line.
  at_fix "$W/seed"
  at_claim "$W/seed" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  at_claim "$W/seed" "docs/bad.md" '**Gate-checked** on the PR head commit by `conformance/nonexistent-gate.sh`.'
  at_expect "a seeded claim naming an UNREACHABLE check reds" 1 "$W/seed"
  at_says "the unreachable red names the offending file and script" 'docs/bad.md' "$W/seed"
  rm -f "$W/seed/export/docs/bad.md"
  at_expect "removing the seeded line greens it again (the red was CAUSED by that line)" 0 "$W/seed"

  # MODE AXIS — a dial-reachable gate claimed without a delivery qualifier reds; with one, greens.
  at_fix "$W/mode"
  at_claim "$W/mode" "docs/a.md" '**Gate-checked** on the PR head commit by `conformance/loop-state.sh`.'
  at_expect "a dial-reachable gate claimed with NO delivery qualifier reds" 1 "$W/mode"
  at_says "the mode red says the dial is undisclosed" 'FAIL[mode]' "$W/mode"
  at_claim "$W/mode" "docs/a.md" '**Gate-checked** by `conformance/loop-state.sh` — observe-mode until the adopter flips `LOOP_STATE_MODE`.'
  at_expect "the same claim WITH the delivery qualifier greens" 0 "$W/mode"

  # EMITTED-DEFAULT AXIS (LOOP-STATE-ADOPTER-ENFORCE, 2026-08-30). Whether a gate is DIAL-reachable
  # is a property of what the adopter's workflow SHIPS, not of which file the run-line lives in.
  # With the emitted default at `enforce`, a run-line in profiles/adopter-gates.yml is HARD reach —
  # the claim "gate-checked by loop-state.sh" is simply TRUE for that adopter, and demanding a dial
  # qualifier would force the corpus to disclose a dial that is not deciding anything. With the
  # default at `observe` the old demand is exactly right. So the axis reads the default rather than
  # hardcoding either answer, and a future flip in EITHER direction moves this check with it.
  at_fix "$W/emitted"
  at_set_mode "$W/emitted" enforce
  at_claim "$W/emitted" "docs/a.md" '**Gate-checked** on the PR head commit by `conformance/loop-state.sh`.'
  at_expect "emitted default enforce: an UNQUALIFIED loop-state claim is true and greens" 0 "$W/emitted"

  # THE INVERSE, ON THE SAME FIXTURE — this pair is the discriminant. A mutant that simply deleted
  # the mode axis would pass the leg above and fail this one; a mutant that ignored the emitted
  # default would fail the leg above and pass this one. Neither passes both.
  at_set_mode "$W/emitted" observe
  at_expect "flipping the emitted default back to observe RE-ARMS the qualifier demand" 1 "$W/emitted"
  at_says "the re-armed demand is the mode axis" 'FAIL[mode]' "$W/emitted"

  # FAIL-SAFE DIRECTION: no env block at all (an adopter deleted the line) must read as `observe`,
  # i.e. the DEMANDING answer. An unreadable dial must never be taken as "enforcing".
  at_set_mode "$W/emitted" none
  at_expect "an ABSENT emitted default is read as observe (demanding), never as enforce" 1 "$W/emitted"

  # DELIVERY TOKEN IS WORD-ANCHORED (security LOW-2). A sentence that merely REPORTS an observation
  # ("observed", "observer") is not a dial disclosure and must not green the claim; the bare word,
  # alone and without LOOP_STATE_MODE, must.
  at_fix "$W/observed"
  at_claim "$W/observed" "docs/a.md" '**Gate-checked** by `conformance/loop-state.sh`; no failures were observed by the reviewer.'
  at_expect "\"observed\" does NOT satisfy the delivery qualifier (word-anchored)" 1 "$W/observed"
  at_claim "$W/observed" "docs/a.md" '**Gate-checked** by `conformance/loop-state.sh`; it runs in observe mode on your tree.'
  at_expect "the bare word \"observe\" alone DOES satisfy it" 0 "$W/observed"

  # COMMENTS-EXCLUDED PARSE (MED-3) — the pin had no oracle: the old fixture comment did not match the
  # run-line regex even with the exclusion removed, so a `grep -v '^#'` -> `cat` mutant SURVIVED. The
  # fixture comment is now a REAL commented-out run line, so a claim naming it is RED while comments
  # are excluded and GREEN the moment they are not — which is what kills that mutant.
  at_fix "$W/commented"
  at_claim "$W/commented" "docs/a.md" 'Enforced by `conformance/commented.sh` on every push.'
  at_expect "a check named only on a COMMENTED-OUT run line is unreachable (comments excluded) and reds" 1 "$W/commented"
  at_says "the commented-out red is the unreachable axis" 'FAIL[unreachable]' "$W/commented"

  # KIT TOKEN (M-6 narrowing) — the token switches the judged set; it does not exempt.
  at_fix "$W/kit1"
  at_claim "$W/kit1" "docs/a.md" 'Enforced by `conformance/kitonly.sh` in the kit'"'"'s own CI.'
  at_expect "kit token + a kit-reachable script greens" 0 "$W/kit1"
  at_fix "$W/kit2"
  at_claim "$W/kit2" "docs/a.md" 'Enforced by `conformance/nowhere.sh` in the kit'"'"'s own CI.'
  at_expect "kit token + a KIT-UNREACHABLE script still reds (the token narrows, never exempts)" 1 "$W/kit2"
  at_says "the kit-token red says the token does not excuse the claim" 'FAIL[kit-token]' "$W/kit2"

  # ── THE TWO-LIST DETECTOR (ADOPTER-TOLD-LEXICON-RESIDUAL) ─────────────────────────────────────
  # LIST HYGIENE FIRST, and it is checked BOTH WAYS. Two lists only mean something while they are
  # DISJOINT and both NON-EMPTY: a verb in both is judged by whichever branch runs first (silently),
  # and an empty NONCLAIM_VERBS turns every description into a red while an empty CLAIM_VERBS empties
  # the claim domain. Neither failure is visible in any corpus leg, so it is asserted here directly.
  # ⚠️ `while IFS= read`, NEVER `for _cv in $(…)`: every entry is TWO WORDS ("enforced by"), so word
  # splitting shreds them and the comparison silently matches nothing. The first draft of this leg did
  # exactly that and a mutant putting `enforced by` in BOTH lists SURVIVED it — the leg was vacuous.
  _lx=0
  printf '%s\n' "$NONCLAIM_VERBS" | tr '|' '\n' > "$W/nonclaim.list"
  printf '%s\n' "$CLAIM_VERBS" | tr '|' '\n' > "$W/claim.list"
  while IFS= read -r _cv; do
    [ -n "$_cv" ] || continue
    grep -qxF "$_cv" "$W/nonclaim.list" && {
      echo "FAIL: selftest — the verb \"$_cv\" is in BOTH CLAIM_VERBS and NONCLAIM_VERBS. The two lists are the whole detector; an overlapping verb is judged by whichever branch is written first, silently."; sfail=1; _lx=1; }
  done < "$W/claim.list"
  [ "$(printf '%s\n' "$CLAIM_VERBS" | tr '|' '\n' | grep -c .)" -ge 5 ] || {
    echo "FAIL: selftest — CLAIM_VERBS collapsed below 5 entries; the claim domain would empty out"; sfail=1; }
  [ "$(printf '%s\n' "$NONCLAIM_VERBS" | tr '|' '\n' | grep -c .)" -ge 5 ] || {
    echo "FAIL: selftest — NONCLAIM_VERBS collapsed below 5 entries; ordinary description would red"; sfail=1; }
  [ "$_lx" = 0 ] && echo "PASS: selftest — CLAIM_VERBS and NONCLAIM_VERBS are disjoint and both non-empty"
  # MEMBERSHIP, PINNED. One representative from each list, asserted in the direction that would break
  # if the list it lives in were emptied or if the two were swapped.
  printf '%s\n' 'enforced by' | grep -qxiE "$CLAIM_VERBS" || { echo "FAIL: selftest — 'enforced by' left CLAIM_VERBS"; sfail=1; }
  printf '%s\n' 'generated by' | grep -qxiE "$NONCLAIM_VERBS" || { echo "FAIL: selftest — 'generated by' left NONCLAIM_VERBS"; sfail=1; }
  printf '%s\n' 'enforced by' | grep -qxiE "$NONCLAIM_VERBS" && { echo "FAIL: selftest — a CLAIM verb is also allowlisted as non-claim"; sfail=1; }
  # THE OUT-OF-LEXICON ARM. An unknown passive verb over a ref-bearing line must RED **naming the
  # verb** — the remedy is a one-word list edit, so the message has to carry the word.
  at_fix "$W/lex"
  at_claim "$W/lex" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  at_claim "$W/lex" "docs/lex.md" 'The entry contract is frobnicated by `conformance/hardgate.sh` on every push.'
  at_expect "an OUT-OF-LEXICON passive verb over a check reference reds" 1 "$W/lex"
  at_says "the lexicon red NAMES the offending verb" 'frobnicated by' "$W/lex"
  at_says "the lexicon red is its own axis" 'FAIL[lexicon]' "$W/lex"
  # LOAD-BEARING NEGATIVE #1: the same line with an ALLOWLISTED verb must be silent. Without this,
  # an always-red lexicon arm (or an empty NONCLAIM_VERBS) would pass the leg above.
  at_claim "$W/lex" "docs/lex.md" 'The skeleton is generated by `conformance/hardgate.sh` at build time.'
  at_expect "an allowlisted NON-CLAIM verb over the same reference is silent" 0 "$W/lex"
  # LOAD-BEARING NEGATIVE #2: the arm must need a REF. A passive verb with no conformance reference on
  # the line is ordinary English and must never red, or the detector reds the whole corpus.
  at_claim "$W/lex" "docs/lex.md" 'The release notes are frobnicated by the maintainer before publication.'
  at_expect "an unknown passive verb with NO check reference on the line is not a claim and is silent" 0 "$W/lex"
  # THE BARE-BASENAME EXTRACTOR — the second unnamed hole. A backticked basename that RESOLVES against
  # the export's conformance/ names the same check as the anchored path and must be judged the same.
  at_fix "$W/bare"
  at_claim "$W/bare" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  at_claim "$W/bare" "docs/bare.md" 'Enforced by `nonexistent-gate.sh` on every push.'
  at_expect "a BARE backticked basename naming an unreachable check reds like the anchored form" 1 "$W/bare"
  at_says "the bare-basename red resolves to the full path" 'conformance/nonexistent-gate.sh' "$W/bare"
  # LOAD-BEARING NEGATIVE: a basename that does NOT resolve against the export's conformance/ is not a
  # reference at all. Without this the extractor would conjure a claim out of any `foo.sh` in prose.
  at_claim "$W/bare" "docs/bare.md" 'Enforced by `some-random-tool.sh` on every push.'
  at_expect "a backticked basename that resolves to NOTHING in conformance/ is not a reference" 0 "$W/bare"
  # LIVING/DATED SCOPING, AND ITS BOUNDARY. Three legs on one fixture; the THIRD is the one that
  # matters — the exemption covers the REWORD-demanding lexicon arm ONLY. An earlier draft skipped the
  # whole file and disarmed the reachability arms over every dated record; leg 3 pins that shut.
  at_fix "$W/dated"
  at_claim "$W/dated" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  at_claim "$W/dated" "docs/live.md" 'The contract is frobnicated by `conformance/hardgate.sh` on every push.'
  at_expect "an out-of-lexicon verb in a LIVING doc reds" 1 "$W/dated"
  rm -f "$W/dated/export/docs/live.md"
  at_claim "$W/dated" "CHANGELOG.md" 'The contract is frobnicated by `conformance/hardgate.sh` on every push.'
  at_expect "the SAME out-of-lexicon verb in CHANGELOG.md is exempt (a dated record must not be reworded)" 0 "$W/dated"
  # THE BOUNDARY LEG: an UNREACHABLE-check claim in that same dated record still REDS. Reporting that
  # a named gate is not wired is a fact about today's tree, not a demand to rewrite history.
  at_claim "$W/dated" "CHANGELOG.md" '**Gate-checked** by `conformance/nonexistent-gate.sh`.'
  at_expect "an UNREACHABLE claim in a dated record still reds (the exemption is the lexicon arm only)" 1 "$W/dated"
  at_says "the dated-record red is the reachability axis, not the lexicon one" 'FAIL[unreachable]' "$W/dated"

  # FLOOR MECHANISM — each floor is load-bearing, and each leg can now pass ONLY via its own branch.
  # ⚠️ THE PREVIOUS VERSION OF THESE LEGS WAS TAUTOLOGICAL and both review seats said so: with fixture
  # floors of 1, the only fixture that could breach a floor was an EMPTY one, which ALSO emptied the
  # claim domain — so the leg's red actually came from the downstream empty-domain branch, and the
  # floor comparison itself was never observed. Fixture floors are now 3, and every leg below breaches
  # exactly ONE input while keeping the others live.
  #
  # MD floor: corpus 2 (< 3) but the claim domain is NON-EMPTY and would otherwise be green, so the
  # only thing that can red this is the corpus comparison.
  at_fix "$W/nomd"
  at_claim "$W/nomd" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  rm -f "$W/nomd/export/docs/f2.md" "$W/nomd/export/docs/f3.md"
  at_expect "a corpus UNDER the floor FAILs on the corpus comparison, with a live non-empty domain" 1 "$W/nomd"
  at_says "the corpus red names the corpus floor" 'Markdown file(s), under the floor of' "$W/nomd"
  # ROW floor: registry 2 (< 3) but hardgate KEEPS its live row, so the claim below would be green and
  # the reach set is non-empty — the only thing that can red this is the registry comparison.
  at_fix "$W/norows"
  at_claim "$W/norows" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  { printf 'check control hardgate sh conformance/hardgate.sh\n'
    printf 'check control kitonly --kitself sh conformance/kitonly.sh\n'; } > "$W/norows/export/conformance/verify.sh"
  at_expect "a registry UNDER the floor FAILs on the registry comparison, with a live reach set" 1 "$W/norows"
  at_says "the registry red names the registry floor" "'check' row(s), under the floor of" "$W/norows"
  # ANCHOR: every count stays over its floor and the domain is live; only the anchor is gone.
  at_fix "$W/noanchor"
  at_claim "$W/noanchor" "docs/a.md" 'Enforced by `conformance/hardgate.sh` on every push.'
  printf 'jobs:\n  x:\n    steps:\n      - run: echo nothing\n' > "$W/noanchor/export/profiles/adopter-gates.yml"
  at_expect "losing the loop-state run-line anchor FAILs (the dial axis would be silently dead)" 1 "$W/noanchor"
  at_says "the anchor red names the anchor" 'loop-state.sh run-line' "$W/noanchor"

  # NO CLAIM LINES AT ALL — every floor is satisfied (3 filler docs, 3 registry rows, anchor present),
  # so an empty claim domain is the ONLY thing that can red this one.
  at_fix "$W/noclaims"
  at_expect "a corpus with ZERO claim lines FAILs (an empty domain asserts nothing)" 1 "$W/noclaims"
  at_says "the empty-domain red says the domain is empty" 'ZERO claim lines matched' "$W/noclaims"

  # ARMING (vet H-3), both legs, exercised through the REAL run() with no --from-export.
  #   (a) a kit-MARKED tree cannot self-N/A;  (b) an export failure on an armed tree is FAIL, not N/A.
  mkdir -p "$W/armed/docs"; : > "$W/armed/docs/ROADMAP-KIT.md"   # marked, but not a git repo
  _arc=0; _arout=$( cd "$W/armed" && sh "$_self" 2>&1 ) || _arc=$?
  if [ "$_arc" = 0 ]; then
    echo "FAIL: selftest — a kit-MARKED tree exited 0; the arming marker did not hold it to the lock"; sfail=1
  elif printf '%s\n' "$_arout" | grep -q '^N/A'; then
    echo "FAIL: selftest — a kit-MARKED tree SELF-N/A'd; one marker must hold the tree to the lock"; sfail=1
  elif ! printf '%s\n' "$_arout" | grep -qF 'never an N/A'; then
    echo "FAIL: selftest — an export failure on an ARMED tree did not say why it is a FAIL and not an N/A"; sfail=1
  else
    echo "PASS: selftest — an armed tree cannot self-N/A, and a failed export there is a FAIL"
  fi
  # ...and the opposite direction: a marker-LESS (adopter-shaped) tree renders a line-anchored N/A.
  mkdir -p "$W/adopter"
  _adc=0; _adout=$( cd "$W/adopter" && sh "$_self" 2>&1 ) || _adc=$?
  if [ "$_adc" != 0 ] || ! printf '%s\n' "$_adout" | grep -q '^N/A: adopter-told'; then
    echo "FAIL: selftest — an adopter-shaped tree did not render a line-anchored 'N/A:' at rc 0 (got rc $_adc)"; sfail=1
  else
    echo "PASS: selftest — an adopter-shaped tree self-N/As legibly at rc 0"
  fi

  rm -rf "$W"
  [ "$sfail" -eq 0 ] && { echo "adopter-told --selftest: OK (anchor + seeded-false-claim reds and its removal greens + mode axis both ways + the emitted-default axis (enforce greens an unqualified claim, observe re-arms the demand, absent fail-safes to observe) + word-anchored delivery token (observed vs observe) + comments-excluded oracle + kit-token narrowing both ways + three branch-isolated floors + empty-domain + arming both directions + the TWO-LIST detector: disjoint non-empty lexicons, an out-of-lexicon verb reds NAMING the verb, an allowlisted verb and a verb with no check reference are both silent + the bare-basename extractor with its unresolvable-basename negative + living-vs-dated scoping on one fixture, all three directions: the lexicon arm is exempt in a dated record, red in a living one, and the REACHABILITY arms stay armed in the dated record too)"; return 0; }
  echo "adopter-told --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker, so fixture builders and kill logic sit in the protected oracle region) ---

at_fix() {  # <dir> — a minimal EXPORT-shaped tree plus a kit-shaped tree beside it
  _d=$1
  mkdir -p "$_d/export/profiles/tsn" "$_d/export/conformance" "$_d/export/docs" \
           "$_d/kit/.github/workflows" "$_d/kit/conformance"
  # a shipped pipeline that INVOKES one gate (hard-reachable) and CARRIES ONE COMMENTED-OUT run line.
  # ⚠️ The commented line must be a REAL run line, byte-for-byte the shape of the live one below it —
  # a prose comment mentioning a path is not an oracle for the comments-excluded pin, because it fails
  # the invocation regex anyway (MED-3: that is exactly how the `grep -v` -> `cat` mutant survived).
  printf 'jobs:\n  q:\n    steps:\n      #      - run: sh conformance/commented.sh\n      - run: sh conformance/hardgate.sh\n' \
    > "$_d/export/profiles/tsn/ci.yml"
  # A FILLER CORPUS that clears the fixture MD floor (3) and carries no claim verb and no
  # conformance ref, so it changes no verdict — it only stops the floor legs being tautological.
  printf '# filler\n\nNothing here makes a claim about anything.\n' > "$_d/export/docs/f1.md"
  printf '# filler\n\nStill nothing.\n' > "$_d/export/docs/f2.md"
  printf '# filler\n\nAlso nothing.\n' > "$_d/export/docs/f3.md"
  # the dialed workflow — its loop-state run-line is the anchor the floor requires
  printf 'env:\n  LOOP_STATE_MODE: observe\njobs:\n  g:\n    steps:\n      - run: sh conformance/loop-state.sh --head "$SHA"\n' \
    > "$_d/export/profiles/adopter-gates.yml"
  # the export registry: one LIVE row, one --kitself row, one --selftest-only row
  { printf 'check control hardgate sh conformance/hardgate.sh\n'
    printf 'check control kitonly --kitself sh conformance/kitonly.sh\n'
    printf 'check control selfonly sh conformance/selfonly.sh --selftest\n'
  } > "$_d/export/conformance/verify.sh"
  # REAL FILES in the export's conformance/, because the BARE-BASENAME extractor's whole predicate is
  # "does this backticked basename RESOLVE here". Content is irrelevant; existence is the test. A
  # basename with no file behind it must stay invisible, which is what `some-random-tool.sh` pins.
  : > "$_d/export/conformance/hardgate.sh"; : > "$_d/export/conformance/nonexistent-gate.sh"
  # the kit registry + workflows: kitonly.sh is reachable HERE and nowhere else
  printf 'check control hardgate sh conformance/hardgate.sh\n' > "$_d/kit/conformance/verify.sh"
  printf 'jobs:\n  k:\n    steps:\n      - run: sh conformance/kitonly.sh\n      - run: sh conformance/loop-state.sh\n' \
    > "$_d/kit/.github/workflows/ci.yml"
}

at_set_mode() {  # <dir> <enforce|observe|none> — rewrite the fixture's emitted LOOP_STATE_MODE
  # `none` omits the env block entirely, which is what an adopter who deleted the line leaves
  # behind. The reader must treat that as `observe` — the DEMANDING direction.
  if [ "$2" = none ]; then
    printf 'jobs:\n  g:\n    steps:\n      - run: sh conformance/loop-state.sh --head "$SHA"\n' \
      > "$1/export/profiles/adopter-gates.yml"
  else
    printf 'env:\n  LOOP_STATE_MODE: %s\njobs:\n  g:\n    steps:\n      - run: sh conformance/loop-state.sh --head "$SHA"\n' \
      "$2" > "$1/export/profiles/adopter-gates.yml"
  fi
}

at_claim() {  # <dir> <relative-md-path> <line> — plant a claim line in the fixture corpus
  mkdir -p "$(dirname "$1/export/$2")"
  printf '# fixture\n\n%s\n' "$3" > "$1/export/$2"
}

at_run() {  # <dir> — judge the fixture export against the fixture kit
  ( cd "$1" && sh "$_self" --from-export export --kit-root kit 2>&1 )
}

at_expect() {  # <label> <want-rc> <dir>
  _rc=0; _out=$(at_run "$3") || _rc=$?
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want rc $2, got $_rc)"; printf '%s\n' "$_out" | sed 's/^/    /'; sfail=1; fi
}

at_says() {  # <label> <needle> <dir>
  _out=$(at_run "$3") || :
  if printf '%s\n' "$_out" | grep -qF -- "$2"; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (missing '$2')"; printf '%s\n' "$_out" | sed 's/^/    /'; sfail=1; fi
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
run; exit $?
