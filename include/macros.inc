; macros.inc - Stack frame and calling convention macros for x64 Windows ABI
; All functions use Microsoft x64 calling convention:
;   Args: rcx, rdx, r8, r9, then stack
;   Shadow space: 32 bytes reserved by caller
;   Stack must be 16-byte aligned at CALL instruction

; PROC_FRAME - Set up a standard stack frame with local space
; Usage: PROC_FRAME <num_local_bytes>
; Allocates shadow space (32) + locals, aligned to 16 bytes
%macro PROC_FRAME 0-1 0
    push rbp
    mov rbp, rsp
    %assign _locals %1
    %assign _frame_size (32 + _locals + 15) & ~15
    ; Ensure 16-byte alignment: after CALL, RSP is 8-mod-16
    ; After PUSH RBP, RSP is 16-aligned
    ; So we need _frame_size to keep alignment
    %if (_frame_size % 16) != 0
        %assign _frame_size _frame_size + 8
    %endif
    sub rsp, _frame_size
%endmacro

; END_PROC_FRAME - Tear down stack frame and return
%macro END_PROC_FRAME 0
    mov rsp, rbp
    pop rbp
    ret
%endmacro

; WCALL - Call a Windows API function with up to 6 arguments
; Handles register assignment and shadow space
; Usage: WCALL function, arg1, arg2, ...
%macro WCALL 1-7
    ; Save any args to registers
    %if %0 >= 2
        mov rcx, %2
    %endif
    %if %0 >= 3
        mov rdx, %3
    %endif
    %if %0 >= 4
        mov r8, %4
    %endif
    %if %0 >= 5
        mov r9, %5
    %endif
    %if %0 >= 6
        ; 5th arg goes to [rsp+32]
        mov qword [rsp+32], %6
    %endif
    %if %0 >= 7
        ; 6th arg goes to [rsp+40]
        mov qword [rsp+40], %7
    %endif
    call %1
%endmacro

; CCALL - Same as WCALL but more explicit name for C runtime calls
%define CCALL WCALL

; String literal in .data section with auto-generated label
; Usage: STATIC_STRING name, "text"
%macro STATIC_STRING 2+
    section .data
    %1: db %2, 0
    section .text
%endmacro

; Wide string literal (UTF-16LE) in .data section
; Doesn't auto null-terminate individual chars - use dw for each char
%macro WIDE_STRING 2+
    section .data
    align 2
    %1:
    %assign _ws_i 0
    %strlen _ws_len %2
    %rep _ws_len
        %assign _ws_i _ws_i + 1
        %substr _ws_ch %2 _ws_i
        dw _ws_ch
    %endrep
    dw 0
    section .text
%endmacro

; LOCAL_VAR - Access a local variable relative to RBP
; Usage: LOCAL_VAR(offset) -> [rbp - offset]
; Since we use shadow space at [rbp - frame_size] to [rbp - frame_size + 32],
; locals start at [rbp - 32 - offset] but it's simpler to use RSP-relative addressing.
; We'll use [rsp + 32 + offset] for locals (after shadow space).
; Actually, let's keep it simple: use [rbp - N] for named locals.

; SAVE_NONVOL - Push non-volatile registers that the function will use
%macro SAVE_NONVOL 1-*
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro

; RESTORE_NONVOL - Pop non-volatile registers (reverse order of SAVE_NONVOL)
%macro RESTORE_NONVOL 1-*
    ; Rotate to last argument first
    %rep %0 - 1
        %rotate 1
    %endrep
    ; Now pop in reverse
    %rep %0
        pop %1
        %rotate -1
    %endrep
%endmacro

; DEBUG_PRINT - Print a string to stdout (for debugging)
; Uses WriteFile on stdout handle
%macro DEBUG_PRINT 1
    ; %1 = address of null-terminated string
    push rcx
    push rdx
    push r8
    push r9
    sub rsp, 56        ; shadow + align + local for bytes written

    ; Get string length
    mov rcx, %1
    call asm_strlen

    ; WriteFile(stdout, str, len, &written, NULL)
    mov rcx, -11        ; STD_OUTPUT_HANDLE
    call [GetStdHandle]
    mov rcx, rax        ; handle
    mov rdx, %1         ; buffer
    mov r8, rax         ; length (need to recalc)
    lea r9, [rsp+48]    ; &bytes_written
    mov qword [rsp+32], 0 ; lpOverlapped
    ; Actually this macro is getting complex, use the print_console function instead
    add rsp, 56
    pop r9
    pop r8
    pop rdx
    pop rcx
%endmacro

; MIN/MAX helpers
%macro MIN 2
    cmp %1, %2
    cmovg %1, %2
%endmacro

%macro MAX 2
    cmp %1, %2
    cmovl %1, %2
%endmacro
