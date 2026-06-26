#include <initguid.h>
#include "Driver.h"

NTSTATUS
DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath
    )
{
    WDF_DRIVER_CONFIG config;
    WDF_OBJECT_ATTRIBUTES attributes;

    WDF_DRIVER_CONFIG_INIT(&config, Diptas2557EvtDeviceAdd);
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    attributes.EvtCleanupCallback = Diptas2557EvtDriverContextCleanup;

    return WdfDriverCreate(DriverObject, RegistryPath, &attributes, &config, WDF_NO_HANDLE);
}

VOID
Diptas2557EvtDriverContextCleanup(
    _In_ WDFOBJECT DriverObject
    )
{
    UNREFERENCED_PARAMETER(DriverObject);
}

NTSTATUS
Diptas2557EvtDeviceAdd(
    _In_ WDFDRIVER Driver,
    _Inout_ PWDFDEVICE_INIT DeviceInit
    )
{
    NTSTATUS status;
    WDFDEVICE device;
    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_PNPPOWER_EVENT_CALLBACKS pnpCallbacks;
    WDF_IO_QUEUE_CONFIG queueConfig;
    PDEVICE_CONTEXT context;

    UNREFERENCED_PARAMETER(Driver);

    WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&pnpCallbacks);
    pnpCallbacks.EvtDevicePrepareHardware = Diptas2557EvtPrepareHardware;
    pnpCallbacks.EvtDeviceReleaseHardware = Diptas2557EvtReleaseHardware;
    pnpCallbacks.EvtDeviceD0Entry = Diptas2557EvtD0Entry;
    pnpCallbacks.EvtDeviceD0Exit = Diptas2557EvtD0Exit;
    pnpCallbacks.EvtDeviceSelfManagedIoInit = Diptas2557EvtSelfManagedIoInit;
    WdfDeviceInitSetPnpPowerEventCallbacks(DeviceInit, &pnpCallbacks);

    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attributes, DEVICE_CONTEXT);
    status = WdfDeviceCreate(&DeviceInit, &attributes, &device);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    context = DeviceGetContext(device);
    RtlZeroMemory(context, sizeof(*context));
    context->Device = device;
    context->CurrentBook = (ULONG)-1;
    context->CurrentPage = (ULONG)-1;
    context->Muted = TRUE;

    status = WdfDeviceCreateDeviceInterface(device, &GUID_DEVINTERFACE_DIPTAS2557, NULL);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchSequential);
    queueConfig.EvtIoDeviceControl = Diptas2557EvtIoDeviceControl;
    return WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES, WDF_NO_HANDLE);
}
