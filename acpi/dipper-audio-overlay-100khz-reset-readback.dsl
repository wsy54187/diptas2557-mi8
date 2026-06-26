/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260408 (32-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of ./acpi/dipper-audio-overlay-100khz-reset-readback.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000166 (358)
 *     Revision         0x02
 *     Checksum         0x11
 *     OEM ID           "DIPPER"
 *     OEM Table ID     "TASRBK"
 *     OEM Revision     0x00000001 (1)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20260408 (539362312)
 */
DefinitionBlock ("", "SSDT", 2, "DIPPER", "TASRBK", 0x00000001)
{
    External (_SB_.ADSP.SLM1.ADCM.AUDD, DeviceObj)
    External (_SB_.GIO0, DeviceObj)
    External (_SB_.I2C6, DeviceObj)
    External (_SB_.PSUB, DeviceObj)

    Scope (\_SB)
    {
        Device (AFT1)
        {
            Name (_HID, "AFLT0001")  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_DEP, Package (0x01)  // _DEP: Dependencies
            {
                \_SB.ADSP.SLM1.ADCM.AUDD, 
            })
        }

        Device (SPK1)
        {
            Name (_HID, "TTAS2557")  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Alias (\_SB.PSUB, _SUB)
            Name (_DEP, Package (0x02)  // _DEP: Dependencies
            {
                \_SB.GIO0, , 
                \_SB.I2C6, 
            })
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Return (Buffer (0x64)
                {
                    /* 0000 */  0x8E, 0x19, 0x00, 0x02, 0x00, 0x01, 0x02, 0x00,  // ........
                    /* 0008 */  0x00, 0x01, 0x06, 0x00, 0xA0, 0x86, 0x01, 0x00,  // ........
                    /* 0010 */  0x4C, 0x00, 0x5C, 0x5F, 0x53, 0x42, 0x2E, 0x49,  // L.\_SB.I
                    /* 0018 */  0x32, 0x43, 0x36, 0x00, 0x8C, 0x20, 0x00, 0x01,  // 2C6.. ..
                    /* 0020 */  0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00,  // ........
                    /* 0028 */  0x00, 0x00, 0x17, 0x00, 0x00, 0x19, 0x00, 0x23,  // .......#
                    /* 0030 */  0x00, 0x00, 0x00, 0x1E, 0x00, 0x5C, 0x5F, 0x53,  // .....\_S
                    /* 0038 */  0x42, 0x2E, 0x47, 0x49, 0x4F, 0x30, 0x00, 0x8C,  // B.GIO0..
                    /* 0040 */  0x20, 0x00, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00,  //  .......
                    /* 0048 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x17, 0x00, 0x00,  // ........
                    /* 0050 */  0x19, 0x00, 0x23, 0x00, 0x00, 0x00, 0x4C, 0x00,  // ..#...L.
                    /* 0058 */  0x5C, 0x5F, 0x53, 0x42, 0x2E, 0x47, 0x49, 0x4F,  // \_SB.GIO
                    /* 0060 */  0x30, 0x00, 0x79, 0x00                           // 0.y.
                })
            }
        }
    }
}

