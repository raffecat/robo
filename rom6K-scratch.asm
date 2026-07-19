
; ------------------------------------------------------------------------------
; BASIC Dispatcher

MACRO DISPATCH
   JMP rom_disp
ENDM

; @@ rom_disp, disp_stmt
; Y remains valid at all times as CODE offset
; Only advance CODE between statements
disp_stmt:
  TYA            ; [2] current CODE offset [all BASIC handlers MUST preserve]
  LDY #0         ; [2] reset CODE offset
  CLC            ; [2]
  ADC CODE       ; [3] add Y to CODE low
  STA CODE       ; [3] update CODE low
  BCS @bump      ; [2] -> next page [+1]
  JMP rom_disp   ; [3] -> opcode dispatch  [17]    (JMP to `ram_disp` for RAM routine)
@bump:
  INC CODEH      ; [5] advance CODE high byte
;;  JMP ram_disp   ; [3] -> opcode dispatch  [26]  (use JMP only for RAM routine)

rom_disp:
  LDA (CODE),Y     ; [5] fetch opcode
  INY              ; [2] advance CODE offset
  STA ram_disp     ; [3] store pointer low byte (use `ram_disp` as a POINTER for rom_disp)
  JMP (ram_disp)   ; [5] -> JMP [+3] -> [18]

; table of opcode JMP instructions (ONE page only: 86 opcodes)
; write opcode into RAM JMP instruction, then execute it
; COPY this routine to ram_disp when entering BASIC {8 bytes}
ram_disp_src:
  LDA (CODE),Y     ; [5] fetch opcode
  STA ram_disp+6   ; [3] store in JMP+1 (low byte of address)
  INY              ; [2] advance CODE offset
  JMP basjmp       ; [3] -> JMP [+3] -> [16]


; @@ print_hex
; print a u16 number {Acc0,1} in hexadecimal
print_hex:      ; print Acc1,Acc0 in hex (uses A,X,Y)
  LDA Acc1      ; high byte
  JSR out_hex
  LDA Acc0
  ; fall through
out_hex:
  TAY
  CLC
  LSR           ; 0 -> Acc -> C
  LSR
  LSR
  LSR
  CMP #10
  BCC ok1       ; if < 10 -> skip (C=0)
  ADC #6        ; 'A'-10-48-(C=1)
ok1:
  ADC #48       ; add '0'
  JSR writechar ; output char to screen (A=char, preserves Y)
  TYA
  AND #15
  CMP #10
  BCC ok2       ; if < 10 -> skip (C=0)
  ADC #6        ; 'A'-10-48-(C=1)
ok2:
  ADC #48       ; add '0'
  JMP writechar ; output char to screen (A=char, preserves Y)







; EXPRESSION Parsing
; ^  *,/,DIV,MOD  +,-  =,<>,<=,<,>=,>  AND  OR,EOR

; @@ cg_expr
cg_expr:           ; (uses A,X,Y,B,C,D,Src,Acc)
  JSR cg_expr_o    ;
  BCC @no_expr     ; -> no match
  RTS
@no_expr:
  LDY #<kwt_expr
  JMP cgx_expect_y

; @@ cg_expr_o
cg_expr_o:         ; (uses A,X,Y,B,C,D,Src,Acc) -> CS=found
  JSR skip_spc     ; X=ln (uses A)
  JSR is_alpha     ; CC=alphabetic A=alphabet-index (uses A)
  BCS @not_kw      ; -> not a keyword
  ; keyword lookup
  TAY              ; as an index (0-25)
  LDA expr_idx,Y   ; offset within keyword table
  LDY #>expr_page  ; expr keyword table
  JSR scan_kw_idx  ; X=ln A,Y=table -> CS=found, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCC @not_kw      ; -> no match
  ; matched keyword
  AND #63          ; low 6 bits
  CMP #50          ; ASSERT <50
  BCS @bounds      ; ASSERT
  TAY              ; as index
  LDA expr_pb,Y    ; A = parse byte
  STA D            ; save parse flags for parse function
  AND #15          ; low 4 bits
  JSR @call        ; -> call handler and return here
  JMP @infix
@bounds
  JMP cgx_bounds
@not_kw:
  LDA LineBuf,X    ; get next char
  CMP #$28         ; "("
  BEQ @subexpr     ; -> subexpression
  CMP #$2D         ; "-"
  BEQ @minus       ; -> minus
  CMP #$2B         ; "+"
  BEQ @plus        ; -> plus
  CMP #$22         ; '"'
  BEQ @str         ; -> string literal
  SEC
  SBC #48          ; '0'
  CMP #10          ; digits
  BCC @num         ; -> digits 0-9
  JSR cg_var_o     ; must be a var
  BCS @infix       ; -> matched a var
  CLC              ; CC=not-found
  RTS
@call:
  ASL              ; times 2 (word index)
  TAY              ; as index
  LDA expr_fn+1,Y  ; parse function, high byte
  PHA              ; push high
  LDA expr_fn,Y    ; parse function, low byte
  PHA              ; push low
  RTS              ; return to parse function
@subexpr:
  INX              ; skip "("
  JSR cg_expr      ; require expression
  LDY #$29         ; ")"
  JSR cg_chr       ; require ")"
  JMP @infix
@minus:
  INX              ; skip "-"
  JSR cg_expr      ; require expression
  ; XXX check if Acc holds num
  LDA #OP_NEG      ; negate Acc
  JSR cg_emit
  BNE @infix       ; always
@plus:
  INX              ; skip "+"
  JSR cg_expr      ; require expression
  ; XXX check if Acc holds num/str
  LDA #OP_UPLUS    ; numerify Acc
  JSR cg_emit
  BNE @infix       ; always
@str:
  INX              ; skip '"'
  JSR cg_str_lp    ; -> rest of string
  JMP @infix
@num:
  JSR cg_num_o     ; parse and output number
  JMP @infix
@rhs:
  STA E            ; set rbp for cg_expr
  JSR cg_expr
@infix:
  ; infix operators
  JSR skip_spc
  LDA LineBuf,X    ; get next char
  INX              ; pre-advance
  CMP #$5E         ; '^' [8*4=32]  or [8*(4+2+2)=64] with a table (smaller [32 vs 16], 1/2 speed)
  BEQ @ifx_pow
  CMP #$2A         ; '*'
  BEQ @ifx_mul
  CMP #$2B         ; '+'
  BEQ @ifx_div
  CMP #$3D         ; '='
  BEQ @ifx_add
  CMP #$3C         ; '<'
  BEQ @ifx_sub
  CMP #$2F         ; '/'
  BEQ @ifx_lt
  CMP #$2D         ; '-'
  BEQ @ifx_eq
  CMP #$3E         ; '>'
  BEQ @ifx_gt
  DEX              ; undo pre-advance
  LDA #<kw_infix
  LDY #>kw_infix
  JSR scan_kw_all  ; X=ln A,Y=table -> CS=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCS @ifx_kw
  ; end of expression
  SEC              ; CS=found
  RTS              ; CS=found
@ifx_pow:
  LDA #OP_POW
  JSR cg_emit
  LDA #1           ; ^ rbp
  CMP E            ; compare rbp
  BNE @rhs
@ifx_mul:
  LDA #OP_MUL
  JSR cg_emit
  LDA #2           ; *,/ rbp
  CMP E            ; compare rbp
  BNE @rhs
@ifx_div:
  LDA #OP_DIV
  JSR cg_emit
  LDA #2           ; *,/ rbp
  CMP E            ; compare rbp
  BNE @rhs
@ifx_add:
  LDA #OP_ADD
  JSR cg_emit
  LDA #3           ; +,- rbp
  CMP E            ; compare rbp
  BNE @rhs
@ifx_sub:
  LDA #OP_SUB
  JSR cg_emit
  LDA #3           ; +,- rbp
  CMP E            ; compare rbp
  BNE @rhs
@ifx_lt:
  LDA LineBuf,X    ; get next char
  INX              ; pre-advance
  CMP #$3D         ; '='
  BEQ @ifx_le
  CMP #$3E         ; '>'
  BEQ @ifx_ne
  DEX              ; undo pre-advance
  ; less than
  LDA #OP_LT
  JSR cg_emit
  JSR cg_expr      ; require expression -> done
  JMP @infix
@ifx_eq:
  LDA #OP_EQ
  JSR cg_emit
  JSR cg_expr      ; require expression -> done
  JMP @infix
@ifx_gt:
  LDA LineBuf,X    ; get next char
  INX              ; pre-advance
  CMP #$3D         ; '='
  BEQ @ifx_ge
  DEX              ; undo pre-advance
  ; greater than
  LDA #OP_GT
  JSR cg_emit
  JSR cg_expr      ; require expression -> done
  JMP @infix
@ifx_kw:
  JSR cg_emit      ; [write OPCODE]
  JSR cg_expr      ; require expression -> done
  JMP @infix
@ifx_le:
  LDA #OP_LE
  JSR cg_emit
  JSR cg_expr      ; require expression -> done
  JMP @infix
@ifx_ne:
  LDA #OP_NE
  JSR cg_emit
  JSR cg_expr      ; require expression -> done
  JMP @infix
@ifx_ge:
  LDA #OP_GE
  JSR cg_emit
  JSR cg_expr      ; require expression -> done
  JMP @infix




; KEYWORD parse-function table
; matches stmt_pb entries
; no special alignment requirements         (XXX avoid crossing page boundary though)
stmt_fn:            ; [20]
  DW cg_for      -1 ;  0 = FOR .. TO .. [ STEP .. ]
  DW cg_if       -1 ;  1 = IF .. THEN .. [ ELSE .. ]
  DW cg_print    -1 ;  2 = PRINT .. SPC .. TAB .. ~';
  DW cg_varlist  -1 ;  3 = LOCAL/NEXT/READ  var-list .. A,B  7=indices 6=optional
  DW cg_dim      -1 ;  4 = DIM .. A(n,..)
  DW cg_data     -1 ;  5 = DATA .. , .. (up to 255)
  DW cg_args     -1 ;  6 = expr x NN
  DW cg_def      -1 ;  7 = DEF .. FN|PROC name (a,b..)
  DW cg_none     -1 ;  8 = none
  DW cg_else     -1 ;  9 = ELSE
  DW cg_proc     -1 ; 11 = PROC
  DW cg_let      -1 ; 12 = LET .. var = ..
  DW cg_on       -1 ; 13 = ON .. ERROR|num .. GOTO|GOSUB .. ELSE
  DW cg_rem      -1 ; 14 = REM ..
  DW cg_onoff    -1 ; 15 = on-off
  DW cg_expr14   -1 ; 16 = expr x 1-4
  DW cg_hash     -1 ; 17 = # stmt

; X = input line offset
; E = parse flags for parse function
; [writes OPCode] for stmt

; @@ cg_for
; PARSE: var "=" iexpr "TO" iexpr [ "STEP" iexpr ]
; WRITE: (var) (expr) (expr) [ OP_STEP (expr) ]
cg_for:          ; X=ln-ofs
  JSR cg_var     ; X=ln (uses A,Y,B)  [writes var-index]
  LDY #61        ; "="
  JSR cg_chr     ; X=ln Y=ch (uses A)
  JSR cg_expr    ; (uses A,X,Y,B,C,D,Src,Acc) [writes expr-code]
  LDY #<kwt_to   ; "TO"
  JSR cg_kw      ; X=ln Y=kw (uses A,Y,B,C)
  JSR cg_expr    ; (uses A,X,Y,B,C,D,Src,Acc) [writes expr-code]
  LDY #<kwt_step ; "STEP"
  JSR cg_kw_o    ; X=ln Y=kw (uses A,Y,B,C) -> CS=found
  BCC @no_step   ; -> no STEP
  LDA #OP_STEP   ; 
  JSR cg_emit    ;                            [writes OP_STEP]
  JSR cg_expr    ; (uses A,X,Y,B,C,D,Src,Acc) [writes expr-code]
@no_step:
cg_none:
  RTS            ; -> X=ln


; @@ cg_if
; PARSE: expr "THEN" line|stmt* [ "ELSE" line|stmt* ]
; WRITE: (expr) (len) (stmts) [ OP_ELSE (len) (stmts) ]
cg_if:
  JSR cg_expr    ; (uses A,X,Y,B,C,D,Src,Acc) [writes expr-code]
  LDY #<kwt_then ; "THEN"
  JSR cg_kw_o    ; X=ln Y=kw (uses A,Y,B,C) -> CS=found, A=OP
  BCC @no_then   ; -> no THEN
  JSR tok_n16    ; X=ln (uses A,Y,B,Acc01) -> Acc01,CS=found
  BCS @then_ln   ; -> THEN <line>
  LDA #OP_THEN   ;
  JSR cg_emit    ;                    [writes OP_THEN]
@no_then:
  ; XXX reserve a byte for THEN length
  JSR cg_stmts   ;                    [writes stmt-code]
@if_else:
  LDY #<kw_else  ; "ELSE"
  JSR cg_kw_o    ; X=ln Y=kw (uses A,Y,B,C) -> CS=found, A=OP
  BCC @no_else   ; -> no ELSE
  JSR tok_n16    ; X=ln (uses A,Y,B,Acc01) -> Acc01,CS=found
  BCS @else_ln   ; -> ELSE <line>
  LDA #OP_ELSE   ;
  JSR cg_emit    ;                    [writes OP_ELSE]
  ; XXX reserve a byte for ELSE length
  JMP cg_stmts   ;                    [writes stmt-code]
@then_ln:
  LDA #OP_THENG  ;
  JSR @wr_goto
  JMP @if_else
@else_ln:
  LDA #OP_ELSEG  ;
@wr_goto:
  JSR cg_emit    ;                    [writes OP_THENG]
  LDA Acc0       ; low byte
  JSR cg_emit    ;                    [writes Line lo]
  LDA Acc1       ; high byte
  JSR cg_emit    ;                    [writes Line hi]
@no_else:
  RTS


; @@ cg_print
; Print statement.
; Ends only when no EXPR and no CTRL symbol.
; how do we decode this?
; OP_PRINT,OP_STR,OP_SEMI,OP_VAR,OP_COMMA,OP_PAREN,OP_PEND|OP_PENDS
; ^ if stmts have top-bit, next stmt ends print (semi changes OP_PRINT to OP_PRINTS)
; ^ if print ends with ' is it elided?
cg_print:
@loop:
  JSR skip_spc    ; X=ln (uses A)
  LDA LineBuf,X   ; get next char (spaces skipped in cg_expr)
  BEQ @done       ; -> end of line
  INX             ; advance input (assume match)
  CMP #$2C        ; ","
  BEQ @comma      ; -> write OP_COMMA (to colum mode)
  CMP #$3B        ; ";"                            (flag:optional flag:restart)
  BEQ @semi       ; -> write OP_SEMI (to compact mode)
  CMP #$27        ; "'"
  BEQ @eol        ; -> write OP_EOL (end of line)
  CMP #$53        ; "S"
  BEQ @spc
  CMP #$54        ; "T"
  BEQ @tab
  DEX             ; undo advance, so cg_expr_o can match it
@try_ex:
  JSR cg_expr_o   ; (uses A,X,Y,B,C,D,Src,Acc) -> CS=found
  BCS @loop       ; -> found expr
  ; CMP #OP_SEMI  ; was the last opcode a semi?    (token:endif)
                  ; ^ won't work, EXPR OPs end with data bytes
                  ;   need to store last opcode written (or similar)
@done:
  ; add OP_EIF, or OP_EIFS if last opcode was OP_SEMI (replace it?)
  RTS             ; end of print
@comma:
  LDA #OP_COMMA
  JSR cg_emit     ; [write OP_COMMA]
  BNE @loop
@semi:
  LDA #OP_SEMI
  JSR cg_emit     ; [write OP_SEMI]
  BNE @loop
@eol:
  LDA #OP_EOL
  JSR cg_emit     ; [write OP_EOL]
  BNE @loop
@spc:
  LDY #<kwt_spc
  BNE @spc_e
@tab:
  LDY #<kwt_tab
@spc_e:
  DEX             ; undo advance, so cg_kw_o can match it
  JSR cg_kw_o     ; X=ln Y=kw (uses A,Y,B) -> CS=found A=OP
  BCC @try_ex     ; -> try expr
  JSR cg_emit     ; [write OP_SPC/OP_TAB]
  ; XXX <---- parse param
  BNE @loop


; @@ cg_varlist (3)
; comma separated list of vars; $80 allow indices; $40 optional
; Code: LOCAL/NEXT/READ 
cg_varlist:
  JSR cg_var_o     ; X=ln -> B=start X=end CS=found (uses A,X,B)
  BCC @novars      ; -> no vars found
@loop:
  LDY #$2C         ; ','
  JSR cg_chr_o     ; X=ln Y=ch -> CS=found (uses A,X,Y)
  BCC @nocomma     ; -> not a comma
@next:
  JSR cg_var_o     ; X=ln -> B=start X=end CS=found (uses A,X,B)
  BCS @loop        ; -> found a var, go again
@done:
  LDA #0
  JSR cg_emit      ; zero terminate
  RTS
@novars:
  BIT E            ; parse flags [N=parens][V=optional]
  BVS @done        ; -> ok to match nothing
  LDY #<kwt_var
  JMP cgx_expect_y
@nocomma:
  BIT E            ; parse flags [N=parens][V=optional]
  BPL @done        ; -> parens are not ours
  LDY #$28         ; '('
  JSR cg_chr_o     ; X=ln Y=ch -> CS=found (uses A,X,Y)
  BCC @done        ; -> no paren found
  JSR cg_exprlist  ; parse `x,y,z..)`
  LDY #$2C         ; ','
  JSR cg_chr_o     ; X=ln Y=ch -> CS=found (uses A,X,Y)
  BCS @next        ; -> after comma
  BCC @done        ; -> not a comma (we're done)


; @@ cg_dim ()
cg_dim:
  JSR cg_var       ; X=ln (uses A,B)
  LDY #$28         ; '('
  JSR cg_chr       ; X=ln Y=ch (uses A)
  JSR cg_exprlist  ; parse `x,y,z..)`
  RTS

cg_len_start:     ; (uses A,D) -> A,D=0
  LDA CODE        ; save current write-pos (Src = write-pos)
  STA Src
  LDA CODEH
  STA SrcH
  LDA #0
  JSR cg_emit     ; write length placeholder
  STA D
  RTS

cg_len_end:       ; (uses A,Y)
  LDA D           ; get length counter
  LDY #0          ;
  STA (Src),Y     ; write length counter at saved write-pos
  RTS             ;


; @@ cg_data ()
cg_data:
@loop:
  JSR cg_s32      ; from LineBuf,X -> Acc,X,NE=found (uses A,Y,B,C,Term)
  BNE @num        ; -> write a number
  JSR cg_str_o    ; output str (with length prefix)
  BCS @comma      ; -> wrote a string
  ; implicit string, up to next comma
  JSR cg_len_start ; (uses A,D) -> A,D=0
@raw:
  LDA LineBuf,X   ; next input char
  BEQ @ends       ; -> end of input
  INX             ; advance input
  INC D           ; count characters
  CMP #$2C        ; ','
  BNE @raw        ; -> no comma
@ends:
  DEC D           ; counted one too many
  JSR cg_len_end  ; patch D into code
  JMP @loop       ; -> another
@num:
  LDA #0
  JSR cg_emit     ; "zero-len" number sentinel
  LDA Acc0        ; copy number to output
  JSR cg_emit
  LDA Acc1
  JSR cg_emit
@comma:
  LDY #$2C        ; ','
  JSR cg_chr_o    ; X=ln Y=ch (uses A) -> CS=found
  BCS @loop
  RTS


; @@ cg_args ()
cg_args:
  LDA E           ; get parse flags [NNNPPPPP]
  ROL             ; N[NNPPPPPC]
  ROL             ; N[NPPPPPCN]
  ROL             ; N[PPPPPCNN]
  ROL             ; P[PPPPCNNN]
  AND #7          ;  [00000NNN]
  STA E           ; number of args
@loop:
  JSR cg_expr     ; (uses A,X,Y,B,C,D,Src,Acc)
  DEC E           ; count down args
  BEQ @done       ; -> have all expected args
  JSR skip_spc
  LDA LineBuf,X   ; next input char
  INX             ; advance (assume match)
  CMP #$2C        ; is it ','?
  BEQ @loop       ; -> found comma, go again
  DEX             ; undo advance
  LDA #$2C        ; ','
  JMP cgx_expect  ; -> "Expecting ," (A)
@done:
  RTS

; @@ cg_def
cg_def:
  ; try PROC
  LDY #<kwt_proc
  JSR cg_kw_o     ; X=ln Y=kw (uses A,Y,B) -> CS=found A=OP
  BCS @proc       ; -> is DEF PROC
  ; try FN
  LDY #<kwt_fn
  JSR cg_kw_o     ; X=ln Y=kw (uses A,Y,B) -> CS=found A=OP
  BCC syn_err
  JSR cg_var      ; XXX should be cg_name (not a var)
  ; require "(" for FN
  LDY #$28        ; '('
  JSR cg_chr      ;
@args:
  JSR cg_varlist  ; require one arg (uses A,Y,B)
  LDY #$29        ; ')'
  JSR cg_chr      ; require ')'
@done:
  RTS
@proc:
  JSR cg_var      ; XXX should be cg_name (not a var)
  ; optional "(" for PROC
  LDY #$28        ; '('
  JSR cg_chr_o    ; X=ln Y=ch (uses A) -> CS=found
  BCC @done       ; -> no params
  LDY #$29        ; ')'
  JSR cg_chr_o    ; X=ln Y=ch (uses A) -> CS=found
  BCC @args       ; -> non-empty params
  BCS @done       ; -> empty params

syn_err:
  LDY #<msg_syntax
  JMP report_err


; @@ cg_else
cg_else:
  ; XXX if the line contains a prior IF statement,
  ; XXX this statement will be parsed inside that IF body cg_stmts loop
  ; XXX otherwise we report "No IF"
  ; XXX we must 'exit' the cg_stmts loop,
  ; XXX causing it to end the IF body and parse the ELSE body
  ; XXX length-prefix
  ; XXX stmt_list
  ; XXX clear the last IF statement
  RTS


; @@ cg_envelope
cg_envelope:
  ; XXX parse 14 numbers as bytes
  RTS


; @@ cg_proc
cg_proc:
  JSR cg_var      ; XXX should be cg_name (not a var)
  ; optional "(" for PROC
  LDY #$28        ; '('
  JSR cg_chr_o    ; X=ln Y=ch (uses A) -> CS=found
  BCC cg_proc_rt  ; -> no params
  LDY #$29        ; ')'
  JSR cg_chr_o    ; X=ln Y=ch (uses A) -> CS=found
  BCS cg_proc_rt  ; -> empty params
cg_exprlist:
  JSR cg_expr     ; expect an expression (required)
@loop:
  LDY #$2C        ; ','
  JSR cg_chr_o    ; X=ln Y=ch (uses A) -> CS=found
  BCC @done       ; -> no comma, done
  JSR cg_expr_o   ; expect an expression
  BCS @loop       ; -> found, go again
@done:
  LDY #$29        ; ')'
  JSR cg_chr      ; X=ln Y=ch (uses A) require ')'
cg_proc_rt:
  RTS

; @@ cg_let
cg_let:
  JSR cg_var         ; X=ln (uses A,B)
  LDY #$3D           ; '='
  JSR cg_chr         ; X=ln Y=ch (uses A)
  JSR cg_expr        ; (uses A,X,Y,B,C,D,Src,Acc)
  RTS


; @@ cg_on
cg_on:
  ; XXX GOTO or GOSUB or PROC ...
  RTS


; @@ cg_rem
cg_rem:
  ; XXX chomp rest of line
  RTS


; @@ cg_onoff
cg_onoff:
  ; XXX parse ON or OFF, encode as byte?
  RTS

cg_expr14:   ; expr x 1-4  (uses A,X,Y,B,C,D,Src,Acc)
  RTS

cg_hash:     ; # stmt
  RTS





  AND #63            ; clear top 2 bits of hi-byte
  CMP #41            ; ASSERT
  BCS @bounds        ; ASSERT
  TAY                ; [2] 0-40 as index
;; LDA stmt_pb,Y      ; [4] A = parse byte (indexed by opcode)
  STA E              ; [3] save parse flags for parse function
  AND #31            ; [2] low 5 bits
  ; dispatch
  ASL                ; [2] times 2 (word index)
  TAY                ; [2] as index
;;  LDA stmt_fn+1,Y    ; [4] parse function, high byte
  PHA                ; [3] push high
;;  LDA stmt_fn,Y      ; [4] parse function, low byte
  PHA                ; [3] push low
  RTS                ; [6] return to parse function
@bounds:
  LDY #<msg_range
  JMP report_err






; ------------------------------------------------------------------------------
; PAGE 16 - INTERPRETER


; Classic BASIC:
; Tokenised "Parse during Execute" model
; If Space -> skip (discard all spaces during tokenize)
; If Operator -> pop and execute higher ops; push op (SEPARATE stack, use LineBuf)
; If Alpha -> parse Name and find VAR (at the same time?) -> push VAR tag + pointer
; If Digit -> parse Number (Tokenise numbers: 0OPS; 1OP; 2OP; 3OP; 4OP) -> push NUM tag + value
; If LParen -> push '('
; If RParen -> pop and execute ops until '(' found
; If Unexpected -> pop and execute ops -> stack-check -> RTS

; Operators: +, -, *, /, DIV, MOD, AND, OR, EOR, 
; Integers: 10 x 0OPs, 1OP, 2OP, 3OP, 4OP (14)
; Floats: 1FP, 2FP, 3FP, 4FP, 5FP (5)
; Vars: 1VAR, NVAR, 1VAR$, NVAR$ (4)
; 256-byte classifier table: char -> JMP offset in RT page

; one-address opcodes work better for 6502
; can also TSX and work with $100,X (SP -> below last PHA)

; A=B*2+C -> VAR:B MULI1:2 ADDV:C

basjmp:
;  JMP rt_add_v    ; var: (LDA var; ADC Acc)
;  JMP rt_sub_v    ;
;  JMP rt_mul_v
;  JMP rt_div_v
;  JMP rt_addi1
;  JMP rt_addi2
;  JMP rt_addi4
;  JMP rt_addf
;  JMP rt_subi1
;  JMP rt_subi2
;  JMP rt_subi4
;  JMP rt_subf
;  JMP rt_muli1
;  JMP rt_muli2
;  JMP rt_muli4
;  JMP rt_mulf
;  JMP rt_divi1
;  JMP rt_divi2
;  JMP rt_divi4
;  JMP rt_divf     ;                          20
;  JMP rt_push     ; Push Acc
;  JMP rt_pop_add  ; Pop and Add to Acc
;  JMP rt_pop_sub  ; Pop and Sub from Acc
;  JMP rt_pop_mul  ; Pop and Mul Acc
;  JMP rt_pop_div  ; Pop and Div Acc          25
;  JMP rt_c1       ; Acc = i1
;  JMP rt_c2       ; Acc = i2
;  JMP rt_c4       ; Acc = i4
;  JMP rt_var1     ; Acc = Var len=1
;  JMP rt_varN     ; Acc = Var len=N          30
;  JMP rt_let1     ; Var = Acc len=1
;  JMP rt_letN     ; Var = Acc len=N
;  JMP rt_if       ; JSR expr; test Acc; GOTO line or !GOTO next-line
;  JMP rt_print    ; [;]Str/Var/JSR expr/;/,/'


; LOAD CONSTANT

ar_f1const:      ; load floating point constant (1-byte mantissa)
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i1const:      ; load 1-byte signed integer constant
  LDA (CODE),Y   ; [5] const byte 0
  INY            ; [2] advance
  STA Acc0       ; [3]
  ORA #$7F       ; [2] sign extend
  BMI @neg       ; [2] -> [3]
  LDA #0         ; [2] positive
@neg:
  STA Acc1       ; [3] sign extend
  STA Acc2       ; [3] sign extend
  STA Acc3       ; [3] sign extend      (21 CYCLES)
  ;DISPATCH

ar_f2const:      ; load floating point constant (2-byte mantissa)
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i2const:      ; load 2-byte signed integer constant
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc0       ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc1       ; [3]
  ORA #$7F       ; [2] sign extend [14]
  BMI @neg       ; [2] -> [3]
  LDA #0         ; [2] positive
@neg:
  STA Acc2       ; [3]  sign extend
  STA Acc3       ; [3]  sign extend     (24 CYCLES)
  ;DISPATCH

ar_f3const:      ; load floating point constant (3-byte mantissa)
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i3const:      ; load 3-byte signed integer constant
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc0       ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc1       ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc2       ; [3]
  ORA #$7F       ; [2] sign extend [20]
  BMI @neg       ; [2] -> [3]
  LDA #0         ; [2] positive
@neg:
  STA Acc3       ; [3] sign extend      (27 CYCLES)
  ;DISPATCH

ar_f4const:      ; load floating point constant (4-byte mantissa)
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA AccE       ; [3] exponent         (+6 CYCLES)
ar_i4const:      ; load 4-byte signed integer constant
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc0       ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc1       ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc2       ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Acc3       ; [3]                  (24 CYCLES)
  ;DISPATCH


; LOAD VARIABLE

ar_ivar:         ; read an integer variable  (XXX unify these, always copy 5 bytes)
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  TAX
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  ; fall
;ar_ireadax:     ; also used to read from arrays (COPY Indirect)
  STX Src        ; [3]
  STA SrcH       ; [3]
  LDY #0         ; [2]
  ; fall
ar_iread4:
  LDA (Src),Y    ; [5] load var low byte
  STA Acc0       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] load var byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] load var byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA (Src),Y    ; [5] load var high byte
  STA Acc3       ; [3]
  ;DISPATCH

ar_fvar:         ; read an integer variable
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA Src        ; [3]
  LDA (CODE),Y   ; [5] const exponent
  INY            ; [2] advance
  STA SrcH       ; [3]
  LDY #0         ; [2]
  LDA (Src),Y    ; [5] load var low byte
  STA AccE       ; [3] exponent
  INY            ; [2]
  BNE ar_iread4  ; [2] always taken


; ADD CONST INT

ar_uadd2c:       ; add 2-byte unsigned integer constant
  LDA #2         ; [2] const length
  BNE ar_uaddc   ; [3] -> common uaddc

ar_uadd3c:       ; add 2-byte unsigned integer constant
  LDA #3         ; [2] const length
  BNE ar_uaddc   ; [3] -> common uaddc

ar_uadd4c:       ; add 2-byte unsigned integer constant
  LDA #4         ; [2] const length
  BNE ar_uaddc   ; [3] -> common uaddc

ar_uadd1c:       ; add 1-byte unsigned integer constant
  LDA #1         ; [2] const length
  ; +++ fall through to @@ ar_uaddc +++  {14}

ar_uaddc:
  STA B          ; [3] save const length
  CLC            ; [2]
  LDX #0         ; [2] index into Acc0[4] (Lo -> Hi)
@loop:
  LDA (CODE),Y   ; [5] const int
  INY            ; [2] advance
  ADC Acc0,X     ; [3] add const to next byte of Acc0
  STA Acc0,X     ; [3] update Acc0
  INX            ; [2] advance to next byte of Acc0
  DEC B          ; [5] more const bytes?
  BNE @loop      ; [2] -> next const byte [+1]
  BCC @done      ; [2] -> no carry [+1]
  LDA #0         ; [2] add #0 to add carry
@carry:
  CPX #3         ; [2] at last byte of Acc0?
  BEQ @done      ; [2] -> end of Acc0 [+1]
  ADC Acc0,X     ; [3] add carry to next byte of Acc0
  STA Acc0,X     ; [3] update Acc0
  INX            ; [2] advance to next byte of Acc0
  BCS @carry     ; [2] -> more carry [+1]                   {35} -> {49}
@done:
  ;DISPATCH



; ADD CONST INT STACK

; A,Y = opcode (from DISPATCH)
ar_uadd1C:       ; add 2-byte unsigned integer constant
  LDA (CODE),Y   ; [5] const int
  INY            ; [2] advance
  PHA            ; [3] push
  LDA #0         ; [2]
  PHA            ; [3] push
  PHA            ; [3] push
  PHA            ; [3] push
  BEQ ar_uadd_S  ; [3] -> common ar_uadd_S

ar_uadd3C:       ; add 2-byte unsigned integer constant
  LDA #3         ; [2] const length
  BNE ar_uaddc   ; [3] -> common ar_uadd_S

ar_uadd4C:       ; add 2-byte unsigned integer constant
  LDA #4         ; [2] const length
  BNE ar_uaddc   ; [3] -> common ar_uadd_S

ar_uadd0C:       ; add 1-byte unsigned integer constant
  AND #$0F       ; [2] 4-bit const int in the low bits of the opcode
  PHA            ; [3] push
  LDA #0         ; [2]
  PHA            ; [3] push
  PHA            ; [3] push
  PHA            ; [3] push
  ; +++ fall through to @@ ar_uadd_S +++  {14}

ar_uadd_S:




; ADD CONST INT LADDER

; entry points   {14}

ar_uaddc_L:      ; add unsigned integer constant (X = const length)
  CLC            ; [2]

  LDA (CODE),Y   ; [5] const int
  INY            ; [2] advance
  ADC Acc0       ; [3] add constant byte 0 to LOW byte
  STA Acc0       ; [3]
  DEX            ; [2]
  BEQ @carry0    ; [2] -> to carry ladder [+1]

  LDA (CODE),Y   ; [5] const int
  INY            ; [2] advance
  ADC Acc1       ; [3] add constant byte 1 to BYTE 1
  STA Acc1       ; [3]
  DEX            ; [2]
  BEQ @carry1    ; [2] -> to carry ladder [+1]

  LDA (CODE),Y   ; [5] const int
  INY            ; [2] advance
  ADC Acc2       ; [3] add constant byte 2 to BYTE 2
  STA Acc2       ; [3]
  DEX            ; [2]
  BEQ @carry2    ; [2] -> to carry ladder [+1]

  LDA (CODE),Y   ; [5] const int
  INY            ; [2] advance
  ADC Acc3       ; [3] add constant byte 3 to HIGH byte
  STA Acc3       ; [3]

  ;DISPATCH

@carry0:
  LDA #0         ; [2] add #0 to add carry
  ADC Acc1       ; [3] add constant byte 1 to BYTE 1
  STA Acc1       ; [3]
  BCC @done      ; [2] -> no carry [+1]
@carry1:
  LDA #0         ; [2] add #0 to add carry
  ADC Acc2       ; [3] add constant byte 2 to BYTE 2
  STA Acc2       ; [3]
  BCC @done      ; [2] -> no carry [+1]
@carry2:
  LDA #0         ; [2] add #0 to add carry
  ADC Acc3       ; [3] add constant byte 3 to HIGH byte   {25}  ->  {82}
  STA Acc3       ; [3]
@done:
  ;DISPATCH



; ------------------------------------------------------------------------------
; PAGE


; VARS - ADD INTEGER

ar_iaddv:        ; add an integer variable
  LDA (CODE),Y   ; [5] pointer low
  INY            ; [2] advance
  TAX
  LDA (CODE),Y   ; [5] pointer high
  INY            ; [2] advance
  ; fall
;ar_iaddax:
  STX Src        ; [3]
  STA SrcH       ; [3]
  LDY #0         ; [2]
  CLC            ; [2] 16
  LDA Acc0       ; [3]
  ADC (Src),Y    ; [5] add var low byte
  STA Acc0       ; [3]
  INY            ; [2]
  LDA Acc1       ; [3]
  ADC (Src),Y    ; [5] add var byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA Acc2       ; [3]
  ADC (Src),Y    ; [5] add var byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA Acc3       ; [3]
  ADC (Src),Y    ; [5] add var high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check  16+4*13 = (68 CYCLES)
  ;DISPATCH

ar_isubv:        ; subtract an integer variable (pointer follows)
  LDA (CODE),Y   ; [5] pointer low
  INY            ; [2] advance
  TAX
  LDA (CODE),Y   ; [5] pointer high
  INY            ; [2] advance
;ar_isubax:
  STX Src        ; [3]
  STA SrcH       ; [3]
  LDY #0         ; [2]
  SEC            ; [2] 16
  LDA Acc0       ; [3]
  SBC (Src),Y    ; [5] subtract var low byte
  STA Acc0       ; [3]
  INY            ; [2]
  LDA Acc1       ; [3]
  SBC (Src),Y    ; [5] subtract var byte 1
  STA Acc1       ; [3]
  INY            ; [2]
  LDA Acc2       ; [3]
  SBC (Src),Y    ; [5] subtract var byte 2
  STA Acc2       ; [3]
  INY            ; [2]
  LDA Acc3       ; [3]
  SBC (Src),Y    ; [5] subtract var high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check  16+4*13 = (68 CYCLES)
  ;DISPATCH

overflow:
  BRK
  DW 1


; PUSH / POP - INTEGER

ar_ipush:        ; push acc (begin sub-expr)
  LDA Acc3       ; [3]
  PHA            ; [3] push low byte
  LDA Acc2       ; [3]
  PHA            ; [3] push byte 1
  LDA Acc1       ; [3]
  PHA            ; [3] push byte 2
  LDA Acc0       ; [3]
  PHA            ; [3] push high byte   (24 CYCLES)
  ;DISPATCH

ar_ipopadd:      ; pop int; acc += int (end sub-expr)
  CLC            ; [2] for addition
  PLA            ; [4]
  ADC Acc0       ; [3] add low byte
  STA Acc0       ; [3]
  PLA            ; [4]
  ADC Acc1       ; [3] add byte 1
  STA Acc1       ; [3]
  PLA            ; [4]
  ADC Acc2       ; [3] add byte 2
  STA Acc2       ; [3]
  PLA            ; [4]
  ADC Acc3       ; [3] add high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check   (44 CYCLES)
  ;DISPATCH

ar_ipopsub:      ; pop int; acc -= int (end sub-expr)
  PLA            ; [4]
  EOR #$FF       ; [2] invert,
  SEC            ; [2] and add one
  ADC Acc0       ; [3] reverse-subtract low byte
  STA Acc0       ; [3]
  PLA            ; [4]
  EOR #$FF       ; [2] invert
  ADC Acc1       ; [5] subtract byte 1
  STA Acc1       ; [3]
  PLA            ; [4]
  EOR #$FF       ; [2] invert
  ADC Acc2       ; [5] subtract byte 2
  STA Acc2       ; [3]
  PLA            ; [4]
  EOR #$FF       ; [2] invert
  ADC Acc3       ; [5] subtract high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check
  ;DISPATCH

ar_ipoprsb:      ; pop int; acc = int - acc (reverse subtract)
  SEC            ; [2] for subtract
  PLA            ; [4]
  SBC Acc0       ; [3] subtract low byte
  STA Acc0       ; [3]
  PLA            ; [4]
  SBC Acc1       ; [3] subtract byte 1
  STA Acc1       ; [3]
  PLA            ; [4]
  SBC Acc2       ; [3] subtract byte 2
  STA Acc2       ; [3]
  PLA            ; [4]
  SBC Acc3       ; [3] subtract high byte
  STA Acc3       ; [3]
  BVS overflow   ; [2] overflow check   (44 CYCLES)
  ;DISPATCH


; @@ bas_print
; PRINT basic statement
bas_print:
  ; ...
  JSR print
  ;DISPATCH




; @@ txt_scroll - WIP
; scroll the text window by X,Y in text mode
txt_scroll:              ; uses (A,X,Y,B,C,TXTP)
  STX D                  ; [3] save delta X
  STY E                  ; [3] save delta Y
  ; set up source
  LDX WinL               ; [3] text window left
  LDY WinT               ; [3] text window top
  JSR txt_addr_xy        ; [6] calculate TXTP at old X,Y (uses A,X,Y) [40]
  LDA TXTP               ; [3]
  STA Src                ; [3]
  LDA TXTPH              ; [3]
  STA SrcH               ; [3]
  ; set up destination
  ; XX needs clipping (and adjust source when clipped...)
  CLC                    ; [2]
  LDA WinL               ; [3]
  ADC D                  ; [3] adjusted WinL
  STA D                  ; [2] save it
  TAX                    ; [2] destination X coordinate
  CLC                    ; [2]
  LDA WinT               ; [3]
  ADC E                  ; [3] adjusted WinL
  STA E                  ; [2] save it
  TAY                    ; [2] destination Y coordinate
  JSR txt_addr_xy        ; [6] calculate TXTP at new X,Y (uses A,X,Y) [40]
  LDA TXTP               ; [3]
  STA Dst                ; [3]
  LDA TXTPH              ; [3]
  STA DstH               ; [3]
  ; XX calc width and height
  JMP txt_copy


; @@ txt_copy - WIP
; XXX would be nice if caller passed in the direction, and flipped Src+Dest for bottom-up.
; copy a text rect from Src to Dest of size (B=width, C=height)
; moving up: top-to-bottom (L/R doesn't matter)    -> top-down + left-to-right   [source is greater]
; moving down: bottom-to-top (L/R doesn't matter)  -> bottom-up + right-to-left  [source is less]
; moving left: ttb-or-btt (left-to-right)          -> top-down + left-to-right   [source is greater]
; moving right: ttb-or-btt (right-to-left)         -> bottom-up + right-to-left  [source is less]
txt_copy:                ; uses (A,X,Y,B,C,Src,Dest)
  LDA C                  ; [3] number of rows
  BEQ @done              ; [2] -> no rows to scroll [+1]
  LDX B                  ; [3] number of columns
  BEQ @done              ; [2] -> no cols to scroll [+1]
; choose direction
  LDA SrcH               ; [3] get source high
  CMP DstH               ; [3] compare dest high
  BCC @bottomup          ; [2] sourceH < destH (source is less; bottom-up) [+1]
  BNE txt_copy_td        ; [2] sourceH > destH (source is greater; top-down) [+1]
; sourceH == destH
  LDA Src                ; [3] get source low
  CMP Dst                ; [3] compare dest low
  BCS txt_copy_td        ; [2] sourceL >= destL (source is greater; top-down) [+1]
@bottomup:
; flip source (start at the bottom)
  LDX C                  ; [3] number of rows
  DEX                    ; [2] minus one
  BEQ txt_copy_bu        ; [2] -> only one line to scroll, no flip [+1]
  LDA Src                ; [3] get Src low
@bu_flip_s:
  CLC                    ; [2]
  ADC #32                ; [2] advance one line
  BCC @bu_no_fsh         ; [2] -> no carry [+1]
  INC SrcH               ; [5] SrcH += 1
@bu_no_fsh:
  DEX                    ; [2] decrement rows
  BNE @bu_flip_s         ; [2] -> more lines [+1]   (rows*12)
  STA Src                ; [3] set Src low
; flip destination
  LDX C                  ; [3] number of rows
  DEX                    ; [2] minus one
  LDA Dst                ; [3] get Dest low
@bu_flip_d:
  CLC                    ; [2]
  ADC #32                ; [2] advance one line
  BCC @bu_no_fdh         ; [2] -> no carry [+1]
  INC DstH               ; [5] DestH += 1
@bu_no_fdh:
  DEX                    ; [2] decrement rows
  BNE @bu_flip_d         ; [2] -> more lines [+1]
  STA Dst                ; [3] set Dest low
  JMP txt_copy_bu        ; [3] -> copy bottom-up, right-to-left
@done:
  RTS



This costs +2 cycles and -1 byte, avoids ROR instruction:

; @@ txt_addr_xy
; calculate VRAM address for an X,Y coordinate in text mode; set TXTP
; [000000YY][YYYXXXXX]  32x24 text matrix
txt_addr_xy:     ; (uses A,X,Y) [40]
  STX TXTP       ; [3] save X [000XXXXX]
  TYA            ; [2] get Y [000YYYYY]
  ASL            ; [2] [00YYYYY0]            (10s/5b)
  ASL            ; [2] [0YYYYY00]
  ASL            ; [2] [YYYYY000]
  ASL            ; [2] [YYYY0000][C=Y4]
  ASL            ; [2] [YYY00000][C=Y3]
  ORA TXTP       ; [3] [YYYXXXXX]
  STA TXTP       ; [3] set TXTP
  TYA            ; [2] get Y [000YYYYY]
  LSR            ; [2] [0000YYYY][C=Y0]     (10s/6b)  // (20s/11b)
  LSR            ; [2] [00000YYY][C=Y1]
  LSR            ; [2] [000000YY][C=Y2]
  CLC            ; [2] must clear (C=Y2)
  ADC #$2        ; [2] add $200 base address to TXTPH
  STA TXTPH      ; [3] set TXTPH
  RTS            ; [6]




; USR: call machine code (expression)
do_usr:
  JSR do_expr_u16 ; address expr (uses A,X,Y,??? -> Acc0,1)
  LDA Acc0        ; address low
  STA Src         ;
  LDA Acc1        ; address high
  STA SrcH        ;
  LDX #2          ; param counter    [could bake param count]
@param:
  LDA (CODE),Y    ; [5] peek next byte
  CMP #OP_COMMA   ; is it ','?
  BNE @done       ; -> no comma
  INY             ; advance
  JSR do_expr_u16 ; register expr (uses A,X,Y,???)
  LDA Acc0        ; modulo 255
  STA B,X         ; set D/C/B
  DEX
  BPL @param      ; -> loop until -1 (up to 3 times)
@done:
  STY E           ; save CODE offset
  JSR @call       ; push return address
  LDY E           ; restore CODE offset
  JMP do_stmt     ; -> next stmt
@call:
  LDA B
  LDX C
  LDY D
  JSR (Src)       ; -> call machine code routine
  STA Acc0        ; result
  LDA #0
  STA Acc1
  STA Acc2
  STA AccE
  JMP do_expr     ; XX next expr op


; DISPATCH (6 bytes)
; ram_disp = $E0   ; self-modifying {JMP,Low,High} (E0-E2; 3 bytes)


BEQ tok_ret1       ; -> end of input, done


0F1D5 A9 00                       LDA #0
0F1D7 85 95                       STA C              ; length in characters
0F1E2 E6 95                       INC C              ; length += 1
0F1F1 A5 95                       LDA C              ; final length of string
(8)
0F1EB A5 A8                       LDA EmitOfs        ; current emit offset
0F1ED 18                          CLC
0F1EE E5 94                       SBC B              ; subtract start offset -> string length
(5)



; @@ tok_kw
; match a keyword in kwtab [required]
tok_kw:          ; X=ln Y=kw (uses A,Y,B,C) -> CS=found, A=OP
  STY C          ; save keyword for error case
  JSR tok_kw_o   ; uses (A,Y,B) -> CS=found
  BCC @no_kw     ; -> "Expected <kw>"
  RTS
@no_kw:
  LDY C          ; restore keyword
  JMP tok_expect_y

; @@ tok_kw_o
; match a keyword in kwtab [optional]
tok_kw_o:        ; X=ln Y=kw (uses A,Y,B) -> CS=found A=OP
  JSR skip_spc   ; X=ln (uses A)
  STX B          ; [3] save ln in case we don't match
  DEX            ; [2] set up for pre-increment
  DEY            ; [2] set up for pre-increment
@loop:
  INX            ; [2] pre-increment
  INY            ; [2] pre-increment
  LDA kwtab,Y    ; [4] get keyword char
  CMP LineBuf,X  ; [4] matches input char?
  BEQ @loop      ; [3] -> continue until not equal
  CMP #$80       ; [2] CF=(A >= $80) top-bit set
  BCS @found     ; [2] -> found match [+1]
  LDX B          ; [3] restore ln at start of kw
@found:
  RTS            ; [6] -> CS=found A=OP


; @@ tok_expect_y
; Report an error message at offset Y in the message page
tok_expect_y:     ; Y=kw-ofs[kwtab]  (uses A,B,C,D,E,X,Y,Src,Dst)
  STY E
  LDY #<msg_expecting
  JSR printmsg    ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  LDY E           ; keyword offset
  JSR printkw     ; Y=offset (uses A,Src)
  JSR newline
  JMP repl





; --- WINDOW ---

; WINDOW: set a text window
do_window:
  STY E            ; save CODE offset
  LDX #4           ; evaluate 4 arguments
  JSR args_i8      ; stack: (X,Y,W,H) <-
  TSX
  ; left
  LDA $103,X       ; X coordinate low byte
  AND #31          ; modulo 32
  STA WinL         ; set window left
  ; top
  LDA $102,X       ; Y coordinate low byte
  CMP #23          ; clamp if >23
  BCC @y_ok        ; CC < 23
  LDA #23          ; maximum 23
@y_ok
  STA WinT         ; set window top
  ; width
  SEC
  LDA #32
  SBC WinL         ; 32 - WinL (minimum 1)
  CMP $101,X       ; is (32-WinL) < W
  BCC @w_ok        ; CC < W (not enough space for W, use (32-WinL))
  LDA $101,X       ; use W
@w_ok:
  STA WinW         ; set window width
  ; height
  SEC
  LDA #24
  SBC WinT         ; 24 - WinT (minimum 1)
  CMP $100,X       ; is (24-WinT) < H
  BCC @h_ok        ; CC < H (not enough space for H, use (24-WinT))
  LDA $100,X       ; use H
@h_ok:
  STA WinH         ; set window height
  ; clean up
  PLA              ; pop X
  PLA              ; pop Y
  PLA              ; pop W
  PLA              ; pop H
  ; move cursor
  JSR txt_home     ; move cursor to (0,0) in the window (uses A,X,Y)
  LDY E            ; restore CODE offset
  JMP do_stmt


; --- COPY, FILL ---

; @@ do_copy
; copy the text screen by (X,Y)
do_copy:
  STY E            ; save CODE offset
  LDX #6           ; evaluate 6 arguments
  JSR args_i8      ; stack: (X,Y,W,H) <-
  JSR txt_copy     ; text copy from (X,Y) to (X,Y) size (W,H)
  LDY E            ; restore CODE offset
  JMP do_stmt

; @@ do_fill
; fill the text screen from (X0,Y0) to (X1,Y1) with (CH)
do_fill:
  STY E            ; save CODE offset
  LDX #4           ; evaluate 4 arguments
  JSR args_i8      ; stack: (X0,Y0,X1,Y1,W,H) <-
  JSR gfx_fill     ; -> fill rectangle (X0,Y0)-(X1,Y1)
  LDY E            ; restore CODE offset
  JMP do_stmt      ; -> next stmt






Tokenised INPUT:

0F5BE B1 B6                       LDA (CODE),Y    ; [5] get tag byte
0F5C0 C8                          INY             ; advance (tag byte)
0F5C1 0A                          ASL             ; bit 7 to carry, bit 6 to sign
0F5C2 B0 19                       BCS @input      ; -> input var ($80)
0F5C4 30 09                       BMI @strlit     ; -> string literal ($40)
0F5C6 0A                          ASL             ; bit 5 to sign
0F5C7 30 21                       BMI @nl         ; -> newline ($20)
0F5C9 20 43 FD                    JSR newline     ; always newline
0F5CC 4C 0C F5                    JMP do_stmt     ; end of input
0F5CF                           ; print a string literal ($40)
0F5CF                           @strlit:
0F5CF 20 EC F4                    JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
0F5D2 A6 B7                       LDX CODEH       ; string literal high
0F5D4 A4 B6                       LDY CODE        ; string literal low
0F5D6 20 EA FD                    JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
0F5D9 C8                          INY             ; +1 for length-byte -> new CODE-ofs
0F5DA 4C BE F5                    JMP @loop       ; -> continue
0F5DD                           ; input to var
0F5DD                           @input:
0F5DD 10 05                       BPL @readln     ; -> no question mark (no $40)
0F5DF A9 3F                       LDA #$3F        ; '?'
0F5E1 20 32 FD                    JSR wrchr       ; ; print '?' (uses A,X,Src,Dst,F) preserves Y
0F5E4                           @readln:
0F5E4                             ; TODO bind VAR
0F5E4                             ; TODO store str/num flag
0F5E4 20 16 FE                    JSR readline    ; read input (uses A,X,Y,B,C) -> Y=length (EQ if zero)
0F5E7                             ; TODO parse number
0F5E7                             ; TODO set var
0F5E7 4C BE F5                    JMP @loop       ; -> continue
0F5EA                           @nl
0F5EA 20 43 FD                    JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
0F5ED 4C BE F5                    JMP @loop       ; -> continue
0F5F0
/50
can spend 28 tokenising


Untokenised INPUT:

0F5BE                           do_input:
0F5BE A9 00                       LDA #0
0F5C0 85 95                       STA C
0F5C2                           @loop:
0F5C2 B1 B6                       LDA (CODE),Y    ; [5] get next byte
0F5C4 F0 24                       BEQ @endln      ; -> end of statement
0F5C6 C9 A8                       CMP #OP_STR     ; literal string?
0F5C8 F0 2C                       BEQ @strlit     ; -> string literal
0F5CA C9 2C                       CMP #$2C        ; ',' comma?
0F5CC F0 22                       BEQ @comma      ; -> comma
0F5CE C9 27                       CMP #$27        ; single-quote?
0F5D0 F0 33                       BEQ @nl         ; -> newline
0F5D2 C9 3A                       CMP #$3A        ; ':' colon?
0F5D4 F0 13                       BEQ @end        ; -> end of statement
0F5D6 C9 3A                       CMP #$3A        ; ';' semicolon?
0F5D8 F0 27                       BEQ @skip       ; -> ignore
0F5DA                           ; input to var
0F5DA A6 95                       LDX C
0F5DC F0 05                       BEQ @readln
0F5DE A9 3F                       LDA #$3F        ; '?'
0F5E0 20 32 FD                    JSR wrchr       ; print '?' (uses A,X,Src,Dst,F) preserves Y
0F5E3                           @readln:
0F5E3                             ; TODO bind VAR
0F5E3                             ; TODO store str/num flag
0F5E3 20 16 FE                    JSR readline    ; read input (uses A,X,Y,B,C) -> Y=length (EQ if zero)
0F5E6                             ; TODO parse number
0F5E6                             ; TODO set var
0F5E6 4C BE F5                    JMP do_input    ; -> continue (reset C)
0F5E9                           @end:
0F5E9 C8                          INY             ; ':'
0F5EA                           @endln:
0F5EA 20 43 FD                    JSR newline     ; always newline
0F5ED 4C 0C F5                    JMP do_stmt     ; end of input
0F5F0                           @comma:
0F5F0 C8                          INY             ; ','
0F5F1 E6 95                       INC C           ; C=1
0F5F3 4C C2 F5                    JMP @loop       ; -> continue (keep C)
0F5F6                           ; print a string literal ($40)
0F5F6                           @strlit:
0F5F6 C8                          INY             ; OP_STR
0F5F7 20 EC F4                    JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
0F5FA A6 B7                       LDX CODEH       ; string literal high
0F5FC A4 B6                       LDY CODE        ; string literal low
0F5FE 20 EA FD                    JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
0F601                           @skip:
0F601 C8                          INY             ; +1 for length-byte -> new CODE-ofs
0F602 4C BE F5                    JMP do_input    ; -> continue (reset C)
0F605                           @nl
0F605 C8                          INY             ; "'"
0F606 20 43 FD                    JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
0F609 4C BE F5                    JMP do_input    ; -> continue (reset C)
0F60C
/78 (+28)


Tokenized PRINT:

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
  JSR num_print   ; print a number on the stack [TODO: currently Acc]
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



Untokenised PRINT:

0F60F                           do_print:
0F60F                           @loop:
0F60F A9 00                       LDA #0
0F611 85 95                       STA C           ; clear sep
0F613                           @fromsep:
0F613 B1 B6                       LDA (CODE),Y    ; [5] get tag byte
0F615 F0 4B                       BEQ @endb       ; -> end of statement
0F617 C8                          INY             ; advance
0F618 C9 A8                       CMP #OP_STR     ; is it a string literal?
0F61A F0 26                       BEQ @strlit     ; -> print string literal
0F61C C9 3B                       CMP #$3B        ; is it ';'
0F61E F0 30                       BEQ @semi       ; -> semicolon
0F620 C9 2C                       CMP #$2C        ; is it ','
0F622 F0 30                       BEQ @comma      ; -> next print zone
0F624 C9 27                       CMP #$27        ; is it "'"
0F626 F0 34                       BEQ @nl         ; -> new line
0F628 C9 3A                       CMP #$3A        ; ':' colon?
0F62A F0 37                       BEQ @end        ; -> end of statement
0F62C                           ; num/str expression
0F62C 20 94 F7                    JSR do_expr     ; evaluate expression (to stack)
0F62F 68                          PLA             ; type
0F630 D0 06                       BNE @str        ; -> string result
0F632 20 73 F3                    JSR num_print   ; print a number on the stack [TODO: currently Acc]
0F635 4C 0F F6                    JMP @loop       ; -> continue
0F638                           @str:
0F638 68                          PLA
0F639 A8                          TAY             ; string addr low
0F63A 68                          PLA
0F63B AA                          TAX             ; string addr high
0F63C 20 EA FD                    JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
0F63F 4C 0F F6                    JMP @loop       ; -> continue
0F642                           ; print a string literal
0F642                           @strlit:
0F642 20 EC F4                    JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
0F645 A6 B7                       LDX CODEH       ; string literal high
0F647 A4 B6                       LDY CODE        ; string literal low
0F649 20 EA FD                    JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
0F64C C8                          INY             ; +1 for length-byte -> new CODE-ofs
0F64D 4C 0F F6                    JMP @loop       ; -> continue
0F650                           ; track semicolon
0F650                           @semi:
0F650 85 95                       STA C           ; save ';' sep
0F652 D0 BF                       BNE @fromsep    ; -> continue
0F654                           ; tab to next field
0F654                           @comma:
0F654 A9 09                       LDA #9          ; tab: advance to next print zone (4 coumns x 8 spaces)
0F656 20 A7 FD                    JSR wrctl       ; print $09 tab (uses A,X,Src,Dst,F) preserves Y
0F659 4C 0F F6                    JMP @loop       ; -> continue
0F65C                           @nl:
0F65C 20 43 FD                    JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
0F65F 4C 0F F6                    JMP @loop       ; -> continue
0F662                           @endb:
0F662 C8                          INY             ; advance $00
0F663                           @end:
0F663 A5 95                       LDA C           ; get last sep
0F665 D0 03                       BNE @exit       ; -> exit without newline
0F667 20 43 FD                    JSR newline     ; newline at end of print
0F66A                           @exit:
0F66A 4C 0C F5                    JMP do_stmt     ; end of print (non-zero)
0F66D
/94

Untokenised PRINT:

do_print:
@loop:
  LDA #0
  STA C           ; clear sep
@fromsep:
  LDA (CODE),Y    ; [5] get tag byte
  BEQ @endb       ; -> end of statement
  INY             ; advance
  CMP #OP_STR     ; is it a string literal?
  BEQ @strlit     ; -> print string literal
  CMP #$3B        ; is it ';'
  BEQ @semi       ; -> semicolon
  CMP #$2C        ; is it ','
  BEQ @comma      ; -> next print zone
  CMP #$27        ; is it "'"
  BEQ @nl         ; -> new line
  CMP #$3A        ; ':' colon?
  BEQ @end        ; -> end of statement
; num/str expression
  JSR do_expr     ; evaluate expression (to stack)
  PLA             ; type
  BNE @str        ; -> string result
  JSR num_print   ; print a number on the stack [TODO: currently Acc]
  JMP @loop       ; -> continue
@str:
  PLA
  TAY             ; string addr low
  PLA
  TAX             ; string addr high
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  JMP @loop       ; -> continue
; print a string literal
@strlit:
  JSR code_add_y  ; advance CODE by Y so we can pass CODE [TODO meh]
  LDX CODEH       ; string literal high
  LDY CODE        ; string literal low
  JSR print       ; print it, X=high Y=low -> Y = strlen (uses A,B,X,Y,Term,Src,Dst)
  INY             ; +1 for length-byte -> new CODE-ofs
  JMP @loop       ; -> continue
; track semicolon
@semi:
  STA C           ; save ';' sep
  BNE @fromsep    ; -> continue
; tab to next field
@comma:
  LDA #9          ; tab: advance to next print zone (4 coumns x 8 spaces)
  JSR wrctl       ; print $09 tab (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue
@nl:
  JSR newline     ; write newline (uses A,X,Src,Dst,F) preserves Y
  JMP @loop       ; -> continue
@endb:
  INY             ; advance $00
@end:
  LDA C           ; get last sep
  BNE @exit       ; -> exit without newline
  JSR newline     ; newline at end of print
@exit:
  JMP do_stmt     ; end of print (non-zero)




; ------------------------------------------------------------------------------
; BASIC Tokenizer (pre-SYNTAX)
;
; X = current source offset in LineBuf (persistent)

; @@ tok_eol:
; end of line reached, do whatever
tok_eol:
  RTS

; @@ miss_quo
; report a missing quote
miss_quo:
  LDA #$22           ; closing quote '"'
  JMP err_expect

; @@ tok_str
; tokenize a string
tok_str:
  LDA #OP_STR
  JSR tok_emit       ; opcode (uses Y) -> preserves A,X
  JSR tok_emit       ; length placeholder (uses Y) -> preserves A,X
  STY B              ; save offset of length byte (Y from tok_emit!)    [zero; each emit is +1]
  INX                ; consume open '"'
@str_lp:
  LDA LineBuf,X      ; next input char
  BEQ miss_quo       ; -> end of line; missing quote
  CMP #$22           ; '"'
  BEQ @str_quo       ; -> maybe end of string
@str_out:
  INX                ; consume input
  JSR tok_emit       ; emit the character (uses Y) -> preserves A,X
  BPL @str_lp        ; -> always (MI on overrun)
@str_quo:
  INX                ; consume closing '"'
  LDA LineBuf,X      ; next input char
  CMP #$22           ; is it also '"' (double-quote)
  BEQ @str_out       ; -> include this one in the string
; end of string
  LDA EmitOfs        ; current emit offset
  CLC
  SBC B              ; subtract start offset -> string length
  LDY B              ; address of length placeholder
  STA LineBuf,Y      ; patch in string length
  JMP tok_exprs      ; -> expect more

tok_oper:
  TYA                ; operator index {27..} too much mem, do a tab_sym matcher?
  CLC                ; 
  ADC #$10           ; $10 - $1A
  CMP #OP_GT         ; is it >= OP_GT
  BCS @tok_gt        ; choose OP_GT, OP_GE
  CMP #OP_NE         ; is it >= OP_LT
  BCS @tok_lt        ; choose OP_NE, OP_LT, OP_LE
  JMP tok_emit       ; -> emit token
@tok_gt:
@tok_lt:
  LDA LineBuf,X      ; next input char
  CMP #$3E           ; is it '>' for '<>' ?
  BEQ @tok_ne
  CMP #$3D           ; is it '=' for '<='?
  BEQ @tok_le
  ; TODO etc ..      ; NOT FINISHED
@tok_ne:
@tok_le:
  LDY #<msg_syntax
  JMP report_err


; @@ tokenize
; tokenize BASIC statements (in-place in LineBuf)
tokenize:            ; X=ln-ofs
  DEX                ; set up for pre-increment
tok_stmts:
  INX                ; pre-increment (for ':' BEQ)
  JSR skip_spc       ; X=ln-ofs (uses A) -> A=next-char
  JSR is_alpha       ; X=ln-ofs (uses A) -> A=AtoZ-index CC=alphabetic
  BCS tok_syn        ; -> no STMT or VAR
  ; search for a matching statement keyword
  TAY                ; A-Z as index (0-25)
  LDA stmt_idx,Y     ; offset in stmt_page (A-Z)
  LDY #>stmt_page    ; stmt keyword table
  JSR scan_kw_idx    ; X=ln-ofs A,Y=table -> CF=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCC tok_var        ; -> no match, must be VAR
  JSR tok_emit       ; output token with top-bit set (uses Y) -> preserves A,X
; parse remaining tokens up to EOL or ':'
tok_exprs:
  JSR skip_spc       ; X=ln-ofs (uses A) -> A=next-char
  CMP #0             ; end of input?
  BEQ tok_eol        ; -> end of input, done
  CMP #$22           ; open quote '"'
  BEQ tok_str        ; -> tokenize a string
  CMP #$3A           ; colon ':'
  BEQ tok_stmts      ; -> another stmt
; is it an operator?
  LDY #0             ; oper_tab index {12+10=22}
@oper_lp:
  CMP oper_tab,Y     ; matches next operator?
  BEQ tok_oper       ; -> emit operator ($10+Y)
  INY                ; skip operator
  CPY #oper_tab_sz   ; done?
  BNE @oper_lp       ; -> next operator
; is it a name?
  JSR is_alpha       ; X=ln-ofs (uses A) -> A=AtoZ-index CC=alphabetic
  BCC tok_fn_var     ; -> keyword/variable (A=AtoZ-index)
; is it a number?
  LDA LineBuf,X      ; next input char
  SEC                ; for subtract
  SBC #48            ; make '0' be 0
  CMP #10            ; 10 digits (CS if >= 10)
  BCC tok_number     ; -> integer or float
; report syntax error
tok_syn:
  LDY #<msg_syntax
  JMP report_err

; recognise and emit a varaible name (X at 1st letter)
tok_var:
  LDA LineBuf,X      ; reload 1st var-name byte
@var_lp:
  INX                ; consume var-name byte
  JSR tok_emit       ; output the character (uses Y) -> preserves A,X
  LDA LineBuf,X      ; next var-name byte
  TAY                ; save original char
  AND #$DF           ; lower -> upper (clear bit 5)
  SEC                ; for subtract
  SBC #65            ; make 'A' be 0
  CMP #26            ; 26 letters (CS if >= 26)
  TYA                ; restore original char
  BCC @var_lp        ; -> output and continue
  JMP tok_exprs      ; -> expect more

; parse function names and context-keywords (A=AtoZ-index)
tok_fn_var:          ; is alpha...
  TAY                ; A-Z as index (0-25)
  LDA expr_idx,Y     ; offset in expr_page (A-Z)
  LDY #>expr_page    ; expr keyword table
  JSR scan_kw_idx    ; X=ln-ofs A,Y=table -> CF=found, X=ln-ofs, A=hi-byte (uses A,X,Y,B,C,D,Src)
  BCC tok_var        ; -> no match, must be VAR
  JSR tok_emit       ; output token (kw or fn) (uses Y) -> preserves A,X
  JMP tok_exprs      ; -> expect more

; parse a number
tok_number:
  JSR num_val        ; from LineBuf,X -> X, Acc, CS=overflow (uses A,X,Y,Term)
  BCS err_overflow   ; -> unsigned overflow
  ; XXX output the number
  JMP tok_exprs      ; -> expect more

err_overflow:
  LDY #<msg_overflow
  JMP report_err


; @@ skip_spc
; skip spaces in the input buffer [NO TEXT-OUT]
skip_spc:        ; X=ln-ofs -> X (uses A,X)
  LDA LineBuf,X  ; [4] next input char
  INX            ; [2] advance (assume match)
  CMP #32        ; [2] was it space?
  BEQ skip_spc   ; [2] -> loop [+1]
  DEX            ; [2] undo advance (didn't match)
  RTS            ; [6] return X=ln-ofs, A=next-char [12+6=18]

; @@ is_alpha
is_alpha:        ; X=input-ofs (uses A) -> CC=alphabetic
  LDA LineBuf,X  ; [4] next input char
  AND #$DF       ; [2] lower -> upper (clear bit 5) detect alpha char
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CS if >= 26)
tok_ret1:
  RTS            ; [6] return A=alphabet-index CC=alphabetic [12+6=18]

; @@ tok_emit
; Emit an opcode at CODE and advance CODE.
tok_emit:            ; uses Y; preserves A,X -> PL=ok  [19]
  LDY EmitOfs        ; [3] get output offset           [MZ]
  STA LineBuf,Y      ; [5] write opcode                []
  INC EmitOfs        ; [5] advance output offset       [NZ]
  RTS                ; [6] M=0 (PL) unless overrun

; @@ tok_num_o
; tokenize and emit a number
tok_num_o:       ; CS=found
  JSR num_val    ; from LineBuf,X -> Acc,X,NE=found (uses A,Y,B,C,Term)
  BEQ tok_syn    ; -> not a number
  LDA Acc2
  BMI @neg       ; -> handle negative case
  BNE @int4
  LDA Acc1
  BNE @int2
@int1:
  LDA #OP_INT2
  JSR tok_emit   ; write OP_INT2
  BNE @wr0
@int2:
  LDA #OP_INT3
  JSR tok_emit   ; write OP_INT3
  BNE @wr1
@int4:
  LDA #OP_INT4
  JSR tok_emit   ; write OP_INT4
  LDA AccE       ; XXX finish this
  JSR tok_emit
  LDA Acc2
  JSR tok_emit
@wr1:
  LDA Acc1
  JSR tok_emit
@wr0:
  LDA Acc0
  JSR tok_emit
  SEC
  RTS
@neg:            ; A=Acc3
  CMP #$FF
  BNE @int4      ; -> not FF, need 0,1,2,3
  ; Acc2 is FF
  LDA Acc1
  BPL @int4      ; -> not negative, need extra sign byte
  CMP #$FF
  BNE @int2      ; -> not FF, need 0,1
  ; Acc1 is FF
  LDA Acc0
  BPL @int2      ; -> not negative, need extra sign byte
  BMI @int1      ; -> negative, single byte

; @@ err_expect
; Report an "Expecting [char]" error
err_expect:       ; A = expected character (uses A,B,C,D,E,X,Y,Src,Dst)
  STA E           ; save char
  LDY #<msg_expecting
  JSR printmsg    ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  LDA E           ; restore char
  JSR wrchr       ; uses A,X
  JSR newline     ; uses A,X
  JMP repl




; Literal -> Term
; NumVar -> Term
; PopExpr -> Term

; @@ num_push
; push Acc to the stack (start of subexpr)
num_push:
  LDA Acc3       ; [3]
  PHA            ; [3]
  LDA Acc2       ; [3]
  PHA            ; [3]
  LDA Acc1       ; [3]
  PHA            ; [3]
  LDA Acc0       ; [3]
  PHA            ; [3]
  RTS            ; [6] // 30    (or just use num_add_stack // 60 always?)

; @@ num_pop
; push Acc to the stack (start of subexpr)
num_pop:
  PLA            ; [4]
  LDA Term0      ; [3]
  PLA            ; [4]
  LDA Term1      ; [3]
  PLA            ; [4]
  LDA Term2      ; [3]
  PLA            ; [4]
  LDA Term3      ; [3]
  RTS            ; [6] // 34

; @@ num_add
; add 32-bit numbers in Acc and Term
num_add:
  TSX            ; [2] get SP
  LDA Term3      ; [3] Term3
  ORA Acc3       ; [3] Acc3
  BNE @fpadd     ; [2] -> floating point add
  CLC            ; [2] no carry in
  LDA Acc0       ; [3] get Acc0
  ADC Term0      ; [3] add Term0
  STA Acc0       ; [3] update Acc0
  LDA Acc1       ; [3] get Acc1
  ADC Term1      ; [3] add Term1
  STA Acc1       ; [3] update Acc1
  LDA Acc2       ; [3] get Acc2
  ADC Term2      ; [3] add Term2
  STA Acc2       ; [3] update Acc2
@fpadd:          ; XX fp
  RTS            ; [6] // 45

; @@ num_popadd
; add 32-bit number on the stack to Acc (pushed BE->LE)
; 100:Top0 101:Top1 102:Top2 103:Top3
num_popadd:
  TSX            ; [2] get SP
  LDA $103,X     ; [4] Top3
  ORA Acc3       ; [3] Acc3
  BNE @fpadd     ; [2] -> floating point add
  CLC            ; [2] no carry in
  PLA            ; [4] Top0  SP++
  ADC Acc0       ; [3] add to Acc0
  STA Acc0       ; [3] update Acc0
  PLA            ; [4] Top1  SP++
  ADC Acc1       ; [3] add to Acc1
  STA Acc1       ; [3] update Acc1
  PLA            ; [4] Top2  SP++
  ADC Acc2       ; [3] add to Acc2
  STA Acc2       ; [3] update Acc2
  PLA            ; [4] Top3  (zero for int)
@fpadd:          ; XX fp
  RTS            ; [6] // 53

; @@ num_popsub
; subtract 32-bit number on the stack from Acc (pushed BE->LE)
; 100:Top0 101:Top1 102:Top2 103:Top3
num_popsub:
  TSX            ; [2] get SP
  LDA $103,X     ; [4] Top3
  ORA Acc3       ; [3] Acc3
  BNE @fpsub     ; [2] -> floating point subtract
  SEC            ; [2] add 1
  PLA            ; [4] Top0  SP++
  EOR $FF        ; [2] invert Top0
  ADC Acc0       ; [3] subtract from Acc0
  STA Acc0       ; [3] update Acc0
  PLA            ; [4] Top1  SP++
  EOR $FF        ; [2] invert Top1
  ADC Acc1       ; [3] subtract from Acc1
  STA Acc1       ; [3] update Acc1
  PLA            ; [4] Top2  SP++
  EOR $FF        ; [2] invert Top2 (to subtract)
  ADC Acc2       ; [3] subtract from Acc2
  STA Acc2       ; [3] update Acc2
  PLA            ; [4] Top3  (zero for int)
@fpsub:          ; XX fp
  RTS            ; [6] // 59


; --- PROC ---

; DEFPROC: define procedure
do_defproc:
  JMP do_stmt     ; -> next stmt

; PROC: call PROC <name>
do_proc:
  LDA #VT_PROC    ; variable tag
  JSR find_var    ; PROCs are indexed as vars (report not found)
  ;
  JMP do_stmt

; LOCAL: expect VAR
;        verify inside a PROC (control stack)
;        do the thing
do_local:
  JMP do_stmt





---- 1st

messages:    ; must be within one page for Y indexing
msg_err:
  DB 13, "ERR "
msg_syn:  DB "SYN"
msg_div:  DB "DIV"
msg_ovf:  DB "OVF"
msg_rng:  DB "RNG"
msg_dat:  DB "DAT"
msg_var:  DB "VAR"
msg_typ:  DB "TYP"
msg_esc:  DB "ESC"

; Current: 52 code + 29 data = 81  no syn_expect_y

; @@ report_err
; Report an error and return to BASIC repl.
report_err:       ; A = msg address low (18b+ESC)
  PHA             ; save msg offset
  LDA #0          ; ptr low
  LDY #5          ; length = 5
  JSR report_msg  ; XA=ptr, Y=len -> X=0, Y=len (uses A,X,Y,B,Ptr,Src,Dst)
  PLA             ; msg offset (saved)
  LDY #3          ; length = 3
  JSR report_msg  ; XA=ptr, Y=len -> X=0, Y=len (uses A,X,Y,B,Ptr,Src,Dst)
  JSR newline     ; (uses A,X,Src,Dst,F) preserves Y
@wait:            ; wait for Escape to be released
  LDA ModKeys     ; check key state
  BMI @wait       ; -> Escape still down
  JMP repl

report_msg:
  LDX #>messages  ; ptr high
  JMP print_xa    ; XA=ptr, Y=len -> X=0, Y=len (uses A,X,Y,B,Ptr,Src,Dst)

; @@ err_expect
; Report "ERR SYN [char]"
err_expect:       ; A = expected character
  PHA             ; save char
  LDA #<msg_syn
  LDY #3          ; length = 3
  JSR report_msg  ; Y=low (uses A,B,C,D,X,Y,Src,Dst)
  LDA #32
  JSR wrchr       ; uses A,X
  PLA             ; restore char
  JSR wrchr       ; uses A,X
  JSR newline     ; uses A,X
  JMP repl



---- 2nd

messages:    ; must be within one page for Y indexing
msg_err:  DB 13,"ERR ",$81  ; ($81 print next word on stack)
msg_syn:  DB "SYN",$80
msg_mis:  DB "SYN ",$C0     ; ($C0 print char on stack)
msg_kwx:  DB "SYN ",$81     ; ($81 print next word on stack)
msg_div:  DB "DIV",$80
msg_ovf:  DB "OVF",$80
msg_rng:  DB "RNG",$80
msg_dat:  DB "DAT",$80
msg_var:  DB "VAR",$80
msg_typ:  DB "TYP",$80
msg_esc:  DB "ESC",$80

; Current: 54 code + 29 data = 83  no syn_expect_y
; New: 42 code + 48 data - 12 syn_expect_x = 78

; @@ report_err
; Report an error and return to BASIC repl.
report_err:       ; A = msg address low (13b)
  PHA             ; save A                            (1)
@start:
  LDY #0          ; print "ERR "                      (2)
@loop:
  LDA messages,Y  ; get next char                     (3)
  BMI @special    ; -> special decode (>= $80)        (2)
@wrchr:
  JSR wrchr       ; print it (uses A,X)               (3)
@cont:
  INY             ; advance                           (1)
  BPL @loop       ; -> always                         (2)
@special:
  ASL             ;                                   (1)
  BEQ @done       ; -> finished ($80)                 (2)
  BMI @char       ; -> print char on stack ($C0)      (2)
  PLA             ; print next msg (> $80)            (1)
  TAY             ; as msg offset                     (1)
  BNE @loop       ; -> print msg                      (2)
@char:            ; print char on stack ($C0)
  PLA             ;                                   (1)
  JSR wrchr       ; print it (uses A,X)               (3)
@done:
  JSR newline     ; (uses A,X,Src,Dst,F) preserves Y  (3)
@wait:            ; wait for Escape to be released (debounce)
  LDA ModKeys     ; check key state                   (2)
  BMI @wait       ; -> Escape still down              (2)
  JMP repl        ;                                   (3)

; @@ err_expect
; Report "ERR SYN [char]"
err_expect:       ; A = expected character (12b)
  PHA             ; save [char]                       (1)
  LDA #<msg_mis   ; ptr low                           (2)
  BNE report_err  ; -> report it                      (2)


; report missing keyword
syn_expect_x:    ; A=kwofs[kwtab]  (17b)                             [USED 1x]
;  STX E          ; from syn_kwo                 (-1)
  PHA             ; push kwofs
  LDA #<msg_kwx   ; kw msg
  JMP report_err  ; A=msg
;  LDX E          ; keyword offset               (-2)
;  JSR printkw    ; X=offset (uses A,Src)        (-3)
;  JSR newline                                   (-3)
;  JMP repl                                      (-3)



---- 3rd

messages:    ; must be within one page for Y indexing
msg_err:  DB 13,"ERR ",$80  ; ($81 print next word on stack)
msg_syn:  DB "SYN",$80
msg_syns: DB "SYN ",$80     ; ($C0 print char on stack)
msg_div:  DB "DIV",$80
msg_ovf:  DB "OVF",$80
msg_rng:  DB "RNG",$80
msg_dat:  DB "DAT",$80
msg_var:  DB "VAR",$80
msg_typ:  DB "TYP",$80
msg_esc:  DB "ESC",$80


; Current: 54 code + 29 data = 83  no syn_expect_y
; New: 42 code + 48 data - 12 syn_expect_x = 78
; NewX3: 50 code + 43 data - (12+3) syn_expect_x = 78

; @@ report_err
; Report an error and return to BASIC repl.
report_err:
  JSR report_msg  ; print it                          (3)
report_done:
  JSR newline     ;                                   (3)
@wait:            ; wait for Escape to be released (debounce)
  LDA ModKeys     ; check key state                   (2)
  BMI @wait       ; -> Escape still down              (2)
  JMP repl        ;       

report_kw:
  PHA             ; push keyword                      (1)
  LDA #<msg_syns  ; "SYN "                            (2)
  JSR report_msg  ; print "ERR SYN "                  (3)
  PLA             ; pop keyword                       (1)
  JSR report_one  ; print KW
  BMI report_done ; -> done

report_msg:
  PHA             ; push msg                          (1)
  LDA #0          ; print "ERR "                      (2)
  JSR report_one  ;                                   (3)
  PLA             ; pop msg                           (1)
  ; fall through
report_one:
  LDX #>messages
  JMP print_xap   ; print XA with len=(XA)

; @@ err_expect
; Report "ERR SYN [char]"
err_expect:       ; A = expected character (12b)
  PHA             ; save [char]                       (1)
  LDA #<msg_syns  ; ptr low                           (2)
  JSR report_msg  ; -> report it                      (3)
  PLA             ; pop [char]                        (1)
  JSR wrchr       ; -> print it                       (3)
  JMP report_done ;                                   (3)


; report missing keyword
syn_expect_x:    ; A=kwofs[kwtab]  (17b)                             [USED 1x]
;  STX E          ; from syn_kwo                 (-1)
;  PHA             ; push kwofs            (-1)
;  LDA #<msg_syns  ; kw msg                (-2)
  JMP report_kw   ; A=msg
;  LDX E          ; keyword offset               (-2)
;  JSR printkw    ; X=offset (uses A,Src)        (-3)
;  JSR newline                                   (-3)
;  JMP repl                                      (-3)






TOKENISING


; @@ tok_num_o
; tokenize and emit a number
tok_num_o:       ; CS=found
  JSR num_val    ; from LineBuf,X -> Acc,X,NE=found (uses A,Y,B,C,Term)
  BEQ tok_syn    ; -> not a number
  LDA Acc2
  BMI @neg       ; -> handle negative case
  BNE @int4
  LDA Acc1
  BNE @int2
@int1:
  LDA #OP_INT2
  JSR tok_emit   ; write OP_INT2 (uses X=0; preserves A,Y; sets NE)
  BNE @wr0
@int2:
  LDA #OP_INT3
  JSR tok_emit   ; write OP_INT3 (uses X=0; preserves A,Y; sets NE)
  BNE @wr1
@int4:
  LDA #OP_INT4
  JSR tok_emit   ; write OP_INT4 (uses X=0; preserves A,Y; sets NE)
  LDA AccE       ; XXX finish this
  JSR tok_emit   ; (uses X=0; preserves A,Y; sets NE)
  LDA Acc2
  JSR tok_emit   ; (uses X=0; preserves A,Y; sets NE)
@wr1:
  LDA Acc1
  JSR tok_emit   ; (uses X=0; preserves A,Y; sets NE)
@wr0:
  LDA Acc0
  JSR tok_emit   ; (uses X=0; preserves A,Y; sets NE)
  SEC
  RTS
@neg:            ; A=Acc3
  CMP #$FF
  BNE @int4      ; -> not FF, need 0,1,2,3
  ; Acc2 is FF
  LDA Acc1
  BPL @int4      ; -> not negative, need extra sign byte
  CMP #$FF
  BNE @int2      ; -> not FF, need 0,1
  ; Acc1 is FF
  LDA Acc0
  BPL @int2      ; -> not negative, need extra sign byte
  BMI @int1      ; -> negative, single byte


; @@ miss_quo
; report a missing quote
miss_quo:
  LDA #$22           ; closing quote '"'
  JMP err_expect

; @@ tok_str
; tokenize a string
tok_str:
  LDA #OP_STRL
  JSR tok_emit       ; opcode (uses X=0; preserves A,Y; sets NE)
  JSR tok_emit_pl    ; length placeholder (uses X=0; preserves A,Y; sets NE) -> Dst
  INY                ; consume open '"'
@str_lp:
  LDA (Ptr),Y        ; next input char
  BEQ miss_quo       ; -> end of line; missing quote
  CMP #$22           ; '"'
  BEQ @str_quo       ; -> maybe end of string
@str_out:
  INY                ; consume input
  JSR tok_emit       ; emit the character (uses X=0; preserves A,Y; sets NE)
  BNE @str_lp        ; -> always
@str_quo:
  INY                ; consume closing '"'
  LDA (Ptr),Y        ; next input char
  CMP #$22           ; is it also '"' (double-quote)
  BEQ @str_out       ; -> include this one in the string
; end of string
  LDA Emit           ; Emit offset (within page)
  CLC
  SBC Dst            ; subtract patch offset -> string length
  STA (Dst,X)        ; patch in string length (X=0 from tok_emit)
  JMP tok_exprs      ; -> expect more


; parse remaining tokens up to EOL or ':'
tok_exprs:
  JSR skip_spc       ; Y=ofs -> Y, A=next-char (uses X)
  CMP #0             ; end of input?
  BEQ tok_eol        ; -> end of input, done
  CMP #$22           ; open quote '"'
  BEQ tok_str        ; -> tokenize a string
  CMP #$3A           ; colon ':'
  BEQ tok_stmts      ; -> another stmt
; is it an operator?
  LDX #0             ; oper_tab index {12+10=22}
@oper_lp:
  CMP oper_tab,X     ; matches next operator?
;  BEQ tok_oper       ; -> emit operator ($10+Y)
  BEQ tok_syn   ; XXX
  INX                ; next operator
  CPX #oper_tab_sz   ; done?
  BNE @oper_lp       ; -> next operator
; is it a name?
  JSR is_alpha       ; Y=ofs -> Y, A=az-index, CC=alpha
  BCC tok_fn_var     ; -> keyword/variable (A=az-index)
; is it a number?
  LDA (Src),Y        ; next input char
  SEC                ; for subtract
  SBC #48            ; make '0' be 0
  CMP #10            ; 10 digits (CS if >= 10)
  BCC tok_number     ; -> integer or float



; parse function names and context-keywords (A=AtoZ-index)
tok_fn_var:          ; A=az-index
  TAX                ; as index (0-25)
  LDA expr_idx,X     ; offset in expr_page (A-Z)
  LDX #>expr_page    ; expr keyword table
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,Y,B,C,D,Src)
  BCC tok_var        ; -> no match, must be VAR
  JSR tok_emit       ; output token (kw or fn) (uses X=0; preserves A,Y; sets NE)
  JMP tok_exprs      ; -> expect more

; parse a number
tok_number:
  JSR num_val        ; from (Ptr),Y -> Y, Acc, CS=overflow (uses A,X,Y,Term)
  BCS err_overflow   ; -> unsigned overflow
  ; XXX output the number
  JMP tok_exprs      ; -> expect more




-------- AUTO --------

cmd_auto:
  LDA #10            ; [2]
  STA AutoLn         ; [3] start from line 10
  STA AutoInc        ; [3] step by 10
  LDA #0             ; [2]
  STA AutoLnH        ; [3]
  JSR num_u16        ; [6] parse number at Y -> Y,Acc,NE=found (uses A,Y,B)
  BEQ @start         ; [2] -> no number [+1]
  LDA Acc0           ; [3]
  STA AutoLn         ; [3] set start line
  LDA Acc1           ; [3]
  STA AutoLnH        ; [3]
  JSR syn_comma_o    ; [24+] does ',' follow?
  BNE @start         ; [2] -> no comma
  JSR num_u16        ; [6] parse number at Y -> Y,Acc01,NE=found (uses A,Y,B)
  BEQ @start         ; [2] -> no number [+1]
  LDA Acc0           ; [3]
  STA AutoInc        ; [3]
  BEQ err_range      ; [2] -> bad step (equals zero)
  LDA Acc1           ; [3]
  BNE err_range      ; [2] -> bad step (non-zero high byte)
@start:
@loop:
  ; print the line number
  LDA #0
  STA AccE
  STA Acc2
  LDA AutoLnH
  STA Acc1
  LDA AutoLn
  STA Acc0
  JSR num_print      ; print Acc (uses A,X)
  LDA #32
  JSR wrchr          ; uses A,X
  ; read an input line
  JSR readline
  JSR newline
  ; parse and tokenise the line
  LDY #0          ; (Ptr),Y offset
  JSR tokenize    ; tokenize the line; returns CF=valid?
  ; XXX insert the tokenized line into the BASIC program
  ; increment line number
  LDA AutoInc
  CLC
  ADC AutoLn
  STA AutoLn
  BCC @loop         ; -> no carry
  INC AutoLnH
  BNE @loop         ; -> loop until wraparound
  RTS

err_range:
  LDA #<msg_rng
  JMP report_err



-------- TEXT COPY --------

; @@ txt_copy
; copy text rect from (X0,Y0) to (X1,Y1) size (W,H) on stack
txt_copy:
  RTS

; @@ txt_copy_td
; copy a text rect top-down, left-to-right (move the rect up/left)
; from (Src) to (Dest) both at top-left; Y=height, WinW=width (both non-zero)
txt_copy_td:             ; uses (A,X,Y,Src,Dest)
  STY F                  ; [3] set row counter
@td_row:
  LDX #32                ; [3] number of columns
  LDY #0                 ; [2] left-to-right column index
@td_col:
  LDA (Src),Y            ; [3] read character
  STA (Dst),Y            ; [3] write character
  INY                    ; [2] increment column index
  DEX                    ; [2] decrement column count
  BNE @td_col            ; [3] -> until X=0
; advance to next line
  CLC                    ; [2]
  LDA #32                ; [2] advance to the next line
  ADC Src                ; [3] Src += 32 (one line)
  STA Src                ; [3]
  BCC @td_no_sh          ; [2] -> no carry [+1]
  INC SrcH               ; [5] SrcH += 1
@td_no_sh:
  CLC                    ; [2]
  LDA #32                ; [2] advance to the next line
  ADC Dst                ; [3] Dest += 32 (one line)
  STA Dst                ; [3]
  BCC @td_no_dh          ; [2] -> no carry [+1]
  INC DstH               ; [5] SrcH += 1
@td_no_dh:
  DEC F                  ; [2] decrement row counter
  BNE @td_row            ; [3] until rows=0
  RTS

; @@ txt_copy_bu
; copy a text rect bottom-up, right-to-left (move the rect down/right)
; from (Src) to (Dest) both at BOTTOM-left; width=WinW height=WinH (both non-zero)
txt_copy_bu:             ; uses (A,X,Y,B,C,Src,Dest)
  LDA WinH               ; [3] number of rows
  STA B                  ; [3] row count
@bu_row:
  LDY WinW               ; [3] number of columns
  DEY                    ; [2] pre-decrement right-to-left column index
@bu_col:
  LDA (Src),Y            ; [3] read character
  STA (Dst),Y            ; [3] write character
  DEY                    ; [2] decrement column index
  BPL @bu_col            ; [3] -> until Y=-1
; advance to next line
  SEC                    ; [2]
  LDA Src                ; [3]
  SBC #32                ; [2] Src -= 32 (go up one line)
  STA Src                ; [3]
  BCS @bu_no_sh          ; [2] -> no borrow [+1]
  DEC SrcH               ; [5] SrcH -= 1
@bu_no_sh:
  SEC                    ; [2]
  LDA Dst                ; [3]
  SBC #32                ; [2] Dst -= 32 (go up one line)
  STA Dst                ; [3]
  BCC @bu_no_dh          ; [2] -> no carry [+1]
  DEC DstH               ; [5] SrcH -= 1
@bu_no_dh:
  DEC B                  ; [2] decrement row count
  BNE @bu_row            ; [3] until rows=0
  RTS














; ------------------------------------------------------------------------------
; Error Reporting

err_bounds:
  LDA #<msg_rng
  ; +++ fall through to @@ report_err +++

; @@ report_err
; Report an error and return to BASIC repl.
report_err:       ; A = msg address low
  JSR printmsg    ; Y=ptr -> 
  LDY #<msg_err
  JSR printmsgln  ; Y=ptr -> 
  JMP repl

; @@ err_expect
; Report "Expect [char]"
err_expect:       ; A = expected character
  PHA             ; save char
  LDY #<msg_exp
  JSR printmsg
  PLA             ; restore char
  JSR wrchr       ; uses A,X
  JSR newline     ; uses A,X
  JMP repl

; @@ report_bad
; Report an error and return to BASIC repl.
report_bad:       ; A = msg address low
  STY E
  LDY #<msg_bad
  JSR printmsgln  ; Y=ptr -> 
  LDY E
  JSR printmsg    ; Y=ptr -> 
  JMP repl


; ------------------------------------------------------------------------------
; BASIC Tokenizer
;
; Y = current source offset at (Ptr)
; A,X = temporaries

; @@ skip_spc
; skip spaces in the input buffer [NO TEXT-OUT]
skip_spc:        ; Y=ofs -> Y, A=next-char (uses A,X)
  LDA (Ptr),Y    ; [5] next input char
  INY            ; [2] advance (assume match)
  CMP #32        ; [2] was it space?
  BEQ skip_spc   ; [2] -> loop [+1]
  DEY            ; [2] undo advance (didn't match)
  RTS            ; [6] return Y=ofs, A=next-char [19]

; @@ is_alpha
is_alpha:        ; Y=ofs (uses A) -> Y, A=az-index, CC=alphabetic
  LDA (Ptr),Y    ; [5] next input char
  AND #$DF       ; [2] lower -> upper (clear bit 5) detect alpha char
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CS if >= 26)
tok_ret1:
  RTS            ; [6] -> A=az-index CC=alpha [19]


; @@ tok_emit_pl
; Emit a placeholder byte at (Emit) and advance (Emit).
tok_emit_pl:
  LDX EmitOfs        ; [3] save EmitOfs for patching later
  STX EmitPtch       ; [3]
  ; +++ fall through to @@ tok_emit +++

; @@ tok_emit
; Emit an opcode at (Emit) and advance (Emit).
tok_emit:            ; (uses X; preserves A,Y; sets NE)  [21]
  LDX EmitOfs        ; [2] get emit offset
  STA Emit,X         ; [5] emit token
  INC EmitOfs        ; [5] advance emit offset
  BMI err_overflow   ; [2] -> overflowed emit buffer
  RTS                ; [6]


err_overflow:
  LDA #<msg_ovf
  JMP report_err

; report syntax error
tok_syn:
  LDA #<msg_syn
  JMP report_err


;  DB "SYN"  ; 361 bytes + patch IF/ELSE + PRINT/INPUT + DEF FN + EXPRs (768 bytes?)


SYN_FLAG    = $80       ; bit 3 flag

SYN_0       = $00       ; no args
SYN_NN      = $01       ; N x <expr_n> *
SYN_DATA    = $02       ; <len><data>
SYN_CH      = $03       ; #<n> [ ',' <expr_s> ]:FLAG
SYN_LET     = $04       ; [LET] <var> = <expr>                      -> <var><expr_*>
SYN_DIM     = $05       ; DIM <var> '(' <expr> ')'                  -> <var><expr_n>
SYN_FOR     = $06       ; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>] -> <var><expr_n><expr_n><expr_n|$00>
SYN_NEXT    = $07       ; NEXT [<var>|$00]                          -> <var|$00>
SYN_IF      = $08       ; IF <expr_n> [THEN [<line>]]               -> <expr_n><len|n16>
SYN_ELSE    = $09       ; ELSE [<line>]                             -> <len>
SYN_READ    = $0A       ; READ {<var> ','}                          -> <len>{<var>}
SYN_INPUT   = $0B       ; { [,;'] "str" | <var> }                   -> <len>{<op|lit|var>}
SYN_PRINT   = $0C       ; { [,;'] "str" | <expr_n> | <expr_s> } [;] -> <len>{<op|lit|var>}
SYN_DEF     = $0D       ; 'FN' <name> '(' {<var>} ')'               -> <name><len>{<var>}


syn_tab:                         ; [30]
  DB 0                           ; OP_LN      $C0   (not used)
  DB SYN_0                       ; OP_CLS     $C1
  DB SYN_CH                      ; OP_CLOSE   $C2
  DB SYN_DATA                    ; OP_DATA    $C3
  DB SYN_DIM                     ; OP_DIM     $C4
  DB SYN_DEF                     ; OP_DEFFN   $C5
  DB SYN_ELSE                    ; OP_ELSE    $C6
  DB SYN_0                       ; OP_END     $C7
  DB SYN_FOR                     ; OP_FOR     $C8
  DB SYN_NN | (1<<4)             ; OP_GOTO    $C9
  DB SYN_NN | (1<<4)             ; OP_GOSUB   $CA
  DB SYN_IF                      ; OP_IF      $CB
  DB SYN_INPUT                   ; OP_INPUT   $CC
  DB SYN_LET                     ; OP_LET     $CD
  DB SYN_NN | (4<<4)             ; OP_LINE    $CE
  DB SYN_NN | (1<<4)             ; OP_MODE    $CF
  DB SYN_NEXT                    ; OP_NEXT    $D0
  DB SYN_NN | (2<<4)             ; OP_OPT     $D1
  DB SYN_CH | SYN_FLAG           ; OP_OPEN    $D2
  DB SYN_NN | (2<<4)             ; OP_PLOT    $D3
  DB SYN_NN | (2<<4)             ; OP_POKE    $D4
  DB SYN_PRINT                   ; OP_PRINT   $D5
  DB SYN_READ                    ; OP_READ    $D6
  DB SYN_0                       ; OP_REPEAT  $D7
  DB SYN_NN | (1<<4)             ; OP_RESTORE $D8
  DB SYN_0                       ; OP_RETURN  $D9
  DB SYN_DATA                    ; OP_REM     $DA
  DB SYN_NN | (4<<4) | SYN_FLAG  ; OP_SOUND   $DB
  DB SYN_NN | (1<<4)             ; OP_UNTIL   $DC
  DB SYN_NN | (1<<4)             ; OP_WAIT    $DD

syn_jmp:                ; [14] range-checked page offsets
  DB (syn_0 - syn_page)
  DB (syn_nn - syn_page)
  DB (syn_data - syn_page)
  DB (syn_ch - syn_page)
  DB (syn_let - syn_page)
  DB (syn_dim - syn_page)
  DB (syn_for - syn_page)
  DB (syn_next - syn_page)
  DB (syn_if - syn_page)
  DB (syn_else - syn_page)
  DB (syn_read - syn_page)
  DB (syn_input - syn_page)
  DB (syn_print - syn_page)
  DB (syn_def - syn_page)


; -------------------------------------------------------------
; $300 Syntax Recognisers
;
; Y = line-ofs
; D = syn_tab byte (syn:7-4, flag:3, count:2-0)
; E = line-len (from REPL)
; skip_spc already done

; var/expr types
TYPE_NUM   = 0
TYPE_STR   = 1
TYPE_ARR   = 2
TYPE_NUM_A = 2 ; TYPE_ARR|TYPE_NUM
TYPE_STR_A = 3 ; TYPE_ARR|TYPE_STR

ORG $F400
syn_page:

                  ; XXX OP_LETN, OP_LETS, OP_LETA opcode must be emtted here...
syn_let:          ; LET <var> '=' <expr> -> {LETn|LETs|LETa}<var><expr> (x2?)
  JSR syn_var     ; expect and emit <name>[$] -> A=type
  STA E           ; save expr type
  LDA #$3D        ; '='
  JSR syn_sym     ; expect '='
  JSR syn_exp     ; tokenize and emit expression -> A=type
  CMP E           ; same as var?
  BNE syn_type    ; -> type mismatch
  RTS

syn_0:           ; no args
  RTS

syn_nn:          ; N x <expr_n>
  LDA D          ; FnnnSSSS
  ROR            ; xFnnnSSS
  ROR            ; xxFnnnSS
  ROR            ; xxxFnnnS
  ROR            ; xxxxFnnn
  AND #7         ; up to 7 arguments
  STA D          ; num exprs
  BNE @first     ; -> no first comma (assume D>0)
@loop:
  JSR syn_comma  ; expect ','
@first:
  JSR syn_exp_n  ; tokenize and emit numeric expression
  DEC D
  BNE @loop
@done:
  RTS

syn_sound:        ; N x <expr_n> +1 or +2
  JSR syn_nn      ; tokenize first four arguments
  JSR syn_exp_no  ; tokenize and emit numeric expression (optional) -> CS=found
  BCC syn_00      ; -> no 5th argument
  JSR syn_exp_no  ; tokenize and emit numeric expression (optional) -> CS=found
  BCC syn_00      ; -> no 6th argument
  RTS

syn_00:
  LDA #0
  JMP tok_emit    ; write $00 marker (uses X=0; preserves A,Y; sets NE)

syn_data:         ; <len><data>
  JSR syn_rem_len ; get remaining length of input (uses A,B) -> A
  JSR tok_emit    ; write length (uses X=0; preserves A,Y; sets NE)
  STA B           ; length counter
@copy:
  LDA (Ptr),Y     ; next input char
  INY             ; advance input
  JSR tok_emit    ; emit code (uses X=0; preserves A,Y; sets NE)
  DEC B           ; decrement length counter
  BNE @copy       ; -> until done
  RTS

syn_ch:
  JMP syn_chan    ; expect and emit '#' <channel> -> A

syn_ch_s:
  JSR syn_chan    ; expect and emit '#' <channel> -> A
  JSR syn_comma   ; expect ','
  JSR syn_exp_s   ; tokenize and emit string expression
  RTS

syn_type:
  LDA #<msg_typ   ; "TYP ERR"
  JMP report_err  ; -> report error

syn_dim:          ; DIM <var> '(' <expr> ')' -> {DIM}<var><expr_n>
  JSR syn_var     ; expect and emit <name>[$] -> A=type
  LDA #$28        ; '('
  JSR syn_sym     ; expect '('
  JSR syn_exp_n   ; tokenize and emit numeric expression
  LDA #$29        ; ')'
  JSR syn_sym     ; expect ')'
syn_ret:
  RTS

syn_for:          ; FOR <var> '=' <expr_n> 'TO' <expr_n> ['STEP' <expr_n>] -> {FOR}<var><expr_n><expr_n><expr_n|$00>
  JSR syn_var     ; expect and emit <name>[$] -> A=type
  AND #1          ; mask off TYPE_ARR = 2
  BNE syn_type    ; -> type mismatch (must be TYPE_NUM = 0)
  LDA #$3D        ; '='
  JSR syn_sym     ; expect '='
  JSR syn_exp_n   ; tokenize and emit numeric expression (from)
  LDX #>kwt_to    ; "TO"
  JSR syn_kwo     ; match "TO"
  BCC syn_expect_y ; -> "Expected <kw>"
  JSR syn_exp_n   ; tokenize and emit numeric expression (to)
  LDX #>kwt_step  ; "STEP"
  JSR syn_kwo     ; match "STEP" -> CS=found A=OP
  BCC syn_00      ; emit $00 marker
  JMP syn_exp_n   ; tokenize and emit numeric expression (step)

syn_next:
  JSR skip_spc    ; before is_alpha
  JSR is_alpha    ; X=ln-ofs (uses A) -> CC=alphabetic
  BCS syn_00      ; emit $00 marker (no var)
  JMP syn_var     ; expect and emit <name>[$] -> A=type (XXX runtime type-check)

syn_if:            ; IF <expr_n> THEN <line>/<stmts> [ELSE..] -> {IF}<expr_n><len> | {IFLN}<expr_n><n16>
  JSR syn_exp_n    ; tokenize and emit numeric expression
  LDX #>kwt_then   ; "THEN"
  JSR syn_kwo      ; match "THEN" uses (A,Y,B) -> CS=found
  BCC syn_expect_y ; -> "Expected <kw>"
  BCC @stmts       ; -> no "THEN"
  JSR syn_u16o     ; tokenize and emit u16 -> CS=found
  BCC @stmts       ; -> no <line>
  ; XXX patch opcode = OP_IFLN
@stmts:
  ; XXX emit placeholder for length
  ; XXX set "inside IF" flag and save placeholder ofs
  RTS

syn_else:
  ; XXX check "inside IF" -> missing IF
  ; XXX patch saved length-offset: (Ofs) = X
  ; XXX reserve space for length
  ; XXX set "inside ELSE" flag and save length-offset

syn_read:
  JSR tok_emit_pl ; length placeholder (uses X=0; preserves A,Y; sets NE) -> Dst
  STX D           ; counter
@loop:
  JSR syn_var     ; expect and emit <var>[$]
  INC D           ; count vars
  JSR syn_comma_o ; comma?
  BEQ @loop       ; -> more
  DEY             ; did not consume
@done:
  LDA D           ; get length
  LDX #0          ; const X=0
  STA (Dst),X     ; patch in length over length placeholder
  RTS

syn_input:

; last print-sep is assumed to be ' (newline)
; if a [,;] print-sep appears at the end of the statement, it is used instead
syn_print:

syn_def:


; Syntax Utils

; report missing keyword
syn_expect_y:    ; Y=kw-ofs[kwtab]  (uses A,B,X,Y,Src,Dst)    [USED 1x]
  STY E
  LDY #<msg_syn  ;
  JSR printmsg   ; Y=low (uses A,B,X,Y,Src,Dst)
  LDY E          ; keyword offset
  JSR printkw    ; Y=offset (uses A,Src)
  JSR newline
  JMP repl

syn_rem_len:     ; get remaining length of input (uses A,B) -> A      [USED 1x]
  STX B          ; current ln-ofs
  LDA E          ; length of line from `repl`
  CLC
  SBC B          ; subtract start of data
  RTS

syn_comma:       ;              [USED 2x]
  LDA #$2C       ; ','
syn_sym:
  STA F
  JSR skip_spc   ; Y=ofs -> Y, A=next-char (uses A,X)
  CMP F          ; is it equal?
  BNE @expect    ; -> "Expecting <char>"
  INY            ; consume char
  RTS
@expect:
  JMP err_expect

syn_comma_o:     ;            [USED 2x]
  LDA #$2C       ; ','
syn_sym_o:
  STA F
  JSR skip_spc   ; Y=ofs -> Y, A=next-char (uses A,X)
  CMP F          ; is it equal?
  BNE @over
  INY            ; consume char if matched
@over:
  RTS

syn_chan:        ; expect and emit '#' <channel> -> A   [USED 2x]
  LDA #$23       ; '#'
  JSR syn_sym    ; expect '#'
  JSR num_u16    ; integer literal
  LDA Acc1
  BNE @range     ; -> out of range
  LDA Acc0
  CMP #4         ; is it >= 4
  BCS @range     ; -> out of range (too big)
  JMP tok_emit   ; emit 0-9 (uses X=0; preserves A,Y; sets NE)
@range:
  JMP err_range

; match a keyword in kwtab   [XXX use match_kws instead?]
syn_kwo:         ; Y=ln X=kw (uses A,Y,B) -> CS=found A=OP    [USED 3x]
  JSR skip_spc   ; 
  STY F          ; [3] save ln in case we don't match
  DEX            ; [2] set up for pre-increment
  DEY            ; [2] set up for pre-increment
@loop:
  INX            ; [2] pre-increment
  INY            ; [2] pre-increment
  LDA kwtab,X    ; [4] get keyword char
  CMP (Src),Y    ; [4] matches input char?
  BEQ @loop      ; [3] -> continue until not equal
  CMP #$80       ; [2] CF=(A >= $80) top-bit set
  BCS @found     ; [2] -> found match [+1]
  LDY F          ; [3] restore ln at start of kw
@found:
  RTS            ; [6] -> CS=found A=OP

syn_u16o:        ;          [USED 1x]
  RTS

syn_exp:         ; tokenize and emit expression -> A=type
syn_exp_no:      ; tokenize and emit numeric expression (optional)
syn_exp_n:       ; tokenize and emit numeric expression
syn_exp_s:       ; tokenize and emit string expression
syn_var:         ; expect and emit <name>[$] -> CS=str


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

oper_tab_sz = 10
oper_tab:
  DB '^'  ; OP_POW
  DB '*'  ; OP_MUL
  DB '/'  ; OP_DIV
  DB '+'  ; OP_ADD
  DB '-'  ; OP_SUB
  DB '='  ; OP_EQ
  DB '<'  ; OP_NE, OP_LT, OP_LE
  DB '<'  ; (for above)
  DB '<'  ; (for above)
  DB '>'  ; OP_GT, OP_GE




; @@ copy_fw (OLD)
; copy memory forwards (new < old)
; from (Src) to (Dest) with AX=size
copy_fw:                 ; copy forwards AX=size (uses A,X,Y,F,Src,Dest)
  STA F                  ; [3] page counter            F = 1
@page:
  LDY #0                 ; [3] page offset             Y = 0                  Y = 0     Y = FE    Y = FF
@span:
  LDA (Src),Y            ; [3] read byte               (Src),0  (Src),1       (Src),0   (Src),FE  (Src),FF
  STA (Dst),Y            ; [3] write byte              (Dst),0  (Dst),1       (Dst),0   (Dst),FE  (Dst),FF
  INY                    ; [2] increment page offset   Y = 1    Y = 2         Y = 1     Y = FF    Y = 0
  DEX                    ; [2] decrement span count    X = 1    X = 0         X = FF    X = 1     X = 0
  BNE @span              ; [3] -> until X=0            ->       EQ            ->        ->        EQ
; advance to next page
  LDX #0                 ; [2] next span count = 256                X = 0                            X = 0
  TYA                    ; [2] final Y = initial X                  Y = 2                            Y = 0
  BEQ @whole             ; [2] -> whole page step                   NE                               ->
  CLC                    ; [2]
  ADC Src                ; [3] bump Src += Y                      Src += 2
  STA Src                ; [3] 
  BCC @no_shi            ; [2]
  INC SrcH               ; [5]
@no_shi:
  TYA                    ; [2] final Y = initial X
  CLC                    ; [2]
  ADC Dst                ; [3] bump Dst += Y                      Dst += 2
  STA Dst                ; [3]
  BCC @no_dhi            ; [2]
  INC DstH               ; [5]
@no_dhi:
  JMP @page              ; [3] until pages=0                      ->
@whole:
  INC SrcH               ; [5] Src += 256                                                       Src += 256
  INC DstH               ; [5] Dst += 256                                                       Dst += 256
  DEC F                  ; [2] decrement page counter                                               F = 0
  BNE @page              ; [3] until pages=0                                                        EQ
  RTS                    ; [6]

; @@ copy_bw
; copy memory backwards (old < new) by one or more bytes
; from (Src) to (Dest) with length AX
copy_bw:                 ; uses (A,X,Y,F,Src,Dst)
  STA F                  ; [3] page count
  LDA SrcH               ; [3] Src += A * 256         Src += 256
  CLC
  ADC F
  STA SrcH
  LDA DstH               ; [3] Dst += A * 256         Dst += 256
  ADC F                  ; [2] no CLC (assume no 64K wraparound)
  STA DstH
  TXA
  BEQ @page              ; [2] -> no residual X
  INC F                  ; [5] +1 page (residual)      F = 2
@page:
  TXA                    ; [2] X = counter             X=2                         X=0       X=FF
  TAY                    ; [2] Y = offset              Y=2                         Y=0       Y=FF
@span:
  DEY                    ; [2] pre-decrement           Y=1          Y=0            Y=FF      Y=FE
  LDA (Src),Y            ; [3] read byte               (Src+256),1  (Src+256),0    (Src),FF  (Src),FE
  STA (Dst),Y            ; [3] write byte              (Dst+256),1  (Dst+256),0    (Dst),FF  (Dst),FE
  DEX                    ; [2] decrement span count    X=1          X=0            X=FF      X=FE
  BNE @span              ; [3] -> until X=0            ->           EQ             ->        ->
; advance to next page
  DEC SrcH               ; [5] Src -= 256                                 Src                   -Src
  DEC DstH               ; [5] Dst -= 256                                 Dst                   -Dst
  LDX #0                 ; [2] span count = 256                           X = 0                 X = 0
  DEC F                  ; [2] decrement page counter                     F = 1                 F = 0
  BNE @page              ; [3] until pages=0                              ->                    EQ
  RTS

@toend:                  ; advance to last page (assumes few pages) [13b -> 8b] [19s -> A*15s]
  INC SrcH               ; [5] Src += 256 (one page)
  INC DstH               ; [5] Dst += 256 (one page)
  DEY                    ; [2]
  BNE @toend             ; [2] -> more pages [+1]


do_let:          ; assign VAR = Expr (num/str)                       (57b)
  JSR find_var   ; [6] find VAR at Y=ofs -> Y, Ptr=slot, NE=str
  STY D          ; [3] save Y=ofs
  BNE @str       ; [2] -> str [+1]
  JSR eval_n     ; [6] evaluate numeric expression
  LDX ExpTop     ; [3] empty top
  LDY #0         ; [2] Var ofs
  DEX
  LDA ExprStk,X  ; [4] TermE
  STA (Ptr),Y    ; [6] write to VarE
  INY
  DEX
  LDA ExprStk,X  ; [4] Term2
  STA (Ptr),Y    ; [6] write to Var2
  INY
@scon:
  DEX
  LDA ExprStk,X  ; [4] Term1 or Str1
  STA (Ptr),Y    ; [6] write to Var1
  INY
  DEX
  LDA ExprStk,X  ; [4] Term0 or Str0
  STA (Ptr),Y    ; [6] write to Var0
  STX ExpTop     ; [3] update top
  LDY D          ; [3] save Y=ofs
  JMP do_stmt     ; -> next stmt
@str:
  JSR eval_s     ; [6] evaluate string expression
  LDX ExpTop     ; [3] empty top
  LDY #0         ; [2] Var ofs
  BEQ @scon      ; [3] -> copy str ptr to slot


; an eldrich horror..
; @@ find_var
; find VAR at Y=ofs -> Y, Ptr=slot, X=tag, report not found            (108b)
find_var:        ; (uses A,X)
  LDA (CODE),Y   ; [5] get next byte
  AND #$DF       ; [2] lower -> upper (clear bit 5)
  SEC            ; [2] for subtract
  SBC #65        ; [2] make 'A' be 0
  CMP #26        ; [2] 26 letters (CS if >= 26)
  BCS do_syn1    ; [2] -> syntax error
; copy VarPtr from VarPtrs
  ASL            ; [2] letter * 2
  TAX            ; [2] 0-50 index
  LDA VarPtrs,X  ; [4] var-list pointer low byte
  STA Ptr        ; [3] 
  INX            ; [2] next byte
  LDA VarPtrs,X  ; [4] var-list pointer high byte (zero if no VARs)
  BEQ @novar     ; [2] -> no VARs start with this letter [+1]
  STA PtrH       ; [3] 
; search var-list at Ptr
  STY C          ; [3] save Y=ofs at start of VAR
  LDX #0         ; [2] const X=0
@mlp:            ; [30] per char:
  LDA (CODE),Y   ; [5] get next Code byte    (may be $80+ for KW)
  CMP (Ptr,X)    ; [6] equals next VAR byte? (may be $80+ type-tag at end of name)
  BNE @nom       ; [2] -> end of match [+1]
  INY            ; [2] advance code-ofs (won't exceed 127)
  INC Ptr        ; [5] advance Ptr (may cross a page)
  BNE @mlp       ; [2] -> No Ptr page cross [+1]
  INC PtrH       ; [5] advance Ptr page
  BNE @mlp       ; [3] -> always (assumes no 64K wraparound)
@nom:            ; is A >= $80 (hit) or not (miss)
  BPL @missx     ; [2] -> incomplete CODE match [+1] (VAR match may be complete)
  LDA (Ptr,X)    ; [6] is Ptr,X >= $80 (hit) or not (miss)
  BPL @miss      ; [2] -> incomplete VAR match [+1]
; found a match
  TAX            ; [2] save $8x type-tag
  LDA Ptr        ; [3]
  CLC            ; [2]
  ADC #3         ; [2] Ptr += 3 [$80][NextL][NextH]
  STA Ptr        ; [3]
  BCC @nno1      ; [2] -> no page cross [+1]
  INC PtrH       ; [5] advance Ptr page
@nno1:
  RTS            ; [6] -> X=tag
@missx:          ; skip rest of VAR (may be complete)
  LDA (Ptr,X)    ; [6] is Ptr,X >= $80 (hit) or not (miss)
  BMI @next      ; [2] -> at end of VAR [+1]
@miss:           ; skip rest of VAR (we know we're not at the end yet)
  INC Ptr        ; [5] advance Ptr
  BCC @mno1      ; [2] -> no page cross [+1]
  INC PtrH       ; [5] advance Ptr page
@mno1:
  LDA (Ptr,X)    ; [6] is Ptr,X >= $80 (hit) or not (miss)
  BPL @miss      ; [2] -> skip more [+1]
@next:
  INC Ptr        ; [5] advance Ptr over [$x] byte
  BCC @mno2      ; [2] -> no page cross [+1]
  INC PtrH       ; [5] advance Ptr page
@mno2:
  LDA (Ptr,X)    ; [6] get [NextL]
  TAY            ; [2] save
  INC Ptr        ; [5] advance Ptr over [$x] byte
  BCC @mno3      ; [2] -> no page cross [+1]
  INC PtrH       ; [5] advance Ptr page
@mno3:
  LDY C          ; [3] restore Y=ofs at start of VAR (for next match)
  LDA (Ptr,X)    ; [6] get [NextH] (zero at end of var-list)
  BEQ @novar     ; [2] -> no more VARs
  STX Ptr        ; [3] set new Ptr
  STA PtrH       ; [3] set new PtrH
  BNE @mlp       ; [3] -> always (NextH cannot be zero)
@novar:          ; no matching VAR found
  LDA #<msg_var
  JMP report_err

do_syn1:
  LDA #<msg_syn
  JMP report_err




; @@ tok_patch_pl
; patch "last length placeholder" with (emit_ofs - patch_addr)
tok_patch_pl:       ; (uses A preserves X,Y)
  STY B             ; [3] save Y (ln_ofs)
  LDY EmitPtch      ; [3] Y = emit patch address
  BEQ @done         ; [2] -> no patch address [+1]
  LDA EmitOfs       ; [3] A = emit_ofs
  CLC               ; [2] minus 1 (exclude patched byte)
  SBC EmitPtch      ; [3] A = emit_ofs - patch_addr (i.e. length)
  STA EmitBuf,Y     ; [5] write length at patch address
  LDA #0            ; [2] no patch address
  STA EmitPtch      ; [3] clear "last length placeholder"
@done:
  LDY B             ; [3] restore Y (ln_ofs)
  RTS

; @@ tok_emit_pl
; Emit a placeholder byte at (Emit) and advance (Emit).
tok_emit_pl:         ; (uses X; preserves A,Y; sets PL)  [30]
  LDX EmitOfs        ; [3] get current EmitOfs
  STX EmitPtch       ; [3] set "last length placeholder" for patching
  ; +++ fall through to @@ tok_emit +++


uOpSTEP:            ; $8E add <slot.16> += <top.16>  // 28 bytes!!
  CLC               ;
  PLA               ; topL
  STA Acc0          ; low
  PLA               ; topH
  STA Acc1          ; high
  PLA               ; slotL
  ADC Acc0          ; slotL + topL
  STA Acc2          ; slotL + topL
  PLA               ; slotH
  ADC Acc1          ; slotH + topH
  PHA               ; new slotH
  LDA Acc2          ; slotL + topL
  PHA               ; new slotL
  LDA Acc1          ; topH
  PHA               ; topH
  LDA Acc0          ; topL
  PHA               ; topL
  JMP uCodeLoop     ; -> next op









; ------------------------------------------------------------------------------
; PAGE 8 - OLD TOKENIZER

ORG BasROM+$800

old_reset:
  SEI              ; disable interrupts
  CLD              ; disable BCD mode
  LDA #End4K       ; end of memory (page)
  STA MemSize      ; set size of memory (in pages)
  LDX #$FF         ; reset stack
  TXS              ; SP=$FF
  INX              ; X=0 (text mode)
  JSR vid_mode     ; set mode, clear screen
  LDY #<msg_boot   ; display welcome message
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)

  ; detect memory installed
  ; XXX scan memory
  LDA #BasePg      ; page $02 (constant)
  STA TopPtrH      ; reset TOP
  LDX #0           ; X0=0
  STX TopPtr       ; reset TOP

  ; display free memory
  STX AccE         ; AccE=0 to display free memory
  STX Acc2         ; Acc2=0 to display free memory
  STX Acc0         ; Acc0=0 to display free memory
  LDX VidBase      ; bottom of video memory (page)
  DEX              ; minus $02 (BasePg, constant)
  DEX
  STX Acc1         ; Acc1=(number of pages)
  JSR num_print    ; (uses A,X)
  LDY #<msg_freemem
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)
  ; +++ fall through to @@ basic +++

; ------------------------------------------------------------------------------
; BASIC repl

; @@ basic
; enter the basic command-line interface
basic:
  CLD              ; disable BCD mode (for re-entry)
  JSR cmd_new      ; initialize BASIC program (XXX maybe?)
  LDY #<msg_ready  ; 
  JSR printmsgln   ; (uses A,B,C,D,X,Y,Src,Dst)
repl:              ; <- entry point after parse error
basic_esc:         ; <- entry point after Escape
  SEI              ; disable interrupts
  LDX #$FF         ; reset stack on entry
  TXS              ; set stack pointer
  JSR irq_init     ; init IRQ vector, init keyboard, enable IRQ
  JSR readline     ; -> LineBuf, Y=length
  JSR newline      ; uses A,X

  LDY #0           ; [2] input offset
  STY EmitOfs      ; [3] reset EmitOfs for code gen
  STY EmitPtch     ; [3] ensure no EmitPtch
  ; parse line number
  JSR skip_spc     ; [24+] Y=ofs -> Y, A=next-char
  CMP #0           ; [2] end of line? (must CMP)
  BEQ repl         ; [2] -> empty line, go back to repl [+1]
  JSR num_u16      ; [6] parse number at Y -> Y,Acc,NE=found (uses A,B,X)
  BNE @haveline    ; [2] -> found line number [+1]

  ; try matching a repl command
  LDA #<repl_tab   ; [2] repl commands offset
  LDX #>repl_tab   ; [2] repl commands page
  JSR match_kws    ; [6] Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC @direct      ; [3] -> no match, parse direct
  JSR @docmd       ; [6] run the command
  JMP repl         ; [3] -> back to repl

  ; jump to the REPL command (slow, but saves space)
@docmd:
  AND #7            ; [2] isolate low 3 bits
  ASL               ; [2] times 2 (word index)
  TAX               ; [2] as index
  LDA repl_cmd+1,X  ; [4] repl function, high byte   (XXX use single page, LDA #n)
  PHA               ; [3] push high
  LDA repl_cmd,X    ; [4] repl function, low byte
  PHA               ; [3] push low
  RTS               ; [6] "return" to the REPL command

  ; tokenize and evaluate direct BASIC statements
@direct:
  JSR tokenize     ; [6] tokenize BASIC statements (X=ln-ofs)
;  LDA #>EmitBuf    ; [2] EmitBuf page
;  STA CODEH        ; [3] set CODE page
;  LDY #0           ; [2] code offset
;  STY CODE         ; [3] set CODE low
;  JMP do_stmt      ; [3] -> execute the line
@dumpcode:
  LDY EmitOfs       ; [DEBUG]
  LDA #0            ; [DEBUG]
  STA EmitBuf,Y     ; [DEBUG]
  TAY               ; [DEBUG]
@debug:
  LDA EmitBuf,Y      ; [DENUG]
  BEQ repl           ; [DEBUG]
  JSR prhex          ; [DEBUG] A=byte; (uses A,X,F,Src,Dst) preserves Y
  LDA #32            ; [DEBUG]
  JSR wrchr          ; [DEBUG] A=char; (uses A,X,F,Src,Dst) preserves Y
  INY                ; [DEBUG]
  BNE @debug         ; [DEBUG]

  ; tokenize and append/edit the BASIC program
@haveline:         ; X = after line number
  ; save line number for bas_ins_line
  LDA Acc0         ; [3]
  STA LineNo       ; [3] tokenized line number
  LDA Acc1         ; [3]
  STA LineNoH      ; [3] tokenized line number high
  BMI err_bounds   ; [2]
  JSR tokenize     ; [6] tokenize BASIC statements (X=ln-ofs)
                   ;     XXX insert the tokenized line into the BASIC program
  JMP @dumpcode         ; [6] return to repl

; @@ escape
; must wait for ESC to be released
escape:           ; A = msg address low
  JSR hide_cursor ; uses A,Y; Y=0
  LDY #<msg_esc   ;
  JSR printmsgln  ; Y=msg (uses A,B,X,Y,Ptr,Src,Dst)
@wait:            ; wait for Escape to be released
  LDA ModKeys     ; check key state
  BMI @wait       ; -> ESC still down
  BPL basic_esc   ; -> re-enter repl, MUST reset stack


; ------------------------------------------------------------------------------
; Error Reporting

err_bounds:
  LDY #<msg_rng
  ; +++ fall through to @@ report_err +++

; @@ report_err
; Report an error and return to BASIC repl.
report_err:       ; Y = msg address low
  JSR printmsg    ; Y=ptr -> 
  LDY #<msg_err
  JSR printmsgln  ; Y=ptr -> 
  JMP repl

; @@ err_expect
; Report "Missing [char]"
err_expect:       ; A = expected character
  PHA             ; save char
  LDY #<msg_exp
  JSR printmsg
  PLA             ; restore char
  JSR wrchr       ; uses A,X
  JSR newline     ; uses A,X
  JMP repl


; ------------------------------------------------------------------------------
; BASIC Tokenizer
;
; Y = current LineBuf offset at (Ptr)
; A,X = temporaries

; emit a string literal
emit_str:
@copy:
  JSR tok_emit       ; emit char (uses X=0; preserves A,Y; sets PL)
  INY                ; advance
  LDA LineBuf,Y      ; get next char
  BEQ @missing       ; -> at end of line, missing quote
  CMP #34            ; is it `"`?
  BNE @copy          ; -> continue
  INY                ; advance
  CMP LineBuf,Y      ; is next char `"` ?
  BEQ @copy          ; -> emit one `"` and continue
  JSR tok_emit       ; emit closing `"` (uses X=0; preserves A,Y; sets PL)
  BPL tok_loop       ; -> ALWAYS (PL)
@missing:            ; at end of line, missing quote
  LDA #34            ; `"`
  BNE err_expect     ; error: missing `"` (A!=0)

; @@ emit_let        (so we can report syntax error for unknown keywords)
emit_let:            ; Y -> Y,EQ
  JSR emit_var       ; -> recognise and emit VAR
  JSR skip_spc       ; Y=ofs -> Y, A=next-char
  CMP #61            ; is it `=`?
  BEQ tok_loop       ; -> expect an expression (not enforced)
  ; ...
tok_syn:             ; report syntax error
  LDY #<msg_syn
  BNE report_err

tok_colon:
  INY                ; consume `:`
  SEC                ; 
  ROR D              ; set D=128
  BNE tok_stmt       ; -> ALWAYS: require a statement

; @@ tokenize
; tokenize BASIC statements (in-place in LineBuf/EmitBuf)
tokenize:            ; Y=ofs, uses A,X,B,C,D,Src
  LDA #0
  STA D              ; D=0, no LET until `:`
tok_stmt:
  JSR skip_spc       ; Y=ofs -> Y, A=next-char
  CMP #61            ; `=`
  BEQ tok_fnret      ; -> FN return
  JSR is_alpha       ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCS tok_syn        ; -> syntax error
  TAX                ; A-Z as index (0-25)
  LDA stmt_idx,X     ; offset in stmt_page (A-Z)
  LDX #>stmt_page    ; stmt table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC emit_let       ; -> no match, emit LET
  ORA #$C0           ; set top bits (match_kws uses d7,d6)
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y; sets PL)
  CMP #OP_DATA       ; a DATA statement? ($C3)
  BEQ tok_data       ; -> handle DATA/REM
  CMP #OP_REM        ; a REM statement? ($DC)
  BEQ tok_data       ; -> handle DATA/REM
  CMP #OP_ELSE       ; an ELSE statement? ($C6)
  BEQ tok_then       ; -> handle THEN/ELSE (NOT tok_else, opcode already emitted)
tok_loop:
  JSR skip_spc       ; Y=ofs -> Y, A=next-char
  TAX                ; save A (set flags for BEQ)
  BEQ tok_done       ; -> end of line
  JSR is_alpha       ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC tok_kwv        ; -> emit KEYWORD or VAR
  TXA                ; restore A
  CMP #34            ; `"`
  BEQ emit_str       ; -> emit STRING
  JSR is_digit       ; A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC emit_num       ; -> emit NUMBER
  TXA                ; restore A
  CMP #58            ; `:`
  BEQ tok_colon      ; -> expect statement
  CMP #60            ; <> <= <
  BEQ tok_ltgt       ; -> tokenize less than
  CMP #62            ; >= >
  BEQ tok_ltgt       ; -> tokenize greater than
tok_emitx:
  TXA                ; emit X
tok_emitc:           ; output character: ^ + - * / ( ) # , ; $
  JSR tok_emit       ; output character (uses X=0; preserves A,Y; sets PL)
  INY                ; advance input
  BPL tok_loop       ; -> ALWAYS: continue tokenize

tok_fnret:
  LDA #OP_FNRET
  BNE tok_emitc

tok_kwv:             ; AND,OR,EOR,DIV,MOD,THEN,ELSE,TO,STEP,FN,(functions)
  TAX                ; A-Z as index
  LDA expr_idx,X     ; offset in expr_page (A-Z)
  LDX #>expr_page    ; expr table page
  JSR match_kws      ; Y=ofs XA=table -> CF=found, Y=ofs, A=high-byte (uses A,X,B,Src)
  BCC @var           ; -> no match, emit VAR
  AND #$BF           ; clear bit 6 ($40)
  CMP #OP_THEN       ; a THEN statement? ($A5)
  BEQ tok_then       ; -> handle THEN
  CMP #OP_ELSEA      ; an ELSE statement? ($86)
  BEQ tok_else       ; -> handle ELSE
  JSR tok_emit       ; output token with top-bit set (uses X=0; preserves A,Y; sets PL)
  BPL tok_loop       ; -> ALWAYS: continue
@var:
  JSR emit_var_ex    ; -> recognise and emit VAR
  JMP tok_loop       ; -> ALWAYS: continue

tok_data:            ; copy rest of line verbatim
  JSR skip_spc       ; Y=ofs -> Y, A=next-char
@copy:
  LDA LineBuf,Y      ; copy rest of the line
  BEQ tok_done       ; -> end of line
  INY                ; advance input
  JSR tok_emit       ; emit code (uses X=0; preserves A,Y; PL)
  BPL @copy          ; -> ALWAYS: until end of line
tok_done:
  RTS

tok_else:
  LDA #OP_ELSE       ; emit OP_ELSE ($C6)
  JSR tok_emit       ; emit code (uses X=0; preserves A,Y; PL)
tok_then:            ; handle THEN/ELSE
  JSR skip_spc       ; Y=ofs -> Y, A=next-char
  JSR is_digit       ; A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC emit_num       ; -> DIGIT: emit line number
  JMP tok_stmt       ; -> ALWAYS: require a statement

tok_ltgt:            ; less than / greater than
  ASL                ; A=(60|62) (<|>) x2 = (120|124)
  AND #$1F           ; A=(24|28)
  STA B              ; A -> B
  INY                ; advance input (<|>)
  LDA LineBuf,Y      ; next input char
  SEC                ;
  SBC #60            ; '<'
  CMP #3             ; '<'=0 '='=1 '>'=2
  BCS tok_emitx      ; -> no match, just emit (<|>) (A >= 3)
  INY                ; advance input (<|=|>)
  ORA B              ; A = (24|28)|(0-2) = 24:<< 25:<= 26:<> 28:>< 29:>= 30:>>
  BNE tok_emitc      ; -> ALWAYS: emit and continue (A!=0)

; assumes next char is digit
emit_num:
@loop:
  JSR num_u24        ; from LineBuf,Y-> Y,Acc,CS=ovf (uses A,X,Term)
  BCS @ovf           ; -> overflow
  LDA Acc2
  BNE @int4          ; -> 3 bytes plus opcode
  LDA Acc1
  BNE @int3          ; -> 2 bytes plus opcode
  LDA Acc0
  CMP #10            ; CS if >= 10
  BCS @int2          ; -> 1 byte plus opcode
; single-digit number
  ORA #$F0           ; 0xF0 - 0xF9 (nums >= 0xF0)
  JMP @done          ; -> ALWAYS
@int2:
  LDA #OP_INT2       ; 2-byte integer (with opcode)
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  JMP @out1
@int3:
  LDA #OP_INT3       ; 3-byte integer (with opcode)
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  JMP @out2
@int4:
  LDA #OP_INT4       ; 4-byte integer (with opcode)
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
;out3:
  LDA Acc2
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
@out2:
  LDA Acc1
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
@out1:
  LDA Acc0
@done:
  JSR tok_emit       ; emit byte (uses X=0; preserves A,Y; PL)
  JMP tok_loop       ; -> ALWAYS
@ovf:
  JMP err_overflow

; @@ emit_var
; copy VAR[$] to output (assumes 1st char is alpha)
emit_var:
  BIT D            ; [3] N=1 after `:`
  BPL emit_var_ex  ; [2] -> no LET prefix [+1]
  LDX #OP_LET      ; [2]
emvr_lp:
  TXA              ; [2] X -> A
  JSR tok_emit     ; [6] output byte (uses X=0; preserves A,Y; sets PL)
emit_var_ex:       ; <- start VAR emit
  LDA LineBuf,Y    ; [4] next input char
  INY              ; [2] advance input (assume match)
  TAX              ; [2] save X=char
  JSR is_alpha     ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC emvr_lp      ; [2] -> is alpha, continue [+1]
  TXA              ; [2] restore A
  JSR is_digit     ; [6] A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC emvr_lp      ; [2] -> is digit, continue [+1]
  TXA              ; [2] restore A
  DEY              ; [2] undo advance (didn't match)
  CMP #36          ; [2] is it `$` ?
  BNE @nostr       ; [2] -> no [+1]
  JSR tok_emit     ; [6] output `$` (uses X=0; preserves A,Y; sets PL)
  INY              ; [2] consume `$`
@nostr:
  RTS              ; [2] -> return

; @@ tok_emit
; Emit an opcode at Emit,X and advance EmitOfs.
tok_emit:            ; (uses X; preserves A,Y; sets PL)  [21]
  LDX EmitOfs        ; [3] get emit offset
  STA EmitBuf,X      ; [5] emit token
  INC EmitOfs        ; [5] advance emit offset
  BMI err_overflow   ; [2] -> overflowed emit buffer [+1]
  RTS                ; [6]

err_overflow:
  LDY #<msg_ovf
  JMP report_err

; @@ skip_spc
skip_spc:          ; tokenize - skip spaces
@loop:             ; Y=ofs -> Y, A=next-char
  LDA LineBuf,Y    ; [4] next input char
  INY              ; [2] advance input (assume match)
  CMP #32          ; [2] was it space?
  BEQ @loop        ; [2] -> loop [+1]
  DEY              ; [2] undo advance (didn't match)
  RTS              ; [6]

; @@ is_alpha
is_alpha:          ; A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  AND #$DF         ; [2] lower -> upper (clear bit 5)
  SEC              ; [2] for subtract
  SBC #64          ; [2] make '@' be 0
  CMP #27          ; [2] 27 letters including `@` (CS if >= 27)
  RTS              ; [6] -> A=az-index CC=alpha [14]

; @@ is_digit
is_digit:          ; A=char -> A=[0..9], CC=found (preserves X,Y)
  SEC              ; [2] for subtract
  SBC #48          ; [2] make '0' be 0
  CMP #10          ; [2] 10 digits (CS if >= 10)
  RTS              ; [6] -> A=digit CC=found [12]





; ------------------------------------------------------------------------------
; REPL Command List

; matches repl_tab entries in the same order
; no special alignment requirements
repl_cmd:            ; 8 entries
  DW cmd_list     -1 ;
  DW cmd_run      -1 ;
  DW cmd_art      -1 ;
  DW cmd_save     -1 ;
  DW cmd_auto     -1 ;
  DW cmd_del      -1 ;
  DW cmd_new      -1 ;
  DW cmd_old      -1 ;

cmd_list:
  JSR ldprog        ; set up CODE -> Y=0, NE=no_program
  BNE cmdret        ; -> no program
  ; XXX parse start[,end] lines
  JMP list          ; -> print listing

cmd_run:            ; 27 bytes
  ; skip space
  ; is open-quote? -> JSR cmd_load -> run it
  JSR ldprog        ; set up CODE -> Y=0, NE=no_program
  BNE cmdret        ; -> no program
  JSR cmd_clear     ; clear all vars (uses A,X preserves Y)
  JMP do_ln_op      ; -> expect first line (OP_LN)

ldprog:
  LDA #BasePg       ; copy BasePg into CODE ($02)
  STA CODEH         ; CODE page
  LDY #0            ; Y=0
  STY CODE          ; CODE offset
  STY Data          ; clear data pointer
  STY DataH         ; clear data pointer
  STY OpTop         ; clear operator stack
  LDA (CODE),Y      ; get first byte of program
  CMP #$E9          ; BASIC marker
cmdret:
  RTS

cmd_del:
cmd_auto:
  RTS

cmd_clear:          ; clear all variables (uses A,X preserves Y)  10 bytes
  LDA #0
  LDX #51           ; 52 bytes VarPtrs
@lp:
  STA VarPtrs,X     ; clear pointer
  DEX
  BPL @lp
  ; reset free space
  LDA TopPtr
  STA FreePtr
  LDA TopPtrH
  STA FreePtrH
  RTS

cmd_art:            ; 29 bytes
  LDX #0            ; text mode
  JSR vid_mode      ; set mode (X=mode, uses A,X,Y,B)
  LDY #<msg_art
  JSR printmsg
  JSR txt_home
@idle:
  JSR show_cursor   ; enable cursor (uses A,Y)
@wait:
  BIT ModKeys       ; detect ESC
  BMI @esc
  JSR readchar      ; get char from keyboard
  BEQ @wait         ; -> continue waiting
  TAX               ; save key
  JSR hide_cursor   ; disable cursor (uses A,Y)
  TXA               ; restore key
@loop:
  JSR wrchr         ; print it, or do control code (uses A,X,F,Src,Dst) preserves Y
  JSR readchar      ; get char from keyboard
  BNE @loop         ; -> more chars
  BEQ @idle         ; -> go idle
@esc:
  JMP escape

; delete line-range
; cmd_del:
;  JSR num_u16       ; Y=ofs (uses A,Y,B,C,Term) -> Acc,Y,NE=found
;  JSR find_line     ; find matching line (Acc -> Ptr, CS=found)
; move code down over it
; update next line's prev length


cmd_save:
  ; skip space
  ; is open-quote? -> JSR tok_string -> open file -> read it -> close file
  RTS

cmd_new:           ; 26 bytes
  LDA #BasePg      ; bottom of BASIC memory ($02)
  STA TopPtrH      ; end of BASIC program
  LDY #0           ; offset = 0
  STY TopPtr       ; initially zero
@lp:
  LDA @tpl,Y
  STA (TopPtr),Y
  INY
  CPY #7
  BNE @lp
  STY TopPtr       ; set program length
  RTS
@tpl:
  DB $E9, OP_LN, $FF, $FF, 1, 0, OP_END

cmd_old:
  ; XX walk old program and verify valid lines
  RTS


; @@ printkw
; Print a keyword directly from a Keyword Table
printkw:          ; 13 bytes
  LDA kwtab,Y     ; [4] first char
@loop:
  JSR wrchr       ; [6] print char (uses A,X,F,Src,Dst) preserves Y
  INY             ; [2] advance
  LDA kwtab,Y     ; [4] load next char
  BPL @loop       ; [3] until top-bit is set
  RTS             ; [6] done

; ------------------------------------------------------------------------------
; END OF - OLD TOKENIZER




uOpSUB8:            ; $8F sutract <slot> -= <top> dropping <top>
  SEC               ; for SBC
  PLA               ; pop top
  STA B             ; temp
  PLA
  ADC B
  PHA               ;                    8b  19c
  JMP uCodeLoop     ; -> next op



MISSING LABEL?!

; @@ emit_var
; match and emit a VAR name (assume 1st letter is alpha) XXX ideally
emit_var:          ; Y=ofs -> Y, CC=found
  LDA LineBuf,Y    ; [4] next input char
  JSR is_alpha     ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC @start       ;
  CLC              ; [2] CC=not-found
  RET              ; [6] return
@lp:
  JSR emit_byte    ; [6] emit char -> (uses X; preserves A,Y; sets PL)
@start:
  LDA LineBuf,Y    ; [4] next input char
  INY              ; [2] advance input (assume match)
  TAX              ; [3] save char
  JSR is_alpha     ; [6] A=char -> A=az-index, CC=alphabetic (preserves X,Y)
  BCC @lp          ; [2] -> is alpha, continue [+1]
  TXA              ; [2] restore char
  JSR is_digit     ; [6] A=char -> A=[0..9], CC=found (preserves X,Y)
  BCC @lp          ; [2] -> is digit, continue [+1]
  DEY              ; [2] undo advance (didn't match)
  RTS              ; [6] CS=found


