param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PPC_DRIVER_CFGDEV_NONCRC = 0x00000101
$PPC_DRIVER_CRCCHK = 0x00000200
$PPC_DRIVER_CONFDEV = 0x00000300
$PPC_DRIVER_MTPLLSRC = 0x00000400

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$pos = 0

function Need([int]$count) {
    if ($script:pos -gt $script:bytes.Length -or $count -gt ($script:bytes.Length - $script:pos)) {
        throw "Unexpected end of file at offset $script:pos, need $count"
    }
}

function U16BE {
    Need 2
    $v = ([int]$script:bytes[$script:pos] -shl 8) -bor [int]$script:bytes[$script:pos + 1]
    $script:pos += 2
    return $v
}

function U32BE {
    Need 4
    $v = ([uint32]$script:bytes[$script:pos] -shl 24) -bor
         ([uint32]$script:bytes[$script:pos + 1] -shl 16) -bor
         ([uint32]$script:bytes[$script:pos + 2] -shl 8) -bor
         [uint32]$script:bytes[$script:pos + 3]
    $script:pos += 4
    return $v
}

function FixedString([int]$count) {
    Need $count
    $raw = $script:bytes[$script:pos..($script:pos + $count - 1)]
    $script:pos += $count
    $nul = [Array]::IndexOf($raw, [byte]0)
    if ($nul -ge 0) {
        $raw = $raw[0..([Math]::Max(0, $nul - 1))]
    }
    return ([Text.Encoding]::ASCII.GetString($raw)).TrimEnd([char]0)
}

function CString {
    $start = $script:pos
    while ($script:pos -lt $script:bytes.Length -and $script:bytes[$script:pos] -ne 0) {
        $script:pos++
    }
    if ($script:pos -ge $script:bytes.Length) {
        throw "Unterminated string at offset $start"
    }
    $count = $script:pos - $start
    $text = if ($count -gt 0) { [Text.Encoding]::ASCII.GetString($script:bytes[$start..($script:pos - 1)]) } else { '' }
    $script:pos++
    return $text
}

function ParseBlock([string]$owner, [int]$index, [uint32]$driverVersion) {
    $offset = $script:pos
    $type = U32BE
    $checksums = $null
    if ($driverVersion -ge $script:PPC_DRIVER_CRCCHK) {
        Need 4
        $checksums = @{
            PChecksumPresent = $script:bytes[$script:pos]
            PChecksum = $script:bytes[$script:pos + 1]
            YChecksumPresent = $script:bytes[$script:pos + 2]
            YChecksum = $script:bytes[$script:pos + 3]
        }
        $script:pos += 4
    }
    $commands = U32BE
    $dataLen = [int]($commands * 4)
    Need $dataLen
    $dataStart = $script:pos
    $summary = SummarizeCommands $dataStart $commands
    $script:pos += $dataLen
    [pscustomobject]@{
        Owner = $owner
        Index = $index
        Offset = ('0x{0:X}' -f $offset)
        Type = ('0x{0:X8}' -f $type)
        Commands = $commands
        DataBytes = $dataLen
        CommandSummary = $summary
        Checksums = $checksums
    }
}

function SummarizeCommands([int]$dataStart, [int]$commands) {
    $i = 0
    $writes = 0
    $delays = 0
    $bulkWrites = 0
    $unknown = @()
    $maxDelayMs = 0
    $touched = New-Object 'System.Collections.Generic.HashSet[string]'

    while ($i -lt $commands) {
        $base = $dataStart + ($i * 4)
        $book = [int]$script:bytes[$base]
        $page = [int]$script:bytes[$base + 1]
        $offset = [int]$script:bytes[$base + 2]
        $data = [int]$script:bytes[$base + 3]
        $i++

        if ($offset -le 0x7f) {
            $writes++
            [void]$touched.Add(('{0:X2}:{1:X2}' -f $book, $page))
        } elseif ($offset -eq 0x81) {
            $delays++
            $delayMs = ($book -shl 8) + $page
            if ($delayMs -gt $maxDelayMs) {
                $maxDelayMs = $delayMs
            }
        } elseif ($offset -eq 0x85) {
            $bulkWrites++
            if ($i -ge $commands) {
                $unknown += ('truncated-bulk@{0}' -f ($i - 1))
                break
            }

            $len = ($book -shl 8) + $page
            $bulkBase = $dataStart + ($i * 4)
            $bulkBook = [int]$script:bytes[$bulkBase]
            $bulkPage = [int]$script:bytes[$bulkBase + 1]
            [void]$touched.Add(('{0:X2}:{1:X2}' -f $bulkBook, $bulkPage))
            $i++
            if ($len -ge 2) {
                $i += [int]([Math]::Floor(($len - 2) / 4) + 1)
            }
            if ($i -gt $commands) {
                $unknown += ('bulk-overrun@{0}' -f ($i - 1))
                break
            }
        } else {
            $unknown += ('opcode-0x{0:X2}@{1}' -f $offset, ($i - 1))
            break
        }
    }

    [pscustomobject]@{
        RegisterWrites = $writes
        Delays = $delays
        BulkWrites = $bulkWrites
        MaxDelayMs = $maxDelayMs
        UnknownOpcodes = $unknown
        TouchedBookPages = @($touched)
    }
}

function ParseData([string]$owner, [uint32]$driverVersion) {
    $name = FixedString 64
    $description = CString
    $blocks = U16BE
    $items = @()
    for ($i = 0; $i -lt $blocks; $i++) {
        $items += ParseBlock $owner $i $driverVersion
    }
    [pscustomobject]@{
        Name = $name
        Description = $description
        BlockCount = $blocks
        Blocks = $items
    }
}

Need 104
$magic = -join ($bytes[0..3] | ForEach-Object { '{0:X2}' -f $_ })
if ($magic -ne '35353532') {
    throw "Bad TAS2557 magic: $magic"
}
$pos = 4

$header = [ordered]@{}
$header.Size = U32BE
$header.Checksum = ('0x{0:X8}' -f (U32BE))
$header.PpcVersion = ('0x{0:X8}' -f (U32BE))
$driverFwVersion = U32BE
$header.FwVersion = ('0x{0:X8}' -f $driverFwVersion)
$driverVersion = U32BE
$header.DriverVersion = ('0x{0:X8}' -f $driverVersion)
$header.Timestamp = ('0x{0:X8}' -f (U32BE))
$header.DdcName = FixedString 64
$header.Description = CString
$header.DeviceFamily = U32BE
$header.Device = U32BE

$plls = @()
$pllCount = U16BE
for ($i = 0; $i -lt $pllCount; $i++) {
    $name = FixedString 64
    $desc = CString
    $block = ParseBlock "PLL[$i]" 0 $driverVersion
    $plls += [pscustomobject]@{ Name = $name; Description = $desc; Block = $block }
}

$programs = @()
$programCount = U16BE
for ($i = 0; $i -lt $programCount; $i++) {
    $name = FixedString 64
    $desc = CString
    Need 1
    $appMode = $bytes[$pos]
    $pos++
    $boost = U16BE
    $data = ParseData "Program[$i]" $driverVersion
    $programs += [pscustomobject]@{ Name = $name; Description = $desc; AppMode = $appMode; Boost = $boost; Data = $data }
}

$configs = @()
$configCount = U16BE
for ($i = 0; $i -lt $configCount; $i++) {
    $name = FixedString 64
    $desc = CString
    if ($driverVersion -ge $PPC_DRIVER_CONFDEV -or ($driverVersion -ge $PPC_DRIVER_CFGDEV_NONCRC -and $driverVersion -lt $PPC_DRIVER_CRCCHK)) {
        $devices = U16BE
    } else {
        $devices = 1
    }
    Need 2
    $program = $bytes[$pos]
    $pll = $bytes[$pos + 1]
    $pos += 2
    $samplingRate = U32BE
    $pllSrc = $null
    $pllSrcRate = $null
    if ($driverVersion -ge $PPC_DRIVER_MTPLLSRC) {
        Need 1
        $pllSrc = $bytes[$pos]
        $pos++
        $pllSrcRate = U32BE
    }
    $data = ParseData "Config[$i]" $driverVersion
    $configs += [pscustomobject]@{
        Name = $name
        Description = $desc
        Devices = $devices
        Program = $program
        Pll = $pll
        SamplingRate = $samplingRate
        PllSrc = $pllSrc
        PllSrcRate = $pllSrcRate
        Data = $data
    }
}

$calibrations = @()
if ($pos -lt $bytes.Length) {
    $calCount = U16BE
    for ($i = 0; $i -lt $calCount; $i++) {
        $name = FixedString 64
        $desc = CString
        Need 2
        $program = $bytes[$pos]
        $config = $bytes[$pos + 1]
        $pos += 2
        $data = ParseData "Calibration[$i]" $driverVersion
        $calibrations += [pscustomobject]@{ Name = $name; Description = $desc; Program = $program; Config = $config; Data = $data }
    }
}

[pscustomobject]@{
    File = (Resolve-Path -LiteralPath $Path).Path
    Length = $bytes.Length
    ParsedBytes = $pos
    Header = [pscustomobject]$header
    PllCount = $pllCount
    ProgramCount = $programCount
    ConfigCount = $configCount
    CalibrationCount = $calibrations.Count
    Plls = $plls
    Programs = $programs
    Configs = $configs
    Calibrations = $calibrations
} | ConvertTo-Json -Depth 12
