# Model-tiering economics — the fan-out measurement

**Date of measurement:** 2026-07-16 · **Type:** measurement record (not a doctrine page) ·
**Boarded as:** `ECONOMICS-RECEIPT-INTO-REPO` (the B9 Δ3 rider; the old `T5-10`)

This is the evidence behind the kit's model-tiering doctrine. The doctrine itself lives where it is
executable: the per-task **Model tier (dispatch)** field in
[`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`](../../templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md),
the fan-out/serialize marking discipline in [`skills/plan/SKILL.md`](../../skills/plan/SKILL.md),
the tier declarations in `.kit/model-tiers.conf`, and the CI lock
[`conformance/model-tiering-plan-wired.sh`](../../conformance/model-tiering-plan-wired.sh) that
keeps a plan from shipping without them. Ratification happens at **plan approval** (ruling
`D-240804-5`), never per dispatch.

The receipt is written down here because until now it lived only in session memory — a doctrine
whose justifying measurement is not in the repo is a doctrine the next reader has to take on trust.

## The experiment

- **Vehicle:** a throwaway URL-shortener (zero-dependency Python stdlib), built **twice** from
  identical scaffolds.
- **Slices:** 4, deliberately **disjoint** — create/redirect · analytics · rate-limit · TTL-expiry.
- **Run A — MIXED:** 4 builders on the **fast** tier, reassembly on the **deep** tier.
- **Run B — BASELINE:** everything on the **deep** tier.
- Closed the `P1.3-spike` and `P1.5` rows.

## The headline: cost and speed DIVERGE

| Axis | Mixed (Run A) | Baseline (Run B) | Delta |
|---|---|---|---|
| **Cost** (deep-equivalent tokens; weights deep = 1.0, fast = 0.3) | **91,648** | 192,093 | **−52% (cheaper)** |
| **Speed** (wall-clock, end to end) | **243.4 s** | 237.3 s | **+2.6% (slower)** |

Detail behind the two numbers:

- **Tokens.** Fast builders burned **161,193 raw** tokens (×0.3 = 48,358 deep-equivalent) against
  the deep builders' **147,775** (×1.0). The cheap tier used **6.5% MORE raw tokens** — the deep
  tier is genuinely more token-efficient per unit of work; the cost win comes entirely from the
  price weight, not from doing less.
- **Wall-clock.** The builder phase was **faster** when tiered down — 99.4 s vs 124.3 s (**−20%**).
  The **reassembly** phase reversed it: 144.0 s vs 113.0 s. The cheap builders left **one**
  cross-slice conflict, and resolving it cost **+31 s of SERIAL reassembly**. The deep run
  integrated **21/21 green on the first try**.

## The durable insight

**Rework is cheap in tokens and expensive in wall-clock.** The assembly tax lands on *speed* far
harder than on *cost*, because rework happens in the one phase that cannot be parallelized.

So the rule the kit encodes is a **two-variable** one, not "always tier down":

- **Cost-bound and cleanly separable work → cheaper builders.** The 52% is real and, if anything,
  understated (see the ceilings).
- **Latency-bound or coupled work → top tier.** Tier-down is a clear cost win but a **latency
  gamble riding on output cleanliness**: one conflict was enough to erase a 20% builder-phase lead.

## Honest ceilings

1. **n = 1.** This is directional, not a distribution. Nothing here supports a confidence interval.
2. **Wall-clock is noisy** — a 2.6% delta on a single pair of runs is inside the noise band; treat
   "roughly the same speed, half the cost" as the finding, not "2.6% slower".
3. **The 0.3 weight is a placeholder.** Real fast-tier pricing sits nearer 0.2×, which makes the
   cost win **conservative** as stated.
4. **The 4 slices were designed disjoint — the best case for fan-out.** A coupled epic pays a
   bigger assembly tax, and the whole speed result is contingent on how much rework the cheap tier
   leaves behind.
5. **Tiers are named by role, not by vendor model.** The measurement was run on one provider's
   fast/deep pair; the ratio, not the model name, is what transfers.
