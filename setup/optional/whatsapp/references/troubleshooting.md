# Troubleshooting

Diagnose from the bottom up: process, network, bridge authentication, WhatsApp connection, MCP server, client registration.

## It worked yesterday and today it does not

Read this before anything else when someone who already had a working setup
says their WhatsApp stopped, the AI cannot read their messages, or a tool
answers that WhatsApp is not on. It is the commonest report there is, it
arrives the morning after the machine was first shut down, and it is **not**
the same problem as installing.

**Do not reinstall, and do not re-pair, until you have read the four checks
below.** The linked session in `store/` is the one thing here that cannot be
rebuilt without the owner picking up their phone again. A reinstall that
"fixes" a bridge which was merely asleep costs them a pairing they did not
need to redo, and it is the most likely way for you to make this worse.

To them, say nothing yet beyond *"Let me take a look."* Announce the fix once
it is done, not each thing you tried.

### The four states, cheapest first

Work down. Stop at the first one that is false; that is the fault.

**1. Is anything listening on the bridge port?**
If nothing answers, the bridge is not running. Go to check 2.
If something answers but does not identify itself as the bridge, another
program took the port while the bridge was away — find it before restarting,
or the restart fails the same way.

**2. Did the thing that is supposed to start it survive?**
This is the check people skip, and it is the one that fails. **Verify the
autostart mechanism still exists — do not assume the install created it.**

- Windows: the Startup shortcut *and* the watchdog scheduled task. Registering
  a scheduled task returns "Access is denied" on locked-down, corporate and
  some OEM machines, so an install can succeed with **no watchdog at all** and
  say nothing. If the task is missing, that is your answer: the bridge died
  once and nothing was ever going to bring it back.
- macOS: `launchctl print gui/$(id -u)/com.user.whatsapp-bridge`. A plist on
  disk is not a loaded agent.
- Linux: `systemctl --user is-enabled whatsapp-bridge`.

Restore whatever is missing before you start the bridge, or you will be back
here tomorrow.

**3. Is it running but not connected?**
`connected: false` with the process alive is almost always **the bridge
starting before the network did.** Login and boot fire well before wifi
associates; the bridge comes up, cannot reach WhatsApp, and sits there. This
is the single most likely cause of a day-two report on a laptop.

Restart the bridge now that the network is up — that alone fixes it. Then fix
the cause so it does not recur: it must restart on *any* exit, not only on
failure, and it should start late enough that the network exists.

- Windows service: `SERVICE_DELAYED_AUTO_START`, and let NSSM restart it on
  exit.
- macOS: `KeepAlive` true, not `SuccessfulExit`-conditional.
- Linux: `Restart=always` with `After=network-online.target`.

**4. Is it connected but logged out?**
`connected: true`, `logged_in: false` means the phone unlinked it — they
removed the device, hit the linked-device limit, or WhatsApp expired an idle
session. This is the only one of the four that needs them. Pair again by
phone code; keep everything else.

### What to say when it is fixed

One sentence, no history:

> *"It's back — you can ask about your messages again."*

If it was state 4 and they had to link again, add why in plain words:

> *"Your phone had unlinked it, so we linked it again."*

Never explain a port, a service, a watchdog or a network race. They asked for
their WhatsApp, not for the reason.

### If the same machine comes back a third time

Something structural is wrong — quarantined by antivirus each night, a locked
down account that cannot hold any autostart, a port permanently taken. Stop
restarting it by hand. Find which of those it is and fix that, because the
owner is now watching a thing break on a schedule and will not trust it again
however many times you revive it.

## Service running but WhatsApp disconnected

1. Confirm the service's child process is the expected bridge binary, not merely the service wrapper.
2. Call authenticated `/api/auth/status` and record `connected`, `logged_in`, `pairing_required`, and `wa_version` without exposing the token.
3. Read recent bridge logs.
4. Test DNS and HTTPS reachability for `web.whatsapp.com`.
5. If startup failed due to DNS, restore name resolution and restart the bridge; a running REST server does not prove the WhatsApp websocket connected.
6. If the source is current but binaries predate it, rebuild pinned dependencies and restart.

## Pairing

- If `logged_in: true`, do not pair again.
- If `pairing_required: true`, **prefer the phone pairing code over the QR** — see "Pair by phone number first" below. Fall back to `get_pairing_qr` only if the code path fails, and if you do, read "Showing a QR without opening Acrobat" before putting anything on screen. Either way, keep rotating it — one fetch is never enough.

### Pair by phone number first — this is the default

**Always try the phone code before the QR.** An eight-character code the owner
types beats a square they have to aim a camera at: no image, no file, no
browser, no webcam, and nothing that can open in the wrong application. It
appears in the chat they are already looking at.

Reach for the QR only when the code path has actually failed — not because a QR
seemed simpler to produce.

**Ask for their number, and give an example.** A bare "what's your number?"
gets every format under the sun and a long pause while they wonder which one you
want. The example is what stops that:

> *"What's the phone number on your WhatsApp? You can type it however you
> normally would — for example 012-345 6789."*

Let them type it themselves. Never type it for them, never read it off a contact
list, and never ask them to add a country code or strip a zero — formatting is
your job, not theirs.

Any way they write it is right: `0123456789`, `012-345 6789`, `60123456789`,
`+60 12-345 6789`. Normalize it yourself to E.164 digits with no `+`:

- Strip spaces, dashes, brackets and any leading `+`.
- If it already starts with the country code, keep it.
- If it starts with a national trunk `0`, drop that `0` and prefix the country
  code.
- `60` + `0123456789` is **not** `600123456789`. The trunk zero goes:
  `60123456789`. The bridge rejects the wrong form without saying why.

**If they gave a national number and you do not know their country**, ask —
plainly, once, and only if you cannot tell from the machine's own locale or time
zone:

> *"And which country is that number in?"*

Never guess a country code. A number normalized against the wrong country is the
same silent failure as a mistyped digit: accepted, delivered nowhere.

**Read the number back before you use it**, and wait for them to confirm:

> *"I'll use 60 12 345 6789 — is that right?"*

A number that is one digit out is accepted by WhatsApp, sends the code to a
stranger, and leaves the owner staring at a phone that never buzzes. It looks
exactly like the setup being broken, and it is the one failure you cannot detect
afterwards.

**Wait for the bridge's websocket to connect before requesting.** A code
requested too early fails with `websocket not connected` and then keeps failing
forever on that session. Confirm `connected: true` first.

Then request it:

```text
POST http://127.0.0.1:8080/api/auth/pair-phone
Authorization: Bearer <token>
Content-Type: application/json

{"phone":"60123456789"}
```

The response carries `code`. Show those eight characters **as text in the
conversation** — no file, no image, no browser — and tell them where to type it:

> *"On your phone open WhatsApp, tap Linked Devices, then Link a Device, then
> tap 'Link with phone number instead'. Type this code: ABCD-1234"*

Requesting a phone code does not cancel the QR; both live on the same session,
so a QR remains available as a fallback and dies at the same time.

### Showing a QR without opening Acrobat

Only if the code path failed.

**Never open an image file by association.** `Start-Process`, `Invoke-Item`,
`open` or `xdg-open` on a `.png` lands in whatever that machine associates with
images — Acrobat, Photos, Paint, an editor asking about colour profiles. For an
owner it is a strange program opening on top of their work, and it will not
refresh when the code rotates.

Do one of these instead, in order of preference:

1. **Render the QR inline in the conversation** if your surface can display an
   image directly. Nothing touches disk.
2. **Write a small HTML page** and open *that*. Browsers are the one association
   that is reliable on a stranger's machine. Embed the PNG as a `data:` URI so
   the page is a single self-contained file, put the eight-character code
   underneath it as text, and add `<meta http-equiv="refresh" content="3">` so
   the page reloads itself while you rewrite it on rotation. Write to a temporary
   file, then open the `.html`.

Never hand the owner a file path and ask them to open it themselves.
- This is the one moment the owner has to do something. Give it in full, in
  plain words, and ask which phone they have first if you do not know — Linked
  Devices is **not** under Settings on Android, and an owner sent to the wrong
  menu will scroll past Account, Privacy, Chats and Notifications, find nothing,
  and give up:

  > *"Open WhatsApp on your phone. On an iPhone, tap Settings. On Android, tap
  > the three dots at the top right. Then tap Linked Devices, then Link a
  > Device."*

  That gets them to the right screen on either phone. What they do next depends
  on which path you are on — typing the eight-character code, or pointing the
  camera at a square — so finish the instruction with the line from that section
  rather than assuming the camera.

  Then hold the pairing open — actively, not by sleeping. What you are waiting
  for is someone finding a menu on a phone for the first time, which takes
  longer than one code lives. See "The code expires, and you must rotate it"
  below before you present anything: fetching once and waiting is the single
  commonest way this step fails.
- WhatsApp session lifetime is not a fixed 20-day guarantee. Re-pair only when the linked session is actually invalid or removed.
- If the linked-device limit is reached, the user must remove an old device on the phone.

### The code expires, and you must rotate it

**A pairing session lasts about 160 seconds.** WhatsApp rotates the QR every
twenty seconds or so, and after a handful of rotations WhatsMeow runs out of
codes and closes the login websocket. The 8-character phone-link code dies with
the same session.

That is shorter than the job in front of the owner. A first-time Android owner
hunting for Linked Devices routinely takes longer than one session, so **assume
the first code will die before they scan it.** This is normal and is not a
fault.

**HTTP 200 does not mean the code is alive.** The bridge's QR goroutine returns
on its channel timeout and never clears the stored pairing state, so
`/api/auth/pairing-qr` keeps answering 200 with the *same dead PNG forever*.
Nothing in the response says it is stale. Fetch it once, show it, and wait ten
minutes, and you will have shown the owner a dead square for nine of them and
then reported a broken install.

Detect staleness by change, not by status:

- Re-fetch every few seconds and compare the code to the last one.
- A code that has **not changed for about 90 seconds is dead.** A live pairing
  session never sits still that long.

To get a live code again, **restart the bridge, then re-fetch.** Nothing else
clears the stale state — re-requesting the endpoint returns the same dead image.

Budget the whole pairing attempt at **ten minutes and up to four bridge
restarts.** At ~160 seconds a session, ten minutes takes three or four goes;
two is not enough. Raise your tool's timeout to cover the full ten minutes
before you start, and do not let it cut the wait short.

**Rotating is not cancelling.** Replace a code the moment it is dead, and never
while it is live and they are mid-scan — the square they are pointing at is the
one you are about to invalidate. If they say they are scanning, let the current
code run its course.

Say it once, in plain words, and do not narrate each rotation:

> *"The square refreshes by itself every so often. Take your time — just scan
> whichever one is on screen when you get there."*

If four restarts pass with nobody scanning, stop. Tell them you will set it up
whenever they are ready, and leave it. A code nobody scanned is not a failure to
diagnose, and it is not a support case.

For passkey-gated accounts, use the repository's `tools/onboard-passkey.mjs` only after a phone-code pairing request creates the challenge. The user must complete the system-camera/WebAuthn confirmation with a nearby phone. Inspect the helper and its expected environment before executing it.

## Tools missing in a client

1. Confirm the MCP binary path exists and starts in stdio mode without writing protocol-breaking text to stdout.
2. Confirm `WHATSAPP_API_KEY` and `API_BASE_URL` are supplied to the MCP process.
3. Parse the client configuration.
4. Remove duplicate registrations named `whatsapp`, `whatsapp-mcp-go`, or `whatsapp-mcp`, retaining one intended entry.
5. Restart or refresh the client surface.
6. Inspect client MCP logs and run its MCP list/status command.

## Media

- Local install: use `send_media` with `media_path`.
- Remote install: use upload/object-storage flow only when the MCP server cannot access the local path.
- Voice-note conversion requires FFmpeg; ordinary file sending does not.
- Expired WhatsApp CDN media may recover through the bridge's media-retry receipt when the sender's device still has the file and is online.

## Build failures

- `go-sqlite3 requires cgo`: enable CGO and install a working C compiler.
- Windows DLL error: ensure the service environment includes the compiler runtime directory used by the binary, or produce a self-contained build where feasible.
- Go version error: follow the `go` directive in each module, not a hard-coded version in this skill.
- Dirty `go.mod`/`go.sum` after an update: determine whether an earlier `go get -u` changed pins. Preserve the diff, restore only with explicit authority, then build the repository-pinned revision.

## Safe recovery

- Never delete session databases as a first response to sync problems.
- Back up `store/` before database repair.
- Prefer resync/reconnect APIs and protocol updates before considering re-pairing.
- Preserve logs and exact health output long enough to establish the cause.
