#!/usr/bin/env bash
#
# Acceptance tests for vimigo-setup.sh.
#
# Drives the two config writes against throwaway files in a temporary
# directory. Nothing here touches the real Claude or ChatGPT configuration,
# the keychain, or the network.
#
# The guarantees under test are the ones that break somebody's machine when
# they fail: an unrelated setting must survive, a second run must not stack a
# duplicate, and a rejected write must put the original file back.
#
# The config-editing logic is plain Node, so this suite runs anywhere Node
# does. The Homebrew and keychain paths are macOS-only and are not covered
# here; they are exercised by running the script itself on a Mac.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vimigo-setup.sh
. "$SCRIPT_DIR/vimigo-setup.sh"

FAILURES=0
RAN=0

assert() {
    # $1 = 0 for pass, anything else for fail. $2 = description.
    RAN=$((RAN + 1))
    if [ "$1" -eq 0 ]; then
        printf '  \033[32mPASS\033[0m  %s\n' "$2"
    else
        printf '  \033[31mFAIL\033[0m  %s\n' "$2"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_not() {
    # Passes when $1 is a non-zero status, for the cases that must refuse.
    if [ "$1" -eq 0 ]; then assert 1 "$2"; else assert 0 "$2"; fi
}

SANDBOX="$(mktemp -d 2>/dev/null || mktemp -d -t vimigo)"
trap 'rm -rf "$SANDBOX"' EXIT

CLAUDE_CONFIG="$SANDBOX/Claude/claude_desktop_config.json"
CODEX_CONFIG="$SANDBOX/codex/config.toml"
STATE_DIR="$SANDBOX/state"

FAKE_TOKEN="zo_sk_TESTONLY_not_a_real_key"
get_zo_token() { printf '%s' "$FAKE_TOKEN"; }

# Treated as present throughout, for the same reason Claude and ChatGPT are
# stubbed further down: most of this suite is about which rows appear and in
# what order, and a row left outstanding only because the machine running the
# tests has not got the app would fail every "nothing left to do" check. The
# section that tests this row in particular sets it both ways itself.
hermes_installed() { return 0; }

# And the same for the /compile-data command, for exactly the same reason. Its
# own section sets it both ways.
#
# It is stubbed rather than really installed: the real thing writes into
# ~/.claude/skills and onto the Desktop, and a test suite that leaves files in
# either place has changed the machine it was only supposed to measure.
#
# The real one is kept first, because bash holds one definition per name and
# the section that tests it needs the real thing back. unset -f does not undo a
# stub, it deletes the function outright - which reads as three tests failing
# on a defect that is entirely the fixture's.
REAL_EVENT_SKILL_INSTALLED="$(declare -f event_skill_installed)"
event_skill_installed() { return 0; }

printf '\n\033[36mClaude Desktop config\033[0m\n'

mkdir -p "$(dirname "$CLAUDE_CONFIG")"
cat > "$CLAUDE_CONFIG" <<'JSON'
{
  "mcpServers": {
    "somebody-elses-server": { "command": "node", "args": ["server.js"] }
  },
  "someUnrelatedSetting": 42
}
JSON

claude_mcp_configured; assert_not $? 'starts out not connected'

connect_zo_to_claude >/dev/null 2>&1
claude_mcp_configured; assert $? 'reports connected after the write'

# Each field of the written entry, checked one at a time so a failure names
# exactly which guarantee broke.
json_field() {
    # $1 = a JavaScript expression over `data`, written as a literal in this
    # file. It is substituted into the program text and parsed by node as code,
    # so nothing is evaluated at runtime.
    node -e "
        const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
        process.exit(($1) ? 0 : 1);
    " "$CLAUDE_CONFIG" 2>/dev/null
}

json_field '"somebody-elses-server" in data.mcpServers'
assert $? "the owner's other MCP server survived"

json_field 'data.someUnrelatedSetting === 42'
assert $? 'an unrelated setting survived'

# An absolute path, or the bare word if npx could not be found. Asserting the
# bare word is what this used to do, and it would have passed forever while
# Claude Desktop on macOS - which launches MCP servers with a minimal PATH -
# failed to find npx at all.
json_field 'data.mcpServers.zo.command === "npx" || /(^|\/)npx$/.test(data.mcpServers.zo.command)'
assert $? 'the entry launches npx, by a path Claude can actually find'

json_field 'data.mcpServers.zo.args.includes("https://api.zo.computer/mcp")'
assert $? 'the entry points at the Zo endpoint'

[ -d "$(dirname "$CLAUDE_CONFIG")/vimigo-backups" ]
assert $? 'a backup of the original was kept'

# Running it twice must leave exactly one entry, not two.
connect_zo_to_claude >/dev/null 2>&1
json_field 'Object.keys(data.mcpServers).filter(n => n === "zo").length === 1'
assert $? 'a second run leaves exactly one Zo entry'

json_field '"somebody-elses-server" in data.mcpServers'
assert $? "a second run still keeps the owner's other server"

printf '\n\033[36mChatGPT (Codex) config\033[0m\n'

mkdir -p "$(dirname "$CODEX_CONFIG")"
cat > "$CODEX_CONFIG" <<'TOML'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"

[plugins."github@openai-curated"]
enabled = true
TOML

codex_mcp_configured; assert_not $? 'starts out not connected'

connect_zo_to_chatgpt >/dev/null 2>&1
codex_mcp_configured; assert $? 'reports connected after the write'

grep -q 'model = "gpt-5.6-sol"' "$CODEX_CONFIG"
assert $? 'the existing model setting survived'

grep -qF '[plugins."github@openai-curated"]' "$CODEX_CONFIG"
assert $? "the owner's existing plugin section survived"

# A path, not a bare name - and the slash is the whole assertion.
#
# This used to read ^command = "([^"]*/)?npx", where the path in front of npx
# is optional. So it passed against command = "npx", which is what this file
# actually wrote: it was handed the resolved path and ignored it. A packaged
# desktop app does not inherit the shell PATH, so a bare name is one it cannot
# look up and Zo never starts inside ChatGPT.
#
# The same shape of test passed on Windows while customers were reading
# 'C:\Program' is not recognized. A test that only proves the word "npx"
# appears somewhere proves nothing worth having.
grep -qE '^command = "[^"]*/npx"' "$CODEX_CONFIG"
assert $? 'the entry launches npx by its full path, not a name ChatGPT must look up'
grep -qE '^command = "npx"' "$CODEX_CONFIG"
assert_not $? 'and never the bare word, which is what shipped'
# Claude has always had this right. Both apps must agree, on both platforms.
CODEX_CMD="$(grep -E '^command = ' "$CODEX_CONFIG" | head -1 | sed 's/^command = "//; s/"$//')"
[ -x "$CODEX_CMD" ] || [ -f "$CODEX_CMD" ]
assert $? 'and that path is a real file on this machine'

connect_zo_to_chatgpt >/dev/null 2>&1
SECTIONS="$(grep -cE '^\[mcp_servers\.zo\]' "$CODEX_CONFIG")"
[ "$SECTIONS" -eq 1 ]
assert $? 'a second run leaves exactly one Zo section'

# The header count alone is not enough: dropping the header but leaving its
# body would orphan the command line into whichever section came before,
# silently corrupting a setting the owner never touched.
#
# Matched by shape rather than by the exact string 'command = "npx"', which is
# what this counted before. That string only ever appeared because the setup
# wrote the bare word - the very defect three assertions above now forbid - so
# fixing the bug turned this count to zero and failed a check about something
# else entirely. A test written against a value only a bug produces is a test
# that has to be broken before the bug can be fixed.
BODY_LINES="$(grep -cE '^command = ".*npx"' "$CODEX_CONFIG")"
[ "$BODY_LINES" -eq 1 ]
assert $? 'a second run leaves no orphaned settings behind'

grep -q 'model = "gpt-5.6-sol"' "$CODEX_CONFIG"
assert $? 'a second run keeps the model setting'

printf '\n\033[36mRefusing to write without a key\033[0m\n'

get_zo_token() { printf ''; }
rm -f "$CLAUDE_CONFIG"
connect_zo_to_claude >/dev/null 2>&1
assert_not $? 'the Claude write is refused with no key'
[ ! -f "$CLAUDE_CONFIG" ]
assert $? 'no config file is created when the write is refused'

printf '\n\033[36mCorrupt config is left alone\033[0m\n'

get_zo_token() { printf '%s' "$FAKE_TOKEN"; }
printf 'this is not json at all {{{' > "$CLAUDE_CONFIG"
connect_zo_to_claude >/dev/null 2>&1
assert_not $? 'a corrupt Claude config is refused'
[ "$(cat "$CLAUDE_CONFIG")" = 'this is not json at all {{{' ]
assert $? 'the corrupt file was not modified'

printf '\n\033[36mWhat this build offers\033[0m\n'

# Two parts of the setup can be switched off. What follows drives the real
# collect_checks, the real menu and the real "start over" screen, because the
# fault worth catching is not "the flag is read" - it is a checklist that
# quietly comes out in a different order, or a key that still works while
# nothing on screen offers it.

# The reply a finished Zo gives, so the rows can be built without a network.
# Everything answers "done" on purpose: a row missing because it is complete
# proves nothing about a row missing because it was switched off.
ZO_FIXTURE='{"ok":true,"workspaceUrl":"https://example.zo.computer",
"aiProviders":{"claude":{"loggedIn":true},"codex":{"loggedIn":true}},
"whatsapp":{"connected":true,"answering":true},
"integrations":{"gmail":{"connected":true}},
"skills":{"installed":["morning-briefing"],"missing":[]},
"secondBrain":{"folders":3,"notes":7},
"employees":["Joe"]}'

profile_set talkChannel whatsapp
load_homebrew_env() { return 0; }
find_local_whatsapp() { return 0; }

zo_rows() {
    # $1 assistant, $2 skills, $3 brain, $4 employees, $5 = 'key' or 'nokey'.
    # Prints the rows that live on Zo, in the order the owner reads them.
    FEATURE_AI_ASSISTANT="$1"
    FEATURE_ZO_SKILLS="$2"
    FEATURE_SECOND_BRAIN="$3"
    FEATURE_AI_EMPLOYEES="$4"
    # Google held on, because these checks are about the order of the rows
    # around it. Its own switch is covered on its own, below.
    FEATURE_GOOGLE='on'
    if [ "$5" = 'nokey' ]; then
        zo_verify() { ZO_ANSWER=''; }
    else
        zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
    fi
    # Only stdout is silenced. Sending stderr to /dev/null here hid a
    # collect_checks that died mid-run, and the only symptom was two unrelated
    # assertions failing with no explanation whatsoever.
    collect_checks >/dev/null
    local entry keys=''
    for entry in "${CHECKS[@]}"; do
        case "${entry%%|*}" in
            zo-claude-code|zo-codex|zo-skills|zo-brain|zo-google|talk-to-zo|zo-employees)
                keys="$keys${keys:+ }${entry%%|*}" ;;
        esac
    done
    printf '%s' "$keys"
}

ALL_ON='zo-claude-code zo-codex zo-skills zo-brain zo-google talk-to-zo zo-employees'
ALL_OFF='zo-claude-code zo-codex zo-google'

[ "$(zo_rows on on on on key)" = "$ALL_ON" ]
assert $? 'everything on, the checklist is in the order it always was'
[ "$(zo_rows off off off off key)" = "$ALL_OFF" ]
assert $? 'everything off, only the rows that always ship are left'
[ "$(zo_rows on off off off key)" = 'zo-claude-code zo-codex zo-google talk-to-zo' ]
assert $? 'the assistant alone brings back only its own row'
[ "$(zo_rows off on off off key)" = 'zo-claude-code zo-codex zo-skills zo-google' ]
assert $? 'skills alone bring back only skills, in their old place'
[ "$(zo_rows off off on off key)" = 'zo-claude-code zo-codex zo-brain zo-google' ]
assert $? 'the second brain alone sits where it always sat'
[ "$(zo_rows off off off on key)" = 'zo-claude-code zo-codex zo-google zo-employees' ]
assert $? 'employees alone stay last'

# The fault this guards is a real one, shipped for weeks on Windows: the list
# shown before the key is pasted was kept by hand and drifted out of step with
# the list shown after, so pasting the key silently rearranged the screen.
[ "$(zo_rows on on on on nokey)" = "$(zo_rows on on on on key)" ]
assert $? 'everything on, pasting the key does not rearrange the list'
[ "$(zo_rows off off off off nokey)" = "$(zo_rows off off off off key)" ]
assert $? 'everything off, pasting the key does not rearrange the list either'

# Whatever else is switched off, the owner must finish with a way to reach
# their Zo. Claude Desktop and ChatGPT are that way and are never switchable.
#
# Read off CHECKS rather than off zo_rows, which by design only returns the
# rows that live on Zo - the two app connections were never in it.
all_rows() {
    zo_rows "$1" "$2" "$3" "$4" "$5" >/dev/null
    printf '%s\n' "${CHECKS[@]}"
}

all_rows off off off off key | grep -q '^claude-mcp|'
assert $? 'Zo inside Claude Desktop survives every switch being off'
all_rows off off off off key | grep -q '^chatgpt-mcp|'
assert $? 'Zo inside ChatGPT survives every switch being off'
all_rows off off off off nokey | grep -q '^chatgpt-mcp|'
assert $? 'and survives with no key either, so there is always somewhere to type'

printf '\n\033[36mTelegram: is a phone connected\033[0m\n'

# The question used to be answered by counting entries in a file on Zo's disk.
# That file is not written when a phone pairs through Zo's hosted bot - it was a
# month stale on the Zo that found this - so the count never moved and the setup
# waited for ever on a link that had already worked. The answer now comes from
# the only place Zo states it: the reply to a message it cannot route.
#
# It reads prose, so it is tested like prose: on the exact wording seen live, on
# the shapes a reworded Zo might send, and on the ones that must never be read
# as a connected phone.
tg_accounts() {
    "$(node_bin)" -e '
        const { readConnectedTelegram } = require(process.argv[1]);
        process.stdout.write(JSON.stringify(readConnectedTelegram(process.argv[2])));
    ' "$SCRIPT_DIR/zo-verify.js" "$1"
}

LIVE_WORDING="Error: Failed to send Telegram message: ValueError: No Telegram binding found for recipient 'vimigo-setup-status-probe'. Connected accounts: heartsmith. Do not retry — inform the user that delivery failed."

[ "$(tg_accounts "$LIVE_WORDING")" = '["heartsmith"]' ]
assert $? 'the wording Zo actually sends names the connected phone'
[ "$(tg_accounts 'Connected accounts: alice, bob, carol.')" = '["alice","bob","carol"]' ]
assert $? 'several phones are all read, and trimmed'
[ "$(tg_accounts 'Connected accounts: none.')" = '[]' ]
assert $? '"none" is not a phone'
[ "$(tg_accounts 'Connected accounts: .')" = '[]' ]
assert $? 'and neither is an empty list'
[ "$(tg_accounts 'Telegram message sent successfully')" = '[]' ]
assert $? 'a send that worked is not proof on its own'
[ "$(tg_accounts '')" = '[]' ]
assert $? 'nothing back is not proof either'
[ "$(tg_accounts 'connected accounts: Heartsmith.')" = '["Heartsmith"]' ]
assert $? 'the wording is matched whatever its case'

printf '\n\033[36mOne AI app is enough\033[0m\n'

# A customer who pays for ChatGPT and not Claude is a finished setup, not a
# half-finished one. Counted as half-finished their Claude rows stayed red for
# ever, the checklist never said done, and what they reported was "a problem
# with the Zo connection".
# Globals, not locals of app_rows. A stub that closes over a local keeps
# referring to it after the call returns, and the next collect_checks then dies
# on an unbound variable under set -u - silently, taking the whole suite with
# it and reporting nothing but a non-zero exit.
#
# TEST_ prefixed, and that matters: these were WANT_CLAUDE and WANT_GPT until
# the script itself grew a WANT_CLAUDE. collect_checks then overwrote the
# stub's own answer mid-call, so "with neither installed" tested a machine with
# Claude on it.
TEST_HAS_CLAUDE='no'
TEST_HAS_GPT='yes'

app_rows() {
    # $1 = has Claude, $2 = has ChatGPT. Prints "key:status" for the four rows
    # that the answer decides.
    TEST_HAS_CLAUDE="$1"; TEST_HAS_GPT="$2"
    app_installed() {
        case "$1" in
            Claude)  [ "$TEST_HAS_CLAUDE" = 'yes' ] ;;
            ChatGPT) [ "$TEST_HAS_GPT" = 'yes' ] ;;
        esac
    }
    claude_mcp_configured() { [ "$TEST_HAS_CLAUDE" = 'yes' ]; }
    codex_mcp_configured() { [ "$TEST_HAS_GPT" = 'yes' ]; }
    zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
    collect_checks >/dev/null 2>&1
    local entry out=''
    for entry in "${CHECKS[@]}"; do
        case "${entry%%|*}" in
            claude-app|chatgpt-app|claude-mcp|chatgpt-mcp)
                out="$out${out:+ }$(printf '%s' "$entry" | cut -d'|' -f1,3 | tr '|' ':')" ;;
        esac
    done
    printf '%s' "$out"
}

[ "$(app_rows yes no)" = 'claude-app:ok chatgpt-app:skipped claude-mcp:ok chatgpt-mcp:skipped' ]
assert $? 'with only Claude, the ChatGPT rows are settled and not chased'
[ "$(app_rows no yes)" = 'claude-app:skipped chatgpt-app:ok claude-mcp:skipped chatgpt-mcp:ok' ]
assert $? 'with only ChatGPT, the Claude rows are settled and not chased'
[ "$(app_rows yes yes)" = 'claude-app:ok chatgpt-app:ok claude-mcp:ok chatgpt-mcp:ok' ]
assert $? 'with both, both are used'
# Nothing to prefer, so both are offered - a blank machine still gets set up.
[ "$(app_rows no no)" = 'claude-app:missing chatgpt-app:missing claude-mcp:missing chatgpt-mcp:missing' ]
assert $? 'with neither, both are still offered'

# The part that decides whether they ever see "all done".
settled_only() {
    local entry
    for entry in "${CHECKS[@]}"; do
        case "$(printf '%s' "$entry" | cut -d'|' -f3)" in
            ok|skipped) ;;
            *) return 1 ;;
        esac
    done
    return 0
}
app_rows no yes >/dev/null
settled_only
assert $? 'a ChatGPT-only machine can reach a finished setup'

# The two plan rows need a paid subscription, so no amount of pressing Enter
# clears them. Counted as outstanding they held the setup open for anyone
# paying for neither, which is most people trying it.
zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
NO_PLANS='{"ok":true,"workspaceUrl":"https://example.zo.computer",
"aiProviders":{"claude":{"loggedIn":false},"codex":{"loggedIn":false}},
"whatsapp":{"connected":true,"answering":true},
"integrations":{"gmail":{"connected":true}},
"skills":{"installed":["morning-briefing"],"missing":[]},
"secondBrain":{"folders":3,"notes":7},"employees":["Joe"]}'
zo_verify() { ZO_ANSWER="$NO_PLANS"; }
collect_checks >/dev/null 2>&1
printf '%s\n' "${CHECKS[@]}" | grep -q '^zo-claude-code|Claude plan on Zo|skipped|'
assert $? 'an unsigned Claude plan is settled, not outstanding'
printf '%s\n' "${CHECKS[@]}" | grep -q '^zo-codex|ChatGPT plan on Zo|skipped|'
assert $? 'an unsigned ChatGPT plan is settled too'
settled_only
assert $? 'so paying for neither plan still reaches a finished setup'

printf '\n\033[36mNode has to be new enough to talk to Zo\033[0m\n'

# zo-verify.js calls fetch, which is built into Node from 18 and simply does
# not exist before it. On an older Node the row read "ok, version 16" in green,
# every Zo row then said "could not reach Zo to check", and every Zo step
# failed in turn with no reason given. That is what a customer saw.
node_row() {
    # $1 = what node --version reports, or empty for no node at all.
    local want="$1"
    if [ -z "$want" ]; then
        node_bin() { printf ''; }
        command_version() { printf ''; }
    else
        node_bin() { printf '/usr/local/bin/node'; }
        command_version() {
            case "$1" in node) printf '%s' "${want#v}" ;; *) printf '' ;; esac
        }
        node() { [ "$1" = '--version' ] && printf '%s\n' "$want"; }
    fi
    zo_verify() { ZO_ANSWER=''; }
    collect_checks >/dev/null 2>&1
    printf '%s\n' "${CHECKS[@]}" | grep '^node|' | head -1 | cut -d'|' -f3
}

[ "$(node_row v16.20.2)" = 'needs-you' ]
assert $? 'Node 16 is reported as too old, not as a tick'
[ "$(node_row v14.21.3)" = 'needs-you' ]
assert $? 'and so is Node 14'
[ "$(node_row v18.0.0)" = 'ok' ]
assert $? 'Node 18 is the first that works'
[ "$(node_row v24.18.0)" = 'ok' ]
assert $? 'and anything newer is fine'
[ "$(node_row '')" = 'missing' ]
assert $? 'no node at all is missing, which is a different fix'

printf '\n\033[36mNo step goes missing from the run\033[0m\n'

# "Step 3 of 7" is worked out from what is still outstanding, so a switched-off
# feature has to take its step with it. A total that still counts a step nothing
# will ever run strands the owner on "Step 5 of 7" at the end, certain something
# failed - and a sequence with a hole in it says the same thing louder.
ZO_UNDONE='{"ok":true,"workspaceUrl":"https://example.zo.computer",
"aiProviders":{"claude":{"loggedIn":false},"codex":{"loggedIn":false}},
"whatsapp":{"connected":false,"detail":"not linked yet"},
"integrations":{"gmail":{"connected":false}},
"skills":{"installed":[],"missing":["morning-briefing"]},
"secondBrain":null,"employees":[]}'

fix_one() { printf 'WOULD_DO %s\n' "$1"; return 1; }

step_trail() {
    # $1 = every switch at once. Prints "1/7 2/7 ..." as the owner sees it,
    # driving the real fix_everything rather than counting rows by hand.
    FEATURE_AI_ASSISTANT="$1"
    FEATURE_ZO_SKILLS="$1"
    FEATURE_SECOND_BRAIN="$1"
    FEATURE_AI_EMPLOYEES="$1"
    FEATURE_GOOGLE="$1"
    zo_verify() { ZO_ANSWER="$ZO_UNDONE"; }
    collect_checks >/dev/null 2>&1
    fix_everything 2>&1 |
        sed -n 's/.*Step \([0-9][0-9]*\) of \([0-9][0-9]*\).*/\1\/\2/p' |
        tr '\n' ' ' | sed 's/ *$//'
}

trail_is_whole() {
    # Passes when the numbers run 1..N with no gaps and N is the total claimed.
    #
    # No steps at all is whole, and on this build it is the point: with every
    # feature switched off and one AI app already set up, there is genuinely
    # nothing left to run. Calling that a gap failed the suite for doing
    # exactly what it was asked to do.
    local trail="$1" want=1 total='' pair
    [ -n "$trail" ] || return 0
    for pair in $trail; do
        [ "${pair%%/*}" = "$want" ] || return 1
        total="${pair##*/}"
        want=$((want + 1))
    done
    [ -n "$total" ] && [ "$((want - 1))" = "$total" ]
}

TRAIL_OFF="$(step_trail off)"
TRAIL_ON="$(step_trail on)"

trail_is_whole "$TRAIL_OFF"
assert $? 'switched off, the steps run 1..N with no gaps and end on the total'
trail_is_whole "$TRAIL_ON"
assert $? 'switched on, the steps run 1..N with no gaps and end on the total'

# Counted as a difference, not as an absolute: how many local rows are
# outstanding depends on the machine this suite runs on, but switching two
# features off must remove exactly two steps anywhere.
steps_off="$(printf '%s' "$TRAIL_OFF" | wc -w | tr -d ' ')"
steps_on="$(printf '%s' "$TRAIL_ON" | wc -w | tr -d ' ')"
[ "$((steps_on - steps_off))" -eq 5 ]
assert $? 'switching all five off removes exactly five steps, no more and no fewer'

case "$TRAIL_OFF" in *WOULD_DO*) false ;; *) true ;; esac
assert $? 'and nothing was actually run to find that out'

printf '\n\033[36mThe assistant refuses to start on a half-finished setup\033[0m\n'

# The rule Tengku set: the main setup finishes first. The assistant needs the
# Zo key, the scripts this setup puts on the Zo, and a Zo that answers - so
# started early it fails somewhere in the middle, having already asked for a
# phone number, and what the owner remembers is that the assistant broke.
gate_says() {
    # $1 = 'done' or 'halfway'. Prints what the gate found, one title per line.
    FEATURE_AI_ASSISTANT='off'; FEATURE_ZO_SKILLS='off'
    FEATURE_SECOND_BRAIN='off'; FEATURE_AI_EMPLOYEES='off'; FEATURE_GOOGLE='off'
    if [ "$1" = 'done' ]; then
        app_installed() { [ "$1" = 'ChatGPT' ]; }
        claude_mcp_configured() { return 1; }
        codex_mcp_configured() { return 0; }
    else
        # Nothing installed and nothing connected: the state a customer is in
        # before they have run anything.
        app_installed() { return 1; }
        claude_mcp_configured() { return 1; }
        codex_mcp_configured() { return 1; }
    fi
    zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
    main_setup_unfinished
}

# Captured once each, and read from the variable. Calling gate_says again for
# every assertion re-ran a whole checklist per line and made a failure hard to
# read: three assertions could disagree about the same machine.
GATE_DONE="$(gate_says done)"
GATE_HALF="$(gate_says halfway)"

[ -z "$GATE_DONE" ]
assert $? 'a finished setup lets the assistant through'
[ -n "$GATE_HALF" ]
assert $? 'a half-finished one does not'
case "$GATE_HALF" in
    *'ChatGPT Desktop'*) true ;;
    *) printf '        it said: %s\n' "$(printf '%s' "$GATE_HALF" | tr '\n' ';')"; false ;;
esac
assert $? 'and it names what is still missing, rather than just refusing'

# Its own row must never be the thing that blocks it.
FEATURE_AI_ASSISTANT='on'
app_installed() { [ "$1" = 'ChatGPT' ]; }
claude_mcp_configured() { return 1; }
codex_mcp_configured() { return 0; }
zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
[ -z "$(main_setup_unfinished)" ]
assert $? 'the assistant is not counted against itself'
[ "$FEATURE_AI_ASSISTANT" = 'on' ]
assert $? 'and the switch is left as it was found'

printf '\n\033[36mGoogle is a switch like the rest\033[0m\n'

# The last row that could hold a v1 setup open. Tengku believed it was already
# off and it was not: the four switches were the assistant, skills, the second
# brain and employees, and Google was never among them - so on a finished
# setup it sat there as the one outstanding thing.
google_row() {
    FEATURE_AI_ASSISTANT='off'; FEATURE_ZO_SKILLS='off'
    FEATURE_SECOND_BRAIN='off'; FEATURE_AI_EMPLOYEES='off'
    FEATURE_GOOGLE="$1"
    if [ "$2" = 'nokey' ]; then zo_verify() { ZO_ANSWER=''; }
    else zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }; fi
    collect_checks >/dev/null 2>&1
    printf '%s\n' "${CHECKS[@]}" | grep -c '^zo-google|' | tr -d ' '
}

[ "$(google_row on key)" = '1' ]
assert $? 'switched on, Google is on the list'
[ "$(google_row off key)" = '0' ]
assert $? 'switched off, Google is gone'
[ "$(google_row on nokey)" = '1' ]
assert $? 'and with no key it still appears when switched on'
[ "$(google_row off nokey)" = '0' ]
assert $? 'and still does not when switched off, so the list never rearranges'

# The whole point of switching it off: nothing is left for the owner to do.
FEATURE_AI_ASSISTANT='off'; FEATURE_ZO_SKILLS='off'
FEATURE_SECOND_BRAIN='off'; FEATURE_AI_EMPLOYEES='off'; FEATURE_GOOGLE='off'
app_installed() { [ "$1" = 'ChatGPT' ]; }
claude_mcp_configured() { return 1; }
codex_mcp_configured() { return 0; }
zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
collect_checks >/dev/null 2>&1
settled_only
assert $? 'with everything off, a ChatGPT-only machine has nothing left to do'

printf '\n\033[36mA switched-off feature takes its key with it\033[0m\n'

menu_keys() {
    # $1 assistant, $2 brain, $3 employees. Prints the letters the finished
    # menu offers, in order.
    FEATURE_AI_ASSISTANT="$1"
    FEATURE_SECOND_BRAIN="$2"
    FEATURE_AI_EMPLOYEES="$3"
    # Held on, and said here rather than inherited. These checks are about each
    # feature taking its own key with it, and Z and S are not features - they
    # are the finished menu itself, which has its own switch and its own
    # section above. Left to inherit, all five of these turned red the day that
    # switch went off, for a reason none of them is about.
    FEATURE_FINISHED_MENU='on'
    # Colours stripped first. They are empty until apply_theme runs, so a
    # pattern that looked for them found nothing and every row read as absent.
    show_main_options finished 2>&1 |
        sed 's/[[:cntrl:]]\[[0-9;]*m//g' |
        awk '$1 ~ /^[A-Z]$/ && NF > 1 { printf "%s%s", sep, $1; sep = " " }'
}

[ "$(menu_keys on on on)" = 'E T A M Z S Q' ]
assert $? 'everything on, the finished menu offers every key it always did'
[ "$(menu_keys off off off)" = 'Z S Q' ]
assert $? 'everything off, only Zo, start over and close are left'
[ "$(menu_keys on off off)" = 'A Z S Q' ]
assert $? 'the assistant alone leaves A'
[ "$(menu_keys off on off)" = 'M Z S Q' ]
assert $? 'the second brain alone leaves M'
[ "$(menu_keys off off on)" = 'E T Z S Q' ]
assert $? 'employees alone leave E and T'

# Hidden is not enough. A key that still fires while nothing on screen mentions
# it is worse than a missing one: the owner presses E by accident and this
# build hires somebody it was never meant to be able to hire.
hire_employee() { printf 'RAN_HIRE\n'; }
show_team_screen() { printf 'RAN_TEAM\n'; }
setup_second_brain() { printf 'RAN_BRAIN\n'; }

reset_whatsapp_assistant() { printf 'RAN_ASSISTANT_SETUP\n'; }

pressed() {
    # $1 assistant, $2 brain, $3 employees, $4 = the key. Prints what ran, or
    # NOTHING when the key was refused.
    FEATURE_AI_ASSISTANT="$1"
    FEATURE_SECOND_BRAIN="$2"
    FEATURE_AI_EMPLOYEES="$3"
    local out
    out="$(printf '\n' | handle_main_choice "$4" 2>&1 | grep -E 'RAN_' | head -1)"
    printf '%s' "${out:-NOTHING}"
}

[ "$(pressed off off off e)" = 'NOTHING' ]
assert $? 'pressing E with employees switched off hires nobody'
[ "$(pressed off off off t)" = 'NOTHING' ]
assert $? 'pressing T with employees switched off shows no team'
[ "$(pressed off off off m)" = 'NOTHING' ]
assert $? 'pressing M with the second brain switched off builds nothing'
[ "$(pressed off off off a)" = 'NOTHING' ]
assert $? 'pressing A with the assistant switched off sets up nothing'
[ "$(pressed on on on e)" = 'RAN_HIRE' ]
assert $? 'and switched on, E still hires'
[ "$(pressed on on on t)" = 'RAN_TEAM' ]
assert $? 'switched on, T still shows the team'
[ "$(pressed on on on m)" = 'RAN_BRAIN' ]
assert $? 'switched on, M still builds the second brain'
[ "$(pressed on on on a)" = 'RAN_ASSISTANT_SETUP' ]
assert $? 'switched on, A still sets the assistant up again'

printf '\n\033[36mStart over renumbers itself\033[0m\n'

reset_whatsapp_assistant() { printf 'RAN_ASSISTANT\n'; }
reset_ai_employees() { printf 'RAN_EMPLOYEES\n'; }
get_installed_by_us() { printf ''; }
ask_yes_no() { return 1; }

reset_pick() {
    # $1 assistant, $2 employees, $3 = what the owner types. Prints what ran.
    FEATURE_AI_ASSISTANT="$1"
    FEATURE_AI_EMPLOYEES="$2"
    local out
    out="$(printf '%s\n' "$3" | reset_vimigo_setup 2>&1 |
        grep -Eo 'RAN_ASSISTANT|RAN_EMPLOYEES|Nothing was changed' | head -1)"
    printf '%s' "${out:-NOTHING}"
}

reset_prompt() {
    FEATURE_AI_ASSISTANT="$1"
    FEATURE_AI_EMPLOYEES="$2"
    printf '\n' | reset_vimigo_setup 2>&1 | grep -o 'Choose [^>]*' | head -1
}

[ "$(reset_prompt on on)" = 'Choose 1, 2 or 3, or Enter to go back ' ]
assert $? 'everything on, start over still offers three'
[ "$(reset_prompt on off)" = 'Choose 1 or 2, or Enter to go back ' ]
assert $? 'employees off, it offers two and says so'
# One option left is not hypothetical: switch both off and "Everything" is all
# there is. Counting backwards from one would print "Choose  or 1".
[ "$(reset_prompt off off)" = 'Choose 1, or Enter to go back ' ]
assert $? 'both off, it offers one and still reads as a sentence'

[ "$(reset_pick on on 1)" = 'RAN_ASSISTANT' ]
assert $? 'everything on, 1 is the assistant'
[ "$(reset_pick on on 2)" = 'RAN_EMPLOYEES' ]
assert $? 'everything on, 2 lets an employee go'
[ "$(reset_pick on off 1)" = 'RAN_ASSISTANT' ]
assert $? 'employees off, 1 is still the assistant'
# The one that bites. Hiding an option without renumbering leaves its old
# number wired to it - a key nothing on screen mentions, quietly letting an AI
# employee go, or wiping the assistant.
[ "$(reset_pick on off 2)" != 'RAN_EMPLOYEES' ]
assert $? 'employees off, 2 never reaches the employee reset'
[ "$(reset_pick off on 1)" != 'RAN_ASSISTANT' ]
assert $? 'assistant off, 1 never reaches the assistant reset'
[ "$(reset_pick off on 1)" = 'RAN_EMPLOYEES' ]
assert $? 'assistant off, 1 is the employee reset instead, as the screen says'
[ "$(reset_pick off off 1)" = 'Nothing was changed' ]
assert $? 'both off, 1 is Everything and reaches neither of the other two'
[ "$(reset_pick on on 08)" = 'Nothing was changed' ]
assert $? 'a leading zero is read as text, not as octal'
[ "$(reset_pick on on '')" = 'Nothing was changed' ]
assert $? 'Enter goes back without changing anything'

printf '\n\033[36mThe Mac restarts the apps itself, as Windows does\033[0m\n'

# These apps read their settings once, at startup. "Quit it completely and open
# it again" is a small instruction a good number of people will not carry out -
# some minimise the window and call that closed - and the result is a green tick
# beside an app that cannot see Zo. Windows has closed and reopened them for a
# while; the Mac was still asking, which is what made the two setups differ.
sleep() { return 0; }
osascript() { return 0; }
open() { return 0; }

# Every branch out of restart_desktop_app has to leave the owner knowing what
# to do next, and none of them may claim something that was not checked.
app_is_running() { return 1; }
OUT="$(restart_desktop_app 'Claude' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$OUT" | grep -q 'Open Claude when you like'
assert $? 'an app that is not running is left alone rather than launched'
printf '%s' "$OUT" | grep -q 'Closing Claude'
assert_not $? 'and nothing is closed that was never open'

# Running, and it quits when asked, and it comes back: the ordinary case.
RESTART_CALLS=0
app_is_running() {
    RESTART_CALLS=$((RESTART_CALLS + 1))
    # open, then gone once asked, then back after being reopened.
    case "$RESTART_CALLS" in 1) return 0 ;; 2) return 1 ;; *) return 0 ;; esac
}
OUT="$(restart_desktop_app 'Claude' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$OUT" | grep -q 'Closing Claude and opening it again'
assert $? 'a running app is closed and reopened without asking the owner'
printf '%s' "$OUT" | grep -q 'Claude is open again'
assert $? 'and the owner is told it came back'

# Running, and it will not quit - usually an unsaved document behind a dialog.
app_is_running() { return 0; }
OUT="$(restart_desktop_app 'ChatGPT' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$OUT" | grep -q 'did not close on its own'
assert $? 'an app that refuses to quit is reported, not forced'
printf '%s' "$OUT" | grep -q 'Quit ChatGPT yourself'
assert $? 'and the owner is told to quit it themselves'
printf '%s' "$OUT" | grep -q 'not just the window'
assert $? 'and told what quitting actually means on a Mac'

# It quit, and then would not come back. Before this was checked, the setup
# said "open again, with Zo connected" over an app that was not running - so
# the owner believed the step was finished and stopped looking.
app_is_running() { return 1; }
OUT="$(restart_desktop_app 'Claude' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$OUT" | grep -q 'is open again'
assert_not $? 'an app that never came back is never reported as open'

RESTART_CALLS=0
app_is_running() {
    RESTART_CALLS=$((RESTART_CALLS + 1))
    # open, then gone, and it never comes back however long we wait.
    case "$RESTART_CALLS" in 1) return 0 ;; *) return 1 ;; esac
}
OUT="$(restart_desktop_app 'Claude' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$OUT" | grep -q 'Could not open Claude again by itself'
assert $? 'a failed reopen is admitted rather than reported as success'
printf '%s' "$OUT" | grep -q 'Open Claude yourself'
assert $? 'and the owner is told to open it themselves'

# Could not tell. macOS asks permission the first time one program controls
# another, and somebody who clicks Don't Allow lands exactly here - with an app
# still open on its old settings that cannot see Zo.
app_is_running() { return 2; }
OUT="$(restart_desktop_app 'Claude' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$OUT" | grep -q 'Could not tell whether Claude is open'
assert $? 'an unknown answer is never quietly treated as "not running"'
printf '%s' "$OUT" | grep -q 'quit Claude completely'
assert $? 'and the owner is asked to restart it themselves instead'

unset -f sleep osascript open app_is_running

# The three answers exist at all, which is what makes the branch above possible.
awk '/^app_is_running\(\)/,/^\}/' "$SCRIPT_DIR/vimigo-setup.sh" | grep -q 'return 2'
assert $? 'the check can say "could not tell" rather than guessing'

# The two safety properties, read off the source because no test can prove the
# absence of a kill by running it.
awk '/^restart_desktop_app\(\)/,/^\}/' "$SCRIPT_DIR/vimigo-setup.sh" | grep -qE 'pkill|killall|kill -'
assert_not $? 'nothing force-kills a Mac app, which would take unsaved work with it'
awk '/^app_is_running\(\)/,/^\}/' "$SCRIPT_DIR/vimigo-setup.sh" | grep -q 'osascript'
assert $? 'and the application is asked by name, never matched against processes'
# The reason that matters: Claude Code ships a program called claude, and on
# Windows closing everything by that name closed the terminal the owner was
# sitting in. AppleScript only ever addresses the graphical application.
awk '/^app_is_running\(\)/,/^\}/' "$SCRIPT_DIR/vimigo-setup.sh" | grep -qE 'pgrep|ps -|grep .*claude'
assert_not $? 'so a Claude Code session in the next tab is never caught by it'

printf '\n\033[36mThe finished screen is the same on both\033[0m\n'

RESTART_PENDING=''
DONE_SCREEN="$(show_all_done 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$DONE_SCREEN" | grep -q 'A L L   D O N E'
assert $? 'the Mac finished screen says ALL DONE'
printf '%s' "$DONE_SCREEN" | grep -q 'Everything above is set up and working'
assert $? 'and points at the checklist above it, word for word as Windows does'
grep -q 'Everything above is set up and working' "$SCRIPT_DIR/vimigo-setup.ps1"
assert $? 'and Windows really does say that sentence, so the two agree'
printf '%s' "$DONE_SCREEN" | grep -qi 'quit'
assert_not $? 'and neither asks anybody to quit an app themselves any more'

# It used to clear the screen, throwing away the checklist it was describing.
awk '/^show_all_done\(\)/,/^\}/' "$SCRIPT_DIR/vimigo-setup.sh" | grep -q 'clear_screen'
assert_not $? 'and it no longer wipes the list it is the footer of'

# The one case the deleted warning was right about.
#
# A restart the setup could not do is mentioned once, in the middle of a long
# run, to somebody who is not reading closely. Without this it is never said
# again, and they finish on a screen saying everything works beside an app that
# cannot see Zo.
RESTART_PENDING='ChatGPT '
PENDING_SCREEN="$(show_all_done 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
printf '%s' "$PENDING_SCREEN" | grep -q 'close ChatGPT completely'
assert $? 'a restart that failed is said again at the end, and names the app'
printf '%s' "$PENDING_SCREEN" | grep -q 'not just the window'
assert $? 'and says what closing an app actually means on a Mac'
printf '%s' "$PENDING_SCREEN" | grep -q 'Claude'
assert_not $? 'and never names an app that restarted perfectly well'
RESTART_PENDING=''

printf '\n\033[36mThe finished screen ends the setup, it does not open a menu\033[0m\n'

# "ALL DONE" is the screen an owner is most likely to be tapping at idly,
# having just been told everything worked - so a key that removes what the setup
# installed must not be sitting on it.
finished_menu() {
    FEATURE_FINISHED_MENU="$1"
    FEATURE_AI_ASSISTANT='off'; FEATURE_ZO_SKILLS='off'
    FEATURE_SECOND_BRAIN='off'; FEATURE_AI_EMPLOYEES='off'; FEATURE_GOOGLE='off'
    show_main_options finished 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
}

PLAIN="$(finished_menu off)"
printf '%s' "$PLAIN" | grep -q 'Start over'
assert_not $? 'Start over is gone from the finished screen'
printf '%s' "$PLAIN" | grep -q 'Open your Zo'
assert_not $? 'and so is Open your Zo'
printf '%s' "$PLAIN" | grep -q 'WARNING'
assert_not $? 'and the warning that went with it'
printf '%s' "$PLAIN" | grep -q 'Close'
assert $? 'Close is still offered, so there is a way out'
printf '%s' "$PLAIN" | grep -q 'What you can do'
assert_not $? 'and the header goes too, rather than sitting above a lone Close'

FULL="$(finished_menu on)"
printf '%s' "$FULL" | grep -q 'Start over'
assert $? 'switched on, Start over comes back exactly as it was'
printf '%s' "$FULL" | grep -q 'Open your Zo'
assert $? 'and Open your Zo with it'

# Hidden is not enough on its own. This script's own rule: a key that still
# works while nothing offers it is worse than a missing one, because it fires by
# accident and nothing on screen explains what just happened.
FEATURE_FINISHED_MENU='off'
handle_main_choice s >/dev/null 2>&1
assert_not $? 'the S key is gated, not merely hidden'
handle_main_choice z >/dev/null 2>&1
assert_not $? 'as is the Z key'

# Taken off the screen, not taken away.
grep -q '"--reset"' "$SCRIPT_DIR/vimigo-setup.sh"
assert $? 'starting over is still reachable, by asking for it on purpose'

printf '\n\033[36mThe /compile-data command\033[0m\n'

# Both halves, as shipped. A row that goes green while the zip is missing the
# file it copies is the one failure nobody would find until the event.
[ -f "$SCRIPT_DIR/event/compile-data/SKILL.md" ]
assert $? 'the command ships beside the setup'
[ -f "$SCRIPT_DIR/event/Submit my AI workflow - ChatGPT.txt" ]
assert $? 'and so does the ChatGPT copy of it, for owners with no slash commands'
grep -q '^name: compile-data$' "$SCRIPT_DIR/event/compile-data/SKILL.md"
assert $? 'the skill is named for the command the owner is told to type'

# The address the whole thing exists to reach. Both halves carry it, because a
# submission that lands in the owner's own Drive and is never shared with
# anybody is indistinguishable from one that was never made.
grep -qF 'vimigoai@vimigoapp.com' "$SCRIPT_DIR/event/compile-data/SKILL.md"
assert $? 'it knows the address to share the folder with'
grep -qF 'vimigoai@vimigoapp.com' "$SCRIPT_DIR/event/Submit my AI workflow - ChatGPT.txt"
assert $? 'and so does the ChatGPT copy'

# Named, because a document with no name on it cannot be matched to a company
# afterwards, and the folder is named for the company alone by instruction.
grep -qF 'AI Workflow Submission' "$SCRIPT_DIR/event/compile-data/SKILL.md"
assert $? 'it knows what the document is called'

# The instruction most easily lost in an edit, and the one with a real cost: an
# invented time saving in a document a CEO will consult on.
grep -qiF 'never invent a number' "$SCRIPT_DIR/event/compile-data/SKILL.md"
assert $? 'it is told not to invent results'

# The batch and the dates, pinned in both halves and checked against each other.
#
# Step 1 of the skill filters the owner's files by the programme dates, so a
# stale window matches nothing and the review comes back empty - which reads as
# a broken command rather than a wrong date. This has been wrong twice: shipped
# as V001 / July, corrected to V002 / August. Pinned here so the third time is
# a failing test rather than a hundred and twenty empty submissions.
EVENT_BATCH='V002'
EVENT_MONTH='August 2026'
for half in "$SCRIPT_DIR/event/compile-data/SKILL.md" \
            "$SCRIPT_DIR/event/Submit my AI workflow - ChatGPT.txt"; do
    grep -qF "$EVENT_BATCH" "$half"
    assert $? "$(basename "$half") names the batch it is for"
    grep -qF "$EVENT_MONTH" "$half"
    assert $? "$(basename "$half") names the month it is for"
    grep -qF 'V001' "$half"
    assert_not $? "$(basename "$half") does not still name the batch before it"
done

# The real thing, run against a sandbox rather than the tester's own home, so
# nothing here lands in ~/.claude or on anybody's Desktop.
REAL_HOME="$HOME"
HOME="$SANDBOX/home"
mkdir -p "$HOME/Desktop"
eval "$REAL_EVENT_SKILL_INSTALLED"
FEATURE_EVENT_SKILL='on'

WANT_CLAUDE='yes'; WANT_CHATGPT='yes'
event_skill_installed
assert_not $? 'with neither half in place it is not done'

install_event_skill >/dev/null 2>&1
assert $? 'installing it works with nothing to sign into'
[ -f "$HOME/.claude/skills/compile-data/SKILL.md" ]
assert $? 'the command lands where Claude looks for a personal skill'
[ -f "$HOME/Desktop/Submit my AI workflow - ChatGPT.txt" ]
assert $? 'and the ChatGPT copy lands on the Desktop, where it can be found'
event_skill_installed
assert $? 'and afterwards it reads as done'

# An owner who chose one app must not be held back by the other one's half.
# This is the mistake the Zo plan rows made: a row that can never go green on a
# machine that answered the first question honestly.
rm -f "$HOME/Desktop/Submit my AI workflow - ChatGPT.txt"
WANT_CLAUDE='yes'; WANT_CHATGPT='no'
event_skill_installed
assert $? 'a Claude owner is finished without a ChatGPT file they cannot use'
rm -rf "$HOME/.claude"
WANT_CLAUDE='no'; WANT_CHATGPT='yes'
install_event_skill >/dev/null 2>&1
[ ! -d "$HOME/.claude/skills/compile-data" ]
assert $? 'a ChatGPT owner is not given a Claude skill they will never type'
event_skill_installed
assert $? 'and the Desktop file alone finishes them'

# Start over has to take it back, or the row stays green and the step never
# runs again - which is the one thing start over exists for.
WANT_CLAUDE='yes'; WANT_CHATGPT='yes'
install_event_skill >/dev/null 2>&1
remove_event_skill >/dev/null 2>&1
event_skill_installed
assert_not $? 'starting over takes the command back'

# Only ours. ~/.claude/skills is the owner's folder and may hold skills they
# made themselves.
mkdir -p "$HOME/.claude/skills/something-they-wrote"
printf 'theirs\n' > "$HOME/.claude/skills/something-they-wrote/SKILL.md"
install_event_skill >/dev/null 2>&1
remove_event_skill >/dev/null 2>&1
[ -f "$HOME/.claude/skills/something-they-wrote/SKILL.md" ]
assert $? 'and leaves skills the owner put there themselves alone'

HOME="$REAL_HOME"
event_skill_installed() { return 0; }

# The row, in the list. Same two ends as Hermes One: it must appear on a machine
# with no Zo key as readily as on one with a key.
FEATURE_EVENT_SKILL='on'
CHECKS=(); add_event_skill_check
printf '%s' "${CHECKS[0]}" | grep -q '^event-skill|Your /compile-data command|ok|'
assert $? 'an installed command reads as done'
event_skill_installed() { return 1; }
CHECKS=(); add_event_skill_check
printf '%s' "${CHECKS[0]}" | grep -q '^event-skill|Your /compile-data command|missing|'
assert $? 'a missing one reads as missing'
event_skill_installed() { return 0; }

FEATURE_EVENT_SKILL='off'
CHECKS=(); add_event_skill_check
[ "${#CHECKS[@]}" -eq 0 ]
assert $? 'switched off, the row disappears completely'
FEATURE_EVENT_SKILL='on'

# Answered on this Mac. If it ever falls through to the Zo questions it comes
# back "could not tell" on exactly the machines that have not got a key.
zo_verify() { ZO_ANSWER=''; }
[ "$(check_now event-skill)" = 'true' ]
assert $? 'its own check answers here, without asking Zo'

case " $OWNER_COMPLETES " in *' event-skill '*) false ;; *) true ;; esac
assert $? 'it never asks "have you finished that step?" about a file it copied'
case " $NEEDS_ZO_KEY " in *' event-skill '*) false ;; *) true ;; esac
assert $? 'and it does not wait for a Zo key it has no use for'

printf '\n\033[36mHermes One, the last step\033[0m\n'

# Stubbed, so what follows tests the checklist rather than whatever happens to
# be installed on the machine running the suite.
hermes_installed() { return 1; }

all_keys() {
    # $1 = 'key' or 'nokey', $2 = FEATURE_HERMES, $3 = FEATURE_AI_EMPLOYEES.
    # Every row, in order, so the last one can be named.
    FEATURE_HERMES="$2"
    FEATURE_AI_EMPLOYEES="$3"
    FEATURE_AI_ASSISTANT='off'; FEATURE_ZO_SKILLS='off'
    FEATURE_SECOND_BRAIN='off'; FEATURE_GOOGLE='off'
    if [ "$1" = 'nokey' ]; then
        zo_verify() { ZO_ANSWER=''; }
    else
        zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
    fi
    collect_checks >/dev/null
    local entry keys=''
    for entry in "${CHECKS[@]}"; do
        keys="$keys${keys:+ }${entry%%|*}"
    done
    printf '%s' "$keys"
}

last_key() { printf '%s' "${1##* }"; }

[ "$(last_key "$(all_keys key on off)")" = 'hermes-app' ]
assert $? 'it is the last row on the list'

# The one that matters most. collect_checks gives up early when Zo cannot be
# reached, and this row is built after that point - so written in the obvious
# place it would be missing from every machine without a key, which is every
# machine the first time it is opened.
[ "$(last_key "$(all_keys nokey on off)")" = 'hermes-app' ]
assert $? 'with no Zo key at all it is still offered, and still last'

# The other early exit. Employees used to end the function outright, so
# anything after it vanished on every build that ships with them switched off.
[ "$(last_key "$(all_keys key on on)")" = 'hermes-app' ]
assert $? 'switching AI employees back on does not push it off the end'
[ "$(last_key "$(all_keys key on off)")" = 'hermes-app' ]
assert $? 'and switching them off again does not take it with them'

case " $(all_keys key off off) " in *' hermes-app '*) false ;; *) true ;; esac
assert $? 'switched off, the row disappears completely'

FEATURE_HERMES='on'
hermes_installed() { return 0; }
CHECKS=(); add_hermes_check
printf '%s' "${CHECKS[0]}" | grep -q '^hermes-app|Hermes One|ok|'
assert $? 'an installed Hermes One reads as done'
hermes_installed() { return 1; }
CHECKS=(); add_hermes_check
printf '%s' "${CHECKS[0]}" | grep -q '^hermes-app|Hermes One|missing|'
assert $? 'a missing one reads as missing'

# Answered on this Mac. If it ever falls through to the Zo questions it comes
# back "could not tell" on exactly the machines that have not got a key.
hermes_installed() { return 0; }
zo_verify() { ZO_ANSWER=''; }
[ "$(check_now hermes-app)" = 'true' ]
assert $? 'its own check answers here, without asking Zo'
hermes_installed() { return 1; }

case " $OWNER_COMPLETES " in *' hermes-app '*) false ;; *) true ;; esac
assert $? 'it never asks "have you finished that step?" about work it just did'
case " $NEEDS_ZO_KEY " in *' hermes-app '*) false ;; *) true ;; esac
assert $? 'and it does not wait for a Zo key it has no use for'

# Being part of the main setup has one consequence worth stating out loud: the
# AI Personal Assistant one-liner refuses until the main setup is finished, and
# Hermes One is now part of what finished means. Named, so somebody who has
# skipped it is told which step is in the way rather than just "not yet".
FEATURE_HERMES='on'
hermes_installed() { return 1; }
main_setup_unfinished | grep -q 'Hermes One'
assert $? 'an unfinished Hermes One holds the assistant one-liner back, by name'
hermes_installed() { return 0; }
main_setup_unfinished | grep -q 'Hermes One'
assert_not $? 'and once it is installed it stops holding it back'

printf '\n\033[36mWhich Hermes build this Mac gets\033[0m\n'

# The real feed, as published, checked without going near the network.
MAC_FEED_FIXTURE="$(cat <<'YML'
version: 0.7.6
files:
  - url: hermes-desktop-0.7.6-x64-mac.zip
    sha512: SUM_FOR_INTEL
    size: 194080443
  - url: hermes-desktop-0.7.6-arm64-mac.zip
    sha512: SUM_FOR_APPLE_SILICON
    size: 185737105
path: hermes-desktop-0.7.6-x64-mac.zip
sha512: SUM_FOR_INTEL
releaseDate: '2026-07-22T11:49:43.758Z'
YML
)"
curl() { printf '%s\n' "$MAC_FEED_FIXTURE"; }

# This is the trap. The file ends with a second copy of the Intel checksum, at
# the top level, describing the release as a whole - so anything that reaches
# for "the last checksum in the file", or the first one after a match, hands
# every Apple Silicon Mac a checksum belonging to the Intel build. It would
# have failed on nothing but real Apple hardware, which is most customers.
uname() { printf 'arm64\n'; }
[ "$(hermes_mac_asset)" = 'hermes-desktop-0.7.6-arm64-mac.zip SUM_FOR_APPLE_SILICON' ]
assert $? 'an Apple Silicon Mac gets the Apple Silicon build, and its own checksum'

uname() { printf 'x86_64\n'; }
[ "$(hermes_mac_asset)" = 'hermes-desktop-0.7.6-x64-mac.zip SUM_FOR_INTEL' ]
assert $? 'an Intel Mac gets the Intel build, and its own checksum'

# Anything unrecognised is treated as Intel, which every Mac can run.
uname() { printf 'something-new\n'; }
[ "$(hermes_mac_asset)" = 'hermes-desktop-0.7.6-x64-mac.zip SUM_FOR_INTEL' ]
assert $? 'an unfamiliar processor falls back to the build that runs anywhere'

curl() { return 1; }
[ -z "$(hermes_mac_asset)" ]
assert $? 'an unreachable feed says nothing, so the pinned version is used'
unset -f curl uname

# A regression guard, for a line that shipped.
#
# This script never defined a say function, though every other zo-*.sh does -
# so "say Downloading Node.js" called /usr/bin/say and the Mac read it out
# through the speakers instead of printing it. Every clean Mac took that path.
grep -qE '^[[:space:]]*say[[:space:]]+["'"'"']' "$SCRIPT_DIR/vimigo-setup.sh"
assert_not $? 'nothing calls say, which on a Mac speaks the line out loud'

printf '\n\033[36mThe two setups agree on what they offer\033[0m\n'

# A Mac and a Windows machine offering different setups is worse than either
# answer on its own, and nothing else would notice: the two scripts share no
# code, only a promise to stay in step.
WIN="$SCRIPT_DIR/vimigo-setup.ps1"
win_default() { grep -oE "\\\$script:Feature$1 +\\= '[a-z]+'" "$WIN" | head -1 | grep -oE "'[a-z]+'" | tr -d "'"; }
mac_default() { grep -oE "^FEATURE_$1='[a-z]+'" "$SCRIPT_DIR/vimigo-setup.sh" | head -1 | grep -oE "'[a-z]+'" | tr -d "'"; }

[ -n "$(win_default AiAssistant)" ] && [ "$(win_default AiAssistant)" = "$(mac_default AI_ASSISTANT)" ]
assert $? 'both scripts ship the same answer for the AI Personal Assistant'
[ -n "$(win_default ZoSkills)" ] && [ "$(win_default ZoSkills)" = "$(mac_default ZO_SKILLS)" ]
assert $? 'both scripts ship the same answer for the Zo skills'
[ -n "$(win_default SecondBrain)" ] && [ "$(win_default SecondBrain)" = "$(mac_default SECOND_BRAIN)" ]
assert $? 'both scripts ship the same answer for the second brain'
[ -n "$(win_default AiEmployees)" ] && [ "$(win_default AiEmployees)" = "$(mac_default AI_EMPLOYEES)" ]
assert $? 'both scripts ship the same answer for AI employees'
[ -n "$(win_default Hermes)" ] && [ "$(win_default Hermes)" = "$(mac_default HERMES)" ]
assert $? 'both scripts ship the same answer for Hermes One'
# Carried on this side without doing anything yet, so that the pair cannot
# drift. A switch present in one file only is how the two setups come apart.
[ -n "$(win_default ClaudeFeatures)" ] && [ "$(win_default ClaudeFeatures)" = "$(mac_default CLAUDE_FEATURES)" ]
assert $? 'both scripts ship the same answer for the Claude Desktop features'
[ "$(mac_default CLAUDE_FEATURES)" = 'on' ]
assert $? 'and that answer is on, because the training uses Cowork rather than Chat'
# The only one that ships on, so it is worth stating rather than implying.
[ "$(mac_default HERMES)" = 'on' ]
assert $? 'and that answer is on, because it was asked for by name'

printf '\n\033[36mThe switch is generous about what counts as yes\033[0m\n'

for word in on ON On yes true 1 ' on '; do
    feature_on "$word"
    assert $? "\"$word\" turns a feature on"
done
for word in off OFF no false 0 '' maybe onn; do
    feature_on "$word"
    assert_not $? "\"$word\" leaves it off"
done

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
    printf '\033[31m%d of %d checks FAILED.\033[0m\n' "$FAILURES" "$RAN"
    exit 1
fi
printf '\033[32mAll %d checks passed.\033[0m\n' "$RAN"
exit 0
