/*
 * Sample only. Do not compile/install without confirming the real Windows ACPI
 * controller path for Xiaomi Mi 8.
 *
 * Linux dipper sources identify TAS2557 at I2C address 0x4c with reset GPIO 76
 * and IRQ GPIO 30. Current Windows DSDT has _SB.I2C4, _SB.I2C6, _SB.IC11,
 * and _SB.IC15, but it has no TAS/TTAS/AFLT device. The controller below is
 * a placeholder and must be confirmed before any override is attempted.
 */

Device (TAS7)
{
    Name (_HID, "DIPT2557")
    Name (_CID, "TTAS2557")
    Name (_DDN, "Xiaomi Mi 8 TAS2557 Smart Amplifier")

    Method (_CRS, 0, NotSerialized)
    {
        Name (RBUF, ResourceTemplate ()
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

            GpioInt (
                Level,
                ActiveHigh,
                Exclusive,
                PullDefault,
                0,
                "\\_SB.GIO0",
                0,
                ResourceConsumer,
                ,
            )
            { 30 }
        })

        Return (RBUF)
    }
}
