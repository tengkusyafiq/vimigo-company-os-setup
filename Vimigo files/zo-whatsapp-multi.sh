#!/usr/bin/env bash
#
# Runs more than one WhatsApp number on a customer's Zo.
#
# One bridge holds one linked device: a second pair attempt against the same
# bridge is refused with "already paired". So each number gets its own bridge -
# its own store, its own port, its own secrets, its own Zo service - built from
# the one shared checkout.
#
# Each is named by the owner, because "which number is 60123456789 again" is a
# question nobody should have to answer six months later. The name becomes the
# instance id, the Zo service label, and the MCP entry name, so the same word
# follows it everywhere.
#
# Install to /home/workspace/Services/vimigo-setup/ on the customer's Zo.
#
# Usage:
#   ./zo-whatsapp-multi.sh list
#   ./zo-whatsapp-multi.sh add sales 60123456789
#   ./zo-whatsapp-multi.sh status sales
#   ./zo-whatsapp-multi.sh pair sales 60123456789
#   ./zo-whatsapp-multi.sh remove sales

set -uo pipefail

REPO=/home/workspace/Services/whatsapp-mcp-go
INSTANCES=/home/workspace/Services/whatsapp-instances

# The bridge that existed before any of this. It keeps its original home and
# port so that moving to multiple numbers never disturbs a working one.
LEGACY_DIR="$REPO/whatsapp-bridge"
LEGACY_PORT=8080
LEGACY_NAME=main

FIRST_PORT=8081

say()  { printf '  %s\n' "$1"; }
good() { printf '  \033[32m%s\033[0m\n' "$1"; }
warn() { printf '  \033[33m%s\033[0m\n' "$1"; }
bad()  { printf '  \033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[36m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# Instances
# ---------------------------------------------------------------------------

slugify() {
    # Lower case, letters digits and dashes only. The result is used as a
    # directory name, a service label and an MCP entry name, so it has to be
    # safe in all three.
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

instance_dir() {
    if [ "$1" = "$LEGACY_NAME" ]; then printf '%s' "$LEGACY_DIR"; else printf '%s/%s' "$INSTANCES" "$1"; fi
}

instance_port() {
    if [ "$1" = "$LEGACY_NAME" ]; then printf '%s' "$LEGACY_PORT"; return 0; fi
    local file; file="$(instance_dir "$1")/PORT"
    [ -f "$file" ] && cat "$file"
}

list_instances() {
    # The original first, then any added later, so the order is stable.
    [ -d "$LEGACY_DIR" ] && printf '%s\n' "$LEGACY_NAME"
    [ -d "$INSTANCES" ] || return 0
    local dir
    for dir in "$INSTANCES"/*/; do
        [ -d "$dir" ] || continue
        basename "$dir"
    done
}

next_free_port() {
    local port="$FIRST_PORT" taken
    while true; do
        taken=no
        for name in $(list_instances); do
            [ "$(instance_port "$name")" = "$port" ] && taken=yes
        done
        # Also skip anything already listening, which catches ports in use by
        # something outside this script entirely.
        if [ "$taken" = no ] && ! curl -s --max-time 2 "http://127.0.0.1:$port/" >/dev/null 2>&1; then
            printf '%s' "$port"; return 0
        fi
        port=$((port + 1))
        [ "$port" -gt 8120 ] && { bad 'No free port found.'; return 1; }
    done
}

bridge_token() {
    local dir port key
    dir="$(instance_dir "$1")"; port="$(instance_port "$1")"
    [ -n "$port" ] || return 1
    key="$(grep '^WHATSAPP_API_KEY=' "$dir/.env" 2>/dev/null | cut -d= -f2-)"
    [ -n "$key" ] || return 1
    curl -s --max-time 10 -X POST "http://127.0.0.1:$port/auth/login" \
        -H "Authorization: Bearer $key" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4
}

instance_status() {
    local port token
    port="$(instance_port "$1")"
    [ -n "$port" ] || { printf 'no port assigned'; return 1; }
    token="$(bridge_token "$1")"
    [ -n "$token" ] || { printf 'not running'; return 1; }
    curl -s --max-time 10 "http://127.0.0.1:$port/api/auth/status" \
        -H "Authorization: Bearer $token"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_list() {
    step 'WhatsApp numbers on this Zo'
    local any=no name port state label
    for name in $(list_instances); do
        any=yes
        port="$(instance_port "$name")"
        state="$(instance_status "$name")"
        label="$(cat "$(instance_dir "$name")/LABEL" 2>/dev/null || printf '%s' "$name")"
        case "$state" in
            *'"logged_in":true'*)      printf '  %-14s %-22s port %-6s connected\n' "$name" "$label" "$port" ;;
            *'"pairing_required":true'*) printf '  %-14s %-22s port %-6s waiting to be paired\n' "$name" "$label" "$port" ;;
            *)                          printf '  %-14s %-22s port %-6s %s\n' "$name" "$label" "$port" "${state:-unknown}" ;;
        esac
    done
    [ "$any" = yes ] || say 'None yet.'
}

cmd_add() {
    local raw="${1:-}" phone="${2:-}"
    [ -n "$raw" ] || { bad 'Give the number a name, for example: sales'; return 1; }

    local name; name="$(slugify "$raw")"
    [ -n "$name" ] || { bad 'That name has no letters or digits in it.'; return 1; }
    [ "$name" = "$LEGACY_NAME" ] && { bad "The name '$LEGACY_NAME' is taken by the first number."; return 1; }

    local dir; dir="$(instance_dir "$name")"
    [ -d "$dir" ] && { bad "There is already a number called '$name'."; return 1; }

    [ -x "$REPO/whatsapp-bridge/whatsapp-bridge" ] || {
        bad 'The WhatsApp bridge is not built yet. Run zo-whatsapp-setup.sh install first.'
        return 1
    }

    step "Adding WhatsApp number '$name'"

    local port; port="$(next_free_port)" || return 1
    say "Using port $port."

    mkdir -p "$dir/store" "$dir/logs"
    printf '%s' "$port" > "$dir/PORT"
    printf '%s' "$raw" > "$dir/LABEL"

    # Its own secrets. Sharing them between bridges would let one instance's
    # token authenticate against another, which is a poor way to keep two
    # businesses' messages apart.
    umask 077
    cat > "$dir/.env" <<EOF
WHATSAPP_API_KEY=$(openssl rand -hex 32)
WHATSAPP_JWT_SECRET=$(openssl rand -hex 32)
IS_POSTGRES=false
HOST=127.0.0.1
PORT=$port
LOG_LEVEL=info
BRIDGE_TZ=Asia/Kuala_Lumpur
EOF
    chmod 600 "$dir/.env"

    # The binary is shared from the one checkout; only the working directory
    # and environment differ, so each has its own store and port.
    cat > "$dir/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$dir"
set -a; . ./.env; set +a
exec "$REPO/whatsapp-bridge/whatsapp-bridge"
EOF
    chmod +x "$dir/run.sh"

    say 'Starting it...'
    nohup "$dir/run.sh" >> "$dir/logs/bridge.log" 2>&1 &
    sleep 8

    if [ -z "$(bridge_token "$name")" ]; then
        bad 'It did not start. Recent log:'
        tail -10 "$dir/logs/bridge.log" 2>/dev/null | sed -E 's/[A-Fa-f0-9]{64}/<redacted>/g' | sed 's/^/    /'
        return 1
    fi

    good "'$name' is running on port $port."
    # Machine-readable, for zo-verify.js. Everything else on this screen is for
    # a person reading a terminal; these two lines are the contract, so the
    # setup never has to parse an English sentence that might be reworded.
    printf 'VIMIGO_WA_PORT %s\n' "$port"
    printf 'VIMIGO_WA_READY %s\n' "$name"
    say ''
    say 'Register it as a Zo service so it stays running, with:'
    say "  label      whatsapp-$name"
    say "  entrypoint $dir/run.sh"
    say "  workdir    $dir"
    say ''

    [ -n "$phone" ] && cmd_pair "$name" "$phone"
    return 0
}

cmd_state() {
    # One line a machine can read: is this number's bridge up, and is a phone
    # linked to it? Used to poll while the owner types the code in.
    local name="${1:-}"
    [ -n "$name" ] || { printf 'VIMIGO_WA_STATE name= running=no paired=no\n'; return 1; }
    name="$(slugify "$name")"

    local port state running=no paired=no
    port="$(instance_port "$name")"
    if [ -n "$port" ]; then
        state="$(instance_status "$name" 2>/dev/null)"
        case "$state" in
            *'"logged_in":true'*) running=yes; paired=yes ;;
            *'"pairing_required":true'*) running=yes ;;
            '') ;;
            'not running'|'no port assigned') ;;
            *) running=yes ;;
        esac
    fi
    printf 'VIMIGO_WA_STATE name=%s port=%s running=%s paired=%s\n' \
        "$name" "${port:-}" "$running" "$paired"
}

wait_connected() {
    # $1 = name, $2 = seconds to wait. True once the bridge's websocket to
    # WhatsApp is actually up.
    #
    # Asking for a pairing code before it is up returns "websocket not
    # connected" and burns the attempt. Twelve seconds was the old guess and it
    # is not enough on a cold start.
    local name="$1" limit="${2:-60}" waited=0 port state
    port="$(instance_port "$name")"
    [ -n "$port" ] || return 1
    while [ "$waited" -lt "$limit" ]; do
        state="$(curl -s --max-time 6 "http://127.0.0.1:$port/api/auth/status" \
            -H "Authorization: Bearer $(bridge_token "$name")" 2>/dev/null)"
        case "$state" in
            *'"connected":true'*) return 0 ;;
            *'"logged_in":true'*) return 0 ;;
        esac
        sleep 4
        waited=$((waited + 4))
    done
    return 1
}

cmd_pair() {
    local name="${1:-}" phone="${2:-}"
    [ -n "$name" ] || { bad 'Which number? Use the name you gave it.'; return 1; }
    [ -d "$(instance_dir "$name")" ] || { bad "There is no number called '$name'."; return 1; }
    [ -n "$phone" ] || { bad 'Give the phone number, digits only, e.g. 60123456789'; return 1; }

    step "Pairing '$name' with $phone"

    local port token response
    port="$(instance_port "$name")"
    token="$(bridge_token "$name")"
    [ -n "$token" ] || { bad "'$name' is not running."; printf 'VIMIGO_WA_STALE %s\n' "$name"; return 1; }

    request_code() {
        curl -s --max-time 30 -X POST "http://127.0.0.1:$port/api/auth/pair-phone" \
            -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
            -d "{\"phone\":\"$2\"}"
    }

    wait_connected "$name" 12 || true
    response="$(request_code "$token" "$phone")"

    # No restart-and-retry here any more, and that is from evidence rather than
    # taste. A bridge left unpaired long enough answers "websocket not
    # connected" and does not come back: restarted, it reconnects the process
    # and never the socket - watched for sixty seconds, reporting
    # connected:false the whole way. The only thing that clears it is a fresh
    # instance.
    #
    # So this says so, quickly, and lets the caller rebuild. Spending a minute
    # first on a reconnection that has never once worked just makes the owner
    # wait longer for the same answer.
    case "$response" in
        *'"code"'*|*already*paired*) ;;
        *) printf 'VIMIGO_WA_STALE %s\n' "$name" ;;
    esac

    case "$response" in
        *already*paired*)
            good "'$name' is already linked to a phone."
            printf 'VIMIGO_WA_PAIRED %s\n' "$name"
            return 0 ;;
        *'"code"'*)
            good 'Pairing code:'
            local code
            code="$(printf '%s\n' "$response" | grep -oE '"code":"[^"]+"' | cut -d'"' -f4)"
            printf '%s\n' "$code" | sed 's/^/      /'
            printf 'VIMIGO_WA_CODE %s\n' "$code"
            say ''
            say 'On the phone: WhatsApp, Settings, Linked Devices, Link a device,'
            say 'Link with phone number instead, then type the code.'
            return 0 ;;
        *) bad 'Could not get a code.'; say "$response"; return 1 ;;
    esac
}

cmd_remove() {
    local name="${1:-}"
    [ -n "$name" ] || { bad 'Which number?'; return 1; }
    [ "$name" = "$LEGACY_NAME" ] && { bad "The first number cannot be removed here."; return 1; }
    local dir; dir="$(instance_dir "$name")"
    [ -d "$dir" ] || { bad "There is no number called '$name'."; return 1; }

    step "Removing '$name'"
    pkill -f "$dir/run.sh" 2>/dev/null
    sleep 2

    # Moved aside, never deleted. The store holds the linked WhatsApp session,
    # and if this turns out to be the wrong instance that session is gone for
    # good otherwise.
    local archive="$INSTANCES/.removed/$name.$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$(dirname "$archive")"
    mv "$dir" "$archive"
    good "Stopped and archived to $archive"
    say "Its Zo service, whatsapp-$name, still needs deleting by hand."
}

case "${1:-list}" in
    list)   cmd_list ;;
    add)    cmd_add "${2:-}" "${3:-}" ;;
    pair)   cmd_pair "${2:-}" "${3:-}" ;;
    status) if [ -n "${2:-}" ]; then instance_status "$2"; echo; else cmd_list; fi ;;
    state)  cmd_state "${2:-}" ;;
    remove) cmd_remove "${2:-}" ;;
    *) say 'Use: list | add <name> [phone] | pair <name> <phone> | status [name] | state <name> | remove <name>'; exit 2 ;;
esac
