# Android Secure Wipe

**Securely erase your Android phone before trade-in or sale.** Factory resets don't actually overwrite your data - this tool does.

![SecureWipe Wizard](docs/screenshot-desktop-app.png)

---

## The Problem

**Factory reset ≠ secure erase.** When you "wipe" your phone, the data isn't overwritten - it's just marked as deleted. With basic forensic tools, anyone can recover it.

### This isn't theoretical:

| Study | Finding |
|-------|---------|
| **University of Hertfordshire (2018)** | 19% of "wiped" phones on eBay still had personal data - emails, intimate photos, tax documents |
| **Avast (2014)** | From just 20 factory-reset phones, researchers recovered **40,000+ photos**, emails, texts, GPS data, and a loan application |

Once your trade-in leaves your hands, you have zero control over who touches it. Take the extra 15 minutes to wipe it properly.

> **Note:** This is for **Android only**. iPhones have Secure Enclave - factory reset actually works there.

---

## Get Started

### Desktop App (Recommended)

Download from [GitHub Releases](https://github.com/OnlyParams/android-secure-wipe/releases):
- **Windows**: `.msi` installer
- **macOS**: `.dmg`
- **Linux**: `.deb`, `.rpm`, or `.AppImage`

### CLI Scripts

```bash
git clone https://github.com/OnlyParams/android-secure-wipe.git
cd android-secure-wipe
./scripts/quick_wipe.sh -d YOUR_DEVICE_ID    # ~15 min, 3 passes
./scripts/full_wipe.sh -d YOUR_DEVICE_ID     # 1-2 hrs, fills storage
```

**Prerequisite:** [ADB](https://developer.android.com/studio/releases/platform-tools) must be installed (`sudo apt install adb` / `brew install android-platform-tools`)

---

<details>
<summary><strong>Why Your Trade-In Phone Is a Liability</strong> (click to expand)</summary>

## The Journey After You Hand It Over

When you drop your phone in that trade-in envelope or hand it to a carrier rep, you're trusting a surprisingly complex global supply chain with your digital life.

### Domestic Triage

Your device first lands at a US processing facility - typically operated by companies like Assurant, Hyla, or Phobio. There, technicians grade your phone's condition, run diagnostics, and perform their own data wipe.

### The Sorting Hat

Your phone gets graded and routed accordingly:

- **Grade A** (minimal wear): Resold as "Certified Pre-Owned" through Samsung, carriers, Amazon Renewed
- **Grade B** (light damage): Sold through secondary US retailers or exported to Latin America and Eastern Europe
- **Grade C** (significant wear): Shipped overseas for cheaper repair labor - Asia, Africa, or the Middle East

### Where It Gets Interesting

Once your phone leaves that initial US facility, you have zero visibility into who handles it, what tools they use, or what data recovery attempts might occur.

Is a foreign government systematically scraping intelligence from random American trade-ins? Probably not - the volume makes targeted collection impractical.

*Probably.*

But "probably not" isn't "impossible." You're betting against every underpaid technician, every corner-cutting refurbisher, and every opportunistic data thief in that chain.

</details>

<details>
<summary><strong>The Research: What Survives a Factory Reset</strong> (click to expand)</summary>

## The Documented Evidence

### University of Hertfordshire / Comparitech Study (2018)

Researchers purchased 100 secondhand phones on eBay and found that **19% still contained data from previous owners**, with 17% having personally identifiable information - including private emails, intimate photos, tax documents, and bank account details.

[Source](https://www.comparitech.com/blog/information-security/personal-data-left-on-mobile-phones/)

### Avast Study (2014)

From just **20 used Android phones** purchased on eBay - all factory reset - Avast recovered:
- More than **40,000 personal photos**
- Hundreds of emails and text messages
- Over 1,000 Google searches
- A completed loan application
- The identities of four previous owners

**How they did it:** Using standard forensic tools - FTK Imager for disk imaging, `dd` for raw disk cloning, and Scalpel for data carving - researchers extracted data from "unallocated space" that standard deletion doesn't touch.

[Source](https://blog.avast.com/2014/07/09/android-foreniscs-pt-2-how-we-recovered-erased-data/)

### The Real Risks

Forget spy movie scenarios. The real threats are mundane:

- **Lazy consumer wipes** - Factory reset without removing accounts leaves recovery breadcrumbs
- **Cached credentials** - Banking apps, email clients, and authenticators leave fragments
- **Cloud account links** - A phone still tied to your Google account remains a liability
- **Personal content** - Photos, messages, documents that weren't encrypted

</details>

---

<details>
<summary><strong>Full Step-by-Step Guide</strong> (click to expand)</summary>

## Secure Android Phone Wipe Guide

A complete guide to securely wiping an Android phone before trade-in, sale, or disposal.

### Phase 1: Backup Your Data

#### Option A: Samsung Smart Switch (Recommended for Samsung)

1. Install [Smart Switch](https://www.samsung.com/us/support/owners/app/smart-switch) on your computer
2. Connect phone via USB
3. Open Smart Switch -> Click "Backup"
4. Select all data categories you want to preserve
5. Wait for backup to complete

#### Option B: Google Backup

1. **Settings -> Google -> Backup**
2. Ensure "Back up to Google Drive" is ON
3. Tap "Back up now"
4. Verify backup completed in Google Drive

#### Option C: Manual Backup via ADB

```bash
adb backup -apk -shared -all -f phone_backup.ab
adb pull /sdcard/DCIM ./backup/photos
adb pull /sdcard/Download ./backup/downloads
```

#### Don't Forget

- [ ] Photos and videos synced to cloud or computer
- [ ] Contacts synced to Google account
- [ ] WhatsApp/Signal/Telegram backups
- [ ] Authenticator apps (export codes FIRST)
- [ ] Notes and documents
- [ ] Game save data

---

### Phase 2: Sign Out of Accounts

> **Critical:** If you factory reset without removing your Google account first, the phone will be locked with Factory Reset Protection (FRP).

1. Go to **Settings -> Accounts**
2. Tap each account and select **"Remove account"**
3. Remove your Google account **last**

#### Samsung Phones - Extra Steps

1. **Settings -> Accounts -> Samsung account -> Sign out**
2. **Settings -> Biometrics and security -> Find My Mobile -> Turn OFF**

---

### Phase 3: Factory Reset

#### From Settings (Preferred)
1. **Settings -> General Management -> Reset**
2. Tap **Factory data reset**
3. Scroll down, tap **Reset**
4. Enter PIN/password if prompted
5. Tap **Delete all**

#### From Recovery Mode (If needed)
1. Power off phone
2. Hold **Volume Up + Power** until logo appears
3. Select "Wipe data/factory reset"
4. Confirm and reboot

---

### Phase 4: Enable USB Debugging

After factory reset, go through minimal setup:

1. **Skip everything** - Wi-Fi, Google account, Samsung account
2. **Enable Developer Options:** Settings -> About Phone -> Tap Build Number 7 times
3. **Enable USB Debugging:** Settings -> Developer Options -> USB Debugging ON
4. **Connect to Computer:** Authorize the connection on phone
5. **Verify:** Run `adb devices` - should show your device

---

### Phase 5: Secure Overwrite

#### Quick Wipe (~15 minutes)
```bash
./scripts/quick_wipe.sh -d YOUR_DEVICE_ID
```

#### Full Wipe (1-2+ hours)
```bash
./scripts/full_wipe.sh -d YOUR_DEVICE_ID
```

---

### Phase 6: Final Steps

1. Disconnect phone from computer
2. Perform another factory reset (recommended)
3. Power off the phone
4. Remove SIM card and SD card
5. **Phone is ready for trade-in/sale**

</details>

<details>
<summary><strong>Desktop App Usage</strong> (click to expand)</summary>

## SecureWipe Wizard

### Prerequisites

1. **Install ADB**:
   - Linux: `sudo apt install adb`
   - Windows: Download [Platform-Tools](https://developer.android.com/tools/releases/platform-tools)
   - macOS: `brew install android-platform-tools`

2. **On your Android device**:
   - Enable Developer Options (tap Build number 7 times)
   - Enable USB Debugging
   - Use a data-capable USB cable

### Usage

1. **Launch SecureWipe Wizard**
2. **Connect your Android phone via USB**
3. **Step 1: Prepare** - Click "Check Connection", verify device info
4. **Step 2: Options** - Choose Quick Wipe (~15 min) or Full Wipe (1-3 hrs)
5. **Step 3: Confirm** - Review settings, click Start Wipe
6. **Step 4: Progress** - Watch real-time progress (can abort anytime)
7. **Step 5: Done** - Factory reset, remove SIM/SD, power off

### Safety Notes

- Always backup important data first
- Sign out of all accounts before wiping
- Samsung devices: storage reporting quirks handled automatically
- Multiple devices: unplug others first

### Build from Source

```bash
cd desktop-app
npm install
npm run tauri dev    # Development
npm run tauri build  # Production
```

Requirements: Node.js 20+, Rust 1.70+, ADB installed

</details>

<details>
<summary><strong>Troubleshooting</strong> (click to expand)</summary>

## Common Issues

### "unauthorized" in adb devices

Your phone sees the computer but hasn't trusted it yet.

1. Look at your phone screen for "Allow USB debugging?" popup
2. Check "Always allow from this computer"
3. Tap **Allow**

**If no popup:** Settings -> Developer Options -> Revoke USB debugging authorizations -> Reconnect

### "device not found" or "no devices"

1. Try a different USB cable (many are charge-only)
2. Try a different USB port
3. Check USB mode on phone: select "File Transfer" or "MTP"
4. Restart ADB: `adb kill-server && adb start-server`

### "Permission denied" errors

1. Make sure you completed factory reset first
2. Reconnect the phone
3. Restart ADB

### Write speed is slow

Normal for flash storage. Tips:
- Use USB 3.0 port (usually blue)
- Use high-quality cable
- Use `--size 512` for faster passes
- Keep phone unlocked during wipe

### Phone disconnects during wipe

1. Disable auto-sleep: Settings -> Display -> Screen timeout -> 10 minutes
2. Keep phone unlocked
3. Don't move the phone or cable

</details>

<details>
<summary><strong>Security Notes</strong> (click to expand)</summary>

## Technical Details

- **Encryption:** Android 6.0+ encrypts user data by default. Factory reset destroys encryption keys, making recovery very difficult even without overwriting.

- **Wear Leveling:** Flash storage uses wear leveling, which may leave data fragments in reserved blocks. Multiple overwrite passes help address this.

- **Secure Erase:** Some phones support hardware-level secure erase via fastboot. Check your device documentation.

- **For Highly Sensitive Data:** Physical destruction is the only 100% guarantee.

</details>

---

## Contributing

Found an issue or have a suggestion? Open an issue or submit a PR.

## Credits

- **McJuniorstein** — Project lead, testing, and direction
- **Claude Opus 4.5** (Anthropic) — Architecture, Rust/Tauri implementation, and documentation
- **Grok 4.1** (xAI) — Research and planning contributions

## License

MIT License - See [LICENSE](LICENSE) for details.

---

*Created by [OnlyParams](https://onlyparams.dev), a division of Ciphracore Systems LLC - Practical security for the reasonably paranoid.*
