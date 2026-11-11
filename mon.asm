MonBase = $FC00
ROMSize = 1024

VidBase  = $A0          ; first video page
VidLast  = $A3          ; last video page

LineBuf  = $100         ; Input Buffer (128 bytes)

IO_KEY   = $F8          ; ASCII keyboard read (7:Strobe 6-0:ASCII)
IO_CAS   = $F9          ; Cassette Write (7:TapeTx 6:TXD 1:RTS 0:Speaker) / Read (7:KeyLatch 2:CTS 1:RXD 0:TapeRx)


; ------------------------------------------------------------------------------
; Registers

; -- $D0-DF Temporaries (16)

Src      = $D0        ; source pointer \ WRCH, CLS  [Term0]
SrcH     = $D1        ; source pointer |            [Term1]
Acc0     = Src        ; ALIAS: accumulator byte 0
Acc1     = SrcH       ; ALIAS: accumulator byte 1
Dst      = $D2        ; destn pointer  | WRCH, CLS  [Term0]
DstH     = $D3        ; destn pointer  /            [Term1]
Term0    = Dst        ; ALIAS: term byte 0
Term1    = DstH       ; ALIAS: term byte 1
Ptr      = $D4        ; third pointer  \ findln, ins/del line
PtrH     = $D5        ; third pointer  /
B        = $D6        ; extra register | Subroutines are annotated with usage;
End      = B          ; monitor address
C        = $D7        ; extra register | held across calls only when unused
EndH     = C          ; monitor address
D        = $D8        ; extra register | by callees (manually tracked)
E        = $D9        ; extra register |
F        = $DA        ; IO Temp register (all IO, cpyf/cpyb)
;xx      = $DB
;xx      = $DC
;xx      = $DD
;xx      = $DE
;xx      = $DF

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


; ------------------------------------------------------------------------------
; Monitor

ORG MonBase

; 1000              set address = 1000 (dump one row)
; 1000,80           set address = 1000, dump 128 bytes
; 0-3FF             set address = 0, dump range (1024 bytes)
; CR                dump 128 more
; W A9 B8 20 FF95   write bytes, dump written range

; 0000 _
; 0000 A9 B8 20 FF95
; 0005 _
; 0005 G 0
; 0005 _
; 0005 0000

; addr = 0, len = 8
; loop: (m=0)x
; CR: redo
; hex: (m=0) set addr (m=1) set len = hex - addr
; `-`: m++, loop
; `W`: enter write mode (print addr, accept hex bytes)

reset   SEI
        CLD

        ; detect memory   (24b)
        ; write page number to 1st byte of each page
        LDA #0
        TAY               ; Y=0
        ;;TAX             ; page number = 0
        LDX #9            ; page number = 9 (above BASIC)   XXX pre-loaded BASIC!!!
        STA Ptr           ; clear low byte
msetl   STX PtrH          ; update ptr
        TXA               ; A = page number
        STA (Ptr),Y       ; write page number
        INX               ; next page
        BNE msetl         ; -> until X=0
        ; test 1st byte of each page for page number
        LDX #9            ; page number = 9 (above BASIC)   XXX pre-loaded BASIC!!!
mchkl   INX               ; incr Page
        STX PtrH          ; update Ptr
        TXA               ; A = page number
        CMP (Ptr),Y       ; compare page number
        BEQ mchkl         ; -> until not equal
        STX MemSz         ; set size of memory (in pages)

        ; monitor         (74b)
        JSR cls           ; -> Y=0,EQ
        BEQ repl
goto    JSR run           ; fall through on RTS
repl    LDX #$7F          ; 128-byte stack (for BASIC at $180)
        TXS               ; set SP
        JSR wrnl          ; new line
        LDA #93           ; `]`
repe    JSR wrch          ; (uses A,X,F,Src,Dst) -> X=0
        JSR rdln
        LDX #0            ; input ofs
        STX D             ; clear mode
        ; parse hex addrs
        JSR rdhx          ; X=ofs -> B,C (End)
        LDA End           ; B
        STA Ptr
        LDA EndH          ; C
        STA PtrH
        LDA LineBuf,X
        CMP #45           ; `-`
        BNE repc          ; -> no range
        INX
        JSR rdhx          ; (X=ofs, Y=count) -> End
        ; parse command
repc    LDA LineBuf,X
        BEQ prnt          ; -> print range
        CMP #58           ; `:`
        BEQ wrt           ; -> write to memory
        CMP #71           ; G
        BEQ goto          ; -> go to code
        CMP #90           ; Z
        BEQ clr           ; -> clear
        CMP #76           ; L
        BEQ load          ; -> load from cassette
        CMP #83           ; S
        BEQ save          ; -> save to cassette
        ; error
        LDA #63           ; `?`
        BNE repe          ; -> to repl


; ------------------------------------------------------------------------------
; PRINT, CLEAR, WRITE, RUN (91 bytes)

prnl    JSR wrnl
prnt    LDA PtrH
        JSR wrhx          ; A=byte; (uses A,X,F,Src,Dst) preserves Y
        LDA Ptr
        JSR wrhx          ; A=byte; (uses A,X,F,Src,Dst) preserves Y
        LDY #8
prlp    JSR wrsp          ; A=char; (uses A,X,F,Src,Dst) preserves Y -> X=0
        LDA (Ptr,X)
        JSR wrhx          ; A=byte; (uses A,X,F,Src,Dst) preserves Y
        ; increment address
incp    INC Ptr
        BNE prnp
        INC PtrH
        ; check end address
prnp    LDA PtrH
        CMP EndH     ; C
        BCC prco     ; -> less, continue
        BNE repl     ; -> greater, done (fixes -FF, but not FFFF)
        LDA Ptr
        CMP End      ; B
        BEQ prco     ; -> equal, continue
        BCS repl     ; -> greater, done
        ; continue loop
prco    BIT D        ; check mode
        BMI clco     ; -> continue clear (+4)
        ; continue print
        DEY          ; 
        BNE prlp     ; -> write 8 bytes
        LDA IO_KEY   ; check ESC
        CMP #$9B     ; $80+ESC
        BNE prnl     ; -> next line (always)
        JMP repl     ; -> STOP

        ; start clear (17b with STX D and BIT D)
clr     LDX #0
        LDA #$80
        STA D        ; mode = clear (+6)
        ; continue clear
clco    TXA          ; X=0 (EQ)
        STA (Ptr,X)
        BEQ incp     ; -> continue (+5)

        ; write to memory (17b)
wrt     LDY #0       ; write offset
wrtc    INX          ; `:` or separator
wrtl    STX E        ; save pos
        JSR rdhx     ; read byte (X=pos, uses A)
        CPX E        ; no change?
        BEQ wrtc     ; skip a char                    (XXX need to detect end of line)
        STA (Ptr),Y  ; write to memory
        INY          ; 119 chars, max 59 bytes
        BNE wrtl     ; -> always

      ; run subroutine
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
rdhx    LDA #0        ; (A,X) -> X
        STA End       ; B clear it
        STA EndH      ; C
rdhl    LDA LineBuf,X
        SEC
        SBC #48       ; `0`
        CMP #10       ; is it `0`-`9`
        BCC @ok       ; -> 0-9
        SBC #17       ; 48+17=`A`
        CMP #6        ; is it `A`-`F`
        BCS retn      ; -> not hex
        ADC #10       ; -> 10-15
@ok     ASL End
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
retn    RTS


; ------------------------------------------------------------------------------
; CASSETTE

DB "CAS"

        ; receive byte
        LDY #8        ; [2] 8 bits
crst    LDX #0        ; [2] timer
        ; wait for zero-crossing
crzc    INX           ; [2]
        LDA IO_CAS    ; [3]
        BPL crzc      ; [3] -> wait [8] 8*1117 = 8.936 µs between samples
        ; wait for end of pulse
crzx    LDA IO_CAS    ; [3]
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
cwb     LDY #8        ; [2] 8 bits
cwlp    ROL B         ; [5] CF << byte
        LDX #12       ; [2] 4800 Hz (1)
        BCS cwhi      ; [2] -> write high [+1]
        LDX #17       ; [2] 3200 Hz (0)
cwhi    LDA #1        ; [2] d0=1 bit
cwd1    STA IO_CAS    ; [3] output bit
        DEX           ; [2] 
        BNE cwd1      ; [3] -> delay loop
        LDA #0        ; [2] d0=1 bit
cwd2    STA IO_CAS    ; [3] output bit
        DEX           ; [2] 
        BNE cwd2      ; [3] -> delay loop


; ------------------------------------------------------------------------------
; num16, wrnum (103b)

ORG MonBase+ROMSize-219-71-89-103

        ; @@ num16
        ; parse an unsigned 16-bit number (0-32767)
        ; from LineBuf,Y -> Args[0],Y,CS=found (uses A,X,Src)
num16   LDA #0         ; [2]
        STA Acc0       ; [3] clear Acc
        STA Acc1       ; [3]
        DEY            ; [2] for pre-increment
n16lp   INY            ; [2] pre-increment
        LDA LineBuf,Y  ; [4] get next char
        EOR #48        ; [2] make '0' be 0
        CMP #10        ; [2]
        BCS numrt      ; [2] >= 10 -> done [+1]
        TAX            ; [2] save digit 0-9
        ; multiply Acc by 10
        ASL Acc0       ; [5] Acc = Acc*2 (=Val*2)
        ROL Acc1       ; [5]
        BCS numovf     ; [2] -> unsigned overflow
        LDA Acc0       ; [3] Term = Acc (=Val*2)
        STA Term0      ; [3] 
        LDA Acc1       ; [3]
        STA Term1      ; [3]
        ASL Acc0       ; [5] Acc *= 2 (=Val*4)
        ROL Acc1       ; [5]
        BCS numovf     ; [2] -> unsigned overflow
        ASL Acc0       ; [5] Acc *= 2 (=Val*8)
        ROL Acc1       ; [5]
        BCS numovf     ; [2] -> unsigned overflow
        CLC            ; [2]
        TXA            ; [2] Acc += digit 0-9
        ADC Acc0       ; [3]
        BCC n16np      ; [2] -> no carry [+1]
        INC Acc1       ; [5]
        BEQ numovf     ; [2] -> unsigned overflow [+1]
n16np   ADC Term0      ; [3] Acc += Term (=Val*2)
        STA Acc0       ; [3]
        LDA Acc1       ; [3]
        ADC Term1      ; [3]
        STA Acc1       ; [3]
        BCS numovf     ; [2] -> unsigned overflow
        BPL n16lp      ; [2] -> no signed overflow, continue [+1]
numovf  SEC            ; [2]
        RTS            ; [6] -> CS=overflow

numrt   CLC            ; [2]
        RTS            ; [6] -> CS=overflow

        ; @@ wrnum
        ; print number in Acc (uses A,X,B,C,F,Src,Dst)
        ; using div16 to save space!
wrnum   LDA #0            ; [2] 
        PHA               ; [3] sentinel
        STA Term1         ; [3] divisor high byte (Dst)
        LDA #10           ; [2] divisor = 10
        STA Term0         ; [3] divisor low byte (Dst)
wrnul   JSR div16         ; [733] Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Src,Dst)
        LDA B             ; [3] remainder
        ORA #48           ; [2] 0-9 -> '0'-'9'
        PHA               ; [3] pushes once or more
        LDA Acc0          ; [3]
        ORA Acc1          ; [3]
        BNE wrnul         ; [2] -> until zero [+1]
        PLA               ; [4]
wrnup   JSR wrch          ; [6] print it (uses A,X,F,Src,Dst) preserves Y
        PLA               ; [4]
        BNE wrnup         ; [2] -> until sentinel [+1]
        RTS               ; [6] -> EQ



; ------------------------------------------------------------------------------
; mul16, div16 (89b)

ORG MonBase+ROMSize-219-71-89

        ; @@ mul16
        ; Acc=multiplicand, Term=multiplier -> BC=product (uses A,X,B,C,Acc,Term)
mul16   LDA #0            ; [2] clear
        STA B             ; [3] B partial product low
        STA C             ; [3] C partial product high
        LDX #16           ; [2] 16 bit multiplier
        ; shift multiplier right, test low-bit
mullp   LSR Acc1          ; [5] 0 >> multiplier >> CF
        ROR Acc0          ; [5] CF >> multiplier >> CF
        BCC mulzb         ; [2] -> zero bit, no add [+1]
        ; partial += shifted multiplicand x low-bit of multiplier
        CLC               ; [2] sadly CF=1
        LDA B             ; [3] partial product
        ADC Term0         ; [3] partial += multiplicand
        STA B             ; [3]
        LDA C             ; [3] partial product
        ADC Term1         ; [3] partial += multiplicand
        STA C             ; [3]
        BCS mulov         ; [2] -> overflow
        ; shift multiplicand left (×2) into next higher place
mulzb   ASL Term0         ; [2] CF << multiplicand << 0
        ROL Term1         ; [5] XX << multiplicand << CF
        BCS mulov         ; [2] -> overflow (multiplicand)
        DEX               ; [2]
        BNE mullp         ; [3] -> continue
        CLC               ; [2] no overflow
mulov   RTS               ; [6] -> CS=overflow

        ; @@ div16
        ; Acc=dividend, Term=divisor -> Acc=quotient, BC=remainder (uses A,X,B,C,Acc,Term)
div16   LDA #0         ; 
        STA B          ; remainder = 0
        STA C          ; remainder = 0
        LDX #16        ; 16 bits
        ; shift dividend bits left into remainder
divlp   ASL Acc0       ; [5] CF << dividend << 0  (shift 0 into quotient by default)
        ROL Acc1       ; [5] CF << dividend << CF
        ROL B          ; [2] CF << remainder << CF
        ROL C          ; [2] XX << remainder << CF
        ; until remainder >= divisor
        LDA C          ; [3] high byte
        CMP Term1      ; [3] is remainder >= divisor?
        BCC divnx      ; [2] -> less, continue loop [+1]
        BNE divgt      ; [2] -> greater, do subtraction [+1] (otherwise equal)
        LDA B          ; [3] low byte
        CMP Term0      ; [3] is remainder >= divisor?
        BCC divnx      ; [2] -> less, continue loop [+1]
        ; subtract divisor from remainder
divgt   SEC            ; [2]
        LDA B          ; [3] low byte
        SBC Term0      ; [3] subtract divisor
        STA B          ; [3] new remainder
        LDA C          ; [3] mid byte
        SBC Term1      ; [3] subtract divisor
        STA C          ; [3] new remainder
        ; shift 1 into quotient (one times divisor found)
        INC Acc0       ; [5] quotient bit0 = 1 (shift quotient into Acc)
divnx   DEX            ; [2]
        BNE divlp      ; [3] -> continue division
        RTS            ; return



; ------------------------------------------------------------------------------
; Memory Copy: CPYF, CPYB (71b)

ORG MonBase+ROMSize-219-71

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

        ; @@ cpyb
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


; ------------------------------------------------------------------------------
; IO: CLS, HOME, TCLR, RDLN, WRNL, WRSP, WRHX, WRCH, Vectors (215b)

ORG MonBase+ROMSize-219

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
        CPY #78           ; is buffer full? (2 lines)
        BEQ rdlnw         ; buffer full -> do nothing
        ; write char
        STA LineBuf,Y     ; write char (insert at cursor)
        INY               ; increase length (NE)
        JSR wrch          ; A=char (uses A,X,F,Src,Dst) preserves Y -> NE / NE from Y
        BNE rdlnw         ; -> ALWAYS wait for key
        ; backspace       (X=0)
rdlnbs  TYA               ; test length
        BEQ rdlnw         ; -> cannot backspace
        LDA #32           ; space <- (CS)
        STA (TXTP,X)      ; clear the cursor
        DEY               ; reduce length
        INC RemX          ; give back one remaining cell
        DEC TXTP          ; back up one cell
        BNE rdlnpg        ; -> ok
        DEC TXTPH         ; crossed page
rdlnpg  CLC               ; take BCC
rdlnx   LDA #32           ; space <- (X=0,CS)
        STA (TXTP,X)      ; clear the cursor
        BCC rdlnw         ; -> came from backspace
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

        ; @@ wrhx
        ; write byte in hex
        ; A=byte; (uses A,X,F,Src,Dst) preserves Y  (23b)
wrhx    PHA               ; save A
        LSR               ; shift top 4 bits down
        LSR               ; 
        LSR               ; 
        LSR               ; 
        JSR wrhxd         ; print digit
        PLA               ; restore A
        AND #15           ; keep low 4 bits
wrhxd   CMP #10           ; is it >10 ?
        BCS wrhxp         ; -> yes, print letter (CF=1)
        ADC #$FA          ; add 48 - 54 (-6)
        CLC               ; set CF=0 (for digits >=6)
wrhxp   ADC #54           ; 'A'65 - 10 - 1(CF)
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

; @@ CPU Vectors
ORG MonBase+ROMSize-6
DW NmiVec        ; $FFFA, $FFFB ... NMI vector
DW reset         ; $FFFC, $FFFD ... Reset vector
DW IrqVec        ; $FFFE, $FFFF ... BRK/IRQ vector
