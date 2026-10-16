#!/bin/sh
# SWAS-196 fixture: a stand-in store binary for the preflight identity legs (never the real Keychain). The selftest builds a
# copy of the credential library whose store path is THIS file's copy. It answers the attribute-only lookup with the account
# named in the sibling file `present`, or with rc 44 (no item) when that file is absent. It never answers a secret request.
d=${0%/*}
for a in "$@"; do
  if [ "$a" = "-w" ]; then exit 44; fi
done
[ -f "$d/present" ] || exit 44
printf '    "acct"\074blob\076="%s"\n' "$(cat "$d/present")"
exit 0
