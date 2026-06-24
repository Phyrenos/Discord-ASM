; rest_app_commands.asm - Application (slash) command registration via REST
; Uses the global g_application_id / g_guild_id (defined in interactions.asm).

section .data
    s_guilds_slash: db "/guilds/", 0
    k_description:  db "description", 0

section .text

; Internal: build {"name":..,"description":..,"type":1} into rest_json_buf
; rcx = name, rdx = description ; returns rax = body length
_app_cmd_body:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_name]
    mov rdx, [rbp-8]
    call jb_key_str
    lea rcx, [k_description]
    mov rdx, [rbp-16]
    call jb_key_str
    lea rcx, [k_type]
    mov rdx, 1                 ; CHAT_INPUT
    call jb_key_int
    call jb_end_obj
    lea rcx, [rest_json_buf]
    call asm_strlen
    mov rsp, rbp
    pop rbp
    ret

; rest_register_global_command(rcx=name, rdx=description)
; POST /applications/{app}/commands
rest_register_global_command:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_applications]
    lea rdx, [g_application_id]
    lea r8, [s_commands]
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    call _app_cmd_body
    mov [rbp-24], rax
    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-24]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_register_guild_command(rcx=name, rdx=description)
; POST /applications/{app}/guilds/{guild}/commands
rest_register_guild_command:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_applications]
    lea rdx, [g_application_id]
    lea r8, [s_guilds_slash]
    lea r9, [g_guild_id]
    lea rax, [s_commands]
    mov [rsp+32], rax
    call rc_build_path
    mov rcx, [rbp-8]
    mov rdx, [rbp-16]
    call _app_cmd_body
    mov [rbp-24], rax
    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-24]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; rest_list_global_commands() -> rax=response  GET /applications/{app}/commands
rest_list_global_commands:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    lea rcx, [p_applications]
    lea rdx, [g_application_id]
    lea r8, [s_commands]
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

; rest_delete_global_command(rcx=command_id)
; DELETE /applications/{app}/commands/{id}
rest_delete_global_command:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_applications]
    lea rdx, [g_application_id]
    lea r8, [s_commands]
    lea r9, [s_slash]
    mov rax, [rbp-8]
    mov [rsp+32], rax
    call rc_build_path
    lea rcx, [w_method_DELETE]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret
