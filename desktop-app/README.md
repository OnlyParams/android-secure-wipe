# SecureWipe Wizard

**A desktop application for secure Android data erasure.**

Built by OnlyParams, a division of Ciphracore Systems LLC.

## Overview

SecureWipe Wizard provides a user-friendly graphical interface for the secure wipe scripts in this repository. It guides users through the process of securely erasing data from Android devices before trade-in or disposal.

## Features

- **Step-by-step wizard** - Guided process from device connection to completion
- **Automatic device detection** - Detects connected Android devices via ADB
- **Two wipe modes**:
  - **Quick Wipe** (~15 mins): 3 passes with 1GB chunks - NIST-compliant for everyday use
  - **Full Wipe** (1-3+ hrs): Multi-pass 95% storage fill - maximum security
- **Double Factory Reset** - Optional pre and post-wipe factory resets for paranoid mode
- **Real-time progress** - Live logs and progress tracking
- **Cross-platform** - Linux, Windows, macOS

## Prerequisites

- **ADB** (Android Debug Bridge) installed and in PATH
- **Node.js** 20+
- **Rust** 1.70+ (for building)

## Development

```bash
# Install dependencies
npm install

# Run in development mode (hot reload)
npm run tauri dev

# Run tests
npm test
```

## Building

```bash
# Build for current platform
npm run tauri build

# Binaries will be in src-tauri/target/release/
```

## Project Structure

```
desktop-app/
├── src/                    # Svelte frontend
│   ├── App.svelte          # Main wizard component
│   ├── lib/                # Reusable components
│   └── app.css             # Tailwind styles
├── src-tauri/              # Rust backend
│   ├── src/
│   │   ├── lib.rs          # Tauri commands
│   │   └── main.rs         # Entry point
│   ├── scripts/            # Wipe scripts (copied from repo root)
│   └── tauri.conf.json     # Tauri configuration
└── package.json
```

## Tech Stack

- **Frontend**: Svelte 5 + Tailwind CSS
- **Backend**: Rust + Tauri v2
- **Build**: Vite

## Security

- No telemetry or tracking
- Scripts run in isolated subprocesses with cleared environment
- All inputs validated and sanitized
- Strict Content Security Policy

## License

MIT License - See [LICENSE](../LICENSE) for details.

---

**OnlyParams, a division of Ciphracore Systems LLC**
