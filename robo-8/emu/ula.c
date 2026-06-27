#include "header.h"
#include <stdio.h>

enum io_reg {
    IO_VCTL    = 0xFF,   // video control      (7:VSync 6:VRow 5:Blank 4:Grey 3:Bpp 2:Text 1:VRes 0:HRes)
    IO_VPL2    = 0xFE,   // palette register   (7-4:C2 3-0:C3)
    IO_VPL1    = 0xFD,   // palette register   (7-4:BG 3-0:~FG)
    IO_VLIN    = 0xFC,   // current video line (read: V-counter >= 192 Blank)(write: IRQAck 7:VSync 6:VRow 5:KBInt)
    IO_KEYB    = 0xFB,   // Keyboard scan      (write: 7-6:Volume 3-0:KBCol)(read: KBRow)
    IO_PSGF    = 0xFA,   // PSG Frequency      (write: 7-0:Divider)(7860 Hz / divider)
};

uint8_t OpenBus[8*1024] = { 0xEE };
uint8_t SysROM[8*1024];
uint8_t MainRAM[8*1024];
uint8_t CartRAM[8*1024];

extern uint16_t vdp_vcount; // 9-bit vertical line count

uint8_t  VidCtl    = 0x2E;   // 8-bit video control (4:Width 3:Height 2:Grey 1:APA 0:Color)
uint8_t  VidPal1   = 0x3E;   // 8-bit register      (7-4:BG 3-0:~FG)
uint8_t  VidPal2   = 0xC1;   // 8-bit register      (7-4:C2 3-0:C3)
uint8_t  KbdCol    = 0x03;   // 4-bit register
uint8_t  PSGVol    = 0x03;   // 2-bit register
uint8_t  PSGFrq    = 0x28;   // 8-bit register

static uint8_t* MemMap[8] = {
    MainRAM,               // Base 8K RAM
    CartRAM,               // 8K RAM Cart
    OpenBus,               // RAM Expansion (16K RAM Cart)
    OpenBus,               // RAM Expansion (32K RAM Cart)
    OpenBus,               // RAM Expansion (32K RAM Cart)
    OpenBus,               // Expansion Port
    OpenBus,               // Expansion Port
    SysROM,                // System ROM (4K, mirrored twice)
};

static uint8_t MemMapWR[8] = {
    1,                     // 8K Main RAM
    1,                     // 8K RAM Cart
    0,                     // RAM Expansion (16K RAM Cart)
    0,                     // RAM Expansion (32K RAM Cart)
    0,                     // RAM Expansion (32K RAM Cart)
    0,                     // Expansion Port
    0,                     // Expansion Port
    0,                     // System ROM
};

static uint8_t ula_io_read(uint16_t address) {
    // catch up the VDP before reading IO
    advance_vdp();
    // open bus value
    uint8_t value = 0xEE;
    // now read the IO port
    switch (address) {
        // F-page
        case IO_VLIN:       // $FC: (0-191 are visible lines)
            value = vdp_vcount & 0xFF;
            break;
        case IO_KEYB: {     // $FB: (read: KBRow)
            value = scanKeyCol(KbdCol);
            break;
        }
        default:
            // Read-through to RAM.
            return MainRAM[address];
    }
    if (address == IO_VLIN) {
        printf("IO Read: [$%02X] -> $%02X\n", address, value);
    }
    return value;
}

static void ula_io_write(uint16_t address, uint8_t value) {
    // catch up the VDP before reading IO
    advance_vdp();
    // now write the IO value
    switch (address) {
        // F-page
        case IO_VCTL:       // $FF: (7:VSync 6:VRow 5:Blank 4:Grey 3:Bpp 2:Text 1:VRes 0:HRes)
            VidCtl = value;
            break;
        case IO_VPL2:       // $FE: (7-4:C2 3-0:C3)
            VidPal2 = value;
            break;
        case IO_VPL1:       // $FD: (7-4:BG 3-0:~FG)
            VidPal1 = value;
            break;
        case IO_VLIN:       // $FC: (IRQAck 7:VSync 6:VRow 5:KBInt)
            break;
        case IO_KEYB:       // $FB: (7-6:Volume 3-0:KBCol)
            KbdCol = value & 0x0F;
            PSGVol = value >> 6;
            break;
        case IO_PSGF: {     // $FC: PSG Divider (read: last write)
            PSGFrq = value;
            break;
        }
    }
    // write-through to RAM.
    MainRAM[address] = value;
    // log IO writes (except keyboard row / irq ack)
    if (address != IO_KEYB && address != IO_VLIN) {
        printf("IO Write: [$%02X] <- $%02X\n", address, value);
    }
}

uint8_t read6502(uint16_t address) {
    // address < 0xF8 or address >= 0x100
    if ((unsigned)address - 0xF8 >= 0x08) {
        return MemMap[address >> 13][address & 0x1fff]; // 8K Banks
    } else {
        return ula_io_read(address);
    }
}

void write6502(uint16_t address, uint8_t value) {
    // address < 0xF8 or address >= 0x100
    if ((unsigned)address - 0xF8 >= 0x08) {
        unsigned page = address >> 13;
        if (MemMapWR[page]) {
            MemMap[page][address & 0x1fff] = value; // 8K Banks
        }
    } else {
        ula_io_write(address, value);
    }
}
