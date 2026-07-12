#!/bin/sh
# adopter-export.sh — produce a clean adopter distribution of the kit via `git archive`
# (honors .gitattributes export-ignore; excludes gitignored scratch/node_modules automatically,
# since an archive contains only committed tracked files). Optionally prunes unused stack profiles.
#   sh scripts/adopter-export.sh <dest-dir> [--profile <stack>] [--selftest]
# Operates on committed HEAD. NEVER writes inside the kit repo. Exit: 0 ok · 1 runtime · 2 usage.
# POSIX sh; dash-clean.
# What it changes: Writes the exported kit distribution into <dest-dir> (creates it); never writes inside the kit repo.
# Guardrails: Operates on committed HEAD via `git archive`; refuses a non-empty <dest-dir> (no clobber); rejects an unknown --profile; never mutates the kit repo.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

usage() { echo "usage: adopter-export.sh <dest-dir> [--profile <stack>] [--selftest]" >&2; exit 2; }

known_profiles() { ls -d "$ROOT"/profiles/*/ 2>/dev/null | sed 's#.*/profiles/##; s#/$##'; }

# --- CP-4: repository ownership is a hard precondition -------------------------------------
# `git rev-parse --is-inside-work-tree` answers "is there a repo ABOVE me?" — not "is THIS dir the
# root of its own repo?". The two diverge only when nested, which is why every non-nested test
# agrees and why the kit once wrote a pre-push hook into a stranger's repository.
#
# BOTH sides of the compare must be PHYSICAL paths: `--show-toplevel` is symlink-resolved, `$PWD`
# is not. On macOS /tmp -> /private/tmp, so a logical compare FALSE-REFUSES under /tmp while
# passing on Linux CI. Normalizing both sides is the only compare that cannot drift.
#
# Honest ceiling: this proves OWNERSHIP. It does NOT cover GIT_DIR / GIT_WORK_TREE redirection,
# submodules, or `git worktree add` trees. See CP-11.
owning_repo_root() {  # <dir> -> stdout: physical toplevel, or empty when <dir> is in no repo
  ( CDPATH='' cd "$1" 2>/dev/null || exit 0
    _t=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    CDPATH='' cd "$_t" 2>/dev/null && pwd -P )
}
owns_itself() {  # <dir> -> 0 iff <dir> is its own repo root, or is in no repo at all
  # "Cannot determine" must REFUSE, never proceed (the kit's default). Compute the physical cwd FIRST:
  # a dir we cannot even cd into is not "in no repo -> fine", it is unknown -> refuse. Unreachable from
  # today's call sites (all pass "$PWD"/"$ROOT"), but the wrong default is worth closing.
  _phys=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_phys" ] || return 1
  _own=$(owning_repo_root "$1")
  [ -n "$_own" ] || return 0
  [ "$_own" = "$_phys" ]
}

# CP-4: do_export is now ATOMIC. It stages into a sibling temp dir, verifies, and only then renames
# into place. Previously it extracted into <dest> BEFORE the carve could fail — so a failed export
# left a non-empty <dest>, and the retry hit "refusing to clobber". The adopter was WEDGED, and the
# selftest ASSERTED that wedge ("should extract before refusing"). The design was wrong; this is it
# corrected. A failed export now leaves NO destination.
do_export() {  # <dest> <profile-or-empty>  — atomic: stage -> verify -> rename
  _final=$1; _prof=${2:-}
  [ -n "$_final" ] || { echo "adopter-export: missing dest" >&2; return 2; }
  if [ -e "$_final" ] && [ -n "$(ls -A "$_final" 2>/dev/null)" ]; then
    echo "adopter-export: dest '$_final' exists and is not empty — refusing to clobber" >&2; return 1
  fi
  if [ -n "$_prof" ] && ! known_profiles | grep -qxF -- "$_prof"; then
    echo "adopter-export: unknown profile '$_prof' (known: $(known_profiles | tr '\n' ' '))" >&2; return 1
  fi
  # CP-4: the kit must be the root of its OWN repo. Nested in a foreign worktree as an UNTRACKED dir,
  # `git archive HEAD` resolves to the PARENT's HEAD and the cwd prefix matches nothing — yielding an
  # empty archive, "exported 0 files", and exit 0. A silent success is the worst failure mode there is.
  if ! owns_itself "$ROOT"; then
    _parent=$(owning_repo_root "$ROOT")
    echo "adopter-export: the kit at '$ROOT' is not the root of its own git repository." >&2
    echo "  owned by: $_parent  (git toplevel)" >&2
    echo "  'git archive HEAD' would archive THAT repo's HEAD, not the kit — producing an empty" >&2
    echo "  archive and a silent 0-file 'success'. Run the exporter from the kit's own repo root." >&2
    return 1
  fi
  _parent_dir=$(dirname "$_final")
  mkdir -p "$_parent_dir"
  # Sibling of <dest>, so the final `mv` is a same-filesystem rename (atomic), not a cross-device copy.
  _stage=$(mktemp -d "$_parent_dir/.adopter-export.XXXXXX") || {
    echo "adopter-export: could not create a staging dir under '$_parent_dir'" >&2; return 1; }
  if _export_into "$_stage" "$_prof"; then
    [ -d "$_final" ] && { rmdir "$_final" 2>/dev/null || { rm -rf "$_stage"; \
      echo "adopter-export: dest '$_final' is not an empty dir — refusing" >&2; return 1; }; }
    mv "$_stage" "$_final" || { rm -rf "$_stage"; return 1; }
    return 0
  fi
  rm -rf "$_stage"
  return 1
}

_export_into() {  # <staging-dir> <profile-or-empty>  — all the real work; writes ONLY into staging
  _dest=$1; _prof=${2:-}
  mkdir -p "$_dest"
  # --worktree-attributes: honor the working-tree .gitattributes (so export-ignore applies even
  # before it is committed, and after a clean clone where worktree == HEAD). Archive content is HEAD.
  _ar=$(mktemp) || { echo "adopter-export: mktemp failed" >&2; return 1; }
  if ! ( cd "$ROOT" && git archive --worktree-attributes HEAD ) > "$_ar"; then
    echo "adopter-export: git archive failed (is '$ROOT' a git repo with a committed HEAD?)" >&2
    rm -f "$_ar"; return 1
  fi
  tar -x -C "$_dest" < "$_ar"
  rm -f "$_ar"
  # --- S3b: carve maintainer-only claims whose verified workflows are export-ignored ---
  # .github/workflows/{drift-watch,golden-path}.yml are export-ignored (maintainer-only CI), but
  # their claims + wired-checks ship; the claims' real-workflow verifiers would FAIL in the adopter's
  # claims-registry. Strip those claims from the adopter's COPY of claims.tsv + REQUIRED_IDS (the kit's
  # own registry is untouched). The wired-check scripts stay — their --selftest in the adopter ci.yml
  # is self-contained and passes. If a new maintainer-only workflow+claim is added without carving it,
  # conformance/adopter-export-wired.sh goes RED (it runs the adopter's full claims-registry).
  # adopter-export is ALSO carved: it is a kit-self check (an adopter has no reason to verify the kit's
  # OWN export mechanism), AND keeping it would recurse (claims-registry -> adopter-export-wired.sh ->
  # claims-registry -> ...). The kit still verifies adopter-export in its own CI.
  _ct="$_dest/conformance/claims.tsv"; _cr="$_dest/conformance/claims-registry.sh"
  if [ -f "$_ct" ] && [ -f "$_cr" ]; then
    _tab=$(printf '\t')
    for _c in drift-watch golden-path adopter-export repo-ownership feature-flags-wired containment-audit runtime-security structured-logging app-tracing metrics-endpoint otlp-backend trace-query agentops-sensor orchestrator-loop escalation-seam conflict-safe-integration skill-spine; do
      grep -v "^${_c}${_tab}" "$_ct" > "$_ct.$$.s3b" && mv "$_ct.$$.s3b" "$_ct"
      sed "s/ ${_c}\\([\"[:space:]]\\)/\\1/" "$_cr" > "$_cr.$$.s3b" && mv "$_cr.$$.s3b" "$_cr"
    done
  fi
  # R3/C2: the kit's root .gitignore ignores /src/ and /test/ (stray KIT dogfooding output); an
  # adopter puts product source there, so strip those two EXACT lines from the EXPORTED .gitignore
  # (the kit's own .gitignore is untouched). `grep -vx` matches whole lines only, so an adopter path
  # like `my/src/lib` or `/src/foo` is never clobbered. Idempotent.
  _gi="$_dest/.gitignore"
  if [ -f "$_gi" ]; then
    grep -vxE '/(src|test)/' "$_gi" > "$_gi.$$.r3c2" 2>/dev/null || true
    mv "$_gi.$$.r3c2" "$_gi"
  fi
  # --- KW6-A2: carve the kit's `Backlog backend` declaration out of the EXPORTED CLAUDE.md ---
  # The kit's root CLAUDE.md is the PRODUCT doc; it doubles as this repo's project config only because
  # the kit self-hosts (incept.sh:15 renames it to ENGINEERING-PRINCIPLES.md and stamps a fresh project
  # CLAUDE.md for a real adopter). It declares `Backlog backend: BACKLOG.md`, but BACKLOG.md itself is
  # export-ignored so incept.sh:344's `[ -f BACKLOG.md ] ||` guard still stamps the adopter their OWN
  # board. A shipped declaration + a pruned board => the adopter tree declares a backend it does not
  # have and conformance/backlog-current.sh:167 hard-FAILs. Strip the declaration from the EXPORT so
  # resolve_backend returns UNDECLARED — the adopter tree N/As by the legitimate "no board declared"
  # route, NOT by weakening the gate (the kit's own CLAUDE.md is untouched; source tree unchanged).
  # Anchor is VERBATIM resolve_backend's field grep (conformance/backlog-lib.sh:19) so the carve and the
  # reader agree on what a declaration IS — if they disagreed the export would ship a live declaration
  # and go green while lying. Fail LOUDLY on a no-op carve (a silent carve is a dark carve): the kit
  # always ships this declaration post-KW6-A2, so ZERO matches means the field's format drifted from the
  # reader — refuse the export rather than ship a tree that might still declare. Idempotent (each fresh
  # `git archive` re-extracts the source line; the carve removes it deterministically).
  _cm="$_dest/CLAUDE.md"
  _cm_anchor='^[-*[:space:]]*\**backlog backend\**[^:]*:'
  if [ -f "$_cm" ]; then
    # Assert EXACTLY ONE anchor match before stripping. The reader (backlog-lib.sh::resolve_backend,
    # :19) takes `grep … | head -1` — it treats one line, the FIRST, as "the declaration". A blind
    # `grep -Eiv` over-carves: it deletes EVERY matching line, so a real declaration plus a prose or
    # fenced-code line beginning "Backlog backend:" would both vanish from the exported doc while the
    # reader only ever considered the first — carve and reader disagreeing about what "the declaration"
    # is. Count lines instead: 0 => the field format drifted from the reader (loud fail — a silent
    # zero-match carve ships the declaration again unnoticed); >1 => ambiguous (loud fail, delete
    # NOTHING — refuse to blind-delete lines the reader never reads); exactly 1 => strip it. `|| true`
    # keeps grep's no-match rc-1 from tripping `set -eu` (grep -c still prints the count "0").
    _cm_n=$(grep -Eic "$_cm_anchor" "$_cm" 2>/dev/null || true)
    if [ "$_cm_n" -eq 0 ]; then
      echo "adopter-export: 'Backlog backend' carve anchor no longer matches CLAUDE.md — the declaration format drifted from conformance/backlog-lib.sh::resolve_backend. Update this carve and the reader together, or remove this carve if the kit stopped declaring a backend." >&2
      return 1
    fi
    if [ "$_cm_n" -gt 1 ]; then
      echo "adopter-export: 'Backlog backend' carve is ambiguous — $_cm_n lines in the exported CLAUDE.md match the declaration anchor, but resolve_backend reads only the first (head -1). Carve and reader disagree about which line is 'the declaration'; refusing to blind-delete $_cm_n lines. Make the kit declare its backend on exactly ONE line (offending lines):" >&2
      grep -Ein "$_cm_anchor" "$_cm" >&2 || true
      return 1
    fi
    # Exactly one match: strip that single line. (`grep -Eiv` removes it; there is only the one.)
    grep -Eiv "$_cm_anchor" "$_cm" > "$_cm.$$.kw6a2" && mv "$_cm.$$.kw6a2" "$_cm"
    # Two-sided dark-carve detection: a declaration must NOT survive the strip.
    if grep -Eiq "$_cm_anchor" "$_cm"; then
      echo "adopter-export: FAILED to carve the 'Backlog backend' declaration from the exported CLAUDE.md" >&2
      rm -f "$_cm.$$.kw6a2"; return 1
    fi
  fi
  _pruned=0
  if [ -n "$_prof" ]; then
    for _p in $(known_profiles); do
      [ "$_p" = "$_prof" ] && continue
      if [ -d "$_dest/profiles/$_p" ]; then rm -rf "$_dest/profiles/$_p"; _pruned=$((_pruned + 1)); fi
      [ -f "$_dest/profiles/$_p.md" ] && rm -f "$_dest/profiles/$_p.md"
    done
    # docs/STACK-SELECTION.md links to every profiles/<stack>.md; after a single-profile prune
    # those 9 links dangle (check-links FAILS on the adopter's first push). Replace it with a stub
    # that links only to the KEPT selected profile, so the exported tree is link-clean. The file
    # still exists, so inbound links (README, START-HERE, the kept profile doc) stay valid.
    # Emit via printf with $_prof as a %s ARGUMENT (never interpreted) — closes any heredoc/sed
    # interpolation class even if a future profile dir name contained shell/regex metacharacters.
    if [ -f "$_dest/docs/STACK-SELECTION.md" ]; then
      {
        printf '# Stack selection\n\n'
        printf 'This export was created for the **%s** profile — see [the profile guide](../profiles/%s.md).\n\n' "$_prof" "$_prof"
        printf 'The full multi-stack comparison matrix lives in the upstream Sparkwright kit\n'
        printf '(`docs/STACK-SELECTION.md`); it is omitted here because the other stack profiles\n'
        printf 'are not included in a single-profile export.\n'
      } > "$_dest/docs/STACK-SELECTION.md"
    fi
  fi
  _src_n=$( ( cd "$ROOT" && git ls-files | wc -l ) | tr -d ' ' )
  _out_n=$(find "$_dest" -type f | wc -l | tr -d ' ')
  # CP-4: a zero-file export is an ERROR, not a success. This used to print "exported 0 files" and
  # return 0 — the adopter got an empty directory and a green exit.
  if [ "$_out_n" -eq 0 ]; then
    echo "adopter-export: exported 0 files — the archive of '$ROOT' was EMPTY. Refusing to report" >&2
    echo "  success on an empty export. (Is the kit a git repo with a committed HEAD?)" >&2
    return 1
  fi
  echo "adopter-export: exported $_out_n files to $_final (kit HEAD tracked $_src_n; pruned $_pruned unused profile(s))"
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  fail=0
  _t=$(mktemp -d)
  _d="$_t/exp"
  do_export "$_d" typescript-node >/dev/null || { echo "FAIL: export errored"; fail=1; }
  # export-ignored → ABSENT. CHANGELOG.md joins this set: the full dev changelog narrates deferred
  # hardening across the whole history and stays private (the public product's release notes live on
  # GitHub Releases). README links to Releases, not to CHANGELOG.md, so the export has no dangling link.
  for p in docs/ROADMAP-KIT.md .github/workflows/golden-path.yml .github/workflows/drift-watch.yml CHANGELOG.md .publish-identifiers; do
    [ -e "$_d/$p" ] && { echo "FAIL: export-ignored path present: $p"; fail=1; } || echo "PASS: absent $p"
  done
  # kept → PRESENT (scripts/fixtures now SHIPS — the tier-advice/agent-scorecard selftests in the
  # adopter ci.yml depend on scripts/fixtures/scorecard/)
  for p in MAINTAINING.md WALKTHROUGH.md conformance templates profiles/_TEMPLATE.md profiles/typescript-node scripts/fixtures/scorecard; do
    [ -e "$_d/$p" ] && echo "PASS: present $p" || { echo "FAIL: kept path missing: $p"; fail=1; }
  done
  # STACK-SELECTION stubbed on --profile: exists + no link to a pruned profile (e.g. go)
  if [ -f "$_d/docs/STACK-SELECTION.md" ] && ! grep -Fq '](../profiles/go.md)' "$_d/docs/STACK-SELECTION.md"; then
    echo "PASS: STACK-SELECTION stubbed (no pruned-profile link)"
  else echo "FAIL: STACK-SELECTION still links a pruned profile (or missing)"; fail=1; fi
  # R3/C2: the exported .gitignore must NOT ignore /src/ or /test/ (an adopter's source goes there)
  if grep -qxE '/(src|test)/' "$_d/.gitignore" 2>/dev/null; then
    echo "FAIL: exported .gitignore still ignores /src/ or /test/ (adopter source un-committable)"; fail=1
  else echo "PASS: exported .gitignore does not ignore /src/ or /test/"; fi
  # KW6-A2: the exported CLAUDE.md must NOT declare a Backlog backend (BACKLOG.md is export-ignored, so
  # a shipped declaration would FAIL the adopter's backlog-current). The carve must resolve to undeclared.
  if grep -Eiq '^[-*[:space:]]*\**backlog backend\**[^:]*:' "$_d/CLAUDE.md" 2>/dev/null; then
    echo "FAIL: exported CLAUDE.md still declares a Backlog backend (carve failed → adopter backlog-current FAILs)"; fail=1
  else echo "PASS: exported CLAUDE.md declares no Backlog backend (carve resolves undeclared → adopter N/As)"; fi
  # S3b: the maintainer-only claims are carved from the export's registry copies
  # (feature-flags-wired is kit-self: it greps the export-ignored golden-path.yml — E2)
  for p in drift-watch golden-path adopter-export feature-flags-wired containment-audit runtime-security structured-logging app-tracing metrics-endpoint otlp-backend trace-query agentops-sensor orchestrator-loop escalation-seam conflict-safe-integration skill-spine; do
    if grep -q "^$p$(printf '\t')" "$_d/conformance/claims.tsv"; then echo "FAIL: claim $p not carved from claims.tsv"; fail=1
    else echo "PASS: $p carved from claims.tsv"; fi
    if grep -qE '[" ]'"$p"'[ "]' "$_d/conformance/claims-registry.sh"; then echo "FAIL: $p not carved from REQUIRED_IDS"; fail=1
    else echo "PASS: $p carved from REQUIRED_IDS"; fi
  done
  # pruned profile → ABSENT
  [ -e "$_d/profiles/go" ] && { echo "FAIL: pruned profile present: go"; fail=1; } || echo "PASS: pruned profiles/go"
  [ -e "$_d/profiles/go.md" ] && { echo "FAIL: pruned profile doc present: go.md"; fail=1; } || echo "PASS: pruned profiles/go.md"
  # R3/C2 bare-export path: export WITHOUT a profile arg must also strip /src/ and /test/
  _d2="$_t/exp2"
  do_export "$_d2" >/dev/null 2>&1 || { echo "FAIL: bare export errored"; fail=1; }
  if grep -qxE '/(src|test)/' "$_d2/.gitignore" 2>/dev/null; then
    echo "FAIL: bare-export .gitignore still ignores /src/ or /test/"; fail=1
  else echo "PASS: bare-export .gitignore clean"; fi
  # unknown profile → nonzero
  if ( do_export "$_t/exp3" nonsuch >/dev/null 2>&1 ); then echo "FAIL: unknown profile accepted"; fail=1; else echo "PASS: unknown profile rejected"; fi
  # non-empty dest → nonzero
  mkdir -p "$_t/full"; : > "$_t/full/x"
  if ( do_export "$_t/full" >/dev/null 2>&1 ); then echo "FAIL: non-empty dest accepted"; fail=1; else echo "PASS: non-empty dest rejected"; fi
  # exactly one stack profile dir remains
  _np=$(find "$_d/profiles" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$_np" = "1" ] && echo "PASS: exactly one stack profile dir remains" || { echo "FAIL: $_np profile dirs remain (expected 1)"; fail=1; }
  # export is non-empty
  _tot=$(find "$_d" -type f | wc -l | tr -d ' ')
  [ "$_tot" -gt 0 ] && echo "PASS: export non-empty ($_tot files)" || { echo "FAIL: export empty"; fail=1; }
  # KW6-A2 over-carve lock: a CLAUDE.md carrying >1 anchor-matching `Backlog backend` lines must make
  # the export LOUD-FAIL (rc != 0) and delete NOTHING. resolve_backend reads only head -1, so blind-
  # deleting every match would strip lines the reader never considers — carve and reader disagreeing
  # about which line is "the declaration". The carve runs on `git archive HEAD`, so a two-declaration
  # scenario is unreachable through the real kit HEAD (which declares exactly one); prove it in a
  # throwaway git repo whose HEAD carries two declarations, driving a byte-COPY of THIS script (its
  # ROOT resolves to the throwaway repo, so it archives that HEAD, exercising the real carve verbatim).
  # Mirrors _test-t3b-overcarve.sh case 3, made self-contained for the shipped --selftest.
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  _g="$_t/twodecl"; mkdir -p "$_g/scripts"
  cp "$_self" "$_g/scripts/adopter-export.sh"
  {
    printf '# Proj\n\n'
    printf -- '- **Backlog backend**: BACKLOG.md (repo-native)\n\n'
    printf '```\n'
    printf 'Backlog backend: jira\n'
    printf '```\n'
  } > "$_g/CLAUDE.md"
  ( cd "$_g" && git init -q && git add -A \
      && git -c user.email=t@kit -c user.name=t commit -qm two >/dev/null 2>&1 )
  _gd="$_t/twodecl-exp"
  if ( cd "$_g" && sh scripts/adopter-export.sh "$_gd" >/dev/null 2>&1 ); then
    echo "FAIL: >1 Backlog-backend declarations did not loud-fail the export (over-carve unguarded)"; fail=1
  else
    echo "PASS: >1 Backlog-backend declarations loud-fail the export (rc != 0)"
  fi
  # CP-4: INVERTED. This assertion used to demand that a refused carve LEAVE the destination
  # populated ("should extract before refusing") — which is exactly what wedged the adopter's retry.
  # The export is atomic now: a failure leaves NO destination, and the retry must succeed.
  if [ -e "$_gd" ]; then
    echo "FAIL: a failed export LEFT A DESTINATION behind — the retry is wedged (export must be atomic)"; fail=1
  else
    echo "PASS: a failed export left no destination (stage -> verify -> atomic rename)"
    # Liveness — the RIGHT test for atomicity. The retry must not be WEDGED by the first attempt's
    # leftover state. The two-declaration CLAUDE.md is committed, so a bare retry would re-fail for the
    # legitimate original reason (ambiguous carve), NOT a wedge — so first REPAIR the cause (drop one
    # declaration, commit), THEN retry the SAME dest. With the pre-CP-4 code the first failed attempt
    # left "$_gd" populated and this retry would hit "refusing to clobber"; atomic export leaves
    # nothing, so it succeeds. THAT is the invariant this asserts.
    _repaired() { printf '# Proj\n\n- **Backlog backend**: BACKLOG.md (repo-native)\n'; }
    if ( cd "$_g" && _repaired > CLAUDE.md && git add -A \
           && git -c user.email=t@kit -c user.name=t commit -qm repair >/dev/null 2>&1 \
           && sh scripts/adopter-export.sh "$_gd" >/dev/null 2>&1 ); then
      echo "PASS: after repairing the cause, the retry succeeds (not wedged by leftover state)"
    else
      echo "FAIL: the retry is wedged — a failed export blocked a later good one (atomicity broken)"; fail=1
    fi
  fi
  rm -rf "$_t"
  [ "$fail" -eq 0 ] && { echo "OK: adopter-export selftest"; exit 0; } || { echo "FAIL: adopter-export selftest"; exit 1; }
fi

# — main —
DEST=""; PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) [ $# -ge 2 ] || usage; PROFILE=$2; [ -n "$PROFILE" ] || { echo "adopter-export: --profile requires a non-empty stack name" >&2; usage; }; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "adopter-export: unknown flag $1" >&2; usage ;;
    *) [ -z "$DEST" ] || usage; DEST=$1; shift ;;
  esac
done
[ -n "$DEST" ] || usage
do_export "$DEST" "$PROFILE"
