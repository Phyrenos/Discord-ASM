; gateway_send.asm - Gateway send-side opcodes (presence, members, voice)
; Built with the JSON builder and sent over the existing WebSocket.

section .bss
    gws_buf: resb MAX_JSON_PAYLOAD     ; gateway send-payload scratch

section .data
    k_op:         db "op", 0
    k_dd:         db "d", 0
    k_since:      db "since", 0
    k_activities: db "activities", 0
    k_status:     db "status", 0
    k_afk:        db "afk", 0
    k_type:       db "type", 0
    k_guild_id:   db "guild_id", 0
    k_query:      db "query", 0
    k_limit:      db "limit", 0
    k_channel_id2: db "channel_id", 0
    k_self_mute:  db "self_mute", 0
    k_self_deaf:  db "self_deaf", 0

section .text

; ============================================================
; ws_send_json - Send a null-terminated JSON string over the gateway socket
; rcx = buffer
; ============================================================
ws_send_json:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], rcx
    call asm_strlen
    mov rdx, rax
    mov rcx, [rbp-8]
    call ws_send
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; gateway_update_presence - Send an op 3 Presence Update
; rcx = status string ("online"/"idle"/"dnd"/"invisible")
; rdx = activity text
; r8  = activity type (0=Playing,1=Streaming,2=Listening,3=Watching,5=Competing)
; ============================================================
gateway_update_presence:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx       ; status
    mov [rbp-16], rdx      ; activity
    mov [rbp-24], r8       ; type

    lea rcx, [gws_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_op]
    mov rdx, GATEWAY_OP_PRESENCE_UPDATE
    call jb_key_int
    lea rcx, [k_dd]
    call jb_begin_key_obj
    lea rcx, [k_since]
    xor rdx, rdx
    call jb_key_int
    lea rcx, [k_activities]
    call jb_begin_key_arr
    call jb_begin_obj
    lea rcx, [k_name]
    mov rdx, [rbp-16]
    call jb_key_str
    lea rcx, [k_type]
    mov rdx, [rbp-24]
    call jb_key_int
    call jb_end_obj
    call jb_end_arr
    lea rcx, [k_status]
    mov rdx, [rbp-8]
    call jb_key_str
    lea rcx, [k_afk]
    xor rdx, rdx
    call jb_key_bool
    call jb_end_obj        ; close d
    call jb_end_obj        ; close root

    lea rcx, [gws_buf]
    call ws_send_json
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; gateway_request_guild_members - Send an op 8 Request Guild Members
; rcx = guild id, rdx = query string (e.g. "" for all), r8 = limit
; ============================================================
gateway_request_guild_members:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8

    lea rcx, [gws_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_op]
    mov rdx, GATEWAY_OP_REQUEST_GUILD_MEMBERS
    call jb_key_int
    lea rcx, [k_dd]
    call jb_begin_key_obj
    lea rcx, [k_guild_id]
    mov rdx, [rbp-8]
    call jb_key_str
    lea rcx, [k_query]
    mov rdx, [rbp-16]
    call jb_key_str
    lea rcx, [k_limit]
    mov rdx, [rbp-24]
    call jb_key_int
    call jb_end_obj
    call jb_end_obj

    lea rcx, [gws_buf]
    call ws_send_json
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; gateway_update_voice_state - Send an op 4 Voice State Update (no audio)
; rcx = guild id, rdx = channel id, r8 = self_mute (0/1), r9 = self_deaf (0/1)
; ============================================================
gateway_update_voice_state:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rcx
    mov [rbp-16], rdx
    mov [rbp-24], r8
    mov [rbp-32], r9

    lea rcx, [gws_buf]
    call jb_init
    call jb_begin_obj
    lea rcx, [k_op]
    mov rdx, GATEWAY_OP_VOICE_STATE_UPDATE
    call jb_key_int
    lea rcx, [k_dd]
    call jb_begin_key_obj
    lea rcx, [k_guild_id]
    mov rdx, [rbp-8]
    call jb_key_str
    lea rcx, [k_channel_id2]
    mov rdx, [rbp-16]
    call jb_key_str
    lea rcx, [k_self_mute]
    mov rdx, [rbp-24]
    call jb_key_bool
    lea rcx, [k_self_deaf]
    mov rdx, [rbp-32]
    call jb_key_bool
    call jb_end_obj
    call jb_end_obj

    lea rcx, [gws_buf]
    call ws_send_json
    mov rsp, rbp
    pop rbp
    ret
