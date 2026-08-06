#!/usr/bin/env bash
# Vimigo AI Setup - double-click this file in Finder.
#
# It only starts the setup menu. Nothing is installed until you choose it.
#
# If macOS refuses to open it, right-click the file and choose Open instead,
# then confirm. That is Gatekeeper asking permission for a downloaded script.

# Everything else lives in the folder beside this file, so the customer sees
# two things they might reasonably open rather than eighteen.
cd "$(dirname "$0")/Vimigo files" 2>/dev/null || {
    echo
    echo "  The \"Vimigo files\" folder is missing."
    echo
    echo "  This happens when only one file was copied out of the zip"
    echo "  instead of the whole folder. Copy the whole folder and try again."
    echo
    read -r -p "  Press Enter to close "
    exit 1
}
exec bash ./vimigo-setup.sh
