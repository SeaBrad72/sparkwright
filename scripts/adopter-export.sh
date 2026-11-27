#!/bin/sh
# adopter-export.sh — produce a clean adopter distribution of the kit via `git archive`
# (honors .gitattributes export-ignore; excludes gitignored scratch/node_modules automatically,
# since an archive contains only committed tracked files). Optionally prunes unused stack profiles.
#   sh scripts/adopter-export.sh <dest-dir> [--profile <stack>] [--brownfield <target-repo>] [--selftest]
#   (--brownfield needs --profile.)
# Operates on committed HEAD. NEVER writes inside the kit repo. Exit: 0 ok · 1 runtime · 2 usage.
# POSIX sh; dash-clean.
# What it changes: Writes the exported kit distribution into <dest-dir> (creates it), including the .kit-manifest and .kit-digests records of what and which bytes it shipped, the .kit-source record of which kit commit it archived, and conformance/kit-release.sha256, the digests of the shipped files that conformance/selftest-inputs.tsv names; never writes inside the kit repo; with --brownfield it leaves out the greenfield-only profiles/<stack>/scaffold* folders that incept copies into a new project, and where the target repository has its own front-page file (matched by the name before its first dot, in any letter case) it leaves out the kit's README.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md or SECURITY.md and moves the kit's LICENSE to LICENSE-SPARKWRIGHT.
# Guardrails: Operates on committed HEAD via `git archive`; refuses a non-empty <dest-dir> (no clobber); rejects an unknown --profile; never mutates the kit repo; the --brownfield target repository is only read (validated, never written; only its root file names are listed, and a name is printed only when it is plain text).
set -eu
_BF_LATE=

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

usage() { echo "usage: adopter-export.sh <dest-dir> [--profile <stack>] [--brownfield <target-repo>] [--selftest]  (--brownfield needs --profile)" >&2; exit 2; }

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
# The root test asks git (`--is-inside-work-tree` plus `--show-prefix`, see owns_itself); it does NOT
# compare path strings. A path compare drifts: `--show-toplevel` is symlink-resolved while `$PWD` is not
# (macOS /tmp -> /private/tmp), and on a case-insensitive filesystem a case-variant `cd` keeps its
# spelling in `pwd -P` while git reports the stored one (SWAS-463). The physical paths below only
# decide "in no repo at all" and name the owner in the refusal text.
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
  # Ask git whether <dir> is the root, never compare path strings: on a case-insensitive filesystem `cd` into a
  # case-variant spelling keeps that spelling in `pwd -P` while git reports the toplevel as stored, so a string
  # compare refused the repository's own root. `--show-prefix` prints an empty line exactly at the root.
  # git also prints an empty prefix when the cwd is OUTSIDE the work tree (a `core.worktree` pointing elsewhere), so the same subshell requires
  # `--is-inside-work-tree` to print exactly `true`; anything else refuses.
  _pfx=$( CDPATH='' cd "$1" 2>/dev/null && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && git rev-parse --show-prefix 2>/dev/null ) || return 1   # MUT-OWNSINSIDE
  [ -z "$_pfx" ]   # MUT-OWNSROOT
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
do_export() {  # <dest> <profile-or-empty> [<brownfield-target-or-empty>]  — atomic: stage -> verify -> rename
  _final=$1; _prof=${2:-}; _bft=${3:-}; _keep_git=0
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
  if _export_into "$_stage" "$_prof" "$_bft"; then
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

_bf_scaffold() {  # <staging-dir> <brownfield-target-or-empty> — leave out greenfield-only scaffold folders (flag alone; reads nothing from the target)
  _BF_N=0
  [ -n "${2:-}" ] || return 0   # MUT-CARVEALWAYS
  [ -n "$1" ] && [ -d "$1" ] || return 1
  [ -d "$1/profiles" ] && [ ! -L "$1/profiles" ] || return 0
  for _bfc_pd in "$1"/profiles/*/; do
    [ -d "$_bfc_pd" ] && [ ! -L "${_bfc_pd%/}" ] || continue
    for _bfc_s in "${_bfc_pd}scaffold" "${_bfc_pd}"scaffold-*; do   # MUT-CLIKEPT
      [ -d "$_bfc_s" ] && [ ! -L "$_bfc_s" ] || continue
      rm -rf "$_bfc_s"; _BF_N=$((_BF_N + 1))   # MUT-NOCARVE
    done
  done
}

# SWAS-1012: the front-page carve. It reads ONLY the target's root names (`ls -1A`, no content, nothing
# written there) and sets aside the kit's own front-page files where the target has its own.
_bf_fp_say() {  # <text> — one decision line, under the brownfield prefix
  _BF_FP="${_BF_FP:-}adopter-export: brownfield: $1${_BF_NL}"
}
_bf_fp_name() {  # <target name> -> stdout: the name when it is plain text (letters, digits, . _ - space; 1 to 64 long), else a fixed phrase
  if printf '%s' "$1" | LC_ALL=C grep -Eq '^[A-Za-z0-9._ -]{1,64}$'; then printf '%s' "$1"; else printf 'a file of yours'; fi   # MUT-FPNAME
}
_bf_fp_hit() {  # <root listing> <kit stem> -> stdout: the first listing name whose stem (before its first dot), case-folded under LC_ALL=C, equals the kit stem
  printf '%s\n' "$1" | LC_ALL=C awk -v want="$2" '
    { i = index($0, ".")
      s = (i > 0) ? substr($0, 1, i - 1) : $0     # MUT-FPSTEM
      if (tolower(s) == tolower(want)) { print $0; exit }   # MUT-FPCASE
    }'
}
_bf_fp_sec() {  # <staging-dir> <root listing> <target> — the kit's SECURITY.md: (a) an exact-name entry or (b) a case-folded one sets it aside; (c) any other stem keeps it
  [ -f "$1/SECURITY.md" ] || return 0
  if printf '%s\n' "$2" | grep -qxF -e SECURITY.md; then _bfs_x=1; else _bfs_x=0; fi   # MUT-FPSECPATH
  _bfs_f=$(printf '%s\n' "$2" | LC_ALL=C awk 'tolower($0) == "security.md" { print; exit }')   # MUT-FPSECFOLD MUT-FPSECSTEM
  if [ "$_bfs_x" = 1 ]; then
    rm -f "$1/SECURITY.md"
    if [ ! -e "$1/SECURITY.md" ]; then _bf_fp_say "SECURITY.md left out (your repository has SECURITY.md)"; fi
  elif [ -n "$_bfs_f" ]; then
    rm -f "$1/SECURITY.md"
    if [ ! -e "$1/SECURITY.md" ]; then _bf_fp_say "SECURITY.md left out (your repository has $(_bf_fp_name "$_bfs_f")); conformance/security-policy.sh needs a file named exactly SECURITY.md on a case-sensitive runner, so rename yours"; fi
  fi
}
_bf_frontpage() {  # <staging-dir> <brownfield-target> — README, CONTRIBUTING, CODE_OF_CONDUCT left out and LICENSE moved to LICENSE-SPARKWRIGHT where the target has a stem match
  [ -n "${2:-}" ] && [ -d "$2" ] || return 0
  _bff_ls=$(ls -1A -- "$2" 2>/dev/null) || {
    _bff_ls=''
    _bf_fp_say "your repository's root could not be listed, so no front-page file was left out"
  }
  for _bff_k in README CONTRIBUTING CODE_OF_CONDUCT; do
    [ -f "$1/$_bff_k.md" ] || continue
    _bff_h=$(_bf_fp_hit "$_bff_ls" "$_bff_k")
    [ -n "$_bff_h" ] || continue
    rm -f "$1/$_bff_k.md"
    if [ ! -e "$1/$_bff_k.md" ]; then _bf_fp_say "$_bff_k.md left out (your repository has $(_bf_fp_name "$_bff_h"))"; fi
  done
  _bff_h=$(_bf_fp_hit "$_bff_ls" LICENSE)
  if [ -f "$1/LICENSE" ] && [ -n "$_bff_h" ]; then
    mv "$1/LICENSE" "$1/LICENSE-SPARKWRIGHT"   # MUT-FPLICDROP
    if [ ! -e "$1/LICENSE" ]; then _bf_fp_say "LICENSE kept as LICENSE-SPARKWRIGHT (your repository has $(_bf_fp_name "$_bff_h"))"; fi
  fi
  _bf_fp_sec "$1" "$_bff_ls" "$2"
}
_bf_carve() {  # <staging-dir> <brownfield-target-or-empty> — the scaffold carve, then the front-page carve (the one brownfield block, before the records)
  _BF_NL=$(printf '\n_'); _BF_NL=${_BF_NL%_}; _BF_FP=''   # the front-page decision lines are recorded here and printed after the scaffold line
  _bf_scaffold "$1" "${2:-}" || return 1
  _bf_frontpage "$1" "${2:-}"
}

_export_into() {  # <staging-dir> <profile-or-empty> [<brownfield-target-or-empty>]  — all the real work; writes ONLY into staging
  _dest=$1; _prof=${2:-}; _bft=${3:-}; _BF_N=0
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
  # SWAS-607 (2b): conformance-ci-wired, doc-budget, conformance-mass-budget, incept-first-run-green, poster-parity and
  # dial-state are carved because their verifier scripts are export-ignored (only the kit's own rows and ci.yml ran them): a claim whose
  # verifier does not ship would FAIL in the adopter's claims-registry, so it is carved here, never dropped from the kit's own registry.
  # SWAS-608 (the owner's named yes, errata E4): governing-docs-current, mirror-current and badge-version, for the same reason. badge-version is
  # the FIRST id of REQUIRED_IDS (preceded by the opening quote, not a space), so the sed below has a second expression for that position.
  if _ae_is_kit_tree; then
    _ct="$_dest/conformance/claims.tsv"; _cr="$_dest/conformance/claims-registry.sh"
    if [ -f "$_ct" ] && [ -f "$_cr" ]; then
      _tab=$(printf '\t')
      for _c in drift-watch adopter-export repo-ownership orchestrator-loop escalation-seam conflict-safe-integration skill-spine ratification-parity adopter-gates-parity conformance-ci-wired doc-budget conformance-mass-budget incept-first-run-green poster-parity dial-state governing-docs-current mirror-current badge-version; do
        grep -v "^${_c}${_tab}" "$_ct" > "$_ct.$$.s3b" && mv "$_ct.$$.s3b" "$_ct"
        sed -e "s/ ${_c}\\([\"[:space:]]\\)/\\1/" -e "s/\"${_c} /\"/" "$_cr" > "$_cr.$$.s3b" && mv "$_cr.$$.s3b" "$_cr"
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
  # --- SWAS-1011: brownfield — leave out the greenfield-only scaffold folders, BEFORE the records below
  # are written so .kit-manifest and .kit-digests never name a removed path. On the flag alone (it is the
  # person's choice, like the profile prune), so it is not gated on _ae_is_kit_tree.
  _bf_carve "$_dest" "$_bft"   # MUT-BFLATE-AT
  # --- KIT-UPDATE-BASE-ADVANCES: the export STATES which vendor commit it archived (.kit-source) ------
  # Two lines: `commit <40-hex>` and `version <VERSION>`. VERSION alone cannot tell two pre-release
  # `main`s apart, so kit-update/incept key the kit-base chain on this sha. Written BEFORE the manifest
  # and digests below, so it is listed and digested like any shipped file. The ambient-GIT_DIR refusal
  # in do_export already guarantees `git rev-parse HEAD` here reads the KIT's repo. Unresolvable or
  # malformed -> refuse: a silent record-less export would re-create the stale-base defect.
  _ks_sha=$( cd "$ROOT" && git rev-parse --verify HEAD 2>/dev/null ) || _ks_sha=''
  case "$_ks_sha" in
    *[!0-9a-f]*|'') _ks_sha='' ;;
  esac
  if [ "${#_ks_sha}" -ne 40 ]; then
    echo "adopter-export: could not resolve a 40-hex HEAD sha in '$ROOT' for .kit-source — refusing" >&2; return 1
  fi
  _ks_ver=$(tr -d '[:space:]' < "$_dest/VERSION" 2>/dev/null || true)
  # A tree with no VERSION (a foreign/vendored derivative) still records its commit; the version reads `unknown`.
  [ -n "$_ks_ver" ] || _ks_ver=unknown
  printf 'commit %s\nversion %s\n' "$_ks_sha" "$_ks_ver" > "$_dest/.kit-source" && chmod 644 "$_dest/.kit-source"

  # --- SWAS-1008 slice 3: the release manifest, conformance/kit-release.sha256 -------------------------------
  # The sha256 of every shipped file that some line of conformance/selftest-inputs.tsv matches, under one header
  # line that repeats .kit-source's two facts. It is DERIVED HERE, from the bytes this export ships, never
  # hand-written, and the kit repo holds no copy. Order matters twice. After the profile prune and AFTER the
  # brownfield carve above (SWAS-1011 design 8 (a)), so it is taken from the FINAL staged tree and never names a
  # removed path; and BEFORE .kit-manifest and .kit-digests below, so the manifest lists it and the digests cover
  # it. The map names no profiles/ path (errata E8), so the same bytes hold for every export shape of a release.
  # Locked by conformance/kit-manifest.sh, which re-derives it independently. A re-export of an export carries the
  # old file, which is removed first and derived again, so its header always states THIS export's .kit-source.
  # NO HASHER, or no map, MEANS NO FILE, said out loud: an adopter tree with no manifest runs the full aggregate.
  rm -f "$_dest/conformance/kit-release.sha256"
  _rm_map="$_dest/conformance/selftest-inputs.tsv"
  _rm_hasher=''
  if command -v shasum >/dev/null 2>&1; then _rm_hasher='shasum -a 256'
  elif command -v sha256sum >/dev/null 2>&1; then _rm_hasher='sha256sum'
  fi
  if [ ! -s "$_rm_map" ]; then
    echo "adopter-export: no conformance/selftest-inputs.tsv in this tree, so NO conformance/kit-release.sha256 was written (an adopter tree with no manifest runs the full aggregate)." >&2
  elif [ -z "$_rm_hasher" ]; then
    echo "adopter-export: WARNING — no shasum/sha256sum on this machine, so NO conformance/kit-release.sha256 was written." >&2
    echo "  This export is still usable; an adopter tree with no manifest runs the full aggregate." >&2
  else
    _rm_all=$(mktemp) || { echo "adopter-export: mktemp failed (release manifest)" >&2; return 1; }
    _rm_scope=$(mktemp) || { rm -f "$_rm_all"; echo "adopter-export: mktemp failed (release manifest)" >&2; return 1; }
    ( cd "$_dest" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) > "$_rm_all"
    # a path with a newline in it is two lines to everything below: the count of NUL-terminated entries must equal the lines
    _rm_nul=$( ( cd "$_dest" && find . -type f -print0 ) | tr -cd '\0' | wc -c | tr -d ' ' )
    _rm_lines=$(wc -l < "$_rm_all" | tr -d ' ')
    if [ "$_rm_nul" != "$_rm_lines" ]; then
      _rm_nlp=$( ( cd "$_dest" && find . -type f -print0 ) | tr '\0\n' '\n~' | grep -n '~' | head -1 || true )
      rm -f "$_rm_all" "$_rm_scope"; echo "adopter-export: refusing to write conformance/kit-release.sha256 — a shipped path contains a newline (shown here with ~ for the newline): $_rm_nlp" >&2; return 1
    fi
    # the map's grammar is read in conformance/kit-manifest.sh: `<row>TAB<glob>`, `@all TAB<path>`, `<row>TAB!<path>`; a glob's
    # `*` is any run of characters, `/` included
    awk '
      function rx(g,  i, c, o) {
        o = "^"
        for (i = 1; i <= length(g); i++) {
          c = substr(g, i, 1)
          if (c == "*") o = o ".*"
          else if (c == ".") o = o "\\."
          else if (c == "+") o = o "\\+"
          else o = o c
        }
        return o "$"
      }
      BEGIN { FS = "\t" }
      FNR == NR {
        if ($0 ~ /^#/ || NF < 2) next
        if (substr($2, 1, 1) == "!") { ex[$1 SUBSEP substr($2, 2)] = 1; next }
        n++; r[n] = $1; re[n] = rx($2); next
      }
      {
        if ($0 == "conformance/kit-release.sha256") next
        for (i = 1; i <= n; i++) if ($0 ~ re[i] && !((r[i] SUBSEP $0) in ex)) { print; next }
      }' "$_rm_map" "$_rm_all" > "$_rm_scope" || { rm -f "$_rm_all" "$_rm_scope"; echo "adopter-export: release manifest scope failed" >&2; return 1; }
    rm -f "$_rm_all"
    if [ ! -s "$_rm_scope" ]; then
      rm -f "$_rm_scope"; echo "adopter-export: refusing to write an EMPTY conformance/kit-release.sha256 (the map matches no file)" >&2; return 1
    fi
    # an in-scope path outside the census's character class (letters, digits, . _ / * + -) is refused by name: the
    # manifest and the glob-to-regex conversion are exact only inside it
    _rm_odd=$(LC_ALL=C grep -n '[^A-Za-z0-9._/*+-]' "$_rm_scope" | head -3 | tr '\n' ' ' || true)
    if [ -n "$_rm_odd" ]; then
      rm -f "$_rm_scope"; echo "adopter-export: refusing to write conformance/kit-release.sha256 — an in-scope path is outside the allowed characters (letters, digits, . _ / * + -): $_rm_odd" >&2; return 1
    fi
    _rm_raw=$(mktemp) || { rm -f "$_rm_scope"; echo "adopter-export: mktemp failed (release manifest)" >&2; return 1; }
    # TWO STEPS, as for .kit-digests: the hasher's rc must reach this test, not sort's
    if ! ( cd "$_dest" && tr '\n' '\0' < "$_rm_scope" | xargs -0 $_rm_hasher -- ) > "$_rm_raw"; then
      rm -f "$_rm_scope" "$_rm_raw"; echo "adopter-export: release manifest digest build failed (hasher returned non-zero)" >&2; return 1
    fi
    rm -f "$_rm_scope"
    { printf '# kit-release v%s %s\n' "$_ks_ver" "$_ks_sha"; LC_ALL=C sort -k2 "$_rm_raw"; } > "$_rm_raw.out" || { rm -f "$_rm_raw" "$_rm_raw.out"; echo "adopter-export: release manifest sort failed" >&2; return 1; }
    rm -f "$_rm_raw"
    mv "$_rm_raw.out" "$_dest/conformance/kit-release.sha256" && chmod 644 "$_dest/conformance/kit-release.sha256"
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
  { ( cd "$_dest" && find . -type f | sed 's|^\./||' ); echo '.kit-manifest'; echo '.kit-digests'; } \
    | LC_ALL=C sort -u > "$_mf" || { rm -f "$_mf"; echo "adopter-export: manifest build failed" >&2; return 1; }
  if [ ! -s "$_mf" ]; then
    rm -f "$_mf"; echo "adopter-export: refusing to write an EMPTY .kit-manifest" >&2; return 1
  fi
  mv "$_mf" "$_dest/.kit-manifest" && chmod 644 "$_dest/.kit-manifest"

  # --- ADOPTER-TREE-IDENTITY: the export states WHICH BYTES it shipped (.kit-digests) ----------------
  # The manifest says what shipped; it cannot say whether the SECURITY.md now sitting in an adopter's
  # tree is the one this export put there or one the adopter wrote. incept must know, because it
  # replaces the kit's own SECURITY.md/README.md (which cannot be export-ignored — the public mirror IS
  # an export and security-channel-live.sh probes its policy) and must never touch the adopter's.
  #
  # THE EXPORTER IS THE ONLY ACTOR THAT CAN RECORD THIS, for the same reason it is the only one that can
  # write the manifest: it is holding the kit's own tree, before an adopter's tree exists. The obvious
  # alternative — incept comparing against the `kit-base` it vendors — was REFUTED by measurement:
  # capture_kit_base stages kit-base FROM THE TREE BEING INCEPTED, so a brownfield adopter's own file
  # becomes its own "pristine twin" and would be clobbered.
  #
  # SELF-EXCLUSION: no line for `.kit-digests` itself — a file cannot contain its own digest. Written
  # AFTER .kit-manifest so the manifest's own digest is recorded. Locked by conformance/kit-manifest.sh.
  # NO HASHER = NO FILE, said out loud: incept's fallback on a digest-less export is to leave both files
  # alone, which is the safe direction. A silent empty/partial record would be the unsafe one.
  _hasher=''
  if command -v shasum >/dev/null 2>&1; then _hasher='shasum -a 256'
  elif command -v sha256sum >/dev/null 2>&1; then _hasher='sha256sum'
  fi
  if [ -z "$_hasher" ]; then
    echo "adopter-export: WARNING — no shasum/sha256sum on this machine, so NO .kit-digests was written." >&2
    echo "  This export is still usable; incept will leave SECURITY.md and README.md as the kit's and say so." >&2
  else
    _df=$(mktemp) || { echo "adopter-export: mktemp failed (digests)" >&2; return 1; }
    # Batch through xargs — one hasher process per few hundred paths, not per file. `grep -v` drops the
    # self-entry. Paths come from `find -type f` (the kit ships none with spaces or newlines), and the
    # NUL delimiter keeps that true even if one ever appeared with a space.
    # TWO STEPS, on purpose: piping the hasher straight into `sort` would test SORT's rc and discard the
    # hasher's, so an unreadable file would land as a short-but-sorted record and the manifest-coverage
    # leg would be the only thing left standing between that and a silent wrong replacement.
    if ! ( cd "$_dest" && grep -v '^\.kit-digests$' .kit-manifest | tr '\n' '\0' | xargs -0 $_hasher ) > "$_df.raw"; then
      rm -f "$_df" "$_df.raw"; echo "adopter-export: digest build failed (hasher returned non-zero)" >&2; return 1
    fi
    if ! LC_ALL=C sort -k2 "$_df.raw" > "$_df"; then
      rm -f "$_df" "$_df.raw"; echo "adopter-export: digest sort failed" >&2; return 1
    fi
    rm -f "$_df.raw"
    if [ ! -s "$_df" ]; then
      rm -f "$_df"; echo "adopter-export: refusing to write an EMPTY .kit-digests" >&2; return 1
    fi
    mv "$_df" "$_dest/.kit-digests" && chmod 644 "$_dest/.kit-digests"
  fi
  [ "${_BF_LATE:-}" = 1 ] && _bf_carve "$_dest" "$_bft"  # MUT-BFLATE-LATE

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
  if [ -n "$_bft" ]; then
    echo "adopter-export: brownfield: left out $_BF_N greenfield-only scaffold folder(s); incept copies them into a new project, and an existing project does not need them"
    [ -z "${_BF_FP:-}" ] || printf '%s' "$_BF_FP"
  fi
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
  for p in docs/ROADMAP-KIT.md .github/workflows/golden-path.yml .github/workflows/drift-watch.yml CHANGELOG.md changelog.d scripts/changelog-assemble.sh docs/governance/DECISIONS.md ARCHIVE-SAFE-SET.txt conformance/mass-acks.txt conformance/mass-release-baseline.txt WALKTHROUGH.md .publish-identifiers conformance/aggregate-coverage.sh conformance/kit-base.sh scripts/ci-time-report.sh conformance/incept-manifests conformance/repo-ownership.sh .github/golden-path/.trivyignore; do
    [ -e "$_d/$p" ] && { echo "FAIL: export-ignored path present: $p"; fail=1; } || echo "PASS: absent $p"
  done
  # SWAS-608: one sample per area of the kit-only files hidden by name in .gitattributes (a conformance script, the
  # kit-update family, a scripts/ file, a data directory) joined the absence list above: that is the proof the
  # attribute took. conformance/kit-current.sh and scripts/publish-public.sh join the kept list below, because
  # doctor.sh / kit-current.sh reach them behind a [ -f ] guard and a hidden file would read as a quiet N/A.
  # conformance/shim-coverage.sh and conformance/boundary-redteam.sh join the kept list too (the security seat kept them
  # shipped), so a later change cannot hide either with every gate green.
  # kept → PRESENT (scripts/fixtures now SHIPS — otlp-export.sh --selftest on an adopter tree reads
  # scripts/fixtures/otel-trace-sample.ndjson)
  for p in MAINTAINING.md conformance templates profiles/_TEMPLATE.md profiles/typescript-node scripts/fixtures/otel-trace-sample.ndjson conformance/kit-current.sh scripts/publish-public.sh conformance/shim-coverage.sh conformance/boundary-redteam.sh; do
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
  for p in drift-watch adopter-export orchestrator-loop escalation-seam conflict-safe-integration skill-spine conformance-ci-wired doc-budget conformance-mass-budget incept-first-run-green poster-parity dial-state governing-docs-current mirror-current badge-version; do
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

  # --- KIT-UPDATE-BASE-ADVANCES: the export carries a well-formed .kit-source == the kit's HEAD, and it is
  # listed in .kit-manifest and digested in .kit-digests like any shipped file.
  _ks_head=$( cd "$ROOT" && git rev-parse HEAD 2>/dev/null )
  if [ "$(cat "$_d/.kit-source" 2>/dev/null)" = "$(printf 'commit %s\nversion %s' "$_ks_head" "$(git -C "$ROOT" show HEAD:VERSION | tr -d '[:space:]')")" ] \
     && grep -qx '\.kit-source' "$_d/.kit-manifest" && grep -q ' \.kit-source$' "$_d/.kit-digests"; then
    echo "PASS: .kit-source records the kit HEAD + VERSION and is in the manifest and digests"
  else
    echo "FAIL: .kit-source missing, malformed, not equal to HEAD/VERSION, or not in manifest/digests"; fail=1
  fi

  # --- SWAS-1008 slice 3: the export carries conformance/kit-release.sha256 — a header that repeats .kit-source, a line
  # for each file the map matches and none for itself — and it is listed in .kit-manifest and digested in .kit-digests.
  # (conformance/kit-manifest.sh re-derives it independently, byte for byte.)
  _rm_f="$_d/conformance/kit-release.sha256"
  if [ -s "$_rm_f" ] && [ "$(sed -n 1p "$_rm_f")" = "# kit-release v$(git -C "$ROOT" show HEAD:VERSION | tr -d '[:space:]') $_ks_head" ] \
     && [ "$(wc -l < "$_rm_f" | tr -d ' ')" -ge 2 ] \
     && ! grep -q ' conformance/kit-release\.sha256$' "$_rm_f" \
     && grep -qx 'conformance/kit-release\.sha256' "$_d/.kit-manifest" && grep -q ' conformance/kit-release\.sha256$' "$_d/.kit-digests"; then
    echo "PASS: SWAS-1008 — the export carries kit-release.sha256 (header equals .kit-source, no self-line, in the manifest and the digests)"
  else
    echo "FAIL: SWAS-1008 — kit-release.sha256 missing, empty, headed wrongly, holding a line for itself, or not in manifest/digests"; fail=1
  fi
  # No hasher means no file, said on stderr. PATH is a scratch directory of symlinks to every tool on the real PATH
  # except the hashers, so the exporter finds git, tar, awk and the rest and finds no shasum or sha256sum.
  _nh="$_t/nohash-bin"; mkdir -p "$_nh"
  printf '%s\n' "$PATH" | tr ':' '\n' | while read -r _nhd; do
      [ -d "$_nhd" ] || continue
      for _nhf in "$_nhd"/*; do
        _nhb=${_nhf##*/}
        case "$_nhb" in
          shasum|sha*sum) continue ;;
        esac
        [ -e "$_nh/$_nhb" ] || ln -s "$_nhf" "$_nh/$_nhb" 2>/dev/null || :
      done
    done
  _nhsh=$(command -v sh)
  _nhout=$( cd "$ROOT" && PATH="$_nh" "$_nhsh" scripts/adopter-export.sh "$_t/nohash-exp" 2>&1 ) || _nhout="$_nhout [export rc nonzero]"
  if printf '%s\n' "$_nhout" | grep -q 'no shasum/sha256sum on this machine, so NO conformance/kit-release.sha256 was written' \
     && [ -f "$_t/nohash-exp/.kit-manifest" ] && [ ! -e "$_t/nohash-exp/conformance/kit-release.sha256" ] && ! printf '%s\n' "$_nhout" | grep -q 'rc nonzero'; then
    echo "PASS: SWAS-1008 — with no hasher on the PATH the export writes no kit-release.sha256 and says so on stderr"
  else
    echo "FAIL: SWAS-1008 — with no hasher on the PATH the export wrote a kit-release.sha256, failed, or did not say so: $(printf '%s' "$_nhout" | tail -2 | tr '\n' ' ')"; fail=1
  fi

  # --- SWAS-1008 slice 3 (security B2): an in-scope path outside the allowed characters is refused by name. A control
  # fixture with only clean names exports and writes the manifest; the same tree plus `conformance/a b.sh` does not.
  _b2="$_t/b2fix"; mkdir -p "$_b2/scripts" "$_b2/conformance"
  cp "$_self" "$_b2/scripts/adopter-export.sh"
  printf 'row\tconformance/*\n' > "$_b2/conformance/selftest-inputs.tsv"
  printf 'x\n' > "$_b2/conformance/a.sh"
  ( cd "$_b2" && git init -q && git add -A && git -c user.email=b@kit -c user.name=b commit -qm b2 >/dev/null 2>&1 )
  _b2ok=0; ( cd "$_b2" && sh scripts/adopter-export.sh "$_t/b2-exp-ok" >/dev/null 2>&1 ) && [ -s "$_t/b2-exp-ok/conformance/kit-release.sha256" ] && _b2ok=1
  printf 'x\n' > "$_b2/conformance/a b.sh"
  ( cd "$_b2" && git add -A && git -c user.email=b@kit -c user.name=b commit -qm b2odd >/dev/null 2>&1 )
  _b2rc=0; _b2err=$( cd "$_b2" && sh scripts/adopter-export.sh "$_t/b2-exp-bad" 2>&1 >/dev/null ) || _b2rc=$?
  if [ "$_b2ok" = 1 ] && [ "$_b2rc" != 0 ] && [ ! -e "$_t/b2-exp-bad" ] && printf '%s\n' "$_b2err" | grep -q 'outside the allowed characters.*a b.sh'; then
    echo "PASS: SWAS-1008 — an in-scope path with a space is refused by name, and a clean tree exports its manifest"
  else
    echo "FAIL: SWAS-1008 — the odd-path refusal did not hold (clean ok=$_b2ok, odd rc=$_b2rc, stderr: $(printf '%s' "$_b2err" | tail -1))"; fail=1
  fi
  # a path with a NEWLINE in it is refused too (it would read as two clean lines); remove the space file so only the newline one is odd
  ( cd "$_b2" && git rm -q -f "conformance/a b.sh" && printf 'x\n' > "$(printf 'conformance/n\nm.sh')" && git add -A \
      && git -c user.email=b@kit -c user.name=b commit -qm b2nl >/dev/null 2>&1 )
  _b2rc=0; _b2err=$( cd "$_b2" && sh scripts/adopter-export.sh "$_t/b2-exp-nl" 2>&1 >/dev/null ) || _b2rc=$?
  if [ "$_b2rc" != 0 ] && [ ! -e "$_t/b2-exp-nl" ] && printf '%s\n' "$_b2err" | grep -q 'contains a newline'; then
    echo "PASS: SWAS-1008 — a shipped path with a newline is refused by name"
  else
    echo "FAIL: SWAS-1008 — the newline-path refusal did not hold (rc=$_b2rc, stderr: $(printf '%s' "$_b2err" | tail -1))"; fail=1
  fi

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
  # SWAS-1008 slice 3 — a tree with no conformance/selftest-inputs.tsv (this foreign fixture) gets NO release manifest, said out loud
  if printf '%s\n' "$_k2out" | grep -q 'NO conformance/kit-release.sha256 was written' && [ ! -e "$_k2d/conformance/kit-release.sha256" ] && [ -f "$_k2d/.kit-manifest" ]; then
    echo "PASS: SWAS-1008 — a tree with no selftest-inputs.tsv exports with no kit-release.sha256, and the export says so"
  else
    echo "FAIL: SWAS-1008 — a tree with no selftest-inputs.tsv wrote a kit-release.sha256, or the export did not say it wrote none"; fail=1
  fi
  rm -rf "$_k2d" 2>/dev/null || true

  # --- SWAS-1011 E1-E8: --brownfield leaves out the greenfield-only scaffold folders. The form is
  # `<dest> --profile <stack> --brownfield <target-repo>` (the errata: --profile is required). Every
  # brownfield cell passes a target: an empty directory outside the kit and outside <dest>.
  echo "--- SWAS-1011: --brownfield leaves out greenfield-only scaffold (E1-E8) ---"
  _bf_tgt="$_t/bf-target"; mkdir -p "$_bf_tgt"
  _bfd="$_t/bf-exp"; _bfp="$_t/bf-plain"
  _bfre='profiles/[^/]+/scaffold(-[^/]*)?/'
  _bfout=$(do_export "$_bfd" typescript-node "$_bf_tgt" 2>/dev/null) || _bfout=""
  _bfpout=$(do_export "$_bfp" typescript-node 2>/dev/null) || _bfpout=""

  # E1 — no scaffold folder; the kept profile files stay.
  _e1_bad=$(find "$_bfd/profiles" -mindepth 2 -maxdepth 2 -type d \( -name scaffold -o -name 'scaffold-*' \) 2>/dev/null || true)
  _e1_keep=1
  for _e1p in profiles/typescript-node/ci.yml profiles/typescript-node.md profiles/ratification.yml profiles/_TEMPLATE.md; do
    [ -f "$_bfd/$_e1p" ] || _e1_keep=0
  done
  if [ -z "$_e1_bad" ] && [ "$_e1_keep" = 1 ]; then
    echo "PASS: E1 — a --brownfield export has no profiles/*/scaffold* folder and keeps ci.yml, the profile doc, ratification.yml and _TEMPLATE.md"
  else
    echo "FAIL: E1 — scaffold folder(s) present [$(printf '%s' "$_e1_bad" | tr '\n' ' ')] or a kept profile file is missing (keep=$_e1_keep)"; fail=1
  fi

  # E2 — greenfield unchanged: a plain export (no flag) still carries both scaffolds.
  if [ -f "$_bfp/profiles/typescript-node/scaffold/package.json" ] && [ -f "$_bfp/profiles/typescript-node/scaffold-cli/package.json" ]; then
    echo "PASS: E2 — a plain export still carries scaffold/ and scaffold-cli/ (greenfield unchanged)"
  else
    echo "FAIL: E2 — a plain export lost a scaffold folder (greenfield changed)"; fail=1
  fi

  # E3 — the records agree with the tree (manifest == files on disk, no scaffold path in either record).
  _e3m="$_bfd/.kit-manifest"
  _e3_disk=$(cd "$_bfd" 2>/dev/null && find . -type f | sed 's|^\./||' | LC_ALL=C sort) || _e3_disk=""
  _e3_rec=""; [ -f "$_e3m" ] && _e3_rec=$(LC_ALL=C sort "$_e3m")
  _e3_scaf=0
  grep -Eq "$_bfre" "$_e3m" 2>/dev/null && _e3_scaf=1
  grep -Eq "$_bfre" "$_bfd/.kit-digests" 2>/dev/null && _e3_scaf=1
  if [ -n "$_e3_rec" ] && [ "$_e3_disk" = "$_e3_rec" ] && [ "$_e3_scaf" = 0 ]; then
    echo "PASS: E3 — .kit-manifest equals the files on disk, and neither it nor .kit-digests names a profiles/*/scaffold* path"
  else
    echo "FAIL: E3 — the records disagree with the tree (scaffold named: $_e3_scaf, manifest empty: $([ -n "$_e3_rec" ] && echo no || echo yes), disk==manifest: $([ "$_e3_disk" = "$_e3_rec" ] && echo yes || echo no))"; fail=1
  fi
  # E3 forward leg (design §8): N-A while the exporter writes no conformance/kit-release.sha256.
  if [ -f "$_bfd/conformance/kit-release.sha256" ]; then
    if grep -Eq "$_bfre" "$_bfd/conformance/kit-release.sha256"; then
      echo "FAIL: E3 forward — kit-release.sha256 names a carved scaffold path"; fail=1
    else
      echo "PASS: E3 forward — kit-release.sha256 names no carved scaffold path"
    fi
  else
    echo "N-A: E3 forward — the exporter writes no conformance/kit-release.sha256 yet (design §8)"
  fi

  # E4 — no default test discovery, per stack. Matchers read relative paths on stdin; each has a
  # positive control on sample paths, so a regex that matches nothing cannot pass vacuously.
  _e4_node='(^|/)(test|test-[^/]*|[^/]*[._-]test)[.](js|mjs|cjs|ts|mts|cts)$|(^|/)test/.*[.](js|mjs|cjs|ts|mts|cts)$'
  _e4_py='(^|/)(test_[^/]*|[^/]*_test)[.]py$'
  _e4_go='_test[.]go$'
  _e4_ctl=$(printf '%s\n' a/x.test.ts b/y-test.js c/z_test.mjs test-q.cjs test.js t/test/any.mts | grep -Ec "$_e4_node" || true)
  [ "$_e4_ctl" = 6 ] || { echo "FAIL: E4 control — the Node matcher found $_e4_ctl of 6 sample test paths"; fail=1; }
  [ "$(printf '%s\n' a/test_x.py b/y_test.py | grep -Ec "$_e4_py" || true)" = 2 ] || { echo "FAIL: E4 control — the pytest matcher missed a sample"; fail=1; }
  [ "$(printf '%s\n' a/x_test.go | grep -Ec "$_e4_go" || true)" = 1 ] || { echo "FAIL: E4 control — the Go matcher missed a sample"; fail=1; }
  _e4_scan() {  # <stack> <regex> : export --brownfield, fail if any file matches the stack's default test patterns
    _e4s=$1; _e4x="$_t/e4-$1"
    if ! do_export "$_e4x" "$_e4s" "$_bf_tgt" >/dev/null 2>&1 || [ ! -f "$_e4x/.kit-manifest" ]; then
      echo "FAIL: E4 — the $_e4s --brownfield export did not build"; fail=1; return 0
    fi
    _e4hit=$(cd "$_e4x" && find . -type f | sed 's|^\./||' | grep -E "$2" || true)
    if [ -z "$_e4hit" ]; then
      echo "PASS: E4 — a $_e4s --brownfield export holds no file matching its default test patterns"
    else
      echo "FAIL: E4 — a $_e4s --brownfield export holds default-discoverable test file(s): $(printf '%s' "$_e4hit" | head -3 | tr '\n' ' ')"; fail=1
    fi
  }
  _e4_scan typescript-node "$_e4_node"
  _e4_scan python "$_e4_py"
  _e4_scan go "$_e4_go"

  # E5 — stdout: the existing `exported …` line, then the brownfield line (N >= 1); none without the flag.
  _e5_n=$(printf '%s\n' "$_bfout" | sed -n 's/^adopter-export: brownfield: left out \([0-9][0-9]*\) greenfield-only scaffold folder(s); incept copies them into a new project, and an existing project does not need them$/\1/p')
  if printf '%s\n' "$_bfout" | head -1 | grep -Eq '^adopter-export: exported [0-9]+ files to .* \(kit HEAD tracked [0-9]+; pruned [0-9]+ unused profile\(s\)\)$' \
     && [ -n "$_e5_n" ] && [ "$_e5_n" -ge 1 ] && ! printf '%s\n' "$_bfpout" | grep -q 'brownfield:'; then
    echo "PASS: E5 — --brownfield prints the unchanged exported line, then 'brownfield: left out $_e5_n …'; a plain run prints no brownfield line"
  else
    echo "FAIL: E5 — stdout shape wrong (N='$_e5_n'; plain run printed a brownfield line: $(printf '%s\n' "$_bfpout" | grep -c 'brownfield:' || true))"; fail=1
  fi

  # E6 — not gated on the kit tree: the byte copy in the marker-less foreign fixture still carves.
  mkdir -p "$_fx/profiles/x/scaffold/test"
  printf 'test\n' > "$_fx/profiles/x/scaffold/test/a.test.js"
  printf 'name: x\n' > "$_fx/profiles/x/ci.yml"
  ( cd "$_fx" && git add -A && git -c user.email=f@foreign -c user.name=foreign commit -qm plant >/dev/null 2>&1 )
  _e6d="$_t/e6-exp"
  if ( cd "$_fx" && sh scripts/adopter-export.sh "$_e6d" --profile x --brownfield "$_bf_tgt" >/dev/null 2>&1 ) \
     && [ ! -e "$_e6d/profiles/x/scaffold" ] && [ -f "$_e6d/profiles/x/ci.yml" ]; then
    echo "PASS: E6 — in a marker-less foreign tree the scaffold is carved and profiles/x/ci.yml stays"
  else
    echo "FAIL: E6 — the foreign-tree --brownfield export kept the scaffold, dropped ci.yml, or did not run"; fail=1
  fi

  # E7 — no dangling link: check-links runs inside a git index (errata E2) in each export; the
  # brownfield run has no failing line the plain run lacks and none naming a scaffold path; a planted
  # broken link must fail the script (non-vacuity). Precondition: the brownfield export is carved.
  _e7_run() {  # <export dir> -> stdout: check-links output; return: its rc
    ( cd "$1" && git init -q && git add -A && sh conformance/check-links.sh ) 2>&1
  }
  _e7bf=$(_e7_run "$_bfd") || true
  _e7pl=$(_e7_run "$_bfp") || true
  _e7_bfb=$(printf '%s\n' "$_e7bf" | grep '^BROKEN:' || true)
  _e7_plb=$(printf '%s\n' "$_e7pl" | grep '^BROKEN:' || true)
  _e7_extra=$(printf '%s\n' "$_e7_bfb" | grep -v '^$' | grep -vxF -e "$_e7_plb" || true)
  _e7_ran=0
  printf '%s\n' "$_e7bf" | grep -Eq '^(OK|FAIL):' && printf '%s\n' "$_e7pl" | grep -Eq '^(OK|FAIL):' && _e7_ran=1
  if [ -z "$_e1_bad" ] && [ -f "$_bfd/.kit-manifest" ] && [ "$_e7_ran" = 1 ] && [ -z "$_e7_extra" ] \
     && ! printf '%s\n' "$_e7_bfb" | grep -Eq 'scaffold'; then
    echo "PASS: E7 — check-links on the --brownfield export shows no failing link the plain export lacks, none naming a scaffold path"
  else
    echo "FAIL: E7 — carved=$([ -z "$_e1_bad" ] && echo yes || echo no) ran=$_e7_ran extra-broken=[$(printf '%s' "$_e7_extra" | head -3 | tr '\n' ' ')]"; fail=1
  fi
  _e7c="$_t/e7-planted"; mkdir -p "$_e7c"
  if [ -f "$_bfd/.kit-manifest" ] && cp -R "$_bfd/." "$_e7c/" 2>/dev/null; then
    printf 'see [gone](planted-missing-target-1011.md)\n' >> "$_e7c/README.md"
    _e7pn=$(_e7_run "$_e7c") && _e7prc=0 || _e7prc=1
    if [ "$_e7prc" = 1 ] && printf '%s\n' "$_e7pn" | grep -q 'planted-missing-target-1011.md'; then
      echo "PASS: E7 non-vacuity — a planted broken link in a kept document fails check-links and is named"
    else
      echo "FAIL: E7 non-vacuity — a planted broken link did not fail check-links (the leg is vacuous)"; fail=1
    fi
  else
    echo "FAIL: E7 non-vacuity — no brownfield export to plant into"; fail=1
  fi

  # E8 — the refusals: each exits 2 with its own message. A leg with dest-state `absent` also asserts
  # <dest> was not created. The messages are the contract the flag build must print.
  _e8() {  # <label> <message-regex> <dest> <absent|keep> <args...>
    _e8l=$1; _e8m=$2; _e8dest=$3; _e8st=$4; shift 4
    _e8rc=0
    _e8err=$(sh "$_self" "$_e8dest" "$@" 2>&1 >/dev/null) || _e8rc=$?
    _e8gone=1
    [ "$_e8st" = absent ] && [ -e "$_e8dest" ] && _e8gone=0
    if [ "$_e8rc" = 2 ] && printf '%s\n' "$_e8err" | grep -Eq -e "$_e8m" && [ "$_e8gone" = 1 ]; then
      echo "PASS: E8 — $_e8l refused (exit 2, own message)"
    else
      echo "FAIL: E8 — $_e8l (rc=$_e8rc, dest-clean=$_e8gone, stderr: $(printf '%s' "$_e8err" | head -1))"; fail=1
    fi
  }
  _e8_tsn="--profile typescript-node"
  _e8_nov='adopter-export: --brownfield needs a target repository'
  # shellcheck disable=SC2086 # _e8_tsn is a fixed two-word flag pair
  _e8 "no value" "$_e8_nov" "$_t/e8-a" absent $_e8_tsn --brownfield
  _e8 "a value starting with a dash" "$_e8_nov" "$_t/e8-b" absent --brownfield --profile x
  # shellcheck disable=SC2086
  _e8 "--brownfield twice" 'adopter-export: --brownfield given twice' "$_t/e8-c" absent $_e8_tsn --brownfield "$_bf_tgt" --brownfield "$_bf_tgt"
  # shellcheck disable=SC2086
  _e8 "a missing target" 'target is not an existing directory' "$_t/e8-d" absent $_e8_tsn --brownfield "$_t/e8-nonesuch"
  : > "$_t/e8-file"
  # shellcheck disable=SC2086
  _e8 "a file as target" 'target is not an existing directory' "$_t/e8-e" absent $_e8_tsn --brownfield "$_t/e8-file"
  ln -s "$_bf_tgt" "$_t/e8-link"
  # shellcheck disable=SC2086
  _e8 "a symlink target" 'target is a symlink' "$_t/e8-f" absent $_e8_tsn --brownfield "$_t/e8-link"
  # shellcheck disable=SC2086
  _e8 "the kit root as target" 'target is the kit or inside it' "$_t/e8-g" absent $_e8_tsn --brownfield "$ROOT"
  # shellcheck disable=SC2086
  _e8 "a target inside the kit" 'target is the kit or inside it' "$_t/e8-h" absent $_e8_tsn --brownfield "$ROOT/scripts"
  # shellcheck disable=SC2086
  _e8 "a dot-dot target back into the kit" 'target is the kit or inside it' "$_t/e8-j" absent $_e8_tsn --brownfield "$ROOT/scripts/.."
  ln -s "$ROOT" "$_t/kitlink"
  # shellcheck disable=SC2086
  _e8 "a target reached through a symlinked parent into the kit" 'target is the kit or inside it' "$_t/e8-k" absent $_e8_tsn --brownfield "$_t/kitlink/scripts"
  # shellcheck disable=SC2086
  _e8 "a dest inside the target" 'dest is inside the --brownfield target' "$_bf_tgt/inner-dest" absent $_e8_tsn --brownfield "$_bf_tgt"
  # shellcheck disable=SC2086
  _e8 "no --profile" 'needs --profile' "$_t/e8-i" absent --brownfield "$_bf_tgt"
  _e8g="$_t/e8-gitonly"; mkdir -p "$_e8g" && ( cd "$_e8g" && git init -q )
  _e8g_before=$(cksum "$_e8g/.git/HEAD" "$_e8g/.git/config")
  # shellcheck disable=SC2086
  _e8 "a target equal to a .git-only dest" 'target is the destination or inside it' "$_e8g" keep $_e8_tsn --brownfield "$_e8g"
  if [ "$(ls -A "$_e8g")" = ".git" ] && [ "$(cksum "$_e8g/.git/HEAD" "$_e8g/.git/config")" = "$_e8g_before" ]; then
    echo "PASS: E8 — the .git-only dest was left untouched"
  else
    echo "FAIL: E8 — the .git-only dest was changed by the refused run"; fail=1
  fi
  mkdir -p "$_t/e8-outer/sub"
  # shellcheck disable=SC2086
  _e8 "a target inside the dest" 'target is the destination or inside it' "$_t/e8-outer" keep $_e8_tsn --brownfield "$_t/e8-outer/sub"
  [ "$(ls -A "$_t/e8-outer")" = "sub" ] || { echo "FAIL: E8 — the dest holding the target was changed by the refused run"; fail=1; }

  # E9 — a committed `profiles` that is a symlink to a directory outside the staging must not be
  # carved through: the outside scaffold survives, and the export itself still ran.
  _e9f="$_t/e9-fix"; _e9o="$_t/e9-outside"; _e9d="$_t/e9-exp"
  mkdir -p "$_e9f/scripts" "$_e9o/x/scaffold"
  cp "$_self" "$_e9f/scripts/adopter-export.sh"
  cp "$ROOT/scripts/incept.sh" "$_e9f/scripts/incept.sh"
  printf 'outside\n' > "$_e9o/x/scaffold/a.txt"
  ln -s "$_e9o" "$_e9f/profiles"
  ( cd "$_e9f" && git init -q && git add -A \
      && git -c user.email=e@kit -c user.name=e commit -qm e9 >/dev/null 2>&1 )
  ( cd "$_e9f" && sh scripts/adopter-export.sh "$_e9d" --profile x --brownfield "$_bf_tgt" >/dev/null 2>&1 ) || true
  if [ -f "$_e9o/x/scaffold/a.txt" ] && [ -L "$_e9d/profiles" ]; then
    echo "PASS: E9 — a symlinked profiles/ is not carved through: the outside scaffold survives"
  else
    echo "FAIL: E9 — the outside scaffold was removed through a symlinked profiles/, or the fixture export did not carry the symlink"; fail=1
  fi

  # --- SWAS-1012 FP1-FP8: --brownfield sets aside the kit's front-page files where the target has its own.
  # Each cell's target is its own sibling `mktemp -d` directory (outside the kit and outside <dest>), so none
  # of the E8 refusals fires. The cells drive do_export on the real tree; the mutants run on the twins
  # (FP1f..FP8f) in the mutant fixture repo below, because a byte copy resolves ROOT from its own location.
  echo "--- SWAS-1012: --brownfield front-page carve (FP1-FP8) ---"
  _fp_mk() {  # <file name>... -> sets _fp_tg to a new target directory holding those files
    _fp_tg=$(mktemp -d "$_t/fp-tgt.XXXXXX")
    for _fpn in "$@"; do printf 'mine\n' > "$_fp_tg/$_fpn"; done
  }
  _fp_run() {  # <tag> <target> -> sets _fpd (the export dir) and _fpo (its stdout)
    _fpd="$_t/fp-$1"
    _fpo=$(do_export "$_fpd" typescript-node "$2" 2>/dev/null) || _fpo=""
    if [ ! -f "$_fpd/.kit-manifest" ]; then echo "FAIL: $1 — the --brownfield export did not build"; fail=1; fi
  }
  _fp_once() {  # <text> -> 0 when stdout _fpo holds the text on exactly one line
    [ "$(printf '%s\n' "$_fpo" | grep -Fc -e "$1" || true)" = 1 ]
  }
  _fp_none() {  # <text> -> 0 when stdout _fpo holds the text on no line
    [ "$(printf '%s\n' "$_fpo" | grep -Fc -e "$1" || true)" = 0 ]
  }
  _fp_snap() {  # <dir> -> stdout: its entry list and checksums
    ( cd "$1" && find . | LC_ALL=C sort && find . -type f | LC_ALL=C sort | tr '\n' '\0' | xargs -0 cksum )
  }
  _fp_result() {  # <label> <0|1 ok> <pass text> <fail text>
    if [ "$2" = 0 ]; then echo "PASS: $1 — $3"; else echo "FAIL: $1 — $4"; fail=1; fi
  }

  # FP1 — the target's own readme, licence, contributing guide and code of conduct (any case/extension) stay.
  _fp_mk readme.md License CONTRIBUTING.md code_of_conduct.MD
  _fp1_tg=$_fp_tg; _fp1_before=$(_fp_snap "$_fp1_tg")
  _fp_run fp1 "$_fp1_tg"; _fp1d=$_fpd
  _fp1_bad=0
  for _fpn in README.md CONTRIBUTING.md CODE_OF_CONDUCT.md LICENSE; do
    if [ -e "$_fp1d/$_fpn" ]; then _fp1_bad=1; fi
    if [ "$_fpn" = LICENSE ]; then _fp_once 'LICENSE kept as LICENSE-SPARKWRIGHT' || _fp1_bad=1; else _fp_once "$_fpn left out" || _fp1_bad=1; fi
  done
  cmp -s "$_fp1d/LICENSE-SPARKWRIGHT" "$ROOT/LICENSE" || _fp1_bad=1
  [ -f "$_fp1d/SECURITY.md" ] || _fp1_bad=1
  _fp_result FP1 "$_fp1_bad" "the kit's README, CONTRIBUTING and CODE_OF_CONDUCT are left out, LICENSE moved to LICENSE-SPARKWRIGHT byte-identical, SECURITY.md kept, one line per decision" \
    "front-page carve wrong (a kit file still present, LICENSE-SPARKWRIGHT missing or different, SECURITY.md missing, or a decision line not printed exactly once)"

  # FP2 — the baseline: an empty target leaves every front-page file in place and prints no decision line.
  _fp_mk
  _fp_run fp2 "$_fp_tg"
  _fp2_bad=0
  for _fpn in README.md LICENSE CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md; do [ -f "$_fpd/$_fpn" ] || _fp2_bad=1; done
  [ ! -e "$_fpd/LICENSE-SPARKWRIGHT" ] || _fp2_bad=1
  _fp_none 'your repository has' || _fp2_bad=1
  _fp_result FP2 "$_fp2_bad" "an empty target keeps all five front-page files, no LICENSE-SPARKWRIGHT, no decision line" \
    "an empty target changed the front-page files or printed a decision line"

  # FP3 — the records describe the final tree.
  _fp3_bad=0
  grep -qxF 'LICENSE-SPARKWRIGHT' "$_fp1d/.kit-manifest" || _fp3_bad=1
  grep -q ' LICENSE-SPARKWRIGHT$' "$_fp1d/.kit-digests" || _fp3_bad=1
  for _fpn in README.md LICENSE CONTRIBUTING.md CODE_OF_CONDUCT.md; do
    if grep -qxF "$_fpn" "$_fp1d/.kit-manifest"; then _fp3_bad=1; fi
    if grep -q " $_fpn\$" "$_fp1d/.kit-digests"; then _fp3_bad=1; fi
  done
  _fp_result FP3 "$_fp3_bad" ".kit-manifest and .kit-digests list LICENSE-SPARKWRIGHT and none of the left-out names" \
    "a record names a left-out file or omits LICENSE-SPARKWRIGHT"

  # FP4 — the target is only read.
  if [ "$(_fp_snap "$_fp1_tg")" = "$_fp1_before" ]; then _fpr=0; else _fpr=1; fi
  _fp_result FP4 "$_fpr" "the target's entries and checksums are identical before and after the export" "the export changed the target"

  # FP5 — SECURITY.md: (a) exact name, (b) another letter case, (c) only another extension.
  _fp_mk SECURITY.md; _fp_run fp5a "$_fp_tg"
  _fp5a_bad=0
  [ ! -e "$_fpd/SECURITY.md" ] || _fp5a_bad=1
  _fp_once 'SECURITY.md left out' || _fp5a_bad=1
  _fp_none 'security-policy.sh' || _fp5a_bad=1
  _fp_result FP5a "$_fp5a_bad" "an exact SECURITY.md in the target leaves the kit's out, with no rename line" "the exact-name case is wrong"
  _fp_mk security.md; _fp_run fp5b "$_fp_tg"
  _fp5b_bad=0
  [ ! -e "$_fpd/SECURITY.md" ] || _fp5b_bad=1
  _fp_once 'SECURITY.md left out' || _fp5b_bad=1
  _fp_once 'security-policy.sh' || _fp5b_bad=1
  _fp_result FP5b "$_fp5b_bad" "security.md in the target leaves the kit's SECURITY.md out and prints the rename line" "the case-folded case is wrong"
  _fp_mk SECURITY.rst; _fp_run fp5c "$_fp_tg"
  _fp5c_bad=0
  [ -f "$_fpd/SECURITY.md" ] || _fp5c_bad=1
  _fp_none 'SECURITY.md left out' || _fp5c_bad=1
  _fp_result FP5c "$_fp5c_bad" "SECURITY.rst alone keeps the kit's SECURITY.md" "SECURITY.md was left out for a non-colliding stem"

  # FP6 — a directory of a matching name also matches.
  _fp_mk; mkdir "$_fp_tg/README"; _fp_run fp6 "$_fp_tg"
  _fp6_bad=0
  [ ! -e "$_fpd/README.md" ] || _fp6_bad=1
  _fp_once 'README.md left out' || _fp6_bad=1
  _fp_result FP6 "$_fp6_bad" "a directory named README sets the kit's README.md aside" "a directory named README did not set README.md aside"

  # FP7 — the stem rule: LICENSE.txt and README.rst match.
  _fp_mk LICENSE.txt README.rst; _fp_run fp7 "$_fp_tg"
  _fp7_bad=0
  [ ! -e "$_fpd/README.md" ] || _fp7_bad=1
  [ ! -e "$_fpd/LICENSE" ] || _fp7_bad=1
  [ -f "$_fpd/LICENSE-SPARKWRIGHT" ] || _fp7_bad=1
  _fp_result FP7 "$_fp7_bad" "LICENSE.txt and README.rst match by stem: LICENSE moved, README.md left out" "the stem rule did not apply"

  # FP8 — a target name with a control byte is never printed raw.
  _fp_mk "readme.$(printf '\001')md"; _fp_run fp8 "$_fp_tg"
  _fp8_bad=0
  [ ! -e "$_fpd/README.md" ] || _fp8_bad=1
  _fp_once 'a file of yours' || _fp8_bad=1
  [ "$(printf '%s' "$_fpo" | LC_ALL=C tr -d '\001')" = "$_fpo" ] || _fp8_bad=1
  _fp_result FP8 "$_fp8_bad" "a control-byte name sets README.md aside, the line says 'a file of yours', stdout holds no control byte" \
    "the control-byte case is wrong (README.md kept, no 'a file of yours' line, or a raw control byte printed)"

  # --- SWAS-1011 mutants: each is a `sed` of ONE tagged line in a byte copy of this script, run in a
  # throwaway git repo (every fixture file committed before the export: the export is `git archive HEAD`).
  # The real cells above run THIS script, not the copy, so each mutant reds a fixture-shaped twin: E1f
  # (carved, ci.yml kept), E2f (plain export keeps both scaffolds), E3f (manifest names no scaffold path),
  # E6 (the marker-less foreign fixture, which is its own twin) and E8np (bare --brownfield refused). A
  # control run (no mutation) must hold every cell, and a mutant whose sed changed nothing is a FAIL.
  # Each sed pattern is anchored on the code's own indent and tag so it cannot match these lines.
  echo "--- SWAS-1011: mutants of the --brownfield carve and its refusal ---"
  _bfm_cells() {  # <name> <sed-script> <mutates|control> -> sets _bfm_red (space-led list of cells that failed)
    _bfmn=$1; _bfmf="$_t/bfm-$1"; _bfm_red=""
    mkdir -p "$_bfmf/scripts" "$_bfmf/profiles/x/scaffold/test" "$_bfmf/profiles/x/scaffold-cli/test"
    sed -e "$2" "$_self" > "$_bfmf/scripts/adopter-export.sh"
    if [ "$3" = mutates ] && cmp -s "$_self" "$_bfmf/scripts/adopter-export.sh"; then _bfm_red=" SED-CHANGED-NOTHING"; return 0; fi
    cp "$ROOT/scripts/incept.sh" "$_bfmf/scripts/incept.sh"
    printf '# fixture readme\n' > "$_bfmf/README.md"
    printf 'fixture licence\n' > "$_bfmf/LICENSE"
    printf '# fixture contributing\n' > "$_bfmf/CONTRIBUTING.md"
    printf '# fixture security\n' > "$_bfmf/SECURITY.md"
    printf 'name: x\n' > "$_bfmf/profiles/x/ci.yml"
    printf '# x\n' > "$_bfmf/profiles/x.md"
    printf 'test\n' > "$_bfmf/profiles/x/scaffold/test/a.test.js"
    printf 'test\n' > "$_bfmf/profiles/x/scaffold-cli/test/b.test.js"
    ( cd "$_bfmf" && git init -q && git add -A \
        && git -c user.email=m@kit -c user.name=m commit -qm bfm >/dev/null 2>&1 )
    _bfmo="$_bfmf-bf"; _bfmp="$_bfmf-plain"; _bfme="$_bfmf-e6"; _bfmr="$_bfmf-np"
    ( cd "$_bfmf" && sh scripts/adopter-export.sh "$_bfmo" --profile x --brownfield "$_bf_tgt" >/dev/null 2>&1 ) || true
    ( cd "$_bfmf" && sh scripts/adopter-export.sh "$_bfmp" --profile x >/dev/null 2>&1 ) || true
    if [ -f "$_bfmo/profiles/x/ci.yml" ] && [ ! -e "$_bfmo/profiles/x/scaffold" ] && [ ! -e "$_bfmo/profiles/x/scaffold-cli" ]; then :; else _bfm_red="$_bfm_red E1f"; fi
    if [ -f "$_bfmp/profiles/x/scaffold/test/a.test.js" ] && [ -f "$_bfmp/profiles/x/scaffold-cli/test/b.test.js" ]; then :; else _bfm_red="$_bfm_red E2f"; fi
    if [ -f "$_bfmo/.kit-manifest" ] && ! grep -q scaffold "$_bfmo/.kit-manifest"; then :; else _bfm_red="$_bfm_red E3f"; fi
    cp "$_bfmf/scripts/adopter-export.sh" "$_fx/scripts/adopter-export.sh"
    ( cd "$_fx" && sh scripts/adopter-export.sh "$_bfme" --profile x --brownfield "$_bf_tgt" >/dev/null 2>&1 ) || true
    cp "$_self" "$_fx/scripts/adopter-export.sh"
    if [ -f "$_bfme/profiles/x/ci.yml" ] && [ ! -e "$_bfme/profiles/x/scaffold" ]; then :; else _bfm_red="$_bfm_red E6"; fi
    _bfmrc=0
    _bfmerr=$( ( cd "$_bfmf" && sh scripts/adopter-export.sh "$_bfmr" --brownfield "$_bf_tgt" ) 2>&1 >/dev/null ) || _bfmrc=$?
    if [ "$_bfmrc" = 2 ] && printf '%s\n' "$_bfmerr" | grep -q 'needs --profile' && [ ! -e "$_bfmr" ]; then :; else _bfm_red="$_bfm_red E8np"; fi
    _bfm_twins
    return 0
  }
  _bfm_mk() {  # <file name>... -> sets _bfm_tg to a new target directory (its own sibling of the fixture repo) holding those empty files
    _bfm_tg=$(mktemp -d "$_t/bfmt.XXXXXX")
    for _bfm_nm in "$@"; do : > "$_bfm_tg/$_bfm_nm"; done
  }
  _bfm_tx() {  # <tag> <target> -> sets _bfm_xd (the export dir) and _bfm_xo (its stdout); a twin export that built nothing is red as XRUN-<tag>
    _bfm_xd="$_bfmf-x$1"
    _bfm_xo=$( cd "$_bfmf" && sh scripts/adopter-export.sh "$_bfm_xd" --profile x --brownfield "$2" 2>/dev/null ) || _bfm_xo=""
    [ -f "$_bfm_xd/.kit-manifest" ] || _bfm_red="$_bfm_red XRUN-$1"
  }
  _bfm_twins() {  # SWAS-1012 front-page twins: one export of the fixture repo per twin, each into its own target
    _bfm_mk readme.md License; _bfm_tx 1 "$_bfm_tg"
    if [ ! -e "$_bfm_xd/README.md" ] && [ ! -e "$_bfm_xd/LICENSE" ] && [ -f "$_bfm_xd/LICENSE-SPARKWRIGHT" ]; then :; else _bfm_red="$_bfm_red FP1f"; fi
    _bfm_mk readme.md; _bfm_tx 3 "$_bfm_tg"
    if [ -f "$_bfm_xd/.kit-manifest" ] && ! grep -qxF 'README.md' "$_bfm_xd/.kit-manifest"; then :; else _bfm_red="$_bfm_red FP3f"; fi
    _bfm_mk security.md; _bfm_tx 5b "$_bfm_tg"
    if [ ! -e "$_bfm_xd/SECURITY.md" ] && printf '%s\n' "$_bfm_xo" | grep -Fq 'security-policy.sh'; then :; else _bfm_red="$_bfm_red FP5bf"; fi
    _bfm_mk SECURITY.rst; _bfm_tx 5c "$_bfm_tg"
    if [ -f "$_bfm_xd/SECURITY.md" ]; then :; else _bfm_red="$_bfm_red FP5cf"; fi
    _bfm_mk security.md; _bfm_tx 5d "$_bfm_tg"
    if printf '%s\n' "$_bfm_xo" | grep -Fq 'security-policy.sh'; then :; else _bfm_red="$_bfm_red FP5df"; fi
    _bfm_mk README.rst; _bfm_tx 7 "$_bfm_tg"
    if [ ! -e "$_bfm_xd/README.md" ]; then :; else _bfm_red="$_bfm_red FP7f"; fi
    _bfm_mk "readme.$(printf '\001')md"; _bfm_tx 8 "$_bfm_tg"
    if printf '%s\n' "$_bfm_xo" | grep -Fq 'a file of yours' && [ "$(printf '%s' "$_bfm_xo" | LC_ALL=C tr -d '\001')" = "$_bfm_xo" ]; then :; else _bfm_red="$_bfm_red FP8f"; fi
  }
  _bfm_verdict() {  # <label> <expected red cells, space-led, "" for none>
    if [ "$_bfm_red" = "$2" ]; then
      echo "PASS: mutant $1 — killed; it reds exactly:${2:- (none: the unmutated control holds every cell)}"
    else
      echo "FAIL: mutant $1 — expected red cells [${2# }], got [${_bfm_red# }]"; fail=1
    fi
  }
  _bfm_cells control 's/^NO-SUCH-LINE-1011$//' control
  _bfm_verdict control ""
  _bfm_cells NOCARVE 's/^      rm -rf .*# MUT-NOCARVE$/      :/' mutates
  _bfm_verdict MUT-NOCARVE " E1f E3f E6"
  _bfm_cells CARVEALWAYS 's/^  \[ -n .*# MUT-CARVEALWAYS$/  :/' mutates
  _bfm_verdict MUT-CARVEALWAYS " E2f"
  _bfm_cells CLIKEPT 's/^    for _bfc_s in .*# MUT-CLIKEPT$/    for _bfc_s in "${_bfc_pd}scaffold"; do/' mutates
  _bfm_verdict MUT-CLIKEPT " E1f E3f"
  _bfm_cells BFLATE 's/^  _bf_carve .*# MUT-BFLATE-AT$/  _BF_LATE=1/' mutates
  _bfm_verdict MUT-BFLATE " E3f FP3f"
  _bfm_cells BFNOPROFILE '/^  \[ -n .*# MUT-BFNOPROFILE$/d' mutates
  _bfm_verdict MUT-BFNOPROFILE " E8np"
  # --- SWAS-1012 front-page mutants: each reds named twins (FP1f..FP8f above), never an FP cell on the real tree.
  # The expected set is every twin the mutated line moves, in twin order; a sed that changed nothing is a FAIL.
  _bfm_cells FPNAME "s/^  if printf .*# MUT-FPNAME\$/  if :; then printf '%s' \"\$1\"; else printf 'a file of yours'; fi/" mutates
  _bfm_verdict MUT-FPNAME " FP8f"
  _bfm_cells FPSTEM 's/^      s = (i > 0) .*# MUT-FPSTEM$/      s = $0/' mutates
  _bfm_verdict MUT-FPSTEM " FP1f FP3f FP7f FP8f"
  _bfm_cells FPCASE 's/^      if (tolower(s) == tolower(want)) \(.*# MUT-FPCASE\)$/      if (s == want) \1/' mutates
  _bfm_verdict MUT-FPCASE " FP1f FP3f FP8f"
  _bfm_cells FPLICDROP 's/^    mv .*# MUT-FPLICDROP$/    rm -f "$1\/LICENSE"/' mutates
  _bfm_verdict MUT-FPLICDROP " FP1f"
  _bfm_cells FPSECFOLD 's/^\(  _bfs_f=.*\)tolower(\$0) == "security.md"\(.*# MUT-FPSECFOLD MUT-FPSECSTEM\)$/\1$0 == "SECURITY.md"\2/' mutates
  _bfm_verdict MUT-FPSECFOLD " FP5bf FP5df"
  _bfm_cells FPSECSTEM 's/^\(  _bfs_f=.*\)tolower(\$0) == "security.md"\(.*# MUT-FPSECFOLD MUT-FPSECSTEM\)$/\1tolower(substr($0, 1, index($0, ".") - 1)) == "security"\2/' mutates
  _bfm_verdict MUT-FPSECSTEM " FP5cf"
  # MUT-FPSECPATH swaps the listing's exact-name test for a path test. A path test sees security.md as SECURITY.md only on a
  # case-insensitive filesystem, so its kill is recorded only there; on a case-sensitive one the twins stay green by design.
  _bfm_fs() {  # -> sets _bfm_ci to 1 on a case-insensitive filesystem: create `a` in the selftest's temp dir and test `A`
    _bfm_ci=0; : > "$_t/bfm-case-a"
    if [ -e "$_t/bfm-case-A" ]; then _bfm_ci=1; fi
    rm -f "$_t/bfm-case-a"
  }
  _bfm_fs
  _bfm_cells FPSECPATH 's/^  if printf .*# MUT-FPSECPATH$/  if [ -e "$3\/SECURITY.md" ]; then _bfs_x=1; else _bfs_x=0; fi/' mutates
  if [ "$_bfm_ci" = 1 ]; then
    echo "filesystem: case-insensitive, so MUT-FPSECPATH's kill is recorded"
    _bfm_verdict MUT-FPSECPATH " FP5bf FP5df"
  elif [ -z "$_bfm_red" ]; then
    echo "N-A: mutant MUT-FPSECPATH — filesystem is case-sensitive, so the path test is false for security.md and its twins stay green by design; no kill is recorded on this runner"
  else
    echo "FAIL: mutant MUT-FPSECPATH — on a case-sensitive filesystem the twins must stay green, got red [${_bfm_red# }]"; fail=1
  fi
  if [ -z "$(ls -A "$_bf_tgt")" ]; then
    echo "PASS: the --brownfield target stayed empty through every export and mutant (it is only read)"
  else
    echo "FAIL: the --brownfield target was written"; fail=1
  fi

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
_bf_refuse() { echo "adopter-export: $1" >&2; exit 2; }
_bf_phys() {  # <path> -> stdout: its physical path; a not-yet-existing tail is appended to the nearest existing ancestor
  _bpp=$1; _bps=''
  while [ ! -d "$_bpp" ]; do
    _bps="/$(basename "$_bpp")$_bps"; _bpp=$(dirname "$_bpp")
  done
  case "$_bps" in
    */../*|*/..|*/./*|*/.) return 1 ;;
  esac
  _bpd=$(CDPATH='' cd -P "$_bpp" && pwd -P) || return 1
  printf '%s%s\n' "${_bpd%/}" "$_bps"
}
_bf_within() {  # <inner> <outer> -> 0 when <inner> is <outer> or lies under it (both physical)
  [ "$1" = "$2" ] && return 0
  case "$1" in
    "${2%/}"/*) return 0 ;;
  esac
  return 1
}
bf_validate() {  # <target> <dest> <profile> — every refusal exits 2 before any work; the target is only read
  [ -n "$3" ] || _bf_refuse "--brownfield needs --profile <stack> (the export keeps only your stack's files)"   # MUT-BFNOPROFILE
  _bvt=$1
  while [ "${#_bvt}" -gt 1 ] && [ "${_bvt%/}" != "$_bvt" ]; do _bvt=${_bvt%/}; done
  [ ! -L "$_bvt" ] || _bf_refuse "--brownfield target is a symlink ('$1'); name the real directory"
  [ -d "$_bvt" ] || _bf_refuse "--brownfield target is not an existing directory ('$1')"
  _bvp=$(_bf_phys "$_bvt") || _bf_refuse "--brownfield target '$1' cannot be resolved to a physical path"
  _bvr=$(_bf_phys "$ROOT") || _bf_refuse "cannot resolve the kit root to a physical path"
  _bf_within "$_bvp" "$_bvr" && _bf_refuse "--brownfield target is the kit or inside it ('$1'); name your own repository"
  _bvd=$(_bf_phys "$2") || _bf_refuse "<dest-dir> '$2' cannot be resolved to a physical path"
  _bf_within "$_bvp" "$_bvd" && _bf_refuse "--brownfield target is the destination or inside it ('$1'); export to a directory outside your repository"
  _bf_within "$_bvd" "$_bvp" && _bf_refuse "--brownfield: dest is inside the --brownfield target ('$2'); export outside your repository and copy the tree in"
  return 0
}

DEST=""; PROFILE=""; BF_SEEN=0; BF_TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --brownfield)
      [ "$BF_SEEN" = 0 ] || _bf_refuse "--brownfield given twice"
      BF_SEEN=1
      { [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#-}" = "$2" ]; } || _bf_refuse "--brownfield needs a target repository (the path of your own repo, which is only read)"
      BF_TARGET=$2; shift 2 ;;
    --profile) [ $# -ge 2 ] || usage; PROFILE=$2; [ -n "$PROFILE" ] || { echo "adopter-export: --profile requires a non-empty stack name" >&2; usage; }; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "adopter-export: unknown flag $1" >&2; usage ;;
    *) [ -z "$DEST" ] || usage; DEST=$1; shift ;;
  esac
done
[ -n "$DEST" ] || usage
[ "$BF_SEEN" = 0 ] || bf_validate "$BF_TARGET" "$DEST" "$PROFILE"
do_export "$DEST" "$PROFILE" "$BF_TARGET"
