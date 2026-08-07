#!/bin/bash
#
# Vimigo - the AI Personal Assistant, on its own.
#
#   curl -fsSL https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-assistant-mac.sh | bash
#
# The main setup connects Claude and ChatGPT on the laptop to the owner's Zo.
# This is the other half: a WhatsApp or Telegram number the owner can message
# from their phone, answered by their Zo.
#
# It is deliberately not on the front page. v1 ships without it, and this is
# for somebody who has asked for it - not something a first-time customer
# stumbles into.
#
# Same shape as install-mac.sh: a script piped into bash was never a file on
# disk, so Gatekeeper never applies.

set -u

RELEASE='https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/v1.0/vimigo-company-os-setup-mac-v1.0.zip'
DESKTOP="$HOME/Desktop"
FOLDER='Vimigo AI Setup'

teal()  { printf '\033[36m%s\033[0m\n' "$1"; }
plain() { printf '%s\n' "$1"; }

stop() {
    printf '\n\033[31m  %s\033[0m\n\n' "$1"
    plain '  Nothing was changed. Tell Vimigo support what this said.'
    plain ''
    exit 1
}

printf '\n'
teal '  Vimigo - AI Personal Assistant'
plain ''

[ "$(uname -s)" = 'Darwin' ] || stop 'This is the Mac version, and this is not a Mac.'

[ -d "$DESKTOP" ] || DESKTOP="$HOME"
TARGET="$DESKTOP/$FOLDER"
SETUP="$TARGET/Vimigo files/vimigo-setup.sh"

# Reuse the folder the main setup left, when it is there. Downloading a second
# copy would leave two on the Desktop and the owner guessing which is current.
if [ -f "$SETUP" ]; then
    plain '  Using the setup already on your Desktop.'
else
    WORK="$(mktemp -d 2>/dev/null || mktemp -d -t vimigo)" || stop 'Could not make a temporary folder.'
    trap 'rm -rf "$WORK"' EXIT

    plain '  Downloading. This takes a moment.'
    curl -fsSL --retry 2 --connect-timeout 30 -o "$WORK/setup.zip" "$RELEASE" \
        || stop 'Could not download it. Check the wifi and try again.'

    plain '  Unpacking...'
    ditto -x -k "$WORK/setup.zip" "$WORK/out" 2>/dev/null \
        || unzip -q "$WORK/setup.zip" -d "$WORK/out" \
        || stop 'The download did not unpack. Try again in a moment.'

    INNER="$(find "$WORK/out" -maxdepth 2 -type d -name 'Vimigo files' -print 2>/dev/null | head -1)"
    [ -n "$INNER" ] || stop 'That download did not contain the setup.'

    if [ -e "$TARGET" ]; then
        n=1
        while [ -e "$TARGET (old $n)" ]; do n=$((n + 1)); done
        mv "$TARGET" "$TARGET (old $n)" || stop 'Could not move the old copy out of the way.'
    fi
    mv "$(dirname "$INNER")" "$TARGET" || stop 'Could not put the folder on your Desktop.'
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
fi

[ -f "$SETUP" ] || stop 'The setup file is missing.'
chmod +x "$SETUP" 2>/dev/null || true

plain ''
plain '  Setting up your assistant...'
plain ''
sleep 1

# < /dev/tty is load-bearing: this script arrived through a pipe, so without
# reattaching the keyboard every question would swallow the rest of this file
# instead of waiting for an answer.
exec bash "$SETUP" --assistant < /dev/tty
