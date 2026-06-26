param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('ForceShutdown','ValidateFirmware','SafeStartup','SafeUnmute')]
    [string]$Command,

    [string]$FirmwarePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$interfaceGuid = '{2c0802aa-fe43-4b91-a640-38e2423f8145}'
$interface = $null
for ($attempt = 0; $attempt -lt 10 -and [string]::IsNullOrWhiteSpace($interface); $attempt++) {
    $interface = (
        pnputil /enum-interfaces /class $interfaceGuid |
            Select-String -Pattern '(\\\\\?\\\S+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } |
            Select-Object -First 1
    )
    if ([string]::IsNullOrWhiteSpace($interface)) {
        Start-Sleep -Milliseconds 500
    }
}
if ([string]::IsNullOrWhiteSpace($interface)) {
    Write-Error 'diptas2557 device interface was not found.'
}

$source = @'
using System;
using System.Runtime.InteropServices;

public static class DiptasNativeIo
{
    public const UInt32 GENERIC_READ = 0x80000000;
    public const UInt32 GENERIC_WRITE = 0x40000000;
    public const UInt32 FILE_SHARE_READ = 0x00000001;
    public const UInt32 FILE_SHARE_WRITE = 0x00000002;
    public const UInt32 OPEN_EXISTING = 3;
    public static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateFile(
        string lpFileName,
        UInt32 dwDesiredAccess,
        UInt32 dwShareMode,
        IntPtr lpSecurityAttributes,
        UInt32 dwCreationDisposition,
        UInt32 dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(
        IntPtr hDevice,
        UInt32 dwIoControlCode,
        byte[] lpInBuffer,
        UInt32 nInBufferSize,
        byte[] lpOutBuffer,
        UInt32 nOutBufferSize,
        out UInt32 lpBytesReturned,
        IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@

if (-not ('DiptasNativeIo' -as [type])) {
    Add-Type -TypeDefinition $source
}

function New-Ioctl {
    param([uint32]$Function, [uint32]$Access)
    $fileDeviceDiptas2557 = [uint32]0x8337
    $methodBuffered = [uint32]0
    [uint32](([uint64]$fileDeviceDiptas2557 -shl 16) -bor ([uint64]$Access -shl 14) -bor ([uint64]$Function -shl 2) -bor [uint64]$methodBuffered)
}

$accessRead = [uint32]1
$accessWrite = [uint32]2
$ioctls = @{
    ForceShutdown = New-Ioctl -Function 0x802 -Access $accessWrite
    ValidateFirmware = New-Ioctl -Function 0x803 -Access $accessWrite
    SafeStartup = New-Ioctl -Function 0x804 -Access ($accessRead -bor $accessWrite)
    SafeUnmute = New-Ioctl -Function 0x805 -Access ($accessRead -bor $accessWrite)
}

$inputBytes = [byte[]]::new(0)
if ($Command -eq 'ValidateFirmware') {
    if ([string]::IsNullOrWhiteSpace($FirmwarePath)) {
        Write-Error 'ValidateFirmware requires -FirmwarePath.'
    }
    $resolvedFirmware = Resolve-Path -LiteralPath $FirmwarePath
    $inputBytes = [IO.File]::ReadAllBytes($resolvedFirmware)
}

$handle = [DiptasNativeIo]::CreateFile(
    $interface,
    [DiptasNativeIo]::GENERIC_READ -bor [DiptasNativeIo]::GENERIC_WRITE,
    [DiptasNativeIo]::FILE_SHARE_READ -bor [DiptasNativeIo]::FILE_SHARE_WRITE,
    [IntPtr]::Zero,
    [DiptasNativeIo]::OPEN_EXISTING,
    0,
    [IntPtr]::Zero)
if ($handle -eq [DiptasNativeIo]::INVALID_HANDLE_VALUE) {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "CreateFile failed: $err"
}

try {
    [uint32]$bytes = 0
    $out = [byte[]]::new(4)
    $ok = [DiptasNativeIo]::DeviceIoControl(
        $handle,
        [uint32]$ioctls[$Command],
        $inputBytes,
        [uint32]$inputBytes.Length,
        $out,
        [uint32]$out.Length,
        [ref]$bytes,
        [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    [pscustomobject]@{
        Command = $Command
        Interface = $interface
        Ok = $ok
        Win32Error = $err
        BytesReturned = $bytes
    } | Format-List
    if (-not $ok) {
        exit 1
    }
} finally {
    [void][DiptasNativeIo]::CloseHandle($handle)
}
