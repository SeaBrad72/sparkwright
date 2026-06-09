# Slice 7f — Doc Refresh & Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A docs-only consistency sweep closing verified staleness — ratification-role casing, README profile undercount, stale doc-set tables, a future-tense conformance note, and an inception-done-at-kit-root clarification — with zero behavior/contract change.

**Architecture:** Pure Markdown/string edits across governing docs, the enterprise addendum, README, CLAUDE.md, and two conformance files; validated by `check-links.sh` + a casing grep + the full conformance sweep. No new mechanism. MINOR → 2.18.0.

**Tech Stack:** Markdown; POSIX `sh` (one comment-only edit to `inception-done.sh`). No application code, no contract change.

**Spec:** `docs/superpowers/specs/2026-06-08-slice7f-doc-refresh-design.md` (approved). **Branch:** `feature/slice-7f-doc-refresh` (created; spec committed). **Version target:** 2.18.0 (MINOR).

---

## Conventions (read before any task)
- Feature branch → PR → **human ratification**. Agents never self-merge. Governing-doc surface → Security-owner lens.
- **Guard hazard:** the live `.claude/` PreToolUse guard scans Bash command text for destructive literals — never type a recursive-delete. Commit messages are pre-vetted clean.
- **Casing rule (matches §2):** role **labels** at the start of a table cell / bold list item → first word capitalized (`Security owner`); **mid-prose** mentions → fully lowercase (`a security-owner-ratified record`). `CODEOWNERS` (the GitHub filename) is unchanged. **`CHANGELOG.md` is never edited** (append-only history).
- **No normative change:** every edit is casing / wording / enumeration only — no role responsibility or requirement changes.

---

### Task 1: Ratification-role casing normalization (3 files)

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§13 table + §245 env row + §366 prose)
- Modify: `docs/enterprise/ratification-rbac.md` (role table + mapping list + governed-exception prose)
- Modify: `conformance/audit-evidence-checklist.md` (intro + governed-exception + table header)

Apply each exact replacement (old → new). All are unique strings in their file.

- [ ] **Step 1: `DEVELOPMENT-PROCESS.md` — §13 ratification table (4 labels)**

```
| **Project Owner** | requirements   →  | **Project owner** | requirements
| **Code Owner** (per CODEOWNERS) |     →  | **Code owner** (per CODEOWNERS) |
| **Security Owner** | governing-doc   →  | **Security owner** | governing-doc
| **Release Manager** | production     →  | **Release manager** | production
```
Replace these four cell labels in `DEVELOPMENT-PROCESS.md` (lines ~359–362). Concretely:
- `| **Project Owner** | requirements & scope` → `| **Project owner** | requirements & scope`
- `| **Code Owner** (per CODEOWNERS) | code PRs` → `| **Code owner** (per CODEOWNERS) | code PRs`
- `| **Security Owner** | governing-doc changes` → `| **Security owner** | governing-doc changes`
- `| **Release Manager** | production deploys / promotions, rollbacks |` → `| **Release manager** | production deploys / promotions, rollbacks |`

- [ ] **Step 2: `DEVELOPMENT-PROCESS.md` — §245 env row + §366 prose (mid-prose lowercase)**

- `UAT sign-off + **human approval (Release Manager)** |` → `UAT sign-off + **human approval (release manager)** |`
- `An exception is an auditable event: a **Security-Owner-ratified, time-boxed** record` → `An exception is an auditable event: a **security-owner-ratified, time-boxed** record`

- [ ] **Step 3: `docs/enterprise/ratification-rbac.md` — role table (4 labels)**

- `| **Project Owner** | requirements & scope` → `| **Project owner** | requirements & scope`
- `| **Code Owner** (per CODEOWNERS domain) | code PRs` → `| **Code owner** (per CODEOWNERS domain) | code PRs`
- `| **Security Owner** | governing-doc changes` → `| **Security owner** | governing-doc changes`
- `| **Release Manager** | production deploys / promotions, rollback decisions` → `| **Release manager** | production deploys / promotions, rollback decisions`

- [ ] **Step 4: `docs/enterprise/ratification-rbac.md` — mapping list (3 labels) + prose (2)**

- `- **Code Owner** → \`CODEOWNERS\`` → `- **Code owner** → \`CODEOWNERS\``
- `- **Security Owner** → a CODEOWNERS entry` → `- **Security owner** → a CODEOWNERS entry`
- `- **Release Manager** → environment protection` → `- **Release manager** → environment protection`
- `a posture/gate exception requires a **Security-Owner-ratified** record` → `a posture/gate exception requires a **security-owner-ratified** record`
- `| Ratified by | the Security Owner (≠ the requester) |` → `| Ratified by | the security owner (≠ the requester) |`

- [ ] **Step 5: `conformance/audit-evidence-checklist.md` — intro + exception prose + table header**

- `A reviewer (Security Owner for governing controls — see` → `A reviewer (security owner for governing controls — see`
- `a Security-Owner-ratified, time-boxed record (what / why / expiry / compensating control)` → `a security-owner-ratified, time-boxed record (what / why / expiry / compensating control)`
- `| Exception ID | Control waived | Ratified by (Security Owner) | Expires | Compensating control |` → `| Exception ID | Control waived | Ratified by (security owner) | Expires | Compensating control |`

- [ ] **Step 6: Verify — no stray Title-Case ratification role remains in live docs; CHANGELOG untouched**

Run:
```bash
grep -rnE 'Project Owner|Code Owner|Security Owner|Release Manager|Security-Owner|Project-Owner|Code-Owner|Release-Manager' . 2>/dev/null | grep -v docs/superpowers/ | grep -v '.git/' | grep -v CHANGELOG.md || echo "CLEAN: no stray Title-Case ratification role in live docs"
git status --short CHANGELOG.md || true
```
Expected: `CLEAN: no stray Title-Case ratification role in live docs`, and `CHANGELOG.md` is NOT in the modified set. (If any stray match prints, fix that instance to the casing rule. `CODEOWNERS` all-caps filename matches are fine — the grep above is for the spaced/hyphenated role names, which won't match the filename.)

- [ ] **Step 7: Verify links + commit**

```bash
sh conformance/check-links.sh
git add DEVELOPMENT-PROCESS.md docs/enterprise/ratification-rbac.md conformance/audit-evidence-checklist.md
git commit -m "docs(consistency): normalize ratification-role casing to §2 functions convention (labels capped, prose lowercase)"
```
Expected: `check-links.sh` exit 0.

---

### Task 2: README profile list — 7 → 10

**Files:**
- Modify: `README.md` (~line 60, the "Generate your own profile" intro)

- [ ] **Step 1: Name all 10 shipped profiles**

Replace:
```markdown
The kit ships first-class profiles for **TypeScript/Node, Python, Java/Spring, C#/.NET, Go, Rust, and Kotlin** — but it is **never limited to them**. For any other stack:
```
with:
```markdown
The kit ships first-class profiles for **TypeScript/Node, Python, Java/Spring, C#/.NET, Go, Rust, Kotlin, Data Engineering, ML, and Terraform** (10 in all) — but it is **never limited to them**. For any other stack:
```

- [ ] **Step 2: Cross-check the count against shipped profiles**

Run: `ls profiles/*.md | grep -v _TEMPLATE | wc -l`
Expected: `10` (the README now names exactly the shipped set: data-engineering, dotnet, go, java-spring, kotlin, ml, python, rust, terraform, typescript-node).

- [ ] **Step 3: Verify links + commit**

```bash
sh conformance/check-links.sh
git add README.md
git commit -m "docs(readme): name all 10 shipped profiles (was 7)"
```

---

### Task 3: Refresh stale doc-set tables (CLAUDE.md + README "What's inside")

**Files:**
- Modify: `CLAUDE.md` (the "## The document set" table)
- Modify: `README.md` (the "## What's inside" table — `templates/` and `docs/` rows)

- [ ] **Step 1: `CLAUDE.md` — refresh the `templates/` row and add enterprise + docs rows**

In the `## The document set` table, replace the `templates/` row:
```markdown
| **`templates/`** | `PROJECT-CLAUDE-TEMPLATE.md`, `BACKLOG-TEMPLATE.md`. |
```
with:
```markdown
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`. |
```
Then, immediately AFTER the `conformance/` row (the last row, ending `…satisfies its contract.`), add two rows:
```markdown
| **`docs/enterprise/`** | Enterprise addendum — compliance crosswalk, secrets-at-scale, ratification RBAC, audit-evidence (maps the kit's controls to SOC 2 + ISO 27001:2022). |
| **`docs/`** (other) | `work-tracking/adapters.md` (backlog backends), `adoption/brownfield.md` (existing-repo adoption + `.claude/` hygiene). |
```

- [ ] **Step 2: `README.md` — refresh the "What's inside" `templates/` and `docs/` rows**

Replace:
```markdown
| **`templates/`** | `PROJECT-CLAUDE-TEMPLATE.md`, `BACKLOG-TEMPLATE.md`. |
| **`docs/`** | `ADR-000-EXAMPLE.md` — worked stack-decision record. |
```
with:
```markdown
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`. |
| **`docs/`** | `ADR-000-EXAMPLE.md`; `enterprise/` (compliance addendum), `work-tracking/` (backlog adapters), `adoption/` (brownfield). |
```

- [ ] **Step 3: Verify links + commit**

```bash
sh conformance/check-links.sh
git add CLAUDE.md README.md
git commit -m "docs(consistency): refresh doc-set tables (enterprise addendum, current templates + docs)"
```
Expected: `check-links.sh` exit 0 (the new rows reference real paths; they are inline code, not links, so they aren't checked — but confirm green).

---

### Task 4: Present-tense conformance note + inception-done-at-kit-root clarification

**Files:**
- Modify: `conformance/README.md` (line 12; + an inception-done note)
- Modify: `conformance/inception-done.sh` (header comment)

- [ ] **Step 1: `conformance/README.md` — present tense for the kit's own CI**

Replace:
```markdown
- **In the kit's own CI** (a later slice) — the kit proves it satisfies its own contracts.
```
with:
```markdown
- **In the kit's own CI** (`.github/workflows/ci.yml`) — the kit proves it satisfies its own contracts.
```

- [ ] **Step 2: `conformance/README.md` — add the inception-done-at-kit-root note**

Immediately AFTER the Index table's closing (the blockquote line that begins `> The enterprise addendum…`), add a new paragraph:
```markdown

> **Note on `inception-done.sh` at the kit root:** this gate is *expected to FAIL* when run against the kit's own repository — the kit is the reference/template **source**, not an instantiated project (it has no `ADR-000`, `RUNBOOK.md`, etc.). It passes only inside a project that has completed Inception. Do not "fix" the kit root to satisfy it.
```

- [ ] **Step 3: `conformance/inception-done.sh` — header comment note**

In `conformance/inception-done.sh`, the header is:
```sh
#!/bin/sh
# inception-done.sh — verify the Inception-Done gate (START-HERE.md / DEVELOPMENT-PROCESS.md §3)
# in a project directory. Usage: sh conformance/inception-done.sh [dir]   (default: .)
set -eu
```
Insert one comment line after the `Usage:` comment line and before `set -eu`:
```sh
# NOTE: expected to FAIL at the kit root (the kit is the template source, not an
# instantiated project). It passes only in a project that has completed Inception.
```

- [ ] **Step 4: Verify syntax + links + commit**

```bash
sh -n conformance/inception-done.sh && echo "syntax OK"
sh conformance/check-links.sh
git add conformance/README.md conformance/inception-done.sh
git commit -m "docs(conformance): present-tense kit-CI note + inception-done-at-kit-root clarification"
```
Expected: `syntax OK`, `check-links.sh` exit 0.

---

### Task 5: Version, CHANGELOG, ROADMAP (close Slice 7) + full sweep

**Files:**
- Modify: `VERSION` (`2.17.0` → `2.18.0`); `CHANGELOG.md`; `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the sole contents of `VERSION` with:
```
2.18.0
```

- [ ] **Step 2: CHANGELOG block**

Insert after the `Format: …` line (and its blank line), before `## [2.17.0]`:
```markdown
## [2.18.0] - 2026-06-08

Slice 7f — Doc refresh & consistency. Final sub-slice of Slice 7 (adoption/safety hardening). Docs-only; no behavior or contract change.

### Changed
- **Ratification-role casing** normalized to the §2 "functions, not titles" convention (labels first-word-capitalized, prose lowercase) across `DEVELOPMENT-PROCESS.md` §13, `docs/enterprise/ratification-rbac.md`, and `conformance/audit-evidence-checklist.md`. (`CHANGELOG.md` history left untouched.)
- `README.md` now names all **10** shipped profiles (was 7); `README.md` "What's inside" and `CLAUDE.md` document-set tables refreshed to include the enterprise addendum and the current template/docs set.
- `conformance/README.md` describes the kit's own CI in the present tense and adds a note that `inception-done.sh` is *expected to fail at the kit root* (the kit is the template source, not an instantiated project) — also noted in the script header.

### Note
MINOR (2.18.0): documentation consistency only. **Completes Slice 7** (environments & prod safety, personas, containers, work-tracking, brownfield, doc refresh).

```

- [ ] **Step 3: ROADMAP row + mark Slice 7 complete**

In `docs/ROADMAP-KIT.md`, after the `7e ✅` row, insert:
```markdown
| 7f ✅ | **Doc refresh & consistency** *(shipped v2.18.0)* | — (docs only) | ratification-role casing + 10-profile count + doc-set tables + inception-done note | `check-links.sh` + casing grep |
```

- [ ] **Step 4: Full conformance sweep + casing grep**

Run:
```bash
sh conformance/check-links.sh && \
sh conformance/profile-completeness.sh && \
sh conformance/agent-autonomy.sh && \
sh conformance/container-supply-chain.sh && \
sh conformance/backlog-adapters.sh && \
sh conformance/guard-wired.sh && \
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" || break; done && \
grep -rnE 'Project Owner|Code Owner|Security Owner|Release Manager|Security-Owner' . 2>/dev/null | grep -v docs/superpowers/ | grep -v '.git/' | grep -v CHANGELOG.md && echo "WARN: stray Title-Case role remains" || echo "ALL GREEN (casing clean)"
```
Expected: the conformance checks all pass and the final line is `ALL GREEN (casing clean)` (the grep finds nothing in live docs, so the `||` branch prints). (Exclude `inception-done.sh` — fails at kit root by design, now documented.) If a conformance check fails, STOP and report BLOCKED.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.18.0 — doc refresh & consistency (7f); Slice 7 complete"
```

---

### Task 6: Final review + open PR (stop for ratification)

- [ ] **Step 1: Push**

```bash
git push -u origin feature/slice-7f-doc-refresh
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Slice 7f — Doc refresh & consistency (v2.18.0) · Slice 7 complete" --body "$(cat <<'EOF'
## Summary
Docs-only consistency sweep closing verified staleness — no behavior or contract change. **Completes Slice 7.** v2.18.0 (MINOR).

- **Ratification-role casing** normalized to the §2 functions convention (labels first-word-capped, prose lowercase) across §13, `ratification-rbac.md`, `audit-evidence-checklist.md`. `CHANGELOG.md` history untouched.
- **README** names all 10 shipped profiles (was 7).
- **Doc-set tables** (CLAUDE.md + README "What's inside") refreshed: enterprise addendum + current templates/docs.
- **conformance/README** present-tense kit-CI note + an `inception-done.sh`-fails-at-kit-root clarification (also in the script header) so it isn't "fixed" later.
- Skipped (audited non-issue): CHANGELOG link-defs — the headers aren't links, nothing is broken.

## Governance
Governing-doc surface (§13 / enterprise RBAC) → Security-owner lens. Casing/wording only — zero normative change to any role's responsibilities. Agent did not self-merge; awaiting human ratification.

## Conformance
check-links · profile-completeness · agent-autonomy · container-supply-chain · backlog-adapters · guard-wired · ci-gates ×10 — all green. Casing grep: no stray Title-Case ratification role in live docs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: STOP**

Report the PR URL and stop. Do not merge — Bradley ratifies. Slice 7 is complete when this PR is open and green.

---

## Notes for the executor
- **Dependency order:** Tasks 1–4 are independent docs edits; Task 5 (meta + sweep) depends on all prior. Run in order or parallel-safe per file.
- **Casing is the one substantive task:** Task 1 Step 6's grep is the proof — no stray Title-Case ratification role in live docs, and `CHANGELOG.md` untouched. That grep is the slice's regression check.
- **Never edit `CHANGELOG.md` for casing** — it is append-only history (only Task 5 adds a NEW entry).
- **Do not touch** any `.sh` logic, `.claude/`, profiles, or `ci.yml` — 7f changes only docs + one comment line in `inception-done.sh`.
