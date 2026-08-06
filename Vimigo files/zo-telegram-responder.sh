#!/usr/bin/env bash
#
# Gives one AI employee its own Telegram, and keeps it running.
#
# Zo's own Telegram connects the OWNER'S account, so an employee sitting on it
# would answer as the boss. Each employee gets its own bot instead - made by
# the owner in Telegram in about five taps - and one of these runs per bot.
#
# A bot needs no SIM card. That is why this exists: five employees can have
# five identities without buying a single phone number.
#
# Install to /home/workspace/Services/vimigo-setup/ on the customer's Zo.
#
# Usage:
#   ./zo-telegram-responder.sh install john --token 123:ABC --brief "You handle sales."
#   ./zo-telegram-responder.sh status john
#   ./zo-telegram-responder.sh enable john
#   ./zo-telegram-responder.sh logs john
#   ./zo-telegram-responder.sh remove john

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMPLOYEES="$HERE/telegram"

say()  { printf '  %s\n' "$1"; }
good() { printf '  \033[32m%s\033[0m\n' "$1"; }
warn() { printf '  \033[33m%s\033[0m\n' "$1"; }
bad()  { printf '  \033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[36m%s\033[0m\n' "$1"; }

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

employee_dir() { printf '%s/%s' "$EMPLOYEES" "$1"; }

env_value() {
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- | sed "s/^'//; s/'$//"
}

# Stops one employee's bot and waits for it to actually go.
#
# By pid file, because run.sh ends in exec: the running process is python and
# its command line never mentions run.sh, so pkill -f matches nothing. That
# exact mistake let an old process keep running with old settings while the
# installer reported success.
stop_employee() {
    local dir pid
    dir="$(employee_dir "$1")"
    pid="$(cat "$dir/responder.pid" 2>/dev/null)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        local waited=0
        while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
            sleep 1; waited=$((waited + 1))
        done
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$dir/responder.pid"

    # Belt and braces for anything left by an older build, matched on working
    # directory because every employee runs the same script.
    local stale
    for stale in $(pgrep -f 'zo-telegram-responder\.py' 2>/dev/null); do
        [ "$(readlink -f "/proc/$stale/cwd" 2>/dev/null)" = "$(readlink -f "$dir" 2>/dev/null)" ] || continue
        kill "$stale" 2>/dev/null; sleep 2; kill -9 "$stale" 2>/dev/null
    done
    return 0
}

cmd_install() {
    local raw="${1:-}"; shift || true
    local token='' brief='' name='' enabled=false code='' no_start=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --token)   token="${2:-}"; shift 2 ;;
            --brief)   brief="${2:-}"; shift 2 ;;
            --name)    name="${2:-}"; shift 2 ;;
            --code)    code="${2:-}"; shift 2 ;;
            # Answer everyone. Deliberately not the default: a new employee
            # knows a job title and nothing about the business, and a customer
            # believes whatever it tells them.
            --enable)  enabled=true; shift ;;
            # Write everything, start nothing. Whoever registers this as a Zo
            # service will start it, and two copies polling one bot is a 409
            # for both - Telegram allows exactly one reader.
            --no-start) no_start=true; shift ;;
            *) bad "Unknown option: $1"; return 1 ;;
        esac
    done

    local slug; slug="$(slugify "$raw")"
    [ -n "$slug" ] || { bad 'Give the employee a name.'; return 1; }
    [ -n "$token" ] || { bad 'A Telegram bot token is needed.'; return 1; }
    [ -n "$name" ] || name="$raw"

    # Checked before anything is written, so a mistyped token fails here rather
    # than as silence three screens later.
    local who; who="$(curl -s --max-time 20 "https://api.telegram.org/bot$token/getMe")"
    case "$who" in
        *'"ok":true'*) ;;
        *) bad 'Telegram did not accept that token.'; return 1 ;;
    esac
    local username; username="$(printf '%s' "$who" | grep -oE '"username":"[^"]+"' | head -1 | cut -d'"' -f4)"

    # A bot can only be read by one thing at a time.
    #
    # Reusing a bot that already has a webhook - an n8n flow, some other
    # automation - means Telegram refuses every read with a 409, forever. The
    # symptom is an employee that installs perfectly and then never hears
    # anything, which is indistinguishable from being broken.
    #
    # Deleting the webhook would fix this instantly and silently break whatever
    # was on the other end of it, so it is refused instead. A new bot is free
    # and takes a minute.
    local hook; hook="$(curl -s --max-time 20 "https://api.telegram.org/bot$token/getWebhookInfo")"
    local hook_url; hook_url="$(printf '%s' "$hook" | grep -oE '"url":"[^"]*"' | head -1 | cut -d'"' -f4)"
    if [ -n "$hook_url" ]; then
        bad 'VIMIGO_BOT_IN_USE'
        say "That bot (@$username) is already being used by something else."
        return 1
    fi

    # No webhook, but something else may still be polling it. Same outcome, so
    # it is worth the one extra second to find out now rather than later.
    local probe; probe="$(curl -s --max-time 20 "https://api.telegram.org/bot$token/getUpdates?timeout=0&limit=1")"
    case "$probe" in
        *'"error_code":409'*|*Conflict*)
            bad 'VIMIGO_BOT_IN_USE'
            say "That bot (@$username) is already being used by something else."
            return 1 ;;
    esac

    step "Setting up $name on Telegram"

    local dir; dir="$(employee_dir "$slug")"
    mkdir -p "$dir/state" "$dir/logs"

    # 16 bytes, not 4.
    #
    # This word is what decides who owns the employee, and the owner of an
    # employee can tell it anything - it answers through Zo, which reaches
    # their mail, files and calendar. Whoever says it first is believed, so it
    # has to be unguessable rather than merely unlikely. Four bytes is 32 bits;
    # this is 128, and costs nothing.
    [ -n "$code" ] || code="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"

    # Every value single quoted: run.sh sources this file, so an unquoted job
    # description would be run as shell.
    quoted() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

    umask 077
    {
        printf 'BOT_TOKEN=%s\n'       "$(quoted "$token")"
        printf 'STATE_DIR=%s\n'       "$(quoted "$dir/state")"
        printf 'ASSISTANT_NAME=%s\n'  "$(quoted "$name")"
        printf 'ASSISTANT_BRIEF=%s\n' "$(quoted "$brief")"
        printf 'ENABLED=%s\n'         "$(quoted "$enabled")"
        printf 'PAIR_CODE=%s\n'       "$(quoted "$code")"
    } > "$dir/.env"
    chmod 600 "$dir/.env"
    printf '%s' "$username" > "$dir/USERNAME"

    # Redirected here, inside run.sh, rather than by whoever launches it.
    #
    # Started by hand its output went to the log; started by Zo as a service it
    # went to Zo's own logs instead, so the file stayed frozen at whatever the
    # last manual run wrote. Everything that checks on this employee reads that
    # file - including the setup, which waits for it to say the bot is
    # listening - so under Zo it waited for a line that was never going to
    # arrive.
    cat > "$dir/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$dir"
set -a; . ./.env; set +a
echo \$\$ > "$dir/responder.pid"
exec python3 "$HERE/zo-telegram-responder.py" >> "$dir/logs/responder.log" 2>&1
EOF
    chmod +x "$dir/run.sh"

    stop_employee "$slug"

    if [ "$no_start" = true ]; then
        good "$name is ready on Telegram as @$username"
        printf '  PAIRCODE %s\n' "$code"
        printf '  USERNAME %s\n' "$username"
        return 0
    fi

    nohup "$dir/run.sh" >> "$dir/logs/responder.log" 2>&1 &

    # Given time to come up and checked for what it actually did, rather than
    # assumed from the command having been sent.
    local waited=0 started=''
    while [ -z "$started" ] && [ "$waited" -lt 20 ]; do
        sleep 1; waited=$((waited + 1))
        grep -q 'answering as @' "$dir/logs/responder.log" 2>/dev/null && started=yes
        grep -q 'did not accept this bot token' "$dir/logs/responder.log" 2>/dev/null && {
            bad 'Telegram did not accept that token.'; return 1; }
    done

    if [ -z "$started" ]; then
        bad "$name could not be started. Recent log:"
        tail -8 "$dir/logs/responder.log" 2>/dev/null |
            sed -E 's/[0-9]{6,}:[A-Za-z0-9_-]{30,}/<token hidden>/g' | sed 's/^/    /'
        return 1
    fi

    good "$name is live on Telegram as @$username"
    printf '  PAIRCODE %s\n' "$code"
    printf '  USERNAME %s\n' "$username"
    say ''
    say "Register as a Zo service so it stays running, with:"
    say "  label      telegram-$slug"
    say "  entrypoint $dir/run.sh"
    say "  workdir    $dir"
    return 0
}

cmd_status() {
    local slug; slug="$(slugify "${1:-}")"
    local dir; dir="$(employee_dir "$slug")"
    [ -d "$dir" ] || { bad 'No such employee.'; return 1; }

    local pid; pid="$(cat "$dir/responder.pid" 2>/dev/null)"
    local username; username="$(cat "$dir/USERNAME" 2>/dev/null)"
    local enabled; enabled="$(env_value "$dir/.env" ENABLED)"
    local owner; owner="$(grep -oE '"owner": ?"[^"]+"' "$dir/state/telegram.json" 2>/dev/null | head -1)"

    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        warn "$slug is not running."
        return 1
    fi
    printf '  USERNAME %s\n' "$username"
    if [ "$enabled" = "true" ]; then
        good "$slug is answering everyone as @$username"
    elif [ -n "$owner" ]; then
        good "$slug is answering you only, as @$username"
    else
        warn "$slug is waiting for you to say hello, as @$username"
    fi
    return 0
}

cmd_enable() {
    local slug; slug="$(slugify "${1:-}")"
    local dir; dir="$(employee_dir "$slug")"
    [ -f "$dir/.env" ] || { bad 'No such employee.'; return 1; }

    local tmp; tmp="$(mktemp)"
    grep -v '^ENABLED=' "$dir/.env" > "$tmp"
    printf "ENABLED='true'\n" >> "$tmp"
    cat "$tmp" > "$dir/.env"; rm -f "$tmp"
    chmod 600 "$dir/.env"

    # Read once at startup, so it has to be restarted for this to mean anything.
    stop_employee "$slug"
    nohup "$dir/run.sh" >> "$dir/logs/responder.log" 2>&1 &
    sleep 4
    cmd_status "$slug"
}

cmd_logs() {
    local slug; slug="$(slugify "${1:-}")"
    tail -30 "$(employee_dir "$slug")/logs/responder.log" 2>/dev/null |
        sed -E 's/[0-9]{6,}:[A-Za-z0-9_-]{30,}/<token hidden>/g'
}

cmd_remove() {
    local slug; slug="$(slugify "${1:-}")"
    local dir; dir="$(employee_dir "$slug")"
    [ -d "$dir" ] || { bad 'No such employee.'; return 1; }
    stop_employee "$slug"
    mkdir -p "$EMPLOYEES/.removed"
    mv "$dir" "$EMPLOYEES/.removed/$slug.$(date -u +%Y%m%dT%H%M%SZ)"
    good "$slug has stopped answering on Telegram."
}

cmd_list() {
    [ -d "$EMPLOYEES" ] || { say 'None yet.'; return 0; }
    local dir
    for dir in "$EMPLOYEES"/*/; do
        [ -d "$dir" ] || continue
        cmd_status "$(basename "$dir")" || true
    done
}

case "${1:-list}" in
    install) shift; cmd_install "$@" ;;
    status)  cmd_status "${2:-}" ;;
    enable)  cmd_enable "${2:-}" ;;
    logs)    cmd_logs "${2:-}" ;;
    remove)  cmd_remove "${2:-}" ;;
    list)    cmd_list ;;
    *) say 'Use: install <name> --token <t> [--brief "..."] [--enable] | status | enable | logs | remove | list'; exit 2 ;;
esac
