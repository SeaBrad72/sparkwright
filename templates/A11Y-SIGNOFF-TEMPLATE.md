# Accessibility Sign-off

> **Template.** Delete this guidance line; fill the table — replace every `[replace: …]` / `[describe evidence: …]` / `[your name]` stub. The auditable evidence for the Definition-of-Done **Accessibility** item (`CLAUDE.md`). Designer (or the a11y owner) signs at Review. Keep it a structured record, not prose.
>
> **Where it must live:** `conformance/a11y-obligation.sh` reads **`A11Y-SIGNOFF.md` at the repository root** — a change touching a user-facing UI surface requires it present **and filled**. Copy it elsewhere (`docs/sign-offs/`, the PR body) for history if you like, but the root file is the one the gate reads; filed only elsewhere, the gate reds with "absent".

| Field | Value |
|-------|-------|
| Gate | Accessibility (WCAG 2.1 AA) |
| Feature / story | [replace: link to feature/story] |
| Keyboard-navigable | [replace: pass / fail] |
| Screen-reader | [replace: pass / fail] |
| Contrast ≥ 4.5:1 (3:1 large) | [replace: pass / fail] |
| Visible focus indicator | [replace: pass / fail] |
| prefers-reduced-motion respected | [replace: pass / fail / N/A] |
| Tool evidence | [describe evidence: axe / Lighthouse run link + score] |
| Decision | [replace: **pass** / fail] |
| Signer (role) | [your name] (Designer / a11y owner) |
| Date | [replace: YYYY-MM-DD] |
| Notes | |
