; winapi.inc - Windows API extern declarations and constants

; ============================================================
; kernel32.dll imports
; ============================================================
extern ExitProcess
extern GetProcessHeap
extern HeapAlloc
extern HeapFree
extern HeapReAlloc
extern Sleep
extern CreateThread
extern WaitForSingleObject
extern CloseHandle
extern GetLastError
extern GetStdHandle
extern WriteFile
extern GetTickCount64
extern lstrlenA
extern lstrcpyA
extern MultiByteToWideChar
extern WideCharToMultiByte
extern GetEnvironmentVariableA

; ============================================================
; winhttp.dll imports
; ============================================================
extern WinHttpOpen
extern WinHttpConnect
extern WinHttpOpenRequest
extern WinHttpSetOption
extern WinHttpAddRequestHeaders
extern WinHttpSendRequest
extern WinHttpReceiveResponse
extern WinHttpReadData
extern WinHttpQueryDataAvailable
extern WinHttpWebSocketCompleteUpgrade
extern WinHttpWebSocketSend
extern WinHttpWebSocketReceive
extern WinHttpWebSocketQueryCloseStatus
extern WinHttpCloseHandle
extern WinHttpSetStatusCallback
extern WinHttpQueryHeaders

; ============================================================
; Constants
; ============================================================

; Heap flags
HEAP_ZERO_MEMORY        equ 0x00000008

; Standard handles
STD_OUTPUT_HANDLE       equ -11

; Code page
CP_UTF8                 equ 65001

; WinHTTP constants
WINHTTP_ACCESS_TYPE_DEFAULT_PROXY   equ 0
WINHTTP_NO_PROXY_NAME               equ 0
WINHTTP_NO_PROXY_BYPASS              equ 0
WINHTTP_NO_REFERER                   equ 0
WINHTTP_DEFAULT_ACCEPT_TYPES         equ 0
WINHTTP_NO_ADDITIONAL_HEADERS        equ 0
WINHTTP_NO_REQUEST_DATA              equ 0
WINHTTP_HEADER_NAME_BY_INDEX         equ 0
WINHTTP_NO_OUTPUT_BUFFER             equ 0

WINHTTP_FLAG_SECURE                  equ 0x00800000

; WinHTTP option constants
WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET equ 114
WINHTTP_OPTION_SECURE_PROTOCOLS      equ 84

; WinHttpQueryHeaders info levels / flags
WINHTTP_QUERY_STATUS_CODE            equ 19
WINHTTP_QUERY_FLAG_NUMBER            equ 0x20000000
WINHTTP_NO_HEADER_INDEX              equ 0

; WinHTTP secure protocols
WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2  equ 0x00000800
WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3  equ 0x00002000

; WinHTTP WebSocket buffer types
WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE    equ 0
WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE   equ 1
WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE      equ 2
WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE     equ 3
WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE             equ 4

; WinHTTP add request headers flags
WINHTTP_ADDREQ_FLAG_ADD              equ 0x20000000
WINHTTP_ADDREQ_FLAG_REPLACE          equ 0x80000000

; HTTP port
INTERNET_DEFAULT_HTTPS_PORT          equ 443

; Internet schemes
INTERNET_SCHEME_HTTPS                equ 2

; Callback flags
WINHTTP_CALLBACK_FLAG_ALL_COMPLETIONS equ 0x000FFFFF

; MultiByteToWideChar / WideCharToMultiByte flags
MB_PRECOMPOSED          equ 0x00000001

; Thread constants
INFINITE                equ 0xFFFFFFFF

; Boolean
TRUE                    equ 1
FALSE                   equ 0
NULL                    equ 0

; INTERNET_PORT is WORD (16-bit)
; HTTP methods as wide strings are defined in http.asm
