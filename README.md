# Vimigo Company OS Setup

Sets up your computer to work with Zo, Claude and ChatGPT.

You do not need to know anything technical.

![How the Vimigo Company OS fits together: you reach Zo through your AI
Personal Assistant on WhatsApp, or through Claude and ChatGPT on your laptop.
Zo runs 24/7 in the cloud and holds your business data.](company-os.png)

**This release sets up the right-hand side** — Claude and ChatGPT on your
laptop, connected to your Zo and your business data. The WhatsApp assistant is
coming.

## Run it — one line

Nothing to download, unzip or drag anywhere. Copy the line for your computer,
paste it, press Enter. It fetches everything, puts the folder on your Desktop,
and starts.

### Mac

1. Press **Command + Space**, type `Terminal`, press **Enter**.
2. Paste this and press **Enter**:

```
curl -fsSL https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-mac.sh | bash
```

### Windows

1. Press the **Windows key**, type `PowerShell`, press **Enter**.
2. Paste this and press **Enter**:

```
irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-windows.ps1 | iex
```

Afterwards you can just double-click the launcher in that Desktop folder —
`Setup-Mac.command` or `Setup-Windows.bat`. The security warning does not come
back, because the one line clears it for you.

<details>
<summary>Prefer to download a zip instead?</summary>

You can:
**[Windows](https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/v1.0/vimigo-company-os-setup-windows-v1.0.zip)**
&nbsp;·&nbsp;
**[Mac](https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/v1.0/vimigo-company-os-setup-mac-v1.0.zip)**
— open it and copy the **whole folder** to your Desktop, then double-click the
launcher inside. Running it from inside the zip does not work.

On Windows you will get "Windows protected your PC": click **More info**, then
**Run anyway**. On a Mac you will hit a block that is genuinely hard to get
past — see below.

(If you land on the releases page, ignore the two "Source code" files. GitHub
adds those to everything; they are not what you want.)

</details>

<details>
<summary>If you downloaded the zip and your Mac is refusing to open it</summary>

You will have seen **"Apple could not verify Setup-Mac.command is free of
malware"**, offering only *Done* and *Move to Trash*.

**Click Done.** Do not click *Move to Trash* — it is the blue button and it
deletes the setup.

Then either run the one-line command above, which is easier, or:

1. Open **System Settings** → **Privacy & Security**, scroll to **Security**.
2. Find the line about `Setup-Mac.command` and click **Open Anyway**.
3. Give your fingerprint or password, then click **Open**.

If step 1 shows no such line, you have not tried to open it yet — the button
only appears after your Mac has blocked it once.

Older instructions said to right-click and choose **Open**. That stopped
working in macOS Sequoia; Apple removed it, which is why the warning now offers
no way forward at all.

</details>

## What happens

It checks what you already have, then sets up the rest for you.

Along the way it asks you to:

- paste your Zo account key
- click Allow on a few Google screens
- type your computer password once or twice

That is all. Everything else it does itself.

You already have Claude or ChatGPT? One is enough. The setup uses whichever you
have and does not push the other on you.

You can close it any time and run it again later. It carries on from where it
left off, and never does the same thing twice.

## If something goes wrong

Run it again. Most things sort themselves out on a second go.

If it happens twice, contact Vimigo support and tell them what the screen said.

## Getting an AI to help you through it

If you have Claude or ChatGPT open, you can ask it to walk you through this
instead of reading the steps yourself. Paste this to it:

> I am setting up Vimigo Company OS on my [Windows PC / Mac]. I am not
> technical. Read
> https://github.com/tengkusyafiq/vimigo-company-os-setup and walk me through
> it one step at a time. Ask me what I can see on my screen before telling me
> the next thing to do, and never give me commands to type unless there is no
> other way.

### If you are the AI reading this

Notes from the people who built it:

- **The owner is not technical.** Assume someone over 60 who has never opened a
  terminal. Never ask them to type a command, read a file path, or open a
  config file. They can click, tap a phone, sign in on a website, type a short
  code, and restart the computer. Nothing else.
- **Ask what is on their screen before you answer.** The setup shows a
  checklist and re-checks after every step, so what it says now is the truth.
  Your guess about where they are is not.
- **The Mac block is not a fault.** "Apple could not verify" is expected. Send
  them to System Settings → Privacy & Security → Open Anyway, and warn them off
  "Move to Trash". They must try to open it once first or the button is not
  there.
- **Pressing Enter does everything, in order.** There is no need to pick
  individual steps, and picking them out of order is how people end up with an
  assistant that has nothing behind it.
- **One AI app is enough.** If they have only ChatGPT or only Claude, that is a
  finished setup, not half of one.
- **It is safe to run again.** It never repeats work, it backs up any config it
  touches, and it verifies rather than trusting an installer. "Run it again" is
  a real fix for most things.
- **Do not invent troubleshooting.** If a step fails twice, the answer is
  Vimigo support with what the screen said — not a workaround you thought of.

## Licence

MIT
