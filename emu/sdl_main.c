// Robo Emulator - SDL Main

#include <SDL2/SDL.h>
#include "header.h"
#include "io.c"

#include <unistd.h>  // for getcwd()
#include <limits.h>  // for PATH_MAX

const uint32_t one_frame = 34298; // 34,298.188 CPU cycles per field
const uint32_t one_scanline = 568*2/9; // PAL 568 pixels at 1/2 of 17.734475, CPU at 1/9 of 17.734475 (=126.222)
// ^ should accumulate pixel clocks, derive whole cycles, permit negative count

const Uint8 *keys = 0;

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

     char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd))) { cwd[0] = 'X'; cwd[1] = 0; }
    printf("dir %s\n", cwd);

    // load the ROM image.
    memset(SysROM, 0xFF, sizeof(SysROM));
    size_t rom_size = read_binary_file("rom.bin", (char*)SysROM, sizeof(SysROM));
    printf("loaded ROM %zu\n", rom_size);

    // create window.
    if (!init_render()) {
        printf("cannot create SDL window\n");
        return 1;
    }

    // get the keys array - valid for app lifetime.
    // value of 1 means the key is pressed, value of 0 means that it is not.
    keys = SDL_GetKeyboardState(NULL);

    // start the CPU.
    reset6502();

    // run the simulator.
    SDL_Event event;
    int running = 1;
    while (running) {
        // process events.
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = 0;
            }
        }    

        // run the CPU.
        exec6502(one_scanline);

        // make render progress.
        advance_vdp();
    }

    final_render();

    return 0;
}

uint8_t scanKeyCol(uint8_t col) {
    //   Esc ` 1 2 3 4 5 6  7 8 9 0 - = DEL UP    (16)
    //   Tab Q W E R T Y U  I O P [ ] \     DOWN  (15)
    //  Caps A S D F G H J  K L ; '     RET LEFT  (14)
    // Ctl LSh Z X C V B N  M , . / RSh SPC RIGHT (15)
    switch (col) {
        case 0:
            return (keys[SDL_SCANCODE_ESCAPE]<<7) |
                   (keys[SDL_SCANCODE_GRAVE]<<6) |
                   (keys[SDL_SCANCODE_1]<<5) |
                   (keys[SDL_SCANCODE_2]<<4) |
                   (keys[SDL_SCANCODE_3]<<3) |
                   (keys[SDL_SCANCODE_4]<<2) |
                   (keys[SDL_SCANCODE_5]<<1) |
                   (keys[SDL_SCANCODE_6]<<0);
        case 1:
            return (keys[SDL_SCANCODE_TAB]<<7) |
                   (keys[SDL_SCANCODE_Q]<<6) |
                   (keys[SDL_SCANCODE_W]<<5) |
                   (keys[SDL_SCANCODE_E]<<4) |
                   (keys[SDL_SCANCODE_R]<<3) |
                   (keys[SDL_SCANCODE_T]<<2) |
                   (keys[SDL_SCANCODE_Y]<<1) |
                   (keys[SDL_SCANCODE_U]<<0);
        case 2:
            return (keys[SDL_SCANCODE_CAPSLOCK]<<7) |
                   (keys[SDL_SCANCODE_A]<<6) |
                   (keys[SDL_SCANCODE_S]<<5) |
                   (keys[SDL_SCANCODE_D]<<4) |
                   (keys[SDL_SCANCODE_F]<<3) |
                   (keys[SDL_SCANCODE_G]<<2) |
                   (keys[SDL_SCANCODE_H]<<1) |
                   (keys[SDL_SCANCODE_J]<<0);
        case 3:
            return (keys[SDL_SCANCODE_LCTRL]<<7) |
                   (keys[SDL_SCANCODE_LSHIFT]<<6) |
                   (keys[SDL_SCANCODE_Z]<<5) |
                   (keys[SDL_SCANCODE_X]<<4) |
                   (keys[SDL_SCANCODE_C]<<3) |
                   (keys[SDL_SCANCODE_V]<<2) |
                   (keys[SDL_SCANCODE_B]<<1) |
                   (keys[SDL_SCANCODE_N]<<0);

        case 4:
            return (keys[SDL_SCANCODE_7]<<7) |
                   (keys[SDL_SCANCODE_8]<<6) |
                   (keys[SDL_SCANCODE_9]<<5) |
                   (keys[SDL_SCANCODE_0]<<4) |
                   (keys[SDL_SCANCODE_MINUS]<<3) |
                   (keys[SDL_SCANCODE_EQUALS]<<2) |
                   (keys[SDL_SCANCODE_BACKSPACE]<<1) |
                   (keys[SDL_SCANCODE_UP]<<0);
        case 5:
            return (keys[SDL_SCANCODE_I]<<7) |
                   (keys[SDL_SCANCODE_O]<<6) |
                   (keys[SDL_SCANCODE_P]<<5) |
                   (keys[SDL_SCANCODE_LEFTBRACKET]<<4) |
                   (keys[SDL_SCANCODE_RIGHTBRACKET]<<3) |
                   (keys[SDL_SCANCODE_BACKSLASH]<<2) |
                   (0<<1) |
                   (keys[SDL_SCANCODE_DOWN]<<0);
        case 6:
            return (keys[SDL_SCANCODE_K]<<7) |
                   (keys[SDL_SCANCODE_L]<<6) |
                   (keys[SDL_SCANCODE_SEMICOLON]<<5) |
                   (keys[SDL_SCANCODE_APOSTROPHE]<<4) |
                   (0<<3) |
                   (0<<2) |
                   (keys[SDL_SCANCODE_RETURN]<<1) |
                   (keys[SDL_SCANCODE_LEFT]<<0);
        case 7:
            return (keys[SDL_SCANCODE_M]<<7) |
                   (keys[SDL_SCANCODE_COMMA]<<6) |
                   (keys[SDL_SCANCODE_PERIOD]<<5) |
                   (keys[SDL_SCANCODE_SLASH]<<4) |
                   (keys[SDL_SCANCODE_RSHIFT]<<3) |
                   (0<<2) |
                   (keys[SDL_SCANCODE_SPACE]<<1) |
                   (keys[SDL_SCANCODE_RIGHT]<<0);
    }
    return 0;
}
