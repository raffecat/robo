; Robo BASIC 1.0
; Use `asm6` to compile: https://github.com/parasyte/asm6

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

ZeroPg   = $0000  ; zero page
StackPg  = $0100  ; stack page
SysPg    = $0200  ; keyboard(16) system-vars(16) sound(64) serial(64)
LineBuf  = $0300  ; line buffer, disk/tape buffer, expression stack
Scratch  = $0400  ; scratch space (BASIC stack, parser output)
LOMEM    = $0400  ; bottom of BASIC memory
HIMEM    = $8000  ; top of BASIC memory
FREEMEM  = HIMEM-LOMEM

KeyBuf   = $0200  ; keyboard buffer in SysPg (16 bytes)
SysCmds  = $0210  ; REPL command-list pointer {Bank,Low,High} (for ROM override)
SysStmt  = $0213  ; BASIC statement extension cmd-list {Bank,Low,High} (for ROM override)
IrqVec   = $0216  ; IRQ vector in RAM {JMP abs instruction} (for ROM override)

; ------------------------------------------------------------------------------
; Zero Page

Src      = $00    ; source pointer
SrcH     = $01    ; source pointer high
Ptr      = $02    ; second pointer
PtrH     = $03    ; second pointer high
Tmp      = $04    ; temp
Tmp2     = $05    ; temp
Tmp3     = $06    ; temp
Tmp4     = $07    ; temp 4 (used by AUTO [can't use in parser])

; Keyboard buffer

KeyHd    = $0A    ; keyboard buffer head (owned by User)
KeyTl    = $0B    ; keyboard buffer tail (owned by IRQ)
ModKeys  = $0C    ; modifier keys [7:Esc 6:Shf 5:Ctl 4:Fn] (owned by IRQ)
LastKey  = $0D    ; keyboard last key pressed, for auto-repeat (owned by IRQ)

; BASIC vars

AccE     = $10    ; Accumulator exponent
Acc0     = $11    ; Accumulator low byte
Acc1     = $12    ; Accumulator byte 1
Acc2     = $13    ; Accumulator byte 2
Acc3     = $14    ; Accumulator high byte

TermE     = $15    ; Term exponent
Term0     = $16    ; Term low byte
Term1     = $17    ; Term byte 1
Term2     = $18    ; Term byte 2
Term3     = $19    ; Term high byte

Code     = $1C    ; saved BASIC code address
CodeH    = $1D
Line     = $1E    ; current line number (used by AUTO, parse_cmd, bas_ins_line)
LineH    = $1F

; Video vars

WinRem   = $20    ; remaining horizontal space in text window
WinL     = $21    ; text window left
WinT     = $22    ; text window top
WinW     = $23    ; text window width
WinH     = $24    ; text window height
CurX     = $25    ; text cursor X                   XXX need these?
CurY     = $26    ; text cursor Y                   XXX need these?
Dstl     = $27    ; text write address low  (saved DSTL)
Dsth     = $28    ; text write address high (saved DSTH)
Color    = $29    ; text color (bg-col : fg-col)

; High vars

IRQTmp   = $BF    ; Temp for IRQ handler

; ------------------------------------------------------------------------------
; Defines

ModShift = $80    ; Shift is down
ModCtrl  = $40    ; Ctrl is down
ModFn    = $20    ; Fn is down
ModCaps  = $10    ; Caps lock is down
ModLeft  = $08    ; Left Arrow is down
ModRight = $04    ; Right Arrow is down
ModDown  = $02    ; Down Arrow is down
ModUp    = $01    ; Up Arrow is down

; IO Registers

IO_SRCL     = $D0    ; DMA src low
IO_SRCH     = $D1    ; DMA src high
IO_DSTL     = $D2    ; DMA dest low
IO_DSTH     = $D3    ; DMA dest high
IO_DCTL     = $D4    ; DMA control         (7-6:direction 5:vertical 4:reverse 2-0:mode)
IO_DRUN     = $D5    ; DMA count           (write: start DMA, 0=256; read: increment DST += 640)
IO_FILL     = $D6    ; DMA fill byte       (write: set FILL byte [data latch]; read: last value to/from IO_DDRW)
IO_DDRW     = $D7    ; DMA data R/W        (read: reads from src++; write: writes to dest++)
IO_DJMP     = $D8    ; DMA jump indirect   (read: indirect table jump [stalls for +1 cycle]; write: set Jump Table [page latch])
IO_APWR     = $D9    ; DMA APA write       (read: second byte of indirect jump; write: triggers APA write cycle, writes [page latch])
IO_BNK8     = $DA    ; Bank switch $8000   (low 6 bits)
IO_BNKC     = $DB    ; Bank switch $C000   (low 6 bits)
;------     = $DC    ; 
;------     = $DD    ; 
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
;------     = $EE    ; 
;------     = $EF    ; 

IO_YLIN     = $F0    ; current Y-line         (read: V-counter; write: wait for VBlank)
IO_YCMP     = $F1    ; compare Y-line         (read/write, $FF won't trigger)
IO_SCRH     = $F2    ; horizontal scroll      (tile offset from 0, wraps) [in map-space]
IO_SCRV     = $F3    ; vertical scroll        (row offset from 0, wraps)  [in map-space]
IO_FINH     = $F4    ; horizontal fine scroll (top 3 bits)                [in bit-space]
IO_FINV     = $F5    ; vertical fine scroll   (top 3 bits)                [in bit-space]
IO_VCTL     = $F6    ; video control          (7:APA 6:Grey 5:HCount 4:Double 3-2:VCount 1-0:Divider)
IO_VENA     = $F7    ; interrupt enable       (7:VSync 6:VCmp 5:HSync 3:Power_LED 2:Caps_LED 1:Spr_En 0:BG_En)
IO_VSTA     = $F8    ; interrupt status       (7:VSync 6:VCmp 5:HSync)  (read:status / write:clear)
IO_VMAP     = $F9    ; name table size        (2:2 width 32,64,128,256; height 32,64,128,256)
IO_VTAB     = $FA    ; name table base        (page byte)
IO_VBNK     = $FB    ; tile bank R/W          (write: [sssaaaa] set slot to addr*1K; read: [sss-----] read slot)
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
DMA_Copy       = 0     ; copy from source to destinaton
DMA_Fill       = 1     ; using fill byte (write IO_FILL)
DMA_Masked     = 2     ; copy pixels, skip zero pixels (shares APA HW)
DMA_APA        = 3     ; APA addressing: low 3 bits of address select pixel; BPP from VCTL
DMA_Palette    = 4     ; read src / write dest is palette memory, SRCL/DSTL only; ignores direction
DMA_Sprite     = 5     ; read src / write dest is sprite memory, SRCL/DSTL only; ignores direction
DMA_SprClr     = 6     ; write $FF to Y coords of sprites (inc by 4), DSTL only; ignores direction
; VCTL flags [ANCGVVHD]
VCTL_APA       = $80   ; linear framebuffer at address 0 (or linear 8x8 tiles?)
VCTL_NARROW    = $40   ; 5x8 tiles at 2bpp only; left 5 pixels of each tile (64 columns)
VCTL_16COL     = $20   ; attributes contain [BBBBFFFF] BG,FG colors (2+2x16 colours)
VCTL_LATCH     = $20   ; in APA mode, latch color on zero (filled shapes mode)
VCTL_GREY      = $10   ; disable Colorburst for text legibility
VCTL_V240      = $0C   ; 240 visible lines per frame
VCTL_V224      = $08   ; 224 visible lines per frame
VCTL_V200      = $04   ; 200 visible lines per frame
VCTL_V192      = $00   ; 192 visible lines per frame
VCTL_H320      = $02   ; 320 visible pixels per line (shift rate)
VCTL_H256      = $00   ; 256 visible pixels per line (shift rate)
VCTL_4BPP      = $01   ; divide clock by 4, use 4 bits per pixel (double-width)
VCTL_2BPP      = $00   ; divide clock by 2, use 2 bits per pixel (square pixels)
; VENA flags
VENA_VSync     = $80
VENA_VCmp      = $40
VENA_HSync     = $20
VENA_Pwr_LED   = $08
VENA_Caps_LED  = $04
VENA_Spr_En    = $02
VENA_BG_En     = $01
; VSTA flags
VSTA_VSync     = $80
VSTA_VCmp      = $40
VSTA_HSync     = $20


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

; ROM entry table     ; public entry points (double-JMP vectors)
  DB  10              ; ROM version 1.0
  DB  11              ; number of entry points:
  JMP reset           ; $C000  reset the computer                              (JMP)
  JMP basic           ; $C002  enter BASIC                                     (JMP)
  JMP print           ; $C004  print len-prefix X=page Y=offset                (JSR uses A,X,Y)
  JMP writechar       ; $C006  print char in A                                 (JSR preserves X,Y)
  JMP newline         ; $C008  print a newline, scroll if necessary            (JSR preserves X,Y)
  JMP readline        ; $C00A  read a line into LineBuf page (zero-terminated) (JSR uses A,X,Y)
  JMP mode            ; $C00C  set screen mode, clear the screen               (JSR uses A,X,Y)
  JMP cls             ; $C00E  clear the screen                                (JSR uses A,X,Y)
  JMP tab             ; $C010  move the text cursor to X,Y                     (JSR uses A,X,Y)
  JMP clear_sprites   ; $C012                                                  (JSR preserves Y)
  JMP reset_tilebank  ; $C014                                                  (JSR preserves X,Y)

messages:    ; must be within one page for Y indexing
welcome_1:
  DB 14, "Robo BASIC 1.0"
welcome_2:
  DB 12, " bytes free",13
ready:
  DB 5, "READY"
err_range:
  DB 8, "Bad line"
err_stmt:
  DB 11, "Bad command"
err_bound:
  DB 13,"Out of bounds"
msg_expecting:
  DB 10,"Expecting "
err_no:
  DB 3,"No "
err_var:
  DB 16,"No such variable"
err_div:
  DB 11,"Div by zero"
err_ovf:
  DB 8,"Overflow"
err_type:
  DB 13,"Type mismatch"
err_escape:
  DB 7, 13, "Escape"
err_prog:
  DB 10,"No program"

reset:
  SEI            ; disable interrupts
  CLD            ; disable BCD mode
  LDX #$FF       ; reset stack [to align it?]
  TXS            ; stack init
  JSR chrcpy     ; copy tileset to VRAM (XXX move to Mode?)
  LDX #$1F       ; blue BG white FG
  STX Color      ; set text color (before MODE)
  LDX #4         ; screen mode 4 (40x25 text, 16 color)
  JSR mode       ; set mode, clear screen (uses Color)
  LDY #<welcome_1
  JSR printmsg
  ; 32768 - 5*256 (ZeroPg, StackPg, SysPg, LineBuf, Scratch)
  ; 16384 will be added for each bank of expanded RAM
  LDA #<31488    ; low
  STA Acc0
  LDA #>31488    ; high
  STA Acc1
  JSR n16_print
  LDY #<welcome_2
  JSR printmsg
  LDY #<ready
  JSR printmsg
  ; +++ fall through to @@ basic +++

; @@ basic
; enter the basic command-line interface
basic:
  CLD            ; disable BCD mode (for re-entry)
  JSR irq_init   ; init IRQ vector, init keyboard, enable IRQ
  LDA #>bas_jump ; high byte
  STA IO_DJMP    ; set BASIC jump table page (XXX move to enter_interp)
repl:            ; <- entry point after parse error
  LDA #$3E       ; ">"
  JSR writechar
  ; XXX must restore text cursor after parsing/interpreting?
basic_e1:        ; <- entry point after Escape
  LDX #$FF       ; reset stack on entry (e.g. from Escape) [for overflow detect]
  TXS            ; stack init
  JSR readline   ; -> Y=length
  JSR newline    ; preserves X,Y
  JSR parse_cmd
  JMP repl

; @@ repl_esc
; Escape from readline or the interpreter
repl_esc:
  LDY #<err_escape
  JSR printmsg
  LDA #$3E       ; ">"
  JSR writechar
@wait:           ; wait for Escape to be released
  STA IO_YLIN    ; wait for vblank
  LDA ModKeys    ; check key state
  BMI @wait      ; -> Escape still down
  JMP basic_e1   ; -> re-enter repl


; ------------------------------------
; BASIC Parser

e_stmt:
  LDY #<err_stmt
  JMP pf_error

; @@ parse_cmd
; parse a BASIC command line
parse_cmd:
  LDX #0           ; [2]
  JSR skip_spc     ; [24+] leading spaces

  ; parse line number
  JSR n16_parse    ; [12+] parse number at LineBuf,X -> {Acc0/1}, X, EQ=no (uses A,Y,Tmp)
  BNE @haveline    ; [2] -> found line number [+1]

  ; try matching a repl command
  LDA #<repl_tab   ; [2] repl commands table
  LDY #>repl_tab   ; [2]
  JSR scan_kw_all  ; [6] search -> CF=1 if found, X=next-input
  BCC @immediate   ; [3] -> no match, parse immediate
  EOR #$80         ; [2] clear top bit
  CMP #repl_len    ; [2] ASSERT
  BCS e_bounds     ; [2] ASSERT
  ASL              ; [2] times 2 (word index)
  TAY              ; [2] as index
  LDA repl_fn+1,Y  ; [4] repl function, high byte
  PHA              ; [3] push high
  LDA repl_fn,Y    ; [4] repl function, low byte
  PHA              ; [3] push low
  RTS              ; [6] return to repl function

@immediate:
  LDX #0           ; [2]
  JSR parse_line   ; [6]
  ; execute the line immediately
  RTS              ; [6]

@haveline:         ; X = after line number
  ; save line number for bas_ins_line
  LDA Acc0         ; [3]
  STA Line         ; [3]
  LDA Acc1         ; [3]
  STA LineH        ; [3]
  BMI e_range2     ; [2]
  JSR parse_line   ; [6]
  ; copy tokenised line into place
  JMP bas_ins_line ; [3]


; @@ parse_line
; called from parse_cmd or from cmd_auto
parse_line:
  ; init bytecode write pos
  LDA #1         ; [2] after OP at [0]
  STA Ptr        ; [3] bytecode write offset (+Ptr)

  JSR skip_spc   ; [24+] leading spaces

  ; XXX this needs to use pf_stmts, recursion is allowed
  ; XXX pf_stmts needs to call pf_stmt in a loop
  ; XXX pf_stmt needs to do what this does

  ; check for alpha char
  JSR is_alpha   ; [24] returns CF=0 if alphabetic
  BCS e_stmt     ; [2] -> not a keyword (CF=1)

  ; search for a matching statement keyword
  TAY              ; [2] as an index (0-25)
  LDA stmt_tab,Y   ; [4] offset within keyword table
  LDY #>stmt_page  ; [2] stmt keyword table
  JSR scan_kw_idx  ; [6] search -> CF=1 if found, X=next-input (start-of-token if CF=0)
  BCS @stmt_found  ; [2] -> found a match
  JMP parse_var    ; [3] -> no match, must be a variable

  ; matched a statement
@stmt_found:      ; A = top-bit byte; X -> after keyword
  STA LineBuf     ; write opcode to LineBuf[0] (stmts keep top-bit)
  EOR #$80        ; clear top bit
  CMP #41         ; ASSERT
  BCS e_bounds    ; ASSERT
  TAY             ; as index
  LDA stmt_pb,Y   ; A = parse byte
  STA PtrH        ; save parse flags for parse function (+PtrH)
  AND #31         ; low 5 bits
  ASL             ; times 2 (word index)
  TAY             ; as index
  LDA stmt_fn+1,Y ; parse function, high byte
  PHA             ; push high
  LDA stmt_fn,Y   ; parse function, low byte
  PHA             ; push low
  RTS             ; return to parse function


e_bounds:
  LDY #<err_bound
  JMP pf_error

e_range2:
  LDY #<err_range
  JMP pf_error


; @@ skip_spc
; skip spaces in the input buffer
skip_spc:        ; X = input-ofs (uses A preserves Y) -> returns X
  LDA LineBuf,X  ; [4] next input char
  INX            ; [2] advance (assume match)
  CMP #32        ; [2] was it space?
  BEQ skip_spc   ; [2] -> loop [+1]
  DEX            ; [2] undo advance (didn't match)
  RTS            ; [6] return X [12+6=18]


; @@ is_alpha
is_alpha:        ; X=input-ofs (uses A, preserves X,Y) -> CF=0 if alphabetic
  LDA LineBuf,X  ; [4] next input char
  AND #$DF       ; [2] lower -> upper (clear bit 5)
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CF=1 if >= 26)
  RTS            ; [6] return CF=0 if alphabetic [12+6=18]


; @@ scan_kw_idx
; find a matching keyword in a table indexed by first letter
scan_kw_idx:       ; X=input-offset A=table-low Y=table-high
  ; find first keyword for this letter
  STA Src          ; [3] table-low
  STY SrcH         ; [3] table-high
  ; start the search  
  LDY #$FF         ; [2] search-mode: same-first-char (D7=1)
  STY Tmp3         ; [3] set mode
  INY              ; [2] word list offset (start of 1st word) = 0
  BEQ scan_kw_list ; [3] -> always

; @@ scan_kw_all
; scan a list of keywords, matching all keywords in the list.
scan_kw_all:       ; X=input-offset A=table-low Y=table-high
  STA Src          ; [3] table-low
  STY SrcH         ; [3] table-high
  LDY #0           ; [2] word list offset (start of 1st word)
  STY Tmp3         ; [3] search-mode: all-keywords (D7=0)
  ; +++ fall through to @@ scan_kw_list +++

; @@ scan_kw_list
; find a matching keyword (terminated by a byte with the top-bit set) in a zero-terminated list
; two search modes are supported: same-first-char (D7=1) or all-keywords (D7=0)
scan_kw_list:    ; X=input-ofs Y=keyword-ofs Src=keyword-list Tmp3.D7=search-mode (+Tmp2)
  STX Tmp        ; [3] save start of token (+Tmp)
  DEX            ; [2] nullify first pre-increment
  DEY            ; [2] nullify first pre-increment
@next_kw:
  LDA #0         ; [2] zero
  STA Tmp2       ; [3] dot shorthand off (zero) (Tmp2)
@match_lp:
  INX            ; [2] pre-increment input position
  INY            ; [2] pre-increment keyword position
  LDA LineBuf,X  ; [4] next input char
  EOR (Src),Y    ; [5] compare keyword char
  BEQ @match_lp  ; [2] -> yes, next char [+1]
  CMP #32        ; [2] differs only by upper/lower case? (bit 5)
  BEQ @match_en  ; [2] -> yes, enable dot, next char [+1]

  ; no match, check edge-cases
  LDA LineBuf,X  ; [4] reload input char
  BEQ @no_match  ; [2] -> end of input (check if we matched the current keyword) [+1]
  CMP #46        ; [2] dot
  BEQ @match_dot ; [2] -> check dot shorthand [+1]

  ; input char didn't match
@no_match:       ; X = offset of nonmatching character
  LDA (Src),Y    ; [5] check keyword char's top bit
  BMI @kw_found  ; [2] -> matched a keyword (top bit set) [+1]

  ; no match, skip rest of keyword (find top-bit)
@skip_lp:
  INY            ; [2] pre-increment Y
  LDA (Src),Y    ; [5] check keyword char
  BPL @skip_lp   ; [2] -> top bit clear, keep going [+1]
  INY            ; [2] skip byte with top-bit

  ; match-mode: does next keyword start with same letter / are there more keywords?
  LDX Tmp        ; [3] restore X = start of token (Tmp)
  LDA (Src),Y    ; [5] first char of next keyword
  BEQ @not_found ; [2] -> zero byte, end of list [+1]
  BIT Tmp3       ; [3] check scan_kw_list mode
  BPL @next_kw   ; [2] -> check next keyword (D7=0: all-keywords mode) [+1]
  CMP LineBuf,X  ; [3] does it match first char? (D7=1: same-first-char mode)
  BEQ @next_kw   ; [2] -> check next keyword [+1]

  ; did not find a match
@not_found:
  CLC            ; [2] clear carry: no match found
  RTS            ; [6] X = start of token

; input and keyword chars differ by case
; check if keyword is lowercase (otherwise input is lowercase!)
@match_en:       ; A = 32
  AND (Src),Y    ; is keyword lowercase? (bit 5 set)
  BEQ @no_match  ; -> keyword not lowercase (input is lowercase)
  STA Tmp2       ; [3] enable dot (A=32: non-zero) (Tmp2)
  BNE @match_lp  ; [3] always jump

; match a dot input char, if shorthand enabled
@match_dot:      ; X=next-in Y=next-kw
  LDA Tmp2       ; [3] is dot enabled for this keyword?
  BEQ @no_match  ; [3] -> not enabled (zero), didn't match input
  INX            ; [2] advance over the dot
  DEY            ; [2] for pre-inc Y below
@dot_lp:         ; advance to byte with top-bit set
  INY            ; [2] pre-inc Y
  LDA (Src),Y    ; [5] check keyword char
  BPL @dot_lp    ; [3] -> top bit clear, keep going

@kw_found:
  SEC            ; [2] set carry: keyword was found
  RTS            ; [6] X = next-character A=top-bit byte


e_range:
  LDY #<err_range
  JMP pf_error


; @@ n16_parse
; parse a 16-bit number -> {Acc0/1}, X, ZF
n16_parse:       ; from LineBuf,X returning {Acc0/1} X=end ZF=no-match (uses A,Y,Tmp)
  LDA #0         ; [2] length of num
  STA Acc0       ; [3] clear result
  STA Acc1       ; [3]
  STX Tmp        ; [3] save X to compare at end
@loop:           ; -> 14+76+25 [115]
  LDA LineBuf,X  ; [4] get next char
  SEC            ; [2]
  SBC #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS @done      ; [2] >= 10 -> @done
  TAY            ; [2] save digit 0-9
  JSR n16_mul_10 ; [12+64=76] uses A, preserves X,Y (+Acc,+Term)
  TYA            ; [2] restore digit
  CLC            ; [2]
  ADC Acc0       ; [3] add digit 0-9
  STA Acc0       ; [3]
  LDA Acc1       ; [3]
  ADC #0         ; [2] add carry
  STA Acc1       ; [3]
  BCS e_range    ; [2] -> unsigned overflow
  INX            ; [2] advance source
  JMP @loop      ; [3]
@done:
  CPX Tmp        ; [3] ZF=1 if no match
  RTS            ; [6] return X=end

; @@ n16_mul_10
; multiply {Acc0,1} by 10 (uses Term)
n16_mul_10:     ; Uses A, preserves X,Y (+Term)
  LDA Acc0      ; [3] Term = Val * 2
  ASL           ; [2]
  STA Term0     ; [3]
  LDA Acc1      ; [3]
  ROL           ; [2]
  STA Term1     ; [3]
  BCS e_range   ; [2] -> unsigned overflow
  ASL Term0     ; [5] Term *= 2 = Val * 4
  ROL Term1     ; [5]
  BCS e_range   ; [2] -> unsigned overflow
  CLC           ; [2]
  LDA Acc0      ; [3] Acc += Term = Val * 5
  ADC Term0     ; [3]
  STA Acc0      ; [3]
  LDA Acc1      ; [3]
  ADC Term1     ; [3]
  STA Acc1      ; [3]
  BCS e_range   ; [2] -> unsigned overflow
  ASL Acc0      ; [5] Acc *= 2 = Val * 10
  ROL Acc1      ; [5]
  BCS e_range   ; [2] -> unsigned overflow
  RTS           ; [6] -> [64+6]


; @@ n16_print
; print a 16-bit number {Acc0,1}
n16_print:       ; from {Acc0,1} (uses Y +Tmp)
  LDA #0
  PHA            ; sentinel
@loop:
  JSR n16_div10  ; {Acc0,1} /= 10 -> A = remainder
  ORA #48        ; 0-9 -> '0'-'9'
  PHA
  LDA Acc0
  ORA Acc1
  BNE @loop
@print:
  PLA
  BEQ @done
  JSR writechar  ; print it (A=char, preserves X,Y)
  JMP @print
@done
  RTS

; @@ n16_div10
; divide {Acc0,1} by 10, returning A = remainder (uses X) (SLOW)
; shifts dividend left into remainder
; if remainder >= 10, subtracts 10 and shifts 1 left into quotient
; else shifts 0 left into quotient
n16_div10:
  LDX #16        ; [2] 16 bits
  LDA #0         ; [2] remainder
@loop:
  ASL Acc0       ; [5] CF << dividend << 0 (quotient bit0 = 0)
  ROL Acc1       ; [5] CF << dividend << CF
  ROL A          ; [2] remainder << CF
  CMP #10        ; [2] is remainder >= divisor?
  BCS @ge10      ; [2] -> do subtraction (CF=1)  (~1/3 of the time)
  DEX            ; [2]
  BNE @loop      ; [3] -> @loop [21]
  RTS            ; [6] return A = remainder
@ge10:           ; CF=1
  SBC #10        ; [2]
  INC Acc0       ; [5] quotient bit0 = 1 (shift quotient into Acc0/1)
  DEX            ; [2]
  BNE @loop      ; [3] -> @loop [29]
  RTS            ; [6] return A = remainder [4+11*21+5*29+6 = ~386]


; @@ print_hex
; print a u16 number {Acc0,1} in hexadecimal
print_hex:      ; print Acc1,Acc0 in hex (uses A,Y, preserves X)
  LDA Acc1      ; high byte
  JSR out_hex
  LDA Acc0
  ; fall through
out_hex:
  TAY
  CLC
  LSR           ; 0 -> Acc -> C
  LSR
  LSR
  LSR
  CMP #10
  BCC ok1       ; if < 10 -> skip (C=0)
  ADC #6        ; 'A'-10-48-(C=1)
ok1:
  ADC #48       ; add '0'
  JSR writechar ; output char to screen (A=char, preserves X,Y)
  TYA
  AND #15
  CMP #10
  BCC ok2       ; if < 10 -> skip (C=0)
  ADC #6        ; 'A'-10-48-(C=1)
ok2:
  ADC #48       ; add '0'
  JMP writechar ; output char to screen (A=char, preserves X,Y)


parse_var:       ; X -> start of token (1st char is alpha)
@loop:
  INX            ; [2] next char
  LDA LineBuf,X  ; [4] next input char
  AND #$DF       ; [2] lower -> upper (clear bit 5)
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters
  BCC @loop      ; [2] is a letter -> @loop [+1]
  STX Tmp2       ; [3] save end of token
  JSR skip_spc   ; [24+]
  LDA LineBuf,X  ; [4] next input char
  CMP #$3D       ; [2] is it '='?
  BEQ @let       ; [2] -> LET name = <expr> [+1]
  JMP e_stmt     ; [3]
@let:
  INX            ; [2]
  JSR pf_expr    ; [6] parse expr
  LDY #<err_var
  JMP pf_error


e_expect:         ; A = expected character
  STA Tmp         ; save char
  LDY #<msg_expecting
  JSR printmsg    ; Y=low (uses A,X,Y,Src)
  LDA Tmp         ; restore char
  JSR writechar
  JSR newline
  JMP repl

e_expect_kw:      ; Tmp = keyword (low byte) in kwtab
  LDY #<msg_expecting
  JSR printmsg    ; Y=low (uses A,X,Y,Src)
  LDY Tmp         ; keyword offset
  JSR printkw     ; Y=offset (uses A,Src)
  JMP repl

printkw:          ; 13 bytes
  LDA kwtab,Y     ; [4] first char
@loop:
  JSR writechar   ; [6] print char (A=char, preserves X,Y)
  INY             ; [2] advance
  LDA kwtab,Y     ; [4] load next char
  BPL @loop       ; [3] until top-bit is set
  RTS             ; [6] done

; KEYWORD parse-function table
; matches stmt_pb "parse function" entries
; no special alignment requirements
stmt_fn:             ; [41]
  DW pfs_for      -1 ;  0 = FOR .. TO .. [ STEP .. ]
  DW pfs_if       -1 ;  1 = IF .. THEN .. [ ELSE .. ]
  DW pfs_print    -1 ;  2 = PRINT .. SPC .. TAB .. ~';
  DW pfs_varlist  -1 ;  3 = var-list .. A,B
  DW pfs_fim      -1 ;  4 = DIM .. A(n,..)
  DW pfs_data     -1 ;  5 = DATA .. , .. (up to 255)
  DW pfs_num      -1 ;  6 = num stmt, uses NN
  DW pfs_def      -1 ;  7 = DEF .. FN|PROC name (a,b..)
  DW pfs_cond     -1 ;  8 = condition
  DW pfs_else     -1 ;  9 = ELSE
  DW pfs_envelope -1 ; 10 = ENVELOPE (14 args)
  DW pfs_proc     -1 ; 11 = PROC
  DW pfs_let      -1 ; 12 = LET .. var = ..
  DW pfs_on       -1 ; 13 = ON .. ERROR|num .. GOTO|GOSUB .. ELSE
  DW pfs_rem      -1 ; 14 = REM ..
  DW pfs_onoff    -1 ; 15 = on-off
  DW pfs_str      -1 ; 16 = str stmt, uses NN
  DW pfs_hash     -1 ; 17 = # stmt

; X = input line offset
; PtrH = parse flags for parse function
; Ptr = bytecode write pos in LineBuf (=1)
; LineBuf[0] = OPCode for stmt

; Pack ?a,8,c -> [OP_PRINT][FVar1][1Ofs][Int8][08][FVar1][1Ofs]
; 1Ofs -> [Base][1Ofs]
; 2Ofs -> [Base+2Ofs][1Ofs]

OP_STEP = 1
OP_ELSE = 2
OP_GOTO = 3

pfs_for:
  ; var "=" iexpr "TO" iexpr [ "STEP" iexpr ]
  JSR pf_var     ; parse var
  JSR skip_spc   ; [24+]
  LDA #61        ; "="
  CMP LineBuf,X  ; next char
  BNE e_expect
  JSR pf_expr    ; parse expr
  LDY #<kw_to    ; "TO"
  JSR match_kw   ; uses A,X,Y (Tmp=Y) -> CF,X
  BCS e_expect_kw ; -> expecting TO (Tmp=kw_to)
  JSR pf_expr    ; parse expr
  LDY #<kw_step  ; "STEP"
  JSR match_kw   ; uses A,X,Y (Tmp=Y) -> CF,X
  BCS @done      ; -> no STEP
  LDA #OP_STEP   ; write OP_STEP
  JSR pf_opcode
  JSR pf_expr    ; parse expr  
@done:
  RTS

pfs_if:
  ; expr "THEN" line|stmt* [ "ELSE" line|stmt* ]
  JSR pf_expr    ; parse expr
  LDY #<kw_then  ; "THEN"
  JSR match_kw   ; uses A,X,Y (Tmp) -> CF,X
  BCS @no_then   ; -> allow stmts, but not line no
  JSR n16_parse  ; [12+] parse line number -> {Acc0/1}, X, EQ=no (uses A,Y,Tmp)
  BNE @then_line ; [2] -> found line number
@no_then:
  JSR pf_stmts   ; parse statements
@if_else:
  LDY #<kw_else  ; "ELSE"
  JSR match_kw   ; uses A,X,Y (Tmp) -> CF,X
  BCS @done      ; -> no ELSE
  LDA #OP_ELSE   ; write OP_ELSE
  JSR pf_opcode
  JSR n16_parse  ; [12+] parse line number -> {Acc0/1}, X, EQ=no (uses A,Y,Tmp)
  BNE @else_line ; [2] -> found line number
  JSR pf_stmts   ; parse statements
@done:
  RTS
@then_line:
  LDA #OP_GOTO   ; write OP_GOTO
  JSR pf_opcode
  JSR pf_line    ; write line number (find in index at runtime?)
  JMP @if_else
@else_line:
  LDA #OP_GOTO   ; write OP_GOTO
  JSR pf_opcode
  JSR pf_line    ; write line number (find in index at runtime?)
  RTS

pfs_print:
  ; { "str" | TAB() | SPC() | expr | ' } [;|,]
  RTS

pfs_varlist:
  RTS
pfs_fim:
  RTS
pfs_data:
  RTS
pfs_num:
  RTS
pfs_def:
  RTS
pfs_cond:
  RTS
pfs_else:
  RTS
pfs_envelope:
  RTS
pfs_proc:
  RTS
pfs_let:
  RTS
pfs_on:
  RTS
pfs_rem:
  RTS
pfs_onoff:
  RTS
pfs_str:
  RTS
pfs_hash:
  RTS


; Common parser functions
; these directly output opcodes to LineBuf+Ptr

pf_var:
  JSR skip_spc  ; [24+]
  RTS

pf_expr:
  JSR skip_spc  ; [24+]
  RTS

pf_stmts:
  JSR skip_spc  ; [24+]
  RTS

match_kw:        ; Y = keyword low byte (on kwtab page)
  STY Tmp        ; for e_expect_kw (error case)
  JSR skip_spc  ; [24+] uses A (preserves Y) -> X
  ; XXX compare it
  SEC            ; CF=1 means not found
  RTS

pf_opcode:       ; A=opcode (preserves X)           [XXX replace with DMA write]
  LDY Ptr        ; bytecode write pos in LineBuf
  STA LineBuf,Y  ; append the opcode
  INC Ptr        ; advance output pos
  RTS

; XXX do these dynamic-bind and set a bit somewhere?
pf_line:
  LDY Ptr        ; bytecode write pos in LineBuf
  LDA Acc0       ; low byte
  STA LineBuf,Y  ; append the opcode
  INY
  LDA Acc1       ; low byte
  STA LineBuf,Y  ; append the opcode
  INY
  STY Ptr
  RTS

bas_ins_line:
  RTS


; current version uses 6 bytes
pf_error:         ; Y = low byte (in messages page)
  JSR printmsg    ; Y=low
  JMP repl

; to be a win, this needs to be smaller than adding a length byte
; to every message in messages (25-6 = 19 messages)
;pf_error2:       ; Y=msg-ofs in messages page
;  LDA messages,Y ; first char can be uppercase, print unconditionally
;@loop
;  JSR writechar  ; A=char (preserves X,Y)
;  INY
;  LDA messages,Y
;  CMP #97        ; 'a'
;  BCS @loop      ; >= 97 (loop while lowercase)
;  ORA #32        ; set bit 5 (to lowercase)
;  JSR writechar
;  JSR newline
;  JMP repl


; REPL handler table
; matches repl_tab entries
; no special alignment requirements
repl_fn:             ; 9 entries (repl_len)
  DW cmd_list     -1 ;
  DW cmd_run      -1 ;
  DW cmd_auto     -1 ;
  DW cmd_renum    -1 ;
  DW cmd_delete   -1 ;
  DW cmd_load     -1 ;
  DW cmd_save     -1 ;
  DW cmd_new      -1 ;
  DW cmd_old      -1 ;

cmd_list:
  RTS

cmd_run:
  RTS

cmd_auto:
  LDA #10            ; [2]
  STA Line           ; [3] start from line 10
  STA Tmp4           ; [3] step by 10
  LDA #0             ; [2]
  STA LineH          ; [3]
  JSR skip_spc       ; [6] uses A (preserves Y) -> X
  JSR n16_parse      ; [6] parse number at LineBuf,X -> {Acc0/1}, X, EQ=no (uses A,Y,Tmp)
  BEQ @loop          ; [2] -> no number [+1]
  LDA Acc0           ; [3]
  STA Line           ; [3] set start line
  LDA Acc1           ; [3]
  STA LineH          ; [3]
  JSR skip_spc       ; [6] uses A (preserves Y) -> X
  LDA LineBuf,X      ; [4]
  CMP #$2C           ; [2] comma
  BNE @loop          ; [2] -> no comma
  JSR skip_spc       ; [6] uses A (preserves Y) -> X
  JSR n16_parse      ; [6] parse number at LineBuf,X -> {Acc0/1}, X, EQ=no (uses A,Y,Tmp)
  BEQ @loop          ; [2] -> no number [+1]
  LDA Acc0           ; [3]
  STA Tmp4           ; [3]
  BEQ @range         ; [2] -> bad step (equals zero)
  LDA Acc1           ; [3]
  BNE @range         ; [2] -> bad step (non-zero high byte)
@loop:
  ; print the line number
  LDA Line
  STA Acc0
  LDA LineH
  STA Acc1
  JSR n16_print     ; assumes text mode
  LDA #32
  JSR writechar     ; assumes text mode
  ; read an input line
  JSR readline      ; assumes text mode
  JSR newline       ; assumes text mode
  ; parse and tokenise the line
  LDX #0
  JSR parse_line    ; corrupts text mode; returns CF=valid?
  ; copy tokenised line into place
  JSR bas_ins_line
  ; increment line number
  CLC
  LDA Tmp4
  ADC Line          ; add step
  STA Line
  BCC @loop         ; -> no carry
  INC LineH
  BNE @loop         ; -> unless zero
@range:
  JMP e_range

cmd_renum:
  RTS

cmd_delete:
  RTS

cmd_load:
  RTS

cmd_save:
  RTS

cmd_new:
  RTS

cmd_old:
  RTS



; ------------------------------------------------------------------------------
; STATEMENT KEYWORDS - MUST be page aligned (Y indexing)
ALIGN ROM+$500
stmt_page:

kws_a:
kws_b:
  DB "BPUT",$80
kws_c:
  DB "COLOR",$81
  DB "COLOUR",$81
  DB "CALL",$82
  DB "CLEAR",$83
  DB "CLS",$84
  DB "CLOSE",$85
kws_d:
  DB "DATA",$86
  DB "DRAW",$87
  DB "DIM",$88
  DB "DEF",$89
kws_e:
  DB "ELSE",$8A
  DB "ENVELOPE",$8B
  DB "END",$8C
kws_f:
  DB "FOR",$8D
kws_g:
  DB "GOTO",$8E
  DB "GOSUB",$8F
kws_h:
kws_i:
  DB "IF",$90
  DB "INPUT",$91
kws_j:
kws_k:
kws_l:
  DB "LET",$92
  DB "LOCAL",$93
kws_m:
  DB "MOVE",$94
  DB "MODE",$95
kws_n:
  DB "NEXT",$96
kws_o:
  DB "ON",$97
  DB "OPT",$98
  DB "OPEN",$99
kws_p:
  DB "PRINT",$9A
  DB "PLOT",$9B
  DB "PLAY",$9C
  DB "PROC",$9D
kws_q:
kws_r:
  DB "READ", $9E
  DB "REPEAT",$9F
  DB "RECTANGLE",$A0
  DB "RESTORE",$A1
  DB "RETURN",$A2
  DB "REM",$A3
  DB "REPORT",$A4
kws_s:
kws_t:
  DB "TRIANGLE",$A5
  DB "TRACE",$A6
kws_u:
  DB "UNTIL",$A7
kws_v:
kws_w:
  DB "WAIT",$A8
kws_x:
kws_y:
kws_z:
  DB 0


; in specific OPERATOR contexts: THEN, ELSE, TO, STEP
; in print contexts: SPC, TAB

; ------------------------------------------------------------------------------
; EXPRESSION KEYWORDS - MUST be page aligned (Y indexing)
ALIGN $100
expr_page:

expr_a:
  DB "AND",$80      ; kw oper (4)
  DB "ABS",$81      ; fn (0,0)
  DB "ACS",$82      ; fn (0,0)
  DB "ASC",$83      ; fn (0,0)
  DB "ASN",$84      ; fn (0,0)
  DB "ATN",$85      ; fn (0,0)
expr_b:
  DB "BGET",$86     ; # function (2,0)
expr_c:
  DB "CHR",$87      ; fn$ (1,1)
  DB "COS",$88      ; fn (0,1)
expr_d:
  DB "DEG",$89      ; fn (0,1)
  DB "DIV",$8A      ; kw oper (4)
expr_e:
  DB "EOR",$8B      ; kw oper (4)
  DB "EXP",$8C      ; fn (0,1)
  DB "EOF",$8D      ; # function (2,0)
  DB "ERR",$8E      ; no-arg (0,0)
  DB "ERL",$8F      ; no-arg (0,0)
  DB "EVAL",$90     ; eval$ (1,1)
expr_f:
  DB "FALSE",$91    ; no-arg (0,0)
  DB "FN",$92       ; function-call (9)
expr_g:
  DB "GET",$93      ; fn-or-fn$ (8,0)
expr_h:
expr_i:
  DB "INKEY",$94    ; fn-or-fn$ (8,1) 1st is $
  DB "INSTR",$95    ; fn$ (1,1) 1st is $
  DB "INT",$96      ; fn (0,1)
expr_j:
expr_k:
expr_l:
  DB "LEN",$97      ; fn-or-fn# (B,1) 1st is $
  DB "LEFT",$98     ; fn$ (1,2) 1st is $
  DB "LN",$99       ; fn (0,1)
  DB "LOG",$9A      ; fn (0,1)
expr_m:
  DB "MID",$9B      ; fn$ (1,3) 1st is $
  DB "MOD",$9C      ; kw oper (4,1)
expr_n:
  DB "NOT",$9D      ; kw oper (5)
expr_o:
  DB "OR",$9E       ; kw oper (4)
expr_p:
  DB "POINT",$9F    ; fn (0,2)
  DB "POS",$A0      ; fn-or-fn# (B,0)
  DB "PI",$A1       ; no-arg (0,0)
expr_q:
expr_r:
  DB "RIGHT",$A2    ; fn$ (1,2) 1st is $
  DB "RAD",$A3      ; fn (0,1)
  DB "RND",$A4      ; fn (0,1)
expr_s:
  DB "STR",$A5      ; fn$ (1,1) 1st is $
  DB "SIN",$A6      ; fn (0,1)
  DB "SQR",$A7      ; fn (0,1)
  DB "STRING",$A8   ; fn$ (1,2) 1st is $
  DB "SGN",$A9      ; fn (0,1)
expr_t:
  DB "TAN",$AA      ; fn (0,1)
  DB "TRUE",$AB     ; no-arg (0,0)
  DB "TIME",$AC     ; no-arg (0,0)
  DB "TOP",$AD      ; no-arg (0,0)
expr_u:
  DB "USR", $AE     ; fn (0,1)
expr_v:
  DB "VAL",$AF      ; fn (0,1)
  DB "VPOS",$B0     ; no-arg (3,0)
expr_w:
expr_x:
expr_y:
expr_z:
  DB 0

; context keywords (keep on one page for Y indexing)
kwtab:
kw_to:
  DB "TO", $80
kw_step:
  DB "STEP", $80
kw_then:
  DB "THEN", $80
kw_else:
  DB "ELSE", $80


; ------------------------------------------------------------------------------
; TABLES - MUST be page aligned (Y indexing)
ALIGN $100

; Command list for the repl
; matches repl_fn table
repl_len = 9
repl_tab:
  DB "LIST",$80
  DB "RUN",$81
  DB "AUTO",$82
  DB "RENUMBER",$83
  DB "DELETE",$84
  DB "LOAD",$85
  DB "SAVE",$86
  DB "NEW",$87
  DB "OLD",$88
  DB 0

; STATEMENT KEYWORDS
stmt_tab:
  DB (kws_a - stmt_page) ; A
  DB (kws_b - stmt_page) ; B
  DB (kws_c - stmt_page) ; C
  DB (kws_d - stmt_page) ; D
  DB (kws_e - stmt_page) ; E
  DB (kws_f - stmt_page) ; F
  DB (kws_g - stmt_page) ; G
  DB (kws_h - stmt_page) ; H
  DB (kws_i - stmt_page) ; I
  DB (kws_j - stmt_page) ; J
  DB (kws_k - stmt_page) ; K
  DB (kws_l - stmt_page) ; L
  DB (kws_m - stmt_page) ; M
  DB (kws_n - stmt_page) ; N
  DB (kws_o - stmt_page) ; O
  DB (kws_p - stmt_page) ; P
  DB (kws_q - stmt_page) ; Q
  DB (kws_r - stmt_page) ; R
  DB (kws_s - stmt_page) ; S
  DB (kws_t - stmt_page) ; T
  DB (kws_u - stmt_page) ; U
  DB (kws_v - stmt_page) ; V
  DB (kws_w - stmt_page) ; W
  DB (kws_x - stmt_page) ; X
  DB (kws_y - stmt_page) ; Y
  DB (kws_z - stmt_page) ; Z

; STATEMENT parse bytes: [FNNPPPPP]
; F - flag for parse function
; NN - number of arguments
; PPPPP - parse function:
;  0 = FOR .. TO .. [ STEP .. ]
;  1 = IF .. THEN .. [ ELSE .. ]
;  2 = PRINT .. SPC .. TAB .. ~';
;  3 = var-list .. A,B
;  4 = DIM .. A(n,..)
;  5 = DATA .. , .. (up to 255)
;  6 = num stmt, uses NN
;  7 = DEF .. FN|PROC name (a,b..)
;  8 = condition
;  9 = ELSE
; 10 = ENVELOPE (14 args)
; 11 = PROC
; 12 = LET .. var = ..
; 13 = ON .. ERROR|num .. GOTO|GOSUB .. ELSE
; 14 = REM ..
; 15 = on-off
; 16 = str stmt, uses NN
; 17 = # stmt
stmt_pb:           ; [41]
  DB 17+(2<<5)     ; "BPUT",$80      # stmt (7,2)
  DB 6+(1<<5)      ; "COLOR",$81     num stmt (6,1)
  DB 6+(1<<5)+$80  ; "CALL",$82      num stmt (6,1+) XXX F also means optional
  DB 6             ; "CLEAR",$83     num stmt (6,0)
  DB 6             ; "CLS",$84       num stmt (6,0)
  DB 17+(2<<5)     ; "CLOSE",$85     # stmt (7,2)
  DB 5             ; "DATA",$86      data (5)
  DB 6+(2<<5)      ; "DRAW",$87      num stmt (6,2)
  DB 4             ; "DIM",$88       dim (4)
  DB 7             ; "DEF",$89       def (7)
  DB 9             ; "ELSE",$8A      else (9)
  DB 10            ; "ENVELOPE",$8B  envelope (10)
  DB 6             ; "END",$8C       num stmt (6,0)
  DB 0             ; "FOR",$8D       for (0)
  DB 6+(1<<5)      ; "GOTO",$8E      num stmt (6,1)
  DB 6+(1<<5)      ; "GOSUB",$8F     num stmt (6,1)
  DB 1             ; "IF",$90        if (1)
  DB 2+$80         ; "INPUT",$91     print (2 N=1)
  DB 12            ; "LET",$92       let (12)
  DB 3             ; "LOCAL",$93     var-list (3 N=0)
  DB 6+(2<<5)      ; "MOVE",$94      num stmt (6,2)
  DB 6+(1<<5)      ; "MODE",$95      num stmt (6,1)
  DB 3+$80         ; "NEXT",$96      var-list (3 N=1) with indices
  DB 13            ; "ON",$97        on (13)
  DB 6+(2<<5)      ; "OPT",$98       num stmt (6,2)
  DB 16+(1<<5)     ; "OPEN",$99      str stmt (5,1)
  DB 2             ; "PRINT",$9A     print (2 N=0)
  DB 6+(2<<5)      ; "PLOT",$9B      num stmt (6,2)
  DB 6             ; "PLAY",$9C      num stmt (6,?) XXX
  DB 11            ; "PROC",$9D      proc (11)
  DB 3+$80         ; "READ", $9E     var-list (3 N=1) with indices
  DB 6             ; "REPEAT",$9F    num stmt (6,0)
  DB 6+(2<<5)      ; "RECTANGLE",$A0 num stmt (6,2)
  DB 6+(1<<5)+$80  ; "RESTORE",$A1   num stmt (6,1 F=1) optional arg
  DB 6             ; "RETURN",$A2    num stmt (6,0)
  DB 14            ; "REM",$A3       rem (14)
  DB 6             ; "REPORT",$A4    num stmt (6,0)
  DB 6+(2<<5)      ; "TRIANGLE",$A5  num stmt (6,2)
  DB 15            ; "TRACE",$A6     on-off (15)
  DB 8             ; "UNTIL",$A7     condition (8)
  DB 6             ; "WAIT",$A8      num stmt (6,0)

; EXPRESSION KEYWORDS
expr_tab:
  DB (expr_a - expr_page) ; A
  DB (expr_b - expr_page) ; B
  DB (expr_c - expr_page) ; C
  DB (expr_d - expr_page) ; D
  DB (expr_e - expr_page) ; E
  DB (expr_f - expr_page) ; F
  DB (expr_g - expr_page) ; G
  DB (expr_h - expr_page) ; H
  DB (expr_i - expr_page) ; I
  DB (expr_j - expr_page) ; J
  DB (expr_k - expr_page) ; K
  DB (expr_l - expr_page) ; L
  DB (expr_m - expr_page) ; M
  DB (expr_n - expr_page) ; N
  DB (expr_o - expr_page) ; O
  DB (expr_p - expr_page) ; P
  DB (expr_q - expr_page) ; Q
  DB (expr_r - expr_page) ; R
  DB (expr_s - expr_page) ; S
  DB (expr_t - expr_page) ; T
  DB (expr_u - expr_page) ; U
  DB (expr_v - expr_page) ; V
  DB (expr_w - expr_page) ; W
  DB (expr_x - expr_page) ; X
  DB (expr_y - expr_page) ; Y
  DB (expr_z - expr_page) ; Z

; EXPRESSION parse bytes: [FNNPPPPP]
; F - flags for parse function
; NN - number of arguments (or more flags)
; PPPPP - parser index:
;  0 = () function, uses NN
;  1 = $() function, uses NN
;  2 = # function, uses NN
;  3 = no-arg
;  4 = keyword operator (AND OR)
;  5 = NOT
;  6 = func() or func#()
;  7 = const or const#
;  8 = fn-or-fn$ ()
;  9 = function-call ()
;  B = str fn# ()
; XXX returns $ vs takes $ argument
expr_pb:           ; [49]
  DB 4             ; "AND",$80      kw oper (4)
  DB 0+(1<<5)      ; "ABS",$81      fn (0,0)
  DB 0+(1<<5)      ; "ACS",$82      fn (0,0)
  DB 0+(1<<5)      ; "ASC",$83      fn (0,0)
  DB 0+(1<<5)      ; "ASN",$84      fn (0,0)
  DB 0+(1<<5)      ; "ATN",$85      fn (0,0)
  DB 2             ; "BGET",$86     # function (2,0)
  DB 1+(1<<5)      ; "CHR",$87      fn$ (1,1)
  DB 0+(1<<5)      ; "COS",$88      fn (0,1)
  DB 0+(1<<5)      ; "DEG",$89      fn (0,1)
  DB 4             ; "DIV",$8A      kw oper (4)
  DB 4             ; "EOR",$8B      kw oper (4)
  DB 0+(1<<5)      ; "EXP",$8C      fn (0,1)
  DB 2             ; "EOF",$8D      # function (2,0)
  DB 0             ; "ERR",$8E      no-arg (0,0)
  DB 0             ; "ERL",$8F      no-arg (0,0)
  DB 0+(1<<5)      ; "EVAL",$90     eval (1,1)
  DB 0             ; "FALSE",$91    no-arg (0,0)
  DB 9             ; "FN",$92       function-call (9)
  DB 8             ; "GET",$93      fn-or-fn$ (8,0)
  DB 8+(1<<5)      ; "INKEY",$94    fn-or-fn$ (8,1) 1st is $
  DB 1+(1<<5)      ; "INSTR",$95    fn$ (1,1) 1st is $
  DB 0+(1<<5)      ; "INT",$96      fn (0,1)
  DB 11+(1<<5)     ; "LEN",$97      fn-or-fn# (B,1) 1st is $
  DB 1+(2<<5)      ; "LEFT",$98     fn$ (1,2) 1st is $
  DB 0+(1<<5)      ; "LN",$99       fn (0,1)
  DB 0+(1<<5)      ; "LOG",$9A      fn (0,1)
  DB 1+(3<<5)      ; "MID",$9B      fn$ (1,3) 1st is $
  DB 4             ; "MOD",$9C      kw oper (4,1)
  DB 4             ; "NOT",$9D      kw oper (5)
  DB 4             ; "OR",$9E       kw oper (4)
  DB 0+(2<<5)      ; "POINT",$9F    fn (0,2)
  DB 11            ; "POS",$A0      fn-or-fn# (B,0)
  DB 0             ; "PI",$A1       no-arg (0,0)
  DB 1+(2<<5)      ; "RIGHT",$A2    fn$ (1,2) 1st is $
  DB 0+(1<<5)      ; "RAD",$A3      fn (0,1)
  DB 0+(1<<5)      ; "RND",$A4      fn (0,1)
  DB 1+(1<<5)      ; "STR",$A5      fn$ (1,1) 1st is $
  DB 0+(1<<5)      ; "SIN",$A6      fn (0,1)
  DB 0+(1<<5)      ; "SQR",$A7      fn (0,1)
  DB 1+(2<<5)      ; "STRING",$A8   fn$ (1,2) 1st is $
  DB 0+(1<<5)      ; "SGN",$A9      fn (0,1)
  DB 0+(1<<5)      ; "TAN",$AA      fn (0,1)
  DB 0             ; "TRUE",$AB     no-arg (0,0)
  DB 0             ; "TIME",$AC     no-arg (0,0)
  DB 0             ; "TOP",$AD      no-arg (0,0)
  DB 0+(1<<5)      ; "USR", $AE     fn (0,1)
  DB 0+(1<<5)      ; "VAL",$AF      fn (0,1)
  DB 0             ; "VPOS",$B0     no-arg (3,0)



; ------------------------------------------------------------------------------
; PAGE 8 - INTERPRETER
ORG ROM+$800 ; 2K

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

ar_ivar:         ; read an integer variable  (XXX unify these, always copy 5 bytes)
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
; PAGE 9

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
  LDA Acc3       ; [3]
  PHA            ; [3] push low byte
  LDA Acc2       ; [3]
  PHA            ; [3] push byte 1
  LDA Acc1       ; [3]
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




; ------------------------------------------------------------------------------
; PAGE 10 - SYSTEM
ORG ROM+$1000 ; 4K

; @@ key_scan
; scan the keyboard matrix for a keypress
; [..ABCDE....]
;    ^hd  ^tl     ; empty when hd==tl, full when tl+1==hd
keyscan:          ; uses A,X,Y returns nothing (CANNOT use normal Tmp)
  LDY #8          ; [2] last key column
  STY IO_KEYB     ; [3] set keyscan column (0-7)
  LDA IO_KEYB     ; [3] read key state bitmap
  STA ModKeys     ; [3] update modifier keys
  DEY             ; [2] prev column
; debounce check
  CMP IO_KEYB     ; [3] check if stable (3+2+3)/2MHz=4µs later
  BNE keyscan     ; [2] if not -> try again
@col_lp:          ; -> [13] cycles
  STY IO_KEYB     ; [3] set keyscan column (0-7)
  LDX IO_KEYB     ; [3] read key state bitmap
  BNE @key_hit    ; [2] -> one or more keys pressed [+1]
  DEY             ; [2] prev column
  BPL @col_lp     ; [3] go again, until Y<0
  STY LastKey     ; [3] no keys pressed: clear last key pressed (to $FF)
  RTS             ; [6] TOTAL Scan 2+13*8-1+6 = [111] cycles
@key_hit:         ; X=bitmap Y=column
  STY IRQTmp      ; [3] save keyscan column for resuming later
  TYA             ; [2] active keyscan column
  ASL             ; [2] column * 8
  ASL             ; [2] 
  ASL             ; [2] 
; debounce check 
  CPX IO_KEYB     ; [3] check if stable 17/2Mhz = 8.5µs later
  BNE @col_lp     ; [2] if not -> try again
  TAY             ; [2] scantab offset = col*8 as index
  TXA             ; [2] key state bitmap
; find first bit set
; loop WILL terminate because A is non-zero!
@bsf_lp:          ; A=bitmap Y=scantab -> [7] cycles
  INY             ; [2] count number of shifts
  ASL A           ; [2] shift keys bits left into CF
  BCC @bsf_lp     ; [3] until CF=1
; translate to ascii
  BIT ModKeys     ; [3] test shift key [N=Esc][V=Shf]
  BVS @shift      ; [2] -> shift is down (bit 6)
  TAX             ; [2] save remaining bitmap
  LDA scantab-1,Y ; [4] translate to ASCII (Y is off by +1)
@shft_ret:
  CMP LastKey     ; [3] one-key roll over
  BEQ @cont_scan  ; [2] keep scanning (XXX go check timer, auto-repeat)
  STA LastKey     ; [3] save last key pressed
; append to keyboard buffer
  LDY KeyTl       ; [3] keyboard buffer write offset
  STA KeyBuf,Y    ; [4] always safe to write at KeyTl
  INY             ; [2] increment
  TYA             ; [2]
  AND #15         ; [2] modulo circular buffer
  CMP KeyHd       ; [3] is Tl+1 == Hd ?
  BEQ @full       ; [2] -> key buffer is full (don't update KeyTl)
  STA KeyTl       ; [3] update Tl = Tl+1 % 32
@full:
  RTS             ; [6] done
@shift:
  LDA scanshf-1,Y ; [4] translate to ASCII (Y is off by +1)
  BPL @shft_ret   ; [3] top bit is never set!!
@cont_scan:
  RTS             ; XXXXX debug
  TXA             ; [2] restore bitmap
  BNE @bsf_lp     ; [3] -> continue bsf loop
  LDY IRQTmp      ; [3] restore keyscan column
  BNE @col_lp     ; [3] -> continue scanning key columns
  STY LastKey     ; [3] no keys pressed: clear last key pressed (to $00)
  RTS             ; [6] done

; keymap tables
; must be within a page to avoid boundary cross (uses 2x64 = 128 bytes)

;   Esc 1 2 3 4 5 6 7 (0)  8 9 0 - = ` Del Up    (4)
;   Tab Q W E R T Y U (1)  I O P [ ] \     Down  (5)
;  Caps A S D F G H J (2)  K L ; '     Ret Left  (6)
;       Z X C V B N M (3)  , . /       Spc Right (7)
;   Shf Ctl Fn                                   (8)
scantab:
  DB  $1B, $31, $32, $33, $34, $35, $36, $37     ;   Esc 1 2 3 4 5 6 7
  DB  $09, $71, $77, $65, $72, $74, $79, $75     ;   Tab q w e r t y u
  DB  $0E, $61, $73, $64, $66, $67, $68, $6A     ;  Caps a s d f g h j
  DB  $00, $7A, $78, $63, $76, $62, $6E, $6D     ;       z x c v b n m
  DB  $38, $39, $30, $2D, $3D, $60, $08, $8B     ;     8 9 0 - = ` Del Up
  DB  $69, $6F, $70, $5B, $5D, $5C, $00, $8A     ;     i o p [ ] \     Down
  DB  $6B, $6C, $3B, $27, $00, $00, $0D, $88     ;     k l ; '     Ret Left
  DB  $2C, $2E, $2F, $00, $00, $00, $20, $89     ;     , . /       Spc Right
scanshf:
  DB  $1B, $21, $40, $23, $24, $25, $5E, $26     ;   Esc ! @ # $ % ^ &
  DB  $09, $51, $57, $45, $52, $54, $59, $55     ;   Tab Q W E R T Y U
  DB  $0E, $41, $53, $44, $46, $47, $48, $4A     ;  Caps A S D F G H J
  DB  $00, $5A, $58, $43, $56, $42, $4E, $4D     ;       Z X C V B N M
  DB  $2A, $28, $29, $5F, $2B, $7E, $08, $8B     ;     * ( ) _ + ~ Del Up
  DB  $49, $4F, $50, $7B, $7D, $7C, $00, $8A     ;     I O P { } |     Down
  DB  $4B, $4C, $3A, $22, $00, $00, $0D, $88     ;     K L : "     Ret Left
  DB  $3C, $3E, $3F, $00, $00, $00, $20, $89     ;     < > ?       Spc Right

; @@ readchar
; read a single character from the keyboard buffer
; AUTO-REPEAT: the last key held (save its scancode to compare)
; ROLLOVER: pressing a new key replaces the prior held key
; INKEY(-K): directly scans the key (high 5:col low 3:row)
readchar:        ; uses A,X,Y returns ASCII or zero (!Tmp)
  ; JSR keyscan    ; scan keyboard, fill buffer     (XXX move to VSync interrupt)
  LDX KeyHd      ; [3] load keyboard buffer head
  CPX KeyTl      ; [3] Hd == Tl -> empty, @wait
  BEQ @nokey     ; [2] buffer is empty
  LDY KeyBuf,X   ; [4] next buffered key
  INX            ; [2] inc keyboard buffer head
  TXA            ; [2]
  AND #15        ; [2] modulo circular buffer
  STA KeyHd      ; [3] save new head
  TYA            ; [2]
  RTS            ; [6] -> return A (ZF)
@nokey:
  LDA #0         ; [2] return 0
  RTS            ; [6]


; ------------------------------------------------------------------------------
; WRITECHAR, PRINT

; @@ writechar
; write a single character to the screen
; assumes we're in "text mode" with DMA DST set up
writechar:       ; A=char; preserves X,Y [25]
  CMP #32        ; [2] is it a control character?
  BCC wrctrl     ; [2] if <32 -> execute control code and return [+1]
  STA IO_DDRW    ; [3] write tile byte to VRAM
  LDA Color      ; [2] current text color (16-color mode)
  STA IO_DDRW    ; [3] write attribte byte to VRAM
  DEC WinRem     ; [5] at right edge of window?
  BEQ newline    ; [2] if so -> newline [+1]
  RTS            ; [6]

; @@ newline, in "text mode"
; advance to the next line inside the text window
; scroll the text window if we're at the bottom
; DMA is already set up (DST*) for "text mode"
newline:         ; uses A, preserves X,Y
  LDA WinRem     ; [3] current WinRem
  CLC            ; [2]
  ADC #64        ; [2] advance = 64 - (WinW - WinRem) = WinRem + 64 - WinW
  SEC            ; [2]
  SBC WinW       ; [3]
  CLC            ; [2]
  ASL A          ; [2] A*2 for (text,attr) pairs [CF=1 if A >= 128]
  CLC            ; [2]
  ADC IO_DSTL    ; [3] add destination low (may set CF=1)
  STA IO_DSTL    ; [3] set destination low
  BCC @nohi      ; [2] CF=0, did not cross a page boundary [+1]
  INC IO_DSTH    ; [5] CF=1, increment destination high
@nohi:           ; 
  LDA WinW       ; [3] reset remaining window width
  STA WinRem     ; [3] must be ready to write in steady-state
  RTS            ; [6]

; @@ wrctrl, in "text mode"
; write a single control code
wrctrl:          ; uses A, preserves X,Y
  CMP #13        ; [2] is it RETURN?
  BEQ newline    ; [2] -> do newline and return [+1]
  CMP #8         ; [2] is it BACKSPACE?
  BEQ @backsp    ; [2] -> do backspace and return [+1]
  RTS            ; [6]
@backsp:         ; go back one cell and clear it
  LDA WinRem     ; [3] remaining space
  CMP WinW       ; [3] window width
  BEQ @back_sol  ; [2] equal -> at start of the line [+1]
  INC WinRem     ; [5] give back one character
  ; only correct if we're not at the left edge:
  DEC IO_DSTL    ; [5] cannot wrap (within an aligned span of 128)
  DEC IO_DSTL    ; [5] cannot wrap (as above)
  LDA #32        ; [3] space character
  STA IO_DDRW    ; [3] only to decrement the address!
  LDA Color      ; [2] current text color (16-color mode)
  STA IO_DDRW    ; [3] write attribute (reverse dir)
  DEC IO_DSTL    ; [5] cannot wrap (redoing the above decrements)
  DEC IO_DSTL    ; [5] cannot wrap
  RTS            ; [6]
@back_sol:       ; start of buffer, or some line within a buffer?
  ; XXX incomplete: go back to previous line if multiline
  RTS

; @@ printmsg
; println a string in the messages page
printmsg:
  LDX #>messages  ; high byte
  ; +++ fall through to @@ println +++

; @@ println
; print a string, then a carriage return
; assumes we're in "text mode" with DMA DST set up
println:           ; X=high Y=low
  JSR print
  JMP newline

; @@ print, in "text mode"
; write a length-prefix string to the screen
; assumes we're in "text mode" with DMA DST set up
print:           ; X=high Y=low (uses Src,A,X,Y)
  STX SrcH       ; src high
  STY Src        ; src low
  LDY #0         ; string offset, counts up
  LDA (Src),Y    ; load string length
  BEQ @ret       ; -> nothing to print
  TAX            ; length, counts down
  INY            ; advance to first char
@loop:
  LDA (Src),Y    ; [5] load char from string
  ; begin writechar inline
  CMP #32        ; [2] is it a control character?
  BCC @ctrl      ; [2] if <32 -> @ctrl
  STA IO_DDRW    ; [3] write tile byte to VRAM
  LDA Color      ; [3] current text color (16-color mode)
  STA IO_DDRW    ; [3] write attribte byte to VRAM
  DEC WinRem     ; [5] at right edge of window?
  BEQ @nl        ; [2] if so -> @nl
  ; end writechar inline
@incr:
  INY            ; [2] advance string offset
  DEX            ; [2] decrement length
  BNE @loop      ; [3] not at end -> @loop
@ret
  RTS            ; [6] done
@nl:             ; wrap onto the next line and keep printing
  LDA #13        ; [2] newline control code
@ctrl:
  JSR wrctrl     ; [6] execute control code (uses A, preserves X,Y)
  JMP @incr


; ------------------------------------------------------------------------------
; READLINE, LINE EDITOR

; Arrows move within the line; insert or delete text anywhere
; Shift+Select and COPY, MOVE, DEL; Ctrl+L/R goes to Start/End
; insert logic:
; get buffered key count (up to CTRL code or wraparound)
; check if room in buffer
; DMA copy backwards From=old_end To=new_end Len=(buf_len-cursor_pos)
; copy in the buffered chars
; ... do the same thing on the screen, line by line
;     (maybe just re-print the rest of the line, with EOL clearing?)

; @@ readline
; read a single line of input into the line buffer (zero-terminated)
; XXX this will become the line editor
readline:        ; uses A,X,Y, returns Y=length (Z=1 if zero)
  LDA #0
  STA Tmp        ; init line offset [3] not [4]
@wait:
  STA IO_YLIN    ; wait for vblank (A ignored)
  BIT ModKeys    ; check for Escape
  BMI @esc
@more:
  JSR readchar   ; read char from keyboard -> A (ZF) uses X,Y !Tmp
  BEQ @wait      ; if zero -> @wait
  CMP #13        ; is it RETURN?
  BEQ @done      ; if so -> exit
  LDY Tmp        ; load line offset [3] not [4]
  CMP #8         ; is it BACKSPACE?
  BEQ @backsp    ; if so -> @backsp
  CPY #$FF       ; at the final byte?
  BEQ @beep      ; buffer full -> beep
  STA LineBuf,Y  ; append to line buffer
  INY            ; advance line offset
  STY Tmp        ; save line offset [3] not [4]
  JSR writechar  ; output char to screen (A=char, preserves X,Y)
  JMP @more      ; keep reading chars
@done:
  LDA #0         ; terminator
  LDY Tmp        ; get line offset (ZF)
  STA LineBuf,Y  ; write to line buffer
  RTS            ; returns Y=length (ZF=1 if zero)
@backsp:
  CPY #0         ; at the first byte?
  BEQ @beep      ; buffer empty -> beep
  DEY            ; go back one place
  STY Tmp        ; save line offset [3] not [4]
  JSR wrctrl     ; backspace the display
    ; XXX if text is selected -> from=end_of_sel; to=start_of_sel
    ; XXX else from=cursor; to=cursor-1
    ; XXX DMA_len = buf_length - from
    ; XXX DMA_Dest = `to` (and save it)
    ; XXX DMA copy forwards Src=from Dst=to
    ; XXX Write N=(from-to) blank chars to DMA (wrap at WinW)
    ; XXX restore saved DMA Dest at `to`
  JMP @more
@beep:
  JSR beep
  LDA KeyTl      ; clear keyboard buffer
  STA KeyHd
  JMP @more
@esc:
  JMP repl_esc

; @@ beep
; play an error beep over the speaker
beep:            ; XXX start beep playing
mode_ret:
  RTS


; ------------------------------------------------------------------------------
; MODE, CLS, TAB, reset sprites & palette

modetab:
  .byte VCTL_APA+VCTL_H320+VCTL_V200+VCTL_2BPP                         ; mode 0, graphics,    4 color (320x200) 4
  .byte VCTL_APA+VCTL_H320+VCTL_V200+VCTL_4BPP                         ; mode 1, graphics,   16 color (160x200) 16
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP                                  ; mode 2, 40x25 tile,  4 color (320x200) 4x8=32
  .byte VCTL_H320+VCTL_V200+VCTL_4BPP                                  ; mode 3, 20x25 tile, 16 color (160x200) 16x2=32
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL                       ; mode 4, 40x25 text, 16 color (320x200) 16+16=32
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL+VCTL_NARROW           ; mode 5, 64x25 text, 16 color (320x200) 16+16=32
  .byte VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL+VCTL_NARROW+VCTL_GREY ; mode 6, 64x25 text, 16 shade (320x200) 16+16=32

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
mode:            ; set screen mode, X=mode (+Tmp)
  CPX #7         ; range-check mode number
  BCS mode_ret   ; if >= 7
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
  LDA #VENA_VSync|VENA_BG_En|VENA_Spr_En
  STA IO_VENA    ; interrupt/video enable
  LDA #4         ; w=64 (1<<2) h=32 (0)
  STA IO_VMAP    ; tilemap size (ignored in APA modes)
  LDA #>VR_TEXT  ; tilemap base address (ignored in APA modes)
  STA IO_VTAB    ; set tilemap high byte
  JSR reset_tilebank  ; reset tile bank-switching
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
cls:                     ; (+Tmp)
  LDX WinL               ; [3] text window left
  LDY WinT               ; [3] text window top
  JSR text_addr_xy       ; [6] calculate DSTH,DSTL at X,Y
  LDY WinH               ; [3] number of rows to fill
  STY Tmp                ; [3] row counter
  LDX Color              ; [3] fill attribute
@row:
  LDA #32                ; [2] fill tile (space)
  LDY WinW               ; [3] number of columns to fill
@col:
  STA IO_DDRW            ; [3] write tile
  STX IO_DDRW            ; [3] write attribute
  DEY                    ; [2] decrement column count
  BPL @col               ; [3] until Y=0        (BUG: out by one, FIX: BNE)
; advance VRAM address by map width (64) - WinW
  LDA #64
  SEC
  SBC WinW               ; XXX keep this in a var?
  ASL                    ; 2x this width (safe: was <= 64)
  CLC
  ADC IO_DSTL
  STA IO_DSTL
  BCC @low_ok            ; [3] C=1 when DSTL wraps around
  INC IO_DSTH            ; [5] address high += 1
@low_ok:
  DEC Tmp                ; [5] decrement row count
  BNE @row               ; [3] until row=0
  ; +++ fall through to @@ home +++

; @@ home
; move the cursor to the top-left of the window
; update DMA address (DSTL,DSTH) for "text mode"
; home:          ; (+Tmp)
  LDX #0         ; top-left corner of text window
  LDY #0         ; 
  BEQ tab_e2     ; skip range checks
  ; +++ fall through to @@ tab +++

; @@ tab
; move the cursor to X,Y in index registers (unsigned)
; relative to the top-left corner of the text window, zero-based.
; update DMA address (DSTL,DSTH) for "text mode"
tab:             ; (+Tmp)
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
text_addr_xy:    ; (+Tmp)
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

; @@ reset_tilebank
; reset all tile bank-switching to the default 1:1 mapping
reset_tilebank:
  LDA #$00       ; map slot 0 to address-region 0
  CLC
@banklp:
  STA IO_VBNK    ; [3] bank slot,addr [ssssaaaa]
  ADC #$11       ; [2] 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF ..
  BCC @banklp    ; [3] .. 110 (C=1)  [[ 16*8 = 128 cycles ]]
  RTS


; @@ dma_fill_rect
; fill VRAM rect with byte FILL at address DSTH,DSTL (changes DMA mode!)
dma_fill_rect:           ; A=stride X=width Y=height (+Tmp)
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



; ------------------------------------------------------------------------------
; PAGE 37-3A (1K) + 3B-3E (1K)

ORG CHROM        ; 256 x 8 = 2K char rom
  INCLUDE "font/font.txt"

; ------------------------------------------------------------------------------
; PAGE 3F
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
; also turn on video display for visual feedback
  LDA #VENA_Pwr_LED|VENA_BG_En ; $14
  STA IO_VENA    ; video enable
  STA IO_VTAB    ; tilemap page ($1400 in VRAM)
  STA IO_VMAP    ; tilemap size ($14=10100 w=64 h=32)
  LDA #VCTL_H320+VCTL_V200+VCTL_2BPP+VCTL_16COL
  STA IO_VCTL
  LDA #0
  STA IO_DSTL
  STA IO_DSTH
  LDA #DMA_M2V|DMA_Fill  ; DMA fill VRAM
  STA IO_DCTL
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
  JMP reset              ; all tests passed

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
@memchk:                 ; A=fill X=page
  STA IO_FILL            ; [3] also fill VRAM
  STX $01                ; [3] pointer high = page byte
; fill the page
  LDY $03                ; [3] load Y count (256 [=$00] except for stack page)
  STY IO_DRUN            ; [3] start DMA fill (for visual feedback)
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

; @@ halt
; stop the CPU, wait for interrupt
halt:
  STA IO_YLIN    ; wait for vblank
  JMP halt

; @@ irq_init
; set up IRQ vector in zero page, init keyboard, enable interrupts
irq_init:
  SEI            ; disable IRQ
  LDA #0         ; reset keyboard buffer (with interrupts disabled)
  STA KeyHd
  STA KeyTl
  LDA #$4C       ; JMP abs
  STA IrqVec
  LDA #<irq_rom  ; low byte
  STA IrqVec+1
  LDA #>irq_rom  ; high byte
  STA IrqVec+2
  CLI            ; enable IRQ
  RTS

; @@ irq_rom
; standard ROM IRQ handler: keyboard scan
irq_rom:
  JSR keyscan
  LDA #VSTA_VSync|VSTA_VCmp|VSTA_HSync
  STA IO_VSTA    ; acknowledge interrupts
nmi_vec:
  RTI

; @@ Vector Table
ORG VEC
DW nmi_vec       ; $FFFA, $FFFB ... NMI (Non-Maskable Interrupt) vector
DW reset         ; $FFFC, $FFFD ... RES (Reset) vector (reset_hard)
DW IrqVec        ; $FFFE, $FFFF ... IRQ (Interrupt Request) vector
