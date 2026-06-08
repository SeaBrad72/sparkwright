# Slice 7b — Multi-Persona Role Touchpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the kit legible and usable by the non-developer roles around a build loop (Product Owner/BA, QA, DevOps/SRE, Designer) by adding named persona touchpoints, two intake templates, and persona-routed onboarding — without turning the kit into a PM/design tool.

**Architecture:** Pure docs + templates slice (no executable code). It **augments** the existing "functions, not titles" model (`DEVELOPMENT-PROCESS.md` §2) with a persona→function→touchpoint mapping, adds `FEATURE-REQUEST-TEMPLATE.md` + `SPEC-TEMPLATE.md` in `templates/`, prepends a "Who are you? Start here" router to `START-HERE.md` (surfacing `scripts/incept.sh`), and gives Designer a lane in §5 + §15. Validation is the kit's own conformance scripts, not unit tests.

**Tech Stack:** Markdown; POSIX `sh` conformance scripts (`check-links.sh`, `profile-completeness.sh`, `agent-autonomy.sh`, `ci-gates.sh`, `inception-done.sh`). No new gate, no code.

**Spec:** `docs/superpowers/specs/2026-06-06-slice7b-personas-design.md` (approved). **Version target:** `2.14.0` (MINOR — additive docs/templates).

**Governance note (applies to every task):** This is a feature branch (`feature/slice-7b-personas`, already created). Commit per task. Do **not** merge — the slice ends at a PR for human ratification (governing-doc change → Security-Owner lens). Agents never self-merge. The active `.claude/` guard blocks commit/PR text containing literal destructive command strings (e.g. `DROP DATABASE`, `db:drop`); keep commit messages free of such literals.

**Conventions to match (read before starting):**
- Templates open with a guidance blockquote: `> **Template.** …` then a `**Created:** [date]` line, then a `## How to use`, then fillable sections with `>` guidance under each. See `templates/BACKLOG-TEMPLATE.md:1-10` for the exact house style.
- `DEVELOPMENT-PROCESS.md` uses `---` rules between numbered sections and `**Bold**` lead-ins in tables.
- Relative links in `templates/` and `docs/` are checked by `conformance/check-links.sh` — every link must resolve from the file's own location.

---

### Task 1: Persona mapping in `DEVELOPMENT-PROCESS.md` §2

Augment the §2 roles section with a persona→function→touchpoint table directly after the existing "Enforced separations" line, before the `---` rule.

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md:40-42` (insert after line 40, the "Enforced separations" paragraph; before the `---` at line 42)

- [ ] **Step 1: Insert the persona subsection**

After the line ending `…(agents propose, humans ratify).` and before the `---`, insert:

```markdown

### Personas (who holds which function)

The functions above are authoritative. **Personas are lenses on them** — an enterprise puts named roles around the loop; this maps each to the function it holds, where it plugs in, and its entry/exit artifact. One person or agent may hold several (the §2 rule).

| Persona | Holds function(s) | Plugs in at | Entry → exit artifact |
|---------|-------------------|-------------|-----------------------|
| **Product Owner / BA** | Intent owner | Discover → Plan; accepts increments | `FEATURE-REQUEST` in → accepted increment out |
| **Designer** | informs Intent owner | Discover (UX input) → Review (a11y sign-off) | design assets/handoff in → accessibility sign-off |
| **Engineer** | Builder (often also Reviewer / Lead) | Plan → Build → Review | spec in → reviewed PR out |
| **QA Engineer** | Reviewer (test lens) + acceptance | Review + UAT acceptance gate (§9 Environments & promotion) | test strategy/cases in → UAT sign-off out |
| **DevOps / SRE** | On-call / operator | Release → Operate (promotion, deploy, rollback, monitoring) | promotion run in → operated service out |
| **Security owner** | Security owner | the security / ratification gate (§7, §13) | threat model in → gate pass / governed exception |
| **Lead / Agent** | Lead / integrator, Builder | the whole loop | the board in → integrated, ratified work out |

QA's UAT acceptance ties to the Dev→QA→UAT→Prod model (§9); Designer's a11y sign-off ties to the Definition-of-Done accessibility item.
```

- [ ] **Step 2: Verify links still resolve**

Run: `sh conformance/check-links.sh`
Expected: exit 0, no broken links (the §9/§7/§13 references are intra-doc section names, not links — no new link introduced here).

- [ ] **Step 3: Verify no regression in process-dependent conformance**

Run: `sh conformance/inception-done.sh && sh conformance/profile-completeness.sh`
Expected: both exit 0 (this edit doesn't touch inception artifacts or profiles).

- [ ] **Step 4: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "feat(process): persona mapping augments functions-not-titles model (§2)"
```

---

### Task 2: Designer lane in §5 Discovery and §15 Artifact Flow

Give Designer an explicit input at Discovery and a row in the artifact-flow table so visual/UX deliverables have a defined home.

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md:112` (add a Designer/UX prompt to the §5 Discovery list, after the Innovation lens bullet)
- Modify: `DEVELOPMENT-PROCESS.md:382-391` (add a "Design assets / UX handoff" row to the §15 artifact-flow table)

- [ ] **Step 1: Add the UX prompt to §5**

After the `- **Innovation lens** — …` bullet (line 112) and before the blank line preceding `**Output:**`, insert:

```markdown
- **UX & accessibility lens** — is there a user-experience or visual surface? If so, the Designer informs the candidate here; capture rough flows/assets and flag the WCAG 2.1 AA a11y obligation that the Definition of Done will check.
```

- [ ] **Step 2: Add the Designer row to §15**

In the artifact-flow table, after the `Spec (design)` row (line 383) insert:

```markdown
| Design assets / UX handoff | Discover → Plan (referenced in spec) | UX surface changes | designer (informs intent owner) |
```

- [ ] **Step 3: Verify links + no regression**

Run: `sh conformance/check-links.sh && sh conformance/inception-done.sh`
Expected: both exit 0.

- [ ] **Step 4: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "feat(process): designer lane in Discovery (§5) and artifact flow (§15)"
```

---

### Task 3: `FEATURE-REQUEST-TEMPLATE.md` (PO/BA front door)

A fillable, non-coder-friendly intake form mirroring the §5 Discovery prompts. Feeds Plan.

**Files:**
- Create: `templates/FEATURE-REQUEST-TEMPLATE.md`

- [ ] **Step 1: Write the template**

```markdown
# [Feature / Request Title] — Feature Request

> **Template.** The front door for anyone proposing functional requirements — Product Owner, BA, stakeholder, support, or an engineer capturing a need. You do **not** need to write code or know the stack to fill this in. It mirrors the Discovery prompts (`DEVELOPMENT-PROCESS.md` §5); a complete one becomes a validated candidate ready for **Plan**.

**Requested by:** [name / role] · **For whom (users):** [audience] · **Date:** [date]

## How to use
- Fill every section below in plain language. Bullet points are fine.
- Skip nothing: an unanswered section is a signal the idea isn't ready (that's useful, not a failure).
- Hand the finished file to the team or drop it on the board (`DEVELOPMENT-PROCESS.md` §6). The Intent owner validates it; survivors go to Plan, the rest to the roadmap parking lot.

---

## Problem & user
> What problem, for whom? What is the current pain or workaround?

[...]

## Evidence
> What tells us this is real — support tickets, user requests, telemetry, revenue? Not "we assume."

[...]

## Success metric / hypothesis
> How will we know it worked? State it measurably ("X drops by Y%", "users can now Z").

[...]

## Rough scope & risk
> Roughly how big? Any obvious risk, compliance, privacy, or children's-data flag? Anything explicitly out of scope?

[...]

## UX & accessibility
> Is there a screen or visual surface? Attach/link any sketches or designer handoff. Note accessibility needs (the Definition of Done requires WCAG 2.1 AA for user-facing UI).

[...]

## Innovation / AI lens
> Could AI materially improve this? Any reusable or product angle? (Optional — leave blank if not applicable.)

[...]
```

- [ ] **Step 2: Verify the template's links resolve**

Run: `sh conformance/check-links.sh`
Expected: exit 0 (the `DEVELOPMENT-PROCESS.md` references are bare filenames in prose, not markdown links — no link to break; confirm the script stays green).

- [ ] **Step 3: Commit**

```bash
git add templates/FEATURE-REQUEST-TEMPLATE.md
git commit -m "feat(templates): add FEATURE-REQUEST-TEMPLATE (PO/BA intake front door)"
```

---

### Task 4: `SPEC-TEMPLATE.md` (the PRD behind the gated Plan phase)

A tool-neutral spec/PRD template for teams not using the superpowers brainstorming flow. Sits behind the Plan gate.

**Files:**
- Create: `templates/SPEC-TEMPLATE.md`

- [ ] **Step 1: Write the template**

```markdown
# [Feature Name] — Spec (PRD)

> **Template.** The design/PRD produced at the **Plan** gate (`DEVELOPMENT-PROCESS.md` §4, §7) from a validated `FEATURE-REQUEST` (or direct Discovery). Tool-neutral — if you use the superpowers brainstorming flow, that produces an equivalent spec; this is the manual form. A reviewer signs off before Build begins.

**Author:** [name / agent] · **Intent owner:** [who accepts it] · **Date:** [date] · **Status:** draft / in review / approved

## How to use
- Every section is required unless marked optional. "Could be interpreted two ways" means pick one and write it down.
- Acceptance criteria must be **testable** — they become the tests and the Reviewer's checklist.
- Approved spec → Build. Scope changes after approval are a new revision, noted here.

---

## Context & problem
> The problem and why now. Link the originating `FEATURE-REQUEST` if there is one.

[...]

## Goals & non-goals
> What this delivers; what it explicitly does **not** (the YAGNI fence).

[...]

## Users & personas
> Who uses this and in what role (see the persona map, `DEVELOPMENT-PROCESS.md` §2).

[...]

## Functional requirements
> Numbered, specific behaviors the system must exhibit.

[...]

## Acceptance criteria (testable)
> Pass/fail conditions. Each maps to at least one test. 100% on critical paths (auth, payments, data integrity).

[...]

## UX & accessibility notes
> Flows, states, designer handoff links. WCAG 2.1 AA obligations for any user-facing UI.

[...]

## Data & privacy considerations
> What data is touched; PII/consent/retention/children's-data implications (`DEVELOPMENT-STANDARDS.md` §2 + the enterprise privacy family). "None" is a valid, explicit answer.

[...]

## Risks & mitigations
> What could go wrong technically or operationally, and the mitigation.

[...]

## Out of scope
> Deferred or explicitly excluded — so reviewers don't flag them as gaps.

[...]
```

- [ ] **Step 2: Verify links resolve**

Run: `sh conformance/check-links.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add templates/SPEC-TEMPLATE.md
git commit -m "feat(templates): add SPEC-TEMPLATE (PRD behind the Plan gate)"
```

---

### Task 5: Persona-routed onboarding in `START-HERE.md`

Prepend a "Who are you? Start here" router that routes each persona to its minimal path and surfaces `scripts/incept.sh` (currently undiscoverable from the front door). Closes G7.

**Files:**
- Modify: `START-HERE.md:7-9` (insert the router after the `---` on line 7, before `## 0. Orient`)

- [ ] **Step 1: Insert the router**

After line 7 (`---`) and before line 9 (`## 0. Orient (5 min)`), insert:

```markdown
## Who are you? Start here

This guide's numbered steps are the **engineer/lead Inception path**. If you're a different role, start at your row, then return here only for the steps your row points to.

| If you are… | Start with | Then |
|-------------|-----------|------|
| **Product Owner / BA / stakeholder** | `templates/FEATURE-REQUEST-TEMPLATE.md` | hand it to the team or drop it on the board (`DEVELOPMENT-PROCESS.md` §6) — no engineering setup needed |
| **Designer** | the Discovery UX prompt (`DEVELOPMENT-PROCESS.md` §5) + the a11y items in the Definition of Done (`CLAUDE.md`) | attach assets to the spec; own the a11y sign-off at Review |
| **QA Engineer** | the testing bar (`DEVELOPMENT-STANDARDS.md`) + the UAT acceptance gate (`DEVELOPMENT-PROCESS.md` §9) | own acceptance |
| **DevOps / SRE** | the environment model (`DEVELOPMENT-PROCESS.md` §9) + `RUNBOOK.md` + CI (`DEVELOPMENT-STANDARDS.md` §14) | own promotion & operate |
| **Engineer / Lead — new project** | **run `sh scripts/incept.sh`**, then work the judgment steps below | full Inception (steps 1–7) |
| **Engineer — existing repo (brownfield)** | the steps below, adapting in place | (dedicated brownfield path lands in a later slice) |

---

```

- [ ] **Step 2: Verify all router links resolve**

Run: `sh conformance/check-links.sh`
Expected: exit 0. The router references `templates/FEATURE-REQUEST-TEMPLATE.md` (created in Task 3), `RUNBOOK.md`, `scripts/incept.sh`, and sibling docs — confirm each is a real path relative to repo root. If `check-links.sh` flags `RUNBOOK.md` (which exists only in instantiated projects, not the kit root), render it as inline code (already done above) rather than a link so it isn't checked.

- [ ] **Step 3: Confirm incept script path is real**

Run: `test -f scripts/incept.sh && echo OK`
Expected: `OK` (the router must not point at a non-existent script).

- [ ] **Step 4: Commit**

```bash
git add START-HERE.md
git commit -m "feat(onboarding): persona router in START-HERE + incept fast-path"
```

---

### Task 6: Persona pointer in `PROJECT-CLAUDE-TEMPLATE.md` §4

Point the project Roles table at the persona mapping so a project assigns real people/agents to personas at Inception.

**Files:**
- Modify: `templates/PROJECT-CLAUDE-TEMPLATE.md:57` (extend the guidance blockquote under `## 4. Roles`)

- [ ] **Step 1: Extend the guidance line**

Replace line 57:

```markdown
> Fill each function from `DEVELOPMENT-PROCESS.md` §2 with a human or agent. One may hold several; builder ≠ reviewer; humans ratify.
```

with:

```markdown
> Fill each function from `DEVELOPMENT-PROCESS.md` §2 with a human or agent. One may hold several; builder ≠ reviewer; humans ratify. For a role-oriented view (PO/BA · Designer · QA · DevOps/SRE mapped to these functions), see the **Personas** table in §2.
```

- [ ] **Step 2: Verify links + inception conformance**

Run: `sh conformance/check-links.sh && sh conformance/inception-done.sh`
Expected: both exit 0.

- [ ] **Step 3: Commit**

```bash
git add templates/PROJECT-CLAUDE-TEMPLATE.md
git commit -m "feat(templates): point project Roles table at the persona map (§4→§2)"
```

---

### Task 7: Version, CHANGELOG, ROADMAP

Record the slice as `2.14.0` and close the loop on the meta files.

**Files:**
- Modify: `VERSION` (single line `2.13.0` → `2.14.0`)
- Modify: `CHANGELOG.md:6` (new `## [2.14.0]` block above `## [2.13.0]`)
- Modify: `docs/ROADMAP-KIT.md:20` (add a 7b ✅ row after the 7a row)

- [ ] **Step 1: Bump VERSION**

Replace the sole contents of `VERSION` with:

```
2.14.0
```

- [ ] **Step 2: Add the CHANGELOG block**

Immediately after line 4 (the `Format: …` line) and its trailing blank line, before `## [2.13.0]`, insert:

```markdown
## [2.14.0] - 2026-06-06

Slice 7b — Multi-persona role touchpoints. Second sub-slice of Slice 7. Makes the kit legible to non-developer roles without becoming a PM/design tool.

### Added
- **Persona mapping** in `DEVELOPMENT-PROCESS.md` §2 — PO/BA · Designer · Engineer · QA · DevOps/SRE · Security · Lead/Agent mapped to the existing "functions, not titles" model (personas are lenses on functions; nothing in §2 is replaced).
- **Designer lane** — a UX & accessibility prompt in §5 Discovery and a "Design assets / UX handoff" row in the §15 artifact flow.
- `templates/FEATURE-REQUEST-TEMPLATE.md` (non-coder intake front door, mirrors the §5 Discovery prompts) and `templates/SPEC-TEMPLATE.md` (tool-neutral PRD behind the Plan gate).
- **Persona-routed onboarding** — a "Who are you? Start here" router atop `START-HERE.md` that routes each role to its minimal path and surfaces `scripts/incept.sh` as the engineer fast-path.

### Changed
- `templates/PROJECT-CLAUDE-TEMPLATE.md` §4 Roles guidance now points at the persona map.

### Note
No new required CI gate (MINOR). Docs/templates only — no enforced separation or code added; personas augment, not replace, the §2 functions.

```

- [ ] **Step 3: Add the ROADMAP row**

After line 19 (the `7a ✅` row) and before the `6 ✅` summary row, insert:

```markdown
| 7b ✅ | **Multi-persona touchpoints** *(shipped v2.14.0)* | process §2/§5/§15 | persona map + `FEATURE-REQUEST`/`SPEC` templates + persona-routed START-HERE | `check-links.sh` + `inception-done.sh` |
```

- [ ] **Step 4: Full conformance sweep**

Run:
```bash
sh conformance/check-links.sh && \
sh conformance/profile-completeness.sh && \
sh conformance/inception-done.sh && \
sh conformance/agent-autonomy.sh && \
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" || break; done && \
echo "ALL GREEN"
```
Expected: `ALL GREEN` (no regression; 7b adds no gate and touches no profile/guard).

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.14.0 — multi-persona role touchpoints (7b)"
```

---

### Task 8: Open the PR (stop for human ratification)

**Files:** none (git/gh only)

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/slice-7b-personas
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Slice 7b — Multi-persona role touchpoints (v2.14.0)" --body "$(cat <<'EOF'
## Summary
Second sub-slice of Slice 7. Adds named persona touchpoints (PO/BA · Designer · QA · DevOps/SRE) as lenses on the existing functions-not-titles model, two intake templates (FEATURE-REQUEST, SPEC), persona-routed START-HERE surfacing incept.sh, and a designer lane. Docs/templates only — no new gate, no code, no enforced separation. v2.14.0 (MINOR).

## Governance
Governing-doc change (DEVELOPMENT-PROCESS.md §2/§5/§15) → Security-Owner lens. Agent did not self-merge; awaiting human ratification.

## Conformance
check-links · profile-completeness · inception-done · agent-autonomy · ci-gates ×10 — all green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: STOP**

Report the PR URL to the human and **stop**. Do not merge. Bradley ratifies and merges (the established 7a pattern). The slice is complete when the PR is open and green.

---

## Notes for the executor
- **No unit tests** in this slice — it ships Markdown. The conformance scripts are the regression suite; "green" is the bar.
- **Order matters only for Task 5 + Task 7**: Task 5's router links to the template created in Task 3, and Task 7's CHANGELOG/ROADMAP describe all prior tasks — run them after their dependencies. Tasks 1–4 are independent.
- **Guard caution:** the live `.claude/` guard scans Bash command text. None of these commits/PRs should contain literal destructive command strings, but if a future edit to the CHANGELOG quotes one (e.g. when summarizing 7a), reword to avoid the literal — the guard over-blocks on mention by design.
- **Do not touch** `guard.sh`, `agent-autonomy.sh`, any `profiles/`, or any CI YAML — 7b changes none of them; that's how we know it's regression-safe.
