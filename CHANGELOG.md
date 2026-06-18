# Changelog

All notable changes to Sparkwright are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.8.0] - 2026-06-18

**MINOR** — H2a of the Tier-2 hardening arc: **containment reference — ship the boundary the guard only documents.** A verify-before-build pass found most of H2.1 already shipped (the egress-allowlist NetworkPolicy landed in 11b) and that "no-egress devcontainer" is a category error for a dev inner-loop (it needs egress for package installs). Reframed to **sandbox-FS devcontainer + egress-allowlist pairing** and closed the two real gaps. **Additive reference material; no control weakened; the verified `typescript-node` path is untouched.**

### Added
- **`profiles/typescript-node/compose.yaml`** — a host-isolated **`agent` service** so the kit *dogfoods* the read-only-FS pattern it documents (it previously shipped only prose): `read_only` root, `tmpfs` scratch, **work-tree-only** mount (no `$HOME`/`~/.aws`/`~/.ssh`/`docker.sock`), `cap_drop: [ALL]`, `no-new-privileges`, `network_mode: none`, `HOME`/`npm_config_cache`→tmpfs so it actually runs read-only. **Opt-in behind `profiles: [agent]`** — a plain `docker compose up` never starts it, so the `app`/`db` dev path is byte-unchanged.
- **`profiles/typescript-node/.devcontainer/devcontainer.sandbox.json`** — the IDE sandbox variant (`--read-only`/`--tmpfs`/`--cap-drop ALL`/`--security-opt no-new-privileges`, work-tree-only `workspaceMount`).
- **`docs/operations/containment.md` §2** — concrete, copy-pasteable **AWS / GCP / Azure OIDC-federation** snippets (was prose-only): AWS IAM role trust policy (`aud` + repo/ref-pinned `sub`) + `configure-aws-credentials`; GCP Workload Identity Pool with a repo-pinned attribute-condition + `google-github-actions/auth`; Azure Federated Credential + `azure/login` — all zero-static-secret.

### Changed
- **`docs/operations/containment.md` §1** — now points to both shipped artifacts and states the **honest ceiling**: an IDE-attached container is inherently weaker than the headless `agent` service (the editor injects a writable, networked server), so the devcontainer is host-isolated but **not** no-egress; FS-sandbox and egress are separate controls — pair either with `egress-control.md` for the network layer.
- **`docs/ROADMAP-KIT.md`** — H2 split into **H2a** (✅ this release) / **H2b** (`kit-guard install-shims`, pending); "no-egress devcontainer" reframed; **P2 marked complete** and **WS4 ✅** (the deferred 3.7.0 housekeeping).

### Honest ceilings (no overclaim)
- A green `containment-ready.sh` proves *declared + attested*, **never** that the FS is truly read-only or tokens truly expire — enforcement stays platform-owned (`docs/enterprise/platform-safety-boundary.md`).
- This does **not** give the kit a new passing CI containment signal — CI runs `containment-ready.sh --selftest` only and never scans the profile. The win is an *adoptable artifact* + self-consistency (the kit now models the pattern it documents).
- **Deferred (tracked):** `containment-ready.sh::has_readonly_mount_config` scans `.devcontainer/devcontainer.json` but not the new `.sandbox.json` filename (and not `--read-only` runArgs); the `compose.yaml` `read_only: true` already provides the match for profile adopters, so this is a future one-line heuristic tidy, not a defect.

## [3.7.0] - 2026-06-18

**MINOR** — P2/WS4 of the usability-governance milestone (the **last P2 slice**): **persona routing**. Non-engineer personas now find their entry at the front door, and interactive `incept` prompts operator-fluency. **Surface/route only — nothing deleted, no gate disabled, no applicable control weakened**; the routing copy explicitly *reinforces* gate universality ("rigor is carried, not waived").

### Added
- **`ONBOARDING.md`** — a "**Which role are you?**" section: a thin persona-routing table (Product Owner/BA · Designer · QA Engineer · Security Owner · DevOps/SRE · Engineer) mapping each to where it plugs into the loop and its entry → exit artifact, pointing to the authoritative function map (`DEVELOPMENT-PROCESS.md` §2) rather than copying it (drift-safe). A "**the rigor is carried, not waived**" note makes explicit that a non-builder is routed to *their own* additional bar (testable acceptance criteria, a11y sign-off), never *out* of an applicable control — the CI/agent-boundary gates bind to the PR regardless of author role ("routing by role changes which doc you open, never which gate applies").
- **`scripts/incept.sh`** — the interactive flow now prompts operator-fluency (the 7th field; previously flag/env-only). Empty-enter stays **non-coercive** — the existing undeclared-fluency notice fires, no silent default, no `CLAUDE.md` stamp; a typo is rejected by the existing membership validation.

### Notes
- **Security Owner in the §13 ratification role table** (a third WS4 item in the original spec) was **verified already present** — across `DEVELOPMENT-PROCESS.md` §2 Roles/Personas, the §7 threat-model/compliance gates, the §13 ratification matrix, and `docs/enterprise/ratification-rbac.md` (added during WS2/3.4.0). No edit made — editing complete, consistent governing tables would be redundant control-plane churn.
- **Deferred-with-reason (residual):** the operator-fluency membership test (`incept.sh` :118-119) uses the POSIX space-padded `case` idiom, which loose-matches a multi-token string containing a valid token (e.g. `"x novice y"`). Assessed pre-existing (reachable today via `--operator-fluency`), non-exploitable (only space-delimited words pass → no sed metacharacter can reach the `:170` `sedi`; threat model is an operator scaffolding their own repo), and out of WS4 item-3 scope. Independently re-verified by the reviewer. Tracked for a later control-plane validation-hardening ticket.

### Why
A go/no-go usability finding: the front door routed only the *experience* axis (novice → practitioner); a QA, designer, product owner, or security owner had no signposted entry, and interactive `incept` collected six fields but never fluency. WS4 closes both without weakening anything — persona routing is additive surfacing, and the fluency prompt is non-coercive.

## [3.6.0] - 2026-06-18

**MINOR** — D4-presentation: **"ratification required" is now a merge-gate, not a red failure.** The `gate-agent-boundary` job exits 0 and posts a distinct `control-plane-ratification` check-run instead of `exit 1`-ing red — so an unratified control-plane PR **blocks the merge in amber, sends no "CI failed" email**, and red ❌ / failure emails are reserved for genuine failures. Decision logic unchanged; enforcement, audit trail, and harness-independence preserved. **Live-verified on PR #114** (`ACTION_REQUIRED` · workflow `success`/no-email · merge `BLOCKED`).

### Changed
- **`.github/workflows/ci.yml` + `profiles/typescript-node/ci.yml`** — the `gate-agent-boundary` job now exits 0 and posts the `control-plane-ratification` check-run via the Checks API (needs `checks: write`); `CI=` is cleared on the `agent-boundary.sh` call so its true three-state (0 ratified/no-cp · 1 unratified-cp · 2 cannot-evaluate) maps to `success` / `action_required` / `failure`. `conformance/agent-boundary.sh` is untouched — **presentation only.**
- **Branch protection:** require the `control-plane-ratification` check so `action_required` blocks the merge (GitHub blocks any required check that isn't `success`). Keep `enforce_admins: false` solo (the logged admin-merge is the ratification); flip `enforce_admins: true` when a team forms (WS2).
- Docs updated to the verified behavior (`docs/operations/harness-enforcement-evidence.md` live evidence; `START-HERE.md` solo note).

### Why
A permanently-red, *required-less* gate emailed "CI failed" on every solo control-plane PR — training red-blindness in the PR view **and** the inbox (the alert-fatigue anti-pattern). "Ratification required" is an awaiting-action **merge-gate** (like "Review required"), not a test; presenting it as such protects the failure channel so a *real* failure still cuts through. (We also found the old gate was never a required check — noise without enforcement; now it's enforcement without noise.)

## [3.5.0] - 2026-06-18

**MINOR** — P2/WS3 of the usability-governance milestone: **progressive-disclosure front door**. Curates the first impression to a ~5-file core path with a pull-not-push map for the enterprise/operability/continuity depth — so a newcomer sees a front door, not the full file wall. **Nothing deleted, no gate disabled, no applicable control hidden**; ordering and emphasis only.

### Added
- **`START-HERE.md`** — a top-of-file "you do not need to read all of this" block: the **first 5** core path (`START-HERE.md` · `CLAUDE.md` · `DEVELOPMENT-PROCESS.md` · your `profiles/<stack>.md` · `AGENTS.md`) + a **pull-not-push** trigger map (regulated → `docs/enterprise/`; live system → `docs/operations/`; data service → `docs/continuity/`; need an artifact → `templates/`). The conditional gates already activate by trigger; the docs are now discovered the same way.
- **`ONBOARDING.md`** — a matching "you will not read all of this" note that hands to the START-HERE core-5 map.
- **`docs/enterprise/README.md`** — explicit pull-not-push framing (reached on trigger; not part of the core path; adopting nothing here weakens no floor).

### Changed
- **`conformance/onboarding-complete.sh`** — extended to assert the front-door signal (first-5 + pull-not-push map) is present in `START-HERE.md`, so the progressive-disclosure surface can't silently regress. Wired in the kit's CI.

## [3.4.0] - 2026-06-18

**MINOR** — P2/WS2 of the usability-governance milestone: **risk-tiered solo review lane**. A solo maintainer now has a recorded, audit-defensible way to satisfy `builder ≠ reviewer` — without faking it and without a second human — that upgrades to enforced two-human SoD with a single `enforce_admins: true` flip and zero rework of the recorded evidence when a teammate joins. Additive (docs/template/process + one presence conformance check); no applicable control weakened.

### Added
- **`templates/REVIEW-RECORD-TEMPLATE.md`** — the recorded-review artifact: agent-review findings + human ratification, plus (high-risk) specific acknowledgments tied to each finding (the anti-theater requirement). Carries the solo compensating-control statement + the one-flip (`enforce_admins: true`), zero-evidence-rework upgrade note.
- **`docs/operations/review-lane.md`** — the two tiers (default = recorded `reviewer`-subagent review + recorded ratification; high-risk [control-plane / security-auth / data-schema / prod / irreversible] = + a structured human self-review), the already-wired trigger (the `agent-boundary` control-plane set + the §13 autonomy tiers), the compensating-controls compliance rationale, and the solo→team upgrade (one `enforce_admins: true` flip — the second human's approval meets the existing required-review rule; the flip removes the owner `--admin` bypass — with zero rework of recorded evidence).
- **`conformance/review-lane.sh`** — presence/wiring conformance check, wired into the kit's own CI.

### Changed
- **`DEVELOPMENT-PROCESS.md` §12** — a **net-zero** solo-lane pointer (the doc is at its 470-line cap). **`conformance/audit-evidence-checklist.md`** gains an Independent-code-review / SoD evidence row mapping the bundle to the SoD control.

### Honest ceiling
- The high-risk self-review is **process discipline, not a fail-closed gate** (mechanically blocking it needs a second actor the solo case lacks) — the kit makes it the path of least resistance + audit-visible, and the `agent-boundary` CI gate still forces ratification on control-plane diffs regardless.

## [3.3.0] - 2026-06-18

**MINOR** — P2/WS1 of the usability-governance milestone: **guard false-positive fix (deny-by-default)**. The control-plane guard stops falsely blocking read-only commands that merely *mention* a control-plane path, and the path check no longer false-denies a same-named file in a non-control-plane directory — without weakening any protection (verified across four adversarial security reviews + a dual corpus).

### Changed
- **WS1 — control-plane command rule, deny-by-default.** `guard-core.sh` keeps the prior co-occurrence deny as the **floor** (no protection removed) and allows back ONLY a *provably-safe single read command*: no `;`/`&&`/`||`/`|`/`&`/redirect/command-substitution chaining, and a leading verb (after stripping a leading `\`, env-assignments, and `sudo`/`command`/`env`/`exec`/`time`/`nice`/`nohup`/`stdbuf`/`builtin`) in a strict write/exec-free read allowlist (`grep`/`cat`/`ls`/`wc`/`diff`/`cut`/`od`/… — `sed`/`awk`/`find`/`sort`/`uniq`/`less`/`xxd` are excluded as write/exec-capable). So `grep cp scripts/kit-guard`, `cat .github/workflows/ci.yml`, `ls -l scripts/kit-guard` are allowed while every real mutation — and any unrecognized leading token (wrapper, interpreter, prefix) — stays denied.
- **Path basename net narrowed + normalized (found via a real `.vscode/settings.json` report).** The bare-basename fallback fires only for a normalized path with no genuine parent directory, or one that escapes its root via `..`; `fpn` strips a leading `./`, a trailing `/`, and resolves `..` to a fixpoint. So `.vscode/settings.json` / `app/config/settings.json` are allowed while `./settings.json`, `../guard.sh`, `a/../../kit-guard`, and `.claude/settings.json/` are denied.
- Both directions are regression-locked by an expanded dual corpus in `conformance/agent-autonomy.sh`; the `.claude/README.md` over-block note is updated to the precise behavior.

### Honest ceilings
- The guard remains a speed bump: variable/`eval`/command-substitution indirection, and uncommon write-via-flag tools (`sort -o`, `xxd -r`, `perl -pi`, `ed`) are documented pre-existing gaps, backstopped by the `agent-boundary` CI gate on the diff. A compound command that merely *mentions* a control-plane path stays denied (safer than parsing compound shell) — use `KIT_GUARD_SELFEDIT=1` or split the command.

## [3.2.0] - 2026-06-17

**MINOR** — H1 of the post-3.0.0 backlog: **enforcement integrity** — the kit's own controls now resist the agent they govern. Brings the enforcement layer into the control-plane set, constrains adapter `proof.check` execution, removes an agent-forgeable ratification label, and makes the kit dogfood its own governance gate. Additive hardening; the supported `typescript-node` path stays green.

### Added
- **H1.1 — the enforcement layer is now control-plane.** `guard-core.sh::is_control_plane_path` (the single source of truth honored by the inline guard, `pre-push`, `kit-guard`, and the `agent-boundary` CI gate) now covers `conformance/`, `adapters/`, `scripts/fixtures/`, the named kit scripts (`incept`, `dora`, `agent-scorecard`, `agent-trace`, `coverage-ratchet`, `license-check`, `preflight`, `new-adapter`, `new-profile`), and the governing docs `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md`. An agent can no longer weaken a gate's logic, relax the Definition of Done, or add an adapter without ratification. `scripts/` is a **named-script set, not a blanket prefix**, so an adopter's own `scripts/` code is unaffected (adopter friction = zero).
- **H1.4 — the kit dogfoods its own gate.** `.github/workflows/ci.yml` now runs the **real** `gate-agent-boundary` job on every PR (previously only `--selftest`). An unratified control-plane PR makes the job `exit 1`, which GitHub renders as a **failed (red) check** meaning *"ratification required"* — the expected human step, **not a code regression** (live-verified on PR #110). The "ratification required" semantics ride the job/step naming + docs; GitHub offers no non-failing-but-blocking state for a plain step, so a true neutral presentation is a tracked D4 follow-up.

### Changed
- **H1.2 — `proof.check` allowlist.** `conformance/harness-adapter.sh` executes an adapter's `proof.check` only if it is a bare `conformance/*.sh` path (no arguments, shell metacharacters, or `..` traversal) that exists — anything else is rejected *before execution* and cannot prove `native`. Closes arbitrary-code execution from an unratified adapter manifest; a new selftest canary proves the dangerous check never runs.
- **H1.3 — removed the self-ratifiable label.** The `agent-boundary` ratification signal is now a **non-author approval only**; the `ratified-control-plane` label (self-appliable by an agent via `gh pr edit --add-label`) is gone. Solo maintainers ratify via a logged `enforce_admins: false` admin-merge — recorded, never faked.

### Honest ceilings
- The inline guard remains a speed bump: a control-plane edit made through a language interpreter (`python -c`, a script) is **not** caught by its command-string heuristic — the `agent-boundary` CI gate is the post-hoc backstop that catches the resulting diff before merge. Command-string false-positive tuning is deferred to **P2/WS1**; GitLab gate parity to **H4**.
- The `proof.check` allowlist also rejects a **symlinked** check (`[ ! -L ]`), closing the residual where `[ -f ]` would follow a committed symlink under `conformance/` to a payload elsewhere (itself ratification-gated by H1.1 — this is belt-and-suspenders). One named-set residual remains: a newly-added kit `scripts/*.sh` is not control-plane until hand-enrolled in `is_control_plane_path` — a conformance check asserting full enrollment is a possible follow-up.

## [3.1.0] - 2026-06-17

**MINOR** — P1 of the post-3.0.0 backlog: turns the adapter `controlPlanePaths` from a declarative inventory into real enforcement (N5), plus profile parity and conformance-honesty hardening. Additive; the supported `typescript-node` path stays green.

### Added
- **N5 — `controlPlanePaths` union enforcement.** The `agent-boundary` gate now denies an unratified PR that touches any path in the **union of adapter-declared `controlPlanePaths`** (across `adapters/*/adapter.json`), in addition to the kit-standard `guard-core.sh::is_control_plane_path` floor. Entries match exactly or as a directory prefix (a value ending in `/`). So each harness's *own* control-plane surface is enforced — e.g. an unratified `AGENTS.md` edit (declared by the `generic` adapter, outside the guard-core set) is now caught. `jq`-absent or no `adapters/` degrades to the floor. `docs/operations/harness-adapters.md` updated from "future work" to "enforced."

### Fixed
- **Profile parity** — the `python` scaffold now sets `fail_under = 80` (the 80% coverage floor the profile + Definition of Done require); the GitLab `typescript-node` CI reference gains the conditional `gate-eval` the GitHub reference already had.
- **Conformance honesty** — `branch-protection.sh` adds a non-fatal advisory when `require_code_owner_reviews` is disabled (so builder ≠ sole reviewer stays visible on protected paths); `runtime-guards.md` now honestly enumerates the known guard-bypass classes (redirect/`printf` writes, `curl --data @file`, `git am`/`git apply`, interpreters) as within the speed-bump ceiling, rather than over-promising.

## [3.0.1] - 2026-06-17

**PATCH** — closes the four pre-announce conditions from the 3.0.0 go/no-go (an 11-dimension adversarial review: **GO-WITH-CONDITIONS, 0 blockers**). No new capability; makes the release safe to announce. The remaining Medium/Low findings are tracked as a 3.0.x fix-forward follow-up.

### Fixed
- **Brownfield safety (High):** `scripts/incept.sh` no longer silently overwrites an existing repo's `.github/workflows/ci.yml` or CODEOWNERS. It marker-detects the kit's *own* reference files (replacing them in a greenfield kit copy, as before) but **preserves and warns** for a genuine adopter file. (go/no-go #2)
- **Governance-doc honesty (High):** `docs/operations/harness-adapters.md` no longer claims an adapter's `controlPlanePaths` "feeds the `agent-boundary` gate's union." The gate enforces the `guard-core.sh::is_control_plane_path` set for *every* harness and does not read per-adapter manifests; the field is now described as a declarative inventory with the union-wiring named as future work. (go/no-go #3)
- **First-run DX (Medium):** `incept` now stamps a **stack-appropriate** default `PORT` into `.env.example` (3000 node, 8000 python, 8080 go/rust) instead of a hardcoded 8080 — fixing the documented `curl localhost:3000` for the default typescript-node stack. (go/no-go #4)

### Release integrity (go/no-go #1)
- The mis-pointed `v3.0.0` git tag (it pointed at an old v2.12.0-era commit) is corrected to the real 3.0.0 release commit, and the previously-untagged `2.63.0`–`2.65.0` releases are back-tagged — a release-maintenance action performed alongside this patch.

## [3.0.0] - 2026-06-17

**Harness-neutrality milestone — N4: proof, positioning, and the release.** Closes the LLM/harness-neutral arc (N1–N4): the kit is now usable with any agent harness out of the gate, with the enforcement floor **maintainer-verified to block regardless of harness**. **MAJOR as a milestone marker, NOT a breaking change** — an existing Claude Code adopter upgrades with nothing broken; everything added across N1–N4 is additive and the default experience is untouched.

### The milestone (N1–N4)
- **N1 (`2.63.0`)** — the `agent-boundary` CI gate: harness-independent control-plane ratification, so the §13 agent boundary holds on any harness (including one with no inline guard, because CI catches an unratified control-plane edit before merge).
- **N2 (`2.64.0`)** — the adapter boundary contract + `conformance/harness-adapter.sh` (the composing meta-check with the "lying-native" guard) + the `claude-code` reference adapter.
- **N3 (`2.65.0`)** — the `generic` floor-only adapter + `incept --harness` (multi-select, default `claude-code`) + Inception-Done enforcement (a project can't pass Inception unless each declared adapter conforms — greenfield **and** brownfield).
- **N4 (this release)** — see below.

### Added (N4)
- **`docs/operations/harness-enforcement-evidence.md`** — names the maintainer-verified enforcement proof: three deterministic, CI-locked surface selftests — `scripts/kit-guard --selftest` (the CLI surface any non-Claude runtime pipes through), `hooks/pre-push --selftest` (git-history), and `conformance/agent-boundary.sh --selftest` (the CI gate) — that block destructive/control-plane actions regardless of caller.
- **BYO adapters** — `adapters/_TEMPLATE/` (a floor-only skeleton that conforms immediately) + `scripts/new-adapter.sh <harness>` (mirrors `scripts/new-profile.sh`), so any harness (Cursor, Gemini, …) is a guided, validated path — parity with the stack BYO story.
- **Positioning** — the README is now explicitly **stack- AND harness-neutral**.

### Honesty / engineering notes
- **Split proof bar:** enforcement is *maintainer-verified* (the three surface selftests — deterministic, CI-locked — block any caller); process-following is *authored-to-contract*; and the **live cross-harness agent demo** (driving a real third-party agent end-to-end) is documented as the recommended **first real-world validation**, honestly *not* claimed as already-run. The floor is a maintainer-verified **speed bump, not containment** — the real boundary remains platform-owned (`docs/enterprise/platform-safety-boundary.md`).

## [2.65.0] - 2026-06-17

**Harness-neutrality — N3: the `generic` adapter + `incept --harness`.** Third slice of the LLM/harness-neutral milestone (→ `3.0.0`). The kit becomes pickup-able with a non-Claude harness out of the gate, provably enforced for greenfield **and** brownfield. **MINOR** — additive; the no-flag `incept` experience is unchanged.

### Added
- **The `generic` adapter** (`adapters/generic/adapter.json`) — an all-`floor` manifest (`mcp-gate: n-a`) that proves a harness with **no inline guard** (Codex, Cursor, Copilot reading `AGENTS.md`) clears the boundary contract entirely via the Kit-enforced floor (the git hook + CI backstop), with inline interception honestly absent.
- **`incept.sh --harness <list>`** — multi-select, comma-separated, **defaults to `claude-code`** (a no-flag run behaves exactly as before). Validates each name against the `adapters/` registry, stamps a **"Target harness(es)"** field into the project `CLAUDE.md`, and — after its transforms, on the real project — runs `conformance/harness-adapter.sh` per selected harness as a **loud, non-fatal** report (a brownfield adopter sees exactly which floor gaps remain).
- **Inception-Done enforcement** — `conformance/inception-done.sh` now reads the stamped harness field and **fails the gate** if any selected adapter doesn't conform to the boundary contract. This is the brownfield safety net: a merged repo can't pass Inception until its declared adapter(s) actually conform (greenfield passes; a non-conforming adapter blocks).

### Changed
- The kit dogfoods it: a `generic` real-run is added to the kit's `ci.yml` + `verify.sh`, and the CI bootstrap job now incepts with `--harness claude-code,generic` (exercising stamp → enforcement end-to-end).

### Honesty / engineering notes
- **Report at the action, enforce at the checkpoint:** incept reports gaps non-fatally so an adopter can finish setup and then close them; the Inception-Done gate is what blocks unsafe. Verified: incept does not rewrite `AGENTS.md` and removes no floor files, so a correctly-incepted project conforms post-transform — the enforcement is honest, not hollow. The BYO adapter `_TEMPLATE` and the live cross-harness demo are N4.

## [2.64.0] - 2026-06-17

**Harness-neutrality — N2: the adapter boundary contract.** Second slice of the LLM/harness-neutral milestone (→ `3.0.0`). **MINOR** — additive: a contract doc, the `claude-code` reference adapter, and a composing conformance check; no change to existing gates, nothing breaks.

### Added
- **Adapter boundary contract** (`docs/operations/harness-adapters.md`) — the 5 dimensions (`context-binding`, `command-guard`, `history-protection`, `review-roles`, `mcp-gate`), each with a **Kit-enforced floor** (the equal-enforcement guarantee — asserted for every harness) and an optional **Kit-assisted native** bonus, plus the JSON manifest schema.
- **`adapters/` + the `claude-code` reference adapter** (`adapters/claude-code/adapter.json`) — a declarative manifest that **references** the existing `.claude/` governance layer (not a copy): control-plane paths, binding files, and per-dimension `native`/`floor`/`n-a` with a per-dimension proof. The kit's `.claude/` stays exactly where it is.
- **`conformance/harness-adapter.sh`** — a *composing* meta-check (three-state; `--selftest`): validates the manifest, asserts the floor for **every** dimension by calling existing checks (`agents-brief.sh`, `guard-core-sourced.sh`, …), and runs each `native` dimension's declared proof so an adapter **cannot overclaim** (the "lying-native" guard — `command-guard: native` must pass `guard-wired.sh`; `mcp-gate: native` must pass `mcp-policy.sh`). It composes the existing checks, never reimplements them.

### Changed
- The kit dogfoods it: `harness-adapter.sh --selftest` plus a real-run against the `claude-code` adapter are wired into the kit's `ci.yml`, and the real-run is registered in the `verify.sh` aggregate.

### Honesty / engineering notes
- The **floor is the equal-enforcement guarantee** (asserted for every dimension regardless of declared level); `native` is an additive bonus whose claim must pass a real proof. The `generic`/AGENTS.md adapter + `incept --harness` are N3.

## [2.63.0] - 2026-06-17

**Harness-neutrality — N1: the agent-boundary CI gate.** First slice of the LLM/harness-neutral milestone (→ `3.0.0`). **MINOR** — additive: a new §13 governance gate + reference job + conformance check; the 7 required build gates are unchanged and nothing breaks. Claude Code stays the default, regression-locked.

### Added
- **`conformance/agent-boundary.sh`** — a harness-independent, three-state CI check (`0`/`1`/`2`; UNVERIFIED escalates under CI/`--require`) that fails a PR whose diff touches a control-plane path without an explicit human ratification signal (a CODEOWNER approval or the `ratified-control-plane` label — the label path was later removed in 3.2.0/H1.3 as agent-forgeable). Reuses `guard-core.sh::is_control_plane_path` (single source of truth — no forked path list); a pure decision core with an in-process `--selftest`.
- **`gate-agent-boundary`** reference job in `profiles/typescript-node/ci.yml` — computes the changed-file set + the ratification signal (label or a non-author approval, taking each reviewer's latest review) and runs the check fail-closed; a `gh` failure fails the step loudly. It is a §13 governance gate, **not** one of the 7 required build gates.
- **§13 contract clause** in `DEVELOPMENT-PROCESS.md` + a fourth surface row in `docs/operations/runtime-guards.md`: the gate makes "agents propose, humans ratify; never self-edit the control plane" hold on **every** harness — including one with no inline guard — because CI catches an unratified control-plane edit before merge.

### Changed
- The kit dogfoods the new check: `agent-boundary.sh --selftest` is wired into the kit's own `ci.yml` and registered in the `verify.sh` aggregate (so `ci-selftest-coverage` enforces it).

### Honesty / engineering notes
- **Split proof bar:** the enforcement half is deterministic and maintainer-verified (the selftest corpus + the conformance run); the live ratification shell (`gh`) runs only inside a real GitHub PR and is authored-to-contract — the gates catch deviation, the agent's compliance is not assumed.
- **Honest ceiling:** CI is post-hoc and `.github/workflows/*` is itself control-plane — the real boundary remains platform-owned (`docs/enterprise/platform-safety-boundary.md`).

## [2.62.1] - 2026-06-17

**PATCH** — closes the post-launch go/no-go backlog (per-stack reproducibility + container/config completeness). No new capability; makes 2.62.0's per-stack promises true. Several fixes Docker-verified.

### Fixed
- **go** — ship the `.golangci.yml` baseline (govet/staticcheck/errcheck/gosec) that profile §2 promised, and **pin** the `golangci-lint-action` version so green is reproducible. Refactored the scaffold to a configured `http.Server` (`newServer()`, `ReadHeaderTimeout`) to satisfy gosec G114; added its test (coverage 88.9%). *Docker-verified: lint clean + tests pass.*
- **typescript-node** — the Dockerfile `HEALTHCHECK` referenced an unbuilt `dist/healthcheck.js` **and** `node` isn't on `$PATH` in distroless. Added `src/healthcheck.ts` (coverage-excluded) and fixed the probe to `/nodejs/bin/node`. *Docker-verified: container reports `healthy`.*
- **dotnet** — added the `.editorconfig` + `Directory.Build.props` (`TreatWarningsAsErrors`, analyzers) profile §2 declared mandatory; fixed the Dockerfile to publish the app project only (not the `.sln`) and drop the non-existent root `packages.lock.json` COPY. *Docker-verified: build 0 warnings/0 errors, test passes.*
- **kotlin** — the one-time `gradle wrapper` step is now version-pinned (`--gradle-version 8.10`) so an older local Gradle can't generate an incompatible wrapper.
- **java-spring** — OWASP dep-scan now caches the NVD dataset and accepts an optional `NVD_API_KEY` secret, with a first-run caveat (keyless runs can rate-limit).
- **incept** — the scaffold-copy now skips stray build artifacts (`node_modules`, `dist`, `coverage`, `__pycache__`, `.coverage`, `target`, `bin`, `obj`, …) so a project incepted from a dirty dev tree stays clean.

## [2.62.0] - 2026-06-16

**Deliver the scaffold** — the second pre-launch go/no-go found the kit overclaimed turnkey readiness in its headline surfaces; this release makes those claims true. **MINOR** — additive (the new eval gate is conditional, not universally required); closes all seven verified Highs (H1–H7) from that review.

### Added
- **Per-stack starter scaffolds** (`profiles/<stack>/scaffold/`) for all 7 service stacks — manifest + lint/type config + a `/healthz` surface + its test, authored to each `ci.yml` gate contract. `scripts/incept.sh` copies the scaffold into an empty repo (brownfield-safe), so Inception's "green pipeline on the empty project" gate is reachable in one command. typescript-node is verified green on clone; go is clone-green by construction; the rest are authored-to-contract with a documented one-time lockfile/wrapper step (see each `scaffold/README.md`).
- **Reference eval harness** (`profiles/ml/evals/run.py` + `golden.jsonl` + `rubric.md`) — a deterministic, offline scorer runnable as `python -m evals.run --threshold 0.8`, green on clone with no API key (swap in a pinned LLM judge for production). `python` and `typescript-node` gain a **conditional `gate-eval`** that runs only when an `evals/` dir is present.
- **`.env.example`** is now created by `incept` and asserted by `conformance/inception-done.sh`; `incept` also guarantees `.env` is gitignored.
- **Stack-driven environments** — each service profile gains an "Environments this stack needs" section; `docs/STACK-SELECTION.md` gains a stack × backing-services matrix; `incept` now copies the profile's `compose.yaml`.

### Changed
- **`guard-wired.sh`** now structurally validates that the PreToolUse hook matcher admits the mutating tools (Bash/Write/Edit/NotebookEdit/`mcp__*`) — a misconfigured matcher no longer reports the guard as wired; jq-absent is UNVERIFIED (exit 2), never a silent pass. Adds `--selftest`.
- **`mcp-policy.sh`** jq-absent now exits 2 (UNVERIFIED) instead of 0 (PASS).
- **`go` + `rust`** ship a stateless (app-only) `compose.yaml` — no longer Postgres-by-default (their archetype is networked-service/CLI).
- Reworded the eval / scaffold / environment claims across README and the profiles to match what now ships (honesty invariant).

## [2.61.0] - 2026-06-15

**Discovery loop (FRAME + SHAPE)** — an **optional, opt-in** upstream front-end that turns a raw signal into a *Ready* backlog the Sparkwright engine consumes. **MINOR** — new docs + templates + one structural control; **no change to the existing process** (stages 3–6 are documented as the existing engine).

### Added
- **`docs/discovery/discovery-loop.md`** — the six-stage product loop (owner · ART=human turns · AI=tasks · gate · loop-backs); maps stages 3–6 onto Sparkwright's existing loop; states the opt-in/skip rule and the Ready seam.
- **`docs/discovery/frame.md` + `shape.md`** — the two new stage guides (FRAME = Product/Frame-approved; SHAPE = Design/Direction-chosen), each with its human-turns vs AI-tasks split.
- **`templates/OPPORTUNITY-BRIEF-TEMPLATE.md` + `SHAPING-DOC-TEMPLATE.md`** — the upstream artifacts that feed the existing FEATURE-REQUEST/SPEC at PLAN → Ready (no duplication).
- **`conformance/discovery-complete.sh`** — structural drift-guard (present + wired); wired into CI.
- Wiring: an ONBOARDING discovery door, README milestone link + What's-inside row, GLOSSARY entries.

### Honesty / engineering notes
- **Opt-in, never a turnstile** — arrive with a Ready backlog and you skip discovery entirely (the onboarding Practitioner fast-path). The default drop-in-and-build path is untouched.
- **Zero process change** — the core-3 docs are unchanged (900/900); the layer is all new files. The ART/AI split is guidance, not an automated gate (discovery is judgment work).

## [2.60.0] - 2026-06-15

**Named *Sparkwright* + execution-engine milestone.** The kit gets its real name — *Sparkwright* (`spark` + `-wright`, a maker who turns the spark into built, shipped software) — replacing the placeholder "Agentic SDLC Kit" descriptor across the prose. **MINOR** — naming + positioning only; no functional, contract, or process change (the product *name* is not logic-bearing; the repo slug stays `agentic-sdlc-kit` until a deliberate pre-launch rename).

### Changed
- **Name** — "Agentic SDLC Kit" → **Sparkwright** across README/MAINTAINING/START-HERE/templates/enterprise docs/scripts display text. "an agentic SDLC kit" is kept as the *descriptor* (clarity/SEO). Repo slug unchanged for now (renamed once, pre-launch).

### Added
- **Milestone positioning** — README now states Sparkwright is the **execution engine** (Ready backlog → operating, monitored software): drop it in and build. A **discovery front-end** (raw signal → Ready work — the FRAME/SHAPE upstream stages) is named as a **separate, optional upstream layer** on the roadmap, so the build-mode user is never forced through discovery they don't need.

## [2.59.0] - 2026-06-15

**Onboarding on-ramp** — a fluency-aware front door that meets developers across the experience spectrum (vibe-coder → principal), teaches *the system around the code* by routing to canonical sources (never duplicating the standards), and lets the agent adapt its assistance. **MINOR** — new front-door docs + a structural conformance control; no new universal-required gate.

### Added
- **`ONBOARDING.md`** — experience-axis front door: the *coding ≠ engineering* thesis + 3 self-select lanes (Novice / Adjacent / Practitioner, non-punitive to switch) + a layered Learning lane that motivates each pillar (TDD · 15-factor · security · governance · environments · observability) and routes to canonical sources + the existing kit docs. Hands off to `START-HERE.md` (role axis).
- **`docs/onboarding/first-feature-tdd.md`** — a worked red-green-refactor TDD walkthrough (reference stack), the one concrete code beat the whole-loop `WALKTHROUGH.md` lacked.
- **Operator fluency** — declared in the project-CLAUDE template (§3) and read by the agent via `docs/operations/operator-fluency.md`: adapts *communication* to the operator's level (explain + confirm-before-irreversible for Novice/Adjacent; terse for Practitioner), refined by observation, **never** changing what the agent is permitted to do. `incept.sh --operator-fluency <level>` stamps it; an undeclared run nudges (not walls) toward the on-ramp.
- **`conformance/onboarding-complete.sh`** — structural drift-guard: the on-ramp is present + wired (registered as a `verify.sh` control).

### Honesty / engineering notes
- **The on-ramp teaches; the guard + gates protect.** A bypass (the Practitioner lane / `--operator-fluency practitioner`) skips the *teaching*, never the *protection* — which is what makes "functional and not dangerous" hold even for someone who skips onboarding.
- **No duplication of the standards** — the Learning lane motivates and routes; the canonical content stays in the standards/profiles as the single source of truth (DRY).

## [2.58.0] - 2026-06-15

**Code-quality lens + CI-coverage lock** — a deliberately right-sized quality pass (pulled back from a 3-slice arc after a strategic check: the kit was already strong on `gate-lint`/type-checks/test-quality/coverage-ratchet/builder≠reviewer, so this polishes the last 20%) plus a meta-check that makes the kit's own CI enforcement self-auditing. **MINOR** — a new control check + adopter-facing review discipline; **no new universal-required gate** (the code-quality lens is review discipline, not a fail-closed gate, by design).

### Added
- **Code-quality lens** (`#85`): `docs/operations/code-quality.md` — the review dimensions a metric can't gate (readability · simplicity · function size · naming · comment quality · type/interface design · cohesion/coupling · dead code) + complexity/duplication as **recommended per-stack `gate-lint` config** (not new gates) + consistency as the through-line. `templates/CODE-REVIEW-CHECKLIST.md` for the §7 Review gate; a `+0` fold in `DEVELOPMENT-PROCESS.md` §7 naming the lens; the per-stack complexity/duplication linter line across all 10 profiles + `_TEMPLATE`.
- **Shellcheck regression-lock** (`#85`): `conformance/shellcheck.sh` lints the kit's **maintainer-editable** shell (`scripts/`, `conformance/`, `hooks/pre-push`) at the error/warning floor; conditional on shellcheck installed (SKIP-pass if absent; CI runs it for real). Kit shell made clean via justified `# shellcheck disable=SCnnnn # reason` comments.
- **CI smokes** (`#86`): `security-policy.sh` + `privacy-ready.sh` selftests and the `shellcheck.sh` real-run/selftest wired into the kit's own pipeline (closing the SP-2/SP-3/code-quality CI-wiring gap).
- **CI-coverage meta-check** (this release): `conformance/ci-selftest-coverage.sh` — flags (fail-closed) any selftest-capable kit check (`conformance/*.sh`, `scripts/*.sh`, `hooks/pre-push`) that is not wired into `ci.yml`, so a checker can't quietly ship "existing but unenforced." "Wired" means named in an execution context (comments and `name:` labels are stripped before matching, so a *mention* isn't mistaken for a *run*). **Self-excluded** (a meta-check can't non-circularly verify its own wiring — its presence in `ci.yml` is a one-time maintainer bootstrap). Registered as a `verify.sh` control; it gates the push **as its own real-run CI step** (the kit's `verify.sh --selftest` step is a renderer check and does not propagate control exit codes).

### Honesty / engineering notes
- **The shellcheck scope is honest, not maximal**: the §13 control-plane guard (`.claude/hooks/guard*.sh`) is **excluded** from the lint lock — it carries only benign warnings (redundant-but-still-denying case patterns + a `cls=read` false positive; no dead deny-rule, independently verified) and is regression-locked **behaviorally** by its own deny-corpus conformance instead. The README/header scope the claim to maintainer shell rather than overclaiming "the kit's own shell code."
- **A check "existing" ≠ "enforced"**: a `.sh` with a `--selftest` only protects against regressions once it runs in CI on every push. The coverage meta-check turns that from a thing a human must remember into a thing the kit guarantees.

## [2.57.0] - 2026-06-12

**Security & Privacy completeness arc** — closes the verified gaps from a repo-grounded gap-scan so the kit's security/privacy posture is whole before the pivot to UX/product-design. **MINOR** — new conditional gates + reference tools + readiness checks; no new *universal-required* gate. Three ratified, security-reviewed slices (#79 SP-1, #82 SP-2, #83 SP-3).

### Added
- **SP-1 — security gates** (`#79`): two **conditional** gates (the a11y/load/eval family). `gate-sast` (first-party static analysis — Semgrep default / CodeQL alt, per profile) for the injection/auth-bypass/SSRF class that `gate-dep-scan` and `gate-secret-scan` miss. `gate-license` — `scripts/license-check.sh` (sh+jq) acts on the existing CycloneDX SBOM: flags denylisted strong-copyleft (anchor spares weak-copyleft `LGPL`), evaluates every license entry + splits SPDX `AND`/`OR` expressions, and **self-flags undetermined/NOASSERTION** components, pointing to a **per-stack upgrade ladder** (`cargo-deny`, `go-licenses`, …) that keeps the same `gate-license` id. Named in §7/§14 + `conditional-gates.sh`; `docs/operations/security-scanning.md`.
- **SP-2 — disclosure policy** (`#82`): `templates/SECURITY-TEMPLATE.md` + `conformance/security-policy.sh` (conditional three-state; triggers on a governed repo via `CLAUDE.md`) + `incept.sh` scaffolding. The kit **dogfoods** its own `SECURITY.md` (GitHub private vulnerability reporting — anonymization-safe).
- **SP-3 — data governance** (`#83`): a 4-tier **classification scheme** (Public/Internal/Confidential/Restricted) + `templates/PRIVACY-REVIEW-TEMPLATE.md` (DPIA-lite) + `conformance/privacy-ready.sh` (triggers only on a declared Confidential/Restricted value → a recorded privacy review). `docs/enterprise/data-governance.md`. COPPA/children's-data framed as **one applicability, not a mandate**.

### Honesty / engineering notes
- **Conditional, not universal** — SAST/license/privacy apply on the N/A-with-reason basis; no forced friction on a CLI/IaC/Public-data repo. Green proves the scan *ran* / policy *applied* / posture *recorded* — never that code is secure, licenses legally cleared, or processing lawful (Manual operator rows).
- **License is stack-neutral but self-aware** — necessary-not-sufficient over the SBOM, with an explicit, contract-preserving upgrade path when an enterprise needs higher fidelity.
- **Guardrails held under pressure** — independent security-owner review per slice caught and fixed: 2 copyleft false-negatives + a CI-pin break (SP-1), an attempted doc-budget guardrail loosening (SP-2, reverted), and a privacy-gate fail-open (SP-3). The core-doc budget stayed at its deliberate 900 cap throughout.

## [2.56.0] - 2026-06-12

Modern Practices arc, Slice **MP-3 — agentic-ops**: observe and govern an agent's *own work*, the layer the kit lacked (the §13 guard *prevents* harm, §7 evals judge a *feature's* output, §2 tracks *spend* — none observed the **execution**). **MINOR** — new reference tools + contract + readiness rows; no new required gate (the tools are validated by their own selftests, not by failing a PR). Shipped as five ratified PRs (#73 MP-3a, #74 MP-3a.2, #75 MP-3b, #76/#77 kit-CI smokes), each independently security-reviewed (builder ≠ sole reviewer) → SHIP.

### Added
- **MP-3a — the trace contract + conformance** (`#73`): a stack/harness-neutral **agent-run trace schema** (OTel-GenAI-anchored required-core + recommended; identity-keyed `agent.id`/`run.id`/`work_item.id`/`parent.run.id` for multi-agent safety) in `docs/operations/agentic-ops.md`, the **sensor→§13-autonomy-tier** model, plus `conformance/agentops-ready.sh` (conditional, three-state, declared-discipline) + `agentic-ops-readiness.md` + RUNBOOK/CLAUDE declaration wiring.
- **MP-3a.2 — the dev-time emitter** (`#74`): `scripts/agent-trace.sh` (sh+jq+gh, the `dora.sh` idiom) derives a schema-conformant trace from a Claude Code JSONL transcript — transcript-native fields solid, `gh`/`git`-correlated fields best-effort (`unknown` when not derivable, never fabricated). The reference *adapter* in the "portable contract + thin per-harness adapter" model; turns the kit's own session transcripts into MP-3b's calibration corpus.
- **MP-3b — the behavior→tier loop** (`#75`): `scripts/agent-scorecard.sh` groups traces by agent, computes behavior metrics over a window, classifies each agent `regressed | steady | earned` against its **own trailing baseline**, and emits the **asymmetric** tier directive — fail-safe **auto-downgrade** on regression, **Security-owner-ratified raise** recommendation on earned improvement. Operationalizes the agent-quality-metrics → autonomy-adjustment §13 already names. §13 pointer (a `+0` append) + `agentic-ops-readiness.md` row 6.
- **Kit-CI smokes** (`#76`, `#77`): `agent-trace.sh` and `agent-scorecard.sh` `--selftest` run in the kit's own pipeline.

### Honesty / engineering notes
- **The kit emits directives; it never actuates** — it never mutates `.claude/`, the guard, or any tier store; the adopter wires the directive into their enforcement plane (the standing "real boundary is platform-owned" stance).
- **`unknown` = missing, never zero** — an agent is never downgraded on absent data; thin data (`< min-runs`) → `steady`/no-directive (fail-safe).
- **Relative-to-self, locally calibrated, no data pooling** — thresholds compare an agent to its own history; calibration is local to each adopter; the kit never phones home or pools agent-behavior data (a deliberate privacy property).
- **No new blocking gate** — behavior is trend-scored, not run-gated; the tools fail no PR (enforcement is the tier, via the adopter's plane). Each slice's independent review hardened it (MP-3a.2: timestamp-less-crash + path-traversal; MP-3b: two silent-drop bugs) before SHIP.

## [2.55.0] - 2026-06-12

Profile-depth: **deployable artifacts**. Closes the measured gap where only `typescript-node` shipped drop-in container/deploy companions — now **all 6 other service stacks** do, and the 3 non-service stacks document why they don't. **MINOR** — additive reference artifacts + a CI lock; the image gates were already in the contract (`conformance/container-supply-chain.sh`), so no new required gate. Shipped as four ratified PRs (#68 batch A, #69 batch B, #70 batch C, #71 kit-CI lock), each independently security-reviewed (builder ≠ sole reviewer) → SHIP.

### Added
- **Container/deploy companions for the 6 service stacks** (`go`, `rust`, `python`, `java-spring`, `kotlin`, `dotnet`): a stack-appropriate multi-stage non-root `Dockerfile` + `.dockerignore`, a `compose.yaml` (app + Postgres, §13 dev/prod parity), and a `deploy/` reference (k8s manifests + Helm chart) mirroring `profiles/typescript-node/`. Each wires the conditional container image supply-chain into `ci.yml`: `gate-image-sbom` (Syft/CycloneDX, on PR) + a push-only `image-provenance` job attesting provenance **bound to the image digest** (`gate-image-provenance`).
- **Reference-pointers for the 3 non-service stacks** — `ml` (model-serving / batch image), `data-engineering` (orchestrated job / code-location image), and `terraform` (**N/A by design** — `plan`/`apply` *is* the deploy) document the pattern in §9 instead of shipping a generic Dockerfile. Recorded as a convention in `MAINTAINING.md` §1.
- **`container-supply-chain.sh` wired into `conformance/verify.sh` (a control check) and the kit's own `.github/workflows/ci.yml`** — the new Dockerfiles are regression-guarded on every push/PR (multi-stage + non-root + both image gates; non-service profiles N/A).

### Honesty / engineering notes
- **Base images chosen for correctness, not uniformity:** python = `slim` **not distroless** (distroless-python tracks Debian's 3.11 and would silently downgrade the declared 3.12); `go` = distroless/static, `rust` = distroless/cc (glibc), JVM = distroless/java21, `dotnet` = chiseled aspnet (`USER 1654`).
- **No in-image HEALTHCHECK on distroless/chiseled** (java-spring, kotlin, dotnet) — they ship no shell/curl, so a HEALTHCHECK would be a claim that can't execute; k8s liveness/readiness probes (Actuator for Spring) are the health mechanism. Read-only root FS is paired with a writable `/tmp` emptyDir where the runtime needs it.
- **No devcontainer** for these stacks — distroless/chiseled have no shell to exec into; `compose.yaml` already delivers the §13 dev/prod-parity requirement.

## [2.54.0] - 2026-06-12

Modern Practices arc, Slice MP-2 — the developer inner loop, **with both MP-1 (test-quality) and MP-2 (inner-loop) tooling now completed across all 10 profiles + the template** (MP-1 had shipped them only to the python/typescript-node representatives). **MINOR** — guidance + per-stack profile tooling; no new gate.

### Added
- **`docs/operations/dev-inner-loop.md`** — the **three-tier feedback model**: **pre-commit** (format · lint · type-check · affected/fast test subset, seconds-fast, `--no-verify`-able) → **pre-push** (the agent guard) → **CI** (the authoritative §14 gate set). Layered, not redundant — fast checks on changed files locally; the full/slow gates in CI.
- **Per-stack test-quality + inner-loop tooling in all 10 profiles + `profiles/_TEMPLATE.md`** — mutation + property-based libs and a pre-commit inner loop, mapped to each stack (PITest/jqwik for JVM, Stryker.NET/FsCheck for .NET, cargo-mutants/proptest for Rust, go-mutesting/rapid for Go, etc.). For **data-engineering** and **terraform**, the existing `gate-data-quality` / `gate-policy` gates **are** the test-quality bar (mutation/property are N/A for SQL-dbt / HCL) — stated explicitly.
- **`MAINTAINING.md`** — a maintainer rule: cross-cutting per-stack tooling must reach **all** applicable profiles + the template, not just the representatives (recommended tooling isn't conformance-enforced, so piecemeal adds leave stacks thin).

### Honesty / agentic
- Pre-commit is a **recommended accelerator, not a gate** (gating it just trains bypass) — enforcement stays in CI + the guard. Tightens the agent's inner loop: faster feedback, fewer broken commits, less wasted CI.

## [2.53.0] - 2026-06-12

Modern Practices arc, Slice MP-1 — test quality beyond coverage. Adds the two practices the audit found genuinely absent, both especially relevant when **agents write the tests**. **MINOR** — guidance + STANDARDS principle + per-stack profile tooling; no new gate (mutation is too slow to gate every PR).

### Added
- **`docs/operations/test-quality.md`** — coverage ≠ quality. **Mutation testing** (injects bugs, checks the suite catches them; the honest test-quality signal — "green ≠ verified" applied to the suite itself; the reliable catch for an agent that gamed the coverage gate with assertion-light tests; run on critical paths / nightly, not every PR). **Property-based testing** (generative inputs find edge cases a human or agent didn't write). Per-stack tools for both.
- **`DEVELOPMENT-STANDARDS.md` §7** — a Test-quality principle (coverage = execution, not assertion strength) + a Property-based row in the testing pyramid.
- **Profile tooling** — `profiles/python.md` (`hypothesis` + `mutmut`/`cosmic-ray`), `profiles/typescript-node.md` (`fast-check` + Stryker).

### Honesty
- Both are **recommended, not fail-closed gates** — a green coverage gate stays necessary but is **not sufficient** evidence of test quality. The kit names the principle and ships the tools; the team sets the cadence + critical-path scope.

## [2.52.0] - 2026-06-11

Safe Non-Prod arc, Slice SNP-2 — ephemeral / preview environments. **Closes the Safe Non-Prod arc** (and the deferred list from the feature-coverage analysis). Seeds from SNP-1 test data. **MINOR** — guidance + conditional check + RUNBOOK record.

### Added
- **`docs/operations/preview-environments.md`** — per-PR isolated-environment lifecycle (open → exercise → auto-teardown) + the security guardrails (safe data only · scoped short-lived creds · TTL/auto-teardown · isolation; never prod data or secrets).
- **`conformance/preview-env-ready.sh`** + **`preview-environments-readiness.md`** — conditional, fail-closed check (binds on a **deploy surface**: Dockerfile or deploy workflow) asserting the RUNBOOK §4 records the preview-env approach; N/A for non-deployable. `verify.sh` now **8 doc-checks**.
- **`DEVELOPMENT-PROCESS.md`** §9 gains an ephemeral-preview-environments contract; **`templates/RUNBOOK-TEMPLATE.md`** §4 records the approach.

### Honesty
- A green check proves the approach is **recorded**, never that previews *actually* spin up / tear down / isolate / exclude prod data — those stay Manual operator rows. Conditional + proportional: non-deployable → N/A; recommended-not-required (a tiny tool may record N/A-with-reason). Records the colon-adjacent record-line lesson from SNP-1 (fresh→FAIL and filled→OK both verified).

## [2.51.0] - 2026-06-11

Safe Non-Prod arc, Slice SNP-1 — cross-stack test-data management. Closes the "never use prod data unsanitized — but *how*?" gap with a stack-neutral pattern + a light conditional check. The foundation preview environments (SNP-2) will seed from. **MINOR** — guidance + conditional check + RUNBOOK record.

### Added
- **`docs/operations/test-data-management.md`** — stack-neutral patterns: the **classify-then-handle** rule (public ok · PII/children's → synthetic or masked, never raw prod), synthetic generation, anonymization/masking (mask-on-extract), deterministic seeds, and the anti-patterns.
- **`conformance/test-data-ready.sh`** + **`test-data-readiness.md`** — conditional, fail-closed check (binds on a **data surface**: DB url in `.env.example`, a migrations/prisma/alembic dir, or a DB service in compose) asserting the RUNBOOK §2 records the test-data approach (not the placeholder); N/A for pure-compute projects. Wired into `verify.sh` (now 7 doc-checks) + CI.
- **`templates/RUNBOOK-TEMPLATE.md`** §2 records the test-data approach; **`DEVELOPMENT-STANDARDS.md`** §7 gains a test-data principle.

### Honesty
- A green check proves the approach is **recorded**, never that the data is *actually* synthetic/masked or that no prod data leaked — those stay Manual rows. Conditional + proportional: non-data projects → N/A (zero overhead). US-aware: PII / children's data → masked or synthetic (COPPA-grade).

## [2.50.0] - 2026-06-11

Responsible-AI arc, Slice RAI-3 — AI-governance crosswalk + agentic-threat lens. **Closes the Responsible-AI arc.** **US-first**; **MINOR** — documentation only, no gate/script.

### Added
- **`docs/enterprise/ai-governance-crosswalk.md`** — US-first map of the kit's AI-governance controls + the RAI artifacts to **NIST AI RMF + GenAI Profile** (the practical US anchor + TX TRAIGA safe harbor), **ISO/IEC 42001** (clauses + Annex A), **US state law / COPPA / FTC**, and **OWASP LLM + Agentic Top 10 + MITRE ATLAS**. The **EU AI Act** is a fenced optional overlay (only with EU market exposure; conformity-assessment / CE / FRIA / EU-DB are Org-owned, out of the US baseline). Sibling of `compliance-crosswalk.md` with the same honest `Responsibility` column.
- **Agentic-AI lens** on `templates/THREAT-MODEL-TEMPLATE.md` — an OWASP-Agentic-Top-10 (ASI01–10) subsection so an AI agent's threat model considers goal-hijack, tool-misuse, identity abuse, memory poisoning, human-trust exploitation, and rogue-agent behavior, each pointing at the kit control that mitigates it. N/A for non-agent features.

### Honesty
- The crosswalk **shows its own edges**: agentic-threat coverage is reported truthfully — **5 of 10 fully covered, 3 partial, 2 platform-owned gaps** (memory poisoning, inter-agent comms) — not a rounded-up number. ISO 42001 *certification* and state-law *legal determination* are **Org-owned**; the kit provides the evidence, not the compliance program.

### Arc closed
- The Responsible-AI arc (RAI-1 System Card · RAI-2 fairness + transparency · RAI-3 crosswalk + agentic lens) completes the third AI-governance axis — *is the AI fair, disclosed, human-overseen, risk-classified, and mappable to US regimes?* — alongside the existing eval gate (*is it good?*) and threat-model (*how is it attacked?*).

## [2.49.0] - 2026-06-11

Responsible-AI arc, Slice RAI-2 — fairness eval + AI-output transparency. The two genuine content gaps from the arc design, plus the good-citizen AI-incident feedback loop. **US-anchored** (EEOC / NYC LL144 / CO-CA consequential-decision; CA SB 942 / AB 2013 / COPPA-FTC; EU Art. 10/50 optional overlays). **MINOR** — additive templates; **no new gate or conformance script** (all Manual, owner-verified).

### Added
- **Fairness / bias eval dimension** — `templates/EVAL-PLAN-TEMPLATE.md` gains a Fairness/bias section (protected dimensions, disparate-impact / four-fifths metric, owner review; N/A for non-human-subject features) + a Manual row in `conformance/eval-readiness.md`. Rides the existing eval wiring.
- **`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`** — AI-output disclosure record (AI interaction disclosed · synthetic content labeled · C2PA provenance · children's-audience disclosure); referenced from the AI System Card + the responsible-ai-readiness transparency row. No separate §7 gate row — folds into the AI System Card gate (no gate proliferation).
- **AI-incident feedback** — `templates/POSTMORTEM-TEMPLATE.md` names AI incidents (harmful output, jailbreak, bias) and feeds the failing case back to the EVAL-PLAN red-team set, closing the eval loop.

### Honesty
- Fairness and transparency are **Manual** (owner-verified) — the kit records the dimension is *declared/considered*, never that the AI is *actually fair* or the disclosure *actually shipped*. All additions are N/A-able; non-AI and non-human-subject features carry zero overhead. No new fail-closed check.

## [2.48.0] - 2026-06-11

Responsible-AI arc, Slice RAI-1 — the AI System Card. Closes the substantive AI-governance gap surfaced by the feature-coverage analysis: the kit had eval (*is the model good?*) and threat-model (*how is it attacked?*) but not *is it fair, disclosed, human-overseen, and risk-classified?* **US-first** (NIST AI RMF + GenAI Profile anchor; TX TRAIGA / CO SB 26-189 / CA ADMT / COPPA-FTC the real surface; EU AI Act an optional overlay). **MINOR** — conditional check + two templates; no new universal gate.

### Added
- **`templates/AI-SYSTEM-CARD-TEMPLATE.md`** — the per-AI-feature declaration: model+version, **US risk classification** (consequential-decision / children's-data / prohibited-use triggers; optional EU overlay), intended/out-of-scope use, data flows+consent, human oversight, guardrail links, known limitations, security/compliance-owner sign-off. Doubles as the ISO/IEC 42005 impact assessment.
- **`templates/AI-POLICY-TEMPLATE.md`** — one-page org AI policy (ISO 42001 Clause 5.2).
- **`conformance/responsible-ai-ready.sh`** + **`conformance/responsible-ai-readiness.md`** — conditional check (binds on an AI feature: `evals/`, `EVAL-PLAN`, `AI-SYSTEM-CARD`, or `AI feature: yes`) asserting the card is **present + classified + oversight-named**; N/A for non-AI. Wired into `verify.sh` + CI + a §7 gate row.

### Good-citizen guardrails (opt-in, never gated)
- Distilled the *substantive* best practices from EU AI Act (Arts. 10/12/14/15/50/72) + US state law into recommended template lines — **prohibited-use acknowledgment, data-minimization, human review/appeal path** — that the fail-closed check does **not** enforce. Lean into the good practice, skip the certification bureaucracy.

### Honesty
- A green check proves the card is **declared/classified/recorded**, never that the classification is *correct*, the AI is *fair*, or it is *compliant* — those stay Manual security/compliance-owner rows. Conditional + proportional: non-AI → N/A (zero overhead); low-risk = a two-line card. US-first: no EU-only burden (conformity assessment / CE / FRIA / EU-DB) in any baseline.

## [2.47.0] - 2026-06-11

Gate parity, Slice 2 — observability/SLO and threat-model get the declared-artifact treatment, **closing the gate-parity arc**. Both were named in prose but lacked an artifact: observability had no readiness check, the threat-model gate had no template. **MINOR** — one conditional check + two templates; no new universal gate.

### Added
- **`conformance/observability-ready.sh`** + **`conformance/observability-readiness.md`** — conditional check (binds on a deploy surface: Dockerfile or deploy workflow) asserting the observability posture is **recorded** — RUNBOOK §8 declares an `SLOs:` target and a `Telemetry wired:` signal set (not placeholders); N/A for non-deployed. Wired into `verify.sh` + CI. Mirrors the `resilience-ready` family.
- **`templates/THREAT-MODEL-TEMPLATE.md`** — STRIDE + LINDDUN-lite privacy lens + security-owner sign-off. Wired into the §7 security gate, the DoR threat-model flag, the templates list, and `DEVELOPMENT-STANDARDS.md` §2. **No conformance script by decision** — a script cannot tell a real threat model from a box-ticked one, and "sensitive" is not honestly auto-detectable.
- **`templates/RUNBOOK-TEMPLATE.md`** §8 now records SLOs + telemetry (the keyed phrases `observability-ready.sh` greps).

### Honesty
- Each readiness check proves the posture is **declared/recorded**, never that it **works** — signals emitting in prod, alerts firing, the error budget being tracked, and the threat model's *quality* stay **Manual** operator/security-owner rows. Necessary, not sufficient.

## [2.46.0] - 2026-06-11

Gate parity, Slice 1 — eval-driven development gets the kit's declared-artifact + conformance treatment. The AI-feature Eval gate was named in prose but lacked a template and a readiness check; this closes that. **MINOR** — additive template + conditional check; no new universal gate.

### Added
- **`templates/EVAL-PLAN-TEMPLATE.md`** — the AI-feature eval artifact (dataset + rubric, regression threshold, safety/red-team, pinned judge + model version, harness, model-upgrade-regression trigger).
- **`conformance/eval-ready.sh`** + **`conformance/eval-readiness.md`** — conditional check (binds on an AI-feature signal: `evals/` dir, `EVAL-PLAN.md`, or `AI feature: yes`) asserting the eval discipline is **declared** (plan + threshold + harness recorded); N/A for non-AI. Wired into `verify.sh` + CI.

### Honesty
- The readiness check proves the discipline is **declared**, never that the evals **pass** — execution stays the §7 Eval gate (CI runs the suite); red-team + judge-independence are Manual rows. Necessary, not sufficient.

## [2.45.0] - 2026-06-11

Task Context Contract (TCC) — declared per-step context envelope. Applies the kit's "declare the contract, make it inspectable" discipline to the build/dispatch layer: a qualifying agent step now carries a declared Reads (constraints/inputs) · Writes · Prohibitions contract, verified by the same reviewers. **MINOR** — additive template + tool-neutral process convention; advisory (no new gate), no behaviour change.

### Added
- **`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`** — the four-sided contract + constraints-vs-material framing, the proportionality rule (full TCC on governing-surface OR security OR multi-file; one-line default otherwise), conflict precedence, the honesty note (declared ≠ obeyed), reviewer-binding, and a worked example.
- **`DEVELOPMENT-PROCESS.md`** — §12 "Context-bound dispatch" convention (tool-neutral; reviewer receives the same contract), §13 Auditability extended to record which governing clauses bound each action, §15 artifact-flow row.

### Notes
- **Advisory in v1** — no conformance drift-guard yet (added only once the format proves out). The self-improving "recurring-violation → promote" loop is a deferred fast-follow.
- Origin: evaluation of the ICM paper (arXiv:2603.16021v2), whose declared per-stage inputs + reference-vs-working distinction surfaced the gap. No new runtime dependency; superpowers remains authoring-only.

## [2.44.0] - 2026-06-11

Arc exit gate + secret.read remediation (A9 + Slice 11e — **Containment arc CLOSED**). The exit-gate red-team (A9) confirmed W3 closed-in-kit and W2 honestly-bounded, and caught one blocker: the MCP gate allowed `secret.read` tools (A8 family 6) despite A8 designating them deny-by-default. 11e closes it. **MINOR** — additive gate coverage + the A9 findings artifact.

### Added
- **A9 arc-exit red-team** — three adversarial red-teams (MCP gate / egress+containment honesty / cross-arc ledger); verdict: arc closes honestly once `secret.read` is gated. W3 → closed-in-kit; W2 → honestly-bounded/platform-owned.
- **`secret.read` gating** (`guard_check_mcp`, Slice 11e) — secret-material reads are now deny-by-default by **name**: an action naming a secret (`secret/credential/password/api_key/private_key/access_token…`) **or** a known secret-store server (`vault/1password/secretsmanager/keyvault/doppler…`) on a read → deny, even when a read verb leads. Restores A8 family 6. Corpus cases added; allowlist/override escape hatches preserved.

### Honesty
- The gate's honest ceiling is updated: a secret read via a **generic-named** server/action (`mcp__storage__read_blob` holding a credential) is **not** caught by name — the real controls are the platform egress allowlist + the 11c sandbox.
- **Carried residual:** attestation in `egress-policy.sh` / `containment-ready.sh` is honor-based (disclosed since 2.43.0); keep the Manual-row adjacency explicit in auditor-facing packaging.

### Containment arc — closed
W2 (no interpreter-egress control) → **honestly-bounded, platform-owned** (reference shipped + wiring verified three-state; in-process tail never claimed closed). W3 (guard saw only Bash-family tools) → **closed-in-kit** (MCP capability gate, deny-by-default incl. secret.read, Kit-enforced by name, regression-locked). No green check implies containment a shell can't deliver.

## [2.43.0] - 2026-06-11

Honesty & assurance restatement (Slice 11d — Containment arc). Reconciles the kit's narrative/summary docs to the post-11a/b/c reality and regression-locks the responsibility tiers. **MINOR** — docs + one drift-guard; no behaviour change.

### Added
- **`conformance/assurance-tiers.sh`** — drift-guard asserting the compliance crosswalk states each arc control at its real tier (MCP capability gate = **Kit-enforced**; egress / sandboxed FS / scoped tokens / separate prod creds = **Kit-assisted**); `--selftest`; wired into CI and `verify.sh` (live control).
- **MCP capability gate** now recorded in the compliance crosswalk + audit-evidence checklist as **Kit-enforced** (with the honest by-name caveat: it gates MCP tool capability by name; the net.egress class is a name-match speed bump).

### Changed
- `platform-safety-boundary.md`, `EXEC-BRIEF.md`, and `DEVELOPMENT-PROCESS.md` §13 reconciled: the guard is a speed bump for shell/interpreter **and** a deny-by-default MCP capability gate (Kit-enforced); the four platform controls are kit-referenced + verify-wired (**Kit-assisted**) — enforcement remains platform-owned. No caveat removed (no overclaim).
- `containment-readiness.md`: documented that attestation dates are honor-based (the carried 11c LOW — resolved by documentation; both candidate code fixes would false-negative).

### Honesty
- The restatement only **adds qualifiers**; every honest caveat (deny-list speed bump, "these four controls are the boundary", platform-owned enforcement) is preserved. "Kit-enforced" appears only for the MCP gate, always with the by-name caveat. The drift-guard verifies the tiers are *stated*, not "true".

## [2.42.0] - 2026-06-11

Sandbox + scoped-credential references + conformance (Slice 11c — Containment arc). Formalizes platform-safety-boundary controls #2/#3/#4 (sandboxed FS · scoped tokens · separate prod creds) as a declared, verifiable posture. **MINOR** — conditional three-state check + reference docs; no new universal gate.

### Added
- **`docs/operations/containment.md`** — reference: read-only-FS compose/devcontainer snippet, OIDC→role short-TTL token pattern, separate-prod-creds/break-glass pattern + how to attest.
- **`conformance/containment-ready.sh`** — one conditional three-state check over three sub-aspects (Sandbox FS / Scoped tokens / Prod credentials), overall = weakest aspect; UNVERIFIED escalates under CI/`--require`; `--selftest` corpus; CI-wired. Pairs with `conformance/containment-readiness.md` (Auto vs Manual).
- **RUNBOOK** containment attestation lines (`templates/RUNBOOK-TEMPLATE.md`).

### Changed
- Compliance crosswalk + audit-evidence: the three agent-boundary rows (#2/#3/#4) **Org-owned → Kit-assisted** (reference shipped + wiring verified). `platform-safety-boundary.md` notes each is now reference-shipped + verify-wired.

### Honesty
- The check **verifies declaration + attestation, never enforcement** — PASS ≠ "FS actually read-only / tokens actually expire / prod creds actually unreachable" (Manual rows). UNVERIFIED is a first-class non-pass; enforcement stays platform-owned.

## [2.41.0] - 2026-06-11

Egress-allowlist reference + conformance (Slice 11b — Containment arc, the honest W2). Ships a default-deny network-egress reference and verifies the platform control is declared + attested-wired. **MINOR** — conditional three-state check + reference docs; no new universal gate.

### Added
- **`docs/operations/egress-control.md`** — default-deny network-egress reference (k8s `NetworkPolicy` paved road + cloud-egress-firewall / forward-proxy patterns + how to attest).
- **`conformance/egress-policy.sh`** — three-state check (PASS declared+attested · UNVERIFIED declared-not-attested · FAIL networked-undeclared · N/A no-surface), escalating UNVERIFIED→FAIL under CI/`--require`; `--selftest` corpus; CI-wired. Pairs with `conformance/egress-readiness.md` (Auto vs Manual).
- **RUNBOOK** egress attestation line (`templates/RUNBOOK-TEMPLATE.md`).

### Changed
- Compliance crosswalk + audit-evidence: egress row **Org-owned → Kit-assisted** (reference shipped + wiring verified). `platform-safety-boundary.md` notes egress is now reference-shipped + verify-wired.

### Honesty
- The check **never inspects traffic** — PASS = declared + attested, not "packets are dropped" (a Manual row). Interpreter/DNS/build-tool exfil is impossible to gate in-process (A8 Part 2); enforcement stays platform-owned. UNVERIFIED is a first-class non-pass.

## [2.40.0] - 2026-06-11

MCP capability gate (Slice 11a — Containment arc). Closes W3: the guard now sees MCP tool calls and denies un-allowlisted destructive/egress MCP capabilities by default. **MINOR** — additive in-kit control + a portable contract; no universal gate added.

### Added
- **`guard_check_mcp`** (in `guard-core.sh`) — classifies `mcp__<server>__<action>` by action verb; read-only allowed, destructive/egress denied, **fail-closed** on the unclassifiable. The Claude PreToolUse matcher now routes `mcp__.*`; `.claude/mcp-policy.json` (control-plane-protected, shipped empty-allow) carries the per-project allowlist + classOverride; `kit-guard mcp` exposes the same gate to any runtime (the portable mcp-policy contract).
- **`conformance/mcp-policy.sh`** — classification corpus (deny destructive, allow read, honor allowlist/override, fail-closed). CI-gated; plus `agent-autonomy.sh` MCP live-path cases.

### Honesty
- The gate is **Kit-enforced for what the tool name reveals** — a renamed/obfuscated action is not caught, and the egress class is a name-match speed bump, **not** egress containment (the platform allowlist, 11b). Documented in `runtime-guards.md` + `platform-safety-boundary.md`.

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
- **Competitive benchmark** — the A5 record behind the brief's differentiation (with sources).

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

Slice 6a — Enterprise addendum, pillar 1: the compliance crosswalk. First of four sub-slices.

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

[2.7.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.7.0
[2.6.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.6.0
[2.5.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.5.0
[2.4.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.4.0
[2.3.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.3.0
[2.2.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.2.0
[2.1.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.1.0
[2.0.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.0.0
[1.0.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v1.0.0
