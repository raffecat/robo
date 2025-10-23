#include <stdint.h>

// Memory
#define VRAM_SIZE 16384
extern uint8_t SysROM[16*1024];
extern uint8_t MainRAM_0[16*1024];
extern uint8_t MainRAM_1[16*1024];
extern uint8_t CartRAM[16*1024];
extern uint8_t VRAM[VRAM_SIZE];
extern uint8_t PAL_RAM[64];
extern uint8_t SPR_RAM[160]; // 160 for 80-col color mode

// Fake6502
void reset6502();
void exec6502(uint32_t tickcount);
void step6502();
void request_irq();
void request_nmi();
extern uint32_t clockticks6502;
extern uint16_t pc;
extern uint8_t sp, a, x, y, status;
extern uint8_t dbg_enable;
extern uint16_t dbg_break;
extern uint8_t pend_irq;

// debugger
extern uint16_t dbg_break;
void dbg_decode_next_op(uint16_t pc);

// ULA
uint8_t read6502(uint16_t address);
void write6502(uint16_t address, uint8_t value);
extern uint8_t VidYCmp;
extern uint8_t VidScrH;
extern uint8_t VidScrV;
extern uint8_t VidFinH;
extern uint8_t VidFinV;
extern uint8_t VidCtl;
extern uint8_t VidEna;
extern uint8_t VidSta;
extern uint8_t PendInt;
extern uint8_t NameSize;
extern uint8_t NameBase;

// render
int init_render();
void final_render();
void render();
void advance_vdp();
extern uint16_t vdp_vcount; // 9-bit vertical line count
extern uint8_t vdp_vblank;  // 1-bit latch
extern uint8_t vdp_vbusy; // 1-bit latch (VDP is using VRAM)

// SDL
uint8_t scanKeyCol(uint8_t);

enum vctl_bits {
    VCTL_APA       = 0x80,  // linear framebuffer at address 0 (or linear 8x8 tiles?)
    VCTL_NARROW    = 0x40,  // 5x8 tiles at 2bpp only; left 5 pixels of each tile (64 columns)
    VCTL_16COL     = 0x20,  // attributes contain [BBBBFFFF] BG,FG colors (2+2x16 colours)
    VCTL_LATCH     = 0x20,  // in APA mode, latch color on zero (filled shapes mode)
    VCTL_GREY      = 0x10,  // disable Colorburst for text legibility
    VCTL_V240      = 0x0C,  // 240 visible lines per frame
    VCTL_V224      = 0x08,  // 224 visible lines per frame
    VCTL_V200      = 0x04,  // 200 visible lines per frame
    VCTL_V192      = 0x00,  // 192 visible lines per frame
    VCTL_H320      = 0x02,  // 320 visible pixels per line (shift rate)
    VCTL_H256      = 0x00,  // 256 visible pixels per line (shift rate)
    VCTL_4BPP      = 0x01,  // divide clock by 4, use 4 bits per pixel (double-width)
    VCTL_2BPP      = 0x00,  // divide clock by 2, use 2 bits per pixel (square pixels)
};
enum vena_bits {
    VENA_VSync     = 0x80,
    VENA_VCmp      = 0x40,
    VENA_HSync     = 0x20,
    VENA_Pwr_LED   = 0x08,
    VENA_Caps_LED  = 0x04,
    VENA_Spr_En    = 0x02,
    VENA_BG_En     = 0x01,
};
enum vsta_bits {
    VSTA_VSync     = 0x80,
    VSTA_VCmp      = 0x40,
    VSTA_HSync     = 0x20,
};
enum dma_ctl {
    // direction
    dma_ctl_to_vram = 0x40,
    dma_ctl_from_vram = 0x80,
    // flags
    dma_ctl_vertical = 0x20,
    dma_ctl_reverse = 0x10,
    // mode
    DMA_Copy        = 0x00,  // copy bytes from source to destinaton
    DMA_Fill        = 0x01,  // using fill byte (write IO_DJMP)
    DMA_Masked      = 0x02,  // copy pixels, skip zero pixels (shares APA HW)
    DMA_APA         = 0x03,  // APA addressing: low 3 bits of address select pixel; BPP from VCTL
    DMA_Palette     = 0x04,  // read src / write dest is palette memory, SRCL/DSTL only; ignores direction
    DMA_Sprite      = 0x05,  // read src / write dest is sprite memory, SRCL/DSTL only; ignores direction
    DMA_SprClr      = 0x06,  // write $FF to Y coords of sprites (inc by 4), DSTL only; ignores direction
    // mode mask
    DMA_Mode        = 0x07,  // low 3 bits
};
