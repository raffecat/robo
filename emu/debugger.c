// Robo Emulator - Debugger

#include <stdio.h>
#include <stdint.h>
#include <SDL2/SDL.h>
#include "header.h"

// future debugger: 
// keep a sorted array of entry points, in RAM order.
// limit distance between entry points to ~64 bytes for reverse search.
// disassemble code blocks from top to bottom of screen.
// when jumping to an address that isn't in the array, insert it.

static const char* dbg_mnemonictable[256] = {
/*        |  0  |  1  |  2  |  3  |  4  |  5  |  6  |  7  |  8  |  9  |  A  |  B  |  C  |  D  |  E  |  F  |      */
/* 0 */    "BRK","ORA","NOP","SLO","NOP","ORA","ASL","SLO","PHP","ORA","ASL","NOP","NOP","ORA","ASL","SLO", /* 0 */
/* 1 */    "BPL","ORA","NOP","SLO","NOP","ORA","ASL","SLO","CLC","ORA","NOP","SLO","NOP","ORA","ASL","SLO", /* 1 */
/* 2 */    "JSR","AND","NOP","RLA","BIT","AND","ROL","RLA","PLP","AND","ROL","NOP","BIT","AND","ROL","RLA", /* 2 */
/* 3 */    "BMI","AND","NOP","RLA","NOP","AND","ROL","RLA","SEC","AND","NOP","RLA","NOP","AND","ROL","RLA", /* 3 */
/* 4 */    "RTI","EOR","NOP","SRE","NOP","EOR","LSR","SRE","PHA","EOR","LSR","NOP","JMP","EOR","LSR","SRE", /* 4 */
/* 5 */    "BVC","EOR","NOP","SRE","NOP","EOR","LSR","SRE","CLI","EOR","NOP","SRE","NOP","EOR","LSR","SRE", /* 5 */
/* 6 */    "RTS","ADC","NOP","RRA","NOP","ADC","ROR","RRA","PLA","ADC","ROR","NOP","JMP","ADC","ROR","RRA", /* 6 */
/* 7 */    "BVS","ADC","NOP","RRA","NOP","ADC","ROR","RRA","SEI","ADC","NOP","RRA","NOP","ADC","ROR","RRA", /* 7 */
/* 8 */    "NOP","STA","NOP","SAX","STY","STA","STX","SAX","DEY","NOP","TXA","NOP","STY","STA","STX","SAX", /* 8 */
/* 9 */    "BCC","STA","NOP","NOP","STY","STA","STX","SAX","TYA","STA","TXS","NOP","NOP","STA","NOP","NOP", /* 9 */
/* A */    "LDY","LDA","LDX","LAX","LDY","LDA","LDX","LAX","TAY","LDA","TAX","NOP","LDY","LDA","LDX","LAX", /* A */
/* B */    "BCS","LDA","NOP","LAX","LDY","LDA","LDX","LAX","CLV","LDA","TSX","LAX","LDY","LDA","LDX","LAX", /* B */
/* C */    "CPY","CMP","NOP","DCP","CPY","CMP","DEC","DCP","INY","CMP","DEX","NOP","CPY","CMP","DEC","DCP", /* C */
/* D */    "BNE","CMP","NOP","DCP","NOP","CMP","DEC","DCP","CLD","CMP","NOP","DCP","NOP","CMP","DEC","DCP", /* D */
/* E */    "CPX","SBC","NOP","ISB","CPX","SBC","INC","ISB","INX","SBC","NOP","SBC","CPX","SBC","INC","ISB", /* E */
/* F */    "BEQ","SBC","NOP","ISB","NOP","SBC","INC","ISB","SED","SBC","NOP","ISB","NOP","SBC","INC","ISB"  /* F */
};

typedef enum dbg_eam {
    ea_imp,
    ea_acc,
    ea_imm,
    ea_rel,
    ea_zp,
    ea_zpx,
    ea_zpy,
    ea_abs,
    ea_absx,
    ea_absy,
    ea_ind,
    ea_indx,
    ea_indy,
} dbg_eam;

static const dbg_eam dbg_addrmode[256] = {
/*          |  0  |   1    |    2   |    3   |     4  |     5  |     6  |     7  |     8  |     9  |     A  |     B  |     C  |     D  |     E  |    F   |     */
/* 0 */     ea_imp, ea_indx,  ea_imp, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_acc,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* 0 */
/* 1 */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpx,  ea_zpx,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absx, ea_absx, /* 1 */
/* 2 */     ea_abs, ea_indx,  ea_imp, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_acc,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* 2 */
/* 3 */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpx,  ea_zpx,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absx, ea_absx, /* 3 */
/* 4 */     ea_imp, ea_indx,  ea_imp, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_acc,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* 4 */
/* 5 */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpx,  ea_zpx,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absx, ea_absx, /* 5 */
/* 6 */     ea_imp, ea_indx,  ea_imp, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_acc,  ea_imm, ea_ind,  ea_abs,  ea_abs,  ea_abs, /* 6 */
/* 7 */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpx,  ea_zpx,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absx, ea_absx, /* 7 */
/* 8 */     ea_imm, ea_indx,  ea_imm, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_imp,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* 8 */
/* 9 */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpy,  ea_zpy,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absy, ea_absy, /* 9 */
/* A */     ea_imm, ea_indx,  ea_imm, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_imp,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* A */
/* B */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpy,  ea_zpy,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absy, ea_absy, /* B */
/* C */     ea_imm, ea_indx,  ea_imm, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_imp,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* C */
/* D */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpx,  ea_zpx,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absx, ea_absx, /* D */
/* E */     ea_imm, ea_indx,  ea_imm, ea_indx,   ea_zp,   ea_zp,   ea_zp,   ea_zp,  ea_imp,  ea_imm,  ea_imp,  ea_imm, ea_abs,  ea_abs,  ea_abs,  ea_abs, /* E */
/* F */     ea_rel, ea_indy,  ea_imp, ea_indy,  ea_zpx,  ea_zpx,  ea_zpx,  ea_zpx,  ea_imp, ea_absy,  ea_imp, ea_absy, ea_absx, ea_absx, ea_absx, ea_absx  /* F */
};

#define FLAG_CARRY     0x01
#define FLAG_ZERO      0x02
#define FLAG_INTERRUPT 0x04
#define FLAG_DECIMAL   0x08
#define FLAG_OVERFLOW  0x40
#define FLAG_SIGN      0x80

void dbg_decode_next_op(uint16_t pc) {
    char regs[32]; // PIC "A=xx X=xx Y=xx [CVNZID]" // 24
    // register state
    sprintf(regs, "A=%02X X=%02X Y=%02X [%c%c%c%c%c%c]", a, x, y, 
        (status&FLAG_CARRY)?'C':'-', (status&FLAG_OVERFLOW)?'V':'-',
        (status&FLAG_SIGN)?'N':'-', (status&FLAG_ZERO)?'Z':'-',
        (status&FLAG_INTERRUPT)?'I':'-', (status&FLAG_DECIMAL)?'D':'-');
    // decode instruction
    uint8_t op = read6502(pc);
    const char* mne = dbg_mnemonictable[op];
    const dbg_eam mode = dbg_addrmode[op];
    switch (mode) {
        case ea_imp: {
            printf("%04X %s                \t\t%s\n", pc, mne, regs);
            break;
        }
        case ea_acc: {
            printf("%04X %s A              \t\t%s\n", pc, mne, regs);
            break;
        }
        case ea_imm: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s #$%02X            \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        case ea_rel: {
            int8_t val = read6502(pc+1); // NB signed int8
            uint16_t to = pc+2+val;
            printf("%04X %s %+d -> $%04X    \t\t%s\n", pc, mne, val, (int)(to), regs);
            break;
        }
        case ea_zp: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s $%02X            \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        case ea_zpx: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s $%02X,X          \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        case ea_zpy: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s $%02X,Y          \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        case ea_abs: {
            uint8_t lo = read6502(pc+1);
            uint8_t hi = read6502(pc+2);
            uint16_t to = (hi<<8)|lo;
            printf("%04X %s $%04X          \t\t%s\n", pc, mne, (int)(to), regs);
            break;
        }
        case ea_absx: {
            uint8_t lo = read6502(pc+1);
            uint8_t hi = read6502(pc+2);
            uint16_t to = (hi<<8)|lo;
            printf("%04X %s $%04X,X        \t\t%s\n", pc, mne, (int)(to), regs);
            break;
        }
        case ea_absy: {
            uint8_t lo = read6502(pc+1);
            uint8_t hi = read6502(pc+2);
            uint16_t to = (hi<<8)|lo;
            printf("%04X %s $%04X,Y        \t\t%s\n", pc, mne, (int)(to), regs);
            break;
        }
        case ea_ind: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s ($%02X)          \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        case ea_indx: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s (%02X,X)         \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        case ea_indy: {
            uint8_t val = read6502(pc+1);
            printf("%04X %s ($%02X),Y        \t\t%s\n", pc, mne, (int)(val), regs);
            break;
        }
        default:
            printf("bad addr mode %d", mode);
    }
}
