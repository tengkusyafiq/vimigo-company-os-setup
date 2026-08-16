# vimigo ai setup — start here

You are setting up a business owner's computer. They have never opened a
terminal. Read "Who you are talking to" in `MASTER.md` before you say anything
to them.

Do these four things in order, then hand over to the master skill.

## 1. Check the manifest

    node lib/manifest.js https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/manifest.json

- `"action": "halt"` — stop. Say the `notice` to the owner in your own plain
  words and do nothing else. Do not explain what a manifest is.
- `"action": "refetch"` — re-fetch every file under `setup/` before continuing.
- `"action": "proceed"` — continue.
- `"offline": true` — continue anyway, and say nothing about it.

## 2. Read or create the state

    node lib/state.js init

This is the checklist, and it lives on disk in `state.json` because this
computer is going to restart before you are finished.

## 3. Install the master skill

Copy `MASTER.md` to `~/.claude/skills/vimigo-ai-setup/SKILL.md`, creating the
folders. This is what lets the owner come back after a restart by saying
*"continue my vimigo ai setup"* instead of pasting anything again.

## 4. Show the checklist and begin

    node lib/state.js show

Then say:

> *"Right — I can see what your computer needs. I'll work through it and tell
> you whenever I need you for anything. It'll take a little while."*

Then follow `MASTER.md`.
