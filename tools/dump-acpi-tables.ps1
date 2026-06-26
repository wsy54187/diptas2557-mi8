param(
    [string]$OutDir = "$PSScriptRoot\..\..\acpi-dump"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$source = @"
using System;
using System.Runtime.InteropServices;

public static class FirmwareTables
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint EnumSystemFirmwareTables(uint FirmwareTableProviderSignature, IntPtr pFirmwareTableEnumBuffer, uint BufferSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint GetSystemFirmwareTable(uint FirmwareTableProviderSignature, uint FirmwareTableID, IntPtr pFirmwareTableBuffer, uint BufferSize);

    public static uint Tag(string s)
    {
        byte[] b = System.Text.Encoding.ASCII.GetBytes(s);
        if (b.Length != 4) throw new ArgumentException("tag must be 4 ASCII chars");
        return (uint)((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]);
    }

    public static string Untag(uint v)
    {
        char[] c = new char[4];
        c[0] = (char)((v >> 24) & 0xff);
        c[1] = (char)((v >> 16) & 0xff);
        c[2] = (char)((v >> 8) & 0xff);
        c[3] = (char)(v & 0xff);
        return new string(c);
    }
}
"@

Add-Type -TypeDefinition $source

$provider = [FirmwareTables]::Tag('ACPI')
$enumSize = [FirmwareTables]::EnumSystemFirmwareTables($provider, [IntPtr]::Zero, 0)
if ($enumSize -eq 0) {
    throw "EnumSystemFirmwareTables(ACPI) returned no data. Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

$enumPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$enumSize)
try {
    $written = [FirmwareTables]::EnumSystemFirmwareTables($provider, $enumPtr, $enumSize)
    if ($written -eq 0) {
        throw "EnumSystemFirmwareTables(ACPI) failed. Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $ids = New-Object System.Collections.Generic.List[uint32]
    for ($offset = 0; $offset -lt $written; $offset += 4) {
        $ids.Add([uint32][Runtime.InteropServices.Marshal]::ReadInt32($enumPtr, $offset))
    }
}
finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($enumPtr)
}

$summary = @()
foreach ($id in $ids) {
    $sig = [FirmwareTables]::Untag($id)
    $size = [FirmwareTables]::GetSystemFirmwareTable($provider, $id, [IntPtr]::Zero, 0)
    if ($size -eq 0) {
        $summary += [pscustomobject]@{ Signature = $sig; Id = ('0x{0:X8}' -f $id); Size = 0; Path = ''; Status = 'FAILED_SIZE' }
        continue
    }

    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$size)
    try {
        $got = [FirmwareTables]::GetSystemFirmwareTable($provider, $id, $ptr, $size)
        if ($got -eq 0) {
            $summary += [pscustomobject]@{ Signature = $sig; Id = ('0x{0:X8}' -f $id); Size = 0; Path = ''; Status = 'FAILED_READ' }
            continue
        }

        $bytes = New-Object byte[] $got
        [Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, [int]$got)
        $safeSig = ($sig.ToCharArray() | ForEach-Object {
            if ([char]::IsLetterOrDigit($_)) { $_ } else { '_' }
        }) -join ''
        $index = @($summary | Where-Object Signature -eq $sig).Count
        $path = Join-Path $OutDir ('{0}-{1:D2}.aml' -f $safeSig, $index)
        [System.IO.File]::WriteAllBytes($path, $bytes)
        $summary += [pscustomobject]@{ Signature = $sig; Id = ('0x{0:X8}' -f $id); Size = $got; Path = $path; Status = 'OK' }
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}

$summary | Sort-Object Signature,Path | Tee-Object -FilePath (Join-Path $OutDir 'summary.txt')
