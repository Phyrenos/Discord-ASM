; command_handlers.asm - Command implementations and registration
; Included by bot.asm

section .data
    ; Built-in command names
    cmd_name_ping:  db "ping", 0
    cmd_name_hello: db "hello", 0
    cmd_name_info:  db "info", 0
    cmd_name_react: db "react", 0
    cmd_name_gay: db "gay", 0

    ; Command responses
    resp_pong:      db "Pong!", 0
    ; Hello command
    resp_hello_pre: db "Hello, <@", 0
    resp_hello_suf: db ">!", 0

    ; Gay command
    resp_gay_pre: db ">! You are ", 0
    resp_gay_suf: db "% gay!", 0
    temp_num_buf: db 0, 0, 0, 0, 0, 0, 0, 0  ; 8 bytes of zeros
    resp_info:      db "I am a Discord bot written in pure x86-64 assembly (NASM)!", 0
    
    ; Reaction emoji (URL encoded: %F0%9F%91%8D = thumbs up)
    emoji_thumbsup: db "%F0%9F%91%8D", 0

section .text


get_random_percent:
    rdrand rax              ; Get hardware random number
    jnc get_random_percent  ; If CF=0, hardware was busy; try again
    xor rdx, rdx            ; Clear rdx for division
    mov rcx, 101            ; Range 0-100
    div rcx                 ; rax / 101, remainder in rdx
    mov rax, rdx            ; Move remainder (0-100) to rax
    ret

; ============================================================
; Built-in command handlers
; Signature: void handler(rcx=channel_id, rdx=args, r8=author_username, r9=message_id, [rsp+40]=author_id)
; ============================================================

; !ping - Reply with "Pong!"
cmd_handler_ping:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx       ; channel_id

    ; Send "Pong!" to channel
    lea rcx, [bot_token]
    mov rdx, [rbp-8]
    lea r8, [resp_pong]
    call rest_send_message

    mov rsp, rbp
    pop rbp
    ret

; !gay - reply with how gay they are
cmd_handler_gay:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx        ; channel_id
    mov [rbp-16], r8       ; author_username

    mov rax, [rbp+48]      ; 5th arg (author_id) is at [rbp+48]
    mov [rbp-32], rax      ; author_id

    ; 1. Generate the random number
    call get_random_percent
    mov [rbp-24], rax       ; Store the result (e.g., 69)

    ; 2. Build response: "Hello, <author>! You are <num>% gay."
    lea rcx, [cmd_resp_buf]
    lea rdx, [resp_hello_pre] ; "Hello, "
    call asm_strcpy

    lea rcx, [cmd_resp_buf]
    mov rdx, [rbp-32]       ; <author>
    call asm_strcat

    lea rcx, [cmd_resp_buf]
    lea rdx, [resp_gay_pre]     ; "! You are "
    call asm_strcat

    ; 3. Convert number to string and append
    mov rcx, [rbp-24]       ; The random number
    lea rdx, [temp_num_buf] ; A small scratch buffer
    call asm_itoa           ; Your integer-to-ascii function
    
    lea rcx, [cmd_resp_buf]
    lea rdx, [temp_num_buf]
    call asm_strcat

    lea rcx, [cmd_resp_buf]
    lea rdx, [resp_gay_suf] ; "% gay!"
    call asm_strcat

    ; 4. Send message
    lea rcx, [bot_token]
    mov rdx, [rbp-8]
    lea r8, [cmd_resp_buf]
    call rest_send_message

    mov rsp, rbp
    pop rbp
    ret
    
; !hello - Reply with "Hello, <username>!"
cmd_handler_hello:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx       ; channel_id
    mov [rbp-16], r8       ; author_username

    mov rax, [rbp+48]      ; 5th arg (author_id) is at [rbp+48]
    mov [rbp-32], rax      ; author_id

    ; Build response: "Hello, <author_username>!"
    lea rcx, [cmd_resp_buf]
    lea rdx, [resp_hello_pre]
    call asm_strcpy

    lea rcx, [cmd_resp_buf]
    mov rdx, [rbp-32]
    call asm_strcat

    lea rcx, [cmd_resp_buf]
    lea rdx, [resp_hello_suf]
    call asm_strcat

    ; Send message
    lea rcx, [bot_token]
    mov rdx, [rbp-8]
    lea r8, [cmd_resp_buf]
    call rest_send_message

    mov rsp, rbp
    pop rbp
    ret

; !info - Reply with bot info
cmd_handler_info:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx       ; channel_id

    lea rcx, [bot_token]
    mov rdx, [rbp-8]
    lea r8, [resp_info]
    call rest_send_message

    mov rsp, rbp
    pop rbp
    ret

; !react - React to the user's message with a thumbs up
cmd_handler_react:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx       ; channel_id
    mov [rbp-16], r9       ; message_id

    lea rcx, [bot_token]
    mov rdx, [rbp-8]
    mov r8, [rbp-16]
    lea r9, [emoji_thumbsup]
    call rest_add_reaction

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; register_all_commands - Register all commands
; ============================================================
register_all_commands:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; Register !ping
    lea rcx, [cmd_name_ping]
    lea rdx, [cmd_handler_ping]
    call register_command

    lea rcx, [msg_cmd_reg]
    call print_console
    lea rcx, [cmd_name_ping]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    ; Register !gay
    lea rcx, [cmd_name_gay]
    lea rdx, [cmd_handler_gay]
    call register_command

    lea rcx, [msg_cmd_reg]
    call print_console
    lea rcx, [cmd_name_gay]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    ; Register !hello
    lea rcx, [cmd_name_hello]
    lea rdx, [cmd_handler_hello]
    call register_command

    lea rcx, [msg_cmd_reg]
    call print_console
    lea rcx, [cmd_name_hello]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    ; Register !info
    lea rcx, [cmd_name_info]
    lea rdx, [cmd_handler_info]
    call register_command

    lea rcx, [msg_cmd_reg]
    call print_console
    lea rcx, [cmd_name_info]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    ; Register !react
    lea rcx, [cmd_name_react]
    lea rdx, [cmd_handler_react]
    call register_command

    lea rcx, [msg_cmd_reg]
    call print_console
    lea rcx, [cmd_name_react]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    mov rsp, rbp
    pop rbp
    ret
