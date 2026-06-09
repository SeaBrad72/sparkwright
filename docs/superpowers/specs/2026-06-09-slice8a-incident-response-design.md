# Design — Slice 8a: Incident Response standard + blameless postmortem template

**Date:** 2026-06-09
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** First sub-slice of Slice 8 (continuity & safe-delivery hardening). Arc-of-record: `docs/superpowers/ideation/2026-06-08-delivery-safety-continuity-gaps.md`. Closes gap **A1** (no Incident Response standard + a dangling cross-reference). Continuity-first, per the locked Slice 8 ordering.

---

## 1. Goal

Give the kit the Incident Response standard that `DEVELOPMENT-PROCESS.md` §9 already promises — and twice points a **broken cross-reference** at — plus the **blameless postmortem template** the §15 artifact-flow already requires but never shipped. This turns "P0/P1 escalate to Incident Response + postmortem" from a dangling pointer into a real, followable standard, and closes the loop (postmortem action items route back into the backlog/recurring-maintenance). Stack-neutral; no new mechanism that forces tooling. MINOR → **2.19.0**.

## 2. The defect being fixed (verified)

- `DEVELOPMENT-PROCESS.md:212` — "*Production* incidents follow Operate & Support (§9) and the **Incident Response / postmortem procedure in `DEVELOPMENT-STANDARDS.md`**." — **dangling**: STANDARDS has no such section (it ends at §14).
- `DEVELOPMENT-PROCESS.md:225` — "P0/P1 escalate to **Incident Response + postmortem (`DEVELOPMENT-STANDARDS.md`)**." — **dangling**, same reason.
- `DEVELOPMENT-PROCESS.md:412` — artifact-flow row "`| Postmortem | Incident (P0/P1) | — | responder + human |`" requires a Postmortem artifact, but `templates/` has **no postmortem template** (verified: BACKLOG, FEATURE-REQUEST, PROJECT-CLAUDE, RUNBOOK, SPEC only).

`DEVELOPMENT-STANDARDS.md` is §1–§14; **§14 (CI/CD) is the last section** and is cross-referenced throughout the kit. The severity ladder P0–P3 currently lives **only** in the user's global `CLAUDE.md` / PROCESS §9 triage — the kit's own standards never define it.

## 3. Decisions

- **Append as `DEVELOPMENT-STANDARDS.md` §15 "Incident Response" — do not renumber.** Incident Response is topically near Resilience (§4) / Data Management (§10), but §5–§14 are cross-referenced across the whole kit (notably §14, cited ~10×). Inserting mid-list and renumbering would be a high-blast-radius, error-prone change for a cosmetic gain. Appending §15 is a pure addition with zero renumbering. (This mirrors the kit's own additive-versioning discipline.)
- **Roles as *functions*, not titles** — consistent with the kit's §2 "functions, not titles" principle and the 7f casing normalization. **Incident commander · comms lead · scribe**; on a small team one person holds several. **Agents assist** (detect, correlate, summarize, draft timeline, propose mitigations); **a human commands** and authorizes any irreversible production action — ties to `DEVELOPMENT-PROCESS.md` §13 (the env-aware guard blocks agents from destructive prod actions) and the §13 autonomy tiers.
- **Blameless** — the postmortem examines systems and contributing factors, never individual blame. Required for **P0/P1**, recommended for P2.
- **The loop closes** — postmortem **action items route back into the loop** (backlog items per §6 / recurring-maintenance per §15), so a P0/P1 produces durable learning, not just a document. Mirrors the kit's retro philosophy (PROCESS §11/§15).
- **Light framework anchor, not a crosswalk** — a one-line nod to **NIST SP 800-61** (computer-security incident handling) and SRE incident-management practice, for adopters who need to map. Per the locked Q3 decision, frameworks fold into their slice as a *reference*, not a standalone crosswalk; **NIST 800-34 (contingency/DR) is reserved for 8c**.
- **Conformance is a checklist row, not a `.sh`** — incident-handling *quality* (was the incident well-commanded? was the postmortem genuinely blameless?) is not mechanically gradeable; a grep would be theater and would violate the kit's "don't draw a map that hides its edges" honesty. The right register is a **Manual audit-evidence row** plus the existing artifact-flow requirement. No new script.

## 4. Deliverables

| # | File(s) | Change |
|---|---------|--------|
| A | `DEVELOPMENT-STANDARDS.md` (append after §14, ~line 250) | New **§15 Incident Response** section (full content in §5 below) |
| B | `templates/POSTMORTEM-TEMPLATE.md` (new) | Blameless postmortem template (structure in §6 below) |
| C | `DEVELOPMENT-PROCESS.md` (lines 212, 225) | Repoint the two dangling refs → "`DEVELOPMENT-STANDARDS.md` §15 (Incident Response)" |
| D | `DEVELOPMENT-PROCESS.md` (artifact-flow row ~line 412) | Postmortem row references `templates/POSTMORTEM-TEMPLATE.md` |
| E | `conformance/audit-evidence-checklist.md` (after line 32, Observability) | New row: **Incident response · postmortem** · CC7.3, CC7.4 / A.5.24–A.5.28 · evidence = postmortem record(s) + action-item backlog links · **Manual** |
| F | `CLAUDE.md` (document-set "templates" mention) + `README.md` (template list, if it enumerates) | Add POSTMORTEM to the listed template set (refreshed in 7f) |
| Meta | `VERSION` 2.19.0 · `CHANGELOG.md` (2.19.0 entry) · `docs/ROADMAP-KIT.md` (8a row; open Slice 8) |

## 5. Detailed design — `DEVELOPMENT-STANDARDS.md` §15

Stack-neutral prose, in the established §-section voice. Content:

- **One-line purpose + framework anchor.** "How a production incident is declared, commanded, resolved, and learned from. Aligns with NIST SP 800-61 and SRE incident-management practice; the *contingency/DR* side lives in [8c]." (8c link as a forward reference, or omitted until 8c ships — decide at plan time; safe default: name DR as "your RUNBOOK DR section / §10" without a forward dangling ref.)
- **Severity matrix (P0–P3)** — promote the ladder from PROCESS §9 triage into the standard, with declare-criteria:
  - **P0 (critical):** prod down · data loss · security breach · safety/children's-audience exposure. All-hands; declare immediately.
  - **P1 (high):** major feature broken / significant user impact, no full outage. Urgent.
  - **P2 (medium):** degraded or partial; a workaround exists.
  - **P3 (low):** minor / cosmetic; scheduled fix.
  - Ties explicitly to PROCESS §9 ("the same P0–P3 the triage step routes on").
- **Incident roles (functions).** Incident commander (owns the response, the only one who declares severity changes and authorizes mitigations), comms lead (stakeholder/status updates), scribe (timeline + decisions). One person may hold several on a small team. **Agents assist; a human commands** — irreversible prod actions are human-authorized (→ PROCESS §13 guard + autonomy tiers).
- **Response arc.** detect → **declare** (severity + named commander) → **stabilize/mitigate first** (flag-off / rollback per PROCESS §10 — restore service before root-causing) → resolve → **postmortem**.
- **Postmortem.** Blameless; **required for P0/P1**, recommended for P2. Uses `templates/POSTMORTEM-TEMPLATE.md`. **Action items route back into the loop** (backlog §6 / recurring-maintenance §15) with owner + due — the incident teaches the next iteration ("the loop closes", CLAUDE.md principle 6).
- **Honesty boundary** (consistent with 7a/7e). The kit standardizes the *practice and artifacts*; incident **tooling** (paging, status page, on-call rotation) and the human on-call program are **Org-owned** — named, not pretended-to-enforce.

## 6. Detailed design — `templates/POSTMORTEM-TEMPLATE.md`

House style: guidance blockquotes (matching the other templates' `> _Fill this with…_` voice), fill-in placeholders. Sections:

1. **Header** — incident ID/title · severity (P0–P3) · date · incident commander · status (open/closed).
2. **Summary** — 2–3 sentences, plain language.
3. **Impact** — who/what affected · duration (detect→resolve) · data or users affected · SLA/SLO breach if any.
4. **Timeline** — UTC-stamped: detected → declared → key mitigations → resolved. (Scribe's record.)
5. **Root cause(s) & contributing factors** — the "5 whys" / systems view; **blameless framing stated explicitly**.
6. **Detection** — how we found out (alert? user report?) and how fast; gap if detection lagged.
7. **What went well / what didn't** — candid, system-focused.
8. **Action items** — table: action · owner · due · **backlog link** · type (prevent / detect-faster / mitigate-faster). This is the loop-closing artifact.
9. **Blameless statement** — a short standing note that this document examines systems, not people.

## 7. Validation / testing

- `sh conformance/check-links.sh` → 0 (new §15 internal refs and the POSTMORTEM template path resolve; no link broken by the repoints).
- `sh conformance/ci-gates.sh profiles/<stack>/ci.yml` (the app-pipeline target — loop over `profiles/*/ci.yml`, as the kit's own CI does; NOT the kit's meta-CI `.github/workflows/ci.yml`, which lacks the 8 app gate-ids by design), `profile-completeness.sh`, `agent-autonomy.sh`, `container-supply-chain.sh`, `backlog-adapters.sh`, `guard-wired.sh` → green (no regression; this slice adds no script and changes no profile/CI).
- `grep -n "Incident Response / postmortem procedure in" DEVELOPMENT-PROCESS.md` → **no match** (both dangling forms repointed); `grep -rn "§15" DEVELOPMENT-STANDARDS.md` confirms the section exists and is numbered 15.
- `grep -c "Incident response" conformance/audit-evidence-checklist.md` ≥ 1 (row added in the Security & engineering controls block).
- Template: `templates/POSTMORTEM-TEMPLATE.md` exists, all nine sections present, guidance-blockquote style matches a sibling template.
- Kit CI green.

## 8. Risks & mitigations

- **Renumber temptation** — a future contributor may "tidy" §15 into topical order and renumber. Mitigation: the section's placement note + this spec record why it's appended; §14's heavy inbound references make the cost self-evident.
- **Forward-reference to 8c dangles** — if §15 links to a DR section that 8c hasn't shipped yet, `check-links.sh` could fail or the ref dangles. Mitigation: reference §10 / "your RUNBOOK DR section" (which exist today), not an unshipped 8c anchor.
- **Over-prescription** — turning incident response into a rigid checklist that small teams ignore. Mitigation: roles-as-functions ("one person may hold several"), P-tiering the postmortem requirement (required only P0/P1), and naming tooling as Org-owned.
- **Scope creep into 8c (DR/BIA)** — keep contingency/backup-restore drills out; §15 is *response to an incident*, 8c is *continuity/recovery planning*. The framework split (800-61 here, 800-34 in 8c) enforces the boundary.

## 9. Out of scope

- DR / backup-restore drills, BIA, RTO/RPO tiering — that is **8c**.
- Any new conformance `.sh` (incident-handling quality isn't mechanically gradeable).
- On-call/paging tooling, status-page integration — **Org-owned**, named not built.
- Renumbering §5–§14 of STANDARDS.
- Changing PROCESS §9 / §13 substance — 8a only repoints the two dangling refs and the artifact-flow row.

## 10. Definition of Done

- §15 Incident Response appended to STANDARDS (severity matrix, roles-as-functions, response arc, blameless postmortem requirement, action-items-route-back, Org-owned tooling boundary, NIST 800-61 anchor); §14 and all prior sections unrenumbered.
- `templates/POSTMORTEM-TEMPLATE.md` created (nine sections, house style).
- PROCESS §9 lines 212 + 225 repointed to §15; artifact-flow Postmortem row references the template; CLAUDE.md/README template mentions include POSTMORTEM.
- `audit-evidence-checklist.md` Incident-response row added (Manual).
- All conformance green; `check-links.sh` 0; §7 greps pass; kit CI green.
- `VERSION` 2.19.0; CHANGELOG 2.19.0 entry; ROADMAP 8a row.
- Feature branch → PR → **human ratification** (governing-doc surface → **security-owner lens**, per §13/RBAC). Agent never self-merges.
