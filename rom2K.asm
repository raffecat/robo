; Frontier 2K BASIC
; Use `asm6` to compile: https://github.com/parasyte/asm6

BasROM   = $200   ; 2K BASIC

ZeroPg   = $00    ; zero page (constant)
StackPg  = $01    ; stack page (constant)
VidBase  = $A0    ; start of video memory ($A000)
BaseAdr  = $0200  ; start of free memory (constant $0200)
End4K    = $10    ; end of 4KB memory (minimum RAM fitted)

; ------------------------------------------------------------------------------
; Monitor Routines

cls  = $FF06
home = $FF18
tclr = $FF25
cpyf = $FF2F
rdln = $FF51
wrnl = $FF91
wrsp = $FF9E
wrch = $FFA0
prhx = $FFE3

; ------------------------------------------------------------------------------
; Zero Page $00-7F - BASIC WORKSPACE

; -- $00-3F BASIC Arg Stack (64 bytes)

Args     = $00    ; Ascending Empty Stack, 32 words (ArgTop)

LineNo   = $00    ; ALIAS Parsed line number                      (used in EDIT)
LineNoH  = $01    ; ALIAS Parsed line number                      (used in EDIT)

; -- $70-7F Array Vars (16)

ArrVars  = $70    ; [@-G] 8 x 16-bit pointers

; -- $80-B5 Integer Vars (54)

IntVars  = $80    ; [@-Z] 27 x 16-bit variables                   (used in RT / Direct)

; -- $B6-BF BASIC Pointers (12 bytes)

OpTop    = $B6    ; Top of Oprs (stack pointer)                   (used in RT / Direct)
ArgTop   = $B7    ; Top of Args (stack pointer)                   (used in RT / Direct)
Data     = $B8    ; BASIC data pointer (next DATA statement)      (used in RT)
DataH    = $B9    ; 
CODE     = $BA    ; BASIC code pointer (next instruction)         (used in RT / Direct)
CODEH    = $BB
TopPtr   = $BC    ; TOP of BASIC program, start of variables      (used in RT / EDIT)
TopPtrH  = $BD
FreePtr  = $BE    ; FREE space at end of variables                (used in RT / Direct / EDIT)
FreePtrH = $BF

EmitOfs  = DataH  ; ALIAS: emit offset for tokenized code         (used in EDIT)

; -- $C0-CF System Temporaries (16)

Src      = $C0        ; source pointer \ Scroll (PRINT/WRCH), CLS  [Term0]
SrcH     = $C1        ; source pointer | Tokenize (match_kws/num_val)     [Term1]
Acc0     = Src        ; ALIAS: accumulator byte 0          (used in RT / Direct)
Acc1     = SrcH       ; ALIAS: accumulator byte 1
Dst      = $C2        ; destn pointer  | Scroll (PRINT/WRCH), CLS  [Term2]
DstH     = $C3        ; destn pointer  /                                  [TermE]
Term0    = Dst        ; ALIAS: term byte 0
Term1    = DstH       ; ALIAS: term byte 1
Ptr      = $C4        ; third pointer  \ VAR ptr, STR ptr, PRINT src (can cause Scroll)
PtrH     = $C5        ; third pointer  /
B        = $C6        ; extra register | Subroutines are annotated with usage;
C        = $C7        ; extra register | held across calls only when unused
D        = $C8        ; extra register | by callees (manually tracked)
E        = $C9        ; extra register |
F        = $CA        ; extra register |

TXTP     = $CB        ; text write address
TXTPH    = $CC        ; text write address high
RemX     = $CD        ; remaining space on line
CurTime  = $CE        ; cursor flash timer

MemSize  = $CF        ; detected memory size in pages

; -- $D0-E7 free (24)

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
IO_KEY   = $F8        ; ASCII keyboard read (7-bit)
IO_CAS   = $F9        ; Cassette IO (3:Speaker 2:RTS 1:TXD 0:TapeTx) / Read (7:KeyLatch 2:CTS 1:RXD 0:TapeRx)
IO_RES1  = $FA        ; Reserved
IO_RES2  = $FB        ; Reserved
IO_RES3  = $FC        ; Reserved
IO_RES4  = $FD        ; Reserved
IO_RES5  = $FE        ; Reserved
IO_RES6  = $FF        ; Reserved

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

Oprs     = $100    ; Operator Stack (32 bytes)

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

msg_ok:
  DB "OK",13,0

; error messages (36b)
msg_syn:  DB "SYN",0
msg_rng:  DB "RNG",0
msg_for:  DB "FOR",0
msg_gos:  DB "GOS",0
msg_typ:  DB "TYP",0
msg_esc:  DB "ESC",0


; ------------------------------------------------------------------------------
; BASIC

reset:
  SEI               ; disable interrupts
  CLD               ; disable BCD mode
  LDX #$FF          ; X = $FF
  TXS               ; reset SP = $FF
  LDA #End4K        ; end of memory (page)                XXX detect memory
  STA MemSize       ; set size of memory (in pages)
  JSR cls           ; clear screen
repl:
  LDY #<msg_ok      ; "OK"
  JSR err_wrn       ; print it (uses A,X,Y)
  JSR rdln          ; read command or BASIC statement
; parse the line
  LDY #0            ; offset = 0
  JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Acc/Src,Term/Dst)
  CPY #0            ; no match?
  BEQ @direct       ; -> no line number [+1]
  LDA Acc1          ; save LineNo
  STA LineNoH       ; 
  LDA Acc0          ; 
  STA LineNo        ; 
  JSR skip_spc      ; Y=ofs -> A,X=next-char (EQ if zero)
  BEQ @delln        ; -> empty line, delete the line [+1]
  JSR tokenize      ; tokenize the line
  ;JSR debug         ;
  ; insert the line
  JMP repl          ; -> return to repl
@direct:
  JSR skip_spc      ; Y=ofs -> A,X=next-char (EQ if zero)
  BEQ repl          ; -> empty line, back to repl [+1]
  JSR tokenize      ; tokenize the line
  ;JSR debug         ;
  LDA #OP_END       ; 
  JSR tok_emit      ; terminate the line
  LDA #>EmitBuf     ; EmitBuf page ($01)
  LDX #0            ; at offset 0
  JSR set_prog      ; set up for execution
  JMP stmt          ; -> execute the statement  (XXX how does this return without OP_END?)
@delln:
  JSR del_line      ; delete the line at LineNo
  JMP repl



; ------------------------------------------------------------------------------
; Errors


; @@ escape
; report Escape pressed, return to REPL  (5b)
escape:
  ; JSR hide_cursor   ; uses A,Y; Y=0 (for Escape)
  LDY #<msg_esc     ; "ESC"
  ; +++ fall through +++

; @@ err_rep
; report an error with `#` prefix  (17b)
report_err:
err_rep:            ; Y=msg_ofs
  JSR wrnl          ; new line (uses A,X) preserves Y
  LDA #35           ; `#`
  DEY               ; for INY
  JSR err_wr        ; write #<MSG>
  JSR wrnl          ; new line (uses A,X) preserves Y
  JMP repl          ; -> always

; @@ err_wr
; write a message with prefix (zero-terminated)  (9b)
; also used by TAPE routines
err_wr:             ; Y=message A=prefix_char
  JSR wrch          ; write char (A=char, uses A,X) preserves Y
  INY               ; 
err_wrn:            ; Y=message (no prefix)
  LDA messages,Y    ; next char
  BNE err_wr        ; loop until zero
  RTS               ; -> EQ



; ------------------------------------------------------------------------------
; BASIC Tokenizer
;
; Y = LineBuf offset
; A,X = temporaries

; emit a string literal
emit_str:
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
  BNE tk_emt         ; -> emit and continue
@missing:            ; at end of line, missing quote
  LDY <msg_syn       ; #MIS
  BNE err_rep        ; -> report error

tk_sym:
  LDA #<expr_ops     ; operator table
  BNE tk_mkw         ; -> ALWAYS

; @@ tokenize
; tokenize BASIC statements (in-place in LineBuf/EmitBuf)
tokenize:            ; Y=ofs,D=0 uses A,X,B,C,D,Src
  JSR skip_spc       ; Y=ofs -> A,X=next-char (EQ if zero)
  BEQ tk_ret         ; -> end of line
  EOR #64            ; '@' to 0
  CMP #27            ; 26 letters plus @
  BCS tk_sym         ; -> not a letter
  TAX                ; A-Z index (0-26)
  LDA kw_tab,X       ; look up KW offset (A-Z)
tk_mkw:
  JSR match_kws      ; Y=ofs A=kw_ofs -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC tk_not         ; -> not a token
  AND #$BF           ; clear bit 6 ($40)
tk_emt:
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y; sets PL)
  BPL tokenize       ; -> ALWAYS
tk_ret:
  RTS

tk_not:
  LDA LineBuf,Y      ; reload A=next-char
  TAX                ; save A
  EOR #48            ; make '0' be 0
  CMP #10            ; 10 digits
  BCC tk_num         ; -> emit number
  TXA                ; A=next-char
  BCS tk_emt         ; -> ALWAYS

tk_num:
  JSR num_u16        ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Acc/Src,Term/Dst)
  STY B              ; save Y
  LDY #2             ; OP_INT3 (+2) "extra +1" for BPL loop
  LDA $01            ;
  BNE @out           ; -> 2 bytes plus opcode
  DEY                ; OP_INT2 (+1)
  LDA $00            ;
  CMP #10            ; CS if >= 10
  BCS @out           ; -> 1 byte plus opcode
; single-digit number
  SBC #8             ; minus 9 (CS=0)
  TAY                ; [-9..0]
@out:                ; <- CS=1
  TYA                ; Y=OP_INTn|OP_In
  SEC                ; for single-digit path
  ADC #OP_INT2-2     ; 3->OP_INT4 2->OP_INT3 1->OP_INT2 (-2 for CS=1 and "extra +1")
@lp:
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  LDA Acc0-1,Y       ; 3->Acc2 2->Acc1 1->Acc0 done
  DEY                ; 3->2    2->1    1->0    0->-1
  BPL @lp            ; -> loop until Y<0
@done:
  LDY B              ; restore Y
  JMP tokenize       ; -> ALWAYS

tok_ovf:
  LDY #<msg_rng      ; [2] #RNG
  JMP err_rep        ; [3] -> report error

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

; @@ tok_emit
; emit an opcode at Emit,X and advance EmitOfs.
tok_emit:            ; (uses X; preserves A,Y -> NE,PL)
  LDX EmitOfs        ; [3] get emit offset
  STA EmitBuf,X      ; [5] emit token
  INC EmitOfs        ; [5] advance emit offset (NE)
  BMI tok_ovf        ; [2] -> overflowed emit buffer [+1] -> MI
  RTS                ; [6] -> NE,PL,X=EmitOfs-1 (for emit_str)

; @@ match_kws
; find matching keyword, terminated by a byte with top-bit set.
; if no match, continue until bit 6 is set.
match_kws:       ; Y=ofs, A=kw_ofs -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  STY B          ; [3] save start of input
  TAX            ; [2] starting kw_ofs
  BEQ @next_kw   ; [3] -> start
@match_lp:
  INY            ; [2] pre-increment input position
  INX            ; [2] pre-increment keyword position
@next_kw:
  LDA kw_pg,X    ; [4] next keyword char
  BMI @found     ; [2] -> matched keyword (top bit set) [+1] (MUST check LDA flags not CMP flags)
  CMP LineBuf,Y  ; [4] does it match input?
  BEQ @match_lp  ; [2] -> yes, next char [+1]
; no match, skip rest of keyword (find top-bit)
@skip_lp:
  INX            ; [2] find end of this keyword
  LDA kw_pg,X    ; [4] check keyword byte
  BPL @skip_lp   ; [2] -> top bit clear, keep going [+1]
  INX            ; [2] advance to next keyword
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
; NewLen = EmitOfs + 4 (add header)
; IF replacing:
;   OldLen = existing Line Length
;   Ptr += OldLen (advance to end of line)
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
  ; NewLen = EmitOfs + 4 ; add line header
  JSR find_line     ; [6] find matching line (Args[0] -> Ptr, CS=found)
  BCS @replace      ; [2] -> replace line at Ptr
  ; insert line:
  ; cpy(To=Ptr+Ins,From=Ptr,Len=Top-From) to make room
  ; Top += Ins
@copyin:
  ; copy EmitBuf -> Ptr
  ; done

@replace:
  LDY #3            ; OP_LN, LnL, LnH, Len
  LDA (Ptr),Y       ; get line length (including header)
  STA B             ; save old line length

  ; get new line length, add header
  LDA EmitOfs       ; new line length
  SEC
  ADC #4            ; minus header
  CMP B             ; is new > old?
  BEQ @copyin       ; -> same length, copy it
  BCS @longer       ; -> new is longer
  ; shorter:
  ; cpyb(Ptr+NewLen,Ptr+
  @longer:

  LDA Ptr
  STA Src           ; Dst = Ptr
  CLC
  ADC B             ; add 
  LDA PtrH
  STA DstH
; JSR mcpy          ; from (Src) to (Dst) with XY=size (uses A,X,Y,F,Src,Dst)


; @@ del_line
; delete the program line at LineNo
del_line:
  ; XXX
  RTS


; ------------------------------------------------------------------------------
; PAGE 5 - Statement Tokens

ORG BasROM+$200
kw_pg:

; start-of-line
OP_EOP     = $80
OP_LN      = $81
; keywords
OP_CLS     = $82
OP_CALL    = $83
OP_CLEAR   = $84
OP_DATA    = $85
OP_DIM     = $86
OP_END     = $87
OP_FOR     = $88
OP_GOTO    = $89
OP_GOSUB   = $8A
OP_IF      = $8B
OP_INPUT   = $8C
OP_LET     = $8D
OP_LOAD    = $8E
OP_LIST    = $8F
OP_NEXT    = $90
OP_NEW     = $91
OP_PRINT   = $92
OP_POKE    = $93
OP_READ    = $94
OP_RESTORE = $95
OP_RETURN  = $96
OP_REM     = $97
OP_RUN     = $98
OP_SAVE    = $99
OP_TONE    = $9A
OP_NSTMT   = $9B     ; first non-stmt
; context keywords
OP_STEP    = $9B
OP_TO      = $9C
OP_THEN    = $9D
; unary operators (highest precedence, evaluated post-fix, right-associative!)
OP_NEG     = $9E     ; 6 unary negate `-` (replaces OP_SUB)
OP_NOT     = $9F     ; 6 unary NOT
; unary functions (high precedence, evaluated post-fix, right-associative!)
OP_AT      = $A0     ; 6 unary fn (arg,arg)
OP_KEY     = $A1     ; 6 unary fn (arg)
OP_PEEK    = $A2     ; 6 unary fn (arg)
OP_RND     = $A3     ; 6 unary fn ([arg])
; infix binary (from highest to lowest, left-associative)
OP_MUL     = $A4     ; 5 binary op  LSR for prec
OP_DIV     = $A5     ; 5 binary op
OP_ADD     = $A6     ; 4 binary op
OP_SUB     = $A7     ; 4 binary op
OP_EQ      = $A8     ; 3 binary `=`
OP_NE      = $A9     ; 3 binary
OP_LT      = $AA     ; 3 binary `<`
OP_LE      = $AB     ; 3 binary
OP_GT      = $AC     ; 3 binary `>`
OP_GE      = $AD     ; 3 binary
OP_AND     = $AE     ; 2 binary op
OP_OR      = $AF    ; 1 binary op
; open paren (lowest precedence)
OP_LPAR    = $B0     ; 0 open parenthesis (lowest [never forced to eval], skips apply phase, always pushed)
OP_RPAR    = $B1     ; 0 close parenthesis (lowest, forces all ops to eval up to OP_LPAR [which always stops eval])
; numbers (non-operator)
OP_I0      = $C0     ; 1-byte (OP_I0 + [0-9])
OP_INT2    = $CA     ; 2-byte (opc|int8)
OP_INT3    = $CB     ; 3-byte (opc|int16)

kws_at:
kws_a:
ex_at     DB "AT",       OP_AT       +$40
ex_and    DB "AND",      OP_AND      +0
kws_b:
kws_c:
kw_call   DB "CALL",     OP_CALL     +$40
kw_cls    DB "CLS",      OP_CLS      +0
kws_d:
kw_data   DB "DATA",     OP_DATA     +$40
kw_dim    DB "DIM",      OP_DIM      +0
kws_e:
kw_end    DB "END",      OP_END      +0
kws_f:
kw_for    DB "FOR",      OP_FOR      +0
kws_g:
kw_goto   DB "GOTO",     OP_GOTO     +$40
kw_gosub  DB "GOSUB",    OP_GOSUB    +0
kws_h:
kws_i:
kw_if     DB "IF",       OP_IF       +$40
kw_input  DB "INPUT",    OP_INPUT    +0
kws_j:
kws_k:
ex_key    DB "KEY",      OP_KEY      +0
kws_l:
kw_let    DB "LET",      OP_LET      +$40
kw_load   DB "LOAD",     OP_LOAD     +$40
kw_list   DB "LIST",     OP_LIST     +0
kws_m:
kws_n:
kw_next   DB "NEXT",     OP_NEXT     +$40
ex_not    DB "NOT",      OP_NOT      +$40
kw_new    DB "NEW",      OP_NEW      +0
kws_o:
ex_or     DB "OR",       OP_OR       +0
kws_p:
kw_print  DB "PRINT",    OP_PRINT    +$40
ex_peek   DB "PEEK",     OP_PEEK     +$40
kw_poke   DB "POKE",     OP_POKE     +0
kws_q:
kws_r:
ex_rnd    DB "RND",      OP_RND      +$40
kw_read   DB "READ",     OP_READ     +$40
kw_rest   DB "RESTORE",  OP_RESTORE  +$40
kw_retr   DB "RETURN",   OP_RETURN   +$40
kw_rem    DB "REM",      OP_REM      +$40
kw_run    DB "RUN",      OP_RUN      +0
kws_s:
ex_step   DB "STEP",     OP_STEP     +$40
kw_save   DB "SAVE",     OP_SAVE     +0
kws_t:
ex_to     DB "TO",       OP_TO       +$40
ex_then   DB "THEN",     OP_THEN     +$40
kw_tone   DB "TONE",     OP_TONE     +0
kws_u:
kws_v:
kws_w:
kws_x:
kws_y:
kws_z     DB 0,0         ; match_kws needs two

expr_ops:
ex_mul  DB "*",       OP_MUL    +$40     ; operator  42
ex_div  DB "/",       OP_DIV    +$40     ; operator  47
ex_add  DB "+",       OP_ADD    +$40     ; operator  43
ex_sub  DB "-",       OP_SUB    +$40     ; operator  45
ex_eq   DB "=",       OP_EQ     +$40     ; operator  61
ex_ne   DB "<>",      OP_NE     +$40     ; operator  60 62
ex_lt   DB "<",       OP_LT     +$40     ; operator  60
ex_le   DB "<=",      OP_LE     +$40     ; operator  60 61
ex_gt   DB ">",       OP_GT     +$40     ; operator  62
ex_ge   DB ">=",      OP_GE     +$40     ; operator  62 61
ex_lp   DB "(",       OP_LPAR   +$40     ; operator  40
ex_rp   DB ")",       OP_RPAR   +0       ; operator  41
        DB 0,0        ; match_kws needs two


; Keyword Index
kw_tab:
  DB (kws_a - kw_pg) ; @
  DB (kws_a - kw_pg) ; A
  DB (kws_b - kw_pg) ; B
  DB (kws_c - kw_pg) ; C
  DB (kws_d - kw_pg) ; D
  DB (kws_e - kw_pg) ; E
  DB (kws_f - kw_pg) ; F
  DB (kws_g - kw_pg) ; G
  DB (kws_h - kw_pg) ; H
  DB (kws_i - kw_pg) ; I
  DB (kws_j - kw_pg) ; J
  DB (kws_k - kw_pg) ; K
  DB (kws_l - kw_pg) ; L
  DB (kws_m - kw_pg) ; M
  DB (kws_n - kw_pg) ; N
  DB (kws_o - kw_pg) ; O
  DB (kws_p - kw_pg) ; P
  DB (kws_q - kw_pg) ; Q
  DB (kws_r - kw_pg) ; R
  DB (kws_s - kw_pg) ; S
  DB (kws_t - kw_pg) ; T
  DB (kws_u - kw_pg) ; U
  DB (kws_v - kw_pg) ; V
  DB (kws_w - kw_pg) ; W
  DB (kws_x - kw_pg) ; X
  DB (kws_y - kw_pg) ; Y
  DB (kws_z - kw_pg) ; Z


; Keyword Reverse Lookup
stmt_rev:                     ; [34] indices MUST match OPCODEs
  DB (kw_cls - kw_pg)     ; OP_CLS
  DB (kw_data - kw_pg)    ; OP_DATA
  DB (kw_dim - kw_pg)     ; OP_DIM
  DB (kw_end - kw_pg)     ; OP_END
  DB (kw_for - kw_pg)     ; OP_FOR
  DB (kw_goto - kw_pg)    ; OP_GOTO
  DB (kw_gosub - kw_pg)   ; OP_GOSUB
  DB (kw_if - kw_pg)      ; OP_IF
  DB (kw_input - kw_pg)   ; OP_INPUT
  DB (kw_let - kw_pg)     ; OP_LET
  DB (kw_load - kw_pg)    ; OP_LOAD
  DB (kw_list - kw_pg)    ; OP_LIST
  DB (kw_next - kw_pg)    ; OP_NEXT
  DB (kw_new - kw_pg)     ; OP_NEW
  DB (kw_print - kw_pg)   ; OP_PRINT
  DB (kw_poke - kw_pg)    ; OP_POKE
  DB (kw_read - kw_pg)    ; OP_READ
  DB (kw_rest - kw_pg)    ; OP_RESTORE
  DB (kw_retr - kw_pg)    ; OP_RETURN
  DB (kw_rem - kw_pg)     ; OP_REM
  DB (kw_run - kw_pg)     ; OP_RUN
  DB (kw_save - kw_pg)    ; OP_SAVE
  DB (kw_tone - kw_pg)    ; OP_TONE
  ; context keywords
  DB (ex_step - kw_pg)    ; OP_STEP
  DB (ex_to - kw_pg)      ; OP_TO
  DB (ex_then - kw_pg)    ; OP_THEN
  ; unary operators
  DB (ex_not - kw_pg)     ; OP_NOT
  DB (ex_sub - kw_pg)     ; OP_NEG
  ; unary functions
  DB (ex_at - kw_pg)      ; OP_AT
  DB (ex_key - kw_pg)     ; OP_KEY
  DB (ex_peek - kw_pg)    ; OP_PEEK
  DB (ex_rnd - kw_pg)     ; OP_RND
  ; infix binary
  DB (ex_mul - kw_pg)     ; OP_MUL
  DB (ex_div - kw_pg)     ; OP_DIV
  DB (ex_add - kw_pg)     ; OP_ADD
  DB (ex_sub - kw_pg)     ; OP_SUB
  DB (ex_eq - kw_pg)      ; OP_EQ
  DB (ex_ne - kw_pg)      ; OP_NE
  DB (ex_lt - kw_pg)      ; OP_LT
  DB (ex_le - kw_pg)      ; OP_LE
  DB (ex_gt - kw_pg)      ; OP_GT
  DB (ex_ge - kw_pg)      ; OP_GE
  DB (ex_and - kw_pg)     ; OP_AND
  DB (ex_or - kw_pg)      ; OP_OR
  ; open paren
  DB (ex_lp - kw_pg)      ; OP_LPAR
  DB (ex_rp - kw_pg)      ; OP_RPAR


; @@ Statement Dispatch
; jump table (30 entries)
stmt_l:
  DB <repl         ; OP_EOP
  DB <line         ; OP_LN
  DB <do_cls       ; OP_CLS
  DB <skip         ; OP_DATA
  DB <do_dim       ; OP_DIM
  DB <repl         ; OP_END
  DB <do_for       ; OP_FOR
  DB <goto         ; OP_GOTO
  DB <gosub        ; OP_GOSUB
  DB <ifs          ; OP_IF
  DB <input        ; OP_INPUT
  DB <let          ; OP_LET
  DB <do_load      ; OP_LOAD
  DB <list         ; OP_LIST
  DB <do_next      ; OP_NEXT
  DB <new          ; OP_NEW
  DB <do_print     ; OP_PRINT
  DB <poke         ; OP_POKE
  DB <read         ; OP_READ
  DB <resto        ; OP_RESTORE
  DB <do_return    ; OP_RETURN
  DB <skip         ; OP_REM
  DB <run          ; OP_RUN
  DB <save         ; OP_SAVE
  DB <do_tone      ; OP_TONE
stmt_h:
  DB >repl         ; OP_EOP
  DB >line         ; OP_LN
  DB >do_cls       ; OP_CLS
  DB >skip         ; OP_DATA
  DB >do_dim       ; OP_DIM
  DB >repl         ; OP_END
  DB >do_for       ; OP_FOR
  DB >goto         ; OP_GOTO
  DB >gosub        ; OP_GOSUB
  DB >ifs          ; OP_IF
  DB >input        ; OP_INPUT
  DB >let          ; OP_LET
  DB >do_load      ; OP_LOAD
  DB >list         ; OP_LIST
  DB >do_next      ; OP_NEXT
  DB >new          ; OP_NEW
  DB >do_print     ; OP_PRINT
  DB >poke         ; OP_POKE
  DB >read         ; OP_READ
  DB >resto        ; OP_RESTORE
  DB >do_return    ; OP_RETURN
  DB >skip         ; OP_REM
  DB >run          ; OP_RUN
  DB >save         ; OP_SAVE
  DB >do_tone      ; OP_TONE


; ------------------------------------------------------------------------------
; PAGE 5 - Commands

ALIGN 16

DB "CMD"

; @@ LIST
; display program listing
list    JSR expr          ; line number -> Args[0]  ; XXX expr   s? Then LDX #0
        JSR find_line     ; find matching line, or next (Args[0] -> Args[0])  ; pass X?
        LDA (CODE),Y      ; read code
        CMP #44           ; comma?
        BNE lsts          ; -> no, start listing
        INY               ; comma
        JSR expr          ; line number -> Args[1]
        JSR find_line     ; find matching line, or next (Args[1] -> Args[1]) -> X
lsts    LDY #0            ; skip OP_LINE
        LDA (CODE),Y      ; get LineL
        CMP #OP_EOP       ; end of program marker
        BEQ lstx          ; -> end of program (0)
        INY               ; skip OP
        INY               ; LnHi
        INY               ; LnLo
        INY               ; skip LineLen
        JSR num_print     ; print Args[ArgTop] (uses A,X)
        JSR wrsp          ; print space (A=char, uses A,X) preserves Y
lstx    JMP repl

save    JMP repl

new     JMP repl          ; -> back to REPL

; @@ set_prog
; set up to run BASIC statements (AX=ptr)
set_prog:
  STA CODEH         ; CODE page
  LDY #0            ; interpreter code offset
  STY CODE          ; CODE ofs
  STY Data          ; clear data pointer
  STY DataH         ; clear data pointer
  STY OpTop         ; clear operator stack
  STY ArgTop        ; clear args stack
  RTS


; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

ALIGN 16
DB "RUN"

; control frame tags
TAG_FOR    = $F0
TAG_GOSUB  = $F1

; variable tags
VT_NONE = 0
VT_NUM = $80
VT_STR = $81
VT_NUM_ARR = $82

        ; @@ OP_RUN
        ; start running the BASIC program
run     LDA TopPtr        ; reset free space
        STA FreePtr
        LDA TopPtrH
        STA FreePtrH
        LDA #0            ; clear vars (9b)
        LDX #75           ; ArrVars, IntVars, OpTop, ArgTop, Data, DataH, CODE
runc    STA ArrVars,X     ; clear
        DEX
        BPL runc          ; -> loop
        TAY               ; CODE offset = 0
        LDA #>BaseAdr     ; start of BASIC program
        STA CODEH         ; set CODE page
        BNE stmt          ; -> start

        ; IF expr THEN
ifs     JSR expr       ; condition
        LDA $00
        ORA $01
        BNE stmt       ; -> cond is true, next stmt
        ; +++ fall through: skip +++

        ; REM, DATA
        ; advance to end of line
skip    LDY #3          ; (OP_LN,LnL,LnH,>Len<)
        LDA (CODE),Y    ; get line length
        TAY             ; set Y = line length (NE)
        BNE stmt        ; -> OP_LINE / OP_EOP

        ; @@ OP_LINE
        ; start of line: fold Y into CODE.
line    TYA            ; [2] get accumulated Y
        LDY #3         ; [2] skip (LnL,LnH,Len)
        CLC            ; [2]
        ADC CODE       ; [3] add Y to CODE
        STA CODE       ; [3] update CODE
        BCC stmt       ; [2] -> no overflow [+1]
        INC CODEH      ; [5]
        ; +++ fall through to @@ stmt +++

        ; @@ stmt
        ; expect a statement token: jump to statement handler
        ; otherwise assume LET
stmt    LDA (CODE),Y    ; [5] load token
        INY             ; [2] advance CODE
        BPL let         ; [2] -> implied LET [+1]
        ; debug check [+4 cycles]
        CMP #OP_NSTMT   ; [2] check code
        BCS esyn0       ; [2] -> bad code
        ; token dispatch
        TAX             ; [2]
        LDA stmt_l,X    ; [4]
        STA Src         ; [3] PHA
        LDA stmt_h,X    ; [4]
        STA SrcH        ; [3] PHA
        JMP (Src)       ; [5] RTS // [30]

        ; OP_LET or implied
        ; assign VAR[$] = Expr
let     JSR findv       ; find [@-Z] var -> ofs
        PHA             ; save var ofs
        JSR expr        ; -> Args[0]
        PLA             ; pop var ofs
        JSR setv        ; assign Args[0]
        JMP stmt        ; -> next stmt

        ; assign Args[0] to var ofs (A)
setv    TAX             ; as index (10b)
        LDA $00         ; Args[0]
        STA IntVars,X   ; low byte
        LDA $01         ; 
        STA IntVars+1,X ; high byte
        RTS

        ; find [@-Z] var -> ofs (10b)
findv   LDA (CODE),Y    ; read code
        EOR #64         ; 64->0
        CMP #27         ; [@-Z]
        BCS esyn0       ; -> syntax error
        INY             ; var
        ASL             ; ofs = [@-Z] x 2
        RTS

        ; OP_GOTO
goto    JSR expr       ; -> Args[0]
goln    JSR find_line  ; find matching line (Args[0] -> Args[0], CS=found)
        BCC esyn0      ; -> not found
        LDA $00
        STA CODE
        LDA $01
        STA CODEH
        LDY #3         ; skip (LnL,LnH,Len)
        BNE stmt       ; always OP_LINE

        ; OP_GOSUB
gosub   JSR expr       ; -> Args[0]
        JSR push_code  ; save return CODE (frame)   XXX JSR'd can't PHA
        LDA #TAG_GOSUB ; 
        PHA            ; (frame)
        BNE goln       ; -> ALWAYS

        ; OP_RESTORE
        ; Find specified line, set Data (READ does most of the work)
resto   JSR expr        ; -> Args[0]
        JSR find_line   ; find matching line, or next (Args[0] -> Args[0])
        LDA $00
        STA Data        ; pointer to next data, low
        LDA $01
        STA DataH       ; pointer to next data, high
        JMP stmt   

esyn0   LDY #<msg_syn
        JMP report_err

        ; OP_READ
        ; Data always points into the program (start of program, last RESTORE, last READ)
        ; @lp if (Data) >= $80 we're at eol; find next DATA line
        ; read num at (Data), assign to var, advance Data -> @lp
rdnx    INY             ; comma (in Code)
read    JSR findv       ; find [@-Z] var (uses A) reads code -> ofs (10b)
        TAX             ; var ofs -> X
        STY D           ; save Y
        LDY #0          ; data ofs -> Y
        LDA (Data),Y    ; 
        BMI rdfd        ; -> find next DATA
        STA IntVars,X   ; low byte
        INY             ;
        LDA (Data),Y    ; 
        STA IntVars+1,X ; high byte
        INY             ;
        TYA             ; advance Data
        CLC             ;
        ADC Data        ; Data += Y
        STA Data        ;
        BCC rdnp        ; -> no page cross
        INC DataH       ; DataH += 1
rdnp    LDY D           ; restore Y = Code ofs
        LDA (CODE),Y    ; read code
        CMP #44         ; comma
        BEQ rdnx        ; -> next var
        JMP stmt        ; -> next stmt
rdfd    LDY D           ; find next DATA line
        ;;
        JMP stmt

        ; OP_INPUT
inpnx   INY             ; comma
input   JSR findv       ; find [@-Z] var (uses A) -> ofs
        PHA             ; PUSH var index
        STY B           ; save CODE ofs
inprt   LDA #$3F        ; '?'
        JSR wrch        ; write '?' (uses A,X,F,Src,Dst) preserves Y
        LDY B           ; restore CODE ofs (retry)
        JSR rdln        ; read input (uses A,X,Y,B,C) -> Y=length
        STY C           ; new CODE ofs
        LDY #0          ; Y = input ofs
        JSR num_u16     ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Acc/Src,Term/Dst)
        CPY #0          ; 
        BEQ inprt       ; -> no, retry
        LDY C           ; commit new CODE ofs
        PLA             ; POP var index
        JSR setv        ; assign Args[0] to var ofs (A)
        LDA (CODE),Y    ; read code
        CMP #44         ; comma
        BEQ inpnx       ; -> again



; DIM: expect VAR '(' DIM-expr ')'
;      add var to var-list;
;      allocate array memory at TOP or HEAP?
do_dim:
  ; find [@-G] array -> X
  ; check if DIM'd -> error
  ; expect '('
  JSR expr        ; -> dimension(s)
  ; size = multiply dims loop (x2)
  ; expect ')'
  ; set array ptr = Free
  ; Free += size
  JMP stmt        ; -> next stmt



; --- FOR, NEXT ---

; FOR: expect VAR; '='; expr 'TO' expr ['STEP' expr]
;      push FOR loop on control stack; save address;
;           jump to STMT loop
do_for:
  ; find [@-Z] variable -> A,X
  PHA             ; push VAR (frame)
  JSR expr        ; "FROM" expression -> Args
  LDA $00
  PHA
  LDA $01
  PHA
  JSR expr        ; "TO" expression -> Args
  LDA $02
  PHA
  LDA $03
  PHA
  LDA (CODE),Y    ; peek next byte
  CMP #OP_STEP    ; "STEP"?
  BEQ @step       ; -> handle "STEP"
  ; push 01 00
  LDA #1
  PHA
  LDA #0
  PHA
@cont:
  JSR push_code   ; save return CODE (uses A,Y -> Y=0)   XXX JSR'd can't PHA
  LDA #TAG_FOR    ;
  PHA             ; push "FOR" control tag
  JMP stmt        ; [3] -> next stmt
@step:
  INY             ; OP_STEP
  JSR expr        ; "STEP" expression -> Args
  LDA $04
  PHA
  LDA $05
  PHA
  BNE @cont       ; -> continue with FOR


; NEXT: optional VAR
;       scan control stack for matching FOR 'VAR' (same address);
;       add STEP to VAR;
;       compare VAR vs TO based on STEP sign;
;       continue -> restore CODE address -> jump to STMT loop
;       otherwise -> pop FOR frame -> jump to STMT loop
do_next:
  ; must be A-Z int var
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
  JMP stmt   
@nofor:
  LDY #<msg_for
  JMP report_err



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
  JMP stmt   



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
  JSR wrnl        ; newline at end of print (preserves Y)
@endsemi:
  JMP stmt        ; end of print (non-zero)
; tab to next field
@comma:
  LDA #9          ; tab: advance to next print zone (5 coumns x 8 spaces)
  ;; JSR wrctl       ; print $09 tab (uses A,X,Src,Dst,F) preserves Y
  BNE do_print    ; -> always (won't be zero), set comma mode
@semi:
  INC D           ; semi mode
  BNE @loop       ; -> always (won't be zero)
; numeric expression
@expr:
  BMI @strexp     ; -> string expr ($60)
  JSR expr        ; evaluate numeric expression (to stack)
  JSR num_print   ; print Args[ArgTop] (uses A,X) -> NewArgTop
  STX ArgTop      ; pop it
  JMP @loop       ; -> continue
; print a string literal ($20)
@strlit:
  ; print string literal
  JMP @loop       ; -> continue
; string expression
@strexp:
  ; print quoted string
  PLA
  TAY             ; string addr low
  PLA
  TAX             ; string addr high
  ; TODO ^ if this points to the var, deref again!
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  ; TODO decrement REFs in string?
  JMP @loop       ; -> continue
@nl
  JSR wrnl        ; write newline (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue


; --- LOAD ---

; LOAD <string>
do_load:
  ; if running -> do_run
  ; else -> repl
  JMP repl         ; -> back to REPL


e_syn1:
  LDY #<msg_syn
  JMP report_err


; --- POKE ---

; POKE expr_n ',' expr_n
;      write byte to memory
poke:
  JSR ex2_u16      ; stack: (Addr,Byte) <-  (XXX elide)
  LDA $02          ; byte to write
  LDX #0
  STA ($00,X)      ; write to memory
  JMP stmt   


; --- CLS ---

; CLS: clear the screen
do_cls:
  STY E            ; save CODE offset
  JSR cls          ; (uses A,X,Y)
  LDY E            ; restore CODE offset
  JMP stmt         ; -> next stmt


; --- TONE ---

do_tone:
  JSR ex2_u16      ; stack: (Pitch,Duration) <-
  ; XXX
  JMP stmt   


; --- VARIABLES ---

; @@ find_var
; find A-Z variable -> X
find_var:
  RTS


; --- HELPERS ---

; DB <m_num2  ; PLOT num, num             u16,u16          -> e_range (good enough)
; DB <m_num2  ; POKE num, num             u16,u8           -> e_range (or modulo)
; DB <m_num2  ; TONE num, num             u8,u8            -> e_range (or modulo)
; DB <m_numo2 ; LIST [num],[num]          [u16,u16]        -> e_range
; DB <m_chsx  ; LOAD str$ [num]           u16/u8
; DB <m_chsx  ; RUN str$ [num]            u16/u8
; DB <m_chsx  ; SAVE str$ [num]           u16/u8

e_range:
e_type:

m_comma:
  LDA (CODE),Y ; next byte
  CMP #44      ; is comma?
  BNE e_syn1   ; -> syntax error
  INY
m_ret:
  RTS

; @@ find_frame
; pop frames until TAG matches, report missing
find_frame:       ; A=Tag
  ; XXX caller frame is in the way...
  TSX
  RTS


; @@ push_code (helper)
; fold Y into CODE and push it on the stack
; advance to the next statement or line
push_code:        ; uses (A,Y) -> Y=0     XXX JSR'd can't PHA
  LDA CODE        ; 
  PHA             ; push CODE
  LDA CODEH       ; 
  PHA             ; push CODEH
  TYA             ;
  PHA             ; push Offset
  RTS             ; 


; @@ find_line
; find matching line (X=Arg) -> Ptr, CS=found
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



; @@ ex4_u16
; parse u16, u16, u16, u16
ex4_u16:
  JSR ex2_u16
  JSR m_comma
  ; +++ fall through +++

; @@ ex2_u16
; parse u16, u16
ex2_u16:
  JSR expr     ; -> Args
  JSR m_comma
  ; +++ fall through: expr    +++

; @@ expr   
; evaluate an expression
expr   :
  RTS


; ------------------------------------------------------------------------------
; Numerics

; @@ num_add
; add two 32-bit numbers on the stack (pushed BE->LE)
; [A3][A2][A1][A0][T3][T2][T1][T0][PCH][PCL]
; *** to use the stack, must JMP here (not JSR)
num_add:
  LDX ArgTop     ; [3] top of expr stack (full descending from $180)
  CLC            ; [2] no carry in              15
  LDA $104,X     ; [4] get Dst0
  ADC $100,X     ; [4] subtract Top0 $104-1
  STA $104,X     ; [5] set Dst0                +13
  LDA $105,X     ; [4] get Dst1
  ADC $101,X     ; [4] subtract Arg1 $105-2
  STA $105,X     ; [5] set Dst1                +13
  INX            ; [2] ArgTop += 2
  INX            ; [2]
  STX ArgTop     ; [3] pop the top expr        +11
  RTS            ; [6] // 60                    +6

; @@ num_sub
; subtract two 32-bit numbers on the stack (pushed BE->LE)
; [A3][A2][A1][A0][T3][T2][T1][T0][PCH][PCL]
; *** to use the stack, must JMP here (not JSR)
num_sub:         ; (uses A,X)
  LDX ArgTop     ; [3] top of expr stack (full descending from $180)
  SEC            ; [2] no carry in              15
  LDA $104,X     ; [4] get Dst0
  SBC $100,X     ; [4] subtract Top0 $104-1
  STA $104,X     ; [5] set Dst0                +13
  LDA $105,X     ; [4] get Dst1
  SBC $101,X     ; [4] subtract Arg1 $105-2
  STA $105,X     ; [5] set Dst1                +13
  INX            ; [2] ArgTop += 2
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
  ; XXX update this (Term stays const)
  JSR div_u16    ; [733] Acc=dividend, A=divisor -> Acc=quotient, A=remainder (uses A,X,B,Acc)
  ORA #48        ; [2] 0-9 -> '0'-'9'
  PHA            ; [3] pushes once or more
  LDA Acc0       ; [3]
  ORA Acc1       ; [3]
  BNE @loop      ; [2] -> until zero [+1]
  PLA            ; [4]
@print:
  JSR wrch       ; [X] print it (uses A,X,F,Src,Dst) preserves Y
  PLA            ; [4]
  BNE @print     ; [2] -> until sentinel [+1]
num_rt:
  RTS

; @@ num_u16
; parse an unsigned 16-bit number
num_u16:         ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Acc/Src,Term/Dst)
  LDA #0         ; [2]
  STA $00        ; [3] clear Args[0]
  STA $01        ; [3]
  DEY            ; [2] for pre-increment
@loop:           ; -> 14+76+25 [115]
  INY            ; [2] pre-increment
  LDA LineBuf,Y  ; [4] get next char
  EOR #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS num_rt     ; [2] >= 10 -> done [+1]
  TAX            ; [2] save digit 0-9
; multiply Acc by 10
  ASL Acc0       ; [5] Acc = Acc*2 (=Val*2)
  ROL Acc1       ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  LDA Acc0       ; [3] Term = Acc (=Val*2)
  STA Term0      ; [3]
  LDA Acc1       ; [3]
  STA Term1      ; [3]
  ASL Acc0       ; [5] Acc *= 2 (=Val*4)
  ROL Acc1       ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  ASL Acc0       ; [5] Acc *= 2 (=Val*8)
  ROL Acc1       ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  CLC            ; [2]
  TXA            ; [2] Acc += digit 0-9
  ADC Acc0       ; [3]
  BCC @noc       ; [2] -> no carry [+1]
  INC Acc1       ; [5]
  BEQ err_ovf    ; [2] -> unsigned overflow [+1]
@noc:
  ADC Term0      ; [3] Acc += Term (=Val*2)
  STA $00        ; [3] Args[0]
  LDA Acc1       ; [3]
  ADC Term1      ; [3]
  STA $01        ; [3]
  BCC @loop      ; [2] -> no overflow, continue [+1]
err_ovf:
  LDY #<msg_rng  ; [2] #RNG
  JMP report_err ; [3] -> report overflow



; ----------------------------------------------------------------------
; Integer Multiply / Divide

ALIGN 16
DB "MUL"

; @@ mul_u16
; multiply BCD = Acc * Term (24-bit)
mul_u16:         ; Acc=multiplier Term=multiplicand -> BC=product (uses A,X,B,C,Acc,Term)
  LDA #0         ; [2]
  STA B          ; [3] B partial product
  STA C          ; [3] C partial product
  LDX #24        ; [2] 24 bit multiplier
  CLC            ; [2] CF=0
@loop:
  BCS err_ovf    ; [2] -> overflow (multiplicand)
; shift multiplier right, test each bit in turn
  LSR Acc1       ; [5] 0 >> multiplier >> CF
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
  BCS err_ovf    ; [2] -> overflow
@skip:
; shift multiplicand left (×2) into next higher place
  ASL Term0      ; [2] CF << multiplicand << 0
  ROL Term1      ; [5] XX << multiplicand << CF
  DEX            ; [2]
  BNE @loop      ; [3] -> continue
  RTS            ; [6] -> BCD=product

; @@ div_u16
; divide Acc = Acc / Term remainder BCD (long-division method)
div_u16:         ; Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
  LDA #0         ; [2] remainder = 0
  STA B          ; [3] remainder = 0
  STA C          ; [3] remainder = 0
  LDX #16        ; [2] 16 bits
@loop:
; shift dividend bits left into remainder
  ASL Acc0       ; [5] CF << dividend << 0  (shift 0 into quotient by default)
  ROL Acc1       ; [5] CF << dividend << CF
  ROL B          ; [2] CF << remainder << CF
  ROL C          ; [2] XX << remainder << CF
; until remainder >= divisor
  LDA C          ; [3] high byte
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
; shift 1 into quotient (one times divisor found)
  INC Acc0       ; [5] quotient bit0 = 1 (shift quotient into Acc)
@next:
  DEX            ; [2]
  BNE @loop      ; [3] -> continue division
  RTS            ; [6] return


; @@ print
; print a string
print:            ; X=high Y=low (uses A,B,X,Y,Ptr,Src,Dst)
  STX PtrH        ; [3] pointer high
  STY Ptr         ; [3] pointer low
  LDY #0          ; [2] Y=0
  LDA (Ptr),Y     ; [5] load string length
  TAY             ; [2] Y=length
  BEQ @ret        ; [2] -> nothing to print [+1]
@lp:
  LDA (Ptr),Y     ; [5] fetch next char
  JSR wrch        ; [6] (uses A,X,B,Src,Dst preserves Y)
  DEY             ; [2] decrement length
  CPY #1          ; [2] at length byte?
  BNE @lp         ; [3] -> loop // 8 -> 13+16+8 = [37]
@ret:
  RTS             ; [6] 

ORG BasROM+$7FF
  DB 0
