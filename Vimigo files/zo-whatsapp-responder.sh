#!/usr/bin/env bash
#
# Turns a paired WhatsApp number into one that actually answers.
#
# Pairing alone only makes the bridge sync messages into a database. This wires
# the bridge's webhook to a small responder, which asks Zo - the same engine
# behind the web chat - and sends the answer back.
#
# One responder per number. Its port is the bridge's port plus 1000, so the
# first number answers on 9080, the next on 9081, matching 8080 and 8081.
#
# Install to /home/workspace/Services/vimigo-setup/ on the customer's Zo.
#
# Usage:
#   ./zo-whatsapp-responder.sh install main --owner 60123456789
#   ./zo-whatsapp-responder.sh install sales --name Zoe --brief "You handle sales enquiries..."
#   ./zo-whatsapp-responder.sh status main
#   ./zo-whatsapp-responder.sh test main
#   ./zo-whatsapp-responder.sh remove sales

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=/home/workspace/Services/whatsapp-mcp-go
INSTANCES=/home/workspace/Services/whatsapp-instances
LEGACY_DIR="$REPO/whatsapp-bridge"
LEGACY_PORT=8080
LEGACY_NAME=main

say()  { printf '  %s\n' "$1"; }
good() { printf '  \033[32m%s\033[0m\n' "$1"; }
warn() { printf '  \033[33m%s\033[0m\n' "$1"; }
bad()  { printf '  \033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[36m%s\033[0m\n' "$1"; }

instance_dir() {
    if [ "$1" = "$LEGACY_NAME" ]; then printf '%s' "$LEGACY_DIR"; else printf '%s/%s' "$INSTANCES" "$1"; fi
}

instance_port() {
    if [ "$1" = "$LEGACY_NAME" ]; then printf '%s' "$LEGACY_PORT"; return 0; fi
    local file; file="$(instance_dir "$1")/PORT"
    [ -f "$file" ] && cat "$file"
}

responder_port() {
    local port; port="$(instance_port "$1")"
    [ -n "$port" ] || return 1
    printf '%s' "$((port + 1000))"
}

responder_dir() { printf '%s/responders/%s' "$HERE" "$1"; }

# Stops a responder and waits for its port to actually come free. Starting the
# replacement while the old one still holds the port is how a settings change
# ends up not being applied.
stop_responder() {
    local rdir rport pid
    rdir="$(responder_dir "$1")"
    rport="$(responder_port "$1")" || return 0
    pid="$(cat "$rdir/responder.pid" 2>/dev/null)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        local waited=0
        while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
            sleep 1; waited=$((waited + 1))
        done
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$rdir/responder.pid"

    # Belt and braces, for processes left by an older build with no pid file.
    #
    # Two ways, because neither is guaranteed. This Zo has no `ss` at all, and
    # the first attempt at this used it - so the fallback did nothing, silently,
    # which is precisely the failure it existed to prevent.
    #
    # Working directory is what tells two instances apart: they all run the
    # same script, and only run.sh's cd distinguishes them.
    local stale
    for stale in $(pgrep -f 'zo-whatsapp-responder\.py' 2>/dev/null); do
        [ "$(readlink -f "/proc/$stale/cwd" 2>/dev/null)" = "$(readlink -f "$rdir" 2>/dev/null)" ] || continue
        kill "$stale" 2>/dev/null; sleep 2; kill -9 "$stale" 2>/dev/null
    done

    # And whatever still holds the port, whichever build left it there.
    if command -v fuser >/dev/null 2>&1; then
        fuser -k -TERM "$rport/tcp" >/dev/null 2>&1
        sleep 2
        fuser -k -KILL "$rport/tcp" >/dev/null 2>&1
    fi

    # The port has to be free before the replacement is started, or it dies on
    # bind and the old settings stay in force.
    local waited=0
    while curl -s --max-time 2 "http://127.0.0.1:$rport/" >/dev/null 2>&1 && [ "$waited" -lt 10 ]; do
        sleep 1; waited=$((waited + 1))
    done
    return 0
}

env_value() {
    # Reads one KEY=value out of an env file without sourcing it, so a stray
    # character in a secret cannot become a shell command.
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-
}

# Adds or replaces one setting in an env file, leaving everything else alone.
set_env_value() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    if [ -f "$file" ]; then grep -v "^$key=" "$file" > "$tmp" 2>/dev/null; fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------

cmd_install() {
    local name="${1:-$LEGACY_NAME}"; shift || true
    local assistant_name='' brief='' owners='' groups=false hook=true personal=false self_chat=false enabled=false no_start=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)   assistant_name="${2:-}"; shift 2 ;;
            --brief)  brief="${2:-}"; shift 2 ;;
            --owner)  owners="${2:-}"; shift 2 ;;
            --groups) groups=true; shift ;;
            # The owner's own assistant. Answers only the numbers given, and
            # refuses to run without at least one - the assistant that can
            # read the owner's mail and calendar is the last thing that should
            # take instructions from whoever finds the number.
            --pa)     personal=true; shift ;;
            # Answers the owner's own "message yourself" chat, so someone with
            # a single number can try this before buying a second SIM.
            --self)   self_chat=true; shift ;;
            # Actually answer people. Deliberately not the default: an employee
            # the setup just created knows its job title and nothing about the
            # business, and a customer believes whatever it tells them. The
            # owner turns it on once they have taught it the job.
            --enable) enabled=true; shift ;;
            # Write everything, start nothing. Whoever registers this as a Zo
            # service starts it, and two copies fight over the port - the
            # second dies on bind and the settings just written are not the
            # ones in force.
            --no-start) no_start=true; shift ;;
            # Sets everything up but leaves the number not yet pointed at it.
            # For proving the responder works before letting it loose on a
            # number that real people already message.
            --no-hook) hook=false; shift ;;
            *) bad "Unknown option: $1"; return 1 ;;
        esac
    done

    if [ "$personal" = true ] && [ -z "$(printf '%s' "$owners" | tr -cd '0-9')" ]; then
        bad 'A personal assistant needs the list of numbers allowed to talk to it.'
        say 'Pass at least one with --owner 60123456789,60129876543'
        return 1
    fi

    # The owner's own assistant is the one channel that has to work when the
    # setup finishes - it is where they type. Everything else stays silent
    # until somebody says otherwise.
    [ "$personal" = true ] && enabled=true

    local dir port rport
    dir="$(instance_dir "$name")"
    [ -d "$dir" ] || { bad "There is no WhatsApp number called '$name'."; return 1; }
    port="$(instance_port "$name")"
    rport="$(responder_port "$name")" || { bad 'No port assigned to that number.'; return 1; }

    local key; key="$(env_value "$dir/.env" WHATSAPP_API_KEY)"
    [ -n "$key" ] || { bad "Could not read '$name' settings."; return 1; }

    step "Making '$name' answer"

    local rdir; rdir="$(responder_dir "$name")"
    mkdir -p "$rdir/state" "$rdir/logs"

    # Its own settings file, readable only by this account: it holds the key
    # that can send messages as this number.
    # Every value single quoted.
    #
    # run.sh sources this file, so an unquoted value is shell. A job
    # description of "Handle sales enquiries." ran `sales` as a command and
    # took the whole responder down with it - and a description containing
    # $(...) would have run that instead. Quoted, nothing inside is code.
    quoted() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

    umask 077
    {
        printf 'BRIDGE_URL=%s\n'        "$(quoted "http://127.0.0.1:$port")"
        printf 'BRIDGE_API_KEY=%s\n'    "$(quoted "$key")"
        printf 'LISTEN_PORT=%s\n'       "$(quoted "$rport")"
        printf 'STATE_DIR=%s\n'         "$(quoted "$rdir/state")"
        printf 'ASSISTANT_NAME=%s\n'    "$(quoted "$assistant_name")"
        printf 'ASSISTANT_BRIEF=%s\n'   "$(quoted "$brief")"
        printf 'OWNER_NUMBERS=%s\n'     "$(quoted "$owners")"
        printf 'ALLOW_GROUPS=%s\n'      "$(quoted "$groups")"
        printf 'REQUIRE_ALLOWLIST=%s\n' "$(quoted "$personal")"
        printf 'ANSWER_SELF_CHAT=%s\n'  "$(quoted "$self_chat")"
        printf 'ENABLED=%s\n'           "$(quoted "$enabled")"
    } > "$rdir/.env"
    chmod 600 "$rdir/.env"

    # Its own pid file, written by the wrapper before it hands over.
    #
    # The obvious "pkill -f run.sh" does not work here and failed silently,
    # which is the worst way for it to fail: run.sh ends in exec, so the
    # running process is python and its command line has no mention of run.sh.
    # Nothing was ever killed, the old process kept the port, the new one died
    # with "address already in use" - and because the health check found the
    # OLD one still answering, the install reported success. An allowlist
    # tightened at that moment was quietly never applied.
    # Redirected inside run.sh, not by the launcher: started by hand the output
    # went to the log, started by Zo as a service it went to Zo's own logs, and
    # everything that checks on this reads the file.
    cat > "$rdir/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$rdir"
set -a; . ./.env; set +a
echo \$\$ > "$rdir/responder.pid"
exec python3 "$HERE/zo-whatsapp-responder.py" >> "$rdir/logs/responder.log" 2>&1
EOF
    chmod +x "$rdir/run.sh"

    stop_responder "$name"

    if [ "$no_start" = true ]; then
        good "Ready. Zo will start it."
        # The webhook still has to be pointed at it, which is the part that
        # survives a restart and is not this script's to skip.
        local current_hook; current_hook="$(env_value "$dir/.env" WEBHOOK_URL)"
        if [ "$hook" = true ] && [ "$current_hook" != "http://127.0.0.1:$rport/" ]; then
            set_env_value "$dir/.env" WEBHOOK_URL "http://127.0.0.1:$rport/"
            say 'Pointed the number at it.'
        fi
        return 0
    fi

    nohup "$rdir/run.sh" >> "$rdir/logs/responder.log" 2>&1 &

    # Given time to come up rather than checked once. Freeing the port can take
    # a moment, and a single check three seconds in reported a perfectly good
    # responder as failed.
    local live='' waited=0
    while [ -z "$live" ] && [ "$waited" -lt 20 ]; do
        sleep 1; waited=$((waited + 1))
        live="$(curl -s --max-time 3 "http://127.0.0.1:$rport/" 2>/dev/null |
            grep -oE '"pid":[[:space:]]*[0-9]+' | tr -cd '0-9')"
    done

    # Confirmed to be THIS process, not whatever was there before. Comparing
    # the pid is the only thing that tells the difference, and the difference
    # is whether the settings just written are the ones in force. run.sh ends
    # in exec, so the shell's pid is the one Python keeps.
    local started; started="$(cat "$rdir/responder.pid" 2>/dev/null)"

    if [ -z "$live" ]; then
        bad 'The responder did not start. Recent log:'
        tail -10 "$rdir/logs/responder.log" 2>/dev/null | sed -E 's/[A-Fa-f0-9]{32,}/<redacted>/g' | sed 's/^/    /'
        return 1
    fi
    if [ "$live" != "$started" ]; then
        bad 'Something else is already using that port, so the new settings are not live.'
        say "Stop whatever is on port $rport and run this again."
        return 1
    fi
    good "Responder running on port $rport."

    # Point the bridge at it. This is the piece that was missing entirely:
    # without WEBHOOK_URL the bridge stores incoming messages and tells nobody.
    if [ "$hook" != true ]; then
        warn "'$name' is NOT pointed at it yet, as asked."
        say "Prove it first with:  $0 test $name <your phone number>"
        say "Then run this again without --no-hook."
        return 0
    fi

    local current; current="$(env_value "$dir/.env" WEBHOOK_URL)"
    if [ "$current" = "http://127.0.0.1:$rport/" ]; then
        say 'The number was already pointed at it.'
    else
        set_env_value "$dir/.env" WEBHOOK_URL "http://127.0.0.1:$rport/"
        say 'Restarting the number so it picks that up...'
        if [ "$name" = "$LEGACY_NAME" ]; then
            pkill -f "$REPO/run-bridge.sh" 2>/dev/null
            pkill -x whatsapp-bridge 2>/dev/null
        else
            pkill -f "$dir/run.sh" 2>/dev/null
        fi
        # Zo restarts a registered service within a couple of seconds. An
        # unregistered one has to be started here.
        sleep 12
        if ! curl -s --max-time 5 "http://127.0.0.1:$port/" >/dev/null 2>&1; then
            if [ "$name" != "$LEGACY_NAME" ]; then
                nohup "$dir/run.sh" >> "$dir/logs/bridge.log" 2>&1 &
                sleep 8
            fi
        fi
    fi

    cmd_status "$name"
    say ''
    say "Register the responder as a Zo service so it stays running, with:"
    say "  label      whatsapp-responder-$name"
    say "  entrypoint $rdir/run.sh"
    say "  workdir    $rdir"
}

cmd_status() {
    local name="${1:-$LEGACY_NAME}"
    local dir port rport
    dir="$(instance_dir "$name")"
    port="$(instance_port "$name")"
    rport="$(responder_port "$name")" || { bad 'Unknown number.'; return 1; }

    local hooked responder
    hooked="$(env_value "$dir/.env" WEBHOOK_URL)"
    responder="$(curl -s --max-time 5 "http://127.0.0.1:$rport/" 2>/dev/null)"

    # Three separate things, and all three have to be true. Running is not
    # answering, and pointed at is not switched on - conflating any of them is
    # how a silent assistant gets reported as working.
    if [ -z "$responder" ]; then
        warn "The reply service for '$name' is not running."
        return 1
    fi
    if [ "$hooked" != "http://127.0.0.1:$rport/" ]; then
        warn "'$name' is not pointed at its reply service yet."
        return 1
    fi
    case "$responder" in
        *'"enabled": true'*|*'"enabled":true'*) ;;
        *)
            warn "'$name' is set up but not switched on, so it answers nobody."
            return 1 ;;
    esac

    good "'$name' is answering."
    return 0
}

# Proves the whole path end to end without needing a second phone: asks the
# responder to answer a message that looks exactly like a real one.
cmd_test() {
    local name="${1:-$LEGACY_NAME}" rport
    rport="$(responder_port "$name")" || { bad 'Unknown number.'; return 1; }

    local to="${2:-}"
    [ -n "$to" ] || { bad 'Give a phone number to send the test answer to.'; return 1; }
    local digits; digits="$(printf '%s' "$to" | tr -cd '0-9')"

    step "Testing '$name'"
    curl -s --max-time 10 -X POST "http://127.0.0.1:$rport/" \
        -H 'Content-Type: application/json' \
        -d "{\"chat_jid\":\"${digits}@s.whatsapp.net\",\"sender\":\"${digits}\",\"is_from_me\":false,\"is_group\":false,\"message_type\":\"text\",\"message_id\":\"vimigo-test-$(date +%s)\",\"push_name\":\"Test\",\"content\":\"Say hello in one short sentence.\"}" \
        >/dev/null
    say 'Sent. The answer should arrive on that number within a minute.'
}

cmd_logs() {
    local name="${1:-$LEGACY_NAME}"
    tail -30 "$(responder_dir "$name")/logs/responder.log" 2>/dev/null |
        sed -E 's/[A-Fa-f0-9]{32,}/<redacted>/g'
}

cmd_remove() {
    local name="${1:-}"
    [ -n "$name" ] || { bad 'Which number?'; return 1; }
    local dir rdir rport
    dir="$(instance_dir "$name")"
    rdir="$(responder_dir "$name")"
    rport="$(responder_port "$name")"

    step "Stopping the responder for '$name'"
    pkill -f "$rdir/run.sh" 2>/dev/null
    # The webhook goes first, so the bridge stops posting to a dead port.
    if [ -f "$dir/.env" ]; then
        local tmp; tmp="$(mktemp)"
        grep -v '^WEBHOOK_URL=' "$dir/.env" > "$tmp" 2>/dev/null
        cat "$tmp" > "$dir/.env"; rm -f "$tmp"
    fi
    good "'$name' will stop answering. Its conversations are kept in $rdir/state."
}

case "${1:-status}" in
    install) shift; cmd_install "$@" ;;
    status)  cmd_status "${2:-$LEGACY_NAME}" ;;
    test)    cmd_test "${2:-$LEGACY_NAME}" "${3:-}" ;;
    logs)    cmd_logs "${2:-$LEGACY_NAME}" ;;
    remove)  cmd_remove "${2:-}" ;;
    *) say 'Use: install <number> [--name X] [--brief "..."] [--owner 60...] | status | test <number> <phone> | logs | remove' ; exit 2 ;;
esac
