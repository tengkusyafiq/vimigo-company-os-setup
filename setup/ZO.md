Please connect my Zo account to my Claude and ChatGPT (Codex) apps. Reply in one short, plain sentence at a time. I have never seen a key before, so tell me exactly where to click. If a step fails, fix it yourself; never tell me to ask anyone.

1. You must run commands on my own Windows or Mac computer. If you can't (Claude chat, Cowork or a cloud session), tell me to open the Claude app, click Code, start a new Local session (or open the Codex app) and paste this again. If you can run commands but this session is read-only, or blocks writing files or the internet, tell me to give you full access (in Claude Code, switch the mode at the bottom to Bypass permissions; in the Codex app, choose Full access), and carry on once I have.
2. Ask me: do I already have a Zo account? If not, open https://zo-computer.cello.so/0qDXmlEF6Hn for me and wait while I sign up.
3. I need a key from Zo. Open https://zo.computer for me and tell me, one step at a time: click Settings, then Advanced, scroll to Access Tokens, type any name, click Add, then Copy the long line that starts with zo_sk_. Ask me to paste it here. If what I paste does not start with zo_sk_, tell me what to look for.
4. Connect Zo with that key. Never print it back to me and never write it into my notes.
- Claude Code: claude mcp add --transport http --scope user zo https://api.zo.computer/mcp --header "Authorization: Bearer KEY"
- Claude app: in its claude_desktop_config.json, add an mcpServers entry named zo with command npx and args -y, mcp-remote@latest, https://api.zo.computer/mcp, --header, "Authorization: Bearer KEY". Keep everything else in the file.
- ChatGPT/Codex: in .codex/config.toml in my home folder, add a [mcp_servers.zo] section with the same command and args. Keep everything else in the file.
Do all three even if an app is not installed yet: create the file and its folder if they are missing. The Claude app file is claude_desktop_config.json inside the Claude folder in my AppData Roaming folder on Windows, or in ~/Library/Application Support/Claude on a Mac. Afterwards open each of the three places and check it really contains zo, then tell me which are connected. Never say one is connected without checking.
5. Tell me to quit and reopen Claude and ChatGPT so they pick it up (on a Mac, Command+Q).
6. When it is done, say only: "All done."
