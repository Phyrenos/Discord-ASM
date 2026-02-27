; ping_bot.asm - Example Discord bot with !ping and !hello commands
;
; This is a standalone example that demonstrates how to use the bot library.
; Since the library uses %include for single-object compilation, this file
; IS the bot - just build src/bot.asm which has everything built in.
;
; To add custom commands, see the register_builtin_commands function in
; src/bot.asm and follow the same pattern:
;
;   1. Define a command name string:
;      cmd_name_mycommand: db "mycommand", 0
;
;   2. Write a handler function:
;      cmd_handler_mycommand:
;          ; rcx = channel_id (string)
;          ; rdx = args after command (string, may be empty)
;          ; r8  = author username (string)
;          push rbp
;          mov rbp, rsp
;          sub rsp, 64
;          mov [rbp-8], rcx       ; save channel_id
;          ; ... build your response ...
;          lea rcx, [bot_token]
;          mov rdx, [rbp-8]       ; channel_id
;          lea r8, [my_response]  ; your response string
;          call rest_send_message
;          mov rsp, rbp
;          pop rbp
;          ret
;
;   3. Register it in register_builtin_commands:
;      lea rcx, [cmd_name_mycommand]
;      lea rdx, [cmd_handler_mycommand]
;      call register_command
;
; === Usage ===
;
;   set DISCORD_TOKEN=your_bot_token_here
;   build.bat
;   build\bot.exe
;
; The bot will connect to Discord and respond to:
;   !ping  -> "Pong!"
;   !hello -> "Hello, <your_username>!"
;   !info  -> "I am a Discord bot written in pure x86-64 assembly (NASM)!"
;
; === Required Bot Permissions ===
;   - Send Messages
;   - Read Message Content (privileged intent - enable in Discord Developer Portal)
;
; === Discord Developer Portal Setup ===
;   1. Create application at https://discord.com/developers/applications
;   2. Go to Bot section, create bot
;   3. Enable MESSAGE CONTENT INTENT under Privileged Gateway Intents
;   4. Copy the bot token
;   5. Generate invite URL with bot scope + Send Messages permission
;   6. Invite to your server
