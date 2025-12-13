// SecureWipe Wizard - Tauri Backend
// OnlyParams, a division of Ciphracore Systems LLC
//
// Phase 2: Enhanced backend with streaming progress, robust parsing, and tests
//
// This module exposes Tauri commands for:
// - ADB device detection and management
// - Secure wipe execution (quick/full modes) with progress streaming
// - Factory reset triggering
// - Device-specific instructions

use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::Mutex;
use tauri::{Emitter, Manager, State};

// Global state for managing the running wipe process
struct WipeState {
    device_id: Mutex<Option<String>>,
}

// ============================================================================
// Data Structures
// ============================================================================

/// Device information returned from ADB
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub id: String,
    pub model: String,
    pub brand: String,
    pub android_version: String,
}

/// Storage information from device
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageInfo {
    pub total_mb: u64,
    pub used_mb: u64,
    pub available_mb: u64,
    pub percent_used: u8,
}

/// Progress event emitted during wipe operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WipeProgress {
    pub pass: u32,
    pub total_passes: u32,
    pub percent: f32,
    pub bytes_written: u64,
    pub message: String,
    pub phase: String, // "writing", "verifying", "cleanup"
}

/// Wipe configuration from frontend
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WipeConfig {
    pub mode: String,         // "quick" or "full"
    pub passes: u32,          // Number of passes (1-20)
    pub size_mb: Option<u32>, // Chunk size for quick mode (64-10240)
    pub double_reset: bool,   // Enable double factory reset
}

/// Result of an ADB command check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdbStatus {
    pub installed: bool,
    pub version: Option<String>,
    pub devices_connected: u32,
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Validate and sanitize device ID to prevent command injection
fn sanitize_device_id(device_id: &str) -> Result<String, String> {
    // Device IDs should only contain alphanumeric, colons, and dots
    // Examples: "emulator-5554", "192.168.1.1:5555", "RFXXXXXXXX"
    let valid = device_id
        .chars()
        .all(|c| c.is_alphanumeric() || c == ':' || c == '.' || c == '-' || c == '_');

    if !valid || device_id.is_empty() || device_id.len() > 64 {
        return Err("Invalid device ID format".to_string());
    }

    Ok(device_id.to_string())
}

/// Parse ADB devices output into a list of device IDs
fn parse_adb_devices(output: &str) -> Vec<(String, String)> {
    output
        .lines()
        .skip(1) // Skip "List of devices attached"
        .filter_map(|line| {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[1] == "device" {
                Some((parts[0].to_string(), parts[1].to_string()))
            } else {
                None
            }
        })
        .collect()
}

/// Parse df output to get storage info
/// Note: Android df returns 1K-blocks by default (no -m flag support on some devices)
fn parse_df_output(output: &str) -> Result<StorageInfo, String> {
    let lines: Vec<&str> = output.lines().collect();
    let data_line = lines.get(1).ok_or("No data in df output")?;
    let parts: Vec<&str> = data_line.split_whitespace().collect();

    if parts.len() < 5 {
        return Err("Unexpected df output format".to_string());
    }

    // Values are in 1K-blocks, convert to MB
    let total_kb: u64 = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let used_kb: u64 = parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(0);
    let available_kb: u64 = parts.get(3).and_then(|s| s.parse().ok()).unwrap_or(0);

    // Parse percentage (remove % sign)
    let percent_str = parts.get(4).unwrap_or(&"0%");
    let percent_used: u8 = percent_str
        .trim_end_matches('%')
        .parse()
        .unwrap_or(0);

    Ok(StorageInfo {
        total_mb: total_kb / 1024,
        used_mb: used_kb / 1024,
        available_mb: available_kb / 1024,
        percent_used,
    })
}

/// Strip ANSI escape codes from a string
fn strip_ansi(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '\x1b' {
            // Skip escape sequence: ESC [ ... m
            if chars.peek() == Some(&'[') {
                chars.next();
                while let Some(&nc) = chars.peek() {
                    chars.next();
                    if nc == 'm' {
                        break;
                    }
                }
            }
        } else {
            result.push(c);
        }
    }
    result
}

/// Parse progress from script output
/// Script outputs:
/// - "PROGRESS: Pass N - XMB / YMB (Z%)" (within-pass progress from full wipe)
/// - "Pass N complete" (per-pass completion)
/// - "Passes completed: N" (final summary)
fn parse_progress_line(line: &str, total_passes: u32) -> Option<WipeProgress> {
    // Strip ANSI color codes first
    let clean_line = strip_ansi(line);

    // Must contain "Pass" to be a progress line
    if !clean_line.contains("Pass") {
        return None;
    }

    // Handle "Passes completed: N" format (final summary)
    if clean_line.contains("Passes completed:") {
        let pass = clean_line
            .split("Passes completed:")
            .nth(1)
            .and_then(|s| s.trim().parse().ok())
            .unwrap_or(total_passes);

        return Some(WipeProgress {
            pass,
            total_passes,
            percent: 100.0,
            bytes_written: 0,
            message: clean_line,
            phase: "complete".to_string(),
        });
    }

    // Handle "Pass N complete" format (per-pass update)
    // Must match "Pass " followed by a digit (not "Passes")
    let pass: u32 = if let Some(idx) = clean_line.find("Pass ") {
        let after_pass = &clean_line[idx + 5..]; // Skip "Pass "
        after_pass
            .chars()
            .take_while(|c| c.is_numeric())
            .collect::<String>()
            .parse()
            .unwrap_or(1)
    } else {
        return None; // "Passes" without space doesn't count
    };

    // Calculate overall percent based on completed passes and within-pass progress
    let percent = if clean_line.contains("complete") {
        // Pass complete: overall = (pass / total) * 100
        (pass as f32 / total_passes as f32) * 100.0
    } else if let Some(pct_idx) = clean_line.find('%') {
        // Within-pass progress: extract the percentage from the line
        let start = clean_line[..pct_idx]
            .rfind(|c: char| !c.is_numeric() && c != '.')
            .map(|i| i + 1)
            .unwrap_or(0);
        let within_pass_pct: f32 = clean_line[start..pct_idx].parse().unwrap_or(0.0);
        // Calculate overall progress: ((completed_passes + within_pass/100) / total) * 100
        // Pass 1 at 50% with 3 passes = ((0 + 0.5) / 3) * 100 = 16.7%
        let completed_passes = pass.saturating_sub(1) as f32;
        ((completed_passes + within_pass_pct / 100.0) / total_passes as f32) * 100.0
    } else {
        0.0
    };

    let phase = if clean_line.contains("complete") { "complete".to_string() } else { "writing".to_string() };

    Some(WipeProgress {
        pass,
        total_passes,
        percent,
        bytes_written: 0,
        message: clean_line,
        phase,
    })
}

// ============================================================================
// Tauri Commands
// ============================================================================

/// Check if ADB is installed and get version info
#[tauri::command]
async fn check_adb_status() -> Result<AdbStatus, String> {
    // Check if ADB is installed
    let version_output = Command::new("adb")
        .arg("version")
        .output();

    match version_output {
        Ok(output) if output.status.success() => {
            let version_str = String::from_utf8_lossy(&output.stdout);
            let version = version_str
                .lines()
                .next()
                .map(|s| s.to_string());

            // Count connected devices
            let devices_output = Command::new("adb")
                .arg("devices")
                .output()
                .map_err(|e| format!("Failed to list devices: {}", e))?;

            let devices_str = String::from_utf8_lossy(&devices_output.stdout);
            let devices = parse_adb_devices(&devices_str);

            Ok(AdbStatus {
                installed: true,
                version,
                devices_connected: devices.len() as u32,
            })
        }
        _ => Ok(AdbStatus {
            installed: false,
            version: None,
            devices_connected: 0,
        }),
    }
}

/// Check for connected devices and return device info
#[tauri::command]
async fn check_adb() -> Result<DeviceInfo, String> {
    // Run `adb devices` to list connected devices
    let output = Command::new("adb")
        .arg("devices")
        .output()
        .map_err(|e| format!("Failed to run ADB: {}. Is ADB installed?", e))?;

    if !output.status.success() {
        return Err("ADB command failed. Please check ADB installation.".to_string());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let devices = parse_adb_devices(&stdout);

    if devices.is_empty() {
        return Err(
            "No device connected. Please:\n\
             1. Connect your Android device via USB\n\
             2. Enable USB Debugging in Developer Options\n\
             3. Authorize this computer on your phone"
                .to_string(),
        );
    }

    // Use first connected device
    let device_id = &devices[0].0;

    // Get device properties
    let get_prop = |prop: &str| -> String {
        Command::new("adb")
            .args(["-s", device_id, "shell", "getprop", prop])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default()
    };

    let model = get_prop("ro.product.model");
    let brand = get_prop("ro.product.brand");
    let android_version = get_prop("ro.build.version.release");

    if model.is_empty() {
        return Err("Connected device not responding. Please unlock your phone and try again.".to_string());
    }

    Ok(DeviceInfo {
        id: device_id.clone(),
        model,
        brand,
        android_version,
    })
}

/// Get storage information from connected device
#[tauri::command]
async fn get_storage_info(device_id: String) -> Result<StorageInfo, String> {
    let device_id = sanitize_device_id(&device_id)?;

    // Note: Don't use -m flag - not supported on all Android devices (e.g., Samsung)
    // Default output is 1K-blocks which we convert in parse_df_output
    let output = Command::new("adb")
        .args(["-s", &device_id, "shell", "df", "/sdcard"])
        .output()
        .map_err(|e| format!("Failed to get storage info: {}", e))?;

    if !output.status.success() {
        return Err("Failed to read storage info. Device may be locked.".to_string());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    parse_df_output(&stdout)
}

/// Execute secure wipe operation with streaming progress
#[tauri::command]
async fn run_wipe(
    window: tauri::Window,
    state: State<'_, WipeState>,
    device_id: String,
    config: WipeConfig,
) -> Result<String, String> {
    let device_id = sanitize_device_id(&device_id)?;

    // Store device ID for abort functionality
    {
        let mut dev_lock = state.device_id.lock().unwrap();
        *dev_lock = Some(device_id.clone());
    }

    // Validate inputs
    let passes = config.passes.clamp(1, 20);
    let size_mb = config.size_mb.map(|s| s.clamp(64, 10240)).unwrap_or(1024);

    // Validate mode
    if config.mode != "quick" && config.mode != "full" {
        return Err("Invalid wipe mode. Must be 'quick' or 'full'.".to_string());
    }

    let script = if config.mode == "quick" {
        "quick_wipe.sh"
    } else {
        "full_wipe.sh"
    };

    // Get the scripts directory path - check multiple locations
    let exe_path = std::env::current_exe()
        .map_err(|e| format!("Failed to get exe path: {}", e))?;

    let possible_paths = vec![
        exe_path.parent().unwrap().join("scripts"),
        exe_path.parent().unwrap().join("../Resources/scripts"),
        std::path::PathBuf::from("scripts"),
    ];

    let scripts_dir = possible_paths
        .into_iter()
        .find(|p| p.join(script).exists())
        .ok_or("Scripts directory not found. Please reinstall the application.")?;

    // Emit start event
    let _ = window.emit(
        "wipe-progress",
        WipeProgress {
            pass: 0,
            total_passes: passes,
            percent: 0.0,
            bytes_written: 0,
            message: format!("Starting {} wipe with {} passes...", config.mode, passes),
            phase: "starting".to_string(),
        },
    );

    // Build command with sanitized arguments
    let mut cmd = Command::new("bash");
    cmd.current_dir(&scripts_dir)
        .arg(script)
        .arg("-d")
        .arg(&device_id)
        .arg("-p")
        .arg(passes.to_string())
        .arg("-y") // Auto-confirm
        .arg("--raw") // Raw output mode for real-time streaming (no pipe buffering)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if config.mode == "quick" {
        cmd.arg("-s").arg(size_mb.to_string());
    }

    // Clear environment for security
    cmd.env_clear();
    // But we need PATH for the script to find adb
    if let Ok(path) = std::env::var("PATH") {
        cmd.env("PATH", path);
    }

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to start wipe: {}", e))?;

    // Stream stdout for progress
    if let Some(stdout) = child.stdout.take() {
        let reader = BufReader::new(stdout);
        let window_clone = window.clone();

        for line in reader.lines().map_while(Result::ok) {
            // Parse progress from line
            if let Some(progress) = parse_progress_line(&line, passes) {
                let _ = window_clone.emit("wipe-progress", progress);
            }
        }
    }

    // Wait for completion
    let status = child
        .wait()
        .map_err(|e| format!("Wipe process error: {}", e))?;

    // Clear wipe state
    {
        let mut dev_lock = state.device_id.lock().unwrap();
        *dev_lock = None;
    }

    // Emit completion event
    let _ = window.emit(
        "wipe-complete",
        serde_json::json!({
            "success": status.success(),
            "mode": config.mode,
            "passes": passes
        }),
    );

    if status.success() {
        Ok(format!(
            "Wipe completed successfully! {} passes of {} mode.",
            passes, config.mode
        ))
    } else {
        Err("Wipe failed. Check device connection and try again.".to_string())
    }
}

/// Abort a running wipe operation
#[tauri::command]
async fn abort_wipe(
    window: tauri::Window,
    state: State<'_, WipeState>,
) -> Result<String, String> {
    // Get the device ID
    let device_id = {
        let dev_lock = state.device_id.lock().unwrap();
        dev_lock.clone()
    };

    let device_id = match device_id {
        Some(id) => id,
        None => return Err("No wipe operation in progress.".to_string()),
    };

    // Kill the wipe scripts on the host
    let _ = Command::new("pkill")
        .arg("-f")
        .arg("wipe.sh")
        .output();

    // Kill dd process on the device
    let _ = Command::new("adb")
        .arg("-s")
        .arg(&device_id)
        .arg("shell")
        .arg("pkill -f 'dd if=/dev/urandom'")
        .output();

    // Clean up temp files on the device
    let _ = Command::new("adb")
        .arg("-s")
        .arg(&device_id)
        .arg("shell")
        .arg("rm -rf /sdcard/wipe_temp/")
        .output();

    // Clear wipe state
    {
        let mut dev_lock = state.device_id.lock().unwrap();
        *dev_lock = None;
    }

    // Emit abort event
    let _ = window.emit(
        "wipe-aborted",
        serde_json::json!({
            "message": "Wipe operation aborted and cleaned up."
        }),
    );

    Ok("Wipe aborted. Temporary files cleaned up.".to_string())
}

/// Trigger factory reset via ADB (opens settings screen)
#[tauri::command]
async fn run_factory_reset(device_id: String, is_final: bool) -> Result<String, String> {
    let device_id = sanitize_device_id(&device_id)?;

    // Try intents in order of specificity - some are blocked on certain devices
    let intents = [
        // Most direct - but often requires system permission
        ("android.settings.MASTER_CLEAR", "Factory Reset"),
        // Backup & Reset settings - works on some devices
        ("android.settings.BACKUP_AND_RESET_SETTINGS", "Backup & Reset"),
        // Privacy settings - contains reset on some devices
        ("android.settings.PRIVACY_SETTINGS", "Privacy Settings"),
        // Internal storage - close to reset on Samsung
        ("android.settings.INTERNAL_STORAGE_SETTINGS", "Storage Settings"),
    ];

    for (intent, name) in intents {
        let output = Command::new("adb")
            .args(["-s", &device_id, "shell", "am", "start", "-a", intent])
            .output();

        if let Ok(out) = output {
            let stdout = String::from_utf8_lossy(&out.stdout);
            let stderr = String::from_utf8_lossy(&out.stderr);

            // Check if it worked (no Permission Denial or Error in output)
            if !stdout.contains("Permission Denial")
                && !stdout.contains("Error:")
                && !stderr.contains("Permission Denial")
                && !stderr.contains("SecurityException")
            {
                let phase = if is_final { "final" } else { "initial" };
                return Ok(format!(
                    "{} opened on device ({} reset).\n\
                     Navigate to: Settings > General management > Reset > Factory data reset\n\
                     Then confirm the reset on your device.",
                    name, phase
                ));
            }
        }
    }

    // Fallback: just open main Settings
    let output = Command::new("adb")
        .args(["-s", &device_id, "shell", "am", "start", "-n", "com.android.settings/.Settings"])
        .output()
        .map_err(|e| format!("Failed to open settings: {}", e))?;

    if output.status.success() {
        let phase = if is_final { "final" } else { "initial" };
        Ok(format!(
            "Settings opened on device ({} reset).\n\
             Navigate to: General management > Reset > Factory data reset\n\
             Then confirm the reset on your device.",
            phase
        ))
    } else {
        Err("Could not open settings. Please manually navigate to Settings > General management > Reset.".to_string())
    }
}

/// Check if device is still connected (for polling after reset)
#[tauri::command]
async fn check_device_connected(device_id: String) -> Result<bool, String> {
    let device_id = sanitize_device_id(&device_id)?;

    let output = Command::new("adb")
        .arg("devices")
        .output()
        .map_err(|e| format!("Failed to check devices: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let devices = parse_adb_devices(&stdout);

    Ok(devices.iter().any(|(id, _)| id == &device_id))
}

/// Get device-specific factory reset instructions
#[tauri::command]
fn get_instructions(brand: String, model: String) -> Vec<String> {
    let brand_lower = brand.to_lowercase();
    let model_lower = model.to_lowercase();

    match brand_lower.as_str() {
        "samsung" => {
            if model_lower.contains("s24") || model_lower.contains("s25") {
                vec![
                    "1. Go to Settings > General management > Reset".to_string(),
                    "2. Tap 'Factory data reset'".to_string(),
                    "3. Scroll down and review the information".to_string(),
                    "4. Tap 'Reset' at the bottom".to_string(),
                    "5. Enter your PIN/password if prompted".to_string(),
                    "6. Tap 'Delete all' to confirm".to_string(),
                    "".to_string(),
                    "Note: One UI may require Samsung account verification.".to_string(),
                ]
            } else if model_lower.contains("a55") || model_lower.contains("a54") {
                vec![
                    "1. Go to Settings > General management > Reset".to_string(),
                    "2. Tap 'Factory data reset'".to_string(),
                    "3. Review and tap 'Reset'".to_string(),
                    "4. Enter your PIN and tap 'Delete all'".to_string(),
                ]
            } else {
                vec![
                    "1. Go to Settings > General management > Reset".to_string(),
                    "2. Tap 'Factory data reset'".to_string(),
                    "3. Tap 'Reset' and confirm with your PIN".to_string(),
                    "4. Tap 'Delete all' to complete".to_string(),
                ]
            }
        }
        "google" => vec![
            "1. Go to Settings > System > Reset options".to_string(),
            "2. Tap 'Erase all data (factory reset)'".to_string(),
            "3. Tap 'Erase all data' to confirm".to_string(),
            "4. Enter your PIN if prompted".to_string(),
            "5. Wait for the device to restart".to_string(),
        ],
        "oneplus" => vec![
            "1. Go to Settings > System > Reset options".to_string(),
            "2. Tap 'Erase all data (factory reset)'".to_string(),
            "3. Tap 'Reset phone'".to_string(),
            "4. Enter your PIN and confirm".to_string(),
            "5. Device will reboot and reset".to_string(),
        ],
        "motorola" => {
            if model_lower.contains("edge") {
                vec![
                    "1. Go to Settings > System > Reset options".to_string(),
                    "2. Tap 'Erase all data (factory reset)'".to_string(),
                    "3. Tap 'Erase all data'".to_string(),
                    "4. Enter your PIN to confirm".to_string(),
                ]
            } else {
                vec![
                    "1. Go to Settings > System > Advanced > Reset options".to_string(),
                    "2. Tap 'Erase all data (factory reset)'".to_string(),
                    "3. Confirm and enter your PIN".to_string(),
                ]
            }
        }
        "nothing" | "cmf" => vec![
            "1. Go to Settings > System > Reset options".to_string(),
            "2. Tap 'Erase all data (factory reset)'".to_string(),
            "3. Tap 'Erase all data' and confirm".to_string(),
            "4. Enter your PIN if prompted".to_string(),
        ],
        _ => vec![
            "1. Go to Settings > System (or General Management)".to_string(),
            "2. Find 'Reset' or 'Reset options'".to_string(),
            "3. Select 'Factory data reset' or 'Erase all data'".to_string(),
            "4. Follow on-screen prompts to confirm".to_string(),
            "5. Enter your PIN/password if requested".to_string(),
            "".to_string(),
            "Note: Steps may vary by manufacturer and Android version.".to_string(),
        ],
    }
}

/// Revoke ADB debugging on device (optional security step)
#[tauri::command]
async fn revoke_adb(device_id: String) -> Result<String, String> {
    let device_id = sanitize_device_id(&device_id)?;

    let output = Command::new("adb")
        .args([
            "-s",
            &device_id,
            "shell",
            "settings",
            "put",
            "global",
            "adb_enabled",
            "0",
        ])
        .output()
        .map_err(|e| format!("Failed to revoke ADB: {}", e))?;

    if output.status.success() {
        Ok("ADB debugging disabled on device. You may need to re-enable it for future use.".to_string())
    } else {
        Err("Failed to disable ADB debugging. Device may require root access.".to_string())
    }
}

/// Clean up any temporary wipe files on device
#[tauri::command]
async fn cleanup_wipe_files(device_id: String) -> Result<String, String> {
    let device_id = sanitize_device_id(&device_id)?;

    let output = Command::new("adb")
        .args([
            "-s",
            &device_id,
            "shell",
            "rm",
            "-rf",
            "/sdcard/wipe_temp",
            "/sdcard/secure_wipe_*",
        ])
        .output()
        .map_err(|e| format!("Failed to cleanup: {}", e))?;

    if output.status.success() {
        Ok("Temporary wipe files cleaned up.".to_string())
    } else {
        // Not critical if cleanup fails
        Ok("Cleanup attempted. Some files may remain.".to_string())
    }
}

// ============================================================================
// App Setup
// ============================================================================

/// Cleanup any running wipe processes and temp files
fn cleanup_on_exit(state: &WipeState) {
    // Get the device ID if a wipe was in progress
    let device_id = {
        let dev_lock = state.device_id.lock().unwrap();
        dev_lock.clone()
    };

    // Kill any running wipe scripts
    let _ = Command::new("pkill")
        .arg("-f")
        .arg("wipe.sh")
        .output();

    // If we have a device ID, clean up device-side processes and files
    if let Some(device_id) = device_id {
        // Kill dd process on device
        let _ = Command::new("adb")
            .arg("-s")
            .arg(&device_id)
            .arg("shell")
            .arg("pkill -f 'dd if=/dev/urandom'")
            .output();

        // Clean up temp files
        let _ = Command::new("adb")
            .arg("-s")
            .arg(&device_id)
            .arg("shell")
            .arg("rm -rf /sdcard/wipe_temp/")
            .output();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(WipeState {
            device_id: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![
            check_adb_status,
            check_adb,
            get_storage_info,
            run_wipe,
            abort_wipe,
            run_factory_reset,
            check_device_connected,
            get_instructions,
            revoke_adb,
            cleanup_wipe_files,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                // Cleanup when window is closed
                if let Some(state) = window.try_state::<WipeState>() {
                    cleanup_on_exit(&state);
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_device_id_valid() {
        assert!(sanitize_device_id("emulator-5554").is_ok());
        assert!(sanitize_device_id("192.168.1.1:5555").is_ok());
        assert!(sanitize_device_id("RFXXXXXXXX").is_ok());
        assert!(sanitize_device_id("device_123").is_ok());
    }

    #[test]
    fn test_sanitize_device_id_invalid() {
        assert!(sanitize_device_id("").is_err());
        assert!(sanitize_device_id("device; rm -rf /").is_err());
        assert!(sanitize_device_id("$(whoami)").is_err());
        assert!(sanitize_device_id(&"a".repeat(100)).is_err());
    }

    #[test]
    fn test_parse_adb_devices() {
        let output = "List of devices attached\n\
                      emulator-5554\tdevice\n\
                      192.168.1.1:5555\tdevice\n\
                      RF123456\toffline\n";

        let devices = parse_adb_devices(output);
        assert_eq!(devices.len(), 2);
        assert_eq!(devices[0].0, "emulator-5554");
        assert_eq!(devices[1].0, "192.168.1.1:5555");
    }

    #[test]
    fn test_parse_adb_devices_empty() {
        let output = "List of devices attached\n\n";
        let devices = parse_adb_devices(output);
        assert!(devices.is_empty());
    }

    #[test]
    fn test_parse_df_output() {
        // Real Samsung S24 output format (1K-blocks, not MB)
        let output = "Filesystem     1K-blocks    Used Available Use% Mounted on\n\
                      /dev/fuse      483563724 3229496 480203156   1% /storage/emulated\n";

        let info = parse_df_output(output).unwrap();
        // Values are converted from KB to MB (divided by 1024)
        assert_eq!(info.total_mb, 483563724 / 1024);  // ~472230 MB
        assert_eq!(info.used_mb, 3229496 / 1024);     // ~3153 MB
        assert_eq!(info.available_mb, 480203156 / 1024); // ~468948 MB
        assert_eq!(info.percent_used, 1);
    }

    #[test]
    fn test_parse_df_output_invalid() {
        let output = "Error: device not found\n";
        assert!(parse_df_output(output).is_err());
    }

    #[test]
    fn test_strip_ansi() {
        let with_ansi = "\x1b[0;32mPass 2 complete\x1b[0m";
        assert_eq!(strip_ansi(with_ansi), "Pass 2 complete");

        let no_ansi = "Pass 2 complete";
        assert_eq!(strip_ansi(no_ansi), "Pass 2 complete");
    }

    #[test]
    fn test_parse_progress_line() {
        // Test "Pass N complete" with ANSI codes
        let line = "\x1b[0;32mPass 2 complete\x1b[0m";
        let progress = parse_progress_line(line, 3).unwrap();
        assert_eq!(progress.pass, 2);
        assert_eq!(progress.total_passes, 3);
        assert!((progress.percent - 66.67).abs() < 1.0);
    }

    #[test]
    fn test_parse_progress_line_final() {
        // Test "Passes completed: N" format (final summary)
        let line = "\x1b[0;32mPasses completed: 3\x1b[0m";
        let progress = parse_progress_line(line, 3).unwrap();
        assert_eq!(progress.pass, 3);
        assert_eq!(progress.total_passes, 3);
        assert_eq!(progress.percent, 100.0);
        assert_eq!(progress.phase, "complete");
    }

    #[test]
    fn test_parse_progress_line_no_match() {
        let line = "Starting wipe operation...";
        assert!(parse_progress_line(line, 3).is_none());
    }

    #[test]
    fn test_parse_progress_line_full_wipe_format() {
        // Test "PROGRESS: Pass N - XMB / YMB (Z%)" format from full_wipe.sh
        let line = "\x1b[1;33mPROGRESS: Pass 1 - 256MB / 50000MB (0%)\x1b[0m";
        let progress = parse_progress_line(line, 3).unwrap();
        assert_eq!(progress.pass, 1);
        assert_eq!(progress.total_passes, 3);
        // Pass 1 at 0% with 3 passes = ((0 + 0) / 3) * 100 = 0%
        assert!(progress.percent < 1.0);
        assert_eq!(progress.phase, "writing");

        // Test mid-pass progress
        let line2 = "PROGRESS: Pass 2 - 25000MB / 50000MB (50%)";
        let progress2 = parse_progress_line(line2, 3).unwrap();
        assert_eq!(progress2.pass, 2);
        // Pass 2 at 50% with 3 passes = ((1 + 0.5) / 3) * 100 = 50%
        assert!((progress2.percent - 50.0).abs() < 1.0);
    }

    #[test]
    fn test_wipe_config_validation() {
        let config = WipeConfig {
            mode: "quick".to_string(),
            passes: 25, // Over limit
            size_mb: Some(50), // Under limit
            double_reset: false,
        };

        // Passes should clamp to 20
        assert_eq!(config.passes.clamp(1, 20), 20);

        // Size should clamp to minimum 64
        assert_eq!(config.size_mb.unwrap().clamp(64, 10240), 64);
    }

    #[test]
    fn test_get_instructions_samsung_s24() {
        let instructions = get_instructions("Samsung".to_string(), "Galaxy S24 Ultra".to_string());
        assert!(!instructions.is_empty());
        assert!(instructions[0].contains("Settings"));
        assert!(instructions.iter().any(|s| s.contains("One UI")));
    }

    #[test]
    fn test_get_instructions_pixel() {
        let instructions = get_instructions("Google".to_string(), "Pixel 8 Pro".to_string());
        assert!(!instructions.is_empty());
        assert!(instructions.iter().any(|s| s.contains("System")));
    }

    #[test]
    fn test_get_instructions_fallback() {
        let instructions = get_instructions("Unknown".to_string(), "Phone XYZ".to_string());
        assert!(!instructions.is_empty());
        assert!(instructions.iter().any(|s| s.contains("may vary")));
    }

    #[test]
    fn test_get_instructions_case_insensitive() {
        let instructions1 = get_instructions("SAMSUNG".to_string(), "galaxy s24".to_string());
        let instructions2 = get_instructions("samsung".to_string(), "Galaxy S24".to_string());
        assert_eq!(instructions1.len(), instructions2.len());
    }
}
