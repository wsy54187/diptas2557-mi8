Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent (Split-Path -Parent $root)
$out = Join-Path $workspace 'outputs\dipper-tas2557-driver-source.zip'

if (Test-Path $out) {
    Remove-Item -LiteralPath $out -Force
}

Compress-Archive -Path (Join-Path $root '*') -DestinationPath $out -Force
Get-Item $out | Select-Object FullName,Length,LastWriteTime
