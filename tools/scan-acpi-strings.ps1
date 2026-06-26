param(
    [string]$AcpiDir = "$PSScriptRoot\..\..\acpi-dump"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$patterns = @(
    'TAS',
    '2557',
    'TTAS',
    'AFLT',
    'I2C4',
    'I2C5',
    'I2C6',
    'IC11',
    'IC15',
    'QCOM0220',
    'QCOM0217',
    'QCOM0269',
    'QCOM0262',
    'WCD',
    '9340',
    'GPIO',
    'GIO'
)

foreach ($file in Get-ChildItem -Path $AcpiDir -Filter *.aml -File) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $ascii = -join ($bytes | ForEach-Object {
        if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { "`n" }
    })

    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($ascii, [regex]::Escape($pattern), 'IgnoreCase')
        foreach ($m in $matches) {
            $start = [Math]::Max(0, $m.Index - 48)
            $len = [Math]::Min(120, $ascii.Length - $start)
            $snippet = $ascii.Substring($start, $len) -replace '\s+', ' '
            [pscustomobject]@{
                File = $file.Name
                Pattern = $pattern
                Offset = $m.Index
                Snippet = $snippet
            }
        }
    }
}
