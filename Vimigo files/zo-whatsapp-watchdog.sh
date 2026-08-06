#!/usr/bin/env bash
#
# Watches the WhatsApp bridge and speaks only when something changes.
#
# Zo's own service manager already restarts a crashed bridge within a couple of
# seconds, so this is not the thing keeping it alive. Its job is the states a
# restart cannot fix - an unlinked phone, a bridge that is up but not talking to
# WhatsApp, or one that keeps dying - and telling the owner about them.
#
# Exit 0 means "nothing to say". Exit 1 means "tell the owner".
#
# It reports only on a CHANGE of state. An alert that repeats every fifteen
# minutes while nothing is happening trains the owner to ignore it, and then the
# one that matters gets ignored too. A state that has not changed is repeated at
# most once a day so a long-running problem is not forgotten entirely.
#
# Everything it prints is read by a business owner with no technical background.
# No paths, no commands, no logs beyond the unrecoverable case, and the fallback
# is "contact Vimigo support" rather than instructions to carry out.
#
# A paired WhatsApp session is never re-paired here. Losing the linked device is
# the owner's decision, not a repair step.
#
# Install to /home/workspace/Services/vimigo-setup/ on the customer's Zo.

set -uo pipefail

REPO=/home/workspace/Services/whatsapp-mcp-go
PORT=8080
STATE_FILE=/home/workspace/Services/vimigo-setup/.watchdog-state
REPEAT_AFTER_SECONDS=86400

bridge_running() { pgrep -x whatsapp-bridge >/dev/null 2>&1; }

bridge_status() {
    local key token
    key="$(grep '^WHATSAPP_API_KEY=' "$REPO/whatsapp-bridge/.env" 2>/dev/null | cut -d= -f2-)"
    [ -n "$key" ] || return 1
    token="$(curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/auth/login" \
        -H "Authorization: Bearer $key" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)"
    [ -n "$token" ] || return 1
    curl -s --max-time 10 "http://127.0.0.1:$PORT/api/auth/status" \
        -H "Authorization: Bearer $token"
}

# announce <state-key> <message...>
# Prints and exits 1 only when this differs from what was last reported, or
# enough time has passed to be worth repeating.
announce() {
    local state="$1"; shift
    local now last_state last_time age
    now="$(date +%s)"

    last_state=""; last_time=0
    if [ -f "$STATE_FILE" ]; then
        last_state="$(head -1 "$STATE_FILE" 2>/dev/null)"
        last_time="$(sed -n 2p "$STATE_FILE" 2>/dev/null)"
        case "$last_time" in ''|*[!0-9]*) last_time=0 ;; esac
    fi

    age=$(( now - last_time ))
    if [ "$state" = "$last_state" ] && [ "$age" -lt "$REPEAT_AFTER_SECONDS" ]; then
        exit 0
    fi

    printf '%s\n%s\n' "$state" "$now" > "$STATE_FILE"
    printf '%s\n' "$@"
    [ "$state" = "healthy" ] && exit 0
    exit 1
}

restarted=no
if ! bridge_running; then
    restarted=yes
    mkdir -p "$REPO/whatsapp-bridge/logs"
    nohup "$REPO/run-bridge.sh" >> "$REPO/whatsapp-bridge/logs/bridge.log" 2>&1 &
    sleep 10
fi

if ! bridge_running; then
    announce "down" \
        "Your WhatsApp assistant has stopped and will not start again." \
        "Please forward this message to Vimigo support." \
        "" \
        "$(tail -15 "$REPO/whatsapp-bridge/logs/bridge.log" 2>/dev/null | sed -E 's/[A-Fa-f0-9]{64}/<redacted>/g')"
fi

status="$(bridge_status)"
note=""
[ "$restarted" = yes ] && note="The bridge had stopped and was restarted. "

case "$status" in
    *'"logged_in":true'*)
        announce "healthy" "Your WhatsApp is connected again. Nothing for you to do."
        ;;
    *'"pairing_required":true'*)
        announce "unpaired" \
            "${note}Your WhatsApp is not connected to your assistant right now." \
            "" \
            "To reconnect it, open Vimigo Setup on your computer and choose" \
            "WhatsApp. It will show you a short code." \
            "" \
            "Then on your phone: open WhatsApp, tap Settings, tap Linked" \
            "Devices, tap Link a device, choose Link with phone number" \
            "instead, and type in the code."
        ;;
    *)
        announce "disconnected" \
            "${note}Your WhatsApp assistant is running but cannot reach WhatsApp." \
            "This is usually temporary. If it is still saying this tomorrow," \
            "please forward this message to Vimigo support." \
            "" \
            "${status:-The bridge did not answer at all.}"
        ;;
esac
