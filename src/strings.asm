; strings.asm - String utility functions
; All functions follow Microsoft x64 ABI

; ============================================================
; asm_strlen - Get length of null-terminated string
; rcx = string pointer
; Returns: rax = length (not counting null)
; ============================================================
asm_strlen:
    xor rax, rax
    test rcx, rcx
    jz .done
.loop:
    cmp byte [rcx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ============================================================
; asm_strcmp - Compare two null-terminated strings
; rcx = string1, rdx = string2
; Returns: rax = 0 if equal, <0 if s1<s2, >0 if s1>s2
; ============================================================
asm_strcmp:
    push rbx
.loop:
    movzx eax, byte [rcx]
    movzx ebx, byte [rdx]
    sub eax, ebx
    jne .done
    test bl, bl
    jz .done
    inc rcx
    inc rdx
    jmp .loop
.done:
    pop rbx
    ret

; ============================================================
; asm_strncmp - Compare n bytes of two strings
; rcx = string1, rdx = string2, r8 = max bytes
; Returns: rax = 0 if equal for n bytes
; ============================================================
asm_strncmp:
    push rbx
    test r8, r8
    jz .equal
.loop:
    movzx eax, byte [rcx]
    movzx ebx, byte [rdx]
    sub eax, ebx
    jne .done
    test bl, bl
    jz .equal
    inc rcx
    inc rdx
    dec r8
    jnz .loop
.equal:
    xor eax, eax
.done:
    pop rbx
    ret

; ============================================================
; asm_strcpy - Copy string from src to dst
; rcx = dst, rdx = src
; Returns: rax = dst
; ============================================================
asm_strcpy:
    push rsi
    mov rax, rcx            ; rax = dst (write pointer)
    mov rsi, rcx            ; rsi = original dst (preserved)
    test rdx, rdx
    jz .null_src
.loop:
    mov cl, [rdx]
    mov [rax], cl
    test cl, cl
    jz .done
    inc rax
    inc rdx
    jmp .loop
.null_src:
    mov byte [rax], 0
.done:
    mov rax, rsi            ; return original dst pointer
    pop rsi
    ret

; ============================================================
; asm_strcat - Concatenate src onto end of dst
; rcx = dst, rdx = src
; Returns: rax = dst
; ============================================================
asm_strcat:
    push rbx
    mov rbx, rcx           ; save dst
    ; Find end of dst
.find_end:
    cmp byte [rcx], 0
    je .copy
    inc rcx
    jmp .find_end
.copy:
    ; rcx now points to null terminator of dst
    mov al, [rdx]
    mov [rcx], al
    test al, al
    jz .done
    inc rcx
    inc rdx
    jmp .copy
.done:
    mov rax, rbx
    pop rbx
    ret

; ============================================================
; asm_strncpy - Copy up to n bytes from src to dst
; rcx = dst, rdx = src, r8 = max bytes (including null)
; Returns: rax = dst
; ============================================================
asm_strncpy:
    push rsi
    mov rsi, rcx            ; save original dst
    mov rax, rcx
    test r8, r8
    jz .done
    dec r8                  ; reserve space for null
.loop:
    test r8, r8
    jz .terminate
    mov cl, [rdx]
    mov [rax], cl
    test cl, cl
    jz .done_restore
    inc rax
    inc rdx
    dec r8
    jmp .loop
.terminate:
    mov byte [rax], 0
.done_restore:
    mov rax, rsi
.done:
    pop rsi
    ret

; ============================================================
; asm_memcpy - Copy n bytes from src to dst
; rcx = dst, rdx = src, r8 = count
; Returns: rax = dst
; ============================================================
asm_memcpy:
    mov rax, rcx
    test r8, r8
    jz .done
.loop:
    mov cl, [rdx]
    mov [rax], cl
    inc rax
    inc rdx
    dec r8
    jnz .loop
    mov rax, rcx            ; restore original dst
    ret
.done:
    ret

; ============================================================
; asm_memset - Fill n bytes with a value
; rcx = dst, dl = value, r8 = count
; Returns: rax = dst
; ============================================================
asm_memset:
    mov rax, rcx
    test r8, r8
    jz .done
.loop:
    mov [rcx], dl
    inc rcx
    dec r8
    jnz .loop
.done:
    ret

; ============================================================
; asm_find_char - Find first occurrence of character in string
; rcx = string, dl = character to find
; Returns: rax = pointer to char, or 0 if not found
; ============================================================
asm_find_char:
    test rcx, rcx
    jz .not_found
.loop:
    mov al, [rcx]
    test al, al
    jz .not_found
    cmp al, dl
    je .found
    inc rcx
    jmp .loop
.found:
    mov rax, rcx
    ret
.not_found:
    xor eax, eax
    ret

; ============================================================
; asm_itoa - Convert integer to decimal string
; rcx = value (signed 64-bit), rdx = buffer
; Returns: rax = buffer
; ============================================================
asm_itoa:
    push rbx
    push rdi
    mov rdi, rdx            ; save buffer pointer
    mov rax, rcx            ; value to convert

    ; Handle negative
    test rax, rax
    jns .positive
    neg rax
    mov byte [rdi], '-'
    inc rdi
.positive:
    ; Push digits in reverse
    mov rbx, rdi            ; save start of digits
    mov rcx, 10
.digit_loop:
    xor edx, edx
    div rcx                 ; rax = quotient, rdx = remainder
    add dl, '0'
    mov [rdi], dl
    inc rdi
    test rax, rax
    jnz .digit_loop

    ; Null terminate
    mov byte [rdi], 0
    dec rdi                 ; rdi = last digit

    ; Reverse the digits
.reverse:
    cmp rbx, rdi
    jge .done
    mov al, [rbx]
    mov cl, [rdi]
    mov [rbx], cl
    mov [rdi], al
    inc rbx
    dec rdi
    jmp .reverse
.done:
    mov rax, rdx            ; return original buffer
    pop rdi
    pop rbx
    ret

; ============================================================
; asm_str_to_int - Parse decimal string to integer
; rcx = string pointer
; Returns: rax = parsed integer value
; ============================================================
asm_str_to_int:
    xor rax, rax
    xor r8, r8              ; sign flag
    test rcx, rcx
    jz .done

    ; Skip whitespace
.skip_ws:
    cmp byte [rcx], ' '
    je .next_ws
    cmp byte [rcx], 9       ; tab
    je .next_ws
    jmp .check_sign
.next_ws:
    inc rcx
    jmp .skip_ws

.check_sign:
    cmp byte [rcx], '-'
    jne .check_plus
    mov r8, 1
    inc rcx
    jmp .parse
.check_plus:
    cmp byte [rcx], '+'
    jne .parse
    inc rcx

.parse:
    movzx edx, byte [rcx]
    sub edx, '0'
    cmp edx, 9
    ja .apply_sign
    imul rax, 10
    add rax, rdx
    inc rcx
    jmp .parse

.apply_sign:
    test r8, r8
    jz .done
    neg rax
.done:
    ret

; ============================================================
; asm_to_wide - Convert UTF-8 string to UTF-16LE using MultiByteToWideChar
; rcx = utf8 string, rdx = wide buffer, r8 = wide buffer size (in WCHARs)
; Returns: rax = number of wide chars written
; ============================================================
asm_to_wide:
    push rbp
    mov rbp, rsp
    sub rsp, 64             ; shadow space + args

    ; Save parameters
    mov [rsp+48], r8        ; save wide buf size

    ; Get UTF-8 string length
    push rcx
    push rdx
    call asm_strlen          ; rax = length
    pop rdx
    pop rcx
    inc rax                  ; include null terminator

    ; MultiByteToWideChar(CP_UTF8, 0, utf8str, len, widebuf, widebufsize)
    mov [rsp+40], rax        ; save length
    mov r9, [rsp+48]        ; cchWideChar = buffer size
    mov [rsp+32], rdx       ; lpWideCharStr (5th arg)
    mov [rsp+40], r9        ; cchWideChar (6th arg - reuse slot after we used it)
    ; Actually need to restructure for 6 args
    ; Args: rcx=CodePage, rdx=dwFlags, r8=lpMultiByteStr, r9=cbMultiByte, [rsp+32]=lpWideCharStr, [rsp+40]=cchWideChar
    mov r9, rax              ; cbMultiByte = string length + null
    mov r8, rcx              ; lpMultiByteStr = utf8 string
    mov [rsp+32], rdx        ; lpWideCharStr = wide buffer
    mov rax, [rsp+48]
    mov [rsp+40], rax        ; cchWideChar = buffer size
    mov ecx, CP_UTF8         ; CodePage
    xor edx, edx            ; dwFlags = 0

    call MultiByteToWideChar

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; asm_from_wide - Convert UTF-16LE string to UTF-8 using WideCharToMultiByte
; rcx = wide string, rdx = utf8 buffer, r8 = utf8 buffer size
; Returns: rax = number of bytes written
; ============================================================
asm_from_wide:
    push rbp
    mov rbp, rsp
    sub rsp, 80             ; shadow space + extra args

    ; WideCharToMultiByte(CP_UTF8, 0, widestr, -1, utf8buf, bufsize, NULL, NULL)
    mov [rsp+32], rdx       ; lpMultiByteStr (5th arg)
    mov [rsp+40], r8        ; cbMultiByte (6th arg)
    mov qword [rsp+48], 0   ; lpDefaultChar (7th arg)
    mov qword [rsp+56], 0   ; lpUsedDefaultChar (8th arg)
    mov r9, -1              ; cchWideChar = -1 (null terminated)
    mov r8, rcx             ; lpWideCharStr
    xor edx, edx           ; dwFlags = 0
    mov ecx, CP_UTF8        ; CodePage

    call WideCharToMultiByte

    mov rsp, rbp
    pop rbp
    ret
