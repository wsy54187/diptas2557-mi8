#pragma once

#include <guiddef.h>

// {2C0802AA-FE43-4B91-A640-38E2423F8145}
DEFINE_GUID(GUID_DEVINTERFACE_DIPTAS2557,
    0x2c0802aa, 0xfe43, 0x4b91, 0xa6, 0x40, 0x38, 0xe2, 0x42, 0x3f, 0x81, 0x45);

#define FILE_DEVICE_DIPTAS2557 0x8337

#define IOCTL_DIPTAS2557_GET_STATUS \
    CTL_CODE(FILE_DEVICE_DIPTAS2557, 0x801, METHOD_BUFFERED, FILE_READ_DATA)

#define IOCTL_DIPTAS2557_FORCE_SHUTDOWN \
    CTL_CODE(FILE_DEVICE_DIPTAS2557, 0x802, METHOD_BUFFERED, FILE_WRITE_DATA)

#define IOCTL_DIPTAS2557_VALIDATE_FIRMWARE \
    CTL_CODE(FILE_DEVICE_DIPTAS2557, 0x803, METHOD_BUFFERED, FILE_WRITE_DATA)

#define IOCTL_DIPTAS2557_SAFE_STARTUP \
    CTL_CODE(FILE_DEVICE_DIPTAS2557, 0x804, METHOD_BUFFERED, FILE_READ_DATA | FILE_WRITE_DATA)

#define IOCTL_DIPTAS2557_SAFE_UNMUTE \
    CTL_CODE(FILE_DEVICE_DIPTAS2557, 0x805, METHOD_BUFFERED, FILE_READ_DATA | FILE_WRITE_DATA)

typedef struct _DIPTAS2557_STATUS {
    ULONG Size;
    ULONG LastPgid;
    ULONG LastSafeGuard;
    ULONG FirmwareMagic;
    ULONG FirmwareDriverVersion;
    ULONG FirmwareDeviceFamily;
    ULONG FirmwareDevice;
    ULONG FirmwareProgramCount;
    ULONG FirmwareConfigCount;
    ULONG FirmwareSafeProgram;
    ULONG FirmwareSafeConfig;
    ULONG LastProbeStatus;
    ULONG LastResetStatus;
    ULONG LastSoftwareResetStatus;
    ULONG LastResetReadbackStatus;
    BOOLEAN AllowI2cProbe;
    BOOLEAN AllowResetProbe;
    BOOLEAN AllowSoftwareResetProbe;
    BOOLEAN ResetGpioReady;
    BOOLEAN ResetLevelAfterPulse;
    BOOLEAN AllowResetReadbackBypass;
    BOOLEAN ResetPulseActiveHigh;
    BOOLEAN I2cReady;
    BOOLEAN FirmwareLoaded;
    BOOLEAN AllowSpeakerPowerUp;
    BOOLEAN AllowI2cWrites;
    BOOLEAN Powered;
    BOOLEAN Muted;
    ULONG LastAddressWriteStatus;
    ULONG LastDataReadStatus;
    BOOLEAN AllowSplitReadProbe;
    BOOLEAN AllowRawReadProbe;
    ULONG LastRawReadStatus;
    ULONG LastRawReadValue;
    ULONG LastShutdownStatus;
    ULONG LastSafeStartupStatus;
    ULONG LastSafeUnmuteStatus;
    ULONG LastPrepareHardwareStatus;
    ULONG LastSpbInitializeStatus;
    ULONG LastGpioInitializeStatus;
    ULONG TranslatedResourceCount;
    ULONG I2cResourceCount;
    ULONG GpioResourceCount;
    ULONG LastI2cConnectionIdLow;
    ULONG LastI2cConnectionIdHigh;
    ULONG LastGpioConnectionIdLow;
    ULONG LastGpioConnectionIdHigh;
    ULONG SpbCreateStatus;
    ULONG SpbLockStatus;
    ULONG SpbOpenStatus;
    ULONG GpioCreateStatus;
    ULONG GpioLockStatus;
    ULONG GpioOpenStatus;
    ULONG SpbReady;
    ULONG GpioReady;
} DIPTAS2557_STATUS, *PDIPTAS2557_STATUS;
