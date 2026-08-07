# Notes for an AI helping someone through this

The owner can paste this to Claude or ChatGPT:

> I am setting up Vimigo Company OS on my [Windows PC / Mac]. I am not
> technical. Read
> https://github.com/tengkusyafiq/vimigo-company-os-setup and walk me through
> it one step at a time. Ask me what I can see on my screen before telling me
> the next thing to do, and never give me commands to type unless there is no
> other way.

## If you are the AI reading this

Notes from the people who built it.

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

- **There are only three things they must do themselves:** choose Claude or
  ChatGPT, sign in to that app and leave it open, and paste their Zo key. If
  they are doing anything else by hand, something has gone wrong.

- **Signing in is the step people skip.** The Zo connection is written into a
  file the app keeps for a signed-in user, so an app nobody has opened looks
  perfectly installed and has no Zo in it. If Zo is missing from the app, ask
  whether they actually signed in.

- **Do not invent troubleshooting.** If a step fails twice, the answer is
  Vimigo support with what the screen said — not a workaround you thought of.
  Editing config files by hand is how a working setup becomes an unrecoverable
  one.
