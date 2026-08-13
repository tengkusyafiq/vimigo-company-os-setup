#!/usr/bin/env bash
#
# Connects a WhatsApp number to the AI apps on this Mac.
#
# The macOS mirror of vimigo-whatsapp.ps1. Where the two ever disagree, the
# PowerShell doer is the specification: it is the one that has been run against
# a real bridge, a real Task Scheduler and three real client configs.
#
# WHAT THIS TARGETS
#
#   bash 3.2 and the BSD userland, because that is what a stock Mac has.
#   No associative arrays. No case-folding parameter expansion. No whole-file
#   readers into an array - neither of the two bash 4 builtins for that.
#   No GNU-only tool flags - each of the banned forms fails on a stock Mac
#   with an error a business owner cannot act on, and the acceptance suite
#   greps this file for every one of them. In-place stream editing eats the
#   next argument as a backup suffix; -P is not a grep option here; base64
#   has no line-wrap flag and needs none; there is no -f for readlink, no -d
#   for date, no -c for stat. And the interpreter Apple removed in macOS 12.3
#   is not merely absent: /usr/bin/ still holds a stub whose only effect is a
#   modal "install the command line developer tools" dialog that no output
#   redirection can suppress, mid-install, in front of somebody who has never
#   opened a terminal.
#
#   No sudo, no admin, ever. Autostart is a per-user LaunchAgent under the
#   owner's own home directory, never a machine-wide one under /Library - the
#   suite greps this file for the machine-wide word, so it is not spelled out
#   even here.
#
# WHAT IT NEVER DOES
#
#   Nothing here deletes, moves, empties or overwrites anything under
#   <root>/run/. That is the bridge's working directory and it holds the
#   linked-device session; losing it means the owner has to fetch their phone
#   and pair again, which is the one thing this whole design exists to avoid.
#   --reinstall replaces bin/ and rewrites configuration, and leaves run/
#   untouched.
#
#   No customer-visible sentence ever carries a file path, a port, a command,
#   a hash, JSON, a tool name, a secret or a phone number.
#
#   Nothing raw ever reaches the screen either, and that is a stronger rule
#   than the one above: the sentences here are all careful, and a single
#   unguarded mkdir prints "mkdir: cannot create directory '/Users/.../Library/
#   Application Support/Vimigo/whatsapp': File exists" underneath one of them.
#   So every command below that touches the filesystem sends its error output
#   to /dev/null and reports failure as a return value instead - the same
#   division the Windows doer gets from wrapping each phase in try/catch. This
#   is not tidiness: the realistic trigger is a full disk on a 128 GB laptop
#   pulling 28 MB and a year of WhatsApp history at a venue, which is exactly
#   when the owner is least able to act on an errno.
#
#   Where the thing that fails is the REDIRECTION rather than the command -
#   writing into a folder that is not a folder - the 2>/dev/null has to come
#   BEFORE the > it guards. Redirections are applied left to right and the
#   shell reports a failed one on whatever standard error is at that moment,
#   so a trailing 2>/dev/null is applied too late to catch anything. Every
#   `2>/dev/null >` below reads oddly for exactly that reason; do not tidy it
#   round the other way.
#
# USAGE
#
#   vimigo-whatsapp.sh --zip-path <path> --zip-sha256 <64-hex>   fresh install
#   vimigo-whatsapp.sh --doctor | --fix | --reconnect | --reinstall
#   vimigo-whatsapp.sh                                            install or repair
#
# Deliberately NOT `set -e` and NOT `set -u`.
#
#   `set -e` in a script this long is a promise it cannot keep: every probe
#   here is expected to fail sometimes (a bridge that is not listening yet, a
#   client that is not installed), and a stray non-zero from any of them would
#   end the install with no sentence on screen at all. Failure is handled
#   explicitly instead, at every call.
#
#   `set -u` would abort with a raw "unbound variable" line naming this file
#   and a line number - the exact shape of output the audience rule forbids.
#   Every expansion below is nonetheless written to be -u clean, and the
#   acceptance suite sources this file under `set -u` and drives it, so that
#   cleanliness is proven rather than asserted.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

install_root() { printf '%s' "$HOME/Library/Application Support/Vimigo/whatsapp"; }

LAUNCH_AGENT_LABEL='com.vimigo.whatsapp'

# NOT in the install root. `launchctl bootstrap` will load a plist from
# anywhere, but only ~/Library/LaunchAgents is scanned at login - so a plist
# written into the install root passes every check that can be run on the day
# (launchctl print shows it loaded, killing the bridge is followed by a
# KeepAlive respawn) and then silently never loads again after the owner's
# next restart. Overridable so the acceptance suite writes a throwaway copy
# instead of a real LaunchAgent on whatever machine happens to run it.
LAUNCH_AGENT_PLIST="${LAUNCH_AGENT_PLIST_TEST:-$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist}"

# A fixed private band, walked in order. Never port 0: that hands back
# something from the ephemeral range, and that number is then frozen into the
# LaunchAgent and three client configs forever. After a reboot another process
# holds it first, the bridge cannot bind and does not exit (its listener runs
# in a goroutine that only logs), so something IS answering on the port, the
# check succeeds against the squatter, and the repair ladder restarts a
# dead-in-the-water bridge three times before giving up. This band sits
# outside the ephemeral range, so the same port is free again tomorrow.
PORT_BAND_START=8765
PORT_BAND_END=8865

EXPECTED_BINARIES='whatsapp-bridge whatsapp-mcp'

# Where the repair skill sits inside the release zip. build-whatsapp.sh stages
# it there and refuses to build without it, for the same reason it refuses
# without this script: the zip is the only thing that reaches the laptop.
SKILL_ZIP_ENTRY='whatsapp-mcp-setup/SKILL.md'

RELEASE_ZIP_URL='https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/v1.0/vimigo-whatsapp-mac-v1.0.zip'

# The last-resort fallback only, and it CANNOT be filled in for real.
# build-whatsapp.sh stages this very file into the zip before hashing it, so
# the zip's SHA256 is a function of this file's own bytes - writing that hash
# in here changes the file, which changes the zip, which changes the hash. No
# fixed point exists. See get_release_zip below for where the real pin lives
# instead (installed.json, carried there at runtime from the --zip-sha256 the
# one-liner already verified the bytes against).
#
# Left as a placeholder forever, on purpose. A placeholder is never 64
# lowercase hex characters, so a call that falls all the way back to this
# constant fails closed - it refuses the download - rather than silently
# skipping verification.
RELEASE_ZIP_SHA256='<filled in by Task 13 from the built asset>'

MCP_ENTRY_NAME='whatsapp'
STALE_MCP_NAMES='whatsapp-mcp whatsapp-mcp-go'

RULES_START='<!-- vimigo:whatsapp:start -->'
RULES_END='<!-- vimigo:whatsapp:end -->'

# Identical wording to the MCP server's own Instructions constant. Both exist
# because neither reaches all three clients on its own: Claude Desktop has no
# instruction file, and a reinstalled AI app loses its file but keeps the
# server.
AI_RULES="$(cat <<'AIRULES'
## Talking to the owner about WhatsApp

The person using this is a business owner. They have never opened a terminal
and do not know what a file, a path, a command, a port, or a log is.

Never show them a file path, a command, JSON, a chat ID, a tool name, an error
message, or a log line. Never offer to run, install, edit, or fix anything.
Say "your WhatsApp", never "the bridge" or "the MCP server". Call people by the
name in their contacts, never by a number.

Reply in the language they wrote in. If they write Malay or a mix, answer the
same way, and draft WhatsApp replies in the language and tone of the chat being
replied to.

Keep it short. A summary of unread messages is who, and what they want - not a
transcript.

Before sending any WhatsApp message, show the exact words and wait for a yes.
Sending is not reversible and it goes to a real person.

If WhatsApp is not working, do not diagnose it. Use the whatsapp-mcp-setup
skill. The only thing you may ever ask them to do is something on their phone.
AIRULES
)"

# Resolved fresh at every use rather than frozen into a variable at load, so
# the acceptance suite can point each one at a sandbox after sourcing and
# never touch this machine's real configuration. Same shape as the Windows
# doer's $script:ClaudeDesktopConfigPathOverride.
claude_desktop_config_path() {
    printf '%s' "${CLAUDE_DESKTOP_CONFIG_OVERRIDE:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"
}
codex_config_path() {
    printf '%s' "${CODEX_CONFIG_OVERRIDE:-$HOME/.codex/config.toml}"
}
claude_memory_path() {
    printf '%s' "${CLAUDE_MEMORY_OVERRIDE:-$HOME/.claude/CLAUDE.md}"
}
codex_memory_path() {
    printf '%s' "${CODEX_MEMORY_OVERRIDE:-$HOME/.codex/AGENTS.md}"
}
# The one folder every AI app on this Mac reads a skill from - Claude Code,
# Claude Desktop and Cowork all load ~/.claude/skills/<name>/SKILL.md. Under
# the owner's own home, so installing it needs no password and no
# administrator, and one write reaches all three.
claude_skill_path() {
    printf '%s' "${CLAUDE_SKILL_OVERRIDE:-$HOME/.claude/skills/whatsapp-mcp-setup/SKILL.md}"
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

make_temp_dir() {
    # BSD mktemp needs a template or -t; a bare `mktemp -d` fails outright,
    # the caller's work directory becomes "", and every path underneath it
    # becomes /manifest.json - which then "verifies" against nothing and
    # reports success having installed precisely nothing.
    local d
    d="$(mktemp -d 2>/dev/null || mktemp -d -t vimigo-wa 2>/dev/null)" || return 1
    [ -n "$d" ] && [ -d "$d" ] || return 1
    printf '%s' "$d"
}

file_sha256() {
    # shasum ships with macOS. sha256sum is the fallback for the machines this
    # is developed on; neither is a GNU-only flag, and both print the hash as
    # the first field.
    [ -f "${1:-}" ] || return 1
    local out=''
    if command -v shasum >/dev/null 2>&1; then
        out="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
        out="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')"
    fi
    printf '%s' "$out" | grep -qE '^[0-9a-f]{64}$' || return 1
    printf '%s' "$out"
}

is_sha256() {
    printf '%s' "${1:-}" | grep -qE '^[0-9a-f]{64}$'
}

new_secret() {
    # od, not the interpreter Apple removed, and not $RANDOM - which is a
    # 15-bit value from a seeded generator and is not a secret at all.
    # -An -N32 -tx1 is POSIX and behaves identically on the BSD and GNU
    # implementations; the tr strips the spacing od inserts between bytes.
    LC_ALL=C od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

xml_escape() {
    # Only the paths need this. Everything else written into the LaunchAgent
    # is either a constant of ours or 64 characters of lowercase hex, and a
    # home directory containing an ampersand would otherwise produce a plist
    # launchd refuses to parse, with no message anybody can act on.
    printf '%s' "${1:-}" | sed -e 's|&|\&amp;|g' -e 's|<|\&lt;|g' -e 's|>|\&gt;|g'
}

log_note() {
    # A one-line diagnostic note for whoever helps this owner later. Never
    # shown on screen, and never allowed to fail or block anything on its own
    # account. Appended to the same log the bridge itself writes into, so
    # there is exactly one place to look rather than two.
    local root="${1:-}" text="${2:-}"
    [ -n "$root" ] || return 0
    mkdir -p "$root/logs" 2>/dev/null || return 0
    trim_bridge_log "$root"
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$text" 2>/dev/null >> "$root/logs/bridge.log" || true
    return 0
}

LOG_CEILING_BYTES=2000000
LOG_KEEP_BYTES=200000

trim_bridge_log() {
    # $1 root. A ceiling on the one file that has none of its own.
    #
    # launchd appends every line the bridge prints to logs/bridge.log, and a
    # bridge that cannot read its configuration prints two lines and exits
    # CLEANLY - so the watchdog starts it again, for ever. Nothing in launchd
    # rotates that file. Left alone it is the same failure that started all of
    # this: a disk quietly filling up on a laptop that has 128 GB and a year
    # of WhatsApp history to hold. The throttle in the LaunchAgent slows that
    # loop right down; this is what bounds it.
    #
    # Truncated in place - read the tail, write it back over the same file -
    # rather than moved aside. The running bridge holds this file open in
    # append mode: renaming it leaves the bridge writing into something nobody
    # can find again, while a rewrite through the same name keeps the file it
    # is holding and simply makes it shorter. The tail is kept rather than the
    # head, because what a helper needs is what happened most recently.
    #
    # Nothing here is under run/, and nothing here may fail loudly.
    local root="${1:-}" log size
    [ -n "$root" ] || return 0
    log="$root/logs/bridge.log"
    [ -f "$log" ] || return 0
    size="$(wc -c < "$log" 2>/dev/null | tr -d ' ')"
    case "$size" in ''|*[!0-9]*) return 0 ;; esac
    [ "$size" -gt "$LOG_CEILING_BYTES" ] || return 0
    tail -c "$LOG_KEEP_BYTES" "$log" 2>/dev/null > "$log.vimigo-tmp" || return 0
    cat "$log.vimigo-tmp" 2>/dev/null > "$log" || true
    rm -f "$log.vimigo-tmp" 2>/dev/null || true
    return 0
}

free_port() {
    # The first port in the band that nothing answers on.
    #
    # /dev/tcp is a bash builtin - no external command, and therefore no
    # chance of the developer-tools dialog. A refused connection means
    # nothing is listening, which is what free means here.
    local p="$PORT_BAND_START"
    while [ "$p" -le "$PORT_BAND_END" ]; do
        if ! ( exec 3<>"/dev/tcp/127.0.0.1/$p" ) 2>/dev/null; then
            printf '%s' "$p"
            return 0
        fi
        p=$((p + 1))
    done
    return 1
}

# ---------------------------------------------------------------------------
# The launcher and the LaunchAgent
# ---------------------------------------------------------------------------

write_bridge_launcher() {
    # $1 the launcher path, which lives in <root>/bin
    #
    # It carries no configuration and no secret: launchd hands the bridge its
    # environment natively, so the LaunchAgent is the one place the key lives.
    # What this file exists for is the working directory.
    #
    # The bridge calls os.MkdirAll("store") in whatever directory it happens
    # to be started in, BEFORE it reads any configuration - so if that
    # directory is bin/, the linked-device session lands in bin/store/, where
    # the next repair or start-over replaces bin/ and destroys it. The plist
    # sets WorkingDirectory as well, but a `cd` that is checked here fails
    # loudly and immediately instead of trusting one mechanism with the one
    # piece of data that cannot be recreated without the owner's phone.
    local path="${1:-}"
    [ -n "$path" ] || return 1
    mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
    cat 2>/dev/null > "$path" <<'LAUNCHER'
#!/bin/sh
# Vimigo - starts your WhatsApp connection. Written by the setup; not meant to
# be edited. The working directory is the whole point of this file: the bridge
# creates its store in whatever directory it is started in, and that store
# holds the link to the phone.
here=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$here/../run" || exit 1
exec "$here/whatsapp-bridge"
LAUNCHER
    chmod 0755 "$path" 2>/dev/null || return 1
    return 0
}

write_launch_agent() {
    # $1 plist  $2 program  $3 working directory  $4 api key  $5 jwt  $6 port
    #
    # launchd carries the environment natively, so there is no wrapper holding
    # secrets and no .env anywhere - the bridge reads os.Getenv only.
    #
    # KeepAlive is the watchdog: launchd restarts the bridge within seconds of
    # it dying, where the Windows side has to poll every five minutes for the
    # same effect. RunAtLoad is the login half.
    #
    # ThrottleInterval is the bound on that watchdog, and it is needed because
    # of how the bridge fails rather than how it dies. A configuration it
    # cannot read is a log line and a plain return, so the process exits
    # ZERO - and KeepAlive on its own reads a clean exit as "start it again",
    # every ten seconds, for ever. Two lines of log each time, into a file
    # nothing rotates, on the same 128 GB laptop whose disk filling up is the
    # failure that started this. trim_bridge_log caps the file; this slows the
    # loop that fills it.
    #
    # Thirty seconds, not the five minutes the Windows watchdog polls at, and
    # not the ten the default gives. The doer issues `launchctl kickstart -k`
    # immediately after bootstrapping this agent, and whether launchd honours
    # a throttle against an explicit kickstart is not something that can be
    # answered off a Mac. If it does, the delay lands inside resume_bridge's
    # ninety-second wait and inside restart_bridge's sixty, and nothing an
    # owner is watching gets slower. Five minutes would sit outside both and
    # turn a healthy install into "Your WhatsApp did not start."
    #
    # Not a KeepAlive dictionary keyed on SuccessfulExit either, which would
    # bound the loop absolutely by never restarting a clean exit. That is a
    # stricter rule than Windows has, and the one case it would change is the
    # one that matters most in this room: a phone that unlinks, a bridge that
    # stops, and --reconnect with nothing left running to pair against.
    local plist="${1:-}" program="${2:-}" workdir="${3:-}" key="${4:-}" jwt="${5:-}" port="${6:-}"
    [ -n "$plist" ] || return 1
    mkdir -p "$(dirname "$plist")" 2>/dev/null || return 1

    local e_program e_workdir e_log
    e_program="$(xml_escape "$program")"
    e_workdir="$(xml_escape "$workdir")"
    e_log="$(xml_escape "$workdir/../logs/bridge.log")"

    cat 2>/dev/null > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCH_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$e_program</string>
  </array>
  <key>WorkingDirectory</key><string>$e_workdir</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$e_log</string>
  <key>StandardErrorPath</key><string>$e_log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>WHATSAPP_API_KEY</key><string>$key</string>
    <key>WHATSAPP_JWT_SECRET</key><string>$jwt</string>
    <key>IS_POSTGRES</key><string>false</string>
    <key>HOST</key><string>127.0.0.1</string>
    <key>PORT</key><string>$port</string>
    <key>LOG_LEVEL</key><string>info</string>
    <key>FULL_SYNC</key><string>true</string>
    <key>FULLSYNC_DAYS</key><string>365</string>
    <key>DEVICE_NAME</key><string>Vimigo AI</string>
  </dict>
</dict>
</plist>
PLIST
    # It holds the connection key, so only this owner may read it.
    chmod 0600 "$plist" 2>/dev/null || return 1
    return 0
}

read_agent_value() {
    # $1 plist  $2 environment variable name
    #
    # A line reader rather than a plist tool, because this only ever reads
    # back what write_launch_agent above wrote, in the exact one-key-per-line
    # shape it writes it - which means it needs nothing installed, behaves
    # identically everywhere, and can be proven on the machine this is
    # developed on rather than only on the day. The vertical bar is the sed
    # delimiter so the closing tags need no escaping.
    local plist="${1:-}" name="${2:-}" value=''
    [ -f "$plist" ] || return 1
    [ -n "$name" ] || return 1
    value="$(sed -n "s|^[[:space:]]*<key>$name</key><string>\(.*\)</string>[[:space:]]*\$|\1|p" "$plist" 2>/dev/null | head -1)"
    [ -n "$value" ] || return 1
    printf '%s' "$value"
}

register_autostart() {
    # $1 plist path. Bootout first, so a changed port actually takes effect -
    # bootstrap alone against an already-loaded label is a no-op, and the
    # bridge would keep running with the old environment while every client
    # config pointed at the new port.
    #
    # Nothing in here may end the install. An owner whose install otherwise
    # succeeded must not be stopped by a machine-specific launchd refusal;
    # autostart_registered below is the truth of what actually landed, and
    # the check verb is where a missing one gets reported.
    local plist="${1:-$LAUNCH_AGENT_PLIST}" uid
    [ -f "$plist" ] || return 1
    uid="$(id -u)"
    launchctl bootout "gui/$uid/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$uid" "$plist" >/dev/null 2>&1 || true
    launchctl kickstart -k "gui/$uid/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    autostart_registered
}

autostart_registered() {
    # Two things, and both have to be true.
    #
    # launchctl print alone says the job is loaded RIGHT NOW, which a plist
    # bootstrapped from any directory on the disk satisfies. Only
    # ~/Library/LaunchAgents is scanned at login, so a plist that is loaded
    # but not there passes every check available on the day and then silently
    # stops loading after the owner's next restart. The Windows doer reports
    # its two halves - the login entry and the watchdog - through one code for
    # the same reason: the sentence the owner reads is true either way, and
    # the repair rung re-attempts both unconditionally.
    [ -f "$LAUNCH_AGENT_PLIST" ] || return 1
    launchctl print "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1
}

remove_autostart() {
    launchctl bootout "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    rm -f "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    return 0
}

bridge_pids() {
    # $1 root. Matched against this install's own binary path, never by name
    # alone, so an unrelated whatsapp-bridge elsewhere on the machine is never
    # touched - the same rule the Windows doer follows when it matches on
    # .Path rather than on the process name.
    local root="${1:-}"
    [ -n "$root" ] || return 1
    pgrep -f "$root/bin/whatsapp-bridge" 2>/dev/null
}

suspend_bridge() {
    # $1 root. Nothing that replaces a binary or moves the port may run
    # without this first: launchd's KeepAlive brings the bridge straight back,
    # and a move onto a running binary fails halfway through, leaving one file
    # replaced and one not.
    local root="${1:-}" waited=0
    launchctl bootout "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    if [ -n "$root" ]; then
        local pid
        for pid in $(bridge_pids "$root"); do
            kill "$pid" >/dev/null 2>&1 || true
        done
        while [ "$waited" -lt 30 ]; do
            [ -n "$(bridge_pids "$root")" ] || return 0
            sleep 1
            waited=$((waited + 1))
        done
        [ -n "$(bridge_pids "$root")" ] && return 1
    fi
    return 0
}

resume_bridge() {
    # $1 root  $2 port  $3 api key
    #
    # Confirmed, not assumed. The bridge does NOT exit non-zero on a bad
    # configuration - at the pinned commit a config failure is a log line and
    # a plain return, so the process exits ZERO having done nothing at all.
    # Anything that decides "did it start" from an exit status reads a missing
    # key as success. This keys on the bridge answering on its port instead.
    local root="${1:-}" port="${2:-}" key="${3:-}"
    register_autostart "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1
    [ -n "$port" ] && [ -n "$key" ] || return 1
    wait_bridge_answering "$port" "$key" 90
}

# ---------------------------------------------------------------------------
# Talking to the bridge
# ---------------------------------------------------------------------------

bridge_reachable() {
    # Liveness only. On its own this is evidence of nothing: it is just as
    # true for a squatter as for us, which is why identity lives in
    # auth_status below and "answers but is not ours" has a code of its own.
    local port="${1:-0}"
    ( exec 3<>"/dev/tcp/127.0.0.1/$port" ) 2>/dev/null
}

bridge_token() {
    # $1 port  $2 api key. The key goes in the Authorization header and
    # nowhere else: the bridge builds "Bearer " + its configured key and
    # compares it to the header, and never reads the request body at all.
    # Posting the key in the body 401s on a perfectly healthy, freshly paired
    # install.
    curl -fsS -X POST --max-time 10 -H "Authorization: Bearer ${2:-}" \
        "http://127.0.0.1:${1:-0}/auth/login" 2>/dev/null |
        sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

pairing_status() {
    # $1 port  $2 token. The raw body, or nothing.
    curl -fsS --max-time 10 -H "Authorization: Bearer ${2:-}" \
        "http://127.0.0.1:${1:-0}/api/auth/status" 2>/dev/null
}

auth_status() {
    # $1 port  $2 api key. Logs in and prints the status body, or prints
    # nothing at all.
    #
    # Identity, not liveness: our bridge answers this with these fields.
    # Anything else on the port does not, and that is a different problem with
    # a different repair. An overridable seam, so the acceptance suite can
    # drive every rung of the check without a bridge, a network or a service.
    local token
    token="$(bridge_token "${1:-}" "${2:-}")"
    [ -n "$token" ] || return 1
    local body
    body="$(pairing_status "${1:-}" "$token")"
    printf '%s' "$body" | grep -q '"logged_in"' || return 1
    printf '%s' "$body"
}

json_flag_true() {
    # $1 body  $2 field. JSON from one endpoint, read the way a shell can read
    # it without a parser: the field name, a colon, optional space, then the
    # literal true.
    printf '%s' "${1:-}" | grep -qE "\"${2:-}\"[[:space:]]*:[[:space:]]*true"
}

pairing_code() {
    # $1 port  $2 token  $3 phone number in E.164
    curl -fsS -X POST --max-time 15 -H "Authorization: Bearer ${2:-}" \
        -H 'Content-Type: application/json' \
        -d "{\"phone\":\"${3:-}\"}" \
        "http://127.0.0.1:${1:-0}/api/auth/pair-phone" 2>/dev/null |
        sed -n 's/.*"code"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

chat_count() {
    # $1 port  $2 token. -1 when the question could not be asked at all, so a
    # caller can tell "no conversations yet" from "no answer".
    local body
    body="$(curl -fsS --max-time 15 -H "Authorization: Bearer ${2:-}" \
        "http://127.0.0.1:${1:-0}/api/chats?limit=1" 2>/dev/null)" || { printf '%s' '-1'; return 1; }
    local n
    n="$(printf '%s' "$body" | sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
    [ -n "$n" ] || { printf '%s' '-1'; return 1; }
    printf '%s' "$n"
}

wait_first_chats() {
    # $1 port  $2 token  $3 timeout seconds
    #
    # logged_in flips the moment the phone links, but a full sync over 365
    # days keeps ingesting for minutes afterwards and the status endpoint
    # exposes no progress at all. The first non-empty chat list is the only
    # honest signal that "what did Ali say last week?" can be answered - and a
    # confident wrong answer is the first impression a hundred people take
    # away.
    local deadline=$(( $(date +%s) + ${3:-180} )) n
    while [ "$(date +%s)" -lt "$deadline" ]; do
        n="$(chat_count "${1:-}" "${2:-}")"
        case "$n" in
            ''|-1) : ;;
            *) [ "$n" -gt 0 ] 2>/dev/null && return 0 ;;
        esac
        sleep 3
    done
    return 1
}

wait_bridge_answering() {
    # $1 port  $2 api key  $3 timeout seconds
    #
    # Polled, not slept. A cold start is the client connecting plus a full
    # sync opening a year of history; eight seconds is barely the process
    # launching, so a short wait reports failure on a machine that becomes
    # healthy twenty seconds later - and the skill then has the AI run repair
    # three times, which is nine forced kills of the bridge during a sync.
    local deadline=$(( $(date +%s) + ${3:-60} ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if bridge_reachable "${1:-}"; then
            if [ -n "$(auth_status "${1:-}" "${2:-}")" ]; then return 0; fi
        fi
        sleep 2
    done
    return 1
}

restart_bridge() {
    # $1 root  $2 port
    #
    # The bridge's own QR goroutine returns on a channel timeout and never
    # clears the pairing QR state, so the endpoint answers 200 with the same
    # dead square forever once the underlying QR channel has timed out. No new
    # code exists until the client reconnects, which makes a restart the only
    # way back to a live square - and it costs nothing here: nothing has
    # linked yet (the loop returns the instant it does), and the store lives
    # under run/, untouched by any of this.
    local root="${1:-}" port="${2:-}" waited=0
    suspend_bridge "$root" >/dev/null 2>&1
    register_autostart "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1
    while [ "$waited" -lt 60 ]; do
        bridge_reachable "$port" && return 0
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# ---------------------------------------------------------------------------
# Binaries
# ---------------------------------------------------------------------------

get_installed_zip_sha256() {
    # The one persisted copy of a pin this install actually verified against,
    # written by install_binaries the moment a real one comes through it. Read
    # defensively: an install that never had a pin to persist has no such
    # field, and that must read back as "no pin available".
    local root="${1:-}"
    [ -f "$root/installed.json" ] || return 1
    local value
    value="$(sed -n 's/.*"zip_sha256"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{64\}\)".*/\1/p' "$root/installed.json" 2>/dev/null | head -1)"
    is_sha256 "$value" || return 1
    printf '%s' "$value"
}

get_release_zip() {
    # $1 root  $2 an already-verified pin, when the caller has one
    #
    # The repair ladder's own way to re-fetch. A Mac owner whose binaries went
    # missing has no one-liner in front of them any more, and without this no
    # documented verb could put them back.
    #
    # The pin is never baked into this file (see RELEASE_ZIP_SHA256 above for
    # why no fixed point exists). It is carried at runtime instead, in this
    # order:
    #   1. what the caller hands in, when it already holds a verified pin;
    #   2. installed.json's own zip_sha256, written by the last successful
    #      install - the ordinary case for a repair, since the owner's
    #      original one-liner already ran once and left it behind;
    #   3. the compiled constant, which is never real - so reaching that point
    #      with nothing better available always fails closed.
    local root="${1:-}" pin="${2:-}"
    is_sha256 "$pin" || pin="$(get_installed_zip_sha256 "$root")"
    is_sha256 "$pin" || pin="$RELEASE_ZIP_SHA256"
    is_sha256 "$pin" || return 1

    local dir target actual
    dir="$(make_temp_dir)" || return 1
    target="$dir/release.zip"
    if ! curl -fsL --connect-timeout 30 --speed-limit 1024 --speed-time 60 \
             --max-time 1200 --retry 2 --retry-delay 5 \
             -o "$target" "$RELEASE_ZIP_URL" 2>/dev/null; then
        rm -rf "$dir" 2>/dev/null
        return 1
    fi
    actual="$(file_sha256 "$target")" || { rm -rf "$dir" 2>/dev/null; return 1; }
    if [ "$actual" != "$pin" ]; then
        rm -rf "$dir" 2>/dev/null
        return 1
    fi
    printf '%s' "$target"
}

# The path get_release_zip last handed back, when this run fetched one for
# itself. A plain variable rather than a return value, because every caller
# takes that return value through a command substitution - a subshell, where
# anything the fetch wanted to record about itself is lost the moment it ends.
FETCHED_RELEASE_ZIP=''

discard_release_zip() {
    # $1 whatever get_release_zip handed back.
    #
    # 28 MB, in a temporary directory nothing ever removed: once for every
    # repair that had to reinstall, once for every start-over, and once more
    # each time either is run again. macOS does clear that folder on its own,
    # "on its own" meaning days - on a laptop whose disk filling up is the
    # failure this whole round of work is about.
    #
    # Deliberately narrow. The file name is get_release_zip's own, so the
    # owner's one-liner download - which the one-liner made, and the one-liner
    # deletes - never matches this and is never touched. The directory goes
    # with rmdir rather than rm -rf, which refuses a directory that still has
    # anything else in it, so the worst this can do on a path it should never
    # have been handed is nothing at all. Nothing under run/ can match either
    # shape.
    local zip="${1:-}" dir
    case "$zip" in
        */release.zip) : ;;
        *) return 0 ;;
    esac
    [ -f "$zip" ] || return 0
    dir="$(dirname "$zip")"
    case "$dir" in
        ''|/|.|..) return 0 ;;
    esac
    rm -f "$zip" 2>/dev/null || true
    rmdir "$dir" 2>/dev/null || true
    return 0
}

manifest_binary_keys() {
    # Every key inside the manifest's binaries object, sorted, space
    # separated. Walking whatever keys happen to be present is what lets a
    # half-written manifest skip the loop body entirely and still reach
    # "verified" - so the key set is compared as a set, before a single hash
    # is looked at.
    #
    # Read as ONE string rather than line by line, because how the manifest is
    # laid out is not ours to assume. A pretty-printed manifest and a
    # single-line one describe exactly the same install, and the single-line
    # form is what a writer that dumps JSON with no indentation produces - one
    # keyword argument away, in a publishing script nobody thinks of as part of
    # this file. Read line by line with a greedy pattern, a single-line
    # manifest yields only its LAST key: the key set then never matches, every
    # download is refused on every Mac, and the hash comparison that was
    # supposed to be the real check is never even reached - so deleting that
    # comparison changes nothing anybody would notice.
    local file="${1:-}"
    [ -f "$file" ] || return 0
    # Nothing at all when there is no such object, rather than whatever keys
    # happen to sit at the top level.
    grep -q '"binaries"' "$file" 2>/dev/null || return 0
    tr -d '\n' < "$file" 2>/dev/null |
        sed -e 's/.*"binaries"[[:space:]]*:[[:space:]]*[{]//' -e 's/[}].*//' |
        tr ',' '\n' |
        sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:[[:space:]]*"[0-9a-f]\{64\}"[[:space:]]*$/\1/p' |
        sort | tr '\n' ' '
}

write_installed_json() {
    # $1 manifest source  $2 destination  $3 the pin, real 64-hex or not
    #
    # One write, and it is the last thing install_binaries does, so
    # "installed.json exists" never means "exists, but the pin write is still
    # pending". Nothing is persisted when the pin is not real 64-hex - a
    # manual run with nothing to record - because get_release_zip's fallback
    # chain already treats an absent field exactly like an older install that
    # never had one.
    local src="${1:-}" dest="${2:-}" sha="${3:-}"
    [ -f "$src" ] || return 1
    if is_sha256 "$sha" && ! grep -q '"zip_sha256"' "$src" 2>/dev/null; then
        awk -v sha="$sha" 'BEGIN{done=0}
            {
                if (done == 0 && index($0, "{") > 0) {
                    sub(/\{/, "{\"zip_sha256\": \"" sha "\",")
                    done = 1
                }
                print
            }' "$src" 2>/dev/null > "$dest" || return 1
        grep -q "\"zip_sha256\": \"$sha\"" "$dest" 2>/dev/null || return 1
        return 0
    fi
    cat "$src" 2>/dev/null > "$dest" || return 1
    return 0
}

install_binaries() {
    # $1 zip  $2 root  $3 the zip's own already-verified sha256 (optional)
    #
    # Every step is checked. Unchecked, the failure mode is not a crash: a
    # stream edit against a missing manifest yields "", a hash of a missing
    # binary fails but its status is masked by the pipe into awk and also
    # yields "", "" and "" compare equal, so both names "verify" - and the
    # function's exit status then comes from the trailing cleanup, which is
    # zero. A truncated download on venue wifi installed nothing and reported
    # success.
    local zip="${1:-}" root="${2:-}" pin="${3:-}"
    [ -n "$zip" ] && [ -n "$root" ] || return 1
    [ -f "$zip" ] || return 1

    local work
    work="$(make_temp_dir)" || return 1

    # ditto first, because it ships with macOS and understands the archive
    # format Apple produces; unzip second for everything else. Both silenced:
    # handed something that is not an archive, unzip prints four lines about
    # end-of-central-directory signatures and names the file three times.
    if ! ditto -x -k "$zip" "$work" >/dev/null 2>&1; then
        if ! unzip -oq "$zip" -d "$work" >/dev/null 2>&1; then
            rm -rf "$work" 2>/dev/null
            return 1
        fi
    fi

    [ -f "$work/manifest.json" ] || { rm -rf "$work" 2>/dev/null; return 1; }

    # Strip the downloaded-from-the-internet flag on OUR OWN extraction tree,
    # before anything is copied anywhere and long before anything runs. The
    # one-liner cannot reach these files - it never sees them, because this
    # function re-extracts the archive into a tree of its own - so this is the
    # only place it can be done, and without it Gatekeeper blocks the bridge
    # with a dialog the owner cannot act on. The Windows doer clears the
    # equivalent mark at the same point, for the same reason.
    xattr -dr com.apple.quarantine "$work" >/dev/null 2>&1 || true

    # The key set must match the real release exactly, before any hash is
    # checked. A loop that walks only the manifest's own keys can never notice
    # a binary the manifest simply omits: the one it does list gets verified
    # and installed, and the result is a silently incomplete install rather
    # than a refusal.
    local want_keys have_keys
    want_keys="$(printf '%s\n' $EXPECTED_BINARIES | sort | tr '\n' ' ')"
    have_keys="$(manifest_binary_keys "$work/manifest.json")"
    if [ "$want_keys" != "$have_keys" ]; then
        rm -rf "$work" 2>/dev/null
        return 1
    fi

    local name want actual
    for name in $EXPECTED_BINARIES; do
        [ -f "$work/$name" ] || { rm -rf "$work" 2>/dev/null; return 1; }
        want="$(sed -n "s/.*\"$name\"[[:space:]]*:[[:space:]]*\"\([0-9a-f]\{64\}\)\".*/\1/p" "$work/manifest.json" 2>/dev/null | head -1)"
        actual="$(file_sha256 "$work/$name")" || { rm -rf "$work" 2>/dev/null; return 1; }
        # Both sides must exist and the expected side must be a real hash, or
        # "" and "" compare equal and that counts as verified.
        is_sha256 "$want" || { rm -rf "$work" 2>/dev/null; return 1; }
        is_sha256 "$actual" || { rm -rf "$work" 2>/dev/null; return 1; }
        [ "$want" = "$actual" ] || { rm -rf "$work" 2>/dev/null; return 1; }
    done

    # All four directories, not just bin. The launcher changes into run/ and
    # the linked-device session lands there; the log path in the LaunchAgent
    # points into logs/, and launchd refuses to start a job whose log file it
    # cannot open.
    mkdir -p "$root/bin" "$root/run" "$root/logs" "$root/pairing" 2>/dev/null || { rm -rf "$work" 2>/dev/null; return 1; }

    # Verified first, moved second, and what already moved is rolled back on a
    # failure - so a half-populated bin/ is impossible rather than merely
    # unlikely.
    local moved='' done_name
    for name in $EXPECTED_BINARIES; do
        if ! mv "$work/$name" "$root/bin/$name" 2>/dev/null; then
            for done_name in $moved; do rm -f "$root/bin/$done_name" 2>/dev/null; done
            rm -rf "$work" 2>/dev/null
            return 1
        fi
        if ! chmod 0755 "$root/bin/$name" 2>/dev/null; then
            for done_name in $moved; do rm -f "$root/bin/$done_name" 2>/dev/null; done
            rm -f "$root/bin/$name" 2>/dev/null
            rm -rf "$work" 2>/dev/null
            return 1
        fi
        moved="$moved $name"
    done

    # Belt and braces on the mark: a move within one filesystem carries
    # extended attributes with the file, and the strip above already ran, but
    # this costs nothing and the failure it guards against is a dialog nobody
    # in the room can dismiss for them.
    xattr -dr com.apple.quarantine "$root/bin" >/dev/null 2>&1 || true

    # Last, so its presence keeps meaning "every binary verified and landed" -
    # never a partial set.
    if ! write_installed_json "$work/manifest.json" "$root/installed.json" "$pin"; then
        for done_name in $moved; do rm -f "$root/bin/$done_name" 2>/dev/null; done
        rm -rf "$work" 2>/dev/null
        return 1
    fi
    rm -rf "$work" 2>/dev/null
    return 0
}

install_skill() {
    # $1 the release zip.
    #
    # Lifts the repair skill out of the zip and writes it where the AI apps
    # read it. This is the only route the skill has onto an owner's Mac: it is
    # published to the public repository too, but that is somewhere a person
    # could go and find it, not somewhere a client will ever load it. Without
    # it, an owner whose WhatsApp stops working weeks from now is talking to an
    # assistant that has never heard of the four repair verbs and starts
    # improvising at somebody who has never opened a terminal.
    #
    # Nothing here may end an install. Every failure is a plain non-zero return
    # for the caller to note in the log and carry on: WhatsApp working with no
    # skill costs the owner a worse conversation later, WhatsApp not working
    # costs them the whole thing.
    #
    # Read from the zip rather than from install_binaries' extraction tree,
    # which is deleted inside that function and must not be depended on from
    # out here. unzip rather than ditto: only unzip can be asked for a single
    # member, and it is on every Mac. Silenced, because handed anything it does
    # not like it prints four lines about central directory signatures.
    local zip="${1:-}" dest dir
    [ -f "$zip" ] || return 1
    dest="$(claude_skill_path)"
    [ -n "$dest" ] || return 1

    dir="$(make_temp_dir)" || return 1
    if ! unzip -oq "$zip" "$SKILL_ZIP_ENTRY" -d "$dir" >/dev/null 2>&1; then
        rm -rf "$dir" 2>/dev/null
        return 1
    fi
    if [ ! -f "$dir/$SKILL_ZIP_ENTRY" ]; then
        rm -rf "$dir" 2>/dev/null
        return 1
    fi
    if ! mkdir -p "$(dirname "$dest")" 2>/dev/null; then
        rm -rf "$dir" 2>/dev/null
        return 1
    fi
    if ! cp "$dir/$SKILL_ZIP_ENTRY" "$dest" 2>/dev/null; then
        rm -rf "$dir" 2>/dev/null
        return 1
    fi
    # The same mark install_binaries clears on its own tree, for the same
    # reason: this came out of something downloaded from the internet.
    xattr -d com.apple.quarantine "$dest" >/dev/null 2>&1 || true
    rm -rf "$dir" 2>/dev/null
    return 0
}

binary_blocked() {
    # $1 root. The mark macOS attaches to anything downloaded. Left on, the
    # first run raises a dialog with two buttons, one of them wrong, in front
    # of somebody who was promised nothing would be asked of them.
    local root="${1:-}" name
    command -v xattr >/dev/null 2>&1 || return 1
    for name in $EXPECTED_BINARIES; do
        [ -f "$root/bin/$name" ] || continue
        if xattr -p com.apple.quarantine "$root/bin/$name" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# The pairing page
# ---------------------------------------------------------------------------

PHONE_STEPS="$(cat <<'STEPS'
        <li>Open WhatsApp on your phone</li>
        <li>On iPhone: tap <b>Settings</b>. On Android: tap the <b>three dots</b> at the top right.</li>
        <li>Tap <b>Linked Devices</b></li>
        <li>Tap <b>Link a Device</b></li>
STEPS
)"

# The fingerprint/face/PIN prompt fires AFTER tapping Link a Device, right
# before the camera opens - not before it. Telling the owner to expect it any
# earlier describes something that has not happened yet, to the audience most
# likely to read that as a sign something has already gone wrong. It is also
# the only non-action in the list, so it is a note between steps rather than a
# numbered step of its own.
FINGERPRINT_NOTE='<p class="calm">Your phone may ask for your fingerprint, face, or PIN next. That is normal.</p>'

pairing_body() {
    local state="${1:-waiting}" qr="${2:-}" code="${3:-}" or_block=''
    # Both routes on the one page, with an OR between them nobody can miss.
    #
    # The code used to be a different page, reached only after the square had
    # failed for ten minutes, and then briefly a line telling the owner to press
    # a key in a terminal - which is a terminal instruction in a flow that is
    # meant to happen on screen. The number is asked for before the browser
    # opens now, so both routes can be live from the first second and the owner
    # picks with their eyes instead of being asked anything.
    #
    # Steps 1-4 are shared and both routes restart at 5, because that is exactly
    # what the phone shows: the same four taps, then a fork.
    #
    # The leading newline lives in the block rather than in the page below it.
    # A bare $or_block on its own line leaves an empty line behind when there is
    # no code - and the two platforms then disagree, because this body is built
    # through a command substitution, which strips exactly that trailing blank
    # and PowerShell's here-string does not.
    if [ -n "$code" ]; then
        or_block="
$(cat <<ORBLOCK
      <p class="orbar">OR</p>
      <p class="calm">If your camera will not read the square:</p>
      <ol start="5">
        <li>Tap <b>Link with phone number</b></li>
        <li>Type the code below</li>
      </ol>
      <p class="code">$code</p>
      <p class="calm">If it runs out, a new one appears here by itself.</p>
ORBLOCK
)"
    fi
    case "$state" in
        qr)
            cat <<QRBODY
      <ol>
$PHONE_STEPS
      </ol>
      $FINGERPRINT_NOTE
      <ol start="5">
        <li>Point your phone at the square below</li>
      </ol>
      <img class="qr" src="data:image/png;base64,$qr" alt="Scan this with your phone">
      <p class="calm">This square refreshes by itself. You never need to hurry.</p>$or_block
QRBODY
            ;;
        code)
            cat <<CODEBODY
      <ol>
$PHONE_STEPS
      </ol>
      $FINGERPRINT_NOTE
      <ol start="5">
        <li>Tap <b>Link with phone number</b></li>
        <li>Type the code below</li>
      </ol>
      <p class="code">$code</p>
      <p class="calm">If it runs out, a new one appears here by itself.</p>
CODEBODY
            ;;
        syncing)
            cat <<'SYNCBODY'
      <p class="done">Connected</p>
      <p class="calm">Your WhatsApp is copying your recent conversations across.
      This can take a few minutes. You can leave this window open.</p>
SYNCBODY
            ;;
        syncing-timeout)
            # The phone genuinely linked - that part is true and stays true.
            # What is not true yet is "ready, you can close this window": the
            # wait for the first conversations gave up before a single one
            # showed up. Say what is actually happening instead of declaring
            # it done.
            cat <<'SYNCTIMEOUTBODY'
      <p class="done">Connected</p>
      <p class="calm">Your conversations are still copying across - this is
      taking a little longer than usual. You can close this window; the
      copying keeps going on its own.</p>
SYNCTIMEOUTBODY
            ;;
        error)
            # Written when something genuinely went wrong talking to this
            # computer's own WhatsApp connection - not "no code to show yet",
            # which is a normal moment covered by waiting/qr/code. It keeps
            # refreshing on purpose: the loop that wrote it is still trying,
            # and a working answer replaces this the moment one arrives.
            cat <<'ERRORBODY'
      <p class="calm">Something isn't working right now. This page will keep
      trying by itself. If it does not recover, ask your assistant for help.</p>
ERRORBODY
            ;;
        connected)
            cat <<'DONEBODY'
      <p class="done">Connected</p>
      <p class="calm">Your WhatsApp is ready. You can close this window.</p>
DONEBODY
            ;;
        timeout)
            cat <<'TIMEOUTBODY'
      <p class="calm">We stopped waiting. Ask your assistant to connect your
      WhatsApp again.</p>
TIMEOUTBODY
            ;;
        *)
            cat <<'WAITBODY'
      <p class="calm">Getting ready. This takes a few seconds.</p>
WAITBODY
            ;;
    esac
}

pairing_html() {
    # $1 state  $2 qr as base64  $3 pairing code
    #
    # A meta refresh, not scripting: the file is opened as a local file and a
    # fetch from there is blocked by the browser. The loop rewrites the whole
    # page every two seconds, which keeps the square live and flips it to
    # Connected with nothing running in the page at all.
    #
    # Three seconds, not two, on purpose. The write cadence and the refresh
    # cadence must not be the same number, or every reload is a coin toss
    # against the swap.
    local state="${1:-waiting}" refresh body
    case "$state" in
        connected|timeout|syncing-timeout) refresh='' ;;
        *) refresh='<meta http-equiv="refresh" content="3">' ;;
    esac
    body="$(pairing_body "$state" "${2:-}" "${3:-}")"
    cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
$refresh
<title>Connect your WhatsApp</title>
<style>
  body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
         background: #10241c; color: #f2f7f4; margin: 0;
         display: flex; align-items: center; justify-content: center;
         min-height: 100vh; text-align: center; }
  main { padding: 2rem; max-width: 30rem; }
  h1 { font-size: 1.6rem; font-weight: 600; }
  ol { text-align: left; line-height: 2; font-size: 1.05rem; margin: 1.5rem auto; max-width: 22rem; }
  .qr { width: 17rem; height: 17rem; background: #fff; padding: 1rem; border-radius: 8px; }
  .code { font-size: 2.6rem; letter-spacing: 0.3em; font-weight: 700; margin: 2rem 0; }
  .done { font-size: 2.2rem; font-weight: 700; color: #48cf98; }
  .calm { color: #9dbdb0; }
  .orbar { display: flex; align-items: center; gap: 1rem; margin: 2.5rem 0;
           color: #9dbdb0; font-weight: 700; letter-spacing: 0.2em; }
  .orbar::before, .orbar::after { content: ""; flex: 1; height: 1px; background: #2c4a3d; }
</style>
</head>
<body><main><h1>Connect your WhatsApp</h1>
$body
</main></body>
</html>
HTML
}

write_pairing_page() {
    # $1 root  $2 html
    #
    # Written beside the real file and moved into place. A truncate-then-write
    # leaves a reload reading zero bytes, and an empty document carries no
    # meta refresh - so the browser sits on a blank page for ever while the
    # loop behind it keeps writing squares nobody sees. Over a hundred
    # laptops refreshing every three seconds for several minutes each, that
    # window gets hit.
    local root="${1:-}" html="${2:-}"
    mkdir -p "$root/pairing" 2>/dev/null || return 1
    printf '%s' "$html" 2>/dev/null > "$root/pairing/pair.html.tmp" || return 1
    mv "$root/pairing/pair.html.tmp" "$root/pairing/pair.html" 2>/dev/null || return 1
    printf '%s' "$root/pairing/pair.html"
}

open_in_browser() {
    # A seam, so the acceptance suite can drive the whole loop without a
    # browser window opening on the implementer's machine every run.
    open "${1:-}" >/dev/null 2>&1 || true
    return 0
}

to_e164() {
    # The same rule as Windows, including the trunk zero after the country
    # code: "+60 012 345 6789" is what people write on a form, and 600123456789
    # is rejected by the bridge without saying why.
    local digits rest
    digits="$(printf '%s' "${1:-}" | tr -cd '0-9')"
    case "$digits" in
        60*)
            rest="${digits#60}"
            rest="${rest#0}"
            printf '60%s' "$rest"
            ;;
        0*) printf '60%s' "${digits#0}" ;;
        *)  printf '%s' "$digits" ;;
    esac
}

start_pairing_loop() {
    # $1 root  $2 port  $3 api key  $4 timeout seconds  $5 phone number
    #
    # 600, not 300. A first-time 60-plus Android owner reading these steps
    # cold - find the three-dot overflow menu (it is not in Settings), find
    # Linked Devices, get past whatever unlock prompt WhatsApp inserts, get a
    # clean scan - runs a genuine 100-230 seconds for one clean attempt with
    # nothing going wrong. Real friction can push somebody who was always
    # going to succeed past 300. The two failure directions are not
    # symmetric: too generous costs a person who was never going to link an
    # extra five minutes looking at a square that keeps refreshing itself
    # anyway, and they needed a human either way; too tight manufactures a
    # failure for someone who was about to succeed. Do not tidy this back down
    # by counting seconds instead of people.
    local root="${1:-}" port="${2:-}" key="${3:-}" timeout="${4:-600}" phone="${5:-}"
    local page token='' code='' code_at=0 opened=0 status=''
    local qr='' last_qr='' qr_changed_at=0 restarts=0 stalled http tmpdir qrfile
    local qr_stall_seconds=90 code_refresh_seconds=60 max_restarts=2
    local deadline=$(( $(date +%s) + timeout ))

    # Computed rather than taken from the write's return value, so the path
    # the browser is pointed at is known even if that very first write fails.
    page="$root/pairing/pair.html"
    write_pairing_page "$root" "$(pairing_html waiting '' '')" >/dev/null 2>&1

    # Fails closed, and the fallback that used to be here is why.
    #
    # A square is fetched as a file, and the current directory is where that
    # file used to land whenever a private directory could not be made -
    # which, under the one-liner, is the owner's own home folder. Somebody
    # else's home directory is not ours to leave a file in, and the only
    # machine that ever takes this branch is one that could not make a
    # temporary directory at all: out of disk, or a temporary folder that is
    # not writable. Neither is a state to start writing into $HOME on.
    #
    # Only the square needs it. The phone-number route asks the bridge for a
    # code and puts that straight on the page, so a run that was given a
    # number carries on exactly as before; a run that was not returns now,
    # which hands pair_with_fallback the one thing it can still offer this
    # owner instead of ten minutes of a page that can never fill in.
    tmpdir="$(make_temp_dir)" || tmpdir=''
    qrfile=''
    [ -z "$tmpdir" ] || qrfile="$tmpdir/qr.png"
    if [ -z "$qrfile" ] && [ -z "$phone" ]; then
        log_note "$root" 'pairing: no private directory was available for the square'
        return 1
    fi

    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ -z "$token" ]; then
            token="$(bridge_token "$port" "$key")"
        fi

        if [ -n "$token" ]; then
            status="$(pairing_status "$port" "$token")"
            if [ -z "$status" ]; then
                token=''
            elif json_flag_true "$status" 'logged_in'; then
                # Linked, but not ready. Say what is true and keep the window
                # useful rather than telling them to close it too early.
                write_pairing_page "$root" "$(pairing_html syncing '' '')" >/dev/null 2>&1
                [ "$opened" -eq 1 ] || { open_in_browser "$page"; opened=1; }

                # The answer matters. On a timeout, "Connected - you can close
                # this window" would tell the owner it is safe to walk away
                # while nothing has actually synced yet, which is the exact
                # dishonesty this wait exists to prevent. The phone genuinely
                # linked either way, so only which page gets written changes.
                if wait_first_chats "$port" "$token" 180; then
                    write_pairing_page "$root" "$(pairing_html connected '' '')" >/dev/null 2>&1
                else
                    write_pairing_page "$root" "$(pairing_html syncing-timeout '' '')" >/dev/null 2>&1
                fi

                # Recorded so the check verb can tell "still copying" from
                # "this owner genuinely has no conversations". A date and a
                # count of seconds, nothing else - the second field is there
                # because BSD has no way to parse the first one back without a
                # flag that does not exist here.
                printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(date +%s)" 2>/dev/null > "$root/linked-at.txt" || true
                [ -n "$tmpdir" ] && rm -rf "$tmpdir" 2>/dev/null
                return 0
            fi
        fi

        if [ -n "$token" ]; then
            # The code, when a number was given - fetched ALONGSIDE the square
            # rather than instead of it. /auth/pairing-qr and /auth/pair-phone
            # are independent on the bridge, so both routes can be live at once
            # and the owner picks with their eyes instead of being asked.
            #
            # Fetched once and cached forever used to be the bug: the page
            # promises "If it runs out, a new one appears here by itself", but
            # nothing ever cleared it, so a code that expired partway through a
            # ten-minute window just sat there looking valid.
            if [ -n "$phone" ]; then
                if [ -z "$code" ] || [ $(( $(date +%s) - code_at )) -ge "$code_refresh_seconds" ]; then
                    code="$(pairing_code "$port" "$token" "$phone")"
                    code_at="$(date +%s)"
                fi
            fi

            # The status code, not the exit status. A 410 is the normal
            # "nothing to show yet" - already linked, or pairing has not
            # started - and must not be mistaken for a fault. Everything
            # else IS a fault: an owner whose bridge is genuinely broken
            # otherwise sits looking at "Getting ready. This takes a few
            # seconds." for the whole ten-minute window, because nothing
            # ever tells the loop something is actually wrong.
            #
            # Guarded on qrfile: with a number in hand and no private directory
            # to write a square into, the code alone is still a working way in.
            qr=''
            if [ -n "$qrfile" ]; then
                http="$(curl -s -o "$qrfile" -w '%{http_code}' --max-time 10 \
                        -H "Authorization: Bearer $token" \
                        "http://127.0.0.1:$port/api/auth/pairing-qr" 2>/dev/null)"
                case "$http" in
                    200)
                        # base64 with no flags. There is no line-wrap flag
                        # here, and macOS emits one line anyway.
                        qr="$(base64 < "$qrfile" 2>/dev/null | tr -d '\n')"
                        ;;
                    410) : ;;
                    *) [ -n "$code" ] || write_pairing_page "$root" "$(pairing_html error '' '')" >/dev/null 2>&1 ;;
                esac
            fi

            if [ -n "$qr" ]; then
                # The bridge's QR goroutine never clears a timed-out
                # square: it keeps answering 200 with the same dead image
                # forever. Byte-identical output across consecutive
                # fetches for longer than a real rotation ever takes is
                # that stall, not a slow phone or a quiet moment. Ninety
                # seconds sits comfortably above the largest genuine gap
                # measured against the real binary (59.3 seconds, the very
                # first rotation).
                if [ "$qr" != "$last_qr" ]; then
                    last_qr="$qr"
                    qr_changed_at="$(date +%s)"
                fi
                stalled=$(( $(date +%s) - qr_changed_at ))
                if [ "$stalled" -ge "$qr_stall_seconds" ] && [ -n "$code" ]; then
                    # A dead square and a live code is not a fault, and it must
                    # not be treated as one: restarting the bridge would take
                    # the pairing session the code belongs to down with it and
                    # invalidate a code the owner may be halfway through
                    # typing. Drop the square, keep the code.
                    write_pairing_page "$root" "$(pairing_html code '' "$code")" >/dev/null 2>&1
                elif [ "$stalled" -ge "$qr_stall_seconds" ] && [ "$restarts" -lt "$max_restarts" ]; then
                    restarts=$((restarts + 1))
                    restart_bridge "$root" "$port" >/dev/null 2>&1
                    # A restarted bridge is a brand-new process talking a
                    # brand-new session: the old token is dead and an entirely
                    # fresh QR sequence begins. Nothing here was ever shown to
                    # a phone that could still act on it, so nothing is lost by
                    # starting over - but any code issued against the old
                    # session died with it, so it is cleared rather than left
                    # on screen looking valid.
                    token=''
                    last_qr=''
                    qr_changed_at=0
                    code=''
                    code_at=0
                elif [ "$stalled" -ge "$qr_stall_seconds" ]; then
                    # Restarts exhausted and the square is provably dead -
                    # say so rather than let it sit there looking alive
                    # for the rest of the window.
                    write_pairing_page "$root" "$(pairing_html error '' '')" >/dev/null 2>&1
                else
                    write_pairing_page "$root" "$(pairing_html qr "$qr" "$code")" >/dev/null 2>&1
                fi
            elif [ -n "$code" ]; then
                # A code in hand and no square yet, whether because the bridge
                # has none to give or because fetching it faulted. Either way
                # there is something the owner can act on, which beats both
                # "Getting ready" and an error page.
                write_pairing_page "$root" "$(pairing_html code '' "$code")" >/dev/null 2>&1
            fi
        fi

        # Opened once, on the first pass. A loop like this opens a new window
        # every two seconds if nobody stops it.
        [ "$opened" -eq 1 ] || { open_in_browser "$page"; opened=1; }

        sleep 2
    done

    # Never leave anything on screen that the owner might act on when nothing
    # is listening for the result. A stale square and a still-valid phone-link
    # code fail the same way: if they scan or type it after this loop has
    # given up, WhatsApp genuinely links their phone while the setup has moved
    # on - nothing runs the client registration or restarts the AI apps. A
    # linked phone and a half-configured machine, with no signal anything is
    # wrong, is worse than a clean stop and much harder to diagnose in a room
    # of a hundred people.
    write_pairing_page "$root" "$(pairing_html timeout '' '')" >/dev/null 2>&1
    [ -n "$tmpdir" ] && rm -rf "$tmpdir" 2>/dev/null
    return 1
}

# ---------------------------------------------------------------------------
# Client registration
# ---------------------------------------------------------------------------

backup_config_file() {
    # A fresh, timestamped copy every time, never only the first. Backing up
    # only the file's first-ever snapshot and always restoring THAT one
    # reverts every legitimate change made since - including a connector
    # installed afterwards by this same event. A rollback must only ever undo
    # what this run itself did.
    local path="${1:-}"
    [ -f "$path" ] || return 0
    local dir stamp base old
    dir="$(dirname "$path")/vimigo-backups"
    mkdir -p "$dir" 2>/dev/null || return 0
    base="$(basename "$path")"
    stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
    cp "$path" "$dir/$base.$stamp.bak" 2>/dev/null || true
    # The rollback copy this run will restore from, if it has to.
    cp "$path" "$path.vimigo-backup" 2>/dev/null || true

    # Five, and the rest go.
    #
    # Every verb backs up both client files, and the repair ladder rewrites
    # them on every rung it takes - so this is called several times in a
    # single repair, and every repair after that adds more. Nothing else on
    # the machine will ever tidy a folder called vimigo-backups sitting beside
    # the owner's own configuration, and nobody will ever open it. What a
    # rollback needs is this run's copy; what a helper needs is the last few.
    # A year of the rest is a pile.
    #
    # Newest first by name rather than by time: the stamp is UTC and sorts the
    # way it ran, so nothing here has to ask the filesystem for a date and
    # read it back with a flag BSD does not have. Only our own names are
    # matched, so anything else in that folder is nothing to do with us and is
    # left alone.
    ls -1 "$dir" 2>/dev/null |
        grep -E "^$base"'\.[0-9]{8}T[0-9]{6}Z\.bak$' |
        sort -r |
        tail -n +6 |
        while IFS= read -r old; do
            [ -n "$old" ] || continue
            rm -f "$dir/$old" 2>/dev/null || true
        done
    return 0
}

add_mcp_json() {
    # $1 config  $2 mcp binary  $3 api key  $4 port
    #
    # plutil ships on every Mac and edits JSON losslessly. Node is not
    # guaranteed to be present and neither is any other interpreter, so
    # neither is used here.
    local path="${1:-}" exe="${2:-}" key="${3:-}" port="${4:-}" name
    [ -n "$path" ] || return 1
    command -v plutil >/dev/null 2>&1 || return 1

    if [ ! -f "$path" ]; then
        mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
        printf '{}\n' 2>/dev/null > "$path" || return 1
    fi
    backup_config_file "$path"

    # Left exactly as found if it is not JSON we can read. The path is
    # deliberately never printed: it is the one thing a non-technical owner
    # cannot act on.
    plutil -lint "$path" >/dev/null 2>&1 || return 1

    for name in $MCP_ENTRY_NAME $STALE_MCP_NAMES; do
        plutil -remove "mcpServers.$name" "$path" >/dev/null 2>&1 || true
    done

    # Create the container ONLY if it is missing.
    #
    # Replacing the value at that keypath unconditionally is the trap here:
    # the intent is "create if missing", and an owner who ran the earlier
    # setup has other servers under mcpServers already. Overwrite it and they
    # are gone from Claude Desktop with no message at all, while Windows
    # preserves them - the two platforms behaving oppositely on the same
    # owner's data. An extract fails when the key is absent, so the insert
    # runs exactly then and never otherwise.
    if ! plutil -extract mcpServers xml1 -o /dev/null "$path" >/dev/null 2>&1; then
        plutil -insert mcpServers -json '{}' "$path" >/dev/null 2>&1 || return 1
    fi

    # Checked, not swallowed. An insert that fails on a document with no
    # mcpServers key left the setup printing success while no WhatsApp tools
    # appeared anywhere.
    if ! plutil -insert "mcpServers.$MCP_ENTRY_NAME" -json "{
        \"command\": \"$exe\",
        \"args\": [],
        \"env\": {
            \"WHATSAPP_API_KEY\": \"$key\",
            \"API_BASE_URL\": \"http://127.0.0.1:$port/api\",
            \"IS_HTTP\": \"false\",
            \"OWNER_MODE\": \"true\"
        }
    }" "$path" >/dev/null 2>&1; then
        [ -f "$path.vimigo-backup" ] && cp "$path.vimigo-backup" "$path" 2>/dev/null
        return 1
    fi

    # Read it back the way the app will read it. A write that lands as
    # something the app cannot parse is worse than no write at all, because
    # the app then loses every other server it had.
    if ! plutil -lint "$path" >/dev/null 2>&1; then
        [ -f "$path.vimigo-backup" ] && cp "$path.vimigo-backup" "$path" 2>/dev/null
        return 1
    fi
    plutil -extract "mcpServers.$MCP_ENTRY_NAME.command" raw -o - "$path" >/dev/null 2>&1 || {
        [ -f "$path.vimigo-backup" ] && cp "$path.vimigo-backup" "$path" 2>/dev/null
        return 1
    }
    return 0
}

remove_toml_section_tree() {
    # $1 file. Drops [mcp_servers.whatsapp] AND its sub-tables, leaving every
    # other section byte-identical.
    #
    # A line walker, deliberately. A pattern that stops at the next line
    # beginning with a bracket stops at OUR OWN [mcp_servers.whatsapp.env] -
    # so the old env table survives and a second one is appended on the very
    # next run. Two tables with the same name is a hard error: Codex refuses
    # the entire file, and the owner loses their model setting and their other
    # servers along with WhatsApp. The stale copy also carries the old port.
    #
    # A header is recognised by its leading bracket and the FIRST closing
    # bracket after it, never by how the line ends: "[mcp_servers.zo]  # my zo
    # connector" is a legal header carrying a trailing comment, and testing
    # what the line ends with rejects it outright - so the walker never stops
    # dropping and eats that server and the entire rest of the file with it.
    local file="${1:-}" tmp line trimmed name dropping=0
    [ -f "$file" ] || return 0
    # A file that is there but cannot be read has to stop this outright. The
    # loop below would read nothing at all, write an empty scratch file, and
    # move THAT over the owner's own configuration - every other server they
    # had, gone, and silently now that the reader's complaint is redirected.
    [ -r "$file" ] || return 1
    tmp="$file.vimigo-tmp"
    : 2>/dev/null > "$tmp" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "$trimmed" in
            \[*\]*)
                name="${trimmed#\[}"
                name="${name%%\]*}"
                dropping=0
                case "$name" in
                    mcp_servers.whatsapp|mcp_servers.whatsapp.*|\
                    mcp_servers.whatsapp-mcp|mcp_servers.whatsapp-mcp.*|\
                    mcp_servers.whatsapp-mcp-go|mcp_servers.whatsapp-mcp-go.*) dropping=1 ;;
                esac
                ;;
        esac
        [ "$dropping" -eq 1 ] || printf '%s\n' "$line" >> "$tmp"
    # On the whole loop, so the appends inside it are covered too.
    done 2>/dev/null < "$file"
    mv "$tmp" "$file" 2>/dev/null || return 1
    return 0
}

toml_other_headers() {
    # Every section header in the file that is not one of ours. The counts in
    # add_mcp_toml only look for OUR OWN table names, so on their own they are
    # blind by construction to a walker bug that eats somebody else's server.
    # This is the other half of that check.
    local file="${1:-}" line trimmed name
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "$trimmed" in
            \[*\]*)
                name="${trimmed#\[}"
                name="${name%%\]*}"
                case "$name" in
                    mcp_servers.whatsapp|mcp_servers.whatsapp.*|\
                    mcp_servers.whatsapp-mcp|mcp_servers.whatsapp-mcp.*|\
                    mcp_servers.whatsapp-mcp-go|mcp_servers.whatsapp-mcp-go.*) ;;
                    *) printf '%s\n' "$name" ;;
                esac
                ;;
        esac
    done 2>/dev/null < "$file"
    return 0
}

add_mcp_toml() {
    # $1 config  $2 mcp binary  $3 api key  $4 port
    local path="${1:-}" exe="${2:-}" key="${3:-}" port="${4:-}"
    [ -n "$path" ] || return 1
    mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
    [ -f "$path" ] || : 2>/dev/null > "$path" || return 1
    backup_config_file "$path"

    local before after lost
    before="$(toml_other_headers "$path")"

    remove_toml_section_tree "$path" || return 1
    cat 2>/dev/null >> "$path" <<TOML

[mcp_servers.whatsapp]
command = "$exe"
args = []

[mcp_servers.whatsapp.env]
WHATSAPP_API_KEY = "$key"
API_BASE_URL = "http://127.0.0.1:$port/api"
IS_HTTP = "false"
OWNER_MODE = "true"
TOML

    # The three things that actually go wrong, checked before success is
    # claimed: our section missing, a table defined twice, or a section the
    # owner already had quietly gone.
    after="$(toml_other_headers "$path")"
    lost=0
    local header
    # One header per line, never one per word.
    #
    # `for header in $before` splits the list on spaces and then globs each
    # piece, and [mcp_servers."my server"] is a perfectly legal header. Split
    # in two, neither half is found in the list taken afterwards, so a write
    # that lost nothing at all reports that it did: the rollback below then
    # puts the owner's file back exactly as it was - minus the WhatsApp they
    # just asked for - and the install ends on "one of your apps could not be
    # connected", over a space in somebody else's server name. A name holding
    # a star or a bracket goes the same way through the glob.
    #
    # Matched with -F as well as -x, for the other half of the same point: a
    # server name is text, not a pattern. Read as a pattern, a name with a dot
    # in it matches things it is not, and one with an unbalanced bracket is
    # not a legal pattern at all - grep refuses it, and that refusal reads as
    # "lost" too.
    while IFS= read -r header; do
        [ -n "$header" ] || continue
        printf '%s\n' "$after" | grep -qxF "$header" || { lost=1; break; }
    done <<< "$before"
    # Counted into variables and forced to a number first. A count taken
    # straight from a file that has gone missing is the empty string, and
    # `[ "" -ne 1 ]` is not a false comparison - it is bash printing "integer
    # expression expected", naming this file and a line number, on the owner's
    # screen. Nothing that cannot be counted may read as one.
    local n_head n_env
    n_head="$(grep -c '^\[mcp_servers.whatsapp\]$' "$path" 2>/dev/null)"
    n_env="$(grep -c '^\[mcp_servers.whatsapp.env\]$' "$path" 2>/dev/null)"
    case "$n_head" in ''|*[!0-9]*) n_head=0 ;; esac
    case "$n_env" in ''|*[!0-9]*) n_env=0 ;; esac
    if [ "$n_head" -ne 1 ] || [ "$n_env" -ne 1 ] ||
       [ "$lost" -ne 0 ]; then
        [ -f "$path.vimigo-backup" ] && cp "$path.vimigo-backup" "$path" 2>/dev/null
        return 1
    fi
    return 0
}

add_mcp_claude_code() {
    # $1 mcp binary  $2 api key  $3 port
    #
    # Claude Code owns its own configuration file and is the only thing that
    # may write it: it legitimately holds keys differing only by case, which a
    # round-trip through anything else either refuses or silently drops. The
    # CLI owns that file; we ask it.
    #
    # No CLI on this machine is a normal outcome, not a failure to shout
    # about: the caller reports "not registered" for this one client and
    # carries on.
    command -v claude >/dev/null 2>&1 || return 1

    claude mcp remove --scope user "$MCP_ENTRY_NAME" >/dev/null 2>&1 || true

    # The positional name comes BEFORE the options, and the command after a
    # bare double dash: options-before-name fails outright with a complaint
    # about a missing command argument, because the parser never recognises
    # anything after the dashes as the command at all.
    claude mcp add --scope user "$MCP_ENTRY_NAME" \
        -e "WHATSAPP_API_KEY=${2:-}" \
        -e "API_BASE_URL=http://127.0.0.1:${3:-}/api" \
        -e 'IS_HTTP=false' \
        -e 'OWNER_MODE=true' \
        -- "${1:-}" >/dev/null 2>&1 || return 1

    # Confirmed from the CLI's own view of its own file, never from ours. Both
    # the binary AND the owner-mode switch, never just the path: without that
    # switch the MCP server sends no instructions at all, and Claude Desktop -
    # which has no instruction file to fall back on - answers a 60-plus
    # business owner with raw chat IDs and tool names, and sends messages
    # without showing the words first.
    local listed
    listed="$(claude mcp get "$MCP_ENTRY_NAME" 2>&1)" || return 1
    printf '%s' "$listed" | grep -qF "${1:-}" || return 1
    printf '%s' "$listed" | grep -qF 'OWNER_MODE=true' || return 1
    return 0
}

add_mcp_everywhere() {
    # $1 mcp binary  $2 api key  $3 port
    #
    # Every return value is kept. A writer that failed silently is how a green
    # install and a client that has never heard of WhatsApp end up being the
    # same thing.
    local failed=0
    add_mcp_json "$(claude_desktop_config_path)" "${1:-}" "${2:-}" "${3:-}" || failed=1
    add_mcp_toml "$(codex_config_path)" "${1:-}" "${2:-}" "${3:-}" || failed=1
    if command -v claude >/dev/null 2>&1; then
        add_mcp_claude_code "${1:-}" "${2:-}" "${3:-}" || failed=1
    fi
    return "$failed"
}

unescaped_json_text() {
    # $1 file. Its text with the JSON escape taken back off every forward
    # slash.
    #
    # Claude Desktop's configuration is written by plutil, and the JSON writer
    # underneath it escapes forward slashes: the address that goes in as
    # http://127.0.0.1:8765/api can come back out spelled
    # http:\/\/127.0.0.1:8765\/api. Both are the same address and both are
    # legal JSON, and nothing here can promise which spelling a given version
    # of macOS writes. A plain search for the address as it was handed in
    # matches only one of the two.
    cat "${1:-}" 2>/dev/null | sed -e 's|\\/|/|g'
}

json_api_base_url_matches() {
    # $1 config  $2 the address the apps have to be carrying
    #
    # Read back through the same tool that wrote it wherever that tool exists,
    # and compared as a whole value rather than hunted for as a substring, so
    # the answer is about the value and not about one of the two ways it can be
    # spelled. Where plutil is absent, or will not answer, the file's own text
    # is unescaped first and both spellings then read the same.
    #
    # This is not a tidy-up. Get it wrong in the direction the plain search got
    # it wrong and a perfect install reports out-of-date app settings: the
    # ladder rewrites the same file twice, closes and reopens Claude Desktop
    # twice, and finishes on "I could not fix this one. Please contact Vimigo
    # support." in front of an owner whose WhatsApp is working.
    local path="${1:-}" want="${2:-}" value=''
    [ -f "$path" ] || return 1
    if command -v plutil >/dev/null 2>&1; then
        value="$(plutil -extract "mcpServers.$MCP_ENTRY_NAME.env.API_BASE_URL" raw -o - "$path" 2>/dev/null)"
        # An answer is an answer, right or wrong. Only silence - no plutil, a
        # key that is not there, a refusal - falls through to the text below.
        if [ -n "$value" ]; then
            [ "$value" = "$want" ]
            return $?
        fi
    fi
    unescaped_json_text "$path" | grep -qF "$want"
}

client_registration_state() {
    # $1 port  $2 api key. Prints exactly one of: ok, missing, stale.
    #
    # A Claude Desktop update resets its config; a write can fail; a port
    # change can rewrite some files and not others. The bridge is up and
    # linked through all of that, so the check said "Your WhatsApp is
    # connected." while no client could see a single WhatsApp tool - the exact
    # symptom the skill's trigger list names first, and the one most easily
    # fixed.
    local port="${1:-}" key="${2:-}" missing=0 stale=0 path text want
    for path in "$(claude_desktop_config_path)" "$(codex_config_path)"; do
        if [ ! -f "$path" ]; then missing=1; continue; fi
        text="$(unescaped_json_text "$path")"
        case "$path" in
            *.toml) printf '%s' "$text" | grep -q 'mcp_servers.whatsapp' || { missing=1; continue; } ;;
            *)      printf '%s' "$text" | grep -q '"whatsapp"' || { missing=1; continue; } ;;
        esac
        # The address is the one field an Apple tool decides the spelling of,
        # so it is the one field asked for by name rather than searched for.
        case "$path" in
            *.toml) printf '%s' "$text" | grep -qF "http://127.0.0.1:$port/api" || stale=1 ;;
            *)      json_api_base_url_matches "$path" "http://127.0.0.1:$port/api" || stale=1 ;;
        esac
        for want in "$key" 'OWNER_MODE'; do
            printf '%s' "$text" | grep -qF "$want" || { stale=1; break; }
        done
    done

    # Not installed is not broken. Only a client that exists can be missing
    # its entry.
    if command -v claude >/dev/null 2>&1; then
        if text="$(claude mcp get "$MCP_ENTRY_NAME" 2>&1)"; then
            for want in "http://127.0.0.1:$port/api" "$key" 'OWNER_MODE'; do
                printf '%s' "$text" | grep -qF "$want" || { stale=1; break; }
            done
        else
            missing=1
        fi
    fi

    if [ "$missing" -ne 0 ]; then printf 'missing'; return 0; fi
    if [ "$stale" -ne 0 ]; then printf 'stale'; return 0; fi
    printf 'ok'
    return 0
}

restart_ai_clients() {
    # Only apps that were already running are restarted. Launching an app the
    # owner had closed is a surprise, and surprises get reported as faults.
    #
    # pkill, never an Apple Event. Driving another app by Apple Event triggers
    # a "Terminal wants access to control Claude" prompt mid-install, which is
    # a security decision the audience rule says the owner cannot be asked to
    # make - and "Don't Allow" is remembered, so the client is never
    # restarted, never re-reads the config it was just given, and the failure
    # is invisible. pkill needs no automation permission at all. Opening an
    # app that is still running is a no-op, which is the other half of why the
    # naive version did nothing.
    local app waited
    for app in Claude ChatGPT; do
        pgrep -x "$app" >/dev/null 2>&1 || continue

        printf '  Closing %s and opening it again, so it picks this up.\n' "$app"
        pkill -x "$app" >/dev/null 2>&1 || true

        waited=0
        while pgrep -x "$app" >/dev/null 2>&1 && [ "$waited" -lt 15 ]; do
            sleep 1
            waited=$((waited + 1))
        done

        open -a "$app" >/dev/null 2>&1 || true
        sleep 3
        # Never left as "it worked" when it did not.
        pgrep -x "$app" >/dev/null 2>&1 || \
            printf '  Please close %s completely and open it again.\n' "$app"
    done
    return 0
}

# ---------------------------------------------------------------------------
# The AI rules block
# ---------------------------------------------------------------------------

marked_block_wellformed() {
    # $1 file. True when the file holds either no marker at all, or exactly
    # one matched pair in the right order.
    #
    # A malformed pair - an orphaned start, an orphaned end, more than one of
    # either, or an end before its start - can follow an interrupted write or
    # a manual edit. There is no reliable way to tell a truncated copy of OUR
    # OWN block from the owner's own prose that happens to quote the marker,
    # and guessing wrong means deleting their notes. So: touch nothing.
    local file="${1:-}" starts ends first_start first_end
    [ -f "$file" ] || return 0
    starts="$(grep -cF "$RULES_START" "$file" 2>/dev/null)"
    ends="$(grep -cF "$RULES_END" "$file" 2>/dev/null)"
    # Anything that is not a number is not a count. A file that cannot be read
    # gives back the empty string here, and comparing that as a number is bash
    # printing "integer expression expected" - this file's name, a line number
    # and all - to somebody who has just been promised nothing would be asked
    # of them. Unreadable therefore reads as "do not touch it", which is what
    # the whole function is for.
    case "$starts" in ''|*[!0-9]*) return 1 ;; esac
    case "$ends" in ''|*[!0-9]*) return 1 ;; esac
    [ "$starts" -eq 0 ] && [ "$ends" -eq 0 ] && return 0
    [ "$starts" -eq 1 ] && [ "$ends" -eq 1 ] || return 1
    first_start="$(grep -nF "$RULES_START" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
    first_end="$(grep -nF "$RULES_END" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
    case "$first_start" in ''|*[!0-9]*) return 1 ;; esac
    case "$first_end" in ''|*[!0-9]*) return 1 ;; esac
    [ "$first_start" -lt "$first_end" ]
}

remove_marked_block() {
    # $1 file. Writes to a temp file beside it and moves that into place: an
    # in-place stream edit here eats the next argument as a backup suffix and
    # errors out with a message about an invalid command code.
    #
    # Removal is the exact inverse of what set_ai_rules_block appends - the
    # marker lines and everything between them, nothing else - so the file
    # comes back byte for byte as it was before the block was ever added.
    local file="${1:-}" tmp line dropping=0
    [ -f "$file" ] || return 0
    # Same reason remove_toml_section_tree checks it: a file that is there but
    # cannot be read would come through the loop below as nothing at all, and
    # the move at the end would replace the owner's own notes with an empty
    # file.
    [ -r "$file" ] || return 1
    marked_block_wellformed "$file" || return 1
    tmp="$file.vimigo-tmp"
    : 2>/dev/null > "$tmp" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$dropping" -eq 1 ]; then
            [ "$line" = "$RULES_END" ] && dropping=0
            continue
        fi
        if [ "$line" = "$RULES_START" ]; then
            dropping=1
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    # On the whole loop, so the appends inside it are covered too.
    done 2>/dev/null < "$file"
    mv "$tmp" "$file" 2>/dev/null || return 1
    return 0
}

set_ai_rules_block() {
    # $1 file. Their own memory file, and Claude Code reads it every session,
    # so everything already in it survives untouched.
    local file="${1:-}"
    [ -n "$file" ] || return 1
    mkdir -p "$(dirname "$file")" 2>/dev/null || return 1
    if [ -f "$file" ]; then
        backup_config_file "$file"
        remove_marked_block "$file" || return 1
        # Only ever appended after a final newline, so a file that did not end
        # with one does not get our marker welded onto the end of their last
        # sentence.
        if [ -s "$file" ] && [ -n "$(tail -c 1 "$file" 2>/dev/null)" ]; then
            printf '\n' 2>/dev/null >> "$file" || return 1
        fi
    else
        : 2>/dev/null > "$file" || return 1
    fi
    printf '%s\n%s\n%s\n' "$RULES_START" "$AI_RULES" "$RULES_END" 2>/dev/null >> "$file"
}

remove_ai_rules_block() {
    remove_marked_block "${1:-}"
}

# ---------------------------------------------------------------------------
# The check
# ---------------------------------------------------------------------------

history_arrived() {
    # $1 root  $2 port  $3 api key
    #
    # logged_in flips the moment the phone links, and a full sync over 365
    # days keeps ingesting for minutes afterwards while the status endpoint
    # exposes no progress at all. Saying OK inside that window is how the demo
    # question - "what did Ali say last week?" - gets a confident "nothing
    # new" in front of a hundred people.
    #
    # Bounded by the moment pairing succeeded, so an owner who genuinely has
    # no conversations is not stuck reporting "still copying" for ever. Every
    # unreadable case fails open: a check that cannot answer must not invent a
    # fault.
    local root="${1:-}" port="${2:-}" key="${3:-}" linked token n
    [ -f "$root/linked-at.txt" ] || return 0
    linked="$(cut -d' ' -f2 < "$root/linked-at.txt" 2>/dev/null | head -1)"
    case "$linked" in
        ''|*[!0-9]*) return 0 ;;
    esac
    [ $(( $(date +%s) - linked )) -lt 900 ] || return 0

    token="$(bridge_token "$port" "$key")"
    [ -n "$token" ] || return 0
    n="$(chat_count "$port" "$token")"
    case "$n" in
        ''|-1) return 0 ;;
    esac
    [ "$n" -gt 0 ] 2>/dev/null && return 0
    return 1
}

doctor_fix_message() {
    # The sentence the ladder prints as a rung actually starts. Kept apart
    # from the sentence the check prints, because a read-only check that
    # promises an action - "Putting them back." - tells the owner twice that a
    # fix is under way, and they may land on "contact Vimigo support" having
    # believed it was already handled.
    case "${1:-}" in
        WA-01) printf 'Putting the missing pieces back now.' ;;
        WA-02) printf 'Clearing that now.' ;;
        WA-03) printf 'Moving your WhatsApp to a different connection now.' ;;
        WA-04) printf 'Setting it to start with this computer now.' ;;
        WA-05) printf 'Starting it now.' ;;
        WA-06) printf 'Trying again now.' ;;
        WA-07) printf 'Putting its settings back now.' ;;
        WA-09) printf 'Connecting them now.' ;;
        WA-10) printf 'Updating them now.' ;;
        WA-11) printf 'Waiting for your conversations to finish copying.' ;;
        *) printf '' ;;
    esac
}

doctor_state() {
    # $1 root. Prints <CODE>|<message>|<human 0 or 1> on one line.
    #
    # A machine string, consumed only by format_doctor_line and fix_ladder,
    # and NEVER printed to anyone. `human` is literally 0 or 1, never
    # true/false: a P code read as auto-fixable loops the ladder three times
    # over something only the owner can do on their phone.
    local root="${1:-}" name port key status regs

    for name in $EXPECTED_BINARIES; do
        if [ ! -f "$root/bin/$name" ]; then
            printf 'WA-01|Some pieces of your WhatsApp are missing.|0'
            return 0
        fi
    done
    if binary_blocked "$root"; then
        printf "WA-02|Your computer's security is holding your WhatsApp back.|0"
        return 0
    fi

    # Its own code, not WA-01. install_binaries writes the two binaries and
    # installed.json and never writes the launcher or the LaunchAgent, so a
    # WA-01 rung cannot clear this condition: it would download 28 MB on venue
    # wifi, change nothing, and do it twice more before reporting failure.
    port="$(read_agent_value "$LAUNCH_AGENT_PLIST" PORT)"
    key="$(read_agent_value "$LAUNCH_AGENT_PLIST" WHATSAPP_API_KEY)"
    if [ ! -f "$root/bin/start-bridge.sh" ] || [ ! -f "$LAUNCH_AGENT_PLIST" ] ||
       [ -z "$port" ] || [ -z "$key" ]; then
        printf 'WA-07|Your WhatsApp lost its settings.|0'
        return 0
    fi

    if ! autostart_registered; then
        printf 'WA-04|Your WhatsApp is not set to start with this computer.|0'
        return 0
    fi

    if ! bridge_reachable "$port"; then
        printf 'WA-05|Your WhatsApp is not running.|0'
        return 0
    fi

    status="$(auth_status "$port" "$key")"
    if [ -z "$status" ]; then
        # Something is on the port and it will not identify itself as us. A
        # restart cannot help: the bridge does not exit when it fails to bind,
        # so restarting it three times just leaves the squatter in place. The
        # port has to move, and everything that carries the port has to move
        # with it.
        printf 'WA-03|Something else on this computer is using the connection your WhatsApp needs.|0'
        return 0
    fi

    # Order matters, and this order is the fix. When WhatsApp unlinks the
    # device - the owner removed it, or the phone was offline long enough -
    # the client logs out AND closes the socket, so connected is false and
    # pairing_required is true at the same time. Testing connected first turns
    # the commonest real failure in the room into "cannot reach the internet",
    # kills and restarts a healthy bridge three times, and never says the one
    # thing the owner actually has to do.
    if json_flag_true "$status" 'pairing_required' || ! json_flag_true "$status" 'logged_in'; then
        printf 'P-01|Open WhatsApp on your phone and scan the square on screen.|1'
        return 0
    fi
    if ! json_flag_true "$status" 'connected'; then
        printf 'WA-06|Your WhatsApp cannot reach the internet.|0'
        return 0
    fi

    regs="$(client_registration_state "$port" "$key")"
    if [ "$regs" = 'missing' ]; then
        printf 'WA-09|Your apps cannot see your WhatsApp yet.|0'
        return 0
    fi
    if [ "$regs" = 'stale' ]; then
        printf 'WA-10|Your apps have out-of-date WhatsApp settings.|0'
        return 0
    fi

    if ! history_arrived "$root" "$port" "$key"; then
        printf 'WA-11|Your WhatsApp is connected and is still copying your recent conversations across.|0'
        return 0
    fi

    printf 'OK|Your WhatsApp is connected.|0'
    return 0
}

format_doctor_line() {
    # $1 the machine string. Prints the message and nothing else - never the
    # pipe-delimited string itself, and never the code appended in brackets.
    # The code is jargon with no meaning and no action to a 60-plus owner, and
    # the rules block forbids showing it at the same moment the skill tells
    # the AI to relay this exact sentence. The dispatch prints the code on its
    # own second line, and the skill says that line is for the AI.
    printf '%s\n' "$(printf '%s' "${1:-}" | cut -d'|' -f2)"
}

# ---------------------------------------------------------------------------
# The repair ladder
# ---------------------------------------------------------------------------

get_installed_secrets() {
    # $1 root. Prints "<api key> <jwt secret>".
    #
    # The LaunchAgent is the only place the key lives, so a missing one
    # normally means minting a new one - and a new key with three client
    # configs still carrying the old one is rejected on every tool call, which
    # looks exactly like a broken install. The client configs hold the key
    # too, so it can usually be recovered and nothing has to change.
    #
    # The JWT secret is not recovered and does not need to be: it only signs
    # tokens this bridge issues and verifies itself, and every caller logs in
    # again straight afterwards.
    local root="${1:-}" key='' jwt='' path
    key="$(read_agent_value "$LAUNCH_AGENT_PLIST" WHATSAPP_API_KEY)"
    jwt="$(read_agent_value "$LAUNCH_AGENT_PLIST" WHATSAPP_JWT_SECRET)"
    if [ -n "$key" ] && [ -n "$jwt" ]; then
        printf '%s %s' "$key" "$jwt"
        return 0
    fi
    if [ -z "$key" ]; then
        path="$(claude_desktop_config_path)"
        if [ -f "$path" ]; then
            key="$(sed -n 's/.*"WHATSAPP_API_KEY"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{64\}\)".*/\1/p' "$path" 2>/dev/null | head -1)"
        fi
    fi
    [ -n "$key" ] || key="$(new_secret)"
    printf '%s %s' "$key" "$(new_secret)"
}

update_bridge_wiring() {
    # $1 root  $2 "newport" to move off the current port
    #
    # Five things carry the port and the key: the launcher, the LaunchAgent,
    # and three client configs. They are rewritten here, in one function,
    # because that is the only way they cannot drift - a rewrite that touches
    # some and not others leaves clients pointing at a port nothing is
    # listening on, which the check happily reads as healthy.
    #
    # Nothing under run/ is read, written, moved or deleted anywhere in here.
    local root="${1:-}" newport="${2:-}" secrets key jwt port=0 ok=0
    secrets="$(get_installed_secrets "$root")"
    key="${secrets%% *}"
    jwt="${secrets##* }"

    if [ "$newport" != 'newport' ]; then
        port="$(read_agent_value "$LAUNCH_AGENT_PLIST" PORT)"
        case "$port" in ''|*[!0-9]*) port=0 ;; esac
    fi

    # Stopped before a port is chosen, so our own bridge is never mistaken for
    # something occupying the band - and so nothing is holding a binary.
    suspend_bridge "$root" >/dev/null 2>&1

    if [ "$port" -le 0 ]; then
        port="$(free_port)" || port=''
    fi
    if [ -z "$port" ]; then
        resume_bridge "$root" "" "" >/dev/null 2>&1
        return 1
    fi

    # Silenced at the call as well as inside each of them. Every one of these
    # is guarded internally, and this is the belt to that pair of braces: the
    # repair ladder is the one path an owner reaches with something already
    # wrong on the machine, so it is the likeliest place for a writer to meet
    # a disk with nothing left on it.
    write_bridge_launcher "$root/bin/start-bridge.sh" 2>/dev/null || ok=1
    write_launch_agent "$LAUNCH_AGENT_PLIST" "$root/bin/start-bridge.sh" "$root/run" "$key" "$jwt" "$port" 2>/dev/null || ok=1
    register_autostart "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || \
        log_note "$root" 'autostart: launchd would not take the agent'
    add_mcp_everywhere "$root/bin/whatsapp-mcp" "$key" "$port" 2>/dev/null || ok=1
    restart_ai_clients

    resume_bridge "$root" "$port" "$key" >/dev/null 2>&1 || ok=1
    return "$ok"
}

fix_ladder() {
    # $1 root  $2 max rounds  $3 budget seconds
    #
    # A wrapper around the rungs, and it exists for one line: the download the
    # ladder may fetch for itself has to go however the ladder ends. The rungs
    # below leave by seven different routes - a healthy machine, a code only
    # the owner can clear, a code nobody wrote a rung for, a rung that changed
    # nothing, the round budget, the clock, and the grace period at the end -
    # and a cleanup written at each of them is a cleanup that will be missed
    # by the eighth.
    local status=0
    FETCHED_RELEASE_ZIP=''
    # The one place a repair reliably passes through, and a repair is the one
    # thing that runs on a machine where the watchdog may have been restarting
    # a bridge that cannot start for weeks. Silent, and it cannot fail.
    trim_bridge_log "${1:-}"
    fix_ladder_rungs "$@" || status=1
    discard_release_zip "$FETCHED_RELEASE_ZIP"
    FETCHED_RELEASE_ZIP=''
    return "$status"
}

fix_ladder_rungs() {
    # $1 root  $2 max rounds  $3 budget seconds
    local root="${1:-}" max_rounds="${2:-3}" budget_seconds="${3:-600}"
    local zip='' last_code='' state='' code='' after='' after_code='' changed
    local port key regs deadline

    LADDER_ROUNDS=0
    deadline=$(( $(date +%s) + budget_seconds ))

    while [ "$LADDER_ROUNDS" -lt "$max_rounds" ]; do
        [ "$(date +%s)" -lt "$deadline" ] || break
        LADDER_ROUNDS=$((LADDER_ROUNDS + 1))

        state="$(doctor_state "$root" 2>/dev/null)"
        code="$(printf '%s' "$state" | cut -d'|' -f1)"

        # Neither of these is a fault. Nothing is broken; history is still
        # landing.
        case "$code" in
            OK|WA-11) return 0 ;;
        esac

        port="$(read_agent_value "$LAUNCH_AGENT_PLIST" PORT)"
        key="$(read_agent_value "$LAUNCH_AGENT_PLIST" WHATSAPP_API_KEY)"

        # One plain sentence before anything happens. Without it the terminal
        # shows nothing for anything from twenty seconds to several minutes,
        # and the documented reaction to a frozen window is to close it or
        # press keys - which kills the repair mid-way and can leave a
        # half-written config behind.
        printf '\n'
        local said
        said="$(doctor_fix_message "$code")"
        [ -n "$said" ] || said="$(printf '%s' "$state" | cut -d'|' -f2)"
        printf '  %s\n' "$said"

        if [ "$(printf '%s' "$state" | cut -d'|' -f3)" = '1' ]; then
            # A human code is not "give up". The ladder can still do the one
            # automatic thing it requires: write the page and open it.
            # Returning straight away left "scan the square on screen" with no
            # square anywhere. But it never loops: three rounds of killing a
            # healthy bridge over something only the owner can do on their
            # phone is exactly what this guard exists to prevent.
            #
            # Through the fallback, not the bare loop. Repair is where an owner
            # whose camera cannot read a QR ends up - it is what put the square
            # back after their first attempt failed - so it is the last place
            # that should be able to offer only a square.
            if pair_with_fallback "$root" "$port" "$key"; then
                continue
            fi
            return 1
        fi

        changed=1
        case "$code" in
            WA-01)
                if [ -z "$zip" ]; then
                    zip="$(get_release_zip "$root" '' 2>/dev/null)" || zip=''
                    # Recorded, so the wrapper can remove it whichever way the
                    # ladder ends. Kept in $zip as well, because a later round
                    # that needs it again must not pull 28 MB over venue wifi
                    # a second time.
                    FETCHED_RELEASE_ZIP="$zip"
                fi
                if [ -n "$zip" ]; then
                    suspend_bridge "$root" >/dev/null 2>&1
                    install_binaries "$zip" "$root" "$(file_sha256 "$zip")" 2>/dev/null || changed=0
                    update_bridge_wiring "$root" '' 2>/dev/null || true
                else
                    changed=0
                fi
                ;;
            WA-02)
                xattr -dr com.apple.quarantine "$root/bin" >/dev/null 2>&1 || true
                if binary_blocked "$root"; then
                    if [ -z "$zip" ]; then
                        zip="$(get_release_zip "$root" '' 2>/dev/null)" || zip=''
                        FETCHED_RELEASE_ZIP="$zip"
                    fi
                    if [ -n "$zip" ]; then
                        suspend_bridge "$root" >/dev/null 2>&1
                        install_binaries "$zip" "$root" "$(file_sha256 "$zip")" 2>/dev/null || changed=0
                        update_bridge_wiring "$root" '' 2>/dev/null || true
                    else
                        changed=0
                    fi
                fi
                ;;
            WA-03) update_bridge_wiring "$root" 'newport' 2>/dev/null || true ;;
            WA-04) register_autostart "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || changed=0 ;;
            WA-05)
                register_autostart "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
                if [ -n "$port" ] && [ -n "$key" ]; then
                    wait_bridge_answering "$port" "$key" 90 || changed=0
                else
                    changed=0
                fi
                ;;
            WA-06)
                suspend_bridge "$root" >/dev/null 2>&1
                if [ -n "$port" ] && [ -n "$key" ]; then
                    resume_bridge "$root" "$port" "$key" >/dev/null 2>&1 || changed=0
                else
                    changed=0
                fi
                ;;
            WA-07|WA-09|WA-10) update_bridge_wiring "$root" '' 2>/dev/null || true ;;
            *)
                # An unhandled code stops the ladder. Falling through and
                # looping means three rounds of doing nothing, several minutes
                # of silence, and then a failure report.
                return 1
                ;;
        esac

        after="$(doctor_state "$root" 2>/dev/null)"
        after_code="$(printf '%s' "$after" | cut -d'|' -f1)"

        # A rung that did not clear the round's condition has not made
        # progress.
        if [ "$after_code" = "$code" ]; then
            if [ "$changed" -eq 0 ] || [ "$code" = "$last_code" ]; then break; fi
        fi
        last_code="$code"
    done

    # The same grace period the rungs get. Reporting failure against a machine
    # that is thirty seconds from healthy is how a working install ends up at
    # "contact Vimigo support".
    port="$(read_agent_value "$LAUNCH_AGENT_PLIST" PORT)"
    key="$(read_agent_value "$LAUNCH_AGENT_PLIST" WHATSAPP_API_KEY)"
    if [ -n "$port" ] && [ -n "$key" ]; then
        wait_bridge_answering "$port" "$key" 60 >/dev/null 2>&1 || true
    fi
    code="$(doctor_state "$root" 2>/dev/null | cut -d'|' -f1)"
    case "$code" in
        OK|WA-11) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# The verbs
# ---------------------------------------------------------------------------

OWNER_PHONE=''

read_owner_phone_number() {
    # Asked once, before the browser opens.
    #
    # It used to be asked only after the square had already failed for its full
    # ten minutes, which is ten minutes of somebody looking at a square their
    # camera is never going to read. Asked first, the code can be on the page
    # beside the square from the first second, and nobody has to discover that
    # a second route exists - both are simply there.
    #
    # An answer is not required. Skip it and the page shows the square alone,
    # exactly as it always did.
    #
    # Fails closed with no keyboard attached: an empty answer must never
    # become an empty phone number posted to the bridge, which fails in a way
    # nobody can see. This is also why the one-liner hands this script a real
    # terminal.
    OWNER_PHONE=''
    [ -t 0 ] || return 0
    printf '\n'
    printf '  What is the WhatsApp number on this phone?\n'
    printf '  It lets us put a code on screen as well as a square, in case\n'
    printf '  your camera will not read the square. Press Enter to skip.\n'
    printf '  Your WhatsApp number: '
    local answer=''
    IFS= read -r answer || answer=''
    OWNER_PHONE="$answer"
    return 0
}

pair_with_fallback() {
    # $1 root  $2 port  $3 api key
    #
    # One window, not two. The number is asked for first and handed straight to
    # the loop, so the square and the code go up together and the owner never
    # has to run out of one to be offered the other.
    #
    # An answer with no digits in it converts to nothing at all - the same
    # shape an empty answer already is, and is treated the same way: the square
    # alone, rather than a window spent posting a number the bridge can only
    # reject.
    local root="${1:-}" port="${2:-}" key="${3:-}" e164=''
    read_owner_phone_number
    [ -z "$OWNER_PHONE" ] || e164="$(to_e164 "$OWNER_PHONE")"
    start_pairing_loop "$root" "$port" "$key" 600 "$e164"
}

fresh_install() {
    # $1 root  $2 zip path  $3 the zip's verified sha256
    #
    # A wrapper around the steps, for the same one reason fix_ladder has one:
    # a download this function fetched for itself has to go however the
    # install ends, and the steps below end at seven different returns - one
    # of them ten minutes later, after somebody walked away from the square.
    #
    # Only ever what THIS function fetched. The ordinary path is handed a zip
    # by the one-liner, which made that file and removes it itself; touching
    # it from here would be reaching into somebody else's temporary directory.
    local status=0
    FETCHED_RELEASE_ZIP=''
    # A first install has nothing to trim. A start-over on a machine that has
    # been restarting a bridge which cannot start does, and it arrives here.
    trim_bridge_log "${1:-}"
    fresh_install_steps "$@" || status=1
    discard_release_zip "$FETCHED_RELEASE_ZIP"
    FETCHED_RELEASE_ZIP=''
    return "$status"
}

fresh_install_steps() {
    # $1 root  $2 zip path  $3 the zip's verified sha256
    local root="${1:-}" zip="${2:-}" pin="${3:-}" key jwt port record

    printf '\n'
    printf '  Setting up your WhatsApp. This takes a few minutes.\n'

    if [ -z "$zip" ]; then
        zip="$(get_release_zip "$root" "$pin" 2>/dev/null)" || zip=''
        FETCHED_RELEASE_ZIP="$zip"
        if [ -z "$zip" ]; then
            printf '\n'
            printf '  Something went wrong setting up your WhatsApp. Please contact Vimigo support.\n'
            return 1
        fi
    fi

    # Whatever pin this zip was actually checked against, real 64-hex or not:
    # computed fresh from the file on disk when the caller did not hand one
    # in, so installed.json always ends up carrying the truth about the bytes
    # just verified, not merely whatever a caller remembered to pass.
    record="$pin"
    is_sha256 "$record" || record="$(file_sha256 "$zip")" || record=''

    # Every writer below is silenced at the call as well as inside itself.
    # This is the shape the Windows doer gets from wrapping the whole of its
    # fresh install in one try/catch: the sentences here are the only thing
    # this owner may ever see, and an errno printed underneath one of them -
    # naming a folder they have never heard of - is the failure this guards
    # against, not the failure it reports.
    if ! install_binaries "$zip" "$root" "$record" 2>/dev/null; then
        printf '\n'
        printf '  Something went wrong setting up your WhatsApp. Please contact Vimigo support.\n'
        return 1
    fi

    # After, not before. Said first, a download that arrived corrupt - the
    # commonest failure on venue wifi - reads as "Putting the pieces in place."
    # followed immediately by "Something went wrong", which tells the owner
    # something was under way when nothing was. The line before it already
    # said this takes a few minutes, so nothing is silent in the meantime.
    # (The Windows doer still says it first; its whole install sits inside one
    # try/catch, so the same two lines appear there in the same order. Worth
    # moving there too.)
    printf '  Putting the pieces in place.\n'

    key="$(new_secret)"
    jwt="$(new_secret)"
    port="$(free_port)" || port=''
    if [ -z "$key" ] || [ -z "$jwt" ] || [ -z "$port" ]; then
        printf '\n'
        printf '  Something went wrong setting up your WhatsApp. Please contact Vimigo support.\n'
        return 1
    fi

    printf '  Setting it to start with this computer.\n'
    if ! write_bridge_launcher "$root/bin/start-bridge.sh" 2>/dev/null ||
       ! write_launch_agent "$LAUNCH_AGENT_PLIST" "$root/bin/start-bridge.sh" "$root/run" "$key" "$jwt" "$port" 2>/dev/null; then
        printf '\n'
        printf '  Something went wrong setting up your WhatsApp. Please contact Vimigo support.\n'
        return 1
    fi
    register_autostart "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || \
        log_note "$root" 'autostart: launchd would not take the agent'

    if ! resume_bridge "$root" "$port" "$key" >/dev/null 2>&1; then
        printf '\n'
        printf '  Your WhatsApp did not start. Please restart the computer and try again.\n'
        return 1
    fi

    printf '  Connecting it to your apps.\n'
    local registered=0
    add_mcp_everywhere "$root/bin/whatsapp-mcp" "$key" "$port" 2>/dev/null || registered=1

    # The repair skill, into the folder all three apps read. Done here, before
    # restart_ai_clients below, so a client that reads its skills at startup
    # has it from its very first session rather than the one after.
    #
    # Not fatal, and not a word about it on screen: there is no sentence about
    # this an owner could act on, and telling them the install failed when
    # their WhatsApp is about to work would be false as well as useless. The
    # reason goes to the log, where every other silent-by-design failure in
    # this function already goes.
    install_skill "$zip" 2>/dev/null || \
        log_note "$root" 'repair skill: it could not be put where the AI apps read it'

    # A file whose markers do not match a single start/end pair is left
    # untouched rather than guessed at, and that decision goes to the log, not
    # to this owner's screen.
    set_ai_rules_block "$(claude_memory_path)" 2>/dev/null || \
        log_note "$root" 'ai rules block: an existing file had a marker pair that did not match, so it was left untouched'
    set_ai_rules_block "$(codex_memory_path)" 2>/dev/null || \
        log_note "$root" 'ai rules block: an existing file had a marker pair that did not match, so it was left untouched'

    # Restarted here, before pairing, deliberately: the clients only need to
    # re-read their config, and doing it now means nothing closes an app in
    # the owner's face while the phone is being linked or a year of history is
    # landing.
    restart_ai_clients

    printf '  Opening the page where you link your phone.\n'
    if ! pair_with_fallback "$root" "$port" "$key"; then
        printf '\n'
        printf '  Your WhatsApp is not linked yet. Ask your assistant to try again.\n'
        return 1
    fi

    if [ "$registered" -ne 0 ]; then
        printf '\n'
        printf '  Your WhatsApp is linked, but one of your apps could not be connected.\n'
        printf '  Ask your assistant to repair it.\n'
        return 1
    fi

    printf '\n'
    printf '  Your WhatsApp is connected.\n'
    return 0
}

clear_for_reinstall() {
    # $1 root. Everything except run/.
    #
    # The linked-device session lives there, and a start-over that costs the
    # owner their phone link is worse than whatever it was called for. bin/
    # and installed.json, and nothing else: not run/, not run/store, not
    # linked-at.txt, not logs/. Split out of the verb so this can be proven
    # against a sandbox holding a fake session file.
    local root="${1:-}"
    [ -n "$root" ] || return 1
    suspend_bridge "$root" >/dev/null 2>&1
    remove_autostart
    rm -rf "$root/bin" 2>/dev/null || true
    rm -f "$root/installed.json" 2>/dev/null || true
    return 0
}

invoke_reinstall() {
    # $1 root
    #
    # The pin is captured BEFORE installed.json is deleted, or this destroys
    # the one thing it needs. That field is the only place a real pin lives
    # once the owner is past their original one-liner - the compiled constant
    # can never be real - so once the file is gone, the pin is gone with it
    # unless it is carried forward explicitly.
    local root="${1:-}" pin
    pin="$(get_installed_zip_sha256 "$root")" || pin=''
    clear_for_reinstall "$root"
    fresh_install "$root" '' "$pin"
}

doctor_verb() {
    # $1 root
    #
    # Two lines, always - even when a probe throws, hangs its way to nothing,
    # or prints something nobody expected. This is the interface the whole
    # skill rests on: the AI runs it first, reads the code on the second line,
    # and decides what to do next. Hand it a stack trace and no code and it
    # reads that as "no code", runs the repair on a state nobody ever
    # diagnosed, and tells the owner to contact support regardless of whether
    # the repair helped.
    #
    # WA-00 is reserved for exactly this - "the check itself could not run" -
    # and doctor_state never returns it. The shape test is deliberately strict
    # rather than merely counting fields: a probe that leaked a line onto
    # standard output would otherwise corrupt the string and be printed
    # verbatim to the owner.
    local root="${1:-}" state code
    state="$(doctor_state "$root" 2>/dev/null)"
    code="$(printf '%s' "$state" | cut -d'|' -f1)"
    if [ "$(printf '%s' "$state" | awk -F'|' '{print NF}')" != '3' ] ||
       ! printf '%s' "$code" | grep -qE '^(OK|WA-[0-9]{2}|P-[0-9]{2})$'; then
        printf '  Something went wrong checking your WhatsApp.\n'
        printf 'WA-00\n'
        return 0
    fi
    format_doctor_line "$state"
    printf '%s\n' "$code"
    return 0
}

reconnect_verb() {
    # $1 root
    #
    # The documented answer to "my phone got unlinked", and the one verb that
    # must never do anything else - no reinstall, no re-port, nothing under
    # run/ touched.
    local root="${1:-}" port key
    if [ ! -f "$root/bin/whatsapp-bridge" ] || [ ! -f "$LAUNCH_AGENT_PLIST" ]; then
        printf '  Your WhatsApp is not set up on this computer yet.\n'
        return 0
    fi
    port="$(read_agent_value "$LAUNCH_AGENT_PLIST" PORT)"
    key="$(read_agent_value "$LAUNCH_AGENT_PLIST" WHATSAPP_API_KEY)"
    # A LaunchAgent that lost its port or its key reads back as nothing, and
    # pairing with nothing posts an empty number the bridge can only reject.
    # Guarded so this branch always ends in the one plain sentence below.
    if [ -n "$port" ] && [ -n "$key" ]; then
        pair_with_fallback "$root" "$port" "$key" && return 0
    fi
    printf '\n'
    printf '  I could not connect your WhatsApp. Please contact Vimigo support.\n'
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Sourcing this file loads the functions without running the setup, which is
# how the acceptance suite drives everything against throwaway paths. It must
# sit here, between the definitions above and the dispatch below, and nothing
# below it may be reachable except through it.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
fi

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

ARG_DOCTOR=0
ARG_FIX=0
ARG_RECONNECT=0
ARG_REINSTALL=0
ARG_ZIP_PATH=''
ARG_ZIP_SHA256=''
ARG_BAD=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --doctor)    ARG_DOCTOR=1 ;;
        --fix)       ARG_FIX=1 ;;
        --reconnect) ARG_RECONNECT=1 ;;
        --reinstall) ARG_REINSTALL=1 ;;
        --zip-path)   shift; ARG_ZIP_PATH="${1:-}" ;;
        --zip-sha256) shift; ARG_ZIP_SHA256="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" ;;
        *) ARG_BAD=1 ;;
    esac
    shift || break
done

ROOT="$(install_root)"

# Exit 0 on every benign path, including "already installed" and "the ladder
# gave up after saying so". The one-liner treats any non-zero exit as a hard
# failure and prints its own error sentence on top of whatever this printed,
# so a non-zero exit after a sentence the owner can act on would show them two
# contradictory things at once.

if [ "$ARG_BAD" -eq 1 ]; then
    printf '\n'
    printf '  Something went wrong. Please contact Vimigo support.\n'
    exit 0
fi

if [ "$ARG_DOCTOR" -eq 1 ]; then
    doctor_verb "$ROOT"
    exit 0
fi

if [ "$ARG_FIX" -eq 1 ]; then
    if ! fix_ladder "$ROOT" 3 600; then
        printf '\n'
        printf '  I could not fix this one. Please contact Vimigo support.\n'
    fi
    exit 0
fi

if [ "$ARG_RECONNECT" -eq 1 ]; then
    reconnect_verb "$ROOT"
    exit 0
fi

if [ "$ARG_REINSTALL" -eq 1 ]; then
    invoke_reinstall "$ROOT" || true
    exit 0
fi

# No verb. A first run installs; a second run repairs, because the commonest
# reason to paste the line twice is that something stopped working.
if [ -f "$ROOT/bin/whatsapp-bridge" ]; then
    if ! fix_ladder "$ROOT" 3 600; then
        printf '\n'
        printf '  I could not fix this one. Please contact Vimigo support.\n'
    fi
else
    fresh_install "$ROOT" "$ARG_ZIP_PATH" "$ARG_ZIP_SHA256" || true
fi
exit 0
