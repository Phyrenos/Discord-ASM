; rest_core.asm - Generic Discord REST transport
;
; All REST endpoints go through rest_call, which:
;   * keeps a single cached HTTPS connection to discord.com (g_hApiConnect),
;   * builds the "Authorization: Bot <token>" header from the global bot_token,
;   * converts the UTF-8 path to wide,
;   * issues the request, and
;   * transparently retries on HTTP 429 using the body's retry_after.
;
; This removes the connect/auth/wide/request/free/close boilerplate that used to
; be copy-pasted into every endpoint.

section .bss
    g_hApiConnect:  resq 1        ; cached discord.com connection handle
    g_rest_status:  resd 1        ; HTTP status of the last rest_call
    rc_auth_wide:   resw 512      ; "Authorization: Bot ..." (wide)
    rc_path_wide:   resw 1024     ; request path (wide)

section .data
    rc_retry_key:   db "retry_after", 0

section .text

; ============================================================
; parse_retry_ms - Parse a "retry_after" seconds value (e.g. 0.567) to ms
; rcx = pointer to the number
; Returns: rax = milliseconds to wait (with a small safety buffer)
; ============================================================
parse_retry_ms:
    push rbx
    push rsi
    mov rsi, rcx

    ; integer seconds * 1000
    mov rcx, rsi
    call asm_str_to_int
    imul rax, 1000
    mov rbx, rax

    ; advance to '.'
.find_dot:
    mov al, [rsi]
    test al, al
    jz .done
    cmp al, '.'
    je .frac
    inc rsi
    jmp .find_dot

.frac:
    inc rsi
    ; up to 3 fractional digits -> milliseconds
    movzx eax, byte [rsi]
    sub eax, '0'
    cmp eax, 9
    ja .done
    imul eax, 100
    add rbx, rax
    inc rsi
    movzx eax, byte [rsi]
    sub eax, '0'
    cmp eax, 9
    ja .done
    imul eax, 10
    add rbx, rax
    inc rsi
    movzx eax, byte [rsi]
    sub eax, '0'
    cmp eax, 9
    ja .done
    add rbx, rax

.done:
    add rbx, 250           ; safety buffer
    mov rax, rbx
    pop rsi
    pop rbx
    ret

; ============================================================
; rest_call - Perform a Discord REST request
; rcx = method (wide string, e.g. w_method_GET/POST/PUT/...)
; rdx = path (UTF-8, e.g. "/api/v10/channels/123/messages")
; r8  = body (UTF-8, or NULL)
; r9  = body length (0 if no body)
; Returns: rax = heap response buffer (caller must http_free_response), or 0.
;          g_rest_status = HTTP status code.
; ============================================================
rest_call:
    push rbp
    mov rbp, rsp
    sub rsp, 192

    mov [rbp-8], rcx       ; method
    mov [rbp-16], rdx      ; path
    mov [rbp-24], r8       ; body
    mov [rbp-32], r9       ; body length
    mov qword [rbp-56], 0  ; attempt counter

    ; Ensure we have a connection to discord.com
    cmp qword [g_hApiConnect], 0
    jne .have_conn
    lea rcx, [w_discord_host]
    call http_connect
    test rax, rax
    jz .fail
    mov [g_hApiConnect], rax
.have_conn:

    ; Build auth header (wide) from the global token
    lea rcx, [bot_token]
    lea rdx, [rc_auth_wide]
    mov r8, 512
    call make_auth_header_wide

    ; Convert path to wide
    mov rcx, [rbp-16]
    lea rdx, [rc_path_wide]
    mov r8, 1024
    call asm_to_wide

.attempt:
    ; http_request(hConnect, method, pathWide, body, bodyLen, authHeader)
    mov rcx, [g_hApiConnect]
    mov rdx, [rbp-8]
    lea r8, [rc_path_wide]
    mov r9, [rbp-24]
    mov rax, [rbp-32]
    mov [rsp+32], rax      ; body length
    lea rax, [rc_auth_wide]
    mov [rsp+40], rax      ; auth header
    call http_request

    test rax, rax
    jz .fail               ; transport failure
    mov [rbp-40], rax      ; response buffer

    mov eax, dword [g_http_status]
    mov dword [g_rest_status], eax
    cmp eax, 429
    jne .success

    ; --- Rate limited: maybe retry ---
    inc qword [rbp-56]
    cmp qword [rbp-56], 5
    jg .success            ; out of retries; hand back the 429 response

    ; Determine wait time from the body's retry_after
    mov rcx, [rbp-40]
    lea rdx, [rc_retry_key]
    call json_find_key
    test rax, rax
    jz .default_wait
    mov rcx, rax
    call parse_retry_ms
    mov [rbp-48], rax
    jmp .do_wait
.default_wait:
    mov qword [rbp-48], 1000
.do_wait:
    mov rcx, [rbp-40]
    call http_free_response
    mov rcx, [rbp-48]
    call Sleep
    jmp .attempt

.success:
    mov rax, [rbp-40]
    jmp .done
.fail:
    mov dword [g_rest_status], 0
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; rest_call_simple - rest_call but free the body and return success/failure
; Same args as rest_call.
; Returns: rax = 1 if 2xx/3xx, 0 otherwise
; ============================================================
rest_call_simple:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    call rest_call
    test rax, rax
    jz .fail
    mov rcx, rax
    call http_free_response
    mov eax, dword [g_rest_status]
    cmp eax, 400
    jae .fail
    mov eax, 1
    jmp .done
.fail:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; rest_cleanup - Close the cached REST connection (call at shutdown)
; ============================================================
rest_cleanup:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    cmp qword [g_hApiConnect], 0
    je .done
    mov rcx, [g_hApiConnect]
    call WinHttpCloseHandle
    mov qword [g_hApiConnect], 0
.done:
    mov rsp, rbp
    pop rbp
    ret
