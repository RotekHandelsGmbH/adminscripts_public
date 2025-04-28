#!/bin/bash
# ==============================================================================
#  FilteredTreeSync.sh
#
#  🌳 Selective Tree-Based File Synchronization Script
#
#  Author: bitranox
#  Version: 1.6
#  License: MIT
#
# ==============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Emojis
INFO="🔹"
OK="✅"
ERROR="❌"
WARN="⚠️"
COPY="📂"
CHECK="🔍"
DELETE="🗑️"

# Logo
echo -e "${GREEN}"
echo "    🌳  FilteredTreeSync"
echo "      /\\"
echo "     /  \\    Filter + Copy + Preserve Directory Structure"
echo "    /____\\"
echo -e "${NC}"

# Argument Parsing
if [[ $# -lt 3 ]]; then
    echo -e "${RED}$ERROR Usage: $0 <source_directory> <destination_directory> <file_pattern> [--deletesources] [--dry-run] [--autoconfirm]${NC}"
    exit 1
fi

SRC_DIR="$1"
DEST_DIR="$2"
PATTERN="$3"
DELETE_SOURCES=false
DRY_RUN=false
AUTOCONFIRM=false

shift 3
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deletesources)
            DELETE_SOURCES=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --autoconfirm)
            AUTOCONFIRM=true
            ;;
        *)
            echo -e "${RED}$ERROR Unknown option: $1${NC}"
            exit 1
            ;;
    esac
    shift
done

# Detect if file pattern expanded improperly
if [[ ! "$PATTERN" == *"*"* && ! "$PATTERN" == *"?"* && ! "$PATTERN" == *"["* && ! "$PATTERN" == *"]"* ]]; then
    echo -e "${YELLOW}$WARN Warning: File pattern \"$PATTERN\" appears to have been expanded prematurely. Did you forget to quote it?${NC}"
fi

# Show summary
echo -e "\n${CYAN}🔹 Summary:${NC}"
echo -e "${BLUE}  Source Directory:      ${NC}$SRC_DIR"
echo -e "${BLUE}  Destination Directory: ${NC}$DEST_DIR"
echo -e "${BLUE}  File Pattern:           ${NC}\"$PATTERN\""
echo -e "${BLUE}  Dry-run Mode:           ${NC}${DRY_RUN}"
echo -e "${BLUE}  Delete Sources:         ${NC}${DELETE_SOURCES}"
echo -e "${BLUE}  Auto-confirm:           ${NC}${AUTOCONFIRM}"
echo

if [[ "$AUTOCONFIRM" == false ]]; then
    read -n 1 -s -r -p $'\nPress any key to continue...\n'
    echo
else
    echo -e "${BLUE}$INFO Auto-confirm enabled: continuing immediately...${NC}"
fi

# Find files excluding destination
echo -e "${BLUE}$INFO Searching for files matching \"$PATTERN\" in \"$SRC_DIR\"...${NC}"
mapfile -d '' -t FILES < <(find "$SRC_DIR" \( -path "$DEST_DIR" -o -path "$DEST_DIR/*" \) -prune -false -o -type f -iname "$PATTERN" -print0)

TOTAL=${#FILES[@]}
if [[ $TOTAL -eq 0 ]]; then
    echo -e "${YELLOW}$WARN No matching files found.${NC}"
    exit 0
fi

echo -e "${GREEN}$OK Found $TOTAL files.${NC}"
echo

# Progress Bar
BAR_WIDTH=50

draw_progress_bar() {
    local progress=$1
    local total=$2
    local width=$3

    if [[ $total -eq 0 ]]; then
        percent=100
        filled=$width
        empty=0
    else
        percent=$(( progress * 100 / total ))
        filled=$(( progress * width / total ))
        empty=$(( width - filled ))
    fi

    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %d%% (%d/%d)" "$percent" "$progress" "$total"
}

export -f draw_progress_bar

# --- Copy Files ---
echo -e "${CYAN}$COPY Starting ${DRY_RUN:+(dry-run) }copy...${NC}"

COPIED=0
export SRC_DIR DEST_DIR DRY_RUN TOTAL COPIED BAR_WIDTH

copy_file() {
    local FILE="$1"
    local REL_PATH="${FILE#$SRC_DIR/}"
    local DEST_FILE="$DEST_DIR/$REL_PATH"

    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$(dirname "$DEST_FILE")"
        cp "$FILE" "$DEST_FILE"
    else
        echo -e "${YELLOW}Would copy:${NC} $REL_PATH"
    fi

    ((COPIED++))
    draw_progress_bar "$COPIED" "$TOTAL" "$BAR_WIDTH"
}

export -f copy_file

printf "%s\0" "${FILES[@]}" | xargs -0 -n 1 -P 4 bash -c 'copy_file "$0"'

echo
echo -e "${GREEN}$OK Copying complete.${NC}"
echo

# --- Verify Files ---
echo -e "${CYAN}$CHECK Verifying copied files...${NC}"

VERIFIED=0
ERRORS=0
export VERIFIED ERRORS

verify_file() {
    local FILE="$1"
    local REL_PATH="${FILE#$SRC_DIR/}"
    local DEST_FILE="$DEST_DIR/$REL_PATH"

    if [[ "$DRY_RUN" == false ]]; then
        if ! cmp -s "$FILE" "$DEST_FILE"; then
            echo -e "${RED}$ERROR File mismatch: $REL_PATH${NC}"
            ((ERRORS++))
        fi
    else
        echo -e "${YELLOW}Would verify:${NC} $REL_PATH"
    fi

    ((VERIFIED++))
    draw_progress_bar "$VERIFIED" "$TOTAL" "$BAR_WIDTH"
}

export -f verify_file

printf "%s\0" "${FILES[@]}" | xargs -0 -n 1 -P 4 bash -c 'verify_file "$0"'

echo

# --- Deletion Logic ---
if [[ "$DRY_RUN" == false ]]; then
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}$OK Verification successful: All files copied correctly.${NC}"

        if [[ "$DELETE_SOURCES" == true ]]; then
            echo -e "${RED}$DELETE Deleting source files...${NC}"
            for FILE in "${FILES[@]}"; do
                if [[ "$FILE" != "$DEST_DIR"* ]]; then
                    rm -f "$FILE"
                fi
            done
            echo -e "${GREEN}$OK Source files deleted successfully.${NC}"
        fi
    else
        echo -e "${RED}$ERROR Verification failed: $ERRORS file(s) mismatched.${NC}"
        echo -e "${YELLOW}$WARN Skipping deletion of source files.${NC}"
    fi
else
    if [[ "$DELETE_SOURCES" == true ]]; then
        echo -e "${YELLOW}$WARN Would delete the following files after successful verification:${NC}"
        for FILE in "${FILES[@]}"; do
            if [[ "$FILE" != "$DEST_DIR"* ]]; then
                echo -e "${YELLOW}Would delete:${NC} $FILE"
            fi
        done
        echo
        echo -e "${BLUE}$INFO Dry-run completed: no files were copied; source files would have been deleted.${NC}"
    else
        echo
        echo -e "${BLUE}$INFO Dry-run completed: no files were copied or deleted.${NC}"
    fi
fi

echo
echo -e "${GREEN}$OK Done.${NC}"
