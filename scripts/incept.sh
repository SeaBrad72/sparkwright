#!/bin/sh
# incept.sh — Inception bootstrap (DEVELOPMENT-PROCESS.md §3 / START-HERE.md).
# Transforms a freshly-cloned Agentic SDLC Kit into a configured, Inception-complete
# project, in place. Interactive by default; --noninteractive for automation/CI.
#
#   sh scripts/incept.sh [--name N] [--intent-owner O] [--stack S] \
#                        [--backlog md|github|linear|jira] [--noninteractive]
#
# It frees the root Claude-Code memory slot (CLAUDE.md = kit principles) by renaming the
# principles doc to ENGINEERING-PRINCIPLES.md and rewriting the principles-sense references,
# then stamps the PROJECT's CLAUDE.md/RUNBOOK.md/BACKLOG.md/ADR-000 and wires the profile CI.
set -eu

NAME="${INCEPT_NAME:-}"; OWNER="${INCEPT_INTENT_OWNER:-}"
STACK="${INCEPT_STACK:-typescript-node}"; BACKLOG="${INCEPT_BACKLOG:-md}"; INTERACTIVE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --intent-owner) OWNER="$2"; shift 2 ;;
    --stack) STACK="$2"; shift 2 ;;
    --backlog) BACKLOG="$2"; shift 2 ;;
    --noninteractive) INTERACTIVE=0; shift ;;
    -h|--help) echo "usage: incept.sh [--name N] [--intent-owner O] [--stack S] [--backlog md|github|linear|jira] [--noninteractive]"; exit 0 ;;
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

# --- safety guards ---
[ -f ENGINEERING-PRINCIPLES.md ] && { echo "error: ENGINEERING-PRINCIPLES.md exists — already incepted. Aborting." >&2; exit 1; }
{ [ -f CLAUDE.md ] && grep -q "Engineering Principles & Definition of Done" CLAUDE.md; } || {
  echo "error: not an un-incepted Agentic SDLC Kit (principles CLAUDE.md not found). Aborting." >&2; exit 1; }

# --- collect inputs ---
if [ "$INTERACTIVE" -eq 1 ]; then
  [ -n "$NAME" ]  || { printf 'Project name: '; read -r NAME; }
  [ -n "$OWNER" ] || { printf 'Intent owner: '; read -r OWNER; }
  printf 'Stack [%s]: ' "$STACK"; read -r _s || true; [ -n "${_s:-}" ] && STACK="$_s"
  printf 'Backlog backend (md/github/linear/jira) [%s]: ' "$BACKLOG"; read -r _b || true; [ -n "${_b:-}" ] && BACKLOG="$_b"
fi
[ -n "$NAME" ]  || { echo "error: --name required" >&2; exit 2; }
[ -n "$OWNER" ] || { echo "error: --intent-owner required" >&2; exit 2; }

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

# --- 4. RUNBOOK / BACKLOG / ADR-000 ---
[ -f RUNBOOK.md ] || { cp templates/RUNBOOK-TEMPLATE.md RUNBOOK.md; sedi "s/\[Project Name\]/${ENAME}/g" RUNBOOK.md; }
case "$BACKLOG" in
  md) [ -f BACKLOG.md ] || { cp templates/BACKLOG-TEMPLATE.md BACKLOG.md; sedi "s/\[Project Name\]/${ENAME}/g" BACKLOG.md; } ;;
  *)  echo "note: backlog backend '$BACKLOG' selected — declare it in CLAUDE.md §3; no BACKLOG.md created." ;;
esac
mkdir -p docs/architecture
[ -f docs/architecture/ADR-000-stack.md ] || { cp docs/ADR-000-EXAMPLE.md docs/architecture/ADR-000-stack.md; sedi "s/\[YYYY-MM-DD\]/${DATE}/g" docs/architecture/ADR-000-stack.md; }

# --- 5. wire CI from the chosen profile ---
mkdir -p .github/workflows
if [ -f "profiles/${STACK}/ci.yml" ]; then
  cp "profiles/${STACK}/ci.yml" .github/workflows/ci.yml
  [ -f "profiles/${STACK}/CODEOWNERS" ] && cp "profiles/${STACK}/CODEOWNERS" .github/CODEOWNERS
else
  echo "note: no profiles/${STACK}/ci.yml — add a CI workflow satisfying DEVELOPMENT-STANDARDS.md §14 (conformance/ci-gates.sh checks it)."
fi

# --- 6. next steps (the judgment incept does NOT automate) ---
cat <<EOF

✅ Inception scaffolding complete for "${NAME}" (kit v${VER}, stack ${STACK}).

Do the judgment steps incept does NOT automate (see START-HERE.md):
  1. Write the charter prose in CLAUDE.md (problem, vision, success metrics, scope).
  2. Record the real stack decision in docs/architecture/ADR-000-stack.md.
  3. Protect main (green CI to merge; builder != sole merger).
  4. Declare per-project config in CLAUDE.md §3 (autonomy tiers, SLO, review routing, WIP).
  5. Assign roles in CLAUDE.md §4.

Verify: sh conformance/inception-done.sh
EOF
