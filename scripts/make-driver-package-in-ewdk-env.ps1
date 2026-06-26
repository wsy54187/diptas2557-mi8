Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $root 'build\Release\ARM64'
$packageDir = Join-Path $root 'build\package\ARM64'
$infSource = Join-Path $root 'package\diptas2557.inf'
$sysSource = Join-Path $buildDir 'diptas2557.sys'
$certSource = Join-Path $buildDir 'diptas2557.cer'
$infTarget = Join-Path $packageDir 'diptas2557.inf'
$sysTarget = Join-Path $packageDir 'diptas2557.sys'
$catTarget = Join-Path $packageDir 'diptas2557.cat'
$certTarget = Join-Path $packageDir 'diptas2557.cer'

foreach ($tool in 'inf2cat','signtool') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "$tool is not on PATH. Run this from the EWDK environment."
    }
}

foreach ($path in $infSource,$sysSource,$certSource) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "Missing input: $path"
    }
}

Remove-Item -LiteralPath $packageDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
Copy-Item -LiteralPath $infSource -Destination $infTarget
Copy-Item -LiteralPath $sysSource -Destination $sysTarget
Copy-Item -LiteralPath $certSource -Destination $certTarget

$infText = Get-Content -LiteralPath $infTarget -Raw
foreach ($gate in 'AllowI2cProbe','AllowResetProbe','AllowSoftwareResetProbe','AllowSplitReadProbe','AllowRawReadProbe','AllowI2cWrites','AllowSpeakerPowerUp') {
    if ($infText -notmatch ('HKR,,\"{0}\",0x00010001,0' -f [regex]::Escape($gate))) {
        Write-Error "Unsafe package INF: $gate must default to 0."
    }
}

inf2cat /driver:$packageDir /os:10_CO_ARM64
if ($LASTEXITCODE -ne 0) {
    throw "inf2cat failed with exit code $LASTEXITCODE"
}

$thumbprint = (Get-AuthenticodeSignature -LiteralPath $sysSource).SignerCertificate.Thumbprint
if ([string]::IsNullOrWhiteSpace($thumbprint)) {
    Write-Error 'Could not read test-signing certificate thumbprint from built SYS.'
}

signtool sign /ph /fd sha256 /sha1 $thumbprint $catTarget
if ($LASTEXITCODE -ne 0) {
    throw "signtool failed with exit code $LASTEXITCODE"
}

Get-ChildItem -LiteralPath $packageDir |
    Select-Object FullName,Length,LastWriteTime |
    Format-Table -AutoSize

Write-Host ''
Write-Host 'Package hashes:'
Get-FileHash -LiteralPath $infTarget,$sysTarget,$catTarget -Algorithm SHA256 |
    Format-Table -AutoSize
