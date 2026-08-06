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

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
    printf '\033[31m%d of %d checks FAILED.\033[0m\n' "$FAILURES" "$RAN"
    exit 1
fi
printf '\033[32mAll %d checks passed.\033[0m\n' "$RAN"
exit 0
