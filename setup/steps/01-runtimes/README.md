# Step 1 — Node, Git and Python

## What done looks like

`node steps/01-runtimes/verify.js` prints `"ok": true`. Use its `evidence`
string verbatim when you mark the row:

    node lib/state.js set runtimes done --evidence "<evidence from verify.js>"

Never write your own evidence. The string has to come from something you read
back, or the row means nothing.

## What to say

Before you start:

> *"First I'm putting three small programs on your computer that everything
> else needs. Takes a few minutes — you don't have to do anything."*

While waiting, roughly once a minute:

> *"Still installing — about two minutes in. These usually take three to five."*

When it's done, say nothing. Show the checklist and move to the next row.

## Rules

- **Never run an install in the foreground.** Run it in the background and poll,
  or you cannot say anything for the whole five minutes.
- Install only what `verify.js` says is missing. Re-installing something that is
  already there wastes the owner's time and occasionally breaks it.
- Read the platform file — `windows.md` or `macos.md` — before running anything.
