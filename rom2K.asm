; Frontier 2K BASIC
; Use `asm6` to compile: https://github.com/parasyte/asm6

BasROM   = $0200   ; 2K BASIC
ProgPg   = $0A00   ; start of program memory (constant)
End4K    = $10     ; end of 4KB memory (minimum RAM fitted)

; ------------------------------------------------------------------------------
; Monitor Routines

montr = $FE00
cls   = $FF05
home  = $FF17
tclr  = $FF24
cpyf  = $FF2E
rdln  = $FF50
wrnl  = $FF91
wrsp  = $FF9E
wrch  = $FFA0
prhx  = $FFE3

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

Src      = $C0        ; source pointer \ Scroll (PRINT/WRCH), CLS  [Term0]
SrcH     = $C1        ; source pointer | Tokenize (tkmat/num_val   [Term1]
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

TopPtr   = $D0        ; TOP of BASIC program, start of variables      (used in RT / EDIT)
TopPtrH  = $D1

; -- $D2-E7 free (22)

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
        ; detect memory   (27b)
        LDY #0            ; const
        TYA               ; A=0 (store non-match at $A0)
        LDX #$A0          ; highest RAM page (+1)
        STX PtrH          ; PtrL can be any ($00 from Monitor)
msetl   STA (Ptr),Y       ; write page number
        DEC PtrH          ; decr Ptr
        DEX               ; decr Page
        TXA               ; A = Page
        CPX #>ProgPg      ; stop above BASIC! ($0A)
        BNE msetl         ; -> until $00
mchkl   INC PtrH          ; incr Ptr
        INX               ; incr Page
        TXA               ; A = Page
        CMP (Ptr),Y       ; compare page number
        BEQ mchkl         ; -> until differs
        STX MemSize       ; set size of memory (in pages)
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
        STX ArgTop        ; reset Args stack
        STX OpTop         ; reset Oprs stack
        LDA #62           ; `>`
        JSR wrch          ; write char (A=char, uses A,X) preserves Y
        JSR rdln          ; read command or BASIC statement
        ; parse the line
        LDY #0            ; offset = 0
        STY EmitOfs       ; reset
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y (uses A,X,Src)
        STY D             ; line-no flag (NE=found)
        DEY               ; for INY
        ; tokenize the line
tkskp   INY               ; skip space
tokn    LDA #46           ; DEBUG (dot)
        JSR wrch          ; DEBUG
        LDA LineBuf,Y     ; next input char
        CMP #32           ; space?
        BEQ tkskp         ; -> skip it
        TAX               ; X=next-char (NE/EQ)
        BEQ tkeol         ; -> end of line
        EOR #64           ; '@' to 0
        CMP #27           ; 26 letters plus @
        BCS tksym         ; -> not a letter
        TAX               ; A-Z index (0-26)
        LDA kw_tab,X      ; look up KW offset (A-Z)
        ; match keyword
tkmat   TAX               ; as index
        STY B             ; save start of input
        DEY               ; set up input pos
        DEX               ; set up keyword pos
tkmlp   INY               ; pre-increment input pos
        INX               ; pre-increment keyword pos
tkmnx   LDA kwpg,X        ; next keyword char
        BMI tkfnd         ; -> found keyword (bit 7 set) [+1]
        CMP LineBuf,Y     ; does it match input?
        BEQ tkmlp         ; -> yes, next char [+1]
        ; find next keyword
tkmsk   INX               ; find end of this keyword
        LDA kwpg,X        ; check keyword byte
        BPL tkmsk         ; -> top bit clear, keep going [+1]
        INX               ; skip bit-7 byte
        LDY B             ; restore Y = start of input
        ASL               ; shift left bit-7 byte
        BMI tkmnx         ; -> bit 6 set, try next keyword [+1]
        ; no match found
        LDA LineBuf,Y     ; reload A=next-char, emit it
        INY               ; advance input
        BNE tkemt         ; -> emit it (always, skip $BF for caps)
tkfnd   AND #$BF          ; clear bit 6 (1011 1111)
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
tksym   CPX #34           ; "
        BEQ tkstr         ; -> String
        TXA               ; A=next-char
        EOR #48           ; make '0' be 0
        CMP #10           ; 10 digits
        BCC tknum         ; -> emit number
        LDA #<expr_ops    ; operator table
        BNE tkmat         ; -> ALWAYS match operators

        ; direct command
dcmd    LDA #OP_EOP       ; end of program
        JSR tkemi         ; terminate the line
        ;
debug   LDY #0            ; DEBUG
dbglp   LDA EmitBuf,Y     ; 
        JSR prhx          ; saves Y
        JSR wrsp          ; saves Y
        INY
        CPY EmitOfs       ; emit length
        BCC dbglp         ; -> less, loop
        JSR wrnl          ; DEBUG
        ; 
        LDA #>EmitBuf     ; page ($01)
        STA CODEH         ; set CODE page
        LDY #0            ; 
        STY CODE          ; set CODE ofs
        STY OpTop         ; clear operator stack
        STY ArgTop        ; clear args stack
        JMP stmtj         ; -> execute statement (at Y=0)

        ; copy a string (28b)
tkstr   TXA               ; A=next-char
tkstl   JSR tkemi         ; emit char (uses X=0; preserves A,Y; sets PL)
        INY               ; advance
        LDA LineBuf,Y     ; get next char
        BEQ tksyn         ; -> at end of line, missing quote
        CMP #34           ; is it `"`?
        BNE tkstl         ; -> no, loop (not a quote)
        ; found a quote
        CMP LineBuf+1,Y   ; is next char `"` ?
        BNE tkemt         ; -> end of string, emit closing quote
        ; double-quote
        JSR tkemi         ; emit `"` (uses X=0; preserves A,Y; sets PL)
        BPL tkstl         ; -> loop, second `"`

tksyn   JMP esyn          ; -> report error

        ; emit a number (45b)
tknum   JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
        STY B             ; save Y
        LDX #OP_INT2      ; OP_INT2
        LDY #2            ; 2 bytes
        LDA $01           ; high byte
        BNE tknmo         ; -> OP_INT2 + 2 bytes
        DEX               ; OP_INT1
        DEY               ; 1 byte
        LDA $00           ; low byte
        CMP #10           ; CS if >= 10
        BCS tknmo         ; -> OP_INT1 + 1 byte (CS)
        DEY               ; 0 bytes
        ORA #OP_I0        ; single-digit
        TAX               ;
tknmo   TXA               ; X=OP
tknlp   JSR tkemi         ; (uses X=0; preserves A,Y; PL)
        LDX $FF,Y         ; 2=$01, 1=$00, 0=$FF (relies on zp,Y wrap-around)
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
errl    JSR wrch          ; write char (A=char, uses A,X) preserves Y
        INY               ; 
        LDA msgs,Y        ; next char
        BPL errl          ; loop until >= $80
        JSR wrnl          ; new line (uses A,X) preserves Y
        JMP repl          ; -> always


; ------------------------------------------------------------------------------
; PAGE 1 - Statement Tokens

msgs = BasROM+$100
kwpg = BasROM+$100

; start-of-line
OP_EOP     = $80
OP_LN      = $81
OP_EOL     = $82     ; use BCC
OP_COLN    = $82
OP_EOS     = $83     ; use BCC
; keywords
OP_CLS     = $83
OP_CALL    = $84
OP_END     = $85
OP_FOR     = $86
OP_GOTO    = $87
OP_GOSUB   = $88
OP_IF      = $89
OP_INPUT   = $8A
OP_LET     = $8B
OP_LOAD    = $8C
OP_LIST    = $8D
OP_MON     = $8E
OP_NEXT    = $8F
OP_NEW     = $90
OP_PRINT   = $91
OP_POKE    = $92
OP_RETURN  = $93
OP_REM     = $94
OP_RUN     = $95
OP_SAVE    = $96
OP_TONE    = $97
OP_NSTMT   = $98     ; first non-stmt
; context keywords
OP_STEP    = $99
OP_TO      = $9A
OP_THEN    = $9B
; unary operators (highest precedence, evaluated post-fix, right-associative!)
OP_PRE     = $9C     ; first prefix operator:
OP_NPRE    = 6       ; number of prefix operators (includes OP_SUB)
OP_LPAR    = $9C     ; 0 open parenthesis (lowest [never forced to eval])
OP_NOT     = $9D     ; 6 unary NOT
OP_KEY     = $9E     ; 6 unary fn (arg)
OP_PEEK    = $9F     ; 6 unary fn (arg)
OP_RND     = $A0     ; 6 unary fn (arg)
; infix binary (from highest to lowest, left-associative)
OP_IFX     = $A1     ; first infix operator:
OP_NIFX    = 12      ; number of infix operators
OP_SUB     = $A1     ; 4 binary op (MUST be first: also OP_NEG)
OP_ADD     = $A2     ; 4 binary op
OP_MUL     = $A3     ; 5 binary op  LSR for prec
OP_DIV     = $A4     ; 5 binary op
OP_EQ      = $A5     ; 3 binary `=`
OP_NE      = $A6     ; 3 binary
OP_LT      = $A7     ; 3 binary `<`
OP_LE      = $A8     ; 3 binary
OP_GT      = $A9     ; 3 binary `>`
OP_GE      = $AA     ; 3 binary
OP_AND     = $AB     ; 2 binary op
OP_OR      = $AC     ; 1 binary op
; special case (not prefix or infix)
OP_RPAR    = $AD     ; close parenthesis (forces all ops to eval up to OP_LPAR [which always stops eval])
; numbers (non-operator)
OP_I0      = $C0     ; 1-byte (OP_I0 + [0-9])
OP_I9      = $C9     ; 1-byte
OP_INT1    = $CA     ; 1-byte (opc|int8)
OP_INT2    = $CB     ; 2-byte (opc|int16)

kws_at:
kws_a:
ex_and    DB "AND",      OP_AND      +0
kws_b:
kws_c:
kw_call   DB "CALL",     OP_CALL     +$40
kw_cls    DB "CLS",      OP_CLS      +0
kws_d:
kws_e:
kw_end    DB "END",      OP_END      +0
kws_f:
msg_for   ;
kw_for    DB "FOR",      OP_FOR      +0
kws_g:
kw_goto   DB "GOTO",     OP_GOTO     +$40
msg_gos   ;
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
kw_mon    DB "MON",      OP_MON      +0
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
kws_z     DB 0,0         ; tkmat needs two

expr_ops:
ex_mul    DB "*",       OP_MUL    +$40
ex_div    DB "/",       OP_DIV    +$40
ex_add    DB "+",       OP_ADD    +$40
ex_sub    DB "-",       OP_SUB    +$40
ex_eq     DB "=",       OP_EQ     +$40
ex_ne     DB "<>",      OP_NE     +$40
ex_lt     DB "<",       OP_LT     +$40
ex_le     DB "<=",      OP_LE     +$40
ex_gt     DB ">",       OP_GT     +$40
ex_ge     DB ">=",      OP_GE     +$40
ex_lp     DB "(",       OP_LPAR   +$40
ex_rp     DB ")",       OP_RPAR   +$40
ex_co     DB ":",       OP_COLN   +0
          DB 0,0        ; tkmat needs two

          ; messages
msg_syn   DB "SYN",$80
msg_num   DB "NUM",$80
msg_big   DB "BIG",$80
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
kwrvs = kwrev - OP_EOL
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
  DB (kw_mon - kwpg)     ; OP_MON
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
  DB (ex_not - kwpg)     ; OP_NOT
  DB (ex_key - kwpg)     ; OP_KEY
  DB (ex_peek - kwpg)    ; OP_PEEK
  DB (ex_rnd - kwpg)     ; OP_RND
  ; infix binary
  DB (ex_sub - kwpg)     ; OP_SUB
  DB (ex_add - kwpg)     ; OP_ADD
  DB (ex_mul - kwpg)     ; OP_MUL
  DB (ex_div - kwpg)     ; OP_DIV
  DB (ex_eq - kwpg)      ; OP_EQ
  DB (ex_ne - kwpg)      ; OP_NE
  DB (ex_lt - kwpg)      ; OP_LT
  DB (ex_le - kwpg)      ; OP_LE
  DB (ex_gt - kwpg)      ; OP_GT
  DB (ex_ge - kwpg)      ; OP_GE
  DB (ex_and - kwpg)     ; OP_AND
  DB (ex_or - kwpg)      ; OP_OR
  ; close paren
  DB (ex_rp - kwpg)      ; OP_RPAR


; @@ Statement Dispatch
; jump table (30 entries)
stmtl = stml - $80
stmth = stmh - $80
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
        DB <mon          ; OP_MON
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
        DB >mon          ; OP_MON
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
        STA $01
        DEY               ; Y=1
        LDA (Ptr),Y       ; (OP LnLo >LnHi< Len)
        STA $00
        JSR prnum         ; print Args[0] (uses A,X,B,C,F,Src,Dst)
        JSR wrsp          ; print space (A=char, uses A,X) preserves Y
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
lstnx   JSR wrnl          ; crlf
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

        ; OP_MON
mon     JMP montr         ; enter monitor


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
        STA TopPtrH
        LDA #4            ; (OP_EOP LnLo LhHi Len)
        STA TopPtr
        LDA #OP_EOP       ; end of program ($80)
        STA ProgPg        ; OP_EOP
        STA ProgPg+1      ; negative line number (EOP mark)
        STA ProgPg+2      ; $8080
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


        ; OP_IF
        ; evaluate condition, skip rest of line if false
        ; if true, check for implied GOTO (line number)
ifs     JSR expr          ; condition -> Args[0]
        LDA $00           ; test Args[0]
        ORA $01           ;
        BEQ skip          ; -> cond is false, skip rest of line
ifsl    LDA (CODE),Y      ; read code
        INY               ; assume match
        CMP #OP_THEN      ; "THEN"?
        BNE stmtj         ; -> next stmt (no colon)
        DEY               ; undo
        CMP #OP_I0        ; is it a number?
        BCS goto          ; -> implied GOTO
        BNE stmtj         ; -> next stmt (no colon)


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
        BEQ line          ; [2] -> next line [+1]
        CMP #OP_EOP
        BEQ lstx          ; -> to REPL
        BNE esyn
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
        JSR prhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        JSR wrnl          ; DEBUG (uses A,X,F,Src,Dst) -> X=0
        PLA               ; DEBUG
        BPL let           ; [2] -> implied LET [+1]
        INY               ; [2] advance code
        ; guard [+4 cycles]
        CMP #OP_NSTMT     ; [2] non-statement?
        BCS esyn          ; [2] -> bad code
        ; token dispatch
        TAX               ; [2]
        LDA stmtl,X       ; [4]
        STA Src           ; [3] PHA
        LDA stmth,X       ; [4]
        STA SrcH          ; [3] PHA
        JMP (Src)         ; [5] RTS // [34] [colon +15]

;;colx    CMP #OP_EOP       ; is it OP_EOP?
;;        BNE esyn          ; -> no, syntax error [+1]
;;        JMP repl          ; -> end of program


        ; OP_LET or implied
        ; assign VAR[(N)] = Expr
let     JSR findv         ; find [@-Z] var -> ofs (A)      XXX common A(N) -> Ptr (3 callers)
        PHA               ; push var ofs
        LDA (CODE),Y      ; read code
        CMP #OP_EQ        ; `=`
        BNE esyn          ; -> syntax error
        INY               ; `=`
        JSR expr          ; -> Args[0]
        PLA               ; pop var ofs
        JSR setv          ; assign Args[0]
        JMP colon         ; -> colon


        ; find [@-Z] var -> ofs (A)
        ; used by OP_LET, OP_DIM*, OP_READ, OP_INPUT, OP_FOR, Expr (11b)
findv   LDA (CODE),Y      ; [5] read code
        EOR #64           ; [2] 64->0
        CMP #27           ; [2] @-Z
        BCS esyn          ; [2] -> syntax error
        ASL               ; [2] ofs = [@-Z] x 2
        INY               ; [2] for var
        RTS               ; [6] -> NE // [21]

        ; assign Args[0] to var ofs (A)
        ; used by OP_LET, OP_FOR, OP_INPUT
setv    TAX               ; as index (10b)
        LDA $00           ; Args[0]
        STA IVar,X        ; low byte
        LDA $01           ; 
        STA IVar+1,X      ; high byte
        RTS


        ; OP_GOTO
goto    JSR expr          ; -> Args[0]
goln    JSR fndln         ; find line (Args[0] -> XA/Ptr, CS=found)
        BCC enum1         ; -> not found
        STX CODEH
        STA CODE
        LDY #4            ; skip (OP_LN,LnL,LnH,Len,><)
        BNE stmtj         ; expect stmt (Y=4)


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


enum1   LDY #<msg_num
        DB $2C            ; BIT abs
esyn    LDY #<msg_syn
        JMP erro


        ; OP_INPUT
inpnx   INY               ; comma
input   JSR findv         ; find [@-Z] var -> A=ofs       XXX common A(N) -> Ptr
        PHA               ; PUSH var index
        STY B             ; save CODE ofs
        ; print var/str
inprt   LDA #63           ; '?'
        JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
        JSR rdln          ; read input (uses A,X,Y,B,C) -> Y=length
        LDY #0            ; Y = input ofs
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
        CPY #0            ; consumed input?
        BEQ inprt         ; -> no, retry
        PLA               ; POP var index
        JSR setv          ; assign Args[0] to var A=ofs
        LDY B
        LDA (CODE),Y      ; read code
        CMP #44           ; comma
        BEQ inpnx         ; -> again                    XXX string prompt; suppress '?' with semi


        ; OP_POKE
poke    JSR exp2          ; $00 = Addr, $02 = Byte
        LDA $02           ; byte
        LDX #0
        STA ($00,X)       ; write to memory
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
callj   JMP ($00)         ; jump to Args[0]


        ; OP_FOR          (75b)
        ; TAG_FOR Vofs StL StH ToH ToL CoH CoL CoY (9 bytes)
for     JSR findv         ; find var -> A=ofs
        STA $06           ; save var ofs
        LDA (CODE),Y
        CMP #OP_EQ        ; `=`
        BNE esyn          ; -> syntax error
        INY
        JSR expr          ; start expression -> $00-01
        LDA $06           ; get var ofs
        JSR setv          ; assign Args[0] to var ofs (A)
        ; expect "TO"
        LDA (CODE),Y
        CMP #OP_TO        ; "TO"
        BNE esyn          ; -> syntax error
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


        ; OP_PRINT        (89b)
prnl    JSR wrnl          ; newline (uses A,X,F,Src,Dst)
print   LDA (CODE),Y      ; [5] read code
        BPL prsym         ; [2] -> var name
        CMP #OP_EOS       ; [2] end of stmt?
        BCC prend         ; [2] -> end print [+1]
        ; print number
prexp   JSR expr          ; evaluate expression -> Args[0]
        JSR prnum         ; print Args[0] (uses A,X,B,C,F,Src,Dst) -> EQ
        LDA #0
        STA ArgTop        ; pop Args[0]
        BEQ print         ; -> always
        ; symbol or alpha
prsym   CMP #64           ; letter?
        BCS prexp         ; -> yes [+1]
        INY               ; advance
        CMP #34           ; `"`
        BEQ prstr         ; -> string
        CMP #44           ; `,`?
        BEQ prcom         ; -> comma
        CMP #59           ; `;`?
        BEQ print         ; -> semi
        CMP #39           ; `'`?
        BEQ prnl          ; -> new line
        DEY               ; undo advance
        ; assume colon
prend   DEY               ; go back one
        LDA (CODE),Y      ; test semi (+8b)
        INY               ; go fwd one
        CMP #59           ; `;`?
        BEQ prret         ; -> no CRLF
        JSR wrnl          ; write newline (uses A,X,F,Src,Dst)
prret   JMP colon         ; -> colon
        ; print string
prdqt   INY               ; skip second `"`
prstl   JSR wrch          ; print it
prstr   LDA (Ptr),Y       ; read code
        BMI esyn1         ; -> bad code (guard)
        INY               ; advance
        CMP #34           ; `"`
        BNE prstl         ; -> loop
        CMP (Ptr),Y       ; is next char `"`?
        BEQ prdqt         ; -> skip quote, loop
        BNE print         ; -> always
        ; comma
prcml   JSR wrsp          ; write a space
prcom   LDA RemX          ; remaining space                            ; XXX field-width control
        AND #7            ; 8 spaces
        BNE prcml         ; -> more spaces
        BEQ print         ; -> always


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
        STA B             ; save var ofs
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
        JSR prhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        LDA (Ptr),Y       ; DEBUG (OP_LN >LnLo< LnHi Len)
        JSR prhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        PLA               ; DEBUG 
        BMI fndgt         ; -> end of program (negative line)
        CMP $01           ; equals high byte?
        BCC fndnx         ; -> line < target, next line
        BNE fndgt         ; -> line is > target, stop
        LDA (Ptr),Y       ; (OP_LN >LnLo< LnHi Len)
        CMP $00           ; equals low byte?
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

        ; prefix   (6)
prec    DB 0       ; 9D OP_LPAR open parenthesis (lowest [never forced to eval])
        DB 6       ; 9E OP_NOT unary NOT
        DB 6       ; 9F OP_KEY test key (arg)
        DB 6       ; A0 OP_PEEK peek address (arg)
        DB 6       ; A1 OP_RND random number (arg: mod N)
        DB 6       ; A2 OP_NEG unary negate `-` (replaces OP_SUB)
        ; infix    (12)
        DB 4       ; A3 OP_SUB
        DB 5       ; A5 OP_MUL
        DB 5       ; A6 OP_DIV
        DB 4       ; A4 OP_ADD
        DB 3       ; A7 OP_EQ
        DB 3       ; A8 OP_NE
        DB 3       ; A9 OP_LT
        DB 3       ; AA OP_LE
        DB 3       ; AB OP_GT
        DB 3       ; AC OP_GE
        DB 2       ; AD OP_AND
        DB 1       ; AE OP_OR

        ; prefix -> push it -> expect another expr
        ; var/int -> require infix or eol
        ; infix -> pop/apply higher prec -> push it -> expect another expr
        ;          eol -> pop/apply higher all -> ret

        ; expr `,` expr
exp2    JSR expr          ; [6] -> Args
        LDA (CODE),Y      ; [5] next byte
        CMP #44           ; [2] is comma?
        BNE xsyn          ; [2] -> syntax error
        INY               ; [2] comma
        ; +++ fall through: expr +++

        ; evaluate an expression [pre:36 ifx:51 var:82 num:55/59/74]
expr    LDA (CODE),Y      ; [5]
        BPL xvar          ; [2] -> var name [+1]
        CMP #OP_I0        ; [2] >= $C0
        BCS xint          ; [2] -> number [+1]
        SBC #OP_PRE+1     ; [2] first prefix operator (+1 for CC)
        CMP #OP_NPRE      ; [2] number of prefix operators
        BCS xsyn          ; [2] -> not allowed // [17]
        ; +++ fall through: xphop +++

        ; push operator
xphop   LDX OpTop         ; [3] stack ptr
        CPX #OprsE        ; [2] end of stack
        BCS xbig          ; [2] -> "?BIG"
        STA Oprs,X        ; [4] push operator index [zp,X]
        INC OpTop         ; [5] zp
        BNE expr          ; [3] -> always, var/int/prefix // [19]

        ; variable        (14b)
xvar    JSR findv         ; [6][21] -> A=ofs (or syntax error)
        TAX               ; [2] as index
        LDA (CODE),Y      ; [5]
        CMP #40           ; [2] '('
        BEQ xidx          ; [2] -> array index
        LDA IVar+1,X      ; [4] high [zp,X]
        STA F             ; [3] set high (F)
        LDA IVar,X        ; [4] low (A) // [46+8=54][28]=82
        ; +++ fall through: xpush +++

        ; push XA to Arg stack
xpush   LDX ArgTop        ; [3] stack (ascending empty)
        CPX #ArgsE        ; [2] end of stack
        BCS xbig          ; [2] -> "?BIG"
        STA $00,X         ; [4] low (A) [zp,X]
        LDA F             ; [3] high (F)
        STA $01,X         ; [4] high [zp,X]
        INX               ; [2] advance stack
        INX               ; [2]
        STX ArgTop        ; [3] // [28]
        ; +++ fall through: xinf +++

        ; infix operator or eol
        ; pop/apply higher prec -> xphop (push it)
xinf    LDA (CODE),Y      ; [5] read code
        SEC               ; [2]
        SBC #OP_IFX       ; [2] first infix
        CMP #OP_NIFX      ; [2] is it infix?
        BCS xend          ; [2] -> no, end expr
        INY               ; [2]
        ADC #OP_NPRE      ; [2] map above prefix (for prec)
        PHA               ; [3] save A=operator
        TAX               ; [2] as index
        LDA prec,X        ; [4] get precedence
        STA F             ; [3] save precedence                  XXX use X and Y to simplify?
xifpl   LDX OpTop         ; [3] stack top
        BEQ xinfp         ; [2] -> stack empy [+1]
        LDA Oprs,X        ; [4] get top [zp,X]
        ;; another level of indirection:
        ;; get precedence for stack entry                        XXX finish pop/apply !!!
        ;; pop/apply higher prec
xinfp   PLA               ; [3] restore A=operator
        JMP xphop         ; [3] -> push it // [32+19=51]         XXX impl ABS, RND, PEEK, KEY !!!

xend    ; pop/apply all remaining                                XXX impl + - * / = <> > < >= <= AND OR NOT !!!
        RTS

xsyn    JMP esyn          ; -> syntax error


xbig    LDY #<msg_big
        JMP erro

xidx    INY               ;
        JSR expr          ; nested expr?!
        LDA (CODE),Y
        CMP #41           ; ')'
        BNE xsyn          ; -> syntax error
        INY
        ; ASL,ROR expr BCS oob
        ; CMP ArrSz,X      ; bounds check
        ; ADC Arg[Top]+ArrPt[X] -> Src
        ; A=(Src) X=(Src+1)
        ; -> xpush


        ; OP_In, OP_INTn    (29b)
xint    INY               ; [2]
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
        BNE xsyn          ; [2] -> bad code (CS)
        LDA (CODE),Y      ; [5] high (big-endian)
        STA F             ; [3] set high (F)
        INY               ; [2]
xint1   LDA (CODE),Y      ; [5] low (CS)
        INY               ; [2] (NE)
        BNE xpush         ; [3] -> push XA // [INT1:19+12+28=59 INT2:34+12+28=74]



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

        ; print number in Args[0]
prnum   LDA #0         ; [2] (uses A,X,B,C,F,Src,Dst)
        PHA            ; [3] sentinel
        STA Term1      ; [3] divisor high byte (Dst)
        LDA #10        ; [2] divisor = 10
        STA Term0      ; [3] divisor low byte (Dst)
        LDA $00        ; [3] Args[0] low (copy Args[0] for LIST)
        STA Acc0       ; [3] set Acc0 (Src)
        LDA $01        ; [3] Args[0] high
        STA Acc1       ; [3] set Acc1 (Src)
prndv   JSR div_u16    ; [733] Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Src,Dst)
        LDA B          ; [3] remainder
        ORA #48        ; [2] 0-9 -> '0'-'9'
        PHA            ; [3] pushes once or more
        LDA Acc0       ; [3]
        ORA Acc1       ; [3]
        BNE prndv      ; [2] -> until zero [+1]
        PLA            ; [4]
prnpl   JSR wrch       ; [6] print it (uses A,X,F,Src,Dst) preserves Y
        PLA            ; [4]
        BNE prnpl      ; [2] -> until sentinel [+1]
prnrt   RTS            ; [6] -> prnum:EQ


; @@ num_u16
; parse an unsigned 16-bit number
num_u16:         ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
  LDA #0         ; [2]
  STA $00        ; [3] clear Args[0]
  STA $01        ; [3]
  DEY            ; [2] for pre-increment
@loop:           ; -> 14+76+25 [115]
  INY            ; [2] pre-increment
  LDA LineBuf,Y  ; [4] get next char
  EOR #48        ; [2] make '0' be 0
  CMP #10        ; [2]
  BCS prnrt      ; [2] >= 10 -> done [+1]
  TAX            ; [2] save digit 0-9
; multiply Acc by 10
  ASL $00        ; [5] Acc = Acc*2 (=Val*2)
  ROL $01        ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  LDA $00        ; [3] Term = Acc (=Val*2)
  STA Src        ; [3] 
  LDA $01        ; [3]
  STA SrcH       ; [3]
  ASL $00        ; [5] Acc *= 2 (=Val*4)
  ROL $01        ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  ASL $00        ; [5] Acc *= 2 (=Val*8)
  ROL $01        ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  CLC            ; [2]
  TXA            ; [2] Acc += digit 0-9
  ADC $00        ; [3]
  BCC @noc       ; [2] -> no carry [+1]
  INC $01        ; [5]
  BEQ err_ovf    ; [2] -> unsigned overflow [+1]
@noc:
  ADC Src        ; [3] Acc += Term (=Val*2)
  STA $00        ; [3] Args[0]
  LDA $01        ; [3]
  ADC SrcH       ; [3]
  STA $01        ; [3]
  BCC @loop      ; [2] -> no overflow, continue [+1]
err_ovf:
  JMP enumb      ; [3] -> report overflow



; ----------------------------------------------------------------------
; Integer Multiply / Divide

; @@ mul_u16
; multiply BCD = Acc * Term (24-bit)
mul_u16:         ; Acc=multiplier Term=multiplicand -> BC=product (uses A,X,B,C,Acc,Term)
  LDA #0         ; [2]
  STA B          ; [3] B partial product
  STA C          ; [3] C partial product
  LDX #16        ; [2] 16 bit multiplier
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
  LDA #0         ; 
  STA B          ; remainder = 0
  STA C          ; remainder = 0
  LDX #16        ; 16 bits
  ;;STY F          ; save code ofs
  ;;LDY ArgTop     ; argument stack (empty)
  ;;LDA $FC,Y      ; SP-4 (dividend low)
  ;;STA Acc0       ; copy to Acc0
  ;;LDA $FD,Y      ; SP-3 (dividend high)
  ;;STA Acc1       ; copy to Acc1
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
  ;;LDY F          ; restore code ofs
  RTS            ; return


; ------------------------------------------------------------------------------
; Memory Copy

; @@ mcopyb
; copy memory backwards from (Src) to (Dst) with XY=size      (37b)
; assume (Dst > Src) but Src/Dst may overlap 
mcpyb:                   ; uses (A,X,Y,F,Src,Dst)
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


ORG BasROM+$7FF
  DB 0
