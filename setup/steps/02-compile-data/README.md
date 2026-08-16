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

## Do not restart anything for this row

The files are on disk the moment you write them, and `verify.js` reads disk. The
row is done. What a restart buys is `/compile-data` appearing in the menu — and
that is needed at the **end of the event**, not now.

So finish the checklist first. Restarting Claude Code here kills the session
mid-setup, costs the owner a resume they did not ask for, and gains nothing they
will use in the next hour.

Mention it once, at the very end, after every row is green:

> *"One last thing — close Claude and open it again when you get a moment. That
> makes the /compile-data command appear in your menu. It's for the end of the
> event, so there's no rush."*

If they are still in this session at the end and you have to restart anyway,
say it the way `MASTER.md` says:

> *"I'm going to close this and reopen it. When it's back, say hi and I'll pick
> up where we are."*

## What to say

> *"Now I'm adding a command you'll use at the end of the event. One moment."*

Then nothing until it is done. This one takes seconds, so no heartbeat is
needed.
