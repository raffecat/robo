// Robo Emulator - Renderer

#include <SDL2/SDL.h>
#include <string.h>
#include "header.h"

// NTSC Vert: 192 + 25 + 9 + 3 + 8 + 25 = 262
// NTSC Horz: 128 + 31 + 6 + 16 + 2 + 10 + 4 + 31 = 228
// NTSC Final: 9 + 256 + 67 + 11 + 32 + 4 + 20 + 8 + 56 = 456 (x2)
enum vtiming {
    fb_syncwidth = 12 + 32 + 4 + 20 + 8,
    fb_hdelay = 8+1,    // 1 character (prefetch) + 1 pixel (output delays)
    fb_viswidth = 256,
    fb_visheight = 192,
    fb_hleftbord = 56-fb_hdelay,  // left border in FB
    fb_hrightbord = 67, // right border in FB
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
static SDL_Texture* texture = 0;
static uint64_t vdp_clk = 0;
static int vdp_nextbus = 0;

// vdp timing
uint16_t vdp_hcount = 0; // 8-bit horizontal count
uint16_t vdp_vcount = 0; // 9-bit vertical line count (visible to ula.c)
uint8_t vdp_hborder = 1;  // 1-bit latch (visible to ula.c)
uint8_t vdp_hblank = 0;  // 1-bit latch
uint8_t vdp_vborder = 0;  // 1-bit latch
uint8_t vdp_vblank = 0;  // 1-bit latch (visible to ula.c)

// pixel pipeline
static uint8_t vdp_latch = 0x12; // 8-bit character latch
static uint8_t vdp_shift = 0xF3; // 8-bit pixel shift register

// colors.py
static uint32_t hw_pal[16] = { // RGB
0x0,
0x3800ff,
0xff00b0,
0xff9632,
0xffff20,
0x47ff8b,
0xe0ff,
0x6900ff,
0x7f7f7f,
0x64249f,
0x9c2582,
0xb97b62,
0xa0d55e,
0x67de79,
0xbae9,
0xffffff,
};

// framebuffer
// SDL_PIXELFORMAT_ARGB8888 uses 32-bit integers; byte-order depends on the platform's endianness.
// MSB -> { alpha, red, green, blue } <- LSB
static uint32_t FB[fb_width*fb_height]; // 300K!
//static uint32_t* FBspan = &FB[0];
static uint16_t FBcol = 455 - (fb_viswidth+fb_hdelay+fb_hrightbord+fb_syncwidth);
static uint16_t FBrow = 0;

int init_render() {
    // check horizontal timing
    int htime = fb_viswidth+fb_hdelay+fb_hrightbord+fb_syncwidth+fb_hleftbord;
    if (htime != 455) {
        printf("wrong horizontal timing: %d\n", htime);
        return 0;
    }
    SDL_Init(SDL_INIT_VIDEO|SDL_INIT_EVENTS);
    window = SDL_CreateWindow(
        "ECS-604",
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
    // fill DRAM with random bytes
    srand(time(NULL));
    for (int i=0; i<8192; i++) {
        MainRAM[i] = rand();
        CartRAM[i] = rand();
    }
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
        // first WINDOW row
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
    SDL_RenderPresent(renderer);
}

// advance the renderer to catch up with the CPU clock (clockticks6502)
// the current vdp_clk has already been processed
void advance_vdp() {
    // NTSC: 14.31818 Mhz: CPU is 1/14 at 1.022727; VDP shift clk is 1/2 at 7.15909 MHz (139.68ns)
    // PAL 17.734475 MHz: CPU is 1/18 at 0.985248; VDP shift clk is 1/2 at 8.8672375 MHz (112.77ns)
    uint64_t vdp_target = clockticks6502 * 7; // exactly 7 px per CPU cycle
    while (vdp_clk < vdp_target) {
        // Horizontal timer counts 256/8=32 characters, at a rate of 7px per CPU cycle.
        // XXX this means the CPU address cannot be derived from the HCounter.
        // No it can, we just get 4 duplicate reads during a line (use these for refresh)

        if (--vdp_nextbus < 1) {
            // VRAM memory access on each BUS cycle (1.022727 MHz) (every 14/2=7 pixels)
            vdp_nextbus = 7;
            // FIXME: we double up some columns: we're getting ahead at a rate
            // of 1px per char; when we overtake, we load a char early but
            // using the current VDP (HCounter) address...
            // HAddress: low 5 bits (0-31); VAddress: 5 bits above that (0-23)
            uint16_t addr = 0x000 + ((((vdp_vcount>>3)&31)<<5)|((vdp_hcount>>3)&31)); // [0,1024)
            vdp_latch = MainRAM[addr]; // Char
        }
        uint16_t vdp_hsub = vdp_hcount & 7; // 0-7 (low 3 bits of hcount)
        // load next character every bus cycle
        // if (vdp_hsub == 4) {
            // HAddress: low 5 bits (0-31); VAddress: 5 bits above that (0-23)
            // Base: $0200 (this will access up to 1KB, only 768 displayed)
            // uint16_t addr = 0x000 + ((((vdp_vcount>>3)&31)<<5)|((vdp_hcount>>3)&31)); // [0,1024)
            // vdp_latch = MainRAM[addr]; // Char
        // }
        // load the shift register every 8th CLK
        uint8_t prev_shift_out = (vdp_shift>>7); // pixel latch has 1px delay
        uint8_t prev_vidpal = VidPal;
        if (vdp_hsub == 0) {
            // load the latched character (via CharROM) into the shift register
            // on the first pixel of the next tile
            int address = (vdp_latch << 3) + (vdp_vcount & 7);
            vdp_shift = CharROM[address];
            // Load the palette latch from $8x/$9x (C1) color codes.
            if ((vdp_latch & 0xF0) == 0x80) VidPal = (VidPal & 0xF0) | (vdp_latch & 0x0F); // FG
            if ((vdp_latch & 0xF0) == 0x90) VidPal = (VidPal & 0x0F) | ((vdp_latch & 0x0F) << 4); // BG
        }
        // shift the register every CLK (suppressed when loading)
        if (vdp_hsub != 0) {
            vdp_shift = vdp_shift << 1; // wired up backwards so top bit shifts out first
        }
        if (vdp_vborder == 0 && vdp_hborder == 0) { // vdp_hborder == 0
            // display area
            // latch the pixel on the next CLK (prev_shift_out)
            int vdp_pixel = prev_shift_out ? (prev_vidpal & 15) : (prev_vidpal >> 4); // palette select MUX
            uint32_t output = 0xFF000000 | hw_pal[vdp_pixel]; // HW palette (phase select MUX)
            if (FBrow < fb_height && FBcol < fb_width) { // safety check
                int coord = ((fb_vbord+FBrow) * fb_width) + FBcol; // FBSpan+FBcol
                FB[coord] = output;
            }
        }

        // Clock in the new HCount, VCount, and decodes.
        vdp_clk++;
        vdp_hcount++;
        FBcol++;
        // NTSC Horz: 128 + 31 + 6 + 16 + 2 + 10 + 4 + 31 = 228 (x2 for pixels)
        // [0][1][2][3][4][5][6][7][8][-]
        // [/][0][1][2][3][4][5][6][7][8]
        if (vdp_hcount == fb_hdelay) {
            vdp_hborder = 0;     // turn off border (after 1 character + 1 pixel)
        }
        if (vdp_hcount == fb_viswidth+fb_hdelay) {
            vdp_hborder = 1;     // turn on border (after 33 characters + 1 pixel)
        }
        if (vdp_hcount == fb_viswidth+fb_hdelay+fb_hrightbord) {
            vdp_hblank = 1;      // turn on HBLANK
        }
        if (vdp_hcount == fb_viswidth+fb_hdelay+fb_hrightbord+fb_syncwidth) {
            vdp_hblank = 0;      // turn off HBLANK
            FBcol = 0;           // reset output column
        }
        if (vdp_hcount == fb_viswidth+fb_hdelay+fb_hrightbord+fb_syncwidth+fb_hleftbord) { // NTSC 455/7 = 65
            // NTSC: 227.5 color-burst cycles per line at 3.57954 MHz
            // NTSC: 455 pixels per line at 7.15909 MHz
            // CPU: 455/7 = 65 cycles at 1.02272 MHz exactly
            vdp_hcount = 0;      // end of line
            FBrow++;             // next output row
            VidPal = 0x0F;       // reset VidPal latch for each line (Black BG, White FG)

            // NTSC Vert: 192 + 25 + 9 + 3 + 8 + 25 = 262
            vdp_vcount++;
            if (vdp_vcount == 192) {
                vdp_vborder = 1; // turn on vertical border
            }
            if (vdp_vcount == 192+25) {
                vdp_vblank = 1;   // start of vblank
                render();
                request_irq();
            }
            if (vdp_vcount == 192+25+9+3+8) {
                vdp_vblank = 0;   // end of vblank
            }
            if (vdp_vcount == 192+25+9+3+8+25) {
                vdp_vcount = 0;    // end of field (262 lines)
                vdp_vborder = 0;   // turn off vertical border
                FBrow = 0;         // reset output row
                //vdp_nextbus = 0;   // TESTING (bus rates other than 7)
            }

            // calculate output row address
            // int coord = (fb_vbord+FBrow) * fb_width;
            // FBspan = &FB[coord];
        }
    }
}
