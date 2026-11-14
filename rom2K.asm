; Frontier 2K BASIC
; Use `asm6` to compile: https://github.com/parasyte/asm6

BasROM   = $0000

; ------------------------------------------------------------------------------
; Monitor Routines

rand  = $FDD6     ; random number in [1..Term] -> Acc (uses A,X,B,C,Acc,Term)
num16 = $FE0B     ; from LineBuf,Y -> Acc,Y,CS=found (uses A,X,Y,Acc/Src)
wrnum = $FE53     ; print Acc (uses A,X,B,C,F,Src,Dst)
mul16 = $FE72     ; Acc=multiplicand, Term=multiplier -> BC=product (uses A,X,B,C,Acc,Term)
div16 = $FE9A     ; Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
mcpy  = $FECB     ; (uses A,X,Y,F,Src,Dst)
cpyf  = $FEDC     ; (uses A,X,Y,F,Src,Dst) -> X=0
cpyb  = $FEFE     ; (uses A,X,Y,F,Src,Dst) -> Y=0
cls   = $FF23     ; (uses A,X,Y) -> Y=0,EQ
home  = $FF35     ; (uses A,Y) -> Y=0,EQ
tclr  = $FF42     ; (uses A,Y) -> Y=0,EQ
rdln  = $FF4C     ; (uses A,X,Y,F,Src,Dst) -> Y=len
wrnl  = $FF92     ; (uses A,X,F,Src,Dst) preserves Y
wrsp  = $FF9F     ; (uses A,X,F,Src,Dst) preserves Y
wrhx  = $FFA3     ; (uses A,X,F,Src,Dst) preserves Y
wrch  = $FFB7     ; (uses A,X,F,Src,Dst) preserves Y

; ------------------------------------------------------------------------------
; Zero Page

; -- $80-CF BASIC WORKSPACE (80 bytes)

EmitOfs  = $80        ; emit offset for tokenize (ALIAS)              (used in EDIT)
LnNoL    = $81        ; line number low for tokenize (ALIAS)
LnNoH    = $82        ; line number high for tokenize (ALIAS)

Oprs     = $80        ; Ascending Empty Stack, OpTop (16)
OprsE    = $90        ; End of Stack

IVar     = $90        ; [@-Z] 27 x 16-bit variables ($36)             (used in RT / Direct)

OpTop    = $C6        ; Top of Oprs (stack pointer)                   (used in RT / Direct)
;xx      = $C7
CODE     = $C8        ; BASIC code pointer (next instruction)         (used in RT / Direct)
CODEH    = $C9        ;
TopL     = $CA        ; TOP of BASIC program
TopH     = $CB        ;
;xx      = $CC
;xx      = $CD
JmpOp    = $CE        ; JMP indirect ptr for operators
JmpOpH   = $CF

; -- $D0-DF Temporaries (16)

Src      = $D0        ; source pointer \ WRCH, CLS  [Term0]
SrcH     = $D1        ; source pointer |            [Term1]
Acc0     = Src        ; ALIAS: accumulator byte 0
Acc1     = SrcH       ; ALIAS: accumulator byte 1
Dst      = $D2        ; destn pointer  | WRCH, CLS  [Term0]
DstH     = $D3        ; destn pointer  /            [Term1]
Term0    = Dst        ; ALIAS: term byte 0
Term1    = DstH       ; ALIAS: term byte 1
Ptr      = $D4        ; statement pointer \ (safe to hold across exprs and IO)
PtrH     = $D5        ; statement pointer /
B        = $D6        ; extra register \ Subroutines annotated with usage.
C        = $D7        ; extra register | Safe to hold across calls only when
D        = $D8        ; extra register / unused by callee (manually tracked)
E        = $D9        ; statement register (safe to hold across exprs and IO)
F        = $DA        ; IO Temp register (all IO, cpyf/cpyb, scratch use)
;xx      = $DB
;xx      = $DC
;xx      = $DD
;xx      = $DE
SChk     = $DF

; -- $E0-EF System Vars (16)

TXTP     = $E0        ; text write address
TXTPH    = $E1        ; text write address high
RemX     = $E2        ; remaining space on line
CurTime  = $E3        ; cursor flash timer
RNGL     = $E4        ; RNG state (LFSR)
RNGH     = $E5        ; 
;xx      = $E6
MemSz    = $E7        ; detected memory size in pages

IRQTmp   = $E8        ; Temp for IRQ handler
IRQTm2   = $E9        ; Temp for IRQ handler
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


; ------------------------------------------------------------------------------
; PAGE ONE $100-1FF - STACK

LineBuf  = $101    ; Input Buffer (79 bytes $101-150, leaves 47 bytes stack)
EmitBuf  = $101    ; Emit Buffer (79 bytes $101-150)


; ------------------------------------------------------------------------------
; PAGE 0 - REPL

ORG BasROM                ; 128 bytes at $0000

        SEI               ; disable interrupts
        CLD               ; disable BCD mode
        ; initialise BASIC
        JSR cls           ; clear screen
        JMP new           ; init program -> jumps to repl
        ; return to repl
        ; reset the stack, errors jump out of subroutines
repl    LDX #$7F          ; 128-byte stack
        TXS               ; set SP
        LDA #0            ; A = 0
        PHA               ; push 0 (TAG_EMPTY at $FF)
        LDA #>xoppg       ; operator page
        STA JmpOpH        ; set ptr high
        LDA #62           ; `>`
        JSR wrch          ; (uses A,X,F,Src,Dst) preserves Y
        JSR rdln          ; (uses A,X,Y,F,Src,Dst) -> Y=len
        ; parse the line
        LDY #0            ; Line ofs = 0
        STY EmitOfs       ; reset
        JSR rdnum         ; from LineBuf,Y -> Acc,Y (uses A,X,Src)
        LDA Acc0          ; set LineNo
        STA LnNoL         ; 
        LDA Acc1          ; set LineNo
        STA LnNoH         ; 
        STY D             ; line-no flag (NE=found)
        DEY               ; for INY
        ; tokenize the line
tkskp   INY               ; skip space
tokn    LDA LineBuf,Y     ; next input char
        BEQ tkeol         ; -> end of line
        CMP #32           ; space?
        BEQ tkskp         ; -> skip it
        STY B             ; save start-of-word
        ; match keywords
        LDX #$FF          ; offset (-1 for pre-inc)
        DEY               ; for pre-inc
tkmlp   INY               ; pre-increment input pos
tkmnx   INX               ; pre-increment keyword pos
        LDA kwpg,X        ; next keyword char
        BMI tkemt         ; -> found opcode, emit (bit 7 set)
        CMP LineBuf,Y     ; does it match input?
        BEQ tkmlp         ; -> yes, next char
        ; not a match
        LDY B             ; restore Y = start of word
        ASL               ; test keyword byte (d7=0)
        BEQ tkmno         ; -> DB 0, end of list
tkmsk   INX               ; find end of this keyword
        LDA kwpg,X        ; check keyword byte
        BPL tkmsk         ; -> top bit clear, keep going
        BMI tkmnx         ; -> next keyword (always)
        ; not a keyword
tkmno   JMP tknkw

tkemy   INY               ; advance input
tkemt   JSR tkemi         ; output token with top-bit set (uses X=0; preserves A,Y; sets PL)
        BPL tokn          ; -> ALWAYS

        ; end of line
tkeol   LDA D             ; line-no found?
        BEQ dcmd          ; -> no, direct command
        JMP insert        ; -> insert/replace line

        ; direct command
dcmd    LDA #OP_EOP       ; end of program
        JSR tkemi         ; terminate the line
        ;
;;        LDY #0            ; DEBUG
;;dbglp   LDA EmitBuf,Y     ; 
;;        JSR wrhx          ; saves Y
;;        JSR wrsp          ; saves Y
;;        INY
;;        CPY EmitOfs       ; emit length
;;        BCC dbglp         ; -> less, loop
;;        JSR wrnl          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        ; 
        LDA #>EmitBuf     ; page ($01)
        STA CODEH         ; set CODE page
        LDY #0            ; 
        STY CODE          ; set CODE ofs
        STY OpTop         ; clear operator stack
        STA (CODE),Y      ; direct-mode marker ($01 vs OP_LN/OP_EOP)
        INY               ; first opcode (EmitBuf=$101)
        JMP stmtj         ; -> execute statement (at Y=0)


ORG BasROM+$80            ; ensure < $80

; ------------------------------------------------------------------------------
; PAGE 1 - DCMD

ORG BasROM+$180           ; stack is $0100-017F

tknkw   LDA LineBuf,Y     ; reload input char
        CMP #34           ; "
        BEQ tkstr         ; -> String
        EOR #48           ; make '0' be 0
        CMP #10           ; 10 digits
        BCC tknum         ; -> emit number
        EOR #48           ; undo
tkstrx  JMP tkemy

        ; copy a string (23b)
tkstrl  CMP #34           ; is it `"`?
        BNE tkstr         ; -> no, loop (not a quote)
        ; found a quote
        CMP LineBuf+1,Y   ; is next char `"` ?
        BNE tkstrx        ; -> end of string, emit closing quote
        ; double-quote
        INY               ; first `"`
        JSR tkemi         ; emit `"` (uses X=0; preserves A,Y; sets PL)
tkstr   JSR tkemi         ; emit char (uses X=0; preserves A,Y; sets PL)
        INY               ; advance
        LDA LineBuf,Y     ; get next char
        BNE tkstrl        ; -> not end of line (else missing quote)
        JMP esyn          ; -> report error

        ; emit a number (45b)
tknum   JSR rdnum         ; from LineBuf,Y -> Acc,Y,CS=overflow (uses A,X,Src)
        STY B             ; save Y
        LDX #OP_INT2      ; OP_INT2
        LDY #2            ; 2 bytes
        LDA Acc1          ; high byte
        BNE tknmo         ; -> OP_INT2 + 2 bytes
        DEX               ; OP_INT1
        DEY               ; 1 byte
        LDA Acc0          ; low byte
        CMP #10           ; CS if >= 10
        BCS tknmo         ; -> OP_INT1 + 1 byte (CS)
        DEY               ; 0 bytes
        ORA #OP_I0        ; single-digit
        TAX               ;
tknmo   TXA               ; X=OP
tknlp   JSR tkemi         ; (uses X=0; preserves A,Y; PL)
        LDX Acc0-1,Y      ; 2=Acc1, 1=Acc0, 0=XX
        TXA               ; can't LDA zp,Y
        DEY               ; 2>1 1>0 0>FF
        BPL tknlp         ; -> until Y<0
        LDY B             ; restore Y
        JMP tokn          ; 

        ; emit code
        ; uses X; preserves A,Y -> NE,PL
tkemi   LDX EmitOfs       ; [3] get emit offset
        STA EmitBuf,X     ; [5] emit token
        INC EmitOfs       ; [5] advance emit offset (NE)
        BMI enumb         ; [2] -> buffer overflow [+1] -> MI
rkret   RTS               ; [6] -> NE,PL,X=EmitOfs-1 (for emit_str)

        ; read a number
rdnum   JSR num16         ; from LineBuf,Y -> Acc,Y,CS=overflow (uses A,X,Src)
        BCC rkret         ; -> no overflow
        ; +++ fall through: enumb +++

        ; report an error (Y=msg)
enumb   LDY #<msg_num-1   ; "?NUM"
        DB $2C            ; BIT abs
eesc    LDY #<msg_esc-1   ; "?ESC"                                          XXX detect ESCAPE !!
erro    LDA #63           ; `?`
errl    JSR wrch          ; write char (uses A,X,F,Src,Dst) preserves Y
        INY
errw    LDA msgs,Y        ; next char
        BPL errl          ; -> until $80/$C0
        ; report line no
        ASL               ; test bit 6
        BMI errno         ; -> $C0, print line number
        LDY #0            ; 
        LDA (CODE),Y      ; OP_LN / direct-mode marker
        BPL errx          ; -> direct mode, done
        INY
        LDA (CODE),Y      ; LnLo
        STA Acc0
        INY
        LDA (CODE),Y      ; LnHi
        STA Acc1
        LDY #<msg_at      ; " AT ",$C0
        BNE errw          ; -> always
errno   JSR wrnum         ; print line number
errx    JSR wrnl          ; crlf (uses A,X,F,Src,Dst) preserves Y
        JMP repl          ; -> always


; ------------------------------------------------------------------------------
; PAGE 1 - Statement Tokens

; start-of-line
OP_STMT    = $C0     ; * stmt base
OP_EOP     = $C0
OP_LN      = $C1
OP_EOL     = $C2     ; * use BCC
OP_COLN    = $C2
; keywords
OP_CLS     = $C3
OP_END     = $C4
OP_FOR     = $C5
OP_GOTO    = $C6
OP_GOSUB   = $C7
OP_IF      = $C8
OP_INPUT   = $C9
OP_LET     = $CA
OP_LOAD    = $CB
OP_LIST    = $CC
OP_NEXT    = $CD
OP_NEW     = $CE
OP_PRINT   = $CF
OP_POKE    = $D0
OP_RETURN  = $D1
OP_REM     = $D2
OP_RUN     = $D3
OP_SAVE    = $D4
OP_TONE    = $D5
OP_XSTMT   = $D6     ; * first non-stmt
; context keywords
OP_STEP    = $D6
OP_TO      = $D7
OP_THEN    = $D8
; unary operators (highest precedence, evaluated post-fix, right-associative)
OP_NPRE    = 6       ; * num prefix (excludes OP_NEG,OP_IDX)
OP_LPAR    = $80     ; 0 open parenthesis (lowest precedence, ends pop/apply -> xinf)
OP_ABS     = $81     ; 7 unary Minus (OP_SUB ORA #16 -> push)
OP_NOT     = $82     ; 7 unary NOT
OP_PEEK    = $83     ; 7 unary fn (arg)
OP_RND     = $84     ; 7 unary fn (arg)
OP_USR     = $85     ; 7 call user subroutine (at arg)
; unary specials
OP_NEG     = $86     ; 7 unary Minus (OP_SUB)
OP_IDX     = $87     ; 0 unary array (lowest precedence, ends pop/apply -> xinf)
; infix binary (from highest to lowest, left-associative)
OP_INFX    = $88     ; * first infix
OP_NIFX    = 12      ; * num infix (excludes OP_RPAR)
OP_MUL     = $88     ; 6 binary op  LSR for prec
OP_DIV     = $89     ; 6 binary op
OP_ADD     = $8A     ; 5 binary op
OP_SUB     = $8B     ; 5 binary op (maps to OP_NEG)
OP_EQ      = $8C     ; 4 binary `=`
OP_NE      = $8D     ; 4 binary `<>`
OP_LE      = $8E     ; 4 binary `<=`
OP_GE      = $8F     ; 4 binary `>=`
OP_LT      = $90     ; 4 binary `<`
OP_GT      = $91     ; 4 binary `>`
OP_AND     = $92     ; 3 binary op
OP_OR      = $93     ; 2 binary op
; infix specials
OP_RPAR    = $94     ; 0 infix close parenthesis (forces all ops to eval up to OP_LPAR/OP_IDX)
OP_SIZE    = $95     ; push size of @-array
; numbers (non-operator)
OP_I0      = $F0     ; 1-byte (OP_I0 + [0-9])
OP_I9      = $F9     ; 1-byte
OP_INT1    = $FA     ; 1-byte (opc|int8)
OP_INT2    = $FB     ; 2-byte (opc|int16)

kwpg:
ex_mul    DB "*",        OP_MUL
ex_div    DB "/",        OP_DIV
ex_add    DB "+",        OP_ADD
ex_sub    DB "-",        OP_SUB
ex_eq     DB "=",        OP_EQ
ex_ne     DB "<>",       OP_NE
ex_le     DB "<=",       OP_LE
ex_ge     DB ">=",       OP_GE
ex_lt     DB "<",        OP_LT
ex_gt     DB ">",        OP_GT
ex_lp     DB "(",        OP_LPAR
ex_rp     DB ")",        OP_RPAR
ex_co     DB ":",        OP_COLN
kw_let    DB "LET",      OP_LET
kw_print  DB "PRINT",    OP_PRINT
kw_if     DB "IF",       OP_IF
kw_for    DB "FOR",      OP_FOR
kw_next   DB "NEXT",     OP_NEXT
ex_to     DB "TO",       OP_TO
kw_gosub  DB "GOSUB",    OP_GOSUB
kw_retr   DB "RETURN",   OP_RETURN
kw_input  DB "INPUT",    OP_INPUT
kw_goto   DB "GOTO",     OP_GOTO
kw_cls    DB "CLS",      OP_CLS
kw_rem    DB "REM",      OP_REM
ex_rnd    DB "RND",      OP_RND
ex_abs    DB "ABS",      OP_ABS
ex_peek   DB "PEEK",     OP_PEEK
kw_poke   DB "POKE",     OP_POKE
kw_tone   DB "TONE",     OP_TONE
ex_and    DB "AND",      OP_AND
ex_or     DB "OR",       OP_OR
ex_not    DB "NOT",      OP_NOT
ex_step   DB "STEP",     OP_STEP
ex_then   DB "THEN",     OP_THEN
kw_end    DB "END",      OP_END
kw_list   DB "LIST",     OP_LIST
kw_run    DB "RUN",      OP_RUN
kw_new    DB "NEW",      OP_NEW
kw_load   DB "LOAD",     OP_LOAD
kw_save   DB "SAVE",     OP_SAVE
ex_usr    DB "USR",      OP_USR
          DB 0

msgs = BasROM+$200

msg_syn   DB "SYN",$80
msg_num   DB "NUM",$80
msg_big   DB "STK",$80
msg_esc   DB "ESC",$80
msg_at    DB " AT ",$80

; Keyword Reverse Lookup
kwrvs = kwrev - OP_EOL   ; includes `:`
kwrev:                   ; indices MUST match OPCODEs
  DB (ex_co - kwpg)      ; `:`
  DB (kw_cls - kwpg)     ; OP_CLS
  DB (kw_end - kwpg)     ; OP_END
  DB (kw_for - kwpg)     ; OP_FOR
  DB (kw_goto - kwpg)    ; OP_GOTO
  DB (kw_gosub - kwpg)   ; OP_GOSUB
  DB (kw_if - kwpg)      ; OP_IF
  DB (kw_input - kwpg)   ; OP_INPUT
  DB (kw_let - kwpg)     ; OP_LET
  DB (kw_load - kwpg)    ; OP_LOAD
  DB (kw_list - kwpg)    ; OP_LIST
  DB (kw_next - kwpg)    ; OP_NEXT
  DB (kw_new - kwpg)     ; OP_NEW
  DB (kw_print - kwpg)   ; OP_PRINT
  DB (kw_poke - kwpg)    ; OP_POKE
  DB (kw_retr - kwpg)    ; OP_RETURN
  DB (kw_rem - kwpg)     ; OP_REM
  DB (kw_run - kwpg)     ; OP_RUN
  DB (kw_save - kwpg)    ; OP_SAVE
  DB (kw_tone - kwpg)    ; OP_TONE
  ; context keywords
  DB (ex_step - kwpg)    ; OP_STEP
  DB (ex_to - kwpg)      ; OP_TO
  DB (ex_then - kwpg)    ; OP_THEN
  ; unary operators
  DB (ex_lp - kwpg)      ; OP_LPAR
  DB (ex_abs - kwpg)     ; OP_ABS
  DB (ex_not - kwpg)     ; OP_NOT
  DB (ex_peek - kwpg)    ; OP_PEEK
  DB (ex_rnd - kwpg)     ; OP_RND
  DB (ex_usr - kwpg)     ; OP_USR
  DB (ex_sub - kwpg)     ; OP_NEG
  DB (ex_lp - kwpg)      ; OP_IDX
  ; infix binary
  DB (ex_mul - kwpg)     ; OP_MUL
  DB (ex_div - kwpg)     ; OP_DIV
  DB (ex_add - kwpg)     ; OP_ADD
  DB (ex_sub - kwpg)     ; OP_SUB
  DB (ex_eq - kwpg)      ; OP_EQ
  DB (ex_ne - kwpg)      ; OP_NE
  DB (ex_lt - kwpg)      ; OP_LT
  DB (ex_le - kwpg)      ; OP_LE
  DB (ex_gt - kwpg)      ; OP_GT
  DB (ex_ge - kwpg)      ; OP_GE
  DB (ex_and - kwpg)     ; OP_AND
  DB (ex_or - kwpg)      ; OP_OR
  DB (ex_rp - kwpg)      ; OP_RPAR


; @@ Statement Dispatch
; jump table (30 entries)
stmtl = stml - OP_STMT
stmth = stmh - OP_STMT
stml    DB <repl         ; OP_EOP  (executed in direct mode)
        DB <esyn         ; OP_LN   (not a stmt)
        DB <esyn         ; OP_COLN (not a stmt)
        DB <clss         ; OP_CLS
        DB <repl         ; OP_END
        DB <for          ; OP_FOR
        DB <goto         ; OP_GOTO
        DB <gosub        ; OP_GOSUB
        DB <ifs          ; OP_IF
        DB <input        ; OP_INPUT
        DB <let          ; OP_LET
        DB <load         ; OP_LOAD
        DB <list         ; OP_LIST
        DB <next         ; OP_NEXT
        DB <new          ; OP_NEW
        DB <print        ; OP_PRINT
        DB <poke         ; OP_POKE
        DB <retn         ; OP_RETURN
        DB <skip         ; OP_REM
        DB <run          ; OP_RUN
        DB <save         ; OP_SAVE
        DB <tone         ; OP_TONE
stmh    DB >repl         ; OP_EOP
        DB >esyn         ; OP_LN
        DB >esyn         ; OP_COLN
        DB >clss         ; OP_CLS
        DB >repl         ; OP_END
        DB >for          ; OP_FOR
        DB >goto         ; OP_GOTO
        DB >gosub        ; OP_GOSUB
        DB >ifs          ; OP_IF
        DB >input        ; OP_INPUT
        DB >let          ; OP_LET
        DB >load         ; OP_LOAD
        DB >list         ; OP_LIST
        DB >next         ; OP_NEXT
        DB >new          ; OP_NEW
        DB >print        ; OP_PRINT
        DB >poke         ; OP_POKE
        DB >retn         ; OP_RETURN
        DB >skip         ; OP_REM
        DB >run          ; OP_RUN
        DB >save         ; OP_SAVE
        DB >tone         ; OP_TONE


; <<<<<
; insert line / replace line / delete line (NewLen=0)
; <<<<<
; NewLen += 4 if > 0               (add space for header)
; fndln LineNo -> Ptr/XA           (find start of LineNo/NextLn [insert point])
; save XA -> Src                   (code-above to move up/down)
; if found (CS), OldLen = (Src),3 else 0
; Src += OldLen                    (code-above src: end of LineNo or start of NextLn)
; Dst = Src + (NewLen - OldLen)    (code-above dest: move code by delta)
; Size = Top - Src                 (Size to move up/down)
; if Dst + Size > MemSz -> ?MEM    (Out of memory)
; Top = Dst + Size                 (update Top)
; JSR mcpy                         (from Src to Dst of Size, no-op if Src=Dst)
; if NewLen:
; copy from EmitBuf,Y to (Ptr),Y   (copy in new line)
; <<<<<
; store LineNo and EmitOfs at LineBuf,1-3 (and write OP_LN at 0)


insert  LDA EmitOfs       ; did we emit?  (9b)
        BEQ insnn         ; -> empty line
        CLC
        ADC #4            ; 4-byte line header
insnn   STA C             ; C = NewLen
        JSR fndln         ; find start of LineNo/NextLn [insert point] (Acc -> XA/Ptr)  (115b!)
        STA Src           ; Src = code-above to move up/down            (17b)
        STX SrcH
        ; if line found, get OldLen
        LDA #0            ; OldLen = 0
        LDY #3            ; 3rd byte
        BCC insno         ; -> line not found
        LDA (Src),Y       ; load length byte
insno   STA B             ; B = OldLen
        ; adjust Src: end of LineNo or start of NextLn                  (11b)
        CLC
        ADC Src           ; Src = Src + OldLen
        STA Src
        LDA #0
        ADC SrcH
        STA SrcH
        ; calculate Dst = Src + (NewLen - OldLen)                       (26b)
        SEC
        LDA C             ; C = NewLen [0..4e]
        SBC B             ; B = OldLen [0..4e]
        STA D             ; D = Signed Delta low [-4e..4e]
        LDA #0
        SBC #1            ; subtract 1 unless CC -> CS=FF CC=0  (CS=neutral CC=borrow)
        STA E             ; E = Signed Delta high
        CLC
        LDA Src           ; Dst = Src + Delta
        ADC D             ; D = Delta low
        STA Dst
        LDA SrcH
        ADC E             ; E = Delta high
        STA DstH
        ; calculate size to move: Size = Top - Src                      (13b)
        SEC
        LDA TopL
        SBC Src
        STA D             ; D = Size low
        LDA TopH
        SBC SrcH
        STA E             ; E = Size high
        ; check if Dst + Size > MemSz                                   (14b)
        CLC
        LDA Dst
        ADC D             ; D = Size low
        TAX
        LDA DstH
        ADC E             ; E = Size high
        CMP MemSz
        BCS emem          ; -> out of memory
        ; update Top = Dst + Size
        STA TopH
        STX TopL
        ; copy memory from Src to Dst of Size (no-op if Src=Dst)        (7b)
        LDX E             ; E = Size high
        LDY D             ; D = Size low
        JSR mcpy          ; XY=size (uses A,X,Y,F,Src,Dst)
        ; insert the new line, unless empty                             (16b)
        LDY C             ; C = NewLen [0..4e]
        BEQ insx          ; -> empty, done
        DEY
inscp   LDA EmitBuf,Y     ; copy from EmitBuf,Y to (Ptr),Y
        STA (Ptr),Y       ; Ptr = insert point
        DEY
        BPL inscp         ; until Y<0
insx    JMP repl          ; -> done

emem    LDY #<msg_big-1   ;                                             (5b)
        JMP erro


        ; OP_LIST         (80b)
list    JSR expr          ; line number -> Acc/XA
        JSR fndln         ; find matching line, or next (Acc -> XA/Ptr)
        ; line number
lstln   LDY #2            ; Y=2
        LDA (Ptr),Y       ; (OP LnLo >LnHi< Len)
        BMI lstx          ; -> end of program (negative line number)
        STA Acc0
        DEY               ; Y=1
        LDA (Ptr),Y       ; (OP LnLo >LnHi< Len)
        STA Acc1
        JSR wrnum         ; print Acc (uses A,X,B,C,F,Src,Dst)
        JSR wrsp          ; print space (uses A,X,F,Src,Dst) preserves Y
        LDY #4            ; skip header
        ; line contents
lstco   LDA (Ptr),Y       ; next byte
        BPL lstch         ; -> char
        CMP #OP_EOL       ; end of line?                         ASSUMES: BMI and <OP_EOL means EOL
        BCC lstnx         ; -> next line
        ; print token                                            XXX bad token check?
        STY B             ; save line ofs
        TAX               ; as index
        LDY kwrvs,X       ; look up token offset (-1)            XXX now split $80/$C0, also $F0 numbers..
        LDA #32           ; space before token
lsttk   JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
        INY               ; advance
        LDA kwpg,Y        ; next char
        BPL lsttk         ; -> more
        LDY B             ; restore line ofs
        LDA #32           ; space after token
        ; print char
lstch   JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
        JMP lstco         ; -> continue
        ; next line
lstnx   JSR wrnl          ; crlf (uses A,X,F,Src,Dst) preserves Y
        TYA               ; get accumulated Y
        CLC               ; thanks crlf
        ADC Ptr           ; add Y to Ptr
        STA Ptr           ; update Ptr
        BCC lstln         ; -> no page cross
        INC PtrH          ;
        BNE lstln         ; -> always
        ; done
lstx    JMP repl

        ; OP_SAVE
save    JMP repl          ;                                   XXX need SAVE !!!


; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

; control frame tags
TAG_FOR    = $F0
TAG_GOSUB  = $F1

        ; OP_NEW
        ; sets up a new program at ProgPg ($0A00)
        ; above the BASIC interpreter
        ; drops into RUN to reset all BASIC state
new     LDA #>ProgPg      ; set top of program
        STA TopH
        LDA #<ProgPg+4    ; (OP_EOP LnLo LhHi Len)
        STA TopL
        LDA #OP_EOP       ; end of program ($C0)
        STA ProgPg        ; OP_EOP
        STA ProgPg+1      ; negative line number (EOP mark)
        STA ProgPg+2      ; $C0C0
        LDA #0
        STA ProgPg+3      ; zero length (EOP mark)
        ; +++ fall through: run empty program +++

        ; OP_RUN
        ; start running the BASIC program
        ; clear all variables, reset BASIC stacks, set CODE
run     LDA #0            ; clear vars (9b)
        LDX #CODE-IVar    ; IVar(54),OpTop(1)
runcl   STA IVar,X        ; clear zp,X
        DEX
        BNE runcl         ; -> loop
        TAY               ; CODE offset = 0
        LDA #>ProgPg      ; start of BASIC program (NE)
        STA CODEH         ; set CODE page
        LDA #<ProgPg      ; (OP_EOP LnLo LhHi Len)
        STA CODE          ; set CODE ofs
        JMP colon         ; -> expect OP_LN/OP_EOP (Y=0)


        ; OP_REM
        ; advance to end of line
skip    LDY #3            ; (OP_LN,LnL,LnH,>Len<)
        LDA (CODE),Y      ; get line length
        TAY               ; set Y = line length (NE)
        ; +++ fall through: colon +++

        ; expect `:` or OP_LN / OP_EOP
colon   LDA (CODE),Y      ; [5] read code
        CMP #OP_COLN      ; [2] is it `:`?
        BEQ stmtc         ; [2] -> next stmt [+1]
        CMP #OP_LN        ; [2] is it OP_LN?
        BEQ line
        ;; BNE eolx          ; [2] -> no [+1]
        CMP #OP_EOP       ; end of program?
        BEQ lstx          ; -> back to REPL
        JMP esyn          ; -> syntax error

        ; +++ fall through: line (Y=OP_LN) +++

        ; start of line: advance CODE by Y
line    TYA               ; [2] get accumulated Y
        LDY #3            ; [2] skip 4 (OP_LN,LnL,LnH,Len,><) +1 from stmtc
        CLC               ; [2]
        ADC CODE          ; [3] add Y to CODE (points at OP_LN)
        STA CODE          ; [3] update CODE
        BCC stmtc         ; [2] -> no page cross [+1] // [15]
        INC CODEH         ; [5]
        ; +++ fall through: stmtc +++

        ; STMT dispatch
stmtc   INY               ; [2] skip `:`
stmtj   LDA (CODE),Y      ; [5] read code
;;        PHA               ; DEBUG
;;        JSR wrhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
;;        JSR wrnl          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
;;        PLA               ; DEBUG
        BPL let           ; [2] -> implied LET [+1]
        INY               ; [2] advance code
        ; guard [+4 cycles]
        CMP #OP_XSTMT     ; [2] non-statement?
        BCS esyn          ; [2] -> bad code
        ; token dispatch
        TAX               ; [2]
        LDA stmtl,X       ; [4]
        STA Ptr           ; [3] PHA
        LDA stmth,X       ; [4]
        STA PtrH          ; [3] PHA
        JMP (Ptr)         ; [5] RTS // [34] [colon +15]


        ; OP_LET or implied
        ; assign VAR = Expr
let     JSR findv         ; find [@-Z] var -> ofs (A)
        BEQ leta          ; -> array
        PHA               ; push var ofs
        JSR eqexp         ; `=` expr -> Acc/XA
        PLA               ; pop var ofs
        JSR setv          ; assign Acc to var (ofs=A)
        JMP colon         ; -> colon


        ; OP_IF
        ; evaluate condition, skip rest of line if false
        ; if true, check for implied GOTO (line number)
ifs     JSR expr          ; condition -> Acc/XA
        ORA Acc1          ; test Acc
        BEQ skip          ; -> cond is false, skip rest of line
        ; cond is true
        LDA (CODE),Y      ; read code
        INY               ; assume match
        CMP #OP_THEN      ; "THEN"?
        BNE stmtj         ; -> no, expect stmt (no colon)
        DEY               ; undo
        CMP #OP_I0        ; is it a number? ($F0)
        BCS goto          ; -> implied GOTO
        BNE stmtj         ; -> next stmt (no colon)


        ; OP_GOTO
goto    JSR expr          ; -> Acc/XA
goln    JSR fndln         ; find line (Acc -> XA/Ptr, CS=found)
        BCC enum1         ; -> not found
        STX CODEH
        STA CODE
        LDA IO_KEY        ; check ESCAPE
        CMP #$9B          ; $80+ESC
        BEQ eesc1
        LDY #4            ; skip (OP_LN,LnL,LnH,Len,><)
        BNE stmtj         ; expect stmt (Y=4)


        ; OP_GOSUB
gosub   JSR expr          ; -> Acc/XA
        LDA CODE          ; 
        PHA               ; push CODE                        XXX stack full check !!!
        LDA CODEH         ; 
        PHA               ; push CODEH
        TYA               ;
        PHA               ; push Offset
        LDA #TAG_GOSUB    ; 
        PHA               ; push TAG
        BNE goln          ; -> ALWAYS


eesc1   LDY #<msg_esc     ; "?ESC"
        DB $2C            ; BIT abs
enum1   LDY #<msg_num-1
        DB $2C            ; BIT abs
esyn    LDY #<msg_syn-1
        JMP erro


        ; LET @(N) = Expr (52b)
leta    LDA (CODE),Y
        CMP #OP_LPAR      ; `(`
        BNE esyn          ; -> syntax
        JSR expr          ; -> Acc/XA
        ASL               ; Acc0
        ROL Acc1
        BCS enum1         ; was negative
        ADC TopL          ; TOP + (Index * 2)
        STA Ptr
        TXA               ; Acc1
        ADC TopH
        STA PtrH
        BCS enum1         ; overflow
        CMP MemSz
        BCS enum1         ; out of bounds
        JSR eqexp         ; `=` expr -> Acc/XA
        STY F             ; save Y=code-ofs
        LDY #0
        STA (Ptr),Y       ; write Acc0 to array
        INY
        TXA               ; Acc1
        STA (Ptr),Y       ; write Acc1 to array
        LDY F             ; restore Y=code-ofs
        JMP colon


        ; OP_INPUT
        ; disallowed in direct mode (overwrites EmitBuf)
inpnx   INY               ; comma
input   JSR findv         ; find [@-Z] var -> A=ofs
        BEQ esyn          ; -> `@` syntax
        STY D             ; save CODE ofs
        PHA               ; PUSH var index
        ; read number
inprt   LDA #63           ; '?'
        JSR wrch          ; (uses A,X,F,Src,Dst) preserves Y
        JSR rdln          ; (uses A,X,Y,F,Src,Dst) -> Y=len
        LDY #0            ; Y = input ofs
        JSR rdnum         ; from LineBuf,Y -> Acc,Y (uses A,X,Src)
        CPY #0            ; consumed input?
        BEQ inprt         ; -> no, retry
        PLA               ; POP var index
        JSR setv          ; assign Acc to var A=ofs
        ; check comma
        LDY D             ; restore CODE ofs
        LDA (CODE),Y      ; read code
        CMP #$2C          ; comma
        BEQ inpnx         ; -> again
        JMP colon         ; -> colon


        ; OP_POKE
poke    JSR exp2          ; -> Ptr, Acc/XA
        LDX #0
        STA (Ptr,X)       ; write Acc0 at Ptr
        JMP colon         ; -> colon


        ; OP_CLS
clss    STY E             ; save CODE offset
        JSR cls           ; (uses A,X,Y)
        LDY E             ; restore CODE offset
        JMP colon         ; -> colon


        ; OP_FOR          (78b)
        ; TAG_FOR Vofs StL StH ToH ToL CoH CoL CoY (9 bytes)
for     JSR findv         ; find var -> A=ofs
        BEQ esyn1         ; -> `@` syntax
        STA E             ; save var ofs
        JSR eqexp         ; `=` expr -> Acc/XA
        LDA E             ; get var ofs
        JSR setv          ; assign Acc to var (ofs=A)
        ; expect "TO"
        LDA (CODE),Y
        CMP #OP_TO        ; "TO"
        BNE esyn1         ; -> syntax error
        JSR expr          ; "TO" expression -> Acc/XA
        STA Ptr           ; Acc -> Ptr
        STX PtrH
        ; optional "STEP"
        LDX #1            ; set STEP = 1
        STX Acc0          ; low byte
        DEX               ; #0
        STX Acc1          ; high byte
        LDA (CODE),Y      ; peek next byte
        CMP #OP_STEP      ; "STEP"
        BNE forco         ; -> no, continue
        INY               ; OP_STEP
        JSR expr          ; "STEP" expression -> Acc/XA
forco   TYA               ; push Offset                          XXX stack full check !!!
        PHA
        LDA CODEH         ; push CODEH
        PHA
        LDA CODE          ; push CODE
        PHA
        LDA Ptr           ; ToL   (15b)
        PHA
        LDA PtrH          ; ToH
        PHA
        LDA Acc1          ; StH
        PHA
        LDA Acc0          ; StL
        PHA
        LDA E             ; Vofs
        PHA
        LDA #TAG_FOR      ; TAG_FOR
        PHA
        JMP colon         ; -> colon


esyn1   JMP esyn


        ; find [@-Z] var -> ofs (A)
        ; used by OP_LET, OP_DIM*, OP_READ, OP_INPUT, OP_FOR, Expr (11b)
findv   LDA (CODE),Y      ; [5] read code
        EOR #64           ; [2] 64->0
        CMP #27           ; [2] @-Z
        BCS esyn1         ; [2] -> syntax error
        INY               ; [2] for var
        ASL               ; [2] ofs = [@-Z] x 2
        RTS               ; [6] -> EQ=@/NE=A-Z // [21]

        ; assign Acc to var (ofs=A)
        ; used by OP_LET, OP_FOR, OP_INPUT
setv    TAX               ; as index (10b)
        LDA Acc0          ; 
        STA IVar,X        ; low byte
        LDA Acc1          ; 
        STA IVar+1,X      ; high byte
        RTS


        ; OP_PRINT
        ; print string
prdqt   INY               ; skip second `"`
prstl   JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
prstr   LDA (CODE),Y      ; read code
        BMI esyn1         ; -> bad code (guard)
        INY               ; advance
        CMP #34           ; `"`
        BNE prstl         ; -> loop
        CMP (CODE),Y      ; is next char `"`?
        BEQ prdqt         ; -> skip quote, loop
        ; entry point
print   LDX #0            ; Sep=0
prins   LDA (CODE),Y      ; [5] read code
        BPL prsym         ; [2] -> letter/symbol
        CMP #OP_STMT      ; [2] next stmt/line? ($C0)          ASSUMES: OP_STMT > OP_EXPRs
        BCS prend         ; [2] -> end print [+1]
        ; print expr
prexp   JSR expr          ; evaluate expression -> Acc/XA
        JSR wrnum         ; print Acc (uses A,X,B,C,F,Src,Dst) -> EQ
        BEQ print         ; -> always
        ; symbol or alpha
prsym   CMP #64           ; letter?
        BCS prexp         ; -> yes
        INY               ; advance
        CMP #34           ; `"`
        BEQ prstr         ; -> string
        CMP #44           ; `,`?
        BEQ prcom         ; -> comma
        CMP #59           ; `;`?
        BEQ prsem         ; -> semi
        ; syntax error
prend   CMP #OP_I0        ; number? ($F0)
        BCS prexp         ; -> yes
        TXA               ; Sep=1?
        BNE prret         ; -> no CRLF
        JSR wrnl          ; crlf (uses A,X,F,Src,Dst) preserves Y
prret   JMP colon         ; -> colon
prcml   JSR wrsp          ; write space (uses A,X,F,Src,Dst) preserves Y
prcom   LDA RemX          ; remaining space
        AND #7            ; 8 spaces
        BNE prcml         ; -> more spaces
prsem   LDX #1            ; Sep=1
        BNE prins         ; -> always


        ; OP_NEXT total   (85b)
nxtno   CMP #TAG_GOSUB
        BNE efor          ; -> "?FOR"
        LDA #3            ; TAG_GOSUB frame (minus TAG)
        DB $2C            ; BIT abs
nxtsk   LDA #7            ; TAG_FOR frame (minus TAG and VAR)
        STA F             ; frame size
        TSX
        TXA
        CLC
        ADC F             ; add frame size
        TAX
        TXS
        BNE nxtfr         ; -> always

        ; OP_NEXT
        ; Stack: TAG_FOR Vofs StL StH ToH ToL CoH CoL CoY (9 bytes)
next    JSR findv         ; find var -> A=ofs
        STA B             ; save var ofs (`@` won't match)
        ; check tag
nxtfr   PLA               ; pop TAG
        CMP #TAG_FOR
        BNE nxtno         ; -> no FOR (TAG_EMPTY at $FF)
        ; check var
        PLA               ; pop Vofs
        CMP B             ; matches var?
        BNE nxtsk         ; -> skip FOR
        TAX               ; as var index
        ; add STEP to Var
        PLA               ; pop StL
        CLC               ; 
        ADC IVar,X        ; add StL to VarL
        STA IVar,X        ; 
        PLA               ; pop StH
        ADC IVar+1,X      ; add StH to VarH
        STA IVar+1,X      ; 
        BVS enum2         ; -> overflow
        ; compare TO
        PLA               ; pop ToH
        CMP IVar+1,X      ; ToH > VarH?
        BEQ nexcl         ; -> ToH = VarH, compare low
        BCS nexc1         ; -> ToH is greater, continue FOR
nexcl   PLA               ; pop ToL
        CMP IVar,X        ; ToL > VarL?
        BCS nexco         ; -> ToL is greater/equal, continue FOR
        ; exit FOR (CC)
        PLA               ; pop CoH
        PLA               ; pop CoL
        PLA               ; pop CoY
        JMP colon         ; -> colon
        ; continue FOR
nexc1   PLA               ; pop ToL (CS)
nexco   PLA               ; pop CoL (CS)
        STA CODEH         ; set CODEH
        PLA               ; pop CoH
        STA CODE          ; set CODE
        PLA               ; pop CoY
        TAY               ; set CODE offset
        TSX               ; re-push  (6b)   TSX, STX B, LDX B, TXS (6b)
        TXA
        SBC #9            ; push 9 bytes (TAG_FOR)
        TAX
        TXS
        JMP colon         ; -> colon (after FOR)


egos    LDY #<kw_gosub
        DB $2C            ; BIT abs
efor    LDY #<kw_for      ; "?FOR"
        JMP erro          ; -> report error
enum2   JMP enumb


        ; OP_RETURN       ; (27b)
retpo   CMP #TAG_FOR
        BNE egos          ; -> no GOSUB (TAG_EMPTY at $FF)
        TSX
        TXA
        CLC
        ADC #8            ; size of TAG_FOR (minus TAG)
        TAX
        TXS
retn    PLA               ; pop TAG
        CMP #TAG_GOSUB
        BNE retpo         ; -> pop TAG_FOR (5b)
        PLA
        STA CODE          ; restore CODE
        PLA
        STA CODEH         ; restore CODEH
        PLA
        TAY               ; restore CODE ofs
        JMP colon         ; -> colon (after GOSUB)


        ; OP_LOAD
load    ; clear vars? (must clear data, arrays, set top & free, reset CODE)
        JMP repl         ; -> back to REPL                                    XXX need LOAD !!!


        ; OP_TONE
tone    JSR exp2         ; -> Ptr, Acc
        ;                                                                     XXX need TONE !!!
        JMP colon         ; -> colon


        ; --- FIND LINE ---

        ; find matching line (CS), or following line (CC)
        ; find Acc -> XA/Ptr (uses A,X,F)       (56b)
fndln   STY B             ; save Y
        LDA #>ProgPg      ; start of BASIC program
        STA PtrH          ; set Ptr page
        LDY #0            ; Y=0
        STY Ptr           ; set Ptr ofs
fndlp   LDY #2            ; Y=2
        LDA (Ptr),Y       ; (OP_LN LnLo >LnHi< Len)
        DEY               ; Y=1 moved!
;;        PHA               ; DEBUG 
;;        JSR wrhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
;;        LDA (Ptr),Y       ; DEBUG (OP_LN >LnLo< LnHi Len)
;;        JSR wrhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
;;        PLA               ; DEBUG 
        BMI fndgt         ; -> end of program (negative line)
        CMP Acc1          ; equals high byte?
        BCC fndnx         ; -> line < target, next line
        BNE fndgt         ; -> line is > target, stop
        LDA (Ptr),Y       ; (OP_LN >LnLo< LnHi Len)
        CMP Acc0          ; equals low byte?
        BCC fndnx         ; -> line < target, next line
        BNE fndgt         ; -> line is > target, stop
        ; found the line
        SEC               ; CS=found
fndrt   LDX PtrH          ; X = addr high byte
        LDA Ptr           ; A = addr low byte
        LDY B             ; restore Y
        RTS               ; -> XA=Ptr, CS
        ; found greater line number
fndgt   CLC               ; CC=not-found
        BCC fndrt         ; -> ALWAYS
        ; advance to the next line
fndnx   LDY #3            ; (OP_LN LnLo LnHi >Len<) <- BCC
        LDA (Ptr),Y       ; line length
        ADC Ptr           ; add length to Ptr (CC)
        STA Ptr           ; update Ptr
        BCC fndlp         ; -> no overflow [+1]
        INC PtrH          ;
        BNE fndlp         ; -> ALWAYS [+1] // 56b


        ; --- EXPRESSIONS ---

        ; prefix -> push it -> expect another expr
        ; var/int -> require infix or eol
        ; infix -> pop/apply higher prec -> push it -> expect another expr
        ;          eol -> pop/apply higher all -> ret

        ; a number
xnumb   CMP #OP_I0        ; [2] a number? (>=$F0)
        BCC xsyn1         ; [2] -> syntax error [+1]
        INY               ; [2] OP/digit
        LDX #0            ; [2] 
        STX Acc1          ; [3] set high
        CMP #OP_INT1      ; [2]
        BEQ xint1         ; [2] -> 1-byte int [+1]
        BCS xint2         ; [2] -> 2-byte int [+1]
        ; single-digit
        AND #15           ; [2] low 4 bits (CC)
        BCC xinfa         ; [3] -> A=Acc0 // [15+12+28=55]

        ; OP_INT2
xint2   CMP #OP_INT2      ; [2] guard
        BNE xsyn1         ; [2] -> bad code (CS)
        LDA (CODE),Y      ; [5] high (big-endian)
        STA Acc1          ; [3] set high
        INY               ; [2] high
xint1   LDA (CODE),Y      ; [5] low (CS)
        INY               ; [2] low (NE)
        BNE xinfa         ; [3] -> A=Acc0 // [INT1:19+12+28=59 INT2:34+12+28=74]

        ; `=` expr
eqexp   LDA (CODE),Y
        CMP #OP_EQ
        BNE xsyn1
        INY
        BNE expr          ; always (Y>0)

        ; expr `,` expr
exp2    JSR expr          ; -> Acc/XA
        STA Ptr           ; Acc -> Ptr
        STX PtrH
        LDA (CODE),Y      ; [5] next byte
        CMP #44           ; [2] is comma?
        BNE xsyn1         ; [2] -> syntax error
        INY               ; [2] comma
        ; +++ fall through: expr +++

        ; evaluate an expression [pre:36 ifx:51 var:82 num:55/59/74]
expr    TSX
        STX SChk
exprc   LDA (CODE),Y      ; [5]
        ;;JSR dbgx          ; DEBUG
        ;;TAX               ; DEBUG test
        BPL xvar          ; [2] -> var name [+1]
        CMP #OP_INFX      ; [2] prefix? (before infix)
        BCC xpshy         ; [2] -> prefix, push [+1]
        CMP #OP_SUB       ; [2] unary minus?
        BNE xnumb         ; [2] -> no, number [+1]
        LDA #OP_NEG       ; [2] OP_SUB -> OP_NEG
        ; +++ fall through: xpshy +++

        ; push operator
xpshy   INY               ; [2] advance
        LDX OpTop         ; [3] stack ptr
        CPX #OprsE        ; [2] end of stack
        BCS xbig          ; [2] -> "?BIG"
        STA Oprs,X        ; [4] push operator index [zp,X]
        INC OpTop         ; [5] zp
        BNE exprc         ; [3] -> always // 

xsyn1   BNE xsyn          ; [2] <- (NE)

        ; array access
xarr    LDA (CODE),Y      ; [5] read operator
        CMP #OP_LPAR      ; [2] `(`?
        BNE xvar2         ; [2] -> not array access
        LDA #OP_IDX       ; [2] `@(` bracket/operator
        BNE xpshy         ; [3] -> always, push

        ; variable        (12b)
xvar    JSR findv         ; [6][21] -> A=ofs (or syntax error)
        BEQ xarr          ; [2] -> array var
xvar2   TAX               ; [2] as index
        LDA IVar+1,X      ; [4] high [zp,X]
        STA Acc1          ; [3] set high
        LDA IVar,X        ; [4] A=Acc0 // 
        ; +++ fall through: xinfa +++

        ; infix operator or eol
xinfa   STA Acc0          ; [3] set low
xinf    LDA (CODE),Y      ; [5] read operator
        ;;JSR dbgx          ; DEBUG
        SEC               ; [2]
        SBC #OP_INFX      ; [2] map infix to 0
        CMP #OP_NIFX      ; [2] is it infix?
        BCS xend          ; [2] -> no, end expr or OP_RPAR
        TAX               ; [2] as index
        LDA preci,X       ; [4] infix precendence (X=0-12)
xopsp   STA D             ; [3] save precedence
        ; pop/apply higher precedence (loop)
xoplp   LDX OpTop         ; [3] empty ascending
        BEQ xinfp         ; [2] -> stack empy [+1]
        DEX               ; [2] down to top
        LDA Oprs,X        ; [4] get top OP [zp,X]
        TAX               ; [2] X=OP
        LDA prec-$80,X    ; [4] top precendence (X=$80-$92)
        CMP D             ; [3] top-prec >= new-prec?
        BCS xopdo         ; [2] -> do top operator (uses A,X,B,C,Acc,Term)
        ; push infix operator
xinfp   LDA D             ; [3] is prec = 0? (end of expr)
        BEQ xret          ; [2] -> yes, return
        LDA Acc1          ; [3] push current Acc,
        PHA               ; [3] infix requires RHS
        LDA Acc0          ; [3] (low byte on top)
        PHA               ; [3] 
        LDA (CODE),Y      ; [5] re-read operator
        JMP xpshy         ; [3] -> push it // 
        ; stack check (verify all pushed args were popped)
        TSX
        CPX SChk
        BNE xbig
        ; Acc -> XA for callers
xret    LDX Acc1
        LDA Acc0
        RTS

xsyn    JMP esyn          ; -> syntax error
        DB $2C            ; BIT abs
xbig    LDY #<msg_big-1
        JMP erro

        ; apply operator  (X=OP)
xopdo   DEC OpTop         ; [5] pop
        LDA OpJp-$80,X    ; [4] routine offset (X=$80-$92)
        STA JmpOp         ; [3] set jump
        LDA Acc0          ; [3] OP_IDX, OP_NOT, OP_DIV (saves bytes)
        JMP (JmpOp)       ; [3] -> do operator (uses A,X,B,C,F,Acc,Term)

        ; end of expr or OP_RPAR
xend    LDA #0            ; [2] prec = 0 (force eval all)
        BEQ xopsp         ; [2] -> set precendence (pop/apply all)



        ; prefix
prec    DB 1       ; $80 OP_LPAR open parenthesis (OP_RPAR forces eval; ends pop/apply loop)
        DB 7       ; $81 OP_ABS absolute (tail OP_NEG)
        DB 7       ; $82 OP_NOT unary NOT
        DB 7       ; $83 OP_PEEK peek address (arg)
        DB 7       ; $84 OP_RND random number (arg: mod N)
        DB 7       ; $85 OP_USR call user subroutine (at arg)
        DB 7       ; $86 OP_NEG unary negate `-` (replaces OP_SUB)
        DB 1       ; $87 OP_IDX open parenthesis (OP_RPAR forces eval; ends pop/apply loop)
        ; infix
preci   DB 6       ; $88 OP_MUL
        DB 6       ; $89 OP_DIV
        DB 5       ; $8A OP_ADD
        DB 5       ; $8B OP_SUB
        DB 4       ; $8C OP_EQ
        DB 4       ; $8D OP_NE
        DB 4       ; $8E OP_LE
        DB 4       ; $8F OP_GE
        DB 4       ; $90 OP_LT
        DB 4       ; $91 OP_GT
        DB 3       ; $92 OP_AND
        DB 2       ; $93 OP_OR

        ; operator JMP offsets
OpJp    DB <xlpr   ; OP_LPAR open parenthesis (back to xinf)
        DB <xabs   ; OP_ABS absolute (tail OP_NEG)
        DB <xnot   ; OP_NOT unary NOT
        DB <xpeek  ; OP_PEEK peek address (arg)
        DB <xrnd   ; OP_RND random number (arg: mod N)
        DB <xusr   ; OP_USR call user subroutine (at arg)
        DB <xneg   ; OP_NEG unary negate `-`
        DB <xidx   ; OP_IDX open parenthesis (back to xinf)
        ; infix
        DB <xmul   ; OP_MUL
        DB <xdiv   ; OP_DIV
        DB <xadd   ; OP_ADD
        DB <xsub   ; OP_SUB
        DB <xeq    ; OP_EQ
        DB <xne    ; OP_NE
        DB <xle    ; OP_LE
        DB <xge    ; OP_GE
        DB <xlt    ; OP_LT
        DB <xgt    ; OP_GT
        DB <xand   ; OP_AND
        DB <xor    ; OP_OR



        ; --- OPERATORS (PAGE) ---

        ; XXX OR, RND, MUL, DIV don't fit..

xoppg   = BasROM+$700

        ; OP_IDX
        ; prefix `@(`     (41b)
xidx    ASL               ; index * 2 (A=Acc0)
        ROL Acc1
        BCS xnum          ; was negative
        ADC TopL          ; CC
        STA Term0
        LDA Acc1
        ADC TopH
        STA Term1
        CMP MemSz
        BCS xnum          ; out of bounds
        STY F
        LDY #0
        LDA (Term0),Y     ; read array
        STA Acc0          ; replace index
        INY
        LDA (Term0),Y
        STA Acc1
        LDY F
        ; +++ fall through: OP_LPAR +++

        ; OP_LPAR
xlpr    LDA (CODE),Y      ; [5] re-read operator
        CMP #OP_RPAR      ; [2] is it `)`?
        BNE xsyn          ; [2] -> no, missing `)`
        INY               ; [2] skip `)`
        JMP xinf          ; [3] -> expect infix

xnum    LDY #<msg_num-1
        JMP erro

        ; OP_ABS
xabs    LDA Acc1          ; [3] high byte
        BPL xnxop         ; [2] -> positive [+1] // 4b
        ; +++ fall through: xneg +++

        ; OP_NEG
xneg    SEC               ; [2]
        LDA #0            ; [2] 0 - X
        SBC Acc0          ; [3] low byte
        STA Acc0          ; [3] result low
        LDA #0            ; [2] 
        SBC Acc1          ; [3] high byte
        STA Acc1          ; [3] result high
xnxop   JMP xoplp         ; [3] -> next oper // 16b

        ; OP_NOT
xnot    EOR #$FF          ; [2] invert (A=Acc0)
        STA Acc0          ; [3] result low
        LDA Acc1          ; [3] high byte
        EOR #$FF          ; [2] invert
        STA Acc1          ; [3] result high
        JMP xoplp         ; [3] -> next oper // 15b

        ; OP_PEEK
xpeek   LDX #0            ; [2]
        LDA (Acc0,X)      ; [6] fetch byte
        STA Acc0          ; [4] result low
        STX Acc1          ; [4] result high
        BEQ xnxop         ; [3] -> next oper // 10b

        ; OP_USR
xusr    STY E             ; save CODE offset
        JSR xusrj         ; call subroutine
        LDY E             ; restore CODE offset
        BNE xnxop         ; [3] -> next oper // 10b
xusrj   JMP (Acc0)        ; jump to address

        ; OP_ADD
        ; Acc=RHS, Stack=LHS
xadd    CLC               ; [2]
        PLA               ; [4] left low (pushed last)
        ADC Acc0          ; [3] right low
        STA Acc0          ; [3] result low
        PLA               ; [4] left high
        ADC Acc1          ; [3] right high
        STA Acc1          ; [3] result high
        BVS xnum          ; [2] overflow
        JMP xoplp         ; [3] -> next oper // 16b [27]

        ; OP_SUB
xsub    SEC               ; [2]
        PLA               ; [4] left low
        SBC Acc0          ; [3] right low
        STA Acc0          ; [3] result low
        PLA               ; [4] left high
        SBC Acc0          ; [3] right high
        STA Acc0          ; [3] result high
        BVS xnum          ; [2] overflow
        JMP xoplp         ; [3] always // 16b [27]

        ; OP_EQ
xeq     PLA               ; left low
        CMP Acc0          ; right low
        BNE xfalsp        ; -> not equal
        PLA               ; left high
        CMP Acc1          ; right high
        BNE xfalse        ; -> not equal // 12b
        BEQ xtrue         ; -> equal

xtruep  PLA
xtrue   LDA #$FF
        BNE xbool
xfalsp  PLA
xfalse  LDA #0
xbool   STA Acc0          ; result low
        STA Acc1          ; result high
        JMP xoplp         ; always // 15b

        ; OP_NE
xne     PLA               ; left low
        CMP Acc0          ; right low
        BNE xtruep        ; -> not equal
        PLA               ; left high
        CMP Acc1          ; right high
        BNE xtrue         ; -> not equal
        BEQ xfalse        ; -> equal // 12b

        ; Less/Greater
xltne   BVS xltV          ; -> overflow
xgtV    BMI xtrue         ; -> less    [greater]
        BPL xfalse        ; -> greater [less]
xgtne   BVS xgtV          ; -> overflow
xltV    BPL xtrue         ; -> greater [less]
        BMI xfalse        ; -> less    [greater]

        ; OP_LT
xlt     PLA               ; left low
        TAX               ; save low
        PLA               ; left high
        CMP Acc1          ; right high
        BNE xltne         ; -> not equal
        CPX Acc0          ; right low
        BCC xtrue         ; -> less
        BCS xfalse        ; -> gt/eq (always) // 13b

        ; OP_LE
xle     PLA               ; left low
        TAX               ; save low
        PLA               ; left high
        CMP Acc1          ; right high
        BNE xltne         ; -> not equal
        CPX Acc0          ; right low
        BCC xtrue         ; -> less
        BEQ xtrue         ; -> equal
        BNE xfalse        ; -> greater (always) // 15b

        ; OP_GT
xgt     PLA               ; left low
        TAX               ; save low
        PLA               ; left high
        CMP Acc1          ; right high
        BNE xgtne         ; -> not equal
        CPX Acc0          ; right low
        BCC xfalse        ; -> less
        BNE xtrue         ; -> greater
        BEQ xfalse        ; -> equal // 15b

        ; OP_GE
xge     PLA               ; left low
        TAX               ; save low
        PLA               ; left high
        CMP Acc1          ; right high
        BNE xgtne         ; -> not equal
        CPX Acc0          ; right low
        BCS xtrue         ; -> greater/equal
        BCC xfalse        ; -> less // 13b

        ; OP_AND
xand    PLA               ; [4] left low
        AND Acc0          ; [3] right low
        STA Acc0          ; [3] result low
        PLA               ; [4] left high
        AND Acc1          ; [3] right high
        STA Acc1          ; [3] result high
        JMP xoplp         ; [3] always // 15b

        ; OP_OR
xor     PLA               ; [4] left low
        ORA Acc0          ; [3] right low
        STA Acc0          ; [3] result low
        PLA               ; [4] left high
        ORA Acc1          ; [3] right high
        STA Acc1          ; [3] result high
        JMP xoplp         ; [3] always // 15b

        ; OP_DIV          (34)
xdiv    STA Term0         ; [3] divisor low (A=Acc0)
        LDA Acc1          ; [3] right high
        STA Term1         ; [3] divisor high
        PLA               ; [4] left low
        STA Acc0          ; [3] dividend low
        PLA               ; [4] left high
        STA Acc1          ; [3] dividend high
        JSR div16         ; [6] Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
        JMP xoplp         ; [3] always // 34b

        ; OP_MUL          (69)
xmul    PLA               ; [4] left low
        STA Term0         ; [3] multiplier low
        PLA               ; [4] left high
        STA Term1         ; [3] multiplier high
        JSR mul16         ; [6] Acc=multiplicand, Term=multiplier -> BC=product (uses A,X,B,C,Acc,Term)
        BCS eovf          ; [2] -> overflow
        LDA B             ; [3] product low
        STA Acc0          ; [3] result low
        LDA C             ; [3] product high
        STA Acc1          ; [3] result high
        JMP xoplp         ; [3] always
eovf    JMP xnum          ; [3] overflow

        ; OP_RND          (67)
xrnd    PLA               ; [4] low byte
        STA Term0         ; [3] divisor low
        PLA               ; [4] high byte
        STA Term1         ; [3] divisor high
        JSR rand          ; [6] random number in [1..Term] -> Acc (uses A,X,B,C,Acc,Term)
        JMP xnxop         ; [3] -> next oper // 12b


;;dbgx    PHA
;;        JSR wrhx          ; DEBUG
;;        JSR wrsp
;;        PLA
;;        RTS


; ALIGN 256
ProgPg = $   ; start of program memory

ORG BasROM+$FFF
DB 0

; ins/del line
; "at line NNN"
; LOAD/SAVE
; TONE
; OP_SIZE (immediate, push)


; 8B9
; 87D
; 878
; 873
; 842 (moved RND)
; 83D (CALL -> USR)
; 845 (stack check: TSX;STX SChk;TSX;CPX SChk;BNE xbig) +8 bytes
; 862 (?SYN AT 10) +29 bytes
; 853 (Acc/XA)
; 8AF (insert line)
