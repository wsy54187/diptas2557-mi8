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

public static class NativeIo
{
    public const UInt32 GENERIC_READ = 0x80000000;
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
        IntPtr lpInBuffer,
        UInt32 nInBufferSize,
        byte[] lpOutBuffer,
        UInt32 nOutBufferSize,
        out UInt32 lpBytesReturned,
        IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@

if (-not ('NativeIo' -as [type])) {
    Add-Type -TypeDefinition $source
}

function Get-U32 {
    param([byte[]]$Buffer, [int]$Offset)
    [BitConverter]::ToUInt32($Buffer, $Offset)
}

$fileDeviceDiptas2557 = 0x8337
$function = 0x801
$methodBuffered = 0
$fileReadData = 1
$ioctlGetStatus = [uint32](([uint64]$fileDeviceDiptas2557 -shl 16) -bor ([uint64]$fileReadData -shl 14) -bor ([uint64]$function -shl 2) -bor [uint64]$methodBuffered)

$handle = [NativeIo]::CreateFile($interface, [NativeIo]::GENERIC_READ, [NativeIo]::FILE_SHARE_READ -bor [NativeIo]::FILE_SHARE_WRITE, [IntPtr]::Zero, [NativeIo]::OPEN_EXISTING, 0, [IntPtr]::Zero)
if ($handle -eq [NativeIo]::INVALID_HANDLE_VALUE) {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "CreateFile failed: $err"
}

try {
    $out = New-Object byte[] 192
    [uint32]$bytes = 0
    $ok = [NativeIo]::DeviceIoControl($handle, [uint32]$ioctlGetStatus, [IntPtr]::Zero, 0, $out, [uint32]$out.Length, [ref]$bytes, [IntPtr]::Zero)
    if (-not $ok) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Error "DeviceIoControl(GET_STATUS) failed: $err"
    }

    $status = [ordered]@{
        Interface = $interface
        BytesReturned = $bytes
        Size = Get-U32 $out 0
        LastPgid = ('0x{0:X8}' -f (Get-U32 $out 4))
        LastSafeGuard = ('0x{0:X8}' -f (Get-U32 $out 8))
        FirmwareMagic = ('0x{0:X8}' -f (Get-U32 $out 12))
        FirmwareDriverVersion = ('0x{0:X8}' -f (Get-U32 $out 16))
        FirmwareDeviceFamily = Get-U32 $out 20
        FirmwareDevice = Get-U32 $out 24
        FirmwareProgramCount = Get-U32 $out 28
        FirmwareConfigCount = Get-U32 $out 32
        FirmwareSafeProgram = Get-U32 $out 36
        FirmwareSafeConfig = Get-U32 $out 40
        LastProbeStatus = ('0x{0:X8}' -f (Get-U32 $out 44))
    }

    if ($bytes -ge 72) {
        $status.LastResetStatus = ('0x{0:X8}' -f (Get-U32 $out 48))
        $status.LastSoftwareResetStatus = ('0x{0:X8}' -f (Get-U32 $out 52))
        $status.LastResetReadbackStatus = ('0x{0:X8}' -f (Get-U32 $out 56))
        $status.AllowI2cProbe = [bool]$out[60]
        $status.AllowResetProbe = [bool]$out[61]
        $status.AllowSoftwareResetProbe = [bool]$out[62]
        $status.ResetGpioReady = [bool]$out[63]
        $status.ResetLevelAfterPulse = [bool]$out[64]
        $status.I2cReady = [bool]$out[65]
        $status.FirmwareLoaded = [bool]$out[66]
        $status.AllowSpeakerPowerUp = [bool]$out[67]
        $status.AllowI2cWrites = [bool]$out[68]
        $status.Powered = [bool]$out[69]
        $status.Muted = [bool]$out[70]
        $postBoolOffset = 72
        if ($bytes -ge 180) {
            $status.AllowResetReadbackBypass = [bool]$out[65]
            $status.ResetPulseActiveHigh = [bool]$out[66]
            $status.I2cReady = [bool]$out[67]
            $status.FirmwareLoaded = [bool]$out[68]
            $status.AllowSpeakerPowerUp = [bool]$out[69]
            $status.AllowI2cWrites = [bool]$out[70]
            $status.Powered = [bool]$out[71]
            $status.Muted = [bool]$out[72]
            $postBoolOffset = 76
        }
        if ($bytes -ge ($postBoolOffset + 12)) {
            $status.LastAddressWriteStatus = ('0x{0:X8}' -f (Get-U32 $out $postBoolOffset))
            $status.LastDataReadStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 4)))
            $status.AllowSplitReadProbe = [bool]$out[$postBoolOffset + 8]
            if ($bytes -ge ($postBoolOffset + 20)) {
                $status.AllowRawReadProbe = [bool]$out[$postBoolOffset + 9]
                $status.LastRawReadStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 12)))
                $status.LastRawReadValue = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 16)))
                if ($bytes -ge ($postBoolOffset + 32)) {
                    $status.LastShutdownStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 20)))
                    $status.LastSafeStartupStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 24)))
                    $status.LastSafeUnmuteStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 28)))
                    if ($bytes -ge ($postBoolOffset + 104)) {
                        $status.LastPrepareHardwareStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 32)))
                        $status.LastSpbInitializeStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 36)))
                        $status.LastGpioInitializeStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 40)))
                        $status.TranslatedResourceCount = Get-U32 $out ($postBoolOffset + 44)
                        $status.I2cResourceCount = Get-U32 $out ($postBoolOffset + 48)
                        $status.GpioResourceCount = Get-U32 $out ($postBoolOffset + 52)
                        $status.LastI2cConnectionIdLow = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 56)))
                        $status.LastI2cConnectionIdHigh = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 60)))
                        $status.LastGpioConnectionIdLow = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 64)))
                        $status.LastGpioConnectionIdHigh = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 68)))
                        $status.SpbCreateStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 72)))
                        $status.SpbLockStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 76)))
                        $status.SpbOpenStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 80)))
                        $status.GpioCreateStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 84)))
                        $status.GpioLockStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 88)))
                        $status.GpioOpenStatus = ('0x{0:X8}' -f (Get-U32 $out ($postBoolOffset + 92)))
                        $status.SpbReady = [bool](Get-U32 $out ($postBoolOffset + 96))
                        $status.GpioReady = [bool](Get-U32 $out ($postBoolOffset + 100))
                    }
                }
            }
        }
    } elseif ($bytes -ge 66) {
        $status.LastResetStatus = ('0x{0:X8}' -f (Get-U32 $out 48))
        $status.LastSoftwareResetStatus = ('0x{0:X8}' -f (Get-U32 $out 52))
        $status.AllowI2cProbe = [bool]$out[56]
        $status.AllowResetProbe = [bool]$out[57]
        $status.AllowSoftwareResetProbe = [bool]$out[58]
        $status.ResetGpioReady = [bool]$out[59]
        $status.I2cReady = [bool]$out[60]
        $status.FirmwareLoaded = [bool]$out[61]
        $status.AllowSpeakerPowerUp = [bool]$out[62]
        $status.AllowI2cWrites = [bool]$out[63]
        $status.Powered = [bool]$out[64]
        $status.Muted = [bool]$out[65]
    } elseif ($bytes -ge 61) {
        $status.LastResetStatus = ('0x{0:X8}' -f (Get-U32 $out 48))
        $status.AllowI2cProbe = [bool]$out[52]
        $status.AllowResetProbe = [bool]$out[53]
        $status.ResetGpioReady = [bool]$out[54]
        $status.I2cReady = [bool]$out[55]
        $status.FirmwareLoaded = [bool]$out[56]
        $status.AllowSpeakerPowerUp = [bool]$out[57]
        $status.AllowI2cWrites = [bool]$out[58]
        $status.Powered = [bool]$out[59]
        $status.Muted = [bool]$out[60]
    } else {
        $status.AllowI2cProbe = [bool]$out[48]
        $status.I2cReady = [bool]$out[49]
        $status.FirmwareLoaded = [bool]$out[50]
        $status.AllowSpeakerPowerUp = [bool]$out[51]
        $status.AllowI2cWrites = [bool]$out[52]
        $status.Powered = [bool]$out[53]
        $status.Muted = [bool]$out[54]
        $status.StatusLayout = 'legacy-0.1.2'
    }

    [pscustomobject]$status | Format-List
} finally {
    [void][NativeIo]::CloseHandle($handle)
}
