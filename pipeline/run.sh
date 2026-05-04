#!/bin/sh
# Wrapper for the Just Ship pipeline runner.
#
# This wrapper ships into consumer repos as `.pipeline/run.sh` (via setup.sh)
# and delegates to the TypeScript runner. The engine repo itself does NOT
# install a `.pipeline/` copy — there's no Source/Install duplication here
# anymore (T-1064), so no drift-check is needed on either side.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec npx tsx "$SCRIPT_DIR/run.ts" "$@"
