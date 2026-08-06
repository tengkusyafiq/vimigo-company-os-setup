#!/usr/bin/env bash
#
# Signs Zo in to a Claude Code or Codex subscription, so the owner's Zo uses
# their existing plan instead of paying per use.
#
# Run on the Zo server. Both flows need a browser, so this cannot finish on its
# own: it starts the sign-in, prints what the owner has to open, and reports
# when it worked.
#
# The two tools differ in shape and are handled differently:
#
#   codex  - prints a URL and a one-time code, then completes by itself once
#            the code is entered in the browser. Fire and poll.
#   claude - prints a URL, then WAITS for a code to be pasted back. The process
#            has to stay alive with a writable stdin, so it is started with a
#            FIFO and the code is delivered with the `code` command.
#
# Install to /home/workspace/Services/vimigo-setup/ on the customer's Zo.
#
# Usage:
#   ./zo-ai-signin.sh status
#   ./zo-ai-signin.sh start codex
#   ./zo-ai-signin.sh start claude
#   ./zo-ai-signin.sh code claude <code-from-browser>

set -uo pipefail

RUN_DIR=/home/workspace/Services/vimigo-setup/.signin
CLAUDE_FIFO="$RUN_DIR/claude.in"
CLAUDE_LOG="$RUN_DIR/claude.log"
CODEX_LOG="$RUN_DIR/codex.log"

mkdir -p "$RUN_DIR"

# Strips ANSI escapes so the output can be read by a script or a human.
plain() { sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$1" 2>/dev/null; }

claude_logged_in() {
    claude auth status 2>/dev/null | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'
}

codex_logged_in() {
    # Deliberately not `! codex login status | grep -q "not logged in"`.
    # `codex login status` exits 1 when signed out, and under `set -o pipefail`
    # the pipeline inherits that 1, which the leading `!` then flips into
    # success - reporting a signed-out machine as signed in. Read the text.
    local out
    out="$(codex login status 2>&1)"
    case "$out" in
        *[Nn]"ot logged in"*) return 1 ;;
        *[Ll]"ogged in"*)     return 0 ;;
        *)                    return 1 ;;
    esac
}

cmd_status() {
    local claude_state codex_state
    if claude_logged_in; then claude_state=true; else claude_state=false; fi
    if codex_logged_in; then codex_state=true; else codex_state=false; fi
    printf '{"claude":{"loggedIn":%s},"codex":{"loggedIn":%s}}\n' "$claude_state" "$codex_state"
}

start_codex() {
    if codex_logged_in; then echo "ALREADY_SIGNED_IN"; return 0; fi

    # -x, never -f: `pkill -f "codex login"` also matches the shell running this
    # script, so it kills itself and the caller sees an unexplained SIGTERM.
    pkill -x codex 2>/dev/null
    sleep 1
    rm -f "$CODEX_LOG"

    # --device-auth, not the default flow: the default starts a login server on
    # localhost:1455, which is unreachable from the owner's laptop because this
    # is running on the Zo server.
    nohup codex login --device-auth > "$CODEX_LOG" 2>&1 </dev/null &
    # The device code takes a few seconds to arrive from OpenAI.
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        sleep 2
        grep -qE '[A-Z0-9]{4}-[A-Z0-9]{4,}' "$CODEX_LOG" 2>/dev/null && break
    done

    local url code
    url="$(plain "$CODEX_LOG" | grep -oE 'https://[^ ]*device[^ ]*' | head -1)"
    code="$(plain "$CODEX_LOG" | grep -oE '\b[A-Z0-9]{4}-[A-Z0-9]{4,}\b' | head -1)"

    if [ -z "$code" ]; then
        echo "FAILED"
        plain "$CODEX_LOG" | grep -vE '^\s*$' | head -10
        return 1
    fi

    printf 'URL %s\nCODE %s\n' "${url:-https://auth.openai.com/codex/device}" "$code"
}

start_claude() {
    if claude_logged_in; then echo "ALREADY_SIGNED_IN"; return 0; fi

    pkill -x claude 2>/dev/null
    sleep 1
    rm -f "$CLAUDE_LOG" "$CLAUDE_FIFO"
    mkfifo "$CLAUDE_FIFO"

    # Holding the FIFO open from a sleeping writer keeps claude waiting instead
    # of seeing EOF and giving up before the owner has pasted anything.
    ( sleep 900 > "$CLAUDE_FIFO" ) &
    nohup claude auth login --claudeai < "$CLAUDE_FIFO" > "$CLAUDE_LOG" 2>&1 &

    for _ in 1 2 3 4 5 6 7 8; do
        sleep 2
        grep -q 'https://' "$CLAUDE_LOG" 2>/dev/null && break
    done

    local url
    url="$(plain "$CLAUDE_LOG" | grep -oE 'https://[^ ]+' | head -1)"
    if [ -z "$url" ]; then
        echo "FAILED"
        plain "$CLAUDE_LOG" | grep -vE '^\s*$' | head -10
        return 1
    fi
    printf 'URL %s\n' "$url"
}

# Delivers the code the browser gave back to the waiting claude process.
cmd_code() {
    local code="${1:-}"
    [ -n "$code" ] || { echo "FAILED: no code given"; return 1; }
    [ -p "$CLAUDE_FIFO" ] || { echo "FAILED: no sign-in is waiting. Start it again."; return 1; }

    printf '%s\n' "$code" > "$CLAUDE_FIFO"

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        if claude_logged_in; then echo "SIGNED_IN"; return 0; fi
    done

    echo "FAILED"
    plain "$CLAUDE_LOG" | grep -vE '^\s*$' | tail -8
    return 1
}

case "${1:-status}" in
    status) cmd_status ;;
    start)
        case "${2:-}" in
            codex)  start_codex ;;
            claude) start_claude ;;
            *) echo "FAILED: say which one, codex or claude"; exit 2 ;;
        esac
        ;;
    code)
        case "${2:-}" in
            claude) cmd_code "${3:-}" ;;
            codex)  echo "Codex needs no code here - enter it in the browser instead."; exit 2 ;;
            *) echo "FAILED: say which one"; exit 2 ;;
        esac
        ;;
    *) echo "Use: status | start <codex|claude> | code claude <code>"; exit 2 ;;
esac
