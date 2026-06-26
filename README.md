# diptas2557 experimental driver

This is an early Windows KMDF driver draft for the Xiaomi Mi 8 (`dipper`) TAS2557 speaker amplifier.

It is intentionally conservative:

- no TAS2557 I2C writes by default
- no TAS2557 I2C probe/read transaction by default
- no automatic speaker power-up by default
- no TAS2559/TAS2560 MIX2S/MIX3 firmware table reuse
- no startup/unmute unless the registry safety gate is explicitly enabled and Dipper TAS2557 firmware has been validated/loaded
- D0 entry opens the I2C resource but does not touch the bus unless `AllowI2cProbe=1`; mute/shutdown writes require the separate `AllowI2cWrites` gate
- firmware validation is metadata-only and does not write TAS2557 firmware command blocks to hardware

## Current status

This tree is source only. The current phone does not have the Windows Driver Kit or Visual Studio Build Tools installed, so it has not been compiled locally yet.

The driver needs an ACPI node exposing the TAS2557 I2C target. Current Windows device enumeration does not expose one.

The DSDT was dumped successfully on 2026-06-17. It contains `AUDD\QCOM0262` and `AUDD\QCOM0277` strings, but no TAS/TAS2557/TTAS/AFLT strings. See `outputs\dipper-acpi-audio-findings.md`.

## Hardware target

- Device: Xiaomi Mi 8 / dipper
- Amplifier: TI TAS2557
- I2C address: `0x4c`
- Reset GPIO: TLMM 76
- IRQ GPIO: TLMM 30
- Speaker ID GPIO: TLMM 27
- Audio path: `QUATERNARY_MI2S_RX`

## Files

- `src/Driver.c` - KMDF driver entry/device add
- `src/Device.c` - PnP/power callbacks
- `src/Spb.c` - SPB/I2C helper routines
- `src/Tas2557.c` - TAS2557 register/state helpers
- `src/Public.h` - public IOCTL/interface definitions
- `package/diptas2557.inf` - draft test INF
- `acpi/dipper-tas2557-sample.asl` - sample ACPI shape, not directly installable
- `acpi/dipper-audio-overlay-draft.asl` - draft SSDT-style overlay with `AFLT0001` and `TTAS2557`
- `scripts/package-source.ps1` - package source into `outputs`
- `scripts/preflight.ps1` - check current system before any install
- `scripts/assert-safe-install-preconditions.ps1` - refuse install if no TAS2557 PnP device exists
- `scripts/prepare-acpi-overlay-test.ps1` - locked what-if helper for a future `acpitabl.dat` test
- `scripts/check-overlay-readiness.ps1` - read-only readiness check before ACPI overlay enumeration
- `scripts/install-overlay-enumeration-test.ps1` - elevated, opt-in ACPI overlay enumeration test
- `scripts/verify-overlay-enumeration.ps1` - post-reboot PnP check for `AFLT0001`/`TTAS2557`
- `scripts/rollback-overlay-enumeration-test.ps1` - elevated rollback for the overlay enumeration test
- `scripts/install-first-stage-bind-only.ps1` - elevated install wrapper for a signed bind-only package
- `scripts/rollback-first-stage-driver.ps1` - elevated rollback for the first-stage driver package
- `tools/dump-acpi-tables.ps1` - best-effort user-mode firmware table dump
- `tools/read-acpi-direct.ps1` - direct ACPI table-name read attempts
- `tools/scan-acpi-strings.ps1` - string scan for dumped ACPI tables
- `tools/validate-tas2557-firmware.ps1` - verify Dipper TAS2557 firmware header before using it
- `tools/parse-tas2557-firmware.ps1` - parse TAS2557 firmware metadata without writing hardware
- `tools/new-tas2557-firmware-allowlist.ps1` - generate a machine-readable firmware allowlist JSON
- `docs/web-search-notes.md` - public TAS2557 Windows reference notes
- `docs/next-build-tools.md` - required WDK/ASL build tools and safe test sequence
- `docs/overlay-build-proof.md` - iASL tool hash, compile result, and AML hash
- `docs/firmware-allowlist.md` - metadata gates required before firmware can unlock startup

## Safety gate

The INF defaults `AllowI2cProbe`, `AllowResetProbe`, `AllowSoftwareResetProbe`,
`AllowSplitReadProbe`, `AllowI2cWrites`, and `AllowSpeakerPowerUp` to `0`.

With those settings, the driver should never execute TAS2557 register reads, register writes, startup, or unmute. It may only bind to the ACPI node and open the I2C resource.

`AllowI2cProbe=1` is required before the driver attempts the first PGID read. That read uses a standard I2C write-read transaction to send the register address and then read one byte; it is intended to be non-mutating, but it is still bus activity and is therefore opt-in.

Version `0.1.3.0` adds a separate `AllowResetProbe=1` gate. With the reset-capable overlay installed, this permits only the Android-reference hardware reset pulse on GPIO 76 (low 5 ms, high 2 ms) before the PGID read. It does not permit TAS2557 register writes, firmware loading, speaker power-up, or unmute. Speaker-id GPIO 27 remains absent.

Version `0.1.5.0` adds `AllowSoftwareResetProbe=1`. It is accepted only together with `AllowResetProbe=1` and while `AllowI2cWrites=0`. It permits exactly the original Dipper/TI probe write `register 0x01 = 0x01`, waits 1 ms, then performs the PGID read. It does not unlock general register writes, firmware loading, speaker power-up, or unmute.

Version `0.1.6.0` reads GPIO 76 back after the reset pulse. If the reset line
cannot be read or is not high, the driver refuses all I2C activity and remains
muted/off. This distinguishes a successfully submitted GPIO request from a
physically released TAS2557 reset line.

Version `0.1.7.0` retains the same gates and GPIO readback, but extends the
reset-release settling delay from the Android minimum of 2 ms to 20 ms before
the single software-reset probe write. This is a bounded timing diagnostic,
not a general I2C-write unlock.

Version `0.1.8.0` adds `AllowSplitReadProbe=1`. The default remains `0`.

Version `0.1.9.0` changes only the bounded SPB request timeout from 250 ms
to 2000 ms. This tests whether the first Qualcomm GENI/QUP transfer is being
cut off during controller bring-up. It does not add any bus transaction or
change any probe, write, firmware, power, mute, or playback gate default.
When explicitly enabled, the PGID read uses one synchronous address write
followed by one synchronous data read, matching the public TAS2557 Windows
reference transport. The driver records each operation status separately.
This still does not enable firmware loading, speaker power-up, or unmute.

`AllowI2cWrites=1` is required before mute/shutdown or any TAS2557 register-value writes are allowed. `AllowSpeakerPowerUp=1` is an additional, later gate for startup/unmute.

Even if both registry gates are changed to `1`, the current draft still refuses startup/unmute until a future firmware loader marks the Dipper TAS2557 firmware as validated and loaded.

`IOCTL_DIPTAS2557_VALIDATE_FIRMWARE` only parses a caller-supplied TAS2557 firmware blob and records metadata. It deliberately leaves `FirmwareLoaded` false, so it cannot unlock speaker power by itself.

## Firmware precheck

The Dipper TAS2557 blobs currently found under `work\dipper-android-audio-blobs\Forte` have the expected legacy TAS2557 magic:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate-tas2557-firmware.ps1 ..\dipper-android-audio-blobs\Forte\tas2557_uCDSP_aac.bin
```

Expected `Magic`:

```text
35 35 35 32
```

The kernel driver should use the same rule: unknown firmware format means no speaker power-up.

## Expected bring-up order

1. Install WDK/Visual Studio Build Tools on a development machine.
2. Dump ACPI tables from the phone and confirm which Windows I2C controller maps to the TAS2557 bus. Windows' built-in firmware table API may expose only non-AML tables on this device; if DSDT/SSDT are missing, use ACPICA `acpidump`/`iasl` from a trusted source.
3. Add or enable a TAS2557 ACPI child device.
4. Build and test-sign `diptas2557.sys`.
5. Install only the amp driver and verify it stays muted/off.
6. Add AudFilter/miniport integration only after the amp driver can safely probe and shut down.

## Rollback

If installed under a test OEM INF:

```powershell
pnputil /delete-driver <diptas2557-oem.inf> /uninstall /force
pnputil /scan-devices
```

Keep the base audio rollback ready:

```powershell
pnputil /delete-driver oem67.inf /uninstall /force
pnputil /delete-driver oem66.inf /uninstall /force
pnputil /delete-driver oem65.inf /uninstall /force
pnputil /delete-driver oem63.inf /uninstall /force
pnputil /scan-devices
```
