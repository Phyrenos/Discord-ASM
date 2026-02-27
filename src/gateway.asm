; gateway.asm - Discord Gateway WebSocket connection and event handling

section .data
    ; Identify payload parts (built manually without sprintf)
    identify_p1: db '{"op":2,"d":{"token":"', 0
    identify_p2: db '","intents":', 0
    identify_p3: db ',"properties":{"os":"windows","browser":"asm-discord","device":"asm-discord"}}}', 0

    ; Log messages
    gw_connecting_msg:  db "[Gateway] Connecting to Discord Gateway...", 10, 0
    gw_connected_msg:   db "[Gateway] WebSocket connection established!", 10, 0
    gw_hello_msg:       db "[Gateway] Received Hello, heartbeat interval: ", 0
    gw_identify_msg:    db "[Gateway] Sending Identify...", 10, 0
    gw_identify_ok_msg: db "[Gateway] Identify sent successfully", 10, 0
    gw_identify_fail:   db "[Gateway] ERROR: Identify send failed, error: ", 0
    gw_ready_msg:       db "[Gateway] Bot is READY!", 10, 0
    gw_dispatch_msg:    db "[Gateway] Event: ", 0
    gw_recv_msg:        db "[Gateway] Received op: ", 0
    gw_hb_ack_msg:      db "[Gateway] Heartbeat ACK received", 10, 0
    gw_reconnect_msg:   db "[Gateway] Reconnect requested", 10, 0
    gw_invalid_msg:     db "[Gateway] Invalid session", 10, 0
    gw_ws_err_msg:      db "[Gateway] WebSocket connection failed!", 10, 0
    gw_recv_err_msg:    db "[Gateway] Receive error code: ", 0
    gw_last_err_msg:    db "[Gateway] GetLastError: ", 0
    gw_close_code_msg:  db "[Gateway] WebSocket close code: ", 0
    gw_close_reason_msg:db "[Gateway] Close reason: ", 0
    gw_close_recv_msg:  db "[Gateway] Received WebSocket CLOSE frame", 10, 0
    gw_close_4014_msg:  db "[Gateway] ERROR: Disallowed intents! Enable MESSAGE CONTENT INTENT in Discord Developer Portal", 10, 0
    gw_close_4004_msg:  db "[Gateway] ERROR: Authentication failed - check your bot token", 10, 0
    gw_close_4013_msg:  db "[Gateway] ERROR: Invalid intents value", 10, 0
    gw_payload_msg:     db "[Gateway] Payload: ", 0
    gw_payload_len_msg: db "[Gateway] Payload length: ", 0
    gw_event_mc:        db "MESSAGE_CREATE", 0
    gw_event_ready:     db "READY", 0
    gw_ms_suffix:       db "ms", 10, 0
    gw_newline:         db 10, 0

    ; JSON keys
    key_op:                 db "op", 0
    key_d:                  db "d", 0
    key_s:                  db "s", 0
    key_t:                  db "t", 0
    key_heartbeat_interval: db "heartbeat_interval", 0
    key_content:            db "content", 0
    key_channel_id:         db "channel_id", 0
    key_id:                 db "id", 0
    key_author:             db "author", 0
    key_username:           db "username", 0
    key_bot:                db "bot", 0

section .bss
    gw_recv_buf:        resb MAX_WS_RECV_BUF     ; WebSocket receive buffer
    gw_send_buf:        resb MAX_JSON_PAYLOAD     ; WebSocket send buffer
    gw_event_name_buf:  resb 128                  ; Event name buffer
    gw_channel_id_buf:  resb MAX_CHANNEL_ID_LEN   ; Channel ID buffer
    gw_message_id_buf:  resb MAX_CHANNEL_ID_LEN   ; Message ID buffer
    gw_content_buf:     resb MAX_MESSAGE_LEN      ; Message content buffer
    gw_author_buf:      resb 128                  ; Author username buffer
    gw_author_id_buf:   resb 128                  ; Author id buffer
    gw_num_buf:         resb 32                   ; Number formatting buffer
    gw_bytes_read:      resd 1                    ; WS bytes read
    gw_buf_type:        resd 1                    ; WS buffer type
    gw_close_status:    resw 1                    ; WebSocket close status code
    gw_close_reason:    resb 256                  ; WebSocket close reason string
    gw_close_reason_len:resd 1                    ; close reason length

section .text

; ============================================================
; gateway_connect - Connect to Discord Gateway and start event loop
; rcx = bot token (UTF-8)
; rdx = intents (integer)
; Does not return until connection ends
; ============================================================
gateway_connect:
    push rbp
    mov rbp, rsp
    sub rsp, 192

    mov [rbp-8], rcx       ; token
    mov [rbp-16], rdx      ; intents

    ; Print connecting message
    lea rcx, [gw_connecting_msg]
    call print_console

    ; Initialize HTTP session
    call http_init
    test rax, rax
    jz .ws_error

    ; Connect WebSocket to gateway
    call ws_connect
    test rax, rax
    jz .ws_error

    ; Print connected
    lea rcx, [gw_connected_msg]
    call print_console

    ; === Event Loop ===
    ; First message should be Hello (op 10)
.recv_loop:
    ; Clear receive buffer
    lea rcx, [gw_recv_buf]
    xor dl, dl
    mov r8, MAX_WS_RECV_BUF
    call asm_memset

    ; Receive WebSocket message
    lea rcx, [gw_recv_buf]
    mov edx, MAX_WS_RECV_BUF - 1
    lea r8, [gw_bytes_read]
    lea r9, [gw_buf_type]
    call ws_recv

    ; Check for error
    test eax, eax
    jnz .recv_error

    ; Check for CLOSE buffer type
    mov edx, dword [rel gw_buf_type]
    cmp edx, WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE
    je .handle_close_frame

    ; Null-terminate received data
    mov eax, dword [rel gw_bytes_read]
    lea rcx, [gw_recv_buf]
    mov byte [rcx + rax], 0

    ; Handle fragmented messages - keep receiving until we get a complete message
    mov edx, dword [rel gw_buf_type]
    cmp edx, WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE
    jne .message_complete

    ; Fragment - accumulate more data
    mov r12d, eax           ; total bytes so far
.frag_loop:
    lea rcx, [rel gw_recv_buf]
    add rcx, r12
    mov edx, MAX_WS_RECV_BUF - 1
    sub edx, r12d
    jle .message_complete   ; buffer full
    lea r8, [gw_bytes_read]
    lea r9, [gw_buf_type]
    call ws_recv
    test eax, eax
    jnz .recv_error

    ; Check for close during fragment assembly
    mov edx, dword [rel gw_buf_type]
    cmp edx, WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE
    je .handle_close_frame

    mov eax, dword [rel gw_bytes_read]
    add r12d, eax

    mov edx, dword [rel gw_buf_type]
    cmp edx, WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE
    je .frag_loop

    ; Null-terminate
    lea rcx, [gw_recv_buf]
    mov byte [rcx + r12], 0

.message_complete:
    ; Parse opcode
    lea rcx, [gw_recv_buf]
    lea rdx, [key_op]
    call json_find_key
    test rax, rax
    jz .recv_loop          ; malformed, skip

    mov rcx, rax
    call json_extract_int
    mov [rbp-24], rax      ; opcode

    ; Update sequence number if present
    push rax
    lea rcx, [gw_recv_buf]
    lea rdx, [key_s]
    call json_find_key
    test rax, rax
    jz .no_seq
    cmp byte [rax], 'n'    ; "null"
    je .no_seq
    mov rcx, rax
    call json_extract_int
    mov [g_sequence_num], rax
.no_seq:
    pop rax

    ; Dispatch by opcode
    cmp rax, GATEWAY_OP_HELLO
    je .handle_hello

    cmp rax, GATEWAY_OP_DISPATCH
    je .handle_dispatch

    cmp rax, GATEWAY_OP_HEARTBEAT_ACK
    je .handle_hb_ack

    cmp rax, GATEWAY_OP_HEARTBEAT
    je .handle_hb_request

    cmp rax, GATEWAY_OP_RECONNECT
    je .handle_reconnect

    cmp rax, GATEWAY_OP_INVALID_SESSION
    je .handle_invalid

    ; Unknown opcode - log and continue
    lea rcx, [gw_recv_msg]
    call print_console
    mov rcx, [rbp-24]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    jmp .recv_loop

; ----- Hello (op 10) -----
.handle_hello:
    ; Extract heartbeat_interval from d.heartbeat_interval
    lea rcx, [gw_recv_buf]
    lea rdx, [key_d]
    lea r8, [key_heartbeat_interval]
    call json_find_nested_key
    test rax, rax
    jz .recv_loop

    mov rcx, rax
    call json_extract_int
    mov [rbp-32], rax      ; heartbeat interval

    ; Print hello message
    lea rcx, [gw_hello_msg]
    call print_console
    mov rcx, [rbp-32]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_ms_suffix]
    call print_console

    ; Start heartbeat thread
    mov rcx, [rbp-32]
    call start_heartbeat

    ; Send Identify
    lea rcx, [gw_identify_msg]
    call print_console

    ; Build identify payload manually: p1 + token + p2 + intents_str + p3
    lea rcx, [gw_send_buf]
    lea rdx, [identify_p1]
    call asm_strcpy

    lea rcx, [gw_send_buf]
    mov rdx, [rbp-8]        ; token
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [identify_p2]
    call asm_strcat

    ; Convert intents to string
    mov rcx, [rbp-16]       ; intents
    lea rdx, [gw_num_buf]
    call asm_itoa

    lea rcx, [gw_send_buf]
    lea rdx, [gw_num_buf]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [identify_p3]
    call asm_strcat

    ; Log payload length
    lea rcx, [gw_send_buf]
    call asm_strlen
    mov [rbp-48], rax       ; save length

    lea rcx, [gw_payload_len_msg]
    call print_console
    mov rcx, [rbp-48]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; Dump payload content (with token masked)
    lea rcx, [gw_payload_msg]
    call print_console
    lea rcx, [gw_send_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; Send identify payload
    mov rdx, [rbp-48]       ; length
    lea rcx, [gw_send_buf]
    call ws_send

    ; Check send result
    test eax, eax
    jnz .identify_send_fail

    lea rcx, [gw_identify_ok_msg]
    call print_console
    jmp .recv_loop

.identify_send_fail:
    mov [rbp-56], rax       ; save error code
    lea rcx, [gw_identify_fail]
    call print_console
    mov rcx, [rbp-56]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console
    jmp .done

; ----- Dispatch (op 0) -----
.handle_dispatch:
    ; Get event name from "t"
    lea rcx, [gw_recv_buf]
    lea rdx, [key_t]
    call json_find_key
    test rax, rax
    jz .recv_loop

    ; Extract event name
    mov rcx, rax
    lea rdx, [gw_event_name_buf]
    mov r8, 128
    call json_extract_string

    ; Print event name
    lea rcx, [gw_dispatch_msg]
    call print_console
    lea rcx, [gw_event_name_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; Check for READY
    lea rcx, [gw_event_name_buf]
    lea rdx, [gw_event_ready]
    call asm_strcmp
    test eax, eax
    jnz .check_message_create

    lea rcx, [gw_ready_msg]
    call print_console
    jmp .recv_loop

.check_message_create:
    ; Check for MESSAGE_CREATE
    lea rcx, [gw_event_name_buf]
    lea rdx, [gw_event_mc]
    call asm_strcmp
    test eax, eax
    jnz .recv_loop         ; not a message event

    ; Extract message data from "d" object
    ; Get channel_id
    lea rcx, [gw_recv_buf]
    lea rdx, [key_d]
    call json_find_key
    test rax, rax
    jz .recv_loop
    mov [rbp-40], rax      ; d object start

    ; Find channel_id in d
    mov rcx, rax
    lea rdx, [key_channel_id]
    call json_find_key
    test rax, rax
    jz .recv_loop

    mov rcx, rax
    lea rdx, [gw_channel_id_buf]
    mov r8, MAX_CHANNEL_ID_LEN
    call json_extract_string

    ; Find id in d (message id)
    mov rcx, [rbp-40]
    lea rdx, [key_id]
    call json_find_key
    test rax, rax
    jz .recv_loop

    mov rcx, rax
    lea rdx, [gw_message_id_buf]
    mov r8, MAX_CHANNEL_ID_LEN
    call json_extract_string

    ; Find content in d
    mov rcx, [rbp-40]
    lea rdx, [key_content]
    call json_find_key
    test rax, rax
    jz .recv_loop

    mov rcx, rax
    lea rdx, [gw_content_buf]
    mov r8, MAX_MESSAGE_LEN
    call json_extract_string

    ; Find author.id in d
    mov rcx, [rbp-40]
    lea rdx, [key_author]
    call json_find_key
    test rax, rax
    jz .dispatch_no_author

    ; Check if author is a bot
    push rax
    mov rcx, rax
    lea rdx, [key_bot]
    call json_find_key
    test rax, rax
    jz .not_bot
    mov rcx, rax
    call json_extract_bool
    test eax, eax
    jnz .skip_bot           ; skip bot messages
.not_bot:
    pop rax

    ; Extract ID
    push rax
    mov rcx, rax
    lea rdx, [key_id]
    call json_find_key
    test rax, rax
    jz .skip_id
    mov rcx, rax
    lea rdx, [gw_author_id_buf]
    mov r8, 128
    call json_extract_string
.skip_id:
    pop rax

    ; Extract Username
    mov rcx, rax
    lea rdx, [key_username]
    call json_find_key
    test rax, rax
    jz .dispatch_no_author

    mov rcx, rax
    lea rdx, [gw_author_buf]
    mov r8, 128
    call json_extract_string
    jmp .dispatch_msg

.skip_bot:
    pop rax                 ; balance push from .not_bot path
    jmp .recv_loop

.dispatch_no_author:
    mov byte [gw_author_buf], 0
    mov byte [gw_author_id_buf], 0

.dispatch_msg:
    ; Dispatch to command system (5 args)
    lea rax, [gw_author_id_buf]
    mov [rsp+32], rax      ; 5th arg
    
    lea rcx, [gw_channel_id_buf]
    lea rdx, [gw_content_buf]
    lea r8, [gw_author_buf]
    lea r9, [gw_message_id_buf]
    call dispatch_command

    jmp .recv_loop

; ----- Heartbeat ACK (op 11) -----
.handle_hb_ack:
    mov qword [g_heartbeat_acked], 1
    lea rcx, [gw_hb_ack_msg]
    call print_console
    jmp .recv_loop

; ----- Heartbeat request (op 1) -----
.handle_hb_request:
    ; Server is asking us to heartbeat immediately
    cmp qword [g_sequence_num], -1
    je .hb_null

    ; Build {"op":1,"d":<seq>} manually
    lea rcx, [gw_send_buf]
    lea rdx, [hb_seq_prefix]
    call asm_strcpy

    mov rcx, [g_sequence_num]
    lea rdx, [gw_num_buf]
    call asm_itoa

    lea rcx, [gw_send_buf]
    lea rdx, [gw_num_buf]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [hb_seq_suffix]
    call asm_strcat

    lea rcx, [gw_send_buf]
    call asm_strlen
    mov rdx, rax
    lea rcx, [gw_send_buf]
    call ws_send
    jmp .recv_loop

.hb_null:
    lea rcx, [hb_payload_null]
    call asm_strlen
    mov rdx, rax
    lea rcx, [hb_payload_null]
    call ws_send
    jmp .recv_loop

; ----- Reconnect (op 7) -----
.handle_reconnect:
    lea rcx, [gw_reconnect_msg]
    call print_console
    ; For now, just exit the loop - a production bot would reconnect
    jmp .done

; ----- Invalid Session (op 9) -----
.handle_invalid:
    lea rcx, [gw_invalid_msg]
    call print_console
    jmp .done

; ----- WebSocket CLOSE frame received -----
.handle_close_frame:
    lea rcx, [gw_close_recv_msg]
    call print_console

    ; Query the close status from WinHTTP
    call .query_close_status
    jmp .done

; ----- Receive error -----
.recv_error:
    ; Save the WinHTTP error code
    mov [rbp-56], rax

    ; Print error code
    lea rcx, [gw_recv_err_msg]
    call print_console
    mov rcx, [rbp-56]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; Also get GetLastError
    call GetLastError
    mov [rbp-64], rax

    lea rcx, [gw_last_err_msg]
    call print_console
    mov rcx, [rbp-64]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; Try to query close status (may give us Discord's close code)
    call .query_close_status
    jmp .done

; Internal helper: query and print WebSocket close status
.query_close_status:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; WinHttpWebSocketQueryCloseStatus(hWebSocket, &usStatus, pvReason, dwReasonLength, &dwReasonLengthConsumed)
    mov rcx, [g_hWebSocket]
    test rcx, rcx
    jz .qcs_done

    lea rdx, [gw_close_status]       ; &usStatus (USHORT)
    lea r8, [gw_close_reason]         ; pvReason buffer
    mov r9, 256                       ; dwReasonLength
    lea rax, [gw_close_reason_len]
    mov [rsp+32], rax                 ; &dwReasonLengthConsumed
    call WinHttpWebSocketQueryCloseStatus

    ; Check if the query succeeded
    test eax, eax
    jnz .qcs_done

    ; Print close code
    lea rcx, [gw_close_code_msg]
    call print_console
    movzx rcx, word [gw_close_status]
    mov [rbp-8], rcx        ; save close code
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; Print human-readable close code explanations
    mov rcx, [rbp-8]
    cmp rcx, 4014
    je .qcs_4014
    cmp rcx, 4004
    je .qcs_4004
    cmp rcx, 4013
    je .qcs_4013
    jmp .qcs_reason

.qcs_4014:
    lea rcx, [gw_close_4014_msg]
    call print_console
    jmp .qcs_reason
.qcs_4004:
    lea rcx, [gw_close_4004_msg]
    call print_console
    jmp .qcs_reason
.qcs_4013:
    lea rcx, [gw_close_4013_msg]
    call print_console

.qcs_reason:
    ; Print close reason if present
    mov eax, [gw_close_reason_len]
    test eax, eax
    jz .qcs_done

    ; Null-terminate the reason
    lea rcx, [gw_close_reason]
    mov byte [rcx + rax], 0

    lea rcx, [gw_close_reason_msg]
    call print_console
    lea rcx, [gw_close_reason]
    call print_console
    lea rcx, [gw_newline]
    call print_console

.qcs_done:
    mov rsp, rbp
    pop rbp
    ret

.ws_error:
    lea rcx, [gw_ws_err_msg]
    call print_console

    ; Print GetLastError for WS connection failure too
    call GetLastError
    mov [rbp-56], rax
    lea rcx, [gw_last_err_msg]
    call print_console
    mov rcx, [rbp-56]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

.done:
    ; Stop heartbeat
    call stop_heartbeat

    ; Cleanup
    call http_cleanup

    mov rsp, rbp
    pop rbp
    ret
