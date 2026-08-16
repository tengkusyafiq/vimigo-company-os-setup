# The Cowork fix on Windows

Only reachable when `verify.js` said `"fix": "start"`. For any other answer,
read `README.md` — the other two are refusals, not commands.

## Warn before the box appears

    > *"Windows is going to ask your permission in a blue box. Click Yes — I'm
    > switching some Windows features back on that Cowork needs."*

## Start the stopped services

Two of the three are drivers rather than ordinary services, and a driver whose
start type is `disabled` refuses to start while saying nothing useful about why.
So set the start type and start it, in one elevated call:

    sc.exe config vmcompute start= demand & sc.exe start vmcompute
    sc.exe config hns       start= demand & sc.exe start hns
    sc.exe config vfpext    start= demand & sc.exe start vfpext

Run only the ones that are not already running — `verify.js` names them. Join
them with `&`, which is the separator `cmd.exe` actually has. A `;` between them
is PowerShell's, and `cmd.exe` reads it as an ordinary argument: the calls
collapse into one malformed command, nothing runs, and the step reports success.

Elevate once, for all of them together, rather than once per service:

    Start-Process cmd.exe -ArgumentList '/c','<the joined commands>' -Verb RunAs -Wait -WindowStyle Hidden

The space in `start= demand` is required. `start=demand` is not the same thing
to `sc.exe` and it will refuse it.

## Check, do not announce

`sc.exe` exiting zero proves the command was accepted, not that the service is
running. Ask again:

    node optional/hcs-fix/verify.js

Only `"ok": true` means it worked. If it still says `"fix": "start"`, the
services would not start — that is the end of what is safe to try here. Block
the row and move on; do not escalate to enabling features.

## Then the restart that is not a restart

Claude Desktop reads this at startup, so it needs reopening — the computer does
not:

> *"Done. Close Claude completely and open it again — not just the window — and
> Cowork should work. Your computer doesn't need restarting."*

## What you never do here

No `dism`. No enabling Windows features. No restarting the computer. Those are
the `"features"` path, and `README.md` says why that one is refused.
