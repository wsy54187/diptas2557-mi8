# TAS2557 Firmware Allowlist

This driver must not enable TAS2557 startup/unmute unless Dipper firmware metadata matches the known-safe profile parsed from Xiaomi Mi 8 Android blobs.

## Required metadata

- magic: `0x35353532`
- device family: `0`
- device: `2`
- driver version: `0x00000400`
- program count: at least `1`
- config count: at least `1`
- safe program index: `0`
- safe config index: `0`
- safe sample rate: `48000`
- block types:
  - `0x00` PLL
  - `0x01` program device A
  - `0x03` config coefficient device A
  - `0x04` config pre device A
- command opcodes:
  - register write, offset `<= 0x7f`
  - delay, offset `0x81`
  - bulk write, offset `0x85`

## Parsed Dipper firmware evidence

`outputs/dipper-tas2557-firmware-parse.md`

The parsed Dipper firmware contains:

- `Program[0]`: `Tuning Mode`
- `Config[0]`: `configuration_Tuning Mode_48 KHz_s1_0`

## Current code state

The current driver source exposes firmware metadata fields in `DIPTAS2557_STATUS`, but does not yet load firmware. Therefore `FirmwareLoaded` remains false and startup/unmute remains blocked even if `AllowI2cWrites` and `AllowSpeakerPowerUp` are both set.
