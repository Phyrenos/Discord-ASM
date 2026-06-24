; gateway.asm - Discord Gateway WebSocket connection and event handling
;
; Compatibility / robustness:
;   * Auto-reconnect: gateway_connect is an outer loop. Instead of exiting on
;     op 7 (RECONNECT), op 9 (INVALID_SESSION), a CLOSE frame, a receive error,
;     or a heartbeat-watchdog trip, it tears the session down and reconnects
;     with exponential backoff (capped). Truly fatal close codes (bad token,
;     bad intents, ...) stop instead of looping forever.
;   * RESUME: READY supplies session_id (and resume_gateway_url). On a
;     recoverable disconnect we send op 6 RESUME to replay missed events; if
;     the gateway rejects it (INVALID_SESSION) we fall back to a fresh IDENTIFY.
;   * Presence: IDENTIFY advertises an activity ("Playing <activity>") and an
;     online status.

section .data
    ; Identify payload parts (built manually without sprintf)
    identify_p1: db '{"op":2,"d":{"token":"', 0
    identify_p2: db '","intents":', 0
    identify_p3: db ',"properties":{"os":"windows","browser":"asm-discord","device":"asm-discord"},"presence":{"activities":[{"name":"', 0
    identify_p4: db '","type":0}],"status":"online","afk":false}}}', 0

    ; Resume payload parts: {"op":6,"d":{"token":"..","session_id":"..","seq":N}}
    resume_p1:   db '{"op":6,"d":{"token":"', 0
    resume_p2:   db '","session_id":"', 0
    resume_p3:   db '","seq":', 0
    resume_p4:   db '}}', 0

    ; Log messages
    gw_connecting_msg:  db "[Gateway] Connecting to Discord Gateway...", 10, 0
    gw_connected_msg:   db "[Gateway] WebSocket connection established!", 10, 0
    gw_hello_msg:       db "[Gateway] Received Hello, heartbeat interval: ", 0
    gw_identify_msg:    db "[Gateway] Sending Identify...", 10, 0
    gw_identify_ok_msg: db "[Gateway] Identify sent successfully", 10, 0
    gw_identify_fail:   db "[Gateway] ERROR: Identify send failed, error: ", 0
    gw_resuming_msg:    db "[Gateway] Resuming previous session...", 10, 0
    gw_resumed_msg:     db "[Gateway] Session RESUMED successfully", 10, 0
    gw_ready_msg:       db "[Gateway] Bot is READY!", 10, 0
    gw_dispatch_msg:    db "[Gateway] Event: ", 0
    gw_recv_msg:        db "[Gateway] Received op: ", 0
    gw_hb_ack_msg:      db "[Gateway] Heartbeat ACK received", 10, 0
    gw_reconnect_msg:   db "[Gateway] Reconnect requested by gateway", 10, 0
    gw_invalid_msg:     db "[Gateway] Invalid session", 10, 0
    gw_reconnecting_msg:db "[Gateway] Reconnecting, attempt ", 0
    gw_backoff_msg:     db "[Gateway] Backing off (ms): ", 0
    gw_giveup_msg:      db "[Gateway] Max reconnect attempts reached - giving up", 10, 0
    gw_fatal_msg:       db "[Gateway] Fatal close code - not reconnecting", 10, 0
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
    gw_event_resumed:   db "RESUMED", 0
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
    key_session_id:         db "session_id", 0
    key_resume_url:         db "resume_gateway_url", 0

    ; Key path for READY -> d.application.id (used with json_find_path)
    ready_path_keys:        dq key_d, k_application, key_id

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

    ; Session / reconnect state
    g_session_id:       resb MAX_SESSION_ID_LEN   ; Discord session id (from READY)
    g_resume_url:       resb MAX_RESUME_URL_LEN   ; resume_gateway_url (from READY)
    g_can_resume:       resq 1                    ; 1 = try RESUME on next HELLO
    g_reconnect_attempts: resq 1                  ; consecutive (re)connect failures

section .text

; ============================================================
; gateway_connect - Connect to Discord Gateway and run the event loop,
; reconnecting automatically until a fatal condition or the attempt cap.
; rcx = bot token (UTF-8)
; rdx = intents (integer)
; Does not return until the bot gives up / hits a fatal error
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

    ; Initialize session / reconnect state (once)
    mov qword [g_can_resume], 0
    mov qword [g_reconnect_attempts], 0
    mov qword [g_sequence_num], -1
    mov byte [g_session_id], 0
    mov qword [g_zombie], 0

.connect_attempt:
    ; Clear stale close status / zombie flag for this fresh connection
    mov word [gw_close_status], 0
    mov qword [g_zombie], 0

    ; (Re)connect WebSocket to gateway
    call ws_connect
    test rax, rax
    jz .connect_failed

    ; Connected - reset the failure counter
    mov qword [g_reconnect_attempts], 0

    ; Print connected
    lea rcx, [gw_connected_msg]
    call print_console

    ; === Event Loop ===
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

    ; Decide: resume an existing session, or identify fresh?
    cmp qword [g_can_resume], 0
    je .send_identify
    cmp byte [g_session_id], 0
    je .send_identify
    jmp .send_resume

; ----- Send Identify -----
.send_identify:
    lea rcx, [gw_identify_msg]
    call print_console

    ; Build identify payload: p1 + token + p2 + intents + p3 + activity + p4
    lea rcx, [gw_send_buf]
    lea rdx, [identify_p1]
    call asm_strcpy

    lea rcx, [gw_send_buf]
    mov rdx, [rbp-8]        ; token
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [identify_p2]
    call asm_strcat

    ; intents -> string
    mov rcx, [rbp-16]       ; intents
    lea rdx, [gw_num_buf]
    call asm_itoa

    lea rcx, [gw_send_buf]
    lea rdx, [gw_num_buf]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [identify_p3]
    call asm_strcat

    ; presence activity text (configurable via DISCORD_ACTIVITY)
    lea rcx, [gw_send_buf]
    lea rdx, [g_activity]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [identify_p4]
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
    ; Treat a failed send as a recoverable disconnect
    mov qword [g_can_resume], 1
    jmp .do_reconnect

; ----- Send Resume (op 6) -----
.send_resume:
    lea rcx, [gw_resuming_msg]
    call print_console

    ; Build resume payload: p1 + token + p2 + session_id + p3 + seq + p4
    lea rcx, [gw_send_buf]
    lea rdx, [resume_p1]
    call asm_strcpy

    lea rcx, [gw_send_buf]
    mov rdx, [rbp-8]        ; token
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [resume_p2]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [g_session_id]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [resume_p3]
    call asm_strcat

    ; seq -> string
    mov rcx, [g_sequence_num]
    lea rdx, [gw_num_buf]
    call asm_itoa

    lea rcx, [gw_send_buf]
    lea rdx, [gw_num_buf]
    call asm_strcat

    lea rcx, [gw_send_buf]
    lea rdx, [resume_p4]
    call asm_strcat

    ; Send it
    lea rcx, [gw_send_buf]
    call asm_strlen
    mov rdx, rax
    lea rcx, [gw_send_buf]
    call ws_send

    test eax, eax
    jnz .identify_send_fail   ; same recovery path

    jmp .recv_loop

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
    jz .handle_ready

    ; Check for RESUMED
    lea rcx, [gw_event_name_buf]
    lea rdx, [gw_event_resumed]
    call asm_strcmp
    test eax, eax
    jz .handle_resumed

    ; Otherwise: find the "d" object and hand off to the registered event table
    lea rcx, [gw_recv_buf]
    lea rdx, [key_d]
    call json_find_key
    test rax, rax
    jz .recv_loop
    mov rdx, rax                   ; d object pointer
    lea rcx, [gw_event_name_buf]   ; event name
    lea r8, [gw_recv_buf]          ; full payload
    call dispatch_event
    jmp .recv_loop

; ----- READY: capture session_id + resume_gateway_url for future RESUME -----
.handle_ready:
    lea rcx, [gw_recv_buf]
    lea rdx, [key_d]
    lea r8, [key_session_id]
    call json_find_nested_key
    test rax, rax
    jz .ready_url
    mov rcx, rax
    lea rdx, [g_session_id]
    mov r8, MAX_SESSION_ID_LEN
    call json_extract_string
    mov qword [g_can_resume], 1

.ready_url:
    lea rcx, [gw_recv_buf]
    lea rdx, [key_d]
    lea r8, [key_resume_url]
    call json_find_nested_key
    test rax, rax
    jz .ready_fin
    mov rcx, rax
    lea rdx, [g_resume_url]
    mov r8, MAX_RESUME_URL_LEN
    call json_extract_string

.ready_app:
    ; Capture application id (d.application.id) for slash-command registration,
    ; unless it was already provided via DISCORD_APP_ID env.
    cmp byte [g_application_id], 0
    jne .ready_register
    lea rcx, [gw_recv_buf]
    lea rdx, [ready_path_keys]
    mov r8, 3
    call json_find_path
    test rax, rax
    jz .ready_register
    mov rcx, rax
    lea rdx, [g_application_id]
    mov r8, 64
    call json_extract_string

.ready_register:
    ; Register slash commands once (no-op if already done / no app id)
    call register_slash_commands_with_discord

.ready_fin:
    mov qword [g_reconnect_attempts], 0
    lea rcx, [gw_ready_msg]
    call print_console
    jmp .recv_loop

; ----- RESUMED: gateway accepted our resume and replayed events -----
.handle_resumed:
    mov qword [g_reconnect_attempts], 0
    lea rcx, [gw_resumed_msg]
    call print_console
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
    ; Resume if we still hold a session; otherwise reconnect fresh
    cmp byte [g_session_id], 0
    je .reconnect_fresh
    mov qword [g_can_resume], 1
    jmp .do_reconnect
.reconnect_fresh:
    mov qword [g_can_resume], 0
    mov qword [g_sequence_num], -1
    jmp .do_reconnect

; ----- Invalid Session (op 9) -----
.handle_invalid:
    lea rcx, [gw_invalid_msg]
    call print_console
    ; d is a boolean: true = the session is resumable, false = start over
    lea rcx, [gw_recv_buf]
    lea rdx, [key_d]
    call json_find_key
    test rax, rax
    jz .invalid_fresh
    mov rcx, rax
    call json_extract_bool
    test eax, eax
    jz .invalid_fresh
    ; resumable
    mov qword [g_can_resume], 1
    jmp .do_reconnect
.invalid_fresh:
    mov qword [g_can_resume], 0
    mov byte [g_session_id], 0
    mov qword [g_sequence_num], -1
    jmp .do_reconnect

; ----- WebSocket CLOSE frame received -----
.handle_close_frame:
    lea rcx, [gw_close_recv_msg]
    call print_console
    call .query_close_status
    jmp .evaluate_close

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
    jmp .evaluate_close

; ----- Decide whether a close/error is fatal or should trigger a reconnect -----
.evaluate_close:
    movzx rax, word [gw_close_status]
    cmp rax, 4004
    je .fatal_close
    cmp rax, 4010
    je .fatal_close
    cmp rax, 4011
    je .fatal_close
    cmp rax, 4012
    je .fatal_close
    cmp rax, 4013
    je .fatal_close
    cmp rax, 4014
    je .fatal_close
    ; Recoverable - try to resume (a fresh IDENTIFY will follow if it's rejected)
    mov qword [g_can_resume], 1
    jmp .do_reconnect

.fatal_close:
    lea rcx, [gw_fatal_msg]
    call print_console
    jmp .shutdown

; ----- Tear down the current session and reconnect with backoff -----
.do_reconnect:
    call stop_heartbeat
    call ws_close

.backoff_and_retry:
    inc qword [g_reconnect_attempts]
    mov rax, [g_reconnect_attempts]
    cmp rax, MAX_RECONNECT_ATTEMPTS
    jg .give_up

    ; Print "Reconnecting, attempt N"
    lea rcx, [gw_reconnecting_msg]
    call print_console
    mov rcx, [g_reconnect_attempts]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    ; backoff = min(BASE << (attempts-1), MAX), shift capped to keep it sane
    mov r10, [g_reconnect_attempts]
    dec r10
    cmp r10, 5
    jle .bk_shift
    mov r10, 5
.bk_shift:
    mov rax, RECONNECT_BASE_MS
    mov rcx, r10
    shl rax, cl
    cmp rax, RECONNECT_MAX_MS
    jbe .bk_cap
    mov rax, RECONNECT_MAX_MS
.bk_cap:
    ; Log the backoff
    mov [rbp-72], rax
    lea rcx, [gw_backoff_msg]
    call print_console
    mov rcx, [rbp-72]
    lea rdx, [gw_num_buf]
    call asm_itoa
    lea rcx, [gw_num_buf]
    call print_console
    lea rcx, [gw_newline]
    call print_console

    mov rcx, [rbp-72]
    call Sleep
    jmp .connect_attempt

; ws_connect failed outright - close partial handles then back off
.connect_failed:
    call ws_close
    jmp .backoff_and_retry

.give_up:
    lea rcx, [gw_giveup_msg]
    call print_console
    jmp .shutdown

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

.shutdown:
    ; Stop heartbeat and clean up all handles
    call stop_heartbeat
    call http_cleanup

    mov rsp, rbp
    pop rbp
    ret
