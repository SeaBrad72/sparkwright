# ROI Model — Agentic SDLC Kit

**This is a *planning model parameterized by your inputs* — not a measured result, a benchmark, or a guarantee. Consistent with the kit's honesty standard: it shows the logic and labels every assumption; it does not assert savings.**

For the leadership framing this supports, see [EXEC-BRIEF.md](EXEC-BRIEF.md). The elevated-baseline figures below are sourced from the [competitive benchmark, A5 record](../superpowers/reviews/2026-06-10-competitive-benchmark.md).

---

## 1. Inputs (you supply)

Every number in this model is yours. The kit supplies the *arithmetic*, not the values. Replace each row with your own measured or best-estimate figure, and label any figure you cannot measure as an assumption.

| Input | Symbol | Notes |
|-------|--------|-------|
| Team size | `N` | Engineers in scope for adoption. |
| Avg fully-loaded cost of a production incident | `C_incident` | Include responder time, remediation, and customer/SLA impact — not just the fix. |
| Deploy frequency | `D` | Deploys per month across the scoped team. |
| Current audit-evidence prep | `H_audit` | Hours spent assembling evidence per audit cycle today. |
| Audit cycles per year | `cycles` | E.g. 2 for a semi-annual review. |
| Agentic token spend | `T_spend` | Per feature, or per month — pick one and stay consistent. |
| Loaded engineer hourly rate | `R` | Fully-loaded (salary + overhead) hourly cost. |

> A model is only as honest as its inputs. If a value is an estimate, write "(assumption)" next to it wherever you record it.

---

## 2. Value levers

Three levers, each with its formula. Two reduce downside; one nets out velocity against the cost of governing it.

### Lever 1 — Risk reduction

```
risk_reduction = incidents_avoided × C_incident
```

The avoided downside is a **reduction of an elevated baseline**, not a raw gain over your status quo. The field's own data is the reference point: AI adoption layered onto weak governance was associated with a **+30% change-failure rate** and **+23.5% incidents per PR** ([A5 record](../superpowers/reviews/2026-06-10-competitive-benchmark.md)). Agents amplify whatever discipline they are dropped into.

So `incidents_avoided` is the difference between an *elevated* AI-on-weak-governance incident rate and the rate under enforced guardrails — i.e. you are modelling how much of that elevation you avoid, not a reduction below your pre-AI baseline. Express it as:

```
incidents_avoided = (elevated_incident_rate − guardrailed_incident_rate) × D × months
```

Use your own measured rates where you have them; where you don't, anchor `elevated_incident_rate` against the +23.5% figure and **label it an assumption.** Frame the result as reducing an elevated rate, never as a guaranteed saving.

### Lever 2 — Audit-evidence time saved

```
audit_savings = hours_saved_per_cycle × cycles_per_year × R
```

`hours_saved_per_cycle` is the reduction in `H_audit` once controls map to a per-control evidence list and the conformance harness emits mechanical evidence ([audit-evidence-checklist.md](../../conformance/audit-evidence-checklist.md)). This is the most directly measurable lever — you have a before (`H_audit`) and an after.

### Lever 3 — Agentic velocity, net

```
velocity_net = delivery_speedup_value − guardrail_overhead_cost − T_spend
```

This lever is explicitly **NET, not gross.** Three components:

- **`delivery_speedup_value`** — the value of work delivered faster, in your own terms (e.g. `engineer_hours_saved × R`). Measure it; do not assume it.
- **`guardrail_overhead_cost`** — the cost of running the governance the speedup depends on. The guard adds roughly **24K governance tokens per feature**, but this is **largely prompt-cached after first load**, so the marginal cost across a feature's iterations is well below 24K × iterations. Convert the effective token volume to cost at your provider's rate.
- **`T_spend`** — your agentic token spend (the input above), subtracted in full.

If `velocity_net` is negative under your inputs, the model is telling you the honest answer: at your current scale the guardrail and token cost exceed the measured speedup. That is a valid outcome of an honest model.

---

## 3. Output

Combine the levers into a 12-month range:

```
total_value = risk_reduction + audit_savings + velocity_net
```

Produce three figures, not one:

| Scenario | How to build it |
|----------|-----------------|
| **Low** | Conservative inputs: smaller avoided-incident delta, lower speedup, full token cost. |
| **Expected** | Your best-estimate inputs. |
| **High** | Optimistic-but-defensible inputs. |

### Sensitivity note

In most adopter profiles the result is dominated by **two or three inputs**:

1. **`C_incident` × `incidents_avoided`** — incident cost and the avoided-incident delta usually swing the total more than anything else; small changes here move the whole range.
2. **`R` and `H_audit`** — the audit lever scales linearly with the loaded rate and the hours actually saved.
3. **`delivery_speedup_value`** — the hardest to measure and the easiest to over-claim; treat it skeptically.

State the value of every dominant input next to the result, and **label every assumption.** A range with unlabeled assumptions is not an honest model.

---

## Worked example (illustration of the method — not a claim about your org)

An UNNAMED regulated, privacy-sensitive enterprise, ~200 engineers. The figures below are **example inputs chosen to demonstrate the worksheet** — they are not measured, not benchmarked, and not a forecast for any real organization.

**Example inputs (all illustrative):**

| Input | Example value |
|-------|---------------|
| `N` | 200 engineers |
| `C_incident` | $25,000 per production incident (assumption) |
| `D` | 400 deploys/month |
| `H_audit` | 240 hours per audit cycle (assumption) |
| `cycles` | 2 per year |
| `R` | $120/hour loaded |
| `T_spend` | $30,000/year agentic spend (assumption) |

**Lever 1 — Risk reduction (illustrative):**
Assume an elevated AI-on-weak-governance incident rate of 1.0 incident per 100 PRs and a guardrailed rate of 0.8 per 100 PRs — a 0.2/100 delta consistent with avoiding part of the +23.5% elevation (assumption). At 400 deploys/month × 12 months = 4,800 PRs:
```
incidents_avoided = 0.002 × 4,800 = 9.6 incidents
risk_reduction    = 9.6 × $25,000 = $240,000
```

**Lever 2 — Audit-evidence time saved (illustrative):**
Assume mechanical evidence cuts `H_audit` by 60% → 144 hours saved per cycle:
```
audit_savings = 144 × 2 × $120 = $34,560
```

**Lever 3 — Agentic velocity, net (illustrative):**
Assume measured speedup is worth $150,000/year. Guardrail overhead: ~24K tokens/feature, largely prompt-cached, across ~600 features/year nets to an effective ~$15,000/year token equivalent (assumption). Subtract `T_spend` in full:
```
velocity_net = $150,000 − $15,000 − $30,000 = $105,000
```

**12-month range (illustrative):**

| Scenario | Total |
|----------|-------|
| **Low** (half the incident delta, no net velocity credit) | ~$155,000 |
| **Expected** (sum of the three levers above) | ~$380,000 |
| **High** (full incident delta + stronger speedup) | ~$520,000 |

**Dominant inputs here:** `C_incident` and the avoided-incident delta (Lever 1) drive most of the range; `delivery_speedup_value` is the largest swing in the high case and the least measurable.

These numbers are illustrative inputs to demonstrate the worksheet; substitute your own.
