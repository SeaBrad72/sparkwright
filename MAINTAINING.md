# Maintaining the Kit

## 1. The artifact convention: Contract · Reference · Conformance

Every capability the kit ships has three parts. This is the same "universal standard + profile" split the kit already uses, generalized to every artifact.

| Part | What it is | Where it lives | Binding? |
|------|-----------|----------------|----------|
| **Contract** | The stack-neutral requirement — *what must be true* | `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md` | **Yes** — law |
| **Reference implementation** | A working, adaptable artifact — *one way to satisfy it* | `profiles/<stack>.md`, repo root, or `.claude/` | No — copy & adapt |
| **Conformance check** | An executable script or checklist — *proof the impl satisfies the contract* | `conformance/` | **Yes** — must pass |

**The rule for adopters:** you may rewrite any reference implementation freely — change the CI file, swap the stack, restructure the scaffold — **as long as the matching conformance check still passes.** The contract is law; the implementation is yours.

Container artifacts (`Dockerfile`, `compose.yaml`, `deploy/`) ship for the 7 *service* profiles only; `ml`, `data-engineering` and `terraform` ship a reference-pointer in §9 instead, by design.

A recommended per-stack practice reaches every applicable profile and `profiles/_TEMPLATE.md`, or none.

**Worked example (CI/CD):**
- *Contract* — `DEVELOPMENT-STANDARDS.md` §14: "CI MUST run the seven required gates — lint, type-check, test+coverage≥80%, build, secret scan, dependency scan, supply-chain integrity (SBOM + provenance); `main` is protected; the builder is never the sole merger."
- *Reference* — `.github/workflows/ci.yml` in the TypeScript profile, marked "copy & adapt to your stack."
- *Conformance* — `conformance/ci-gates.<ext>` that asserts each gate fires.

A team on Python deletes the Node workflow, writes their own, and stays conformant because the gates still fire.

## 2. Versioning

- The canonical version lives in `VERSION` (single line) and is mirrored by the top entry of the project's changelog (`CHANGELOG.md` in this repo; each project keeps its own).
- **Semantic versioning** applied to *governance impact*, not lines of prose:
  - **MAJOR** — a change to a binding contract that existing adopters must act on (a new required gate, a removed guarantee).
  - **MINOR** — additive: a new reference implementation, a new profile, a new optional capability.
  - **PATCH** — clarifications, typo fixes, non-binding wording.
- Adopting projects record the version they took in their `CLAUDE.md` (`Kit version adopted: vX.Y.Z`), so drift is visible.
- On the 3.x line a release can carry acts you must take with no major bump, and the release note lists them (conduct, not enforced).

A downstream retro's kit-level learning goes in that project's own backlog, where its owner ratifies or declines it.

The kit maintainers' own rules are in `docs/kit-internals/maintaining.md` (kept with the kit maintainers' tree; not in your export).
