# AI Personal Assistant

A WhatsApp or Telegram number you can message from your phone, answered by your
Zo. Ask it something at 11pm from the car park and it answers.

**Finish the [main setup](README.md) first.** This checks, and stops if you
have not — everything here needs your Zo key and a Zo that is already
answering.

## Mac

1. Hold **Command** and press **Space**.
2. Type `Terminal` and press **Enter**.
3. Copy the line below, paste it, and press **Enter**.

```
curl -fsSL https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-assistant-mac.sh | bash
```

## Windows

1. Click **Start**.
2. Type `PowerShell` and press **Enter**.
3. Copy the line below, paste it, and press **Enter**.

```
irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-assistant-windows.ps1 | iex
```

## What it asks you

Which way you want to reach it:

- **WhatsApp** — needs a **spare number**, not the one you use every day. The
  assistant answers *as* that number, so linking your own leaves nobody for you
  to message.
- **Telegram** — free, and takes about two minutes on your phone.
- **On the web** — nothing to set up.

Then it links it, and tells you when it is answering.

Run the same line again any time to change your mind.
