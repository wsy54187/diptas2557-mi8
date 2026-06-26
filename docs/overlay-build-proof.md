# Dipper TAS2557 ACPI Overlay Build Proof

Generated on 2026-06-17.

## Tool

- Tool package: `work/tools/acpica-20260408/iasl-win-20260408.zip`
- Source URL: `https://github.com/acpica/acpica/releases/download/20260408/iasl-win-20260408.zip`
- SHA256: `121F5E4F30B1DF63D09052294E4A605D4DEE2DFB9599FA24AF4AC6015DF02B70`
- `iasl.exe` version: `20260408`

## Input

- ASL: `work/dipper-tas2557-driver/acpi/dipper-audio-overlay-draft.asl`

## Output

- AML: `work/dipper-tas2557-driver/acpi/dipper-audio-overlay-draft.aml`
- AML length: `323` bytes
- AML SHA256: `EE49766488DFA76D8073672CEF69258C03E72AB515550BC7839C20A9E516CD7A`
- Decompiled ASL: `work/dipper-tas2557-driver/acpi/dipper-audio-overlay-draft.dsl`

## Compile result

```text
Compilation successful. 0 Errors, 0 Warnings, 0 Remarks, 1 Optimizations
```

## Decompiled checks

The decompiled AML contains:

- `AFLT0001`
- `TTAS2557`
- dependency on `\_SB.ADSP.SLM1.ADCM.AUDD`
- dependency on `\_SB.GIO0`
- dependency on `\_SB.I2C6`
- I2C target `0x004C` on `\_SB.I2C6`
- GPIO interrupt resource on `\_SB.GIO0`, pin `30`

The first overlay intentionally does not expose reset GPIO `76` or speaker-id GPIO `27`.

## Not executed

- No `acpitabl.dat` was copied to `C:\Windows\System32`.
- Test signing was not enabled.
- No reboot was triggered.
- No TAS2557 driver was installed.

