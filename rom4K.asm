; Robo 4K BASIC 1.0
; Use `asm6` to compile: https://github.com/parasyte/asm6

; BASIC runtime   1K
; Floating point  1K
; BASIC parser    1K
; Editor          1K

ROM      = $F000  ; 4K = $1000 from F000-FFFF
VEC      = $FFFA  ; vector table, 6 bytes

ZeroPg   = $0000  ; zero page
StackPg  = $0100  ; stack page
ScreenPg = $0200  ; start of screen memory
FreePg   = $0500  ; start of free memory
EndPg    = $1000  ; end of memory

; ------------------------------------------------------------------------------
; Zero Page

; -- $0x-7x lines: Buffer Space

LineBuf  = $00    ; line buffer, scratch space (00-7F; 128 bytes)

; -- $8x line: Unused

; -- $9x line: Memory Registers

Src      = $90    ; source pointer \ Used by PRINT/WRCHR/WRCTL/COPY/CLS (scrolling)
SrcH     = $91    ; source pointer | Used by Tokenize(scan_kw/num_val)
Dst      = $92    ; second pointer | Used by PRINT/WRCHR/WRCTL/COPY/CLS (scrolling)
DstH     = $93    ; second pointer | 
B        = $94    ; extra register | Subroutines are annotated with usage;
C        = $95    ; extra register | held across calls only when unused
D        = $96    ; extra register | by callees (manually tracked)
E        = $97    ; extra register | 
F        = $98    ; extra register / Scratch (always transient; cannot hold)
; 98-9F  free (8 bytes)

; -- $Ax line: BASIC Registers

Acc0     = $A0    ; Accumulator low byte
Acc1     = $A1    ; Accumulator byte 1
Acc2     = $A2    ; Accumulator byte 2
AccE     = $A3    ; Accumulator exponent

Term0    = $A4    ; Term low byte
Term1    = $A5    ; Term byte 1
Term2    = $A6    ; Term byte 2
TermE    = $A7    ; Term exponent
PrintL   = $A6    ; Term byte 2 ALIAS (for print:)
PrintH   = $A7    ; Term exponent ALIAS (for print:)

DataL    = $A8    ; next DATA statement (Commas become OP_DATA; zero if no DATA found or end of data)
DataH    = $A9    ; next DATA statement (Commas become OP_DATA; zero if no DATA found or end of data)
EmitOfs  = $A8    ; Tokenizer emit offset ALIAS (tokenizer)
AutoInc  = $A9    ; AUTO line step ALIAS (for cmd_auto:)

; -- $Bx line: BASIC Pointers

LOMEM    = $B0    ; BASIC memory base address ($3500/$2500/$0500 text; $3800/$2800/$0800 APA)
LOMEMH   = $B1
TOP      = $B2    ; TOP of the BASIC program (where variables start)
TOPH     = $B3
HIMEM    = $B4    ; BASIC memory limit address ($4000 unless RAM expansion installed)
HIMEMH   = $B5
CODE     = $B6    ; current BASIC code pointer (next instruction)
CODEH    = $B7
LINE     = $B8    ; current BASIC line number (for edit/auto, for execution)
LINEH    = $B9

; -- $Cx line: OS Vars

KeyHd    = $C0    ; keyboard buffer head (owned by User)
KeyTl    = $C1    ; keyboard buffer tail (owned by IRQ)
ModKeys  = $C2    ; modifier keys [7:Esc 6:Shf 5:Ctl 4:Fn] (owned by IRQ)
LastKey  = $C3    ; keyboard last key pressed, for auto-repeat (owned by IRQ)

WinL     = $C4    ; text window left
WinT     = $C5    ; text window top
WinW     = $C6    ; text window width
WinH     = $C7    ; text window height

CurY     = $C8    ; text cursor Y
WinRem   = $C9    ; remaining horizontal space in text window (WinW - CurX)
WinAdv   = $CA    ; advance to reach start of next line (32 - WinW)
TXTP     = $CB    ; text write address
TXTPH    = $CC    ; text write address high
CurTime  = $CD    ; cursor flash timer
CurChar  = $CE    ; character under cursor

; -- $Dx line: Keyboard buffer

KeyBuf   = $D0    ; keyboard buffer (16 bytes, could shrink this to 8 bytes)

; -- $Ex line: OS Vectors

; Vectors (E5-EF)
SysCmds  = $E5    ; REPL command-list pointer {Low,High} (for ROM override)
SysStmt  = $E7    ; BASIC statement extension cmd-list {Low,High} (for ROM override)
IRQTmp   = $E9    ; Temp for IRQ handler
NmiVec   = $EA    ; NMI vector in RAM {JMP,Low,High} (for ROM override)
IrqVec   = $ED    ; IRQ vector in RAM {JMP,Low,High} (for ROM override)

; -- $Fx line: IO space (F0-FF)

IO_VCTL  = $FF    ; video mode (7-4:border 1:Grey 0:APA)
IO_VPAL  = $FE    ; palette for APA (7-4:BG 3-0:FG)
IO_VLIN  = $FD    ; current vertical line (>= 192 in vborder/vblank) (write: ack INT)
IO_KEYB  = $FC    ; Keyboard scan (write: set row; read: scan column)
IO_PSGF  = $FB    ; PSG frequency (7860 Hz / divider)

; ------------------------------------------------------------------------------
; Defines

; IO_VCTL bits
VCTL_APA    = $01   ; linear framebuffer at address $200
VCTL_GREY   = $02   ; disable Colorburst for text legibility
VCTL_BORDER = $F0   ; border color (high nibble)

ModShift = $80    ; Shift is down
ModCtrl  = $40    ; Ctrl is down
ModFn    = $20    ; Fn is down
ModCaps  = $10    ; Caps lock is down
ModLeft  = $08    ; Left Arrow is down
ModRight = $04    ; Right Arrow is down
ModDown  = $02    ; Down Arrow is down
ModUp    = $01    ; Up Arrow is down

; ------------------------------------------------------------------------------
; PAGE 0

ORG ROM

; ROM entry table     ; public entry points
  JMP reset           ; $E000  reset the computer                           (JMP)
  JMP basic           ; $E003  enter BASIC                                  (JMP)
  JMP print           ; $E006  print string, len-prefix, X=page Y=offset    (JSR uses A,B,X,Y)
  JMP wrchr           ; $E009  print char or control code in A              (JSR preserves Y)
  JMP newline         ; $E00C  print a newline, scroll if necessary         (JSR preserves Y)
  JMP readline        ; $E00F  read a line into LineBuf (zero-terminated)   (JSR uses A,X,Y) -> Y=length
  JMP readchar        ; $E00C  read a character from the keyboard           (JSR uses A,X,Y) -> A=char/zero ZF
  JMP vid_mode        ; $E012  set screen mode, clear the screen            (JSR uses A,X,Y)
  JMP vid_cls         ; $E015  clear the screen                             (JSR uses A,X,Y)
  JMP txt_tab         ; $E018  move text cursor to X,Y within text window   (JSR uses A,X,Y)

messages:    ; must be within one page for Y indexing
msg_boot:    ; blue red orange yellow green cyan purple
  DB 27
  DB $91,$92,$93,$94,$95,$90,13,13
  DB "Frontier BASIC 1.0",13
msg_freemem:
  DB 12, " bytes free",13
ready:
  DB 5,"READY"
msg_expecting:
  DB 8,"Missing "
msg_div:
  DB 5,"Div 0"
msg_overflow:
  DB 8,"Overflow"
msg_syntax:
  DB 5,"What?"
msg_range:
  DB 5, "Range?"
msg_escape:
  DB 7, 13, "Escape"
msg_searching:
  DB 9,"Searching"
msg_loading:
  DB 7,"Loading"
msg_bad:
  DB 4,"Bad "
msg_prog:
  DB 7,"Program"
msg_block:
  DB 5,"Block"
msg_var:
  DB 3,"Var"
msg_type:
  DB 4,"Type"


reset:
  SEI            ; disable interrupts
  CLD            ; disable BCD mode
  LDX #$FF       ; reset stack [to align it?]
  TXS            ; stack init
  INX            ; #0
  STX Acc2       ; Acc2=0 to display free memory
  INX            ; #1 for cursor reset
  STX CurTime    ; show on the next frame
  DEX            ; screen mode 0 (32x24 text, 16 color)
  JSR vid_mode   ; set mode, clear screen
  LDY #<msg_boot
  JSR printmsgln  ; (uses A,B,C,D,X,Y,Src,Dst)
  ; detect memory installed
  LDA #<FreePg     ; low
  STA LOMEM        ; set BASIC start address (will be dynamic)
  STA TOP          ; also reset TOP
  LDA #>FreePg     ; high
  STA LOMEMH
  STA TOPH
  LDA #<EndPg      ; low
  STA HIMEM        ; set BASIC end address (will be dynamic)
  LDA #>EndPg      ; high
  STA HIMEMH
  ; display free memory
  CLC
  LDA HIMEM
  SBC LOMEM
  STA Acc0
  LDA HIMEMH
  SBC LOMEMH
  STA Acc1
  JSR num_print
  LDY #<msg_freemem
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)
  LDY #<ready
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)
  ; +++ fall through to @@ basic +++

; @@ basic
; enter the basic command-line interface
basic:
  CLD            ; disable BCD mode (for re-entry)
  JSR irq_init   ; init IRQ vector, init keyboard, enable IRQ
repl:            ; <- entry point after parse error
basic_e1:        ; <- entry point after Escape
  LDX #$FF       ; reset stack on entry (e.g. from Escape) [for overflow detect]
  TXS            ; stack init
  INX            ; = 0
  STX DataL      ; no data yet
  STX DataH      ; no data yet
  JSR readline   ; -> Y=length
  JSR newline    ; uses A,X

  ; parse the command
  LDX #0           ; [2]
  JSR skip_spc     ; [24+] X=ln-ofs -> X (uses A,X) leading spaces
  LDA LineBuf,X    ; [3] peek ahead
  BEQ repl         ; [2] -> empty line, go back to repl [+1]
  JSR num_u16      ; [6] parse number at X -> X,Acc,NE=found (uses A,Y,B)
  BNE @haveline    ; [2] -> found line number [+1]

  ; try matching a repl command
  LDA #<repl_tab   ; [2] repl commands table
  LDY #>repl_tab   ; [2]
  JSR scan_kw_all  ; [6] X=ln-ofs A,Y=table -> CF=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCC @direct      ; [3] -> no match, parse direct
  AND #$7F         ; [2] clear top bit of hi-byte
  CMP #repl_len    ; [2] ASSERT
  BCS @bounds      ; [2] ASSERT A >= repl_len
  JSR @docmd       ; [6] run the command
  JMP repl         ; [3] -> back to repl
  ; jump to the REPL command (slow, but saves space)
@docmd:
  ASL              ; [2] times 2 (word index)
  TAY              ; [2] as index
  LDA repl_fn+1,Y  ; [4] repl function, high byte
  PHA              ; [3] push high
  LDA repl_fn,Y    ; [4] repl function, low byte
  PHA              ; [3] push low
  RTS              ; [6] "return" to the REPL command

  ; tokenize and evaluate direct BASIC statements
@direct:
  LDX #0           ; [2]
  JSR tokenize     ; [6] tokenize BASIC statements
                   ;     XXX execute the line immediately
  JMP repl         ; [6] return to repl

  ; tokenize and append/edit the BASIC program
@haveline:         ; X = after line number
  ; save line number for bas_ins_line
  LDA Acc0         ; [3]
  STA LINE         ; [3]
  LDA Acc1         ; [3]
  STA LINEH        ; [3]
  BMI @bounds      ; [2]
  JSR tokenize     ; [6] tokenize BASIC statements
                   ;     XXX insert the tokenized line into the BASIC program
  JMP repl         ; [6] return to repl

@bounds:
  LDY #<msg_range
  ; +++ fall through to @@ report_err +++

; @@ report_err
; Report an error and return to the BASIC repl.
report_err:       ; Y = low byte (in messages page)
  JSR printmsgln  ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  JMP repl

report_bad:       ; Y = low byte (in messages page)
  STY E
  LDY #<msg_bad
  JSR printmsg    ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  LDY E
  JSR printmsgln  ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  JMP repl

; @@ repl_esc
; Escape from readline or the interpreter
repl_esc:
  LDY #<msg_escape
  JSR printmsgln ; (uses A,B,C,D,X,Y,Src,Dst)
  LDA #$3E       ; ">"
  JSR wrchr      ; uses A,X
@wait:           ; wait for Escape to be released
  LDA ModKeys    ; check key state
  BMI @wait      ; -> Escape still down
  JMP basic_e1   ; -> re-enter repl



; ------------------------------------------------------------------------------
; BASIC Tokenizer
;
; X = current source offset in LineBuf (persistent)

; @@ skip_spc
; skip spaces in the input buffer [NO TEXT-OUT]
skip_spc:        ; X=ln-ofs -> X (uses A,X)
  LDA LineBuf,X  ; [4] next input char
  INX            ; [2] advance (assume match)
  CMP #32        ; [2] was it space?
  BEQ skip_spc   ; [2] -> loop [+1]
  DEX            ; [2] undo advance (didn't match)
  RTS            ; [6] return X=ln-ofs, A=next-char [12+6=18]

; @@ is_alpha
is_alpha:        ; X=input-ofs (uses A) -> CC=alphabetic [NO TEXT-OUT]
  LDA LineBuf,X  ; [4] next input char
  AND #$DF       ; [2] lower -> upper (clear bit 5) detect alpha char
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CS if >= 26)
tok_ret1:
  RTS            ; [6] return A=alphabet-index CC=alphabetic [12+6=18]

; @@ tok_emit
; Emit an opcode at CODE and advance CODE.
tok_emit:            ; uses Y; preserves A,X -> PL=ok  [19]
  LDY EmitOfs        ; [3] get output offset           [MZ]
  STA LineBuf,Y      ; [5] write opcode                []
  INC EmitOfs        ; [5] advance output offset       [NZ]
  RTS                ; [6] M=0 (PL) unless overrun

; @@ tok_eol:
; end of line reached, do whatever
tok_eol:
  RTS

; @@ miss_quo
; report a missing quote
miss_quo:
  LDA #$22           ; closing quote '"'
  JMP tok_expect

; @@ tok_str
; tokenize a string
tok_str:
  LDA #OP_STR
  JSR tok_emit       ; opcode (uses Y) -> preserves A,X
  JSR tok_emit       ; length placeholder (uses Y) -> preserves A,X
  STY B              ; save offset of length byte (Y from tok_emit!)    [zero; each emit is +1]
  INX
@str_lp:
  LDA LineBuf,X      ; next input char
  BEQ miss_quo       ; -> end of line; missing quote
  CMP #$22           ; '"'
  BEQ @str_quo       ; -> maybe end of string
@str_out:
  INX                ; advance (consume input)
  JSR tok_emit       ; emit the character (uses Y) -> preserves A,X
  BPL @str_lp        ; -> always (MI on overrun)
@str_quo:
  INX                ; advance (consume '"')
  LDA LineBuf,X      ; next input char
  CMP #$22           ; is it also '"' (double-quote)
  BEQ @str_out       ; -> include this one in the string
; end of string
  DEX                ; undo advance (not consumed)
  LDA EmitOfs        ; current emit offset
  CLC
  SBC B              ; subtract start offset -> string length
  LDY B              ; address of length placeholder
  STA LineBuf,Y      ; patch in string length
  JMP tok_exprs      ; -> expect more

; @@ tokenize
; tokenize BASIC statements (in-place in LineBuf)
tokenize:            ; X=ln-ofs
tok_stmts:
  JSR skip_spc       ; X=ln-ofs (uses A) -> A=next-char
  JSR is_alpha       ; X=ln-ofs (uses A) -> A=AtoZ-index CC=alphabetic
  BCS tok_syn        ; -> no STMT or VAR
  ; search for a matching statement keyword
  TAY                ; A-Z as index (0-25)
  LDA stmt_idx,Y     ; offset in stmt_page (A-Z)
  LDY #>stmt_page    ; stmt keyword table
  JSR scan_kw_idx    ; X=ln-ofs A,Y=table -> CF=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCC tok_var        ; -> no match, must be VAR
  JSR tok_emit       ; output token with top-bit set (uses Y) -> preserves A,X
; parse remaining tokens up to EOL or ':'
tok_exprs:
  JSR skip_spc       ; X=ln-ofs (uses A) -> A=next-char
  BEQ tok_eol        ; -> end of input, done
  CMP #$22           ; open quote '"'
  BEQ tok_str        ; -> tokenize a string
  CMP #$3A           ; colon ':'
  BEQ tok_stmts      ; -> another stmt
  ; tokenize function names and context-keywords
  JSR is_alpha       ; X=ln-ofs (uses A) -> A=AtoZ-index CC=alphabetic
  BCC tok_fn_var     ; -> keyword/variable (A=AtoZ-index)
  ; is it a number?
  LDA LineBuf,X      ; next input char
  SEC                ; for subtract
  SBC #48            ; make '0' be 0
  CMP #10            ; 10 digits (CS if >= 10)
  BCC tok_number     ; -> integer or float
; report syntax error
tok_syn:
  LDY #<msg_syntax
  JMP report_err

; recognise and emit a varaible name (X at 1st letter)
tok_var:
  LDA LineBuf,X      ; reload 1st var-name byte
@var_lp:
  INX                ; consume var-name byte
  JSR tok_emit       ; output the character (uses Y) -> preserves A,X
  LDA LineBuf,X      ; next var-name byte
  TAY                ; save original char
  AND #$DF           ; lower -> upper (clear bit 5)
  SEC                ; for subtract
  SBC #65            ; make 'A' be 0
  CMP #26            ; 26 letters (CS if >= 26)
  TYA                ; restore original char
  BCC @var_lp        ; -> output and continue
  JMP tok_exprs      ; -> expect more

; parse function names and context-keywords (A=AtoZ-index)
tok_fn_var:          ; is alpha...
  TAY                ; A-Z as index (0-25)
  LDA expr_idx,Y     ; offset in expr_page (A-Z)
  LDY #>expr_page    ; expr keyword table
  JSR scan_kw_idx    ; X=ln-ofs A,Y=table -> CF=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCC tok_var        ; -> no match, must be VAR
  JSR tok_emit       ; output token (kw or fn) (uses Y) -> preserves A,X
  JMP tok_exprs      ; -> expect more

; parse a number
tok_number:
  JSR num_val        ; from LineBuf,X -> X, Acc, CS=overflow (uses A,X,Y,Term)
  BCS err_overflow   ; -> unsigned overflow
  ; XXX output the number
  JMP tok_exprs      ; -> expect more

err_overflow:
  LDY #<msg_overflow
  JMP report_err


; @@ tok_num_o
; tokenize and emit a number
tok_num_o:       ; CS=found
  JSR num_val    ; from LineBuf,X -> Acc,X,NE=found (uses A,Y,B,C,Term)
  BEQ tok_syn    ; -> not a number
  LDA Acc2
  BMI @neg       ; -> handle negative case
  BNE @int4
  LDA Acc1
  BNE @int2
@int1:
  LDA #OP_INT1
  JSR tok_emit   ; write OP_INT1
  BNE @wr0
@int2:
  LDA #OP_INT2
  JSR tok_emit   ; write OP_INT2
  BNE @wr1
@int4:
  LDA #OP_INT4
  JSR tok_emit   ; write OP_INT4
  LDA AccE       ; XXX finish this
  JSR tok_emit
  LDA Acc2
  JSR tok_emit
@wr1:
  LDA Acc1
  JSR tok_emit
@wr0:
  LDA Acc0
  JSR tok_emit
  SEC
  RTS
@neg:            ; A=Acc3
  CMP #$FF
  BNE @int4      ; -> not FF, need 0,1,2,3
  ; Acc2 is FF
  LDA Acc1
  BPL @int4      ; -> not negative, need extra sign byte
  CMP #$FF
  BNE @int2      ; -> not FF, need 0,1
  ; Acc1 is FF
  LDA Acc0
  BPL @int2      ; -> not negative, need extra sign byte
  BMI @int1      ; -> negative, single byte


; @@ tok_expect
; Report an "Expecting [char]" error
tok_expect:       ; A = expected character (uses A,B,C,D,E,X,Y,Src,Dst)
  STA E           ; save char
  LDY #<msg_expecting
  JSR printmsg    ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  LDA E           ; restore char
  JSR wrchr       ; uses A,X
  JSR newline     ; uses A,X
  JMP repl


; ------------------------------------------------------------------------------
; BASIC LIST

; @@ printkw
; Print a keyword directly from a Keyword Table
printkw:          ; 13 bytes
  LDA kwtab,Y     ; [4] first char
@loop:
  JSR wrchr       ; [6] print char (A=char, uses A,X)
  INY             ; [2] advance
  LDA kwtab,Y     ; [4] load next char
  BPL @loop       ; [3] until top-bit is set
  RTS             ; [6] done



; ------------------------------------------------------------------------------
; Numerics

; @@ num_u16
; tokenize a line number (0-65535)
num_u16:         ; X=ln (uses A,Y,B,C,Term) -> Acc,X,NE=found
  STX C          ; save ln-ofs
  JSR num_u24    ; from LineBuf,X -> Acc,X,CS=found (uses A,Y,B,C,Term)
  BCS err_range  ; -> out of range
  LDA Acc2       ; high byte is non-zero (or number is negative)
  ORA AccE       ; exponent is non-zero (a float)
  BNE err_range  ; -> out of range, negative, on non-integer
  CPX C          ; NE if found; EQ not-found
  RTS

err_range:
  LDY #<msg_range
  JMP report_err

tok_clc:
  CLC
  RTS            ; CC=not-found

; @@ num_val
; parse a 24-bit number with optional sign prefix (TODO: floating point)
num_val:         ; from LineBuf,X -> X,Acc,CS=ovf (uses A,X,Y,B,Term)
  LDA #0
  STA B          ; [3] sign=$00
  LDA LineBuf,X  ; [4] get first char
  CMP #$2D       ; [2] '-'
  BEQ @minus     ; [2] -> negative [+1]
@cont:
  JSR num_u24    ; [6] -> (Src),Y -> Acc,Y,CS=ovf,A=Acc3 (uses A,X,Term)
  BCS @ovf       ; [2] -> unsigned overflow
  LDA B          ; [3] get negate flag
  BNE num_neg    ; [6] negate Acc (uses A) -> Acc,CS=ovf
  BIT Acc2       ; [3] test top byte [NZV]
  BPL @ret       ; [2] -> ok
@ovf:
  SEC            ; [2] positive overflow
@ret:
  RTS            ; [6] -> Acc,Y,CS=ovf
@minus:
  INX            ; [2] consume '-'
  INC B          ; [5] set negate flag
  BNE @cont      ; [3] -> always (B=1)

; @@ num_neg
; one minus Acc (uses A) -> Acc,CS=ovf
num_neg:
  SEC            ; [2]
  LDA #0         ; [2]
  SBC Acc0       ; [3]
  STA Acc0       ; [3]
  LDA #0         ; [2]
  SBC Acc1       ; [3]
  STA Acc1       ; [3]
  LDA #0         ; [2]
  SBC Acc2       ; [3]
  STA Acc2       ; [3]
  RTS  

; @@ num_u24
; parse an unsigned 24-bit number
num_u24:         ; from LineBuf,X -> X,Acc,CS=ovf (uses A,X,Y,Term)
  LDA #0         ; [2] length of num
  STA Acc0       ; [3] clear result
  STA Acc1       ; [3]
  STA Acc2       ; [3]
  STA AccE       ; [3]
@loop:           ; -> 14+76+25 [115]
  LDA LineBuf,X  ; [4] get next char
  SEC            ; [2]
  SBC #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS @done      ; [2] >= 10 -> @done
  TAY            ; [2] save digit 0-9
  JSR num_mul10  ; [12+64=76] (uses A,Term) Acc *= 10
  BCS @ovf       ; [2] -> unsigned overflow [+1]
  TYA            ; [2] restore digit -> A
  CLC            ; [2]
  ADC Acc0       ; [3] add digit 0-9
  STA Acc0       ; [3]
  LDA Acc1       ; [3]
  ADC #0         ; [2] add carry
  STA Acc1       ; [3]
  LDA Acc2       ; [3]
  ADC #0         ; [2] add carry
  STA Acc2       ; [3]
  BCS @ovf       ; [2] -> unsigned overflow [+1]
  INX            ; [2] advance source
  BNE @loop      ; [3] -> always (unless Y wraps around)
@done:
  CLC            ; [2] success, no overflow
@ovf:
  RTS            ; [6] return Acc, Y=end, CS=overflow

; @@ num_mul10
; multiply unsigned Acc by 10 (uses A,Term)
num_mul10:      ; Uses A, preserves X,Y (+Term)
  LDA Acc0      ; [3] Term = Val * 2
  ASL           ; [2]
  STA Term0     ; [3]
  LDA Acc1      ; [3]
  ROL           ; [2]
  STA Term1     ; [3]
  LDA Acc2      ; [3]
  ROL           ; [2]
  STA Term2     ; [3]
  BCS @ovf      ; [2] -> unsigned overflow
  ASL Term0     ; [5] Term *= 2 (=Val*4)
  ROL Term1     ; [5]
  ROL Term2     ; [5]
  BCS @ovf      ; [2] -> unsigned overflow
  CLC           ; [2]
  LDA Acc0      ; [3] Acc += Term (=Val*5)
  ADC Term0     ; [3]
  STA Acc0      ; [3]
  LDA Acc1      ; [3]
  ADC Term1     ; [3]
  STA Acc1      ; [3]
  LDA Acc2      ; [3]
  ADC Term2     ; [3]
  STA Acc2      ; [3]
  BCS @ovf      ; [2] -> unsigned overflow
  ASL Acc0      ; [5] Acc *= 2 (=Val*10)
  ROL Acc1      ; [5]
  ROL Acc2      ; [5] sets CS on overflow
@ovf:
  RTS           ; [6] -> [106+6] CS=overflow


; @@ num_print
; print a number in Acc (TODO floating point)
num_print:       ; from {Acc0,1} (uses A,X,Y)
  LDA #0
  PHA            ; sentinel
@loop:
  JSR num_div10  ; {Acc0,1} /= 10 -> A = remainder (uses X)
  ORA #48        ; 0-9 -> '0'-'9'
  PHA
  LDA Acc0
  ORA Acc1
  ORA Acc2
  BNE @loop      ; -> until zero
@print:
  PLA
  BEQ @done
  JSR wrchr      ; print it (A=char, uses A,X)
  BNE @print     ; always (unless zero-byte)
@done
  RTS

; @@ num_div10
; divide {Acc0,1} by 10, returning A = remainder (uses X) (SLOW)
; shifts dividend left into remainder
; if remainder >= 10, subtracts 10 and shifts 1 left into quotient
; else shifts 0 left into quotient
num_div10:
  LDX #24        ; [2] 24 bits
  LDA #0         ; [2] remainder
@loop:
  ASL Acc0       ; [5] CF << dividend << 0 (quotient bit0 = 0)
  ROL Acc1       ; [5] CF << dividend << CF
  ROL Acc2       ; [5] CF << dividend << CF
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


; ------------------------------------------------------------------------------
; Keyword Table Search

; @@ scan_kw_idx
; find a matching keyword in a table indexed by first letter
scan_kw_idx:       ; X=ln-ofs A,Y=table -> CS=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  ; find first keyword for this letter
  STA Src          ; [3] table-low
  STY SrcH         ; [3] table-high
  ; start the search  
  LDY #$FF         ; [2] Y = -1
  STY D            ; [3] set search-mode: same-first-char (D7=1)
  INY              ; [2] word list offset (start of 1st word) = 0
  BEQ scan_kw_list ; [3] -> always

; @@ scan_kw_all
; scan a list of keywords, matching all keywords in the list
scan_kw_all:       ; X=ln-ofs A,Y=table -> CS=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  STA Src          ; [3] table-low
  STY SrcH         ; [3] table-high
  LDY #0           ; [2] word list offset (start of 1st word)
  STY D            ; [3] set search-mode: all-keywords (D7=0)
  ; +++ fall through to @@ scan_kw_list +++

; @@ scan_kw_list
; find a matching keyword (terminated by a byte with the top-bit set) in a zero-terminated list
; two search modes are supported:
; (D7=1) searches consecutive keywords that all start with the same letter, starting from A,Y
; (D7=0) searches the rest of the table, starting from A,Y
scan_kw_list:    ; X=ln-ofs Y=kw-ofs Src=kw-list D=search-mode -> CF=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  STX B          ; [3] save start of token
@next_kw:
  DEX            ; [2] nullify first pre-increment
  DEY            ; [2] nullify first pre-increment
  LDA #0         ; [2] zero
  STA C          ; [3] dot shorthand off (zero)
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
  LDX B          ; [3] restore X = start of token
  LDA (Src),Y    ; [5] first char of next keyword
  BEQ @not_found ; [2] -> zero byte, end of list [+1]
  BIT D          ; [3] check scan_kw_list mode
  BPL @next_kw   ; [2] -> check next keyword (D7=0: all-keywords mode) [+1]
  CMP LineBuf,X  ; [3] does it match first char? (D7=1: same-first-char mode)
  BEQ @next_kw   ; [2] -> check next keyword [+1]

  ; did not find a match
@not_found:
  CLC            ; [2] clear carry: no match found
  RTS            ; [6] X = start of token

; input and keyword chars differ by case
; check if keyword is lowercase (otherwise input is lowercase)
@match_en:       ; A = 32
  AND (Src),Y    ; is keyword lowercase? (bit 5 set)
  BEQ @no_match  ; -> keyword not lowercase (input is lowercase)
  STA C          ; [3] enable dot (A=32: non-zero)
  BNE @match_lp  ; [3] always jump

; match a dot input char, if shorthand enabled
@match_dot:      ; X=next-in Y=next-kw
  LDA C          ; [3] is dot enabled for this keyword?
  BEQ @no_match  ; [3] -> not enabled (zero), didn't match input
  INX            ; [2] advance over the dot
  DEY            ; [2] for pre-inc Y below
@dot_lp:         ; advance to byte with top-bit set
  INY            ; [2] pre-inc Y
  LDA (Src),Y    ; [5] check keyword char
  BPL @dot_lp    ; [3] -> top bit clear, keep going

@kw_found:
  SEC            ; [2] set carry: keyword was found
  RTS            ; [6] X = next-character A=hi-byte (top bit set)


; ------------------------------------------------------------------------------
; REPL Commands

; matches repl_tab entries in the same order
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
  LDA LOMEM         ; copy LOMEM into CODE
  STA CODE
  EOR TOP           ; 0 if LOMEM == TOP
  STA C
  LDA LOMEMH
  STA CODEH
  EOR TOPH          ; 0 if LOMEMH == TOPH
  EOR C
  BEQ @noprog       ; if 0 -> no program
  LDY #0            ; set CODE offset
  STY DataL         ; no data yet
  STY DataH         ; no data yet
  JMP do_ln_ex      ; -> expect first line
@noprog:
  RTS

cmd_auto:
  LDA #10            ; [2]
  STA LINE           ; [3] start from line 10
  STA AutoInc        ; [3] step by 10
  LDA #0             ; [2]
  STA LINEH          ; [3]
  JSR num_u16        ; [6] parse number at X -> X,Acc01,NE=found (uses A,Y,B)   XXX can it be a NO TEXT util?
  BEQ @start         ; [2] -> no number [+1]
  LDA Acc0           ; [3]
  STA LINE           ; [3] set start line
  LDA Acc1           ; [3]
  STA LINEH          ; [3]
  JSR skip_spc       ; [24+] X=ln-ofs -> X (uses A,X) leading spaces
  LDA LineBuf,X      ; [4]
  CMP #$2C           ; [2] ","
  BNE @start         ; [2] -> no comma
  JSR num_u16        ; [6] parse number at X -> X,Acc01,NE=found (uses A,Y,B)   XXX can it be a NO TEXT util?
  BEQ @start         ; [2] -> no number [+1]
  LDA Acc0           ; [3]
  STA AutoInc        ; [3]
  BEQ @range         ; [2] -> bad step (equals zero)
  LDA Acc1           ; [3]
  BNE @range         ; [2] -> bad step (non-zero high byte)
@start:
@loop:
  ; print the line number
  LDA LINE
  STA Acc0
  LDA LINEH
  STA Acc1
  JSR num_print
  LDA #32
  JSR wrchr          ; uses A,X
  ; read an input line
  JSR readline
  JSR newline
  ; parse and tokenise the line
  LDX #0
  JSR tokenize    ; tokenize the line; returns CF=valid?
  ; XXX insert the tokenized line into the BASIC program
  ; increment line number
  LDA AutoInc
  CLC
  ADC LINE
  STA LINE
  BCC @loop         ; -> no carry
  INC LINEH
  BNE @loop         ; -> loop until wraparound
  RTS
@range:
  JMP err_range

cmd_renum:
  RTS

cmd_delete:
  RTS

cmd_load:
  RTS

cmd_save:
  RTS

cmd_new:
  LDA LOMEM        ; bottom of BASIC memory
  STA TOP          ; end of BASIC program
  LDA LOMEMH       ; bottom of BASIC memory high
  STA TOPH         ; end of BASIC program high
  RTS

cmd_old:
  ; XX walk old program and verify valid lines
  RTS



; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

; jump table
stmt_l:
  DB <do_cls
  DB <do_close
  DB <do_data
  DB <do_dim
  DB <do_deffn
  DB <do_defproc
  DB <do_else
  DB <do_end
  DB <do_for
  DB <do_goto
  DB <do_gosub
  DB <do_if
  DB <do_input
  DB <do_let
  DB <do_line
  DB <do_local
  DB <do_mode
  DB <do_next
  DB <do_opt
  DB <do_open
  DB <do_plot
  DB <do_poke
  DB <do_print
  DB <do_proc
  DB <do_read
  DB <do_repeat
  DB <do_fill
  DB <do_restore
  DB <do_return
  DB <do_rem
  DB <do_copy
  DB <do_sound
  DB <do_until
  DB <do_wait
  DB <do_window
  DB <do_fnret
  DB <do_thenln
  DB <do_elseln
  DB <do_ln1
stmt_h:
  DB >do_cls
  DB >do_close
  DB >do_data
  DB >do_dim
  DB >do_deffn
  DB <do_defproc
  DB >do_else
  DB >do_end
  DB >do_for
  DB >do_goto
  DB >do_gosub
  DB >do_if
  DB >do_input
  DB >do_let
  DB >do_line
  DB >do_local
  DB >do_mode
  DB >do_next
  DB >do_opt
  DB >do_open
  DB >do_plot
  DB >do_poke
  DB >do_print
  DB >do_proc
  DB >do_read
  DB >do_repeat
  DB >do_fill
  DB >do_restore
  DB >do_return
  DB >do_rem
  DB >do_copy
  DB >do_sound
  DB >do_until
  DB >do_wait
  DB >do_window
  DB >do_fnret
  DB >do_thenln
  DB >do_elseln
  DB >do_ln1

; control frame tags
TOK_FOR    = $F0
TOK_FOR_S  = $F1
TAG_GOSUB  = $F2

; variable tags
VT_NUM = 1
VT_STR = 2
VT_NUM_ARR = 3
VT_STR_ARR = 4
VT_FN = 5
VT_PROC = 6


; --- DISPATCH ---

; expect start of next line
do_ln_ex:
  LDA (CODE),Y   ; [5] load token
  CMP #OP_LN     ; [2]
  BNE do_syn0    ; [2] -> syntax error
  ; +++ fall through to @@ do_ln0 +++

; start a new line: fold Y into CODE.
; assumes (CODE),Y points at OP_LN.
do_ln0:          ; advance past OP_LN and line header; add Y to CODE
  INY            ; [2] skip OP_LN
do_ln1:          ; advance past line header; add Y to CODE
  TYA            ; [2] get accumulated Y
  LDY #4         ; [2] skip (LineLo,LineHi,LenBk,LenFw)
  CLC            ; [2]
  ADC CODE       ; [3] add Y to CODE
  STA CODE       ; [3] update CODE
  BCC do_stmt    ; [2] -> no overflow [+1]
  INC CODEH      ; [5]
  ; +++ fall through to @@ do_stmt +++

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
  LDA stmt_h,X   ; [4]
  STA SrcH       ; [3]
  JMP (Src)      ; [5]  /30 total  (XXX write $C0+ token into JMP in RAM /18)


; --- LET, DIM ---

do_let:
  ; check for VAR (implied LET)
  AND #$DF       ; [2] lower -> upper (clear bit 5)
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CS if >= 26)
  BCS do_syn0    ; [2] -> syntax error
  ; get ptr to var-list at TOP for this letter
  STY B          ; [3] save Y=code-ofs
  ASL A          ; [2] letter * 2
  TAY            ; [2] 0-25 letter boxes
  LDA (TOP),Y    ; [5] var-list pointer low byte
  STA Src        ; [3] 
  INY            ; [2] next byte
  LDA (TOP),Y    ; [5] var-list pointer high byte
  STA SrcH       ; [3] 
  ; scan the list for a matching VAR
  ; XXX

do_syn0:
  LDY #<msg_syntax
  JMP report_err

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


; END: end the program (return to REPL)
do_end:
  JMP repl


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
  LDA #TOK_FOR    ;
@cont:
  STA B           ; save tag
  JSR push_code   ; save return CODE (uses A,Y -> Y=0)
  LDA B           ; restore tag
  PHA             ; push "FOR" control tag
  JMP do_stmt     ; [3] -> next stmt
@step:
  JSR do_expr_n   ; [12+] -> evaluate numeric "STEP" expression (onto stack) [4]
  LDA #TOK_FOR_S  ;
  BNE @cont       ; -> continue with FOR


; NEXT: optional VAR (array indices)
;       scan control stack for matching FOR 'VAR' (same name, address);
;       add STEP to VAR;
;       compare VAR vs TO based on STEP sign;
;       continue -> restore Code address -> jump to STMT loop
;       otherwise, jump to STMT loop
do_next:
  JMP do_stmt


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
  JSR do_expr_b  ; [12+] boolean expr (uses A,X,Y,???)
  BCC do_else    ; [2] -> cond is false, advance to ELSE (re-uses do_else code) [+1]
  INY            ; [2] skip length-byte (for ELSE)
  JMP do_stmt    ; [3] -> next stmt


; REM skip Len bytes to reach EOL
do_rem:
  ; +++ fall through to @@ do_else +++

; DATA: skip Len bytes to reach EOL
do_data:
  ; +++ fall through to @@ do_else +++

; ELSE: skip Len bytes to reach EOL
; (also used to skip DATA and to skip THEN code/ELSE code)
do_else:
  LDA (CODE),Y    ; [5] get Length
  STY B           ; [3] save Y
  SEC             ; [2] +1 (advance)
  ADC B           ; [3] Y += Len + 1
  TAY             ; [2]
  JMP do_stmt     ; [6] -> next stmt


; --- GOTO, GOSUB, RETURN ---

; THEN-ln (variant of GOTO, for LIST command)
do_thenln:
  ; +++ fall through to @@ do_goto +++

; ELSE-ln (variant of GOTO, for LIST command)
do_elseln:
  ; +++ fall through to @@ do_goto +++

; GOTO: do_expr_u16;
;       scan either dir for matching line;
;       set CODE and jump to do_ln
do_goto:           ; A=next-tok
  JSR do_expr_u16  ; evaluate integer expression (Acc01)
go_line:
  JSR find_line    ; find matching line (addr of 1st statement -> Acc01) or error
  LDA Acc0
  STA CODE
  LDA Acc1
  STA CODEH
  LDY #0
  JMP do_stmt      ; next stmt


; GOSUB: do_expr_n;
;       scan either dir for matching line;
;       push GOSUB frame on control stack, with return Code address;
;       set Code and jump to LINE start
do_gosub:
  JSR do_expr_u16 ; [12+] -> evaluate u16 expression (to Acc01) [2]
  JSR push_code   ; [12+] -> save return CODE
  LDA #TAG_GOSUB  ; [2]
  PHA             ; [3]
  JMP go_line     ; [12+] -> find matching line and jump to it


; RETURN:
;       scan control stack for matching GOSUB frame;
;       pop GOSUB frame and restore Code address;
;       jump to STMT loop
do_return:
  JMP do_stmt


; --- REPEAT, UNTIL ---

; REPEAT push a control frame
do_repeat:
  JMP do_stmt


; UNTIL
do_until:
  JMP do_stmt


; --- DATA, READ, RESTORE ---

; READ VARs[$]
;      if data-ptr is FFFF, scan for first DATA-line
;      read vars from current data-ptr and advance
;      find vars and assign new values
do_read:
  JMP do_stmt


; RESTORE [expr_n]
;         scan from line N (or first) for first DATA statement
;         set the data-ptr
do_restore:
  JSR do_expr_u16   ; evaluate int16 expression (to Acc01)
  JSR find_line     ; find matching line (addr of 1st statement -> Acc01) or error
  LDA Acc0
  STA DataL         ; pointer to next data, low
  LDA Acc1
  STA DataH         ; pointer to next data, high
  JMP do_stmt


; --- PRINT, INPUT ---

; INPUT:
do_input:         ; uses PRINT parser (mode)
  JMP do_stmt


; PRINT
do_print:
  ; loop:
  ; if str -> JSR print (A,B,C,D,E,X,Y,Src,Dst)
  ; find var
  ; cvt -> linebuf -> print
  ; etc
  JMP do_stmt


; --- OPEN, CLOSE ---

; OPEN: open a file
do_open:
  JMP do_stmt


; CLOSE: expect '#' expr
;        verify channel is open;
;        flush any queued data;
;        mark channel closed
do_close:
  JMP do_stmt     ; -> next stmt


; --- POKE, OPT ---

; OPT: set option
do_opt:
  LDX #2           ; evaluate 2 arguments
  JSR args_i8      ; stack: (Option,Value) <-
  JMP do_stmt


; POKE expr_n ',' expr_n
;      write byte to memory
do_poke:
  JSR do_expr_u16  ; evaluate int16 expression (to Acc01)
  JSR do_expr_i8   ; A = value to poke
  LDX #0           ; index
  STA (Acc0,X)     ; write to memory at (Acc01)
  JMP do_stmt


; --- FN ---

; DEFFN: define function
do_deffn:
  JMP do_stmt     ; -> next stmt

do_fnret:
  ; return from function
  ; 1. find FN on control stack [num/$]
  JSR do_expr   ; do_expr_s or do_expr_n (depends on [num/$] flag)
  ; 2. pop FN frame and Code Address
  JMP do_stmt


; --- PROC ---

; DEFPROC: define procedure
do_defproc:
  JMP do_stmt     ; -> next stmt

; PROC: call PROC <name>
do_proc:
  LDA #VT_PROC    ; variable tag
  JSR find_var    ; PROCs are indexed as vars (report not found)
  ;
  JMP do_stmt

; LOCAL: expect VAR
;        verify inside a PROC (control stack)
;        do the thing
do_local:
  JMP do_stmt


; --- MODE, WAIT, CLS ---

; MODE do_expr_n
do_mode:
  STY E            ; save CODE offset
  JSR do_expr_i8   ; A = mode
  JSR vid_mode     ; set mode (A=mode, uses A,X,Y,B)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt

; WAIT frames
do_wait:
  JSR do_expr_i8   ; A = i8   (XX need to save Y?)
  TAX
  BNE @loop        ; -> non-zero
  INX              ; wait 0 -> wait 1
@loop:
  LDA IO_VLIN      ; get vertical line counter
  CMP #192       ; at bottom of screen?
  BNE @loop        ; wait for line == 192
@stall:
  LDA IO_VLIN      ; get vertical line counter
  CMP #192       ; at bottom of screen?
  BEQ @stall       ; wait for line != 192
  DEX
  BNE @loop        ; -> is not zero, loop
@done:
  JMP do_stmt

; CLS: clear the screen
do_cls:
  STY E            ; save CODE offset
  JSR vid_cls      ; (uses A,X,Y)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt


; --- WINDOW ---

; WINDOW: set a text window
do_window:
  STY E            ; save CODE offset
  LDX #4           ; evaluate 4 arguments
  JSR args_i8      ; stack: (X,Y,W,H) <-
  TSX
  ; left
  LDA $103,X       ; X coordinate low byte
  AND #31          ; modulo 32
  STA WinL         ; set window left
  ; top
  LDA $102,X       ; Y coordinate low byte
  CMP #23          ; clamp if >23
  BCC @y_ok        ; CC < 23
  LDA #23          ; maximum 23
@y_ok
  STA WinT         ; set window top
  ; width
  SEC
  LDA #32
  SBC WinL         ; 32 - WinL (minimum 1)
  CMP $101,X       ; is (32-WinL) < W
  BCC @w_ok        ; CC < W (not enough space for W, use (32-WinL))
  LDA $101,X       ; use W
@w_ok:
  STA WinW         ; set window width
  ; height
  SEC
  LDA #24
  SBC WinT         ; 24 - WinT (minimum 1)
  CMP $100,X       ; is (24-WinT) < H
  BCC @h_ok        ; CC < H (not enough space for H, use (24-WinT))
  LDA $100,X       ; use H
@h_ok:
  STA WinH         ; set window height
  ; clean up
  PLA              ; pop X
  PLA              ; pop Y
  PLA              ; pop W
  PLA              ; pop H
  ; move cursor
  JSR txt_home     ; move cursor to (0,0) in the window (uses A,X,Y)
  LDY E            ; restore CODE offset
  JMP do_stmt


; --- COPY, FILL ---

; @@ do_copy
; copy the text screen by (X,Y)
do_copy:
  STY E            ; save CODE offset
  LDX #6           ; evaluate 6 arguments
  JSR args_i8      ; stack: (X,Y,W,H) <-
  JSR txt_copy     ; text copy from (X,Y) to (X,Y) size (W,H)
  LDY E            ; restore CODE offset
  JMP do_stmt

; @@ do_fill
; fill the text screen from (X0,Y0) to (X1,Y1) with (CH)
do_fill:
  STY E            ; save CODE offset
  LDX #4           ; evaluate 4 arguments
  JSR args_i8      ; stack: (X0,Y0,X1,Y1,W,H) <-
  JSR gfx_fill     ; -> fill rectangle (X0,Y0)-(X1,Y1)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt


; --- SOUND ---

do_sound:
  LDX #3           ; evaluate 3 arguments
  JSR args_i8      ; stack: (Pitch,Volume,Length) <-
  JMP do_stmt


; --- GRAPHICS ---

; PLOT: plot a point (x,y)
do_plot:
  STY E            ; save CODE offset
  LDX #2           ; evaluate 2 arguments
  JSR args_i8      ; stack: (X,Y) <-
  JSR gfx_plot     ; -> draw a point (X,Y)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt

; LINE: draw bresenham line (x,y)
do_line:
  STY E            ; save CODE offset
  LDX #4           ; evaluate 4 arguments
  JSR args_i8      ; stack: (X0,Y0,X1,Y1) <-
  JSR gfx_line     ; -> draw bresenham line (X0,Y0)-(X1,Y1)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt


; --- VARIABLES ---

; @@ bind_var
; find or insert named variable for assignment
bind_var:
  RTS


; @@ find_var
; find named variable for reading
find_var:
  RTS


; --- HELPERS ---

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
  RTS
@newln:
  TYA             ; [2] get accumulated Y                      (optional)
  LDY #5          ; [2] skip (OpLn,LineLo,LineHi,LenBk,LenFw)  (optional)
  BNE @push       ; [3] -> now push it                         (optional)


; @@ find_line
; find matching line (Acc01) -> addr of 1st stmt (Acc01) or error
find_line:
; TODO starts from current CODE and searches towards target
; TODO report error if line not found
  RTS


; --- EXPRESSIONS ---

; @@ do_expr
; evaluate an expression (XXX should be do_expr_n, do_expr_s, do_expr_b)   (TODO errors?)
; XXX "PRINT" is the outlier, accepting all types...
; XXX tracked state: expect a comma after each expr except the first?
do_expr:
do_expr_n:
do_expr_i:
do_expr_s::
  RTS


; @@ do_expr_b
; evaluate a boolean expression -> CC|CS
do_expr_b:
  ; XX detect string expr
  JSR do_expr_i   ; -> evaluate integer expression  (TODO errors?)
  ; XX cast to bool
  RTS


; @@ do_expr_u16
; evaluate integer expression, range-check u16, return Acc01
do_expr_u16:
  JSR do_expr_i   ; -> evaluate integer expression  (TODO errors?)
  LDA AccE
  ORA Acc2
  BNE do_range    ; -> out of range, negative, on non-integer
  RTS

; @@ do_expr_i8
; evaluate i8 expression -> A  (TODO errors?)
do_expr_i8:
  JSR do_expr_i   ; -> evaluate integer expression  (TODO: uses Y?)
  LDA Acc0        ; get low byte (modulo 256)
  RTS

; @@ args_i8
; parse #X x i8 arguments, push on stack
args_i8:
  STX E           ; save counter
  JSR do_expr_i8  ; parse i8 -> A  (TODO errors?)
  PHA             ; push argument
  ; check for comma
  DEC E           ; decrement counter
  BNE args_i8
  ; push zeros until counter=0 ?
  RTS

; @@ do_range
; report "out of range" error
do_range:
  JMP err_range


; ------------------------------------------------------------------------------
; PAGE 7 - Statement Tokens

ORG $FA00

OP_CLS     = $C1   ; 0x01 when top bits masked off
OP_CLOSE   = $C2
OP_COPY    = $DF
OP_DATA    = $C3
OP_DIM     = $C4
OP_DEFFN   = $C5   ; must be even
OP_DEFPROC = $C6   ; must be odd
OP_ELSE    = $C7   ; ELSE with <length>     (OP_ELSE,$xx vs source "EL.")
OP_END     = $C8
OP_FILL    = $DB
OP_FOR     = $C9
OP_GOTO    = $CA
OP_GOSUB   = $CB
OP_IF      = $CC   ; IF <else-ofs> <cond> (THEN1,0xNN | THEN2,0xNN,0xMM | THEN | ε)   [OP_IF,$nn vs "IF"]
OP_INPUT   = $CD
OP_LET     = $CE
OP_LINE    = $CF
OP_LOCAL   = $D0
OP_MODE    = $D1
OP_NEXT    = $D2
OP_OPT     = $D3
OP_OPEN    = $D4
OP_PLOT    = $D5
OP_POKE    = $D6
OP_PRINT   = $D7
OP_PROC    = $D8
OP_READ    = $D9
OP_REPEAT  = $DA
OP_RESTORE = $DC
OP_RETURN  = $DD
OP_REM     = $DE
OP_SOUND   = $E0
OP_UNTIL   = $E1
OP_WAIT    = $E2
OP_WINDOW  = $E3
OP_STEP    = $E4
OP_THEN    = $E5
OP_THENLN  = $E6
OP_ELSELN  = $E7
OP_LN      = $E8 ; start-of-line


ALIGN $100
stmt_page:

kws_a:
kws_b:
kws_c:
kw_cls    DB "CLS",      OP_CLS
kw_close  DB "CLOSE",    OP_CLOSE  ; #ch
kw_copy   DB "COPY",     OP_COPY
kws_d:
kw_data   DB "DATA",     OP_DATA
kw_dim    DB "DIM",      OP_DIM
kw_def    DB "DEF",      OP_DEFFN
kws_e:
kw_else   DB "ELSE",     OP_ELSE
kw_end    DB "END",      OP_END
kws_f:
kw_fill   DB "FILL",     OP_FILL
kw_for    DB "FOR",      OP_FOR
kws_g:
kw_goto   DB "GOTO",     OP_GOTO
kw_gosub  DB "GOSUB",    OP_GOSUB
kws_h:
kws_i:
kw_if     DB "IF",       OP_IF
kw_input  DB "INPUT",    OP_INPUT  ; [#ch,]
kws_j:
kws_k:
kws_l:
kw_let    DB "LET",      OP_LET
kw_line   DB "LINE",     OP_LINE
kw_local  DB "LOCAL",    OP_LOCAL
kws_m:
kw_mode   DB "MODE",     OP_MODE
kws_n:
kw_next   DB "NEXT",     OP_NEXT
kws_o:
kw_opt    DB "OPT",      OP_OPT
kw_open   DB "OPEN",     OP_OPEN
kws_p:
kw_plot   DB "PLOT",     OP_PLOT
kw_poke   DB "POKE",     OP_POKE
kw_print  DB "PRINT",    OP_PRINT  ; [#ch,]
kw_proc   DB "PROC",     OP_PROC
kws_q:
kws_r:
kw_read   DB "READ",     OP_READ
kw_rept   DB "REPEAT",   OP_REPEAT
kw_rest   DB "RESTORE",  OP_RESTORE
kw_retr   DB "RETURN",   OP_RETURN
kw_rem    DB "REM",      OP_REM
kws_s:
kw_soun   DB "SOUND",    OP_SOUND
kws_t:
kws_u:
kw_until  DB "UNTIL",    OP_UNTIL
kws_v:
kws_w:
kw_wait   DB "WAIT",     OP_WAIT
kw_wind   DB "WINDOW",   OP_WINDOW
kws_x:
kws_y:
kws_z:
  DB 0 ; end of list

; Statement Index
stmt_idx:
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

; Statement Reverse Lookup    ; (COULD linear-search the Statement Tokens...)
stmt_rev:                     ; [34] indices MUST match OPCODEs
  DB (kw_cls - stmt_page)     ; "CLS",$C4
  DB (kw_close - stmt_page)   ; "CLOSE",$C6
  DB (kw_copy - stmt_page)    ; "COPY",$E9
  DB (kw_data - stmt_page)    ; "DATA",$C7
  DB (kw_dim - stmt_page)     ; "DIM",$C9
  DB (kw_def - stmt_page)     ; "DEF",$CA
  DB (kw_else - stmt_page)    ; "ELSE",$CB
  DB (kw_end - stmt_page)     ; "END",$CD
  DB (kw_fill - stmt_page)    ; "FILL",$E2
  DB (kw_for - stmt_page)     ; "FOR",$CE
  DB (kw_goto - stmt_page)    ; "GOTO",$CF
  DB (kw_gosub - stmt_page)   ; "GOSUB",$D0
  DB (kw_if - stmt_page)      ; "IF",$D1
  DB (kw_input - stmt_page)   ; "INPUT",$D2
  DB (kw_let - stmt_page)     ; "LET",$D3
  DB (kw_line - stmt_page)    ; "LINE",$C8
  DB (kw_local - stmt_page)   ; "LOCAL",$D4
  DB (kw_mode - stmt_page)    ; "MODE",$D6
  DB (kw_next - stmt_page)    ; "NEXT",$D7
  DB (kw_opt - stmt_page)     ; "OPT",$D9
  DB (kw_open - stmt_page)    ; "OPEN",$DB
  DB (kw_plot - stmt_page)    ; "PLOT",$DD
  DB (kw_poke - stmt_page)    ; "POKE",$C1
  DB (kw_print - stmt_page)   ; "PRINT",$DC
  DB (kw_proc - stmt_page)    ; "PROC",$DE
  DB (kw_read - stmt_page)    ; "READ", $E0
  DB (kw_rept - stmt_page)    ; "REPEAT",$E1
  DB (kw_rest - stmt_page)    ; "RESTORE",$E3
  DB (kw_retr - stmt_page)    ; "RETURN",$E4
  DB (kw_rem - stmt_page)     ; "REM",$E5
  DB (kw_soun - stmt_page)    ; "SOUND",$EA
  DB (kw_until - stmt_page)   ; "UNTIL",$ED
  DB (kw_wait - stmt_page)    ; "WAIT",$F0
  DB (kw_wind - stmt_page)    ; "WINDOW",$F1   {39}

; 19 bytes free

; ------------------------------------------------------------------------------
; PAGE 8 - Expression Tokens

ALIGN $100
expr_page:
kwtab:

OPS_NUM  = $B0       ; all of $Bx are number literals

OP_I0    = $B0       ; 1-byte
OP_I9    = $B9       ; 1-byte
OP_INT1  = $BA       ; 2-byte
OP_INT2  = $BB       ; 3-byte
OP_INT4  = $BC       ; 5-byte

; use C0 codes for these (in precedence order)
OP_POW   = $10
OP_MUL   = $11
OP_DIV   = $12
OP_ADD   = $13
OP_SUB   = $14
OP_EQ    = $15
OP_NE    = $16
OP_LT    = $17
OP_LE    = $18
OP_GT    = $19
OP_GE    = $1A

OP_UNEG  = $1B       ; unary
OP_UPLUS = $1C       ; unary

OP_STR   = $1D


; EXPRESSION TOKENS

expr_a:
expr_b:
ex_abs  DB "ABS",     $80      ; fn (0,0)
ex_at   DB "AT",      $81      ; fn (0,2)  read pixel at (x,y)
ex_asc  DB "ASC",     $82      ; fn (0,1)  ascii code from string
expr_c:
ex_chr  DB "CHR",     $83      ; fn$ (1,1)
ex_cos  DB "COS",     $84      ; fn (0,1)
expr_d:
expr_e:
ex_eof  DB "EOF",     $85      ; # function (2,0)
ex_err  DB "ERR",     $86      ; no-arg (0,0)
ex_erl  DB "ERL",     $87      ; no-arg (0,0)
expr_f:
ex_fn   DB "FN",      $88      ; function-call (9)
expr_g:
ex_get  DB "GET",     $89      ; fn-or-fn$ (8,0)
expr_h:
expr_i:
ex_ink  DB "INKEY",   $90      ; fn-or-fn$ (8,1) 1st is $
ex_ins  DB "INSTR",   $91      ; fn$ (1,1) 1st is $
ex_int  DB "INT",     $92      ; fn (0,1)
expr_j:
expr_k:
expr_l:
ex_len  DB "LEN",     $93      ; fn-or-fn# (B,1) 1st is $
ex_lft  DB "LEFT",    $94      ; fn$ (1,2) 1st is $
expr_m:
ex_mid  DB "MID",     $95      ; fn$ (1,3) 1st is $
expr_n:
expr_o:
expr_p:
ex_pos  DB "POS",     $96      ; fn-or-fn# (B,0)  cursor x
ex_pi   DB "PI",      $97      ; no-arg (0,0)
expr_q:
expr_r:
ex_rgt  DB "RIGHT",   $98      ; fn$ (1,2) 1st is $
ex_rnd  DB "RND",     $99      ; fn (0,1)
expr_s:
ex_str  DB "STR",     $9A      ; fn$ (1,1) 1st is $
ex_sin  DB "SIN",     $9B      ; fn (0,1)
ex_sqr  DB "SQR",     $9C      ; fn (0,1)
ex_sgn  DB "SGN",     $9D      ; fn (0,1)
expr_t:
ex_tme  DB "TIME",    $9E      ; no-arg (0,0)
ex_top  DB "TOP",     $9F      ; no-arg (0,0)
expr_u:
ex_usr  DB "USR",     $A0      ; fn (0,1)
expr_v:
ex_val  DB "VAL",     $A1      ; fn (0,1)
ex_vps  DB "VPOS",    $A2      ; no-arg (3,0)   cursor y
expr_w:
expr_x:
expr_y:
expr_z:
  DB 0

kw_prefix:
kw_not  DB "NOT",     $A3      ; operator
kw_infix:
kw_and  DB "AND",     $A4      ; operator
kw_div  DB "DIV",     $A5      ; operator
kw_eor  DB "EOR",     $A6      ; operator
kw_mod  DB "MOD",     $A7      ; operator
kw_or   DB "OR",      $A8      ; operator


; context keywords (keep on one page for Y indexing)
; note: `kwtab` is at start of page
kwt_to:
  DB "TO",       $FF      ; FOR keyword
kwt_step:
  DB "STEP",     OP_STEP  ; FOR keyword
kwt_then:
  DB "THEN",     OP_THEN  ; IF keyword
kwt_spc:
  DB "SPC",      $83      ; print opcodes
kwt_tab:
  DB "TAB",      $84      ; print opcodes
  OP_COMMA =     $80      ; print opcodes
  OP_SEMI =      $81      ; print opcodes
  OP_EOL =       $82      ; print opcodes
kwt_fn:
  DB "FN",       $00      ; DEF keyword
kwt_proc:
  DB "PROC",     $01      ; DEF keyword
kwt_stmt:
  DB "statement",  $FF    ; Expecting
kwt_expr:
  DB "expression", $FF    ; Expecting
kwt_var:
  DB "variable",   $FF    ; Expecting



expr_rev:                  ; [29]
  DB (ex_abs - expr_page)  ; "ABS",$80
  DB (ex_at - expr_page)   ; "AT",$99
  DB (ex_asc - expr_page)  ; "ASC",$82
  DB (ex_chr - expr_page)  ; "CHR",$86
  DB (ex_cos - expr_page)  ; "COS",$87
  DB (ex_eof - expr_page)  ; "EOF",$8A
  DB (ex_err - expr_page)  ; "ERR",$8B
  DB (ex_erl - expr_page)  ; "ERL",$8C
  DB (ex_fn  - expr_page)  ; "FN",$8F
  DB (ex_get - expr_page)  ; "GET",$90
  DB (ex_ink - expr_page)  ; "INKEY",$91
  DB (ex_ins - expr_page)  ; "INSTR",$92
  DB (ex_int - expr_page)  ; "INT",$93
  DB (ex_len - expr_page)  ; "LEN",$94
  DB (ex_lft - expr_page)  ; "LEFT",$95
  DB (ex_mid - expr_page)  ; "MID",$98
  DB (ex_pos - expr_page)  ; "POS",$9A
  DB (ex_pi  - expr_page)  ; "PI",$9B
  DB (ex_rgt - expr_page)  ; "RIGHT",$9C
  DB (ex_rnd - expr_page)  ; "RND",$9E
  DB (ex_str - expr_page)  ; "STR",$9F
  DB (ex_sin - expr_page)  ; "SIN",$A0
  DB (ex_sqr - expr_page)  ; "SQR",$A1
  DB (ex_sgn - expr_page)  ; "SGN",$A3
  DB (ex_tme - expr_page)  ; "TIME",$A6
  DB (ex_top - expr_page)  ; "TOP",$A7
  DB (ex_usr - expr_page)  ; "USR", $A8
  DB (ex_val - expr_page)  ; "VAL",$A9
  DB (ex_vps - expr_page)  ; "VPOS",$AA

kw_rev_pre:
  DB (kw_not - expr_page)  ; "NOT",$AB

kw_rev_inf:
  DB (kw_and - expr_page)  ; "AND",$AC
  DB (kw_div - expr_page)  ; "DIV",$AD
  DB (kw_eor - expr_page)  ; "EOR",$AE
  DB (kw_mod - expr_page)  ; "MOD",$AF
  DB (kw_or  - expr_page)  ; "OR",$B0

; 16 bytes free

; ------------------------------------------------------------------------------
; PAGE B - Repl Commands
ALIGN $100

; Command list for the repl
; matches repl_fn table
repl_len = 9
repl_tab:
  DB "LIST",$80
  DB "RUN",$81
  DB "AUTO",$82
  DB "RENUM",$83
  DB "DEL",$84
  DB "LOAD",$85
  DB "SAVE",$86
  DB "NEW",$87
  DB "OLD",$88
  DB 0


; Expression Index
expr_idx:
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



; ------------------------------------------------------------------------------
; PAGE C - GRAPHICS ROUTINES

; @@ gfx_plot
; draw a point at (X,Y)
; all params are s16 on the stack
gfx_plot:          ; uses (A,X,Y)
  RTS

; @@ gfx_line
; draw a Bresenham line (X0,Y0) to (X1,Y1)
; all params are s16 on the stack
gfx_line:          ; uses (A,X,Y)
  RTS

; @@ gfx_fill
; fill a rectangle (X0,Y0) to (X1,Y1)
; all params are s16 on the stack
gfx_fill:          ; uses (A,X,Y)
  RTS


; ------------------------------------------------------------------------------
; PAGE 10 - SYSTEM

; @@ key_scan
; scan the keyboard matrix for a keypress
; [..ABCDE....]
;    ^hd  ^tl     ; empty when hd==tl, full when tl+1==hd
keyscan:          ; uses A,X,Y returns nothing (CANNOT use B,C,D,E)
  LDY #8          ; [2] last key column
  STY IO_KEYB     ; [3] set keyscan column (0-7)
  LDA IO_KEYB     ; [3] read row_bitmap
  STA ModKeys     ; [3] update modifier keys
  DEY             ; [2] prev column
; debounce check
  CMP IO_KEYB     ; [3] check if stable (3+2+3)/2MHz=4µs later
  BNE keyscan     ; [2] if not -> try again
@col_lp:          ; -> [13] cycles
  STY IO_KEYB     ; [3] set keyscan column (0-7)
  LDX IO_KEYB     ; [3] read row_bitmap
  BNE @key_hit    ; [2] -> one or more keys pressed [+1]
  DEY             ; [2] prev column
  BPL @col_lp     ; [3] go again, until Y<0
  STY LastKey     ; [3] no keys pressed: clear last key pressed (to $FF)
  RTS             ; [6] TOTAL Scan 2+13*8-1+6 = [111] cycles
@key_hit:         ; X=row_bitmap Y=column
  STY IRQTmp      ; [3] save keyscan column for resuming later
  TYA             ; [2] active keyscan column
  ASL             ; [2] column * 8
  ASL             ; [2] 
  ASL             ; [2] 
; debounce check 
  CPX IO_KEYB     ; [3] check if stable 17/2Mhz = 8.5µs later
  BNE @col_lp     ; [2] if not -> try again
  TAY             ; [2] scantab offset = col*8 as index
  TXA             ; [2] row_bitmap
; find first bit set
; loop WILL terminate because A is non-zero!
@bsf_lp:          ; A=row_bitmap Y=scantab -> [7] cycles
  INY             ; [2] count number of shifts
  ASL A           ; [2] shift keys bits left into CF
  BCC @bsf_lp     ; [3] until CF=1
; translate to ascii
  BIT ModKeys     ; [3] test shift key [N=Esc][V=Shf]
  BVS @shift      ; [2] -> shift is down (bit 6)
  TAX             ; [2] save remaining row_bitmap
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
  RTS             ; XXXXX debug (1-key, we want 2-key)
  TXA             ; [2] restore row_bitmap
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
  DB  $38, $39, $30, $2D, $3D, $60, $08, $01     ;     8 9 0 - = ` Del Up
  DB  $69, $6F, $70, $5B, $5D, $5C, $00, $02     ;     i o p [ ] \     Down
  DB  $6B, $6C, $3B, $27, $00, $00, $0D, $03     ;     k l ; '     Ret Left
  DB  $2C, $2E, $2F, $00, $00, $00, $20, $04     ;     , . /       Spc Right
scanshf:
  DB  $1B, $21, $40, $23, $24, $25, $5E, $26     ;   Esc ! @ # $ % ^ &
  DB  $09, $51, $57, $45, $52, $54, $59, $55     ;   Tab Q W E R T Y U
  DB  $0E, $41, $53, $44, $46, $47, $48, $4A     ;  Caps A S D F G H J
  DB  $00, $5A, $58, $43, $56, $42, $4E, $4D     ;       Z X C V B N M
  DB  $2A, $28, $29, $5F, $2B, $7E, $08, $01     ;     * ( ) _ + ~ Del Up
  DB  $49, $4F, $50, $7B, $7D, $7C, $00, $02     ;     I O P { } |     Down
  DB  $4B, $4C, $3A, $22, $00, $00, $0D, $03     ;     K L : "     Ret Left
  DB  $3C, $3E, $3F, $00, $00, $00, $20, $04     ;     < > ?       Spc Right

; $00 No key
; $01 Up
; $02 Down
; $03 Left
; $04 Right
; $08 Backspace
; $09 Tab
; $0D Return
; $0E CapsLock
; $1B Escape

; @@ readchar
; read a single character from the keyboard buffer
; AUTO-REPEAT: the last key held (save its scancode to compare)
; ROLLOVER: pressing a new key replaces the prior held key
; INKEY(-K): directly scans the key (5:3 col:row)
readchar:        ; uses A,X,Y returns ASCII or zero
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
; PRINT, WRCHR, WRCTL, NEWLINE

; @@ wrchr
; write a single character to the screen
; assumes we're in text mode with TXTP set up
wrchr:           ; A=char; (uses A,X,Src,Dst,F) preserves Y [25]
  CMP #32        ; [2] is it a control character?
  BCC wrctl      ; [2] -> ch < 32, do control code [+1]  (uses A,X preserves Y)
  LDX #0         ; [2] const for (TXTP,X) ie (TXTP)
  STA (TXTP,X)   ; [6] write character to video memory
  DEC WinRem     ; [5] at right edge of window?
  BEQ @nl        ; [2] if so -> newline [+1]
  INC TXTP       ; [5] advance text position
  RTS            ; [6]
@nl:
  INC WinRem     ; [5] let newline do it, so it can detect TXTPH increment (fix!)
  ; +++ fall through to @@ newline +++

; @@ newline, in "text mode"
; advance to the next line inside the text window
; scroll the text window if we're at the bottom
; assumes we're in text mode with TXTP set up
newline:         ; (uses A,X,Src,Dst,F) preserves Y
  LDX CurY       ; [3] get Cursor Y
  INX            ; [2] advance Cursor Y
  CPX WinH       ; [3] off the bottom of the window?
  BEQ @scroll    ; [2] -> scroll down [+1]
  STX CurY       ; [3] update Cursor Y
; advance TXTP to start of next line
  LDA WinRem     ; [3] to get to right side of window (may be 0, up to 32)
  CLC            ; [2]
  ADC WinAdv     ; [3] to get to left side of next line (up to 32 for both)
  ADC TXTP       ; [3] add TXTP low (may set CF=1)
  STA TXTP       ; [3] set TXTP low
  ; XXX adding zero since `INC TXTP` already happened in `wrchr`,
  ; so no CF=1 triggered here; only fails if WinW=32 (if WinW=31 here,
  ; we would be at 255, and adding 1 would produce carry.)
  BCC @skiphi    ; [2] -> no carry [+1]
  INC TXTPH      ; [5] TXTPH += 1
@skiphi:           ; 
  LDA WinW       ; [3] reset remaining window width
  STA WinRem     ; [3] must be ready to write in steady-state
  RTS            ; [6]
; scroll the text window up one line
@scroll:
  TYA             ; save Y for caller
  PHA
  LDX WinH
  DEX
  BEQ @noscr       ; -> height is one line, no scroll
; set up Src
  LDX WinL
  LDY WinT
  INY              ; source starts down one line
  JSR txt_addr_xy  ; uses A,X,Y sets TXTP
  LDA TXTP
  STA Src
  LDA TXTPH
  STA SrcH
; set up Dst
  LDX WinL
  LDY WinT
  JSR txt_addr_xy  ; uses A,X,Y sets TXTP
  LDA TXTP
  STA Dst
  LDA TXTPH
  STA DstH
; scroll up one line
  LDX WinW         ; cols = WinW
  LDY WinH
  DEY              ; rows = WinH - 1
  JSR txt_copy_td  ; copy top-down from Src to Dst; uses (A,X,Y,Src,Dst,F)
@noscr:
; clear the bottom line
  LDX WinL         ; left of window
  LDA WinT
  CLC
  ADC WinH         ; bottom of window (too far)
  TAY
  DEY              ; minus 1 row (inside window)
  JSR txt_addr_xy  ; uses A,X,Y sets TXTP
  LDA #32          ; fill with spaces
  LDY WinW         ; window width
  STY WinRem       ; reset WinRem
  DEY              ; minus 1
@clear:
  STA (TXTP),Y     ; write a space
  DEY              ; decrement column
  BPL @clear       ; -> until Y=-1
; return
  PLA              ; restore Y for caller
  TAY               
  RTS              ; [6]

; @@ wrctl
; write a single control code
; assumes we're in text mode with TXTP set up
wrctl:           ; (uses A,X,Src,Dst,F) preserves Y
  CMP #13        ; [2] is it RETURN?
  BEQ newline    ; [2] -> do newline [+1]
  CMP #8         ; [2] is it BACKSPACE?
  BEQ @backsp    ; [2] -> do backspace [+1]
  CMP #1         ; [2] is it LEFT ARROW?
  BEQ @left      ; [2] -> do move left [+1]
  RTS            ; [6]
@backsp:         ; go back one cell and clear it
  JSR @left      ; [12+] move cursor left one place
  BCC @ret       ; [2] -> bail out
  LDA #32        ; [3] space character
  LDX #0         ; [2] const for (TXTP,X) ie (TXTP)
  STA (TXTP,X)   ; [6] clear the character under the cursor
  SEC            ; [2] success
@ret:
  RTS            ; [6]
@left:           ; move back one cell
  LDA WinRem     ; [3] remaining space on this line
  CMP WinW       ; [3] window width
  BEQ @left_sol  ; [2] equal -> at start of this line [+1]
  INC WinRem     ; [5] give back one character
  DEC TXTP       ; [5] we're at >0 inside the line (won't wrap)
  SEC            ; [2] success
  RTS            ; [6]
@left_sol:       ; start of buffer, or some line within a buffer?
  DEC CurY       ; go up one line
  BMI @up_bad
  LDA TXTP
  SEC
  SBC WinAdv     ; to end of prior line (CC if wrapped)
  BCS @left_noh  ; -> no TXTPH decrement
  DEC TXTPH      ; TXTPH -= 1  (no effect on CF)
@left_noh:
  SEC            ; success
  RTS
@up_bad:
  INC CurY       ; undo decrement
  CLC            ; failed
  RTS

; WinRem puts the zero-point at the right margin for quick right-edge detect.
; CurX puts the zero-point at the left margin for quick left-edge detect.


; @@ printmsgln
; println a string in the messages page
printmsgln:
  LDX #>messages  ; high byte (uses A,B,X,Y,Term,Src,Dst)
  ; +++ fall through to @@ println +++

; @@ println
; print a string, then a carriage return
; assumes we're in "text mode" with DMA DST set up
println:           ; X=high Y=low (uses A,B,X,Y,Term,Src,Dst)
  JSR print
  JMP newline

; @@ printmsg
; print a string in the messages page
printmsg:         ; Y=msg (uses A,B,X,Y,Term,Src,Dst)
  LDX #>messages  ; high byte
  ; +++ fall through to @@ print +++

; @@ print, in text mode
; write a length-prefix string to the screen
; assumes we're in text mode with TXTP set up
print:           ; X=high Y=low (uses A,B,X,Y,Term,Src,Dst)
  STX PrintH     ; src high
  STY PrintL     ; src low
  LDY #0         ; string offset, counts up
  LDA (PrintL),Y ; load string length
  BEQ @ret       ; -> nothing to print
  STA B          ; length to print
  LDX #0         ; const for (TXTP,X) ie (TXTP)
@loop:
  INY            ; [2] advance to next char              2
  LDA (PrintL),Y ; [5] load char from string             7
  ; begin wrchr inline
  CMP #32        ; [2] is it a control character?        9
  BCC @ctrl      ; [2] if <32 -> @ctrl [+1]              11
  STA (TXTP,X)   ; [6] write character to video memory   17
  INC TXTP       ; [5] advance text position             22
  DEC WinRem     ; [5] at right edge of window?          27
  BEQ @nl        ; [2] if so -> @nl [+1]                 29
  ; end wrchr inline
@incr:
  CPY B          ; [5] equals length?                    32
  BNE @loop      ; [2] not at end -> @loop [+1]          35 per char!
@ret
  RTS            ; [6] done
@nl:             ; wrap onto the next line and keep printing
  LDA #13        ; [2] newline control code
@ctrl:
  JSR wrctl      ; [6] execute control code (uses A,X,Src,Dst) preserves Y
  LDX #0         ; [2] restore constant X=0
  JMP @incr


; ------------------------------------------------------------------------------
; READLINE, LINE EDITOR

; Arrows move within the line; insert or delete text within the line
; Up/Down goes to Start/End. TAB to complete a line.

; BUG: by happenstace, BASIC starts on an 8th line which ends at TXTP=255,
; had a bug at WinW=32 where TXTPH didn't get incremented (fixed!)

; BUG: can bypass the readline buffer-full check while wrapping onto
; a new line and scrolling down at the same time. can type forever.


; @@ readline
; read a single line of input into the line buffer (zero-terminated)
readline:        ; uses A,X,Y,B,C returns Y=length (Z=1 if zero)
  LDA #0
  STA B          ; init line length
  STA C          ; init line cursor (linear)
@idle:
  JSR show_cursor
@wait:
  BIT ModKeys    ; check for Escape
  BMI @esc
  JSR readchar   ; read char from keyboard (uses A,X,Y -> A,ZF)
  BEQ @wait      ; if zero -> @wait
  TAX
  JSR hide_cursor ; uses A,Y
  TXA
@cont:
  CMP #32        ; is it a control code?
  BCC @ctrl      ; -> char < 32, control code
  LDY B          ; current line length
  CPY #$7F       ; at end of buffer?
  BEQ @beep      ; buffer full -> beep
  LDY C          ; load line cursor
  STA LineBuf,Y  ; write at cursor
  INC C          ; advance line cursor
  INC B          ; increase line length
  JSR wrchr      ; print char to screen (A=char, uses A,X, preserves Y)
@more:           ; keep reading chars
  JSR readchar   ; read char from keyboard (uses A,X,Y -> A,ZF)
  BNE @cont      ; -> continue typing
  BEQ @idle      ; -> return to idle
@ctrl:
  CMP #13        ; is it RETURN?       works
  BEQ @return    ; -> return
  CMP #8         ; is it BACKSPACE?    works up to sol
  BEQ @backsp    ; -> backspace
  CMP #$03       ; Left Arrow
  BEQ @left      ; -> move cursor left
  CMP #$04       ; Right Arrow
  BEQ @right     ; -> move cursor right
@beep:
  JSR beep
  LDA KeyTl      ; clear keyboard buffer (only beep once)
  STA KeyHd
  JMP @more
@esc:
  JMP repl_esc
@left:
  LDY C          ; load line cursor
  BEQ @beep      ; -> at start of buffer, beep
  JSR wrctl      ; move left on the display (A=1) (uses A,X, preserves Y -> CC=fail)
  BCC @beep      ; -> could not move left (e.g. scrolled off the top)
  DEC C          ; move line cursor back
  JMP @more
@right:
  LDY C          ; load line cursor
  CPY B          ; compare length of buffer
  BEQ @beep      ; -> at end of buffer, beep
  JSR wrctl      ; move right on the display (A=2) (uses A,X, preserves Y -> CC=fail)
  BCC @beep      ; -> could not move right (e.g. no idea why?)
  INC C          ; move line cursor forwards
  JMP @more
@return:
  LDA #0         ; terminator
  LDY B          ; get line length
  STA LineBuf,Y  ; write to line buffer
  RTS            ; returns Y=length (ZF=1 if zero)
@backsp:
  LDY C          ; load line cursor
  BEQ @beep      ; -> at start of buffer, beep
  JSR wrctl      ; backspace the display (A=8) (uses A,X, preserves Y -> CC=fail)
  BCC @beep      ; -> could not move right (e.g. scrolled off the top)
  DEC C          ; move line cursor back
  DEC B          ; subtract 1 from line length
  JMP @more

; @@ beep
; play an error beep over the speaker
beep:            ; XXX start beep playing
mode_ret:
  RTS


; ------------------------------------------------------------------------------
; MODE, CLS, TAB, text_addr_xy

; @@ vid_mode
; mode 0 is text mode 32 x 24
; mode 1 is APA mode 128 x 96
vid_mode:        ; set screen mode, A=mode (uses A,X,Y,B)
  AND #1         ; modes 0-1
  STA IO_VCTL    ; set video mode; reset border color
  LDA #$0F       ; BG=black FG=white (for APA mode)
  STA IO_VPAL    ; set palette
  LDA #0
  STA WinL       ; reset text window left                                  (window)
  STA WinT       ; reset text window top
  STA WinAdv     ; advance to reach next line (32 - WinW)
  LDA #32        ;                                                         (window)
  STA WinW       ; reset text window width                                 (window)
  LDA #24        ;
  STA WinH       ; reset text window height
  ; +++ fall through to @@ vid_cls +++

; @@ vid_cls
; clear the screen or text window
vid_cls:                 ; (uses A,X,Y) [~6680]
  LDX WinL               ; [3] text window left                            (window: #0)
  LDY WinT               ; [3] text window top
  JSR txt_addr_xy        ; [6] calculate TXTP at X,Y (uses A,X,Y) [40]
  LDX WinH               ; [3] number of rows
@row:
  LDA #32                ; [2] space character
  LDY WinW               ; [3] reload column count                         (window: #32)
  DEY                    ; [2] assumes WinW > 0
@col:
  STA (TXTP),Y           ; [3] write character
  DEY                    ; [2] decrement column count
  BPL @col               ; [3] -> until Y=-1 [8*32=(256+20)*24=6624]
; advance DST to next line
  LDA #32                ; [3] advance to the next line
  CLC                    ; [2]
  ADC TXTP               ; [3] TXTP += 32
  STA TXTP               ; [3]
  BCC @noc               ; [2] -> no carry [+1]
  INC TXTPH              ; [5] TXTPH += 1
@noc:
  DEX                    ; [2] decrement row count
  BNE @row               ; [3] until row=0
  ; +++ fall through to @@ txt_home +++

; @@ home
; move the cursor to the top-left of the window
; update DMA address (DSTL,DSTH) for "text mode"
txt_home:        ; (uses A,X,Y)
  LDX #0         ; top-left corner of text window
  LDY #0         ; 
  BEQ tab_e2     ; skip range checks
  ; +++ fall through to @@ txt_tab +++

; @@ tab
; move the cursor to X,Y in index registers (unsigned)
; relative to the top-left corner of the text window, zero-based.
; update DMA address (DSTL,DSTH) for "text mode"
txt_tab:         ; (uses A,X,Y)
  CPX WinW       ; clamp X if out of range (WinW)                       (window: would be AND #31)
  BCC @x_ok      ; -> X < WinW (OK)                                     (window)
  LDX WinW       ; (CS)                                                 (window)
  DEX            ; (CS) clamp to last column (XXX reduce WinW by -1?)   (window)
@x_ok:
  CPY WinH       ; clamp Y if out of range (WinH)                       (window: #23)
  BCC @y_ok      ; -> Y < WinH (OK)
  LDY WinH       ;                                                      (window: #23)
  DEY            ; clamp to last row  (XXX reduce WinH by -1?)          (window)
@y_ok:
tab_e2:
  STX F          ; save CurX to Scratch
  LDA WinW       ; WinRem = WinW - CurX                                 (window)
  SEC            ;                                                      (window)
  SBC F          ;                                                      (window)
  STA WinRem     ; set WinRem (accelerates PRINT)
  STY CurY       ; set cursor Y
; Map from text window X,Y to screen X,Y
; the text plane is 32x24 in text mode
  TXA            ; X column in text window                              (window: add WinL)
  CLC            ;                                                      (window: add WinL)
  ADC WinL       ; X column in screen space (add window left)           (window: add WinL)
  TAX            ; back to X                                            (window: add WinL)
  TYA            ; Y row in text window                                 (window: add WinT)
  CLC            ;                                                      (window: add WinT)
  ADC WinT       ; Y row in screen space (add window top)               (window: add WinT)
  TAY            ; back to Y                                            (window: add WinT)
  ; +++ fall through to @@ txt_addr_xy +++

; @@ txt_addr_xy
; calculate VRAM address for an X,Y coordinate in text mode; set TXTP
; [000000YY][YYYXXXXX]  32x24 text matrix
txt_addr_xy:     ; (uses A,X,Y, does not use F for @scroll) [40]
  STX TXTP       ; [3] save X [000XXXXX]
  TYA            ; [2] get Y [000YYYYY]
  ROR            ; [2] [0000YYYY][C=Y0]      (only ROR in the ROM.. could do ASL/LSR)
  ROR            ; [2] [Y0000YYY][C=Y1]
  ROR            ; [2] [YY0000YY][C=Y2]
  TAY            ; [2] save [YY0000YY]       (+2s/+1b)
  ROR            ; [2] [YYY0000Y][C=Y3]
  AND #$E0       ; [2] [YYY00000]            (10s/6b)
  ORA TXTP       ; [3] [YYYXXXXX]
  STA TXTP       ; [3] set TXTP
  TYA            ; [2] get [YY0000YY]
  AND #3         ; [2] [000000YY] low [Y43]  (8s/6b)  // (18s/12b) vs ASL/LSR ver
  CLC            ; [2] must clear (C=Y3)
  ADC #$2        ; [2] add $200 base address to TXTPH
  STA TXTPH      ; [3] set TXTPH
  RTS            ; [6]

; @@ txt_copy_td
; copy a text rect top-down, left-to-right (move the rect up/left)
; from (Src) to (Dest) both at top-left; Y=height, WinW=width (both non-zero)
txt_copy_td:             ; uses (A,X,Y,Src,Dest)
  STY F                  ; [3] set row counter
@td_row:
  LDX WinW               ; [3] number of columns
  LDY #0                 ; [2] left-to-right column index
@td_col:
  LDA (Src),Y            ; [3] read character
  STA (Dst),Y            ; [3] write character
  INY                    ; [2] increment column index
  DEX                    ; [2] decrement column count
  BNE @td_col            ; [3] -> until X=0
; advance to next line
  CLC                    ; [2]
  LDA #32                ; [2] advance to the next line
  ADC Src                ; [3] Src += 32 (one line)
  STA Src                ; [3]
  BCC @td_no_sh          ; [2] -> no carry [+1]
  INC SrcH               ; [5] SrcH += 1
@td_no_sh:
  CLC                    ; [2]
  LDA #32                ; [2] advance to the next line
  ADC Dst                ; [3] Dest += 32 (one line)
  STA Dst                ; [3]
  BCC @td_no_dh          ; [2] -> no carry [+1]
  INC DstH               ; [5] SrcH += 1
@td_no_dh:
  DEC F                  ; [2] decrement row counter
  BNE @td_row            ; [3] until rows=0
  RTS

; @@ txt_copy
; copy text rect from (X0,Y0) to (X1,Y1) size (W,H) on stack
txt_copy:
  RTS

; @@ txt_copy_bu
; copy a text rect bottom-up, right-to-left (move the rect down/right)
; from (Src) to (Dest) both at BOTTOM-left; width=WinW height=WinH (both non-zero)
txt_copy_bu:             ; uses (A,X,Y,B,C,Src,Dest)
  LDA WinH               ; [3] number of rows
  STA B                  ; [3] row count
@bu_row:
  LDY WinW               ; [3] number of columns
  DEY                    ; [2] pre-decrement right-to-left column index
@bu_col:
  LDA (Src),Y            ; [3] read character
  STA (Dst),Y            ; [3] write character
  DEY                    ; [2] decrement column index
  BPL @bu_col            ; [3] -> until Y=-1
; advance to next line
  SEC                    ; [2]
  LDA Src                ; [3]
  SBC #32                ; [2] Src -= 32 (go up one line)
  STA Src                ; [3]
  BCS @bu_no_sh          ; [2] -> no borrow [+1]
  DEC SrcH               ; [5] SrcH -= 1
@bu_no_sh:
  SEC                    ; [2]
  LDA Dst                ; [3]
  SBC #32                ; [2] Dst -= 32 (go up one line)
  STA Dst                ; [3]
  BCC @bu_no_dh          ; [2] -> no carry [+1]
  DEC DstH               ; [5] SrcH -= 1
@bu_no_dh:
  DEC B                  ; [2] decrement row count
  BNE @bu_row            ; [3] until rows=0
  RTS



; ------------------------------------------------------------------------------
; PAGE

show_cursor:     ; uses A,Y
  SEI            ; disable IRQ
  LDY #0
  LDA (TXTP),Y   ; get char under cursor
  CMP #$EF       ; is the cursor shown?   (XX conflict with $EF char)
  BEQ @done      ; -> already shown
  STA CurChar    ; save char under cursor
  LDA #$EF       ; cursor block
  STA (TXTP),Y   ; write cursor block
  LDA #30
  STA CurTime    ; reset cursor timer
@done:
  CLI            ; enable IRQ
  RTS

hide_cursor:     ; uses A,Y
  SEI            ; disable IRQ
  LDY #0
  LDA (TXTP),Y   ; get char under cursor
  CMP #$EF       ; is the cursor shown?   (XX conflict with $EF char)
  BNE @done      ; -> not shown
; restore char
  LDA CurChar    ; saved character
  STA (TXTP),Y   ; restore the saved character
@done:
  CLI            ; enable IRQ
  RTS


; @@ irq_init
; set up IRQ vector in zero page, init keyboard, enable interrupts
irq_init:
  SEI            ; disable IRQ
  LDA #0         ; reset keyboard buffer (with interrupts disabled)
  STA KeyHd
  STA KeyTl
  STA ModKeys    ; ensure Escape is not pressed!
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
  PHA            ; save A
  TXA
  PHA            ; save X
  TYA
  PHA            ; save Y
  STA IO_VLIN    ; acknowledge interrupt
  JSR keyscan
; cursor blink
  DEC CurTime
  BNE @done      ; -> no blink
  LDA #30
  STA CurTime    ; reset cursor timer
  LDY #0
  LDA (TXTP),Y   ; get char under cursor
  CMP #$EF       ; is the cursor shown?   (XX conflict with $EF char)
  BEQ @restore
  STA CurChar    ; save char under cursor
  LDA #$EF
  STA (TXTP),Y   ; write cursor block
  JMP @done
@restore:
  LDA CurChar    ; saved character
  STA (TXTP),Y   ; restore the saved character
@done:
  PLA            ; restore Y
  TAY
  PLA            ; restore X
  TAX
  PLA            ; restore A
nmi_vec:
  RTI

; @@ Vector Table
ORG VEC
DW nmi_vec       ; $FFFA, $FFFB ... NMI vector
DW reset         ; $FFFC, $FFFD ... Reset vector
DW IrqVec        ; $FFFE, $FFFF ... BRK/IRQ vector
