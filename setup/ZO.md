Before anything else — this applies to every file in this setup, not only
this one:

If you cannot run commands on this computer at all, stop and reply only:

> *"This needs to run in Claude Code or Codex, not here. In the Claude app,
> click **Code**. Or open the **Codex** app. Then paste the same message
> there."*

Then run one command to see which operating system your commands actually
run on — `uname -s` with a shell tool, or
`[System.Environment]::OSVersion.Platform` with PowerShell only:

    uname -s

If it says `Linux`, you are inside a sandbox (for example Claude Cowork), not
on their Windows or Mac computer. Stop and reply with the same sentence
above. Participants' computers are only Windows or macOS — never Linux.

---

# vimigo ai setup — Zo (session 2)

You are setting up a business owner's Zo account. Read "Who you are talking
to" in `MASTER.md` before you say anything to them. This file may be fetched
and read entirely on its own, with nothing else on the computer yet — so §0
through §4 below are `START.md`'s own §0 through §4, **verbatim**. Keep them
identical if either file changes; a laptop with no Node yet needs §1 exactly
as much here as it does there.

## 0. Put the setup on this computer

One command decides how this goes:

    node --version

**If it answers, let the shipped downloader do the work.** It reads
`files.json` — the list of everything this setup needs — and pulls the whole
tree down for you. Fetch that one file to
`<home>/.vimigo/setup/lib/fetch-setup.js` first:

    https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/lib/fetch-setup.js

then run it, and skip to step 1:

    node lib/fetch-setup.js

**If it does not answer**, Node is missing — step 1 installs it — so do this
part by hand. Fetch this:

    https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/files.json

It is an object with one key, **not a bare array**:

```json
{ "files": ["MASTER.md", "START.md", "lib/state.js", "steps/01-runtimes/README.md"] }
```

Read `files.json`'s `files` list. Fetch each entry from
`https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/<path>`
and write it to `<home>/.vimigo/setup/<path>`, keeping the folders.

**Use your own tools for this — the ones you use to read a web page and write a
file.** Do not shell out to `curl`, `wget`, or `Invoke-WebRequest`: on a real
machine `curl` was intercepted by a plugin and never reached the network, and
the improvised fallback that followed guessed the shape above wrong and crashed.

**Overwrite whatever is already there. Every file, every time.** A folder that
already exists means a previous run, and a previous run means older
instructions — quite possibly the ones with the fault somebody has since fixed.
Skipping a file because it is present is how a machine keeps running a version
nobody can reach.

**You never need git for this**, either way, and the by-hand path needs nothing
installed at all — which is the point of having one. Both git and Node may be
missing on this machine; installing them is row 1 of the checklist.

`<home>` is the owner's home folder: `%USERPROFILE%` on Windows,
`$HOME` on macOS. Everything below runs from `<home>/.vimigo/setup`.

Do not fetch anything under `optional/` yet. Those are fetched only if someone
asks for them, which is what keeps a risky one off a machine nobody asked.

## 1. Make sure Node is here

    node --version

If that fails, Node is not installed — and everything below is a Node program.
Read `steps/01-runtimes/README.md` and the platform file beside it, which you
have just downloaded, and install Node now.

That is row 1 of the checklist anyway, so you are not doing extra work, you are
doing it first. Come back here once `node --version` answers. Do not mark the
row done yet — the row needs Git and Python too, and it needs its check to have
run.

## 2. Check the manifest

    node lib/manifest.js

- `"action": "halt"` — stop. Say the `notice` to the owner in your own plain
  words and do nothing else. Do not explain what a manifest is.
- `"action": "refetch"` — do step 0 again, overwriting what is there, then
  carry on.
- `"action": "proceed"` — continue.
- `"offline": true` — continue anyway, and say nothing about it.

## 3. Read or create the state

Use the `version` that step 2 printed:

    node lib/state.js init --version <version from step 2>

This is the checklist, and it lives on disk in `state.json` because this
computer is going to restart before you are finished.

If it prints `"reason":"sandbox"` instead of a checklist, you are not on
their computer. Stop everything, and reply only with the sentence at the very
top of this file.

Recording the version is what lets a later session notice it is running old
instructions and fetch new ones by itself. Leave it out and this machine keeps
whatever it downloaded today, forever.

## 4. Install the master skill

Copy `MASTER.md` to **both**
`<home>/.claude/skills/vimigo-ai-setup/SKILL.md` and
`<home>/.agents/skills/vimigo-ai-setup/SKILL.md`, creating the folders. This is
what lets the owner come back after a restart by saying *"continue my vimigo ai
setup"* instead of pasting anything again, whichever app they open.

If `<home>/.codex/skills/vimigo-ai-setup/` exists, delete it. Codex reads both
`~/.agents/skills` and `~/.codex/skills` — a copy in both places shows up
twice in its skill list.

**Overwrite it if it is already there.** An installed copy is from a previous
run, and every later session reads that copy rather than this file — so a stale
one keeps its fault forever, and the owner has no way to know.

## 5. Finish session 1 first, if it was skipped

    node lib/session1.js

Never decide this from the sync row's own liveness check — that only proves
the last two-minute job ran recently, and reads a perfectly healthy but quiet
laptop (lunch break, bad wifi) as unfinished.

- **`"handoff": false`** — carry straight on to step 6.
- **`"handoff": true`** — `runtimes` or `second-brain` isn't done, or a
  Vimigo event is open right now and this laptop has never joined or said no
  to any event (for instance, session 1 couldn't reach Vimigo). Fetch the
  local `START.md` (§0 above already put it on this computer) and follow it
  from **§5 through §7**, completely and exactly as written — its own
  short-circuit, its "ask who they are" question, and its `sync` row
  included.

  **If `"joinedBefore": true`**, this laptop has already taken part in an
  event, and the hand-off is only for a red setup row: follow `START.md`'s
  §5 and §6, then its `runtimes` and `second-brain` rows only. Skip its
  `sync` row entirely — do not open `steps/03-sync`, do not mention
  saving to Vimigo, and never enrol it into the event open now.
  That is the case even when `START.md` §5's own check says an event
  is open.

A laptop that has already taken part in an event — joined one, or said no to
one — is never handed off for saving to Vimigo from here, whatever event is
open now: `"handoff"` stays `false` for that, and you say nothing about it.
The same when no event is open, or Vimigo can't be reached.

**Only `START.md`'s own text ever enrols a laptop.** This file hands off to
it rather than doing any of that itself. However it finishes — including its
own §5 short-circuit, which just means session 1 turns out to already be
done — come back here either way and carry on to step 6.

## 6. Connect Zo

Follow `steps/04-zo/README.md` completely, from the top. Do everything it
says, including the platform file beside it.

## 7. Show the checklist and finish

    node lib/state.js show

Then one sentence:

> *"Your Zo is connected. You can talk to it from here now."*

## Never

- **Never enrol by this file's own instructions.** The only file that ever
  enrols a laptop is `START.md`, through its `steps/03-sync` row, which is
  exactly why an unfinished session 1 is handed to it rather than repeated
  here.
