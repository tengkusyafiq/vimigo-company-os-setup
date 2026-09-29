# Step 2 — their Second Brain

A folder of plain notes in their home folder that Claude and ChatGPT both read
and write, so their AI remembers them. It stays theirs after the event.

## If it already works

Run `verify.js` first. If it already passes, leave it alone and mark the row —
`init` and `skills.sync` are safe to repeat, but there is nothing here to fix.

## Do

1. Use the name, company and role they gave you:

       node lib/brain.js init --name "<name>" --company "<company>" --role "<role>"

2. Install the skills — the local copy, so this works offline:

       node lib/skills.js sync --local

3. Check:

       node steps/02-second-brain/verify.js

Mark it with the evidence it printed:

    node lib/state.js set second-brain done --evidence "<evidence>"

## Rules

- `init` never overwrites a note that exists. Run it as often as you like.
- It writes the skill for **both** apps even if only one is installed; an app
  installed tomorrow finds it the first time it opens. Never put a copy under
  the `.codex/skills` folder — Codex lists a skill found there twice.
- It adds a short block to each app's standing-instruction file, between two
  marker lines, and leaves everything else in those files alone.
- **Never install the ChatGPT app, the Codex app or the Claude app** — not in
  session 1, and not when another session hands off to it. If Codex isn't on
  this computer, prepare it anyway: `init` and `skills.js sync` still write
  the skills into `~/.agents/skills/<name>/` and the block into
  `~/.codex/AGENTS.md`, so when the owner installs the app later it just
  works.

## What to say

> *"Now I'm giving your AI a notebook, so it remembers you and your work from one day to the next."*
