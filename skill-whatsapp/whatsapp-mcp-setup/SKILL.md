---
name: whatsapp-mcp-setup
description: Install, connect, or repair the owner's WhatsApp connection for Claude Code, Codex, or Claude Desktop. Use when someone wants to connect WhatsApp to their AI, says their WhatsApp stopped working, cannot see WhatsApp tools, or needs to link their number again.
---

# Connecting WhatsApp

## The one rule

The person you are helping is a business owner. They have never opened a
terminal. **Never ask them to run a command, open a file, read a path, or
explain an error.** The only thing you may ask them to do is something on their
own phone.

You run everything. They watch.

## Installing

Run this yourself, in one go. Do not explain it, do not modify it, and do not
substitute your own commands.

**Windows — in PowerShell.** `irm` and `iex` are PowerShell's own words for
this and exist nowhere else: in Command Prompt, in bash, or in Git Bash the
line comes straight back as "command not found".

```
irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-whatsapp-windows.ps1 | iex
```

Not ready for Mac yet. Ask Vimigo, and we will send you the line as soon as it is.

A page opens in their browser with a square to scan. Tell them:

> *"Open WhatsApp on your phone. On an iPhone, tap Settings. On Android, tap
> the three dots at the top right. Then tap Linked Devices, then Link a Device,
> and point your phone at your screen."*

Nothing else. **Ask which phone they have if you do not know** — Linked Devices
is not in Settings on Android, and an owner sent to the wrong menu will scroll
past Account, Privacy, Chats and Notifications, find nothing, and stop. This is
the only action the whole design asks of them.

If they cannot scan it — a cracked screen, a camera that will not focus — the
setup asks for their WhatsApp number in the window it is already running in,
and shows a code to type on the phone instead. Let it ask. Do not ask for the
number yourself, and never type it for them.

## When something is wrong

The setup exposes four verbs. **You may use these and nothing else.** Do not
invent commands, inspect files, read logs, or edit configuration by hand.

| Verb | Windows | Mac |
|---|---|---|
| Check | `-Doctor` | `--doctor` |
| Repair | `-Fix` | `--fix` |
| Link again | `-Reconnect` | `--reconnect` |
| Start over | `-Reinstall` | `--reinstall` |

Run one exactly like this, with the verb from the table on the end. Every part
of these lines is load-bearing; copy them as they are written.

**On Windows, in PowerShell** — not Command Prompt, not bash:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Vimigo\whatsapp\vimigo-whatsapp.ps1" -Doctor
```

If the only shell you have on Windows is bash, that same line works there with
`$LOCALAPPDATA` in place of `$env:LOCALAPPDATA`, and nothing else changed.

`-ExecutionPolicy Bypass` is what makes the line work at all. Home and personal
Windows machines ship set to refuse to run scripts, and without it every verb
comes back as a security refusal carrying a file path and a web link, and no
code for you to read. It applies to that one command, alters nothing on the
machine, and needs no administrator prompt. Never reach for `Set-ExecutionPolicy`
instead — the form an AI usually reaches for changes the whole machine and
demands an administrator prompt. Nothing here needs one, and asking a business
owner to approve one is out of the question.

**On a Mac, in Terminal** — bash or zsh, either is fine:

```
bash "$HOME/Library/Application Support/Vimigo/whatsapp/vimigo-whatsapp.sh" --doctor
```

Keep the quotes on both lines. The Mac path has spaces in it, and so does the
Windows one for an owner whose account is named after two words.

Never put `sudo` in front of either line, and never run either one as an
administrator.

**Check prints exactly two lines**, the same on both platforms:

```
Your WhatsApp is connected.
OK
```

The **first line** is for the owner. It is already written for them; say it
word for word and add nothing.
The **second line** is a code, and it is for you. **Never show it to them, and
never say it out loud.** It means nothing to them and there is nothing they can
do with it.

Either line may arrive with a couple of spaces in front of it. Strip the spaces
off both ends of both lines before you do anything with them: the spaces are
not part of the sentence you say, and `OK` with two spaces in front of it is
still `OK`. Match every code in this page that way.

### How long these take, and what to do about it

Check answers in seconds. **Repair, Link again and Start over do not.**

Repair is not a few minutes. It works through up to three rounds with a budget
of ten minutes, and a round that finds the phone unlinked stops inside a
pairing wait for a further ten minutes on top — because what it is waiting for
is a 60-year-old finding Linked Devices on an Android phone for the first time,
which was measured, not guessed. **Worst case is about twenty minutes in a
single call.** Link again and Start over can run just as long, for the same
reason.

So, before you run any of the three:

- **Raise your tool's timeout to at least twenty-five minutes** — 1500 seconds,
  or 1500000 milliseconds, whichever unit it takes. Shell tools commonly
  default to two minutes, which would kill a repair roughly ten times over.
- **If your tool will not go that high, run it in the background** and wait for
  it to finish on its own. Do not run it in the foreground and let the tool cut
  it off.
- **Never kill it, and never run a second verb while one is running.** Killing
  Repair mid-pairing is the worst thing you can do here: it stops a phone link
  that was seconds from working, and it can stop it three times in a row.
- Long silences are normal and are not a hang. It prints one plain sentence per
  step and then goes quiet, sometimes for many minutes.
- If your tool does cut one off, do **not** immediately run it again. Run
  **Check**, and start from step 3.

**Follow this exactly:**

1. Run **Check**.
2. If Check did not print two lines — an error instead, a complaint that the
   file does not exist, or nothing at all — then WhatsApp is not installed on
   this computer, and none of the other three verbs exist here either. Go back
   to **Installing** above and run the one line for their platform. This is not
   a support case, and they must never see what the error said. (A machine that
   *is* installed always gets two lines out of Check, even when the check
   itself goes wrong: the code is then `WA-00`, and that goes down the ladder
   like any other.)
3. If the second line is `OK`, say the first line and stop. Nothing is wrong.
4. If the second line is `WA-11`, nothing is wrong either: their WhatsApp is
   connected and still copying recent conversations across. Say the first
   line and wait. Do not run Repair.
5. If the second line starts with `P-`, the rest is on their phone and nothing
   is broken. Say the first line **before** you run anything, so they know to
   look at their phone — then run **Repair**, which is what puts the square on
   screen and waits for them. Then run **Check**. If it is still `P-`, say the
   first line again and leave it there: do not go round again, and do not send
   them to support. They have not scanned yet, which is not a fault. When they
   tell you they are ready, use **Link again**.
6. Otherwise, run **Repair**, with your timeout already raised as above. It
   prints a sentence as it goes and then goes quiet — do not interrupt it, and
   do not run anything else while it is running.
7. Run **Check** again and go back to step 3. Three rounds, at most.
8. If three rounds have not moved a `WA-` code, run **Start over** once, then
   run **Check** once more.
9. If it still is not `OK`, say: *"I could not fix this one. Please contact
   Vimigo support."* Do not diagnose further.

### When to use Link again

Repair already puts the square on screen by itself whenever Check says `P-`,
and waits ten minutes for someone to scan it. **Link again** is for after that
window has closed, when nothing else will bring the square back:

- they walked away, or closed the page, and now say they are ready;
- they removed this computer from Linked Devices on the phone themselves;
- they have a new phone, or want a different WhatsApp number on this computer.

It only re-links. It downloads nothing, replaces nothing, and never touches
their message history. Like Repair it can sit there for twenty minutes, because
what it is waiting for is a person finding a menu on a phone. Raise your
timeout the same way.

Run **Check** first, always — never reach for this as an opening move — and
never run it while the code is `WA-11`.

### When to use Start over

**Start over** is step 8, and step 8 only: three rounds of Repair have not
moved a `WA-` code. It puts the pieces back from nothing — fetches a fresh
copy, rewrites the settings, registers everything again — while deliberately
keeping their message history and their link to their phone, so it costs them
nothing except the download.

Never run it on a `P-` code or on `WA-11`. Neither of those is a fault, and
starting over will not help either one. Run it once, never twice.

## What never to do

- Never tell them to install Go, Git, a compiler, or a package manager. Nothing
  here needs any of them.
- Never delete their message history to fix a problem. It holds the link to
  their phone, and deleting it means starting over.
- Never print a file path, a command, or an error message to them.
- Never send a WhatsApp message without showing the exact words first and
  waiting for a yes.
