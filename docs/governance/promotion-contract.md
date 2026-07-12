# The Proportional Promotion Contract — the human↔AI handoff model

**Status:** Canonical model (ratified 2026-06-29). The single source of truth for *how much ceremony a change carries on its way to users.* `DEVELOPMENT-PROCESS.md` §9 (Environments) and §13 (Agent Governance) reference this doc; `CLAUDE.md`'s Definition of Ready/Done point here for the promotion judgment. Design rationale: `docs/architecture/2026-06-29-proportional-promotion-contract-design.md`.

> **What this doc does:** it *documents the model* — the matrix, the change-classes, the deferral ratchet, the GO/NO-GO contract. **What it does not do:** it adds no new enforcement. The `promotion-readiness.sh` classifier (slice 2), the proportional gates (slice 3), and the relaxed agent-commit / delegable-execution rule (slice 4) have all shipped; the existing gates run unchanged and the delegable-execution contract below is now operative. This is the kit becoming self-consistent with its own principles (proportional autonomy, surface-don't-actuate, honest-ceiling, agents-propose-humans-ratify), not new dogma.

---

## The model

**rigor = f(rung × change-class)**, modulated by **{trust, autonomy}**.

The kit already scales rigor by consequence on **one** axis — *who acts* (the L0–L3 autonomy tiers in §13, governed by risk × reversibility × blast radius). The promotion contract adds the second axis the kit already implies but never connected, and proportions the two:

- **Axis A — the rung (how far you're promoting):** Spike → Integration → Release candidate → Staging/UAT → Production. *How close to real users / how big the blast radius.* These are the same promotion tiers as `DEVELOPMENT-PROCESS.md` §9 (Dev/QA/UAT/Prod), named by intent.
- **Axis B — the change-class (what's changing):** **Ordinary** (app code, docs, tests) · **Sensitive** (security boundary, data, money, anything irreversible) · **Control-plane** (the kit's own guardrails, standards, gates, governance marker — the meta-level).
- **Modulator — trust (earned track-record):** the agent's scorecard (`scripts/agent-scorecard.sh` — rework / review-rejection / escalation rates) tunes *where the auto-GO line sits within the Ordinary cells*. It is a **dial, not a third matrix axis** — a 3-D matrix would break the "anyone can walk in" requirement.
- **Modulator — autonomy (composition, new):** autonomy is a **second modulator** alongside trust — it tunes *how much automated scaffolding substitutes for absent human eyes*. Fanning out N agents (human eyes scarce) shifts rigor toward automated scaffolding — mandatory demonstrable increments (`skills/demonstrate`), tighter auto-gates, runaway metering; a small human-proximate build keeps it light. Like trust it is a **dial, not a third axis** — it modulates *composition* (human touchpoint ↔ automated scaffolding), never the matrix cells; a 3-D matrix would break the "anyone can walk in" requirement. *(Honest ceiling: a documented principle informing judgment, not a CI-enforced gate — composition is un-gateable, the same ceiling as trust.)*

**One-sentence mental model:** *How much ceremony? It scales with how far you're promoting and how dangerous the change is — and a trusted agent earns a lighter touch in the safe zone.*

---

## The honest actuation model

The load-bearing correction (owner reframe, 2026-07-07): the bootstrap made the human the mechanical *executor* of agent-prepared work (run `apply.py`, type the merge, push the tag) while the real control — the GO — was incidental. Stated plainly, the model is:

- **The GO is the only validation.** The load-bearing human act at every gate is the *judgment*: review + quick-UAT (`skills/demonstrate`) + flag/risk decisions + "proceed," recorded (`approved-by:`). **The keystroke — who types the merge/tag/deploy — is never a control.**
- **On the GO, the agent executes.** The human *leads* (ratifies); the agent *executes*, bound to the approved SHA, `shipped == approved` verified.
- **A human keystroke is only ever a *kill-switch*, never a validation.** Beyond the GO there are exactly **two** real controls, and neither is a rubber-stamp keystroke:
  1. **A second human's independent GO (SoD)** — a *second judgment*, team-only; solo genuinely can't have it (honest label, never faked). This is the real `builder ≠ ratifier` upgrade.
  2. **A circuit-breaker against a compromised / malfunctioning agent** — a kill-switch, real *only* against that threat, defense-in-depth, off by default (the general kill-switch posture, below).
- **`builder ≠ ratifier` is preserved and is the real SoD** — the agent builds+executes, the human ratifies; the keystroke was never SoD. Best-practice-aligned (approval-gated automation, not "a human must click").

**`lean` is genuinely first-class — the honest baseline**, not enterprise-with-switches-off. In `lean`: small, human-proximate builds, light automated ceremony, the agent actuates on a recorded GO, the kill-switch off. **`enterprise` is the *superset* that *adds* scaffolding** (the kill-switch, heavier records, dual-control where a team exists) — it *strengthens* by adding a human step; `lean` never *removes* an applicable gate. This is descriptive framing only — **no gate reads the mode** (`conformance/mode-enforcement-blind.sh`).

---

## The contract matrix

| Rung | **Ordinary** (code/docs/tests) | **Sensitive** (security/data/money/irreversible) | **Control-plane** (kit's own guardrails) |
|---|---|---|---|
| **Spike** (ephemeral/throwaway) | Agent autonomous (L3); cheap gates advisory; no human gate ← *the relaxation win* | Human-gated (always) | Human-authored (always) |
| **Integration** (PR + ephemeral preview) | Automated gates (lint/type/test/secret-scan) required; agent self-review; GO lightweight/delegable (auto when trust is healthy) | High-risk review lane; human GO | AMBER apply + control-plane-ratification |
| **Release candidate** (merged, Definition-of-Deployable) | The meaningful go/no-go — human renders explicit GO against a promotion-readiness surfacing; builder≠reviewer; DoD + acceptance-criteria checked | full dual review + human GO | human ratify + meta-control |
| **Staging/UAT** | smoke + acceptance sign-off | + threat/privacy re-check | N/A |
| **Production** (canary/blue-green) | human-commanded; progressive rollout; rollback ready | human-commanded; irreversible-gated | N/A |

The cells are the kit's *existing* pieces connected: the autonomy tiers (§13) fill the "agent autonomous" cells, the environment promotion (§9) is the rungs, the review-lane Default/High-risk is Ordinary/Sensitive, the control-plane guard + AMBER + M2-S5 is the right column, and the human GO at Release-candidate/Production is the go/no-go. **"N/A" = not applicable** — the control-plane is a governance artifact whose lifecycle is author→ratify→merge; it does not deploy to runtime rungs — **not** "not available."

---

## Change-class definitions + fail-safe derivation

- **Control-plane** — *path-derived* (the guard's `is_control_plane_path` already detects it): the guard, CI, `conformance/`, governing docs, agent/skill defs, the governance marker, release/escalation scripts.
- **Sensitive** — path-heuristic (`auth/`, `payments/`, `migrations/`, secret/key handling) **+** declared **+** reviewer-confirmable. The Definition-of-Ready conditional flags (threat-model/privacy, eval, compliance) ride here as sub-flags.
- **Ordinary** — everything else (the default for the relaxed path).
- **Fail-safe:** when classification is uncertain, **default to the higher class.** Classification is **derived, not self-asserted** wherever possible, and **verified at the promotion gate** — a change cannot relax itself by mislabeling. (The classifier gets the non-vacuity treatment in slice 2: a load-bearing test that a mislabeled Sensitive change is caught at promotion.)

---

## The promotion contract — mechanics

1. **Within a rung:** the agent moves freely at the rung's autonomy tier — commit, iterate, build, no per-action gate. For Ordinary work this is most of development time.
2. **Relaxation = deferral, not a waiver.** A change that skipped ceremony at Spike carries **no relaxation upward.** The instant it is *promoted* toward a consequential rung, the **destination rung's gates fire — on the whole accumulated change**, not the delta. You don't pay the tax while it's a throwaway; you pay it in full the moment it heads toward users. **Rigor ratchets at every promotion** — that is how nothing harmful rides upward.
3. **Promotion-readiness surfacing:** at each promotion the agent produces a structured surfacing — *what changed, change-class, blast radius, what's proven vs. attested, DoD + acceptance-criteria status (tracker-sourced), what could regress.* It re-classifies and re-checks against the destination bar — a re-evaluation, not a rubber stamp.
4. **GO/NO-GO judgment, not a keystroke:** the human renders an explicit GO whose *depth* equals the cell's rigor (lightweight/auto for Ordinary-low; a real recorded judgment for Sensitive / Control-plane / Release-candidate / Production). **Execution after GO is delegable** to either party — the agent may merge/tag/apply *after* the human's GO. The keystroke stops being the (false) control; the **judgment is the control.**

   **Never-weaken invariant:** a GO is never reached by weakening security, architecture, or governance. If the bar can't be met the change does not promote — you do not lower the bar to manufacture a green.
5. **DoD + acceptance criteria are the *content* of the Release-candidate go/no-go** (frame vs. content): the RC promotion-readiness pulls the story's acceptance criteria (from the tracker — Jira / ADO / `BACKLOG.md`) and the kit's Definition of Done, and cross-checks "did it meet the criteria," not merely "does it not break."

---

## What stays human-governed (unchanged)

The **Control-plane column stays human-ratified at every applicable rung.** The meta-level — the kit changing its own guardrails / standards / gates / governance marker — must not be agent-self-governable (fox/henhouse). This redesign does **not** relax it; it relaxes the *Ordinary* class where the ceremony is currently miscalibrated. This invariant is locked by `conformance/promotion-contract-documented.sh` (the Control-plane column of this matrix can never document an "agent autonomous" disposition).

## Delegable execution — who may run the keystroke (operative)

Execution of a promotion's keystrokes (merge, tag, release) is **delegable after an explicit recorded human GO** — the judgment is the control, not the keystroke. What is delegable depends on the change-class:

- **Tier 1 — always (build phase, within a rung):** the agent reads/drafts, writes code + tests on a feature branch, `git commit`s (reversible), pushes feature branches, opens PRs, authors the AMBER `apply.py`. No per-action gate.
- **Tier 2 — delegable only after a recorded GO (Ordinary/Sensitive):** the agent may execute a normal, branch-protection-permitted merge of an Ordinary/Sensitive PR and run the tag/release step for an Ordinary release. Never before the GO; **never unilateral at a promotion.**
- **Tier 3 — the GO/NO-GO judgment itself is human-rendered, never delegable at any rung.** **Control-plane GO stays human at every rung**; the **actuation** (merge/tag/apply) is delegable to the agent **only** on a SHA-bound, per-merge recorded GO — explicit + recorded + per-merge + **non-blanket** + **SHA-bound**, verifying post-actuation that the shipped SHA == the approved SHA (record format + verification = S2). As of **S6 this actuation is *wired*** — `scripts/promotion-verify.sh actuate` (the operative mechanism, in the honest-ceiling note below), not just a documented permission. Autonomous / inferred / auto-merge / blanket control-plane actuation stays banned. The `gh pr merge --admin` branch-protection bypass remains a human act (server-side, outside the guard — the honesty boundary, un-guardable). The **catastrophic non-promotion set** — push-to-main / force-push (guard-blocked); deploy-to-prod / delete-data / rotate-secrets / incur-spend — is denied **regardless of any approval** (approval authorizes *promotion*, never destruction).

The decisive line is `is_control_plane_path` (change-class), not the keystroke: because the kit's own surface *is* the control-plane, the kit's own work carries the **Tier-3 control-plane rule** above — the **GO stays the maintainer's** (never delegable), while the **actuation** is delegable only on that SHA-bound, per-merge recorded GO.

**The corrected division (who actuates — the load-bearing correction).** On the recorded **GO**, the **agent** actuates all mechanical steps — run `apply.py`, `git add`/commit, push, open the PR, tag, `scripts/promotion-verify.sh record` + push the notes + `check`. The **human** does the **GO** (review + `skills/demonstrate` + risk-acceptance + "proceed") and — **solo, control-plane only** — the single `gh pr merge --admin` (the kill-switch + SoD-substitute, because solo cannot satisfy branch protection; the guard denies `--admin` to the agent). **Ordinary / team work: the agent merges too, so the human does zero mechanical keystrokes — only the GO.** This is not a relaxation: the guard still blocks the agent's Write/Edit to control-plane paths **and** the `--admin` bypass, the agent never actuates **without** a recorded GO, and `builder ≠ ratifier` — the GO stays the human's. Solo, the human's *only* control-plane keystroke is `--admin`; every other mechanical step is the agent's.

On a recorded GO the agent actuates the mechanical steps (apply, commit, push, tag, record, check); the human's only control-plane keystroke, solo, is the `--admin` merge.

**The mechanism (S6 — operative).** The `actuate` protocol is now **wired**: `scripts/promotion-verify.sh actuate --ref <pr|tag> --approved-sha <sha>` performs the delegated control-plane actuation on a recorded GO. It **fails closed** unless *all three* hold, then runs a *normal, non-`--admin`* merge and re-verifies `shipped == approved`:

1. a GO note binds **exactly** `<sha>` under `refs/notes/promotions`;
2. the derived `approved-by:` label is **`[authenticated: <forge>-review]`** (read from that line's trailing label only — never a body scan, per the S5a decoy lesson);
3. the **approver identity ≠ the commit author** (`builder ≠ ratifier`, real teeth — self-approval, even authenticated, is not SoD).

**The assurance bar (ratified):** `[self-asserted]` / `[committer]` / `[signed: gpg]`-alone **all fail** the control-plane bar — commit signing proves *who wrote* the commit, not that a *distinct* party reviewed and approved it.

**The kill-switch holds — the honest mechanism (no mode read).** The solo hold is **server-side**, not the local label check: a *normal* `gh pr merge` is rejected without a real forge review (branch protection), and `gh pr merge --admin` — the only server-side bypass — is **human-only**. *That* is what keeps `--admin` the human's one act (the honest solo kill-switch). The wired `actuate` gate's authenticated-label bar is **defense-in-depth + an audit discipline over a self-authorable git note** — NOT the primary solo control: until the forge-review derivation seam (`docs/adoption/vc-hosts.md`) is wired, the `[authenticated: <forge>-review]` label is self-authorable (a raw `git notes add` is outside the guard), so solo, `derive_assurance` can only *honestly* emit `[self-asserted]`/`[committer]` — the label bar records and audits, it does not by itself authenticate. A **team's** authenticated second-reviewer GO both satisfies branch protection *and* meets the label bar → the agent does a **normal** (non-`--admin`) merge, keystroke genuinely retired. The guard **never reads `lean`/`enterprise`** — mode-blindness is by construction (`conformance/mode-enforcement-blind.sh` preserved); the *solo hold itself* is the server-side branch-protection + human-`--admin` control, not the local label read.

**Honest ceilings (S6):** the gate is **fixture-proven now, solo** (`conformance/promotion-actuate-wired.sh` — one liveness anchor + nine fail-closed negatives). The live `gh pr merge` (a swappable `--merge-cmd`), the forge-review → `[authenticated: <forge>-review]` derivation (`docs/adoption/vc-hosts.md`), and the team merge credential are documented **seams** — no solo consumer, wired when a team is provisioned. The server-side `--admin` bypass stays **un-guardable** (`docs/operations/runtime-guards.md` honesty boundary — the guard's `--admin` deny is a *speed-bump*; the real boundary is never issuing the agent an admin credential). Live enforcement also remains the guard (push-to-main / force-push) + the `agent-boundary` CI gate (control-plane ratification at merge).


### Approve→execute→log — the actuation protocol (non-control-plane; operative)

For **non-control-plane** promotions the agent may actuate the merge/tag **after an explicit, recorded, per-gate human GO** — the protocol validated in the Relay dogfood (KW1 · D2). The mechanism (`scripts/promotion-verify.sh` binding GO records as git notes under `refs/notes/promotions`, locked by `conformance/promotion-verify-wired.sh`) makes the already-shipped delegable-execution permission (v3.83.0) **auditable and safe**:

1. **Approve** — the agent **provides the means** to review + verify (the PR, diff, checks, the running increment via `skills/demonstrate`) and **waits**. The human renders the GO/NO-GO and gives an **explicit approval token** — per-gate, recorded, and **never inferred** from conversational phrasing ("let's do the merge" is *not* a token).
2. **Execute** — only on that recorded GO does the agent run the merge/tag keystroke.
3. **Log** — the agent records the approval with `scripts/promotion-verify.sh record`: it binds a structured GO record to the approved commit as a **git note** under `refs/notes/promotions` (`approved-sha` · `approved-by` · `gate`/`rung`/`change-class` · `scope` · `approval-token` · `basis`), and posts the record ref on the PR for at-a-glance visibility. The record is **tree-invariant** — bound *outside* the tree it approves, so it can never perturb it (closes S4-finding #1: an in-tree log append perturbed the approved tree). The `approved-by` line carries a **derived assurance label** — `[signed: gpg]` (a signed approved-sha) → `[committer]` (the git committer identity) → `[self-asserted]` (a free-typed approver git cannot corroborate) — that never overclaims *how* identity was established; authenticated team approval (`[authenticated: <forge>-review]`) is a forge-adapter **seam** (`docs/adoption/vc-hosts.md`), wired with a team consumer. View the trail with `promotion-verify.sh log` (a projection of the notes); share it with `git push origin refs/notes/promotions`.
4. **Verify** — the agent then runs `scripts/promotion-verify.sh check` to assert **`shipped == approved`** (the merged trunk / the tag carries the approved SHA — and the tag's `VERSION` matches the approved one), **at merge AND at tag**. A mismatch is an incident, not a warning — it hard-fails (`SHIPPED != APPROVED`).

This is **uniform delegation riding the existing rung×change-class gating** — no new axis. It changes behavior only where a human GO is already mandated: it removes the *keystroke* there while keeping the *GO*. **Blast radius scales the verification, not the permission** — `shipped == approved` is uniform but most load-bearing at RC/Production, trivial at Spike.

**`builder ≠ ratifier`** — a **first-class invariant, peer to `builder ≠ reviewer`** (a.k.a. `builder ≠ promoter`): the agent may prepare, execute, and record a promotion; it must **never ratify** it.

**Control-plane actuation stays human — a kill-switch + a temporary bootstrap, *not* "human control"** (honest relabel, S4/KW20). This `approve→execute→log` protocol wires **non-control-plane** promotions only; control-plane actuation follows the Tier-3 rule above (the GO stays the maintainer's; actuation is delegable only on a SHA-bound, per-merge recorded GO). The reason the human still types the control-plane keystroke **solo** is **not** that the keystroke is a governance control — it never was. It is that (a) solo, **no authenticated second-reviewer GO can exist**, so a *normal* agent merge is rejected server-side (branch protection) and `--admin` — the sole bypass — is human-only, leaving `--admin` the human's only route; and (b) the solo **kill-switch** (the only defense-in-depth a solo maintainer has) *is* that server-side control. **S6 grants the capability** — the agent-actuation path for the control-plane is now wired, on top of the **S5** recovery net (the honest thing that makes delegated actuation safe is *recovery*: see, stop, undo, not a keystroke); a **team's** authenticated second GO meets the bar and the agent actuates a *normal* merge. The wired `actuate` path's label bar is defense-in-depth + audit over a self-authorable note (a raw `git notes add` is outside the guard) — it does **not** by itself make the bar "unmeetable solo"; the honest reason `--admin` stays human solo is the **server-side** branch-protection + human-`--admin` control. Solo, the Tier-3 rule and "the control-plane GO stays the maintainer's" remain TRUE — because no authenticated second judgment exists, not because a local check fabricates one.

**Recovery — the S5b net (drilled).** Control-plane recovery reuses this contract's own `check`: `git revert <bad control-plane merge>` restores the prior tree, and `scripts/promotion-verify.sh check --ref HEAD --approved-sha <last-good>` proves *reverted == last-good* by the **same tree-equality** that proves *shipped == approved* — no new revert command. This restoration is drilled + CI-gated by `conformance/control-plane-revert-drill.sh` (a *non-restoring* revert FAILs, the load-bearing negative), and assembled into the agent break-glass procedure (halt → revert → rotate → postmortem) in [`docs/operations/break-glass.md`](../operations/break-glass.md). S5b builds the *undo* — the S6 precondition; S6 is the deliberate capability grant on top of it.

### The general kill-switch posture

The "deploy-failsafe dial" and the solo "human merges the control-plane" are **the same object** wearing two labels: a **configurable human circuit-breaker at a high-assurance actuation point**, calibrated to *blast-radius × threat-model*. S4 unifies them into one honest posture:

- **What it is:** a human keystroke retained at an actuation point *purely* as a **kill-switch, not a validation** — the GO is the validation; this is a circuit-breaker against a compromised / malfunctioning agent. It is a **posture, not a gate** — a gate would read the mode.
- **Default posture:** *on* where blast-radius is highest **and** there is no other defense-in-depth (solo control-plane; production deploy); *off* where the agent + gates + `shipped == approved` are trusted (the `lean` / non-control-plane default — the agent actuates on the recorded GO).
- **`lean` vs `enterprise`:** `lean` = the agent actuates on the recorded GO, kill-switch off. `enterprise` = *adds* the kill-switch (and, where a team exists, the real SoD second-GO). Enterprise **strengthens** (adds a human step); `lean` never *removes* an applicable gate.
- **Posture, not gate — preserves `mode-enforcement-blind`:** no enforcement-surface script reads the mode to decide the kill-switch. It is a documented, human-configured operational posture (see `docs/operations/progressive-delivery.md`).
- **Honest ceiling / defer-build-ahead:** the control-plane actuation is now **wired (S6, on the S5 recovery net)** — ending that bootstrap; the *prod-deploy* failsafe posture remains a documented posture with no live consumer yet, riding **KW23**. S4 defined the posture honestly; S6 built the control-plane half.

**Honest ceiling:** `shipped == approved` is the **gateable** guarantee — the record's existence, its SHA-binding, and the post-actuation content match are CI-checkable (the half that would have hard-failed the tag-on-wrong-commit / content-not-committed slips). The match is by **tree equality** (`git rev-parse <ref>^{tree}` == `<approved-sha>^{tree}`) — exact content equality, which neither false-fails a squash merge nor false-passes a revert or extra content. `never-infer` is **FLOOR discipline** — that the agent *waited* and refused to infer approval is not runtime-gateable; the record's existence + SHA-binding is checkable, the *judgment not to infer* is discipline. Do not read a green check as proof of never-infer. **The record itself — a git note bound to the approved commit under `refs/notes/promotions` — is a self-authorable *advisory* trail: it *binds* (tree-invariantly, so it can never false-fail `check`) but does NOT *authenticate*. A git note is a mutable ref: it defends against an honest-but-buggy agent's slips and provides audit evidence, but it is NOT tamper-evident against a compromised/malicious actor (that threat is the S4 deploy-failsafe circuit-breaker's job, not this record). The `approved-by` assurance label (`[signed: gpg]` → `[committer]` → `[self-asserted]`) states HOW identity was established and never overclaims. Re-recording a GO on the *same* approved-sha **supersedes** the prior note (`git notes add -f`) — prior gate history is not retained in the trail; view the current recorded state with `promotion-verify.sh log`. The authoritative assurance is the trailing derived label on the `approved-by:` line (derived, honest) — consumers must read *that* line's label, not substring-scan the whole note body, because a `--token`/`--basis`/`--scope` value may legitimately contain bracket text (e.g. `approval-token: "GO [per PR #257]"`).** Documented-coherently by `conformance/promotion-contract-documented.sh`; the integrity check is non-vacuously locked by `conformance/promotion-verify-wired.sh`.

---

## Solo vs. team — same model, honest label

The model is **team-ready by construction.** Solo, the human holds all ratifier roles; with a team, the existing ratification-RBAC roles distribute and `control-plane-ratification` becomes a *real* second-reviewer gate. The gate emits a **truthful state label** rather than a lying binary:

- **`RATIFIED-BY-SECOND-REVIEWER`** — team; separation-of-duties genuinely satisfied.
- **`SOLO-ADMIN-OVERRIDE-LOGGED`** — solo; SoD satisfied by the *compensating control* (the immutable admin-merge audit trail). Honestly weaker, and the label says so.

It never claims a protection that wasn't exercised. Solo SoD genuinely cannot be satisfied (the forge forbids self-approval); the model **names** that, it doesn't fake it. (Emitting this label is slice 3; changing the solo behavior is out of scope — the team experiment comes later.)

---

## Honest ceilings (what this does NOT claim)

1. **Judgment quality is un-gateable.** We can *inform* it (the surfacing), *record* it (an auditable GO), and *measure its outcomes* (the scorecard — rework / escape / incident rates feeding the loop). We cannot CI-prove a GO was a *good* judgment. (Same ceiling as the `operating` skill.)
2. **The classifier is fail-safe, not omniscient.** Safe-default + path-derivation + promotion-gate verification — not perfect detection.
3. **Solo SoD cannot be truly satisfied** — named via the state label, not faked green.

---

## Build status — an epic of ~4 governed slices

| Slice | Scope | Status |
|---|---|---|
| **1. Model + standards (keystone)** | This doc + §9/§13 + DoR/DoD references + the coherence lock. | **this slice** |
| **2. Change-class derivation + promotion-readiness surfacing** | `promotion-readiness.sh` classifies (reusing `is_control_plane_path`) + emits the surfacing; load-bearing fail-safe-classifier negative. | **v3.81.0** |
| **3. Proportional gates** | Gate/keystroke requirements conditional on (class × rung); `control-plane-ratification` emits the team/solo state label. | **v3.82.0** |
| **4. Relax agent-commit + delegable execution** | "Free within rung after explicit GO; execution delegable post-GO; never unilateral at a promotion." | **v3.83.0** |

Slice 1 is the spec everything else implements; all four slices have now shipped (the delegable-execution contract above is the last), each sequenced deliberately with appetite decided after the prior one.
