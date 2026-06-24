; rest_users.asm - User REST endpoints

section .data
    k_username:  db "username", 0
    p_my_guilds: db "/api/v10/users/@me/guilds", 0

section .text

; rest_get_current_user() -> rax=response  GET /users/@me
rest_get_current_user:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [w_method_GET]
    lea rdx, [p_users_me]
    xor r8, r8
    xor r9, r9
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_get_user(rcx=user_id) -> rax=response  GET /users/{u}
rest_get_user:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_users]
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

; rest_modify_current_user(rcx=new username)  PATCH /users/@me
rest_modify_current_user:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_username]
    mov rdx, [rbp-8]
    call jb_key_str
    call jb_end_obj
    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-16], rax
    lea rcx, [w_method_PATCH]
    lea rdx, [p_users_me]
    lea r8, [rest_json_buf]
    mov r9, [rbp-16]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_list_my_guilds() -> rax=response  GET /users/@me/guilds
rest_list_my_guilds:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [w_method_GET]
    lea rdx, [p_my_guilds]
    xor r8, r8
    xor r9, r9
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_leave_guild(rcx=guild)  DELETE /users/@me/guilds/{g}
rest_leave_guild:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_users_me_guilds]
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
