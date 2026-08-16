# Hermes One

Only when the owner asks for it. Nothing else in this setup depends on it, and
nothing breaks if it is never installed.

Hermes One is a desktop app — the app for Hermes Agent, which belongs to Nous
Research rather than to Vimigo. Installing it is a download and an installer.

## Say this before you install, not after

This is the single most likely thing on the whole checklist to end in a
complaint, so it goes first, in plain words:

> *"Quick heads-up before I put this on: Hermes needs its own AI key to answer
> anything, and your ChatGPT or Claude subscription doesn't include one. It's a
> separate sign-up you pay per use. I'll install it either way — you can decide
> about the key later, and it costs you nothing to leave it."*

Say it **before**, because an owner who has done everything right, and pays for
ChatGPT every month, will otherwise open a brand new app and be asked for
something they have not got. That reads as a broken setup, and it is not.

## What done looks like

    node optional/hermes/verify.js

`"ok": true` means the app is installed. That is the whole row.

    node lib/state.js set hermes done --evidence "<evidence from verify.js>"

**The row is done the moment Hermes One is installed.** The key is optional and
theirs to decide on later. Never hold this row open waiting for one, never ask
them for one, and never treat a keyless Hermes as a failure.

## If it is already installed, leave it alone

Run `verify.js` first. If it passes, mark the row and move on.

## Installing

The platform file beside this has the addresses and the silent-install flags.
It is a plain download, so it is slower than it looks — heartbeat it:

> *"Still downloading — about a minute in. Usually two or three."*

## When it is done

Open it once, so they have seen it:

> *"That's installed. I'll open it so you know where it is — if it asks for a
> key, just close it. Nothing else needs it."*

Then finish. Do not walk them into the key screen, do not compare providers,
and do not offer to sign them up for one. If they ask what a key costs, say it
is per use and they can look at it after the event.

## Never

- Never suggest their ChatGPT or Claude subscription will work. It will not.
- Never block this row on a key.
- Never let this row hold up anything else — it is last for a reason.
