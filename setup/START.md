# vimigo ai setup — start here

You are setting up a business owner's computer. They have never opened a
terminal. Read "Who you are talking to" in `MASTER.md` before you say anything
to them.

**You have read this one file over the web. Nothing else is on this computer
yet.** Step 0 is what puts it there. Do not skip it and do not run any command
below before it — none of those files exist until you fetch them.

Say this first, then go quiet and work:

> *"Right — give me a moment to get set up, then I'll walk you through it."*

## 0. Put the setup on this computer

One command decides how this goes:

    node --version

**If it answers, let the shipped downloader do the work.** It reads
`files.json` — the list of everything this setup needs — and pulls the whole
tree down for you. Fetch that one file to
`<home>/.vimigo/setup/lib/fetch-setup.js` first:

    https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/lib/fetch-setup.js

then run it, and skip to step 1:

    node lib/fetch-setup.js https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/

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

    node lib/manifest.js https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/manifest.json

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

Recording the version is what lets a later session notice it is running old
instructions and fetch new ones by itself. Leave it out and this machine keeps
whatever it downloaded today, forever.

## 4. Install the master skill

Copy `MASTER.md` to `<home>/.claude/skills/vimigo-ai-setup/SKILL.md`, creating
the folders. This is what lets the owner come back after a restart by saying
*"continue my vimigo ai setup"* instead of pasting anything again.

**Overwrite it if it is already there.** An installed copy is from a previous
run, and every later session reads that copy rather than this file — so a stale
one keeps its fault forever, and the owner has no way to know.

## 5. Find out what is already working

Before you change anything, run all three checks and mark whatever already
passes:

    node steps/01-runtimes/verify.js
    node steps/02-compile-data/verify.js
    node steps/03-zo/verify.js <key, only if you already have one>

Mark every row that came back ok, using the evidence it returned. A machine
that arrives with Node already on it, or half-finished from yesterday, should
show that on the first screen — not get it reinstalled.

## 6. Show the checklist and begin

    node lib/state.js show

If everything is already ticked, say so and stop. Do not go looking for work:

> *"Good news — this is all set up already. Nothing for me to do."*

Otherwise:

> *"Right — I can see what your computer needs. I'll work through it and tell
> you whenever I need you for anything. It'll take a little while."*

Then follow `MASTER.md`.
