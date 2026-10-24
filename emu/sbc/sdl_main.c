// Robo Emulator - SDL Main

#include <SDL2/SDL.h>
#include "header.h"
#include "io.c"

#include <unistd.h>  // for getcwd()
#include <limits.h>  // for PATH_MAX

const Uint8 *keys = 0;
static Uint8 dbg_mode = 1;

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

     char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd))) { cwd[0] = 'X'; cwd[1] = 0; }
    printf("dir %s\n", cwd);

    // load the ROM image.
    memset(SysROM, 0xEE, sizeof(SysROM));
    size_t mon_size = read_binary_file("mon.bin", (char*)(SysROM), 512);
    printf("loaded monitor %zu\n", mon_size);
    for (size_t to = 512; to <= sizeof(SysROM)-512; to += 512) {
        memcpy((char*)(SysROM)+to, (char*)(SysROM), 512);
    }
    size_t bas_size = read_binary_file("rom2K.bin", (char*)(MainRAM)+512, 2048);
    printf("loaded BASIC %zu\n", bas_size);

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
    //pc = 0xE000; // Monitor ROM

    // DEBUGGER
    dbg_enable = 0;
    dbg_break = 0x0F0E4;
    Uint32 held_time = 0;

    // run the simulator.
    SDL_Event event;
    int running = 1;
    while (running) {
        // process events.
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = 0;
            }
            if (event.type == SDL_KEYDOWN && !event.key.repeat) {
                SDL_Keycode sym = event.key.keysym.sym;
                uint16_t mod = event.key.keysym.mod;

                if (sym >= SDLK_a && sym <= SDLK_z) sym &= 0xDF; // map to uppper-case.
                if (mod & KMOD_CTRL) {
                    if (sym >= 0x40 && sym <= 0x5F) {
                        sym &= 0x1F; // clear bits 5 and 6.
                    }
                }

                if (sym >= 0 && sym <= 127) {
                    ula_key_strobe((uint8_t)sym);
                }
            }
        }    

        // run the CPU.
        if (!dbg_enable) {
            exec6502(cpu_clk_per_line);
            // clockticks6502++;
            // advance_vdp();
        } else {
            // debugger
            if (pc != dbg_break) {
                // run until we hit the breakpoint.
                exec6502(cpu_clk_per_line);
            } else {
                // stopped on the breakpoint.
                if (keys[SDL_SCANCODE_RSHIFT]) {
                    if (dbg_mode == 1) { // waiting
                        dbg_mode = 2; // single step held down
                        held_time = SDL_GetTicks() + 300;
                        uint16_t old_pc = pc;
                        step6502();
                        dbg_decode_next_op(old_pc);
                        dbg_break = pc; // advance the breakpoint
                    } else if (SDL_GetTicks() > held_time) {
                        // auto-repeat
                        held_time = SDL_GetTicks() + 80;
                        uint16_t old_pc = pc;
                        step6502();
                        dbg_decode_next_op(old_pc);
                        dbg_break = pc; // advance the breakpoint
                    }
                } else if (keys[SDL_SCANCODE_RALT]) {
                    dbg_break = 0; // continue
                } else {
                    dbg_mode = 1; // back to waiting
                }
                advance_vdp();
                render();
            }
        }

        // make render progress.
        advance_vdp();
    }

    final_render();
    return 0;
}
