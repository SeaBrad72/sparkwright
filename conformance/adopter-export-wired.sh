#!/bin/sh
# adopter-export-wired.sh — regression-lock for the S3 adopter-clean obtain mechanism.
# Asserts: the export mechanism exists, the .gitattributes export-ignore set is present, the set is
# LINK-SAFE (no export-ignored path is a `](path)` markdown-link target from a KEPT doc; links
# BETWEEN export-ignored docs are fine — both ends prune together), the export is CI-green: fixtures
# ship, STACK-SELECTION is stubbed on `--profile`, no broken links, AND the exported tree's own
# claims-registry passes (orphaned-maintainer-only-claim guard).
#   sh conformance/adopter-export-wired.sh [--selftest]
# Exit: 0 = wired + link-safe + CI-green · 1 = regression · 2 = setup. POSIX sh; dash-clean.
set -eu
_here=$(CDPATH='' cd "$(dirname "$0")" && pwd)   # resolve dir BEFORE cd so sourcing is cwd-independent
cd "$_here/.."
. "$_here/wf-helpers.sh"   # provides wf_extract_links() (single source of truth)
# Kill git auto-gc for this check + ALL subprocesses (the nested verify, adopter-export, and the
# selftest fixtures): a commit's detached `git gc --auto` keeps writing to .git after it returns,
# racing the temp `rm -rf` into ENOTEMPTY under CI load (green locally/PR, red on the loaded
# main-push runner). Env-scoped (no global mutation), additive (only forces gc.auto=0). Root-cause
# hygiene for every cleanup site at once; the `|| true` on each rm below is the hard guarantee.
# The structural refactor (isolate this green-on-clone verify into its own job) is boarded: Phase 1.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=gc.auto
export GIT_CONFIG_VALUE_0=0
ROOT="${EXPORT_ROOT:-.}"

# the export-ignore set this lock enforces (must match .gitattributes)
# BACKLOG.md + SPARKWRIGHT-CONSOLIDATED-BACKLOG.md (KW6-A2): the kit's work board + roadmap table are
# export-ignored so incept.sh:344's `[ -f BACKLOG.md ] ||` guard still stamps each adopter their OWN board.
# NOTE: this list is a SECOND SOURCE for the export-ignore set declared in .gitattributes. They must
# agree — adding an `export-ignore` there without adding it here leaves the new path scanned as a KEPT
# doc, so its (legitimate) links to other export-ignored files FAIL this check even though the real
# export excludes it. That is exactly how docs/plans/ reddened this gate: Slice 3 moved plans to a
# tracked location, the first plan doc landed there, and it cited ci.yml / golden-path.yml / a design
# doc — all correct, all export-ignored.
# The two drift directions are NOT symmetric, and only one is already enforced — know which:
#   * IGN entry NOT export-ignored (the dangerous, fail-OPEN direction: the path ships to adopters while
#     this check skips its links as "not a KEPT doc") is ALREADY caught by block (a) below, which
#     requires every IGN entry to carry the attribute in .gitattributes. Measured, not assumed.
#   * export-ignored but NOT in IGN (loud): reddens the link scan, self-announcing — that is exactly how
#     docs/plans/ was caught. Deliberately NOT asserted as set-equality: .gitattributes legitimately
#     export-ignores paths IGN has no reason to carry (.github/dependabot.yml, ROADMAP.md,
#     KIT-FEEDBACK.md, scratchpad/**), and requiring equality produces 5 false FAILs on this tree.
# The true relation is IGN ⊆ export-ignored, block (a) is what enforces it, and a separate equality
# check here would be fully shadowed by it — dead defense-in-depth, removed rather than kept.
IGN="docs/ROADMAP-KIT.md .github/workflows/ci.yml .github/workflows/ratification.yml .github/workflows/release-coherence.yml .github/workflows/drift-watch.yml .github/workflows/golden-path.yml docs/superpowers/ .superpowers/ .github/CODEOWNERS docs/architecture/ docs/plans/ docs/governance/meta-control-log.md docs/governance/.meta-control-last BACKLOG.md SPARKWRIGHT-CONSOLIDATED-BACKLOG.md CHANGELOG.md .publish-identifiers"

# _no_shipped_workflows <exported-tree> -> 0 = clean · 1 = a workflow shipped (and NAMES it)
# P0-FU: an adopter export ships ZERO GitHub workflows — incept installs the profile's ci.yml +
# ratification.yml. The kit's own dev workflows are all export-ignored, so their kit-self jobs cannot
# redden the adopter's first CI. COMPLETE-BY-CONSTRUCTION: it counts what ACTUALLY shipped, so a NEW
# kit-dev workflow added without export-ignoring it (the enumeration trap) leaks here rather than into
# a real adopter's first push.
_no_shipped_workflows() {
  # Match BOTH extensions: GitHub Actions honors *.yml AND *.yaml equally, so a *.yaml kit workflow
  # would ship undetected if we only counted *.yml — reopening the very leak class this lock closes.
  _leak=$(find "$1/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) -type f 2>/dev/null)
  [ -z "$_leak" ] && return 0
  echo "FAIL: the adopter export ships GitHub workflow(s) — a kit-dev workflow's jobs would redden the adopter's first CI (P0-FU); export-ignore it in .gitattributes:"
  printf '%s\n' "$_leak" | sed 's#.*/\.github/#  .github/#'
  return 1
}

# _no_eof_blank <file> -> 0 = the file ends with exactly one newline (no blank line at EOF) · 1 = a
# blank line at EOF (and NAMES the fix). K12 Cause B: the KW6-A2 carve deletes CLAUDE.md's LAST content
# line (the `Backlog backend:` declaration), which in source sits below a blank separator — deleting it
# leaves that blank as the new EOF, so `git diff --check` reports "new blank line at EOF" and incept.sh
# inherits it into the renamed ENGINEERING-PRINCIPLES.md. Detect it from bytes (no git dependency): a
# blank line at EOF means the final two bytes are both newlines (\n\n); od avoids $(...) newline-strip.
_no_eof_blank() {
  [ -f "$1" ] || { echo "FAIL: $1 missing (cannot check for a blank line at EOF)"; return 1; }
  case "$(tail -c2 "$1" | od -An -tx1 | tr -d ' \n')" in
    0a0a) echo "FAIL: exported $(basename "$1") orphans a blank line at EOF (KW6-A2 carve — strip trailing blanks after the carve in adopter-export.sh)"; return 1 ;;
  esac
  return 0
}

run() {
  rc=0
  [ -f "$ROOT/.gitattributes" ] || { echo "FAIL: no .gitattributes"; return 1; }
  [ -f "$ROOT/scripts/adopter-export.sh" ] || { echo "FAIL: no scripts/adopter-export.sh"; return 1; }
  # (a) each export-ignore entry present with the attribute
  for p in $IGN; do
    grep -Eq "^$(printf '%s' "$p" | sed 's/[.[\*^$/]/\\&/g')[[:space:]]+export-ignore" "$ROOT/.gitattributes" \
      || { echo "FAIL: .gitattributes missing export-ignore for $p"; rc=1; }
  done
  # Fail-closed (M2 security review): every IGN entry must be a plain pathspec — no git-pathspec
  # magic / regex-hostile chars — else `:(exclude)$entry` could make the block-(b) `git grep` error
  # (rc>=2) and, because that grep's error is swallowed by `2>/dev/null | grep -q .`, the link scan
  # would silently PASS. Reject unsafe entries up front so the exclude can never go dark.
  for _i in $IGN; do
    case "$_i" in
      *[!A-Za-z0-9/._-]*) echo "FAIL: IGN entry '$_i' has an unsafe char (breaks the link-safety :(exclude) pathspec)"; rc=1 ;;
    esac
  done
  # (b) LINK-SAFETY: no export-ignored path is a `](…path…)` link target from a KEPT doc.
  # Match the BASENAME inside a markdown link `](…)` so relative forms (](../ROADMAP-KIT.md)) are
  # caught too, not just the full path. Files only (a dir basename like 'fixtures' is rarely a link
  # target and an over-match there is a safe false-positive).
  # Scan KEPT docs ONLY: exclude the IGN set itself from the search, so a link BETWEEN two
  # export-ignored docs (ignored→ignored, e.g. the verdict log → its run artifacts) does NOT
  # false-fail — both ends are pruned together, so the link never reaches the adopter tree. Only a
  # KEPT→ignored link breaks check-links there. The exclude tokens come from a variable, so the
  # `:(exclude)` parens are literal (no shell re-parse after expansion); intentionally unquoted to
  # word-split into one pathspec per IGN entry.
  _ign_excl=""
  for _i in $IGN; do _ign_excl="$_ign_excl :(exclude)$_i"; done
  for p in $IGN; do
    _bn=$(basename "$(printf '%s' "$p" | sed 's#/$##')")
    if ( cd "$ROOT" && git grep -I -lE "\]\([^)]*${_bn}" -- '*.md' $_ign_excl 2>/dev/null | grep -q .); then
      echo "FAIL: export-ignored '$p' is a markdown-link target from a KEPT doc (would break check-links on the adopter tree)"; rc=1
    fi
  done
  # (c) the export prunes + keeps correctly AND is CI-green (drive the real script)
  _t=$(mktemp -d); _d="$_t/exp"
  if ( cd "$ROOT" && sh scripts/adopter-export.sh "$_d" --profile typescript-node >/dev/null 2>&1 ); then
    [ -e "$_d/docs/ROADMAP-KIT.md" ] && { echo "FAIL: export kept ROADMAP-KIT.md"; rc=1; }
    [ -e "$_d/docs/architecture" ] && { echo "FAIL: export kept docs/architecture/ (blanket export-ignore not honored)"; rc=1; }
    [ -e "$_d/profiles/go" ]        && { echo "FAIL: export kept pruned profile go"; rc=1; }
    [ -e "$_d/MAINTAINING.md" ]     || { echo "FAIL: export dropped kept MAINTAINING.md"; rc=1; }
    [ -e "$_d/conformance" ]        || { echo "FAIL: export dropped kept conformance/"; rc=1; }
    # BEHAVIOURAL (the S3a fix): fixtures ship, STACK-SELECTION is stubbed, no link in the export dangles.
    [ -e "$_d/scripts/fixtures/scorecard" ] || { echo "FAIL: export dropped scripts/fixtures/scorecard (breaks tier-advice/agent-scorecard --selftest in adopter CI)"; rc=1; }
    if [ -f "$_d/docs/STACK-SELECTION.md" ] && ! grep -Fq '](../profiles/go.md)' "$_d/docs/STACK-SELECTION.md"; then :; \
      else echo "FAIL: STACK-SELECTION not stubbed (links a pruned profile)"; rc=1; fi
    # no broken relative markdown link in the export tree. The export contains only tracked files
    # (git archive), so an on-disk [ -e ] resolve is equivalent to check-links' tracked-set test.
    # NB: write to a temp file, NOT $(...) — a `case` inside command-substitution is a POSIX trap
    # that bash-as-/bin/sh mis-parses (dash is fine). The redirect form sidesteps it.
    _badf=$(mktemp)
    find "$_d" -name '*.md' -type f | while IFS= read -r _f; do
      _fdir=$(dirname "$_f")
      wf_extract_links "$_f" | while IFS= read -r _ln; do
        case "$_ln" in
          http://*|https://*|mailto:*|'#'*) continue ;;
        esac
        _tgt=$(printf '%s' "$_ln" | sed -E 's/[#?].*$//'); [ -z "$_tgt" ] && continue
        case "$_tgt" in
          /*) _r="$_d$_tgt" ;;
          *)  _r="$_fdir/$_tgt" ;;
        esac
        [ -e "$_r" ] || printf '%s -> %s\n' "$_f" "$_ln"
      done
    done > "$_badf"
    if [ -s "$_badf" ]; then echo "FAIL: broken relative links in export:"; cat "$_badf"; rc=1; fi
    rm -f "$_badf"
    # S3b BEHAVIOURAL: the exported tree's OWN claims-registry passes (the integrity gate the adopter's
    # CI runs). git-init + add + COMMIT so verifiers needing a HEAD (`git archive HEAD`) or `git ls-files`
    # (e.g. check-links) work — matching what a real adopter does. This is the "run the whole adopter CI"
    # check: it catches ANY orphaned/maintainer-only claim.
    if ( cd "$_d" && git init -q && git add -A \
         && git -c gc.auto=0 -c user.email=ci@kit -c user.name=ci commit -qm export >/dev/null 2>&1 \
         && sh conformance/claims-registry.sh >/dev/null 2>&1 ); then
      echo "PASS: exported tree's claims-registry passes"
    else
      echo "FAIL: exported tree's claims-registry does NOT pass (an orphaned maintainer-only claim — carve it in adopter-export.sh)"; rc=1
    fi
    # ── GREEN-ON-CLONE MOVED OUT (P1-CI-c) — it is NOT deleted; see conformance/green-on-clone.sh.
    #
    # A full 87-check `verify.sh --require` used to run RIGHT HERE, on the exported tree. Two problems,
    # both named by P0-FU(a) ("load-sensitive + opaque … refactor to a dedicated, visible green-on-clone
    # job") and neither fixed until now:
    #
    #   COST    — it was ~58s of this check's 77s. And `non-vacuity` MUTATION-TESTS this check, so EVERY
    #             MUTANT re-ran the ENTIRE 87-check battery. That — not the export, which takes <1s —
    #             was the 387s non-vacuity leg. A proof nested inside a mutation-tested check is paid for
    #             ONCE PER MUTANT.
    #   OPACITY — it ran `>/dev/null 2>&1`. You learned green-on-clone broke; you never learned WHICH
    #             control failed.
    #
    # The proof now runs in its own check + its own parallel CI job (`cf-green-on-clone`), gating behind
    # the same `conformance` aggregator. Same coverage, ~1/4 the cost here, and it prints the failing
    # control. DO NOT re-nest it here to "keep things together" — that is the defect, not the design.
    for _cc in drift-watch golden-path adopter-export; do
      if grep -q "^$_cc$(printf '\t')" "$_d/conformance/claims.tsv"; then
        echo "FAIL: claim $_cc not carved from the export"; rc=1
      fi
    done
    # R3/C2 assertion: the exported .gitignore must NOT still ignore /src/ or /test/
    grep -qxE '/(src|test)/' "$_d/.gitignore" 2>/dev/null && { echo "FAIL: exported .gitignore still ignores /src/ or /test/"; rc=1; }
    # (f) P0-FU: the export ships ZERO GitHub workflows (kit-dev CI is export-ignored; incept installs the profile's)
    _no_shipped_workflows "$_d" || rc=1
    # (i) removed — IGN ⊆ export-ignored is already enforced by block (a); set-equality is deliberately
    # NOT asserted (see the note at the IGN definition). Kept as a numbered placeholder so the (a)…(h)
    # lettering below stays stable.
    # (h) K12 Cause B: the exported CLAUDE.md must NOT orphan a blank line at EOF. The KW6-A2 carve
    # (adopter-export.sh) deletes CLAUDE.md's last content line; if the trailing-blank strip below it
    # regresses, the blank separator becomes the new EOF and incept.sh inherits it into the renamed
    # ENGINEERING-PRINCIPLES.md (a `git diff --check` "new blank line at EOF" on the adopter's first commit).
    _no_eof_blank "$_d/CLAUDE.md" || rc=1
  else
    echo "FAIL: adopter-export.sh errored"; rc=1
  fi
  # Cleanup must never fail the verdict: a background writer (git auto-gc from the nested
  # commit, or a check inside the nested verify) can race `rm -rf` into ENOTEMPTY under CI
  # load — green locally/PR, red on the loaded main-push runner. The assertions above ARE the
  # verdict; a leaked temp dir on an ephemeral runner is harmless.
  rm -rf "$_t" 2>/dev/null || true
  # (e) DESIGN B / F1: the README must NOT hardcode the export file-count — it drifts silently
  # (this lock now prevents the 242/392 -> 277/416 drift). The export script prints the exact count
  # at run time; the README defers to it. Guard the two stale phrasings so a count can't creep back.
  if [ -f "$ROOT/README.md" ]; then
    # catch the "down from N" / "~N" phrasing AND any bare 3+-digit "NNN files" count (the export
    # is always a few hundred files); a 1–2-digit count near "files" is plausibly legit prose, so it
    # is deliberately not matched (zero false-positive on the current README).
    if grep -Eq 'down from [~]?[0-9]|[0-9]{3,}[[:space:]]+files' "$ROOT/README.md"; then
      echo "FAIL: README hardcodes a drifting export file-count — say the export script prints the exact count instead (design B / F1)"; rc=1
    fi
  fi
  # (g) FIXPOINT / public-mirror front door. The public repo is produced BY adopter-export
  # (publish-public.sh:[1/5] runs it), so the published mirror IS an export output. The README then has
  # the adopter run adopter-export ON that mirror — export-of-an-export. That second run MUST succeed and
  # be a fixpoint: export(export(X)) == export(X). CI only ever exported from the DEV tree, so this
  # front-door path shipped BROKEN (v3.157.0: the Backlog-backend carve treated the already-carved
  # zero-match state as fatal drift and aborted). This block is that missing leg — it exports twice,
  # simulating publish then adopter, and asserts the second export both succeeds and is byte-identical.
  _fp=$(mktemp -d); _fp1="$_fp/mirror"; _fp2="$_fp/adopter"
  if ( cd "$ROOT" && sh scripts/adopter-export.sh "$_fp1" >/dev/null 2>&1 ) \
     && ( cd "$_fp1" && git init -q && git add -A \
          && git -c gc.auto=0 -c user.email=ci@kit -c user.name=ci commit -qm mirror >/dev/null 2>&1 ) \
     && ( cd "$_fp1" && sh scripts/adopter-export.sh "$_fp2" >/dev/null 2>&1 ); then
    # Behavioral, NOT a re-grep: ask the REAL reader (resolve_backend, sourced in a subshell so it
    # neither pollutes run() nor needs a copy of the anchor) whether the twice-exported tree declares a
    # backend. Using the reader's OWN grep means a future carve/reader anchor drift trips HERE —
    # restoring the drift tripwire the carve's 0-match pass removed, and killing the 3rd anchor copy.
    # (This is the [[presence-check-cannot-see-substitution]] lesson applied to this exact file.)
    if [ -n "$( . "$ROOT/conformance/backlog-lib.sh"; resolve_backend "$_fp2" 2>/dev/null )" ]; then
      echo "FAIL: export-of-an-export resolves a live Backlog backend (carve/reader drift)"; rc=1
    fi
    # Empty dirs are cosmetic: the FIRST export can leave an empty .github/workflows/ (git does not
    # track empty dirs, so the re-export drops it); P0-FU requires zero workflow FILES, satisfied by
    # both. Prune empty dirs from BOTH trees so the fixpoint asserts same files + same content, not
    # incidental directory entries.
    find "$_fp1" "$_fp2" -depth -type d -empty -not -path '*/.git/*' -delete 2>/dev/null || true
    if diff -rq --exclude=.git "$_fp1" "$_fp2" >/dev/null 2>&1; then
      echo "PASS: adopter-export is a fixpoint (public-mirror re-export succeeds)"
    else
      echo "FAIL: adopter-export is not a fixpoint — export(export(X)) != export(X):"; diff -rq --exclude=.git "$_fp1" "$_fp2" 2>&1 | head; rc=1
    fi
  else
    echo "FAIL: export-of-an-export FAILED — the published mirror's front door is broken (an adopter following the README cannot run adopter-export on the mirror; cause: the Backlog-backend carve rejects the already-carved zero-match state)"; rc=1
  fi
  rm -rf "$_fp" 2>/dev/null || true
  [ "$rc" -eq 0 ] && echo "PASS: adopter-export wired + link-safe + prunes + README-count-clean + fixpoint"
  return $rc
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  run >/dev/null 2>&1 || { echo "adopter-export-wired --selftest: FAIL (real tree not green)"; sfail=1; }
  # negative: a tree whose .gitattributes lacks the export-ignore set must FAIL the lock.
  # Base the throwaway archive on $ROOT (= EXPORT_ROOT, default ".") so this is exercisable from flat
  # scratch (EXPORT_ROOT=<real-repo>) AND in production (ROOT="." after the top-of-file cd).
  _n=$(mktemp -d)
  ( cd "$ROOT" && git archive --worktree-attributes HEAD ) | tar -x -C "$_n" 2>/dev/null || true
  : > "$_n/.gitattributes"   # empty attributes => entries missing
  cp "$ROOT/scripts/adopter-export.sh" "$_n/scripts/adopter-export.sh" 2>/dev/null || true
  # Subshell scoping (not `ROOT=x run`) is required: a `VAR=val function` prefix LEAKS in POSIX sh,
  # and the _r fixture below reads $ROOT — an env-prefix leak would corrupt it with the deleted $_n.
  if ( ROOT="$_n"; run ) >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (empty .gitattributes still passed)"; sfail=1
  fi
  rm -rf "$_n" 2>/dev/null || true
  # negative (F1): a tree identical to HEAD but whose README hardcodes a count must FAIL the lock.
  _r=$(mktemp -d)
  ( cd "$ROOT" && git archive --worktree-attributes HEAD ) | tar -x -C "$_r" 2>/dev/null || true
  cp "$ROOT/scripts/adopter-export.sh" "$_r/scripts/adopter-export.sh" 2>/dev/null || true
  printf '\nYou get 242 files for typescript-node, down from 392.\n' >> "$_r/README.md"
  # git-init so the tree passes every OTHER block (export needs `git archive HEAD`) — isolating the
  # README guard as the SOLE failure cause, so this fixture is load-bearing (run() fails ONLY on (e)).
  ( cd "$_r" && git init -q && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm r >/dev/null 2>&1 ) || true
  if ( ROOT="$_r"; run ) >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (README hardcoded count not caught)"; sfail=1
  fi
  rm -rf "$_r" 2>/dev/null || true
  # negative (link-safety / M2): the block-(b) exclude must NOT blind the check to a real KEPT→ignored
  # link. Build a tiny tree where a KEPT doc links an export-ignored doc; the lock MUST still FAIL.
  # (Guards against the M2 fix over-broadening the exclusion and silently passing real breakage.)
  _l=$(mktemp -d)
  mkdir -p "$_l/docs" "$_l/scripts"
  printf 'kept\nlink to [bad](ROADMAP-KIT.md)\n' > "$_l/keep.md"      # KEPT doc → ignored target
  printf '# roadmap\n' > "$_l/docs/ROADMAP-KIT.md"
  : > "$_l/.gitattributes"
  for _e in $IGN; do printf '%s export-ignore\n' "$_e" >> "$_l/.gitattributes"; done
  cp "$ROOT/scripts/adopter-export.sh" "$_l/scripts/adopter-export.sh" 2>/dev/null || true
  ( cd "$_l" && git init -q && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm l >/dev/null 2>&1 ) || true
  if ( ROOT="$_l"; run ) >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (KEPT→ignored markdown link not caught — exclusion over-broadened)"; sfail=1
  fi
  rm -rf "$_l" 2>/dev/null || true
  # positive-blanket (item-6 teeth): a NEW, individually-unlisted docs/architecture/ doc must be
  # export-ignored by the BLANKET rule — and must LEAK if the blanket rule is stripped (load-bearing negative).
  _b=$(mktemp -d); _bx=$(mktemp -d); _bx2=$(mktemp -d)
  ( cd "$ROOT" && git archive --worktree-attributes HEAD ) | tar -x -C "$_b" 2>/dev/null || true
  cp "$ROOT/scripts/adopter-export.sh" "$_b/scripts/adopter-export.sh" 2>/dev/null || true
  mkdir -p "$_b/docs/architecture"; printf '# unlisted design doc\n' > "$_b/docs/architecture/zzz-unlisted-probe.md"
  ( cd "$_b" && git init -q && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm probe >/dev/null 2>&1 ) || true
  ( cd "$_b" && sh scripts/adopter-export.sh "$_bx" >/dev/null 2>&1 ) || true
  if [ -e "$_bx/docs/architecture/zzz-unlisted-probe.md" ]; then
    echo "adopter-export-wired --selftest: FAIL (blanket did not export-ignore an unlisted docs/architecture/ doc)"; sfail=1
  fi
  grep -v '^docs/architecture/[[:space:]][[:space:]]*export-ignore' "$_b/.gitattributes" > "$_b/.ga.tmp" && mv "$_b/.ga.tmp" "$_b/.gitattributes"
  ( cd "$_b" && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm strip >/dev/null 2>&1 ) || true
  ( cd "$_b" && sh scripts/adopter-export.sh "$_bx2" >/dev/null 2>&1 ) || true
  if [ ! -e "$_bx2/docs/architecture/zzz-unlisted-probe.md" ]; then
    echo "adopter-export-wired --selftest: FAIL (probe vacuous — unlisted doc dropped even without the blanket rule)"; sfail=1
  fi
  rm -rf "$_b" "$_bx" "$_bx2" 2>/dev/null || true
  # negative (P0-FU / item-6 teeth): the zero-workflow lock (f) must FLAG a shipped workflow and PASS a
  # clean export. Driven directly (no export) — load-bearing: an always-clean mutation greens the leak case.
  _z=$(mktemp -d); mkdir -p "$_z/.github/workflows"
  _no_shipped_workflows "$_z" || { echo "adopter-export-wired --selftest: FAIL (empty workflows dir wrongly flagged as a leak)"; sfail=1; }
  # BOTH extensions must trip it — GitHub Actions honors *.yml and *.yaml alike.
  for _ext in yml yaml; do
    printf 'name: kitdev\non: push\n' > "$_z/.github/workflows/kitdev-probe.$_ext"
    if _no_shipped_workflows "$_z" >/dev/null 2>&1; then
      echo "adopter-export-wired --selftest: FAIL (a shipped .$_ext GitHub workflow was NOT flagged — the zero-workflow lock is vacuous)"; sfail=1
    fi
    rm -f "$_z/.github/workflows/kitdev-probe.$_ext"
  done
  rm -rf "$_z" 2>/dev/null || true
  # negative (h / K12 Cause B / item-6 teeth): _no_eof_blank must FLAG a file ending in a blank line
  # and PASS a clean file. Driven directly (no export) — load-bearing: a mutation that neuters the EOF
  # detection greens the blank-ending case, which this KILLs. Mirrors the (f) zero-workflow negative.
  _e=$(mktemp -d)
  printf 'text\nBacklog backend: BACKLOG.md\n' > "$_e/clean.md"
  _no_eof_blank "$_e/clean.md" >/dev/null 2>&1 || { echo "adopter-export-wired --selftest: FAIL (a clean CLAUDE.md was wrongly flagged as an EOF blank)"; sfail=1; }
  printf 'text\n\n' > "$_e/blank.md"   # trailing blank line = the exact carve-orphaned state
  if _no_eof_blank "$_e/blank.md" >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (a blank line at EOF was NOT flagged — the EOF-blank lock (h) is vacuous)"; sfail=1
  fi
  rm -rf "$_e" 2>/dev/null || true
  # negative (g / KW27 non-vacuity): block (g) must have TEETH — with the PRE-FIX carve (zero-match =>
  # loud-fail), export-of-an-export MUST fail. Export the real tree once (a mirror), reintroduce the
  # pre-fix zero-match `return 1` into the FIXTURE's own script, commit (adopter-export archives HEAD),
  # then re-export: it must FAIL. If it still succeeds, block (g) is vacuous — it would not catch the
  # v3.157.0 front-door regression.
  _fpm=$(mktemp -d); _fpo=$(mktemp -d)
  if ( cd "$ROOT" && sh scripts/adopter-export.sh "$_fpm" >/dev/null 2>&1 ); then
    sed 's/if \[ "$_cm_n" -eq 0 \]; then/if [ "$_cm_n" -eq 0 ]; then return 1;/' \
      "$_fpm/scripts/adopter-export.sh" > "$_fpm/scripts/.ae.tmp" && mv "$_fpm/scripts/.ae.tmp" "$_fpm/scripts/adopter-export.sh"
    ( cd "$_fpm" && git init -q && git add -A \
      && git -c user.email=ci@kit -c user.name=ci commit -qm pre-fix >/dev/null 2>&1 ) || true
    if ( cd "$_fpm" && sh scripts/adopter-export.sh "$_fpo" >/dev/null 2>&1 ); then
      echo "adopter-export-wired --selftest: FAIL (pre-fix zero-match carve still let export-of-an-export succeed — block (g) is vacuous)"; sfail=1
    fi
  else
    echo "adopter-export-wired --selftest: FAIL (could not build the export-of-export fixture)"; sfail=1
  fi
  rm -rf "$_fpm" "$_fpo" 2>/dev/null || true
  [ "$sfail" -eq 0 ] && { echo "adopter-export-wired --selftest: OK"; exit 0; } || exit 1
fi

# Kit-repo detector (C1 / R3): this check only has meaning inside the kit's own repo.
# OR-of-markers is fail-closed: golden-path.yml is control-plane + export-ignored (un-spoofable);
# deleting only the unprotected ROADMAP-KIT.md marker cannot make the kit skip its own checks.
# N/A-skip only when BOTH are absent (true adopter tree). When either is present, run full.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$ROOT/.github/workflows/golden-path.yml" ]; then
  echo "adopter-export-wired: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
fi

run
