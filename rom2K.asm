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

cls = $FD00
home = $FD12                           
tclr = $FD1F                           
cpyf = $FD29                           
rdln = $FD4B                           
wrnl = $FD81                           
wrch = $FD91                           
wrbs = $FDD2                           
prhx = $FDE1                           

; ------------------------------------------------------------------------------
; Zero Page $00-7F - BASIC WORKSPACE

; -- $00-1F BASIC Operator Stack (32 bytes)

OpStack  = $00    ; BASIC operator stack                          (used in RT / Direct)

LineNo   = $00    ; ALIAS Parsed line number                      (used in EDIT)
LineNoH  = $01    ; ALIAS Parsed line number                      (used in EDIT)

; -- $20-73 BASIC Variables (84 bytes)

IntVars  = $20    ; A-Z 26 x 16-bit variables (52)                (used in RT / Direct)
StrVars  = $54    ; A-H 8 x 16-bit pointers (16)
ArrVars  = $64    ; A-H 8 x 16-bit pointers (16)

; -- $74-7F BASIC Pointers (12 bytes)

OpTop    = $74    ; Top of OpStack (stack pointer)                (used in RT / Direct)
ArgTop   = $75    ; Top of ArgStack (stack pointer)               (used in RT / Direct)
TopPtr   = $76    ; TOP of BASIC program, start of variables      (used in RT / EDIT)
TopPtrH  = $77
FreePtr  = $78    ; FREE space at end of variables                (used in RT / Direct / EDIT)
FreePtrH = $79
HeapPtr  = $7A    ; bottom of string HEAP, descending             (used in RT / Direct / EDIT)
HeapPtrH = $7B
CODE     = $7C    ; BASIC code pointer (next instruction)         (used in RT / Direct)
CODEH    = $7D
Data     = $7E    ; BASIC data pointer (next DATA statement)      (used in RT)
DataH    = $7F    ; ALIAS (EmitOfs)

EmitPtch = $7E    ; ALIAS Data  - emit placeholder offset         (used in EDIT)
EmitOfs  = $7F    ; ALIAS DataH - emit offset for tokenized code  (used in EDIT)

; ------------------------------------------------------------------------------
; Zero Page $80-FF - OS WORKSPACE

; -- $80-BF Free (64)

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
  LDA #End4K        ; end of memory (page)
  STA MemSize       ; set size of memory (in pages)
  JSR cls           ; clear screen
repl:
  LDY #<msg_ok      ; [2] "OK"
  JSR err_wrn       ; [6] print it (uses A,X,Y)
  JSR rdln          ; [6] read command or BASIC statement
  ; using Ptr is compatible with VAL(A$)
  ; use the screen as the input buffer instead?
  ; costs 6 bytes, saves 7 bytes LineBuf addressing
  STY Ptr           ; [3] set input Ptr low ($00)
  INY               ; [2]
  STY PtrH          ; [3] set input Ptr high ($01)
  DEY               ; [2]
; parse the line
  JSR num_ln        ; check for number, CS=found
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
; Y = current LineBuf offset at (Ptr)
; A,X = temporaries

; emit a string literal
; MUST insert LEN prefix, otherwise runtime will need to count length
emit_str:
  LDA #OP_STR        ;
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
  LDY <msg_syn       ; #MIS
  BNE err_rep        ; -> report error

; @@ emit_let        (report syntax error for unknown keywords)
emit_let:            ; Y -> Y,EQ
  JSR emi_var        ; -> recognise and emit A-Z[$][(..)]
  JSR skip_spc       ; Y=ofs -> A,X=next-char (EQ if zero)
  CMP #61            ; is it `=`?
  BEQ tok_loop       ; -> valid LET stmt
tok_syn:             ; VAR was an unknown keyword, roll back?
  LDY #<msg_syn      ; report syntax error
  BNE report_err     ; -> unknown keyword

tok_colon:
  ; subsequent statement
  INY                ; consume `:`
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
  BEQ tok_colon      ; -> expect statement (XXX needs emit)
  LDA #<expr_ops     ; operator table
  LDX #>expr_page    ; stmt table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC tok_syn        ; -> syntax error
@emiop:
  AND #$BF           ; clear bit 6 ($40)
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y) -> PL
  BPL tok_loop       ; -> ALWAYS: continue
@fnvar:              ; FUNCTION/VAR (or ELSE inside IF body)
  TAX                ; A-Z as index
  LDA expr_kwi,X     ; look up KW offset (A-Z)
  LDX #>expr_page    ; expr table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCS @emiop         ; -> match, emit opcode (can be OP_ELSEX)
  JSR emi_var        ; -> recognise and emit VAR (expr context)
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

; @@ emit_num        (46b)
; assumes next char is digit
emit_num:
  JSR num_u16        ; from LineBuf,Y-> Y,Acc,CS=ovf (uses A,X,Term)
  BCS tok_ovf        ; -> overflow
  STY B              ; save Y
  LDY #2             ; OP_INT3 (+2) "extra +1" for BPL loop
  LDA Acc1           ;
  BNE @out           ; -> 2 bytes plus opcode
  DEY                ; OP_INT2 (+1)
  LDA Acc0           ;
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
  JMP tok_loop       ; -> ALWAYS

tok_ovf:
  LDY #<msg_rng      ; [2] #RNG
  JMP err_rep        ; [3] -> report error

; @@ emi_var
; copy VAR[$] to output (assumes 1st char is alpha)
emi_var:
  LDA LineBuf,Y    ; [4] next input char
  JSR tok_emit     ; [6] output byte (uses X=0; preserves A,Y; sets PL)
  INY              ; [2] advance input (assume match)
  LDA LineBuf,Y    ; [4] next input char
  CMP #36          ; [2] `$`
  BNE @done
  INY
  JSR tok_emit     ; [6] output byte (uses X=0; preserves A,Y; sets PL)
@done:
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

; @@ match_kws
; find matching keyword, terminated by a byte with top-bit set (8x,9x,Ax,Bx)
; if no match, continue until bit 6 is set (Cx,Dx,Ex,Fx)
; note: XA table cannot cross a page boundary (INC/DEC Src would wrap)
match_kws:       ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  STY B          ; [3] save start of input
  STA Src        ; [3] table-low (offset)
  STX SrcH       ; [3] table-high (page)
  LDX #0         ; [2] const X=0
  BEQ @next_kw   ; [3] -> start
@match_lp:
  INY            ; [2] pre-increment input position
  INC Src        ; [5] pre-increment keyword position
@next_kw:
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
; JSR mem_copy      ; from (Src) to (Dst) with XY=size (uses A,X,Y,F,Src,Dst)
@copyin:
  ; XXX


; @@ del_line
; delete the program line at LineNo
del_line:
  ; XXX
  RTS


; ------------------------------------------------------------------------------
; PAGE 5 - Statement Tokens

ORG BasROM+$200
stmt_page:
expr_page:


; $8x-9x more keywords to follow (same first letter) -$40
; $Cx-Dx last keyword in list (for this letter)      -0
; (ORA #$40 before emit -> $Cx-Dx for statements)

OP_LN      = $C0   ; start-of-line
OP_CLS     = $C1
OP_CLEAR   = $C3
OP_DATA    = $C4
OP_DIM     = $C5
OP_END     = $C7
OP_FOR     = $C8
OP_GOTO    = $C9
OP_GOSUB   = $CA
OP_IF      = $CB
OP_INPUT   = $CC
OP_LET     = $CD
OP_LOAD    = $CF
OP_LIST    = $D0
OP_NEXT    = $D1
OP_NEW     = $D2
OP_PRINT   = $D4
OP_POKE    = $D6
OP_READ    = $D7
OP_RESTORE = $D8
OP_RETURN  = $D9
OP_REM     = $DA
OP_RUN     = $DB
OP_TONE    = $DC
OP_SAVE    = $DD

kws_at:
kws_a:
kws_b:
kws_c:
kw_cls    DB "CLS",      OP_CLS    -0     ; bit 6 set for more ($C0)
kw_clear  DB "CLEAR",    OP_CLEAR  -$40   ; bit 6 clear to end ($C0-$40)
kws_d:
kw_data   DB "DATA",     OP_DATA   -0
kw_dim    DB "DIM",      OP_DIM    -$40
kws_e:
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
kw_load   DB "LOAD",     OP_LOAD   -0
kw_list   DB "LIST",     OP_LIST   -$40
kws_m:
kws_n:
kw_next   DB "NEXT",     OP_NEXT   -0
kw_new    DB "NEW",      OP_NEW    -$40
kws_o:
kws_p:
kw_print  DB "PRINT",    OP_PRINT  -0     ; [#ch,]
kw_poke   DB "POKE",     OP_POKE   -$40
kws_q:
kws_r:
kw_read   DB "READ",     OP_READ     -0
kw_rest   DB "RESTORE",  OP_RESTORE  -0
kw_retr   DB "RETURN",   OP_RETURN   -0
kw_rem    DB "REM",      OP_REM      -0
kw_run    DB "RUN",      OP_RUN      -$40
kws_s:
kw_save   DB "SAVE",     OP_SAVE     -0
kws_t:
kw_tone   DB "TONE",     OP_TONE     -0
kws_u:
kws_v:
kws_w:
kws_x:
kws_y:
kws_z     DB 0,0         ; match_kws needs two

; EXPRESSION TOKENS

; numbers (non-operator)
OP_I0    = $80     ; 1-byte (OP_I0 + [0-9])
OP_INT2  = $8A     ; 2-byte (opc|int8)
OP_INT3  = $8B     ; 3-byte (opc|int16)
; strings (non-operator)
OP_STR   = $91     ; string literal
; unary operators (highest precedence, evaluated post-fix, right-associative!)
OP_NEG   = $92     ; 6 unary negate `-` (replaces OP_SUB)
OP_NOT   = $93     ; 6 unary NOT
; unary functions (high precedence, evaluated post-fix, right-associative!)
OP_ABS   = $94     ; 6 unary fn (arg)
OP_ASC   = $95     ; 6 unary fn (arg$)
OP_CHR   = $96     ; 6 unary fn (arg)
OP_KEY   = $99     ; 6 unary fn (arg)
OP_LEN   = $9A     ; 6 unary fn (arg$)
OP_PEEK  = $9B     ; 6 unary fn (arg)
OP_STR   = $9C     ; 6 unary fn (arg)
OP_MID   = $9E     ; 6 unary fn (arg$, arg, [arg])
OP_USR   = $A1     ; 6 unary fn (arg)
OP_VAL   = $A2     ; 6 unary fn (arg$)
OP_RND   = $A3     ; 6 unary fn ([arg])
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
OP_STEP  = $BC     ; FOR stmt
OP_TO    = $BD     ; FOR stmt
OP_THEN  = $BE     ; IF stmt

expr_a:
ex_asc  DB "ASC",     OP_ASC    +$40     ; fn (0,1)  bit 6 clear to end ($80)
ex_and  DB "AND",     OP_AND    +0       ; binary op
expr_b:
expr_c:
ex_chr  DB "CHR$",    OP_CHR    +0       ; fn$ (1,1)
expr_d:
expr_e:
expr_f:
expr_g:
expr_h:
expr_i:
expr_j:
expr_k:
ex_key  DB "KEY",     OP_KEY    +0       ; KEY(n) key down test
expr_l:
ex_len  DB "LEN",     OP_LEN    +0       ; fn-or-fn# (B,1) 1st is $
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
ex_rnd  DB "RND",     OP_RND    +0       ; fn (0,1)
expr_s:
ex_str  DB "STR$",    OP_STR    +$40     ; fn$ (1,1) 1st is $
ex_step DB "STEP",    OP_STEP   +0       ; `FOR` keyword
expr_t:
ex_to   DB "TO",      OP_TO     +$40     ; `FOR` keyword
ex_then DB "THEN",    OP_THEN   +$40     ; `IF` keyword
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

; Statement Reverse Lookup
stmt_rev:                     ; [34] indices MUST match OPCODEs
  DB (kw_cls - stmt_page)     ; OP_CLS
  DB (kw_clear - stmt_page)   ; OP_CLEAR
  DB (kw_data - stmt_page)    ; OP_DATA
  DB (kw_dim - stmt_page)     ; OP_DIM
  DB (kw_end - stmt_page)     ; OP_END
  DB (kw_for - stmt_page)     ; OP_FOR
  DB (kw_goto - stmt_page)    ; OP_GOTO
  DB (kw_gosub - stmt_page)   ; OP_GOSUB
  DB (kw_if - stmt_page)      ; OP_IF
  DB (kw_input - stmt_page)   ; OP_INPUT
  DB (kw_let - stmt_page)     ; OP_LET
  DB (kw_load - stmt_page)    ; OP_LOAD
  DB (kw_list - stmt_page)    ; OP_LIST
  DB (kw_next - stmt_page)    ; OP_NEXT
  DB (kw_new - stmt_page)     ; OP_NEW
  DB (kw_print - stmt_page)   ; OP_PRINT
  DB (kw_poke - stmt_page)    ; OP_POKE
  DB (kw_read - stmt_page)    ; OP_READ
  DB (kw_rest - stmt_page)    ; OP_RESTORE
  DB (kw_retr - stmt_page)    ; OP_RETURN
  DB (kw_rem - stmt_page)     ; OP_REM
  DB (kw_run - stmt_page)     ; OP_RUN
  DB (kw_save - stmt_page)    ; OP_SAVE
  DB (kw_tone - stmt_page)    ; OP_TONE


; Expression Index (starts at $3F9)
expr_kwi:
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

; Expression Reverse Lookup
expr_rev:                  ; 
  DB (ex_asc - expr_page)  ; OP_ASC
  DB (ex_chr - expr_page)  ; OP_CHR
  DB (ex_key - expr_page)  ; OP_KEY
  DB (ex_len - expr_page)  ; OP_LEN
  DB (ex_mid - expr_page)  ; OP_MID
  DB (ex_peek - expr_page) ; OP_PEEK
  DB (ex_rnd - expr_page)  ; OP_RND
  DB (ex_str - expr_page)  ; OP_STR
  DB (ex_usr - expr_page)  ; OP_USR
  DB (ex_val - expr_page)  ; OP_VAL
  ; operators
  DB (ex_and - expr_page)  ; OP_AND   operator
  DB (ex_not - expr_page)  ; OP_NOT   operator
  DB (ex_or - expr_page)   ; OP_OR    operator
  ; keywords
  DB (ex_step - expr_page) ; OP_STEP  keyword
  DB (ex_to - expr_page)   ; OP_TO    keyword
  DB (ex_then - expr_page) ; OP_THEN  keyword
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
  DB <do_clear     ; OP_CLEAR   = $C3
  DB <do_data      ; OP_DATA    = $C4
  DB <do_dim       ; OP_DIM     = $C5
  DB <repl         ; OP_END     = $C7
  DB <do_for       ; OP_FOR     = $C8
  DB <do_goto      ; OP_GOTO    = $C9
  DB <do_gosub     ; OP_GOSUB   = $CA
  DB <do_if        ; OP_IF      = $CB
  DB <do_input     ; OP_INPUT   = $CC
  DB <do_let       ; OP_LET     = $CD
  DB <do_load      ; OP_LOAD    = $CF
  DB <do_list      ; OP_LIST    = $D0
  DB <do_next      ; OP_NEXT    = $D1
  DB <do_new       ; OP_NEW     = $D2
  DB <do_print     ; OP_PRINT   = $D4
  DB <do_poke      ; OP_POKE    = $D6
  DB <do_read      ; OP_READ    = $D7
  DB <do_restore   ; OP_RESTORE = $D8
  DB <do_return    ; OP_RETURN  = $D9
  DB <do_rem       ; OP_REM     = $DA
  DB <do_run       ; OP_RUN     = $DB
  DB <do_tone      ; OP_TONE    = $DC
  DB <do_save      ; OP_SAVE    = $DD
stmt_h:
  DB >do_ln        ; OP_LN      = $C0
  DB >do_cls       ; OP_CLS     = $C1
  DB >do_clear     ; OP_CLEAR   = $C3
  DB >do_data      ; OP_DATA    = $C4
  DB >do_dim       ; OP_DIM     = $C5
  DB >repl         ; OP_END     = $C7
  DB >do_for       ; OP_FOR     = $C8
  DB >do_goto      ; OP_GOTO    = $C9
  DB >do_gosub     ; OP_GOSUB   = $CA
  DB >do_if        ; OP_IF      = $CB
  DB >do_input     ; OP_INPUT   = $CC
  DB >do_let       ; OP_LET     = $CD
  DB >do_load      ; OP_LOAD    = $CF
  DB >do_list      ; OP_LIST    = $D0
  DB >do_next      ; OP_NEXT    = $D1
  DB >do_new       ; OP_NEW     = $D2
  DB >do_print     ; OP_PRINT   = $D4
  DB >do_poke      ; OP_POKE    = $D6
  DB >do_read      ; OP_READ    = $D7
  DB >do_restore   ; OP_RESTORE = $D8
  DB >do_return    ; OP_RETURN  = $D9
  DB >do_rem       ; OP_REM     = $DA
  DB >do_run       ; OP_RUN     = $DB
  DB >do_tone      ; OP_TONE    = $DC
  DB >do_save      ; OP_SAVE    = $DD
stmt_chk = $DE



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



; ------------------------------------------------------------------------------
; PAGE 5 - Commands

ALIGN 16

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
  JSR num_print     ; print Acc01 (uses A,X)
  LDA #32           ; space
  JSR wrch          ; print char (A=char, uses A,X) preserves Y •••
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
  LDA #0
  LDX #51           ; clear 52-bytes IntVars (TODO: others)
@lp:
  STA IntVars,X     ; A=0
  DEX
  BPL @lp
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
  JSR find_var   ; [6] find A-Z variable at Y=ofs -> X
  AND #1         ; [2] num/str flag
  BNE @str       ; [2] -> str [+1]
  JSR do_expr_n  ; [6] evaluate numeric expression -> Acc
@scpy:
  LDA Acc0       ; [3] 
  STA (Ptr),Y    ; [6] write to Var0
  INY            ; [2]
  LDA Acc1       ; [3] 
  STA (Ptr),Y    ; [6] write to Var1
  LDY B          ; [3] restore Y=CodeOfs
  JMP do_stmt     ; -> next stmt
@str:
  JSR do_expr_s  ; [6] evaluate string expression -> Acc2E (StrPtr)
  JMP @scpy      ; [3] -> copy str ptr to slot


; DIM: expect VAR '(' DIM-expr ')'
;      add var to var-list;
;      allocate array memory at TOP or HEAP?
do_dim:
  LDA #VT_NUM_ARR ; variable tag
  JSR find_var    ; find A-Z variable at Y=ofs -> X
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
  JSR find_var    ; find A-Z variable at Y=ofs -> X
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
  JMP do_stmt
@nofor:
  LDY #<msg_for
  JMP report_err


; --- IF ---

; IF: parse BOOL-EXPR,
;     optional THEN kw,
;     if expr is true:
;        jump to STMT loop
;     if expr is false:
;        advance CODE to end of line
;        jump to STMT loop
do_if:
  JSR do_expr_b  ; [12+] numeric expr (uses A,X,Y,???)
  BCC do_eol     ; [2] -> cond is false, advance to end of line [+1]
  JMP do_stmt    ; [3] -> next stmt


; REM, DATA, ELSE
; advance to end of line (look up line length, add to CODE)
do_rem:
do_data:
do_eol:
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
  JSR find_var    ; find A-Z variable at Y=ofs -> X
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
  JSR wrch        ; ; print '?' (uses A,X,F,Src,Dst) preserves Y
@readln:
  ; TODO bind VAR
  ; TODO store str/num flag
  JSR rdln        ; read input (uses A,X,Y,B,C) -> Y=length (EQ if zero)
  ; TODO parse number
  ; TODO set var
  JMP @loop       ; -> continue
@nl:
  JSR wrnl        ; write newline (uses A,X,Src,Dst,F) preserves Y
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
  JSR wrnl        ; newline at end of print (preserves Y)
@endsemi:
  JMP do_stmt     ; end of print (non-zero)
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
  JSR wrnl        ; write newline (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue


; --- LOAD ---

; LOAD <expr_s>
do_load:
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
  JSR cls          ; (uses A,X,Y)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt


; --- TONE ---

do_tone:
  JSR ex2_u16      ; stack: (Pitch,Duration) <-
  ; XXX
  JMP do_stmt


; --- VARIABLES ---

; @@ find_var
; find A-Z variable -> X
find_var:
  RTS

do_syn1:
  LDY #<msg_syn
  JMP report_err


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
  BNE do_syn1  ; -> syntax error
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
  RTS

; @@ num_ln
; tokenize a line number (0-65535)
num_ln:          ; Y=ofs (uses A,X,B,Term) -> Acc,Y,CS=found
  JSR skip_spc   ; Y=ofs -> A,X=next-char (EQ if zero)
  STY B          ; save ofs
  JSR num_u16    ; from LineBuf,Y -> Acc,Y=end (uses A,X,Y,Acc,Term,Ptr)
  CPY B          ; number found?
  BEQ @nom       ; -> no match
  LDA Acc1       ; number is negative?
  BMI num_range  ; -> negative
  SEC            ; CS=found
  RTS
@nom:
  CLC            ; CC=not-found
  RTS

num_range:
  LDY #<msg_rng  ; #RNG
  JMP err_rep    ; -> report error

; @@ num_val
; parse a 16-bit number with optional sign prefix (TODO: floating point) (TODO: from (Ptr),Y ?)
num_val:         ; from LineBuf,Y -> Y,Acc (uses A,B,X,Term)
  JSR skip_spc   ; [6] Y=ofs -> A,X=next-char (EQ if zero)
  CMP #$2D       ; [2] `-`
  BEQ @minus     ; [2] -> negative [+1]
  JMP num_u16    ; [6] -> (Src),Y -> Acc,Y (uses A,X,Term)
@minus:
  INY            ; [2] skip `-`
  JSR num_u16    ; [6] -> (Src),Y -> Acc,Y (uses A,X,Term)
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
  BCC err_ovf    ; [2] -> overflow (Acc >= 2^23)
num_done:
  RTS

; @@ num_u16
; parse an unsigned 16-bit number
num_u16:         ; from LineBuf,Y -> Acc,Y=end (uses A,X,Acc,Term)
  LDA #0         ; [2]
  STA Acc0       ; [3] clear result
  STA Acc1       ; [3]
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
  CLC            ; [2] Acc += digit 0-9
  TXA            ; [2]
  ADC Acc0       ; [3]
  BCC @noc       ; [2] -> no carry [+1]
  INC Acc1       ; [5]
  BEQ err_ovf    ; [2] -> unsigned overflow [+1]
@noc:
  ADC Term0      ; [3] Acc += Term (=Val*10)
  STA Acc0       ; [3]
  LDA Acc1       ; [3]
  ADC Term1      ; [3]
  STA Acc1       ; [3]
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
mul_u16:         ; Acc=multiplier Term=multiplicand -> BCD=product (uses A,X,B,C,D)
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
div_u16:         ; Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,Acc)
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
; write a length-prefix string to the screen
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

