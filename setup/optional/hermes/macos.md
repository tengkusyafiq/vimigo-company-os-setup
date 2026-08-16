# Hermes One on macOS

## Which file

    https://api.github.com/repos/fathah/hermes-desktop/releases/latest

Two Mac builds ship, and picking the wrong one gives them an app that will not
open. Ask the machine which it is:

    uname -m

- `arm64` — Apple Silicon — take the asset ending `-arm64.dmg`
- `x86_64` — Intel — take the asset ending `-x64.dmg`

If that address does not answer, the download page is
`https://hermesone.org/download`.

## Installing

Mount it, copy the app across, unmount:

    hdiutil attach -nobrowse -quiet "<the .dmg you downloaded>"
    cp -R "/Volumes/<the mounted name>/Hermes One.app" ~/Applications/
    hdiutil detach -quiet "/Volumes/<the mounted name>"

`~/Applications`, not `/Applications`. The owner's own folder needs no password;
the system one asks for theirs, and this row is not worth a password prompt.
Create it if it is not there.

Always detach, including when the copy failed. A mounted image left behind sits
on their desktop looking like something went wrong.

## Gatekeeper

An app downloaded outside the App Store is quarantined, and the first open shows
a warning rather than the app. Clear it as part of installing, so they never
meet it:

    xattr -dr com.apple.quarantine ~/Applications/"Hermes One.app"

## Checking

    node optional/hermes/verify.js

## Opening it once

    open ~/Applications/"Hermes One.app"

Say what it is before it appears:

> *"That's installed. I'll open it so you know where it is — if it asks for a
> key, just close it. Nothing else needs it."*
