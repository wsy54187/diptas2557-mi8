param(
    [switch]$RestartDevice
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Administrator privileges are required.'
}

$deviceId = 'ACPI\TTAS2557\0'
$deviceRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0\Device Parameters'
$driverSubkey = (Get-PnpDeviceProperty -InstanceId $deviceId | Where-Object KeyName -eq 'DEVPKEY_Device_Driver').Data
$driverRegPath = Join-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class' $driverSubkey

foreach ($path in $deviceRegPath,$driverRegPath) {
    Set-ItemProperty -LiteralPath $path -Name AllowI2cProbe -Type DWord -Value 0
    Set-ItemProperty -LiteralPath $path -Name AllowResetProbe -Type DWord -Value 0
    Set-ItemProperty -LiteralPath $path -Name AllowSoftwareResetProbe -Type DWord -Value 0
    Set-ItemProperty -LiteralPath $path -Name AllowSplitReadProbe -Type DWord -Value 0
    Set-ItemProperty -LiteralPath $path -Name AllowRawReadProbe -Type DWord -Value 0
    Set-ItemProperty -LiteralPath $path -Name AllowI2cWrites -Type DWord -Value 0
    Set-ItemProperty -LiteralPath $path -Name AllowSpeakerPowerUp -Type DWord -Value 0
}

if ($RestartDevice) {
    pnputil /restart-device $deviceId
    Start-Sleep -Seconds 2
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1')
} else {
    Write-Host 'PGID/reset probe gates cleared. Device was not restarted.'
}
