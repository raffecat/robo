MonBase = $EC00

VidBase  = $02          ; first video page
VidLast  = $05          ; last video page

LineBuf  = $100         ; Input Buffer (128 bytes)  XXX must use the screen buffer
EmitBuf  = $100         ; Tokenized Emit Buffer (128 bytes)

IO_KEY     = $F8        ; Keyboard 8-bit (7:TXD 6:RTS 5:TapeOut 4:Speaker 3-0:KBCol) / read: KB row 8-bit
IO_IOR     = $F9        ; IO Read: (2:TapeIn 1:CTS 0:RXD)
IO_ACK     = $FA        ; IRQ Acknowledge

; ------------------------------------------------------------------------------
; Registers

RBase      = $60        ; Scratch space ($60-7F; 32 bytes)

Src        = RBase+0    ; source pointer (Scroll, KeyScan)
SrcH       = RBase+1    ; source pointer (Scroll, KeyScan)
Dst        = RBase+2    ; destn pointer (Scroll)
DstH       = RBase+3    ; destn pointer (Scroll)
Ptr        = RBase+4    ; third pointer (Code)
PtrH       = RBase+5    ; third pointer (Code)

B          = RBase+6    ; extra register | Subroutines are annotated with usage
C          = RBase+7    ; extra register | held across calls only when unused
D          = RBase+8    ; extra register | held across calls only when unused

ModKeys    = RBase+9    ; modifier keys [7:Esc 6:Shf 5:Ctl 4:Fn] (owned by IRQ)
CurrKey    = RBase+10   ; keyboard current key pressed, for auto-repeat (owned by IRQ)

TRemX      = RBase+11   ; remaining X positions
TXTP       = RBase+12   ; text write address
TXTPH      = RBase+13   ; text write address high

CurTime    = RBase+14   ; cursor flash timer

DbgA       = RBase+16   ; Scratch Space
DbgX       = RBase+17   ; Scratch Space
DbgY       = RBase+18   ; Scratch Space


; ------------------------------------------------------------------------------
; Monitor

ORG MonBase
dipg = MonBase

monitor:
  SEI
  CLD
  LDX #$FF
  TXS
; set up keyboard
  LDA #0
  STA CurrKey
  STA ModKeys
; enter monitor
  JSR cls
  LDY #welc - msgs
  JSR prmsg
repl:
  LDA #93  ; `]`
  JSR wrch
  JSR rdln
  JSR wrnl
  LDX #0
; parse hex addr
; ...
; parse command (A-F are HEX!)
  LDA LineBuf,X
  BEQ read  ; -> print one
  CMP #45   ; `-`
  BEQ dump  ; -> hex dump (range)
  CMP #58   ; `:`
  BEQ write ; -> write (hex)
  CMP #71   ; G
  BEQ goto  ; -> goto code
  CMP #65   ; A
  BEQ assem ; -> assemble
  CMP #68   ; D
  BEQ disas ; -> disassemble
err:
  LDY #what - msgs
  JSR prmsg
  JMP repl

disas:
assem:
goto:
read:
dump:
write:
  JMP repl


; ------------------------------------------------------------------------------
; MESSAGES

msgs:
welc  DB "Chroma Monitor",0
what  DB "What?",0



; -0            jumps(16)(odd=rel,even>8=#)       BEQ     0000
; -1 -5 -9 -D   high(16)/2=arith                  (A&3=1) 0001 0101 1001 1101
; -2            noop(A2=LDX#)                     DONE*
; -3 -7 -B -F   noop                              (A&3=3) 0011 0111 1011 1111
; -4            high=op4h    low=noop(24=BITzp)   DONE    0100
; -6 -A -E      low/2=shf    (-A.odd=noop)  high->3x8tab  (2)  0110 1010 1110 (A&3=2)
; -8            misc(16)                          DONE    1000
; -C            misc(16) BIT JMP LDY CPX                  1100 (A&3=0)




  PLA         ; [--HHHSLL] restore A 
  LSR         ; [---HHHSL]L  0001 0101 1001 1101
  BCS @c5D    ; -> -5 -D
; -1 -9
  LSR         ; [----HHHS]L  0001 0101 1001 1101
  BCS @c9     ; -> -9
; -1          ; (ind,X) or (ind,Y)
  PHA
  LDA #40     ; `(`
  JSR wrch    ; output (uses A,X,B)
  PLA  
  LSR         ; [-----HHH]S
  BCS @indY   ; -> (ind,Y)
; (ind,X)
  LDA #<n_IX  ; `,X)`
  BNE hxbp    ; -> hexb, print -> dinext
; (ind,Y)
@indY:
  LDA #<n_IY  ; `,Y)`
  BNE hxbp    ; -> hexb, print -> dinext
; -9
@c9:          ; #imm / abs,Y
  LSR         ; [-----HHH]S
  BCS @absY   ; -> abs,Y
; #imm
  LDA #35     ; `#`
  JSR wrch    ; output (uses A,X,B)
;
@x11: ; -3 -7 -B -F <<- (entirely noop)
@hxb:
  LDA #0
  BEQ hxbp    ; -> hexb -> dinext
; abs,Y
@absY:
  LDA #<n_cY  ; `,Y`
  BNE hxwp    ; -> hexw, print -> dinext
; -5 -D
@c5D:
  LSR         ; [----HHHS]L  0101 1101
  BCS @cD     ; -> -D
; -5          ; zpg / zpg,X
  LSR         ; [-----HHH]S
  BCC @hxb    ; -> zpg
; zpg,X
  LDA #<n_cX  ; `,X`
  BNE hxbp    ; -> hexb, print -> dinext
; -D
@cD:          ; abs / abs,X
  LSR         ; [-----HHH]S
  BCS @absX   ; -> abs,X
; abs
  LDA #0
  BEQ hxwp    ; -> hexw -> dinext
@absX:
  LDA #<n_cX  ; `,X`
  BNE hxwp    ; -> hexw, print -> dinext


hxbp:         ; hexb, [print A=mnem] -> dinext
  PHA         ; save A
  JSR hexb    ; output hex byte (from code)
hxcp:
  PLA         ; restore A
  BEQ @skip   ; -> no print
  JSR print   ; print mnemonic at A
@skip:
  JMP dinext  ; -> continue

hxwp:         ; hexw, [print A=mnem] -> dinext
  PHA         ; save A
  JSR hexw    ; output hex byte (from code)
  JMP hxcp    ; -> print, etc

hexb:
hexw:
  RTS



; ------------------------------------------------------------------------------
; DISASSEMBLER

ALIGN 256
di_pg = $

dinext:
  JSR wrnl
disas1:
; print address
  LDA PtrH
  JSR prhex
  LDA Ptr
  JSR wrhex
; decode instruction
  LDY #0       ;
  LDA (Ptr),Y  ; fetch opcode
  TAY          ; save opcode
  AND #15      ; low-nibble
  TAX          ; index
  LDA di_jmp,X ; low byte
  PHA          ;
  LDA #>di_pg  ; high byte
  PHA          ;
  TYA          ; restore opcode
  LSR          ; [0HHHHLLL]
  LSR          ; [00HHHHLL]
  LSR          ; [000HHHHL]
  LSR          ; [0000HHHH] low-nibble
  RTS          ; -> to handler

c_0:            ; A=high_nibble X=opcode (11b)
  CPY #$80      ; X=opcode
  BEQ c_ndef    ; -> not defined
  LDX #<n_0     ; 
  JSR prmne     ; print mnemonic (1 of 16)    needs A=high-nibble
; addressing mode:
; odd -> rel
; even.hi -> #imm
; $20 -> abs
; no addr

c_8:
  LDX #<n_8     ; 
  JSR prmne     ; print mnemonic (1 of 16)    needs A=high-nibble
; no addr
; a_none:

c_159D:         ; A=high_nibble X=opcode (7b)
  LDX #<n_159D  ; 
  JSR prmnd     ; print mnemonic (1 of 8)    needs A=high-nibble
c_adrs:         ; addressing mode:
; 0-3 ind,X / ind,Y
;a_ind:
; 4-7 zpg / zpg,X[Y]
a_zp_c:
a_zpg:
a_zpgX:
; 8-B #imm / abs,Y
a_imm:
; C-F abs / abs,X
a_ab_c:
a_abs:

c_2:            ; A=high_nibble X=opcode (12b)
  CPY #$A2      ; X=opcode (LDX #)
  BNE c_ndef    ; -> not defined
  LDA #<n_LDX   ; "LDX"
  JSR print     ; print mnemonic
  JMP a_imm     ; #imm

c_ndef:         ; not an opcode
  ; print hex

c_A:            ; A=high_nibble X=opcode      needs A=high-nibble
  PHA           ; push high nibble
  TAX           ; high nibble
  LDA di_cA,X   ; mnemonic
  BEQ c_ndef    ; -> not defined
  JSR print     ; print mnemonic
  PLA           ; pop high nibble
  ; addressing mode:
  BMI @none     ; -> no addr
  LDA #65       ; `A`
  JSR wrch      ; print it
@none:
  ; now what?


c_4:            ; A=high_nibble X=opcode       needs A=high-nibble
  TAX           ; high nibble
  LDA di_c4,X   ; mnemonic
  BEQ c_ndef    ; -> not defined
  JSR print     ; print mnemonic
  JMP a_zp_c    ; zpg / zpg,X

c_C:            ; A=high_nibble X=opcode      needs A=high-nibble
  CPY #$9C      ; same as 4, except $9C
  BEQ c_ndef    ; -> not defined
  TAX           ; high nibble
  LDA di_c4,X   ; mnemonic         XXX merge -C JMP opcodes with $80 flag
  BEQ c_ndef    ; -> not defined
  JSR print     ; print mnemonic
  JMP a_ab_c    ; abs / abs,X

c_6:            ; A=high_nibble X=opcode      needs A=high-nibble
  LDX #<n_6E    ; 
  JSR prmnd     ; print mnemonic (1 of 8)
  JMP a_zp_c    ; zpg / zpg,X

c_E:            ; A=high_nibble X=opcode      needs A=high-nibble
  CPY #$9E      ; same as 6, except $9E
  BEQ c_ndef    ; -> not defined
  LDX #<n_6E    ; 
  JSR prmnd     ; print mnemonic (1 of 8)
  JMP a_ab_c    ; abs / abs,X


di_jmp:
  DB <c_0    -1 ; 0
  DB <c_159D -1 ; 1
  DB <c_2    -1 ; 2
  DB 0       -1 ; 3
  DB <c_4    -1 ; 4
  DB <c_159D -1 ; 5
  DB <c_6    -1 ; 6
  DB 0       -1 ; 7
  DB <c_8    -1 ; 8
  DB <c_159D -1 ; 9
  DB <c_A    -1 ; A
  DB 0       -1 ; B
  DB <c_C    -1 ; C
  DB <c_159D -1 ; D
  DB <c_E    -1 ; E
  DB 0       -1 ; F


prmnd:        ; print mnemonic at (C=base + (A/2)*3)
  LSR         ; div 2
prmne:        ; print mnemonic at (C=base + A*3)
  STX C       ; save base (C)
  STA B       ; save A
  ASL         ; A*2
  CLC
  ADC B       ; A*2+A = 3*A
  ADC C       ; base(C) + 3*A
print:
  TAY
  LDA mnem,Y  ;
  JSR wrch    ; (uses A,X)
  INY
  LDA mnem,Y  ;
  JSR wrch
  INY
  LDA mnem,Y  ;
  JSR wrch
  LDA #32
  JSR wrch
  RTS



; ------------------------------------------------------------------------------
; MNEMONICS

ALIGN 256
mnem:            ; 56 opcodes
n_JMP  DB "JMP"  ; -4/C
n_STY  DB "STY"  ; -4/C
n_0:
n_BRK  DB "BRK"  ; • l=0: h*3
n_BPL  DB "BPL"  ; rel
n_JSR  DB "JSR"  ; abs•
n_BMI  DB "BMI"  ; rel
n_RTI  DB "RTI"  ; i
n_BVC  DB "BVC"  ; rel
n_RTS  DB "RTS"  ; i
n_BVS  DB "BVS"  ; rel
n_BIT  DB "BIT"  ; -4/C (not defined in n_0)
n_BCC  DB "BCC"  ; rel
n_LDY  DB "LDY"  ; #    -4/C  (both)
n_BCS  DB "BCS"  ; rel
n_CPY  DB "CPY"  ; #    -4/C  (both)
n_BNE  DB "BNE"  ; rel
n_CPX  DB "CPX"  ; #    -4/C  (both)  <<- must be <$40
n_BEQ  DB "BEQ"  ; rel
n_159D:
n_ORA  DB "ORA"  ; a l=159D: (h/2)*3
n_AND  DB "AND"  ; a
n_EOR  DB "EOR"  ; a
n_ADC  DB "ADC"  ; a
n_STA  DB "STA"  ; a
n_LDA  DB "LDA"  ; a
n_CMP  DB "CMP"  ; a
n_SBC  DB "SBC"  ; a
n_6E:
n_ASL  DB "ASL"  ; h l=6EA.0-7: (h/2)*3
n_ROL  DB "ROL"  ; h
n_LSR  DB "LSR"  ; h
n_ROR  DB "ROR"  ; h
n_STX  DB "STX"  ; h l=6E.8-F
n_LDX  DB "LDX"  ; h
n_DEC  DB "DEC"  ; h
n_INC  DB "INC"  ; h
n_8:
n_PHP  DB "PHP"  ; i l=8: h*3
n_CLC  DB "CLC"  ; i
n_PLP  DB "PLP"  ; i
n_SEC  DB "SEC"  ; i
n_PHA  DB "PHA"  ; i
n_CLI  DB "CLI"  ; i
n_PLA  DB "PLA"  ; i
n_SEI  DB "SEI"  ; i
n_DEY  DB "DEY"  ; i
n_TYA  DB "TYA"  ; i
n_TAY  DB "TAY"  ; i
n_CLV  DB "CLV"  ; i
n_INY  DB "INY"  ; i
n_CLD  DB "CLD"  ; i
n_INX  DB "INX"  ; i
n_SED  DB "SED"  ; i
;
n_TXA  DB "TXA"  ; implied
n_TXS  DB "TXS"
n_TAX  DB "TAX"
n_TSX  DB "TSX"
n_DEX  DB "DEX"
n_NOP  DB "NOP"
;
n_IX   DB ",X)"
n_IY   DB ",Y)"
n_cX   DB ",X "
n_cY   DB ",Y "

; ------------------------------------------------------------------------------
; TABLES

di_tab:
di_c4:
  DB 0         ; not defined
  DB 0         ; not defined
  DB <n_BIT    ;
  DB 0         ; not defined
  DB 0         ; not defined
  DB 0         ; not defined
  DB 0         ; not defined
  DB 0         ; not defined
  DB <n_STY    ;
  DB <n_STY    ;
  DB <n_LDY    ;
  DB <n_LDY    ;
  DB <n_CPY    ;
  DB 0         ; not defined
  DB <n_CPX    ;
  DB 0         ; not defined

di_cA:
  DB <n_ASL    ;
  DB 0         ; not defined
  DB <n_ROL    ;
  DB 0         ; not defined
  DB <n_LSR    ;
  DB 0         ; not defined
  DB <n_ROR    ;
  DB 0         ; not defined
  DB <n_TXA    ;
  DB <n_TXS    ;
  DB <n_TAX    ;
  DB <n_TSX    ;
  DB <n_DEX    ;
  DB 0         ; not defined
  DB <n_NOP    ;
  DB 0         ; not defined


; ------------------------------------------------------------------------------
; HEX

; @@ wrhex
wrhex:              ; (uses A,X,B,Src,Dst) preserves Y
  JSR prhex         ; A=byte; (uses A,X,F,Src,Dst) preserves Y
wrspc:
  LDA #32           ; 
  JMP wrch          ; A=char; (uses A,X,F,Src,Dst) preserves Y

; @@ prhex
; print a byte in hex
prhex:              ; A=byte; (uses A,X,B,Src,Dst) preserves Y
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
  JMP wrch          ; -> write char (uses A,X,F,Src,Dst) preserves Y


; ------------------------------------------------------------------------------
; PRMSG, CLS, HOME, WRCH, WRNL, WRBS, MCOPYF, READLINE, KEYSCAN  (512 bytes)

ORG MonBase + $600

_prlp:
  JSR wrch        ; (uses A,X,B,Src,Dst)
  INY
prmsg:            ; Y=msg
  LDA msgs,Y      ;
  BNE _prlp       ; -> continue
  ; +++ fall through +++

; write newline     (13b)
wrnl:             ; (uses A,X,B,Src,Dst) -> X=0
  LDA TRemX       ; [3] 40..1
  CLC             ; [2]
  ADC TXTP        ; [3]
  STA TXTP        ; [3]
  BCC wreon       ; [2] -> check bottom-of-screen [+1]
  INC TXTPH       ; [5]
  BNE wreon       ; [2] -> ALWAYS check bottom-of-screen [+1]

; write character   (16b)
wrch:             ; (uses A,X,B,Src,Dst)
  LDX #0          ; [2]
  STA (TXTP,X)    ; [6]
  DEC TRemX       ; [5] remaining space on line
  BEQ wreol       ; [2] -> end of line [+1]
  INC TXTP        ; [5]
  BEQ @pg         ; [2] -> cross page [+1]
  RTS             ; [6] X=0, NE // [28]
@pg:              ; page cross (at column 16)
  INC TXTPH       ; [5]
  RTS             ; [6] X=0, NE

; check and scroll at bottom of screen (18b)
wreol:            ; (uses A,X,B,Src,Dst)
  INC TXTP        ; [5] never conincides with page cross (INC for wrch)
wreon:
  LDA #40         ; [2] reset TRemX
  STA TRemX       ; [3]
  LDA TXTP        ; [3] check bottom of screen (could use RemY)
  CMP #192        ; [2] end of screen: ofs = 192
  BNE wrret       ; [2] -> no, NE [+1]
  LDA TXTPH       ; [3]
  CMP #VidLast    ; [2] end of screen: page = 2 3 4 >5<
  BNE wrret       ; [2] -> no, NE [+1]
;
; scroll down, clear exposed line
  TYA             ; [2] save Y
  PHA             ; [3]
  LDA #VidBase    ; [2]
  STA SrcH        ; [3]
  STA DstH        ; [3]
  LDA #40         ; [2] from row = 1
  STA Src         ; [3]
  LDA #0          ; [2] to row = 0
  STA Dst         ; [3]
; move contents up one line
  LDA #192        ; [2] 960 bytes = 192 bytes
  LDX #3          ; [2] plus 3 pages
  JSR mcopyf      ; [6] copy fwd XY=size (uses A,X,Y,B,Src,Dst) -> X=0
; clear the bottom line
  LDA #VidLast    ; [2] last page of screen
  STA TXTPH       ; [3]
  LDA #152        ; [2] 192-40 offset
  STA TXTP        ; [3]
  JSR txtclr      ; [6] (uses A,Y) -> (Y=0, EQ)
  PLA             ; [3]
  TAY             ; [2] restore Y (X=0)
wrret:
  RTS             ; [6] X=?

; @@ cls
; clear the screen
cls:              ; (uses A,X,Y,F)
  JSR home        ; -> Y=0
  LDX #3          ; number of whole pages
@lp:
  LDY #0          ; count = 256
  JSR txt_clr_n   ; Y=count (uses A,Y) -> (Y=0,EQ)
  INC TXTPH       ; next page
  DEX             ; 
  BNE @lp         ; -> loop
  LDY #192        ; count = 192
  JSR txt_clr_n   ; Y=count (uses A,Y) -> (Y=0,EQ)
home:
  LDA #40         ; [2] reset TRemX
  STA TRemX       ; [3]
  LDA #VidBase    ; [2] reset TXTP
  STA TXTPH       ; [3]
  LDY #0          ; [2]
  STY TXTP        ; [3]
  RTS             ; [6] Y=0

; write backspace   (15b)
; does not limit backspaces to the line or screen (hacky)
wrbs:             ; (uses A)
  INC TRemX       ; give back one remaining cell
  DEC TXTP        ; back up one cell
  BNE @done       ; -> ok
  DEC TXTPH       ; crossed page
@done:
  LDX #0          ;
  LDA #32         ; space
  STA (TXTP,X)    ; write it
  RTS

; @@ txtclr
; fill a text row at TXTP (does not change TXTP)
txtclr:            ; (uses A,Y)
  LDY #40          ; [2] count = 40
txt_clr_n:         ; Y=count (uses A,Y)
  LDA #32          ; [2] fill with spaces
@loop:
  DEY              ; [2] decrement column
  STA (TXTP),Y     ; [6] write a space
  BNE @loop        ; [3] -> until Y=0
  RTS              ; [6] -> (Y=0, EQ)

; @@ mcopyf
; copy memory forwards from (Src) to (Dst) with XY=size  (32b)
; assume (Dst < Src) but Src/Dst may overlap
mcopyf:                  ; (uses A,X,Y,B,Src,Dst) -> X=0
  STY B                  ; [3] save part-page
; whole pages
  LDY #0                 ; [2] for @plp or @olp
  TXA                    ; [2] is X=0?
  BEQ @part              ; [2] -> no whole pages [+1]
@plp:
  LDA (Src),Y            ; [5] read byte
  STA (Dst),Y            ; [6] write byte
  INY                    ; [2] advance
  BNE @plp               ; [3] -> until Y=0 (256 bytes) [+1]
  INC SrcH               ; [5] next Src page
  INC DstH               ; [5] next Dst page
  DEX                    ; [2] decrement page count
  BNE @plp               ; [2] -> another page (Y=0) [+1]
@part:                   ; (Y=0)
  LDX B                  ; [3] restore part-len // [3]
  BEQ @done              ; [2] -> no part [+1]
@olp:
  LDA (Src),Y            ; [5] read byte
  STA (Dst),Y            ; [6] write byte
  INY                    ; [2] advance
  DEX                    ; [2] decrement length
  BNE @olp               ; [3] -> until X=0 [+1]
@done:
  RTS                    ; [6] X=0


; ------------------------------------------------------------------------------
; READLINE

; @@ rdln
; read a line of input
rdln:             ; uses A,X,Y,B -> LineBuf, Y=length (EQ if zero)
  LDA #0          ; 
  STA B           ; init line length
@idle:
; reset blink timer
  LDX #0          ; 
  LDA #$20        ; ensure cell is a space
  STA (TXTP,X)    ; for cursor blink
  STX CurTime     ; 
@wait:
; blink the cursor
  DEC CurTime     ; cursor blink
  BNE @nobl       ; -> not yet [+1]
  LDA (TXTP,X)    ; current cursor ($20 or $EF)
  EOR #$CF        ; $EF-$20
  STA (TXTP,X)    ; opposite cursor ($EF or $20)
@nobl:
  JSR keyscan     ; scan for a key (uses A,X,Y) -> A=key
  TAX             ; test A=0
  BEQ @wait       ; if no char -> @wait
; hide the cursor
  TAY             ; save A=key
  LDX #0          ; 
  LDA #$20        ; 
  STA (TXTP,X)    ; write a space
  TYA             ; restore A=key
@cont:
  CMP #32         ; is it a control code?
  BCC @ctrl       ; -> char < 32, control code
  LDY B           ; current length
  CPY #38         ; is buffer full? (1 line)
  BEQ @more       ; buffer full -> do nothing
  ; write new char at cursor
  STA LineBuf,Y   ; write char (insert at cursor)
  INC B           ; increase length
  JSR wrch        ; print A=char (uses A,X,F,Src,Dst) preserves Y •••
@more:            ; keep reading chars
  JSR keyscan     ; scan for a key (uses A,X,Y) -> A=key
  TAX             ; test A=0
  BNE @cont       ; -> another key
  BEQ @idle       ; -> return to idle
@ctrl:
  CMP #13         ; is it RETURN?
  BEQ @return     ; -> return
  LDY B           ; check length
  BEQ @more       ; -> cannot backspace
  CMP #8          ; is it BACKSPACE?
  BNE @more       ; -> no
; backspace
  DEC B           ; length -= 1
  JSR wrbs        ; write backspace (uses A,X, preserves Y -> CC=fail)
  JMP @more
@return:
  LDA #0          ; terminator
  LDY B           ; get line length (NE/EQ)
  STA LineBuf,Y   ; write terminator to line buffer
  RTS             ; returns Y=length (NE/EQ)


; ------------------------------------------------------------------------------
; KEYBOARD  (212b)

; @@ keyscan
; scan the keyboard matrix for a keypress
; on keypress: (no CurrKey) key -> CurrKey
; on keypress: (have CurrKey) -> ignore newkey, complete scan
; on released CurrKey: clear CurrKey
keyscan:          ; uses A,X,Y returns nothing (CANNOT use B,C,D,E)
  LDA #0          ; [2] zero
  STA SrcH        ; [3] clear key-hit flags (NE=found)
  STA ModKeys     ; [3] clear ModKeys (set again if any modkeys are down)   2
  LDY #8          ; [2] last key col (modifiers)
; ...
@col_lp:          ; -> [13] cycles (Y=col)
  STY IO_KEY      ; [3] set keyscan col (0-7)              0µs (-> 7+3=10µs after prior)
  NOP             ; [2] delay                              2µs
  LDX IO_KEY      ; [3] read col_bitmap                    2+3µs read 5/0.89Mhz = 5.6µs settle
  BNE @col_hit    ; [2] -> one or more keys pressed [+1]   2µs -> 1µs (3µs)
@col_cont:
  DEY             ; [2] prev col                           2µs
  BPL @col_lp     ; [3] go again, until Y<0                2+2+3µs -> (7µs)
; finished
; check for key-ups
  LDA #0          ; [2] A=0
  LDX SrcH        ; [3] check key-hit flags (NE=found)
  BNE @key1dn     ; [2] -> CurrKey still down [+1]
  STA CurrKey     ; [3] clear CurrKey (to $00)
@key1dn:
  RTS             ; -> A=0
; ...
@col_hit:         ; X=col_bitmap(!=0) Y=col
; debounce check 
  CPX IO_KEY      ; [3] check if stable                    3+3µs read 6/0.89Mhz = 6.7µs verify
  BNE @col_lp     ; [2] if not -> try again
  CPY #8          ; [2] is ModKeys col?
  BEQ @mods       ; [2] -> handle ModKeys [+1]
  STY Src         ; [3] save col for @cont_bsf
  TYA             ; [2] active scan col
  ASL             ; [2] col * 8
  ASL             ; [2] 
  ASL             ; [2] 
  TAY             ; [2] Y=col*8 (X=col_bitmap Y=col*8 Src=col)
  TXA             ; [2] A = col_bitmap(!=0)
; find first bit set
; loop WILL terminate because A is non-zero!
@bsf_lp:          ; (A=col_bitmap Y=scantab_ofs) -> [7] cycles
  INY             ; [2] count shifts (Y = col*8 + n_shifts)
  ASL A           ; [2] shift keys bits left into CF
  BCC @bsf_lp     ; [3] until CF=1 (key is down)         (XXX will invert this, down = 0 bit)
; found a key down (Y=phys_key)
  TAX             ; [2] save remaining bits (X=col_bitmap)
  CPY CurrKey     ; [2] phys_key matches CurrKey?
  BEQ @is_curr    ; [2] -> found CurrKey [+1]
  LDA CurrKey     ; [3] check if we have a CurrKey
  BNE @cont_bsf   ; [3] -> have CurrKey, ignore keypress, continue scan (X=col_bitmap Y=scantab_ofs Src=col)
  STY CurrKey     ; [3] set CurrKey = phys_key (CORRECT here)
; new key press: translate key
  BIT ModKeys     ; [3] test shift key [N=Esc][V=Shf]
  BVS @shift      ; [2] -> shift is down (bit 6)
  LDA scantab-1,Y ; [4] translate to ASCII (Y is off by +1) -> A=char (EQ/NE)  EA
  RTS             ; [6] return A=char (EQ/NE)
@shift:
  LDA scanshf-1,Y ; [4] translate to ASCII (Y is off by +1) -> A=char (EQ/NE)  1F
  RTS             ; [6] return A=char (EQ/NE)
;
@is_curr:         ; found CurrKey during scan (set Hit.NE)
  INC SrcH        ; set Hit.NE
@cont_bsf:        ; (X=col_bitmap Y=scantab_ofs Src=col)
  TXA             ; [2] restore remaining bits (X=col_bitmap)
  BNE @bsf_lp     ; [3] -> continue bsf loop if A != 0 (more keys are down)   (XXX will invert this, $FF)
  LDY Src         ; [3] restore active scan col (Src=col)
  JMP @col_cont   ; [3] -> ALWAYS: continue scanning cols (Y in [0..8])
; ...
@mods:            ; <- EQ
  STX ModKeys     ; [3] update ModKeys (X=col_bitmap)
  BEQ @col_cont   ; [2] -> ALWAYS: scan next column (BEQ @mods) [+1]

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


; ------------------------------------------------------------------------------
; DEBUG

debug:
  STA DbgA
  STX DbgX
  STY DbgY
  TAX
  BEQ @skip
  JSR wrhex
@skip:
  LDA DbgA
  LDX DbgX
  LDY DbgY
  RTS

ALIGN 256
