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

## The one thing the owner does — and you walk them through every click

They have never seen a key and do not know what one is. **Never say "paste your
key here" and stop.** That sentence assumes they know what a key is, where it
lives, and that they have one. All three are wrong. Every time you name
something they have to find, say where it is on screen in the same breath.

### First, ask whether they have an account

> *"Do you already have a Zo account, or shall I get you signed up?"*

This one answer changes everything that follows, and somebody without an account
cannot produce a key at all — they would sit on a page hunting for something
that is not there.

### If they do not have one

The sign-up link, in full:

```text
https://zo-computer.cello.so/0qDXmlEF6Hn
```

**Open that yourself.** The platform file beside this says how. Never ask the
owner for a link, never ask them to find one in an email or a WhatsApp group,
and never send them to `zo.computer` directly — the plain page does not carry
the referral code, and the account is then not attributed to Vimigo.

You have the link. It is written above. There is nothing here to ask for.

Say what is about to happen, then wait:

> *"I'm opening the sign-up page. Make yourself an account there — email and a
> password — and tell me when you're signed in. I'll take it from there."*

Wait for them to say they are in. Do not ask for anything yet.

### Show them the page rather than reading five clicks aloud

When you cannot drive the screen yourself, open the page instead. It carries
the same clicks with a picture of each:

```text
https://tengkusyafiq.github.io/vimigo-company-os-setup/help/zo-key.html
```

If that will not load, fetch the local copy and open the file:

    node lib/fetch-setup.js <base> help/files.json

It lands at `<home>/.vimigo/setup/help/zo-key.html`. Beside it, `help/zo-key.md`
is the same words with no pictures — read from that when neither page opens.

> *"I've opened a page that shows you exactly where to click. Follow it, and
> paste me the key when you've got it."*

Then be quiet and let them read. Do not narrate the page back at them.

### The sign-up page does not give them a key

This is where the old wording sent people looking for something that was never
on screen. **There is no key until somebody makes one**, and making one takes
five clicks inside Zo's settings.

If you have tools that can see and control the screen, **do it yourself.** They
are signed in; this part is clicking, and clicking is your job:

> *"Thanks — give me a moment, I'll set up the connection myself."*

Otherwise read the five clicks out, one line at a time, and wait after each:

1. Click **Settings**, then **Advanced**
2. Find **Access Key**
3. Type any name in the box — *my computer* does
4. Click **Add**
5. Zo shows you a long line of letters starting with `zo_sk_` — copy it

Then, and only then, ask for it — naming the thing you can both see:

> *"Copy that long line starting with zo_sk_ and paste it to me here."*

You can open the settings page for them too, rather than describing where it is:

```text
https://zo.computer
```

Their own workspace address works better once you know it — `verify.js` returns
it — but before that, the plain address gets them to the same Settings button.

### If they already have an account

Same five clicks. They still have to make a key, because the key is per computer
and this computer does not have one. Do not assume an existing account means an
existing key, and check the client configs first as above.

### When they paste something

A key starts with `zo_sk_`. If what they paste does not, they have copied the
wrong thing — usually their email, their password, or the workspace address.
Do not run it through `verify.js` and report a failure; say what to look for:

> *"That's not quite it — the one I need is a long line starting with zo_sk_,
> just under where you clicked Add."*

Then run `verify.js` and let Zo answer.

## After the key works: two things they will want

Both are optional, both need a person, and both have a page. Say the reason
before you open either — an owner who knows why a step exists asks better
questions when it goes wrong.

### Connecting their AI subscription

> *"Your Zo needs a brain to think with. You already pay for one — your ChatGPT
> or Claude subscription — so we point Zo at that instead of buying a second
> one. Nothing extra to pay. Want me to show you?"*

```text
https://tengkusyafiq.github.io/vimigo-company-os-setup/help/ai-subscription.html
```

**The names on that screen do not match what they pay for.** ChatGPT is called
**Codex**, Claude is called **Claude Code**. Say which one to click before they
go looking, or they will hunt for a ChatGPT button that is not there.

The two routes also run in opposite directions — Codex copies a code out to the
sign-in page, Claude Code brings one back — so never help from memory of the
other one.

### Talking to their Zo from their phone

> *"Right now you can only talk to your Zo at this computer. Link Telegram and
> you can message it from your phone, anywhere — like texting a colleague who's
> always at their desk. Want that?"*

```text
https://tengkusyafiq.github.io/vimigo-company-os-setup/help/telegram.html
```

### Checking they are signed in somewhere

    node steps/03-zo/signed-in.js

- `"state": "found"` — leave it alone, say nothing.
- `"state": "unknown"` — **not a failure.** It cannot see Claude Desktop, which
  is a perfectly normal thing to be using. Ask, because they can answer by
  looking:

  > *"Is your Claude or ChatGPT app open and signed in? You should see your own
  > name or picture in the corner."*

  Yes: accept it and move on. Unsure: open the subscription page above. No: walk
  them through signing in, then ask again.

**Never block the `zo` row on this.** Signing in is not something you can do for
them, and refusing to finish over a question you cannot answer is worse than
asking.

## Never

- Never say "the key" to somebody who has not been shown one. Name where it is
  on screen every single time.
- Never ask them to find, open, or look up anything you can open yourself.
- Never print the key back to them, and never put it in a message, a log, or a
  file you show them.
- Never mark this row done because they pasted something. Mark it done because
  Zo answered.

## Order

This row must be green before anything below it is attempted. A skill, an
integration or an assistant set up against a Zo that is not connected looks
identical to one that worked, and fails later in a way nobody can trace.
