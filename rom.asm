; Robo BASIC 1.0

; BASIC runtime   2K
; Floating point  2K
; BASIC parser    2K
; Graphics        2K
; Editor          2K
; Char ROM        2K // 12K

ROM      = $C000  ; 16K = $4000  C000-F3FF
CHROM    = $F700  ;  2K = $800   F700-FEFF
CHROM_E  = $FF00  ;
BOOT     = $FF00  ; 250 bytes
VEC      = $FFFA  ;   6 bytes

VR_TEXT  = $3000  ; text area at 12K

ZEROPG   = $0000  ; zero page
STACK    = $0100  ; stack page
KeyBuf   = $0200  ; keyboard(32) + sound(4*16=64) + serial(64)
LineBuf  = $0300  ; line buffer, disk/tape buffer, expression stack
BSTACK   = $0400  ; basic stack (for,repeat,gosub)
LOMEM    = $0400  ; bottom of BASIC memory
HIMEM    = $8000  ; top of BASIC memory
FREEMEM  = HIMEM-LOMEM

Src      = $00    ; source pointer
SrcH     = $01    ; source pointer high
Ptr      = $02    ; second pointer        XX
PtrH     = $03    ; second pointer high   XX
Tmp      = $04    ; temp
Tmp2     = $05    ; temp                  XX
KeyHd    = $06    ; keyboard buffer head
KeyTl    = $07    ; keyboard buffer tial
LastKey  = $08    ; keyboard last key pressed, for auto-repeat

; BASIC vars

AccE     = $10    ; Accumulator exponent
Acc0     = $11    ; Accumulator low byte
Acc1     = $12    ; Accumulator byte 1
Acc2     = $13    ; Accumulator byte 2
Acc3     = $14    ; Accumulator high byte

; Text Mode vars

CurX     = $20    ; text cursor X                   XXX need these?
CurY     = $21    ; text cursor Y                   XXX need these?
WinL     = $22    ; text window left
WinT     = $23    ; text window top
; WinR     = $24    ; text window right (exclusive)   XXX can do without
; WinB     = $25    ; text window bottom (exclusive)  XXX can do without
WinW     = $26    ; text window width
WinH     = $27    ; text window height
CurP     = $28    ; text write address low  (saved DSTL)
CurH     = $29    ; text write address high (saved DSTH)
ScrX     = $2A    ; text scroll X position (modulo 64) of left edge
ScrY     = $2B    ; text scroll Y position (modulo 32) of top edge
WinRem   = $2C    ; remaining horizontal space in text window
MapST    = $2D    ; text mode map stride (64,128,256,512)
MapSZH   = $2E    ; 

YSave    = $30    ; saved Y in leaf code

; IO Registers

IO_SRCL     = $D0    ; DMA src low
IO_SRCH     = $D1    ; DMA src high
IO_DSTL     = $D2    ; DMA dest low
IO_DSTH     = $D3    ; DMA dest high
IO_DCTL     = $D4    ; DMA control         (7-6:direction 5:vertical 4:reverse 2-0:mode)
IO_DRUN     = $D5    ; DMA count           (writing starts DMA, 0=256)
IO_AROP     = $D6    ; APA raster op       (2:rop_en 1-0:rop[0=NOT 1=OR 2=AND 3=XOR])
IO_DDRW     = $D7    ; DMA data R/W        (read: reads from src++; write: writes to dest++)
IO_DJMP     = $D8    ; DMA jump indirect   (read-only: indirect jump low byte)
IO_FILL     = $D8    ; DMA fill byte       (write-only: set fill byte)
IO_DJMH     = $D9    ; DMA jump indirect   (read-only: indirect jump high byte)
IO_JTBL     = $D9    ; DMA jump table      (write-only: table-jump page register)
IO_BNK8     = $DA    ; Bank switch $8000   (low 4 bits)
IO_BNKC     = $DB    ; Bank switch $C000   (low 4 bits)
IO_HDML     = $DC    ; HDMA src low        (enabled in VCTL)
IO_HDMH     = $DD    ; HDMA src high
IO_KEYB     = $DE    ; Keyboard scan (write: set row; read: scan column)
IO_MULW     = $DF    ; Booth multiplier (write {AL,AH,BL,BH} read {RL,RH})

IO_TON0     = $E0    ; PSG Ch.0 tone
IO_PCH0     = $E1    ; PSG Ch.0 pitch
IO_VOL0     = $E2    ; PSG Ch.0 volume
IO_TON1     = $E3    ; PSG Ch.1 tone
IO_PCH1     = $E4    ; PSG Ch.1 pitch
IO_VOL1     = $E5    ; PSG Ch.1 volume
IO_TON2     = $E6    ; PSG Ch.2 tone
IO_PCH2     = $E7    ; PSG Ch.2 pitch
IO_VOL2     = $E8    ; PSG Ch.2 volume
IO_TON3     = $E9    ; PSG Ch.3 tone
IO_PCH3     = $EA    ; PSG Ch.3 pitch
IO_VOL3     = $EB    ; PSG Ch.3 volume
IO_GP0R     = $EC    ; Game port 0 read
IO_GP1R     = $ED    ; Game port 1 read
IO_GP2R     = $EE    ; Game port 2 read       (not fitted)
IO_GP3R     = $EF    ; Game port 3 read       (not fitted)

IO_YLIN     = $F0    ; current Y-line         (read: V-counter; write: wait for VBlank)
IO_YCMP     = $F1    ; compare Y-line         (read/write, $FF won't trigger)
IO_SCRH     = $F2    ; horizontal scroll      (tile offset from 0, wraps) [in map-space]
IO_SCRV     = $F3    ; vertical scroll        (row offset from 0, wraps)  [in map-space]
IO_FINH     = $F4    ; horizontal fine scroll (top 3 bits)                [in bit-space]
IO_FINV     = $F5    ; vertical fine scroll   (top 3 bits)                [in bit-space]
IO_VCTL     = $F6    ; video control          (7:APA 6:Grey 5:HCount 4:Double 3-2:VCount 1-0:Divider)
IO_VENA     = $F7    ; interrupt enable       (7:VSync 6:VCmp 5:HSync 4:Power_LED 3:Caps_LED 2:BG_En 1:Spr_En 0:HDMA_En)
IO_VSTA     = $F8    ; interrupt status       (7:VSync 6:VCmp 5:HSync)  (read:status / write:clear)
IO_VMAP     = $F9    ; name table size        (2:2 width 32,64,128,256; height 32,64,128,256)
IO_VTAB     = $FA    ; name table base        (high byte)
IO_VBNK     = $FB    ; tile bank R/W          (write: [aaaadddd] bank addr,data; read: [aaaa----] read data)
IO_PALA     = $FC    ; palette address        (direct palette-memory address, top bit enables auto-increment)
IO_PALD     = $FD    ; palette data R/W       (direct palette-memory data, increments address if enabled)
IO_SPRA     = $FE    ; sprite address         (direct sprite-memory address)
IO_SPRD     = $FF    ; sprite data R/W        (direct sprite-memory data, increments address)


; DCTL direction
DMA_M2M        = $00
DMA_M2V        = $40
DMA_V2M        = $80
DMA_V2V        = $C0   ; can be used for windowed scrolling
; DCTL flags
DMA_Vert       = $20   ; increments VRAM by current map width, from VMAP [column copy]
DMA_Rev        = $10   ; derements src and dest addresses [memmove]
; DCTL mode
DMA_Copy       = 0     ; copy bytes
DMA_Fill       = 1     ; using src low-byte
DMA_Masked     = 2     ; copy pixels, skip zero pixels; BPP from VCTL
DMA_APA        = 3     ; uses AROP; APA addressing: low 1-3 bits of address select pixel; BPP from VCTL
DMA_Palette    = 4     ; read src / write dest is palette memory, low-byte only; ignores direction
DMA_Sprite     = 5     ; read src / write dest is sprite memory, low-byte only; ignores direction
; ROP mode
ROP_None       = 0
ROP_Invert     = 4+0
ROP_Or         = 4+1
ROP_And        = 4+2
ROP_Xor        = 4+3
; VCTL flags [AGHUVVDD]
VCTL_APA       = $80   ; direct VRAM addressing, fixed at address 0
VCTL_NARROW    = $40   ; render the left 5 pixels of each tile (64 columns)
VCTL_16COL     = $20   ; attributes contain [BBBBFFFF] BG,FG colors (2+2x16 colours)
VCTL_GREY      = $10   ; disable Colorburst for improved text legibility
VCTL_V240      = $0C   ; 240 visible lines per frame
VCTL_V224      = $08   ; 224 visible lines per frame
VCTL_V200      = $04   ; 200 visible lines per frame
VCTL_V192      = $00   ; 192 visible lines per frame
VCTL_H320      = $02   ; 320 visible pixel-clocks per line (shift rate)
VCTL_H256      = $00   ; 256 visible pixel-clocks per line (shift rate)
VCTL_4BPP      = $01   ; divide by 4, use 4 bits per pixel
VCTL_2BPP      = $00   ; divide by 2, use 2 bits per pixel
; VENA flags
VENA_VSync     = $80
VENA_VCmp      = $40
VENA_HSync     = $20
VENA_Pwr_LED   = $10
VENA_Caps_LED  = $08
VENA_BG_En     = $04
VENA_Spr_En    = $02
VENA_HDMA_En   = $01


; DMA Acceleration

MACRO LDA_DMA
  LDA IO_DDRW        ; on real HW
ENDM
MACRO LDX_DMA
  LDX IO_DDRW        ; on real HW
ENDM
MACRO LDY_DMA
  LDY IO_DDRW        ; on real HW
ENDM
MACRO DISPATCH
   JMP (IO_DJMP)     ; on real HW
ENDM



; ------------------------------------------------------------------------------
; PAGE 0

ORG ROM

; ROM entry table     ; public entry points
  DB  10              ; version 1.0
  DB  11              ; length of table:
  DW  reset_soft      ; $C000
  DW  basic           ; $C002
  DW  readline        ; $C004
  DW  print           ; $C006
  DW  mode            ; $C008
  DW  cls             ; $C00A
  DW  home            ; $C00C
  DW  tab             ; $C00E
  DW  clear_sprites   ; $C010  (sub-optimal)
  DW  reset_gfx_remap ; $C012

reset_soft:
  SEI            ; disable interrupts
  CLD            ; disable BCD mode
  LDX #$FF
  TXS            ; stack init
  JSR chrcpy     ; copy tileset to VRAM
  LDX #4         ; screen mode 4 (40x25 text, 4 color, 2+2x16)
  JSR mode       ; set mode (+ clear screen)
  LDX #34
  LDY #1
  JSR tab
  LDX #>robologo
  LDY #<robologo
  JSR print
  LDX #34
  LDY #2
  JSR tab
  LDX #>robologo2
  LDY #<robologo2
  JSR print
  JSR home
  LDX #>welcome_1
  LDY #<welcome_1
  JSR print
  LDX #>welcome_2
  LDY #<welcome_2
  JSR print
  ; +++ fall through to @@ basic +++

; @@ basic
; enter the basic command-line interface
basic:
  LDA #>bas_jump
  STA IO_JTBL    ; set up BASIC jump table
  LDX #>ready
  LDY #<ready
  JSR print
  LDA #0         ; clear keyboard buffer
  STA KeyHd
  STA KeyTl
@repl:
  LDX #>prompt
  LDY #<prompt
  JSR print
  JSR readline
  JSR newline
  ; echo the command
  LDX #>LineBuf
  LDY #<LineBuf
  JSR print
  JSR newline
  STA IO_YLIN    ; wait for vblank
  STA IO_YLIN    ; wait for vblank
  STA IO_YLIN    ; wait for vblank
  STA IO_YLIN    ; wait for vblank
  STA IO_YLIN    ; wait for vblank
  STA IO_YLIN    ; wait for vblank
  JMP @repl

; 31488 leaves 5 pages (zero-page, stack, input-buffer, basic-loops, basic-misc)
robologo:
  DB 4, 8,12,12,9
robologo2:
  DB 4, 10,12,12,11
welcome_1:
  DB 16, "Robo BASIC 1.0",13,13
welcome_2:
  DB 17, "31744 bytes free",13
ready:
  DB 6, "READY",13
prompt:
  DB 1, ">"


; @@ print, in "text mode"
; write a length-prefix string to the screen
; assumes we're in "text mode" with DMA DST set up
print:           ; X=high Y=low
  STX SrcH       ; src high
  STY Src        ; src low
  LDY #0         ; string offset, counts up
  LDA (Src),Y    ; load string length
  TAX            ; length, counts down
  INY            ; advance to first char
@loop:
  LDA (Src),Y    ; [5] load char from string
  ; begin writechar inline
  CMP #13        ; [2] is it RETURN?
  BEQ @nl        ; [2] if so -> @nl
  STA IO_DDRW    ; [3] write tile byte to VRAM
  LDA #0         ; [2] white=15 (in 16-color mode)
  STA IO_DDRW    ; [3] write attribte byte to VRAM
  DEC WinRem     ; [5] at right edge of window?
  BEQ @nl        ; [2] if so -> @nl
  ; end writechar inline
@incr:
  INY            ; [2] advance string offset
  DEX            ; [2] decrement length
  BNE @loop      ; [3] not at end -> @loop
  RTS            ; [6] done
@nl:             ; wrap onto the next line and keep printing
  JSR newline    ; [6] uses A, preserves X,Y
  JMP @incr      ; [3] always
; control codes
; @ctrl:
;   CMP #13        ; [2] ENTER
;   BEQ @nl        ; [2]
;   CMP #8         ; [2] BACKSPACE
;   BEQ backspc    ; [2]
;   BNE @incr      ; [3] always (opposite test above)


; @@ writechar
; write a single character to the screen
; assumes we're in "text mode" with DMA DST set up
writechar:       ; A=char; preserves X,Y
  CMP #13        ; is it RETURN?
  BEQ newline    ; uses A, preserves X,Y -> will RTS
  STA IO_DDRW    ; [3] write tile byte to VRAM
  LDA #0         ; [2] white=15 (in 16-color mode)
  STA IO_DDRW    ; [3] write attribte byte to VRAM
  DEC WinRem     ; [5] at right edge of window?
  BNE ret        ; [3] if not -> RTS
; +++ fall through: wrap onto the next line

; @@ newline, in "text mode"
; advance to the next line inside the text window
; scroll the text window if we're at the bottom
; DMA is already set up (DST*) for "text mode"
newline:         ; uses A, preserves X,Y
  LDA WinRem     ; current WinRem
  CLC            ; unknown CF
  ADC #64        ; advance = 64 - (WinW - WinRem) = WinRem + 64 - WinW
  SEC            ;
  SBC WinW       ;
  CLC            ; 
  ASL A          ; A*2 for (text,attr) pairs [CF=1 if A >= 128]
  CLC            ; 
  ADC IO_DSTL    ; add destination low (may set CF=1)
  STA IO_DSTL    ; set destination low
  BCC @nohi      ; CF=0, did not cross a page boundary
  INC IO_DSTH    ; CF=1, increment destination high
@nohi:           ; 
  LDA WinW       ; reset remaining window width
  STA WinRem     ; must be ready to write in steady-state
ret:
  RTS


; halt:
;   STA IO_YLIN    ; wait for vblank
;   JMP halt


; ------------------------------------------------------------------------------
; PAGE 1

; @@ readline
; read a single line of input into the line buffer
readline:        ; uses A,X,Y
  LDA #1
  STA Tmp        ; init line offset [3] not [4]
@wait:
  STA IO_YLIN    ; wait for vblank (A ignored)
@more:
  JSR readchar   ; read char from keyboard, uses A,X,Y !Tmp
  BEQ @wait      ; if zero -> @wait
  CMP #13        ; is it RETURN?
  BEQ @done      ; if so -> exit
  LDY Tmp        ; load line offset [3] not [4]
  CMP #08        ; is it BACKSPACE?
  BEQ @backsp    ; if so -> @backsp
  STA LineBuf,Y  ; append to line buffer
  INY            ; advance line offset
  BEQ @beep      ; wrapped around -> @beep (and don't save line ofs)
  STY Tmp        ; save line offset [3] not [4]
  JSR writechar  ; output char to screen (A=char, preserves X,Y)
  JMP @more      ; keep reading chars
@done:
  LDY Tmp        ; get line offset  [extra +9]
  DEY            ; started at 1
  STY LineBuf    ; write string length in first byte
  RTS
@backsp:
  DEY            ; go back one place
  STY Tmp        ; save line offset [3] not [4]
    ; XXX decrement cursor position, detect window edge, etc
    ; XXX write a SPACE char over the contents
    ; XXX decrement the output pointer again
  JMP @more
@beep:
  JSR beep
  LDA KeyTl      ; clear keyboard buffer
  STA KeyHd
  JMP @wait


; @@ beep
; play an error beep over the speaker
beep:            ; XXX start beep playing
  RTS


modetab:
  .byte VCTL_APA+VCTL_H320+VCTL_V200+VCTL_2BPP                         ; mode 0, graphics,    4 color (320x200) 4
  .byte VCTL_APA+VCTL_H320+VCTL_V200+VCTL_4BPP                         ; mode 1, graphics,   16 color (160x200) 16
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP                                  ; mode 2, 40x25 text,  4 color (320x200) 4x8
  .byte VCTL_H320+VCTL_V200+VCTL_4BPP                                  ; mode 3, 20x25 text, 16 color (160x200) 16x2
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL                       ; mode 4, 40x25 text,  4 color (320x200) 2+2x16
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL+VCTL_NARROW           ; mode 5, 64x25 text,  4 color (320x200) 2+2x16
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL+VCTL_NARROW+VCTL_GREY ; mode 6, 64x25 text,  4 shade (320x200) 2+2x16

text_palette:
  ;       IIRRGGBB
  ; hex(0b00000000) 00
  ; hex(0b01000010) 42
  ; hex(0b01001000) 48
  ; hex(0b01001010) 4A
  ; hex(0b01100000) 60
  ; hex(0b01100010) 62
  ; hex(0b01100100) 64
  ; hex(0b01101010) 6A
  ; hex(0b11010101) D5
  ; hex(0b11010111) D7
  ; hex(0b11011101) DD
  ; hex(0b11011111) DF
  ; hex(0b11110101) F5
  ; hex(0b11110111) F7
  ; hex(0b11111101) FD
  ; hex(0b11111111) FF
  .byte $00, $42, $48, $4A, $60, $62, $64, $6A, $D5, $D7, $DD, $DF, $F5, $F7, $FD, $FF  ; ~EGA


; @@ mode, set screen mode in X
; modes 0-3 are linear APA modes, 1/2/4/8 bpp
; modes 4-7 are tiled "text" modes, 1/2/4/8 bpp
; modes 8-15 are greyscale versions of the above (no colorburst)
mode:            ; set screen mode
  CPX #7         ; range-check mode number
  BCS ret        ; if >= 7
  LDA modetab,X  ; screen mode config
  STA IO_VCTL    ; write video control register
  LDA #0
  STA IO_SCRH    ; reset scroll horizontal
  STA IO_SCRV    ; reset scroll vertical
  STA IO_FINH    ; reset horizontal fine scroll
  STA IO_FINV    ; reset vertical fine scroll
  STA WinL       ; reset text window left
  STA WinT       ; reset text window top
  LDA #40
  STA WinW       ; reset text window width
  LDA #28
  STA WinH       ; reset text window height  (XXX depends on mode)
  LDA #6         ; (BG_En|Spr_En)
  STA IO_VENA    ; interrupt/video enable
  LDA #4         ; w=64 (1<<2) h=32 (0)
  STA IO_VMAP    ; tilemap size (ignored in APA modes)
  LDA #>VR_TEXT  ; tilemap base address (ignored in APA modes)
  STA IO_VTAB    ; set tilemap high byte
  JSR reset_gfx_remap  ; reset tile graphics bank-switching
  JSR clear_sprites
; set_palette:
  LDX #0
  STX IO_PALA    ; set palette address
@pallp:
  LDA text_palette,X
  STA IO_PALD    ; write palette, increment
  INX
  CPX #16
  BNE @pallp
  ; +++ fall through to @@ cls +++

; @@ cls, in "text mode"
; clear the text window
; 64-40=24 wasted cycles: fill_rect saves 7 cycles per row
cls:                     ; clear tilemap
  LDA #32                ; [2] fill with $20 (space)
  STA IO_FILL            ; [3] DMA fill byte
  LDX WinL               ; [3] text window left
  LDY WinT               ; [3] text window top
  JSR text_addr_xy       ; [6] calculate DSTH,DSTL at X,Y
  LDA WinW               ; [3] text window width
  CLC                    ; [2]
  ASL A                  ; [2] text window width * 2 for (tile,attr)
  TAX                    ; [2] X = rect width param
  LDY WinH               ; [3] Y = rect height param
  LDA #128               ; [2] A = stride, always 128 bytes (64 tiles) in "text mode"
  JSR dma_fill_rect      ; [6] A=stride X=width Y=height (changes DMA mode!)
  LDA #DMA_M2V|DMA_Copy  ; [2] switch back to BASIC mode
  STA IO_DCTL            ; [3] set copy-mem-to-vram mode
  ; +++ fall through to @@ home +++

; @@ home
; move the cursor to the top-left of the window
; update DMA address (DSTL,DSTH) for "text mode"
home:
  LDX #0         ; top-left corner of text window
  LDY #0         ; 
  BEQ tab_e2     ; skip range checks

; @@ tab
; move the cursor to X,Y in index registers (unsigned)
; relative to the top-left corner of the text window, zero-based.
; update DMA address (DSTL,DSTH) for "text mode"
tab:
  CPX WinW       ; clamp X if out of range (WinW)
  BCC @x_ok      ; CC < WinW
  LDX WinW       ; (CS)
  DEX            ; (CS) clamp to last column (XXX reduce WinW by -1?)
@x_ok:
  CPY WinH       ; clamp Y if out of range (WinH)
  BCC @y_ok      ; CC < WinH
  LDY WinH
  DEY            ; clamp to last row  (XXX reduce WinH by -1?)
@y_ok:
tab_e2:
  STX CurX       ; cursor X
  STY CurY       ; cursor Y
  LDA WinW       ; WinRem = WinW - CurX
  SEC
  SBC CurX
  STA WinRem     ; accelerates PRINT
; Map from text window X,Y to tilemap X,Y
; SCRH,SCRV is the amount we have scrolled the text plane (in map-space)
; the text plane is 64x32 in "text mode"
  TXA            ; X column in text window
  CLC
  ADC WinL       ; X column in screen space (add window left)
  TAX            ; back to X
  TYA            ; Y row in text window
  CLC
  ADC WinT       ; Y row in screen space (add window top)
  TAY            ; back to Y
  ; +++ fall through to @@ text_addr_xy +++

; @@ text_addr_xy
; calculate the tilemap address for an X,Y coordinate; set the DMA DSTH,DSTL
; do not change the cursor position (use `tab` for that)
text_addr_xy:
  TXA            ; X column
  CLC            ; don't know state of CF
  ADC IO_SCRH    ; add H scroll (in map-space) -> X column in tilemap [may set CF=1]
  AND #63        ; modulo text map width (always 64 in "text mode")
  CLC            ; CF may be set
  ASL A          ; double it -> map to VRAM address-space, (tile,attr) pairs
  STA Tmp        ; save tilemap X coord
  TYA            ; Y row in text window
  CLC            ; above may set CF
  ADC IO_SCRV    ; Y row in tilemap (add V scroll offset) [may set CF=1]
  AND #31        ; modulo tilemap height (always 32 in "text mode")
  TAY            ; save tilemap Y cood
; Calculate VRAM address,
;  [00VVV000][00000000]  is a 2K boundary in VRAM
; +[00000YYY][YY000000]  which we can combine with OR
; +[00000000][00XXXXXX]  at 64x32 map size (assume width=64 "text mode")
  CLC
  AND #1         ; [0000000Y] low 1 bit of Y
  ROR            ; [00000000] C=Y
  ROR            ; [Y0000000] C=0
  ORA Tmp        ; [YXXXXXX0]
  STA IO_DSTL    ; DMA write-address low
  TYA            ; [000YYYYY] reload TileMap Y coord
  LSR            ; [0000YYYY]
  ORA #>VR_TEXT  ; [VVVVYYYY] text area base address ($3000 in "text mode")
  STA IO_DSTH    ; DMA write-address high
  RTS


; ------------------------------------------------------------------------------
; PAGE 2

; keymap tables
; must be page-aligned (uses 2x64 = 128 bytes)
ORG ROM+$200
;   Esc ` 1 2 3 4 5 6  7 8 9 0 - = DEL UP    (16)
;   Tab Q W E R T Y U  I O P [ ] \     DOWN  (15)
;  Caps A S D F G H J  K L ; '     RET LEFT  (14)
; Ctl LSh Z X C V B N  M , . / RSh SPC RIGHT (15)
scantab:
  DB  $1B, $60, $31, $32, $33, $34, $35, $36     ;   Esc ` 1 2 3 4 5 6
  DB  $09, $51, $57, $45, $52, $54, $59, $55     ;   Tab Q W E R T Y U
  DB  $00, $41, $53, $44, $46, $47, $48, $4A     ;  Caps A S D F G H J
  DB  $00, $00, $5A, $58, $43, $56, $42, $4E     ; Ctl LSh Z X C V B N
  DB  $37, $38, $39, $30, $2D, $3D, $00, $18     ;     7 8 9 0 - =     DEL
  DB  $49, $4F, $50, $5B, $5D, $5C, $00, $8B     ;     I O P [ ] \     UP
  DB  $4B, $4C, $3B, $27, $00, $00, $0D, $8A     ;     K L ; '     RET DOWN
  DB  $4D, $2C, $2E, $2F, $00, $20, $88, $89     ;     M , . / RSh SPC LEFT RIGHT
shiftab:
  DB  $1B, $7E, $40, $22, $23, $24, $25, $5E     ;   Esc ~ ! @ # $ % ^
  DB  $09, $71, $77, $65, $72, $74, $79, $75     ;   Tab q w e r t y u
  DB  $00, $61, $73, $64, $66, $67, $68, $6A     ;  Caps a s d f g h j
  DB  $00, $00, $7A, $78, $63, $76, $62, $6E     ; Ctl LSh z x c v b n
  DB  $26, $2A, $28, $29, $5F, $2B, $00, $18     ;     & * ( ) _ +     DEL
  DB  $69, $6F, $71, $7B, $7D, $7C, $00, $8B     ;     i o p { } |     UP
  DB  $6B, $6C, $3A, $22, $00, $00, $0D, $8A     ;     k l : "     RET DOWN
  DB  $6D, $3C, $3E, $3F, $00, $20, $88, $89     ;     m < > ? RSh SPC LEFT RIGHT

; @@ key_scan
; scan the keyboard matrix for a keypress
; [..ABCDE....]
;    ^hd  ^tl    ; empty when hd==tl, full when tl+1==hd
keyscan:         ; uses A,X,Y returns nothing (!Tmp)
  LDY #7         ; [2] last key column
@col_lp:         ; -> [13] cycles
  STY IO_KEYB    ; [3] set keyscan column (0-7)
  LDX IO_KEYB    ; [3] read key state bitmap
  BNE @key_hit   ; [2] -> one or more keys pressed
  DEY            ; [2] prev key column
  BPL @col_lp    ; [3] go again, until Y<0
  STY LastKey    ; [3] no keys pressed: clear last key pressed
  RTS            ; [6] TOTAL Scan 2+13*8-1+6 = [111] cycles
@key_hit:
  TYA            ; active keyscan column
  ASL            ; column * 8
  ASL
  ASL
  TAY            ; scantab offset = col*8
  TXA            ; key state bitmap
; find first bit set
; loop WILL terminate because A is non-zero!
@bsf_lp:         ; -> [7] cycles
  INY            ; [2] count number of shifts
  ASL A          ; [2] shift keys bits left into CF
  BCC @bsf_lp    ; [3] until CF=1
; translate to ascii
  DEY            ; went one too far: [1..8]->[0..7]
  LDA scantab,Y  ; translate to ASCII
  CMP LastKey    ; debounce
  BEQ @done      ; XXX auto-repeat
  STA LastKey    ; save last key pressed, for auto-repeat
; append to keyboard buffer
  LDY KeyTl      ; keyboard buffer write offset
  STA KeyBuf,Y   ; always safe to write at KeyTl
  INY            ; increment
  TYA
  AND #31        ; modulo circular buffer
  CMP KeyHd      ; Tl+1 == Hd -> @full (don't increment)
  BEQ @done
  STA KeyTl      ; update Tl = Tl+1 % 32
@done:
  RTS


; @@ readchar
; read a single character from the keyboard buffer
; AUTO-REPEAT: the last key held (save its scancode to compare)
; ROLLOVER: pressing a new key replaces the prior held key
; INKEY(-K): directly scans the key (high 5:col low 3:row)
readchar:        ; uses A,X,Y returns ASCII or zero (!Tmp)
  JSR keyscan    ; scan keyboard, fill buffer     (XXX move to VSync interrupt)
  LDX KeyHd      ; [3] load keyboard buffer head
  CPX KeyTl      ; [3] Hd == Tl -> empty, @wait
  BEQ @nokey     ; [2] buffer is empty
  LDY KeyBuf,X   ; [4] next buffered key
  INX            ; [2]inc keyboard buffer head
  TXA            ; [2]
  AND #31        ; [2] modulo circular buffer
  STA KeyHd      ; [3] save new head
  TYA            ; [2]
  RTS            ; [6] return A
@nokey:
  LDA #0         ; [2] return 0
  RTS            ; [6]


; @@ clear_sprites
; reset all 32 sprites to an offscreen (invisible) position
; sprites are [Y-coord][X-coord][attribs][tile-idx]
; YYY it would be useful (and faster) to have a DMA fill-sprites mode
clear_sprites:
  LDA #$80       ; sprite Y-coord ptr (first SBC takes us to $7C, the last sprite)
  LDX #$FF       ; offscreen Y coord
@sprloop:
  SEC
  SBC #4         ; [2] previous sprite Y coord
  STA IO_SPRA    ; [3] set sprite address
  STX IO_SPRD    ; [3] set Y coord to $FF (offscreen)
  BNE @sprloop   ; [3] until A=0  [[ 11*32 = 352 cycles | DMA: 32 cycles! ]]
  RTS


; @@ reset_gfx_remap
; reset all tile bank-switching to the default 1:1 mapping
reset_gfx_remap:
  LDA #$00       ; map slot 0 to address-region 0
  CLC
@banklp:
  STA IO_VBNK    ; [3] bank slot,addr [ssssaaaa]
  ADC #$11       ; [2] 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF ..
  BCC @banklp    ; [3] .. 110 (C=1)  [[ 16*8 = 128 cycles ]]
  RTS


; @@ FREE SPACE ~ 36 bytes free


; ------------------------------------------------------------------------------
; PAGE 3

; one-address opcodes would work better for 6502
; since we need to copy pointers/values to zp anyway
; so define an accumulator in ZP

; could stack 5-byte values in zp at $80-$FF
; or use the actual stack? reserve 40 x 5 = 200 stack bytes for expression nesting.
; CLC; PLA; ADC Acc0; STA Acc0; PLA; ADC Acc1; STA Acc1; PLA; ADC Acc2; STA Acc2; ... (Stack + Paren Result)
; SEC; PLA; SBC Acc0; STA Acc0; PLA; SBC Acc1; STA Acc1; PLA; SBC Acc2; STA Acc2; ... (Stack - Paren Result)
; SEC; PLA; EOR #$FF; ADC Acc0; STA Acc0; PLA; EOR #$FF; ADC Acc1; STA Acc1; ... (Paren Result - Stack)

; what about parens? if leftmost, just do it.
; if not, they come after an operator;
; push the current Acc while evaluating the parens,
; then restore acc and (operator) the result 'var'.

ORG ROM+$300

bas_jump:       ; MUST be page-aligned (Jump Table HW only takes a page byte)
  DW ar_i1const, ar_i2const, ar_i3const, ar_i4const
  DW ar_f1const, ar_f2const, ar_f3const, ar_f4const
  DW ar_ivar,    ar_fvar
  DW ar_uadd1c,  ar_uadd2c,  ar_uadd3c,  ar_uadd4c
  DW ar_iaddv,  ar_isubv
  DW ar_ipush,  ar_ipopadd, ar_ipopsub, ar_ipoprsb

; LOAD CONSTANT

ar_f1const:      ; load floating point constant (1-byte mantissa)
  LDA_DMA        ; [3] const mantissa
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i1const:      ; load 1-byte signed integer constant
  LDA_DMA        ; [3] const byte 0
  STA Acc0       ; [3]
  ORA #$7F       ; [2] sign extend
  BMI @neg       ; [2] -> [3]
  LDA #0         ; [2] positive
@neg:
  STA Acc1       ; [3] sign extend
  STA Acc2       ; [3] sign extend
  STA Acc3       ; [3] sign extend      (21 CYCLES)
  DISPATCH

ar_f2const:      ; load floating point constant (2-byte mantissa)
  LDA_DMA        ; [3] const mantissa
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i2const:      ; load 2-byte signed integer constant
  LDA_DMA        ; [3] const byte 0
  STA Acc0       ; [3]
  LDA_DMA        ; [3] const byte 1
  STA Acc1       ; [3]
  ORA #$7F       ; [2] sign extend [14]
  BMI @neg       ; [2] -> [3]
  LDA #0         ; [2] positive
@neg:
  STA Acc2       ; [3]  sign extend
  STA Acc3       ; [3]  sign extend     (24 CYCLES)
  DISPATCH

ar_f3const:      ; load floating point constant (3-byte mantissa)
  LDA_DMA        ; [3] const mantissa
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i3const:      ; load 3-byte signed integer constant
  LDA_DMA        ; [3] const byte 0
  STA Acc0       ; [3]
  LDA_DMA        ; [3] const byte 1
  STA Acc1       ; [3]
  LDA_DMA        ; [3] const byte 2
  STA Acc2       ; [3]
  ORA #$7F       ; [2] sign extend [20]
  BMI @neg       ; [2] -> [3]
  LDA #0         ; [2] positive
@neg:
  STA Acc3       ; [3] sign extend      (27 CYCLES)
  DISPATCH

ar_f4const:      ; load floating point constant (4-byte mantissa)
  LDA_DMA        ; [3] const mantissa
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i4const:      ; load 4-byte signed integer constant
  LDA_DMA        ; [3] const byte 0
  STA Acc0       ; [3]
  LDA_DMA        ; [3] const byte 1
  STA Acc1       ; [3]
  LDA_DMA        ; [3] const byte 2
  STA Acc2       ; [3]
  LDA_DMA        ; [3] const byte 3
  STA Acc3       ; [3]                  (24 CYCLES)
  DISPATCH


; LOAD VARIABLE

ar_ivar:         ; read an integer variable
  LDX_DMA        ; [3] var pointer low
  LDA_DMA        ; [3] var pointer high
  ; fall
;ar_ireadax:     ; also used to read from arrays (COPY Indirect)
  STX Src        ; [3]
  STA SrcH       ; [3]
  LDY #0         ; [2]
  ; fall
ar_iread4:
  LDA (Src),Y    ; [5] load var low byte
  STA Acc0       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] load var byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] load var byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] load var high byte
  STA Acc3       ; [3]
  DISPATCH

ar_fvar:         ; read an integer variable
  LDA_DMA        ; [3] var pointer low
  STA Src        ; [3]
  LDA_DMA        ; [3] var pointer high
  STA SrcH       ; [3]
  LDY #0         ; [2]
  LDA (Src),Y    ; [5] load var low byte
  STA AccE       ; [3] exponent
  INY            ; [2]
  BNE ar_iread4  ; [2] always taken


; ADD CONST INT

ar_uadd1c:       ; add 1-byte unsigned integer constant
  CLC            ; [2]
  LDA_DMA        ; [3] 
  ADC Acc0       ; [3] add constant byte 0
  STA Acc0       ; [3]
  BCS uadd_cs1   ; [2] -> ripple carry  (13 CYCLES)
  DISPATCH

uadd_cs1:        ; add carry into byte 1
  LDA #0         ; [2]
  ADC Acc1       ; [3]
  STA Acc1       ; [3]
  BCS uadd_cs2   ; [2] -> ripple carry  (10+14=24 CYCLES)
  DISPATCH

ar_uadd2c:       ; add 2-byte unsigned integer constant
  CLC            ; [2]
  LDA_DMA        ; [3] 
  ADC Acc0       ; [3] add constant byte 0
  STA Acc0       ; [3]
  LDA_DMA        ; [3] 
  ADC Acc1       ; [3] add constant byte 1
  STA Acc1       ; [3]
  BCS uadd_cs2   ; [2] -> ripple carry  (13 CYCLES)
  DISPATCH

uadd_cs2:        ; add carry into byte 2
  LDA #0         ; [2]
  ADC Acc2       ; [3]
  STA Acc2       ; [3]
  BCS uadd_cs3   ; [2] -> ripple carry  (10+25=35 CYCLES)
  DISPATCH

ar_uadd3c:       ; add 3-byte unsigned integer constant
  CLC            ; [2]
  LDA_DMA        ; [3] 
  ADC Acc0       ; [3] add constant byte 0
  STA Acc0       ; [3]
  LDA_DMA        ; [3] 
  ADC Acc1       ; [3] add constant byte 1
  STA Acc1       ; [3]
  LDA_DMA        ; [3] 
  ADC Acc2       ; [3] add constant byte 2
  STA Acc2       ; [3]                                               <--- PAGE 4
  BCS uadd_cs3   ; [2] -> ripple carry  (13 CYCLES)
  DISPATCH

; ------------------------------------------------------------------------------
; PAGE 4

uadd_cs3:        ; add carry into byte 3
  LDA #0         ; [2]
  ADC Acc3       ; [3]
  STA Acc3       ; [3]
  BVS overflow   ; [2] ->overflow       (10+36=46 CYCLES)
  DISPATCH

ar_uadd4c:       ; add 4-byte unsigned integer constant
  CLC            ; [2]
  LDA_DMA        ; [3] 
  ADC Acc0       ; [3] add constant byte 0
  STA Acc0       ; [3]
  LDA_DMA        ; [3] 
  ADC Acc1       ; [3] add constant byte 1
  STA Acc1       ; [3]
  LDA_DMA        ; [3] 
  ADC Acc2       ; [3] add constant byte 2
  STA Acc2       ; [3]
  LDA_DMA        ; [3] 
  ADC Acc3       ; [3] add constant byte 3
  STA Acc3       ; [3]
  BVS overflow   ; [2] ->overflow       (13 CYCLES)
  DISPATCH


; VARS - ADD INTEGER

ar_iaddv:        ; add an integer variable
  LDX_DMA         ; [3] var pointer low
  LDA_DMA         ; [3] var pointer high
  ; fall
;ar_iaddax:
  STX Src        ; [3]
  STA SrcH       ; [3]
  LDY #0         ; [2]
  CLC            ; [2] 16
  LDA Acc0       ; [3]
  ADC (Src),Y    ; [5] add var low byte
  STA Acc0       ; [3]
  INY            ; [2]
  LDA Acc1       ; [3]
  ADC (Src),Y    ; [5] add var byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA Acc2       ; [3]
  ADC (Src),Y    ; [5] add var byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA Acc3       ; [3]
  ADC (Src),Y    ; [5] add var high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check  16+4*13 = (68 CYCLES)
  DISPATCH

ar_isubv:        ; subtract an integer variable (pointer follows)
  LDX_DMA         ; [3] var pointer low
  LDA_DMA         ; [3] var pointer high
;ar_isubax:
  STX Src        ; [3]
  STA SrcH       ; [3]
  LDY #0         ; [2]
  SEC            ; [2] 16
  LDA Acc0       ; [3]
  SBC (Src),Y    ; [5] subtract var low byte
  STA Acc0       ; [3]
  INY            ; [2]
  LDA Acc1       ; [3]
  SBC (Src),Y    ; [5] subtract var byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA Acc2       ; [3]
  SBC (Src),Y    ; [5] subtract var byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA Acc3       ; [3]
  SBC (Src),Y    ; [5] subtract var high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check  16+4*13 = (68 CYCLES)
  DISPATCH

overflow:
  BRK
  DW 1


; PUSH / POP - INTEGER

ar_ipush:        ; push acc (begin sub-expr)
  LDA Acc0       ; [3]
  PHA            ; [3] push low byte
  LDA Acc0       ; [3]
  PHA            ; [3] push byte 1
  LDA Acc0       ; [3]
  PHA            ; [3] push byte 2
  LDA Acc0       ; [3]
  PHA            ; [3] push high byte   (24 CYCLES)
  DISPATCH

ar_ipopadd:      ; pop int; acc += int (end sub-expr)
  CLC            ; [2] for addition
  PLA            ; [4]
  ADC Acc0       ; [3] add low byte
  STA Acc0       ; [3]
  PLA            ; [4]
  ADC Acc1       ; [3] add byte 1
  STA Acc1       ; [3]
  PLA            ; [4]
  ADC Acc2       ; [3] add byte 2
  STA Acc2       ; [3]
  PLA            ; [4]
  ADC Acc3       ; [3] add high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check   (44 CYCLES)
  DISPATCH

ar_ipopsub:      ; pop int; acc -= int (end sub-expr)
  PLA            ; [4]
  EOR #$FF       ; [2] invert,
  SEC            ; [2] and add one
  ADC Acc0       ; [3] reverse-subtract low byte
  STA Acc0       ; [3]
  PLA            ; [4]
  EOR #$FF       ; [2] invert
  ADC Acc1       ; [5] subtract byte 1
  STA Acc1       ; [3]
  PLA            ; [4]
  EOR #$FF       ; [2] invert
  ADC Acc2       ; [5] subtract byte 2
  STA Acc2       ; [3]
  PLA            ; [4]
  EOR #$FF       ; [2] invert
  ADC Acc3       ; [5] subtract high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check
  DISPATCH

ar_ipoprsb:      ; pop int; acc = int - acc (reverse subtract)
  SEC            ; [2] for subtract
  PLA            ; [4]
  SBC Acc0       ; [3] subtract low byte
  STA Acc0       ; [3]
  PLA            ; [4]
  SBC Acc1       ; [3] subtract byte 1
  STA Acc1       ; [3]
  PLA            ; [4]
  SBC Acc2       ; [3] subtract byte 2
  STA Acc2       ; [3]
  PLA            ; [4]
  SBC Acc3       ; [3] subtract high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check   (44 CYCLES)
  DISPATCH


; @@ bas_print
; PRINT basic statement
bas_print:
  ; ...
  JSR print
  DISPATCH



ORG CHROM        ; 256 x 8 = 2K char rom
  INCLUDE "font/font.txt"

ORG BOOT
; Gfx in VRAM are 2bpp as HLHLHLHL (4 pixels)
; Gfx in ROM are 1bpp interleaved as BABABABA (8 pixels, A then B)
chrcpy:          ; copy 2K charmap to 4K CHAR RAM  [[ 51 bytes ]]
  LDA #DMA_M2V|DMA_Copy
  STA IO_DCTL    ; [3] set DMA mode: write to VRAM
  LDY #0         ; [2] zero
  STY IO_DSTH    ; [3] VRAM dest, high byte
  STY IO_DSTL    ; [3] VRAM dest, low byte
  STY Src        ; [3] src low byte (temp+0)
  LDA #>CHROM    ; [2] src first page
  STA SrcH       ; [3] src high byte (temp+1)
chrcpy_lp:
  LDA (Src),Y    ; [6] read 'BABABABA' (packed in ROM)
  TAX            ; [2] save temp (using all of A,X,Y)
  AND #$55       ; [2] 01010101 to get A
  STA IO_DDRW    ; [6] write '0A0A0A0A' (1st four px)
  TXA            ; [2] restore packed 'BABABABA'
  CLC            ; [2] shifted into top bit:
  LSR            ; [2] shift B into A position
  AND #$55       ; [2] 01010101 to get B
  STA IO_DDRW    ; [6] write '0B0B0B0B' (2nd four px)
  INY            ; [2] increment src
  BNE chrcpy_lp  ; [3] until Y=0 (copy 256 from src)
  INC SrcH       ; [5] next source page
  LDA SrcH       ; [3] src high byte
  CMP #>CHROM_E  ; [2] reached end page?
  BNE chrcpy_lp  ; [3]
  RTS

reset_hard:
  SEI                    ; disable interrupts
  CLD                    ; disable BCD mode
  LDX #$FF
  TXS                    ; stack init
; turn on power LED to help with troubleshooting
  LDA #VENA_Pwr_LED      ; turn on Power LED
  STA IO_VENA
; memory check: don't start up if RAM is bad.
; test zero page, without using zero-page indirect
  LDA #$55
  JSR @zptest
  LDA #$AA
  JSR @zptest
; test remaining pages using zero-page indirect
  LDX #0                 ; [2]
  STX $00                ; [3] pointer low (=0)
  INX                    ; [2] page byte (=1)
  LDA #$FE               ; [2] 256-2 bytes (top stack entry in use)
  STA $03                ; [3] set initial Y count for stack page (=$FE)
@pg_lp:
  LDA #$55
  JSR @memchk            ; relies on $1FE,$1FF (will crash otherwise)
  LDA #$AA
  JSR @memchk            ; relies on $1FE,$1FF (will crash otherwise) -> Y=0
  LDY #0                 ; XXX testing, remove
  STY $03                ; [3] reset Y count: full page of 256 bytes (=$00)
  INX                    ; [2] next page
  BPL @pg_lp             ; stop when X=128 (32K)
; all tests pass
  JMP reset_soft         ; all tests passed

; @@ zptest
; relies on $1FE-$1FF (will crash otherwise)
@zptest:
  STA $00                ; [3] save fill byte in byte 0
  LDX #$BF               ; [2] below IO area
@zpf_lp:
  STA $00,X              ; [4] indexed write
  DEX                    ; [2] count down
  BNE @zpf_lp            ; [3] until Y=0 (write 191)
  LDX #$BF               ; [2] below IO area
@zpc_lp:
  CMP $00,X              ; [4] indexed compare
  BNE badram             ; [3] fail if not equal
  DEX                    ; [2] count down
  BNE @zpc_lp            ; [3] until X=$00 (which holds fill byte)
  CMP $00                ; [3] verify fill byte in $00
  BNE badram             ; [3] fail if not equal
  RTS

; @@ memchk
; relies on $1FE-$1FF (will crash otherwise)
@memchk:                 ; A=fill X=page Y=bytes (preserves A,X returns Y=0)
  STX $01                ; [3] pointer high = page byte
; fill the page
  LDY $03                ; [3] load Y count (256 [=$00] except for stack page)
@mmf_lp:
  DEY                    ; [2] pre-decrement
  STA ($00),Y            ; [6] write fill byte
  BNE @mmf_lp            ; [3]
; compare the result
  LDY $03                ; [3] load Y count (256 [=$00] except for stack page)
  DEY                    ; [2] last byte of page to be scanned
@mmc_lp:
  CMP ($00),Y            ; [5] verify fill byte
  BNE badram             
  DEY
  BNE @mmc_lp
  CMP ($00),Y            ; verify last byte (Y=0)
  BNE badram
  RTS

; @@ badram
; RAM test failed: blink the Caps LED
; this toggles ~4 times (2 blinks) per second [NTSC timing]
badram:
  LDA IO_VENA
  EOR #VENA_Caps_LED   ; toggle Caps LED
  STA IO_VENA
  LDX #15              ; 60/4=15 frames
@delay:                ; for 15 frames
  STA IO_YLIN          ; wait for VBlank
  DEX                  ; 
  BNE @delay           ; 
  JMP badram


; @@ dma_fill_rect
; fill VRAM rect with byte FILL at address DSTH,DSTL (changes DMA mode!)
dma_fill_rect:           ; A=stride X=width Y=height
  STA Tmp                ; [3] save stride
  LDA #DMA_M2V|DMA_Fill  ; [2] VRAM fill mode
  STA IO_DCTL            ; [3] set DMA mode
  LDA IO_DSTL            ; [3] keep DSTL in A
@loop:
  STX IO_DRUN            ; [3] start DMA (fill 'width' bytes)
  CLC                    ; [2]
  ADC Tmp                ; [3] address += stride
  STA IO_DSTL            ; [3] set new DSTL
  BCC @low_ok            ; [3] C=1 when DSTL wraps around
  INC IO_DSTH            ; [5] address high += 1
@low_ok:
  DEY                    ; [2] decrement height
  BNE @loop              ; [3] until Y=0  [[ 17 per iteration ]]
  RTS                    ; [6]


; @@ dma_fill_vram
; fill VRAM with byte A, start at page X, fill Y pages (changes DMA mode!)
dma_fill_vram:           ; A=byte X=base.pg Y=count
  STA IO_FILL            ; [3] DMA fill byte
  LDA #DMA_M2V|DMA_Fill  ; [2] DMA fill mode (M2M)
  STA IO_DCTL            ; [3] set fill mode
  STX IO_DSTH            ; [3] DMA dest high (page)
  LDA #0                 ; [2]
  STA IO_DSTL            ; [3] DMA dest low  (0)
@loop:
  STA IO_DRUN            ; [3] start DMA (fill 256 bytes)
  DEY                    ; [2]
  BNE @loop              ; [3]
  RTS                    ; [6]


intv:
  RTI

ORG VEC
DW intv          ; $FFFA, $FFFB ... NMI (Non-Maskable Interrupt) vector
DW reset_soft    ; $FFFC, $FFFD ... RES (Reset) vector
DW intv          ; $FFFE, $FFFF ... IRQ (Interrupt Request) vector
