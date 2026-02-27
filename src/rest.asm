; rest.asm - Discord REST API functions

section .data
    ; API paths
    api_gateway_path: db "/api/v10/gateway/bot", 0
    api_messages_path: db "/api/v10/channels/", 0
    api_messages_suffix: db "/messages", 0
    api_messages_reactions: db "/reactions/", 0
    api_messages_me: db "/@me", 0

    ; JSON template for sending messages
    msg_json_pre:  db '{"content":"', 0
    msg_json_post: db '"}', 0

    ; Wide path buffer for API calls
section .bss
    w_api_path_buf:     resw 512
    w_auth_header_buf:  resw 512
    rest_json_buf:      resb 4096
    rest_path_buf:      resb 512

section .text

; ============================================================
; rest_get_gateway_url - Get the Gateway WebSocket URL from Discord
; rcx = bot token (UTF-8 string)
; rdx = output buffer for URL
; r8  = output buffer size
; Returns: rax = length of URL, or 0 on failure
; ============================================================
rest_get_gateway_url:
    push rbp
    mov rbp, rsp
    sub rsp, 160

    mov [rbp-8], rcx       ; token
    mov [rbp-16], rdx      ; output buffer
    mov [rbp-24], r8       ; output size

    ; Connect to discord.com
    lea rcx, [w_discord_host]
    call http_connect
    test rax, rax
    jz .error
    mov [rbp-32], rax      ; hConnect

    ; Build auth header (wide)
    mov rcx, [rbp-8]
    lea rdx, [w_auth_header_buf]
    mov r8, 512
    call make_auth_header_wide

    ; Convert path to wide
    lea rcx, [api_gateway_path]
    lea rdx, [w_api_path_buf]
    mov r8, 512
    call asm_to_wide

    ; Make GET request
    ; http_request(hConnect, method, path, body, bodyLen, authHeader)
    mov rcx, [rbp-32]
    lea rdx, [w_method_GET]
    lea r8, [w_api_path_buf]
    xor r9, r9              ; no body
    mov qword [rsp+32], 0   ; body length = 0
    lea rax, [w_auth_header_buf]
    mov [rsp+40], rax        ; auth header
    call http_request

    test rax, rax
    jz .close

    mov [rbp-40], rax       ; response buffer

    ; Parse "url" from response JSON
    mov rcx, rax
    lea rdx, [.key_url]
    call json_find_key

    test rax, rax
    jz .free_resp

    ; Extract string value
    mov rcx, rax
    mov rdx, [rbp-16]
    mov r8, [rbp-24]
    call json_extract_string

    mov [rbp-48], rax       ; URL length

    ; Free response
    mov rcx, [rbp-40]
    call http_free_response

    ; Close connect handle
    mov rcx, [rbp-32]
    call WinHttpCloseHandle

    mov rax, [rbp-48]
    jmp .done

.free_resp:
    mov rcx, [rbp-40]
    call http_free_response
.close:
    mov rcx, [rbp-32]
    call WinHttpCloseHandle
.error:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

section .data
    .key_url: db "url", 0

section .text

; ============================================================
; rest_send_message - Send a message to a Discord channel
; rcx = bot token (UTF-8)
; rdx = channel ID (UTF-8 string)
; r8  = message content (UTF-8 string)
; Returns: rax = 1 on success, 0 on failure
; ============================================================
rest_send_message:
    push rbp
    mov rbp, rsp
    sub rsp, 192

    mov [rbp-8], rcx       ; token
    mov [rbp-16], rdx      ; channel ID
    mov [rbp-24], r8       ; message content

    ; Build path: /api/v10/channels/{channel_id}/messages
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_path]
    call asm_strcpy

    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat

    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_suffix]
    call asm_strcat

    ; Build JSON body: {"content":"<message>"}
    lea rcx, [rest_json_buf]
    lea rdx, [msg_json_pre]
    call asm_strcpy

    lea rcx, [rest_json_buf]
    mov rdx, [rbp-24]
    call asm_strcat

    lea rcx, [rest_json_buf]
    lea rdx, [msg_json_post]
    call asm_strcat

    ; Get body length
    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-32], rax      ; body length

    ; Connect to discord.com
    lea rcx, [w_discord_host]
    call http_connect
    test rax, rax
    jz .error
    mov [rbp-40], rax      ; hConnect

    ; Build auth header (wide)
    mov rcx, [rbp-8]
    lea rdx, [w_auth_header_buf]
    mov r8, 512
    call make_auth_header_wide

    ; Convert path to wide
    lea rcx, [rest_path_buf]
    lea rdx, [w_api_path_buf]
    mov r8, 512
    call asm_to_wide

    ; Make POST request
    mov rcx, [rbp-40]
    lea rdx, [w_method_POST]
    lea r8, [w_api_path_buf]
    lea r9, [rest_json_buf]
    mov rax, [rbp-32]
    mov [rsp+32], rax           ; body length
    lea rax, [w_auth_header_buf]
    mov [rsp+40], rax           ; auth header
    call http_request

    test rax, rax
    jz .close

    ; Free response (we don't need it)
    mov rcx, rax
    call http_free_response

    ; Close connect handle
    mov rcx, [rbp-40]
    call WinHttpCloseHandle

    mov eax, 1
    jmp .done

.close:
    mov rcx, [rbp-40]
    call WinHttpCloseHandle
.error:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; rest_add_reaction - Add a reaction to a message
; rcx = bot token (UTF-8)
; rdx = channel ID (UTF-8 string)
; r8  = message ID (UTF-8 string)
; r9  = emoji (UTF-8 string, URL encoded)
; Returns: rax = 1 on success, 0 on failure
; ============================================================
rest_add_reaction:
    push rbp
    mov rbp, rsp
    sub rsp, 192

    mov [rbp-8], rcx       ; token
    mov [rbp-16], rdx      ; channel ID
    mov [rbp-24], r8       ; message ID
    mov [rbp-32], r9       ; emoji

    ; Build path: /api/v10/channels/{channel_id}/messages/{message_id}/reactions/{emoji}/@me
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_path]
    call asm_strcpy

    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat

    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_suffix]
    call asm_strcat
    
    lea rcx, [rest_path_buf]
    lea rdx, [w_method_GET]  ; Need a slash, just using existing ones or adding manually
    call asm_strlen
    lea rcx, [rest_path_buf]
    add rcx, rax             ; Move to end
    mov byte [rcx], '/'
    mov byte [rcx+1], 0

    lea rcx, [rest_path_buf]
    mov rdx, [rbp-24]
    call asm_strcat

    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_reactions]
    call asm_strcat

    lea rcx, [rest_path_buf]
    mov rdx, [rbp-32]
    call asm_strcat

    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_me]
    call asm_strcat

    ; Connect to discord.com
    lea rcx, [w_discord_host]
    call http_connect
    test rax, rax
    jz .error
    mov [rbp-40], rax      ; hConnect

    ; Build auth header (wide)
    mov rcx, [rbp-8]
    lea rdx, [w_auth_header_buf]
    mov r8, 512
    call make_auth_header_wide

    ; Convert path to wide
    lea rcx, [rest_path_buf]
    lea rdx, [w_api_path_buf]
    mov r8, 512
    call asm_to_wide

    ; Make PUT request
    mov rcx, [rbp-40]
    lea rdx, [w_method_PUT]
    lea r8, [w_api_path_buf]
    xor r9, r9                  ; empty body
    mov qword [rsp+32], 0       ; body length 0
    lea rax, [w_auth_header_buf]
    mov [rsp+40], rax           ; auth header
    call http_request

    test rax, rax
    jz .close

    ; Free response (we don't need it)
    mov rcx, rax
    call http_free_response

    ; Close connect handle
    mov rcx, [rbp-40]
    call WinHttpCloseHandle

    mov eax, 1
    jmp .done

.close:
    mov rcx, [rbp-40]
    call WinHttpCloseHandle
.error:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret
