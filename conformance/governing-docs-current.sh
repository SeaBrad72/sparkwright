#!/bin/sh
# governing-docs-current.sh — recurrence latch for the RETIRED control-plane hand-off.
#
# CP-8c (v3.124.0) abolished the AMBER `apply.py` hand-off (author to scratchpad/, a HUMAN runs an
# idempotent script) and replaced it with the DEV-CLONE (the agent edits directly in a disposable
# clone; the guard stays armed on the real repo; the human reviews a CI-green DIFF). CP-10 fixed
# two docs. It missed the rest, which kept PRESCRIBING the retired route — including the ones an
# agent reads BEFORE it can know better (DRIFT-1, the KW21 class in governance itself).
# CP-8c/CP-10 fixed INSTANCES and the drift recurred. This fixes the CLASS: it turns RED if a
# governing artifact ever teaches the retired convention again.
#
#   usage: sh conformance/governing-docs-current.sh [--selftest]
#   exit:  0 = every governing doc is current (or N/A: incepted tree) · 1 = a governing doc
#          prescribes the retired route, a named member is missing, or the set has drifted · 2 = usage
#
# KIT-ONLY, BY DESIGN (dual review, DRIFT-1 B1/B2). This latch governs the KIT's OWN governing docs.
# It must NOT run on an adopter's tree, for two reasons the reviewers proved with PoCs:
#   1. VACUITY BY SUBSTITUTION. `scripts/incept.sh` does `git mv CLAUDE.md ENGINEERING-PRINCIPLES.md`
#      and stamps a NEW project CLAUDE.md. Post-incept the slot named "CLAUDE.md" is still FULL — with
#      a different document. A presence check cannot see a substitution: the count stays whole and the
#      green looks earned while the real principles doc goes unscanned.
#   2. FALSE-RED ON ADOPTER PROSE. `apply.py` is a generic filename. An adopter writing "run
#      `python scripts/apply.py` for migrations" in their own file would hard-RED a zero-tolerance,
#      REQUIRED_IDS-undroppable gate — wedged by a latch about the kit's internal history.
# So: we detect an incepted tree by the kit's OWN invariant (incept.sh:195 — ENGINEERING-PRINCIPLES.md
# exists <=> already incepted) and return N/A. Live-scanned in the kit's ci.yml; NOT in verify.sh's
# portable battery. The claim's verifier is `--selftest` (fixture-based, tree-independent), so the
# claim stays registered and undroppable everywhere.
#
# HONEST CEILING (read before trusting a green):
#   - It greps a KNOWN signature over a NAMED set. It is a recurrence latch for THIS retirement —
#     NOT a general "no retired convention anywhere" prover.
#   - A paraphrase that avoids both tokens escapes it. A future retirement it has never been told
#     about escapes it entirely.
#   - It proves the governing docs no longer TEACH the retired route. It does NOT prove the
#     dev-clone route is FOLLOWED.
set -eu
cd "$(dirname "$0")/.."

# ---- the governing set (NAMED, never globbed) -------------------------------------------------
# Globbing is how a scan set silently shrinks to zero and a check goes vacuously green. So the set is
# NAMED — and a named member that is MISSING is a FAIL, not a skip (a rename would otherwise retire a
# file from the scan in silence). The `skills/*` and `agents/*` FAMILIES are additionally guarded by
# check_set_complete() below, so a NEW skill/agent cannot be born outside the fence.
# SET SIZE 31 -> 30 (FRONT-DOOR-ONE-ROUTER): ONBOARDING.md was RETIRED, its content folded into
# START-HERE.md, which stays in the set. That is the ONLY member removed. The set has no cardinality
# lock, so this comment plus a one-line diff is what distinguishes a deliberate retirement from a
# silent shrink — a reviewer diffs the heredoc below and must see exactly one line gone.
governing_set() {
  cat <<'SET'
skills/build/SKILL.md
skills/continuous-discovery/SKILL.md
skills/debugging/SKILL.md
skills/demonstrate/SKILL.md
skills/design/SKILL.md
skills/evals/SKILL.md
skills/operating/SKILL.md
skills/plan/SKILL.md
skills/review/SKILL.md
skills/tdd/SKILL.md
skills/using-skills/SKILL.md
skills/verification/SKILL.md
skills/worktrees/SKILL.md
agents/engineer.agent.md
agents/orchestrator.agent.md
agents/reviewer.agent.md
agents/security.agent.md
CLAUDE.md
AGENTS.md
START-HERE.md
MAINTAINING.md
MATURITY.md
DEVELOPMENT-PROCESS.md
DEVELOPMENT-STANDARDS.md
docs/governance/promotion-contract.md
docs/operations/harness-adapters.md
docs/kit-internals/meta-control.md
docs/operations/release-tag.md
templates/PROJECT-CLAUDE-TEMPLATE.md
templates/KIT-FEEDBACK-TEMPLATE.md
SET
}

# The retired-convention signature. `apply.py` = the retired VEHICLE; `AMBER` = the retired CEREMONY
# NAME. Either one, in a governing doc, means the retired route is being taught. Matched CASE-
# INSENSITIVELY (dual review): "Amber"/"Apply.py" must not slip the fence on capitalisation alone.
SIGNATURE='apply\.py|AMBER'

# ---- the allowlist policy: ZERO-TOLERANCE (ratified 2026-07-14) --------------------------------
# A hit anywhere in the governing set is a VIOLATION. There is no in-set allowlist, deliberately.
#
# The rejected alternative was a context-aware rule (allow the hit when the line also carries a
# retirement marker like "retired"/"superseded"). It reads more forgiving and is strictly WEAKER:
# it opens a gaming path where a future agent re-introduces the whole prescription and satisfies
# this latch by dropping the word "retired" into the sentence — the check greens while the doc
# teaches the retired route, which is the exact failure DRIFT-1 exists to prevent.
#
# The cost is accepted and small: a governing doc may not NAME the retired convention, even to warn
# someone off it. It doesn't need to — the explainer docs that carry the history
# (docs/kit-internals/retiring-conventions.md, docs/operations/runtime-guards.md) sit deliberately
# OUTSIDE the governing set. Governing docs teach the CURRENT route and point at those for the why.
#
# This latch exists because a fix DIDN'T STICK (CP-8c/CP-10 fixed instances; the drift recurred).
# Its whole value is that it cannot be argued with. Keep it that way.
# (Zero-tolerance takes no context, so this takes no arguments. If you are tempted to add some,
#  re-read the paragraph above first.)
is_violation() { return 0; }

# ---- face 2: the backlog-name face (GOVERNING-DOC-CONTRADICTIONS, 2026-08-27) -------------------
# `BACKLOG.md` is the ONE authoritative board (CLAUDE.md § Roster authority, since 2026-08-20);
# `docs/ROADMAP-KIT.md` is a superseded marker (D-240815-1). MAINTAINING.md kept naming ROADMAP-KIT as
# "its own backlog" for two months after that. Same latch shape, same zero-tolerance: a governing line
# that names ROADMAP-KIT together with the word "backlog" is a VIOLATION — no context rule, for the
# reason above. Cost accepted: a governing doc may not say "ROADMAP-KIT is no longer the backlog"
# either; it says what the board IS and stops.
BACKLOG_NAME_SIGNATURE='ROADMAP-KIT'
BACKLOG_NAME_COTOKEN='backlog'

# ---- face 3: the harness-status face (GOVERNING-DOC-CONTRADICTIONS, 2026-08-27) ------------------
# The adopter's charter is STAMPED from `templates/PROJECT-CLAUDE-TEMPLATE.md` and `scripts/incept.sh`
# says the same sentence on the first run. Both called codex "experimental" for weeks after
# docs/operations/harness-adapters.md promoted it to floor-verified — a stale status stamped into every
# new project. Single source of truth: the maturity CARDS in harness-adapters.md (`#### <harness>` +
# `- **Maturity tier:** **<tier>**`). The STAMP set below is NAMED; every line in it that names a
# carded harness AND a maturity word must carry that harness's card tier. Coherence, not a string ban:
# if the card changes, the stamp must change with it, whichever direction.
# The judged unit is the TIER CLAIM ADJACENT to the harness name, found by a WORD WALK (awk, POSIX):
# the line is lowercased, split into clauses on `.`/`;`, each clause into words on anything but
# [a-z0-9-] (so **bold**, quotes and backticks vanish — round 3, m1). For EVERY occurrence of the
# harness word: the first `is`/`are` WORD within 8 words after it (whole words — "this" is not "is";
# round 3, m2), then the FIRST tier word within 4 words after that verb — so "codex is experimental and
# codex is floor-verified" reds on the first claim (round 3, M2), and "codex is experimental … Floor-
# verified is codex's maximum" reds (round 2, M2). Every claim on the line is judged, not just the first.
# The bare word `verified` followed by a verification preposition (by / against / live / at / in / via /
# through / during / with / on) is the OTHER sense of the word and is not a claim; the exemption never
# applies to `experimental` or `floor-verified` (round 3, M1). A claim negated at the verb ("is not …",
# "is no longer …") is SKIPPED, not judged.
# HONEST CEILING: a claim whose verb sits more than 8 words after the harness, or whose tier sits more
# than 4 words after the verb ("codex is, as of today and by the evidence, experimental"), is not judged;
# an abbreviation or decimal inside the clause ("is, e.g. today, experimental") splits it and drops the
# claim; a paraphrase that avoids the is/are shape escapes; a NEGATED claim is skipped in both directions
# ("codex is not floor-verified" passes); a claim about several harnesses at once ("both codex and gemini
# are experimental") is attributed to the LAST one named; a verification preposition outside the class
# above false-reds a truthful "verified <prep>" line (an enumeration — widen it, don't drop the test).
stamp_set() {
  cat <<'SET'
templates/PROJECT-CLAUDE-TEMPLATE.md
scripts/incept.sh
MATURITY.md
SET
}
MATURITY_WORDS='experimental|verified'
TIER_WORDS='floor-verified|verified|experimental'
VERIFICATION_PREPS='by|against|live|at|in|via|through|during|with|on'
HARNESS_CARDS_DOC='docs/operations/harness-adapters.md'

# claim_tiers LINE HARNESS -> one lowercased tier word per adjacent claim LINE makes about HARNESS
# (possibly several; empty when the line makes none, or only negated / verification-sense ones).
claim_tiers() {
  # POSIX awk only (split with an ERE, `x in ARR`, scalar indexing) — no gawk/mawk extensions; CI runs mawk.
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | awk -v h="$2" -v preps="$VERIFICATION_PREPS" -v tiers="$TIER_WORDS" -v harnesses="$3" '
    BEGIN {
      np = split(preps, P, "|"); for (i = 1; i <= np; i++) PREP[P[i]] = 1
      nt = split(tiers, T, "|"); for (i = 1; i <= nt; i++) TIER[T[i]] = 1
      nh = split(harnesses, H, " "); for (i = 1; i <= nh; i++) HARNESS[H[i]] = 1
    }
    {
      nc = split($0, C, /[.;]/)
      for (c = 1; c <= nc; c++) {
        n = split(C[c], W, /[^a-z0-9-]+/)
        for (i = 1; i <= n; i++) {
          if (W[i] != h) continue
          # EVERY is/are verb in the window is tried: a negated or verification-sense verb does not
          # end the search ("codex, which is verified by CP-7, is experimental" reds — round 4, M1).
          # A DIFFERENT carded harness between the harness and the verb re-attributes the clause
          # ("Unlike codex, the cursor adapter is experimental" makes no claim about codex — round 4, m1).
          for (v = i + 1; v <= n && v <= i + 8; v++) {
            if ((W[v] in HARNESS) && W[v] != h) break
            if (W[v] != "is" && W[v] != "are") continue
            if (W[v + 1] == "not" || (W[v + 1] == "no" && W[v + 2] == "longer")) continue
            t = 0
            for (k = v + 1; k <= n && k <= v + 4; k++) if (W[k] in TIER) { t = k; break }
            if (!t) continue
            if (W[t] == "verified" && (W[t + 1] in PREP)) continue
            print W[t]; break
          }
        }
      }
    }'
}

# card_tiers ROOT -> lines of "<harness> <tier>" parsed from the cards doc; the tier is the FIRST
# token of the bolded value ("verified (first-class)" -> "verified"). Empty when absent.
card_tiers() {
  awk '
    /^#### [a-z][a-z0-9-]*$/ { cur = substr($0, 6); next }
    cur != "" && /Maturity tier:\*\* \*\*[^*]+\*\*/ {
      t = $0; sub(/.*Maturity tier:\*\* \*\*/, "", t); sub(/\*\*.*/, "", t); sub(/[^a-z-].*/, "", t)
      if (t != "") { print cur, t }; cur = ""
    }' "$1/$HARNESS_CARDS_DOC" 2>/dev/null
}
# card_headings ROOT -> the number of `#### <harness>` headings that carry a "Maturity tier" line (in ANY
# format) before the next heading — i.e. the CARDS, not every lowercase h4 in the doc (review round 2, m2).
card_headings() {
  awk '
    /^#### [a-z][a-z0-9-]*$/ { if (pending) n++; pending = 0; inh = 1; next }
    /^##/ { if (pending) n++; pending = 0; inh = 0; next }
    inh && /Maturity tier/ { pending = 1 }
    END { if (pending) n++; print n + 0 }' "$1/$HARNESS_CARDS_DOC" 2>/dev/null || echo 0
}

# scan_harness_status ROOT -> 0 clean / 1 violation. Prints each violation.
scan_harness_status() {
  _hs_root=$1; _hs_viol=0; _hs_cards=$(card_tiers "$_hs_root")
  _hs_all=$(printf '%s\n' "$_hs_cards" | cut -d' ' -f1 | tr '\n' ' ')   # every carded harness name
  if [ -z "$_hs_cards" ]; then
    echo "FAIL: no harness maturity cards parsed from $HARNESS_CARDS_DOC (the harness-status face has no source of truth — vacuous)"
    return 1
  fi
  # PARTIAL parse loss is as vacuous as total loss: every card heading must yield a tier (review B1).
  _hs_nh=$(card_headings "$_hs_root"); _hs_np=$(printf '%s\n' "$_hs_cards" | grep -c .)
  if [ "${_hs_nh:-0}" -ne "$_hs_np" ]; then
    echo "FAIL: $HARNESS_CARDS_DOC has $_hs_nh harness card heading(s) but only $_hs_np parsed tier(s) — a card format the parser cannot read leaves that harness unguarded"
    return 1
  fi
  for _hs_f in $(stamp_set); do
    if [ ! -f "$_hs_root/$_hs_f" ]; then
      echo "FAIL: named stamp artifact '$_hs_f' is MISSING (renamed? removed? — the stamp set must track it)"
      _hs_viol=1; continue
    fi
    while IFS= read -r _hs_hit; do
      [ -n "$_hs_hit" ] || continue
      _hs_n=${_hs_hit%%:*}; _hs_t=${_hs_hit#*:}
      for _hs_ct in $(printf '%s\n' "$_hs_cards" | tr ' ' ':'); do
        _hs_h=${_hs_ct%%:*}; _hs_tier=${_hs_ct#*:}
        for _hs_said in $(claim_tiers "$_hs_t" "$_hs_h" "$_hs_all"); do   # every adjacent claim on the line
          [ "$_hs_said" = "$_hs_tier" ] && continue
          echo "FAIL: $_hs_f:$_hs_n claims harness '$_hs_h' is '$_hs_said' but its card tier is '$_hs_tier' ($HARNESS_CARDS_DOC)"
          echo "    | $_hs_t"
          _hs_viol=1
        done
      done
    done <<EOF
$(grep -niE "$MATURITY_WORDS" "$_hs_root/$_hs_f" 2>/dev/null || true)
EOF
  done
  return "$_hs_viol"
}

# ---- set-completeness: a new skill/agent cannot be born outside the fence ----------------------
# The set is NAMED (not globbed) for anti-vacuity. The cost of naming is that it can go STALE — the
# original DRIFT-1 set missed 6 skills, an agent, START-HERE.md and MATURITY.md, and a planted
# prescription in START-HERE.md sailed straight through. So: enumerate the families ON DISK and FAIL
# if anything resolved is not in the named set. Named for anti-vacuity, family-locked for coverage.
check_set_complete() {
  _root=$1; _gap=0
  for _found in "$_root"/skills/*/SKILL.md "$_root"/agents/*.agent.md; do
    [ -f "$_found" ] || continue                    # unexpanded glob when a family is absent
    _rel=${_found#"$_root"/}
    if ! governing_set | grep -qxF "$_rel"; then
      echo "FAIL: $_rel exists on disk but is NOT in the named governing set (set drift — add it)"
      _gap=1
    fi
  done
  return "$_gap"
}

# ---- the scan ----------------------------------------------------------------------------------
scan() {
  _root=$1; _viol=0; _scanned=0

  # KIT-ONLY: an incepted tree is N/A (see the header). incept.sh:195 uses this same invariant.
  if [ -f "$_root/ENGINEERING-PRINCIPLES.md" ]; then
    echo "governing-docs-current: N/A — incepted tree (this latch governs the KIT's own governing docs)"
    return 0
  fi

  check_set_complete "$_root" || _viol=1

  for _f in $(governing_set); do
    if [ ! -f "$_root/$_f" ]; then
      # A NAMED member that is missing is a FAILURE, never a silent skip: a rename or a typo would
      # otherwise retire a file from the scan and still print a confident "OK — N scanned".
      echo "FAIL: named governing artifact '$_f' is MISSING (renamed? removed? — the scan set must track it)"
      _viol=1
      continue
    fi
    _scanned=$((_scanned + 1))
    while IFS= read -r _hit; do
      [ -n "$_hit" ] || continue
      _n=${_hit%%:*}; _t=${_hit#*:}
      if is_violation; then
        echo "FAIL: $_f:$_n prescribes the RETIRED control-plane hand-off (dev-clone is the current route)"
        echo "    | $_t"
        _viol=1
      fi
    done <<EOF
$(grep -niE "$SIGNATURE" "$_root/$_f" 2>/dev/null || true)
EOF
    # face 2: ROADMAP-KIT named as the backlog.
    while IFS= read -r _hit; do
      [ -n "$_hit" ] || continue
      _n=${_hit%%:*}; _t=${_hit#*:}
      printf '%s' "$_t" | grep -qi "$BACKLOG_NAME_COTOKEN" || continue
      echo "FAIL: $_f:$_n names ROADMAP-KIT as a backlog (BACKLOG.md is the one authoritative board; D-240815-1)"
      echo "    | $_t"
      _viol=1
    done <<EOF
$(grep -ni "$BACKLOG_NAME_SIGNATURE" "$_root/$_f" 2>/dev/null || true)
EOF
  done

  # face 3: the stamped harness status must match the maturity cards.
  scan_harness_status "$_root" || _viol=1

  # Anti-vacuity backstop: a scan that resolved NOTHING is a failure, never a green.
  if [ "$_scanned" -eq 0 ]; then
    echo "FAIL: governing set resolved to ZERO files under '$_root' — vacuous scan, not a pass"
    return 1
  fi
  if [ "$_viol" -ne 0 ]; then
    echo "governing-docs-current: FAIL — $_scanned scanned; a governing doc contradicts the current route/board/harness status (or the set drifted) — see the FAIL lines above"
    return 1
  fi
  echo "governing-docs-current: OK — $_scanned governing artifact(s) (+ $(stamp_set | grep -c .) stamp artifact(s)) scanned; none prescribes the retired hand-off, names ROADMAP-KIT as a backlog, or stamps a harness tier its card contradicts"
  return 0
}

# ---- selftest (non-vacuity: the check must be RED-able) ----------------------------------------
# Fixtures LEFT in place (no rm -rf; the 7e guard convention).
selftest() {
  st=0
  base=$(mktemp -d)

  # A minimal COMPLETE fixture tree: every named member present, all clean.
  mk_clean() {
    _d=$1
    for _m in $(governing_set) $(stamp_set); do
      mkdir -p "$_d/$(dirname "$_m")"
      printf '# governing doc\nControl-plane work is authored in a dev-clone; the human reviews the diff.\n' > "$_d/$_m"
    done
    # Maturity cards (face 3's source of truth) + a coherent stamp line in each stamp-set member.
    # claude-code's card uses the REAL format, "**verified (first-class)**" — the parser must read it.
    printf '#### claude-code\n- **Maturity tier:** **verified (first-class)** — self-hosted.\n#### codex\n- **Maturity tier:** **floor-verified** — cold CP-7.\n#### gemini\n- **Maturity tier:** **experimental** — unproven.\n' \
      >> "$_d/$HARNESS_CARDS_DOC"
    for _m in $(stamp_set); do
      printf "Only 'claude-code' is VERIFIED; 'codex' is FLOOR-VERIFIED; 'gemini' is EXPERIMENTAL.\n" >> "$_d/$_m"
    done
  }

  mk_clean "$base/clean"
  if scan "$base/clean" >/dev/null 2>&1; then
    echo "OK: clean governing set -> GREEN"
  else
    echo "FAIL: selftest — a clean governing set wrongly reddened"; st=1
  fi

  # NEGATIVE (load-bearing): a governing doc that PRESCRIBES the retired route must go RED.
  # If this passes, the check is dead and every green it ever emitted was worthless.
  mk_clean "$base/planted"
  printf 'Author it under `scratchpad/`, assemble an idempotent `apply.py`, and hand it to the human (AMBER).\n' \
    >> "$base/planted/skills/plan/SKILL.md"
  if scan "$base/planted" >/dev/null 2>&1; then
    echo "FAIL: selftest — planted retired prescription did NOT redden the scan (check is dead)"; st=1
  else
    echo "OK: planted retired-convention prescription -> RED"
  fi

  # CASE-INSENSITIVITY: capitalisation must not slip the fence.
  mk_clean "$base/case"
  printf 'The Amber hand-off: a human runs Apply.Py from scratchpad.\n' >> "$base/case/MAINTAINING.md"
  if scan "$base/case" >/dev/null 2>&1; then
    echo "FAIL: selftest — a case-variant prescription escaped (needs -i)"; st=1
  else
    echo "OK: case-variant prescription -> RED"
  fi

  # MISSING NAMED MEMBER must FAIL, not silently scan fewer files (dual review M3).
  mk_clean "$base/missing"
  rm -f "$base/missing/skills/plan/SKILL.md"
  if scan "$base/missing" >/dev/null 2>&1; then
    echo "FAIL: selftest — a MISSING named member passed (silent-skip vacuity)"; st=1
  else
    echo "OK: missing named member -> FAIL (no silent skip)"
  fi

  # SET DRIFT: a NEW skill on disk that is not in the named set must FAIL (dual review M1/M4) —
  # otherwise a future skill is born outside the fence and can teach the retired route freely.
  mk_clean "$base/drift"
  mkdir -p "$base/drift/skills/brand-new"
  printf '# brand-new skill\n' > "$base/drift/skills/brand-new/SKILL.md"
  if scan "$base/drift" >/dev/null 2>&1; then
    echo "FAIL: selftest — a skill outside the named set passed (set drift undetected)"; st=1
  else
    echo "OK: skill outside the named set -> FAIL (set-drift caught)"
  fi

  # INCEPTED TREE -> N/A (kit-only). Both dual-review BLOCKER PoCs, verbatim:
  #   B1 — incept RENAMES CLAUDE.md -> ENGINEERING-PRINCIPLES.md and stamps a NEW project CLAUDE.md.
  #        The slot stays FULL, so the old code printed a confident "OK — 18 scanned" while the real
  #        principles doc (unscanned) fully prescribed the retired route. A presence check cannot see
  #        a SUBSTITUTION. We must NOT emit a green here — N/A is the honest answer.
  #   B2 — `apply.py` is a generic filename; an adopter's own prose must never RED an undroppable gate.
  mk_clean "$base/incepted"
  printf '# kit principles (renamed by incept)\nAuthor under `scratchpad/`, assemble an idempotent `apply.py` (the AMBER hand-off).\n' \
    > "$base/incepted/ENGINEERING-PRINCIPLES.md"
  printf 'Run `python scripts/apply.py` to apply our DB migrations.\n' >> "$base/incepted/AGENTS.md"
  _out=$(scan "$base/incepted" 2>&1) && _rc=0 || _rc=1
  if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -q 'N/A'; then
    echo "OK: incepted tree -> N/A (no false green over a substituted slot; adopter prose cannot RED it)"
  elif [ "$_rc" = 0 ]; then
    echo "FAIL: selftest — incepted tree returned a GREEN, not N/A (vacuity by substitution: $_out)"; st=1
  else
    echo "FAIL: selftest — an incepted tree was scanned and RED-ed on adopter prose"; st=1
  fi

  # FACE 2 (load-bearing): re-plant MAINTAINING.md's retired sentence -> RED.
  mk_clean "$base/backlogname"
  printf 'its own `CHANGELOG`; its own backlog (`docs/ROADMAP-KIT.md`); its own L3 retros.\n' >> "$base/backlogname/MAINTAINING.md"
  if scan "$base/backlogname" >/dev/null 2>&1; then
    echo "FAIL: selftest — ROADMAP-KIT re-planted as the backlog did NOT redden the scan (face 2 is dead)"; st=1
  else
    echo "OK: ROADMAP-KIT named as the backlog -> RED"
  fi
  # FACE 2 precision: naming ROADMAP-KIT WITHOUT the backlog word is not a hit (it is an arming marker elsewhere).
  mk_clean "$base/backlogmarker"
  printf 'The kit-self marker is `docs/ROADMAP-KIT.md` (export-ignored).\n' >> "$base/backlogmarker/MAINTAINING.md"
  if scan "$base/backlogmarker" >/dev/null 2>&1; then
    echo "OK: ROADMAP-KIT named as a marker (no backlog word) -> GREEN"
  else
    echo "FAIL: selftest — face 2 reddened a plain marker mention (over-broad)"; st=1
  fi

  # FACE 3 (load-bearing): re-plant the stale incept.sh stamp (codex EXPERIMENTAL) -> RED, in EACH stamp member.
  for _sm in $(stamp_set); do
    _sd="$base/stale-$(basename "$(dirname "$_sm")")"
    mk_clean "$_sd"
    printf "Only 'claude-code' is a VERIFIED harness; 'gemini'/'codex'/'cursor' are EXPERIMENTAL (unproven).\n" >> "$_sd/$_sm"
    if scan "$_sd" >/dev/null 2>&1; then
      echo "FAIL: selftest — codex re-stamped EXPERIMENTAL in $_sm did NOT redden the scan (face 3 is dead)"; st=1
    else
      echo "OK: codex stamped EXPERIMENTAL against a floor-verified card ($_sm) -> RED"
    fi
  done
  # FACE 3 is bidirectional: the CARD moves and the stamp does not -> RED.
  mk_clean "$base/cardmoved"
  printf '#### cursor\n- **Maturity tier:** **floor-verified** — promoted.\n' >> "$base/cardmoved/$HARNESS_CARDS_DOC"
  printf "'cursor' is EXPERIMENTAL.\n" >> "$base/cardmoved/scripts/incept.sh"
  if scan "$base/cardmoved" >/dev/null 2>&1; then
    echo "FAIL: selftest — a promoted card with a stale stamp passed (face 3 is one-directional)"; st=1
  else
    echo "OK: card promoted, stamp stale -> RED"
  fi
  # FACE 3 reads the REAL claude-code card format: demoting the reference harness in a stamp -> RED (review B1).
  mk_clean "$base/refharness"
  printf "Only 'claude-code' is EXPERIMENTAL.\n" >> "$base/refharness/templates/PROJECT-CLAUDE-TEMPLATE.md"
  if scan "$base/refharness" >/dev/null 2>&1; then
    echo "FAIL: selftest — claude-code stamped EXPERIMENTAL against a 'verified (first-class)' card passed (parser blind to the real format)"; st=1
  else
    echo "OK: claude-code stamped EXPERIMENTAL against its real-format card -> RED"
  fi
  # FACE 3 whole-token tier: "floor-verified" must not satisfy a "verified" card (review M2).
  mk_clean "$base/substring"
  printf "'claude-code' is FLOOR-VERIFIED here.\n" >> "$base/substring/scripts/incept.sh"
  if scan "$base/substring" >/dev/null 2>&1; then
    echo "FAIL: selftest — 'floor-verified' satisfied a 'verified' card by substring"; st=1
  else
    echo "OK: substring tier ('floor-verified' vs 'verified') -> RED"
  fi
  # FACE 3 precision: the VERIFICATION sense of "verified" naming a harness is not a tier claim (review M3).
  mk_clean "$base/othersense"
  printf 'Harness: [codex] — each is **verified** against the boundary contract at Inception (verified by `conformance/harness-boundary.sh`).\n' \
    >> "$base/othersense/templates/PROJECT-CLAUDE-TEMPLATE.md"
  if scan "$base/othersense" >/dev/null 2>&1; then
    echo "OK: 'verified against …' naming a harness (verification sense) -> GREEN"
  else
    echo "FAIL: selftest — face 3 reddened the verification sense of 'verified' (false-RED on template prose)"; st=1
  fi
  # FACE 3 (round 2, M1): a stale claim PLUS a "verified by <script>" citation on the same line -> RED.
  mk_clean "$base/mixedline"
  printf "'codex' is EXPERIMENTAL (verified by conformance/harness-boundary.sh).\n" >> "$base/mixedline/MATURITY.md"
  if scan "$base/mixedline" >/dev/null 2>&1; then
    echo "FAIL: selftest — a 'verified by' citation disarmed a stale tier claim on the same line"; st=1
  else
    echo "OK: stale claim + 'verified by' citation on one line -> RED"
  fi
  # FACE 3 (round 2, M2): MATURITY.md's real shape — the right tier ALSO appears later on the line -> still RED.
  mk_clean "$base/doubletoken"
  printf '**`codex` is experimental** — the floor exercised cold. Floor-verified is `codex`'"'"'s honest maximum.\n' >> "$base/doubletoken/MATURITY.md"
  if scan "$base/doubletoken" >/dev/null 2>&1; then
    echo "FAIL: selftest — a demoted claim passed because the card tier appeared elsewhere on the line"; st=1
  else
    echo "OK: demoted claim with the card tier elsewhere on the line -> RED (tier judged adjacent to the claim)"
  fi
  # FACE 3 (round 3, M1): the preposition exemption belongs to bare "verified" only -> "experimental in …" RED.
  mk_clean "$base/expin"
  printf 'The kit'"'"'s `codex` adapter is experimental in the current release.\n' >> "$base/expin/MATURITY.md"
  if scan "$base/expin" >/dev/null 2>&1; then
    echo "FAIL: selftest — 'is experimental in …' escaped via the verification-preposition exemption"; st=1
  else
    echo "OK: 'is experimental in …' -> RED (exemption is for bare 'verified' only)"
  fi
  # FACE 3 (round 3, M2): two claims on one line, stale first -> RED (every claim judged, first tier after the verb).
  mk_clean "$base/twoclaims"
  printf '`codex` is experimental and `codex` is floor-verified.\n' >> "$base/twoclaims/MATURITY.md"
  if scan "$base/twoclaims" >/dev/null 2>&1; then
    echo "FAIL: selftest — a stale claim survived because a true claim followed it on the line"; st=1
  else
    echo "OK: stale claim followed by a true claim on one line -> RED"
  fi
  # FACE 3 (round 4, M1): a verification-sense verb must not MASK a stale claim later in the clause -> RED.
  mk_clean "$base/maskedclaim"
  printf '`codex`, which is verified by CP-7, is experimental today.\n' >> "$base/maskedclaim/MATURITY.md"
  if scan "$base/maskedclaim" >/dev/null 2>&1; then
    echo "FAIL: selftest — a 'verified by' verb masked a stale claim later in the same clause"; st=1
  else
    echo "OK: stale claim after a verification-sense verb in the same clause -> RED"
  fi
  # FACE 3 (round 4, m1): a comparative names another harness first; the claim belongs to the nearer one -> GREEN.
  mk_clean "$base/comparative"
  printf 'Unlike `codex`, the `gemini` adapter is experimental.\n' >> "$base/comparative/MATURITY.md"
  if scan "$base/comparative" >/dev/null 2>&1; then
    echo "OK: comparative sentence attributes the claim to the nearer harness -> GREEN"
  else
    echo "FAIL: selftest — a comparative sentence was attributed to the wrong harness (false-RED)"; st=1
  fi
  # FACE 3 (round 3, m1/m2): bold on the preposition, and "this" is not "is" -> GREEN.
  mk_clean "$base/boldprep"
  printf '`codex` is verified **by** the CP-7 field test. codex: this experimental note is prose.\n' >> "$base/boldprep/MATURITY.md"
  if scan "$base/boldprep" >/dev/null 2>&1; then
    echo "OK: bold preposition + 'this' inside a word -> GREEN"
  else
    echo "FAIL: selftest — markdown emphasis or an unanchored verb produced a false-RED"; st=1
  fi
  # FACE 3 (round 2, m1): sibling verification phrasings are not tier claims -> GREEN.
  mk_clean "$base/prepclass"
  printf 'The codex floor is verified in a cold field test; each adapter is verified via the boundary contract.\n' >> "$base/prepclass/MATURITY.md"
  if scan "$base/prepclass" >/dev/null 2>&1; then
    echo "OK: 'verified in/via …' naming a harness -> GREEN"
  else
    echo "FAIL: selftest — face 3 reddened a verification-sense sibling phrasing"; st=1
  fi
  # FACE 3 (round 2, m2): a non-card lowercase h4 in the cards doc does not break heading parity -> GREEN.
  mk_clean "$base/extraheading"
  printf '#### fit-rubric\n- choose by fit, then disclose maturity.\n' >> "$base/extraheading/$HARNESS_CARDS_DOC"
  if scan "$base/extraheading" >/dev/null 2>&1; then
    echo "OK: a non-card h4 in the cards doc -> GREEN (parity counts cards, not headings)"
  else
    echo "FAIL: selftest — a non-card heading tripped the headings==tiers parity leg"; st=1
  fi
  # FACE 3 partial parse loss: a card heading whose tier line the parser cannot read -> FAIL (review B1).
  mk_clean "$base/partialcards"
  printf '#### cursor\n- Maturity tier: experimental (unbolded — unreadable).\n' >> "$base/partialcards/$HARNESS_CARDS_DOC"
  if scan "$base/partialcards" >/dev/null 2>&1; then
    echo "FAIL: selftest — a card heading with no parseable tier passed (partial parse loss = silent blindness)"; st=1
  else
    echo "OK: card heading without a parseable tier -> FAIL (no partial vacuity)"
  fi
  # FACE 3 anti-vacuity: no parseable cards -> FAIL, never green.
  mk_clean "$base/nocards"
  printf '# governing doc\n' > "$base/nocards/$HARNESS_CARDS_DOC"
  if scan "$base/nocards" >/dev/null 2>&1; then
    echo "FAIL: selftest — zero maturity cards passed (face 3 vacuous)"; st=1
  else
    echo "OK: no maturity cards -> FAIL (no vacuous green)"
  fi
  # FACE 3: a missing stamp member is a FAIL, not a silent skip.
  mk_clean "$base/nostamp"
  rm -f "$base/nostamp/scripts/incept.sh"
  if scan "$base/nostamp" >/dev/null 2>&1; then
    echo "FAIL: selftest — a MISSING stamp member passed (silent-skip vacuity)"; st=1
  else
    echo "OK: missing stamp member -> FAIL (no silent skip)"
  fi

  # ANTI-VACUITY: an empty tree resolves ZERO governing docs -> must FAIL, never green.
  mkdir -p "$base/empty"
  if scan "$base/empty" >/dev/null 2>&1; then
    echo "FAIL: selftest — an EMPTY governing set passed (vacuous green)"; st=1
  else
    echo "OK: empty governing set -> FAIL (no vacuous green)"
  fi

  if [ "$st" = 0 ]; then echo "governing-docs-current --selftest: OK (fixtures in $base)"; else echo "governing-docs-current --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '') scan "." ;;
  *) echo "usage: governing-docs-current.sh [--selftest]" >&2; exit 2 ;;
esac
