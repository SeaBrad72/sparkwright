#!/bin/sh
# runbook-current.sh — the kit's own release-pinned governing records (RUNBOOK.md and THREAT-MODEL.md)
# must exist and must still name the CURRENT release. C11 KIT-RUNBOOK; the second row added by A4 of
# KIT-EVAL-2-TIER-A (`D-240825-1`).
#
# WHY THIS EXISTS: measured at the C11 probe, this kit had NO RUNBOOK.md at all — its documented
# cold-start path ran entirely through one agent's private memory file, which is a friction-test
# failure (would the resume still work if the model stopped cooperating?). C11 authored the file.
# THIS CHECK IS THE RATCHET that keeps it alive and dated: a living operational doc decays the
# moment the tree moves past it, and the ONE fact in it that is mechanically checkable is which
# release it claims to describe. So the check holds exactly that fact, and says so.
#
# ── HONEST CEILING, STATED FIRST ────────────────────────────────────────────────────────────────────
# THE CHECK'S DOMAIN IS EXISTENCE + VERSION-CURRENCY OF THE TWO RELEASE-PINNED GOVERNING RECORDS,
# AND NOTHING ELSE.
#   · THE SECOND ROW IS THE THREAT MODEL, and it is here for a measured reason: THREAT-MODEL.md was
#     stamped 3.185.0 in its header and 3.186.0 in its footer against a VERSION of 3.218.0 — the one
#     document that says what the guard is FOR had no ratchet at all while the runbook had one. A
#     stale threat model does not merely rot; it launders residuals that were re-accepted against a
#     tree that no longer exists. Grading its stamp is the cheapest true thing a machine can say
#     about it, and the same honest ceiling below applies to it word for word.
#   · A WRONG RECOVERY STEP RENDERS GREEN. Every procedure in the RUNBOOK could be false and this
#     check would still pass; it never reads a single instruction. Content truth is held by review and
#     by the sibling living-doc gates (check-links, citation-live), never here. Do not quote this green
#     as "the runbook is correct" — it is not that claim and cannot be made into it.
#   · IT IS A VERSION RATCHET, NOT A FRESHNESS PROOF. Bumping the marker line in the release PR
#     satisfies it in one keystroke while every other section rots. That is the deliberate trade: a
#     mechanical signal that fires on EVERY release is worth more than a heuristic nobody can satisfy.
#     The honest statement is "someone touched this file at the current release", never "it is true".
#   · THE MARKER IS A CONVENTION, SO IT IS RENAMEABLE. Reword the marker line and the check FAILs
#     (absent marker), which is the safe direction — but an editor who reworded it deliberately can
#     also edit this file. The owner-reviewed diff is the control, as everywhere else in this suite.
#
# ── GRAMMAR (pinned) ────────────────────────────────────────────────────────────────────────────────
# THE MARKER LINE = a line whose first non-blank content is the literal `**Current release:**`. It must
# occur EXACTLY ONCE. A count of two is a FAIL even when BOTH copies are current: an any-line-match
# rule would let a stale copy sit forever beside a fresh one and still green, which is the exact
# concealment shape the unique-marker rule exists to close.
# THE VERSION TOKEN = the first whitespace-delimited word after the marker prefix. It must equal
# `v` + the contents of VERSION, byte for byte. Trailing prose on the same line is permitted (the line
# is a sentence in a document, not a machine record) — the TOKEN is what is graded.
#
# ── ARMING (fail-closed; the C3/C5/C7/C9/C10 kit-marker pattern) ────────────────────────────────────
# On a KIT tree (either export-ignored marker docs/ROADMAP-KIT.md or .github/workflows/golden-path.yml
# present) a missing RUNBOOK.md, a missing/duplicated/stale marker, or a dead VERSION is a FAIL — never
# an N/A. A check that quietly stands down when its own subject vanishes is the concealment class the
# arming block exists to close, and here the subject vanishing IS the defect the row was opened for.
# With NEITHER marker present (an adopter tree) the check renders an honest line-anchored `N/A:` and
# exits 0, UNCONDITIONALLY: RUNBOOK.md is `export-ignore`d, so an adopter's own RUNBOOK is stamped from
# templates/RUNBOOK-TEMPLATE.md and carries no current-release marker by design. Grading it would red
# every adopter for not following a convention the kit never shipped them.
#   ⚠️ CIRCULARITY, DISCLOSED (inherited from the shared marker pattern, not introduced here):
#   docs/ROADMAP-KIT.md is one of the two arming tokens AND a file this slice edits. Deleting it does
#   not red this check — it DISARMS it, silently, along with every other check on the same pair. The
#   second token (golden-path.yml) is why a single deletion is not enough to disarm.
#
# WIRED (pair pointers): conformance/verify.sh `check control runbook-current` (which also enrols this
# file in non-vacuity.sh's mutation sweep) · .github/workflows/ci.yml `docs-links` (the LIVE step, a
# required job with no `if:` so it survives the docs_only skip — a runbook-currency check governs
# exactly the `.md`-only PRs on which cf-verify-enforced is measured DEAD) · ci.yml
# `conformance-selftests` (--selftest).
# Usage: sh conformance/runbook-current.sh [--selftest]   (run from the repo root)
# Exit: 0 = the runbook exists and names the current release (or N/A off the kit tree) · 1 = a missing,
#       duplicated or stale marker / a dead input on an armed tree · 2 = bad usage. POSIX sh; dash-clean.
set -eu

SELFTEST=no
case "${1:-}" in
  "") : ;;
  --selftest) SELFTEST=yes ;;
  *) echo "usage: runbook-current.sh [--selftest]" >&2; exit 2 ;;
esac

RB=RUNBOOK.md
MARKER_RE='^[[:space:]]*\*\*Current release:\*\*'
# ── THE SECOND ROW OF THE MARKER TABLE (A4). Same grammar, same rules, a different file and prefix.
# The THREAT-MODEL marker is deliberately NOT line-anchored: it lives mid-sentence in the document's
# header line (`**System:** … **Kit version:** v3.218.0 · **Date:** …`), and forcing it to column 0
# would have meant reshaping the document to suit the check rather than the other way round.
TM=THREAT-MODEL.md
TM_MARKER_RE='\*\*Kit version:\*\*'

# ── THE VERDICT ENGINE ──────────────────────────────────────────────────────────────────────────────
# Reads RUNBOOK.md and VERSION RELATIVE TO THE CURRENT DIRECTORY — deliberately no `cd "$(dirname $0)"`,
# because the selftest fixtures below are throwaway trees the check is run inside. Every exit is driven
# by the single `_bad` accumulator, so the mutation sweep has one unambiguous fail-path token to neuter.
rb_verdict() {  # <armed 0|1>
  _armed=$1
  _bad=0
  _sep=$(printf '\302\267')          # U+00B7 MIDDLE DOT, the summary separator used kit-wide

  # ── THE ADOPTER FACE, and it is unconditional. See the arming note in the header.
  if [ "$_armed" -eq 0 ]; then
    echo "N/A: runbook-current -- no kit marker present (an adopter tree) and RUNBOOK.md is the kit's own operational doc. There is nothing to grade and no remedy to offer; this is not a pass."
    return "$_bad"
  fi

  # ── DEAD INPUT 1: VERSION. On an armed tree this is a FAIL, not a stand-down — a currency check
  # whose reference value evaporated is asserting nothing, and it must say so loudly.
  _ver=""
  if [ -f VERSION ]; then _ver=$(tr -d '[:space:]' < VERSION); fi
  if ! printf '%s' "$_ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "runbook-current: FAIL -- VERSION is absent or not semver (read: '$_ver') on a KIT-MARKED tree, so there is no reference release to grade $RB against. This is a FAILURE, never an N/A."
    _bad=1
    return "$_bad"
  fi

  # ── DEAD INPUT 2 AND THE GRADE ITSELF, once per governed record. Both files are graded on EVERY
  # run — no early return between them — so a green means both were read, and a run that reds on the
  # runbook still tells you whether the threat model is stale too. `_bad` remains the single
  # accumulator (the mutation sweep's one unambiguous fail-path token).
  rb_file_verdict "$RB" "$MARKER_RE" "current-release" 's/^.*Current release:\*\*[[:space:]]*//' || _bad=1
  rb_file_verdict "$TM" "$TM_MARKER_RE" "kit-version" 's/^.*Kit version:\*\*[[:space:]]*//' || _bad=1
  return "$_bad"
}

# rb_file_verdict <file> <marker_re> <marker_label> <strip_sed> — grade ONE release-pinned record
# against $_ver. Prints exactly one verdict line; returns 0 for OK, 1 for any failure. Reads $_ver and
# $_sep from the caller's scope (POSIX sh has no locals, and this is only ever called from rb_verdict
# on an armed tree that has already proved VERSION).
rb_file_verdict() {
  _f=$1; _mre=$2; _lbl=$3; _strip=$4

  if [ ! -f "$_f" ]; then
    echo "runbook-current: FAIL -- $_f is absent on a KIT-MARKED tree (VERSION $_sep v$_ver $_sep 0 marker line(s) $_sep 0 line(s) scanned). This is a FAILURE, never an N/A: the kit's release-pinned governing records are tracked files or they do not exist."
    return 1
  fi

  _lines=0
  _lines=$(grep -c '' "$_f") || _lines=0
  _n=0
  _n=$(grep -cE "$_mre" "$_f") || _n=0

  if [ "$_n" -eq 0 ]; then
    echo "runbook-current: FAIL -- $_f carries NO $_lbl marker line (expected exactly one line carrying the $_lbl prefix; VERSION is v$_ver $_sep 0 marker line(s) $_sep $_lines line(s) scanned). Without it nothing pins $_f to a release."
    return 1
  fi

  # UNIQUENESS BEFORE CURRENCY (vet MED-2). Two markers are a FAIL even when both are current: the
  # dangerous shape is a stale copy left beside a freshly-bumped one, and an any-line-match rule
  # greens on it forever. Counting first means that shape can never reach the currency test at all.
  # THREAT-MODEL.md is the measured instance, not a hypothetical: it carried a 3.185.0 header stamp
  # and a *different* 3.186.0 footer stamp at the same time.
  if [ "$_n" -gt 1 ]; then
    echo "runbook-current: FAIL -- $_f carries $_n $_lbl marker lines, expected exactly 1 (VERSION is v$_ver $_sep $_lines line(s) scanned). A duplicate lets a stale copy hide beside a fresh one."
    return 1
  fi

  _line=$(grep -E "$_mre" "$_f" | head -1)
  _tok=$(printf '%s\n' "$_line" | sed -e "$_strip" -e 's/[[:space:]].*$//')

  if [ "$_tok" != "v$_ver" ]; then
    echo "runbook-current: FAIL -- $_f declares release '$_tok' but VERSION says 'v$_ver' (1 marker line $_sep $_lines line(s) scanned). Bump $_f's $_lbl line in the release PR."
    return 1
  fi

  printf 'runbook-current: %s -- %s declares %s %s VERSION is v%s %s %d %s marker line(s) %s %d line(s) scanned %s existence and version-currency only: wrong content still renders green\n' \
    "OK" "$_f" "$_tok" "$_sep" "$_ver" "$_sep" "$_n" "$_lbl" "$_sep" "$_lines" "$_sep"
  return 0
}

run() {
  _a=0
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then _a=1; fi
  _rc=0
  rb_verdict "$_a" || _rc=$?
  return "$_rc"
}

# ---------------------------------------------------------------------------- selftest
# Every leg asserts the VERDICT CLASS, and every GREEN leg additionally asserts the PRINTED FIGURES —
# an rc alone would let a mutant that silently stops reading the marker cross-pass every positive leg.
# Fixtures are throwaway directories; this check shells out to nothing and reads no git state, so they
# need no `git init`.
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM

  rb_init() {  # <dir> — a fresh fixture tree, ARMED by default (the kit-marker file)
    rm -rf "$1"; mkdir -p "$1/docs"
    printf 'kit marker\n' > "$1/docs/ROADMAP-KIT.md"
  }
  rb_bare() {  # <dir> — a fresh fixture tree with NO kit marker (an adopter-shaped tree)
    rm -rf "$1"; mkdir -p "$1"
  }
  rb_put() {   # <dir> <relpath> <content with \n escapes>
    mkdir -p "$(dirname "$1/$2")"
    printf '%b' "$3" > "$1/$2"
  }
  rb_out() { ( cd "$1" && sh "$_self" ); }
  rb_expect() {  # <label> <want-rc> <dir>
    _rc=0; _o=$(rb_out "$3") || _rc=$?
    if [ "$_rc" = "$2" ]; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (want rc $2, got $_rc)"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  rb_says() {  # <label> <needle> <dir>
    _o=$(rb_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then echo "PASS: selftest -- $1"
    else echo "FAIL: selftest -- $1 (missing '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1; fi
  }
  rb_denies() {  # <label> <needle> <dir>
    _o=$(rb_out "$3") || :
    if printf '%s\n' "$_o" | grep -qF -- "$2"; then
      echo "FAIL: selftest -- $1 (unexpected '$2')"; printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
    else echo "PASS: selftest -- $1"; fi
  }

  # ── THE POSITIVE ORACLE. A runbook whose marker names the current VERSION. Without this leg an
  # always-red mutant would satisfy every negative leg below.
  rb_init "$W/current"
  rb_put "$W/current" "VERSION" "9.9.9\n"
  rb_put "$W/current" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9 (untagged mid-phase, by ruling)\n\nprose\n"
  rb_put "$W/current" "THREAT-MODEL.md" "# Threat model\n\n**System:** kit **Kit version:** v9.9.9 - **Date:** 2026-08-25\n"
  rb_expect "a runbook naming the current VERSION passes" 0 "$W/current"
  rb_says  "and the declared release is PRINTED, not merely accepted" "declares v9.9.9" "$W/current"
  rb_says  "and the VERSION it was graded against is printed too" "VERSION is v9.9.9" "$W/current"
  rb_says  "and the marker count is printed" "1 current-release marker line(s)" "$W/current"
  rb_says  "and the scanned size is printed" "5 line(s) scanned" "$W/current"
  rb_says  "and the SECOND governed record is graded and named too" "THREAT-MODEL.md declares v9.9.9" "$W/current"
  rb_denies "and the green never over-claims content truth" "FAIL" "$W/current"

  # ── THE SECOND MARKER FILE (A4). The kit shipped a THREAT-MODEL.md stamped 3.185.0 against a
  # VERSION of 3.218.0 — 33 minor releases and ~18 guard commits of drift in the one document that
  # says what the guard is FOR. The RUNBOOK had a ratchet and the threat model did not, so the fix is
  # to generalise this check's marker table rather than mint a second check (design §4).
  rb_init "$W/tm-stale"
  rb_put "$W/tm-stale" "VERSION" "9.9.9\n"
  rb_put "$W/tm-stale" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9\n"
  rb_put "$W/tm-stale" "THREAT-MODEL.md" "# Threat model\n\n**System:** kit **Kit version:** v1.0.0 - **Date:** old\n"
  rb_expect "a STALE THREAT-MODEL stamp FAILS even when the RUNBOOK is current" 1 "$W/tm-stale"
  rb_says  "and names the file and both figures" "THREAT-MODEL.md declares release 'v1.0.0'" "$W/tm-stale"

  rb_init "$W/tm-dup"
  rb_put "$W/tm-dup" "VERSION" "9.9.9\n"
  rb_put "$W/tm-dup" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9\n"
  rb_put "$W/tm-dup" "THREAT-MODEL.md" "# Threat model\n\n**Kit version:** v9.9.9\n\nfooter\n\n**Kit version:** v1.0.0\n"
  rb_expect "TWO kit-version markers FAIL (the header/footer double-stamp actually shipped)" 1 "$W/tm-dup"
  rb_says  "and the count is named" "carries 2" "$W/tm-dup"

  rb_init "$W/tm-none"
  rb_put "$W/tm-none" "VERSION" "9.9.9\n"
  rb_put "$W/tm-none" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9\n"
  rb_put "$W/tm-none" "THREAT-MODEL.md" "# Threat model\n\nno stamp anywhere\n"
  rb_expect "a THREAT-MODEL with NO kit-version marker FAILS on an armed tree" 1 "$W/tm-none"
  rb_says  "and names the missing convention" "carries NO kit-version marker line" "$W/tm-none"

  # ⚠️ EVERY ARMED FIXTURE BELOW CARRIES A CURRENT THREAT-MODEL.md, and that is not decoration.
  # Adding the second marker file made these six legs RC-OVER-DETERMINED: each would have returned 1
  # for its own reason AND for the missing threat model, so the rc no longer proved what the label
  # said and a regression in the RUNBOOK half could hide behind the THREAT-MODEL half. Round-2 review
  # caught it. Same discipline as the ADOPTER-EXPORT-WIRED-SWALLOWED-TEETH row: a negative fixture
  # that fails for many reasons proves none of them individually. (`deadver`/`badver` return early on
  # VERSION and are genuinely single-cause, so they are left alone.)

  # ── STALE MARKER -> FAIL. The row's entire reason for existing.
  rb_init "$W/stale"
  rb_put "$W/stale" "VERSION" "9.9.9\n"
  rb_put "$W/stale" "THREAT-MODEL.md" "# TM\n\n**Kit version:** v9.9.9\n"
  rb_put "$W/stale" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v1.0.0\n"
  rb_expect "a runbook naming a STALE release FAILS" 1 "$W/stale"
  rb_says  "and BOTH figures are named, never just the verdict" "declares release 'v1.0.0' but VERSION says 'v9.9.9'" "$W/stale"

  # ── DUPLICATE MARKERS -> FAIL, EVEN WHEN A CURRENT ONE IS PRESENT (vet MED-2). This is the leg that
  # forbids an any-line-match implementation: the fresh copy would satisfy it and the stale copy would
  # live on forever.
  rb_init "$W/dup"
  rb_put "$W/dup" "VERSION" "9.9.9\n"
  rb_put "$W/dup" "THREAT-MODEL.md" "# TM\n\n**Kit version:** v9.9.9\n"
  rb_put "$W/dup" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v1.0.0\n\nlater section\n\n**Current release:** v9.9.9\n"
  rb_expect "a stale marker sitting beside a CURRENT one FAILS" 1 "$W/dup"
  rb_says  "and the count is named" "carries 2 current-release marker lines" "$W/dup"

  # ── DUPLICATE CURRENT MARKERS -> FAIL TOO. Uniqueness is the rule, not a proxy for staleness: two
  # correct copies still mean two places to forget to bump.
  rb_init "$W/dup2"
  rb_put "$W/dup2" "VERSION" "9.9.9\n"
  rb_put "$W/dup2" "THREAT-MODEL.md" "# TM\n\n**Kit version:** v9.9.9\n"
  rb_put "$W/dup2" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9\n\n**Current release:** v9.9.9\n"
  rb_expect "TWO CURRENT markers still FAIL (uniqueness, not staleness, is the rule)" 1 "$W/dup2"
  rb_says  "and the count is named" "carries 2 current-release marker lines" "$W/dup2"

  # ── MARKER ABSENT -> FAIL. A runbook with no release anchor is ungradeable, and on an armed tree an
  # ungradeable subject is a failure rather than a shrug.
  rb_init "$W/nomarker"
  rb_put "$W/nomarker" "VERSION" "9.9.9\n"
  rb_put "$W/nomarker" "THREAT-MODEL.md" "# TM\n\n**Kit version:** v9.9.9\n"
  rb_put "$W/nomarker" "RUNBOOK.md" "# RUNBOOK\n\nno anchor here at all\n"
  rb_expect "a runbook with NO marker line FAILS on an armed tree" 1 "$W/nomarker"
  rb_says  "and names the missing convention" "carries NO current-release marker line" "$W/nomarker"
  rb_says  "and still prints the figures it did measure" "3 line(s) scanned" "$W/nomarker"

  # ── ARMED + RUNBOOK.md ABSENT -> FAIL, never N/A. The C11 pre-slice state, pinned forever.
  rb_init "$W/missing"
  rb_put "$W/missing" "VERSION" "9.9.9\n"
  rb_put "$W/missing" "THREAT-MODEL.md" "# TM\n\n**Kit version:** v9.9.9\n"
  rb_expect "a KIT-MARKED tree with NO RUNBOOK.md FAILS" 1 "$W/missing"
  rb_says  "and says so in the concealment-class language" "never an N/A" "$W/missing"
  rb_says  "and names RUNBOOK.md as the absent file, not the other record" "RUNBOOK.md is absent" "$W/missing"

  # ── ARMED + THREAT-MODEL.md ABSENT -> FAIL, never N/A. The mirror of the leg above, and the state
  # the kit itself was in until this slice: the document defining what the guard is FOR simply not
  # being there must be a failure, not a silent stand-down (`KIT-SELF-THREAT-MODEL`).
  rb_init "$W/tm-missing"
  rb_put "$W/tm-missing" "VERSION" "9.9.9\n"
  rb_put "$W/tm-missing" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9\n"
  rb_expect "a KIT-MARKED tree with NO THREAT-MODEL.md FAILS" 1 "$W/tm-missing"
  rb_says  "and names THE THREAT MODEL as the absent file" "THREAT-MODEL.md is absent" "$W/tm-missing"
  rb_says  "and says so in the concealment-class language" "never an N/A" "$W/tm-missing"

  # ── ARMED + DEAD VERSION -> FAIL (vet MED-3, the roadmap-current dead-input precedent). A currency
  # check whose reference value vanished must not green over the hole.
  rb_init "$W/deadver"
  rb_put "$W/deadver" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v9.9.9\n"
  rb_expect "a KIT-MARKED tree with NO VERSION file FAILS" 1 "$W/deadver"
  rb_says  "and names the dead input" "VERSION is absent or not semver" "$W/deadver"

  rb_init "$W/badver"
  rb_put "$W/badver" "VERSION" "not-a-version\n"
  rb_put "$W/badver" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** vnot-a-version\n"
  rb_expect "a KIT-MARKED tree with a NON-SEMVER VERSION FAILS (a matching marker cannot rescue it)" 1 "$W/badver"
  rb_says  "and quotes what it actually read" "read: 'not-a-version'" "$W/badver"

  # ── THE SECOND ARMING TOKEN holds the tree on its own. A single deletion must not disarm.
  rm -rf "$W/token2"; mkdir -p "$W/token2/.github/workflows"
  printf 'name: golden-path\n' > "$W/token2/.github/workflows/golden-path.yml"
  rb_put "$W/token2" "VERSION" "9.9.9\n"
  rb_put "$W/token2" "THREAT-MODEL.md" "# TM\n\n**Kit version:** v9.9.9\n"
  rb_expect "the golden-path.yml marker ALONE still arms the check (no ROADMAP-KIT.md)" 1 "$W/token2"
  rb_says  "and it fails as an armed tree, not as an adopter one" "never an N/A" "$W/token2"

  # ── UNARMED -> N/A, UNCONDITIONALLY, and the LINE SHAPE must satisfy verify.sh's C6 classifier.
  # This is the ADOPTER FACE: an export carries no kit marker, and the adopter's own RUNBOOK is
  # stamped from the template with no current-release marker at all.
  rb_bare "$W/na"
  rb_expect "an adopter tree with neither marker nor runbook renders N/A (rc 0)" 0 "$W/na"
  rb_says  "and says N/A in the line-anchored idiom" "N/A: runbook-current" "$W/na"
  rb_says  "and gives the honest reason" "RUNBOOK.md is the kit's own operational doc" "$W/na"

  # ── UNARMED + A STALE RUNBOOK -> STILL N/A. The adopter face is unconditional by design: an adopter
  # who keeps a RUNBOOK.md is not held to the kit's private marker convention.
  rb_bare "$W/nastale"
  rb_put "$W/nastale" "VERSION" "9.9.9\n"
  rb_put "$W/nastale" "RUNBOOK.md" "# RUNBOOK\n\n**Current release:** v1.0.0\n"
  rb_expect "an adopter tree carrying a STALE marker is still N/A, never red" 0 "$W/nastale"
  rb_denies "and never renders a FAIL at an adopter" "FAIL" "$W/nastale"

  # ── UNARMED + A STALE THREAT-MODEL -> STILL N/A. Adopters stamp their own threat model from
  # templates/THREAT-MODEL-TEMPLATE.md and are not held to the kit's private marker convention. The
  # adopter face must stay unconditional across BOTH marker files, or generalising the table would
  # have quietly started redding adopter trees for a document the kit never shipped them.
  rb_bare "$W/natm"
  rb_put "$W/natm" "VERSION" "9.9.9\n"
  rb_put "$W/natm" "THREAT-MODEL.md" "# Threat model\n\n**Kit version:** v1.0.0\n"
  rb_expect "an adopter tree with a STALE THREAT-MODEL stamp is still N/A" 0 "$W/natm"
  rb_denies "and never renders a FAIL at an adopter's threat model" "FAIL" "$W/natm"

  # The predicate below is COPIED VERBATIM from verify.sh's is_self_skip (C6). If that idiom ever
  # changes, this leg is what tells us this check silently started rendering PASS instead of N-A.
  _o=$(rb_out "$W/na") || :
  if printf '%s\n' "$_o" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' &&
     ! printf '%s\n' "$_o" | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'; then
    echo "PASS: selftest -- the N/A output renders N-A under verify.sh's C6 classifier (never PASS)"
  else
    echo "FAIL: selftest -- the N/A output does NOT satisfy verify.sh's is_self_skip predicate"
    printf '%s\n' "$_o" | sed 's/^/    /'; sfail=1
  fi

  if [ "$sfail" = 0 ]; then echo "OK: runbook-current selftest (every verdict class asserted, the green leg pinned to its printed figures)"; exit 0; fi
  echo "FAIL: runbook-current selftest"; exit 1
}

# ---------------------------------------------------------------------------- dispatch
if [ "$SELFTEST" = yes ]; then selftest; exit $?; fi
run; exit $?
