# The Proportional Promotion Contract — the human↔AI handoff model

**Status:** Canonical model (ratified 2026-06-29). The single source of truth for *how much ceremony a change carries on its way to users.* `DEVELOPMENT-PROCESS.md` §9 (Environments) and §13 (Agent Governance) reference this doc; `CLAUDE.md`'s Definition of Ready/Done point here for the promotion judgment. Design rationale: the proportional-promotion-contract design sitting (2026-06-29).

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

The load-bearing correction (owner reframe, 2026-07-07): the bootstrap made the human the mechanical *executor* of agent-prepared work (running the hand-off script, typing the merge, pushing the tag) while the real control — the GO — was incidental. Stated plainly, the model is:

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
| **Integration** (PR + ephemeral preview) | Automated gates (lint/type/test/secret-scan) required; agent self-review; GO lightweight/delegable (auto when trust is healthy) | High-risk review lane; human GO | Dev-clone authoring + control-plane-ratification |
| **Release candidate** (merged, Definition-of-Deployable) | The meaningful go/no-go — human renders explicit GO against a promotion-readiness surfacing; builder≠reviewer; DoD + acceptance-criteria checked | full dual review + human GO | human ratify + meta-control |
| **Staging/UAT** | smoke + acceptance sign-off | + threat/privacy re-check | N/A |
| **Production** (canary/blue-green) | human-commanded; progressive rollout; rollback ready | human-commanded; irreversible-gated | N/A |

The cells are the kit's *existing* pieces connected: the autonomy tiers (§13) fill the "agent autonomous" cells, the environment promotion (§9) is the rungs, the review-lane Default/High-risk is Ordinary/Sensitive, the control-plane guard + dev-clone authoring + M2-S5 is the right column, and the human GO at Release-candidate/Production is the go/no-go. **"N/A" = not applicable** — the control-plane is a governance artifact whose lifecycle is author→ratify→merge; it does not deploy to runtime rungs — **not** "not available."

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
4. **GO/NO-GO judgment, not a keystroke:** the human renders an explicit GO whose *depth* equals the cell's rigor (lightweight/auto for Ordinary-low; a real recorded judgment for Sensitive / Control-plane / Release-candidate / Production). **Execution after GO is delegable** to either party — the agent may merge/tag *after* the human's GO. The keystroke stops being the (false) control; the **judgment is the control.**

   **Never-weaken invariant:** a GO is never reached by weakening security, architecture, or governance. If the bar can't be met the change does not promote — you do not lower the bar to manufacture a green.
5. **DoD + acceptance criteria are the *content* of the Release-candidate go/no-go** (frame vs. content): the RC promotion-readiness pulls the story's acceptance criteria (from the tracker — Jira / ADO / `BACKLOG.md`) and the kit's Definition of Done, and cross-checks "did it meet the criteria," not merely "does it not break."
6. **The pre-build gates are recorded through the same ledger.** `scripts/promotion-verify.sh record` is not only the merge-time GO: `--gate design` and `--gate plan` record the **DESIGN GATE** and **SPEC/PLAN GATE** — the two pre-build touch points that were prose until v3.187.0. Same tool, same SHA-bound note, same derived assurance label; no new ceremony and no new artifact, since the design and plan documents are already mandated. `--basis` names the artifact the GO approves.

   **Record the GO before opening the PR** — `record` fetches the ledger first and publishes it
   itself (`--no-push` is the labelled fixture escape); CI fetches `refs/notes/promotions` within
   seconds of the PR being created, so a ledger published afterwards loses the race and the gate reds
   on a compliant change until the job is re-run. (Measured on this mechanism's own PR: an 11-second
   gap was enough.)

   **Scope the design GO by BRANCH — one record, no re-record.** A design GO is recorded *before* the PR exists, so it carries `--scope branch/<name>` (`D11`). Since **2026-08-11** (`BRANCH-SCOPE-END-TO-END`) the CI gate matches **either** key — `scope: PR-<n>` **or** `scope: branch/<head-branch>` — so that one record satisfies the pre-push hook *and* the merge gate. ⚠️ **TOMBSTONE — the `[S4]#7` interim protocol is RETIRED (2026-08-11).** It required re-recording the GO under the PR scope at PR creation; that step is **gone**, and with it the record→poster race it caused (a re-record landing after CI fetched the ledger cost one decider re-run per gated PR, measured 4×). Existing `PR-<n>` records keep working forever; nothing is migrated. **Ceiling, ratified as narrowed (`D-240811-3`):** branch-scoped records are now **permanent** (only a same-SHA re-record overwrites) and branch names are author-reusable, so the key is bounded by three things and by nothing else — the `D11` charset (a name outside it drops the key, disclosed, rc unchanged), **two-leg containment** (the record's `approved-sha` must be an ancestor of the graded head **and not** an ancestor of merge-base(head, base) — reachability alone is defeated once a historic same-named branch is merged or rebased into the base and its approved commit sits on the mainline, measured; with both legs a historic same-name branch's record is inert, and where no base resolves the run is `reachable-only`, disclosed on stderr and in the verdict, rc unchanged), and the verbatim record render at the judgment surface (`D-240805-4`). A fork PR can reproduce both a branch name and a public commit, so a green design gate on a fork is **one required context**, never a merge — the owner-only ratification approval remains the control.

   For a Sensitive or Control-plane change `conformance/ceremony-binding.sh` checks this in CI: it flags a design artifact that is missing, stubbed, symlinked, unnamed by a `--gate design` record **scoped to that change** (either key), whose approved commit is **not contained** in the graded head's history, or naming an artifact that is not a design document. Ordinary changes derive N-A and are untouched — the gate stays off XS and doc work by design. **It is a REQUIRED status context on `main` as of 2026-07-26** (the 9th), so it blocks the merge rather than merely reporting.

   **Honest ceiling:** the check grades **existence and binding — NOT order, and not quality.** It makes no ordering claim at all: a design written *after* the work passes. That predicate was withdrawn after repeated defeats in three review rounds, and the question is now **closed as a recorded NO-BUILD** (2026-07-30): no sound *evidential* ordering proof is achievable against an author who controls the commits, because every ordering signal is either author-written or attests author-chosen publication order. See the catalogue in the gate's own tombstone (`conformance/ceremony-binding.sh`, the `ORDERING IS WITHDRAWN` block). ⚠️ This closes **proof**, not **prevention** — a control that *creates* order at edit time rather than reconstructing it afterwards would be unaffected by this closure, but the kit ships none today (the `[S1a-i]` edit-time phase gate was built, never wired to a caller, and parked on 2026-08-19; the retirement record is the kit maintainers' `docs/kit-internals/retiring-conventions.md`, not in the adopter export). It also cannot tell whether a design is sound or whether anyone read it. `refs/notes/*` also sits outside branch protection, so the ledger holding these records is itself unprotected. It raises the cost of skipping the gate; it does not make skipping impossible.

7. **Acceptance stays at merge — no pre-merge check stands in for the recorded GO.** Whatever drift controls run *before* merge — a hook, a linter, a stage or phase check — none of them makes an ordering claim or a ratification claim, and a green one is **never** evidence that a promotion was approved. The recorded GO, `ceremony-binding` and `control-plane-ratification` remain the control. A pre-merge control can only raise the cost of *starting* ungated work; only the merge-time gates decide whether it *ships*. This also does not close `ORDINARY-CLASS-UNGATED` — ordinary work still has no merge-time floor.

   *Tombstone (2026-08-19, `D-240819-3`).* The `[S1a-i]` edit-time phase gate (`conformance/phase-gate.sh`) was the concrete instance this item used to describe: an Edit/Write-route decision that failed OPEN on every undecidable state, was **never wired to a caller**, and was parked to the history branch `history/phase-gate-s1a-i`. The principle above outlived it and is stated on its own terms.

---

## §sync — reconciling a diverged ledger

`scripts/promotion-verify.sh sync [--dry-run] [--discard-local <sha>]…` is the front-door cure for a **diverged**
`refs/notes/promotions`: the local ledger holds records origin lacks (whether or not origin has also moved)
(an offline `--no-push`, a crash mid-`record`, or a shared `.git`). `record` refuses on that state and names `sync`;
a plain `git push` is rejected as a non-fast-forward, and a raw `git notes` write is denied by the guard
(`D-240805-3`).

**When to use it.** Only when `record` says "ledger diverged". Preview with `sync --dry-run` (it validates, prints
`WOULD` lines and writes nothing), then run `sync`. It is **operator-only by policy** (the script does not detect CI or a subagent): the orchestrator or owner runs it, never
CI, and **never a subagent** (`D-240805-3`: a subagent never writes the ledger; `D-240805-4`: the orchestrator records, the owner verifies).

**Classification vocabulary** (by note-tree *content*, not by commit):
- `kept-origin <sha> (local-absent)` — origin has a note the local ledger lacks; origin's note is kept (union).
- `twin-origin-wins <sha>` — the same commit, different bytes, identity fields agree; origin's bytes stand (R1).
- `candidate <sha>` — a local-only note; after V1-V7 it is published (`published <sha>`).
- `discarded-local <sha>` — a local note dropped because you named it with `--discard-local`.
- `REFUSED <sha>` — a note that cannot be reconciled; the refusal names the field and the remedy.

**R1 — identity versus free text.** For a twin, `approved-sha` (after resolving), `approved-tree`, `approved-by` (id
*and* label), `gate`, `rung`, `change-class`, `kit-row` and `scope` are compared byte-exact; if they agree, origin
wins and only the free text (`approval-token`, `basis`, `recorded-at`) differs. Any identity disagreement refuses,
prints both notes and names `--discard-local <sha>`.

**V1-V7 — a local-only note is published only if it is exactly what `record` would write now.**
V1 the body grammar (`record`'s 13 lines (a header line + 12 keys, `go-by` fifth), or the LEGACY 12 lines (no `go-by`, which then counts as `(none recorded)`), in order, no control bytes; a `go-by` value must be `(none recorded)` or `<name> [self-asserted]` — any other label is refused, and `go-by` is an identity field for twins); V2 `approved-sha` resolves to the note's own
commit; V3 `approved-tree` is that commit's tree; V4 `kit-row` equals the commit's own `Kit-Row` trailer (or `(none)`);
V5 `change-class` is in `record`'s vocabulary; V6 `scope` obeys `record`'s scope rules; V7 the `approved-by` label is
one `record` could derive now (`derive_assurance`, or the forge-review upgrade). Sanitizers (V1-V6) run before V7. A
failing note is **refused, never rewritten or downgraded**; the remedies are `--discard-local <sha>` or re-issuing the
GO with `record`.

**The voided-upstream arm.** A local-only note on a commit that origin's *history* once carried and no longer does was
voided upstream (`D-240805-3`). Re-publishing it would resurrect a voided record, so `sync` refuses and names the sha.

**A non-note entry in the local ledger tree.** A path that is not a 40-hex note path (or any path in a SHA-256 repository) is refused, never dropped. `sync` cannot discard it (`--discard-local` names notes only). Inspect it with `git ls-tree -r refs/notes/<ref>`; removing a non-note entry is an operator-only plumbing repair (`D-240805-3`: a raw notes write is guard-denied for agents).

**`--discard-local <sha>`.** Repeatable; lowercase 40-hex (used as-is: the commit need not exist locally, which is exactly when the refusals print this remedy) or a unique prefix of 4+ chars, resolved against the note paths of the two ledgers. It applies **only** to the shas it names and drops
those local notes in favour of origin's state. It never touches origin.

**The R2 backup ref.** When a run drops local content (a twin origin wins, or a `--discard-local`), the old local tip is
kept at `refs/kit/promotions-presync-<UTC>`. It is local, never pushed, and no backup is made on a pure fast-forward or
a publish-only run. Once you no longer need it: `git update-ref -d refs/kit/promotions-presync-<ts>`.

**What it never does:** rewrite or change a published note (I1), force-push, create a merge commit, publish a label
`record` could not derive now, push any ref but `refs/notes/promotions` (I3), or delete the ledger. The result is a
fast-forward descendant of origin's tip. Exit codes: 0 reconciled (or nothing to do); 2 refused/unreachable, with
nothing dangling, except two rare paths the script reports loudly: the push was rejected and the ledger moved under the run (not unwound; backup kept), or POSTCONDITION FAILED after a push (state unknown; inspect with `log --unpushed`). A signal exits 130/143.

**Honest ceiling.**
(a) **V7 is evaluated at sync time.** A PR-scoped `[authenticated: github-review]` note is refused when `gh` is
unavailable or offline, when it authenticates as a different account, or when the review has since been dismissed.
Each such candidate costs an un-timed network call.
(b) **Ctrl-C and some CI cancels signal the whole process group.** The deferral protects the shell only, so a git
child can die mid-ref-update. The window is tiny and pre-existing.
(c) **The ledger binds; it does not authenticate.** `sync` proves a published record is one `record` could have written
at sync time, against the forge's answer at sync time; it does not prove a human rendered that GO, and an agent under
the owner's identity can still `record` directly.
(d) **The voided arm sees only voids visible in origin's notes history;** a void done by force-rewriting origin's ledger is
invisible to it (such a force-push is itself denied by the guard and by remote branch protection), or a notes history
truncated by a shallow fetch, which `sync` refuses (a shallow *branch* clone whose notes chain was fetched in full is fine).
(e) **Replacement objects and grafts are honoured by every read `sync` makes.** A `refs/replace/` object, or an
`info/grafts` file, in the operator's clone is applied by git to the history walk, the tree reads that classify
(`ls-tree`/`diff-tree`), and the build on origin's tip. Such an object can cut the notes history without touching the
shallow file, which blinds both the voided arm and the truncation check. It can also skew what `sync` classifies and
builds. Planting either takes local write access by the same actor the rest of this ceiling already names. The hardening
(`GIT_NO_REPLACE_OBJECTS=1` for the whole script, plus a refusal when a grafts file exists) is boarded
(`RECORD-LEDGER-READ-HARDENING`), not claimed.
(f) **Requires git ≥ 2.31** (`--diff-merges=separate`). The history read runs before the fast paths. So on an older
git, every `sync` against an origin that has a ledger refuses with "sync: cannot read origin's ledger history …",
including a pure fast-forward and an already-equal ledger. Only a first publish, where origin has no ledger, still
runs. It fails closed and never publishes wrongly.

---

## What stays human-governed (unchanged)

The **Control-plane column stays human-ratified at every applicable rung.** The meta-level — the kit changing its own guardrails / standards / gates / governance marker — must not be agent-self-governable (fox/henhouse). This redesign does **not** relax it; it relaxes the *Ordinary* class where the ceremony is currently miscalibrated. This invariant is locked by `conformance/promotion-contract-documented.sh` (the Control-plane column of this matrix can never document an "agent autonomous" disposition).

## Delegable execution — who may run the keystroke (operative)

Execution of a promotion's keystrokes (merge, tag, release) is **delegable after an explicit recorded human GO** — the judgment is the control, not the keystroke. What is delegable depends on the change-class:

- **Tier 1 — always (build phase, within a rung):** the agent reads/drafts, writes code + tests on a feature branch, `git commit`s (reversible), pushes feature branches, opens PRs, authors control-plane changes in a **dev-clone** (the guard stays armed on the real repo). No per-action gate.
- **Tier 2 — delegable only after a recorded GO (Ordinary/Sensitive):** the agent may execute a normal, branch-protection-permitted merge of an Ordinary/Sensitive PR and run the tag/release step for an Ordinary release. Never before the GO; **never unilateral at a promotion.**
- **Tier 3 — the GO/NO-GO judgment itself is human-rendered, never delegable at any rung.** **Control-plane GO stays human at every rung**; the **actuation** (merge/tag) is delegable to the agent **only** on a SHA-bound, per-merge recorded GO — explicit + recorded + per-merge + **non-blanket** + **SHA-bound**, verifying post-actuation that the shipped SHA == the approved SHA (record format + verification = S2). As of **S6 this actuation is *wired*** — `scripts/promotion-verify.sh actuate` (the operative mechanism, in the honest-ceiling note below), not just a documented permission. Autonomous / inferred / auto-merge / blanket control-plane actuation stays banned. The `gh pr merge --admin` branch-protection bypass remains a human act (server-side, outside the guard — the honesty boundary, un-guardable). The **catastrophic non-promotion set** — push-to-main / force-push (guard-blocked); deploy-to-prod / delete-data / rotate-secrets / incur-spend — is denied **regardless of any approval** (approval authorizes *promotion*, never destruction).

The decisive line is `is_control_plane_path` (change-class), not the keystroke: because the kit's own surface *is* the control-plane, the kit's own work carries the **Tier-3 control-plane rule** above — the **GO stays the maintainer's** (never delegable), while the **actuation** is delegable only on that SHA-bound, per-merge recorded GO.

**The corrected division (who actuates — the load-bearing correction).** On the recorded **GO**, the **agent** actuates all mechanical steps — `git add`/commit, push, open the PR, tag, `scripts/promotion-verify.sh record` + push the notes + `check`. The **human** does the **GO** (review + `skills/demonstrate` + risk-acceptance + "proceed") and — **solo, control-plane only** — the single `gh pr merge --admin` (the kill-switch + SoD-substitute, because solo cannot satisfy branch protection; the guard denies `--admin` to the agent). **Ordinary / team work: the agent merges too, so the human does zero mechanical keystrokes — only the GO.** This is not a relaxation: the guard still blocks the agent's Write/Edit to control-plane paths **and** the `--admin` bypass, the agent never actuates **without** a recorded GO, and `builder ≠ ratifier` — the GO stays the human's. Solo, the human's *only* control-plane keystroke is `--admin`; every other mechanical step is the agent's.

On a recorded GO the agent actuates the mechanical steps (commit, push, tag, record, check); the human's only control-plane keystroke, solo, is the `--admin` merge.

**The mechanism (S6 — operative).** The `actuate` protocol is now **wired**: `scripts/promotion-verify.sh actuate --ref <pr|tag> --approved-sha <sha>` performs the delegated control-plane actuation on a recorded GO. It **fails closed** unless *all three* hold, then runs a *normal, non-`--admin`* merge and re-verifies `shipped == approved`:

1. a GO note binds **exactly** `<sha>` under `refs/notes/promotions`;
2. the derived `approved-by:` label is **`[authenticated: <forge>-review]`** (read from that line's trailing label only — never a body scan, per the S5a decoy lesson);
3. the **approver identity ≠ the commit author** (`builder ≠ ratifier`, real teeth — self-approval, even authenticated, is not SoD).

**The assurance bar (ratified):** `[self-asserted]` / `[committer]` / `[signed: gpg]`-alone **all fail** the control-plane bar — commit signing proves *who wrote* the commit, not that a *distinct* party reviewed and approved it.

**The kill-switch holds — the honest mechanism (no mode read).** The solo hold is **server-side**, not the local label check: a *normal* `gh pr merge` is rejected without a real forge review (branch protection), and `gh pr merge --admin` — the only server-side bypass — is **human-only**. *That* is what keeps `--admin` the human's one act (the honest solo kill-switch). The wired `actuate` gate's authenticated-label bar is **defense-in-depth + an audit discipline over a self-authorable git note** — NOT the primary control. **Since PR 11 the forge-review derivation IS wired for GitHub** (`docs/adoption/vc-hosts.md`): `record` reads the PR's reviews and emits `[authenticated: github-review]` for a non-author, non-Bot `APPROVED` review bound to the approved sha, so the bar is now **reachable**, and a second reviewer's GO both satisfies branch protection *and* meets the label bar → the agent does a **normal** (non-`--admin`) merge and the keystroke is genuinely retired for Ordinary/Sensitive. **This does not upgrade the label into authentication.** A raw `git notes add` is still outside the guard, and the derivation trusts the local `gh` binary and its ambient credential — so the label remains a **drift control at the note's own trust tier**, and the hold that binds is still server-side branch protection + the human-only `--admin`. The guard **never reads `lean`/`enterprise`** — mode-blindness is by construction (`conformance/mode-enforcement-blind.sh` preserved).

**Honest ceilings (S6, updated at PR 11):** the gate is **fixture-proven** (`conformance/promotion-actuate-wired.sh` — a liveness anchor + fail-closed negatives for the label bar, the SoD teeth, the tree re-check and the control-plane refusal, plus the derivation's own liveness + ten negatives driven through a `gh` PATH shim). The forge-review → `[authenticated: github-review]` derivation is **no longer a seam for GitHub** — it is wired in `record`, so `actuate` opens for **Ordinary/Sensitive** on an authenticated recorded GO, while **Control-plane is refused there** pending the open `TIER-3-CP-MERGE-ACTUATION-RULING` sitting (control-plane merges use the direct path). The live `gh pr merge` (a swappable `--merge-cmd`), the PR-number → merge-commit-sha resolution, other forges' adapters, and a team merge credential remain documented **seams**. The server-side `--admin` bypass stays **un-guardable** (`docs/operations/runtime-guards.md` honesty boundary — the guard's `--admin` deny is a *speed-bump*; the real boundary is never issuing the agent an admin credential). Live enforcement also remains the guard (push-to-main / force-push) + the `agent-boundary` CI gate (control-plane ratification at merge).

**`land` — the direct/control-plane path as ONE transactional verb (SESSION-SURFACE slice 3d, Option A).** The direct path `actuate` refuses (control-plane) is **two unbound commands** — `promotion-verify.sh record` then `gh pr merge` — and nothing ties them; at PR #658 the merge landed and the record was forgotten, so a commit sat on `main` with no recoverable board row. `promotion-verify.sh land --ref <r> --approved-sha <sha> [record's args] [--merge-cmd "<cmd>"]` collapses them into ONE verb: it **RECORDS the GO first** (record's own self-unwinding transaction, passed through untouched — *if the record does not complete, `land` does NOT merge*), confirms the note is bound to the approved SHA, then runs the merge (default `gh pr merge <ref> --squash --match-head-commit <sha>`), and **leaves the branch INTACT** — it refuses any `--delete-branch`/`--delete`/`-d` (in every quoted/split/`=value` spelling) in the merge command (deletion is a separate human act, `D-240819-4`; the branch object holds the commit the note binds) and **never emits `--admin`** in any form (bare or `--admin=<value>`). ⚠️ **The GUARD does not cover branch deletion via `git push`.** `git push origin --delete <b>` and `git push origin :<b>` are **guard-ALLOW** — uncovered and disclosed, not blocked (`D-240819-6` is about Claude's *settings* allow-rules, a prompt, not the guard tier). `land` itself never deletes and refuses a `--merge-cmd` that would; the `git push` deletion forms remain guard-uncovered. The record can no longer be forgotten because the same verb writes it before the merge exists. **`land` changes no boundary** and stays clear of the open `TIER-3-CP-MERGE-ACTUATION-RULING` sitting: the guard still denies `--admin` and control-plane Write/Edit, branch protection is unchanged, and the human still renders the GO and directs the merge. ⚠️ **Honest ceiling — `land` is NOT a hard gate.** By the friction test (*would it bind if the model stopped cooperating?*) it does not: a raw `gh pr merge` still exists and an uncooperative agent runs where this local tool is absent, so `land` refuses a recordless merge **only on its own path**. The friction-test hard gate for a recordless merge is the **CI recordless-merge backstop** (`promotion-verify.sh trace --recent`, server-side, unchanged) plus branch protection; **no prevent-at-merge gate is possible** for a self-authorable git note. `land` eliminates the honest-but-forgetful failure (#658) and makes branch-object preservation atomic — it is not the wall. **THE BAR `land` ENFORCES (GO-IDENTITY-AND-LAND-SOD, `D-241002-2`).** `land` is the verb for the *stronger* class, so it holds the *stronger* bar: it merges control-plane **only on an authenticated non-author forge approval** — the `approved-by` label (computed with the same `derive_assurance` + `forge_review_upgrade` that `record` uses) must be `[authenticated: <forge>-review]` (the regex `actuate` demands) — checked **before** the record (a refusal writes **no note** and runs **no merge**) and **again from the note on origin before the merge** (if the forge's answer changed between the two reads, the note IS recorded and `land` refuses the merge; a re-run after the approval lands, since `record` supersedes). `--approved-by` is therefore the **forge login of a non-author reviewer** whose `APPROVED` review is on the approved sha, and the owner who gave the GO goes in the required **`--go-by <the GO-giver>`** — named in the note, `[self-asserted]` by design (the kit authenticates the forge review, never the person whose judgment the GO is). **Team:** a second account approves the PR, the owner gives the GO, the agent may then merge through `land`. **Solo (one account, no second approver):** `land` refuses by construction and names this path — the agent records the GO with `record` (it takes `--go-by` too) and **the human merges** by an admin squash-merge; the agent never does (the guard denies `--admin`), and `trace --recent` is satisfied by the record. The label is still derived over the local `gh` credential at record time — a drift control at the note's own tier; server-side branch protection + required review is what binds. Fixture-proven in `conformance/promotion-verify-wired.sh` (liveness: a valid record + a stub merge writes the note and runs the merge; negatives: a record failure blocks the merge, a `--delete-branch` merge command is refused, and `trace --recent` binds the trunk head after a successful land).


### Approve→execute→log — the actuation protocol (non-control-plane; operative)

For **non-control-plane** promotions the agent may actuate the merge/tag **after an explicit, recorded, per-gate human GO** — the protocol validated in the Relay dogfood (KW1 · D2). The mechanism (`scripts/promotion-verify.sh` binding GO records as git notes under `refs/notes/promotions`, locked by `conformance/promotion-verify-wired.sh` — wired live in the kit's own CI; it ships to you and the portable aggregate runs its selftest) makes the already-shipped delegable-execution permission (v3.83.0) **auditable and safe**:

1. **Approve** — the agent **provides the means** to review + verify (the PR, diff, checks, the running increment via `skills/demonstrate`) and **waits**. The human renders the GO/NO-GO and gives an **explicit approval token** — per-gate, recorded, and **never inferred** from conversational phrasing ("let's do the merge" is *not* a token).
2. **Execute** — only on that recorded GO does the agent run the merge/tag keystroke.
3. **Log** — the agent records the approval with `scripts/promotion-verify.sh record`: it binds a structured GO record to the approved commit as a **git note** under `refs/notes/promotions` (`approved-sha` · `approved-by` · **`go-by`** · `gate`/`rung`/`change-class` · `scope` · `approval-token` · `basis`; `go-by` names the human who gave the GO and is always `[self-asserted]`, or `(none recorded)` — see `D-241002-2`), and posts the record ref on the PR for at-a-glance visibility. The record is **tree-invariant** — bound *outside* the tree it approves, so it can never perturb it (closes S4-finding #1: an in-tree log append perturbed the approved tree). The `approved-by` line carries a **derived assurance label** — `[signed: gpg]` (a signed approved-sha) → `[committer]` (the git committer identity) → `[self-asserted]` (a free-typed approver git cannot corroborate) — that never overclaims *how* identity was established; authenticated approval (`[authenticated: github-review]`) is **derived from the PR's own reviews** since PR 11 — a non-author, non-Bot `APPROVED` review bound to the approved sha — with other forges still the adapter **seam** (`docs/adoption/vc-hosts.md`). ⚠️ **Operator note: `--approved-by` must be the reviewer's *forge login*, verbatim** (`octocat`, not a display name). The upgrade requires a **byte-equal** match to the review's `user.login`, so a display name records the weaker git-native label and prints `forge-review derivation: reviewer-not-in-reviews` on stderr — it never fails the record, which is exactly why the wrong value is easy to miss. `--class` likewise takes one of `ordinary | sensitive | control-plane` (case-insensitive) and is refused otherwise, because that field now decides whether `actuate` may merge. View the trail with `promotion-verify.sh log` (a projection of the notes). Sharing is not a separate step: `record` fetches `refs/notes/promotions` before it writes, refuses if the local ledger has diverged, and publishes the record itself, unwinding its own unpublished note if the push is rejected — `--no-push` is the labelled fixture/offline escape and says `UNPUBLISHED` on its OK line. `promotion-verify.sh log --unpushed` names anything the remote does not have.
4. **Verify** — the agent then runs `scripts/promotion-verify.sh check` to assert **`shipped == approved`** (the merged trunk / the tag carries the approved SHA — and the tag's `VERSION` matches the approved one), **at merge AND at tag**. A mismatch is an incident, not a warning — it hard-fails (`SHIPPED != APPROVED`).

**Who may record a GO, and which identity goes where (`D-241002-2`, the M 51 answer).** *Recording* a GO is not *rendering* it. An agent may run `record` for **any** class on the owner's explicit word, quoted verbatim in `--token`; the GO — the judgment — stays the human's at every rung and class, and the agent never infers one. Three identities, three fields: **`--token`** is the owner's words; **`--go-by`** is the owner by name (the human judgment, never authenticated); **`--approved-by`** is the forge reviewer — the **one** identity the kit authenticates (`[authenticated: <forge>-review]`) — or, for a design GO, the design commit's committer (a design GO binds to the committer, and `[committer]` is only as strong as `user.name`). `land` enforces the authenticated review for control-plane (above); `actuate` is unchanged. Hence this section's "non-control-plane" heading describes where the *agent merges on `actuate`*, not who may write the note: control-plane GOs are recorded the same way, and merged by `land` (team) or by the human (solo).

This is **uniform delegation riding the existing rung×change-class gating** — no new axis. It changes behavior only where a human GO is already mandated: it removes the *keystroke* there while keeping the *GO*. **Blast radius scales the verification, not the permission** — `shipped == approved` is uniform but most load-bearing at RC/Production, trivial at Spike.

**`builder ≠ ratifier`** — a **first-class invariant, peer to `builder ≠ reviewer`** (a.k.a. `builder ≠ promoter`): the agent may prepare, execute, and record a promotion; it must **never ratify** it.

**Control-plane actuation stays human — a kill-switch + a temporary bootstrap, *not* "human control"** (honest relabel, S4/KW20). This `approve→execute→log` protocol wires **non-control-plane** promotions only; control-plane actuation follows the Tier-3 rule above (the GO stays the maintainer's; actuation is delegable only on a SHA-bound, per-merge recorded GO). The reason the human still types the control-plane keystroke **solo** is **not** that the keystroke is a governance control — it never was. It is that (a) without an authenticated second-reviewer GO a *normal* agent merge is rejected server-side (branch protection) and `--admin` — the sole bypass — is human-only, leaving `--admin` the human's only route; and (b) the solo **kill-switch** (the only defense-in-depth a solo maintainer has) *is* that server-side control. **PR 11 narrowed (a) without removing it:** the derivation makes an authenticated GO producible on GitHub, so `actuate` now merges Ordinary/Sensitive changes — but `actuate` **refuses Control-plane outright** while `TIER-3-CP-MERGE-ACTUATION-RULING` is an open sitting, so the control-plane keystroke stays the human's by an explicit, disclosed arm rather than by construction. That arm is a **drift control** (the class is caller-recorded) and the sitting may remove it. **S6 grants the capability** — the agent-actuation path for the control-plane is now wired, on top of the **S5** recovery net (the honest thing that makes delegated actuation safe is *recovery*: see, stop, undo, not a keystroke); a **team's** authenticated second GO meets the bar and the agent actuates a *normal* merge. The wired `actuate` path's label bar is defense-in-depth + audit over a self-authorable note (a raw `git notes add` is outside the guard) — it does **not** by itself make the bar "unmeetable solo"; the honest reason `--admin` stays human solo is the **server-side** branch-protection + human-`--admin` control. Solo, the Tier-3 rule and "the control-plane GO stays the maintainer's" remain TRUE — because no authenticated second judgment exists, not because a local check fabricates one.

**Recovery — the S5b net (drilled).** Control-plane recovery reuses this contract's own `check`: `git revert <bad control-plane merge>` restores the prior tree, and `scripts/promotion-verify.sh check --ref HEAD --approved-sha <last-good>` proves *reverted == last-good* by the **same tree-equality** that proves *shipped == approved* — no new revert command. This restoration is drilled + CI-gated by `conformance/control-plane-revert-drill.sh` in the kit's own CI (a *non-restoring* revert FAILs, the load-bearing negative; the drill ships to you and the portable aggregate runs its selftest), and assembled into the agent break-glass procedure (halt → revert → rotate → postmortem) in [`docs/operations/break-glass.md`](../operations/break-glass.md). S5b builds the *undo* — the S6 precondition; S6 is the deliberate capability grant on top of it.

### The general kill-switch posture

The "deploy-failsafe dial" and the solo "human merges the control-plane" are **the same object** wearing two labels: a **configurable human circuit-breaker at a high-assurance actuation point**, calibrated to *blast-radius × threat-model*. S4 unifies them into one honest posture:

- **What it is:** a human keystroke retained at an actuation point *purely* as a **kill-switch, not a validation** — the GO is the validation; this is a circuit-breaker against a compromised / malfunctioning agent. It is a **posture, not a gate** — a gate would read the mode.
- **Default posture:** *on* where blast-radius is highest **and** there is no other defense-in-depth (solo control-plane; production deploy); *off* where the agent + gates + `shipped == approved` are trusted (the `lean` / non-control-plane default — the agent actuates on the recorded GO).
- **`lean` vs `enterprise`:** `lean` = the agent actuates on the recorded GO, kill-switch off. `enterprise` = *adds* the kill-switch (and, where a team exists, the real SoD second-GO). Enterprise **strengthens** (adds a human step); `lean` never *removes* an applicable gate.
- **Posture, not gate — preserves `mode-enforcement-blind`:** no enforcement-surface script reads the mode to decide the kill-switch. It is a documented, human-configured operational posture (see `docs/operations/progressive-delivery.md`).
- **Honest ceiling / defer-build-ahead:** the control-plane actuation is now **wired (S6, on the S5 recovery net)** — ending that bootstrap; the *prod-deploy* failsafe posture remains a documented posture with no live consumer yet, riding **KW23**. S4 defined the posture honestly; S6 built the control-plane half.

**Honest ceiling:** `shipped == approved` is the **gateable** guarantee — the record's existence, its SHA-binding, and the post-actuation content match are CI-checkable (the half that would have hard-failed the tag-on-wrong-commit / content-not-committed slips). The match is by **tree equality** (`git rev-parse <ref>^{tree}` == `<approved-sha>^{tree}`) — exact content equality, which neither false-fails a squash merge nor false-passes a revert or extra content. `never-infer` is **FLOOR discipline** — that the agent *waited* and refused to infer approval is not runtime-gateable; the record's existence + SHA-binding is checkable, the *judgment not to infer* is discipline. Do not read a green check as proof of never-infer. **The record itself — a git note bound to the approved commit under `refs/notes/promotions` — is a self-authorable *advisory* trail: it *binds* (tree-invariantly, so it can never false-fail `check`) but does NOT *authenticate*. A git note is a mutable ref: it defends against an honest-but-buggy agent's slips and provides audit evidence, but it is NOT tamper-evident against a compromised/malicious actor (that threat is the S4 deploy-failsafe circuit-breaker's job, not this record). The `approved-by` assurance label (`[signed: gpg]` → `[committer]` → `[self-asserted]`) states HOW identity was established and never overclaims. Re-recording a GO on the *same* approved-sha **supersedes** the prior note (`git notes add -f`) — prior gate history is not retained in the trail; view the current recorded state with `promotion-verify.sh log`. The authoritative assurance is the trailing derived label on the `approved-by:` line (derived, honest) — consumers must read *that* line's label, not substring-scan the whole note body, because a `--token`/`--basis`/`--scope` value may legitimately contain bracket text (e.g. `approval-token: "GO [per PR #257]"`).** Documented-coherently by `conformance/promotion-contract-documented.sh`; the integrity check is non-vacuously locked by `conformance/promotion-verify-wired.sh`, wired live in the kit's own CI (it ships to you; the portable aggregate runs its selftest).

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
