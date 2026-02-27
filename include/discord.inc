; discord.inc - Discord API constants, opcodes, intents

; ============================================================
; Discord Gateway Opcodes
; ============================================================
GATEWAY_OP_DISPATCH             equ 0   ; Receive: event dispatch
GATEWAY_OP_HEARTBEAT            equ 1   ; Send/Receive: heartbeat
GATEWAY_OP_IDENTIFY             equ 2   ; Send: identify
GATEWAY_OP_PRESENCE_UPDATE      equ 3   ; Send: update presence
GATEWAY_OP_VOICE_STATE_UPDATE   equ 4   ; Send: voice state
GATEWAY_OP_RESUME               equ 6   ; Send: resume
GATEWAY_OP_RECONNECT            equ 7   ; Receive: reconnect
GATEWAY_OP_REQUEST_GUILD_MEMBERS equ 8  ; Send: request guild members
GATEWAY_OP_INVALID_SESSION      equ 9   ; Receive: invalid session
GATEWAY_OP_HELLO                equ 10  ; Receive: hello
GATEWAY_OP_HEARTBEAT_ACK        equ 11  ; Receive: heartbeat ACK

; ============================================================
; Discord Gateway Intents
; ============================================================
INTENT_GUILDS                   equ (1 << 0)
INTENT_GUILD_MEMBERS            equ (1 << 1)
INTENT_GUILD_MODERATION         equ (1 << 2)
INTENT_GUILD_EMOJIS             equ (1 << 3)
INTENT_GUILD_INTEGRATIONS       equ (1 << 4)
INTENT_GUILD_WEBHOOKS           equ (1 << 5)
INTENT_GUILD_INVITES            equ (1 << 6)
INTENT_GUILD_VOICE_STATES       equ (1 << 7)
INTENT_GUILD_PRESENCES          equ (1 << 8)
INTENT_GUILD_MESSAGES           equ (1 << 9)
INTENT_GUILD_MESSAGE_REACTIONS  equ (1 << 10)
INTENT_GUILD_MESSAGE_TYPING     equ (1 << 11)
INTENT_DIRECT_MESSAGES          equ (1 << 12)
INTENT_DIRECT_MESSAGE_REACTIONS equ (1 << 13)
INTENT_DIRECT_MESSAGE_TYPING    equ (1 << 14)
INTENT_MESSAGE_CONTENT          equ (1 << 15)

; Common intent combo for a message bot
INTENTS_DEFAULT equ (INTENT_GUILDS | INTENT_GUILD_MESSAGES | INTENT_MESSAGE_CONTENT)

; ============================================================
; Discord API Constants
; ============================================================
DISCORD_API_VERSION             equ 10
MAX_MESSAGE_LEN                 equ 2000
MAX_JSON_PAYLOAD                equ 4096
MAX_WS_RECV_BUF                equ 65536
MAX_TOKEN_LEN                   equ 256
MAX_CHANNEL_ID_LEN              equ 32
MAX_URL_LEN                     equ 512
MAX_COMMAND_NAME                equ 32
MAX_COMMANDS                    equ 64

; Command prefix
DEFAULT_PREFIX_CHAR             equ '!'
