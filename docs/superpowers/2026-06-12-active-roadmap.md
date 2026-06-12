# Active Roadmap & Working Plan — agentic-sdlc-kit (post-compaction continuity)

**As of v2.54.0 (2026-06-12).** This is the working plan for what's next, written so the work survives a context compaction. Execute top-down.

## Current state
- **Latest merged:** v2.53.0 (MP-1 test-quality), v2.52.0 (Safe Non-Prod arc). Earlier this session: Responsible-AI arc (v2.48–2.50), guard-hole closures (#64), anonymization (#62/#63).
- **OPEN PR awaiting Bradley's merge: #66** — "MP-2 dev inner loop + test-quality/inner-loop tooling across ALL 10 profiles + _TEMPLATE + MAINTAINING rule" (v2.54.0). Reviewed SHIP. **MERGE THIS FIRST.**

## Standing conventions / invariants (DO NOT VIOLATE — they govern every slice)
- **Bradley merges every PR** via `gh pr merge <n> --squash --admin --delete-branch`. **The agent NEVER self-merges.** Agent opens the PR, reports the number + merge command.
- **Builder ≠ sole reviewer:** dispatch an independent review (security-reviewer subagent) before every PR. Governing-doc / guard / security changes get the **security-owner lens**.
- **Control-plane is human-only:** the guard blocks the agent from editing `.claude/*`, `.github/workflows/*`, CODEOWNERS, `.git/*`, `hooks/pre-push`, `scripts/kit-guard`. For those, the agent **prepares the exact diff** and Bradley hand-applies it. Prefer giving him a `sed` one-liner or a precise editor find-and-replace; **never a `#`-comment-as-edit inside a runnable block** (that silently no-ops — it bit us once).
- **CI step folds into the slice PR:** if a slice adds a new conformance script, its `--selftest` CI step is applied by Bradley **on the slice branch before merge** (one PR, one merge) — not a separate follow-up PR.
- **Anonymization ([[kit-anonymization]]):** the shippable kit stays generic — no "PBS"/personal/product-name references (repo URLs are the only exception; LICENSE keeps "Bradley James" by his choice). PBS-specific work = a **private overlay**, never baked into the general release.
- **Honesty invariant:** a green check proves a posture is *declared/recorded*, never that it *works*. "necessary, not sufficient." `verify.sh` splits control vs doc checks; UNVERIFIED ≠ pass.
- **Doc-budget caps (core-3):** CLAUDE.md ≤120, DEVELOPMENT-PROCESS.md ≤470 (currently ~468 — VERY tight), DEVELOPMENT-STANDARDS.md ≤320 (currently 316). Prefer append-to-existing-line (+0). Run `conformance/doc-budget.sh` after every core-doc edit.
- **Readiness-check family pattern** (mirror an existing one — `observability-ready.sh` / `resilience-ready.sh` / `test-data-ready.sh`): conditional trigger (deploy-surface = Dockerfile or deploy workflow; data-surface = `dr-ready.sh`'s `has_data_surface`) → N/A · OK · FAIL · `--selftest` with mktemp fixtures left in place (7e guard, no `rm -rf`) → wire into `verify.sh` (`check doc`) + CI selftest + README + audit-evidence rows. **Colon-adjacent record line** in the RUNBOOK (the SNP-1 lesson: `**Key:** [placeholder]`, never a parenthetical before the colon, or a filled value false-FAILs). **Always coupling-test BOTH paths: fresh template → FAIL and filled-value → OK.**
- **Per-slice flow:** brainstorm (if design choices) → spec in `docs/superpowers/specs/` → plan in `docs/superpowers/plans/` → build → independent review → PR → Bradley merges → sync main.
- **MAINTAINER rule (just added):** cross-cutting per-stack tooling must reach ALL applicable profiles + `_TEMPLATE`, not just the representatives (recommended tooling isn't conformance-enforced).

## THE QUEUE (in order)

### 0. Merge PR #66 (Bradley) — closes the tooling-depth gap.

### 1. ★ NEXT BUILD — Profile-depth: deployable artifacts (the measured gap)
**Problem (measured):** only `typescript-node` ships the concrete deployable companions — `Dockerfile`, `compose.yaml`, `deploy/` (k8s + Helm), `ci.gitlab-ci.yml`. The other 9 stacks get full `.md` guidance + a gated `ci.yml` but **no drop-in container/deploy artifacts**. The contract + gates + tooling are even; the shipped *artifacts* are not.

**Decision (Bradley approved "complete it"):**
- **Ship full container/deploy companions for the 6 service stacks** that deploy as containers: **java-spring, kotlin, dotnet, go, rust, python**. Each gets a stack-appropriate `Dockerfile` (multi-stage, non-root, minimal/distroless where apt — they genuinely differ: distroless-Python, JRE-slim/chiseled-JVM, chiseled-.NET, scratch/static-Go, distroless-Rust), a `compose.yaml` (app + its datastore for local parity), and a `deploy/` reference (k8s manifest + optional Helm values) mirroring `profiles/typescript-node/deploy/`. Wire the **image supply-chain** into each profile's `ci.yml`: `gate-image-sbom` + `gate-image-provenance` (build image → SBOM via Syft/Trivy → `attest-build-provenance` on the **image digest**), reusing the push-only OIDC provenance-job pattern. Verified by `conformance/container-supply-chain.sh`.
- **Reference-pattern (NOT a generic web-Dockerfile) for ml / data-engineering / terraform** — their deploy stories differ (model-serving, orchestrated batch, IaC-is-the-deploy). Instead: each `.md` explicitly points to the pattern + documents its stack-specific container/deploy notes (ml: serving image / batch job; data-eng: orchestrated job image; terraform: N/A — the plan/apply IS the deploy). Mark this a conscious convention in MAINTAINING.
- **Fix the known DevOps-audit nit while here:** `conformance/container-supply-chain.sh` is self-tested but NOT wired into kit CI or `verify.sh` — add it (conditional on a Dockerfile, like the other conditional checks) so the image gates are regression-guarded for all the new Dockerfiles.

**Build approach:** likely 2–3 PRs (e.g. service stacks in batches of 2–3 to keep each PR reviewable), each: per-stack Dockerfile+compose+deploy + ci.yml image-gate wiring (ci.yml edits = control-plane → Bradley hand-applies the image-gate steps, OR the profile `ci.yml` is NOT control-plane since it's `profiles/<stack>/ci.yml`, not `.github/workflows/` — **CONFIRM: profiles/*/ci.yml is agent-editable; only the kit's own `.github/workflows/ci.yml` is guarded**). Run `conformance/ci-gates.sh profiles/<stack>/ci.yml` + `profile-completeness.sh` after each. Independent review per PR. Release MINOR per batch.
**Reuse:** `profiles/typescript-node/{Dockerfile,compose.yaml,deploy/,ci.yml}` as the reference; the `gate-image-sbom`/`gate-image-provenance` pattern; `conformance/container-supply-chain.sh`.

### 2. MP-3 — agentic-ops (BRAINSTORM first, then build)
- **Agent-run observability / trace** — tool-call sequence, decisions, retries, latency, token-cost per task (OTel-GenAI / Langfuse-style). The kit governs agent *spend* (STANDARDS §2) but not the *execution trace*.
- **Agent-behavior / process-conformance evals** — eval the agent's SDLC adherence over time (writes tests, doesn't skip gates, mergeable PRs) — eval-driven development pointed at the agent.
- Needs design decisions (artifact shape, what's observed vs gated, tool-neutrality) → dedicated brainstorm.

### 3. Developer-journey-aware support (folds in TDD teaching)
- Detect where someone is (seasoned engineer ↔ brand-new "vibe coder") and meet them at the right scaffolding/guidance level. **Fold in the TDD red-green-refactor teaching** (the audit's "TDD asserted but not taught" gap — a vibe-coder gets the walkthrough; a senior skips it). Also surface mutation/property test-quality here.
- Brainstorm-first (UX/journey-detection design choices).

### 4. Product & Design process integration (generic stub + private PBS overlay)
- A **generic, stubbed** layer with clean extension points so any org plugs in its product/design process (general anonymized release). **Then** a separate **private PBS overlay** reflecting PBS's deeper product process (PBS has done more work on that part).
- This is also where the **pre-story discovery front end** lives (the audit's HIGH gap): raw-signal → opportunity → validated-problem → Ready-story; opportunity/validation artifact + defined validation method + triage owner/ritual; prioritization method (RICE/WSJF); end-user JTBD/persona artifact; deeper Designer lane.
- Keep the general release anonymized; the PBS overlay is private. Brainstorm-first.

## Deferred / noted (not lost)
- Container/deploy for ml/data-eng/terraform = reference-pattern (item 1, option 2).
- Eval-gate teeth only in ML profile — a stack-neutral `gate-eval` reference would give AI features on non-ML stacks CI enforcement (audit finding).
- Error-budget burn-rate alerting guidance (DevOps audit, Low).
- Contract-testing (Pact) reference; semantic-release automation — minor.
