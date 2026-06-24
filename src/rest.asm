; rest.asm - Core Discord REST endpoints (message, reaction, gateway)
; Thin wrappers over rest_call / rest_call_simple (see rest_core.asm).
;
; Note: the leading `token` argument is kept for source compatibility with the
; existing command handlers, but is ignored - rest_call authenticates using the
; global bot_token.

section .data
    ; API paths
    api_gateway_path:       db "/api/v10/gateway/bot", 0
    api_messages_path:      db "/api/v10/channels/", 0
    api_messages_suffix:    db "/messages", 0
    api_messages_reactions: db "/reactions/", 0
    api_messages_me:        db "/@me", 0

    ; ---- Shared path prefixes/segments reused across rest_*.asm modules ----
    p_channels:     db "/api/v10/channels/", 0
    p_guilds:       db "/api/v10/guilds/", 0
    p_users:        db "/api/v10/users/", 0
    p_webhooks:     db "/api/v10/webhooks/", 0
    p_applications: db "/api/v10/applications/", 0
    p_invites:      db "/api/v10/invites/", 0
    p_users_me:     db "/api/v10/users/@me", 0
    p_users_me_channels: db "/api/v10/users/@me/channels", 0
    p_users_me_guilds:   db "/api/v10/users/@me/guilds/", 0
    s_messages_slash: db "/messages/", 0
    s_messages:     db "/messages", 0
    s_typing:       db "/typing", 0
    s_pins:         db "/pins", 0
    s_pins_slash:   db "/pins/", 0
    s_members:      db "/members", 0
    s_members_slash: db "/members/", 0
    s_roles:        db "/roles", 0
    s_roles_slash:  db "/roles/", 0
    s_bans:         db "/bans", 0
    s_bans_slash:   db "/bans/", 0
    s_channels:     db "/channels", 0
    s_invites:      db "/invites", 0
    s_emojis:       db "/emojis", 0
    s_emojis_slash: db "/emojis/", 0
    s_prune:        db "/prune", 0
    s_audit_logs:   db "/audit-logs", 0
    s_bulk_delete:  db "/messages/bulk-delete", 0
    s_crosspost:    db "/crosspost", 0
    s_threads:      db "/threads", 0
    s_commands:     db "/commands", 0
    s_callback:     db "/callback", 0
    s_slash:        db "/", 0

    ; JSON keys
    k_content:  db "content", 0
    k_url:      db "url", 0
    k_name:     db "name", 0
    k_nick:     db "nick", 0
    k_reason:   db "reason", 0
    k_topic:    db "topic", 0

section .bss
    rest_json_buf:  resb 4096       ; shared REST request-body buffer
    rest_path_buf:  resb 1024       ; shared REST path buffer
    rest_emoji_buf: resb 256        ; URL-encoded emoji

section .text

; ============================================================
; rest_get_gateway_url - GET /gateway/bot and extract "url"
; rcx = token (ignored), rdx = output buffer, r8 = output size
; Returns: rax = URL length, or 0 on failure
; ============================================================
rest_get_gateway_url:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    mov [rbp-16], rdx      ; output buffer
    mov [rbp-24], r8       ; output size

    lea rcx, [w_method_GET]
    lea rdx, [api_gateway_path]
    xor r8, r8
    xor r9, r9
    call rest_call
    test rax, rax
    jz .err
    mov [rbp-40], rax      ; response

    mov rcx, rax
    lea rdx, [k_url]
    call json_find_key
    test rax, rax
    jz .free

    mov rcx, rax
    mov rdx, [rbp-16]
    mov r8, [rbp-24]
    call json_extract_string
    mov [rbp-48], rax

    mov rcx, [rbp-40]
    call http_free_response
    mov rax, [rbp-48]
    jmp .done
.free:
    mov rcx, [rbp-40]
    call http_free_response
.err:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; rest_send_message - POST a message to a channel
; rcx = token (ignored), rdx = channel ID, r8 = content (UTF-8)
; Returns: rax = 1 on success, 0 otherwise
; ============================================================
rest_send_message:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    mov [rbp-16], rdx      ; channel ID
    mov [rbp-24], r8       ; content

    ; Path: /api/v10/channels/{id}/messages
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_path]
    call asm_strcpy
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_suffix]
    call asm_strcat

    ; Body: {"content":"<escaped>"}
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_content]
    mov rdx, [rbp-24]
    call jb_key_str
    call jb_end_obj

    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-32], rax

    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-32]
    call rest_call_simple

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; rest_add_reaction - PUT a reaction on a message
; rcx = token (ignored), rdx = channel ID, r8 = message ID, r9 = emoji (UTF-8)
; Returns: rax = 1 on success, 0 otherwise
; ============================================================
rest_add_reaction:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    mov [rbp-16], rdx      ; channel
    mov [rbp-24], r8       ; message
    mov [rbp-32], r9       ; emoji

    ; URL-encode the emoji
    mov rcx, [rbp-32]
    lea rdx, [rest_emoji_buf]
    mov r8, 256
    call asm_url_encode

    ; Path: /api/v10/channels/{ch}/messages/{msg}/reactions/{emoji}/@me
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
    mov dl, '/'
    call asm_strcat_char
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-24]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_reactions]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [rest_emoji_buf]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_me]
    call asm_strcat

    lea rcx, [w_method_PUT]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; rc_build_path - Concatenate up to 5 string pieces into rest_path_buf
; rcx=p1, rdx=p2, r8=p3, r9=p4, [rsp+32]=p5  (NULL terminates the list early)
; Returns: rax = rest_path_buf
; ============================================================
rc_build_path:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    mov [rbp-32], r9
    mov rax, [rbp+48]      ; 5th arg
    mov [rbp-40], rax

    lea rcx, [rest_path_buf]
    mov rdx, [rbp-8]
    call asm_strcpy

    cmp qword [rbp-16], 0
    je .done
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat

    cmp qword [rbp-24], 0
    je .done
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-24]
    call asm_strcat

    cmp qword [rbp-32], 0
    je .done
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-32]
    call asm_strcat

    cmp qword [rbp-40], 0
    je .done
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-40]
    call asm_strcat

.done:
    lea rax, [rest_path_buf]
    mov rsp, rbp
    pop rbp
    ret
