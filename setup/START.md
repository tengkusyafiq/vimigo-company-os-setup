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

Fetch this:

    https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/files.json

It lists every file this setup needs. Fetch each one from
`https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/<path>`
and write it to `<home>/.vimigo/setup/<path>`, keeping the folders.

Use whatever you normally use to fetch a file and write it. **You do not need
git for this, and you do not need Node yet** — both may be missing, and one of
them is the first thing on the checklist.

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

    node lib/state.js init

This is the checklist, and it lives on disk in `state.json` because this
computer is going to restart before you are finished.

## 4. Install the master skill

Copy `MASTER.md` to `<home>/.claude/skills/vimigo-ai-setup/SKILL.md`, creating
the folders. This is what lets the owner come back after a restart by saying
*"continue my vimigo ai setup"* instead of pasting anything again.

## 5. Show the checklist and begin

    node lib/state.js show

Then say:

> *"Right — I can see what your computer needs. I'll work through it and tell
> you whenever I need you for anything. It'll take a little while."*

Then follow `MASTER.md`.
