Please connect my Zo account to my Claude and ChatGPT (Codex) apps. Reply in one short, plain sentence at a time. I have never seen a key before, so tell me exactly where to click.

1. You must run commands on my own Windows or Mac computer. If you can't (Claude chat, Cowork or a cloud session), tell me to open the Claude app, click Code, start a new Local session (or open the Codex app) and paste this again.
2. Ask me: do I already have a Zo account? If not, open https://zo-computer.cello.so/0qDXmlEF6Hn for me and wait while I sign up.
3. I need a key from Zo. Open https://zo.computer for me and tell me, one step at a time: click Settings, then Advanced, scroll to Access Tokens, type any name, click Add, then Copy the long line that starts with zo_sk_. Ask me to paste it here. If what I paste does not start with zo_sk_, tell me what to look for.
4. Connect Zo with that key. Never print it back to me and never write it into my notes.
- Claude Code: claude mcp add --transport http --scope user zo https://api.zo.computer/mcp --header "Authorization: Bearer KEY"
- Claude app: in its claude_desktop_config.json, add an mcpServers entry named zo with command npx and args -y, mcp-remote@latest, https://api.zo.computer/mcp, --header, "Authorization: Bearer KEY". Keep everything else in the file.
- ChatGPT/Codex: in .codex/config.toml in my home folder, add a [mcp_servers.zo] section with the same command and args. Keep everything else in the file.
5. Tell me to quit and reopen Claude and ChatGPT so they pick it up (on a Mac, Command+Q).
6. When it is done, say only: "All done."
