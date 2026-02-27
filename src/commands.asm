; commands.asm - Command registration, parsing, and dispatch

; Command table entry structure:
;   name_ptr:    8 bytes (pointer to command name string, without prefix)
;   handler_ptr: 8 bytes (pointer to handler function)
; Handler signature: void handler(rcx=channel_id, rdx=args, r8=author_username, r9=message_id, [rsp+40]=author_id)

section .bss
    ; Command table: array of (name_ptr, handler_ptr) pairs
    cmd_table:      resb (MAX_COMMANDS * 16)    ; 16 bytes per entry
    cmd_count:      resq 1                       ; number of registered commands
    cmd_prefix:     resb 2                       ; prefix character + null

section .data
    cmd_dispatch_msg:  db "[Commands] Dispatching: !", 0
    cmd_unknown_msg:   db "[Commands] Unknown command: !", 0
    cmd_newline:       db 10, 0

section .text

; ============================================================
; commands_init - Initialize command system
; rcx = prefix character (e.g., '!')
; ============================================================
commands_init:
    mov [cmd_prefix], cl
    mov byte [cmd_prefix+1], 0
    mov qword [cmd_count], 0
    ret

; ============================================================
; register_command - Register a command handler
; rcx = command name (string pointer, e.g., "ping")
; rdx = handler function pointer
; Returns: rax = 1 on success, 0 if table full
; ============================================================
register_command:
    push rbx

    mov rax, [cmd_count]
    cmp rax, MAX_COMMANDS
    jge .full

    ; Calculate offset into table: index * 16
    shl rax, 4             ; * 16
    lea rbx, [cmd_table]
    add rbx, rax

    ; Store entry
    mov [rbx], rcx         ; name_ptr
    mov [rbx+8], rdx       ; handler_ptr

    ; Increment count
    inc qword [cmd_count]

    mov eax, 1
    pop rbx
    ret

.full:
    xor eax, eax
    pop rbx
    ret

; ============================================================
; dispatch_command - Parse message and dispatch to command handler
; rcx = channel_id (string)
; rdx = message content (string)
; r8  = author_username (string)
; r9  = message_id (string)
; [rbp+48] = author_id (string)
; Returns: rax = 1 if command was dispatched, 0 otherwise
; ============================================================
dispatch_command:
    push rbp
    mov rbp, rsp
    sub rsp, 128
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov [rbp-8], rcx       ; channel_id
    mov [rbp-16], rdx      ; message content
    mov [rbp-24], r8       ; author_username
    mov [rbp-32], r9       ; message_id
    
    mov rax, [rbp+48]      ; 5th arg (author_id) is at caller_rsp + 32, so rbp+48
    mov [rbp-40], rax      ; author_id

    ; Check if message starts with prefix
    mov al, [cmd_prefix]
    cmp byte [rdx], al
    jne .not_command

    ; Skip prefix
    inc rdx
    mov r12, rdx           ; r12 = start of command name

    ; Find end of command name (space or null)
    mov rsi, rdx
.find_end:
    mov al, [rsi]
    test al, al
    jz .found_end
    cmp al, ' '
    je .found_end
    inc rsi
    jmp .find_end
.found_end:
    mov r13, rsi           ; r13 = end of command name
    sub rsi, r12           ; rsi = command name length

    ; Args start after space (or NULL if no args)
    mov r14, r13
    cmp byte [r14], ' '
    jne .no_args
    inc r14                 ; skip space to get args
    jmp .lookup
.no_args:
    ; r14 points to null terminator = empty args

.lookup:
    ; Search command table
    xor ebx, ebx           ; index
    mov rdi, [cmd_count]

.search:
    cmp rbx, rdi
    jge .not_found

    ; Get entry
    mov rax, rbx
    shl rax, 4
    lea rcx, [rel cmd_table]
    add rcx, rax

    ; Compare command name
    push rcx
    mov rcx, [rcx]         ; name_ptr
    mov rdx, r12           ; command in message
    mov r8, rsi            ; length
    call asm_strncmp
    pop rcx

    test eax, eax
    jnz .next

    ; Also check the registered name length matches
    push rcx
    mov rcx, [rcx]
    call asm_strlen
    pop rcx
    cmp rax, rsi
    jne .next

    ; Found! Print dispatch message
    push rcx
    lea rcx, [cmd_dispatch_msg]
    call print_console
    mov rcx, [rsp]
    mov rcx, [rcx]          ; name
    call print_console
    lea rcx, [cmd_newline]
    call print_console
    pop rcx

    ; Call handler(channel_id, args, author_username, message_id, author_id)
    mov rax, [rcx+8]       ; handler_ptr
    mov rcx, [rbp-8]       ; channel_id
    mov rdx, r14            ; args
    mov r8, [rbp-24]       ; author_username
    mov r9, [rbp-32]       ; message_id
    
    mov r10, [rbp-40]
    mov [rsp+32], r10      ; 5th arg (author_id) on stack
    
    call rax

    mov eax, 1
    jmp .done

.next:
    inc rbx
    jmp .search

.not_found:
    ; Print unknown command
    lea rcx, [cmd_unknown_msg]
    call print_console
    ; Print the command name character by character... or just skip
    lea rcx, [cmd_newline]
    call print_console

.not_command:
    xor eax, eax

.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    mov rsp, rbp
    pop rbp
    ret
