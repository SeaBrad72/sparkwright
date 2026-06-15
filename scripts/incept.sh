#!/bin/sh
# incept.sh — Inception bootstrap (DEVELOPMENT-PROCESS.md §3 / START-HERE.md).
# Transforms a freshly-cloned Sparkwright kit into a configured, Inception-complete
# project, in place. Interactive by default; --noninteractive for automation/CI.
#
#   sh scripts/incept.sh [--name N] [--intent-owner O] [--stack S] \
#                        [--backlog md|github|jira|ado|linear|gitlab] \
#                        [--ci github|gitlab] [--operator-fluency novice|adjacent|practitioner] [--noninteractive]
#
# It frees the root Claude-Code memory slot (CLAUDE.md = kit principles) by renaming the
# principles doc to ENGINEERING-PRINCIPLES.md and rewriting the principles-sense references,
# then stamps the PROJECT's CLAUDE.md/RUNBOOK.md/BACKLOG.md/ADR-000 and wires the profile CI.
set -eu

NAME="${INCEPT_NAME:-}"; OWNER="${INCEPT_INTENT_OWNER:-}"
STACK="${INCEPT_STACK:-typescript-node}"; BACKLOG="${INCEPT_BACKLOG:-md}"; INTERACTIVE=1
# A stack chosen via INCEPT_STACK is deliberate too — only an un-set stack is a silent default.
[ -n "${INCEPT_STACK:-}" ] && STACK_EXPLICIT=1 || STACK_EXPLICIT=0
CI="${INCEPT_CI:-github}"
FLUENCY="${INCEPT_OPERATOR_FLUENCY:-}"          # empty = undeclared (nudge); else stamped
OPERATOR_FLUENCIES="novice adjacent practitioner"
# Canonical named backlog backends (one source of truth — conformance/backlog-adapters.sh
# asserts this set agrees with DEVELOPMENT-PROCESS.md §6 and docs/work-tracking/adapters.md).
BACKLOG_BACKENDS="md github jira ado linear gitlab"
# CI platforms with a shipped reference pipeline. The contract is the gate-ids (the platform
# is open — see docs/operations/ci-platforms.md); these are the two with a worked reference.
CI_PLATFORMS="github gitlab"

# reqval: a value-taking flag must have a value (else dash's `shift 2` would fail
# under set -e/-u and abort with a confusing error instead of a clean exit 2).
reqval() { [ "$1" -ge 2 ] || { echo "incept: $2 requires a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) reqval $# --name; NAME="$2"; shift 2 ;;
    --intent-owner) reqval $# --intent-owner; OWNER="$2"; shift 2 ;;
    --stack) reqval $# --stack; STACK="$2"; STACK_EXPLICIT=1; shift 2 ;;
    --backlog) reqval $# --backlog; BACKLOG="$2"; shift 2 ;;
    --ci) reqval $# --ci; CI="$2"; shift 2 ;;
    --operator-fluency) reqval $# --operator-fluency; FLUENCY="$2"; shift 2 ;;
    --noninteractive) INTERACTIVE=0; shift ;;
    -h|--help) echo "usage: incept.sh [--name N] [--intent-owner O] [--stack S] [--backlog md|github|jira|ado|linear|gitlab] [--ci github|gitlab] [--operator-fluency novice|adjacent|practitioner] [--noninteractive]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# escape a string for safe use as a sed REPLACEMENT (handles & / \)
esc() { printf '%s' "$1" | sed 's/[&/\\]/\\&/g'; }
# portable in-place sed: last positional arg is the FILE (POSIX; no bash ${@: -1})
sedi() {
  last=
  for last in "$@"; do :; done
  sed -i.bak "$@" && rm -f "${last}.bak"
}

# 9f: fail fast if universal prerequisites are missing — jq is hard-required by the
# guard and conformance, so proceeding would only defer a cryptic failure.
if [ -f scripts/preflight.sh ] && ! sh scripts/preflight.sh >/dev/null 2>&1; then
  echo "incept: missing prerequisites. Run 'sh scripts/preflight.sh' for the list + install hints. Aborting." >&2
  exit 1
fi

# --- safety guards ---
[ -f ENGINEERING-PRINCIPLES.md ] && { echo "error: ENGINEERING-PRINCIPLES.md exists — already incepted. Aborting." >&2; exit 1; }
{ [ -f CLAUDE.md ] && grep -q "Engineering Principles & Definition of Done" CLAUDE.md; } || {
  echo "error: not an un-incepted Sparkwright kit (principles CLAUDE.md not found). Aborting." >&2; exit 1; }

# brownfield safety: warn (never modify) if a .claude/ exists without the kit guard wired.
if [ -f .claude/settings.json ] && ! grep -q 'guard\.sh' .claude/settings.json; then
  echo "warning: .claude/settings.json present but the kit guard is not registered." >&2
  echo "         If this is an existing repo, MERGE .claude/ per docs/adoption/brownfield.md" >&2
  echo "         (add, do not overwrite) before running agents. Continuing without touching .claude/." >&2
fi

# --- collect inputs ---
if [ "$INTERACTIVE" -eq 1 ]; then
  [ -n "$NAME" ]  || { printf 'Project name: '; read -r NAME; }
  [ -n "$OWNER" ] || { printf 'Intent owner: '; read -r OWNER; }
  printf 'Stack [%s] (compare: docs/STACK-SELECTION.md): ' "$STACK"; read -r _s || true; [ -n "${_s:-}" ] && { STACK="$_s"; STACK_EXPLICIT=1; }
  printf 'Backlog backend (md/github/jira/ado/linear/gitlab) [%s]: ' "$BACKLOG"; read -r _b || true; [ -n "${_b:-}" ] && BACKLOG="$_b"
  printf 'CI platform (github/gitlab) [%s]: ' "$CI"; read -r _c || true; [ -n "${_c:-}" ] && CI="$_c"
fi
[ -n "$NAME" ]  || { echo "error: --name required" >&2; exit 2; }
[ -n "$OWNER" ] || { echo "error: --intent-owner required" >&2; exit 2; }
case " $BACKLOG_BACKENDS " in *" $BACKLOG "*) : ;; *) echo "error: unknown --backlog '$BACKLOG' (one of: $BACKLOG_BACKENDS)" >&2; exit 2 ;; esac
case " $CI_PLATFORMS " in *" $CI "*) : ;; *) echo "error: unknown --ci '$CI' (one of: $CI_PLATFORMS)" >&2; exit 2 ;; esac
if [ -n "$FLUENCY" ]; then
  case " $OPERATOR_FLUENCIES " in *" $FLUENCY "*) : ;; *) echo "error: unknown --operator-fluency '$FLUENCY' (one of: $OPERATOR_FLUENCIES)" >&2; exit 2 ;; esac
fi

# 9g: never SILENTLY default the stack — make the default choice explicit + pointed.
if [ "$STACK_EXPLICIT" -eq 0 ]; then
  echo "notice: no --stack given — using '$STACK'. Choose deliberately: docs/STACK-SELECTION.md" >&2
fi
[ -n "$FLUENCY" ] || echo "notice: operator fluency not declared. New to enterprise SDLC? read ONBOARDING.md. Already fluent? pass --operator-fluency practitioner. Leaving the field for you to fill in CLAUDE.md." >&2

DATE=$(date +%Y-%m-%d)
VER=$(cat VERSION 2>/dev/null || echo "unknown")
ENAME=$(esc "$NAME"); EOWNER=$(esc "$OWNER")

# --- 1. free the root memory slot ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git mv CLAUDE.md ENGINEERING-PRINCIPLES.md
else
  mv CLAUDE.md ENGINEERING-PRINCIPLES.md
fi
sedi 's/| \*\*`CLAUDE.md`\*\* (this) |/| **`ENGINEERING-PRINCIPLES.md`** (this) |/' ENGINEERING-PRINCIPLES.md

# --- 2. rewrite principles-sense references (project-sense CLAUDE.md refs stay) ---
sedi -e 's/and `CLAUDE.md` (principles + Definition of Done)/and `ENGINEERING-PRINCIPLES.md` (principles + Definition of Done)/' \
     -e 's/The authoritative checklist is in \*\*`CLAUDE.md`\*\*/The authoritative checklist is in **`ENGINEERING-PRINCIPLES.md`**/' \
     -e 's#Definition-of-Done "CI/CD" check, `CLAUDE.md`)#Definition-of-Done "CI/CD" check, `ENGINEERING-PRINCIPLES.md`)#' \
     DEVELOPMENT-STANDARDS.md
sedi -e 's/and `CLAUDE.md` (authoritative principles + Definition of Done)/and `ENGINEERING-PRINCIPLES.md` (authoritative principles + Definition of Done)/' \
     -e 's/When they overlap, `CLAUDE.md` is authoritative/When they overlap, `ENGINEERING-PRINCIPLES.md` is authoritative/' \
     DEVELOPMENT-PROCESS.md
sedi 's/| \*\*`CLAUDE.md`\*\* | Principles + Definition of Done. Authoritative. |/| **`ENGINEERING-PRINCIPLES.md`** | Principles + Definition of Done. Authoritative. |/' README.md
sedi 's/`CLAUDE.md` (principles + Definition of Done)/`ENGINEERING-PRINCIPLES.md` (principles + Definition of Done)/' START-HERE.md
sedi 's#`DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md`#`DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `ENGINEERING-PRINCIPLES.md`#' MAINTAINING.md
sedi 's/\*\*Principles + Definition of Done:\*\* `CLAUDE.md`/**Principles + Definition of Done:** `ENGINEERING-PRINCIPLES.md`/' templates/PROJECT-CLAUDE-TEMPLATE.md

# --- 3. stamp the project CLAUDE.md ---
cp templates/PROJECT-CLAUDE-TEMPLATE.md CLAUDE.md
sedi -e "s/\*\*Project:\*\* \[name\]/**Project:** ${ENAME}/" \
     -e "s/\*\*Intent owner:\*\* \[who owns the why\]/**Intent owner:** ${EOWNER}/" \
     -e "s#\*\*Status:\*\* \[Inception / Active / Maintenance / Paused\]#**Status:** Inception#" \
     -e "s/\*\*Created:\*\* \[date\]/**Created:** ${DATE}/" \
     -e "s#\*\*Kit version adopted:\*\* \[vX.Y.Z.*\]#**Kit version adopted:** v${VER}#" \
     CLAUDE.md
if [ -n "$FLUENCY" ]; then
  # Capitalize first letter for the human-facing value (Novice/Adjacent/Practitioner)
  FCAP=$(printf '%s' "$FLUENCY" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$FLUENCY" | cut -c2-)
  sedi "s#\*\*Operator fluency\*\* (§onboarding): \[Novice / Adjacent / Practitioner\]#**Operator fluency** (§onboarding): ${FCAP}#" CLAUDE.md
fi

# --- 4. RUNBOOK / BACKLOG / ADR-000 ---
[ -f RUNBOOK.md ] || { cp templates/RUNBOOK-TEMPLATE.md RUNBOOK.md; sedi "s/\[Project Name\]/${ENAME}/g" RUNBOOK.md; }
[ -f SECURITY.md ] || cp templates/SECURITY-TEMPLATE.md SECURITY.md
case "$BACKLOG" in
  md) [ -f BACKLOG.md ] || { cp templates/BACKLOG-TEMPLATE.md BACKLOG.md; sedi "s/\[Project Name\]/${ENAME}/g" BACKLOG.md; } ;;
  jira)
    [ -f JIRA-SETUP.md ] || { cp templates/JIRA-SETUP-TEMPLATE.md JIRA-SETUP.md; sedi "s/\[Project Name\]/${ENAME}/g" JIRA-SETUP.md; }
    echo "note: backlog backend 'jira' selected — JIRA-SETUP.md written; configure it, then verify with 'sh conformance/tracker-contract.sh'. Declare the backend in CLAUDE.md §3." ;;
  *)
    [ -f TRACKER-SETUP.md ] || { cp templates/TRACKER-SETUP-TEMPLATE.md TRACKER-SETUP.md; sedi "s/\[Project Name\]/${ENAME}/g; s/\[BACKEND\]/${BACKLOG}/g" TRACKER-SETUP.md; }
    echo "note: backlog backend '$BACKLOG' selected (convention-tier) — TRACKER-SETUP.md written; map it via docs/work-tracking/adapters.md. Declare it in CLAUDE.md §3." ;;
esac
mkdir -p docs/architecture
[ -f docs/architecture/ADR-000-stack.md ] || { cp docs/ADR-000-EXAMPLE.md docs/architecture/ADR-000-stack.md; sedi "s/\[YYYY-MM-DD\]/${DATE}/g" docs/architecture/ADR-000-stack.md; }

# --- 5. wire CI from the chosen profile (platform-specific path/reference) ---
# The contract is the gate-ids; the platform is open (docs/operations/ci-platforms.md).
# github → .github/workflows/ci.yml ; gitlab → .gitlab-ci.yml at the repo root.
case "$CI" in
  github)
    mkdir -p .github/workflows
    if [ -f "profiles/${STACK}/ci.yml" ]; then
      cp "profiles/${STACK}/ci.yml" .github/workflows/ci.yml
      [ -f "profiles/${STACK}/CODEOWNERS" ] && cp "profiles/${STACK}/CODEOWNERS" .github/CODEOWNERS
    else
      echo "note: no profiles/${STACK}/ci.yml — add a CI workflow satisfying DEVELOPMENT-STANDARDS.md §14 (conformance/ci-gates.sh checks it)."
    fi
    ;;
  gitlab)
    if [ -f "profiles/${STACK}/ci.gitlab-ci.yml" ]; then
      cp "profiles/${STACK}/ci.gitlab-ci.yml" .gitlab-ci.yml
      # GitLab reads CODEOWNERS from root, .gitlab/, or docs/ — .gitlab/ mirrors .github/.
      [ -f "profiles/${STACK}/CODEOWNERS" ] && { mkdir -p .gitlab; cp "profiles/${STACK}/CODEOWNERS" .gitlab/CODEOWNERS; }
    else
      echo "note: no profiles/${STACK}/ci.gitlab-ci.yml — add a .gitlab-ci.yml satisfying DEVELOPMENT-STANDARDS.md §14 (conformance/ci-gates.sh checks it; see docs/operations/ci-platforms.md)."
    fi
    ;;
esac

# --- 5b. install the runtime-guard git pre-push hook (default-on, brownfield-safe) ---
# Git hooks are not version-controlled, so incept installs the reference per-clone.
# Never clobber an existing hook (same discipline as the .claude/ brownfield path).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -f hooks/pre-push ]; then
  HOOK_DST=$(git rev-parse --git-path hooks/pre-push)
  if [ -e "$HOOK_DST" ]; then
    echo "note: $HOOK_DST already exists — NOT overwriting (brownfield-safe). To chain the kit"
    echo "      guard, call 'sh \"$PWD/hooks/pre-push\"' from your existing hook, or replace it."
  else
    mkdir -p "$(dirname "$HOOK_DST")"
    cp hooks/pre-push "$HOOK_DST" && chmod +x "$HOOK_DST"
    echo "installed runtime guard: $HOOK_DST (blocks force-push/push-to-main; bypass: git push --no-verify)"
  fi
fi

# --- 6. next steps (the judgment incept does NOT automate) ---
# Branch-protection guidance is platform-specific: branch-protection.sh / BRANCH-PROTECTION.md
# use the GitHub API; on GitLab the protected-branches equivalent is adopter-owned (honest
# coupling note — see docs/operations/ci-platforms.md).
case "$CI" in
  github) PROTECT_HINT="Protect main NOW — run the gh-api command in profiles/${STACK}/BRANCH-PROTECTION.md; verify with: sh conformance/branch-protection.sh" ;;
  gitlab) PROTECT_HINT="Protect main NOW — in GitLab: Settings → Repository → Protected branches (require merge request + pipeline success + an approval rule). branch-protection.sh uses the GitHub API; the GitLab equivalent is adopter-owned — see docs/operations/ci-platforms.md." ;;
esac
cat <<EOF

✅ Inception scaffolding complete for "${NAME}" (kit v${VER}, stack ${STACK}, CI ${CI}).
Note: the kit's principles doc moved to ENGINEERING-PRINCIPLES.md; this new CLAUDE.md is YOUR project guide (charter, config, roles).

Do the judgment steps incept does NOT automate (see START-HERE.md):
  1. Write the charter prose in CLAUDE.md (problem, vision, success metrics, scope).
  2. Record the real stack decision in docs/architecture/ADR-000-stack.md.
  3. ${PROTECT_HINT}
  4. Declare per-project config in CLAUDE.md §3 (autonomy tiers, SLO, review routing, WIP).
  5. Assign roles in CLAUDE.md §4.
  6. Local runtime guard installed at .git/hooks/pre-push (force-push/push-to-main; bypass: --no-verify).
     Other runtimes: pipe proposed commands through scripts/kit-guard (docs/operations/runtime-guards.md).

Verify: sh conformance/inception-done.sh
EOF
