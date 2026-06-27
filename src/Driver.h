#pragma once

#include <ntddk.h>
#include <wdf.h>
#include <spb.h>
#include <gpio.h>

#define RESHUB_USE_HELPER_ROUTINES
#include <reshub.h>

#include "Public.h"

#define DIPTAS2557_POOL_TAG '755T'

typedef struct _SPB_CONTEXT {
    WDFIOTARGET IoTarget;
    WDFWAITLOCK Lock;
    LARGE_INTEGER ConnectionId;
    NTSTATUS CreateStatus;
    NTSTATUS LockStatus;
    NTSTATUS OpenStatus;
    BOOLEAN Ready;
} SPB_CONTEXT, *PSPB_CONTEXT;

typedef struct _GPIO_CONTEXT {
    WDFIOTARGET IoTarget;
    WDFWAITLOCK Lock;
    LARGE_INTEGER ConnectionId;
    NTSTATUS CreateStatus;
    NTSTATUS LockStatus;
    NTSTATUS OpenStatus;
    BOOLEAN Ready;
} GPIO_CONTEXT, *PGPIO_CONTEXT;

typedef struct _DEVICE_CONTEXT {
    WDFDEVICE Device;
    SPB_CONTEXT Spb;
    GPIO_CONTEXT ResetGpio;
    ULONG CurrentBook;
    ULONG CurrentPage;
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
    NTSTATUS LastProbeStatus;
    NTSTATUS LastResetStatus;
    NTSTATUS LastSoftwareResetStatus;
    NTSTATUS LastResetReadbackStatus;
    NTSTATUS LastAddressWriteStatus;
    NTSTATUS LastDataReadStatus;
    NTSTATUS LastRawReadStatus;
    ULONG LastRawReadValue;
    NTSTATUS LastShutdownStatus;
    NTSTATUS LastSafeStartupStatus;
    NTSTATUS LastSafeUnmuteStatus;
    NTSTATUS LastPrepareHardwareStatus;
    NTSTATUS LastSpbInitializeStatus;
    NTSTATUS LastGpioInitializeStatus;
    ULONG TranslatedResourceCount;
    ULONG I2cResourceCount;
    ULONG GpioResourceCount;
    ULONG LastI2cConnectionIdLow;
    ULONG LastI2cConnectionIdHigh;
    ULONG LastGpioConnectionIdLow;
    ULONG LastGpioConnectionIdHigh;
    BOOLEAN AllowI2cProbe;
    BOOLEAN AllowResetProbe;
    BOOLEAN AllowSoftwareResetProbe;
    BOOLEAN AllowSplitReadProbe;
    BOOLEAN AllowRawReadProbe;
    BOOLEAN AllowSpeakerPowerUp;
    BOOLEAN AllowI2cWrites;
    BOOLEAN ResetLevelAfterPulse;
    BOOLEAN I2cReady;
    BOOLEAN FirmwareLoaded;
    BOOLEAN Powered;
    BOOLEAN Muted;
    PCALLBACK_OBJECT CsAudioCallbackObject;
    PVOID CsAudioCallbackRegistration;
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, DeviceGetContext);

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD Diptas2557EvtDeviceAdd;
EVT_WDF_OBJECT_CONTEXT_CLEANUP Diptas2557EvtDriverContextCleanup;

EVT_WDF_DEVICE_PREPARE_HARDWARE Diptas2557EvtPrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE Diptas2557EvtReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY Diptas2557EvtD0Entry;
EVT_WDF_DEVICE_D0_EXIT Diptas2557EvtD0Exit;
EVT_WDF_DEVICE_SELF_MANAGED_IO_INIT Diptas2557EvtSelfManagedIoInit;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL Diptas2557EvtIoDeviceControl;

NTSTATUS SpbInitialize(_In_ WDFDEVICE Device, _Inout_ PSPB_CONTEXT Spb, _In_ PCM_PARTIAL_RESOURCE_DESCRIPTOR Resource);
VOID SpbDeinitialize(_Inout_ PSPB_CONTEXT Spb);
NTSTATUS SpbWrite(_Inout_ PSPB_CONTEXT Spb, _In_reads_bytes_(Length) const UCHAR* Data, _In_ ULONG Length);
NTSTATUS SpbRead(_Inout_ PSPB_CONTEXT Spb, _Out_writes_bytes_(Length) UCHAR* Data, _In_ ULONG Length);
NTSTATUS SpbWriteRead(_Inout_ PSPB_CONTEXT Spb, _In_reads_bytes_(WriteLength) const UCHAR* WriteData, _In_ ULONG WriteLength, _Out_writes_bytes_(ReadLength) UCHAR* ReadData, _In_ ULONG ReadLength);
NTSTATUS SpbWriteReadSplit(_Inout_ PSPB_CONTEXT Spb, _In_reads_bytes_(WriteLength) const UCHAR* WriteData, _In_ ULONG WriteLength, _Out_writes_bytes_(ReadLength) UCHAR* ReadData, _In_ ULONG ReadLength, _Out_ NTSTATUS* WriteStatus, _Out_ NTSTATUS* ReadStatus);

NTSTATUS GpioInitialize(_In_ WDFDEVICE Device, _Inout_ PGPIO_CONTEXT Gpio, _In_ PCM_PARTIAL_RESOURCE_DESCRIPTOR Resource);
VOID GpioDeinitialize(_Inout_ PGPIO_CONTEXT Gpio);
NTSTATUS GpioWritePin(_Inout_ PGPIO_CONTEXT Gpio, _In_ BOOLEAN High);
NTSTATUS GpioReadPin(_Inout_ PGPIO_CONTEXT Gpio, _Out_ BOOLEAN* High);
NTSTATUS GpioResetPulse(_Inout_ PGPIO_CONTEXT Gpio);

NTSTATUS Tas2557Probe(_Inout_ PDEVICE_CONTEXT Context);
NTSTATUS Tas2557SoftwareResetProbe(_Inout_ PDEVICE_CONTEXT Context);
NTSTATUS Tas2557ForceShutdown(_Inout_ PDEVICE_CONTEXT Context);
NTSTATUS Tas2557SafeStartup(_Inout_ PDEVICE_CONTEXT Context);
NTSTATUS Tas2557SafeUnmute(_Inout_ PDEVICE_CONTEXT Context);
NTSTATUS Tas2557ValidateFirmwareMetadata(_Inout_ PDEVICE_CONTEXT Context, _In_reads_bytes_(Length) const UCHAR* Data, _In_ ULONG Length);
