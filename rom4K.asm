; Robo 4K BASIC 1.0
; Use `asm6` to compile: https://github.com/parasyte/asm6

; BASIC Messages  0.25 ($100)  \              00
; BASIC Tokenize  0.5K ($200)  |  2K          01 02
; BASIC Runtime   1.0K ($400)  |              03 04 05 06
; Floating Point  0.25 ($100)  /              07
; Strings         0.25 ($100)  \              08
; Graphics        0.25 ($100)  |  1K          09
; Keywords        0.5  ($200)  /              0A 0B
; ---------------------------
; Cassette        164b ($a4)   \              0C
; Keyboard        256b ($100)  |              0D
; Print/Wrchr     231b ($e7)   |              0E
; Readline        103b ($67)   |  1K          0F
; Cls/Tab/XY      106b ($6a)   |  
; Copy fw/bw       85b ($55)   |  
; IRQ/Cursor       79b ($4f)   /
;                 -----------
; 256+231+103+106+85+79+164

; 4 pages System:
; • Cassette code
; • Sound interrupt
; • Serial
; • Number conversion

BasROM   = $F000  ; 4K BASIC ROM
DiskROM  = $E000  ; 4K DISK ROM
SizeIMG  = $1000  ; size of 4K file

HWVEC    = $FFFA  ; vector table, 6 bytes
SYSVEC   = $FFC0  ; system vector table


; ------------------------------------------------------------------------------
; Address Space

; Moved VRAM to the end of detected memory: dynamic VidBase.
; Otherwise, on a screen mode change, we would need to
; move the BASIC program (breaking pointers on the stack)
; and machine code programs would need to be compiled
; for a specific screen mode?!

ZeroPg   = $00    ; zero page (constant)
StackPg  = $01    ; stack page (constant)
VidBase  = $02    ; start of video memory (constant)
BaseAdr  = $05C0  ; start of free memory (constant $05C0)
End4K    = $10    ; end of 4KB memory (minimum RAM fitted)


; ------------------------------------------------------------------------------
; Zero Page $00-7F - BASIC WORKSPACE / Free for ASM software

; -- $00-1F BASIC Operator Stack (32 bytes)

OpStack  = $00    ; BASIC operator stack                          (used in Eval [RT / Direct])

LineNo   = $00    ; ALIAS Parsed line number                      (used in EDIT)
LineNoH  = $01    ; ALIAS Parsed line number                      (used in EDIT)

; -- $20-5F BASIC Variables (64 bytes)

VarPtrs  = $20    ; 26 x variable pointers (52)                   (used in RT / Direct)

OpTop    = $54    ; Top of OpStack (stack pointer)                (used in RT / Direct)
ArgTop   = $55    ; Top of ArgStack (stack pointer)               (used in RT / Direct)
TopPtr   = $56    ; TOP of BASIC program, start of variables      (used in RT / EDIT)
TopPtrH  = $57
FreePtr  = $58    ; FREE space at end of variables                (used in RT / Direct / EDIT)
FreePtrH = $59
HeapPtr  = $5A    ; bottom of string HEAP, descending             (used in RT / Direct / EDIT)
HeapPtrH = $5B
CODE     = $5C    ; BASIC code pointer (next instruction)         (used in RT / Direct)
CODEH    = $5D
Data     = $5E    ; BASIC data pointer (next DATA statement)      (used in RT)
DataH    = $5F    ; ALIAS (EmitOfs)

EmitPtch = $5E    ; ALIAS Data  - emit placeholder offset          (used in EDIT)
EmitOfs  = $5F    ; ALIAS DataH - emit offset for tokenized code   (used in EDIT)

; -- $60-7F Scratch Space (32 bytes)


; ------------------------------------------------------------------------------
; Zero Page $80-FF - OS WORKSPACE

; -- $80-8F Keyboard Buffer (16)

KeyBuf     = $80        ; Keyboard buffer (16 bytes, align 16)
KeyBufMask = 15         ; Modulo 16 (bitmask)

; -- $90-9F FCB Table (16)

FCB_1      = $90        ; File Control Block #1 (8 bytes)
FCB_2      = $98        ; File Control Block #2 (8 bytes)
FCB_buf    = 0          ; 0,1  ptr to heap buffer (2)
FCB_blk    = 2          ; 2    current block (1)
FCB_ofs    = 3          ; 3    current ofs (1)
FCB_toc    = 4          ; 4-5  ptr to name string [tape] / toc entry [disk] (2)
FCB_szb    = 6          ; 6    size in blocks (1)
FCB_szo    = 7          ; 7    final block length (1)
FCB_base   = FCB_1 - 8  ; FCB_base + (#n << 3) -> FCB_n

; -- $A0-BF Disk Workspace (32)

; -- $C0-CF System Temporaries (16)

Src      = $C0          ; source pointer \ Scroll (PRINT/WRCHR/WRCTL), CLS  [Term0]
SrcH     = $C1          ; source pointer | Tokenize (match_kws/num_val)     [Term1]
Dst      = $C2          ; destn pointer  | Scroll (PRINT/WRCHR/WRCTL), CLS  [Term2]
DstH     = $C3          ; destn pointer  /                                  [TermE]
Ptr      = $C4          ; third pointer  \ VAR ptr, STR ptr, PRINT src (can cause Scroll)
PtrH     = $C5          ; third pointer  /
B        = $C6          ; extra register | Subroutines are annotated with usage;
C        = $C7          ; extra register | held across calls only when unused
D        = $C8          ; extra register | by callees (manually tracked)
E        = $C9          ; extra register |
F        = $CA          ; extra register | Scratch (always transient; cannot hold)

; xxx    = $CB          ; xxx

Acc0     = $CC          ; accumulator byte 0                  (used in RT / Direct)
Acc1     = $CD          ; accumulator byte 1
Acc2     = $CE          ; accumulator byte 2
AccE     = $CF          ; accumulator exponent (0 for integer)

Term0    = $C0          ; ALIAS Src: term byte 0
Term1    = $C1          ; ALIAS SrcH: term byte 1
Term2    = $C2          ; ALIAS Dst: term byte 2
TermE    = $C3          ; ALIAS DstH: term exponent (0 for integer)

; -- $D0-DF System Vars (16)

KeyHd    = $D0        ; keyboard buffer head (owned by User)
KeyTl    = $D1        ; keyboard buffer tail (owned by IRQ)
ModKeys  = $D2        ; modifier keys [7:Esc 6:Shf 5:Ctl 4:Fn] (owned by IRQ)
CurrKey  = $D3        ; keyboard current key pressed, for auto-repeat (owned by IRQ)
DeadKey  = $D4        ; keyboard last key pressed, to ignore it (owned by IRQ)
KeyRep   = $D5        ; keyboard auto-repeat timer

CurX     = $D6        ; cursor X position
; xxx    = $D7        ; xxx

TXTP     = $D8        ; text write address
TXTPH    = $D9        ; text write address high

CurTime  = $DA        ; cursor flash timer
CurChar  = $DB        ; character under cursor
CurVis   = $DC        ; cursor visible flag (7:visible 6:inhibit 5-0:noise)

; xxx    = $DD        ; xxx
IOChan   = $DE        ; active #iochan (0,1=FCB 8=Parallel 9=Serial)
MemSize  = $DF        ; detected memory size in pages

; -- $E0-EF Option Registers, OS Vectors (16)

Time     = $E0        ; Time Counter 16-bit (VSync)

; Option = $E2-E7     ; OPT registers

IRQTmp   = $E8        ; Temp for IRQ handler #1
IRQTmp2  = $E9        ; Temp for IRQ handler #2
NmiVec   = $EA        ; NMI vector in RAM {JMP,Low,High} (for ROM override)
IrqVec   = $ED        ; IRQ vector in RAM {JMP,Low,High} (for ROM override)

; -- $F0-FF  IO Area (16)

IO_EXT0  = $F0        ; A/B expansion IO
IO_EXT1  = $F1        ; A/B expansion IO
IO_EXT2  = $F2        ; A/B expansion IO
IO_EXT3  = $F3        ; A/B expansion IO
IO_EXT4  = $F4        ; A/B expansion IO
IO_EXT5  = $F5        ; A/B expansion IO
IO_EXT6  = $F6        ; A/B expansion IO
IO_EXT7  = $F7        ; A/B expansion IO
IO_KEY   = $F8        ; Keyboard 8-bit (7:TXD 6:RTS 5:TapeOut 4:Speaker 3-0:KBCol) / read: KB row 8-bit
IO_VID   = $F9        ; IO Read: (2:TapeIn 1:CTS 0:RXD)
IO_VLN   = $FA        ; Reserved
IO_PAL   = $FB        ; Reserved
IO_PSG   = $FC        ; Reserved
IO_CFG   = $FD        ; Reserved
IO_PIO   = $FE        ; Reserved
IO_EXP   = $FF        ; Expansion 8-bit (7:CDsel 6-5:ABsel 4-0:MemoryMap) [R/W]

; I=0000   0=1000 1=2000 2=3000 3=4000 4=5000 5=6000 6=7000
; 4KB +4   ^+A    ^+B    ^+B    ^+B    ^+B    ^+B    ^+B     (^+B ..)
; 4KB +8   ^+A    ^+A    ^+B    ^+B    ^+B    ^+B    ^+B     (^+B ..)
; 4KB +16  ^+A    ^+A    ^+A    ^+A    ^+B    ^+B    ^+B     (^+B ..)
; 8KB +4          ^+A    ^+B    ^+B    ^+B    ^+B    ^+B     (^+B ..)
; 8KB +8          ^+A    ^+A    ^+B    ^+B    ^+B    ^+B     (^+B ..)
; 8KB +16         ^+A    ^+A    ^+A    ^+A    ^+B    ^+B     (^+B ..)
; 16KB +4                       ^+A    ^+B    ^+B    ^+B     (^+B ..)
; 16KB +8                       ^+A    ^+A    ^+B    ^+B     (^+B ..)
; 16KB +16                      ^+A    ^+A    ^+A    ^+A     (^+B ..)
;          tie=0   d0     d1     d2     d3     d4     d4


; ------------------------------------------------------------------------------
; PAGE ONE $100-1FF - STACK

LineBuf  = $100    ; Input Buffer (128 bytes)
EmitBuf  = $100    ; Emit Buffer (128 bytes)

ExprStk  = $100    ; Expression stack (96 bytes = 24 numbers)

StackBot = $180    ; Bottom of BASIC control-stack (cannot go below $180)


; ------------------------------------------------------------------------------
; Defines

ModEsc   = $80    ; Escape is down
ModShift = $40    ; Shift is down
ModCtrl  = $20    ; Ctrl is down
ModGr    = $10    ; GR key is down
ModCol   = $08    ; COL key is down



; ------------------------------------------------------------------------------
; PAGE 0 - BASIC REPL

ORG BasROM
messages:           ; page-aligned

; ------------------------------------------------------------------------------
; Messages

; boot messages (50b)
msg_boot:
  DB $92,$93,$94,$95,$96,$90,13,13
  DB "Frontier BASIC 1.0",13,13,0
msg_freemem:
  DB " bytes free",13,13,0
msg_ready:
  DB "Ready",13,0

; error messages (36b)
msg_mis:  DB "MIS",0
msg_syn:  DB "SYN",0
msg_div:  DB "DIV",0
msg_rng:  DB "RNG",0
msg_var:  DB "VAR",0
msg_for:  DB "FOR",0
msg_gos:  DB "GOS",0
msg_typ:  DB "TYP",0
msg_esc:  DB "ESC",0

; TAPE messages (33b)
msg_press:
  DB "Press ",0
msg_play:
  DB "PLAY",13,0
msg_stop:
  DB "STOP",13,0
msg_load:
  DB "Load ",0
msg_rewind:
  DB "REWIND ",0


; ------------------------------------------------------------------------------
; BASIC

reset:
  SEI               ; disable interrupts
  CLD               ; disable BCD mode
  LDA #End4K        ; end of memory (page)
  STA MemSize       ; set size of memory (in pages)
  LDA #0            ;
  STA IOChan        ; set #chan = 0
  JSR vid_cls       ; clear screen
  LDY #<msg_boot    ; boot message
  JSR err_wrn       ; print it (uses A,X,Y)
  ; print free memory
  LDA MemSize       ; size of fitted memory in pages
  SEC
  SBC #6            ; subtract 4 video + 2 system pages
  STA Acc1
  LDA #64           ; plus 1024-960 = 64 bytes
  STA Acc0
  JSR print_u16     ; print it
  LDY #<msg_freemem ; " bytes free"
  JSR err_wrn       ; print it (uses A,X,Y)
;basic:
  SEI               ; disable interrupts
  CLD               ; disable BCD mode
  LDX #$FF          ; X = $FF
  TXS               ; reset SP = $FF
  JSR irq_init      ; set up IRQ handler (cursor blink)
  LDY #<msg_ready   ; [2] "Ready"
  JSR err_wrn       ; [6] print it (uses A,X,Y)
repl:
  JSR readline      ; [6] read command or BASIC statement
  JSR wr_eol        ; [6] move to new line (REQUIRES: Y=0)
  ; using Ptr is compatible with VAL(A$)
  ; use the screen as the input buffer instead?
  ; costs 6 bytes, saves 7 bytes LineBuf addressing
  STY Ptr           ; [3] set input Ptr low ($00)
  INY               ; [2]
  STY PtrH          ; [3] set input Ptr high ($01)
  DEY               ; [2]
; parse the line
  JSR num_u16       ; check for number, CS=found
  BCC @direct       ; [2] -> no line number [+1]
  LDA Acc1          ; [3] save LineNo
  STA LineNoH       ; [3]
  LDA Acc0          ; [3]
  STA LineNo        ; [3]
  JSR skip_spc      ; [6] Y=ofs -> A,X=next-char (EQ if zero)
  BEQ @delln        ; [2] -> empty line, delete the line [+1]
  JSR tokenize      ; [6] tokenize the line
  ;JSR debug         ;
  JSR ins_line      ; [6] insert the line into the BASIC program
  JMP repl          ; [3] -> return to repl
@direct:
  JSR skip_spc      ; [6] Y=ofs -> A,X=next-char (EQ if zero)
  BEQ repl          ; [2] -> empty line, back to repl [+1]
  JSR tokenize      ; tokenize the line
  ;JSR debug         ;
  LDA #OP_END       ; 
  JSR tok_emit      ; terminate the line
  LDA #>EmitBuf     ; EmitBuf page ($01)
  LDX #0            ; at offset 0
  JSR set_prog      ; set up for execution
  JMP do_stmt       ; -> execute the statement  (XXX how does this return without OP_END?)
@delln:
  JSR del_line      ; delete the line at LineNo
  JMP repl



; ------------------------------------------------------------------------------
; Errors


; @@ escape
; report Escape pressed, return to REPL  (5b)
escape:
  JSR hide_cursor   ; uses A,Y; Y=0 (for Escape)
  LDY #<msg_esc     ; "ESC"
  ; +++ fall through +++

; @@ err_rep
; report an error with `#` prefix  (17b)
report_err:
err_rep:            ; Y=msg_ofs
  JSR newline       ; new line (uses A,X) preserves Y
  LDA #35           ; `#`
  JSR err_wr        ; write #<MSG>
@wait:              ; wait for Escape to be released (for Escape)
  JSR newline       ; new line (uses A,X) preserves Y
  LDA ModKeys       ; check key state
  BMI @wait         ; -> ESC still down
  BEQ repl          ; -> always

; @@ err_wr
; write a message with prefix (zero-terminated)  (9b)
; also used by TAPE routines
err_wr:             ; Y=message A=prefix_char
  JSR wrchr         ; write char (A=char, uses A,X) preserves Y
err_wrn:            ; Y=message (no prefix)
  LDA messages,Y    ; next char
  BNE err_wr        ; loop until zero
  RTS               ; -> EQ



; ------------------------------------------------------------------------------
; BASIC Tokenizer
;
; Y = current LineBuf offset at (Ptr)
; A,X = temporaries

; emit a string literal
; MUST insert LEN prefix, otherwise runtime will need to count length
emit_str:
  LDA #OP_STR        ;
  JSR tok_emit       ; -> X=EmitOfs-1
  INX                ; [2] get emit offset
  STX EmitPtch       ; [2] save placeholder address (inline tok_place)
@copy:
  JSR tok_emit       ; emit char (uses X=0; preserves A,Y; sets PL)
  INY                ; advance
  LDA LineBuf,Y      ; get next char
  BEQ @missing       ; -> at end of line, missing quote
  CMP #34            ; is it `"`?
  BNE @copy          ; -> continue
  INY                ; advance
  CMP LineBuf,Y      ; is next char `"` ?
  BEQ @copy          ; -> emit one `"` and continue
  JSR patch_len      ; patch LEN placeholder (PL)
  BPL tok_loop       ; -> always
@missing:            ; at end of line, missing quote
  LDY <msg_mis       ; #MIS
  BNE err_rep        ; -> report error

; @@ emit_let        (report syntax error for unknown keywords)
emit_let:            ; Y -> Y,EQ
  JSR emi_var        ; -> recognise and emit VAR[$][(..)]
  JSR skip_spc       ; Y=ofs -> A,X=next-char (EQ if zero)
  CMP #61            ; is it `=`?
  BEQ tok_loop       ; -> valid LET stmt
tok_syn:             ; VAR was an unknown keyword, roll back?
  LDY #<msg_syn      ; report syntax error
  BNE report_err     ; -> unknown keyword

tok_colon:
  ; subsequent statement
  INY                ; consume `:`
  INC D              ; D=1 after `:` (used for OP_LET)
  ; +++ fall through +++

; @@ tokenize
; tokenize BASIC statements (in-place in LineBuf/EmitBuf)
; Statement tokens >$C0 replace colon
tokenize:            ; Y=ofs,D=0 uses A,X,B,C,D,Src
  JSR skip_spc       ; Y=ofs -> A,X=next-char (EQ if zero)
  JSR is_alpha       ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCS tok_syn        ; -> syntax error
  TAX                ; A-Z as index (0-25)
  LDA stmt_kwi,X     ; look up KW offset (A-Z)
  LDX #>stmt_page    ; stmt table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC emit_let       ; -> no match, emit VAR
tok_emC:             ; for OP_ELSEX
  ORA #$C0           ; set top bits (match_kws uses d7,d6)
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y; sets PL)
  CMP #OP_DATA       ; a DATA statement?
  BEQ tok_data       ; -> handle DATA/REM
  CMP #OP_REM        ; a REM statement?
  BEQ tok_data       ; -> handle DATA/REM
tok_loop:
  JSR skip_spc       ; Y=ofs -> A,X=next-char (EQ if zero)
  BEQ tok_done       ; -> end of line
  JSR is_alpha       ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC @fnvar         ; -> KEYWORD or VAR
  TXA                ; restore A
  CMP #34            ; `"`
  BEQ emit_str       ; -> emit STRING
  JSR is_digit       ; A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC emit_num       ; -> emit NUMBER
  TXA                ; restore A
  CMP #58            ; `:`
  BEQ tok_colon      ; -> expect statement
  LDA #<expr_ops     ; operator table
  LDX #>expr_page    ; stmt table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC tok_syn        ; -> syntax error
@emiop:
  CMP #OP_ELSEX      ; "ELSE" keyword in expr_kwi?
  BEQ tok_emC        ; -> emit statement opcode ($C0)
  AND #$BF           ; clear bit 6 ($40)
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y) -> PL
  BPL tok_loop       ; -> ALWAYS: continue
@fnvar:              ; FUNCTION/VAR (or ELSE inside IF body)
  TAX                ; A-Z as index
  LDA expr_kwi,X     ; look up KW offset (A-Z)
  LDX #>expr_page    ; expr table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCS @emiop         ; -> match, emit opcode (can be OP_ELSEX)
  JSR emi_var1       ; -> recognise and emit VAR (expr context)
  JMP tok_loop       ; -> ALWAYS: continue

tok_data:            ; copy rest of line verbatim
  JSR skip_spc       ; Y=ofs -> A,X=next-char (EQ if zero)
@copy:
  LDA LineBuf,Y      ; copy rest of the line
  BEQ tok_done       ; -> end of line
  INY                ; advance input
  JSR tok_emit       ; emit code (uses X=0; preserves A,Y) -> PL
  BPL @copy          ; -> ALWAYS: until end of line
tok_done:
  RTS

; @@ emit_num
; assumes next char is digit
emit_num:
@loop:
  JSR num_u24        ; from LineBuf,Y-> Y,Acc,CS=ovf (uses A,X,Term)
  BCS tok_ovf        ; -> overflow
  LDA Acc2
  BNE @int4          ; -> 3 bytes plus opcode
  LDA Acc1
  BNE @int3          ; -> 2 bytes plus opcode
  LDA Acc0
  CMP #10            ; CS if >= 10
  BCS @int2          ; -> 1 byte plus opcode
; single-digit number
  ORA #$F0           ; 0xF0 - 0xF9 (nums >= 0xF0)
  JMP @done          ; -> ALWAYS
@int2:
  LDA #OP_INT2       ; 2-byte integer (with opcode)
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  JMP @out1
@int3:
  LDA #OP_INT3       ; 3-byte integer (with opcode)
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  JMP @out2
@int4:
  LDA #OP_INT4       ; 4-byte integer (with opcode)
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
;out3:
  LDA Acc2
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
@out2:
  LDA Acc1
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
@out1:
  LDA Acc0
@done:
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  JMP tok_loop       ; -> ALWAYS

; @@ emi_var
; copy VAR[$] to output (assumes 1st char is alpha)
emi_var:
  LDA D            ; [3] D=1 after `:` (used for OP_LET)
  BEQ emi_var1     ; [2] -> at start of line [+1]
  LDX #OP_LET      ; [2] emit OP_LET (replaces `:`)
emvr_lp:
  TXA              ; [2] X -> A
  JSR tok_emit     ; [6] output byte (uses X=0; preserves A,Y; sets PL)
emi_var1:          ; <- start VAR emit
  LDA LineBuf,Y    ; [4] next input char
  INY              ; [2] advance input (assume match)
  TAX              ; [2] save X=char
  JSR is_alpha     ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC emvr_lp      ; [2] -> is alpha, continue [+1]
  TXA              ; [2] restore A
  JSR is_digit     ; [6] A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC emvr_lp      ; [2] -> is digit, continue [+1]
  TXA              ; [2] restore A
  DEY              ; [2] undo advance (didn't match)
  CMP #36          ; [2] is it `$` ?
  BNE @nostr       ; [2] -> no [+1]
  JSR tok_emit     ; [6] output `$` (uses X=0; preserves A,Y; sets PL)
  INY              ; [2] consume `$`
@nostr:
  RTS              ; [2] -> return

; @@ tok_place
; emit a placeholder
tok_place:
  LDX EmitOfs        ; [3] get emit offset
  STX EmitPtch       ; [2] save placeholder address
  ; +++ fall through +++

; @@ tok_emit
; emit an opcode at Emit,X and advance EmitOfs.
tok_emit:            ; (uses X; preserves A,Y -> NE,PL)
  LDX EmitOfs        ; [3] get emit offset
  STA EmitBuf,X      ; [5] emit token
  INC EmitOfs        ; [5] advance emit offset (NE)
  BMI tok_ovf        ; [2] -> overflowed emit buffer [+1] -> MI
  RTS                ; [6] -> NE,PL,X=EmitOfs-1 (for emit_str)

; @@ patch_len
; patch placeholder with length
patch_len:
  LDA EmitOfs        ; [3] get emit offset
  CLC                ; [2] minus 1 (exclude patched byte)
  SBC EmitPtch       ; [2] LEN = (EmitOfs-1) - EmitPtch
  LDX EmitPtch       ; [3] get placeholder patch address (PL)
  STA EmitBuf,X      ; [5] write fixup byte
  RTS                ; [6] -> PL

tok_ovf:
  LDY #<msg_rng      ; [2] #RNG
  JMP err_rep        ; [3] -> report error

; @@ match_kws
; find matching keyword, terminated by a byte with top-bit set (8x,9x,Ax,Bx)
; if no match, continue until bit 6 is set (Cx,Dx,Ex,Fx)
; note: XA table cannot cross a page boundary (INC/DEC Src would wrap)
match_kws:       ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  STY B          ; [3] save start of input
  STA Src        ; [3] table-low (offset)
  STX SrcH       ; [3] table-high (page)
  LDX #0         ; [2] const X=0
@next_kw:
  DEY            ; [2] set up for pre-increment
  DEC Src        ; [5] set up for pre-increment
@match_lp:
  INY            ; [2] pre-increment input position
  INC Src        ; [5] pre-increment keyword position
  LDA (Src,X)    ; [6] next keyword char
  BMI @found     ; [2] -> matched keyword (top bit set) [+1] (MUST check LDA flags not CMP flags)
  CMP LineBuf,Y  ; [4] does it match input?
  BEQ @match_lp  ; [2] -> yes, next char [+1]
; no match, skip rest of keyword (find top-bit)
@skip_lp:
  INC Src        ; [5] find end of this keyword
  LDA (Src,X)    ; [6] check keyword byte
  BPL @skip_lp   ; [2] -> top bit clear, keep going [+1]
  INC Src        ; [5] advance to next keyword
  LDY B          ; [3] restore Y = start of input
  ASL            ; [2] shift left top-bit byte
  BMI @next_kw   ; [2] -> bit 6 set, try next keyword [+1]
  CLC            ; [2] no match found
  RTS            ; [6] Y=ofs (restored) X=0
@found:
  SEC            ; [2] set carry: keyword was found
  RTS            ; [6] A=hi-byte (top bit set) X=0


; LET <var> '=' <expr>                                   -> {LETn|LETs|LETa}<var><expr> (x2?)
; DIM <var> '(' <expr> ')'                               -> {DIM}<var><expr_n>
; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>] -> {FOR}<var><expr_n><expr_n><expr_n|$00>
; NEXT [<var>|$00]                                       -> {NEXT}<var|$00>
; ELSE <line>/<stmts>                                    -> {ELSE}<len>       | {ELLN}<n16>
; READ {<var> ','}                                       -> {READ}<len>{<var>}
; PRINT { [,;'] "str" | <expr_n> | <expr_s> } [;]        -> {PRINT|PRINT;}<len>{<op|lit|expr>}
; INPUT { [,;'] "str" | <var> }                          -> {INPUT}<len>{<op|lit|var>}
; OPEN #<n> ',' <expr_s>                                 -> {OPEN}<n><expr_s>
; CLOSE #<n>                                             -> {CLOSE}<n>
; REM <text>                                             -> {REM}<len><data>
; DATA <text>                                            -> {DATA}<len><data>    (XXX "DATA 1.02e1" -> A$)
; RETURN                                                 -> {RETURN}
; CLS                                                    -> {CLS}
; IF <expr_n> THEN <line>/<stmts> [ELSE <line>/<stmts>]  -> {IF}<expr_n><len> | {IFLN}<expr_n><n16>
; GOTO <expr_n>                                          -> {GOTO}<expr_n>
; GOSUB <expr_n>                                         -> {GOSUB}<expr_n>
; RESTORE <expr_n>                                       -> {RESTORE}<n16>
; POKE <expr_n> ',' <expr_n>                             -> {POKE}<expr_n><expr_n>
; SOUND <pitch>,<vol>,<len>,[<dp>,[<dv>]]                -> {SOUND}<expr_n><expr_n><expr_n><expr_n|$00><expr_n|$00>
; PLOT <expr_n> ',' <expr_n>                             -> {PLOT}<expr_n><expr_n>
; LINE <expr_n> ',' <expr_n> ',' <expr_n> ',' <expr_n>   -> {LINE}<expr_n><expr_n><expr_n><expr_n>


; ------------------------------------------------------------------------------
; PAGE 2

; find_line -> Ptr (start of line, or start of first greater line, or end marker)
; InsPtr = Ptr (save it)
; NewLen = EmitOfs + 5 (add header)
; IF replacing:
;   OldLen = existing Line Length
;   Ptr += OldLen (advance to start of next line)
; ELSE
;   OldLen = 0 (always do insert)
; IF NewLen > OldLen:
;   Ins = NewLen - OldLen (insert length)
;   IF Top + Ins >= EndPage -> No Room
;   Src = Ptr       (move up data above Ptr)
;   Dst = Ptr + Ins (move up by Ins)
;   Len = Top - Src (length moved)
;   Top += Ins      (update Top)
;   COPY Len from Src -> Dst
; IF NewLen < OldLen:
;   Del = OldLen - NewLen (delete length)
;   Src = Ptr       (move down data above Ptr)
;   Dst = Ptr - Del (move down by Del)
;   Len = Top - Src (length moved)
;   Top -= Del      (update Top)
;   COPY Len from Src -> Dst
; COPY EmitOfs from EmitBuf -> InsPtr

; @@ ins_line
; insert EmitBuf into the program at LineNo
ins_line:           ; LineNo
  RTS
  LDA LineNo        ; [3] tokenized line number
  STA Acc0          ; [3]
  LDA LineNoH       ; [3] tokenized line number high
  STA Acc1          ; [3]
  JSR find_line     ; [6] find matching line (Acc -> Ptr, CS=found)
  BCS @replace      ; [2] -> replace line at Ptr
; insert line


@replace:
  LDY #3            ; OPLN, NoL, NoH, Len, Pre
  LDA (Ptr),Y       ; get line length (including header)
  STA B             ; save line length
; 

  SEC
  SBC #5            ; minus header
  STA C             ; save new length
  CMP EmitOfs       ; compare new length
  BEQ @copyin       ; -> same length, no need to shift program

  LDA Ptr
  STA Src           ; Dst = Ptr
  CLC
  ADC B             ; add 
  LDA PtrH
  STA DstH
  JSR mem_copy      ; from (Src) to (Dst) with XY=size (uses A,X,Y,F,Src,Dst)
@copyin:
  ; XXX


; @@ del_line
; delete the program line at LineNo
del_line:
  ; XXX
  RTS


; ------------------------------------------------------------------------------
; PAGE 5 - Statement Tokens

ORG BasROM+$300
stmt_page:

; Statement Index
stmt_kwi:
  DB (kws_at - stmt_page) ; @
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

; $8x-9x more keywords to follow (same first letter) -$40
; $Cx-Dx last keyword in list (for this letter)      -0
; (ORA #$40 before emit -> $Cx-Dx for statements)

OP_LN      = $C0   ; start-of-line
OP_CLS     = $C1
OP_CLOSE   = $C2
OP_CLEAR   = $C3
OP_DATA    = $C4
OP_DIM     = $C5
OP_ELSE    = $C6   ; ELSE with <length>     (OP_ELSE,$xx vs source "EL.")
OP_END     = $C7
OP_FOR     = $C8
OP_GOTO    = $C9
OP_GOSUB   = $CA
OP_IF      = $CB   ; IF <else-ofs> <cond> (THEN1,0xNN | THEN2,0xNN,0xMM | THEN | ε)   [OP_IF,$nn vs "IF"]
OP_INPUT   = $CC
OP_LET     = $CD
OP_LINE    = $CE
OP_LOAD    = $CF
OP_LIST    = $D0
OP_NEXT    = $D1
OP_NEW     = $D2
OP_OPEN    = $D3
OP_PRINT   = $D4
OP_PLOT    = $D5
OP_POKE    = $D6
OP_READ    = $D7
OP_RESTORE = $D8
OP_RETURN  = $D9
OP_REM     = $DA
OP_RUN     = $DB
OP_SOUND   = $DC
OP_SAVE    = $DD

kws_at:
kws_a:
kws_b:
kws_c:
kw_cls    DB "CLS",      OP_CLS    -0     ; bit 6 set for more ($C0)
kw_close  DB "CLOSE",    OP_CLOSE  -0     ; bit 6 set for more ($C0)
kw_clear  DB "CLEAR",    OP_CLEAR  -$40   ; bit 6 clear to end ($C0-$40)
kws_d:
kw_data   DB "DATA",     OP_DATA   -0
kw_dim    DB "DIM",      OP_DIM    -$40
kws_e:
kw_else   DB "ELSE",     OP_ELSE   -0     ; match yields $C6 (-0)
kw_end    DB "END",      OP_END    -$40
kws_f:
kw_for    DB "FOR",      OP_FOR    -$40
kws_g:
kw_goto   DB "GOTO",     OP_GOTO   -0
kw_gosub  DB "GOSUB",    OP_GOSUB  -$40
kws_h:
kws_i:
kw_if     DB "IF",       OP_IF     -0
kw_input  DB "INPUT",    OP_INPUT  -$40   ; [#ch,]
kws_j:
kws_k:
kws_l:
kw_let    DB "LET",      OP_LET    -0
kw_line   DB "LINE",     OP_LINE   -0
kw_load   DB "LOAD",     OP_LOAD   -0
kw_list   DB "LIST",     OP_LIST   -$40
kws_m:
kws_n:
kw_next   DB "NEXT",     OP_NEXT   -0
kw_new    DB "NEW",      OP_NEW    -$40
kws_o:
kw_open   DB "OPEN",     OP_OPEN   -$40
kws_p:
kw_print  DB "PRINT",    OP_PRINT  -0     ; [#ch,]
kw_plot   DB "PLOT",     OP_PLOT   -0
kw_poke   DB "POKE",     OP_POKE   -$40
kws_q:
kws_r:
kw_read   DB "READ",     OP_READ     -0
kw_rest   DB "RESTORE",  OP_RESTORE  -0
kw_retr   DB "RETURN",   OP_RETURN   -0
kw_rem    DB "REM",      OP_REM      -0
kw_run    DB "RUN",      OP_RUN      -$40
kws_s:
kw_soun   DB "SOUND",    OP_SOUND  -0
kw_save   DB "SAVE",     OP_SAVE   -$40
kws_t:
kws_u:
kws_v:
kws_w:
kws_x:
kws_y:
kws_z     DB 0,0         ; match_kws needs two

; Statement Reverse Lookup
stmt_rev:                     ; [34] indices MUST match OPCODEs
  DB (kw_cls - stmt_page)     ; OP_CLS
  DB (kw_close - stmt_page)   ; OP_CLOSE
  DB (kw_clear - stmt_page)   ; OP_CLEAR
  DB (kw_data - stmt_page)    ; OP_DATA
  DB (kw_dim - stmt_page)     ; OP_DIM
  DB (kw_else - stmt_page)    ; OP_ELSE
  DB (kw_end - stmt_page)     ; OP_END
  DB (kw_for - stmt_page)     ; OP_FOR
  DB (kw_goto - stmt_page)    ; OP_GOTO
  DB (kw_gosub - stmt_page)   ; OP_GOSUB
  DB (kw_if - stmt_page)      ; OP_IF
  DB (kw_input - stmt_page)   ; OP_INPUT
  DB (kw_let - stmt_page)     ; OP_LET
  DB (kw_line - stmt_page)    ; OP_LINE
  DB (kw_load - stmt_page)    ; OP_LOAD
  DB (kw_list - stmt_page)    ; OP_LIST
  DB (kw_next - stmt_page)    ; OP_NEXT
  DB (kw_new - stmt_page)     ; OP_NEW
  DB (kw_open - stmt_page)    ; OP_OPEN
  DB (kw_print - stmt_page)   ; OP_PRINT
  DB (kw_plot - stmt_page)    ; OP_PLOT
  DB (kw_poke - stmt_page)    ; OP_POKE
  DB (kw_read - stmt_page)    ; OP_READ
  DB (kw_rest - stmt_page)    ; OP_RESTORE
  DB (kw_retr - stmt_page)    ; OP_RETURN
  DB (kw_rem - stmt_page)     ; OP_REM
  DB (kw_run - stmt_page)     ; OP_RUN
  DB (kw_soun - stmt_page)    ; OP_SOUND
  DB (kw_save - stmt_page)    ; OP_SAVE


; @@ skip_spc
skip_spc:          ; tokenize - skip spaces
@loop:             ; Y=ofs, A,X=next-char (EQ if zero)
  LDA LineBuf,Y    ; [4] next input char
  INY              ; [2] advance input (assume match)
  CMP #32          ; [2] was it space?
  BEQ @loop        ; [2] -> loop [+1]
  DEY              ; [2] undo advance (didn't match)
  TAX              ; [2] set EQ/NE (used by 3 callers)
  RTS              ; [6] -> A,X=next-char (EQ if zero)

; @@ is_alpha
is_alpha:          ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  AND #$DF         ; [2] lower -> upper (clear bit 5)
  SEC              ; [2] for subtract
  SBC #64          ; [2] make '@' be 0
  CMP #27          ; [2] 27 letters including `@` (CS if >= 27)
  RTS              ; [6] -> A=az-index CC=alpha [14]

; @@ is_digit
is_digit:          ; A=char -> A=[0..9], CC=found (preserves X,Y)
  SEC              ; [2] for subtract
  SBC #48          ; [2] make '0' be 0
  CMP #10          ; [2] 10 digits (CS if >= 10)
  RTS              ; [6] -> A=digit CC=found [12]

; @@ print_u16
; print a U16 in Acc
print_u16:          ; Acc=U16 (uses A,X)
  LDA #0
  STA Acc2
  STA AccE
  JMP num_print     ; from Acc (uses A,X)


; ------------------------------------------------------------------------------
; PAGE 6 - Expression Tokens

expr_page = BasROM+$400

; Expression Index (starts at $3F9)
expr_kwi:
  DB (expr_at - expr_page) ; @
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


; end-of-stmt opcodes

;; no args
;OP_LN      = $C0   ; immediate
;OP_CLS     = $C1   ; immediate
;OP_CLEAR   = $C2   ; immediate
;OP_DATA    = $C3   ; immediate -> skip line
;OP_ELSE    = $C4   ; immediate -> skip line
;OP_END     = $C5   ; immediate -> to REPL
;OP_NEW     = $C6   ; immediate
;OP_RETURN  = $C7   ; immediate
;OP_REM     = $C8   ; immediate -> skip line   16 x immediate
;; syntax
;OP_DIM     = $C9   ; syntax VAR(exp)
;OP_FOR     = $CA   ; syntax VAR = exp TO exp [STEP exp]
;OP_IF      = $CB   ; syntax IF exp THEN [ln] -> find ELSE
;OP_INPUT   = $CC   ; syntax INPUT ..
;OP_PRINT   = $CD   ; syntax PRINT ..
;OP_LET     = $CE   ; syntax VAR = exp
;OP_NEXT    = $CF   ; syntax [VAR]
;OP_READ    = $D0   ; syntax {VAR} ..
;; EOL
;OP_CLOSE   = $D1   ; EOL #n     -> A1  (EOR #$70)
;OP_GOTO    = $D2   ; EOL exp
;OP_GOSUB   = $D3   ; EOL exp
;OP_RESTORE = $D4   ; EOL exp
;OP_PLOT    = $D5   ; EOL exp,exp
;OP_POKE    = $D6   ; EOL exp,exp
;OP_SOUND   = $D7   ; EOL exp,exp
;OP_LINE    = $D8   ; EOL exp,exp,exp,exp
;OP_LIST    = $D9   ; EOL [exp],[exp]
;OP_LOAD    = $DA   ; EOL [#n] str$ [exp]
;OP_OPEN    = $DB   ; EOL [#n] str$ [exp]
;OP_RUN     = $DC   ; EOL [#n] str$ [exp]
;OP_SAVE    = $DD   ; EOL [#n] str$ [exp]



; EXPRESSION TOKENS

; numbers (non-operator)
OP_I0    = $80     ; 1-byte (OP_I0 + [0-9])
OP_ELSEX = OP_ELSE-$40 ; $86 (ELSE in expr context)
OP_INT2  = $8A     ; 2-byte (opc|int8)
OP_INT3  = $8B     ; 3-byte (opc|int16)
OP_INT4  = $8C     ; 4-byte (opc|int24)
OP_FLT2  = $8D     ; 2-byte (opc|mant8)         [".X" = 0.X]
OP_FLT3  = $8E     ; 3-byte (opc|exp8|mant8)    ["1.2"; "2.55"; "10.2"]
OP_FLT4  = $8F     ; 4-byte (opc|exp8|mant16)   ["99.99", "1.9876"]
OP_FLT5  = $90     ; 5-byte (opc|exp8|mant24)   ["987654.3", "9.876543"]
; strings (non-operator)
OP_STR   = $91     ; string literal
; unary operators (highest precedence, evaluated post-fix, right-associative!)
OP_NEG   = $92     ; 6 unary negate `-` (replaces OP_SUB)
OP_NOT   = $93     ; 6 unary NOT
; unary functions (high precedence, evaluated post-fix, right-associative!)
OP_ABS   = $94     ; 6 unary fn (arg)
OP_ASC   = $95     ; 6 unary fn (arg$)
OP_CHR   = $96     ; 6 unary fn (arg)
OP_INT   = $97     ; 6 unary fn (arg)
OP_JOY   = $98     ; 6 unary fn (arg)
OP_KEY   = $99     ; 6 unary fn (arg)
OP_LEN   = $9A     ; 6 unary fn (arg$)
OP_PEEK  = $9B     ; 6 unary fn (arg)
OP_STR   = $9C     ; 6 unary fn (arg)
OP_LEFT  = $9D     ; 6 unary fn (arg$, arg)
OP_MID   = $9E     ; 6 unary fn (arg$, arg, [arg])
OP_RIGHT = $AF     ; 6 unary fn (arg$, arg)
OP_SGN   = $A0     ; 6 unary fn (arg)
OP_USR   = $A1     ; 6 unary fn (arg)
OP_VAL   = $A2     ; 6 unary fn (arg$)
OP_RND   = $A3     ; 6 unary fn ([arg])
OP_TIME  = $A4     ; 6 unary fn (dummy?)
; infix binary (from highest to lowest, left-associative)
OP_MUL   = $A5     ; 5 binary op  LSR for prec
OP_DIV   = $A6     ; 5 binary op
OP_ADD   = $A7     ; 4 binary op
OP_SUB   = $A8     ; 4 binary op
OP_EQ    = $A9     ; 3 binary `=`
OP_NE    = $AA     ; 3 binary
OP_LT    = $AB     ; 3 binary `<`
OP_LE    = $AC     ; 3 binary
OP_GT    = $AD     ; 3 binary `>`
OP_GE    = $AE     ; 3 binary
OP_AND   = $AF     ; 2 binary op
OP_OR    = $B0     ; 1 binary op
; open paren (lowest precedence)
OP_LPAR  = $B1     ; 0 open parenthesis (lowest [never forced to eval], skips apply phase, always pushed)
OP_RPAR  = $B2     ; 0 close parenthesis (lowest, forces all ops to eval up to OP_LPAR [which always stops eval])

; keywords
OP_AT    = $BB     ; PRINT stmt
OP_STEP  = $BC     ; FOR stmt
OP_TO    = $BD     ; FOR stmt
OP_THEN  = $BE     ; IF stmt
OP_TAB   = $BF     ; PRINT stmt

expr_at:
expr_a:
ex_at   DB "AT",      OP_AT     +$40     ; AT(x,y) in PRINT
ex_abs  DB "ABS",     OP_ABS    +$40     ; fn (0,0)  bit 6 set for more ($80+$40)
ex_asc  DB "ASC",     OP_ASC    +$40     ; fn (0,1)  bit 6 clear to end ($80)
ex_and  DB "AND",     OP_AND    +0       ; binary op
expr_b:
expr_c:
ex_chr  DB "CHR$",    OP_CHR    +0       ; fn$ (1,1)
expr_d:
expr_e:
ex_else DB "ELSE",    OP_ELSEX  +0       ; $C6-$40 = $86
expr_f:
expr_g:
expr_h:
expr_i:
ex_int  DB "INT",     OP_INT    +0       ; fn (0,1)
expr_j:
ex_joy  DB "JOY",     OP_JOY    +0       ; JOY(n) joystick direction
expr_k:
ex_key  DB "KEY",     OP_KEY    +0       ; KEY(n) key down test
expr_l:
ex_len  DB "LEN",     OP_LEN    +$40     ; fn-or-fn# (B,1) 1st is $
ex_lft  DB "LEFT$",   OP_LEFT   +0       ; fn$ (1,2) 1st is $
expr_m:
ex_mid  DB "MID$",    OP_MID    +0       ; fn$ (1,3) 1st is $
expr_n:
ex_not  DB "NOT",     OP_NOT    +0       ; unary op
expr_o:
ex_or   DB "OR",      OP_OR     +0       ; binary op
expr_p:
ex_peek DB "PEEK",    OP_PEEK   +0       ; fn(1)
expr_q:
expr_r:
ex_rgt  DB "RIGHT$",  OP_RIGHT  +$40     ; fn$ (1,2) 1st is $
ex_rnd  DB "RND",     OP_RND    +0       ; fn (0,1)
expr_s:
ex_str  DB "STR$",    OP_STR    +$40     ; fn$ (1,1) 1st is $
ex_sgn  DB "SGN",     OP_SGN    +$40     ; fn (0,1)
ex_step DB "STEP",    OP_STEP   +0       ; `FOR` keyword
expr_t:
ex_time DB "TIME",    OP_TIME   +$40     ; no-arg (0,0)
ex_to   DB "TO",      OP_TO     +$40     ; `FOR` keyword
ex_then DB "THEN",    OP_THEN   +$40     ; `IF` keyword
ex_tab  DB "TAB",     OP_TAB    +0       ; fn (0,1)
expr_u:
ex_usr  DB "USR",     OP_USR    +0       ; fn (0,1)
expr_v:
expr_w:
expr_x:
expr_y:
expr_z:
ex_val  DB "VAL",     OP_VAL    +0       ; fn (0,1)
        DB 0,0        ; match_kws needs two

expr_ops:
ex_add  DB "+",       OP_ADD    +$40     ; operator
ex_sub  DB "-",       OP_SUB    +$40     ; operator
ex_mul  DB "*",       OP_MUL    +$40     ; operator
ex_div  DB "/",       OP_DIV    +$40     ; operator
ex_eq   DB "=",       OP_EQ     +$40     ; operator
ex_ne   DB "<>",      OP_NE     +$40     ; operator
ex_lt   DB "<",       OP_LT     +$40     ; operator
ex_le   DB "<=",      OP_LE     +$40     ; operator
ex_gt   DB ">",       OP_GT     +$40     ; operator
ex_ge   DB ">=",      OP_GE     +0       ; operator
        DB 0,0        ; match_kws needs two

; Expression Reverse Lookup
expr_rev:                  ; 
  DB (ex_abs - expr_page)  ; OP_ABS
  DB (ex_asc - expr_page)  ; OP_ASC
  DB (ex_chr - expr_page)  ; OP_CHR
  DB (ex_int - expr_page)  ; OP_INT
  DB (ex_joy - expr_page)  ; OP_JOY
  DB (ex_key - expr_page)  ; OP_KEY
  DB (ex_len - expr_page)  ; OP_LEN
  DB (ex_lft - expr_page)  ; OP_LEFT
  DB (ex_mid - expr_page)  ; OP_MID
  DB (ex_peek - expr_page) ; OP_PEEK
  DB (ex_rgt - expr_page)  ; OP_RIGHT
  DB (ex_rnd - expr_page)  ; OP_RND
  DB (ex_str - expr_page)  ; OP_STR
  DB (ex_sgn - expr_page)  ; OP_SGN
  DB (ex_time - expr_page) ; OP_TIME
  DB (ex_usr - expr_page)  ; OP_USR
  DB (ex_val - expr_page)  ; OP_VAL
  ; operators
  DB (ex_and - expr_page)  ; OP_AND   operator
  DB (ex_not - expr_page)  ; OP_NOT   operator
  DB (ex_or - expr_page)   ; OP_OR    operator
  ; keywords
  DB (ex_at - expr_page)   ; OP_AT    keyword
  DB (ex_step - expr_page) ; OP_STEP  keyword
  DB (ex_to - expr_page)   ; OP_TO    keyword
  DB (ex_then - expr_page) ; OP_THEN  keyword
  DB (ex_tab - expr_page)  ; OP_TAB   keyword
; operators
  DB (ex_add - expr_page)  ; OP_ADD   binary op
  DB (ex_sub - expr_page)  ; OP_SUB   binary op
  DB (ex_mul - expr_page)  ; OP_MUL   binary op
  DB (ex_div - expr_page)  ; OP_DIV   binary op
  DB (ex_eq - expr_page)   ; OP_EQ    binary op
  DB (ex_ne - expr_page)   ; OP_NE    binary op
  DB (ex_lt - expr_page)   ; OP_LT    binary op
  DB (ex_le - expr_page)   ; OP_LE    binary op
  DB (ex_gt - expr_page)   ; OP_GT    binary op
  DB (ex_ge - expr_page)   ; OP_GE    binary op


; @@ Statement Dispatch
; jump table (30 entries)
stmt_l:
  DB <do_ln        ; OP_LN      = $C0
  DB <do_cls       ; OP_CLS     = $C1
  DB <do_close     ; OP_CLOSE   = $C2
  DB <do_clear     ; OP_CLEAR   = $C3
  DB <do_data      ; OP_DATA    = $C4
  DB <do_dim       ; OP_DIM     = $C5
  DB <do_else      ; OP_ELSE    = $C6
  DB <repl         ; OP_END     = $C7
  DB <do_for       ; OP_FOR     = $C8
  DB <do_goto      ; OP_GOTO    = $C9
  DB <do_gosub     ; OP_GOSUB   = $CA
  DB <do_if        ; OP_IF      = $CB
  DB <do_input     ; OP_INPUT   = $CC
  DB <do_let       ; OP_LET     = $CD
  DB <do_line      ; OP_LINE    = $CE
  DB <do_load      ; OP_LOAD    = $CF
  DB <do_list      ; OP_LIST    = $D0
  DB <do_next      ; OP_NEXT    = $D1
  DB <do_new       ; OP_NEW     = $D2
  DB <do_open      ; OP_OPEN    = $D3
  DB <do_print     ; OP_PRINT   = $D4
  DB <do_plot      ; OP_PLOT    = $D5
  DB <do_poke      ; OP_POKE    = $D6
  DB <do_read      ; OP_READ    = $D7
  DB <do_restore   ; OP_RESTORE = $D8
  DB <do_return    ; OP_RETURN  = $D9
  DB <do_rem       ; OP_REM     = $DA
  DB <do_run       ; OP_RUN     = $DB
  DB <do_sound     ; OP_SOUND   = $DC
  DB <do_save      ; OP_SAVE    = $DD
stmt_h:
  DB >do_ln        ; OP_LN      = $C0
  DB >do_cls       ; OP_CLS     = $C1
  DB >do_close     ; OP_CLOSE   = $C2
  DB >do_clear     ; OP_CLEAR   = $C3
  DB >do_data      ; OP_DATA    = $C4
  DB >do_dim       ; OP_DIM     = $C5
  DB >do_else      ; OP_ELSE    = $C6
  DB >repl         ; OP_END     = $C7
  DB >do_for       ; OP_FOR     = $C8
  DB >do_goto      ; OP_GOTO    = $C9
  DB >do_gosub     ; OP_GOSUB   = $CA
  DB >do_if        ; OP_IF      = $CB
  DB >do_input     ; OP_INPUT   = $CC
  DB >do_let       ; OP_LET     = $CD
  DB >do_line      ; OP_LINE    = $CE
  DB >do_load      ; OP_LOAD    = $CF
  DB >do_list      ; OP_LIST    = $D0
  DB >do_next      ; OP_NEXT    = $D1
  DB >do_new       ; OP_NEW     = $D2
  DB >do_open      ; OP_OPEN    = $D3
  DB >do_print     ; OP_PRINT   = $D4
  DB >do_plot      ; OP_PLOT    = $D5
  DB >do_poke      ; OP_POKE    = $D6
  DB >do_read      ; OP_READ    = $D7
  DB >do_restore   ; OP_RESTORE = $D8
  DB >do_return    ; OP_RETURN  = $D9
  DB >do_rem       ; OP_REM     = $DA
  DB >do_run       ; OP_RUN     = $DB
  DB >do_sound     ; OP_SOUND   = $DC
  DB >do_save      ; OP_SAVE    = $DD
stmt_chk = $DE


; ------------------------------------------------------------------------------
; PAGE 5 - Commands

ORG BasROM+$500

DB "CMD"

; @@ LIST
; display program listing
do_list:            ; args are tokenized
  JSR do_expr_i     ; 
  LDA (CODE),Y      ; next op
  CMP #OP_I0        ; is it a number?
  BCC @list         ; -> no line number
  ;JSR xxx_u16       ; parse number at Y -> Y,Acc,NE=found (uses A,B,X)
  JSR find_line     ; find matching line (Acc01 -> Ptr [nearest])
  LDA Ptr           ; copy found (or subsequent) line pointer
  STA CODE          ; 
  LDA PtrH          ; 
  STA CODEH         ; 
  JSR skip_spc      ; Y=ofs -> A,X=next-char (EQ if zero)
  CMP #44           ; comma?
  BNE @list         ; -> list (N .. N)
  INY               ; skip comma
  ;JSR xxx_u16       ; parse number at Y -> Y,Acc,NE=found (uses A,B,X)
  JSR find_line     ; find matching line (Acc01 -> Ptr [nearest])
@list:
  LDY #1            ; skip OP_LINE
  LDA (CODE),Y      ; get LineL
  STA Acc0          ; set Acc
  INY               ; skip LineL
  LDA (CODE),Y      ; get LineH
  STA Acc1          ; set Acc
  INY               ; skip LineH
  AND Acc0          ; (Acc0 AND Acc1)
  CMP #255          ; is it 0xFFFF
  BEQ @ends         ; -> end of program
  JSR print_u16     ; print Acc01 (uses A,X)
  LDA #32           ; space
  JSR wrchr         ; print char (A=char, uses A,X) preserves Y •••
  INY               ; skip LineLen
@stmt:
@ends:
  JMP do_stmt

do_save:
  JMP do_stmt

do_new:
  JMP repl          ; -> back to REPL

; @@ set_prog
; set up to run BASIC statements (AX=ptr)
set_prog:
  STA CODEH         ; CODE page
  STX CODE          ; CODE ofs
  LDY #0            ; interpreter code offset
  STY Data          ; clear data pointer
  STY DataH         ; clear data pointer
  STY OpTop         ; clear operator stack
  RTS

; @@ do_clear
; clear all variables (statement)
do_clear:
  JSR clear
  JMP do_stmt

; clear all BASIC variables (used by do_run)
clear:
  ; reset free space = top of program (clear variables)
  LDA TopPtr
  STA FreePtr
  LDA TopPtrH
  STA FreePtrH
  ; reset string heap = top of memory (clear strings)
  LDA MemSize
  STA HeapPtrH
  LDA #0
  STA HeapPtr
  LDX #51           ; clear 52-bytes VarPtrs
@lp:
  STA VarPtrs,X     ; A=0
  DEX
  BPL @lp
  RTS


; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

ALIGN 16
DB "RUN"


; 563 bytes free
; 
; TIME interrupt, access (20 bytes?) = 504 bytes
; SOUND implementation (40 bytes?)
; Cassette load/save (128 bytes?)
; Floating Point... (256 bytes?!)
; LINE routine (60 bytes?)
; JOY, KEY input
; PEEK, USR
; RND generator
; ABS, SGN, INT
; EQ, NE, LT, LE, GT, GE
; AND, OR, NOT
; LEN, LEFT$, MID$, RIGHT$, ASC, CHR$, STR$, VAL -- remove LEFT$/RIGHT$ ?
; DIM allocation
; VAR allocation
; String compaction!

; control frame tags
TAG_FOR    = $F0
TAG_GOSUB  = $F1

; variable tags
VT_NONE = 0
VT_NUM = $80
VT_STR = $81
VT_NUM_ARR = $82


; --- DISPATCH ---

; @@ code_add_y
; add code offset Y to CODE (used for PRINT)
code_add_y:
  TYA            ; [2] get accumulated Y
  LDY #0         ; [2] reset Y
  CLC            ; [2]
  ADC CODE       ; [3] add Y to CODE
  STA CODE       ; [3] update CODE
  BCC @done      ; [2] -> no overflow [+1]
  INC CODEH      ; [5]
@done:
  RTS

do_syn0:
  LDY #<msg_syn
  JMP report_err

; CLOSE: expect '#' expr
;        verify channel is open;
;        flush any queued data;
;        mark channel closed
do_close:
  JSR m_chan
  BCC do_syn0
  ; close it
  JMP do_stmt      ; -> next stmt

; @@ do_run
; start running the BASIC program
do_run:
  JSR clear      ; [6] clear all vars
  LDA #>BaseAdr  ; [2] copy BaseAdr into CODE
  LDX #<BaseAdr  ; [2]
  JSR set_prog   ; [6] set up for execution
  LDA (CODE),Y   ; [5] load token
  CMP #OP_LN     ; [2] start of line?
  BNE do_syn0    ; [2] -> syntax error
  INY            ; [2]
  ; +++ fall through to @@ do_ln +++

; @@ do_ln
; start a new line: fold Y into CODE.
; assumes (CODE),Y points at OP_LN.
do_ln:           ; advance past line header; add Y to CODE
  TYA            ; [2] get accumulated Y
  LDY #3         ; [2] skip (LineLo,LineHi,LineLen)
  CLC            ; [2]
  ADC CODE       ; [3] add Y to CODE
  STA CODE       ; [3] update CODE
  BCC do_stmt    ; [2] -> no overflow [+1]
  INC CODEH      ; [5]
  ; +++ fall through to @@ do_stmt +++

; @@ do_stmt
; STMT: expect a statement token; jump to statement handler,
;       otherwise, if '=' jump to FN return statement,
;       otherwise jump to LET statement (VAR = ...)
do_stmt:
  LDA (CODE),Y   ; [5] load token
  INY            ; [2] advance CODE
  BPL do_let     ; [2] -> implied LET statement [+1]
  ; token dispatch
  TAX            ; [2]
  LDA stmt_l,X   ; [4]
  STA Src        ; [3]
  LDA stmt_h,X   ; [4]  XXX replace with JMP -> JMP saves 4 cycles
  STA SrcH       ; [3]
  JMP (Src)      ; [5]  // 30 total  (XXX write $C0+ token into JMP in RAM /18)


; --- LET, DIM ---

do_let:          ; assign VAR[$] = Expr                              (40b)
  JSR find_var   ; [6] find VAR matching Y=ofs -> Ptr=var, Y=slot-ofs, A=tag, B=CodeOfs; report not found
  AND #1         ; [2] num/str flag
  BNE @str       ; [2] -> str [+1]
  JSR eval_n     ; [6] evaluate numeric expression -> Acc
  LDA Acc0       ; [3] 
  STA (Ptr),Y    ; [6] write to Var0
  INY            ; [2]
  LDA Acc1       ; [3] 
  STA (Ptr),Y    ; [6] write to Var1
  INY            ; [2]
@scpy:
  LDA Acc2       ; [3] 
  STA (Ptr),Y    ; [6] write to Var2
  INY            ; [2]
  LDA AccE       ; [3] 
  STA (Ptr),Y    ; [6] write to VarE
  LDY B          ; [3] restore Y=CodeOfs
  JMP do_stmt     ; -> next stmt
@str:
  JSR eval_s     ; [6] evaluate string expression -> Acc2E (StrPtr)
  JMP @scpy      ; [3] -> copy str ptr to slot


; DIM: expect VAR '(' DIM-expr ')'
;      add var to var-list;
;      allocate array memory at TOP or HEAP?
do_dim:
  LDA #VT_NUM_ARR ; variable tag
  JSR bind_var    ; -> bind a new variable
  JSR do_expr_i   ; -> evaluate integer expression (dimension)
  ; XX allocate array
  ; XX attach to var?
  JMP do_stmt     ; -> next stmt


; --- FOR, NEXT ---

; FOR: expect VAR; '='; expr 'TO' expr ['STEP' expr]
;      push FOR loop on control stack; save address;
;           jump to STMT loop
do_for:
  LDA #VT_NUM     ; variable tag
  JSR bind_var    ; [12+] -> evaluate variable (onto stack) [2]
  JSR do_expr_n   ; [12+] -> evaluate numeric "FROM" expression (onto stack) [4]
  JSR do_expr_n   ; [12+] -> evaluate numeric "TO" expression (onto stack) [4]
  LDA (CODE),Y    ; [5] peek next byte
  BNE @step       ; -> handle "STEP"
@cont:
  LDA #TAG_FOR    ;
  STA B           ; save tag
  JSR push_code   ; save return CODE (uses A,Y -> Y=0)
  LDA B           ; restore tag
  PHA             ; push "FOR" control tag
  JMP do_stmt     ; [3] -> next stmt
@step:
  JSR do_expr_n   ; [12+] -> evaluate numeric "STEP" expression (onto stack) [4]
  BNE @cont       ; -> continue with FOR


; NEXT: optional VAR
;       scan control stack for matching FOR 'VAR' (same address);
;       add STEP to VAR;
;       compare VAR vs TO based on STEP sign;
;       continue -> restore CODE address -> jump to STMT loop
;       otherwise -> pop FOR frame -> jump to STMT loop
do_next:
  JSR find_var    ; find VAR Y -> Ptr=var, Y=slot-ofs, A=tag, B=code-ofs; report not found
@loop:
  LDA #TAG_FOR
  JSR find_frame    ; pop frames until A=TAG
  ; compare VAR=Ptr
  BNE @loop

  ; not found -> No FOR
  ; add STEP to VAR
  ; compare TO value
  ; if less, set CODE to loop address
  ; else pop FOR frame
  JMP do_stmt
@nofor:
  LDY #<msg_for
  JMP report_err


; --- IF, ELSE ---

; IF: parse BOOL-EXPR,
;     optional THEN kw,
;     if expr is true:
;        skip length-byte
;        jump to STMT loop  (THEN<ln> is a STMT)
;     if expr is false:
;        advance CODE by length-byte
;        jump to STMT loop  (ELSE<ln> is a STMT)
do_if:
  JSR do_expr_b  ; [12+] numeric expr (uses A,X,Y,???)
  BCC do_else    ; [2] -> cond is false, advance to ELSE (re-uses do_else code) [+1]
  INY            ; [2] skip length-byte (for ELSE)
  JMP do_stmt    ; [3] -> next stmt


; REM, DATA, ELSE
; advance to end of line (look up line length, add to CODE)
do_rem:
do_data:
do_else:
  LDA (CODE),Y    ; [5] get Length
  STY B           ; [3] save Y
  SEC             ; [2] +1 (advance)
  ADC B           ; [3] Y += Len + 1
  TAY             ; [2]
  JMP do_stmt     ; [6] -> next stmt


; --- GOTO, GOSUB, RETURN ---

; GOTO:
;       scan either dir for matching line;
;       set CODE and jump to do_ln
do_goto:           ; A=next-tok
  JSR do_expr_u16  ; -> stack
go_line:
  JSR find_line    ; find matching line (Ptr -> Ptr, CS=found)
  LDA Ptr
  STA CODE
  LDA PtrH
  STA CODEH
  LDY #0
  JMP do_stmt      ; next stmt


; GOSUB: do_expr_n;
;       scan either dir for matching line;
;       push GOSUB frame on control stack, with return Code address;
;       set Code and jump to LINE start
do_gosub:
  JSR do_expr_u16 ; [12+] -> stack
  JSR push_code   ; [12+] -> save return CODE
  LDA #TAG_GOSUB  ; [2]
  PHA             ; [3]
  JMP go_line     ; [6] -> find matching line and jump to it


; RETURN:
;       scan control stack for matching GOSUB frame;
;       pop GOSUB frame and restore Code address;
;       jump to STMT loop
do_return:
  LDA #TAG_GOSUB
  JSR find_frame  ; pop frames until TAG
  PLA             ; discard tag
  PLA             ; restore saved CODE address
  STA CODE
  PLA
  STA CODEH
  JMP do_stmt


; --- DATA, READ, RESTORE ---

; READ VARs[$]
;      if data-ptr is FFFF, scan for first DATA-line
;      read vars from current data-ptr and advance
;      find vars and assign new values
do_read:
  JSR bind_var    ; find or bind variable (onto stack) [2]
  ; XX if no data, go find first DATA
  ; XX read tag at next data element
  ; XX if type differs, convert to var type
  ; XX copy value to var slot
  JMP do_stmt


; RESTORE [expr_n]
;         scan from line N (or first) for first DATA statement
;         set the data-ptr
do_restore:
  JSR do_expr_u16   ; -> stack
  JSR find_line     ; find matching line (Ptr -> Ptr, CS=found)
  LDA Ptr
  STA Data          ; pointer to next data, low
  LDA PtrH
  STA DataH         ; pointer to next data, high
dostjp:
  JMP do_stmt


; --- PRINT, INPUT ---


; INPUT:
do_input:
@loop:
  LDA (CODE),Y    ; [5] get tag byte
  INY             ; advance (tag byte)
  BEQ dostjp      ; end of input
  ASL             ; bit 7 to carry, bit 6 to sign
  BCS @input      ; -> input var ($80)
  BMI @strlit     ; -> string literal ($40)
  ASL             ; bit 5 to sign
  BMI @nl         ; -> newline ($20)
  BPL @loop       ; -> otherwise
; print a string literal ($40)
@strlit:
  JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
  LDX CODEH       ; string literal high
  LDY CODE        ; string literal low
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  INY             ; +1 for length-byte -> new CODE-ofs
  BNE @loop       ; -> continue  (ASSUMES length <= 254)
; input to var
@input:
  BPL @readln     ; -> no question mark (no $40)
  LDA #$3F        ; '?'
  JSR wrchr       ; ; print '?' (uses A,X,F,Src,Dst) preserves Y
@readln:
  ; TODO bind VAR
  ; TODO store str/num flag
  JSR readline    ; read input (uses A,X,Y,B,C) -> Y=length (EQ if zero)
  ; TODO parse number
  ; TODO set var
  JMP @loop       ; -> continue
@nl:
  JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue


; PRINT
; (MS BASIC: always semi unless explicit comma [stateless])
do_print:
  LDA #0          ; comma mode
  STA D           ; set comma mode
@loop:
  LDA (CODE),Y    ; [5] get tag byte
  CMP #44         ; `,`?
  BEQ @comma      ; -> comma mode
  CMP #59         ; `;`?
  BEQ @semi       ; -> semi mode
@resume:
  INY             ; advance (tag byte)
  ASL             ; discard bit 7
  ASL             ; bit 6 to carry, bit 5 to sign
  BCS @expr       ; -> num/str expr ($40/$60)
  BMI @strlit     ; -> string literal ($20)
  ASL             ; bit 4 to sign
  BMI @nl         ; -> newline ($10)
  ASL             ; bit 3 to sign
  BMI @endsemi    ; -> end of print with semicolon ($08)
  JSR newline     ; newline at end of print (preserves Y)
@endsemi:
  JMP do_stmt     ; end of print (non-zero)
; tab to next field
@comma:
  LDA #9          ; tab: advance to next print zone (5 coumns x 8 spaces)
  JSR wrctl       ; print $09 tab (uses A,X,Src,Dst,F) preserves Y
  BNE do_print    ; -> always (won't be zero), set comma mode
@semi:
  INC D           ; semi mode
  BNE @loop       ; -> always (won't be zero)
; numeric expression
@expr:
  BMI @strexp     ; -> string expr ($60)
  JSR expr_n      ; evaluate numeric expression (to stack)
  JSR num_print   ; print a number on the stack (uses A,X)
  JMP @loop       ; -> continue
; print a string literal ($20)
@strlit:
  JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
  LDX CODEH       ; string literal high
  LDY CODE        ; string literal low
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  INY             ; +1 for length-byte -> new CODE-ofs
  JMP @loop       ; -> continue
; string expression
@strexp:
  JSR expr_s      ; evaluate string expression (to stack)
  PLA
  TAY             ; string addr low
  PLA
  TAX             ; string addr high
  ; TODO ^ if this points to the var, deref again!
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  ; TODO decrement REFs in string?
  JMP @loop       ; -> continue
@nl
  JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue


; --- OPEN, CLOSE ---

; OPEN: open a file
do_open:
  JSR m_chsx
  JMP do_stmt


; LOAD <expr_s>
do_load:
  JSR m_chsx
  ; if running -> do_run
  ; else -> repl
  JMP repl         ; -> back to REPL


; --- POKE ---

; POKE expr_n ',' expr_n
;      write byte to memory
do_poke:
  JSR ex2_u16      ; stack: (Addr,Byte) <-
  ; XXX
  LDX #0           ; index
  STA (Ptr,X)      ; write to memory at (Acc01)
  JMP do_stmt


; --- CLS ---

; CLS: clear the screen
do_cls:
  STY E            ; save CODE offset
  JSR vid_cls      ; (uses A,X,Y)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt


; --- SOUND ---

do_sound:
  JSR ex2_u16      ; stack: (Pitch,Duration) <-
  ; XXX
  JMP do_stmt


; --- GRAPHICS ---

; PLOT: plot a point (x,y)
do_plot:
  JSR ex2_u16      ; stack: (X,Y) <-
  STY E            ; save CODE offset
  JSR gfx_plot     ; -> draw a point
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt

do_line:
  JSR ex4_u16      ; stack: (X,Y) <-
  STY E            ; save CODE offset
  JSR gfx_line     ; -> draw a line
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt


; --- VARIABLES ---

; @@ bind_var
; find or insert named variable for assignment
bind_var:
  RTS


; @@ find_var
; find VAR matching Y=ofs -> Ptr=var, Y=slot-ofs, A=tag, B=code-ofs; report not found      (84b)
find_var:         ; (uses A,X)
; add Y to CODE so we can start at Y=0 (vastly simplifies everything)
  TYA             ; [2]
  CLC             ; [2]
  ADC CODE        ; [3] add Y to CODE
  STA CODE        ; [3] update CODE
  BCC @noch       ; [2] -> no page cross [+1]
  INC CODEH       ; [5]
@noch:
  LDY #0          ; [2] reset Y=0 // [17]
; first letter index
  LDA (CODE),Y    ; [5] get next byte
  AND #$DF        ; [2] lower -> upper (clear bit 5)
  SEC             ; [2] for subtract
  SBC #65         ; [2] make 'A' be 0
  CMP #26         ; [2] 26 letters (CS if >= 26)
  BCS do_syn1     ; [2] -> syntax error // [15]
; copy VarPtr from VarPtrs
  ASL             ; [2] letter * 2
  TAX             ; [2] 0-50 index
  LDA VarPtrs,X   ; [4] var-list pointer low byte
  STA Ptr         ; [3] 
  LDA VarPtrs+1,X ; [4] var-list pointer high byte (zero if no VARs)
  BEQ @novar      ; [2] -> no VARs start with this letter [+1]
  STA PtrH        ; [3]
; compare (CODE),Y to (Ptr),Y until they differ
@next:            ; <- check next VAR
  DEY             ; [2] for pre-increment // [22] (54 setup!)
@cmp:             ; [+15] per char:
  INY             ; [2] pre-increment
  LDA (CODE),Y    ; [5] get next Code byte    (may be $80+ for KW)
  CMP (Ptr),Y     ; [5] equals next VAR byte? (may be $80+ type-tag at end of name)
  BEQ @cmp        ; [2] -> same, continue [+1]
; they differ: is (CODE),Y < $80 (miss)
  BPL @miss       ; [2] -> incomplete CODE match [+1] (VAR match may be complete)
  LDA (Ptr),Y     ; [5] is Ptr,X < $80 (miss)
  BPL @miss       ; [2] -> incomplete VAR match [+1]
; found a match
  STY B           ; [3] -> B = code-ofs
  INY             ; [2] skip [$8x]
  INY             ; [2] skip [NextL]
  INY             ; [2] skip [NextH]
  RTS             ; [6] -> Ptr=var, Y=slot-ofs, A=tag, B=code-ofs // [26] (80+15*n total: 95,110,125..) 
@miss:           ; skip rest of VAR (may be at end already)
  DEY            ; [2] for pre-increment
@xlp:            ; [+9] per char:
  INY            ; [2] pre-increment
  LDA (Ptr),Y    ; [5] is Ptr,X >= $80
  BPL @xlp       ; [2] -> more to go [+1]
; at end of VAR
  INY            ; [2] skip [$8x]
  LDA (Ptr),Y    ; [5] get [NextL]
  TAX            ; [2] save [NextL] -> X
  INY            ; [2] Y++
  LDA (Ptr),Y    ; [5] get [NextH] (zero at end of var-list)
  BEQ @novar     ; [2] -> no more VARs
  STX Ptr        ; [3] set new [PtrL] <- X
  STA PtrH       ; [3] set new [PtrH]
  LDY #0         ; [2] reset Y=0
  BEQ @next      ; [3] -> check next VAR (always)
@novar:          ; no matching VAR found
  LDY #<msg_var
  JMP report_err

do_syn1:
  LDY #<msg_syn
  JMP report_err


; --- HELPERS ---

; DB <m_num2  ; PLOT num, num             u16,u16          -> e_range (good enough)
; DB <m_num2  ; POKE num, num             u16,u8           -> e_range (or modulo)
; DB <m_num2  ; SOUND num, num            u8,u8            -> e_range (or modulo)
; DB <m_num4  ; LINE num, num, num, num   u16,u16,u16,u16  -> e_range (good enough)
; DB <m_numo2 ; LIST [num],[num]          [u16,u16]        -> e_range
; DB <m_chan  ; CLOSE #n                  --
; DB <m_chsx  ; LOAD [#n] str$ [num]      u16/u8
; DB <m_chsx  ; OPEN [#n] str$ [num]      u16/u8
; DB <m_chsx  ; RUN [#n] str$ [num]       u16/u8
; DB <m_chsx  ; SAVE [#n] str$ [num]      u16/u8

m_chan:
  LDA (CODE),Y ; next byte
  CMP #35      ; `#`
  BNE m_clc    ; -> no #channel
m_chan1:
  INY
  LDA (CODE),Y ; expect a digit
  CMP #OP_I0+1 ; #1 is valid
  BCS e_range  ; -> out of range (less than 1)
  CMP #OP_I0+3 ; #2 is valid
  BCC @valid   ; -> valid (less than 3)
  CMP #OP_I0+8 ; #8 is valid (serial)
  BNE e_range  ; -> out of range
@valid:
  AND #15      ; 1,2,8
  STA IOChan   ; set #channel
  SEC          ; 
  RTS          ; CS=found

m_clc:
  CLC
  RTS

e_range:
e_type:

m_comma:
  LDA (CODE),Y ; next byte
  CMP #44      ; is comma?
  BNE do_syn1  ; -> syntax error
  INY
m_ret:
  RTS

m_chsx:
  JSR m_chan   ; optional #channel -> IOChan
  BCC @skip
  JSR m_comma  ; expect a comma
@skip:
  JSR do_expr_s   ; expect a string -> ArgTop
  LDA (CODE),Y ; 
  CMP #44      ; is comma?
  BNE m_ret    ; -> no, done  (XXX string at ArgTop vs number at ArgTop...)
  INY          ;
  JMP do_expr_u16 ; expect a number -> stack (XXX any VAR uses Ptr)



; @@ find_frame
; pop frames until TAG matches, report missing
find_frame:       ; A=Tag
  ; XXX caller frame is in the way...
  TSX
  RTS


; @@ push_code (helper)
; fold Y into CODE and push it on the stack
; advance to the next statement or line
push_code:        ; uses (A,Y) -> Y=0
  LDA (CODE),Y    ; [5] peek next byte                         (optional 11 bytes)
  CMP #OP_LN      ; [2] is it EOL?                             (optional)
  BEQ @newln      ; [2] -> start of next line                  (optional)
  TYA             ; [2] get accumulated Y
  LDY #0          ; [2] reset CODE offset
@push:
  CLC             ; [2]
  ADC CODE        ; [3] add Y to CODE
  PHA             ; [3] push CODE
  LDA CODEH       ; [3]
  ADC #0          ; [2] add carry
  PHA             ; [3] push CODEH
  RTS             ; XXX oops - returns to the pushed CODE
@newln:
  TYA             ; [2] get accumulated Y                      (optional)
  LDY #5          ; [2] skip (OpLn,LineLo,LineHi,LenBk,LenFw)  (optional)
  BNE @push       ; [3] -> now push it                         (optional)


; @@ find_line
; find matching line (Acc01) -> Ptr, CS=found
find_line:
; TODO starts from current CODE and searches towards target
; TODO if not found, return first line greater than LineNo (for insertion)
  RTS


; --- EXPRESSIONS ---




prefix:
; CMP #OP_MUL
; BCS e_syn        ; -> not a prefix operator (greater/equal)

infix:
; CMP #OP_MUL
; BCC e_syn        ; -> not an operator (less)
; CMP #OP_RPAR
; BCS e_syn        ; -> not an operator (greater/equal)
; BEQ @rpar        ; -> close parenthesis (special case)
; TAX
; LDA prec_b,X     ; prec - $A5 (OP_MUL)
; pop-apply lower/same prec
; push oper
; -> prefix

prec_b = prec - $A5
prec:
  DB 5  ; OP_MUL
  DB 5  ; OP_DIV
  DB 4  ; OP_ADD
  DB 4  ; OP_SUB
  DB 3  ; OP_EQ
  DB 3  ; OP_NE
  DB 3  ; OP_LT
  DB 3  ; OP_LE
  DB 3  ; OP_GT
  DB 3  ; OP_GE
  DB 2  ; OP_AND
  DB 1  ; OP_OR



; XXX can't push and also RTS...

; @@ ex4_u16
; parse u16, u16, u16, u16
ex4_u16:
  JSR ex2_u16
  JSR m_comma
  ; +++ fall through +++

; @@ ex2_u16
; parse u16, u16
ex2_u16:
  JSR do_expr_u16  ; -> stack
  JSR m_comma
  ; +++ fall through +++

; @@ do_expr_u16
; evaluate integer expression, range-check u16 -> Ptr
do_expr_u16:
  JSR do_expr_i   ; -> stack (how?!)
  PLA             ; exponent
  BNE do_range
  PLA             ; high byte
  BNE do_range    ; -> out of range, negative, on non-integer
  RTS

; @@ do_range
; report "out of range" error
do_range:
  LDY <msg_rng       ; #RNG
  JMP err_rep        ; -> report error


; @@ do_expr
; evaluate an expression (XXX should be do_expr_n, do_expr_s)   (TODO errors?)
; XXX "PRINT" is the outlier, accepting all types...
; XXX tracked state: expect a comma after each expr except the first?
do_expr:
do_expr_n:
do_expr_b:
do_expr_i:
do_expr_s:
  RTS



; ------------------------------------------------------------------------------
; Numeric Evaluator

ALIGN 16
DB "EVAL"


;prefix:
;  LDA (CODE),Y   ; next opcode
;  BPL @var       ; -> VAR (alpha)
;  CMP #OP_EOP    ; end of prefix?
;  BCS @syn       ; -> Syntax Error (corrupt)
;  TAX            ; as index
;  LDA pretab,X   ; get offset
;  STA PrePtr     ; set prefix pointer
;  JMP (PrePtr)   ; -> dispatch

  ; $80: push oper -> pre (if FUN takes an ARG)
  ; '-': push oper -> pre
  ; 'NOT': push oper -> pre
  ; ^ push these, evaluate at infix (as lowest prec)
  ; var: chk '(' -> array -> (push val, typ) -> inf
  ; ^ BPL
  ; num: (push val, typ) -> inf
  ; ^ BCS
  ; str: (push val, typ) -> inf
  ; ^ BEQ ?
  ; '(': push oper -> pre
  ; ^ BEQ ?
  ; -> corrupt

;@var:
;@syn:

;infix:
  ; (get next op, mask off prec, pop-eval)
  ; cmp ')' -> @clpar
  ; push oper (never apply now)
  ; @clpar: pop oper (expect '(' or 'Missing')

;pop_eval:
  ; oper -> infix tab, range chk -> syn

;num:
;  LDX ArgTop
;  LDA (CODE),Y
;  INY
;  STA $100,X
;  INX
;  STX ArgTop


badprg:
  LDY #<msg_syn
  JMP report_err

eval_s:    ; XXX
  RTS

e_typ1:
  LDY #<msg_typ
  JMP report_err

; @@ eval_n
; evaluate numeric expression -> Acc
eval_n:
  LDA (CODE),Y   ; [5] get next byte
  BMI @bfunc     ; [2] -> BASIC function [8]
  CMP $40        ; [2] below letters?
  BCC @numpf     ; [2] -> number ($3x) or prefix ($2x) [12]
; --- look up variable [11]
  JSR find_var   ; [6] find VAR matching Y=ofs -> Ptr=var, Y=slot-ofs, A=tag, B=CodeOfs; report not found
  AND #1         ; [2] num/str flag
  BNE e_typ1     ; [2] -> not a number [+1]
  LDA (Ptr),Y    ; [5] Num0
  PHA            ; [3] push Num0   (XXX write to Expr stack?)
  INY            ; [2]
  LDA (Ptr),Y    ; [5] Num1
  PHA            ; [3] push Num1
  INY            ; [2]
  LDA (Ptr),Y    ; [5] Num2
  PHA            ; [3] push Num2
  INY            ; [2]
  LDA (Ptr),Y    ; [5] Num3
  PHA            ; [3] push Num3
  LDY B          ; [3] restore CodeOfs
  BNE eval_n     ; [3] -> always [11+12+48=71+find]

@numpf:          ; [12]
  CMP #$30       ; [2] number (>= $30)
  BCS @numbr     ; [2] -> number ($3x) [17]
  CMP #$28       ; [2] '('
  BEQ @dlpar     ; [2] -> do LPAREN [+1]
  CMP #$2D       ; [2] '-'
  BEQ @duneg     ; [2] -> do UNEG [+1]
  CMP #$2B       ; [2] '+'
  BEQ @dupls     ; [2] -> do UPLUS [+1]
  BNE badprg     ; [3] -> otherwise, bad program

@duneg:
  ; push it to operator stack -> eval at next binary op
@dupls:
  ; push it to operator stack -> eval at next binary op
@dlpar:
  ; push it to operator stack -> eval at next binary op

@numbr:          ; [17]
  SEC            ; [2]
  SBC #$30       ; [2] 0-9, i1,i2,i3, f1,f2,f3   ".1" ".12" ".123" "1.23"  (XXX also need f4)
  CMP #10        ; [2] is it below 10?
  BCC @numsd     ; [2] -> single digit [26]
  CMP #$3D       ; [2] is it float >= $3D?
  BCS @numfl     ; [2] -> floating point [30]
  ; ......

@numsd:          ; [26]
  PHA            ; [3] Num0   (XXX write to Expr stack?)
  LDA #0         ; [2]
  PHA            ; [3] Num1
  PHA            ; [3] Num2
  PHA            ; [3] NumE
  BEQ eval_n     ; [3] -> always [43]

@numfl:          ; [30]
  ; ......

@bfunc:          ; [8]
  AND #$1F       ; [2] keep low 5 bits
  TAX            ; [2]
  LDA fntabl,X   ; [4] func ptr low (minus 1)
  PHA            ; [3]
  LDA fntabh,X   ; [4] func ptr high
  PHA            ; [3]
  RTS            ; [6] jump to function [32]


fntabl:          ; BASIC function pointers low
fntabh:          ; BASIC function pointers high  (XXX or single-page?)


; ------------------------------------------------------------------------------
; Numerics

; @@ num_add
; add two 32-bit numbers on the stack (pushed BE->LE)
; [A3][A2][A1][A0][T3][T2][T1][T0][PCH][PCL]
; *** to use the stack, must JMP here (not JSR)
num_add:
  ; +6 bytes (+14 cycles) save return address
  TSX            ; [2] get SP
  LDA $103,X     ; [4] Top3
  ORA $107,X     ; [4] Trm3
; BNE @fpadd     ; [2] -> floating point add [+1] (11)
  CLC            ; [2] no carry in              14
  PLA            ; [4] get Top0  SP++
  ADC $103,X     ; [4] add Term0 $104-1
  STA $103,X     ; [4] replace Term0            +12
  PLA            ; [4] get Top1  SP++
  ADC $103,X     ; [4] add Term1 $105-2
  STA $103,X     ; [4] replace Term1            +12
  PLA            ; [4] get Top2  SP++
  ADC $103,X     ; [4] add Term1 $106-3
  STA $103,X     ; [4] replace Term1            +12
  PLA            ; [4] Top3  (zero for int)     +4
  ; +6 bytes (+14 cycles) restore return address
  RTS            ; [6] // 60                    +6

; @@ num_sub
; subtract two 32-bit numbers on the stack (pushed BE->LE)
; [A3][A2][A1][A0][T3][T2][T1][T0][PCH][PCL]
; *** to use the stack, must JMP here (not JSR)
num_sub:         ; (uses A,X)
  LDX ArgTop     ; [3] top of expr stack (full descending from $180)
  LDA $107,X     ; [4] Dst3 (destination)
  ORA $103,X     ; [4] Top3
; BNE @fpsub     ; [2] -> floating point add [+1] (11)
  SEC            ; [2] no carry in              15
  LDA $104,X     ; [4] get Dst0
  SBC $100,X     ; [4] subtract Top0 $104-1
  STA $104,X     ; [5] set Dst0                +13
  LDA $105,X     ; [4] get Dst0
  SBC $101,X     ; [4] subtract Arg1 $105-2
  STA $105,X     ; [5] set Dst1                +13
  LDA $106,X     ; [4] get Dst0
  SBC $100,X     ; [4] subtract Arg2 $106-3
  STA $106,X     ; [5] set Dst2                +13
  INX            ; [2] ArgTop += 4
  INX            ; [2]
  INX            ; [2]
  INX            ; [2]
  STX ArgTop     ; [3] pop the top expr        +11
  RTS            ; [6] // 71 (was 60)          +6



; ----------------------------------------------------------------------
; Integer Parse / Print

ALIGN 16
DB "NUM"

; @@ num_print
; print a number in Acc (TODO floating point)
num_print:       ; from Acc (uses A,X,B,Acc) preserves Y
  LDA #0         ; [2]
  PHA            ; [3] sentinel
@loop:
  LDA #10        ; [2] divisor = 10
  JSR div_u8     ; [733] Acc=dividend, A=divisor -> Acc=quotient, A=remainder (uses A,X,B,Acc)
  ORA #48        ; [2] 0-9 -> '0'-'9'
  PHA            ; [3] pushes once or more
  LDA Acc0       ; [3]
  ORA Acc1       ; [3]
  ORA Acc2       ; [3]
  BNE @loop      ; [2] -> until zero [+1]
  PLA            ; [4]
@print:
  JSR wrchr      ; [X] print it (uses A,X,F,Src,Dst) preserves Y
  PLA            ; [4]
  BNE @print     ; [2] -> until sentinel [+1]
  RTS

; @@ num_u16
; tokenize a line number (0-65535)
num_u16:         ; Y=ofs (uses A,X,B,Term) -> Acc,Y,CS=found
  JSR skip_spc   ; Y=ofs -> A,X=next-char (EQ if zero)
  STY B          ; save ofs
  JSR num_u24    ; from LineBuf,Y -> Acc,Y=end (uses A,X,Y,Acc,Term,Ptr)
  CPY B          ; number found?
  BEQ @nom       ; -> no match
  LDA Acc2       ; high byte is non-zero (or number is negative)
  ORA AccE       ; or exponent is non-zero (number is float)
  BNE num_range  ; -> out of range (0-65535), negative, on non-integer
  SEC            ; CS=found
  RTS
@nom:
  CLC            ; CC=not-found
  RTS

num_range:
  LDY #<msg_rng  ; #RNG
  JMP err_rep    ; -> report error

; @@ num_val
; parse a 24-bit number with optional sign prefix (TODO: floating point) (TODO: from (Ptr),Y ?)
num_val:         ; from LineBuf,Y -> Y,Acc (uses A,B,X,Term)
  JSR skip_spc   ; [6] Y=ofs -> A,X=next-char (EQ if zero)
  CMP #$2D       ; [2] `-`
  BEQ @minus     ; [2] -> negative [+1]
  JMP num_u24    ; [6] -> (Src),Y -> Acc,Y (uses A,X,Term)
@minus:
  INY            ; [2] skip `-`
  JSR num_u24    ; [6] -> (Src),Y -> Acc,Y (uses A,X,Term)
  ; +++ fall through +++

; @@ num_neg
; one minus Acc (uses A) -> Acc
num_neg:
  SEC            ; [2]
  LDA #0         ; [2]
  TAX            ; [2]
  SBC Acc0       ; [3]
  STA Acc0       ; [3]
  TXA            ; [2]
  SBC Acc1       ; [3]
  STA Acc1       ; [3]
  TXA            ; [2]
  SBC Acc2       ; [3]
  STA Acc2       ; [3]
  BCC err_ovf    ; [2] -> overflow (Acc >= 2^23)
num_done:
  RTS

; @@ num_u24
; parse an unsigned 24-bit number
num_u24:         ; from LineBuf,Y -> Acc,Y=end (uses A,X,Acc,Term)
  LDA #0         ; [2]
  STA Acc0       ; [3] clear result
  STA Acc1       ; [3]
  STA Acc2       ; [3]
  STA AccE       ; [3]
  DEY            ; [2] for pre-increment
@loop:           ; -> 14+76+25 [115]
  INY            ; [2] pre-increment
  LDA LineBuf,Y  ; [4] get next char
  SEC            ; [2]
  SBC #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS num_done   ; [2] >= 10 -> done [+1]
  TAX            ; [2] save digit 0-9
; multiply Acc by 10
  ASL Acc0       ; [5] Acc = Acc*2 (=Val*2)
  ROL Acc1       ; [5]
  ROL Acc2       ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  LDA Acc0       ; [3] Term = Acc (=Val*2)
  STA Term0      ; [3]
  LDA Acc1       ; [3]
  STA Term1      ; [3]
  LDA Acc2       ; [3]
  STA Term2      ; [3]
  ASL Acc0       ; [5] Acc *= 2 (=Val*4)
  ROL Acc1       ; [5]
  ROL Acc2       ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  ASL Acc0       ; [5] Acc *= 2 (=Val*8)
  ROL Acc1       ; [5]
  ROL Acc2       ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  CLC            ; [2] Acc += digit 0-9
  TXA            ; [2]
  ADC Acc0       ; [3]
  BCC @noc       ; [2] -> no carry [+1]
  INC Acc1       ; [5]
  BNE @noc       ; [2] -> no carry [+1]
  INC Acc2       ; [5]
  BEQ err_ovf    ; [2] -> unsigned overflow [+1]
@noc:
  ADC Term0      ; [3] Acc += Term (=Val*10)
  STA Acc0       ; [3]
  LDA Acc1       ; [3]
  ADC Term1      ; [3]
  STA Acc1       ; [3]
  LDA Acc2       ; [3]
  ADC Term2      ; [3]
  STA Acc2       ; [3]
  BCC @loop      ; [2] -> no overflow, continue [+1]
err_ovf:
  LDY #<msg_rng  ; [2] #RNG
  JMP report_err ; [3] -> report overflow



; ----------------------------------------------------------------------
; Integer Multiply / Divide

ALIGN 16
DB "MUL"

; @@ mul_u24
; multiply BCD = Acc * Term (24-bit)
mul_u24:         ; Acc=multiplier Term=multiplicand -> BCD=product (uses A,X,B,C,D)
  LDA #0         ; [2]
  STA B          ; [3] B partial product
  STA C          ; [3] C partial product
  STA D          ; [3] D partial product
  LDX #24        ; [2] 24 bit multiplier
  CLC            ; [2] CF=0
@loop:
  BCS err_ovf    ; [2] -> overflow (multiplicand)
; shift multiplier right, test each bit in turn
  LSR Acc2       ; [5] 0 >> multiplier >> CF
  ROR Acc1       ; [5] CF >> multiplier >> CF
  ROR Acc0       ; [5] CF >> multiplier >> CF
  BCC @skip      ; [2] -> zero bit, no add [+1]
; partial += shifted multiplicand x low-bit of multiplier
  CLC            ; [2] sadly CF=1
  LDA B          ; [3] partial product
  ADC Term0      ; [3] partial += multiplicand
  STA B          ; [3]
  LDA C          ; [3] partial product
  ADC Term1      ; [3] partial += multiplicand
  STA C          ; [3]
  LDA D          ; [3] partial product
  ADC Term2      ; [3] partial += multiplicand
  STA D          ; [3]
  BCS err_ovf    ; [2] -> overflow
@skip:
; shift multiplicand left (×2) into next higher place
  ASL Term0      ; [2] CF << multiplicand << 0
  ROL Term1      ; [5] CF << multiplicand << CF
  ROL Term2      ; [5] XX << multiplicand << CF
  DEX            ; [2]
  BNE @loop      ; [3] -> continue
  RTS            ; [6] -> BCD=product

; @@ div_u8
; divide Acc by a 8-bit divisor (used for num_print)
; long-division method
div_u8:          ; Acc=dividend, A=divisor -> Acc=quotient, A=remainder (uses A,X,Acc,Term0)
  STA Term0      ; [3] set divisor
div_u8_en:
  LDA #0         ; [2] remainder
  LDX #24        ; [2] 24-bit dividend
@loop:
; shift dividend bits left into remainder
  ASL Acc0       ; [5] CF << dividend << 0  (shift 0 into quotient by default)
  ROL Acc1       ; [5] CF << dividend << CF
  ROL Acc2       ; [5] CF << dividend << CF
  ROL            ; [2] remainder << CF
; until remainder >= divisor
  CMP Term0      ; [3] is remainder >= divisor?
  BCC @next      ; [2] -> no, skip subtraction (~2/3 of the time) [+2]
; subtract divisor from remainder
  SBC Term0      ; [3] subtract divisor (CF=1)
; shift 1 into quotient (one times divisor found)
  INC Acc0       ; [5] quotient bit0 = 1
@next:
  DEX            ; [2]
  BNE @loop      ; [3] -> continue division
  RTS            ; [6] return

; @@ div_u24
; divide Acc = Acc / Term remainder BCD (long-division method)
div_u24:         ; Acc=dividend, Term=divisor -> Acc=quotient, BCD=remainder (uses A,X,B,Acc)
  LDA Term1      ; [3]
  ORA Term2      ; [3]
  BEQ div_u8_en  ; [2] -> use div_u8 fast-path
  LDA #0         ; [2] remainder = 0
  STA B          ; [3] remainder = 0
  STA C          ; [3] remainder = 0
  STA D          ; [3] remainder = 0
  LDX #24        ; [2] 24 bits
@loop:
; shift dividend bits left into remainder
  ASL Acc0       ; [5] CF << dividend << 0  (shift 0 into quotient by default)
  ROL Acc1       ; [5] CF << dividend << CF
  ROL Acc2       ; [5] CF << dividend << CF
  ROL B          ; [2] CF << remainder << CF
  ROL C          ; [2] CF << remainder << CF
  ROL D          ; [2] XX << remainder << CF
; until remainder >= divisor
  LDA D          ; [3] high byte
  CMP Term2      ; [3] is remainder >= divisor?
  BCC @next      ; [2] -> less, continue loop [+1]
  BNE @ge10      ; [2] -> greater, do subtraction [+1] (otherwise equal)
  LDA C          ; [3] mid byte
  CMP Term1      ; [3] is remainder >= divisor?
  BCC @next      ; [2] -> less, continue loop [+1]
  BNE @ge10      ; [2] -> greater, do subtraction [+1] (otherwise equal)
  LDA B          ; [3] low byte
  CMP Term0      ; [3] is remainder >= divisor?
  BCC @next      ; [2] -> less, continue loop [+1]
@ge10:           ;
; subtract divisor from remainder
  SEC            ; [2]
  LDA B          ; [3] low byte
  SBC Term0      ; [3] subtract divisor
  STA B          ; [3] new remainder
  LDA C          ; [3] mid byte
  SBC Term1      ; [3] subtract divisor
  STA C          ; [3] new remainder
  LDA D          ; [3] high byte
  SBC Term2      ; [3] subtract divisor
  STA D          ; [3] new remainder
; shift 1 into quotient (one times divisor found)
  INC Acc0       ; [5] quotient bit0 = 1 (shift quotient into Acc)
@next:
  DEX            ; [2]
  BNE @loop      ; [3] -> continue division
  RTS            ; [6] return




; ------------------------------------------------------------------------------
; Sys ROM - GRAPHICS ROUTINES

DB "GFX"

; @@ gfx_plot
; draw a point at (X,Y)
; all params are u8 on the stack: [00XXXXXX][00YYYYYY]<--
gfx_plot:          ; uses (A,X,Y,F)
  PLA              ; [00YYYYYY] pop Y (0..47)
  STA F            ; [00YYYYYY] save Y (keep low bit)
  LSR              ; [000YYYYY] div 2 (0..23)
  TAY              ; [000YYYYY] set text Y coord
  PLA              ; [0XXXXXXX] pop X (0..79)
  PHA              ; [0XXXXXXX] push X (keep low bit)
  LSR              ; [00XXXXXX] div 2 (0..39)
  TAX              ; [00XXXXXX] X = col
  TYA              ; [000YYYYY] A = row
  JSR txt_at       ; calculate TXTP address: A=row X=col (uses A,X,Y)
; compute semigraphics
  PLA              ; [0XXXXXXX] pop X
  ROR              ; [00XXXXXX] -> CF=X0
  LDA F            ; [00YYYYYY]
  AND #1           ; [0000000Y]
  ROL              ; [000000YX]
  TAX              ; as index
; update screen
  LDY #0
  LDA (TXTP),Y     ; read text screen
  CMP #240         ; is it >= 240?
  BCS @merge       ; -> merge semigraphics
  TYA              ; empty cell
@merge:
  ORA semigr,X     ; OR in semigraphics
  STA (TXTP),Y     ; write back
@done:
  RTS

semigr:
  DB 248   ; top-left
  DB 244   ; top-right
  DB 242   ; bottom-left
  DB 241   ; bottom-right


; @@ gfx_line
; draw a line from (X0,Y0 to X1,Y1)
gfx_line:
  RTS



; ------------------------------------------------------------------------------
; PAGE X - Debug

;ALIGN 16
;DB "DBG"
;
;; DEBUG routine
;debug:
;  LDY EmitOfs       ; [DEBUG]
;  LDA #0            ; [DEBUG]
;  STA EmitBuf,Y     ; [DEBUG]
;  TAY               ; [DEBUG]
;@lp:
;  LDA EmitBuf,Y     ; [DENUG]
;  BEQ @repl         ; [DEBUG]
;  STA Acc0          ; [DEBUG]
;  LDA #0            ; [DEBUG]
;  STA Acc1          ; [DEBUG]
;  STA Acc2          ; [DEBUG]
;  STA AccE          ; [DEBUG]
;  JSR dbghex        ; [DEBUG] (uses A,X,F,Src,Dst) preserves Y
;  INY               ; [DEBUG]
;  BNE @lp           ; [DEBUG]
;@repl:
;  JMP repl
;
;
;; @@ dbghex
;dbghex:
;  JSR prhex         ; [DEBUG] A=byte; (uses A,X,F,Src,Dst) preserves Y
;  LDA #32           ; [DEBUG]
;  JSR wrchr         ; [DEBUG] A=char; (uses A,X,F,Src,Dst) preserves Y
;  RTS
;
;; @@ prhex
;; print a byte in hex
;prhex:              ; A=byte; (uses A,X,F,Src,Dst) preserves Y
;  PHA               ; save A
;  LSR               ; shift top 4 bits down
;  LSR               ; 
;  LSR               ; 
;  LSR               ; 
;  JSR @dig          ; print digit
;  PLA               ; restore A
;  AND #15           ; keep low 4 bits
;@dig:
;  CMP #10           ; is it >10 ?
;  BCS @let          ; -> yes, print letter (CF=1)
;  ADC #$FA          ; add 48 - 54 (-6)
;  CLC               ; set CF=0 (for digits >=6)
;@let:               ; 
;  ADC #54           ; 'A'65 - 10 - 1(CF)
;  JMP wrchr         ; -> write char (uses A,X,F,Src,Dst) preserves Y





; ------------------------------------------------------------------------------
; ------------------------------------------------------------------------------
; SYSTEM ROM - 1K

ORG BasROM+$C6A

; Sound interrupt
; Cassette I/O
; Serial I/O

; @@ key_scan     (139b code; 267b including tables)
; scan the keyboard matrix for a keypress
; on pressing a new key: (no CurrKey) new key -> CurrKey (preserve dead key)
; on pressing a new key: (no DeadKey) new key -> CurrKey -> DeadKey (shift down)
; on pressing a new key: (current AND dead) -> ignore newkey, complete scan
; on released current key: clear current key (preserve dead key)
; on released dead key: clear dead key (preserve current key)
; [..ABCDE....]
;    ^hd  ^tl     ; empty when hd==tl, full when tl+1==hd
keyscan:          ; uses A,X,Y returns nothing (CANNOT use B,C,D,E)
  LDA #0          ; [2] zero
  STA IRQTmp2     ; [3] clear key-hit flags (N=Hit.C | V=Hit.D)
  STA ModKeys     ; [3] clear ModKeys (set again if any modkeys are down)   2
  LDY #8          ; [2] last key row (modifiers)
; ...
@row_lp:          ; -> [13] cycles (Y=row)
  STY IO_KEY      ; [3] set keyscan row (0-7)              0µs (-> 7+3=10µs after prior)
  NOP             ; [2] delay                              2µs
  LDX IO_KEY      ; [3] read col_bitmap                    2+3µs read 5/0.89Mhz = 5.6µs settle
  BNE @key_hit    ; [2] -> one or more keys pressed [+1]   2µs -> 1µs (3µs)
@row_cont:
  DEY             ; [2] prev row                           2µs
  BPL @row_lp     ; [3] go again, until Y<0                2+2+3µs -> (7µs)
; ...
@finish:          ; check for key ups
  LDA #0          ; [2] A=0
  BIT IRQTmp2     ; [3] check key-hit flags (N=Hit.C | V=Hit.D)
  BMI @key1dn     ; [2] -> CurrKey is still down [+1]
  STA CurrKey     ; [3] clear CurrKey (to $00)
@key1dn:
  BVS @key2dn     ; [2] -> DeadKey is still down [+1]
  STA DeadKey     ; [3] clear DeadKey (to $00)
@key2dn:
  LDY CurrKey     ; [3] get current phys_key
  BEQ @done       ; [2] -> no current key
  LDA #4          ; [2] repeat rate: 4 frames
  DEC KeyRep      ; [5] count down to auto-repeat
  BEQ @inskey     ; [2] -> repeat current key (Y=phys_key) [+1]
  RTS             ; [6] TOTAL Scan ~[110] cycles
; ...
@key_hit:         ; X=col_bitmap(!=0) Y=row
; debounce check 
  CPX IO_KEY      ; [3] check if stable                    3+3µs read 6/0.89Mhz = 6.7µs verify
  BNE @row_lp     ; [2] if not -> try again
  CPY #8          ; [2] is ModKeys row?
  BEQ @mods       ; [2] -> handle ModKeys [+1]
  STY IRQTmp      ; [3] save keyscan row for @cont_bsf
  TYA             ; [2] active keyscan row
  ASL             ; [2] row * 8
  ASL             ; [2] 
  ASL             ; [2] 
  TAY             ; [2] scantab offset = row*8 as index  (X=col_bitmap Y=row*8 IRQTmp=row)
  TXA             ; [2] A = col_bitmap(!=0)
; find first bit set
; loop WILL terminate because A is non-zero!
@bsf_lp:          ; (A=col_bitmap Y=scantab_ofs) -> [7] cycles
  INY             ; [2] count number of shifts (Y = row*8 + col_N)
  ASL A           ; [2] shift keys bits left into CF
  BCC @bsf_lp     ; [3] until CF=1 (key is down)                            (XXX will invert, down == 0)
; ...
; found a key down
  TAX             ; [2] save remaining col_bitmap (X)
  LDA IRQTmp2     ; [3] get key-hit flags (N=Hit.C | V=Hit.D)
  CPY CurrKey     ; [2] phys_key matches CurrKey?
  BEQ @is_curr    ; [2] -> found CurrKey [+1]
  CPY DeadKey     ; [2] phys_key matches DeadKey?
  BEQ @is_dead    ; [2] -> found DeadKey [+1]
  LDA CurrKey     ; [3] check if we have a CurrKey
  BEQ @setcurr    ; [3] -> no CurrKey: set CurrKey, insert keypress (Y), then return
  LDA DeadKey     ; [3] check DeadKey
  BNE @cont_bsf   ; [3] -> have DeadKey, ignore keypress, continue scan (X=col_bitmap Y=scantab_ofs IRQTmp=row)
; no dead key: rotate current key into dead key
  LDA CurrKey     ; [3] get CurrKey
  STA DeadKey     ; [3] move CurrKey to DeadKey
@setcurr:         ; set CurrKey, insert keypress (Y), then return
  STY CurrKey     ; [3] set CurrKey to phys_key (Y!=0)
  LDA #16         ; [2] initial delay: 16 frames
; ...
@inskey:          ; insert keypress (Y=phys_key, A=delay)
  STA KeyRep      ; [3] reset key-repeat timer for new key
; translate to ascii
  BIT ModKeys     ; [3] test shift key [N=Esc][V=Shf]
  BVS @shift      ; [2] -> shift is down (bit 6)
  LDA scantab-1,Y ; [4] translate to ASCII (Y is off by +1)
@shft_ret:        ; append to keyboard buffer
  LDY KeyTl       ; [3] keyboard buffer write offset
  STA KeyBuf,Y    ; [4] always safe to write at KeyTl
  INY             ; [2] increment
  TYA             ; [2]
  AND #KeyBufMask ; [2] modulo circular buffer
  CMP KeyHd       ; [3] is Tl+1 == Hd ?
  BEQ @done       ; [2] -> key buffer is full (don't update KeyTl)
  STA KeyTl       ; [3] update Tl = Tl+1 % 32
@done:
  RTS             ; [6] return
@shift:
  LDA scanshf-1,Y ; [4] translate to ASCII (Y is off by +1)
  BPL @shft_ret   ; [3] ALWAYS (top bit never set in scanshf)
; ...
@cont_hitf:       ; (A=IRQTmp2 X=col_bitmap Y=scantab_ofs IRQTmp=row)
  STA IRQTmp2     ; update key-hit flags (IRQTmp2)
@cont_bsf:        ; (X=col_bitmap Y=scantab_ofs IRQTmp=row)
  TXA             ; [2] restore remaining col_bitmap
  BNE @bsf_lp     ; [3] -> continue bsf loop if A != 0 (more keys are down)   (XXX will invert this, $FF)
  LDY IRQTmp      ; [3] restore keyscan row
  BPL @row_cont   ; [3] -> ALWAYS: continue scanning rows (Y in [0..8])
; ...
@mods:
  STX ModKeys     ; [3] update ModKeys (X=col_bitmap)
  BEQ @row_cont   ; [2] -> ALWAYS: scan next row (BEQ @mods) [+1]
@is_curr:         ; found CurrKey during scan (set Hit.C)
  ORA #128        ; set Hit.C=1
  BNE @cont_hitf  ; -> ALWAYS: continue scan (X=col_bitmap Y=scantab_ofs IRQTmp=row)
@is_dead:         ; found DeadKey during scan (set Hit.D)
  ORA #64         ; set Hit.D=1
  BNE @cont_hitf  ; -> ALWAYS: continue scan (X=col_bitmap Y=scantab_ofs IRQTmp=row)

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
  DB  $38, $39, $30, $2D, $3D, $60, $08, $1C     ;     8 9 0 - = ` Del Up
  DB  $69, $6F, $70, $5B, $5D, $5C, $00, $1D     ;     i o p [ ] \     Down
  DB  $6B, $6C, $3B, $27, $00, $00, $0D, $1E     ;     k l ; '     Ret Left
  DB  $2C, $2E, $2F, $00, $00, $00, $20, $1F     ;     , . /       Spc Right
scanshf:
  DB  $1B, $21, $40, $23, $24, $25, $5E, $26     ;   Esc ! @ # $ % ^ &
  DB  $09, $51, $57, $45, $52, $54, $59, $55     ;   Tab Q W E R T Y U
  DB  $0E, $41, $53, $44, $46, $47, $48, $4A     ;  Caps A S D F G H J
  DB  $00, $5A, $58, $43, $56, $42, $4E, $4D     ;       Z X C V B N M
  DB  $2A, $28, $29, $5F, $2B, $7E, $08, $1C     ;     * ( ) _ + ~ Del Up
  DB  $49, $4F, $50, $7B, $7D, $7C, $00, $1D     ;     I O P { } |     Down
  DB  $4B, $4C, $3A, $22, $00, $00, $0D, $1E     ;     K L : "     Ret Left
  DB  $3C, $3E, $3F, $00, $00, $00, $20, $1F     ;     < > ?       Spc Right

; $00 No key
; $08 Backspace
; $09 Tab
; $0D Return
; $0E CapsLock
; $1B Escape
; $1C Up
; $1D Down
; $1E Left
; $1F Right

; @@ readchar
; read a single character from the keyboard buffer
; KEY(k): directly scans the key (5:3 col:row)
readchar:         ; uses A,X,Y returns ASCII or zero
  LDX KeyHd       ; [3] load keyboard buffer head
  CPX KeyTl       ; [3] Hd == Tl -> empty, @wait
  BEQ @nokey      ; [2] buffer is empty
  LDY KeyBuf,X    ; [4] next buffered key
  INX             ; [2] inc keyboard buffer head
  TXA             ; [2]
  AND #KeyBufMask ; [2] modulo circular buffer
  STA KeyHd       ; [3] save new head
  TYA             ; [2]
  RTS             ; [6] -> return A (ZF)
@nokey:
  LDA #0          ; [2] return 0 (ZF)
  RTS             ; [6]


; ------------------------------------------------------------------------------
; PRINT, WRCHR, WRCTL, NEWLINE  (251b)

; @@ print
; write a length-prefix string to the screen
print:            ; X=high Y=low (uses A,B,X,Y,Ptr,Src,Dst)
  STX PtrH        ; [3] pointer high
  STY Ptr         ; [3] pointer low
  LDX #0          ; [2] X = 0 (const)
  LDA (Ptr,X)     ; [6] load string length
  BEQ @ret        ; [2] -> nothing to print [+1]
  STA B           ; [3] set length
@lp:
  INC Ptr         ; [5] increment source pointer
  BEQ @page       ; [2] -> page cross [+1] // 13
@pgre:
  LDA (Ptr,X)     ; [6] fetch next char
  ; inline wrchr
  CMP #32         ; [2] is it a control character?
  BCC @ctrl       ; [2] -> yes [+1]
  LDY CurX        ; [3] Y = CurX
  STA (TXTP),Y    ; [6] write char
  INY             ; [2] advance CurX
  CPY #40         ; [2] is CurX = 40?
  BEQ @eol        ; [2] -> yes, end of line [+1] // 16
  STY CurX
  ; end wrchr
@incr:
  DEC B           ; [5] decrement length
  BNE @lp         ; [3] -> loop // 8 -> 13+16+8 = [37]
@ret:
  RTS             ; [6] 
@page:
  INC PtrH        ; [5] next page
  BNE @pgre       ; [3] -> always (assume no 64K wrap)
@eol:
  JSR wr_eol      ; [6] wrap onto next line -> (Y=0)
@incx:
  LDX #0          ; [2] X = 0 (const)
  BEQ @incr       ; [3] -> always
@ctrl:
  JSR wrctl_y     ; [6] execute control code (uses A,X,Y,F,Src,Dst) -> (Y=CurX)
  JMP @incx       ; [3] -> always

; @@ wrchr        (18b)
; write a single character to the screen
wrchr:            ; A=char; (uses A,X,F,Src,Dst) preserves Y [24]
  CMP #32         ; [2] is it a control character?
  BCC wrctl       ; [2] -> yes [+1]  (uses A,X,F,Src,Dst) preserves Y
  STY F           ; [3] preserve Y (CONTRACT)
  LDY CurX        ; [3] Y = CurX
  STA (TXTP),Y    ; [6] write char
  INY             ; [2] advance CurX
  CPY #40         ; [2] at end of line?
  BEQ wr_eol      ; [2] -> yes [+1]
  STY CurX        ; [3] update CurX
  LDY F           ; [3] restore Y
  RTS             ; [6] -> (NE) // [28]

; page cross
wr_pg:            ; <- Y=0 [18]
  INC TXTPH       ; [5] page cross (NE, assume no 64K wrap) -> [29]
wr_ret:           ; <- Y=0, NE [22/29]
  RTS             ; [6] -> (Y=0, NE) -> [28/35]

; @@ newline      (57b)
; advance to end of line / wrap onto next line
newline:
  TYA             ; preserve Y
  PHA
  JSR wr_eol
  PLA
  TAY             ; restore Y
  RTS

wr_eol:           ; (uses A,X,Y) -> (Y=0)
  LDY #0          ; [2] reset CurX = 0
  STY CurX        ; [3] 
  LDA TXTP        ; [3] advance TXTP by 40
  CLC             ; [2] 
  ADC #40         ; [2] 
  STA TXTP        ; [3] 
  BCS wr_pg       ; [2] -> page cross [+1] (Y=0) // [18]
  CMP #192        ; [2] bottom of screen? (low byte)
  BNE wr_ret      ; [2] -> no [+1] (Y=0, NE) // [22]
  LDA TXTPH       ; [3] bottom of screen? (high byte)
  CMP #VidBase+3  ; [2] 
  BNE wr_ret      ; [2] -> no [+1] (Y=0, NE) // [29]
;
; scroll down     ; // [28]
  LDA #VidBase    ; [2]
  STA SrcH        ; [3]
  STA DstH        ; [3]
  LDA #40         ; [2] from row = 1
  STA Src         ; [3]
  LDA #0          ; [2] to row = 0
  STA Dst         ; [3]
; move contents up one line
  LDA #192        ; [2] 960 bytes = 192 bytes
  LDX #3          ; [2] plus 3 pages // [50]
  JSR mcopyf      ; [6] copy forwards XY=size (uses A,X,Y,F,Src,Dst) // [3*4111 + 192*18 + 20] = [15809]
; clear the bottom row
  LDA #VidBase+3  ; [2] last page of screen
  STA TXTPH       ; [3]
  LDA #152        ; [2] 192-40 offset
  STA TXTP        ; [3]
  JSR txt_clr     ; [6] clear row at TXTP (uses A,Y) -> (Y=0, EQ) // [16+450]
; return
  RTS             ; [6] -> (Y=0, EQ) -> [50+15809+16+450+6] = [16331] vs ~14940 per frame

; @@ wrctl        (105b)
; write a single control code
; assumes we're in text mode with TXTP set up
wrctl:            ; (uses A,X,F,Src,Dst) preserves Y
  STY F           ; [3] preserve Y (CONTRACT)
  LDY CurX        ; [2] load Y=CurX
  JSR wrctl_y
  LDY F
  RTS             ; Y[NE]

wrctl_y:          ; (Y=CurX)
  CMP #13         ; [2] is it RETURN?
  BEQ wr_eol      ; [2] -> do newline [+1] -> (Y=0)
  CMP #8          ; [2] is it BACKSPACE?
  BEQ @backsp     ; [2] -> do backspace [+1] -> (Y=CurX)
  CMP #$1E        ; [2] is it LEFT ARROW?
  BEQ @left       ; [2] -> do move left [+1] -> (Y=CurX)
  CMP #$1F        ; [2] is it RIGHT ARROW?
  BEQ @right      ; [2] -> do move right [+1] -> (Y=CurX)
  CMP #$1C        ; [2] is it UP ARROW?
  BEQ @up         ; [2] -> do move left [+1] -> (Y=CurX)
  CMP #$1D        ; [2] is it DOWN ARROW?
  BEQ @down       ; [2] -> do move left [+1] -> (Y=CurX)
  RTS             ; -> (Y=CurX)

@backsp:          ; go back one cell and clear it
  JSR @left       ; [21] move cursor left one place -> (Y=CurX)
  LDA #32         ; [3] space character
  STA (TXTP),Y    ; [6] clear the character under the cursor
  RTS             ; [6] // 36 (Y=CurX)

@left:            ; move left one place
  TYA             ; [2] test CurX
  BEQ @up_r       ; [2] -> at start of line, wrap around to the left [+1]
  DEY             ; [2] go back one space
  STY CurX        ; [3] update CurX
  RTS             ; [6] -> (Y=CurX) // 15

@up_r:
  LDY #39         ; [2] set CurX=39 (right edge)
  STY CurX        ; [3]
@up:              ; move up one line
  LDA TXTP        ; [3]
  SEC             ; [2]
  SBC #40         ; [2]
  BCC @uppg       ; [2] -> page-cross (borrowed) [+1]
@upcon:
  STA TXTP        ; [3]
  RTS             ; [6] -> (Y=CurX)

@uppg:
  LDX TXTPH       ; [3] test TXTPH
  CPX #VidBase    ; [2] at top of screen? ($02)
  BEQ @done       ; [2] -> cannot go up [+1]
  DEC TXTPH       ; [5] go up one page (NE)
  BNE @upcon      ; [3] -> always (Y=CurX)

@right:           ; move right one place
  CPY #39         ; [2] test CurX
  BEQ @dn_l       ; [2] -> at end of line, wrap around to the right [+1]
  INY             ; [2] advance
  STY CurX        ; [3] update CurX
  RTS             ; [6] -> (Y=CurX) // 15

@dn_l:
  LDY #0          ; [2] set CurX=0 (left edge)
  STY CurX        ; [3]
@down:            ; move down one line
  LDA TXTP        ; [3]
  CMP #192        ; [2] at bottom of screen? (low byte)
  BNE @dnok       ; [2] -> no, continue [+1]
  LDX TXTPH       ; [3] check page
  CPX #VidBase+3  ; [2] at bottom of screen? (high byte)
  BEQ @done       ; [2] -> cannot go down [+1]
@dnok:
  CLC             ; [2]
  ADC #40         ; [2]
  STA TXTP        ; [3]
  BCC @done       ; [2] -> no page-cross [+1]
  INC TXTPH       ; [5] go down one page
@done:
  RTS             ; [6] -> (Y=CurX)


; ------------------------------------------------------------------------------
; READLINE, LINE EDITOR   (101b)

; Arrows move within the line; insert or delete text within the line.
; TAB calls up an existing line in edit mode.

; @@ readline
; read a single line of input into the line buffer (zero-terminated)
readline:         ; uses A,X,Y,B,C -> LineBuf, Y=length (EQ if zero)
  LDA #0          ; 
  STA B           ; init line length
@idle:
  JSR show_cursor ; uses A,Y; Y=0
@wait:
  BIT ModKeys     ; check for Escape
  BMI @esc
  JSR readchar    ; from keyboard (uses A,X,Y -> A,ZF)
  BEQ @wait       ; if no char -> @wait
  TAX             ; save key
  JSR hide_cursor ; uses A,Y; Y=0
  TXA             ; restore key
@cont:
  CMP #32         ; is it a control code?
  BCC @ctrl       ; -> char < 32, control code
  LDY B           ; current length
  CPY #119        ; is buffer full? (3 lines)
  BEQ @more       ; buffer full -> do nothing
  ; write new char at cursor
  STA LineBuf,Y   ; write char (insert at cursor)
  INC B           ; increase length
  JSR wrchr       ; print A=char (uses A,X,F,Src,Dst) preserves Y •••
@more:            ; keep reading chars
  JSR readchar    ; from keyboard (uses A,X,Y -> A,ZF)
  BNE @cont       ; -> got another char
  BEQ @idle       ; -> return to idle
@ctrl:
  CMP #13         ; is it RETURN?
  BEQ @return     ; -> return
  LDY B           ; check length
  BEQ @more       ; -> cannot backspace
  CMP #8          ; is it BACKSPACE?
  BNE @more       ; -> no
; backspace
  DEC B           ; length -= 1
  JSR wrctl       ; write the control code (uses A,X, preserves Y -> CC=fail)
  JMP @more
@esc:
  JMP escape
@return:
  LDY B           ; get line length
  LDA #0          ; terminator
  STA LineBuf,Y   ; write terminator to line buffer
  RTS             ; returns Y=length (ZF=1 if zero)


; ------------------------------------------------------------------------------
; CLS, HOME, txt_at   (93b)

; @@ vid_cls
; clear the screen or text window
vid_cls:         ; (uses A,X,Y,F)
  JSR txt_home   ; A=row X=col -> TXTP(AY) (uses A,X,Y,F)
  LDX #3         ; number of whole pages
@lp:
  LDY #0         ; count = 256
  JSR txt_clr_n  ; Y=count (uses A,Y) -> (Y=0,EQ)  3  2  1
  INC TXTPH      ; next page
  DEX            ; 
  BNE @lp        ; -> loop
  LDY #192       ; count = 192
  JSR txt_clr_n  ; Y=count (uses A,Y) -> (Y=0,EQ)
  ; +++ fall through to @@ txt_home +++

; @@ home
; move the cursor to the top-left of the window
; update DMA address (DSTL,DSTH) for "text mode"
txt_home:        ; (uses A,X,Y)
  LDX #0         ; col = 0
  LDY #0         ; row = 0
  STY CurX       ; reset CurX
  BEQ txt_at2    ; -> skip range check

; @@ txt_at
; move the cursor to X,Y
txt_at:          ; X=col Y=row -> TXTP (uses A,X,Y)
  CPX #40        ; clamp X if out of range
  BCC @x_ok      ; -> valid
  LDX #39        ; 
@x_ok:
  CPY #24        ; clamp Y if out of range
  BCC @y_ok      ; -> valid
  LDY #23        ; 
@y_ok:
txt_at2:         ; XXX sets complete TXTP address (no CurX support)
  TYA            ; [000YYYYY]       (0..23)
  LSR            ; [0000YYYY] div 2 (0..11) CF=Y0
  TAY            ; as index
  TXA            ; [00XXXXXX] (0..39)
  BCC @noY0      ; -> even row
  ADC #39        ; add 40 (if CF=Y0=1) -> CF=0    6 bytes, saves 24 (net 18 saved)
@noY0:
  ADC txtatl,Y   ; add low byte -> CF
  STA TXTP       ; set destination low
  LDA txtath,Y   ; look up high byte
  ADC #0         ; add carry (from low byte)
  STA TXTPH      ; set destination high
  RTS

txtatl:    ; 12 bytes
  DB 0     ;  0
  DB 80    ;  2
  DB 160   ;  4
  DB 240   ;  6 -> 280
  DB 64    ;  8
  DB 144   ; 10
  DB 224   ; 12 -> 264
  DB 48    ; 14
  DB 128   ; 16
  DB 208   ; 18
  DB 32    ; 20
  DB 112   ; 22

txtath:    ; 12 bytes
  DB 2+0   ;  0
  DB 2+0   ;  2
  DB 2+0   ;  4
  DB 2+0   ;  6
  DB 2+1   ;  8
  DB 2+1   ; 10
  DB 2+1   ; 12
  DB 2+2   ; 14
  DB 2+2   ; 16
  DB 2+2   ; 18
  DB 2+3   ; 20
  DB 2+3   ; 22

; @@ txt_clr
; fill a text row at TXTP (does not change TXTP)
txt_clr:           ; (uses A,Y)
  LDY #40          ; [2] count = 40
txt_clr_n:         ; Y=count (uses A,Y)
  LDA #32          ; [2] fill with spaces
@loop:
  DEY              ; [2] decrement column
  STA (TXTP),Y     ; [6] write a space  39 38 .. 01 00
  BNE @loop        ; [3] -> until Y=0 // [11]
  RTS              ; [6] -> (Y=0, EQ) // [10 + 40*11] = [450]


; ------------------------------------------------------------------------------
; Memory Copy

; @@ mem_copy
; copy memory from (Src) to (Dst) with XY=size                (17b)    [17+31+37 = 85]
mem_copy:                ; (uses A,X,Y,F,Src,Dst)
  LDA DstH               ; [3]
  CMP SrcH               ; [3]
  BCC mcopyf             ; [2] -> DstH < SrcH (copy forwards)
  BNE mcopyb             ; [2] -> DstH > SrcH (copy backwards)
; high bytes are equal
  LDA Dst                ; [3]
  CMP Src                ; [3]
  BCC mcopyf             ; [2] -> Dst < Src (copy forwards)
  BNE mcopyb             ; [2] -> Dst > Src (copy backwards)
  RTS                    ; [6] no copy

; @@ mcopyf
; copy memory forwards from (Src) to (Dst) with XY=size       (32b)
; assume (Dst < Src) but Src/Dst may overlap 
mcopyf:                  ; (uses A,X,Y,F,Src,Dst)
  STY F                  ; [3] save part-page
; whole pages
  LDY #0                 ; [2] for @plp or @olp
  TXA                    ; [2] is X=0?
  BEQ @part              ; [2] -> no whole pages [+1] // [9]
@plp:
  LDA (Src),Y            ; [5] read byte       (Src),0  (Src),1 .. (Src),FF -> EQ
  STA (Dst),Y            ; [6] write byte      (Dst),0  (Dst),1 .. (Dst),FF -> EQ
  INY                    ; [2] advance
  BNE @plp               ; [3] -> until Y=0 (256 bytes) [+1] // [16*256] = [4096]
  INC SrcH               ; [5] next Src page
  INC DstH               ; [5] next Dst page
  DEX                    ; [2] decrement page count
  BNE @plp               ; [2] -> another page (Y=0) [+1] // [+15] = [PG*4111]
@part:                   ; (Y=0)
  LDX F                  ; [3] restore part-len // [3]
@olp:
  LDA (Src),Y            ; [5] read byte
  STA (Dst),Y            ; [6] write byte
  INY                    ; [2] advance
  DEX                    ; [2] decrement length
  BNE @olp               ; [3] -> until X=0 [+1] // [OFS*18]
  RTS                    ; [6] -> // [PG*4111 + OFS*18 + 18]

; @@ mcopyb
; copy memory backwards from (Src) to (Dst) with XY=size      (37b)
; assume (Dst > Src) but Src/Dst may overlap 
mcopyb:                  ; uses (A,X,Y,F,Src,Dst)
  STX F                  ; [3] page count
; advance to last page (13b, 19s)
  LDA SrcH               ; [3] Src += A * 256
  CLC                    ; [2]
  ADC F                  ; [3]
  STA SrcH               ; [3]
  LDA DstH               ; [3] Dst += A * 256
  ADC F                  ; [2] no CLC (assume no 64K wrap)
  STA DstH               ; [3]
; begin copy
  TYA                    ; [2] is Y=0?
  BEQ @lp                ; [2] -> Y=0, no partial page [+1]
  INC F                  ; [5] pages++ for partial page
@lp:
  DEY                    ; [2] count--
  LDA (Src),Y            ; [5] read byte (sets NE/EQ)
  STA (Dst),Y            ; [6] write byte
  TYA                    ; [2] is count==0?
  BNE @lp                ; [3] -> until count=0 // [18]
; back to previous page
  DEC SrcH               ; [5] Src -= 256
  DEC DstH               ; [5] Dst -= 256
  DEC F                  ; [5] pages-- (Y=0)
  BNE @lp                ; [2] -> until pages=0 [+1] // [+18]
  RTS                    ; [6] 


; ------------------------------------------------------------------------------
; Cursor

; @@ cursor_off
; turn off and inhibit cursor
hide_cursor:      ; (uses A,Y preserves X)
  SEI             ; [2] disable interrupts
  BIT CurVis      ; [3] is cursor visible?
  BPL @hidden     ; [2] already hidden? (top-bit clear) [+1]
  JSR cur_hide    ; [6] restore char under cursor
@hidden:
  LDA #$40        ; [2] set bit 6
  STA CurVis      ; [3] cursor inhibited
  CLI             ; [2] re-enable interrupts
  RTS             ; [6]

; @@ cursor_on
; turn on and un-inhibit cursor
show_cursor:      ; (uses A,Y preserves X)
  SEI             ; [2] disable interrupts
  BIT CurVis      ; [3] is cursor visible?
  BMI @shown      ; [2] already shown? (top-bit set) [+1]
  JSR cur_show    ; [6] make cursor visible
@shown:
  CLI             ; [2] re-enable interrupts
  RTS             ; [6]

cur_toggle:       ; toggle cursor (requires interrupts disabled)
  BIT CurVis      ; [3] is cursor visible?
  BVS cur_inh     ; [2] -> cursor inhibited [+1]
  BPL cur_show    ; [2] -> no, show it [+1]
cur_hide:         ; hide cursor (uses A,Y; Y=0)
  LDY CurX        ; [2] Y = CurX (0..39)
  STY CurVis      ; [3] clear top-bit (cursor hidden, no inhibit)
  LDA CurChar     ; [3] get saved char
  STA (TXTP),Y    ; [5] restore char under cursor (no flags)
  JMP cur_ret     ; [3] -> always
cur_show:         ; show cursor (uses A,Y; Y=0)
  LDY CurX        ; [2] Y = CurX
  LDA (TXTP),Y    ; [5] get char under cursor
  STA CurChar     ; [3] save char under cursor
  LDA #$EF        ; [2] cursor block
  STA (TXTP),Y    ; [6] write cursor block
  LDA #$80        ; [2] set top bit
  STA CurVis      ; [3] set top-bit (cursor visible, no inhibit)
cur_ret:
  LDA #24         ; [2]
  STA CurTime     ; [3] reset cursor timer
cur_inh:
  RTS             ; [6]

; ------------------------------------------------------------------------------
; IRQ

; @@ irq_init
; set up IRQ vector in zero page, init keyboard, enable interrupts
irq_init:
  SEI            ; disable IRQ
  LDA #0         ; reset keyboard buffer (with interrupts disabled)
  STA KeyHd
  STA KeyTl
  STA ModKeys    ; ensure Escape is not pressed!
  LDA #$40       ; inhibit cursor until enabled
  STA CurVis
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
  STA IO_VLN     ; [3] acknowledge interrupt
  PHA            ; [3] save A
  TXA            ; [2]
  PHA            ; [3] save X
  TYA            ; [2]
  PHA            ; [3] save Y
; keyboard scan
  JSR keyscan    ; [6]
; cursor blink
  DEC CurTime    ; [5]
  BNE @done      ; [2] -> not yet [+1]
  JSR cur_toggle ; [6] toggle cursor
@done:
  PLA            ; [4] restore Y
  TAY            ; [2]
  PLA            ; [4] restore X
  TAX            ; [2]
  PLA            ; [4] restore A
nmi_vec:
  RTI            ; [6]

; testkey:
; mem_fill:
; file_save:
; file_load:
; file_open:
; file_close:
; gfx_color:
; sys_opt:

; @@ System Vectors
; ORG SYSVEC
; JMP wrchr           ; $FFB0  print char or control code in A              (JSR preserves Y)
; JMP print           ; $FFB3  print string, len-prefix, X=page Y=offset    (JSR uses A,B,X,Y)
; JMP testkey         ; $FFB6  test a keyboard key A=code                   (JSR uses A,X,Y) -> CS=down CC=up
; JMP readchar        ; $FFB9  read a character from the keyboard           (JSR uses A,X,Y) -> A=char/zero ZF
; JMP readline        ; $FFBC  read a line into LineBuf (zero-terminated)   (JSR uses A,X,Y) -> Y=length
; JMP mem_fill        ; $FFC0  fill DST with A size X,Y                     (JSR uses A,X,Y)
; JMP mem_copy        ; $FFC3  copy SRC to DST size X,Y                     (JSR uses A,X,Y)
; JMP file_save       ; $FFC6  save SRC size X,Y name at PTR                (JSR uses A,X,Y)
; JMP file_load       ; $FFC9  load to DST name at PTR                      (JSR uses A,X,Y)
; JMP file_open       ; $FFCC  open file name at PTR for read/write         (JSR uses A,X,Y)
; JMP file_close      ; $FFD0  close the open file                          (JSR uses A,X,Y)
; JMP gfx_color       ; $FFD3  set graphics color / operation               (JSR uses A,X,Y)
; JMP gfx_plot        ; $FFD6  draw a line to X,Y                           (JSR uses A,X,Y)
; JMP gfx_line        ; $FFD9  draw a line to X,Y                           (JSR uses A,X,Y)
; JMP sys_opt         ; $FFDC  set option X to A                            (JSR uses A,X,Y)
; JMP vid_cls         ; $FFE3  clear the screen                             (JSR uses A,X,Y)
; JMP txt_at          ; $FFE6  move text cursor to X,Y within text window   (JSR uses A,X,Y)
; JMP basic           ; $FFE9  enter BASIC                                  (JMP)

; @@ CPU Vectors
ORG BasROM+$1000-6
DW nmi_vec       ; $FFFA, $FFFB ... NMI vector
DW reset         ; $FFFC, $FFFD ... Reset vector
DW IrqVec        ; $FFFE, $FFFF ... BRK/IRQ vector
