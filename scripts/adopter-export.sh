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

# B6 rider (c) — ADOPTER-EXPORT-CARVES-FOREIGN-TREES. Every policy carve below (claims.tsv/registry,
# .gitignore's kit-dogfood lines, CLAUDE.md's Backlog-backend line, .gitattributes' export-ignore
# stub) is KIT-SELF logic: it strips THIS repo's own maintainer-only declarations out of the export.
# $ROOT is derived from `dirname "$0"` (line 12) — wherever this exact SCRIPT FILE happens to live —
# so if adopter-export.sh is vendored into a FOREIGN tree (a downstream derivative that keeps its own
# copy of this script) and run there, $ROOT resolves to THAT tree, and every carve below would
# blindly strip the FOREIGN tree's own, legitimate declarations, believing them to be the kit's (the
# A6 measured deletion class). Gate each carve on this tree actually LOOKING like the kit's own dev
# tree: >=1 KIT_INTERNAL_MARKERS file present in $ROOT — the SAME soundness-locked set incept.sh
# refuses on, parsed the way conformance/incept-containment.sh:18 does (the single source of truth,
# not a second, driftable copy of the list).
# DISCLOSED FALSE-POSITIVE BOUND (rider (c)): a brownfield tree produced by a literal `git clone` of
# this repo (rather than `scripts/incept.sh`, which strips the markers on install) still carries every
# KIT_INTERNAL_MARKERS file, so this gate reads it as the kit's own dev tree and carves it as such —
# even though its maintainer-only declarations are legitimately the brownfield adopter's, not the
# kit's. Known, not fixed here; see docs/adoption/brownfield.md for the clone-adoption path.
_ae_kit_tree_markers() {
  sed -n "s/^KIT_INTERNAL_MARKERS='\\(.*\\)'.*/\\1/p" "$ROOT/scripts/incept.sh" 2>/dev/null
}
_ae_is_kit_tree() {
  _aekt=0
  for _aem in $(_ae_kit_tree_markers); do
    [ -e "$ROOT/$_aem" ] && { _aekt=1; break; }
  done
  [ "$_aekt" = 1 ]
}

# --- CP-4: repository ownership is a hard precondition -------------------------------------
# `git rev-parse --is-inside-work-tree` answers "is there a repo ABOVE me?" — not "is THIS dir the
# root of its own repo?". The two diverge only when nested, which is why every non-nested test
# agrees and why the kit once wrote a pre-push hook into a stranger's repository.
#
# BOTH sides of the compare must be PHYSICAL paths: `--show-toplevel` is symlink-resolved, `$PWD`
# is not. On macOS /tmp -> /private/tmp, so a logical compare FALSE-REFUSES under /tmp while
# passing on Linux CI. Normalizing both sides is the only compare that cannot drift.
#
# CP-11 closes the git-dir-CONTAINMENT gap: an ambient GIT_DIR/GIT_WORK_TREE env redirect is now hard-
# refused here (env-ONLY — adopter-export takes no nested-tree path, so there is no --allow-nested gate).
# Residual (named, not absorbed): core.hooksPath, GIT_OBJECT_DIRECTORY, insteadOf — the git dir stays
# inside the cwd, so containment passes; out of CP-11 scope. See CP-11 design §6.
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

# CP-11: an ambient GIT_DIR/GIT_WORK_TREE makes `git archive HEAD` read a repo OTHER than the kit. This is
# env-ONLY: a structural linked worktree archives the kit's own HEAD correctly and maintainers run from
# worktrees, so it must NOT refuse those (spec §3b). See CP-11 / conformance/repo-ownership.sh (E3, P3).
git_env_redirected() { [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; }

# K1: `mkdir adopter && cd adopter && git init` and THEN export is the natural adopter order — and
# the emptiness test above refused it, because a `.git`-only directory is not empty. A destination
# whose SINGLE entry is a real `.git` DIRECTORY is accepted; anything else is not. Deliberately
# exact-match on the entry name and deliberately not a symlink: `.git` plus a README is a populated
# tree (still refused), and a symlinked `.git` would let the staged tree be written through a link
# to a path the adopter never named. The repo itself is not inspected — a `.git` with history is
# accepted too; the adopter asked for that.
dest_only_holds_git() {  # <dest> -> 0 when the ONLY entry is a real, non-symlink .git dir
  _dg=$1
  [ "$(ls -A "$_dg" 2>/dev/null)" = ".git" ] || return 1
  [ -d "$_dg/.git" ] && [ ! -L "$_dg/.git" ]
}

# CP-4: do_export is now ATOMIC. It stages into a sibling temp dir, verifies, and only then renames
# into place. Previously it extracted into <dest> BEFORE the carve could fail — so a failed export
# left a non-empty <dest>, and the retry hit "refusing to clobber". The adopter was WEDGED, and the
# selftest ASSERTED that wedge ("should extract before refusing"). The design was wrong; this is it
# corrected. A failed export now leaves NO destination.
do_export() {  # <dest> <profile-or-empty>  — atomic: stage -> verify -> rename
  _final=$1; _prof=${2:-}; _keep_git=0
  [ -n "$_final" ] || { echo "adopter-export: missing dest" >&2; return 2; }
  if [ -e "$_final" ] && [ -n "$(ls -A "$_final" 2>/dev/null)" ]; then
    if dest_only_holds_git "$_final"; then
      _keep_git=1
    else
      echo "adopter-export: dest '$_final' exists and is not empty — refusing to clobber" >&2; return 1
    fi
  fi
  if [ -n "$_prof" ] && ! known_profiles | grep -qxF -- "$_prof"; then
    echo "adopter-export: unknown profile '$_prof' (known: $(known_profiles | tr '\n' ' '))" >&2; return 1
  fi
  # CP-4: the kit must be the root of its OWN repo. Nested in a foreign worktree as an UNTRACKED dir,
  # `git archive HEAD` resolves to the PARENT's HEAD and the cwd prefix matches nothing — yielding an
  # empty archive, "exported 0 files", and exit 0. A silent success is the worst failure mode there is.
  if git_env_redirected; then
    echo "adopter-export: your git environment redirects git away from the kit." >&2
    [ -n "${GIT_DIR:-}" ]       && echo "  GIT_DIR=$GIT_DIR" >&2
    [ -n "${GIT_WORK_TREE:-}" ] && echo "  GIT_WORK_TREE=$GIT_WORK_TREE" >&2
    echo "  'git archive HEAD' would archive THAT repo's HEAD, not the kit. Clear the redirect:" >&2
    echo "    env -u GIT_DIR -u GIT_WORK_TREE sh scripts/adopter-export.sh <dest>" >&2
    return 1
  fi
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
    if [ "$_keep_git" = 1 ]; then
      # K1: `.git` lives IN <dest>, so `rmdir` can never clear it and the atomic rename is not
      # available. Move the staged CONTENTS in instead, one same-filesystem `mv` per top-level
      # entry (dotfiles included; `git archive` never carries a `.git`, so nothing collides with
      # the adopter's repo). HONEST CEILING: this one path is NOT atomic — a mid-move failure
      # leaves <dest> partially populated, and the message below says so rather than pretending.
      _final_abs=$(cd "$_final" && pwd) || { rm -rf "$_stage"; return 1; }
      if ! ( cd "$_stage" && find . -mindepth 1 -maxdepth 1 -exec mv -- {} "$_final_abs/" \; ); then
        # DELIBERATELY NOT `rm -rf "$_stage"`. On every OTHER failure path the staged tree is
        # discarded because <dest> was never touched; here it WAS, so the stage holds whatever did
        # not make it across. Deleting it would destroy the only copy of the un-moved remainder and
        # leave the operator with a half-populated destination and nothing to complete it from.
        echo "adopter-export: could not move the staged export into '$_final' — it is now" >&2
        echo "  PARTIALLY POPULATED. The staged tree is DELIBERATELY LEFT IN PLACE at:" >&2
        echo "    $_stage" >&2
        echo "  Inspect it, complete the move by hand, or remove everything in '$_final' except" >&2
        echo "  .git and re-run; delete the staging dir yourself when you are done with it." >&2
        return 1
      fi
      rm -rf "$_stage"
      return 0
    fi
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
  # conformance/adopter-export-claims.sh face-0 goes RED (it runs the adopter's full claims-registry
  # on the kit-marked export — in the cf-export-claims job per non-docs PR and weekly in drift-watch;
  # un-nested from adopter-export-wired.sh at NON-VACUITY-SHARD2-FLOOR, 2026-08-15).
  # adopter-export is ALSO carved: it is a kit-self check (an adopter has no reason to verify the kit's
  # OWN export mechanism). The old recursion chain (claims-registry -> adopter-export-wired.sh ->
  # claims-registry -> ...) is broken by the un-nesting; the live recursion stop is
  # adopter-export-claims.sh's marker-absent N/A (the check stands down on any exported tree before
  # building anything). The kit still verifies adopter-export in its own CI.
  # ratification-parity is carved for the same kit-self reason: it verifies the kit's OWN install
  # mechanism (that incept ships the §13 gate for every stack), its real run N/As on an adopter tree, and
  # its --selftest drives real incept via `git archive` — which needs the kit's .git, absent in an export.
  # The kit still verifies ratification-parity in its own CI. The installed gate itself is unaffected.
  if _ae_is_kit_tree; then
    _ct="$_dest/conformance/claims.tsv"; _cr="$_dest/conformance/claims-registry.sh"
    if [ -f "$_ct" ] && [ -f "$_cr" ]; then
      _tab=$(printf '\t')
      for _c in drift-watch golden-path adopter-export repo-ownership feature-flags-wired containment-audit runtime-security structured-logging app-tracing metrics-endpoint otlp-backend trace-query agentops-sensor orchestrator-loop escalation-seam conflict-safe-integration skill-spine ratification-parity adopter-gates-parity; do
        grep -v "^${_c}${_tab}" "$_ct" > "$_ct.$$.s3b" && mv "$_ct.$$.s3b" "$_ct"
        sed "s/ ${_c}\\([\"[:space:]]\\)/\\1/" "$_cr" > "$_cr.$$.s3b" && mv "$_cr.$$.s3b" "$_cr"
      done
    fi
  else
    echo "adopter-export: S3b claims carve SKIPPED — '$ROOT' does not look like the kit's own dev tree (no KIT_INTERNAL_MARKERS present) — expected when exporting from a public clone or the published mirror (an export of an export); nothing is wrong; a foreign tree's claims.tsv/claims-registry.sh ship untouched"
  fi
  # R3/C2: the kit's root .gitignore ignores /src/ and /test/ (stray KIT dogfooding output); an
  # adopter puts product source there, so strip those two EXACT lines from the EXPORTED .gitignore
  # (the kit's own .gitignore is untouched). `grep -vx` matches whole lines only, so an adopter path
  # like `my/src/lib` or `/src/foo` is never clobbered. Idempotent.
  if _ae_is_kit_tree; then
    _gi="$_dest/.gitignore"
    if [ -f "$_gi" ]; then
      grep -vxE '/(src|test)/' "$_gi" > "$_gi.$$.r3c2" 2>/dev/null || true
      mv "$_gi.$$.r3c2" "$_gi"
    fi
  else
    echo "adopter-export: .gitignore /src//test/ carve SKIPPED — '$ROOT' does not look like the kit's own dev tree (no KIT_INTERNAL_MARKERS present) — expected when exporting from a public clone or the published mirror (an export of an export); nothing is wrong; a foreign tree's .gitignore ships untouched"
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
  # and go green while lying. Idempotent BY DESIGN: 1 match => strip it (the dev-source path); 0 matches
  # => already carved, nothing to strip => pass (the export-of-an-export path — the public mirror is
  # itself an export). Because the anchor IS the reader's grep, zero matches means the reader sees no
  # declaration, which is precisely the post-state to guarantee — so a no-op carve is success, not drift.
  # The only loud-fail is >1 (ambiguous — refuse to blind-delete lines the reader never reads).
  _cm="$_dest/CLAUDE.md"
  _cm_anchor='^[-*[:space:]]*\**backlog backend\**[^:]*:'
  if ! _ae_is_kit_tree; then
    echo "adopter-export: 'Backlog backend' CLAUDE.md carve SKIPPED — '$ROOT' does not look like the kit's own dev tree (no KIT_INTERNAL_MARKERS present) — expected when exporting from a public clone or the published mirror (an export of an export); nothing is wrong; a foreign tree's declaration ships untouched"
  elif [ -f "$_cm" ]; then
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
      # 0 matches = the tree is ALREADY in the exported post-state: its CLAUDE.md declares no backend.
      # This is the NORMAL, correct input whenever adopter-export runs on its own output — the published
      # public mirror IS an export (publish-public.sh generates it via adopter-export), and the README
      # has the adopter re-export that mirror (export-of-an-export). Because this anchor is verbatim
      # resolve_backend's grep (backlog-lib.sh:19), zero anchor matches == the reader will find no
      # declaration == exactly the post-state this carve exists to guarantee. Nothing to strip → pass.
      # (This makes adopter-export a fixpoint: export(export(X)) == export(X); locked by
      # conformance/adopter-export-wired.sh block (g). A genuine format-drift in the DEV source is
      # harmless here for the same reason — a declaration the anchor can't see, the reader can't read
      # either, so the export never ships a live backend. The >1 case below still loud-fails.)
      :
    fi
    if [ "$_cm_n" -gt 1 ]; then
      echo "adopter-export: 'Backlog backend' carve is ambiguous — $_cm_n lines in the exported CLAUDE.md match the declaration anchor, but resolve_backend reads only the first (head -1). Carve and reader disagree about which line is 'the declaration'; refusing to blind-delete $_cm_n lines. Make the kit declare its backend on exactly ONE line (offending lines):" >&2
      grep -Ein "$_cm_anchor" "$_cm" >&2 || true
      return 1
    fi
    # Exactly one match: strip that single line. (`grep -Eiv` removes it; there is only the one.) The
    # 0-match case also falls through to here and is a deliberate safe no-op: `grep -Eiv` re-emits every
    # line unchanged, so the mv rewrites CLAUDE.md identically. Keep this in mind before editing below.
    grep -Eiv "$_cm_anchor" "$_cm" > "$_cm.$$.kw6a2" && mv "$_cm.$$.kw6a2" "$_cm"
    # Two-sided dark-carve detection: a declaration must NOT survive the strip.
    if grep -Eiq "$_cm_anchor" "$_cm"; then
      echo "adopter-export: FAILED to carve the 'Backlog backend' declaration from the exported CLAUDE.md" >&2
      rm -f "$_cm.$$.kw6a2"; return 1
    fi
    # K12 Cause B: normalize the blank line(s) the carve orphaned. Deleting the `Backlog backend:`
    # declaration leaves the blank ABOVE it adjacent to the blank BELOW it, and where that lands
    # depends on where the declaration sits — which is why this must not assume a position:
    #   - at EOF (the pre-A1.1 shape, when it was CLAUDE.md's LAST content line) the orphan became a
    #     trailing blank -> `git diff --check`: "new blank line at EOF";
    #   - MID-FILE (its shape since the Roster-authority section moved to the top — MEASURED at line 20
    #     of 132) the orphan becomes a DOUBLE BLANK, which the old trailing-only trim did not touch.
    # Both are inherited by incept.sh into the renamed ENGINEERING-PRINCIPLES.md.
    # This re-emit collapses any run of blank lines to exactly one and drops leading/trailing blanks, so
    # it is POSITION-INDEPENDENT and covers both. UNCONDITIONAL and naturally idempotent: on an
    # already-clean file (the 0-match export-of-an-export path) it re-emits byte-identically, so the
    # block-(g) fixpoint holds — VERIFIED, along with byte-identity against the previous trailing-only
    # form on the `main` baseline. Locked by conformance/adopter-export-wired.sh block (h).
    # (This awk RUNS at export time on the temp export file $_cm — never on kit source.)
    awk 'NF==0{b=1;next} {if(n++ && b) print ""; b=0; print}' "$_cm" > "$_cm.$$.ws" && mv "$_cm.$$.ws" "$_cm"
  fi
  # --- A6: carve the kit's maintainer-only `.gitattributes` export-ignore rules out of the EXPORT ---
  # The kit's root .gitattributes export-ignores its OWN maintainer-only files (ci.yml, ratification.yml,
  # docs/architecture/, CHANGELOG.md, BACKLOG.md, the governance meta-control-log, ...) from `git archive`.
  # Shipped verbatim, that file makes the ADOPTER's `git archive HEAD` silently DROP the very files incept
  # installs (their CI workflows + ADRs) plus their own CHANGELOG / backlog / governance log — the adopter's
  # archive loses the adopter's work. Every kit entry is `export-ignore` (no eol/text/diff attribute), so
  # replacing the file loses ZERO mechanical function. Replace the kit-OWN file with a self-documenting stub
  # (design 2026-08-04-gitattributes-inheritance, option B + stub). MARKER-GUARDED + idempotent: only a file
  # whose FIRST line is the kit marker is replaced — an already-stubbed file (export-of-an-export, the
  # block-(g) fixpoint) or an adopter's own .gitattributes is left byte-identical, so export(export(X)) holds.
  # (A6's shipped state is a byte-identical kit file, so a whole-file replace of the kit-own file is the
  # simplest correct carve; a brownfield adopter who CONCATENATED their lines under the kit block owns that
  # bespoke merge — routed to ADOPTER-EXPORT-CARVES-FOREIGN-TREES, out of A6 scope.) Mutates ONLY the
  # staging copy $_dest/.gitattributes; the kit's own file is NEVER touched.
  if ! _ae_is_kit_tree; then
    echo "adopter-export: .gitattributes A6 stub-carve SKIPPED — '$ROOT' does not look like the kit's own dev tree (no KIT_INTERNAL_MARKERS present) — expected when exporting from a public clone or the published mirror (an export of an export); nothing is wrong; a foreign tree's .gitattributes ships untouched (closes the class this carve's own header names as 'out of A6 scope')"
  else
    _ga="$_dest/.gitattributes"
    if [ -f "$_ga" ]; then
      IFS= read -r _ga_first < "$_ga" || _ga_first=''
      case "$_ga_first" in
        '# Maintainer-only paths excluded from'*)
          {
            printf '# .gitattributes — an adopter distribution intentionally carries NO export-ignore rules.\n'
            printf '# The upstream kit export-ignores its OWN maintainer-only files from `git archive`; those\n'
            printf '# rules were carved out here (scripts/adopter-export.sh) so YOUR `git archive` KEEPS your\n'
            printf '# work — your CI workflows, ADRs, CHANGELOG, backlog and governance log ship, not vanish.\n'
            printf '# Add your own attributes (text / eol / linguist / merge) below as your project needs them.\n'
          } > "$_ga.$$.a6" && mv "$_ga.$$.a6" "$_ga"
          ;;
      esac
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
  # --- P1.2-pre: the export STATES what it shipped (.kit-manifest) -----------------------------------
  # The exporter is the ONLY actor that knows the kit-own file set: it just built it (git archive, minus
  # export-ignore, minus the --profile prune above) and, until now, threw it away. Every attempt to
  # RE-DERIVE that set afterwards has failed — cp_kit_replace's marker does not even survive inception
  # (the kit's ci.yml carries `Kit-own CI`; the profiles/*/ci.yml incept installs in its place carries
  # none). So record the FACT here, where it is still known. Locked by conformance/kit-manifest.sh;
  # consumed by scripts/incept.sh to vendor the `kit-base` orphan branch.
  #
  # Emitted AFTER the carves and the prune, so it describes the FINAL tree the adopter receives — a
  # --profile export therefore states its PRUNED contents, which is what makes a per-adopter merge base
  # well-defined ("the tree at version X" is otherwise NOT unique: the public mirror ships un-pruned).
  #
  # Two pinned decisions, both load-bearing:
  #   LC_ALL=C — a locale-dependent sort order makes the manifest non-reproducible across machines, and
  #              this artifact's entire job is to be a stable, comparable fact. It would pass on one box.
  #   self-listing — the manifest is part of the export, so kit-base must be able to carry it forward.
  # -type f ONLY (not -type l): the manifest must never NAME a symlink. A symlink in the manifest would
  # let incept's kit-base capture copy a file from outside the export into a committed git ref (review
  # #318 S1). The kit ships zero symlinks, so this drops nothing; conformance/kit-manifest.sh's own scan
  # DOES include -type l, so a symlink appearing on disk but absent from the manifest turns it RED.
  _mf=$(mktemp) || { echo "adopter-export: mktemp failed (manifest)" >&2; return 1; }
  { ( cd "$_dest" && find . -type f | sed 's|^\./||' ); echo '.kit-manifest'; } \
    | LC_ALL=C sort -u > "$_mf" || { rm -f "$_mf"; echo "adopter-export: manifest build failed" >&2; return 1; }
  if [ ! -s "$_mf" ]; then
    rm -f "$_mf"; echo "adopter-export: refusing to write an EMPTY .kit-manifest" >&2; return 1
  fi
  mv "$_mf" "$_dest/.kit-manifest" && chmod 644 "$_dest/.kit-manifest"

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
  # docs/governance/DECISIONS.md joins this set (TRIAL-PREP-FIRST-MILE): the kit's ruling ledger is
  # about the kit's own internals, and the entry contract sends every agent into it — so an adopter
  # gets an EMPTY one stamped by incept.sh, never ours. The A6 leg below asserts the stamped copy
  # SURVIVES in the adopter's own archive; this line asserts the kit's copy never arrives.
  # ARCHIVE-SAFE-SET.txt joins it too (review round): adopter-export-wired.sh does NOT demand an IGN
  # entry for it — its link scan reads KEPT `.md` docs, and IGN is deliberately a subset rather than
  # an equality — so this line is the ONLY thing that proves the new export-ignore took effect.
  # conformance/mass-acks.txt joins the set for ARCHIVE-SAFE-SET.txt's exact reason (CUT-A7): it is
  # export-ignored, adopter-export-wired.sh does NOT demand an IGN entry for it (IGN is a subset, and
  # its link scan reads KEPT `.md` docs), so this line is the ONLY thing that proves the attribute
  # took effect. It also guards a live hazard: conformance/ ships wholesale, so a leaked ledger would
  # arrive in an adopter tree as a bypass surface for a ratchet they never adopted.
  # WALKTHROUGH.md joins the set (FRONT-DOOR-ONE-ROUTER): it MOVED from the kept list below into this
  # absence list when the one-router front door retired it. It is a KEPT-list veteran, so the move is
  # the only thing that proves the new export-ignore attribute actually took effect — a deletion from
  # the kept list alone would have shipped a botched .gitattributes entry green.
  for p in docs/ROADMAP-KIT.md .github/workflows/golden-path.yml .github/workflows/drift-watch.yml CHANGELOG.md docs/governance/DECISIONS.md ARCHIVE-SAFE-SET.txt conformance/mass-acks.txt WALKTHROUGH.md .publish-identifiers; do
    [ -e "$_d/$p" ] && { echo "FAIL: export-ignored path present: $p"; fail=1; } || echo "PASS: absent $p"
  done
  # kept → PRESENT (scripts/fixtures now SHIPS — the tier-advice/agent-scorecard selftests in the
  # adopter ci.yml depend on scripts/fixtures/scorecard/)
  for p in MAINTAINING.md conformance templates profiles/_TEMPLATE.md profiles/typescript-node scripts/fixtures/scorecard; do
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
  _g="$_t/twodecl"; mkdir -p "$_g/scripts" "$_g/docs"
  cp "$_self" "$_g/scripts/adopter-export.sh"
  cp "$ROOT/scripts/incept.sh" "$_g/scripts/incept.sh"   # B6 rider (c): _ae_is_kit_tree reads KIT_INTERNAL_MARKERS from here
  # B6 rider (c): this fixture asserts KIT-TREE carve behaviour (the over-carve loud-fail), so it
  # must actually LOOK like a kit tree — plant one KIT_INTERNAL_MARKERS file. Without it,
  # _ae_is_kit_tree correctly reads FALSE (this throwaway repo carries none of the kit's own
  # markers) and the carve — and this whole assertion — would be silently skipped.
  : > "$_g/docs/ROADMAP-KIT.md"
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
  # --- A6: end-to-end archive-retention lock (design 2026-08-04-gitattributes-inheritance, "The lock").
  # The property that matters is NOT "the file has certain bytes" but "the ADOPTER's git archive keeps the
  # ADOPTER's work". Real export -> real incept -> add adopter files -> commit -> `git archive HEAD` MUST
  # retain every collision path in _a6_targets: incept's own CI workflows + ADR-000 + the stamped
  # backlog + the stamped decision ledger (the files the
  # kit's .gitattributes export-ignores AND incept installs), plus adopter-added ADR-001, CHANGELOG, and
  # the governance meta-control-log. Load-bearing negative: replanting the kit's export-ignore
  # .gitattributes into the same tree MUST drop those paths (proves the check has teeth + that the CARVE
  # is what retains them). This leg drives real incept/export from the kit's .git (ratification-parity
  # precedent); it is wired into CI by scripts/adopter-export.sh --selftest (ci.yml), enforced present by
  # conformance/ci-selftest-coverage.sh — no new claim id.
  # HONEST CEILING: this leg is NOT reached by the non-vacuity mutation sweep — target_set() greps
  # `conformance/*.sh` control checks only, so `non-vacuity.sh --only adopter-export` exits 2 (no match).
  # ci-selftest-coverage proves the selftest RUNS, not that any leg is non-vacuous, so a future edit
  # neutering the carve-match or the replant would keep CI green. Teeth here are this --selftest leg +
  # hand mutation-testing (both legs driven RED at build) — weaker than the sweep, and named as such
  # (same ceiling the kit records for the kit-base / .kit-manifest locks).
  # docs/governance/DECISIONS.md is the 8th target (TRIAL-PREP-FIRST-MILE): incept stamps an EMPTY
  # ledger, the kit export-ignores its own, and the adopter's copy must survive their `git archive`
  # exactly like their stamped backlog does. It is the seeded-file half of the same lockstep.
  _a6_targets='.github/workflows/ci.yml .github/workflows/ratification.yml docs/architecture/ADR-000-stack.md docs/architecture/ADR-001-x.md CHANGELOG.md BACKLOG.md docs/governance/meta-control-log.md docs/governance/DECISIONS.md'
  # The count in the PASS line is DERIVED from the list, never transcribed: the previous hardcoded "7"
  # was one edit away from attesting to a number the list no longer had.
  # shellcheck disable=SC2086 # deliberate word-splitting — _a6_targets is a space-separated path list
  _a6_n=$( set -- $_a6_targets; echo $# )
  # _a6_dropped <incepted+committed tree> : echo each target path NOT in `git archive HEAD` (empty = all kept)
  _a6_dropped() {
    _al=$( ( cd "$1" && git archive HEAD 2>/dev/null | tar -t 2>/dev/null ) )
    for _p in $_a6_targets; do
      printf '%s\n' "$_al" | grep -qxF "$_p" || printf '%s\n' "$_p"
    done
  }
  # _a6_build_adopter <tree> : incept the exported tree in place, add the adopter files, git-init + commit.
  _a6_build_adopter() {
    ( cd "$1" && sh scripts/incept.sh --name A6Retain --intent-owner probe \
        --stack typescript-node --backlog md --ci github --noninteractive >/dev/null 2>&1 ) || return 1
    _a6_gov="docs/governance"; _a6_mcl="$_a6_gov/meta-control-log.md"
    ( cd "$1" \
        && printf '# ADR-001\n' > docs/architecture/ADR-001-x.md \
        && printf '# Changelog\n' > CHANGELOG.md \
        && mkdir -p "$_a6_gov" && printf 'log\n' > "$_a6_mcl" \
        && git init -q && git add -A \
        && git -c gc.auto=0 -c user.email=t@kit -c user.name=t commit -qm adopter >/dev/null 2>&1 ) || return 1
  }
  _a6d=$(mktemp -d); _a6exp="$_a6d/exp"
  if do_export "$_a6exp" typescript-node >/dev/null 2>&1 && _a6_build_adopter "$_a6exp"; then
    _a6_miss=$(_a6_dropped "$_a6exp")
    if [ -z "$_a6_miss" ]; then
      echo "PASS: A6 — the adopter's git archive keeps all $_a6_n target paths (the carve retains the adopter's work)"
    else
      echo "FAIL: A6 — the adopter's git archive DROPPED: $(printf '%s' "$_a6_miss" | tr '\n' ' ')"; fail=1
    fi
    # Load-bearing negative: replant the kit's export-ignore .gitattributes, recommit, re-archive -> the
    # target paths MUST drop again. If they do not, the retention check is vacuous.
    cp "$ROOT/.gitattributes" "$_a6exp/.gitattributes"
    ( cd "$_a6exp" && git add -A && git -c gc.auto=0 -c user.email=t@kit -c user.name=t commit -qm replant >/dev/null 2>&1 ) || true
    _a6_miss2=$(_a6_dropped "$_a6exp")
    if [ -n "$_a6_miss2" ]; then
      echo "PASS: A6 negative — replanting the kit's export-ignore .gitattributes drops target paths (retention check is non-vacuous)"
    else
      echo "FAIL: A6 negative — kit export-ignore .gitattributes dropped NO target path (retention check is vacuous)"; fail=1
    fi
  else
    echo "FAIL: A6 — could not build the export/incept fixture for the archive-retention lock"; fail=1
  fi
  # Teardown must NEVER decide a verdict (P0-FU(a), the green-on-clone.sh pattern): the fixture is a
  # git-inited tree, and a detached git gc still writing into .git races a bare rm into ENOTEMPTY
  # under `set -eu` — reddening a PASSING selftest (measured: PR #501 battery 2, 2026-08-07).
  rm -rf "$_a6d" 2>/dev/null || true

  # --- B6 rider (c) — ADOPTER-EXPORT-CARVES-FOREIGN-TREES: a FOREIGN tree's own, legitimate policy
  # declarations must SURVIVE being run through this script — every carve above is KIT-SELF logic and
  # must not fire when $ROOT is not the kit's own dev tree (no KIT_INTERNAL_MARKERS present). A byte-
  # COPY of this script is driven from a throwaway repo carrying NONE of the kit's markers, but WITH
  # each carve's OWN trigger shape: a Backlog-backend CLAUDE.md declaration, a .gitignore /src//test/
  # line, a .gitattributes whose first line is the EXACT A6 marker text (the brownfield-concatenation
  # shape A6's own header names as "out of A6 scope"), and a claims.tsv/claims-registry.sh carrying
  # one of the carved claim ids. The measured A6 deletion is the negative this proves closed.
  echo "--- B6 rider (c): a foreign tree's declarations survive export (no KIT_INTERNAL_MARKERS) ---"
  _fx="$_t/foreign"; mkdir -p "$_fx/scripts" "$_fx/conformance"
  cp "$_self" "$_fx/scripts/adopter-export.sh"
  cp "$ROOT/scripts/incept.sh" "$_fx/scripts/incept.sh"
  printf '# Foreign Project\n\n- **Backlog backend**: BACKLOG.md (repo-native)\n' > "$_fx/CLAUDE.md"
  printf '/src/\n/test/\nmy-own-rule\n' > "$_fx/.gitignore"
  printf '# Maintainer-only paths excluded from THIS foreign tree'"'"'s own archive (not the kit'"'"'s)\nsome/foreign/path export-ignore\n' > "$_fx/.gitattributes"
  _ftab=$(printf '\t')
  printf 'drift-watch%sa foreign claim%stest -x /%stree\n' "$_ftab" "$_ftab" "$_ftab" > "$_fx/conformance/claims.tsv"
  printf '#!/bin/sh\nREQUIRED_IDS="drift-watch"\n' > "$_fx/conformance/claims-registry.sh"
  ( cd "$_fx" && git init -q && git add -A \
      && git -c user.email=f@foreign -c user.name=foreign commit -qm foreign >/dev/null 2>&1 )
  _fxd="$_t/foreign-exp"
  if ( cd "$_fx" && sh scripts/adopter-export.sh "$_fxd" >/dev/null 2>&1 ); then
    _fok=1
    grep -q 'Backlog backend' "$_fxd/CLAUDE.md" 2>/dev/null || { echo "FAIL: rider(c) — foreign CLAUDE.md's Backlog-backend declaration did NOT survive export"; _fok=0; }
    grep -qxE '/(src|test)/' "$_fxd/.gitignore" 2>/dev/null || { echo "FAIL: rider(c) — foreign .gitignore's /src//test/ lines did NOT survive export"; _fok=0; }
    grep -q 'my-own-rule' "$_fxd/.gitignore" 2>/dev/null || { echo "FAIL: rider(c) — foreign .gitignore's own rule did NOT survive export"; _fok=0; }
    head -1 "$_fxd/.gitattributes" 2>/dev/null | grep -q "excluded from THIS foreign tree" || { echo "FAIL: rider(c) — foreign .gitattributes was REPLACED by the A6 stub (over-carve of a foreign tree)"; _fok=0; }
    grep -q '^drift-watch' "$_fxd/conformance/claims.tsv" 2>/dev/null || { echo "FAIL: rider(c) — foreign claims.tsv's drift-watch row did NOT survive export"; _fok=0; }
    grep -q 'drift-watch' "$_fxd/conformance/claims-registry.sh" 2>/dev/null || { echo "FAIL: rider(c) — foreign claims-registry.sh's REQUIRED_IDS did NOT survive export"; _fok=0; }
    [ "$_fok" = 1 ] && echo "PASS: rider(c) — a foreign tree's CLAUDE.md / .gitignore / .gitattributes / claims declarations all SURVIVE export (no KIT_INTERNAL_MARKERS -> every kit-self carve skipped)" || fail=1
  else
    echo "FAIL: rider(c) — could not export the foreign-tree fixture at all"; fail=1
  fi
  # Soundness leg: a CLEAN kit export (the real tree, which DOES carry the markers) must still never
  # ship a KIT_INTERNAL_MARKERS file itself — export-ignore already guarantees this; this just proves
  # the rider's own gate is not vacuously "always skip".
  _cd="$_t/cleancheck"
  if do_export "$_cd" typescript-node >/dev/null 2>&1; then
    _leaked=""
    for _m in $(_ae_kit_tree_markers); do
      [ -e "$_cd/$_m" ] && _leaked="$_leaked $_m"
    done
    if [ -z "$_leaked" ]; then
      echo "PASS: rider(c) soundness — a clean kit export carries NO KIT_INTERNAL_MARKERS file (the carve-gate is not vacuously permissive)"
    else
      echo "FAIL: rider(c) soundness — a clean kit export leaked marker(s):$_leaked"; fail=1
    fi
  else
    echo "FAIL: rider(c) soundness — could not build the clean-export fixture"; fail=1
  fi
  # --- K2 — every `carve SKIPPED` notice the exporter actually PRINTS must say it is expected.
  # They are the loudest thing the quickstart prints from a public clone and they read like four
  # failures. ASSERTED ON CAPTURED STDOUT of a REAL export, re-using the marker-less foreign fixture
  # built above (no KIT_INTERNAL_MARKERS -> every carve skips -> every notice fires). An earlier
  # draft grepped this script's own SOURCE, which is not the same claim: source text proves the
  # string exists, not that the run emits it — and the naive source grep also counted its own two
  # patterns (measured 7 against 4 real notices).
  echo "--- K2: every carve-SKIPPED notice the exporter PRINTS tells the reader nothing is wrong ---"
  _k2d="$_t/k2-exp"
  _k2out=$( ( cd "$_fx" && sh scripts/adopter-export.sh "$_k2d" ) 2>&1 ) || true
  # `grep -c` exits 1 on zero matches, which under `set -e` would abort a PASSING selftest silently
  # instead of printing the named FAIL below — the count is the assertion, so never let rc escape.
  _k2_all=$(printf '%s\n' "$_k2out" | grep -c 'carve SKIPPED') || true
  _k2_ok=$(printf '%s\n' "$_k2out" | grep -c 'carve SKIPPED.*nothing is wrong') || true
  _k2_all=${_k2_all:-0}; _k2_ok=${_k2_ok:-0}
  if [ "$_k2_all" -ge 4 ] && [ "$_k2_all" -eq "$_k2_ok" ]; then
    echo "PASS: K2 — the exporter PRINTED $_k2_all carve-SKIPPED notice(s), every one carrying the 'nothing is wrong' tail"
  else
    echo "FAIL: K2 — the exporter printed $_k2_all carve-SKIPPED notice(s) and only $_k2_ok carried the reassurance tail"; fail=1
  fi
  rm -rf "$_k2d" 2>/dev/null || true

  rm -rf "$_fx" "$_fxd" "$_cd" 2>/dev/null || true

  # --- K1 — a `git init`'d destination is accepted; anything else in it is still refused.
  # The adopter's natural order is `mkdir proj && cd proj && git init` and THEN export; the
  # emptiness test refused exactly that (T1 cold trial). POSITIVE: `.git`-only -> export lands and
  # `.git` SURVIVES. NEGATIVES (load-bearing — without them the fix would be "accept any dest"):
  # `.git` + one file -> refused with the file untouched; a SYMLINKED `.git` -> refused.
  echo "--- K1: a .git-only destination is accepted, and only that ---"
  _gd="$_t/gitonly"; mkdir -p "$_gd" && ( cd "$_gd" && git init -q )
  if do_export "$_gd" typescript-node >/dev/null 2>&1; then
    if [ -d "$_gd/.git" ] && [ -f "$_gd/MAINTAINING.md" ]; then
      echo "PASS: K1 — .git-only dest -> OK with .git intact and the export landed"
    else
      echo "FAIL: K1 — .git-only dest exported but .git or the export content is missing"; fail=1
    fi
  else
    echo "FAIL: K1 — .git-only dest was refused (the defect this fixes)"; fail=1
  fi
  _gp="$_t/gitplus"; mkdir -p "$_gp" && ( cd "$_gp" && git init -q ) && echo hi > "$_gp/README.md"
  if do_export "$_gp" typescript-node >/dev/null 2>&1; then
    echo "FAIL: K1 — .git plus a file was ACCEPTED (a populated tree must still be refused)"; fail=1
  else
    [ "$(cat "$_gp/README.md" 2>/dev/null)" = hi ] \
      && echo "PASS: K1 — .git plus file -> refused, the adopter's file untouched" \
      || { echo "FAIL: K1 — refused but the adopter's file was disturbed"; fail=1; }
  fi
  _gl="$_t/gitlink"; _gr="$_t/gitreal"; mkdir -p "$_gl" "$_gr" && ln -s "$_gr" "$_gl/.git"
  if do_export "$_gl" typescript-node >/dev/null 2>&1; then
    echo "FAIL: K1 — a SYMLINKED .git was accepted (the staged tree could be written through a link)"; fail=1
  else
    echo "PASS: K1 — symlinked .git -> refused"
  fi
  rm -rf "$_gd" "$_gp" "$_gl" "$_gr" 2>/dev/null || true

  rm -rf "$_t" 2>/dev/null || true
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
