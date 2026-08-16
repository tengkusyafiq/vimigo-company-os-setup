# Step 3 on Windows

## Opening the sign-up page

    Start-Process "https://zo-computer.cello.so/0qDXmlEF6Hn"

Open it yourself. Do not print the address and ask them to type it, and do not
ask them where to find it — it is right there.

Tell them first, so a browser appearing is not a surprise:

> *"I'm opening the sign-up page for you now."*

## Opening the settings page, where the key is actually made

Signing up does not produce a key. Once they say they are signed in, open the
page where one gets made rather than describing how to navigate there:

    Start-Process "https://zo.computer"

Then Settings → Advanced → Access Key, per the five clicks in `README.md`.

If you have tools that can see and click the screen, do those five clicks
yourself instead of reading them out. They have signed in; the rest is clicking.

## Registering Zo with both apps

Claude Desktop and Claude Code do not share a configuration file. Write both, or
the owner gets Zo in one app and not the other and reasonably concludes it is
broken.

    %APPDATA%\Claude\claude_desktop_config.json     Claude Desktop
    %USERPROFILE%\.claude.json                      Claude Code

Parse the JSON, add or replace the one `mcpServers` entry, write it back. Never
overwrite the whole file — anything else in there belongs to the owner.

ChatGPT Desktop carries Codex, which reads TOML:

    %USERPROFILE%\.codex\config.toml

## After writing

Both apps read their server list once, at startup. Say so before quitting
anything:

> *"I'm going to close Claude and reopen it so it picks this up. When it's back,
> say hi and I'll carry on."*
