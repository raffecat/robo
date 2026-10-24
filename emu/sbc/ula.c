#include "header.h"
#include <stdio.h>

// XXX: Reveal, TapeMotor
enum io_reg {
    IO_KEY   = 0xF8, // ASCII Keyboard read (7-bit)
    IO_CAS   = 0xF9, // Cassette IO (3:Speaker 2:RTS 1:TXD 0:TapeTx) / Read (7:KeyLatch 2:CTS 1:RXD 0:TapeRx)
    IO_XXA   = 0xFA, // Reserved
    IO_XXB   = 0xFB, // Reserved
    IO_XXC   = 0xFC, // Reserved
    IO_XXD   = 0xFD, // Reserved
    IO_XXE   = 0xFE, // Reserved
    IO_XXF   = 0xFF  // Reserved
};

uint8_t OpenBus[8*1024] = { 0xEE };
uint8_t SysROM[8*1024];
uint8_t MainRAM[8*1024];
uint8_t VRAM[8*1024];

extern uint16_t vdp_vcount; // 9-bit vertical line count

uint8_t  KbdCol    = 0x03;   // 4-bit register

uint8_t* MemMap[8] = {
    MainRAM,               // Base 8K RAM
    OpenBus,               // 8K RAM Board
    OpenBus,               // RAM Expansion
    OpenBus,               // RAM Expansion
    OpenBus,               // RAM Expansion
    VRAM,                  // VRAM (8K)
    OpenBus,               // IO Area (8K)
    SysROM,                // System ROM (upper 8K)
};

// Writeable ROM area for Monitor debugging?
#define wr_rom 0

static uint8_t MemMapWR[8] = {
    1,                     // 4K Main RAM
    0,                     // 8K RAM Board
    0,                     // RAM Expansion
    0,                     // RAM Expansion
    0,                     // RAM Expansion
    1,                     // VRAM (8K)
    0,                     // IO Area (8K)
    wr_rom,                // System ROM (upper 8K)
};

static int key_latch = 0;
static char last_key = 0;

static uint8_t ula_io_read(uint16_t address) {
    // catch up the VDP before reading IO
    advance_vdp();
    uint8_t value = 0xEE;
    // now read the IO port
    switch (address) {
        // F-page
        case IO_KEY: {
            key_latch = 0;
            return last_key;
        }
        case IO_CAS: {
            return (key_latch<<7); // KeyLatch:7
        }
        default: {
            // Read back from RAM
            return MainRAM[address];
        }
    }
    if (address != IO_CAS) {
        printf("IO Read: [$%02X] -> $%02X\n", address, value);
    }
    return value;
}

void ula_key_strobe(uint8_t key) {
    // new keypress
    last_key = key;
    key_latch = 1;
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
    }
    // Write-through to RAM
    MainRAM[address] = value;
    // log IO writes
    printf("IO Write: [$%02X] <- $%02X\n", address, value);
}

uint8_t read6502(uint16_t address) {
    // address < 0xF0 or address >= 0x100
    if ((unsigned)address - 0xF0 >= 0x10) {
        return MemMap[address >> 13][address & 0x1fff]; // 8K Banks
    } else {
        return ula_io_read(address);
    }
}

void write6502(uint16_t address, uint8_t value) {
    // address < 0xF0 or address >= 0x100
    if ((unsigned)address - 0xF0 >= 0x10) {
        unsigned page = address >> 13;
        if (MemMapWR[page]) {
            MemMap[page][address & 0x1fff] = value; // 8K Banks
        }
    } else {
        ula_io_write(address, value);
    }
}
