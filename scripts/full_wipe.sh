#!/bin/bash
#
# full_wipe.sh - Thorough secure wipe for Android phones
# Dynamic storage detection, 3 passes x full storage
# Includes logging, progress tracking, and desktop notification
# Runtime: 1-2+ hours depending on storage size
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PASSES=3
WIPE_DIR="/sdcard/wipe_temp"
LOG_FILE="phone_wipe.log"
CHUNK_SIZE_MB=512  # Write in 512MB chunks for progress tracking
FILL_PERCENT=95    # Fill to 95% to avoid running out of space

# Initialize log file
echo "=== Android Full Secure Wipe Log ===" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

log() {
    echo "$1"
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

log_only() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

# Send desktop notification (cross-platform)
notify() {
    local title="$1"
    local message="$2"

    # Linux (notify-send)
    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$message" 2>/dev/null || true
    fi

    # macOS (osascript)
    if command -v osascript &> /dev/null; then
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    fi

    # Windows (PowerShell) - only works in certain terminals
    if command -v powershell.exe &> /dev/null; then
        powershell.exe -Command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); [System.Windows.Forms.MessageBox]::Show('$message','$title')" 2>/dev/null || true
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android Full Secure Wipe${NC}"
echo -e "${BLUE}  Multi-pass thorough overwrite${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    log "${RED}Error: adb is not installed or not in PATH${NC}"
    echo "Install with:"
    echo "  Linux: sudo apt install adb"
    echo "  macOS: brew install android-platform-tools"
    echo "  Windows: Download Android SDK Platform Tools"
    exit 1
fi

# Check for connected device
log "Checking for connected device..."
DEVICE=$(adb devices | grep -v "List" | grep "device$" | head -1 | cut -f1)

if [ -z "$DEVICE" ]; then
    log "${RED}Error: No authorized device found${NC}"
    echo "Make sure:"
    echo "  1. Phone is connected via USB"
    echo "  2. USB debugging is enabled"
    echo "  3. You've authorized this computer on the phone"
    echo
    echo "Run 'adb devices' to check connection status"
    exit 1
fi

log "${GREEN}Found device: $DEVICE${NC}"
log_only "Device ID: $DEVICE"

# Get device model
MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
log "Device model: $MODEL"
log_only "Model: $MODEL"
echo

# Create temp directory on phone
log "Creating temp directory..."
adb shell "mkdir -p $WIPE_DIR" 2>/dev/null || true

# Get storage information
log "Analyzing storage..."
STORAGE_INFO=$(adb shell "df /sdcard" | tail -1)
TOTAL_KB=$(echo "$STORAGE_INFO" | awk '{print $2}' | tr -d 'KMG')
AVAILABLE_KB=$(echo "$STORAGE_INFO" | awk '{print $4}' | tr -d 'KMG')

# Handle different df output formats
if echo "$STORAGE_INFO" | grep -q "G"; then
    # Gigabytes
    TOTAL_GB=$(echo "$STORAGE_INFO" | awk '{print $2}' | tr -d 'G')
    AVAILABLE_GB=$(echo "$STORAGE_INFO" | awk '{print $4}' | tr -d 'G')
    TOTAL_MB=$((TOTAL_GB * 1024))
    AVAILABLE_MB=$((AVAILABLE_GB * 1024))
elif echo "$STORAGE_INFO" | grep -q "M"; then
    # Megabytes
    TOTAL_MB=$(echo "$STORAGE_INFO" | awk '{print $2}' | tr -d 'M')
    AVAILABLE_MB=$(echo "$STORAGE_INFO" | awk '{print $4}' | tr -d 'M')
else
    # Kilobytes (default)
    TOTAL_MB=$((TOTAL_KB / 1024))
    AVAILABLE_MB=$((AVAILABLE_KB / 1024))
fi

# Calculate target fill size (95% of available)
TARGET_MB=$((AVAILABLE_MB * FILL_PERCENT / 100))
NUM_CHUNKS=$((TARGET_MB / CHUNK_SIZE_MB))

echo -e "${CYAN}Storage Analysis:${NC}"
echo -e "  Total storage: ~$((TOTAL_MB / 1024))GB"
echo -e "  Available: ~$((AVAILABLE_MB / 1024))GB (${AVAILABLE_MB}MB)"
echo -e "  Target fill: ~$((TARGET_MB / 1024))GB (${TARGET_MB}MB)"
echo -e "  Chunks per pass: $NUM_CHUNKS x ${CHUNK_SIZE_MB}MB"
echo

log_only "Total: ${TOTAL_MB}MB, Available: ${AVAILABLE_MB}MB, Target: ${TARGET_MB}MB"

# Estimate time
ESTIMATED_MINUTES=$((TARGET_MB * PASSES / 50 / 60))  # Rough estimate: 50MB/s write speed
echo -e "${YELLOW}Estimated time: ${ESTIMATED_MINUTES}+ minutes (varies by device)${NC}"
echo

# Confirm before proceeding
echo -e "${YELLOW}This will fill the storage with random data ${PASSES} times.${NC}"
echo -e "${YELLOW}Total data to write: ~$((TARGET_MB * PASSES / 1024))GB${NC}"
echo
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Aborted by user."
    exit 0
fi

echo
log "Starting full secure wipe..."
START_TIME=$(date +%s)

# Progress bar function
progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

# Run wipe passes
for pass in $(seq 1 $PASSES); do
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Pass $pass of $PASSES${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_only "Starting pass $pass of $PASSES"

    PASS_START=$(date +%s)
    PASS_DIR="$WIPE_DIR/pass_${pass}"

    # Create pass directory
    adb shell "mkdir -p $PASS_DIR"

    echo -e "${YELLOW}Writing ${TARGET_MB}MB of random data in ${CHUNK_SIZE_MB}MB chunks...${NC}"

    WRITTEN_MB=0
    CHUNK_NUM=0

    while [ $WRITTEN_MB -lt $TARGET_MB ]; do
        CHUNK_NUM=$((CHUNK_NUM + 1))
        FILENAME="$PASS_DIR/chunk_${CHUNK_NUM}.bin"

        # Calculate remaining space to avoid overfilling
        REMAINING=$((TARGET_MB - WRITTEN_MB))
        if [ $REMAINING -lt $CHUNK_SIZE_MB ]; then
            CURRENT_CHUNK=$REMAINING
        else
            CURRENT_CHUNK=$CHUNK_SIZE_MB
        fi

        # Write chunk
        adb shell "dd if=/dev/urandom of=$FILENAME bs=1048576 count=$CURRENT_CHUNK 2>/dev/null" 2>/dev/null

        WRITTEN_MB=$((WRITTEN_MB + CURRENT_CHUNK))

        # Update progress
        progress_bar $WRITTEN_MB $TARGET_MB
        log_only "Pass $pass: Written ${WRITTEN_MB}MB / ${TARGET_MB}MB"

        # Check if we're running low on space
        CURRENT_AVAIL=$(adb shell "df /sdcard" | tail -1 | awk '{print $4}' | tr -d 'KMG')
        if [ "$CURRENT_AVAIL" -lt 100 ] 2>/dev/null; then
            echo
            log "${YELLOW}Storage nearly full, stopping early for this pass${NC}"
            break
        fi
    done

    echo  # New line after progress bar

    # Sync to ensure data is written
    echo -e "${YELLOW}Syncing to storage...${NC}"
    adb shell "sync"
    sleep 2

    # Delete pass data
    echo -e "${YELLOW}Deleting pass $pass data...${NC}"
    adb shell "rm -rf $PASS_DIR"
    adb shell "sync"
    sleep 1

    PASS_END=$(date +%s)
    PASS_DURATION=$((PASS_END - PASS_START))
    PASS_MINUTES=$((PASS_DURATION / 60))
    PASS_SECONDS=$((PASS_DURATION % 60))

    log "${GREEN}Pass $pass complete: ${WRITTEN_MB}MB written in ${PASS_MINUTES}m ${PASS_SECONDS}s${NC}"
    log_only "Pass $pass completed: ${WRITTEN_MB}MB in ${PASS_DURATION}s"
done

# Final cleanup
echo
log "Performing final cleanup..."
adb shell "rm -rf $WIPE_DIR" 2>/dev/null || true
adb shell "sync"

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
TOTAL_MINUTES=$((TOTAL_DURATION / 60))
TOTAL_SECONDS=$((TOTAL_DURATION % 60))
TOTAL_DATA_GB=$((TARGET_MB * PASSES / 1024))

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Full Secure Wipe Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Device: $MODEL${NC}"
echo -e "${GREEN}  Total time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s${NC}"
echo -e "${GREEN}  Passes completed: $PASSES${NC}"
echo -e "${GREEN}  Total data written: ~${TOTAL_DATA_GB}GB${NC}"
echo -e "${GREEN}========================================${NC}"

log_only "=== Wipe Complete ==="
log_only "Total time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
log_only "Total data: ~${TOTAL_DATA_GB}GB"
echo "" >> "$LOG_FILE"
echo "Completed: $(date)" >> "$LOG_FILE"

# Send desktop notification
notify "Android Secure Wipe Complete" "Device: $MODEL | Time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s | Data: ${TOTAL_DATA_GB}GB"

echo
echo -e "${YELLOW}Recommended next steps:${NC}"
echo "  1. Perform a factory reset from Settings"
echo "  2. Power off the phone"
echo "  3. Remove SIM and SD cards"
echo "  4. Phone is ready for trade-in"
echo
echo -e "${CYAN}Log saved to: $LOG_FILE${NC}"
