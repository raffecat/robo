; Robo 4K BASIC 1.0
; Use `asm6` to compile: https://github.com/parasyte/asm6

; BASIC runtime   1.5K ($600)
; Floating point  0.5K ($200)
; BASIC parser    1K
; Editor          1K

; 3 pages left:
; • floating point
; • square root
; • string heap
; • string functions
; • line drawing
; • APA graphics
; • Casette code
; • Sound interrupt

ROM      = $F000  ; 4K = $1000 from F000-FFFF
VEC      = $FFFA  ; vector table, 6 bytes

ZeroPg   = $0000  ; zero page
StackPg  = $0100  ; stack page
ScreenPg = $0200  ; start of screen memory
Base4K   = $0500  ; start of free memory
End4K    = $1000  ; end of memory

; ------------------------------------------------------------------------------
; Zero Page $00-7F - BASIC WORKSPACE

; -- $00-1F BASIC Operator Stack (32 operators)

OperStk  = $00    ; BASIC operator stack

; -- $20-3F Scratch Space (32)

Scratch  = $20

; -- $40-73 BASIC Variables (52; 26 pointers)

VarPtrs  = $40    ; 26 x BASIC variable pointers (A-Z)

; -- $74-7F BASIC Pointers (12; 6 pointers)

OpTop    = $74    ; top of OperStk (stack pointer)
BasePage = $75    ; BASIC base address ($3500/$2500/$0500 text; $3800/$2800/$0800 APA)
TopPtr   = $76    ; TOP of the BASIC program (variables start)
TopPtrH  = $77
FreePtr  = $78    ; BASIC end of variables (free space)            [LineNo]
FreePtrH = $79
HeapPtr  = $7A    ; BASIC start of string heap (at top of memory)  [AutoLn]
HeapPtrH = $7B
CODE     = $7C    ; BASIC code pointer (next instruction)          [Emit]
CODEH    = $7D
Data     = $7E    ; BASIC data pointer (next DATA statement)       [AutoInc]
DataH    = $7F

AutoInc  = $74    ; ALIAS OpTop - AUTO line increment [Tokenize]
LineNo   = $78    ; ALIAS FreePtr - parsed line number [Tokenize]
LineNoH  = $79    ; ALIAS FreePtrH - parsed line number [Tokenize]
AutoLn   = $7A    ; ALIAS HeapPtr - AUTO line number low [Tokenize]
AutoLnH  = $7B    ; ALIAS HeapPtrH - AUTO line number high [Tokenize]
Emit     = $7C    ; ALIAS CODE - emit tokenized code [Tokenize]
EmitH    = $7D    ; ALIAS CODEH - emit tokenized code [Tokenize]
;        = $7E    ; ALIAS Data - 
;        = $7F    ; ALIAS DataH - 

; ------------------------------------------------------------------------------
; Zero Page $80-FF - OS WORKSPACE

; -- $80-9F IO Buffers (32)

KeyBuf   = $80    ; Keyboard Buffer (16 bytes)
IOBuf    = $90    ; IO Buffer (16 bytes)

; -- $A0-BF File Control Blocks (32)

FCB_0    = $A0    ; File Control Block 0 (8 bytes)
FCB_1    = $A8    ; File Control Block 1 (8 bytes)
FCB_2    = $B0    ; File Control Block 2 (8 bytes)
FCB_3    = $B8    ; File Control Block 3 (8 bytes)

; -- $C0-CF Temporaries

Src      = $C0    ; source pointer \ Scroll (PRINT/WRCHR/WRCTL), CLS
SrcH     = $C1    ; source pointer | Tokenize (scan_kw/num_val)
Dst      = $C2    ; second pointer | Scroll (PRINT/WRCHR/WRCTL), CLS
DstH     = $C3    ; second pointer | 
Ptr      = $C4    ; third pointer  \ INPUT ptr; PRINT src (can cause Scroll)
PtrH     = $C5    ; third pointer  /
B        = $C6    ; extra register | Subroutines are annotated with usage;
C        = $C7    ; extra register | held across calls only when unused
D        = $C8    ; extra register | by callees (manually tracked)
E        = $C9    ; extra register | 
F        = $CA    ; extra register | Scratch (always transient; cannot hold)

;        = $CB    ;

AccE     = $CC    ; accumulator exponent (0 for integer)
Acc2     = $CD    ; accumulator byte 2
Acc1     = $CE    ; accumulator byte 1
Acc0     = $CF    ; accumulator byte 0

TermE    = $C0    ; ALIAS Src:  term exponent (0 for integer)
Term2    = $C1    ; ALIAS SrcH: term byte 2
Term1    = $C2    ; ALIAS Dst:  term byte 1
Term0    = $C3    ; ALIAS DstH: term byte 0

; -- $D0-DF OS Vars

KeyHd    = $D0    ; keyboard buffer head (owned by User)
KeyTl    = $D1    ; keyboard buffer tail (owned by IRQ)
ModKeys  = $D2    ; modifier keys [7:Esc 6:Shf 5:Ctl 4:Fn] (owned by IRQ)
LastKey  = $D3    ; keyboard last key pressed, for auto-repeat (owned by IRQ)
KeyRep   = $D4    ; keyboard auto-repeat timer

WinT     = $D5    ; text window top
WinH     = $D7    ; text window height

;WinRem   = $D9    ; remaining space on this line
TXTP     = $DB    ; text write address
TXTPH    = $DC    ; text write address high
CurTime  = $DD    ; cursor flash timer
CurChar  = $DE    ; character under cursor

EndPage  = $DF    ; end of memory (page)

; -- $E0-EF OS Vectors

; Vectors (E4-EF)
IRQTmp2  = $E4    ; Temp for IRQ handler #2
SysCmds  = $E5    ; REPL command-list pointer {Low,High} (for ROM override)
SysStmt  = $E7    ; BASIC statement extension cmd-list {Low,High} (for ROM override)
IRQTmp   = $E9    ; Temp for IRQ handler #1
NmiVec   = $EA    ; NMI vector in RAM {JMP,Low,High} (for ROM override)
IrqVec   = $ED    ; IRQ vector in RAM {JMP,Low,High} (for ROM override)

; -- $F0-FF  IO Registers

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

ModEsc   = $80    ; Escape is down
ModShift = $40    ; Shift is down
ModCtrl  = $20    ; Ctrl is down
ModGr    = $10    ; GR key is down
ModCol   = $08    ; COL key is down

; ------------------------------------------------------------------------------
; PAGE 0

ORG ROM

; ROM entry table     ; public entry points (might be too expensive)
JMP reset             ; $E000  reset the computer                           (JMP)
; JMP basic           ; $E003  enter BASIC                                  (JMP)
; JMP print           ; $E006  print string, len-prefix, X=page Y=offset    (JSR uses A,B,X,Y)
; JMP wrchr           ; $E009  print char or control code in A              (JSR preserves Y)
; JMP newline         ; $E00C  print a newline, scroll if necessary         (JSR preserves Y)
; JMP readline        ; $E00F  read a line into LineBuf (zero-terminated)   (JSR uses A,X,Y) -> Y=length
; JMP readchar        ; $E00C  read a character from the keyboard           (JSR uses A,X,Y) -> A=char/zero ZF
; JMP vid_mode        ; $E012  set screen mode, clear the screen            (JSR uses A,X,Y)
; JMP vid_cls         ; $E015  clear the screen                             (JSR uses A,X,Y)
; JMP txt_tab         ; $E018  move text cursor to X,Y within text window   (JSR uses A,X,Y)

messages:    ; must be within one page for Y indexing
msg_boot:    ; blue red orange yellow green cyan purple
  DB 27
  DB $91,$92,$93,$94,$95,$90,13,13
  DB "Frontier BASIC 1.0",13
msg_freemem:
  DB 12, " bytes free",13
ready:
  DB 5,"READY"
msg_searching:
  DB 9,"Searching"
msg_loading:
  DB 7,"Loading"

; ~64 bytes error messages
msg_exp:  DB 7,"Expect "
msg_syn:  DB 6,"Syntax" ; Error
msg_div:  DB 3,"DIV"    ; Error
msg_ovf:  DB 3,"OVF"    ; Error
msg_err:  DB 6," Error"
msg_bad:  DB 4,"Bad "
msg_rng:  DB 5,"Range"  ; Bad
msg_blk:  DB 5,"Block"  ; Bad
msg_var:  DB 3,"VAR"    ; Bad
msg_typ:  DB 4,"Type"   ; Bad
msg_esc:  DB 6,"Escape"

; ------------------------------------------------------------------------------
; Startup

reset:
  SEI            ; disable interrupts
  CLD            ; disable BCD mode
  LDX #$FF       ; reset stack [to align it?]
  TXS            ; stack init
  LDX #1         ; #1 for cursor reset
  STX CurTime    ; show on the next frame
  DEX            ; screen mode 0 (32x24 text, 16 color)
  JSR vid_mode   ; set mode, clear screen
  LDY #<msg_boot
  JSR printmsgln  ; (uses A,B,C,D,X,Y,Src,Dst)
  ; detect memory installed
  ; XX scan memmap
  LDA #>End4K      ; page
  STA EndPage      ; set end of memory (will be dynamic)
  LDA #>Base4K     ; page
  STA BasePage     ; set BASIC start address (will be dynamic)
  STA TopPtrH      ; also reset TOP
  LDX #0           ; low
  STX TopPtr       ; page-aligned
  ; display free memory
  STX AccE         ; AccE=0 to display free memory
  STX Acc2         ; Acc2=0 to display free memory
  SEC
  LDA EndPage
  SBC BasePage
  STA Acc1         ; Acc1=(number of pages)
  STX Acc0         ; Acc0=0
  JSR num_print    ; (uses A,X)
  LDY #<msg_freemem
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)
  LDY #<ready
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)
  ; +++ fall through to @@ basic +++

; ------------------------------------------------------------------------------
; BASIC repl

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
  STX Data       ; no data yet
  STX DataH      ; no data yet
  JSR readline   ; -> Y=length
  STY E          ; input line length, for tokenizer
  JSR newline    ; uses A,X

  ; parse the command
  LDY #0           ; [2]
  JSR skip_spc     ; [24+] Y=ofs -> Y, A=next-char (uses A,X)
  BEQ repl         ; [2] -> empty line, go back to repl [+1]
  JSR num_u16      ; [6] parse number at Y -> Y,Acc,NE=found (uses A,B,X,Y)
  BNE @haveline    ; [2] -> found line number [+1]

  ; try matching a repl command
  LDX #>repl_tab   ; [2] repl commands high byte
  LDA #<repl_tab   ; [2] repl commands low byte
  JSR match_kws    ; [6] Y=ofs AX=table -> CF=found, Y=ofs, A=high-byte (uses A,X,Y,B,C,D,Src)
  BCC @direct      ; [3] -> no match, parse direct
  AND #$7F         ; [2] clear top bit of hi-byte
  CMP #repl_len    ; [2] ASSERT
  BCS err_bounds   ; [2] ASSERT A < repl_len
  JSR @docmd       ; [6] run the command
  JMP repl         ; [3] -> back to repl
  ; jump to the REPL command (slow, but saves space)
@docmd:
  ASL              ; [2] times 2 (word index)   (XXX use two tables to remove this)
  TAY              ; [2] as index
  LDA repl_fn+1,Y  ; [4] repl function, high byte   (XXX use single page, LDA #n)
  PHA              ; [3] push high
  LDA repl_fn,Y    ; [4] repl function, low byte
  PHA              ; [3] push low
  RTS              ; [6] "return" to the REPL command

  ; tokenize and evaluate direct BASIC statements
@direct:
  LDX #0           ; [2]
  JSR tokenize     ; [6] tokenize BASIC statements (X=ln-ofs)
                   ;     XXX execute the line immediately
  JMP repl         ; [6] return to repl

  ; tokenize and append/edit the BASIC program
@haveline:         ; X = after line number
  ; save line number for bas_ins_line
  LDA Acc0         ; [3]
  STA LineNo       ; [3] tokenized line number
  LDA Acc1         ; [3]
  STA LineNoH      ; [3] tokenized line number high
  BMI err_bounds   ; [2]
  JSR tokenize     ; [6] tokenize BASIC statements (X=ln-ofs)
                   ;     XXX insert the tokenized line into the BASIC program
  JMP repl         ; [6] return to repl


; ------------------------------------------------------------------------------
; Error Reporting

; Current: 54 code + 63 data = 117 (vs 82)  no syn_expect_y

err_bounds:
  LDA #<msg_rng
  ; +++ fall through to @@ report_err +++

; @@ report_err
; Report an error and return to BASIC repl.
report_err:       ; A = msg address low
  JSR printmsg    ; Y=ptr -> 
  LDY #<msg_err
  JSR printmsgln  ; Y=ptr -> 
  JMP repl

; @@ report_bad
; Report an error and return to BASIC repl.
report_bad:       ; A = msg address low
  STY E
  LDY #<msg_bad
  JSR printmsgln  ; Y=ptr -> 
  LDY E
  JSR printmsg    ; Y=ptr -> 
  JMP repl

; @@ err_expect
; Report "Expect [char]"
err_expect:       ; A = expected character
  PHA             ; save char
  LDY #<msg_exp
  JSR printmsg
  PLA             ; restore char
  JSR wrchr       ; uses A,X
  JSR newline     ; uses A,X
  JMP repl

escape:       ; A = msg address low
  LDY #<msg_esc
  JSR printmsgln  ; Y=ptr -> 
@wait:            ; wait for Escape to be released
  LDA ModKeys     ; check key state
  BMI @wait       ; -> Escape still down
  JMP repl



; ------------------------------------------------------------------------------
; BASIC Tokenizer
;
; Y = current source offset at (Ptr)
; A,X = temporaries

; report syntax error
tok_syn:
  LDA #<msg_syn
  JMP report_err

; recognise and emit a varaible name (Y at 1st letter)
tok_var:
  JMP syn_let        ; -> use LET handler

; @@ tokenize
; tokenize BASIC statements (in-place in LineBuf)
tokenize:            ; Y=ofs
  DEY                ; set up for pre-increment
tok_stmts:
  INY                ; pre-increment (for ':' BEQ)
  JSR skip_spc       ; Y=ofs -> Y, A=next-char (uses X)
  JSR is_alpha       ; Y=ofs -> Y, A=az-index, CC=alpha
  BCS tok_syn        ; -> no STMT or VAR
  TAX                ; A-Z as index (0-25)
  LDA stmt_idx,X     ; offset in stmt_page (A-Z)
  LDX #>stmt_page    ; stmt table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,Y,B,C,D,Src)
  BCC tok_var        ; -> no match, must be VAR (use LET handler)
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y; sets NE)
  AND #$63           ; low 6 bits, statement index
  CMP #stmt_count    ; ASSERT: is it < stmt_count
  BCS tok_syn        ; ASSERT: -> out of bounds
  TAX                ; as statement index               (syn_jmp indirect)(+8b)
  LDA syn_tab,X      ; syn_tab byte for this statement  (syn_jmp indirect)
  STA D              ; save syn_tab byte (for handler)  (syn_jmp indirect)
  AND #15            ; handler index in low 4 bits      (syn_jmp indirect)
  TAX                ; as index
  LDA #>syn_page     ; syntax handler page
  PHA                ; push high
  LDA syn_jmp,X      ; handler address in syn_page
  PHA                ; push low
  RTS                ; "return" to the syntax handler

; @@ skip_spc
; skip spaces in the input buffer [NO TEXT-OUT]
skip_spc:        ; Y=ofs -> Y, A=next-char (uses A,X)
  LDA (Ptr),Y    ; [5] next input char
  INY            ; [2] advance (assume match)
  CMP #32        ; [2] was it space?
  BEQ skip_spc   ; [2] -> loop [+1]
  DEY            ; [2] undo advance (didn't match)
  RTS            ; [6] return Y=ofs, A=next-char [19]

; @@ is_alpha
is_alpha:        ; Y=ofs (uses A) -> Y, A=az-index, CC=alphabetic
  LDA (Ptr),Y    ; [5] next input char
  AND #$DF       ; [2] lower -> upper (clear bit 5) detect alpha char
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CS if >= 26)
tok_ret1:
  RTS            ; [6] -> A=az-index CC=alpha [19]

; @@ tok_emit_pl
; Emit a placeholder byte at (Emit) and advance (Emit).
tok_emit_pl:
  LDA Emit           ; save Emit for patching later
  STA Dst
  LDA EmitH
  STA DstH
  ; +++ fall through to @@ tok_emit +++

; @@ tok_emit
; Emit an opcode at (Emit) and advance (Emit).
tok_emit:            ; (uses X=0; preserves A,Y; sets NE)  [21]
  LDX #0             ; [2] const 0
  STA (Emit,X)       ; [6] emit token
  INC Emit           ; [5] advance emit offset
  BEQ err_overflow   ; [2] -> overflowed page
  RTS                ; [6]

err_overflow:
  LDA #<msg_ovf
  JMP report_err


; @@ match_kws
; find matching keyword, terminated by a byte with top-bit set (8x,9x,Ax,Bx)
; if no match, continue until bit 6 is set (Cx,Dx,Ex,Fx)
match_kws:       ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,Y,B,C,D,Src)
  STY B          ; [3] save start of input
  STA Src        ; [3] table-low
  STX SrcH       ; [3] table-high
  LDX #0         ; [2] const X=0
@next_kw:
  DEY            ; [2] set up for pre-increment
@match_lp:
  INY            ; [2] pre-increment input position
  INC Src        ; [5] pre-increment keyword position
  LDA (Src,X)    ; [6] next keyword char
  CMP (Ptr),Y    ; [4] does it match input?
  BEQ @match_lp  ; [2] -> yes, next char [+1]
  BPL @not_found ; [2] -> did not match keyword (top bit clear) [+1]
  SEC            ; [2] set carry: keyword was found
  RTS            ; [6] X = next-character A=hi-byte (top bit set)
; no match, skip rest of keyword (find top-bit)
@not_found:
  INC Src        ; [5] pre-increment keyword position
  LDA (Src,X)    ; [6] check keyword char
  BPL @not_found ; [2] -> top bit clear, keep going [+1]
  INC Src        ; [5] adance past top-bit byte
  LDY B          ; [3] restore Y = start of input
  ASL            ; [2] shift left top-bit byte
  BPL @next_kw   ; [2] -> bit 6 clear, try next keyword [+1]
  CLC            ; [2] no match found
  RTS            ; [6] Y = start of input


; LET <var> '=' <expr>                                   -> {LETn|LETs|LETa}<var><expr> (x2?)
; DIM <var> '(' <expr> ')'                               -> {DIM}<var><expr_n>
; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>] -> {FOR}<var><expr_n><expr_n><expr_n|$00>
; NEXT [<var>|$00]                                       -> {NEXT}<var|$00>
; IF <expr_n> THEN <line>/<stmts> [ELSE <line>/<stmts>]  -> {IF}<expr_n><len> | {IFLN}<expr_n><n16>
; ELSE <line>/<stmts>                                    -> {ELSE}<len>       | {ELLN}<n16>
; READ {<var> ','}                                       -> {READ}<len>{<var>}
; INPUT { [,;'] "str" | <var> }                          -> {INPUT}<len>{<op|lit|var>}
; PRINT { [,;'] "str" | <expr_n> | <expr_s> } [;]        -> {PRINT|PRINT;}<len>{<op|lit|expr>}
; DEF FN <name> '(' {<var>} ')'                          -> {DEFFN}<name><len>{<var>}
; OPEN #<n> ',' <expr_s>                                 -> {OPEN}<n><expr_s>
; CLOSE #<n>                                             -> {CLOSE}<n>
; REM <text>                                             -> {REM}<len><data>
; DATA <text>                                            -> {DATA}<len><data>    (XXX "DATA 1.02e1" -> A$)
; RETURN                                                 -> {RETURN}
; REPEAT                                                 -> {REPEAT}
; CLS                                                    -> {CLS}
; GOTO <expr>                                            -> {GOTO}<expr_n>
; GOSBU <expr>                                           -> {GOSUB}<expr_n>
; RESTORE <expr_n>                                       -> {RESTORE}<n16>
; UNTIL <expr_n>                                         -> {UNTIL}<expr_n>
; MODE <expr_n>                                          -> {MODE}<expr_n>
; WAIT <expr_n>                                          -> {WAIT}<expr_n>
; POKE <expr_n> ',' <expr_n>                             -> {POKE}<expr_n><expr_n>
; OPT <expr_n> ',' <expr_n>                              -> {OPT}<expr_n><expr_n>
; SOUND <pitch><vol><len>[<dp>[<dv>]]                    -> {SOUND}<expr_n><expr_n><expr_n><expr_n|$00><expr_n|$00>
; PLOT <expr_n> ',' <expr_n>                             -> {PLOT}<expr_n><expr_n>
; LINE <expr_n> ',' <expr_n> ',' <expr_n> ',' <expr_n>   -> {PLOT}<expr_n><expr_n><expr_n><expr_n>
; '=' <expr>                                             -> {RETFN}<expr>   (not a keyword)

SYN_FLAG    = $80       ; bit 3 flag

SYN_0       = $00       ; no args
SYN_NN      = $01       ; N x <expr_n> *
SYN_DATA    = $02       ; <len><data>
SYN_CH      = $03       ; #<n> [ ',' <expr_s> ]:FLAG
SYN_LET     = $04       ; [LET] <var> = <expr>                      -> <var><expr_*>
SYN_DIM     = $05       ; DIM <var> '(' <expr> ')'                  -> <var><expr_n>
SYN_FOR     = $06       ; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>] -> <var><expr_n><expr_n><expr_n|$00>
SYN_NEXT    = $07       ; NEXT [<var>|$00]                          -> <var|$00>
SYN_IF      = $08       ; IF <expr_n> [THEN [<line>]]               -> <expr_n><len|n16>
SYN_ELSE    = $09       ; ELSE [<line>]                             -> <len>
SYN_READ    = $0A       ; READ {<var> ','}                          -> <len>{<var>}
SYN_INPUT   = $0B       ; { [,;'] "str" | <var> }                   -> <len>{<op|lit|var>}
SYN_PRINT   = $0C       ; { [,;'] "str" | <expr_n> | <expr_s> } [;] -> <len>{<op|lit|var>}
SYN_DEF     = $0D       ; 'FN' <name> '(' {<var>} ')'               -> <name><len>{<var>}


syn_tab:                         ; [30]
  DB 0                           ; OP_LN      $C0   (not used)
  DB SYN_0                       ; OP_CLS     $C1
  DB SYN_CH                      ; OP_CLOSE   $C2
  DB SYN_DATA                    ; OP_DATA    $C3
  DB SYN_DIM                     ; OP_DIM     $C4
  DB SYN_DEF                     ; OP_DEFFN   $C5
  DB SYN_ELSE                    ; OP_ELSE    $C6
  DB SYN_0                       ; OP_END     $C7
  DB SYN_FOR                     ; OP_FOR     $C8
  DB SYN_NN | (1<<4)             ; OP_GOTO    $C9
  DB SYN_NN | (1<<4)             ; OP_GOSUB   $CA
  DB SYN_IF                      ; OP_IF      $CB
  DB SYN_INPUT                   ; OP_INPUT   $CC
  DB SYN_LET                     ; OP_LET     $CD
  DB SYN_NN | (4<<4)             ; OP_LINE    $CE
  DB SYN_NN | (1<<4)             ; OP_MODE    $CF
  DB SYN_NEXT                    ; OP_NEXT    $D0
  DB SYN_NN | (2<<4)             ; OP_OPT     $D1
  DB SYN_CH | SYN_FLAG           ; OP_OPEN    $D2
  DB SYN_NN | (2<<4)             ; OP_PLOT    $D3
  DB SYN_NN | (2<<4)             ; OP_POKE    $D4
  DB SYN_PRINT                   ; OP_PRINT   $D5
  DB SYN_READ                    ; OP_READ    $D6
  DB SYN_0                       ; OP_REPEAT  $D7
  DB SYN_NN | (1<<4)             ; OP_RESTORE $D8
  DB SYN_0                       ; OP_RETURN  $D9
  DB SYN_DATA                    ; OP_REM     $DA
  DB SYN_NN | (4<<4) | SYN_FLAG  ; OP_SOUND   $DB
  DB SYN_NN | (1<<4)             ; OP_UNTIL   $DC
  DB SYN_NN | (1<<4)             ; OP_WAIT    $DD

syn_jmp:                ; [14] range-checked page offsets
  DB (syn_0 - syn_page)
  DB (syn_nn - syn_page)
  DB (syn_data - syn_page)
  DB (syn_ch - syn_page)
  DB (syn_let - syn_page)
  DB (syn_dim - syn_page)
  DB (syn_for - syn_page)
  DB (syn_next - syn_page)
  DB (syn_if - syn_page)
  DB (syn_else - syn_page)
  DB (syn_read - syn_page)
  DB (syn_input - syn_page)
  DB (syn_print - syn_page)
  DB (syn_def - syn_page)


; -------------------------------------------------------------
; $300 Syntax Recognisers
;
; Y = line-ofs
; D = syn_tab byte (syn:7-4, flag:3, count:2-0)
; E = line-len (from REPL)
; skip_spc already done

; var/expr types
TYPE_NUM   = 0
TYPE_STR   = 1
TYPE_ARR   = 2
TYPE_NUM_A = 2 ; TYPE_ARR|TYPE_NUM
TYPE_STR_A = 3 ; TYPE_ARR|TYPE_STR

ALIGN $100
syn_page:

syn_0:           ; no args
  RTS

syn_nn:          ; N x <expr_n>
  LDA D          ; FnnnSSSS
  ROR            ; xFnnnSSS
  ROR            ; xxFnnnSS
  ROR            ; xxxFnnnS
  ROR            ; xxxxFnnn
  AND #7         ; up to 7 arguments
  STA D          ; num exprs
  BNE @first     ; -> no first comma (assume D>0)
@loop:
  JSR syn_comma  ; expect ','
@first:
  JSR syn_exp_n  ; tokenize and emit numeric expression
  DEC D
  BNE @loop
@done:
  RTS

syn_sound:        ; N x <expr_n> +1 or +2
  JSR syn_nn      ; tokenize first four arguments
  JSR syn_exp_no  ; tokenize and emit numeric expression (optional) -> CS=found
  BCC syn_00      ; -> no 5th argument
  JSR syn_exp_no  ; tokenize and emit numeric expression (optional) -> CS=found
  BCC syn_00      ; -> no 6th argument
  RTS

syn_00:
  LDA #0
  JMP tok_emit    ; write $00 marker (uses X=0; preserves A,Y; sets NE)

syn_data:         ; <len><data>
  JSR syn_rem_len ; get remaining length of input (uses A,B) -> A
  JSR tok_emit    ; write length (uses X=0; preserves A,Y; sets NE)
  STA B           ; length counter
@copy:
  LDA (Ptr),Y     ; next input char
  INY             ; advance input
  JSR tok_emit    ; emit code (uses X=0; preserves A,Y; sets NE)
  DEC B           ; decrement length counter
  BNE @copy       ; -> until done
  RTS

syn_ch:
  JMP syn_chan    ; expect and emit '#' <channel> -> A

syn_ch_s:
  JSR syn_chan    ; expect and emit '#' <channel> -> A
  JSR syn_comma   ; expect ','
  JSR syn_exp_s   ; tokenize and emit string expression
  RTS

                  ; XXX OP_LETN, OP_LETS, OP_LETA opcode must be emtted here...
syn_let:          ; LET <var> '=' <expr> -> {LETn|LETs|LETa}<var><expr> (x2?)
  JSR syn_var     ; expect and emit <name>[$] -> A=type
  STA E           ; save expr type
  LDA #$3D        ; '='
  JSR syn_sym     ; expect '='
  JSR syn_exp     ; tokenize and emit expression -> A=type
  CMP E           ; same as var?
  BNE syn_type    ; -> type mismatch
  RTS

syn_type:
  LDA #<msg_typ   ; "TYP ERR"
  JMP report_err  ; -> report error

syn_dim:          ; DIM <var> '(' <expr> ')' -> {DIM}<var><expr_n>
  JSR syn_var     ; expect and emit <name>[$] -> A=type
  LDA #$28        ; '('
  JSR syn_sym     ; expect '('
  JSR syn_exp_n   ; tokenize and emit numeric expression
  LDA #$29        ; ')'
  JSR syn_sym     ; expect ')'
syn_ret:
  RTS

syn_for:          ; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>] -> {FOR}<var><expr_n><expr_n><expr_n|$00>
  JSR syn_var     ; expect and emit <name>[$] -> A=type
  AND #1          ; mask off TYPE_ARR = 2
  BNE syn_type    ; -> type mismatch (must be TYPE_NUM = 0)
  LDA #$3D        ; '='
  JSR syn_sym     ; expect '='
  JSR syn_exp_n   ; tokenize and emit numeric expression (from)
  LDX #>kwt_to    ; "TO"
  JSR syn_kwo     ; match "TO"
  BCC syn_expect_y ; -> "Expected <kw>"
  JSR syn_exp_n   ; tokenize and emit numeric expression (to)
  LDX #>kwt_step  ; "STEP"
  JSR syn_kwo     ; match "STEP" -> CS=found A=OP
  BCC syn_00      ; emit $00 marker
  JMP syn_exp_n   ; tokenize and emit numeric expression (step)

syn_next:
  JSR skip_spc    ; before is_alpha
  JSR is_alpha    ; X=ln-ofs (uses A) -> CC=alphabetic
  BCS syn_00      ; emit $00 marker (no var)
  JMP syn_var     ; expect and emit <name>[$] -> A=type (XXX runtime type-check)

syn_if:            ; IF <expr_n> THEN <line>/<stmts> [ELSE..] -> {IF}<expr_n><len> | {IFLN}<expr_n><n16>
  JSR syn_exp_n    ; tokenize and emit numeric expression
  LDX #>kwt_then   ; "THEN"
  JSR syn_kwo      ; match "THEN" uses (A,Y,B) -> CS=found
  BCC syn_expect_y ; -> "Expected <kw>"
  BCC @stmts       ; -> no "THEN"
  JSR syn_u16o     ; tokenize and emit u16 -> CS=found
  BCC @stmts       ; -> no <line>
  ; XXX patch opcode = OP_IFLN
@stmts:
  ; XXX emit placeholder for length
  ; XXX set "inside IF" flag and save placeholder ofs
  RTS

syn_else:
  ; XXX check "inside IF" -> missing IF
  ; XXX patch saved length-offset: (Ofs) = X
  ; XXX reserve space for length
  ; XXX set "inside ELSE" flag and save length-offset

syn_read:
  JSR tok_emit_pl ; length placeholder (uses X=0; preserves A,Y; sets NE) -> Dst
  STX D           ; counter
@loop:
  JSR syn_var     ; expect and emit <var>[$]
  INC D           ; count vars
  JSR syn_comma_o ; comma?
  BEQ @loop       ; -> more
  DEY             ; did not consume
@done:
  LDA D           ; get length
  LDX #0          ; const X=0
  STA (Dst),X     ; patch in length over length placeholder
  RTS

syn_input:

; last print-sep is assumed to be ' (newline)
; if a [,;] print-sep appears at the end of the statement, it is used instead
syn_print:

syn_def:


; Syntax Utils

; report missing keyword
syn_expect_y:    ; Y=kw-ofs[kwtab]  (uses A,B,X,Y,Term,Src,Dst)    [USED 1x]
  STY E
  LDY #<msg_syn  ;
  JSR printmsg   ; Y=low (uses A,B,X,Y,Term,Src,Dst)
  LDY E          ; keyword offset
  JSR printkw    ; Y=offset (uses A,Src)
  JSR newline
  JMP repl

syn_rem_len:     ; get remaining length of input (uses A,B) -> A      [USED 1x]
  STX B          ; current ln-ofs
  LDA E          ; length of line from `repl`
  CLC
  SBC B          ; subtract start of data
  RTS

syn_comma:       ;              [USED 2x]
  LDA #$2C       ; ','
syn_sym:
  STA F
  JSR skip_spc   ; Y=ofs -> Y, A=next-char (uses A,X)
  CMP F          ; is it equal?
  BNE @expect    ; -> "Expecting <char>"
  INY            ; consume char
  RTS
@expect:
  JMP err_expect

syn_comma_o:     ;            [USED 2x]
  LDA #$2C       ; ','
syn_sym_o:
  STA F
  JSR skip_spc   ; Y=ofs -> Y, A=next-char (uses A,X)
  CMP F          ; is it equal?
  BNE @over
  INY            ; consume char if matched
@over:
  RTS

syn_chan:        ; expect and emit '#' <channel> -> A   [USED 2x]
  LDA #$23       ; '#'
  JSR syn_sym    ; expect '#'
  JSR num_u16    ; integer literal
  LDA Acc1
  BNE @range     ; -> out of range
  LDA Acc0
  CMP #4         ; is it >= 4
  BCS @range     ; -> out of range (too big)
  JMP tok_emit   ; emit 0-9 (uses X=0; preserves A,Y; sets NE)
@range:
  JMP err_range

; match a keyword in kwtab   [XXX use match_kws instead?]
syn_kwo:         ; Y=ln X=kw (uses A,Y,B) -> CS=found A=OP    [USED 3x]
  JSR skip_spc   ; 
  STY F          ; [3] save ln in case we don't match
  DEX            ; [2] set up for pre-increment
  DEY            ; [2] set up for pre-increment
@loop:
  INX            ; [2] pre-increment
  INY            ; [2] pre-increment
  LDA kwtab,X    ; [4] get keyword char
  CMP (Src),Y    ; [4] matches input char?
  BEQ @loop      ; [3] -> continue until not equal
  CMP #$80       ; [2] CF=(A >= $80) top-bit set
  BCS @found     ; [2] -> found match [+1]
  LDY F          ; [3] restore ln at start of kw
@found:
  RTS            ; [6] -> CS=found A=OP

syn_u16o:        ;          [USED 1x]
  RTS

syn_exp:         ; tokenize and emit expression -> A=type
syn_exp_no:      ; tokenize and emit numeric expression (optional)
syn_exp_n:       ; tokenize and emit numeric expression
syn_exp_s:       ; tokenize and emit string expression
syn_var:         ; expect and emit <name>[$] -> CS=str


; NUDs:
; number
; string
; var[$][(n)]
; ABS[$](x[,y])
; FN<name>[$](...)
; '-' expr
; 'NOT' expr
; '(' expr

; LEDs:
; operators ^ * / + - = <> <= < >= >
; AND,OR,EOR,DIV,MOD
; ')'
; "Missing operator"

oper_tab_sz = 10
oper_tab:
  DB '^'  ; OP_POW
  DB '*'  ; OP_MUL
  DB '/'  ; OP_DIV
  DB '+'  ; OP_ADD
  DB '-'  ; OP_SUB
  DB '='  ; OP_EQ
  DB '<'  ; OP_NE, OP_LT, OP_LE
  DB '<'  ; (for above)
  DB '<'  ; (for above)
  DB '>'  ; OP_GT, OP_GE




; ------------------------------------------------------------------------------
; BASIC LIST

DB "LIST"

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
; REPL Commands

DB "REPL"

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
  LDA #0
  STA CODE
  LDA BasePage      ; copy BasePage into CODE
  STA CODEH
  EOR TopPtrH       ; 0 if TOPH == CODEH (compare)
  ORA TopPtr        ; 0 if TOPL == 0 (compare)
  BEQ @noprog       ; if 0 -> no program
  LDY #0            ; set CODE offset
  STY Data          ; no data yet
  STY DataH         ; no data yet
  JMP do_ln_op      ; -> expect first line (OP_LN)
@noprog:
  RTS

cmd_auto:
  RTS

err_range:
  LDA #<msg_rng
  JMP report_err


; How does this work?
; Walk program lines:
;   Assign next ascending number + $8000 to this program line.
;   Walk the whole program and change all old-line refs to new-line + $8000.
; Walk program lines again, subtract $8000 from all lines and refs.
cmd_renum:
  RTS

cmd_delete:
  RTS

cmd_load:
  RTS

cmd_save:
  RTS

cmd_new:
  LDA #0           ; bottom of BASIC memory
  STA TopPtr       ; end of BASIC program
  LDA BasePage     ; bottom of BASIC memory
  STA TopPtrH      ; end of BASIC program
  RTS

cmd_old:
  ; XX walk old program and verify valid lines
  RTS



; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

DB "RUNT"

; jump table
stmt_l:
  DB <do_ln
  DB <do_cls
  DB <do_close
  DB <do_data
  DB <do_dim
  DB <do_deffn
  DB <do_else
  DB <do_end
  DB <do_for
  DB <do_goto
  DB <do_gosub
  DB <do_if
  DB <do_input
  DB <do_let
  DB <do_line
  DB <do_mode
  DB <do_next
  DB <do_opt
  DB <do_open
  DB <do_plot
  DB <do_poke
  DB <do_print
  DB <do_read
  DB <do_repeat
  DB <do_restore
  DB <do_return
  DB <do_rem
  DB <do_sound
  DB <do_until
  DB <do_wait
  DB <do_fnret
  DB <do_thenln
  DB <do_elseln
stmt_h:
  DB >do_ln
  DB >do_cls
  DB >do_close
  DB >do_data
  DB >do_dim
  DB >do_deffn
  DB >do_else
  DB >do_end
  DB >do_for
  DB >do_goto
  DB >do_gosub
  DB >do_if
  DB >do_input
  DB >do_let
  DB >do_line
  DB >do_mode
  DB >do_next
  DB >do_opt
  DB >do_open
  DB >do_plot
  DB >do_poke
  DB >do_print
  DB >do_read
  DB >do_repeat
  DB >do_restore
  DB >do_return
  DB >do_rem
  DB >do_sound
  DB >do_until
  DB >do_wait
  DB >do_fnret
  DB >do_thenln
  DB >do_elseln

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

; @@ do_ln_op
; expect start of next line
do_ln_op:
  LDA (CODE),Y   ; [5] load token
  CMP #OP_LN     ; [2]
  BNE do_syn0    ; [2] -> syntax error
  INY            ; [2]
  ; +++ fall through to @@ do_ln +++

; @@ do_ln
; start a new line: fold Y into CODE.
; assumes (CODE),Y points at OP_LN.
do_ln:           ; advance past line header; add Y to CODE
  TYA            ; [2] get accumulated Y
  LDY #4         ; [2] skip (LineLo,LineHi,LenBk,LenFw)
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
  ; get ptr to var-list at TOP for this letter     [JSR find_var]
  STY B          ; [3] save Y=code-ofs
  ASL A          ; [2] letter * 2
  TAY            ; [2] 0-25 letter boxes
  LDA (TopPtr),Y ; [5] var-list pointer low byte
  STA Src        ; [3] 
  INY            ; [2] next byte
  LDA (TopPtr),Y ; [5] var-list pointer high byte
  STA SrcH       ; [3] 
  ; scan the list for a matching VAR
  ; XXX

do_syn0:
  LDA #<msg_syn
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
  JSR syn_exp_n  ; [12+] numeric expr (uses A,X,Y,???)
  BCC do_else    ; [2] -> cond is false, advance to ELSE (re-uses do_else code) [+1]
  INY            ; [2] skip length-byte (for ELSE)
  JMP do_stmt    ; [3] -> next stmt


; REM skip Len bytes to reach EOL
; DATA: skip Len bytes to reach EOL
; ELSE: skip Len bytes to reach EOL
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
  JSR do_expr_u16  ; evaluate integer expression (Ptr)
go_line:
  JSR find_line    ; find matching line (addr of 1st statement -> Ptr) or error
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
  JSR do_expr_u16 ; [12+] -> evaluate u16 expression (to Ptr) [2]
  LDA PtrH
  PHA
  LDA Ptr
  PHA
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
  JSR do_expr_u16   ; evaluate int16 expression (to Ptr)
  JSR find_line     ; find matching line (addr of 1st statement -> Ptr) or error
  LDA Ptr
  STA Data          ; pointer to next data, low
  LDA PtrH
  STA DataH         ; pointer to next data, high
  JMP do_stmt


; --- PRINT, INPUT ---


; INPUT:
do_input:
@loop:
  LDA (CODE),Y    ; [5] get tag byte
  INY             ; advance (tag byte)
  ASL             ; bit 7 to carry, bit 6 to sign
  BCS @input      ; -> input var ($80)
  BMI @strlit     ; -> string literal ($40)
  ASL             ; bit 5 to sign
  BMI @nl         ; -> newline ($20)
  JSR newline     ; always newline
  JMP do_stmt     ; end of input
; print a string literal ($40)
@strlit:
  JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
  LDX CODEH       ; string literal high
  LDY CODE        ; string literal low
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  INY             ; +1 for length-byte -> new CODE-ofs
  JMP @loop       ; -> continue
; input to var
@input:
  BPL @readln     ; -> no question mark (no $40)
  LDA #$3F        ; '?'
  JSR wrchr       ; ; print '?' (uses A,X,Src,Dst,F) preserves Y
@readln:
  ; TODO bind VAR
  ; TODO store str/num flag
  JSR readline    ; read input (uses A,X,Y,B,C) -> Y=length (EQ if zero)
  ; TODO parse number
  ; TODO set var
  JMP @loop       ; -> continue
@nl
  JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue


; PRINT
; (MS BASIC: always semi unless explicit comma [stateless])
do_print:
@loop:
  LDA (CODE),Y    ; [5] get tag byte
  BMI @comma      ; -> comma 'tab' ($80 flag)
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
  JSR newline     ; newline at end of print
@endsemi:
  JMP do_stmt     ; end of print (non-zero)
; tab to next field
@comma:
  PHA             ; save A
  LDA #9          ; tab: advance to next print zone (4 coumns x 8 spaces)
  JSR wrctl       ; print $09 tab (uses A,X,Src,Dst,F) preserves Y
  PLA             ; restore A
  BNE @resume     ; -> always (won't be zero)
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
  JSR do_expr_u16  ; evaluate int16 expression -> Ptr
  JSR do_expr_i8   ; A = value to poke
  LDX #0           ; index
  STA (Ptr,X)      ; write to memory at (Acc01)
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


; --- MODE, WAIT, CLS ---

; MODE
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
; find named variable (Y=ofs -> Src; report not found)
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

; @@ do_expr_u16
; evaluate integer expression, range-check u16 -> Ptr
do_expr_u16:
  JSR do_expr_i   ; -> evaluate integer expression  (TODO errors?)
  PLA             ; Acc0
  STA Ptr
  PLA             ; Acc1
  STA PtrH
  PLA
  STA F
  PLA
  ORA F
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

; @@ do_expr
; evaluate an expression (XXX should be do_expr_n, do_expr_s)   (TODO errors?)
; XXX "PRINT" is the outlier, accepting all types...
; XXX tracked state: expect a comma after each expr except the first?
do_expr:
do_expr_n:
do_expr_i:
do_expr_s::
  RTS


; NUDs:
; number
; string
; var[$][(n)]
; ABS[$](x[,y])
; FN<name>[$](...)
; '-' expr
; 'NOT' expr
; '(' expr

; LEDs:
; operators ^ * / + - = <> <= < >= >
; AND,OR,EOR,DIV,MOD
; ')'
; "Missing operator"


; ------------------------------------------------------------------------------
; Numerics

; @@ num_var
; push 1-byte int to the stack (pushed BE->LE)
num_var:
  LDA #VT_NUM    ; [2] variable tag
  JSR find_var   ; [12+] find named variable (Y=ofs -> Src; report not found)
  STY E          ; [3] save Y=ofs
  LDY #3         ; [2] ofs=3
  LDA (Src),Y    ; [5] get Var3
  PHA            ; [3] push Var3
  DEY            ; [2] ofs=2
  LDA (Src),Y    ; [5] get Var2
  PHA            ; [3] push Var2
  DEY            ; [2] ofs=1
  LDA (Src),Y    ; [5] get Var1
  PHA            ; [3] push Var1
  DEY            ; [2] ofs=0
  LDA (Src),Y    ; [5] get Var0
  PHA            ; [3] push Var0
  LDY E          ; [3] restore Y=ofs
  RTS            ; [6]

; @@ num_i1
; push 1-byte int to the stack (pushed BE->LE)
num_i1:
  LDA #0         ; [2]
  PHA            ; [3]  Acc3 (int)
  PHA            ; [3]  Acc2
  BEQ num_i1_e   ; [3]  -> common tail

; @@ num_i2
; push 2-byte int to the stack (pushed BE->LE)
num_i2:
  LDA #0         ; [2]
  PHA            ; [3]  Acc3 (int)
  BEQ num_i2_e   ; [3]  -> common tail

; @@ num_i3
; push 3-byte int to the stack (pushed BE->LE)
num_i3:
  LDA #0         ; [2]
  PHA            ; [3]  Acc3 (int)
  LDA (CODE),Y   ; [3]  Acc2
num_i2_e:
  PHA            ; [3]  Acc2
  LDA (CODE),Y   ; [3]  Acc1
num_i1_e:
  PHA            ; [3]  Acc1
  LDA (CODE),Y   ; [3]  Acc0
  PHA            ; [3]  Acc0
  INY            ; [2]
  RTS            ; [6] // 31

; @@ num_add
; add two 32-bit numbers on the stack (pushed BE->LE)
; 100:Top0 101:Top1 102:Top2 103:Top3
; 104:Trm0 105:Trm1 106:Trm2 107:Trm3
num_add:
  TSX            ; [2] get SP
  LDA $103,X     ; [4] Top3
  ORA $107,X     ; [4] Trm3
; BNE @fpadd     ; [2] -> floating point add [+1] (11)
  CLC            ; [2] no carry in
  PLA            ; [4] get Top0  SP++
  ADC $103,X     ; [4] add Term0 $104-1
  STA $103,X     ; [4] replace Term0
  PLA            ; [4] get Top1  SP++
  ADC $103,X     ; [4] add Term1 $105-2
  STA $103,X     ; [4] replace Term1
  PLA            ; [4] get Top2  SP++
  ADC $103,X     ; [4] add Term1 $106-3
  STA $103,X     ; [4] replace Term1
  PLA            ; [4] Top3  (zero for int)
  RTS            ; [6] // 60

; @@ num_sub
; subtract two 32-bit numbers on the stack (pushed BE->LE)
num_sub:
  TSX            ; [2] get SP
  LDA $103,X     ; [4] Top3
  ORA $107,X     ; [4] Trm3
; BNE @fpsub     ; [2] -> floating point add [+1] (11)
  SEC            ; [2] no carry in
  PLA            ; [4] get Top0  SP++
  SBC $103,X     ; [4] subtract Term0 $104-1
  STA $103,X     ; [4] replace Term0
  PLA            ; [4] get Top1  SP++
  SBC $103,X     ; [4] subtract Term1 $105-2
  STA $103,X     ; [4] replace Term1
  PLA            ; [4] get Top2  SP++
  SBC $103,X     ; [4] subtract Term2 $106-3
  STA $103,X     ; [4] replace Term2
  PLA            ; [4] Top3  (zero for int)
  RTS            ; [6] // 60
  RTS


; @@ num_u16
; tokenize a line number (0-65535)
num_u16:         ; Y=ofs (uses A,Y,B,C,Term) -> Acc,Y,NE=found
  STY C          ; save ofs
  JSR num_u24    ; from LineBuf,X -> Acc,X,CS=found (uses A,Y,B,C,Term)
  BCS num_range  ; -> out of range
  LDA Acc2       ; high byte is non-zero (or number is negative)
  ORA AccE       ; exponent is non-zero (a float)
  BNE num_range  ; -> out of range, negative, on non-integer
  CPY C          ; NE if found; EQ not-found
  RTS

num_range:
  LDA #<msg_rng
  JMP report_err

tok_clc:
  CLC
  RTS            ; CC=not-found

; @@ num_val
; parse a 24-bit number with optional sign prefix (TODO: floating point)
num_val:         ; from LineBuf,Y -> Y,Acc,CS=ovf (uses A,B,X,Term)
  LDA #0
  STA B          ; [3] sign=$00
  LDA (Ptr),Y    ; [5] get first char
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
  INY            ; [2] consume '-'
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
num_u24:         ; from LineBuf,Y-> Y,Acc,CS=ovf (uses A,X,Y,Term)
  LDA #0         ; [2] length of num
  STA Acc0       ; [3] clear result
  STA Acc1       ; [3]
  STA Acc2       ; [3]
  STA AccE       ; [3]
@loop:           ; -> 14+76+25 [115]
  LDA (Ptr),Y    ; [5] get next char
  SEC            ; [2]
  SBC #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS @done      ; [2] >= 10 -> @done
  TAX            ; [2] save digit 0-9
  JSR num_mul10  ; [12+64=76] (uses A,Term) Acc *= 10
  BCS @ovf       ; [2] -> unsigned overflow [+1]
  TXA            ; [2] restore digit -> A
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
  INY            ; [2] advance input
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
num_print:       ; from Acc (uses A,X)
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
; PAGE 9 - GRAPHICS ROUTINES

DB "GRAP"

semigr:
  DB 248  ; top-left
  DB 244  ; top-right
  DB 242  ; bottom-left
  DB 241  ; bottom-right

; @@ gfx_plot
; draw a point at (X,Y)
; all params are u8 on the stack: [00XXXXXX][00YYYYYY]<--
gfx_plot:          ; uses (A,X,Y,F)
  LDA #$02         ; screen base address
  STA DstH         ; set destination high
  PLA              ; [nnYYYYYY] get Y
gfx_plot_1:        ; (A=y, Stack=x)
  CMP #24          ; is it >= 24?
  BCS @done        ; -> out of bounds
  ASL              ; [0YYYYYY0]
  TAX              ; [0YYYYYY0] -> X
  ASL              ; [YYYYYY00]
  ASL              ; [YYYYY000]
  ASL              ; [YYYY0000]
  AND #$F0         ; %11100000  drop low bit Y
  STA F            ; [YYY00000] -> F
  PLA              ; [nnXXXXXX] get X
  CMP #32          ; is it >= 32?
  BCS @done        ; -> out of bounds
  LSR              ; [000XXXXX]X drop low bit X
  ORA F            ; [YYYXXXXX]X <- F
  STA Dst          ; set destination low
; compute semigraphics
  ROL              ; [nnnnnnnX]
  AND #1           ; [0000000X]
  STA F            ; [0000000X] -> F
  TXA              ; [0YYYYYY0] <- X
  AND #2           ; [000000Y0]
  ORA F            ; [000000YX] <- F
  TAX              ; as index
; update screen
  LDY #0
  LDA (Dst),Y      ; read text screen
  CMP #240       ; is it >= 240?
  BCS @merge       ; -> merge semigraphics
  TYA              ; empty text cell
@merge:
  ORA semigr,X     ; OR in semigraphics
  STA (Dst),Y      ; write back
@done:
  RTS


; @@ gfx_line
; draw a Bresenham line (X0,Y0) to (X1,Y1)
; all params are s16 on the stack
gfx_line:          ; uses (A,X,Y)
  LDA #$02         ; screen base address
  STA DstH         ; set destination high
  TSX              ; SP -> X
  LDY #0           ; const
@xmajor:
  LDA #248
  ; XX set up for X major
@xm_lp:
; step bresenham
  ; XX
; step semigraphics
  EOR #$C          ; %1000 <-> %0100  (alternate, every X pixel)
  STA F            ; save A
; write to screen
  LDA (Dst),Y      ; read text screen
  CMP #240       ; is it >= 240?
  BCS @xm_wr       ; -> merge semigraphics
  TYA              ; empty text cell
@xm_wr:
  ORA F            ; OR in semigraphics
  STA (Dst),Y      ; write back

  ; 
  RTS


; ------------------------------------------------------------------------------
; PAGE A - Statement Tokens
ORG $FA00
stmt_page:

; $8x-9x more keywords to follow (same first letter) -$40
; $Cx-Dx last keyword in list (for this letter)      -0
; (ORA #$40 before emit -> $Cx-Dx for statements)

OP_LN      = $C0   ; start-of-line
OP_CLS     = $C1
OP_CLOSE   = $C2
OP_DATA    = $C3
OP_DIM     = $C4
OP_DEFFN   = $C5
OP_ELSE    = $C6   ; ELSE with <length>     (OP_ELSE,$xx vs source "EL.")
OP_END     = $C7
OP_FOR     = $C8
OP_GOTO    = $C9
OP_GOSUB   = $CA
OP_IF      = $CB   ; IF <else-ofs> <cond> (THEN1,0xNN | THEN2,0xNN,0xMM | THEN | ε)   [OP_IF,$nn vs "IF"]
OP_INPUT   = $CC
OP_LET     = $CD
OP_LINE    = $CE
OP_MODE    = $CF
OP_NEXT    = $D0
OP_OPT     = $D1
OP_OPEN    = $D2
OP_PLOT    = $D3
OP_POKE    = $D4
OP_PRINT   = $D5
OP_READ    = $D6
OP_REPEAT  = $D7
OP_RESTORE = $D8
OP_RETURN  = $D9
OP_REM     = $DA
OP_SOUND   = $DB
OP_UNTIL   = $DC
OP_WAIT    = $DD

stmt_count = 30  ; $1E

; extras
OP_STEP    = $DE
OP_THEN    = $DF
OP_THENLN  = $E0
OP_ELSELN  = $E1

kws_a:
kws_b:
kws_c:
kw_cls    DB "CLS",      OP_CLS    -$40
kw_close  DB "CLOSE",    OP_CLOSE  -0     ; #ch
kws_d:
kw_data   DB "DATA",     OP_DATA   -$40
kw_dim    DB "DIM",      OP_DIM    -$40
kw_def    DB "DEF",      OP_DEFFN  -0
kws_e:
kw_else   DB "ELSE",     OP_ELSE   -$40
kw_end    DB "END",      OP_END    -0
kws_f:
kw_for    DB "FOR",      OP_FOR    -0
kws_g:
kw_goto   DB "GOTO",     OP_GOTO   -$40
kw_gosub  DB "GOSUB",    OP_GOSUB  -0
kws_h:
kws_i:
kw_if     DB "IF",       OP_IF     -$40
kw_input  DB "INPUT",    OP_INPUT  -0     ; [#ch,]
kws_j:
kws_k:
kws_l:
kw_let    DB "LET",      OP_LET    -$40
kw_line   DB "LINE",     OP_LINE   -0
kws_m:
kw_mode   DB "MODE",     OP_MODE   -0
kws_n:
kw_next   DB "NEXT",     OP_NEXT   -0
kws_o:
kw_opt    DB "OPT",      OP_OPT    -$40
kw_open   DB "OPEN",     OP_OPEN   -0
kws_p:
kw_plot   DB "PLOT",     OP_PLOT   -$40
kw_poke   DB "POKE",     OP_POKE   -$40
kw_print  DB "PRINT",    OP_PRINT  -0     ; [#ch,]
kws_q:
kws_r:
kw_read   DB "READ",     OP_READ     -$40
kw_rept   DB "REPEAT",   OP_REPEAT   -$40
kw_rest   DB "RESTORE",  OP_RESTORE  -$40
kw_retr   DB "RETURN",   OP_RETURN   -$40
kw_rem    DB "REM",      OP_REM      -0
kws_s:
kw_soun   DB "SOUND",    OP_SOUND  -0
kws_t:
kws_u:
kw_until  DB "UNTIL",    OP_UNTIL  -0
kws_v:
kws_w:
kw_wait   DB "WAIT",     OP_WAIT   -0
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
  DB (kw_cls - stmt_page)     ; "CLS",$C1
  DB (kw_close - stmt_page)   ; "CLOSE",$C2
  DB (kw_data - stmt_page)    ; "DATA",$C3
  DB (kw_dim - stmt_page)     ; "DIM",$C4
  DB (kw_def - stmt_page)     ; "DEF",$C5
  DB (kw_else - stmt_page)    ; "ELSE",$C6
  DB (kw_end - stmt_page)     ; "END",$C7
  DB (kw_for - stmt_page)     ; "FOR",$C8
  DB (kw_goto - stmt_page)    ; "GOTO",$C9
  DB (kw_gosub - stmt_page)   ; "GOSUB",$CA
  DB (kw_if - stmt_page)      ; "IF",$CB
  DB (kw_input - stmt_page)   ; "INPUT",$CC
  DB (kw_let - stmt_page)     ; "LET",$CD
  DB (kw_line - stmt_page)    ; "LINE",$CE
  DB (kw_mode - stmt_page)    ; "MODE",$CF
  DB (kw_next - stmt_page)    ; "NEXT",$D0
  DB (kw_opt - stmt_page)     ; "OPT",$D1
  DB (kw_open - stmt_page)    ; "OPEN",$D2
  DB (kw_plot - stmt_page)    ; "PLOT",$D3
  DB (kw_poke - stmt_page)    ; "POKE",$D4
  DB (kw_print - stmt_page)   ; "PRINT",$D5
  DB (kw_read - stmt_page)    ; "READ", $D6
  DB (kw_rept - stmt_page)    ; "REPEAT",$D7
  DB (kw_rest - stmt_page)    ; "RESTORE",$D8
  DB (kw_retr - stmt_page)    ; "RETURN",$D9
  DB (kw_rem - stmt_page)     ; "REM",$DA
  DB (kw_soun - stmt_page)    ; "SOUND",$DB
  DB (kw_until - stmt_page)   ; "UNTIL",$DC
  DB (kw_wait - stmt_page)    ; "WAIT",$DD


; REPL command list
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
  DB "OLD",$C8    ; $Cx terminates list


; ------------------------------------------------------------------------------
; PAGE B - Expression Tokens

ORG $FB00
expr_page:
kwtab:


; EXPRESSION TOKENS

OP_ABS = $80
OP_ASC = $81
OP_BTN = $82
OP_CHR = $83
OP_EOF = $84
OP_FN  = $85
OP_GET = $86
OP_INSTR = $87
OP_INT = $88
OP_JOY = $89
OP_KEY = $8A
OP_LEN = $8B
OP_LEFT = $8C
OP_MID = $8D
OP_POS = $8E
OP_PI = $8F
OP_RIGHT = $90
OP_RND = $91
OP_SCN = $92
OP_STR = $93
OP_SQR = $94
OP_SGN = $95
OP_TIME = $96
OP_TOP = $97
OP_USR = $98
OP_VAL = $99
OP_VPOS = $9A

; operators in precedence order:
OP_NOT   = $AD       ; unary
OP_UNEG  = $AE       ; unary
OP_UPLUS = $AF       ; unary
OP_POW   = $B0       ; binary
OP_MUL   = $B1       ; binary
OP_DIV   = $B2       ; binary
OP_DIVKW = $B3       ; binary
OP_MODKW = $B4       ; binary
OP_ADD   = $B5       ; binary
OP_SUB   = $B6       ; binary
OP_EQ    = $B7       ; binary
OP_NE    = $B8       ; binary
OP_LT    = $B9       ; binary
OP_LE    = $BA       ; binary
OP_GT    = $BB       ; binary
OP_GE    = $BC       ; binary
OP_AND   = $BD       ; binary
OP_OR    = $BE       ; binary
OP_EOR   = $BF       ; binary

; $8x-9x more keywords to follow (same first letter)  +0
; $Cx-Dx last keyword in list (for this letter)       +$40
; (AND #$BF before emit -> $8x-9x for expressions)

expr_a:
ex_abs  DB "ABS",     OP_ABS    +$40     ; fn (0,0)
ex_asc  DB "ASC",     OP_ASC    +0       ; fn (0,1)  ascii code from string
expr_b:
ex_btn  DB "BTN",     OP_BTN    +0       ; BTN(n) joystick button
expr_c:
ex_chr  DB "CHR$",    OP_CHR    +0       ; fn$ (1,1)
expr_d:
expr_e:
ex_eof  DB "EOF",     OP_EOF    +0       ; # function (2,0)
expr_f:
ex_fn   DB "FN",      OP_FN     +0       ; function-call (9)
expr_g:
ex_get  DB "GET",     OP_GET    +0       ; GET$() key, GET() key
expr_h:
expr_i:
ex_ins  DB "INSTR$",  OP_INSTR  +$40     ; fn$ (1,1) 1st is $
ex_int  DB "INT",     OP_INT    +0       ; fn (0,1)
expr_j:
ex_joy  DB "JOY",     OP_JOY    +0       ; JOY(n) joystick direction
expr_k:
ex_key  DB "KEY",     OP_KEY    +0       ; KEY(n) key down
expr_l:
ex_len  DB "LEN",     OP_LEN    +$40     ; fn-or-fn# (B,1) 1st is $
ex_lft  DB "LEFT$",   OP_LEFT   +0       ; fn$ (1,2) 1st is $
expr_m:
ex_mid  DB "MID$",    OP_MID    +0       ; fn$ (1,3) 1st is $
expr_n:
expr_o:
expr_p:
ex_pos  DB "POS",     OP_POS    +$40     ; fn-or-fn# (B,0)  cursor x
ex_pi   DB "PI",      OP_PI     +0       ; no-arg (0,0)
expr_q:
expr_r:
ex_rgt  DB "RIGHT$",  OP_RIGHT  +$40     ; fn$ (1,2) 1st is $
ex_rnd  DB "RND",     OP_RND    +0       ; fn (0,1)
expr_s:
ex_scn  DB "SCN",     OP_SCN    +$40     ; SCN(x,y)  get screen x,y
ex_str  DB "STR$",    OP_STR    +$40     ; fn$ (1,1) 1st is $
ex_sqr  DB "SQR",     OP_SQR    +$40     ; fn (0,1)
ex_sgn  DB "SGN",     OP_SGN    +0       ; fn (0,1)
expr_t:
ex_tme  DB "TIME",    OP_TIME   +$40     ; no-arg (0,0)
ex_top  DB "TOP",     OP_TOP    +0       ; no-arg (0,0)
expr_u:
ex_usr  DB "USR",     OP_USR    +0       ; fn (0,1)
expr_v:
ex_val  DB "VAL",     OP_VAL    +$40     ; fn (0,1)
ex_vps  DB "VPOS",    OP_VPOS   +0       ; no-arg (3,0)   cursor y
expr_w:
expr_x:
expr_y:
expr_z:
  DB 0

kw_prefix:
kw_not  DB "NOT",     OP_NOT    ; operator
kw_infix:
kw_and  DB "AND",     OP_AND    ; operator
kw_div  DB "DIV",     OP_DIVKW  ; operator
kw_eor  DB "EOR",     OP_EOR    ; operator
kw_mod  DB "MOD",     OP_MODKW  ; operator
kw_or   DB "OR",      OP_OR     ; operator

OP_STRL  = $EE       ; string literal
OPS_NUM  = $EF       ; $EF-FF are number literals
OP_I0    = $F0       ; 1-byte
OP_I9    = $F9       ; 1-byte
OP_INT2  = $FA       ; 2-byte (opc|int8)
OP_INT3  = $FB       ; 3-byte (opc|int16)
OP_INT4  = $FC       ; 4-byte (opc|int24)
OP_FLT2  = $FD       ; 2-byte (opc|mant8)         [".X" = 0.X]
OP_FLT3  = $FE       ; 3-byte (opc|exp8|mant8)    ["1.2"; "2.55"; "10.2"]
OP_FLT4  = $FF       ; 4-byte (opc|exp8|mant16)   ["99.99", "1.9876"]
OP_FLT5  = $EF       ; 5-byte (opc|exp8|mant24)   ["987654.3", "9.876543"]


; context keywords (keep on one page for Y indexing)
; note: `kwtab` is at start of page
kwt_at:
  DB "AT",       $FF      ; AT(x,y) in PRINT
kwt_to:
  DB "TO",       $FF      ; FOR keyword
kwt_step:
  DB "STEP",     OP_STEP  ; FOR keyword
kwt_then:
  DB "THEN",     OP_THEN  ; IF keyword
kwt_spc:
  DB "SPC",      $83      ; SPC(n) in PRINT
kwt_tab:
  DB "TAB",      $84      ; TAB(n) in PRINT
  OP_COMMA =     $80      ; print opcodes
  OP_SEMI =      $81      ; print opcodes
  OP_EOL =       $82      ; print opcodes
kwt_fn:
  DB "FN",       $00      ; DEF keyword



expr_rev:                  ; [29]
  DB (ex_abs - expr_page)  ; "ABS",$80
  DB (ex_asc - expr_page)  ; "ASC",$82
  DB (ex_btn - expr_page)  ; "BTN",$82
  DB (ex_chr - expr_page)  ; "CHR",$86
  DB (ex_eof - expr_page)  ; "EOF",$8A
  DB (ex_fn  - expr_page)  ; "FN",$8F
  DB (ex_get - expr_page)  ; "GET",$90
  DB (ex_ins - expr_page)  ; "INSTR",$92
  DB (ex_int - expr_page)  ; "INT",$93
  DB (ex_joy - expr_page)  ; "JOY",$91
  DB (ex_key - expr_page)  ; "KEY",$91
  DB (ex_len - expr_page)  ; "LEN",$94
  DB (ex_lft - expr_page)  ; "LEFT",$95
  DB (ex_mid - expr_page)  ; "MID",$98
  DB (ex_pos - expr_page)  ; "POS",$9A
  DB (ex_pi  - expr_page)  ; "PI",$9B
  DB (ex_rgt - expr_page)  ; "RIGHT",$9C
  DB (ex_rnd - expr_page)  ; "RND",$9E
  DB (ex_scn - expr_page)  ; "SCN",$9E
  DB (ex_str - expr_page)  ; "STR",$9F
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
; PAGE C - SYSTEM
ORG $FC00

; @@ key_scan     (107b code; 254b for all KB stuff!)
; scan the keyboard matrix for a keypress
; [..ABCDE....]
;    ^hd  ^tl     ; empty when hd==tl, full when tl+1==hd
keyscan:          ; uses A,X,Y returns nothing (CANNOT use B,C,D,E)
  LDA #0          ; [2] zero
  STA IRQTmp2     ; [3] clear key-hit flag (is any key down?)
  LDY #8          ; [2] last key column
  STY IO_KEYB     ; [3] set keyscan column (0-7) 0µs
  DEY             ; [2] prev column              2µs
  LDA IO_KEYB     ; [3] read row_bitmap          2+3µs read 5/0.89Mhz = 5.6µs settle
  STA ModKeys     ; [3] update modifier keys     3µs
  CMP IO_KEYB     ; [3] check if stable          3+3µs read 6/0.89Mhz = 6.7µs verify
  BNE keyscan     ; [2] if not -> try again
@col_lp:          ; -> [13] cycles
  STY IO_KEYB     ; [3] set keyscan column (0-7)           0µs (-> 7+3=10µs after prior)
  NOP             ; [2] delay                              2µs
  LDX IO_KEYB     ; [3] read row_bitmap                    2+3µs read 5/0.89Mhz = 5.6µs settle
  BNE @key_hit    ; [2] -> one or more keys pressed [+1]   2µs -> 1µs (3µs)
@col_cont:
  DEY             ; [2] prev column                        2µs
  BPL @col_lp     ; [3] go again, until Y<0                2+2+3µs -> (7µs)
; key up or auto-repeat
  LDA IRQTmp2     ; [3] check key-hit flag (any key down?)
  BNE @rep_chk    ; [2] -> key is down, check for auto-repeat
  STY LastKey     ; [3] no keys pressed: clear last key pressed (to $FF)
  RTS
@rep_chk:
  LDY LastKey     ; [3] get last phys_key
  LDA #4          ; [2] repeat rate: ?? per sec
  DEC KeyRep      ; [5] count down to auto-repeat
  BEQ @repeat     ; [2] -> repeat last key (Y=phys_key) [+1]
  RTS             ; [6] TOTAL Scan 2+13*8-1+6 = [111] cycles
@key_hit:         ; X=row_bitmap Y=column
  CPX IO_KEYB     ; [3] check if stable                    3+3µs read 6/0.89Mhz = 6.7µs verify
  BNE @col_lp     ; [2] if not -> try again
  STY IRQTmp      ; [3] save keyscan column for resuming
  TYA             ; [2] active keyscan column
  ASL             ; [2] column * 8
; debounce check 
  ASL             ; [2] 
  ASL             ; [2] 
  TAY             ; [2] scantab offset = col*8 as index  (X=row_bitmap Y=col*8 IRQTmp=column)
  TXA             ; [2] A = row_bitmap
; find first bit set
; loop WILL terminate because A is non-zero!
@bsf_lp:          ; A=row_bitmap Y=scantab -> [7] cycles
  INY             ; [2] count number of shifts (Y = col*8 + row_N)
  ASL A           ; [2] shift keys bits left into CF
  BCC @bsf_lp     ; [3] until CF=1 (key is down)                            (XXX will invert, down == 0)
; key already down?
  STY IRQTmp2     ; [3] set key-hit flag (any key was down)
  CPY LastKey     ; [3] one-key roll over
  BEQ @was_down   ; [2] -> key was already down
  STY LastKey     ; [3] save last physical key pressed (exit path)
  LDA #16         ; [2] initial delay: ?? sec
@repeat:          ; (Y=phys_key)
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
  AND #15         ; [2] modulo circular buffer
  CMP KeyHd       ; [3] is Tl+1 == Hd ?
  BEQ @full       ; [2] -> key buffer is full (don't update KeyTl)
  STA KeyTl       ; [3] update Tl = Tl+1 % 32
@full:
  RTS             ; [6] done (after one keypress detected)
@shift:
  LDA scanshf-1,Y ; [4] translate to ASCII (Y is off by +1)
  BPL @shft_ret   ; [3] top bit is never set!! (XX won't hold for Gfx)
@was_down:        ; (A=row_bitmap Y=phys_key IRQTmp=column)
;  RTS             ; XXXXX debug (1-key, we want 2-key)
  TAX             ; [2] test remaining row_bitmap
  BNE @bsf_lp     ; [3] -> continue bsf loop if A != 0 (more keys are down)   (XXX will invert this, $FF)
  LDY IRQTmp      ; [3] restore keyscan column (always > 0)
  JMP @col_cont   ; [3] -> continue scanning columns

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

; @@ wrchr       (95b wrchr + newline)
; write a single character to the screen
; assumes we're in text mode with TXTP set up
wrchr:            ; A=char; (uses A,X,F,Src,Dst) preserves Y [25]
  CMP #32         ; [2] is it a control character?
  BCC wrctl       ; [2] -> ch < 32, do control code [+1]  (uses A,X preserves Y)
  LDX #0          ; [2] const for (TXTP,X) ie (TXTP)
  STA (TXTP,X)    ; [6] write character to video memory
  INC TXTP        ; [5] advance text position
  LDA TXTP        ; [5] get new TXTP
  AND #31         ; [2] at start of a line?
  BEQ @nl         ; [2] if so -> newline [+1]
  RTS             ; [6]
@nl:
  DEC TXTP       ; [5] undo advance (back to end of prior line)
  ; +++ fall through to @@ newline +++

; @@ newline, in "text mode"
; advance to the next line inside the text window
; scroll the text window if we're at the bottom
; assumes we're in text mode with TXTP set up
newline:          ; (uses A,X,F,Src,Dst) preserves Y
  LDA TXTP        ; [3]
  ORA #31         ; [2] to end of current line
  TAX             ; [2]
  INX             ; [2] plus 1, to start of next line
  STX TXTP        ; [3]
  BNE @nl_noh     ; [2] -> no page-cross [+1]
  LDA TXTPH       ; [3] test TXTPH
  CMP #$04        ; [2] at bottom of screen?    [$02 $03 $04]
  BEQ scroll      ; [2] -> scroll down [+1]
  INC TXTPH       ; [5] go down one page
@nl_noh:
  RTS             ; [6]

; @@ scroll
; scroll the text window up one line
scroll:           ; (uses A,X,F,Src,Dest) preserves Y
  TYA             ; save Y for caller
  PHA
; set up Src
  LDY WinT         ; 
  INY              ; row = WinT-1
  TYA              ;
  JSR txt_row      ; A=row -> AX=addr (uses A,X,Y,F)
  STA SrcH
  STX Src
; set up Dst
  LDA WinT         ; row = WinT
  JSR txt_row      ; A=row -> AX=addr (uses A,X,Y,F)
  STA DstH
  STX Dst
; scroll up one line
  LDY WinH
  DEY              ; rows = WinH - 1
  BEQ @noscr       ; -> height = 1, no scroll
  JSR txt_rowsz_y  ; Y=rows -> AX=size (uses A,X,Y,F)
  JSR copy_fw      ; copy forwards AX=size (uses A,X,Y,F,Src,Dest)
@noscr:
; clear the bottom row
  LDA WinT         ; XX in support of WinB
  CLC
  ADC WinH         ; bottom of window (too far)
  ADC #$FF         ; minus 1
  LDX #0
  JSR txt_addr_tp  ; A=row X=0 -> AX=TXTP (uses A,X,Y,F)
  JSR txt_clr      ; clear row at TXTP (uses A,Y)
; return
  PLA              ; restore Y for caller
  TAY               
  RTS              ; [6]


; @@ wrctl       (105b wrctl)
; write a single control code
; assumes we're in text mode with TXTP set up
wrctl:           ; (uses A,X,F,Src,Dst) preserves Y
  CMP #13        ; [2] is it RETURN?
  BEQ newline    ; [2] -> do newline [+1]
  CMP #8         ; [2] is it BACKSPACE?
  BEQ @backsp    ; [2] -> do backspace [+1]
  CMP #$1E       ; [2] is it LEFT ARROW?
  BEQ @left      ; [2] -> do move left [+1]
  CMP #$1F       ; [2] is it RIGHT ARROW?
  BEQ @right     ; [2] -> do move right [+1]
  CMP #$1C       ; [2] is it UP ARROW?
  BEQ @up        ; [2] -> do move left [+1]
  CMP #$1D       ; [2] is it DOWN ARROW?
  BEQ @down      ; [2] -> do move left [+1]
  CMP #12        ; [2] is it CLS?
  BEQ @cls       ; [2] -> do cls [+1]
  RTS

@backsp:         ; go back one cell and clear it
  JSR @left      ; [12+] move cursor left one place
  LDA #32        ; [3] space character
  LDX #0         ; [2] const for (TXTP,X) ie (TXTP)
  STA (TXTP,X)   ; [6] clear the character under the cursor
  RTS            ; [6] // 9

@left:           ; move left one place
  DEC TXTP       ; [5] go back one space
  LDA TXTP       ; [3] 
  CMP #$FF       ; [2] crossed page?
  BEQ @up_pg     ; [2] -> crossed page, go up one page [+1]
  RTS            ; [6] // 9

@up:             ; move up one line
  LDA TXTP       ; [3]
  SEC            ; [2]
  SBC #32        ; [2]
  STA TXTP       ; [3]
  BCS @done      ; [2] -> no page-cross [+1]
@up_pg:
  DEC TXTPH      ; [5] go up one page
  LDA TXTPH      ; [3] test TXTPH
  CMP #$01       ; [2] off top of screen?      [$02 $03 $04]
  BNE @done      ; [2] -> no, we're done [+1]
  LDA #$04       ; [2] last screen page
  STA TXTPH      ; [3] wrap around to top of screen
  RTS            ; [6] // 22

@right:          ; move right one place
  INC TXTP       ; [5] go forward one space
  BEQ @down_pg   ; [2] -> crossed page, go down one page [+1]
  RTS            ; [6] // 5

@down:           ; move down one line
  LDA TXTP       ; [3]
  CLC            ; [2]
  ADC #32        ; [2]
  STA TXTP       ; [3]
  BCC @done      ; [2] -> no page-cross [+1]
@down_pg:
  INC TXTPH      ; [5] go down one page
  LDA TXTPH      ; [3] test TXTPH
  CMP #$05       ; [2] off bottom of screen?    [$02 $03 $04]
  BNE @done      ; [2] -> no, we're done [+1]
  LDA #$02       ; [2] first screen page
  STA TXTPH      ; [3] wrap around to top of screen
@done:
  RTS            ; [6] // 22

@cls:
  TYA            ; [2]
  PHA            ; [2] save Y for caller
  JSR vid_cls    ; [2] -> do cls (uses A,X,Y,F) [+1]
  PLA            ; [2]
  TAY            ; [2] restore Y for caller
  RTS            ; [6] // 17



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
; write a length-prefix string to the screen in text-mode
print:           ; X=high Y=low (uses A,B,X,Y,Term,Src,Dst) -> Y = strlen (excludes length byte)
  STX PtrH       ; pointer high
  STY Ptr        ; pointer low
  LDY #0         ; string offset, counts up
  LDA (Ptr),Y    ; load string length
  BEQ @ret       ; -> nothing to print
  STA B          ; length to print
  LDX #0         ; const for (TXTP,X) ie (TXTP)
@loop:
  INY            ; [2] advance to next char              2
  LDA (Ptr),Y    ; [5] load char from string             7
  ; begin wrchr inline
  CMP #32        ; [2] is it a control character?        9
  BCC @ctrl      ; [2] if <32 -> @ctrl [+1]              11
  STA (TXTP,X)   ; [6] write character to video memory   17
  INC TXTP       ; [5] advance text position             22
  LDA TXTP       ; [5] get new TXTP                           (6b) NoRem  6+8=14
  AND #31        ; [2] test low 5 bits
  BEQ @nl        ; [2] if so -> newline [+1]
  ; end wrchr inline
@incr:
  CPY B          ; [5] equals length?                    32
  BNE @loop      ; [2] not at end -> @loop [+1]          35 per char!
@ret
  RTS            ; [6] done; Y = strlen (excludes length byte)
@nl:             ; wrap onto the next line and keep printing
  DEC TXTP       ; [5] undo advance (back to end of prior line)
  LDA #13        ; [2] newline control code
@ctrl:
  JSR wrctl      ; [6] execute control code (uses A,X,Src,Dst) preserves Y
  LDX #0         ; [2] restore constant X=0
  BEQ @incr      ; [3] -> always


; ------------------------------------------------------------------------------
; READLINE, LINE EDITOR

; Arrows move within the line; insert or delete text within the line
; Up/Down goes to Start/End. TAB to complete a line.

; BUG: by happenstace, BASIC starts on an 8th line which ends at TXTP=255,
; had a bug at WinW=32 where TXTPH didn't get incremented (fixed!)


; @@ readline
; read a single line of input into the line buffer (zero-terminated)
readline:        ; uses A,X,Y,B,C returns Y=length (EQ if zero)
  LDA #0
  STA B          ; init line length
  STA C          ; init line cursor (linear)
  LDA TXTP       ; save start of line input
  STA Ptr        ; return this Ptr (adjusted for scrolling)
  LDA TXTPH
  STA PtrH
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
  CPY #$7F       ; is buffer full?         (XXX restrict text window to ensure >=128?)
  BEQ @beep      ; buffer full -> beep
  INC C          ; advance line cursor
  INC B          ; increase line length
  JSR wrchr      ; print char to screen (A=char, uses A,X, preserves Y)    (XXX insert char at cursor C, copy chars)
@more:           ; keep reading chars                                      (XXX if we scroll, update Ptr -= 32!)
  JSR readchar   ; read char from keyboard (uses A,X,Y -> A,ZF)            (easy ver uses LineBuf, copy-up/down loop,
  BNE @cont      ; -> continue typing                                       then re-prints the result to the screen)
  BEQ @idle      ; -> return to idle
@ctrl:
  JSR wrchr      ; XXXX test 
  JMP @more      ; XXXX test 
  CMP #13        ; is it RETURN?
  BEQ @return    ; -> return
  CMP #8         ; is it BACKSPACE?
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
  JMP escape
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
  STA (Ptr),Y    ; write terminator to line buffer   (XXX this is now visible on-screen !)
  RTS            ; returns Y=length (ZF=1 if zero)
@backsp:
  LDY C          ; load line cursor
  BEQ @beep      ; -> at start of buffer, beep
  JSR wrctl      ; backspace the display (A=8) (uses A,X, preserves Y -> CC=fail)   (XXX copy-down instead)
  BCC @beep      ; -> could not move left (e.g. scrolled off the top)
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
vid_mode:        ; set screen mode, A=mode (uses A,X,Y,F)
  AND #1         ; modes 0-1
  STA IO_VCTL    ; set video mode; reset border color
  LDA #$0F       ; BG=black FG=white (for APA mode)
  STA IO_VPAL    ; set palette
  LDA #0
  STA WinT       ; reset text window top
  LDA #24        ;
  STA WinH       ; reset text window height
  ; +++ fall through to @@ vid_cls +++

; @@ vid_cls
; clear the screen or text window
vid_cls:                 ; (uses A,X,Y,F)
  LDA WinT               ; [3] text window top
  LDX #0                 ; [2] col=0
  JSR txt_addr_tp        ; [6] A=row X=col -> TXTP(AX) (uses A,X,Y,F)
  LDX WinH               ; [3] number of rows
@row:
  JSR txt_clr            ; [6] clear row at TXTP (uses A,Y)
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
  CPX #32        ; clamp X if out of range (WinW)                       (window: would be AND #31)
  BCC @x_ok      ; -> X < WinW (OK)                                     (window)
  LDX #31        ; (CS)                                                 (window)
@x_ok:
  CPY WinH       ; clamp Y if out of range (WinH)                       (window: #23)
  BCC @y_ok      ; -> Y < WinH (OK)
  LDY WinH       ;                                                      (window: #23)
  DEY            ; clamp to last row  (XXX reduce WinH by -1?)          (window)
@y_ok:
tab_e2:
; Map from text window X,Y to screen X,Y
; the text plane is 32x24 in text mode
  TYA            ; Y row in text window                                 (window: add WinT)
  CLC            ;                                                      (window: add WinT)
  ADC WinT       ; Y row in screen space (add window top)               (window: add WinT)
  ; +++ fall through to @@ txt_addr_tp +++

; @@ txt_addr_tp
; calculate VRAM address for A=row X=col in text mode; set TXTP
txt_addr_tp:     ; A=row X=col -> TXTP(AX) (uses A,X,Y)
  JSR txt_addr   ; AX -> AX
  STA TXTPH      ; set TXTPH
  STX TXTP       ; set TXTP
  RTS            ; 

; @@ txt_row
; calculate screen row address
txt_row:           ; A=row -> AX=addr (uses A,X,Y,F)
  LDX #0           ; col = 0
  ; +++ fall through to @@ txt_addr +++

; @@ txt_addr
; calculate screen address
txt_addr:          ; A=row X=col -> AX=addr (uses A,X,Y,F)  [19]
  STX F            ; [000XXXXX] -> F
  ROR              ; [0000YYYY]Y
  ROR              ; [Y0000YYY]Y
  ROR              ; [YY0000YY]Y
  TAY              ; [YY0000YY] -> Y
  ROR              ; [YYY0000Y]Y
  AND #$E0         ; [YYY00000]
  ORA F            ; [YYYXXXXX] <- F
  TAX              ; -> X
  TYA              ; [YY0000YY] <- Y
  AND #3           ; [000000YY]
  CLC              ; no carry
  ADC #2           ; VRAM base high byte
  RTS              ; -> AX=address

; @@ txt_rowsz_y
; convert N text-rows to linear size
txt_rowsz_y:       ; Y=rows -> AX=size (uses A,X,Y)
  TYA
  ; +++ fall through to @@ txt_rowsz +++

; @@ txt_rowsz
; convert N text-rows to linear size
txt_rowsz:         ; A=rows -> AX=size (uses A,X,Y)
  ROR              ; [0000YYYY]Y
  ROR              ; [Y0000YYY]Y
  ROR              ; [YY0000YY]Y
  TAY              ; [YY0000YY] -> Y
  ROR              ; [YYY0000Y]Y
  AND #$E0         ; [YYY00000]
  TAX              ; -> X
  TYA              ; [YY0000YY] <- Y
  AND #3           ; [000000YY]
  RTS              ; -> AX=size


; @@ txt_clr
; fill a text row at TXTP (does not change TXTP)
txt_clr:           ; (uses A,Y)
  LDA #32          ; fill with spaces
txt_fill:          ; fill with A
  LDY #31          ; count = 31
@loop:
  STA (TXTP),Y     ; write a space
  DEY              ; decrement column
  BPL @loop        ; -> until Y=-1
  RTS


; @@ copy_fw
; copy memory forwards (new < old)
; from (Src) to (Dest) with AX=size
copy_fw:                 ; copy forwards AX=size (uses A,X,Y,F,Src,Dest)
  STA F                  ; [3] page counter            F = 1
@page:
  LDY #0                 ; [3] page offset             Y = 0                  Y = 0     Y = FE    Y = FF
@span:
  LDA (Src),Y            ; [3] read byte               (Src),0  (Src),1       (Src),0   (Src),FE  (Src),FF
  STA (Dst),Y            ; [3] write byte              (Dst),0  (Dst),1       (Dst),0   (Dst),FE  (Dst),FF
  INY                    ; [2] increment page offset   Y = 1    Y = 2         Y = 1     Y = FF    Y = 0
  DEX                    ; [2] decrement span count    X = 1    X = 0         X = FF    X = 1     X = 0
  BNE @span              ; [3] -> until X=0            ->       EQ            ->        ->        EQ
; advance to next page
  LDX #0                 ; [2] next span count = 256                X = 0                            X = 0
  TYA                    ; [2] final Y = initial X                  Y = 2                            Y = 0
  BEQ @whole             ; [2] -> whole page step                   NE                               ->
  CLC                    ; [2]
  ADC Src                ; [3] bump Src += Y                      Src += 2
  STA Src                ; [3] 
  BCC @no_shi            ; [2]
  INC SrcH               ; [5]
@no_shi:
  TYA                    ; [2] final Y = initial X
  CLC                    ; [2]
  ADC Dst                ; [3] bump Dst += Y                      Dst += 2
  STA Dst                ; [3]
  BCC @no_dhi            ; [2]
  INC DstH               ; [5]
@no_dhi:
  JMP @page              ; [3] until pages=0                      ->
@whole:
  INC SrcH               ; [5] Src += 256                                                       Src += 256
  INC DstH               ; [5] Dst += 256                                                       Dst += 256
  DEC F                  ; [2] decrement page counter                                               F = 0
  BNE @page              ; [3] until pages=0                                                        EQ
  RTS                    ; [6]


; @@ copy_bw
; copy memory backwards (old < new)
; from (Src) to (Dest) with length AX
copy_bw:                 ; uses (A,X,Y,F,Src,Dest)    258 bytes = $0102
  STA F                  ; [3] page counter           F = 1
  LDA SrcH               ; [3] Src += A * 256         Src += 256
  CLC
  ADC F
  STA SrcH
  LDA DstH               ; [3] Dst += A * 256         Dst += 256
  CLC
  ADC F
  STA DstH
  TXA
  BEQ @page              ; [2] -> no residual X
  INC F                  ; [5] +1 page (residual)      F = 2
@page:
  TXA                    ; [2] X = counter             X=2                         X=0       X=FF
  TAY                    ; [2] Y = offset              Y=2                         Y=0       Y=FF
@span:
  DEY                    ; [2] pre-decrement           Y=1          Y=0            Y=FF      Y=FE
  LDA (Src),Y            ; [3] read byte               (Src+256),1  (Src+256),0    (Src),FF  (Src),FE
  STA (Dst),Y            ; [3] write byte              (Dst+256),1  (Dst+256),0    (Dst),FF  (Dst),FE
  DEX                    ; [2] decrement span count    X=1          X=0            X=FF      X=FE
  BNE @span              ; [3] -> until X=0            ->           EQ             ->        ->
; advance to next page
  DEC SrcH               ; [5] Src -= 256                                 Src                   -Src
  DEC DstH               ; [5] Dst -= 256                                 Dst                   -Dst
  LDX #0                 ; [2] span count = 256                           X = 0                 X = 0
  DEC F                  ; [2] decrement page counter                     F = 1                 F = 0
  BNE @page              ; [3] until pages=0                              ->                    EQ
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
