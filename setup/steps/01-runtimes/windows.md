# Step 1 on Windows

## Before you run anything, say this

`winget` raises a UAC prompt. It steals focus and appears with no warning, so
say it first:

> *"Windows is about to ask your permission in a blue box. Click Yes."*

A console window may also appear:

> *"A black window will open. That's normal — I'm using it to install things.
> You can ignore it."*

## Commands

Install only what is missing.

    winget install --id OpenJS.NodeJS.LTS  --silent --accept-package-agreements --accept-source-agreements
    winget install --id Git.Git            --silent --accept-package-agreements --accept-source-agreements
    winget install --id Python.Python.3.13 --silent --accept-package-agreements --accept-source-agreements

Run each in the background and poll, so you can keep talking.

## After installing

`winget` does not refresh the PATH of a shell that is already open, so
`verify.js` will still report the thing missing. Start a new shell before
verifying. If it is still missing after a new shell, the install genuinely
failed — do not mark the row done.
