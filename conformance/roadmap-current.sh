#!/bin/sh
# roadmap-current.sh — a ROADMAP.md item still marked PENDING must not already be sitting in
# BACKLOG.md's `## Done` section. C10 ROADMAP-STALE-RECONCILE.
#
# WHY THIS EXISTS: measured at the C10 probe, the kit's own front-door roadmap reported SEVEN
# shipped-and-tagged items as work still to do — F.2, F.3, P1.2, P1.3, P1.4, P1.5 and P1.6 all
# carried a pending glyph while the board carried a Done row for each. Three artifacts in this tree
# each claim to be the current roadmap and none was; the honesty failure is the kit's own front door,
# which is why the row was reclassified charter-core. C10 reconciled the markers by hand. THIS CHECK
# IS THE RATCHET that keeps them reconciled: it does not prove the reconciliation happened (the
# slice's own diff is that proof), it proves the count stays at zero.
#
# ── HONEST CEILING, STATED FIRST ────────────────────────────────────────────────────────────────────
# THE CHECK'S DOMAIN IS THE ID-JOIN, AND ONLY THE ID-JOIN.
#   · RENAME LAUNDERING IS NOT CAUGHT (the presence-check-cannot-see-substitution class). A stale
#     marker is launderable by renaming the roadmap's cell-1 id, or by rewording the Done row's cell 1:
#     the join breaks, the red goes green, and the DENOMINATOR does not catch it either, because M is
#     glyph-derived, not id-derived. Accepted WITH DISCLOSURE — the owner-reviewed diff is the control,
#     and a pinned id set would fight the denominator. A `renamed-id -> GREEN` selftest leg documents
#     this ceiling honestly rather than pretending it away.
#   · UNALIASED AND ALIAS-TRACKED WORK ARE NAMED FALSE-NEGATIVE CLASSES. Measured on the kit tree:
#     F.1 (a repo-admin act that never had a board row), P1.7 (tracked as the CP-8 family), P1.8
#     (tracked as P0-FU; the Done rows name it only as `P1.8b`, which the token bound correctly
#     REJECTS, and the board's one genuinely token-bounded `P1.8` hit — `P1.8-sibling`, where the
#     hyphen IS a boundary — sits in a RETRO COLUMN, so it is the CELL-1 bound, not the token bound,
#     that keeps it from joining) and ALL of Phase 2 (tracked as CP-6/CP-9/CP-11/KW6-A2-f5) carry no
#     cell-1 id hit. An id-join check cannot red them; it holds the ids it can join, and says so.
#   · THE MARKER CELL IS IDENTIFIED POSITIONALLY, NOT BY HEADER NAME. It is "the last cell, ignoring
#     one optional trailing empty field" — never the column titled `Effort` / `Maturity → target`,
#     because those three tables spell that header three different ways. So INSERTING A NEW TRAILING
#     COLUMN silently moves what this check reads: if the new last cell carries no legend glyph the
#     row leaves M entirely (a quiet denominator shrink), and if it carries one, that column is graded
#     instead of the real marker. Accepted with disclosure for the same reason as the rename ceiling —
#     the owner-reviewed diff is the control, and a header-name rule would be MORE brittle across the
#     three spellings, not less. Measured today: all 18 gradeable rows are 3-column with the glyph in
#     cell 3 and only cell 3. Any future column addition to ROADMAP.md must re-read this note.
#   · A GREEN MEANS "no pending-marked item joins a Done row TODAY". It never means the roadmap is
#     true. Do not quote this green as more than it is.
#
# ── GRAMMAR (pinned, and measured against the real file) ────────────────────────────────────────────
# ITEM ROW = a line beginning `| **`. THE MARKER CELL = the row's LAST cell, ignoring one optional
# trailing empty field (`| a | b | c |` -> cell 3). A row is MARKED when its marker cell contains ANY
# legend glyph (✅ 🔨 🔧 🔍 🧑) — that set is the DENOMINATOR M, so a legitimately all-✅ roadmap
# scores `0 stale of M` GREEN while a marker-stripped stub trips the zero-gradeable FAIL below.
# A row is PENDING when its marker cell contains any of 🔨 🔧 🔍 🧑. MIXED CELLS ARE PENDING BY RULE:
# `✅ core + 🔧` is NOT done, and because the rule is "any pending glyph" that needs no special branch —
# it falls out, and a fixture locks it.
#   The LEGEND line is excluded by the row grammar (it is not a table row). Phase 3's marker-less
#   two-column rows are excluded by the glyph requirement — measured: all 18 gradeable rows carry a
#   glyph in cell 3 and ONLY in cell 3, and all 5 Phase-3 rows carry none anywhere.
#   RESIDUAL, disclosed: a two-column row that ever gained a legend glyph in its prose cell WOULD be
#   graded. It would be graded as PENDING and could then only RED by also joining a Done row — an
#   over-match toward RED, the safe direction. A Phase-3-shaped fixture leg pins today's behaviour.
#
# ── BYTE-SAFE GLYPH MATCHING (this is load-bearing, not tidiness) ───────────────────────────────────
# `LC_ALL=C` (the citation-live precedent) with a PER-GLYPH `index()` against an OCTAL-ESCAPED literal.
# NEVER a bracket expression: under LC_ALL=C a `[🔨🔧🔍🧑]` class degenerates into the SET OF BYTES those
# glyphs are built from, and 🔨 (F0 9F 94 A8), 🔧 (F0 9F 94 A7) and 🔍 (F0 9F 94 8D) share a three-byte
# lead — so ANY unrelated emoji would classify as pending. The decoy fixture below uses 🔪 (F0 9F 94 AA),
# which shares that exact lead byte sequence and is NOT a legend glyph; a bracket-expression mutant
# reds that leg. The escapes are octal so an encoding-unaware edit cannot silently mangle the program.
#
# ── THE JOIN (bounded on BOTH sides; the entire correctness story) ──────────────────────────────────
# The roadmap's cell-1 id is matched against the cell 1 of BACKLOG.md's `## Done` rows ONLY.
#   · SECTION-BOUNDED: `## Done` to the NEXT line matching `^## `. Pinned against the real file — it
#     is followed by `## Blocked`, and the board carries ZERO `###` subheads anywhere, so `^## ` (two
#     hashes then a space) cannot be tripped by a deeper heading.
#   · CELL-1-BOUNDED: whole-row matching over-fires badly — measured, P1.6 shows FIVE whole-row hits
#     against ONE real one, because Done retros MENTION roadmap ids in their prose columns. Only the
#     item cell is joined.
#   · TOKEN-BOUNDED: an occurrence counts only when neither neighbouring byte is alphanumeric, so
#     `P1.8` does not match inside `P1.8b`. Backticks and hyphens ARE boundaries, so `` `P1.2` `` and
#     `P1.2-pre-a` both join. MEASURED BOTH WAYS at build time: excluding `.` from the boundary set
#     and allowing it give the IDENTICAL verdict on this tree (7 stale of 18). The looser rule ships
#     because it biases toward RED — a trailing `P1.6.` at the end of a sentence still joins.
#   · JOIN-ANY: one joining Done row is enough; the item is counted ONCE and the FIRST joining row is
#     named. `P1.2` joining four P1.2-family Done rows over-matches toward RED, which is the safe
#     direction and is stated rather than hidden.
#   RESIDUAL, measured and disclosed: cell 1 is itself long prose on modern board rows, so a retro
#   MENTION can live inside it — `satisfied-by-P1.4` really does appear in the B9 row's item cell.
#   That is an over-match toward RED and changes no verdict here (P1.4 has four genuine joins).
#
# ── ARMING (fail-closed; the C3/C5/C7/C9 kit-marker pattern) ────────────────────────────────────────
# On a KIT tree (either export-ignored marker docs/ROADMAP-KIT.md / .github/workflows/golden-path.yml
# present) an unreadable ROADMAP.md, an absent or empty `## Done` section, or ZERO marked items is a
# FAIL: 18 marked items and 151 Done rows exist here, so zero means the parser or the file is dead,
# and a check that quietly stands down when its own input vanishes is the concealment class the arming
# block exists to close. With NEITHER marker present (an adopter tree, where all three files are
# export-ignored and therefore absent) the same conditions render the honest line-anchored `N/A:`.
# An adopter who KEEPS a ROADMAP.md and a BACKLOG.md with a Done section is graded normally.
#   ⚠️ CIRCULARITY, DISCLOSED: docs/ROADMAP-KIT.md is BOTH one of this check's two arming tokens AND a
#   file this slice edits (it carries a dated supersession header) AND the kit-marker for 44 other
#   conformance scripts. Deleting it does not red this check — it DISARMS it, silently, along with the
#   other 44. That is a property of the shared marker pattern, not of this check, and the second token
#   (golden-path.yml) is why a single deletion is not enough to disarm.
#
# WIRED (pair pointers): conformance/verify.sh `check control roadmap-current` (which also enrols this
# file in non-vacuity.sh's mutation sweep) · .github/workflows/ci.yml `docs-links` (the LIVE step, a
# required job with no `if:` so it survives the docs_only skip — a roadmap-honesty check governs
# exactly the `.md`-only PRs on which cf-verify-enforced is measured DEAD) · ci.yml
# `conformance-selftests` (--selftest).
# Usage: sh conformance/roadmap-current.sh [--selftest]   (run from the repo root)
# Exit: 0 = no pending-marked roadmap item joins a Done row (or N/A off the kit tree) · 1 = a stale
#       marker / a dead input on an armed tree · 2 = bad usage. POSIX sh + one awk pass; dash-clean.
set -eu

SELFTEST=no
case "${1:-}" in
  "") : ;;
  --selftest) SELFTEST=yes ;;
  *) echo "usage: roadmap-current.sh [--selftest]" >&2; exit 2 ;;
esac

# ── THE SINGLE AWK PASS ─────────────────────────────────────────────────────────────────────────────
# One process for both files, read with getline in BEGIN (citation-live's idiom) rather than as ARGV
# input files: getline distinguishes "absent" (-1) from "empty" (0), which is exactly the distinction
# the arming block is built on, and a two-file NR==FNR discrimination silently collapses when the
# first file is missing.
rc_awk() {  # <roadmap-path> <backlog-path> <armed 0|1>
  LC_ALL=C awk -v roadmap="$1" -v backlog="$2" -v armed="$3" '
    function bounded(s, id,   pos, off, b, a) {
      off = 0
      while (1) {
        pos = index(substr(s, off + 1), id)
        if (pos == 0) return 0
        pos = pos + off
        b = (pos == 1) ? "" : substr(s, pos - 1, 1)
        a = substr(s, pos + length(id), 1)
        if ((b == "" || b !~ /[A-Za-z0-9]/) && (a == "" || a !~ /[A-Za-z0-9]/)) return 1
        off = pos
      }
    }
    # Collapse a board cell to one readable line. The cut is taken AT AN ASCII SPACE, never at a byte
    # offset: a blind substr() would split a multi-byte glyph and print mojibake into a CI log.
    function squeeze(s,   t, cut) {
      t = s
      gsub(/[ \t]+/, " ", t)
      sub(/^ /, "", t); sub(/ $/, "", t)
      if (length(t) > 96) {
        cut = 96
        while (cut > 1 && substr(t, cut, 1) != " ") cut--
        if (cut > 1) t = substr(t, 1, cut - 1) " ..."
      }
      return t
    }
    BEGIN {
      sep = "\302\267"                 # U+00B7 MIDDLE DOT, the summary separator used kit-wide
      # THE LEGEND, AS BYTES. Octal escapes, per-glyph, never a bracket expression (see the header).
      LEG[1] = "\342\234\205"          # U+2705  ✅ done
      LEG[2] = "\360\237\224\250"      # U+1F528 🔨 bounded build
      LEG[3] = "\360\237\224\247"      # U+1F527 🔧 small
      LEG[4] = "\360\237\224\215"      # U+1F50D 🔍 verify
      LEG[5] = "\360\237\247\221"      # U+1F9D1 🧑 needs you
      nleg = 5
      PEND[1] = LEG[2]; PEND[2] = LEG[3]; PEND[3] = LEG[4]; PEND[4] = LEG[5]
      npend = 4

      # ── PASS 1: the board. Cell 1 of every row inside `## Done`, and nothing else.
      ndone = 0; bstat = 0; seen_done = 0
      while (1) {
        r = (getline ln < backlog)
        if (r < 0) { bstat = -1; break }
        if (r == 0) break
        if (ln ~ /^## Done/) { seen_done = 1; indone = 1; continue }
        if (indone && ln ~ /^## /) indone = 0
        if (indone && substr(ln, 1, 1) == "|") {
          n = split(ln, c, "|")
          if (n >= 2) done1[++ndone] = c[2]
        }
      }
      close(backlog)

      # ── PASS 2: the roadmap. Item rows, marker cell, id, and the join.
      nmark = 0; nstale = 0; npendrow = 0; rstat = 0; noid = 0; nrows = 0
      while (1) {
        r = (getline ln < roadmap)
        if (r < 0) { rstat = -1; break }
        if (r == 0) break
        nrows++
        if (ln !~ /^\| \*\*/) continue
        n = split(ln, c, "|")
        if (n < 3) continue
        mi = n
        if (c[mi] ~ /^[ \t]*$/) mi = n - 1
        if (mi < 3) continue
        mcell = c[mi]
        ismark = 0
        for (k = 1; k <= nleg; k++) if (index(mcell, LEG[k]) > 0) ismark = 1
        if (!ismark) continue
        id = c[2]
        gsub(/[*`]/, "", id)
        sub(/^[ \t]+/, "", id)
        sub(/[ \t].*$/, "", id)
        # NEVER SILENT, AND ON AN ARMED TREE NEVER TOLERATED: a marked row whose item cell yields no
        # id cannot be joined, so it would drop out of the denominator M and take the C-2
        # denominator-integrity guarantee with it — the same "green over a shrunken domain" class the
        # zero-marker FAIL exists to close, just one row at a time. Collected by line number and
        # judged AFTER the verdict (see the MED-A note below): a FAIL on an armed tree, a reported
        # count on an adopter tree, and NEVER a reason to stand down to N/A.
        if (id == "") { noid++; noidat = noidat " " nrows; continue }
        nmark++
        ispend = 0
        for (k = 1; k <= npend; k++) if (index(mcell, PEND[k]) > 0) ispend = 1
        if (!ispend) continue
        npendrow++
        for (j = 1; j <= ndone; j++) {
          if (bounded(done1[j], id)) {
            nstale++
            print "STALE  " roadmap " item " id " is marked " squeeze(mcell) " (pending) but " \
                  backlog " ## Done carries: " squeeze(done1[j])
            break
          }
        }
      }
      close(roadmap)

      # ── ARMING + the verdict.
      why = ""
      if (rstat < 0)        why = "the roadmap (" roadmap ") could not be read"
      else if (bstat < 0)   why = "the board (" backlog ") could not be read"
      else if (!seen_done)  why = "the board (" backlog ") has no `## Done` section"
      else if (ndone == 0)  why = "the `## Done` section of the board (" backlog ") contains no rows"
      else if (nmark == 0)  why = "no marked item rows were found in " roadmap " (" nrows " line(s) scanned)"
      if (why != "") {
        if (armed == 1) {
          # The diagnostic quotes the figures THIS RUN measured, never a hard-coded census: a literal
          # "18 marked / 151 Done rows" would be a stale claim the day either file changed — the
          # decay class the verify.sh header itself warns about, and one this check exists to oppose.
          # (NB for future editors: NO APOSTROPHES anywhere between the awk quotes — a single quote
          # closes the shell-quoted program and the failure surfaces as "print: command not found".)
          print "roadmap-current: FAIL -- " why " on a KIT-MARKED tree. This is a FAILURE, never an N/A: this run parsed " nrows " roadmap line(s), " nmark " marked item(s) and " ndone " Done row(s), and a green over an empty or shrunken domain asserts nothing."
          exit 1
        }
        print "N/A: roadmap-current -- no kit marker present (an adopter tree) and " why ". There is nothing to grade and no remedy to offer; this is not a pass."
        exit 0
      }
      # UNIDENTIFIABLE ROWS ARE JUDGED HERE, NOT IN THE `why` CHAIN ABOVE (review MED-A). `noid` is
      # NOT an empty-input condition: the domain is gradeable and a verdict is in hand. Routing it
      # through `why` made ONE malformed row convert an UNARMED run to N/A even with a real STALE
      # already printed — a genuine FAIL silently downgraded to rc 0. It is a FAIL only on an ARMED
      # tree (where the denominator guarantee is load-bearing); an adopter tree is GRADED NORMALLY and
      # merely told the count, which is what the arming note at the top of this file promises.
      if (armed == 1 && noid > 0)
        print "UNIDENTIFIABLE  " noid " marked item row(s) in " roadmap " carry no extractable cell-1 id, so they cannot be joined and would silently leave the denominator (line(s):" noidat ")"
      res = (nstale == 0 && !(armed == 1 && noid > 0)) ? "OK" : "FAIL"
      printf "roadmap-current: %s -- %d stale of %d marked item(s) %s %d pending-class %s %d Done row(s) joined on cell 1 %s %d unidentifiable marked row(s) %s id-join only: unaliased and alias-tracked items are named false negatives\n", \
        res, nstale, nmark, sep, npendrow, sep, ndone, sep, noid, sep
      if (res == "OK") exit 0
      exit 1
    }
  '
}

run() {
  _armed=0
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then _armed=1; fi
  _rc=0
  rc_awk ROADMAP.md BACKLOG.md "$_armed" || _rc=$?
  return "$_rc"
}

# ---------------------------------------------------------------------------- selftest
# Every leg asserts the VERDICT CLASS, and every GREEN leg additionally asserts the PRINTED `N stale
# of M marked` FIGURES — an rc alone would let a mutant that silently empties the denominator
# cross-pass every positive leg. Fixtures are throwaway directories; this check shells out to nothing
# and reads no git state, so they need no `git init`.
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  # The legend glyphs, as shell-level byte literals, so the fixtures are written in the same
  # unambiguous octal form the check matches against.
  G_DONE=$(printf '\342\234\205')
  G_HAMMER=$(printf '\360\237\224\250')
  G_WRENCH=$(printf '\360\237\224\247')
  G_DECOY=$(printf '\360\237\224\252')   # U+1F52A 🔪 — shares 🔨/🔧/🔍's THREE-BYTE LEAD, not a legend glyph

  rc_init() {  # <dir> — a fresh fixture tree, ARMED by default (the kit-marker file)
    rm -rf "$1"; mkdir -p "$1/docs"
    printf 'kit marker\n' > "$1/docs/ROADMAP-KIT.md"
  }
  rc_put() {   # <dir> <relpath> <content with \n escapes>
    mkdir -p "$(dirname "$1/$2")"
    printf '%b' "$3" > "$1/$2"
  }
  rc_board() { # <dir> <done-rows content> — a minimal board with a bounded Done section
    rc_put "$1" "BACKLOG.md" "## Ready\n| SOMETHING-READY | m |\n\n## Done\n$2\n\n## Blocked\n| none |\n"
  }
  rc_out() { ( cd "$1" && sh "$_self" ); }
  rc_expect() {  # <label> <want-rc> <dir>
    _rc=0; _o=$(rc_out "$3") || _rc=$?
    if [ "$_rc" = "$2" ]; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (want rc $2, got $_rc)"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  rc_says() {  # <label> <needle> <dir>
    _o=$(rc_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (missing '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  rc_denies() {  # <label> <needle> <dir>
    _o=$(rc_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then
      echo "FAIL: selftest -- $1 (unexpected '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
    else echo "PASS: selftest -- $1"; fi
  }

  # ── THE POSITIVE ORACLE. A pending marker whose id sits in Done. Without this leg an
  # always-green mutant satisfies every GREEN leg below.
  rc_init "$W/stale"
  rc_put "$W/stale" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.1 — a shipped thing** | what | $G_HAMMER |\n"
  rc_board "$W/stale" "| P9.1 — a shipped thing | 2026-01-01 | Shipped v9.9.9 |"
  rc_expect "a pending marker whose id sits in Done FAILS" 1 "$W/stale"
  rc_says  "and the count names it stale" "1 stale of 1 marked" "$W/stale"
  rc_says  "and the defect NAMES the roadmap side" "STALE  ROADMAP.md item P9.1" "$W/stale"
  rc_says  "and NAMES the board side too" "BACKLOG.md ## Done carries:" "$W/stale"

  # ── PENDING BUT GENUINELY OPEN -> GREEN. The honest case must not red.
  rc_init "$W/open"
  rc_put "$W/open" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.2 — still open** | what | $G_HAMMER |\n"
  rc_board "$W/open" "| SOMETHING-ELSE — unrelated | 2026-01-01 | Shipped |"
  rc_expect "a pending marker with no Done row passes" 0 "$W/open"
  rc_says  "and the denominator is still counted" "0 stale of 1 marked" "$W/open"

  # ── ALREADY ✅ AND IN DONE -> GREEN. The marker filter: a done item in Done is the RECONCILED state.
  rc_init "$W/done"
  rc_put "$W/done" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.3 — shipped and marked** | what | $G_DONE |\n"
  rc_board "$W/done" "| P9.3 — shipped and marked | 2026-01-01 | Shipped v9.9.9 |"
  rc_expect "a DONE-marked item sitting in Done passes" 0 "$W/done"
  rc_says  "and still counts toward the denominator" "0 stale of 1 marked" "$W/done"

  # ── THE CELL-1 BOUND. The id appears only in the Done row`s RETRO column, never its item cell —
  # the measured 5-hits-vs-1 face. Dropping the cell-1 bound reds this leg.
  rc_init "$W/retro"
  rc_put "$W/retro" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.4 — genuinely open** | what | $G_HAMMER |\n"
  rc_board "$W/retro" "| UNRELATED-ROW — other work | 2026-01-01 | Shipped; satisfied-by-P9.4 per the retro |"
  rc_expect "an id MENTIONED only in a Done row's retro column does not red" 0 "$W/retro"
  rc_says  "and the item stays counted as open" "0 stale of 1 marked" "$W/retro"

  # ── THE SECTION BOUND. The id is cell 1 of a row OUTSIDE `## Done`. Dropping the section bound
  # reds this leg.
  rc_init "$W/section"
  rc_put "$W/section" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.5 — open, and boarded as Ready** | what | $G_HAMMER |\n"
  rc_put "$W/section" "BACKLOG.md" "## Ready\n| P9.5 — open, and boarded as Ready | m |\n\n## Done\n| UNRELATED | 2026-01-01 | Shipped |\n\n## Blocked\n| none |\n"
  rc_expect "an id in a NON-Done section's cell 1 does not red" 0 "$W/section"
  rc_says  "and the item stays counted as open" "0 stale of 1 marked" "$W/section"

  # ── THE SECTION *CLOSING* BOUND, which the leg above does NOT reach (review MED-1, a surviving
  # mutant). The fixture above puts its decoy row in `## Ready`, which PRECEDES `## Done` — so it
  # kills the OPENING bound only, and dropping `indone = 0` survived it. Here the decoy id is cell 1
  # of a row in `## Blocked`, i.e. AFTER the Done section: only the closing bound excludes it.
  rc_init "$W/closing"
  rc_put "$W/closing" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.14 — open, and currently blocked** | what | $G_HAMMER |\n"
  rc_put "$W/closing" "BACKLOG.md" "## Ready\n| SOMETHING | m |\n\n## Done\n| UNRELATED-DONE | 2026-01-01 | Shipped |\n\n## Blocked\n| P9.14 — open, and currently blocked | waiting on a decision |\n"
  rc_expect "an id in cell 1 of a section AFTER ## Done does not red (the CLOSING bound)" 0 "$W/closing"
  rc_says  "and the Done join set stays bounded to one row" "1 Done row(s) joined on cell 1" "$W/closing"
  rc_says  "and the item stays counted as open" "0 stale of 1 marked" "$W/closing"

  # ── A MARKED ROW WITH NO EXTRACTABLE ID MUST FAIL ON AN ARMED TREE (review MED-2). Left silent it
  # drops out of M, shrinking the denominator the C-2 guarantee rests on — one row at a time.
  rc_init "$W/noid"
  rc_put "$W/noid" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.15 — a real row** | what | $G_DONE |\n| **** | what | $G_HAMMER |\n"
  rc_board "$W/noid" "| P9.15 — a real row | 2026-01-01 | Shipped |"
  rc_expect "a marked row whose item cell yields no id FAILS on an armed tree" 1 "$W/noid"
  rc_says  "and the count of unidentifiable rows is named" "1 marked item row(s)" "$W/noid"
  rc_says  "and the offending line is named, never just counted" "line(s): 4" "$W/noid"

  # ── THE REGRESSION LEG (review MED-A). `noid` is NOT an empty-input condition — the domain is
  # GRADEABLE — so routing it through the same `why` chain as "no roadmap"/"no Done section" made ONE
  # malformed row convert an UNARMED run into N/A even with a real STALE already printed, silently
  # downgrading a genuine FAIL to rc 0 and falsifying the header promise that an adopter who keeps
  # both files is graded normally. An unarmed tree must still GRADE: FAIL on the stale, and merely
  # REPORT the noid count.
  rm -rf "$W/unarmednoid"; mkdir -p "$W/unarmednoid"          # NO kit marker: an adopter-shaped tree
  rc_put "$W/unarmednoid" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.16 — a shipped thing** | what | $G_HAMMER |\n| **** | what | $G_HAMMER |\n"
  rc_board "$W/unarmednoid" "| P9.16 — a shipped thing | 2026-01-01 | Shipped v9.9.9 |"
  rc_expect "an UNARMED tree with a malformed row still GRADES and FAILS on a real stale" 1 "$W/unarmednoid"
  rc_says  "naming the stale item, not standing down to N/A" "STALE  ROADMAP.md item P9.16" "$W/unarmednoid"
  rc_denies "and never renders N/A while a defect is in hand" "N/A: roadmap-current" "$W/unarmednoid"
  rc_says  "while the malformed row is still REPORTED in the summary" "1 unidentifiable marked row(s)" "$W/unarmednoid"

  # ── MIXED CELLS ARE PENDING BY RULE (the P2.1 face: `✅ core + 🔧`). Dropping the rule greens this.
  rc_init "$W/mixed"
  rc_put "$W/mixed" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.6 — half shipped** | what | $G_DONE core + $G_WRENCH |\n"
  rc_board "$W/mixed" "| P9.6 — half shipped | 2026-01-01 | Shipped v9.9.9 |"
  rc_expect "a MIXED marker cell is pending by rule and FAILS when it joins Done" 1 "$W/mixed"
  rc_says  "and is reported stale" "1 stale of 1 marked" "$W/mixed"

  # ── AN ALL-✅ ROADMAP IS GREEN WITH A NON-ZERO DENOMINATOR (design vet C-2). `Marked` counts every
  # legend glyph, so the reconciled end-state does NOT trip the zero-gradeable FAIL.
  rc_init "$W/allgreen"
  rc_put "$W/allgreen" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.7 — one** | what | $G_DONE |\n| **P9.8 — two** | what | $G_DONE |\n"
  rc_board "$W/allgreen" "| P9.7 — one | 2026-01-01 | Shipped |\n| P9.8 — two | 2026-01-01 | Shipped |"
  rc_expect "an all-done roadmap passes" 0 "$W/allgreen"
  rc_says  "with a NON-ZERO denominator (never the zero-gradeable FAIL)" "0 stale of 2 marked" "$W/allgreen"
  rc_denies "and is not reported as an empty domain" "FAIL" "$W/allgreen"

  # ── THE DECOY GLYPH (design vet C-3). 🔪 shares 🔨/🔧/🔍's three-byte lead. Under LC_ALL=C a bracket
  # expression `[🔨🔧🔍🧑]` degenerates to that byte set and would classify this row PENDING, joining
  # Done and reddening. Per-glyph index() keeps it correctly DONE-only.
  rc_init "$W/decoy"
  rc_put "$W/decoy" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.9 — shipped, annotated with a non-legend emoji** | what | $G_DONE $G_DECOY |\n"
  rc_board "$W/decoy" "| P9.9 — shipped, annotated with a non-legend emoji | 2026-01-01 | Shipped |"
  rc_expect "a NON-legend emoji sharing the pending lead bytes does not make a row pending" 0 "$W/decoy"
  rc_says  "and the row is still counted marked" "0 stale of 1 marked" "$W/decoy"

  # ── THE RENAME-LAUNDERING CEILING, DOCUMENTED RATHER THAN PRETENDED AWAY (design vet C-1). The work
  # IS done and the marker IS stale, but the board row was reworded, so the join breaks and this
  # check greens. The owner-reviewed diff is the control.
  rc_init "$W/renamed"
  rc_put "$W/renamed" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.10 — shipped under another name** | what | $G_HAMMER |\n"
  rc_board "$W/renamed" "| THE-SAME-WORK-RENAMED | 2026-01-01 | Shipped v9.9.9 |"
  rc_expect "a renamed board row breaks the join and GREENS (the disclosed ceiling)" 0 "$W/renamed"
  rc_says  "and the ceiling is visible in the denominator" "0 stale of 1 marked" "$W/renamed"

  # ── A PHASE-3-SHAPED (two-column, marker-less) ROW IS NOT GRADED, even when its id sits in Done.
  rc_init "$W/phase3"
  rc_put "$W/phase3" "ROADMAP.md" "| Item | What |\n|---|---|\n| **AxisB — meta-orchestration** | Session-teams |\n| Item | What | Effort |\n|---|---|---|\n| **P9.11 — open** | what | $G_HAMMER |\n"
  rc_board "$W/phase3" "| AxisB — meta-orchestration | 2026-01-01 | Shipped |"
  rc_expect "a marker-less two-column row is ignored" 0 "$W/phase3"
  rc_says  "and only the marked row counts toward M" "0 stale of 1 marked" "$W/phase3"

  # ── ARMED + ROADMAP.md ABSENT -> FAIL, never N/A.
  rc_init "$W/armedmissing"
  rc_board "$W/armedmissing" "| UNRELATED | 2026-01-01 | Shipped |"
  rc_expect "a KIT-MARKED tree with no ROADMAP.md FAILS" 1 "$W/armedmissing"
  rc_says  "and says so in the concealment-class language" "never an N/A" "$W/armedmissing"

  # ── ARMED + ZERO MARKED ITEMS -> FAIL. A marker-stripped stub must not green vacuously.
  rc_init "$W/armedzero"
  rc_put "$W/armedzero" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.12 — no glyph at all** | what | none |\n"
  rc_board "$W/armedzero" "| P9.12 — no glyph at all | 2026-01-01 | Shipped |"
  rc_expect "a KIT-MARKED tree with zero marked items FAILS (never a vacuous green)" 1 "$W/armedzero"
  rc_says  "and names the empty denominator" "no marked item rows were found" "$W/armedzero"

  # ── ARMED + NO `## Done` SECTION -> FAIL. Without this, deleting the board greens the check.
  rc_init "$W/armednodone"
  rc_put "$W/armednodone" "ROADMAP.md" "| Item | What | Effort |\n|---|---|---|\n| **P9.13 — open** | what | $G_HAMMER |\n"
  rc_put "$W/armednodone" "BACKLOG.md" "## Ready\n| SOMETHING | m |\n"
  rc_expect "a KIT-MARKED tree whose board has no Done section FAILS" 1 "$W/armednodone"
  rc_says  "and names the missing section" "has no \`## Done\` section" "$W/armednodone"

  # ── UNARMED + NOTHING TO GRADE -> N/A, and the LINE SHAPE must satisfy verify.sh's C6 classifier.
  # This is the ADOPTER FACE: a one-shot export carries neither roadmap nor board (both are
  # export-ignored), so neither arming token and neither input file is present.
  rm -rf "$W/na"; mkdir -p "$W/na"
  rc_expect "an adopter tree with neither marker nor roadmap renders N/A (rc 0)" 0 "$W/na"
  rc_says  "and says N/A in the line-anchored idiom" "N/A: roadmap-current" "$W/na"
  # The predicate below is COPIED VERBATIM from verify.sh's is_self_skip (C6). If that idiom ever
  # changes, this leg is what tells us this check silently started rendering PASS instead of N-A.
  _o=$(rc_out "$W/na") || :
  if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
     ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
    echo "PASS: selftest -- the N/A output renders N-A under verify.sh's C6 classifier (never PASS)"
  else
    echo "FAIL: selftest -- the N/A output does NOT satisfy verify.sh's is_self_skip predicate"
    printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
  fi

  if [ "$sfail" = 0 ]; then echo "OK: roadmap-current selftest (every verdict class asserted, every green leg pinned to its N/M figures)"; exit 0; fi
  echo "FAIL: roadmap-current selftest"; exit 1
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
run; exit $?
