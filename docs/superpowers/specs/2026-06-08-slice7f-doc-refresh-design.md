# Design — Slice 7f: Doc Refresh & Consistency (Slice 7 closeout)

**Date:** 2026-06-08
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Sixth and final sub-slice of Slice 7. Closes audit gap G12 (doc staleness) + the consistency loose-ends surfaced across the 7a–7e reviews. Plan: `~/.claude/plans/drifting-stirring-thunder.md` §7f.

---

## 1. Goal

A docs-only consistency sweep that closes the kit's accumulated staleness and the loose ends flagged during Slice 7 reviews — no new mechanism, no new contract, no behavior change. The fixes are scoped to **verified** drift (audited, not assumed). MINOR → **2.18.0**.

## 2. Decisions

- **Casing — normalize the ratification-role set to match §2's convention.** §2 renders roles as functions with the **first word capitalized, the rest lowercase** ("Security owner", "Intent owner", "On-call / operator"). The §13 / `ratification-rbac.md` / `audit-evidence-checklist.md` ratification set (Project Owner · Code Owner · Security Owner · Release Manager) is Title-Cased — drift from the kit's own "functions, not titles" principle (§2). Normalize the **whole set** so we don't create a new intra-table inconsistency by touching only "Security owner":
  - **Role labels** (start of a table cell or bold list item): first word capitalized → **Project owner · Code owner · Security owner · Release manager**.
  - **Mid-prose mentions** (inside a sentence): fully lowercase → "a **security-owner-ratified** record", "the **security owner** (≠ requester)", "human approval (**release manager**)".
  - **`CHANGELOG.md` is left untouched** — changelog entries are an append-only historical record; rewriting a shipped entry's casing revises history.
- **CHANGELOG link-defs (G12) — skip.** Audited: the `## [2.x.0]` headers are plain text, not links, so **no broken links exist**. Adding Keep-a-Changelog compare-links would be a net-new cosmetic feature, not a consistency fix (YAGNI).
- **No new conformance check.** Consistency here is low-risk prose; `check-links.sh` already guards link integrity, and the casing/refresh fixes are one-time.

## 3. Deliverables (all verified drift)

| # | File(s) | Fix |
|---|---------|-----|
| A | `DEVELOPMENT-PROCESS.md` (§13 lines 359–362, 245, 366), `docs/enterprise/ratification-rbac.md` (13–16, 25, 27, 28, 34, 43), `conformance/audit-evidence-checklist.md` (7, 58, 60) | Normalize ratification-role casing (labels first-word-capped; prose lowercase) |
| B | `README.md` (~line 60) | Profile list names 7 but **10 ship** — add `data-engineering`, `ml`, `terraform` |
| C | `CLAUDE.md` (the document-set table) | Add `docs/enterprise/` (shipped 6a–6d); refresh the `templates/` row (now also RUNBOOK / FEATURE-REQUEST / SPEC templates); add a `docs/` row (work-tracking, adoption) |
| D | `conformance/README.md` (line 12) | "In the kit's own CI **(a later slice)**" → present tense (the kit now ships `.github/workflows/ci.yml`) |
| E | `conformance/inception-done.sh` (header comment) **and** `conformance/README.md` | Note that `inception-done.sh` is **expected to fail at the kit root** (the kit is the template source, not an instantiated project) — so no future contributor "fixes" it |
| Meta | `VERSION` 2.18.0; `CHANGELOG.md`; `docs/ROADMAP-KIT.md` (7f row, mark Slice 7 complete) |

## 4. Detailed design

### 4.A Ratification-role casing
Per-instance normalization using the rule in §2. The four role names (Project owner · Code owner · Security owner · Release manager) become first-word-capped in table/list **labels** and fully lowercase in **prose**. Hyphenated adjective forms (`Security-Owner-ratified`) → `security-owner-ratified`. `CODEOWNERS` (the GitHub filename, all-caps) is unchanged. The plan enumerates each of the ~18 sites with its exact target string (no ambiguity).

### 4.B README profile count
Replace the 7-name list with all 10 shipped profiles (or a count + representative names that doesn't undercount). Keep the "never limited to them / generate your own" framing intact.

### 4.C CLAUDE.md document-set table
Add rows so the table reflects what actually ships: `docs/enterprise/` (compliance crosswalk, secrets-at-scale, RBAC, audit-evidence — the enterprise addendum), and a `docs/` row covering `work-tracking/adapters.md` + `adoption/brownfield.md`. Update the `templates/` row to list the current template set (PROJECT-CLAUDE, BACKLOG, RUNBOOK, FEATURE-REQUEST, SPEC) or summarize it ("project + intake templates"). Keep the table concise — summarize where a full enumeration would bloat it.

### 4.D conformance/README present-tense
Line 12 currently reads "In the kit's own CI **(a later slice)** — the kit proves it satisfies its own contracts." The kit now has `.github/workflows/ci.yml`. Change to present tense (e.g. "In the kit's own CI — the kit proves it satisfies its own contracts (`.github/workflows/ci.yml`).").

### 4.E inception-done kit-root note
Add a short note in two places so it can't be missed: (1) the `inception-done.sh` header comment, and (2) `conformance/README.md` (near the index row). Content: *this gate is expected to FAIL at the kit root — the kit is the reference/template source, not an instantiated project; it passes only in a project that has completed Inception.* This prevents the recurring "is inception-done broken?" confusion seen across reviews.

## 5. Validation / testing
- `sh conformance/check-links.sh` → 0 (no link broken by the edits; new doc-set rows reference real paths).
- `sh conformance/profile-completeness.sh`, `agent-autonomy.sh`, `container-supply-chain.sh`, `backlog-adapters.sh`, `guard-wired.sh`, `ci-gates.sh` ×10 → green (no regression; docs-only).
- Casing: a post-edit `grep -rn "Security Owner\|Project Owner\|Code Owner\|Release Manager"` over the live docs (excluding `CHANGELOG.md` and `docs/superpowers/`) returns **only** intended forms (i.e. no stray Title-Case ratification role remains, and CHANGELOG history is intact).
- README: the profile list names all 10 shipped profiles (cross-check against `ls profiles/*.md`).
- Kit CI green.

## 6. Risks & mitigations
- **Casing edit misses an instance or over-reaches** (e.g. touches `CODEOWNERS` or CHANGELOG). Mitigation: the plan enumerates each site with exact strings; the §5 grep verifies completeness and that CHANGELOG is untouched.
- **Doc-set table bloat.** Mitigation: summarize the template/docs sets rather than exhaustively listing every file.
- **A "fix" changes meaning.** Mitigation: every edit is casing/wording/enumeration only — no normative content changes; the §13/RBAC role *responsibilities* are unchanged.

## 7. Out of scope
- CHANGELOG compare-links / link-defs (non-actionable — no broken links).
- Any new conformance check or contract change.
- Rewriting `CHANGELOG.md` historical entries (casing or otherwise).
- Renaming roles or changing their responsibilities — casing only.

## 8. Definition of Done
- A–E applied; ratification-role casing consistent (labels first-word-capped, prose lowercase) across the live docs; CHANGELOG history untouched.
- README names all 10 profiles; CLAUDE.md doc-set table reflects `docs/enterprise/` + current templates/docs; conformance/README present-tense + the inception-done-at-kit-root note (also in the script header).
- §5 casing grep shows no stray Title-Case ratification role; all conformance green.
- `VERSION` 2.18.0; CHANGELOG + ROADMAP (7f row, **Slice 7 marked complete**).
- Feature branch → PR → **human ratification** (governing-doc surface → Security-owner lens). Agent never self-merges.
