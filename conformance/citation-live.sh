#!/bin/sh
# citation-live.sh — every `path.ext:LINE` citation in the kit's LIVING Markdown must still point at
# a line that EXISTS and is NOT BLANK. C9 CITATION-LIVE (ruling D-240804-2, the resolves-variant).
#
# WHY THIS EXISTS: the kit's governance record is held together by citations — a row, a ruling or a
# design that names the file and line it is talking about. `DECISIONS.md` states the principle
# directly ("a row you cannot verify from its citation is a defect"), and the standing doctrine is
# "cite by row identifier, never line number". Neither was gated; measured at the C9 probe, 77 sites
# across the tree cited a line that had moved or vanished. This check is that doctrine's gate, and
# the doctrine itself lands in DEVELOPMENT-STANDARDS.md ("Citation discipline") — read them together.
#
# ── HONEST CEILING, STATED FIRST (it is the whole shape of this check) ──────────────────────────────
# THIS IS THE *RESOLVES* VARIANT: it detects a line that VANISHED, never one whose MEANING CHANGED.
# The measured example is the row's own flagship evidence: `ci.yml:1304` was a dead pointer when the
# row was written and is a perfectly live — and semantically wrong — line today, because the file
# grew past it. Same class, one day old: C7's design cites a workflow line that drifted by eleven
# lines inside 24h and stays green here. A green from this check means "the cited line still exists
# and has content", NOT "the citation still says what its author meant". The semantic variant stays
# behind D-240804-2's revisit condition. Do not quote this green as more than it is.
#
# ── DOMAIN (principled, not convenient) ─────────────────────────────────────────────────────────────
# SOURCES = tracked `*.md` files that are LIVING documents. EXEMPT-and-REPORTED: the dated record —
# docs/architecture/20*.md, docs/plans/20*.md, docs/plans/brief-*.md, CHANGELOG.md and
# docs/governance/meta-control-log.md. A dated document is an IMMUTABLE RECORD: its citations were
# correct against the tree of its own date and are recoverable from git history, so grading them
# against today HEAD is a category error, and "repairing" them would rewrite the record. Measured at
# the C9 probe: 59 of the 77 decayed sites live in exactly those documents.
# TARGETS = any tracked file; a citation whose TARGET is dated is likewise EXEMPT-and-REPORTED (a
# historical anchor into an immutable record).
# ⚠️ THE DATED-TARGET TEST RUNS ON THE CITATION STRING, BEFORE RESOLUTION, AND THE ORDER IS THE
# CONTROL (design vet H-1). The dated directories are export-pruned, so a resolve-first order would
# turn DECISIONS.md's bare-basename dated citations (7 measured) into UNRESOLVABLE FAILs on every
# fresh adopter clone. String-first also closes the symlink-alias face without resolving anything.
# EXEMPTIONS ARE NEVER SILENT: their counts print on EVERY run, pass or fail.
#
# ── GRAMMAR (pinned) ────────────────────────────────────────────────────────────────────────────────
# A citation is `<path>.<ext>:<N>` with optional range/list endpoints (`:12-15`, `:12,20`), where the
# extension is ALPHABETIC-FIRST and 1-6 chars (this is what kills IP addresses, ports and ratios —
# measured 20 such tokens), plus DOTFILES with an empty stem (`.gitattributes:7` is a real citation
# shape; BACKLOG.md carries three). EVERY range/list endpoint is judged: a range that ENDS on a blank
# line is decayed.
#   UNCOUNTED FALSE-NEGATIVE CLASSES, named as such — this check does not claim them, and its
#   coverage figure must NOT be read as "every citation":
#     · EXTENSIONLESS targets (`hooks/pre-push:224`) — invisible to the grammar.
#     · GLOB-QUALIFIED citations (`profiles/*/ci.yml` or `.github/workflows/*.yml` at a line) —
#       rejected by the left word boundary, because the glob metacharacter truncates the token and
#       reporting the fragment would name a path nobody wrote (review HIGH-1). Markdown bold wrapped
#       DIRECTLY around a bare citation (`**name.md:21**`) falls out with them — exactly one such
#       occurrence exists on the kit tree, in a dated source. Boarded: CITATION-GLOB-FORM.
#     · NON-ASCII paths — the pinned path class is ASCII, so a citation NAMING an accented path is
#       uncounted. The FILE is still enumerated and read as a source: see the core.quotePath note in
#       run(), which is a different (and much worse) failure this check does NOT have.
#   OUT OF SCOPE, COUNTED: the backticked bare-`:NNN` CONTINUATION form (a second citation whose
#   antecedent file is the previous token). It is undecidable without antecedent resolution; the
#   summary prints its LIVE count every run — over the whole `.md` corpus, living AND dated, which is
#   the one counter here that is not domain-scoped, and the summary says so. Recorded figures move as
#   the corpus does; the run is always the authority. Boarded: CITATION-CONTINUATION-FORM.
#   OUT OF SCOPE, NOT COUNTED: `.sh`-comment citations (101 tokens under this grammar as-of the C9
#   build; 6 genuine decays found and repaired in-slice, in preflight.sh and the guard core — the
#   design predicted 4). Widening to them requires handling the false-positive classes that
#   live only in shell sources — doc-budget.sh's `BUDGETS="CLAUDE.md:135 ..."` line-CEILING grammar
#   collision (structurally guaranteed to read past EOF) and conformance fixture strings. Every one of
#   those FP classes is out of this domain BY CONSTRUCTION, which is why this check carries NO
#   by-name exclusion list. Boarded: CITATION-CODE-COMMENT-WIDENING.
#
# ── RESOLUTION ──────────────────────────────────────────────────────────────────────────────────────
# Against the TRACKED set (`git ls-files`, check-links.sh's idiom — an untracked-but-on-disk file does
# NOT resolve, or the check would false-pass locally and ship dead pointers): qualified repo-relative
# path -> unique tracked basename -> a three-rule tie-breaker (prefer the shallowest path; penalise
# profiles/, templates/, adapters/, */scaffold/*, */fixtures/*, archive/). Measured: 24% -> 88% -> 99%
# decidable. Still ambiguous, or zero candidates => UNRESOLVABLE (a FAIL, reported by class — an
# absent target is never a skip).
#   CEILING: the tie-breaker is a CONVENTION and its mis-picks are PROBABILISTIC, not fail-tight —
#   the wrong file's line N is usually non-blank, so a mis-resolution usually greens silently.
#   CEILING: the dated classifier keys partly on a BASENAME SHAPE (`20NN-*.md`), so RENAMING a target
#   into that shape exempts every citation into it. Accepted, not closed: the move is loud in the
#   exempt counts this check prints on every run, and the owner reviews diffs. Named on the board
#   (CITATION-GLOB-FORM) rather than left as a silent property.
#
# ── COMPLEMENTARY TO check-links.sh, ZERO OVERLAP ───────────────────────────────────────────────────
# check-links.sh validates Markdown LINKS and deliberately SKIPS code spans; ~85% of citations live
# inside code spans, and its own header discloses that backticked path references are uncovered. This
# check covers exactly that gap for the citations that carry a line number. Neither subsumes the other.
#
# ── ARMING (fail-closed; the C3/C5/C7 kit-marker pattern) ───────────────────────────────────────────
# On a KIT tree (either of the export-ignored markers docs/ROADMAP-KIT.md /
# .github/workflows/golden-path.yml present) a failed or empty corpus enumeration, or ZERO in-domain
# citations, is a FAIL: 1,447 exist here, so zero means the extractor or `git ls-files` broke, and a
# git failure must never silently render N/A. With NEITHER marker present (an adopter tree) zero
# citations is the honest line-anchored `N/A:` — a citation-free corpus has nothing wrong with it and
# no sane remedy. The anti-vacuity control lives in --selftest and the non-vacuity sweep, NOT in a
# runtime fail-on-zero.
#
# THE RATCHET IS INTENDED: future decay in a living doc reds `docs-links` — a required context — on
# unrelated PRs, the same posture check-links already has. The fix is always a cheap re-cite.
#
# WIRED (pair pointers): verify.sh `check control citation-live` (which also enrols this file in
# non-vacuity.sh's mutation sweep) · .github/workflows/ci.yml `docs-links` (the LIVE step, a required
# job with no `if:` so it survives the docs_only skip) · ci.yml `conformance-selftests` (--selftest).
# Usage: sh conformance/citation-live.sh [--selftest]   (run from the repo root)
# Exit: 0 = every in-domain citation is live (or N/A off the kit tree) · 1 = decay / unresolvable /
#       a broken corpus on an armed tree · 2 = bad usage. POSIX sh + one awk pass; dash-clean.
set -eu

SELFTEST=no
case "${1:-}" in
  "") : ;;
  --selftest) SELFTEST=yes ;;
  *) echo "usage: citation-live.sh [--selftest]" >&2; exit 2 ;;
esac

# ── THE SINGLE AWK PASS ─────────────────────────────────────────────────────────────────────────────
# One process for the whole corpus. NOT a per-pointer loop: the naive shape (a subprocess per
# citation) was measured at 6.25s against 0.27s here — a 23x cliff on a check that runs in a required
# CI job and in every local `verify.sh`. ARGV[1] is the tracked-file listing, ARGV[2] the `*.md`
# listing; every source and every cited target is read with getline, so no file is opened twice and
# nothing shells out.
cl_awk() {  # <tracked-listing> <md-listing> <armed 0|1>
  LC_ALL=C awk -v armed="$3" '
    BEGIN { sep = "·" }
    function depth(p,   s) { return split(p, s, "/") - 1 }
    function penalised(p) {
      return (p ~ /^profiles\// || p ~ /^templates\// || p ~ /^adapters\// ||
              p ~ /\/scaffold\// || p ~ /\/fixtures\// || p ~ /^archive\//) ? 1 : 0
    }
    # DATED = the immutable record. One predicate, used for BOTH the source domain and the
    # before-resolution target test, so the two can never drift apart.
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
    # THE THREE-RULE TIE-BREAKER. Shallowest wins; a fixture/scaffold/profile copy is penalised so it
    # loses to the real file at equal depth. A remaining tie is UNRESOLVABLE, never a guess.
    function resolve_base(b,   k, arr, i, sc, best, bestsc, ties) {
      k = split(bcand[b], arr, "\n"); bestsc = -1; ties = 0; best = ""
      for (i = 1; i <= k; i++) {
        sc = penalised(arr[i]) * 1000 + depth(arr[i])
        if (bestsc < 0 || sc < bestsc) { bestsc = sc; best = arr[i]; ties = 1 }
        else if (sc == bestsc) { ties = ties + 1 }
      }
      if (ties > 1) return "AMB"
      return best
    }
    # scan one source line for citations. dsrc = the source is a dated record (exempt-and-counted).
    function scan(ln, f, lno, dsrc,   line, consumed, pre, tok, p, ci, bn, ext, stem, t, ne, ep, ie) {
      line = ln
      while (match(line, /`:[0-9]+/)) { oos++; line = substr(line, RSTART + RLENGTH) }
      line = ln; consumed = ""
      while (match(line, /(([A-Za-z0-9_.@+-]+\/)*[A-Za-z0-9_.@+-]*[A-Za-z0-9_@+-]\.[A-Za-z][A-Za-z0-9]*|\.[A-Za-z][A-Za-z0-9_-]*):[0-9]+([,-][0-9]+)*/)) {
        pre = consumed substr(line, 1, RSTART - 1)
        tok = substr(line, RSTART, RLENGTH)
        consumed = pre tok
        line = substr(line, RSTART + RLENGTH)
        # LEFT WORD BOUNDARY (the pinned grammar). A token glued to a preceding path-expression char is
        # a FRAGMENT of something longer, not a citation, and reporting the fragment would name a path
        # its author never wrote. The class covers word chars, the path separator, the dot, AND THE
        # GLOB METACHARACTERS `*` `?`. Four real classes, all rejected here:
        #   glob, qualified   — `profiles/*/ci.yml:301`      would yield the fragment `/ci.yml:301`
        #   glob, unqualified — `.github/workflows/*.yml:40` would yield the fragment `.yml:40`
        #   URL-embedded      — `https://host/a.md:1`        would yield `host/a.md:1`
        #   mid-word dotfile  — `A.b_c-d:12`                 would yield `.b_c-d:12`
        # BUILD-TIME FALSIFICATION, IN TWO ROUNDS (design §10 A2-F1 and A3-H1). Round 1: without the
        # boundary at all, the kit tree reported 3 in-domain UNRESOLVABLE against the probe-measured 1 — the
        # two extras were qualified glob fragments. Round 2 (review HIGH-1): the segment-structured
        # path rule closed only the QUALIFIED shape; the UNQUALIFIED one still reached the dotfile
        # branch, and `*.md:5` escaped merely because "md" is under the dotfile minimum length — an
        # accident, not a rule. Both shapes are now rejected by the same class, and a selftest leg
        # pins all four. Glob-qualified citations are an UNCOUNTED FALSE-NEGATIVE class, exactly like
        # extensionless targets: this check does not claim them. Boarded: CITATION-GLOB-FORM.
        # COST, MEASURED, NOT ASSUMED: exactly ONE citation on the kit tree is preceded by `*` —
        # `**meta-control-log.md:21-22**`, markdown bold around a bare basename, in a DATED source
        # (docs/architecture/2026-08-13-guard-judge-resolved-target-design.md). It was an exempt-SOURCE
        # count and is now uncounted: EXEMPT sources 1144 -> 1143, everything else identical.
        # LIVE/DECAYED/UNRESOLVABLE are untouched at 190/0/0. Markdown bold around a citation is
        # therefore a (vanishingly rare) uncounted shape, folded into CITATION-GLOB-FORM.
        if (pre ~ /[A-Za-z0-9_.\/*?-]$/) { noise++; continue }
        ci = tok; sub(/^.*:/, "", ci)
        p  = tok; sub(/:[0-9,-]+$/, "", p)
        bn = p; sub(/^.*\//, "", bn)
        ext = bn; sub(/^.*\./, "", ext)
        stem = bn; sub(/\.[^.]*$/, "", stem)
        if (stem == "") { if (length(ext) < 3 || length(ext) > 21) { noise++; continue } }
        else            { if (length(ext) < 1 || length(ext) > 6)  { noise++; continue } }
        if (dsrc) { exsrc++; continue }
        cites++
        if (is_dated(p)) { extgt++; continue }
        if (p ~ /\//) t = (p in tracked) ? p : ""
        else if (!(p in bcount)) t = ""
        else if (bcount[p] == 1) t = bcand[p]
        else t = resolve_base(p)
        nsite++
        site_src[nsite] = f ":" lno; site_tok[nsite] = tok
        site_eps[nsite] = ci; site_t[nsite] = t
        if (t == "" || t == "AMB") {
          site_why[nsite] = (t == "AMB") ? "ambiguous basename (" bcount[p] " tracked candidates; the tie-breaker did not decide)" \
                                         : "no tracked file matches that path or basename"
        } else {
          want[t] = 1
          ne = split(ci, ep, /[,-]/)
          for (ie = 1; ie <= ne; ie++) tneed[t] = tneed[t] " " (ep[ie] + 0)
        }
      }
    }
    NR == FNR {
      tracked[$0] = 1
      n = split($0, s, "/"); b = s[n]
      if (b in bcount) { bcount[b] = bcount[b] + 1; bcand[b] = bcand[b] "\n" $0 }
      else { bcount[b] = 1; bcand[b] = $0 }
      next
    }
    {
      f = $0; nsrc++
      dsrc = is_dated(f)
      if (dsrc) ndated++; else nliving++
      lno = 0
      while (1) {
        r = (getline ln < f)
        if (r <= 0) break
        lno = lno + 1
        scan(ln, f, lno, dsrc)
      }
      close(f)
      # NAME THE FILE, never just a count (review MED-3): every other verdict this check prints
      # identifies its site, and an operator handed "1 file could not be read" has to go find it.
      if (r < 0) { readerr++; badread = badread " " f }
    }
    END {
      # PASS 2 — read each cited target ONCE and judge every requested endpoint against it.
      for (t in want) {
        nl = 0; split("", L, ":")
        while (1) { rr = (getline tl < t); if (rr <= 0) break; nl = nl + 1; L[nl] = tl }
        close(t)
        if (rr < 0) { readerr++; badread = badread " " t }
        eof[t] = nl
        nn = split(tneed[t], cc, " ")
        for (m = 1; m <= nn; m++) {
          c = cc[m] + 0
          if (c < 1 || c > nl) verdict[t SUBSEP c] = "past EOF"
          else if (L[c] ~ /^[ \t]*$/) verdict[t SUBSEP c] = "blank line"
          else verdict[t SUBSEP c] = ""
        }
      }
      # PASS 3 — emit per-site defects IN SOURCE ORDER (deterministic; no external sort).
      for (i = 1; i <= nsite; i++) {
        t = site_t[i]
        if (t == "" || t == "AMB") {
          unres++
          print "UNRESOLVABLE  " site_src[i] " cites " site_tok[i] " -- " site_why[i]
          continue
        }
        bad = ""
        k2 = split(site_eps[i], eps, /[,-]/)
        for (j = 1; j <= k2; j++) {
          c = eps[j] + 0
          if (verdict[t SUBSEP c] != "") bad = bad " " c " (" verdict[t SUBSEP c] ")"
        }
        if (bad == "") { live++; continue }
        decayed++
        print "DECAYED  " site_src[i] " cites " site_tok[i] " -> " t " has " eof[t] " lines; dead endpoint(s):" bad
      }
      # ARMING + the summary. The exempt and out-of-scope counts print on EVERY run.
      if (readerr > 0) {
        print "citation-live: FAIL -- " readerr " file(s) in the corpus could not be read, so the judgement would be over an unknown subset. Unreadable:" badread
        exit 1
      }
      if (cites == 0) {
        if (armed == 1) {
          print "citation-live: FAIL -- ZERO in-domain citations found across " nliving " living Markdown file(s) on a KIT-MARKED tree. The kit carries ~1,400; zero means the extractor or the corpus enumeration is dead, and a green over an empty domain asserts nothing."
          exit 1
        }
        print "N/A: citation-live -- no kit marker present (an adopter tree) and no path.ext:LINE citations in the living Markdown corpus (" nliving " file(s) scanned, " ndated " dated file(s) exempt). There is nothing to grade and no remedy to offer; this is not a pass."
        exit 0
      }
      res = (decayed == 0 && unres == 0) ? "OK" : "FAIL"
      # LOW-8: the continuation count is deliberately taken over the WHOLE .md corpus (living AND
      # dated), unlike every other counter here, which is domain-scoped. Relabelled rather than
      # re-scoped — the whole-corpus figure is the one the design and the board rows quote, and
      # re-scoping it would silently restate a recorded measurement.
      printf "citation-live: %s -- %d LIVE %s %d DECAYED %s %d UNRESOLVABLE %s %d EXEMPT-dated (sources %d/targets %d) %s %d out-of-scope continuation-form (whole .md corpus, living + dated) %s %d living/%d dated .md file(s) scanned\n", \
        res, live, sep, decayed, sep, unres, sep, exsrc + extgt, exsrc, extgt, sep, oos, sep, nliving, ndated
      if (res == "OK") exit 0
      exit 1
    }
  ' "$1" "$2"
}

run() {
  _armed=0
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then _armed=1; fi
  _w=$(mktemp -d) || { echo "citation-live: FAIL -- could not create a work directory"; return 1; }
  # Unconditional cleanup that PRESERVES the rc: a swallowed failure here would be the same
  # silent-disarm class the arming block exists to close.
  trap 'rm -rf "$_w"' EXIT INT TERM

  _enum=1
  # `-c core.quotePath=false` IS LOAD-BEARING, NOT TIDINESS (review HIGH-2). Under git's DEFAULT
  # quotePath=true a non-ASCII tracked path is emitted C-QUOTED (`"docs/caf\303\251.md"`), and awk's
  # getline cannot open that literal — so ONE accented filename anywhere in the tree turns this check
  # into "the corpus could not be read" for EVERYTHING. Same cure, same reason, as obligation-lib.sh's
  # changeset derivation and promotion-readiness-wired.sh's stronger-half note. A selftest leg holds it.
  git -c core.quotePath=false ls-files > "$_w/tracked" 2>/dev/null || _enum=0
  git -c core.quotePath=false ls-files -- "*.md" > "$_w/md" 2>/dev/null || _enum=0
  [ -s "$_w/md" ] || _enum=0
  if [ "$_enum" = 0 ]; then
    if [ "$_armed" = 1 ]; then
      echo "citation-live: FAIL -- the Markdown corpus could not be enumerated (git ls-files failed or returned nothing) on a KIT-MARKED tree. This is a FAILURE, never an N/A: a check that quietly stands down when its own input is missing is the concealment class the arming block exists to close."
      return 1
    fi
    echo "N/A: citation-live -- no kit marker present (an adopter tree) and no tracked Markdown corpus to enumerate here. There is nothing to grade; this is not a pass."
    return 0
  fi

  _rc=0
  cl_awk "$_w/tracked" "$_w/md" "$_armed" || _rc=$?
  return "$_rc"
}

# ---------------------------------------------------------------------------- selftest
# Every leg asserts the VERDICT CLASS WORD (LIVE / DECAYED / UNRESOLVABLE / EXEMPT / N/A), not just an
# rc: a branch-collapse mutant that reds for the wrong reason must not cross-pass a leg (design vet
# L-3). Fixtures are throwaway `git init` trees — no commit, so no ambient git identity is read
# (the selftest-hermetic lane's face (a)), and no ambient repo state is consulted (its face (b)).
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  cl_init() {  # <dir> — a fresh, EMPTY fixture repo (never a clone of the surrounding tree)
    rm -rf "$1"; mkdir -p "$1"
    ( cd "$1" && git init -q . >/dev/null 2>&1 )
  }
  cl_put() {   # <dir> <relpath> <content with \n escapes>
    mkdir -p "$(dirname "$1/$2")"
    printf '%b' "$3" > "$1/$2"
  }
  cl_add() { ( cd "$1" && git add -A . >/dev/null 2>&1 ); }
  cl_out() { ( cd "$1" && sh "$_self" 2>&1 ); }
  cl_expect() {  # <label> <want-rc> <dir>
    _rc=0; _o=$(cl_out "$3") || _rc=$?
    if [ "$_rc" = "$2" ]; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (want rc $2, got $_rc)"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  cl_says() {  # <label> <needle> <dir>
    _o=$(cl_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (missing '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  cl_denies() {  # <label> <needle> <dir>
    _o=$(cl_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then
      echo "FAIL: selftest -- $1 (unexpected '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
    else echo "PASS: selftest -- $1"; fi
  }

  # ── LIVENESS ANCHOR. Without a positive leg an always-red mutant satisfies every negative below.
  cl_init "$W/live"
  cl_put "$W/live" "docs/target.md" 'one\ntwo\nthree\n'
  cl_put "$W/live" "docs/a.md" 'see `docs/target.md:2` for it\n'
  cl_add "$W/live"
  cl_expect "a live citation passes" 0 "$W/live"
  cl_says  "and is counted LIVE" "1 LIVE" "$W/live"

  # ── PAST EOF -> DECAYED.
  cl_init "$W/eof"
  cl_put "$W/eof" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/eof" "docs/a.md" 'see `docs/target.md:99` for it\n'
  cl_add "$W/eof"
  cl_expect "a citation past EOF fails" 1 "$W/eof"
  cl_says  "and is classed DECAYED (past EOF)" "DECAYED" "$W/eof"
  cl_says  "naming the past-EOF reason" "past EOF" "$W/eof"

  # ── BLANK LINE -> DECAYED. The line EXISTS; its content is gone. This is the 62-of-77 majority class.
  cl_init "$W/blank"
  cl_put "$W/blank" "docs/target.md" 'one\n\nthree\n'
  cl_put "$W/blank" "docs/a.md" 'see `docs/target.md:2` for it\n'
  cl_add "$W/blank"
  cl_expect "a citation of a blank line fails" 1 "$W/blank"
  cl_says  "naming the blank-line reason" "blank line" "$W/blank"

  # ── RANGE ENDPOINT ON A BLANK LINE -> DECAYED. The START is live; only the END rotted.
  cl_init "$W/range"
  cl_put "$W/range" "docs/target.md" 'one\ntwo\n\nfour\n'
  cl_put "$W/range" "docs/a.md" 'see `docs/target.md:1-3` for it\n'
  cl_add "$W/range"
  cl_expect "a range whose END endpoint is blank fails" 1 "$W/range"
  cl_says  "and the dead ENDPOINT is named, not the range" "3 (blank line)" "$W/range"

  # ── UNTRACKED / DELETED TARGET -> UNRESOLVABLE (a FAIL, never a skip: the row's constraint iii).
  # The file is ON DISK but not in the index — exactly the case a filesystem test would false-pass.
  cl_init "$W/untracked"
  cl_put "$W/untracked" "docs/a.md" 'see `docs/ghost.md:2` for it\n'
  cl_add "$W/untracked"
  cl_put "$W/untracked" "docs/ghost.md" 'one\ntwo\n'
  cl_expect "an untracked-but-on-disk target fails (tracked-set resolution)" 1 "$W/untracked"
  cl_says  "and is classed UNRESOLVABLE" "UNRESOLVABLE" "$W/untracked"

  # ── AMBIGUOUS AFTER THE TIE-BREAKER -> UNRESOLVABLE, reported. Two equal-depth, equally-unpenalised
  # candidates: the tie-breaker refuses to guess.
  cl_init "$W/amb"
  cl_put "$W/amb" "docs/x/dup.md" 'one\ntwo\n'
  cl_put "$W/amb" "docs/y/dup.md" 'one\ntwo\n'
  cl_put "$W/amb" "docs/a.md" 'see `dup.md:2` for it\n'
  cl_add "$W/amb"
  cl_expect "an ambiguous bare basename fails" 1 "$W/amb"
  cl_says  "and says the tie-breaker did not decide" "the tie-breaker did not decide" "$W/amb"

  # ── THE TIE-BREAKER DECIDES when only the penalty separates the candidates (equal depth). Dropping
  # the penalty rule turns this leg into the UNRESOLVABLE above — which is how a dropped tie-breaker
  # is caught.
  cl_init "$W/tie"
  cl_put "$W/tie" "profiles/p/dup.md" 'only-one-line\n'
  cl_put "$W/tie" "docs/d/dup.md" 'one\ntwo\n'
  cl_put "$W/tie" "docs/a.md" 'see `dup.md:2` for it\n'
  cl_add "$W/tie"
  cl_expect "the tie-breaker resolves a penalised duplicate (profiles/ loses at equal depth)" 0 "$W/tie"
  cl_says  "and the resolved citation counts LIVE" "1 LIVE" "$W/tie"

  # ── DOTFILE (empty stem) IS GRADED, not ignored (design vet M-2).
  cl_init "$W/dot"
  cl_put "$W/dot" ".gitattributes" 'one\ntwo\n'
  cl_put "$W/dot" "docs/a.md" 'see `.gitattributes:99` for it\n'
  cl_add "$W/dot"
  cl_expect "a dotfile citation is graded (past EOF fails)" 1 "$W/dot"
  cl_says  "and the dotfile decay is classed DECAYED" "DECAYED" "$W/dot"

  # ── DATED SOURCE -> EXEMPT, counted. The dated file cites a line that does not exist; grading it
  # would red an immutable record. The living file keeps the domain non-empty.
  cl_init "$W/dsrc"
  cl_put "$W/dsrc" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/dsrc" "docs/a.md" 'see `docs/target.md:1` for it\n'
  cl_put "$W/dsrc" "docs/architecture/2026-01-02-old.md" 'it said `docs/target.md:900` back then\n'
  cl_add "$W/dsrc"
  cl_expect "a dated SOURCE citing a dead line does not fail the tree" 0 "$W/dsrc"
  cl_says  "and its exemption is REPORTED with an exact count" "1 EXEMPT-dated (sources 1/targets 0)" "$W/dsrc"

  # ── DATED TARGET -> EXEMPT, counted. A living doc anchoring INTO the record.
  cl_init "$W/dtgt"
  cl_put "$W/dtgt" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/dtgt" "docs/architecture/2026-01-02-old.md" 'one\n'
  cl_put "$W/dtgt" "docs/a.md" 'live `docs/target.md:1`, anchor `docs/architecture/2026-01-02-old.md:900`\n'
  cl_add "$W/dtgt"
  cl_expect "a dated TARGET citation does not fail the tree" 0 "$W/dtgt"
  cl_says  "and its exemption is REPORTED with an exact count" "1 EXEMPT-dated (sources 0/targets 1)" "$W/dtgt"

  # ── THE ADOPTER FACE (design vet H-1): the dated dirs are EXPORT-PRUNED, so the target does not
  # exist at all. The dated test runs on the CITATION STRING BEFORE resolution, so this is EXEMPT —
  # a resolve-first order would red every fresh adopter clone.
  cl_init "$W/pruned"
  cl_put "$W/pruned" "docs/target.md" 'one\n'
  cl_put "$W/pruned" "docs/a.md" 'live `docs/target.md:1`, anchor `2026-01-02-pruned.md:9`\n'
  cl_add "$W/pruned"
  cl_expect "a citation of an EXPORT-PRUNED dated basename is exempt, not unresolvable" 0 "$W/pruned"
  cl_says  "and is counted as a dated TARGET exemption" "(sources 0/targets 1)" "$W/pruned"
  # The needle is the DEFECT-LINE prefix, not the bare word: the summary line names every verdict
  # class as a counter label on every run, so a bare-word denial would be unsatisfiable.
  cl_denies "and is never reported as an UNRESOLVABLE defect" "UNRESOLVABLE  docs/a.md" "$W/pruned"

  # ── GLOB-QUALIFIED CITATIONS ARE NOT GRADED (review HIGH-1). `.github/workflows/*.yml:40` matched
  # the DOTFILE branch as the fragment `.yml:40` and reported an UNRESOLVABLE for a path nobody wrote;
  # `*.md:5` escaped only because "md" is under the dotfile minimum length — an accident, not a rule.
  # The glob metacharacters belong in the left-boundary class.
  cl_init "$W/glob"
  cl_put "$W/glob" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/glob" "docs/a.md" 'live `docs/target.md:2`; globs `.github/workflows/*.yml:40`, `**/*.yaml:7`, `profiles/*/ci.yml:301`, `docs/?.md:9`\n'
  cl_add "$W/glob"
  cl_expect "glob-qualified citations are NOT graded (no false red on a path nobody wrote)" 0 "$W/glob"
  cl_says  "and exactly the ONE real citation is counted" "1 LIVE" "$W/glob"
  cl_denies "and no glob fragment is reported as a defect" "UNRESOLVABLE  docs/a.md" "$W/glob"

  # ── A NON-ASCII TRACKED PATH IS SCANNED, NOT A WHOLE-TREE FAILURE (review HIGH-2). `git ls-files`
  # C-QUOTES non-ASCII names under the default core.quotePath=true, so the corpus listing carries a
  # literal `"docs/caf\303\251.md"` that getline cannot open — turning ONE unusual filename into
  # "the corpus could not be read" for the entire tree. The in-repo precedent is obligation-lib.sh's
  # changeset derivation; this leg kills a revert to a bare `git ls-files`.
  cl_init "$W/utf8"
  cl_put "$W/utf8" "docs/café.md" 'an accented filename, carrying no citations of its own\n'
  cl_put "$W/utf8" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/utf8" "docs/a.md" 'see `docs/target.md:2` for it\n'
  cl_add "$W/utf8"
  cl_expect "a non-ASCII tracked path does not break the corpus" 0 "$W/utf8"
  cl_says  "and it is ENUMERATED AND READ, not skipped (3 living files)" "3 living/0 dated" "$W/utf8"
  cl_denies "and no unreadable-corpus failure is raised" "could not be read" "$W/utf8"

  # ── AN UNREADABLE CORPUS FILE FAILS BY NAME (review MED-3). Tracked, then removed from disk:
  # `git ls-files` still lists it and getline cannot read it. Every other verdict names its site.
  cl_init "$W/unreadable"
  cl_put "$W/unreadable" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/unreadable" "docs/a.md" 'see `docs/target.md:1` for it\n'
  cl_put "$W/unreadable" "docs/gone.md" 'tracked now, deleted next\n'
  cl_add "$W/unreadable"
  rm -f "$W/unreadable/docs/gone.md"
  cl_expect "a tracked-but-unreadable corpus file FAILS" 1 "$W/unreadable"
  cl_says  "and the failure NAMES the unreadable path" "docs/gone.md" "$W/unreadable"

  # ── ARMED + ZERO CITATIONS -> FAIL. The kit-marked tree cannot legitimately have none.
  cl_init "$W/armedzero"
  cl_put "$W/armedzero" "docs/ROADMAP-KIT.md" 'no citations here\n'
  cl_put "$W/armedzero" "docs/a.md" 'still nothing to cite\n'
  cl_add "$W/armedzero"
  cl_expect "a KIT-MARKED tree with zero citations FAILS (never a vacuous green)" 1 "$W/armedzero"
  cl_says  "and says the domain is empty" "ZERO in-domain citations" "$W/armedzero"

  # ── ARMED + FAILED ENUMERATION -> FAIL, never N/A. The `.git` gitfile points nowhere, so
  # `git ls-files` fails no matter what encloses the fixture.
  cl_init "$W/armedbroken"
  cl_put "$W/armedbroken" "docs/ROADMAP-KIT.md" 'marked\n'
  cl_put "$W/armedbroken" "docs/a.md" 'see `docs/ROADMAP-KIT.md:1`\n'
  rm -rf "$W/armedbroken/.git"
  cl_put "$W/armedbroken" ".git" 'gitdir: /nonexistent-citation-live-fixture\n'
  cl_expect "a KIT-MARKED tree whose corpus enumeration FAILS is a FAIL, not an N/A" 1 "$W/armedbroken"
  cl_says  "and says so in the concealment-class language" "never an N/A" "$W/armedbroken"

  # ── UNARMED + ZERO CITATIONS -> N/A, and the LINE SHAPE must satisfy verify.sh's C6 classifier.
  cl_init "$W/na"
  cl_put "$W/na" "docs/a.md" 'a citation-free adopter document\n'
  cl_add "$W/na"
  cl_expect "an adopter tree with zero citations renders N/A (rc 0)" 0 "$W/na"
  cl_says  "and says N/A in the line-anchored idiom" "N/A: citation-live" "$W/na"
  # The predicate below is COPIED VERBATIM from verify.sh's is_self_skip (C6). If that idiom ever
  # changes, this leg is what tells us this check silently started rendering PASS instead of N-A.
  _o=$(cl_out "$W/na") || :
  if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
     ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
    echo "PASS: selftest -- the N/A output renders N-A under verify.sh's C6 classifier (never PASS)"
  else
    echo "FAIL: selftest -- the N/A output does NOT satisfy verify.sh's is_self_skip predicate"
    printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
  fi

  # ── THE OUT-OF-SCOPE CONTINUATION FORM IS COUNTED, NEVER GRADED.
  cl_init "$W/cont"
  cl_put "$W/cont" "docs/target.md" 'one\ntwo\n'
  cl_put "$W/cont" "docs/a.md" 'see `docs/target.md:1` and `:900` too\n'
  cl_add "$W/cont"
  cl_expect "a continuation-form citation is not graded" 0 "$W/cont"
  cl_says  "and is counted in the out-of-scope disclosure" "1 out-of-scope continuation-form" "$W/cont"

  if [ "$sfail" = 0 ]; then echo "OK: citation-live selftest (every verdict class asserted by name)"; exit 0; fi
  echo "FAIL: citation-live selftest"; exit 1
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
run; exit $?
