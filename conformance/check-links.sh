#!/bin/sh
# check-links.sh — assert every relative Markdown link in the kit's distributable
# docs points to a TRACKED file (one that exists in a fresh `git clone`, not merely
# on the local disk). Resolving against the tracked set — `git ls-files`, not a
# filesystem `[ -e ]` test — is deliberate: an untracked-but-on-disk target (e.g. a
# gitignored file) would otherwise false-pass locally and ship as a dead link
# publicly. Ignores http(s)/mailto/pure-anchor links. Scans every tracked Markdown
# file — no directory is excluded from validation.
#
# Link EXTRACTION skips Markdown code — fenced blocks (``` / ~~~) and inline code
# spans (`...`) — so prose that merely *quotes* link syntax (e.g. documenting the
# `]( )` form inside backticks) is not mistaken for a real link. A link inside code is
# not rendered as a link, so it can never be a dead link for a reader; ignoring it is
# correctness, not a loophole. Conservative by design: rare nested-fence / mismatched-fence
# shapes may OVER-extract vs a strict CommonMark renderer — fail-safe (a possible false-flag,
# never a missed real link; verified against `marked`).
# Usage: sh conformance/check-links.sh [--selftest]   (run from repo root)
set -eu

# extract_links <file>: print each relative-link target, with code regions removed first.
extract_links() {
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }   # toggle on a fence line; drop the fence line
    fence { next }                                       # drop everything inside a fenced block
    { gsub(/`[^`]*`/, ""); print }                       # drop inline `code` spans, keep the rest
  ' "$1" | grep -oE ']\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//'
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  printf 'see [x](real-target.md) here\n' > "$d/a.md"
  extract_links "$d/a.md" | grep -q '^real-target.md$' || { echo "FAIL: selftest — real link not extracted"; sf=1; }
  printf 'the `](codespan-target.md)` link form\n' > "$d/b.md"
  if extract_links "$d/b.md" | grep -q 'codespan-target'; then echo "FAIL: selftest — code-span link wrongly extracted"; sf=1; fi
  printf '```\n[x](fenced-target.md)\n```\n' > "$d/c.md"
  if extract_links "$d/c.md" | grep -q 'fenced-target'; then echo "FAIL: selftest — fenced link wrongly extracted"; sf=1; fi
  printf '```\ncode\n```\nthen [y](after-fence.md) too\n' > "$d/e.md"
  extract_links "$d/e.md" | grep -q '^after-fence.md$' || { echo "FAIL: selftest — link after a closed fence not extracted (fence state must reset)"; sf=1; }
  printf 'inline `code` then a real [z](mixed-target.md) link\n' > "$d/g.md"
  extract_links "$d/g.md" | grep -q '^mixed-target.md$' || { echo "FAIL: selftest — real link on a line with a code span not extracted"; sf=1; }
  if [ "$sf" = 0 ]; then echo "OK: check-links selftest (code spans + fences skipped; real links still extracted)"; exit 0; fi
  echo "FAIL: check-links selftest"; exit 1
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: check-links.sh [--selftest]" >&2; exit 2 ;;
esac

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

git ls-files '*.md' | while IFS= read -r f; do
  dir=$(dirname "$f")
  extract_links "$f" | while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    target=$(printf '%s' "$link" | sed -E 's/[#?].*$//')
    [ -z "$target" ] && continue
    case "$target" in
      /*) resolved=".${target}" ;;
      *)  resolved="${dir}/${target}" ;;
    esac
    # Tracked-set test (NOT [ -e ]): matches a tracked file, or a directory that
    # contains tracked files. git normalizes ./ and ../ in the pathspec.
    [ -n "$(git ls-files -- "$resolved" 2>/dev/null)" ] || echo "BROKEN: $f: $link -> $resolved" >> "$tmp"
  done
done

if [ -s "$tmp" ]; then
  echo "FAIL: broken relative Markdown links:" >&2
  cat "$tmp" >&2
  exit 1
fi
echo "OK: all relative Markdown links resolve"
exit 0
