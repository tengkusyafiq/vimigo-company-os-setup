#!/usr/bin/env bash
#
# Vimigo WhatsApp bridge - installs on the customer's Zo server.
#
# The bridge must stay connected when the customer's laptop sleeps, so it lives
# on Zo and never on the laptop. That also keeps Go, a C compiler, and a service
# manager off the customer's machine entirely.
#
# Run this ON ZO (via Zo's shell), not on the laptop.
#
# Usage:
#   ./zo-whatsapp-setup.sh           install or repair, then report status
#   ./zo-whatsapp-setup.sh status    report status only, change nothing
#   ./zo-whatsapp-setup.sh pair <phone>   request a pairing code, e.g. 60123456789
#
# Every step detects before it acts. Re-running is safe: an existing repository,
# secrets, and session store are reused, never regenerated over a working setup.

set -uo pipefail

REPO_URL="https://github.com/vimigo-lee/whatsapp-mcp-go.git"
REPO="${WHATSAPP_REPO:-/home/workspace/Services/whatsapp-mcp-go}"
GO_VERSION="1.25.0"
GOROOT_DIR="/home/workspace/.local/go"
BRIDGE_PORT=8080
MCP_PORT=5777

say()  { printf '  %s\n' "$1"; }
good() { printf '  \033[32m%s\033[0m\n' "$1"; }
warn() { printf '  \033[33m%s\033[0m\n' "$1"; }
bad()  { printf '  \033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[36m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# Go toolchain
# ---------------------------------------------------------------------------
# The repository pins go 1.25.0 in both go.mod files. Distribution Go is often
# far older, so the version is checked rather than assumed.

ensure_go() {
    step '1. Go toolchain'

    if [ -x "$GOROOT_DIR/bin/go" ] && "$GOROOT_DIR/bin/go" version | grep -q "go${GO_VERSION%.*}"; then
        good "Go $("$GOROOT_DIR/bin/go" version | awk '{print $3}') already installed."
        export PATH="$GOROOT_DIR/bin:$PATH"
        return 0
    fi

    if command -v go >/dev/null 2>&1 && go version | grep -q "go1\.2[5-9]"; then
        good "System Go $(go version | awk '{print $3}') is new enough."
        return 0
    fi

    say "Installing Go $GO_VERSION (the repository requires it)."
    mkdir -p /home/workspace/.local
    if ! curl -fsSL -o /tmp/go.tgz \
        "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"; then
        bad 'Could not download Go.'
        return 1
    fi
    rm -rf "$GOROOT_DIR"
    tar -C /home/workspace/.local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
    export PATH="$GOROOT_DIR/bin:$PATH"

    if go version >/dev/null 2>&1; then
        good "Go $(go version | awk '{print $3}') installed."
        return 0
    fi
    bad 'Go did not install correctly.'
    return 1
}

ensure_compiler() {
    # go-sqlite3 is CGO, so a C compiler is mandatory.
    if command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
        good "C compiler present ($( (gcc --version || cc --version) 2>/dev/null | head -1 ))."
        return 0
    fi
    # Installed here rather than reported. This runs as root on the customer's
    # own Zo, and the alternative was printing "apt-get install -y
    # build-essential" at a business owner who has never opened a terminal -
    # which is not an instruction they can carry out, so it is not a fallback.
    say 'Installing the build tools this needs...'
    if apt-get install -y --no-install-recommends build-essential >/dev/null 2>&1 ||
       (apt-get update >/dev/null 2>&1 && apt-get install -y --no-install-recommends build-essential >/dev/null 2>&1); then
        if command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
            good 'Build tools installed.'
            return 0
        fi
    fi

    bad 'Could not install the build tools this needs.'
    return 1
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

ensure_repo() {
    step '2. Source code'

    if [ -d "$REPO/.git" ]; then
        good "Repository already present at $REPO"
        # Only fast-forward, and only when the tree is clean, so local edits and
        # the session store are never discarded to make an update succeed.
        if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
            git -C "$REPO" pull --ff-only >/dev/null 2>&1 \
                && say "Updated to $(git -C "$REPO" log --oneline -1)" \
                || say 'Left at the current revision (no clean fast-forward).'
        else
            warn 'Local changes present - left exactly as they are.'
        fi
        return 0
    fi

    # A directory that exists without a .git in it is a dead end, not a hiccup:
    # git clone refuses to write into a non-empty directory, so every retry
    # from here on fails the same way and the owner can never get past it. It
    # happens after an interrupted install, or when something else creates the
    # path first.
    #
    # So it is moved aside - and any linked WhatsApp session inside it is
    # carried across, because losing that costs a re-pair and it is the one
    # thing here that cannot be downloaded again.
    local rescued=""
    if [ -d "$REPO" ]; then
        warn 'Found a half-finished copy. Setting it aside and starting fresh.'
        if [ -f "$REPO/whatsapp-bridge/store/whatsapp.db" ]; then
            rescued="$(mktemp -d)"
            cp -a "$REPO/whatsapp-bridge/store" "$rescued/store" 2>/dev/null || rescued=""
        fi
        mkdir -p /home/workspace/Trash
        mv "$REPO" "/home/workspace/Trash/whatsapp-mcp-go.partial.$(date -u +%Y%m%dT%H%M%SZ)" 2>/dev/null || {
            bad 'Could not move the half-finished copy out of the way.'
            return 1
        }
    fi

    mkdir -p "$(dirname "$REPO")"
    if git clone --depth 1 "$REPO_URL" "$REPO" >/dev/null 2>&1; then
        if [ -n "$rescued" ] && [ -d "$rescued/store" ]; then
            mkdir -p "$REPO/whatsapp-bridge"
            rm -rf "$REPO/whatsapp-bridge/store"
            cp -a "$rescued/store" "$REPO/whatsapp-bridge/store" 2>/dev/null &&
                say 'Your existing WhatsApp session was kept, so no need to link again.'
            rm -rf "$rescued"
        fi
        good "Cloned $(git -C "$REPO" log --oneline -1)"
        return 0
    fi
    bad 'Could not clone the repository.'
    return 1
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build_binaries() {
    step '3. Build'

    export CGO_ENABLED=1
    export GOFLAGS=-buildvcs=false

    for module in whatsapp-bridge:whatsapp-bridge whatsapp-mcp-server:whatsapp-mcp; do
        local dir="${module%%:*}" out="${module##*:}"
        say "Building $dir ..."
        if ! (cd "$REPO/$dir" && go mod download && go build -o "$out" .); then
            bad "Build failed in $dir"
            return 1
        fi
    done

    good 'Both binaries built.'
    return 0
}

# ---------------------------------------------------------------------------
# Secrets and launchers
# ---------------------------------------------------------------------------

ensure_config() {
    step '4. Configuration'

    local bridge_env="$REPO/whatsapp-bridge/.env"
    local mcp_env="$REPO/whatsapp-mcp-server/.env"
    local api_key

    if [ -f "$bridge_env" ] && grep -q '^WHATSAPP_API_KEY=.\+' "$bridge_env"; then
        api_key="$(grep '^WHATSAPP_API_KEY=' "$bridge_env" | cut -d= -f2-)"
        good 'Existing secrets reused. The linked WhatsApp session stays valid.'
    else
        # Hex, not base64: no +, / or = padding, so nothing downstream can
        # mangle the value when it passes through a shell or a config writer.
        api_key="$(openssl rand -hex 32)"
        local jwt_secret; jwt_secret="$(openssl rand -hex 32)"
        umask 077
        cat > "$bridge_env" <<EOF
WHATSAPP_API_KEY=$api_key
WHATSAPP_JWT_SECRET=$jwt_secret
IS_POSTGRES=false
HOST=127.0.0.1
PORT=$BRIDGE_PORT
LOG_LEVEL=info
BRIDGE_TZ=Asia/Kuala_Lumpur
EOF
        good 'New secrets generated.'
    fi

    umask 077
    cat > "$mcp_env" <<EOF
WHATSAPP_API_KEY=$api_key
API_BASE_URL=http://127.0.0.1:$BRIDGE_PORT/api
IS_HTTP=true
HTTP_BASE_URL=127.0.0.1:$MCP_PORT
EOF
    chmod 600 "$bridge_env" "$mcp_env"

    # Neither binary reads a .env file: they read the real process environment,
    # and only docker-compose was wiring that up. Outside compose the launchers
    # below are the only supported way to start them.
    cat > "$REPO/run-bridge.sh" <<'LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/whatsapp-bridge"
set -a; . ./.env; set +a
exec ./whatsapp-bridge
LAUNCH

    cat > "$REPO/run-mcp.sh" <<'LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/whatsapp-mcp-server"
set -a; . ./.env; set +a
exec ./whatsapp-mcp
LAUNCH

    chmod +x "$REPO/run-bridge.sh" "$REPO/run-mcp.sh"
    good 'Config written with owner-only permissions.'
    return 0
}

# ---------------------------------------------------------------------------
# Bridge process
# ---------------------------------------------------------------------------

bridge_running() { pgrep -f "$REPO/whatsapp-bridge/whatsapp-bridge$" >/dev/null 2>&1 \
    || pgrep -x whatsapp-bridge >/dev/null 2>&1; }

start_bridge() {
    step '5. Bridge process'

    if bridge_running; then
        good 'Bridge already running. Left alone.'
        return 0
    fi

    mkdir -p "$REPO/whatsapp-bridge/store" "$REPO/whatsapp-bridge/logs"
    nohup "$REPO/run-bridge.sh" > "$REPO/whatsapp-bridge/logs/bridge.log" 2>&1 &
    sleep 6

    if bridge_running; then
        good 'Bridge started.'
        return 0
    fi
    bad 'Bridge did not stay up. Recent log:'
    tail -15 "$REPO/whatsapp-bridge/logs/bridge.log" 2>/dev/null | sed 's/^/    /'
    return 1
}

# ---------------------------------------------------------------------------
# Bridge API
# ---------------------------------------------------------------------------

bridge_token() {
    # The API key goes in the Authorization header, and login sits at
    # /auth/login - outside the JWT-protected /api prefix.
    local key
    key="$(grep '^WHATSAPP_API_KEY=' "$REPO/whatsapp-bridge/.env" 2>/dev/null | cut -d= -f2-)"
    [ -n "$key" ] || return 1
    curl -s --max-time 10 -X POST "http://127.0.0.1:$BRIDGE_PORT/auth/login" \
        -H "Authorization: Bearer $key" \
        | grep -oE '"token":"[^"]+"' | cut -d'"' -f4
}

show_status() {
    step 'WhatsApp connection'

    if ! bridge_running; then
        bad 'The bridge is not running.'
        return 1
    fi

    local token; token="$(bridge_token)"
    if [ -z "$token" ]; then
        bad 'Could not authenticate to the bridge.'
        return 1
    fi

    local status
    status="$(curl -s --max-time 10 "http://127.0.0.1:$BRIDGE_PORT/api/auth/status" \
        -H "Authorization: Bearer $token")"

    case "$status" in
        *'"logged_in":true'*)
            good 'WhatsApp is linked and logged in.'
            say "$status"
            return 0 ;;
        *'"pairing_required":true'*)
            warn 'WhatsApp is not linked yet.'
            say ''
            say 'To link it, run:'
            say "    $0 pair <your phone number, e.g. 60123456789>"
            say ''
            say 'WhatsApp will show a code. On your phone open WhatsApp, go to'
            say 'Settings, Linked Devices, Link a device, then Link with phone'
            say 'number instead, and type the code.'
            return 1 ;;
        *)
            warn 'Bridge is up but WhatsApp is not connected.'
            say "$status"
            return 1 ;;
    esac
}

request_pairing_code() {
    local phone="${1:-}"
    if [ -z "$phone" ]; then
        bad 'A phone number is required, in full international form.'
        say 'Example for Malaysia: 60123456789 (no +, no spaces, no dashes)'
        return 1
    fi

    step "Pairing WhatsApp for $phone"

    local token; token="$(bridge_token)"
    if [ -z "$token" ]; then bad 'Could not authenticate to the bridge.'; return 1; fi

    local response
    response="$(curl -s --max-time 30 -X POST \
        "http://127.0.0.1:$BRIDGE_PORT/api/auth/pair-phone" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        -d "{\"phone\":\"$phone\"}")"

    case "$response" in
        *already*paired*) good 'Already paired. Nothing to do.'; return 0 ;;
        *code*)
            good 'Pairing code requested.'
            say "$response"
            say ''
            say 'On your phone: WhatsApp, Settings, Linked Devices,'
            say 'Link a device, Link with phone number instead, then type the code.'
            return 0 ;;
        *)
            bad 'Pairing request failed.'
            say "$response"
            return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-install}" in
    status)
        show_status
        ;;
    pair)
        request_pairing_code "${2:-}"
        ;;
    install)
        ensure_go || exit 1
        ensure_compiler || exit 1
        ensure_repo || exit 1
        build_binaries || exit 1
        ensure_config || exit 1
        start_bridge || exit 1
        show_status || true
        printf '\n'
        ;;
    *)
        bad "Unknown command: $1"
        say 'Use: install | status | pair <phone>'
        exit 2
        ;;
esac
