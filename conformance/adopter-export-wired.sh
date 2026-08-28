#!/bin/sh
# adopter-export-wired.sh — regression-lock for the S3 adopter-clean obtain mechanism.
# Asserts: the export mechanism exists, the .gitattributes export-ignore set is present, the set is
# LINK-SAFE (no export-ignored path is a `](path)` markdown-link target from a KEPT doc; links
# BETWEEN export-ignored docs are fine — both ends prune together), and the export is CI-green:
# fixtures ship, STACK-SELECTION is stubbed on `--profile`, no broken links.
# ⚠️ THE EXPORTED TREE'S OWN CLAIMS-REGISTRY IS NO LONGER PROVEN HERE. That proof (the orphaned-
# maintainer-only-claim guard) lives in conformance/adopter-export-claims.sh as of
# NON-VACUITY-SHARD2-FLOOR — measured at 96.7% of this check's --selftest cost, paid once per mutant.
# Do not re-nest it; see the note in block (c).
#   sh conformance/adopter-export-wired.sh [--selftest]
# Exit: 0 = wired + link-safe + CI-green · 1 = regression · 2 = setup. POSIX sh; dash-clean.
set -eu
_here=$(CDPATH='' cd "$(dirname "$0")" && pwd)   # resolve dir BEFORE cd so sourcing is cwd-independent
cd "$_here/.."
. "$_here/wf-helpers.sh"   # provides wf_extract_links() (single source of truth)
# ⚠️ THE git-auto-gc GUARD IS NOT HERE ANY MORE — it is set at BOTH dispatch sites below (the top of
# the `--selftest` block and immediately before the tail `run`), and this note is why. Everything above
# the `--selftest` marker is `non-vacuity.sh`'s MUTATION REGION: the guard's `GIT_CONFIG_COUNT` is a
# `<var>=1` accumulator idiom, so every mutant ran with the anti-`git gc` race protection DISABLED —
# a flake-fail inside a mutant reads as a KILL, i.e. as proof this check has teeth it may not have.
# (It also inflated the mutant census with an accumulator that guards nothing.) What the guard does:
# a commit's detached `git gc --auto` keeps writing to .git after it returns, racing the temp `rm -rf`
# into ENOTEMPTY under CI load (green locally/PR, red on the loaded main-push runner). Env-scoped (no
# global mutation), additive (only forces gc.auto=0); the `|| true` on each rm below is the hard
# guarantee. Both sites are required because the `--selftest` arm exits before the tail.
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
# docs/governance/DECISIONS.md (TRIAL-PREP-FIRST-MILE): the kit's own ruling ledger, export-ignored
# for RUNBOOK.md's exact reason — incept.sh stamps an EMPTY one from templates/DECISIONS-TEMPLATE.md
# only when the file is ABSENT. It MUST be listed here as well as in .gitattributes: the omission is
# SILENT in the safe direction until the ledger gains one markdown link to another export-ignored
# target, at which point the link scan reds on a file the real export never ships.
IGN="docs/ROADMAP-KIT.md .github/workflows/ci.yml .github/workflows/ratification.yml .github/workflows/release-coherence.yml .github/workflows/drift-watch.yml .github/workflows/golden-path.yml docs/superpowers/ .superpowers/ .github/CODEOWNERS docs/architecture/ docs/plans/ docs/governance/meta-control-log.md docs/governance/.meta-control-last docs/governance/DECISIONS.md BACKLOG.md RUNBOOK.md REQUIRED-CHECKS.md SPARKWRIGHT-CONSOLIDATED-BACKLOG.md CHANGELOG.md .publish-identifiers .kit/dials.conf"

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

# _no_double_blank <file> -> 0 = no run of 2+ consecutive blank lines · 1 = at least one (and NAMES it).
# THE SAME DEFECT AS _no_eof_blank, ONE POSITION OVER. _no_eof_blank pins the carve's orphaned blank
# only where the declaration happened to sit at the time it was written — the LAST content line. When the
# Roster-authority section moved to the top of CLAUDE.md the declaration moved to line 20 of 132, the
# orphan became a MID-FILE double blank, and the EOF lock stayed green over it (MEASURED on a real
# adopter-export.sh -> incept.sh run: a double blank at lines 19-20 of the exported CLAUDE.md that the
# `main` baseline does not have). A lock keyed to a POSITION cannot survive the content moving; this one
# is keyed to the DEFECT, so it holds wherever the declaration lands next.
_no_double_blank() {
  [ -f "$1" ] || { echo "FAIL: $1 missing (cannot check for a double blank line)"; return 1; }
  if [ "$(awk 'NF==0{c++;next} {if(c>1) n++; c=0} END{print n+0}' "$1")" != "0" ]; then
    echo "FAIL: exported $(basename "$1") orphans a DOUBLE BLANK line (KW6-A2 carve — collapse blank runs after the carve in adopter-export.sh)"
    return 1
  fi
  return 0
}

# _link_safety ROOT -> 0 iff no IGN entry is a markdown-link target from a doc the archive KEEPS.
# Fail-closed: the archive is written to a file and its rc checked (a partial stream would otherwise
# exempt every doc after the cut), and an empty listing is a FAIL, never a KEPT set that passes.
# The KEPT set is HEAD's; `git grep` reads the worktree — an added-but-uncommitted kept doc is not
# judged until it is committed (CI always runs on a commit; a local pre-push run may green early).
# Only ever called in `||` / `if` context: under `set -e` a bare call would exit on the empty-grep
# before the fail-closed message could print.
_link_safety() {
  _ls_root=$1; _ls_rc=0; _ls_kept=$(mktemp); _ls_ar=$(mktemp)
  if ! ( cd "$_ls_root" && git archive --worktree-attributes HEAD ) > "$_ls_ar" 2>/dev/null; then
    echo "FAIL: 'git archive HEAD' failed (no commits, or not a git repo) — the link-safety scan has no KEPT set"
    rm -f "$_ls_kept" "$_ls_ar"; return 1
  fi
  tar -tf "$_ls_ar" 2>/dev/null | grep '\.md$' > "$_ls_kept"
  if [ ! -s "$_ls_kept" ]; then
    echo "FAIL: the archive lists no .md docs — the link-safety scan has no KEPT set"
    rm -f "$_ls_kept" "$_ls_ar"; return 1
  fi
  rm -f "$_ls_ar"
  for _ls_p in $IGN; do
    _ls_bn=$(basename "$(printf '%s' "$_ls_p" | sed 's#/$##')")
    # core.quotePath=false: git grep would C-quote a non-ASCII path ("docs/caf\303\251.md") while
    # tar prints it raw, and the -Fx filter would drop a REAL kept->ignored hit (measured, review R1).
    if ( cd "$_ls_root" && git -c core.quotePath=false grep -I -lE "\]\([^)]*${_ls_bn}" -- '*.md' 2>/dev/null ) | grep -Fxf "$_ls_kept" | grep -q .; then
      echo "FAIL: export-ignored '$_ls_p' is a markdown-link target from a KEPT doc (would break check-links on the adopter tree)"; _ls_rc=1
    fi
  done
  rm -f "$_ls_kept"; return "$_ls_rc"
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
  # Fail-closed (M2 security review): every IGN entry must be a plain path — no regex-hostile
  # chars — because its basename is interpolated into block (b)'s `git grep -lE` as an ERE; an
  # invalid ERE errors (rc 2), that error is swallowed by `2>/dev/null`, the hit set is empty and
  # the link scan would silently PASS. Reject unsafe entries up front so the scan can never go dark.
  for _i in $IGN; do
    case "$_i" in
      *[!A-Za-z0-9/._-]*) echo "FAIL: IGN entry '$_i' has an unsafe char (would corrupt the link-safety git-grep ERE)"; rc=1 ;;
    esac
  done
  # (b) LINK-SAFETY: no export-ignored path is a `](…path…)` link target from a KEPT doc.
  # Match the BASENAME inside a markdown link `](…)` so relative forms (](../ROADMAP-KIT.md)) are
  # caught too, not just the full path. Files only (a dir basename like 'fixtures' is rarely a link
  # target and an over-match there is a safe false-positive).
  # Scan KEPT docs ONLY, and KEPT means WHAT `git archive` SHIPS — the archive's own listing is the
  # single truth. A link BETWEEN two export-ignored docs never reaches the adopter, so it is not a
  # break. The previous form excluded the IGN list (21 hand-named entries) from the scan, while
  # .gitattributes export-ignores 41 patterns: a doc under docs/governance/tier-a/ — ignored by the
  # archive, absent from IGN — was scanned as KEPT and its link to an IGN target fired a false FAIL
  # (#579, run 32915859644). Filtering hits by the archive listing closes the whole class: no path
  # can be "kept" here and pruned there. (ADOPTER-EXPORT-WIRED-EXCLUDE-TRAILING-SLASH — the row's
  # trailing-slash theory was measured false: git 2.48 honours `:(exclude)dir/`; the cause was IGN.)
  _link_safety "$ROOT" || rc=1
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
    # git-init + add + COMMIT the export, matching what a real adopter does on their first push. The
    # COMMIT IS LOAD-BEARING FOR THE DIAL FIXTURE BELOW, which pushes `$(git rev-parse HEAD)` through the
    # exported hook — it is not bookkeeping.
    #
    # ── THE CLAIMS-REGISTRY RUN MOVED OUT (NON-VACUITY-SHARD2-FLOOR) — it is NOT deleted; see
    #    conformance/adopter-export-claims.sh.
    #
    # A full `claims-registry.sh` used to run RIGHT HERE, on the exported tree, and again (via the
    # fixture-r path) on the raw worktree-attributes export. MEASURED on an instrumented run of this
    # file's own --selftest: 134.0s + 181.6s of 326.6s — 96.7%. And `non-vacuity` MUTATION-TESTS this
    # check with three selftest runs per judgment, so that pair WAS the shard-2 floor. It is the same
    # defect the green-on-clone note below names: A PROOF NESTED INSIDE A MUTATION-TESTED CHECK IS PAID
    # FOR ONCE PER MUTANT. The un-nested check also asserts the second face at its TRUE polarity for the
    # first time (the raw export's registry fails BY CONSTRUCTION — the carve is skipped on an unmarked
    # tree — and that failure used to be swallowed whole). DO NOT re-nest it here.
    if ( cd "$_d" && git init -q && git add -A \
         && git -c gc.auto=0 -c user.email=ci@kit -c user.name=ci commit -qm export >/dev/null 2>&1 ); then
      echo "PASS: exported tree commits cleanly (adopter first-push shape; its claims-registry is proven in adopter-export-claims.sh)"
    else
      echo "FAIL: the exported tree could not be committed — the dial fixture below needs a real HEAD, so nothing downstream of this point is trustworthy"; rc=1
    fi
    # DIAL-DELIVERY Δ-A/Δ-B — the adopter's dial state, in ONE fold: (a) the kit's own enforcement
    # dials do not ship (ALL of them — the two push dials AND the Δ-B KIT_SCOPE_MODE=enforce), and
    # (b) BEHAVIOURAL — with no conf the exported hook OBSERVES a failing entry declaration (rc 0 +
    # the observe prefix) instead of refusing it. (a) alone is a presence check and cannot see a
    # substitution: a hook that read the dial from somewhere else, or defaulted to enforce, would pass
    # it and still red an adopter's first push. The fixture head is the export commit made just above
    # — a real commit carrying no Kit-* trailers, so the predicate genuinely fails and only the DIAL
    # decides the rc. ⚠️ (b) proves the observe-by-absence MECHANISM through the DECL dial (a hook
    # leg). Δ-B's KIT_SCOPE_MODE rides the SAME `.kit/dials.conf`-absent => observe mechanism, but its
    # consumer is loop-state.sh (--head), not the hook body, and firing its scope leg needs a crafted
    # escaping-diff + a resolvable base — heavier than this check may nest (the green-on-clone note
    # below). Its reader-level observe-by-absence proof lives at the right layer: loop-state.sh's own
    # T7c `dm-absent` cross-reader selftest. Here, (a) forbids the conf that would flip SCOPE at all.
    [ -e "$_d/.kit/dials.conf" ] && { echo "FAIL: export kept .kit/dials.conf (every adopter would inherit the kit's enforce dials — the two push dials AND KIT_SCOPE_MODE=enforce — at their first hook re-copy)"; rc=1; }
    _dl=0; _dlo=$( cd "$_d" && printf 'refs/heads/x %s refs/heads/x %s\n' "$(git rev-parse HEAD)" \
      0000000000000000000000000000000000000000 | sh hooks/pre-push 2>&1 ) || _dl=$?
    if [ "$_dl" -ne 0 ] || ! printf '%s' "$_dlo" | grep -q 'kit pre-push (observe):'; then
      echo "FAIL: the EXPORTED hook is not observe-by-default on a failing entry declaration (rc $_dl) — an adopter's first push would be refused"; echo "  got: $_dlo"; rc=1
    else
      echo "PASS: export ships no dial file and the exported hook observes"
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
    _no_double_blank "$_d/CLAUDE.md" || rc=1
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
  # git-auto-gc guard, site 1 of 2 — see the note at the top of this file. It MUST sit at or after this
  # marker: above it, every mutant would run with the race protection off.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=gc.auto
  export GIT_CONFIG_VALUE_0=0
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
  # git-init so the tree passes every OTHER block (export needs `git archive HEAD`).
  # ⚠️ THE SOLE-CAUSE CLAIM THAT USED TO END THIS SENTENCE IS FALSE, AND THE MEASUREMENT IS RECORDED
  # HERE RATHER THAN QUIETLY FIXED (NON-VACUITY-SHARD2-FLOOR, 2026-08-15). It read "isolating the README
  # guard as the SOLE failure cause, so this fixture is load-bearing (run() fails ONLY on (e))". MEASURED
  # by hand-reverting block (e)'s `rc=1` to `rc=0`: this selftest still reports OK. run() on this fixture
  # fails for FIVE OTHER reasons, because the archive strips both kit markers and rider (c)'s
  # `_ae_is_kit_tree` gate then SKIPS every carve — `claim drift-watch/golden-path/adopter-export not
  # carved`, `exported .gitignore still ignores /src/ or /test/`, and block (g)'s `export-of-an-export
  # resolves a live Backlog backend`. So block (e) currently has NO selftest teeth, and this leg proves
  # only "the fixture fails somehow" — the SAME defect class the block-(g) negative below had to work
  # around explicitly (`_aekt=0` -> `_aekt=1`), and the same one that made the nested claims-registry
  # run proof-free. PRE-EXISTING, NOT INTRODUCED BY THE UN-NESTING: all five fail-sites are verbatim in
  # the pre-cure file and untouched by that diff. Fixing it (arm the fixture, or drive block (e) as a
  # pure function like `_no_eof_blank` below) is a separate row — this comment exists so the next reader
  # measures instead of trusting the claim, which is exactly how it survived this long.
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
  # positive (the #579 shape): a directory export-ignored in .gitattributes but NOT in IGN carries a
  # link to an IGN target. The archive prunes it, so it is NOT a kept->ignored link — must PASS.
  # (Before this fix it FAILED: the scan's KEPT set was "everything minus IGN".) Load-bearing pair:
  # the same tree with the link moved into a KEPT doc must FAIL, so the archive filter is proven to
  # discriminate rather than blind.
  _s=$(mktemp -d)
  mkdir -p "$_s/docs" "$_s/hidden"
  printf 'kept, clean\n' > "$_s/keep.md"
  printf 'pruned doc linking [x](ROADMAP-KIT.md)\n' > "$_s/hidden/note.md"
  printf '# roadmap\n' > "$_s/docs/ROADMAP-KIT.md"
  : > "$_s/.gitattributes"
  for _e in $IGN; do printf '%s export-ignore\n' "$_e" >> "$_s/.gitattributes"; done
  printf 'hidden/ export-ignore\n' >> "$_s/.gitattributes"
  ( cd "$_s" && git init -q && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm s >/dev/null 2>&1 ) || true
  if ! _link_safety "$_s" >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (a link inside an archive-pruned dir outside IGN was reported as KEPT->ignored — the #579 false FAIL)"; sfail=1
  fi
  printf 'kept doc linking [x](ROADMAP-KIT.md)\n' >> "$_s/keep.md"
  ( cd "$_s" && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm s2 >/dev/null 2>&1 ) || true
  if _link_safety "$_s" >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (the archive filter blinded the scan to a real KEPT->ignored link)"; sfail=1
  fi
  # non-ASCII kept path (review R1): git grep C-quotes it unless core.quotePath=false; the archive
  # listing is raw; a mismatch drops a REAL kept->ignored hit. Must FAIL.
  printf 'kept, clean\n' > "$_s/keep.md"
  printf 'kept doc linking [x](ROADMAP-KIT.md)\n' > "$_s/café.md"
  ( cd "$_s" && git add -A && git -c user.email=ci@kit -c user.name=ci commit -qm s3 >/dev/null 2>&1 ) || true
  if _link_safety "$_s" >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (a KEPT->ignored link in a non-ASCII-named doc was dropped by path quoting)"; sfail=1
  fi
  rm -rf "$_s" 2>/dev/null || true
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
  # negative (h, MID-FILE half): _no_double_blank must FLAG a double blank that is NOT at EOF and PASS a
  # clean file. The positive fixture is deliberately a file the EOF lock already calls clean — that is
  # the whole point, since the EOF lock was green over exactly this defect on a real export.
  printf 'a\n\nb\n' > "$_e/single.md"
  _no_double_blank "$_e/single.md" >/dev/null 2>&1 || { echo "adopter-export-wired --selftest: FAIL (a single blank separator was wrongly flagged as a double blank)"; sfail=1; }
  printf 'a\n\n\nb\n' > "$_e/dblank.md"   # mid-file double blank = the carve orphan at its NEW position
  _no_eof_blank "$_e/dblank.md" >/dev/null 2>&1 || { echo "adopter-export-wired --selftest: FAIL (fixture invalid — the EOF lock should call this file clean)"; sfail=1; }
  if _no_double_blank "$_e/dblank.md" >/dev/null 2>&1; then
    echo "adopter-export-wired --selftest: FAIL (a MID-FILE double blank was NOT flagged — the double-blank lock (h) is vacuous)"; sfail=1
  fi
  rm -rf "$_e" 2>/dev/null || true
  # negative (g / KW27 non-vacuity): block (g) must have TEETH — with the PRE-FIX carve (zero-match =>
  # loud-fail), export-of-an-export MUST fail. RE-ARMED FOR RIDER (c) (measured vacuous in CI
  # 2026-08-07, PR #501 battery 1): the mirror is a NON-kit tree (KIT_INTERNAL_MARKERS stripped by the
  # export), so rider (c)'s `_ae_is_kit_tree` gate now SKIPS the whole carve block there and the
  # historical zero-match mutant became unreachable — the sed applied cleanly but its target branch was
  # dead code on the mirror path. Fix: force the gate open in the mirror's own script (`_aekt=0` ->
  # `_aekt=1`), then (CONTROL) the forced-gate export-of-an-export must still SUCCEED — proving every
  # carve tolerates the already-carved state, and isolating the mutant as the only cause of the
  # failure asserted next — then (MUTANT) + the pre-fix zero-match `return 1` must FAIL. Both seds are
  # verified applied (a zero-match sed is a silent no-op — exactly the class this negative just fell to).
  _fpm=$(mktemp -d); _fpo=$(mktemp -d)
  if ( cd "$ROOT" && sh scripts/adopter-export.sh "$_fpm" >/dev/null 2>&1 ); then
    sed 's/_aekt=0/_aekt=1/' \
      "$_fpm/scripts/adopter-export.sh" > "$_fpm/scripts/.ae.tmp" && mv "$_fpm/scripts/.ae.tmp" "$_fpm/scripts/adopter-export.sh"
    # >=2: the unmutated script already contains one `_aekt=1` (the marker-hit assignment), so a
    # presence grep is vacuously satisfiable — count instead (reviewer round-4 Minor).
    if [ "$(grep -c '_aekt=1' "$_fpm/scripts/adopter-export.sh" || true)" -lt 2 ]; then
      echo "adopter-export-wired --selftest: FAIL (fixture mutation did not apply — the kit-tree-force sed matched nothing)"; sfail=1
    fi
    ( cd "$_fpm" && git init -q && git add -A \
      && git -c user.email=ci@kit -c user.name=ci commit -qm forced-gate >/dev/null 2>&1 ) || true
    if ! ( cd "$_fpm" && sh scripts/adopter-export.sh "$_fpo" >/dev/null 2>&1 ); then
      echo "adopter-export-wired --selftest: FAIL (CONTROL broke — forced-gate export-of-an-export failed WITHOUT the mutant, so the negative below cannot isolate its cause)"; sfail=1
    else
      rm -rf "$_fpo" 2>/dev/null || true; _fpo=$(mktemp -d)
      sed 's/if \[ "$_cm_n" -eq 0 \]; then/if [ "$_cm_n" -eq 0 ]; then return 1;/' \
        "$_fpm/scripts/adopter-export.sh" > "$_fpm/scripts/.ae.tmp" && mv "$_fpm/scripts/.ae.tmp" "$_fpm/scripts/adopter-export.sh"
      if ! grep -q 'then return 1;' "$_fpm/scripts/adopter-export.sh"; then
        echo "adopter-export-wired --selftest: FAIL (fixture mutation did not apply — the zero-match sed matched nothing)"; sfail=1
      fi
      ( cd "$_fpm" && git add -A \
        && git -c user.email=ci@kit -c user.name=ci commit -qm pre-fix >/dev/null 2>&1 ) || true
      if ( cd "$_fpm" && sh scripts/adopter-export.sh "$_fpo" >/dev/null 2>&1 ); then
        echo "adopter-export-wired --selftest: FAIL (pre-fix zero-match carve still let export-of-an-export succeed — block (g) is vacuous)"; sfail=1
      fi
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

# git-auto-gc guard, site 2 of 2 — the live path (the `--selftest` arm above exits before reaching it).
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=gc.auto
export GIT_CONFIG_VALUE_0=0
run
