# GitHub Actions ARM64 driver build

This source tree includes `.github/workflows/build-driver.yml`.

The workflow uses a Windows GitHub-hosted runner, installs the current Visual Studio/WDK toolchain with Microsoft's WDK WinGet configuration, builds `Release|ARM64`, creates a self-signed test certificate, signs `diptas2557.sys` and `diptas2557.cat`, then uploads the package as an artifact.

Artifact contents:

```text
build/package/ARM64/diptas2557.inf
build/package/ARM64/diptas2557.sys
build/package/ARM64/diptas2557.cat
build/package/ARM64/diptas2557.cer
build/Release/ARM64/diptas2557.pdb
build/ci/package-sha256.txt
build/ci/signatures.txt
```

Phone-side install notes:

1. Keep the phone in the safe baseline before installing.
2. Import `diptas2557.cer` into the test-signing trusted store only if Windows rejects the package signature.
3. Install only this package first; do not bind `tas2557_amp`.
4. Confirm `0.1.12.0` is bound and every gate is `False`.
5. Only then run `STAGE-C-TASK-012.txt`.

The workflow intentionally keeps the INF default gates at `0` and fails the build if those defaults are changed.

References:

- Microsoft Learn: https://learn.microsoft.com/en-us/windows-hardware/drivers/install-the-wdk-using-winget
- Microsoft Learn: https://learn.microsoft.com/en-us/windows-hardware/drivers/develop/building-arm64-drivers
- Microsoft Windows-driver-samples WinGet config: https://github.com/microsoft/Windows-driver-samples/blob/main/_wdk_utils/winget/configs/wdk-vscommunity.dsc.yaml
