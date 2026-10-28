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

cls  = $FF05
home = $FF17
tclr = $FF24
cpyf = $FF2E
rdln = $FF50
wrnl = $FF91
wrsp = $FF9E
wrch = $FFA0
prhx = $FFE3

; ------------------------------------------------------------------------------
; Zero Page $00-BF - BASIC WORKSPACE

; -- $00-3F BASIC Arg Stack (64 bytes)

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
Data     = $B8    ; BASIC data pointer (next DATA statement)      (used in RT)
DataH    = $B9    ; 
DataY    = $BA
CODE     = $BB    ; BASIC code pointer (next instruction)         (used in RT / Direct)
CODEH    = $BC
FreePtr  = $BD    ; FREE space at end of variables                (used in RT / Direct / EDIT)
FreePtrH = $BE

EmitOfs  = OpTop  ; ALIAS: emit offset for tokenized code         (used in EDIT)

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
        LDX #$FF          ; X = $FF
        TXS               ; reset SP = $FF
        LDA #End4K        ; end of memory (page)                XXX detect memory
        STA MemSize       ; set size of memory (in pages)
        JSR cls           ; clear screen
        JMP new           ; init program -> jumps to repl

        ; return to repl
repl    LDA #62           ; `>`
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
dbglp   LDA EmitBuf,Y
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
        STY Data          ; clear data pointer  (should clear this only on code edits)
        STY DataH         ; clear data pointer  (along with all arrays)
        STY OpTop         ; clear operator stack
        STY ArgTop        ; clear args stack
        JMP stmt          ; -> execute statement

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

tksyn   LDY <msg_syn      ; syntax error
        BNE erro          ; -> report error


        ; emit a number (45b)
tknum   JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
        STY B             ; save Y
        LDX #OP_INT2      ; 
        LDY #2            ; 2 bytes
        LDA $01           ; high byte
        BNE tknmo         ; -> opcode + 2 bytes
        DEX               ; OP_INN1
        DEY               ; 1 byte
        CMP #$FF          ; high byte = $FF?
        BEQ tknmo         ; -> opcode + 1 byte
        DEX               ; OP_INT1
        LDA $00           ; low byte
        CMP #10           ; CS if >= 10
        BCS tknmo         ; -> opcode + 1 byte (CS)
        DEY               ; 0 bytes
        ORA #OP_I0        ; single-digit
        TAX               ;
tknmo   TXA               ; X=OP
tknlp   JSR tkemi         ; (uses X=0; preserves A,Y; PL)
        LDX $FF,Y         ; 2=$01, 1=$00, 0=$FF (wrap-around)
        TXA               ; 
        DEY               ; 2>1 1>0 0>FF
        BPL tknlp         ; -> until Y<0
        LDY B             ; restore Y
        JMP tokn          ; 


        ; emit code
        ; uses X; preserves A,Y -> NE,PL
tkemi   LDX EmitOfs       ; [3] get emit offset
        STA EmitBuf,X     ; [5] emit token
        INC EmitOfs       ; [5] advance emit offset (NE)
        BMI tkovf         ; [2] -> buffer overflow [+1] -> MI
        RTS               ; [6] -> NE,PL,X=EmitOfs-1 (for emit_str)

tkovf   LDY #<msg_ovf     ; "?OVF"
        JMP erro          ; -> report error

        ; report an error (Y=msg)
escap   LDY #<msg_esc     ; escape pressed
erro    LDA #63           ; `?`
        DEY               ; for INY
errl    JSR wrch          ; write char (A=char, uses A,X) preserves Y
        INY               ; 
        LDA msgs,Y        ; next char
        BPL errl          ; loop until >= $80
        JSR wrnl          ; new line (uses A,X) preserves Y
        JMP repl          ; -> always



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



; ------------------------------------------------------------------------------
; PAGE 5 - Statement Tokens

ORG BasROM+$200
msgs:
kwpg:

; start-of-line
OP_EOP     = $80
OP_LN      = $81
; keywords
OP_CLS     = $82
OP_CALL    = $83
OP_DATA    = $84
OP_DIM     = $85
OP_END     = $86
OP_FOR     = $87
OP_GOTO    = $88
OP_GOSUB   = $89
OP_IF      = $8A
OP_INPUT   = $8B
OP_LET     = $8C
OP_LOAD    = $8D
OP_LIST    = $8E
OP_NEXT    = $8F
OP_NEW     = $90
OP_PRINT   = $91
OP_POKE    = $92
OP_READ    = $93
OP_RESTORE = $94
OP_RETURN  = $95
OP_REM     = $96
OP_RUN     = $97
OP_SAVE    = $98
OP_TONE    = $99
OP_NSTMT   = $9A     ; first non-stmt
; context keywords
OP_STEP    = $9A
OP_TO      = $9B
OP_THEN    = $9C
; unary operators (highest precedence, evaluated post-fix, right-associative!)
OP_XOP     = $9D     ; first prefix operator:
OP_NEG     = $9D     ; 6 unary negate `-` (replaces OP_SUB)
OP_NOT     = $9E     ; 6 unary NOT
; unary functions (high precedence, evaluated post-fix, right-associative!)
OP_KEY     = $9F     ; 6 unary fn (arg)
OP_PEEK    = $A0     ; 6 unary fn (arg)
OP_RND     = $A1     ; 6 unary fn (arg)
; infix binary (from highest to lowest, left-associative)
OP_IOP     = $A2     ; first infix operator:
OP_MUL     = $A2     ; 5 binary op  LSR for prec
OP_DIV     = $A3     ; 5 binary op
OP_ADD     = $A4     ; 4 binary op
OP_SUB     = $A5     ; 4 binary op
OP_EQ      = $A6     ; 3 binary `=`
OP_NE      = $A7     ; 3 binary
OP_LT      = $A8     ; 3 binary `<`
OP_LE      = $A9     ; 3 binary
OP_GT      = $AA     ; 3 binary `>`
OP_GE      = $AB     ; 3 binary
OP_AND     = $AC     ; 2 binary op
OP_OR      = $AD     ; 1 binary op
; open paren (lowest precedence)
OP_LPAR    = $AE     ; 0 open parenthesis (lowest [never forced to eval], skips apply phase, always pushed)
OP_RPAR    = $AF     ; 0 close parenthesis (lowest, forces all ops to eval up to OP_LPAR [which always stops eval])
OP_NOP     = $B0     ; last operator (exclusive)
; numbers (non-operator)
OP_I0      = $C0     ; 1-byte (OP_I0 + [0-9])
OP_I9      = $C9     ; 1-byte
OP_INT1    = $CA     ; 1-byte (opc|int8) high byte $00
OP_INN1    = $CB     ; 1-byte (opc|int8) high byte $FF
OP_INT2    = $CC     ; 2-byte (opc|int16)

kws_at:
kws_a:
ex_and    DB "AND",      OP_AND      +0
kws_b:
kws_c:
kw_call   DB "CALL",     OP_CALL     +$40
kw_cls    DB "CLS",      OP_CLS      +0
kws_d:
msg_data  ;
kw_data   DB "DATA",     OP_DATA     +$40
kw_dim    DB "DIM",      OP_DIM      +0
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
kws_z     DB 0,0         ; tkmat needs two

expr_ops:
ex_mul    DB "*",       OP_MUL    +$40     ; operator  42
ex_div    DB "/",       OP_DIV    +$40     ; operator  47
ex_add    DB "+",       OP_ADD    +$40     ; operator  43
ex_sub    DB "-",       OP_SUB    +$40     ; operator  45
ex_eq     DB "=",       OP_EQ     +$40     ; operator  61
ex_ne     DB "<>",      OP_NE     +$40     ; operator  60 62
ex_lt     DB "<",       OP_LT     +$40     ; operator  60
ex_le     DB "<=",      OP_LE     +$40     ; operator  60 61
ex_gt     DB ">",       OP_GT     +$40     ; operator  62
ex_ge     DB ">=",      OP_GE     +$40     ; operator  62 61
ex_lp     DB "(",       OP_LPAR   +$40     ; operator  40
ex_rp     DB ")",       OP_RPAR   +0       ; operator  41
          DB 0,0        ; tkmat needs two


          ; messages
msg_syn   DB "SYN",$80
msg_ovf   DB "OVF",$80
msg_lin   DB "LINE",$80
msg_esc   DB "BRK",$80
msg_bad   DB "BAD",$80
msg_mem   DB "FULL",$80

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
stmt_rev:                     ; [34] indices MUST match OPCODEs
  DB (kw_cls - kwpg)     ; OP_CLS
  DB (kw_data - kwpg)    ; OP_DATA
  DB (kw_dim - kwpg)     ; OP_DIM
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
  DB (kw_read - kwpg)    ; OP_READ
  DB (kw_rest - kwpg)    ; OP_RESTORE
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
  DB (ex_not - kwpg)     ; OP_NOT
  DB (ex_sub - kwpg)     ; OP_NEG
  ; unary functions
  DB (ex_key - kwpg)     ; OP_KEY
  DB (ex_peek - kwpg)    ; OP_PEEK
  DB (ex_rnd - kwpg)     ; OP_RND
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
  ; open paren
  DB (ex_lp - kwpg)      ; OP_LPAR
  DB (ex_rp - kwpg)      ; OP_RPAR


; @@ Statement Dispatch
; jump table (30 entries)
stmtl = stml - $80
stmth = stmh - $80
stml:
  DB <repl         ; OP_EOP
  DB <line         ; OP_LN
  DB <clss         ; OP_CLS
  DB <call         ; OP_CALL
  DB <skip         ; OP_DATA
  DB <dims         ; OP_DIM
  DB <repl         ; OP_END
  DB <for          ; OP_FOR
  DB <goto         ; OP_GOTO
  DB <gosub        ; OP_GOSUB
  DB <ifs          ; OP_IF
  DB <input        ; OP_INPUT
  DB <let          ; OP_LET
  DB <do_load      ; OP_LOAD
  DB <list         ; OP_LIST
  DB <next         ; OP_NEXT
  DB <new          ; OP_NEW
  DB <do_print     ; OP_PRINT
  DB <poke         ; OP_POKE
  DB <read         ; OP_READ
  DB <resto        ; OP_RESTORE
  DB <retn         ; OP_RETURN
  DB <skip         ; OP_REM
  DB <run          ; OP_RUN
  DB <save         ; OP_SAVE
  DB <do_tone      ; OP_TONE
stmh:                                   
  DB >repl         ; OP_EOP
  DB >line         ; OP_LN
  DB >clss         ; OP_CLS
  DB >call         ; OP_CALL
  DB >skip         ; OP_DATA
  DB >dims         ; OP_DIM
  DB >repl         ; OP_END
  DB >for          ; OP_FOR
  DB >goto         ; OP_GOTO
  DB >gosub        ; OP_GOSUB
  DB >ifs          ; OP_IF
  DB >input        ; OP_INPUT
  DB >let          ; OP_LET
  DB >do_load      ; OP_LOAD
  DB >list         ; OP_LIST
  DB >next         ; OP_NEXT
  DB >new          ; OP_NEW
  DB >do_print     ; OP_PRINT
  DB >poke         ; OP_POKE
  DB >read         ; OP_READ
  DB >resto        ; OP_RESTORE
  DB >retn         ; OP_RETURN
  DB >skip         ; OP_REM
  DB >run          ; OP_RUN
  DB >save         ; OP_SAVE
  DB >do_tone      ; OP_TONE


; ------------------------------------------------------------------------------
; PAGE 5 - Commands

DB "CMD"

; @@ LIST
; display program listing
list    JSR expr          ; line number -> Args[0]
        JSR fndln         ; find matching line, or next (Args[0] -> XA/Ptr)
        STA D             ; low
        STX E             ; high
        LDA (CODE),Y      ; read code
        CMP #44           ; comma?
        BNE lsts          ; -> no, start listing
        INY               ; comma
        LDX #0            ; reset ArgTop (pop Args[0])
        STX ArgTop
        JSR expr          ; line number -> Args[0]
        JSR fndln         ; find matching line, or next (Args[0] -> XA/Ptr)
lsts    LDY #2            ; Y=2
        LDA (D),Y         ; (OP LnLo >LnHi< Len)
        BMI lstx          ; -> end of program (negative line)
        STA $01
        DEY               ; Y=1
        LDA (D),Y         ; (OP LnLo >LnHi< Len)
        STA $00
        JSR num_print     ; print Args[ArgTop] (uses A,X)
        JSR wrsp          ; print space (A=char, uses A,X) preserves Y
        LDY #4            ; skip header

lstx    JMP repl

save    JMP repl


; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

DB "RUN"

; control frame tags
TAG_FOR    = $F0
TAG_GOSUB  = $F1

; variable tags
VT_NONE = 0
VT_NUM = $80
VT_STR = $81
VT_NUM_ARR = $82

        ; OP_NEW
new     LDA #>BaseAdr     ; set top of program
        STA TopPtrH
        LDA #4            ; (OP_EOP LnLo LhHi Len)
        STA TopPtr
        LDA #OP_EOP       ; end of program ($80)
        STA BaseAdr
        LDA #$FF
        STA BaseAdr+2     ; negative line number (EOP mark)
        LDA #0
        STA BaseAdr+3     ; zero length (EOP mark)
        BNE lstx          ; JMP repl

        ; OP_RUN
        ; start running the BASIC program
run     LDA TopPtr        ; reset free space
        STA FreePtr
        LDA TopPtrH
        STA FreePtrH
        LDA #0            ; clear vars (9b)
        LDX #92           ; ArrPt(16),ArrSz(16),IVar(54),OpTop(1),ArgTop(1),Data(3),CODE(1)
runcl   STA ArrPt,X       ; clear
        DEX
        BPL runcl         ; -> loop
        TAY               ; CODE offset = 0
        LDA #>BaseAdr     ; start of BASIC program
        STA CODEH         ; set CODE page
        BNE stmt          ; -> start

        ; OP_IF
ifs     JSR expr          ; condition -> Args[0]
        LDA $00           ; test Args[0]
        ORA $01           ;
        BEQ skip          ; -> cond is false, skip rest of line
        LDA (CODE),Y      ; read code
        CMP #OP_NSTMT     ; is it a number/expr?
        BCS goto          ; -> implied GOTO
        BNE stmt          ; -> next stmt

        ; OP_REM
        ; OP_DATA
        ; advance to end of line
skip    LDY #3            ; (OP_LN,LnL,LnH,>Len<)
        LDA (CODE),Y      ; get line length
        TAY               ; set Y = line length (NE)
        BNE stmt          ; -> OP_LINE / OP_EOP

        ; OP_LINE
        ; start of line: fold Y into CODE.
line    TYA               ; [2] get accumulated Y
        LDY #4            ; [2] skip (OP,LnL,LnH,Len,><)
        CLC               ; [2]
        ADC CODE          ; [3] add Y to CODE
        STA CODE          ; [3] update CODE
        BCC stmt          ; [2] -> no overflow [+1]
        INC CODEH         ; [5]
        ; +++ fall through to @@ stmt +++

        ; STMT dispatch
stmt    LDA (CODE),Y      ; [5] load token
        PHA               ; DEBUG
        JSR prhx          ; DEBUG (uses A,X,F,Src,Dst) preserves Y
        JSR wrnl          ; DEBUG
        PLA               ; DEBUG
        BPL let           ; [2] -> implied LET [+1]
        INY               ; [2] advance CODE
        ; debug check [+4 cycles]
        CMP #OP_NSTMT     ; [2] check code
        BCS ebad          ; [2] -> bad code
        ; token dispatch
        TAX               ; [2]
        LDA stmtl,X       ; [4]
        STA Src           ; [3] PHA
        LDA stmth,X       ; [4]
        STA SrcH          ; [3] PHA
        JMP (Src)         ; [5] RTS // [30]

ebad    LDY #<msg_bad
        JMP erro

        ; OP_LET or implied
        ; assign VAR[$] = Expr
let     JSR findv         ; find [@-Z] var -> ofs (A)      XXX array assign
        PHA               ; save var ofs                   XXX common B(N) -> Ptr (4 callers)
        JSR expr          ; -> Args[0]
        PLA               ; pop var ofs
        JSR setv          ; assign Args[0]
        JMP stmt          ; -> next stmt

        ; assign Args[0] to var ofs (A)
setv    TAX               ; as index (10b)
        LDA $00           ; Args[0]
        STA IVar,X        ; low byte
        LDA $01           ; 
        STA IVar+1,X      ; high byte
        RTS

        ; find [@-Z] var -> ofs (10b)
findv   LDA (CODE),Y      ; read code
        EOR #64           ; 64->0
        CMP #27           ; [@-Z]
        BCS esyn0         ; -> syntax error
        INY               ; for var
        ASL               ; ofs = [@-Z] x 2
        RTS

        ; OP_GOTO
goto    JSR expr          ; -> Args[0]
goln    JSR fndln         ; find line (Args[0] -> XA, CS=found)
        BCC eline         ; -> not found
        STX CODEH
        STA CODE
        LDY #3            ; skip (LnL,LnH,Len)
        BNE stmt          ; always OP_LINE

        ; OP_GOSUB
gosub   JSR expr          ; -> Args[0]
        LDA CODE          ; 
        PHA               ; push CODE
        LDA CODEH         ; 
        PHA               ; push CODEH
        TYA               ;
        PHA               ; push Offset
        LDA #TAG_GOSUB    ; 
        PHA               ; push TAG
        BNE goln          ; -> ALWAYS

        ; OP_RESTORE
        ; Find specified line, set Data (READ does most of the work)
resto   JSR expr          ; -> Args[0]
        JSR fndln         ; find line, or next (Args[0] -> XA)
        BCC eline         ; -> not found
        STX DataH         ; pointer to next data, high
        STA Data          ; pointer to next data, low
        JMP stmt   

eline   LDY #<msg_lin
        BNE ej0

        ; OP_READ
        ; Data always points into the program (start of program, last RESTORE, last READ)
        ; @lp if (Data) >= $80 we're at eol; find next DATA line
        ; read num at (Data), assign to var, advance Data -> @lp
rdnxt   INY               ; comma (in Code)
read    JSR findv         ; find [@-Z] var (uses A) reads code -> ofs (A)      XXX common B(N) -> Ptr
        TAX               ; var ofs -> X
        STY D             ; save Y
        LDY DataY         ; data ofs
rdfnd   LDA (Data),Y      ; 
        INY               ; assume comma
        CMP #44           ; `,`
        BEQ rdfnd         ; -> skip comma
        DEY               ; undo
        CMP #OP_I0        ; number?
        BCC rdnon         ; -> non-number
        ; can't use expr (Data not CODE)          XXX evaluate number! (common with LIST)
        STA IVar,X        ; low byte
        INY               ;
        LDA (Data),Y      ; 
        STA IVar+1,X      ; high byte
        INY               ;
        STY DataY         ; save data ofs
        ; next var
        LDY D             ; restore Y = Code ofs
        LDA (CODE),Y      ; read code
        CMP #44           ; comma
        BEQ rdnxt         ; -> next var
        JMP stmt          ; -> next stmt
        ; find next DATA
rdnon   AND #$FE          ; clear low bit
        CMP #OP_LN        ; is it end of line? (OP_LN/OP_EOP)
        BNE esyn0         ; -> syntax error in DATA
rdskp   LDY #3            ; find next DATA line
        LDA (Data),Y      ; get Line length
        BEQ edata         ; -> out of data (end of program)
        CLC               ;
        ADC Data          ; Data += Y
        STA Data          ;
        BCC rdnpg         ; -> no page cross
        INC DataH         ;
rdnpg   INY               ; first opcode
        LDA (Data),Y      ; 
        CMP #OP_DATA      ; is it data?
        BNE rdskp         ; -> skip this line
        INY               ; OP_DATA
        BEQ rdfnd         ; -> match data

esyn0   LDY #<msg_syn
ej0     JMP erro
edata   LDY #<msg_data
        BNE ej0

        ; OP_INPUT
inpnx   INY               ; comma
input   JSR findv         ; find [@-Z] var (uses A) -> ofs (A)       XXX common B(N) -> Ptr
        PHA               ; PUSH var index
        STY B             ; save CODE ofs
        ; get input
        ; parse var(s)
        ; ask for more input if short
        ; parse more var(s)
inprt   LDA #63           ; '?'
        JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
        JSR rdln          ; read input (uses A,X,Y,B,C) -> Y=length
        LDY #0            ; Y = input ofs
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
        CPY #0            ; consumed input?
        BEQ inprt         ; -> no, retry
        PLA               ; POP var index
        JSR setv          ; assign Args[0] to var ofs (A)
        LDY B
        LDA (CODE),Y      ; read code
        CMP #44           ; comma
        BEQ inpnx         ; -> again                    XXX string prompt; suppress '?' with semi

        ; OP_POKE
poke    JSR ex2_u16       ; $00 = Addr, $02 = Byte
        LDA $02           ; byte
        LDX #0
        STA ($00,X)       ; write to memory
        JMP stmt          ; -> next stmt

        ; OP_CLS
clss    STY E             ; save CODE offset
        JSR cls           ; (uses A,X,Y)
        LDY E             ; restore CODE offset
        JMP stmt          ; -> next stmt

call    JSR expr          ; -> Args[0]
        STY E             ; save CODE offset
        JSR callj         ; 
        LDY E             ; restore CODE offset
        JMP stmt          ; -> next stmt
callj   JMP ($00)         ; jump to Args[0]

        ; OP_DIM          (56b)
dims    JSR findv         ; find var -> X=ofs            XXX raw VAR only
        CPX #16           ; beyond [@-G]?
        BCS esyn0         ; -> not a valid array
        LDA ArrPt+1,X     ; check high byte
        BNE esyn0         ; -> already DIM'd
        TXA
        PHA               ; save X=ofs
        JSR expr          ; -> dimension Args[0]
        ASL $00           ; CF << dim << 0
        ROL $01           ; OV << dim << CF
        BCS emem          ; -> out of memory
        PLA
        TAX               ; restore X=ofs
        LDA $00           ; dim size
        STA ArrSz,X       ; set size low
        LDA $01           ; dim size
        STA ArrSz+1,X     ; set size high
        LDA FreePtrH      ; free space
        STA ArrPt+1,X     ; set array low
        LDA FreePtr       ; free space
        STA ArrPt,X       ; set array high
        CLC
        ADC $00           ; add size low
        STA FreePtr       ; bump Free
        LDA FreePtrH      ; reload free high
        ADC $01           ; add size high
        STA FreePtrH      ; bump Free
        BCS emem          ; -> out of memory
        JMP stmt          ; -> next stmt

emem    LDY #<msg_mem
ej1     JMP erro

        ; OP_FOR          (74b)
for     JSR findv         ; find var -> X=ofs           XXX raw VAR only
        TXA
        PHA               ; push var ofs
        LDA (CODE),Y
        CMP #OP_EQ        ; `=`
        BNE esyn1         ; -> syntax error
        INY
        JSR expr          ; start expression -> Args+0
        PLA               ; A=var-ofs
        PHA               ; re-push
        JSR setv          ; assign Args[0] to var ofs (A)
        ; expect "TO"
        LDA (CODE),Y
        CMP #OP_TO        ; "TO"
        BNE esyn1         ; -> syntax error
        JSR expr          ; "TO" expression -> Args+2
        LDA $02
        PHA               ; low byte
        LDA $03
        PHA               ; high byte
        ; check for "STEP"
        LDA (CODE),Y      ; peek next byte
        CMP #OP_STEP      ; "STEP"
        BEQ forst         ; -> handle "STEP"
        LDA #1            ; push $0001
        PHA               ; low byte
        LDA #0
        PHA               ; high byte
forco   LDA CODE          ; 
        PHA               ; push CODE
        LDA CODEH         ; 
        PHA               ; push CODEH
        TYA               ;
        PHA               ; push Offset
        LDA #TAG_FOR      ;
        PHA               ; push TAG
        JMP stmt          ; -> next stmt
forst   INY               ; OP_STEP
        JSR expr          ; "STEP" expression -> Args
        LDA $04
        PHA               ; low byte
        LDA $05
        PHA               ; high byte
        JMP forco         ; -> continue FOR

esyn1   JMP esyn0
eovf    LDY #<msg_ovf
        BNE ej1

        ; OP_NEXT         ()
next    LDA (CODE),Y      ; (optional, can't use findv)      XXX raw VAR only, optional
        EOR #64           ; @->0
        CMP #27
        BCS nexf          ; -> find frame
        INY
        ASL
        ;;;                                                 XXX do something with var
nexf    STY F             ; save code ofs
        LDA #TAG_FOR
        JSR popfr         ; pop frames until TAG match
        TSX               ; get SP (>empty< TAG CoY CoH CoL StH StL ToH ToL Vofs)
        ; add STEP to Var
        LDY $109,X        ; Vofs
        LDA $106,X        ; StL                            XXX PLA is non-destructive..
        CLC               ;                                    need to re-order in FOR
        ADC IVar,Y        ; add Step to Var           (TAG Vofs StL StH ToH ToL CoH CoL CoY)
        STA IVar,Y        ; low
        LDA $105,X        ; StH
        ADC IVar+1,Y      ; add Step to Var
        STA IVar+1,Y      ; high
        BVS eovf          ; -> overflow
        ; compare TO
        CMP $107,X        ; var >= to? (high)
        BCC nexc          ; -> less, continue FOR
        BNE nexx          ; -> greater, exit FOR
        LDA IVar,Y        ; high equal, test low
        CMP $108,X        ; var >= to? (low)
        BCC nexc          ; -> less, continue FOR
        BEQ nexc          ; -> less, continue FOR
        ; exit FOR (CS)
nexx    TXA
        ADC #9-1          ; pop 9 items
        TAX
        TXS
        LDY F             ; save code ofs
        JMP stmt          ; -> next stmt
        ; continue FOR
nexc    LDA $103,X        ; CoH
        STA CODEH         ; set CODE
        LDA $104,X        ; CoL
        STA CODE          ; set CODE
        LDA $102,X        ; CoY
        TAY               ; set CODE offset
        JMP stmt          ; -> next stmt

; RETURN:
;       scan control stack for matching GOSUB frame;
;       pop GOSUB frame and restore Code address;
;       jump to STMT loop
retn    LDA #TAG_GOSUB
        JSR popfr         ; pop frames until TAG match
        PLA               ; TAG
popcd   PLA               ; restore saved CODE address
        STA CODE          ; restore CODE
        PLA
        STA CODEH         ; restore CODEH
        PLA
        TAY               ; restore CODE ofs
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



; LOAD <string>
do_load:
  ; if running -> do_run
  ; else -> repl
  JMP repl         ; -> back to REPL


e_syn1:
  LDY #<msg_syn
  JMP erro



; --- TONE ---

do_tone:
  JSR ex2_u16      ; stack: (Pitch,Duration) <-
  ; XXX
  JMP stmt   



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

        ; find frame -> X=SP
popfr   TSX
        RTS



        ; find matching line (CS), or following line (CC)
        ; find Args[0] -> XA/Ptr (uses A,X,F)       (56b)
fndln   STY B             ; save Y
        LDA #>BaseAdr     ; start of BASIC program
        STA PtrH          ; set Ptr page
        LDY #0            ; Y=0
        STA Ptr           ; set Ptr ofs
fndlp   LDA PtrH          ; DEBUG
        JSR prhx          ; DEBUG
        LDA Ptr           ; DEBUG
        JSR prhx          ; DEBUG
        JSR wrsp          ; DEBUG
        LDY #2            ; Y=2
        LDA (Ptr),Y       ; (OP_LN LnLo >LnHi< Len)
        BMI fndgt         ; -> end of program (negative line)
        DEY               ; Y=1
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



; @@ ex2_u16
; parse u16, u16
ex2_u16:
  JSR expr     ; -> Args
  LDA (CODE),Y ; next byte
  CMP #44      ; is comma?
  BNE e_syn1   ; -> syntax error
  INY
  ; +++ fall through: expr +++

; @@ expr   
; evaluate an expression
expr    LDA (CODE),Y
        BPL xvar          ; < $80
        CMP #OP_I0        ; >= $C0
        BCS xint
        CMP #OP_XOP       ; first prefix operator
        BCC xret          ; -> statement
        CMP #OP_IOP
        BCS xsyn          ; -> infix operator
        ; push prefix operator
        LDX OpTop
        CPX #OprsE        ; end of stack
        BCS efull         ; -> "?FULL"
        STA Oprs,X        ; push operator
        INC OpTop
        BNE expr          ; -> expect var/int/prefix

        ; prefix -> push it -> expect another expr
        ; var/int -> pop/apply prefix loop -> require infix or eol
        ; infix -> pop/apply higher prec -> push it -> expect another expr
        ; eol -> pop/apply loop -> RTS

xsyn    JMP esyn0         ; not impl
xbad    LDY #<msg_bad
        JMP erro

        ; variable        (14b)
xvar    JSR findv         ; -> X=ofs (or syntax error)         XXX common B(N) -> Ptr
        ; check for array
        LDA (CODE),Y
        CMP #40           ; '('
        BEQ xidx
        ; read var
        LDA IVar+1,X      ; high (X)
        TAX               ;
        LDA IVar,X        ; low (A)
        ; +++ fall through: xpush +++

        ; push XA to Arg stack
xpush   STY F             ; save CodeOfs
        LDY ArgTop        ; stack (ascending empty)
        CPY #ArgsE        ; end of stack
        BCS efull         ; -> "?FULL"
        STA $00,Y         ; low (A)
        STX $01,Y         ; high (X)
        INY               ; advance stack
        INY
        STY ArgTop        ;
        LDY F             ; restore CodeOfs
        BCC xinf          ; -> infix

efull   LDY #<msg_mem
        JMP erro

xidx    INY               ;
        JSR expr          ; inside expr?
        LDA (CODE),Y
        CMP #41           ; ')'
        BNE xsyn          ; -> syntax error
        INY
        ; ASL,ROR expr BCS oob
        ; CMP ArrSz,X      ; bounds check
        ; ADC Arg[Top]+ArrPt[X] -> Src
        ; A=(Src) X=(Src+1)
        ; -> xpush


        ; infix operators
xinf
xret    RTS

        ; OP_In, OP_INTn    (32b)
xint    INY               ; [2]
        CMP #OP_INT2      ; [2]
        BCS xint2         ; [2] -> 2-byte int [+1]
        LDX #0            ; [2] high (X) = $00
        CMP #OP_INT1      ; [2]
        BEQ xint1         ; [2] -> 1-byte int [+1]
        BCS xinn1         ; [2] -> 1-byte high $FF [+1]
        ; single-digit
xint0   AND #15           ; [2] low 4 bits (CC)
        BCC xpush         ; [3] -> push XA

        ; OP_INN1
xinn1   LDX #$FF          ; [2] high (X) = $FF
        BNE xint1         ; [3] -> always

        ; OP_INT2
xint2   BNE xbad          ; [2] -> invalid op (CS)
        LDA (CODE),Y      ; [5] high (big-endian)
        INY               ; [2]
        TAX               ; [2] high (X)
xint1   LDA (CODE),Y      ; [5] low (CS)
        INY               ; [2] 
        BCS xpush         ; -> push XA



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
  BCS num_rt     ; [2] >= 10 -> done [+1]
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
  LDY #<msg_ovf  ; [2] "?OVF"
  JMP erro       ; [3] -> report overflow



; ----------------------------------------------------------------------
; Integer Multiply / Divide

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


ORG BasROM+$7FF
  DB 0
