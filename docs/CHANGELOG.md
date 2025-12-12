# Changelog

All notable changes to SecureWipe Wizard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Full wipe mode testing (pending)

---

## [1.0.0-beta.2] - 2025-12-12

### Added
- **Step 1 Prerequisites Notice**: Amber warning box reminding users to backup data, sign out of accounts, disable Find My Device, and perform initial factory reset before using the tool
- **Docs Link**: Direct link to GitHub README for full instructions
- **Step 5 Final Checklist**: Comprehensive numbered list for post-wipe verification including FRP check, data verification, SIM/SD removal, and device power-off
- **Disclaimer**: "This tool overwrites free space after reset. We are not responsible for data loss."
- `strip_ansi()` function to remove ANSI escape codes from script output
- `test_strip_ansi` and `test_parse_progress_line_final` unit tests (now 15 total)

### Changed
- **Samsung Compatibility**: Removed `-m` flag from `df` command (not supported on Samsung devices), now parses 1K-blocks and converts to MB
- **Progress Parsing**: Updated to handle actual script output format ("Pass N complete" and "Passes completed: N") instead of expected format
- **Factory Reset**: Replaced unreliable ADB intent button with manual instructions (MASTER_CLEAR intent blocked on most devices)
- **Step 5 Checklist**: Changed from interactive checkboxes to simple numbered list

### Removed
- **Double Factory Reset Feature**: Removed checkbox from Step 2 and display from Step 3 (factory reset now handled via instructions only)
- Factory reset button from Step 5 (replaced with instructions)
- Unused state variables: `isResetting`, `resetMessage`, `finalResetDone`, `doubleReset`
- `triggerFactoryReset()` function

### Fixed
- **Pass Counter Bug**: Progress ring now correctly shows pass 1/3 → 2/3 → 3/3 instead of staying stuck at 1/3
- **Storage Info Error**: "Failed to read storage info" error on Samsung devices due to unsupported `df -m` flag
- ANSI escape codes (`[0;32m`) no longer break progress message parsing

### Tested
- Samsung Galaxy S24 Ultra (SM-S928U) - Android 16
- Quick wipe: 3 passes x 1024MB completed successfully (~15 seconds per pass)
- Device detection (hot plug and cold start)
- Full wizard flow Steps 1-5

---

## [1.0.0-beta.1] - 2025-12-11

### Added
- **Phase 3: Full 5-Step Wizard Frontend**
  - Step 1 (Prepare): Live device detection with `check_adb_status`, storage info display
  - Step 2 (Options): Quick/Full mode cards, passes slider (1-10), chunk size selector
  - Step 3 (Confirm): Settings recap with warning banner, Start Wipe button
  - Step 4 (Progress): Circular progress ring, pass counter, real-time log streaming via Tauri events
  - Step 5 (Done): Success screen, brand-specific factory reset instructions
- Svelte 5 runes ($state, $derived) for reactive state management
- Tauri invoke/listen APIs for frontend-backend communication
- TunesBro-inspired card design with teal-green Tailwind palette

### Security
- **CRITICAL**: Scripts now require `-d DEVICE_ID` flag (no auto-detection fallback)
- Prevents wrong-device wipes when multiple devices connected
- Clear error messages guide user to correct device ID

---

## [1.0.0-alpha.1] - 2025-12-11

### Added
- **Phase 2: Enhanced Rust Backend**
  - `sanitize_device_id()` - Input validation to prevent command injection
  - `parse_adb_devices()` - Robust ADB output parsing
  - `parse_df_output()` - Storage info parsing
  - `check_adb_status` - ADB installation and version check
  - `check_device_connected` - Device connectivity polling
  - `run_factory_reset` - Factory reset settings screen launcher
  - `cleanup_wipe_files` - Temporary file cleanup
  - Streaming progress via Tauri events during wipe
- 13 unit tests covering parsing, sanitization, and instructions
- Environment clearing in subprocess execution (retains PATH only)

### Added
- **Phase 1: Tauri App Scaffold**
  - Tauri v2 + Svelte 5 + Tailwind CSS setup
  - Basic Rust backend with ADB commands
  - Project structure and build configuration
  - OnlyParams branding and strict CSP

---

## Scripts

### [2.2.0] - 2025-12-11
- Input validation for all parameters
- `--dry-run` flag for quick_wipe.sh
- Novice-friendly documentation

### [2.1.0] - 2025-12-11
- Device targeting with `-d` flag
- `--yes` flag for non-interactive mode
- Space verification before wipe

### [2.0.0] - 2025-12-11
- Major rewrite with performance and safety improvements
- Multi-pass overwrite with configurable passes
- Progress reporting

---

*OnlyParams, a division of Ciphracore Systems LLC*
