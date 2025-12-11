#!/bin/bash
#
# quick_wipe.sh - Fast secure wipe for Android phones
# 3 passes x 1GB chunks, ~15 minutes
# Good for most trade-in scenarios
#
# Version: 2.2.0
# Repository: https://github.com/OnlyParams/android-secure-wipe
#
# CHANGELOG:
# ----------
# v2.2.0 (2024-12-11)
#   - Added input validation for --passes (must be 1-20) and --size (64-10240 MB)
#   - Rejects non-numeric values with clear error messages
#   - Added --dry-run flag for consistency with full_wipe.sh
#   - Improved WIPE_DIR quoting in cleanup for safety
#   - Better error messages for novice users
#
# v2.1.0 (2024-12-11)
#   - Added explicit device targeting with adb -s to prevent wrong-device errors
#   - Added --yes/-y flag to skip confirmation prompt (for automation)
#   - Added space verification before write (ensures available >= requested size)
#
# v2.0.0 (2024-12-11)
#   - Rewrote to run wipe loop on-device in single adb shell session
#   - Added set -euo pipefail for safer execution
#   - Added trap handler for cleanup on interrupt
#   - Added --passes and --size options
#   - Added --version and --help flags
#
# v1.0.0 (2024-12-11)
#   - Initial release
#   - Per-pass adb shell calls
#   - Basic progress output
#

set -euo pipefail

VERSION="2.2.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration defaults
PASSES=3
CHUNK_SIZE_MB=1024  # 1GB per pass
WIPE_DIR="/sdcard/wipe_temp"
AUTO_YES=false
DRY_RUN=false
MIN_SPACE_MB=100    # Minimum required space in MB

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --passes)
            PASSES="$2"
            shift 2
            ;;
        --size)
            CHUNK_SIZE_MB="$2"
            shift 2
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --version|-v)
            echo "quick_wipe.sh version $VERSION"
            exit 0
            ;;
        --help|-h)
            echo "Usage: quick_wipe.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --passes N    Number of overwrite passes (default: 3, max: 20)"
            echo "  --size MB     Size in MB to write per pass (default: 1024, range: 64-10240)"
            echo "  --dry-run     Show what would be done without writing any data"
            echo "  --yes, -y     Skip confirmation prompt (for automation)"
            echo "  --version     Show version number"
            echo "  --help        Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./quick_wipe.sh                    # Default: 3 passes x 1GB"
            echo "  ./quick_wipe.sh --passes 5        # 5 passes x 1GB"
            echo "  ./quick_wipe.sh --size 512        # 3 passes x 512MB (faster)"
            echo "  ./quick_wipe.sh --dry-run         # See what would happen"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Input Validation
# =============================================================================

# Validate PASSES is a number between 1 and 20
if ! [[ "$PASSES" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: --passes must be a number${NC}"
    echo "Example: --passes 3"
    exit 1
fi

if [ "$PASSES" -lt 1 ] || [ "$PASSES" -gt 20 ]; then
    echo -e "${RED}Error: --passes must be between 1 and 20${NC}"
    echo "You specified: $PASSES"
    echo ""
    echo "Recommended values:"
    echo "  - 1-3 passes: Good for most trade-ins"
    echo "  - 3-5 passes: Extra cautious"
    echo "  - More than 5: Diminishing returns, much longer time"
    exit 1
fi

# Validate CHUNK_SIZE_MB is a number between 64 and 10240 (64MB to 10GB)
if ! [[ "$CHUNK_SIZE_MB" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: --size must be a number (in megabytes)${NC}"
    echo "Example: --size 1024  (for 1GB per pass)"
    exit 1
fi

if [ "$CHUNK_SIZE_MB" -lt 64 ] || [ "$CHUNK_SIZE_MB" -gt 10240 ]; then
    echo -e "${RED}Error: --size must be between 64 and 10240 MB${NC}"
    echo "You specified: ${CHUNK_SIZE_MB}MB"
    echo ""
    echo "Recommended values:"
    echo "  - 512 MB:  Quick test (~8 min for 3 passes)"
    echo "  - 1024 MB: Default, good balance (~15 min for 3 passes)"
    echo "  - 2048 MB: More thorough (~30 min for 3 passes)"
    exit 1
fi

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ -n "${DEVICE:-}" ]; then
        echo ""
        echo -e "${YELLOW}Interrupted! Cleaning up...${NC}"
        adb -s "$DEVICE" shell "rm -rf \"$WIPE_DIR\"" 2>/dev/null || true
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Parse storage size with unit suffix (handles decimals like "1.2G")
parse_size_to_mb() {
    local size_str="$1"
    local value suffix mb

    value=$(echo "$size_str" | sed -E 's/([0-9.]+).*/\1/')
    suffix=$(echo "$size_str" | sed -E 's/[0-9.]+(.*)/\1/' | tr '[:lower:]' '[:upper:]')

    case "$suffix" in
        G|GB) mb=$(awk "BEGIN {printf \"%.0f\", $value * 1024}") ;;
        M|MB) mb=$(awk "BEGIN {printf \"%.0f\", $value}") ;;
        K|KB) mb=$(awk "BEGIN {printf \"%.0f\", $value / 1024}") ;;
        *)    mb=$(awk "BEGIN {printf \"%.0f\", $value / 1024}") ;;
    esac

    echo "$mb"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android Quick Secure Wipe v${VERSION}${NC}"
echo -e "${BLUE}  ${PASSES} passes x ${CHUNK_SIZE_MB}MB${NC}"
echo -e "${BLUE}========================================${NC}"
echo

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}*** DRY RUN MODE - No data will be written ***${NC}"
    echo
fi

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Error: adb is not installed or not in PATH${NC}"
    echo ""
    echo "Install ADB first:"
    echo "  Linux:   sudo apt install adb"
    echo "  macOS:   brew install android-platform-tools"
    echo "  Windows: Download from developer.android.com/studio/releases/platform-tools"
    exit 1
fi

# Check for connected device
echo -e "${YELLOW}Checking for connected device...${NC}"
DEVICE=$(adb devices | grep -v "List" | grep "device$" | head -1 | cut -f1)

if [ -z "$DEVICE" ]; then
    echo -e "${RED}Error: No authorized device found${NC}"
    echo ""
    echo "Checklist:"
    echo "  1. Is your phone connected via USB cable?"
    echo "  2. Is USB debugging enabled? (Settings -> Developer Options -> USB Debugging)"
    echo "  3. Did you tap 'Allow' on the phone when it asked to trust this computer?"
    echo ""
    echo "Still stuck? Run 'adb devices' to see what's detected."
    exit 1
fi

echo -e "${GREEN}Found device: $DEVICE${NC}"

# From here on, use adb -s "$DEVICE" for all commands to ensure correct device targeting

# Check available space
echo -e "${YELLOW}Checking available storage...${NC}"
STORAGE_LINE=$(adb -s "$DEVICE" shell "df -h /sdcard 2>/dev/null | tail -1" | tr -d '\r')
AVAILABLE_STR=$(echo "$STORAGE_LINE" | awk '{print $4}')
AVAILABLE_MB=$(parse_size_to_mb "$AVAILABLE_STR")

# Verify we have enough space
if [ "$AVAILABLE_MB" -lt "$CHUNK_SIZE_MB" ]; then
    echo -e "${RED}Error: Not enough storage space${NC}"
    echo "  Available: ${AVAILABLE_MB}MB"
    echo "  Requested: ${CHUNK_SIZE_MB}MB per pass"
    echo ""
    echo "Solutions:"
    echo "  - Use a smaller --size (e.g., --size 512)"
    echo "  - Free up space on the device first"
    exit 1
fi

if [ "$AVAILABLE_MB" -lt "$MIN_SPACE_MB" ]; then
    echo -e "${RED}Error: Storage space critically low (${AVAILABLE_MB}MB)${NC}"
    exit 1
fi

echo -e "${GREEN}Available: ${AVAILABLE_MB}MB${NC}"
echo

# Confirm before proceeding
TOTAL_MB=$((CHUNK_SIZE_MB * PASSES))
echo -e "${YELLOW}This will write ${CHUNK_SIZE_MB}MB of random data ${PASSES} times.${NC}"
echo -e "${YELLOW}Total: ${TOTAL_MB}MB (~$((TOTAL_MB / 1024))GB)${NC}"
echo -e "${YELLOW}Estimated time: ~$((TOTAL_MB / 60)) minutes${NC}"
echo

if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}Dry run complete. No data was written.${NC}"
    echo ""
    echo "To actually run the wipe, remove the --dry-run flag."
    exit 0
fi

if [ "$AUTO_YES" = true ]; then
    echo -e "${GREEN}Auto-confirmed via --yes flag${NC}"
else
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo
echo -e "${BLUE}Starting quick wipe (runs on-device for speed)...${NC}"
START_TIME=$(date +%s)

# Run entire wipe on-device in single adb shell session
adb -s "$DEVICE" shell "$(cat <<REMOTE_SCRIPT
#!/system/bin/sh
WIPE_DIR="$WIPE_DIR"
PASSES=$PASSES
CHUNK_SIZE_MB=$CHUNK_SIZE_MB

mkdir -p "\$WIPE_DIR"

for pass in \$(seq 1 \$PASSES); do
    echo "=== PASS \$pass of \$PASSES ==="
    FILENAME="\$WIPE_DIR/wipe_pass_\${pass}.bin"

    echo "Writing \${CHUNK_SIZE_MB}MB of random data..."
    dd if=/dev/urandom of="\$FILENAME" bs=1048576 count=\$CHUNK_SIZE_MB 2>&1 | grep -v records || true

    echo "Syncing..."
    sync

    echo "Deleting pass \$pass data..."
    rm -f "\$FILENAME"
    sync

    echo "PASS_DONE: \$pass"
done

rm -rf "\$WIPE_DIR"
sync
echo "COMPLETE"
REMOTE_SCRIPT
)" 2>&1 | while IFS= read -r line; do
    case "$line" in
        "=== PASS"*)
            echo ""
            echo -e "${BLUE}$line${NC}"
            ;;
        "Writing"*|"Syncing"*|"Deleting"*)
            echo -e "  ${YELLOW}$line${NC}"
            ;;
        "PASS_DONE:"*)
            pass_num="${line#PASS_DONE: }"
            echo -e "  ${GREEN}Pass $pass_num complete${NC}"
            ;;
        "COMPLETE")
            echo ""
            ;;
        *)
            [ -n "$line" ] && echo "  $line"
            ;;
    esac
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_DURATION / 60))
SECS=$((TOTAL_DURATION % 60))

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Quick Wipe Complete!${NC}"
echo -e "${GREEN}  Total time: ${MINUTES}m ${SECS}s${NC}"
echo -e "${GREEN}  Passes completed: $PASSES${NC}"
echo -e "${GREEN}  Data written: ${TOTAL_MB}MB${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}Recommended next steps:${NC}"
echo "  1. Perform a factory reset from Settings"
echo "  2. Power off the phone"
echo "  3. Remove SIM and SD cards"
echo "  4. Phone is ready for trade-in"
