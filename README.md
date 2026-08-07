# Vimigo Company OS Setup

Connects Claude or ChatGPT on your computer to your Zo.

You do not need to know anything technical. One line, once.

## Mac

1. Hold **Command** and press **Space**.
2. Type `Terminal` and press **Enter**.
3. Copy the line below, paste it, and press **Enter**.

```
curl -fsSL https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-mac.sh | bash
```

## Windows

1. Click **Start**.
2. Type `PowerShell` and press **Enter**.
3. Copy the line below, paste it, and press **Enter**.

```
irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-windows.ps1 | iex
```

## That is it

The setup opens and tells you what it is doing. It will ask you to sign in to
Claude or ChatGPT, and to paste your Zo key. Everything else it does itself.

If it stops, run the same line again — it carries on from where it got to.

If it stops twice, contact Vimigo support and tell them what the screen said.

---

Helping someone through this using Claude or ChatGPT? Read
[AGENT-NOTES.md](AGENT-NOTES.md).

MIT licence.
