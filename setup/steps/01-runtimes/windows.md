# Step 1 on Windows

## Before you run anything, say this

`winget` raises a UAC prompt. It steals focus and appears with no warning, so
say it first:

> *"Windows is about to ask your permission in a blue box. Click Yes."*

A console window may also appear:

> *"A black window will open. That's normal — I'm using it to install things.
> You can ignore it."*

## First, check the installer exists

    winget --version

Not every Windows machine has it. Windows 10 without App Installer, and plenty
of company laptops, have no `winget` at all — and this row gates every other
row, so a machine that stops here stops entirely.

**If it answers**, use the commands below. **If it does not**, skip to "When
there is no winget". Do not run a `winget install` to find out; a command that
is not there fails in a way that looks like the install failed.

## Commands

Install only what is missing.

    winget install --id OpenJS.NodeJS.LTS  --silent --accept-package-agreements --accept-source-agreements
    winget install --id Git.Git            --silent --accept-package-agreements --accept-source-agreements
    winget install --id Python.Python.3.13 --silent --accept-package-agreements --accept-source-agreements

Run each in the background and poll, so you can keep talking.

## When there is no winget

Download the official installers and run them yourself. This is your job, not
the owner's — never send them to the Microsoft Store to fetch App Installer,
and never leave the row blocked because a package manager is absent.

**Node** — ask nodejs.org which release is current rather than pinning one that
will be stale by the event:

    https://nodejs.org/dist/index.json

Take the first entry whose `lts` is not false, then build the address from its
`version` exactly as written, `v` and all:

    https://nodejs.org/dist/v24.19.0/node-v24.19.0-x64.msi

Install it without a window:

    msiexec /i "<the .msi you downloaded>" /qn /norestart

**Git** — the current release is listed here:

    https://api.github.com/repos/git-for-windows/git/releases/latest

Take the asset whose name ends `-64-bit.exe`, then:

    <the .exe you downloaded> /VERYSILENT /NORESTART /NOCANCEL

**Python**:

    https://www.python.org/ftp/python/3.13.3/python-3.13.3-amd64.exe
    <the .exe you downloaded> /quiet InstallAllUsers=0 PrependPath=1

These take longer than `winget` — they are plain downloads. Keep the heartbeat
going, and say the same thing you would have said anyway:

> *"Still installing — about three minutes in. These usually take five."*

The owner never needs to know which route you took.

## After installing

`winget` does not refresh the PATH of a shell that is already open, so
`verify.js` will still report the thing missing. Start a new shell before
verifying. If it is still missing after a new shell, the install genuinely
failed — do not mark the row done.
