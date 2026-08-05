# Threat Model

**System:** Sparkwright — an agentic SDLC kit. **Version:** 3.185.0 · **Date:** 2026-07-25
**Owner:** Bradley James · **Data classification:** Internal (the kit holds no customer data)

> **Why this exists.** The kit ships an **autonomous agent control plane**: a pre-tool-use guard with
> 45 deny rules, a promotion/ratification system that decides when a human must approve, and a
> conformance suite whose green is the signal adopters trust. A defect in any of those is a governance
> failure, not a bug. This model covers the **kit itself**, not the applications built with it — an
> adopter writes their own from `templates/THREAT-MODEL-TEMPLATE.md`.

## System & assets

| Asset | Why an attacker wants it | Where it lives |
|---|---|---|
| **The guard's deny set** | Disarming it gives an agent destructive shell, secret reads, and control-plane writes | `.claude/hooks/guard-core.sh` |
| **The change-class derivation** | Downgrading `control-plane`→`ordinary` removes the independent-ratifier requirement | **The whole derivation chain, not one script.** The *listing* is built by `.github/workflows/ratification.yml`, `profiles/ratification.yml` (adopter-facing) and `.github/workflows/ci.yml`; it is *classified* by `conformance/promotion-readiness.sh` and `conformance/obligation-lib.sh`, and *consumed* by `conformance/agent-boundary.sh`. Naming only the classifier is what let T2 hide: the classifier was hardened while three listing-builders still collapsed renames. **No class-wide lock guards this chain** — one was built and withdrawn (boarded `CHANGESET-DERIVATION-LOCK`); the only automated guards are `ratification-parity.sh`'s two anchors on the emitted profiles |
| **The obligation gates** | Suppressing them lets sensitive/regulated changes ship with no threat model, UAT or a11y record | `conformance/*-obligation.sh`, `conformance/obligation-lib.sh` |
| **The conformance green** | A vacuous PASS is worse than a FAIL: it is false assurance an adopter acts on | all of `conformance/` |
| **The published mirror** | It is what adopters install; a poisoned publish reaches every downstream tree | `scripts/publish-public.sh` |
| **CI credentials** | `GITHUB_TOKEN`, the release/publish path | `.github/workflows/*` |

**Not assets:** the kit stores no customer data, no PII, no payment data, and holds no production
credentials. Its value to an attacker is **leverage over downstream repos**, not data at rest.

## Trust boundaries

1. **Agent → repository.** The agent proposes; the guard is the enforcement boundary. Crossing it
   without a recorded GO is the central threat.
2. **Contributor → control plane.** `conformance/`, `.github/workflows/`, `skills/`, `agents/`,
   `.kit/` require §13 ratification by a non-author.
3. **Kit → adopter.** The public mirror. Everything crossing it is inherited by trees we never see.
4. **CI → forge.** Workflow tokens, branch protection, the release tag.
5. **Untrusted text → verdict.** Board rows, records, commit messages and glob arguments all reach
   check output that a human or a status API reads.

## Threats (STRIDE) + mitigations

| # | Threat | Vector | Mitigation | Residual |
|---|---|---|---|---|
| T1 | **Elevation** — agent disarms the guard | `KIT_GUARD_SELFEDIT=1`, or editing `guard-core.sh` | Global kill switch is documented as never-use; control-plane edits routed to a dev-clone with the guard armed on the real repo; `agent-autonomy.sh` fixtures per mutation form (Write/Edit, `>` redirect, `sed -i`) | An interpreter invocation is the canonical bypass — **disclosed, not closed**; the platform, not the guard, is the real boundary |
| T2 | **Tampering** — control-plane change ships without a ratifier | Rename a file out of the control-plane set so `--class` derives `ordinary` | **MITIGATED this release, at all FIVE derivation sites.** The first analysis named only the classifier and was wrong about where the threat lived: `promotion-readiness.sh` is *advisory*, while the **required** `control-plane-ratification` gate reads a PR-files-API listing that collapses a rename to its destination (the source survives only in `previous_filename`, which nothing read). Fixed: the three API listings project `previous_filename`; the two git derivations pass `--no-renames`; `ratification-parity.sh` anchors the `previous_filename` projection so no emitted profile regresses (load-bearing negative present). **No class-wide lock ships with this release** — one was built and withdrawn: a text scanner over shell source was defeated three times across three review rounds (a same-line decoy, a continuation decoy, a trailing-backslash line never scanned, then a comment-continuation that blinded it entirely, flag reordering that hid `git diff -M --name-only`, and a pipe that is not a segment boundary), and each repair introduced roughly as many holes as it closed. Boarded as `CHANGESET-DERIVATION-LOCK` with that evasion catalogue as required design input. **So the five sites are fixed and individually mutation-proven, but nothing observes the CLASS: a sixth collapsing derivation would be unobserved.** The API listings additionally carry a **newline guard**, because `jq -r` emits a raw newline and a crafted filename otherwise split one API entry into two lines that each classified separately — measured to defeat the suffix-constrained `agents/*.agent.md` pattern and post the required gate GREEN. All monotone — a rename can only *add* the source path. Mutation-proven, including under a hostile host `diff.renames=false` | **Residual, and real.** (a) **CLOSED this release, and the earlier wording here was wrong.** A newline in a filename splits the path so each fragment is classified alone; this document previously claimed "control-plane is fail-safe" from that, which is **false** — `is_control_plane_path` includes SUFFIX-constrained patterns (`agents/*.agent.md`), so `agents/x⏎.agent.md` splits into `agents/x` + `.agent.md` and **neither** matches (measured; a control-plane→ordinary downgrade). POSIX `sh` cannot *preserve* such a path, but it can *detect* one: the `-z` stream carries a newline byte only when a filename does, so both producers now treat that as a **derive failure** and fail-safe. Mutation-proven. (b) **No class lock ships.** The five sites are fixed and each is individually mutation-proven, but nothing detects a **sixth** collapsing derivation — a new workflow listing, or a new producer, would be unobserved until someone noticed. This is the largest residual in this row and it is deliberate: the withdrawn scanner is boarded as `CHANGESET-DERIVATION-LOCK`, because shipping a check whose own claim register was demonstrably false is worse than shipping none. (c) The GO record's `--class` is self-asserted and never cross-checked against the derivation (boarded, `PROMOTION-GO-CLASS-CROSSCHECK`). (d) `enforce_admins: false` — see residual #6. (e) **The Files API returns at most 3000 files.** `--paginate` then simply stops — a *success*, not an error — so neither `set -e` nor the empty-listing escalation fires, and a control-plane path past the cap is invisible to the required gate. Not introduced or worsened by this release (the cap counts entries, not lines); reachable in a monorepo adopter and paddable deliberately. **Unguarded — disclosed, not closed.** |
| T3 | **Repudiation** — what merged ≠ what was approved | Push after approval; merge a different tree | `dismiss_stale` on push; `promotion-verify check` asserts `shipped == approved` by **tree equality** on both main and the tag | Requires the operator to actually run `check` — it is a step, not a trigger |
| T4 | **Information disclosure** — secret reaches the public mirror | A new file ships by allow-by-omission | `publish-public.sh` runs gitleaks + a sensitivity scan **fail-closed** before push; `.gitattributes export-ignore` strips internal artifacts | New-public-surface is still **allow-by-omission** (boarded, `PUB-POLICY`) |
| T5 | **DoS** — a check hangs or exhausts CI | Malformed argument to a gate | Fixed this release: a value-less gate-defining flag spun forever emitting ~7 MB/s (44 MB in 6 CPU-s). Now a named FAIL | Other unbounded loops not systematically audited |
| T6 | **Spoofing** — author approves their own control-plane change | Self-approval | `author-not-approver-wired.sh` + §13 requires a non-author ratifier; `builder ≠ ratifier` | Solo operation depends on a second identity being genuinely separate |
| T7 | **Tampering** — a gate passes by not running | Vacuous green | Non-vacuity sweep mutates every check and requires the mutant to die; liveness anchors paired with load-bearing negatives | **`artifact-gate` is vacuously green over ~61 files** — semgrep cannot parse a one-line `case` and swallows to EOF. Boarded `SAST-PARSE-COMPLETENESS`. **Parse completeness is observable by no gate.** |
| T8 | **Elevation** — an obligation gate is switched off by its caller | `--record DECOY.md`, `--exclude-globs '*'`, `--stub-pattern` | Closed this release: `--` sentinel + first-assignment-wins fence five gate-defining arguments; universal-glob refusal; exclusion shape assertion | `KIT_OBL_TEST=1` in the **environment** still reopens the engine's fixture flags (boarded `OBLIGATION-TESTMODE-ENV-FLAG`). `ceremony-binding`'s own env-borne flag (`KIT_CB_TEST` enabling `--changed`) is **removed** — the gate implements no fixture flag, and argv `--changed` is refused rc 2 (slice A4) |

## Privacy (LINDDUN-lite)

The kit processes **no personal data**. It stores contributor handles in commit metadata and
promotion notes (`refs/notes/promotions`) — GitHub identities already public in the repo history.
No DPIA required; `privacy-ready.sh` correctly derives N/A for this project.

**One caveat:** adopter trees may hold PII. The kit's obligation gates read **path names only**, never
file contents, so no adopter data crosses into kit-owned tooling.

## Agentic-AI lens — OWASP Agentic Top 10

| Risk | Posture |
|---|---|
| **Excessive agency** | The guard's deny set plus the recorded-GO requirement. Agents actuate mechanics; humans hold judgment. `runaway-guard.sh` caps token/step/agent dimensions. |
| **Prompt injection** | Board rows, records and glob arguments are attacker-influenceable text reaching check output. Verified this release: injection battery (`$(id)`, backticks, format strings, raw ANSI) produced **zero** command execution and zero caller bytes in any verdict. |
| **Tool misuse** | Gate-defining arguments are fenced (T8). Fixture flags are test-mode gated — **except via the environment** (open). |
| **Identity & impersonation** | `builder ≠ reviewer ≠ ratifier`, enforced by §13 and the non-author check. |
| **Unsafe output handling** | Check verdicts strip control bytes before rendering template-controlled text (the ANSI-repaint fix in `a11y-obligation.sh`). **Extended this release to `promotion-readiness.sh`'s surfacing**, where it was a *forgery* vector, not merely cosmetic: v3.184.0's `PROMOTION-PATH-QUOTING` replaced git's `core.quotePath=true` (which **escaped** control bytes) with `-z` + `quotePath=false` (**raw** passthrough), and PR authors name files. Measured: a filename carrying `CR` + `ESC[2K` + `ESC[1A` printed a **forged** `Change-class (aggregate): ordinary` line and scrolled the true `control-plane` line out of view — on the surface a human reads to give the §13 GO. Stripped at the **render** boundary only; stripping before `classify_path` would let a crafted name become a *lower* class (the fail-open direction). Board-controlled text still reaches `echo` in `backlog-current.sh` — pre-existing, exit code unaffected. |
| **Memory / context poisoning** | Agent memory is advisory; every load-bearing claim is re-measured. This release recorded twelve cases of an executor correctly refusing a false instruction from its own brief. |

## Residual risk

**Accepted, tracked, and disclosed at the point of use:**

1. **No class-wide lock guards the change-set derivation (MED)** — T2 above is mitigated at all five
   **known** sites, each individually mutation-proven, but nothing detects a **sixth**. A scanner was built
   and withdrawn: over three review rounds it was defeated by a same-line decoy, a continuation decoy, a
   trailing-backslash line it never scanned, a `\`-terminated **comment** that hid an entire derivation,
   an **argument reorder** (`diff "$base"...HEAD --name-only -z`) that drops `--no-renames` while looking
   harmless, and `&`/`|`/subshell separators its segmenter did not treat as boundaries. Each repair opened
   roughly as many holes as it closed, and its own claim register was demonstrably false — so it is boarded
   (`CHANGESET-DERIVATION-LOCK`) with that catalogue as required design input rather than shipped. Keeping
   the two producer derivations convergent is a **human** obligation until it lands. It also cannot tell whether a given
   listing is actually consumed by a classifier; it assumes any workflow-level listing is, which is the
   fail-safe direction. **No class-wide lock ships this release** (see T2 residual (b)); the five known
   sites are fixed and mutation-proven individually, and a sixth would be unobserved.
   **`profiles/` paths classify `ordinary`** — measured: `profiles/ratification.yml` and `profiles/*/ci.yml`
   both derive `ordinary`, so **the adopter-facing §13 gate and the ten emitted CI workflows can be edited
   with no independent ratifier**. That is a governance gap in its own right, independent of T2, and it is
   the reason a self-service exemption sentinel was judged unsafe to ship. Boarded as
   `PROFILES-ORDINARY-CLASS`.
   **One git derivation remains unguarded against newline splitting:** `.github/workflows/ci.yml`'s
   `backlog-presence` listing pipes `-z` output through `tr` without a newline check, so a crafted path
   still mis-splits there. Its consumer is board hygiene, not the ratifier, so the reachable impact is a
   wrong `backlog-presence` verdict rather than a §13 downgrade — **disclosed, not closed**.
   Sibling residuals: the **newline-in-filename** downgrade is **CLOSED this release** — both git producers
   fail-closed on a newline byte in the `-z` stream, and the three API listings carry a `jq` guard that
   refuses a splittable listing (the earlier wording here, "control-plane is fail-safe", was **false**: the
   suffix-constrained `agents/*.agent.md` pattern is defeated by a split — see T2 residual (a)). Still open:
   the GO record's `--class` is self-asserted and never cross-checked against the derivation (boarded,
   `PROMOTION-GO-CLASS-CROSSCHECK`), and a trailing `\r` or space in a path defeats the same
   suffix-constrained patterns (lower reachability — such a name is inert to the filesystem glob — but the
   *class* "a control byte in a filename defeats a suffix-constrained pattern" is only half closed).
2. **`SAST-PARSE-COMPLETENESS` (MED)** — T7. **Now the highest open item.** The SAST control is blind to
   most of the shell fleet.
3. **`OBLIGATION-TESTMODE-ENV-FLAG` (LOW)** — T8. Requires control of the process environment.
4. **Guard bypass via interpreter invocation** — architectural, disclosed since CP-8. The guard is a
   speed bump; the platform is the boundary.
5. **Obligation gates are path heuristics** — a file holding PII with no telltale name derives N/A.
   Named misses: `medical/`, `biometric`, `passport`, `iban`, `tax_id`, `nhs_number`, ALL-CAPS
   `PERSONAL-DATA/`.
6. **The three obligation jobs are now REQUIRED contexts on this repo — with two live caveats, so this
   is not "enforced" without qualification.** Verified against the live API 2026-07-25: `main` requires
   **8** contexts (`conformance`, `bootstrap`, `docs-links`, `control-plane-ratification`,
   `backlog-presence`, `threat-obligation`, `uat-obligation`, `a11y-obligation`).
   (a) **Nothing in-repo declares them**, so silently removing one is undetectable — `branch-protection.sh`
   only asserts that required-status-checks *exists at all*, which stays green if seven of the eight are
   deleted. Boarded: `BRANCH-PROTECTION-DECLARATION-LOCK`.
   (b) **`enforce_admins: false`**, and the kit's own prescribed solo route is `gh pr merge --admin`
   (`docs/governance/promotion-contract.md`) — which **bypasses all eight**. On that route the obligation
   gates remain effectively advisory, and the real control is the recorded GO, not the check.
   Adopters who enable `enforce_admins` and require reviews get the stronger property.

**Explicitly not accepted:** a vacuous green. Where a check cannot prove its claim, it says so in its
own header rather than passing quietly.

## Sign-off

**Threat model reviewed by:** security-reviewer (independent lens; `builder ≠ reviewer`)
**Date:** 2026-07-25 · **Kit version:** 3.186.0
**Basis:** first written during Slice B `OBLIGATION-HARDEN` (closed T5/T8, surfaced T2/T7). **Revised in the
T2 slice**, whose *plan review* — `reviewer` + `security-reviewer` dispatched on the design and plan
**before any build** — established that this document's own T2 analysis was scoped to the wrong asset: it
named the classifier when the threat lived in the three *listing builders* feeding it, two of which were
live bypasses and one of which ships to every adopter. That finding is why the asset row above now names
the whole chain. **The re-review trigger below fired on this slice** (a change to the promotion contract's
derivation) and the review happened at the plan gate rather than after the fact.
Re-review when the control plane changes shape — a new guard matcher, a new gate class, or a change to
the promotion contract.
