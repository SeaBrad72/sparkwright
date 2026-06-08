# Design — Slice 7b: Multi-Persona Role Touchpoints

**Date:** 2026-06-06
**Status:** Approved (umbrella plan) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Second sub-slice of Slice 7. Closes audit gaps G5/G6/G7. Plan: `~/.claude/plans/drifting-stirring-thunder.md` §7b.

---

## 1. Goal

Make the kit usable by — and legible to — the non-developer roles an enterprise puts around a build loop (Product Owner/BA, QA, DevOps/SRE, Designer), **without turning the kit into a PM/design tool**. Engineer + Agent stay the core operating surface; we add **named role touchpoints** — each persona mapped to the loop function it holds, where it plugs in, and its entry/exit artifact — plus the two missing intake artifacts (a feature-request template and a spec/PRD template) so "anybody presenting functional requirements" has a front door.

## 2. Decisions

- **Augment, don't replace, the "functions, not titles" model (§2).** The existing 6 functions stay. We add a **persona → function → touchpoint** mapping so a PO/QA/DevOps/Designer can see where they fit. Personas are *lenses on the functions*, not new enforced roles.
- **Two new intake artifacts:** `FEATURE-REQUEST-TEMPLATE.md` (the PO/BA front door, mirroring the §5 Discovery prompts) and `SPEC-TEMPLATE.md` (the PRD behind the gated Plan/spec phase). Both follow the existing `_TEMPLATE` guidance-blockquote style.
- **Persona-routed onboarding:** a "Who are you? Start here" map at the top of `START-HERE.md` routing each persona to its minimal path; surface `scripts/incept.sh` as the engineer/lead fast path (it's currently undiscoverable from the front door).
- **Designer gets a real lane:** named in §2, an input at Discovery, an accessibility sign-off owner in the Definition of Done, and a row in the §15 artifact-flow.
- **No new gate, no code, no enforced separation added.** Version **2.14.0** (MINOR, additive docs/templates).

## 3. Deliverables

| Part | Files |
|------|-------|
| Persona mapping | `DEVELOPMENT-PROCESS.md` §2 (persona table after the roles table); §5 (PO/Designer as intake drivers); §15 (designer lane in artifact flow) |
| Intake templates | `templates/FEATURE-REQUEST-TEMPLATE.md`, `templates/SPEC-TEMPLATE.md` |
| Onboarding | `START-HERE.md` (persona "Who are you?" map + incept fast-path) |
| Project config | `templates/PROJECT-CLAUDE-TEMPLATE.md` §4 (roles reference the personas) |
| Meta | `VERSION` 2.14.0; `CHANGELOG.md`; `docs/ROADMAP-KIT.md` (7b row) |

## 4. Detailed design

### 4.1 Persona mapping (`DEVELOPMENT-PROCESS.md` §2)
Add a subsection after the roles table titled "Personas (who holds which function)":

| Persona | Holds function(s) | Plugs in at | Entry / exit artifact |
|---------|-------------------|-------------|-----------------------|
| **Product Owner / BA** | Intent owner | Discover → Plan; accepts increments | `FEATURE-REQUEST` in → accepted increment out |
| **Designer** | (informs Intent owner) | Discover (UX input) → Review (a11y sign-off) | design assets/handoff in → accessibility sign-off |
| **Engineer** | Builder (+ often Reviewer/Lead) | Plan → Build → Review | spec in → reviewed PR out |
| **QA Engineer** | Reviewer (test lens) + acceptance | Review + **UAT acceptance gate** (§ Environments & promotion) | test strategy/cases → UAT sign-off |
| **DevOps / SRE** | On-call / operator | Release → Operate (promotion, deploy, rollback, monitoring) | promotion run → operated service |
| **Security Owner** | Security owner | the security/ratification gate (§7, §13) | threat model → gate pass / governed exception |
| **Lead / Agent** | Lead / integrator, Builder | the whole loop | the board → integrated, ratified work |

One person/agent may hold several (the §2 rule). Note: QA's UAT acceptance ties to the Dev→QA→UAT→Prod model from 7a; Designer's a11y sign-off ties to the Definition-of-Done accessibility item.

### 4.2 Intake templates
- **`templates/FEATURE-REQUEST-TEMPLATE.md`** — the PO/BA front door, one fillable section per §5 Discovery prompt: Problem & user · Evidence · Success metric / hypothesis · Rough scope & risk · Innovation/AI lens. Plus a "for whom / requested by" line. Guidance blockquotes explain each (non-coder-friendly). Output feeds Plan.
- **`templates/SPEC-TEMPLATE.md`** — the PRD behind the gated Plan/spec phase: Context/problem · Goals & non-goals · Users & personas · Functional requirements · Acceptance criteria (testable) · UX/design notes (+ a11y) · Data/▮privacy considerations · Risks · Out of scope. Mirrors the brainstorming-spec discipline but tool-neutral for non-superpowers users.

### 4.3 Persona-routed onboarding (`START-HERE.md`)
Add a "Who are you? Start here" table at the very top (before step 0):

| If you are… | Start with | Then |
|-------------|-----------|------|
| **Product Owner / BA / stakeholder** | `templates/FEATURE-REQUEST-TEMPLATE.md` | hand it to the team / drop it on the board (§6) |
| **Designer** | Discovery (§5) + the a11y items in the Definition of Done | attach assets to the spec |
| **QA** | the testing standards + the UAT acceptance gate (§ Environments & promotion) | own acceptance |
| **DevOps / SRE** | the env model + RUNBOOK + CI (§14) | own promotion/operate |
| **Engineer / Lead (greenfield)** | **run `sh scripts/incept.sh`** then do the judgment steps | full Inception |
| **Engineer (existing repo)** | brownfield adoption (7e) | — |

This makes `incept.sh` discoverable (G7) and gives non-coders a one-line path instead of four dense engineering docs.

### 4.4 Designer lane (§15 artifact flow)
Add a row/lane to the artifact-flow table: design assets (Discover) → referenced in the spec (Plan) → a11y sign-off at Review (DoD) → shipped. So visual/UX deliverables have a defined home, not just code/spec/CI.

### 4.5 Project config (`PROJECT-CLAUDE-TEMPLATE.md` §4)
The Roles table guidance gains a one-line pointer to the persona mapping (so a project assigns real people/agents to personas at Inception).

## 5. Validation / testing
- `sh conformance/check-links.sh` → 0 (new templates + START-HERE links resolve).
- `sh conformance/profile-completeness.sh`, `ci-gates.sh` ×10, `agent-autonomy.sh` → green (no regression; docs-only slice).
- Manual: a non-developer can read the START-HERE persona map → open `FEATURE-REQUEST-TEMPLATE.md` → fill it without touching engineering setup (the G5/G6 acceptance).
- `inception-done.sh` still passes (templates added, none removed).
- Kit CI green.

## 6. Risks & mitigations
- **Scope creep into a PM/design tool.** Mitigation: personas are *lenses on existing functions*, not new workflows; two templates only; no new enforced role/gate.
- **Contradicting the "functions, not titles" model.** Mitigation: the persona table explicitly maps personas *to* the functions; the functions remain authoritative.
- **Template bloat.** Mitigation: FEATURE-REQUEST mirrors the existing §5 prompts (no new concepts); SPEC mirrors the brainstorming spec.

## 7. Out of scope
- Per-persona dedicated workflows / separate onboarding products (the rejected "full multi-persona" option).
- Design tooling integration (Figma, etc.) — the lane references handoff, doesn't integrate.
- The QA/UAT *environment mechanics* (shipped in 7a) — 7b only puts the QA persona on that gate.

## 8. Definition of Done
- §2 persona mapping added (augments, doesn't replace, the functions table); §5 + §15 name Designer/PO touchpoints + designer lane.
- `FEATURE-REQUEST-TEMPLATE.md` + `SPEC-TEMPLATE.md` shipped in `templates/`.
- `START-HERE.md` "Who are you?" map + `incept.sh` fast-path; `PROJECT-CLAUDE-TEMPLATE.md` §4 persona pointer.
- All conformance green; kit CI green; `VERSION` 2.14.0; CHANGELOG + ROADMAP (7b).
- Feature branch → PR → **human ratification** (governing-doc change → Security-Owner lens).
