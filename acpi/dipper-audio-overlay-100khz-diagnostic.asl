/*
 * Diagnostic variant of the Dipper TAS2557 overlay.
 *
 * The only functional difference from dipper-audio-overlay-draft.asl is
 * I2cSerialBusV2 speed: 100 kHz instead of 400 kHz.
 *
 * Do not install without preserving the current acpitabl.dat rollback copy.
 * All driver safety gates must remain zero during overlay replacement.
 */

DefinitionBlock ("", "SSDT", 2, "DIPPER", "TAS100K", 0x00000001)
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
                        100000,
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
