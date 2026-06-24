; rest_messages.asm - Message + reaction REST endpoints
; All thin wrappers over rc_build_path + rest_call / rest_call_simple.

section .text

; ------------------------------------------------------------
; rest_edit_message(rcx=channel, rdx=msg_id, r8=new content)
; PATCH /channels/{ch}/messages/{id}  body {"content":"..."}
; ------------------------------------------------------------
rest_edit_message:
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

    lea rcx, [w_method_PATCH]
    lea rdx, [rest_path_buf]
    lea r8, [rest_json_buf]
    mov r9, [rbp-32]
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; rest_delete_message(rcx=channel, rdx=msg_id)
; DELETE /channels/{ch}/messages/{id}
; ------------------------------------------------------------
rest_delete_message:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_messages_slash]
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

; ------------------------------------------------------------
; rest_get_message(rcx=channel, rdx=msg_id) -> rax=response buf (caller frees)
; GET /channels/{ch}/messages/{id}
; ------------------------------------------------------------
rest_get_message:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_messages_slash]
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

; ------------------------------------------------------------
; rest_get_channel_messages(rcx=channel) -> rax=response buf (caller frees)
; GET /channels/{ch}/messages
; ------------------------------------------------------------
rest_get_channel_messages:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_messages]
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

; ------------------------------------------------------------
; rest_pin_message(rcx=channel, rdx=msg_id)  PUT /channels/{ch}/pins/{id}
; ------------------------------------------------------------
rest_pin_message:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_pins_slash]
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

; ------------------------------------------------------------
; rest_unpin_message(rcx=channel, rdx=msg_id)  DELETE /channels/{ch}/pins/{id}
; ------------------------------------------------------------
rest_unpin_message:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_pins_slash]
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

; ------------------------------------------------------------
; rest_crosspost_message(rcx=channel, rdx=msg_id)
; POST /channels/{ch}/messages/{id}/crosspost
; ------------------------------------------------------------
rest_crosspost_message:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_messages_slash]
    mov r9, [rbp-16]
    lea rax, [s_crosspost]
    mov [rsp+32], rax
    call rc_build_path
    lea rcx, [w_method_POST]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; rest_remove_own_reaction(rcx=channel, rdx=msg_id, r8=emoji)
; DELETE /channels/{ch}/messages/{id}/reactions/{emoji}/@me
; ------------------------------------------------------------
rest_remove_own_reaction:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    ; encode emoji into rest_emoji_buf
    mov rcx, [rbp-24]
    lea rdx, [rest_emoji_buf]
    mov r8, 256
    call asm_url_encode
    ; path
    lea rcx, [rest_path_buf]
    lea rdx, [p_channels]
    call asm_strcpy
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-8]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [s_messages_slash]
    call asm_strcat
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
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
    lea rcx, [w_method_DELETE]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; rest_remove_all_reactions(rcx=channel, rdx=msg_id)
; DELETE /channels/{ch}/messages/{id}/reactions
; ------------------------------------------------------------
rest_remove_all_reactions:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [rest_path_buf]
    lea rdx, [p_channels]
    call asm_strcpy
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-8]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [s_messages_slash]
    call asm_strcat
    lea rcx, [rest_path_buf]
    mov rdx, [rbp-16]
    call asm_strcat
    lea rcx, [rest_path_buf]
    lea rdx, [api_messages_reactions]
    call asm_strcat
    ; trim trailing slash of "/reactions/" -> "/reactions"
    lea rcx, [rest_path_buf]
    call asm_strlen
    lea rcx, [rest_path_buf]
    mov byte [rcx+rax-1], 0
    lea rcx, [w_method_DELETE]
    lea rdx, [rest_path_buf]
    xor r8, r8
    xor r9, r9
    call rest_call_simple
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------------------------------------
; rest_bulk_delete(rcx=channel, rdx=raw JSON array of message id strings)
; POST /channels/{ch}/messages/bulk-delete  body {"messages":[...]}
; ------------------------------------------------------------
rest_bulk_delete:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    lea rcx, [p_channels]
    mov rdx, [rbp-8]
    lea r8, [s_bulk_delete]
    xor r9, r9
    mov qword [rsp+32], 0
    call rc_build_path
    lea rcx, [rest_json_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_messages_key]
    mov rdx, [rbp-16]
    call jb_key_raw
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

section .data
    k_messages_key: db "messages", 0
