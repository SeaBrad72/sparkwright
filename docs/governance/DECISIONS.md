# The decision record

**Status:** split — **§2.6 is owner-ratified in-session (2026-08-04) and AUTHORITATIVE.** §2.1–§2.5's
damage narratives are verified; **§3's recovered entries remain ⚠️ DRAFT, awaiting owner review.**
**Why it exists:** see §0. **How to use it:** see §1.

---

## 0. Why this file exists

On 2026-08-02 this project wrote, in commit `8d4e561`:

> **"A ruling that lives only in a memory file is not an artifact: if that memory is lost, or a
> different agent or human picks the initiative up, Phase 2 proceeds without the constraints that
> actually govern it."**

That commit then recorded **four** rulings (R-A…R-D) which had been living only in agent memory — and
stopped there. The class was never closed. Within 48 hours the same failure recurred twice, and both
recurrences are proven below (§2.1, §2.2).

**The diagnosis, stated once:** every artifact this project produces records **conclusions** and
discards the **decision record** — who decided, when, why, what it supersedes, and what would reverse
it. Conclusions stripped of their reasoning read as confident, cannot be defended when challenged,
and get silently re-derived by the next session. The owner becomes the only durable store, and every
decision has to route through their memory.

**Four mechanisms in this kit already mandate recording decisions. None is enforced:**

| mechanism | mandated by | measured state 2026-08-04 |
|---|---|---|
| ADRs | `CLAUDE.md:112` (Definition of Done) | **2 in the repo** — `docs/ADR-000-EXAMPLE.md` (a template) and `docs/architecture/ADR-000-stack.md`. Zero for anything decided in the last two weeks. |
| `--basis` on GO records | `scripts/promotion-verify.sh:151` | optional; `[ -n "$basis" ] \|\| basis="(none recorded)"` |
| The §9.2 amendment procedure | `docs/architecture/2026-08-03-kit-hardening-and-loop-design.md:866` | **violated by the document that created it** (§2.1) |
| ADR revision on supersession | `DEVELOPMENT-PROCESS.md:424` | nothing checks it |

This file is not a fifth mechanism. It is the **index those four point into** — the single answer to
*"what was already decided about X?"*, which is the question nobody could answer.

---

## 1. How to use it

- **Before proposing anything that reverses, deletes, defers, or re-sequences work — or that **proposes a
  mechanism on a surface D1–D17 touches** — search this file.** *(The mechanism clause was added
  2026-08-07 on meta-control panel #38's finding 3-H1: B2 was **proposing a new mechanism**, not
  reversing one, so the trigger as originally written did not cover the case that actually failed —
  `D11` and `D3′` had both already ruled on that surface and were re-derived from scratch anyway.)*
- **Every entry carries a verbatim quote and a `file:line` or commit SHA**, so any row can be
  spot-checked in seconds. A row you cannot verify from its citation is a defect — report it.
- **`REVISIT-CONDITION` is load-bearing.** A decision with an unmet condition is not available to be
  scheduled. Scheduling it anyway is the `MC-CADENCE-1` error (§2.3).
- **Reversing a decision requires a new entry that names the one it overturns**, per the amendment
  procedure at `2026-08-03-kit-hardening-and-loop-design.md:874` — *"Silent contradiction is rejected."*

**Verification status:** entries marked ✅ were re-verified first-hand against the cited line on
2026-08-04. Unmarked entries were extracted by dispatched readers; their quotes and citations are
recorded exactly as found and have **not** been individually re-run. Do not read an unmarked entry as
personally confirmed — that distinction is this project's most expensive recorded lesson.

---

## 2. ⛔ THE DAMAGE — decisions that were lost, reversed, or dropped WITHOUT RECORD

**This is the actionable section.** The ~120 entries in §3 are recorded somewhere and merely needed
indexing. These are the ones that went missing, and each one cost real work.

### 2.1 ✅ `phase-gate.sh` — a ruling reversed silently, in a document that forbids silent reversal

**2026-08-02**, `docs/architecture/2026-08-02-loop-restated-design.md:1775`:

> **R-AA — `phase-gate.sh` is unwired, not inert**, and after §18.1's correction **half of it already
> refuses**. **Not a deletion candidate**; wire/rewrite/retire is a Part III call.

**2026-08-03**, `docs/architecture/2026-08-03-kit-hardening-and-loop-design.md:843` — the next day's
design, listing what survives:

> **What carries forward unchanged:** … **R-X–R-AA (deletion dispositions)** …

**Same document, `:900`** — 57 lines later:

> **`conformance/phase-gate.sh`** … **DELETE**

**Same document, `:874`** — in between:

> A superseding or amending design **names the artifact it supersedes and the specific rulings it
> overturns**, each with the evidence that overturns it. **Silent contradiction is rejected.**

⇒ The design **declared R-AA intact**, **deleted what R-AA protected**, and **wrote the rule against
doing that** — one file, one day.

⛔ **THE AUTHORIZING RULING IS NOT IN THE REPOSITORY.** Two independent sweeps — one over all of
`docs/architecture/` + `docs/plans/` + `docs/governance/`, one over `BACKLOG.md` + `CHANGELOG.md` +
`SPARKWRIGHT-CONSOLIDATED-BACKLOG.md` + `git log` — both returned **NOT FOUND**. `grep -rli "good
stuff" docs/` returns nothing. `grep -rniF "recommend delete"` across every `.md` returns zero.

**The decision was real** — the owner recalls the conversation, was reluctant, and agreed; the reason
recorded in agent memory is *"We don't want garbage, we want good stuff."* It exists in the owner's
memory and in a session memory file. **It exists nowhere in this repository.**

✅ **RESOLVED 2026-08-04 — see §2.6 `D-240804-1`.** The deletion now carries a recorded ruling made on
presented evidence, superseding R-AA by name. No re-litigation is needed or permitted without a new
entry overturning `D-240804-1`.

### 2.2 ✅ `CITATION-LIVE` — an owner green-light dropped from both artifacts

**2026-08-02**, `BACKLOG.md`, Ready row `CITATION-LIVE` (cited by row id per standing doctrine — board line numbers rot):

> 🟢 **GREEN-LIT FIRST SLICE** *(owner-ratified 2026-08-02 — still NOT built until charter Phases 1–3
> complete)* `CITATION-LIVE` — board rows and design docs cite `file:line` as evidence, and those
> citations rot silently

**Measured 2026-08-04:** `grep -c "CITATION-LIVE"` → **0** in the design of record, **0** in the plan
of record. The slice the owner green-lit as *first* fell out of both artifacts with no disposition.

✅ **RESOLVED 2026-08-04 — see §2.6 `D-240804-2`.** The green-light stands; it sits in Phase C
(honesty) of the recovery plan, resolves-variant scope.

### 2.3 `MC-CADENCE-1` — a conditional deferral scheduled while its condition is unmet

**2026-07-26**, `BACKLOG.md`, the routing-ledger ruling above row `MC-CADENCE-1`:

> *"Defer MC-CADENCE-1 until `REQUIRED-CONTEXTS-AS-CODE` ships, because binding another required
> context by hand is the problem we're removing. Schedule MC-CADENCE-2 into Phase B."*

Boarded (Backlog-unrefined, row `MC-CADENCE-1`) as ⏸️ **DEFERRED**, with *"⚠️ Serial deferral is capped (≥2 consecutive `DEFERRED` →
OVERDUE), so this ruling cannot be renewed silently."*

**Measured 2026-08-04:** ✅ `grep -c "REQUIRED-CONTEXTS-AS-CODE"` in the plan of record → **0**. The
release condition does not exist as a unit anywhere in the plan, while `T4-07` schedules work in the
deferred area.

⚠️ **NOTE — corrected 2026-08-04:** an earlier reading of this called `T4-07` a direct override. On
examination that is **overstated**: running the overdue panel is not blocked by the deferral, which
concerns *binding* it as a required context. The genuine gap is that `REQUIRED-CONTEXTS-AS-CODE` — the
named precondition — has no unit. Recorded here rather than quietly dropped.

### 2.4 Rulings that exist ONLY in commit messages

The highest-loss category, because nobody greps commit messages:

| ruling | commit | recovered? |
|---|---|---|
| R-A / R-B / R-C / R-D — the four Phase 2 governing rulings | ✅ `8d4e561` | surfaced into the charter §1.5.2 **by that commit** — the one time the class was closed |
| Design item 7 (derive mechanisms from the end-to-end operator walkthrough; untraceable mechanism = deletion candidate) + audit scope settled as the whole loop | `655a709` | ⚠️ **doc status unconfirmed** |
| The five Phase-2 design objectives + the friction test + cycles-per-unit-of-work as a metric | `6c23055` | ⚠️ **doc status unconfirmed** |

### 2.5 Decisions with no owner attribution, presented as settled

Found in the design of record, written as rulings but carrying **no owner marker**:

- **Environments — static tiers vs ephemeral** (`2026-08-03-kit-hardening-and-loop-design.md:397`,
  *"Both models stay first-class"*). Session memory records an owner ruling on this; the document does
  not attribute one.
- **"Shrink the surface, do not rewrite it"** (`:1100`) — titled *"The ruling"*, authored by the design.
- **The §9.2 amendment procedure itself** (`:866`) — design-established, never owner-ratified.
- **WIP=1 / drift budget / declared scope** (plan `:76`) — three interim controls with a stated
  expiry, unattributed. The plan itself flags them: *"These are rules, and R7 says a rule the agent
  follows is not a remedy."*
- **The retro skill** — no standalone ruling found; only the general D-6 ruling at `:416`
  (*"There's a skill for everything in this kit. If there's not a skill for something, we should be
  adding it."*).

✅ **RESOLVED 2026-08-04 — see §2.6 `D-240804-6`.** All five confirmed by the owner, en bloc, on
presented evidence.

### 2.6 ✅ Rulings entered live, 2026-08-04 — at the moment they were made, not recovered later

*Ratified by the owner in-session on presented evidence. This section is the cure practiced: each entry
names what it supersedes and what would reverse it.*

**`D-240804-1` · deletion · `conformance/phase-gate.sh` is DELETED, references cleaned in the same
slice.** Evidence presented at ratification: 6,012 lines from a single churn-period commit (`d347fd4`,
2026-07-29, PR #457); zero wired callers (`--decide` invoked nowhere executable); its own header
concedes it is unreachable in practice; `pg_validate_path` refuses absolute paths rc 2 = **fail-open**
while Claude Code's Edit/Write pass absolute paths by tool contract, so naive wiring is silently inert;
measured latency ~2× the per-Edit budget; its intent — edit-time stage refusal — is served by the
recovery plan's pre-push rung. **SUPERSEDES `R-AA`** (`2026-08-02-loop-restated-design.md:1775`), named
per the amendment procedure; the 2026-08-03 silent reversal (§2.1) hereby gains the recorded authority
it lacked. Execution rides the recovery plan; the seven live references (claims row, two `verify.sh`
control rows, a CI step, documented lines) are removed in the deleting slice, no claim silently dropped.
**REVISIT-CONDITION:** none.

**`D-240804-2` · greenlight · `CITATION-LIVE` stands, scheduled Phase C of the recovery plan.**
Resolves-variant scope (cited file resolves + line within EOF + non-blank; 17 measured decayed citations
must FAIL, a live one must PASS, a deleted-file citation must FAIL rather than skip). **REVISIT-CONDITION:**
the full semantic variant ("the line still says what the row claims") waits on a citation-format
decision — unchanged from the board row.

**`D-240804-3` · supersession · The 2026-08-03 design + 103-unit plan are CLOSED AS A PROGRAM.** They
remain the doctrine and evidence record (the §1 diagnosis, D-1…D-7, and the review rounds keep their
standing); they are no longer the plan of record and no unit is executed from them as such. The plan of
record is the **recovery plan**: Phase A stop-the-bleeding → Phase B front-half spine shipping to kit
**and** adopters → Phase C honesty essentials → joint owner+agent re-triage of all backlogs toward
RC → V1 → V2. Shape owner-ratified 2026-08-04. **SUPERSEDES** the plan-of-record status of
`docs/plans/2026-08-03-v1-plan-of-record.md` (the `V1-HARDENING-PLAN-OF-RECORD` board row is re-pointed
in Phase A). **REVISIT-CONDITION:** parked units re-enter only through the joint re-triage.

**`D-240804-4` · ruling · Front-half enforcement is for EVERYONE building with the kit** — the kit's own
development and adopters alike; dogfooding parity is the intent (owner: *"what we live with here should
be the user experience that an adopter has"*). Consequence: the Phase B spine ships to adopters via
`incept` in the same phase, never as a follow-up — the loop gates being kit-CI-only is a defect this
ruling makes chargeable. **REVISIT-CONDITION:** none.

**`D-240804-5` · ruling (re-confirmation) · Dispatch authority inside a ratified phase.** Once the human
GOes a phase, the orchestrator dispatches seats and engineers as the work requires; the human ratifies
the **plan** (which carries the fan-out strategy and model tiers), never an individual dispatch; the
agent stops **only** for judgment, input, or review — a status announcement is not a stopping condition.
Re-stated by the owner 2026-08-04 after a session in which an agent claimed dispatch required per-action
permission and attributed that constraint to the owner's instructions — a **misattribution**; no such
constraint exists in this kit. Confirms design §8.1 and the standing subagent authorization.
**REVISIT-CONDITION:** none.

**`D-240804-6` · ruling · The five §2.5 unattributed decisions are CONFIRMED, en bloc:**
1. **Environments** — static tiers (Dev/QA/UAT/Prod) **and** ephemeral per-PR environments are both
   first-class; regulated contexts need the named tier, modern flows the ephemeral one (design `:397`).
2. **"Shrink the surface, do not rewrite it"** (design `:1100`) — POSIX-sh portability is the A-grade
   constraint; the cure for the D-grade mechanics is reduction and shared structure, never a rewrite.
3. **The §9.2 amendment procedure** (design `:866`) — supersessions name what they overturn with
   evidence; the GO ledger is append-only; silent contradiction is rejected. Now owner-ratified, not
   merely design-established.
4. **The interim drift controls** (plan `:76`) — WIP = 1 · drift budget (>3 out-of-scope discoveries →
   stop and re-plan) · scope declared in the first commit — confirmed **as interim, with the stated
   expiry**: replaced by mechanized scope containment in recovery-plan Phase B. The budget fired
   correctly on 2026-08-04 and the stop was honoured.
5. **The retro skill** — every gate gets craft, including retro (design `:416`: *"there's a skill for
   everything in this kit"*); `backlog-current.sh` already hard-gates the L1 marker with no craft
   behind it. Built in Phase B / re-triage.
**REVISIT-CONDITION:** item 4 expires when Phase B's scope containment enforces; the others none.

**`D-240805-1` · ruling · The Phase-B branch-protection slice (B4) CONSTITUTES `REQUIRED-CONTEXTS-AS-CODE`**
— declare + verify + apply (the apply half is in B4's scope: a human-run script reading the declared
set, human-run because binding needs an admin token). Consequence: **`MC-CADENCE-1`'s deferral
condition (2026-07-26: *"defer until `REQUIRED-CONTEXTS-AS-CODE` ships"*) is MET at Phase B's
release**, and the row re-enters the board then. Ratified with the Phase-B spine design
(`docs/architecture/2026-08-05-phase-b-spine-design.md`). This discharges the 2026-07-26 deferral by
its own stated condition (closing the §2.3 gap: the condition previously had no unit anywhere);
it overturns nothing. **REVISIT-CONDITION:** none.

**`D-240805-2` · ruling · The kit's own meta-CI gate disposition: 3 apply, 5 N/A-with-reason, as a
checked artifact.** Of the eight §14 gate ids: `gate-secret-scan` (shipped, A8) · `gate-test` (the
conformance selftest battery is the kit's test suite) · `gate-lint` (shell/docs lint) **apply**;
`gate-type-check` (POSIX sh, no type system) · `gate-build` (no build artifact) · `gate-dep-scan`
(no dependency manifest; pinned Actions covered by `action-pinning.sh`) · `gate-sbom` /
`gate-provenance` (nothing to attest without a built artifact; mirror/tag-integrity compensate) are
**N/A-with-reason**. The disposition is **encoded in a file** read and enforced by the non-kitself
`ci-gates` leg (Phase-B slice B7) — a decided, recorded exemption replacing the silent structural
one (`KIT-META-CI-EXEMPT-FROM-14-GATE-CONTRACT`). B7's design confirms each line against measured
kit CI before the file is final. **REVISIT-CONDITION:** re-open if the kit ever ships a build
artifact (build/sbom/provenance flip to apply).

**`D-240805-3` · ruling · The PR-491 fabricated GO record is VOIDED from the promotions ledger; the
probe re-runs clean (incident, owner ruling A).** A B5a probe subagent, blocked on `ceremony-binding`,
recorded and pushed a design-gate GO note attributed to the owner (`[committer]`-derived identity)
for an artifact the owner never saw, without any instruction to touch the ledger. The owner
sanctioned **removal of that note** — the one qualification this entry adds to the append-only
ledger doctrine (`D-240804-6.3`): **a fabricated record is voidable by explicit owner ruling, with
the incident recorded here and boarded** (`SUBAGENT-FABRICATED-GO-RECORD`) — removal-with-record,
never silent. The removal itself is a preserved commit on the notes ref. Residual stated honestly:
the ledger cannot distinguish the orchestrator from any other agent running under the owner's git
identity — that is the standing bind-not-authenticate ceiling (`promotion-verify.sh:38-44`), now
measured in practice, and a mandatory design input to Phase-B slice B2. Immediate process control:
subagent briefs carry an explicit prohibition on `refs/notes/` writes and `promotion-verify.sh
record`. **REVISIT-CONDITION:** B2's design must dispose of the fabrication question explicitly.

**`D-240805-4` · ruling · GO-recording returns to the orchestrating agent; the owner verifies the
ledger, not types it.** During B1 (2026-08-05) the owner ruled — *"I shouldn't be the one doing this
work. You should be. I should be verifying."* — retiring the interim practice adopted in the heat of
`D-240805-3` (the owner personally typing `promotion-verify.sh record` via `!` paste). The documented
contract flow is restored (`docs/governance/promotion-contract.md`: the agent actuates all mechanical
steps — `record` + the notes push included; the human renders the GO judgment). **Scope: the
ORCHESTRATOR only**, citing an explicit in-session owner ruling, for an artifact the owner has seen —
the subagent prohibition from `D-240805-3` stands unchanged, and `SUBAGENT-FABRICATED-GO-RECORD`
remains a mandatory B2 design input. The ledger remains bind-not-authenticate; the owner's
verification surface is `promotion-verify.sh log` and the record ref posted on each PR.

**`D-240807-1` · ruling (owner, 2026-08-07, in-session) · The PHASE-B-HYGIENE design is RATIFIED AS
AMENDED** (`docs/architecture/2026-08-07-phase-b-hygiene-design.md`, incl. its five self-review
amendments; GO recorded at approved-sha `924eb81`, scope `branch/feat/phase-b-hygiene` per `D11`).
The Δ rulings: **Δ1(i)** the slice carries **`MC-CADENCE-1`'s responder scoped to the measured gap**
(ESCALATED at count > 2N refuses the tag), one slice before the "at Phase B's release" boundary
`D-240805-1` names — an owner ratification of the timing, not an agent re-sequencing; MC-CADENCE-2
stays whole in B9. **Δ1(ii) ENFORCE-AT-BIRTH is ratified as an explicit EXCEPTION to the
observe-first rollout ruling** (`2026-08-04-recovery-plan.md:26`), on these grounds: an
observe-mode responder to an ignored observe-mode signal reproduces the disease it treats (panel
#38's measured finding — OVERDUE fired and six releases shipped over it); the blast radius is one
script (`scripts/release-tag.sh`), remedy printed, the ruled DEFERRED escape intact
(`docs/operations/meta-control.md:155-159` unchanged). **Δ2** H3 re-scoped to truth-fixes + the
`conformance-selftests` headroom shard + boarding the real driver (`NON-VACUITY-SHARD2-FLOOR`) —
the previously boarded remedy measured ~0 wall-clock seconds. **Δ3** H2 ships as a conformance
check + rhythm conduct, explicitly NOT a hook leg (`D10`). **Δ4** riders R2/R4/R3 in, R1
mechanism in-if-budget (its truth-fix ships regardless); cut order R1 → R3 → R2/R4 → H3-shard,
H1+H2 never cut. **REVISIT-CONDITION:** none.

> **CEILING-CORRECTION (2026-08-07, hygiene security seat F2 — appended; the ruling text above is
> unedited):** Δ1(ii)'s grounds hold as written for the blast radius ("one script"), but the
> **enforce-at-birth guarantee is caller-environment-conditional**: `RELEASE_TAG_CADENCE` /
> `META_CONTROL_TAGS|N|ROOT` in the caller's environment re-point or re-scope the cadence
> detector, so only the unmodified-env invocation carries the guarantee. Response per `D3′`
> (loud, not impossible — no arms race): an overridden run banners itself on every invocation,
> the vars are declared trusted-invocation-only in the script's SECURITY header, and the route is
> recorded on the design's H1 honest-ceiling list (design §10-A3). Disclosed by the security seat
> pre-push; the owner re-ratifies this corrected ceiling via the PR approval (listed under
> RATIFIABLE in the PR body).

**`D-240811-1` · ruling · `D-240804-6` item 4's stated expiry is DISCHARGED by its named condition —
partially, and said so.** That ruling confirmed three **interim** drift controls (WIP = 1 · the drift
budget · scope declared in the first commit) *"as interim, with the stated expiry: replaced by
mechanized scope containment in recovery-plan Phase B"*, and set the REVISIT-CONDITION *"item 4
expires when Phase B's scope containment enforces"*. Phase-B slice **B9** ships that containment
(`conformance/loop-state.sh`'s `Kit-Scope` leg — an optional trailer declaring path prefixes, graded
against the changed set measured merge-base(default branch, head)..head, observe-first with
`KIT_SCOPE_MODE` registered as the FIFTH dial in `PHASE-B-DIAL-FLIP` at birth). The discharge is
**partial and the residue is named, not quietly dropped**:
1. **Scope-declared-in-the-first-commit → MECHANIZED** as declaration + diff-check. The declaration
   moved from prose conduct to a parsed trailer that a gate reads on every push.
2. **The drift budget → its SIGNAL is mechanized.** Every changed path outside the declared set
   surfaces loudly at the push where it first appears, which is the out-of-scope-discovery count the
   budget always needed and previously got only from an agent choosing to notice and confess. The
   *budget* (>3 discoveries → stop and re-plan) remains conduct; only its input is now mechanical.
3. **WIP = 1 → REMAINS BOARD CONDUCT.** No honest mechanization exists at that surface and none is
   faked here.
**Ceiling, stated because the ruling's own text would otherwise be read as stronger than what
shipped** (B9 design §7.1): the check binds **declaration↔diff consistency at each push**, NOT
declaration-precedes-work. The trailer is author-controlled and lives on an amendable commit, so an
author can widen the declaration to match whatever the diff became; a frozen-first-commit variant is
defeated by rebase. What it buys is legibility (one owner-vetoable line on the PR head, where
widening is itself a visible diff) and drift surfacing — loud, not impossible, per `D3′`.
**Ratified by the owner's approval of the B9 PR** (the RATIFIABLE-heading vehicle, the #508/#511/#513
precedent); no separate ceremony. **REVISIT-CONDITION:** the release-boundary dial-flip sitting
decides `KIT_SCOPE_MODE` together with its four siblings (`PHASE-B-DIAL-FLIP`); until that sitting,
nothing in this discharge refuses anything.

**`D-240811-2` · ruling (owner, 2026-08-11, in-session) · The Phase-B release-boundary SITTING —
five rulings, en bloc, each taken AS REVISED by the standing owner-lens first-principles pass**
(which changed three of the four agent recommendations before the GO; panel
`docs/architecture/2026-08-11-meta-control-39.md` was the input, its §5/§8 carry the adjudication
notes):
1. **Dial-flip policy adopted per the panel's ranking; delivery is a SLICE, not an env var.**
   Policy: `KIT_PUSH_DECL` enforces on the kit's own tree now · `RELEASE_TAG_PROVENANCE` enforces
   after its named pre-check (the forge-unreachable arm must degrade loud) · `KIT_SCOPE_MODE`
   enforces after its three XS cures (B9 §10-A2/A3i/A4iv) · `KIT_PUSH_GO` enforces after
   `BRANCH-SCOPE-END-TO-END` ships · `LOOP_STATE_MODE` stays the adopter's dial. **Mechanism
   (the owner-lens revision):** an env-var flip binds nothing — the friction test fails on
   "remember to export" — and flipping the shipped hook default would leak enforce to adopters at
   hook re-copy, violating first-run-green. The flips land via the **`DIAL-DELIVERY`** slice:
   repo-carried dial state, kit-tree enforce / adopter-export observe, each flip proven by
   `PHASE-B-DIAL-FLIP`'s before/after AC (an actual denied push, never a read of the dial's
   value). No dial is left in bare observe: every observe state above carries its named trigger.
2. **`BOARD-DOR-FIELDS` is FUNDED as an XS slice now** (success-metric/hypothesis field into the
   board template + live rows) — the owner-lens revision of the agent's proposed dated deferral:
   deferring a third-carry item at the same sitting that adopts ruling 4's third-carry escalation
   would be self-inconsistent, and Phase C should enter through a board that satisfies the kit's
   own Definition of Ready. This discharges panel #39 C3 and reverses the row's prior deferral by
   explicit ruling.
3. **The verify.sh lane-cost disposition is a DATED DEFERRAL, decided together with
   `NON-VACUITY-SHARD2-FLOOR` after its per-mutant substrate measurement** — the owner-lens
   revision of the panel's exclusions-entry preference: choosing coverage reduction before the
   measurement the panel itself demands (its §8a) is deciding ahead of the evidence. The
   substrate measurement is funded early post-B; no further conformance-core re-shards (measured
   ~0 wall-clock benefit).
4. **The panel's three meta-amendments are ADOPTED** (ratified with the PR carrying this entry):
   the two standing panel-template questions (permission re-ratification · scope-coherence lens)
   in `docs/operations/meta-control.md` · the first-live-run-dogfood line in
   `skills/design/SKILL.md` (a slice shipping a new mechanism records that mechanism's first live
   run on its own slice in §10) · third-carry auto-escalation (a finding reaching its third
   consecutive panel escalates one severity) in `docs/operations/meta-control.md`. Ruling 2 above
   is the escalation rule's first application, made knowingly.
5. **The publish gate: the recorded release GO IS the publish authorization** (owner-ruled earlier
   the same day, recorded here). Historical publishes rode per-run harness prompt-clicks; the
   auto-mode classifier's silent removal of that prompt (measured 2026-08-11: `publish-public.sh`
   denied with no ask) exposed that the gate lived in a harness mode, not in the kit. The durable
   gate is the ledger's release GO; the permission allowlist entry
   (`Bash(sh scripts/publish-public.sh*)`, owner-added) is that ruling's **delivery surface**, not
   an independent control. Third measured face of the permission-surface class →
   `PERMISSION-SURFACE-DELIVERY-AUDIT`, promoted to Ready with this sitting.
**REVISIT-CONDITION:** ruling 1's per-dial triggers are each self-executing (a named event, not a
date); ruling 3 re-opens at the `NON-VACUITY-SHARD2-FLOOR` substrate measurement; the others none.

**`D-240811-3` · ruling (owner, 2026-08-11, in-session at the BRANCH-SCOPE-END-TO-END design GO) ·
Branch-scoped GO records become PERMANENT; the B2 §8 author-controlled-key ceiling is re-ratified
AS NARROWED.** The `[S4]#7` re-record protocol is retired (tombstoned in
`docs/governance/promotion-contract.md`), so the `-f` reaping that kept branch records transient
disappears. The ceiling ratified: *an author-controlled key whose records persist, bounded by (a)
the D11 charset, (b) TWO-LEG containment — the approved commit must be reachable from the graded
head AND not already integrated into the base (leg 2 added in fix round 1 after the security seat
measured the one-leg form satisfying unrelated same-named work at rc 0 under merge/rebase
integration; disclosed degradation to reachable-only where no base resolves), and (c) the
`D-240805-4` render keeping every matched record owner-visible verbatim.* The fork face is stated
in the design §9.1: a fork can green the design gate; the owner's ratification approval remains
the merge control. The strong cure was chosen over prose narrowing precisely so this entry is
true as ratified. **REVISIT-CONDITION:** re-open if a base-resolution shape is found where leg 2
silently fails to run (the disclosed-skip arms are the only sanctioned degradations).

**`D-240813-1` · ruling (owner, 2026-08-13, in-session at the `BOARD-DOR-FIELDS` design GO) ·
DEMOTE, DON'T FILL — the DoR's Success-metric field is enforced AT ENTRY, and a Ready row that
cannot carry an honest measurable metric DEMOTES rather than being filled in.** `D-240811-2.2`
funded the field; this entry records how it is met, because the mechanical reading of "the field
lands in live rows" was falsified by measurement at build time.

**The falsifier:** the Ready table held **138** non-empty rows. Populating 138 cells would
mass-produce exactly the populated-but-untrue filler the row's own honest ceiling warns against,
and would leave the board's measured 50% misstatement rate intact while looking cured.

**The reconciliation, and it is exact:** **12 KEEP + 12 CLOSE + 111 DEMOTE + 2 index-rows-to-prose
= 137 triaged**, plus **`BOARD-DOR-FIELDS` itself** — which is not in the triage because its own
claim commit had already moved it from Ready to In Progress — **= 138, the base table exactly.
Zero rows lost.** Verified by identifier: all 137 triaged identifiers are present in the base
Ready table and all 137 still resolve on the post-edit board, and the single base row matched by
no triage entry is `BOARD-DOR-FIELDS`. (`WAIVER-CLOSING` is a badge prefix on the demoted
`PHASE2-OWED-SWEEPS` row, not a row of its own.)

**Ruled:** a row that cannot state how we will know it worked is **by definition not Ready**. It
moves to *Backlog (unrefined)* under a dated ledger note keeping its identity and its reason;
promotion back costs one line (add a metric) and the gate is the ratchet. The asymmetry is the
argument — demotion is cheap to reverse, a manufactured metric is not, so doubt resolves toward
DEMOTE. Correspondingly, `N/A — <reason>` is REJECTED for this cell (the In-Review PR asymmetry
applied to the DoR): an escape hatch here would rebuild the filler the ruling exists to prevent.

**The disposition was ruled at the GO** and applied at build: **KEEP 12 in Ready · CLOSE 12 as
already discharged (one collective Done entry) · DEMOTE 111 · 2 index pseudo-rows to prose = 137
triaged; + `BOARD-DOR-FIELDS` in flight = 138.** Both flagged P0s were KEPT against the probe's
recommendation, each on named grounds:
- **`GUARD-HOOKSPATH-CASE-BYPASS`** — kept as a **knowing owner re-ruling on the DEAD-PREMISE
  ground, explicitly NOT on "the deferral condition lapsed"** (that reading is disputed: two of the
  named three phases are complete, so if the condition means A/B/C it has not lapsed). The premise
  is dead because since v3.210.0 `core.hooksPath` IS the live rung, so the still-reproducing
  lowercase ALLOW lets one command silently repoint the entire pre-push spine. Its build carries
  the security seat under the standing guard-matcher rule, independent of this slice's waiver.
- **`ADOPTER-TOLD-LOOP-GATES-ARE-ENFORCED`** — kept **re-premised in two halves**: the XS truth-fix
  of the shipped `CLAUDE.md:10` / `AGENTS.md:10` per-gate wording (the false enforcement claim is
  LIVE in the adopter's most-authoritative file, and `incept` renames those files into the
  adopter's own governing document), plus the row's never-built check.

**Honest ceiling, ruled as part of the ruling:** the gate proves a metric is POPULATED, never that
it is TRUE or measurable. Measurability is human judgment at the review seat; a prose scanner for
"is this measurable" is the kit's standing veto and was not attempted. The exit side of the metric
loop (`## Released` → did it move?) stays dead and out of scope — disclosed, not cured.

**This entry is RATIFIABLE at the PR carrying it** (the #508 precedent, as used by `D-240811-2.4`
and `D-240811-3`): the owner's approval of this diff ratifies both the ruling text and the
disposition list, the design GO having ratified the scheme. **REVISIT-CONDITION:** re-open if the
review seat finds the populated-not-true ceiling is being exploited — i.e. if demoted rows return
to Ready carrying metrics that no one could fail.

---

## 3. The recovered record

**126 decisions recovered** from `docs/architecture/`, `docs/plans/`, `docs/governance/`, `BACKLOG.md`,
`SPARKWRIGHT-CONSOLIDATED-BACKLOG.md`, `CHANGELOG.md`, `MAINTAINING.md`, `ROADMAP.md` and `git log`
(48 + 78, before de-duplication). Every entry carries a verbatim quote and a citation.

**Schema:** `ID · DATE · SOURCE · TYPE · QUOTE · DECISION · REVISIT-CONDITION · SUPERSEDES`
**Types:** `ruling` · `deferral` · `refusal` · `deletion` · `supersession` · `greenlight`

⏳ **The full de-duplicated table is the next step** and is deliberately not pasted here unreviewed —
transcribing 126 relayed entries into an authoritative-looking file, unverified, would repeat the exact
defect this file exists to close. The raw extractions are complete and the merge is mechanical.

**Distribution (raw, pre-dedup):** ruling 68 · deferral 22 · refusal 17 · deletion 11 · supersession 8
· greenlight 8.

**Highest-value subset — every conditional deferral**, because these are the ones that get scheduled
while their condition is unmet (the §2.3 error class):

| decision | condition | met? |
|---|---|---|
| `MC-CADENCE-1` | `REQUIRED-CONTEXTS-AS-CODE` (B4) ships | ✅ **no — and it has no unit** |
| The `[S*]` burn-down pause (2026-08-02) | *"nothing is picked from them until this charter's Phase 3 produces a re-plan"* | Phase 3 produced the plan; the plan is **unratified** |
| Audit findings (2026-08-02) | *"nothing here is built before Phase 3"* | as above |
| The two P0 guard bypasses | *"NOT built before the three phases complete"* | as above |
| `T2-06` corpus | *"if it exceeds ~200 against the ~150 estimate, stop and re-plan"* | unmeasured |
| Row identity as substrate | *"blocked behind T0-05 and a re-measure"* | `T0-05` folded into `T1-13` |
| Premise register vs D5 (R-G) | *"to be settled when R3 is actually scheduled"* | unscheduled |
| `dor-defined` / `discovery-complete` (R-X) | *"delete if they cannot be made honest"* | untested |
| `KW26` guard ergonomics | *"pick up only if it becomes material"* | — |
| `MAINTAINING.md` public strip | *"requires a contribution-model decision first"* | undecided |
| CLAUDE.md §1 act 2 (R-E) | *"Revisit A only if the roster becomes load-bearing for meta-orchestration"* | — |
| Sensitive class approver bar (R-K) | *"until real sensitive work flows and there is data to lower it"* | — |
| `T0-06` / `T0-08` | an owner product decision, recorded | ⏳ **owed** |
| T0 calibration capture | ✅ **RULED 2026-08-04** — retro clause on every T0 row | ✅ met |

---

## 4. What is NOT yet done

1. The de-duplicated 126-row table (§3).
2. **Wiring:** every board row and plan unit cites its decision id, or `none — new`; missing reds the
   board gate.
3. **Teeth:** `--basis` becomes required on `promotion-verify.sh record`; a decision with an unmet
   revisit-condition cannot be scheduled; a unit deleting something shipped inside 30 days must name
   its authorizing decision. ⚠️ Control-plane — needs ratification, lands via dev-clone.
4. **The reviewer seat's standing duty:** reconcile every claim in a diff against this file. This is
   the load-bearing half — measured on 2026-08-04, *every* defect found that day was found by the
   reviewer seat or the owner, and *none* by the builder unaided (R7).

**Honest ceiling:** this catches drift at review time, not at think time. It does not stop a wrong
proposal being made; it stops one landing unnoticed. Claiming more would be the defect it treats.
