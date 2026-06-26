# Public TAS2557 Windows References

Checked on 2026-06-17.

## Xiaomi Mi 8 / dipper

- `n00b69/woa-dipper` is an active Xiaomi Mi 8 Windows installation guide, but the public README does not show a completed internal-speaker TAS2557 solution.
- Search terms around `dipper TAS2557 Windows WOA` mostly lead back to generic WOA guides, Android firmware blobs, or unrelated USB/recovery pages.

## Closest Windows TAS2557 work

- `sunflower2333/tas2557_win` is the closest public TAS2557 Windows codebase.
- It provides:
  - an `AudFilter` upper filter for the Qualcomm audio miniport path
  - a `TAS2557_amp` driver
  - an ACPI sample for `AFLT0001` and `TTAS2557` on `\_SB.I2C6`, I2C address `0x4c`, IRQ GPIO `30`
- It is not safe to install as-is on this Xiaomi Mi 8:
  - startup/unmute code is auto-generated and hardcoded
  - README says speakers may fail to shut down, may work intermittently, and may produce very loud noise
  - the project release is for a different trial target, not a verified Dipper package

## Related but not directly reusable

- `woa-miatoll/tas256X_win` is for TAS2562/TAS2564, not TAS2557. It confirms the same architecture style and credits sunflower's AudFilter, but its hardcoded settings target Redmi/POCO miatoll devices.
- The `tas256X_win` code is useful as a Windows architecture reference only:
  - it keeps an `AudFilter` callback path separate from the I2C amplifier driver
  - it implements explicit active/mute/shutdown power states
  - it checks chip IDs before applying settings
  - it hardcodes boost, current-limit, limiter, slot, and TDM settings for TAS2562/TAS2564 devices
- Do not port the TAS256x power/boost/limiter register values to Dipper. They are chip- and board-specific and could be unsafe on TAS2557.

## Current direction

Use the public projects only for architecture and ACPI shape. Keep the Dipper driver probe-only until:

1. ACPI exposes the TAS2557 as a PnP device.
2. The driver can prove I2C register access and immediately force shutdown.
3. Dipper's own TAS2557 firmware/calibration is parsed and validated.
4. Startup/unmute is tested at very low volume with rollback ready.

The current Dipper draft is deliberately stricter than the public TAS256x driver: it may probe and force shutdown, but it does not enable active playback unless a future firmware loader has validated and loaded Dipper's own TAS2557 firmware.

## Additional check on 2026-06-17

Searches for `qcauddev_ext850.inf`, `AUDD\QCOM0262`, and `ADCM\VEN_QCOM&DEV_0240` did not reveal a completed Dipper speaker package.

Public driver database pages list `AUDD\QCOM0262` as a Qualcomm Aqstic audio adapter hardware ID. That supports the local DSDT finding that `AUDD\QCOM0262` is the expected Qualcomm audio miniport child, but it does not provide Dipper-specific topology, speaker protection, or TAS2557 control.
