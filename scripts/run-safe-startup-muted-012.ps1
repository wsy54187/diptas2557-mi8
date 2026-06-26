param(
    [string]$FirmwarePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Administrator privileges are required.'
}

$root = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent (Split-Path -Parent $root)
$logDir = Join-Path $workspace ("work\diptas2557-safe-startup-012-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
$deviceId = 'ACPI\TTAS2557\0'
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0\Device Parameters'
$driverSubkey = (Get-PnpDeviceProperty -InstanceId $deviceId | Where-Object KeyName -eq 'DEVPKEY_Device_Driver').Data
if ([string]::IsNullOrWhiteSpace($driverSubkey)) {
    Write-Error 'Could not resolve current driver registry subkey.'
}
$driverRegPath = Join-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class' $driverSubkey
$driverRegExportPath = "HKLM\SYSTEM\CurrentControlSet\Control\Class\$driverSubkey"

if ([string]::IsNullOrWhiteSpace($FirmwarePath)) {
    $candidates = @(
        'C:\dipper-audio\dipper-acdb\tas2557_uCDSP_goer.bin',
        'C:\dipper-audio\dipper-tas2557-pkg\tas2557_uCDSP_goer.bin',
        'C:\dipper-audio\vendor\firmware\tas2557_uCDSP_goer.bin',
        'C:\Users\Admin\Desktop\tas2557_uCDSP_goer.bin',
        'C:\Users\Admin\Documents\Codex\2026-06-18\8\work\dipper-firmware\firmware_tas2557_uCDSP_goer.bin'
    )
    $FirmwarePath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($FirmwarePath) -or -not (Test-Path -LiteralPath $FirmwarePath)) {
    Write-Error 'Could not find tas2557_uCDSP_goer firmware. Pass -FirmwarePath explicitly.'
}
$FirmwarePath = (Resolve-Path -LiteralPath $FirmwarePath).Path

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

pnputil /enum-devices /instanceid $deviceId /drivers | Out-File -LiteralPath (Join-Path $logDir 'driver-before.txt') -Encoding utf8
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') | Out-File -LiteralPath (Join-Path $logDir 'status-before.txt') -Encoding utf8
reg export 'HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0\Device Parameters' (Join-Path $logDir 'device-parameters-before.reg') /y | Out-Null
reg export $driverRegExportPath (Join-Path $logDir 'driver-class-before.reg') /y | Out-Null

try {
    foreach ($path in $regPath,$driverRegPath) {
        Set-ItemProperty -LiteralPath $path -Name AllowI2cProbe -Type DWord -Value 1
        Set-ItemProperty -LiteralPath $path -Name AllowResetProbe -Type DWord -Value 1
        Set-ItemProperty -LiteralPath $path -Name AllowSoftwareResetProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowSplitReadProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowRawReadProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowI2cWrites -Type DWord -Value 1
        Set-ItemProperty -LiteralPath $path -Name AllowSpeakerPowerUp -Type DWord -Value 1
    }

    pnputil /restart-device $deviceId | Tee-Object -FilePath (Join-Path $logDir 'restart-open-gates.txt')
    Start-Sleep -Seconds 3
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') |
        Out-File -LiteralPath (Join-Path $logDir 'status-after-open-gates.txt') -Encoding utf8

    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'invoke-driver-ioctl.ps1') `
        -Command ValidateFirmware -FirmwarePath $FirmwarePath |
        Tee-Object -FilePath (Join-Path $logDir 'ioctl-validate-firmware.txt')
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') |
        Out-File -LiteralPath (Join-Path $logDir 'status-after-validate-firmware.txt') -Encoding utf8

    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'invoke-driver-ioctl.ps1') `
        -Command SafeStartup |
        Tee-Object -FilePath (Join-Path $logDir 'ioctl-safe-startup-muted.txt')
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') |
        Out-File -LiteralPath (Join-Path $logDir 'status-after-safe-startup-muted.txt') -Encoding utf8

    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'invoke-driver-ioctl.ps1') `
        -Command ForceShutdown |
        Tee-Object -FilePath (Join-Path $logDir 'ioctl-force-shutdown.txt')
} finally {
    foreach ($path in $regPath,$driverRegPath) {
        Set-ItemProperty -LiteralPath $path -Name AllowI2cProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowResetProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowSoftwareResetProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowSplitReadProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowRawReadProbe -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowI2cWrites -Type DWord -Value 0
        Set-ItemProperty -LiteralPath $path -Name AllowSpeakerPowerUp -Type DWord -Value 0
    }

    pnputil /restart-device $deviceId | Tee-Object -FilePath (Join-Path $logDir 'restart-safe-gates.txt')
    Start-Sleep -Seconds 6
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') |
        Out-File -LiteralPath (Join-Path $logDir 'status-final-safe.txt') -Encoding utf8
}

@"
Safe-startup muted test finished.

Firmware used:
$FirmwarePath

Rollback registry:
reg import "$logDir\device-parameters-before.reg"
reg import "$logDir\driver-class-before.reg"
pnputil /restart-device $deviceId

Emergency clear all gates:
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\clear-pgid-probe-gate.ps1" -RestartDevice
"@ | Out-File -LiteralPath (Join-Path $logDir 'rollback-command.txt') -Encoding utf8

Write-Host "Safe-startup muted log: $logDir"
