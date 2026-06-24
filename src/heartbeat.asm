; heartbeat.asm - Heartbeat thread for keeping Gateway connection alive
;
; Robustness features:
;   * Chunked sleep so the thread reacts quickly to shutdown/reconnect
;     instead of being stuck in one long Sleep(interval) call.
;   * Generation counter: every time start_heartbeat runs it bumps
;     g_hb_generation and hands the new value to the thread. A thread whose
;     captured generation no longer matches exits immediately, so a reconnect
;     can never leave two heartbeat threads racing on the same socket.
;   * ACK watchdog: if the previous heartbeat was never ACKed (op 11) by the
;     time the next one is due, the connection is a "zombie". The thread sets
;     g_zombie and closes the WebSocket, which unblocks the main receive loop
;     and triggers a reconnect.

section .bss
    g_heartbeat_interval:   resq 1  ; interval in ms
    g_sequence_num:         resq 1  ; last sequence number received (-1 = null)
    g_heartbeat_acked:      resq 1  ; whether the last heartbeat we sent was ACKed
    g_bot_running:          resq 1  ; flag to stop heartbeat thread
    g_hb_generation:        resq 1  ; current heartbeat-thread generation
    g_zombie:               resq 1  ; set when the watchdog tripped (informational)

section .data
    ; Heartbeat payload templates
    hb_payload_null: db '{"op":1,"d":null}', 0
    hb_seq_prefix:   db '{"op":1,"d":', 0
    hb_seq_suffix:   db '}', 0
    hb_started_msg:  db "[Heartbeat] Thread started, interval: ", 0
    hb_send_msg:     db "[Heartbeat] Sending heartbeat", 10, 0
    hb_zombie_msg:   db "[Heartbeat] No ACK received - connection is a zombie, forcing reconnect", 10, 0
    hb_ms_suffix:    db "ms", 10, 0

section .bss
    hb_payload_buf: resb 128
    hb_num_tmp:     resb 32

; Sleep granularity (ms) - how often the thread re-checks stop/generation
HB_SLEEP_CHUNK equ 250

section .text

; ============================================================
; heartbeat_thread_proc - Thread procedure for heartbeat
; rcx = this thread's generation value
; Loops: sleep(interval) -> watchdog check -> send heartbeat -> repeat
; ============================================================
heartbeat_thread_proc:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    mov [rbp-8], rcx          ; my generation

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

.loop:
    ; --- Sleep the interval, in small chunks, checking for stop/generation ---
    mov r12, [g_heartbeat_interval]
.sleep_chunk:
    cmp qword [g_bot_running], 0
    je .exit
    mov rax, [g_hb_generation]
    cmp rax, [rbp-8]
    jne .exit
    test r12, r12
    jle .after_sleep
    ; chunk = min(remaining, HB_SLEEP_CHUNK)
    mov rax, HB_SLEEP_CHUNK
    cmp r12, HB_SLEEP_CHUNK
    jge .have_chunk
    mov rax, r12
.have_chunk:
    sub r12, rax
    mov rcx, rax
    call Sleep
    jmp .sleep_chunk

.after_sleep:
    ; Re-check stop/generation after sleeping the full interval
    cmp qword [g_bot_running], 0
    je .exit
    mov rax, [g_hb_generation]
    cmp rax, [rbp-8]
    jne .exit

    ; --- Watchdog: was the previous heartbeat ACKed? ---
    cmp qword [g_heartbeat_acked], 0
    jne .send_hb

    ; Zombie connection - no ACK since last send. Close the socket so the
    ; main receive loop errors out and reconnects, then exit this thread.
    lea rcx, [hb_zombie_msg]
    call print_console
    mov qword [g_zombie], 1
    call ws_close
    jmp .exit

.send_hb:
    ; Build heartbeat payload
    cmp qword [g_sequence_num], -1
    je .send_null

    ; {"op":1,"d":<seq>}
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

    ; Mark as not acked (waiting for ACK from the gateway)
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
;
; Note: does NOT reset g_sequence_num - the sequence number must survive a
; resume so the heartbeat keeps reporting the correct value. gateway_connect
; owns the lifetime of g_sequence_num.
; ============================================================
start_heartbeat:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    ; Store interval and (re)arm the thread
    mov [g_heartbeat_interval], rcx
    mov qword [g_bot_running], 1
    mov qword [g_heartbeat_acked], 1   ; assume healthy until proven otherwise

    ; New generation - any previous thread will see the mismatch and exit
    inc qword [g_hb_generation]

    ; CreateThread(NULL, 0, proc, generation, 0, NULL)
    xor ecx, ecx           ; lpThreadAttributes
    xor edx, edx           ; dwStackSize (default)
    lea r8, [heartbeat_thread_proc]
    mov r9, [g_hb_generation]   ; lpParameter = this thread's generation
    mov qword [rsp+32], 0  ; dwCreationFlags
    mov qword [rsp+40], 0  ; lpThreadId
    call CreateThread

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; stop_heartbeat - Signal heartbeat thread to stop
; Bumps the generation so the running thread exits even if it is mid-sleep.
; ============================================================
stop_heartbeat:
    mov qword [g_bot_running], 0
    inc qword [g_hb_generation]
    ret
