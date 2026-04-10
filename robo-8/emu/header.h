#include <stdint.h>

// NTSC: 227.5 color-burst cycles per line at 3.57954 MHz
// VDP: 455 pixels per line at 7.159090 MHz (x2)
// CPU: 455/7 = 65 cycles at 1.022727 MHz exactly (/7)
enum vdp_const {
    master_clk = 14318181,      // 14.318181 MHz
    pixel_clk = master_clk / 2, // ~7.1590905 MHz
    cpu_clk = master_clk / 14,  // ~1.022727 MHz
    frames_per_sec = 60,
    lines_per_frame = 262,
    lines_per_sec = frames_per_sec * lines_per_frame,  // 15720 Hz
    cpu_clk_per_line = 456/8,   // exactly 57 CPU cycles per line
};

// Memory
extern uint8_t SysROM[8*1024];
extern uint8_t MainRAM[8*1024];
extern uint8_t CartRAM[8*1024];
extern uint8_t CharROM[256*8];

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
extern uint8_t VidCtl;
extern uint8_t VidPal;
extern uint8_t KbdCol;
extern uint8_t PSGFrq;

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
    VCTL_COLOR     = 0x01,  // Color Semigraphics mode
    VCTL_W128      = 0x02,  // APA width 256/128 (column double mode)
    VCTL_V96       = 0x04,  // APA height 192/96 (row double mode)
    VCTL_APA       = 0x03,  // linear framebuffer at address $200
    VCTL_GREY      = 0x10,  // disable Colorburst for text legibility
};
enum vpal_bits {
    PAL_FG         = 0x07,     // low 3 bits
    PAL_BG         = 0x07<<3,  // next 3 bits
    PAL_BORDER     = 0x03<<6,  // top 2 bits
};
