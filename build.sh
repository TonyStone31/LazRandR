#!/bin/bash
# Build LazRandR with the fpcupdeluxe Lazarus/FPC trunk installation.
#
# The widgetset is pinned to gtk3: it is the only one compiled in this
# Lazarus install, and it is what the project's LFMs are laid out against.

set -u

LAZ_ROOT="/media/tony/storpart/fpctrunklaztrunk"
LAZARUS_DIR="$LAZ_ROOT/lazarus"
PCP_DIR="$LAZ_ROOT/config_lazarus"
PROJECT_FILE="lazrandr.lpi"
EXECUTABLE="lazrandr"
WIDGETSET="gtk3"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

CLEAN=0
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        --clean)   CLEAN=1 ;;
        --verbose) VERBOSE=1 ;;
        --help)
            echo "Usage: ./build.sh [--clean] [--verbose]"
            echo "  --clean    remove lib/ and the binary before building"
            echo "  --verbose  show the full compiler log instead of a summary"
            exit 0 ;;
        *) echo -e "${RED}Unknown option: $arg${NC}"; exit 1 ;;
    esac
done

cd "$(dirname "$0")" || exit 1

echo -e "${BLUE}=== Building LazRandR (${WIDGETSET}) ===${NC}"

if [ ! -x "$LAZARUS_DIR/lazbuild" ]; then
    echo -e "${RED}lazbuild not found at $LAZARUS_DIR/lazbuild${NC}"
    exit 1
fi
if [ ! -f "$PROJECT_FILE" ]; then
    echo -e "${RED}Project file $PROJECT_FILE not found${NC}"
    exit 1
fi

if [ "$CLEAN" = "1" ]; then
    echo -e "${YELLOW}Cleaning...${NC}"
    rm -rf lib/
    rm -f "$EXECUTABLE"
fi

# lazbuild keys recompilation off the .pas timestamp alone. Edit a form in the
# designer and only the .lfm changes, so the stale .ppu -- with the OLD form
# resource still baked in -- gets relinked and the change silently vanishes.
# Touch the .pas whenever its .lfm is newer so the unit actually rebuilds.
for lfm in *.lfm; do
    [ -e "$lfm" ] || continue
    pas="${lfm%.lfm}.pas"
    if [ -f "$pas" ] && [ "$lfm" -nt "$pas" ]; then
        echo -e "${YELLOW}  $lfm changed -> forcing rebuild of $pas${NC}"
        touch "$pas"
    fi
done

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

"$LAZARUS_DIR/lazbuild" \
    --pcp="$PCP_DIR" \
    --ws="$WIDGETSET" \
    "$PROJECT_FILE" >"$LOG" 2>&1
RESULT=$?

if [ "$VERBOSE" = "1" ]; then
    cat "$LOG"
else
    # Errors and warnings are what matter; hints are noise at this volume.
    grep -E "Error|Fatal|Warning|Linking|lines compiled" "$LOG" || true
fi

if [ $RESULT -ne 0 ]; then
    echo -e "${RED}=== Build FAILED ===${NC}"
    [ "$VERBOSE" = "0" ] && echo "Re-run with --verbose for the full log."
    exit $RESULT
fi

if [ ! -f "$EXECUTABLE" ]; then
    echo -e "${RED}Build reported success but $EXECUTABLE is missing${NC}"
    exit 1
fi

SIZE=$(du -h "$EXECUTABLE" | cut -f1)
LINKED=$(ldd "$EXECUTABLE" 2>/dev/null | grep -o 'libgtk-[0-9x.-]*so[0-9.]*' | head -1)

echo -e "${GREEN}=== Build OK ===${NC}"
echo -e "  binary:    ${GREEN}./$EXECUTABLE${NC} ($SIZE)"
echo -e "  widgetset: ${GREEN}${WIDGETSET}${NC}${LINKED:+  (linked: $LINKED)}"
echo -e "  run with:  ${YELLOW}./run.sh${NC}"
