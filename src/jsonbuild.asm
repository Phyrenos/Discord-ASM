; jsonbuild.asm - Minimal JSON builder over a caller-supplied buffer.
;
; Tracks a small stack of "is the next element the first in this container?"
; flags so commas are inserted automatically. String values are escaped via
; asm_json_escape; object keys are assumed to be safe literal identifiers.
;
; Usage:
;   lea  rcx, [mybuf]            ; jb_init(buffer)
;   call jb_init
;   call jb_begin_obj           ; {
;   lea  rcx,[k_content] / mov rdx, value
;   call jb_key_str             ;   "content":"..."
;   call jb_end_obj             ; }
;
; NOTE: single builder context (not reentrant); fine because all payloads are
; built and sent on the gateway thread before the next one starts.

section .bss
    jb_buf:          resq 1     ; target buffer pointer
    jb_depth:        resq 1     ; current container depth (index into first stack)
    jb_first_stack:  resb 64    ; per-depth "first element" flags
    jb_escape_buf:   resb 4096  ; scratch for escaped string values
    jb_num_buf:      resb 32    ; scratch for integer formatting

section .data
    jb_true_str:     db "true", 0
    jb_false_str:    db "false", 0

section .text

; ------------------------------------------------------------
; jb_init - Begin a new document in the given buffer
; rcx = buffer
; ------------------------------------------------------------
jb_init:
    mov [jb_buf], rcx
    mov byte [rcx], 0
    mov qword [jb_depth], 0
    mov byte [jb_first_stack], 1
    ret

; ------------------------------------------------------------
; Internal: emit a separating comma if this is not the first element
; of the current container.
; ------------------------------------------------------------
_jb_sep:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov rax, [jb_depth]
    lea r9, [jb_first_stack]
    cmp byte [r9+rax], 0
    je .comma
    mov byte [r9+rax], 0       ; was first; subsequent elements need a comma
    jmp .done
.comma:
    mov rcx, [jb_buf]
    mov dl, ','
    call asm_strcat_char
.done:
    mov rsp, rbp
    pop rbp
    ret

; Internal: push/pop a container nesting level
_jb_push:
    mov rax, [jb_depth]
    inc rax
    cmp rax, 63
    ja .cap
    mov [jb_depth], rax
    lea r9, [jb_first_stack]
    mov byte [r9+rax], 1
.cap:
    ret

_jb_pop:
    mov rax, [jb_depth]
    test rax, rax
    jz .done
    dec rax
    mov [jb_depth], rax
.done:
    ret

; Internal: append one char to the working buffer (rcx-safe wrapper)
; dl = char
_jb_putc:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov rcx, [jb_buf]
    call asm_strcat_char
    mov rsp, rbp
    pop rbp
    ret

; Internal: append "key": (assumes _jb_sep already done)
; rcx = key
_jb_emit_key:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov dl, '"'
    call _jb_putc
    mov rcx, [jb_buf]
    mov rdx, [rbp-8]
    call asm_strcat
    mov dl, '"'
    call _jb_putc
    mov dl, ':'
    call _jb_putc
    mov rsp, rbp
    pop rbp
    ret

; Internal: append "escaped-value"
; rcx = value (UTF-8)
_jb_emit_qstr:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov dl, '"'
    call _jb_putc
    mov rcx, [rbp-8]
    lea rdx, [jb_escape_buf]
    mov r8, 4096
    call asm_json_escape
    mov rcx, [jb_buf]
    lea rdx, [jb_escape_buf]
    call asm_strcat
    mov dl, '"'
    call _jb_putc
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; Container open/close
; ------------------------------------------------------------
jb_begin_obj:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call _jb_sep
    mov dl, '{'
    call _jb_putc
    call _jb_push
    mov rsp, rbp
    pop rbp
    ret

jb_end_obj:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov dl, '}'
    call _jb_putc
    call _jb_pop
    mov rsp, rbp
    pop rbp
    ret

jb_begin_arr:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call _jb_sep
    mov dl, '['
    call _jb_putc
    call _jb_push
    mov rsp, rbp
    pop rbp
    ret

jb_end_arr:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov dl, ']'
    call _jb_putc
    call _jb_pop
    mov rsp, rbp
    pop rbp
    ret

; "key":{  - open a nested object as the value of a key
; rcx = key
jb_begin_key_obj:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_key
    mov dl, '{'
    call _jb_putc
    call _jb_push
    mov rsp, rbp
    pop rbp
    ret

; "key":[  - open a nested array as the value of a key
; rcx = key
jb_begin_key_arr:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_key
    mov dl, '['
    call _jb_putc
    call _jb_push
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; Key/value members
; ------------------------------------------------------------
; rcx = key, rdx = string value (escaped)
jb_key_str:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_key
    mov rcx, [rbp-16]
    call _jb_emit_qstr
    mov rsp, rbp
    pop rbp
    ret

; rcx = key, rdx = signed integer value
jb_key_int:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_key
    mov rcx, [rbp-16]
    lea rdx, [jb_num_buf]
    call asm_itoa
    mov rcx, [jb_buf]
    lea rdx, [jb_num_buf]
    call asm_strcat
    mov rsp, rbp
    pop rbp
    ret

; rcx = key, rdx = 0 (false) / nonzero (true)
jb_key_bool:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_key
    mov rcx, [jb_buf]
    cmp qword [rbp-16], 0
    je .false
    lea rdx, [jb_true_str]
    jmp .emit
.false:
    lea rdx, [jb_false_str]
.emit:
    call asm_strcat
    mov rsp, rbp
    pop rbp
    ret

; rcx = key, rdx = raw JSON value pointer (number/object/array literal)
jb_key_raw:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_key
    mov rcx, [jb_buf]
    mov rdx, [rbp-16]
    call asm_strcat
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; Array elements (no key)
; ------------------------------------------------------------
; rcx = string value (escaped)
jb_val_str:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    call _jb_sep
    mov rcx, [rbp-8]
    call _jb_emit_qstr
    mov rsp, rbp
    pop rbp
    ret

; rcx = raw JSON value pointer
jb_val_raw:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    call _jb_sep
    mov rcx, [jb_buf]
    mov rdx, [rbp-8]
    call asm_strcat
    mov rsp, rbp
    pop rbp
    ret
