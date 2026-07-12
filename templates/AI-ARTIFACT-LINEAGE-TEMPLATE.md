# AI Artifact Lineage Record

> One record per **produced AI artifact** (a generated dataset, a fine-tuned model, or a
> shipped model output). Ties the artifact back to the model, prompt, inputs, and evaluation
> that produced it, plus its governance links. Pair with the per-*system* `AI-SYSTEM-CARD.md`
> and the `EVAL-PLAN.md` (which describes the tests).
>
> **Honest ceiling:** this record is an attestation. `conformance/artifact-lineage-ready.sh`
> checks it is present and carries its six load-bearing marker phrases — it cannot verify the
> fields are filled or the values accurate. Accuracy is the signer's responsibility (§6).

## 1. Artifact
- **Artifact ID / name:** <e.g. sentiment-classifier, support-summaries-2026-07>
- **Artifact version / hash:** <semver or content hash — the immutable identifier>
- **Type:** <dataset | fine-tuned model | generated output>
- **Produced-at:** <YYYY-MM-DD>

## 2. Producing model
- **Model ID + version:** <e.g. claude-opus-4-8>
- **Provider:** <e.g. Anthropic>

## 3. Prompt / template
- **Prompt/template version:** <id + version or hash of the prompt/template used>

## 4. Inputs
- **Input dataset version(s):** <dataset id + version/hash of every input source>

## 5. Evaluation  *(the quality gate — links EVAL-PLAN + the pinned judge)*
- **Eval-plan reference:** <path/link to EVAL-PLAN.md>
- **Eval score:** <score(s) from the eval run, with the metric>
- **Judge id:** <the judge/model that scored it, e.g. the pinned PINNED_JUDGE_MODEL>

## 6. Governance
- **Linked AI System Card:** <path/link to AI-SYSTEM-CARD.md>
- **Intended use:** <what this artifact is / isn't for>
- **Known limitations:** <bias, coverage gaps, out-of-distribution caveats>
- **Human sign-off:** <owner name + date — the accountable signer attesting the above is accurate>
