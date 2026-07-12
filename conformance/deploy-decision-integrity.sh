#!/bin/sh
exec sh "$(dirname "$0")/decision-integrity.sh" deploy "$@"
