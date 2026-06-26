# Build Tool Requirements

Current phone status on 2026-06-17:

- `msbuild`: not found
- `signtool`: not found
- `inf2cat`: not found
- `stampinf`: not found
- `iasl` / `asl`: not found

## Needed before any compiled test

1. Visual Studio Build Tools with ARM64 driver build support.
2. Windows Driver Kit matching this Windows build as closely as practical.
3. An ASL compiler:
   - Microsoft `asl.exe` from WDK, or
   - official ACPICA `iasl.exe` from a verified source.

## Safety rule

Do not enable test signing or copy `acpitabl.dat` until:

1. `dipper-audio-overlay-draft.asl` compiles cleanly to AML.
2. The AML decompiles back to the same `AFLT0001` and `TTAS2557` resources.
3. The existing rollback backup is still present.
4. The ACPI replacement path is tested as enumeration-only first, with no TAS2557 driver installed.
5. Any first TAS2557 driver install uses the default `AllowI2cProbe=0`, `AllowI2cWrites=0`, and `AllowSpeakerPowerUp=0` values, so it binds without touching the TAS2557 I2C bus.

## Target test sequence

1. Compile overlay:

   ```powershell
   iasl.exe .\acpi\dipper-audio-overlay-draft.asl
   ```

2. Decompile and inspect:

   ```powershell
   iasl.exe -d .\acpi\dipper-audio-overlay-draft.aml
   ```

3. Run what-if overlay helper:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\prepare-acpi-overlay-test.ps1 -CompiledAmlPath .\acpi\dipper-audio-overlay-draft.aml -WhatIfOnly
   ```

4. Only after manual review, unlock and execute the overlay test.
