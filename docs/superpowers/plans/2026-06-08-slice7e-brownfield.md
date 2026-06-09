# Slice 7e — Brownfield Adoption & `.claude/` Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the kit safely adoptable into an existing repo (brownfield) without clobbering the adopter's `.claude/`, document `.claude/` scoping, and enforce the runtime guard's liveness via a fail-closed conformance check wired into the Inception gate.

**Architecture:** A new `conformance/guard-wired.sh` (fail-closed) verifies the `.claude/` PreToolUse guard is actually wired; `inception-done.sh` calls it so no project passes Inception with a dead guard. A threat-model-first `docs/adoption/brownfield.md` documents the copy-in + `.claude/` MERGE policy; README documents `.claude/` scoping (project vs global); `incept.sh` warns (never modifies) on an un-wired `.claude/`.

**Tech Stack:** POSIX `sh` (conformance + incept), Markdown. No application code, no new universally-required CI gate.

**Spec:** `docs/superpowers/specs/2026-06-08-slice7e-brownfield-design.md` (approved). **Branch:** `feature/slice-7e-brownfield` (created; spec committed). **Version target:** 2.17.0 (MINOR).

---

## Governance & conventions (read before any task)
- Feature branch → PR → **human ratification**. Agents never self-merge. Governing surface + a security check → Security-Owner lens.
- **Guard hazard:** the live `.claude/` PreToolUse guard scans Bash command text for destructive literals. Commit messages are pre-vetted clean. File contents written via Write/Edit are not scanned. The negative tests below rename/restore files with `mv`/`cp` — never `rm`.
- **Do-no-harm core:** nothing in this slice may auto-modify a `.claude/`. `incept.sh` only *warns*; the merge is human-performed per the doc.
- **The kit's own guard is wired** (`.claude/settings.json` registers `sh "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh"` under PreToolUse), so `guard-wired.sh` PASSes at the kit root.

---

### Task 1: `conformance/guard-wired.sh` — the fail-closed guard-liveness check

**Files:**
- Create: `conformance/guard-wired.sh`

- [ ] **Step 1: Write the check**

Create `conformance/guard-wired.sh` with EXACTLY:

```sh
#!/bin/sh
# guard-wired.sh — verify the agent runtime guard is ACTUALLY active in a project.
#
# The kit's runtime safety rests on the .claude/ PreToolUse guard hook. This check
# fails closed if the guard isn't wired, so a project — especially a brownfield repo
# with prod credentials already configured — cannot run agents unprotected. Run
# anytime; also invoked by inception-done.sh (the Inception gate).
# See docs/adoption/brownfield.md.
set -eu

DIR="${1:-.}"
S="$DIR/.claude/settings.json"
H="$DIR/.claude/hooks/guard.sh"
fail=0

if [ ! -f "$S" ]; then
  echo "FAIL: $S missing — no .claude/ settings to register the guard"; fail=1
elif ! grep -q 'PreToolUse' "$S" || ! grep -qE '"command".*guard\.sh' "$S"; then
  # require guard.sh inside a "command" value (an actually-invoked hook), not a stray
  # mention elsewhere in the JSON — closes a false-pass on a guard.sh reference in prose.
  echo "FAIL: $S does not register the guard (need a PreToolUse hook whose command runs guard.sh)"; fail=1
else
  echo "PASS: guard registered as a PreToolUse hook in settings.json"
fi

if [ ! -f "$H" ]; then
  echo "FAIL: $H missing — the guard hook script is absent"; fail=1
elif ! sh -n "$H" 2>/dev/null; then
  echo "FAIL: $H is not a valid sh script"; fail=1
else
  echo "PASS: guard hook present and parses"
fi

if [ "$fail" -ne 0 ]; then
  echo "guard-wired: FAIL — the runtime guard is NOT active; agents would run unprotected (see docs/adoption/brownfield.md)" >&2
  exit 1
fi
echo "guard-wired: OK (PreToolUse guard hook registered and present)"
exit 0
```

- [ ] **Step 2: Executable + POSIX syntax (sh + dash)**

```bash
chmod +x conformance/guard-wired.sh
sh -n conformance/guard-wired.sh && echo "syntax OK"
command -v dash >/dev/null 2>&1 && dash -n conformance/guard-wired.sh && echo "dash OK" || echo "(dash absent)"
```
Expected: `syntax OK` (+ `dash OK` if present).

- [ ] **Step 3: Positive run — guard is wired at the kit root**

Run: `sh conformance/guard-wired.sh; echo "exit=$?"`
Expected: two `PASS:` lines, `guard-wired: OK (...)`, `exit=0`.

- [ ] **Step 4: NEGATIVE TEST (mandatory, proves non-vacuous) — simulate an un-wired guard in a temp copy**

```bash
TMP=$(mktemp -d)
mkdir -p "$TMP/.claude/hooks"
# settings WITHOUT a guard registration:
printf '{ "permissions": { "allow": [] } }\n' > "$TMP/.claude/settings.json"
cp .claude/hooks/guard.sh "$TMP/.claude/hooks/guard.sh"
sh conformance/guard-wired.sh "$TMP"; echo "unwired-exit=$?"
# now wire it and confirm it passes:
printf '{ "hooks": { "PreToolUse": [ { "hooks": [ { "command": "sh .claude/hooks/guard.sh" } ] } ] } }\n' > "$TMP/.claude/settings.json"
sh conformance/guard-wired.sh "$TMP"; echo "wired-exit=$?"
echo "(leave $TMP — it is a mktemp throwaway the OS reclaims; do NOT run rm -rf, the live guard blocks it)"
```
Expected: the un-wired run prints `FAIL: … does not register the guard …` and `unwired-exit=1`; the wired run prints `guard-wired: OK` and `wired-exit=0`. If the un-wired case does NOT exit 1, STOP and report BLOCKED — the check is vacuous. **Do not clean up with `rm -rf`** — the active `.claude/` guard denies it; the `mktemp` dir is a throwaway the OS reclaims.

- [ ] **Step 5: Commit**

```bash
git add conformance/guard-wired.sh
git commit -m "feat(conformance): guard-wired — fail-closed check the runtime guard is actually active"
```

---

### Task 2: Wire guard-liveness into the Inception gate

**Files:**
- Modify: `conformance/inception-done.sh` (after the `need .claude` line)

- [ ] **Step 1: Add the guard-liveness assertion**

In `conformance/inception-done.sh`, find this block:
```sh
need ENGINEERING-PRINCIPLES.md
need CLAUDE.md
need RUNBOOK.md
need .claude
need .github/workflows/ci.yml
```
Immediately AFTER the `need .github/workflows/ci.yml` line, insert:
```sh

# the guard must be WIRED, not just present (slice 7e; docs/adoption/brownfield.md)
if [ -f conformance/guard-wired.sh ] && sh conformance/guard-wired.sh . >/dev/null 2>&1; then
  echo "PASS: runtime guard wired (PreToolUse → guard.sh)"
else
  echo "FAIL: runtime guard not wired — run: sh conformance/guard-wired.sh"; fail=1
fi
```

> Note: `inception-done.sh` does `cd "$DIR"` near the top, so `conformance/guard-wired.sh` resolves relative to the project root being checked (where `conformance/` is copied in). The kit's own guard is wired, so this line PASSes at the kit root — `inception-done.sh` still fails overall there for the pre-existing reasons (ADR-000/RUNBOOK/etc.), unchanged.

- [ ] **Step 2: Verify — kit root: guard line PASSes; gate still fails for pre-existing reasons**

Run: `sh conformance/inception-done.sh 2>&1 | grep -E "runtime guard|Inception-Done"`
Expected: `PASS: runtime guard wired (PreToolUse → guard.sh)` and `FAIL: Inception-Done gate not satisfied in '.'` (the overall gate still fails at the kit root for the pre-existing missing-ADR/RUNBOOK reasons — that's expected and unchanged).

- [ ] **Step 3: Verify the gate FAILs when the guard is unwired (fixture)**

```bash
TMP=$(mktemp -d); cd "$TMP"
# minimal project that satisfies the OTHER inception checks but has NO guard:
touch ENGINEERING-PRINCIPLES.md RUNBOOK.md BACKLOG.md
printf '**Project:** x\n**Intent owner:** y\n' > CLAUDE.md
mkdir -p .claude .github/workflows docs/architecture; touch .github/workflows/ci.yml docs/architecture/ADR-000-stack.md
printf '{ "permissions": {} }\n' > .claude/settings.json   # guard NOT registered
mkdir -p conformance; cp "$OLDPWD/conformance/guard-wired.sh" conformance/
sh "$OLDPWD/conformance/inception-done.sh" . 2>&1 | grep -E "runtime guard"
cd "$OLDPWD"
echo "(leave $TMP — mktemp throwaway; do NOT rm -rf, the live guard blocks it)"
```
Expected: `FAIL: runtime guard not wired — run: sh conformance/guard-wired.sh`. (Confirms the gate catches a dead guard.) **Do not clean up with `rm -rf`** — the active guard denies it; the `mktemp` dir is OS-reclaimed.

- [ ] **Step 4: Commit**

```bash
git add conformance/inception-done.sh
git commit -m "feat(conformance): Inception-Done gate now requires a WIRED guard (not just .claude/ present)"
```

---

### Task 3: Index `guard-wired.sh` in the conformance README

**Files:**
- Modify: `conformance/README.md` (Index table)

- [ ] **Step 1: Add the row**

In `conformance/README.md`, find the `backlog-adapters.sh` row in the Index table:
```markdown
| `backlog-adapters.sh` | script | `DEVELOPMENT-PROCESS.md` §6 (named backends agree across incept / §6 / the adapter guide) | CI / Review |
```
Immediately AFTER it, insert:
```markdown
| `guard-wired.sh` | script | `DEVELOPMENT-PROCESS.md` §13 — the `.claude/` runtime guard is actually wired (fail-closed; gates Inception) | CI / Inception |
```

- [ ] **Step 2: Verify links**

Run: `sh conformance/check-links.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add conformance/README.md
git commit -m "docs(conformance): index guard-wired.sh"
```

---

### Task 4: `docs/adoption/brownfield.md` — threat-model-first adoption path

**Files:**
- Create: `docs/adoption/brownfield.md`

- [ ] **Step 1: Write the doc**

Create `docs/adoption/brownfield.md` (create `docs/adoption/` as needed) with EXACTLY:

````markdown
# Brownfield Adoption — Bringing the Kit into an Existing Repo

Greenfield adoption (starting a new repo *from* the kit) is covered by `../../START-HERE.md`. This guide is for **brownfield**: layering the kit onto an existing repo that already has code, history, and possibly its own `.claude/`.

## ⚠️ Read this first — the risk

The kit's runtime safety is the **`.claude/` PreToolUse guard** (`.claude/hooks/guard.sh`, registered in `.claude/settings.json`). It blocks destructive/irreversible agent actions (`../../DEVELOPMENT-PROCESS.md` §13).

Brownfield **inverts the kit's risk gradient.** A greenfield repo starts empty and safe; a legacy repo already has `.env` files, cloud credentials, and kube contexts wired up. If you adopt the kit's *process* but skip the `.claude/` **merge** — so the guard isn't actually registered — you get **agents operating on a live system with real production reach and no runtime protection**, while believing you have the kit's safety. That is worse than not adopting the kit.

**Before any agent runs in this repo, verify the guard is live:**

```sh
sh conformance/guard-wired.sh
```

It must print `guard-wired: OK`. If it FAILs, the guard is not wired — fix the merge below first. (The Inception gate, `conformance/inception-done.sh`, also enforces this.)

## When to use this guide

- **Greenfield** (new/empty repo): start from the kit, run `sh scripts/incept.sh`. Use `../../START-HERE.md`.
- **Brownfield** (existing repo with code): follow this guide. You **copy the kit in** and **merge** `.claude/` rather than starting from the kit.

## 1. Copy the kit in

Bring these into your repo root (adapt, don't blindly overwrite):

- Governing docs: `ENGINEERING-PRINCIPLES.md` (the kit's principles `CLAUDE.md`, renamed), `DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`, `MAINTAINING.md`.
- `profiles/`, `conformance/`, `templates/`, `docs/`, `scripts/`.
- `.github/workflows/ci.yml` (from your chosen `profiles/<stack>/ci.yml`) — **merge** with any existing CI; don't drop your pipeline.
- `.claude/` — **merge, never overwrite** (next section).

If your repo has its own root `CLAUDE.md`, keep it as your *project* `CLAUDE.md` and bring the kit's principles in as `ENGINEERING-PRINCIPLES.md` (the name the kit uses post-Inception).

## 2. The `.claude/` MERGE policy (do-no-harm core)

If your repo already has a `.claude/`, **do not overwrite it.** Keep your hooks and settings; **add** the kit's guard:

1. Copy `.claude/hooks/guard.sh` into your `.claude/hooks/` (keep your existing hooks).
2. In your `.claude/settings.json`, **add** the kit's PreToolUse guard hook (merge into any existing `hooks.PreToolUse` array — don't replace it):

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash|Write|Edit|NotebookEdit",
      "hooks": [
        { "type": "command", "command": "sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\"" }
      ]
    }
  ]
}
```

3. Leave `.claude/settings.local.json` alone — it is **gitignored** (personal, per-developer). Do not copy the kit's over yours.
4. Verify: `sh conformance/guard-wired.sh` → must be `guard-wired: OK`.

> The kit does **not** script this merge: a merge bug could clobber exactly the hooks we're protecting. The merge is human-performed; `guard-wired.sh` verifies the result.

## 3. Inception (adapted)

`scripts/incept.sh` is the **greenfield** bootstrap — it renames the kit's root `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps fresh project artifacts, which assumes you started *from* the kit. In a brownfield repo you do the Inception **judgment** steps by hand (`../../START-HERE.md` steps 1–7): write the charter, record the stack as **ADR-000**, instantiate the project `CLAUDE.md` from `../../templates/PROJECT-CLAUDE-TEMPLATE.md`, start `RUNBOOK.md`, pick a backlog backend (`work-tracking/adapters.md`), assign roles.

Then run the gate:

```sh
sh conformance/inception-done.sh
```

It now checks that the **runtime guard is wired** (not just that `.claude/` exists), so you cannot pass Inception with a dead guard.

## 4. Residual gaps (be honest about these)

The guard is necessary, not sufficient:

- **Pattern coverage.** `guard.sh` matches *common* destructive verbs. Your legacy repo may have **bespoke destructive tooling** (`make nuke-db`, a homegrown deploy/migration script) the patterns don't recognize. Extend `.claude/hooks/guard.sh` with your repo's destructive commands, and re-run `sh conformance/agent-autonomy.sh` after editing.
- **Runtime scope.** The guard covers only the **Claude Code runtime**. Humans at a shell and other agent runtimes are **not** covered — and a legacy system is more likely to have other automation/people holding prod access. The **platform backstop is Org-owned** and matters *more* here because the blast radius pre-exists: production IAM, separate prod accounts/credentials, and deploy approvals (`../enterprise/README.md` — the human-coverage boundary). The kit's guard reduces agent risk; it does not replace platform controls.
````

- [ ] **Step 2: Verify links resolve**

Run: `sh conformance/check-links.sh`
Expected: exit 0. The doc links `../../START-HERE.md`, `../../DEVELOPMENT-PROCESS.md`, `../../templates/PROJECT-CLAUDE-TEMPLATE.md`, `work-tracking/adapters.md` (sibling under `docs/`), and `../enterprise/README.md` — all resolve from `docs/adoption/`.

- [ ] **Step 3: Commit**

```bash
git add docs/adoption/brownfield.md
git commit -m "docs(adoption): threat-model-first brownfield path + .claude/ merge policy"
```

---

### Task 5: `README.md` — `.claude/` scoping section

**Files:**
- Modify: `README.md` (after the "Quickstart (drop-in & go)" section)

- [ ] **Step 1: Insert the scoping section**

In `README.md`, find the end of the `## Quickstart (drop-in & go)` section — the line:
```markdown
4. Pass the **Inception Done** gate → enter the loop at **Discover**.
```
Immediately AFTER it (before `## How the kit is built`), insert:
```markdown

## Where `.claude/` lives (scoping)

The kit ships a project-level **`.claude/`** (the `guard.sh` PreToolUse hook + `settings.json`). It is **scoped to this repo only** — it governs Claude Code within this repository's tree and does **not** touch your global `~/.claude/` or your machine.

- `.claude/settings.json` — committed **team policy** (registers the guard; permission allow/ask/deny).
- `.claude/settings.local.json` — **gitignored** personal per-developer overrides; never committed.

Dropping the kit into a repo affects only that repo. Adopting into an **existing** repo that already has its own `.claude/`? Follow `docs/adoption/brownfield.md` — **merge**, never overwrite, and verify with `sh conformance/guard-wired.sh`.
```

- [ ] **Step 2: Verify links**

Run: `sh conformance/check-links.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): .claude/ scoping (project vs global) + brownfield pointer"
```

---

### Task 6: `START-HERE.md` — brownfield row → guide

**Files:**
- Modify: `START-HERE.md` (the persona-router brownfield row)

- [ ] **Step 1: Update the brownfield row**

In `START-HERE.md`, find the router row:
```markdown
| **Engineer — existing repo (brownfield)** | adapt the numbered steps below to your existing repo | a dedicated brownfield path is planned |
```
Replace it with:
```markdown
| **Engineer — existing repo (brownfield)** | **`docs/adoption/brownfield.md`** (copy-in + `.claude/` merge + guard verify) | then the Inception judgment steps below |
```

- [ ] **Step 2: Verify links**

Run: `sh conformance/check-links.sh`
Expected: exit 0. (`docs/adoption/brownfield.md` is referenced as inline code, consistent with the other router cells; confirm green.)

- [ ] **Step 3: Commit**

```bash
git add START-HERE.md
git commit -m "docs(start-here): brownfield router row points at the adoption guide"
```

---

### Task 7: `scripts/incept.sh` — warn (never modify) on an un-wired `.claude/`

**Files:**
- Modify: `scripts/incept.sh` (after the safety-guards block)

- [ ] **Step 1: Add the warning**

In `scripts/incept.sh`, find the safety-guards block:
```sh
# --- safety guards ---
[ -f ENGINEERING-PRINCIPLES.md ] && { echo "error: ENGINEERING-PRINCIPLES.md exists — already incepted. Aborting." >&2; exit 1; }
{ [ -f CLAUDE.md ] && grep -q "Engineering Principles & Definition of Done" CLAUDE.md; } || {
  echo "error: not an un-incepted Agentic SDLC Kit (principles CLAUDE.md not found). Aborting." >&2; exit 1; }
```
Immediately AFTER that block, insert:
```sh

# brownfield safety: warn (never modify) if a .claude/ exists without the kit guard wired.
if [ -f .claude/settings.json ] && ! grep -q 'guard\.sh' .claude/settings.json; then
  echo "warning: .claude/settings.json present but the kit guard is not registered." >&2
  echo "         If this is an existing repo, MERGE .claude/ per docs/adoption/brownfield.md" >&2
  echo "         (add, do not overwrite) before running agents. Continuing without touching .claude/." >&2
fi
```

- [ ] **Step 2: Verify syntax (sh + dash) + the warning logic**

```bash
sh -n scripts/incept.sh && echo "syntax OK"
command -v dash >/dev/null 2>&1 && dash -n scripts/incept.sh && echo "dash OK" || echo "(dash absent)"
# the kit's own settings DO register guard.sh, so grep finds it (warning would NOT fire here):
grep -q 'guard\.sh' .claude/settings.json && echo "kit guard registered (warning suppressed in greenfield)"
```
Expected: `syntax OK`, (`dash OK`), `kit guard registered (warning suppressed in greenfield)`. DO NOT execute `incept.sh` (it mutates the repo and would refuse anyway).

- [ ] **Step 3: Commit**

```bash
git add scripts/incept.sh
git commit -m "feat(incept): warn on an un-wired/foreign .claude/ (never modifies it)"
```

---

### Task 8: Version, CHANGELOG, ROADMAP + full sweep

**Files:**
- Modify: `VERSION` (`2.16.0` → `2.17.0`); `CHANGELOG.md`; `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the sole contents of `VERSION` with:
```
2.17.0
```

- [ ] **Step 2: CHANGELOG block**

Insert after the `Format: …` line (and its blank line), before `## [2.16.0]`:
```markdown
## [2.17.0] - 2026-06-08

Slice 7e — Brownfield adoption & `.claude/` hygiene. Fifth sub-slice of Slice 7. Makes the kit safely adoptable into an existing repo and enforces that the runtime guard is actually wired.

### Added
- **`conformance/guard-wired.sh`** — fail-closed check that the `.claude/` PreToolUse guard is actually registered and present. **Wired into `inception-done.sh`**, so no project (greenfield or brownfield) passes Inception with a dead guard.
- **`docs/adoption/brownfield.md`** — threat-model-first brownfield path: copy-in steps, the `.claude/` **merge** policy (add the guard, never overwrite), Inception adapted, and honest residual gaps (pattern coverage + the Org-owned platform backstop).
- **`README.md` `.claude/` scoping** — project-level vs global `~/.claude/`; `settings.json` (committed) vs `settings.local.json` (gitignored). Dropping the kit affects only that repo, not the machine.

### Changed
- `conformance/inception-done.sh` now requires the guard to be **wired**, not just `.claude/` present.
- `scripts/incept.sh` **warns** (never modifies) when a `.claude/` without the kit guard is detected, pointing at the brownfield merge guide.
- `START-HERE.md` brownfield router row points at the adoption guide; `conformance/README.md` indexes `guard-wired.sh`.

### Note
MINOR (2.17.0): no new universally-required CI gate, no integration code, no breaking change. Brownfield inverts the kit's risk gradient (a legacy repo's blast radius pre-exists), so the guard-liveness check is the enforcement teeth behind the merge guidance.

```

- [ ] **Step 3: ROADMAP row**

In `docs/ROADMAP-KIT.md`, after the `7d ✅` row, insert:
```markdown
| 7e ✅ | **Brownfield & `.claude/` hygiene** *(shipped v2.17.0)* | process §13 (guard) | `docs/adoption/brownfield.md` + `.claude/` scoping + incept warn | `guard-wired.sh` (gates Inception) + `check-links.sh` |
```

- [ ] **Step 4: Full conformance sweep**

Run:
```bash
sh conformance/check-links.sh && \
sh conformance/profile-completeness.sh && \
sh conformance/agent-autonomy.sh && \
sh conformance/container-supply-chain.sh && \
sh conformance/backlog-adapters.sh && \
sh conformance/guard-wired.sh && \
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" || break; done && \
echo "ALL GREEN"
```
Expected: `ALL GREEN`. (Exclude `inception-done.sh` — exits 1 against the kit root by design; the guard line within it PASSes, but the gate fails for the pre-existing ADR/RUNBOOK reasons.) If any check fails, STOP and report BLOCKED.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.17.0 — brownfield adoption & .claude/ hygiene (7e)"
```

---

### Task 9: Final review + open PR (stop for ratification)

- [ ] **Step 1: Push**

```bash
git push -u origin feature/slice-7e-brownfield
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Slice 7e — Brownfield adoption & .claude/ hygiene (v2.17.0)" --body "$(cat <<'EOF'
## Summary
Makes the kit safely adoptable into an existing repo and turns "the guard is active" from a recommendation into a fail-closed conformance check. v2.17.0 (MINOR).

- **`conformance/guard-wired.sh`** — fail-closed: asserts the `.claude/` PreToolUse guard is registered and present; **wired into `inception-done.sh`** so no project passes Inception with a dead guard. Negative-tested.
- **`docs/adoption/brownfield.md`** — threat-model-first: the risk of a silently-inactive guard on a legacy system (prod creds pre-wired), copy-in steps, the `.claude/` **merge** policy (add the guard, never overwrite), Inception adapted, honest residual gaps + Org-owned backstop.
- **README `.claude/` scoping** — project-level vs global; committed `settings.json` vs gitignored `settings.local.json`.
- **`incept.sh`** warns (never modifies) on an un-wired `.claude/`.

## Why guard-liveness is enforced, not documented
Brownfield inverts the kit's risk gradient: a legacy repo already has prod reach wired up, so adopting agentic work with an un-merged (inactive) guard is the worst case. The recommendation is therefore backed by a check that fails closed and gates Inception — the same "make it a conformance check" move the kit uses for every safety property.

## Do-no-harm
Nothing auto-modifies a `.claude/`: `incept.sh` only warns; the merge is human-performed; `guard-wired.sh` verifies the result. No copy/adopt script.

## Governance
Governing surface (§13 guard) + a security check → Security-Owner lens. Agent did not self-merge; awaiting human ratification.

## Conformance
check-links · profile-completeness · agent-autonomy · container-supply-chain · backlog-adapters · guard-wired (negative-tested) · ci-gates ×10 — all green. No new universal gate (MINOR).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: STOP**

Report the PR URL and stop. Do not merge — Bradley ratifies (governing surface + security check). Slice complete when the PR is open and green.

---

## Notes for the executor
- **Dependency order:** Task 2 (inception-done wiring) depends on Task 1 (guard-wired.sh existing). Task 8's sweep depends on all prior. Tasks 3–7 are independent edits.
- **The guard-liveness check is the slice's point:** Task 1 Step 4's negative test (un-wired settings → exit 1) is mandatory evidence it isn't vacuous — the whole slice exists to stop an inactive guard on a live legacy system.
- **Do-no-harm is absolute here:** no task may auto-edit a `.claude/`. `incept.sh` only warns. Negative tests build `mktemp` throwaway dirs and **do not delete them** — the active `.claude/` guard denies recursive deletes (and the OS reclaims `mktemp` paths). Never use a recursive-delete command in any step; restore repo files with `cp`/`mv` from backups if needed.
- **Do not touch** `guard.sh` itself, `agent-autonomy.sh`, profiles, or any `ci.yml` — 7e changes none of them.
