; bot.asm - Main entry point and bot initialization
; This is the root file that includes all other source files.
; Build: nasm -f win64 src/bot.asm -o build/bot.obj -Iinclude/ -Isrc/
;        link build/bot.obj /SUBSYSTEM:CONSOLE /ENTRY:main /OUT:build/bot.exe \
;             kernel32.lib winhttp.lib msvcrt.lib

bits 64
default rel

; ============================================================
; Include headers
; ============================================================
%include "macros.inc"
%include "winapi.inc"
%include "discord.inc"

; ============================================================
; Data section - Bot configuration and globals
; ============================================================
section .data
    ; Bot configuration
    bot_prefix:     db "!", 0

    ; Startup messages
    msg_banner:     db "========================================", 10
                    db "  Discord Bot - Pure x86-64 Assembly", 10
                    db "  NASM + WinHTTP on Windows", 10
                    db "========================================", 10, 0
    msg_init:       db "[Bot] Initializing...", 10, 0
    msg_token_load: db "[Bot] Token loaded", 10, 0
    msg_no_token:   db "[Bot] ERROR: Set DISCORD_TOKEN environment variable!", 10, 0
    msg_registering:db "[Bot] Registering commands...", 10, 0
    msg_starting:   db "[Bot] Starting gateway connection...", 10, 0
    msg_shutdown:   db "[Bot] Shutting down...", 10, 0
    msg_cmd_reg:    db "[Bot] Registered command: !", 0
    msg_newline:    db 10, 0

    ; Environment variable name
    env_token_name: db "DISCORD_TOKEN", 0



section .bss
    bot_token:      resb MAX_TOKEN_LEN  ; Bot token from environment
    cmd_resp_buf:   resb 512            ; Buffer for building command responses

; ============================================================
; Text section - All code
; ============================================================
section .text

; Include all source modules
%include "strings.asm"
%include "json.asm"
%include "http.asm"
%include "heartbeat.asm"
%include "commands.asm"
%include "rest.asm"
%include "gateway.asm"

; ============================================================
; print_console - Print a null-terminated string to stdout
; rcx = string pointer
; ============================================================
print_console:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx       ; save string pointer

    ; Get string length
    call asm_strlen
    mov [rbp-16], rax      ; string length

    test rax, rax
    jz .done

    ; GetStdHandle(STD_OUTPUT_HANDLE)
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [rbp-24], rax      ; stdout handle

    ; WriteFile(handle, buffer, length, &written, NULL)
    mov rcx, rax           ; handle
    mov rdx, [rbp-8]       ; buffer
    mov r8d, dword [rbp-16] ; number of bytes
    lea r9, [rbp-32]       ; &bytes_written
    mov qword [rsp+32], 0  ; lpOverlapped
    call WriteFile

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; get_env_var - Get environment variable value
; rcx = variable name
; rdx = output buffer
; r8  = buffer size
; Returns: rax = length of value, 0 if not found
; ============================================================
extern GetEnvironmentVariableA
get_env_var:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; GetEnvironmentVariableA(name, buffer, size)
    ; Args already in rcx, rdx, r8
    call GetEnvironmentVariableA

    ; Returns length, or 0 on failure
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; Register all commands
; ============================================================
%include "command_handlers.asm"


; ============================================================
; strip_quotes - Remove surrounding double quotes from a string in-place
; rcx = string pointer (modified in-place)
; If string starts and ends with ", shifts content left and removes both
; ============================================================
strip_quotes:
    push rsi
    push rdi

    mov rsi, rcx            ; rsi = string

    ; Check if first char is "
    cmp byte [rsi], '"'
    jne .done

    ; Find the end of the string
    mov rdi, rsi
.find_end:
    cmp byte [rdi], 0
    je .check_end
    inc rdi
    jmp .find_end

.check_end:
    ; rdi points to null terminator
    ; Check if char before null is "
    dec rdi                 ; rdi = last char
    cmp rdi, rsi            ; make sure string is at least 2 chars
    jle .done
    cmp byte [rdi], '"'
    jne .done

    ; Remove trailing quote by placing null there
    mov byte [rdi], 0

    ; Shift string left by 1 to remove leading quote
    mov rdi, rsi            ; dst = start
    lea rsi, [rsi + 1]     ; src = start + 1
.shift:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done_shifted
    inc rsi
    inc rdi
    jmp .shift

.done_shifted:
.done:
    pop rdi
    pop rsi
    ret

; ============================================================
; main - Entry point
; ============================================================
global main
main:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    ; Print banner
    lea rcx, [msg_banner]
    call print_console

    ; Print init message
    lea rcx, [msg_init]
    call print_console

    ; Load bot token from environment
    lea rcx, [env_token_name]
    lea rdx, [bot_token]
    mov r8, MAX_TOKEN_LEN
    call get_env_var

    test eax, eax
    jz .no_token

    ; Strip surrounding quotes if present (Windows set VAR="val" includes quotes)
    lea rcx, [bot_token]
    call strip_quotes

    lea rcx, [msg_token_load]
    call print_console

    ; Initialize command system
    mov cl, DEFAULT_PREFIX_CHAR
    call commands_init

    ; Register commands
    lea rcx, [msg_registering]
    call print_console
    call register_all_commands

    ; Start gateway connection (blocks until disconnect)
    lea rcx, [msg_starting]
    call print_console

    lea rcx, [bot_token]
    mov rdx, INTENTS_DEFAULT
    call gateway_connect

    ; Shutdown
    lea rcx, [msg_shutdown]
    call print_console

    xor ecx, ecx
    call ExitProcess

.no_token:
    lea rcx, [msg_no_token]
    call print_console
    mov ecx, 1
    call ExitProcess
