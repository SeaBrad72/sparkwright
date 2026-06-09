# Slice 8a — Incident Response standard + blameless postmortem template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Append an Incident Response standard (§15) to `DEVELOPMENT-STANDARDS.md`, ship a blameless `POSTMORTEM-TEMPLATE.md`, fix the two dangling `DEVELOPMENT-PROCESS.md` cross-references, and wire the artifact-flow + audit-evidence + doc-set mentions — closing gap A1.

**Architecture:** Docs-only slice. No executable code, so "tests" are the kit's own **conformance checks** (`check-links.sh`, `ci-gates.sh`, etc.) plus targeted `grep` assertions that prove (a) the dangling refs are gone, (b) §15 exists, (c) the template exists with all sections. TDD adapts to: assert the *current* (broken/absent) state, make the edit, assert the *fixed* state. The §15 section is **appended** after §14 — no renumbering of §1–§14 (which are cross-referenced kit-wide).

**Tech Stack:** Markdown; POSIX `sh` conformance scripts; `git`.

**Spec:** `docs/superpowers/specs/2026-06-09-slice8a-incident-response-design.md`

---

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `DEVELOPMENT-STANDARDS.md` | Universal quality bar | **Append** §15 Incident Response (after §14, before the closing "Remember" block) |
| `templates/POSTMORTEM-TEMPLATE.md` | Blameless postmortem artifact | **Create** |
| `DEVELOPMENT-PROCESS.md` | Process/flow | Repoint 2 dangling refs (lines 212, 225) + artifact-flow Postmortem row (line 412) |
| `conformance/audit-evidence-checklist.md` | Per-control audit evidence | Add Incident-response row (after Observability, line 32) |
| `CLAUDE.md` | Doc-set table | Add `POSTMORTEM` to templates row (line 17) |
| `README.md` | What's inside | Add `POSTMORTEM` to templates row (line 23) |
| `VERSION` | Kit version | `2.18.0` → `2.19.0` |
| `CHANGELOG.md` | Change history | New 2.19.0 entry |
| `docs/ROADMAP-KIT.md` | Kit backlog | Add 8a row |

**Note on §14 placement:** `DEVELOPMENT-STANDARDS.md` ends with §14 (CI/CD) followed by a horizontal rule and a closing italic "**Remember:** this is the *universal* bar…" block. §15 must be inserted **between the end of §14's content and that closing `---` / Remember block** so the closing note stays last.

---

### Task 1: Append §15 Incident Response to DEVELOPMENT-STANDARDS.md

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (insert §15 before the final `---` + "Remember" block, currently near the end of the file)

- [ ] **Step 1: Assert the section does not yet exist (failing test)**

Run:
```bash
grep -n "## 15. Incident Response" DEVELOPMENT-STANDARDS.md; echo "exit=$?"
```
Expected: no match, `exit=1` (the section is absent — this is the gap).

- [ ] **Step 2: Locate the insertion point**

Run:
```bash
grep -n "Remember:\*\* this is the \*universal\* bar" DEVELOPMENT-STANDARDS.md
```
Expected: one match (the closing block). §15 is inserted **above** the `---` that precedes this line. Confirm the lines just before it are the end of §14 (the `deploy-prod` reference + "Required reviewers…" paragraph).

- [ ] **Step 3: Insert the §15 section**

Insert the following block immediately **before** the `---` line that precedes the closing "**Remember:** this is the *universal* bar…" block. The exact text to insert (a leading blank line, the section, then a trailing blank line so the existing `---` still separates it from the Remember block):

```markdown
## 15. Incident Response

How a production incident is declared, commanded, resolved, and learned from. Aligns with **NIST SP 800-61** (computer-security incident handling) and SRE incident-management practice. This section owns *response to an incident*; *continuity and recovery planning* (backup/restore drills, RTO/RPO, BIA) lives with your RUNBOOK DR section and §10. The kit standardizes the **practice and artifacts**; incident **tooling** (paging, on-call rotation, status page) and the human on-call program are **Org-owned** — named here, wired to your platform.

### Severity

The same P0–P3 ladder the Operate triage step routes on (`DEVELOPMENT-PROCESS.md` §9):

| Severity | Declare when | Response |
|----------|--------------|----------|
| **P0 — critical** | Production down · data loss · security breach · safety / children's-audience exposure | All-hands; declare immediately |
| **P1 — high** | Major feature broken or significant user impact, no full outage | Urgent; declare |
| **P2 — medium** | Degraded or partial; a workaround exists | Handle in-hours |
| **P3 — low** | Minor / cosmetic | Scheduled fix |

### Roles (functions, not titles)

One person may hold several on a small team — these are functions, not headcount.

- **Incident commander** — owns the response; the only role that changes the declared severity and authorizes mitigations. **A human commands**; **agents assist** — detect, correlate, summarize, draft the timeline, propose mitigations. Irreversible production actions are human-authorized (`DEVELOPMENT-PROCESS.md` §13 guard + autonomy tiers).
- **Comms lead** — stakeholder and status updates at a stated cadence.
- **Scribe** — keeps the timeline and records decisions as they happen.

### Response arc

```
detect → declare (severity + named commander)
       → stabilize / mitigate FIRST (flag-off · rollback — restore service before root-causing; DEVELOPMENT-PROCESS.md §10)
       → resolve
       → postmortem
```

### Postmortem (blameless)

Required for **P0/P1**, recommended for P2. Use `templates/POSTMORTEM-TEMPLATE.md`. The postmortem examines **systems and contributing factors, never individual blame**. Its action items **route back into the loop** — backlog items (`DEVELOPMENT-PROCESS.md` §6) or recurring-maintenance (`DEVELOPMENT-PROCESS.md` §15) with an owner and due date — so the incident teaches the next iteration (the loop closes; `CLAUDE.md` principle 6).
```

- [ ] **Step 4: Assert the section now exists and §14 was not renumbered**

Run:
```bash
grep -n "## 15. Incident Response" DEVELOPMENT-STANDARDS.md && \
grep -n "## 14. CI/CD Pipeline" DEVELOPMENT-STANDARDS.md && \
grep -c "## 16\." DEVELOPMENT-STANDARDS.md
```
Expected: §15 matches; §14 still present (unrenumbered); `## 16.` count is `0`. Also confirm the "Remember: …universal bar" block is still the **last** content:
```bash
tail -3 DEVELOPMENT-STANDARDS.md
```
Expected: the closing "Remember" paragraph (NOT the §15 table).

- [ ] **Step 5: Run link check (no broken internal refs introduced)**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`. (All §15 refs — §9, §10, §6, §13, §15 of PROCESS; §10 of STANDARDS; the template path — resolve. The template path resolves only after Task 2; if check-links validates file paths and runs before Task 2, expect it to flag `templates/POSTMORTEM-TEMPLATE.md` — in that case run this step's link check after Task 2. See note below.)

> **Ordering note:** `templates/POSTMORTEM-TEMPLATE.md` is referenced by §15 but created in Task 2. If `check-links.sh` validates relative file links, run the full link check at the END of Task 2, not here. Within Task 1, Step 5 may instead just confirm no *other* link broke: `sh conformance/check-links.sh 2>&1 | grep -v "POSTMORTEM-TEMPLATE" ; echo done`.

- [ ] **Step 6: Commit**

```bash
git add DEVELOPMENT-STANDARDS.md
git commit -m "feat(standards): add §15 Incident Response (append, no renumber)

Severity matrix P0-P3, roles-as-functions, response arc, blameless
postmortem requirement routing action items back into the loop.
NIST 800-61 anchor; incident tooling named Org-owned.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Create templates/POSTMORTEM-TEMPLATE.md

**Files:**
- Create: `templates/POSTMORTEM-TEMPLATE.md`

- [ ] **Step 1: Assert the template does not exist (failing test)**

Run: `ls templates/POSTMORTEM-TEMPLATE.md 2>&1; echo "exit=$?"`
Expected: "No such file", `exit` non-zero.

- [ ] **Step 2: Create the template**

Create `templates/POSTMORTEM-TEMPLATE.md` with exactly this content (house style matches the sibling templates' guidance-blockquote voice):

```markdown
# [Incident Title] — Postmortem

> **Template.** A **blameless** postmortem for a production incident (required for P0/P1, recommended for P2 — see `DEVELOPMENT-STANDARDS.md` §15). It examines **systems and contributing factors, never individual blame**. The goal is durable learning: every action item routes back onto the board (`DEVELOPMENT-PROCESS.md` §6 / §15).

**Incident ID:** [id] · **Severity:** [P0 / P1 / P2 / P3] · **Date:** [date] · **Incident commander:** [name / role] · **Status:** [open / closed]

## How to use
- Fill every section in plain language; bullet points are fine.
- Times in UTC. Keep the timeline factual and chronological.
- Hand the finished file to the team and link each action item to its backlog entry.

---

## 1. Summary
> Two or three sentences: what happened, in plain language.

[...]

## 2. Impact
> Who and what was affected · duration (detect → resolve) · users or data affected · any SLA/SLO breach.

[...]

## 3. Timeline (UTC)
> The scribe's record: detected → declared → key mitigations → resolved.

| Time (UTC) | Event |
|------------|-------|
| [hh:mm] | [what happened] |

## 4. Root cause(s) & contributing factors
> The systems view ("5 whys" is a useful tool). **Blameless:** describe what in the system allowed this, not who.

[...]

## 5. Detection
> How we found out (alert · user report · telemetry) and how quickly. If detection lagged, say why.

[...]

## 6. What went well / what didn't
> Candid and system-focused. What helped the response; what got in the way.

[...]

## 7. Action items
> The loop-closing artifact. Each item has an owner, a due date, and a backlog link. Type: prevent (stop recurrence) · detect-faster · mitigate-faster.

| Action | Owner | Due | Backlog link | Type |
|--------|-------|-----|--------------|------|
| [action] | [owner] | [date] | [#id] | [prevent / detect-faster / mitigate-faster] |

## 8. Blameless statement
> This postmortem examines systems and processes, not people. We assume everyone acted with good intent and the information they had at the time.
```

- [ ] **Step 3: Assert the template exists with all required sections**

Run:
```bash
ls templates/POSTMORTEM-TEMPLATE.md && \
grep -cE "^## [1-8]\. " templates/POSTMORTEM-TEMPLATE.md
```
Expected: file listed; section count `8` (Summary, Impact, Timeline, Root cause, Detection, What went well/didn't, Action items, Blameless statement).

- [ ] **Step 4: Run the full link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0` — the §15 reference to `templates/POSTMORTEM-TEMPLATE.md` now resolves, and the template's own refs (`DEVELOPMENT-STANDARDS.md` §15, `DEVELOPMENT-PROCESS.md` §6/§15) resolve.

- [ ] **Step 5: Commit**

```bash
git add templates/POSTMORTEM-TEMPLATE.md
git commit -m "feat(templates): add blameless POSTMORTEM-TEMPLATE.md

Nine-section blameless postmortem (summary, impact, timeline, root
cause, detection, went well/didn't, action items, blameless statement).
Action items route back to the backlog per DEVELOPMENT-STANDARDS.md §15.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Repoint the two dangling PROCESS refs + artifact-flow row

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md:212` (Event-retro line)
- Modify: `DEVELOPMENT-PROCESS.md:225` (Operate Route line)
- Modify: `DEVELOPMENT-PROCESS.md:412` (artifact-flow Postmortem row)

- [ ] **Step 1: Assert the dangling refs currently exist (failing test)**

Run:
```bash
grep -n "Incident Response / postmortem procedure in \`DEVELOPMENT-STANDARDS.md\`" DEVELOPMENT-PROCESS.md
grep -n "escalate to Incident Response + postmortem (\`DEVELOPMENT-STANDARDS.md\`)" DEVELOPMENT-PROCESS.md
```
Expected: line 212 matches the first; line 225 matches the second. These point at a STANDARDS section that did not exist before Task 1 — the defect.

- [ ] **Step 2: Fix line 212**

Replace this exact text:
```
*Production* incidents follow Operate & Support (§9) and the Incident Response / postmortem procedure in `DEVELOPMENT-STANDARDS.md`.
```
with:
```
*Production* incidents follow Operate & Support (§9) and the Incident Response / postmortem standard in `DEVELOPMENT-STANDARDS.md` §15.
```

- [ ] **Step 3: Fix line 225**

Replace this exact text:
```
P0/P1 escalate to Incident Response + postmortem (`DEVELOPMENT-STANDARDS.md`).
```
with:
```
P0/P1 escalate to Incident Response + postmortem (`DEVELOPMENT-STANDARDS.md` §15).
```

- [ ] **Step 4: Fix the artifact-flow Postmortem row (line 412)**

Replace this exact row:
```
| Postmortem | Incident (P0/P1) | — | responder + human |
```
with:
```
| Postmortem (`templates/POSTMORTEM-TEMPLATE.md`) | Incident (P0/P1) | — | responder + human |
```

- [ ] **Step 5: Assert the dangling refs are gone and the new refs resolve**

Run:
```bash
grep -c "postmortem procedure in \`DEVELOPMENT-STANDARDS.md\`" DEVELOPMENT-PROCESS.md
grep -c "DEVELOPMENT-STANDARDS.md\` §15" DEVELOPMENT-PROCESS.md
grep -c "templates/POSTMORTEM-TEMPLATE.md" DEVELOPMENT-PROCESS.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `grep -c` → `0` (old dangling phrasing gone); second → `2` (both refs now cite §15); third → `1` (artifact-flow row links the template); `check-links.sh` `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "fix(process): repoint dangling incident-response refs to STANDARDS §15

Lines 212/225 cited a non-existent STANDARDS section; now point at
§15. Artifact-flow Postmortem row links the new template.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Add the Incident-response audit-evidence row

**Files:**
- Modify: `conformance/audit-evidence-checklist.md` (Security & engineering controls table, after the Observability row at line 32)

- [ ] **Step 1: Assert no incident-response row exists yet (failing test)**

Run: `grep -c "Incident response" conformance/audit-evidence-checklist.md; echo done`
Expected: `0`.

- [ ] **Step 2: Insert the row**

Insert this row immediately **after** the existing Observability row:
```
| Observability / monitoring | CC7.2 / A.8.15, A.8.16 | dashboards, alerts | Manual | |
```
The new row to add directly beneath it:
```
| Incident response · postmortem | CC7.3, CC7.4 / A.5.24–A.5.28 | postmortem record(s) (`templates/POSTMORTEM-TEMPLATE.md`) + action-item backlog links | Manual | |
```

- [ ] **Step 3: Assert the row exists and the table is intact**

Run:
```bash
grep -c "Incident response · postmortem" conformance/audit-evidence-checklist.md && \
grep -c "CC7.3, CC7.4 / A.5.24" conformance/audit-evidence-checklist.md
```
Expected: both `1`.

- [ ] **Step 4: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0` (the new row's template link resolves).

- [ ] **Step 5: Commit**

```bash
git add conformance/audit-evidence-checklist.md
git commit -m "docs(conformance): add incident-response audit-evidence row

CC7.3/7.4 / ISO A.5.24-A.5.28; Manual; evidence = postmortem records
plus action-item backlog links.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Add POSTMORTEM to the doc-set template mentions

**Files:**
- Modify: `CLAUDE.md:17` (document-set templates row)
- Modify: `README.md:23` (What's inside templates row)

- [ ] **Step 1: Assert POSTMORTEM is not yet listed (failing test)**

Run:
```bash
grep -n "PROJECT-CLAUDE\`, \`BACKLOG\`, \`RUNBOOK\`, \`FEATURE-REQUEST\`, \`SPEC\`" CLAUDE.md README.md
grep -c "POSTMORTEM" CLAUDE.md README.md
```
Expected: the first finds the templates row in both files; `POSTMORTEM` count `0` in each.

- [ ] **Step 2: Update CLAUDE.md line 17**

Replace this exact text (in `CLAUDE.md`):
```
Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`.
```
with:
```
Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`, `POSTMORTEM`.
```

- [ ] **Step 3: Update README.md line 23**

Replace this exact text (in `README.md`):
```
Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`.
```
with:
```
Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`, `POSTMORTEM`.
```

- [ ] **Step 4: Assert both updated**

Run: `grep -c "POSTMORTEM" CLAUDE.md README.md`
Expected: `1` in each file.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: list POSTMORTEM template in CLAUDE.md + README doc-set

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Version bump, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`
- Modify: `CHANGELOG.md` (new entry at top, after the format header)
- Modify: `docs/ROADMAP-KIT.md` (new 8a row after the 7f row at line 24)

- [ ] **Step 1: Bump VERSION**

Replace the contents of `VERSION` (`2.18.0`) with:
```
2.19.0
```

- [ ] **Step 2: Add the CHANGELOG entry**

Insert this entry immediately **above** the `## [2.18.0] - 2026-06-08` line:
```markdown
## [2.19.0] - 2026-06-09

Slice 8a — Incident Response standard + blameless postmortem template. First sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A1 (no incident-response standard + a dangling cross-reference).

### Added
- **`DEVELOPMENT-STANDARDS.md` §15 — Incident Response**: P0–P3 severity matrix, incident roles as functions (commander · comms · scribe; agents assist, a human commands), the detect→declare→mitigate→resolve→postmortem arc, and a blameless-postmortem requirement (P0/P1) whose action items route back into the loop. NIST SP 800-61 anchor; incident tooling named Org-owned.
- **`templates/POSTMORTEM-TEMPLATE.md`** — a nine-section blameless postmortem (summary, impact, timeline, root cause, detection, went well/didn't, action items, blameless statement).
- **`conformance/audit-evidence-checklist.md`** — an Incident-response row (CC7.3/7.4 / ISO A.5.24–A.5.28; Manual).

### Fixed
- The two **dangling cross-references** in `DEVELOPMENT-PROCESS.md` §8/§9 (lines 212, 225) that pointed at a non-existent STANDARDS incident-response section now cite `DEVELOPMENT-STANDARDS.md` §15. The artifact-flow Postmortem row links the new template.

### Note
MINOR (2.19.0): additive — a new standard section, a template, and reference fixes. No new required CI gate; no behavior change. §1–§14 of `DEVELOPMENT-STANDARDS.md` are unrenumbered (§15 appended).
```

- [ ] **Step 3: Add the ROADMAP row**

In `docs/ROADMAP-KIT.md`, insert this row immediately **after** the 7f row (line 24):
```
| 8a ✅ | **Incident Response standard** *(shipped v2.19.0)* | standards §15 + process §8/§9 | §15 Incident Response + `POSTMORTEM-TEMPLATE.md` + dangling-ref fixes | `check-links.sh` + audit-evidence (Manual row) |
```

- [ ] **Step 4: Assert meta updates**

Run:
```bash
cat VERSION && \
grep -c "## \[2.19.0\]" CHANGELOG.md && \
grep -c "8a ✅" docs/ROADMAP-KIT.md
```
Expected: `2.19.0`; CHANGELOG count `1`; ROADMAP count `1`.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.19.0 — incident response standard (8a)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Full conformance sweep (whole-slice verification)

**Files:** none (verification only)

- [ ] **Step 1: Run every conformance check**

Run:
```bash
sh conformance/check-links.sh; echo "links=$?"
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 || echo "FAIL $p"; done; echo "ci-gates done"
sh conformance/profile-completeness.sh; echo "profiles=$?"
sh conformance/agent-autonomy.sh; echo "autonomy=$?"
sh conformance/container-supply-chain.sh; echo "containers=$?"
sh conformance/backlog-adapters.sh; echo "backlog=$?"
sh conformance/guard-wired.sh; echo "guard=$?"
```
Expected: `links=0`, no `FAIL` lines from the ci-gates loop (all 10 profiles pass), `profiles=0`, `autonomy=0`, `containers=0` (or skip-N/A pass), `backlog=0`, `guard=0`. (`inception-done.sh` is expected to FAIL at the kit root and is intentionally NOT run here — see `conformance/README.md`.)

> **ci-gates target:** `ci-gates.sh` validates the **8 application gate-ids**, which live in **profile** `ci.yml` files — run it against `profiles/*/ci.yml` (as the kit's own CI does, `.github/workflows/ci.yml:21`). Do NOT run it against the kit's own `.github/workflows/ci.yml`: that is the meta/conformance pipeline, not an application pipeline, so it lacks those gate-ids and fails by design (on `main` too — not a regression).

- [ ] **Step 2: Final spec-coverage greps**

Run:
```bash
grep -c "## 15. Incident Response" DEVELOPMENT-STANDARDS.md          # 1
grep -c "## 16\." DEVELOPMENT-STANDARDS.md                           # 0 (no renumber)
grep -c "postmortem procedure in \`DEVELOPMENT-STANDARDS.md\`" DEVELOPMENT-PROCESS.md  # 0 (dangling gone)
ls templates/POSTMORTEM-TEMPLATE.md                                  # exists
grep -c "Incident response · postmortem" conformance/audit-evidence-checklist.md      # 1
cat VERSION                                                          # 2.19.0
```
Expected values are in the comments above.

- [ ] **Step 3: Confirm clean tree + push the branch**

```bash
git status --short        # expect clean (all committed)
git push -u origin feature/slice-8a-incident-response
```

- [ ] **Step 4: Open the PR (do NOT merge — human ratification gate)**

```bash
gh pr create --title "Slice 8a — Incident Response standard + blameless postmortem template (v2.19.0)" \
  --body "$(cat <<'EOF'
Closes gap A1 (Slice 8 arc). First sub-slice of the continuity & safe-delivery hardening arc.

## What
- **`DEVELOPMENT-STANDARDS.md` §15 — Incident Response** (appended, no renumber): P0–P3 severity matrix, roles-as-functions (commander · comms · scribe; agents assist, a human commands), detect→declare→mitigate→resolve→postmortem arc, blameless-postmortem requirement (P0/P1) routing action items back into the loop. NIST 800-61 anchor; incident tooling named Org-owned.
- **`templates/POSTMORTEM-TEMPLATE.md`** — nine-section blameless postmortem.
- **Fixed** the two dangling `DEVELOPMENT-PROCESS.md` refs (212/225) → §15; artifact-flow Postmortem row links the template.
- **Audit-evidence** Incident-response row (CC7.3/7.4 / A.5.24–A.5.28; Manual).
- Doc-set mentions (`CLAUDE.md`/`README.md`) list POSTMORTEM.

## Verification
All conformance green (`check-links.sh`, `ci-gates.sh`, `profile-completeness.sh`, `agent-autonomy.sh`, `container-supply-chain.sh`, `backlog-adapters.sh`, `guard-wired.sh`). §1–§14 unrenumbered. MINOR → 2.19.0.

## Governance
Governing-doc surface (STANDARDS/PROCESS) → **security-owner lens** on review. Agent does not self-merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: STOP for human ratification**

Do not merge. Report the PR URL and the green conformance results to Bradley for review and merge (governing-doc change → security-owner lens per §13/RBAC).

---

## Self-Review

**1. Spec coverage:**
- §15 section (spec §5) → Task 1. ✅
- POSTMORTEM template, nine sections (spec §6) → Task 2. ✅
- Dangling refs 212/225 + artifact-flow row (spec §4 C/D) → Task 3. ✅
- Audit-evidence row (spec §4 E) → Task 4. ✅
- CLAUDE.md/README mentions (spec §4 F) → Task 5. ✅
- VERSION 2.19.0 + CHANGELOG + ROADMAP (spec §4 Meta) → Task 6. ✅
- Validation greps + conformance (spec §7) → woven into each task + Task 7. ✅
- Append-not-renumber (spec §3) → Task 1 Steps 2/4 + Task 7 Step 2 (`## 16.` count 0). ✅
- 8c forward-ref avoided (spec §8 risk) → §15 text references §10 / RUNBOOK DR, not an unshipped 8c anchor. ✅

**2. Placeholder scan:** The `[...]` and `[id]`/`[name]` tokens inside the POSTMORTEM template (Task 2) are **intended template fill-ins** (matching sibling templates' style), not plan placeholders. No "TBD/TODO/implement later" in the plan's own instructions. ✅

**3. Consistency:** Section number "§15" is used identically in STANDARDS (the new section), the two PROCESS repoints, the template's back-reference, the audit row, CHANGELOG, and ROADMAP. "CC7.3, CC7.4 / A.5.24–A.5.28" identical in spec §4E, Task 4, and CHANGELOG. The template's "nine-section" claim vs. the `^## [1-8]\.` grep: the grep counts the **eight numbered** sections (1–8); the header (`# [Incident Title]`) + the "How to use" block are unnumbered, so "nine sections" in prose = 8 numbered + the header block. Task 2 Step 3 asserts `8` numbered — consistent. ✅
