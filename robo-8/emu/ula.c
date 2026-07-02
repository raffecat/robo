#include "header.h"
#include <stdio.h>

enum io_reg {
    IO_DATA = 0xF8, // OUT 8-bit (7-5:Volume 2:RTS 1:TXD 0:TapeOut) / IN (2:CTS 1:RXD 0:TapeIn)
    IO_KEYB = 0xF9, // Keyboard column 4-bit (3:Strobe 2-0:KBCol) / read: KB row 8-bit
    IO_LINE = 0xFA, // IRQAck 3-bit (7:VSync 6:VRow 5:KBInt) / read: vertical line (>= 192 in vblank)
    IO_PSGF = 0xFB, // PSG frequency 8-bit (write: 7-0:Divider)(7860 Hz / divider)
    IO_PAL1 = 0xFC, // palette for APA 8-bit (7-4:BG 3-0:~FG)
    IO_PAL2 = 0xFD, // palette for APA 8-bit (7-4:C2 3-0:C3)
    IO_VPGC = 0xFE, // video page 8-bit (video base page, page counter)
    IO_VCTL = 0xFF, // video mode 8-bit (7:VSync 6:VRow 5:Parallel 4:? 3:Grey 2:2Bpp 1-0:VMux)
};

uint8_t OpenBus[8*1024] = { 0xEE };
uint8_t SysROM[16*1024];
uint8_t MainRAM[8*1024];
uint8_t CartRAM[8*1024];

extern uint16_t vdp_vcount; // 9-bit vertical line count

uint8_t  VidCtl    = 0x2E;   // 8-bit video control ()
uint8_t  VidPgC    = 0x23;   // 5-bit video page counter
uint8_t  VidPal1   = 0x3E;   // 8-bit register      (7-4:BG 3-0:~FG)
uint8_t  VidPal2   = 0xC1;   // 8-bit register      (7-4:C2 3-0:C3)
uint8_t  KbdCol    = 0x03;   // 4-bit register
uint8_t  PSGVol    = 0x03;   // 2-bit register
uint8_t  PSGFrq    = 0x28;   // 8-bit register

uint8_t* MemMap[8] = {
    MainRAM,               // Base 8K RAM
    CartRAM,               // 8K RAM Cart
    OpenBus,               // RAM Expansion (16K RAM Cart)
    OpenBus,               // RAM Expansion (32K RAM Cart)
    OpenBus,               // RAM Expansion (32K RAM Cart)
    OpenBus,               // RAM Expansion (32K RAM Cart)
    SysROM,                // BASIC ROM (4K, mirrored twice in bottom 8K)
    SysROM+0x2000,         // System ROM (2K, mirrored twice in top 4K)
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
        case IO_KEYB: {     // (read: KBRow)
            value = scanKeyCol(KbdCol);
            break;
        }
        case IO_LINE:       // (0-191 are visible lines)
            value = vdp_vcount & 0xFF;
            break;
        default:
            return 0xEE;    // open bus
    }
    if (address != IO_KEYB) {
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
        case IO_VCTL:       // (7:VSync 6:VRow 5:Parallel 4:Grey 3:Bpp 2:Text 1:VRes 0:HRes)
            VidCtl = value;
            break;
        case IO_VPGC:
            VidPgC = value; // Video page counter (8-bit)
            break;
        case IO_PAL2:       // Palette (7-4:C2 3-0:C3)
            VidPal2 = value;
            break;
        case IO_PAL1:       // Palette (7-4:BG 3-0:~FG)
            VidPal1 = value;
            break;
        case IO_PSGF:       // PSG Divider (read: last write)
            PSGFrq = value;
            break;
        case IO_LINE:       // (IRQAck 7:VSync 6:VRow 5:KBInt)
            break;
        case IO_KEYB:       // (3-0:KBCol)
            KbdCol = value & 0x0F;
            break;
        case IO_DATA:       // (7-6:Volume 2:RTS 1:TXD 0:TapeOut)
            PSGVol = value >> 6;
            break;
    }
    // write-through to RAM.
    MainRAM[address] = value;
    // log IO writes (except keyboard row / irq ack)
    if (address != IO_KEYB && address != IO_LINE) {
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
