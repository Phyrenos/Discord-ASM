; json.asm - Minimal JSON parser for Discord Gateway payloads
; Not a full parser - targeted key extraction for known Discord JSON structures

; ============================================================
; json_find_key - Find a key in a JSON string and return pointer to its value
; rcx = json string pointer
; rdx = key to find (without quotes)
; Returns: rax = pointer to value start (after colon and whitespace), or 0 if not found
; ============================================================
json_find_key:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov rsi, rcx            ; json string
    mov rdi, rdx            ; key to find

    ; Get key length
    mov rcx, rdi
    call asm_strlen
    mov r12, rax            ; r12 = key length

.scan:
    ; Find next quote
    cmp byte [rsi], 0
    je .not_found
    cmp byte [rsi], '"'
    je .check_key
    inc rsi
    jmp .scan

.check_key:
    inc rsi                 ; skip opening quote
    ; Compare key
    mov rcx, rsi
    mov rdx, rdi
    mov r8, r12
    call asm_strncmp
    test eax, eax
    jnz .skip_string

    ; Check that key is followed by closing quote
    cmp byte [rsi + r12], '"'
    jne .skip_string

    ; Found key - skip past closing quote and find colon
    lea rsi, [rsi + r12 + 1]
.find_colon:
    cmp byte [rsi], 0
    je .not_found
    cmp byte [rsi], ':'
    je .found_colon
    inc rsi
    jmp .find_colon

.found_colon:
    inc rsi                 ; skip colon
    ; Skip whitespace
.skip_ws:
    cmp byte [rsi], ' '
    je .skip_ws_next
    cmp byte [rsi], 9
    je .skip_ws_next
    cmp byte [rsi], 10
    je .skip_ws_next
    cmp byte [rsi], 13
    je .skip_ws_next
    jmp .found
.skip_ws_next:
    inc rsi
    jmp .skip_ws

.found:
    mov rax, rsi
    jmp .done

.skip_string:
    ; Skip to end of current string value
    cmp byte [rsi], 0
    je .not_found
    cmp byte [rsi], '"'
    je .end_str
    cmp byte [rsi], 0x5C   ; backslash
    jne .skip_next
    inc rsi                 ; skip escaped char
.skip_next:
    inc rsi
    jmp .skip_string
.end_str:
    inc rsi                 ; skip closing quote
    jmp .scan

.not_found:
    xor eax, eax

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================
; json_extract_string - Extract a JSON string value into buffer
; rcx = pointer to value start (should point to opening quote)
; rdx = output buffer
; r8  = output buffer size
; Returns: rax = length of extracted string, or 0 on error
; ============================================================
json_extract_string:
    push rbx
    push rsi
    push rdi

    mov rsi, rcx            ; value pointer
    mov rdi, rdx            ; output buffer
    mov rbx, r8             ; buffer size
    dec rbx                 ; leave room for null

    ; Check for opening quote
    cmp byte [rsi], '"'
    jne .error
    inc rsi                 ; skip opening quote

    xor ecx, ecx           ; output index
.copy_loop:
    cmp rcx, rbx
    jge .truncate

    mov al, [rsi]
    test al, al
    jz .error              ; unexpected end of string

    cmp al, '"'
    je .end_string

    cmp al, 0x5C           ; backslash
    jne .store_char

    ; Handle escape
    inc rsi
    mov al, [rsi]
    cmp al, '"'
    je .store_char
    cmp al, 0x5C           ; backslash
    je .store_char
    cmp al, '/'
    je .store_char
    cmp al, 'n'
    jne .check_t
    mov al, 10
    jmp .store_char
.check_t:
    cmp al, 't'
    jne .check_r
    mov al, 9
    jmp .store_char
.check_r:
    cmp al, 'r'
    jne .store_char
    mov al, 13
    ; Fall through to store_char

.store_char:
    mov [rdi + rcx], al
    inc rcx
    inc rsi
    jmp .copy_loop

.end_string:
    mov byte [rdi + rcx], 0
    mov rax, rcx
    jmp .done

.truncate:
    mov byte [rdi + rcx], 0
    mov rax, rcx
    jmp .done

.error:
    mov byte [rdi], 0
    xor eax, eax

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

; ============================================================
; json_extract_int - Extract a JSON integer value
; rcx = pointer to value start (should point to digit or minus)
; Returns: rax = parsed integer value
; ============================================================
json_extract_int:
    ; Simply delegate to asm_str_to_int
    jmp asm_str_to_int

; ============================================================
; json_extract_bool - Extract a JSON boolean value
; rcx = pointer to value start
; Returns: rax = 1 for true, 0 for false
; ============================================================
json_extract_bool:
    cmp byte [rcx], 't'
    je .true
    xor eax, eax
    ret
.true:
    mov eax, 1
    ret

; ============================================================
; json_skip_value - Skip over a JSON value (string, number, object, array, bool, null)
; rcx = pointer to value start
; Returns: rax = pointer to character after the value
; ============================================================
json_skip_value:
    push rbx

    mov al, [rcx]

    ; String?
    cmp al, '"'
    je .skip_string

    ; Object?
    cmp al, '{'
    je .skip_braced

    ; Array?
    cmp al, '['
    je .skip_bracketed

    ; Number, bool, null - skip until delimiter
.skip_literal:
    inc rcx
    mov al, [rcx]
    test al, al
    jz .done_literal
    cmp al, ','
    je .done_literal
    cmp al, '}'
    je .done_literal
    cmp al, ']'
    je .done_literal
    cmp al, ' '
    je .done_literal
    cmp al, 10
    je .done_literal
    cmp al, 13
    je .done_literal
    jmp .skip_literal
.done_literal:
    mov rax, rcx
    pop rbx
    ret

.skip_string:
    inc rcx                 ; skip opening quote
.str_loop:
    mov al, [rcx]
    test al, al
    jz .str_end
    cmp al, 0x5C           ; backslash
    jne .str_no_escape
    inc rcx                 ; skip escaped char
    jmp .str_next
.str_no_escape:
    cmp al, '"'
    je .str_close
.str_next:
    inc rcx
    jmp .str_loop
.str_close:
    inc rcx                 ; skip closing quote
.str_end:
    mov rax, rcx
    pop rbx
    ret

.skip_braced:
    mov bl, '{'
    mov bh, '}'
    jmp .skip_nested

.skip_bracketed:
    mov bl, '['
    mov bh, ']'

.skip_nested:
    mov edx, 1             ; depth counter
    inc rcx                ; skip opening bracket
.nest_loop:
    mov al, [rcx]
    test al, al
    jz .nest_done
    cmp al, '"'
    je .nest_string
    cmp al, bl
    jne .nest_check_close
    inc edx
    jmp .nest_next
.nest_check_close:
    cmp al, bh
    jne .nest_next
    dec edx
    jz .nest_close
.nest_next:
    inc rcx
    jmp .nest_loop
.nest_string:
    inc rcx
.nest_str_loop:
    mov al, [rcx]
    test al, al
    jz .nest_done
    cmp al, 0x5C           ; backslash
    jne .nest_str_no_esc
    inc rcx
    jmp .nest_str_next
.nest_str_no_esc:
    cmp al, '"'
    je .nest_str_close
.nest_str_next:
    inc rcx
    jmp .nest_str_loop
.nest_str_close:
    inc rcx
    jmp .nest_loop
.nest_close:
    inc rcx                 ; skip closing bracket
.nest_done:
    mov rax, rcx
    pop rbx
    ret

; ============================================================
; json_find_nested_key - Find a nested key like "d.heartbeat_interval"
; rcx = json string, rdx = outer key, r8 = inner key
; Returns: rax = pointer to inner value, or 0 if not found
; ============================================================
json_find_nested_key:
    push rbx
    push r12
    sub rsp, 40

    mov r12, r8             ; save inner key

    ; Find outer key first
    ; rcx = json, rdx = outer key (already set)
    call json_find_key
    test rax, rax
    jz .not_found

    ; Now search within the outer value for inner key
    mov rcx, rax            ; value start (should be '{' for object)
    mov rdx, r12            ; inner key
    call json_find_key

    jmp .done

.not_found:
    xor eax, eax
.done:
    add rsp, 40
    pop r12
    pop rbx
    ret

; ============================================================
; json_find_path - Walk an arbitrary-depth key path
; rcx = json string, rdx = pointer to array of key-string pointers, r8 = count
; Returns: rax = pointer to the value at the path, or 0 if any key missing
; Example: keys = [ptr"d", ptr"author", ptr"id"], count = 3
; ============================================================
json_find_path:
    push rbx
    push rsi
    push r12
    push r13

    mov rsi, rcx            ; current search position
    mov r12, rdx            ; key pointer array
    mov r13, r8             ; remaining count

.loop:
    test r13, r13
    jz .found
    mov rcx, rsi
    mov rdx, [r12]         ; next key pointer
    call json_find_key
    test rax, rax
    jz .notfound
    mov rsi, rax           ; descend into the value
    add r12, 8
    dec r13
    jmp .loop

.found:
    mov rax, rsi
    jmp .done
.notfound:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rsi
    pop rbx
    ret

; ============================================================
; json_array_count - Count top-level elements in a JSON array
; rcx = pointer to value (should be '[')
; Returns: rax = element count (0 if not an array or empty)
; ============================================================
json_array_count:
    push rbx
    push rsi
    mov rsi, rcx
    cmp byte [rsi], '['
    jne .zero
    inc rsi
    xor rbx, rbx
.skipws:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .ws
    cmp al, 9
    je .ws
    cmp al, 10
    je .ws
    cmp al, 13
    je .ws
    jmp .check_empty
.ws:
    inc rsi
    jmp .skipws
.check_empty:
    cmp byte [rsi], ']'
    je .done
.elem:
    inc rbx                ; count this element
    mov rcx, rsi
    call json_skip_value
    mov rsi, rax
.skip2:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .ws2
    cmp al, 9
    je .ws2
    cmp al, 10
    je .ws2
    cmp al, 13
    je .ws2
    jmp .after2
.ws2:
    inc rsi
    jmp .skip2
.after2:
    cmp byte [rsi], ','
    jne .done
    inc rsi
.skip3:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .ws3
    cmp al, 9
    je .ws3
    cmp al, 10
    je .ws3
    cmp al, 13
    je .ws3
    jmp .elem
.ws3:
    inc rsi
    jmp .skip3
.done:
    mov rax, rbx
    pop rsi
    pop rbx
    ret
.zero:
    xor eax, eax
    pop rsi
    pop rbx
    ret

; ============================================================
; json_array_get - Get a pointer to the Nth element of a JSON array
; rcx = pointer to value (should be '['), rdx = index (0-based)
; Returns: rax = pointer to element value, or 0 if out of range
; ============================================================
json_array_get:
    push rbx
    push rsi
    push r12
    mov rsi, rcx
    mov r12, rdx           ; target index
    cmp byte [rsi], '['
    jne .gnone
    inc rsi
    xor rbx, rbx           ; current index
.gws:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .gw
    cmp al, 9
    je .gw
    cmp al, 10
    je .gw
    cmp al, 13
    je .gw
    jmp .gcheck
.gw:
    inc rsi
    jmp .gws
.gcheck:
    cmp byte [rsi], ']'
    je .gnone
.gloop:
    cmp rbx, r12
    je .gfound
    mov rcx, rsi
    call json_skip_value
    mov rsi, rax
.gskip:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .gw2
    cmp al, 9
    je .gw2
    cmp al, 10
    je .gw2
    cmp al, 13
    je .gw2
    jmp .gafter
.gw2:
    inc rsi
    jmp .gskip
.gafter:
    cmp byte [rsi], ','
    jne .gnone
    inc rsi
.gws3:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .gw3
    cmp al, 9
    je .gw3
    cmp al, 10
    je .gw3
    cmp al, 13
    je .gw3
    jmp .gnext
.gw3:
    inc rsi
    jmp .gws3
.gnext:
    inc rbx
    jmp .gloop
.gfound:
    mov rax, rsi
    jmp .gdone
.gnone:
    xor eax, eax
.gdone:
    pop r12
    pop rsi
    pop rbx
    ret

; ============================================================
; json_extract_int_str - Extract an integer that may be a bare number or a
; quoted snowflake string (e.g. "123456789012345678").
; rcx = pointer to value start
; Returns: rax = parsed integer
; ============================================================
json_extract_int_str:
    cmp byte [rcx], '"'
    jne .num
    inc rcx
.num:
    jmp asm_str_to_int
