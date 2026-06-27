#include "Driver.h"

NTSTATUS
GpioInitialize(
    _In_ WDFDEVICE Device,
    _Inout_ PGPIO_CONTEXT Gpio,
    _In_ PCM_PARTIAL_RESOURCE_DESCRIPTOR Resource
    )
{
    NTSTATUS status;
    DECLARE_UNICODE_STRING_SIZE(resourcePath, RESOURCE_HUB_PATH_SIZE);
    WDF_OBJECT_ATTRIBUTES targetAttributes;
    WDF_IO_TARGET_OPEN_PARAMS openParams;

    RtlZeroMemory(Gpio, sizeof(*Gpio));

    if (Resource->Type != CmResourceTypeConnection ||
        Resource->u.Connection.Class != CM_RESOURCE_CONNECTION_CLASS_GPIO ||
        Resource->u.Connection.Type != CM_RESOURCE_CONNECTION_TYPE_GPIO_IO) {
        return STATUS_INVALID_PARAMETER;
    }

    Gpio->ConnectionId.LowPart = Resource->u.Connection.IdLowPart;
    Gpio->ConnectionId.HighPart = Resource->u.Connection.IdHighPart;

    RESOURCE_HUB_CREATE_PATH_FROM_ID(
        &resourcePath,
        Gpio->ConnectionId.LowPart,
        Gpio->ConnectionId.HighPart);

    WDF_OBJECT_ATTRIBUTES_INIT(&targetAttributes);
    status = WdfIoTargetCreate(Device, &targetAttributes, &Gpio->IoTarget);
    Gpio->CreateStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = WdfWaitLockCreate(WDF_NO_OBJECT_ATTRIBUTES, &Gpio->Lock);
    Gpio->LockStatus = status;
    if (!NT_SUCCESS(status)) {
        GpioDeinitialize(Gpio);
        return status;
    }

    WDF_IO_TARGET_OPEN_PARAMS_INIT_OPEN_BY_NAME(
        &openParams,
        &resourcePath,
        GENERIC_READ | GENERIC_WRITE);

    openParams.ShareAccess = 0;
    openParams.CreateDisposition = FILE_OPEN;
    openParams.FileAttributes = FILE_ATTRIBUTE_NORMAL;

    status = WdfIoTargetOpen(Gpio->IoTarget, &openParams);
    Gpio->OpenStatus = status;
    if (!NT_SUCCESS(status)) {
        GpioDeinitialize(Gpio);
        return status;
    }

    Gpio->Ready = TRUE;
    return STATUS_SUCCESS;
}

VOID
GpioDeinitialize(
    _Inout_ PGPIO_CONTEXT Gpio
    )
{
    if (Gpio->IoTarget != NULL) {
        WdfIoTargetClose(Gpio->IoTarget);
        WdfObjectDelete(Gpio->IoTarget);
    }

    if (Gpio->Lock != NULL) {
        WdfObjectDelete(Gpio->Lock);
    }

    RtlZeroMemory(Gpio, sizeof(*Gpio));
}

NTSTATUS
GpioWritePin(
    _Inout_ PGPIO_CONTEXT Gpio,
    _In_ BOOLEAN High
    )
{
    NTSTATUS status;
    UCHAR value = High ? 1 : 0;
    WDF_MEMORY_DESCRIPTOR input;
    WDF_REQUEST_SEND_OPTIONS options;

    if (!Gpio->Ready) {
        return STATUS_DEVICE_NOT_READY;
    }

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&input, &value, sizeof(value));
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(250));

    WdfWaitLockAcquire(Gpio->Lock, NULL);
    status = WdfIoTargetSendIoctlSynchronously(
        Gpio->IoTarget,
        NULL,
        IOCTL_GPIO_WRITE_PINS,
        &input,
        NULL,
        &options,
        NULL);
    WdfWaitLockRelease(Gpio->Lock);

    return status;
}

NTSTATUS
GpioReadPin(
    _Inout_ PGPIO_CONTEXT Gpio,
    _Out_ BOOLEAN* High
    )
{
    NTSTATUS status;
    UCHAR value = 0;
    WDF_MEMORY_DESCRIPTOR output;
    WDF_REQUEST_SEND_OPTIONS options;

    if (!Gpio->Ready || High == NULL) {
        return STATUS_DEVICE_NOT_READY;
    }

    *High = FALSE;
    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&output, &value, sizeof(value));
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(250));

    WdfWaitLockAcquire(Gpio->Lock, NULL);
    status = WdfIoTargetSendIoctlSynchronously(
        Gpio->IoTarget,
        NULL,
        IOCTL_GPIO_READ_PINS,
        NULL,
        &output,
        &options,
        NULL);
    WdfWaitLockRelease(Gpio->Lock);

    if (NT_SUCCESS(status)) {
        *High = (value & 1u) != 0;
    }

    return status;
}

NTSTATUS
GpioResetPulse(
    _Inout_ PGPIO_CONTEXT Gpio
    )
{
    NTSTATUS status;
    LARGE_INTEGER interval;

    status = GpioWritePin(Gpio, FALSE);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    interval.QuadPart = -10 * 5000;
    KeDelayExecutionThread(KernelMode, FALSE, &interval);

    status = GpioWritePin(Gpio, TRUE);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    /*
     * The Android driver uses a 2 ms minimum release delay. Recovery logs
     * show the working Linux I2C controller has already been active for about
     * 367 ms before the first TAS2557 register transaction. Keep the reset
     * pulse unchanged, but give the Windows qci2c D0 path a bounded 400 ms
     * stabilization window before the first diagnostic transfer.
     */
    interval.QuadPart = -10 * 400000;
    KeDelayExecutionThread(KernelMode, FALSE, &interval);
    return STATUS_SUCCESS;
}
