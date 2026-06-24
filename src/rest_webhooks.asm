; rest_webhooks.asm - Webhook REST endpoints

section .data
    s_webhooks: db "/webhooks", 0

section .text

; rest_create_webhook(rcx=channel, rdx=name) -> rax=response
; POST /channels/{ch}/webhooks  body {"name":"..."}
rest_create_webhook:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_webhooks]
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
    call rest_call
    mov rsp, rbp
    pop rbp
    ret

; rest_delete_webhook(rcx=webhook_id)  DELETE /webhooks/{w}
rest_delete_webhook:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_webhooks]
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

; rest_execute_webhook(rcx=webhook_id, rdx=token, r8=content)
; POST /webhooks/{w}/{token}  body {"content":"..."}
rest_execute_webhook:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    lea rcx, [p_webhooks]
    mov rdx, [rbp-8]
    lea r8, [s_slash]
    mov r9, [rbp-16]
    mov qword [rsp+32], 0
    call rc_build_path
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
