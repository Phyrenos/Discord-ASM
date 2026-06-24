; events.asm - Gateway dispatch-event table and handlers
;
; Mirrors the prefix-command table (commands.asm): handlers register by event
; name and the gateway's DISPATCH path looks them up. Handler signature:
;   void handler(rcx = pointer to the event's "d" object,
;                rdx = event name string,
;                r8  = pointer to the full gateway payload)
;
; HELLO / READY / RESUMED stay in gateway.asm because they own connection state.

section .bss
    event_table:    resb (MAX_EVENTS * 16)   ; (name_ptr, handler_ptr) pairs
    event_count:    resq 1

    ; MESSAGE_CREATE scratch
    ev_channel_buf:  resb MAX_CHANNEL_ID_LEN
    ev_msgid_buf:    resb MAX_CHANNEL_ID_LEN
    ev_content_buf:  resb MAX_MESSAGE_LEN
    ev_author_buf:   resb 128
    ev_authorid_buf: resb 128

section .data
    ; Event name strings (registered with register_event_handler)
    ev_name_message_create:  db "MESSAGE_CREATE", 0
    ev_name_message_update:  db "MESSAGE_UPDATE", 0
    ev_name_message_delete:  db "MESSAGE_DELETE", 0
    ev_name_reaction_add:    db "MESSAGE_REACTION_ADD", 0
    ev_name_reaction_remove: db "MESSAGE_REACTION_REMOVE", 0
    ev_name_guild_create:    db "GUILD_CREATE", 0
    ev_name_guild_delete:    db "GUILD_DELETE", 0
    ev_name_member_add:      db "GUILD_MEMBER_ADD", 0
    ev_name_member_remove:   db "GUILD_MEMBER_REMOVE", 0
    ev_name_channel_create:  db "CHANNEL_CREATE", 0
    ev_name_channel_delete:  db "CHANNEL_DELETE", 0
    ev_name_typing_start:    db "TYPING_START", 0
    ev_name_interaction:     db "INTERACTION_CREATE", 0

    ; Generic event log strings
    ev_log_generic:   db "[Event] handled: ", 0

section .text

; ============================================================
; register_event_handler - Register a handler for a dispatch event name
; rcx = event name string, rdx = handler function pointer
; Returns: rax = 1 on success, 0 if table full
; ============================================================
register_event_handler:
    push rbx
    mov rax, [event_count]
    cmp rax, MAX_EVENTS
    jge .full
    shl rax, 4
    lea rbx, [event_table]
    add rbx, rax
    mov [rbx], rcx
    mov [rbx+8], rdx
    inc qword [event_count]
    mov eax, 1
    pop rbx
    ret
.full:
    xor eax, eax
    pop rbx
    ret

; ============================================================
; dispatch_event - Look up an event name and invoke its handler
; rcx = event name, rdx = d object pointer, r8 = full payload
; ============================================================
dispatch_event:
    push rbp
    mov rbp, rsp
    sub rsp, 80
    mov [rbp-8], rcx       ; event name
    mov [rbp-16], rdx      ; d pointer
    mov [rbp-24], r8       ; payload
    mov qword [rbp-32], 0  ; index
.loop:
    mov rax, [rbp-32]
    cmp rax, [event_count]
    jae .none
    shl rax, 4
    lea rcx, [event_table]
    add rcx, rax
    mov [rbp-40], rcx      ; entry pointer
    mov rcx, [rcx]         ; registered name
    mov rdx, [rbp-8]       ; incoming event name
    call asm_strcmp
    test eax, eax
    jnz .next
    ; match - call handler(d, name, payload)
    mov rcx, [rbp-40]
    mov rax, [rcx+8]       ; handler ptr
    mov rcx, [rbp-16]      ; d pointer
    mov rdx, [rbp-8]       ; event name
    mov r8, [rbp-24]       ; payload
    call rax
    jmp .done
.next:
    inc qword [rbp-32]
    jmp .loop
.none:
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; ev_log - small helper: print "[Event] handled: <name>\n"
; rdx = event name
; ============================================================
ev_log:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rdx
    lea rcx, [ev_log_generic]
    call print_console
    mov rcx, [rbp-8]
    call print_console
    lea rcx, [gw_newline]
    call print_console
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; ev_on_message_create - Parse a message and dispatch to the command system
; rcx = d object (the message), rdx = event name, r8 = payload
; ============================================================
ev_on_message_create:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    mov [rbp-8], rcx       ; message object

    ; channel_id
    mov rcx, [rbp-8]
    lea rdx, [key_channel_id]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [ev_channel_buf]
    mov r8, MAX_CHANNEL_ID_LEN
    call json_extract_string

    ; message id
    mov rcx, [rbp-8]
    lea rdx, [key_id]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [ev_msgid_buf]
    mov r8, MAX_CHANNEL_ID_LEN
    call json_extract_string

    ; content
    mov rcx, [rbp-8]
    lea rdx, [key_content]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [ev_content_buf]
    mov r8, MAX_MESSAGE_LEN
    call json_extract_string

    ; author object
    mov rcx, [rbp-8]
    lea rdx, [key_author]
    call json_find_key
    test rax, rax
    jz .no_author
    mov [rbp-16], rax      ; author object

    ; bot? skip bot authors
    mov rcx, rax
    lea rdx, [key_bot]
    call json_find_key
    test rax, rax
    jz .not_bot
    mov rcx, rax
    call json_extract_bool
    test eax, eax
    jnz .done              ; skip bot messages
.not_bot:
    ; author id
    mov rcx, [rbp-16]
    lea rdx, [key_id]
    call json_find_key
    test rax, rax
    jz .skip_aid
    mov rcx, rax
    lea rdx, [ev_authorid_buf]
    mov r8, 128
    call json_extract_string
    jmp .aid_done
.skip_aid:
    mov byte [ev_authorid_buf], 0
.aid_done:
    ; username
    mov rcx, [rbp-16]
    lea rdx, [key_username]
    call json_find_key
    test rax, rax
    jz .no_author
    mov rcx, rax
    lea rdx, [ev_author_buf]
    mov r8, 128
    call json_extract_string
    jmp .dispatch

.no_author:
    mov byte [ev_author_buf], 0
    mov byte [ev_authorid_buf], 0

.dispatch:
    lea rax, [ev_authorid_buf]
    mov [rsp+32], rax            ; 5th arg (author_id)
    lea rcx, [ev_channel_buf]
    lea rdx, [ev_content_buf]
    lea r8, [ev_author_buf]
    lea r9, [ev_msgid_buf]
    call dispatch_command

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; register_all_events - register the built-in event handlers
; Additional handlers (Phase C) are registered here.
; ============================================================
register_all_events:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    lea rcx, [ev_name_message_create]
    lea rdx, [ev_on_message_create]
    call register_event_handler

    lea rcx, [ev_name_guild_create]
    lea rdx, [ev_on_guild_create]
    call register_event_handler

    lea rcx, [ev_name_member_add]
    lea rdx, [ev_on_member_add]
    call register_event_handler

    lea rcx, [ev_name_reaction_add]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_reaction_remove]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_message_update]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_message_delete]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_guild_delete]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_member_remove]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_channel_create]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_channel_delete]
    lea rdx, [ev_on_generic]
    call register_event_handler

    lea rcx, [ev_name_typing_start]
    lea rdx, [ev_on_generic]
    call register_event_handler

    mov rsp, rbp
    pop rbp
    ret

section .bss
    ev_name_scratch: resb 128

section .data
    k_user:       db "user", 0
    ev_guild_msg: db "[Event] guild available: ", 0
    ev_member_msg: db "[Event] member joined: ", 0

section .text

; ------------------------------------------------------------
; ev_on_generic - default handler: just logs the event name
; rcx = d, rdx = name, r8 = payload
; ------------------------------------------------------------
ev_on_generic:
    jmp ev_log

; ------------------------------------------------------------
; ev_on_guild_create - log the guild name
; rcx = d (guild object)
; ------------------------------------------------------------
ev_on_guild_create:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov rcx, [rbp-8]
    lea rdx, [k_name]
    call json_find_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [ev_name_scratch]
    mov r8, 128
    call json_extract_string
    lea rcx, [ev_guild_msg]
    call print_console
    lea rcx, [ev_name_scratch]
    call print_console
    lea rcx, [gw_newline]
    call print_console
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; ev_on_member_add - log the joining member's username (d.user.username)
; rcx = d
; ------------------------------------------------------------
ev_on_member_add:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov rcx, [rbp-8]
    lea rdx, [k_user]
    lea r8, [key_username]
    call json_find_nested_key
    test rax, rax
    jz .done
    mov rcx, rax
    lea rdx, [ev_name_scratch]
    mov r8, 128
    call json_extract_string
    lea rcx, [ev_member_msg]
    call print_console
    lea rcx, [ev_name_scratch]
    call print_console
    lea rcx, [gw_newline]
    call print_console
.done:
    mov rsp, rbp
    pop rbp
    ret
