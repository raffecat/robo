MonBase = $FE00
ROMSize = 512

VidBase  = $A0          ; first video page
VidLast  = $A3          ; last video page

LineBuf  = $100         ; Input Buffer (128 bytes)

IO_KEY   = $F8          ; ASCII keyboard read (7:Strobe 6-0:ASCII)
IO_CAS   = $F9          ; Cassette Write (7:TapeTx 6:TXD 1:RTS 0:Speaker) / Read (7:KeyLatch 2:CTS 1:RXD 0:TapeRx)

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
F        = $CA        ; IO Temp register

TXTP     = $CB        ; text write address
TXTPH    = $CC        ; text write address high
RemX     = $CD        ; remaining space on line
CurTime  = $CE        ; cursor flash timer

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
      LDA End       ; B
      STA Ptr
      LDA EndH      ; C
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

; ------------------------------------------------------------------------------
; PRINT, WRITE, CLEAR (65 bytes)

prnl  JSR wrnl
prnt  LDA PtrH
      JSR prhx     ; A=byte; (uses A,X,F,Src,Dst) preserves Y
      LDA Ptr
      JSR prhx     ; A=byte; (uses A,X,F,Src,Dst) preserves Y
      LDY #8
prlp  JSR wrsp     ; A=char; (uses A,X,F,Src,Dst) preserves Y -> X=0
      LDA (Ptr,X)
      JSR prhx     ; A=byte; (uses A,X,F,Src,Dst) preserves Y
      ; increment address
incp  INC Ptr
      BNE prnp
      INC PtrH
      ; check end address
prnp  LDA PtrH
      CMP EndH     ; C
      BCC prco     ; -> less, continue
      BNE repl     ; -> greater, done (fixes -FF, but not FFFF)
      LDA Ptr
      CMP End      ; B
      BEQ prco     ; -> equal, continue
      BCS repl     ; -> greater, done
      ; continue loop
prco  BIT D        ; check mode
      BMI clco     ; -> continue clear (+4)
      ; continue print
      DEY          ; 
      BNE prlp     ; -> write 8 bytes
      LDA IO_KEY   ; check ESC
      CMP #$9B     ; $80+ESC
      BNE prnl     ; -> next line (always)
      BEQ repl     ; -> STOP

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
      BEQ wrtc     ; skip a char                    (XXX need to detect end of line)
      STA (Ptr),Y  ; write to memory
      INY          ; 119 chars, max 59 bytes
      BNE wrtl     ; -> always

      ; jump to memory
run   JMP (Ptr)


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
      STA End       ; B clear it
      STA EndH      ; C
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
; CASSETTE


      ; receive byte
      LDY #8        ; [2] 8 bits
crst  LDX #0        ; [2] timer
      ; wait for zero-crossing
crzc  INX           ; [2]
      LDA IO_CAS    ; [3]
      BPL crzc      ; [3] -> wait [8] 8*1117 = 8.936 µs between samples
      ; wait for end of pulse
crzx  LDA IO_CAS    ; [3]
      BMI crzx      ; [3] -> wait [6]
      ; decode bit
      CPX #15       ; [2] mid-point (12<->17) CS=greater/eq(1) CC=less(0)
      ROL B         ; [5] byte << CF
      DEY           ; [2]
      BNE crst      ; [3]

      ; 1117ns per cycle
      ; 1 / 4800 Hz * 1000 = 208333 ns / 2 / 1117 = 93.25 cycles / 8 = 11.65625
      ; 1 / 3200 Hz * 1000 = 312500 ns / 2 / 1117 = 139.88 cycles / 8 = 17.485

      ; record byte (A=byte)
cwb   LDY #8        ; [2] 8 bits
cwlp  ROL B         ; [5] CF << byte
      LDX #12       ; [2] 4800 Hz (1)
      BCS cwhi      ; [2] -> write high [+1]
      LDX #17       ; [2] 3200 Hz (0)
cwhi  LDA #1        ; [2] d0=1 bit
cwd1  STA IO_CAS    ; [3] output bit
      DEX           ; [2] 
      BNE cwd1      ; [3] -> delay loop
      LDA #0        ; [2] d0=1 bit
cwd2  STA IO_CAS    ; [3] output bit
      DEX           ; [2] 
      BNE cwd2      ; [3] -> delay loop




; ------------------------------------------------------------------------------
; CLS, HOME, TCLR, CPYF, RDLN, WRNL, WRCH, WRBS

ORG MonBase+256+7

        ; @@ cls
        ; clear the screen
        ; (uses A,X,Y) -> Y=0,EQ
cls     JSR home          ; -> Y=0
        LDX #3            ; number of whole pages
clslp   JSR tcln          ; Y=count (uses A,Y) -> Y=0,EQ
        INC TXTPH         ; next page
        DEX               ; 
        BNE clslp         ; -> loop
        LDY #192          ; count = 192
        JSR tcln          ; Y=count (uses A,Y) -> Y=0,EQ
        ; +++ fall through: home +++

        ; @@ home
        ; move cursor to top-left
        ; (uses A,Y) -> Y=0,EQ
home    LDA #40           ; [2] reset RemX
        STA RemX          ; [3]
        LDA #VidBase      ; [2] reset TXTP
        STA TXTPH         ; [3]
        LDY #0            ; [2]
        STY TXTP          ; [3]
        RTS               ; [6] Y=0,EQ

        ; @@ tclr
        ; fill a text row at TXTP (does not change TXTP)
        ; Y=count (uses A,Y)
tclr    LDY #40           ; [2] count = 40
tcln    LDA #32           ; [2] fill with spaces
tclrlp  DEY               ; [2] decrement column
        STA (TXTP),Y      ; [6] write a space
        BNE tclrlp        ; [3] -> until Y=0
        RTS               ; [6] -> (Y=0, EQ)

        ; @@ rdln
        ; read a line of input
        ; (uses A,X,Y,F,Src,Dst -> LineBuf, Y=len)
rdln    LDY #0            ; line length
        ; show cursor
rdlnw   LDX #0
        LDA (TXTP,X)      ; read cursor
        DEC CurTime       ; cursor blink
        BNE rdlnnb        ; -> not yet [+1]
        EOR #$3F          ; $20/$1F
rdlnnb  STA (TXTP,X)      ; update cursor
        ; get a key
        LDA IO_KEY        ; (7:Latch 6-0:ASCII)
        BPL rdlnw         ; -> wait for keypress
        AND #$7F          ; clear top bit
        CMP #8            ; is it BACKSPACE?
        BEQ rdlnbs        ; -> go back
        CMP #13           ; is it RETURN?
        BEQ rdlnx         ; -> return (CS)
        CPY #119          ; is buffer full? (3 lines)
        BEQ rdlnw         ; buffer full -> do nothing
        ; write char
        STA LineBuf,Y     ; write char (insert at cursor)
        INY               ; increase length (NE)
        JSR wrch          ; A=char (uses A,X,F,Src,Dst) preserves Y -> NE / NE from Y
        BNE rdlnw         ; -> ALWAYS wait for key
        ; backspace
rdlnbs  TYA               ; test length <- (X=0)
        BEQ rdlnw         ; -> cannot backspace
        DEY               ; reduce length
        INC RemX          ; give back one remaining cell
        DEC TXTP          ; back up one cell
        BNE rdlnpg        ; -> ok
        DEC TXTPH         ; crossed page
rdlnpg  CLC               ; take BCC
rdlnx   LDA #32           ; space <- (CS)
        STA (TXTP,X)      ; clear the cell
        BCC rdlnw         ; -> came from @back
        TXA               ; A=0
        STA LineBuf,Y     ; terminator  -> Y=length
        ; +++ fall through: wrnl +++

        ; @@ wrnl
        ; write newline
        ; (uses A,X,F,Src,Dst) -> X=0  (13b)
wrnl    LDA RemX          ; [3] 40..1
        CLC               ; [2]
        ADC TXTP          ; [3]
        STA TXTP          ; [3]
        BCC wreol         ; [2] -> no page cross [+1]
        INC TXTPH         ; [5]
        BNE wreol         ; [2] -> ALWAYS check bottom-of-screen [+1]

        ; @@ wrsp
        ; write a space  (4b)
wrsp    LDA #32
        BNE wrch

        ; @@ prhx
        ; print byte in hex
        ; A=byte; (uses A,X,F,Src,Dst) preserves Y  (23b)
prhx    PHA               ; save A
        LSR               ; shift top 4 bits down
        LSR               ; 
        LSR               ; 
        LSR               ; 
        JSR prhxd         ; print digit
        PLA               ; restore A
        AND #15           ; keep low 4 bits
prhxd   CMP #10           ; is it >10 ?
        BCS prhxp         ; -> yes, print letter (CF=1)
        ADC #$FA          ; add 48 - 54 (-6)
        CLC               ; set CF=0 (for digits >=6)
prhxp   ADC #54           ; 'A'65 - 10 - 1(CF)
        ; +++ fall through: wrch +++

        ; @@ wrch
        ; write character   (16b)
        ; (uses A,X,F,Src,Dst) -> X=0
wrch    LDX #0            ; [2]
        STA (TXTP,X)      ; [6]
        INC TXTP          ; [5]
        BNE wrchpg        ; [2] -> no page cross [+1]
        INC TXTPH         ; [5]
wrchpg  DEC RemX          ; [5] remaining space on line
        BNE wrret         ; [2] -> not end of line, X=0, NE [+1]
        ; +++ fall through: wreol +++

        ; check and scroll at bottom of screen (18b)
        ; (uses A,X,F,Src,Dst)
wreol   LDA #40           ; [2] reset RemX
        STA RemX          ; [3]
        LDA TXTP          ; [3] check bottom of screen (could use RemY)
        CMP #192          ; [2] end of screen: ofs = 192
        BNE wrret         ; [2] -> no, NE (wrch:X=0) [+1]
        LDA TXTPH         ; [3]
        CMP #VidLast      ; [2] end of screen: page = 0 1 2 >3<
        BNE wrret         ; [2] -> no, NE (wrch:X=0) [+1]
        ; scroll down, clear exposed line
        TYA               ; [2] save Y
        PHA               ; [3] (can't use STY F, cpyf does)
        LDA #VidBase      ; [2]
        STA SrcH          ; [3]
        STA DstH          ; [3]
        LDA #40           ; [2] from row = 1
        STA Src           ; [3]
        LDA #0            ; [2] to row = 0
        STA Dst           ; [3]
        ; move contents up one line
        LDY #152          ; [2] 192-40 = 152
        LDX #3            ; [2] plus 3 pages
        JSR cpyf          ; [6] copy fwd XY=size (uses A,X,Y,F,Src,Dst) -> X=0
        ; clear the bottom line
        LDA #VidLast      ; [2] last page of screen
        STA TXTPH         ; [3]
        LDA #152          ; [2] 192-40 start of last line
        STA TXTP          ; [3]
        JSR tclr          ; [6] (uses A,Y) -> (Y=0, EQ)
        PLA               ; [4]
        TAY               ; [2]
wrret   RTS               ; [6] <- NE (wrch:X=0)
                          ; -> X=0 (except wrnl)

        ; @@ cpyf
        ; copy memory forwards from (Src) to (Dst) with XY=size  (34b)
        ; assumes (Dst <= Src) but may overlap
        ; (uses A,X,Y,F,Src,Dst) -> X=0
cpyf    STY F             ; [3] save part-page
        LDY #0            ; [2] for cpyfw or cpyfp
        TXA               ; [2] is X=0?
        BEQ cpyfnw        ; [2] -> no whole pages [+1]
        ; whole pages
cpyfw   LDA (Src),Y       ; [5] read byte
        STA (Dst),Y       ; [6] write byte
        INY               ; [2] advance
        BNE cpyfw         ; [3] -> until Y=0 (256 bytes) [+1]
        INC SrcH          ; [5] next Src page
        INC DstH          ; [5] next Dst page
        DEX               ; [2] decrement page count
        BNE cpyfw         ; [2] -> another page (Y=0) [+1]
        ; part page
cpyfnw  LDX F             ; [3] restore part-len (Y=0)
        BEQ cpyfx         ; [2] -> no part [+1]
cpyfp   LDA (Src),Y       ; [5] read byte
        STA (Dst),Y       ; [6] write byte
        INY               ; [2] advance
        DEX               ; [2] decrement length
        BNE cpyfp         ; [3] -> until X=0 [+1]
cpyfx   RTS               ; [6] X=0


; @@ CPU Vectors
ORG MonBase+ROMSize-6
DW NmiVec        ; $FFFA, $FFFB ... NMI vector
DW mon           ; $FFFC, $FFFD ... Reset vector
DW IrqVec        ; $FFFE, $FFFF ... BRK/IRQ vector
