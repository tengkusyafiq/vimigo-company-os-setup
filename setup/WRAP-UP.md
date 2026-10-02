Before anything else — this applies to every file in this setup, not only
this one:

If you cannot run commands on this computer at all, stop and reply only:

> *"This needs to run on your own computer, not here. In the Claude app,
> click **Code**, start a **new session** and choose **Local** — not cloud,
> not Cowork. Or open the **Codex** app. Then paste the same message there."*

Then run one command to see which operating system your commands actually
run on — `uname -s` with a shell tool, or
`[System.Environment]::OSVersion.Platform` with PowerShell only:

    uname -s

If it says `Linux`, you are inside a sandbox — Claude Cowork, or a cloud
session (even one linked to their computer) — not on their Windows or Mac
computer. Stop and reply with only the same sentence above: no explanation of
sandboxes, no options, nothing else. Participants' computers are only Windows or macOS — never Linux.

---

# vimigo ai setup — wrap-up (last session)

## Keep every reply short and simple

The owner is sitting in a busy room, and a long message overwhelms them and gets
misunderstood. So, for the whole session:

- Each message is **one or two short, plain sentences** — never a paragraph, a
  bullet list or a summary. The checklist, when you show it, is the only longer
  thing you may print.
- **Do not explain what the setup does, how it works, what it installs, what is
  copied, where files are, or what happens next.** The class already explained it
  in the room. Answer such a question only if the owner asks it, in one sentence.
- Do not mention folders, versions, scripts, settings, tests or anything
  technical, and do not describe what you checked or read.
- Your last message is **only** the closing line this file gives you — nothing
  before it, nothing after it.

This is the last-day wrap-up of Vimigo's in-person AI class. On the stage, Shane
asked who wants to share their Second Brain for consultation. **The owner who
pasted this said yes — they chose it, and the message they pasted says exactly
what is shared.** You do not need to ask again, and you must not talk them out of
it or explain it at length.

What happens, in this order: make sure the setup is on this computer, write their
AI Workflow Submission into their Second Brain, then share their Second Brain to
Shane for consultation — once, now. Nothing is shared before this, nothing runs
in the background, and their conversations and other files are never sent. This
session never sets up Zo. Never tell the owner to contact anybody: you fix things
yourself.

**First, check whether this computer is already set up.** With your own
file-reading tool (not a shell command), look for the folder
`<home>/.vimigo/setup/lib` (`<home>` is `%USERPROFILE%` on Windows, `$HOME` on
macOS).

- **If it is there with files in it**, the basic setup already ran on this
  computer. Do **not** run §0–§4 below — nothing needs downloading or
  re-installing, and re-downloading only trips the computer's permission prompt
  for no reason. Go straight to **§5**.
- **If it is missing**, §0–§4 below are `START.md`'s own §0–§4, **verbatim** —
  do them to set the computer up, then carry on from §5.

Everything from §0 to §4 is only for that second case.

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

## 5. Make sure the basics are done

    node lib/session1.js

- **`"handoff": false`** — say nothing about this, and go to step 6.
- **`"handoff": true`** — `runtimes` or `second-brain` isn't done. Fetch the
  local `START.md` and follow it from **§5 through §7**, then come back here.
  (Its name question gives you their name, company and role.)

## 6. Tell them, once

Say this one line, then go quiet and work through steps 7 and 8:

> *"Give me a few minutes — I'm writing up what you built this week."*

## 7. Write their AI Workflow Submission

Read `steps/05-submission/README.md`, and the `windows.md` or `macos.md` beside
it, and follow it completely: the submission document in their Second Brain, then
the files that show their work.

Keep to about **10 minutes** for this step. If it runs long, stop and go to
step 8 anyway — the share takes whatever is written by then. That README's one
question about Google files is the only thing this step may ask them; time spent
waiting for their answer does not count toward the 10 minutes.

## 8. Share it, once

Take their name, company and role from `Second Brain/About me.md` (exactly as
written there). Then:

    node lib/enrol.js --resume --name "<name>" --company "<company>" --role "<role>"

It answers with `"ok"`:

- `"ok": true` — go on to the send below.
- `"reason": "not-open"` — sharing is not open. Say only:
  *"Sharing isn't open right now. Your Second Brain stays on your computer."*
  and stop.
- `"reason": "offline"` or `"reason": "refused"` — run the same command once
  more. If it still fails, say only:
  *"This computer couldn't connect just now. Please paste the same message again in a few minutes."*
  and stop.
- Anything else — say only the same sentence as above, and stop.

Then send:

    node "<home>/.vimigo/setup/lib/sync.js" --final --finish

`<home>` is `%USERPROFILE%` on Windows, `$HOME` on a Mac.

It answers with one `"outcome"`. Choose the line from `"outcome"` alone — never
from `"ok"` or `"reason"` — and say only that line.

If the command stops without printing an answer — it timed out, or was stopped —
treat that exactly as `"outcome": "busy-retry"` below. Never guess another
outcome, and never run anything else instead.

- `"outcome": "sent"` → *"All done. Your Second Brain is shared with Shane for consultation, and it stays on your computer too."*
- `"outcome": "busy-retry"` → the server is busy or there is more to send than
  fits in one run (each run stops itself after a few seconds, and the next
  carries on). Say nothing; run the same command again, up to thirty more times.
  If it is still `"busy-retry"` after that, say:
  *"It's busy right now. Please paste the same message again in a few minutes."*
  If a try gives another outcome, say that outcome's line instead.
- `"outcome": "offline"` or `"outcome": "nothing-sent"` → run the same command
  up to three more times first; it is usually the wifi. If it is still the same,
  say: *"This computer couldn't connect just now. Please paste the same message again once you're online."*
  If a try gives another outcome, say that outcome's line instead.
- `"outcome": "closed"` → *"Sharing is closed now. Your Second Brain stays on your computer."*
- `"outcome": "not-enrolled"` or `"outcome": "declined"` → run the enrol command
  above once more, then the send again. If it is the same, say the offline line
  above.

That line is the end. Nothing else changes. Their Second Brain, their skills and
their Zo stay exactly as they are.

## Never

- **Never offer Zo here, or start it.**
- **Never send, list or read their conversations, chats or anything outside the
  Second Brain folder.** The only thing that leaves this computer is the Second
  Brain, by the two commands above.
- **Never run `sync.js` or `enrol.js` unless this wrap-up is what you are doing.**
