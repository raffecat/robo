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

EmitOfs  = OpTop  ; ALIAS: emit offset for tokenized code         (used in EDIT)

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
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y (uses A,X,Acc/Src,Term/Dst)
        STY D             ; line-no flag (NE=found)
        DEY               ; for INY
        ; tokenize the line
tkskp   INY               ; skip space
tokn    LDA #46           ; DEBUG (dot)
        JSR wrch          ; DEBUG
        LDA LineBuf,Y     ; next input char
        CMP #32           ; space?
        BEQ tkskp         ; -> skip it
        TAX               ; X=next-char
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
        BNE tkemt         ; -> emit it
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
        JSR prhx
        JSR wrsp
        INY
        CPY EmitOfs
        BCC dbglp
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

        ; copy a string
tkstr   TXA               ; A=next-char
tkstl   JSR tkemi         ; emit char (uses X=0; preserves A,Y; sets PL)
        INY               ; advance
        LDA LineBuf,Y     ; get next char
        BEQ tksyn         ; -> at end of line, missing quote
        CMP #34           ; is it `"`?
        BNE tkstl         ; -> continue
        INY               ; advance
        CMP LineBuf,Y     ; is next char `"` ?
        BNE tkemt         ; -> end of string
        JSR tkemi         ; emit " (uses X=0; preserves A,Y; sets PL)
        BPL tkstl         ; -> ALWAYS emit again and continue (double-quote)
tksyn   LDY <msg_syn      ; syntax error
        BNE erro          ; -> report error

        ; emit a number
tknum   JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Acc/Src,Term/Dst)
        STY B             ; save Y
        LDY #2            ; #2 -> OP_INT2
        LDA $01           ; high byte
        BNE tknmo         ; -> 2 bytes plus opcode
        DEY               ; #1 -> OP_INT1
        LDA $00           ; low byte
        CMP #10           ; CS if >= 10
        BCS tknmo         ; -> 1 byte plus opcode
        ; single-digit number
        SBC #8            ; minus 9 (CS=0)
        TAY               ; Y=[-9..0]
tknmo   TYA               ; A=2 OP_I9 +A=2 = OP_INT2
        CLC               ; A=1 OP_I9 +A=1 = OP_INT1
        ADC #OP_I9        ; A=[-9..0] OP_I9 +A=[-9..0]
        ; emit opcode, then bytes
tknem   JSR tkemi         ; (uses X=0; preserves A,Y; PL)  2 emit 1 ld -> emit 0 ld -> emit -1 stop
        DEY               ; 2 -> 1, 1 -> 0, 0 -> -1
        LDA $00,Y         ; 1=$01, 0=$00
        CPY #0            ; restore flags, ugh
        BPL tknem         ; -> until Y<0
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
        BNE errl          ; loop until zero
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
OP_NEG     = $9D     ; 6 unary negate `-` (replaces OP_SUB)
OP_NOT     = $9E     ; 6 unary NOT
; unary functions (high precedence, evaluated post-fix, right-associative!)
OP_AT      = $9F     ; 6 unary fn (arg,arg)
OP_KEY     = $A0     ; 6 unary fn (arg)
OP_PEEK    = $A1     ; 6 unary fn (arg)
OP_RND     = $A2     ; 6 unary fn ([arg])
; infix binary (from highest to lowest, left-associative)
OP_MUL     = $A3     ; 5 binary op  LSR for prec
OP_DIV     = $A4     ; 5 binary op
OP_ADD     = $A5     ; 4 binary op
OP_SUB     = $A6     ; 4 binary op
OP_EQ      = $A7     ; 3 binary `=`
OP_NE      = $A8     ; 3 binary
OP_LT      = $A9     ; 3 binary `<`
OP_LE      = $AA     ; 3 binary
OP_GT      = $AB     ; 3 binary `>`
OP_GE      = $AC     ; 3 binary
OP_AND     = $AD     ; 2 binary op
OP_OR      = $AE     ; 1 binary op
; open paren (lowest precedence)
OP_LPAR    = $AF     ; 0 open parenthesis (lowest [never forced to eval], skips apply phase, always pushed)
OP_RPAR    = $B0     ; 0 close parenthesis (lowest, forces all ops to eval up to OP_LPAR [which always stops eval])
; numbers (non-operator)
OP_I0      = $C0     ; 1-byte (OP_I0 + [0-9])
OP_I9      = $C9     ; 1-byte
OP_INT1    = $CA     ; 1-byte (opc|int8)
OP_INT2    = $CB     ; 2-byte (opc|int16)

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
msg_syn   DB "SYN",0
msg_ovf   DB "OVF",0
msg_for   DB "FOR",0
msg_gos   DB "GOS",0
msg_typ   DB "TYP",0
msg_esc   DB "ESC",0

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
  DB (ex_at - kwpg)      ; OP_AT
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
stmh:
  DB >repl         ; OP_EOP
  DB >line         ; OP_LN
  DB >clss         ; OP_CLS
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
list    JSR expr          ; line number -> Args[0]  ; XXX or exprs?
        JSR fndln         ; find matching line, or next (Args[0] -> Args[0])  ; pass X?
        LDA (CODE),Y      ; read code
        CMP #44           ; comma?
        BNE lsts          ; -> no, start listing
        INY               ; comma
        JSR expr          ; line number -> Args[1]
        JSR fndln         ; find matching line, or next (Args[1] -> Args[1]) -> X
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

        ; OP_NEW
new     LDA #>BaseAdr     ; set top of program
        STA TopPtrH
        LDA #3            ; (OP_EOP LnLo LhHi)
        STA TopPtr
        LDA #OP_EOP       ; end of program ($80)
        STA BaseAdr
        LDA #$FF
        STA BaseAdr+1     ; set line number:
        STA BaseAdr+2     ; 65535
        BNE lstx          ; JMP repl

        ; OP_RUN
        ; start running the BASIC program
run     LDA TopPtr        ; reset free space
        STA FreePtr
        LDA TopPtrH
        STA FreePtrH
        LDA #0            ; clear vars (9b)
        LDX #75           ; ArrVars, IntVars, OpTop, ArgTop, Data, DataH, CODE
runcl   STA ArrVars,X     ; clear
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
        BCS esyn0         ; [2] -> bad code
        ; token dispatch
        TAX               ; [2]
        LDA stmtl,X       ; [4]
        STA Src           ; [3] PHA
        LDA stmth,X       ; [4]
        STA SrcH          ; [3] PHA
        JMP (Src)         ; [5] RTS // [30]

        ; OP_LET or implied
        ; assign VAR[$] = Expr
let     JSR findv         ; find [@-Z] var -> ofs (A)      XXX array assign
        PHA               ; save var ofs
        JSR expr          ; -> Args[0]
        PLA               ; pop var ofs
        JSR setv          ; assign Args[0]
        JMP stmt          ; -> next stmt

        ; assign Args[0] to var ofs (A)
setv    TAX               ; as index (10b)
        LDA $00           ; Args[0]
        STA IntVars,X     ; low byte
        LDA $01           ; 
        STA IntVars+1,X   ; high byte
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
        BCC esyn0         ; -> not found
        STX CODEH
        STA CODE
        LDY #3            ; skip (LnL,LnH,Len)
        BNE stmt          ; always OP_LINE

        ; OP_GOSUB
gosub   JSR expr          ; -> Args[0]
        JSR push_code     ; save return CODE (frame)        XXX JSR'd can't PHA
        LDA #TAG_GOSUB    ; 
        PHA               ; (frame)
        BNE goln          ; -> ALWAYS

        ; OP_RESTORE
        ; Find specified line, set Data (READ does most of the work)
resto   JSR expr          ; -> Args[0]
        JSR fndln         ; find line, or next (Args[0] -> XA)
        STX DataH         ; pointer to next data, high
        STA Data          ; pointer to next data, low
        JMP stmt   

esyn0   LDY #<msg_syn
        JMP erro

        ; OP_READ
        ; Data always points into the program (start of program, last RESTORE, last READ)
        ; @lp if (Data) >= $80 we're at eol; find next DATA line
        ; read num at (Data), assign to var, advance Data -> @lp
rdnx    INY               ; comma (in Code)
read    JSR findv         ; find [@-Z] var (uses A) reads code -> ofs (A)
        TAX               ; var ofs -> X
        STY D             ; save Y
        LDY #0            ; data ofs -> Y
        LDA (Data),Y      ; 
        BMI rdfd          ; -> find next DATA
        STA IntVars,X     ; low byte
        INY               ;
        LDA (Data),Y      ; 
        STA IntVars+1,X   ; high byte
        INY               ;
        TYA               ; advance Data
        CLC               ;
        ADC Data          ; Data += Y
        STA Data          ;
        BCC rdnp          ; -> no page cross
        INC DataH         ; DataH += 1
rdnp    LDY D             ; restore Y = Code ofs
        LDA (CODE),Y      ; read code
        CMP #44           ; comma
        BEQ rdnx          ; -> next var
        JMP stmt          ; -> next stmt
rdfd    LDY D             ; find next DATA line
        ;;                                                 XXX find next DATA
        JMP stmt

        ; OP_INPUT
inpnx   INY               ; comma
input   JSR findv         ; find [@-Z] var (uses A) -> ofs (A)
        PHA               ; PUSH var index
        STY B             ; save CODE ofs (for retry)
inprt   LDA #63           ; '?'
        JSR wrch          ; print it (uses A,X,F,Src,Dst) preserves Y
        LDY B             ; restore CODE ofs (for retry)
        JSR rdln          ; read input (uses A,X,Y,B,C) -> Y=length
        STY C             ; new CODE ofs
        LDY #0            ; Y = input ofs
        JSR num_u16       ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Acc/Src,Term/Dst)
        CPY #0            ; 
        BEQ inprt         ; -> no, retry
        LDY C             ; commit new CODE ofs
        PLA               ; POP var index
        JSR setv          ; assign Args[0] to var ofs (A)
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
  PHA             ; low byte
  LDA $01
  PHA             ; high byte
  JSR expr        ; "TO" expression -> Args
  LDA $02
  PHA             ; low byte
  LDA $03
  PHA             ; high byte
  LDA (CODE),Y    ; peek next byte
  CMP #OP_STEP    ; "STEP"?
  BEQ @step       ; -> handle "STEP"
  LDA #1          ; push $0001
  PHA             ; low byte
  LDA #0
  PHA             ; high byte
@cont:
  JSR push_code   ; save return CODE (uses A,Y -> Y=0)   XXX JSR'd can't PHA
  LDA #TAG_FOR    ;
  PHA             ; push "FOR" control tag
  JMP stmt        ; [3] -> next stmt
@step:
  INY             ; OP_STEP
  JSR expr        ; "STEP" expression -> Args
  LDA $04
  PHA             ; low byte
  LDA $05
  PHA             ; high byte
  JMP @cont       ; -> continue FOR


; NEXT: optional VAR
;       scan control stack for matching FOR 'VAR' (same address);
;       add STEP to VAR;
;       compare VAR vs TO based on STEP sign;
;       continue -> restore CODE address -> jump to STMT loop
;       otherwise -> pop FOR frame -> jump to STMT loop
do_next:
  JSR findv         ; find [@-Z] var -> ofs (A)
@loop:
  LDA #TAG_FOR
  JSR find_frame    ; pop frames until A=TAG
  ; compare VAR=ofs
  BNE @loop

  ; not found -> No FOR
  ; add STEP to VAR
  ; compare TO value
  ; if less, set CODE to loop address
  ; else pop FOR frame
  JMP stmt   
@nofor:
  LDY #<msg_for
  JMP erro



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


        ; find matching line (CS), or following line (CC)
        ; find Args[0] -> XA/Ptr (uses A,X,F)
fndln   STY B             ; save Y
        LDA #>BaseAdr     ; start of BASIC program
        STA PtrH          ; set Ptr page
        LDY #0            ; Y=0
        STA Ptr           ; set Ptr ofs
fndlp   LDA PtrH          ; DEBUG
        JSR prhx          ; (uses A,X,F,Src,Dst) preserves Y
        LDA Ptr
        JSR prhx          ; (uses A,X,F,Src,Dst) preserves Y
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
expr    LDA (CODE),Y
        CMP #OP_I0
        BCS expi
expz    JMP esyn0         ; not impl

        ; OP_In, OP_INTn
expi    INY
        CMP #OP_INT1
        BCC expi0
        BEQ expi1
        CMP #OP_INT2
        BNE expz
        ; OP_INT2
        LDA (CODE),Y
        STA $00           ; low
        INY
        LDA (CODE),Y
        STA $01           ; high
        INY
        RTS
        ; OP_INT1        
expi1   LDA (CODE),Y
        INY
        BNE exp0r
        ; single digit
expi0   EOR #$C0          ; clear top two bits
exp0r   STA $00
        LDA #0
        STA $01
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
  ASL $00        ; [5] Acc = Acc*2 (=Val*2)
  ROL $01        ; [5]
  BCS err_ovf    ; [2] -> unsigned overflow
  LDA $00        ; [3] Term = Acc (=Val*2)
  STA Term0      ; [3]
  LDA $01        ; [3]
  STA Term1      ; [3]
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
  ADC Term0      ; [3] Acc += Term (=Val*2)
  STA $00        ; [3] Args[0]
  LDA $01        ; [3]
  ADC Term1      ; [3]
  STA $01        ; [3]
  BCC @loop      ; [2] -> no overflow, continue [+1]
err_ovf:
  LDY #<msg_ovf  ; [2] "?OVF"
  JMP erro       ; [3] -> report overflow



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
