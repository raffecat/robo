#include "header.h"
#include <stdio.h>

// XXX: Reveal, TapeMotor
enum io_reg {
    IO_KEY   = 0xF8, // Keyboard (7:TXD 6:RTS 5:TapeOut 4:Speaker 3-0:KBCol) / read: KB row
    IO_IOR   = 0xF9, // IO Read: (3:TapeIn 2:BUSY 1:CTS 0:RXD)
    IO_ACK   = 0xFA, // IRQAck (any-write)
    IO_XXB   = 0xFB, // Reserved
    IO_XXC   = 0xFC, // Reserved
    IO_XXD   = 0xFD, // Reserved
    IO_XXE   = 0xFE, // Reserved
    IO_EXP   = 0xFF  // Expansion 8-bit (7:CDsel 6-5:ABsel 4-0:MemoryMap) [R/W]
};

uint8_t OpenBus[8*1024] = { 0xEE };
uint8_t SysROM[8*1024];
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
    OpenBus,               // RAM Expansion (8K RAM Cart)
    OpenBus,               // RAM Expansion (8K RAM Cart)
    OpenBus,               // RAM Expansion (8K RAM Cart)
    OpenBus,               // RAM Expansion (8K RAM Cart)
    OpenBus,               // Cartridge ROM (8K)
    SysROM,                // System ROM (upper 4K)
};

static uint8_t MemMapWR[8] = {
    1,                     // 8K Main RAM
    1,                     // 8K RAM Cart
    0,                     // RAM Expansion (8K RAM Cart)
    0,                     // RAM Expansion (8K RAM Cart)
    0,                     // RAM Expansion (8K RAM Cart)
    0,                     // RAM Expansion (8K RAM Cart)
    0,                     // Cartridge ROM (8K)
    0,                     // System ROM (upper 4K)
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
        case IO_ACK: {
            // Acknowledge Interrupt (ignore data)
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
    if (address != IO_KEY && address != IO_ACK) {
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
