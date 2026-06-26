# Dipper TAS2557 Build Toolchain

Date: 2026-06-17

## Current machine

- Windows 10 ARM64 build `21390`
- No `git`, `msbuild`, `cl`, `signtool`, `inf2cat`, or `stampinf` currently on `PATH`
- Current Codex process is not elevated

## Chosen toolchain path

Use the official Microsoft EWDK 26100.6584 ISO for VS2022-era driver builds:

```text
https://go.microsoft.com/fwlink/?linkid=2335681
```

The link resolves to:

```text
EWDK_ge_release_svc_prod1_26100_250904-1728.iso
```

Expected size is about 20.0 GB. The EWDK is preferred here because it is self-contained and avoids modifying the base phone OS with a full Visual Studio installation before the driver is ready.

## Download helpers

Start or resume the BITS download:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-ewdk-download.ps1
```

Check progress:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-ewdk-download.ps1
```

After the ISO is complete, mount it locally and run:

```cmd
LaunchBuildEnv.cmd
E:\BuildEnv\SetupVSEnv.cmd
```

Then build `diptas2557.sln` for ARM64 from that environment.

Current local EWDK command:

```cmd
subst W: "E:\Program Files\Windows Kits\10"
call E:\BuildEnv\SetupBuildEnv.cmd
call E:\BuildEnv\SetupVSEnv.cmd
cd /d C:\Users\Admin\Documents\Codex\2026-06-14\8\work\dipper-tas2557-driver
powershell -ExecutionPolicy Bypass -File .\scripts\build-in-ewdk-env.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\make-driver-package-in-ewdk-env.ps1
```

## Safety reminder

Do not install any built driver until:

1. `scripts\assert-safe-install-preconditions.ps1` passes.
2. The package INF still defaults:

   ```text
   AllowI2cProbe = 0
   AllowI2cWrites = 0
   AllowSpeakerPowerUp = 0
   ```

3. The overlay rollback path still exists.
4. The first install is bind-only.
