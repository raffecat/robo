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
; Casette         164b ($a4)   \              0C
; Keyboard        256b ($100)  |              0D
; Print/Wrchr     231b ($e7)   |              0E
; Readline        103b ($67)   |  1K          0F
; Cls/Tab/XY      106b ($6a)   |  
; Copy fw/bw       85b ($55)   |  
; INT/Cursor       79b ($4f)   /
;                 -----------
; 256+231+103+106+85+79+164

; 5 pages Bas ROM:
; • floating point
; • square root
; • string heap
; • string functions

; 4 pages Sys ROM:
; • Line drawing
; • Cassette code
; • Sound interrupt
; • Color zones
; • Serial and parallel
; • Number conversion
; • Graphics font? 3x5: 5 * 96 / 2 = 240 bytes

BasROM   = $C000  ; 4K/8K BASIC ROM
DiskROM  = $E000  ; 4K DISK ROM
SysROM   = $F800  ; 2K SYSTEM ROM (twice)
SizeIMG  = $1800  ; size of 6K file

HWVEC    = $FFFA  ; vector table, 6 bytes
SYSVEC   = $FFC0  ; system vector table

; ------------------------------------------------------------------------------
; Address Space

; Moved VRAM to the end of detected memory: dynamic VidBase.
; Otherwise, on a screen mode change, we would need to
; move the BASIC program (breaking pointers on the stack)
; and machine code programs would need to be compiled
; for a specific screen mode?!

ZeroPg   = $00  ; zero page (constant)
StackPg  = $01  ; stack page (constant)
BasePg   = $02  ; start of free memory (constant)
End4K    = $10  ; end of 4KB memory (minimum RAM fitted)

; ------------------------------------------------------------------------------
; Zero Page $00-7F - BASIC WORKSPACE

; -- $00-1F BASIC Operator Stack (32 operators)

OperStk  = $00    ; BASIC operator stack

; -- $20-3F Unused space (32)

;DiskArea = $20    ; (32 bytes)

; -- $40-73 BASIC Variables (52; 26 pointers)

uCReg    = $40    ; ALIAS: uCode registers ($40-$43)
InPtr    = $44    ; ALIAS: Input Pointer (uCode)
InPtrH   = $45    ; ALIAS: Input Pointer (uCode)
VarPtrs  = $40    ; 26 x BASIC variable pointers (A-Z)

; -- $74-7F BASIC Pointers (12; 6 pointers)

OpTop    = $74    ; Top of OperStk (stack pointer)
; XXX    = $75    ; unused
TopPtr   = $76    ; TOP of the BASIC program, start of variables
TopPtrH  = $77
FreePtr  = $78    ; FREE space at end of variables                 [LineNo]
FreePtrH = $79
HeapPtr  = $7A    ; start of string HEAP at top of memory          [AutoLn]
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

EmitOfs  = $7E    ; ALIAS Data - emit offset for tokenized code [Tokenize] [uCode]
EmitPtch = $7F    ; ALIAS DataH - emit patch offset [Tokenize] [uCode]
uCode    = $7A    ; ALIAS HeapPtr, AutoLn   [uCode]
uCodeH   = $7B    ; ALIAS HeapPtrH, AutoLnH [uCode]
JmpOp    = $78    ; ALIAS FreePtr, LineNo   [uCode]
JmpOpH   = $79    ; ALIAS FreePtrH, LineNoH [uCode]

; ------------------------------------------------------------------------------
; Zero Page $80-FF - OS WORKSPACE

; -- $80-9F IO Buffers (32)

KeyBufMask = 15   ; Modulo 16 (bitmask)

KeyBuf   = $80    ; Keyboard Buffer (16 bytes)
IOBuf    = $90    ; IO Buffer (16 bytes)

; -- $A0-BF File Control Blocks (32)

FCB_0    = $A0    ; File Control Block 0 (8 bytes)
FCB_1    = $A8    ; File Control Block 1 (8 bytes)
FCB_2    = $B0    ; File Control Block 2 (8 bytes)
FCB_3    = $B8    ; File Control Block 3 (8 bytes)

; -- $C0-CF Temporaries

Src      = $C0    ; source pointer \ Scroll (PRINT/WRCHR/WRCTL), CLS
SrcH     = $C1    ; source pointer | Tokenize (match_kws/num_val)
Dst      = $C2    ; second pointer | Scroll (PRINT/WRCHR/WRCTL), CLS
DstH     = $C3    ; second pointer | 
Ptr      = $C4    ; third pointer  \ PRINT src (can cause Scroll)
PtrH     = $C5    ; third pointer  /
B        = $C6    ; extra register | Subroutines are annotated with usage;
C        = $C7    ; extra register | held across calls only when unused
D        = $C8    ; extra register | by callees (manually tracked)
E        = $C9    ; extra register | 
F        = $CA    ; extra register | Scratch (always transient; cannot hold)

ExpTop   = $CB    ; top of Expr stack (in stack page)

AccE     = $CC    ; accumulator exponent (0 for integer)
Acc2     = $CD    ; accumulator byte 2
Acc1     = $CE    ; accumulator byte 1
Acc0     = $CF    ; accumulator byte 0

TermE    = $C0    ; ALIAS Src:  term exponent (0 for integer)
Term2    = $C1    ; ALIAS SrcH: term byte 2
Term1    = $C2    ; ALIAS Dst:  term byte 1
Term0    = $C3    ; ALIAS DstH: term byte 0

; -- $D0-DF System Vars

KeyHd    = $D0    ; keyboard buffer head (owned by User)
KeyTl    = $D1    ; keyboard buffer tail (owned by IRQ)
ModKeys  = $D2    ; modifier keys [7:Esc 6:Shf 5:Ctl 4:Fn] (owned by IRQ)
CurrKey  = $D3    ; keyboard current key pressed, for auto-repeat (owned by IRQ)
DeadKey  = $D4    ; keyboard last key pressed, to ignore it (owned by IRQ)
KeyRep   = $D5    ; keyboard auto-repeat timer

WinT     = $D6    ; text window top
WinH     = $D7    ; text window height

TXTP     = $D8    ; text write address
TXTPH    = $D9    ; text write address high
CurTime  = $DA    ; cursor flash timer
CurChar  = $DB    ; character under cursor
CurVis   = $DC    ; cursor visible flag

VidBase  = $DD    ; base of video memory in pages
MemSize  = $DE    ; size of memory fitted (detected memory) in pages

; DE-DF free (2)

; -- $E0-EF OS Vectors

; E0-E3 free (4)

; Vectors (E4-EF)
SysCmds  = $E4    ; REPL command-list pointer {Low,High} (for ROM override)
SysStmt  = $E6    ; BASIC statement extension cmd-list {Low,High} (for ROM override)
IRQTmp   = $E8    ; Temp for IRQ handler #1
IRQTmp2  = $E9    ; Temp for IRQ handler #2
NmiVec   = $EA    ; NMI vector in RAM {JMP,Low,High} (for ROM override)
IrqVec   = $ED    ; IRQ vector in RAM {JMP,Low,High} (for ROM override)

; -- $F0-FF  IO Area

IO_MMAP  = $F0    ; expansion mapping 4-bit (write)
IO_DSK0  = $F4    ; disk expansion 0
IO_DSK1  = $F5    ; disk expansion 1
IO_DSK2  = $F6    ; disk expansion 2
IO_DSK3  = $F7    ; disk expansion 3
IO_DATA  = $F8    ; OUT 8-bit (7-6:Volume 2:RTS 1:TXD 0:TapeOut) / IN (2:CTS 1:RXD 0:TapeIn)
IO_KEYB  = $F9    ; Keyboard column 4-bit (3:Strobe 2-0:KBCol) / read: KB row 8-bit
IO_LINE  = $FA    ; IRQAck 3-bit (7:VSync 6:VRow 5:KBInt) / read: vertical line (>= 192 in vblank)
IO_PSGF  = $FB    ; PSG frequency 8-bit (write: 7-0:Divider)(7860 Hz / divider)
IO_PAL1  = $FC    ; palette for APA 8-bit (7-4:BG 3-0:~FG)
IO_PAL2  = $FD    ; palette for APA 8-bit (7-4:C2 3-0:C3)
IO_VPGC  = $FE    ; video page counter 5-bit
IO_VCTL  = $FF    ; video mode 8-bit (7:VSync 6:VRow 5:Parallel 4:? 3:Grey 2:2Bpp 1-0:VMux)

; ------------------------------------------------------------------------------
; PAGE ONE $100-1FF - STACK

LineBuf  = $100    ; Input Buffer (128 bytes)
EmitBuf  = $100    ; Emit Buffer (128 bytes)

ExprStk  = $100    ; Expression stack (96 bytes = 24 numbers)

StackBot = $180    ; Bottom of BASIC control-stack (cannot go below $180)

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
; PAGE 0 - Boot + Subs

ORG BasROM

reset:
  SEI               ; disable interrupts
  CLD               ; disable BCD mode
  LDA #End4K        ; end of memory (page)
  STA MemSize       ; set size of memory (in pages)
  LDX #$FF          ; X = $FF
  TXS               ; reset SP = $FF
  INX               ; X = 0
  STX Acc0          ; clear Acc1
  JSR vid_mode      ; set text mode (X=0)
  JSR irq_init      ; set up IRQ handler (required for video)
  LDY #<msg_boot    ; boot message
  JSR printmsgln    ; print it
  ; print free memory
  LDX VidBase       ; get video base page
  DEX               ; minus 2 (ASSUMES BasePg=$02)
  DEX               ; 
  STX Acc1          ; 
  JSR print_u16     ; print it
  LDY #<msg_freemem ; free memory message
  JSR printmsgln    ; print it
basic:
  LDY #<msg_ready   ; [2] ready message
  JSR printmsgln    ; [6] print it
repl:
  JSR readline      ; [6] read command or BASIC statement
  JSR newline       ; [6] move to new line
; parse the line
  LDA #0            ; [2] 
  STA EmitOfs       ; [3] reset EmitOfs for code gen
  STA EmitPtch      ; [3] reset EmitPtch for code gen
  STA InPtr         ; [3] reset input offset
  LDA #>LineBuf     ; [2]
  STA InPtrH        ; [3] set input page
  JSR skip_spc      ; [6] A=next-char
  CMP #0            ; [2] empty line? (must CMP)
  BEQ repl          ; [2] -> empty line, go back to repl [+1]
  JSR uCodeParse    ; [6] parse line
  BNE @haveline     ; -> found line number
  JSR debug
  LDA #>EmitBuf     ; EmitBuf page ($01)
  JSR set_prog      ; set up for execution
; JMP do_stmt       ; -> execute the statement  (XXX how does this return without OP_END?)
  JMP repl
@haveline:          ; have a line number
  JSR debug
; JSR ins_line      ; [6] insert the line into the BASIC program
  JMP repl          ; [3] -> return to repl

set_prog:
  STA CODEH         ;
  LDY #0            ; code offset
  STY CODE          ; CODE base (ASSUMES EmitBuf is page-aligned)
  STY Data          ; clear data pointer
  STY DataH         ; clear data pointer
  STY OpTop         ; clear operator stack
  RTS

; @@ report_err
report_err:         ; Y=message
  JSR printmsgln
  JMP repl

; @@ err_expect
err_expect:         ; A=char
  PHA
  LDY #<msg_exp
  JSR printmsg
  PLA
  JSR wrchr
  JSR newline
  JMP repl

; @@ escape
; must wait for ESC to be released
escape:             ; A = msg address low
  JSR hide_cursor   ; uses A,Y; Y=0
  LDY #<msg_esc     ; 
  JSR printmsgln    ; 
@wait:              ; wait for Escape to be released  (XXX -> opcode? 6b vs 4b)  -2
  LDA ModKeys       ; check key state
  BMI @wait         ; -> ESC still down
  JMP repl

set_lno:            ; copy Acc to LineNo
  LDA Acc0
  STA LineNo        ; [3] set LineNo for ins_line
  LDA Acc1
  STA LineNoH
  RTS

;callcmd:            ; call the command (so it can RTS)
;  AND #$3F          ; [2] clear top two bits (hi-byte)
;  TAX               ; [2] as index
;  LDA #>cmds_page   ; [2] X = high byte (page)
;  PHA               ; [3] push high byte
;  LDA disp_cmds,X   ; [4] A = subroutine offset (NOTE minus 1)
;  PHA               ; [3] push low byte minus 1
;  JMP skip_spc      ; [3] -> skip_spc, then RTS to the command


uCodeParse:
  LDX #0            ; [2]
  LDA #>uOpsPg      ; [2]
  STA JmpOpH        ; [3]
uCodeJmp:           ; 
  CPX #$40          ; [2]
  BCS uCodeSub      ; [2] -> call sub [+1]
uCodeCall:
  LDY entry,X       ; [4] Y = entry point // jmp:[15]
uCodeLoop:
  LDX uCodePg,Y     ; [4] get opcode
  BPL uCodeJmp      ; [2] -> do jump [+1]
  INY               ; [2] advance PC
  LDA uoptab,X      ; [4] op addr low (plus $80)
  STA JmpOp         ; [3] set JMP addr
  JMP (JmpOp)       ; [5] -> do it // opcode:[20]
uCodeSub:
  TXA               ; [2]
  AND #63           ; [2]
  JSR uCodeCall     ; [6] -> call it // sub:[26]


; ------------------------------------------------------------------------------
; PAGE 1 - Tables

ORG BasROM+$100
uTabsPg:
input_pg:
print_pg:

ud_input:
ud_print:
ud_stmt:
ud_expr:

; Commands Index (MUST be at offset 0)
kwi_Cmds  DB <tab_cmds
kwi_THEN  DB <tab_then
kwi_ELSE  DB <tab_else
kwi_TO    DB <tab_to
kwi_STEP  DB <tab_step
kwi_FN    DB <tab_fn
kwi_PrFn  DB <tab_prfn
kwi_Infx  DB <tab_infx

; Context keywords
tab_then  DB "THEN",$80         ; bit 6 clear to end (~$40)
tab_else  DB "ELSE", OP_ELSE    ; bit 6 clear to end (~$40)
tab_to    DB "TO",$80           ; bit 6 clear to end (~$40)
tab_step  DB "STEP",$80         ; bit 6 clear to end (~$40)
tab_fn    DB "FN",$80           ; bit 6 clear to end (~$40)

; Commands Table (matches ud_cmds)
tab_cmds:
  DB "LIST",   $80 +$40  ; bit 6 set for more ($40)
  DB "RUN",    $81 +$40
  DB "ART",    $82 +$40
  DB "SAVE",   $83 +$40
  DB "AUTO",   $84 +$40
  DB "DEL",    $85 +$40
  DB "NEW",    $86 +$40
  DB "OLD",    $87 +$40
  DB "CLEAR",  $88 +0    ; bit 6 clear to end (~$40)

; Commands Dispatch (matches cmd_tab)
ud_cmds:         ; page A
;  DB <aList
;  DB <aRun
;  DB <aArt
;  DB <aSave
;  DB <aAuto
;  DB <aDel
;  DB <aNew
;  DB <aOld
;  DB <aClear

; Print Function Table (matches ud_prfn)
tab_prfn  DB "SPC", OP_SPC+$40  ; bit 6 set, continue (+$40)
          DB "TAB", OP_TAB+$40  ; bit 6 set, continue (+$40)
          DB "AT",  OP_AT       ; bit 6 clear to end (~$40)

; Print Function Dispatch (matches tab_prfn)
ud_prfn:
;  DB <bPrFnArg1
;  DB <bPrFnArg1
;  DB <bPrFnArg2

tab_infx  DB 0


; table of entry points (0-63)
; table of subroutines (64-127)

en_stmt   = 0
en_syn    = 1
en_ret    = 2
en_n3     = 3
en_n2     = 4
en_n1     = 5
en_for    = 6
en_nvar   = 7
en_nexp   = 8
en_sexp   = 9
en_exp    = 10
en_else   = 11
en_goln   = 12
en_if     = 13
en_let    = 14
en_type   = 15
en_typchk = 16
en_read   = 17
en_rdlp   = 18
en_sound  = 19
en_snd    = 20
en_next   = 21
en_dim    = 22
en_dim1   = 23
en_dims   = 24
en_data   = 25
en_close  = 26
en_range  = 27
; en_ch1    = 28
en_open   = 29
en_nud    = 30
en_strl   = 31
en_fnvar  = 32
en_num    = 33
en_var    = 34
en_led    = 35
en_var1   = 36
en_var2   = 37
en_gttab  = 38
en_lttab  = 39
en_fnret  = 40
en_input  = 41
en_inp_s  = 42
en_print  = 43
en_prn2   = 44
en_prn1   = 45
en_def    = 46
en_deflp  = 47
en_def1   = 48
en_svar   = 49
en_chn    = 50
en_xs     = 51
en_zcn    = 52
en_sns    = 53
en_inst1  = 54

entry:
  DB <e_stmt
  DB <e_syn
  DB <e_ret
  DB <e_n3
  DB <e_n2
  DB <e_n1
  DB <e_for
  DB <e_nvar
  DB <e_nexp
  DB <e_sexp
  DB <e_exp
  DB <e_else
  DB <e_goln
  DB <e_if
  DB <e_let
  DB <e_type
  DB <e_typchk
  DB <e_read
  DB <e_rdlp
  DB <e_sound
  DB <e_snd
  DB <e_next
  DB <e_dim
  DB <e_dim1
  DB <e_dims
  DB <e_data
  DB <e_close
  DB <e_range
  DB 0         ; e_ch1
  DB <e_open
  DB <e_nud
  DB <e_strl
  DB <e_fnvar
  DB <e_num
  DB <e_var
  DB <e_led
  DB <e_var1
  DB <e_var2
  DB <e_gttab
  DB <e_lttab
  DB <e_fnret
  DB <e_input
  DB <e_inp_s
  DB <e_print
  DB <e_prn2
  DB <e_prn1
  DB <e_def
  DB <e_deflp
  DB <e_def1
  DB <e_svar
  DB <e_chn
  DB <en_xs
  DB <en_zcn
  DB <en_sns
  DB <en_inst1

tab_input:
  DB 34, en_inp_s  ; `"`
  DB ",", $80      ; comma separator
  DB ";", $81      ; semi separator
  DB ":", en_ret   ; colon end of stmt
  DB 0, en_ret     ; nul end of line
  DB $80+en_input  ; end of table, match addr

tab_print:
  DB ",", $80      ; OP_COMMA
  DB ";", $81      ; OP_SEMI
  DB "'", $82      ; OP_NEWLN
  DB ":", en_ret   ; colon end of stmt
  DB 0, en_ret     ; nul end of line
  DB $80+en_print  ; end of table, match addr

tab_nud:
  DB "+", en_nud   ; plus -> e_nud
  DB "-", OP_UNEG  ; unary negate
  DB "(", OP_PAREN ; left paren
  DB 34, en_strl   ; `“`
  DB $80+en_nud    ; end of table, match addr

tab_led:
  DB "+", OP_ADD   ; 
  DB "-", OP_SUB   ; 
  DB "*", OP_MUL   ; 
  DB "/", OP_DIV   ; 
  DB "^", OP_POW   ; 
  DB "=", OP_EQ    ; 
  DB ">", en_gttab ; 
  DB "<", en_lttab ; 
  DB $80+en_nud    ; end of table, match addr

tab_gt:
  DB "=", OP_GE
  DB $80+en_nud    ; end of table

tab_lt:
  DB "=", OP_LE
  DB ">", OP_NE
  DB $80+en_nud    ; end of table


; Emit routines

; @@ emit_data
emit_data:
  JSR skip_spc     ; A=next-char, E=ofs(X)
  STY B            ; save Y=uCode
  LDY E            ; Y=ofs
@copy:
  LDA LineBuf,Y    ; copy rest of the line
  BEQ @done        ; -> end of line
  INY              ; advance input
  JSR emit_byte    ; emit code (uses X=0; preserves A,Y; PL)
  BPL @copy        ; -> ALWAYS: until end of line
@done:
  STY E            ; save updated E=ofs
  LDY B            ; restore Y=code
  JMP uCodeLoop    ; -> next op


; must be in the 2nd half of the page
uoptabx:
  DB <uRET   ; $C0
  DB <uTAB   ; $C1 <tab
  DB <uISA   ; $C2 or -> en_else
  DB <uISD   ; $C3 or -> en_else
  DB <uKWA   ; $C4 >page, <udisp
  DB <uREQ   ; $C5 "ch"
  DB <uIF    ; $C6 "ch", -> en_match
  DB <uIFN   ; $C7 "ch", -> en_match
  DB <uOUT   ; $C8 byte
  DB <uVAR   ; $C9 or -> en_else (parse/emit VAR)
  DB <uSTR   ; $CA (emit str, assumed ")
  DB <uDATA  ; $CB (emit data)
  DB <uN16   ; $CC or -> en_else
  DB <uEM16  ; $CD (emit N16)
  DB <uPLACE ; $CE (emit placeholder)
  DB <uLEN   ; $CF (emit length)
  DB <uEQ    ; $D0 value -> en_match (ur_vt)
  DB <uEQ    ; $D1 value -> en_match (ur_et)
  DB <uERR   ; $D2 <msg
  DB <uKW    ; $D3 <kwi, -> en_match
  DB <uZV    ; $D4 (ur_vt)
  DB <uZV    ; $D5 (ur_et)
  DB <uZV    ; $D6 (ur_cnt)
  DB <uZV    ; $D7 (ur_x)
  DB <uINC   ; $D8 (ur_vt)
  DB <uINC   ; $D9 (ur_et)
  DB <uINC   ; $DA (ur_cnt)
  DB <uINC   ; $DB (ur_x)
  DB <uCMPVE ; $DC (ur_vt, ur_et) -> en_type   XXX single use
  DB <uOUTCH ; $DD (emit var)
  DB <uPATCH ; $DE (patch in var)

uoptab = uoptabx - $80


; ------------------------------------------------------------------------------
; PAGE 2 - uCode

ORG BasROM+$200
uCodePg:

U_RET   = $C0
U_TAB   = $C1   ; <tab
U_ISA   = $C2   ; or -> en_else
U_ISD   = $C3   ; or -> en_else
U_KWA   = $C4   ; >page, <udisp
U_REQ   = $C5   ; "ch"
U_IF    = $C6   ; "ch", -> en_match
U_IFN   = $C7   ; "ch", -> en_match
U_OUT   = $C8   ; byte
U_VAR   = $C9   ; or -> en_else (parse/emit VAR)
U_STR   = $CA   ; (emit str, assumed ")
U_DATA  = $CB   ; (emit data)
U_N16   = $CC   ; or -> en_else
U_EM16  = $CD   ; (emit N16)
U_PLACE = $CE   ; (emit placeholder)
U_LEN   = $CF   ; (emit length)
U_EQ    = $D0   ; value -> en_match         (D0=vt, D1=et)
U_ERR   = $D2   ; <msg
U_KW    = $D3   ; <kwi, -> en_match
U_ZV    = $D4   ; (zero var - one of four)  (D4=vt, D5=et, D6=cnt, D7=x)
U_INC   = $D8   ; (inc var)                 (D8=vt, D9=et, DA=cnt, DB=x)
U_CMPVE = $DC   ; vt<>et -> en_type         (vt <> et) single-use
U_OUTCH = $DD   ; (emit var)                (n16) single-use
U_PATCH = $DE   ; (patch in var)            (cnt) single-use

ur_vt = 0
ur_et = 1
ur_cnt = 2

u_sub = $40   ; bit 6


; Statement Parser

e_parse   DB U_N16, en_stmt
e_stmt    DB U_KWA, >stmt_page, <ud_stmt
          DB U_IF, "=", en_fnret
e_syn     DB U_ERR, <msg_syn
e_range   DB U_ERR, <msg_rng
e_type    DB U_ERR, <msg_typ

e_fnret   DB U_OUT, OP_FNRET
          DB en_exp


; Statement Syntaxes

e_let     DB en_var|u_sub
          DB U_REQ, "="
          DB en_exp|u_sub
e_typchk  DB U_CMPVE, en_type
          DB U_RET

e_n3      DB en_nexp|u_sub
e_n2      DB en_nexp|u_sub
e_n1      DB en_nexp

e_sound   DB en_n3|u_sub
          DB en_snd|u_sub
e_snd     DB U_IF, ",", en_ret
          DB en_nexp

e_dim     DB en_var|u_sub
          DB U_IFN, "$", en_dim1       ; XXX permits spaces!
          DB U_OUT, "$"
e_dim1    DB U_REQ, "("                ; XXX permits spaces!
          DB en_dims

e_read    DB U_PLACE
          DB U_ZV|ur_cnt
e_rdlp    DB en_var|u_sub
          DB U_INC|ur_cnt
          DB U_IF, ",", en_rdlp
          DB U_PATCH|ur_cnt
          DB U_RET

e_data    DB U_PLACE
          DB U_DATA
          DB U_LEN
          DB U_RET

e_if      DB U_PLACE
          DB en_nexp|u_sub
          DB U_KW, <kwi_THEN, en_stmt
          DB en_goln

e_else    DB U_LEN
          DB U_PLACE
e_goln    DB U_N16, en_stmt
          DB U_OUT, OP_GOTO
          DB U_EM16
          DB U_RET

e_for     DB en_nvar|u_sub
          DB U_KW, <kwi_TO, en_syn
          DB en_nexp|u_sub
          DB U_KW, <kwi_STEP, en_ret
          DB en_nexp

e_next    DB en_var|u_sub
          DB U_EQ|ur_vt, 1, en_syn
          DB U_RET

e_open    DB en_close|u_sub
          DB U_IFN, ",", en_syn
          DB en_sexp

e_close   DB U_REQ, "#"
e_chn     DB U_N16, en_syn
          DB U_OUTCH
          DB U_RET

e_input   DB U_TAB, <tab_input
          DB U_KWA, >input_pg, <ud_input  ; ELSE -> e_else
          DB en_var|u_sub ; must be VAR
          DB en_input     ; -> loop
e_inp_s   DB U_STR        ; emit string literal
          DB en_input     ; -> loop

e_print   DB U_TAB, <tab_print
          DB U_KWA, >print_pg, <ud_print  ; ELSE -> e_else
          DB en_exp|u_sub ; an expression
          DB en_print     ; -> loop
e_prn2    DB en_nexp|u_sub
e_prn1    DB en_nexp|u_sub
          DB en_print     ; -> loop

e_def     DB U_KW, <kwi_FN, en_syn   ; `FN` keyword
          DB en_svar|u_sub           ; VAR[$] name
          DB U_IFN, "(", en_def1
e_deflp   DB en_svar|u_sub           ; VAR[$] name
          DB U_IF, ",", en_deflp     ; -> loop
e_def1    DB U_IF, "=", en_fnret     ; -> e_fnret
          DB U_RET


; Expressions

e_nexp    DB en_exp|u_sub
          DB U_EQ|ur_vt, 1, en_type   ; 1=str -> type mismatch
          DB U_RET

e_sexp    DB en_exp|u_sub
          DB U_EQ|ur_vt, 0, en_type   ; 0=num -> type mismatch
          DB U_RET

e_exp     DB U_ZV|ur_et      ; 0=int result unless modified
e_nud     DB U_TAB, <tab_nud
          DB U_ISA, en_fnvar
          DB U_ISD, en_num
          DB en_syn
e_strl    DB U_OUT, OP_STRL
          DB U_STR
          DB en_led

e_fnvar   DB U_KWA, >expr_page, <ud_expr
          DB en_var|u_sub
          DB en_led

e_num     DB 0

e_var     DB U_ZV|ur_vt          ; 0=num VAR
          DB U_VAR, en_var1
          DB en_syn
e_var1    DB U_IFN, "$", en_var2 ;                 XXX permits spaces!
          DB U_OUT, "$"
          DB U_INC|ur_vt         ; 1=str VAR
e_var2    DB U_IFN, "(", en_ret  ;                 XXX permits spaces!
          DB U_OUT, "("
e_dims    DB en_nexp|u_sub
          DB U_IF, ",", en_dims
          DB U_REQ, ","
e_ret     DB U_RET

e_nvar    DB en_var|u_sub
          DB U_EQ|ur_vt, 1, en_type
          DB U_RET

e_svar    DB en_var|u_sub
          DB U_EQ|ur_vt, 0, en_type
          DB U_RET

e_led     DB U_TAB, <tab_led
          DB U_KW, <kwi_Infx, en_ret
          DB U_RET        ; end of expr (no more operators)

e_gttab   DB U_TAB, <tab_gt
          DB U_OUT, OP_GT
          DB en_nud

e_lttab   DB U_TAB, <tab_lt
          DB U_OUT, OP_LT
          DB en_nud

; Expression Syntaxes

; "PI",      OP_PI      ; none -> num            e_xn
; "TIME",    OP_TIME    ; none -> num            e_xn
; "TOP",     OP_TOP     ; none -> num            e_xn
; "POS",     OP_POS     ; none -> num            e_xn
; "VPOS",    OP_VPOS    ; none -> num            e_xn
; "GET",     OP_GET     ; none -> num            e_xn
; "ABS",     OP_ABS     ; num -> num             e_nn
; "RND",     OP_RND     ; num -> num             e_nn
; "SQR",     OP_SQR     ; num -> num             e_nn
; "SGN",     OP_SGN     ; num -> num             e_nn
; "USR",     OP_USR     ; num -> num             e_nn
; "BTN",     OP_BTN     ; num -> num             e_nn
; "JOY",     OP_JOY     ; num -> num             e_nn
; "KEY",     OP_KEY     ; num -> num             e_nn
; "INT",     OP_INT     ; num -> num             e_nn
; "SCN",     OP_SCN     ; num, num -> num        e_nnn
; "ASC",     OP_ASC     ; str -> num             e_sn
; "VAL",     OP_VAL     ; str -> num             e_sn         stops at first non-numeric
; "LEN",     OP_LEN     ; str -> num             e_sn
; "GET$",    OP_GET     ; none -> str            e_xs
; "INSTR$",  OP_INSTR   ; [num], str, str -> num e_instr
; "LEFT$",   OP_LEFT    ; str, num -> str        e_sns
; "RIGHT$",  OP_RIGHT   ; str, num -> str        e_sns
; "STRING$", OP_STRING  ; str, num -> str        e_sns
; "MID$",    OP_MID     ; str, num, num -> str   e_snns       length optional (MS)
; "CHR$",    OP_CHR     ; num -> str             e_ns
; "STR$",    OP_STR     ; num -> str             e_ns
; "EOF#",    OP_EOF     ; #ch                    e_ch
; "LEN#",    OP_FLEN    ; #ch                    e_ch         peek, poke cast to int
; "FN",      OP_FN      ; special

e_xs      DB U_INC|ur_et                                        ; none -> str  (set type=str)
e_xn      DB U_RET                                              ; none -> num
e_nnn     DB en_nexp|u_sub                                      ; num, num -> num
e_zcn     DB U_IFN, ",", en_syn                                 ; "comma num"
e_nn      DB en_nexp                                            ; num -> num
e_sn      DB en_sexp                                            ; str -> num
e_sns     DB en_xs|u_sub                                        ; str, num -> str  (set type=str)
          DB en_sexp|u_sub
          DB en_zcn
e_snns    DB en_sns|u_sub                                       ; str, num, num -> str  (set type=str)
          DB en_zcn
e_ns      DB en_xs|u_sub                                        ; num -> str  (set type=str)
          DB en_nexp
e_ch      DB en_chn                                             ; {0-9}
e_instr   DB en_exp|u_sub                                       ; [num], str, str -> num (MS quirk)
          DB U_EQ|ur_et, 1, en_inst1                            ; (0=num -> continue; 1=str -> skip one arg)
          DB en_sexp|u_sub
e_inst1   DB en_sexp                                            ; XXX but how does RT know?

; 32 x u_sub      \ +55 bytes (two-byte / 12-bit encoding)
; 23 x bare jump  / -55 bytes (remove entry-table)


; ------------------------------------------------------------------------------
; PAGE 3 - uCode Page B

ORG BasROM+$300
uOpsPg:


uRET:               ; $C0 return from SUB/uCode
  RTS

uEQ:                ; $D0 (D0=vt, D1=et) value -> en_match
  TXA               ; X=opcode
  AND #1            ; low bit (0=vt, 1=et)
  TAX               ;
  LDA uCodePg,Y     ; get value
  CMP uCReg,X       ; compare var
  BEQ ucJmp         ; -> take jump
  BNE ucSkip        ; -> skip jump, continue

uCMPVE:             ; $DC ur_vt <> ur_et -> en_type
  LDA uCReg+ur_vt   ; 
  CMP uCReg+ur_et   ; 
  BEQ ucSkip        ; -> same, skip jump, continue
  BNE ucJmp         ; -> different, take jump

uISA:               ; $C2 or -> en_else
  JSR skip_spc      ; [6] A=next-char
  JSR is_alpha      ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCS ucJmp         ; [2] -> jump if no match [+1]
ucSkip:
  INY               ; [2] skip jump addr
ucCont:
  JMP uCodeLoop     ; [3] -> continue

uISD:            ; $C3 or -> en_else
  JSR skip_spc      ; [6] A=next-char
  JSR is_digit      ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC ucSkip        ; [3] -> skip jump and continue
  ; +++ fall through +++

ucJmp:
  LDA uCodePg,Y     ; [4] get opcode
  TAY               ; [2]
  JMP uCodeLoop     ; [3] -> continue

uREQ:            ; $C5 "ch"
  STA B             ; [3] save A
  JSR skip_spc      ; [6] A=next-char
  CMP B             ; [3] does it match?
  BEQ ucCont        ; [2] -> yes, continue [+1]
  LDA B             ; [3]
  JMP err_expect    ; [3] -> report error

uIF:                ; $C6 "ch", -> en_match
  STA B             ; [3] save A
  JSR skip_spc      ; [6] A=next-char
  CMP B             ; [3] does it match?
  BEQ ucJmp         ; [2] -> yes, jump [+1]
  BNE ucSkip        ; [3] -> no, skip jump and continue

uIFN:               ; $C7 "ch", -> en_match
  STA B             ; [3] save A
  JSR skip_spc      ; [6] A=next-char
  CMP B             ; [3] does it match?
  BNE ucJmp         ; [2] -> yes, jump [+1]
  BEQ ucSkip        ; [3] -> no, skip jump and continue

uN16:               ; $CC or -> en_else
  JSR num_u16       ; [6] Y=ofs (uses A,Y,B,C,Term) -> Acc,Y,NE=found   (XXX save/restore Y, or set Src/Ptr?)
  BEQ ucJmp         ; [2] -> not found, jump [+1]
  BNE ucSkip        ; [2] -> found, skip jump and continue [+1]

uOUT:               ; $C8 byte
  LDA uCodePg,Y     ; [4] get byte to emit
  INY               ; [2]
uOUT_emit:
  JSR emit_byte     ; [6] (uses X; preserves A,Y; sets PL)
  JMP uCodeLoop     ; [3] -> continue

uOUTCH:             ; $DD (emit n16 low, range-check 0-9)
  LDA Acc1          ; 
  BNE @range        ; -> out of range
  LDA Acc0          ; 
  CMP #10           ; is it >= 10?
  BCC uOUT_emit
@range:
  LDY #<msg_rng
  JMP report_err

uEM16:              ; $CD (emit N16)
  LDA Acc0          ; low byte
  JSR emit_byte     ; [6] (uses X; preserves A,Y; sets PL)
  LDA Acc1          ; low byte
  JSR emit_byte     ; [6] (uses X; preserves A,Y; sets PL)
  JMP uCodeLoop     ; [3] -> continue

uERR:               ; $D2 <msg
  LDA uCodePg,Y     ; [4] get msg
  TAY               ; [2] Y=msg
  JMP report_err    ; [3] -> report it

uZV:                ; $D4 (D4=vt, D5=et, D6=cnt, D7=x)
  TXA               ; X=opcode
  AND #3            ; low 2 bits (0=vt, 1=et, 2=cnt, 3=x)
  TAX               ;
  LDA #0            ;
  STA uCReg,X       ; set register = 0
  JMP uCodeLoop     ; -> continue

uINC:               ; $D8 (D8=vt, D9=et, DA=cnt, DB=x)
  TXA               ; X=opcode
  AND #3            ; low 2 bits (0=vt, 1=et, 2=cnt, 3=x)
  TAX               ;
  INC uCReg,X       ; increment register
  JMP uCodeLoop     ; -> continue

uPLACE:             ; $CE (emit placeholder)
  JSR emit_place
  JMP uCodeLoop     ; -> continue

uLEN:               ; $CF (emit length)
  JMP patch_len

uPATCH:             ; $DE (DE=cnt)
  JMP patch_byte

uTAB:               ; $C1 <tab
uKWA:               ; $C4 >page, <udisp
  JMP match_kws
uKW:                ; $D3 <kwi, -> en_match

uVAR:               ; $C9 or -> en_else (parse/emit VAR)
  JMP emit_var      ; [6] copy VAR to output

uSTR:               ; $CA (emit str, assumed ")
  JMP emit_str      ; [6] copy string to output

uDATA:              ; $CB (emit data)
  JMP emit_data     ; [6] copy data to output


; ------------------------------------------------------------------------------
; PAGE 4 - 

ORG BasROM+$400


; Emit Routines

; @@ emit_var
; match and emit a VAR name (assume 1st letter is alpha)    Y=in-ofs X=out-ofs
emit_var:
  JSR skip_spc     ; [24] A=next-char
  TAX              ; [2] save char
  JSR is_alpha     ; [20] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCS emit_jmp     ; [2] -> no match, bail out
@lp:
  TXA              ; [2] restore char
  JSR emit_byte    ; [27] emit char -> (uses X; preserves A,Y; sets PL)
@start:
  LDX #0           ; [2]
  LDA (InPtr,X)    ; [6] next input char
  INC InPtr        ; [5] advance input (assume match)
  TAX              ; [2] save char
  JSR is_alpha     ; [20] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC @lp          ; [2] -> is alpha, continue [+1]
  TXA              ; [2] restore char
  JSR is_digit     ; [18] A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC @lp          ; [2] -> is digit, continue [+1]
; end of VAR
  DEC InPtr        ; [5] undo advance (didn't match)
emit_skip:
  INY              ; [2] skip jump <addr>
  JMP uCodeLoop    ; [3] -> next op

; @@ emit_str
; match and emit a string literal (assume `"` already matched, E>0)
; jump to <addr> on missing closing quote
emit_str:
  STY B            ; save Y=uCode
  LDY E            ; load E=ofs
  DEY              ; for pre-advance INY
  BNE @start       ; -> start (ASSUMES E>0)
@copy:
  JSR emit_byte    ; [27] emit char (uses X; preserves A,Y; sets PL)
@start:
  INY              ; pre-advance input
  LDA LineBuf,Y    ; next input char
  BEQ @miss        ; -> at end of line (missing quote), jump to <addr>
  CMP #34          ; is it `"`?
  BNE @copy        ; -> continue
  INX              ; advance
  CMP LineBuf,Y    ; is next char `"` ?
  BEQ @copy        ; -> emit one `"` and continue
  BNE emit_skip    ; -> skip jump, then next op
@miss:
  STY E            ; save updated E=ofs
  LDY B            ; restore Y=code
emit_jmp:
  JMP ucJmp        ; -> jump to <addr>




; ------------------------------------------------------------------------------
; PAGE 5 - Messages

ORG BasROM+$500
messages:    ; page-aligned

msg_boot:    ; red orange yellow green cyan
  DB 8+19
  DB $92,$93,$94,$95,$96,$90,13,13
; DB 18+19
; DB $91,$92,$93,$94,$95,$96,$97, $98, $99,$9A,$9B,$9C,$9D,$9E,$9F, $90,13,13
; DB $91,$99,$92,$9A,$93,$9B,$94, $9C, $95,$9D,$96,$9E,$97,$98,$9F, $90,13,13
  DB "Frontier BASIC 1.0",13
msg_freemem:
  DB 12+17
  DB " bytes free",13
  DB "Type ART to draw",13
msg_ready:
  DB 5,"Ready"
msg_searching:
  DB 9,"Searching"
msg_loading:
  DB 7,"Loading"
msg_art:
  DB 14+4+42
  ; XXX need raw print to display these arrows (or distinct codes)
  DB "Chroma ART ",$1C,$1D,$1E,$1F," to move, GRA+key to draw, COL+key for color"
msg_play:
  DB 4,"PLAY"
msg_stop:
  DB 4,"STOP"
msg_press:
  DB 6,"Press "
msg_ontape:
  DB 8," on TAPE"

; ~64 bytes error messages
msg_exp:  DB 8,"Missing "
msg_syn:  DB 7,"Problem"
msg_div:  DB 8,"Div by 0"
msg_ovf:  DB 7,"Too big"
msg_prg:  DB 7,"Corrupt"
msg_var:  DB 9,"Not set: "
msg_typ:  DB 10,"Wrong type"
msg_rng:  DB 6,"Range?"
msg_blk:  DB 5,"Block"
msg_esc:  DB 8,13,13,"Escape"


; ------------------------------------------------------------------------------
; PAGE 6 - Statement Tokens

ORG BasROM+$600

; Statement Index (MUST be at offset 0)
stmt_page:
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
OP_LOAD    = $CF
OP_MODE    = $D0
OP_NEXT    = $D1
OP_OPT     = $D2
OP_OPEN    = $D3
OP_PUT     = $D4
OP_PRINT   = $D5
OP_PLOT    = $D6
OP_POKE    = $D7
OP_READ    = $D8
OP_REPEAT  = $D9
OP_RESTORE = $DA
OP_RETURN  = $DB
OP_REM     = $DC
OP_SOUND   = $DD
OP_UNTIL   = $DE
OP_WAIT    = $DF

kws_at:
kws_a:
kws_b:
kws_c:
kw_cls    DB "CLS",      OP_CLS    -0     ; bit 6 set for more ($C0)
kw_close  DB "CLOSE",    OP_CLOSE  -$40   ; bit 6 clear to end ($C0-$40)
kws_d:
kw_data   DB "DATA",     OP_DATA   -0
kw_dim    DB "DIM",      OP_DIM    -0
kw_def    DB "DEF",      OP_DEFFN  -$40
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
kw_load   DB "LOAD",     OP_LOAD   -$40
kws_m:
kw_mode   DB "MODE",     OP_MODE   -$40
kws_n:
kw_next   DB "NEXT",     OP_NEXT   -$40
kws_o:
kw_opt    DB "OPT",      OP_OPT    -0
kw_open   DB "OPEN",     OP_OPEN   -$40
kws_p:
kw_put    DB "PUT",      OP_PUT    -0
kw_print  DB "PRINT",    OP_PRINT  -0     ; [#ch,]
kw_plot   DB "PLOT",     OP_PLOT   -0
kw_poke   DB "POKE",     OP_POKE   -$40
kws_q:
kws_r:
kw_read   DB "READ",     OP_READ     -0
kw_rept   DB "REPEAT",   OP_REPEAT   -0
kw_rest   DB "RESTORE",  OP_RESTORE  -0
kw_retr   DB "RETURN",   OP_RETURN   -0
kw_rem    DB "REM",      OP_REM      -$40
kws_s:
kw_soun   DB "SOUND",    OP_SOUND  -$40
kws_t:
kws_u:
kw_until  DB "UNTIL",    OP_UNTIL  -$40
kws_v:
kws_w:
kws_x:
kws_y:
kws_z:
kw_wait   DB "WAIT",     OP_WAIT   -$40

; Statement Reverse Lookup
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
  DB (kw_load - stmt_page)    ; "LOAD",$CF
  DB (kw_mode - stmt_page)    ; "MODE",$D0
  DB (kw_next - stmt_page)    ; "NEXT",$D1
  DB (kw_opt - stmt_page)     ; "OPT",$D2
  DB (kw_open - stmt_page)    ; "OPEN",$D3
  DB (kw_put - stmt_page)     ; "PUT",$D4
  DB (kw_print - stmt_page)   ; "PRINT",$D5
  DB (kw_plot - stmt_page)    ; "PLOT",$D6
  DB (kw_poke - stmt_page)    ; "POKE",$D7
  DB (kw_read - stmt_page)    ; "READ", $D8
  DB (kw_rept - stmt_page)    ; "REPEAT",$D9
  DB (kw_rest - stmt_page)    ; "RESTORE",$DA
  DB (kw_retr - stmt_page)    ; "RETURN",$DB
  DB (kw_rem - stmt_page)     ; "REM",$DC
  DB (kw_soun - stmt_page)    ; "SOUND",$DD
  DB (kw_until - stmt_page)   ; "UNTIL",$DE
  DB (kw_wait - stmt_page)    ; "WAIT",$DF


; @@ skip_spc
skip_spc2:          ; skip spaces
  LDX #0           ; [2] X=0
@loop:             ; A=next-char
  LDA (InPtr,X)    ; [6] next input char
  INC InPtr        ; [5] advance input (assume match)
  CMP #32          ; [2] was it space?
  BEQ @loop        ; [2] -> loop [+1]
  DEC InPtr        ; [5] undo advance (didn't match)
  RTS              ; [6] // [28] +13

; @@ skip_spc
skip_spc:          ; skip spaces
  LDX E            ; [3] X=ofs
@loop:             ; A=next-char
  LDA LineBuf,X    ; [4] next input char
  INX              ; [2] advance input (assume match)
  CMP #32          ; [2] was it space?
  BEQ @loop        ; [2] -> loop [+1]
  DEX              ; [2] undo advance (didn't match)
  STX E            ; [3] update E=ofs
  RTS              ; [6] // [24] +14

; @@ is_digit
is_digit:          ; A=char -> A=[0..9], CC=found (preserves X,Y)
  SEC              ; [2] for subtract
  SBC #48          ; [2] make '0' be 0
  CMP #10          ; [2] 10 digits (CS if >= 10)
  RTS              ; [6] -> A=digit CC=found [12]

; @@ is_alpha
is_alpha:          ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  AND #$DF         ; [2] lower -> upper (clear bit 5)
  SEC              ; [2] for subtract
  SBC #64          ; [2] make '@' be 0
  CMP #27          ; [2] 27 letters including `@` (CS if >= 27)
  RTS              ; [6] -> A=az-index CC=alpha [14]

; @@ print_u16
; print a U16 in Acc
print_u16:          ; Acc=U16 (uses A,X)
  LDA #0
  STA Acc2
  STA AccE
  JMP num_print     ; from Acc (uses A,X)


; ------------------------------------------------------------------------------
; PAGE 7 - Expression Tokens

ORG BasROM+$700
kwtab: ; ??

; Expression Index (MUST be at offset 0)
expr_page:
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


; EXPRESSION TOKENS

OP_ABS = $80
OP_ASC = $81
OP_AND = $9D       ; binary op
OP_BTN = $82
OP_CHR = $83
OP_DIV = $9E       ; binary op
OP_EOF = $84
OP_EOR = $9F       ; binary op
OP_FN  = $85
OP_ELSEA = $86     ; to match OP_ELSE $C6 (i.e. $86 + $40)
OP_GET = $87
OP_INSTR = $88
OP_INT = $89
OP_JOY = $8A
OP_KEY = $8B
OP_LEN = $8C
OP_LEFT = $8D
OP_MID = $8E
OP_MOD = $A0       ; binary op
OP_NOT = $A1       ; unary op
OP_OR  = $A2       ; binary op
OP_POS = $8F
OP_PI = $90
OP_RIGHT = $91
OP_RND = $92
OP_SCN = $93
OP_STRING = $94
OP_STR = $95
OP_SQR = $96
OP_SGN = $97
OP_STEP = $A3      ; `FOR` keyword
OP_TIME = $98
OP_TO = $A4        ; `FOR` keyword
OP_THEN = $A5      ; `IF` keyword
OP_TOP = $99
OP_USR = $9A
OP_VAL = $9B
OP_VPOS = $9C
OP_FNRET = $A6
; print functions
OP_SPC   = $A7       ; SPC(n)
OP_TAB   = $A8       ; TAB(n)
OP_AT    = $A9       ; PRINT AT x,y
OP_IDX   = $AA       ; Array index: n, <dim-exprs>
; operators
OP_PAREN = $AB
OP_UNEG = $AC
OP_ADD = $AD
OP_SUB = $AE
OP_MUL = $AF
OP_DIV = $B0
OP_POW = $B1
OP_IDIV = $B2
OP_IMOD = $B3
OP_STRL = $B4
OP_NOT = $B5


OP_I0    = $F0       ; 1-byte
OP_I9    = $F9       ; 1-byte
OP_INT2  = $FA       ; 2-byte (opc|int8)
OP_INT3  = $FB       ; 3-byte (opc|int16)
OP_INT4  = $FC       ; 4-byte (opc|int24)
OP_FLT2  = $FD       ; 2-byte (opc|mant8)         [".X" = 0.X]
OP_FLT3  = $FE       ; 3-byte (opc|exp8|mant8)    ["1.2"; "2.55"; "10.2"]
OP_FLT4  = $FF       ; 4-byte (opc|exp8|mant16)   ["99.99", "1.9876"]
OP_FLT5  = $EF       ; 5-byte (opc|exp8|mant24)   ["987654.3", "9.876543"]

; operators in precedence order:
; 24:<< 25:<= 26:<> 28:>< 29:>= 30:>>
OP_EQ    = 61        ; binary `=`
OP_NE    = 26        ; binary
OP_LT    = 60        ; binary `<`
OP_LE    = 25        ; binary
OP_GT    = 62        ; binary `>`
OP_GE    = 29        ; binary

expr_at:
expr_a:
ex_abs  DB "ABS",     OP_ABS    +$40     ; fn (0,0)  bit 6 set for more ($80+$40)
ex_asc  DB "ASC",     OP_ASC    +$40     ; fn (0,1)  bit 6 clear to end ($80)
ex_and  DB "AND",     OP_AND    +0       ; binary op
expr_b:
ex_btn  DB "BTN",     OP_BTN    +0       ; BTN(n) joystick button
expr_c:
ex_chr  DB "CHR$",    OP_CHR    +0       ; fn$ (1,1)
expr_d:
ex_div  DB "DIV",     OP_DIV    +0       ; binary op
expr_e:
ex_eof  DB "EOF",     OP_EOF    +$40     ; # function (2,0)
ex_eor  DB "EOR",     OP_EOR    +$40     ; binary op
ex_else DB "ELSE",    OP_ELSEA  +0       ; keyword
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
ex_mid  DB "MID$",    OP_MID    +$40     ; fn$ (1,3) 1st is $
ex_mod  DB "MOD",     OP_MOD    +0       ; binary op
expr_n:
ex_not  DB "NOT",     OP_NOT    +0       ; unary op
expr_o:
ex_or   DB "OR",      OP_OR     +$40     ; binary op
expr_p:
ex_pos  DB "POS",     OP_POS    +$40     ; fn-or-fn# (B,0)  cursor x
ex_pi   DB "PI",      OP_PI     +0       ; no-arg (0,0)
expr_q:
expr_r:
ex_rgt  DB "RIGHT$",  OP_RIGHT  +$40     ; fn$ (1,2) 1st is $
ex_rnd  DB "RND",     OP_RND    +0       ; fn (0,1)
expr_s:
ex_scn  DB "SCN",     OP_SCN    +$40     ; SCN(x,y)  get screen x,y
ex_stri DB "STRING$", OP_STRING +$40     ; fn$ (n,s) 2nd is $
ex_str  DB "STR$",    OP_STR    +$40     ; fn$ (1,1) 1st is $
ex_sqr  DB "SQR",     OP_SQR    +$40     ; fn (0,1)
ex_sgn  DB "SGN",     OP_SGN    +$40     ; fn (0,1)
ex_step DB "STEP",    OP_STEP   +0       ; `FOR` keyword
expr_t:
ex_time DB "TIME",    OP_TIME   +$40     ; no-arg (0,0)
ex_to   DB "TO",      OP_TO     +$40     ; `FOR` keyword
ex_then DB "THEN",    OP_THEN   +$40     ; `IF` keyword
ex_top  DB "TOP",     OP_TOP    +0       ; no-arg (0,0)
expr_u:
ex_usr  DB "USR",     OP_USR    +0       ; fn (0,1)
expr_v:
expr_w:
expr_x:
expr_y:
expr_z:
ex_val  DB "VAL",     OP_VAL    +$40     ; fn (0,1)
ex_vps  DB "VPOS",    OP_VPOS   +0       ; no-arg (3,0)   cursor y

ex_fnret: DB "=", $80

; LIST keywords (keep on one page for Y indexing)
 ; note: `kwtab` is at start of page
kwt_print:
  DB "AT",       $B0      ; AT(x,y) in PRINT
  DB "SPC",      $B1      ; SPC(n) in PRINT
  DB "TAB",      $B2-$40  ; TAB(n) in PRINT

; Expression Reverse Lookup
expr_rev:                  ; [38]
  DB (ex_abs - expr_page)  ; "ABS",$80
  DB (ex_asc - expr_page)  ; "ASC",$81
  DB (ex_btn - expr_page)  ; "BTN",$82
  DB (ex_chr - expr_page)  ; "CHR",$83
  DB (ex_eof - expr_page)  ; "EOF",$84
  DB (ex_fn  - expr_page)  ; "FN",$85
  DB (ex_else - expr_page) ; "ELSE",$86
  DB (ex_get - expr_page)  ; "GET",$87
  DB (ex_ins - expr_page)  ; "INSTR",$88
  DB (ex_int - expr_page)  ; "INT",$89
  DB (ex_joy - expr_page)  ; "JOY",$8A
  DB (ex_key - expr_page)  ; "KEY",$8B
  DB (ex_len - expr_page)  ; "LEN",$8C
  DB (ex_lft - expr_page)  ; "LEFT",$8D
  DB (ex_mid - expr_page)  ; "MID",$8E
  DB (ex_pos - expr_page)  ; "POS",$8F
  DB (ex_pi  - expr_page)  ; "PI",$90
  DB (ex_rgt - expr_page)  ; "RIGHT",$91
  DB (ex_rnd - expr_page)  ; "RND",$92
  DB (ex_scn - expr_page)  ; "SCN",$93
  DB (ex_stri - expr_page) ; "STRING",$94
  DB (ex_str - expr_page)  ; "STR",$95
  DB (ex_sqr - expr_page)  ; "SQR",$96
  DB (ex_sgn - expr_page)  ; "SGN",$97
  DB (ex_time - expr_page) ; "TIME",$98
  DB (ex_top - expr_page)  ; "TOP",$99
  DB (ex_usr - expr_page)  ; "USR", $9A
  DB (ex_val - expr_page)  ; "VAL",$9B
  DB (ex_vps - expr_page)  ; "VPOS",$9C
  DB (ex_and - expr_page)  ; "AND",$9D   operator
  DB (ex_div - expr_page)  ; "DIV",$9E   operator
  DB (ex_eor - expr_page)  ; "EOR",$9F   operator
  DB (ex_mod - expr_page)  ; "MOD",$A0   operator
  DB (ex_not - expr_page)  ; "NOT",$A1   operator
  DB (ex_or - expr_page)   ; "OR",$A2    operator
  DB (ex_step - expr_page) ; "STEP",$A3  keyword
  DB (ex_to - expr_page)   ; "TO",$A4    keyword
  DB (ex_then - expr_page) ; "THEN",$A5  keyword
  DB (ex_fnret - expr_page); "=",$A6     special


; @@ emit_place
; emit a placeholder byte, set current placeholder
emit_place:         ; (uses A,X; preserves Y; sets PL)
  LDX EmitOfs       ; [3] get emit offset
  STX EmitPtch      ; [3] set placeholder patch address
  LDA #$FF          ; [2] emit $FF
  ; +++ fall through +++

; @@ emit_byte
; Emit an opcode at Emit,X and advance EmitOfs.
emit_byte:           ; (uses X; preserves A,Y -> NE,PL)
  LDX EmitOfs        ; [3] get emit offset
  STA EmitBuf,X      ; [5] emit token
  INC EmitOfs        ; [5] advance emit offset (NE)
  BMI @ovf           ; [2] -> overflowed emit buffer [+1] -> MI
  RTS                ; [6] -> NE,PL [21]
@ovf:
  LDY #<msg_ovf
  JMP report_err     ; [3] -> overlow

; @@ patch_len
; patch current placeholder with emitted length
patch_len:          ; (uses A,X; preserves Y) -> NE=found
  LDA EmitOfs       ; [3] A = emit_ofs
  CLC               ; [2] minus 1 (exclude patched byte)
  SBC EmitPtch      ; [3] A = emit_ofs - patch_addr (i.e. length)
  ; +++ fall through +++

; @@ patch_byte
; patch the current placeholder
patch_byte:         ; A=patch (uses X) -> NE=found
  LDX EmitPtch      ; [3] get placeholder patch address
  BEQ @noplace      ; [2] -> no current patch address -> EQ
  STA EmitBuf,X     ; [5] write fixup byte -> NE
@noplace:
  JMP uCodeLoop     ; [3] -> continue


; ------------------------------------------------------------------------------
; PAGE 8 - Support Routines

DB "SUP"


; @@ dbghex
dbghex:
  JSR prhex         ; [DEBUG] A=byte; (uses A,X,F,Src,Dst) preserves Y
  LDA #32           ; [DEBUG]
  JSR wrchr         ; [DEBUG] A=char; (uses A,X,F,Src,Dst) preserves Y
  RTS

; DEBUG routine
debug:
  LDY EmitOfs       ; [DEBUG]
  LDA #0            ; [DEBUG]
  STA EmitBuf,Y     ; [DEBUG]
  TAY               ; [DEBUG]
@lp:
  LDA EmitBuf,Y     ; [DENUG]
  BEQ @repl         ; [DEBUG]
  STA Acc0          ; [DEBUG]
  LDA #0            ; [DEBUG]
  STA Acc1          ; [DEBUG]
  STA Acc2          ; [DEBUG]
  STA AccE          ; [DEBUG]
  JSR dbghex        ; [DEBUG] (uses A,X,F,Src,Dst) preserves Y
  INY               ; [DEBUG]
  BNE @lp           ; [DEBUG]
@repl:
  JMP repl



; @@ match_kws
; find matching keyword, terminated by a byte with top-bit set (8x,9x,Ax,Bx)
; if no match, continue until bit 6 is set (Cx,Dx,Ex,Fx)
; note: XA table cannot cross a page boundary (INC/DEC Src would wrap)
match_kws:       ; E=ofs (KWPage LetterIdx) -> CF=found, E=ofs, A=hi-byte (uses A,X,Y,B,Src)
  LDA (uCode),Y  ; [4] get keyword page <tab> ($C4,C6,C7)
  STA SrcH       ; [3] SrcH = keyword page
  INY            ; [2] increment PC
  STY B          ; [3] save Y=uCode
  JSR skip_spc   ; [6] A=next-char, E=ofs
  JSR is_alpha   ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCS @jump      ; [2] -> no letter, take jump [+1]
  TAY            ; [2] Y = letter index
  LDX #0         ; [2] X = 0 const
  STX Src        ; [3] Src = 0
  LDA (Src),Y    ; [4] A = 1st KW ofs from KWPage,Y
  STA Src        ; [3] Src = 1st KW ofs
@next_kw:
  LDY E          ; [3] Y = input ofs
  DEY            ; [2] set up for pre-increment
  DEC Src        ; [5] set up for pre-increment
@match_lp:
  INY            ; [2] pre-increment input position
  INC Src        ; [5] pre-increment keyword position
  LDA (Src,X)    ; [6] next keyword char
  BMI @matched   ; [2] -> matched keyword (found hi-byte) [+1] (MUST check LDA flags not CMP flags)
  CMP LineBuf,Y  ; [4] does it match input?
  BEQ @match_lp  ; [2] -> yes, next char [+1]
@skip_lp:        ; no match
  INC Src        ; [5] find hi-byte at end of KW
  LDA (Src,X)    ; [6] get next KW byte
  BPL @skip_lp   ; [2] -> top bit clear, keep going [+1]
  INC Src        ; [5] advance over hi-byte
  ASL            ; [2] test bit 6 (continue bit)
  BMI @next_kw   ; [2] -> bit 6 set, try next keyword [+1]
  LDY B          ; [3] restore Y=uCode
;  JMP uOpG       ; [3] -> jump to <addr>  XXX
@matched:        ; found match
  PHA            ; [3] push hi-byte
  STY E          ; [3] save post-match input ofs
  LDY B          ; [3] restore Y=uCode
  INY            ; [2] skip jump <addr>
  JMP uCodeLoop  ; [3] -> next op
@jump:
  JMP ucJmp      ; [3] -> take jump

; ------------------------------------------------------------------------------
; Insert Line

; @@ ins_line
; insert EmitBuf into the program at LineNo

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

ins_line:           ; LineNo
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

; ------------------------------------------------------------------------------
; LIST Output

list:               ; CODE,Y at start of first line
  LDY #0            ;
  STY Acc2          ; clear
  STY AccE          ; clear
  INY               ; point at LineL
  LDA (CODE),Y      ; get LineL
  STA Acc0          ; set Acc
  INY               ; point at LineH
  LDA (CODE),Y      ; get LineH
  STA Acc1          ; set Acc
  AND Acc0          ; (Acc0 AND Acc1)
  CMP #255        ; is it 0xFFFF
;  BEQ list_end      ; -> end of program
  JSR num_print     ; print a number on the stack (uses A,X)
  LDA #32           ; space
  JSR wrchr         ; print char (A=char, uses A,X)
  INY               ; skip LineLen
  INY               ; skip PrevLen
list_stmt:
list_end:
  RTS

; ------------------------------------------------------------------------------
; Print Hex

; @@ prhex
; print a byte in hex
prhex:              ; A=byte; (uses A,X,F,Src,Dst) preserves Y
  PHA               ; save A
  LSR               ; shift top 4 bits down
  LSR               ; 
  LSR               ; 
  LSR               ; 
  JSR @dig          ; print digit
  PLA               ; restore A
  AND #15           ; keep low 4 bits
@dig:
  CMP #10           ; is it >10 ?
  BCS @let          ; -> yes, print letter (CF=1)
  ADC #$FA          ; add 48 - 54 (-6)
  CLC               ; set CF=0 (for digits >=6)
@let:               ; 
  ADC #54           ; 'A'65 - 10 - 1(CF)
  JMP wrchr         ; -> write char (uses A,X,F,Src,Dst) preserves Y







; ------------------------------------------------------------------------------
; PAGE 8 - BASIC Runtime

; ORG BasROM+$800



; ------------------------------------------------------------------------------
; BASIC Interpreter
; Y = code offset (persistent)

DB "RUN"

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
  DB <do_load
  DB <do_mode
  DB <do_next
  DB <do_opt
  DB <do_open
  DB <do_put
  DB <do_print
  DB <do_plot
  DB <do_poke
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
  DB >do_load
  DB >do_mode
  DB >do_next
  DB >do_opt
  DB >do_open
  DB >do_put
  DB >do_print
  DB >do_plot
  DB >do_poke
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
VT_NUM = $80
VT_STR = $81
VT_NUM_ARR = $82
VT_STR_ARR = $83


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
;  LDY #<aSyn
;  JMP uCodeEnt   ; [3] -> jump to error handler (pushing A)


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
  JSR do_expr_i  ; [12+] numeric expr (uses A,X,Y,???)
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
  JSR find_line    ; find matching line (Acc01 -> Ptr, CS=found)
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
  JSR find_line     ; find matching line (Acc01 -> Ptr, CS=found)
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


; LOAD <expr_s>
do_load:
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
  TAX
  JSR vid_mode     ; set mode (X=mode, uses A,X,Y,B)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt

; WAIT frames
do_wait:
  JSR do_expr_i8   ; A = i8   (XX need to save Y?)
  TAX
  BNE @loop        ; -> non-zero
  INX              ; wait 0 -> wait 1
@loop:
  LDA IO_LINE      ; get vertical line counter
  CMP #192       ; at bottom of screen?
  BNE @loop        ; wait for line == 192
@stall:
  LDA IO_LINE      ; get vertical line counter
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

; PUT x, y, char
do_put:
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
;  LDY #<aSyn     ; XXX uVar
;  JMP uCodeEnt

do_syn1:
;  LDY #<aSyn
;  JMP uCodeEnt


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
;  LDY #<aRange
;  JMP uCodeEnt


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
; Numeric Evaluator

  DB "EVAL"

badprg:
;  LDY #<aSyn
;  JMP uCodeEnt

eval_s:    ; XXX
  RTS

e_typ1:
;  LDY #<aSyn    ; XXX uType
;  JMP uCodeEnt

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

DB "NUMS"


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
  LDX ExpTop     ; [3] top of expr stack (full descending from $180)
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
  INX            ; [2] ExpTop += 4
  INX            ; [2]
  INX            ; [2]
  INX            ; [2]
  STX ExpTop     ; [3] pop the top expr        +11
  RTS            ; [6] // 71 (was 60)          +6


; @@ num_u16
; tokenize a line number (0-65535)
num_u16:         ; Y=ofs (uses A,Y,B,C,Term) -> Acc,Y,NE=found
  STY C          ; save ofs
  JSR num_u24    ; from LineBuf,Y -> Y,Acc,CS=found (uses A,Y,B,C,Term)
  BCS num_range  ; -> out of range
  LDA Acc2       ; high byte is non-zero (or number is negative)
  ORA AccE       ; exponent is non-zero (a float)
  BNE num_range  ; -> out of range, negative, on non-integer
  CPY C          ; NE if found; EQ not-found
  RTS

num_range:
;  LDY #<aRange
;  JMP uCodeEnt

tok_clc:
  CLC
  RTS            ; CC=not-found

; @@ num_val
; parse a 24-bit number with optional sign prefix (TODO: floating point) (TODO: from (Ptr),Y ?)
num_val:         ; from LineBuf,Y -> Y,Acc,CS=ovf (uses A,B,X,Term)
  LDA #0
  STA B          ; [3] sign=$00
  LDA LineBuf,Y  ; [5] get first char
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
num_u24:         ; from LineBuf,Y-> Y,Acc,CS=ovf (uses A,X,Term)
  LDA #0         ; [2] length of num
  STA Acc0       ; [3] clear result
  STA Acc1       ; [3]
  STA Acc2       ; [3]
  STA AccE       ; [3]
@loop:           ; -> 14+76+25 [115]
  LDA LineBuf,Y  ; [5] get next char
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
  JSR wrchr      ; print it (uses A,X,F,Src,Dst) preserves Y
  BNE @print     ; always (OK unless wrchr scrolled) XXX
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
; ------------------------------------------------------------------------------
; SYSTEM ROM - 2K

ORG BasROM+$1000
BASE SysROM

; Graphics routines
; Number conversion
; Sound routines
; Cassette routines
; Serial routines
; Parallel routines


; ------------------------------------------------------------------------------
; Sys ROM - GRAPHICS ROUTINES

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
; OS Routines

; last 1KB
ORG SysROM+$400

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
  STY IO_KEYB     ; [3] set keyscan row (0-7)              0µs (-> 7+3=10µs after prior)
  NOP             ; [2] delay                              2µs
  LDX IO_KEYB     ; [3] read col_bitmap                    2+3µs read 5/0.89Mhz = 5.6µs settle
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
  CPX IO_KEYB     ; [3] check if stable                    3+3µs read 6/0.89Mhz = 6.7µs verify
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
; AUTO-REPEAT: the last key held (save its scancode to compare)
; ROLLOVER: pressing a new key replaces the prior held key
; INKEY(-K): directly scans the key (5:3 col:row)
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
; PRINT, WRCHR, WRCTL, NEWLINE

; @@ printmsgln
; println a string in the messages page
printmsgln:       ; Y=msg (uses A,B,X,Y,F,Ptr,Src,Dst)
  JSR printmsg    ; -> print it
  JMP newline     ; -> print \n

; @@ printmsg
; print a string in the messages page
printmsg:
  LDX #>messages  ; high byte
  ; +++ fall through +++

; @@ print, in text mode
; write a length-prefix string to the screen in text-mode
print:           ; X=high Y=low (uses A,B,X,Y,Ptr,Src,Dst) -> Y = strlen (excludes length byte)
  STX PtrH       ; [3] pointer high
  STY Ptr        ; [3] pointer low
  LDY #0         ; [2] string offset, counts up
  LDA (Ptr),Y    ; [5] load string length
  BEQ @ret       ; [2] -> nothing to print [+1]
  STA B          ; [3] length to print
@loop:
  INY            ; [2] advance to next char              2
  LDA (Ptr),Y    ; [5] load char from string             7
  ; begin wrchr inline
  CMP #32        ; [2] is it a control character?        9
  BCC @ctrl      ; [2] if <32 -> @ctrl [+1]              11
  LDX #0         ; [2] const for (TXTP,X) - each time for @nlpg and @ctrl
  STA (TXTP,X)   ; [6] write character to video memory   17
  INC TXTP       ; [5] advance text position             22
  BEQ @nlpg      ; [2] -> crossed page boundary [+1]
  ; end wrchr inline
@incr:
  CPY B          ; [3] equals length?                    32
  BNE @loop      ; [2] not at end -> @loop [+1]          35 per char!
@ret:
  RTS            ; [6] done -> Y = strlen, EQ (excludes length byte)
@nlpg:           ; crossed a page boundary
  JSR nl_page    ; *** crossed a page boundary (uses A,X,F,Src,Dst) preserves Y
  JMP @incr      ; [3] -> always
@ctrl:
  JSR wrctl      ; *** execute control code (uses A,X,F,Src,Dst) preserves Y
  JMP @incr      ; [3] -> always


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
  BNE nl_npg      ; [2] -> no page-cross [+1]
nl_page:          ; crossed a page boundary (uses A,X,F,Src,Dst preserves Y)
  LDX TXTPH       ; [3] test TXTPH
  INX             ; [2] plus 1, to start of next page
  CPX MemSize     ; [3] off bottom of screen?
  BEQ nl_scrup    ; [2] -> scroll up [+1]
  STX TXTPH       ; [3] go down one page
nl_npg:
  RTS             ; [6] -> NE (unless scrolled, assumes no 64K wraparound)

; @@ wrchr       (95b wrchr + newline)
; write a single character to the screen
; assumes we're in text mode with TXTP set up
wrchr:            ; A=char; (uses A,X,F,Src,Dst) preserves Y [25]
  CMP #32         ; [2] is it a control character?
  BCC wrctl       ; [2] -> ch < 32, do control code [+1]  (uses A,X preserves Y)
  LDX #0          ; [2] const for (TXTP,X) ie (TXTP)
  STA (TXTP,X)    ; [6] write character to video memory
  INC TXTP        ; [5] advance text position
  BEQ nl_page     ; [2] -> crossed page boundary [+1]
  RTS             ; [6] -> NE (unless scrolled)

; @@ nl_scrup
; scroll the text window up one line
nl_scrup:          ; (uses A,X,F,Src,Dest) preserves Y
  TYA              ; save Y for caller
  PHA
; set up Src
  LDY WinT         ; 
  INY              ; row = WinT-1
  TYA              ;
  JSR txt_row      ; A=row -> AY=addr (uses A,X,Y,F)
  STA SrcH
  STY Src
; set up Dst
  LDA WinT         ; row = WinT
  JSR txt_row      ; A=row -> AY=addr (uses A,X,Y,F)
  STA DstH
  STY Dst
; scroll up one line
  LDY WinH
  DEY              ; rows = WinH - 1
  BEQ @noscr       ; -> height = 1, no scroll
  TYA              ; 
  JSR txt_row      ; A=rows -> AY=size+VidBase (uses A,X,Y,F)
  SEC
  SBC VidBase      ; AY=size (subtract VidBase)
  TAX
  JSR mcopyf       ; copy forwards XY=size (uses A,X,Y,F,Src,Dst)
@noscr:
; clear the bottom row
  LDA WinT         ; XX in support of WinB
  CLC
  ADC WinH         ; bottom of window (too far)
  ADC #$FF         ; minus 1
  LDX #0
  JSR txt_addr_tp  ; A=row X=0 -> AY=TXTP (uses A,X,Y,F)
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
  RTS            ; 

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


; ------------------------------------------------------------------------------
; READLINE, LINE EDITOR

; Arrows move within the line; insert or delete text within the line.
; TAB calls up an existing line in edit mode.

; @@ readline
; read a single line of input into the line buffer (zero-terminated)
readline:         ; uses A,X,Y,B,C -> LineBuf, Y=length (EQ if zero)
  LDA #0          ; 
  STA B           ; init line length
  STA C           ; init line cursor (linear)
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
  LDY C           ; current cursor position
  CPY #$7F        ; is buffer full?
  BEQ @more       ; buffer full -> do nothing
  STA LineBuf,Y   ; write to line buffer   (XXX shift up rest of buffer)
  INC B           ; increase line length
  INC C           ; advance line cursor
  JSR wrchr       ; print A=char (uses A,X,F,Src,Dst) preserves Y
@more:            ; keep reading chars
  JSR readchar    ; from keyboard (uses A,X,Y -> A,ZF)
  BNE @cont       ; -> got another char
  BEQ @idle       ; -> return to idle
@ctrl:
  CMP #13         ; is it RETURN?
  BEQ @return     ; -> return
  LDY C           ; get cursor (C)
  BEQ @noleft     ; -> cannot move left
  CMP #8          ; is it BACKSPACE?
  BEQ @backsp     ; -> backspace
  CMP #$1E        ; is it Left Arrow
  BEQ @left       ; -> move cursor left
@noleft:
  CMP #$1F        ; is it Right Arrow
  BEQ @right      ; -> move cursor right
  BNE @more       ; -> always
@esc:
  JSR hide_cursor ; uses A,Y; Y=0
  JMP escape
@backsp:
  DEC B           ; length -= 1
@left:
  DEY             ; cursor -= 1 (move left)
@wrcur:
  STY C           ; update cursor
  JSR wrctl       ; move left on the display (A=1) (uses A,X, preserves Y -> CC=fail)
  JMP @more
@right:
  CPY B           ; cursor == length?
  BEQ @more       ; -> at end of buffer, do nothing
  INY             ; cursor += 1 (move right)
  BNE @wrcur      ; -> always
@return:
  LDY B           ; get line length
  LDA #0          ; terminator
  STA LineBuf,Y   ; write terminator to line buffer
  RTS             ; returns Y=length (ZF=1 if zero)


; ------------------------------------------------------------------------------
; MODE, CLS, TAB, text_addr_xy

; Mode table:
;           0    1      2      3      4       5
;           Text 128x96 128x96 256x96 128x192 256x192
;           1bpp 1bpp   2bpp   1bpp   2bpp    1bpp
mode_ctl DB $80, $81,   $86,   $82,   $87,    $83
mode_siz DB 3,   6,     12,    12,    24,     24    ; in pages

; @@ vid_mode
vid_mode:        ; set screen mode, X=mode (uses A,X,Y,F)
  CPX #6         ; modes 0-5
  BCS vid_ret    ; -> bad mode
  LDA MemSize    ; get end of memory             $10
  SEC            ; for SBC
  SBC mode_siz,X ; subtract mode size in pages   $10 - 3 = $0D
  BCC vid_ret    ; -> not enough memory
  STA VidBase    ; set base of video memory
  STA IO_VPGC    ; set video page counter
  LDA mode_ctl,X ; get mode control
  STA IO_VCTL    ; set video mode
  LDA #0         ; BG=black FG=white (for APA mode)
  STA IO_PAL1    ; reset palette
  STA IO_PAL2    ; reset palette
  STA WinT       ; reset text window top
  LDA #24        ;
  STA WinH       ; reset text window height
  ; +++ fall through to @@ vid_cls +++

; @@ vid_cls
; clear the screen or text window
vid_cls:                 ; (uses A,X,Y,F)
  LDA WinT               ; [3] text window top
  LDX #0                 ; [2] col=0
  JSR txt_addr_tp        ; [6] A=row X=col -> TXTP(AY) (uses A,X,Y,F)
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
txt_addr_tp:       ; A=row X=col -> TXTP(XY) (uses A,X,Y)
  JSR txt_addr_ax  ; AX -> AY
  STA TXTPH        ; set TXTPH
  STY TXTP         ; set TXTP
vid_ret:
  RTS              ; 

; @@ txt_row
; calculate screen row address
txt_row:           ; A=row -> AY=addr (uses A,X,Y,F)
  LDX #0           ; col = 0
  ; +++ fall through to @@ txt_addr_ax +++

; @@ txt_addr_ax
; calculate screen address
txt_addr_ax:       ; A=row X=col -> AY=addr (uses A,X,Y,F)   (19b) [36]
  STX F            ; [3] [000XXXXX] -> F (tmp)
  ROR              ; [2] [0000YYYY]Y
  ROR              ; [2] [Y0000YYY]Y
  ROR              ; [2] [YY0000YY]Y
  TAX              ; [2] [YY0000YY] -> X (tmp)
  ROR              ; [2] [YYY0000Y]Y
  AND #$E0         ; [2] [YYY00000]
  ORA F            ; [3] [YYYXXXXX] <- F (tmp)
  TAY              ; [2] -> Y (low)
  TXA              ; [2] [YY0000YY] <- X (tmp)
  AND #3           ; [2] [000000YY]
  CLC              ; [2] for ADC
  ADC VidBase      ; [2] add video base page
  RTS              ; [6] -> AY=addr


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
; copy memory forwards from (Src) to (Dst) with XY=size       (31b)
; assume (Dst < Src) but Src/Dst may overlap 
mcopyf:                  ; (uses A,X,Y,F,Src,Dst)             X=$03 Y=$00
  TYA                    ; [2] is Y=0?                        A=$00
  BEQ @strt              ; [2] -> Y=0, no partial page [+1]   ->
  INX                    ; [2] pages++ for partial page
@strt:
  STX F                  ; [3] pages                          F=$03
  TAX                    ; [2] X=count
  LDY #0                 ; [2] ofs = 0                        Y=$00
@lp:
  LDA (Src),Y            ; [3] read byte       (Src),0  (Src),1 .. (Src),FF  (Src+1),0  (Src+1),1
  STA (Dst),Y            ; [3] write byte      (Dst),0  (Dst),1 .. (Dst),FF  (Dst+1),0  (Dst+1),1
  INY                    ; [2] ofs++
  BEQ @wrap              ; [2] -> Y=ofs wrap-around [+1]
@cont:
  DEX                    ; [2] count--                        X=$FF X=$FE .. X=$00 X=$FF X=$FE
  BNE @lp                ; [2] -> until count=0 [+1]          ->    ->       --    ->    ->
  DEC F                  ; [5] pages-- (X=0)                  (Pg1)          F=$02             F=$01       F=$00
  BNE @lp                ; [2] -> until pages=0 [+1]                         ->                ->          --
  RTS                    ; [6] done                                          (Pg2)             (Pg3)       RTS
@wrap:                   ; Y=ofs > 255 so bump both pages
  INC SrcH               ; [5] next Src page
  INC DstH               ; [5] next Dst page
  JMP @cont              ; [3] -> always (assume no 64K wraparound)

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
  ADC F                  ; [2] no CLC (assume no 64K wraparound)
  STA DstH               ; [3]
; begin copy
  TYA                    ; [2] is Y=0?
  BEQ @lp                ; [2] -> Y=0, no partial page [+1]
  INC F                  ; [5] pages++ for partial page
@lp:
  DEY                    ; [2] count--
  LDA (Src),Y            ; [3] read byte
  STA (Dst),Y            ; [3] write byte
  TYA                    ; [2] is count==0?
  BNE @lp                ; [3] -> until count=0
; back to previous page
  DEC SrcH               ; [5] Src -= 256
  DEC DstH               ; [5] Dst -= 256
  DEC F                  ; [5] pages-- (Y=0)
  BNE @lp                ; [2] -> until pages=0 [+1]
  RTS


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
  LDA CurChar     ; [3] get saved char
  LDY #0          ; [2] EQ
  STY CurVis      ; [3] clear top-bit (cursor hidden) (no flags)
  STA (TXTP),Y    ; [5] restore char under cursor (no flags)
  BEQ cur_ret     ; [3] -> always (EQ)
cur_show:         ; show cursor (uses A,Y; Y=0)
  LDY #0          ; [2]
  LDA (TXTP),Y    ; [5] get char under cursor
  STA CurChar     ; [3] save char under cursor
  LDA #$EF        ; [2] cursor block
  STA (TXTP),Y    ; [6] write cursor block
  LDA #$80        ; [2] set top bit (but not bit 6: inhibit)
  STA CurVis      ; [3] set top-bit (cursor now visible)
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
  PHA            ; save A
  TXA
  PHA            ; save X
  TYA
  PHA            ; save Y
; reset video base address
  LDA VidBase    ; video mode base page
  STA IO_VPGC    ; set video page counter
; keyboard scan
  LDA #32        ; acknowledge 5:KBInt
  STA IO_LINE    ; acknowledge interrupt
  JSR keyscan
; cursor blink
  DEC CurTime     ; [5]
  BNE @done       ; [2] -> not yet [+1]
  JSR cur_toggle  ; [] toggle cursor
@done:
  PLA            ; restore Y
  TAY
  PLA            ; restore X
  TAX
  PLA            ; restore A
nmi_vec:
  RTI

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
; JMP vid_mode        ; $FFE0  set screen mode, clear the screen            (JSR uses A,X,Y)
; JMP vid_cls         ; $FFE3  clear the screen                             (JSR uses A,X,Y)
; JMP txt_tab         ; $FFE6  move text cursor to X,Y within text window   (JSR uses A,X,Y)
; JMP basic           ; $FFE9  enter BASIC                                  (JMP)

; @@ CPU Vectors
ORG SysROM+$800-6
DW nmi_vec       ; $FFFA, $FFFB ... NMI vector
DW reset         ; $FFFC, $FFFD ... Reset vector
DW IrqVec        ; $FFFE, $FFFF ... BRK/IRQ vector
