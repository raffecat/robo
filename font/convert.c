#include <stdio.h>

#include "ASCIIv4.c"

int main() {
    uint32_t stride = 128; // canvas width
    uint32_t row_stride = stride * 8; // one row of chars
    const uint32_t* row = &asciiv4_data[0][0];
    int ch = 0;
    // 16 rows of characters (starting at 0)
    for (int y=0; y<16; y++) {
        // 16 characters across
        for (int x=0; x<16; x++) {
            // 8 lines per character
            const uint32_t* chara = &row[x*8];
            printf("DB ");
            for (int cy=0; cy<8; cy++) {
                // 8 pixels per line
                int byte = 0;
                for (int cx=0; cx<8; cx++) {
                    const uint32_t px = chara[cx];
                    if (px >= 0x80000000) {
                        byte |= 128 >> cx; // white pixel
                    }
                }
                // re-pack [LLLLRRRR] pixels
                //    into [RLRLRLRL] format
                byte = ((byte&128)>>1) | ((byte&64)>>2) | ((byte&32)>>3) | ((byte&16)>>4)
                     | ((byte&8)<<4) | ((byte&4)<<3) | ((byte&2)<<2) | ((byte&1)<<1);
                printf(cy==7?"%d":"%d,",byte);
                chara += stride; // next line
            }
            printf("  ; %d\n", ch);
            ch++;
        }
        row += row_stride;
    }
    return 0;
}
