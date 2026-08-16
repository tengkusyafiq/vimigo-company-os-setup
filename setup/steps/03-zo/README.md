# Step 3 — the Zo account

Three things in one row: the owner has a Zo account, this computer holds its
key, and both Claude and ChatGPT can reach it on the owner's own subscription.

## What done looks like

`node steps/03-zo/verify.js <key>` prints `"ok": true`. That answer comes from
Zo, not from anything on this machine.

    node lib/state.js set zo done --evidence "<evidence from verify.js>"

## The only thing the owner does

Sign up and copy their key. Everything else is yours.

Send them to the Vimigo referral link — never the plain sign-up page, or the
account is not attributed. Then:

> *"Sign up on the page I've opened, then copy the key it gives you and paste
> it here."*

If they already have an account, they still need the key:

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
