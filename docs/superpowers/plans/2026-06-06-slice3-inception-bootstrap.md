# Slice 3: Inception Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `scripts/incept.sh` — a one-command, in-place Inception bootstrap that turns a freshly-cloned kit into a configured project — plus the templates it stamps and an executable Inception-Done conformance check.

**Architecture:** Contract/reference/conformance slice on branch `feature/slice-3-inception-bootstrap`. The **canonical kit stays un-incepted** (principles remain in `CLAUDE.md`). `incept.sh` performs the adoption transform: `git mv CLAUDE.md ENGINEERING-PRINCIPLES.md`, rewrites the *principles-sense* references (leaving *project-sense* `CLAUDE.md` references intact), stamps a project `CLAUDE.md`/`RUNBOOK.md`/`BACKLOG.md`/`ADR-000`, and wires the chosen profile's CI. `conformance/inception-done.sh` verifies the 7-item gate; CI copies the kit to a temp dir, runs incept non-interactively, and asserts the gate passes (never transforms the kit itself).

**Tech Stack:** POSIX `sh` (portable `sed -i.bak`), Git, GitHub Actions. Spec: `docs/superpowers/specs/2026-06-06-slice3-inception-bootstrap-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `templates/RUNBOOK-TEMPLATE.md` (new) | Cold-resume runbook template |
| `templates/BACKLOG-TEMPLATE.md` (rewrite) | §6 flow-board backlog template |
| `conformance/inception-done.sh` (new) | Verify the Inception-Done gate in a project dir |
| `scripts/incept.sh` (new) | The in-place bootstrap (rename + ref-rewrite + stamp + CI wire) |
| `conformance/README.md` (edit) | Index `inception-done.sh` |
| `.github/workflows/ci.yml` (edit) | Add `bootstrap` job (incept-into-temp → inception-done) |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md` (edit) | 2.2.0; changelog; Slice 3 done + 6→5 |

**Precondition:** on branch `feature/slice-3-inception-bootstrap` (the spec commit is here). The canonical kit's `CLAUDE.md` is NOT renamed by this slice — only `incept.sh` renames, at adoption time.

---

### Task 1: templates/RUNBOOK-TEMPLATE.md

**Files:**
- Create: `templates/RUNBOOK-TEMPLATE.md`

- [ ] **Step 1: Write the template**

Create `templates/RUNBOOK-TEMPLATE.md`:

```markdown
# [Project Name] — RUNBOOK

> **Template.** Created at Inception; grow it at each release. Must enable a **cold resume** by another engineer or agent (DEVELOPMENT-STANDARDS.md §11). Fill every `[...]`.

**Project:** [Project Name]
**Last Updated:** [date]

---

## 1. Local setup
- Prerequisites: [runtime + version, package manager, Docker/devcontainer]
- Install: `[install command]`
- Configure env: copy `.env.example` → `.env.local`, fill values (see §3)
- Run locally: `[dev command]`

## 2. Test / build
- Test: `[test command]` · Coverage: `[coverage command]` (≥80%, 100% critical)
- Lint / type-check: `[commands]`
- Build: `[build command]`

## 3. Environment variables
Documented in `.env.example` (committed, placeholders only). Required:
- `[VAR]` — [purpose] — [where to obtain]

## 4. Deploy
- Target: [Vercel / Railway / container / …]
- Trigger: [merge to main → auto-deploy / manual]
- Steps: `[deploy command(s)]`

## 5. Rollback
- Fastest path: [feature-flag off / redeploy previous / revert+redeploy]
- Command: `[rollback command]`
- Every release declares its rollback path before shipping (DEVELOPMENT-PROCESS.md §10).

## 6. Disaster recovery
- **RPO:** [< 24h default] · **RTO:** [< 4h default]
- Backups: [cadence, location] · Restore verified: [date] (recurring-maintenance item)

## 7. Test accounts & credentials
- [account/role] — [location of credentials, e.g. secrets manager path] (never commit secrets)

## 8. Monitoring & alerting
- Error tracking: [tool/link] · Health check: [endpoint] · Alerts: [what fires, to whom]

## 9. Known issues / technical debt
- [issue] — [impact] — [tracking link]

---

**Resume check:** could another engineer or agent take this project cold using only this file + README + the kit docs? If not, fill the gaps.
```

- [ ] **Step 2: Verify and commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
grep -q "cold resume" templates/RUNBOOK-TEMPLATE.md && grep -q "## 5. Rollback" templates/RUNBOOK-TEMPLATE.md && echo OK
git add templates/RUNBOOK-TEMPLATE.md
git commit -m "feat: add RUNBOOK-TEMPLATE.md (cold-resume runbook)"
```
Expected: prints `OK`.

---

### Task 2: templates/BACKLOG-TEMPLATE.md (rewrite to flow-board)

**Files:**
- Modify (overwrite): `templates/BACKLOG-TEMPLATE.md`

- [ ] **Step 1: Replace the file's entire contents**

Overwrite `templates/BACKLOG-TEMPLATE.md` with exactly this content (replaces the stale phase/PROGRESS model with the §6 flow-board):

```markdown
# [Project Name] — Backlog (Flow Board)

> **Template.** The tactical work-item queue that runs the loop (DEVELOPMENT-PROCESS.md §6). Ordered, not a pile. This is the `BACKLOG.md` backend; swap for GitHub Issues/Linear/Jira per the project `CLAUDE.md` if chosen.

**Created:** [date] · **Backlog backend:** BACKLOG.md (repo-native)

## How to use
- Every item has: **intent** (why) · **acceptance criteria** · **size** (one-flow small) · **risk/complexity tag** · **owner** (human or agent) · **links** (spec/PR/milestone).
- **Order** by value × urgency ÷ effort-risk — the intent owner ranks; the lead breaks ties on risk/deps. No story points.
- Work types share one board and are prioritized against each other: **feature · bug · tech-debt · spike · recurring**. Tech-debt gets a standing paydown share each cycle.
- Move items down the states as they flow. Entering **In Progress** is an atomic ownership claim (no double-claims).

---

## Ready
> Passed Definition of Ready (criteria present, sliced, deps known). Safe to start.

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |
|------|--------------|---------------------|------|------|------|-------|-------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] |

## In Progress
> WIP-limited. One atomic claim per item.

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review
> Builder ≠ sole reviewer. Awaiting merge gate.

| Item | Reviewer | PR |
|------|----------|----|
| | | |

## Released
> Deployed; awaiting outcome validation (did it move its metric?).

| Item | Released | Success metric / hypothesis |
|------|----------|------------------------------|
| | | |

## Done
> Definition of Done met, L1 retro written, outcome validated.

| Item | Closed | Retro/outcome |
|------|--------|---------------|

## Blocked
| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|

---

## Backlog (unrefined)
> Validated candidates from Discover, not yet Ready. The roadmap/parking-lot lives separately (strategic altitude).

- [ ] [candidate] — [intent] — [risk tag]

**Last Updated:** [date]
```

- [ ] **Step 2: Verify the stale model is gone and the flow-board is present**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
grep -Eqi "Completed Phases|Innovation Features|PROGRESS.md|Phase X" templates/BACKLOG-TEMPLATE.md && echo "FAIL: stale model remains" || echo "OK: no stale phase model"
grep -q "## In Progress" templates/BACKLOG-TEMPLATE.md && grep -q "atomic ownership claim" templates/BACKLOG-TEMPLATE.md && echo "OK: flow-board present"
```
Expected: `OK: no stale phase model` then `OK: flow-board present`.

- [ ] **Step 3: Commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git add templates/BACKLOG-TEMPLATE.md
git commit -m "feat: rewrite BACKLOG-TEMPLATE.md to the §6 flow-board model"
```

---

### Task 3: conformance/inception-done.sh

**Files:**
- Create: `conformance/inception-done.sh`

- [ ] **Step 1: Write the gate checker**

Create `conformance/inception-done.sh`:

```sh
#!/bin/sh
# inception-done.sh — verify the Inception-Done gate (START-HERE.md / DEVELOPMENT-PROCESS.md §3)
# in a project directory. Usage: sh conformance/inception-done.sh [dir]   (default: .)
set -eu

DIR="${1:-.}"
cd "$DIR"
fail=0

need() { if [ -e "$1" ]; then echo "PASS present: $1"; else echo "FAIL missing: $1"; fail=1; fi; }

need ENGINEERING-PRINCIPLES.md
need CLAUDE.md
need RUNBOOK.md
need .claude
need .github/workflows/ci.yml

if ls docs/architecture/ADR-000*.md >/dev/null 2>&1; then
  echo "PASS present: docs/architecture/ADR-000*.md"
else
  echo "FAIL missing: docs/architecture/ADR-000*.md"; fail=1
fi

if [ -f BACKLOG.md ] || grep -q "Backlog backend" CLAUDE.md 2>/dev/null; then
  echo "PASS present: backlog (BACKLOG.md or declared backend)"
else
  echo "FAIL missing: BACKLOG.md or a declared backlog backend"; fail=1
fi

# project CLAUDE.md key header fields must be filled (no leftover placeholders)
if grep -Eq '\*\*Project:\*\* \[name\]|\*\*Intent owner:\*\* \[who owns' CLAUDE.md 2>/dev/null; then
  echo "FAIL: project CLAUDE.md key fields not filled (Project / Intent owner)"; fail=1
else
  echo "PASS: project CLAUDE.md key header fields filled"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: Inception-Done gate not satisfied in '$DIR'"; exit 1; fi
echo "OK: Inception-Done gate satisfied in '$DIR'"
exit 0
```

- [ ] **Step 2: Test against a passing fixture, then a failing one**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
chmod +x conformance/inception-done.sh
fx=$(mktemp -d)
mkdir -p "$fx/.claude" "$fx/.github/workflows" "$fx/docs/architecture"
: > "$fx/ENGINEERING-PRINCIPLES.md"; : > "$fx/RUNBOOK.md"; : > "$fx/BACKLOG.md"
: > "$fx/.github/workflows/ci.yml"; : > "$fx/docs/architecture/ADR-000-stack.md"
printf '**Project:** DemoApp\n**Intent owner:** Jane\n' > "$fx/CLAUDE.md"
sh conformance/inception-done.sh "$fx"; echo "pass-exit=$?"
rm "$fx/RUNBOOK.md"
sh conformance/inception-done.sh "$fx"; echo "fail-exit=$?"
rm -rf "$fx"
```
Expected: first run all `PASS`, `OK: ...`, `pass-exit=0`; second run `FAIL missing: RUNBOOK.md`, `fail-exit=1`.

- [ ] **Step 3: Commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git add conformance/inception-done.sh
git commit -m "feat: add inception-done.sh conformance check (the Inception gate)"
```

---

### Task 4: scripts/incept.sh (the bootstrap)

**Files:**
- Create: `scripts/incept.sh`

- [ ] **Step 1: Write the bootstrap script**

Create `scripts/incept.sh` with exactly this content:

```sh
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
sedi() { sed -i.bak "$@" && rm -f "${@: -1}.bak" 2>/dev/null || true; }  # portable in-place

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
```

- [ ] **Step 2: Syntax check**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
chmod +x scripts/incept.sh
sh -n scripts/incept.sh && echo "syntax OK"
```
Expected: `syntax OK`.

- [ ] **Step 3: Bootstrap a temp copy and verify (the real test)**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
tmp=$(mktemp -d)
git archive HEAD | tar -x -C "$tmp"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoApp --intent-owner "CI Bot" --stack typescript-node --backlog md )
echo "--- inception-done on temp project ---"
sh conformance/inception-done.sh "$tmp"; echo "exit=$?"
echo "--- post-conditions ---"
test -f "$tmp/ENGINEERING-PRINCIPLES.md" && echo "renamed OK"
grep -q "DemoApp" "$tmp/CLAUDE.md" && echo "project CLAUDE stamped"
grep -q "ENGINEERING-PRINCIPLES.md" "$tmp/DEVELOPMENT-STANDARDS.md" && echo "standards ref rewritten"
grep -q "The authoritative checklist is in \*\*\`CLAUDE.md\`\*\*" "$tmp/DEVELOPMENT-STANDARDS.md" && echo "STALE REF REMAINS (fail)" || echo "no stale principles ref in standards"
test -f "$tmp/.github/workflows/ci.yml" && echo "CI wired"
echo "--- re-run must refuse ---"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name X --intent-owner Y ); echo "rerun-exit=$?"
rm -rf "$tmp"
```
Expected: `inception-done` all PASS + `exit=0`; `renamed OK`; `project CLAUDE stamped`; `standards ref rewritten`; `no stale principles ref in standards`; `CI wired`; re-run prints the "already incepted" error with `rerun-exit=1`.

If any sed left a stale principles reference or a placeholder unfilled, fix the corresponding `sed` expression in `incept.sh` (the strings must match the current doc wording) and re-run. Do NOT edit the kit's own docs — the canonical kit keeps `CLAUDE.md` as principles; only the temp copy is transformed.

- [ ] **Step 4: Commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git add scripts/incept.sh
git commit -m "feat: add incept.sh Inception bootstrap (rename + stamp + CI wire)"
```

---

### Task 5: conformance/README index + CI bootstrap job

**Files:**
- Modify: `conformance/README.md`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Index inception-done.sh**

In `conformance/README.md`, find this exact line:

```
| `agent-autonomy.sh` | script | `DEVELOPMENT-PROCESS.md` §13 (autonomy tiers) — guard denies a tier breach | PreToolUse hook / CI |
```

Replace with:

```
| `agent-autonomy.sh` | script | `DEVELOPMENT-PROCESS.md` §13 (autonomy tiers) — guard denies a tier breach | PreToolUse hook / CI |
| `inception-done.sh` | script | `DEVELOPMENT-PROCESS.md` §3 / `START-HERE.md` (the Inception gate) | CI (bootstrap-into-temp) |
```

- [ ] **Step 2: Add the bootstrap job to kit CI**

In `.github/workflows/ci.yml`, find this exact block (the end of the `conformance` job's last step):

```
      - name: Agent-autonomy guard conformance (§13)
        run: sh conformance/agent-autonomy.sh
```

Replace with:

```
      - name: Agent-autonomy guard conformance (§13)
        run: sh conformance/agent-autonomy.sh

  bootstrap:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bootstrap a temp project and verify Inception-Done
        run: |
          tmp=$(mktemp -d)
          git archive HEAD | tar -x -C "$tmp"
          ( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoApp --intent-owner "CI" --stack typescript-node --backlog md )
          sh conformance/inception-done.sh "$tmp"
```

- [ ] **Step 3: Verify YAML + local equivalence**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'YAML OK'"
grep -c "inception-done.sh" conformance/README.md
```
Expected: `YAML OK`; `1`.

- [ ] **Step 4: Commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git add conformance/README.md .github/workflows/ci.yml
git commit -m "feat: index inception-done + add CI bootstrap-into-temp job"
```

---

### Task 6: VERSION + CHANGELOG + ROADMAP (2.2.0)

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Overwrite `VERSION` with exactly one line + trailing newline:

```
2.2.0
```

- [ ] **Step 2: Add the 2.2.0 CHANGELOG entry**

In `CHANGELOG.md`, find this exact line:

```
## [2.1.0] - 2026-06-06
```

Insert IMMEDIATELY BEFORE it:

```
## [2.2.0] - 2026-06-06

Slice 3 — Inception bootstrap. One command turns a cloned kit into a configured project. Absorbs the template work (RUNBOOK + flow-board BACKLOG); roadmap collapses 6→5.

### Added
- `scripts/incept.sh` — in-place Inception bootstrap (interactive + `--noninteractive`). At adoption it renames the principles doc `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` (freeing the project memory slot), rewrites the principles-sense references, stamps the project `CLAUDE.md`/`RUNBOOK.md`/`BACKLOG.md`/`ADR-000`, and wires the profile's CI. Prints the judgment steps it does not automate.
- `templates/RUNBOOK-TEMPLATE.md` — cold-resume runbook (setup/deploy/rollback/RPO-RTO).
- `conformance/inception-done.sh` — verifies the Inception-Done gate; kit CI bootstraps a temp project and asserts it passes.

### Changed
- `templates/BACKLOG-TEMPLATE.md` — rewritten from the stale phase/PROGRESS model to the §6 flow-board (states, work-item fields, ordering, work types, tech-debt paydown).
- `.github/workflows/ci.yml` — new `bootstrap` job (incept-into-temp → inception-done).
- `docs/ROADMAP-KIT.md` — Slice 3 done; roadmap 6→5 (template work absorbed).

### Note
The canonical kit stays **un-incepted** (principles remain in `CLAUDE.md`, which also serves as the kit's own memory). The `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename is an **adoption-time transform performed by `incept.sh`**, not a change to the kit's own layout.

```

- [ ] **Step 3: Add the 2.2.0 link reference**

In `CHANGELOG.md`, find:

```
[2.1.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.1.0
```

Replace with:

```
[2.2.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.2.0
[2.1.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.1.0
```

- [ ] **Step 4: Mark Slice 3 done in the roadmap**

In `docs/ROADMAP-KIT.md`, find this exact line:

```
| 3 | **Inception bootstrap** | START-HERE 8-step gate | `init` script: scaffold structure, CI, stamped project `CLAUDE.md`/`RUNBOOK`/`BACKLOG` | Inception-Done checklist, automated |
```

Replace with:

```
| 3 ✅ | **Inception bootstrap** *(shipped v2.2.0; absorbed templates)* | START-HERE 8-step gate | `scripts/incept.sh` + `RUNBOOK-TEMPLATE.md` + flow-board `BACKLOG-TEMPLATE.md` | `conformance/inception-done.sh` |
```

Then find this exact line (the former Slice 4 row):

```
| 4 | **Template fixes** | DoD + process §6 | rewrite `BACKLOG-TEMPLATE.md` to the flow-board model; add `RUNBOOK-TEMPLATE.md` | `conformance/template-lint` — placeholders filled, matches §6 |
```

Replace with:

```
| ~~4~~ | **Template fixes** *(absorbed into Slice 3, v2.2.0)* | DoD + process §6 | RUNBOOK-TEMPLATE.md + flow-board BACKLOG-TEMPLATE.md shipped | covered by `inception-done.sh` |
```

- [ ] **Step 5: Verify and commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
cat VERSION
grep -c "## \[2.2.0\]" CHANGELOG.md
grep -c "shipped v2.2.0" docs/ROADMAP-KIT.md
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "release: 2.2.0 — Slice 3 Inception bootstrap (changelog + roadmap)"
```
Expected: `2.2.0`; `1`; `1`.

---

### Task 7: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Full conformance sweep (the kit itself is unchanged & still green)**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/typescript-node/ci.yml >/dev/null && echo "ci-gates OK"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "check-links OK"
test -f conformance/15-factor-checklist.md && echo "15-factor present"
echo "--- kit's own CLAUDE.md is STILL the principles doc (not renamed) ---"
grep -q "Engineering Principles & Definition of Done" CLAUDE.md && echo "kit CLAUDE.md unchanged (principles)"
test -f ENGINEERING-PRINCIPLES.md && echo "UNEXPECTED: kit was incepted" || echo "kit not incepted (correct)"
```
Expected: all OK lines; `kit CLAUDE.md unchanged (principles)`; `kit not incepted (correct)`.

- [ ] **Step 2: End-to-end bootstrap (same as CI) passes locally**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoApp --intent-owner "CI" --stack typescript-node --backlog md ) >/dev/null
sh conformance/inception-done.sh "$tmp" >/dev/null && echo "bootstrap → inception-done OK"
# the bootstrapped project's CI workflow itself satisfies §14
sh conformance/ci-gates.sh "$tmp/.github/workflows/ci.yml" >/dev/null && echo "bootstrapped CI satisfies §14"
rm -rf "$tmp"
```
Expected: `bootstrap → inception-done OK`; `bootstrapped CI satisfies §14`.

- [ ] **Step 2b: Guard does not block this slice's flow**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
for c in "git push -u origin feature/slice-3-inception-bootstrap" "git mv a b" "gh pr create --fill"; do
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$c" | sh .claude/hooks/guard.sh 2>/dev/null | grep -q deny && echo "DENY: $c" || echo "ALLOW: $c"
done
```
Expected: all `ALLOW`.

- [ ] **Step 3: Push and open the PR**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git push -u origin feature/slice-3-inception-bootstrap
gh pr create --title "Slice 3: Inception bootstrap — incept.sh + templates + inception-done (v2.2.0)" --body "$(cat <<'EOF'
## Summary
One command turns a cloned kit into a configured, Inception-complete project.

- **`scripts/incept.sh`** — in-place bootstrap (interactive + `--noninteractive`). At adoption: renames principles `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` (frees the project memory slot) and rewrites the principles-sense references; stamps the project `CLAUDE.md`/`RUNBOOK.md`/`BACKLOG.md`/`ADR-000`; wires the profile CI; prints the judgment steps it won't automate.
- **Templates absorbed:** new `RUNBOOK-TEMPLATE.md`; `BACKLOG-TEMPLATE.md` rewritten to the §6 flow-board. (Roadmap 6→5.)
- **Conformance** `conformance/inception-done.sh`; kit CI `bootstrap` job copies the kit to a temp dir, runs incept non-interactively, and asserts the gate passes — never transforming the kit itself.
- **Release** 2.2.0 (MINOR).

## Design note (template-repo principle)
The canonical kit stays **un-incepted** — principles remain in `CLAUDE.md`. The rename to `ENGINEERING-PRINCIPLES.md` is an **adoption-time transform** done by `incept.sh`, because a template is never itself an instance (a fresh clone must instantiate cleanly, and CI must be able to bootstrap a copy).

## Ratification
`incept.sh` rewrites governing-doc references at adoption (verified via bootstrap-into-temp). Adds tooling + templates. **Human ratification required before merge.**

Spec: `docs/superpowers/specs/2026-06-06-slice3-inception-bootstrap-design.md`
Plan: `docs/superpowers/plans/2026-06-06-slice3-inception-bootstrap.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: branch pushed; PR URL printed; kit CI starts (now with conformance + docs-links + bootstrap jobs).

- [ ] **Step 4: Report CI status, stop for ratification**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
sleep 15
gh pr checks 2>&1 | head
```
Do **not** merge. Report PR URL + CI results.

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 deliverables all mapped — incept.sh→T4, RUNBOOK template→T1, BACKLOG rewrite→T2, inception-done→T3, conformance index + CI bootstrap→T5, VERSION/CHANGELOG/ROADMAP→T6, validation/PR→T7. Spec §4.4 reference-transform is implemented inside incept.sh (T4 step 1) and verified by T4 step 3 (no stale principles ref) — note the resolved decision: the kit is NOT renamed; only the adoption transform renames, so there is no kit-wide sweep task. Spec §5 validation (bootstrap-into-temp, safety re-run refuses, templates lint, kit still green) is in T4/T7.

**Placeholder scan:** no TBD/TODO; all file bodies complete; the `[...]` tokens in the RUNBOOK/BACKLOG/PROJECT templates are intentional fill-in placeholders.

**Type/name consistency:** the rename target `ENGINEERING-PRINCIPLES.md` is identical across incept.sh seds (T4), inception-done.sh (T3), and verification (T4/T7). `conformance/inception-done.sh` path consistent across T3/T5/T7. The CI `bootstrap` job (T5) uses the same `git archive | tar` + incept + inception-done invocation as the local test (T4 step 3 / T7 step 2). The seds in T4 target the exact doc strings captured from the current kit (DEVELOPMENT-STANDARDS §9/§12/§14, DEVELOPMENT-PROCESS §line-9, README doc-set row, START-HERE orient line, MAINTAINING contract trio, PROJECT-CLAUDE-TEMPLATE inherited-standards pointer) — all principles-sense; project-sense `CLAUDE.md` references are deliberately left unchanged.
