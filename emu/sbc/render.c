// Robo Emulator - Renderer

#include <SDL2/SDL.h>
#include <string.h>
#include "header.h"

// NTSC Vert: 192 + 25 + 9 + 3 + 8 + 25 = 262
// NTSC Horz: 128 + 31 + 6 + 16 + 2 + 10 + 4 + 31 = 228
// NTSC Final: 9 + 256 + 67 + 11 + 32 + 4 + 20 + 8 + 56 = 456 (x2)
// NTSC NEW: 32 + 4+20 + 8 + 56 + 256 + 64 + 16 = 456
enum vtiming {
    fb_syncwidth = 16 + 32 + 4+20 + 8,
    fb_hdelay = 8,    // 1 character (prefetch) + 1 pixel (output delays)
    fb_viswidth = 320,
    fb_visheight = 192,
    fb_hleftbord = 24-fb_hdelay,  // left border in FB
    fb_hrightbord = 32, // right border in FB
    fb_vbord = 25,      // border height in FB
    fb_width = fb_viswidth+(fb_hleftbord+fb_hrightbord),
    fb_height = fb_visheight+(fb_vbord+fb_vbord),
    width = fb_width*2,  // MUST be twice as wide
    height = fb_height*2, // MUST be twice as high
};

//                         3:8
// 9                     = 000 001001    1001          (2A 2A)   2-AND        6 x 2-AND (2 ICs)
// 9+256                 = 100 001001    1001    +1    (2A)      2-AND        5 x 3-AND (2 ICs)
// 9+256+48              = 100 111001    1001+1  +2    (3+2A)    3-AND
// 9+256+48+11           = 101 000100    101     +1    (2A)      2-AND 2-AND
// 9+256+48+11+32        = 101 100100    101     +2    (3A)      3-AND                     (1 3:8)
// 9+256+48+11+32+4      = 101 101000    101     +2    (3A)      3-AND            (7 x 2A) (2 ICs)
// 9+256+48+11+32+4+20   = 101 111100    101+2   +2    (3A)      3-AND            (4 x 3A) (2 ICs)
// 9+256+48+11+32+4+20+8 = 110 000100    11      +1    (2A)      2-AND 2-AND
// 456                   = 111 001000    11      +2    (2A)      3-AND


static SDL_Window* window = 0;
static SDL_Renderer* renderer = 0;
static Uint64 frame_due = 0;
static SDL_Texture* texture = 0;
static uint64_t vdp_clk = 0;
//static int vdp_nextbus = 0;

// vdp timing
uint16_t vdp_hcount = 0; // 8-bit horizontal count
uint16_t vdp_vcount = 0; // 9-bit vertical line count (visible to ula.c)
uint16_t vdp_base = 0xA000; // 16-bit video page counter
uint16_t vdp_address = 0xA000; // 16-bit video page counter
uint8_t vdp_hborder = 1;  // 1-bit latch (visible to ula.c)
uint8_t vdp_hblank = 0;  // 1-bit latch
uint8_t vdp_hc1en = 0;  // 1-bit latch (apply C1 control codes)
uint8_t vdp_vborder = 0;  // 1-bit latch
uint8_t vdp_vblank = 0;  // 1-bit latch (visible to ula.c)

// pixel pipeline
static uint8_t vdp_latch = 0x12; // 8-bit character latch
static uint8_t vdp_shift = 0xF3; // 8-bit pixel shift register

// colors.py
static uint32_t hw_pal[16] = { // RGB
0x000000,
0xffffff,
};

// framebuffer
// SDL_PIXELFORMAT_ARGB8888 uses 32-bit integers; byte-order depends on the platform's endianness.
// MSB -> { alpha, red, green, blue } <- LSB
static uint32_t FB[fb_width*fb_height]; // 300K!
//static uint32_t* FBspan = &FB[0];
static uint16_t FBcol = 455 - (fb_hdelay+fb_viswidth+fb_hrightbord+fb_syncwidth);
static uint16_t FBrow = 0;

int init_render() {
    // check horizontal timing
    // 32 + 4+20 + 8 + 56 + 256 + 64 + 16 = 456
    int htime = fb_hdelay+fb_viswidth+fb_hrightbord+fb_syncwidth+fb_hleftbord;
    if (htime != 456) {
        printf("wrong horizontal timing: %d\n", htime);
        return 0;
    }
    SDL_Init(SDL_INIT_VIDEO|SDL_INIT_EVENTS);
    window = SDL_CreateWindow(
        "Frontier SBC",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        width, height,
        0
    );
    if (!window) return 0;
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE|SDL_RENDERER_PRESENTVSYNC); // SDL_RENDERER_ACCELERATED
    if (!renderer) return 0;
    // if (!SDL_RenderSetLogicalSize(renderer, width, height)) return 0;
    texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING,
        width, height
    );
    if (!texture) return 0;
    return 1;
}

void final_render() {
    SDL_DestroyTexture(texture); texture=0;
    SDL_DestroyRenderer(renderer); renderer=0;
    SDL_DestroyWindow(window); window=0;
    SDL_Quit();
}

void render() {
    void* pixels;
    int pitch;
    if (SDL_LockTexture(texture, NULL, &pixels, &pitch) != 0) {
        return;
    }

    // render the framebuffer.
    // memcpy(pixels, FB, sizeof(FB));
    char* dst_row = pixels; // pitch is in bytes
    uint32_t* src_row = FB;    // all FB addressing is in pixels
    for (int y=0; y<fb_height; y++) {
        char* dst_next_row = dst_row + pitch;
        uint32_t* to1 = (uint32_t*)dst_row;
        uint32_t* to2 = (uint32_t*)dst_next_row;
        uint32_t* from = src_row;
        for (int x=0; x<fb_width; x++) {
            // window must be TWICE as high as FB
            // window must be TWICE as wide as FB
            // fill four pixels:
            to1[0] = from[0];
            to1[1] = from[0];
            to2[0] = from[0];
            to2[1] = from[0];
            to1 += 2;
            to2 += 2;
            from += 1;
        }
        dst_row += pitch + pitch; // advance two rows
        src_row += fb_width;      // advance one row
    }

    SDL_UnlockTexture(texture);    
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, NULL, NULL);
    // wait until frame_due has arrived.
    if (!frame_due) frame_due = SDL_GetTicks64();
    Uint64 now;
    while ((now=SDL_GetTicks64()) <= frame_due) {
        SDL_Delay(1);
    }
    SDL_RenderPresent(renderer); // wait for VSync (snap to 60fps)
    frame_due = SDL_GetTicks64() + 16; // of 16.66666ms
}

// advance the renderer to catch up with the CPU clock (clockticks6502)
// the current vdp_clk has already been processed
void advance_vdp() {
    // NTSC: 14.31818 Mhz: VDP shift clk is 1/2 at 7.15909 MHz (139.68ns); CPU is 1/8 at 0.895 MHz
    // PAL 17.734475 MHz: VDP shift clk is 13/32 at 7.20463 MHz (138.79ns); CPU is 1/8 at 0.900 MHz
    uint64_t vdp_target = clockticks6502 * 8; // exactly 8px per CPU cycle
    while (vdp_clk < vdp_target) {
        // Horizontal timer counts 320/8=40 characters, at a rate of 8px per CPU cycle.
        uint16_t vdp_hsub = vdp_hcount & 7; // 0-7 (low 3 bits of hcount)

        // output a pixel (delay: 1px)
        if (vdp_hborder == 0 && vdp_vborder == 0 ) { // 
            if (FBrow < fb_height && FBcol < fb_width) { // safety check
                // clock in the pixel from the palette MUX output on this clock edge
                int pixel = (vdp_shift>>7) ? 1 : 0;
                // drive the resistor DAC from the pixel latch
                uint32_t dac_color = hw_pal[pixel]; // HW palette
                int coord = ((fb_vbord+FBrow) * fb_width) + FBcol; // FBSpan+FBcol
                FB[coord] = 0xFF000000 | dac_color;
            }
        }
        FBcol++; // position on the display

        // shift/load the shift register every CLK (delay: 0px)
        if (vdp_hsub == 0) {
            // load the latched character (via CharROM) into the shift register
            int address = (vdp_latch << 3) + (vdp_vcount & 7);
            vdp_shift = CharROM[address];
        } else {
            vdp_shift = vdp_shift << 1; // wired up backwards so top bit shifts out first
        }

        // load a character every bus cycle when fetch is enabled (0px)
        if (vdp_hsub == 4) { // vdp_hfetch == 1
            // HAddress: low 5 bits (0-31); VAddress: 5 bits above that (0-23)
            // Base: VidPgC (this will access up to 1KB, only 768 displayed)
            vdp_latch = MemMap[vdp_address >> 13][vdp_address & 0x1fff]; // 8K Banks
            vdp_address++;
        }

        // Clock in the new HCount, VCount, and decodes.
        // NTSC Horz: 4 + 128 + 28 + 8 + 16 + 2+10+4 + 28 = 228 (color clocks)
        // NTSC Horz: 1 + 32 + 7 + 2 + 4 + 4 + 7 = 57 (text cells)
        // [0][1][2][3][4][5][6][7][8][-]
        // [/][0][1][2][3][4][5][6][7][8]
        // how does +2 cause the 1st pixel to appear at the right side?
        if (vdp_hcount == 4) {   // MUST enable before first vdp_hcount%8==0
            vdp_hc1en = 1;       // start iterpreting color control codes (vdp_hcount=8)
        }
        if (vdp_hcount == fb_hdelay) {
            vdp_hborder = 0;     // turn off border (at 8+1=9)
        }
        if (vdp_hcount == fb_hdelay+fb_viswidth) {
            vdp_hborder = 1;     // turn on border (after 33 characters) (at 8+256+1 = 265)
            vdp_hc1en = 0;       // stop processing color codes (allow CPU to set palette)
        }
        if (vdp_hcount == fb_hdelay+fb_viswidth+fb_hrightbord) {
            vdp_hblank = 1;      // turn on HBLANK (at 8+256+64+1 = 329)
        }
        if (vdp_hcount == fb_hdelay+fb_viswidth+fb_hrightbord+fb_syncwidth) {
            vdp_hblank = 0;      // turn off HBLANK (at 8+256+64+80+1 = 409)
            // start of visible scanline
            FBrow++;             // next output row
            FBcol = 0;           // reset output column
        }
        if (vdp_hcount == fb_hdelay+fb_viswidth+fb_hrightbord+fb_syncwidth+fb_hleftbord-1) {
            // NTSC: 227.5 color-burst cycles per line at 3.57954 MHz
            // NTSC: 455 pixels per line at 7.15909 MHz
            // CPU: 455/7 = 65 cycles at 1.02272 MHz exactly
            vdp_hcount = 0;      // end of line (at 8+256+64+80+48-1+1 = 456)

            // advance text row every 8 lines
            if ((vdp_vcount & 7) == 7) {
                vdp_base += 40;
            }

            // NTSC Vert: 192 + 25 + 9 + 3 + 8 + 25 = 262
            vdp_vcount++;

            // vertical decodes
            if (vdp_vcount == 192) {
                vdp_vborder = 1; // turn on vertical border
            }
            if (vdp_vcount == 192+25) {
                vdp_vblank = 1;   // start of vblank
                // request_irq();
            }
            if (vdp_vcount == 192+25+9+3+8) {
                vdp_vblank = 0;   // end of vblank
            }
            if (vdp_vcount == 192+25+9+3+8+25) {
                vdp_vcount = 0;    // end of field (262 lines)
                vdp_vborder = 0;   // turn off vertical border
                FBrow = 0;         // reset output row
                vdp_base = 0xA000; // reset to top of screen
                render();
            }

            // reset VDP address to vdp_base at the start of each line.
            vdp_address = vdp_base;

            // calculate output row address
            // int coord = (fb_vbord+FBrow) * fb_width;
            // FBspan = &FB[coord];
        } else {
            // latch the new HCount
            vdp_hcount++;
        }
        vdp_clk++;
    }
}
