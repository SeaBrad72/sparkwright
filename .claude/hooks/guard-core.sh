#!/bin/sh
# guard-core.sh — runtime-agnostic deny-matrix (the SINGLE SOURCE OF TRUTH).
# Pure: no stdin parsing, no runtime-specific emit. Each check prints the "13: …"
# reason to STDOUT and returns 1 (deny); returns 0 (allow) with no output.
# Consumed by: .claude/hooks/guard.sh (Claude PreToolUse), hooks/pre-push (git),
# scripts/kit-guard (CLI). See docs/operations/runtime-guards.md.
# A SPEED BUMP, not a boundary — the real control is platform-owned
# (docs/enterprise/platform-safety-boundary.md). POSIX sh; no `local` (dash-clean).

selfedit_allowed() { [ "${KIT_GUARD_SELFEDIT:-0}" = "1" ]; }

# control-plane paths an agent must never silently modify (guard integrity + gates).
# scanner-config allowlists/ignores — an edit here can silently narrow a required gate (KW10):
# .gitleaks.toml / .gitleaksignore / .semgrepignore / .trivyignore / .checkov.yaml|.yml are
# enumerated in the case below (both bare + */-prefixed forms). Honest ceiling: this covers
# DEDICATED scanner-config files (path-matchable). Coverage thresholds embedded in SHARED
# multi-purpose files (pyproject.toml, .golangci.yml) are NOT path-matchable without blocking the
# whole file — that is a content-level problem, out of scope here.
# is_control_plane_path <path> — CASE-INSENSITIVE since A2. On a case-INSENSITIVE filesystem (the
# macOS default, and the kit's own development platform) `.Claude/hooks/guard-core.sh` resolves to the
# REAL guard while a byte-literal match classified it `ordinary` — so the guard could be edited out of
# the way by typing one capital letter, and the required §13 gate derived `ordinary` for it. Measured.
#
# STRICTLY FAIL-SAFE: folding can only ever ADD paths to the control-plane set, and no consumer treats
# a `true` verdict as a grant (guard_check_path denies, is_control_plane_target denies,
# promotion-readiness escalates). The cost is that a genuinely-distinct `Skills/` file on a
# case-SENSITIVE filesystem is now treated as control-plane — a guard prompt, never a bypass.
#
# HOT PATH: this runs on every PreToolUse, twice per path. The literal `case` below is tried FIRST and
# decides every all-lowercase path with zero subprocesses; only a path that actually contains an
# uppercase byte AND missed the literal match pays one `tr`. `LC_ALL=C` + the explicit `A-Z`/`a-z`
# ranges keep it byte-safe: under a Turkish locale `[:upper:]` maps I->ı, which would then fail to
# match `i` in the patterns.
#
# CEILING: closes CASE variance only. It does NOT close Unicode normalization (NFC/NFD) or homoglyphs —
# a related class, deliberately not claimed. Do not read this green as closing those.
# _fs_case_insensitive: is THIS filesystem case-insensitive? Probed ONCE and cached — the fold's cost
# and its false-positive risk both depend on the answer, and it cannot change mid-process. Uses `/tmp`
# (POSIX-required to exist) with `$HOME` as a fallback; no files are written. A Linux box that happens
# to have a real `/TMP` directory answers "insensitive" and simply folds more — the safe direction.
_kit_fs_ci=""
_fs_case_insensitive() {
  if [ -z "$_kit_fs_ci" ]; then
    _kit_fs_ci=0
    # PROBE THE TREE WE ARE JUDGING, not `/` or `$HOME`. An earlier draft tested `/tmp` vs `/TMP` with a
    # `$HOME` fallback, which answers for the WRONG VOLUME and is wrong in real setups: a repo on a
    # case-insensitive disk image or a `+F` casefold ext4 directory under a case-sensitive `/`, a Linux
    # container with a macOS bind mount, or a case-sensitive APFS volume mounted under a
    # case-insensitive `/`. In each the probe said "sensitive" while the variant genuinely resolved.
    # `.github` is present in this repo and in every incepted adopter, so it is a reliable in-tree
    # anchor; `$PWD` is the fallback for a caller running outside a kit tree. No files are written and
    # no env value steers the answer.
    for _kfd in "." ".."; do
      if [ -d "$_kfd/.github" ] && [ -d "$_kfd/.GITHUB" ]; then _kit_fs_ci=1; break; fi
    done
    if [ "$_kit_fs_ci" = 0 ] && [ -d "${PWD:-.}" ]; then
      _kfu=$(printf '%s' "${PWD:-.}" | LC_ALL=C tr 'a-z' 'A-Z')
      [ "$_kfu" != "${PWD:-.}" ] && [ -d "$_kfu" ] && _kit_fs_ci=1
    fi
  fi
  [ "$_kit_fs_ci" = 1 ]
}

# is_control_plane_path <path> — case-insensitive since A2, in TWO tiers.
#
# WHY TWO TIERS. Folding everything unconditionally was measured to break three SHIPPED profiles:
# `src/Adapters/Repo.cs`, `Adapters/Http/StripeAdapter.cs` and `Skills/Onboarding.cs` all derived
# control-plane, and PascalCase directories are the language convention in profiles/dotnet,
# profiles/java-spring and profiles/kotlin — `Adapters/` being the idiomatic ports-and-adapters folder.
# On a case-SENSITIVE filesystem (every CI runner) that is not a guard prompt but a MERGE BLOCK on an
# ordinary PR, clearable only with `--admin` — defeating §13 rather than enforcing it. The design's
# stated cost ("rare, and only a guard prompt") was wrong on both halves.
#
#   TIER 1 — kit-owned names, folded ALWAYS. `.claude/`, `.github/`, `.git/`, the ENUMERATED `.kit/`
#   confs (budget · roster · model-tiers · model-map · dials — a FILENAME enumeration, NOT a `.kit/`
#   directory prefix; the earlier wording claimed a prefix the patterns never implemented, which is
#   how `.kit/dials.conf` measured ORDINARY the day before it shipped), `codeowners`,
#   `claude.md`, `development-*.md`, the named scripts, the scanner-ignore files. Nobody names
#   application code `CLAUDE.md`, so there is no false-positive surface and these stay closed on EVERY
#   platform. This is the tier the real attacks used (`.Claude/hooks/guard-core.sh`, `Claude.md`).
#
#   TIER 2 — generic directory prefixes (`conformance/`, `skills/`, `adapters/`, `agents/`, `scripts/`),
#   folded ONLY on a case-insensitive filesystem. There the variant genuinely RESOLVES to the real
#   directory, which is what makes it dangerous; on a case-sensitive filesystem `Adapters/` is simply a
#   different directory and folding it would be a false positive with no corresponding risk.
#
# ⚠️ RESIDUAL, stated rather than hidden: a path committed on a case-SENSITIVE machine that would
# collide on a case-INSENSITIVE checkout is classified on the CI runner's filesystem, not the
# developer's. Tier 1 is unconditional precisely because that is where a cross-platform collision would
# actually matter; Tier 2's residual is a generic directory an adopter has deliberately named.
is_control_plane_path() {
  _cpp_match "$1" && return 0
  case "$1" in *[A-Z]*) : ;; *) return 1 ;; esac
  _cppf=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  _cpp_kitowned "$_cppf" && return 0
  _fs_case_insensitive && _cpp_match "$_cppf" && return 0
  return 1
}

# TIER 1 set — kit-owned, unambiguous, folded on every platform.
#
# ⚠️ THE LINE IS DRAWN AT FILENAME GRANULARITY, NOT DIRECTORY GRANULARITY. The first cut of this split
# put whole directories in Tier 2 (`skills/`, `conformance/`, `agents/`, `scripts/`) because
# `Skills/Onboarding.cs` and `src/Adapters/Repo.cs` are plausible adopter code. But the ambiguity is in
# the FILE, not the folder: no dotnet/java/kotlin adopter ships `Skills/review/SKILL.md`,
# `Agents/reviewer.agent.md`, `Conformance/verify.sh` or `Scripts/promotion-verify.sh`. Drawing the line
# at the directory left those classified ORDINARY on every Linux runner — a live §13 bypass (below) —
# while buying no false-positive protection they needed.
#
# THE BYPASS THIS CLOSES, measured: an attacker opens a PR adding `Skills/incident-response/SKILL.md`.
# On ubuntu-latest the class derived `ordinary`, `control-plane-ratification` posted GREEN "nothing to
# ratify", and it merged under an ordinary review. Git then checks a NEW file at a case-variant path
# out SILENTLY into the real directory on any case-insensitive clone — no collision warning, unlike an
# existing file (which warns, and whose real content wins because the lowercase path sorts later). So
# the attacker's file becomes a live agent-instruction surface carrying kit authority.
#
# `.claude/` IS A SEGMENT-ANCHORED FAMILY (GUARD-PATH-ENUMERATION-INCOMPLETE S1). It began as
# `guard.sh`/`guard-core.sh` by name, so every other file in the hook directory derived `ordinary` —
# measured: `.claude/hooks/entry-core.sh` -> ordinary, with Write, Edit and `sed -i` on it all ALLOWED.
# That was cured for `hooks/` with a directory prefix; the SAME hole then measured live one level up:
# `.claude/commands/*` and `.claude/plugins/*` both derived ordinary at 9d29406e (neither directory
# exists yet, which is exactly why no census over tracked files could see them). The whole directory is
# wired into settings.json as agent instrumentation, so ANY file in it is a live control-plane surface
# an agent could author unratified. The family is the fix the per-directory prefix was a down payment
# on: `.claude/*|*/.claude/*` — one rule, no list, and a sub-directory invented tomorrow is covered
# before it exists.
# THE ANCHOR IS THE POINT. `.claude/*|*/.claude/*` matches a full `.claude` PATH SEGMENT (at the start
# or after a `/`), NEVER `*.claude/...`: the loose form also matched any component merely ENDING in
# `.claude` — measured, `my.claude/hooks/x` and `src/mycompany.claude/hooks/z` both derived
# control-plane. Those are ordinary adopter files, and an unnecessary control-plane classification is
# an unnecessary ratification demand on an ordinary PR. The anchored family still captures a vendored
# `vendor/pkg/.claude/hooks/h.sh` and, via this tier's unconditional fold, `.Claude/Hooks/Entry.sh`.
# THE FOUR SIBLING `*.claude/...` PATTERNS ARE NOW GONE — deliberately, WITH the evidence the comment
# they replace demanded. `*.claude/settings.json` · `*.claude/settings.local.json` ·
# `*.claude/mcp-policy.json` · `*.claude/agents/*` each carried the identical `<x>.claude/...` false
# positive (measured: `my.claude/settings.json`, `my.claude/mcp-policy.json`, `my.claude/agents/x.md`
# all derived control-plane). The old note left them alone because narrowing four patterns on the file
# that decides what may be edited at all is its own change — "its own fixtures, its own monotonicity
# run, its own review". This slice IS that change: the sibling-relief ALLOW fixtures on BOTH routes and
# the corner-spelling DENY fixtures live in conformance/agent-autonomy.sh, the fold-monotonicity sweep
# runs over synthetic never-tracked family paths in promotion-readiness-wired.sh, and the pathhit
# `.claude` leg is re-anchored in the same commit so the relief is not route-split.
# ⚠️ COVERAGE WIDENS ONE STEP with the family: files sitting DIRECTLY in `.claude/` (`.claude/README.md`,
# `.claude/settings.local.json`) are control-plane now where the enumeration reached only four names.
# That is the intended direction — everything in the agent's own instrumentation directory is governing
# — and it is fail-SAFE (a ratification demand, never a missed one). Fixtures record it explicitly so
# it reads as a decision, not as drift.
# ⚠️ THE RELIEF ARM BELOW IS FIRST ON PURPOSE, AND IT IS THE ONLY HOLE IN THE `.claude/` FAMILY.
# GUARD-CLAUDE-HOME-INSTRUMENTATION-FP (design docs/architecture/2026-08-17-guard-claude-home-fp-design.md).
# The family above is segment-anchored, so `*/.claude/*` matches ANY absolute path carrying a
# `/.claude/` segment — including the agent harness's OWN home directory. Measured 2026-08-17, minutes
# after S1 shipped: `~/.claude/projects/<p>/memory/*.md` (persistent agent memory) and
# `~/.claude/plans/*.md` (plan mode) were guard-DENY on both the Edit and Write tool routes, which
# broke the standing memory directive and plan mode in EVERY session wherever this hook is wired.
# Those two subtrees are the agent's WORKSPACE, not its instrumentation. Everything else under
# `.claude/` — settings.json, settings.local.json, mcp-policy.json, hooks/, agents/, commands/,
# plugins/, skills/, workflows/, CLAUDE.md, statusline-command.sh (which the harness EXECUTES), and
# every name invented tomorrow — stays family-denied: those are the user-level halves of the exact
# permission surfaces PERMISSION-LOCAL-ACCRETION-SIGNAL monitors, and the categorical owner-keystroke
# bright line. `tasks/`/`todos/` are deliberately NOT relieved: each addition is its own ratified
# control-plane change, which is the correct friction direction.
# POSIX `case` is FIRST-MATCH-WINS, so this arm must precede the family arm or it is inert.
# ⚠️ IT MUST BE ADDED TO **BOTH** TIERS ATOMICALLY. Tier 1 ⊆ Tier 2 is the fold's soundness
# invariant: relieving only here would leave Tier 1 NARROWER (harmless) while relieving only in
# `_cpp_match` would leave Tier 1 BROADER — manufacturing control-plane-ness on the folded spelling.
# A one-sided WIDENING confined to `_cpp_kitowned` is caught on every filesystem only by the
# BRIGHTLINE-T1 predicate in conformance/promotion-readiness-wired.sh; a one-sided RELIEF in either
# direction is caught by the relief ALLOW legs, the case-variant one FS-independently.
# WHY THE RELIEF HALF NEEDS NO STRUCTURAL LEG (measured, and an earlier draft of this comment claimed
# otherwise): once `_cpp_kitowned` returns 0 the wrapper returns control-plane IMMEDIATELY — the
# conditional Tier-2 re-check below it never runs — so a relief missing from Tier 1 turns the
# case-variant subject `…/.CLAUDE/PLANS/x.md` control-plane on a case-INSENSITIVE host too, not just
# on CI. The WIDENING half is the genuinely FS-dependent one (vet C2): a widened Tier 1 hands the
# subject back to that same re-check, which still denies on macOS, so it dies only on CI at the
# verdict level — which is what BRIGHTLINE-T1 exists to cover.
# ⚠️ THE RELIEF IS CLASSIFIER-ONLY, BY OWNER RULING (design §3, C1 = option (b)). The `_CP8B_PATHHIT_*`
# regex legs deny DIRECTLY without ever consulting this function, so a non-read-verb shell spelling
# (`sed -i`, `tee`, an interpreter's `open(...)`) aimed at a relieved name STILL denies. That is a
# DISCLOSED RETAINED FALSE POSITIVE, fixtured in conformance/agent-autonomy.sh — the broken workflows
# use the tool route exclusively, and this keeps the guard's hottest deny leg byte-untouched.
# ⚠️ TWO FACES DISCLOSED RATHER THAN DISCOVERED: (i) the arm returns EARLY, so a family name nested
# UNDER a relieved one (`.claude/projects/x/hooks/pre-push`) classifies ordinary — pinned as a
# recorded decision, not drift; (ii) the relief is by subtree NAME, not location, so a repo that
# TRACKED these subtrees would derive `ordinary` at `promotion-readiness --class` and merge without
# control-plane ratification (pinned in promotion-readiness-wired.sh). $HOME-anchored patterns were
# rejected as the alternative: env-dependent matching is the worse failure mode.
_cpp_kitowned() {
  case "$1" in
    .claude/projects/*|*/.claude/projects/*|.claude/plans/*|*/.claude/plans/*) return 1 ;;
    .claude/*|*/.claude/*|\
    */.github/workflows/*|.github/workflows/*|*/.git/*|.git/*|\
    .kit/budget.conf|*/.kit/budget.conf|.kit/roster.conf|*/.kit/roster.conf|\
    .kit/model-tiers.conf|*/.kit/model-tiers.conf|.kit/model-map.conf|*/.kit/model-map.conf|\
    .kit/dials.conf|*/.kit/dials.conf|\
    .kit/ratification-seats.conf|*/.kit/ratification-seats.conf|\
    codeowners|*/codeowners|claude.md|*/claude.md|\
    development-standards.md|*/development-standards.md|\
    development-process.md|*/development-process.md|\
    agents.md|*/agents.md|\
    required-checks.md|*/required-checks.md|\
    .gitattributes|*/.gitattributes|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    .gitleaks.toml|*/.gitleaks.toml|.gitleaksignore|*/.gitleaksignore|\
    .semgrepignore|*/.semgrepignore|.trivyignore|*/.trivyignore|\
    .checkov.yaml|*/.checkov.yaml|.checkov.yml|*/.checkov.yml|\
    docs/governance/.meta-control-last|*/docs/governance/.meta-control-last|\
    docs/governance/meta-control-log.md|*/docs/governance/meta-control-log.md|\
    conformance/*.sh|*/conformance/*.sh|\
    skills/*/skill.md|*/skills/*/skill.md|\
    agents/*.agent.md|*/agents/*.agent.md|\
    scripts/incept.sh|*/scripts/incept.sh|scripts/dora.sh|*/scripts/dora.sh|\
    scripts/agent-scorecard.sh|*/scripts/agent-scorecard.sh|\
    scripts/agent-trace.sh|*/scripts/agent-trace.sh|\
    scripts/escalate.sh|*/scripts/escalate.sh|\
    scripts/coverage-ratchet.sh|*/scripts/coverage-ratchet.sh|\
    scripts/license-check.sh|*/scripts/license-check.sh|\
    scripts/preflight.sh|*/scripts/preflight.sh|\
    scripts/new-adapter.sh|*/scripts/new-adapter.sh|\
    scripts/new-profile.sh|*/scripts/new-profile.sh|\
    scripts/doctor.sh|*/scripts/doctor.sh|\
    scripts/postmortem.sh|*/scripts/postmortem.sh|\
    scripts/tier-advice.sh|*/scripts/tier-advice.sh|\
    scripts/sparkwright|*/scripts/sparkwright|\
    scripts/containment-audit.sh|*/scripts/containment-audit.sh|\
    scripts/sod-check.sh|*/scripts/sod-check.sh|\
    scripts/model-tier.sh|*/scripts/model-tier.sh|\
    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\
    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\
    scripts/release-tag.sh|*/scripts/release-tag.sh|\
    scripts/promotion-verify.sh|*/scripts/promotion-verify.sh|\
    adapters/*/adapter.json|*/adapters/*/adapter.json|\
    conformance/claims.tsv|*/conformance/claims.tsv|\
    conformance/aggregate-exclusions.txt|*/conformance/aggregate-exclusions.txt|\
    conformance/incept-manifests/*|*/conformance/incept-manifests/*|\
    conformance/fixtures/*|*/conformance/fixtures/*|\
    scripts/fixtures/*|*/scripts/fixtures/*)
      return 0 ;;
  esac
  return 1
}

# ⚠️ TIER 1 MUST BE A STRICT SUBSET OF _cpp_match. The fold's only sound invariant is
#   is_control_plane_path(p)  =>  is_control_plane_path(tolower(p))
# i.e. folding may only ever PRESERVE control-plane-ness, never CREATE it. An earlier draft listed
# `*.claude/*` and `*/.github/*` here while `_cpp_match` carried only `.github/workflows/*` and five
# specific `.claude/` files — so Tier 1 was BROADER than the set it folds and manufactured new
# classifications. Measured over all tracked files: `.github/ISSUE_TEMPLATE/*`,
# `.github/PULL_REQUEST_TEMPLATE.md` and `.claude/README.md` flipped ordinary -> control-plane on EVERY
# platform. Those are GitHub's own uppercase conventions, present in near-every adopter, so a PR editing
# a bug-report template demanded non-author ratification — the merge block this whole split exists to
# avoid, arriving through the tier that was supposed to be the safe one.
# `conformance/invariant-fold-monotone` (promotion-readiness-wired.sh) now asserts the invariant over
# every tracked path, because it is a PROPERTY, not an example — an anchor list cannot catch this.
# ⚠️ THE TRACKED-FILE CENSUS IS BLIND WHERE THIS SLICE WORKS. `scripts/zz-*`, `.claude/commands/*`,
# `profiles/zz-*` are not tracked (two of those directories do not exist at all), so a sweep over
# `git ls-files` says nothing about them. The invariant is therefore ALSO asserted over synthetic,
# never-tracked family paths — same check, explicit list — or the subset relation would be proven
# only where it was never in doubt.

# The pattern set, LOWERCASED. Both sides of the comparison are folded — the subject by the wrapper
# above, the patterns here at authoring time. ⚠️ Every pattern in this list MUST stay lowercase: a
# pattern carrying an uppercase byte can never match a folded subject, which would SILENTLY DECLASSIFY
# it. That is not hypothetical — the first draft of this change kept `CODEOWNERS`, `CLAUDE.md`,
# `DEVELOPMENT-STANDARDS.md` and `DEVELOPMENT-PROCESS.md` byte-identical and turned all four `ordinary`.
# The `.claude/*` family is the IDENTICAL segment-anchored form Tier 1 carries (see the note above
# `_cpp_kitowned`, which records the measurements behind it): Tier 1 must stay a strict subset of this
# set, so the two patterns are kept byte-identical rather than merely equivalent.
#
# GUARD-PATH-ENUMERATION-INCOMPLETE S1 — THE DIRECTORY FAMILIES LIVE HERE, AND ONLY HERE.
# `scripts/*|*/scripts/*` and `profiles/*|*/profiles/*` join `conformance/`, `skills/` and `adapters/`
# in TIER 2 — deliberately NOT in `_cpp_kitowned`. Tier 1 folds on EVERY platform, so a generic
# `scripts/` prefix there would fold `src/Scripts/Deploy.cs` into control-plane on case-SENSITIVE
# Linux and reinstate the exact false-positive class the tier split was built to close (the same
# measurement that produced `src/Adapters/Repo.cs` and `Skills/Onboarding.cs`). Tier 1 keeps its
# per-NAME script entries as the unambiguous-filename floor; because the family lives only here, the
# "Tier 1 ⊆ Tier 2" invariant above stops being self-satisfied and becomes a real proof.
# WHY A FAMILY AT ALL: `scripts/` was protected per-file (~20 names), and the class demonstrated itself
# live — `scripts/branch-protection-apply.sh` was born 2026-08-06 outside the hand list and was
# guard-writable and mergeable as `ordinary` for ten days. `profiles/` carries the enforcement-bearing
# surfaces an adopter's CI actually runs (`adopter-gates.yml`, `ratification.yml`, per-stack `ci.yml`,
# `BRANCH-PROTECTION.md`), and any curated sub-list inside it would be the same defect reborn.
# The DEEP arm (`*/scripts/*`, `*/profiles/*`) SHIPS on measurement, not on taste: `git archive HEAD`
# retains 403 `profiles/` paths (no export-ignore entry) and `scripts/incept.sh` §5a4 keeps
# `profiles/<STACK>/`, `ratification.yml` and `adopter-gates.yml`, so incepted adopter trees carry a
# real `profiles/` root; the arm also catches the 14 tracked `profiles/*/scaffold/scripts/*` files.
# ⚠️ DISCLOSED, NOT DISCOVERED LATER: "scripts" and "profiles" are far commoner directory names in an
# adopter app tree than conformance/skills/adapters, so `frontend/scripts/build.js` and
# `src/profiles/user.ts` become guard-DENY in ANY adopter tree where this hook is wired (byte-literal
# on every platform — the case-conditioning only ever protects case-VARIANT spellings). Fail-safe by
# direction, and the price is stated rather than waved at: ~37 profiles-touching commits/month
# measured on the kit itself, all of which become dev-clone + ratification work.
# ⚠️ THERE IS NO "OBSERVE MODE" ON THIS ROUTE, AND AN EARLIER DRAFT OF THIS COMMENT SAID OTHERWISE.
# `LOOP_STATE_MODE` softens the CI class/loop-state route ONLY. This file has no mode knob of any
# kind, and `.claude/` ships in the adopter export — so wherever the PreToolUse hook is wired, these
# denies are UNCONDITIONAL from the first tool call. "Observe-mode adopters see advisories, not
# blocks" was false here and is the kind of softener that turns a disclosed cost into a surprise.
# The per-name `scripts/*.sh` entries below are now SUBSUMED by the family. They are kept, not pruned:
# they are the byte-identical mirror of Tier 1's floor, and deleting entries from the list that decides
# what may be edited at all is a change that would need its own evidence — not a tidy-up.
# THE CURATED ROOT ADDITIONS, with the property named. `agents.md` (the roster-authority floor; the
# file `incept` renames into the adopter's governing doc), `required-checks.md` (binds which CI
# contexts block merge — the same enforcement-bearing class), and `.gitattributes` AT EVERY DEPTH
# (`git archive` honors it per-directory, so a nested `docs/.gitattributes` flipping `export-ignore`
# carries the identical export-control property; root-only would have been incomplete). `.gitignore` is
# deliberately EXCLUDED — untracked files never export, so the property does not cover it.
# ⚠️ HONEST CEILING: root-level governing files are NOT structurally derivable. This stays a curated
# list, and a NEW root governing file still needs a list edit. The compensating detection is a
# guard-vs-class census lock (S2), which is where "the list drifted" becomes a red instead of a probe
# finding. Do not read the families above as covering this row.
# THE HOME-INSTRUMENTATION RELIEF ARM IS MIRRORED HERE, BYTE-IDENTICALLY, AND FIRST
# (GUARD-CLAUDE-HOME-INSTRUMENTATION-FP — the full rationale sits above `_cpp_kitowned`, where the
# same arm leads Tier 1). Kept byte-identical rather than merely equivalent, exactly as the
# `.claude/*` family patterns are, because Tier 1 ⊆ Tier 2 is asserted structurally and a relief
# present in only one tier is the failure mode that check exists to catch. `case` is
# first-match-wins: this arm must precede the family arm below or it is inert.
_cpp_match() {
  case "$1" in
    .claude/projects/*|*/.claude/projects/*|.claude/plans/*|*/.claude/plans/*) return 1 ;;
    .claude/*|*/.claude/*|\
    docs/governance/.meta-control-last|*/docs/governance/.meta-control-last|\
    docs/governance/meta-control-log.md|*/docs/governance/meta-control-log.md|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    */.github/workflows/*|.github/workflows/*|*/codeowners|codeowners|*/.git/*|.git/*|\
    .gitleaks.toml|*/.gitleaks.toml|.gitleaksignore|*/.gitleaksignore|\
    .semgrepignore|*/.semgrepignore|.trivyignore|*/.trivyignore|\
    .checkov.yaml|*/.checkov.yaml|.checkov.yml|*/.checkov.yml|\
    conformance/*|*/conformance/*|adapters/*|*/adapters/*|\
    skills/*|*/skills/*|\
    scripts/*|*/scripts/*|\
    profiles/*|*/profiles/*|\
    agents.md|*/agents.md|\
    required-checks.md|*/required-checks.md|\
    .gitattributes|*/.gitattributes|\
    scripts/fixtures/*|*/scripts/fixtures/*|\
    scripts/incept.sh|*/scripts/incept.sh|scripts/dora.sh|*/scripts/dora.sh|\
    scripts/agent-scorecard.sh|*/scripts/agent-scorecard.sh|\
    scripts/agent-trace.sh|*/scripts/agent-trace.sh|\
    scripts/escalate.sh|*/scripts/escalate.sh|\
    scripts/coverage-ratchet.sh|*/scripts/coverage-ratchet.sh|\
    scripts/license-check.sh|*/scripts/license-check.sh|\
    scripts/preflight.sh|*/scripts/preflight.sh|\
    scripts/new-adapter.sh|*/scripts/new-adapter.sh|\
    scripts/new-profile.sh|*/scripts/new-profile.sh|\
    scripts/doctor.sh|*/scripts/doctor.sh|\
    scripts/postmortem.sh|*/scripts/postmortem.sh|\
    scripts/tier-advice.sh|*/scripts/tier-advice.sh|\
    scripts/sparkwright|*/scripts/sparkwright|\
    scripts/containment-audit.sh|*/scripts/containment-audit.sh|\
    scripts/sod-check.sh|*/scripts/sod-check.sh|\
    .kit/budget.conf|*/.kit/budget.conf|\
    .kit/roster.conf|*/.kit/roster.conf|\
    .kit/model-tiers.conf|*/.kit/model-tiers.conf|\
    .kit/model-map.conf|*/.kit/model-map.conf|\
    .kit/dials.conf|*/.kit/dials.conf|\
    .kit/ratification-seats.conf|*/.kit/ratification-seats.conf|\
    scripts/model-tier.sh|*/scripts/model-tier.sh|\
    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\
    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\
    scripts/release-tag.sh|*/scripts/release-tag.sh|\
    scripts/promotion-verify.sh|*/scripts/promotion-verify.sh|\
    agents/*.agent.md|*/agents/*.agent.md|\
    development-standards.md|*/development-standards.md|\
    development-process.md|*/development-process.md|\
    claude.md|*/claude.md)
      return 0 ;;
  esac
  return 1
}

# --- CP-8c: dev-clone affordance ----------------------------------------------------
# _resolve_physical "<path>": echo the physical (symlink-resolved) absolute path. Resolves the
# DEEPEST EXISTING ancestor with `cd … && pwd -P` (collapsing `..`, symlinks, the macOS
# /tmp->/private/tmp landmine) and re-appends the not-yet-existing tail.
# SUBPROCESSES: `pwd -P` (CP-4's sanctioned one), plus `readlink` for the leaf loop below and `tr`
# in _under_temp's folded arm — both added 2026-08-01 by GUARD-PATH-ALIAS-BYPASS. The earlier
# "`pwd -P` is the one sanctioned subprocess" wording is superseded; leaving it would have been a
# false certification of the same shape as the cp/hardlink one this slice also corrects. Both new
# calls fail SAFE: an absent `readlink` returns 127 => `return 1` => callers deny.
# ⚠️ It resolves the physical PARENT plus a symlink-resolved leaf — it does NOT detect HARDLINKS
# (a hardlink has no link to follow; see GUARD-CP-HARDLINK-ALIAS).
_resolve_physical() {
  _rp=$1
  case "$_rp" in /*) : ;; *) _rp="$(pwd)/$_rp" ;; esac
  # GUARD-PATH-ALIAS-BYPASS (P0): resolve a symlinked LEAF. The ancestor walk below never examines
  # the final component, so a one-symlink leaf named innocuously reached any target unseen. Bounded
  # at 64: SYMLOOP_MAX is 32 here, so exhaustion means adversarial, never deep-but-legitimate.
  # Exit on "still a symlink" rather than on the counter, so a legitimate chain of exactly 64 that
  # DID resolve is not refused. A relative target resolves against the LINK's own directory; `..`
  # inside a target is left to `cd -P` and never collapsed textually. Failure => rc 1 => callers deny.
  _n=0
  while [ -L "$_rp" ] && [ "$_n" -lt 64 ]; do
    _t=$(readlink "$_rp") || return 1
    case "$_t" in /*) _rp=$_t ;; *) _rp="$(dirname "$_rp")/$_t" ;; esac
    _n=$((_n+1))
  done
  [ -L "$_rp" ] && return 1
  [ "$_rp" = / ] && { printf '/'; return 0; }   # degenerate root; avoids a `//` result
  _rpd=$(dirname "$_rp"); _rpb=$(basename "$_rp"); _rps=$_rpb
  while [ ! -d "$_rpd" ]; do
    _rpb=$(basename "$_rpd"); _rpd=$(dirname "$_rpd"); _rps="$_rpb/$_rps"
    [ "$_rpd" = "/" ] && break
  done
  # `cd` (logical) canonicalises `..` against the path STRING before chdir, so a `..` following a
  # symlink erases the symlink instead of following it — the original P0. `-P` chdirs physically.
  _rpp=$(CDPATH='' cd -P "$_rpd" 2>/dev/null && pwd -P) || return 1
  if [ "$_rpp" = / ]; then printf '/%s' "$_rps"; else printf '%s/%s' "$_rpp" "$_rps"; fi
}

# _under_temp "<physical_path>": 0 iff the path is under a HARDCODED temp root. The set is FIXED
# and never read from $TMPDIR — reading an env var to WIDEN "disposable temp" is the fail-open
# direction (a poisoned TMPDIR=$HOME would relax ~/.claude). Covers Linux /tmp, macOS
# /private/tmp, and the macOS per-user temp (resolved: /private/var/folders/*/T/).
_under_temp() {
  case "$1/" in
    /tmp/*|/private/tmp/*|/var/folders/*/T/*|/private/var/folders/*/T/*) return 0 ;;
  esac
  # GUARD-UNDER-TEMP-CASE: a case-folded SECOND arm, never a replacement. Folding only the subject
  # against the list above would make its literal uppercase `T` unmatchable — and since a bare
  # `mktemp -d` yields /var/folders/…/T/… on macOS, every dev-clone would stop relaxing while Linux
  # CI (TMPDIR unset => /tmp) stayed green. Arm 1 is byte-identical to before and returns first, so
  # this can only ever ADD a temp match. The short-circuit keeps the hot path subprocess-free —
  # but with an EXPLICIT set, not `[A-Z]`: under a UTF-8 locale bash's range collation matches
  # lowercase too, so `[A-Z]` fires on every path and spawns the very subprocess it exists to avoid.
  # Measured — bash-as-/bin/sh matched "/tmp/foo"; dash did not. (Line 90 carries the same latent
  # issue in a colder path; left alone here to keep this slice's diff to its own subject.)
  case "$1" in *[ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) : ;; *) return 1 ;; esac
  _ut=$(printf '%s/' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  case "$_ut" in
    /tmp/*|/private/tmp/*|/var/folders/*/t/*|/private/var/folders/*/t/*) return 0 ;;
  esac
  return 1
}

# guard_dev_clone_relaxable "<path>" "<protected_root>": return 0 IFF a control-plane edit to
# <path> is safe to relax. THREE conditions, all physically resolved:
#   1. <path> is UNDER a (hardcoded) temp root, AND
#   2. <path> is OUTSIDE the protected repo root, AND
#   3. the protected root is NOT itself under temp.
# Condition 3 is load-bearing: when the protected tree is itself disposable (the mktemp'd export,
# a CI checkout), a path escaping the root lands as a temp-SIBLING that satisfies 1+2 — condition 3
# disables the affordance there, where there is no live control plane to protect anyway. A real
# repo (~/Development/…) is never under temp, so the dev-clone case is unaffected.
# Empty protected_root => 1 (fail-safe). A surviving `..` in the resolved path => 1 (an unresolved
# tail that could escape back into root). Only the CALLER (guard_check_path) uses this, only to skip
# the control-plane deny — never the secret or destructive denies.
guard_dev_clone_relaxable() {
  _dp=$1; _droot=$2
  [ -n "$_droot" ] || return 1
  _dphys=$(_resolve_physical "$_dp") || return 1
  _drootp=$(_resolve_physical "$_droot") || return 1
  [ -n "$_dphys" ] && [ -n "$_drootp" ] || return 1
  # GUARD-PATH-ALIAS-BYPASS (P0): this predicate is the one that turns control-plane denies OFF, so
  # it takes the CONJUNCTION — the LITERAL path must qualify too, not just the resolved one.
  # Without it, leaf resolution carries an inside-root control-plane path out to temp, all three
  # resolved-side conditions hold, and DENY flips to ALLOW. $_dp arrives RAW (:303) — absolutise and
  # collapse `..` (the same fixpoint guard_check_path uses) or relative spellings sail past.
  # NOT `|| is_control_plane_path "$_dp"`: _cp8c_relax is only read where that is already true, so
  # the disjunct would be unconditionally true and disable the affordance entirely (measured).
  _dpa=$_dp
  case "$_dpa" in /*) : ;; *) _dpa="$(CDPATH='' pwd -P)/$_dpa" ;; esac
  _dpa=$(printf '%s' "$_dpa" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta')
  case "$_drootp" in /) return 1 ;; esac              # degenerate root: `//*` matches nothing
  case "$_dpa/" in "$_drootp"/*) return 1 ;; esac     # literal inside the root => never relax
  # The literal must ALSO be under temp. When it is not but the RESOLVED path is, the caller was
  # addressing a genuine clone through a symlink from outside temp — a legitimate workflow that used
  # to work. Flag it so guard_check_path can name the real-path remedy instead of falling through to
  # the generic control-plane reason, whose only signposted escape is the global kill switch.
  if ! _under_temp "$_dpa"; then
    # Only promise the real-path remedy when that spelling would GENUINELY relax — i.e. when the
    # affordance's OTHER conditions already hold: the root must not itself be under temp (condition
    # 3), the resolved path must be outside the root (condition 2), and must carry no surviving
    # `..`. Without these the message sends the operator to a spelling that also denies, and THAT
    # denial's only signpost is the global kill switch — the endorsed-bypass class, one hop out.
    if _under_temp "$_dphys" && ! _under_temp "$_drootp"; then
      case "/$_dphys/" in
        *"/../"*) : ;;
        *) case "$_dphys/" in
             "$_drootp"/*) : ;;
             *) _cp8c_hint=symlinked-clone ;;
           esac ;;
      esac
    fi
    return 1
  fi
  case "/$_dphys/" in *"/../"*) return 1 ;; esac
  _under_temp "$_drootp" && return 1          # condition 3: disposable root => affordance off
  case "$_dphys/" in "$_drootp"/*) return 1 ;; esac  # condition 2: must be outside root
  _under_temp "$_dphys" && return 0           # condition 1: target under temp
  return 1
}

# =============================================================================================
# GUARD-CP-HARDLINK-ALIAS — the guard resolves SYMLINKS but not HARDLINKS. A hardlink is a second
# directory entry for one inode; there is no link to follow, so a benign-named hardlink's resolved
# path IS the benign name and every union arm (literal ∨ normalised ∨ resolved) passes it. This adds
# a RESOLVED-INODE disjunct to the same unions: if the resolved target shares its inode with a
# control-plane or secret file reached by a different directory entry, it writes/reads THAT file, and
# the name it is reached by does not change what it touches. (design 2026-08-18-guard-cp-hardlink-alias)
# =============================================================================================

# _is_secret_path "<path>" — the ONE source of truth for "is this a secret filename". Reproduces the
# two arms every direct secret site carries: the byte-literal glob AND the case-folded arm (a
# case-variant .ENV/.PEM on a case-insensitive filesystem reaches the same inode). Consolidated here
# (GUARD-CP-HARDLINK-ALIAS §2c) from the eight inlined copies so the pattern cannot drift; the coupling
# selftest in agent-autonomy.sh pins the alternation string byte-identical. The TEMPLATE allowlist is
# deliberately NOT folded in — it stays byte-literal at each call site (never fold an allow matcher).
_is_secret_path() {
  case "$1" in
    *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*) return 0 ;;
  esac
  case "$1" in *[A-Za-z]*)
    _isp=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
    case "$_isp" in
      *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*) return 0 ;;
    esac ;;
  esac
  return 1
}

# _is_secret_hit "<path>" — the secret classifier the INODE check uses. Same as _is_secret_path but
# with the TEMPLATE-NAME EXEMPTION (BUILD CONDITION A, vet round 2): the inode wrapper has no allowlist
# in front of it, so without this a hardlinked `.env.example` whose only sibling is a benign file would
# self-classify (its own returned name `.env.example` matches `*.env.*`) and over-deny every write/read
# to a legitimate hardlinked template. A find-returned name that IS a template name does not count as a
# secret hit; the cloak still denies because the REAL `.env` sibling is a non-template secret.
_is_secret_hit() {
  case "$(basename "$1" 2>/dev/null || printf '%s' "$1")" in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
  esac
  _is_secret_path "$1"
}

# _nlink_of "<path>" — echo the target's hard-link count; rc 1 (echo nothing) when it cannot be a
# number. BSD (`stat -f '%l'`, darwin) vs GNU (`stat -c '%h'`) branch: GNU form tried first because
# BSD stat rejects `-c` (measured: "illegal option -- c"), while GNU stat's `-f` means --file-system
# (a different datum), so the order matters. ⚠️ BUILD MANDATE (vet, HIGH): parse with the
# DECLINE-ON-NON-DIGIT negated-class idiom — an empty/absent/non-digit count routes to fail-safe (the
# caller treats rc 1 as "cannot count => run find / deny"), NEVER to a head-anchored positive match
# that would let ""/"x" slip to the nlink==1 ALLOW.
_nlink_of() {
  _nl=$(stat -c '%h' "$1" 2>/dev/null) || _nl=$(stat -f '%l' "$1" 2>/dev/null) || _nl=''
  case "$_nl" in ''|*[!0-9]*) return 1 ;; esac   # decline-on-non-digit (vet BUILD MANDATE)
  printf '%s' "$_nl"
}

# _devino_of "<path>" — echo "<device> <inode>" (both decimal); rc 1 on any non-"digits SP digits".
# Same BSD/GNU branch and the same decline-on-non-digit discipline as _nlink_of.
_devino_of() {
  _di=$(stat -c '%d %i' "$1" 2>/dev/null) || _di=$(stat -f '%d %i' "$1" 2>/dev/null) || _di=''
  case "$_di" in
    *[!0-9\ ]*|''|*' '*' '*) return 1 ;;   # exactly two space-separated digit fields
  esac
  case "$_di" in *' '*) : ;; *) return 1 ;; esac
  printf '%s' "$_di"
}

# _hl_physical_home — echo the PHYSICALLY-resolved $HOME (rc 1 + empty when $HOME is unset/unreadable).
# ⚠️ H1 (reviewer, round 3): the cap MUST compare the PHYSICAL $HOME, not the raw env string. A
# symlinked $HOME (e.g. HOME=/tmp/homelink -> /private/tmp/fakehome) never prefix-matches a
# physically-resolved candidate, so a raw-env compare silently misses and reopens the `find $HOME` DoS.
_hl_physical_home() { CDPATH= cd "${HOME:-/}" 2>/dev/null && pwd -P; }

# _hl_at_or_above_home "<physical-path>" — rc 0 iff <physical-path> IS $HOME or an ancestor of $HOME
# (then "$HOME/" glob-matches "$path"/*). Used to CAP both the derived AND the passed root (LOW-1):
# a repo rooted at/above $HOME would scope a home-or-wider find. Empty/unreadable home => rc 1 (no cap).
_hl_at_or_above_home() {
  _hah_home=$(_hl_physical_home) || return 1
  [ -n "$_hah_home" ] || return 1
  case "$_hah_home/" in "$1"/*) return 0 ;; esac
  return 1
}

# _hlink_repo_root "<path>" — derive the NEAREST ancestor of <path> containing .git or .claude
# (GUARD-CP-HARDLINK-ALIAS §2d). ONLY reached when no protected root was PASSED (kit-guard CLI, older
# adapters, and — until MEDIUM-1 threaded it — the read side); when a root is passed, that
# authoritative, unsteerable value is used directly.
# ⚠️ NEAREST, and CAPPED STRICTLY BELOW the PHYSICAL $HOME (H1). The earlier OUTERMOST climb was a DoS:
# `~/.claude` EXISTS on a real machine, so for a repo under `~` the outermost ancestor became $HOME and
# `find $HOME -inum` walked the ENTIRE home directory on the highest-frequency tool path. So: return
# the NEAREST `.git`/`.claude` ancestor, and NEVER $HOME, any ancestor at/above $HOME, or `/`. If the
# nearest boundary IS $HOME, or the walk reaches $HOME/`/` with no repo boundary strictly below,
# derivation FAILS (rc 1) → the engine fail-safes to a HIT (deny) for that one nlink>1 target.
_hlink_repo_root() {
  _hrr=$1
  case "$_hrr" in /*) : ;; *) _hrr="$(pwd)/$_hrr" ;; esac
  _hrhome=$(_hl_physical_home) || _hrhome=''
  _hrd=$(dirname "$_hrr")
  while : ; do
    case "$_hrd" in /) return 1 ;; esac                       # reached / with no boundary => fail
    if [ -n "$_hrhome" ]; then
      # A candidate that IS $HOME or an ancestor of $HOME is disqualified — BEFORE the boundary test,
      # so a repo at/above $HOME never scopes a home-or-wider find. Strictly-below or outside passes.
      case "$_hrhome/" in "$_hrd"/*) return 1 ;; esac
    fi
    if [ -e "$_hrd/.git" ] || [ -d "$_hrd/.claude" ]; then printf '%s' "$_hrd"; return 0; fi
    _hrd=$(dirname "$_hrd")
  done
}

# _hl_find_inode "<root>" "<ino>" — echo the names sharing <ino> under <root> (standard prune),
# guarded by a fail-safe WATCHDOG (reviewer I1, the durable class-closer). If the find exceeds
# KIT_HL_FIND_BUDGET seconds it is KILLED and this returns rc 1 (=> the engine fail-safes to a
# HIT/deny). `timeout(1)` is not portable (absent on macOS), so: the find runs in the background
# writing a trap-cleaned temp file; a DISARM-FLAG watchdog kills it on expiry and can never kill a
# REUSED pid (it checks the flag first). Any orphaned `sleep` self-terminates and finds its flag gone.
_hl_find_inode() {
  _hlf_root=$1; _hlf_ino=$2
  _hlf_tmp=$(mktemp 2>/dev/null) || return 1
  _hlf_arm="$_hlf_tmp.arm"; : > "$_hlf_arm" 2>/dev/null || { rm -f "$_hlf_tmp"; return 1; }
  # ⚠️ Both background jobs MUST detach ALL inherited fds (</dev/null >/dev/null 2>&1). This engine is
  # itself run inside a `$(...)` capture by the caller; a backgrounded job that inherits the capture's
  # stdout pipe holds it open, so `$(...)` blocks for the FULL budget even when find returns instantly
  # (measured: ~10s per check). find writes to its own temp file; the watchdog talks to no one.
  find "$_hlf_root" -xdev \
      \( -type d \( -path '*/.git/objects' -o -path '*/.git/lfs' -o -name node_modules \) \) -prune \
      -o -inum "$_hlf_ino" -print > "$_hlf_tmp" 2>/dev/null </dev/null &
  _hlf_fpid=$!
  ( sleep "${KIT_HL_FIND_BUDGET:-10}" 2>/dev/null; [ -f "$_hlf_arm" ] && kill "$_hlf_fpid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  _hlf_wpid=$!
  if wait "$_hlf_fpid" 2>/dev/null; then _hlf_rc=0; else _hlf_rc=1; fi   # non-zero (error OR kill) => fail-safe
  rm -f "$_hlf_arm"                          # DISARM: an orphaned sleep now finds the flag gone (no PID-reuse kill)
  kill "$_hlf_wpid" 2>/dev/null || :         # best-effort reap of the watchdog subshell
  wait "$_hlf_wpid" 2>/dev/null || :
  if [ "$_hlf_rc" -eq 0 ]; then cat "$_hlf_tmp" 2>/dev/null; rm -f "$_hlf_tmp"; return 0; fi
  rm -f "$_hlf_tmp"; return 1
}

# _hardlink_alias_hit "<resolved>" "<root>" "<classifier-fn>" — the engine. Returns rc 0 in TWO cases,
# both of which the caller treats as a HIT (deny): a GENUINE hit echoes the (sanitized) offending path;
# a FAIL-SAFE hit echoes NOTHING (empty). rc 1 = no alias (ALLOW), echoes nothing. So the caller
# denies on rc 0 and picks its reason by whether the echoed name is non-empty (M1 — a DISTINCT
# fail-safe reason, true for what may be an ordinary file). Fail-safe fires on any tooling anomaly
# (stat/find cannot run, no root derivable, device mismatch, root at/above $HOME, or the find watchdog
# timing out) — over-denying a resolvable target rather than silently opening the alias route.
_hardlink_alias_hit() {
  _ha_res=$1; _ha_root=$2; _ha_cls=$3
  # 0. A hardlink requires an EXISTING file (a new-file Write, or an unresolved leaf, has no inode and
  #    no aliases) — so a non-existent target is NOT a hit here (the string matchers already judge its
  #    NAME). This must precede the stat fail-safe, or every write to a new path would over-deny.
  [ -e "$_ha_res" ] || return 1
  # 0b. GUARD-HL-REVIEW-FASTFOLLOW F1 — a DIRECTORY subject exits HERE, before the nlink pre-filter.
  #    Every directory has st_nlink >= 2 (`.` + its parent entry + one per subdir), so step 1's cheap
  #    exit NEVER fires for one; and guard.sh routes Grep/Glob `.tool_input.path` (usually a directory)
  #    through guard_check_read, so the agent's highest-frequency search tools were paying mktemp + a
  #    backgrounded repo-wide find + the watchdog subshell per call (~83ms measured).
  #    SOUNDNESS — scoped to the SUPPORTED filesystems (ext*/xfs/btrfs/APFS): POSIX link() on a
  #    directory is refused there, and BOTH classifier arms (is_control_plane_path, _is_secret_hit)
  #    only ever name FILES, so a directory can never be the hardlink alias of a CP/secret file — the
  #    skipped inode check is provably redundant for it. Legacy HFS+ DID allow directory hardlinks;
  #    that is disclosed in docs/operations/runtime-guards.md. A directory named at a control-plane
  #    path is still judged by the STRING matchers, which run outside this helper. Symlinked
  #    directories are unaffected (symlinks resolve BEFORE this helper, which takes the resolved path).
  #    The dir-swap-between-decision-and-write TOCTOU is §4 CEILING 2's existing class, not a new one.
  [ -d "$_ha_res" ] && return 1
  # 1. Fast pre-filter: link count. nlink<=1 => no alias => ALLOW (the subprocess-cheap common case).
  #    On an EXISTING target a count that cannot be parsed is anomalous and fails safe to a HIT.
  _ha_nl=$(_nlink_of "$_ha_res") || return 0
  [ "$_ha_nl" -le 1 ] 2>/dev/null && return 1
  # 2. The target's own (dev,ino). Fail-safe HIT if unreadable.
  _ha_di=$(_devino_of "$_ha_res") || return 0
  _ha_dev=${_ha_di%% *}; _ha_ino=${_ha_di##* }
  # 3. Root: the PASSED protected root (live hook — authoritative) else derive the NEAREST repo
  #    boundary strictly below $HOME (§2d). No derivable root fails safe to a HIT.
  if [ -z "$_ha_root" ]; then
    _ha_root=$(_hlink_repo_root "$_ha_res") || return 0
  fi
  # 3b. Cap the FINAL root — passed OR derived — at the PHYSICAL $HOME (LOW-1). A repo rooted AT $HOME
  #     (or above) would `find $HOME`; resolve the root physically and fail safe to a HIT there. The
  #     physical resolution also aligns the root with _res (both physical) for the scan below.
  _ha_root=$(CDPATH= cd "$_ha_root" 2>/dev/null && pwd -P) || return 0
  _hl_at_or_above_home "$_ha_root" && return 0
  # 4. Device coherence (vet C3, MEDIUM). A hardlink cannot cross devices, so any alias is on _res's
  #    device. If the root sits on a DIFFERENT device, do NOT skip (skip = no-hit = fail-OPEN): re-root
  #    at _res's own repo (re-capped); if that is still cross-device, fail safe to a HIT.
  _ha_rd=$(_devino_of "$_ha_root") || return 0
  if [ "${_ha_rd%% *}" != "$_ha_dev" ]; then
    _ha_root=$(_hlink_repo_root "$_ha_res") || return 0
    _ha_root=$(CDPATH= cd "$_ha_root" 2>/dev/null && pwd -P) || return 0
    _hl_at_or_above_home "$_ha_root" && return 0
    _ha_rd=$(_devino_of "$_ha_root") || return 0
    [ "${_ha_rd%% *}" = "$_ha_dev" ] || return 0
  fi
  # 5. Enumerate the inode's other names within the repo, on the one filesystem (-xdev), under the
  #    fail-safe find WATCHDOG (I1). PRUNE ONLY the internally-hardlinked BULK that never shares an
  #    inode with a worktree write-target: .git/objects, .git/lfs (vet C1 — the rest of .git, incl.
  #    config/hooks/refs, is control-plane and STAYS in scope) and node_modules (vet C2 — DISCLOSED
  #    residual). A find that errors OR exceeds the time budget fails safe to a HIT.
  _ha_names=$(_hl_find_inode "$_ha_root" "$_ha_ino") || return 0
  # 6. Classify each returned name whose DEVICE equals _res's (kills the inode-number-coincidence FP
  #    across devices). A genuine hit echoes the sanitized path (LOW-3: strip control chars, cap length
  #    — a newline in a filename would otherwise break the deny JSON).
  _ha_ofs=$IFS; IFS='
'
  for _ha_p in $_ha_names; do
    [ -n "$_ha_p" ] || continue
    _ha_pd=$(_devino_of "$_ha_p") || continue
    [ "${_ha_pd%% *}" = "$_ha_dev" ] || continue
    if "$_ha_cls" "$_ha_p"; then
      IFS=$_ha_ofs
      printf '%s' "$_ha_p" | tr -d '\000-\037\177' | cut -c1-200
      return 0
    fi
  done
  IFS=$_ha_ofs
  return 1
}

# Thin wrappers over the one engine (design §2b). BOTH forward the PASSED protected root ($2) — the
# live hook's root is authoritative and unsteerable, and using it avoids the home-walk DoS entirely
# (the engine only DERIVES when $2 is empty). The CP wrapper classifies with is_control_plane_path;
# the SECRET wrapper with _is_secret_hit (template exemption). When no root is passed (kit-guard CLI),
# the engine derives the NEAREST repo boundary strictly below the PHYSICAL $HOME.
_hardlink_alias_hit_cp()     { _hardlink_alias_hit "$1" "$2" is_control_plane_path; }
_hardlink_alias_hit_secret() { _hardlink_alias_hit "$1" "$2" _is_secret_hit; }

# guard_check_read "<file>": deny reading SECRET material into the agent's context (the read half of
# exfil, A8 family 6) — the secret then reaches the model provider / logs / a PR. Symmetric with the
# secret-WRITE deny in guard_check_path but NARROWER: it does NOT deny control-plane reads (reading the
# guard/CI to understand it is legitimate). Template env files (.env.example/.sample/.template/.dist)
# are allowed; a single file_path means `*.env.*` is safe here (no multi-arg form to abuse). Honest
# ceilings: an interpreter (python -c open()) bypasses the shell path, and jq-absent leaves Read allowed.
guard_check_read() {
  fp=$1
  # MEDIUM-1 (round 3): the live hook now threads its PROTECTED_ROOT here as $2, so the read-side
  # secret-inode check uses the AUTHORITATIVE, unsteerable root instead of always deriving (closes the
  # live-read planted-`sub/.git` steer). Empty $2 (kit-guard CLI) keeps the nearest-derive fallback.
  _gcr_root=${2:-}
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  # GUARD-PATH-ALIAS-BYPASS (P0): the read half was the variant proven reachable end to end — a
  # renamed symlink returned a planted secret's contents through the real Read tool. Same union
  # rule as the write side: allowlist on literal AND resolved; deny on literal OR resolved; a
  # failure to resolve is itself a denial. The allowlist below short-circuits before everything,
  # which is exactly why it must take the conjunction rather than either name alone.
  _rres=''; _rrok=0
  _rres=$(_resolve_physical "$fp") && _rrok=1 || _rrok=0
  _rrbase=''; [ "$_rrok" = 1 ] && _rrbase=$(basename "$_rres" 2>/dev/null || printf '%s' "$_rres")
  if ! selfedit_allowed && [ "$_rrok" = 0 ]; then
    printf '13: path (%s) could not be resolved - refusing to read a target that cannot be identified.' "$fp"; return 1
  fi
  # GUARD-CP-HARDLINK-ALIAS (§2b): the secret-INODE check goes BEFORE the template allowlist (vet
  # HIGH-1) — a single end-of-function placement would be dead code for the flagship cloak (a hardlink
  # named `.env.example` onto a real `.env` satisfies the conjunctive allowlist and returns ALLOW
  # first). Gated `! selfedit_allowed` only (there is no root on the read path; the wrapper derives it).
  # Reads of CONTROL-PLANE files stay legitimate, so the read side denies ONLY on a secret hit — this
  # closes the silent-exfil case a gate provably cannot catch. A non-empty name => a genuine secret
  # hardlink; empty => the engine's fail-safe (M1: a DISTINCT, true reason, not the secret-specific one).
  if ! selfedit_allowed && [ "$_rrok" = 1 ]; then
    if _hlnamed=$(_hardlink_alias_hit_secret "$_rres" "$_gcr_root"); then
      if [ -n "$_hlnamed" ]; then
        printf '13: this path is a hardlink to secret material (%s) - reading it is the read half of exfil, human-gated. The name it is reached by does not change what it reads.' "$_hlnamed"
      else
        printf '13: could not verify the target'\''s hardlink aliases (stat/find unavailable, timed out, or an ambiguous root) - denied fail-safe (refusing to read a target whose aliases cannot be confirmed). Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget - make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds); see docs/operations/runtime-guards.md, section Hardlink aliases.'
      fi
      return 1
    fi
  fi
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist)
      case "$_rrbase" in
        .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
      esac ;;
  esac
  if ! selfedit_allowed; then
    # GUARD-CP-HARDLINK-ALIAS §2c: the byte-literal + case-folded secret arms are consolidated into
    # _is_secret_path (one source of truth, byte-identity-coupled). The template ALLOW above stays
    # byte-literal (never folded), so a case-variant `.ENV.EXAMPLE` still falls through to this deny —
    # the existing accepted over-deny (design §3/§4a). Deny MESSAGE stays here (literal wording).
    if _is_secret_path "$fp"; then
      printf '13: reading secret material (%s) into context is the read half of exfil (-> model/logs/PR) - human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1
    fi
    # …and the union on the RESOLVED target (both arms, via the same helper), so a benign name cannot
    # front a secret file.
    if [ "$_rrok" = 1 ] && _is_secret_path "$_rres"; then
      printf '13: this path resolves to secret material (%s) - reading it is the read half of exfil, human-gated. The name it is reached by does not change what it reads.' "$_rres"; return 1
    fi
  fi
  return 0
}

# --- CP-8a: leading-verb discipline -------------------------------------------------
# A segment's LEADING VERB decides whether its arguments are CODE or DATA. These two
# commands contain identical bytes; only the verb tells them apart:
#     bash -c "rm -rf /"          <- the argument is CODE   (a weapon)   -> must DENY
#     grep -rn "rm -rf" scripts/  <- the argument is DATA   (a search)   -> must ALLOW
# guard_read_only_command returns 0 ONLY for a command that is provably a SINGLE read-only
# invocation; for everything else the destructive matrix below runs UNCHANGED on the RAW
# command. It never rewrites or splits the command (see the closing note).
#
# INVARIANT (load-bearing): a verdict may only move DENY -> ALLOW when a safe lead is
# POSITIVELY RECOGNIZED. An unknown lead strips nothing, so behaviour is byte-for-byte
# today's. A bug here therefore fails CLOSED (over-denies), never OPEN.
#
# There is NO splitting: a shell metacharacter (; | & < > $ ( ) or backtick) ANYWHERE makes
# the whole command non-exempt outright. That is why a quoted separator cannot trick the
# exemption — it never parses the command into segments at all. Fail-closed.
#
# A segment is exempt ONLY if ALL of these hold:
#   1. it contains no < > $ ( ) or backtick — a redirect can truncate a file even under a
#      read verb (`echo -n > ci.yml`), and a command substitution smuggles code past it
#      (`grep foo $(rm -rf /)`). Unparseable => never exempt.
#   2. its first token carries no env-assignment (`GIT_EXTERNAL_DIFF=rm git diff`) and is not
#      a wrapper — the lead must be the verb itself, plainly.
#   3. that verb is in the STRICT set below: tools that write ONLY to stdout.
# The set deliberately EXCLUDES every tool with a write/exec escape, exactly as the WS1 note
# at guard_check_command already established — this is that vetted list, not a fresh one:
#   sed  (`s///e` EXECUTES the pattern space; `w file` writes one)
#   awk  (`system()`, `print > "file"`)
#   find (`-exec` / `-delete`)
#   sort (`-o file`)  ·  uniq (`uniq in out`)  ·  less/more (`!cmd`)  ·  xxd (`-r` writes)
# Admitting any of them would hand the guard an arbitrary-execution primitive to save a
# keystroke. `sed -n` stays denied; `head`/`tail` do the same job with no escape.
# `git` is admitted only on subcommands that cannot destroy (NOT push/reset/clean/checkout);
# `kit-guard` only on its read-only subcommands, so a guard slice can probe the guard.
# Returns 0 (exempt) ONLY for a command that is provably a SINGLE read-only invocation.
# It never REWRITES the command: on the non-exempt path the destructive matrix receives the
# raw string byte-for-byte, so not one of its ~40 rules has its assumptions perturbed. (An
# earlier draft split the command into segments and rejoined them with ';' — that destroyed
# the pipe `curl x | sh` detects and the end-of-string `--admin` anchors on, silently turning
# two DENY rules into ALLOW. Do not reintroduce rewriting.)
guard_read_only_command() {
  _c=$1
  # 1. ANY separator, redirect, substitution, expansion or backtick => not a simple, single
  #    invocation => never exempt. This is what makes the exemption safe rather than clever:
  #    `grep foo && rm -rf /`, `grep foo $(rm -rf /)`, `echo -n > ci.yml` all fail here.
  printf '%s' "$_c" | grep -q '[;|&<>$()`]' && return 1
  # 2. the leading verb, plainly: strip only whitespace and a leading backslash. An
  #    env-assignment prefix (`GIT_EXTERNAL_DIFF=rm git diff`) is not plainly a verb.
  _lead=$(printf '%s' "$_c" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//')
  _arg1=$(printf '%s' "$_c" | sed -E 's/^[[:space:]]*//; s/^[^[:space:]]+[[:space:]]+//; s/[[:space:]].*$//')
  case "$_lead" in
    *=*) return 1 ;;
    # 3. STRICT set: tools that write ONLY to stdout. Deliberately EXCLUDES every tool with a
    #    write/exec escape — exactly as the WS1 note below already established. This is that
    #    vetted list, not a fresh one:
    #      sed  (`s///e` EXECUTES the pattern space; `w file` writes one)
    #      awk  (`system()`, `print > "file"`)   ·  find (`-exec` / `-delete`)
    #      sort (`-o file`)  ·  uniq (`uniq in out`)  ·  less/more (`!cmd`)  ·  xxd (`-r`)
    #    Admitting any of them would hand the guard an arbitrary-execution primitive to save a
    #    keystroke. `sed -n` therefore stays denied; head/tail do the job with no escape.
    grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink|echo|printf|which|type)
      return 0 ;;
    git)
      # only subcommands that cannot destroy — NOT push/reset/clean/checkout.
      case "$_arg1" in
        # NOT diff|log|show — they honor --output=<file>, an arbitrary file WRITE via the
        # diff machinery (see the git --output deny in guard_check_command). commit|status|
        # blame|describe carry no such write flag.
        commit|status|blame|describe) return 0 ;;
      esac ;;
    kit-guard|*/kit-guard)
      # the guard's own read-only CLI, so a guard slice can probe the guard.
      # ⚠️ GUARD-READONLY-FP-RELIEF structural finding S2 (2026-08-19, measured both ways, security
      # vet L1): this clause is DEAD FOR CP-CLASSIFYING ARGUMENTS ONLY — STILL REQUIRED FOR BARE
      # `kit-guard` PROBING. `guard_read_only_command` runs at the bottom of `guard_check_command`,
      # AFTER the CP-8b control-plane block, so a `kit-guard path <control-plane-path>` has already
      # been decided (and, before Arm A, denied) by the time control reaches here — which is why
      # relief for that face is built in the CP arms (`_cp8b_tad_is_kit_query`) and NOT here.
      # The clause is LIVE for the far more common probe whose argument is a destructive command
      # rather than a path: `kit-guard cmd 'rm -rf /'` reaches this line and is exempted from the
      # destructive matrix by it. Deleting it would break guard self-probing outright.
      case "$_arg1" in
        cmd|path|mcp) return 0 ;;
      esac ;;
  esac
  return 1
}

# --- CP-8b: bind a verb/flag to its TARGET ------------------------------------------
# The block this replaces matched the CO-OCCURRENCE of a mutation verb and a control-plane path
# anywhere in the flat command string, and never asked whether the verb's TARGET was that path. Two
# symmetric faces of that one missing relation:
#   over-DENY : `cp conformance/x /tmp/b` (copying OUT) - both tokens present, so denied.
#   over-ALLOW: `git archive -o conformance/x` (a real write) - `git archive` is not a mutation verb,
#               and `mv conformance /tmp` (the BARE directory) - the path patterns all require a
#               trailing slash, so they match a file INSIDE the dir and never the dir ITSELF.
# See docs/architecture/2026-07-12-cp8-guard-ergonomics-design.md sections 7-13.
#
# INVARIANT (load-bearing, inherited from CP-8a): a verdict may move DENY -> ALLOW only where a safe
# shape is POSITIVELY RECOGNIZED. Every relaxation below is an allow-back from the existing deny floor;
# anything unrecognized keeps today's behavior. A bug here therefore fails CLOSED, never OPEN.

# bare control-plane DIRECTORY names, for TARGET matching only. is_control_plane_path is deliberately
# NOT widened: it also drives the Write/Edit path (guard_check_path), and this slice adds no blast
# radius there. `mv conformance/ /tmp` was already denied; `mv conformance /tmp` was not - and that one
# command relocates every gate in the repo.
# CASE-INSENSITIVE since A2, for the same reason as is_control_plane_path and via the same two-step:
# literal first (zero subprocesses for an all-lowercase target), fold only on an uppercase miss.
# Measured before the fix: `mv skills /tmp/x` -> DENY but `mv Skills /tmp/x` -> ALLOW, and on a
# case-insensitive filesystem that second command relocates the REAL skills/ directory — precisely the
# command the comment above exists to deny. is_control_plane_path does NOT cover these: its patterns
# are `skills/*`, which a bare directory name never matches.
is_control_plane_target() {
  is_control_plane_path "$1" && return 0
  # GUARD-CP-WRITE-ROUTES Cure 1 (Route 1): normalize the subject through _cp8b_norm (collapse
  # //, a /./ FIXPOINT, trailing /, leading ./, and .. traversal) before the exact-literal match,
  # so a redundant-syntax spelling (hooks//pre-push, hooks/./pre-push, hooks/./././pre-push,
  # x/../hooks/pre-push) can no longer evade it. The normalized value feeds is_control_plane_path
  # AS WELL AS _ctm_match: the Route-1 exploit targets are FILES (hooks/pre-push, scripts/kit-guard,
  # scripts/dora.sh) matched ONLY by is_control_plane_path — _ctm_match is bare-DIRECTORY names, so
  # feeding _ctm_match alone would leave the file route open (K-N1b pins this line). Canonical-only:
  # normalization collapses redundant syntax, it never reclassifies a genuinely-ordinary path.
  _ct=$(_cp8b_norm "$1")
  is_control_plane_path "$_ct" && return 0
  _ctm_match "$_ct" && return 0
  case "$_ct" in
    *[A-Z]*) _ctm_match "$(printf '%s' "$_ct" | LC_ALL=C tr 'A-Z' 'a-z')" && return 0 ;;
  esac
  # GUARD-DENY-TRIO M1: a glob-spelled target whose literal prefix segment-intersects a protected leaf
  # (`hooks/pre-pus*`, `AGENTS.m*`, `agents/*.agent.m*`) is a write to a governing file. Reached from the
  # write-verb route (_cp8b_cp_target_in), the combined-redirect route (_cp8b_tad_redir_cp /
  # _cp8b_redirect_hits_cp) and the bare-token walk (_cp8b_tok_is_cp) — one site covers all. Reads never
  # reach here (read verbs' args are data). Fast-exits on a metachar-free target, so ordinary paths and
  # the hot path are untouched; the broad-glob relief (`*`, `docs/*`, `build/out-*`) survives inside it.
  _cp8b_glob_hits_cp "$1" && return 0
  return 1
}

# Bare control-plane DIRECTORY names, LOWERCASED (see the _cpp_match warning: an uppercase byte in any
# pattern here can never match a folded subject and would silently un-protect that directory).
#
# ⚠️ THIS IS THE FOURTH MATCHER, AND IT IS THE ONE A NEW DIRECTORY FAMILY IS MOST LIKELY TO MISS.
# The C5 completeness discipline names THREE matcher sites (`is_control_plane_path` + the two pathhit
# regex tiers); this list is a fourth, and it is invisible from all three because it holds BARE
# directory names — `is_control_plane_path`'s patterns are `profiles/*`, which a bare `profiles` never
# matches. GUARD-PATH-ENUMERATION-INCOMPLETE S1 shipped the `profiles/` family through the three named
# sites and left this one out; measured on the shipped build, `mv profiles /tmp/x` and
# `chmod -R 777 profiles` both ALLOWED while every file inside `profiles/` denied. That is the exact
# hole the `mv conformance /tmp` note above records, reopened for a new family one release later: a
# family is only as protected as its least-protected route, and the single command that relocates the
# whole directory is the one worth the most to an attacker. ANY future directory family must be added
# HERE as well as to `_cpp_match` and both pathhit tiers — four sites, not three.
_ctm_match() {
  case "$1" in
    conformance|skills|adapters|agents|scripts|profiles|hooks|.claude|.github|.git|.kit|\
    */conformance|*/skills|*/adapters|*/agents|*/scripts|*/profiles|*/hooks|*/.claude|*/.github|*/.git|*/.kit)
      return 0 ;;
  esac
  return 1
}

# GUARD-DENY-TRIO M1 — close the glob-spelled write-route evasion by LITERAL-PREFIX-ANCHORED,
# SEGMENT-SAFE disqualification (design docs/architecture/2026-08-18-guard-deny-trio-design.md §3,
# D-240816-1). A write-verb argument or combined-redirect target spelled as a glob (`hooks/pre-pus*`,
# `AGENTS.m*`, `agents/*.agent.m*`) evades the exact-literal pathhit corpus: `hooks/pre-push` is a
# full-filename leaf, so `hooks/pre-pus*` matches no exact pattern and ALLOWs. The cure denies a glob
# token IFF, after Cure-1 normalization, its NON-EMPTY literal prefix segment-intersects a protected
# leaf. NOT the naive `case "<leaf>" in <token>)` (design H-1, REJECTED): POSIX `case` lets `*` cross
# `/`, so that shape denies `cp x.txt docs/*` (`docs/*` would match `docs/governance/…`). The SLASH-COUNT
# guard in _cp8b_glob_scan is the H-1 lock — token and leaf must have equal slash counts, which makes a
# `*` unable to consume a `/`, so the match is per-segment even though POSIX `case` is used.
#
# _CP8B_GLOB_LEAVES is the residual pathhit-T1 leaf set (the SAME protected NAMES is_control_plane_path
# classifies — NOT a new enumeration of glob spellings, the D-240816-1 trap — the existing leaf NAMES
# re-consulted prefix-wise). Directory-family members (.claude/ .github/ .git/ conformance/ skills/
# adapters/ scripts/ profiles/) are DELIBERATELY ABSENT: a glob under them already pathhits
# (`skills/[^space]*` matches `skills/foo*`), so they need no prefix consult. `agents/*.agent.md` is
# the one glob-shaped leaf (agents/ is not a directory family — only `agents/*.agent.md` is protected),
# kept as a glob and matched by _cp8b_glob_scan's DIRECTIONAL branch (§10 A3), NOT a raw `case` — a
# raw `case "$leaf" in $token)` under-matched every CONCRETE-name glob (`agents/reviewer.agent.m*`).
# A selftest cross-checks every entry is
# is_control_plane_path-classified, binding this list to the authoritative corpus so it cannot drift to
# a non-CP name. ⚠️ A NEW full-filename CP leaf OUTSIDE a directory family must be added HERE too — this
# is the glob-write route's site, a FIFTH alongside the is_control_plane_path/_ctm_match/two-pathhit
# sites the C5 completeness discipline already names. `_LC` mirrors _CP8B_PATHHIT_T1_LC: a lowercased
# copy consulted on an uppercase-token miss (so `CODEOWNER*`, `AGENTS.m*`, `REQUIRED-CHECKS.m*` fold),
# authored lowercase to match a folded subject.
# ⚠️ ADOPTER-SAFETY CONSTRAINT (what _cp8b_glob_scan actually requires): a PATTERN leaf must be
# single-dir-segment with the `*` in the FINAL path segment (the `dir/*.ext` shape, e.g.
# `agents/*.agent.md`). A leaf with the glob NOT last, or a multi-segment-deep protected family, is NOT
# covered by _cp8b_glob_scan and would silently UNDER-match — add such a family to the pathhit tiers /
# _cpp_match instead, or extend _cp8b_glob_scan first. (The nested-depth residual is §10 A5.)
_CP8B_GLOB_LEAVES='hooks/pre-push docs/governance/meta-control-log.md docs/governance/.meta-control-last CODEOWNERS AGENTS.md REQUIRED-CHECKS.md .gitattributes .gitleaks.toml .gitleaksignore .semgrepignore .trivyignore .checkov.yaml .checkov.yml .kit/budget.conf .kit/roster.conf .kit/model-tiers.conf .kit/model-map.conf .kit/dials.conf .kit/ratification-seats.conf agents/*.agent.md'
_CP8B_GLOB_LEAVES_LC='hooks/pre-push docs/governance/meta-control-log.md docs/governance/.meta-control-last codeowners agents.md required-checks.md .gitattributes .gitleaks.toml .gitleaksignore .semgrepignore .trivyignore .checkov.yaml .checkov.yml .kit/budget.conf .kit/roster.conf .kit/model-tiers.conf .kit/model-map.conf .kit/dials.conf .kit/ratification-seats.conf agents/*.agent.md'

# _cp8b_glob_scan "<token>" "<leaf-list>": 0 iff <token> (a glob pattern, already normalized/folded)
# segment-safe intersects a leaf. Slash-count equality per leaf (pure parameter-expansion counter, no
# fork) forbids `*` from crossing `/`. TWO leaf shapes:
#   • CONCRETE leaf (no metachar): `case "$leaf" in $token)` — the token-glob matches the literal leaf.
#   • PATTERN leaf (`agents/*.agent.md`, carrying its OWN `*`): the raw `case` above UNDER-matches — a
#     literal `*` in the SUBJECT aligns only a token whose metachar sits at the same spot, so a
#     CONCRETE-name glob like `agents/reviewer.agent.m*` (which expands onto the real `.agent.md` file)
#     slipped (GUARD-DENY-TRIO §10 A3, both review seats). Instead do a DIRECTIONAL glob-intersection:
#     split the leaf at its `*` into LP (`agents/`) and LS (`.agent.md`); the token DENIES iff its
#     DIRECTORY segment glob-intersects the leaf's literal dir (leaf-dir as SUBJECT / token-dir as
#     PATTERN, so a dir metachar like `ag*`/`agent?`/`agen[t]s` that expands onto `agents/` still
#     commits — §10 A4) AND its BASENAME COMMITS ITS LITERAL to LS — some suffix that STARTS WITH LS's
#     first byte glob-matches LS (`case "$LS" in <suffix>)`). The starts-with-LS[0] anchor is the
#     non-overshoot lock: a bare trailing `*` never starts with `.`, so `agents/foo*` and
#     `ag*/notes.txt` (broad globs that do NOT spell `.agent…`) stay ALLOW — `agents/` is NOT a blanket
#     CP prefix; only the `*.agent.md` family is. slash-count equality keeps both single-segment (no
#     `*` crosses `/`). The leaf word-split runs under `set -f`.
_cp8b_glob_scan() {
  _gsn=0; _gsr=$1; while : ; do case "$_gsr" in */*) _gsn=$((_gsn+1)); _gsr=${_gsr#*/} ;; *) break ;; esac; done
  _gsg=0; case "$-" in *f*) _gsg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split of the leaf list; globbing disabled above
  for _gl in $2; do
    _gln=0; _glr=$_gl; while : ; do case "$_glr" in */*) _gln=$((_gln+1)); _glr=${_glr#*/} ;; *) break ;; esac; done
    [ "$_gsn" = "$_gln" ] || continue
    case "$_gl" in
      *[*?[]*)
        # PATTERN leaf: directional glob-intersection (see header). Split the leaf at its first metachar
        # into LP (dir, incl trailing /) and LS (literal suffix); split the TOKEN at its LAST / into a
        # directory segment and a basename.
        _glp=${_gl%%[*?[]*}; _gls=${_gl#*[*?[]}
        case "$1" in */*) _gtd=${1%/*}; _gtb=${1##*/} ;; *) continue ;; esac
        # The token's DIRECTORY segment must glob-INTERSECT the leaf's literal dir (leaf-dir as SUBJECT,
        # token-dir as PATTERN — the concrete-leaf branch's own shape), so a DIR-segment metachar
        # (`ag*`, `agent?`, `agen[t]s`) that expands onto `agents/` still commits. The first A3 cut
        # anchored LP as a LITERAL (`case "$1" in "$LP"*`) and evaded on exactly those spellings
        # (§10 A4). slash-count equality already bounds both to a single dir segment, so POSIX `*`
        # cannot cross a `/` here — no H-1 over-deny (`ag*/notes.txt` stays ALLOW via the LS test below).
        # shellcheck disable=SC2254  # $_gtd is a DELIBERATE glob pattern (the token's dir segment)
        case "${_glp%/}" in $_gtd) : ;; *) continue ;; esac
        # …AND the token's BASENAME must COMMIT its literal to LS: some suffix that STARTS WITH LS's
        # first byte glob-matches LS. The starts-with-LS[0] anchor is the non-overshoot lock — a bare
        # trailing `*` never starts with `.`, so `<dir>/notes.txt` and `<dir>/foo*` stay ALLOW.
        _gl0=${_gls%"${_gls#?}"}
        _gss=$_gtb
        while [ -n "$_gss" ]; do
          case "$_gss" in
            "$_gl0"*)
              # shellcheck disable=SC2254  # $_gss is a DELIBERATE glob pattern (a token-basename suffix)
              case "$_gls" in $_gss) [ "$_gsg" = 1 ] || set +f; return 0 ;; esac ;;
          esac
          _gss=${_gss#?}
        done ;;
      *)
        # shellcheck disable=SC2254  # $1 is a DELIBERATE glob pattern (the proposed write token)
        case "$_gl" in
          $1) [ "$_gsg" = 1 ] || set +f; return 0 ;;
        esac ;;
    esac
  done
  [ "$_gsg" = 1 ] || set +f
  return 1
}

# _cp8b_glob_hits_cp "<token>": 0 (DENY) iff <token> is a glob whose non-empty literal prefix segment-
# intersects a _CP8B_GLOB_LEAVES member. Fast-exits on the common no-metachar token (one `case`), so the
# hot path pays nothing; only a glob-bearing write/redirect target runs the scan. Cure-1 normalization
# runs BEFORE the prefix test (design H-2), so `./hooks/pre-pus*` (leading `./` stripped) and
# `hooks//pre-pus*` (// collapsed) deny like `hooks/pre-pus*`. An EMPTY literal prefix (bare `*`, or
# `./*` -> `*` after norm) never denies — the broad-glob relief (`*`, `docs/*`, `cp x.txt ./*`).
_cp8b_glob_hits_cp() {
  case "$1" in *[*?[]*) : ;; *) return 1 ;; esac      # no glob metachar -> not this predicate
  _gt=$(_cp8b_norm "$1")
  case "${_gt%%[*?[]*}" in '') return 1 ;; esac        # empty literal prefix -> ALLOW (bare * / ./*)
  _cp8b_glob_scan "$_gt" "$_CP8B_GLOB_LEAVES" && return 0
  case "$_gt" in *[A-Z]*) : ;; *) return 1 ;; esac      # fold only on an uppercase byte (mirrors :93)
  _cp8b_glob_scan "$(printf '%s' "$_gt" | LC_ALL=C tr 'A-Z' 'a-z')" "$_CP8B_GLOB_LEAVES_LC"
}

# _cp8b_joinlines: collapse backslash-newline CONTINUATIONS to a space. A continuation is NOT a command
# separator, and grep is LINE-oriented: `git push \<nl> origin main` puts `push` and `main` on different
# lines, so the flat push rule's regex matches neither (a pre-existing hole). Join first, split second.
_cp8b_joinlines() {
  printf '%s\n' "$1" | sed -e :a -e '/\\$/N; s/\\\n/ /; ta'
}

# _cp8b_joinlines_empty: the same collapse, but to NOTHING instead of a space. Both spellings are
# needed and neither is a substitute for the other, because a continuation means different things at
# different places in a command. BETWEEN tokens the shell yields a word break, so the space-joined
# view is the faithful one (`git push \<nl> origin main` really is three words) — that is
# `_cp8b_joinlines` above, and the push arm must keep it. INSIDE a token there is no break at all:
# `--ad\<nl>min` executes as `--admin`, and the space-joined view says `--ad min`, which matches
# nothing. T2 round 2: that intra-token case was a live bypass on BOTH halves of the --admin arm
# (`gh pr merge 5 --ad\<nl>min` and `gh api … pulls/5/me\<nl>rge` both ALLOWED at 35a2032f).
# The arm therefore reads BOTH views and denies on either — add-only, so no existing deny is lost,
# and the space-joined view keeps holding the between-token forms the empty-joined one would mangle.
_cp8b_joinlines_empty() {
  printf '%s\n' "$1" | sed -e :a -e '/\\$/N; s/\\\n//; ta'
}

# _cp8b_strip_subst: remove shell substitutions to a FIXPOINT — `$(…)`, `` `…` `` and `${…}`.
# Each sed expression is NON-NESTED by construction (`[^()]*`, `[^`]*`, `[^{}]*`), which means one
# pass strips only the INNERMOST occurrences: `$(echo $(echo))` loses its inner `$(echo)` and leaves
# `$(echo )` standing. Round 1 ran exactly one pass and called the class closed; the seat then walked
# straight through it with `--ad$(echo $(echo))min` and ``--ad`echo \`echo\``min``. Iterating to a
# fixpoint is what makes "innermost-first" actually reach the outermost, and it terminates because
# every pass that changes the string strictly shortens it. The cap is belt-and-braces against a
# pathological input, not a correctness bound.
# Newlines are flattened to a SPACE FIRST, because sed is line-oriented and a substitution may
# straddle one (`--ad$(<nl>)min`). A space rather than nothing, so the flattening cannot silently
# weld two separate command lines into one merge-shaped string.
_cp8b_strip_subst() {
  _ssv=$(printf '%s' "$1" | tr '\n' ' ')
  _ssi=0
  while [ "$_ssi" -lt 8 ]; do
    _ssp=$_ssv
    _ssv=$(printf '%s' "$_ssv" | sed -e 's/\$([^()]*)//g' -e 's/`[^`]*`//g' -e 's/\${[^{}]*}//g')
    [ "$_ssv" = "$_ssp" ] && break
    _ssi=$((_ssi + 1))
  done
  printf '%s' "$_ssv"
}

# _cp8b_gh_pr_merge_order "<view>": 0 iff <view> is `gh pr merge` SHAPED — by TOKEN ORDER, not by
# adjacency. This is T2 round 3's fix, and the defect it closes was PRE-EXISTING and critical.
# ── THE DEFECT. Every `gh pr merge --admin` arm in this file is gated by a shape test that was the
# regex `gh[[:space:]]+pr[[:space:]]+merge` — an ADJACENCY match. But `gh` takes its GLOBAL flags
# BEFORE the sub-command (`-R/--repo`, `--hostname`, and friends), so the ordinary operator spelling
# `gh -R o/r pr merge 5 --admin` puts two tokens between `gh` and `pr`, matches nothing, and was
# MEASURED ALLOW at 07928fc1 — as were `--repo o/r` and `--repo=o/r`. Worse, round 2's glue
# disqualifier asks SHAPE FIRST, so `gh -R o/r pr merge 5 --admin $(date)` ALLOWED too: the rule that
# was supposed to close the joiner class "by construction" never ran, because the construction was
# gated on the wrong question. ★ THE LESSON IS NOT ROUND 1's OR ROUND 2's. Those rounds hardened the
# NORMALISATION; nobody re-examined the PREDICATE the normalisation feeds. Four faithful views of a
# string are worth nothing if the question asked of all four is wrong.
# ── THE RULE. Tokenise on whitespace and walk in order: find a token `gh` (or any path ending `/gh`,
# so `/usr/local/bin/gh` still counts), then a token `pr`, then a token `merge`. Tokens in between may
# only be a FLAG (`-`-prefixed, which covers `--repo=o/r` fused) or the VALUE of the flag immediately
# preceding (which covers `-R o/r`). Anything else — a bare word that is not what we are looking for —
# ends that candidate, and the walk restarts from it.
# The token we are LOOKING FOR always wins over the flag-value skip. That ordering is load-bearing:
# in `gh --verbose pr merge`, `--verbose` takes no value, and a naive "skip the token after a flag"
# would eat `pr`. Pinned by a cell.
# ⚠️ THAT ORDERING BUYS ONE RESIDUAL, and T2 round 4 names it rather than leaving it implied: when a
# flag's VALUE is itself the token being looked for, the value wins and the candidate ends — so
# `gh --repo pr pr merge 5 --admin` ALLOWs (the first `pr` is taken as the sub-command, `merge` is not
# where the walk then looks). It is priced, not a hole: `gh` REJECTS that command because `pr` is not
# an OWNER/REPO, so no merge can happen. Pinned as a MEASURED-UNCOVERED ALLOW by the cell
# `T2R4 CEILING (v) --repo VALUE collides with the sub-command` in conformance/agent-autonomy.sh.
# ── THE LEAD TOKEN IS COMPARED CASE-INSENSITIVELY (T2 round 4). APFS and NTFS are case-insensitive
# file systems, so `GH pr merge 5 --admin` and `/usr/local/bin/GH …` RUN on the owner's own host, and
# every shape test here compared `gh` case-sensitively — MEASURED ALLOW at both 07928fc1 and 2be451ae.
# ONLY the lead token is folded, never the whole view: `--ADMIN` is not a flag `gh` accepts, so folding
# the flags too would invent an over-deny on a command that cannot bypass anything. Pinned both ways.
# ── WHAT IT REFUSES, which is the reason it is an ORDER test and not a "these three tokens appear"
# test: `gh pr list | grep merge` and `gh pr list --search merge` are NOT shaped — `list` sits between
# `pr` and `merge` and is neither a flag nor a flag's value. Those are READS this row exists to keep
# working, and both are pinned as ALLOW cells.
# ── ADD-ONLY. It ships as a DISJUNCT beside the incumbent adjacency grep at both call sites, never as
# a replacement. The union can only ever add a deny, so no verdict that denied at 07928fc1 can stop
# denying — which is what keeps M-R1..M-R12's anchors valid. It matters concretely: the adjacency
# regex is a SUBSTRING match and can fire inside a token this walk would reject.
# `set -f` is saved and restored around the split, because the view may contain glob metacharacters
# and pathname expansion here would rewrite the very tokens being judged.
_cp8b_gh_pr_merge_order() {
  _mo_sf=0; case "$-" in *f*) _mo_sf=1 ;; esac
  set -f
  _mo_g=0; _mo_p=0; _mo_prev=''
  for _mo_t in $1; do
    # the LEAD token only, case-folded (see the header); flags and sub-commands stay case-sensitive.
    _mo_tl=$(printf '%s' "$_mo_t" | tr 'A-Z' 'a-z')
    if [ "$_mo_g" = 0 ]; then
      case "$_mo_tl" in gh|*/gh) _mo_g=1; _mo_p=0; _mo_prev='' ;; esac
      continue
    fi
    if [ "$_mo_p" = 0 ]; then
      if [ "$_mo_t" = pr ]; then _mo_p=1; _mo_prev=''; continue; fi
    elif [ "$_mo_t" = merge ]; then
      [ "$_mo_sf" = 1 ] || set +f
      unset _mo_sf _mo_g _mo_p _mo_prev _mo_t _mo_tl 2>/dev/null || :
      return 0
    fi
    case "$_mo_t" in -*) _mo_prev=$_mo_t; continue ;; esac
    case "$_mo_prev" in -*) _mo_prev=''; continue ;; esac
    _mo_g=0; _mo_p=0; _mo_prev=''
    case "$_mo_tl" in gh|*/gh) _mo_g=1 ;; esac
  done
  [ "$_mo_sf" = 1 ] || set +f
  unset _mo_sf _mo_g _mo_p _mo_prev _mo_t _mo_tl 2>/dev/null || :
  return 1
}

# _CP8B_API_MUTATOR: the presence-only MUTATION INDICATOR pattern for (A)'s REST disjunct (T2 round
# 3). PRESENCE, never a value: `--method $(echo PUT)` hides the method behind glue and still denies,
# because the indicator token is plainly there. A lone variable so ONE mutant (M-R14) can drop the
# whole requirement, and so this list cannot drift apart from the comment that explains it.
_CP8B_API_MUTATOR='(^|[[:space:]])(-X|--method|-f|-F|--field|--raw-field|--input)'

# _CP8B_API_READONLY_FLAGS: the value-taking flags of `gh api` that cannot carry a METHOD or a BODY.
# A lone variable so ONE mutant can drop the whole exclusion, and so the list cannot drift apart from
# the comment that explains it (the same shape as `_CP8B_API_MUTATOR` above).
# MEASURED AGAINST `gh version 2.96.0 (2026-07-02)` — this list is a CLI surface, not a protocol one,
# so a later gh that gives one of these flags a body-carrying meaning silently widens the exclusion.
# Re-measure the list when the pinned version moves; that is the maintenance this line exists to ask for.
_CP8B_API_READONLY_FLAGS='--jq -q -H --header --template -t --cache --hostname --preview -p'

# _cp8b_api_expansion_indicator "<view>": 0 iff <view> carries a token that CONTAINS an expansion byte
# (`$` or a backtick) and is NOT the value of a read-only flag. T2 round 4, and it exists because
# round 3 REGRESSED here.
# ── THE REGRESSION. `$_CP8B_API_MUTATOR` above is a LITERAL-token test, so a method carried by an
# expansion has no indicator to find: `gh api "$X" repos/o/r/pulls/5/merge` — with the ordinary
# `X=-XPUT` — DENIED at 07928fc1 and ALLOWED at 2be451ae, and nothing else in the guard caught it.
# ★ The lesson is about DIRECTION: round 3's narrowing was measured against the over-denies it
# refunded and not against the denies it silently dropped. A narrowing needs both measurements.
# ── THE RULE, and it is deliberately NOT a revert (round 2's unconditional disjunct is the over-deny
# that M-R14 locks the refund of). The guard cannot read what an expansion expands to, so fail-CLOSED
# is to assume it could be the method: a token that is wholly `$NAME`, `${…}`, `$(…)` or a backtick
# pair COUNTS as a mutation indicator — UNLESS the token immediately BEFORE it is one of the read-only
# value-taking flags below. Presence of the FLAG, never its value, exactly as the literal indicator is
# presence-only. `--jq "$(cat q)"`, `-H "X-Y: $(cat h)"` and `--jq "$(cat q)" -q .x` therefore keep
# round 3's refund.
# ── T2 ROUND 5: THE PREDICATE IS `CONTAINS`, NOT `IS`, AND THAT IS THE WHOLE CHANGE.
# ★ Round 4 wrote "the token is WHOLLY an expansion" and anchored a regex on it. That is an INSTANCE
# shape dressed as a rule: it describes the five spellings round 4 had in front of it and nothing
# else, and six more measured DENY at 07928fc1 and ALLOW at cec9bce4 — round 4's own re-deny left the
# regression it was written to close still open. `$(cat m)` and `$*` WORD-SPLIT, so no fragment is
# wholly an expansion; `$@`, `$1`, `${X}${Y}` and `"$X$Y"` are single tokens the anchored alternation
# simply did not describe; `"$X"suffix` needs only one extra byte. Enumerating expansion SYNTAXES is
# the same losing move as enumerating paths — so the question is no longer "which expansion is this?"
# but "is there an expansion byte in this token at all?". A token containing `$` or a backtick
# ANYWHERE counts. The guard still cannot read what an expansion expands to; fail-CLOSED is still to
# assume it could be the method.
# ── THE EXCLUSION IS UNCHANGED IN ROLE and is what keeps round 3's refund: presence of a read-only
# value-taking flag immediately BEFORE the token (or FUSED to it as `--jq=…`), never the flag's value.
# ── ⚠️ THE TOKENIZER IS NOW QUOTE-AWARE, AND IT HAD TO BECOME SO. Round 4 ran over the DE-QUOTED
# views, where `-H "A: $X"` — ONE shell word — word-splits into `A:` and `$X`, whose preceding token
# is `A:` and not `-H`. Under `IS` that read survived by ACCIDENT (`$(cat` in the sibling `-H "X-Y:
# $(cat h)"` is not wholly an expansion, so the accident even looked like a rule); under `CONTAINS` it
# would have denied an ordinary header read. MEASURED, not reasoned: `gh api -H "A: $X"
# repos/o/r/pulls/5/merge` was ALREADY DENIED at cec9bce4 — an unpinned round-4 over-deny in exactly
# the read lane this row exists to protect — and it is refunded here and pinned by its own cell.
# So this function takes a view with its QUOTES INTACT (`$_pj`/`$_pe`, not `$_pn`/`$_pne`) and splits
# on unquoted whitespace only, dropping the quote bytes. A backslash is treated as a joiner exactly as
# `_s6_dequote` treats it: the byte is dropped and the next byte kept, so `\$` reads as `$` and denies
# — fail-closed, and one byte's worth of over-deny on a shape nobody writes.
# ── WHY awk. A POSIX `for` loop over `$1` cannot see quotes; the alternative is a character walk in
# shell, which is an order of magnitude slower on every command the hook judges. awk is already used
# in this file (`_cp8b_hd_consumer`). No `set -f` dance is needed any more: the split happens inside
# awk, so pathname expansion never touches the tokens.
_cp8b_api_expansion_indicator() {
  printf '%s\n' "$1" | awk -v roflags="$_CP8B_API_READONLY_FLAGS" '
    BEGIN { n = split(roflags, fl, " "); for (i = 1; i <= n; i++) ro[fl[i]] = 1; buf = "" }
    { buf = buf $0 " " }
    END {
      q = ""; tok = ""; started = 0; prev = ""; hit = 0; L = length(buf)
      for (i = 1; i <= L; i++) {
        c = substr(buf, i, 1)
        if (q != "") { if (c == q) { q = "" } else { tok = tok c } ; started = 1; continue }
        if (c == "\047" || c == "\042") { q = c; started = 1; continue }
        if (c == "\\") { i++; if (i <= L) { tok = tok substr(buf, i, 1) } ; started = 1; continue }
        if (c == " " || c == "\t") {
          if (started) {
            e = index(tok, "=")
            fused = (e > 1 && (substr(tok, 1, e - 1) in ro))
            if (!(prev in ro) && !fused && (index(tok, "$") > 0 || index(tok, "\140") > 0)) { hit = 1; break }
            prev = tok; tok = ""; started = 0
          }
          continue
        }
        tok = tok c; started = 1
      }
      exit (hit ? 0 : 1)
    }'
}

# _s6_dequote: delete the JOINER bytes `'`, `"` and `\`. In the shell a quote is a joiner, not a
# boundary — `me''rge` executes as `merge` — so a matcher that respects quotes is a matcher that can
# be walked through. Extracted as a helper at T2 round 2 so the porcelain arm's four views share ONE
# definition (and so one mutant can revert all four; see M-R1).
# ⚠️ NAMED `_s6_`, NOT `_cp8b_`, ON PURPOSE. `_cp8b_dequote` ALREADY EXISTS further down this file
# (the token de-quoter used by the control-plane target parse). A second definition under that name
# would not be an error — the shell simply keeps the LAST one — so this arm would have silently
# called the other function, and M-R1 would have mutated a dead definition and passed while proving
# nothing. Caught by the mutant's own "matched 2 lines" report during the build. The two helpers do
# similar things and must NOT be merged: that one strips a `--flag=` prefix and is load-bearing for
# path matching; this one only deletes bytes.
_s6_dequote() {
  printf '%s' "$1" | tr -d "'\"\\\\"
}

# _cp8b_segments "<cmd>": print one segment per line (split on ; && || | & and newline).
# Used ONLY by the CP-8b logic below. It is NEVER fed back into the destructive matrix, which keeps
# seeing the raw, unsplit string. (CP-8a: an earlier draft split the command and REJOINED it with ';',
# which destroyed the pipe `curl x | sh` detects and the end-of-string `--admin` anchors on, silently
# turning two DENY rules into ALLOW. Nothing is rejoined here.)
# A separator inside a quoted string over-splits into a bogus segment whose lead is unrecognized ->
# scan-and-deny. Over-DENY, fail-closed - and identical to today's verdict.
# GUARD-DENY-TRIO M1 (fd-dup/combined-redirect half): the `&` of a REDIRECT operator (`>&`, `&>`,
# `2>&`, `>>&`) is NOT a command separator and must not split the command. Before this, `s/&/;/g`
# turned `echo x >&conformance/verify.sh` into `echo x >` + `conformance/verify.sh`, orphaning the
# redirect TARGET into a bare segment that the kit-exec recognizer then read as "running the script" and
# ALLOWED — a combined-redirect WRITE laundered as a command. (The boarded GUARD-REDIRECT-FD-DUP-
# COMBINED-BYPASS mechanism, absorbed here.) The design named `_redir_targets`' `&`-exclusion as the
# fix, but the split happens HERE first, so `_redir_targets` never saw `>&word`; both must change. A
# redirect `&` is protected via the _cp8b_soh sentinel across the `&`->`;` pass, then restored, so ONLY
# a true separator `&` (background/`&&` already collapsed above) splits. fd-dups (`2>&1`, `>&-`) keep
# their `&` and stay one segment — _redir_targets then classifies them (numeric/`-` => excluded).
_cp8b_soh=$(printf '\001')
_cp8b_segments() {
  _cp8b_joinlines "$1" \
    | sed -e 's/&&/;/g' -e 's/||/;/g' -e 's/|/;/g' \
          -e "s/>&/>$_cp8b_soh/g" -e "s/&>/$_cp8b_soh>/g" \
          -e 's/&/;/g' \
          -e "s/$_cp8b_soh/\&/g" \
    | tr ';\n' '\n\n'
}

# === GUARD-READ-LANE-2 F-a — THE QUOTED-SPAN MASK, GATED ON A READ-LED WHOLE =======================
# design: docs/architecture/2026-08-26-guard-read-lane-2-design.md §3-F-a.
#
# THE DEFECT. `_cp8b_segments` above is quote-BLIND. A separator byte inside a `'…'` or `"…"` span is
# not a separator at all, but it splits anyway — so `grep -E "a|b" conformance/verify.sh` becomes the
# fragments `grep -E "a` and `b" conformance/verify.sh`, the second of which has an unrecognized lead
# and is scan-and-denied on its control-plane token. Every measured face of this row (R3, R4, R5) is
# that one bug, and it denies PLAIN READS.
#
# THE CURE, AND ITS SHAPE. This is FAIL-BY-DISQUALIFICATION, never fail-by-parse (`D-240813-3`; three
# rounds of this class were reverted, each having reopened a control-plane WRITE hole). It is NOT a
# shell parser. It builds a SEGMENTATION COPY in which the five separator bytes are replaced by
# sentinels WHEN THEY LIE INSIDE A QUOTED SPAN, and it keeps that copy only under a gate. On ANY byte
# whose quoting it cannot settle by inspection it DECLINES — returns the input untouched — and the
# command is judged exactly as it is today, byte for byte. Every path out of here is either "today"
# or "a whole command led end-to-end by read verbs".
#
# THE DECLINE SET, and why each byte is in it:
#   `\` BEFORE `"`, `'` OR `\`   an escaped quote (`x\"`) is NOT a span boundary. A walker that reads
#               it as one masks the REAL `;` after it and merges a write into a read: reverted round
#               3's exact defect. `\\` is in the set because it CONSUMES the next backslash, so the
#               byte after it must not be read as an escape either.
#               ⚠️ NARROWED FROM "ANY BACKSLASH" BY THE T8 REVIEW (commit B). The whole-string form
#               cost the row its own headline faces — `grep -n "readonly\|READONLY" <cp>` and
#               `grep -rn "speed bump\|speed-bump" docs skills`, i.e. grep BRE alternation, the single
#               commonest read spelling in this repo. THE NARROWING IS STILL A DISQUALIFICATION, not a
#               parser: every OTHER `\X` is TWO LITERAL BYTES to the shell and to the walker alike, so
#               it cannot move a span boundary, and the walker needs no rule to handle it correctly.
#               Only the three pairs above can desynchronise a span-kind walk, and only those decline.
#               (`$` and backtick still decline the WHOLE string; `\`+newline is already gone at
#               `_cp8b_joinlines`.) Mutants M-A2 / M-A2b / M-A2c pin the set and each of its members;
#               `K-MASK-BSLASH` pins all three pairs at source level.
#               ⚠️ AND THE SPELLING IS LOAD-BEARING. Written as a `case` pattern, `*'\\"'*` is TWO
#               backslashes inside single quotes and matches NOTHING: the decline vanishes silently
#               while the line is still visibly in the file (the seat measured M-A2 flipping ALLOW
#               against exactly that). It is a `grep` against `_cp8b_mask_bs`, assembled once below
#               from `_cp8b_sq` so no layer of quoting has to be counted by eye.
#   `` ` ``     a command substitution: the bytes that run are not the bytes here.
#   `$`         the same, plus `${…}` and `$VAR`. Design §8's invariant is that NO recogniser in this
#               slice accepts a `$` (it is what keeps GUARD-KIT-EXEC-REDIRECT-UNRESOLVED-TARGET out
#               of reach); this honours it.
#   `<<`        a heredoc. Its body is Arm E's subject and its quoting rules are not these.
#   newline/CR  after joining, a residual newline means more than one command line; the segmenter
#               splits on it and the mask has no opinion about what the second line quotes.
#   odd `"` or odd `'` count  unbalanced quoting over the whole string: the walker's span model and
#               the shell's cannot be shown to agree, so it is not asserted.
#   an OPEN SPAN at the end of the walk (T8 review finding F-2)  the counts are a PRECHECK, not the
#               property: CROSS-KIND PARITY (two `'` and two `"`, one of the `"` inert inside the
#               single-quoted span) passes both counts and still ends mid-span. The walk itself now
#               reports its end state and this declines on it.
# With those bytes gone, "the current opening quote kind wins until its match" IS the shell's rule,
# which is why the walker tracks nothing else.
#
# THE LOAD-BEARING GATE. Masking is kept only if EVERY segment of the masked copy is led by a verb on
# `_CP8B_MASK_GATE_VERBS`. That list is a SEPARATELY DECLARED, re-vetted subset — NOT `_CP8B_READ_VERBS`
# and not a runtime subtraction of it, because the seat's vet (§10-A1 findings 4-5) falsified the first
# draft's "complete by inheritance": `file -C -m X` WRITES `X.mgc`, and the git "read subs" include
# `add`/`commit`/`stash`, which mutate the index and the worktree (`git stash push -- <cp>` discards
# guard edits). So `file` is OUT of the gate and the git subs are the declared query forms only. Those
# verbs keep their existing DATA recognition in the old arms — nothing about their verdict changes —
# they simply may not AUTHORISE re-segmentation.
# What the gate buys, stated HONESTLY — and the first draft of this paragraph overclaimed, so read the
# correction rather than the slogan. WHAT IS TRUE: with the mask kept, every segment's LEAD VERB is on
# this list, so no segment can be led by `cp`/`install`/`mv`/`rm`/`sh`/a kit script, and the mutation
# arms keyed on those LEADS are not reached. WHAT IS NOT TRUE, and was claimed: that the segments are
# therefore harmless. A LEXICON IS A VERB LIST; THE EXEC/WRITE FLAG LIVES IN THE ARGV. The T8 review
# (finding F-1) MEASURED four verbs on the first draft of this list that carry one — `rg --pre <cmd>`
# and `git grep -O <cmd>` EXEC an arbitrary program, `diff --to-file=<path>` and `column -o <path>`
# WRITE one — and all four ALLOW at pristine 4b3debc3, i.e. they are PRE-EXISTING data-lexicon holes
# this gate would have amplified by re-segmenting whole commands on their authority. They are OFF the
# list below, fail-closed, and the underlying holes stay boarded and open (narrowing the data lexicon
# is a different row; doing it here would widen over-deny across the whole read lane unmeasured).
# THE PROPERTY THAT REMAINS, and it is the one a reviewer can check: the mask may only ever be kept for
# a command every one of whose segments is led by a verb this list VETTED — vetting that is a human
# judgement per verb, re-done when a verb is added, NOT an inference from the read lexicon and NOT a
# proof of harmlessness. Any other lead — `sh`, `python3`, `xargs`, `tee`, `cp`, a kit script, an empty lead — discards the
# mask outright. This is what separates F-a from reverted round 2, which classified on the FIRST lead.
# The lead is judged DE-QUOTED (T7's critical: a de-quoted lookup beside a raw test is how `'-delete'`
# slipped find's allowlist), so `'sh'` and `"tee"` are the words they will actually be.
#
# ORDERING. T1's `_cp8b_piped_interp_hit` runs on the RAW command in both arms BEFORE the mask is even
# consulted, so a pipe into an interpreter is judged raw whatever the quoting looks like.
#
# SENTINEL DISCIPLINE (seat finding 7). FIVE DISTINCT bytes, all different from the `>&` sentinel
# `_cp8b_soh` (0x01) used by `_cp8b_segments` above and from `_cp8b_stx` (0x02) used by
# `_cp8b_pipe_segments` — a shared byte would let one mechanism's bookkeeping forge the other's.
# One byte per separator so the restore is exact and total.
_cp8b_mk_pipe=$(printf '\016')
_cp8b_mk_semi=$(printf '\017')
_cp8b_mk_amp=$(printf '\020')
_cp8b_mk_gt=$(printf '\021')
_cp8b_mk_lt=$(printf '\022')
_cp8b_mk_all="$_cp8b_mk_pipe$_cp8b_mk_semi$_cp8b_mk_amp$_cp8b_mk_gt$_cp8b_mk_lt"
# Two users, both below: the mask walk's decline set (`_cp8b_mask_quoted`) and `_cp8b_strip_heredocs`.
_cp8b_cr=$(printf '\r')
_cp8b_sq=$(printf '\047')
# _cp8b_mask_bsset / _cp8b_mask_bs — the NARROWED backslash disqualifier (T8 review, commit B).
# THE SET, on its own line, is the reviewable half: the three bytes a `\` may not immediately precede.
# `"` and `'` because an ESCAPED QUOTE is not a span boundary and a walker that reads it as one
# desynchronises (reverted round 3's defect); `\` because a backslash consumes the next backslash, so
# the byte after the pair must not be read as an escape either. Nothing else belongs here: every other
# `\X` is two literal bytes to the shell and to the walker alike.
# THE PATTERN is a BRE — one literal backslash, then that set as a bracket expression. Assembled once,
# from variables, rather than spelled at the use site: the `'` arrives as `$_cp8b_sq` and the literal
# backslash as a double-quoted `\\\\`, so nothing here depends on counting quote layers by eye. See
# the decline-set note above for the `case`-pattern trap this avoids. Resulting bytes: \\["'\\]
_cp8b_mask_bsset="\"$_cp8b_sq\\\\"
_cp8b_mask_bs="\\\\[$_cp8b_mask_bsset]"
# The gate lexicon: `_CP8B_READ_VERBS` MINUS `file`, and `git` admitted only through the sub list.
# ⚠️ IT IS A COPY ON PURPOSE and must NOT be rewritten as a subtraction of `_CP8B_READ_VERBS`: the two
# lists answer different questions (that one asks "are this verb's arguments data?", this one asks
# "may this verb authorise re-segmentation of the whole command?"), and `file` is the measured proof
# they differ. A future addition to the read lexicon must be re-vetted before it appears here.
# ⚠️ T8 REVIEW FINDING F-1 — FOUR VERBS REMOVED, and the removals are the vet, not a style change:
#   `rg`     — `rg --pre <cmd>` runs an arbitrary preprocessor per file (EXEC).
#   `git grep` (the sub `grep`) — `-O/--open-files-in-pager <cmd>` runs a pager command (EXEC).
#   `diff`   — a `--to-file=<path>` operand is not read-only in every diff implementation (WRITE).
#   `column` — `-o <arg>` is an output SEPARATOR in one dialect and an output FILE in another, and the
#              guard cannot tell which binary it faces (WRITE).
# Bare `grep`/`egrep`/`fgrep` STAY: they carry no exec or write flag. The price is priced and celled —
# a flagless `rg`/`diff`/`column`/`git grep` quoted-alternation read of a CP file is DENY again, one
# retry away from `grep -E`. Removal is fail-closed; adding a verb back requires its own measurement.
_CP8B_MASK_GATE_VERBS='grep egrep fgrep ls cat head tail wc stat du cut tr nl od hexdump tac comm cmp basename dirname realpath readlink echo printf which type shellcheck jq shasum md5 cksum yamllint git'
_CP8B_MASK_GATE_GIT_SUBS='status blame describe diff log show ls-files'
# _cp8b_unmask_quoted "<s>": the sentinels back to their bytes. Total and exact — one byte per byte.
_cp8b_unmask_quoted() {
  printf '%s' "$1" | tr "$_cp8b_mk_all" '|;&><'
}
# _cp8b_mask_walk "<joined-cmd>": the span walk. Tracks ONLY the current opening quote kind, which is
# the shell's own rule once the decline set has removed every byte that could complicate it. awk, not
# a sed pass: a regex cannot carry the open/closed state a span needs, and a shell `while read -n1`
# loop over every command is a per-byte fork budget this hook does not have.
_cp8b_mask_walk() {
  printf '%s\n' "$1" | awk -v P="$_cp8b_mk_pipe" -v S="$_cp8b_mk_semi" -v A="$_cp8b_mk_amp" \
                           -v G="$_cp8b_mk_gt" -v L="$_cp8b_mk_lt" -v Q="$_cp8b_sq" '
    NR == 1 {
      n = length($0); q = ""; out = ""
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q == "") { if (c == "\"" || c == Q) { q = c }; out = out c; continue }
        if (c == q)  { q = ""; out = out c; continue }
        if      (c == "|") out = out P
        else if (c == ";") out = out S
        else if (c == "&") out = out A
        else if (c == ">") out = out G
        else if (c == "<") out = out L
        else               out = out c
      }
      printf "%s", out
      # T8 review finding F-2 - THE END STATE IS PART OF THE ANSWER. A walk that reaches the end of
      # the string with a span still OPEN did not model the shell, it guessed. The two even-count
      # prechecks in _cp8b_mask_quoted cannot see that case, because CROSS-KIND PARITY satisfies them:
      # a string with two single quotes and two double quotes passes both counts even when one double
      # quote is INERT (it sits inside the single-quoted span) and the other opens a span that never
      # closes. The real separator after it was then masked and a write onto the guard was merged into
      # a read verb data argument. Measured DENY at pristine, ALLOW at 41d4278e: a regression.
      # Exit non-zero and the caller declines to today path. M-A4 pins it.
      if (q != "") exit 1
    }'
}
# _cp8b_mask_gate_ok "<masked-cmd>": 0 iff EVERY non-blank segment of the masked copy is led by a gate
# verb. Fails CLOSED on anything it cannot name: an empty lead, a lead carrying a sentinel (`"gr|ep"`),
# an unresolvable git sub — none is on the list, so none passes.
_cp8b_mask_gate_ok() {
  _mgw=$(_cp8b_segments "$1")
  while [ -n "$_mgw" ]; do
    case "$_mgw" in
      *"$_cp8b_nl"*) _mgs=${_mgw%%"$_cp8b_nl"*}; _mgw=${_mgw#*"$_cp8b_nl"} ;;
      *)             _mgs=$_mgw; _mgw='' ;;
    esac
    [ -n "$(printf '%s' "$_mgs" | tr -d '[:space:]')" ] || continue
    _mgp=$(_cp8b_strip_wrappers "$_mgs")
    _mgl=$(_cp8b_dequote "$(_cp8b_lead "$_mgp")")
    _cp8b_in_list "$_mgl" "$_CP8B_MASK_GATE_VERBS" || return 1
    if [ "$_mgl" = git ]; then
      _mgb=$(_cp8b_dequote "$(_cp8b_git_sub "$_mgp")")
      _cp8b_in_list "$_mgb" "$_CP8B_MASK_GATE_GIT_SUBS" || return 1
    fi
  done
  return 0
}
# _cp8b_mask_quoted "<cmd>": PRINTS the string the CP arms should segment — the masked copy when every
# decline passed and the gate held, otherwise the INPUT UNCHANGED. Exit status is informational only
# (0 = mask kept); no caller may branch on it, because "declined" and "kept but identical" must be the
# same thing to everything downstream.
_cp8b_mask_quoted() {
  _mqi=$(_cp8b_joinlines "$1")
  case "$_mqi" in
    *'`'*|*'$'*|*'<<'*)                        printf '%s' "$1"; return 1 ;;
    *"$_cp8b_nl"*|*"$_cp8b_cr"*)               printf '%s' "$1"; return 1 ;;
  esac
  # THE NARROWED BACKSLASH DISQUALIFIER (T8 review, commit B) — decline iff a `\` is IMMEDIATELY
  # followed by `"`, `'` or `\`. Those three pairs are the only ones that can move a span boundary;
  # every other `\X` is two literal bytes and the walk handles it correctly with no rule at all. This
  # is what refunds R3/R4 (`grep "a\|b"`, BRE alternation) without re-opening reverted round 3.
  if printf '%s' "$_mqi" | LC_ALL=C grep -q "$_cp8b_mask_bs"; then printf '%s' "$1"; return 1; fi
  _mqd=$(printf '%s' "$_mqi" | tr -dc '"' | wc -c | tr -d ' ')
  [ "$((_mqd % 2))" = 0 ] || { printf '%s' "$1"; return 1; }
  _mqs=$(printf '%s' "$_mqi" | tr -dc "$_cp8b_sq" | wc -c | tr -d ' ')
  [ "$((_mqs % 2))" = 0 ] || { printf '%s' "$1"; return 1; }
  # F-2 (T8 review): the walk's EXIT STATUS carries its end state — non-zero means it finished with a
  # span still open, which the even-count prechecks above cannot detect (see the note in the walk).
  # An open span means the walker and the shell disagree about what is quoted, so nothing is asserted.
  _mqm=$(_cp8b_mask_walk "$_mqi") || { printf '%s' "$1"; return 1; }
  # Nothing masked => nothing to gate and nothing to gain; hand back the ORIGINAL so the common case
  # is byte-identical to today and cannot be perturbed by the join above.
  [ "$_mqm" != "$_mqi" ] || { printf '%s' "$1"; return 1; }
  _cp8b_mask_gate_ok "$_mqm" || { printf '%s' "$1"; return 1; }
  printf '%s' "$_mqm"
  return 0
}

# _cp8b_unparseable "<seg>": 0 iff the segment carries a construct the guard CANNOT resolve to the bytes
# the shell will actually execute: $VAR, $(...), `...`, <(...). The guard reads PRE-shell-parse bytes;
# the tool acts POST-parse. Such a segment is NEVER relaxed - and, for a git WRITE subcommand, is denied
# OUTRIGHT (see _cp8b_git_write_denied). That is the attack this closes:
#     git archive -o $(echo conformance/verify.sh) HEAD
# would otherwise slip BOTH the target-bind (target unresolvable) AND the co-occurrence floor
# (`git archive` is not a mutation verb). A bare '(' is NOT unparseable - a subshell's lead token is
# unrecognized and already fails closed - so conventional-commit subjects like "fix(guard): ..." parse.
_cp8b_unparseable() {
  printf '%s' "$1" | grep -q '[$`]' && return 0
  printf '%s' "$1" | grep -q '<(' && return 0
  return 1
}

# _cp8b_lead "<seg>": the leading verb, plainly. An env-assignment prefix (`GIT_EXTERNAL_DIFF=rm git
# diff`) yields a token containing '=', which matches no verb set -> unknown -> fail closed.
_cp8b_lead() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//'
}

# _cp8b_dequote "<tok>": strip quote/escape bytes; for --flag=value / of=value forms, yield the VALUE.
# Safe in THIS DIRECTION ONLY: stripping normalizes TOWARD the real path, so --output="conformance/x"
# -> conformance/x -> matches -> DENY. It is NOT general shell parsing; $VAR and $(...) are
# unrecoverable, which is exactly why _cp8b_unparseable REFUSES them rather than parsing them badly.
# (CP-8a's review broke a target-parse whose failure direction was OPEN. Here unparseability is caught
# first and routed to deny, so what remains is a byte-match on a de-quoted literal whose worst case is
# an over-match -> over-DENY -> closed.)
_cp8b_dequote() {
  printf '%s' "$1" | sed -e "s/'//g" -e 's/"//g' -e 's/\\//g'
}

# _cp8b_dequote_lead "<seg>": the segment with ONLY its LEAD TOKEN de-quoted, every other byte
# untouched. T7's cure ("the lead is judged de-quoted") applied where a recogniser needs the whole
# segment but the lexicon lookup inside it keys on the lead: whole-segment `_cp8b_dequote` cannot be
# used there because it would also strip quotes out of the operands the recogniser inspects.
# NORMALIZES TOWARD the real verb, so its only failure direction is an over-match -> over-DENY.
_cp8b_dequote_lead() {
  _dqs=$1
  _dqs=${_dqs#"${_dqs%%[![:space:]]*}"}          # drop leading whitespace
  case "$_dqs" in
    *[[:space:]]*) _dql=${_dqs%%[[:space:]]*}; _dqr=${_dqs#"$_dql"} ;;
    *)             _dql=$_dqs;                 _dqr='' ;;
  esac
  printf '%s%s' "$(_cp8b_dequote "$_dql")" "$_dqr"
}

# _cp8b_tok_is_cp "<tok>": 0 iff the token, de-quoted and stripped of a flag= prefix, is a control-plane
# target.
_cp8b_tok_is_cp() {
  _tt=$(_cp8b_dequote "$1")
  case "$_tt" in *=*) _tt=${_tt#*=} ;; esac
  [ -n "$_tt" ] || return 1
  is_control_plane_target "$_tt"
}

# _cp8b_cp_target_in "<mode>" "<seg>": 0 iff a control-plane TARGET appears among the segment's argument
# tokens.
#   mode=all  - EVERY non-flag token is a target: rm/rmdir/shred/truncate/chmod/chown/tee/patch/dd/sed;
#               mv/rsync (whose SOURCE is destroyed too - which is what catches `mv conformance /tmp`);
#               and ln (which creates a WRITABLE ALIAS to its source - see the dispatch rationale below).
#   mode=last - only the LAST non-flag token is a target: cp/install, which copy CONTENT, so their source
#               is merely READ. This is what makes `cp conformance/verify.sh /tmp/b.sh` (copying OUT)
#               legitimate. A destination-naming flag (-t/--target-directory) is bound explicitly below,
#               in EITHER mode, because it inverts the positional heuristic.
# Globbing is disabled around the word-split so `rm *.sh` cannot expand against the real filesystem.
_cp8b_cp_target_in() {
  _m=$1
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-splitting; globbing disabled above
  set -- $2
  [ $# -gt 0 ] && shift          # drop the leading verb
  _hit=1; _last=''
  while [ $# -gt 0 ]; do
    case "$1" in
      # A destination-naming flag INVERTS the positional heuristic: `cp -t <dir> <src>` and
      # `--target-directory=<dir>` make <dir> the destination even though it is not the last token.
      # Bind it explicitly (any mode) - otherwise the "last token" rule checks the SOURCE and misses
      # the real write target. This is the same flag-binding as `git worktree add -b`. install/ln share
      # -t/--target-directory. A bare `-t` without a value is a malformed command -> nothing to bind.
      -t|--target-directory)
        if [ $# -ge 2 ]; then
          _dt=$(_cp8b_dequote "$2")
          [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
          shift
        fi
        shift; continue ;;
      # Joined short form (`-tconformance`) and abbreviated/`=`-joined long forms (`--target-di=…`,
      # `--target-directory=…`). GNU getopt honors a joined short-option value and any UNAMBIGUOUS long
      # prefix, so a partial match here is not paranoia - it is the exact evasion the security review
      # demonstrated. For cp/ln/install, `--target-d…` is unambiguous (no other `--target-*` option), so
      # matching the family closes the hole without a per-tool option table.
      # CAVEAT (verb-set-coupled): this `--target-d*` match is safe only because NO verb currently routed
      # here (cp/install/mv/rsync/rm/rmdir/shred/truncate/chmod/chown/tee/patch/dd/sed/ln) carries a
      # distinct `--target-d*` option. If a future verb with one is added to these groups, revisit.
      -t?*)
        _dt=$(_cp8b_dequote "${1#-t}")
        _dt=${_dt#=}
        [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
        shift; continue ;;
      --target-d*=*)
        _dt=$(_cp8b_dequote "${1#*=}")
        [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
        shift; continue ;;
      --target-d*)
        if [ $# -ge 2 ]; then
          _dt=$(_cp8b_dequote "$2")
          [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
          shift
        fi
        shift; continue ;;
      -*) shift; continue ;;     # any other flag is not a path target
    esac
    _d=$(_cp8b_dequote "$1")
    case "$_d" in *=*) _d=${_d#*=} ;; esac
    if [ -n "$_d" ]; then
      _last=$_d
      if [ "$_m" = all ] && is_control_plane_target "$_d"; then _hit=0; break; fi
    fi
    shift
  done
  if [ "$_m" = last ] && [ "$_hit" = 1 ] && [ -n "$_last" ] && is_control_plane_target "$_last"; then
    _hit=0
  fi
  [ "$_pg" = 1 ] || set +f
  return $_hit
}

# _cp8b_git_sub "<seg>": the git subcommand, after skipping GLOBAL options. Empty if unresolvable
# (an unknown global option) -> the caller fails closed. A subcommand is a token in COMMAND POSITION:
# you cannot quote your way into `git commit` actually being `git diff`, which is why binding to the
# SUBCOMMAND is sound where CP-8a's review proved binding to the TARGET was not.
_cp8b_git_sub() {
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  [ $# -gt 0 ] && shift          # drop `git`
  _gs=''
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|-C|--git-dir|--work-tree|--exec-path|--namespace)
        [ $# -ge 2 ] || break
        shift 2; continue ;;
      --git-dir=*|--work-tree=*|--exec-path=*|--namespace=*)
        shift; continue ;;
      -p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs)
        shift; continue ;;
      -*) _gs=''; break ;;       # an unknown global option -> unresolvable -> fail closed
      *)  _gs=$1; break ;;
    esac
  done
  [ "$_pg" = 1 ] || set +f
  printf '%s' "$_gs"
}

# _cp8b_git_target_is_cp "<sub>" "<seg>": 0 iff the git WRITE subcommand's own destination is a
# control-plane target. Each subcommand names its destination differently - that is the whole point of
# target-binding, and why a flat regex could never do this.
_cp8b_git_target_is_cp() {
  _gsub=$1
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $2
  _hit=1; _seen=0
  case "$_gsub" in
    archive)
      # `git archive` writes a file ONLY via -o / --output; without it, it streams to stdout.
      # Separated (`-o x`), `=`-joined (`-o=x`, `--output=x`), and short-JOINED (`-ox`) forms all bind.
      while [ $# -gt 0 ]; do
        case "$1" in
          -o|--output)
            if [ $# -ge 2 ] && _cp8b_tok_is_cp "$2"; then _hit=0; break; fi ;;
          --output=*)
            if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
          -o?*)
            _ov=$(_cp8b_dequote "${1#-o}"); _ov=${_ov#=}
            [ -n "$_ov" ] && is_control_plane_target "$_ov" && { _hit=0; break; } ;;
        esac
        shift
      done ;;
    bundle|worktree)
      # `git bundle create <file> <rev>` · `git worktree add [-b <branch>] <path> [<commit>]`.
      # Scan EVERY non-flag token after the marker, not just the first: a flag that takes a VALUE
      # (`git worktree add -b br conformance/wt`) consumes the first slot, so a "first non-flag token"
      # heuristic checks `br` and never sees the real path. Over-scanning can only ADD denies.
      # Only `create`/`add` write into a new path; bundle verify/list and worktree list/prune do not.
      # (The orchestrator uses `git worktree add /tmp/…` on every fan-out, so this MUST stay allowed
      # outside the control plane — corpus family D locks that.)
      while [ $# -gt 0 ]; do
        if [ "$_seen" = 1 ]; then
          case "$1" in
            -*) : ;;
            *) if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
          esac
        fi
        case "$1" in create|add) _seen=1 ;; esac
        shift
      done ;;
    init|clone|checkout|restore)
      # init: [<dir>] · clone: <src> <dir> · checkout/restore: pathspecs (they OVERWRITE the worktree).
      # Any non-flag token naming a control-plane path is a write target. `git checkout -b fix/x` has
      # no such token -> allowed (the A4 false positive).
      [ $# -gt 0 ] && shift      # drop `git`
      [ $# -gt 0 ] && shift      # drop the subcommand
      while [ $# -gt 0 ]; do
        case "$1" in
          -*) : ;;
          *) if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
        esac
        shift
      done ;;
  esac
  [ "$_pg" = 1 ] || set +f
  return $_hit
}

# _cp8b_git_write_denied "<seg>": PREDICATE - returns 0 (TRUE, "deny this") and prints the reason, or 1
# (allow). Note the inverted convention vs. the guard_check_* API: this is an internal predicate, named
# so at the call site.
#
# `-o` is --output (a WRITE) for `git archive` and --only (a READ) for `git commit`. That ambiguity is
# why the flat rule could not resolve it, and why `git commit -m "... --output ..."` was a false
# positive (CP-8a's recorded residual). Subcommand-binding resolves it.
_cp8b_git_write_denied() {
  _ws=$1
  [ "$(_cp8b_lead "$_ws")" = git ] || return 1
  _wsub=$(_cp8b_git_sub "$_ws")
  case "$_wsub" in
    archive|bundle|worktree|init|clone|checkout|restore) : ;;
    diff|log|show|format-patch)
      # The diff machinery honors --output=<file>: an arbitrary file WRITE/TRUNCATE with NO shell
      # redirect, which slips every redirect guard. Denied OUTRIGHT - NO target is parsed, because a
      # quoted / escaped / substituted target evades a byte match while git writes the real path (a live
      # bypass caught in CP-8a re-review). Unchanged from CP-8a; only its SCOPE narrows, from "any git"
      # to "the subcommands that actually honor the flag".
      # Match --output (space/=/joined) AND -o (space, or JOINED value `-oconformance`). This is an
      # OUTRIGHT deny with no target parsed, so a joined value cannot smuggle a write past it.
      if printf '%s' "$_ws" | grep -Eq '(^|[[:space:]])(--output([=[:space:]]|$)|-o([[:space:]]|$|[^[:space:]]))'; then
        printf '13: git %s --output/-o writes an arbitrary file via the diff machinery (defeats the shell-redirect guards) - human-gated. Redirect to a non-control-plane path instead (git diff > /tmp/x), or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
        return 0
      fi
      return 1 ;;
    *) return 1 ;;
  esac
  # A write subcommand. Unparseable target => we CANNOT prove it lands outside the control plane => DENY
  # OUTRIGHT (fail-closed). See _cp8b_unparseable for why this specific clause is the attack surface.
  if _cp8b_unparseable "$_ws"; then
    printf '13: git %s with an unresolvable (variable/substituted) target cannot be proven to land outside the control plane - denied (fail-closed). Use a literal path, or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
    return 0
  fi
  if _cp8b_git_target_is_cp "$_wsub" "$_ws"; then
    printf '13: git %s would write into the control plane (guard / CI gates / conformance) - denied (control-plane integrity). Target a path outside the control plane, or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
    return 0
  fi
  return 1
}

# _cp8b_scan_denied "<seg>": PREDICATE - today's CO-OCCURRENCE rule, applied to ONE segment. This is the
# fail-closed floor for every segment whose lead is an interpreter, a wrapper, or simply unrecognized.
# Extended in exactly one direction - it now also matches a BARE control-plane directory token - which
# can only ADD denies (monotone).
# _cp8b_redirect_hits_cp "<segment>": does any REDIRECT TARGET in this segment land on a control-plane
# path? Derived from is_control_plane_path / is_control_plane_target — the SINGLE SOURCE OF TRUTH —
# rather than a second, hand-maintained inventory.
#
# WHY: the redirect arm used to carry its own regex alternation listing control-plane paths. It drifted
# from the classifier by construction, and the drift was measured: `echo evil > scripts/dora.sh`,
# `> scripts/agent-scorecard.sh`, `> scripts/new-adapter.sh`, `> scripts/postmortem.sh`,
# `> scripts/sparkwright`, `> scripts/fixtures/*` and three more were ALLOWED while classifying
# control-plane at the gate. Adding names closed nine and left nine — "a named set with no
# family-completeness lock rots by construction". Deriving the answer cannot drift.
#
# Targets are extracted after `>` or `>>`, with any fd digit and surrounding whitespace stripped, and
# quotes removed so `> "conformance/x.sh"` is seen. Case folding is inherited from the classifier.
# _redir_targets "<segment>": GUARD-CP-WRITE-ROUTES Cure 2 (Route 2) — the SHARED redirect-target
# EXTRACTION + POSITIVE literal-path allowlist disqualifier, called by BOTH redirect bail sites
# (_cp8b_redirect_hits_cp and _cp8b_tad_redir_cp) so the extraction and the disqualifier cannot drift.
# Each caller keeps its OWN classification loop (composed-vs-plain); this helper only produces the
# candidate literal targets and signals a disqualifying non-literal.
#
# Prints each SAFE (allowlist-clean) target on its own line. Return code:
#   0 = clean — every extracted target is a plain literal (or an fd-dup, which is excluded);
#   2 = a NON-LITERAL target was seen — the caller MUST bail to the deny side (fail-closed): the
#       guard cannot prove an unresolvable $(…)/$VAR/glob/backslash target is not control-plane.
# THE DISQUALIFIER IS A POSITIVE ALLOWLIST, not a bad-byte denylist: a target is recognized safe ONLY
# if every byte is in `[A-Za-z0-9._/@:+=,-]`; anything else ($ backtick * ? [ { ~ \ space etc.)
# disqualifies. A denylist lost twice here — `$`/backtick failed open on globs, an 8-byte set failed
# open on backslash (`hooks\/pre-push`). The allowlist closes the class definitively.
# fd-dups (`2>&1`, `>&2`, `N>&M`) extract to `&N` tokens, and an `&`-led token is EXCLUDED from the
# scan — otherwise a naive allowlist would spuriously disqualify legitimate fd-dups (over-deny).
# DISCLOSED RESIDUAL, not masked (security seat C1, MED): the `&`-exclusion is BROADER than true
# fd-dups. bash's `>&<word>` combined-redirect with a NON-NUMERIC word writes a FILE, but its
# `&<word>` token is `&`-led and so is dropped here too — meaning `_redir_targets` NEVER scans a
# combined-redirect target. A combined-redirect to a control-plane target is therefore not caught by
# THIS arm; it is only ever denied when another arm (the pathhit substring / token walk) independently
# catches the literal, so a spelling that evades those would slip through as an ALLOWED CP-write. This
# is PRE-EXISTING (the old extraction produced the same `&`-led token) and OUTSIDE the two routes this
# slice closes; the functional cure is boarded as its own deny-side slice,
# GUARD-REDIRECT-FD-DUP-COMBINED-BYPASS. Named here so the `&`-exclusion cannot read as complete.
# The split runs under `set -f` (globbing off) with the caller's `-f` state restored, so a `*` target
# is judged as raw text before any pathname expansion.
_redir_targets() {
  case "$1" in *'>'*) : ;; *) return 0 ;; esac
  _rt=$(printf '%s' "$1" | tr '\n' ' ' | sed -e 's/[0-9]*>>*/\n/g' | sed -e '1d' \
        -e 's/^[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//')
  [ -n "$_rt" ] || return 0
  _rtc=0
  _rtg=0; case "$-" in *f*) _rtg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_rt
  while [ $# -gt 0 ]; do
    _rtk=$1; shift
    [ -n "$_rtk" ] || continue
    case "$_rtk" in
      # GUARD-DENY-TRIO M1: a post-`&` token that is ALL-DIGITS (`>&1`, `N>&M`) or `-` (`>&-`) is a
      # true fd-dup/close — not a filesystem target — and stays excluded (the 14 relief forms). A
      # NON-NUMERIC word (`>&conformance/verify.sh`, `>&hooks/pre-pus*`, `>&$VAR`) is bash's combined-
      # redirect FILE write: strip the `&` and let it fall through to the literal/allowlist classifier
      # below, so a literal CP target denies and a glob/$VAR target fails closed (rc 2). This narrows the
      # previously-broad `&`-exclusion (disclosed residual C1) without disturbing any fd-dup form.
      '&'*)
        _rtd=${_rtk#&}
        case "$_rtd" in
          ''|-) continue ;;                             # >&-  / bare & — close/dup, never a file target
          *[!0-9]*) _rtk=$_rtd ;;                        # >&<non-numeric word> — a combined-redirect write
          *) continue ;;                                # >&N (all-digits) — fd-dup, never a file target
        esac ;;
    esac
    case "$_rtk" in
      # GUARD-READONLY-FP-RELIEF Arm G(ii) — a `~`-ROOTED target is a LITERAL for this classifier.
      # `~` was outside the allowlist, so every out-of-repo scratch append (`printf x >> ~/notes.txt`)
      # disqualified and the Cure-2 launder arm denied it. Unlike `$VAR`, a `~` target shows every
      # byte after the home root LITERALLY, so it is control-plane-CHECKABLE — and it is checked:
      # `is_control_plane_target` classifies the `~/…` spelling directly (measured), so
      # `> ~/proj/.claude/settings.json` still denies via the callers' own CP test.
      # ***THE `$VAR` FORM IS DELIBERATELY NOT HERE*** (security vet H1): with the DIRECTORY in the
      # variable, the visible suffix (`pre-push`, `settings.json`, `reviewer.agent.md`) does not
      # self-classify, so relieving it would partially revert the Cure-2 closure — a deny-side
      # weakening inside a false-positive slice. The `$SCRATCH` idiom is answered by a TIP instead.
      # Declines (fall through to rc 2, fail-closed): a `..` byte anywhere in the suffix (it climbs
      # out of $HOME, so the target is no longer shown literally); any non-literal byte after the `~`
      # (a glob/backslash/substitution); and — the design's "cannot SEGMENT-MATCH a control-plane
      # path" condition — any `~` target that trips `_cp8b_pathhit`.
      # ⚠️ THE `_cp8b_pathhit` DISQUALIFIER IS LOAD-BEARING AND WAS FOUND BY A FLOOR REGRESSION, not
      # by design. `is_control_plane_target` ALONE is not enough: `GUARD-CLAUDE-HOME-INSTRUMENTATION-FP`
      # relieved `.claude/plans/*` and `.claude/projects/*` from the CLASSIFIER (a path-route relief),
      # while agent-autonomy.sh pins `echo x >> ~/.claude/plans/x.md` DENY on the COMMAND route as a
      # deliberate retained false positive. With only the classifier consulted, this arm would have
      # silently flipped that pinned decision — a deny-side change belonging to that slice, not this
      # one. `_cp8b_pathhit` is the segment matcher, it still hits the whole `.claude` family, and it
      # keeps every one of those legs green (measured). Widening this arm past `_cp8b_pathhit` is a
      # deny-side decision and needs its own slice.
      # REVIEW I3 (2026-08-19): a HOME-ROOT DOTFILE (`~/.gitconfig`, `~/.config/git/config` — where
      # core.hooksPath ALSO lives — `~/.zshrc`, `~/.ssh/authorized_keys`) moved DENY->ALLOW here,
      # undisclosed: these are not repo control-plane so `_cp8b_pathhit` misses them, but a write to
      # them is a real out-of-repo escalation (`~/.config/git/config` reopens exactly the guard-disable
      # vector Arm F defends). Decline any `~/`-suffix whose FIRST byte after the home root is `.`
      # (the `/.*` glob on the `~`-stripped suffix). The three legit relief legs (`~/notes.txt`,
      # `~/scratch/out.txt`, `~/logs/verify.log`) do not start with `/.`, so they stay allowed.
      '~'|'~/'*)
        case "${_rtk#\~}" in
          *..*|*[!A-Za-z0-9._/@:+=,-]*|/.*) _rtc=2 ;;
          *) if _cp8b_pathhit "$_rtk"; then _rtc=2; else printf '%s\n' "$_rtk"; fi ;;
        esac ;;
      *[!A-Za-z0-9._/@:+=,-]*) _rtc=2 ;;                # NOT a plain literal -> disqualify (fail-closed)
      *) printf '%s\n' "$_rtk" ;;
    esac
  done
  [ "$_rtg" = 1 ] || set +f
  return $_rtc
}

_cp8b_redirect_hits_cp() {
  _rh=$1
  case "$_rh" in *'>'*) : ;; *) return 1 ;; esac
  _rt=$(_redir_targets "$_rh") || return 0   # rc 2 => a non-literal target => fail closed (K-R1b)
  [ -n "$_rt" ] || return 1
  _rg=0; case "$-" in *f*) _rg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_rt
  while [ $# -gt 0 ]; do
    if [ -n "$1" ] && { is_control_plane_path "$1" || is_control_plane_target "$1"; }; then
      [ "$_rg" = 1 ] || set +f
      return 0
    fi
    shift
  done
  [ "$_rg" = 1 ] || set +f
  return 1
}

# _cp8b_pathhit "<segment>": 0 iff a control-plane path appears anywhere in the segment TEXT (the
# string-level basis). SINGLE SOURCE OF TRUTH — called by both the old verb-arm (_cp8b_scan_denied)
# and the new resolved-target arm (_cp8b_target_arm_denied), so the regex cannot drift between them.
# The regex is byte-identical to the inline form _cp8b_scan_denied carried before the target-arm fold
# (GUARD-BASENAME-AFTER-CD-BYPASS), so the old arm's verdict is unchanged. It is REQUIRED for the lifted
# gate: the P0 case `python3 -c "open('hooks/pre-push','w')"` hides the path inside interpreter syntax
# the token split cannot see, but this substring grep does.
# GUARD-HOOKSPATH-CASE-BYPASS (seat MEDIUM, characterized): the alternation is split into the same
# TWO TIERS `is_control_plane_path` already established (:64-98) — reused here, not reinvented, so
# the fold rationale cannot drift between the two matchers. TIER 1 (kit-owned, unambiguous names —
# `.claude`, CODEOWNERS, `.git`, hooks/pre-push, the enumerated `.kit/*.conf` + named scripts, the
# scanner-ignore files, and `agents/*.agent.md`, which is already unconditional in
# `is_control_plane_path`'s own Tier 1) folds on EVERY platform: no adopter coincidentally names a
# different thing `.CLAUDE` or `HOOKS/PRE-PUSH`. TIER 2 (the generic directory prefixes `skills/`,
# `conformance/`, `adapters/`) folds ONLY when `_fs_case_insensitive` — folding it unconditionally
# would reintroduce the EXACT false-positive `is_control_plane_path`'s own A2 fix measured and closed
# (`src/Adapters/Repo.cs`, `Skills/Onboarding.cs` are legitimate adopter code on a case-sensitive
# filesystem). `_fs_case_insensitive` is sound here for the SAME reason it is sound for
# `is_control_plane_path`: these are repo-relative prefixes, always judged against the tree the guard
# itself sits on — not an arbitrary absolute path that could live on a different mounted volume (the
# reason a filesystem probe was REJECTED for the `.env` secret arm, design §3 resolution (B)).
# GUARD-PATH-ENUMERATION-INCOMPLETE S1 — THE `.claude` LEG IS LEFT-ANCHORED, AND THE ANCHOR CLASS IS
# PINNED. The leg used to be `\.claude(/|…)` with NO left anchor, so it matched `foo.claude/` and
# `v2.claude/` — the same `<x>.claude/...` false positive the path globs carried. Relieving it on the
# path route ALONE would have been worse than leaving it: the redirect/cmd route would keep denying an
# ordinary adopter file while the acceptance criterion greened on the path route (route-split relief).
# ⚠️ THE ANCHOR IS `(^|[^A-Za-z0-9._-])`, NOT `(^|/)`. Do NOT transplant the path-glob phrasing "at the
# start or after a /" into this regex: it matches COMMAND TEXT, not a path. `(^|/)` would drop the
# quoted (`".claude/x"`), post-space (`verb .claude/x`) and post-`=` (`--out=.claude/x`) spellings out
# of pathhit entirely — and for the interpreter form `python3 -c "open('.claude/settings.json','w')"`
# pathhit is the ONLY arm that fires (the token walk cannot see a path inside the parentheses), so
# `(^|/)` would re-open that P0 class outright. The class excludes every byte that can end a FILENAME
# (letters, digits, `.`, `_`, `-`), so `foo.claude/` and `v2.claude/` relieve while start-of-string,
# post-`/`, post-space, post-quote, post-`=`, post-`:` all still deny. Corner-spelling DENY fixtures and
# sibling ALLOW fixtures both live in conformance/agent-autonomy.sh; this narrowing is a deny
# RELAXATION and carries its own fixtures and its own monotonicity run, per the standing rule.
# AGENTS.md and REQUIRED-CHECKS.md use the CODEOWNERS-style anchor `(^|[^a-zA-Z.])`: an unanchored
# `agents\.md` would substring-match `subagents.md`.
# ⚠️ `.gitattributes` IS LEFT-ANCHORED WITH THE PINNED CLASS, NOT LEFT BARE. It shipped as a plain
# substring in the first cut of this slice, copied from the `.gitleaksignore` precedent — and that was
# an UNDECLARED deviation from the design, which specifies segment-anchored membership. It produced a
# measured ROUTE SPLIT: `foo.gitattributes` and `docs/my.gitattributes` ALLOWED at the Write/Edit path
# route (the globs `​.gitattributes|*/.gitattributes` are already segment-exact) while DENYING here under
# any unrecognized lead verb. The precedent did not transfer: nothing is plausibly named
# `foo.gitleaksignore`, but `<tool>.gitattributes` is an ordinary generated-file spelling. Anchoring
# aligns this leg with the globs it is supposed to mirror; the class is the same one the `.claude` leg
# pins, so start-of-string, post-`/`, post-space, post-quote, post-`=` and post-`:` all still deny.
# ⚠️ INHERITED-ANCHOR FACE, DECLARED (M3): the CODEOWNERS class `(^|[^a-zA-Z.])` admits `-`, so
# `SUB-AGENTS.md` DENIES here while the path route ALLOWS it (the glob `agents.md|*/agents.md` is
# segment-exact). That asymmetry is inherited from the CODEOWNERS convention this leg copies, not
# introduced by it, and it is fail-SAFE in the direction it errs. It is stated rather than fixed
# because narrowing the shared CODEOWNERS anchor class is a change to an existing deny with its own
# fixtures and its own monotonicity run — not a tidy-up to ride along here.
_CP8B_PATHHIT_T1='((^|[^A-Za-z0-9._-])\.claude(/|[[:space:]]|$)|\.github/workflows|/CODEOWNERS|(^|[^a-zA-Z.])CODEOWNERS|(^|[^a-zA-Z.])AGENTS\.md|(^|[^a-zA-Z.])REQUIRED-CHECKS\.md|(^|[^A-Za-z0-9._-])\.gitattributes|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard|docs/governance/\.meta-control-last|docs/governance/meta-control-log\.md|\.kit/budget\.conf|\.kit/roster\.conf|\.kit/model-map\.conf|\.kit/model-tiers\.conf|\.kit/dials\.conf|scripts/model-tier\.sh|scripts/orchestrator-run\.sh|agents/[^[:space:]]*\.agent\.md|scripts/release-tag\.sh|scripts/promotion-verify\.sh|scripts/escalate\.sh|\.gitleaks\.toml|\.gitleaksignore|\.semgrepignore|\.trivyignore|\.checkov\.yaml|\.checkov\.yml)'
_CP8B_PATHHIT_T1_LC='((^|[^A-Za-z0-9._-])\.claude(/|[[:space:]]|$)|\.github/workflows|/codeowners|(^|[^a-z.])codeowners|(^|[^a-z.])agents\.md|(^|[^a-z.])required-checks\.md|(^|[^A-Za-z0-9._-])\.gitattributes|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard|docs/governance/\.meta-control-last|docs/governance/meta-control-log\.md|\.kit/budget\.conf|\.kit/roster\.conf|\.kit/model-map\.conf|\.kit/model-tiers\.conf|\.kit/dials\.conf|scripts/model-tier\.sh|scripts/orchestrator-run\.sh|agents/[^[:space:]]*\.agent\.md|scripts/release-tag\.sh|scripts/promotion-verify\.sh|scripts/escalate\.sh|\.gitleaks\.toml|\.gitleaksignore|\.semgrepignore|\.trivyignore|\.checkov\.yaml|\.checkov\.yml)'
# TIER 2 gains `scripts/` and `profiles/` — the redirect-route half of the directory families added to
# `_cpp_match`. They land HERE and never in T1, for the identical reason: T1 folds on every platform,
# and an unconditionally-folded `scripts/` would reinstate the measured case-sensitive FP class on the
# cmd route one argument position to the left of where `_cpp_match` closed it.
# ⚠️ THE TWO NEW LEGS ARE LEFT-ANCHORED; the three older ones are not. This is deliberate and it is
# NOT a drive-by symmetry to "finish": these families are SEGMENT properties, and a bare substring
# `scripts/` would deny `myscripts/x.sh` — an ordinary adopter directory that merely ends in the family
# name, i.e. the `my.claude/` false positive rebuilt in a new matcher. The anchor admits `/` (so a real
# `frontend/scripts/build.js` segment still denies, as the design's consequences disclose) and every
# quote/space/`=` lead-in, while excluding filename-tail bytes. Anchoring the three EXISTING legs would
# be a deny RELAXATION on skills/conformance/adapters, which needs its own fixtures and its own
# monotonicity run — it is a separate change, not a tidy-up, and it is not made here.
_CP8B_PATHHIT_T2='(skills/[^[:space:]]*|conformance/[^[:space:]]*|adapters/[^[:space:]]*|(^|[^A-Za-z0-9._-])scripts/[^[:space:]]*|(^|[^A-Za-z0-9._-])profiles/[^[:space:]]*)'
_cp8b_pathhit() {
  printf '%s' "$1" | grep -Eq "${_CP8B_PATHHIT_T1}|${_CP8B_PATHHIT_T2}" && return 0
  # Arm 1 above is byte-identical to the pre-fold regex and returns first (the `_under_temp`
  # add-only shape at :309-328) — this can only ever ADD a pathhit. HOT PATH (Fix 2, dual-review
  # round): guard on an UPPERCASE byte only (`*[A-Z]*`), mirroring `is_control_plane_path:93` — `tr
  # 'A-Z' 'a-z'` cannot change a string that has no uppercase byte, so an all-lowercase command (the
  # common case, on every Bash call) pays zero extra subprocess. `*[A-Za-z]*` (ANY letter) was wrong:
  # it forked `tr`+`grep` on nearly every ordinary lowercase command, since almost every command has
  # a letter somewhere.
  case "$1" in *[A-Z]*) : ;; *) return 1 ;; esac
  _phl=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  printf '%s' "$_phl" | grep -Eq "$_CP8B_PATHHIT_T1_LC" && return 0
  _fs_case_insensitive && printf '%s' "$_phl" | grep -Eq "$_CP8B_PATHHIT_T2"
}

_cp8b_scan_denied() {
  _ss=$1
  _pathhit=1
  if _cp8b_pathhit "$_ss"; then
    _pathhit=0
  else
    # bare control-plane DIRECTORY token (the D1 gap): `bash -c "mv conformance /tmp"`.
    _pg=0; case "$-" in *f*) _pg=1 ;; esac
    set -f
    # shellcheck disable=SC2086
    set -- $_ss
    while [ $# -gt 0 ]; do
      if _cp8b_tok_is_cp "$1"; then _pathhit=0; break; fi
      shift
    done
    [ "$_pg" = 1 ] || set +f
  fi
  [ "$_pathhit" = 0 ] || return 1
  # A2 (case) — the REDIRECT arm is a matcher of its own and was still byte-literal. Measured before
  # this fold: `echo evil > .claude/settings.json` DENY but `> .Claude/settings.json` ALLOW; `> CODEOWNERS`
  # DENY but `> codeowners` ALLOW — the sharper one, because A2 ADDED `codeowners` to the classifier, so
  # the class said control-plane while the guard still permitted the redirect write. Fold the scanned
  # segment once here (the alternation below is authored lowercase to match), rather than duplicating
  # case variants into an already-dense regex. `_ssl` is used ONLY for these greps; every message and
  # every other decision still reads the original `$_ss`.
  _ssl=$_ss
  case "$_ss" in *[A-Z]*) _ssl=$(printf '%s' "$_ss" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
  # VERBS FOLD TOO. On a case-insensitive filesystem `/bin/RM` resolves to `/bin/rm`, so a byte-literal
  # verb match is the same defect as a byte-literal PATH match, one argument position to the left.
  # Measured before this fold: `rm -rf conformance` DENY but `RM -rf conformance` ALLOW; likewise
  # `MV conformance /tmp/x`, which relocates every gate in the repo — the exact command the
  # is_control_plane_target comment exists to deny. `_ssl` is already computed above.
  if printf '%s' "$_ssl" | grep -Eq '(^|[^[:alnum:]_])(rm|rmdir|mv|cp|truncate|shred|chmod|chown|dd|sed|tee|ln|install|patch)[[:space:]]' \
     || printf '%s' "$_ssl" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+(checkout|restore)([[:space:]]|$)' \
     || _cp8b_redirect_hits_cp "$_ss"; then
    return 0
  fi
  return 1
}

# _cp8b_deny_reason "<seg>": print the control-plane deny reason, NAMING the offending segment. Every
# non-git-write deny arm calls this so the block never denies with a BLANK reason (a regression the
# security + code reviews both caught: `main` always printed the `13: … KIT_GUARD_SELFEDIT=1 …` guidance,
# and an empty reason leaves a blocked agent with no explanation and no override hint - in an ERGONOMICS
# slice). The segment name closes the CP-8a section-1.2 UX gap (a denied COMPOUND gave no signal about
# WHICH part offended). Truncated so a pathological segment cannot flood the reason channel.
# _cp8b_message_tip: DRIFT-2. When the RAW command is a git/gh message-carrying invocation, a
# control-plane deny is most often a MULTILINE MESSAGE BODY being segmented on its newlines and scanned as
# code — the message DATA mis-read as a command. The guard does NOT relax the decision (a quote-aware
# segmenter would fail OPEN: it could miss a real `; rm -rf` split); instead it NAMES the safe escape, which
# passes the body from a FILE and cannot execute. This is ADDITIVE to the reason text only — it changes no
# deny/allow verdict, and it is harmless on a genuine attack (the command is still denied; the tip helps no
# bypass). Reads $_cp8b_raw, set at the top of _cp8b_control_plane_denied (its only caller of this arm).
# GUARD-READONLY-FP-RELIEF (the (c′) tip-loss fix + the §3 kept-denied tips). TWO ARGUMENTS now:
#   $1 = the RAW command   — the right key for whole-command shapes (a message body, a heredoc, a
#                            loop head, a quoted alternation) that SPAN segments
#   $2 = the OFFENDING SEGMENT — the right key for lead-verb shapes. Keying these on the RAW was a
#                            measured defect: `cd x && sed -n … <cp>` lost the head/tail escape hint
#                            because the raw lead was `cd`, i.e. the tip disappeared exactly when a
#                            compound made the deny hardest to read. Defaults to $1 for old callers.
# Every arm here is ADDITIVE TO REASON TEXT ONLY — no verdict moves, and naming an escape helps no
# bypass (the command is still denied). The first matching arm returns, so the arms stay exclusive.
_cp8b_message_tip() {
  _mt_raw=$1; _mt_seg=${2:-$1}
  case "$_mt_raw" in
    *"git commit"*|*"git merge"*|*"git tag"*|*"git notes"*|*"gh pr"*|*"gh issue"*|*"gh release"*)
      printf ' TIP: a multi-line commit/PR message body is scanned as data and can trip this; pass it from a FILE instead of an inline -m/--body — `git commit -F <file>` or `gh pr create --body-file <file>` (the file content is never executed).'
      return ;;
  esac
  # Arm E's DECLINE cases land here: the heredoc body was NOT excluded (unquoted delimiter, `<<-`,
  # >1 heredoc, an ambiguous terminator) so its lines were scanned as code. Name the cure.
  case "$_mt_raw" in
    *'<<'*)
      printf ' TIP: a heredoc BODY is scanned as data-mistaken-for-code unless it is inert. Use a quoted heredoc delimiter (`<<'"'"'EOF'"'"'` or `<<"EOF"`, terminator on its own line, no `<<-`), or pass the content from a file — an unquoted or tab-stripped delimiter cannot be bounded safely, so it stays scanned.'
      return ;;
  esac
  # §3 kept-denied, keyed on the RAW LEAD because the offending segment is a FRAGMENT of the
  # construct (a quoted `|` over-splits; a loop BODY is its own segment).
  _mt_rl=$(_cp8b_lead "$_mt_raw")
  case "$_mt_rl" in
    grep|egrep|fgrep|rg)
      case "$_mt_raw" in
        *'|'*)
          printf ' TIP: a quoted alternation/pipe is scanned as a command SEPARATOR (segmentation is deliberately quote-blind — a quote-aware split fails OPEN on a real `; rm -rf`). Use one pattern per invocation, `grep -e A -e B`, or the Grep tool. escape card: docs/operations/runtime-guards.md §Over-deny'
          return ;;
      esac ;;
    for|while|until)
      printf ' TIP: a loop over control-plane paths is scanned per segment and the loop HEAD carries the whole deny (relieving it segment-locally would allow a mass-delete body). Use the Read/Grep tool, or one invocation per file. escape card: docs/operations/runtime-guards.md §Over-deny'
      return ;;
  esac
  # DRIFT-2b: a read-oriented sed/awk/… on a control-plane path is denied because these tools carry write/exec
  # escapes (`sed s///e`/`w`, `awk system()`); NAME the escape-free paths. Detect the LEAD VERB (not a
  # substring — a message body mentioning "sed" must not trigger this). Names BOTH read and edit exits, so it
  # is accurate whether the operator meant `sed -n` (read) or `sed -i` (edit) — no program sub-parse.
  # GUARD-READONLY-FP-RELIEF: keyed on the OFFENDING SEGMENT's lead, not the raw lead (the (c′) fix).
  _mt_lead=$(_cp8b_lead "$_mt_seg")
  case "$_mt_lead" in
    # GUARD-READ-LANE-2 F-e — `find` gets its own clause, because the shared one below names the
    # sed/awk grammars and would have sent a `find` user to a form that cannot express their query.
    # The escape it names is the ALLOWLIST ITSELF: what declined was a primary the guard does not carry.
    find)
      printf ' TIP: find is denied on control-plane paths (it carries write and exec escapes — `-delete`, `-exec`, `-fprint`) EXCEPT when EVERY primary is on a declared read-only ALLOWLIST (`-name -iname -path -ipath -regex -iregex -type -maxdepth -mindepth -mtime -mmin -newer -size -empty -print -print0 -prune -depth -L -H -P -xdev -o -a -not ! ( )`), with no redirect and no unresolved expansion — so what declined here is usually a primary NOT on that list (`-ls`/`-printf` are off it deliberately) — but an operand can decline too: an unresolved expansion (`-name "$P"`), a redirect or segmenter byte, or a `-`-led operand that is not numeric. Re-spell with an allowlisted primary and a literal operand, or use the Glob/Grep tool.'
      return ;;
    sed|awk|sort|uniq|less|more|xxd)
      printf ' TIP: %s is denied on control-plane paths (write/exec escapes) EXCEPT in one exact read grammar — `sed -n <n>[,<m>|,$]p <path>` and `awk <NR-comparison>|{print} [-F<sep>] <path>`, no other flag, one script/program token, no redirect. For a plain READ use that form, head/tail/cat, or the Read tool; to EDIT a control-plane file use the Edit/Write tool in a dev-clone (never via shell). escape card: docs/operations/runtime-guards.md §Over-deny' "$_mt_lead"
      return ;;
    python|python3|node|ruby|perl|source|.)
      printf ' TIP: an interpreter'"'"'s arguments are treated as code, never as data, so a control-plane path inside them cannot be cleared. Use the Read tool, or run the program from a file that names no control-plane path. escape card: docs/operations/runtime-guards.md §Over-deny'
      return ;;
    sh|bash|dash|zsh|ksh)
      case " $_mt_seg " in
        *' -c '*)
          printf ' TIP: an interpreter'"'"'s arguments are treated as code, never as data, so a control-plane path inside them cannot be cleared. Use the Read tool, or run the program from a file that names no control-plane path. escape card: docs/operations/runtime-guards.md §Over-deny'
          return ;;
      esac ;;
    *=*)
      printf ' TIP: an UNVETTED `NAME=value` prefix is not peeled before the scan (the vetted-name allowlist is deliberately closed — widening it per false positive is enumeration creep). Set the variable with `export` as a separate statement, or use a vetted name.'
      return ;;
  esac
}
# _cp8b_trigger_tip "<trigger>" "<segment>": the target-arm sites that had NO tip at all.
_cp8b_trigger_tip() {
  case "$1" in
    redir-nonliteral)
      printf ' TIP: the redirect TARGET is not a plain literal (a `$VAR`, glob, substitution or backslash), so the guard cannot tell whether it names a protected path — and it refuses to guess. Spell the redirect target literally (`> /tmp/out.txt`), use a `~/`-rooted path, or use the Write tool. escape card: docs/operations/runtime-guards.md §Over-deny' ;;
  esac
}
# GUARD-READ-LANE-2 F-h — THE KILL SWITCH IS NOT AN ANSWER TO A READ.
# Every control-plane deny used to end `Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.`
# For the kept-denied READ faces (§3 F-c unvetted `NAME=value`, F-d interpreter `-c`, F-f loop heads,
# and the quote-orphaned fragment an over-split leaves behind) that sentence is actively harmful advice:
# the operator wanted to LOOK at a file, and the guard's answer is "disarm me, globally, for the whole
# session." That is training an escape-hatch reflex for the one class of denial where a free escape
# already exists (the Read/Grep tool, one pattern per invocation, `export` as a separate statement) —
# and those escapes are already named in the tip. So the sentence is dropped when the OFFENDING SEGMENT
# is read-shaped, and kept when it is not. This moves NO VERDICT: it is reason TEXT only, at the two
# sites that carry a segment. `_cp8b_selfedit_hint` is keyed on the SEGMENT via `_cp8b_lead` — the same
# key `_cp8b_message_tip` uses after the (c′) fix — so the sentence and the tip can never disagree about
# which token they are talking about.
# The remaining SELFEDIT sentences in this file are deliberately untouched: they belong to arms with no
# offending segment at all (the Write/Edit tool arms, `git config core.hooksPath`, the git-write arm,
# the empty-reason fallbacks), and every one of those IS a write.
# ⚠️ `echo`/`printf` are EXCLUDED even though both sit in `_CP8B_READ_VERBS`. They are EMITTERS, not
# readers: their argument is text they PRODUCE, so `printf evil > pre-push` is a write and
# `echo "cp e <cp>" | sh` is the code-generation laundering face the T1 pipe rule exists for. Keying
# those on "the lead is in the read lexicon" would hand the kill-switch advertisement exactly to the
# shapes that are trying to write. The two piped-interpreter halves split on this byte and both are
# pinned in agent-autonomy.sh.
# ⚠️⚠️ `sed`/`awk`/`find`/`file` ARE DUAL-MODE AND THE LEAD ALONE CANNOT DECIDE. The first cut of this
# helper read the design's "…or `sed`/`awk`/`find`" as a lead test and dropped the sentence from
# `sed -i s/a/b/ <cp>` — a WRITE, and the acceptance cell caught it. These four verbs are in the
# read-shaped families for the read spelling ONLY; the write spelling of each (`sed -i`, `sed …w <cp>`,
# `awk '{print > "<cp>"}'`, `find … -delete/-exec`, `file -C -m <cp>` — the seat's finding 4) is exactly
# the case the kill switch IS for. So they are gated by a per-verb READ-FLAG ALLOWLIST plus a
# write-escape byte test, and ANY unrecognised flag DECLINES. The failure direction is deliberate and is
# the safe one: declining KEEPS the sentence, i.e. falls back to today's message. A denylist of write
# flags would fail the other way — open — on the next flag someone adds.
# FOLD-FORWARD, DISCHARGED: T6 and T7 built the verdict-bearing grammar recognisers
# (`_cp8b_seg_is_sed_n`, `_cp8b_seg_is_awk_range`, `_cp8b_seg_is_find_ro`) and this table's sed/awk/find
# copies were folded onto them, so there is nothing left for those three to drift from. What survives
# here is the `file` face and the write lexicon/flags below, which no recogniser owns.
_CP8B_FH_INTERP='python python3 perl ruby node sh bash dash zsh'
# (T4's `_CP8B_FH_FIND_RO` forward copy lived here and is GONE — T7 folded this face onto
# `_cp8b_seg_is_find_ro`'s `msg` tier, whose allowlist is the one at `_CP8B_FIND_RO_PRIMARIES`.)
# The WRITE lexicon this face declines on. REUSED, not re-derived: it is the CP verb arm's own mutation
# set (`mv|rsync|ln|rm|rmdir|shred|truncate|chmod|chown|tee|patch|dd|sed` + `cp|install`, :2657/:2659),
# which exists there as a `case` pattern and not as a variable — so it is transcribed here and the two
# must be kept in step. Adding a verb THERE without adding it here costs a lost sentence, never a lost
# deny. `sed` is the only member that is also a dual-mode READ verb, which is why the scan below exempts
# it in LEAD position only (`sed -n …` stays readable; `… | sed …` in any later position does not).
_CP8B_FH_WRITE_VERBS='mv rsync ln rm rmdir shred truncate chmod chown tee patch dd sed cp install'
# Write FLAGS: in-place editing and find's exec/delete primaries. `-i` shadows `file -i`'s entry in the
# read-flag allowlist below — a disclosed over-KEEP (`file -i <cp>` now keeps the sentence), taken
# deliberately because a `-i` denylist entry that carved out one verb would be the fail-open shape.
_CP8B_FH_WRITE_FLAGS='-i --in-place -exec -execdir -delete -ok -okdir'
# M3 — the save/set/restore `set -f` idiom, factored to one pair. NOT re-entrant, and since review
# round 2 that is ASSERTED rather than merely documented: `on` refuses when the save slot is already
# occupied (a nested on..off would clobber the outer caller's saved flag and leak `set -f`, or worse
# restore it early). Every caller handles the refusal by DECLINING in its own safe direction — which
# for this face means KEEPING the kill-switch sentence. `off` empties the slot so the next caller
# finds it free; the slot is a three-state (`''` free · `0` saved-clear · `1` saved-set).
_cp8b_setf_on()  { [ -z "${_cp8b_setf_prev:-}" ] || return 1
                   _cp8b_setf_prev=0; case "$-" in *f*) _cp8b_setf_prev=1 ;; esac; set -f; }
_cp8b_setf_off() { [ "${_cp8b_setf_prev:-0}" = 1 ] || set +f; _cp8b_setf_prev=''; }
# _cp8b_fh_write_escape "<s>": 0 iff <s> carries ANY write escape — a redirect byte, awk's `system(`/
# `getline`, an in-place/exec flag, or a mutation VERB in any token position. Tokens are de-quoted and
# BASENAMED first, so `/bin/rm` and `"rm"` are the same token as `rm`; that is what makes the test hold
# on a program passed to an interpreter as one quoted `-c` argument as well as on a bare segment.
_cp8b_fh_write_escape() {
  case "$1" in *'>'*|*'system'*|*'getline'*) return 0 ;; esac
  _cp8b_setf_on || return 0            # slot busy -> decline -> "write escape" -> the sentence stays
  _fwf=1
  # shellcheck disable=SC2086  # word-splitting the segment into tokens IS the walk
  set -- $1
  for _fwt in "$@"; do
    _fwd=$(_cp8b_dequote "$_fwt"); _fwd=${_fwd##*/}
    if [ "$_fwf" = 1 ]; then
      _fwf=0
      [ "$_fwd" = sed ] && continue      # dual-mode in LEAD position only — see the note above
    fi
    if _cp8b_in_list "$_fwd" "$_CP8B_FH_WRITE_VERBS" || _cp8b_in_list "$_fwd" "$_CP8B_FH_WRITE_FLAGS"
    then _cp8b_setf_off; return 0; fi
  done
  _cp8b_setf_off
  return 1
}
# _cp8b_fh_strip_prefix "<seg>": <seg> with leading `NAME=value` tokens and a leading quote-orphaned
# token removed. Prints the remainder, which may be EMPTY (the bare-prefix / bare-orphan face), and
# EXITS 0 only if it actually stripped something — the caller must not infer that from a string compare,
# because the remainder is re-joined on single spaces and would differ from a segment that merely
# carried a leading or doubled space.
_cp8b_fh_strip_prefix() {
  _cp8b_setf_on || { printf '%s' "$1"; return 1; }   # slot busy -> "stripped nothing", caller re-decides
  _spn=0
  # shellcheck disable=SC2086  # tokenising the segment IS the walk
  set -- $1
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*)   _spn=$((_spn + 1)); shift ;;
      [\'\"]*|*[\'\"]) _spn=$((_spn + 1)); shift ;;
      *) break ;;
    esac
  done
  _cp8b_setf_off
  printf '%s' "$*"
  [ "$_spn" -gt 0 ]
}
# _cp8b_fh_flags_ok "<seg>" "<allowed-flags>": 0 iff every `-`-led token after the lead is allowed.
# `-F:` / `-Fx` normalise to `-F` (awk's separator carries its value in the token).
_cp8b_fh_flags_ok() {
  _ffa=$2
  _cp8b_setf_on || return 1            # slot busy -> decline -> not read-shaped
  # shellcheck disable=SC2086  # word-splitting the segment into tokens IS the walk
  set -- $1
  shift 2>/dev/null || { _cp8b_setf_off; return 0; }
  for _fft in "$@"; do
    case "$_fft" in
      -F?*) _fft=-F ;;
      -*) : ;;
      *) continue ;;
    esac
    _cp8b_in_list "$_fft" "$_ffa" || { _cp8b_setf_off; return 1; }
  done
  _cp8b_setf_off
  return 0
}
# _cp8b_fh_first_operand "<seg>": the first non-flag token after the lead, with ONE matching surrounding
# quote pair stripped (both or none). Empty when there is none.
_cp8b_fh_first_operand() {
  _cp8b_setf_on || return 0            # slot busy -> print nothing -> the script grammar declines
  # shellcheck disable=SC2086  # tokenising the segment IS the walk
  set -- $1
  shift 2>/dev/null || { _cp8b_setf_off; return 0; }
  for _fot in "$@"; do
    case "$_fot" in -*) continue ;; esac
    case "$_fot" in
      "'"*"'") _fot=${_fot#\'}; _fot=${_fot%\'} ;;
      '"'*'"') _fot=${_fot#\"}; _fot=${_fot%\"} ;;
    esac
    printf '%s' "$_fot"
    break
  done
  _cp8b_setf_off
  return 0
}
# ⚠️⚠️ REVIEW ROUND 2 — A LOOP BODY IS A SEQUENCE OF COMMANDS, NOT ONE STRING. Round 1 judged the loop
# by running `_cp8b_fh_write_escape` over the WHOLE raw command, and that test counts a mutation verb in
# ANY token position. In a loop that is wrong in the over-KEEP direction: the body's own read verb takes
# a write verb as an OPERAND all the time, so `for f in <cp>*; do grep rm $f; done` and
# `for f in <cp>*; do sed -n 1p $f; done` — pure reads — were answered with "Set KIT_GUARD_SELFEDIT=1",
# the exact training this face exists to stop. So the raw is SPLIT into sub-segments and each is judged
# on its own LEAD, with the escape bytes/flags still tested anywhere inside it.
# THE WRAPPER LEXICON. `env`/`sudo`/`nice`/`xargs`/`sh -c` and friends do not run themselves — the verb
# is behind them, sometimes inside one quoted argument. For those leads the ANY-POSITION test is exactly
# right and is what is applied, so `do sudo rm $f; done` and `do sh -c "rm $f"; done` still KEEP.
_CP8B_FH_WRAP='env sudo doas nice ionice nohup command time timeout stdbuf setsid chroot su xargs busybox'
# The heads and inert keywords a split can leave as a sub-segment lead. They run nothing themselves.
_CP8B_FH_INERT='for while until if case select read : true false'
# _cp8b_fh_split_body "<raw>": the raw command as sub-segments, one per line. Splits on the separator
# TOKENS `;` `|` `&&` `||` `&` and on the shell words `do done then else elif fi { } ( )`, and on a
# trailing `;` glued to a token (`done`, `$f;`). Tokenising happens under `set -f` in this function's
# own on..off, and the whole thing is called from a `$( )` subshell so nothing leaks to the caller.
_cp8b_fh_split_body() {
  _cp8b_setf_on || return 1            # slot busy -> print nothing -> the caller reads that as an escape
  _fbc=''
  # shellcheck disable=SC2086  # splitting the raw into tokens IS the walk
  set -- $1
  for _fbt in "$@"; do
    _fbs=0
    case "$_fbt" in *';') _fbt=${_fbt%;}; _fbs=1 ;; esac
    case "$_fbt" in
      ''|';'|'|'|'&&'|'||'|'&'|';;'|do|done|then|else|elif|fi|esac|'{'|'}'|'('|')') _fbt=''; _fbs=1 ;;
    esac
    [ -z "$_fbt" ] || _fbc="${_fbc:+$_fbc }$_fbt"
    if [ "$_fbs" = 1 ]; then
      [ -z "$_fbc" ] || printf '%s\n' "$_fbc"
      _fbc=''
    fi
  done
  [ -z "$_fbc" ] || printf '%s\n' "$_fbc"
  _cp8b_setf_off
  return 0
}
# _cp8b_fh_seg_write "<sub-segment>": 0 iff THIS sub-segment carries a write escape. The order is the
# fail-closed one — escape bytes, then write FLAGS anywhere, then the LEAD (after the `NAME=value` /
# quote-orphan peel) decides the verb question. An UNKNOWN lead is a write (`$RM $f` keeps the
# sentence); a known READ verb is not, which is the operand relief this round is about.
_cp8b_fh_seg_write() {
  _fsw=$1
  [ -n "$_fsw" ] || return 1
  case "$_fsw" in *'>'*|*'system'*|*'getline'*) return 0 ;; esac
  _cp8b_setf_on || return 0
  # shellcheck disable=SC2086  # tokenising the sub-segment IS the walk
  set -- $_fsw
  for _fst in "$@"; do
    _fsd=$(_cp8b_dequote "$_fst"); _fsd=${_fsd##*/}
    if _cp8b_in_list "$_fsd" "$_CP8B_FH_WRITE_FLAGS"; then _cp8b_setf_off; return 0; fi
  done
  _cp8b_setf_off
  _fsr=$(_cp8b_fh_strip_prefix "$_fsw") || :
  [ -n "$_fsr" ] || return 1           # a bare prefix / bare orphan runs nothing
  _fsl=$(_cp8b_lead "$_fsr"); _fsl=$(_cp8b_dequote "$_fsl"); _fsl=${_fsl##*/}
  [ -n "$_fsl" ] || return 1
  _cp8b_in_list "$_fsl" "$_CP8B_FH_INERT" && return 1
  # The dual-mode verbs answer with their OWN grammar — the same one the top-level face uses, so a
  # `sed -n 1p $f` body reads and a `sed -n 's/x/y/w <cp>' $f` body writes.
  case "$_fsl" in
    sed|awk|find|file) _cp8b_seg_read_shaped "$_fsr" && return 1
                       return 0 ;;
  esac
  _cp8b_in_list "$_fsl" "$_CP8B_FH_WRITE_VERBS" && return 0
  if _cp8b_in_list "$_fsl" "$_CP8B_FH_WRAP" || _cp8b_in_list "$_fsl" "$_CP8B_FH_INTERP"; then
    _cp8b_fh_write_escape "$_fsr" && return 0
    return 1
  fi
  _cp8b_in_list "$_fsl" "$_CP8B_READ_VERBS" && return 1
  return 0                             # unknown lead -> fail closed -> the sentence stays
}
# _cp8b_fh_body_escape "<raw>": 0 iff ANY sub-segment of <raw> carries a write escape. An empty split
# (the `set -f` slot was busy, or the raw tokenised to nothing) counts as an escape — the safe way.
_cp8b_fh_body_escape() {
  _fbo=$(_cp8b_fh_split_body "$1")
  [ -n "$_fbo" ] || return 0
  while [ -n "$_fbo" ]; do
    case "$_fbo" in
      *"$_cp8b_nl"*) _fbl=${_fbo%%"$_cp8b_nl"*}; _fbo=${_fbo#*"$_cp8b_nl"} ;;
      *) _fbl=$_fbo; _fbo='' ;;
    esac
    _cp8b_fh_seg_write "$_fbl" && return 0
  done
  return 1
}
# ⚠️⚠️⚠️ THE LEAD NEVER DECIDES — REVIEW ROUND 1. The first cut applied the write-escape test ONLY to
# `sed|awk|find|file` and answered every other shape on its LEADING TOKEN. Three families of WRITE lost
# the kill-switch sentence, all measured DENY-without-it on the T4 build:
#   (a) any other read-verb lead plus a redirect — `cat /tmp/a > <cp>`, `jq . /tmp/a > <cp>`, `ls > <cp>`;
#   (b) an unvetted `NAME=value` prefix or a quote-orphaned first token, both of which returned
#       read-shaped BEFORE the verb behind them was ever looked at — `FOO=1 rm -rf <cp>`, `"x" cp … <cp>`;
#   (c) a loop HEAD, unconditionally — including `for f in .claude/hooks/*; do rm $f; done`, whose own
#       tip is warning about the very body that deletes the control plane.
# So the decision is now taken on the WHOLE SEGMENT, in this order, and every unknown DECLINES (declining
# KEEPS the sentence — the safe direction, unchanged):
#   1. a write escape ANYWHERE in the segment (redirect · system(/getline · in-place/exec flag ·
#      mutation verb in any token position) disqualifies FIRST, before any lead is consulted;
#   2. a `NAME=value` / quote-orphan prefix is STRIPPED and the REMAINDER must earn read-shaped on its
#      own (recursing once) — an empty remainder, or a single operand token with no verb at all, is the
#      genuine bare-prefix / bare-orphan face (R7 / R3) and stays read-shaped;
#   3. a loop head is read-shaped only if the RAW command — head AND body — carries no write escape.
# STILL MESSAGE-ONLY: `_cp8b_seg_read_shaped` has exactly one caller, `_cp8b_selfedit_hint`. No verdict
# moves; the `--delta` leg is the standing proof of that.
# FOLD: T6 + T7 DONE — the sed/awk/find arms below now CALL `_cp8b_seg_is_sed_n` /
# `_cp8b_seg_is_awk_range` / `_cp8b_seg_is_find_ro` in their `msg` tier; every forward-copied grammar
# is deleted (`_CP8B_FH_FIND_RO` with it) and K-COUPLE-SED / K-COUPLE-FIND pin that they stay gone.
# `file` is the ONE arm still on the T4 flag-allowlist shape, deliberately: F-e's siblings gave it no
# verdict-bearing recogniser to fold onto (the seat's finding-4 residual ALLOWS today), so there is no
# second tier for it to drift from. This marker is the grep handle the fold briefs use.
_cp8b_seg_read_shaped() {
  _srs=$(_cp8b_lead "$1")
  [ -n "$_srs" ] || return 1
  # 1. WHOLE-SEGMENT write escape. Not a dual-mode special case any more: a `>` is a redirect or an
  # awk/print write target whatever the lead is, `system(`/`getline` are awk's exec and read-from-command
  # escapes, and a mutation verb in ANY token position is a write however it got there.
  _cp8b_fh_write_escape "$1" && return 1
  case "$_srs" in
    echo|printf) return 1 ;;                 # emitters — see the ⚠️ above
    # 3. F-f: a loop HEAD carries the whole deny, so it is judged on the whole RAW command. The head
    # alone is inert by construction; what the tip is warning about lives in the BODY.
    # $2 is the RAW command, passed explicitly by each caller. It is NOT read off a global: the two
    # reason sites keep the raw in DIFFERENT variables (`_cp8b_raw` in the verb arm, `_tad_raw` in the
    # resolved-target arm), and reading one of them here made `for f in .claude/hooks/*; do rm $f; done`
    # — which denies from the resolved-target arm — fall back to the inert HEAD and drop the sentence.
    # No raw at all -> DECLINE: a body we cannot see is not a body we may certify.
    # ROUND 2: per SUB-SEGMENT, not over the whole raw string — see the ⚠️⚠️ block above.
    for|while|until) [ -n "${2:-}" ] || return 1
                     _cp8b_fh_body_escape "$2" && return 1
                     return 0 ;;
  esac
  # 2. F-c / the quote-blind over-split: strip the prefix and re-decide on what is actually being run.
  _srsr=$(_cp8b_fh_strip_prefix "$1"); _srsc=$?
  if [ "$_srsc" = 0 ]; then
    [ -n "$_srsr" ] || return 0            # a BARE prefix / BARE orphan runs nothing — R7's real face
    case "$_srsr" in *[[:space:]]*) ;;      # more than one token -> re-decide below
      *) return 0 ;;                        # a lone operand token, no verb — R3's real face
    esac
    _cp8b_seg_read_shaped "$_srsr" "${2:-}"
    return
  fi
  case "$_srs" in
    # T6 FOLD (design §3-F-b): the sed/awk grammars T4 forward-copied here are GONE — these two arms
    # now CALL the recognisers, in their `msg` tier. One grammar, two tiers: the allow tier
    # (_cp8b_tad_is_read) and this message tier cannot drift apart, because there is nothing left to
    # drift. K-COUPLE-SED pins the call behaviourally (stub the shared script test and BOTH tiers must
    # decline); the tier difference is documented at the recogniser, not re-decided here.
    sed)  _cp8b_seg_is_sed_n "$1" msg; return ;;
    awk)  _cp8b_seg_is_awk_range "$1" msg; return ;;
    find) _cp8b_seg_is_find_ro "$1" msg; return ;;
    file) _cp8b_fh_flags_ok "$1" '-b -h -i -L'; return ;;   # `-C -m` COMPILES a magic file (seat f.4)
  esac
  _cp8b_in_list "$_srs" "$_CP8B_READ_VERBS" && return 0
  # F-d: an interpreter is read-shaped ONLY with a `-c`/`-e` token — a bare `sh x.sh` / `python x.py`
  # runs a FILE and is not the "I meant to read this" shape this face is about.
  _cp8b_in_list "$_srs" "$_CP8B_FH_INTERP" || return 1
  case " $1 " in *' -c '*|*' -e '*) return 0 ;; esac
  return 1
}
# Prints the sentence WITH its leading space, or nothing. Callers no longer carry the literal.
# $2 is the RAW command (each caller passes its own copy — see the loop leg above).
_cp8b_selfedit_hint() {
  _cp8b_seg_read_shaped "$1" "${2:-}" && return 0
  printf ' Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'
}
_cp8b_deny_reason() {
  _dr=$(printf '%s' "$1" | cut -c1-160)
  printf '13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity) - offending segment: [%s].%s%s' "$_dr" "$(_cp8b_message_tip "${_cp8b_raw:-}" "$1")" "$(_cp8b_selfedit_hint "$1" "${_cp8b_raw:-}")"
}

# _cp8b_next_seg: pop the first newline-delimited segment off $_walk into $_seg, leaving the remainder in
# $_walk. Returns 0 while a segment remains, 1 when exhausted. This is PURE PARAMETER EXPANSION - it never
# touches IFS (a global IFS reassignment is the bash.lang.security.ifs-tampering finding, and it also risks
# leaking a modified IFS into the ~40 destructive-matrix rules that run AFTER this block). And it is NOT a
# `cmd | while read` pipe, which would run the body in a SUBSHELL and silently lose the caller's `return`
# (CP-1 shipped exactly that bug, green the whole time). The caller seeds $_walk from _cp8b_segments.
_cp8b_nl='
'
_cp8b_next_seg() {
  [ -n "$_walk" ] || return 1
  case "$_walk" in
    *"$_cp8b_nl"*) _seg=${_walk%%"$_cp8b_nl"*}; _walk=${_walk#*"$_cp8b_nl"} ;;
    *)             _seg=$_walk; _walk='' ;;
  esac
  return 0
}

# ================================================================================================
# GUARD-READ-LANE-2 T1 — the PIPE-INTO-INTERPRETER rule (design §5). ADD-ONLY: both halves can only
# turn an ALLOW into a DENY, never the reverse, so every existing DENY fixture stays green by
# construction (the same monotone shape as the target arm below).
#
# THE MEASURED HOLE (design §1). A quoted-delimiter heredoc body is treated as inert DATA by Arm E,
# and a read-verb-led segment's arguments are treated as inert DATA at :1791. Neither CP arm ever
# looked at what a downstream INTERPRETER does with that data, so three control-plane writes measured
# ALLOW on a clean tree:
#   W11  `sh <<'EOF'` ⏎ `cp /tmp/e .claude/hooks/guard-core.sh` ⏎ `EOF`   (Arm E's body exclusion)
#   W15  the same body piped into `sh`                                     (Arm E again)
#   W16  `echo "cp e .claude/hooks/guard-core.sh" | sh`                    (the read-verb data rule)
# The flat destructive matrix still sees the raw bytes, so the escape is specific to the denials that
# live ONLY in the CP arms — `cp`/`sed -i`/`tee`/`>` onto a control-plane target. A start-line consumer
# gate alone would have shipped W11 DENY and left W15/W16 open one byte over, which is why half 2 is
# framed on the PIPELINE SHAPE (data flowing into something that executes it) rather than on the
# heredoc that happened to carry it.
#
# HONEST SCOPE (review F5 — the first cut of this comment claimed "a CLASS, not a heredoc patch", and
# that overstated it). Half 2's SHAPE is general, but its recognition of "an interpreter" is a
# LEXICON: a hand-maintained list of names, extended below with basenaming, dequoting, exec-prefix
# peeling and an `xargs` command-word re-test.
# THERE ARE TWO RESIDUALS HERE, NOT ONE, and review round 3 found the first cut of this list had
# FILED AN EXAMPLE UNDER THE WRONG ONE, so state the boundary between them precisely.
# ⚠️ ROUND 6 CORRECTED THIS PARAGRAPH'S CLAIM, AND THE CORRECTION IS THE POINT. The round-5 text said
# "AFTER ROUND 5 ONLY (i) REMAINS" and, below, that "a flag missing from the tables costs a needless
# DENY at worst, never an ALLOW". BOTH SENTENCES WERE FALSE WHEN WRITTEN. Round 5's cure for an
# unknown flag looked exactly ONE token past that flag's value, and a second token walked straight
# past it: nine spellings measured ALLOW on d0fda7f2 with the W16 guard-core write aboard, including
# `| sudo --role r --type t sh`, `| xargs -q 1 -q 1 sh`, `| sudo -R dir -R dir sh` and
# `| env --block-signal INT sudo sh`. This is the THIRD time a round of this comment has claimed a
# residual closed and been wrong within one review, so the rule now is: NO SENTENCE HERE MAY CLAIM
# MORE THAN A CELL IN agent-autonomy.sh PINS. What holds is stated below, bound by bound.
# The residual (i) below is a real ceiling — a bigger list is its only cure, not a fix to the peel:
#   (i)  THE LEXICON CEILING — the WRAPPER/BINARY NAME is one this code does not know. `busybox sh`,
#        `./sh`, a renamed or copied shell, and `| some-wrapper --opt val sh` all live HERE: the peel
#        never even looks at `some-wrapper`'s flags, because `some-wrapper` is not on the peel list,
#        so the lead stops on `some-wrapper`, matches no interpreter, and the verdict is untouched.
#        That ALLOW is the ceiling, NOT an under-peel — the earlier cut of this comment cited it as a
#        peel-fidelity case, which mis-described where the hole is and pointed the cure at the wrong
#        code. Both were measured on 86f15acb: `| some-wrapper --opt val sh` and `| some-wrapper sh`
#        ALLOW identically, which is the tell — the flags make no difference.
#   (ii) THE PEEL'S OWN FIDELITY — the name IS known and the peel still lands on the wrong word. This
#        is the one that keeps biting, and it has now been WRONG THREE TIMES: round 1 missed path
#        spellings and exec prefixes; round 2 found the flag peel ate its own command word
#        (`| xargs -- sh`), never peeled a leading `NAME=value` (`| A=1 sh`), never dequoted the lead
#        (`| 'sh'`); round 3 found a known prefix's own long flag in its SEPARATED-value spelling
#        under-peeled onto the value (`| sudo --user root sh`, `| xargs --max-args 1 sh`) and that a
#        `$` introducing a quote defeated the dequote (`| $'sh'`, `| $"sh"`, `| sh$""`). Every one was
#        a fail-OPEN and every one was found by REVIEW, not by the check.
#        round 4 found `env -S` (the SHORT twin of the `--split-string` over-peel round 3 had already
#        excluded, in both its separated and its joined spellings) and one more missing xargs long.
#        Rounds 5 and 6 built TWO RULES here, because the peel fails in two opposite directions.
#        EACH RULE'S SCOPE IS STATED AS EXACTLY WHAT ITS CELLS PIN, AND NO WIDER:
#          · OVER-peel — the lead lands on NOTHING (`| sudo -s`, `| xargs -I sh -c`, `| su`). Covered
#            by FAIL-CLOSED ON EXHAUSTION (round 5): a known wrapper peeled down to an empty segment
#            reports `sh`. SCOPE: over-peel TO EMPTY only. An over-peel that lands on a WORD is not
#            covered — see residual (ii) below.
#          · UNDER-peel — an UNKNOWN flag of a KNOWN wrapper peels one token and the lead lands on the
#            VALUE (`| sudo --role sysadm_r sh` reported `sysadm_r`; `| sudo -R dir sh` reported
#            `dir`). Round 5 cured only the ONE-token spelling by taking both readings across that
#            token; round 6 measured that a second unknown flag defeats any fixed look-ahead and
#            replaced it with the TAINTED-SEGMENT SCAN. SCOPE, precisely: once an unknown flag of a
#            KNOWN wrapper has been peeled, every remaining token OF THAT SEGMENT is matched against
#            the interpreter lexicon MINUS `.`, `source` and `eval` (those three stay lead-only, so
#            `| xargs -q 1 grep -rl pat .` and `| env --block-signal INT grep -c .` stay ALLOW). It is
#            bounded to that one segment, it runs ONLY on a tainted segment, and it says nothing about
#            an unknown WRAPPER — that is residual (i) and is untouched.
#            ⚠️ THE ROUND-4 TEXT HERE PREDICTED THE WRONG CURE (it filed these under "exhaustion
#            catches them") and the ROUND-5 TEXT DECLARED THE CLASS CLOSED while nine spellings were
#            still ALLOW. Both errors are left visible on purpose: reason about this peel from
#            measured leads (`_cp8b_interp_lead` printed directly), never from what it ought to do.
#        So the hand-maintained `_ilvl`/`_ilv` tables are an ACCURACY aid: a value-taking flag missing
#        from them now costs an over-DENY on a tainted segment that happens to carry an interpreter
#        NAME as data, and otherwise costs nothing. That is a claim about TAINTED segments only — it
#        was stated in round 5 as an unconditional "never an ALLOW" and that was false.
# WHAT REMAINS OPEN AFTER ROUND 6, stated as the complete list (anything not here is not claimed).
# EVERY MEMBER IS A PINNED CELL in agent-autonomy.sh's "H R6 RESIDUAL" block, so this list cannot go
# stale silently the way rounds 4 and 5's lists did — a residual closing flips its own cell RED:
#   (a) THE LEXICON CEILING, residual (i) above — an UNKNOWN WRAPPER or an unknown BINARY name:
#       `| some-wrapper sh`, `| some-wrapper --opt val sh`, `| script -c sh`, `| ssh host sh`,
#       `| docker run img sh`, `| nsenter … sh`, `| busybox sh`, `| ./sh`, a renamed or copied shell.
#       The peel never engages, nothing is tainted, and the verdict is untouched. Measured ALLOW.
#   (b) OVER-PEEL ONTO A WORD — `| timeout 5 5 sh` eats one `5`, stops on the other, reports lead `5`.
#       Exhaustion cannot reach it (the lead is not empty) and no unknown flag was peeled, so nothing
#       is tainted either. Measured ALLOW. Narrow: it needs a second bare operand `timeout` rejects.
#   (c) THE PRICED OVER-DENIES, in the safe direction, pinned: `| sudo -R sh cat` (an unknown flag
#       whose VALUE is spelled `sh`) and a CLASS — any tainted segment carrying an interpreter name,
#       or a version-glob match such as `perl5.txt`, as DATA. `| sudo -R dir grep -l python x` was its
#       first example; round 7 measured `| sudo -R dir grep -c node x`, `| sudo -R dir cat ruby` and
#       `| sudo -R dir cat perl5.txt` as the same thing (base-ALLOW on d0fda7f2, DENY now), and pins
#       `perl5.txt` plus its ALLOW twin `perl.txt` as "H R7" cells. Round 6's text here called the
#       grep-pattern collision "the ONLY one this round costs"; that was FALSE and is corrected. The
#       retry is unchanged: drop the unknown flag — `| sudo grep -l python x` is untainted and ALLOW.
#   (d) THE `.`/`source`/`eval` NON-LEAD SKIP — those three are held OUT of the taint lexicon (they
#       stay LEAD-only, so `| xargs -q 1 grep -rl pat .` survives), which means a tainted segment
#       carrying one as a NON-lead token is not scanned for it. Measured ALLOW:
#       `| sudo --role r source /dev/stdin`, `| env --block-signal INT source /dev/stdin`,
#       `| xargs --foo a . /dev/stdin`. NOT EXPLOITABLE, and the pinned DENY cells are the argument:
#       all three are shell BUILTINS, so a wrapper `exec()`s them and they fail ENOENT, and every form
#       that really executes stdin puts a shell — or the builtin itself — in the LEAD, where all three
#       deny (`| source /dev/stdin`, `| . /dev/stdin`, `| sudo -u root source /dev/stdin`, and
#       `| sudo --role r source /dev/stdin sh`, where the trailing `sh` IS in the taint lexicon).
# Residual (i)/(a) is DISCLOSED, not closed: the class of defect it belongs to is closed elsewhere, by
# the flat matrix and by the CP arms' own target binding; this rule narrows the specific laundering
# route where the CP token rides in as data.
#
# Half 1 — the CONSUMER gate — lives inside _cp8b_strip_heredocs below (it is a decision about whether
# to strip). Half 2 — the piped-interpreter re-scan — is here and is called first by BOTH CP arms.
# Both are DISQUALIFICATION-shaped (D-240813-3): a lead this code does not positively recognise leaves
# today's verdict untouched.

# _cp8b_hd_consumer "<heredoc start line>": 0 iff the line's wrapper-peeled lead is a CONTENT CONSUMER
# — a verb that treats the body as text it will print, filter or carry as a message. A shell, an
# interpreter, `git apply`, or any unknown verb MAY EXECUTE the body, so for those the body must stay
# scanned as code. Unknown lead -> 1 -> decline the strip -> pre-#567 behaviour (one retry for a real
# false positive: pass the body from a file, `--input <file>` / `-F <file>`).
_CP8B_HD_CONSUMERS='cat jq grep wc head tail diff'
_cp8b_hd_consumer() {
  # ***THE CONSUMER MUST BE THE WHOLE COMMAND — a SEPARATOR BEFORE THE `<<` DECLINES.*** (Security seat,
  # GUARD-READ-LANE-3, C1 blocking + C2 pre-existing; both reproduced live.) Every test below reads the
  # LEAD of the start line, but a start line may hold SEVERAL commands: in
  # `<recognised consumer> ; python3 /dev/stdin <<'EOF'` the lead is the harmless consumer while the
  # command that actually READS THE BODY is the one after the separator. The body was then ruled inert
  # and an interpreter executed it unscanned — a write onto guard-core.sh itself, measured ALLOW.
  #   C1 (this slice's regression): the consumer was F-j's kit query — DENY on 5d26fbfa, ALLOW on the
  #      first build of this branch, in both the `;` and the `&&` + `sh /dev/stdin` spellings.
  #   C2 (PRE-EXISTING, open on main since the lane-2 consumer gate shipped): the very same shape with
  #      a lane-2 lead — `cat /tmp/note; python3 /dev/stdin <<'EOF'` — measured ALLOW on the PRISTINE
  #      core and on the branch. It is closed HERE rather than deferred: it is one `case` away, it is
  #      the identical root cause, and leaving it would ship a slice whose own fix documents the hole
  #      beside it. The cell is an ALLOW->DENY movement and is declared as such in EXPECTED_DELTA.
  # THIS RUNS FIRST, ahead of all three accept paths (the lane-2 consumer list, F-j's kit query, and the
  # git/gh message carriers), because ALL THREE read only the lead and all three are therefore vulnerable
  # to it — C1 came in through the second, C2 through the first. One decline covers the class.
  # `${1%%<<*}` is the text before the FIRST `<<`; the four post-`<<` declines in `_cp8b_strip_heredocs`
  # (separator AFTER the operator, `<<-`, unquoted delimiter, CP redirect target) are untouched and each
  # still binds its own leg. Disclosed over-deny, the safe direction: a genuine `cd x && cat <<'EOF'`
  # declines too and keeps its body scanned. Mutant M-Fj2 removes this case and must flip W7 to ALLOW.
  case "${1%%<<*}" in *';'*|*'&'*|*'|'*) return 1 ;; esac
  _hdp=$(_cp8b_strip_wrappers "$1")
  _hdv=$(_cp8b_lead "$_hdp")
  _cp8b_in_list "$_hdv" "$_CP8B_HD_CONSUMERS" && return 0
  # GUARD-READ-LANE-3 F-j (design §2 R7) — a segment the kit-QUERY arm already recognises is a content
  # consumer too. The entry contract's own act 1 pipes its path listing into
  # `promotion-readiness.sh --class --changed /dev/stdin <<'EOF'`, whose lead is `sh`; the gate declined,
  # so the pathhit arm read the inert body and denied the kit's own documented first step.
  # THE TEXT BEFORE THE `<<` IS WHAT IS JUDGED, and it must be: `_cp8b_tad_is_kit_query` declines on any
  # `<` byte, so handing it the whole start line would decline every heredoc by construction — a
  # vacuously-safe no-op. `${1%%<<*}` is the consumer command with the redirect operator removed.
  # THIS WIDENS ONLY THE CONSUMER GATE. The four lines after this call in `_cp8b_strip_heredocs` are
  # untouched and each still binds: a separator after the `<<` (`… <<'EOF' | sh`), `<<-`, an UNQUOTED
  # delimiter, and a control-plane redirect target all still refuse the strip. The table membership is
  # the enforcement, exactly as in Arm A — an unlisted script (`sh conformance/verify.sh --class …`)
  # yields the empty token set, declines, and keeps its body scanned. Celled F-j W1…W6.
  _cp8b_tad_is_kit_query "${1%%<<*}" && return 0
  _hdv2=$(printf '%s' "$_hdp" | sed -E 's/^[[:space:]]*//' | awk '{print $2}')
  case "$_hdv $_hdv2" in
    'git commit'|'git tag'|'gh pr'|'gh issue') return 0 ;;
  esac
  return 1
}

# _cp8b_pipe_segments "<cmd>": _cp8b_segments, byte-for-byte, EXCEPT that a segment introduced by a
# `|` is prefixed with a sentinel so the caller can tell a PIPE-FED segment from a `;`/`&&`/`&`-fed
# one. Kept as a near-copy on purpose: it must consider exactly the same bytes to be separators
# (including the `>&`/`&>` redirect protection from GUARD-DENY-TRIO M1), or a redirect operator would
# read as a pipe here and not there. Nothing is ever rejoined (the CP-8a rule).
_cp8b_stx=$(printf '\002')
_cp8b_pipe_segments() {
  _cp8b_joinlines "$1" \
    | sed -e 's/&&/;/g' -e 's/||/;/g' -e "s/|/;$_cp8b_stx/g" \
          -e "s/>&/>$_cp8b_soh/g" -e "s/&>/$_cp8b_soh>/g" \
          -e 's/&/;/g' \
          -e "s/$_cp8b_soh/\&/g" \
    | tr ';\n' '\n\n'
}

# _cp8b_drop_tok "<s>": drop the leading whitespace-delimited token and the whitespace after it.
_cp8b_drop_tok() { printf '%s' "$1" | sed -E 's/^[[:space:]]*[^[:space:]]+[[:space:]]*//'; }

# _cp8b_lead_word "<s>": the leading token, DE-QUOTED. Review round 2, finding 3 (HIGH, fail-OPEN):
# the lead was basenamed but never dequoted, so `| 'sh'`, `| "sh"`, `| '/bin/sh'`, `| "/bin/sh"` and
# `| s\h` — the same interpreter to the shell as `| sh` — all measured ALLOW.
# THE BACKSLASH/QUOTE DECISION, stated because the round-2 brief left it open: strip the bytes
# (normalize TOWARD the program name) rather than treat any quoted/escaped lead as an unknown
# interpreter and DENY. Stripping is safe in THIS DIRECTION ONLY, the same argument _cp8b_dequote
# already carries. The fail-CLOSED alternative was REJECTED on measurement: it flips `| 'cat'`,
# `| "sort"` and `| ca\t` — ordinary read pipelines, ALLOW today — into denials, an unpriced
# read-lane loss on a read-RELIEF row. All three are pinned ALLOW in agent-autonomy.sh, so NO
# over-deny is priced by this finding's cure.
# ROUND 3, finding 2 (HIGH, fail-OPEN): a `$` immediately before the quote defeated the dequote.
# `$'sh'`, `$"sh"` and `sh$""` all run the SAME shell (ANSI-C / locale quoting, and an empty `$""`
# concatenated onto the name), but the dequote left the `$` behind, so the lead was `$sh` / `sh` with
# a stray byte and matched no name — each measured ALLOW on 86f15acb. Strip the `$` only where it
# INTRODUCES a quote, never a bare `$VAR` (which stays unparseable and is refused upstream). Same
# direction-of-safety argument as the dequote itself: it normalizes TOWARD the program name.
_cp8b_lead_word() {
  _lwt=$(_cp8b_lead "$1")
  _lwt=$(printf '%s' "$_lwt" | sed -e "s/\$'/'/g" -e 's/\$"/"/g')
  _cp8b_dequote "$_lwt"
}

# _cp8b_strip_assigns "<s>": drop LEADING `NAME=value` assignment tokens. Review round 2, finding 2
# (HIGH, fail-OPEN): `| A=1 sh`, `| PATH=/x sh`, `| FOO=bar /bin/sh` all run a shell, and the peel's
# `*=*` arm sat INSIDE the flag loop — reachable only AFTER a known prefix — so a LEADING assignment
# was never peeled and each measured ALLOW. Assignments are also legal after a prefix (`env A=1 sh`,
# `sudo A=1 sh`), so this runs before the prefix loop AND after each peeled prefix. Only a real shell
# identifier counts, so `--foo=bar` and `of=/dev/x` are NOT eaten here.
_cp8b_strip_assigns() {
  _sac=$1
  while :; do
    _saw=$(_cp8b_lead "$_sac")
    case "$_saw" in
      [A-Za-z_]*=*) : ;;
      *) break ;;
    esac
    case "${_saw%%=*}" in *[!A-Za-z0-9_]*) break ;; esac
    _sac=$(_cp8b_drop_tok "$_sac")
  done
  printf '%s' "$_sac"
}

# _cp8b_interp_lead "<seg>": print the BASENAMED command word the segment will actually run, after
# peeling the prefixes that merely *arrange to run* something else. Review F1 (HIGH, fail-open): the
# first cut matched only BARE EXACT LOWERCASE names off `_cp8b_lead`, so every ordinary spelling of
# the same shell walked straight through the recogniser and W16's write measured ALLOW again with one
# extra byte — `| /bin/sh`, `| sudo sh`, `| exec sh`, `| nohup sh`, `| timeout 5 /bin/bash`,
# `| /usr/bin/env sh`, `| bash5`, `| python3.11`.
#
# THE PEEL IS DELIBERATELY MINIMAL, and that is the round-2 correction. "This is a DENY trigger, so
# an over-peel can only widen a DENY" is FALSE for the peel itself: over-peeling lands the lead on a
# BENIGN word or on NOTHING, and both fail OPEN. Round 1's single `-[uUgnpILPdEsak]|--*)` arm dropped
# a following value for EVERY `--long` and for no-arg short flags, so `| xargs -- sh`,
# `| xargs --null sh`, `| xargs --max-args=1 sh`, `| command -p sh` and `| time -p sh` each ate their
# OWN COMMAND WORD and measured ALLOW. Hence: peel only KNOWN prefixes, only THEIR known value-taking
# flags, exactly ONE token for an unknown `--long`, and `--` ends flag peeling for that prefix.
#
# FOUR PEELS, in this order:
#   (a) ASSIGNMENTS (`_cp8b_strip_assigns`) — a leading `NAME=value` run, before the prefix loop and
#       again after each peeled prefix, since `env A=1 sh` and `sudo A=1 sh` are both legal.
#   (b) EXEC PREFIXES and their own flags/operands — `sudo -u x`, `env -i`, `env A=1`, `nohup`,
#       `nice -n 5`, `timeout 5`, `command`, `exec`, `time`, and (round 5) the peers `su doas setsid
#       stdbuf ionice chrt taskset flock unshare chroot`. `_cp8b_strip_wrappers` was not reused as
#       the whole answer: it is deliberately CONSERVATIVE (bare `env` only, `timeout` only with a pure
#       duration) because it feeds the kit-exec ALLOW path, where an over-peel would open a hole. Here
#       the direction is inverted — this recogniser is a DENY trigger, so an over-peel can only widen
#       a DENY. It is called on the wrapper-stripped string first and then peels FURTHER on its own
#       terms; the two must not be merged, or the permissive rule below would leak into the ALLOW arm.
#       VALUE-TAKING SHORT FLAGS ARE PER PREFIX, because the same letter means different things:
#         xargs `-n -I -L -P -d -E -s -a` · sudo `-u -U -g -C -h -p -r -t` · nice `-n` ·
#         env `-u -C` (NOT `-S` — round 4; see the over-peel note below) · exec `-a` ·
#         timeout `-k -s` plus the bare duration operand · command and
#         time and nohup take NONE — `command -p/-v/-V` and `time -p` are NO-ARG, and treating them
#         as value-taking is exactly the round-1 hole.
#       VALUE-TAKING LONG FLAGS ARE PER PREFIX TOO (`_ilvl`, round 3): the GNU long spelling of the
#       same option takes a SEPARATED value, so `--user root` / `--max-args 1` / `--unset X` /
#       `--adjustment 5` / `--signal 9` must peel BOTH tokens. Only the BARE `--name` form is on the
#       list; `--name=value` is already one token, and an unknown `--long` still peels ONE token and
#       never a following value. `--` peels itself and ENDS flag peeling for that prefix.
#   (c) `xargs`: peel its flags (`-0 -r -t -p`, and `-n N` / `-I x` / `-L N` / `-P N` / `-d x` /
#       `-E x` / `-s N` in both separated and combined spellings) and RE-TEST the command word that
#       follows through (a). Review F2 (MED, fail-closed regression): `xargs` sat on the interpreter
#       list as a bare name, so it denied regardless of what it ran — `… | xargs cat`, `… | xargs
#       wc -l`, `… | xargs grep -c .` were ALLOW on the parent and DENY after T1, an unpriced read-lane
#       loss on a read-RELIEF row. With NO command word `xargs` is NOT an interpreter: its default
#       command is `echo`.
#   (d) DEQUOTE (`_cp8b_lead_word`) and then BASENAME (`${w##*/}`), in that order, so a quoted or
#       path spelling is judged by the program it names — `| '/bin/sh'` is `sh`.
# `env` needs no case of its own in (c) — it is an exec prefix, so (b) already re-tests its command
# word, which is why `| env cat` is ALLOW and `| env sh -c x` is DENY.
_cp8b_interp_lead() {
  _ilc=$(_cp8b_strip_wrappers "$1")
  _ili=0
  _ilpk=0
  _iltn=0
  while [ "$_ili" -lt 6 ]; do
    _ili=$((_ili + 1))
    _ilc=$(_cp8b_strip_assigns "$_ilc")
    _ilw=$(_cp8b_lead_word "$_ilc")
    [ -n "$_ilw" ] || break
    _ilp=${_ilw##*/}
    case "$_ilp" in
      sudo|exec|command|env|nohup|nice|timeout|time|xargs|\
      su|doas|setsid|stdbuf|ionice|chrt|taskset|flock|unshare|chroot)
        _ilpk=1; _ilc=$(_cp8b_drop_tok "$_ilc") ;;
      *) break ;;
    esac
    # The value-taking SHORT flags of THIS prefix, its value-taking LONG flags, and whether it takes
    # a bare operand.
    # THE KNOWN OVER-PEELS, stated rather than hidden — an over-peel here fails OPEN (see the header):
    #   · `| xargs -I sh -c` treats `sh` as -I's replacement string and lands the lead on `-c`, then
    #     on NOTHING — so ROUND 5's exhaustion rule now DENIES it (measured; it was ALLOW on
    #     f8954369). `| timeout 5 5 sh` eats one `5` and stops on the other, so its lead is `5`, not
    #     empty, and it STILL MEASURES ALLOW — exhaustion cannot reach an over-peel that lands on a
    #     word. It is the last member of the old residual (ii) still open, and it is narrow: it needs
    #     a second bare operand `timeout` itself would reject.
    #   · `--replace` and `--eof` take an OPTIONAL argument in GNU xargs, so listing them as
    #     value-taking over-peels the argument-LESS spelling (`| xargs --replace sh -c x`). Priced as
    #     the lesser risk: the argument-BEARING spelling is the one that carries a shell.
    #   · `env --split-string` is DELIBERATELY ABSENT from `_ilvl`, and this is a measured correction
    #     to the round-3 brief, which listed it. Its "value" is not an option argument but THE COMMAND
    #     LINE ITSELF (`env -S 'sh -c x'` RUNS a shell), so peeling it eats the very word the
    #     recogniser exists to find: adding it flipped `| env --split-string sh` from DENY on
    #     86f15acb to ALLOW. The rule stands — a DENY trigger peels LESS by default.
    #     ROUND 4 finished the same thought on the SHORT twin: `-S` sat in env's `_ilv` and over-peeled
    #     identically (`| env -S sh`, `| env -S /bin/sh` measured ALLOW on 758fafc5), so `S` is off the
    #     list. The JOINED spellings needed the extra `-S?*` arm below, because peeling `-Ssh` as one
    #     opaque flag token also lands the lead on nothing; the arm keeps the tail as the command word.
    # `_ilo`: the prefix's BARE OPERAND, 0 = none · 1 = one NUMERIC operand (`timeout 5`, `chrt 1`,
    # `taskset 1`) · 2 = one operand of ANY shape (`flock /tmp/l`, `chroot /`, `su root`), peeled once.
    # Round 5: the new peers below carry `_ilv=''`/`_ilvl=''` because no value-taking flag of theirs is
    # KNOWN here — an unknown flag now peels one token and, if that exhausts the segment, the
    # exhaustion rule at the bottom denies. Guessing a value-taking flag would fail OPEN; not guessing
    # fails CLOSED, so the empty list is the safe default and stays until a manual is read.
    _ilo=0
    case "$_ilp" in
      xargs)   _ilv='nILPdEsa'
               _ilvl='--max-args --max-lines --max-procs --delimiter --replace --arg-file --eof --max-chars --process-slot-var' ;;
      sudo)    _ilv='uUgChprt'
               _ilvl='--user --group --other-user --prompt --host --chdir --chroot --close-from' ;;
      env)     _ilv='uC';  _ilvl='--unset --chdir' ;;   # NOT --split-string / -S: see below
      exec)    _ilv='a';   _ilvl='' ;;
      nice)    _ilv='n';   _ilvl='--adjustment' ;;
      timeout) _ilv='ks';  _ilvl='--signal --kill-after'; _ilo=1 ;;
      chrt|taskset) _ilv=''; _ilvl=''; _ilo=1 ;;        # priority / affinity-mask operand
      flock|chroot|su) _ilv=''; _ilvl=''; _ilo=2 ;;     # lockfile / new-root / target-user operand
      *)       _ilv='';    _ilvl='' ;;           # command, time, nohup and the round-5 peers
    esac
    # Peel the prefix's OWN flags and operands until a real command word is in front.
    _ildd=0
    while [ "$_ildd" -eq 0 ]; do
      _ilc=$(_cp8b_strip_assigns "$_ilc")
      _ilf=$(_cp8b_lead "$_ilc")
      if [ "$_ilp" = su ]; then
        # `su -c '<string>'` is `env -S`'s twin, one level up: the value is not an option argument but
        # A SHELL COMMAND LINE — `su` hands it to the target user's shell. So the segment RUNS a shell
        # whatever the value spells, and neither peeling the value (over-peel, lands on nothing) nor
        # stopping on it (under-peel, lands on `sh`'s arguments) is right. Answer the question directly:
        # `-c` present -> this segment is a shell.
        case "$_ilf" in
          -c|--command|-c?*|--command=*) _ilc='sh'; _ildd=1; continue ;;
        esac
      fi
      case "$_ilf" in
        '') break ;;
        --)    _ilc=$(_cp8b_drop_tok "$_ilc"); _ildd=1 ;;   # end of flags: the next token is the command
        --*)   # A long flag THIS prefix is known to take a SEPARATED value for peels flag+value;
               # anything else (unknown long, or the `--name=value` form, already one token) peels
               # ONE token. Round 3, finding 1: without `_ilvl` the peel stopped ON the value, so
               # `| xargs --max-args 1 sh`, `| sudo --user root sh`, `| env --unset X sh` and
               # `| nice --adjustment 5 sh` measured ALLOW on 86f15acb.
               # ROUND 5, the residual-(ii) class. An UNKNOWN long is AMBIGUOUS: peel one token and
               # the lead lands on the command word if the flag is valueless, or on the VALUE if it
               # is not. `| sudo --role sysadm_r sh` measured ALLOW on f8954369 for exactly that
               # reason — lead `sysadm_r`. The exhaustion rule does NOT reach it (peeling one token
               # UNDER-peels; it never lands on nothing), and peeling two would deny the pinned read
               # `| xargs --null cat`.
               # ROUND 6 REPLACED ROUND 5'S CURE HERE. Round 5 took BOTH READINGS across exactly one
               # token past the flag's value; a SECOND unknown flag pushed the shell out of that
               # window and nine spellings measured ALLOW on d0fda7f2 (`| sudo --role r --type t sh`,
               # `| xargs -q 1 -q 1 sh`, `| env --block-signal INT sudo sh`, …). The lesson is that
               # the ambiguity is NOT one token wide: once the peel has GUESSED at an unknown flag,
               # its idea of where the command word sits has no reliable relation to the real one, so
               # any fixed look-ahead can be pushed past by adding tokens. So do not look ahead at
               # all here — peel one token and MARK THE SEGMENT TAINTED. The whole-segment scan at the
               # bottom is what resolves the ambiguity, and it subsumes round 5's two readings
               # exactly (the alternate token it inspected is always inside the scanned remainder),
               # which is why that code is GONE rather than kept as a fast path: two mechanisms for
               # one property makes both mutants vacuous.
               if _cp8b_in_list "$_ilf" "$_ilvl"; then
                 _ilc=$(_cp8b_drop_tok "$(_cp8b_drop_tok "$_ilc")")
               else
                 _ilc=$(_cp8b_drop_tok "$_ilc"); _iltn=1
               fi ;;
        -S?*)  # `env -Ssh` / `env -S'sh'`: the JOINED spelling of --split-string. The tail is not an
               # option value but the COMMAND LINE, so peeling the whole token as one opaque flag
               # lands the lead on NOTHING and fails OPEN (round 4). Keep the tail, drop the `-S`,
               # and stop peeling — the next lead word IS the command word. Any other prefix's
               # `-S<something>` keeps the old opaque peel.
               if [ "$_ilp" = env ]; then
                 _ilc="${_ilf#-S} $(_cp8b_drop_tok "$_ilc")"; _ildd=1
               else _ilc=$(_cp8b_drop_tok "$_ilc"); fi ;;
        -?)    # A lone short flag: value separated, or none. A letter NOT in `_ilv` is the exact
               # SHORT twin of the unknown long above — `| sudo -R dir sh` and `| xargs -q 1 sh`
               # measured ALLOW with the long cure alone, and `| sudo -R dir -R dir sh` /
               # `| xargs -q 1 -q 1 sh` measured ALLOW with round 5's — so it takes the same round-6
               # treatment: peel one token, TAINT the segment, let the whole-segment scan decide. A
               # letter that IS in `_ilv` is not ambiguous: the manual says it takes the value, so no
               # guess is made and no taint is earned.
               _ilkn=0
               case "$_ilv" in *"${_ilf#-}"*) [ -n "$_ilv" ] && _ilkn=1 ;; esac
               if [ "$_ilkn" -eq 1 ]; then
                 _ilc=$(_cp8b_drop_tok "$(_cp8b_drop_tok "$_ilc")")
               else
                 _ilc=$(_cp8b_drop_tok "$_ilc"); _iltn=1
               fi ;;
        -*)    _ilc=$(_cp8b_drop_tok "$_ilc") ;;   # combined/valueless: -i, -0, -n1, -I{}, -tv
        *[!0-9smhd]*) if [ "$_ilo" -eq 2 ]; then   # `flock /tmp/l sh`, `chroot / sh`, `su root -c x`
                        _ilo=0; _ilc=$(_cp8b_drop_tok "$_ilc")
                      else break; fi ;;            # otherwise: a real command word — stop peeling
        *[0-9]*) if [ "$_ilo" -ge 1 ]; then        # the bare numeric operand: `timeout 5`, `chrt 1`
                   _ilo=0; _ilc=$(_cp8b_drop_tok "$_ilc")
                 else break; fi ;;
        *) break ;;                                # a bare word of [smhd] letters — `sh` itself
      esac
    done
  done
  _ilc=$(_cp8b_strip_assigns "$_ilc")
  _ilw=$(_cp8b_lead_word "$_ilc")
  # FAIL CLOSED ON EXHAUSTION (round 5, the structural ruling). Landing on NOTHING after a KNOWN
  # wrapper was peeled is the peel's characteristic failure, and it fails OPEN in every spelling: the
  # over-peels (`sudo -s`, `xargs -I sh -c`) and the under-known value-taking longs (`sudo --role
  # sysadm_r sh`, `env --block-signal INT sh`) BOTH end here, with an empty lead that matches no
  # interpreter. Report `sh` instead. The justification is that the two readings of an exhausted
  # segment are (a) the wrapper ran with no command word — `sudo -s`, `sudo -i`, `su`, `su root` — in
  # which case it IS a shell, and (b) the peel ate the command word, in which case the word it ate is
  # unknown and may be one. Both are shell-or-unknown, so `sh` is the honest answer to both.
  # WHY THIS COSTS THE READ LANE NOTHING: a real read pipeline always leaves a command word standing
  # (`| sudo -u root cat`, `| xargs --max-args 1 cat`, `| flock /tmp/l cat`) — it has to, or nothing
  # would read. Exhaustion is not a shape reads take. Measured: no ALLOW cell in agent-autonomy.sh
  # moved. The REJECTED alternative was an UNCONDITIONAL any-token scan of every segment, which
  # denies `| xargs grep -rl pat .` on the `.` entry in the lexicon — a real read-lane loss. Round 6
  # took the conditional form of that scan instead; see below. Mutant M-H13 turns this back into
  # "not an interpreter".
  if [ -z "$_ilw" ] && [ "$_ilpk" -eq 1 ]; then printf 'sh'; return 0; fi
  # THE TAINTED-SEGMENT SCAN (round 6). Reached only when the peel GUESSED — i.e. some unknown flag
  # of a KNOWN wrapper was peeled as one opaque token (`_iltn=1`). At that point the lead this
  # function is about to report is not trustworthy at any fixed distance, so scan every REMAINING
  # token of THIS segment (dequoted, basenamed) and report the first interpreter found.
  # THREE BOUNDS, each one paid for by a pinned cell, so this is not the rejected any-token scan:
  #   · CONDITIONAL — an untainted segment is never scanned, so `| xargs grep -rl pat .`,
  #     `| xargs grep -l python`, `| env cat sh` and `| sudo -u root cat` keep today's ALLOW by
  #     construction, not by luck.
  #   · SEGMENT-BOUNDED — only this pipe segment's own remainder, never the whole command line.
  #   · LEXICON MINUS `.`, `source`, `eval` — those three stay LEAD-ONLY. `.` is the commonest
  #     directory argument there is (`| xargs -q 1 grep -rl pat .` and `| env --block-signal INT
  #     grep -c .` are pinned ALLOW on exactly this exclusion); `source` and `eval` are ordinary
  #     words that appear in filenames and grep patterns. As LEADS all three still deny.
  # THE PRICE, disclosed and pinned: a tainted segment carrying an interpreter NAME as data now
  # denies — `| sudo -R dir grep -l python x` was ALLOW on d0fda7f2 and is DENY here. Once the peel
  # has guessed, this rule cannot tell a grep pattern from a program. The retry is to drop the
  # unknown flag; `| sudo grep -l python x` is untainted and stays ALLOW (pinned beside it).
  # Mutant M-H16 disables the taint MARKING; M-H15 disables this SCAN.
  if [ "$_iltn" -eq 1 ]; then
    _ilts=$_ilc
    while [ -n "$(_cp8b_lead "$_ilts")" ]; do
      _iltw=$(_cp8b_lead_word "$_ilts"); _iltw=${_iltw##*/}
      case "$_iltw" in
        .|source|eval) : ;;
        *) if _cp8b_is_interp "$_iltw"; then printf '%s' "$_iltw"; return 0; fi ;;
      esac
      _ilts=$(_cp8b_drop_tok "$_ilts")
    done
  fi
  printf '%s' "${_ilw##*/}"
}

# _cp8b_piped_interp "<cmd>": PREDICATE — 0 iff some PIPE-FED segment RUNS a shell or interpreter.
# Those are the consumers that turn upstream DATA into CODE. `.`/`source` are on the list because both
# read a file as script. A read verb downstream (`… | head`, `… | grep`, `… | sort`, `… | sed -n 1p`,
# `… | tee /tmp/x`) is NOT, so the ordinary read pipeline keeps today's verdict.
#
# THE POLARITY IS DELIBERATE and must stay POSITIVE (a recogniser of interpreters), not the inverse (a
# recogniser of safe consumers). Inverting it would deny every unlisted pipe consumer — `sort`, `tee`,
# `column`, every project's own filter — a far wider version of exactly the F2 regression this round
# is repairing. The cost of the positive form is the disclosed lexicon ceiling in the block comment
# above (`busybox sh`, `./sh`, a renamed shell, an unknown wrapper): NOT recognised, unchanged today.
# Round 5 note: the peel it calls now fails CLOSED (an exhausted segment reports `sh`), so the
# polarity argument still holds — the positive recogniser is still the thing that can say "no".
# Mutant M-H2 forces this to 1 and W16 flips back to ALLOW; M-H4 removes the basename and `| /bin/sh`
# flips; M-H5 removes the xargs command-word re-test and `| xargs cat` flips back to a false DENY.
#
# _cp8b_is_interp "<word>": THE LEXICON, extracted (round 5) so the peel can consult it too — the
# ambiguous-flag second reading below needs to ask "is this word an interpreter?" before the peel has
# finished. One list, two callers; it must not be copied.
_cp8b_is_interp() {
  case "$1" in
    sh|bash|dash|zsh|ksh|bash[0-9]*|sh[0-9]*|zsh[0-9]*|ksh[0-9]*|\
    python|python[0-9]*|perl|perl[0-9]*|ruby|ruby[0-9]*|node|node[0-9]*|\
    eval|source|.|osascript) return 0 ;;
  esac
  return 1
}
_cp8b_pi_lead=''
_cp8b_piped_interp() {
  case "$1" in *'|'*) : ;; *) return 1 ;; esac
  _piw=$(_cp8b_pipe_segments "$1")
  while [ -n "$_piw" ]; do
    case "$_piw" in
      *"$_cp8b_nl"*) _pis=${_piw%%"$_cp8b_nl"*}; _piw=${_piw#*"$_cp8b_nl"} ;;
      *)             _pis=$_piw; _piw='' ;;
    esac
    case "$_pis" in "$_cp8b_stx"*) _pis=${_pis#"$_cp8b_stx"} ;; *) continue ;; esac
    _pil=$(_cp8b_interp_lead "$_pis")
    if _cp8b_is_interp "$_pil"; then _cp8b_pi_lead=$_pil; return 0; fi
  done
  return 1
}

# _cp8b_pi_note: the second half of the piped-interpreter deny reason (review F3). The reason used to
# name only the upstream READ segment, which reads as a false positive — the agent sees `echo "…"`
# denied and no mention of the shell that made it dangerous. Name the interpreter.
_cp8b_pi_note() {
  printf ' That segment is piped into interpreter [%s], which would EXECUTE it, so the pipeline is judged RAW — no heredoc-body exclusion and no read-verb data exemption. To READ a control-plane file, drop the interpreter from the pipeline.' "$_cp8b_pi_lead"
}

# _cp8b_piped_interp_hit "<cmd>": 0 iff a piped interpreter is present AND some segment of the RAW
# command path-hits a control-plane target. "Raw" is the whole point: no heredoc-body exclusion and no
# read-verb data exemption, because the interpreter downstream is about to execute exactly those bytes.
# The offending segment is left in $_cp8b_pi_seg for the caller's reason string.
# DISCLOSED OVER-DENY, the safe direction: `cat .claude/hooks/guard-core.sh | sh -n` denies (one retry:
# `sh -n <file>` directly, an already-recognised form). `grep x file | sh` carries no CP token and
# stays ALLOW, exactly as today.
_cp8b_pi_seg=''
_cp8b_piped_interp_hit() {
  _cp8b_piped_interp "$1" || return 1
  _pihw=$(_cp8b_segments "$1")
  while [ -n "$_pihw" ]; do
    case "$_pihw" in
      *"$_cp8b_nl"*) _cp8b_pi_seg=${_pihw%%"$_cp8b_nl"*}; _pihw=${_pihw#*"$_cp8b_nl"} ;;
      *)             _cp8b_pi_seg=$_pihw; _pihw='' ;;
    esac
    [ -n "$(printf '%s' "$_cp8b_pi_seg" | tr -d '[:space:]')" ] || continue
    if _cp8b_tad_pathhit "$_cp8b_pi_seg"; then return 0; fi
    # GUARD-READ-LANE-2 T7 — THE BARE-DIRECTORY HALF, and it is a MEASURED HOLE, not a tidy-up. T1 armed
    # this rule on the PATHHIT trigger alone, but the target arm has three: a bare control-plane
    # DIRECTORY NAME (`conformance`, `skills`) is a LITERAL-TOKEN hit, never a pathhit. So the whole
    # laundering rule was unarmed for `<reader> <cp-dir> | sh`, and at 62681ba6 `ls conformance | sh`
    # MEASURED ALLOW — no `find` involved, a pre-existing gap in every read verb. F-e would have
    # inherited it (`find conformance -name '*.sh' | sh` flipped to ALLOW the moment find joined the read
    # lane), which is how it was found. Closing it here rather than shipping the inheritance: the same
    # trigger the target arm uses two lines apart, so the pipe rule is armed by the same CP evidence the
    # deny is. Direction is ALLOW->DENY only. `_cp8b_tad_composed_tok` is deliberately NOT added — it is
    # the fuzzier trigger and no measured route needs it; that stays a one-line ratified add.
    if _cp8b_tad_literal_tok "$_cp8b_pi_seg"; then return 0; fi
  done
  return 1
}

# GUARD-READONLY-FP-RELIEF Arm E — QUOTED-heredoc body exclusion (cures register face N3).
# A heredoc with a QUOTED delimiter (`<<'EOF'` / `<<"EOF"`) is INERT DATA by shell semantics: no
# expansion, no execution. Today each body LINE becomes a segment and is scanned as code, which is
# the false positive that bit one orchestrator session four times. This removes the body REGION from
# the copy the two control-plane arms segment. The RAW command is untouched — every flat rule in
# `guard_check_command` (recursive rm, push-to-main, secret reads, …) still sees every byte, and the
# deny REASONS still print the raw/segment text.
#
# ***THE FAIL DIRECTION IS OVER-EXCLUSION*** (security vet M2): swallowing past a mis-found terminator
# would let a REAL command escape the scan. So every ambiguity resolves to NOT-excluded, and each
# decline below has a must-stay-DENY leg in agent-autonomy.sh that places a live mutator AFTER the
# true terminator. Declines, in order:
#   · a here-STRING (`<<<`) — different construct, not this arm
#   · any CR byte — a CRLF terminator will not compare equal, so the whole command is ambiguous
#   · anything other than EXACTLY ONE `<<` in the command (two heredocs = two body regions to bound;
#     this decline is a conservative BELT — with the exact-terminator rule below, dropping it can
#     only ever exclude the FIRST body, which is inert either way, so no fixture separates it. Stated,
#     not claimed as coverage: the `_kx` precedent at C4 Arm 2, mutant dropped with rationale.)
#   · `<<-` (tab-stripped terminators), an UNQUOTED delimiter, or a delimiter that is not a plain
#     `[A-Za-z0-9_]+` word — the extraction below simply fails to match, and a failed match declines
#   · a heredoc whose own redirect TARGET classifies control-plane or is non-literal
#   · NO line after the start line that is EXACTLY the delimiter — never strip to the end
#   · any earlier line that TRIMS to the delimiter but is not exactly it (whitespace ambiguity)
# ***REVIEW C2 (2026-08-19), residual DIRECTION CORRECTED — the earlier claim was FALSIFIED.*** A
# `<<'WORD'` sequence inside an ordinary quoted argument IS treated as a heredoc start, and the earlier
# comment claimed "the direction of any residual error is a body that stays scanned — over-deny." That
# was WRONG. `: "<<'X'"` followed by `sed -i s/return 1/return 0/ .claude/hooks/guard-core.sh` and a
# line `X` made the first REAL command the heredoc body: it was stripped from the scanned copy and the
# write to the guard's OWN source ALLOWED — an escape from ALL cp8b protection, measured ALLOW on the
# branch, DENY on main. The failure direction is OVER-EXCLUSION, not over-deny. The in-body declines
# (`<<-`, unquoted, whitespace-ambiguous) were never the gap; the ENTRY was. A REAL heredoc operator
# never has a QUOTE byte before the `<<` on its start line (`cat <<'EOF'` — no quote precedes `<<`),
# so declining when one does closes the argument-embedded shape. Disclosed OVER-DENY, the safe
# direction: a genuine heredoc whose start line ALSO carries an earlier quoted string
# (`echo "hi" && cat <<'EOF'`) declines too and its body stays scanned — accepted, since the fail
# direction is over-deny and the common heredoc spelling leads with the redirect verb, unquoted.
# Mutant M-E8 removes that line and reopens the hole.
_cp8b_strip_heredocs() {
  case "$1" in *'<<'*) : ;; *) printf '%s' "$1"; return ;; esac
  case "$1" in *'<<<'*) printf '%s' "$1"; return ;; esac
  case "$1" in *"$_cp8b_cr"*) printf '%s' "$1"; return ;; esac
  _hdc=$(printf '%s' "$1" | grep -o '<<' | wc -l | tr -d '[:space:]')
  [ "$_hdc" = 1 ] || { printf '%s' "$1"; return; }
  _hdl=$(printf '%s\n' "$1" | grep -n '<<' | head -1 | cut -d: -f1)
  [ -n "$_hdl" ] || { printf '%s' "$1"; return; }
  _hds=$(printf '%s\n' "$1" | sed -n "${_hdl}p")
  # REVIEW C2 — ENTRY guard: a quote byte BEFORE the `<<` on the start line means the `<<` is embedded
  # in an argument, not a heredoc operator. Decline (never strip). `${_hds%%<<*}` is the text before
  # the first `<<`; a `'` or `"` in it is the tell.
  case "${_hds%%<<*}" in *[\'\"]*) printf '%s' "$1"; return ;; esac
  # GUARD-READ-LANE-2 T1, half 1 (design §5) — the CONSUMER gate. Arm E excluded a body on the
  # DELIMITER's quoting alone and never on WHO CONSUMES it, so `sh <<'EOF'` + a `cp` onto the guard's
  # own source measured ALLOW (W11). A quoted body is inert only while the consumer treats it as
  # content; when a shell or interpreter reads it, it IS code. Two separately-mutatable lines:
  #   (M-H1) the consumer must be on the content-consumer list; and
  #   (M-H3) the consumer must be the WHOLE start line — a separator after the `<<` operator means
  #          something ELSE downstream also sees the body (`cat <<'EOF' | sh`, `cat <<'EOF' ; true`),
  #          which is the W15 shape one byte over from W11.
  _cp8b_hd_consumer "$_hds" || { printf '%s' "$1"; return; }
  case "${_hds#*<<}" in *'|'*|*';'*|*'&'*) printf '%s' "$1"; return ;; esac
  # The two SEMANTIC guards, deliberately kept as their own lines so each is separately mutatable
  # (the extraction below is intentionally permissive; these decide, not the regex).
  case "$_hds" in *'<<-'*) printf '%s' "$1"; return ;; esac              # tab-stripped terminator (M2)
  printf '%s' "$_hds" | grep -q "<<-\{0,1\}['\"]" || { printf '%s' "$1"; return; }  # QUOTED delimiter only
  _hdw=$(printf '%s' "$_hds" | sed -n 's/.*<<-\{0,1\}["'"'"']*\([A-Za-z0-9_][A-Za-z0-9_]*\).*/\1/p')
  [ -n "$_hdw" ] || { printf '%s' "$1"; return; }
  if _cp8b_tad_redir_cp "$_hds"; then printf '%s' "$1"; return; fi
  _hdo=$(printf '%s\n' "$1" | awk -v start="$_hdl" -v w="$_hdw" '
    NR <= start { pre = pre $0 "\n"; next }
    !seen {
      if ($0 == w) { seen = 1; next }
      t = $0; gsub(/^[ \t]+/, "", t); gsub(/[ \t]+$/, "", t)
      if (t == w) { amb = 1 }
      next
    }
    { post = post $0 "\n" }
    END { if (!seen || amb) exit 3; printf "%s%s", pre, post }') || { printf '%s' "$1"; return; }
  printf '%s' "$_hdo"
}

# _cp8b_control_plane_denied "<cmd>": PREDICATE - the CP-8b control-plane decision. Walks the segments
# and binds each segment's LEADING VERB to that segment's OWN arguments (design section 9.4).
_cp8b_control_plane_denied() {
  _cp8b_raw=$1   # DRIFT-2: the whole command, for _cp8b_message_tip (the message-body escape hint).
  # GUARD-READ-LANE-2 T1, half 2 (design §5): a pipe into an interpreter forces RAW judgment of every
  # upstream segment before anything below can exempt it as data. Add-only — a miss falls straight
  # through to today's walk.
  if _cp8b_piped_interp_hit "$1"; then _cp8b_deny_reason "$_cp8b_pi_seg"; _cp8b_pi_note; return 0; fi
  # GUARD-READ-LANE-2 T8 (design §3-F-a): segment the QUOTED-SPAN MASK when it was kept. It declines to
  # the identical string on every ambiguous byte and whenever the gate does not hold, so this line is a
  # no-op for every command that is not a read-led whole.
  _walk=$(_cp8b_segments "$(_cp8b_mask_quoted "$(_cp8b_strip_heredocs "$1")")")
  while _cp8b_next_seg; do
    [ -n "$(printf '%s' "$_seg" | tr -d '[:space:]')" ] || continue
    # TWO VIEWS OF ONE SEGMENT, and the split is the whole of F-a's blast radius. `$_segm` is the
    # MASKED view and is consulted by exactly the tests whose subject is SHELL METACHARACTER SEMANTICS
    # (here: the `<`/`>` redirect bail). `$_seg` is restored to the command's TRUE BYTES and is what
    # every other test, every reason string, and every downstream recogniser sees — so pathhit, the
    # literal-token walk, the grammars and the deny messages are unchanged, byte for byte. A real
    # UNQUOTED operator is never masked in the first place (the mask is span-bounded), so the DENY
    # half of the sentinel pair is held by `$_segm` itself, not by the restore.
    _segm=$_seg
    case "$_seg" in *["$_cp8b_mk_all"]*) _seg=$(_cp8b_unmask_quoted "$_seg") ;; esac

    # 1. git write-primitives are subcommand-bound and apply REGARDLESS of a control-plane mention
    #    (`git diff --output` writes anywhere). Checked first.
    if _cp8b_git_write_denied "$_seg"; then return 0; fi

    # 2. a segment we cannot parse, or one carrying a redirect, is NEVER relaxed - it keeps today's
    #    scan-and-deny. (`echo -n > .github/workflows/ci.yml` leads with a READ verb; only the redirect
    #    check stands between it and an allow-back.)
    #    F-a: the redirect test reads `$_segm` — a `>` inside a quoted span is a character in an
    #    argument, not an operator, and treating it as one is what denies `echo "a -> b"`. The scan it
    #    guards still runs on the restored `$_seg`.
    if _cp8b_unparseable "$_seg" || printf '%s' "$_segm" | grep -q '[<>]'; then
      if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi
      continue
    fi

    _lv=$(_cp8b_lead "$_seg")
    case "$_lv" in
      # 3. READ TOOLS - CP-8a's strict stdout-only set, REUSED VERBATIM, not re-derived. It deliberately
      #    excludes every tool with a write/exec escape: sed (s///e executes, `w` writes), awk (system(),
      #    print >), find (-exec/-delete), sort (-o), uniq (out), less/more (!cmd), xxd (-r). Their
      #    arguments are DATA: a read command cannot mutate the path it merely mentions.
      grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|file|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink|echo|printf|which|type)
        : ;;
      git)
        _sub=$(_cp8b_git_sub "$_seg")
        case "$_sub" in
          # Read subcommands whose arguments are DATA — `git commit -m "… conformance/x …"` is a MESSAGE,
          # not a target. This set is CP-8a's, REUSED VERBATIM and deliberately NOT widened.
          #
          # Every other git subcommand is left to fall through to scan-and-deny below, and that is a
          # decision, not an oversight. An earlier cut of this slice also certified
          # `add|fetch|pull|rebase|merge|stash|tag|branch|config|push` as "reads" — which would have
          # handed back an arbitrary-execution primitive, because `git rebase --exec "rm -rf conformance"`
          # RUNS the string. That is CP-8a's fail-open repeating exactly: certifying a capability safe by
          # NAMING it, without enumerating every flag it carries ("git diff is a read" — false for
          # --output). None of them NEED the exemption: with no mutation verb in the segment, scan-and-deny
          # allows them anyway. Speculative exemptions are treated as guilty.
          commit|status|blame|describe)
            : ;;
          checkout|restore|archive|bundle|worktree|init|clone)
            : ;;   # already TARGET-BOUND in step 1; a clean pass there is a real ALLOW.
          *)
            if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
        esac ;;
      # 4. MUTATION VERBS - target-bound. Two sub-classes by what the verb does to its SOURCE:
      #    - ALL path tokens are targets when the verb can WRITE THROUGH any of its arguments:
      #        mv/rsync DESTROY the source (this is what catches `mv conformance /tmp/gone`);
      #        ln creates a WRITABLE ALIAS - `ln -s conformance/x /tmp/link` then `echo … > /tmp/link`
      #        writes the control-plane file, so `ln` is NOT a content-copy and every token it names is a
      #        target (security review of CP-8b: grouping `ln` with `cp` was the family's signature
      #        error - certifying a capability safe by the name it is grouped under, not by what it does);
      #        rm/chmod/… mutate their targets in place.
      #    - Only the DESTINATION is a target for cp/install, which copy CONTENT: editing the copy cannot
      #      reach the original, so copying a control-plane file OUT (`cp conformance/x /tmp/b`) is safe.
      #      ⚠️ NOT TRUE OF EVERY cp/install INVOCATION. Some flags make the destination an ALIAS of
      #      the source rather than a copy of its content, and this comment asserted otherwise until
      #      2026-08-01. Same signature error the `ln` note above records — certifying a capability by
      #      the family it is grouped under rather than by what it does. NOT fixed here: the remedy is
      #      a command-matrix change with a different blast radius from this file's path work, and it
      #      is tracked as GUARD-CP-HARDLINK-ALIAS. The flag detail lives on that row, not in this
      #      file — a guard's own source is read by the agent it denies, so an open hole is described
      #      here by its shape, not by a recipe.
      # GUARD-READ-LANE-2 F-b — the ONE read grammar of a DUAL-MODE verb. This arm deliberately
      # SHADOWS the mutation arm below for `sed`: `case` takes the FIRST matching arm, so the `sed`
      # entry in the `mv|rsync|…|sed` list below is now SHADOWED — unreachable for a bare `sed` lead.
      # It is KEPT there on purpose, and the keeping is the safety property: deleting THIS arm restores
      # today's deny exactly, with no second edit and no chance of an accidental read-lane hole left
      # behind. (T6 seat review item 2.) `sed` stays in that list (it IS
      # a mutation verb — that is the D1 build invariant, and the D1-M1 mutant leg proves a lexicon
      # entry would fail open), and every spelling the grammar declines falls THROUGH to it unchanged.
      # `sed -i`, `-e`, `-f`, `-s`, `--expression=`, a `w`/`e`/`s///w` script, a flag-shaped or
      # expansion-carrying operand: all still target-bound. A redirect never reaches here at all —
      # step 2 above scans any segment carrying `<`/`>` before the lead is consulted.
      sed)
        _cp8b_seg_is_sed_n "$_seg" && continue
        if _cp8b_cp_target_in all "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      # GUARD-READ-LANE-2 F-e — the same shadow for `find`, with one difference that matters: `find` is
      # NOT in the mutation list below (it never was — it fell to the `*)` scan-and-deny arm), so this
      # arm's decline path re-enters THAT arm explicitly rather than falling through. Every spelling
      # the grammar declines is therefore scanned exactly as it is today, byte for byte.
      find)
        _cp8b_seg_is_find_ro "$_seg" && continue
        if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      mv|rsync|ln|rm|rmdir|shred|truncate|chmod|chown|tee|patch|dd|sed)
        if _cp8b_cp_target_in all "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      cp|install)
        if _cp8b_cp_target_in last "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      # 5. ANYTHING ELSE - an interpreter, a wrapper, or simply unrecognized. Its arguments may be CODE.
      #    Today's behavior, byte for byte. This is the branch that makes the whole change monotone.
      *)
        if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
    esac
  done
  return 1
}

# ============================================================================================
# GUARD-BASENAME-AFTER-CD-BYPASS + GUARD-INTERPRETER-FAMILY-BYPASS — the resolved-target arm.
# (design: docs/architecture/2026-08-13-guard-judge-resolved-target-design.md §3.)
# The guard judges the RESOLVED target, not the verb. COMPOSITION PROPERTY (§3-C, §9(b)): the final
# control-plane deny is `old-verb-arm (_cp8b_control_plane_denied) ∨ new-target-arm (below)`. The old
# arm is retained VERBATIM — so every existing DENY fixture stays green by construction and this is a
# monotone ADD (panel #19 shape). REALIZATION NOTE: the design's "union at four sites" is realized here
# as one cohesive parallel arm OR'd with the retained old arm — this reproduces the census oracle
# (scratchpad out_MIN2.tsv = today_cp ∨ newarm) exactly and touches no existing decision site, keeping
# the blast radius to an addition. Reads/CP-script execution stay allowed; ordinary-target writes by
# the same tools stay allowed.
#
# HONEST CEILING (design §6): this narrows the drift window for SINGLE-COMMAND, QUOTE-FREE writes only.
# Persisted cwd (no `cd` in the command), `$VAR`/`bash -c`/quoted-separator cd, and `python3 -c`
# building a path by concatenation remain disclosed residuals — the guard stays a speed bump (D3′).

# _cp8b_norm "<path>": textual normalization — collapse //, a /./ FIXPOINT, trailing /, and a `..`
# fixpoint. Byte-identical to guard_check_path's twin sed (single source of truth for composed-path
# shape) — the two are pinned equal by a byte-identity selftest leg (GUARD-CP-WRITE-ROUTES K-COUPLE).
# The /./ leg is a labelled fixpoint (`:b … tb`) mirroring the `..` leg: a single `g` pass misses
# OVERLAPPING /./ runs (hooks/./././pre-push -> hooks/./pre-push residual), so the loop is required to
# fully collapse repeated /./ (K-N2 pins it).
_cp8b_norm() {
  printf '%s' "$1" | sed -e 's#//*#/#g' -e ':b' -e 's#/\./#/#' -e 'tb' -e 's#^\./##' -e 's#/*$##' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta'
}

# _cp8b_has_quote "<segment>": 0 iff the segment carries a quote/escape byte. A quote byte means the
# quote-blind segmenter (:568) MAY have crossed a quote, so a cd in this segment is not trustworthy
# (security C1). This is the fail-safe that keeps the desync attack DENY (see _cp8b_eff_update).
_cp8b_has_quote() { case "$1" in *\'*|*\"*|*\\*) return 0 ;; esac; return 1; }

# _cp8b_cd_arg "<segment>": the second token of a `cd` segment.
_cp8b_cd_arg() { printf '%s' "$1" | sed -E 's/^[[:space:]]*//' | awk '{print $2}'; }

# Part A — cd-state accumulator, fail-safe against desync. $_CP8B_EFF is '' (repo-relative root) or a
# pure relative DESCENT prefix. It updates ONLY on a pure relative descent in a QUOTE-FREE cd segment.
# Every climb-out / relaxation direction (a quote byte, absolute arg, `..`, arg-less cd, `cd -`,
# `cd ~`, `$VAR`/command-substitution) is a NO-OP that LEAVES the prefix unchanged. Rationale (C1): a
# forged *descent* via quote-desync could relax (compose a deeper, ordinary path), so a quoted cd
# segment is not trusted; a forged *climb-out* (absolute/..) is ignored, so the prior real prefix
# survives and the real target still composes → DENY. A no-op only ever RETAINS denials (composition
# is unioned with the literal token), so it is never worse than today — fail-closed by construction.
# The desync attack `cd hooks && echo "z || cd /tmp" && tee pre-push`: the bogus ` cd /tmp"` segment is
# BOTH quoted and absolute → no-op → $_CP8B_EFF stays `hooks` → `tee pre-push` composes hooks/pre-push
# → DENY. (Leg K-D binds this; K-A binds the accumulator itself.)
_cp8b_eff_update() {  # $1 = the cd segment ; reads/writes $_CP8B_EFF
  if _cp8b_has_quote "$1"; then return; fi
  _ea=$(_cp8b_cd_arg "$1")
  case "$_ea" in
    ''|-|'~'*|/*|*..*|*'$'*|*'`'*) return ;;
  esac
  if [ -z "$_CP8B_EFF" ]; then _CP8B_EFF=$(_cp8b_norm "$_ea")
  else _CP8B_EFF=$(_cp8b_norm "$_CP8B_EFF/$_ea"); fi
}

# _cp8b_compose "<token>": composed normalized path (effective-dir ⊕ token) on stdout; rc 1 if the
# token is not composable (no effective dir, or an absolute token). Part B reuses the :1426 fixpoint.
_cp8b_compose() {
  [ -n "$_CP8B_EFF" ] || return 1
  case "$1" in /*) return 1 ;; esac
  _cp8b_norm "$_CP8B_EFF/$1"
}

# _cp8b_composed_is_cp "<token>": 0 iff the token, dequoted and `flag=`-stripped (like _cp8b_tok_is_cp
# :609 — defect 2: else `dd if=/tmp/x of=pre-push` composes hooks/of=pre-push and escapes), composes
# to a control-plane path against the effective dir.
_cp8b_composed_is_cp() {
  _ct2=$(_cp8b_dequote "$1"); case "$_ct2" in *=*) _ct2=${_ct2#*=} ;; esac
  _cc=$(_cp8b_compose "$_ct2") || return 1
  [ -n "$_cc" ] && is_control_plane_target "$_cc"
}

# _cp8b_tad_redir_cp "<segment>": 0 iff a redirect TARGET bails to the deny side — either it classifies
# control-plane (literal ∨ composed) OR it is a NON-LITERAL target (GUARD-CP-WRITE-ROUTES Cure 2, via
# the shared _redir_targets disqualifier). Returning 0 makes the read/kit-exec recognition DECLINE, so a
# `sh conformance/verify.sh > $(echo hooks/pre-push)` is no longer laundered — the pathhit trigger then
# fires on the CP substring the reader was pointed at. The classification loop (composed-vs-plain) is
# kept per-caller so the cd-composition catch (`cd hooks && … > pre-push`) survives (K-R-COMPOSED); the
# split adopts _cp8b_redirect_hits_cp's `set -f` discipline (R2), not the old bare `for`.
_cp8b_tad_redir_cp() {
  case "$1" in *'>'*) : ;; *) return 1 ;; esac
  _rt=$(_redir_targets "$1") || return 0   # rc 2 => a non-literal target => fail closed (K-R1a)
  [ -n "$_rt" ] || return 1
  _rg=0; case "$-" in *f*) _rg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_rt
  while [ $# -gt 0 ]; do
    if [ -n "$1" ]; then
      is_control_plane_target "$1" && { [ "$_rg" = 1 ] || set +f; return 0; }
      _cp8b_composed_is_cp "$1" && { [ "$_rg" = 1 ] || set +f; return 0; }
    fi
    shift
  done
  [ "$_rg" = 1 ] || set +f
  return 1
}

# Part C allow-side. _cp8b_tad_is_read "<segment>": a read-recognized segment never denies. A segment
# carrying a REDIRECT is read-recognized only when the redirect target is NOT control-plane (E5) — this
# is why the two mandatory flips fire: `printf`/`echo` are read verbs (:973), so without E5 narrowing
# `cd hooks && printf x > pre-push` would relax. The read set is CP-8a's stdout-only list, REUSED and
# PINNED (M1): awk/sed/find/sort/less/xxd/uniq stay OUT — each carries a write/exec escape and admitting
# any fails OPEN under the lifted gate. E2 adds git READ subcommands, safe only because the old
# scan-arm still denies `git diff --output=<cp>` (§9(b)); do not retire the old arm.
# C4 Arm 1 (E4a, face a) tier 1 — PLAIN-LIST adds: stdout-only readers, each verified to carry NO
# file-write flag in any form (jq writes only via shell redirect, which E5 already narrows via the
# `>`-target bail at :1180, so `shellcheck cp.sh > hooks/pre-push` stays DENY). Sole consumer of this
# list is _cp8b_tad_is_read (Finding 4 confirmed). `sort`/`less` stay OUT (sort -o writes, less
# shell-escapes); awk/sed/find stay OUT (E4b rejected). `yq`/`tree` are NOT here — they carry
# file-write flags and are handled by the decline-on-any-flag conditional arm below.
_CP8B_READ_VERBS='grep egrep fgrep rg ls cat head tail wc diff stat file du cut tr nl od hexdump column tac comm cmp basename dirname realpath readlink echo printf which type shellcheck jq shasum md5 cksum yamllint'
_CP8B_GIT_READ_SUBS='commit status blame describe add diff log show grep stash ls-files'
_cp8b_in_list() { for _w in $2; do [ "$_w" = "$1" ] && return 0; done; return 1; }
# _cp8b_seg_has_flag "<seg>": 0 iff ANY token after the leading verb begins with '-'. The
# decline-on-ANY-flag disqualifier for the yq/tree conditional read arm (vet Finding 1): genuine
# fail-by-disqualification, NOT a write-flag denylist (a denylist fails OPEN on the next unknown write
# flag — exactly the `yq -s <expr>` hole the vet caught).
_cp8b_seg_has_flag() {
  _pgf=0; case "$-" in *f*) _pgf=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -gt 0 ] && shift               # drop the leading verb
  while [ $# -gt 0 ]; do
    case "$1" in -*) [ "$_pgf" = 1 ] || set +f; return 0 ;; esac
    shift
  done
  [ "$_pgf" = 1 ] || set +f
  return 1
}
# _cp8b_seg_is_shell_n "<seg>": 0 iff the segment is EXACTLY a shell syntax check — the second token is
# EXACTLY `-n` and NO other token begins with `-`. Fail-by-disqualification, mirroring
# _cp8b_seg_has_flag: `-x` executes, `-nc` executes, `-n -c '<cmd>'` executes, and any second flag is an
# unknown, so all of them decline and fall through to the existing deny path. F2-KL pins the exact
# match: relaxing it to "any flag" read-recognizes `sh -x <cp>`, which EXECUTES the file.
_cp8b_seg_is_shell_n() {
  _pnf=0; case "$-" in *f*) _pnf=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -ge 3 ] || { [ "$_pnf" = 1 ] || set +f; return 1; }   # verb + -n + at least one file
  shift                                                      # drop the lead verb (sh|bash|dash)
  [ "$1" = "-n" ] || { [ "$_pnf" = 1 ] || set +f; return 1; }
  shift
  while [ $# -gt 0 ]; do
    case "$1" in -*) [ "$_pnf" = 1 ] || set +f; return 1 ;; esac
    shift
  done
  [ "$_pnf" = 1 ] || set +f
  return 0
}
# === GUARD-READ-LANE-2 F-b — `sed -n <range>p` and `awk <NR-range>` as a GRAMMAR TIER ==============
# The D1 build invariant is UNTOUCHED: `sed`/`awk` are NOT in _CP8B_READ_VERBS (each carries a write and
# an exec escape, so a lexicon entry fails OPEN — `sed -i`, `awk '{print > "<cp>"}'`, `awk '{system(…)}'`).
# They get the `sh -n` precedent instead (_cp8b_seg_is_shell_n above): a recogniser that accepts ONE
# EXACT grammar and DECLINES everything else, so every unknown spelling keeps today's deny.
# Two tiers, ONE source of truth:
#   • the ALLOW tier (`_cp8b_seg_is_sed_n "<seg>"` / `_cp8b_seg_is_awk_range "<seg>"`), wired into
#     _cp8b_tad_is_read below — numeric/NR ranges only, plus full path-token hygiene;
#   • the MESSAGE tier (`… "<seg>" msg`), the ONLY caller of which is _cp8b_seg_read_shaped's sed/awk
#     arm (F-h). It answers a WEAKER question — "is this shaped like a read?" — for a segment that is
#     denying either way, so it declines to judge the operands (a loop body's `$f` is a path it cannot
#     see) and admits sed's ADDRESSED read `/re/p`. Both tiers run the SAME script test, so a mutation
#     of the grammar moves both (the K-COUPLE-SED leg proves the fold is a call, not a copy).
# WHY `/re/p` IS IN THE MESSAGE TIER BUT NOT THE ALLOW TIER: measured safe as a read (a regex ADDRESS
# cannot write, and with exactly two unescaped delimiters and `p` as the only command there is no room
# for a `w`/`e` COMMAND — a `w`/`e` BYTE inside the delimiters is data). It is nonetheless DECLINED on
# the allow side because design §8 prices it out deliberately: the escape is `grep`, one retry, and a
# regex-address grammar is a strictly larger attack surface for a strictly smaller refund. Pinned both
# ways — `sed -n '/re/p' <cp>` DENIES, and its denial does not advertise the kill switch.
_CP8B_SED_SCRIPT_RO='^[0-9]+(,([0-9]+|\$))?p$'
_CP8B_SED_SCRIPT_ADDR='^/[^/\\]*/p$'
# _cp8b_seg_sed_script_ro "<script>" [msg]: 0 iff the (already quote-stripped) sed script is read-only.
# The SOLE grammar site for both tiers. `w`, `e`, `r`, `s///w`, a second command, an unanchored suffix
# — all decline here, which is why the trailing `p$` anchor is load-bearing (M-B1 pins it: a `w` admitted
# here turns `sed -n 1,5w<cp> <file>`, a real WRITE, into an ALLOW).
_cp8b_seg_sed_script_ro() {
  printf '%s' "$1" | grep -Eq "$_CP8B_SED_SCRIPT_RO" && return 0
  [ "${2:-}" = msg ] || return 1
  printf '%s' "$1" | grep -Eq "$_CP8B_SED_SCRIPT_ADDR"
}
# _cp8b_seg_qstrip "<token>": the token with EXACTLY ONE matching surrounding quote pair removed (both
# `'` or both `"`, or none). Prints the stripped token; rc 0 = it was unquoted, 2 = single-quoted,
# 3 = double-quoted, 1 = DECLINE. Declines on a backslash ANYWHERE and on any quote byte LEFT INSIDE
# after the strip — an orphan (`'s/x/y/w`, the quote-blind segmenter's half of a quoted script), a glued
# `a'b'c`, an empty `''`. This is how the grammars stay quote-honest without a quote parser: a token the
# one-pair rule cannot account for is not judged, and not-judged means today's deny.
_cp8b_seg_qstrip() {
  case "$1" in *\\*) return 1 ;; esac
  _qsv=$1; _qsq=0
  case "$_qsv" in
    "'"?*"'") _qsv=${_qsv#\'}; _qsv=${_qsv%\'}; _qsq=2 ;;
    '"'?*'"') _qsv=${_qsv#\"}; _qsv=${_qsv%\"}; _qsq=3 ;;
  esac
  case "$_qsv" in *\'*|*\"*) return 1 ;; esac
  printf '%s' "$_qsv"
  return "$_qsq"
}
# _cp8b_seg_path_ok "<token>": 0 iff the token is a plain PATH OPERAND — non-empty, does not begin with
# `-` (else `sed -n 1p -i` would read as a path), and carries no `$`, backtick, `<`, `>`. An unresolved
# expansion is exactly the GUARD-KIT-EXEC-REDIRECT-UNRESOLVED-TARGET shape; neither grammar accepts one.
# ⚠️ THE `&&`/`||` FORM IS DEFENSIVE, NOT STYLE. `_cp8b_seg_qstrip` reports the quoting KIND in its exit
# status (2/3), and this core is sourced into `set -eu` shells (the conformance delta replay does exactly
# that), where a plain `X=$(…)` on a non-zero status is an abort waiting for the right shell. MEASURED
# HONESTLY: it does NOT reproduce today — every call site sits in an `&&`/`||`/`if` list, where `set -e`
# is suppressed — so this spelling carries no conformance leg (one was written and deleted as vacuous).
# It is kept because the cost is one line and the failure mode is a silent ALLOW-becomes-DENY.
# _cp8b_seg_word_shape_ok "<UNQUOTED token>": 0 iff the shell cannot turn this one token into MORE than
# one word, or into a `-`-led word. Two shapes can: BRACE expansion (`{-delete,-print}` — one inert
# token to a `set -f` word-split, two `-`-led words to bash) and a LEADING glob (`*delete`, `?delete`,
# `[-]delete` — expands to whatever filenames exist, and a pre-planted `./-delete` is a flag). A glob
# that is not first (`conformance/*.sh`) can only ever expand to words under that literal prefix, so it
# stays a path and stays allowed. CALLERS MUST GATE THIS ON UNQUOTEDNESS: `'{a,b}'` and `-name '*.sh'`
# are inert to the shell and must keep passing.
_cp8b_seg_word_shape_ok() {
  case "$1" in *'{'*|*'}'*|*','*) return 1 ;; esac
  case "$1" in '*'*|'?'*|'['*) return 1 ;; esac
  return 0
}
_cp8b_seg_path_ok() {
  case "$1" in ''|-*|*'$'*|*'`'*|*'<'*|*'>'*|*';'*|*'&'*|*'|'*) return 1 ;; esac
  _pkv=$(_cp8b_seg_qstrip "$1") && _pkq=0 || _pkq=$?
  [ "$_pkq" != 1 ] || return 1
  [ "$_pkq" = 0 ] || return 0                   # quoted: the shell expands nothing inside it
  _cp8b_seg_word_shape_ok "$_pkv"
}
# _cp8b_seg_is_sed_n "<seg>" [msg]: the sed grammar. ALLOW tier = `sed`, EXACTLY `-n`, ONE script token,
# ≥1 path tokens, nothing else. Any other flag (`-i`, `-e`, `-f`, `-E`, `-s`, `--expression=…`), a second
# script, or a flag-shaped operand declines — fail-BY-DISQUALIFICATION, the F2-KL precedent, never a
# write-flag denylist (which fails open on the next unknown flag).
_cp8b_seg_is_sed_n() {
  if [ "${2:-}" = msg ]; then
    # The message tier keeps T4's shape — a read-FLAG allowlist plus the SHARED script test — because
    # its subject is a segment that DENIES either way and whose operands may be things it cannot
    # classify (a loop body's `$f`). The write escapes it would otherwise have to find are already
    # tested, over the WHOLE segment, by _cp8b_fh_write_escape before this is ever reached.
    _cp8b_fh_flags_ok "$1" '-n' || return 1
    _cp8b_seg_sed_script_ro "$(_cp8b_fh_first_operand "$1")" msg
    return
  fi
  _cp8b_seg_sed_n_strict "$1"
}
_cp8b_seg_sed_n_strict() (
  set -f
  # shellcheck disable=SC2086  # word-splitting the segment into tokens IS the parse
  set -- $1
  [ $# -ge 3 ] || return 1
  _sdl=$(_cp8b_dequote "${1:-}"); [ "${_sdl##*/}" = sed ] || return 1
  shift
  [ "$1" = "-n" ] || return 1
  shift
  [ $# -ge 2 ] || return 1                      # the script token + at least one path
  _sds=$(_cp8b_seg_qstrip "$1") && _sdq=0 || _sdq=$?   # see the set -e note at _cp8b_seg_path_ok
  [ "$_sdq" != 1 ] || return 1
  shift
  _cp8b_seg_sed_script_ro "$_sds" || return 1
  while [ $# -gt 0 ]; do
    _cp8b_seg_path_ok "$1" || return 1
    shift
  done
  return 0
)
# _cp8b_seg_is_awk_range "<seg>" [msg]: the awk grammar. ALLOW tier = `awk`, an OPTIONAL single `-F<sep>`
# (metachar-free), ONE program token, ≥1 path tokens. The program, quote-stripped, must be an anchored
# `NR` comparison or `{print}`; `{print $N}` is admitted ONLY when the token was SINGLE-quoted, because
# in any other quoting the `$` belongs to the shell. `-v`, `-f`, `-e`, `--source`, `system(`, `getline`,
# a bare `>` anywhere, a second program: decline.
_CP8B_AWK_PROG_RO='^NR *(<=|>=|==|<|>) *[0-9]+( *&& *NR *(<=|>=|<|>) *[0-9]+)?$|^\{ *print *\}$'
_CP8B_AWK_PROG_FIELD='^\{ *print *\$[0-9]+ *\}$'
_cp8b_seg_is_awk_range() {
  # The message tier is the flag allowlist ALONE, by the same argument as sed's: the program token of a
  # denied segment is often something the grammar cannot judge (`END{print NR}`, a printf format), and
  # KEEPING the kill-switch sentence there is the exact mis-training F-h exists to stop. The write
  # escapes (`>`, `system(`, `getline`, an in-place flag) are already tested over the whole segment.
  if [ "${2:-}" = msg ]; then _cp8b_fh_flags_ok "$1" '-F'; return; fi
  _cp8b_seg_awk_range_strict "$1"
}
_cp8b_seg_awk_range_strict() (
  set -f
  # shellcheck disable=SC2086  # word-splitting the segment into tokens IS the parse
  set -- $1
  [ $# -ge 3 ] || return 1
  _awl=$(_cp8b_dequote "${1:-}"); [ "${_awl##*/}" = awk ] || return 1
  shift
  case "$1" in
    -F?*) case "$1" in *'$'*|*'`'*|*\\*|*\'*|*\"*|*'<'*|*'>'*) return 1 ;; esac; shift ;;
    -*)   return 1 ;;
  esac
  [ $# -ge 2 ] || return 1                      # the program token + at least one path
  _awp=$(_cp8b_seg_qstrip "$1") && _awq=0 || _awq=$?  # see the set -e note at _cp8b_seg_path_ok
  [ "$_awq" != 1 ] || return 1
  shift
  if ! printf '%s' "$_awp" | grep -Eq "$_CP8B_AWK_PROG_RO"; then
    [ "$_awq" = 2 ] || return 1                 # `{print $N}` is a SINGLE-quoted-only refund
    printf '%s' "$_awp" | grep -Eq "$_CP8B_AWK_PROG_FIELD" || return 1
  fi
  while [ $# -gt 0 ]; do
    _cp8b_seg_path_ok "$1" || return 1
    shift
  done
  return 0
)
# === GUARD-READ-LANE-2 F-e — `find` as a read through a PRIMARY ALLOWLIST =========================
# Same build invariant, same shape as F-b: `find` is NOT in _CP8B_READ_VERBS. It carries a write escape
# (`-delete`, `-fprint`, `-fprintf`, `-fls`) AND an exec escape (`-exec`, `-execdir`, `-ok`, `-okdir`),
# so a lexicon entry fails OPEN. It gets a recogniser that accepts ONE grammar and declines everything
# else, and the grammar is spelled as an ALLOWLIST of primaries (design §6): an unlisted primary
# OVER-DENIES rather than escaping, which is why `-ls` and `-printf` — both harmless reads — are DENY
# today and admitting them is a one-line ratified add rather than a drip.
# THE LEAD IS TESTED BARE: `find`, de-quoted, with NO basename strip. A pathful lead cannot reach here
# anyway (every dispatch site keys on `_cp8b_lead`, which neither de-quotes nor basenames), so a strip
# here would be dead code claiming a relief that does not exist. This is the SAME net behaviour T6
# shipped for `sed`; both pathful spellings are celled as disclosed over-denies in agent-autonomy.sh.
# ARITY IS PART OF THE ALLOWLIST. `-mtime -1`, `-size +1k`, `-maxdepth 1` put a token AFTER a primary,
# and for `-mtime`/`-size` that token is `-`-led. A flag-shaped walk with no arity would read `-1` as an
# unknown primary and decline a real read; one that skipped arity entirely would read `-1` as a path.
# So the allowlist is split in two: which primaries exist, and which of them consume the next token.
_CP8B_FIND_RO_PRIMARIES='-name -iname -path -ipath -regex -iregex -type -maxdepth -mindepth -mtime -mmin -newer -size -empty -print -print0 -prune -depth -L -H -P -xdev -o -a -not ! ( )'
_CP8B_FIND_RO_ARITY1='-name -iname -path -ipath -regex -iregex -type -maxdepth -mindepth -mtime -mmin -newer -size'
# GUARD-READ-LANE-3 F-h — the verbs `-exec` may run and still be a READ.
# ***THE ENFORCEMENT IS THE PAIR: THIS LIST **AND** THE OPERAND GRAMMAR BELOW.*** An earlier draft of
# this comment claimed the list was "the whole enforcement — the only thing separating `-exec cat {} +`
# from `-exec sh -c … {} +` is membership here". THAT WAS FALSE, and it was falsified by measurement
# (reviewer M-1): with `sed cp tee xargs rm sh` ALL planted in this list, only `-exec tee {} +` flips to
# ALLOW. `-exec rm` and `-exec xargs rm` stay denied by the flat destructive matrix; `-exec sed -i
# s/a/b/ {}`, `-exec sh -c 'id' {}` and `-exec cp /tmp/e {}` stay denied because each carries a BARE
# OPERAND and the sub-grammar admits none. So the list alone holds exactly the verbs whose dangerous
# form needs no operand — which is why mutant M-Fh is anchored on `tee`: it is the one probe that
# isolates this list. Neither half is sufficient; both are load-bearing. It is DELIBERATELY NOT
# `_CP8B_READ_VERBS`, for the reason lane 2's F-a gate lexicon was not either (design §3-F-a, seat
# findings 4–5): that list contains `file`, and `file -C -m X` WRITES `X.mgc`. Every member below
# takes a path and emits to stdout; none has a documented write flag.
# ***THE NEVER-ADD CLASS.*** No interpreter (`sh`, `bash`, `python3`, `perl`, `awk`), no in-place
# editor (`sed`, `ed`, `perl -i`), no copier or writer (`cp`, `mv`, `tee`, `dd`, `install`, `ln`),
# no `xargs`/`env`/`nice`/`timeout` (each runs a program of the caller's choosing), and not `file`
# or `sort` (`sort -o` writes). A member added here is a control-plane WRITE surface, not a
# convenience: it costs a ratified deny-removal and a write-cousin cell, exactly like a lexicon entry.
# ***AND THE FLAG SLOT IS PART OF THE CONTRACT*** (security seat MED-1). The sub-grammar lets a member
# carry its own `-`-led flags, so a member must have NO write mode reachable through a flag — not a
# `--flag=value` one (structurally refused in the walk: any `=` in the slot declines) and not a
# SEPARATE-VALUE one either, which the `=` refusal does NOT catch. `-o <file>`, `-w <file>`,
# `--output <file>` on a future member would be an unguarded control-plane write with a read-looking
# verb in front of it. Vet the flag surface of the verb, not just its default behaviour, before adding.
# ***AND NO VERB WITH A FLAG THAT TAKES AN OUTPUT PATH — the OPERAND GRAMMAR, not the verb list alone,
# is the invariant*** (reviewer I-2). A separate-value flag (`-o <file>`) reaches the slot as a `-`-led
# token followed by a BARE operand, and the bare-operand refusal is what stops it — not this list. The
# two rules protect different halves and a member must satisfy BOTH: no operand-free write (this list)
# and no write reachable through a flag value (the grammar). Measured cousins are celled F-h W15/W15b.
_CP8B_FIND_EXEC_READ_VERBS='cat head tail wc nl od cksum md5 md5sum shasum sha1sum sha256sum stat grep'
# _cp8b_seg_find_exec_ro: the F-h sub-grammar, entered ONLY on a de-quoted `-exec` token, and TERMINAL
# — it consumes the rest of the segment and the segment must end at its `+`. Positional parameters are
# the remaining tokens AFTER `-exec`. `$_fdm` (msg tier) is read from the caller's scope, exactly as
# the surrounding walk does. Shape: <read-verb> [flag-operands…] {} + , with EXACTLY one `{}`, `+` as
# the LAST token, and NO literal operand (a literal path there is the verb's target, not the match —
# `find conformance -exec cat .claude/hooks/guard-core.sh +` is a read of an ARGUMENT, and admitting
# it would let the operand slot carry anything). `\;` is NOT admitted: it carries a backslash, and the
# `D-240813-3` decline set is absolute on that byte — the disclosed over-deny is celled, escape is `+`.
_cp8b_seg_find_exec_ro() {
  [ $# -ge 3 ] || return 1
  _cp8b_in_list "$(_cp8b_dequote "$1")" "$_CP8B_FIND_EXEC_READ_VERBS" || return 1
  shift
  _fxb=0
  while [ $# -gt 1 ]; do
    _fxt=$(_cp8b_dequote "$1")
    case "$_fxt" in
      '{}') _fxb=$((_fxb + 1)) ;;
      # A `-`-led token is the VERB'S OWN FLAG (`head -5`, `wc -l`, `grep -c`). ***IT MAY NOT CARRY A
      # `=` VALUE*** (security seat MED-1, measured DENY on 5d26fbfa -> ALLOW on the first build of this
      # branch): `--output=.claude/x` is one token, is `-`-led, passes the operand hygiene test, and was
      # accepted — so the slot was a silent CONTROL-PLANE-NAMED value the walk never classified. No verb
      # on `_CP8B_FIND_EXEC_READ_VERBS` has a `--flag=value` write mode TODAY, which is exactly why this
      # must be structural and not a lexicon judgement: the day one gains one, the slot is a write.
      # Refusing the whole `=` shape is the disqualification-shaped cure (a CP-token test on the value
      # would be a parse of the value, and would still miss a non-CP-named path that resolves into the
      # tree). Disclosed over-deny: `grep --count` is fine, `grep --count=2` declines; the escape is the
      # short flag. Celled `F-h W15`.
      -*)   case "$_fxt" in *'='*) return 1 ;; esac
            [ "$_fdm" = msg ] || _cp8b_seg_find_operand_ok "$1" || return 1 ;;
      *)    return 1 ;;
    esac
    shift
  done
  [ "$_fxb" = 1 ] || return 1                      # exactly one `{}` — the match, once
  [ "$(_cp8b_dequote "$1")" = '+' ] || return 1     # and the segment ENDS here
  return 0
}
# _cp8b_seg_find_primary_ok "<tok>": 0 iff the token is an allowlisted primary/operator. THE SOLE
# allowlist site for BOTH tiers — the allow tier below and the message tier (F-h) share it, so a
# mutation of the allowlist moves both and they cannot drift (K-COUPLE-FIND proves this behaviourally).
# The token is looked up raw first, then DE-QUOTED, because grouping parens reach the guard escaped
# (`\(`) and a user may quote any primary. De-quoting cannot widen THIS LOOKUP — `'-delete'` and
# `"-exec"` normalise to tokens that are still not on the list.
# ⚠️ THAT IS TRUE OF THE LOOKUP AND WAS FALSE OF THE WALK, and the difference shipped a bypass: the walk
# used to run its UNKNOWN-primary test (`case -*`) on the RAW token, so a quoted escape — which starts
# with a QUOTE byte, not `-` — missed the test, fell through to the PATH-operand arm, and was accepted
# as a path while the shell stripped the quotes and find executed it. The walk now de-quotes ONCE and
# judges BOTH questions off the de-quoted token; the raw token is kept only for the path-operand test.
_cp8b_seg_find_primary_ok() {
  _cp8b_in_list "$1" "$_CP8B_FIND_RO_PRIMARIES" && return 0
  _cp8b_in_list "$(_cp8b_dequote "$1")" "$_CP8B_FIND_RO_PRIMARIES"
}
# _cp8b_seg_find_operand_ok "<tok>": the hygiene test for a token consumed as a primary's OPERAND. It
# may be `-`-led (`-mtime -1`), which is the only thing that distinguishes it from _cp8b_seg_path_ok;
# everything else is the same refusal — an unresolved expansion, a redirect byte, a segmenter byte.
# It takes the SAME word-shape refusal as the path arm, and for a slot-specific reason: `-name *`
# unquoted is expanded by the SHELL, not by find, so the tokens find actually receives are filenames the
# guard never saw — a pre-planted `./-delete` among them lands as a `-`-led word. `-name '*.sh'` is
# quoted, inert, and unaffected; that refund is celled.
_cp8b_seg_find_operand_ok() {
  case "$1" in ''|*'$'*|*'`'*|*'<'*|*'>'*|*';'*|*'&'*|*'|'*) return 1 ;; esac
  _fnv=$(_cp8b_seg_qstrip "$1") && _fnq=0 || _fnq=$?
  [ "$_fnq" != 1 ] || return 1
  [ "$_fnq" = 0 ] || return 0                   # quoted: the shell expands nothing inside it
  _cp8b_seg_word_shape_ok "$_fnv"
}
# _cp8b_seg_find_arity_shape_ok "<de-quoted tok>": the SHAPE test for that same operand slot, and the
# reason it exists is that the slot used to be unchecked — `find <cp> -name -exec cp /tmp/e {} +` had
# its escape SWALLOWED as `-name`'s operand and the walk then accepted the rest. Real find errors on
# that, but the guard was fail-OPEN by construction, and a shape the guard cannot judge must decline.
# The slot admits a `-`-led token for exactly one reason (`-mtime -1`, `-size -1k`), so that is exactly
# what it admits: a `-` followed by digits, with at most one trailing size/time unit letter. Every
# escape name (`-exec`, `-delete`, `-fprint`, `-ls`, …) is alphabetic after the `-` and cannot pass.
_cp8b_seg_find_arity_shape_ok() {
  case "$1" in -*) ;; *) return 0 ;; esac
  _fas=${1#-}
  case "$_fas" in *[!0-9]) _fas=${_fas%[bcwkMGTP]} ;; esac
  case "$_fas" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}
# _cp8b_seg_is_find_ro "<seg>" [msg]: the find grammar. ALLOW tier = lead EXACTLY `find`, then every
# token is an allowlisted primary, that primary's operand, or a clean PATH operand. Anything else —
# `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-fprint`, `-fprintf`, `-fls`, `-ls`, `-printf`, any
# unknown primary, an expansion-carrying operand — declines, and declining is today's deny.
# The MESSAGE tier (F-h) answers the WEAKER question, exactly as sed's and awk's do: its subject is a
# segment that denies either way and whose operands may be things it cannot classify (a loop body's
# `$f`), so it judges the PRIMARIES only and leaves the operands alone. The write escapes it would
# otherwise have to find are already tested, over the whole segment, by _cp8b_fh_write_escape.
_cp8b_seg_is_find_ro() {
  if [ "${2:-}" = msg ]; then _cp8b_seg_find_walk "$1" msg; return; fi
  _cp8b_seg_find_walk "$1"
}
_cp8b_seg_find_walk() (
  _fdm=${2:-}                      # captured BEFORE `set --` overwrites the positional parameters
  set -f
  # shellcheck disable=SC2086  # word-splitting the segment into tokens IS the parse
  set -- $1
  [ $# -ge 2 ] || return 1
  _fdl=$(_cp8b_dequote "${1:-}"); [ "$_fdl" = find ] || return 1
  shift
  while [ $# -gt 0 ]; do
    _fdq=$(_cp8b_dequote "$1")                    # DE-QUOTE ONCE; both judgments below run off it
    # GUARD-READ-LANE-3 F-h — `-exec` is handled HERE, before the primary allowlist, and is
    # deliberately NOT a member of `_CP8B_FIND_RO_PRIMARIES` (adding it there would make it an
    # ordinary primary whose operands are judged as paths — the `-exec cp /tmp/e {} +` hole lane 2's
    # mutant M-E1 exists to catch). The sub-grammar is TERMINAL: it either accepts the whole
    # remainder or declines, so no token after `-exec` is ever judged by the primary walk.
    if [ "$_fdq" = -exec ]; then
      shift
      _cp8b_seg_find_exec_ro "$@" || return 1
      return 0
    fi
    if _cp8b_seg_find_primary_ok "$_fdq"; then
      if _cp8b_in_list "$_fdq" "$_CP8B_FIND_RO_ARITY1"; then
        [ $# -ge 2 ] || return 1                  # a primary with no operand is a malformed find
        shift
        _cp8b_seg_find_arity_shape_ok "$(_cp8b_dequote "$1")" || return 1
        [ "$_fdm" = msg ] || _cp8b_seg_find_operand_ok "$1" || return 1
      fi
      shift
      continue
    fi
    case "$_fdq" in -*) return 1 ;; esac          # an UNKNOWN primary — the allowlist's whole point
    [ "$_fdm" = msg ] || _cp8b_seg_path_ok "$1" || return 1
    shift
  done
  return 0
)
# $2 (optional) is F-a's MASKED view of the same segment, used for the redirect bail ALONE: a `>` that
# lies inside a quoted span is a character in an argument, not an operator. It defaults to $1, so every
# caller that does not know about the mask keeps today's behaviour exactly. Everything below — the
# lexicon lookup, the conditional tiers, the sed/awk/find grammars — runs on $1, the TRUE bytes.
_cp8b_tad_is_read() {
  case "${2:-$1}" in *'>'*) _cp8b_tad_redir_cp "${2:-$1}" && return 1 ;; esac
  _rv=$(_cp8b_lead "$1")
  _cp8b_in_list "$_rv" "$_CP8B_READ_VERBS" && return 0
  # C4 Arm 1 tier 2 (face a) — CONDITIONAL readers `yq`/`tree`. Both carry file-write flags
  # (`yq -i` in place; `yq -s/--split-exp <expr>` writes an expression-named file — no CP token in
  # argv; `tree -o <file>`). DECLINE-ON-ANY-FLAG: read-recognized ONLY when the segment carries NO
  # `-`-leading token at all (pure `yq '<expr>' <file>`, `yq . <file>`, `tree <dir>`). Any flag ->
  # decline -> fall through to the existing deny path. Over-deny on harmless flags (`yq -P`,
  # `tree -H`) is an accepted, disclosed FP. K-H pins this decline.
  # GUARD-FP-RELIEF-2 Arm C (face 3) — `actionlint` joins this SAME conditional tier, deliberately NOT
  # _CP8B_READ_VERBS: `-shellcheck=<cmd>` and `-pyflakes=<cmd>` make it run an arbitrary program, an
  # exec primitive, so the plain list is unavailable. Decline-on-any-flag keeps both exec-flag forms
  # DENY with zero enumeration; over-deny on `-oneline`/`-color` is a disclosed FP, the `yq -P` trade.
  # Bare `actionlint` was never denied (no control-plane token in argv). F2-KK pins the decline.
  case "$_rv" in
    yq|tree|actionlint) _cp8b_seg_has_flag "$1" || return 0 ;;
  esac
  # GUARD-FP-RELIEF-2 Arm D (face 4) — `sh|bash|dash -n <file>` is a shell SYNTAX CHECK. POSIX `-n`
  # reads and parses without executing, so this is a READ arm, not an exec arm, and the file argument
  # may be any path: reading a control-plane script for syntax is already granted via `cat`/`shellcheck`
  # (capability-equivalent). zsh/ksh are excluded — unmeasured need, add on evidence. The E5 redirect
  # bail at the top of this function runs FIRST, so `sh -n cp.sh > hooks/pre-push` stays DENY.
  case "$_rv" in
    sh|bash|dash) _cp8b_seg_is_shell_n "$1" && return 0 ;;
  esac
  # GUARD-READ-LANE-2 F-b — `sed`/`awk` join the SAME conditional tier, deliberately NOT
  # _CP8B_READ_VERBS (build invariant M1: a lexicon entry would read-recognise `sed -i`, `awk
  # '{print > "<cp>"}'` and `awk '{system("…")}'` — it fails OPEN, which is why the D1-M1 mutant leg
  # exists). One exact grammar each; everything else declines to today's deny. The E5 redirect bail at
  # the top of this function runs FIRST, so `sed -n 1,5p cp.sh > .claude/out` stays DENY.
  case "$_rv" in
    sed) _cp8b_seg_is_sed_n "$1" && return 0 ;;
    awk) _cp8b_seg_is_awk_range "$1" && return 0 ;;
  esac
  # GUARD-READ-LANE-2 F-e — `find` joins the same conditional tier on the same argument (a lexicon
  # entry would read-recognise `-exec`/`-delete`). The E5 redirect bail above runs FIRST, so
  # `find conformance -name '*.sh' -printf '%p' > .claude/out` stays DENY.
  case "$_rv" in
    find) _cp8b_seg_is_find_ro "$1" && return 0 ;;
  esac
  if [ "$_rv" = git ]; then
    _rgs=$(_cp8b_git_sub "$1")
    _cp8b_in_list "$_rgs" "$_CP8B_GIT_READ_SUBS" && return 0
  fi
  return 1
}

# E1′ — kit-script EXECUTION exemption (NARROW). Lead sh/bash/dash/zsh/ksh + a conformance/*.sh |
# scripts/*.sh | scripts/kit-guard | scripts/sparkwright script token (bare or ./-prefixed), NO
# redirect, AND every OTHER token still classified. The broad "exempt the whole segment" form fails
# OPEN (`sh conformance/verify.sh .claude/hooks/guard-core.sh` would ALLOW); the narrow form re-denies
# it. Script ARGUMENTS stay unexamined (already the D3′ ceiling). (Leg K-E binds this — C2.)
# C4 Arm 2 (face b) — wrapper-prefix RECOGNITION strip. Produces a recognition-copy of a kit-exec
# segment with vetted benign wrappers peeled, so `timeout 600 sh conformance/verify.sh` is recognized
# as the kit-exec it wraps. Fail-by-disqualification: each shape strips ONLY its exact vetted form;
# anything else (a flag, an env assignment, a non-numeric timeout value) STOPS the loop, leaving a
# non-shell / non-kit lead -> not kit-exec -> deny (over-deny, safe). Bounded to 3 iterations; a
# residual non-wrapper lead breaks earlier. Used ONLY inside _cp8b_tad_is_kit_exec (constraint ii:
# the copy NEVER leaves this arm — deny reasons keep printing the original $_seg).
#   env    : BARE only (constraint i / vet Finding 2) — any following NAME=value assignment OR any
#            flag disqualifies (keeps `env KIT_GUARD_SELFEDIT=1 …`, `env PATH=/tmp …`, `env -i …` DENY;
#            K-F pins both the assignment and the flag leg).
#   timeout: `timeout <[0-9]+[smhd]?>` — a flagged/non-numeric value (`timeout -s KILL`) disqualifies.
#   nice   : bare `nice`, or `nice -n <digits>` — any other flag, or a non-digit -n value
#            (`nice -n hooks/pre-push`), disqualifies.
#   command: bare `command` — `command -v/-p/-V` disqualifies.
# GUARD-FP-RELIEF-2 Arm B (face 2) adds two more tokens in the same grammar:
#   time   : BARE only — any flag (`time -p`) disqualifies (disclosed over-deny). F2-KJ pins it.
#   {      : the bare `{` token of a brace group. Safe by the same recognition-copy argument: the RAW
#            segment still feeds every trigger, so `{ rm -rf conformance` stays DENY (lead after the
#            strip is `rm`, not a shell) and `{ sh cp.sh > hooks/pre-push` still bails on the redirect.
#
# GUARD-FP-RELIEF-2 Arm A (face 1) — the VETTED ASSIGNMENT-PREFIX allowlist. A leading `NAME=value`
# token is peeled from the recognition copy ONLY when NAME is a member of this list AND the value
# passes `_cp8b_assign_val_safe`. Membership IS the whole enforcement: it fails closed on every unknown
# name, so all nine measured face-1 negatives keep their DENY with ZERO deny-side edits.
#
# ***THE NEVER-ADD CLASS — the line this list does not cross.*** This arm precedes a kit-script
# EXECUTION, so the danger is CODE-LOADING / EXEC-ENVIRONMENT variables. Permanently excluded, and no
# future "reasonable" widening may include them: PATH, IFS, LD_PRELOAD, LD_LIBRARY_PATH,
# DYLD_INSERT_LIBRARIES, DYLD_LIBRARY_PATH, BASH_ENV, ENV, SHELLOPTS, and the whole GIT_* family
# (GIT_SSH_COMMAND, GIT_EXTERNAL_DIFF, GIT_PAGER … each names a program git will run). Interpreter
# option variables (NODE_OPTIONS, PERL5OPT, PYTHONSTARTUP, RUBYOPT) are the same class and are equally
# excluded — they look harmless and are not. KIT_* names are never vetted either (KIT_GUARD_SELFEDIT is
# the kill switch, KIT_PUSH_CITE a dial), but note KIT_* in command TEXT is inert — `selfedit_allowed`
# reads the guard's OWN process env, not `$cmd` — so the exec-env family above, not KIT_*, is the
# security-load-bearing exclusion (security vet MED-1).
#
# Contents are MEASURED-USAGE ONLY (owner ruling, design 2026-08-15 §8-Q1/A2): LANG/TZ are vet-confirmed
# exec-inert and were still held out, because monotone add-only makes a token near-irreversible and
# every token owes an evidence-backed leg. Widening costs one token plus one leg, on a measured denial.
_CP8B_VETTED_ASSIGN='SELFTEST LC_ALL'
# _cp8b_assign_val_safe "<value>": 0 iff the value is a plain literal with no shell-active byte.
# ***BUILD MANDATE (security vet HIGH-1).*** This MUST be the decline-on-any-bad-char NEGATED-CLASS
# idiom and MUST NEVER become a positive match: `grep -Eq '^[A-Za-z0-9._:/-]+'` anchors only the HEAD,
# so `SELFTEST=x$(rm -rf conformance)` would satisfy it, strip clean, and ALLOW while the substitution
# executes — fail-by-parse wearing a disqualification costume, the exact class D-240813-3 bans. The
# metachar-FIRST forms (`SELFTEST=$(whoami)`) decline under BOTH builds and cannot tell them apart;
# the valid-char-then-metachar fixtures and mutant F2-KI2b are what pin the idiom itself.
_cp8b_assign_val_safe() {
  case "$1" in ''|*[!A-Za-z0-9._:/-]*) return 1 ;; esac
  return 0
}
# _cp8b_peel_lead_assign "<seg>": drop a leading well-formed `NAME=value` token and the whitespace
# after it. The pattern re-states the SAME character class the disqualifier enforces, so for every
# NON-EMPTY value a mutant that flips only _cp8b_assign_val_safe SURVIVES — this pattern rejects the
# same value a second time. That is why F2-KI2/F2-KI2b flip BOTH halves and honestly pin the PAIR, as
# the C4 literal-side-conjunction leg does.
# THE REDUNDANCY IS NOT TOTAL, and the earlier "no fixture can separate them" claim was FALSE (review
# F1, falsified by measurement): the value pattern is `*` (zero-or-more) while the disqualifier also
# rejects the EMPTY value, so `SELFTEST= sh <kit-script>` separates the halves — a val_safe-only mutant
# IS killable there. Mutant F2-KI2c pins that half ALONE via the empty-value leg. Keep the `*`: making
# it `+` would re-orphan that mutant by restoring total redundancy.
_cp8b_peel_lead_assign() {
  printf '%s' "$1" | sed -E 's%^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._:/-]*[[:space:]]+%%'
}
_cp8b_strip_wrappers() {
  _sw=$1
  _swi=0
  while [ "$_swi" -lt 3 ]; do
    _swl=$(_cp8b_lead "$_sw")
    _sw2=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*//' | awk '{print $2}')
    case "$_swl" in
      timeout)
        case "$_sw2" in [0-9]*) : ;; *) break ;; esac         # value must start with a digit
        case "$_sw2" in *[!0-9smhd]*) break ;; esac           # ... and be a pure [0-9]+[smhd]? duration
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*timeout[[:space:]]+[0-9]+[smhd]?[[:space:]]+//') ;;
      nice)
        case "$_sw2" in
          -n)
            _sw3=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*//' | awk '{print $3}')
            case "$_sw3" in ''|*[!0-9]*) break ;; esac        # `nice -n` needs a digit value
            _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*nice[[:space:]]+-n[[:space:]]+[0-9]+[[:space:]]+//') ;;
          -*) break ;;                                        # any other flag disqualifies
          *) _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*nice[[:space:]]+//') ;;   # bare nice
        esac ;;
      command)
        case "$_sw2" in -*) break ;; esac                     # command -v/-p/-V disqualify
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*command[[:space:]]+//') ;;
      env)
        [ -n "$_sw2" ] || break                               # `env` with no argument -> nothing to strip
        case "$_sw2" in -*|*=*) break ;; esac                 # BARE env only (constraint i; K-F pins)
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*env[[:space:]]+//') ;;
      time)
        case "$_sw2" in ''|-*) break ;; esac                  # BARE time only; `time -p` disqualifies
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*time[[:space:]]+//') ;;
      '{')
        [ -n "$_sw2" ] || break                               # a lone `{` has nothing to peel toward
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*\{[[:space:]]+//') ;;
      *=*)
        # Arm A: vetted-NAME assignment prefix. Both tests must pass or the loop breaks (-> deny).
        _swn=${_swl%%=*}; _swv=${_swl#*=}
        _cp8b_in_list "$_swn" "$_CP8B_VETTED_ASSIGN" || break
        _cp8b_assign_val_safe "$_swv" || break
        # TIGHTEN (security vet Finding 1, owner chose the narrowing cure): decline the peel when the
        # VALUE itself classifies control-plane. Without this the peel removes a CP-classifying token
        # from the recognition copy BEFORE the kit-exec token walk sees it, so
        # `SELFTEST=hooks/pre-push sh <kit-script>` would ALLOW — and it is NOT equivalence-covered,
        # because the two-statement spellings (`SELFTEST=hooks/pre-push ; sh …`, `export SELFTEST=…`)
        # both DENY (measured). This is ALLOW-side narrowing (a peel we decline to perform), not a deny
        # edit. Both spellings of the target are checked, exactly as _cp8b_tad_redir_cp does:
        #   literal  — `SELFTEST=hooks/pre-push …`                              (F2-KI3 pins)
        #   composed — `cd hooks && SELFTEST=pre-push …`, which composes to hooks/pre-push under the
        #              effective dir and was MEASURED ALLOW under a literal-only cure (F2-KI3b pins).
        # Both helpers take the whole `NAME=value` token: each already dequotes and strips the `flag=`
        # prefix, so they classify the VALUE by the same rule the token walk and composed trigger use.
        _cp8b_tok_is_cp "$_swl" && break
        _cp8b_composed_is_cp "$_swl" && break
        # Shape-restricted peel: name and value were both validated above, so this matches exactly the
        # lead token. A non-match makes no progress and the ≤3 bound then exits with a non-shell lead
        # -> not kit-exec -> deny (over-deny, safe).
        _sw=$(_cp8b_peel_lead_assign "$_sw") ;;
      *) break ;;
    esac
    _swi=$((_swi + 1))
  done
  printf '%s' "$_sw"
}
_cp8b_tad_is_kit_exec() {
  # FIX 2: mirror E5's read-arm narrowing — bail (fall through to deny) ONLY when a redirect TARGET
  # classifies control-plane. An fd-dup (`2>&1`, `>&2`, `N>&M`) and an ordinary target (`> /tmp/out`)
  # are non-targets, so the canonical `sh conformance/verify.sh 2>&1` / `> /tmp/out.log` stay kit-exec.
  # `_cp8b_tad_redir_cp` reuses the effective-dir compose, so `cd hooks && sh …verify.sh > pre-push`
  # still bails and denies (target composes to hooks/pre-push). An input `<` redirect target that is
  # control-plane is caught downstream by the literal-token walk below (a read, never a write).
  # C4 Arm 2 constraint iii: the redirect bail runs on the RAW `$1` FIRST, BEFORE wrapper stripping.
  # F-3 (T8 review): `$2`, when given, is the METACHAR VIEW of the same segment (the masked copy, in
  # which a quoted `>` is a sentinel and only a real operator is a `>`); `$1` stays the TRUE-BYTE view
  # the lexicon lookups below need. Every other caller passes one argument and is byte-unchanged.
  case "${2:-$1}" in *'>'*) _cp8b_tad_redir_cp "${2:-$1}" && return 1 ;; esac
  # C4 Arm 2: peel vetted benign wrappers into a recognition-copy (`_kx`). Consumed ONLY below —
  # never fed to the outer trigger evaluation (:1311-1313) or the effective-dir logic (constraint ii).
  # SAFETY IS STRUCTURAL, NOT TEST-GUARDED: `_kx` is function-local and `$_seg`/`$1` are untouched
  # downstream, so no fixture pins this. A future refactor that assigns `_seg=$_kx` (leaking the
  # stripped copy back to the triggers) would NOT be caught by any mutant — the strip set is all
  # non-CP tokens, so such a leak cannot flip a verdict today, which is exactly why it is unmutatable
  # (design §10-A3, mutant K-F2 dropped-with-rationale). Keep `_kx` read-only to this arm.
  _kx=$(_cp8b_strip_wrappers "$1")
  _kv=$(_cp8b_lead "$_kx")
  case "$_kv" in
    sh|bash|dash|zsh|ksh) _ksc=$(printf '%s' "$_kx" | sed -E 's/^[[:space:]]*//' | awk '{print $2}') ;;
    *) _ksc=$_kv ;;
  esac
  _ksc=$(_cp8b_dequote "$_ksc"); _ksc=${_ksc#./}
  case "$_ksc" in
    conformance/*.sh|scripts/*.sh|scripts/kit-guard|scripts/sparkwright) : ;;
    *) return 1 ;;
  esac
  _kpg=0; case "$-" in *f*) _kpg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_kx
  while [ $# -gt 0 ]; do
    _kt=$(_cp8b_dequote "$1"); _kt=${_kt#./}
    if [ "$_kt" != "$_ksc" ] && _cp8b_tok_is_cp "$1"; then [ "$_kpg" = 1 ] || set +f; return 1; fi
    shift
  done
  [ "$_kpg" = 1 ] || set +f
  return 0
}

# GUARD-READONLY-FP-RELIEF Arm A — the kit-exec READ-ONLY QUERY allowlist (cures register faces
# (f1)+(h) in ONE arm). `_cp8b_tad_is_kit_exec` above declines the WHOLE segment as soon as any
# token OTHER than the script classifies control-plane. That disqualifier is right for an unknown
# script (a CP path in argv may be a WRITE target — `sh conformance/verify.sh <cp>` must stay DENY),
# and wrong for the handful of DECLARED query modes whose entire job is to be ASKED about a path:
#   sh scripts/kit-guard path <cp>                                  — ask the guard about a path
#   sh conformance/promotion-readiness.sh --class --changed <listing>  — the ENTRY CONTRACT's act 1
#   sh conformance/agent-boundary.sh --changed <listing> --ratified 0  — its act-1 cross-check
#
# A PAIR MUST NAME A SCRIPT THAT EXISTS. The first cut of this table listed `conformance/phase-gate.sh`
# one merge after that script was parked and deleted: the arm is a pure token match and never stats the
# file, so the allow was unprovable and the behavioural lock below passed over a pair that could not run
# (GUARD-ALLOWLIST-OUTLIVES-ITS-SCRIPT). The lock now asserts existence before it runs a pair, so a
# table entry that outlives its script REDs by name instead of passing vacuously.
#
# THE ENFORCEMENT IS THE DECLARED TABLE, NOT A PARSE (D-240813-3: fail-by-parse cures are banned).
# `_cp8b_kit_query_toks` is the whole allowlist: an unknown script yields the empty set and the arm
# DECLINES, so every unlisted kit script keeps today's verdict with zero deny-side edits — the
# `_CP8B_VETTED_ASSIGN` shape. Adding a pair costs one table line, one leg, and a green coupling lock.
#
# ⚠️ READ-ONLINESS IS LOCKED BEHAVIORALLY, NOT BY REVIEW MEMORY (security vet M1). Every pair in this
# table is RUN against a fixture control-plane argument by `conformance/agent-autonomy.sh`'s Arm-A
# coupling lock, which asserts the repo worktree is byte-unchanged afterwards. A pair that GAINS a
# write path reds that lock. A grep-lock over this list would have been fail-by-hope.
#
# Decline-on-ANY (each is a disqualifier, so a bug here over-denies):
#   · any redirect byte (`<` or `>`) in the segment — `… --path CLAUDE.md > conformance/out.txt`
#   · any `$` / backtick — the guard reads PRE-shell-parse bytes and cannot resolve them
#   · any `..` byte in the script token (belt; the anchored exact table match is the primary)
#   · a script token that is not an EXACT table key after `./`-stripping (no path-alias spellings)
#   · a FIRST post-script token outside the declared set — this is what keeps the WRITER subcommand
#     `scripts/kit-guard install-shims` off the arm
#   · ANY other flag-shaped token outside the declared set (vet M1: presence-matching `--class` alone
#     would let `--class --<writer>` ride). Note the declared sets are per-script SETS, not a single
#     flag: `--class --changed` is already two flag tokens, so a literal one-flag rule could not cure
#     the named face. Non-flag tokens after the query token are DATA (the coupling lock is what makes
#     that safe), which is why a quoted `kit-guard cmd "<probe>"` still recognizes.
# The script position is POSITIONAL (token 1, or token 2 after a bare interpreter): an interpreter
# FLAG (`sh -x …`, `sh -c …`) or an env-assignment prefix lands in the script slot, misses the table
# and declines.
_cp8b_kit_query_toks() {
  case "$1" in
    scripts/kit-guard)                  printf '%s' 'path cmd mcp' ;;
    conformance/promotion-readiness.sh) printf '%s' '--class --changed' ;;
    conformance/agent-boundary.sh)      printf '%s' '--changed --ratified' ;;
    # GUARD-READ-LANE-3 F-i (design §2 R6, "the worst FP in the corpus"): the kit's own branch-protection
    # check, invoked as its own header documents, is refused because its ARGUMENT lives under `profiles/`.
    # ⚠️ SCOPE NARROWED FROM THE DESIGN, ON MEASUREMENT — see the §9 small bet in the build report.
    # §3 Part 2 proposed admitting the WHOLE registered set (97 basenames off `verify.sh`'s dispatch
    # lines). The bet's two halves came back clean — no registered check parses a write-mode flag, none
    # has a literal repo-path write target, and a BEHAVIOURAL run of all 97 in their heaviest mode
    # (`--selftest`) against a `git status --porcelain` oracle mutated the worktree ZERO times — but the
    # third measurement decided it: that run cost **381 s** (with five checks still truncated at a 25 s
    # cap). The Arm-A coupling lock is what makes THIS table safe, and it is safe precisely because it
    # RUNS every declared pair on every `agent-autonomy.sh` invocation. A 97-script lock cannot ride in
    # verify.sh or CI, and a table widened past the lock is the "fail-by-hope" this arm's own header
    # bans. So F-i lands as what the lock can carry: one measured pair, one lock line, one census bump.
    # The generalised form is boarded with its cost as evidence (GUARD-KIT-QUERY-REGISTERED-SET).
    conformance/branch-protection.sh)   printf '%s' '--declared-only' ;;
  esac
}
_cp8b_tad_is_kit_query() {
  case "$1" in *'>'*|*'<'*) return 1 ;; esac
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _kqg=0; case "$-" in *f*) _kqg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -gt 0 ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  case "$1" in sh|bash|dash|zsh|ksh) shift ;; esac      # bare interpreter lead: script is next
  [ $# -gt 0 ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  _kqs=$(_cp8b_dequote "$1"); _kqs=${_kqs#./}; shift
  case "$_kqs" in *..*) [ "$_kqg" = 1 ] || set +f; return 1 ;; esac
  _kqv=$(_cp8b_kit_query_toks "$_kqs")
  [ -n "$_kqv" ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  [ $# -gt 0 ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  _cp8b_in_list "$1" "$_kqv" || { [ "$_kqg" = 1 ] || set +f; return 1; }
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) _cp8b_in_list "$1" "$_kqv" || { [ "$_kqg" = 1 ] || set +f; return 1; } ;;
    esac
    shift
  done
  [ "$_kqg" = 1 ] || set +f
  return 0
}

# GUARD-READONLY-FP-RELIEF Arm B — shell TEST EXPRESSIONS (cures register face N1). `test -f <cp>`
# and `[ -f <cp> ]` interrogate a path's METADATA; neither builtin can mutate the path it names, so
# a control-plane token there is DATA in the strictest sense.
#
# ***THE LEAD SET IS `test` AND `[` ONLY — `if`/`elif` ARE DELIBERATELY EXCLUDED*** (security vet C1,
# substantiated live). `if`/`elif` do not introduce a test EXPRESSION; they introduce a COMMAND whose
# exit status is tested. `if rm <cp>; then :; fi` and `if node write.js <cp>; then :; fi` both wear
# the same "lead + operands" shape as a real test and both MUTATE. Re-adding either keyword to this
# case arm is a write-surface widening, and mutant M-B2 in agent-autonomy.sh exists to catch exactly
# that. An `if [ -f <cp> ]` false positive is cured only TRANSITIVELY — when the segmenter yields the
# inner `[ …` as its own segment; otherwise it keeps today's deny plus the §3 tip.
#
# Decline-on-ANY (a bug here over-denies): any redirect byte; any `$`/backtick; any flag-shaped token
# that is not EXACTLY a single-letter operator (`-exec`, `--remove`, `-pi` all decline — a long flag
# is an unknown, and the numeric comparators `-eq`/`-lt`/… decline with them, a disclosed over-deny
# on expressions that carry no path anyway); any token that is a known mutator verb.
# The mutator-verb list is a BELT: `_cp8b_control_plane_denied`'s verb regex already denies every
# member on this route, so no fixture can separate the two (stated, not claimed as coverage — the
# `_kx` precedent at C4 Arm 2). It is kept because the two lists drift independently.
_CP8B_TEST_MUTATORS='rm rmdir mv cp ln dd tee sed chmod chown install rsync shred truncate patch awk find sort uniq xxd git'
_cp8b_tad_is_test_expr() {
  case "$1" in *'>'*|*'<'*) return 1 ;; esac
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _teg=0; case "$-" in *f*) _teg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -gt 0 ] || { [ "$_teg" = 1 ] || set +f; return 1; }
  case "$1" in test|'[') shift ;; *) [ "$_teg" = 1 ] || set +f; return 1 ;; esac
  while [ $# -gt 0 ]; do
    case "$1" in
      -[A-Za-z]) : ;;                                    # a single-letter test operator
      -*) [ "$_teg" = 1 ] || set +f; return 1 ;;         # -exec / --remove / -pi / -eq -> unknown
      ']'|'!'|'='|'!='|'-') : ;;                          # expression punctuation
      *) if _cp8b_in_list "$1" "$_CP8B_TEST_MUTATORS"; then [ "$_teg" = 1 ] || set +f; return 1; fi ;;
    esac
    shift
  done
  [ "$_teg" = 1 ] || set +f
  return 0
}

# E3 — message carriers: git commit/merge/tag + gh pr/issue/release with a message flag and NO
# redirect. A control-plane hit is inside the message DATA, not a target (an injected `;` splits to its
# own segment and is judged there). The enforcement counterpart of the advisory _cp8b_message_tip.
_cp8b_tad_is_msg_carrier() {
  case "$1" in
    *"git commit"*|*"git merge"*|*"git tag"*|*"gh pr"*|*"gh issue"*|*"gh release"*) : ;;
    *) return 1 ;;
  esac
  case "$1" in *'>'*) return 1 ;; esac
  printf '%s' "$1" | grep -Eq '(^|[[:space:]])(-m|-F|--message|--body|--body-file|--notes|--title)([=[:space:]]|$)'
}

# _cp8b_tad_pathhit "<segment>": trigger 1 — string-level pathhit (single source of truth).
_cp8b_tad_pathhit() { _cp8b_pathhit "$1"; }

# _cp8b_tad_literal_tok "<segment>": trigger 2 — a LITERAL token classifies control-plane (M2 union:
# the literal arm is retained alongside the composed arm; a climb-out desync can never remove it).
_cp8b_tad_literal_tok() {
  _lpg=0; case "$-" in *f*) _lpg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  while [ $# -gt 0 ]; do
    if _cp8b_tok_is_cp "$1"; then [ "$_lpg" = 1 ] || set +f; return 0; fi
    shift
  done
  [ "$_lpg" = 1 ] || set +f
  return 1
}

# _cp8b_tad_composed_tok "<segment>": trigger 3 — a cd-COMPOSED token (or composed redirect target)
# classifies control-plane.
_cp8b_tad_composed_tok() {
  [ -n "$_CP8B_EFF" ] || return 1
  _cts=$1                                # capture BEFORE set -- consumes the positionals (FIX 1)
  _cpg=0; case "$-" in *f*) _cpg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  while [ $# -gt 0 ]; do
    if _cp8b_composed_is_cp "$1"; then [ "$_cpg" = 1 ] || set +f; return 0; fi
    shift
  done
  [ "$_cpg" = 1 ] || set +f
  # A GLUED redirect (`>pre-push`) is one token that composes to `hooks/>pre-push` (not CP), so the
  # loop above misses it; the redirect-target parse recovers the bare target. Passing $1 here was DEAD
  # CODE — the loop's `shift` empties the positionals, so the old `"$1"` was always "" (FIX 1).
  _cp8b_tad_redir_cp "$_cts"
}

# E6 — cp/install destination-binding: judge the copy DESTINATION (literal last token, per :1004-1005,
# OR the composed destination), not "any control-plane token" — so `cp conformance/verify.sh /tmp/b`
# (copy-OUT) stays ALLOW while `cd conformance && cp /tmp/x verify.sh` denies. Declines to close the
# open GUARD-CP-HARDLINK-ALIAS row (cp -l aliasing) — leaves it exactly as today, stated not claimed.
_cp8b_tad_cp_dest_denied() {
  _cp8b_cp_target_in last "$1" && return 0
  _cd=$(printf '%s' "$1" | awk '{for(i=NF;i>=1;i--) if(substr($i,1,1)!="-"){print $i; exit}}')
  _cp8b_composed_is_cp "$_cd" && return 0
  _cp8b_tad_redir_cp "$1"
}

# _cp8b_redir_launder_denied "<seg>": GUARD-CP-WRITE-ROUTES Cure 2 outright-deny — a READER / KIT-EXEC
# segment whose redirect target is NON-LITERAL (glob / $VAR / $(…) / backslash — _redir_targets rc 2)
# denies OUTRIGHT. Such a launder verb (printf/cat/`sh conformance/verify.sh`) declined recognition
# above precisely because its target disqualified; when there is ALSO no literal control-plane substring
# to trip the pathhit trigger (`printf x > hooks/pre-pus*` — a glob the shell would expand onto the real
# hook), nothing else denies it. This arm is that closer, and it is the disclosed `reader > $OUT`
# over-deny made real. SCOPED to reader/kit-exec (the disclosed ceiling, not every verb): recognition is
# re-tested on a redirect-STRIPPED copy, so an ordinary `make > $OUT` is NOT a laundering verb and stays
# allowed. Reuses the shared _redir_targets disqualifier (K-R1a pins this arm's disqualifier).
#
# GUARD-READONLY-FP-RELIEF Arm G(i) — THE CLOSE (this half DENIES MORE). Recognition ran on the
# segment's own lead, so wrapping the laundering verb in a brace group or subshell moved the redirect
# into a `}`/`)`-led segment this arm did not recognize, and the whole Cure-2 closure fell to two
# bytes: `{ printf evil ; } > $VAR/pre-push` and `( printf evil ) > $VAR/pre-push` were both MEASURED
# ALLOW at the 2026-08-19 probe. `_cp8b_strip_group` peels the group tokens and recognition is
# re-tested on the residual; a segment that is ONLY a group CLOSE (or has no verb at all — a bare
# `> $V/pre-push` truncate) is itself the laundering site and denies.
# DISCLOSED OVER-DENY, fixtured both ways: this is scoped by SEGMENT SHAPE, not by what the group
# contains — those live in a different segment. So `{ make ; } > $OUT` now denies while the bare
# `make > $OUT` still allows (the deliberate "not a laundering verb" scope). Spell the target
# literally, or drop the braces.
_cp8b_strip_group() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*[{(][[:space:]]+//; s/[[:space:]]*[})][[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}
_cp8b_redir_launder_denied() {
  case "$1" in *'>'*) : ;; *) return 1 ;; esac
  _redir_targets "$1" >/dev/null && return 1   # rc 0 => every target is a plain literal => not this arm
  _lnr=$(printf '%s' "$1" | sed -e 's/[0-9]*>>*.*$//')   # drop from the first redirect operator onward
  # T8 review finding F-3 — TWO VIEWS, and the caller passes the MASKED segment. That is right for the
  # metachar work above (`case *'>'*`, `_redir_targets`, and this strip): on the masked copy only a
  # REAL redirect operator is still a `>`. It is WRONG for the lexicon lookups below, which key on the
  # lead verb: a sentinel byte anywhere in the lead token names no verb, so the arm would fall through
  # and ALLOW. `_lnu` is the true-byte view for those; `$_lnr` is handed on as the metachar view via
  # the recognisers' second parameter, so their own redirect bails keep seeing real operators only.
  _lnu=$(_cp8b_unmask_quoted "$_lnr")
  # T8 review finding F-4 — and the lead is judged DE-QUOTED, T7's cure one function over. MEASURED at
  # pristine 4b3debc3 and at 41d4278e: `grep x > .cl*/hooks/gu*` DENIED here while `'grep' x >
  # .cl*/hooks/gu*` ALLOWED — the raw lead token `'grep'` matched no read verb, this arm declined, and
  # the glob (which resolves to guard-core.sh ALONE) truncated the guard. One pair of quotes. M-L1
  # pins it. De-quoting can only ever make this arm recognise MORE laundering verbs, i.e. deny more.
  _lnd=$(_cp8b_dequote_lead "$_lnu")
  _cp8b_tad_is_read "$_lnd" "$_lnr" && return 0
  _cp8b_tad_is_kit_exec "$_lnd" "$_lnr" && return 0
  _lng=$(_cp8b_dequote_lead "$(_cp8b_strip_group "$_lnu")")
  case "$_lng" in ''|'}'|')') return 0 ;; esac           # a bare group CLOSE / verbless redirect
  _cp8b_tad_is_read "$_lng" "$_lnr" && return 0
  _cp8b_tad_is_kit_exec "$_lng" "$_lnr" && return 0
  return 1
}

# _cp8b_target_reason "<segment>" "<trigger>": signpost the composition and name the cheap escape.
_cp8b_target_reason() {
  _trs=$(printf '%s' "$1" | cut -c1-160)
  printf '13: writes/executes against a resolved control-plane target (guard / CI gates / conformance) - denied (control-plane integrity; trigger=%s). Offending segment: [%s].%s%s%s' "$2" "$_trs" "$(_cp8b_message_tip "${_tad_raw:-}" "$1")" "$(_cp8b_trigger_tip "$2")" "$(_cp8b_selfedit_hint "$1" "${_tad_raw:-}")"
}

# C4 Arm 3 (face c) — remote-URL token disqualification for git-lead segments. Replaces each WHOLE
# url-shaped token with the placeholder `REMOTE-URL`: a remote URL is not a local write target, so its
# `.git` suffix / any CP substring inside it must not classify. A token is url-shaped iff it is
# SCHEME-BEARING (https|http|ssh|git ://) or SCP-FORM (user@host:path). `file://` is NEVER masked (a
# file URL IS a filesystem path — and its `.git` write stays DENY via the raw clone-dest arm). Masking
# is TOKEN-BOUNDED, never greedy (vet Finding 3, K-G2 pins): `[^[:space:]]*` stops at whitespace, so a
# following CP destination (`… .git hooks`) is never swallowed. No CP path is scheme-bearing or
# scp-shaped, so masking url-shaped tokens can never erase a real CP path token.
_cp8b_mask_remote_urls() {
  printf '%s' "$1" | sed -E \
    -e 's#(^|[[:space:]])(https|http|ssh|git)://[^[:space:]]*#\1REMOTE-URL#g' \
    -e 's#(^|[[:space:]])[A-Za-z0-9._~-]+@[A-Za-z0-9._-]+:[^[:space:]]*#\1REMOTE-URL#g'
}

# _cp8b_target_arm_denied "<cmd>": PREDICATE - Parts A+B+C. Prints the reason and returns 0 to deny.
_cp8b_target_arm_denied() {
  _tad_raw=$1
  # GUARD-READ-LANE-2 T1, half 2 (design §5) — same pre-check, same reason shape as the old arm.
  if _cp8b_piped_interp_hit "$1"; then _cp8b_target_reason "$_cp8b_pi_seg" pathhit; _cp8b_pi_note; return 0; fi
  # Arm E: a quoted heredoc BODY is inert data. F-a (T8): and a quoted separator is not a separator.
  _walk=$(_cp8b_segments "$(_cp8b_mask_quoted "$(_cp8b_strip_heredocs "$1")")")
  _CP8B_EFF=''
  while _cp8b_next_seg; do
    [ -n "$(printf '%s' "$_seg" | tr -d '[:space:]')" ] || continue
    _segm=$_seg                                        # F-a: see the two-views note in the old arm
    case "$_seg" in *["$_cp8b_mk_all"]*) _seg=$(_cp8b_unmask_quoted "$_seg") ;; esac
    _lv=$(_cp8b_lead "$_seg")
    if [ "$_lv" = cd ]; then _cp8b_eff_update "$_seg"; continue; fi
    case "$_lv" in pushd|popd) continue ;; esac        # dir change we cannot track -> no-op (keep prefix)
    _cp8b_tad_is_read "$_seg" "$_segm" && continue
    # DELIBERATE ASYMMETRY, fail-closed: `_cp8b_tad_is_read` above gets BOTH views ($_seg and the masked
    # $_segm) because the mask is what refunds a quoted separator INSIDE a read; kit-exec gets the
    # UNMASKED view only, so a kit-script segment is judged on its raw bytes and can never be exempted
    # on the strength of a mask. One argument here is the narrower answer, not a missing one.
    _cp8b_tad_is_kit_exec "$_seg" && continue
    _cp8b_tad_is_kit_query "$_seg" && continue   # Arm A: a DECLARED read-only kit query (see the table)
    _cp8b_tad_is_test_expr "$_seg" && continue   # Arm B: a `test`/`[` metadata expression
    _cp8b_tad_is_msg_carrier "$_seg" && continue
    case "$_lv" in
      cp|install)
        if _cp8b_tad_cp_dest_denied "$_seg"; then _cp8b_target_reason "$_seg" cp-dest; return 0; fi
        continue ;;
    esac
    # C4 Arm 3: for a git-lead segment, evaluate the three CP triggers on a recognition-copy in which
    # url-shaped tokens are masked (a remote URL's `.git` suffix is not a local write target). Reasons
    # print the ORIGINAL $_seg. The raw clone-DESTINATION arm (_cp8b_git_write_denied :806) and the
    # push-to-main floor run on the RAW string and are untouched, so `git clone <url> .claude`,
    # `git clone <url> hooks`, `git push <url> main` stay DENY. K-G pins the git-lead guard.
    _tad_c=$_seg
    if [ "$_lv" = git ]; then _tad_c=$(_cp8b_mask_remote_urls "$_seg"); fi
    if _cp8b_tad_pathhit "$_tad_c"; then _cp8b_target_reason "$_seg" pathhit; return 0; fi
    if _cp8b_tad_literal_tok "$_tad_c"; then _cp8b_target_reason "$_seg" token; return 0; fi
    if _cp8b_tad_composed_tok "$_tad_c"; then _cp8b_target_reason "$_seg" composed; return 0; fi
    # GUARD-CP-WRITE-ROUTES Cure 2: last, a reader/kit-exec laundering a non-literal redirect target
    # (no literal CP substring above to catch it — the pure-glob route) denies outright.
    # F-a: the LAUNDER arm is a redirect test, so it reads `$_segm` for the same reason the `[<>]` bail
    # does — `echo "=== DIFF (before -> after) ==="` has no redirect in it, and calling its quoted `->`
    # a non-literal target is precisely the false positive. A REAL `> $(…)` is untouched: it is outside
    # every quoted span, so the mask never reached it. The reason still prints the restored `$_seg`.
    if _cp8b_redir_launder_denied "$_segm"; then _cp8b_target_reason "$_seg" redir-nonliteral; return 0; fi
  done
  return 1
}

# _cp8b_push_main_denied "<cmd>": PREDICATE - the push-to-main rule, SCOPED to a segment.
# The flat rule is the FLOOR (it denies); this may only ALLOW BACK when no single segment carries both
# the push and the main/master refspec - i.e. when the flat regex only ever matched by SPANNING a shell
# separator, which is precisely the false positive:
#     git push -u origin fix/x && gh pr create --body "... merges to main"
# This is NOT the rewriting CP-8a forbade: that was splitting the command and REJOINING it with ';',
# which perturbed the OTHER ~40 rules. Here only this ONE rule's window narrows; every other rule still
# sees the raw, unsplit string (`curl x | sh` keeps its pipe, `--admin` keeps its end-of-string anchor).
_cp8b_push_main_denied() {
  _walk=$(_cp8b_segments "$1")
  while _cp8b_next_seg; do
    if printf '%s' "$_seg" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*[^a-zA-Z0-9_.-](main|master)([^a-zA-Z0-9_.-]|$)'; then
      return 0
    fi
  done
  return 1
}

# GUARD-READONLY-FP-RELIEF Arm F — the `git config core.hooksPath` READ/WRITE split (cures register
# face N4; N5 rides along). ***THIS MATCHER IS THE GUARD-DISABLE CROWN JEWEL*** — the same rule that
# over-denies `git config --get core.hooksPath` (asking what the hooks path IS, a pure read) is the
# rule that denies `git config core.hooksPath /tmp/evil`, the primary way an agent switches the
# guard off. So the split is built DEFAULT-DENY (security vet H2): a segment that matches the
# hooksPath matcher DENIES unless it is POSITIVELY recognized as one of the declared query forms.
#
# PER-OCCURRENCE, never per-command: the decision walks segments, so
# `--get … && git config core.hooksPath /tmp/e` (E5) is judged on the WRITE segment and stays DENY.
#
# THE GUARD-DISABLE VECTOR `git config core.hooksPath /tmp/evil` IS HELD BY TWO INDEPENDENT GUARDS,
# and it takes BOTH to open it (measured — the honest claim, corrected after review I4):
#   (1) the query-flag-required line `[ -n "$_gcq" ] || return 1` below — with no query flag the
#       segment is not a read; and
#   (2) the operand-count bound in the trailing `case "$_gcq"` — a `--get` with a value token exceeds
#       the bound and denies.
# `core.hooksPath /tmp/evil` carries no query flag AND two operands, so EACH guard denies it alone: a
# mutant of ONE survives because the OTHER still fires (defence in depth, not redundancy claimed as
# coverage). Only the PAIR opens it — that is why the gate-time kill is M-F6 (removes both, flips it),
# not a single-guard mutant. M-F1 and M-F5 each show one guard alone still holds.
#
# NEVER RECOGNIZED AS A READ, by construction (vet H2 + L2): any segment whose second token is not
# literally `config` — which is what keeps `-c`/`-C`/`--exec-path` carriers off this arm — and any
# segment carrying an option outside the two declared lists. The PRE-EXISTING inline-`-c` hole
# (`git -c core.hooksPath=/tmp/evil <subcmd>` ALLOWs today, because the flat matcher below requires
# `git config` adjacency) is UNCHANGED here and boarded as GUARD-GIT-INLINE-C-HOOKSPATH-HOLE; this
# arm must never be widened to "recognize" such a segment.
# DISCLOSED RIDER (probe surprise 9): `--get-regexp` takes a PATTERN, so a key-spelling that matches
# `core.hooks` without spelling `core.hooksPath` never reaches the flat matcher at all — pre-existing,
# unchanged, and not claimed closed.
_CP8B_GITCFG_QUERY='--get --get-all --get-regexp --get-urlmatch --list -l'
# Read-side scope/output modifiers, each verified to select or format a READ and never to write.
# `--file`/`--blob`/`--config-env`/`-c` are deliberately ABSENT: default-deny sends them to the deny.
_CP8B_GITCFG_SCOPE='--global --local --system --worktree --null -z --name-only --show-origin --show-scope'
_cp8b_gitcfg_is_read() {
  case "$1" in *'>'*|*'<'*) return 1 ;; esac
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _gcg=0; case "$-" in *f*) _gcg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  if [ "${1:-}" != git ];    then [ "$_gcg" = 1 ] || set +f; return 1; fi
  shift
  if [ "${1:-}" != config ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi
  shift
  _gcq=''; _gco=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -*)
        if _cp8b_in_list "$1" "$_CP8B_GITCFG_QUERY"; then
          if [ -n "$_gcq" ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi   # two query flags: unknown
          _gcq=$1
        elif _cp8b_in_list "$1" "$_CP8B_GITCFG_SCOPE"; then
          :
        else
          [ "$_gcg" = 1 ] || set +f; return 1                               # DEFAULT-DENY on unknowns
        fi ;;
      *) _gco=$((_gco + 1)) ;;
    esac
    shift
  done
  if [ -z "$_gcq" ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi   # <== THE CROWN-JEWEL LINE (M-F1)
  case "$_gcq" in
    --list|-l)      if [ "$_gco" -ne 0 ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi ;;
    --get-urlmatch) if [ "$_gco" -gt 2 ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi ;;
    *)              if [ "$_gco" -gt 1 ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi ;;
  esac
  [ "$_gcg" = 1 ] || set +f
  return 0
}
# N5 — a commit/PR MESSAGE that merely NAMES the key is data, not a config write. The exemption is
# narrowed beyond `_cp8b_tad_is_msg_carrier` by a `$`/backtick decline: without it,
# `git commit -m "$(git config core.hooksPath /tmp/evil)"` would wear the message costume while the
# substitution ran the real write (measured DENY today; it must stay DENY).
# ***REVIEW C1 (2026-08-19): the exemption MUST anchor on the LEADING token pair, not a substring.***
# `_cp8b_tad_is_msg_carrier` is a substring match, so a trailing shell COMMENT
# (`git config core.hooksPath /tmp/evil # git commit -m x`) put the `git commit` bytes anywhere in the
# segment and stole the exemption while the REAL lead ran the hooksPath write — measured ALLOW on the
# branch, DENY on main, a write-path widening this slice opened. A genuine message carrier LEADS with
# `git commit`/`gh pr`/…, so keying on the first two whitespace-normalized tokens closes it and moves
# no other verdict (the F3 comment-suffix battery + mutant M-F7 pin it).
_cp8b_gitcfg_msg_data() {
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _gmd=$(printf '%s' "$1" | sed -E 's/^[[:space:]]*//; s/[[:space:]]+/ /g' | cut -d' ' -f1,2)
  case "$_gmd" in
    "git commit"|"git merge"|"git tag"|"git notes"|"gh pr"|"gh issue"|"gh release") : ;;
    *) return 1 ;;
  esac
  _cp8b_tad_is_msg_carrier "$1"
}

# _s6_gh_api_admin "<cmd>": 0 (DENY) iff the command is a `gh api` call with a MUTATING method against
# an ADMIN-ONLY path. This is the REST plumbing UNDERNEATH the S6 arm's `gh pr merge --admin`: that
# porcelain flag is *implemented* as `PUT /repos/:o/:r/pulls/:n/merge`. GraphQL `mergePullRequest`
# honours branch protection; the REST endpoint with an admin token and `enforce_admins:false` does not.
# So denying only the flag left the same bypass one flag-spelling away — reproduced live 2026-08-25 at
# rc=0, and the #567 unstick (2026-08-19) was that very call (it rode a recorded GO bound to the
# approved SHA, so the JUDGMENT control held; the speed-bump simply did not exist for that shape —
# `D-240825-1` (3) records the correction). Same Tier-3 rule as S6 (`D-240813-5`), so it shares S6's
# `13:` message rather than minting a second one.
#
# FAIL-BY-DISQUALIFICATION on the raw unsplit string (guard-FP doctrine, 2026-08-12): a command is
# denied only when BOTH a mutating method AND a listed admin path are positively recognized; anything
# unrecognized falls through to ALLOW here and is judged by the other arms.
#   (b) mutating = an explicit -X/--method PUT|POST|PATCH|DELETE, OR a body flag with no explicit GET
#       (`gh api` defaults to POST once a body is given). ONE NORMALISATION, COMPUTED FIRST, READ BY
#       EVERY PROBE (`$_sgn`) — that ordering is load-bearing, not stylistic; see the note on it in
#       the body. Both the method flag and the GET suppressor
#       tolerate quotes and a FUSED value (`-XPUT`, `-X "PUT"`, `-X 'PUT'`, `-X P''UT`, `-'X' PUT`,
#       `-X\ PUT`, `--met''hod PUT`), and a short body flag
#       (-f/-F) counts only when it carries a FIELD ASSIGNMENT — `-fmerge_method=squash` and
#       `-f contexts[]=x` do; a `sort -f` or `grep -F` in a later pipe stage does NOT (round 3: that
#       over-match denied the owner's own A3 read-back commands).
#       ⚠️ ROUND-1 DEFECT, recorded because it is the whole lesson: the first version anchored the
#       method with `[[:space:]=]+`, so a single quote or a missing space walked straight past a deny
#       arm whose plain form worked. Fix the CLASS (normalize, then match), never the instance.
#   (c) admin path, after NORMALIZATION (below): the pulls/N/merge bypass · ANY branches/*/protection
#       sub-path · repo or org rulesets · git/refs (a ref PATCH with force=true is a force-push over
#       the API) · collaborators/* (a PUT mints an admin) · and the repo ROOT under DELETE or PATCH
#       (a default_branch swap moves protection off the branch everything merges to). The last three
#       are Tier-3 acts in `D-240813-5`'s own words: force-push, privilege grant, delete.
#
# NORMALIZATION, in order, because matching a raw argv string is how round 1 lost: quotes and
# BACKSLASHES → DELETED (a quote JOINS in the shell, it does not separate — round 2 spaced them and
# `me''rge` walked through) · `https?://<host>/` → space (ANY host, so a GHES `--hostname` call
# normalizes identically) · `?` → space (truncate the query string) · `//` → `/`.
# ONE NORMALISATION, COMPUTED FIRST, READ BY EVERY PROBE. The quote/backslash deletion is `$_sgn`
# and is computed before the `gh api` probe, before the method loop and before the body-flag test;
# the path view `$_sga` is derived FROM it. Round 3 computed the deletion late, so the method probes
# still read raw `$1` and the same joiner bypass simply moved from the path to the method
# (round 4). If you add a probe to this function, read `$_sgn` — never `$1`.
# Terminators are then `([[:space:]/]|$)` where a sub-path cannot change the verdict — EXCEPT the repo
# root, which stays exact-segment, because widening it with `/` would swallow every path under it.
#
# THE ONE CARVE-OUT: method POST *and* path `…/protection/required_status_checks/contexts`. That is
# `scripts/branch-protection-apply.sh --apply`'s own human-run call — ADDITIVE, it strengthens
# protection, and denying it would break the very script that closes A3. Note the SHAPE: the rule is
# deny-the-prefix with a method-scoped hole, NOT allow-a-sub-tree. Round 1 had it inverted — it
# enumerated four weakening sub-resources and let the rest through, so `-X DELETE
# …/protection/required_status_checks` (which drops every required context at once) was ALLOW.
# The ALLOW cell for the POST is load-bearing under this shape: delete the carve-out and it reds.
#
# ── HONEST CEILING. A SPEED BUMP ON ONE CLIENT, AND ONLY ON PLAINLY-WRITTEN COMMANDS.
# "Denied" here means "denied when written plainly". Disclosed, NOT closed:
#   · INDIRECTION — `$VAR`, `$(cat f)`, `xargs`, a `gh alias` that expands to the call: the bytes the
#     guard scans are not the bytes that run.
#   · QUOTED WRAPPERS — `sh -c '…'`, `bash -lc '…'`. PRE-EXISTING, NOT introduced here: it blinds the
#     incumbent `--admin` arm and the porcelain-token arms (measured: `sh -c 'gh pr merge 5 --admin'`
#     is ALLOW, on the base tree too). **S6R happens to survive it** — measured — because its first
#     probe matches the wrapped bytes as text and the path normalizer never needed the argv split.
#     That is LUCK, NOT DESIGN: do not generalise it to the other arms, and do not let it argue the
#     class is closed. A cell pins S6R's survival so it cannot regress silently; the class is boarded
#     as GUARD-QUOTED-WRAPPER-BLINDS-COMMAND-ARMS.
#   · PERCENT-ENCODED SEGMENTS — `repos/o/r/pulls/5/%6Derge` is ALLOW (measured); nothing decodes
#     `%XX` here. Boarded on GUARD-REST-ADMIN-CURL-SIBLING.
#   · ANSI-C AND OTHER SHELL-EVALUATED METHOD SPELLINGS — `$'PUT'`, `$"PUT"`, `${M:-PUT}`,
#     `-X{,}PUT` (brace expansion), `P$()UT`, backticks — are ALLOW (measured): the normalisation
#     deletes BYTES, it does not EVALUATE. Closed by the positional-extract row together with the
#     `$VAR` family (GUARD-S6R-POSITIONAL-PATH-EXTRACT), rather than special-cased one spelling at a
#     time — enumerating expansion syntaxes is the same losing move as enumerating paths.
#     Every quote/backslash SPLIT form is closed by contrast, including the pathological
#     `g''h a''pi -''X P''UT re''pos/o/r/pu''lls/5/me''rge`.
#   · SUBSTRING, NOT ARGV — every path test is a substring match over the normalized string. The
#     contexts carve-out is positional-by-subtraction rather than a presence test (round 3), but the
#     general class only retires with GUARD-S6R-POSITIONAL-PATH-EXTRACT.
#   · The body-flag narrowing has its own narrow residual: a downstream `grep -F name=x` (a field
#     ASSIGNMENT in a later pipe stage) still reads as a body flag. Strictly narrower than round 2,
#     and it costs a prompt on a read rather than opening a write.
#   · OTHER CLIENTS — `curl`, `wget`, `python -c "requests…"`, `node -e`, and the `gh` porcelain verbs
#     (`gh repo delete`, `gh ruleset delete`, `gh repo edit --default-branch`). Boarded as
#     GUARD-REST-ADMIN-CURL-SIBLING and GUARD-GH-VERB-ADMIN-SIBLINGS (design §7).
#   ⚠️ `--hostname` (GHES) is NOT in this list: it DENIES, because the host is normalized away and the
#     path is what matters. Round 1's comment claimed otherwise; the fixture cells are the truth.
# And one clause that must not be over-read: GraphQL `mergePullRequest` honouring branch protection is
# GITHUB-SIDE BEHAVIOUR, not a permission boundary this guard maintains — it is why the REST endpoint
# is the interesting one, not a reason to trust the GraphQL path.
# The DURABLE controls remain `D-240813-5`'s human keystroke, the settings allowlist (A2) and
# server-side branch protection with `enforce_admins:true` once a second human exists (A3/D2).
# T2 round 1 (GUARD-READ-LANE-2): the REST half inherited the porcelain half's joiner holes, and the
# seat measured both live — `gh api -X PUT repos/o/r/pulls/5/me$()rge` and a `gh \<nl>api …` line
# continuation both ALLOWED at 4b9f464f. Same doctrine, same shape as the porcelain arm: JOIN
# continuations first (grep is line-oriented), then run the WHOLE scan over TWO views — the joined
# string, and a substitution-stripped twin. Two views, because stripping in a single view would lose
# the deny on `gh api -X PUT `echo repos/o/r/pulls/5/merge`` , whose bytes live inside the
# substitution. This wrapper is add-only: it can only ever add a second chance to DENY.
# T2 round 2: the REST half gets the porcelain half's round-2 precision, because the arm family is
# ONE arm and the seat measured the same two holes here — `gh api -X PUT …/pulls/5/me\<nl>rge` (an
# INTRA-TOKEN continuation, which the space-join turned into `me rge`, matching nothing) and
# `…/me$(<nl>)rge` (a newline the line-oriented sed could not cross). Both ALLOWED at 35a2032f.
# Four views now, deny on any: space-joined, EMPTY-joined, and each one's fixpoint-stripped twin.
# Still add-only — every view is a superset match, so no existing deny is lost.
_s6_gh_api_admin() {
  _sgj=$(_cp8b_joinlines "$1")
  _sge=$(_cp8b_joinlines_empty "$1")
  for _sgv in "$_sgj" "$_sge" "$(_cp8b_strip_subst "$_sgj")" "$(_cp8b_strip_subst "$_sge")"; do
    if _s6_gh_api_admin_scan "$_sgv"; then unset _sgj _sge _sgv 2>/dev/null || :; return 0; fi
  done
  unset _sgj _sge _sgv 2>/dev/null || :
  return 1
}

_s6_gh_api_admin_scan() {
  # ── ONE NORMALISATION, COMPUTED FIRST, READ BY EVERY PROBE. ─────────────────────────────────────
  # ⚠️ THIS ORDERING IS THE FIX, AND ITS ABSENCE WAS A LIVE BYPASS TWICE RUNNING.
  # Quotes and backslashes are deleted because in the shell a quote is a JOINER, not a boundary:
  # adjacent fragments concatenate, so `me''rge` executes as `merge`. Round 3 established that and
  # applied it — to the PATH only, computing the cleaned string AFTER the method and body-flag probes
  # had already read raw `$1`. So the identical trick simply moved to the METHOD: `-X P''UT`,
  # `-X PU\T`, `--met''hod PUT`, and — the one that matters most — `-f 'merge_method=squash'`, which
  # is not an evasion at all but the ORDINARY way a human quotes a shell argument. All ALLOW at
  # 670e9205; `PUT /pulls/N/merge` takes an empty body, so `-X P''UT …/merge` was a complete admin
  # merge. ★ A normalisation that runs after some probes have read the raw string protects only the
  # probes that come after it. Every probe below reads `$_sgn`; nothing reads `$1` again.
  _sgn=$(printf '%s' "$1" | tr -d "'\"\\\\")

  # THE LEAD TOKEN IS CASE-FOLDED — `[Gg][Hh]`, never `pr`/`api`/a flag. T2 round 5, and it is a
  # ROUND-4 MISS, recorded because the miss is the lesson: round 4 folded the lead in the porcelain
  # SHAPE greps and in the order walk and shipped under the subject "GH lead case-folded", while THIS
  # gate — the entry to the arm that denies the REST MUTATIONS — kept comparing `gh` case-sensitively.
  # So `GH pr merge 5 --admin` denied and `GH api -X PUT repos/o/r/pulls/5/merge` (the same bypass one
  # spelling down, and the exact call that unstuck #567) ALLOWED, on a case-insensitive filesystem
  # where `GH` really resolves. Six spellings measured ALLOW at 07928fc1 AND at cec9bce4. A fold
  # applied arm-by-arm is not a fold; every gh-anchored DENY matcher in this file now folds its lead,
  # and each spelling has its own T2R5 cell so a future partial fold cannot pass as a whole one.
  # ⚠️ NOT FOLDED, DELIBERATELY: the message-carrier and heredoc-consumer arms that key on `gh pr` /
  # `gh issue` / `gh release`. Those are EXEMPTIONS — folding them would hand the exemption to a
  # capitalised lead, i.e. widen a hole rather than close one. The fold only ever runs deny-side.
  printf '%s' "$_sgn" | grep -Eq '[Gg][Hh][[:space:]]+api' || { unset _sgn; return 1; }

  # (b1) The explicit method, if any. Fixed probe order; `put` cannot match `-X POST` and `get`
  # cannot match `-X DELETE`, so the order only decides which wins when two methods are present.
  _sgm=''
  for _sgx in put post patch delete get; do
    if printf '%s' "$_sgn" | grep -Eiq "(-X|--method)[[:space:]=]*$_sgx"; then _sgm=$_sgx; break; fi
  done
  # (b2) A body flag, which must carry a FIELD ASSIGNMENT (`name=`) to count.
  # ⚠️ ROUND-2 DEFECT, and it hurt the READ side: matching a bare whitespace-anchored `-f`/`-F`
  # anywhere in the raw string meant a LATER PIPE STAGE supplied the "body" — `gh api …/protection |
  # grep -F required_status_checks` and `… | sort -f` both DENIED. Those are the owner's own A3
  # read-back commands out of RUNBOOK §5. A guard that blocks the command the runbook prescribes is
  # one people learn to route around, which costs more than the rule buys.
  # The bracket expression is POSIX-ordered on purpose: `]` FIRST, `-` LAST, `[` in the middle. A
  # backslash inside an ERE bracket expression is a LITERAL backslash, so `\[\]` would NOT have
  # escaped anything — it would have added `\` to the set and dropped the brackets.
  # `-f contexts[]=x` (the legitimate apply call) must keep matching; a selftest cell pins it.
  _sgb=0
  if printf '%s' "$_sgn" | grep -Eq '(^|[[:space:]])(-f|-F)[[:space:]]*[A-Za-z_][]A-Za-z0-9_.[-]*=' \
     || printf '%s' "$_sgn" | grep -Eq '(^|[[:space:]])(--field|--raw-field|--input)([[:space:]]|=)'; then
    _sgb=1
  fi

  case "$_sgm" in
    put|post|patch|delete) : ;;
    get)                   unset _sgn _sgm _sgb _sgx; return 1 ;;
    *)  [ "$_sgb" = 1 ] || { unset _sgn _sgm _sgb _sgx; return 1; } ;;
  esac
  # Implicit POST: no explicit method, but a body. Only this and an explicit POST can take the carve-out.
  _sgpost=0
  if [ "$_sgm" = post ] || { [ -z "$_sgm" ] && [ "$_sgb" = 1 ]; }; then _sgpost=1; fi

  # The PATH view, derived from the SAME `$_sgn` the probes above read — quotes and backslashes are
  # already gone (round 2 mapped them to SPACES instead, which is backwards: a space-normalizing
  # guard saw `me''rge` as two short tokens and matched neither — six live ALLOWs at 5ada56d9).
  # Deleting loses nothing, because the whitespace around a quoted argument already bounds it.
  # What is added here is URL/query/slash flattening, which only the path tests need.
  _sga=$(printf '%s' "$_sgn" \
    | sed -E -e 's#[Hh][Tt][Tt][Pp][Ss]?://[^/[:space:]]*/# #g' -e 's/\?/ /g' -e 's#//+#/#g')

  # The contexts path, REMOVED — see the carve-out below. Computed once, here, so the carve-out can
  # be a question about what REMAINS rather than about what is merely present somewhere.
  _sgc=$(printf '%s' "$_sga" \
    | sed -E 's#(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/branches/[^/[:space:]]+/protection/required_status_checks/contexts([[:space:]/]|$)# #g')

  _sgr=1
  # 1 — the merge bypass itself (the REST implementation of `gh pr merge --admin`).
  if printf '%s' "$_sga" | grep -Eq '(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/pulls/[0-9]+/merge([[:space:]/]|$)'; then
    _sgr=0
  # 2 — branch protection: DENY the whole sub-tree, with the single POST-to-contexts carve-out.
  # ⚠️ THE CARVE-OUT IS POSITIONAL-BY-SUBTRACTION, not a presence test. Round 2 asked "does the
  # contexts path appear anywhere?", so a DECOY IN A FILENAME took the exemption:
  #   gh api -X POST repos/o/r/branches/main/protection --input /repos/…/protection/…/contexts
  # opened the entire protection subtree under POST (measured ALLOW at 5ada56d9 — the same
  # enumerate-the-offence class as round 1, one level up). Now: strip every contexts occurrence and
  # ask whether a protection path SURVIVES. If one does, that is a real target and it denies.
  # The honest residual is that this is still substring matching, not argv parsing —
  # GUARD-S6R-POSITIONAL-PATH-EXTRACT is boarded to retire the class properly.
  elif printf '%s' "$_sga" | grep -Eq '(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/branches/[^/[:space:]]+/protection([[:space:]/]|$)'; then
    if [ "$_sgpost" = 1 ] \
       && ! printf '%s' "$_sgc" | grep -Eq '(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/branches/[^/[:space:]]+/protection([[:space:]/]|$)'; then
      _sgr=1
    else
      _sgr=0
    fi
  # 3 — repo or org rulesets (same class as protection).
  elif printf '%s' "$_sga" | grep -Eq '(^|[[:space:]]|/)(repos/[^/[:space:]]+/[^/[:space:]]+|orgs/[^/[:space:]]+)/rulesets([[:space:]/]|$)'; then
    _sgr=0
  # 4 — git/refs: `-f force=true` on a ref IS a force-push (Tier 3). PUT included — the method sets
  # below are deliberately WIDER than GitHub's current routing table, because "that verb 405s today"
  # is a fact about GitHub's implementation, not a property this guard should depend on. No
  # legitimate agent traffic writes to any of these paths, so the width costs nothing.
  elif printf '%s' "$_sga" | grep -Eq '(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/git/refs([[:space:]/]|$)'; then
    case "$_sgm" in patch|delete|post|put) _sgr=0 ;; '') [ "$_sgb" = 1 ] && _sgr=0 ;; esac
  # 5 — collaborators: minting or revoking access is a privilege grant (Tier 3). Implicit POST too.
  elif printf '%s' "$_sga" | grep -Eq '(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/collaborators/[^[:space:]]'; then
    case "$_sgm" in put|delete|post) _sgr=0 ;; '') [ "$_sgb" = 1 ] && _sgr=0 ;; esac
  # 6 — the repo ROOT under DELETE (repo deletion) or PATCH (a default_branch swap moves protection
  # off the branch everything merges to). EXACT SEGMENT plus an optional TRAILING slash: `/?` before
  # the terminator accepts `repos/o/r/` without widening to `repos/o/r/anything`.
  elif printf '%s' "$_sga" | grep -Eq '(^|[[:space:]]|/)repos/[^/[:space:]]+/[^/[:space:]]+/?([[:space:]]|$)'; then
    case "$_sgm" in delete|patch) _sgr=0 ;; esac
  fi

  unset _sgn _sga _sgc _sgm _sgb _sgx _sgpost
  return "$_sgr"
}

# ================================================================================================
# GUARD-DENY-LOG (D-240828-4, V1-REPAIR-PROGRAM PR 4a) — THE CLOSURE INSTRUMENT.
#
# WHY IT EXISTS. Every false-positive count in this program ("≥ 9", "3-11 per session") was a HUMAN
# TALLY FROM CHAT, because the guard writes no deny record: `_cp8b_deny_reason` prints and the caller
# exits. That is the actual defect behind "no read lane has a closure criterion" — there is no
# instrument. This function is the instrument: one NDJSON line per deny, so a harvest reads a FILE.
#
# WHAT IT IS NOT. It is an OBSERVATION, never a CONTROL (THREAT-MODEL T5). The log is agent-writable,
# agent-deletable and unauthenticated; it can be forged or truncated by anything that can run in the
# repo. Nothing may ever gate on it. Its ONLY job is to make "did the read lanes get better" a
# measured number instead of an anecdote.
#
# THE FAIL-SAFE, and it is the load-bearing property: LOGGING CAN NEVER CHANGE A VERDICT. Every
# operation here is failure-swallowed and the function ALWAYS returns 0, so a full disk, a read-only
# `.kit-run`, a missing `date` or an unresolvable repo root can never turn a DENY into an ALLOW (or
# an ALLOW into a deny). Callers invoke it AFTER the decision is made, never as part of it.
#
# WHAT IS NEVER WRITTEN: the full command. A command line can carry a secret (a token in a `curl -H`,
# a password in a `psql` URL), and a local plaintext file of every command an agent tried to run is a
# credential store nobody asked for. Only the guard's own OFFENDING SEGMENT is recorded, already
# truncated to 160 bytes by the reason builder and re-truncated here, with control bytes stripped.
#
# HOME: `<repo-root>/.kit-run/guard-denials.ndjson` — the runaway killswitch's run directory
# (docs/operations/runaway-killswitch.md), already in .gitignore and never exported. Owner design GO
# 2026-08-29 chose this home; it is also the answer GUARD-BYPASS-UNLOGGED was waiting for ("where the
# trace lives, and who may read it": local, gitignored, owner-readable, never pushed).
#
# DISABLE: `KIT_GUARD_LOG=0`. Documented in docs/operations/runtime-guards.md.
#
# POSIX sh, no jq: the JSON is hand-built by one printf over eight fixed fields, so `--denials` can
# read it with awk and the kit takes on no new runtime dependency.
_GUARD_DENY_LOG_REL='.kit-run/guard-denials.ndjson'
# JSON-safe a value for a double-quoted string: strip control bytes, then escape backslash and
# double-quote. Backslash FIRST — the other order would double-escape the backslashes the quote rule
# introduces.
# ⚠️ SECURITY M1 (review round 1): the first cut spared \011 \012 \015. A TAB or CR is not legal
# literal JSON inside a string, and a raw NEWLINE in a segment SPLIT ONE RECORD INTO TWO — a log
# forgery primitive (an attacker-influenced segment could synthesise a whole extra NDJSON line).
# The whole C0 range plus DEL now goes, unconditionally.
_guard_log_json() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g'
}
# _guard_log_redact "<segment>" — mask common secret shapes BEFORE the segment is written.
# ⚠️ SECURITY H1 (review round 1), and the honest framing: for a ONE-SEGMENT command the offending
# segment IS the command, so "we never log the command" was too strong a claim. Measured leaks:
# `TOKEN=ghp_… sed -i …`, `curl -H 'Authorization: Bearer …'`, `psql postgres://user:pw@host`.
# This is BEST-EFFORT MASKING, NOT A GUARANTEE — an unrecognised secret shape still lands in the
# file. The prose in THREAT-MODEL.md, RUNBOOK.md §4 and docs/operations/runtime-guards.md says so in
# those words; do not re-strengthen it here or there.
# ORDER MATTERS: `Bearer`/`Basic` run BEFORE `Authorization:`, so the scheme rule has already eaten
# the credential and the Authorization rule only tidies the remainder.
# _guard_log_jsonkey <key-bracket-pattern> <label> — build ONE sed rule masking a JSON
# `"key": "value"` pair, tolerating BACKSLASH-ESCAPED quotes (a JSON body inside a shell command
# arrives as `\"token\": \"…\"`, which is how it actually shows up in a segment).
# ⚠️ ONE RULE PER KEY, deliberately: BSD/macOS `sed` has NO `\|` alternation in BRE, so the combined
# four-key rule this replaces MATCHED NOTHING AT ALL on macOS — it read as working and redacted
# zero JSON secrets. Measured. Four rules cost nothing and work on both seds.
_guard_log_jsonkey() {
  printf 's/\\\\\\{0,1\\}"%s\\\\\\{0,1\\}"[[:space:]]*:[[:space:]]*\\\\\\{0,1\\}"[^"\\\\]*\\\\\\{0,1\\}"/"%s": "<redacted>"/g' "$1" "$2"
}
_guard_log_redact() {
  # ⚠️ MED-3 (review round 2) widened this list. The FIRST rule used to mask only the FIRST
  # assignment, so `A=x TOKEN=ghp_… sed -i …` leaked: the loop below re-runs the leading-assignment
  # rule until it stops changing anything, which walks the whole leading assignment RUN. Bounded at
  # 8 iterations — a leading run longer than that is not a shape worth chasing, and an unbounded
  # loop inside the deny path is exactly the kind of thing that turns a logger into a hang.
  # ONE idempotent sed applied to a FIXPOINT: it skips any already-masked assignments at the head
  # and masks the next unmasked one, so iterating it walks the whole leading run. Locals are reset
  # every call — an accumulator that survived between calls would bleed one command's prefix into
  # the next one's log line.
  _glr_s=$1
  _glr_i=0
  while [ "$_glr_i" -lt 8 ]; do
    _glr_n=$(printf '%s' "$_glr_s" | LC_ALL=C sed 's/^\(\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*=<redacted>\)*\)\([[:space:]]*\)\([A-Za-z_][A-Za-z0-9_]*\)=[^[:space:]]*/\1\3\4=<redacted>/')
    [ "$_glr_n" != "$_glr_s" ] || break
    _glr_s=$_glr_n
    _glr_i=$((_glr_i + 1))
  done
  printf '%s' "$_glr_s" | LC_ALL=C sed \
    -e 's/[Bb]earer[[:space:]][^[:space:]]*/Bearer <redacted>/g' \
    -e 's/[Bb]asic[[:space:]][^[:space:]]*/Basic <redacted>/g' \
    -e 's/[Aa]uthorization:[[:space:]]*[^[:space:]]*/Authorization: <redacted>/g' \
    -e 's/[Xx]-[Aa][Pp][Ii]-[Kk][Ee][Yy]:[[:space:]]*[^[:space:]]*/x-api-key: <redacted>/g' \
    -e 's/[Aa][Pp][Ii]-[Kk][Ee][Yy]:[[:space:]]*[^[:space:]]*/api-key: <redacted>/g' \
    -e 's/[Tt][Oo][Kk][Ee][Nn]=[^[:space:]\&]*/token=<redacted>/g' \
    -e 's/[Aa][Pp][Ii][-_]*[Kk][Ee][Yy]=[^[:space:]\&]*/api_key=<redacted>/g' \
    -e 's/[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]=[^[:space:]\&]*/password=<redacted>/g' \
    -e 's/[Ss][Ee][Cc][Rr][Ee][Tt]=[^[:space:]\&]*/secret=<redacted>/g' \
    -e 's/-u[[:space:]][^[:space:]]*:[^[:space:]]*/-u <redacted>/g' \
    -e 's/-u[^[:space:]]*:[^[:space:]]*/-u<redacted>/g' \
    -e 's/-p[[:space:]][^-][^[:space:]]*/-p <redacted>/g' \
    -e 's/-p[^-[:space:]][^[:space:]]*/-p<redacted>/g' \
    -e "$(_guard_log_jsonkey '[Tt][Oo][Kk][Ee][Nn]' token)" \
    -e "$(_guard_log_jsonkey '[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]' password)" \
    -e "$(_guard_log_jsonkey '[Ss][Ee][Cc][Rr][Ee][Tt]' secret)" \
    -e "$(_guard_log_jsonkey '[Aa][Pp][Ii][-_]*[Kk][Ee][Yy]' api_key)" \
    -e 's#://[^/:@[:space:]]*:[^@[:space:]]*@#://<redacted>@#g'
}
# guard_log_deny <surface> <reason> [tool] — append one NDJSON line. ALWAYS returns 0.
#   surface = pretooluse | kit-guard   tool = Bash/Write/... or `-`
guard_log_deny() {
  case "${KIT_GUARD_LOG:-1}" in 0|no|off|false) return 0 ;; esac
  _gld_surface=${1:-'-'}; _gld_reason=${2:-}; _gld_tool=${3:-'-'}
  [ -n "$_gld_tool" ] || _gld_tool='-'
  # Repo root: the hook's authoritative PROTECTED_ROOT when the caller has one (guard.sh resolves it
  # from its own path and it is unforgeable), else the cwd's toplevel, else give up silently.
  _gld_root=${PROTECTED_ROOT:-}
  if [ -z "$_gld_root" ] || [ ! -d "$_gld_root" ]; then
    # NO `git` SUBPROCESS HERE (shim-coverage.sh measured it): this runs on the DENY path, and under the
    # install-shims harness `git` IS the shim under test — a `git rev-parse` from inside the logger
    # executed the real binary on a denied command. Walk up to the nearest `.git` (dir or worktree
    # file) in pure shell instead; an unresolvable root skips logging, never the verdict.
    _gld_root=$(pwd -P 2>/dev/null || printf '')
    while [ -n "$_gld_root" ] && [ "$_gld_root" != / ] && [ ! -e "$_gld_root/.git" ]; do
      _gld_root=${_gld_root%/*}; [ -n "$_gld_root" ] || _gld_root=/
    done
    [ -e "$_gld_root/.git" ] || _gld_root=''
  fi
  [ -n "$_gld_root" ] && [ -d "$_gld_root" ] || return 0
  # arm = the reason's leading numeric tag (`13: ...`). All-digits or it is not a tag.
  _gld_arm=${_gld_reason%%:*}
  case "$_gld_arm" in ''|*[!0-9]*) _gld_arm='-' ;; esac
  # trigger = the `trigger=<token>` the target arm carries; `-` when the reason has none.
  _gld_trigger=$(printf '%s' "$_gld_reason" | sed -n 's/.*trigger=\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*/\1/p' 2>/dev/null || printf '')
  [ -n "$_gld_trigger" ] || _gld_trigger='-'
  # segment = the text inside the reason's `segment: [...]`.
  # ⚠️ L1 (review round 1): this anchored on the FIRST `[` in the reason, which is WRONG — the sed
  # tip contains a literal `[,<m>|,$]`, so a tipped reason logged a fragment of the TIP as the
  # segment. Anchor on the `segment: [` label both reason builders emit ("offending segment: [" and
  # "Offending segment: [" — the suffix is common to both, so one pattern serves).
  _gld_seg=''
  _gld_rs=0
  case "$_gld_reason" in
    *'segment: ['*)
      _gld_seg=${_gld_reason#*'segment: ['}; _gld_seg=${_gld_seg%%]*}
      # read_shaped, DERIVED FROM THE REASON — reviewer H1/H2, round 1. The first cut RE-DECIDED the
      # predicate by calling `_cp8b_seg_read_shaped` on the already-`]`-truncated segment and without
      # the raw command, so it disagreed with the guard's own judgment in both directions (measured:
      # `cat 'x]y' > conformance/verify.sh` — a WRITE — logged 1, and a loop head the tier HAD judged
      # read logged 0). The reason already carries the answer: `_cp8b_selfedit_hint` appends the
      # `Set KIT_GUARD_SELFEDIT=1` sentence IFF the segment was NOT read-shaped. So read it off,
      # never recompute it — the log and the deny text now cannot disagree BY CONSTRUCTION.
      case "$_gld_reason" in
        *'Set KIT_GUARD_SELFEDIT=1'*) _gld_rs=0 ;;
        *) _gld_rs=1 ;;
      esac
      ;;
  esac
  # ⚠️ THE `else` IS DELIBERATE AND IS NOT WHAT THE REVIEW ASKED FOR VERBATIM. Applying the
  # sentence-absent rule to EVERY reason would mark the destructive matrix read-shaped: reasons like
  # `13: rm of a glob … can be irreversible - human-gated.` carry no SELFEDIT sentence because they
  # come from arms that have no offending segment at all, and they are unambiguously WRITES. The bit
  # is therefore derived only where a segment exists (i.e. where the two-tier read judgment actually
  # ran); a segment-less deny is 0. Flagged to the reviewer rather than silently widened.
  # Redact BEFORE truncating: truncating first could cut a secret in half and leave the prefix.
  _gld_seg=$(_guard_log_redact "$_gld_seg" 2>/dev/null || printf '')
  # ⚠️ M2 (review round 1): `cut -c1-160` counts CHARACTERS, and a multibyte segment produced a
  # 448-byte line against a field documented as "≤160 bytes". LC_ALL=C makes the count bytes, which
  # is what the claim says. Only the LOG site is byte-clamped; the reason string keeps its own cut.
  _gld_seg=$(printf '%s' "$_gld_seg" | LC_ALL=C cut -c1-160 2>/dev/null || printf '')
  # ⚠️ MED-1 (review round 2): the byte clamp above can cut THROUGH a multibyte character, and the
  # resulting line is not valid UTF-8 — at which point macOS awk ABORTS (exit 2, empty stdout) the
  # moment `--denials` reads the file. One truncated `é` therefore voided the ENTIRE harvest, while
  # the reader's own comment promised "counted as malformed, never silently dropped". So the clamp
  # is walked back to a character boundary: strip a trailing sequence ONLY IF it is truncated (a
  # 2-byte lead alone; a 3-byte lead with 0-1 continuations; a 4-byte lead with 0-2). A COMPLETE
  # trailing character is left alone, and pure ASCII is untouched. Result is ≤160 bytes and always
  # valid UTF-8, so the field's documented claim and the reader's robustness both hold.
  _gld_seg=$(printf '%s' "$_gld_seg" | LC_ALL=C sed \
    -e "s/[$(printf '\300')-$(printf '\337')]\$//" \
    -e "s/[$(printf '\340')-$(printf '\357')][$(printf '\200')-$(printf '\277')]\{0,1\}\$//" \
    -e "s/[$(printf '\360')-$(printf '\367')][$(printf '\200')-$(printf '\277')]\{0,2\}\$//" \
    2>/dev/null || printf '%s' "$_gld_seg")
  _gld_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '')
  # session: an explicit KIT_SESSION_ID when the runtime sets one, else the PARENT pid (the agent
  # process / invoking shell), which groups a run's denials without identifying anything. `$$` is the
  # last resort for a shell that does not export PPID.
  _gld_sess=${KIT_SESSION_ID:-${PPID:-$$}}
  _gld_dir="$_gld_root/.kit-run"
  _gld_log="$_gld_root/$_GUARD_DENY_LOG_REL"
  mkdir -p "$_gld_dir" 2>/dev/null || return 0
  # ⚠️⚠️ SECURITY C1 + C2 (review round 1) — THE PLANTED-NODE REFUSAL. Two live findings, both
  # reproduced: (C1) `mkfifo .kit-run/guard-denials.ndjson` is ALLOWED by the guard, and the next
  # deny then BLOCKED FOREVER inside the `>>` open — a hang of the PreToolUse hook, i.e. a denial-of-
  # service on the agent's own tool loop, reachable by one allowed command. (C2) a SYMLINK at the log
  # path turned the logger into an APPEND PRIMITIVE onto any file the process can write —
  # attacker-influenced bytes appended to, say, a governance record.
  # So: write only when `.kit-run` is a real directory (not a symlink) and the log path is either
  # ABSENT or a REGULAR NON-SYMLINK file. Anything else — FIFO, socket, device, symlink (dangling
  # included: `-L` is tested before `-e`, which follows), or a symlinked directory — declines.
  # ⚠️ HONEST CEILING: this is TOCTOU-imperfect. It is aimed at a PLANTED NODE sitting at the path,
  # not at an attacker racing the check between the test and the open. Closing the race needs an
  # O_NOFOLLOW open, which POSIX sh does not have. Stated, not hidden.
  if [ -L "$_gld_dir" ] || [ ! -d "$_gld_dir" ]; then return 0; fi
  if [ -L "$_gld_log" ]; then return 0; fi
  if [ -e "$_gld_log" ] && [ ! -f "$_gld_log" ]; then return 0; fi
  # ⚠️ MED-2 (review round 2) — A HARDLINK DEFEATS BOTH TESTS ABOVE. `ln <victim> .kit-run/
  # guard-denials.ndjson` is ALLOWED for a non-control-plane victim, and the result is a REGULAR,
  # NON-SYMLINK file that passes `-f` and fails `-L` — so the append landed in the victim (measured).
  # Same primitive as C2, one syscall over. A hardlinked file has link count > 1; a freshly created
  # log has exactly 1. GNU `stat -c %h` first, then macOS `stat -f %l` (see below). ⚠️ ON FAILURE WE DEFAULT TO
  # 1, i.e. we WRITE: logging is best-effort and must never become the reason a platform without
  # `stat` silently loses its whole harvest. Refusing is the safe direction only when we KNOW.
  # GNU form FIRST, then BSD — the order this file's own _hl_link_count uses (:541): `stat -c` ERRORS on
  # BSD so the fallback is reached, but `stat -f %l` SUCCEEDS on GNU (there `-f` is FILESYSTEM stat and
  # %l is the max filename length), so the reversed order silently refused every log write on Linux
  # (measured on the first CI run of #597: every log cell read an empty field).
  if [ "$(stat -c %h "$_gld_log" 2>/dev/null || stat -f %l "$_gld_log" 2>/dev/null || echo 1)" = 1 ]; then :; else return 0; fi
  # ⚠️ reviewer M1 (round 1): `2>/dev/null` on a simple command does NOT suppress the shell's own
  # "cannot create" diagnostic for a failed `>>` REDIRECT — that is emitted before the command runs.
  # An unwritable .kit-run therefore leaked a shell error onto the hook's stderr. The subshell makes
  # the redirect failure interior to a command whose stderr IS redirected.
  # HIGH-2 (review round 2): `umask 077` so a FIRST-CREATE lands 0600, not the 0644 the process
  # umask gave it. The file can hold redacted-but-not-guaranteed-clean command segments, so it should
  # not be world-readable on a shared host. Scoped to this subshell — it never touches the caller's
  # umask. It applies to CREATION only: an existing log keeps whatever mode it already has.
  ( umask 077
    printf '{"ts":"%s","surface":"%s","tool":"%s","arm":"%s","trigger":"%s","segment":"%s","read_shaped":%s,"session":"%s"}\n' \
      "$(_guard_log_json "$_gld_ts")" "$(_guard_log_json "$_gld_surface")" "$(_guard_log_json "$_gld_tool")" \
      "$(_guard_log_json "$_gld_arm")" "$(_guard_log_json "$_gld_trigger")" "$(_guard_log_json "$_gld_seg")" \
      "$_gld_rs" "$(_guard_log_json "$_gld_sess")" \
      >> "$_gld_log" ) 2>/dev/null || :
  return 0
}

# guard_check_command "<cmd>": print reason + return 1 if denied, else return 0.
guard_check_command() {
  cmd=$1
  # --- control-plane shell mutation (moved from guard.sh:81-93, + new files) ---
  # GUARD-HOOKSPATH-CASE-BYPASS: unconditional case-fold (`-Eq` -> `-Eiq`), no fork. Git config
  # KEYS are case-insensitive by spec on every platform, so this can only ever ADD a deny — no
  # legitimate command sets a DIFFERENT config key that differs from core.hooksPath only by case.
  # GUARD-READONLY-FP-RELIEF Arm F: the flat matcher is UNCHANGED (same regex, same `-Eiq` fold) and
  # is now the CANDIDATE selector, evaluated per SEGMENT; the read/write decision is the default-deny
  # recognizer above. Segmenting also joins backslash-continuations, so `git config \<nl> core.hooksPath
  # /tmp/evil` — measured ALLOW before this slice, a line-oriented-grep hole — now denies.
  if ! selfedit_allowed; then
    _walk=$(_cp8b_segments "$cmd")
    while _cp8b_next_seg; do
      printf '%s' "$_seg" | grep -Eiq 'git[[:space:]]+config[[:space:]]+([^;&|]*[[:space:]])?core\.hooksPath' || continue
      _cp8b_gitcfg_msg_data "$_seg" && continue
      _cp8b_gitcfg_is_read "$_seg" && continue
      printf '%s' '13: git config core.hooksPath would disable the agent guard - human-gated. Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
    done
  fi
  # --- B2 Δ4(i)′: RAW `git notes` WRITES to the promotion GO ledger (refs/notes/promotions) -----
  # WHAT THIS IS. A DRIFT CONTROL, per owner ruling D3′ (2026-07-28): "BUILD the prevention as a
  # drift control, with the FULL measured bypass set stated in the ceiling … the threat is a model
  # that IGNORES the kit, not one that ATTACKS it … Denying the default route changes default
  # behaviour, which is the goal." The default route is what the D-240805-3 incident actually took:
  # a subagent minted an owner-attributed GO record with a bare `git notes add`. That route is now
  # denied. NOTHING MORE IS CLAIMED.
  #
  # WHAT IS DENIED: the raw `git notes` WRITE verbs (add · append · copy · edit · remove · prune ·
  # merge — copy included, it overwrites a target's note) when the command text targets the
  # promotions ref in any spelling (--ref=promotions · --ref promotions · quoted · the full
  # refs/notes/promotions name).
  # WHAT IS NOT DENIED, deliberately: the ceremonial front door (scripts/promotion-verify.sh
  # record — it DERIVES the assurance label instead of accepting one), every read (show/list),
  # notes on any OTHER ref (fixtures, refs/notes/commits), and the ledger's own publish push
  # (`git push origin refs/notes/promotions`, the front door's share step).
  #
  # ⚠️ THE COMPLETE MEASURED BYPASS SET — every one of these needs NO override and is NOT caught
  # (measured independently by both review seats, 2026-08-07; the earlier claim that "any direct
  # forge of the notes ref via shell is denied" was FALSE when it was ruled on, and is retracted):
  #   1. git PLUMBING: `git hash-object` -> `git mktree` -> `git commit-tree` -> `git update-ref
  #      refs/notes/promotions` mints a valid owner-attributed record with zero denied commands.
  #   2. DESTRUCTION: `git update-ref -d refs/notes/promotions` and
  #      `git push origin :refs/notes/promotions` delete the ledger outright.
  #   3. ALIAS INDIRECTION: `git config alias.x "notes --ref=promotions add ..."` then `git x`.
  #   4. FETCH REFSPEC: `git fetch <remote> '+<src>:refs/notes/promotions'` writes the ref.
  #   5. ENV SPELLINGS: `GIT_NOTES_REF=refs/notes/promotions git notes add …` (the bare-ref
  #      alternative below catches the common form; an indirect spelling does not appear in $cmd).
  #   6. INTERPRETER WRAPPERS: python/node/ruby -c, or any script file, invoking the same git calls.
  #   7. PUSH REFSPEC ONTO THE LEDGER: `git push origin refs/notes/<src>:refs/notes/promotions`
  #      overwrites the ledger from any local ref — measured ALLOW (round 2, sec L-new-1). Entry 2
  #      covers only the DELETE spelling (`:refs/notes/promotions`) and entry 4 only `git fetch`,
  #      so the WRITE-by-push route was missing from a set that called itself COMPLETE. The FORCED
  #      spelling (`+refs/notes/<src>:refs/notes/promotions`) is denied by the unrelated
  #      force/mirror-push rule, not by this arm — that is not coverage, and the unforced form is
  #      enough to overwrite a ref the remote fast-forwards or accepts outright.
  #   8. SYMBOLIC-REF: `git symbolic-ref refs/notes/promotions refs/notes/<other>` repoints the
  #      ledger NAME at another ref — measured ALLOW. It was named in the prose below, which is not
  #      the SET, so it is numbered here.
  #   9. THE SENTINEL ITSELF, under `install-shims` only — see THE SENTINEL below for the
  #      runtime-scoped measurement.
  # NOT in this set, because it is now COVERED (GUARD-HOOKSPATH-CASE-BYPASS): a case-variant ref
  # spelling — `git notes --ref=PROMOTIONS add`, `refs/notes/PROMOTIONS` — is denied the same as the
  # lowercase form. On macOS loose refs are ordinary files, so the uppercase spelling would otherwise
  # write the exact same `.git/refs/notes/promotions` governance ledger the lowercase form protects;
  # the ref-match leg above folds case for that reason. This does not touch entries 1-9: those are a
  # DIFFERENT class (plumbing/destruction/alias/refspec/interpreter/sentinel), still disclosed as-is.
  # These are NOT matched ON PURPOSE. Extending the matcher to update-ref/symbolic-ref/fetch and
  # push refspecs is the ARMS RACE vetoed by the 2026-07-28 design §4 ("no text/graph predicate over
  # author-controlled input") and permanently dropped by [S1]; it would fail the friction test
  # (it binds nothing the moment the model stops cooperating) while growing false denials.
  #
  # THE HONEST CONTROL IS NOT THIS ARM. It is Δ4(ii)'s VISIBILITY: the matched GO record is
  # rendered at the CI judgment surface before the owner's click (D-240805-4), which binds whether
  # or not the model cooperates. Plus the subagent-brief ledger-write prohibition (process).
  # A note BINDS, it does not AUTHENTICATE (scripts/promotion-verify.sh:38-44) — an agent running
  # under the owner's git identity can mint a front-door record and no local mechanism can tell.
  # PREVENTION IS NOT CLAIMED.
  #
  # THE SENTINEL, and why it is honest to ship a forgeable one [B2 sec H1]. Under `kit-guard
  # install-shims` EVERY git invocation is routed through this arm, including promotion-verify.sh's
  # OWN single note write — so the arm blocked the very door its deny message points at, and the
  # ledger became unwritable by any route (measured, not theorised). promotion-verify.sh exports
  # KIT_PROMOTION_FRONT_DOOR=1 around that one write and this arm honours it. IT IS
  # AGENT-FORGEABLE — BUT IN ONE RUNTIME ONLY, and the earlier flat claim ("an agent can prefix the
  # same variable to a raw command") over-stated it. MEASURED BOTH WAYS (round 2, sec L-new-1):
  #   * under `kit-guard install-shims` the shim rebuilds the command from ARGV (`c=$self; for a in
  #     "$@"`), so the `KIT_PROMOTION_FRONT_DOOR=1` prefix never appears in the text this arm reads —
  #     the shell EXPORTS it into the shim's, and therefore this arm's, own environment => ALLOW.
  #   * under the Claude hook / `kit-guard cmd` runtime the prefix arrives INSIDE the command TEXT
  #     and this arm's environment does not carry it => DENY (the raw write is still refused).
  # So the forgeability is entry 9 in the set above, SCOPED to install-shims. Erring safe was right;
  # stating it unscoped was not. Either way it is consistent with the posture, not a hole in a wall —
  # the wall is Δ4(ii).
  # Over-deny residual, accepted: a `git notes` write to a FIXTURE ref whose -m message merely
  # MENTIONS refs/notes/promotions is denied, and so are the conformance fixtures that write
  # `--ref=promotions` inside throwaway repos when they are run under shims (they are not, in CI).
  # No KIT_GUARD_SELFEDIT hint on THIS rule (L2): the one rule whose purpose is to stop
  # record-minting must not close by naming its own off-switch.
  # GUARD-HOOKSPATH-CASE-BYPASS (Fix 1, dual-review round): the REF-NAME leg folds too — on macOS
  # loose refs are ordinary FILES, so `git notes --ref=PROMOTIONS add` writes the same
  # `.git/refs/notes/promotions` file as the lowercase form; this is the same case-variance class as
  # every other fold in this slice (config keys, secret names), not the ref-name family's OTHER
  # disclosed bypasses (plumbing/update-ref/refspecs/alias — those stay exactly as disclosed below).
  # `-Eq` -> `-Eiq` on THIS leg only: the verb leg (next line up) and the write-verb leg (below) stay
  # byte-literal, deliberately — folding them would not narrow the over-deny risk, only widen it for
  # no gain, since "notes"/"add" etc are already case-invariant tokens in practice for this arm's
  # own fixtures. Monotone: a strict superset of the match, so no DENY can become an ALLOW.
  if ! selfedit_allowed \
     && [ "${KIT_PROMOTION_FRONT_DOOR:-}" != "1" ] \
     && printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+([^;&|]*[[:space:]])?notes[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq -- "--ref[= ][\"']?(refs/notes/)?promotions[\"']?([[:space:]]|\$)|refs/notes/promotions" \
     && printf '%s' "$cmd" | grep -Eq 'notes[[:space:]]([^;&|]*[[:space:]])?(add|append|copy|edit|remove|prune|merge)([[:space:]]|$)'; then
    printf '%s' '13: raw `git notes` WRITE verbs (add/append/copy/edit/remove/prune/merge) on refs/notes/promotions are denied - this is the default route a drifting agent takes to mint a GO record (governance-ledger integrity, D-240805-3). Use the front door: scripts/promotion-verify.sh record, which derives the assurance label; publish with `git push origin refs/notes/promotions`. NOT covered, and not claimed to be: git plumbing (hash-object/mktree/commit-tree/update-ref), ledger DESTRUCTION (`update-ref -d`, `push origin :refs/notes/promotions`), alias indirection, fetch OR PUSH refspecs whose DESTINATION is the ref, `symbolic-ref` repointing the ref, GIT_NOTES_REF spellings, interpreter wrappers - see the ceiling at this rule. The control that binds is the record rendered at the CI judgment surface, not this deny.'; return 1
  fi
  # CP-8b: the CO-OCCURRENCE block that used to live here matched a mutation verb and a control-plane
  # path ANYWHERE in the flat string, and never asked whether the verb's TARGET was that path — which
  # is both why `cp conformance/x /tmp/b` (copying OUT) was denied and why `git archive -o conformance/x`
  # (a real write) was allowed. It is replaced by a SEGMENT WALK that binds each segment's leading verb
  # to that segment's OWN arguments, plus subcommand-bound git write-primitives (which also absorb
  # CP-8a's `git … --output` deny, narrowing its scope from "any git" to the subcommands that honor it).
  # Monotone: every relaxation inside the predicate is an allow-back gated on POSITIVE recognition, so a
  # bug there over-denies and cannot over-allow.
  if ! selfedit_allowed; then
    if _cp8b_reason=$(_cp8b_control_plane_denied "$cmd"); then
      # Belt-and-suspenders: every deny arm inside the predicate already prints a reason via
      # _cp8b_deny_reason / _cp8b_git_write_denied, but a blank reason must NEVER reach the adapter (it
      # would surface as an empty permissionDecisionReason - a blocked agent with no guidance). Default it.
      [ -n "$_cp8b_reason" ] || _cp8b_reason='13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'
      printf '%s' "$_cp8b_reason"; return 1
    fi
    # GUARD-BASENAME-AFTER-CD-BYPASS + GUARD-INTERPRETER-FAMILY-BYPASS: the resolved-target arm.
    # UNION with the old arm above (deny = old-verb-arm ∨ new-target-arm). The old arm is retained
    # verbatim, so this can only ever ADD a denial (monotone; panel #19 add-only shape).
    if _cp8b_reason=$(_cp8b_target_arm_denied "$cmd"); then
      [ -n "$_cp8b_reason" ] || _cp8b_reason='13: writes against a resolved control-plane target via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'
      printf '%s' "$_cp8b_reason"; return 1
    fi
  fi
  # H3a: secret-in-context (shell) — a content-read verb (cat/grep/strings/diff/awk/...; also
  # source/. which load a .env into the environment) targeting secret material pulls it into the
  # agent's context: the read half of exfil. Human-gate it, symmetric with the secret-WRITE deny in
  # guard_check_path. ls (metadata) is excluded; template env files (.env.example/.sample/.template/
  # .dist) are NOT in the secret-suffix list so they stay allowed (no command-wide exclusion, which
  # a `cat .env.example .env` multi-arg form could abuse). Honest ceiling: an interpreter
  # (python -c open()) or an uncommon content-emitter not in the verb list bypasses — the robust
  # path is the Read-tool deny (guard_check_read) + platform containment. Asymmetry by design: the
  # shell path enumerates common .env.<suffix> files, while the Read tool's `*.env.*` glob catches
  # any suffix (e.g. `.env.foo` / `.env.local.bak` slip the shell path but the Read equivalent denies).
  # GUARD-HOOKSPATH-CASE-BYPASS (seat HIGH, condition 2): BOTH legs fold (`-Eq` -> `-Eiq`). The
  # verb leg first — on a case-insensitive filesystem `/bin/CAT` resolves to `/bin/cat`, so a
  # byte-literal verb match is the same defect as a byte-literal path match (precedent in-file:
  # `:894-899` folds the CP-arm verbs, "same defect, one argument position to the left"). Then the
  # filename leg. Deny-side only; `.env.example` stays ALLOW because "example" is never a listed
  # suffix alternative — folding case cannot add it (design §4a).
  # GUARD-DENY-TRIO M2 (F3, D-240816-1): the verb leg now also lists CONTENT-DIGEST verbs
  # (md5/md5sum/shasum/sha*sum/cksum/sum/b2sum/b3sum/rhash/xxhsum/crc32/gpg/digest, and `openssl` scoped
  # to its TWO-WORD subcommand form `openssl dgst|sha256|…` — a bare `openssl` would over-match
  # `openssl rsa -in server.key`). A digest of a secret is a CONFIRMATION ORACLE (candidate-value
  # verification / offline brute-force of a short secret), categorically worse than metadata. METADATA
  # verbs (wc/stat/du/ls/file) stay OFF this list — the disclosed, accepted trade, fixtured both ways.
  # HONEST CEILING, stated not implied-closed: this list is NON-EXHAUSTIVE under the SAME interpreter/
  # unknown-binary ceiling the content-read arm already carries — `certutil`, a scripted `openssl -in`,
  # `python -c hashlib`, any renamed digester slips it. The oracle is NARROWED, not closed; the
  # complete-by-disqualification fix (invert to a positive metadata allowlist) is M-sized and boarded
  # separately. `_CP8B_READ_VERBS`' vetting of digests as harmless is UNCHANGED — a digest of a CONTROL-
  # PLANE config is genuinely harmless, so the secret/CP asymmetry is intentional and fixtured both ways.
  if ! selfedit_allowed \
     && printf '%s' "$cmd" | grep -Eiq '(^|[;&|]|[[:space:]])[[:space:]]*((cat|less|more|head|tail|grep|egrep|fgrep|rg|strings|xxd|od|hexdump|base64|nl|tac|diff|cmp|comm|awk|sed|sort|uniq|cut|paste|fold|jq|yq|rev|source|\.|md5|md5sum|shasum|sha1sum|sha224sum|sha256sum|sha384sum|sha512sum|cksum|sum|b2sum|b3sum|rhash|xxhsum|crc32|gpg|digest)[[:space:]]|openssl[[:space:]]+(dgst|sha1|sha224|sha256|sha384|sha512|sha3-224|sha3-256|sha3-384|sha3-512|md5|md5sum|rmd160|blake2b512|blake2s256|shake128|shake256)([[:space:]]|$))' \
     && printf '%s' "$cmd" | grep -Eiq '\.env(\.(local|production|development|staging|test|prod|dev|stage|qa|preview|ci|bak|old))?([[:space:];|&*]|$)|\.(pem|key)([[:space:];|&*]|$)|id_rsa|(^|[[:space:]/;|&])secrets?/'; then
    printf '%s' '13: reading secret material into context (the read half of exfil -> model/logs/PR) is human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # --- destructive matrix: moved VERBATIM from the PRE-SPLIT guard.sh (see git history; the line
  #     range that stood here died with the split) ---
  # CP-8a: the leading verb decides whether the ARGUMENTS are code or data. These carry
  # identical bytes and only the verb tells them apart:
  #     bash -c "rm -rf /"          <- the argument is CODE (a weapon) -> must DENY
  #     grep -rn "rm -rf" scripts/  <- the argument is DATA (a search) -> must ALLOW
  # A provably read-only SINGLE invocation therefore skips the matrix. Everything else
  # falls through with the command UNCHANGED, so no rule below has its input perturbed.
  # CP-8a (security re-review of #297): git's diff machinery (diff/log/show) honors
  # --output=<file> — an arbitrary file WRITE/TRUNCATE with NO shell redirect, so it slips both
  # the control-plane block above and (as a read verb) the exemption below.
  # `git diff --output=.github/workflows/ci.yml HEAD` zeroes the workflow on a clean tree.
  # Do NOT parse the --output TARGET: the guard sees PRE-shell-parse bytes, so any quoting /
  # escaping / substitution of the target (`--output="conformance/x"`, `--output=$(...)`) evades a
  # path match while git still writes the real path (a live bypass caught in re-review). Deny
  # `git ... --output` OUTRIGHT — fail-closed, no target to parse. The legitimate residual is a
  # plain redirect to a non-control-plane path (`git diff > /tmp/x`, which the guard allows) or
  # KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.
  # CP-8b: CP-8a's blanket `git … --output` deny lived here. It is now SUBCOMMAND-BOUND inside
  # _cp8b_git_write_denied (called above): still an OUTRIGHT deny with no target parsed, but scoped to
  # the subcommands that actually honor the flag (diff/log/show/format-patch/archive). That removes the
  # residual CP-8a recorded — `git commit -m "… --output …"`, where a commit message merely *mentions*
  # the flag and `-o` means `--only` — without weakening the deny for any subcommand that can write.
  if guard_read_only_command "$cmd"; then return 0; fi
  # recursive rm in any flag arrangement (-rf, -fr, -r -f, --recursive), bounded so
  # 'confirm'/'npm' are not matched, but quoted forms (bash -c "rm -rf") are.
  if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])rm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alnum:]]*[rR]|--recursive)'; then
    { printf '%s' '13: recursive rm is irreversible - human-gated.'; return 1; }
  fi
  # 9b: non-recursive rm of a DANGEROUS target — a glob, a data/critical file extension,
  # an absolute path, or a dotfile of record. Anchored to command position so a commit
  # message mentioning rm is not matched. Plain relative single files (rm stale.txt,
  # rm dist/bundle.js) remain ALLOWED to avoid over-blocking normal dev work.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]'; then
    if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(--[[:space:]]+)?[^;&|[:space:]]*[*?[][^;&|[:space:]]*([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?/[^[:space:]]' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*(\.env|/\.git)([[:space:]]|$|/)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?\.env([[:space:]]|$)'; then
      { printf '%s' '13: rm of a glob, data file, absolute path, or dotfile-of-record can be irreversible - human-gated. For an ABSOLUTE scratch path the escape is a repo-relative one; escape card: docs/operations/runtime-guards.md §Over-deny'; return 1; }
    fi
  fi
  # 9b: non-rm destruction primitives. Binaries are anchored to COMMAND POSITION
  # (start, or after a ; && || | separator, optional sudo) so a word like "truncate"
  # inside a commit message is NOT matched — only an actually-invoked command is.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(truncate|shred|wipefs|blkdiscard|mkfs(\.[a-z0-9]+)?)([[:space:]]|$)'; then
    { printf '%s' '13: in-place file/device destruction (truncate/shred/wipefs/blkdiscard/mkfs) is irreversible - human-gated.'; return 1; }
  fi
  # dd is a scalpel like rm: deny only when of= targets a device or a data-file extension
  # (dd of=test-fixture.img stays allowed; dd of=/dev/sda and dd of=db.sqlite are denied).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?dd[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq 'of=(/dev/|[^[:space:]]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$))'; then
    { printf '%s' '13: dd of= a device or data file overwrites it irreversibly - human-gated.'; return 1; }
  fi
  # redirection/empty-source truncation of an existing target. GENERIC by target: the
  # patterns below match ANY destination ([^[:space:]&|;]+), so truncating a scanner-config
  # (e.g. `: > .gitleaks.toml`) is already covered here — no path enumeration needed (KW10).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*):[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '/dev/null[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(cat|cp)[[:space:]]+/dev/null[[:space:]]+[>]?[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)echo[[:space:]]+-n[[:space:]]*>[[:space:]]*[^[:space:]&|;]+'; then
    { printf '%s' '13: redirection/empty-source truncation zeroes a file irreversibly - human-gated. TIP: to create or replace a file, use the Write tool (a shell >/: truncation is denied because it can irreversibly zero an existing file).'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-delete([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-exec[[:space:]]+(rm|shred|truncate)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(sudo[[:space:]]+)?xargs[[:space:]]+([^|]*[[:space:]])?(rm|shred|truncate|unlink|wipefs)([[:space:]]|$)'; then
    { printf '%s' '13: bulk irreversible deletion (find -delete / -exec rm / pipe to xargs rm) - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rsync[[:space:]]+[^|]*--delete([[:space:]]|$|[^a-z])'; then
    { printf '%s' '13: rsync --delete mirrors a source and removes destination files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)git[[:space:]]+clean[[:space:]]+[^|]*-[a-z]*[fdx]'; then
    { printf '%s' '13: git clean -f/-d/-x force-deletes untracked/ignored files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?mv[[:space:]]+[^;&|]*[[:space:]]/dev/null([[:space:]]|$)'; then
    { printf '%s' '13: moving a file onto /dev/null destroys its contents - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+reset[[:space:]]+.*--hard'; then
    { printf '%s' '13: git reset --hard discards work irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(npm|yarn|pnpm)[[:space:]]+publish'; then
    { printf '%s' '13: publishing a package is externally irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*(--force|--force-with-lease|--mirror|[[:space:]]-f([[:space:]]|$)|[[:space:]+]\+[^[:space:]]*[[:space:]]*$)'; then
    { printf '%s' '13: force/mirror push rewrites or deletes published history - human-gated.'; return 1; }
  fi
  # push to main/master in any refspec form: 'main', '+main', 'HEAD:main', 'x:master', "main" (incl. git -c … push)
  # CP-8b: SCOPED to a segment. The identical regex now runs per-segment instead of over the flat string,
  # so it can no longer match by SPANNING a shell separator — which is the whole false positive:
  #     git push -u origin fix/x && gh pr create --body "… merges to main"
  # (`git push` in segment 1, the word "main" in segment 2's PR body). A real push to main keeps both on
  # ONE segment and still denies. Only THIS rule's window narrows; every other matrix rule below still
  # sees the raw, unsplit command (`curl … | sh` keeps its pipe; `--admin` keeps its end-of-string anchor).
  # The segmenter also JOINS backslash-newline continuations first, which closes a pre-existing hole:
  # grep is line-oriented, so `git push \<newline> origin main` put `push` and `main` on different lines
  # and the flat regex matched NEITHER.
  if _cp8b_push_main_denied "$cmd"; then
    { printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1; }
  fi
  # S6: gh pr merge --admin/--administrator BYPASSES branch protection (incl. the control-plane-
  # ratification / required-review gate) — the fox opening its own henhouse. A SPEED BUMP (string
  # match): the real boundary is the platform never issuing the agent an admin credential
  # (docs/enterprise/platform-safety-boundary.md). The agent's sanctioned path is a NORMAL merge on
  # a recorded authenticated GO (scripts/promotion-verify.sh actuate); --admin is the SOLO kill-switch.
  # S6R (A1, `D-240825-1`): the porcelain flag is only half the arm — `--admin` IS the REST
  # PUT /pulls/N/merge, so the same doctrine, the same message, one extra disjunct. See
  # _s6_gh_api_admin above for the disqualifier, the deliberate contexts-POST exception, and the
  # honest ceiling (one client; curl/python siblings are boarded, not closed).
  # GUARD-READ-LANE-2 T2 (design §4) — THE SAME NORMALISATION, NOW ON THE PORCELAIN HALF TOO.
  # Until this line the porcelain greps read the RAW string while the REST half (_s6_gh_api_admin)
  # read a quote-stripped copy, so the arm was quote-honest on one side and quote-blind on the other:
  # `sh -c 'gh pr merge 5 --admin'` ALLOWED at 13b176de, as did `bash -lc "…"`, `xargs -0 sh -c '…'`
  # and a same-command `CMD='…'; sh -c "$CMD"`. A quote is a JOINER in the shell, not a boundary
  # (`me''rge` executes as `merge`), so deleting quotes/backslashes is what makes the bytes readable.
  # ★ THE FIX IS BYTE-LEVEL, AND ITS SCOPE IS EXACTLY THE JOINER BYTES NAMED HERE — no more. Round 0's
  # prose claimed "every wrapper shape closes at once … no new wrapper needs adding later"; MEASURED at
  # 4b9f464f that was FALSE, and round 1 closes what it missed. What is handled, each pinned by a cell:
  #   · QUOTE joiners `'` and `"`, and the escaping `\`  (round 0)          — `--ad""min`
  #   · a LINE CONTINUATION *inside* the command (round 1) — `tr` deleted the `\` but left the newline
  #     and grep is line-oriented, so `gh \<nl>pr merge …` matched nothing. `_cp8b_joinlines` first.
  #   · COMMAND SUBSTITUTION used as a joiner (round 1) — `--ad$()min`, `--ad``min`, `me$()rge`,
  #     `--ad`echo`min`. Handled by a SECOND view (`$_px`) with substitutions removed.
  #   · INTRA-TOKEN CONTINUATION, PARAMETER EXPANSION, NEWLINE-STRADDLING AND NESTED substitutions
  #     (round 2) — closed not as four more spellings but by the (A) disqualifier below.
  # FOUR VIEWS, deny if ANY matches — not one merged view. Stripping substitutions in the ONLY view
  # would LOSE a deny, because `` `gh pr merge 5 --admin` `` keeps the offending bytes INSIDE the
  # substitution. Add-only is a contract here: every view is a SUPERSET match over the raw string, so
  # nothing that denied before can stop denying (pinned by the R REG cells in agent-autonomy.sh).
  # HONEST CEILING, REWRITTEN AT ROUND 2 AND NARROWER THAN ROUND 1'S, one sentence per cell.
  # Round 1's ceiling said "bytes ABSENT from the string still pass", and named `$VAR`, `$(cat f)`
  # and `` `echo m` `` as examples. THAT SENTENCE IS NOW FALSE and is retired: inside a merge-shaped
  # command every one of those carries a `$` or a backtick, and (A) denies on the glue byte without
  # ever asking what it expands to (pinned: `--ad$xmin`, `"$@"`, `$ADMIN_FLAG`, `--ad$(cat f)min`).
  # ⚠️ ROUND 2's NEXT SENTENCE WAS ALSO FALSE, AND ROUND 3 MEASURED IT FALSE. It read "what is left is
  # only the case where NO glue byte and NO merge shape is in the string at all". `gh -R o/r pr merge
  # 5 --admin` has BOTH a merge shape and (with `$(date)` appended) a glue byte, and ALLOWED at
  # 07928fc1 — because the SHAPE TEST was an adjacency match and `gh` hoists its global flags in front
  # of the sub-command. The hole was never in the ceiling; it was in the predicate. Closed by
  # `_cp8b_gh_pr_merge_order` (see its header) and pinned by the T2R3 cells.
  # ── THE CEILING AS OF ROUND 3. THREE SENTENCES, EACH BACKED BY A CELL IN agent-autonomy.sh.
  #   (i) A `gh alias`: `gh mymerge 5` ALLOWs — `merge` is not in the command and no shape test can
  #       find a shape that is not there. Aliases live in `gh`'s own config, which this guard does not
  #       read. The CREATION of one is visible in a command string, and `gh alias set mm 'pr merge
  #       --admin'` ALLOWs TODAY — measured, boarded, not closed here. (Cells: `T2R3 CEILING (i)`, ×2.)
  #  (ii) The merge bytes living entirely OUTSIDE the command: `sh ./merge.sh` ALLOWs. The command
  #       names a FILE; the guard scans the command string, not the filesystem the command reaches.
  #       (Cell: `T2R3 CEILING (ii)`.)
  # (iii) GraphQL `mergePullRequest` is NOT a hole and is not listed as one: it HONOURS branch
  #       protection, which is why the REST endpoint is the interesting one — but that is GitHub-side
  #       behaviour, not a boundary this guard maintains. (See the same note on `_s6_gh_api_admin`.)
  # (i) and (ii) are one residual stated twice: the guard reads the bytes it is handed. It does not
  # run the shell, resolve the environment, expand an alias, or open a file. Neither is closed by any
  # amount of further normalisation — which is why round 2 stopped normalising, and why round 3 fixed
  # a PREDICATE rather than adding a spelling. They are boarded, not claimed closed.
  # ⚠️ `M-R4` DOES NOT EXIST, and its absence is deliberate rather than an oversight. Round 1 planned
  # a mutant per change and MEASURED that one planned subject had no probe that flipped on it alone,
  # so the number was cut rather than padded with a mutant that would survive while proving nothing.
  # The gap in the numbering is left visible on purpose: renumbering would hide that a planned lock
  # was dropped for cause.
  # ★★ T2 ROUND 2 — THE JOINER CLASS ENDS HERE, AND IT ENDS BY CHANGING THE FAILURE DIRECTION.
  # Rounds 0 and 1 each closed the joiner spellings they had measured, and the seat came back each
  # time with more: an INTRA-TOKEN continuation (`--ad\<nl>min` — the space-join made it `--ad min`),
  # a PARAMETER EXPANSION (`--ad${x:-}min` — in neither view), a NEWLINE inside the substitution
  # (`--ad$(<nl>)min` — sed and grep are line-oriented), and the NESTED forms
  # `--ad$(echo $(echo))min` / ``--ad`echo \`echo\``min`` (the strip was one non-nested pass).
  # All measured ALLOW at 35a2032f. ★ THE LESSON IS THAT ENUMERATION LOSES: the shell has more ways
  # to glue two fragments together than this guard will ever have rounds, and each round's closing
  # sentence was falsified by the next round's measurement.
  # So the rule below is not another spelling. It is a DISQUALIFIER, and it is fail-CLOSED: if the
  # command is MERGE-SHAPED and also carries a GLUE byte, it is denied OUTRIGHT — the guard never
  # asks what the glue would have expanded to. Every trick in the class needs glue, so the class is
  # closed by construction rather than by enumeration, and a spelling nobody has thought of yet is
  # closed too. The cost is a real over-deny (a legitimate `gh pr merge $(cat pr) --squash` now
  # needs its number spelled out); it is priced, pinned cell by cell, and small.
  _pj=$(_cp8b_joinlines "$cmd")
  _pe=$(_cp8b_joinlines_empty "$cmd")
  _pn=$(_s6_dequote "$_pj")
  _pne=$(_s6_dequote "$_pe")
  # The substitution-stripped twins, now stripped to a FIXPOINT and newline-flattened first, so the
  # nested and newline-straddling forms collapse instead of surviving one pass. These twins are not
  # decoration: they also feed the merge-SHAPE test below, which is what lets the disqualifier see a
  # shape that is itself hidden inside a construct (`gh pr me$(echo $(echo))rge`).
  _px=$(_s6_dequote "$(_cp8b_strip_subst "$_pj")")
  _pxe=$(_s6_dequote "$(_cp8b_strip_subst "$_pe")")
  # (A) MERGE-SHAPED? Asked over every view, so a shape hidden by quoting, continuation or
  # substitution still counts. Two shapes: the porcelain verb, and the REST merge endpoint.
  _pms=0
  # T2 round 3: the porcelain shape is the ADJACENCY grep UNION the TOKEN-ORDER walk (add-only; see
  # `_cp8b_gh_pr_merge_order`). The REST disjunct KEEPS its adjacency deliberately — `gh` REJECTS a
  # hoisted global flag before `api` (`gh -R o/r api …` exits "unknown shorthand flag" and never
  # reaches the endpoint), so there is no real invocation to widen for, and widening would only
  # manufacture over-denies. Measured, not assumed.
  # The REST disjunct ALSO now requires a MUTATION INDICATOR. Round 2 fired on `gh api` +
  # `pulls/N/merge` with no regard for the method, so `gh api …/pulls/5/merge --jq "$(cat q)"` — a GET
  # of the merge-STATUS resource, a pure read — was DENIED, and so was an ordinary `-H "X-Y: $(cat h)"`
  # header. That is an UNPRICED over-deny in exactly the read lane this row exists to protect, and it
  # is the failure mode the row was opened for. The indicator only brings (A) into line with what
  # `_s6_gh_api_admin_scan` has always required of the arm (A) fronts for.
  # T2 round 4: the INDICATOR is literal-token OR expansion-carried (see
  # `_cp8b_api_expansion_indicator` for the regression that made this necessary, and for the
  # read-only-flag exclusion that keeps round 3's refund). Only the LEAD `gh` is case-folded in the
  # adjacency greps — `[Gg][Hh]` — never `pr`, `merge`, `api` or any flag.
  # The api adjacency stays adjacency: measured on `gh 2.96.0`, `gh -R o/r api …` exits
  # `unknown shorthand flag: 'R'` and never reaches the endpoint, so there is no invocation to widen
  # for. That version is recorded because the claim is a MEASUREMENT of one release's CLI parsing.
  # T2 round 5: the expansion indicator is computed ONCE, over the QUOTE-PRESERVING views, and the
  # loop reads the answer. Two reasons, both measured rather than stylistic:
  #   · it must see QUOTES (see the function header) — `$_pn`/`$_pne` have had them deleted, and a
  #     de-quoted `-H "A: $X"` splits into two tokens and loses the read-only-flag exclusion;
  #   · the SUBSTITUTION-STRIPPED twins are the wrong input for it by construction. `_cp8b_strip_subst`
  #     DELETES `$(…)`/`${…}` — the exact bytes this test is about — so the strip can only ever remove
  #     indicators, never add one (any `$` left after stripping was there before). Dropping the twins
  #     therefore loses no deny, and keeping them would actively cost one: in `--jq $(x) $Y` the strip
  #     leaves `--jq` adjacent to `$Y` and hands it the exclusion it has not earned.
  _pai=1
  if _cp8b_api_expansion_indicator "$_pj" || _cp8b_api_expansion_indicator "$_pe"; then _pai=0; fi
  for _pv in "$_pn" "$_pne" "$_px" "$_pxe"; do
    if printf '%s' "$_pv" | grep -Eq '[Gg][Hh][[:space:]]+pr[[:space:]]+merge' \
       || _cp8b_gh_pr_merge_order "$_pv"; then _pms=1; break; fi
    if printf '%s' "$_pv" | grep -Eq '[Gg][Hh][[:space:]]+api' \
       && printf '%s' "$_pv" | grep -Eq 'pulls/[^[:space:]]*/merge' \
       && { printf '%s' "$_pv" | grep -Eq "$_CP8B_API_MUTATOR" \
            || [ "$_pai" = 0 ]; }; then _pms=1; break; fi
  done
  # (A) GLUE? Asked of the RAW command, deliberately: `_cp8b_joinlines` has already consumed the
  # backslash-newline by the time `$_pj` exists, so a joined view can no longer testify that a
  # continuation was ever there. `$` covers `$(…)`, `${…}` and a bare `$VAR` alike — the last of
  # those is the one no byte-level normalisation could ever reach, because its bytes are ABSENT.
  _pgl=0
  printf '%s' "$cmd" | grep -q '[$`]' && _pgl=1
  printf '%s\n' "$cmd" | grep -q '\\$' && _pgl=1
  if [ "$_pms" = 1 ] && [ "$_pgl" = 1 ]; then
    unset _pj _pe _pn _pne _px _pxe _pv _pms _pgl _pai 2>/dev/null || :
    { printf '%s' '13: gh pr merge / merge-endpoint call carries shell substitution or continuation - spell it plainly (no $(...), ${...}, backticks, or line continuation) so the guard can read it; --admin is human-gated. A legitimate merge works with the number and subject written out, or with the body passed via -F file.'; return 1; }
  fi
  # The incumbent --admin probe, unchanged in shape and now reading all four views. The anchor widens
  # from `([[:space:]]|=|$)` to `([^A-Za-z0-9_-]|$)` so `;`, `|`, `&`, `)` anchor too — W13's shape,
  # where deleting the quotes leaves `--admin;` mid-string. It still matters after (A): a glue-free
  # `sh -c 'gh pr merge 5 --admin'` has nothing for the disqualifier to fire on.
  _phit=0
  for _pv in "$_pn" "$_pne" "$_px" "$_pxe"; do
    if { printf '%s' "$_pv" | grep -Eq '[Gg][Hh][[:space:]]+pr[[:space:]]+merge' \
         || _cp8b_gh_pr_merge_order "$_pv"; } \
       && printf '%s' "$_pv" | grep -Eq '(--admin|--administrator)([^A-Za-z0-9_-]|$)'; then
      _phit=1; break
    fi
  done
  unset _pj _pe _pn _pne _px _pxe _pv _pms _pgl _pai 2>/dev/null || :
  if [ "${_phit:-0}" = 1 ] || _s6_gh_api_admin "$cmd"; then
    { unset _phit; printf '%s' '13: gh pr merge --admin bypasses branch protection (incl. control-plane-ratification) - human-gated. The agent actuates via a NORMAL merge on a recorded authenticated GO (scripts/promotion-verify.sh actuate); the --admin bypass is the solo kill-switch. See docs/operations/runtime-guards.md. The REST forms (gh api PUT/POST .../pulls/N/merge, protection or ruleset edits, repo DELETE) are the same bypass.'; return 1; }
  fi
  unset _phit 2>/dev/null || :
  # destructive SQL via a DB client
  if printf '%s' "$cmd" | grep -Eiq '(psql|mysql|mariadb|sqlite3|mongosh?).*(drop[[:space:]]+(table|database)|truncate|delete[[:space:]]+from)'; then
    { printf '%s' '13: destructive SQL (DROP/TRUNCATE/DELETE via a DB client) - human-gated.'; return 1; }
  fi
  # destructive DB resets via migration runners
  if printf '%s' "$cmd" | grep -Eiq '(prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|]*--force-reset|sequelize[^|]*db:migrate:undo:all|knex[^|]*migrate:rollback[^|]*--all|drizzle-kit[[:space:]]+push)'; then
    { printf '%s' '13: destructive DB reset via a migration runner - human-gated.'; return 1; }
  fi
  # dropdb as an invoked command (start or after a shell separator), not when merely
  # mentioned in prose (e.g. a commit message "fix dropdb bug").
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)dropdb([[:space:]]|$)'; then
    { printf '%s' '13: dropdb destroys a database irreversibly - human-gated.'; return 1; }
  fi
  # ORM / framework DB destruction (drop/reset/wipe/fresh) across stacks
  if printf '%s' "$cmd" | grep -Eiq '(rails|rake)[[:space:]]+db:(drop|reset|migrate:reset|purge)|artisan[[:space:]]+(migrate:fresh|migrate:reset|db:wipe)|manage\.py[[:space:]]+(flush|reset_db|sqlflush)|alembic[[:space:]]+downgrade[[:space:]]+base|flyway[[:space:]]+clean|dotnet[[:space:]]+ef[[:space:]]+database[[:space:]]+(drop|update[[:space:]]+0)'; then
    { printf '%s' '13: destructive DB drop/reset via an ORM/framework tool - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'pg_restore[^|]*(--clean|[[:space:]]-c([[:space:]]|$))'; then
    { printf '%s' '13: pg_restore --clean drops objects irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq 'redis-cli[^|]*(flushall|flushdb)'; then
    { printf '%s' '13: redis FLUSHALL/FLUSHDB wipes the datastore - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'kubectl[[:space:]]+([^|]*[[:space:]])?delete([[:space:]]|$)'; then
    { printf '%s' '13: kubectl delete removes cluster resources - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+(volume[[:space:]]+(rm|prune)|system[[:space:]]+prune[^|]*(-a|--all))'; then
    { printf '%s' '13: docker volume/system prune destroys persistent state - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'aws[[:space:]]+s3[[:space:]]+rm[^|]*--recursive|aws[[:space:]]+s3[[:space:]]+rb|aws[[:space:]]+rds[[:space:]]+delete-db-instance|aws[[:space:]]+dynamodb[[:space:]]+delete-table|gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+delete|az[[:space:]]+group[[:space:]]+delete|az[[:space:]]+sql[^|]*[[:space:]]delete'; then
    { printf '%s' '13: cloud resource deletion (storage/DB/instance) is irreversible - human-gated.'; return 1; }
  fi
  # 9b: cloud/infra destruction as capability families (verb-agnostic across vendors)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)terraform[[:space:]]+(destroy|apply)([[:space:]]|$)'; then
    { printf '%s' '13: terraform destroy/apply changes real infrastructure - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(aws|gcloud|az)[[:space:]][^|]*[[:space:]](delete|delete-[a-z-]+|terminate-[a-z-]+|remove|rb|destroy)([[:space:]]|$)'; then
    { printf '%s' '13: cloud resource deletion/termination is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)helm[[:space:]]+(uninstall|delete)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)kubectl[[:space:]]+(drain|cordon)([[:space:]]|$)'; then
    { printf '%s' '13: helm uninstall / kubectl drain disrupts running workloads - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(mongosh?|cockroach|psql|mysql)[^|]*(dropDatabase|drop[[:space:]]+database)' \
     || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(liquibase[[:space:]]+dropAll|flyway[[:space:]]+undo)'; then
    { printf '%s' '13: database drop via a client/migration tool is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(curl|wget|base64[[:space:]]+(-d|--decode)|xxd[[:space:]]+-r)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash|python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'; then
    { printf '%s' '13: piping a fetched/decoded payload into a shell is high-blast-radius - human-gated.'; return 1; }
  fi
  # 9b: data-exfiltration channels (PARTIAL — binary-name denial only; interpreters
  # (python -c, node -e) remain channels. The real control is the platform network-egress
  # allowlist — see docs/enterprise/platform-safety-boundary.md. This is a speed bump.)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(scp|sftp)[[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(curl|wget)[[:space:]][^|]*(-T[[:space:]]|--upload-file|-F[[:space:]]*[^[:space:]&|;]*@|--data-binary[[:space:]]*@|--post-file)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(nc|ncat|netcat)[[:space:]]+[^[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)rclone[[:space:]]+(copy|sync|move)[[:space:]][^|]*[a-zA-Z0-9_-]+:' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*mail[[:space:]]'; then
    { printf '%s' '13: possible data exfiltration (scp/sftp/curl-upload/nc/rclone/mail). Partial guard - the boundary is the platform egress allowlist - human-gated.'; return 1; }
  fi
  # 9b: eval of a command substitution hides the real command from inspection.
  # Anchored to command position so "eval $(...)" inside a commit message is NOT matched.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?eval[[:space:]]+[^;&|]*(\$\(|`)'; then
    { printf '%s' '13: eval of a command substitution obscures the executed command - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(vercel[[:space:]]+(deploy[[:space:]]+)?--prod|railway[[:space:]]+up|fly[[:space:]]+deploy|terraform[[:space:]]+apply|kubectl[[:space:]]+apply|helm[[:space:]]+(install|upgrade))'; then
    { printf '%s' '13: production deploy / infra apply is high-blast-radius - human-gated.'; return 1; }
  fi
  # prod-context catch-all: a mutating kube/helm op against a production context or namespace.
  # Patterns are intentionally `.`-prefixed (not leading `--`) so GNU grep does not parse them
  # as options; the leading `.` matches the space that always precedes the flag in real commands.
  if printf '%s' "$cmd" | grep -Eiq '.(-(kube-)?context[[:space:]=][^[:space:]]*prod)|[[:space:]]-n[[:space:]]+[^[:space:]]*prod' \
     && printf '%s' "$cmd" | grep -Eiq '(kubectl|helm)[[:space:]]([^|]*[[:space:]])?(apply|delete|create|replace|patch|scale|rollout|upgrade|install|uninstall|destroy)'; then
    { printf '%s' '13: mutating operation against a production context - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)([A-Z_]*ENV)=prod[a-z]*[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command in a production environment - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '.(--(env|environment)[[:space:]=]prod)' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command targeting production - human-gated.'; return 1; }
  fi
  return 0
}

# guard_check_mcp "<tool>" "<allowlist>" "<overrides>": ALLOW (return 0) / DENY (return 1 + reason).
# Pure: the adapter loads the policy and passes it in (the core never reads a file).
#   <tool>      a Claude MCP tool name, mcp__<server>__<action> (action = segment after the last __)
#   <allowlist> newline list of exact mcp__server__action OR mcp__server__* wildcards (explicit permit)
#   <overrides> newline list of "mcp__server__action=class" (reclassify; class 'read'/'data.read' => allow)
# Decision: allowlist > override-class > tokenized action-verb heuristic > fail-closed deny.
#   The heuristic tokenizes the action (camelCase->snake, lowercased): the first token must be a
#   read verb to allow, and ANY destructive verb token downgrades to deny (so get_and_delete /
#   fetchAndExport deny; list_deployments / get_updates stay read - the noun is not the verb).
# secret.read (A8 family 6) is deny-by-default by NAME: an action naming secret material, or a
# known secret-store server on a read, is denied even when a read verb leads.
# Honest ceiling: classifies by what the NAME reveals; a renamed action (get_data that exfiltrates),
# a secret read via a generic-named server/action (mcp__storage__read_blob), a server wildcard that
# admits a destructive tool, and real egress are NOT caught here — the platform egress allowlist +
# the 11c sandbox are the real controls (docs/enterprise/platform-safety-boundary.md).
guard_check_mcp() {
  t=$1; al=$2; ov=$3
  # 1. explicit allowlist: exact tool, or its server wildcard (mcp__server__*)
  if printf '%s\n' "$al" | grep -qxF -- "$t" 2>/dev/null; then return 0; fi
  if printf '%s\n' "$al" | grep -qxF -- "${t%__*}__*" 2>/dev/null; then return 0; fi
  # 2. class: a per-tool override wins; else heuristic on the action segment.
  act=${t##*__}
  _rest=${t#mcp__}; srv=$(printf '%s' "${_rest%%__*}" | tr 'A-Z' 'a-z')  # server segment, lowercased
  cls=$(printf '%s\n' "$ov" | while IFS='=' read -r k v; do [ "$k" = "$t" ] && { printf '%s' "$v"; break; }; done || true)
  if [ -z "$cls" ]; then
    # Tokenize the action: split camelCase to snake, lowercase, turn _/- into spaces.
    # Whole-token verb matching keeps legit compounds read (list_deployments, get_updates -
    # 'deployments'/'updates' are not the verbs 'deploy'/'update') while downgrading a read-
    # prefixed action that carries a destructive verb token (get_and_delete, fetchAndExport).
    rverbs=' read get list search query fetch describe show view find count '
    dverbs=' delete drop destroy remove truncate reset write update create insert upsert patch put set upload publish deploy send post email notify apply merge push revoke rotate export download '
    norm=$(printf '%s' "$act" | sed 's/\([a-zA-Z0-9]\)\([A-Z]\)/\1_\2/g' | tr 'A-Z_-' 'a-z  ')
    first=${norm%% *}
    cls=unknown
    case "$rverbs" in *" $first "*) cls=read ;; esac
    for tok in $norm; do
      case "$dverbs" in *" $tok "*) cls=destructive; break ;; esac
    done
    # secret-material READ is deny-by-default even when a read verb leads (A8 family 6 - the read
    # half of exfil). Catch it by NAME: (a) the action names secret material, or (b) the server is
    # a known secret store on a read. Ceiling: a secret read via a generic-named server/action
    # (e.g. mcp__storage__read_blob holding a secret) is NOT caught - that is the 11c sandbox's job.
    if [ "$cls" = "read" ] && printf '%s' "$act" | grep -Eiq 'secret|credential|passphrase|password|api[_-]?key|private[_-]?key|access[_-]?key|secret[_-]?key|auth[_-]?token|access[_-]?token'; then
      cls=secret.read
    fi
    if [ "$cls" = "read" ] && printf '%s' "$srv" | grep -Eiq 'vault|1password|onepassword|secretsmanager|secrets[_-]?manager|secret[_-]?manager|keyvault|key[_-]?vault|credstash|doppler|infisical|akeyless'; then
      cls=secret.read
    fi
  fi
  case "$cls" in
    read|data.read) return 0 ;;
    secret.read) printf '13: MCP tool %s reads secret/credential material - deny-by-default (the read half of exfil; A8 family 6). Allowlist it in .claude/mcp-policy.json if intended.' "$t"; return 1 ;;
    unknown) printf '13: MCP tool %s is not classifiable as read-only - denied (fail-closed). Allowlist it in .claude/mcp-policy.json if safe.' "$t"; return 1 ;;
    *) printf '13: MCP tool %s is a destructive/egress capability (%s) - human-gated. Allowlist it in .claude/mcp-policy.json if intended.' "$t" "$cls"; return 1 ;;
  esac
}

# guard_check_path "<path>": print reason + return 1 if denied, else 0.
# Moved from the PRE-SPLIT guard.sh (drop the jq line — caller passes the path); the line range that
# stood here died with the split, so this cites the file and the change, not a dead offset.
guard_check_path() {
  fp=$1
  # CP-8c: an adapter that can prove the protected repo root passes it as $2. When the target is a
  # dev clone (guard_dev_clone_relaxable), the CONTROL-PLANE denies below relax — the secret-write
  # deny does NOT. No root passed (kit-guard CLI, older adapters) => _cp8c_relax=0 => today's
  # behavior (fail-safe).
  _cp8c_root=${2:-}
  _cp8c_relax=0
  _cp8c_hint=''
  if [ -n "$_cp8c_root" ] && guard_dev_clone_relaxable "$fp" "$_cp8c_root"; then _cp8c_relax=1; fi
  # BYTE-TWIN of _cp8b_norm's sed (GUARD-CP-WRITE-ROUTES K-COUPLE) — the /./ FIXPOINT edit is applied
  # here identically; a byte-identity selftest leg pins the two seds equal so they cannot drift.
  fpn=$(printf '%s' "$fp" | sed -e 's#//*#/#g' -e ':b' -e 's#/\./#/#' -e 'tb' -e 's#^\./##' -e 's#/*$##' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta')
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  # GUARD-PATH-ALIAS-BYPASS (P0): judge the UNION — literal OR normalised OR RESOLVED. The rc is
  # CAPTURED, never discarded via `is_control_plane_path "$(_resolve_physical ...)"`: that form drops
  # the rc, `is_control_plane_path ""` answers ordinary, and every resolution failure becomes a
  # silent ALLOW. Any failure to resolve is itself a denial (design ceiling 9a).
  _res=''; _resok=0
  _res=$(_resolve_physical "$fp") && _resok=1 || _resok=0
  _rbase=''; [ "$_resok" = 1 ] && _rbase=$(basename "$_res" 2>/dev/null || printf '%s' "$_res")
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && [ "$_resok" = 0 ]; then
    printf '13: path (%s) could not be resolved - refusing to write to a target that cannot be identified.' "$fp"; return 1
  fi
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && { is_control_plane_path "$fp" || is_control_plane_path "$fpn"; }; then
    # A dev-clone addressed through a symlink from OUTSIDE temp gets the real remedy, not the kill
    # switch. Naming KIT_GUARD_SELFEDIT here would tell an operator to disarm the guard globally to
    # do work the guard is happy to allow by its real path — the endorsed-bypass class.
    if [ "${_cp8c_hint:-}" = symlinked-clone ]; then
      printf '%s' '13: this dev-clone was addressed through a symlink from outside the temp root, so the clone affordance does not apply (control-plane integrity). Address it by its real path — `cd <clone> && pwd -P` — and the same edit is allowed.'; return 1
    fi
    printf '%s' '13: modifying the guard / its config / CI gates is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && [ "$_resok" = 1 ] && is_control_plane_path "$_res"; then
    printf '13: this path resolves to a control-plane file (%s) - denied (control-plane integrity). The name it is reached by does not change what it writes.' "$_res"; return 1
  fi
  # GUARD-CP-HARDLINK-ALIAS (§2b): the CP-INODE disjunct, immediately after the resolved-CP arm and
  # UNDER THE SAME dev-clone relax gate that arm carries (Leg G). A non-empty name => a genuine CP
  # hardlink; empty => the engine's fail-safe (M1: a DISTINCT reason, true for an ordinary file).
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && [ "$_resok" = 1 ]; then
    if _hlnamed=$(_hardlink_alias_hit_cp "$_res" "$_cp8c_root"); then
      if [ -n "$_hlnamed" ]; then
        printf '13: this path is a hardlink to a control-plane file (%s) - denied (control-plane integrity). The name it is reached by does not change what it writes.' "$_hlnamed"
      else
        printf '13: could not verify the target'\''s hardlink aliases (stat/find unavailable, timed out, or an ambiguous root) - denied fail-safe (control-plane integrity). Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget - make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds); see docs/operations/runtime-guards.md, section Hardlink aliases.'
      fi
      return 1
    fi
  fi
  # WS1: validate by basename when the NORMALIZED path has no real parent directory — either it is a
  # bare name, OR it still ESCAPES its root (a leading/unresolved `..` the fixpoint could not consume),
  # which cannot be trusted by directory. A path with a genuine parent dir (`.vscode/settings.json`) is
  # matched precisely by is_control_plane_path above, so the net is skipped only there. This closes the
  # `./settings.json`, `a/../guard.sh`, multi-`..`, trailing-slash, AND leading-`../name` bypasses while
  # still allowing an innocent `.vscode/settings.json` / `app/config/settings.json`.
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ]; then
    _bare=1
    case "$fpn" in
      ..|../*|*/../*) _bare=1 ;;
      */*)           _bare=0 ;;
    esac
    if [ "$_bare" = 1 ]; then
      # A2 (case) — the FIFTH matcher. This bare/escaping-name net exists precisely for the relative
      # paths that is_control_plane_path's directory-anchored patterns cannot see, and it was still
      # byte-literal: measured, `guard-core.sh` DENIED while `Guard-Core.sh` was ALLOWED, and likewise
      # `Settings.json`, `MCP-Policy.json`, `../Guard-Core.sh`. Reachable via any harness or
      # `scripts/kit-guard` that passes a bare or escaping name. Fold once, then match a LOWERCASE list.
      _bn=$base
      case "$_bn" in *[A-Z]*) _bn=$(printf '%s' "$_bn" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
      case "$_bn" in
        guard.sh|guard-core.sh|kit-guard|pre-push|settings.json|settings.local.json|mcp-policy.json|codeowners|.meta-control-last|meta-control-log.md|\
        .gitleaks.toml|.gitleaksignore|.semgrepignore|.trivyignore|.checkov.yaml|.checkov.yml)
          printf '13: modifying a control-plane file (%s) is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
      esac
    fi
  fi
  # GUARD-CP-HARDLINK-ALIAS (§2b): the secret-INODE disjunct goes BEFORE the template allowlist (vet
  # HIGH-1) and is UNGATED — not relax-gated, not selfedit-gated — byte-parity with the direct secret
  # arms below (a relax-gated secret check would be strictly weaker than the direct arm it mirrors). A
  # genuine single-link `.env.example` produces no hit and falls through to the allowlist unchanged; a
  # hardlinked `.env.example`->`.env` produces a secret hit and denies before the allowlist greens it.
  # (UNGATED: the guard below carries NO _cp8c_relax — K(iv) pins that asymmetry vs the CP site above.)
  if [ "$_resok" = 1 ]; then
    if _hlnamed=$(_hardlink_alias_hit_secret "$_res" "$_cp8c_root"); then
      if [ -n "$_hlnamed" ]; then
        printf '13: this path is a hardlink to secret material (%s) - human-gated. The name it is reached by does not change what it writes.' "$_hlnamed"
      else
        printf '13: could not verify the target'\''s hardlink aliases (stat/find unavailable, timed out, or an ambiguous root) - denied fail-safe (refusing to write to a target whose aliases cannot be confirmed). Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget - make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds); see docs/operations/runtime-guards.md, section Hardlink aliases.'
      fi
      return 1
    fi
  fi
  # The template allowlist is the SECOND predicate that turns denies off, so it takes the
  # CONJUNCTION: allow only when the literal AND the resolved basenames are both template names.
  # Literal-only is a cloak (an alias NAMED .env.example reaching a real .env); resolved-only is a
  # new fail-open (the common `.env -> .env.example` symlink would flip DENY to ALLOW).
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist)
      case "$_rbase" in
        .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
      esac ;;
  esac
  # GUARD-CP-HARDLINK-ALIAS §2c: the byte-literal + case-folded secret arms are consolidated into
  # _is_secret_path (one source of truth, byte-identity-coupled). The template ALLOW above stays
  # byte-literal, so a case-variant `.ENV.EXAMPLE` falls through to THIS deny — an accepted over-deny.
  if _is_secret_path "$fp"; then
    printf '13: writing secret material (%s) - human-gated (use .env.example + a secrets manager).' "$base"; return 1
  fi
  # …and the same union on the RESOLVED path (both arms, via the same helper), so a benign name cannot
  # front a secret target.
  if [ "$_resok" = 1 ] && _is_secret_path "$_res"; then
    printf '13: this path resolves to secret material (%s) - human-gated. The name it is reached by does not change what it writes.' "$_res"; return 1
  fi
  return 0
}

# guard_check_push <remote-ref> <local-sha> <remote-sha>: print reason + return 1 if denied.
# Ref-based (more precise than the command-string git rules): real non-fast-forward detection.
guard_check_push() {
  remote_ref=$1; local_sha=$2; remote_sha=$3
  zero=0000000000000000000000000000000000000000
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      if [ "$local_sha" = "$zero" ]; then
        printf '%s' '13: deleting main/master is destructive and bypasses review - human-gated.'; return 1
      fi
      printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1 ;;
  esac
  # force-push / non-fast-forward to ANY branch: remote tip not an ancestor of the new tip.
  if [ "$remote_sha" != "$zero" ] && [ "$local_sha" != "$zero" ]; then
    if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
      printf '%s' '13: non-fast-forward (force) push rewrites published history - human-gated.'; return 1
    fi
  fi
  return 0
}

# shellcheck shell=sh
# =============================================================================
# guard-core.additions.sh (Slice B) — the EXACT snippet apply.py appends to
# .claude/hooks/guard-core.sh (after guard_check_push, before EOF). Not a
# standalone script: a function fragment sourced with the rest of the core.
# =============================================================================

# guard_check_skill "<skill_name>": the roster-authority dial (Slice B, opt-in, ships OFF).
# Prints a verdict TOKEN on line 1 (allow|ask|deny) and, for ask/deny, a reason on line 2+;
# ALWAYS returns 0 — the adapter (guard.sh) maps the token to a permission decision.
#
# Dial source: KIT_ROSTER_GUARD (per-session override) wins; else MODE= in .kit/roster.conf
# (repo-root-relative; path overridable via KIT_ROSTER_CONF for tests, mirroring
# RUNAWAY_BUDGET_CONFIG). The config file is itself control-plane, so an agent cannot flip the
# dial (see is_control_plane_path + the command/redirect matchers).
#
# FAIL-SAFE toward OFF (the load-bearing invariant): any unreadable/absent/garbage config, or a
# MODE that is not exactly ask|deny, routes to `allow`. A config error must NEVER wedge the
# session — the roster-authority FLOOR contract (CLAUDE.md/AGENTS.md) still steers by preference.
#
# Namespace match resists spoofing: the namespace is the part before the FIRST ':' (no colon =>
# the whole string), trimmed and lowercased, then whole-token matched against BLOCKLIST. So
# `Superpowers:x` (capitalized) and bare `superpowers` are BOTH caught, while `x::superpowers`
# (namespace `x`) and any non-blocklisted namespace (figma/vercel/LSPs) are allowed.
guard_check_skill() {
  _sk=$1
  _conf="${KIT_ROSTER_CONF:-.kit/roster.conf}"

  # 1. mode: session override wins; else MODE= from config; else empty (=> off). Unreadable => off.
  _mode="${KIT_ROSTER_GUARD:-}"
  if [ -z "$_mode" ] && [ -r "$_conf" ]; then
    _mode=$(grep -E '^[[:space:]]*MODE[[:space:]]*=' "$_conf" 2>/dev/null | tail -n1 \
      | sed -E 's/^[[:space:]]*MODE[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g; s/[[:space:]].*$//')
  fi
  _mode=$(printf '%s' "$_mode" | tr 'A-Z' 'a-z')
  # 2. fail-safe: only ask|deny are active; off / empty / garbage => allow.
  case "$_mode" in
    ask|deny) : ;;
    *) printf 'allow\n'; return 0 ;;
  esac

  # 3. namespace = part before the first ':'; trim ws; lowercase (spoof-resistant).
  _ns=${_sk%%:*}
  _ns=$(printf '%s' "$_ns" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr 'A-Z' 'a-z')
  [ -n "$_ns" ] || { printf 'allow\n'; return 0; }

  # 4. blocklist (fail-safe empty if unreadable): whole-token membership, never substring.
  _bl=''
  if [ -r "$_conf" ]; then
    _bl=$(grep -E '^[[:space:]]*BLOCKLIST[[:space:]]*=' "$_conf" 2>/dev/null | tail -n1 \
      | sed -E 's/^[[:space:]]*BLOCKLIST[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g' | tr 'A-Z' 'a-z')
  fi
  case " $_bl " in
    *" $_ns "*) : ;;
    *) printf 'allow\n'; return 0 ;;
  esac

  # 5. blocklisted namespace under an active mode => emit the mode + a MODE-APPROPRIATE reason.
  #    ask: the user is prompted and just approves to proceed (a soft nudge, not a block).
  #    deny: hard-blocked; the only escape is the per-session KIT_ROSTER_GUARD=off override.
  printf '%s\n' "$_mode"
  if [ "$_mode" = ask ]; then
    printf 'kit prefers its own roster (skills/; see skills/using-skills/SKILL.md for the foreign->kit equivalent). Approve this prompt to use `%s` anyway.\n' "$_sk"
  else
    printf 'kit prefers its own roster (skills/; see skills/using-skills/SKILL.md for the foreign->kit equivalent). To use `%s` anyway, set KIT_ROSTER_GUARD=off for this session.\n' "$_sk"
  fi
  return 0
}

# kit_dial_mode "<DIAL_NAME>": the ENFORCEMENT-DIAL reader (DIAL-DELIVERY Δ-A, ruling D-240811-2.1).
# Prints exactly `enforce` or `observe` on stdout and ALWAYS returns 0 — the consumer (today
# hooks/pre-push's two legs) compares the printed word, so a dial can never wedge a push by erroring.
#
# SOURCE: $ROOT/.kit/dials.conf — the REPO-ROOT path, never cwd-relative, so a linked worktree and a
# fixture tree each read their own state (and the kit's own conf can never leak into a fixture, which
# is what keeps hooks/pre-push's dial-leg selftests observe-by-default). $ROOT is the pre-push hook's
# own derivation when set; otherwise it is derived here. PARSE, DON'T SOURCE — guard_check_skill's
# proven idiom above (:1541-1556): a conf file must never become executable code reachable from a gate.
#
# FAIL-SAFE toward OBSERVE (the load-bearing invariant, matching the roster dial's fail-safe-to-off):
# an absent/unreadable/garbage file, a missing key, a value that is not exactly `enforce`, or a dial
# NAME outside [A-Z0-9_] all print `observe`. A dial that cannot be read must never refuse a push.
#
# PRECEDENCE IS ASYMMETRIC, and that asymmetry is the mechanism, not a nicety (owner-lens finding 1):
#   * the conf value is AUTHORITATIVE;
#   * an env var of the same name may ESCALATE observe -> enforce (a per-session tightening);
#   * an env var may NOT de-escalate a conf `enforce`. It LOSES, and one loud anomaly line is printed
#     (the SEC M1 shape at hooks/pre-push:224-236). Env-wins would leave every flip one silent,
#     sticky `export` from undone — a bypass CHEAPER than --no-verify, which at least announces
#     itself per command, and the exact "remember to export" asymmetry the ruling was written to kill.
# An UNSET/empty env var is the normal case and is never an anomaly.
kit_dial_mode() {
  _kdm_name=$1
  # A dial name is a shell identifier by construction; anything else would reach the indirection
  # below, so reject it here and fail safe (this function is never a place to evaluate input).
  case "$_kdm_name" in
    ''|*[!A-Z0-9_]*) printf 'observe\n'; return 0 ;;
  esac
  _kdm_root="${ROOT:-}"
  [ -n "$_kdm_root" ] || _kdm_root=$(git rev-parse --show-toplevel 2>/dev/null) || _kdm_root=""
  [ -n "$_kdm_root" ] || _kdm_root=.
  _kdm_conf="$_kdm_root/.kit/dials.conf"
  _kdm_val=''
  if [ -r "$_kdm_conf" ]; then
    _kdm_val=$(grep -E "^[[:space:]]*${_kdm_name}[[:space:]]*=" "$_kdm_conf" 2>/dev/null | tail -n1 \
      | sed -E "s/^[[:space:]]*${_kdm_name}[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//")
  fi
  # The env side, read INDIRECTLY (POSIX sh has no ${!name}); the name is charset-checked above.
  _kdm_env=$(eval "printf '%s' \"\${$_kdm_name:-}\"")
  if [ "$_kdm_val" = enforce ]; then
    if [ -n "$_kdm_env" ] && [ "$_kdm_env" != enforce ]; then
      # SANITIZE BEFORE INTERPOLATING (review round 1). The value is caller-controlled: a newline in
      # it would FORGE an extra instruction line on stderr — the same injection class hooks/pre-push
      # hardens `refuse_no_core` against (:17-26, where a crafted path could inject `--no-verify`
      # into a refusal). Strip CR/LF and bound the length; the diagnostic value is the first few
      # bytes, not an unbounded echo of whatever was exported.
      _kdm_safe=$(printf '%s' "$_kdm_env" | tr -d '\n\r' | cut -c1-40)
      # ONE LINE PER DIAL PER PROCESS, not per call (review round 1): decl_check_ref and go_relay each
      # consult the dial per ref-line, so a 3-ref push printed the identical anomaly 3x — the same
      # line-discipline defect go_relay's own ONE-RELAY-PER-INVOCATION rule exists to prevent. Keyed
      # per NAME so DECL and GO each still get their own warning. ⚠️ CEILING, measured (review round
      # 1): this memo binds only WITHIN ONE PROCESS. A caller that consults the dial inside a command
      # substitution runs each call in a SUBSHELL, so the assignment below cannot propagate back —
      # measured 3 anomaly lines on a 3-ref-line push both before and after this memo alone. The
      # suppression that actually binds is therefore the CALLER's: hooks/pre-push's `_kit_dial`
      # resolves each dial at most once per push invocation (3 -> 1, re-measured). This memo is kept
      # because it is correct for any in-process consumer and costs nothing; it is NOT the control.
      case " ${_kdm_warned:-} " in
        *" $_kdm_name "*) : ;;
        *)
          printf '%s\n' "kit dial: $_kdm_name='$_kdm_safe' in the environment cannot de-escalate the repo-carried enforce in .kit/dials.conf - the conf WINS (env may only escalate observe->enforce). Change the dial through the ratified control-plane ceremony; a one-off bypass is git push --no-verify, which at least announces itself." >&2
          _kdm_warned="${_kdm_warned:-} $_kdm_name" ;;
      esac
    fi
    printf 'enforce\n'; return 0
  fi
  [ "$_kdm_env" = enforce ] && { printf 'enforce\n'; return 0; }
  printf 'observe\n'; return 0
}
