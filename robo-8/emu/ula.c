#include "header.h"
#include <stdio.h>

enum io_reg {
    IO_VCTL    = 0xF8,   // video control          (4:Width 3:Height 2:Grey 1:APA 0:Color)
    IO_VPAL    = 0xF9,   // palette register       (7-6:Border 5-3:BG 2-0:FG)
    IO_VLIN    = 0xFA,   // current video line     (read: V-counter)
    IO_KEYB    = 0xFB,   // Keyboard scan          (write: set row; read: scan column)
    IO_PSGF    = 0xFC,   // PSG Frequency          (write: set PSG divider)
};

uint8_t OpenBus[8*1024] = { 0xEE };
uint8_t SysROM[8*1024];
uint8_t MainRAM[8*1024];
uint8_t CartRAM[8*1024];

extern uint16_t vdp_vcount; // 9-bit vertical line count

uint8_t  VidCtl   = 0x2E;    // 8-bit video control (4:Width 3:Height 2:Grey 1:APA 0:Color)
uint8_t  VidPal   = 0x15;    // 8-bit register      (7-6:Border 5-3:BG 2-0:FG)
uint8_t  KbdCol    = 0x03;   // 4-bit register
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
        case IO_VCTL:       // $F8: (4:Width 3:Height 2:Grey 1:APA 0:Color)
            value = VidCtl;
            break;
        case IO_VPAL:       // $F9: (7-6:Border 5-3:BG 2-0:FG)
            value = VidPal;
            break;
        case IO_VLIN:       // $FA: (0-191 are visible lines)
            value = vdp_vcount & 0xFF;
            break;
        case IO_KEYB: {     // $FB: Keyboard scan (read: scan column)
            value = scanKeyCol(KbdCol);
            break;
        }
        case IO_PSGF: {     // $FC: PSG Divider (read: last write)
            value = scanKeyCol(KbdCol);
            break;
        }
    }
    printf("IO Read: [$%02X] -> $%02X\n", address, value);
    return value;
}

static void ula_io_write(uint16_t address, uint8_t value) {
    // catch up the VDP before reading IO
    advance_vdp();
    // now write the IO value
    switch (address) {
        // F-page
        case IO_VCTL:       // $F8: (4:Width 3:Height 2:Grey 1:APA 0:Color)
            VidCtl = value;
            break;
        case IO_VPAL:       // $F9: (7-6:Border 5-3:BG 2-0:FG)
            VidPal = value;
            break;
        case IO_VLIN:       // $FA: current Y-line (write: not writeable)
            break;
        case IO_KEYB:       // $FB: set keyboard scan row (4-bit -> 1 of 8 Decoder)
            KbdCol = value & 0x0F;
            break;
        case IO_PSGF: {     // $FC: PSG Divider (read: last write)
            PSGFrq = value;
            break;
        }
    }
    printf("IO Write: [$%02X] <- $%02X\n", address, value);
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
