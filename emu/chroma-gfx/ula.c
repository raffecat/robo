#include "header.h"
#include <stdio.h>

enum io_reg {
    IO_KEY   = 0xF8, // Keyboard/Serial 8-bit (7:TXD 6:RTS 5:TapeOut 4-0:KBCol) / read: KB row 8-bit
    IO_VID   = 0xF9, // Video Control 8-bit (7-4:VideoBase 3-2:Mode 1:Wide 0:2BPP) / read: Junk (STROBE Parallel)
    IO_VLN   = 0xFA, // IRQAck any-write / read: Vertical Line (>= 192 in vblank)
    IO_PAL   = 0xFB, // Color Palette 6-bit (5-4:Entry 3-0:Color) / read: (7-4:Junk 3:TapeIn 2:BUSY 1:CTS 0:RXD)
    IO_PSG   = 0xFC, // PSG Frequency 8-bit (7-0:Divider) (7860 Hz / divider; 255 = silent) [R/W]
    IO_CNF   = 0xFD, // Configuration 8-bit (7-5:Volume 4:Reveal 3:TapeMotor 2:EFsel 1:CDsel 0:ABsel) [R/W]
    IO_PIO   = 0xFE, // Parallel IO 8-bit (7-0 Parallel) [R/W]
    IO_EXP   = 0xFF  // Expansion 8-bit (7:CDsel 6-5:ABsel 4-0:MemoryMap) [R/W]
};

uint8_t OpenBus[8*1024] = { 0xEE };
uint8_t SysROM[16*1024];
uint8_t MainRAM[8*1024];
uint8_t CartRAM[8*1024];

extern uint16_t vdp_vcount; // 9-bit vertical line count

uint8_t  VidCtl    = 0x2E;   // 8-bit video control ()
uint8_t  VidPgC    = 0x23;   // 5-bit video page counter
uint8_t  VidPal[4] = {0x3,0xE,0xC,0x1}; // 4-bit registers
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
    uint8_t value = 0xEE;
    // now read the IO port
    switch (address) {
        // F-page
        case IO_KEY: {
            // Read Keyboard Row
            value = scanKeyCol(KbdCol);
            break;
        }
        case IO_VID: {
            // Read Junk (STROBE Parallel port)
            value = 0xFF;
            break;
        }
        case IO_VLN: {
            // Read Video Line (modulo 256)
            value = vdp_vcount & 0xFF;
            break;
        }
        case IO_PAL: {
            // Read IO (7-4:Junk 3:TapeIn 2:BUSY 1:CTS 0:RXD)
            value = 0xF0;
            break;
        }
        case IO_PSG:
        case IO_CNF:
        case IO_PIO:
        case IO_EXP:
        default: {
            // Read back from RAM
            return MainRAM[address];
        }
    }
    if (address != IO_KEY) {
        printf("IO Read: [$%02X] -> $%02X\n", address, value);
    }
    return value;
}

static void ula_io_write(uint16_t address, uint8_t value) {
    // catch up the VDP before reading IO
    advance_vdp();
    switch (address) {
        // F-page
        case IO_KEY: {
            // Write Keyboard/Serial (7:TXD 6:RTS 5:TapeOut 4-0:KBCol)
            KbdCol = value & 0x0F;
            break;
        }
        case IO_VID: {
            // Write Video Control (7-4:VideoBase 3-2:Mode 1:Wide 0:2BPP)
            VidCtl = value;
            break;
        }
        case IO_VLN: {
            // Acknowledge Interrupt (ignore data)
            break;
        }
        case IO_PAL: {
            // Write Palette (5-4:Entry 3-0:Color)
            int idx = (value >> 4) & 3; // color index
            VidPal[idx] = value & 15;
            break;
        }
        case IO_PSG: {
            // Write PSG Frequency (7-0:Divider)
            PSGFrq = value;
            break;
        }
        case IO_CNF: {
            // Write Configuration (7-5:Volume 4:Reveal 3:TapeMotor 2:EFsel 1:CDsel 0:ABsel)
            PSGVol = value >> 5;
            break;
        }
        case IO_PIO: {
            // Write Parallel Port (7-0:Data)
            break;
        }
        case IO_EXP: {
            // Write Expansion (7:CDsel 6-5:ABsel 4-0:MemoryMap)
            break;
        }
    }
    // Write-through to RAM
    MainRAM[address] = value;
    // log IO writes (except keyboard row / irq ack)
    if (address != IO_KEY && address != IO_VLN) {
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
