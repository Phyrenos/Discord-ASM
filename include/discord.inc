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
; Interaction types (Interaction.type)
; ============================================================
INTERACTION_TYPE_PING                   equ 1
INTERACTION_TYPE_APPLICATION_COMMAND    equ 2
INTERACTION_TYPE_MESSAGE_COMPONENT      equ 3
INTERACTION_TYPE_AUTOCOMPLETE           equ 4
INTERACTION_TYPE_MODAL_SUBMIT           equ 5

; ============================================================
; Interaction callback (response) types
; ============================================================
INTERACTION_CALLBACK_PONG                       equ 1
INTERACTION_CALLBACK_CHANNEL_MESSAGE            equ 4   ; reply with a message
INTERACTION_CALLBACK_DEFERRED_CHANNEL_MESSAGE   equ 5   ; ack, edit later
INTERACTION_CALLBACK_DEFERRED_UPDATE_MESSAGE    equ 6
INTERACTION_CALLBACK_UPDATE_MESSAGE             equ 7
INTERACTION_CALLBACK_AUTOCOMPLETE_RESULT        equ 8
INTERACTION_CALLBACK_MODAL                      equ 9

; ============================================================
; Application command types and option types
; ============================================================
APPLICATION_COMMAND_CHAT_INPUT          equ 1
APPLICATION_COMMAND_USER                equ 2
APPLICATION_COMMAND_MESSAGE             equ 3

CMD_OPTION_SUB_COMMAND                  equ 1
CMD_OPTION_SUB_COMMAND_GROUP            equ 2
CMD_OPTION_STRING                       equ 3
CMD_OPTION_INTEGER                      equ 4
CMD_OPTION_BOOLEAN                      equ 5
CMD_OPTION_USER                         equ 6
CMD_OPTION_CHANNEL                      equ 7
CMD_OPTION_ROLE                         equ 8
CMD_OPTION_MENTIONABLE                  equ 9
CMD_OPTION_NUMBER                       equ 10
CMD_OPTION_ATTACHMENT                   equ 11

; ============================================================
; Message flags / channel types / activity types
; ============================================================
MESSAGE_FLAG_CROSSPOSTED                equ (1 << 0)
MESSAGE_FLAG_SUPPRESS_EMBEDS            equ (1 << 2)
MESSAGE_FLAG_EPHEMERAL                  equ (1 << 6)   ; 64

CHANNEL_TYPE_GUILD_TEXT                 equ 0
CHANNEL_TYPE_DM                         equ 1
CHANNEL_TYPE_GUILD_VOICE                equ 2
CHANNEL_TYPE_GROUP_DM                   equ 3
CHANNEL_TYPE_GUILD_CATEGORY             equ 4
CHANNEL_TYPE_GUILD_ANNOUNCEMENT         equ 5
CHANNEL_TYPE_PUBLIC_THREAD              equ 11
CHANNEL_TYPE_PRIVATE_THREAD             equ 12

ACTIVITY_TYPE_PLAYING                   equ 0
ACTIVITY_TYPE_STREAMING                 equ 1
ACTIVITY_TYPE_LISTENING                 equ 2
ACTIVITY_TYPE_WATCHING                  equ 3
ACTIVITY_TYPE_COMPETING                 equ 5

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
MAX_EVENTS                      equ 64
MAX_INTERACTION_CMDS            equ 64
MAX_SESSION_ID_LEN              equ 128
MAX_RESUME_URL_LEN              equ 256
MAX_ACTIVITY_LEN                equ 256

; ============================================================
; Reconnection / backoff tuning
; ============================================================
MAX_RECONNECT_ATTEMPTS          equ 10      ; give up after this many consecutive failures
RECONNECT_BASE_MS               equ 1000    ; first backoff delay
RECONNECT_MAX_MS                equ 30000   ; backoff cap

; Command prefix
DEFAULT_PREFIX_CHAR             equ '!'

; ============================================================
; Environment variable names (defined in bot.asm)
; ============================================================
; DISCORD_TOKEN    - bot token (required)
; DISCORD_INTENTS  - integer gateway intents bitmask (optional)
; DISCORD_ACTIVITY - presence activity text (optional)
