#!/bin/sh
# adopter-export-wired.sh — regression-lock for the S3 adopter-clean obtain mechanism.
# Asserts: the export mechanism exists, the .gitattributes export-ignore set is present, the set is
# LINK-SAFE (no export-ignored path is a `](path)` markdown-link target from a kept doc), the
# export is CI-green: fixtures ship, STACK-SELECTION is stubbed on `--profile`, no broken links,
# AND the exported tree's own claims-registry passes (orphaned-maintainer-only-claim guard).
#   sh conformance/adopter-export-wired.sh [--selftest]
# Exit: 0 = wired + link-safe + CI-green · 1 = regression · 2 = setup. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."
ROOT="${EXPORT_ROOT:-.}"

# the export-ignore set this lock enforces (must match .gitattributes)
IGN="docs/ROADMAP-KIT.md .github/workflows/drift-watch.yml .github/workflows/golden-path.yml docs/superpowers/ .superpowers/"

run() {
  rc=0
  [ -f "$ROOT/.gitattributes" ] || { echo "FAIL: no .gitattributes"; return 1; }
  [ -f "$ROOT/scripts/adopter-export.sh" ] || { echo "FAIL: no scripts/adopter-export.sh"; return 1; }
  # (a) each export-ignore entry present with the attribute
  for p in $IGN; do
    grep -Eq "^$(printf '%s' "$p" | sed 's/[.[\*^$/]/\\&/g')[[:space:]]+export-ignore" "$ROOT/.gitattributes" \
      || { echo "FAIL: .gitattributes missing export-ignore for $p"; rc=1; }
  done
  # (b) LINK-SAFETY: no export-ignored path is a `](…path…)` link target in any tracked kept doc.
  # Match the BASENAME inside a markdown link `](…)` so relative forms (](../ROADMAP-KIT.md)) are
  # caught too, not just the full path. Files only (a dir basename like 'fixtures' is rarely a link
  # target and an over-match there is a safe false-positive).
  for p in $IGN; do
    _bn=$(basename "$(printf '%s' "$p" | sed 's#/$##')")
    if ( cd "$ROOT" && git grep -I -lE "\]\([^)]*${_bn}" -- '*.md' 2>/dev/null | grep -q .); then
      echo "FAIL: export-ignored '$p' is a markdown-link target (would break check-links on the adopter tree)"; rc=1
    fi
  done
  # (c) the export prunes + keeps correctly AND is CI-green (drive the real script)
  _t=$(mktemp -d); _d="$_t/exp"
  if ( cd "$ROOT" && sh scripts/adopter-export.sh "$_d" --profile typescript-node >/dev/null 2>&1 ); then
    [ -e "$_d/docs/ROADMAP-KIT.md" ] && { echo "FAIL: export kept ROADMAP-KIT.md"; rc=1; }
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
      awk '/^[[:space:]]*(```|~~~)/{f=!f;next} f{next} {gsub(/`[^`]*`/,"");print}' "$_f" 2>/dev/null | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r _ln; do
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
