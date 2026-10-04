#!/bin/sh
# T3b fixture (S-4b): a logging wrapper standing in for scripts/tracker-conf.sh inside a fake
# tree — proves tracker-contract.sh's --selftest F4(b) DRY leg that the contract reads the conf
# THROUGH tracker-conf.sh (calling it with `get base_url`), never re-parsing the grammar itself.
# The caller exports FA_CONFLOG (a fixed path under its own $tmpd) before invoking the fake tree
# whose scripts/tracker-conf.sh IS this file; the REAL parser must be copied beside it, in the
# same directory, as tracker-conf.sh.real.
printf '%s\n' "$*" >> "$FA_CONFLOG"
# shellcheck disable=SC1007  # CDPATH= intentionally clears CDPATH to avoid cd side-effects
_fcl_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$_fcl_dir/tracker-conf.sh.real" "$@"
