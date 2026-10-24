MonBase = $FC00
ROMSize = 512

VidBase  = $A0          ; first video page
VidLast  = $A3          ; last video page

LineBuf  = $100         ; Input Buffer (128 bytes)

IO_KEY   = $F8          ; ASCII keyboard read (7-bit)
IO_CAS   = $F9          ; Cassette Write (3:Speaker 2:RTS 1:TXD 0:TapeTx) / Read (7:KeyLatch 2:CTS 1:RXD 0:TapeRx)

; ------------------------------------------------------------------------------
; Registers

Src      = $C0        ; source pointer \
SrcH     = $C1        ; source pointer | Scroll (PRINT/WRCH)
Dst      = $C2        ; destn pointer  | 
DstH     = $C3        ; destn pointer  /
Ptr      = $C4        ; destn pointer  \ Start Address 
PtrH     = $C5        ; destn pointer  /
B        = $C6        ; extra register \ End Address
C        = $C7        ; extra register /
End      = B
EndH     = C
D        = $C8        ; extra register
E        = $C9        ; extra register
F        = $CA        ; extra register

RemX     = $D3        ; remaining space on line
TXTP     = $D4        ; text write address
TXTPH    = $D5        ; text write address high
CurTime  = $D6        ; cursor flash timer

NmiVec   = $EA        ; NMI vector in RAM {JMP,Low,High} (for ROM override)
IrqVec   = $ED        ; IRQ vector in RAM {JMP,Low,High} (for ROM override)


; ------------------------------------------------------------------------------
; Monitor

ORG MonBase
dipg = MonBase

mon   SEI
      CLD
      JSR cls       ; -> Y=0,EQ
      BEQ repl
goto  JSR run       ; fall through on RTS
repl  JSR wrnl      ; new line
      LDA #93       ; `]`
repe  JSR wrch      ; (uses A,X,F,Src,Dst) -> X=0
      JSR rdln
      LDX #0        ; input ofs
      STX D         ; clear mode
      ; parse hex addrs
      JSR rdhx      ; X=ofs -> B,C (End)
      LDA End
      STA Ptr
      LDA EndH
      STA PtrH
      LDA LineBuf,X
      CMP #45       ; `-`
      BNE repc      ; -> no range
      INX
      JSR rdhx      ; (X=ofs, Y=count) -> End
      ; parse command
repc  LDA LineBuf,X
      BEQ prnt      ; -> print range
      CMP #58       ; `:`
      BEQ wrt       ; -> write to memory
      CMP #71       ; G
      BEQ goto      ; -> go to code
      CMP #90       ; Z
      BEQ clr       ; -> clear
      CMP #76       ; L
      BEQ load      ; -> load from cassette
      CMP #83       ; S
      BEQ save      ; -> save to cassette
      ; error
      LDA #63       ; `?`
      BNE repe      ; -> to repl

run   LDX #0
      JMP (Src)

; ------------------------------------------------------------------------------
; PRINT and CLEAR (65 bytes)

prnl  JSR wrnl
prnt  LDA PtrH
      JSR prhx     ; A=byte; (uses A,X,F,Src,Dst) preserves Y
      LDA Ptr
      JSR prhx     ; A=byte; (uses A,X,F,Src,Dst) preserves Y
      LDY #8
prlp  JSR wrsp     ; A=char; (uses A,X,F,Src,Dst) preserves Y -> X=0  DEY BEQ prnl
      LDA (Ptr,X)
      JSR prhx     ; A=byte; (uses A,X,F,Src,Dst) preserves Y
      ; increment address
incp  INC Ptr
      BNE prnp
      INC PtrH
      ; check end address
prnp  LDA PtrH
      CMP EndH
      BCC prco     ; -> less, continue
      BNE repl     ; -> greater, done (fixes -FF)
      LDA Ptr
      CMP End
      BEQ prco     ; -> equal, continue
      BCS repl     ; -> greater, done
      ; continue loop
prco  BIT D        ; check mode
      BMI clco     ; -> continue clear (+4)
      ; continue print
      DEY          ; 
      BNE prlp     ; -> write 8 bytes
      BEQ prnl     ; -> next line (always)

      ; start clear (17b with STX D and BIT D)
clr   LDX #0
      LDA #$80
      STA D        ; mode = clear (+6)
      ; continue clear
clco  TXA          ; X=0 (EQ)
      STA (Ptr,X)
      BEQ incp     ; -> continue (+5)

      ; write to memory (17b..)
wrt   LDY #0       ; write offset
wrtc  INX          ; `:` or separator
wrtl  STX E        ; save pos
      JSR rdhx     ; read byte (X=pos, uses A)
      CPX E        ; no change?
      BEQ wrtc     ; skip a char   (XXX need to detect end of line)
      STA (Ptr),Y  ; write to memory
      INY          ; 119 chars, max 59 bytes
      BNE wrtl     ; -> always

load:
save:
  JMP repl


; ------------------------------------------------------------------------------
; HEX (52 bytes)

; set $00 prefix (for single byte)
; @lp read nibble -> @nan
; even -> OR it, write it
; odd -> write it, shift it, stash it -> @lp
; @nan:
; even -> LOAD it, write it
; odd -> 
;   A -> 00 0A
;  AB -> 00 AB
; ABC -> 00 AB 0C (0A BC)

; read hex (48b)
rdhx  LDA #0        ; (A,X) -> X
      STA End       ; clear it
      STA EndH
rdhl  LDA LineBuf,X
      SEC
      SBC #48       ; `0`
      CMP #10       ; is it `0`-`9`
      BCC @ok       ; -> 0-9
      SBC #17       ; 48+17=`A`
      CMP #6        ; is it `A`-`F`
      BCS retn      ; -> not hex
      ADC #10       ; -> 10-15
@ok   ASL End
      ROL EndH
      ASL End
      ROL EndH
      ASL End
      ROL EndH
      ASL End
      ROL EndH
      ORA End
      STA End
      INX
      BNE rdhl      ; -> always
retn  RTS


; ------------------------------------------------------------------------------
; CLS, HOME, TCLR, CPYF, RDLN, WRNL, WRCH, WRBS

ORG MonBase+256+6

; @@ cls
; clear the screen
cls:              ; (uses A,X,Y) -> Y=0,EQ
  JSR home        ; -> Y=0
  LDX #3          ; number of whole pages
@lp:
  JSR tcln        ; Y=count (uses A,Y) -> Y=0,EQ
  INC TXTPH       ; next page
  DEX             ; 
  BNE @lp         ; -> loop
  LDY #192        ; count = 192
  JSR tcln        ; Y=count (uses A,Y) -> Y=0,EQ
  ; +++ fall through: home +++

; @@ home
; move cursor to top-left
home:             ; (uses A,Y) -> Y=0,EQ
  LDA #40         ; [2] reset RemX
  STA RemX        ; [3]
  LDA #VidBase    ; [2] reset TXTP
  STA TXTPH       ; [3]
  LDY #0          ; [2]
  STY TXTP        ; [3]
  RTS             ; [6] Y=0,EQ

; @@ tclr
; fill a text row at TXTP (does not change TXTP)
tclr:              ; (uses A,Y)
  LDY #40          ; [2] count = 40
tcln:              ; Y=count (uses A,Y)
  LDA #32          ; [2] fill with spaces
@loop:
  DEY              ; [2] decrement column
  STA (TXTP),Y     ; [6] write a space
  BNE @loop        ; [3] -> until Y=0
  RTS              ; [6] -> (Y=0, EQ)

; @@ cpyf
; copy memory forwards from (Src) to (Dst) with XY=size  (34b)
; assumes (Dst <= Src) but may overlap
cpyf:                    ; (uses A,X,Y,F,Src,Dst) -> X=0
  STY F                  ; [3] save part-page
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
  LDX F                  ; [3] restore part-len
  BEQ @done              ; [2] -> no part [+1]
@olp:
  LDA (Src),Y            ; [5] read byte
  STA (Dst),Y            ; [6] write byte
  INY                    ; [2] advance
  DEX                    ; [2] decrement length
  BNE @olp               ; [3] -> until X=0 [+1]
@done:
  RTS                    ; [6] X=0

; @@ rdln
; read a line of input
rdln:             ; (uses A,X,Y,F -> LineBuf, Y=len)
  LDY #0          ; line length
@wait:
; show the cursor
  LDX #0          ;
  LDA (TXTP,X)    ; read cursor
  DEC CurTime     ; cursor blink
  BNE @nobl       ; -> not yet [+1]
  EOR #$3F        ; $20/$1F
@nobl:
  STA (TXTP,X)    ; update cursor
; get a key
  LDA IO_CAS      ; (7:KeyLatch)
  BPL @wait       ; -> wait for key
  LDA IO_KEY      ; read ASCII key (clears KeyLatch)
  CMP #8          ; is it BACKSPACE?
  BEQ @back       ; -> go back
  CMP #13         ; is it RETURN?
  BEQ @return     ; -> return (CS)
  CPY #119        ; is buffer full? (3 lines)
  BEQ @wait       ; buffer full -> do nothing
; write char at cursor
  STA LineBuf,Y   ; write char (insert at cursor)
  INY             ; increase length (NE)
  JSR wrch        ; A=char (uses A,X,F,Src,Dst) preserves Y -> NE / NE from Y
  BNE @wait       ; -> ALWAYS wait for key
@back:            ; (X=0)
  TYA             ; test if length = 0
  BEQ @wait       ; -> cannot backspace
  DEY             ; reduce length
  INC RemX        ; give back one remaining cell
  DEC TXTP        ; back up one cell
  BNE @nopg       ; -> ok
  DEC TXTPH       ; crossed page
@nopg:
  CLC             ; take BCC
@return:          ; (CS)
  LDA #32         ; space
  STA (TXTP,X)    ; clear the cell
  BCC @wait       ; -> came from @back
  TXA             ; A=0
  STA LineBuf,Y   ; terminator
                  ; -> Y=length
  ; +++ fall through: wrnl +++

; @@ wrnl
; write newline     (13b)
wrnl:             ; (uses A,X,F,Src,Dst) -> X=0
  LDA RemX        ; [3] 40..1
  CLC             ; [2]
  ADC TXTP        ; [3]
  STA TXTP        ; [3]
  BCC wreol       ; [2] -> no page cross [+1]
  INC TXTPH       ; [5]
  BNE wreol       ; [2] -> ALWAYS check bottom-of-screen [+1]

; @@ wrsp
; write a space
wrsp:
  LDA #32
  ; +++ fall through: wrch +++

; @@ wrch
; write character   (16b)
wrch:             ; (uses A,X,F,Src,Dst) -> X=0
  LDX #0          ; [2]
  STA (TXTP,X)    ; [6]
  INC TXTP        ; [5]
  BNE @nopg       ; [2] -> no page cross [+1]
  INC TXTPH       ; [5]
@nopg:
  DEC RemX        ; [5] remaining space on line
  BNE wrret       ; [2] -> not end of line, X=0, NE [+1]
;
; check and scroll at bottom of screen (18b)
wreol:            ; (uses A,X,F,Src,Dst)
  LDA #40         ; [2] reset RemX
  STA RemX        ; [3]
  LDA TXTP        ; [3] check bottom of screen (could use RemY)
  CMP #192        ; [2] end of screen: ofs = 192
  BNE wrret       ; [2] -> no, NE (wrch:X=0) [+1]
  LDA TXTPH       ; [3]
  CMP #VidLast    ; [2] end of screen: page = 0 1 2 >3<
  BNE wrret       ; [2] -> no, NE (wrch:X=0) [+1]
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
  LDY #152        ; [2] 192-40 = 152
  LDX #3          ; [2] plus 3 pages
  JSR cpyf        ; [6] copy fwd XY=size (uses A,X,Y,F,Src,Dst) -> X=0
; clear the bottom line
  LDA #VidLast    ; [2] last page of screen
  STA TXTPH       ; [3]
  LDA #152        ; [2] 192-40 start of last line
  STA TXTP        ; [3]
  JSR tclr        ; [6] (uses A,Y) -> (Y=0, EQ)
  PLA             ; [3]
  TAY             ; [2] restore Y
wrret:            ; <- NE (wrch:X=0)
  RTS             ; [6] -> X=0 (except wrnl)

; @@ prhx
; print a hex digit
prhx:               ; A=byte; (uses A,X,F,Src,Dst) preserves Y
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

; @@ CPU Vectors
ORG MonBase+ROMSize-6
DW NmiVec        ; $FFFA, $FFFB ... NMI vector
DW mon           ; $FFFC, $FFFD ... Reset vector
DW IrqVec        ; $FFFE, $FFFF ... BRK/IRQ vector
