// SecureWipe Wizard - Main Entry Point
// OnlyParams, a division of Ciphracore Systems LLC
//
// Prevents additional console window on Windows in release mode

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    securewipe_wizard_lib::run()
}
