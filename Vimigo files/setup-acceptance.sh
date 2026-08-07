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

grep -qE '^command = "([^"]*/)?npx"' "$CODEX_CONFIG"
assert $? 'the entry launches npx, by a path ChatGPT can actually find'

connect_zo_to_chatgpt >/dev/null 2>&1
SECTIONS="$(grep -cE '^\[mcp_servers\.zo\]' "$CODEX_CONFIG")"
[ "$SECTIONS" -eq 1 ]
assert $? 'a second run leaves exactly one Zo section'

# The header count alone is not enough: dropping the header but leaving its
# body would orphan `command = "npx"` into whichever section came before,
# silently corrupting a setting the owner never touched.
BODY_LINES="$(grep -cF 'command = "npx"' "$CODEX_CONFIG")"
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
    # $1 = second brain switch, $2 = employees switch, $3 = 'key' or 'nokey'.
    # Prints the rows that live on Zo, in the order the owner reads them.
    FEATURE_SECOND_BRAIN="$1"
    FEATURE_AI_EMPLOYEES="$2"
    if [ "$3" = 'nokey' ]; then
        zo_verify() { ZO_ANSWER=''; }
    else
        zo_verify() { ZO_ANSWER="$ZO_FIXTURE"; }
    fi
    collect_checks >/dev/null 2>&1
    local entry keys=''
    for entry in "${CHECKS[@]}"; do
        case "${entry%%|*}" in
            zo-claude-code|zo-codex|zo-skills|zo-brain|zo-google|talk-to-zo|zo-employees)
                keys="$keys${keys:+ }${entry%%|*}" ;;
        esac
    done
    printf '%s' "$keys"
}

BOTH_ON='zo-claude-code zo-codex zo-skills zo-brain zo-google talk-to-zo zo-employees'
BOTH_OFF='zo-claude-code zo-codex zo-skills zo-google talk-to-zo'

[ "$(zo_rows on on key)" = "$BOTH_ON" ]
assert $? 'switched on, the checklist is in the order it always was'
[ "$(zo_rows off off key)" = "$BOTH_OFF" ]
assert $? 'switched off, both rows go and the rest keeps its order'
[ "$(zo_rows on off key)" = 'zo-claude-code zo-codex zo-skills zo-brain zo-google talk-to-zo' ]
assert $? 'one on and one off takes only the one that is off'
[ "$(zo_rows off on key)" = 'zo-claude-code zo-codex zo-skills zo-google talk-to-zo zo-employees' ]
assert $? 'and the other way round'

# The fault this guards is a real one, shipped for weeks on Windows: the list
# shown before the key is pasted was kept by hand and drifted out of step with
# the list shown after, so pasting the key silently rearranged the screen.
[ "$(zo_rows on on nokey)" = "$(zo_rows on on key)" ]
assert $? 'switched on, pasting the key does not rearrange the list'
[ "$(zo_rows off off nokey)" = "$(zo_rows off off key)" ]
assert $? 'switched off, pasting the key does not rearrange the list either'

# The assistant is not switchable. Every other row can come and go; without
# this one there is nowhere for the owner to type.
case "$(zo_rows off off key)" in *talk-to-zo*) true ;; *) false ;; esac
assert $? 'the AI Personal Assistant survives both switches being off'
case "$(zo_rows off off nokey)" in *talk-to-zo*) true ;; *) false ;; esac
assert $? 'and survives with no key either'

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
    # $1 = second brain, $2 = employees. Prints "1/7 2/7 ..." as the owner sees
    # it, driving the real fix_everything rather than counting rows by hand.
    FEATURE_SECOND_BRAIN="$1"
    FEATURE_AI_EMPLOYEES="$2"
    zo_verify() { ZO_ANSWER="$ZO_UNDONE"; }
    collect_checks >/dev/null 2>&1
    fix_everything 2>&1 |
        sed -n 's/.*Step \([0-9][0-9]*\) of \([0-9][0-9]*\).*/\1\/\2/p' |
        tr '\n' ' ' | sed 's/ *$//'
}

trail_is_whole() {
    # Passes when the numbers run 1..N with no gaps and N is the total claimed.
    local trail="$1" want=1 total='' pair
    for pair in $trail; do
        [ "${pair%%/*}" = "$want" ] || return 1
        total="${pair##*/}"
        want=$((want + 1))
    done
    [ -n "$total" ] && [ "$((want - 1))" = "$total" ]
}

TRAIL_OFF="$(step_trail off off)"
TRAIL_ON="$(step_trail on on)"

trail_is_whole "$TRAIL_OFF"
assert $? 'switched off, the steps run 1..N with no gaps and end on the total'
trail_is_whole "$TRAIL_ON"
assert $? 'switched on, the steps run 1..N with no gaps and end on the total'

# Counted as a difference, not as an absolute: how many local rows are
# outstanding depends on the machine this suite runs on, but switching two
# features off must remove exactly two steps anywhere.
steps_off="$(printf '%s' "$TRAIL_OFF" | wc -w | tr -d ' ')"
steps_on="$(printf '%s' "$TRAIL_ON" | wc -w | tr -d ' ')"
[ "$((steps_on - steps_off))" -eq 2 ]
assert $? 'switching both off removes exactly two steps, no more and no fewer'

case "$TRAIL_OFF" in *WOULD_DO*) false ;; *) true ;; esac
assert $? 'and nothing was actually run to find that out'

printf '\n\033[36mA switched-off feature takes its key with it\033[0m\n'

menu_keys() {
    # $1 = second brain, $2 = employees. Prints the letters the finished menu
    # offers, in order.
    FEATURE_SECOND_BRAIN="$1"
    FEATURE_AI_EMPLOYEES="$2"
    # Colours stripped first. They are empty until apply_theme runs, so a
    # pattern that looked for them found nothing and every row read as absent.
    show_main_options finished 2>&1 |
        sed 's/[[:cntrl:]]\[[0-9;]*m//g' |
        awk '$1 ~ /^[A-Z]$/ && NF > 1 { printf "%s%s", sep, $1; sep = " " }'
}

[ "$(menu_keys on on)" = 'E T A M Z S Q' ]
assert $? 'switched on, the finished menu offers every key it always did'
[ "$(menu_keys off off)" = 'A Z S Q' ]
assert $? 'switched off, E, T and M are gone and the rest is unmoved'
[ "$(menu_keys on off)" = 'A M Z S Q' ]
assert $? 'the second brain alone leaves M and takes E and T'
[ "$(menu_keys off on)" = 'E T A Z S Q' ]
assert $? 'employees alone leave E and T and take M'

# Hidden is not enough. A key that still fires while nothing on screen mentions
# it is worse than a missing one: the owner presses E by accident and this
# build hires somebody it was never meant to be able to hire.
hire_employee() { printf 'RAN_HIRE\n'; }
show_team_screen() { printf 'RAN_TEAM\n'; }
setup_second_brain() { printf 'RAN_BRAIN\n'; }

pressed() {
    # $1 = second brain, $2 = employees, $3 = the key. Prints what ran, or
    # NOTHING when the key was refused.
    FEATURE_SECOND_BRAIN="$1"
    FEATURE_AI_EMPLOYEES="$2"
    local out
    out="$(printf '\n' | handle_main_choice "$3" 2>&1 | grep -E 'RAN_' | head -1)"
    printf '%s' "${out:-NOTHING}"
}

[ "$(pressed off off e)" = 'NOTHING' ]
assert $? 'pressing E with employees switched off hires nobody'
[ "$(pressed off off t)" = 'NOTHING' ]
assert $? 'pressing T with employees switched off shows no team'
[ "$(pressed off off m)" = 'NOTHING' ]
assert $? 'pressing M with the second brain switched off builds nothing'
[ "$(pressed on on e)" = 'RAN_HIRE' ]
assert $? 'and switched on, E still hires'
[ "$(pressed on on t)" = 'RAN_TEAM' ]
assert $? 'switched on, T still shows the team'
[ "$(pressed on on m)" = 'RAN_BRAIN' ]
assert $? 'switched on, M still builds the second brain'

printf '\n\033[36mStart over renumbers itself\033[0m\n'

reset_whatsapp_assistant() { printf 'RAN_ASSISTANT\n'; }
reset_ai_employees() { printf 'RAN_EMPLOYEES\n'; }
get_installed_by_us() { printf ''; }
ask_yes_no() { return 1; }

reset_pick() {
    # $1 = employees switch, $2 = what the owner types. Prints what ran.
    FEATURE_AI_EMPLOYEES="$1"
    local out
    out="$(printf '%s\n' "$2" | reset_vimigo_setup 2>&1 |
        grep -Eo 'RAN_ASSISTANT|RAN_EMPLOYEES|Nothing was changed' | head -1)"
    printf '%s' "${out:-NOTHING}"
}

reset_prompt() {
    FEATURE_AI_EMPLOYEES="$1"
    printf '\n' | reset_vimigo_setup 2>&1 | grep -o 'Choose [^>]*' | head -1
}

[ "$(reset_prompt on)" = 'Choose 1, 2 or 3, or Enter to go back ' ]
assert $? 'switched on, start over still offers three'
[ "$(reset_prompt off)" = 'Choose 1 or 2, or Enter to go back ' ]
assert $? 'switched off, it offers two and says so'

[ "$(reset_pick on 1)" = 'RAN_ASSISTANT' ]
assert $? 'switched on, 1 is the assistant'
[ "$(reset_pick on 2)" = 'RAN_EMPLOYEES' ]
assert $? 'switched on, 2 lets an employee go'
[ "$(reset_pick off 1)" = 'RAN_ASSISTANT' ]
assert $? 'switched off, 1 is still the assistant'
# The one that bites. Hiding the middle option without renumbering leaves 2
# wired to the employee reset - a key nothing on screen mentions, quietly
# letting an AI employee go.
[ "$(reset_pick off 2)" != 'RAN_EMPLOYEES' ]
assert $? 'switched off, 2 never reaches the employee reset'
[ "$(reset_pick off 3)" = 'Nothing was changed' ]
assert $? 'switched off, the old number 3 does nothing at all'
[ "$(reset_pick on '')" = 'Nothing was changed' ]
assert $? 'Enter goes back without changing anything'
[ "$(reset_pick on 08)" = 'Nothing was changed' ]
assert $? 'a leading zero is read as text, not as octal'

printf '\n\033[36mThe two setups agree on what they offer\033[0m\n'

# A Mac and a Windows machine offering different setups is worse than either
# answer on its own, and nothing else would notice: the two scripts share no
# code, only a promise to stay in step.
WIN="$SCRIPT_DIR/vimigo-setup.ps1"
win_default() { grep -oE "\\\$script:Feature$1 = '[a-z]+'" "$WIN" | head -1 | grep -oE "'[a-z]+'" | tr -d "'"; }
mac_default() { grep -oE "^FEATURE_$1='[a-z]+'" "$SCRIPT_DIR/vimigo-setup.sh" | head -1 | grep -oE "'[a-z]+'" | tr -d "'"; }

[ -n "$(win_default SecondBrain)" ] && [ "$(win_default SecondBrain)" = "$(mac_default SECOND_BRAIN)" ]
assert $? 'both scripts ship the same answer for the second brain'
[ -n "$(win_default AiEmployees)" ] && [ "$(win_default AiEmployees)" = "$(mac_default AI_EMPLOYEES)" ]
assert $? 'both scripts ship the same answer for AI employees'

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
