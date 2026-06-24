; interactions.asm - Slash command (application command) interaction handling
;
; Flow: INTERACTION_CREATE -> on_interaction_create parses the interaction and
; dispatches by command name to a registered handler, which replies via
; interaction_respond (POST /interactions/{id}/{token}/callback).
;
; Application/guild ids: g_application_id is captured from READY; g_guild_id is
; optional (DISCORD_GUILD_ID env) for instant guild-scoped command registration.

section .bss
    g_application_id:   resb 64
    g_guild_id:         resb 64
    g_slash_registered: resb 1

    interaction_table:  resb (MAX_INTERACTION_CMDS * 16)
    interaction_count:  resq 1

    int_id_buf:    resb 64
    int_token_buf: resb 256
    int_name_buf:  resb 64

section .data
    p_interactions: db "/api/v10/interactions/", 0
    k_token:        db "token", 0
    k_data:         db "data", 0
    k_flags:        db "flags", 0
    k_application:  db "application", 0

    ; Built-in slash command names/descriptions
    ic_name_ping:   db "ping", 0
    ic_desc_ping:   db "Replies with Pong", 0
    ic_name_info:   db "info", 0
    ic_desc_info:   db "About this assembly bot", 0
    ic_name_secret: db "secret", 0
    ic_desc_secret: db "An ephemeral reply only you can see", 0

    ; Responses
    int_resp_pong:   db "Pong! (from pure x86-64 assembly)", 0
    int_resp_info:   db "I am a Discord bot written entirely in x86-64 assembly (NASM), slash commands and all.", 0
    int_resp_secret: db "This message is ephemeral - only you can see it.", 0

    int_log_msg:     db "[Interaction] command: ", 0

section .text

; ============================================================
; register_interaction_command(rcx=name, rdx=handler)
; ============================================================
register_interaction_command:
    push rbx
    mov rax, [interaction_count]
    cmp rax, MAX_INTERACTION_CMDS
    jge .full
    shl rax, 4
    lea rbx, [interaction_table]
    add rbx, rax
    mov [rbx], rcx
    mov [rbx+8], rdx
    inc qword [interaction_count]
    mov eax, 1
    pop rbx
    ret
.full:
    xor eax, eax
    pop rbx
    ret

; ============================================================
; dispatch_interaction - look up a command name and invoke its handler
; rcx = command name, rdx = interaction id, r8 = token, r9 = d object
; handler(rcx = id, rdx = token, r8 = d)
; ============================================================
dispatch_interaction:
    push rbp
    mov rbp, rsp
    sub rsp, 80
    mov [rbp-8], rcx       ; name
    mov [rbp-16], rdx      ; id
    mov [rbp-24], r8       ; token
    mov [rbp-32], r9       ; d
    mov qword [rbp-40], 0  ; index
.loop:
    mov rax, [rbp-40]
    cmp rax, [interaction_count]
    jae .none
    shl rax, 4
    lea rcx, [interaction_table]
    add rcx, rax
    mov [rbp-48], rcx
    mov rcx, [rcx]
    mov rdx, [rbp-8]
    call asm_strcmp
    test eax, eax
    jnz .next
    mov rcx, [rbp-48]
    mov rax, [rcx+8]       ; handler
    mov rcx, [rbp-16]      ; id
    mov rdx, [rbp-24]      ; token
    mov r8, [rbp-32]       ; d
    call rax
    jmp .done
.next:
    inc qword [rbp-40]
    jmp .loop
.none:
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; on_interaction_create - INTERACTION_CREATE event handler
; rcx = d object, rdx = event name, r8 = payload
; ============================================================
on_interaction_create:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx       ; d

    ; only handle APPLICATION_COMMAND (type 2)
    mov rcx, [rbp-8]
    lea rdx, [k_type]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    call json_extract_int
    cmp rax, INTERACTION_TYPE_APPLICATION_COMMAND
    jne .done

    ; interaction id
    mov rcx, [rbp-8]
    lea rdx, [key_id]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [int_id_buf]
    mov r8, 64
    call json_extract_string

    ; interaction token
    mov rcx, [rbp-8]
    lea rdx, [k_token]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [int_token_buf]
    mov r8, 256
    call json_extract_string

    ; command name = d.data.name
    mov rcx, [rbp-8]
    lea rdx, [k_data]
    lea r8, [k_name]
    call json_find_nested_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [int_name_buf]
    mov r8, 64
    call json_extract_string

    ; log + dispatch
    lea rcx, [int_log_msg]
    call print_console
    lea rcx, [int_name_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    lea rcx, [int_name_buf]
    lea rdx, [int_id_buf]
    lea r8, [int_token_buf]
    mov r9, [rbp-8]
    call dispatch_interaction

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; interaction_respond - POST an interaction callback
; rcx = interaction id, rdx = token, r8 = callback type, r9 = content,
; [rsp+32] = flags (64 = ephemeral, 0 = normal)
; ============================================================
interaction_respond:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    mov [rbp-8], rcx       ; id
    mov [rbp-16], rdx      ; token
    mov [rbp-24], r8       ; callback type
    mov [rbp-32], r9       ; content
    mov rax, [rbp+48]      ; flags
    mov [rbp-40], rax

    ; Path: /api/v10/interactions/{id}/{token}/callback
    lea rcx, [rest_path_buf]
    lea rdx, [p_interactions]
    call asm_strcpy
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-8]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [s_slash]
    call asm_strcat
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [s_callback]
    call asm_strcat

    ; Body: {"type":<cbtype>,"data":{"content":"<content>","flags":<flags>}}
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_type]
    mov rdx, [rbp-24]
    call jb_key_int
    lea rcx, [k_data]
    call jb_begin_key_obj
    lea rcx, [k_content]
    mov rdx, [rbp-32]
    call jb_key_str
    lea rcx, [k_flags]
    mov rdx, [rbp-40]
    call jb_key_int
    call jb_end_obj
    call jb_end_obj

    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-48], rax

    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-48]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; Built-in interaction handlers - handler(rcx=id, rdx=token, r8=d)
; ============================================================
int_cmd_ping:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    mov r8, INTERACTION_CALLBACK_CHANNEL_MESSAGE
    lea r9, [int_resp_pong]
    mov qword [rsp+32], 0
    call interaction_respond
    mov rsp, rbp
    pop rbp
    ret

int_cmd_info:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    mov r8, INTERACTION_CALLBACK_CHANNEL_MESSAGE
    lea r9, [int_resp_info]
    mov qword [rsp+32], 0
    call interaction_respond
    mov rsp, rbp
    pop rbp
    ret

int_cmd_secret:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    mov r8, INTERACTION_CALLBACK_CHANNEL_MESSAGE
    lea r9, [int_resp_secret]
    mov qword [rsp+32], MESSAGE_FLAG_EPHEMERAL
    call interaction_respond
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; register_all_interactions - register handlers + the INTERACTION_CREATE event
; ============================================================
register_all_interactions:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    lea rcx, [ic_name_ping]
    lea rdx, [int_cmd_ping]
    call register_interaction_command
    lea rcx, [ic_name_info]
    lea rdx, [int_cmd_info]
    call register_interaction_command
    lea rcx, [ic_name_secret]
    lea rdx, [int_cmd_secret]
    call register_interaction_command

    lea rcx, [ev_name_interaction]
    lea rdx, [on_interaction_create]
    call register_event_handler

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; register_one_slash(rcx=name, rdx=description)
; Registers as a guild command if DISCORD_GUILD_ID is set, else global.
; ============================================================
register_one_slash:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    cmp byte [g_guild_id], 0
    je .global
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    call rest_register_guild_command
    jmp .done
.global:
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    call rest_register_global_command
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; register_slash_commands_with_discord - one-time registration (called on READY)
; Requires g_application_id to be populated.
; ============================================================
register_slash_commands_with_discord:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    cmp byte [g_slash_registered], 0
    jne .done
    cmp byte [g_application_id], 0
    je .done                       ; no application id yet
    mov byte [g_slash_registered], 1

    lea rcx, [ic_name_ping]
    lea rdx, [ic_desc_ping]
    call register_one_slash
    lea rcx, [ic_name_info]
    lea rdx, [ic_desc_info]
    call register_one_slash
    lea rcx, [ic_name_secret]
    lea rdx, [ic_desc_secret]
    call register_one_slash
.done:
    mov rsp, rbp
    pop rbp
    ret
