// Robo Emulator - Debugger

#include <SDL2/SDL.h>
#include "header.h"

// debugger: 
// keep a sorted array of entry points, in RAM order.
// limit distance between entry points to ~64 bytes for reverse search.
// disassemble code blocks from top to bottom of screen.
// when jumping to an address that isn't in the array, insert it.

