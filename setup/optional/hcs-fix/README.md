# The Cowork fix

Only when the owner reports it. Never offered, never run as part of the
checklist, never suggested because you noticed something.

Claude Desktop's Cowork tab runs its sandbox on three Windows services. When
they are not running, Claude shows:

    Missing HCS services: HNS, vmcompute, vfpext

and the Cowork button stays greyed out.

## There are two different faults here, and only one is safe to fix

This is the whole of this document. Read `verify.js`'s answer before you touch
anything.

| What `verify.js` says | What it means | What you do |
|---|---|---|
| `"fix": "start"` | The services are installed but stopped | Start them. Safe. |
| `"fix": "features"` | The services are not installed at all | **Refuse.** See below. |
| `"fix": "firmware"` | Virtualization is off in the laptop's firmware | **Refuse.** Nothing works until it is on, and that is not a thing software changes. |
| `"ok": true` | All three already running | Nothing to do. Say so and stop. |

### `"start"` — do this one

Installed and stopped is a real state, and it looks identical to the owner:
Claude prints the same message either way. Starting a stopped service needs no
restart, changes nothing about how the computer boots, and is undone by a
restart if it goes wrong.

See `windows.md` for the commands. It asks for administrator once. Warn first —
a UAC box that appears unannounced is frightening:

> *"Windows is going to ask your permission in a blue box. Click Yes — I'm
> switching some Windows features back on that Cowork needs."*

Then check again with `verify.js`. If all three are running:

> *"Done. Close Claude completely and open it again, and Cowork should work."*

### `"features"` — refuse this one

The services are not installed. Installing them means turning on Windows
features with `dism` and restarting so Windows can apply them.

**Two laptops did not come back from that restart.** A Legion and an MSI,
different makes, at an event: ran the setup, restarted when asked, and met
*"Your device ran into a problem and couldn't be repaired."* Neither reached
Windows again without recovery. Nobody has since worked out why, and the setup
script that did it has had that step switched off ever since.

So this is not a matter of doing it carefully. **The failure was never
explained**, which means there is no "carefully" to be careful about. Do not
enable the features. Do not restart the machine to apply anything. Do not
research a safer way to do it during an event on somebody else's laptop.

Say it plainly, and make clear what they still have:

> *"I can't switch this one on safely — it needs a change to how Windows starts
> up, and we've seen that stop a laptop booting. Everything else is working:
> your Zo, your commands, all of it. Cowork is the only part that won't run, and
> you can still use Claude normally."*

Then mark the row blocked and carry on:

    node lib/state.js block hcs-fix --reason "Cowork needs a Windows change that isn't safe to make here"

### `"firmware"` — refuse this one too

The laptop's own firmware has virtualization switched off. Nothing above can
work until it is on, and it is a setting in the start-up screen that is named
differently on every make of laptop.

Nothing has been changed and no restart is needed. Say that, because a machine
that cannot do this is not a machine that has been broken:

> *"This laptop has a setting switched off that Cowork needs, and it's not
> something I can change from here — it's in the start-up screen. Everything
> else is set up and working."*

Block the row with the same command and move on.

## Never

- Never run this because you saw the error. Run it because they asked.
- Never enable a Windows feature, run `dism`, or restart the computer for this.
- Never turn Secure Boot off. Nothing here needs it and it makes them less safe.
- Never tell them to change a firmware setting themselves.
- Never leave the impression their setup failed. One button is greyed out.
