#!/bin/sh
# Why this gate: sparkwright explain a11y
# a11y-obligation.sh — HITL obligation: a change-set touching a user-facing UI surface (the
# components/views/pages/screens/ui/frontend/styles directories, at repo root or nested, plus the UI and
# view-template MARKUP EXTENSIONS enumerated in A11Y_SURFACE_GLOBS below — that variable is the single
# source of truth, and the selftest derives its probes FROM it) MUST carry a filled A11Y-SIGNOFF record,
# else FAIL. Diff-level, riding the shipped obligation engine (same as threat-obligation.sh /
# uat-obligation.sh). Closes the Definition-of-Done Accessibility item (CLAUDE.md) and
# DEVELOPMENT-STANDARDS.md §8 (WCAG 2.1 AA), which were prose-only until now.
#
# SCOPE (honest ceiling): green = an A11Y-SIGNOFF record EXISTS and is FILLED for a triggered change —
# NOT that WCAG 2.1 AA was actually met, that axe/Lighthouse was actually run, that the recorded pass/fail
# verdicts are truthful, or that the record is FRESH for this change (review + the signer's name backstop
# those). "Filled" is coarse: the engine rejects the template banner and its stub tokens, but an EMPTY or
# one-line record still reads as filled — a minimum-substance floor is boarded, not claimed. N-A = the
# change-set touches no user-facing UI surface (trigger-absence), exactly like uat-obligation.sh.
# CONSERVATIVE by design: clear-UI globs ONLY — ambiguous/non-UI files are N-A and false-negatives are
# accepted (the only 'uncertain' source is a derive-failure, which fails CLOSED).
#
# The record is read at the REPOSITORY ROOT (./A11Y-SIGNOFF.md) — not docs/sign-offs/. The template's
# banner states this; a record filed elsewhere reds with "absent", which is fail-closed but confusing.
#
# SURFACE vs uat-obligation.sh: the SAME clear-UI directory set, because a11y and taste are two DIFFERENT
# judgments about the SAME user-facing surface (a WCAG verdict signed by the designer/a11y owner vs. an
# acceptance verdict signed by QA/PO). Two DELIBERATE divergences, each from evidence, not taste:
#  1. VIEW-TEMPLATE MARKUP EXTENSIONS replace uat's bare `*/templates/*`. A directory named `templates/`
#     is NOT a UI signal — Helm, CloudFormation and cookiecutter all use it, and this repo carries 14 such
#     files (profiles/*/deploy/helm/templates/*.yaml). Gating them would demand a WCAG sign-off for a
#     Kubernetes Deployment manifest: a false positive with no honest way to satisfy it, and a gate that
#     reds on compliant behavior is a gate that gets deleted. A view template is identified instead by its
#     MARKUP EXTENSION, which also catches a view template living OUTSIDE a templates/ dir.
#     HONEST TRADE (do not restate this as a strict win — an earlier draft did, and review falsified it):
#     the extension list is broader in one direction and NARROWER in another. A view template whose
#     extension is not listed (.vm, .st, .dust, a bare .tmpl variant) is now N/A where the bare directory
#     glob would have caught it. The list below enumerates the mainstream engines, including those the
#     kit's own profiles ship (.gohtml/.tmpl for go, .cshtml/.razor for dotnet, .ftl for java-spring);
#     the residual false-negative is accepted under the conservative posture and named here.
#  2. *.html/*.htm: semantic HTML is a first-class a11y surface, whereas a raw .html edit is not
#     necessarily a taste change.
#
# KNOWN FALSE POSITIVES (boarded, OBLIGATION-CONFIG-TEMPLATE-EXT): several listed extensions are also
# used for NON-UI templates — Ansible/Chef config (roles/nginx/templates/nginx.conf.j2,
# app.conf.erb), Terraform (user_data.tpl), and — note the irony — Helm's own _helpers.tpl, the exact
# case the paragraph above uses to justify dropping */templates/*. So the extension approach narrows that
# false-positive class without eliminating it. Zero such files exist in this repo today; an adopter with
# Ansible, Terraform or Helm will hit it. A real fix needs exclude-glob support in the engine.
# Disclosed rather than discovered.
#
# KNOWN FALSE NEGATIVES: a view template whose extension is not listed (.vm, .st, .dust), server-rendered
# .php/.blade.php, and Android res/layout/*.xml are all N/A. Conservative posture, accepted, named.
#
# NON-ASCII PATHS: fixed in the engine this slice (obl_changeset sets core.quotePath=false and splits on
# NUL). Before that fix a path with one accented byte was quote-wrapped and evaded every EXTENSION glob —
# and because this obligation's surface is mostly extensions, it was the gate this bit hardest.
#
# FRESHNESS (the same disclosure threat-obligation.sh:8 makes): this gate proves a filled record EXISTS —
# NOT that it is fresh for THIS change. One committed root A11Y-SIGNOFF.md satisfies every later UI PR.
# The record carries a Date and a Feature/story link so a reviewer can see staleness; the gate cannot.
#
# Usage:
#   sh conformance/a11y-obligation.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/a11y-obligation.sh --changed FILE  (fixture path list; honored ONLY under
#                                                      --selftest / the KIT_OBL_TEST env flag — ignored in production)
#   sh conformance/a11y-obligation.sh --selftest
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` is the correct idiom: it clears CDPATH for this one command so
# a user's CDPATH cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Tell the engine it is being SOURCED (not executed directly), so its --selftest dispatch stays inert
# here: without this, `sh a11y-obligation.sh --selftest` would run the LIB's selftest (the sourced lib
# sees $1=--selftest) instead of this obligation's 9-leg selftest. Value is 'yes' (NOT a numeric flag) so
# the non-vacuity sweep — which neuters a pre-marker numeric-flag assignment — cannot flip it; this line
# carries no mutable idiom, so run_a11y_obligation stays the (idiomless) mutation region and this file's
# verdict is unchanged. A $0-basename guard would not survive the sweep renaming the lib's copy to .nv-mut-*.
OBL_LIB_SOURCED=yes
. "$DIR/conformance/obligation-lib.sh"

# The obligation: user-facing-UI globs + A11Y-SIGNOFF record. THIS STRING IS THE SINGLE SOURCE OF TRUTH:
# the selftest's coverage leg DERIVES one probe path per glob from it, so adding a glob automatically adds
# its proof and a glob written in an unprobeable SHAPE is itself a failure. Do not hand-maintain a probe
# list alongside it — an earlier draft did, and a newly-added glob then shipped unproven.
# WHAT DERIVED PROBES CANNOT DO (measured, so the comment does not overclaim as an earlier one did): a
# probe derived FROM a glob always matches that glob, so a MISTYPED glob (*.sccs, */screen/*) self-
# validates and the leg stays green. Only the EXACT count lock below catches a glob being dropped, and
# nothing here catches a typo — review and the DELETIONS lock are the backstop. Round-1's hand-listed
# probes caught typos but missed additions; derivation is the opposite trade, stated rather than implied.
# Each directory appears TWICE: `x/*` for a repo-root directory and `*/x/*` for a nested one. `*/x/*`
# requires a leading path segment, so root-level `components/Nav.tsx` would otherwise be N/A.
A11Y_SURFACE_GLOBS='components/*|*/components/*|views/*|*/views/*|pages/*|*/pages/*|screens/*|*/screens/*|ui/*|*/ui/*|frontend/*|*/frontend/*|styles/*|*/styles/*|*.tsx|*.jsx|*.vue|*.svelte|*.css|*.scss|*.less|*.html|*.htm|*.j2|*.jinja|*.jinja2|*.erb|*.hbs|*.handlebars|*.ejs|*.twig|*.pug|*.haml|*.slim|*.liquid|*.mustache|*.astro|*.njk|*.tmpl|*.gohtml|*.templ|*.tpl|*.cshtml|*.razor|*.jsp|*.jspx|*.ftl|*.heex|*.eex'

run_a11y_obligation() {   # args: forwarded (--changed FILE | none)
  obligation_gate \
    --name "a11y" \
    --surface-globs "$A11Y_SURFACE_GLOBS" \
    --record "A11Y-SIGNOFF.md" \
    --template-marker "templates/A11Y-SIGNOFF-TEMPLATE.md" \
    "$@"
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  # The two EXTERNALLY DECLARED counts the completeness locks assert against. Declared here, not computed
  # from the things they check — a lock derived from its subject can always be satisfied by construction.
  A11Y_TEMPLATE_STUB_ROWS=10     # fillable rows in A11Y-SIGNOFF-TEMPLATE.md          (LEG 9)
  A11Y_SURFACE_GLOB_COUNT=49     # alternations in A11Y_SURFACE_GLOBS                 (LEG 5)
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/a11y-st.XXXXXX")"; trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0
  # LEG 1 (liveness/negative): user-facing UI surface touched, NO record -> RED
  printf 'src/components/Nav.tsx\n' > "$_tmp/changed"
  if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: UI surface with no A11Y-SIGNOFF did not FAIL"; rc=1
  fi
  # LEG 2 (positive): no UI surface -> green (N-A)
  printf 'docs/README.md\n' > "$_tmp/changed"
  if ! run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: non-UI change did not pass (N-A)"; rc=1
  fi
  # LEG 3 (fail-safe, simulated): --force-uncertain simulates the uncertain band (the conservative posture
  # has no per-file uncertain heuristic; the REAL uncertain trigger is a derive-failure — LEG 4). NO record -> RED
  printf 'config/settings.yaml\n' > "$_tmp/changed"
  if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" --force-uncertain >/dev/null 2>&1; then
    echo "SELFTEST FAIL: uncertain surface with no record did not FAIL (fail-safe broken)"; rc=1
  fi
  # LEG 4 (REAL derive-failure, C1/H1): a change-set that CANNOT be derived (no resolvable base) must fail
  # CLOSED — route to uncertain and require the record. Throwaway repo with NO origin/main and NO 'main'
  # branch, so both merge-base probes fail: a REAL derive-failure, not the --force-uncertain simulation.
  _dr="$_tmp/derive"; mkdir -p "$_dr"
  git -C "$_dr" init -q >/dev/null 2>&1
  git -C "$_dr" config user.email obl@test.local
  git -C "$_dr" config user.name obl-test
  : > "$_dr/file.txt"; git -C "$_dr" add file.txt; git -C "$_dr" commit -qm init >/dev/null 2>&1
  git -C "$_dr" branch -m obl-st-nobase >/dev/null 2>&1   # rename so neither 'main' nor 'master' resolves
  if ( cd "$_dr" && run_a11y_obligation --root "$_dr" ) >/dev/null 2>&1; then
    echo "SELFTEST FAIL: underivable change-set (no resolvable base) did not FAIL (derive fail-open)"; rc=1
  fi
  # LEG 5 (GLOB COVERAGE): EVERY surface glob must be load-bearing. Without this, only the glob a fixture
  # happens to exercise is proven and the rest can be DELETED while the selftest stays green — a mutation
  # probe confirmed 15 of 16 globs were unproven before this leg existed. Deletion is caught by the exact
  # count lock below; a MISTYPED glob is NOT caught by anything here (it self-validates — see the note at
  # A11Y_SURFACE_GLOBS). Do not read this leg as proving the globs are correct, only that they are present.
  # Each directory glob is probed with the inert extension '.q' so it cannot double-match an extension
  # glob, and each extension glob with a path in no matching directory. Runs BEFORE LEG 6 creates the
  # record, so every RED here is caused by trigger + absence, never by ordering.
  # Probes are DERIVED from $A11Y_SURFACE_GLOBS, never hand-listed, so the leg cannot fall behind the
  # surface it is proving. Three recognised glob shapes; an unrecognised one is itself a failure, so a
  # future glob written in a shape this derivation cannot probe can never ship silently unproven.
  # SPLIT VIA `tr` + `IFS= read`, NOT by save/restore of the global IFS. An earlier version wrapped a
  # `for` in `_oldifs=$IFS; IFS='|'; set -f` … `IFS=$_oldifs`, which semgrep's
  # bash.lang.security.ifs-tampering flagged FOUR times — caught not by any local check but by the kit's
  # own emitted-artifact SAST gate (`artifact-gate`), on the artifact, which is precisely what that gate
  # exists for. Reproduced locally: old file 4 findings, this one 0.
  # (obl_detect in obligation-lib.sh uses a save/restore form that this rule does NOT flag — it ships
  # clean and needs no change. Do not "fix" it on the strength of this note.)
  # `IFS= read -r` is a command-scoped prefix assignment, not a global mutation. Reading from a FILE
  # (not a pipe) keeps the loop in this shell, so `rc` and the counters survive it; a `… | while` would
  # run in a subshell and silently discard every failure this leg detects.
  _covered=0; _globcount=0
  printf '%s\n' "$A11Y_SURFACE_GLOBS" | tr '|' '\n' > "$_tmp/globs"
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    _globcount=$((_globcount + 1))
    case "$_g" in
      '*/'*'/*') _mid=${_g#*/}; _mid=${_mid%/*}; _p="a/$_mid/probe.q" ;;   # nested dir:  */components/*
      *'/*')     _mid=${_g%/*};                  _p="$_mid/probe.q"   ;;   # root dir:    components/*
      '*.'*)     _p="s/probe${_g#\*}"                                  ;;   # extension:   *.tsx
      *)         _p=""                                                 ;;
    esac
    if [ -z "$_p" ]; then
      printf 'SELFTEST FAIL: unrecognised surface-glob shape %s — the coverage leg cannot derive a probe for it, so it would ship UNPROVEN\n' "$_g"; rc=1
    else
      printf '%s\n' "$_p" > "$_tmp/changed"
      if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
        printf 'SELFTEST FAIL: surface glob dead — %s (probe %s) touched with no A11Y-SIGNOFF did not FAIL\n' "$_g" "$_p"; rc=1
      fi
      _covered=$((_covered + 1))
    fi
  done < "$_tmp/globs"
  # Family-completeness: every glob got a probe. Guards the derivation itself going silently inert.
  [ "$_covered" = "$_globcount" ] || { printf 'SELFTEST FAIL: only %s of %s surface globs were probed\n' "$_covered" "$_globcount"; rc=1; }
  # EXACT count lock, not a floor. A floor (>= 20 against an actual 49) let 26 globs — the entire
  # view-template extension set — be deleted with the selftest still printing OK. Same repair as leg 9's:
  # an EXTERNALLY DECLARED constant the code cannot satisfy by construction. Changing the surface must
  # update this number deliberately; a silent deletion reds here.
  [ "$_globcount" = "$A11Y_SURFACE_GLOB_COUNT" ] || {
    printf 'SELFTEST FAIL: %s surface globs parsed, expected exactly %s — a glob was added or removed without updating A11Y_SURFACE_GLOB_COUNT\n' \
      "$_globcount" "$A11Y_SURFACE_GLOB_COUNT"; rc=1; }
  # LEG 6 (FALSE-POSITIVE guard, derived from the SHIPPED template): UI surface touched + a genuinely
  # filled record -> PASS. The fixture is built FROM templates/A11Y-SIGNOFF-TEMPLATE.md (banner stripped,
  # every stub substituted) rather than hand-written, so this leg COUPLES the check to the artifact whose
  # tightening is this slice's headline change. A hand-written fixture cannot do that — and that gap is
  # exactly why an inert '[describe:' stub shipped green through the first review round.
  printf 'src/components/Nav.tsx\n' > "$_tmp/changed"
  _tpl="$DIR/templates/A11Y-SIGNOFF-TEMPLATE.md"
  if [ ! -f "$_tpl" ] || [ ! -s "$_tpl" ]; then
    echo "SELFTEST FAIL: templates/A11Y-SIGNOFF-TEMPLATE.md is missing or empty — the record-shape legs cannot run"; rc=1
  else
    # fill(): the shipped template with its guidance banner deleted and every stub substituted.
    # ONE GENERIC BRACKET PATTERN, not the engine's `(replace|describe|your)` vocabulary. This is the
    # round-2 correction and it is the whole point of legs 6-8: an oracle that recognises only the tokens
    # it already knows cannot detect a template that ADOPTS A NEW ONE. With the vocabulary-coupled version,
    # renaming a cell to `[attach: …]` was invisible to fill(), invisible to the stub finder, AND invisible
    # to the engine — the selftest printed "every template stub cell proven" while the cell was inert.
    # Generic `\[[^]]*\]` means any bracketed token the template adopts is substituted here and probed by
    # leg 8, so the engine must be able to see it. Consequence, deliberate: this template must not carry
    # markdown links in its VALUE cells — for a sign-off form that is a fair constraint, and violating it
    # reds loudly at leg 8 rather than silently weakening detection.
    fill() { grep -v '^> \*\*Template\.\*\*' "$_tpl" | sed 's/\[[^]]*\]/pass — axe 4.9 CI run, 0 violations, Jane Roe/g'; }
    fill > "$_tmp/A11Y-SIGNOFF.md"
    if ! run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      echo "SELFTEST FAIL: the SHIPPED template, banner-stripped and fully filled, was wrongly FAILed as a placeholder"; rc=1
    fi
    # LEG 7 (the BANNER-DELETE bypass this slice exists to close): the shipped template with ONLY its
    # banner line removed — every field still a raw stub — must be rejected as unfilled. Ties the claim
    # to the artifact: a future template edit that reintroduces the bypass reds HERE, forever.
    grep -v '^> \*\*Template\.\*\*' "$_tpl" > "$_tmp/A11Y-SIGNOFF.md"
    if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      echo "SELFTEST FAIL: the shipped template with its banner deleted was accepted as FILLED (banner-delete bypass is open)"; rc=1
    fi
    # LEG 8 (PER-CELL stub detection): the shipped template, banner stripped and every stub filled EXCEPT
    # one — must still be rejected. Run once per stub line, so NO single cell can be the inert one. This
    # is the leg that kills the '[describe:' defect (the tool-evidence cell was invisible to Signal 1) and
    # keeps every other cell honest as the template evolves.
    # Work off the BANNER-STRIPPED template so line numbers align with the fixture and the banner — whose
    # guidance text legitimately NAMES the stub tokens — is never itself probed as a cell.
    # The stub set is found with the SAME generic bracket pattern fill() substitutes — not the engine's
    # vocabulary — so a renamed token stays in the probe set and its inertness reds here.
    grep -v '^> \*\*Template\.\*\*' "$_tpl" > "$_tmp/tpl-nobanner.md"
    _stub_lines=$(grep -n '\[[^]]*\]' "$_tmp/tpl-nobanner.md" | cut -d: -f1)
    _stub_count=$(printf '%s\n' "$_stub_lines" | grep -c '[0-9]' || true)
    if [ -z "$_stub_lines" ]; then
      echo "SELFTEST FAIL: the shipped template carries NO bracketed stub token — the tightening is gone"; rc=1
    fi
    # FAMILY-COMPLETENESS LOCK (the kit's presence-check-cannot-see-substitution lesson). A generic
    # pattern catches a RENAMED token, but not a REMOVED one: reverting a cell to bare `pass / fail`
    # simply drops it from the probe set, and a per-cell loop over a shrinking set stays green — 20 such
    # mutants survived the round-1 version. So the COUNT is asserted against the template's fillable-row
    # count. Deliberately a declared constant: changing the template's row set must be a conscious act
    # that updates this number, not a silent loss of coverage.
    [ "$_stub_count" = "$A11Y_TEMPLATE_STUB_ROWS" ] || {
      printf 'SELFTEST FAIL: %s of %s fillable template rows carry a bracketed stub — a cell lost its token and is invisible to the placeholder check (or a row was added without one)\n' \
        "$_stub_count" "$A11Y_TEMPLATE_STUB_ROWS"; rc=1; }
    # Short-circuit on a failed COUNT LOCK specifically — not on any prior rc, which would silently skip
    # the per-cell probe whenever an unrelated earlier leg failed and cost a fix-and-rerun cycle. The DoS
    # this guards: the per-cell loop runs two full sed passes per bracketed line, so a PR-authored template
    # with ~10^5 rows would hang the job (measured quadratic: 450 rows = 8.6s; 100k rows now reds in ~1s).
    [ "$_stub_count" = "$A11Y_TEMPLATE_STUB_ROWS" ] || _stub_lines=""
    for _ln in $_stub_lines; do
      # Fill everything, then restore ONE line VERBATIM so exactly one stub survives. Composed from
      # head/sed/tail rather than `awk -v raw=…`: awk applies escape-sequence processing to a -v
      # assignment, so a template cell containing a backslash would be restored MANGLED and the leg would
      # then pass against a fixture the real template can never produce (a false green, review round 2).
      # `head -n 0` is ILLEGAL on BSD/macOS head (GNU accepts it), so a stub on line 1 would abort the
      # whole selftest under `set -e` with only `head: illegal line count -- 0` — green on CI, broken
      # locally. Guard the boundary rather than relying on the template's current shape.
      { [ "$_ln" -gt 1 ] && fill | head -n "$((_ln - 1))"
        sed -n "${_ln}p" "$_tmp/tpl-nobanner.md"
        fill | tail -n "+$((_ln + 1))"
      } > "$_tmp/A11Y-SIGNOFF.md"
      if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
        # printf, never echo (echo interprets backslash escapes in dash, /bin/sh on ubuntu-latest) AND
        # strip raw control bytes: printf alone still passes a literal ESC through, and GitHub Actions
        # renders ANSI SGR and honours \r — so template-controlled text could repaint a FAIL line to read
        # as a pass in the log. The exit code was never at risk; the human reading the log was.
        # The class is \000-\010\013-\037\177: 0-8, 11-31 and DEL. It MUST include \015 (CR) — the first
        # version of this line wrote \013\014\016-\037, which skipped CR and so left the exact repaint
        # this comment claims to close. Preserves \011 (tab) and \012 (LF), which are not in the class.
        printf 'SELFTEST FAIL: template line %s left as a stub was NOT detected — that cell token is inert: %s\n' \
          "$_ln" "$(sed -n "${_ln}p" "$_tmp/tpl-nobanner.md" | LC_ALL=C tr -d '\000-\010\013-\037\177')"; rc=1
      fi
    done
  fi
  unset KIT_OBL_TEST   # defence in depth: if this file is ever SOURCED rather than run, the fixture-flag
                       # escape hatch must not survive into the caller's environment.
  [ "$rc" = 0 ] && printf 'OK (a11y-obligation: 9 legs; every surface glob derived+probed, every bracketed template stub cell probed, count-locked at %s rows)\n' "$A11Y_TEMPLATE_STUB_ROWS"
  return $rc
}

# dispatch — BELOW the selftest() definition so the function is defined before it is called
# (POSIX sh executes top-to-bottom; a forward reference to selftest fails with 'command not found').
# The non-vacuity marker is the selftest() line above, so the check-logic region (run_a11y_obligation)
# is still mutated; this dispatch sits after the marker and is emitted verbatim by the sweep.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
run_a11y_obligation "$@"; exit $?
