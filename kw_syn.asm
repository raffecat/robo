
msg_syn:
msg_rng:
err_rep:
is_digit:
tok_emit:
p_stmt:
  RTS

skip_spc:
  LDA LineBuf,Y  ; read input
  INY            ; pre-advance
  CMP #32        ; space?
  BEQ skip_spc   ; -> skip space
  DEY            ; undo advance
  RTS


; ------------------------------------------------------------------------------
; NEW THING

ORG $E400

OP_COMMA = $81
OP_SEMI = $82

Yend   = $00  ; end of match
Yexn   = $80  ; num expr x1
Yexs   = $81  ; string expr
Yexp   = $82  ; num/str expr
Yvar   = $83  ; var
Yvars  = $84  ; var[$]
Yvara  = $85  ; var[$](num)
Ystr   = $86  ; string
Ylno   = $87  ; lineno
Yemit  = $88  ; emit <byte> 
Ych    = $89  ; channel
Ystmt  = $8A  ; end,expect_stmt
Ydata  = $8B  ; emit_data,end
Yjmp   = $8C  ; always <jump>
Yno    = $8D  ; set no-match <jump>
Yinc   = $8E  ; inc opcode

; $B0 if[inc opcode <jump>]
; $B3 if <jump>

y_syn:
y_n4    DB Yexn,$2C,Yexn,$2C                           ; LINE <expr_n> ',' <expr_n> ',' <expr_n> ',' <expr_n>
y_n2    DB Yexn,$2C                                    ; POKE,PLOT,SOUND <expr_n> ',' <expr_n>
y_n1    DB Yexn                                        ; GOTO,GOSUB,RESTORE,UNTIL,MODE <expr_n>
y_x     DB Yend                                        ; CLS,END,REPEAT,RETURN,WAIT
y_let   DB Yvara,$3D,Yexp,Yend                         ; LET <var> '=' <expr>
y_dim   DB Yvars,$28,Yexn,$29,Yend                     ; DIM <var> '(' <expr_n> ')'
y_for   DB Yvar,$3D,Yexn,"TO",Yexn                     ; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>]
        DB Yno,<y_x,"STEP",Yexn,Yend
y_next  DB Yno,<y_x,Yvar,Yend                          ; NEXT [<var>]
y_else  DB Yno,<y_stmt,Ylno,Yend                       ; ELSE <line>/<stmts>
y_stmt  DB Ystmt
y_read  DB Yvara,$2C,$B3,<y_read,Yend                  ; READ {<var> ','}
y_def   DB "FN",Yvar,$28,Yvars,$29,Yend                ; DEF FN <name> '(' <var> ')'
y_open  DB $23,Ych,$2C,Yexs,Yend                       ; OPEN #<n> ',' <expr_s>
y_close DB $23,Ych,Yend                                ; CLOSE #<n>
y_rem   DB Ydata                                       ; REM <text>
y_data  DB Ydata                                       ; DATA <text>
y_if    DB Yexn,Yno,<y_stmt,"THEN",Ylno,Yend           ; IF <expr_n> (THEN <line>/<stmts> | <stmts>)
y_fnret DB Yvara,Yend                                  ; '=' <expr>

; 25b (+4)                                             ; PRINT { [,;] "str" | <expr_n> | <expr_s> } [;]
y_print DB Yno,<y_pr2,$2C,Yemit,OP_COMMA,Yjmp,<y_print ; comma
y_pr2   DB Yno,<y_pr3,$3B,Yemit,OP_SEMI,Yjmp,<y_print  ; semi
y_pr3   DB Yno,<y_pr4,Ystr,Yjmp,<y_print               ; "str"
y_pr4   DB Yno,<y_pr5,Yexp,Yjmp,<y_print               ; expr
y_pr5   DB Yend

; 25b (+4)                                             ; INPUT { [,;] "str" | <var> }
y_input DB Yno,<y_in2,$2C,Yemit,OP_COMMA,Yjmp,<y_input ; comma
y_in2   DB Yno,<y_in3,$3B,Yemit,OP_SEMI,Yjmp,<y_input  ; semi
y_in3   DB Yno,<y_in4,Ystr,Yjmp,<y_input               ; "str"
y_in4   DB Yno,<y_in5,Yvara,Yjmp,<y_input              ; var[$](num)
y_in5   DB Yend

; 123 bytes

; y_vars  DB Yvar,Yno,<Y_done,$24                        ; var[$] (7b)
; Y_done  DB Yno,$00,$00



; X = ycode offset
; Y = LineBuf/Ptr offset

ystart:
  LDX #0         ; y_syn offset
  STX C          ; no-match addr (initially none)    +2
  BEQ ynext      ; -> start

; match text token
ytext:
  STY B          ; save start of token
ytxlp:
  CMP LineBuf,Y  ; matches input?
  BNE ytxno      ; -> no match (required char)
  INY            ; advance input
  INX            ; advance y_syn
  LDA y_syn,X    ; next byte
  BPL ytxlp      ; -> next char
; next token
ynext:           ; skip spaces
  JSR skip_spc
ymatch:
  LDA y_syn,X    ; next byte
  BPL ytext      ; -> text token
; opcode
  STX B          ; save X
  TAX            ; opcode as index
  LDA yoptx,X    ; look up offset 
  STA Dst        ; set jump offset
  LDX B          ; restore X
  INX            ; advance (opcode)
  JMP (Dst)      ; -> do opcode

; no match (6b)
ytxno:
  LDY B          ; rewind input
  LDX C          ; jump to no-match addr
  BNE ynext      ; -> continue
e_syn:
  LDY <msg_syn
  JMP err_rep

yoptx = yoptb - $80
yoptb:
  DB <yexn       ; $80 num expr
  DB <yexs       ; $81 string expr
  DB <yexp       ; $82 num/str expr
  DB <yvar       ; $83 var
  DB <yvars      ; $84 var[$]
  DB <yvara      ; $85 var[$](num)
  DB <ystr       ; $86 string
  DB <ylno       ; $87 lineno
  DB <yemit      ; $88 emit <byte> 
  DB <ych        ; $89 channel
  DB <ystmt      ; $8A end,expect_stmt
  DB <ydata      ; $8B emit_data,end
  DB <yjmp       ; $8C always <jump>
  DB <ynom       ; $8D set no-match <jump>
  DB <yinc       ; $8E inc opcode

; expression
yexn:
yexs:
yexp:

yvars:           ; (14b)
  JSR yvar       ; match var name
  LDA LineBuf,Y  ; next input char
  CMP #$24       ; `$`
  BNE ynext      ; -> no, continue
  INY            ; advance input
  JMP yemitA     ; -> emit `$`

yvara:           ; (25b)
  JSR yvars      ; var[$]
  LDA LineBuf,Y  ; next input char
  CMP #$28       ; `(`
  BNE ynext      ; -> no, continue
  INY            ;
  JSR yexn       ; num expr
  LDA LineBuf,Y  ; next input char
  CMP #$29       ; `)`
  BNE e_syn      ; -> syntax error
  INY            ;
  JMP ynext      ; -> continue

yemit:
  LDA y_syn,X    ; next byte
  INX            ; 
yemitA:
  STX B          ; save X
  JSR tok_emit   ; (uses X=0; preserves A,Y) -> PL
  LDX B          ; restore X
  JMP ynext      ; -> continue

; match and emit a channel digit
ych:
  LDA LineBuf,Y  ; next input char
  JSR is_digit   ; A=char -> A=[0..9], CC=found (preserves X,Y)
  BCS e_syn      ; -> missing digit
  CMP #3         ; #0,#1,#2 are valid
  BCS e_rng      ; -> out of range (>=3)
  CMP #8         ; #8 is serial
  BEQ yemitA     ; -> emit and continue
  ; +++ fall through +++
e_rng:           ; out of range
  LDY <msg_rng
  JMP err_rep

ystmt:
  JMP p_stmt     ; expect stmt

yjmp:
  LDA y_syn,X    ; next byte
  TAX            ; set y_syn offset
  JMP ynext      ; -> continue

ynom:
  LDA y_syn,X    ; next byte
  STA C          ; set no-match addr
  INX            ; 
  JMP ynext      ; -> continue

yinc:
  STX B          ; save X
  LDX D          ; saved opcode ofs
  INC EmitBuf,X  ; increment opcode
  LDX B          ; restore X
  JMP ynext

; match and emit data (rest of line)
ydata:

; match and emit a VAR name
yvar:

; match and emit a string
ystr:

; match and emit a line number
ylno:


DB 0  ; 216
