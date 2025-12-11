#!/bin/bash
#
# quick_wipe.sh - Fast secure wipe for Android phones
# 3 passes x 1GB chunks, ~15 minutes
# Good for most trade-in scenarios
#
# Version: 2.0.0
# Repository: https://github.com/OnlyParams/android-secure-wipe
#
# CHANGELOG:
# ----------
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

VERSION="2.0.0"

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
        --version|-v)
            echo "quick_wipe.sh version $VERSION"
            exit 0
            ;;
        --help|-h)
            echo "Usage: quick_wipe.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --passes N    Number of overwrite passes (default: 3)"
            echo "  --size MB     Size in MB to write per pass (default: 1024)"
            echo "  --version     Show version number"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Interrupted! Cleaning up...${NC}"
        adb shell "rm -rf $WIPE_DIR" 2>/dev/null || true
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android Quick Secure Wipe v${VERSION}${NC}"
echo -e "${BLUE}  ${PASSES} passes x ${CHUNK_SIZE_MB}MB${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Error: adb is not installed or not in PATH${NC}"
    echo "Install with:"
    echo "  Linux: sudo apt install adb"
    echo "  macOS: brew install android-platform-tools"
    echo "  Windows: Download Android SDK Platform Tools"
    exit 1
fi

# Check for connected device
echo -e "${YELLOW}Checking for connected device...${NC}"
DEVICE=$(adb devices | grep -v "List" | grep "device$" | head -1 | cut -f1)

if [ -z "$DEVICE" ]; then
    echo -e "${RED}Error: No authorized device found${NC}"
    echo "Make sure:"
    echo "  1. Phone is connected via USB"
    echo "  2. USB debugging is enabled"
    echo "  3. You've authorized this computer on the phone"
    echo
    echo "Run 'adb devices' to check connection status"
    exit 1
fi

echo -e "${GREEN}Found device: $DEVICE${NC}"
echo

# Confirm before proceeding
TOTAL_MB=$((CHUNK_SIZE_MB * PASSES))
echo -e "${YELLOW}This will write ${CHUNK_SIZE_MB}MB of random data ${PASSES} times.${NC}"
echo -e "${YELLOW}Total: ${TOTAL_MB}MB (~$((TOTAL_MB / 1024))GB)${NC}"
echo -e "${YELLOW}Estimated time: ~$((TOTAL_MB / 60)) minutes${NC}"
echo
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo
echo -e "${BLUE}Starting quick wipe (runs on-device for speed)...${NC}"
START_TIME=$(date +%s)

# Run entire wipe on-device in single adb shell session
adb shell "$(cat <<REMOTE_SCRIPT
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
