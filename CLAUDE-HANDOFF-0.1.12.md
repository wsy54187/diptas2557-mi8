# diptas2557 0.1.12 handoff

Current phone baseline:

- `ACPI\TTAS2557\0` is safely bound to `diptas2557 0.1.10.0`.
- `tas2557_amp` is not bound and must not be forced.
- All TAS2557 gates were restored to `0` in:
  - `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0`
  - `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0\Device Parameters`
  - the active MEDIA class driver key
- Runtime safe state was verified:
  - `Powered=False`
  - `Muted=True`
  - `FirmwareLoaded=False`

0.1.12 purpose:

1. Add manual IOCTLs for safe TAS2557 startup and unmute.
2. Keep install-time and boot-time behavior safe; nothing powers up automatically.
3. Allow a bounded Stage C test that validates GOER firmware metadata, runs `SafeStartup`, keeps the amp muted, records status, then forces shutdown and closes gates.

Critical source changes:

- `src\Public.h`
  - adds `IOCTL_DIPTAS2557_SAFE_STARTUP`
  - adds `IOCTL_DIPTAS2557_SAFE_UNMUTE`
  - extends `DIPTAS2557_STATUS` with:
    - `LastShutdownStatus`
    - `LastSafeStartupStatus`
    - `LastSafeUnmuteStatus`
- `src\Device.c`
  - handles the new IOCTLs
  - records result codes
  - force-shuts down after failed startup/unmute
- `src\Tas2557.c`
  - successful firmware metadata validation now sets `FirmwareLoaded = TRUE`

Build path:

1. Push this clean source tree to GitHub.
2. Run `.github/workflows/build-driver.yml`.
3. Download artifact `diptas2557-arm64-testsigned`.
4. Confirm package files and hashes:
   - `diptas2557.inf`
   - `diptas2557.sys`
   - `diptas2557.cat`
   - `diptas2557.cer`

Phone Stage A:

Run only after the GitHub artifact is downloaded to the phone:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\Admin\Desktop\mi8-tas2557-0.1.12-source\scripts\install-012-bind-only.ps1 -PackageDir <artifact>\build\package\ARM64
```

Stage A must end with:

- bound driver version `0.1.12.0`
- `AllowI2cWrites=False`
- `AllowSpeakerPowerUp=False`
- `Powered=False`
- `Muted=True`

Do not run Stage C until Stage A logs are reviewed.

Phone Stage C:

Only after Stage A is confirmed safe:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\Admin\Desktop\mi8-tas2557-0.1.12-source\scripts\run-safe-startup-muted-012.ps1
```

Stage C intentionally does not call `SafeUnmute`.

Decision after Stage C:

- If `LastSafeStartupStatus == 0x00000000` and status briefly shows `Powered=True`, TAS2557 power-up works. If speaker is still silent later, investigate qcauddev/QCAUD routing.
- If startup fails, inspect `LastSafeStartupStatus`, `LastShutdownStatus`, `LastAddressWriteStatus`, and `LastDataReadStatus` before changing routing.

Do not:

- Force-bind `tas2557_amp`.
- Re-run old `0.1.8/0.1.9/0.1.10` probe scripts.
- Leave TAS gates set to `1`.
- Play test audio during Stage A or Stage C.
- Run `SafeUnmute` before muted startup is reviewed.
