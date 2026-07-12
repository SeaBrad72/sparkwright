#!/bin/sh
# Why this gate: sparkwright explain evals
# artifact-lineage-ready.sh -- kit-self doc-coherence lock for the AI-artifact lineage record
# reference (E11). Asserts templates/AI-ARTIFACT-LINEAGE-TEMPLATE.md still carries its six
# load-bearing fields: the artifact version, the producing model, the prompt/template version,
# the input dataset version, the eval score, and the human sign-off -- the chain that ties a
# produced AI artifact back to the model + prompt + inputs + eval that made it.
#
# SCOPE -- honest ceiling: a green run proves the template is PRESENT and still carries its six
# load-bearing marker phrases (artifact version, model id, prompt/template version, input dataset
# version, eval score, human sign-off) -- it guards the kit's own template against a field being
# silently dropped. The phrases are matched fixed-string anywhere in the file, so it does NOT prove
# those fields are FILLED, nor that any real artifact's stated lineage is accurate (that is the
# signer's responsibility). Kit-self check: N/A outside the kit repo.
#
# Usage:
#   sh conformance/artifact-lineage-ready.sh            (main-path: check the real kit template)
#   sh conformance/artifact-lineage-ready.sh --selftest (fixture anchor + load-bearing negatives)
# Exit: 0 = OK or N/A -- 1 = FAIL (template missing/under-specified). POSIX sh; dash-clean.
set -eu

DOC="${LINEAGE_DOC:-templates/AI-ARTIFACT-LINEAGE-TEMPLATE.md}"

# The lineage record's load-bearing markers (a generic doc lacks these). One per line; the field
# that lost any of them would silently regress to an artifact record that cannot trace its origin.
MARKERS='Artifact version
Model ID + version
Prompt/template version
Input dataset version
Eval score
Human sign-off'

check_doc() {
  d=$1; miss=0
  [ -f "$d" ] || { echo "FAIL: missing AI-artifact lineage template $d"; return 1; }
  # Newline-delimited so a marker may contain spaces; each must be present verbatim.
  # `IFS= read` is command-scoped -- never a global IFS assignment (semgrep: ifs-tampering).
  # Heredoc-fed, NOT piped: the loop stays in this shell, so `miss` survives it.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    # case-insensitive: a heading naturally capitalises the field, but the marker is the phrase.
    grep -qiF -- "$m" "$d" || { echo "FAIL: $d lineage template missing '$m' (artifact can no longer trace its lineage)"; miss=1; }
  done <<MARKERS_EOF
$MARKERS
MARKERS_EOF
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d "${TMPDIR:-/tmp}/artifact-lineage.XXXXXX"); trap 'rm -rf "$d"' EXIT INT TERM
  st=0

  build_fixture() {  # a conformant lineage record; ONE marker per line so each negative isolates
    cat > "$1" <<'MD'
# AI Artifact Lineage Record
Artifact version / hash: the immutable identifier.
Model ID + version: the producing model and its provider.
Prompt/template version: id + version or hash of the prompt used.
Input dataset version(s): dataset id + version of every input source.
Eval score: the score(s) from the eval run, with the metric.
Human sign-off: owner name + date -- the accountable signer.
MD
  }

  run_fixture() { rc=0; LINEAGE_DOC="$1" sh "$0" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
  expect() { got=$(run_fixture "$d/doc.md"); if [ "$got" = "$2" ]; then echo "selftest PASS: $1"; else echo "selftest FAIL: $1 (expected $2, got $got)"; st=1; fi; }
  fresh() { build_fixture "$d/doc.md"; }

  # liveness anchor: fully conformant -> exit 0
  fresh; expect "conformant lineage template -> exit 0" 0

  # one load-bearing negative per marker (drop the line carrying it -> FAIL)
  for m in "Artifact version" "Model ID + version" "Prompt/template version" "Input dataset version" "Eval score" "Human sign-off"; do
    fresh; grep -viF -- "$m" "$d/doc.md" > "$d/doc.md.t" && mv "$d/doc.md.t" "$d/doc.md"
    expect "template missing '$m' -> exit 1" 1
  done

  if [ "$st" -ne 0 ]; then echo "artifact-lineage-ready --selftest: FAIL" >&2; exit 1; fi
  echo "artifact-lineage-ready --selftest: OK (anchor + 6 load-bearing negatives: artifact-version/model-id/prompt-version/input-dataset-version/eval-score/human-sign-off)"
  exit 0
fi

case "${1:-}" in "") : ;; *) echo "usage: artifact-lineage-ready.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self scope: N/A outside the kit repo.
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$DOC" ]; then
  echo "artifact-lineage: N/A -- kit-self check (the AI-artifact lineage template is the kit's own doc; not applicable outside the kit repo)"
  exit 0
fi

if check_doc "$DOC"; then
  echo "artifact-lineage: OK -- AI-artifact lineage template present + carries its six load-bearing marker phrases (artifact version, model id + version, prompt/template version, input dataset version, eval score, human sign-off). NOTE: does NOT prove those fields are filled or that a real artifact's stated lineage is accurate (that is the signer's responsibility)."
  exit 0
fi
echo "FAIL: AI-artifact lineage template under-specified (see reasons above)"
exit 1
