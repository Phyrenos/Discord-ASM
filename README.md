# Discord Bot - Pure x86-64 Assembly (NASM)

A fully functional Discord bot written entirely in x86-64 assembly using NASM for Windows. Connects to the Discord Gateway via WebSocket, handles heartbeats, receives events, and responds to commands - all in pure assembly calling Windows APIs directly.

## Features

- WebSocket connection to Discord Gateway (WSS), Gateway API v10
- Automatic heartbeat with a **zombie-connection watchdog**
- **Auto-reconnect with RESUME** (op 6) and exponential backoff; fatal close
  codes (bad token/intents) stop instead of looping
- **Registered event-handler table** — MESSAGE_CREATE, GUILD_CREATE,
  GUILD_MEMBER_ADD, reactions, typing, channel events, INTERACTION_CREATE, ...
- Prefix-based command system (`!ping`, `!hello`, `!info`, `!react`, ...)
- **Slash commands / interactions** — registers application commands and replies
  to INTERACTION_CREATE (normal + ephemeral)
- Gateway send-side opcodes: **presence update**, request guild members, voice
  state update (no audio)
- **Broad REST coverage** — messages, reactions, channels, guilds, members,
  roles, bans, users, webhooks, emojis, invites, threads, application commands
- Generic `rest_call` transport with **HTTP 429 rate-limit retry**
- JSON builder with automatic string **escaping**, plus a parser with nested
  key-paths and array iteration
- Bot **presence/activity** and env-configurable intents
- Console logging for connection status

## Architecture

```
include/
  macros.inc        Stack frame and calling convention macros
  winapi.inc        Windows API extern declarations and constants
  discord.inc       Opcodes, intents, interaction/command/channel/flag constants

src/
  bot.asm           Entry point, env config, %includes every module
  strings.asm       String utils + asm_json_escape / asm_url_encode
  json.asm          JSON parser: key find, nested paths, array count/get
  jsonbuild.asm     JSON builder (auto-escaping, comma tracking)
  http.asm          WinHTTP wrappers (session, connect, request, websocket, status)
  rest_core.asm     Generic rest_call transport + 429 rate-limit retry
  rest.asm          Core endpoints (send message, reaction) + shared paths/helper
  rest_messages.asm Message + reaction endpoints (edit/delete/pin/bulk/...)
  rest_channels.asm Channel endpoints (typing, DM, modify, invites, ...)
  rest_guilds.asm   Guild/member/role/ban endpoints (kick, ban, roles, audit log)
  rest_users.asm    User endpoints (current user, get user, leave guild, ...)
  rest_webhooks.asm Webhook create/delete/execute
  rest_misc.asm     Emojis, invites, threads, prune
  rest_app_commands.asm  Slash-command registration (global + guild)
  heartbeat.asm     Heartbeat thread, watchdog, generation-safe restart
  gateway.asm       Gateway connect, reconnect/RESUME loop, opcode dispatch
  gateway_send.asm  Send-side opcodes: presence, request members, voice state
  commands.asm      Prefix command table, parsing, dispatch
  command_handlers.asm  Built-in prefix command implementations
  events.asm        Event-handler table + dispatch + handlers (MESSAGE_CREATE, ...)
  interactions.asm  Interaction table, INTERACTION_CREATE, responses, slash setup

examples/
  ping_bot.asm      Documentation and usage guide for the built-in bot
```

## Requirements

- Windows x64
- [NASM](https://www.nasm.us/) (Netwide Assembler)
- Visual Studio Build Tools (`link.exe`) - run from an **x64 Native Tools Command Prompt**
- A Discord bot token with **Message Content Intent** enabled

## Build

From an x64 Native Tools Command Prompt:

```bat
build.bat
```

Output: `build\bot.exe`

## Usage

1. **Create a Discord bot** at https://discord.com/developers/applications
2. Enable **Message Content Intent** under Privileged Gateway Intents
3. Generate an invite URL with `bot` scope and `Send Messages` permission
4. Invite the bot to your server

```bat
set DISCORD_TOKEN=your_bot_token_here
build\bot.exe
```

## Environment variables

| Variable           | Required | Purpose |
|--------------------|----------|---------|
| `DISCORD_TOKEN`    | yes      | Bot token |
| `DISCORD_INTENTS`  | no       | Integer gateway intents bitmask (default: guilds + guild messages + message content) |
| `DISCORD_ACTIVITY` | no       | Presence activity text (default: "pure x86-64 assembly") |
| `DISCORD_APP_ID`   | no       | Application id for slash commands (otherwise read from READY) |
| `DISCORD_GUILD_ID` | no       | If set, slash commands register to this guild (instant) instead of globally |

## Built-in Commands

| Command  | Response |
|----------|----------|
| `!ping`  | Pong! |
| `!hello` | Hello, \<username\>! |
| `!info`  | Bot info message |

## Adding Custom Commands

1. Define a command name in the `.data` section of `src/bot.asm`:
   ```nasm
   cmd_name_mycommand: db "mycommand", 0
   ```

2. Write a handler (follows x64 ABI: rcx=channel_id, rdx=args, r8=author):
   ```nasm
   cmd_handler_mycommand:
       push rbp
       mov rbp, rsp
       sub rsp, 64
       mov [rbp-8], rcx          ; save channel_id
       lea rcx, [bot_token]
       mov rdx, [rbp-8]
       lea r8, [my_response]     ; your response string
       call rest_send_message
       mov rsp, rbp
       pop rbp
       ret
   ```

3. Register it in `register_builtin_commands`:
   ```nasm
   lea rcx, [cmd_name_mycommand]
   lea rdx, [cmd_handler_mycommand]
   call register_command
   ```

## Calling the REST API

All endpoints go through `rest_call` (in `rest_core.asm`), which manages the
connection, `Authorization: Bot <token>` header, wide-path conversion, and 429
retry. Build paths with `rc_build_path` (up to 5 pieces) and bodies with the JSON
builder (`jb_*`), which escapes string values automatically:

```nasm
; POST /channels/{id}/typing
lea  rcx, [p_channels]
mov  rdx, [my_channel_id]
lea  r8,  [s_typing]
xor  r9, r9
mov  qword [rsp+32], 0
call rc_build_path
lea  rcx, [w_method_POST]
lea  rdx, [rest_path_buf]
xor  r8, r8
xor  r9, r9
call rest_call_simple        ; rax = 1 on 2xx/3xx
```

Endpoints that return data (`rest_get_*`) call `rest_call` directly and return a
heap response buffer you must release with `http_free_response`.

## Adding a gateway event handler

Handlers receive `rcx` = the event's `d` object, `rdx` = event name, `r8` = full
payload. Register in `register_all_events` (`events.asm`):

```nasm
lea rcx, [ev_name_typing_start]   ; the event-name string
lea rdx, [my_typing_handler]
call register_event_handler
```

## Adding a slash command

1. Add a name/description and a handler (`rcx`=interaction id, `rdx`=token,
   `r8`=`d`) in `interactions.asm`; reply with `interaction_respond`
   (callback type `INTERACTION_CALLBACK_CHANNEL_MESSAGE`, flags
   `MESSAGE_FLAG_EPHEMERAL` for ephemeral).
2. Register the handler in `register_all_interactions` via
   `register_interaction_command`.
3. Register the command with Discord in `register_slash_commands_with_discord`
   via `register_one_slash` (guild-scoped if `DISCORD_GUILD_ID` is set, else
   global). This runs once automatically on READY.

## How It Works

1. Reads `DISCORD_TOKEN` from environment
2. Initializes WinHTTP session
3. Connects to `gateway.discord.gg` via WebSocket (TLS)
4. Receives Hello (op 10), starts heartbeat thread
5. Sends Identify (op 2) with token and intents
6. Enters event loop: receives Gateway events, dispatches MESSAGE_CREATE to command handlers
7. Command handlers call REST API to send reply messages

## Windows APIs Used

All functionality comes from calling Windows DLLs directly - no C runtime dependencies beyond `sprintf` for number formatting:

- **winhttp.dll** - HTTPS requests and WebSocket
- **kernel32.dll** - Process, heap, threads, console I/O
- **msvcrt.dll** - `sprintf` for payload formatting

## Notes

- Single-bot, single-process design (global state). REST calls run on the
  gateway thread, so the shared REST/JSON buffers are used serially.
- JSON parser is targeted for Discord payloads, not a general-purpose parser
- Bot messages are ignored to prevent self-reply loops
- Reconnect/RESUME is automatic with exponential backoff; only fatal close codes
  (e.g. bad token, disallowed intents) stop the bot
- RESUME reconnects to the main gateway host (not `resume_gateway_url`); if the
  gateway rejects the resume it falls back to a fresh IDENTIFY automatically
- Out of scope (pure WinHTTP / no external deps): voice audio, gateway zlib/ETF
  compression, and multipart file (attachment) uploads
