; rest_channels.asm - Channel REST endpoints

section .data
    k_recipient_id: db "recipient_id", 0

section .text

; rest_trigger_typing(rcx=channel)  POST /channels/{ch}/typing
rest_trigger_typing:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_typing]
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_get_channel(rcx=channel) -> rax=response  GET /channels/{ch}
rest_get_channel:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_channels]
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

; rest_delete_channel(rcx=channel)  DELETE /channels/{ch}
rest_delete_channel:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_channels]
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

; rest_modify_channel_name(rcx=channel, rdx=new name)  PATCH /channels/{ch}
rest_modify_channel_name:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    xor r8, r8
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_name]
    mov rdx, [rbp-16]
    call jb_key_str
    call jb_end_obj
    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-24], rax
    lea rcx, [w_method_PATCH]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-24]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_get_pinned(rcx=channel) -> rax=response  GET /channels/{ch}/pins
rest_get_pinned:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_pins]
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

; rest_create_invite(rcx=channel) -> rax=response  POST /channels/{ch}/invites
rest_create_invite:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_invites]
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_create_dm(rcx=user_id) -> rax=response  POST /users/@me/channels
rest_create_dm:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_recipient_id]
    mov rdx, [rbp-8]
    call jb_key_str
    call jb_end_obj
    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-16], rax
    lea rcx, [w_method_POST]
    lea rdx, [p_users_me_channels]
    lea r8, [rest_json_buf]
    mov r9, [rbp-16]
    call rest_call
    mov rsp, rbp
    pop rbp
    ret
