param(
    [Parameter(Mandatory = $true)]
    [string]$ParsedJsonPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$parsed = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ParsedJsonPath) -Raw | ConvertFrom-Json

$safeConfig = $parsed.Configs | Select-Object -Index 0
$safeProgram = $parsed.Programs | Select-Object -Index 0

if ($parsed.Header.DeviceFamily -ne 0 -or $parsed.Header.Device -ne 2) {
    throw 'Parsed firmware is not a TAS2557 device-family/device match.'
}

if ($parsed.Header.DriverVersion -ne '0x00000400') {
    throw "Unexpected driver version $($parsed.Header.DriverVersion)"
}

if ($safeProgram.Name -ne 'Tuning Mode') {
    throw "Unexpected safe program name: $($safeProgram.Name)"
}

if ($safeConfig.Name -ne 'configuration_Tuning Mode_48 KHz_s1_0') {
    throw "Unexpected safe config name: $($safeConfig.Name)"
}

if ($safeConfig.SamplingRate -ne 48000) {
    throw "Unexpected safe config sampling rate: $($safeConfig.SamplingRate)"
}

$allowlist = [ordered]@{
    SourceFirmware = $parsed.File
    SourceLength = $parsed.Length
    Magic = '0x35353532'
    Checksum = $parsed.Header.Checksum
    PpcVersion = $parsed.Header.PpcVersion
    FirmwareVersion = $parsed.Header.FwVersion
    DriverVersion = $parsed.Header.DriverVersion
    DdcName = $parsed.Header.DdcName
    Description = $parsed.Header.Description
    DeviceFamily = $parsed.Header.DeviceFamily
    Device = $parsed.Header.Device
    ProgramCount = $parsed.ProgramCount
    ConfigCount = $parsed.ConfigCount
    CalibrationCount = $parsed.CalibrationCount
    SafeProgram = [ordered]@{
        Index = 0
        Name = $safeProgram.Name
        Description = $safeProgram.Description
        AppMode = $safeProgram.AppMode
        Boost = $safeProgram.Boost
    }
    SafeConfig = [ordered]@{
        Index = 0
        Name = $safeConfig.Name
        Description = $safeConfig.Description
        Devices = $safeConfig.Devices
        Program = $safeConfig.Program
        Pll = $safeConfig.Pll
        SamplingRate = $safeConfig.SamplingRate
        PllSrc = $safeConfig.PllSrc
        PllSrcRate = $safeConfig.PllSrcRate
    }
    AllowedBlockTypes = @('0x00000000', '0x00000001', '0x00000003', '0x00000004')
    AllowedOpcodes = @('RegisterWrite', 'Delay', 'BulkWrite')
}

$json = $allowlist | ConvertTo-Json -Depth 8
$out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$json | Out-File -LiteralPath $out -Encoding ASCII
Get-Item -LiteralPath $out | Select-Object FullName,Length,LastWriteTime
