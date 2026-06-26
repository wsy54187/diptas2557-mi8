param(
    [string]$PackageDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\package\ARM64')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Administrator privileges are required.'
}

$deviceId = 'ACPI\TTAS2557\0'
$expectedVersion = '0.1.12.0'
$packageDirResolved = Resolve-Path -LiteralPath $PackageDir
$infPath = Join-Path $packageDirResolved 'diptas2557.inf'
$sysPath = Join-Path $packageDirResolved 'diptas2557.sys'
$catPath = Join-Path $packageDirResolved 'diptas2557.cat'

foreach ($path in $infPath,$sysPath,$catPath) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "Missing package file: $path"
    }
}

$infText = Get-Content -LiteralPath $infPath -Raw
if ($infText -notmatch 'DriverVer\s*=\s*06/26/2026\s*,\s*0\.1\.12\.0') {
    Write-Error 'Refusing to install: INF is not diptas2557 0.1.12.0.'
}
foreach ($gate in 'AllowI2cProbe','AllowResetProbe','AllowSoftwareResetProbe','AllowSplitReadProbe','AllowRawReadProbe','AllowI2cWrites','AllowSpeakerPowerUp') {
    if ($infText -notmatch ('HKR,,\"{0}\",0x00010001,0' -f [regex]::Escape($gate))) {
        Write-Error "Refusing to install: unsafe INF default for $gate."
    }
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "C:\dipper-audio\diptas2557-012-install-backup-$ts"
New-Item -ItemType Directory -Force -Path $backup | Out-Null

pnputil /enum-devices /instanceid $deviceId /drivers |
    Out-File -LiteralPath (Join-Path $backup 'drivers-before.txt') -Encoding utf8

try {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') |
        Out-File -LiteralPath (Join-Path $backup 'status-before.txt') -Encoding utf8
} catch {
    $_ | Out-File -LiteralPath (Join-Path $backup 'status-before-error.txt') -Encoding utf8
}

reg export 'HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0' (Join-Path $backup 'ttas2557-root-before.reg') /y | Out-Null
reg export 'HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0\Device Parameters' (Join-Path $backup 'ttas2557-device-parameters-before.reg') /y | Out-Null
$driverSubkeyBefore = (Get-PnpDeviceProperty -InstanceId $deviceId | Where-Object KeyName -eq 'DEVPKEY_Device_Driver').Data
if (-not [string]::IsNullOrWhiteSpace($driverSubkeyBefore)) {
    reg export "HKLM\SYSTEM\CurrentControlSet\Control\Class\$driverSubkeyBefore" (Join-Path $backup 'ttas2557-class-before.reg') /y | Out-Null
}
reg export 'HKLM\SYSTEM\CurrentControlSet\Services\diptas2557' (Join-Path $backup 'diptas2557-service-before.reg') /y | Out-Null

pnputil /add-driver $infPath /install |
    Tee-Object -FilePath (Join-Path $backup 'pnputil-add-driver.txt')

$pnputilExit = $LASTEXITCODE
if ($pnputilExit -ne 0 -and $pnputilExit -ne 3010 -and $pnputilExit -ne 259) {
    throw "pnputil failed with exit code $pnputilExit"
}

$gates = @(
    'AllowI2cProbe',
    'AllowResetProbe',
    'AllowSoftwareResetProbe',
    'AllowSplitReadProbe',
    'AllowRawReadProbe',
    'AllowI2cWrites',
    'AllowSpeakerPowerUp'
)

$driverSubkey = (Get-PnpDeviceProperty -InstanceId $deviceId | Where-Object KeyName -eq 'DEVPKEY_Device_Driver').Data
$paths = @(
    'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0',
    'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\TTAS2557\0\Device Parameters'
)
if (-not [string]::IsNullOrWhiteSpace($driverSubkey)) {
    $paths += (Join-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class' $driverSubkey)
}

foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
        foreach ($gate in $gates) {
            New-ItemProperty -LiteralPath $path -Name $gate -PropertyType DWord -Value 0 -Force | Out-Null
        }
    }
}

sc.exe config diptas2557 start= demand |
    Out-File -LiteralPath (Join-Path $backup 'sc-config-diptas2557.txt') -Encoding utf8

pnputil /restart-device $deviceId |
    Tee-Object -FilePath (Join-Path $backup 'pnputil-restart-device.txt')
Start-Sleep -Seconds 6

pnputil /enum-devices /instanceid $deviceId /drivers |
    Out-File -LiteralPath (Join-Path $backup 'drivers-after.txt') -Encoding utf8

$statusText = powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'query-driver-status.ps1') | Out-String
$statusText | Out-File -LiteralPath (Join-Path $backup 'status-after.txt') -Encoding utf8

$driverInfo = pnputil /enum-devices /instanceid $deviceId /drivers | Out-String
if ($driverInfo -notmatch [regex]::Escape($expectedVersion)) {
    Write-Error "0.1.12.0 is not the bound driver. See $backup\drivers-after.txt"
}
if ($statusText -notmatch 'AllowI2cWrites\s+:\s+False' -or
    $statusText -notmatch 'AllowSpeakerPowerUp\s+:\s+False' -or
    $statusText -notmatch 'Powered\s+:\s+False' -or
    $statusText -notmatch 'Muted\s+:\s+True') {
    Write-Error "Unsafe final status. See $backup\status-after.txt"
}

@"
Rollback 0.1.12 bind-only install:

reg import "$backup\ttas2557-root-before.reg"
reg import "$backup\ttas2557-device-parameters-before.reg"
reg import "$backup\ttas2557-class-before.reg"
reg import "$backup\diptas2557-service-before.reg"
pnputil /restart-device $deviceId
"@ | Out-File -LiteralPath (Join-Path $backup 'rollback-command.txt') -Encoding utf8

Write-Host "diptas2557 0.1.12 bind-only install completed safely."
Write-Host "Backup: $backup"
