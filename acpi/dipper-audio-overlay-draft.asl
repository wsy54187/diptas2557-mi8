/*
 * Draft only. Do not install as-is.
 *
 * This fragment is based on:
 * - current Xiaomi Mi 8 Windows DSDT strings
 * - Linux dipper TAS2557 hardware data
 * - sunflower2333/tas2557_win ACPI sample
 *
 * Current DSDT has:
 * - \_SB.I2C6
 * - \_SB.GIO0
 * - \_SB.ADSP.SLM1.ADCM.AUDD string path
 *
 * Linux dipper DTS also names reset GPIO 76 and speaker-id GPIO 27.
 * This overlay exposes reset GPIO 76 as a GPIO_IO resource, but the driver
 * keeps it inert unless the explicit AllowResetProbe registry gate is enabled.
 * It still does not expose speaker-id GPIO 27.
 *
 * Current DSDT does NOT have:
 * - AFLT0001
 * - TTAS2557
 */

DefinitionBlock ("", "SSDT", 2, "DIPPER", "TAS2557", 0x00000001)
{
    External (\_SB.GIO0, DeviceObj)
    External (\_SB.I2C6, DeviceObj)
    External (\_SB.PSUB, DeviceObj)
    External (\_SB.ADSP.SLM1.ADCM.AUDD, DeviceObj)

    Scope (\_SB)
    {
        Device (AFT1)
        {
            Name (_HID, "AFLT0001")
            Name (_UID, Zero)
            Name (_DEP, Package ()
            {
                \_SB.ADSP.SLM1.ADCM.AUDD
            })
        }

        Device (SPK1)
        {
            Name (_HID, "TTAS2557")
            Name (_UID, Zero)
            Alias (\_SB.PSUB, _SUB)
            Name (_DEP, Package ()
            {
                \_SB.GIO0,
                \_SB.I2C6
            })

            Method (_CRS, 0, Serialized)
            {
                Return (ResourceTemplate ()
                {
                    I2cSerialBusV2 (
                        0x004C,
                        ControllerInitiated,
                        400000,
                        AddressingMode7Bit,
                        "\\_SB.I2C6",
                        0x00,
                        ResourceConsumer,
                        ,
                        Exclusive,
                    )

                    GpioInt (
                        Level,
                        ActiveHigh,
                        Exclusive,
                        PullDown,
                        0,
                        "\\_SB.GIO0",
                        0,
                        ResourceConsumer,
                        ,
                    )
                    { 30 }

                    GpioIo (
                        Exclusive,
                        PullDefault,
                        0,
                        0,
                        IoRestrictionOutputOnly,
                        "\\_SB.GIO0",
                        0,
                        ResourceConsumer,
                        ,
                    )
                    { 76 }
                })
            }
        }
    }
}
