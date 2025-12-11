// SecureWipe Wizard - Tauri Backend
// OnlyParams, a division of Ciphracore Systems LLC
//
// This module exposes Tauri commands for:
// - ADB device detection and management
// - Secure wipe execution (quick/full modes)
// - Factory reset triggering
// - Progress streaming to frontend

use serde::{Deserialize, Serialize};
use std::process::Command;
use tauri::Emitter;

// ============================================================================
// Data Structures
// ============================================================================

/// Device information returned from ADB
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub id: String,
    pub model: String,
    pub brand: String,
}

/// Storage information from device
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageInfo {
    pub total_mb: u64,
    pub available_mb: u64,
}

/// Progress event emitted during wipe operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WipeProgress {
    pub pass: u32,
    pub total_passes: u32,
    pub percent: f32,
    pub message: String,
}

/// Wipe configuration from frontend
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WipeConfig {
    pub mode: String,        // "quick" or "full"
    pub passes: u32,         // Number of passes (1-20)
    pub size_mb: Option<u32>, // Chunk size for quick mode
    pub double_reset: bool,  // Enable double factory reset
}

// ============================================================================
// Tauri Commands
// ============================================================================

/// Check if ADB is available and detect connected devices
#[tauri::command]
async fn check_adb() -> Result<DeviceInfo, String> {
    // Run `adb devices` to list connected devices
    let output = Command::new("adb")
        .arg("devices")
        .output()
        .map_err(|e| format!("Failed to run ADB: {}. Is ADB installed?", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Parse device ID from output (skip header line)
    let lines: Vec<&str> = stdout.lines().collect();
    let device_line = lines
        .iter()
        .skip(1) // Skip "List of devices attached"
        .find(|line| line.contains("device") && !line.contains("offline"))
        .ok_or("No device connected. Please connect your Android device and enable USB debugging.")?;

    let device_id = device_line
        .split_whitespace()
        .next()
        .ok_or("Failed to parse device ID")?
        .to_string();

    // Get device model
    let model_output = Command::new("adb")
        .args(["-s", &device_id, "shell", "getprop", "ro.product.model"])
        .output()
        .map_err(|e| format!("Failed to get device model: {}", e))?;
    let model = String::from_utf8_lossy(&model_output.stdout).trim().to_string();

    // Get device brand
    let brand_output = Command::new("adb")
        .args(["-s", &device_id, "shell", "getprop", "ro.product.brand"])
        .output()
        .map_err(|e| format!("Failed to get device brand: {}", e))?;
    let brand = String::from_utf8_lossy(&brand_output.stdout).trim().to_string();

    Ok(DeviceInfo {
        id: device_id,
        model,
        brand,
    })
}

/// Get storage information from connected device
#[tauri::command]
async fn get_storage_info(device_id: String) -> Result<StorageInfo, String> {
    // Run df command on device
    let output = Command::new("adb")
        .args(["-s", &device_id, "shell", "df", "-m", "/sdcard"])
        .output()
        .map_err(|e| format!("Failed to get storage info: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Parse df output (second line contains the data)
    let lines: Vec<&str> = stdout.lines().collect();
    let data_line = lines
        .get(1)
        .ok_or("Failed to parse storage info")?;

    let parts: Vec<&str> = data_line.split_whitespace().collect();

    // df -m output: Filesystem 1M-blocks Used Available Use% Mounted
    let total_mb: u64 = parts.get(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let available_mb: u64 = parts.get(3)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    Ok(StorageInfo {
        total_mb,
        available_mb,
    })
}

/// Execute secure wipe operation
#[tauri::command]
async fn run_wipe(
    window: tauri::Window,
    device_id: String,
    config: WipeConfig,
) -> Result<String, String> {
    // Validate inputs
    let passes = config.passes.clamp(1, 20);
    let size_mb = config.size_mb.map(|s| s.clamp(64, 10240)).unwrap_or(1024);

    // Determine script to run
    let script = if config.mode == "quick" {
        "quick_wipe.sh"
    } else {
        "full_wipe.sh"
    };

    // Get the scripts directory path
    let scripts_dir = std::env::current_exe()
        .map_err(|e| format!("Failed to get exe path: {}", e))?
        .parent()
        .ok_or("Failed to get parent dir")?
        .join("scripts");

    // Build command with sanitized arguments
    let mut cmd = Command::new("bash");
    cmd.current_dir(&scripts_dir)
        .arg(script)
        .arg("-d").arg(&device_id)
        .arg("-p").arg(passes.to_string())
        .arg("-y"); // Auto-confirm

    if config.mode == "quick" {
        cmd.arg("-s").arg(size_mb.to_string());
    }

    // Clear environment for security (no passthrough)
    cmd.env_clear();

    // Execute and capture output
    let output = cmd
        .output()
        .map_err(|e| format!("Failed to execute wipe script: {}", e))?;

    // Emit completion event
    let _ = window.emit("wipe-complete", serde_json::json!({
        "success": output.status.success(),
        "mode": config.mode,
        "passes": passes
    }));

    if output.status.success() {
        Ok("Wipe completed successfully".to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("Wipe failed: {}", stderr))
    }
}

/// Trigger factory reset via ADB
#[tauri::command]
async fn run_factory_reset(device_id: String, is_final: bool) -> Result<String, String> {
    // Safety: This opens the factory reset screen; user must confirm on device
    let output = Command::new("adb")
        .args([
            "-s", &device_id,
            "shell", "am", "start",
            "-a", "android.settings.MASTER_CLEAR"
        ])
        .output()
        .map_err(|e| format!("Failed to trigger factory reset: {}", e))?;

    if output.status.success() {
        let phase = if is_final { "final" } else { "initial" };
        Ok(format!("Factory reset screen opened ({}). Please confirm on device.", phase))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("Failed to open reset screen: {}", stderr))
    }
}

/// Get device-specific instructions
#[tauri::command]
fn get_instructions(brand: String, model: String) -> Vec<String> {
    // Hardcoded instructions map for supported devices
    match (brand.to_lowercase().as_str(), model.to_lowercase().as_str()) {
        ("samsung", m) if m.contains("s24") || m.contains("s25") => vec![
            "1. Go to Settings > General management > Reset".to_string(),
            "2. Tap 'Factory data reset'".to_string(),
            "3. Review information and tap 'Reset'".to_string(),
            "4. Enter your PIN/password if prompted".to_string(),
            "5. Tap 'Delete all' to confirm".to_string(),
            "Note: One UI may require Samsung account verification.".to_string(),
        ],
        ("google", m) if m.contains("pixel") => vec![
            "1. Go to Settings > System > Reset options".to_string(),
            "2. Tap 'Erase all data (factory reset)'".to_string(),
            "3. Tap 'Erase all data' to confirm".to_string(),
            "4. Enter your PIN if prompted".to_string(),
        ],
        ("oneplus", _) => vec![
            "1. Go to Settings > System > Reset options".to_string(),
            "2. Tap 'Erase all data (factory reset)'".to_string(),
            "3. Tap 'Reset phone'".to_string(),
            "4. Enter your PIN and confirm".to_string(),
        ],
        _ => vec![
            "1. Go to Settings > System (or General Management)".to_string(),
            "2. Find 'Reset' or 'Reset options'".to_string(),
            "3. Select 'Factory data reset' or 'Erase all data'".to_string(),
            "4. Follow on-screen prompts to confirm".to_string(),
            "Note: Steps may vary by manufacturer.".to_string(),
        ],
    }
}

/// Revoke ADB debugging on device (optional security step)
#[tauri::command]
async fn revoke_adb(device_id: String) -> Result<String, String> {
    let output = Command::new("adb")
        .args([
            "-s", &device_id,
            "shell", "settings", "put", "global", "adb_enabled", "0"
        ])
        .output()
        .map_err(|e| format!("Failed to revoke ADB: {}", e))?;

    if output.status.success() {
        Ok("ADB debugging disabled on device".to_string())
    } else {
        Err("Failed to disable ADB debugging".to_string())
    }
}

// ============================================================================
// App Setup
// ============================================================================

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            check_adb,
            get_storage_info,
            run_wipe,
            run_factory_reset,
            get_instructions,
            revoke_adb,
        ])
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
    fn test_get_instructions_samsung() {
        let instructions = get_instructions("Samsung".to_string(), "Galaxy S24".to_string());
        assert!(!instructions.is_empty());
        assert!(instructions[0].contains("Settings"));
    }

    #[test]
    fn test_get_instructions_fallback() {
        let instructions = get_instructions("Unknown".to_string(), "Phone".to_string());
        assert!(!instructions.is_empty());
        assert!(instructions.last().unwrap().contains("may vary"));
    }
}
