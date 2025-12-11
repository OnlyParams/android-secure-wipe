#!/bin/bash
#
# full_wipe.sh - Thorough secure wipe for Android phones
# Dynamic storage detection, multi-pass full storage overwrite
# Includes logging, progress tracking, and desktop notification
#
# Version: 2.1.0
# Repository: https://github.com/OnlyParams/android-secure-wipe
#
# CHANGELOG:
# ----------
# v2.1.0 (2024-12-11)
#   - Added explicit device targeting with adb -s to prevent wrong-device errors
#   - Added --yes/-y flag to skip confirmation prompt (for automation)
#   - Added space verification before write (ensures available >= target)
#   - Minimum space requirement: 100MB
#
# v2.0.0 (2024-12-11)
#   - BREAKING: Rewrote wipe loop to run entirely on-device via single adb shell
#     session instead of per-chunk adb calls (major performance improvement)
#   - Added set -euo pipefail for safer script execution
#   - Added trap handler for cleanup on interrupt/exit
#   - Fixed df parsing to handle decimal values (e.g., "1.2G")
#   - Added --dry-run and --passes options
#   - Improved progress reporting with on-device calculation
#   - Added explicit security disclaimer about flash storage limitations
#
# v1.0.0 (2024-12-11)
#   - Initial release
#   - Per-chunk adb shell calls
#   - Basic progress bar and logging
#   - Desktop notifications (Linux/macOS/Windows)
#
# SECURITY NOTE:
# --------------
# This script overwrites user-accessible storage (/sdcard) with random data.
# On modern Android (6.0+), factory reset destroys encryption keys which is
# the primary defense. This script provides ADDITIONAL assurance against:
#   - Data remnants in unallocated space
#   - Edge cases with wear leveling
#   - Older/unencrypted devices
#
# For maximum security: factory reset + this script + another factory reset.
# For absolute certainty: physical destruction of storage.
#

set -euo pipefail

# Script version
VERSION="2.1.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration defaults
PASSES=3
WIPE_DIR="/sdcard/wipe_temp"
LOG_FILE="phone_wipe.log"
FILL_PERCENT=95    # Fill to 95% to avoid running out of space
DRY_RUN=false
AUTO_YES=false
MIN_SPACE_MB=100   # Minimum required space in MB

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --passes)
            PASSES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --version|-v)
            echo "full_wipe.sh version $VERSION"
            exit 0
            ;;
        --help|-h)
            echo "Usage: full_wipe.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --passes N    Number of overwrite passes (default: 3)"
            echo "  --dry-run     Show what would be done without writing"
            echo "  --yes, -y     Skip confirmation prompt (for automation)"
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

# Initialize log file
echo "=== Android Full Secure Wipe Log ===" > "$LOG_FILE"
echo "Version: $VERSION" >> "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "Passes: $PASSES" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

log() {
    echo -e "$1"
    # Strip color codes for log file
    echo "[$(date '+%H:%M:%S')] $(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOG_FILE"
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

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    echo ""
    if [ $exit_code -ne 0 ] && [ -n "${DEVICE:-}" ]; then
        log "${YELLOW}Interrupted! Cleaning up temporary files on device...${NC}"
        adb -s "$DEVICE" shell "rm -rf $WIPE_DIR" 2>/dev/null || true
        log_only "Cleanup performed after interrupt (exit code: $exit_code)"
    fi
    exit $exit_code
}

# Set trap for cleanup on exit, interrupt, terminate
trap cleanup EXIT INT TERM

# Parse storage size with unit suffix (handles decimals like "1.2G")
parse_size_to_mb() {
    local size_str="$1"
    local value suffix mb

    # Extract numeric value (including decimals)
    value=$(echo "$size_str" | sed -E 's/([0-9.]+).*/\1/')
    # Extract suffix
    suffix=$(echo "$size_str" | sed -E 's/[0-9.]+(.*)/\1/' | tr '[:lower:]' '[:upper:]')

    case "$suffix" in
        G|GB)
            mb=$(awk "BEGIN {printf \"%.0f\", $value * 1024}")
            ;;
        M|MB)
            mb=$(awk "BEGIN {printf \"%.0f\", $value}")
            ;;
        K|KB)
            mb=$(awk "BEGIN {printf \"%.0f\", $value / 1024}")
            ;;
        *)
            # Assume bytes or KB if no suffix
            mb=$(awk "BEGIN {printf \"%.0f\", $value / 1024}")
            ;;
    esac

    echo "$mb"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android Full Secure Wipe v${VERSION}${NC}"
echo -e "${BLUE}  Multi-pass thorough overwrite${NC}"
echo -e "${BLUE}========================================${NC}"
echo

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}*** DRY RUN MODE - No data will be written ***${NC}"
    echo
fi

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

# From here on, use adb -s "$DEVICE" for all commands to ensure correct device targeting

# Get device model
MODEL=$(adb -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
log "Device model: $MODEL"
log_only "Model: $MODEL"
echo

# Get storage information using df -h for human-readable output
log "Analyzing storage..."
STORAGE_LINE=$(adb -s "$DEVICE" shell "df -h /sdcard 2>/dev/null | tail -1" | tr -d '\r')

# Parse the df output - format: Filesystem Size Used Avail Use% Mounted
TOTAL_STR=$(echo "$STORAGE_LINE" | awk '{print $2}')
AVAILABLE_STR=$(echo "$STORAGE_LINE" | awk '{print $4}')

TOTAL_MB=$(parse_size_to_mb "$TOTAL_STR")
AVAILABLE_MB=$(parse_size_to_mb "$AVAILABLE_STR")

# Verify we have enough space
if [ "$AVAILABLE_MB" -lt "$MIN_SPACE_MB" ]; then
    log "${RED}Error: Insufficient storage space${NC}"
    echo "  Available: ${AVAILABLE_MB}MB"
    echo "  Required:  ${MIN_SPACE_MB}MB minimum"
    echo ""
    echo "Free up some space on the device or perform a factory reset first."
    exit 1
fi

# Calculate target fill size (95% of available to leave buffer)
TARGET_MB=$((AVAILABLE_MB * FILL_PERCENT / 100))

# Ensure target is at least MIN_SPACE_MB
if [ "$TARGET_MB" -lt "$MIN_SPACE_MB" ]; then
    log "${RED}Error: Not enough space to perform meaningful wipe${NC}"
    echo "  Available: ${AVAILABLE_MB}MB"
    echo "  Target would be: ${TARGET_MB}MB (below ${MIN_SPACE_MB}MB minimum)"
    exit 1
fi

echo -e "${CYAN}Storage Analysis:${NC}"
echo -e "  Total storage: ~$((TOTAL_MB / 1024))GB ($TOTAL_STR)"
echo -e "  Available: ~$((AVAILABLE_MB / 1024))GB ($AVAILABLE_STR)"
echo -e "  Target fill: ~$((TARGET_MB / 1024))GB (${TARGET_MB}MB at ${FILL_PERCENT}%)"
echo -e "  Passes: $PASSES"
echo

log_only "Total: ${TOTAL_MB}MB, Available: ${AVAILABLE_MB}MB, Target: ${TARGET_MB}MB"

# Estimate time (conservative: ~30MB/s average considering overhead)
ESTIMATED_MINUTES=$((TARGET_MB * PASSES / 30 / 60))
echo -e "${YELLOW}Estimated time: ${ESTIMATED_MINUTES}+ minutes (varies by device speed)${NC}"
echo

# Security disclaimer
echo -e "${CYAN}Security Note:${NC}"
echo "  This overwrites /sdcard (user data partition) with random data."
echo "  On encrypted devices, factory reset destroys encryption keys - that's"
echo "  the primary protection. This script provides additional assurance."
echo

# Confirm before proceeding (unless --yes flag)
echo -e "${YELLOW}This will fill the storage with random data ${PASSES} times.${NC}"
echo -e "${YELLOW}Total data to write: ~$((TARGET_MB * PASSES / 1024))GB${NC}"
echo

if [ "$AUTO_YES" = true ]; then
    log "Auto-confirmed via --yes flag"
else
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Aborted by user."
        exit 0
    fi
fi

if [ "$DRY_RUN" = true ]; then
    echo
    log "${GREEN}Dry run complete. Would have written $((TARGET_MB * PASSES / 1024))GB in $PASSES passes.${NC}"
    exit 0
fi

echo
log "Starting full secure wipe..."
START_TIME=$(date +%s)

# Run the entire wipe operation on-device in a single adb shell session
# This dramatically reduces overhead vs per-chunk adb calls
log "Executing wipe passes on device (this runs entirely on-device for speed)..."

adb -s "$DEVICE" shell "$(cat <<REMOTE_SCRIPT
#!/system/bin/sh
# On-device wipe script - runs entirely on phone for maximum speed

WIPE_DIR="$WIPE_DIR"
TARGET_MB=$TARGET_MB
PASSES=$PASSES
CHUNK_MB=64  # Larger chunks = fewer files = less overhead

mkdir -p "\$WIPE_DIR"

for pass in \$(seq 1 \$PASSES); do
    echo "=== PASS \$pass of \$PASSES ==="
    PASS_DIR="\$WIPE_DIR/pass_\$pass"
    mkdir -p "\$PASS_DIR"

    written=0
    chunk=0

    while [ \$written -lt \$TARGET_MB ]; do
        chunk=\$((chunk + 1))
        remaining=\$((TARGET_MB - written))

        if [ \$remaining -lt \$CHUNK_MB ]; then
            this_chunk=\$remaining
        else
            this_chunk=\$CHUNK_MB
        fi

        # Write random data - bs=1m for 1MB blocks
        dd if=/dev/urandom of="\$PASS_DIR/chunk_\${chunk}.bin" bs=1048576 count=\$this_chunk 2>/dev/null

        written=\$((written + this_chunk))

        # Progress update every ~256MB
        if [ \$((written % 256)) -lt \$CHUNK_MB ]; then
            pct=\$((written * 100 / TARGET_MB))
            echo "PROGRESS: Pass \$pass - \${written}MB / \${TARGET_MB}MB (\${pct}%)"
        fi

        # Check available space - stop if critically low
        avail=\$(df /sdcard 2>/dev/null | tail -1 | awk '{print \$4}')
        # Remove any suffix and check if under 100MB
        avail_num=\$(echo "\$avail" | sed 's/[^0-9]//g')
        if [ -n "\$avail_num" ] && [ "\$avail_num" -lt 100 ] 2>/dev/null; then
            echo "Storage critically low, stopping pass early"
            break
        fi
    done

    echo "Syncing pass \$pass..."
    sync
    sleep 1

    echo "Cleaning up pass \$pass..."
    rm -rf "\$PASS_DIR"
    sync
    sleep 1

    echo "PASS_COMPLETE: Pass \$pass done - wrote \${written}MB"
done

# Final cleanup
rm -rf "\$WIPE_DIR"
sync

echo "WIPE_COMPLETE: All \$PASSES passes finished"
REMOTE_SCRIPT
)" 2>&1 | while IFS= read -r line; do
    # Parse and display progress from device
    case "$line" in
        "=== PASS"*)
            echo ""
            echo -e "${BLUE}$line${NC}"
            log_only "$line"
            ;;
        "PROGRESS:"*)
            # Extract and display progress
            progress_info="${line#PROGRESS: }"
            printf "\r${YELLOW}  %s${NC}    " "$progress_info"
            log_only "$progress_info"
            ;;
        "PASS_COMPLETE:"*)
            echo ""
            pass_info="${line#PASS_COMPLETE: }"
            log "${GREEN}  $pass_info${NC}"
            ;;
        "WIPE_COMPLETE:"*)
            echo ""
            log "${GREEN}${line#WIPE_COMPLETE: }${NC}"
            ;;
        "Syncing"*|"Cleaning"*)
            echo ""
            echo -e "${YELLOW}  $line${NC}"
            ;;
        *)
            # Log other output
            [ -n "$line" ] && log_only "device: $line"
            ;;
    esac
done

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
