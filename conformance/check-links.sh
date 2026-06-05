#!/bin/sh
# check-links.sh — assert every relative Markdown link in the kit's distributable
# docs points to a file that exists. Ignores http(s)/mailto/pure-anchor links and
# the process artifacts under docs/superpowers/ (specs/plans embed example links).
# Usage: sh conformance/check-links.sh   (run from repo root)
set -eu

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

git ls-files '*.md' | grep -v '^docs/superpowers/' | while IFS= read -r f; do
  dir=$(dirname "$f")
  grep -oE ']\([^)]+\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    target=$(printf '%s' "$link" | sed -E 's/[#?].*$//')
    [ -z "$target" ] && continue
    case "$target" in
      /*) resolved=".${target}" ;;
      *)  resolved="${dir}/${target}" ;;
    esac
    [ -e "$resolved" ] || echo "BROKEN: $f: $link -> $resolved" >> "$tmp"
  done
done

if [ -s "$tmp" ]; then
  echo "FAIL: broken relative Markdown links:" >&2
  cat "$tmp" >&2
  exit 1
fi
echo "OK: all relative Markdown links resolve"
exit 0
