# Step 3 on macOS

## Opening the sign-up page

    open "https://zo-computer.cello.so/0qDXmlEF6Hn"

Open it yourself. Do not print the address and ask them to type it, and do not
ask them where to find it — it is right there.

Tell them first, so a browser appearing is not a surprise:

> *"I'm opening the sign-up page for you now."*

## Opening the settings page, where the key is actually made

Signing up does not produce a key. Once they say they are signed in, open the
page where one gets made rather than describing how to navigate there:

    open "https://zo.computer"

Then Settings → Advanced → Access Key, per the five clicks in `README.md`.

If you have tools that can see and click the screen, do those five clicks
yourself instead of reading them out. They have signed in; the rest is clicking.

## Registering Zo with both apps

Claude Desktop and Claude Code do not share a configuration file. Write both.

    ~/Library/Application Support/Claude/claude_desktop_config.json
    ~/.claude.json

Parse the JSON, add or replace the one `mcpServers` entry, write it back. Never
overwrite the whole file.

ChatGPT Desktop carries Codex, which reads TOML:

    ~/.codex/config.toml

## After writing

Closing a window is not quitting on a Mac. Say which one you mean:

> *"I'm going to quit Claude properly — Command+Q, not just closing the window —
> and reopen it. When it's back, say hi and I'll carry on."*
