# The Cowork fix

Only when the owner reports it. Never offered, never run as part of the
checklist, never suggested because you noticed something.

Claude Desktop's Cowork tab runs its sandbox on three Windows services. When
they are not running, Claude shows:

    Missing HCS services: HNS, vmcompute, vfpext

and the Cowork button stays greyed out.

## Read `verify.js`'s answer before you touch anything

This is the whole of this document.

| What `verify.js` says | What it means | What you do |
|---|---|---|
| `"fix": "start"` | The services are installed but stopped | Start them. Safe — see `windows.md`. |
| `"fix": "features"` | The services are not installed at all | You decide — see "You decide" below. |
| `"fix": "firmware"` | Virtualization is off in the laptop's firmware | Refuse. Nothing works until it is on, and that is not a thing software changes. |
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

## You decide — these are the facts, not a script

Starting stopped services (`"fix": "start"`) is safe and reversible: do it.

Turning on Windows features that change how the computer starts
(`"fix": "features"`) left two laptops of different makes unable to boot at a
past event, and nobody established why. You may do it **only when every one of
these holds** — check each, do not assume:

1. **BitLocker is off, or its recovery key is saved somewhere off this laptop.**
   `manage-bde -status C:` shows it. If it is on, the owner's Microsoft account
   usually holds the key (they can look on their phone). No key off the laptop,
   no change — every recovery path asks for it.
2. **System Restore is on, and a restore point named `Before Cowork fix` exists.**
   Turn protection on for the system drive if it is off, create the point, then
   confirm it is listed. This needs one administrator prompt — warn first.
3. **No other virtual-machine software is installed** — VirtualBox, VMware,
   BlueStacks, Android emulators, other hypervisors. If one is, refuse.
4. **Virtualization is on in the firmware** (`"fix": "firmware"` means it is not).
   If it is off, stop: say Cowork will not work on this laptop and that Claude
   Code does everything they need.
5. **They say yes** to: *"This changes how your computer starts up. It's the only
   way to make Cowork work here — is it okay if I do it?"*
6. **Before restarting,** open the recovery page and ask them to keep it on their
   phone — photograph it or open the same address there:

       https://tengkusyafiq.github.io/vimigo-company-os-setup/setup/help/boot-recovery.html

   > *"Keep this on your phone, just in case. If the computer won't start, it shows you the way back — all clicking, no typing."*
7. Only then make the change and restart.

If any one does not hold: say in one sentence that Cowork cannot be switched on
safely on this laptop, and that Claude Code does the same work. Move on.

Either way you land — a safeguard did not hold, or the owner said no — block
the row instead of leaving it hanging:

    node lib/state.js block hcs-fix --reason "Cowork needs a Windows change that isn't safe to make here"

If you went ahead instead and `verify.js` now says `"ok": true`, mark the row
done with that evidence, exactly as any other check.

## Never

- Never run this because you saw the error. Run it because they asked.
- Never enable a Windows feature, run `dism`, or restart the computer for this
  unless every one of the seven safeguards above holds.
- Never turn Secure Boot off. Nothing here needs it and it makes them less safe.
- Never tell them to change a firmware setting themselves.
- Never leave the impression their setup failed. One button is greyed out.
