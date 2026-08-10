#!/bin/bash
#
# Vimigo Company OS Setup - the one-line way in, for a Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-mac.sh | bash
#
# Why this exists.
#
# macOS refuses to open anything downloaded from a browser until the owner
# allows it once, and since macOS Sequoia the old "right-click, then Open"
# route is gone: the warning offers only "Done" and "Move to Trash", and Move
# to Trash is the blue button. The way through is four clicks buried in System
# Settings, and most of the people this is built for never find it. Some delete
# the setup instead, because the blue button looks like the answer.
#
# A script piped into bash was never a file on disk, so none of that applies.
# The folder this leaves on the Desktop is marked as trusted on the way past,
# which means double-clicking works normally from then on too.
#
# It downloads the same zip as the download page, from the same place.

set -u

RELEASE='https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/latest/download/vimigo-company-os-setup-mac.zip'
DESKTOP="$HOME/Desktop"
FOLDER='Vimigo AI Setup'

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
teal()  { printf '\033[36m%s\033[0m\n' "$1"; }
plain() { printf '%s\n' "$1"; }

stop() {
    printf '\n'
    red "  $1"
    plain ''
    plain '  Nothing was changed. Tell Vimigo support what this said.'
    plain ''
    exit 1
}

printf '\n'
teal '  Vimigo Company OS Setup'
plain ''

[ "$(uname -s)" = 'Darwin' ] || stop 'This is the Mac version, and this is not a Mac.'

# The Desktop is where the download page tells people to put it, so this puts
# it in the same place. A missing Desktop means a localised or relocated home
# folder; the home folder itself is the honest fallback.
[ -d "$DESKTOP" ] || DESKTOP="$HOME"
TARGET="$DESKTOP/$FOLDER"

# An earlier copy is moved aside rather than written over. Somebody may have
# put their own notes in there, and a setup that silently eats a folder on the
# Desktop is not one to trust with anything else.
if [ -e "$TARGET" ]; then
    n=1
    while [ -e "$TARGET (old $n)" ]; do n=$((n + 1)); done
    mv "$TARGET" "$TARGET (old $n)" || stop 'Could not move the old copy out of the way.'
    plain "  Your earlier copy is now called \"$FOLDER (old $n)\"."
fi

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t vimigo)" || stop 'Could not make a temporary folder.'
trap 'rm -rf "$WORK"' EXIT

plain '  Downloading. This is about 150KB and takes a moment.'
curl -fsSL --retry 2 --connect-timeout 30 -o "$WORK/setup.zip" "$RELEASE" \
    || stop 'Could not download it. Check the wifi and try again.'

# ditto, not unzip: it ships with macOS, understands the archive format Apple
# produces, and keeps the executable bit on the launcher.
plain '  Unpacking...'
ditto -x -k "$WORK/setup.zip" "$WORK/out" 2>/dev/null \
    || unzip -q "$WORK/setup.zip" -d "$WORK/out" \
    || stop 'The download did not unpack. Try again in a moment.'

# The zip holds one folder. Find it rather than assume its name, so renaming
# the release does not break this.
INNER="$(find "$WORK/out" -maxdepth 2 -type d -name 'Vimigo files' -print 2>/dev/null | head -1)"
[ -n "$INNER" ] || stop 'That download did not contain the setup.'
SOURCE="$(dirname "$INNER")"

mv "$SOURCE" "$TARGET" || stop 'Could not put the folder on your Desktop.'

# The part this whole script exists for. Nothing here came through a browser,
# so there is usually nothing to clear - but ditto can carry the flag across
# from the archive, and one flagged file is enough to bring the warning back.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
chmod +x "$TARGET/Setup-Mac.command" 2>/dev/null || true

SETUP="$TARGET/Vimigo files/vimigo-setup.sh"
[ -f "$SETUP" ] || stop 'The setup file is missing from the download.'
chmod +x "$SETUP" 2>/dev/null || true

plain ''
teal "  Ready. The folder is on your Desktop, called \"$FOLDER\"."
plain '  From now on you can just double-click Setup-Mac.command in it.'
plain ''
plain '  Starting the setup now...'
plain ''
sleep 1

# < /dev/tty is load-bearing.
#
# This script arrived through a pipe, so bash's own input is the rest of the
# script text. Without reattaching the keyboard, the first question the setup
# asks would silently swallow whatever bytes of this file were left instead of
# waiting for an answer - and the owner would watch it race past every prompt.
exec bash "$SETUP" < /dev/tty
