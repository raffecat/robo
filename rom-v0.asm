; rom-v0.asm

.svkw   EQU $07
.zkwlst EQU &08  ; 08-09

inbuf  =  &0200

; minus 1 so we can INY before CMP in match_lp
.kwtab
  DB (kwa-kwtab-1) ; A
  DB (kwb-kwtab-1) ; B
  DB (kwc-kwtab-1) ; C
  DB (kwd-kwtab-1) ; D
  DB (kwe-kwtab-1) ; E
  DB (kwf-kwtab-1) ; F
  DB (kwg-kwtab-1) ; G
  DB (kwh-kwtab-1) ; H
  DB (kwi-kwtab-1) ; I
  DB (kwj-kwtab-1) ; J
  DB (kwk-kwtab-1) ; K
  DB (kwl-kwtab-1) ; L
  DB (kwm-kwtab-1) ; M
  DB (kwn-kwtab-1) ; N
  DB (kwo-kwtab-1) ; O
  DB (kwp-kwtab-1) ; P
  DB (kwq-kwtab-1) ; Q
  DB (kwr-kwtab-1) ; R
  DB (kws-kwtab-1) ; S
  DB (kwt-kwtab-1) ; T
  DB (kwu-kwtab-1) ; U
  DB (kwv-kwtab-1) ; V
  DB (kww-kwtab-1) ; W
  DB (kwx-kwtab-1) ; X
  DB (kwy-kwtab-1) ; Y
  DB (kwz-kwtab-1) ; Z

.kwa
  DB 
.kwb
.kwc
.kwd
.kwe
.kwf
.kwg
.kwh
.kwi
.kwj
.kwk
.kwl
.kwm
.kwn
.kwo
.kwp
.kwq
.kwr
.kws
.kwt
.kwu
.kwv
.kww
.kwx
.kwy
.kwz

  LDX #0
.parse_lp
  ; read next char
  LDA inbuf,X
  INX
  CMP #32         ; skip spaces
  BEQ parse_lp
  TAY             ; for notkw
  ORA #32         ; to lower case
  CMP #123        ; 'z'+1
  BCS notkw       ; greater or equal
  SBC #97         ; 'a' know C=0 (BCS above)
  BMI notkw       ; less than
  ; keyword or variable name
  TAY             ; table index [0-25]
  LDA kwtab,Y
  STA zkwlst      ; pointer to keyword list (low byte)
.match_kw
  STX svkw        ; save start of kw
  TAY             ; pointer to keyword list in Y
.match_lp
  LDA inbuf,X     ; next char of input
  CMP #46         ; dot
  BEQ match_dot
  INX             ; for next iter
  ORA #32         ; to lower case
  INY             ; before cmp to avoid setting Z after cmp
  CMP kwtab,Y     ; next char of keyword
  BEQ match_lp
  ; no match - must be variable name


.notkw
  TYA
  ; digits, operators



; this is cute but only works if Y is tesed on every INY
; and never goes above 128.
ar_adv:          ; add 128 to Code; reset Y (C=1)
  LDY #0         ; [2] reset Y
  ASL Code       ; [5] set Code=0, C from top bit
  BCC ar_advh    ; [2] C=0: set Code=128 (was 0)
  INC CodeH      ; [5] C=1: advance to next page (was 128)
  JMP (JtA)      ; [5] dispatch (19)
ar_advh:         ; (10) on entry (C=0)
  LDA #128       ; [2] C=0: set Code=128 (was 0)
  STA Code       ; [3] store Code
  JMP (JtA)      ; [5] dispatch (20)

ar_adv:          ; INY, add Y to Code; reset Y (C=1)
  TYA            ; [2]
  LDY #0         ; [2] reset Y
  ADC Code       ; [3] add Y+1 to Code (C=1)
  STA Code       ; [3] set new Code low
  TYA            ; [2] set A=0
  ADC CodeH      ; [3] add Carry to Code
  STA CodeH      ; [3] set new Code high
  JMP (JtA)      ; [5] dispatch (23)


compact:         ; one byte per opcode, explict advance (inline in ops)
  LDA (Code),Y   ; [5] load opcode
  INY            ; [2]
  STA TJmp       ; [3] low byte (high byte constant)
  JMP (TJmp)     ; [5] jump indirect [15] (8 bytes)
arrive:
  BNE routine    ; [2] double-jumped [17]
  JMP routine    ; [3] double-jumped [18]
shared_dispatch:
  BCC dispatch   ; [2] relative jump to dispatcher [19/20]

dispatch:        ; zero-page dispatcher, explicit advance (MUST have a single dispatcher)
  LDA Code,Y     ; [4] self-modified by advance
  INY            ; [2]
  STA jmp_1+1    ; [3] write to JMP    [4] unless zp
jmp_1:
  JMP Ptr        ; [3] jump to next opcode [12] (8 bytes)
arrive:
  BNE routine    ; [2] double-jumped [14]
  JMP routine    ; [3] double-jumped [15]
end_of_op:
  JMP $0000      ; [3] jump absolute [17/18] (3 bytes, saves 5 per op)
advance:                                    JSR-RTS costs [+6] saves (-2) bytes per op
  TYA            ; [2] amount to add
  LDY #0         ; [2] reset Y
  CLC            ; [2]
  ADC dispatch+1 ; [3] add Y to Code       [4] unless zp
  STA dispatch+1 ; [3] set new Code low    [4] unless zp
  TYA            ; [2] A=0
  ADC dispatch+2 ; [3] add Carry to Code   [4] unless zp
  STA dispatch+2 ; [3] set new Code high   [4] unless zp
  BCC dispatch   ; [3] always taken

extreme:         ; 3 bytes per opcode
  JSR abs        ; [3] generate JSR instructions (accessing args is tricky)
getargs:         ; instead keep a Code pointer and CLC;ADC#3;STA;BCS and fold with advance [9]
  TSX            ; [2]
  LDA $0101,X    ; [4] low byte of last byte of JSR
  STA Src        ; [3]
  LDA $0102,X    ; [4] high byte of last byte of JSR
  STA SrcH       ; [3]
  LDY #1         ; [2]
  LDA (Src),Y    ; [5] first byte after JSR [23]

indirect:        ; 2 bytes per opcode
  LDA (Code),Y   ; [5]
  INY            ; [2]
  STA Ptr        ; [3]
  LDA (Code),Y   ; [5]
  INY            ; [2]
  STA Ptr+1      ; [3]
  JMP (Ptr)      ; [5] cost [25]

self_modify:
  LDA Code       ; [4] modified LDA abs at &01 low &02 high       00 01 02
  STA $04        ; [3] modify the following JMP                   00 04
  JMP Ptr        ; [3] jump to next opcode                        00 pp cc   cost [10] (8 bytes)
arrive:
  LDY #1         ; [2] (extra)
  LDA (Code),Y   ; [5] load first param byte
advance:
  LDA #5         ; [2] opcode 1 plus operands 4
  CLC            ; [2]
  ADC $01        ; [3] 
  STA $01        ; [3]
  BEQ nextpg     ; [2]                                     JSR would cost [6]
  JMP zero_page  ; [3] cost [15] before next dispatch      RTS would cost [6]

dispatch:        ; combined technique (MUST have a single dispatcher)
  LDA Code,X     ; [4] self-modified
  INX            ; [2]
  BEQ advance    ; [2] not taken
  STA jmp_1+1    ; [3] write to JMP
jmp_1:
  JMP Ptr        ; [3] jump to next opcode [14] or [17] double-jumped
advance:         ; [1]
  INC dispatch+2 ; [5] advance to next page
  STA jmp_2+1    ; [3] write to JMP
jmp_2:
  JMP Ptr        ; [3] jump to next opcode [20] or [23] double-jumped
  ; BUT doesn't handle arguments crossing the page boundary

dispatch:        ; use Y to index Code, advance page when it wraps
  LDA (Code),Y   ; [5] load opcode
  STA BJmp       ; [3] jump low
  INY            ; [2]
  CPY #OpHwm     ; [2]
  BCS advance    ; [2]
  JMP (BJmp)     ; [5] jump indirect [[ 19 ]]

dispatch:        ; 2-byte opcode
  LDA (Code),Y   ; [5/6] get opcode (19/20 cycles, 12 bytes)  (min disp. 13 cycles 6 bytes)
  INY            ; [2] advance
  STA JtA        ; [3] Jump Table Arith low-byte
  LDA (Code),Y   ; [5/6] get opcode (19/20 cycles, 12 bytes)  (min disp. 13 cycles 6 bytes)
  INY            ; [2] advance
  STA JtA        ; [3] Jump Table Arith low-byte
  JMP (JtA)      ; [5] dispatch (C=0 A=opcode) [[ 25 ]]

go_dispatch:
  LDA (Code),Y   ; [5] load opcode
  STA $01        ; [3] jump address low
  INY            ; [2]
  JMP $0000      ; [3] jump to zero page
at_zero
  JMP $XXYY      ; [3] jump to code [[ 16 ]]


dispatch:        ; use Y to index Code, resetting Y at the start of each op
  STY Tmp        ; [3] Code += Y to advance to next opcode
  LDA Code       ; [3]
  CLC            ; [2]
  ADC Tmp        ; [3]
  STA Code       ; [3]
  LDY #0         ; [2]
  BCS nextpage   ; [2] not taken
nextop:
  LDA (Code),Y   ; [5] load opcode
  STA BJmp       ; [3] jump low
  INY            ; [2]
  JMP (BJmp)     ; [5] jump indirect [[ 33 ]]
nextpage:
  INC CodeH      ; [5] next code page
  LDA (Code),Y   ; [5] load opcode
  STA BJmp       ; [3] jump low
  INY            ; [2]
  JMP (BJmp)     ; [5] jump indirect


dispatch:        ; advance Y by const, resetting Y at the start of each op
  LDA Code       ; [3]
  CLC            ; [2]
  ADC #6         ; [2] to advance by 6 bytes
  STA Code       ; [3]
  LDY #0         ; [2]
  BCS nextpage   ; [2] not taken
  LDA (Code),Y   ; [5] load opcode
  INY            ; [2]
  STA BJmp       ; [3] jump low
  JMP (BJmp)     ; [5] jump indirect [[ 29 ]]
nextpage:
  LDA CodeH
  ADC #0
  STA CodeH
  LDA (Code),Y   ; [5] load opcode
  INY            ; [2]
  STA BJmp       ; [3] jump low
  JMP (BJmp)     ; [5] jump indirect [[ 29 ]]


ar_iconst:       ; load an integer constant (COPY and INC Y)
  LDX Code       ; [3]
  STA Src        ; [3]
  LDA CodeH      ; [3]
  STA SrcH       ; [3]
  JSR ar_copy    ; [6]
  BCC dispatch   ; [3] 21+6=27 (adds 27 cycles vs inline!)

ar_copy:
  LDA (Src),Y    ; [5] const low
  STA Acc0       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] const byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] const byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] const high byte
  STA Acc3       ; [3]
  INY            ; [2]
  RTS            ; [6]
