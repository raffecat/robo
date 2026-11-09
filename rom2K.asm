; Frontier 2K BASIC
; Use `asm6` to compile: https://github.com/parasyte/asm6

BasROM   = $0200   ; 2K BASIC
End4K    = $10     ; end of 4KB memory (minimum RAM fitted)

; ------------------------------------------------------------------------------
; Monitor Routines

montr = $FE00
cls   = $FF07     ; (uses A,X,Y) -> Y=0,EQ
home  = $FF19     ; (uses A,Y) -> Y=0,EQ
tclr  = $FF26     ; (uses A,Y) -> Y=0,EQ
rdln  = $FF30     ; (uses A,X,Y,F,Src,Dst) -> Y=len
wrnl  = $FF70     ; (uses A,X,F,Src,Dst) preserves Y
wrsp  = $FF7D     ; (uses A,X,F,Src,Dst) preserves Y
wrhx  = $FF81     ; (uses A,X,F,Src,Dst) preserves Y
wrch  = $FF95     ; (uses A,X,F,Src,Dst) preserves Y
cpyf  = $FFD8     ; (uses A,X,Y,F,Src,Dst) -> X=0

; ------------------------------------------------------------------------------
; Zero Page $00-BF - BASIC WORKSPACE

; -- $00-3F Expression Stacks (96)

Args     = $00    ; Ascending Empty Stack, 32 words (ArgTop)
ArgsE    = $40    ; End of Stack

Oprs     = $40    ; Ascending Empty Stack, 32 bytes (OpTop)
OprsE    = $60    ; End of Stack

; -- $60-6F Arrays (32)

ArrPt    = $60    ; [@-G] 8 x 16-bit pointers
ArrSz    = $70    ; [@-G] 8 x 16-bit pointers

; -- $80-B5 Integer Vars (54)

IVar     = $80    ; [@-Z] 27 x 16-bit variables                   (used in RT / Direct)

; -- $B6-BF BASIC Pointers (12 bytes)

OpTop    = $B6    ; Top of Oprs (stack pointer)                   (used in RT / Direct)
ArgTop   = $B7    ; Top of Args (stack pointer)                   (used in RT / Direct)
Data     = $B8    ; BASIC data pointer (next DATA statement)      (used in RT / Direct)
DataH    = $B9    ; 
DataY    = $BA    ;
CODE     = $BB    ; BASIC code pointer (next instruction)         (used in RT / Direct)
CODEH    = $BC    ;
FreePtr  = $BD    ; FREE space at end of variables                (used in RT / Direct / EDIT)
FreePtrH = $BE    ;
EmitOfs  = $BF    ; emit offset for tokenized code                (used in EDIT)

; ------------------------------------------------------------------------------
; Zero Page $C0-FF - SYSTEM WORKSPACE

; -- $C0-CF System Temporaries (16)

Src      = $C0        ; source pointer \ WRCH, CLS  [Term0]
SrcH     = $C1        ; source pointer |            [Term1]
Acc0     = Src        ; ALIAS: accumulator byte 0
Acc1     = SrcH       ; ALIAS: accumulator byte 1
Dst      = $C2        ; destn pointer  | WRCH, CLS  [Term0]
DstH     = $C3        ; destn pointer  /            [Term1]
Term0    = Dst        ; ALIAS: term byte 0
Term1    = DstH       ; ALIAS: term byte 1
Ptr      = $C4        ; third pointer  \ findln, ins/del line
PtrH     = $C5        ; third pointer  /
B        = $C6        ; extra register | Subroutines are annotated with usage;
C        = $C7        ; extra register | held across calls only when unused
D        = $C8        ; extra register | by callees (manually tracked)
E        = $C9        ; extra register |
F        = $CA        ; IO Temp register (all IO, cpyf/cpyb)

TXTP     = $CB        ; text write address
TXTPH    = $CC        ; text write address high
RemX     = $CD        ; remaining space on line
CurTime  = $CE        ; cursor flash timer
MemSz    = $CF        ; detected memory size in pages

; -- $D0-D3 Extra BASIC Vars (4)

TopL     = $D0        ; TOP of BASIC program, start of variables
TopH     = $D1
JmpOp    = $D2        ; JMP indirect ptr for operators
JmpOpH   = $D3
LFSL     = $D4        ; Linear-feedback RNG
LFSH     = $D5

; -- $D4-E7 free (20)

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


; ------------------------------------------------------------------------------
; PAGE ONE $100-1FF - STACK

LineBuf  = $100    ; Input Buffer (128 bytes)
EmitBuf  = $100    ; Emit Buffer (128 bytes)

CtlBot = $180      ; Bottom of BASIC control-stack (cannot go below $180)


; ------------------------------------------------------------------------------
; PAGE 0 - REPL

ORG BasROM

reset   SEI               ; disable interrupts
        CLD               ; disable BCD mode
        ; detect memory   (25b)
        LDY #0            ; const
        TYA               ; A=0 (store non-match at $A0)
        LDX #$A0          ; highest RAM page +1
msetl   STX PtrH          ; update Ptr
        STA (Ptr),Y       ; write page number
        DEX               ; decr Page
        TXA               ; A = Page (write Page)
        CPX #>ProgPg      ; stop above BASIC! ($0A)
        BNE msetl         ; -> until $00
mchkl   INX               ; incr Page
        STX PtrH          ; update Ptr
        TXA               ; A = Page (write Page)
        CMP (Ptr),Y       ; compare page number
        BEQ mchkl         ; -> until differs
        STX MemSz         ; set size of memory (in pages)
        ; initialise BASIC
        JSR cls           ; clear screen
        JMP new           ; init program -> jumps to repl
        ; return to repl
        ; reset the stack, errors jump out of subroutines
repl    LDX #$FF          ; X = $FF
        TXS               ; reset SP = $FF
        INX               ; X = 0
        TXA               ; A = 0
        PHA               ; push 0 (TAG_EMPTY at $FF)
        STX ArgTop        ; reset Args stack                             XXX use $FE (full asc)
        STX OpTop         ; reset Oprs stack                             XXX use $FE (full asc)
        LDA #>xoppg       ; operator page
        STA JmpOpH        ; set ptr high
        LDA #62           ; `>`
        JSR wrch          ; (uses A,X,F,Src,Dst) preserves Y
        JSR rdln          ; (uses A,X,Y,F,Src,Dst) -> Y=len
        ; parse the line
        LDY #0            ; offset = 0
        STY EmitOfs       ; reset
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y (uses A,X,Src)    XXX BUG tknum also uses Args[0]
        STY D             ; line-no flag (NE=found)
        DEY               ; for INY
        ; tokenize the line
tkskp   INY               ; skip space
tokn    LDA LineBuf,Y     ; next input char
        CMP #32           ; space?
        BEQ tkskp         ; -> skip it
        TAX               ; save X=next-char (EQ)
        BEQ tkeol         ; -> end of line
        STA C             ; save first-char               +2
        STY B             ; save start-of-word
        EOR #64           ; '@' to 0
        CMP #27           ; 26 letters plus @
        BCS tksym         ; -> not a letter
        TAX               ; A-Z index (0-26)
        LDA kw_tab,X      ; look up KW offset (A-Z)
        TAX               ; as index
        ; match keyword
tkmat   DEY               ; set up input pos
        DEX               ; set up keyword pos
tkmlp   INY               ; pre-increment input pos
        INX               ; pre-increment keyword pos
tkmnx   LDA kwpg,X        ; next keyword char
        BMI tkemt         ; -> found opcode, emit (bit 7 set)
        CMP LineBuf,Y     ; does it match input?
        BEQ tkmlp         ; -> yes, next char
        ; find next keyword
        LDY B             ; restore Y = start of word
        ASL               ; test keyword byte (d7=0)
        BEQ tkmno         ; -> DB 0, end of list
tkmsk   INX               ; find end of this keyword
        LDA kwpg,X        ; check keyword byte
        BPL tkmsk         ; -> top bit clear, keep going
        INX               ; advance to next word            +1
        LDA kwpg,X        ; get keyword byte                +3
        CMP #64           ; a letter?                       +2
        BCC tkmnx         ; -> no, next symbol              +2
        CMP C             ; same first char?                +2
        BEQ tkmnx         ; -> yes, next word               +2 -3 -5 -2 = +4
        ; no match found
tkmno   LDA C             ; reload A=first-char
tkemy   INY               ; advance input
tkemt   JSR tkemi         ; output token with top-bit set (uses X=0; preserves A,Y; sets PL)
        BPL tokn          ; -> ALWAYS
tkeol   LDA D             ; line-no found?
        BEQ dcmd          ; -> no, direct command
        LDX EmitOfs       ; did we emit?
        BEQ delln         ; -> no, delete line
        ; insert the line
        JMP repl          ; -> return to repl
        ; delete the line
delln   JMP repl          ; -> return to repl

        ; not a letter
tksym   TXA               ; A=next-char
        CMP #34           ; "
        BEQ tkstr         ; -> String
        EOR #48           ; make '0' be 0
        CMP #10           ; 10 digits
        BCC tknum         ; -> emit number
        LDX #<expr_ops    ; operator table
        BNE tkmat         ; -> ALWAYS match operators

        ; direct command
dcmd    LDA #OP_EOP       ; end of program
        JSR tkemi         ; terminate the line
        ;
debug   LDY #0            ; DEBUG
dbglp   LDA EmitBuf,Y     ; 
        JSR wrhx          ; saves Y
        JSR wrsp          ; saves Y
        INY
        CPY EmitOfs       ; emit length
        BCC dbglp         ; -> less, loop
        JSR wrnl          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        ; 
        LDA #>EmitBuf     ; page ($01)
        STA CODEH         ; set CODE page
        LDY #0            ; 
        STY CODE          ; set CODE ofs
        STY OpTop         ; clear operator stack                    XXX use $FE (full asc)
        STY ArgTop        ; clear args stack                        XXX use $FE (full asc)
        JMP stmtj         ; -> execute statement (at Y=0)

        ; copy a string (23b)
tkstr   JSR tkemi         ; emit char (uses X=0; preserves A,Y; sets PL)
        INY               ; advance
        LDA LineBuf,Y     ; get next char
        BEQ tksyn         ; -> at end of line, missing quote
        CMP #34           ; is it `"`?
        BNE tkstr         ; -> no, loop (not a quote)
        ; found a quote
        CMP LineBuf+1,Y   ; is next char `"` ?
        BNE tkemy         ; -> end of string, emit closing quote
        ; double-quote
        INY               ; first `"`
        JSR tkemi         ; emit `"` (uses X=0; preserves A,Y; sets PL)
        BPL tkstr         ; -> loop, second `"`

tksyn   JMP esyn          ; -> report error

        ; emit a number (45b)
tknum   JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
        STY B             ; save Y
        LDX #OP_INT2      ; OP_INT2
        LDY #2            ; 2 bytes
        LDA Args+1        ; high byte
        BNE tknmo         ; -> OP_INT2 + 2 bytes
        DEX               ; OP_INT1
        DEY               ; 1 byte
        LDA Args          ; low byte
        CMP #10           ; CS if >= 10
        BCS tknmo         ; -> OP_INT1 + 1 byte (CS)
        DEY               ; 0 bytes
        ORA #OP_I0        ; single-digit
        TAX               ;
tknmo   TXA               ; X=OP
tknlp   JSR tkemi         ; (uses X=0; preserves A,Y; PL)
        LDX Args-1,Y      ; 2=$01, 1=$00, 0=$FF (relies on zp,Y wrap-around)
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
        RTS               ; [6] -> NE,PL,X=EmitOfs-1 (for emit_str)

        ; report an error (Y=msg)
enumb   LDY #<msg_num     ; "?NUM"
        DB $2C            ; BIT abs
ebrk    LDY #<msg_brk     ; "?BRK"                                          XXX "at line NNN" !!!
erro    LDA #63           ; `?`
        DEY               ; for INY
errl    JSR wrch          ; write char (uses A,X,F,Src,Dst) preserves Y
        INY               ; 
        LDA msgs,Y        ; next char
        BPL errl          ; loop until >= $80
        JSR wrnl          ; crlf (uses A,X,F,Src,Dst) preserves Y
        JMP repl          ; -> always


; ------------------------------------------------------------------------------
; PAGE 1 - Statement Tokens

msgs = BasROM+$100
kwpg = BasROM+$100

; start-of-line
OP_STMT    = $C0     ; * stmt base
OP_EOP     = $C0
OP_LN      = $C1
OP_EOL     = $C2     ; * use BCC
OP_COLN    = $C2
OP_EOS     = $C3     ; * use BCC
; keywords
OP_CLS     = $C3
OP_CALL    = $C4
OP_END     = $C5
OP_FOR     = $C6
OP_GOTO    = $C7
OP_GOSUB   = $C8
OP_IF      = $C9
OP_INPUT   = $CA
OP_LET     = $CB
OP_LOAD    = $CC
OP_LIST    = $CD
OP_NEXT    = $CE
OP_NEW     = $CF
OP_PRINT   = $D0
OP_POKE    = $D1
OP_RETURN  = $D2
OP_REM     = $D3
OP_RUN     = $D4
OP_SAVE    = $D5
OP_TONE    = $D6
OP_XSTMT   = $D7     ; * first non-stmt
; context keywords
OP_STEP    = $D7
OP_TO      = $D8
OP_THEN    = $D9
; unary operators (highest precedence, evaluated post-fix, right-associative)
OP_NPRE    = 5       ; * num prefix (excludes OP_NEG,OP_IDX)
OP_LPAR    = $80     ; 0 open parenthesis (lowest precedence, ends pop/apply -> xinf)
OP_ABS     = $81     ; 7 unary Minus (OP_SUB ORA #16 -> push)
OP_NOT     = $82     ; 7 unary NOT
OP_PEEK    = $83     ; 7 unary fn (arg)
OP_RND     = $84     ; 7 unary fn (arg)
OP_NEG     = $85     ; 7 unary Minus (OP_SUB)
OP_IDX     = $86     ; 0 unary array (lowest precedence, ends pop/apply -> xinf)
; infix binary (from highest to lowest, left-associative)
OP_IFXB    = 6       ; * infix base in prec table
OP_INFX    = $87     ; * first infix
OP_NIFX    = 12      ; * num infix (excludes OP_RPAR)
OP_MUL     = $87     ; 6 binary op  LSR for prec
OP_DIV     = $88     ; 6 binary op
OP_ADD     = $89     ; 5 binary op
OP_SUB     = $8A     ; 5 binary op (maps to OP_NEG)
OP_EQ      = $8B     ; 4 binary `=`
OP_NE      = $8C     ; 4 binary `<>`
OP_LE      = $8D     ; 4 binary `<=`
OP_GE      = $8E     ; 4 binary `>=`
OP_LT      = $8F     ; 4 binary `<`
OP_GT      = $90    ; 4 binary `>`
OP_AND     = $91     ; 3 binary op
OP_OR      = $92     ; 2 binary op
; special (not prefix or infix)
OP_RPAR    = $93     ; 0 infix close parenthesis (forces all ops to eval up to OP_LPAR/OP_IDX)
OP_SIZE    = $94     ; push size of @-array
; numbers (non-operator)
OP_I0      = $F0     ; 1-byte (OP_I0 + [0-9])
OP_I9      = $F9     ; 1-byte
OP_INT1    = $FA     ; 1-byte (opc|int8)
OP_INT2    = $FB     ; 2-byte (opc|int16)

kws_at:
kws_a:
ex_and    DB "AND",      OP_AND
ex_abs    DB "ABS",      OP_ABS
kws_b:
kws_c:
kw_call   DB "CALL",     OP_CALL
kw_cls    DB "CLS",      OP_CLS
kws_d:
kws_e:
kw_end    DB "END",      OP_END
kws_f:
msg_for   ;
kw_for    DB "FOR",      OP_FOR
kws_g:
kw_goto   DB "GOTO",     OP_GOTO
msg_gos   ;
kw_gosub  DB "GOSUB",    OP_GOSUB
kws_h:
kws_i:
kw_if     DB "IF",       OP_IF
kw_input  DB "INPUT",    OP_INPUT
kws_j:
kws_k:
kws_l:
kw_let    DB "LET",      OP_LET
kw_load   DB "LOAD",     OP_LOAD
kw_list   DB "LIST",     OP_LIST
kws_m:
kws_n:
kw_next   DB "NEXT",     OP_NEXT
ex_not    DB "NOT",      OP_NOT
kw_new    DB "NEW",      OP_NEW
kws_o:
ex_or     DB "OR",       OP_OR
kws_p:
kw_print  DB "PRINT",    OP_PRINT
ex_peek   DB "PEEK",     OP_PEEK
kw_poke   DB "POKE",     OP_POKE
kws_q:
kws_r:
ex_rnd    DB "RND",      OP_RND
kw_retr   DB "RETURN",   OP_RETURN
kw_rem    DB "REM",      OP_REM
kw_run    DB "RUN",      OP_RUN
kws_s:
ex_step   DB "STEP",     OP_STEP
kw_save   DB "SAVE",     OP_SAVE
kws_t:
ex_to     DB "TO",       OP_TO
ex_then   DB "THEN",     OP_THEN
kw_tone   DB "TONE",     OP_TONE
kws_u:
kws_v:
kws_w:
kws_x:
kws_y:
kws_z     DB 0

expr_ops:
ex_mul    DB "*",    OP_MUL
ex_div    DB "/",    OP_DIV
ex_add    DB "+",    OP_ADD
ex_sub    DB "-",    OP_SUB
ex_eq     DB "=",    OP_EQ
ex_ne     DB "<>",   OP_NE
ex_le     DB "<=",   OP_LE
ex_ge     DB ">=",   OP_GE
ex_lt     DB "<",    OP_LT
ex_gt     DB ">",    OP_GT
ex_lp     DB "(",    OP_LPAR
ex_rp     DB ")",    OP_RPAR
ex_co     DB ":",    OP_COLN
          DB 0

          ; messages
msg_syn   DB "SYN",$80
msg_num   DB "NUM",$80
msg_big   DB "STK",$80
msg_brk   DB "BRK",$80

; Keyword Index
kw_tab:
  DB (kws_a - kwpg) ; @
  DB (kws_a - kwpg) ; A
  DB (kws_b - kwpg) ; B
  DB (kws_c - kwpg) ; C
  DB (kws_d - kwpg) ; D
  DB (kws_e - kwpg) ; E
  DB (kws_f - kwpg) ; F
  DB (kws_g - kwpg) ; G
  DB (kws_h - kwpg) ; H
  DB (kws_i - kwpg) ; I
  DB (kws_j - kwpg) ; J
  DB (kws_k - kwpg) ; K
  DB (kws_l - kwpg) ; L
  DB (kws_m - kwpg) ; M
  DB (kws_n - kwpg) ; N
  DB (kws_o - kwpg) ; O
  DB (kws_p - kwpg) ; P
  DB (kws_q - kwpg) ; Q
  DB (kws_r - kwpg) ; R
  DB (kws_s - kwpg) ; S
  DB (kws_t - kwpg) ; T
  DB (kws_u - kwpg) ; U
  DB (kws_v - kwpg) ; V
  DB (kws_w - kwpg) ; W
  DB (kws_x - kwpg) ; X
  DB (kws_y - kwpg) ; Y
  DB (kws_z - kwpg) ; Z

; Keyword Reverse Lookup
kwrvs = kwrev - OP_EOL   ; includes `:`
kwrev:                   ; indices MUST match OPCODEs
  DB (ex_co - kwpg)      ; `:`
  DB (kw_cls - kwpg)     ; OP_CLS
  DB (kw_call - kwpg)    ; OP_CALL
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
        DB <call         ; OP_CALL
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
        DB >call         ; OP_CALL
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


; fndln -> Ptr (start of line, or start of first greater line, or end marker)
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
  JSR fndln         ; [6] find matching line (Args[0] -> Ptr, CS=found)
  BCS @replace      ; [2] -> replace line at Ptr
  ; insert line:
  ; cpy(To=Ptr+Ins,From=Ptr,Len=Top-From) to make room
  ; Top += Ins
@copyin:
  ; copy EmitBuf -> Ptr                                         XXX need ins line !!!
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
  ;                                                              XXX need del line !!!
  RTS

        ; OP_LIST         (80b)
list    JSR expr          ; line number -> Args[0]
        JSR fndln         ; find matching line, or next (Args[0] -> XA/Ptr)
        ; line number
lstln   LDY #2            ; Y=2
        LDA (Ptr),Y       ; (OP LnLo >LnHi< Len)
        BMI lstx          ; -> end of program (negative line)
        STA Args+1
        DEY               ; Y=1
        LDA (Ptr),Y       ; (OP LnLo >LnHi< Len)
        STA Args
        JSR prnum         ; print Args[0] (uses A,X,B,C,F,Src,Dst)
        JSR wrsp          ; print space (uses A,X,F,Src,Dst) preserves Y
        LDY #4            ; skip header
        ; line contents
lstco   LDA (Ptr),Y       ; next byte
        BPL lstch         ; -> char
        CMP #OP_EOL       ; end of line?
        BCC lstnx         ; -> next line
        ; print token                                            XXX bad token check?
        STY B             ; save line ofs
        TAX               ; as index
        LDY kwrvs,X       ; look up token offset (-1)
        LDA #32           ; space before token
lsttk   JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
        INY               ; advance
        LDA kwpg,Y        ; next char
        BPL lsttk         ; -> more
        LDA #32           ; space after token
        LDY B             ; restore line ofs
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
        LDA #4            ; (OP_EOP LnLo LhHi Len)
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
        LDX #92           ; ArrPt(16),ArrSz(16),IVar(54),OpTop(1),ArgTop(1),Data(3),CODE(2)
runcl   STA ArrPt,X       ; clear zp,X
        DEX
        BNE runcl         ; -> loop
        TAY               ; CODE offset = 0
        LDA #>ProgPg      ; start of BASIC program (NE)
        STA CODEH         ; set CODE page
        STY CODE          ; ensure 0
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
        PHA               ; DEBUG
        JSR wrhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        JSR wrnl          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        PLA               ; DEBUG
        BPL let           ; [2] -> implied LET [+1]
        INY               ; [2] advance code
        ; guard [+4 cycles]
        CMP #OP_XSTMT     ; [2] non-statement?
        BCS esyn          ; [2] -> bad code
        ; token dispatch
        TAX               ; [2]
        LDA stmtl,X       ; [4]
        STA Src           ; [3] PHA
        LDA stmth,X       ; [4]
        STA SrcH          ; [3] PHA
        JMP (Src)         ; [5] RTS // [34] [colon +15]


        ; OP_LET or implied
        ; assign VAR = Expr
let     JSR findv         ; find [@-Z] var -> ofs (A)
        BEQ leta          ; -> array
        PHA               ; push var ofs
        JSR eqexp         ; `=` expr -> Args[0]
        PLA               ; pop var ofs
        JSR setv          ; assign Args[0]
        JMP colon         ; -> colon


        ; OP_IF
        ; evaluate condition, skip rest of line if false
        ; if true, check for implied GOTO (line number)
ifs     JSR expr          ; condition -> Args[0]
        LDA Args          ; test Args[0]
        ORA Args+1        ;
        BEQ skip          ; -> cond is false, skip rest of line
ifsl    LDA (CODE),Y      ; read code
        INY               ; assume match
        CMP #OP_THEN      ; "THEN"?
        BNE stmtj         ; -> next stmt (no colon)
        DEY               ; undo
        CMP #OP_I0        ; is it a number?
        BCS goto          ; -> implied GOTO
        BNE stmtj         ; -> next stmt (no colon)


        ; OP_GOTO
goto    JSR expr          ; -> Args[0]
goln    JSR fndln         ; find line (Args[0] -> XA/Ptr, CS=found)
        BCC enum1         ; -> not found
        STX CODEH
        STA CODE
        LDY #4            ; skip (OP_LN,LnL,LnH,Len,><)
        BNE stmtj         ; expect stmt (Y=4)


enum1   LDY #<msg_num
        DB $2C            ; BIT abs
esyn    LDY #<msg_syn
        JMP erro


        ; LET @(N) = Expr (52b)
leta    LDA (CODE),Y
        CMP #OP_LPAR      ; `(`
        BNE esyn          ; -> syntax
        JSR expr          ; -> Args[0]
        JSR eqexp         ; `=` expr -> Args[1]
        ASL Args
        ROL Args+1
        BCS enum1         ; was negative
        LDA Args+0
        ADC TopL          ; CC
        STA Args+0
        LDA Args+1
        ADC TopH
        STA Args+1
        CMP MemSz
        BCS enum1         ; out of bounds
        STY F             ; save Y=code-ofs
        LDY #0
        LDA $02           ; val low
        STA (Args),Y      ; write to array
        INY
        LDA $03           ; val high
        STA (Args),Y
        LDY F             ; restore Y=code-ofs
        JMP colon


        ; OP_GOSUB
gosub   JSR expr          ; -> Args[0]
        LDA CODE          ; 
        PHA               ; push CODE                        XXX stack full check !!!
        LDA CODEH         ; 
        PHA               ; push CODEH
        TYA               ;
        PHA               ; push Offset
        LDA #TAG_GOSUB    ; 
        PHA               ; push TAG
        BNE goln          ; -> ALWAYS


        ; OP_INPUT
inpnx   INY               ; comma
input   JSR findv         ; find [@-Z] var -> A=ofs
        BEQ esyn          ; -> `@` syntax
        STY D             ; save CODE ofs
        PHA               ; PUSH var index
        ; print var/str
inprt   LDA #63           ; '?'
        JSR wrch          ; (uses A,X,F,Src,Dst) preserves Y
        JSR rdln          ; (uses A,X,Y,F,Src,Dst) -> Y=len
        LDY #0            ; Y = input ofs
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
        CPY #0            ; consumed input?
        BEQ inprt         ; -> no, retry
        PLA               ; POP var index
        JSR setv          ; assign Args[0] to var A=ofs
        ; check comma
        LDY D             ; restore CODE ofs
        LDA (CODE),Y      ; read code
        CMP #$2C          ; comma
        BEQ inpnx         ; -> again                    XXX string prompt; suppress '?' with semi
        JMP colon         ; -> colon


        ; OP_POKE
poke    JSR exp2          ; $00 = Addr, $02 = Byte
        LDA $02           ; byte
        LDX #0
        STA (Args,X)      ; write to memory at Args[0]
        JMP colon         ; -> colon


        ; OP_CLS
clss    STY E             ; save CODE offset
        JSR cls           ; (uses A,X,Y)
        LDY E             ; restore CODE offset
        JMP colon         ; -> colon


        ; OP_CALL
call    JSR expr          ; -> Args[0]
        STY E             ; save CODE offset
        JSR callj         ; 
        LDY E             ; restore CODE offset
        JMP colon         ; -> colon
callj   JMP (Args)        ; jump to Args[0]


        ; OP_FOR          (75b)
        ; TAG_FOR Vofs StL StH ToH ToL CoH CoL CoY (9 bytes)
for     JSR findv         ; find var -> A=ofs
        BEQ esyn1         ; -> `@` syntax
        STA $06           ; save var ofs
        JSR eqexp         ; `=` expr -> Args[0]
        LDA $06           ; get var ofs
        JSR setv          ; assign Args[0] to var ofs (A)
        ; expect "TO"
        LDA (CODE),Y
        CMP #OP_TO        ; "TO"
        BNE esyn1         ; -> syntax error
        JSR expr          ; "TO" expression -> $02-03 L,H
        ; optional "STEP"
        LDX #1            ; set STEP = $0001
        STX $04           ; low byte
        DEX               ; #0
        STX $05           ; high byte
        LDA (CODE),Y      ; peek next byte
        CMP #OP_STEP      ; "STEP"
        BNE forco         ; -> no, continue
        INY               ; OP_STEP
        JSR expr          ; "STEP" expression -> $04-05 L,H
forco   TYA               ; push Offset                          XXX stack full check !!!
        PHA
        LDA CODEH         ; push CODEH
        PHA
        LDA CODE          ; push CODE
        PHA
        LDA $02           ; ToL   (15b)
        PHA
        LDA $03           ; ToH
        PHA
        LDA $05           ; StH
        PHA
        LDA $04           ; StL
        PHA
        LDA $06           ; Vofs
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

        ; assign Args[0] to var ofs (A)
        ; used by OP_LET, OP_FOR, OP_INPUT
setv    TAX               ; as index (10b)
        LDA Args          ; Args[0]
        STA IVar,X        ; low byte
        LDA Args+1        ; 
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
print   LDX #0            ; Sep=0
prins   LDA (CODE),Y      ; [5] read code
        BPL prsym         ; [2] -> letter/symbol
        CMP #OP_STMT      ; [2] next stmt/line? ($C0)
        BCS prend         ; [2] -> end print [+1]
        ; print expr
prexp   JSR expr          ; evaluate expression -> Args[0]
        JSR prnum         ; print Args[0] (uses A,X,B,C,F,Src,Dst) -> EQ
        LDA #0            ; TEMP
        STA ArgTop        ; TEMP pop Args[0]
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
prcom   LDA RemX          ; remaining space                            ; XXX field-width control?
        AND #7            ; 8 spaces
        BNE prcml         ; -> more spaces
prsem   INX               ; Sep=1
        BNE prins         ; -> always


        ; OP_NEXT (pop frame) (20b)
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

        ; OP_NEXT         (65b)
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


egos    LDY #<msg_gos
        DB $2C            ; BIT abs
efor    LDY #<msg_for     ; "?FOR"
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
popcd   PLA
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
tone    JSR exp2         ; stack: (Pitch,Duration) <-
        ;                                                                     XXX need TONE !!!
        JMP colon         ; -> colon


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
        STX F             ; [3] set high (F)
        CMP #OP_INT1      ; [2]
        BEQ xint1         ; [2] -> 1-byte int [+1]
        BCS xint2         ; [2] -> 2-byte int [+1]
        ; single-digit
xint0   AND #15           ; [2] low 4 bits (CC)
        BCC xpush         ; [3] -> push XA // [15+12+28=55]

        ; OP_INT2
xint2   CMP #OP_INT2      ; [2] guard
        BNE xsyn1         ; [2] -> bad code (CS)
        LDA (CODE),Y      ; [5] high (big-endian)
        STA F             ; [3] set high (F)
        INY               ; [2] high
xint1   LDA (CODE),Y      ; [5] low (CS)
        INY               ; [2] low (NE)
        BNE xpush         ; [3] -> push XA // [INT1:19+12+28=59 INT2:34+12+28=74]

        ; `=` expr
eqexp   LDA (CODE),Y
        CMP #OP_EQ
        BNE xsyn1
        INY
        BNE expr          ; always (Y>0)

        ; expr `,` expr
exp2    JSR expr          ; [6] -> Args
        LDA (CODE),Y      ; [5] next byte
        CMP #44           ; [2] is comma?
        BNE xsyn1         ; [2] -> syntax error
        INY               ; [2] comma
        ; +++ fall through: expr +++

        ; evaluate an expression [pre:36 ifx:51 var:82 num:55/59/74]
expr    LDA (CODE),Y      ; [5]
        JSR dbgx          ; DEBUG
        TAX               ; DEBUG test
        BPL xvar          ; [2] -> var name [+1]
        CMP #OP_INFX      ; [2] prefix? (before infix)
        BCC xpshy         ; [2] -> prefix, push [+1]
        CMP #OP_SUB       ; [2] unary minus?
        BNE xnumb         ; [2] -> no, number [+1]
        LDA #OP_NEG       ; [2] OP_SUB -> OP_NEG
        ; +++ fall through: xpshy +++

        ; push operator
xpshy   INY               ; [2] advance
xpsho   LDX OpTop         ; [3] stack ptr                      XXX use full asc (extra INX)
        CPX #OprsE        ; [2] end of stack
        BCS xbig          ; [2] -> "?BIG"
        STA Oprs,X        ; [4] push operator index [zp,X]
        INC OpTop         ; [5] zp
        BNE expr          ; [3] -> always // [19]

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
        STA F             ; [3] set high (F)
        LDA IVar,X        ; [4] low (A) // [46+8=54][28]=82 xx
        ; +++ fall through: xpush +++

        ; push FA to Arg stack
xpush   LDX ArgTop        ; [3] stack (ascending empty)         XXX use full asc (pre-inc)
        CPX #ArgsE        ; [2] end of stack
        BCS xbig          ; [2] -> "?BIG"
        STA Args,X        ; [4] low (A) [zp,X]
        LDA F             ; [3] high (F)
        STA Args+1,X      ; [4] high [zp,X]
        INX               ; [2] advance stack
        INX               ; [2]
        STX ArgTop        ; [3] // [28]
        ; +++ fall through: xinf +++

        ; infix operator or eol
xinf    LDA (CODE),Y      ; [5] read operator         C0
        JSR dbgx          ; DEBUG
        SEC               ; [2]
        SBC #OP_INFX      ; [2] map infix to 0
        CMP #OP_NIFX      ; [2] is it infix?
        BCS xend          ; [2] -> no, end expr or OP_RPAR
        TAX               ; [2] as index
        LDA preci,X       ; [4] infix precendence (X=0-12)
xopsp   STA B             ; [3] save precedence
        ; pop/apply higher precedence (loop)
xoplp   LDX OpTop         ; [3] empty ascending
        BEQ xinfp         ; [2] -> stack empy [+1]               XXX use BMI (full asc)
        DEX               ; [2] down to top
        LDA Oprs,X        ; [4] get top OP [zp,X]        OP_NEG
        TAX               ; [2] X=OP
        LDA prec-$80,X    ; [4] top precendence (X=$80-$92)   7
        CMP B             ; [3] top-prec >= new-prec?         0
        BCS xopdo         ; [2] -> do top operator
        ; push infix operator
xinfp   LDA (CODE),Y      ; [5] re-read operator
        TAX               ; [2] save X=operator
        SEC               ; [2]
        SBC #OP_INFX      ; [2] map infix to 0
        CMP #OP_NIFX      ; [2] is it infix?
        BCS xret          ; [2] -> no, return
        INY               ; [2] advance CODE
        TXA               ; [2] restore A=operator
        JMP xpsho         ; [3] -> push it // [32+19=51]
xret    RTS

xsyn    JMP esyn          ; -> syntax error
        DB $2C            ; BIT abs
xbig    LDY #<msg_big
        JMP erro

        ; apply operator  (X=OP)
xopdo   DEC OpTop         ; [5] pop
        LDA OpJp-$80,X    ; [4] routine offset (X=$80-$92)
        STA JmpOp         ; [3] set jump
        LDX ArgTop        ; [3] X=ArgTop (for operators)
        JMP (JmpOp)       ; [3] -> do operator

        ; end of expr or OP_RPAR
xend    LDA #0            ; [2] prec = 0
        BEQ xopsp         ; [2] -> set precendence (pop/apply all)


        ; --- OPERATORS (PAGE) ---

        ; XXX OR, RND, MUL, DIV don't fit..

xoppg   = BasROM+$600

        ; OP_IDX
        ; prefix `@(`     (41b)
xidx    DEX               ; ArgTop (empty ascending)
        DEX
        ASL Args,X        ; index * 2
        ROL Args+1,X
        BCS xnum          ; was negative
        LDA Args,X
        ADC TopL          ; CC
        STA Src
        LDA Args+1,X
        ADC TopH
        STA SrcH
        CMP MemSz
        BCS xnum          ; out of bounds
        STY F
        LDY #0
        LDA (Src),Y       ; read array
        STA Args,X        ; replace index
        INY
        LDA (Src),Y
        STA Args+1,X
        LDY F
        ; +++ fall through: OP_LPAR +++

        ; OP_LPAR
xlpr    LDA (CODE),Y      ; [5] re-read operator
        CMP #OP_RPAR      ; [2] is it `)`?
        BNE xsyn          ; [2] -> no, missing `)`
        INY               ; [2] skip `)`
        JMP xinf          ; [3] -> expect infix

xnum    LDY #<msg_num
        JMP erro

        ; OP_ABS
xabs    LDA Args-1,X      ; [4] right high
        BPL xnxop         ; [2] -> positive [+1] // 4b
        ; +++ fall through: xneg +++

        ; OP_NEG
xneg    SEC               ; [2]
        LDA #0            ; [2] 0 - X
        SBC Args-2,X      ; [4] low byte
        STA Args-2,X      ; [4] result low
        LDA #0            ; [2] 
        SBC Args-1,X      ; [4] high byte
        STA Args-1,X      ; [4] result high
xnxop   JMP xoplp         ; [3] -> next oper // 16b

        ; OP_NOT
xnot    LDA Args-2,X      ; [4] low byte
        EOR #$FF          ; [2] invert
        STA Args-2,X      ; [4] result low
        LDA Args-1,X      ; [4] high byte
        EOR #$FF          ; [2] invert
        STA Args-1,X      ; [4] result high
        JMP xoplp         ; [3] -> next oper // 15b

        ; OP_PEEK
xpeek   LDA (Args-2,X)    ; [6] fetch byte
        STA Args-2,X      ; [4] result low
        LDA #0            ; [2]
        STA Args-1,X      ; [4] result high
        BEQ xnxop         ; [3] -> next oper // 10b

        ; OP_SUB
xsub    SEC               ; [2]
        LDA Args-4,X      ; [4] left low
        SBC Args-2,X      ; [4] right low
        STA Args-4,X      ; [4] result low
        LDA Args-3,X      ; [4] left high
        SBC Args-1,X      ; [4] right high
        STA Args-3,X      ; [4] result high
        BVS xnum          ; [2] overflow
        BVC xpop          ; [3] always // 17b [41]

        ; OP_ADD
xadd    CLC               ; [2]
        LDA Args-4,X      ; [4] left low
        ADC Args-2,X      ; [4] right low
        STA Args-4,X      ; [4] result low
        LDA Args-3,X      ; [4] left high
        ADC Args-1,X      ; [4] right high
        STA Args-3,X      ; [4] result high
        BVS xnum          ; [2] overflow
xpop    DEX               ; [2] // (10)
        DEX               ; [2]
        STX ArgTop        ; [3]
        JMP xoplp         ; [3] -> next oper // 22b [38]

        ; OP_EQ
xeq     LDA Args-4,X      ; left low
        CMP Args-2,X      ; right low
        BNE xfalse        ; -> not equal
        LDA Args-3,X      ; left high
        CMP Args-1,X      ; right high
        BNE xfalse        ; -> not equal // 12b
        ; +++ fall through: xtrue +++
        ;
xtrue   LDA #$FF
        DB $2C            ; BIT abs
xfalse  LDA #0
        STA Args-4,X      ; result low
        STA Args-3,X      ; result high
        JMP xpop          ; always // 12b

        ; OP_NE
xne     LDA Args-4,X      ; left low
        CMP Args-2,X      ; right low
        BNE xtrue         ; -> not equal
        LDA Args-3,X      ; left high
        CMP Args-1,X      ; right high
        BNE xtrue         ; -> not equal
        BEQ xfalse        ; equal // 14b

        ; Less/Greater
xltne   BVS xltV          ; -> overflow
xgtV    BMI xtrue         ; -> less    [greater]
        BPL xfalse        ; -> greater [less]
xgtne   BVS xgtV          ; -> overflow
xltV    BPL xtrue         ; -> greater [less]
        BMI xfalse        ; -> less    [greater]

        ; OP_LT
xlt     LDA Args-3,X      ; left high
        CMP Args-1,X      ; right high
        BNE xltne         ; -> not equal
        LDA Args-4,X      ; left low
        CMP Args-2,X      ; right low
        BCC xtrue         ; -> less
        BCS xfalse        ; -> gt/eq (always) // 14b

        ; OP_LE
xle     LDA Args-3,X      ; left high
        CMP Args-1,X      ; right high
        BNE xltne         ; -> not equal
        LDA Args-4,X      ; left low
        CMP Args-2,X      ; right low
        BCC xtrue         ; -> less
        BEQ xtrue         ; -> equal
        BNE xfalse        ; -> greater (always) // 16b

        ; OP_GT
xgt     LDA Args-3,X      ; left high
        CMP Args-1,X      ; right high
        BNE xgtne         ; -> not equal
        LDA Args-4,X      ; left low
        CMP Args-2,X      ; right low
        BCC xfalse        ; -> less
        BNE xtrue         ; -> greater
        BEQ xfalse        ; -> equal // 16b

        ; OP_GE
xge     LDA Args-3,X      ; left high
        CMP Args-1,X      ; right high
        BNE xgtne         ; -> not equal
        LDA Args-4,X      ; left low
        CMP Args-2,X      ; right low
        BCS xtrue         ; -> greater/equal
        BCC xfalse        ; -> less // 14b

        ; OP_AND
xand    LDA Args-4,X      ; [4] left high
        AND Args-2,X      ; [4] right high
        STA Args-4,X      ; [4] result high
        LDA Args-3,X      ; [4] left low
        AND Args-1,X      ; [4] right low
        STA Args-3,X      ; [4] result low
        JMP xpop          ; [3] always // 15b

        ; OP_OR
xor     LDA Args-4,X      ; [4] left high
        ORA Args-2,X      ; [4] right high
        STA Args-4,X      ; [4] result high
        LDA Args-3,X      ; [4] left low
        ORA Args-1,X      ; [4] right low
        STA Args-3,X      ; [4] result low
        JMP xpop          ; [3] always // 15b

        ; OP_RND
xrnd    LDA LFSH          ; [3]
        STA B             ; [3] 16
        ASL               ; [2]
        ASL               ; [2]
        TAX               ; [2]
        EOR B             ; [3] 14
        STA B             ; [3]
        TXA               ; [2]
        ASL               ; [2]
        TAX               ; [2]
        EOR B             ; [3] 13
        STA B             ; [3]
        TXA               ; [2]
        ASL               ; [2]
        ASL               ; [2]
        EOR B             ; [3] 11
        ASL               ; [2] -> CF
        ROL LFSL          ; [5] <- CF
        ROL LFSH          ; [5] // 28b
        ; modulo
        LDA LFSL          ; [5]
        STA Acc0          ; [3] dividend low
        LDA LFSH          ; [5]
        STA Acc1          ; [3] dividend high
        LDA Args-1,X      ; [4] low byte
        STA Term0         ; [3] divisor low
        LDA Args-2,X      ; [4] high byte
        STA Term1         ; [3] divisor high
        JSR div_u16       ; [6] Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
        LDA B             ; [3] remainder low
        STA Args-1,X      ; [4] result low
        LDA C             ; [3] remainder high
        STA Args-2,X      ; [4] result high
        JMP xnxop         ; [3] -> next oper // 30b -> 58b

        ; OP_DIV
xdiv    STX D             ; [2] save X=stack-ofs                            ; XXX signed division
        LDA Args-4,X      ; [4] left high
        STA Acc1          ; [3] dividend high
        LDA Args-3,X      ; [4] left low
        STA Acc0          ; [3] dividend low
        LDA Args-2,X      ; [4] right high
        STA Term1         ; [3] divisor high
        LDA Args-1,X      ; [4] right low
        STA Term0         ; [3] divisor low
        JSR div_u16       ; [6] Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
        LDX D             ; [2] restore X=stack-ofs
        LDA Acc0          ; [3] quotient low
        STA Args-3,X      ; [4] result low
        LDA Acc1          ; [3] quotient high
        STA Args-4,X      ; [4] result high
        JMP xpop          ; [3] always // 34b

        ; OP_MUL
xmul    STX D             ; [2] save X=ArgTop                           ; XXX signed multiply
        LDA Args-4,X      ; [4] left high
        STA Acc1          ; [3] multiplier high
        LDA Args-3,X      ; [4] left low
        STA Acc0          ; [3] multiplier low
        LDA Args-2,X      ; [4] right high
        STA Term1         ; [3] multiplicand high
        LDA Args-1,X      ; [4] right low
        STA Term0         ; [3] multiplicand low
        ; BC = Acc * Term
        LDA #0            ; [2]
        STA B             ; [3] B partial product low
        STA C             ; [3] C partial product high
        LDX #16           ; [2] 16 bit multiplier
        ; shift multiplier right, test low-bit
xmull   LSR Acc1          ; [5] 0 >> multiplier >> CF
        ROR Acc0          ; [5] CF >> multiplier >> CF
        BCC xmulz         ; [2] -> zero bit, no add [+1]
        ; partial += shifted multiplicand x low-bit of multiplier
        CLC               ; [2] sadly CF=1
        LDA B             ; [3] partial product
        ADC Term0         ; [3] partial += multiplicand
        STA B             ; [3]
        LDA C             ; [3] partial product
        ADC Term1         ; [3] partial += multiplicand
        STA C             ; [3]
        BCS err_ovf       ; [2] -> overflow
        ; shift multiplicand left (×2) into next higher place
xmulz   ASL Term0         ; [2] CF << multiplicand << 0
        ROL Term1         ; [5] XX << multiplicand << CF
        BCS err_ovf       ; [2] -> overflow (multiplicand)
        DEX               ; [2]
        BNE xmull         ; [3] -> continue
        LDX D             ; [2] restore X=stack-ofs
        LDA B             ; [3] product low
        STA Args-3,X      ; [4] result low
        LDA C             ; [3] product high
        STA Args-4,X      ; [4] result high
        JMP xpop          ; [3] always


; ----------------------------------------------------------------------
; Helpers

; @@ num_u16
; parse an unsigned 16-bit number
num_u16:         ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
  LDA #0         ; [2]
  STA Args       ; [3] clear Args[0]
  STA Args+1     ; [3]
  DEY            ; [2] for pre-increment
@loop:           ; -> 14+76+25 [115]
  INY            ; [2] pre-increment
  LDA LineBuf,Y  ; [4] get next char
  EOR #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS dvrt       ; [2] >= 10 -> done [+1]
  TAX            ; [2] save digit 0-9
; multiply Acc by 10
  ASL Args       ; [5] Acc = Acc*2 (=Val*2)
  ROL Args+1     ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  LDA Args       ; [3] Term = Acc (=Val*2)
  STA Src        ; [3] 
  LDA Args+1     ; [3]
  STA SrcH       ; [3]
  ASL Args       ; [5] Acc *= 2 (=Val*4)
  ROL Args+1     ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  ASL Args       ; [5] Acc *= 2 (=Val*8)
  ROL Args+1     ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  CLC            ; [2]
  TXA            ; [2] Acc += digit 0-9
  ADC Args       ; [3]
  BCC @noc       ; [2] -> no carry [+1]
  INC Args+1     ; [5]
  BEQ err_ovf    ; [2] -> unsigned overflow [+1]
@noc:
  ADC Src        ; [3] Acc += Term (=Val*2)
  STA Args       ; [3] Args[0]
  LDA Args+1     ; [3]
  ADC SrcH       ; [3]
  STA Args+1     ; [3]
  BCS err_ovf    ; [2] -> unsigned overflow
  BPL @loop      ; [2] -> no signed overflow, continue [+1]
err_ovf:
  JMP enumb      ; [3] -> report overflow

; @@ div_u16
; divide Acc = Acc / Term remainder BCD (long-division method)
div_u16:         ; Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
  LDA #0         ; 
  STA B          ; remainder = 0
  STA C          ; remainder = 0
  LDX #16        ; 16 bits
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
dvrt:
  RTS            ; return


        ; prefix
prec    DB 1       ; $80 OP_LPAR open parenthesis (OP_RPAR forces eval; ends pop/apply loop)
        DB 7       ; $81 OP_ABS absolute (tail OP_NEG)
        DB 7       ; $82 OP_NOT unary NOT
        DB 7       ; $83 OP_PEEK peek address (arg)
        DB 7       ; $84 OP_RND random number (arg: mod N)
        DB 7       ; $85 OP_NEG unary negate `-` (replaces OP_SUB)
        DB 1       ; $86 OP_IDX open parenthesis (OP_RPAR forces eval; ends pop/apply loop)
        ; infix
preci   DB 6       ; $87 OP_MUL
        DB 6       ; $88 OP_DIV
        DB 5       ; $89 OP_ADD
        DB 5       ; $8A OP_SUB
        DB 4       ; $8B OP_EQ
        DB 4       ; $8C OP_NE
        DB 4       ; $8D OP_LE
        DB 4       ; $8E OP_GE
        DB 4       ; $8F OP_LT
        DB 4       ; $90 OP_GT
        DB 3       ; $91 OP_AND
        DB 2       ; $92 OP_OR

        ; operator JMP offsets
OpJp    DB <xlpr   ; OP_LPAR open parenthesis (back to xinf)
        DB <xabs   ; OP_ABS absolute (tail OP_NEG)
        DB <xnot   ; OP_NOT unary NOT
        DB <xpeek  ; OP_PEEK peek address (arg)
        DB <xrnd   ; OP_RND random number (arg: mod N)
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

        ; find matching line (CS), or following line (CC)
        ; find Args[0] -> XA/Ptr (uses A,X,F)       (56b)
fndln   DEC ArgTop        ; pop Args[0]
        DEC ArgTop        ; pop
        STY B             ; save Y
        LDA #>ProgPg      ; start of BASIC program
        STA PtrH          ; set Ptr page
        LDY #0            ; Y=0
        STY Ptr           ; set Ptr ofs
fndlp   LDY #2            ; Y=2
        LDA (Ptr),Y       ; (OP_LN LnLo >LnHi< Len)
        DEY               ; Y=1 moved!
        PHA               ; DEBUG 
        JSR wrhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        LDA (Ptr),Y       ; DEBUG (OP_LN >LnLo< LnHi Len)
        JSR wrhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        PLA               ; DEBUG 
        BMI fndgt         ; -> end of program (negative line)
        CMP Args+1        ; equals high byte?
        BCC fndnx         ; -> line < target, next line
        BNE fndgt         ; -> line is > target, stop
        LDA (Ptr),Y       ; (OP_LN >LnLo< LnHi Len)
        CMP Args          ; equals low byte?
        BCC fndnx         ; -> line < target, next line
        BNE fndgt         ; -> line is > target, stop
        ; found the line
        SEC               ; CS=found
fndrt   LDX PtrH          ; X = addr high byte
        LDA Ptr           ; A = addr low byte
        LDY B             ; restore Y
        RTS               ; -> XA=ptr, CS
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

        ; print number in Args[0]
prnum   LDA #0            ; [2] (uses A,X,B,C,F,Src,Dst)
        PHA               ; [3] sentinel
        STA Term1         ; [3] divisor high byte (Dst)
        LDA #10           ; [2] divisor = 10
        STA Term0         ; [3] divisor low byte (Dst)
        LDA Args          ; [3] Args[0] low (copy Args[0] for LIST)
        STA Acc0          ; [3] set Acc0 (Src)
        LDA Args+1        ; [3] Args[0] high
        STA Acc1          ; [3] set Acc1 (Src)
prndv   JSR div_u16       ; [733] Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Src,Dst)
        LDA B             ; [3] remainder
        ORA #48           ; [2] 0-9 -> '0'-'9'
        PHA               ; [3] pushes once or more
        LDA Acc0          ; [3]
        ORA Acc1          ; [3]
        BNE prndv         ; [2] -> until zero [+1]
        PLA               ; [4]
prnpl   JSR wrch          ; [6] print it (uses A,X,F,Src,Dst) preserves Y
        PLA               ; [4]
        BNE prnpl         ; [2] -> until sentinel [+1]
prnrt   RTS               ; [6] -> prnum:EQ



; ------------------------------------------------------------------------------
; Memory Copy (37b)

        ; @@ mcopyb
        ; copy memory backwards from (Src) to (Dst) with XY=size
        ; assume (Dst > Src) but Src/Dst may overlap 
        ; uses (A,X,Y,B,Src,Dst)
cpyb    STX F             ; [3] page count
        ; advance to last page (13b, 19s)
        CLC               ; [2]
        LDA SrcH          ; [3] Src += A * 256
        ADC F             ; [3]
        STA SrcH          ; [3]
        LDA DstH          ; [3] Dst += A * 256
        ADC F             ; [2] no CLC (assume no 64K wrap)
        STA DstH          ; [3]
        ; begin copy
        TYA               ; [2] is Y=0?
        BEQ cpyblp        ; [2] -> Y=0, no partial page [+1]
        INC F             ; [5] pages++ for partial page
cpyblp  DEY               ; [2] count--
        LDA (Src),Y       ; [5] read byte (sets NE/EQ)
        STA (Dst),Y       ; [6] write byte
        TYA               ; [2] is count==0?
        BNE cpyblp        ; [3] -> until count=0 // [18]
        ; back one page
        DEC SrcH          ; [5] Src -= 256
        DEC DstH          ; [5] Dst -= 256
        DEC F             ; [5] pages-- (Y=0)
        BNE cpyblp        ; [2] -> until pages=0 [+1] // [+18]
        RTS               ; [6] 


dbgx    PHA
        JSR wrhx          ; DEBUG
        JSR wrsp
        PLA
        RTS


ALIGN 256
ProgPg = $   ; start of program memory

; ORG BasROM+$7FF
;   DB 0

; ins/del line
; "at line NNN"
; LOAD/SAVE
; TONE
; OP_SIZE (immediate, push)
