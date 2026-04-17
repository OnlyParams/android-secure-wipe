# NIST SP 800-88 Rev 2 Compliance Reference

This document maps SecureWipe Wizard's sanitization methods to NIST SP 800-88 Rev 2 "Guidelines for Media Sanitization" (September 2025).

## NIST Sanitization Levels

NIST defines three levels of media sanitization, in increasing order of assurance:

| Level | Method | Description |
|-------|--------|-------------|
| **Clear** | Overwrite all addressable storage | Protects against simple, non-invasive data recovery. Uses standard read/write commands. |
| **Purge** | Cryptographic erase or block erase | Renders data infeasible to recover even with state-of-the-art laboratory techniques. |
| **Destroy** | Physical destruction | Shredding, pulverizing, incinerating, or melting the storage media. |

## How SecureWipe Maps to NIST Levels

### quick_wipe.sh / full_wipe.sh (Overwrite Mode)

**NIST Level: Partial Clear**

The overwrite scripts write random data (`/dev/urandom`) to user-accessible storage (`/sdcard`). This meets NIST Clear requirements for the addressable portion of storage, with the following caveats:

- Flash storage uses **overprovisioning** (extra spare cells not addressable by the host). These cells cannot be reached by software overwrite.
- **Wear leveling** scatters data across physical cells non-deterministically. Overwriting logical addresses does not guarantee all physical copies are overwritten.
- NIST SP 800-88 Rev 2 explicitly warns: "Users who have become accustomed to relying on overwrite techniques on magnetic ISM and who have continued to apply these techniques as ISM types evolved (e.g., to flash memory-based devices) can be exposing their data to increased risk of unintentional disclosure."

**What this means:** Software overwrite provides meaningful protection against casual data recovery tools but does not meet NIST Clear for the full physical storage on flash-based devices.

### Factory Reset (Cryptographic Erase)

**NIST Level: Conditional Purge**

On Android 6.0+ with File-Based Encryption (FBE), factory reset destroys the encryption keys, rendering user data cryptographically unrecoverable. This aligns with NIST Purge via cryptographic erase, **if and only if**:

- Encryption was active for the entire lifetime of the data (no plaintext data was ever stored)
- Key strength is AES-128 or stronger (standard on modern Android)
- All copies of encryption keys are destroyed (including escrow/backup copies)
- The cryptographic module meets FIPS 140-3 requirements (for compliance use)

**Known limitations from forensic research** (Ryder et al., DOI: 10.1016/j.fsidi.2023.301587):

- The **persist** partition retains data after factory reset (battery status, calibration data)
- The **klog** partition retains UEFI/boot logs after reset on Android 12+
- The **userdata** partition retains encrypted remnant bytes (keys are destroyed but ciphertext remains on disk)

### Physical Destruction

**NIST Level: Destroy**

NIST considers physical destruction the only method that provides absolute certainty. SecureWipe Wizard's README recommends this for highly sensitive data.

## Compliance Summary

| Scenario | Recommended Method | NIST Level Achieved |
|----------|-------------------|-------------------|
| Consumer trade-in | Factory reset + overwrite + factory reset | Partial Clear + Conditional Purge |
| Corporate device reuse | Factory reset + full overwrite (3+ passes) | Partial Clear + Conditional Purge |
| Regulatory compliance (HIPAA, GDPR) | Factory reset + full overwrite + document retention | Partial Clear + Conditional Purge (verify with compliance officer) |
| High-security / classified | Physical destruction | Destroy |
| Pre-Android 6.0 (unencrypted) | Full overwrite (3+ passes) + factory reset | Partial Clear |

## Important Disclaimers

- **No software-only method can guarantee complete sanitization of flash storage.** This is a fundamental limitation of the technology, not a deficiency of this tool.
- **Cryptographic erase is only as strong as the key management.** If encryption keys were backed up, escrowed, or extractable before the reset, data may still be recoverable.
- **This tool provides defense in depth.** The recommended workflow (factory reset + overwrite + factory reset) layers cryptographic erase with data overwrite to address multiple threat vectors.
- **For compliance purposes**, consult your organization's data handling policies and legal requirements. This document is informational and does not constitute legal or compliance advice.

## References

- NIST SP 800-88 Rev 2, "Guidelines for Media Sanitization" (September 2025), Chandramouli & Hibbard
- Ryder et al., "Android factory reset data remanence," Forensic Science International: Digital Investigation, 2023 (DOI: 10.1016/j.fsidi.2023.301587)

---

*Document created as part of security audit, April 2026. See SECURITY_AUDIT_2026-04-16.md for full findings.*
