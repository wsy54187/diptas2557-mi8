param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolved = Resolve-Path -LiteralPath $Path
$bytes = [System.IO.File]::ReadAllBytes($resolved.Path)
if ($bytes.Length -lt 32) {
    throw "Firmware is too small: $($bytes.Length) bytes"
}

$magic = ($bytes[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
$expected = '35 35 35 32'

[pscustomobject][ordered]@{
    Path = $resolved.Path
    Length = $bytes.Length
    Magic = $magic
    MagicOk = ($magic -eq $expected)
    HeaderHex = (($bytes[0..31] | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

if ($magic -ne $expected) {
    exit 2
}
