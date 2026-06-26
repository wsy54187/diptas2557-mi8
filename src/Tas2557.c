#include "Driver.h"
#include "Tas2557.h"

static VOID
Tas2557DelayUs(
    _In_ ULONG Microseconds
    )
{
    LARGE_INTEGER interval;
    interval.QuadPart = -10 * (LONGLONG)Microseconds;
    KeDelayExecutionThread(KernelMode, FALSE, &interval);
}

static NTSTATUS
Tas2557SelectBookPage(
    _Inout_ PDEVICE_CONTEXT Context,
    _In_ ULONG Book,
    _In_ ULONG Page
    )
{
    NTSTATUS status;
    UCHAR write[2];

    if (!Context->AllowI2cWrites &&
        (Context->CurrentBook != Book || Context->CurrentPage != Page)) {
        return STATUS_ACCESS_DENIED;
    }

    if (Context->CurrentBook != Book) {
        write[0] = TAS2557_PAGECTL_REG;
        write[1] = 0;
        status = SpbWrite(&Context->Spb, write, sizeof(write));
        if (!NT_SUCCESS(status)) {
            return status;
        }

        write[0] = TAS2557_BOOKCTL_REG;
        write[1] = (UCHAR)Book;
        status = SpbWrite(&Context->Spb, write, sizeof(write));
        if (!NT_SUCCESS(status)) {
            return status;
        }

        Context->CurrentBook = Book;
        Context->CurrentPage = 0;
    }

    if (Context->CurrentPage != Page) {
        write[0] = TAS2557_PAGECTL_REG;
        write[1] = (UCHAR)Page;
        status = SpbWrite(&Context->Spb, write, sizeof(write));
        if (!NT_SUCCESS(status)) {
            return status;
        }

        Context->CurrentPage = Page;
    }

    return STATUS_SUCCESS;
}

static NTSTATUS
Tas2557WriteReg(
    _Inout_ PDEVICE_CONTEXT Context,
    _In_ ULONG Register,
    _In_ UCHAR Value
    )
{
    NTSTATUS status;
    UCHAR write[2];

    if (!Context->AllowI2cWrites) {
        return STATUS_ACCESS_DENIED;
    }

    status = Tas2557SelectBookPage(Context, TAS2557_BOOK_ID(Register), TAS2557_PAGE_ID(Register));
    if (!NT_SUCCESS(status)) {
        return status;
    }

    write[0] = (UCHAR)TAS2557_PAGE_REG(Register);
    write[1] = Value;
    return SpbWrite(&Context->Spb, write, sizeof(write));
}

static NTSTATUS
Tas2557ReadReg(
    _Inout_ PDEVICE_CONTEXT Context,
    _In_ ULONG Register,
    _Out_ UCHAR* Value
    )
{
    NTSTATUS status;
    UCHAR reg;

    if (!Context->AllowI2cWrites) {
        if (TAS2557_BOOK_ID(Register) != 0 || TAS2557_PAGE_ID(Register) != 0) {
            return STATUS_ACCESS_DENIED;
        }
    } else {
        status = Tas2557SelectBookPage(Context, TAS2557_BOOK_ID(Register), TAS2557_PAGE_ID(Register));
        if (!NT_SUCCESS(status)) {
            return status;
        }
    }

    reg = (UCHAR)TAS2557_PAGE_REG(Register);
    if (Context->AllowSplitReadProbe) {
        return SpbWriteReadSplit(
            &Context->Spb,
            &reg,
            sizeof(reg),
            Value,
            sizeof(*Value),
            &Context->LastAddressWriteStatus,
            &Context->LastDataReadStatus);
    }

    Context->LastAddressWriteStatus = STATUS_NOT_SUPPORTED;
    Context->LastDataReadStatus = STATUS_NOT_SUPPORTED;
    return SpbWriteRead(&Context->Spb, &reg, sizeof(reg), Value, sizeof(*Value));
}

NTSTATUS
Tas2557SoftwareResetProbe(
    _Inout_ PDEVICE_CONTEXT Context
    )
{
    NTSTATUS status;
    UCHAR write[2];

    if (!Context->AllowSoftwareResetProbe || Context->AllowI2cWrites) {
        return STATUS_ACCESS_DENIED;
    }

    write[0] = (UCHAR)TAS2557_PAGE_REG(TAS2557_SW_RESET_REG);
    write[1] = 0x01;
    status = SpbWrite(&Context->Spb, write, sizeof(write));
    if (!NT_SUCCESS(status)) {
        return status;
    }

    Context->CurrentBook = 0;
    Context->CurrentPage = 0;
    Tas2557DelayUs(1000);
    return STATUS_SUCCESS;
}

NTSTATUS
Tas2557ForceShutdown(
    _Inout_ PDEVICE_CONTEXT Context
    )
{
    NTSTATUS status;

    if (!Context->Spb.Ready) {
        return STATUS_DEVICE_NOT_READY;
    }

    status = Tas2557WriteReg(Context, TAS2557_CLK_ERR_CTRL, 0x00);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    (VOID)Tas2557WriteReg(Context, TAS2557_SOFT_MUTE_REG, 0x01);
    Tas2557DelayUs(10000);
    (VOID)Tas2557WriteReg(Context, TAS2557_MUTE_REG, 0x03);
    (VOID)Tas2557WriteReg(Context, TAS2557_POWER_CTRL1_REG, 0x60);
    Tas2557DelayUs(2000);
    (VOID)Tas2557WriteReg(Context, TAS2557_POWER_CTRL2_REG, 0x00);
    (VOID)Tas2557WriteReg(Context, TAS2557_POWER_CTRL1_REG, 0x00);
    (VOID)Tas2557WriteReg(Context, TAS2557_GPIO1_PIN_REG, 0x00);
    (VOID)Tas2557WriteReg(Context, TAS2557_GPIO2_PIN_REG, 0x00);
    (VOID)Tas2557WriteReg(Context, TAS2557_GPI_PIN_REG, 0x00);

    Context->Powered = FALSE;
    Context->Muted = TRUE;
    return STATUS_SUCCESS;
}

NTSTATUS
Tas2557Probe(
    _Inout_ PDEVICE_CONTEXT Context
    )
{
    NTSTATUS status;
    UCHAR pgid = 0;
    UCHAR safeGuard = 0;

    status = Tas2557ReadReg(Context, TAS2557_REV_PGID_REG, &pgid);
    Context->LastProbeStatus = status;
    if (!NT_SUCCESS(status)) {
        Context->I2cReady = FALSE;
        Context->Powered = FALSE;
        Context->Muted = TRUE;
        return STATUS_SUCCESS;
    }

    Context->LastPgid = pgid;
    Context->I2cReady = TRUE;

    if (!Context->AllowI2cWrites) {
        Context->Powered = FALSE;
        Context->Muted = TRUE;
        return STATUS_SUCCESS;
    }

    status = Tas2557WriteReg(Context, TAS2557_SAR_ADC2_REG, 0x05);
    Context->LastProbeStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557WriteReg(Context, TAS2557_CLK_ERR_CTRL2, 0x21);
    Context->LastProbeStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557WriteReg(Context, TAS2557_CLK_ERR_CTRL3, 0x21);
    Context->LastProbeStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557WriteReg(Context, TAS2557_SAFE_GUARD_REG, TAS2557_SAFE_GUARD_PATTERN);
    Context->LastProbeStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557ReadReg(Context, TAS2557_SAFE_GUARD_REG, &safeGuard);
    Context->LastProbeStatus = status;
    if (!NT_SUCCESS(status)) {
        return status;
    }

    Context->LastSafeGuard = safeGuard;
    Context->I2cReady = TRUE;

    status = Tas2557ForceShutdown(Context);
    Context->LastProbeStatus = status;
    return status;
}

typedef struct _TAS2557_FW_READER {
    const UCHAR* Cursor;
    const UCHAR* End;
} TAS2557_FW_READER, *PTAS2557_FW_READER;

static NTSTATUS
Tas2557FwNeed(
    _In_ PTAS2557_FW_READER Reader,
    _In_ ULONG Count
    )
{
    if (Reader->Cursor > Reader->End || Count > (ULONG)(Reader->End - Reader->Cursor)) {
        return STATUS_BUFFER_TOO_SMALL;
    }

    return STATUS_SUCCESS;
}

static NTSTATUS
Tas2557FwSkip(
    _Inout_ PTAS2557_FW_READER Reader,
    _In_ ULONG Count
    )
{
    NTSTATUS status = Tas2557FwNeed(Reader, Count);

    if (NT_SUCCESS(status)) {
        Reader->Cursor += Count;
    }

    return status;
}

static NTSTATUS
Tas2557FwReadU16Be(
    _Inout_ PTAS2557_FW_READER Reader,
    _Out_ USHORT* Value
    )
{
    NTSTATUS status = Tas2557FwNeed(Reader, 2);

    if (!NT_SUCCESS(status)) {
        return status;
    }

    *Value = ((USHORT)Reader->Cursor[0] << 8) | (USHORT)Reader->Cursor[1];
    Reader->Cursor += 2;
    return STATUS_SUCCESS;
}

static NTSTATUS
Tas2557FwReadU32Be(
    _Inout_ PTAS2557_FW_READER Reader,
    _Out_ ULONG* Value
    )
{
    NTSTATUS status = Tas2557FwNeed(Reader, 4);

    if (!NT_SUCCESS(status)) {
        return status;
    }

    *Value = ((ULONG)Reader->Cursor[0] << 24) |
             ((ULONG)Reader->Cursor[1] << 16) |
             ((ULONG)Reader->Cursor[2] << 8) |
             (ULONG)Reader->Cursor[3];
    Reader->Cursor += 4;
    return STATUS_SUCCESS;
}

static NTSTATUS
Tas2557FwSkipCString(
    _Inout_ PTAS2557_FW_READER Reader
    )
{
    while (Reader->Cursor < Reader->End) {
        if (*Reader->Cursor++ == 0) {
            return STATUS_SUCCESS;
        }
    }

    return STATUS_INVALID_PARAMETER;
}

static NTSTATUS
Tas2557FwSkipBlock(
    _Inout_ PTAS2557_FW_READER Reader,
    _In_ ULONG DriverVersion
    )
{
    NTSTATUS status;
    ULONG ignored;
    ULONG commands;

    status = Tas2557FwReadU32Be(Reader, &ignored);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    if (DriverVersion >= 0x00000200u) {
        status = Tas2557FwSkip(Reader, 4);
        if (!NT_SUCCESS(status)) {
            return status;
        }
    }

    status = Tas2557FwReadU32Be(Reader, &commands);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    if (commands > ((ULONG)(Reader->End - Reader->Cursor) / 4u)) {
        return STATUS_INVALID_PARAMETER;
    }

    return Tas2557FwSkip(Reader, commands * 4u);
}

static NTSTATUS
Tas2557FwSkipData(
    _Inout_ PTAS2557_FW_READER Reader,
    _In_ ULONG DriverVersion
    )
{
    NTSTATUS status;
    USHORT blocks;
    USHORT i;

    status = Tas2557FwSkip(Reader, 64);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557FwSkipCString(Reader);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557FwReadU16Be(Reader, &blocks);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    for (i = 0; i < blocks; i++) {
        status = Tas2557FwSkipBlock(Reader, DriverVersion);
        if (!NT_SUCCESS(status)) {
            return status;
        }
    }

    return STATUS_SUCCESS;
}

NTSTATUS
Tas2557ValidateFirmwareMetadata(
    _Inout_ PDEVICE_CONTEXT Context,
    _In_reads_bytes_(Length) const UCHAR* Data,
    _In_ ULONG Length
    )
{
    NTSTATUS status;
    TAS2557_FW_READER reader;
    ULONG magic;
    ULONG ignored;
    ULONG driverVersion;
    ULONG deviceFamily;
    ULONG device;
    USHORT pllCount;
    USHORT programCount;
    USHORT configCount;
    USHORT i;
    BOOLEAN safeConfigFound = FALSE;

    if (Data == NULL || Length < 104) {
        return STATUS_INVALID_PARAMETER;
    }

    reader.Cursor = Data;
    reader.End = Data + Length;

    Context->FirmwareLoaded = FALSE;
    Context->FirmwareMagic = 0;
    Context->FirmwareDriverVersion = 0;
    Context->FirmwareDeviceFamily = 0;
    Context->FirmwareDevice = 0;
    Context->FirmwareProgramCount = 0;
    Context->FirmwareConfigCount = 0;
    Context->FirmwareSafeProgram = 0;
    Context->FirmwareSafeConfig = 0;

    status = Tas2557FwReadU32Be(&reader, &magic);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (magic != TAS2557_FW_MAGIC) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }

    status = Tas2557FwReadU32Be(&reader, &ignored); /* size */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &ignored); /* checksum */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &ignored); /* PPC version */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &ignored); /* firmware version */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &driverVersion);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &ignored); /* timestamp */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwSkip(&reader, 64); /* DDC name */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwSkipCString(&reader); /* description */
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &deviceFamily);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = Tas2557FwReadU32Be(&reader, &device);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    if (driverVersion != TAS2557_FW_EXPECTED_DRIVER_VERSION ||
        deviceFamily != TAS2557_FW_EXPECTED_DEVICE_FAMILY ||
        device != TAS2557_FW_EXPECTED_DEVICE) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }

    status = Tas2557FwReadU16Be(&reader, &pllCount);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    for (i = 0; i < pllCount; i++) {
        status = Tas2557FwSkip(&reader, 64);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        status = Tas2557FwSkipCString(&reader);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        status = Tas2557FwSkipBlock(&reader, driverVersion);
        if (!NT_SUCCESS(status)) {
            return status;
        }
    }

    status = Tas2557FwReadU16Be(&reader, &programCount);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (programCount <= TAS2557_FW_SAFE_PROGRAM_INDEX) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    for (i = 0; i < programCount; i++) {
        status = Tas2557FwSkip(&reader, 64);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        status = Tas2557FwSkipCString(&reader);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        status = Tas2557FwSkip(&reader, 3); /* app mode + boost */
        if (!NT_SUCCESS(status)) {
            return status;
        }
        status = Tas2557FwSkipData(&reader, driverVersion);
        if (!NT_SUCCESS(status)) {
            return status;
        }
    }

    status = Tas2557FwReadU16Be(&reader, &configCount);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (configCount <= TAS2557_FW_SAFE_CONFIG_INDEX) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    for (i = 0; i < configCount; i++) {
        UCHAR program;
        ULONG sampleRate;

        status = Tas2557FwSkip(&reader, 64);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        status = Tas2557FwSkipCString(&reader);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        if (driverVersion >= 0x00000300u ||
            (driverVersion >= 0x00000101u && driverVersion < 0x00000200u)) {
            status = Tas2557FwSkip(&reader, 2);
            if (!NT_SUCCESS(status)) {
                return status;
            }
        }
        status = Tas2557FwNeed(&reader, 2);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        program = reader.Cursor[0];
        reader.Cursor += 2; /* program + PLL */
        status = Tas2557FwReadU32Be(&reader, &sampleRate);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        if (driverVersion >= 0x00000400u) {
            status = Tas2557FwSkip(&reader, 5); /* PLL source + source rate */
            if (!NT_SUCCESS(status)) {
                return status;
            }
        }
        status = Tas2557FwSkipData(&reader, driverVersion);
        if (!NT_SUCCESS(status)) {
            return status;
        }

        if (i == TAS2557_FW_SAFE_CONFIG_INDEX &&
            program == TAS2557_FW_SAFE_PROGRAM_INDEX &&
            sampleRate == TAS2557_FW_EXPECTED_SAMPLE_RATE) {
            safeConfigFound = TRUE;
        }
    }

    if (!safeConfigFound) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }

    Context->FirmwareMagic = magic;
    Context->FirmwareDriverVersion = driverVersion;
    Context->FirmwareDeviceFamily = deviceFamily;
    Context->FirmwareDevice = device;
    Context->FirmwareProgramCount = programCount;
    Context->FirmwareConfigCount = configCount;
    Context->FirmwareSafeProgram = TAS2557_FW_SAFE_PROGRAM_INDEX;
    Context->FirmwareSafeConfig = TAS2557_FW_SAFE_CONFIG_INDEX;
    Context->FirmwareLoaded = TRUE;

    return STATUS_SUCCESS;
}

NTSTATUS
Tas2557SafeStartup(
    _Inout_ PDEVICE_CONTEXT Context
    )
{
    NTSTATUS status;
    UCHAR safeGuard = 0;

    if (!Context->AllowI2cWrites || !Context->AllowSpeakerPowerUp) {
        return STATUS_ACCESS_DENIED;
    }

    if (!Context->FirmwareLoaded) {
        return STATUS_DEVICE_NOT_READY;
    }

    status = Tas2557ReadReg(Context, TAS2557_SAFE_GUARD_REG, &safeGuard);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    Context->LastSafeGuard = safeGuard;
    if (safeGuard != TAS2557_SAFE_GUARD_PATTERN) {
        return STATUS_DEVICE_CONFIGURATION_ERROR;
    }

    status = Tas2557WriteReg(Context, TAS2557_GPI_PIN_REG, 0x15);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    (VOID)Tas2557WriteReg(Context, TAS2557_GPIO1_PIN_REG, 0x01);
    (VOID)Tas2557WriteReg(Context, TAS2557_GPIO2_PIN_REG, 0x01);
    (VOID)Tas2557WriteReg(Context, TAS2557_POWER_CTRL2_REG, 0xa0);
    (VOID)Tas2557WriteReg(Context, TAS2557_POWER_CTRL2_REG, 0xa3);
    (VOID)Tas2557WriteReg(Context, TAS2557_POWER_CTRL1_REG, 0xf8);
    Tas2557DelayUs(2000);
    status = Tas2557WriteReg(Context, TAS2557_CLK_ERR_CTRL, 0x2b);
    if (NT_SUCCESS(status)) {
        Context->Powered = TRUE;
        Context->Muted = TRUE;
    }

    return status;
}

NTSTATUS
Tas2557SafeUnmute(
    _Inout_ PDEVICE_CONTEXT Context
    )
{
    NTSTATUS status;

    if (!Context->AllowI2cWrites || !Context->AllowSpeakerPowerUp || !Context->FirmwareLoaded || !Context->Powered) {
        return STATUS_ACCESS_DENIED;
    }

    status = Tas2557WriteReg(Context, TAS2557_MUTE_REG, 0x00);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = Tas2557WriteReg(Context, TAS2557_SOFT_MUTE_REG, 0x00);
    if (NT_SUCCESS(status)) {
        Context->Muted = FALSE;
    }

    return status;
}
