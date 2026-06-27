#include "Driver.h"

static BOOLEAN
Diptas2557ReadBooleanDeviceValue(
    _In_ WDFDEVICE Device,
    _In_ PCWSTR Name
    )
{
    NTSTATUS status;
    WDFKEY key;
    ULONG value = 0;
    UNICODE_STRING valueName;
    ULONG keyTypes[] = {
        PLUGPLAY_REGKEY_DRIVER,
        PLUGPLAY_REGKEY_DEVICE
    };
    ULONG i;

    RtlInitUnicodeString(&valueName, Name);

    for (i = 0; i < ARRAYSIZE(keyTypes); i++) {
        status = WdfDeviceOpenRegistryKey(
            Device,
            keyTypes[i],
            KEY_QUERY_VALUE,
            WDF_NO_OBJECT_ATTRIBUTES,
            &key);

        if (!NT_SUCCESS(status)) {
            continue;
        }

        status = WdfRegistryQueryULong(key, &valueName, &value);
        WdfRegistryClose(key);
        if (NT_SUCCESS(status)) {
            return value != 0;
        }
    }

    return FALSE;
}

static VOID
Diptas2557ReadSafetyGates(
    _In_ WDFDEVICE Device,
    _Inout_ PDEVICE_CONTEXT Context
    )
{
    Context->AllowI2cProbe = Diptas2557ReadBooleanDeviceValue(Device, L"AllowI2cProbe");
    Context->AllowResetProbe = Diptas2557ReadBooleanDeviceValue(Device, L"AllowResetProbe");
    Context->AllowSoftwareResetProbe = Diptas2557ReadBooleanDeviceValue(Device, L"AllowSoftwareResetProbe");
    Context->AllowSplitReadProbe = Diptas2557ReadBooleanDeviceValue(Device, L"AllowSplitReadProbe");
    Context->AllowRawReadProbe = Diptas2557ReadBooleanDeviceValue(Device, L"AllowRawReadProbe");
    Context->AllowSpeakerPowerUp = Diptas2557ReadBooleanDeviceValue(Device, L"AllowSpeakerPowerUp");
    Context->AllowI2cWrites = Diptas2557ReadBooleanDeviceValue(Device, L"AllowI2cWrites");
}

NTSTATUS
Diptas2557EvtPrepareHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesRaw,
    _In_ WDFCMRESLIST ResourcesTranslated
    )
{
    ULONG i;
    NTSTATUS status = STATUS_DEVICE_CONFIGURATION_ERROR;
    PDEVICE_CONTEXT context = DeviceGetContext(Device);
    PCM_PARTIAL_RESOURCE_DESCRIPTOR i2cResource = NULL;
    PCM_PARTIAL_RESOURCE_DESCRIPTOR gpioResource = NULL;

    UNREFERENCED_PARAMETER(ResourcesRaw);

    Diptas2557ReadSafetyGates(Device, context);
    context->TranslatedResourceCount = WdfCmResourceListGetCount(ResourcesTranslated);
    context->I2cResourceCount = 0;
    context->GpioResourceCount = 0;
    context->LastI2cConnectionIdLow = 0;
    context->LastI2cConnectionIdHigh = 0;
    context->LastGpioConnectionIdLow = 0;
    context->LastGpioConnectionIdHigh = 0;
    context->LastSpbInitializeStatus = STATUS_NOT_FOUND;
    context->LastGpioInitializeStatus = STATUS_NOT_FOUND;
    context->LastPrepareHardwareStatus = STATUS_DEVICE_CONFIGURATION_ERROR;

    for (i = 0; i < WdfCmResourceListGetCount(ResourcesTranslated); i++) {
        PCM_PARTIAL_RESOURCE_DESCRIPTOR resource = WdfCmResourceListGetDescriptor(ResourcesTranslated, i);
        if (resource == NULL) {
            continue;
        }

        if (resource->Type == CmResourceTypeConnection &&
            resource->u.Connection.Class == CM_RESOURCE_CONNECTION_CLASS_SERIAL &&
            resource->u.Connection.Type == CM_RESOURCE_CONNECTION_TYPE_SERIAL_I2C) {
            context->I2cResourceCount++;
            i2cResource = resource;
            context->LastI2cConnectionIdLow = resource->u.Connection.IdLowPart;
            context->LastI2cConnectionIdHigh = resource->u.Connection.IdHighPart;
        } else if (resource->Type == CmResourceTypeConnection &&
            resource->u.Connection.Class == CM_RESOURCE_CONNECTION_CLASS_GPIO &&
            resource->u.Connection.Type == CM_RESOURCE_CONNECTION_TYPE_GPIO_IO) {
            context->GpioResourceCount++;
            gpioResource = resource;
            context->LastGpioConnectionIdLow = resource->u.Connection.IdLowPart;
            context->LastGpioConnectionIdHigh = resource->u.Connection.IdHighPart;
        }
    }

    if (gpioResource != NULL) {
        context->LastResetStatus = GpioInitialize(Device, &context->ResetGpio, gpioResource);
        context->LastGpioInitializeStatus = context->LastResetStatus;
    } else {
        context->LastResetStatus = STATUS_NOT_FOUND;
        context->LastGpioInitializeStatus = STATUS_NOT_FOUND;
    }

    if (i2cResource != NULL) {
        status = SpbInitialize(Device, &context->Spb, i2cResource);
        context->LastSpbInitializeStatus = status;
    }

    context->LastPrepareHardwareStatus = status;
    return status;
}

NTSTATUS
Diptas2557EvtReleaseHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesTranslated
    )
{
    PDEVICE_CONTEXT context = DeviceGetContext(Device);

    UNREFERENCED_PARAMETER(ResourcesTranslated);

    if (context->Spb.Ready) {
        context->LastShutdownStatus = Tas2557ForceShutdown(context);
    }

    SpbDeinitialize(&context->Spb);
    GpioDeinitialize(&context->ResetGpio);
    context->I2cReady = FALSE;
    return STATUS_SUCCESS;
}

NTSTATUS
Diptas2557EvtD0Entry(
    _In_ WDFDEVICE Device,
    _In_ WDF_POWER_DEVICE_STATE PreviousState
    )
{
    PDEVICE_CONTEXT context = DeviceGetContext(Device);

    UNREFERENCED_PARAMETER(PreviousState);

    if (!context->Spb.Ready) {
        return STATUS_DEVICE_NOT_READY;
    }

    if (!context->AllowI2cProbe) {
        context->I2cReady = FALSE;
        context->Powered = FALSE;
        context->Muted = TRUE;
        return STATUS_SUCCESS;
    }

    if (context->AllowResetProbe) {
        context->LastResetStatus = GpioResetPulse(&context->ResetGpio);
        if (!NT_SUCCESS(context->LastResetStatus)) {
            context->I2cReady = FALSE;
            context->Powered = FALSE;
            context->Muted = TRUE;
            return STATUS_SUCCESS;
        }

        context->LastResetReadbackStatus = GpioReadPin(
            &context->ResetGpio,
            &context->ResetLevelAfterPulse);
        if (!NT_SUCCESS(context->LastResetReadbackStatus) ||
            !context->ResetLevelAfterPulse) {
            context->I2cReady = FALSE;
            context->Powered = FALSE;
            context->Muted = TRUE;
            return STATUS_SUCCESS;
        }
    }

    if (context->AllowSoftwareResetProbe) {
        if (!context->AllowResetProbe) {
            context->LastSoftwareResetStatus = STATUS_INVALID_DEVICE_STATE;
            context->I2cReady = FALSE;
            context->Powered = FALSE;
            context->Muted = TRUE;
            return STATUS_SUCCESS;
        }

        context->LastSoftwareResetStatus = Tas2557SoftwareResetProbe(context);
        if (!NT_SUCCESS(context->LastSoftwareResetStatus)) {
            context->I2cReady = FALSE;
            context->Powered = FALSE;
            context->Muted = TRUE;
            return STATUS_SUCCESS;
        }
    }

    if (context->AllowRawReadProbe) {
        UCHAR value = 0;

        context->LastRawReadStatus = SpbRead(&context->Spb, &value, sizeof(value));
        context->LastRawReadValue = value;
        context->LastProbeStatus = context->LastRawReadStatus;
        context->I2cReady = NT_SUCCESS(context->LastRawReadStatus);
        context->Powered = FALSE;
        context->Muted = TRUE;
        return STATUS_SUCCESS;
    }

    return Tas2557Probe(context);
}

NTSTATUS
Diptas2557EvtD0Exit(
    _In_ WDFDEVICE Device,
    _In_ WDF_POWER_DEVICE_STATE TargetState
    )
{
    PDEVICE_CONTEXT context = DeviceGetContext(Device);

    UNREFERENCED_PARAMETER(TargetState);

    if (context->Spb.Ready) {
        context->LastShutdownStatus = Tas2557ForceShutdown(context);
    }

    return STATUS_SUCCESS;
}

NTSTATUS
Diptas2557EvtSelfManagedIoInit(
    _In_ WDFDEVICE Device
    )
{
    UNREFERENCED_PARAMETER(Device);
    return STATUS_SUCCESS;
}

VOID
Diptas2557EvtIoDeviceControl(
    _In_ WDFQUEUE Queue,
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength,
    _In_ ULONG IoControlCode
    )
{
    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;
    WDFDEVICE device = WdfIoQueueGetDevice(Queue);
    PDEVICE_CONTEXT context = DeviceGetContext(device);
    size_t bytes = 0;

    if (IoControlCode == IOCTL_DIPTAS2557_FORCE_SHUTDOWN) {
        status = Tas2557ForceShutdown(context);
        context->LastShutdownStatus = status;
    } else if (IoControlCode == IOCTL_DIPTAS2557_VALIDATE_FIRMWARE) {
        PVOID input;

        if (InputBufferLength > MAXULONG) {
            status = STATUS_INVALID_BUFFER_SIZE;
        } else {
            status = WdfRequestRetrieveInputBuffer(Request, 104, &input, NULL);
            if (NT_SUCCESS(status)) {
                status = Tas2557ValidateFirmwareMetadata(context, (const UCHAR*)input, (ULONG)InputBufferLength);
            }
        }
    } else if (IoControlCode == IOCTL_DIPTAS2557_SAFE_STARTUP) {
        status = Tas2557SafeStartup(context);
        context->LastSafeStartupStatus = status;
        if (!NT_SUCCESS(status)) {
            context->LastShutdownStatus = Tas2557ForceShutdown(context);
        }
    } else if (IoControlCode == IOCTL_DIPTAS2557_SAFE_UNMUTE) {
        status = Tas2557SafeUnmute(context);
        context->LastSafeUnmuteStatus = status;
        if (!NT_SUCCESS(status)) {
            context->LastShutdownStatus = Tas2557ForceShutdown(context);
        }
    } else if (IoControlCode == IOCTL_DIPTAS2557_GET_STATUS) {
        PDIPTAS2557_STATUS output;

        if (OutputBufferLength < sizeof(*output)) {
            status = STATUS_BUFFER_TOO_SMALL;
        } else {
            status = WdfRequestRetrieveOutputBuffer(Request, sizeof(*output), (PVOID*)&output, NULL);
            if (NT_SUCCESS(status)) {
                RtlZeroMemory(output, sizeof(*output));
                output->Size = sizeof(*output);
                output->LastPgid = context->LastPgid;
                output->LastSafeGuard = context->LastSafeGuard;
                output->FirmwareMagic = context->FirmwareMagic;
                output->FirmwareDriverVersion = context->FirmwareDriverVersion;
                output->FirmwareDeviceFamily = context->FirmwareDeviceFamily;
                output->FirmwareDevice = context->FirmwareDevice;
                output->FirmwareProgramCount = context->FirmwareProgramCount;
                output->FirmwareConfigCount = context->FirmwareConfigCount;
                output->FirmwareSafeProgram = context->FirmwareSafeProgram;
                output->FirmwareSafeConfig = context->FirmwareSafeConfig;
                output->LastProbeStatus = (ULONG)context->LastProbeStatus;
                output->LastResetStatus = (ULONG)context->LastResetStatus;
                output->LastSoftwareResetStatus = (ULONG)context->LastSoftwareResetStatus;
                output->LastResetReadbackStatus = (ULONG)context->LastResetReadbackStatus;
                output->AllowI2cProbe = context->AllowI2cProbe;
                output->AllowResetProbe = context->AllowResetProbe;
                output->AllowSoftwareResetProbe = context->AllowSoftwareResetProbe;
                output->ResetGpioReady = context->ResetGpio.Ready;
                output->ResetLevelAfterPulse = context->ResetLevelAfterPulse;
                output->I2cReady = context->I2cReady;
                output->FirmwareLoaded = context->FirmwareLoaded;
                output->AllowSpeakerPowerUp = context->AllowSpeakerPowerUp;
                output->AllowI2cWrites = context->AllowI2cWrites;
                output->Powered = context->Powered;
                output->Muted = context->Muted;
                output->LastAddressWriteStatus = (ULONG)context->LastAddressWriteStatus;
                output->LastDataReadStatus = (ULONG)context->LastDataReadStatus;
                output->AllowSplitReadProbe = context->AllowSplitReadProbe;
                output->AllowRawReadProbe = context->AllowRawReadProbe;
                output->LastRawReadStatus = (ULONG)context->LastRawReadStatus;
                output->LastRawReadValue = context->LastRawReadValue;
                output->LastShutdownStatus = (ULONG)context->LastShutdownStatus;
                output->LastSafeStartupStatus = (ULONG)context->LastSafeStartupStatus;
                output->LastSafeUnmuteStatus = (ULONG)context->LastSafeUnmuteStatus;
                output->LastPrepareHardwareStatus = (ULONG)context->LastPrepareHardwareStatus;
                output->LastSpbInitializeStatus = (ULONG)context->LastSpbInitializeStatus;
                output->LastGpioInitializeStatus = (ULONG)context->LastGpioInitializeStatus;
                output->TranslatedResourceCount = context->TranslatedResourceCount;
                output->I2cResourceCount = context->I2cResourceCount;
                output->GpioResourceCount = context->GpioResourceCount;
                output->LastI2cConnectionIdLow = context->LastI2cConnectionIdLow;
                output->LastI2cConnectionIdHigh = context->LastI2cConnectionIdHigh;
                output->LastGpioConnectionIdLow = context->LastGpioConnectionIdLow;
                output->LastGpioConnectionIdHigh = context->LastGpioConnectionIdHigh;
                output->SpbCreateStatus = (ULONG)context->Spb.CreateStatus;
                output->SpbLockStatus = (ULONG)context->Spb.LockStatus;
                output->SpbOpenStatus = (ULONG)context->Spb.OpenStatus;
                output->GpioCreateStatus = (ULONG)context->ResetGpio.CreateStatus;
                output->GpioLockStatus = (ULONG)context->ResetGpio.LockStatus;
                output->GpioOpenStatus = (ULONG)context->ResetGpio.OpenStatus;
                output->SpbReady = context->Spb.Ready ? 1 : 0;
                output->GpioReady = context->ResetGpio.Ready ? 1 : 0;
                bytes = sizeof(*output);
            }
        }
    }

    WdfRequestCompleteWithInformation(Request, status, bytes);
}
