; rest_misc.asm - Emoji, invite, thread and misc guild REST endpoints

section .data
    k_thread_name: db "name", 0

section .text

; rest_list_guild_emojis(rcx=guild) -> rax=response  GET /guilds/{g}/emojis
rest_list_guild_emojis:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_emojis]
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_GET]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_delete_emoji(rcx=guild, rdx=emoji_id)  DELETE /guilds/{g}/emojis/{e}
rest_delete_emoji:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_emojis_slash]
    mov r9, [rbp-16]
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_DELETE]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_get_invite(rcx=code) -> rax=response  GET /invites/{code}
rest_get_invite:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_invites]
    mov rdx, [rbp-8]
    xor r8, r8
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_GET]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_delete_invite(rcx=code)  DELETE /invites/{code}
rest_delete_invite:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_invites]
    mov rdx, [rbp-8]
    xor r8, r8
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_DELETE]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_get_prune_count(rcx=guild) -> rax=response  GET /guilds/{g}/prune
rest_get_prune_count:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_prune]
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_GET]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_start_thread(rcx=channel, rdx=msg_id, r8=name) -> rax=response
; POST /channels/{ch}/messages/{id}/threads  body {"name":"..."}
rest_start_thread:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_messages_slash]
    mov r9, [rbp-16]
    lea rax, [s_threads]
    mov [rsp+32], rax
    call rc_build_path
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_thread_name]
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
    call rest_call
    mov rsp, rbp
    pop rbp
    ret
