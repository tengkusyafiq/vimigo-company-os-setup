---
name: vimigo-ai-setup
description: Set up, resume, or repair a business owner's vimigo AI installation — Node, Git and Python, the /compile-data command, and their Zo account with their own Claude and ChatGPT subscriptions. Use when someone asks to continue their vimigo ai setup, when a setup was interrupted by a restart, or when a row of their setup checklist is not finished.
---

# vimigo ai setup

## Where everything is

The setup lives in `<home>/.vimigo/setup` — `%USERPROFILE%\.vimigo\setup` on
Windows, `$HOME/.vimigo/setup` on macOS. Every command in this file is written
relative to that folder, so work from there.

If that folder is not there, this setup was never downloaded. Fetch
`https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/START.md`
and follow it from the top instead of guessing.

## Before anything else

    node lib/state.js json

That `state.json` file is the truth about this machine. You did not do the rows
it says are done, and you must not redo them.

## Who you are talking to

A business owner who has never opened a terminal. They do not know what a file,
a path, a command, a port or a log is, and they will not say so.

- Never show them a path, a command, a log line, an error, a version number they
  did not ask for, a port, or a key.
- One plain sentence per step, then go quiet.
- The only things you may ask of them: something on their phone, clicking a
  button you warned them about, and pasting their Zo key.
- **When something fails, you fix it.** Never tell them to contact anybody.
  If you genuinely cannot, say what it means for them in plain words and move on
  to the next row.

## The order

Rows run in order, and the required ones gate the optional ones. Nothing below
`zo` may be attempted until `zo` is green.

| Row | Step folder | Required |
|---|---|---|
| `runtimes` | `steps/01-runtimes/` | yes |
| `compile-data` | `steps/02-compile-data/` | yes |
| `zo` | `steps/03-zo/` | yes |
| `whatsapp` | `optional/whatsapp/` | only when asked |
| `hcs-fix` | **not built yet** | — |
| `hermes` | **not built yet** | — |

`hcs-fix` and `hermes` have no instructions in this tree yet. If someone asks
for either, **do not improvise one.** Say it is not ready yet, leave the row
alone, and carry on with the rest:

> *"That part isn't ready for me to set up yet — I'll leave it for now."*

This matters most for the Cowork fix. Making that work means changing how the
computer starts, it has already left one machine unable to boot, and the
instructions that say how to do it safely are not written. An AI improvising
inside the guardrails further down this file is still an AI improvising a boot
configuration change.

## Check before you do anything — every row, every time

**Run the row's `verify.js` first.** Not after. Machines arrive with things
already on them: Node because they write code, the setup half-finished from
yesterday, a Zo key pasted an hour ago before the laptop restarted.

For each row, in this order:

1. Run `steps/<row>/verify.js`.
2. **If it passes, mark the row done with the evidence it returned and move on.
   Change nothing.** It already works. Installing over it wastes their time and
   occasionally breaks the thing that was fine.
3. Only if it fails: read the step's `README.md`, then `windows.md` or
   `macos.md`, do the work, run `verify.js` again, and mark the row.

The rows the owner has to help with are the expensive ones to repeat. Asking
somebody to paste a key they already pasted, or to link a phone that is already
linked, is how a setup stops feeling like it knows what it is doing.

Say nothing about the ones that were already fine. Show the checklist; the
ticks say it.

## Marking a row

    node lib/state.js set <id> done --evidence "<the evidence string from verify.js>"

**Never write your own evidence.** If `verify.js` did not say ok, the row is not
done, however certain you feel. This is the single rule that stops this setup
from confidently breaking somebody's computer.

Show the checklist after every row:

    node lib/state.js show

## Long operations

**Never run an install in the foreground.** A blocked command cannot say
anything, and silence is what makes an owner think it has crashed. Run it in the
background, poll it, and say something roughly once a minute — elapsed time and
a range, never a countdown:

> *"Still installing — about two minutes in. These usually take three to five."*

Past twice the range, say so rather than going quiet:

> *"This is slower than usual. Want me to keep waiting, or try a different way?"*

## Restarts

Say what will happen before it happens, and tell them how to come back.

Claude:

> *"I'm going to close this and reopen it. When it's back, say hi and I'll pick
> up where we are."*

The computer:

> *"Restart your computer whenever you're ready. When it's back, open Claude
> Code and say: continue my vimigo ai setup."*

Both work because the checklist is on disk. Read it first thing when you return.

## When a row cannot be finished

Try, then stop. Do not spend twenty minutes on one row.

    node lib/state.js block <id> --reason "<plain words, no jargon>"

Then **move to the next row** — a stuck row must never block an unrelated one.
At the end, say what is outstanding and what it means for them:

> *"Everything's set up except WhatsApp — this laptop won't let programs start
> themselves automatically, so it'd stop working every time you shut down.
> Better to leave it off than have it break on you."*

## Anything that changes how the computer starts

Boot configuration, disk encryption, and system-wide services are different from
everything else here, because getting them wrong can leave a machine that will
not start. Before any of it:

1. Try the reversible thing first. A stopped service that needs starting is
   reversible; enabling a boot feature is not.
2. Refuse outright on a conflict — another hypervisor installed, virtualization
   disabled in firmware, or disk encryption you cannot suspend.
3. Take a restore point.
4. Ask, in plain words: *"This changes how your computer starts up. It's the
   only way to make that work — is it okay if I do it?"*
5. Know the way back before you start, and walk them through it yourself if it
   goes wrong.

Everything else in this setup stays inside the owner's own home folder and needs
no password and no administrator. Keep it that way.

## Finishing

    node lib/state.js show

Then one or two sentences. Not the list.

> *"You're all set up. Your AI can reach your Zo now."*
