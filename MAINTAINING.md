# Maintaining the Kit

How the Agentic SDLC Kit is **built, versioned, and evolved**. The kit is an internal platform product: it is released with semver, it has a `CHANGELOG`, and — critically — **it is built with the same loop it prescribes**. This file governs the kit itself; it is not copied into adopting projects.

---

## 1. The artifact convention: Contract · Reference · Conformance

Every capability the kit ships has three parts. This is the same "universal standard + profile" split the kit already uses, generalized to every artifact.

| Part | What it is | Where it lives | Binding? |
|------|-----------|----------------|----------|
| **Contract** | The stack-neutral requirement — *what must be true* | `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md` | **Yes** — law |
| **Reference implementation** | A working, adaptable artifact — *one way to satisfy it* | `profiles/<stack>.md`, repo root, or `.claude/` | No — copy & adapt |
| **Conformance check** | An executable script or checklist — *proof the impl satisfies the contract* | `conformance/` | **Yes** — must pass |

**The rule for adopters:** you may rewrite any reference implementation freely — change the CI file, swap the stack, restructure the scaffold — **as long as the matching conformance check still passes.** The contract is law; the implementation is yours.

**Maintainer rule — cross-cutting per-stack tooling reaches *all* profiles or none.** The contract + the §14 gates are conformance-enforced across all 10 profiles (`profile-completeness.sh`, `ci-gates.sh`). But *recommended per-stack tooling* added to a section's content (e.g. test-quality, the inner loop) is **not** conformance-checked — so adding it to only the "representative" `typescript-node`/`python` profiles leaves the other stacks thinner without the net catching it. When you add a cross-cutting recommended practice, add its per-stack tooling line to **every applicable profile and `profiles/_TEMPLATE.md`** (the source for new stacks), or don't add it piecemeal.

**Worked example (CI/CD):**
- *Contract* — `DEVELOPMENT-STANDARDS.md`: "CI MUST enforce lint, type-check, test+coverage≥80%, build, and secret-scan; `main` is protected; the builder is never the sole merger."
- *Reference* — `.github/workflows/ci.yml` in the TypeScript profile, marked "copy & adapt to your stack."
- *Conformance* — `conformance/ci-gates.<ext>` that asserts each gate fires.

A team on Python deletes the Node workflow, writes their own, and stays conformant because the gates still fire.

---

## 2. Versioning

- The canonical version lives in `VERSION` (single line) and is mirrored by the top entry of `CHANGELOG.md`.
- **Semantic versioning** applied to *governance impact*, not lines of prose:
  - **MAJOR** — a change to a binding contract that existing adopters must act on (a new required gate, a removed guarantee).
  - **MINOR** — additive: a new reference implementation, a new profile, a new optional capability.
  - **PATCH** — clarifications, typo fixes, non-binding wording.
- Adopting projects record the version they took in their `CLAUDE.md` (`Kit version adopted: vX.Y.Z`), so drift is visible.

## 3. Releasing (platform team)

1. Land the change on a feature branch via PR (the kit's own loop — see §5).
2. Bump `VERSION`; add a dated `CHANGELOG.md` entry under the new version.
3. Merge to `main`; tag `vX.Y.Z`; the tag is the release.

## 4. Contributing back (the closed loop, applied to the kit)

The kit is improved by the teams using it. When a downstream team's **L3 process retro** (`DEVELOPMENT-PROCESS.md` §8) surfaces a kit-level improvement — a clearer standard, a better reference impl, a missing conformance check — it does **not** stop at the local copy:

1. The team opens a **PR against the canonical kit** describing the improvement and the retro that motivated it.
2. **Agents propose, humans ratify** — the kit's standing rule. A human maintainer reviews and accepts/declines.
3. Accepted changes ship in the next release and flow to every adopter via §2.

This is what makes the kit *self-iterating*: the MD files, scripts, and reference impls are all subject to the same retrospective-and-refactor loop the kit prescribes for product code. A retro that changes nothing is theater — here, kit-level learning lands upstream.

## 5. The kit dogfoods its own loop

The canonical kit repo runs the process in `DEVELOPMENT-PROCESS.md`: feature branches → PR → human ratification for any change to governing docs; its own `CHANGELOG`; its own backlog (`docs/ROADMAP-KIT.md`); its own L3 retros. If a rule is too heavy to follow on the kit itself, that is evidence to fix the rule.

---

**Last Updated:** 2026-06-12
