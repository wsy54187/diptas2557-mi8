param(
    [switch]$SkipHardwarePreconditions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $root 'diptas2557.sln'

foreach ($tool in 'msbuild','inf2cat','signtool') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "$tool is not on PATH. Run this from an EWDK shell after LaunchBuildEnv.cmd and E:\BuildEnv\SetupVSEnv.cmd."
    }
}

if (-not $SkipHardwarePreconditions) {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'assert-safe-install-preconditions.ps1')
}

msbuild $solution /m /p:Configuration=Release /p:Platform=ARM64
if ($LASTEXITCODE -ne 0) {
    throw "msbuild failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Build output:'
Get-ChildItem -Recurse -Path (Join-Path $root 'build\Release\ARM64') -ErrorAction SilentlyContinue |
    Select-Object FullName,Length,LastWriteTime |
    Format-Table -AutoSize
