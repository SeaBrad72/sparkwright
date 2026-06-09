# Slice 7d — Work-Tracking Adapter Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the kit's named backlog backends from "named but figure-it-out-yourself" to documented adapters with a concrete, contract-anchored mapping recipe — add Azure DevOps + GitLab to the named set, and lock the set against drift — guidance only, no integration code.

**Architecture:** A new mapping guide (`docs/work-tracking/adapters.md`) maps six engineering trackers against the same §6-contract template (State map · Field map · Atomic claim · Fit notes) + a bring-your-own recipe. Existing surfaces are wired to it (§6 table, `incept.sh --backlog`, project template). A new `conformance/backlog-adapters.sh` fail-closed check asserts the three surfaces (incept flag set · §6 · guide) agree on the named set, so "named ≠ supported" drift can't recur.

**Tech Stack:** Markdown; POSIX `sh` (conformance + incept). No application code, no new required CI gate.

**Spec:** `docs/superpowers/specs/2026-06-08-slice7d-work-tracking-design.md` (approved). **Branch:** `feature/slice-7d-work-tracking` (created; spec committed). **Version target:** 2.16.0 (MINOR).

---

## Governance & conventions (read before any task)
- Feature branch → PR → **human ratification**. Agents never self-merge. Governing-doc change (§6) → Security-Owner lens.
- **Guard hazard:** the live `.claude/` PreToolUse guard scans **Bash command text** for destructive literals. Commit messages here are pre-vetted clean. File contents written via Write/Edit are not scanned.
- **The canonical named set (one source of truth):** `md · github · jira · ado · linear · gitlab`. It appears as: the `incept.sh` `--backlog` set (short tokens), the §6 table (display names), and the guide section headings (display names). The mapping token→display: `md→BACKLOG.md · github→GitHub · jira→Jira · ado→Azure DevOps · linear→Linear · gitlab→GitLab`. `backlog-adapters.sh` enforces all three agree.
- **No integration code:** `incept.sh` still only scaffolds `BACKLOG.md`; other choices record + point at the guide.

---

### Task 1: The mapping guide — `docs/work-tracking/adapters.md`

**Files:**
- Create: `docs/work-tracking/adapters.md`

- [ ] **Step 1: Write the guide**

Create `docs/work-tracking/adapters.md` with EXACTLY:

````markdown
# Work-Tracking Adapter Guide

How to make a work-tracker satisfy the kit's **backlog contract** (`../../DEVELOPMENT-PROCESS.md` §6). This is **guidance, not integration code** — the kit ships no API client; it ships the mapping you apply once when you adopt a tracker.

## The contract every adapter must satisfy

`DEVELOPMENT-PROCESS.md` §6 defines a backend-agnostic work-item model. An adapter is conformant when it expresses all three:

1. **States** — `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
2. **Required fields** — title · intent (why) · acceptance criteria · size (one-flow small) · risk/complexity · owner (human or agent) · links (spec / PR / milestone).
3. **Atomic claim** — entering **In Progress** is a race-safe single-owner change: no two agents grab the same item. This is the property the kit's multi-agent loop depends on; it is the load-bearing part of every map below.

Each tracker is mapped against the same four headings: **State map · Field map · Atomic claim · Fit notes**.

---

## BACKLOG.md (default, reference)

The repo-native backend (`../../templates/BACKLOG-TEMPLATE.md`). Every other adapter is measured against it.

- **State map** — the six states are `##` section headings; an item is a table row under its current state's heading. Moving the row to a new section = a state change.
- **Field map** — table columns map 1:1: Item→title · Intent→intent · Acceptance criteria→acceptance · Size · Risk · Type · Owner · Links.
- **Atomic claim** — moving a row into **In Progress** is a git commit. Git is the lock: a second agent racing the same claim hits a merge conflict / rejected non-fast-forward push, so exactly one wins. The claim is durable and auditable in history.
- **Fit notes** — zero setup, agent-readable, travels with the repo. Weak for large orgs, cross-repo portfolios, notifications, or dashboards — graduate to a hosted tracker when those matter.

## GitHub (Issues + Projects)

- **State map** — a Projects (v2) board **Status** field with columns for the six states; `Blocked` as a Status value or a `blocked` label.
- **Field map** — issue title→title · body→intent + acceptance · Project custom fields (single-select) for Size and Risk · labels for type · Assignees→owner · `Closes #`/PR links auto-associate.
- **Atomic claim** — assign the issue to exactly one agent **and** set Status→In Progress. Convention: an agent claims only if Assignees is empty, then assigns itself. The assignment is observable but last-writer-wins, so the empty-check-before-claim is what makes it safe.
- **Fit notes** — best-in-class native PR linkage; Projects v2 fields are flexible. The claim is convention-enforced (no server-side guard) — for heavy multi-agent use, gate on "assignee empty" and re-read after assigning.

## Jira (Atlassian)

- **State map** — the project **workflow statuses** map to the six (rename/add statuses to match); `Blocked` as a status or the built-in flag.
- **Field map** — Summary→title · Description→intent + acceptance (or a dedicated Acceptance Criteria field) · a **Size** select custom field · a **Risk** custom field · Assignee→owner · the development panel auto-links branches/commits/PRs. Do **not** map Size to Story Points used for velocity — the kit forbids estimation-as-forecast (`DEVELOPMENT-PROCESS.md` §1).
- **Atomic claim** — Assignee + a workflow **transition** to In Progress, guarded by a condition (only the assignee may transition). Jira transitions are server-side atomic — this is a genuine race-safe claim, the strongest of the hosted options.
- **Fit notes** — strongest workflow modeling and enterprise governance; real transactional claim via transition conditions. Heavyweight; resist the Story-Points-as-size trap.

## Azure DevOps (Boards)

- **State map** — the work-item **State** field / Board columns map to the six (e.g. New→Backlog, Approved→Ready, Active→In Progress, Resolved→In Review, Closed→Done; add a Released state via process customization). `Blocked` via a tag or the Blocked field.
- **Field map** — Title→title · Description→intent · the built-in **Acceptance Criteria** field→acceptance · a Size custom field · Tags for risk/type · Assigned To→owner · native branch/commit/PR linking.
- **Atomic claim** — Assigned To + State→Active; the State change is server-side. Enforce single-assignee; claim only when Assigned To is empty.
- **Fit notes** — native PR/branch linkage and a built-in Acceptance Criteria field that maps cleanly; strong in Microsoft/.NET shops. Matching all six states may need process customization.

## Linear

- **State map** — workflow **states** (Backlog, Todo, In Progress, In Review, Done) map to the six; add a **Released** state or treat Done as Released+Done explicitly; `Blocked` via a label or a blocked-by relation.
- **Field map** — title · description→intent + acceptance · the **estimate** field→size · labels for risk/type · Assignee→owner · GitHub/GitLab sync auto-links PRs and can auto-advance state on PR open.
- **Atomic claim** — Assignee + state→In Progress; Linear's per-issue updates are transactional. Single-assignee convention; the Git sync moving the item on PR open can serve as a corroborating signal.
- **Fit notes** — fast, developer-native, excellent Git sync. Opinionated state model — map Released deliberately. SaaS-only (no self-host).

## GitLab (Issues / Boards)

- **State map** — GitLab issues are natively open/closed, so model the six states with **scoped labels** (`workflow::ready`, `workflow::in-progress`, `workflow::in-review`, …) as board lists; `Blocked` via a scoped label or a blocking-issue link.
- **Field map** — title · description→intent + acceptance · scoped labels for size/risk/type · Assignee→owner · native MR/commit linking (`Closes #`).
- **Atomic claim** — Assignee + set the `workflow::in-progress` scoped label. **Scoped labels are mutually exclusive** — setting one removes the prior `workflow::*` — which gives a clean single-state guarantee; combined with assignee-empty-before-claim this is race-safe in practice.
- **Fit notes** — scoped labels yield clean mutually-exclusive states; native MR linkage; **self-hostable** (key for regulated / air-gapped enterprises). Board state lives in labels rather than a first-class field.

---

## Bring your own tracker

Any tracker works if it satisfies the three contract points:

1. **States** — map its statuses to the six (+ Blocked).
2. **Fields** — map the seven required fields to its fields/labels/custom fields.
3. **Atomic claim** — find a **race-safe** single-owner transition. Prefer a server-side transition (Jira) or a mutually-exclusive state primitive (GitLab scoped labels). If your tool has **no** race-safe primitive, document a compensating convention — single-assignee + check-assignee-empty-before-claim + a short claim TTL — **and record the residual risk** that two agents could still double-claim. Do not pretend the gap is closed; the kit's multi-agent safety depends on naming it.

> General PM tools (Asana, Monday, ClickUp) can be mapped via this recipe, but they lack a race-safe claim primitive and native PR/commit linkage — treat the atomic-claim and traceability caveats above as binding before using one as a multi-agent backlog.
````

- [ ] **Step 2: Verify links resolve**

Run: `sh conformance/check-links.sh`
Expected: exit 0 (`OK: all relative Markdown links resolve`). The guide links to `../../DEVELOPMENT-PROCESS.md` and `../../templates/BACKLOG-TEMPLATE.md` — both resolve from `docs/work-tracking/`.

- [ ] **Step 3: Confirm all six section headings are present (the drift-lock will require these)**

Run:
```bash
for h in "BACKLOG.md" "GitHub" "Jira" "Azure DevOps" "Linear" "GitLab"; do
  grep -qE "^## .*$h" docs/work-tracking/adapters.md && echo "OK: $h" || echo "MISSING: $h"
done
```
Expected: `OK:` for all six.

- [ ] **Step 4: Commit**

```bash
git add docs/work-tracking/adapters.md
git commit -m "feat(work-tracking): contract-anchored adapter guide (6 trackers + BYO recipe)"
```

---

### Task 2: Wire §6 to the guide — `DEVELOPMENT-PROCESS.md`

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` §6 (the "Backend adapters" table + a guide pointer)

The current §6 table (locate by content) is:
```markdown
| Backend | When |
|---------|------|
| **`BACKLOG.md`** (repo-native) | **Default.** Zero setup, travels with the repo, directly agent-readable. Created at Inception/Plan. |
| GitHub Issues + Projects | GitHub-centric teams |
| Linear | Teams already in Linear |
| Atlassian / Jira | Enterprise/Jira shops |
```
And the sentence after it: `The loop, gates, and retros are identical regardless of backend — only storage swaps. An adapter must satisfy the contract: the states above, the required fields, and atomic claiming.`

- [ ] **Step 1: Replace the table with the six-tracker version**

Replace the four-row table above with:
```markdown
| Backend | When |
|---------|------|
| **`BACKLOG.md`** (repo-native) | **Default.** Zero setup, travels with the repo, directly agent-readable. Created at Inception/Plan. |
| GitHub Issues + Projects | GitHub-centric teams |
| Jira (Atlassian) | Enterprise / Jira shops |
| Azure DevOps Boards | Microsoft / .NET shops |
| Linear | Teams already in Linear |
| GitLab Issues / Boards | GitLab shops; self-hosted / regulated |
```

- [ ] **Step 2: Add the guide pointer**

Replace the sentence `The loop, gates, and retros are identical regardless of backend — only storage swaps. An adapter must satisfy the contract: the states above, the required fields, and atomic claiming.` with:
```markdown
The loop, gates, and retros are identical regardless of backend — only storage swaps. An adapter must satisfy the contract: the states above, the required fields, and atomic claiming. **Per-tracker mappings** (state map · field map · atomic claim · fit notes) for each named backend, plus a "bring your own tracker" recipe, are in `docs/work-tracking/adapters.md`. General PM tools (Asana/Monday/ClickUp) are intentionally not named here — they lack a race-safe atomic-claim primitive; use the bring-your-own recipe with its caveats.
```

- [ ] **Step 3: Verify links + no regression**

Run: `sh conformance/check-links.sh`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "feat(process): §6 names ADO + GitLab; points at the adapter guide (contract unchanged)"
```

---

### Task 3: Extend `incept.sh --backlog` to the six trackers

**Files:**
- Modify: `scripts/incept.sh` (usage comment line ~7; arg-parse `--help` usage line ~24; interactive prompt line ~48; add a canonical `BACKLOG_BACKENDS` set + validation; extend the non-md note ~91)

- [ ] **Step 1: Add the canonical backends set near the other defaults**

Find the line (near the top, ~line 15):
```sh
STACK="${INCEPT_STACK:-typescript-node}"; BACKLOG="${INCEPT_BACKLOG:-md}"; INTERACTIVE=1
```
Immediately AFTER it, add:
```sh
# Canonical named backlog backends (one source of truth — conformance/backlog-adapters.sh
# asserts this set agrees with DEVELOPMENT-PROCESS.md §6 and docs/work-tracking/adapters.md).
BACKLOG_BACKENDS="md github jira ado linear gitlab"
```

- [ ] **Step 2: Update the usage comment (~line 7)**

Replace:
```sh
#                        [--backlog md|github|linear|jira] [--noninteractive]
```
with:
```sh
#                        [--backlog md|github|jira|ado|linear|gitlab] [--noninteractive]
```

- [ ] **Step 3: Update the `--help` usage string (~line 24)**

Replace `[--backlog md|github|linear|jira]` inside the `-h|--help)` echo with `[--backlog md|github|jira|ado|linear|gitlab]`. The full line becomes:
```sh
    -h|--help) echo "usage: incept.sh [--name N] [--intent-owner O] [--stack S] [--backlog md|github|jira|ado|linear|gitlab] [--noninteractive]"; exit 0 ;;
```

- [ ] **Step 4: Update the interactive prompt (~line 48)**

Replace:
```sh
  printf 'Backlog backend (md/github/linear/jira) [%s]: ' "$BACKLOG"; read -r _b || true; [ -n "${_b:-}" ] && BACKLOG="$_b"
```
with:
```sh
  printf 'Backlog backend (md/github/jira/ado/linear/gitlab) [%s]: ' "$BACKLOG"; read -r _b || true; [ -n "${_b:-}" ] && BACKLOG="$_b"
```

- [ ] **Step 5: Validate the chosen backend after inputs are collected**

Find the input-validation block (after the interactive section, ~line 50-51):
```sh
[ -n "$NAME" ]  || { echo "error: --name required" >&2; exit 2; }
[ -n "$OWNER" ] || { echo "error: --intent-owner required" >&2; exit 2; }
```
Immediately AFTER those two lines, add:
```sh
case " $BACKLOG_BACKENDS " in *" $BACKLOG "*) : ;; *) echo "error: unknown --backlog '$BACKLOG' (one of: $BACKLOG_BACKENDS)" >&2; exit 2 ;; esac
```

- [ ] **Step 6: Extend the non-md note to point at the guide (~line 91)**

Replace:
```sh
  *)  echo "note: backlog backend '$BACKLOG' selected — declare it in CLAUDE.md §3; no BACKLOG.md created." ;;
```
with:
```sh
  *)  echo "note: backlog backend '$BACKLOG' selected — declare it in CLAUDE.md §3 and map it via docs/work-tracking/adapters.md; no BACKLOG.md created." ;;
```

- [ ] **Step 7: Verify the script still parses and validates**

Run:
```bash
sh -n scripts/incept.sh && echo "syntax OK"
grep -q 'BACKLOG_BACKENDS="md github jira ado linear gitlab"' scripts/incept.sh && echo "set OK"
```
Expected: `syntax OK` and `set OK`. (Do NOT execute `incept.sh` itself — it mutates the repo; the kit root is intentionally un-incepted and the script would refuse anyway, but `sh -n` is the safe check.)

- [ ] **Step 8: Commit**

```bash
git add scripts/incept.sh
git commit -m "feat(incept): --backlog accepts md|github|jira|ado|linear|gitlab + validates; guide pointer"
```

---

### Task 4: Project template — `PROJECT-CLAUDE-TEMPLATE.md` §3

**Files:**
- Modify: `templates/PROJECT-CLAUDE-TEMPLATE.md:47`

- [ ] **Step 1: Update the backlog-backend config line**

Replace line 47:
```markdown
- **Backlog backend** (§6): [`BACKLOG.md` / GitHub Issues+Projects / Linear / Jira] — [link]
```
with:
```markdown
- **Backlog backend** (§6): [`BACKLOG.md` / GitHub Issues+Projects / Jira / Azure DevOps / Linear / GitLab] — [link] (mapping: `docs/work-tracking/adapters.md`)
```

- [ ] **Step 2: Verify links + inception conformance unaffected**

Run: `sh conformance/check-links.sh`
Expected: exit 0. (`docs/work-tracking/adapters.md` is inline code, not a checked link, in this template — projects copy it; confirm the script stays green.)

- [ ] **Step 3: Commit**

```bash
git add templates/PROJECT-CLAUDE-TEMPLATE.md
git commit -m "feat(templates): project backlog config names six backends + guide pointer"
```

---

### Task 5: Drift-lock conformance check — `conformance/backlog-adapters.sh`

**Files:**
- Create: `conformance/backlog-adapters.sh`

The check asserts the canonical named set appears in all three surfaces. It iterates a `token|display` table via a **here-document** (NOT a pipe) so `fail` accumulates in the current shell.

- [ ] **Step 1: Write the check**

Create `conformance/backlog-adapters.sh` with EXACTLY:

```sh
#!/bin/sh
# backlog-adapters.sh — drift lock for the named backlog backends (slice 7d).
#
# The named set must agree across THREE surfaces, or "named ≠ supported" drift
# creeps back in:
#   1. scripts/incept.sh           — the BACKLOG_BACKENDS set (short tokens)
#   2. DEVELOPMENT-PROCESS.md §6    — the backend table (display names)
#   3. docs/work-tracking/adapters.md — one section heading per tracker
# Fail-closed: exit 1 if any surface is missing a named tracker. Stack-neutral,
# zero-dependency. Run at the Review gate (DEVELOPMENT-PROCESS.md §7).
set -eu

INCEPT="scripts/incept.sh"
PROC="DEVELOPMENT-PROCESS.md"
GUIDE="docs/work-tracking/adapters.md"

for f in "$INCEPT" "$PROC" "$GUIDE"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done

# incept's canonical set line (single source in the script)
backends=$(grep -E '^BACKLOG_BACKENDS=' "$INCEPT" | head -1)
# the §6 backend-table region only (avoid false matches elsewhere in the doc)
proc6=$(awk '/^## 6\. Work Items/{f=1} f{print} /^## 7\./{f=0}' "$PROC")

fail=0
# token | display-name pattern (display used in §6 + guide headings)
while IFS='|' read -r token pat; do
  [ -n "$token" ] || continue
  case " $backends " in
    *"$token"*) : ;;
    *) echo "FAIL: $INCEPT BACKLOG_BACKENDS missing '$token'"; fail=1 ;;
  esac
  printf '%s\n' "$proc6" | grep -q "$pat" || { echo "FAIL: $PROC §6 backend table missing '$pat'"; fail=1; }
  grep -qE "^## .*$pat" "$GUIDE" || { echo "FAIL: $GUIDE missing a section heading for '$pat'"; fail=1; }
done <<'EOF'
md|BACKLOG\.md
github|GitHub
jira|Jira
ado|Azure DevOps
linear|Linear
gitlab|GitLab
EOF

if [ "$fail" -ne 0 ]; then
  echo "backlog-adapters: FAIL — the named set drifted across surfaces" >&2
  exit 1
fi
echo "backlog-adapters: OK (incept set, §6 table, and the adapter guide name the same six backends)"
```

- [ ] **Step 2: Executable + POSIX syntax**

Run:
```bash
chmod +x conformance/backlog-adapters.sh
sh -n conformance/backlog-adapters.sh && echo "syntax OK"
command -v dash >/dev/null 2>&1 && dash -n conformance/backlog-adapters.sh && echo "dash OK" || echo "(dash absent)"
```
Expected: `syntax OK` (+ `dash OK` if present).

- [ ] **Step 3: Positive run — all three surfaces agree**

Run: `sh conformance/backlog-adapters.sh; echo "exit=$?"`
Expected: `backlog-adapters: OK (...)` and `exit=0`. (Depends on Tasks 1–3 being done; run after them.)

- [ ] **Step 4: NEGATIVE TEST — prove it's not vacuous**

Temporarily drop `gitlab` from the incept set, confirm FAIL, restore:
```bash
cp scripts/incept.sh /tmp/incept.7d.bak
sed 's/BACKLOG_BACKENDS="md github jira ado linear gitlab"/BACKLOG_BACKENDS="md github jira ado linear"/' /tmp/incept.7d.bak > scripts/incept.sh
sh conformance/backlog-adapters.sh; echo "mutated-exit=$?"
cp /tmp/incept.7d.bak scripts/incept.sh
sh conformance/backlog-adapters.sh >/dev/null 2>&1; echo "restored-exit=$?"
grep -q 'BACKLOG_BACKENDS="md github jira ado linear gitlab"' scripts/incept.sh && echo "incept restored"
```
Expected: mutated run prints `FAIL: scripts/incept.sh BACKLOG_BACKENDS missing 'gitlab'` and `mutated-exit=1`; `restored-exit=0`; `incept restored`. If the mutation does NOT fail, STOP and report BLOCKED (the lock is vacuous).

- [ ] **Step 5: Commit**

```bash
git add conformance/backlog-adapters.sh
git commit -m "feat(conformance): backlog-adapters drift lock (incept set = §6 = guide), fail-closed"
```

---

### Task 6: Conformance README — list the new check (and fix the 7c omission)

**Files:**
- Modify: `conformance/README.md` (Index table)

The Index table currently ends with the `audit-evidence-checklist.md` row. Note `container-supply-chain.sh` (shipped in 7c) is **missing** from the index — add it too while here.

- [ ] **Step 1: Add both rows**

In `conformance/README.md`, find the `audit-evidence-checklist.md` row in the Index table:
```markdown
| `audit-evidence-checklist.md` | checklist | enterprise addendum (`../docs/enterprise/`) — per-control audit evidence | Review / pre-audit |
```
Immediately AFTER it, insert:
```markdown
| `container-supply-chain.sh` | script | `DEVELOPMENT-STANDARDS.md` §14 (conditional container image supply-chain) | Review (conditional on a Dockerfile) |
| `backlog-adapters.sh` | script | `DEVELOPMENT-PROCESS.md` §6 (named backends agree across incept / §6 / the adapter guide) | CI / Review |
```

- [ ] **Step 2: Verify links**

Run: `sh conformance/check-links.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add conformance/README.md
git commit -m "docs(conformance): index backlog-adapters.sh + container-supply-chain.sh (7c omission)"
```

---

### Task 7: Version, CHANGELOG, ROADMAP + full sweep

**Files:**
- Modify: `VERSION` (`2.15.0` → `2.16.0`)
- Modify: `CHANGELOG.md`
- Modify: `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the sole contents of `VERSION` with:
```
2.16.0
```

- [ ] **Step 2: CHANGELOG block**

Insert after the `Format: …` line (and its blank line), before `## [2.15.0]`:
```markdown
## [2.16.0] - 2026-06-08

Slice 7d — Work-tracking adapter guidance. Fourth sub-slice of Slice 7. Lifts named backlog backends from "named" to "documented adapter."

### Added
- **`docs/work-tracking/adapters.md`** — contract-anchored mapping guide: per-tracker **state map · field map · atomic claim · fit notes** for `BACKLOG.md`, GitHub, Jira, **Azure DevOps**, Linear, **GitLab**, plus a "bring your own tracker" recipe. Guidance only — no integration code.
- **`conformance/backlog-adapters.sh`** — fail-closed drift lock: the named set must agree across `incept.sh --backlog`, `DEVELOPMENT-PROCESS.md` §6, and the guide.

### Changed
- `DEVELOPMENT-PROCESS.md` §6 names six backends (adds Azure DevOps + GitLab) and points at the guide; the §6 contract (states/fields/atomic-claim) is unchanged.
- `scripts/incept.sh` `--backlog` accepts `md|github|jira|ado|linear|gitlab`, validates the choice, and points non-`md` choices at the guide (still scaffolds only `BACKLOG.md`).
- `templates/PROJECT-CLAUDE-TEMPLATE.md` §3 names the six backends + the guide.
- `conformance/README.md` indexes `backlog-adapters.sh` and `container-supply-chain.sh` (the latter a 7c index omission).

### Note
MINOR (2.16.0): no new required CI gate, no integration code. General PM tools (Asana/Monday/ClickUp) are intentionally excluded from the named set — they lack a race-safe atomic-claim primitive; the bring-your-own recipe covers them with caveats.

```

- [ ] **Step 3: ROADMAP row**

In `docs/ROADMAP-KIT.md`, after the `7c ✅` row, insert:
```markdown
| 7d ✅ | **Work-tracking adapters** *(shipped v2.16.0)* | process §6 | `docs/work-tracking/adapters.md` (6 trackers + BYO) + incept `--backlog` set + template | `backlog-adapters.sh` + `check-links.sh` |
```

- [ ] **Step 4: Full conformance sweep**

Run:
```bash
sh conformance/check-links.sh && \
sh conformance/profile-completeness.sh && \
sh conformance/agent-autonomy.sh && \
sh conformance/container-supply-chain.sh && \
sh conformance/backlog-adapters.sh && \
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" || break; done && \
echo "ALL GREEN"
```
Expected: `ALL GREEN`. (Exclude `inception-done.sh` — exits 1 against the kit root by design.) If any check fails, STOP and report BLOCKED with the output.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.16.0 — work-tracking adapter guidance (7d)"
```

---

### Task 8: Final review + open PR (stop for ratification)

- [ ] **Step 1: Push**

```bash
git push -u origin feature/slice-7d-work-tracking
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Slice 7d — Work-tracking adapter guidance (v2.16.0)" --body "$(cat <<'EOF'
## Summary
Lifts named backlog backends from "named" to "documented adapter." A contract-anchored mapping guide (`docs/work-tracking/adapters.md`) maps six engineering trackers (BACKLOG.md · GitHub · Jira · **Azure DevOps** · Linear · **GitLab**) against the §6 contract — state map · field map · **atomic claim** · fit notes — plus a bring-your-own recipe. Guidance only, no integration code. v2.16.0 (MINOR).

- §6 names the six + points at the guide (contract unchanged).
- `incept.sh --backlog` accepts + validates the six; scaffolds only `md`.
- `conformance/backlog-adapters.sh` — fail-closed drift lock: incept set = §6 = guide (negative-tested).

## Design intent
The **atomic-claim** mapping is load-bearing (multi-agent safety): each tracker states its exact race-safe claim mechanism, and the BYO recipe tells adopters whose tool lacks one to document a compensating convention + residual risk rather than pretend. General PM tools are excluded from the named set for exactly this reason (no race-safe claim, no native PR linkage).

## Governance
Governing-doc change (§6) → Security-Owner lens. Agent did not self-merge; awaiting human ratification.

## Conformance
check-links · profile-completeness · agent-autonomy · container-supply-chain · backlog-adapters (negative-tested) · ci-gates ×10 — all green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: STOP**

Report the PR URL and stop. Do not merge — Bradley ratifies (governing-doc change). Slice complete when the PR is open and green.

---

## Notes for the executor
- **Dependency order:** Task 5's positive run (Step 3) and Task 7's sweep depend on Tasks 1–3 existing (the three surfaces). Run Task 5 after 1–3. Tasks 2, 3, 4, 6 are otherwise independent edits.
- **The drift lock is the slice's point:** Task 5's negative test (drop a tracker → must FAIL) is mandatory evidence it isn't vacuous — the bug 7d fixes is "named ≠ supported," so the lock must actually catch divergence.
- **No integration code:** if any task tempts you to add an API client or sync logic, stop — 7d is guidance only.
- **Guard caution:** commit messages are pre-vetted clean; if reworded, avoid literal destructive command strings.
- **Do not touch** `.claude/`, `guard.sh`, `agent-autonomy.sh`, profiles, or any `ci.yml` — 7d changes none of them.
