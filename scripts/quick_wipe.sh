#!/bin/bash
#
# quick_wipe.sh - Fast secure wipe for Android phones
# 3 passes x 1GB chunks, ~15 minutes
# Good for most trade-in scenarios
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PASSES=3
CHUNK_SIZE_MB=1024  # 1GB per pass
WIPE_DIR="/sdcard/wipe_temp"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android Quick Secure Wipe${NC}"
echo -e "${BLUE}  3 passes x 1GB (~15 minutes)${NC}"
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

# Create temp directory on phone
echo -e "${YELLOW}Creating temp directory...${NC}"
adb shell "mkdir -p $WIPE_DIR" 2>/dev/null || true

# Get available space
AVAILABLE_KB=$(adb shell "df /sdcard" | tail -1 | awk '{print $4}' | tr -d 'K')
AVAILABLE_MB=$((AVAILABLE_KB / 1024))
echo -e "${BLUE}Available space: ${AVAILABLE_MB}MB${NC}"
echo

# Confirm before proceeding
echo -e "${YELLOW}This will write ${CHUNK_SIZE_MB}MB of random data ${PASSES} times.${NC}"
echo -e "${YELLOW}Estimated time: ~15 minutes${NC}"
echo
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo
START_TIME=$(date +%s)

# Run wipe passes
for pass in $(seq 1 $PASSES); do
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Pass $pass of $PASSES${NC}"
    echo -e "${BLUE}========================================${NC}"

    PASS_START=$(date +%s)
    FILENAME="$WIPE_DIR/wipe_pass_${pass}.bin"

    echo -e "${YELLOW}Writing ${CHUNK_SIZE_MB}MB of random data...${NC}"

    # Write random data using dd via adb shell
    # Using /dev/urandom for random data
    adb shell "dd if=/dev/urandom of=$FILENAME bs=1048576 count=$CHUNK_SIZE_MB 2>&1" | while read line; do
        # Show progress dots
        echo -n "."
    done
    echo

    # Sync to ensure data is written to flash
    echo -e "${YELLOW}Syncing to storage...${NC}"
    adb shell "sync"

    # Delete the file
    echo -e "${YELLOW}Deleting pass $pass data...${NC}"
    adb shell "rm -f $FILENAME"
    adb shell "sync"

    PASS_END=$(date +%s)
    PASS_DURATION=$((PASS_END - PASS_START))
    echo -e "${GREEN}Pass $pass complete (${PASS_DURATION}s)${NC}"
    echo
done

# Cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
adb shell "rm -rf $WIPE_DIR" 2>/dev/null || true
adb shell "sync"

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_DURATION / 60))
SECONDS=$((TOTAL_DURATION % 60))

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Quick Wipe Complete!${NC}"
echo -e "${GREEN}  Total time: ${MINUTES}m ${SECONDS}s${NC}"
echo -e "${GREEN}  Passes completed: $PASSES${NC}"
echo -e "${GREEN}  Data written: $((CHUNK_SIZE_MB * PASSES))MB${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}Recommended next steps:${NC}"
echo "  1. Perform a factory reset from Settings"
echo "  2. Power off the phone"
echo "  3. Remove SIM and SD cards"
echo "  4. Phone is ready for trade-in"
