#!/bin/bash
# Always rebuild, then run.
cd "$(dirname "$0")" || exit 1
./build.sh "$@" || exit 1
exec ./lazrandr
