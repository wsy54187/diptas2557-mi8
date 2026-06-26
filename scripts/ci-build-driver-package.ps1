Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $root 'build\Release\ARM64'
$packageDir = Join-Path $root 'build\package\ARM64'
$ciDir = Join-Path $root 'build\ci'
$infSource = Join-Path $root 'package\diptas2557.inf'
$sysSource = Join-Path $buildDir 'diptas2557.sys'
$infTarget = Join-Path $packageDir 'diptas2557.inf'
$sysTarget = Join-Path $packageDir 'diptas2557.sys'
$catTarget = Join-Path $packageDir 'diptas2557.cat'
$certTarget = Join-Path $packageDir 'diptas2557.cer'

New-Item -ItemType Directory -Force -Path $ciDir | Out-Null

function Find-Tool {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string[]]$Roots
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    foreach ($rootPath in $Roots) {
        if (-not (Test-Path -LiteralPath $rootPath)) {
            continue
        }
        $found = Get-ChildItem -LiteralPath $rootPath -Recurse -Filter $Name -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw "Could not find $Name."
}

$msbuild = Find-Tool -Name 'MSBuild.exe' -Roots @(
    "${env:ProgramFiles}\Microsoft Visual Studio",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio"
)
$inf2cat = Find-Tool -Name 'inf2cat.exe' -Roots @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
    "${env:ProgramFiles}\Windows Kits\10\bin"
)
$signtool = Find-Tool -Name 'signtool.exe' -Roots @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
    "${env:ProgramFiles}\Windows Kits\10\bin"
)

@"
MSBuild:  $msbuild
Inf2Cat:  $inf2cat
SignTool: $signtool
"@ | Tee-Object -FilePath (Join-Path $ciDir 'tool-paths.txt')

& $msbuild (Join-Path $root 'diptas2557.sln') /m /p:Configuration=Release /p:Platform=ARM64 /p:SignMode=Off
if ($LASTEXITCODE -ne 0) {
    throw "MSBuild failed with exit code $LASTEXITCODE"
}

foreach ($path in $infSource,$sysSource) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing input: $path"
    }
}

Remove-Item -LiteralPath $packageDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
Copy-Item -LiteralPath $infSource -Destination $infTarget
Copy-Item -LiteralPath $sysSource -Destination $sysTarget

$infText = Get-Content -LiteralPath $infTarget -Raw
foreach ($gate in 'AllowI2cProbe','AllowResetProbe','AllowSoftwareResetProbe','AllowSplitReadProbe','AllowRawReadProbe','AllowI2cWrites','AllowSpeakerPowerUp') {
    if ($infText -notmatch ('HKR,,\"{0}\",0x00010001,0' -f [regex]::Escape($gate))) {
        throw "Unsafe package INF: $gate must default to 0."
    }
}

$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=Codex diptas2557 test signing' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(3)

Export-Certificate -Cert $cert -FilePath $certTarget | Out-Null
Export-Certificate -Cert $cert -FilePath (Join-Path $ciDir 'diptas2557-testsigning.cer') | Out-Null

& $signtool sign /fd sha256 /sha1 $cert.Thumbprint $sysTarget
if ($LASTEXITCODE -ne 0) {
    throw "signtool failed while signing SYS with exit code $LASTEXITCODE"
}

& $inf2cat /driver:$packageDir /os:10_CO_ARM64
if ($LASTEXITCODE -ne 0) {
    throw "inf2cat failed with exit code $LASTEXITCODE"
}

& $signtool sign /ph /fd sha256 /sha1 $cert.Thumbprint $catTarget
if ($LASTEXITCODE -ne 0) {
    throw "signtool failed while signing CAT with exit code $LASTEXITCODE"
}

Get-ChildItem -LiteralPath $packageDir |
    Select-Object FullName,Length,LastWriteTime |
    Format-Table -AutoSize |
    Out-String |
    Tee-Object -FilePath (Join-Path $ciDir 'package-files.txt')

Get-FileHash -LiteralPath $infTarget,$sysTarget,$catTarget,$certTarget -Algorithm SHA256 |
    Format-Table -AutoSize |
    Out-String |
    Tee-Object -FilePath (Join-Path $ciDir 'package-sha256.txt')

Get-AuthenticodeSignature -LiteralPath $sysTarget,$catTarget |
    Format-List |
    Out-String |
    Tee-Object -FilePath (Join-Path $ciDir 'signatures.txt')
