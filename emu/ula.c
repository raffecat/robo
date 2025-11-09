#include "header.h"
#include <stdio.h>

enum io_reg {
    // DMA
    IO_SRCL    = 0xD0,   // DMA src low         (DMA uses current BNK8/BNKC mapping)
    IO_SRCH    = 0xD1,   // DMA src high        (BASIC must handle bank-crossing due to non-contiguous RAM)
    IO_DSTL    = 0xD2,   // DMA dest low
    IO_DSTH    = 0xD3,   // DMA dest high
    IO_DCTL    = 0xD4,   // DMA control         (7-6:direction 5:vertical 4:reverse 2-0:mode)
    IO_DRUN    = 0xD5,   // DMA count           (write: start DMA, 0=256; read: unused)
    IO_FILL    = 0xD6,   // DMA fill byte       (write: set Data Latch [FILL]; read: last value to/from IO_DDRW)
    IO_DDRW    = 0xD7,   // DMA data R/W        (read: reads from src++; write: writes to dest++)
    IO_DJMP    = 0xD8,   // DMA jump indirect   (read: indirect table jump [stalls for +1 cycle]; write: set Jump Table [TABLE])
    IO_AINC    = 0xD9,   // APA increment       (read: second byte of indirect jump; write: increment DST += 640)
    IO_BNK8    = 0xDA,   // Bank switch $8000   (low 6 bits)
    IO_BNKC    = 0xDB,   // Bank switch $C000   (low 6 bits)
    IO____1    = 0xDC,   // 
    IO____2    = 0xDD,   // 
    IO_KEYB    = 0xDE,   // Keyboard scan (write: set row; read: scan column) (0x80|zp: DMA fastload 5 bytes)
    IO_MULW    = 0xDF,   // Booth multiplier (write {AL,AH,BL,BH} read {RL,RH})

    // Audio
    IO_TON0    = 0xE0,   // PSG Ch.0 tone
    IO_PCH0    = 0xE1,   // PSG Ch.0 pitch
    IO_VOL0    = 0xE2,   // PSG Ch.0 volume
    IO_TON1    = 0xE3,   // PSG Ch.1 tone
    IO_PCH1    = 0xE4,   // PSG Ch.1 pitch
    IO_VOL1    = 0xE5,   // PSG Ch.1 volume
    IO_TON2    = 0xE6,   // PSG Ch.2 tone
    IO_PCH2    = 0xE7,   // PSG Ch.2 pitch
    IO_VOL2    = 0xE8,   // PSG Ch.2 volume
    IO_TON3    = 0xE9,   // PSG Ch.3 tone
    IO_PCH3    = 0xEA,   // PSG Ch.3 pitch
    IO_VOL3    = 0xEB,   // PSG Ch.3 volume
    IO_GP0R    = 0xEC,   // Game port 0 read
    IO_GP1R    = 0xED,   // Game port 1 read
    IO_GP2R    = 0xEE,   // Game port 2 read       (not fitted)
    IO_GP3R    = 0xEF,   // Game port 3 read       (not fitted)

    // Video
    IO_YLIN    = 0xF0,   // current Y-line         (read: V-counter; write: wait for VBlank)
    IO_YCMP    = 0xF1,   // compare Y-line         (read/write, 0xFF won't trigger)
    IO_SCRH    = 0xF2,   // horizontal scroll      (tile offset from 0, wraps)
    IO_SCRV    = 0xF3,   // vertical scroll        (row offset from 0, wraps)
    IO_FINH    = 0xF4,   // horizontal fine scroll (top 3 bits)
    IO_FINV    = 0xF5,   // vertical fine scroll   (top 3 bits)
    IO_VCTL    = 0xF6,   // video control          (7:APA 6:Grey 5:LMask 4:RMask 3-2:VCount 1-0:Divider)
    IO_VENA    = 0xF7,   // video enable           (7:VSyncI 6:VCmpI 5:HSyncI 4:PwrLED 3:CapLED 2:HDMA_En 1:Spr_En 0:BG_En)
    IO_VSTA    = 0xF8,   // interrupt status       (7:VSyncI 6:VCmpI 5:HSyncI)  (read:status / write:clear)
    IO_VMAP    = 0xF9,   // name table size        (4:4 width 32,64,128,256; height 32,64,128,256)
    IO_VTAB    = 0xFA,   // name table base        (high byte)
    IO_VBNK    = 0xFB,   // tile bank R/W          (write: [aaaadddd] bank addr,data; read: [aaaa----] read data)
    IO_PALA    = 0xFC,   // palette address        (direct palette-memory address, top bit enables auto-increment)
    IO_PALD    = 0xFD,   // palette data R/W       (direct palette-memory data, increments address if enabled)
    IO_SPRA    = 0xFE,   // sprite address         (direct sprite-memory address)
    IO_SPRD    = 0xFF,   // sprite data R/W        (direct sprite-memory data, increments address)
};

uint8_t OpenBus[16*1024] = { 0xE1 };
uint8_t SysROM[16*1024];
uint8_t MainRAM_0[16*1024];
uint8_t MainRAM_1[16*1024];
uint8_t CartRAM[16*1024];
uint8_t VRAM[VRAM_SIZE];
uint8_t PAL_RAM[PAL_SIZE];
uint8_t SPR_RAM[SPR_SIZE];

/*vid*/ uint8_t  VidYCmp  = 0xE8;    // 8-bit Y-line compare register
/*vid*/ uint8_t  VidScrH  = 0x2F;    // 3-bit horizontal tile scroll
/*vid*/ uint8_t  VidScrV  = 0x8C;    // 3-bit vertical tile scroll
/*vid*/ uint8_t  VidFinH  = 0x71;    // 3-bit horizontal fine scroll
/*vid*/ uint8_t  VidFinV  = 0x66;    // 3-bit vertical fine scroll
/*vid*/ uint8_t  VidCtl   = 0x2E;    // 8-bit video control
/*vid*/ uint8_t  VidEna   = 0x23;    // 8-bit register
/*vid*/ uint8_t  VidSta   = 0x7F;    // 8-bit register         -- reset to 000 (Interrupts)
/*vid*/ uint8_t  NameSize = 0x07;    // 4-bit name table size (2:2 width 32,64,128,256; height 32,64,128,256)
/*vid*/ uint8_t  NameBase = 0x18;    // 6-bit name table page address (high 6 bits)
static uint8_t  PalAddr   = 0x2C;     // 6-bit register (0-63)
static uint8_t  SprAddr   = 0x61;     // 8-bit register (0-159)

static uint16_t DMA_Src   = 0x1111;   // 16-bit counter
static uint16_t DMA_Dst   = 0x2222;   // 16-bit counter
static uint8_t  DMA_Ctl   = 0x33;     // 8-bit register
static uint8_t  DMA_Run   = 0x00;     // 8-bit counter          -- reset to 0x00 (Stop DMA)
static uint8_t  DMA_DL    = 0x77;     // 8-bit [FILL] data latch
static uint8_t  DMA_Table = 0x55;     // 8-bit [TABLE] register
static uint8_t  Bank8     = 0x05;     // 4-bit register (0-15)
static uint8_t  BankC     = 0x00;     // 4-bit register (0-15)  -- reset to 0x00 (ROM bank 0)
static uint8_t  KbdCol    = 0x03;     // 4-bit register (0-15)

static uint16_t DMA_sinc  = 0x01;     // internal: DMA src increment
static uint16_t DMA_dinc  = 0x01;     // internal: DMA dest increment

static uint8_t* BankMap[16] = {
    // ROM area
    SysROM,                // System ROM
    OpenBus,               // Reserved for System ROM
    OpenBus,               // Reserved for System ROM
    OpenBus,               // Reserved for System ROM
    // Expansion area
    OpenBus,               // Reserved for Expansion Port
    OpenBus,               // Reserved for Expansion Port
    OpenBus,               // Reserved for Expansion Port
    OpenBus,               // Reserved for Expansion Port
    // Cartridge area
    CartRAM,               // 16K RAM Cart
    OpenBus,
    OpenBus,
    OpenBus,
    OpenBus,
    OpenBus,
    OpenBus,
    OpenBus,
};

static uint8_t BankMapWR[16] = {
    // ROM area
    0,                     // System ROM
    0,                     // Reserved for System ROM
    0,                     // Reserved for System ROM
    0,                     // Reserved for System ROM
    // Expansion area
    0,                     // Reserved for Expansion Port
    0,                     // Reserved for Expansion Port
    0,                     // Reserved for Expansion Port
    0,                     // Reserved for Expansion Port
    // Cartridge area
    1,                     // 16K RAM Cart
    0,
    0,
    0,
    0,
    0,
    0,
    0,
};

static uint8_t* RAMView[4] = {
    MainRAM_0,  // Hard wired
    MainRAM_1,  // Hard wired
    OpenBus,    // $8000 bank
    SysROM,     // $C000 bank
};

static uint8_t RAMViewWR[4] = {
    1,  // Writeable
    1,  // Writeable
    0,  // Read only
    0,  // Read only
};

void dma_interlock();
uint8_t dma_read_cycle();
void dma_write_cycle();

static void dma_update_inc() {
    int width = 1 << (6+(NameSize>>2)); // 64/128/256/512
    DMA_sinc = (DMA_Ctl & dma_ctl_reverse) ? 65536-1 : 1;        // -1 : 1
    // Only DST HW implements Vertical (+/- width) and +640 (+512+128)
    DMA_dinc = (DMA_Ctl & dma_ctl_reverse) ?
        ((DMA_Ctl & dma_ctl_vertical) ? 65536-width : 65536-1) : // -vert : -1
        ((DMA_Ctl & dma_ctl_vertical) ? width : 1);              //  vert : 1
}

static uint8_t ula_io_read(uint16_t address) {
    // catch up the VDP before reading IO
    advance_vdp();
    // open bus value
    uint8_t value = 0xEE;
    // now read the IO port
    switch (address) {
        // D-page
        case IO_SRCL: value = DMA_Src & 0xFF; break; // $D0: DMA src low
        case IO_SRCH: value = DMA_Src >> 8;   break; // $D1: DMA src high
        case IO_DSTL: value = DMA_Dst & 0xFF; break; // $D2: DMA dest low
        case IO_DSTH: value = DMA_Dst >> 8;   break; // $D3: DMA dest high
        case IO_DCTL: value = DMA_Ctl;        break; // $D4: DMA control
        case IO_DRUN:                         break; // $D5: unused
        case IO_FILL: value = DMA_DL;         break; // $D6: read FILL byte [data latch]
        case IO_DDRW: {                              // $D7: DMA data R/W (read from DMA_Src)
            // DMA Read cycle, as CPU memory access.
            dma_interlock();
            value = dma_read_cycle();
            break;
        }
        case IO_DJMP: {                              // $D8: DMA jump indirect (read low byte)
            // read from DMA_Src into DMA_DL
            // this costs an extra CPU cycle
            DMA_DL = RAMView[DMA_Src >> 14][DMA_Src & 0x3FFF];
            DMA_Src = (DMA_Src + DMA_sinc) & 0xFFFF;
            clockticks6502++; // XXX wrong: should be 2 pixel cycles (one VRAM cycle)
            // read low byte from jump table
            uint16_t entry = (DMA_Table<<8)|DMA_DL;
            value = RAMView[entry >> 14][entry & 0x3FFF];
            break;
        }
        case IO_AINC: {                              // $D9: DMA jump indirect (read high byte)
            // read high byte from jump table
            uint16_t entry = (DMA_Table<<8)|DMA_DL|1;
            value = RAMView[entry >> 14][entry & 0x3FFF];
            break;
        }   
        case IO_BNK8: value = Bank8; break;          // $DA: Bank switch 0x8000  (low 4 bits)
        case IO_BNKC: value = BankC; break;          // $DB: Bank switch 0xC000  (low 4 bits)
        case IO_KEYB: {                              // $DE: Keyboard scan (read: scan column)
            value = scanKeyCol(KbdCol);
            break;
        }
        case IO_MULW: break;                         // $DF: Booth multiplier? (write {AL,AH,BL,BH} read {RL,RH})

        // E-page
        case IO_TON0:       // $E0: PSG Ch.0 tone
            break;
        case IO_PCH0:       // $E1: PSG Ch.0 pitch
            break;
        case IO_VOL0:       // $E2: PSG Ch.0 volume
            break;
        case IO_TON1:       // $E3: PSG Ch.1 tone
            break;
        case IO_PCH1:       // $E4: PSG Ch.1 pitch
            break;
        case IO_VOL1:       // $E5: PSG Ch.1 volume
            break;
        case IO_TON2:       // $E6: PSG Ch.2 tone
            break;
        case IO_PCH2:       // $E7: PSG Ch.2 pitch
            break;
        case IO_VOL2:       // $E8: PSG Ch.2 volume
            break;
        case IO_TON3:       // $E9: PSG Ch.3 tone
            break;
        case IO_PCH3:       // $EA: PSG Ch.3 pitch
            break;
        case IO_VOL3:       // $EB: PSG Ch.3 volume
            break;

        // F-page
        case IO_YLIN:       // $F0: current Y-line         (read: V-counter; write: wait for VBlank)
            value = vdp_vcount & 0xFF;
            break;
        case IO_YCMP:       // $F1: compare Y-line         (read/write, $FF won't trigger)
            value = VidYCmp;
            break;
        case IO_SCRH: {     // $F2: horizontal scroll
            value = VidScrH;
            break;
        }
        case IO_SCRV: {     // $F3: vertical scroll
            value = VidScrV;
            break;
        }
        case IO_FINH:       // $F4: horizontal fine scroll (top 3 bits)
            value = VidFinH << 5; // top 3 bits are fine offset
            break;
        case IO_FINV:       // $F5: vertical fine scroll   (top 3 bits)
            value = VidFinV << 5; // top 3 bits are fine offset
            break;
        case IO_VCTL:       // $F6: video control          (7:APA 6:Grey 5:Double 4:HCount 3-2:VCount 1-0:Divider) (see below)
            value = VidCtl;
            break;
        case IO_VENA:       // $F7: interrupt enable       (7:VSync 6:VCmp 5:HSync 3:BG_En 2:Spr_En 1:HDMA_En)
            value = VidEna;
            break;
        case IO_VSTA:       // $F8: interrupt status/clear   (7:VSync 6:VCmp 5:HSync)  (write:clear)
            value = VidSta;
            break;
        case IO_VMAP:       // $F9: name table size
            value = NameSize;
            break;
        case IO_VTAB:       // $FA: name table base        (high byte, top 6 bits)
            value = NameBase;
            break;
        case IO_VBNK:       // $FB: tile bank R/W          (write: [aaaadddd] bank addr,data; read: [aaaa----] read data)
            // XXX TODO
            break;
        case IO_PALA:                     // $FC: palette address
            value = PalAddr;
            break;
        case IO_PALD:                     // $FD: palette data R/W
            value = PAL_RAM[PalAddr];
            PalAddr = (PalAddr+1) & (PAL_SIZE-1);   // 6-bit register
            break;
        case IO_SPRA:                     // $FE: sprite address
            value = SprAddr; // was &127
            break;
        case IO_SPRD:                     // $FF: sprite data R/W
            if (SprAddr < SPR_SIZE) {     // (was &127)
                value = SPR_RAM[SprAddr];
            }
            SprAddr++;                    // 8-bit register
            break;        
    }
    // printf("IO Read: [$%02X] -> $%02X\n", address, value);
    return value;
}

static void ula_io_write(uint16_t address, uint8_t value) {
    // catch up the VDP before reading IO
    advance_vdp();
    // now write the IO value
    switch (address) {
        // D-page
        case IO_SRCL:       // $D0: DMA src low
            DMA_Src = (DMA_Src & 0xFF00) | value; // 16-bit register, set low 8 bits
            break;
        case IO_SRCH:       // $D1: DMA src high
            DMA_Src = (DMA_Src & 0x00FF) | (value << 8); // 16-bit register, set high 8 bits
            break;
        case IO_DSTL:       // $D2: DMA dest low
            DMA_Dst = (DMA_Dst & 0xFF00) | value; // 16-bit register, set low 8 bits
            break;
        case IO_DSTH:       // $D3: DMA dest high
            DMA_Dst = (DMA_Dst & 0x00FF) | (value << 8); // 16-bit register, set high 8 bits
            break;
        case IO_DCTL:                        // $D4: DMA control
            DMA_Ctl = value;                 // 8-bit register
            dma_update_inc();
            break;
        case IO_DRUN: {                      // $D5: DMA count
            DMA_Run = value;                 // 8-bit register
            do {
                dma_interlock();             // HW gates each DMA cycle
                dma_read_cycle();
                clockticks6502++;            // +1 RAM cycle (one CPU cycle)
                dma_write_cycle();
                clockticks6502++;            // +1 RAM cycle (one CPU cycle)
                advance_vdp();               // in case DMA write affects next pixel (XXX can it?)
                DMA_Run--;
            } while (DMA_Run > 0);
            break;
        }
        case IO_FILL:                        // $D6: set FILL byte [data latch]
            DMA_DL = value;
            break;
        case IO_DDRW: {                      // $D7: DMA data R/W (write to DMA_Dst)
            // DMA Write cycle
            if ((DMA_Ctl & DMA_Mode) == DMA_APA) {
                // Delayed DMA cycle on the next SYNC (stalling OP-FETCH)
                // Latch into TABLE, because APA Cycle uses DL.
                DMA_Table = value;
                dma_interlock();
                dma_read_cycle();
                clockticks6502++;            // +1 RAM cycle (one CPU cycle)
                dma_write_cycle();
                clockticks6502++;            // +1 RAM cycle (one CPU cycle)
                advance_vdp();               // in case DMA write affects next pixel (XXX can it?)
            } else {
                // DMA Write cycle, as CPU memory access.
                DMA_DL = value;              // latch into DL (transparent latch)
                dma_interlock();
                dma_write_cycle();
                advance_vdp();               // in case DMA write affects next pixel (XXX can it?)
            }
            break;
        }
        case IO_DJMP:                        // $D8: set Jump Table [TABLE]
            DMA_Table = value;               // 8-bit register [TABLE]
            break;
        case IO_AINC: {                      // $D9: increment DST += 640
            DMA_Dst = (DMA_Dst + 512) & 0xFFFF; // bit 9 (CLK 1)
            DMA_Dst = (DMA_Dst + 128) & 0xFFFF; // bit 7 (CLK 2)
            break;
        }
        case IO_BNK8:                        // $DA: Bank switch $8000
            Bank8 = value & 0xF;             // 4-bit register
            RAMView[2] = BankMap[Bank8];     // update active-bank table
            RAMViewWR[2] = BankMapWR[Bank8]; // [2] is the slot at $8000
            break;
        case IO_BNKC:                        // $DB: Bank switch $C000
            BankC = value & 0xF;             // 4-bit register
            RAMView[3] = BankMap[Bank8];     // update active-bank table
            RAMViewWR[3] = BankMapWR[Bank8]; // [3] is the slot at $C000
            break;
        case IO_KEYB:                        // $DE: set keyboard scan column (4-bit)
            KbdCol = value & 0xF;
            break;
        case IO_MULW:                        // $DF: Booth multiplier? (write {AL,AH,BL,BH} read {RL,RH})
            break;

        // E-page
        case IO_TON0:       // $E0: PSG Ch.0 tone
            break;
        case IO_PCH0:       // $E1: PSG Ch.0 pitch
            break;
        case IO_VOL0:       // $E2: PSG Ch.0 volume
            break;
        case IO_TON1:       // $E3: PSG Ch.1 tone
            break;
        case IO_PCH1:       // $E4: PSG Ch.1 pitch
            break;
        case IO_VOL1:       // $E5: PSG Ch.1 volume
            break;
        case IO_TON2:       // $E6: PSG Ch.2 tone
            break;
        case IO_PCH2:       // $E7: PSG Ch.2 pitch
            break;
        case IO_VOL2:       // $E8: PSG Ch.2 volume
            break;
        case IO_TON3:       // $E9: PSG Ch.3 tone
            break;
        case IO_PCH3:       // $EA: PSG Ch.3 pitch
            break;
        case IO_VOL3:       // $EB: PSG Ch.3 volume
            break;

        // F-page
        case IO_YLIN:       // $F0: current Y-line         (write: wait for VBlank)
            // Stall the CPU
            while (!vdp_vblank) {
                clockticks6502++; // XXX wrong: count VDP cycles until VSync, derive CPU cycles
                advance_vdp();
            }
            break;
        case IO_YCMP:       // $F1: compare Y-line         (read/write, $FF won't trigger)
            VidYCmp = value;
            break;
        case IO_SCRH: {     // $F2: horizontal scroll
            // perform modulo on store because we OR VidScrH into video address
            // XXX problem in HW: if you change NameSize later!
            unsigned mapW = 32 << (NameSize >> 2);  // (top 2 bits of 4 are width: 32,64,128,256)
            VidScrH = value & (mapW-1);
            break;
        }
        case IO_SCRV: {     // $F3: vertical scroll
            // perform modulo on store because we OR VidScrV into video address
            // XXX problem in HW: if you change NameSize later!
            unsigned mapH = 32 << (NameSize & 3); //       (bottom 2 bits of 4 are height: 32,64,128,256)
            VidScrV = value & (mapH-1);
            break;
        }
        case IO_FINH:                    // $F4: horizontal fine scroll (top 3 bits)
            VidFinH = value >> 5;        // top 3 bits are fine offset
            break;
        case IO_FINV:                    // $F5: vertical fine scroll   (top 3 bits)
            VidFinV = value >> 5;        // top 3 bits are fine offset
            break;
        case IO_VCTL:                    // $F6: video control (7:APA 6:Grey 5:Double 4:HCount 3-2:VCount 1-0:Divider) (see below)
            VidCtl = value;
            break;
        case IO_VENA:                    // $F7: interrupt enable (7:VSync 6:YCmp 5:HSync 3:BG_En 2:Spr_En 1:HDMA_En)
            VidEna = value;
            break;
        case IO_VSTA:                    // $F8: interrupt status/clear (7:VSync 6:YCmp 5:HSync)
            VidSta &= ~(value & 0xE0);   // 3-bit register [VYH00000]
            break;
        case IO_VMAP:                    // $F9: name table size
            NameSize = value & 0xF;      // 4-bit register [0000WWHH]
            dma_update_inc();
            break;
        case IO_VTAB:                    // $FA: name table base (high byte)
            NameBase = value & 0xF8;     // top 5 bits (2K aligned)
            break;
        case IO_VBNK:                    // $FB: tile bank R/W (write: [aaaadddd] bank addr,data; read: [aaaa----] read data)
            // XXX
            break;
        case IO_PALA:                    // $FC: palette address
            PalAddr = value & (PAL_SIZE-1);
            break;
        case IO_PALD:                    // $FD: palette data R/W
            PAL_RAM[PalAddr] = value;
            PalAddr = (PalAddr+1) & (PAL_SIZE-1);
            break;
        case IO_SPRA:                    // $FE: sprite address
            SprAddr = value; // was &127
            break;
        case IO_SPRD:                     // $FF: sprite data R/W
            if (SprAddr < SPR_SIZE) {     // (was &127)
                SPR_RAM[SprAddr] = value;
            }
            SprAddr++;                    // 8-bit register
            break;
    }
    // printf("IO Write: [$%02X] <- $%02X\n", address, value);
}

void dma_interlock() {
    if (DMA_Ctl & (dma_ctl_to_vram|dma_ctl_from_vram)) { // HW is indiscriminate!
        while (vdp_vbusy) {
            clockticks6502++; // XXX wrong: count VDP cycles until !VBusy, derive CPU cycles
            advance_vdp();
        }
    }
}

uint8_t dma_read_cycle() {
    uint8_t value = 0xEE;
    switch (DMA_Ctl & DMA_Mode) {
        case DMA_Fill: {
            // Dummy read cycle: do nothing.
            return DMA_DL;
        }
        case DMA_APA: {
            // APA Read.
            if (DMA_Ctl & dma_ctl_from_vram) {
                // VRAM address is divided by 8 (HW: select on VRAM addr bus)
                value = VRAM[(DMA_Src>>3) & 0x3FFF]; // divide by 8 (640x200)
            } else {
                value = RAMView[DMA_Src>>14][DMA_Src & 0x3FFF];
            }
            break;
        }
        case DMA_Palette: {
            // Read palette memory, 5-bit address.
            value = PAL_RAM[DMA_Src & (PAL_SIZE-1)];
            break;
        }
        case DMA_Sprite: {
            // Read sprite memory, 7-bit address.
            if (DMA_Src < SPR_SIZE) {     // (was &127)
                value = SPR_RAM[DMA_Src];
            }
            break;
        }
        case DMA_SprClr: {
            // Read sprite memory, 7-bit address ignoring low 2 bits.
            // Quirk: HW doesn't implement inc-src-by-four.
            if (DMA_Src < SPR_SIZE) {     // (was &127)
                value = SPR_RAM[DMA_Src];
            }
            break;
        }
        default: {
            // Read RAM/VRAM in all other modes.
            if (DMA_Ctl & dma_ctl_from_vram) {
                value = VRAM[DMA_Src & 0x3FFF];
            } else {
                value = RAMView[DMA_Src>>14][DMA_Src & 0x3FFF];
            }
        }
    }
    DMA_DL = value; // latch into DL for FILL-readback
    DMA_Src = (DMA_Src + DMA_sinc) & 0xFFFF;
    return value;
}

void dma_write_cycle() {
    switch (DMA_Ctl & DMA_Mode) {
        case DMA_Copy:
        case DMA_Fill: {
            // Write the DL value.
            if (DMA_Ctl & dma_ctl_to_vram) {
                VRAM[DMA_Dst & 0x3FFF] = DMA_DL;
            } else {
                if (RAMViewWR[DMA_Dst>>14]) {
                    RAMView[DMA_Dst>>14][DMA_Dst & 0x3FFF] = DMA_DL;
                }
            }
            DMA_Dst = (DMA_Dst + DMA_dinc) & 0xFFFF;
            break;
        }
        case DMA_Masked: {
            // Only write if the value is non-zero.
            if (DMA_DL != 0x00) {
                if (DMA_Ctl & dma_ctl_to_vram) {
                    VRAM[DMA_Dst & 0x3FFF] = DMA_DL;
                } else {
                    if (RAMViewWR[DMA_Dst>>14]) {
                        RAMView[DMA_Dst>>14][DMA_Dst & 0x3FFF] = DMA_DL;
                    }
                }
            }
            // Increment unconditionally.
            DMA_Dst = (DMA_Dst + DMA_dinc) & 0xFFFF;
            break;
        }
        case DMA_AltFill: {
            // Alternating write pattern.
            uint8_t wr = (DMA_Dst&1) ? DMA_Table : DMA_DL; // 0=[FILL] 1=[TABLE]
            if (DMA_Ctl & dma_ctl_to_vram) {
                VRAM[DMA_Dst & 0x3FFF] = wr;
            } else {
                if (RAMViewWR[DMA_Dst>>14]) {
                    RAMView[DMA_Dst>>14][DMA_Dst & 0x3FFF] = wr;
                }
            }
            DMA_Dst = (DMA_Dst + DMA_dinc) & 0xFFFF;
            break;
        }
        case DMA_APA: {
            // APA masked write.
            uint8_t bit_mask; // HW uses AND-OR gates:
            if (VidCtl & VCTL_4BPP) {
                bit_mask = 15 << ((DMA_Dst&4)>>2); // position %1111 mask using bit %1xx
            } else {
                bit_mask = 3 << ((DMA_Dst&6)>>1); // position %11 mask using bits %11x
            }
            // Data Bus multiplexor, downstream of DL.
            uint8_t wr = (DMA_DL & ~bit_mask) | (DMA_Table & bit_mask); // APA mask
            if (DMA_Ctl & dma_ctl_to_vram) {
                // VRAM address is divided by 8 (HW: select on VRAM addr bus)
                VRAM[(DMA_Dst>>3) & 0x3FFF] = wr;
            } else {
                if (RAMViewWR[DMA_Dst>>14]) {
                    RAMView[DMA_Dst>>14][DMA_Dst & 0x3FFF] = wr;
                }
            }
            DMA_Dst = (DMA_Dst + DMA_dinc) & 0xFFFF;
            break;
        }
        case DMA_Palette: {
            // Write palette memory, 5-bit address
            PAL_RAM[DMA_Dst & (PAL_SIZE-1)] = DMA_DL;
            DMA_Dst = (DMA_Dst + DMA_dinc) & 0xFFFF;
            break;
        }
        case DMA_Sprite: {
            // Write sprite memory, 7-bit address
            if (DMA_Dst < SPR_SIZE) {     // (was &127)
                SPR_RAM[DMA_Dst] = DMA_DL;
            }
            DMA_Dst = (DMA_Dst + DMA_dinc) & 0xFFFF;
            break;
        }
        case DMA_SprClr: {
            // Write $FF to sprite memory, 7-bit address ignoring low 2 bits.
            if (DMA_Dst < SPR_SIZE) {     // (was &127)
                SPR_RAM[DMA_Dst & 0xFC] = 0xFF;
            }
            // Increment DST by 4 (HW only wired up for DST)
            // Vertical mode overrides this (doesn't increment low bits)
            uint16_t inc = (DMA_dinc==1 ? 4 : (DMA_dinc == 65535 ? 65532 : DMA_dinc));
            DMA_Dst = (DMA_Dst + inc) & 0xFFFF;
            break;
        }
    }

}

uint8_t read6502(uint16_t address) {
    // address < 0xC0 or address >= 0x100
    if ((unsigned)address - 0xC0 >= 0x40) {
        return RAMView[address >> 14][address & 0x3fff]; // banked RAM/ROM
    } else {
        return ula_io_read(address);
    }
}

void write6502(uint16_t address, uint8_t value) {
    // address < 0xC0 or address >= 0x100
    if ((unsigned)address - 0xC0 >= 0x40) {
        unsigned page = address >> 14;
        if (RAMViewWR[page]) {
            RAMView[page][address & 0x3fff] = value; // banked RAM/ROM
        }
    } else {
        ula_io_write(address, value);
    }
}
