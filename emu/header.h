#include <stdint.h>

// Memory
#define VRAM_SIZE 16384
extern uint8_t SysROM[16*1024];
extern uint8_t MainRAM_0[16*1024];
extern uint8_t MainRAM_1[16*1024];
extern uint8_t CartRAM[16*1024];
extern uint8_t VRAM[VRAM_SIZE];
extern uint8_t PAL_RAM[64];
extern uint8_t SPR_RAM[128];

// Fake6502
void reset6502();
void exec6502(uint32_t tickcount);
void nmi6502();
void irq6502();
extern uint32_t clockticks6502;

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

// SDL
uint8_t scanKeyCol(uint8_t);
