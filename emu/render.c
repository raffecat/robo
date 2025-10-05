// Robo Emulator - Renderer

#include <SDL2/SDL.h>
#include <string.h>
#include "header.h"

const uint8_t VCTL_APA       = 0x80;   // direct VRAM addressing, fixed at address 0
const uint8_t VCTL_NARROW    = 0x40;   // render the left 5 pixels of each tile (64 columns)
const uint8_t VCTL_16COL     = 0x20;   // attributes contain [BBBBFFFF] BG,FG colors (2+2x16 colours)
const uint8_t VCTL_GREY      = 0x10;   // disable Colorburst for improved text legibility
const uint8_t VCTL_V240      = 0x0C;   // 240 visible lines per frame
const uint8_t VCTL_V224      = 0x08;   // 224 visible lines per frame
const uint8_t VCTL_V200      = 0x04;   // 200 visible lines per frame
const uint8_t VCTL_V192      = 0x00;   // 192 visible lines per frame
const uint8_t VCTL_H320      = 0x02;   // 320 visible pixel-clocks per line (shift rate)
const uint8_t VCTL_H256      = 0x00;   // 256 visible pixel-clocks per line (shift rate)
const uint8_t VCTL_4BPP      = 0x01;   // divide by 4, use 4 bits per pixel
const uint8_t VCTL_2BPP      = 0x00;   // divide by 2, use 2 bits per pixel

const int fb_hbord = 32; // border width in FB
const int fb_vbord = 32; // border height in FB
const int fb_width = 320+(fb_hbord*2);
const int fb_height = 224+(fb_vbord*2);
const int width = fb_width*2;  // MUST be twice as wide
const int height = fb_height*2; // MUST be twice as high

static SDL_Window* window = 0;
static SDL_Renderer* renderer = 0;
static SDL_Texture* texture = 0;
static uint64_t vdp_clk = 0;

// background layer
static uint8_t bg_ld_tl = 0; // 8-bit tile latch
static uint8_t bg_ld_al = 0; // 8-bit attribute latch
static uint8_t bg_ld_low  = 0xCC; // 8-bit pending load
static uint8_t bg_ld_high = 0xCC; // 8-bit pending high
static uint32_t bg_shift  = 0; // 24-bit shift register
static uint8_t bg_pixel   = 0; // 4-bit pixel latch
static uint16_t vdp_hcount = 0; // 9-bit horizontal count
static uint8_t vdp_hsub = 0; // 3-bit horizontal sub-tile counter
static uint8_t vdp_htile = 0; // 8-bit horizontal tile counter (0-39)
static uint8_t vdp_hborder = 0;  // 1-bit latch
static uint8_t vdp_hblank = 0;  // 1-bit latch
static uint8_t vdp_hearly = 0;  // 1-bit latch
uint16_t vdp_vcount = 0; // 9-bit vertical line count (visible to ula.c)
static uint8_t vdp_vsub = 0; // 3-bit vertical sub-tile counter
static uint8_t vdp_vtile = 0; // 8-bit vertical tile counter (0-24)
static uint8_t vdp_vborder = 0;  // 1-bit latch
uint8_t vdp_vblank = 0;  // 1-bit latch (visible to ula.c)
static uint8_t vdp_vearly = 0;  // 1-bit latch

// [00000000][00000000][00000000] -- fetch tile         (load low)
// [00000000][00000000][00000000]
// [00000000][00000000][00000000] -- fetch attrib       (nop)
// [00000000][00000000][00000000]
// [00000000][00000000][00000000] -- fetch gfx low      (load high)
// [00000000][00000000][00000000]
// [00000000][00000000][00000000] -- fetch gfx high     (nop)
// [00000000][00000000][00000000]
// [LLLLLLLL][00000000][00000000] -- load low
// [HHLLLLLL][LL000000][00000000]
// [HHHHLLLL][LLLL0000][00000000] -- nop
// [HHHHHHLL][LLLLLL00][00000000]
// [HHHHHHHH][LLLLLLLL][00000000] -- load high
// [00HHHHHH][HHLLLLLL][LL000000]
// [0000HHHH][HHHHLLLL][LLLL0000] -- nop
// [000000HH][HHHHHHLL][LLLLLL00]
// [NNNNNNNN][HHHHHHHH][LLLLLLLL] -- 16 cycle lag
//           [------------------]
//                ^ VidFinH (0,2,4,6,8,10,12,14)

// framebuffer
// SDL_PIXELFORMAT_ARGB8888 uses 32-bit integers; byte-order depends on the platform's endianness.
// MSB -> { alpha, red, green, blue } <- LSB
static uint32_t FB[fb_width*fb_height]; // 300K!
// static uint8_t Spacer[320*16] = {0}; // XXXX memory check
static uint32_t* FBspan = &FB[0];
static uint16_t FBcol = 0;
static uint16_t FBrow = 0;

int init_render() {
    SDL_Init(SDL_INIT_VIDEO|SDL_INIT_EVENTS);
    window = SDL_CreateWindow(
        "Robo 48",
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
    // fill VRAM with random bytes
    for (int i=0; i<16384; i++) {
        VRAM[i] = i;
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
    // NTSC: 14.31818 Mhz: CPU is 1/7 at 2.045454; VDP shift clk is 1/2 at 7.15909 MHz (139.68ns)
    // PAL 17.734475 MHz: CPU is 1/9 at 1.970497; VDP shift clk is 1/2 at 8.8672375 MHz (112.77ns)
    uint64_t vdp_target = (clockticks6502 * 9) / 2;
    // VCTL (1-0) Divider (DD) is 0=512 (2bpp) 1=320 (2bpp) 2=160 (4bpp)
    uint16_t bpp = (VidCtl & VCTL_4BPP); // 0=2bpp 1=4bpp
    uint32_t bpp_shift = 24 - (2 << bpp); // shift down from bit 24 (22 or 20)
    uint32_t bpp_mask = (1 << (2 << bpp))-1; // (3 or 15)
    while (vdp_clk < vdp_target) {
        // start early, two tiles from the end of the previous line.
        if (vdp_vearly && vdp_hearly) {
            // rising edge:
            // load next background tile every 8 clk
            if (vdp_hsub == 0) {
                int Vshift = 6+(NameSize>>2); // 1 + 5-8 bits (32,64,128,256)
                uint16_t addr = (NameBase<<8)|(vdp_vtile<<Vshift)|(vdp_htile<<1)|0;
                bg_ld_tl = VRAM[addr];
            }
            if (vdp_hsub == 2) {
                int Vshift = 6+(NameSize>>2); // 1 + 5-8 bits (32,64,128,256)
                uint16_t addr = (NameBase<<8)|(vdp_vtile<<Vshift)|(vdp_htile<<1)|1;
                bg_ld_al = VRAM[addr];
                //printf("%04x text %02x %02x\n", addr-1, bg_ld_tl, bg_ld_al);
            }
            if (vdp_hsub == 4) {
                // XXX assumes tiles begin at $0000
                uint16_t addr = ((bg_ld_al&1) << 12) | (bg_ld_tl<<4) | (vdp_vsub << 1) | 0;
                bg_ld_low = VRAM[addr];
            }
            if (vdp_hsub == 6) {
                // XXX assumes tiles begin at $0000
                uint16_t addr = ((bg_ld_al&1) << 12) | (bg_ld_tl<<4) | (vdp_vsub << 1) | 1;
                bg_ld_high = VRAM[addr];
                //printf("%04x gfx  %02x %02x\n", addr-1, bg_ld_low, bg_ld_high);
            }
            // shift left (out <- [msb<-lsb][msb<-lsb][msb<-lsb] <- load)
            bg_shift = bg_shift << 2;
            // load high byte of shift register every 8 clk
            // must load a byte every 4 pixels and shift twice, or use two planes
            if (vdp_hsub == 0) {
                bg_shift |= bg_ld_low; // set high byte of 24-bit
            } else if (vdp_hsub == 4) {
                bg_shift |= bg_ld_high; // set high byte of 24-bit
            }
            // falling edge:
            // clock out a pixel every Nth clk (N=bpp)
            if ((vdp_hsub & bpp) == 0) {
                //bg_pixel = bg_shift & (bpp_mask << (VidFinH << 1));
                bg_pixel = (bg_shift >> bpp_shift) & bpp_mask; // take `bpp` top bits of 24-bit
            }
            if (vdp_vborder == 0 && vdp_hborder == 0) {
                // pixel output
                uint8_t px = PAL_RAM[bg_pixel]; // [IIRRGGBB]
                if (FBrow < fb_height && FBcol < fb_width) { // safety check
                    static uint8_t chroma[4] = {0x00,0x60,0xB0,0xF0}; // 0.....6....B...F
                    static uint8_t luma[4] = {0x05,0x09,0x0C,0x0F};   // .....5...9..C..F
                    uint32_t red = chroma[(px>>4)&3] | luma[px>>6]; // red
                    uint32_t green = chroma[(px>>2)&3] | luma[px>>6]; // green
                    uint32_t blue = chroma[(px>>0)&3] | luma[px>>6]; // blue
                    uint32_t output = 0xFF000000 | (red<<16) | (green<<8) | blue;
                    int coord = ((fb_vbord+FBrow) * fb_width) + fb_hbord + FBcol;
                    FB[coord] = output;
                    FBcol++;
                }
            }
        }
        vdp_clk++;
        // PAL timing: 320+72+104+72 = 568
        vdp_hsub++;
        if (vdp_hsub == 8) {
            vdp_hsub = 0;
            // update horizontal address and timing counter
            uint16_t Hmask = (1 << (5+(NameSize>>2))) - 1; // 5-8 bits (32,64,128,256)
            vdp_htile = (vdp_htile+1) & Hmask;
            vdp_hcount++;
            if (vdp_hcount == 40) {
                vdp_hborder = 1;     // turn on border
                vdp_hearly = 0;      // end of early period
            }
            if (vdp_hcount == 40+9) {
                vdp_hblank = 1;      // turn on HBLANK
            }
            if (vdp_hcount == 40+9+13) {
                vdp_hblank = 0;      // turn off HBLANK
            }
            if (vdp_hcount == 40+9+13+9 - 2) { // early line start
                vdp_hearly = 1;
                // update vertical sub-tile counter
                if (vdp_vsub == 7) {
                    // next tile-row vertically
                    vdp_vsub = 0;
                    // during visible area, increment vtile at the end of each line
                    if (vdp_vborder == 0) {
                        uint16_t Vmask = (1 << (5+(NameSize&3))) - 1; // 5-8 bits (32,64,128,256)
                        vdp_vtile = (vdp_vtile+1) & Vmask;
                    } else if (vdp_vcount == 311) {
                        // on the last line before the visible lines start,
                        // and at the point of early line start,
                        // reset vsub and vtile.
                        vdp_vearly = 1;
                        // uint16_t Vmask = (1 << (5+(NameSize&3))) - 1; // 5-8 bits (32,64,128,256)
                        vdp_vtile = 0; // VidScrV & Vmask; // reload vertical tile counter
                        vdp_vsub = 0; // VidFinV & 3;  // reload vertical sub-tile counter
                    }
                } else {
                    vdp_vsub++;
                }
                // reload horizontal tile counter
                uint16_t Hmask = (1 << (5+(NameSize>>2))) - 1; // 5-8 bits (32,64,128,256)
                vdp_htile = VidScrH & Hmask; // reload horizontal tile counter
                FBcol = 0; // reset framebuffer column
                bg_shift = 0x00FFFF; // XXX debugging
                bg_ld_low = bg_ld_high = 0xFF; // XXX leaking in on the left side
            }
            if (vdp_hcount == 40+9+13+9) { // 71*8=568
                // end of the scanline
                vdp_hcount = 0;      // reset hcount
                vdp_hborder = 0;     // turn off border
                if (vdp_vborder == 0 && FBrow < fb_height-1) { // necessary?
                    FBrow++;
                    int coord = (((fb_vbord+FBrow) * fb_width) + fb_hbord);
                    FBspan = &FB[coord];      // next framebuffer row
                    // printf("+++ row %d\n", FBrow);
                }
                // update line counter
                vdp_vcount++;
                if (vdp_vcount == 224) { // 28 lines * 8 = 224
                    vdp_vborder = 1;
                    vdp_vearly = 0;
                }
                if (vdp_vcount == 224+32) {
                    vdp_vblank = 1;
                }
                if (vdp_vcount == 224+32+24) {
                    vdp_vblank = 0;
                }
                if (vdp_vcount == 224+32+24+32) { // 312
                    // start of next frame
                    vdp_vcount = 0;      // reset vcount
                    vdp_vborder = 0;     // start display output
                    // printf("+++ flip %d\n", FBrow);
                    render();
                    int topleft = ((fb_vbord * fb_width) + fb_hbord);
                    FBspan = &FB[topleft];     // reset FB
                    FBcol = 0;
                    FBrow = 0;
                }
            }
        }
    }
}
