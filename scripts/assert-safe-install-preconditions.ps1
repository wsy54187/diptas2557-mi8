Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$inf = Join-Path $root 'package\diptas2557.inf'

if (-not (Test-Path -LiteralPath $inf)) {
    Write-Error "Missing INF: $inf"
}

$infText = Get-Content -LiteralPath $inf -Raw
foreach ($gate in 'AllowI2cProbe','AllowResetProbe','AllowSoftwareResetProbe','AllowSplitReadProbe','AllowRawReadProbe','AllowI2cWrites','AllowSpeakerPowerUp') {
    if ($infText -notmatch ('HKR,,\"{0}\",0x00010001,0' -f [regex]::Escape($gate))) {
        Write-Error "Unsafe or missing default registry gate in INF: $gate must default to 0."
    }
}

$blockedServices = @(
    'tas2557','tas2559','tas256','tas256x','audfilter' |
        ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue }
)
if ($blockedServices.Count -gt 0) {
    $blockedServices | Select-Object Name,Status | Format-Table -AutoSize
    Write-Error 'Refusing to proceed because a TAS/AudFilter-style service already exists.'
}

$tasDevices = @(Get-PnpDevice -InstanceId 'ACPI\TTAS2557\0' -ErrorAction SilentlyContinue)

if ($tasDevices.Count -eq 0) {
    Write-Error @'
No TAS2557 ACPI/PnP device is present.

Refusing to proceed. A safe install requires a verified TAS2557 ACPI child node
with an SPB/I2C resource, I2C address 0x4c, and IRQ GPIO 30.

The first-stage overlay must expose only the verified TAS2557 resources needed
for the selected experiment. Reset GPIO 76 is permitted only with the separate
AllowResetProbe gate. Speaker-id GPIO 27 must remain absent.

Do not install diptas2557.sys against a guessed or missing hardware node.
'@
}

$tasDevices | Format-Table Status,Class,FriendlyName,InstanceId,Problem -AutoSize

Write-Host ''
Write-Host 'Safety gate defaults verified:'
Write-Host '  AllowI2cProbe      = 0'
Write-Host '  AllowResetProbe    = 0'
Write-Host '  AllowSoftwareResetProbe = 0'
Write-Host '  AllowSplitReadProbe = 0'
Write-Host '  AllowRawReadProbe   = 0'
Write-Host '  AllowI2cWrites     = 0'
Write-Host '  AllowSpeakerPowerUp= 0'
Write-Host ''
Write-Host 'First install stage is bind-only: no TAS2557 I2C bus access, no register writes, no startup, no unmute.'
