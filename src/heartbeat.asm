; heartbeat.asm - Heartbeat thread for keeping Gateway connection alive

section .bss
    g_heartbeat_interval:   resq 1  ; interval in ms
    g_sequence_num:         resq 1  ; last sequence number received (-1 = null)
    g_heartbeat_acked:      resq 1  ; whether last heartbeat was ACKed
    g_bot_running:          resq 1  ; flag to stop heartbeat thread

section .data
    ; Heartbeat payload templates
    hb_payload_null: db '{"op":1,"d":null}', 0
    hb_seq_prefix:   db '{"op":1,"d":', 0
    hb_seq_suffix:   db '}', 0
    hb_started_msg:  db "[Heartbeat] Thread started, interval: ", 0
    hb_send_msg:     db "[Heartbeat] Sending heartbeat", 10, 0
    hb_ms_suffix:    db "ms", 10, 0

section .bss
    hb_payload_buf: resb 128
    hb_num_tmp:     resb 32

section .text

; ============================================================
; heartbeat_thread_proc - Thread procedure for heartbeat
; rcx = parameter (unused)
; Loops: Sleep(interval) -> send heartbeat -> repeat
; ============================================================
heartbeat_thread_proc:
    push rbp
    mov rbp, rsp
    sub rsp, 96

    ; Print start message
    lea rcx, [hb_started_msg]
    call print_console

    ; Print interval
    mov rcx, [g_heartbeat_interval]
    lea rdx, [hb_payload_buf]
    call asm_itoa
    lea rcx, [hb_payload_buf]
    call print_console
    lea rcx, [hb_ms_suffix]
    call print_console

    ; Mark heartbeat as acked initially
    mov qword [g_heartbeat_acked], 1

.loop:
    ; Check if bot is still running
    cmp qword [g_bot_running], 0
    je .exit

    ; Sleep for heartbeat interval
    mov rcx, [g_heartbeat_interval]
    mov ecx, ecx           ; truncate to 32-bit for Sleep
    call Sleep

    ; Check again after sleep
    cmp qword [g_bot_running], 0
    je .exit

    ; Build heartbeat payload
    cmp qword [g_sequence_num], -1
    je .send_null

    ; Build payload with sequence number: {"op":1,"d":<seq>}
    ; Manually: strcpy(buf, prefix) + itoa(seq, tmp) + strcat(buf, tmp) + strcat(buf, suffix)
    lea rcx, [hb_payload_buf]
    lea rdx, [hb_seq_prefix]
    call asm_strcpy

    mov rcx, [g_sequence_num]
    lea rdx, [hb_num_tmp]
    call asm_itoa

    lea rcx, [hb_payload_buf]
    lea rdx, [hb_num_tmp]
    call asm_strcat

    lea rcx, [hb_payload_buf]
    lea rdx, [hb_seq_suffix]
    call asm_strcat

    lea rcx, [hb_payload_buf]
    jmp .send

.send_null:
    lea rcx, [hb_payload_null]

.send:
    ; Print debug
    push rcx
    lea rcx, [hb_send_msg]
    call print_console
    pop rcx

    ; Get payload length
    push rcx
    call asm_strlen
    mov rdx, rax
    pop rcx

    ; Send via WebSocket
    call ws_send

    ; Mark as not acked (waiting for ACK)
    mov qword [g_heartbeat_acked], 0

    jmp .loop

.exit:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; start_heartbeat - Start the heartbeat thread
; rcx = heartbeat interval in ms
; Returns: rax = thread handle
; ============================================================
start_heartbeat:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    ; Store interval
    mov [g_heartbeat_interval], rcx

    ; Initialize sequence to -1 (null)
    mov qword [g_sequence_num], -1
    mov qword [g_bot_running], 1

    ; CreateThread(NULL, 0, proc, param, 0, NULL)
    xor ecx, ecx           ; lpThreadAttributes
    xor edx, edx           ; dwStackSize (default)
    lea r8, [heartbeat_thread_proc]
    xor r9, r9             ; lpParameter
    mov qword [rsp+32], 0  ; dwCreationFlags
    mov qword [rsp+40], 0  ; lpThreadId
    call CreateThread

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; stop_heartbeat - Signal heartbeat thread to stop
; ============================================================
stop_heartbeat:
    mov qword [g_bot_running], 0
    ret
