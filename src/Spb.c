#include "Driver.h"

NTSTATUS
SpbInitialize(
    _In_ WDFDEVICE Device,
    _Inout_ PSPB_CONTEXT Spb,
    _In_ PCM_PARTIAL_RESOURCE_DESCRIPTOR Resource
    )
{
    NTSTATUS status;
    DECLARE_UNICODE_STRING_SIZE(resourcePath, RESOURCE_HUB_PATH_SIZE);
    WDF_OBJECT_ATTRIBUTES targetAttributes;
    WDF_IO_TARGET_OPEN_PARAMS openParams;

    RtlZeroMemory(Spb, sizeof(*Spb));

    if (Resource->Type != CmResourceTypeConnection ||
        Resource->u.Connection.Class != CM_RESOURCE_CONNECTION_CLASS_SERIAL ||
        Resource->u.Connection.Type != CM_RESOURCE_CONNECTION_TYPE_SERIAL_I2C) {
        return STATUS_INVALID_PARAMETER;
    }

    Spb->ConnectionId.LowPart = Resource->u.Connection.IdLowPart;
    Spb->ConnectionId.HighPart = Resource->u.Connection.IdHighPart;

    RESOURCE_HUB_CREATE_PATH_FROM_ID(
        &resourcePath,
        Spb->ConnectionId.LowPart,
        Spb->ConnectionId.HighPart);

    WDF_OBJECT_ATTRIBUTES_INIT(&targetAttributes);
    status = WdfIoTargetCreate(Device, &targetAttributes, &Spb->IoTarget);
    Spb->CreateStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = WdfWaitLockCreate(WDF_NO_OBJECT_ATTRIBUTES, &Spb->Lock);
    Spb->LockStatus = status;
    if (!NT_SUCCESS(status)) {
        SpbDeinitialize(Spb);
        return status;
    }

    WDF_IO_TARGET_OPEN_PARAMS_INIT_OPEN_BY_NAME(
        &openParams,
        &resourcePath,
        GENERIC_READ | GENERIC_WRITE);

    openParams.ShareAccess = 0;
    openParams.CreateDisposition = FILE_OPEN;
    openParams.FileAttributes = FILE_ATTRIBUTE_NORMAL;

    status = WdfIoTargetOpen(Spb->IoTarget, &openParams);
    Spb->OpenStatus = status;
    if (!NT_SUCCESS(status)) {
        SpbDeinitialize(Spb);
        return status;
    }

    Spb->Ready = TRUE;
    return STATUS_SUCCESS;
}

VOID
SpbDeinitialize(
    _Inout_ PSPB_CONTEXT Spb
    )
{
    if (Spb->IoTarget != NULL) {
        WdfIoTargetClose(Spb->IoTarget);
        WdfObjectDelete(Spb->IoTarget);
    }

    if (Spb->Lock != NULL) {
        WdfObjectDelete(Spb->Lock);
    }

    RtlZeroMemory(Spb, sizeof(*Spb));
}

NTSTATUS
SpbWrite(
    _Inout_ PSPB_CONTEXT Spb,
    _In_reads_bytes_(Length) const UCHAR* Data,
    _In_ ULONG Length
    )
{
    NTSTATUS status;
    WDF_MEMORY_DESCRIPTOR input;
    WDF_REQUEST_SEND_OPTIONS options;

    if (!Spb->Ready || Length == 0) {
        return STATUS_DEVICE_NOT_READY;
    }

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&input, (PVOID)Data, Length);
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    /*
     * The Qualcomm controller can still be completing its first D0/Geni
     * transition when the amplifier child enters D0. Keep this bounded, but
     * allow enough time to distinguish controller bring-up latency from a
     * persistent bus failure.
     */
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(2000));

    WdfWaitLockAcquire(Spb->Lock, NULL);
    status = WdfIoTargetSendWriteSynchronously(Spb->IoTarget, NULL, &input, NULL, &options, NULL);
    WdfWaitLockRelease(Spb->Lock);
    return status;
}

NTSTATUS
SpbRead(
    _Inout_ PSPB_CONTEXT Spb,
    _Out_writes_bytes_(Length) UCHAR* Data,
    _In_ ULONG Length
    )
{
    NTSTATUS status;
    WDF_MEMORY_DESCRIPTOR output;
    WDF_REQUEST_SEND_OPTIONS options;

    if (!Spb->Ready || Data == NULL || Length == 0) {
        return STATUS_DEVICE_NOT_READY;
    }

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&output, Data, Length);
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(2000));

    WdfWaitLockAcquire(Spb->Lock, NULL);
    status = WdfIoTargetSendReadSynchronously(
        Spb->IoTarget,
        NULL,
        &output,
        NULL,
        &options,
        NULL);
    WdfWaitLockRelease(Spb->Lock);
    return status;
}

NTSTATUS
SpbWriteRead(
    _Inout_ PSPB_CONTEXT Spb,
    _In_reads_bytes_(WriteLength) const UCHAR* WriteData,
    _In_ ULONG WriteLength,
    _Out_writes_bytes_(ReadLength) UCHAR* ReadData,
    _In_ ULONG ReadLength
    )
{
    NTSTATUS status;
    SPB_TRANSFER_LIST_AND_ENTRIES(2) sequence;
    ULONG index = 0;
    ULONG_PTR bytesTransferred = 0;
    WDF_MEMORY_DESCRIPTOR sequenceDescriptor;
    WDF_REQUEST_SEND_OPTIONS options;

    if (!Spb->Ready || WriteLength == 0 || ReadLength == 0) {
        return STATUS_DEVICE_NOT_READY;
    }

    SPB_TRANSFER_LIST_INIT(&sequence.List, 2);
    sequence.List.Transfers[index] = SPB_TRANSFER_LIST_ENTRY_INIT_SIMPLE(
        SpbTransferDirectionToDevice,
        0,
        (PVOID)WriteData,
        WriteLength);
    index++;
    sequence.List.Transfers[index] = SPB_TRANSFER_LIST_ENTRY_INIT_SIMPLE(
        SpbTransferDirectionFromDevice,
        0,
        ReadData,
        ReadLength);

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(
        &sequenceDescriptor,
        &sequence,
        sizeof(sequence));
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(2000));

    WdfWaitLockAcquire(Spb->Lock, NULL);
    status = WdfIoTargetSendIoctlSynchronously(
        Spb->IoTarget,
        NULL,
        IOCTL_SPB_EXECUTE_SEQUENCE,
        &sequenceDescriptor,
        NULL,
        &options,
        &bytesTransferred);
    WdfWaitLockRelease(Spb->Lock);

    if (NT_SUCCESS(status) &&
        bytesTransferred != (ULONG_PTR)WriteLength + ReadLength) {
        status = STATUS_INFO_LENGTH_MISMATCH;
    }

    return status;
}

NTSTATUS
SpbWriteReadSplit(
    _Inout_ PSPB_CONTEXT Spb,
    _In_reads_bytes_(WriteLength) const UCHAR* WriteData,
    _In_ ULONG WriteLength,
    _Out_writes_bytes_(ReadLength) UCHAR* ReadData,
    _In_ ULONG ReadLength,
    _Out_ NTSTATUS* WriteStatus,
    _Out_ NTSTATUS* ReadStatus
    )
{
    NTSTATUS status;

    if (WriteStatus == NULL || ReadStatus == NULL) {
        return STATUS_INVALID_PARAMETER;
    }

    *WriteStatus = SpbWrite(Spb, WriteData, WriteLength);
    *ReadStatus = STATUS_PENDING;
    if (!NT_SUCCESS(*WriteStatus)) {
        return *WriteStatus;
    }

    status = SpbRead(Spb, ReadData, ReadLength);
    *ReadStatus = status;
    return status;
}
