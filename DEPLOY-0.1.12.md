# Dipper TAS2557 0.1.12 safe-startup diagnostic

This build keeps the default installed state safe:

- `AllowI2cProbe = 0`
- `AllowResetProbe = 0`
- `AllowSoftwareResetProbe = 0`
- `AllowSplitReadProbe = 0`
- `AllowRawReadProbe = 0`
- `AllowI2cWrites = 0`
- `AllowSpeakerPowerUp = 0`

New in 0.1.12:

1. Adds manual IOCTLs for:
   - `IOCTL_DIPTAS2557_SAFE_STARTUP`
   - `IOCTL_DIPTAS2557_SAFE_UNMUTE`
2. Records:
   - `LastShutdownStatus`
   - `LastSafeStartupStatus`
   - `LastSafeUnmuteStatus`
3. Treats a successfully validated GOER firmware metadata blob as the firmware safety token needed for manual startup.
4. Adds `scripts\run-safe-startup-muted-012.ps1`, which performs a bounded test:
   - opens gates,
   - restarts the device,
   - validates firmware metadata,
   - calls safe startup while keeping the amp muted,
   - force-shuts the amp down,
   - closes all gates and restarts back to the safe state.

Do not run `SafeUnmute` until the muted startup status has been reviewed.

Build from an EWDK/VS environment:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-in-ewdk-env.ps1 -SkipHardwarePreconditions
powershell -ExecutionPolicy Bypass -File .\scripts\make-driver-package-in-ewdk-env.ps1
```

Expected package output:

```text
build\package\ARM64\diptas2557.inf
build\package\ARM64\diptas2557.sys
build\package\ARM64\diptas2557.cat
build\package\ARM64\diptas2557.cer
```

After installation and reboot, verify the safe baseline before Stage C:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\query-driver-status.ps1
```

Only then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-safe-startup-muted-012.ps1
```

For phone-side bind-only installation from a GitHub Actions artifact, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-012-bind-only.ps1 -PackageDir <artifact>\build\package\ARM64
```

This install stage restarts only `ACPI\TTAS2557\0`, clears all TAS gates back to `0`, and verifies `Powered=False` and `Muted=True`.
