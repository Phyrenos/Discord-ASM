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

    ; Environment variable names
    env_token_name:    db "DISCORD_TOKEN", 0
    env_intents_name:  db "DISCORD_INTENTS", 0
    env_activity_name: db "DISCORD_ACTIVITY", 0
    env_appid_name:    db "DISCORD_APP_ID", 0
    env_guildid_name:  db "DISCORD_GUILD_ID", 0

    ; Default presence activity text (overridable via DISCORD_ACTIVITY)
    default_activity:  db "Made in discord ASM https://github.com/Phyrenos/Discord-ASM/", 0

    msg_intents:       db "[Bot] Intents: ", 0
    msg_activity:      db "[Bot] Activity: ", 0



section .bss
    bot_token:      resb MAX_TOKEN_LEN  ; Bot token from environment
    cmd_resp_buf:   resb 512            ; Buffer for building command responses
    g_activity:     resb MAX_ACTIVITY_LEN ; Presence activity text (read by gateway.asm)
    intents_env_buf:resb 32             ; Raw DISCORD_INTENTS env value
    g_intents_val:  resq 1              ; Resolved intents bitmask

; ============================================================
; Text section - All code
; ============================================================
section .text

; Include all source modules
%include "strings.asm"
%include "json.asm"
%include "jsonbuild.asm"
%include "http.asm"
%include "rest_core.asm"
%include "heartbeat.asm"
%include "commands.asm"
%include "rest.asm"
%include "rest_messages.asm"
%include "rest_channels.asm"
%include "rest_guilds.asm"
%include "rest_users.asm"
%include "rest_webhooks.asm"
%include "rest_misc.asm"
%include "rest_app_commands.asm"
%include "gateway.asm"
%include "gateway_send.asm"
%include "events.asm"
%include "interactions.asm"

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

    ; Register gateway event handlers
    call register_all_events

    ; Register slash-command handlers + INTERACTION_CREATE handler
    call register_all_interactions

    ; --- Optional: application id / guild id for slash commands ---
    lea rcx, [env_appid_name]
    lea rdx, [g_application_id]
    mov r8, 64
    call get_env_var
    test eax, eax
    jz .appid_done
    lea rcx, [g_application_id]
    call strip_quotes
.appid_done:
    lea rcx, [env_guildid_name]
    lea rdx, [g_guild_id]
    mov r8, 64
    call get_env_var
    test eax, eax
    jz .guildid_done
    lea rcx, [g_guild_id]
    call strip_quotes
.guildid_done:

    ; --- Resolve presence activity (DISCORD_ACTIVITY env, else default) ---
    lea rcx, [env_activity_name]
    lea rdx, [g_activity]
    mov r8, MAX_ACTIVITY_LEN
    call get_env_var
    test eax, eax
    jz .activity_default
    lea rcx, [g_activity]      ; env may wrap the value in quotes
    call strip_quotes
    jmp .activity_done
.activity_default:
    lea rcx, [g_activity]
    lea rdx, [default_activity]
    call asm_strcpy
.activity_done:
    lea rcx, [msg_activity]
    call print_console
    lea rcx, [g_activity]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    ; --- Resolve intents (DISCORD_INTENTS env, else INTENTS_DEFAULT) ---
    lea rcx, [env_intents_name]
    lea rdx, [intents_env_buf]
    mov r8, 32
    call get_env_var
    test eax, eax
    jz .intents_default
    lea rcx, [intents_env_buf]
    call strip_quotes
    lea rcx, [intents_env_buf]
    call asm_str_to_int
    mov [g_intents_val], rax
    jmp .intents_done
.intents_default:
    mov qword [g_intents_val], INTENTS_DEFAULT
.intents_done:
    lea rcx, [msg_intents]
    call print_console
    mov rcx, [g_intents_val]
    lea rdx, [intents_env_buf]
    call asm_itoa
    lea rcx, [intents_env_buf]
    call print_console
    lea rcx, [msg_newline]
    call print_console

    ; Start gateway connection (blocks until disconnect)
    lea rcx, [msg_starting]
    call print_console

    lea rcx, [bot_token]
    mov rdx, [g_intents_val]
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
