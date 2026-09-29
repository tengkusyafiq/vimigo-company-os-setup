# Step 3 — saving their work to Vimigo

Only in session 1, only while a Vimigo event is open right now, and only
after you have said the one line below (once per event). Never from
`MASTER.md`, never on a machine that was not enrolled here.

## If it already works, or they already said no

Run `verify.js` first, **before** you say anything below. If it already
passes — `"saving to Vimigo"`, `"all sent - finished"` and `"stopped at your
request"` all count — leave it alone and mark the row. Do not say the line
below, do not re-run `enrol.js`, and do not run `scheduler.js install` for a
row that already works or that the owner already declined.

`"saving to Vimigo"` also covers a laptop still saving to an earlier event
whose window hasn't closed yet. That enrolment keeps going until its own
event closes — never move it to the one open now.

## Is a Vimigo event open right now?

Vimigo's own server decides this, for every event — ask it:

    node lib/event.js

- **`"state": "none"`** — no event is open. Mark the row and stop, silently —
  **never** say the line below, and never run `enrol.js`:

      node lib/state.js set sync not_asked --evidence "no Vimigo event right now"

- **`"state": "offline"`** — this computer couldn't reach Vimigo. Say nothing
  about Vimigo or this row now. Mark it, finish every other row, and end the
  session with the one sentence `START.md` §8 gives for this case — it tells
  them to paste the same message again once they're online:

      node lib/state.js set sync not_asked --evidence "couldn't reach Vimigo"

- **`"state": "open"`** — carry on below.

## Say this first — but only once per event

    node lib/session1.js

If `"announced"` is already `true`, they have already heard this on this
laptop, for this event. Skip straight to **Do**.

Otherwise, say this once, in your own words, right before you enrol:

> *"As you work, I'll save a copy of your Second Brain and our conversations
> to Vimigo, so your submission is ready at the end without extra steps."*

Then, before anything else — including `enrol.js` below — record that you
said it:

    node lib/sync.js --announce

Do not ask a question and do not wait. Shane has explained it to the room.
If they ask anything about it, answer truthfully.

**If they say they do not want it** — whether that is right now, or only
after `enrol.js` has already run below — record it for this event, then
skip the rest of this row entirely:

    node lib/sync.js --stop
    node steps/03-sync/verify.js
    node lib/state.js set sync done --evidence "<the evidence that returns>"

This is the only thing that stops a later session asking or enrolling again
for this event. It works the same whether `enrol.js` has run yet or not.

If the owner later asks, themselves, to start saving again after declining,
that is the one time to use `--resume`:

    node lib/enrol.js --resume --name "<name>" --company "<company>" --role "<role>"

then carry on with everything below **Do**, exactly as a fresh enrolment
would — the scheduler, the check, and marking the row. A plain `enrol.js`
(no `--resume`) refuses on a laptop that already declined this event, on
purpose — never use it to talk yourself past that on the owner's behalf.

## Do

    node lib/enrol.js --name "<name>" --company "<company>" --role "<role>"

- `{"ok":true}` — go on.
- `"reason":"not-open"` or `"no-event"` — no event is open after all. Mark
  the row exactly as for `"none"` above, and move on.
- `"reason":"offline"` — try once more in a minute. If it is still
  `"offline"`, mark the row exactly as for `"offline"` above — the row, and
  the sentence at the end of the session.
- `"reason":"declined"` — they already said no to this event. Run
  `verify.js` and mark the row with its evidence.
- `"reason":"still-saving"` — this laptop is still saving to an earlier event
  that hasn't closed. Leave that alone and skip the rest of this row: run
  `verify.js`, and mark the row with its evidence if it passes.
- `"reason":"sandbox"` — you are not on their computer. Stop everything and
  reply only with the sentence at the very top of `START.md`.

Then:

    node lib/scheduler.js install

On a Mac, say this **before** running it:

> *"You might see a small note saying something was added. That's this — nothing to click."*

Then wait ten seconds and check — this passes only when Vimigo's server says the
laptop checked in:

    node lib/scheduler.js kick
    node steps/03-sync/verify.js

If it says `no check-in yet`, wait thirty seconds and run the last two again, up
to three times. Mark it:

    node lib/state.js set sync done --evidence "<evidence>"

If it still says `no check-in yet` after three tries, or `install` fails: try
`install` once more. Then block the row in plain words and move on — the
Second Brain still works locally, and this is not worth more of their time:

    node lib/state.js block sync --reason "this computer would not let it run in the background"
