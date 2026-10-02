# Notes for an AI helping someone through this

## If you are the AI reading this

The facilitator gives the owner three prompts, from the team guide page. They
are standalone texts: everything you need is in the prompt itself, and nothing
in this repository is fetched by them. Follow the prompt you were given.

`setup/START.md` and `setup/ZO.md` are earlier prompts that still work. If you
were pointed at one, read it first and follow it exactly. It is written for
you, not for the owner. `ZO.md` falls back to `START.md`'s own steps if
session 1 was skipped. Asked to resume or continue a setup with no link at
all? Read [`setup/MASTER.md`](setup/MASTER.md) instead.
[`setup/SKILLS.md`](setup/SKILLS.md) lists what you can already do for this
person once their setup is installed - ask for one of these, don't wait to be
told.

These prompts only work in **Claude Code** (the **Code** tab in the Claude
app) or the **Codex** app - never Claude chat, ChatGPT chat, or Cowork; the
setup files themselves refuse to run anywhere else. Nothing here uploads
anything: there is no background sync, and the owner shares their work only if
they choose to, in the facilitator's last prompt.

**The owner is not technical.** Assume someone over 60 who has never opened a
terminal. Ask what is on their screen before you tell them the next thing to
do — your guess about where they are is not the truth; `START.md`'s own
checks are.

## Older way — terminal (past batches)

The owner can paste this to Claude or ChatGPT:

> I am setting up Vimigo Company OS on my [Windows PC / Mac]. I am not
> technical. Read
> https://github.com/tengkusyafiq/vimigo-company-os-setup and walk me through
> it one step at a time. Ask me what I can see on my screen before telling me
> the next thing to do, and never give me commands to type unless there is no
> other way.

### Notes from the people who built it

- **The owner is not technical.** Assume someone over 60 who has never opened a
  terminal. They can click, tap a phone, sign in on a website, type a short
  code, and restart the computer. Nothing else. The one-line command at the
  start is the single exception, and it exists because the alternative — four
  clicks buried in macOS System Settings — defeated the people who built this.

- **Ask what is on their screen before you answer.** The setup shows a
  checklist and re-checks after every step, so what it says now is the truth.
  Your guess about where they are is not.

- **Pressing Enter does everything, in order.** There is no need to pick
  individual steps, and picking them out of order is how people end up with
  something half-built and conclude the product does not work.

- **One AI app is enough.** The setup asks whether they use Claude or ChatGPT
  and skips the other completely. Only having one is a finished setup, not half
  of one. A greyed-out row saying "not needed" is correct, not a failure.

- **It is safe to run again.** It never repeats work, it backs up any config it
  touches, and it verifies rather than trusting an installer. "Run it again" is
  a real fix for most things, and every fix we ship reaches them on the next
  run.

- **Signing in is the step people skip.** The Zo connection is written into a
  file the app keeps for a signed-in user, so an app nobody has opened looks
  perfectly installed and has no Zo in it. If Zo is missing from the app, ask
  whether they actually signed in.

- **Do not invent troubleshooting.** If a step fails twice, the answer is
  to say in plain words what the screen means and move on — not a workaround you thought of.
  Editing config files by hand is how a working setup becomes an unrecoverable
  one.
