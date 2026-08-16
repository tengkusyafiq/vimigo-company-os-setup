# Step 3 — the Zo account

Three things in one row: the owner has a Zo account, this computer holds its
key, and both Claude and ChatGPT can reach it on the owner's own subscription.

## What done looks like

`node steps/03-zo/verify.js <key>` prints `"ok": true`. That answer comes from
Zo, not from anything on this machine.

    node lib/state.js set zo done --evidence "<evidence from verify.js>"

## If it is already working, leave it alone

Run `verify.js` before anything else. If it passes, this row is done — mark it
and move on. Do not re-register anything and **do not ask for the key again.**

You may already have a key without the owner touching anything. Before you ask
them for one, look for a Zo entry in the client configs listed in the platform
file beside this — a setup that got this far yesterday, or was interrupted by a
restart, left one there. Try `verify.js` with that key first.

Asking somebody to fetch a key they gave you an hour ago is the moment a setup
stops looking like it knows what it is doing, and it is the one step here they
cannot do quickly.

## The only thing the owner does

Only when there is no working key already. Sign up and copy their key;
everything else is yours.

### The sign-up link, in full

```text
https://zo-computer.cello.so/0qDXmlEF6Hn
```

**Open that yourself.** The platform file beside this says how. Never ask the
owner for a link, never ask them to find one in an email or a WhatsApp group,
and never send them to `zo.computer` directly — the plain page does not carry
the referral code, and the account is then not attributed to Vimigo.

You have the link. It is written above. There is nothing here to ask for.

Then:

> *"I've opened the sign-up page. Sign up, then copy the key it gives you and
> paste it here."*

If they already have an account, they still need the key — but look in the
client configs first, as above, before asking:

> *"Go to your Zo settings and copy the key, then paste it here."*

## Never

- Never print the key back to them, and never put it in a message, a log, or a
  file you show them.
- Never mark this row done because they pasted something. Mark it done because
  Zo answered.

## Order

This row must be green before anything below it is attempted. A skill, an
integration or an assistant set up against a Zo that is not connected looks
identical to one that worked, and fails later in a way nobody can trace.
