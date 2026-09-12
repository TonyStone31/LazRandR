#!/bin/bash
# Build if needed, then run LazRandR.
cd "$(dirname "$0")" || exit 1
[ -x ./lazrandr ] || ./build.sh || exit 1
exec ./lazrandr "$@"
