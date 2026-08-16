# Hermes One on Windows

## Which file

Ask the releases page which version is current rather than pinning one that
will be stale by the event:

    https://api.github.com/repos/fathah/hermes-desktop/releases/latest

Take the asset whose name ends `-setup.exe` — at the time of writing that is
`hermes-desktop-0.7.6-setup.exe`. Not `-portable.exe`: the portable build
installs nothing, so `verify.js` will not find it and the row cannot close.

If that address does not answer, the download page is
`https://hermesone.org/download`.

## Installing

    <the -setup.exe you downloaded> /S

`/S` is the silent switch for this installer. It goes into the owner's own
profile and asks for no administrator rights, so there is no UAC box to warn
them about — say nothing, and let the heartbeat do the talking.

If `/S` leaves nothing installed, run the installer without it and warn first:

> *"An installer window is about to open. Click through it — Next, then Install.
> I'll wait."*

## Checking

    node optional/hermes/verify.js

It looks for the app where Windows records installed programs. A download that
did not finish leaves no entry there, which is the point.

## Opening it once

    Start-Process "<the installed hermes-agent.exe>"

`verify.js` prints where it is. Say what it is before it appears:

> *"That's installed. I'll open it so you know where it is — if it asks for a
> key, just close it. Nothing else needs it."*
