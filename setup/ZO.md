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

# vimigo ai setup — Zo (session 2)

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

You are setting up a business owner's Zo account. Everything stays on this
computer and in their own Zo account — nothing is sent to anyone else. Never tell
the owner to contact anybody: you fix things yourself. Read "Who you are talking
to" in `MASTER.md` before you say anything to them.

**First, check whether this computer is already set up.** With your own
file-reading tool (not a shell command), look for the folder
`<home>/.vimigo/setup/lib` (`<home>` is `%USERPROFILE%` on Windows, `$HOME` on
macOS).

- **If it is there with files in it**, the basic setup already ran on this computer.
  Do **not** run §0–§5 below — nothing needs downloading or re-installing, and
  re-downloading only trips the computer's permission prompt for no reason. Go
  straight to **§6 (Connect Zo)** and continue from there.
- **If it is missing**, the basic setup has not been done here. Then §0–§4 below are
  `START.md`'s own §0–§4, **verbatim** — do them to set the computer up, then
  §5, then §6.

Everything from §0 to §5 is only for that second case.

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

- **`"handoff": false`** — carry straight on to step 6.
- **`"handoff": true`** — `runtimes` or `second-brain` isn't done. Fetch the
  local `START.md` (§0 above already put it on this computer) and follow it
  from **§5 through §7**, then come back here and carry on to step 6.

## 6. Connect Zo

First mark the row started, so it appears on their checklist:

    node lib/state.js set zo doing

Then follow `steps/04-zo/README.md` completely, from the top. Do everything it
says, including the platform file beside it.

## 7. Show the checklist and finish

    node lib/state.js show

Then one sentence:

> *"All done."*

Say nothing more: do not explain what was connected or how to use it.
