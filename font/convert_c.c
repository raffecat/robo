#include <stdio.h>

#include "ECSv1.c"

int main() {
    uint32_t stride = 128; // canvas width
    uint32_t row_stride = stride * 8; // one row of chars
    const uint32_t* row = &ecsv1_data[0][0];
    int ch = 0;
    // 16 rows of characters (starting at 0)
    for (int y=0; y<16; y++) {
        // 16 characters across
        for (int x=0; x<16; x++) {
            // 8 lines per character
            const uint32_t* chara = &row[x*8];
            printf("    ");
            for (int cy=0; cy<8; cy++) {
                // 8 pixels per row
                int byte = 0;
                for (int cx=0; cx<8; cx++) {
                    const uint32_t px = chara[cx];
                    if (px >= 0x80000000) {
                        byte = (byte<<1) | 1;
                    } else {
                        byte = (byte<<1) | 0;
                    }
                }
                printf("0x%02x,",byte);
                chara += stride; // next line
            }
            printf("    // %d\n", ch);
            ch++;
        }
        row += row_stride;
    }
    return 0;
}
