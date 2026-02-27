# Discord Bot - Pure x86-64 Assembly (NASM)

A fully functional Discord bot written entirely in x86-64 assembly using NASM for Windows. Connects to the Discord Gateway via WebSocket, handles heartbeats, receives events, and responds to commands - all in pure assembly calling Windows APIs directly.

## Features

- WebSocket connection to Discord Gateway (WSS)
- Automatic heartbeat to keep the connection alive
- Event dispatch for MESSAGE_CREATE
- Prefix-based command system (`!ping`, `!hello`, `!info`)
- REST API message sending
- Minimal JSON parser for Discord payloads
- Console logging for connection status

## Architecture

```
include/
  macros.inc        Stack frame and calling convention macros
  winapi.inc        Windows API extern declarations and constants
  discord.inc       Discord opcodes, intents, and API constants

src/
  bot.asm           Main entry point, init, command handlers (%includes everything)
  strings.asm       String utilities (strlen, strcmp, strcpy, strcat, itoa, etc.)
  json.asm          JSON key finder and value extractors
  http.asm          WinHTTP wrappers (session, connect, request, websocket)
  rest.asm          Discord REST API (send_message, get_gateway_url)
  heartbeat.asm     Heartbeat thread procedure and sequence tracking
  gateway.asm       Gateway WSS connect, identify, event loop, dispatch
  commands.asm      Command table, registration, prefix parsing, dispatch

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

- Single-bot, single-process design (global state, not thread-safe for multiple bots)
- JSON parser is targeted for Discord payloads, not a general-purpose parser
- Bot messages are ignored to prevent self-reply loops
- On reconnect/invalid session, the bot exits (a production bot would implement reconnection logic)
