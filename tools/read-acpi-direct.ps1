param(
    [string]$OutDir = "$PSScriptRoot\..\..\acpi-direct"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$source = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class FirmwareTableDirect
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint GetSystemFirmwareTable(uint provider, uint id, IntPtr buffer, uint size);

    public static uint TagBE(string s)
    {
        byte[] b = Encoding.ASCII.GetBytes(s);
        return (uint)((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]);
    }

    public static uint TagLE(string s)
    {
        byte[] b = Encoding.ASCII.GetBytes(s);
        return (uint)(b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24));
    }
}
"@

Add-Type -TypeDefinition $source

$providers = @(
    @{ Name = 'ACPI-BE'; Value = [FirmwareTableDirect]::TagBE('ACPI') },
    @{ Name = 'ACPI-LE'; Value = [FirmwareTableDirect]::TagLE('ACPI') }
)

$names = 'DSDT','SSDT','XSDT','RSDT','FACP','APIC','DBG2','IORT','PPTT'
$rows = @()

foreach ($provider in $providers) {
    foreach ($name in $names) {
        foreach ($mode in 'BE','LE') {
            $id = if ($mode -eq 'BE') { [FirmwareTableDirect]::TagBE($name) } else { [FirmwareTableDirect]::TagLE($name) }
            $size = [FirmwareTableDirect]::GetSystemFirmwareTable($provider.Value, $id, [IntPtr]::Zero, 0)
            if ($size -eq 0) {
                $rows += [pscustomobject]@{
                    Provider = $provider.Name
                    Name = $name
                    Mode = $mode
                    Id = ('0x{0:X8}' -f $id)
                    Size = 0
                    Header = ''
                    Path = ''
                }
                continue
            }

            $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$size)
            try {
                $got = [FirmwareTableDirect]::GetSystemFirmwareTable($provider.Value, $id, $ptr, $size)
                $bytes = New-Object byte[] $got
                [Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, [int]$got)
                $header = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(4, $bytes.Length))
                $file = Join-Path $OutDir ('{0}-{1}-{2}.aml' -f $name, $provider.Name, $mode)
                [IO.File]::WriteAllBytes($file, $bytes)
                $rows += [pscustomobject]@{
                    Provider = $provider.Name
                    Name = $name
                    Mode = $mode
                    Id = ('0x{0:X8}' -f $id)
                    Size = $got
                    Header = $header
                    Path = $file
                }
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
            }
        }
    }
}

$rows | Tee-Object -FilePath (Join-Path $OutDir 'direct-summary.txt')
