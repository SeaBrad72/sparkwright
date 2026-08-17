#!/bin/sh
# citation-history.sh — a SUPERSEDED citation value is DE-LINED, never quoted. The living-document
# lint for the meaning-drift face of citation decay (row CITATION-LIVE-MEANING-AND-HISTORY-FACES,
# ruling D-240815-2d, route (b)).
#
# WHY THIS EXISTS: `conformance/citation-live.sh` grades whether a cited line still EXISTS. It cannot
# see the other half — a citation whose line still resolves but no longer MEANS what its author said.
# The kit measured that face on itself twice. At C11 a board note carrying quoted historical line
# values ("the old value, now the new value") was re-measured: every quoted number resolved to a live
# but unrelated line, because the files had grown past them. Detection of meaning-drift is WON'T-FIX
# by ruling (~50% false positives on every grammar tried). The cure is upstream and cheap: when a
# value is superseded, DELETE the value and name the row, heading or symbol instead. This check is
# that doctrine's lint — it reds the one WRITING SHAPE that carries a dead value forward.
#
# ── HONEST CEILING, STATED FIRST (it is the whole shape of this check) ──────────────────────────────
# THIS IS AN ENUMERATION, NOT A DETECTOR. It reds exactly ONE measured byte sequence: a closing
# backtick, U+2192 (the rightwards arrow), an opening backtick, and a colon — the "old`->`:new" pair
# an author writes when they truth-fix a line number in place. Measured over the whole tracked
# Markdown corpus at the 2026-08-15 probe: 2 SITES (5 occurrences), one living and one dated. The
# unit of the census is the SITE (a file and a line), never the occurrence.
#   NEAR-NEIGHBOUR SPELLINGS THAT ESCAPE IT, named rather than implied:
#     · the FULL-SECOND-PATH pair (`a.sh:10` then the arrow then `a.sh:20` written out in full) —
#       the arrow is not followed by a bare `:` , so the sequence does not occur. It escapes.
#     · the SPACED arrow (a space either side) — same reason. It escapes.
#     · past-tense prose ("`a.sh:10` stated X") — NOT red: it rides the REPORT-ONLY detector below,
#       whose false-positive rate was measured at roughly one in two. It is counted and named on
#       every run, and it never decides the exit code.
#   Naive arrow-adjacency (any citation next to any arrow) was measured at ~50% FP and is REJECTED.
#   So: a green here means "the one measured shape does not occur in a living document", never "no
#   quoted history remains". Do not quote this green as more than it is.
#
# ── DOMAIN, AND THE DATED SPLIT (a PINNED COPY, not a shared helper) ────────────────────────────────
# SOURCES = tracked `*.md` files. LIVING documents are graded; the DATED record is EXEMPT-and-COUNTED
# (docs/architecture/20*, docs/plans/20*, docs/plans/brief-*, CHANGELOG.md, the meta-control log, and
# both dated BASENAME shapes). A dated document is an IMMUTABLE RECORD: it is *supposed* to say what
# was true on its date, so a supersession pair there is the record doing its job.
# ⚠️ THE PREDICATE IS COPIED FROM conformance/citation-live.sh's `is_dated()`, DELIBERATELY AND NOT
# SHARED. Extracting a helper would mean editing that check's own awk program, and this slice's
# binding constraint is ZERO logic change there (its mode-purity property). A copy that can silently
# drift is worse than no copy, so it is pinned three ways: this pointer, the matching pointer in
# citation-live.sh's own DOMAIN section, and a --selftest DRIFT leg that builds ONE fixture carrying
# EVERY dated pattern and runs BOTH checks over it — if either predicate moves, that leg reds.
# EXEMPTIONS ARE NEVER SILENT: their counts print on EVERY run, pass or fail.
#
# ── THE REPORT-ONLY FACE (counted, never red) ───────────────────────────────────────────────────────
# A backticked `path.ext:LINE` citation immediately followed by a past-tense verb (said / stated /
# read / carried / claimed / reported / declared / was / were / had) is the OTHER shape a superseded
# value takes. Its measured false-positive rate is about one in two — a living document may perfectly
# legitimately narrate what a still-current line says. So the count is PRINTED on every run and the
# sites are named, and it never moves the exit code. Escalating it would need a grammar nobody has.
#
# ── ARMING (fail-closed; the C3/C5/C7/C9/C10/C11 kit-marker pattern) ────────────────────────────────
# On a KIT tree (either export-ignored marker docs/ROADMAP-KIT.md or .github/workflows/golden-path.yml
# present) a living supersession pair is a FAIL, and a corpus that cannot be enumerated is ALSO a FAIL
# — never an N/A: a check that stands down when its own input vanishes is the concealment class the
# arming block exists to close. With NEITHER marker present (an adopter tree) the check renders an
# honest line-anchored `N/A:` and exits 0, UNCONDITIONALLY. That is deliberate and it is a CEILING,
# not laxity: de-lining is the kit's own writing convention, shipped as prose in
# DEVELOPMENT-STANDARDS.md ("Citation discipline"), and holding an adopter's own documents to a kit
# lint they never opted into would red a first run for a rule they had just received. The adopter
# face of citation discipline is the doctrine, not this gate.
#   ⚠️ CIRCULARITY, DISCLOSED (inherited from the shared marker pattern, not introduced here):
#   docs/ROADMAP-KIT.md is one of the two arming tokens. Deleting it does not red this check — it
#   DISARMS it, along with every other check on the same pair. The second token is why one deletion
#   is not enough.
#
# WIRED (pair pointers): conformance/verify.sh `check control citation-history` (which also enrols
# this file in non-vacuity.sh's mutation sweep) · .github/workflows/ci.yml `docs-links` (the LIVE
# step, a required job with no `if:` so it survives the docs_only skip — a writing-convention lint
# governs exactly the `.md`-only PRs on which cf-verify-enforced is measured DEAD) · ci.yml
# `conformance-selftests` (--selftest).
# Usage: sh conformance/citation-history.sh [--selftest]   (run from the repo root; argv only — this
#        check reads no environment dial and no stdin)
# Exit: 0 = no living supersession pair (or N/A off the kit tree) · 1 = a living pair / an
#       unreadable or unenumerable corpus on an armed tree · 2 = bad usage. POSIX sh + one awk pass.
set -eu

SELFTEST=no
case "${1:-}" in
  "") : ;;
  --selftest) SELFTEST=yes ;;
  *) echo "usage: citation-history.sh [--selftest]" >&2; exit 2 ;;
esac

# THE PINNED SEQUENCE, built from bytes rather than typed, so no editor can normalise it away:
# backtick, U+2192 (0342 0206 0222), backtick, colon.
PAIR=$(printf '`\342\206\222`:')

# ── THE SINGLE AWK PASS ─────────────────────────────────────────────────────────────────────────────
# One process for the whole corpus (the citation-live idiom, and its measured reason: a subprocess per
# candidate was 23x slower there). ARGV[1] is the `*.md` listing; every source is read with getline.
ch_awk() {  # <md-listing> <pair>
  LC_ALL=C awk -v pair="$2" '
    BEGIN { sep = "·" }
    # DATED = the immutable record. COPIED VERBATIM from conformance/citation-live.sh is_dated();
    # see this file header for why it is a copy and how the copy is pinned.
    function is_dated(p,   s, n, b) {
      n = split(p, s, "/"); b = s[n]
      if (p ~ /^docs\/architecture\/20/) return 1
      if (p ~ /^docs\/plans\/20/) return 1
      if (p ~ /^docs\/plans\/brief-/) return 1
      if (b == "CHANGELOG.md") return 1
      if (b == "meta-control-log.md") return 1
      if (b ~ /^20[0-9][0-9]-.*\.md$/) return 1
      if (b ~ /^brief-.*\.md$/) return 1
      return 0
    }
    # THE REPORT-ONLY FACE. A backticked citation whose very next words are past tense. Roughly one
    # in two of these is a legitimate narration of a live line, which is exactly why it is counted
    # and never graded. One hit is enough to count the SITE.
    function past_hit(line,   s, m, tail) {
      s = line
      while (match(s, /`[^`]+`/)) {
        m = substr(s, RSTART + 1, RLENGTH - 2)
        tail = substr(s, RSTART + RLENGTH, 24)
        if (m ~ /\.[A-Za-z][A-Za-z0-9]*:[0-9]+/ &&
            tail ~ /^[ ,;:]*(said|stated|read|carried|claimed|reported|declared|was|were|had)([^A-Za-z]|$)/) return 1
        s = substr(s, RSTART + RLENGTH)
      }
      return 0
    }
    {
      f = $0; nsrc++
      dated = is_dated(f)
      if (dated) ndated++; else nliving++
      lno = 0
      while (1) {
        r = (getline ln < f)
        if (r <= 0) break
        lno = lno + 1
        n = 0; s = ln
        while ((ix = index(s, pair)) > 0) { n = n + 1; s = substr(s, ix + length(pair)) }
        if (n > 0) {
          if (dated) { exsite++; exhit = exhit + n }
          else {
            red++; redhit = redhit + n
            print "SUPERSEDED-CITATION  " f ":" lno " carries " n " quoted-supersession pair(s) -- a superseded line value is quoted beside its replacement, and a quoted value goes stale in silence. DE-LINE it: delete the numbers and name the row, heading or symbol (DEVELOPMENT-STANDARDS.md, Citation discipline)."
          }
        }
        if (!dated && past_hit(ln)) {
          past++
          print "REPORT-ONLY  " f ":" lno " quotes a citation in the PAST TENSE -- roughly one in two of these is a legitimate narration of a live line, so this is COUNTED, never graded. Read it once; de-line it if the value really is superseded."
        }
      }
      close(f)
      # NAME THE FILE, never just a count (the citation-live MED-3 lesson): an operator handed
      # "1 file could not be read" has to go and find it.
      if (r < 0) { readerr++; badread = badread " " f }
    }
    END {
      bad=0
      if (readerr > 0) {
        print "citation-history: FAIL -- " readerr " file(s) in the corpus could not be read, so the judgement would be over an unknown subset (" nliving " living/" ndated " dated .md file(s) reached). Unreadable:" badread
        bad=1
        exit bad
      }
      if (red > 0) bad=1
      res = (bad == 0) ? "OK" : "FAIL"
      printf "citation-history: %s -- %d SUPERSEDED-CITATION site(s) (%d occurrence(s)) %s %d EXEMPT-dated site(s) (%d occurrence(s)) %s %d report-only past-tense site(s) %s %d living/%d dated .md file(s) scanned\n", \
        res, red, redhit, sep, exsite, exhit, sep, past, sep, nliving, ndated
      exit bad
    }
  ' "$1"
}

run() {
  _armed=0
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then _armed=1; fi

  # ── THE ADOPTER FACE, and it is unconditional. See the arming note in the header.
  if [ "$_armed" -eq 0 ]; then
    echo "N/A: citation-history -- no kit marker present (an adopter tree), and de-lining is the kit's own writing convention rather than an adopter obligation (0 file(s) scanned, 0 site(s) graded). The doctrine ships as prose in DEVELOPMENT-STANDARDS.md; this lint is kit-self. There is nothing to grade and no remedy to offer; this is not a pass."
    return 0
  fi

  _w=$(mktemp -d) || { echo "citation-history: FAIL -- could not create a work directory"; return 1; }
  # Unconditional cleanup that PRESERVES the rc: a swallowed failure here would be the same
  # silent-disarm class the arming block exists to close.
  trap 'rm -rf "$_w"' EXIT INT TERM

  _enum=1
  # `-c core.quotePath=false` IS LOAD-BEARING, not tidiness (the citation-live HIGH-2 lesson): under
  # git's default a non-ASCII tracked path is emitted C-QUOTED and awk's getline cannot open that
  # literal, turning ONE accented filename into "the corpus could not be read" for the whole tree.
  git -c core.quotePath=false ls-files -- "*.md" > "$_w/md" 2>/dev/null || _enum=0
  [ -s "$_w/md" ] || _enum=0
  if [ "$_enum" = 0 ]; then
    echo "citation-history: FAIL -- the Markdown corpus could not be enumerated (git ls-files failed or returned nothing) on a KIT-MARKED tree (0 living/0 dated .md file(s) scanned). This is a FAILURE, never an N/A: a check that quietly stands down when its own input is missing is the concealment class the arming block exists to close."
    return 1
  fi

  _rc=0
  ch_awk "$_w/md" "$PAIR" || _rc=$?
  return "$_rc"
}

# ---------------------------------------------------------------------------- selftest
# Every leg asserts the VERDICT CLASS WORD (SUPERSEDED-CITATION / EXEMPT / REPORT-ONLY / N/A), not
# just an rc, so a branch-collapse mutant cannot cross-pass a leg. The LIVING-RED fixture is CUT FROM
# THE REAL SITE (BACKLOG.md's B7 truth-fix parenthetical) before that row was repaired — a synthetic
# fixture would only prove the check catches what its author imagined. Fixtures are throwaway
# `git init` trees, no commit, so no ambient git identity and no ambient repo state is read.
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  _sib=$(CDPATH='' cd "$(dirname "$0")" && pwd)/citation-live.sh
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  # ── THE LIVING RED, CUT FROM THE REAL SITE. Verbatim from BACKLOG.md's KIT-META-CI row as it stood
  # at this slice's design commit: three supersession pairs on ONE line, i.e. one SITE.
  ch_init "$W/red"
  ch_put "$W/red" "BACKLOG.md" 'row text *(Citations truth-fixed by B7, 2026-08-08: `verify.sh:313`\342\206\222`:335`; `ci.yml:1077`\342\206\222`:1267`; `ci-gates.sh:331`\342\206\222`:746`, all re-verified true pre-fix.)* more row text\n'
  ch_add "$W/red"
  ch_expect "the REAL living site (cut from BACKLOG.md pre-repair) FAILS" 1 "$W/red"
  ch_says  "and is classed SUPERSEDED-CITATION at its exact site" "SUPERSEDED-CITATION  BACKLOG.md:1" "$W/red"
  ch_says  "and the OCCURRENCES on that one site are counted" "carries 3 quoted-supersession pair(s)" "$W/red"
  ch_says  "and the census unit is the SITE, not the occurrence" "1 SUPERSEDED-CITATION site(s) (3 occurrence(s))" "$W/red"
  ch_says  "and the remedy names the doctrine, not just the defect" "DE-LINE it" "$W/red"

  # ── THE DE-LINED CURE GREENS. The same sentence, values deleted and the row named instead: the
  # fixture pair is what makes the red actionable rather than merely loud.
  ch_init "$W/cured"
  ch_put "$W/cured" "BACKLOG.md" 'row text *(Citations truth-fixed by B7, 2026-08-08; the superseded line values are de-lined — see the `CI-GATE-CONTRACT` row.)* more row text\n'
  ch_add "$W/cured"
  ch_expect "the DE-LINED form of the same sentence passes" 0 "$W/cured"
  ch_says  "and the census reads zero" "0 SUPERSEDED-CITATION site(s) (0 occurrence(s))" "$W/cured"

  # ── DATED SOURCE -> EXEMPT, COUNTED. The dated record is SUPPOSED to say what was true on its date;
  # grading it would red an immutable document for doing its job.
  ch_init "$W/dated"
  ch_put "$W/dated" "docs/architecture/2026-01-02-old.md" 'it truth-fixed `verify.sh:313`\342\206\222`:335` back then\n'
  ch_put "$W/dated" "docs/a.md" 'a living document with nothing to fix\n'
  ch_add "$W/dated"
  ch_expect "a DATED source carrying the pair does not fail the tree" 0 "$W/dated"
  ch_says  "and its exemption is REPORTED with an exact count" "1 EXEMPT-dated site(s) (1 occurrence(s))" "$W/dated"
  ch_denies "and it is never reported as a defect" "SUPERSEDED-CITATION  docs/architecture" "$W/dated"

  # ── THE REPORT-ONLY FACE, BOTH WAYS. A past-tense citation is COUNTED and NAMED, and the tree stays
  # green: at ~50% FP a red here would train the team to ignore the check.
  ch_init "$W/past"
  ch_put "$W/past" "docs/a.md" 'the note says `DEVELOPMENT-STANDARDS.md:252` stated the pipeline is verified elsewhere\n'
  ch_add "$W/past"
  ch_expect "a PAST-TENSE quoted citation does NOT fail the tree" 0 "$W/past"
  ch_says  "but it is counted" "1 report-only past-tense site(s)" "$W/past"
  ch_says  "and named at its site" "REPORT-ONLY  docs/a.md:1" "$W/past"
  ch_says  "and the disclosure states its own false-positive rate" "one in two" "$W/past"

  ch_init "$W/present"
  ch_put "$W/present" "docs/a.md" 'the note says `DEVELOPMENT-STANDARDS.md:252` registers the pipeline check\n'
  ch_add "$W/present"
  ch_expect "a PRESENT-TENSE citation is not even reported" 0 "$W/present"
  ch_says  "and the report-only counter stays at zero" "0 report-only past-tense site(s)" "$W/present"
  ch_denies "and no report-only line is emitted" "REPORT-ONLY" "$W/present"

  # ── THE CLEAN CORPUS, WITH FIGURES. A green must print what it looked at, or it is a green over an
  # unknown denominator.
  ch_init "$W/clean"
  ch_put "$W/clean" "docs/a.md" 'a living document citing the `CITATION-LIVE` row by name\n'
  ch_put "$W/clean" "CHANGELOG.md" 'dated record\n'
  ch_add "$W/clean"
  ch_expect "a clean corpus passes" 0 "$W/clean"
  # 2 living = docs/a.md + the fixture's own docs/ROADMAP-KIT.md arming marker, which is a tracked
  # `*.md` file like any other and is scanned as one; 1 dated = CHANGELOG.md.
  ch_says  "and the scanned corpus is printed, living and dated" "2 living/1 dated .md file(s) scanned" "$W/clean"

  # ── ARMED + A DEAD CORPUS ENUMERATION -> FAIL, never N/A. The `.git` gitfile points nowhere, so
  # `git ls-files` fails no matter what encloses the fixture.
  ch_init "$W/broken"
  ch_put "$W/broken" "docs/a.md" 'anything\n'
  rm -rf "$W/broken/.git"
  ch_put "$W/broken" ".git" 'gitdir: /nonexistent-citation-history-fixture\n'
  ch_expect "a KIT-MARKED tree whose corpus enumeration FAILS is a FAIL, not an N/A" 1 "$W/broken"
  ch_says  "and says so in the concealment-class language" "never an N/A" "$W/broken"

  # ── UNARMED -> N/A, UNCONDITIONALLY — even over a corpus that WOULD red. The adopter face is the
  # ceiling this check declares in its header, and this leg is what holds it honest.
  ch_bare "$W/na"
  ch_put "$W/na" "BACKLOG.md" 'row text `verify.sh:313`\342\206\222`:335` more row text\n'
  ch_add "$W/na"
  ch_expect "an adopter tree carrying the pair renders N/A (rc 0)" 0 "$W/na"
  ch_says  "and says N/A in the line-anchored idiom" "N/A: citation-history" "$W/na"
  ch_says  "and gives the honest reason" "the kit's own writing convention" "$W/na"
  ch_denies "and never renders a defect line at an adopter" "SUPERSEDED-CITATION  BACKLOG.md" "$W/na"

  # ── THE SECOND ARMING TOKEN holds the tree on its own. A single deletion must not disarm.
  ch_bare "$W/token2"
  mkdir -p "$W/token2/.github/workflows"
  printf 'name: golden-path\n' > "$W/token2/.github/workflows/golden-path.yml"
  ch_put "$W/token2" "BACKLOG.md" 'row text `verify.sh:313`\342\206\222`:335` more row text\n'
  ch_add "$W/token2"
  ch_expect "the golden-path.yml marker ALONE still arms the check (no ROADMAP-KIT.md)" 1 "$W/token2"

  # The predicate below is COPIED VERBATIM from verify.sh's is_self_skip (C6). If that idiom ever
  # changes, this leg is what tells us this check silently started rendering PASS instead of N-A.
  _o=$(ch_out "$W/na") || :
  if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
     ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
    echo "PASS: selftest -- the N/A output renders N-A under verify.sh's C6 classifier (never PASS)"
  else
    echo "FAIL: selftest -- the N/A output does NOT satisfy verify.sh's is_self_skip predicate"
    printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
  fi

  # ── THE DRIFT LEG (design vet C1). ONE fixture carrying EVERY dated pattern the copied predicate
  # knows, graded by BOTH checks — with an ISOLATING fixture per clause, so each clause can fail
  # alone. If either predicate is edited without the other, one of the assertions below goes red —
  # which is the whole reason the copy is allowed to exist.
  ch_init "$W/drift"
  ch_put "$W/drift" "docs/target.md" 'one\ntwo\n'
  ch_put "$W/drift" "docs/a.md" 'a living document citing `docs/target.md:1` live\n'
  # Reviewer I-1: the three path-rule fixtures each ALSO matched a basename rule, so deleting a
  # path clause from either predicate left the leg green — the swallowing class (a fixture that
  # satisfies a clause for two reasons proves neither). The three ISOLATING paths below match
  # their path clause and NO basename clause, so every one of the seven clauses now has a
  # fixture only it can exempt.
  for _p in "docs/architecture/2026-01-02-a.md" "docs/plans/2026-01-02-b.md" \
            "docs/plans/brief-c.md" "CHANGELOG.md" "docs/governance/meta-control-log.md" \
            "notes/2026-05-05-loose.md" "notes/brief-loose.md" \
            "docs/architecture/20-note.md" "docs/plans/20-note.md" "docs/plans/brief-x/y.md"; do
    ch_put "$W/drift" "$_p" 'was `docs/target.md:900`\342\206\222`:9` once\n'
  done
  ch_add "$W/drift"
  ch_expect "drift: every dated pattern is exempt here" 0 "$W/drift"
  ch_says  "drift: all dated patterns are counted exempt" "10 EXEMPT-dated site(s)" "$W/drift"
  ch_says  "drift: the dated ten are the whole dated corpus" "3 living/10 dated .md file(s) scanned" "$W/drift"
  if [ -f "$_sib" ]; then
    _drc=0; _do=$( cd "$W/drift" && sh "$_sib" 2>&1 ) || _drc=$?
    if [ "$_drc" = 0 ] && printf '%s\n' "$_do" | grep -qF -- "(sources 10/targets 0)"; then
      echo "PASS: selftest -- drift: citation-live's OWN is_dated() exempts the same ten fixtures"
    else
      echo "FAIL: selftest -- drift: the two dated predicates DISAGREE (citation-live rc $_drc)"
      printf '%s\n' "$_do" | sed 's/^/    /'; sfail=1
    fi
  else
    echo "FAIL: selftest -- drift: conformance/citation-live.sh is absent, so the pinned copy is unpinned"
    sfail=1
  fi

  if [ "$sfail" = 0 ]; then echo "OK: citation-history selftest (every verdict class asserted by name; the living RED is the real site)"; exit 0; fi
  echo "FAIL: citation-history selftest"; exit 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker, so fixture builders and kill logic sit in the protected oracle region) ---
ch_init() {  # <dir> — a fresh, ARMED fixture repo (kit marker present); never a clone of this tree
  rm -rf "$1"; mkdir -p "$1/docs"
  printf 'kit marker\n' > "$1/docs/ROADMAP-KIT.md"
  ( cd "$1" && git init -q . >/dev/null 2>&1 )
}
ch_bare() {  # <dir> — a fresh fixture repo with NO kit marker (an adopter-shaped tree)
  rm -rf "$1"; mkdir -p "$1"
  ( cd "$1" && git init -q . >/dev/null 2>&1 )
}
ch_put() {   # <dir> <relpath> <content with \n and \NNN escapes>
  mkdir -p "$(dirname "$1/$2")"
  printf '%b' "$3" > "$1/$2"
}
ch_add() { ( cd "$1" && git add -A . >/dev/null 2>&1 ); }
ch_out() { ( cd "$1" && sh "$_self" 2>&1 ); }
ch_expect() {  # <label> <want-rc> <dir>
  _rc=0; _o=$(ch_out "$3") || _rc=$?
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest -- $1"
  else echo "FAIL: selftest -- $1 (want rc $2, got $_rc)"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
}
ch_says() {  # <label> <needle> <dir>
  _o=$(ch_out "$3") || :
  if printf '%s\n' "$_o" | grep -qF -- "$2"; then echo "PASS: selftest -- $1"
  else echo "FAIL: selftest -- $1 (missing '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
}
ch_denies() {  # <label> <needle> <dir>
  _o=$(ch_out "$3") || :
  if printf '%s\n' "$_o" | grep -qF -- "$2"; then
    echo "FAIL: selftest -- $1 (unexpected '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
  else echo "PASS: selftest -- $1"; fi
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
run; exit $?
