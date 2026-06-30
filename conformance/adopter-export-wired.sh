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
ROOT="${EXPORT_ROOT:-.}"

# the export-ignore set this lock enforces (must match .gitattributes)
IGN="docs/ROADMAP-KIT.md .github/workflows/drift-watch.yml .github/workflows/golden-path.yml docs/superpowers/ .superpowers/ .github/CODEOWNERS docs/architecture/ docs/governance/meta-control-log.md docs/governance/.meta-control-last"

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
         && git -c user.email=ci@kit -c user.name=ci commit -qm export >/dev/null 2>&1 \
         && sh conformance/claims-registry.sh >/dev/null 2>&1 ); then
      echo "PASS: exported tree's claims-registry passes"
    else
      echo "FAIL: exported tree's claims-registry does NOT pass (an orphaned maintainer-only claim — carve it in adopter-export.sh)"; rc=1
    fi
    # Green-on-clone: the export must pass the SAME aggregate the adopter's ci.yml runs —
    # verify.sh --require — not just claims-registry. A control-check that hard-fails on the export
    # (e.g. a kit-self check needing an export-ignored file but not N/A-ing) would otherwise only
    # surface when a real adopter pushes. The tree is committed above (git init+add+commit). This
    # drives the FULL adopter aggregate on the export, so this lock's runtime ~doubles (expected,
    # not a hang). RECURSION-SAFE: the export's OWN adopter-export-wired N/A-skips (both kit markers
    # are stripped from the export) and returns before re-exporting — do NOT remove that N/A-skip.
    if ( cd "$_d" && sh conformance/verify.sh --require >/dev/null 2>&1 ); then
      echo "PASS: exported tree's verify --require passes (adopter first CI push is green)"
    else
      echo "FAIL: exported tree's verify.sh --require FAILS — green-on-clone is broken. A control-check hard-fails on the export; make it N/A when its export-ignored dependency is absent (the kit-self pattern)."; rc=1
    fi
    for _cc in drift-watch golden-path adopter-export; do
      if grep -q "^$_cc$(printf '\t')" "$_d/conformance/claims.tsv"; then
        echo "FAIL: claim $_cc not carved from the export"; rc=1
      fi
    done
    # R3/C2 assertion: the exported .gitignore must NOT still ignore /src/ or /test/
    grep -qxE '/(src|test)/' "$_d/.gitignore" 2>/dev/null && { echo "FAIL: exported .gitignore still ignores /src/ or /test/"; rc=1; }
  else
    echo "FAIL: adopter-export.sh errored"; rc=1
  fi
  rm -rf "$_t"
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
  [ "$rc" -eq 0 ] && echo "PASS: adopter-export wired + link-safe + prunes + README-count-clean"
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
  rm -rf "$_n"
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
  rm -rf "$_r"
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
  rm -rf "$_l"
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
  rm -rf "$_b" "$_bx" "$_bx2"
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
