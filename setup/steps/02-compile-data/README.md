# Step 2 — the /compile-data skill

This is what sends the owner's work to Vimigo at the end of the event, so it has
to be typeable as `/compile-data`, not merely available to the model.

## What done looks like

`node steps/02-compile-data/verify.js` prints `"ok": true`, meaning three files
exist: the skill for Claude, the skill for Codex, and the Codex prompt that
makes `/compile-data` a command the owner can type.

    node lib/state.js set compile-data done --evidence "<evidence from verify.js>"

## If it is already there, leave it alone

Run `verify.js` first. If all three files are present it passes, and this row is
done — mark it and move on. Copying over a skill that is already installed
gains nothing and costs a Claude Code restart the owner did not need.

Only copy the files `verify.js` reports as missing. A partly-installed row is
the usual shape here: Claude has it, Codex does not, because a previous run
stopped halfway.

## Where the file comes from

`steps/02-compile-data/skill/SKILL.md`, in this published tree. Copy it into
all three places; do not write your own and do not edit it on the way.

Two of the three destinations are the same file under a different name — Claude
and Codex both read a folder holding a `SKILL.md`. The third is the Codex
prompt, and it is what makes `/compile-data` something the owner can type rather
than something the model has to decide to use on its own. A hundred people are
going to be told to type that command out loud; two out of three is a failure.

## What to say

> *"Now I'm adding a command you'll use at the end of the event. One moment."*

Then nothing until it is done. This one takes seconds, so no heartbeat is
needed.
