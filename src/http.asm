; http.asm - WinHTTP wrapper functions for HTTPS and WebSocket

; ============================================================
; Global state for HTTP session
; ============================================================
section .bss
    g_hSession:     resq 1      ; WinHTTP session handle
    g_hConnect:     resq 1      ; WinHTTP connection handle (gateway)
    g_hWebSocket:   resq 1      ; WebSocket handle
    wide_buf:       resw 1024   ; Temp wide string buffer

section .data
    ; User agent (wide string)
    w_user_agent:
        dw 'D','i','s','c','o','r','d','B','o','t',' ','('
        dw 'A','S','M',',',' ','v','1','.','0',')', 0

    ; HTTP methods (wide strings)
    w_method_GET:   dw 'G','E','T', 0
    w_method_POST:  dw 'P','O','S','T', 0
    w_method_PUT:   dw 'P','U','T', 0

    ; Gateway host (wide string)
    w_gateway_host: dw 'g','a','t','e','w','a','y','.','d','i','s','c','o','r','d','.','g','g', 0

    ; Discord API host (wide string)
    w_discord_host: dw 'd','i','s','c','o','r','d','.','c','o','m', 0

    ; Content-Type header (wide string)
    w_content_type:
        dw 'C','o','n','t','e','n','t','-','T','y','p','e',':',' '
        dw 'a','p','p','l','i','c','a','t','i','o','n','/','j','s','o','n', 0

    ; Gateway WebSocket path (wide string) - /?v=10&encoding=json
    w_gateway_ws_path:
        dw '/','?','v','=','1','0','&','e','n','c','o','d','i','n','g','=','j','s','o','n', 0

section .text

; ============================================================
; http_init - Initialize WinHTTP session
; No args
; Returns: rax = session handle, or 0 on failure
; ============================================================
http_init:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; WinHttpOpen(user_agent, access_type, proxy, proxy_bypass, flags)
    lea rcx, [w_user_agent]
    mov edx, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY
    xor r8, r8              ; no proxy
    xor r9, r9              ; no proxy bypass
    mov qword [rsp+32], 0   ; no flags
    call WinHttpOpen

    test rax, rax
    jz .done

    mov [g_hSession], rax

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; http_connect - Connect to a host
; rcx = wide host string
; Returns: rax = connection handle, or 0 on failure
; ============================================================
http_connect:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; WinHttpConnect(hSession, serverName, port, reserved)
    mov rdx, rcx            ; server name
    mov rcx, [g_hSession]   ; session handle
    mov r8d, INTERNET_DEFAULT_HTTPS_PORT
    xor r9d, r9d            ; reserved
    call WinHttpConnect

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; http_request - Make an HTTPS request
; rcx = connection handle
; rdx = wide method string (GET/POST)
; r8  = wide path string
; r9  = request body (UTF-8, or NULL)
; [rbp+48] = body length (0 if no body)
; [rbp+56] = auth header (wide string, or NULL)
; Returns: rax = pointer to response data (heap allocated), 0 on error
;          [http_response_len] = response length
; ============================================================
section .bss
    http_response_len: resq 1

section .text
http_request:
    push rbp
    mov rbp, rsp
    sub rsp, 192           ; generous space for locals and shadow

    ; Save all args
    mov [rbp-8], rcx       ; connection handle
    mov [rbp-16], rdx      ; method
    mov [rbp-24], r8       ; path
    mov [rbp-32], r9       ; body
    mov rax, [rbp+48]
    mov [rbp-40], rax      ; body length
    mov rax, [rbp+56]
    mov [rbp-48], rax      ; auth header

    ; WinHttpOpenRequest(hConnect, method, path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE)
    mov rcx, [rbp-8]       ; hConnect
    mov rdx, [rbp-16]      ; method
    mov r8, [rbp-24]       ; path
    xor r9, r9             ; version (NULL = HTTP/1.1)
    mov qword [rsp+32], 0  ; referrer
    mov qword [rsp+40], 0  ; accept types
    mov qword [rsp+48], WINHTTP_FLAG_SECURE
    call WinHttpOpenRequest

    test rax, rax
    jz .error
    mov [rbp-56], rax      ; hRequest

    ; Add auth header if provided
    cmp qword [rbp-48], 0
    je .no_auth

    ; WinHttpAddRequestHeaders(hRequest, header, -1, flags)
    mov rcx, [rbp-56]
    mov rdx, [rbp-48]      ; auth header (wide)
    mov r8, -1              ; auto-length
    mov r9d, WINHTTP_ADDREQ_FLAG_ADD
    call WinHttpAddRequestHeaders

.no_auth:
    ; Add Content-Type if we have a body
    cmp qword [rbp-40], 0
    je .send

    mov rcx, [rbp-56]
    lea rdx, [w_content_type]
    mov r8, -1
    mov r9d, WINHTTP_ADDREQ_FLAG_ADD
    call WinHttpAddRequestHeaders

.send:
    ; WinHttpSendRequest(hRequest, headers, headersLen, body, bodyLen, totalLen, context)
    mov rcx, [rbp-56]      ; hRequest
    xor rdx, rdx           ; no additional headers
    xor r8d, r8d           ; headers length = 0
    mov r9, [rbp-32]       ; body (or NULL)
    mov rax, [rbp-40]      ; body length
    mov [rsp+32], rax      ; dwOptionalLength
    mov [rsp+40], rax      ; dwTotalLength
    mov qword [rsp+48], 0  ; context
    call WinHttpSendRequest

    test eax, eax
    jz .close_request

    ; WinHttpReceiveResponse(hRequest, NULL)
    mov rcx, [rbp-56]
    xor rdx, rdx
    call WinHttpReceiveResponse

    test eax, eax
    jz .close_request

    ; Allocate response buffer
    call GetProcessHeap
    mov [rbp-64], rax      ; heap handle

    mov rcx, rax
    mov edx, HEAP_ZERO_MEMORY
    mov r8, MAX_WS_RECV_BUF
    call HeapAlloc

    test rax, rax
    jz .close_request
    mov [rbp-72], rax      ; response buffer
    mov qword [rbp-80], 0  ; total bytes read

    ; Read response data
.read_loop:
    ; WinHttpReadData(hRequest, buffer+offset, remaining, &bytesRead)
    mov rcx, [rbp-56]                  ; hRequest
    mov rdx, [rbp-72]
    add rdx, [rbp-80]                  ; buffer + offset
    mov r8, MAX_WS_RECV_BUF
    sub r8, [rbp-80]                   ; remaining space
    test r8, r8
    jle .read_done
    lea r9, [rbp-88]                   ; &bytesRead
    call WinHttpReadData

    test eax, eax
    jz .read_done

    mov rax, [rbp-88]                  ; bytes read this time
    test rax, rax
    jz .read_done

    add [rbp-80], rax
    jmp .read_loop

.read_done:
    ; Null-terminate
    mov rax, [rbp-72]
    mov rcx, [rbp-80]
    mov byte [rax + rcx], 0

    ; Store response length
    mov rcx, [rbp-80]
    mov [http_response_len], rcx

    ; Close request handle
    mov rcx, [rbp-56]
    call WinHttpCloseHandle

    ; Return response buffer
    mov rax, [rbp-72]
    jmp .done

.close_request:
    mov rcx, [rbp-56]
    call WinHttpCloseHandle

.error:
    xor eax, eax
    mov qword [http_response_len], 0

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; http_free_response - Free a heap-allocated response buffer
; rcx = buffer pointer
; ============================================================
http_free_response:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    test rcx, rcx
    jz .done

    mov r8, rcx             ; buffer to free
    call GetProcessHeap
    mov rcx, rax            ; heap handle
    xor edx, edx            ; flags
    ; r8 already set
    call HeapFree

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; ws_connect - Establish WebSocket connection to Discord Gateway
; No args (uses g_hSession, connects to gateway.discord.gg)
; Returns: rax = WebSocket handle, or 0 on failure
; ============================================================
ws_connect:
    push rbp
    mov rbp, rsp
    sub rsp, 160

    ; Connect to gateway.discord.gg
    lea rcx, [w_gateway_host]
    call http_connect
    test rax, rax
    jz .error
    mov [g_hConnect], rax
    mov [rbp-8], rax

    ; Open GET request for WebSocket upgrade path
    ; WinHttpOpenRequest(hConnect, "GET", path, NULL, NULL, NULL, SECURE)
    mov rcx, rax
    lea rdx, [w_method_GET]
    lea r8, [w_gateway_ws_path]
    xor r9, r9
    mov qword [rsp+32], 0
    mov qword [rsp+40], 0
    mov qword [rsp+48], WINHTTP_FLAG_SECURE
    call WinHttpOpenRequest

    test rax, rax
    jz .error
    mov [rbp-16], rax      ; hRequest

    ; Set WebSocket upgrade option
    ; WinHttpSetOption(hRequest, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, NULL, 0)
    mov rcx, rax
    mov edx, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET
    xor r8, r8
    xor r9d, r9d
    call WinHttpSetOption

    test eax, eax
    jz .close_req

    ; Send the request
    ; WinHttpSendRequest(hRequest, NULL, 0, NULL, 0, 0, 0)
    mov rcx, [rbp-16]
    xor rdx, rdx
    xor r8d, r8d
    xor r9, r9
    mov qword [rsp+32], 0
    mov qword [rsp+40], 0
    mov qword [rsp+48], 0
    call WinHttpSendRequest

    test eax, eax
    jz .close_req

    ; Receive the response (101 Switching Protocols expected)
    mov rcx, [rbp-16]
    xor rdx, rdx
    call WinHttpReceiveResponse

    test eax, eax
    jz .close_req

    ; Complete WebSocket upgrade
    ; WinHttpWebSocketCompleteUpgrade(hRequest, context)
    mov rcx, [rbp-16]
    xor rdx, rdx
    call WinHttpWebSocketCompleteUpgrade

    test rax, rax
    jz .close_req

    mov [g_hWebSocket], rax
    mov [rbp-24], rax

    ; Close the request handle (no longer needed after upgrade)
    mov rcx, [rbp-16]
    call WinHttpCloseHandle

    mov rax, [rbp-24]
    jmp .done

.close_req:
    mov rcx, [rbp-16]
    call WinHttpCloseHandle
.error:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; ws_send - Send data over WebSocket
; rcx = data buffer (UTF-8)
; rdx = data length
; Returns: rax = 0 on success, error code otherwise
; ============================================================
ws_send:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; WinHttpWebSocketSend(hWebSocket, bufferType, buffer, bufferLength)
    mov r8, rcx             ; buffer
    mov r9, rdx             ; buffer length
    mov rcx, [g_hWebSocket] ; WebSocket handle
    mov edx, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE
    call WinHttpWebSocketSend

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; ws_recv - Receive data from WebSocket
; rcx = buffer
; rdx = buffer size
; r8  = pointer to DWORD for bytes read
; r9  = pointer to DWORD for buffer type
; Returns: rax = 0 on success, error code otherwise
; ============================================================
ws_recv:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; WinHttpWebSocketReceive(hWebSocket, buffer, bufferLen, &bytesRead, &bufferType)
    mov [rsp+32], r9       ; &bufferType (5th arg)
    mov r9, r8             ; &bytesRead
    mov r8, rdx            ; bufferLen
    mov rdx, rcx           ; buffer
    mov rcx, [g_hWebSocket]
    call WinHttpWebSocketReceive

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; ws_close - Close WebSocket connection
; ============================================================
ws_close:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    cmp qword [g_hWebSocket], 0
    je .skip_ws
    mov rcx, [g_hWebSocket]
    call WinHttpCloseHandle
    mov qword [g_hWebSocket], 0
.skip_ws:

    cmp qword [g_hConnect], 0
    je .skip_conn
    mov rcx, [g_hConnect]
    call WinHttpCloseHandle
    mov qword [g_hConnect], 0
.skip_conn:

    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; http_cleanup - Close all WinHTTP handles
; ============================================================
http_cleanup:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    call ws_close

    cmp qword [g_hSession], 0
    je .done
    mov rcx, [g_hSession]
    call WinHttpCloseHandle
    mov qword [g_hSession], 0

.done:
    mov rsp, rbp
    pop rbp
    ret

; ============================================================
; make_auth_header_wide - Build "Authorization: Bot <token>" as wide string
; rcx = token (UTF-8)
; rdx = output wide buffer
; r8  = output buffer size in WCHARs
; Returns: rax = wide string pointer (= rdx)
; ============================================================
section .data
    auth_prefix: db "Authorization: Bot ", 0

section .bss
    auth_header_buf: resb 512   ; temp UTF-8 buffer

section .text
make_auth_header_wide:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp-8], rcx       ; token
    mov [rbp-16], rdx      ; wide output
    mov [rbp-24], r8       ; wide buf size

    ; Build "Authorization: Bot <token>" in temp buffer
    lea rcx, [auth_header_buf]
    lea rdx, [auth_prefix]
    call asm_strcpy

    lea rcx, [auth_header_buf]
    mov rdx, [rbp-8]
    call asm_strcat

    ; Convert to wide
    lea rcx, [auth_header_buf]
    mov rdx, [rbp-16]
    mov r8, [rbp-24]
    call asm_to_wide

    mov rax, [rbp-16]

    mov rsp, rbp
    pop rbp
    ret
