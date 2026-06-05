# Changelog

All notable changes to the Agentic SDLC Kit are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-06-05

Slice 1 — CI/CD. Raises the supply-chain posture to the baseline for all projects (new required gates → MAJOR per `MAINTAINING.md` §2).

### Added
- `DEVELOPMENT-STANDARDS.md` §14 **CI/CD Pipeline** — 7 required per-PR gates (lint, type-check, test+coverage≥80%, build, secret-scan, dependency scan, SBOM+provenance) + branch protection (main protected, green-CI-to-merge, builder≠sole-merger).
- TypeScript reference pipeline in `profiles/typescript-node/`: `ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`.
- `conformance/ci-gates.sh` — asserts a workflow declares every required gate; `conformance/check-links.sh` — relative-link integrity check.
- `.github/workflows/ci.yml` — the kit's own CI (conformance + docs links): the kit now dogfoods its gate.

### Changed
- `DEVELOPMENT-PROCESS.md` §10 — supply-chain integrity moves from optional configuration hook to **required CI gates**; §15 — recurring audit reframed as the deeper periodic complement to the per-PR gate.
- `profiles/typescript-node.md` §4 — points to the concrete reference files.
- `docs/ROADMAP-KIT.md` — Slice 1 marked done.

## [1.0.0] - 2026-06-05

First product release — the kit becomes a versioned, drop-in template framework.

### Added
- `LICENSE` (Apache-2.0) — the kit is now licensed for distribution.
- `VERSION` + this `CHANGELOG.md` — the kit is a semver'd product.
- `MAINTAINING.md` — the contract/reference/conformance convention, and how the kit is versioned, released, and contributed back to (the kit dogfoods its own loop).
- `conformance/` — the conformance-check pattern and `15-factor-checklist.md` (the first check, filled for the TypeScript/Node reference profile).
- `DEVELOPMENT-STANDARDS.md` §13 — **15-Factor Architecture**: a binding, conditional-by-project-type contract mapping all 15 factors to where the kit enforces them. Adds previously-uncovered factors: dependencies, disposability, backing services, dev/prod parity, statelessness, concurrency, and telemetry depth.
- `docs/ROADMAP-KIT.md` — the kit's own backlog: the six remaining contract/reference/conformance slices, sequenced.
- "Kit version adopted" field in `templates/PROJECT-CLAUDE-TEMPLATE.md` — projects record the kit version they run.

### Changed
- `DEVELOPMENT-PROCESS.md` §7 — the Review gate adds a conditional **15-Factor conformance** check; §8 — the L3 process retro now routes kit-level improvements upstream as a PR to the canonical kit.
- `README.md` — version surfaced; "How the kit is built" (the contract/reference/conformance convention) added; license declared.

[2.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.0.0
[1.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v1.0.0
