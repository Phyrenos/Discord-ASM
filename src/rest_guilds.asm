; rest_guilds.asm - Guild, member, role and ban REST endpoints

section .text

; rest_get_guild(rcx=guild) -> rax=response  GET /guilds/{g}
rest_get_guild:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
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

; rest_list_guild_channels(rcx=guild) -> rax=response  GET /guilds/{g}/channels
rest_list_guild_channels:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_channels]
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

; rest_get_member(rcx=guild, rdx=user) -> rax=response  GET /guilds/{g}/members/{u}
rest_get_member:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_members_slash]
    mov r9, [rbp-16]
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

; rest_list_members(rcx=guild) -> rax=response  GET /guilds/{g}/members
rest_list_members:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_members]
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

; rest_set_nick(rcx=guild, rdx=user, r8=nick)  PATCH /guilds/{g}/members/{u}
rest_set_nick:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_members_slash]
    mov r9, [rbp-16]
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_nick]
    mov rdx, [rbp-24]
    call jb_key_str
    call jb_end_obj
    lea rcx, [rest_json_buf]
    call asm_strlen
    mov [rbp-32], rax
    lea rcx, [w_method_PATCH]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-32]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; Internal: build /guilds/{g}/members/{u}/roles/{r} into rest_path_buf
; rcx=guild, rdx=user, r8=role
_build_member_role_path:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    lea rcx, [rest_path_buf]
    lea rdx, [p_guilds]
    call asm_strcpy
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-8]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [s_members_slash]
    call asm_strcat
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [s_roles_slash]
    call asm_strcat
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-24]
    call asm_strcat
    mov rsp, rbp
    pop rbp
    ret

; rest_add_member_role(rcx=guild, rdx=user, r8=role)  PUT
rest_add_member_role:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    call _build_member_role_path
    lea rcx, [w_method_PUT]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_remove_member_role(rcx=guild, rdx=user, r8=role)  DELETE
rest_remove_member_role:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    call _build_member_role_path
    lea rcx, [w_method_DELETE]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_kick_member(rcx=guild, rdx=user)  DELETE /guilds/{g}/members/{u}
rest_kick_member:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_members_slash]
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

; rest_ban_member(rcx=guild, rdx=user)  PUT /guilds/{g}/bans/{u}
rest_ban_member:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_bans_slash]
    mov r9, [rbp-16]
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [w_method_PUT]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_unban_member(rcx=guild, rdx=user)  DELETE /guilds/{g}/bans/{u}
rest_unban_member:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_bans_slash]
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

; rest_list_roles(rcx=guild) -> rax=response  GET /guilds/{g}/roles
rest_list_roles:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_roles]
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

; rest_create_role(rcx=guild, rdx=name)  POST /guilds/{g}/roles
rest_create_role:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_roles]
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
    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-24]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_delete_role(rcx=guild, rdx=role)  DELETE /guilds/{g}/roles/{r}
rest_delete_role:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_roles_slash]
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

; rest_get_audit_log(rcx=guild) -> rax=response  GET /guilds/{g}/audit-logs
rest_get_audit_log:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_guilds]
    mov rdx, [rbp-8]
    lea r8, [s_audit_logs]
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
