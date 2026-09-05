# Meta-control — the cadenced adversarial go/no-go (operator procedure)

**This is the shipped, sufficient procedure.** If a gate sent you here — `release-tag.sh` refusing to
tag, `meta-control-fresh.sh` reading OVERDUE/ESCALATED, or `ceremony-binding.sh` asking for a
governance-lane GO — everything needed to clear it is on this page.

## What the panel is

An **independent adversarial review**, run at cadence boundaries, producing a **verdict artifact** whose
findings are **routed into your backlog**. It catches **direction / proportion / over-claim** drift — the
failure class tests and CI cannot see, because the failure is not correctness but *whether you are
building the right thing, at the right size, honestly, in the right order.* Unlike an in-build
self-check it leaves a committed artifact, so *"is there a fresh verdict?"* is mechanically checkable.

## Opt-in — OFF until you create two files

The kit ships this **default-off**: `meta-control-fresh.sh` returns **N/A** on a tree that never adopted
the cadence, and no `verify.sh` row runs it. **The marker and log ARE the opt-in:**

```sh
printf '%s\n' '<your-VERSION> GO' > docs/governance/.meta-control-last
{ printf '%s\n' '# Meta-control verdict log' \
    '| Date | Version | Trigger | Profile | Verdict | Artifact | Summary |' \
    '|------|---------|---------|---------|---------|----------|---------|' \
    "| $(date +%Y-%m-%d) | <your-VERSION> | adoption | light | GO | <panel-artifact-path> | initial adoption row |"; \
} > docs/governance/meta-control-log.md
```

The log is a **markdown pipe table** and must stay one — the gate parses rows starting with `|`
(Version = column 2, Verdict = column 5); a header-only log is an **invalid state** that fail-closes
tagging, so the seed above lands a real first row, with the marker set to the same `VERSION VERDICT`.
Start your log **fresh** — it is your run history; the kit's own copies never ship. Once both exist the
cadence gate applies to your repo; delete them and it returns to N/A. Applicability is **detected, never
declared** — a declared "mode" cannot switch it off while the files exist. Treat both as
**control-plane**: a verdict should be a human-ratified commit, not something the governed agent issues.

## The light 5-lens panel (the copyable form)

The procedure the OVERDUE/ESCALATED cure text prescribes. Run each lens as an **independent adversarial
reviewer, default-to-critical**, then a **verify pass** that re-checks every finding.

1. **Scope-coherence & proportion** — right *size*? over-build, build-ahead-of-need, ceremony with no
   leverage, a control hardened on an empty surface?
2. **Honesty & over-claim** — declaration vs behaviour: do README / CHANGELOG / headline claims match
   what is *proven* (vs merely provided, vs prescribed)?
3. **Enforcement integrity** — the green-while-dark hunt: does each gate verify *behaviour* or only
   *declaration*? has any check drifted green as the code moved beneath it?
4. **Direction & sequencing** — is the *next* planned work still the right next thing, or has the plan
   accreted? what should be resequenced, merged, dropped?
5. **Right-weighting & adoptability** — too much for your team's span? is progressive disclosure intact,
   or has rigor outrun fit?

Per-lens output — **a finding without evidence is dropped**:

```
lens: <name>
findings:
  - severity: Blocker | High | Medium | Low
    title: <short>
    evidence: <file:line | command + output | repro steps>   # REQUIRED
    claim_vs_reality: <what is claimed> vs <what is true>
    recommendation: <concrete next action>
verify:
  - finding: <title>
    status: confirmed | refuted | downgraded
    note: <independent re-check evidence>
```

**Verdict scale** — **GO** (0 blockers, 0 unaddressed highs on the supported path) ·
**GO-WITH-CONDITIONS** (0 blockers; highs fix-forward, breaking no verified path or headline claim) ·
**NO-GO** (≥1 blocker). **Routing — a run that routes nothing is theater:** ranked findings become
backlog rows; any guardrail/standards change is proposed as a human-ratified PR. Agents propose, humans
ratify. At an **epic / release / major boundary** run a broader breadth sweep instead (adoption, persona
usability, harness neutrality, standards adherence, security red-team, operability, honesty): the 5-lens
form is the **backstop**, the boundary sweep the standing obligation. A neutral steward with no stake in
the work produces the artifact, the row, and the routed proposals **as text a human commits**.

## The ledger row (what you commit)

Append **one pipe-table row** per run to `docs/governance/meta-control-log.md` (the gate reads only
lines starting with `|`; Version is column 2, Verdict column 5 — a `·`-separated or plain line is
invisible to it and fail-closes tagging):

```
| Date | Version | Trigger | Profile | Verdict | Artifact | Summary |
|------|---------|---------|---------|---------|----------|---------|
| 2026-08-30 | 3.220.0 | release-boundary | light | GO-WITH-CONDITIONS | docs/architecture/panel.md | 2 highs routed |
```

**Update both files together** — append the row *and* set `.meta-control-last` to the same
`VERSION VERDICT` (e.g. `3.220.0 GO-WITH-CONDITIONS`). The gate fails on desync, so they cannot drift
apart silently. A dated, reasoned **`DEFERRED`** row is a legitimate outcome (a human-ratified "not
now") and also advances the marker: what the gate enforces is that a **conscious cadence decision was
recorded**, not that a ritual was performed. Serial deferral is capped — **two consecutive `DEFERRED`
rows read OVERDUE**, and only a real run clears that.

## The N=5 backstop, and how `release-tag.sh` reads it

`meta-control-fresh.sh` reads the marker and the log and answers one question: *is a panel overdue?* It
is **DUE once more than N=5 release tags** have landed since the last addressed run. N=5 is a **backstop
clock**, not a schedule — it stops "at boundaries" decaying into "never" when boundaries are far apart.

| State | Meaning | `release-tag.sh` |
|---|---|---|
| FRESH / N/A | within N tags, or cadence not adopted | tags normally |
| **OVERDUE** | past N tags, or the serial-deferral cap fired | **warns**; the tag proceeds (grace band) |
| **ESCALATED** | past 2N tags with no recorded decision | **REFUSES to tag** |
| invalid | marker missing, unparseable, or desynced from the log | **REFUSES to tag** (fail-closed) |

To clear ESCALATED: run the 5-lens panel **or** record a dated, human-ratified `DEFERRED` row — either
appends a row and advances the marker, which un-escalates by construction. A marker **ahead of
`VERSION`** is rejected (no fabricated future pin). During a ruled release-batching period with no
per-slice tags, count **merged slices** instead of tags so batching cannot starve the clock. `N` is
env-overridable and that override stays a **human** act: `release-tag.sh` detects a caller-set
`META_CONTROL_*` / `RELEASE_TAG_CADENCE` and says so on **every** invocation — an override can never be
*silent*. Run the live verdict weekly and as an advisory `doctor` metric; per-PR CI should run only
`--selftest`, so an overdue panel never blocks unrelated pull requests.

## Recording the panel's GO (the governance lane)

A panel PR is a **governance-record change**: its basis is the sitting record itself, so it has no design
document and never will. Record its GO on the **governance** gate, not the design gate:

```sh
sh scripts/promotion-verify.sh record --gate governance --scope PR-<n> \
   --approved-sha <commit> --approved-by <human> --basis <the meta-control artifact>
```

`record` fetches the ledger before it writes and publishes the record itself — there is no separate
push step (`--no-push` is the labelled fixture escape, and it says `UNPUBLISHED`).

That lane also requires the change-set to touch **nothing outside the governance file set**, so a routed
cure belongs in its own slice. Never point a design GO at a document the change merely amends.

## Honest ceiling

The gate proves a *decision was recorded on cadence* — never that the panel was run well, that its
findings were true, or that the routed rows were done. Depth is a human judgement; this page only makes
skipping it visible.
