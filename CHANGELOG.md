# Changelog

All notable changes to the Agentic SDLC Kit are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.39.0] - 2026-06-10

A7 residual cleanup (Slice 10). Clears the small backlog the arc-closure re-review surfaced. **MINOR** — additive checks/docs + one guard over-block lifted; no governance bar lowered.

### Added / Changed
- **`preflight.sh`** soft-recommends `gh` + auth for GitHub flows (warns, never fails — GitLab/ADO unaffected).
- **Solo/lite track** now sets `enforce_admins: false` so the owner admin-merge self-ratification actually works (flip to `true` with a second reviewer); the reference `BRANCH-PROTECTION.md` carries a solo note. Conformance unaffected (`branch-protection.sh` never asserted `enforce_admins`).
- **`tracker-contract.sh --deep`** introspects the Jira workflow and **verifies** the Only-Assignee transition condition (the atomic claim moves from *attested* to *verified*); three-state, fixture-tested.
- **Brownfield guide** instructs adding `.claude/settings.local.json` to the adopter's own `.gitignore`.
- **Guard:** lifted the over-block on the reversible `git commit --amend` (force-push / non-fast-forward / `reset --hard` stay denied); regression-locked by an `agent-autonomy.sh` allow-case.

## [2.38.0] - 2026-06-10

Core-doc trim (Slice 9k-b, fast-follow of 9k). A measurement-first pass that **confirmed the core governing docs were already lean** (the Slice 9 arc had added only ~39 lines to the core-3, and the economics win was already banked by 9k's on-demand `AGENTS.md`), tightened the one doc with genuine cruft, and installed a ratchet so they can't silently re-bloat. **MINOR** — no governance content removed; every normative line, gate, and conformance marker preserved (proven by the full suite staying green).

### Changed
- **`DEVELOPMENT-PROCESS.md`** (466→462 lines) — removed stale metadata, a non-normative aside, and a redundant re-listing of the conditional gates (the §7 table already annotates them); no section renumbered. **`DEVELOPMENT-STANDARDS.md`** and **`CLAUDE.md`** were reviewed and left unchanged — already tight, no safe cut without losing substance.

### Added
- **`conformance/doc-budget.sh`** — a per-doc + core-3 line-budget ratchet (CLAUDE.md ≤120, DEVELOPMENT-PROCESS.md ≤470, DEVELOPMENT-STANDARDS.md ≤310, core-3 ≤890); a future PR that re-bloats a core doc fails CI. Budgets raised only by a ratified PR. `--selftest`, CI-gated.

## [2.37.0] - 2026-06-10

Hosted-tracker bootstrap (Slice 9h, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Turns hosted-tracker adoption from prose into a concrete setup artifact plus a contract verifier. **MINOR** — templates + an incept arm + a three-state conformance check; no API client shipped.

### Added
- **`templates/JIRA-SETUP-TEMPLATE.md`** — `incept --backlog jira` emits a project-stamped guide: the six §6 statuses, Size/Risk fields (not Story Points), and the step-by-step **Only-Assignee transition condition** (the server-enforced single-owner claim).
- **`templates/TRACKER-SETUP-TEMPLATE.md`** — convention-tier stub for github/ado/linear/gitlab (board = the six states; claim = assign-when-empty + re-read).
- **`conformance/tracker-contract.sh`** — three-state Jira §6 verifier: live REST checks the states + Size/Risk fields, **UNVERIFIED (exit 2)** without creds, `--selftest` proves the logic in CI. The Only-Assignee condition is **attested, not auto-verified** (honest about REST's limits).

### Changed
- **`scripts/incept.sh`** now writes the matching setup artifact for the chosen backend (`md`→BACKLOG.md unchanged).
- **`docs/work-tracking/adapters.md`** (Jira) points at the bootstrap + verifier.

## [2.36.0] - 2026-06-10

Best-practice fidelity (Slice 9j, Stage V of the "Honest Assurance & Adoption Reach" arc). Declares the kit's SLSA level, adds a NIST SSDF crosswalk, formalizes a11y/load/eval as conditional gates, and makes the reference pipeline satisfy its own SHA-pinning contract. **MINOR** — the a11y/load/eval fork resolved in favor of *honest conditional gates*, not a new universal gate, so no MAJOR.

### Added
- **SLSA Build L2 declaration** (`DEVELOPMENT-STANDARDS.md` §14) — authenticated, service-generated provenance bound to the artifact/image digest; the honest L3 path documented (not claimed).
- **NIST SSDF (SP 800-218) column** in `docs/enterprise/compliance-crosswalk.md`, alongside SOC 2 + ISO 27001:2022.
- **Commit & tag signing** subsection (`DEVELOPMENT-STANDARDS.md` §2) — Sigstore `gitsign` / GPG, recommended hardening (not a gate).
- **`conformance/conditional-gates.sh`** + **`conformance/action-pinning.sh`** drift-guards (`--selftest`), CI-gated.

### Changed
- **a11y / load / eval formalized as conditional gates** (§7 + §14 + DoD): first-class but trigger-bound (UI / service / AI), N/A-with-reason otherwise — not universal. No new universal required gate.
- **`profiles/typescript-node/ci.yml`** now SHA-pins every `uses:` (with `# vX` comments; Dependabot keeps them current) — the canonical reference satisfies its own pinning contract.

## [2.35.0] - 2026-06-10

Economics & hygiene (Slice 9k, Stage V of the "Honest Assurance & Adoption Reach" arc). A load-first agent brief, one canonical home per governance concept, and a self-healing version badge. **MINOR** — additive brief + two completeness checks + label-only doc edits; no governing rule changed.

### Added
- **`AGENTS.md`** — a ≤1-page load-first operating brief (loop · gates · security · agent boundary · stack), each with a §-pointer; an index that defers to `CLAUDE.md`. Instructs agents to expand a full doc only when the task touches it — turning the standing per-feature governance load into an on-demand pull.
- **`conformance/badge-version.sh`** — asserts the README badge equals `VERSION`; `--fix` rewrites it; `--selftest`. The release flow calls `--fix`, ending the recurring badge drift (was 10 versions stale).
- **`conformance/agents-brief.sh`** — keeps `AGENTS.md` a brief: exists, points at the canonical docs, within a line-bound; `--selftest`.

### Changed
- **One canonical home per concept:** the §7 Definition-of-Done gate now points at `CLAUDE.md` (its real home); the `CLAUDE.md` security section is labeled the authoritative summary and `DEVELOPMENT-STANDARDS.md` §2 its expansion — the layering is explicit, no rule changed.
- **README version badge** synced to the current release (no longer stale).

## [2.34.0] - 2026-06-10

Definition-of-Ready robustness (Slice 9i-b, fast-follow of 9i). Promotes the DoR from a scattered parenthetical to a first-class enumerated entry gate, peer to the DoD. **MINOR** — additive block + template checklist + a completeness check; the Definition of Done is unchanged.

### Added
- **`CLAUDE.md` — `## Definition of "Ready"`** entry gate above the DoD: 4 mandatory items (acceptance criteria · INVEST-sliced · deps known · success metric/hypothesis) + 4 conditional flags that map to existing §7 gates (threat-model / UX-a11y / eval / compliance). Frames DoR (entry) vs DoD (exit).
- **`templates/FEATURE-REQUEST-TEMPLATE.md` — `## Definition of Ready`** checklist so an item is filled-to-ready at intake.
- **`conformance/dor-defined.sh`** — completeness drift-guard (DoR enumerated in `CLAUDE.md` + referenced by the gate doc + carried by the intake template); `--selftest`. CI-gated.

### Changed
- **`DEVELOPMENT-PROCESS.md` §7/§11/§4** DoR references now point at the canonical `CLAUDE.md` entry gate (no list duplication).
- **`templates/BACKLOG-TEMPLATE.md`** "Ready" column points at the enumerated DoR.

## [2.33.0] - 2026-06-10

Persona symmetry (Slice 9i, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the SDLC-personas finding (review 6/10): QA and Designer were named with "→ exit artifact" promises that dissolved. **MINOR** — additive templates + annotations + a completeness check; no new DoD requirement.

### Added
- **`templates/TEST-PLAN-TEMPLATE.md`** — QA's dedicated artifact (scope, levels, cases↔acceptance-criteria traceability, environments, entry/exit).
- **`templates/UAT-SIGNOFF-TEMPLATE.md`** / **`templates/A11Y-SIGNOFF-TEMPLATE.md`** — auditable per-gate sign-off records (signer/date/gate/evidence/decision; the a11y one carries the WCAG 2.1 AA checklist + axe/Lighthouse evidence).
- **`conformance/persona-artifacts.sh`** — completeness drift-guard (templates exist + named in the §2 persona table); `--selftest`. CI-gated.

### Changed
- **`DEVELOPMENT-PROCESS.md` §2 persona table annotated** dedicated-vs-shared (PO/QA/Designer own dedicated artifacts; DevOps/SRE works through the RUNBOOK) — the asymmetry is now explicit, not over-promised. §9 UAT gate and §5 Designer lens reference their sign-off records.
- **`CLAUDE.md` DoD Accessibility line** names `A11Y-SIGNOFF` as its auditable evidence (no new requirement).

## [2.32.0] - 2026-06-10

Stack-decision aid (Slice 9g, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the stack-undecided persona (review 5/10): the "⭐ key step" now has comparison material, and `incept` no longer silently defaults. **MINOR** — additive docs + a notice + a completeness check.

### Added
- **`docs/STACK-SELECTION.md`** — comparison matrix across all 10 profiles (Best for / Avoid when / domain), per-stack blurbs, and full-stack (SPA + API) / polyglot guidance.
- **`## Best for / Avoid when`** sections in all 10 `profiles/<stack>.md`, each pointing at the guide.
- **`conformance/stack-selection.sh`** — completeness drift-guard (guide present · every profile has the section · a matrix row per profile); `--selftest`. CI-gated.

### Changed
- **`incept` no longer silently defaults the stack** — prints a loud notice + the guide pointer when no `--stack` is given (the default still works; automation unaffected).
- `START-HERE.md` §2 and `README.md` link the decision aid; `conformance/README.md` indexes the check.

## [2.31.0] - 2026-06-10

Beginner on-ramp (Slice 9f, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the lowest-scoring review persona (beginner, 4/10), aimed by the A6 dogfood: the mechanical bootstrap was already fine; the friction was cognitive. **MINOR** — additive script + docs.

### Added
- **`scripts/preflight.sh`** — fail-fast prerequisite check (universal jq/git/sh always; optional `--stack <name>` toolchain) with install hints; `--selftest`. `incept` runs it at startup and aborts on a missing universal prerequisite.
- **`GLOSSARY.md`** — one-page launchpad for the ~12 load-bearing terms, each linking to its authoritative section.
- **Solo / lite track** in `START-HERE.md` — how one person satisfies builder≠reviewer (owner admin-merge as logged self-ratification) and which gates are deferrable at Stage 1.

### Changed
- **`incept` discloses the `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename** (banner) — closing A6 finding F2.
- `START-HERE.md` / `README.md` point newcomers at preflight + the glossary; `conformance/README.md` indexes the preflight selftest (CI-gated).

## [2.30.0] - 2026-06-10

Exec brief + org rollout + ROI model (Slice 9e, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the review's eng-leader finding — credible audit substance but no leadership front door. **MINOR** — additive docs; no new conformance gate (an exec brief is not a verifiable control).

### Added
- **`docs/enterprise/EXEC-BRIEF.md`** — ≤2-page VP/CTO entry point: what / why / what-you-get, A5-grounded differentiation, honest boundaries, compliance-at-a-glance, pointers.
- **`docs/enterprise/ORG-ROLLOUT.md`** — Pilot→Expand→Fleet adoption, the canonical **Stage 1–4 "tighten at scale"** maturity model, and the fleet version-upgrade process.
- **`docs/enterprise/ROI-MODEL.md`** — parameterized ROI worksheet (adopter inputs + three value levers) and one labeled worked example; honest "planning model, not a result" framing.
- **`docs/superpowers/reviews/2026-06-10-competitive-benchmark.md`** — the A5 record behind the brief's differentiation (with sources).

### Changed
- Leadership cross-links from `README.md` / `START-HERE.md` / `docs/enterprise/README.md`.
- **Fixed the dangling "Stage 1–4" reference**: `DEVELOPMENT-PROCESS.md` and `docs/operations/dora-metrics.md` now point at the canonical model in `ORG-ROLLOUT.md`.
- **Anonymized** remaining shippable references (ROADMAP goal line + owner) to a generic regulated-enterprise archetype.

## [2.29.0] - 2026-06-10

Runtime-guard portability (Slice 9d-b, Tier 1 of the "Honest Assurance & Adoption Reach" arc). The destructive-action guard previously protected only the Claude Code runtime; now the red-teamed deny-matrix is a sourceable single source of truth reused by a universal git pre-push hook and a `kit-guard` CLI, so other runtimes and humans inherit the same denials. **MINOR** — additive; the Claude path is proven behavior-identical, no new universally-required CI gate.

### Added
- **`.claude/hooks/guard-core.sh`** — the deny-matrix as pure functions (`guard_check_command` / `guard_check_path` / `guard_check_push`) + the 9b control-plane helpers. Single source of truth.
- **`hooks/pre-push`** — universal git hook (any runtime + humans): blocks force-push / push-to-main from real refs, before the network round-trip; `--no-verify` is the deliberate override. `--selftest`.
- **`scripts/kit-guard`** — portable CLI (`cmd` / `path` / `--selftest`) any non-Claude runtime pipes proposed actions through.
- **`conformance/guard-core-sourced.sh`** — proves every consumer sources the one core (anti-fork).
- **`docs/operations/runtime-guards.md`** — one matrix, three surfaces; runtime wiring; Windows = WSL/Git-Bash; PATH-shims named as the coverage-depth upgrade; honesty boundary.

### Changed
- **`.claude/hooks/guard.sh`** slimmed to a thin Claude PreToolUse adapter over `guard-core.sh`; behavior proven identical via `conformance/agent-autonomy.sh`.
- **`scripts/incept.sh`** installs the pre-push hook by default (brownfield-safe; never clobbers an existing hook).
- **`conformance/agent-autonomy.sh`** denies edits to the new control-plane files (guard-core / kit-guard / pre-push); kit CI gates the three new selftests.

## [2.28.0] - 2026-06-09

CI-platform portability (Slice 9d, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the review's convergent finding #3: the kit assumed **GitHub Actions** — `ci-gates.sh` only recognized GitHub `id: gate-X` syntax and `incept.sh` hardcoded `.github/workflows/ci.yml`, so a GitLab or Azure-DevOps adopter had to rewrite all CI and could never pass conformance. The contract was always the gate-ids; only the matcher and the reference were GitHub-bound. **MINOR** — additive matcher branch, a new reference, a new flag, and docs (no new universally-required gate; existing GitHub workflows are unaffected). The companion **9d-b runtime-guard portability** (extracting the guard deny-matrix into a runtime-agnostic core) is split out to its own slice — it edits the control-plane `guard.sh` and is human-gated at the terminal.

### Added
- **`profiles/typescript-node/ci.gitlab-ci.yml`** — a real GitLab CI reference expressing the same 8 gate-ids as GitLab job keys (`gate-lint:`, `gate-test:`, …), using the ts-node toolchain; comments name the GitLab-native equivalents (Secret-Detection / Dependency-Scanning / CycloneDX templates). Passes `ci-gates.sh`.
- **`scripts/incept.sh --ci github|gitlab`** — wires the matching platform reference: `github` → `.github/workflows/ci.yml` (unchanged default); `gitlab` → `.gitlab-ci.yml` at the repo root plus `.gitlab/CODEOWNERS`. Validates the value before any mutation; the post-inception branch-protection hint is now platform-aware.
- **`docs/operations/ci-platforms.md`** — the portability reference: the gate-id contract as the platform-neutral interface, how to express it on GitHub / GitLab / Azure DevOps (documented mapping, with the ADO step-name identifier caveat), and the **honest coupling note** — `branch-protection.sh` and `dora.sh` use the GitHub API; the GitLab/ADO equivalent is adopter-owned and reports UNVERIFIED rather than a false pass.

### Changed
- **`conformance/ci-gates.sh`** now recognizes a gate declared **either** as a GitHub Actions `id: gate-X` step **or** a GitLab CI `gate-X:` job key (line-anchored, comment-excluded — same anti-false-positive discipline). No behavior change for existing GitHub workflows. Header updated; the contract is the gate-ids, the platform is open.
- **Tie-ins**: `DEVELOPMENT-STANDARDS.md` §14 conformance line (gates declared by id on any CI platform → `ci-platforms.md`) and the `conformance/README.md` `ci-gates.sh` index row (recognizes GitHub + GitLab).

## [2.27.0] - 2026-06-09

Brownfield ratchet & waiver (Slice 9c, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the brownfield persona's P0: a legacy repo that already fails the gates had no sanctioned path to adopt — it could only abandon the kit or silently disable gates. Now adoption is a tracked, time-boxed, owned **governed exception**, not "comply or fake it". **MINOR** — additive templates/scripts/docs.

### Added
- **`templates/WAIVER-REGISTER.md`** — operationalizes the governed-exception process for adoption. Per-waiver: gate · reason · owner · opened · expires · remediation plan · ratified-by. States the **non-negotiable set** (`secret-scan`, `branch-protection` — never waivable) and the **90-day max lifetime**.
- **`conformance/waivers-valid.sh`** — validates a register: FAILs on expired, non-negotiable-gate, over-90-day, or missing-field waivers; N/A-pass without a register (adoption-conditional). Portable dates (GNU/BSD); `--selftest` (7 cases).
- **`scripts/coverage-ratchet.sh`** — stack-neutral "no-regression-below-baseline": pass your current coverage number, gate on *no drop* below a committed `.coverage-baseline` (seeded on first run) instead of an absolute-80% wall on day one. `--selftest`.

### Changed
- **`docs/adoption/brownfield.md` §5 "Adopting when you already fail the gates"** — the ramp: non-negotiable-vs-deferrable gate tiers, baseline-then-tighten, the waiver register + ratchet workflow, and a recommended tightening schedule.
- **Contract tie-ins**: `DEVELOPMENT-STANDARDS.md` §14 (gates blocking EXCEPT under a tracked/expiring/ratified waiver — never silent) and `DEVELOPMENT-PROCESS.md` governed-exceptions (→ the brownfield register). `conformance/README.md` index row.

## [2.26.0] - 2026-06-09

Conformance honesty — "green ≠ verified" (Slice 9a, the other Tier-0 item of the "Honest Assurance & Adoption Reach" arc). Closes the review's convergent finding #1: conformance checks that pass on documentation/declaration, and a `branch-protection.sh` that silently passed when it could not verify. **MINOR** — additive surfacing + a check behavior change (no new universally-required CI gate).

### Added
- **`conformance/verify.sh`** — an honest aggregate runner. Classifies every check **[control]** (verifies a working/remote control) vs **[doc]** (verifies documentation / recorded evidence exists, NOT that it was tested), prints a footer stating exactly what a green run does and does not prove, and gates only on **control** failures (and on UNVERIFIED under `--require`/CI). Deterministic `--selftest`.
- **`conformance/README.md` "What a green run means — and doesn't"** section + a `verify.sh` index row — the control-vs-documentation taxonomy is now first-class.

### Changed
- **`conformance/branch-protection.sh` is now three-state** (was: silent `exit 0` "Informational" when it could not verify): `exit 0` verified-protected · `exit 1` verified-unprotected · **`exit 2` UNVERIFIED** (no `gh`/remote) — never a silent pass. In CI (`CI` env) or with `--require`, UNVERIFIED escalates to FAIL. Cleaner messaging for the "Branch not protected" (404) and "not readable" (token lacks repo-admin) cases. Adds `--selftest`.

### Note
Behavior change: adopters who ran `branch-protection.sh` in a local `&&` chain expecting `exit 0` when `gh` is absent will now get `exit 2` (UNVERIFIED). That is the fix — a silent pass was the bug.

## [2.25.0] - 2026-06-09

Runtime-safety hardening & honest reframe (Slice 9b — first slice of the "Honest Assurance & Adoption Reach" arc). An adversarial red-team of the agent guard found it **~16% effective and self-disabling** (183 payloads → 111 confirmed bypasses); this slice raises empirical effectiveness to **~91%** on the red-team battery, makes the guard protect its own integrity, and corrects the docs that oversold it. **MINOR** — additive guard coverage + new docs; no new universally-required CI gate.

### Added
- **Hardened deny-list** in `.claude/hooks/guard.sh`: non-rm destruction (`truncate`/`dd of=`/`shred`/`mkfs`/`wipefs`/`blkdiscard`/`find -delete`/`rsync --delete`/`git clean`/redirect-truncation/`mv →/dev/null`); **scalpel `rm`** (denies globs, data-file extensions, absolute paths, dotfiles-of-record while keeping plain `rm stale.txt` allowed); obfuscation-technique denial (`<decode> | sh`, `eval $(…)`, `git -c … push` indirection); **partial** exfiltration denial (`scp`/`sftp`/`curl`-upload/`wget --post-file`/`nc`/`rclone`/`mail`, honestly labelled partial); cloud/infra **capability families** (`terraform destroy`, `*-delete`/`terminate-*` across aws/gcloud/az, `helm uninstall`, `kubectl drain`, DB `drop` via clients/migration tools).
- **Best-effort self/control-plane protection** (not absolute — see residuals): no agent `Bash`/`Write`/`Edit`/`NotebookEdit` may modify `guard.sh`, `settings.json`/`.local`, `.github/workflows/`, `CODEOWNERS`, or `.git/` internals via the common verbs/paths — fixes the `NotebookEdit` `notebook_path` blind spot. Post-review hardening closed `git config core.hooksPath`, `git checkout/restore` of the guard, path-normalization tricks (`//`, `/./`, `..`, basename), and parent-directory ops (`mv .claude`, `chmod -R`, `rmdir`). Human-only `KIT_GUARD_SELFEDIT=1` maintenance escape (an agent cannot set it; the hook process env is human-controlled).
- **`docs/enterprise/platform-safety-boundary.md`** — the Org-owned *real* boundary (network-egress allowlist, separate prod credentials, sandboxed FS, scoped tokens), mapped into `compliance-crosswalk.md`.
- **Regression corpus**: `conformance/agent-autonomy.sh` extended with the red-team bypasses (deny) plus over-block guards (allow) and a self-protection block — locking the fix in CI.

### Changed
- **Honest reframe** of the guard across its header, `.claude/README.md`, and `DEVELOPMENT-PROCESS.md` §13: a **best-effort speed bump for honest mistakes, not a security boundary**. The real boundary is platform-owned.

### Known residuals (by design — the deny-list tail)
- **Interpreters** (`python3 -c`, `node -e`) are not pattern-blockable — they can both **exfiltrate** data *and* **delete/rewrite the guard itself** (self-protection is best-effort, not absolute). The control is the platform sandbox + egress allowlist (Layer 3).
- **Variable-indirection obfuscation** (`X=rm; $X -rf`) is a *deliberate* evasion; the guard targets honest mistakes — deliberate evasion is the platform boundary's job.

## [2.24.1] - 2026-06-09

Doc-coherence closeout — a holistic consistency pass after the Slice 8 arc (v2.19.0–2.24.0). Orientation-layer-only; no contract, behavior, or mechanism change. The kit's first **PATCH** release (corrections, not new capability).

### Fixed
- **README version badge** `v1.0.0` → `v2.24.0` (it had drifted from `VERSION`).
- **Doc-set tables** (`README.md`, `CLAUDE.md`) now list `docs/operations/` (progressive delivery · resilience verification · DORA) and `docs/continuity/` (backup-restore drill · BIA) — previously undiscoverable from the entry-point docs — and add the `BIA` template (shipped in 8c) to the templates list.
- **`DEVELOPMENT-PROCESS.md` §8 conditional-gates clause** — replaced the strained "respectively" 1:1 mapping (7 gates, 5 work-types) with an explicit each-applies-where-it-fits mapping.
- **`DEVELOPMENT-PROCESS.md` §16 quick-reference GATES line** — added the four Slice-8 conditional gates ([15-factor] · [deployable] · [DR] · [resilience]).
- **`conformance/definition-of-deployable.md`** row 11 — qualified the bare `§15` as `DEVELOPMENT-PROCESS.md §15` (disambiguated from the new `DEVELOPMENT-STANDARDS.md` §15 Incident Response added in 8a).
- **`conformance/README.md`** — explained the escalate-only (`dr-ready.sh`) vs plain-N/A (`deployable-ready.sh` / `resilience-ready.sh`) distinction (N/A weight matches blast radius).

### Note
PATCH (2.24.1): documentation coherence only. No `VERSION`-gated behavior, no new gate, no contract change. The continuity & safe-delivery arc (Slice 8) remains complete.

## [2.24.0] - 2026-06-09

Slice 8f — DORA metrics collection. Sixth and final sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap C1 (DORA defined but not instrumented). **Completes Slice 8.**

### Added
- **`docs/operations/dora-metrics.md`** — a collection reference: per-metric GitHub data source + derivation (incl. the adopter-wired change-failure rate / MTTR / retro-closure), the **§9 maturity-gating path** (the home for DORA enforcement — opt-in at scale), and a dashboard pattern. DORA is a feedback instrument, not a gate.
- **`scripts/dora.sh`** — a real collector for the **GitHub-derivable subset** (release cadence, PR lead time, review latency) via `gh` (gh's built-in `--jq` for date math; no separate `jq`). **Degrades gracefully** — any `gh` failure prints "unavailable" and the script still **exits 0** (a report never fails a pipeline) — and names deploy-freq-proper / change-fail / MTTR / retro-closure as adopter-wired. A `--selftest` asserts the no-`gh` degradation path.
- **Kit CI** smokes the collector (`dora.sh --selftest`) — proves it executes + degrades, never gates on the numbers.
- **`DEVELOPMENT-PROCESS.md`** §14 references the doc + collector; §9 cross-references the DORA change-fail / MTTR maturity-gating.

### Note
MINOR (2.24.0): additive — a reference + a report script + a CI smoke. **No new conformance gate**: DORA-value-gating is deliberately a §9 maturity step, not a baseline (a presence check would be theatre; a value-gate baseline would punish early-stage projects). No new CI gate-id; §14's gate set unchanged. **This release completes Slice 8** (incident response · definition of deployable · DR/backup-restore · resilience+load · progressive delivery · DORA).

## [2.23.0] - 2026-06-09

Slice 8e — Progressive-delivery reference + smoke gates. Fifth sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gaps B2 (progressive delivery had no reference) + B3 (post-deploy smoke verification was thin). The reference leg of a triad whose contract (§10) and conformance (8b Definition of Deployable) already shipped.

### Added
- **`docs/operations/progressive-delivery.md`** — a stack-neutral reference: staged / canary / blue-green strategies; **smoke gates at every promotion boundary** (lower-env → the canary/green slice *before* widening → post-full-rollout); automated canary analysis tied to SLOs / error budget (§9); rollback. Tooling (Argo Rollouts / Flagger / flag-driven) named Org-owned.
- **`DEVELOPMENT-STANDARDS.md` §14** — the `deploy-prod` reference now shows **deploy → smoke → rollback-on-fail** (the `if: failure()` step makes it a gate, not a log).

### Changed
- **`conformance/definition-of-deployable.md`** — the smoke row is tightened from "smoke defined + result recorded" to "**post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary** incl. the canary/green slice before widening"; rows 5/6 reference the new doc. Rows stay Manual (behavioural). No script change.
- **`DEVELOPMENT-PROCESS.md` §10**, **`CLAUDE.md` DoD**, **`conformance/README.md`** reference the new doc.

### Note
MINOR (2.23.0): additive — a reference + a tightened checklist row. **No new conformance script**: a post-deploy smoke *gate* is a pipeline behaviour (step ordering + failure semantics) that a cross-stack YAML grep can't reliably detect, so it stays a Manual checklist row with a reference (honest enforcement, not theatre). No new CI gate-id; §14's gate set unchanged.

## [2.22.0] - 2026-06-09

Slice 8d — Resilience + load/soak verification. Fourth sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A3 (resilience principles + load/soak asserted but never verified). Chaos-engineering / SRE anchor.

### Added
- **`docs/operations/resilience-verification.md`** — a stack-neutral how-to: the fault-injection drill (breaker trips, retries back off, degrades gracefully) and the load/soak test (find the knee, catch leaks), with the isolated-env do-no-harm rule and "recorded ≠ passed".
- **`conformance/resilience-readiness.md`** — a conditional resilience checklist (Manual judgment rows + Auto record rows) with a "necessary, not sufficient" callout; verifies `DEVELOPMENT-STANDARDS.md` §4 + §6.
- **`conformance/resilience-ready.sh`** — a conditional, fail-closed companion: for a project with a deploy surface it asserts RUNBOOK §8 records a load/soak date and a fault-injection date (non-placeholder); otherwise N/A. Self-discloses scope (recorded ≠ actually resilient). `--selftest` battery. Stack-neutral (checks a dated record, not load-test tooling).
- **`DEVELOPMENT-PROCESS.md`** — a conditional **Resilience readiness** gate (§7).
- **`DEVELOPMENT-STANDARDS.md`** — §4 and §6 now point at the verification reference ("verify these — don't just assert them"); RUNBOOK §8 gains the resilience-record lines.
- **`audit-evidence-checklist.md`** — a resilience row (A1.2, A1.3 / A.8.6, A.8.16; Auto-conditional).

### Note
MINOR (2.22.0): additive — a conditional Review gate, a checklist, a record-script, and a reference. No new universally-required CI gate; no DoD anchor (proportionate — a resilience miss is a reliability risk caught at Review, not data loss). The 8 application gate-ids and §14 are unchanged.

## [2.21.0] - 2026-06-09

Slice 8c — DR / backup-restore drill + BIA-at-Inception. Third sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A2 (DR was prose-only — no reference, no drill proof, no criticality tiering, no BIA). NIST SP 800-34 anchor.

### Added
- **`docs/continuity/backup-restore-drill.md`** — a stack-neutral restore-drill reference: the isolated-env do-no-harm rule, the 6-step drill, RTO/RPO actuals, and "recorded ≠ passed".
- **`templates/BIA-TEMPLATE.md`** — a Business Impact Analysis (data inventory, criticality tiers, per-tier RTO/RPO, dependencies, max tolerable downtime). Produced at Inception for data-handling projects.
- **`conformance/dr-readiness.md`** — a conditional DR-readiness checklist (Manual judgment rows + Auto rows) with a "necessary, not sufficient" callout and an explicit "the script's N/A is advisory; this checklist applies regardless" note.
- **`conformance/dr-ready.sh`** — a conditional, fail-closed, **escalate-only** companion: for a project with a persistent-data surface it asserts a BIA exists, RUNBOOK RTO/RPO are filled (not placeholder), and a restore-drill date is recorded; otherwise N/A. Its `N/A` is **self-incriminating** (detection is conservative, so a miss never exempts a data project) and its success output self-discloses scope (documented + recorded ≠ tested). `--selftest` battery.
- **Tiered RTO/RPO** by data criticality — `DEVELOPMENT-STANDARDS.md` §10 + RUNBOOK §6 per-tier table.
- **BIA-at-Inception** — a `START-HERE.md` §6 step + a conditional Inception-Done line (data projects); `inception-done.sh` unchanged (a prompt, not a hard gate).
- **`DEVELOPMENT-PROCESS.md`** — a conditional **DR readiness** gate (§7); the §15 recurring item references the drill.
- **Definition of Done anchor** — "DR proven for data services" on the `CLAUDE.md` Production line, so a data service is not "done" without a passed DR-readiness check (backstops the Inception prompt).
- **`audit-evidence-checklist.md`** — a DR-drill row (CC7.5, A1.2 / A.5.29, A.8.13–14; Auto-conditional).

### Note
MINOR (2.21.0): additive — a conditional gate, a conditional DoD item (data services, like the existing AI-eval / accessibility DoD items), a template, and references. No new universally-required CI gate; the 8 application gate-ids and §14 are unchanged.

## [2.20.0] - 2026-06-09

Slice 8b — Definition of Deployable. Second sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap B1 (release-readiness contract not enforced): converts §10's "every release declares its rollback path before it ships" into a conditional Release gate.

### Added
- **`conformance/definition-of-deployable.md`** — a conditional release-readiness checklist (Release gate, `DEVELOPMENT-PROCESS.md` §7) mixing **Manual** judgment rows (rollback tested, alerts wired, migration reversible) and **Auto** rows. Carries a "a green script is necessary, not sufficient" callout and *(documented)* / *(tested / wired)* row labels. OWASP DSOMM anchor.
- **`conformance/deployable-ready.sh`** — a conditional, fail-closed companion script: for a project with a deploy surface (Dockerfile / `environment:` workflow / deploy job) it asserts RUNBOOK has Deploy + Rollback sections and a smoke test is referenced; non-deployable projects skip-pass (N/A). Its success output self-discloses scope (documents present, **not** tested). A **`--selftest`** fixture battery (skip/OK/FAIL) regression-locks the positive path in CI.
- **`DEVELOPMENT-PROCESS.md` §7** — new conditional **Definition of Deployable** gate (deployable services; Release manager + reviewer); §4 Release and §10 rollback reference the checklist.
- **`templates/RUNBOOK-TEMPLATE.md`** — a smoke-test slot under §4 Deploy, so an incepted deployable project satisfies the new check.
- **`conformance/audit-evidence-checklist.md`** — a Release-readiness row (CC8.1 / A.8.31, A.8.32; Auto-conditional).

### Note
MINOR (2.20.0): additive — a **conditional** Release gate at a human checkpoint (like the threat-model / eval / 15-factor gates), not a new universally-required CI gate. The 8 application CI gate-ids and §14 are unchanged.

## [2.19.0] - 2026-06-09

Slice 8a — Incident Response standard + blameless postmortem template. First sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A1 (no incident-response standard + a dangling cross-reference).

### Added
- **`DEVELOPMENT-STANDARDS.md` §15 — Incident Response**: P0–P3 severity matrix, incident roles as functions (commander · comms · scribe; agents assist, a human commands), the detect→declare→mitigate→resolve→postmortem arc, and a blameless-postmortem requirement (P0/P1) whose action items route back into the loop. NIST SP 800-61 anchor; incident tooling named Org-owned.
- **`templates/POSTMORTEM-TEMPLATE.md`** — an eight-section blameless postmortem (summary, impact, timeline, root cause, detection, went well/didn't, action items, blameless statement).
- **`conformance/audit-evidence-checklist.md`** — an Incident-response row (CC7.3/7.4 / ISO A.5.24–A.5.28; Manual).

### Fixed
- The two **dangling cross-references** in `DEVELOPMENT-PROCESS.md` §8/§9 (lines 212, 225) that pointed at a non-existent STANDARDS incident-response section now cite `DEVELOPMENT-STANDARDS.md` §15. The artifact-flow Postmortem row links the new template.

### Note
MINOR (2.19.0): additive — a new standard section, a template, and reference fixes. No new required CI gate; no behavior change. §1–§14 of `DEVELOPMENT-STANDARDS.md` are unrenumbered (§15 appended).

## [2.18.0] - 2026-06-08

Slice 7f — Doc refresh & consistency. Final sub-slice of Slice 7 (adoption/safety hardening). Docs-only; no behavior or contract change.

### Changed
- **Ratification-role casing** normalized to the §2 "functions, not titles" convention (labels first-word-capitalized, prose lowercase) across `DEVELOPMENT-PROCESS.md` §13, `docs/enterprise/ratification-rbac.md`, and `conformance/audit-evidence-checklist.md`. (`CHANGELOG.md` history left untouched.)
- `README.md` now names all **10** shipped profiles (was 7); `README.md` "What's inside" and `CLAUDE.md` document-set tables refreshed to include the enterprise addendum and the current template/docs set.
- `conformance/README.md` describes the kit's own CI in the present tense and adds a note that `inception-done.sh` is *expected to fail at the kit root* (the kit is the template source, not an instantiated project) — also noted in the script header.

### Note
MINOR (2.18.0): documentation consistency only. **Completes Slice 7** (environments & prod safety, personas, containers, work-tracking, brownfield, doc refresh).

## [2.17.0] - 2026-06-08

Slice 7e — Brownfield adoption & `.claude/` hygiene. Fifth sub-slice of Slice 7. Makes the kit safely adoptable into an existing repo and enforces that the runtime guard is actually wired.

### Added
- **`conformance/guard-wired.sh`** — fail-closed check that the `.claude/` PreToolUse guard is actually registered and present. **Wired into `inception-done.sh`**, so no project (greenfield or brownfield) passes Inception with a dead guard.
- **`docs/adoption/brownfield.md`** — threat-model-first brownfield path: copy-in steps, the `.claude/` **merge** policy (add the guard, never overwrite; with explicit duplicate-key JSON guidance), Inception adapted, and honest residual gaps (pattern coverage + the Org-owned platform backstop).
- **`README.md` `.claude/` scoping** — project-level vs global `~/.claude/`; `settings.json` (committed) vs `settings.local.json` (gitignored). Dropping the kit affects only that repo, not the machine.

### Changed
- `conformance/inception-done.sh` now requires the guard to be **wired**, not just `.claude/` present.
- `scripts/incept.sh` **warns** (never modifies) when a `.claude/` without the kit guard is detected, pointing at the brownfield merge guide.
- `START-HERE.md` brownfield router row points at the adoption guide; `conformance/README.md` indexes `guard-wired.sh`.

### Note
MINOR (2.17.0): no new universally-required CI gate, no integration code, no breaking change. Brownfield inverts the kit's risk gradient (a legacy repo's blast radius pre-exists), so the guard-liveness check is the enforcement teeth behind the merge guidance.

## [2.16.0] - 2026-06-08

Slice 7d — Work-tracking adapter guidance. Fourth sub-slice of Slice 7. Lifts named backlog backends from "named" to "documented adapter."

### Added
- **`docs/work-tracking/adapters.md`** — contract-anchored mapping guide: per-tracker **state map · field map · atomic claim · fit notes** for `BACKLOG.md`, GitHub, Jira, **Azure DevOps**, Linear, **GitLab**, plus a "bring your own tracker" recipe. Guidance only — no integration code.
- **`conformance/backlog-adapters.sh`** — fail-closed drift lock: the named set must agree across `incept.sh --backlog`, `DEVELOPMENT-PROCESS.md` §6, and the guide.

### Changed
- `DEVELOPMENT-PROCESS.md` §6 names six backends (adds Azure DevOps + GitLab) and points at the guide; the §6 contract (states/fields/atomic-claim) is unchanged.
- `scripts/incept.sh` `--backlog` accepts `md|github|jira|ado|linear|gitlab`, validates the choice, and points non-`md` choices at the guide (still scaffolds only `BACKLOG.md`).
- `templates/PROJECT-CLAUDE-TEMPLATE.md` §3 names the six backends + the guide.
- `conformance/README.md` indexes `backlog-adapters.sh` and `container-supply-chain.sh` (the latter a 7c index omission).

### Note
MINOR (2.16.0): no new required CI gate, no integration code. General PM tools (Asana/Monday/ClickUp) are intentionally excluded from the named set — they lack a race-safe atomic-claim primitive; the bring-your-own recipe covers them with caveats.

## [2.15.0] - 2026-06-08

Slice 7c — Containers & image supply-chain (pattern + reference profile). Third sub-slice of Slice 7. Containers are first-class for services and explicitly absent for non-services.

### Added
- **Conditional container image supply-chain standard** (`DEVELOPMENT-STANDARDS.md` §14): if a project ships a deployable service image, the image must be multi-stage, non-root, minimal-base, healthchecked, and carry an image SBOM + **build provenance bound to the image digest**. Marked N/A for libraries/CLIs/batch/IaC — no new universal gate.
- **Reference profile `typescript-node`:** `Dockerfile` (multi-stage, distroless non-root), `.dockerignore`, `compose.yaml`, devcontainer, `deploy/k8s/` + `deploy/helm/` (non-root securityContext, probes, resource limits, digest-pinned image).
- **`profiles/typescript-node/ci.yml`** extended: `gate-image-sbom` (Syft/CycloneDX, scans on every PR) and a push-only `image-provenance` job — GHCR push + `actions/attest-build-provenance` digest-bound — with `packages: write` scoped to push-to-main. The 8 universal gate-ids are unchanged.
- **`conformance/container-supply-chain.sh`** — conditional, fail-closed: profiles with a `Dockerfile` must be multi-stage + non-root with image SBOM + digest-bound provenance; profiles without one are N/A (never failed).
- `_TEMPLATE.md` containerization pattern; `RUNBOOK-TEMPLATE.md` Kubernetes deploy guidance; audit-evidence conditional row.

### Changed
- `DEVELOPMENT-STANDARDS.md` §13 reinforces the image as the unit of dev/prod parity; `DEVELOPMENT-PROCESS.md` §9 ties promotion to the attested digest.

### Note
MINOR (2.15.0): no new universally-required CI gate. Image supply-chain is required only when a project ships a service image, so non-service stacks are unaffected. Rolling the pattern to other service profiles is a follow-on slice.

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

## [2.13.0] - 2026-06-06

Slice 7a — Environments & production safety. First sub-slice of Slice 7 (adoption/safety hardening).

### Added
- **Dev → QA → UAT → Prod** environment model with gated promotion (production always human-gated) in `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md` §14 + `PROJECT-CLAUDE-TEMPLATE.md` + `RUNBOOK-TEMPLATE.md`.
- `conformance/branch-protection.sh` — verifies `main` is actually protected (PR reviews + status checks) via `gh api`; informational clean-exit where the API isn't reachable. `incept.sh` now reminds to apply branch protection.
- Env-protected reference prod-deploy workflow; explicit **human-coverage boundary** (the guard governs the Claude Code runtime only; humans/other runtimes are Org-owned platform controls).

### Changed
- **`.claude/hooks/guard.sh` is now environment-aware (additive — no existing deny weakened):** expanded destructive coverage (database drops via ORM/framework tools across Rails/Laravel/Django/Alembic/Flyway/.NET-EF, raw DB-client `DROP DATABASE`, restore-with-clean, cache flush, cluster-resource and container-volume removal, cloud storage/DB/instance deletion) plus a **production-context catch-all** (prod kube/helm context or namespace, `*_ENV=prod` prefix, `--env production` co-occurring with a destructive/deploy verb). All 35 prior conformance cases pass; 61 cases total.

### Note
No new required CI gate (MINOR). Production destructive-action prevention for humans and non-Claude-Code runtimes is Org-owned (platform IAM / account separation / deploy approvals).

## [2.12.0] - 2026-06-06

Slice 6d — Enterprise addendum, pillar 4 (capstone): the audit-evidence checklist. **Completes the enterprise addendum and the kit roadmap.** Tagged `v3.0.0` as the "enterprise layer complete" milestone (a marker, not a semver-major — no new required gate; the kit's contract version is 2.12.0, per `MAINTAINING.md`).

### Added
- `conformance/audit-evidence-checklist.md` — checklist-type conformance check mapping every control in the compliance crosswalk to **where its evidence lives** in a kit-built repo (CI gate logs, SBOM + provenance, PR approvals, the executable `conformance/*.sh`, the §6b managed-secret config, the §6c governed-exception records). Auto rows name the runnable check; Manual rows are attestation; waived controls cite a governed exception.
- Wired into `docs/enterprise/README.md`, the 6b/6c back-references, and the `conformance/README.md` index.

### Note
Documentation/checklist only — no new gate, no code. Completeness tie-off: every crosswalk control has an evidence row. With this, the enterprise addendum (6a crosswalk · 6b secrets-at-scale · 6c ratification RBAC · 6d audit evidence) is complete.

## [2.11.0] - 2026-06-06

Slice 6c — Enterprise addendum, pillar 3: ratification RBAC. Third of four sub-slices.

### Added
- `DEVELOPMENT-PROCESS.md` §13 **"Ratification roles & exceptions"** — defines which named role (Project Owner / Code Owner / Security Owner / Release Manager) may ratify what, the builder ≠ sole-ratifier rule per change, and the **governed-exception process**: required gates/posture are universally required; a Security-Owner-ratified, time-boxed record is the only way to waive (settles the Slice 5e deferred question). §12 cross-references it.
- `docs/enterprise/ratification-rbac.md` — full role model, separation-of-duties, GitHub mapping (CODEOWNERS + branch protection + the profile companions), and the exception-record template.

### Note
No new gate, no code. The agent-autonomy human-gate set is unchanged — agents propose; a human in the appropriate role ratifies. Maps onto existing CODEOWNERS / BRANCH-PROTECTION companions; 6d's audit-evidence checklist attests it.

## [2.10.0] - 2026-06-06

Slice 6b — Enterprise addendum, pillar 2: secrets at scale. Second of four sub-slices.

### Added
- `DEVELOPMENT-STANDARDS.md` §2 **"Secrets at scale"** subsection — the contract: managed store (Vault/KMS) beyond `.env`, least-privilege, rotation (prefer dynamic/short-lived), no plaintext in state/logs/images, CI fetches at run time via OIDC, audited break-glass.
- `docs/enterprise/secrets-at-scale.md` — patterns (static vs dynamic, CI injection reusing the §14 OIDC/provenance pattern, rotation, envelope encryption, break-glass) + a **secret-manager-client-by-stack** table covering all 10 stacks in one place.
- `profiles/_TEMPLATE.md` Security section now points to the secrets-at-scale doc, so future/BYO profiles route correctly.

### Note
Stack-neutral contract + stack-aware reference — **no edit to the 10 existing profiles**. No new gate, no code. The CI-injection pattern ties to the Slice 5e push-only OIDC job.

## [2.9.0] - 2026-06-06

Slice 6a — Enterprise addendum, pillar 1: the compliance crosswalk. First of four sub-slices (umbrella spec: `docs/superpowers/specs/2026-06-06-slice6-enterprise-umbrella-design.md`).

### Added
- `docs/enterprise/README.md` — addendum index + an explicit **responsibility boundary** (Kit-enforced / Kit-assisted / Org-owned), naming what the kit does not cover (HR, physical, vendor risk, BCP, the privacy program).
- `docs/enterprise/compliance-crosswalk.md` — maps the controls the kit enforces/assists to **SOC 2 (Security CC + Privacy P) + ISO 27001:2022 Annex A**, with a dedicated **privacy/data-protection family** (data-subject rights, consent & age-gating, retention, third-party sharing; COPPA/GDPR-minors/CCPA named as triggers). Column-structured so NIST CSF / PCI-DSS / ISO 27701 are a cheap re-index later.

### Note
Pure documentation — no new gate, no code, no profile changes. The crosswalk *maps* controls; it does not mandate new ones. Privacy rows are N/A-with-reason for no-PII projects. Definition of Done unchanged.

## [2.8.0] - 2026-06-06

Slice 5e — CI security hardening across all 10 profile reference pipelines. Triggered by a push security review whose findings proved kit-wide. No new gate, no contract-breaking change.

### Changed
- **All 10 `profiles/*/ci.yml`** restructured to least-privilege OIDC: a `ci` job (all gates, PR + push, `permissions: contents: read`) plus a push-main-only `provenance` job (`needs: ci`) that holds `id-token`/`attestations: write` and attests the build artifact handed off via `upload-artifact`/`download-artifact` (`subject-path: build-artifact/**`). PR-triggered steps can no longer mint an OIDC token. PRs still run every gate.
- Strengthened the `# HARDENING:` block in every reference pipeline (SHA-pin actions · pin tool installs · cloud OIDC trust policy MUST restrict `sub` to `refs/heads/main`).
- `profiles/terraform/ci.yml`: pinned `checkov` to `3.2.533` (verified on PyPI); noted the conftest download should be checksum-verified.

### Added
- `DEVELOPMENT-STANDARDS.md` §14: a **CI security hardening** posture note (least-privilege OIDC via a push-only attestation job · SHA-pinning · trust-policy `sub` restriction). Guidance, not a new required gate — Definition of Done unchanged.

### Note
No gate id was removed from any profile; `conformance/ci-gates.sh` (job-agnostic id presence) and `profile-completeness.sh` pass unchanged across all 10. SHA-pinning the references is modeled as a documented adopter step rather than baked-in opaque hashes.

## [2.7.0] - 2026-06-06

Slice 5d — Terraform/IaC stack profile. Completes the profile family (10 stacks). Proves §14's 8 gates hold even for config-only IaC — via analogs, no contract change.

### Added
- `profiles/terraform.md` + `profiles/terraform/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Terraform ≥1.6 · tflint · `terraform validate`/`test` · Checkov + conftest/OPA · Trivy · gitleaks.
- A dedicated **`gate-policy`** step (Checkov + conftest/OPA) — the IaC headline gate (parallel to ML's `gate-eval` and data-engineering's `gate-data-quality`).

### Note
IaC has no software artifact, so §14's gates map to **analogs**, keeping the 8 intact (no `ci-gates.sh`/§14 change): `gate-build` = `terraform plan` (the plan is the artifact); `gate-dep-scan` = Trivy config scan (vulnerable/misconfigured providers & modules — tfsec is merged into Trivy); `gate-sbom` = Trivy CycloneDX (provider/module inventory). The profile applies the **conditional 15-factor** mechanism (an IaC repo isn't a running service → port-binding/concurrency/stateless/disposability N/A-with-reason). `incept.sh --stack terraform` wires the profile's CI.

## [2.6.0] - 2026-06-06

Slice 5c2 — Data-engineering stack profile. Completes the profile family (9 stacks). The data-eng analog of the ML eval gate: a data-quality gate.

### Added
- `profiles/data-engineering.md` + `profiles/data-engineering/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — dbt-core (warehouse transforms) · Dagster (orchestration, asset checks) · Python ingestion · sqlfluff + ruff (lint) · dbt parse + mypy (validate) · dbt tests/contracts + Great Expectations + pandera + data-diff (data quality) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-data-quality`** step in the data-engineering `ci.yml` (`dbt build` + Great Expectations checkpoint, run against a CI Postgres service) that fails the build on a data-quality violation — the data-eng analog of ML's `gate-eval`. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-data-quality` is an allowed extra.

### Note
`gate-type-check` = `dbt parse` + `mypy` (SQL has no compiler; parsing the model DAG is the validate analog). The profile applies the **conditional 15-factor** mechanism: an orchestrated batch pipeline marks port-binding/concurrency/stateless/disposability N/A-with-reason; the warehouse backing-service + lineage telemetry apply. `incept.sh --stack data-engineering` wires the profile's CI.

## [2.5.0] - 2026-06-06

Slice 5c — ML stack profile. The kit's first profile with a real **eval gate** — wiring the §7 "evals = the dev-time bar / AI analog of TDD" doctrine into CI.

### Added
- `profiles/ml.md` + `profiles/ml/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Python ML lifecycle: uv · ruff (+nbqa) · mypy · pytest (+ pandera data-validation, nbmake notebook smoke) · MLflow (tracking/registry) · DVC (data/model versioning) · notebook hygiene (nbstripout/jupytext) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-eval`** step in the ML `ci.yml` (`python -m evals.run --threshold 0.8`) that fails the build below the eval threshold — metric thresholds and/or LLM-as-judge (pinned judge), plus a safety/red-team set. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-eval` is an allowed ML extra.

### Note
The ML profile applies the **conditional 15-factor** mechanism: a training pipeline is batch, so port-binding/concurrency/stateless/disposability are N/A-with-reason; the serving path satisfies them. `incept.sh --stack ml` wires the profile's CI. The data-engineering profile follows as a separate slice.

## [2.4.0] - 2026-06-06

Slice 5b — More first-class profiles + bring-your-own on-ramp. Seven shipped stacks now: TypeScript, Python, Java/Spring, C#/.NET, Go, Rust, Kotlin.

### Added
- `profiles/dotnet.md` + `profiles/dotnet/` — .NET 8 · dotnet format/analyzers · dotnet build (type-check) · xUnit+coverlet · dotnet list package --vulnerable · CycloneDX .NET · EF Core · ASP.NET Core.
- `profiles/go.md` + `profiles/go/` — Go 1.22+ · golangci-lint · go vet · go test -race -cover · govulncheck · cyclonedx-gomod · golang-migrate.
- `profiles/rust.md` + `profiles/rust/` — Rust stable · clippy · cargo check · cargo-llvm-cov · cargo-audit · cargo-cyclonedx · axum + sqlx.
- `profiles/kotlin.md` + `profiles/kotlin/` — Kotlin/JVM 21 · Gradle (Kotlin DSL) · ktlint+detekt · JUnit5/Kotest+JaCoCo · OWASP dependency-check · cyclonedx-gradle · Spring Boot + Flyway.
- `scripts/new-profile.sh` — scaffolds a new stack profile + a stub `ci.yml` that passes `ci-gates.sh` structurally, so bringing an unsupported stack is a guided, validated workflow.
- `README.md` "Generate your own profile" section; `START-HERE.md` §2B points at the scaffolder.

### Note
Each new `ci.yml` reuses the existing 8-gate `ci-gates.sh`; `profile-completeness.sh` now guards all 7 profiles. Kit CI verifies declaration + completeness; it does not execute the toolchains (adopter-side).

## [2.3.0] - 2026-06-06

Slice 5 — Enterprise profiles. Python and Java/Spring join TypeScript as ready, conformant stack profiles.

### Added
- `profiles/python.md` + `profiles/python/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — uv · ruff · mypy · pytest+cov · gitleaks · pip-audit · CycloneDX-py + provenance; FastAPI + SQLAlchemy/Alembic reference.
- `profiles/java-spring.md` + `profiles/java-spring/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Maven · Spring Boot · Spotless/Checkstyle · JUnit5+JaCoCo · OWASP dependency-check · CycloneDX-maven + provenance; Flyway migrations. (`mvn compile` = type-check; `mvn package` = build.)
- `conformance/profile-completeness.sh` — every profile fills all 11 `_TEMPLATE.md` sections (no leftover `[...]`) and its companion `ci.yml` passes `ci-gates.sh`. Runs in kit CI; also regression-guards `typescript-node.md`.

### Changed
- `.github/workflows/ci.yml` — the conformance job now runs `profile-completeness.sh`.
- `docs/ROADMAP-KIT.md` — Slice 5 marked done.

### Note
`incept.sh --stack python` / `--stack java-spring` now wires the respective profile's CI. Kit CI verifies the profiles' workflows *declare* the §14 gates and the profiles are complete; it does not execute the Python/JVM pipelines (that happens in an adopting project).

## [2.2.0] - 2026-06-06

Slice 3 — Inception bootstrap. One command turns a cloned kit into a configured project. Absorbs the template work (RUNBOOK + flow-board BACKLOG); roadmap collapses 6→5.

### Added
- `scripts/incept.sh` — in-place Inception bootstrap (interactive + `--noninteractive`). At adoption it renames the principles doc `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` (freeing the project memory slot), rewrites the principles-sense references, stamps the project `CLAUDE.md`/`RUNBOOK.md`/`BACKLOG.md`/`ADR-000`, and wires the profile's CI. Prints the judgment steps it does not automate.
- `templates/RUNBOOK-TEMPLATE.md` — cold-resume runbook (setup/deploy/rollback/RPO-RTO).
- `conformance/inception-done.sh` — verifies the Inception-Done gate; kit CI bootstraps a temp project and asserts it passes.

### Changed
- `templates/BACKLOG-TEMPLATE.md` — rewritten from the stale phase/PROGRESS model to the §6 flow-board (states, work-item fields, ordering, work types, tech-debt paydown).
- `.github/workflows/ci.yml` — new `bootstrap` job (incept-into-temp → inception-done).
- `docs/ROADMAP-KIT.md` — Slice 3 done; roadmap 6→5 (template work absorbed).

### Note
The canonical kit stays **un-incepted** (principles remain in `CLAUDE.md`, which also serves as the kit's own memory). The `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename is an **adoption-time transform performed by `incept.sh`**, not a change to the kit's own layout.

## [2.1.0] - 2026-06-06

Slice 2 — Agent governance layer. The §13 autonomy matrix is now mechanically enforced for Claude Code (additive reference + conformance → MINOR per `MAINTAINING.md` §2).

### Added
- `.claude/` governance layer (kit-own + adopter reference): `settings.json` (allow/ask/deny permission globs), `hooks/guard.sh` (PreToolUse hook denying irreversible/high-blast actions, field-scoped via jq, hardened against allowlist-escape bypasses), `agents/reviewer.md` + `agents/security-reviewer.md` (the §12 separations), and `README.md`.
- `conformance/agent-autonomy.sh` — proves the guard denies a tier breach and allows safe actions, with false-positive and bypass-resistance regressions; runs in kit CI.
- `DEVELOPMENT-PROCESS.md` §13 — an "Enforcement reference" note (tool-neutral matrix → Claude Code `.claude/` reference).

### Changed
- `.github/workflows/ci.yml` — the conformance job now also runs `agent-autonomy.sh`.
- `.gitignore` — excludes `.claude/settings.local.json` (personal); `settings.json` is committed/shared.
- `docs/ROADMAP-KIT.md` — Slice 2 marked done.

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

[2.7.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.7.0
[2.6.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.6.0
[2.5.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.5.0
[2.4.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.4.0
[2.3.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.3.0
[2.2.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.2.0
[2.1.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.1.0
[2.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.0.0
[1.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v1.0.0
