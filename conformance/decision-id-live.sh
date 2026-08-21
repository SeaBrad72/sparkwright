#!/bin/sh
# decision-id-live.sh — every `D-YYMMDD-N` ruling id cited in the kit's LIVING Markdown must name a
# ruling that ACTUALLY EXISTS. DANGLING-DECISION-ID-CITES (the citation-live family, one level up).
#
# WHY THIS EXISTS: a `D-*` ruling id is the strongest form of authority this kit has — a row, a design
# or a header cites it to say "this was decided". citation-live.sh (C9) gates whether a cited *line*
# still exists; NOTHING gated whether a cited *ruling* ever existed. Measured at the boarding probe
# (docs/architecture/2026-08-16-decision-id-live-substrate.md), a `D-*` id was unforgeable only by
# convention: a living doc could carry an authority-shaped token to a ruling that was never recorded,
# and no check would red it. This is that gate.
#
# ── HONEST CEILING, STATED FIRST (Decision C / Q3) ──────────────────────────────────────────────────
# THIS IS THE *PARENT-EXISTENCE* VARIANT: it proves the cited ruling's HEADER exists in DECISIONS.md,
# never that the specific sub-item number is a real item in that block, and never that the ruling's
# SUBSTANCE matches the citing claim. A cite to `D-240813-4.99` (parent `D-240813-4` exists, item 99
# does not) PASSES. Verifying item numbers means prose-parsing free-text "1. … 2. …" enumerations —
# fragile, and a standing veto shape in this kit (the same reason C9 resolves to a line's existence,
# not its meaning). The check catches a FABRICATED RULING, not a fabricated sub-item, and says so.
# This matches the sanctioned-commands.tsv:54 precedent: bind via the parent header, never the `.N`.
#
# ── DOMAIN (the load-bearing simplification) ────────────────────────────────────────────────────────
# SOURCES = tracked `*.md` files (`git -c core.quotePath=false ls-files -- "*.md"`). This drops every
# `.sh` conformance source and every throwaway `git init` selftest tree automatically — they are never
# `git ls-files`-tracked — so NO bespoke fixture-exclusion list is needed. The fabricated ids that live
# only in shell fixtures (D-240815-1 in ceremony-binding.sh's `$W` tree, D-FIX-1 in
# permission-surface-audit.sh, the D-240813-41 prefix-collision comment) are out of this domain by
# construction, exactly as C9's `.md`-only choice already solves the same hazard.
# EXEMPT-and-REPORTED: the dated record (is_dated() below — docs/architecture/20*, docs/plans/20*,
# docs/plans/brief-*, CHANGELOG.md, meta-control-log.md, ^20NN-*.md, ^brief-*.md). A dated document
# cites a ruling that was correct against the tree of its own date; grading it against today HEAD is a
# category error and "repairing" it would rewrite the record (the C9 dated-record principle). Only a
# LIVING doc's dangling cite REDs. The dated test runs on the source PATH, before membership, and the
# exempt count PRINTS ON EVERY RUN — the exemption is never silent.
#
# ── GRAMMAR + FOLD (pinned) ─────────────────────────────────────────────────────────────────────────
# A citation is a `D-[0-9]{6}-[0-9]+(\.[0-9]+)?` token. A dotted sub-id `.N` is FOLDED to its parent
# `D-YYMMDD-N` before membership (the sanctioned-commands.tsv:54 precedent — sub-ids never get their
# own header; they live inside the parent block, and `D-240811-2.5` is "no header block and would not
# bind" on its own). A naive literal check would red `D-240813-4.5` (zero literal headers) though its
# parent `D-240813-4` resolves and item 5 is enumerated — the fold is what makes the AC's 2 -> 0 true
# BY RESOLUTION, with no transcription.
#
# ── MEMBERSHIP ──────────────────────────────────────────────────────────────────────────────────────
# The folded id must appear as a real `**`D-YYMMDD-N`` header in docs/governance/DECISIONS.md, matched
# as a FIXED string anchored at column 1 (index()==1) exactly as permission-surface-audit.sh's
# psa_ruling_block does — so a prefix collision (D-240813-4 vs D-240813-41) cannot match, and the FIRST
# backtick-delimited token on the line is the id (a header line may name a second ruling in its prose).
# Absent parent header -> the citation DANGLES.
#
# ── REVERSE DIRECTION (Decision B / Q2): REPORT-ONLY, NEVER RED ──────────────────────────────────────
# A DECISIONS.md entry that no document cites is NOT a defect — a ruling can be self-standing, and most
# are not cross-cited. The uncited-entry count PRINTS as an informational line (like C9's EXEMPT
# counts) but NEVER reds. Gating it would manufacture busywork citations, the opposite of this check's
# honesty.
#
# ── THE EXAMPLE-TOKEN HAZARD (Decision A / Q1): NO SPECIAL EXEMPTION ─────────────────────────────────
# A living `.md` token shaped exactly like an authority citation to a non-existent ruling is PRECISELY
# what this check exists to red. Carving an example-exemption (a sentinel D-9999* range, a "negated
# context" heuristic) would reopen the hole — both real and example cites are backticked; there is no
# reliable textual signal. The fix for such a token is to REWORD the living prose to a non-matching
# form, never to exempt it. The fabricated ids used to test this check live only in (i) this slice's
# dated design [exempt] and (ii) the selftest's throwaway trees [untracked].
#
# ── ARMING (kit-self; the permission-surface-audit precedent) ───────────────────────────────────────
# `D-YYMMDD-N` ruling ids are the KIT'S OWN governance vocabulary — an adopter's docs do not cite them,
# and DECISIONS.md carries the kit's record, not the adopter's. (Since TRIAL-PREP-FIRST-MILE the kit's
# copy is export-ignored outright and an adopter is stamped an EMPTY ledger at Inception, which makes
# the arming below not merely correct but necessary: on an adopter tree the membership set really is
# empty, and grading citations against it would red every tree that ever quotes an id.) So this is
# a KIT-SELF check: with NEITHER export-ignored marker present (docs/ROADMAP-KIT.md /
# .github/workflows/golden-path.yml) it renders the honest line-anchored `N/A:` that verify.sh's C6
# is_self_skip classifier accepts, before reading a thing. On a KIT tree it is FAIL-CLOSED: a
# failed/empty `*.md` enumeration, an unreadable/empty DECISIONS.md, or ZERO in-domain citations is a
# FAIL (the kit carries ~40 cited ids and 26 headers, so zero means the extractor or the enumeration
# broke, and a git failure must never silently render N/A). THE RATCHET IS INTENDED: a future
# fabricated ruling cite in a living doc reds `docs-links`.
#
# WIRED (pair pointers): verify.sh `check control decision-id-live` (which also enrols this file in
# non-vacuity.sh's mutation sweep) · .github/workflows/ci.yml `docs-links` (the LIVE step, a required
# job with no `if:` so it survives the docs_only skip) · ci.yml `conformance-selftests` (--selftest).
# Usage: sh conformance/decision-id-live.sh [--selftest]   (run from the repo root)
# Exit: 0 = every in-domain citation resolves (or N/A off the kit tree) · 1 = a dangling cite / a
#       broken corpus or DECISIONS.md on a KIT tree · 2 = bad usage. POSIX sh + one awk pass; dash-clean.
set -eu

DEC=docs/governance/DECISIONS.md

SELFTEST=no
case "${1:-}" in
  "") : ;;
  --selftest) SELFTEST=yes ;;
  *) echo "usage: decision-id-live.sh [--selftest]" >&2; exit 2 ;;
esac

# ── THE SINGLE AWK PASS ─────────────────────────────────────────────────────────────────────────────
# One process for the whole corpus (C9's shape, its 23x reason). ARGV[1] is the `*.md` source listing;
# DECISIONS.md is read once via getline in BEGIN to build the membership set. Every source is read with
# getline, so nothing shells out and no file is opened twice.
did_awk() {  # <md-listing> <DECISIONS.md path>   (run() guarantees the tree is kit-armed)
  LC_ALL=C awk -v dec="$2" '
    BEGIN {
      sep = "·"
      # Build the membership set from DECISIONS.md headers. Fixed-string column-1 anchor, FIRST
      # backtick-delimited token — the psa_ruling_block idiom, immune to a header naming a second
      # ruling in its own prose.
      nhdr = 0; decread = 0
      while ((getline dl < dec) > 0) {
        decread = 1
        if (index(dl, "**`D-") == 1) {
          h = dl; sub(/^\*\*`/, "", h); sub(/`.*/, "", h)
          if (!(h in hdr)) { hdr[h] = 1; nhdr++ }
        }
      }
      close(dec)
    }
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
    # fold a dotted sub-id .N to its parent D-YYMMDD-N (a real header form).
    function parent(tok,   p) { p = tok; sub(/\.[0-9]+$/, "", p); return p }
    # scan one source line for D-* tokens. dsrc = the source is a dated record (exempt-and-counted).
    function scan(ln, f, lno, dsrc,   line, tok, par) {
      line = ln
      while (match(line, /D-[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9]+(\.[0-9]+)?/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        par = parent(tok)
        cited[par] = 1
        if (dsrc) { exempt++; continue }
        cites++
        nsite++
        site_src[nsite] = f ":" lno
        site_tok[nsite] = tok
        site_par[nsite] = par
      }
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
      if (r < 0) { readerr++; badread = badread " " f }
    }
    END {
      # DECISIONS.md itself must have been readable and non-empty on an armed tree — the authority
      # source going missing is a FAIL, never a silent green over an empty membership set.
      if (readerr > 0) {
        print "decision-id-live: FAIL -- " readerr " source file(s) could not be read, so the judgement would be over an unknown subset. Unreadable:" badread
        exit 1
      }
      if (decread == 0 || nhdr == 0) {
        print "decision-id-live: FAIL -- the ruling record " dec " is missing, unreadable or carries ZERO `**`D-...`` headers on a KIT-MARKED tree. The kit records 26; zero means the authority source is gone, and grading citations against an empty membership set would red every ruling id on the tree."
        exit 1
      }
      # PASS 2 — judge every living-source citation against the membership set, in source order.
      for (i = 1; i <= nsite; i++) {
        if (site_par[i] in hdr) { live++; continue }
        dangling++
        print "DANGLING  " site_src[i] " cites " site_tok[i] " -- no ruling header " site_par[i] " in " dec " (folded parent absent)"
      }
      # Q2 REPORT-ONLY: count DECISIONS entries that no source cites. Never reds.
      uncited = 0
      for (h in hdr) { if (!(h in cited)) uncited++ }
      if (cites == 0) {
        print "decision-id-live: FAIL -- ZERO in-domain decision-id citations across " nliving " living Markdown file(s) on a KIT-MARKED tree. The kit cites ~40; zero means the extractor or the corpus enumeration is dead, and a green over an empty domain asserts nothing."
        exit 1
      }
      res = (dangling == 0) ? "OK" : "FAIL"
      printf "decision-id-live: %s -- %d LIVE %s %d DANGLING %s %d EXEMPT-dated citation(s) %s %d ruling header(s), %d uncited (report-only) %s %d living/%d dated .md file(s) scanned\n", \
        res, live, sep, dangling, sep, exempt, sep, nhdr, uncited, sep, nliving, ndated
      if (res == "OK") exit 0
      exit 1
    }
  ' "$1"
}

run() {
  # KIT-SELF (the permission-surface-audit precedent): `D-YYMMDD-N` ruling ids are the kit's OWN
  # governance vocabulary. With NEITHER export-ignored marker present (an adopter tree) there is
  # nothing here to grade — the adopter's own docs do not cite the kit's ruling ids — so this renders
  # the line-anchored `N/A:` that verify.sh's C6 is_self_skip classifier accepts, BEFORE reading a
  # thing. On a KIT tree the check is fail-closed: from here down, every empty/broken input is a FAIL.
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "N/A: decision-id-live -- no kit marker present (an adopter tree). The D-YYMMDD-N ruling ids this check grades are the kit's own governance vocabulary; there is nothing to grade here and no remedy to offer. This is not a pass."
    return 0
  fi

  _w=$(mktemp -d) || { echo "decision-id-live: FAIL -- could not create a work directory"; return 1; }
  trap 'rm -rf "$_w"' EXIT INT TERM

  _enum=1
  # `-c core.quotePath=false` IS LOAD-BEARING (C9's HIGH-2): a non-ASCII tracked path is C-QUOTED under
  # git's default quotePath=true, and awk's getline cannot open the quoted literal — one accented name
  # would turn this check into "the corpus could not be read" for the whole tree. A selftest leg holds it.
  git -c core.quotePath=false ls-files -- "*.md" > "$_w/md" 2>/dev/null || _enum=0
  [ -s "$_w/md" ] || _enum=0
  if [ "$_enum" = 0 ]; then
    echo "decision-id-live: FAIL -- the Markdown corpus could not be enumerated (git ls-files failed or returned nothing) on a KIT-MARKED tree. This is a FAILURE, never an N/A: a check that quietly stands down when its own input is missing is the concealment class the arming block exists to close."
    return 1
  fi

  _rc=0
  did_awk "$_w/md" "$DEC" || _rc=$?
  return "$_rc"
}

# ---------------------------------------------------------------------------- selftest
# Every leg asserts the VERDICT CLASS WORD (LIVE / DANGLING / EXEMPT / N/A), not just an rc, so a
# branch-collapse mutant that reds for the wrong reason cannot cross-pass (C9's L-3). Fixtures are
# throwaway `git init` trees — no commit, so no ambient git identity or repo state is read. The
# non-vacuity sweep mutates ONLY lines BEFORE the `selftest()` marker; the fixtures live after it.
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  dl_init() {  # <dir> — a fresh, EMPTY fixture repo (never a clone of the surrounding tree)
    rm -rf "$1"; mkdir -p "$1"
    ( cd "$1" && git init -q . >/dev/null 2>&1 )
  }
  dl_put() {   # <dir> <relpath> <content with \n escapes>
    mkdir -p "$(dirname "$1/$2")"
    printf '%b' "$3" > "$1/$2"
  }
  dl_add() { ( cd "$1" && git add -A . >/dev/null 2>&1 ); }
  dl_out() { ( cd "$1" && sh "$_self" 2>&1 ); }
  dl_expect() {  # <label> <want-rc> <dir>
    _rc=0; _o=$(dl_out "$3") || _rc=$?
    if [ "$_rc" = "$2" ]; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (want rc $2, got $_rc)"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  dl_says() {  # <label> <needle> <dir>
    _o=$(dl_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (missing '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  dl_denies() {  # <label> <needle> <dir>
    _o=$(dl_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then
      echo "FAIL: selftest -- $1 (unexpected '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
    else echo "PASS: selftest -- $1"; fi
  }

  # A fixture DECISIONS.md carrying two real headers. The header form is the psa_ruling_block shape:
  # `**`D-...`` anchored at column 1, backtick-delimited.
  _DEC='**`D-240815-1` · ruling · a recorded sitting\n\n**`D-240813-4` · sitting · items 1-6\n'

  # ── LIVENESS ANCHOR. Without a positive leg an always-red mutant satisfies every negative below.
  dl_init "$W/live"
  dl_put "$W/live" "docs/ROADMAP-KIT.md" 'kit marker\n'
  dl_put "$W/live" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/live" "docs/a.md" 'per `D-240815-1` the sitting stands\n'
  dl_add "$W/live"
  dl_expect "a live decision-id citation passes" 0 "$W/live"
  # 3 LIVE = the a.md cite + the two fixture DECISIONS.md headers, which are themselves D-* tokens that
  # self-resolve when DECISIONS.md is scanned as a source (correct, and harmless — they always resolve).
  dl_says  "and is counted LIVE" "3 LIVE" "$W/live"

  # ── DANGLING RED. A living doc cites a fabricated ruling with no header -> rc 1, names id + file.
  dl_init "$W/dangle"
  dl_put "$W/dangle" "docs/ROADMAP-KIT.md" 'kit marker\n'
  dl_put "$W/dangle" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/dangle" "docs/a.md" 'per `D-999999-9` this authority is fabricated\n'
  dl_add "$W/dangle"
  dl_expect "a fabricated decision-id in a living doc fails" 1 "$W/dangle"
  dl_says  "and is classed DANGLING" "DANGLING" "$W/dangle"
  dl_says  "naming the fabricated id" "D-999999-9" "$W/dangle"
  dl_says  "and naming the citing file" "docs/a.md" "$W/dangle"

  # ── DOTTED-SUB-ID FOLD PASS. A living doc cites `D-240813-4.5` with only a `**`D-240813-4`` header:
  # folding .5 to the parent PASSES. A naive literal check reds this — this leg is the fold's pin.
  dl_init "$W/fold"
  dl_put "$W/fold" "docs/ROADMAP-KIT.md" 'kit marker\n'
  dl_put "$W/fold" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/fold" "docs/a.md" 'condition `D-240813-4.5` routes the ledger\n'
  dl_add "$W/fold"
  dl_expect "a dotted sub-id folds to its parent header and passes" 0 "$W/fold"
  dl_says  "and the folded citation counts LIVE" "3 LIVE" "$W/fold"
  # The two-space prefix is the DEFECT-LINE shape; the summary's "0 DANGLING" has a single space, so a
  # bare-word deny would be unsatisfiable (the class word labels a summary counter on every run).
  dl_denies "and is never reported as a DANGLING defect" "DANGLING  " "$W/fold"

  # ── DATED-EXEMPT. The SAME fabricated id inside a dated design does not fail the tree; it is
  # counted EXEMPT. A living cite keeps the domain non-empty.
  dl_init "$W/dated"
  dl_put "$W/dated" "docs/ROADMAP-KIT.md" 'kit marker\n'
  dl_put "$W/dated" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/dated" "docs/a.md" 'per `D-240815-1` the sitting stands\n'
  dl_put "$W/dated" "docs/architecture/2099-01-01-x.md" 'back then `D-999999-9` was the shorthand\n'
  dl_add "$W/dated"
  dl_expect "a fabricated id inside a DATED record does not fail the tree" 0 "$W/dated"
  dl_says  "and the dated citation is counted EXEMPT" "1 EXEMPT-dated" "$W/dated"
  dl_denies "and the dated cite is never a DANGLING defect" "DANGLING  " "$W/dated"

  # ── FIXTURE-DOMAIN PIN. A `.sh` source writing a fabricated id is NOT graded (the `.md`-only
  # domain drops it). The anchor tree with such a `.sh` still passes.
  dl_init "$W/shdomain"
  dl_put "$W/shdomain" "docs/ROADMAP-KIT.md" 'kit marker\n'
  dl_put "$W/shdomain" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/shdomain" "docs/a.md" 'per `D-240815-1` the sitting stands\n'
  dl_put "$W/shdomain" "conformance/fixture.sh" 'printf "%s" "D-999999-9" >> ledger\n'
  dl_add "$W/shdomain"
  dl_expect "a fabricated id in a .sh source is not graded (.md-only domain)" 0 "$W/shdomain"
  dl_says  "and only the living .md citations count LIVE" "3 LIVE" "$W/shdomain"
  dl_denies "and the .sh fabricated id never reds" "DANGLING  " "$W/shdomain"

  # ── ARMING, ADOPTER FACE: no kit marker -> N/A rc 0, in the line-anchored idiom C6 renders N-A.
  dl_init "$W/na"
  dl_put "$W/na" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/na" "docs/a.md" 'per `D-999999-9` even a fabricated id is not graded off the kit tree\n'
  dl_add "$W/na"
  dl_expect "an adopter tree (no kit marker) renders N/A (rc 0) even with a fabricated id" 0 "$W/na"
  dl_says  "and says N/A in the line-anchored idiom" "N/A: decision-id-live" "$W/na"
  # COPIED VERBATIM from verify.sh's is_self_skip (C6): if that idiom changes, this leg tells us this
  # check silently started rendering PASS instead of N-A.
  _o=$(dl_out "$W/na") || :
  if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
     ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
    echo "PASS: selftest -- the N/A output renders N-A under verify.sh's C6 classifier (never PASS)"
  else
    echo "FAIL: selftest -- the N/A output does NOT satisfy verify.sh's is_self_skip predicate"
    printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
  fi

  # ── ARMING, KIT FACE: one marker + a dangling living cite -> rc 1 (not always-N/A). The complement
  # of the adopter leg: the same fabricated id that is ignored off the kit tree REDS on it.
  dl_init "$W/armed"
  dl_put "$W/armed" ".github/workflows/golden-path.yml" 'name: golden-path\n'
  dl_put "$W/armed" "docs/governance/DECISIONS.md" "$_DEC"
  dl_put "$W/armed" "docs/a.md" 'per `D-999999-9` this fabricated id must red on the kit tree\n'
  dl_add "$W/armed"
  dl_expect "a KIT-MARKED tree reds a dangling living cite" 1 "$W/armed"
  dl_says  "and classes it DANGLING" "DANGLING" "$W/armed"

  if [ "$sfail" = 0 ]; then echo "OK: decision-id-live selftest (every verdict class asserted by name)"; exit 0; fi
  echo "FAIL: decision-id-live selftest"; exit 1
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
run; exit $?
