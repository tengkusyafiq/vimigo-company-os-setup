#!/usr/bin/env bash
#
# Vimigo AI Setup - macOS.
#
# Gets this Mac ready to use Zo with Claude Desktop and ChatGPT.
#
# Nothing is installed until you ask for it. The script opens on a status
# screen showing what is already here and what is missing, and every action
# re-checks afterwards instead of trusting an installer's exit code.
#
# Safe to run as many times as you like. Anything already installed is left
# exactly as it is, and existing app configuration is backed up before it is
# changed and never overwritten wholesale.
#
# Usage:
#   ./vimigo-setup.sh          opens the status menu
#   ./vimigo-setup.sh --check  prints the status once and exits, changes nothing

set -u
set -o pipefail

# ---------------------------------------------------------------------------
# What this build offers
# ---------------------------------------------------------------------------
# Two parts of the setup can be switched off for a release that has to stay
# simple. Switched off they disappear from the checklist, from the menu, and
# from the "start over" screen - so the owner is never shown a step this build
# will not do, and never a key that does nothing.
#
# Off is not the same as gone. Every line of code behind them still ships and
# still works; only the ways in are closed. Turning one back on restores the
# same screens it always had, and needs no other change.
#
# One rule holds however these are set: the owner must finish with a way to
# reach their Zo. Claude Desktop and ChatGPT are that way, and they are not
# switchable - so switching the WhatsApp assistant off leaves a setup whose
# point is "your laptop's AI can now read and act on your business", which is a
# smaller promise but a whole one.
#
# vimigo-setup.ps1 carries the same six names with the same defaults, and the
# acceptance suite fails if they ever disagree - a Mac and a Windows machine
# offering different setups is worse than either answer on its own.
FEATURE_AI_ASSISTANT='off'
FEATURE_ZO_SKILLS='off'
FEATURE_GOOGLE='off'
FEATURE_SECOND_BRAIN='off'
FEATURE_AI_EMPLOYEES='off'
# The one switch that ships on. Hermes One is an app on this Mac rather than
# anything on Zo, so it is the only one here that needs no key and no account -
# which is also why it can safely be last.
FEATURE_HERMES='on'
# Carried here, and does nothing here yet.
#
# On Windows this is the row that switches on virtualisation so Claude Desktop's
# Cowork tab works, and it is on because the training uses Cowork and Claude
# Code rather than Chat. A Mac has no equivalent row today; whether it needs one
# is still waiting on a customer's actual error text.
#
# The name is declared anyway so the two files carry the same switches and the
# acceptance suites can hold them to it. A switch that exists in one file only
# is how the two setups drift apart without anybody noticing.
FEATURE_CLAUDE_FEATURES='on'
# What the finished screen offers besides Close.
#
# Off, so "ALL DONE" ends the setup instead of presenting a menu. The two rows
# it hides are "Open your Zo", which is a website the owner can reach anyway,
# and "Start over", which removes what the setup installed - a destructive
# action sitting one keypress away on the screen an owner is most likely to be
# tapping at idly, having just been told everything worked.
#
# Start over is not lost: ./vimigo-setup.sh --reset runs it directly, which is
# how support and testing reach it now.
FEATURE_FINISHED_MENU='off'

# One run, without editing the file - for support, or a demo:
#     VIMIGO_FEATURE_AI_EMPLOYEES=on ./vimigo-setup.sh
# It overrides in both directions, so it can also turn one off.
if [ -n "${VIMIGO_FEATURE_AI_ASSISTANT:-}" ]; then
    FEATURE_AI_ASSISTANT="$VIMIGO_FEATURE_AI_ASSISTANT"
fi
if [ -n "${VIMIGO_FEATURE_ZO_SKILLS:-}" ]; then
    FEATURE_ZO_SKILLS="$VIMIGO_FEATURE_ZO_SKILLS"
fi
if [ -n "${VIMIGO_FEATURE_GOOGLE:-}" ]; then
    FEATURE_GOOGLE="$VIMIGO_FEATURE_GOOGLE"
fi
if [ -n "${VIMIGO_FEATURE_SECOND_BRAIN:-}" ]; then
    FEATURE_SECOND_BRAIN="$VIMIGO_FEATURE_SECOND_BRAIN"
fi
if [ -n "${VIMIGO_FEATURE_AI_EMPLOYEES:-}" ]; then
    FEATURE_AI_EMPLOYEES="$VIMIGO_FEATURE_AI_EMPLOYEES"
fi
if [ -n "${VIMIGO_FEATURE_HERMES:-}" ]; then
    FEATURE_HERMES="$VIMIGO_FEATURE_HERMES"
fi
if [ -n "${VIMIGO_FEATURE_CLAUDE_FEATURES:-}" ]; then
    FEATURE_CLAUDE_FEATURES="$VIMIGO_FEATURE_CLAUDE_FEATURES"
fi
if [ -n "${VIMIGO_FEATURE_FINISHED_MENU:-}" ]; then
    FEATURE_FINISHED_MENU="$VIMIGO_FEATURE_FINISHED_MENU"
fi

feature_on() {
    # Generous about what counts as yes.
    #
    # Somebody reaching for this is typing an environment variable on a support
    # call, and 'ON', 'true' or '1' meeting silence would read as the switch
    # being broken rather than as the wrong word.
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
        on|yes|true|1) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZO_MCP_URL="https://api.zo.computer/mcp"
ZO_MCP_ENTRY="zo"
MCP_REMOTE_PACKAGE="mcp-remote@latest"

CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

STATE_DIR="$HOME/.vimigo-setup"

# Vimigo's Zo referral link. Anyone signing up as part of this setup goes
# through it, so new accounts are attributed correctly.
ZO_SIGNUP_URL="https://zo-computer.cello.so/0qDXmlEF6Hn"
CHATGPT_DOWNLOAD_URL="https://openai.com/chatgpt/download/"
CLAUDE_DOWNLOAD_URL="https://claude.ai/download"

# ---------------------------------------------------------------------------
# Hermes One
# ---------------------------------------------------------------------------
# The desktop app for Hermes Agent. Note whose it is: Hermes Agent belongs to
# Nous Research, but this app does not - it is a community build, and its own
# README says so. It is the one this setup was asked for by name.
#
# Its product name is "Hermes One" and its executable is called hermes-agent,
# both taken from the project's electron-builder.yml rather than guessed.
HERMES_APP_NAME='Hermes One'
HERMES_DOWNLOAD_PAGE='https://hermesone.org/download'
HERMES_RELEASES='https://github.com/fathah/hermes-desktop/releases'

# Which build to fetch is read from the project's own update feed rather than
# from GitHub's API. The API allows sixty calls an hour per address, and a room
# of a hundred and twenty people on one venue wifi shares a single address -
# so the API would have answered the first few laptops and rate-limited the
# rest. This file is an ordinary release download and is not counted.
HERMES_MAC_FEED="$HERMES_RELEASES/latest/download/latest-mac.yml"

# Used only when the feed cannot be reached. It goes stale by design: a pinned
# version that still installs is better than a setup that cannot install
# anything because GitHub was slow.
HERMES_PINNED_VERSION='0.7.6'

# The token lives in the login keychain, not in a file of ours. It does still
# end up inside each AI app's own config file, because that is the only shape
# those apps accept today. The status screen says so plainly.
KEYCHAIN_SERVICE="vimigo-setup-zo-token"

# ---------------------------------------------------------------------------
# The Zo skills worth having on every customer's Zo
# ---------------------------------------------------------------------------
# Names exactly as they appear in Zo's own Skills catalogue.
#
# Note the absence of a "zo-" prefix. That prefix is the publisher tag shown
# beside a skill, not part of its name, and searching for it finds nothing -
# which is how six of these were briefly written off as non-existent.
#
# Two parallel arrays rather than one keyed table: macOS ships bash 3.2, which
# has no associative arrays at all. Same reason for the AI employees below.
ZO_SKILL_KEYS=(
    'morning-briefing'
    'important-email-digest'
    'research-topic'
    'automate-something'
    'generate-pdf'
    'extract-text-from-image'
    'organize-workspace'
    'web-scraper'
    'skill-creator'
)
ZO_SKILL_NOTES=(
    'a daily briefing, at a time you choose'
    'the emails that actually matter, summarised'
    'research anything properly and write it up'
    'turn a repeated job into an automation'
    'turn notes into a proper PDF'
    'read text out of photos, scans and PDFs'
    'tidy scattered files into sensible folders'
    'pull information off websites'
    'teach your Zo something new'
)

# ---------------------------------------------------------------------------
# The AI employees a business can hire
# ---------------------------------------------------------------------------
# One per department, in roughly the order a small Malaysian business needs
# them. Each is a Zo persona: a name and a prompt describing the job.
#
# Permissions are left wide open on purpose - the owner can narrow any of them
# later on their own personas page, and a new employee that cannot do anything
# is a worse first impression than one that can do too much.
EMPLOYEE_KEYS=(
    'assistant' 'admin' 'sales' 'customer-service'
    'accountant' 'marketing' 'hr' 'operations'
)
EMPLOYEE_TITLES=(
    'AI Personal Assistant'
    'AI Admin'
    'AI Sales'
    'AI Customer Service'
    'AI Accountant'
    'AI Marketing'
    'AI HR'
    'AI Operations'
)
EMPLOYEE_FOR=(
    'your diary, mail, reminders, anything'
    'forms, filing, appointments, renewals'
    'quotes, follow-ups, people who went quiet'
    'customer questions, orders, complaints'
    'invoices, receipts, spending, who owes money'
    'posts, captions, promotions'
    'leave, shifts, new joiners, staff questions'
    'stock, suppliers, deliveries, schedules'
)

employee_prompt() {
    # $1 = one of EMPLOYEE_KEYS. Prints the job description sent to Zo.
    #
    # Written for someone who has never used AI. Plain sentences, no jargon,
    # and an instruction to ask rather than guess, because an employee that
    # invents an answer to a customer is worse than one that says "let me check
    # with the boss".
    #
    # Every one of these ends with the same line about the owner having no
    # technical background. That is the hard rule in AGENTS.md and it belongs in
    # the brief itself, not only in the setup: the employee is the thing that
    # actually talks to them, and a brief that leaves it out is an employee that
    # will one day tell a sixty-year-old shop owner to open a terminal.
    #
    # Each one says what it must never do, in the terms the mistake would be
    # made in - a price in RM, a delivery date, a refund, someone's pay -
    # because a customer believes whatever an employee tells them.
    #
    # Kept identical to $script:AiEmployees in vimigo-setup.ps1, and copied from
    # it rather than retyped. They drifted once: the Mac kept an older, softer
    # set that never got the language instruction, the RM rule, the payment
    # guard or the technical-background line, so an employee hired on a Mac was
    # created materially weaker than the same employee hired on Windows. If you
    # change one, change both.
    #
    # Quoted heredocs, so an apostrophe in "the owner's" is just an apostrophe
    # and nothing in the text is ever expanded as a shell variable.
    case "$1" in
        assistant) cat <<'PROMPT'
You are the owner's own assistant. You help with their diary, their email,
their files, reminders, and anything else they ask. Keep answers short and
plain. Reply in the language they write in, English, Malay or a mix. Only
people the owner has approved can reach you; tell nobody else anything about
the owner or the business. Never send a message, book anything or spend money
for them until they have seen it and said yes. If you are not sure, ask the
owner rather than guess. If someone else asks, say let me check with the boss.
The owner has no technical background, so never ask them to run a command,
open a file or read a log.
PROMPT
            ;;
        admin) cat <<'PROMPT'
You keep the business paperwork in order. Forms, filing, appointments, staff
records and licence renewals. When something is missing, say what is missing.
Never invent a name, a date, a reference number or an amount to fill a gap.
Never sign anything, submit a form, move or cancel an appointment, or give out
someone's personal details until the owner has read it and said yes. If a
letter or bill looks important, pass it to the owner rather than act on it. If
the owner has not told you, say let me check with the boss. The owner has no
technical background, so never ask them to run a command, open a file or read
a log.
PROMPT
            ;;
        sales) cat <<'PROMPT'
You help the business sell. You answer people asking about buying, mostly on
WhatsApp, follow up with the ones who went quiet, and track who is still
waiting. Be warm, never pushy, and reply in the language they used. Customers
believe what you tell them, so never quote a price in RM, offer a discount,
promise a delivery date, or say something is in stock unless the owner has
given you that exact figure or date. Never take payment or agree terms for the
business. When you do not know, say let me check with the boss. The owner has
no technical background, so never ask them to run a command, open a file or
read a log.
PROMPT
            ;;
        customer-service) cat <<'PROMPT'
You answer the business's customers, mostly on WhatsApp. Be patient and
polite, keep replies short, and answer in the language they wrote in, Malay,
English or a mix. You only know what the owner has taught you. Never promise a
refund, a replacement, a discount, a delivery date or any amount in RM, and
never give out a staff member's name or number. If a customer is angry or
asking about money, stay kind and pass them to the owner. Saying you do not
know is better than guessing, so say let me check with the boss. The owner has
no technical background, so never ask them to run a command, open a file or
read a log.
PROMPT
            ;;
        accountant) cat <<'PROMPT'
You keep the money side in order. Invoices, receipts, spending, and who still
owes what. Every figure is in RM and must be exact. Never round, never
estimate, and never fill in a number you cannot see on a document; if
something is missing or does not add up, say so. Never send an invoice or
payment reminder, share a bank account number, agree to a discount or
instalment plan, or tell anyone what a customer or staff member owes or earns,
until the owner says yes. If you are unsure, say let me check with the boss.
The owner has no technical background, so never ask them to run a command,
open a file or read a log.
PROMPT
            ;;
        marketing) cat <<'PROMPT'
You help the business get noticed. Write WhatsApp broadcasts, Facebook and
Instagram captions, and promotion ideas in the owner's own voice. Sound like a
real person, not a brochure. Everything you write is a draft: never post, send
or publish anything anywhere yourself. Never invent a price in RM, a discount,
a free gift, a halal or health claim, an award or a review, and never use a
customer's name, photo or words without the owner confirming they agreed. If
you are unsure whether something is true, leave it out and say let me check
with the boss. The owner has no technical background, so never ask them to run
a command, open a file or read a log.
PROMPT
            ;;
        hr) cat <<'PROMPT'
You help with the staff. Leave, shifts, new joiners, EPF and SOCSO questions,
and the small things people ask every day. Reply in Malay when staff write in
Malay. Be fair, be kind, and treat every message as private. Never approve or
reject leave, never confirm a shift change, and never discuss anyone's pay,
warning, complaint, medical certificate or job being at risk; all of that goes
to the owner. Never repeat what one person told you to another. If you do not
know the rule, say let me check with the boss. The owner has no technical
background, so never ask them to run a command, open a file or read a log.
PROMPT
            ;;
        operations) cat <<'PROMPT'
You keep the day running. Stock, suppliers, deliveries and who is doing what.
Tell the owner early when something is running low, running late or about to
clash. Never place an order, agree a supplier's price in RM, confirm a
delivery time to a customer, change someone's shift, or tell one supplier
anything about another, without the owner saying yes first. Write to suppliers
and drivers in the language they use, usually short Malay or English. If you
do not know what is in stock or when something arrives, say let me check with
the boss. The owner has no technical background, so never ask them to run a
command, open a file or read a log.
PROMPT
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# The Vimigo brand colours, straight from the logo. The purple is lifted a
# little from the mark's own #6A5BA6, which is too close to the background to
# read as text.
if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_TEAL=$'\033[38;2;108;197;217m'
    C_YELLOW=$'\033[38;2;252;211;74m'
    C_CORAL=$'\033[38;2;236;97;82m'
    C_PURPLE=$'\033[38;2;150;135;210m'
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'
    C_GREY=$'\033[90m'; C_WHITE=$'\033[97m'
else
    C_RESET=""; C_TEAL=""; C_YELLOW=""; C_CORAL=""; C_PURPLE=""
    C_GREEN=""; C_RED=""; C_GREY=""; C_WHITE=""
fi

# A soft dark blue-grey page rather than pure black. Black with bright text is
# high-contrast and glaring to sit in front of for the length of a setup.
# Handed back on the way out so later commands do not inherit our colours.
apply_theme() {
    [ -t 1 ] || return 0
    [ -n "${VIMIGO_NO_THEME:-}" ] && return 0
    printf '\033]11;#1E232C\007\033]10;#DCE2EC\007'
    return 0
}

reset_theme() {
    [ -t 1 ] || return 0
    [ -n "${VIMIGO_NO_THEME:-}" ] && return 0
    printf '\033]111\007\033]110\007'
    return 0
}

title() {
    local pad=$(( 42 - ${#1} ))
    [ "$pad" -lt 4 ] && pad=4
    printf '\n    %s┏━ %s%s%s ' "$C_PURPLE" "$C_TEAL" "$1" "$C_PURPLE"
    printf '━%.0s' $(seq 1 "$pad")
    printf '%s\n\n' "$C_RESET"
}

# One instruction, with the number in its own colour so a list of them scans as
# a list rather than a paragraph.
numbered() {
    # $1 = number, $2 = text, $3 = optional highlighted tail
    printf '        %s %s %s  %s%s%s' "$C_YELLOW" "$1" "$C_RESET" "$C_WHITE" "$2" "$C_RESET"
    if [ -n "${3:-}" ]; then
        printf ' %s%s%s\n' "$C_TEAL" "$3" "$C_RESET"
    else
        printf '\n'
    fi
}

info()  { printf '      %s%s%s\n' "$C_GREY" "$1" "$C_RESET"; }
good()  { printf '      %s%s%s\n' "$C_GREEN" "$1" "$C_RESET"; }
warn()  { printf '      %s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
bad()   { printf '      %s%s%s\n' "$C_RED" "$1" "$C_RESET"; }

ask_yes_no() {
    local question="$1" answer
    while true; do
        printf '\n      %s%s%s\n' "$C_WHITE" "$question" "$C_RESET"
        printf '         %s Y %s%s Yes      %s N %s%s No%s\n' \
            "$C_TEAL" "$C_RESET" "$C_GREY" "$C_CORAL" "$C_RESET" "$C_GREY" "$C_RESET"
        printf '      %s> %s' "$C_PURPLE" "$C_RESET"
        read -r answer || return 1
        case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     printf '      %sPlease press Y or N.%s\n' "$C_GREY" "$C_RESET" ;;
        esac
    done
}

# A marker that turns while something long is happening on Zo. Animating needs
# something to animate against, so it is drawn between polls rather than during
# one - the marker moving is the only thing telling the owner a four-minute
# build has not hung.
#
# Whole array elements, never sliced. ${row:i:1} counts bytes rather than
# characters, and each of these is three bytes in UTF-8.
WAIT_MARKERS=('◐' '◓' '◑' '◒')

wait_marker() {
    # $1 = frame counter.
    printf '%s' "${WAIT_MARKERS[$(( $1 % ${#WAIT_MARKERS[@]} ))]}"
}

clear_wait_line() {
    # Wipes the whole line so the result prints on a clean row.
    printf '\r%72s\r' ''
}

menu_number() {
    # $1 = whatever the owner typed at a numbered menu. Prints a plain number,
    # or nothing at all.
    #
    # Trimmed to three digits on purpose. A long run of digits overflows the
    # shell's own arithmetic, and `[ 99999999999999999999 -gt 9 ]` prints a
    # raw error at somebody who only leaned on a key.
    printf '%s' "${1:-}" | tr -cd '0-9' | cut -c1-3
}

# ---------------------------------------------------------------------------
# Notes for the steps that happen on Zo's website
# ---------------------------------------------------------------------------

# Asks the owner's Zo what is actually connected, rather than keeping a note of
# what they said. Zo is the only thing that knows, so WhatsApp and the Google
# apps are reported from Zo's own answer.
#
# ZO_ANSWER holds the raw JSON for one render pass. Empty means the question
# could not be asked at all, which is a different situation from "not
# connected" and the screen says so.

ZO_ANSWER=""

zo_verify() {
    ZO_ANSWER=""
    local token="$1"
    case "$token" in zo_sk_*) ;; *) return 0 ;; esac

    local helper="$SCRIPT_DIR/zo-verify.js"
    [ -f "$helper" ] || return 0
    node_bin >/dev/null || return 0

    local answer
    answer="$("$(node_bin)" "$helper" "$token" 2>/dev/null)" || return 0
    case "$answer" in *'"ok":true'*) ZO_ANSWER="$answer" ;; esac
    return 0
}

zo_field() {
    # $1 = a JavaScript expression over `data`, written as a literal in this
    # file. It is substituted into the program text and parsed by node as code.
    [ -n "$ZO_ANSWER" ] || return 0
    printf '%s' "$ZO_ANSWER" | "$(node_bin)" -e "
        let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{
            const data = JSON.parse(s);
            process.stdout.write(String($1));
        });" 2>/dev/null
}

# ---------------------------------------------------------------------------
# The Zo token
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Remembered answers
# ---------------------------------------------------------------------------
# Only what the owner TYPED is remembered - their Zo address, the WhatsApp
# number - so a second run does not ask again.
#
# What is remembered is never what is DONE. Status is re-detected every run.
# A note saying "WhatsApp: connected" keeps saying it after the phone unlinks
# the device, and the owner then stares at a green tick wondering why nothing
# works. Detection cannot go stale; a note can.
#
# The Zo key is deliberately not here. It stays in the login keychain.

PROFILE_FILE="$STATE_DIR/profile"

profile_get() {
    # $1 = key. Prints the value, or nothing.
    [ -f "$PROFILE_FILE" ] || return 0
    grep -E "^$1=" "$PROFILE_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

profile_set() {
    # $1 = key, $2 = value.
    mkdir -p "$STATE_DIR"
    touch "$PROFILE_FILE"
    local kept; kept="$(grep -vE "^$1=" "$PROFILE_FILE" 2>/dev/null || true)"
    printf '%s\n' "$kept" | grep -vE '^$' > "$PROFILE_FILE.tmp" 2>/dev/null || true
    printf '%s=%s\n' "$1" "$2" >> "$PROFILE_FILE.tmp"
    mv "$PROFILE_FILE.tmp" "$PROFILE_FILE"
    chmod 600 "$PROFILE_FILE"
}

ZO_WORKSPACE_URL=""

restore_workspace_url() {
    local saved; saved="$(profile_get workspaceUrl)"
    # Validated on the way in: a tampered file must not become a link the setup
    # opens in the owner's browser.
    case "$saved" in
        https://*.zo.computer) ZO_WORKSPACE_URL="$saved" ;;
    esac
    return 0
}

save_workspace_url() {
    [ -n "${1:-}" ] || return 0
    ZO_WORKSPACE_URL="$1"
    profile_set workspaceUrl "$1"
}

zo_settings_url() {
    if [ -n "$ZO_WORKSPACE_URL" ]; then
        printf '%s/?t=settings&s=advanced' "$ZO_WORKSPACE_URL"
    else
        printf 'https://zo.computer'
    fi
}

zo_integrations_url() {
    if [ -n "$ZO_WORKSPACE_URL" ]; then
        printf '%s/?t=settings&s=integrations' "$ZO_WORKSPACE_URL"
    else
        printf 'https://zo.computer'
    fi
}

zo_ai_settings_url() {
    # The AI page, where providers are connected and default models chosen.
    # A different tab from the Access Key page: sending the owner to the wrong
    # one and asking them to find Providers is the sort of small wrongness that
    # makes a setup feel unreliable.
    if [ -n "$ZO_WORKSPACE_URL" ]; then
        printf '%s/?t=settings&s=ai' "$ZO_WORKSPACE_URL"
    else
        printf 'https://zo.computer'
    fi
}

zo_personas_url() {
    # $1 = optional persona id.
    #
    # Given an id, the link opens that one employee rather than the list.
    # Landing on a list of eight and having to work out which one was just
    # created is a small puzzle, and the owner did not ask for a puzzle.
    if [ -z "$ZO_WORKSPACE_URL" ]; then printf 'https://zo.computer'; return 0; fi
    if [ -n "${1:-}" ]; then
        printf '%s/?t=settings&s=ai&d=personas:%s' "$ZO_WORKSPACE_URL" "$1"
    else
        printf '%s/?t=settings&s=ai&d=personas' "$ZO_WORKSPACE_URL"
    fi
}

zo_skills_url() {
    if [ -n "$ZO_WORKSPACE_URL" ]; then
        printf '%s/?t=skills' "$ZO_WORKSPACE_URL"
    else
        printf 'https://zo.computer'
    fi
}

skills_folder() {
    # The skill folders travel with the setup, beside this script.
    printf '%s/skills' "$SCRIPT_DIR"
}

# ---------------------------------------------------------------------------

get_zo_token() {
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "zo" -w 2>/dev/null || true
}

save_zo_token() {
    local token="$1"
    # Replace rather than stack duplicates in the keychain.
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "zo" >/dev/null 2>&1 || true
    security add-generic-password -s "$KEYCHAIN_SERVICE" -a "zo" -w "$token" -U >/dev/null 2>&1
}

remove_zo_token() {
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "zo" >/dev/null 2>&1 || true
    return 0
}

token_looks_valid() {
    case "${1:-}" in
        zo_sk_*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# What this setup installed, as opposed to what was already here
# ---------------------------------------------------------------------------
# The distinction is the whole point. A Mac that already had Node before any of
# this ran is a Mac where removing Node breaks whatever was using it.
# Uninstalling on the basis of "the setup manages this" and not "the setup
# installed this" is how a reset takes somebody's work with it.

add_installed_by_us() {
    # $1 = key, e.g. node
    local existing; existing="$(profile_get installedByUs)"
    case ",$existing," in *",$1,"*) return 0 ;; esac
    if [ -n "$existing" ]; then
        profile_set installedByUs "$existing,$1"
    else
        profile_set installedByUs "$1"
    fi
}

get_installed_by_us() {
    # Prints one key per line.
    profile_get installedByUs | tr ',' '\n' | grep -vE '^$' || true
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

command_version() {
    # $1 = command, rest = version args. Prints a dotted version, or nothing.
    local command="$1"; shift
    command -v "$command" >/dev/null 2>&1 || return 0
    local raw
    raw="$("$command" "$@" 2>&1)" || return 0
    printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1
}

have_homebrew() { command -v brew >/dev/null 2>&1; }

# Everything this setup does with Zo goes through zo-verify.js, and that calls
# fetch. fetch is built into Node from 18 and simply does not exist before it,
# so an older Node fails every single Zo action while looking perfectly
# installed.
NODE_MIN_MAJOR=18

node_bin() {
    # Prints the path to node, or nothing. Config editing needs it, and so does
    # the Zo connection itself, so it is never an extra dependency: the setup
    # installs Node before it ever reaches a step that edits a config file.
    command -v node 2>/dev/null
}

node_too_old() {
    # True when node is here but older than Zo needs. False when it is fine,
    # and false when there is no node at all - that is "missing", a different
    # row with a different fix.
    local raw major
    raw="$(node_bin)"
    [ -n "$raw" ] || return 1
    major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    case "$major" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$major" -lt "$NODE_MIN_MAJOR" ]
}

npx_bin() {
    # The full path to npx, never the bare word.
    #
    # Claude Desktop on macOS launches an MCP server with a minimal PATH -
    # /usr/bin:/bin:/usr/sbin:/sbin - and ignores what the app's own settings
    # say. Node from Homebrew lives in /opt/homebrew/bin on Apple Silicon and
    # /usr/local/bin on Intel, and neither is on that list, so a config that
    # just says "npx" produces an MCP server that never starts and a Zo that
    # is silently absent from the app. Windows inherits a fuller PATH, which is
    # why the same config works there and hid this.
    local found
    found="$(command -v npx 2>/dev/null)"
    [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    # Fall back to npx sitting beside the node we found.
    local node; node="$(node_bin)"
    [ -n "$node" ] && [ -x "$(dirname "$node")/npx" ] && {
        printf '%s' "$(dirname "$node")/npx"; return 0; }
    printf 'npx'
}

brew_bin() {
    # Apple Silicon and Intel put Homebrew in different places.
    if [ -x /opt/homebrew/bin/brew ]; then printf '/opt/homebrew/bin/brew'
    elif [ -x /usr/local/bin/brew ]; then printf '/usr/local/bin/brew'
    elif command -v brew >/dev/null 2>&1; then command -v brew
    fi
}

load_homebrew_env() {
    local brew; brew="$(brew_bin)"
    [ -n "$brew" ] || return 0
    eval "$("$brew" shellenv)" 2>/dev/null || true
}

find_local_whatsapp() {
    # The WhatsApp bridge belongs on Zo and never on this Mac: a laptop that
    # sleeps drops the WhatsApp connection, and a local build drags in Xcode
    # command line tools and a launch agent for no benefit.
    #
    # An earlier setup guide installed it locally, so machines set up that way
    # still have one. This only reports. It never deletes: the store folder
    # holds the linked WhatsApp session, and losing it costs a re-pair.
    local found=""
    local candidate
    for candidate in "$HOME/Dev/whatsapp-mcp-go" "$HOME/whatsapp-mcp-go" \
                     "$HOME/Documents/whatsapp-mcp-go" "$HOME/whatsapp-mcp"; do
        [ -d "$candidate" ] && found="$found$candidate"$'\n'
    done
    if launchctl list 2>/dev/null | grep -qi 'whatsapp'; then
        found="${found}a WhatsApp launch agent"$'\n'
    fi
    printf '%s' "$found"
}

show_local_whatsapp() {
    title 'WhatsApp is installed on this Mac'

    local found; found="$(find_local_whatsapp)"
    if [ -z "$found" ]; then
        good 'Nothing found. WhatsApp belongs on Zo, and that is where it is.'
        return 0
    fi

    info 'WhatsApp should run on your Zo, not on this Mac. A laptop that'
    info 'sleeps or shuts down drops the WhatsApp connection.'
    printf '\n'
    info 'Found here:'
    printf '%s' "$found" | while IFS= read -r line; do
        [ -n "$line" ] && warn "      $line"
    done
    printf '\n'
    warn 'Nothing has been deleted.'
    info 'The store folder holds your linked WhatsApp session, and deleting it'
    info 'means pairing your phone again. Set WhatsApp up on Zo first, confirm'
    info 'it works, and only then remove the copy here.'
    return 1
}

app_installed() {
    # $1 = application name without .app
    [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]
}

hermes_installed() { app_installed "$HERMES_APP_NAME"; }

claude_mcp_configured() {
    [ -f "$CLAUDE_CONFIG" ] || return 1
    node_bin >/dev/null || return 1
    "$(node_bin)" -e '
        const fs = require("fs");
        try {
            const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8") || "{}");
            process.exit((data.mcpServers || {})[process.argv[2]] ? 0 : 1);
        } catch { process.exit(1); }
    ' "$CLAUDE_CONFIG" "$ZO_MCP_ENTRY" 2>/dev/null
}

codex_mcp_configured() {
    [ -f "$CODEX_CONFIG" ] || return 1
    grep -qE "^[[:space:]]*\[mcp_servers\.${ZO_MCP_ENTRY}\]" "$CODEX_CONFIG"
}

# ---------------------------------------------------------------------------
# The status screen
# ---------------------------------------------------------------------------
# Each check is one line: key|title|status|detail|note
# status is one of: ok, missing, needs-you

CHECKS=()

add_hermes_check() {
    # The last row, and the only one that asks nothing of Zo.
    #
    # It is a function rather than four lines at the bottom of collect_checks
    # because collect_checks has two ends, not one: it returns early when Zo
    # cannot be reached. Written inline at the bottom, this row would have been
    # missing from every machine without a Zo key - which is most of them, at
    # the moment the owner first opens the setup. That exact mistake is why the
    # Zo plan rows sat red for a fortnight.
    feature_on "$FEATURE_HERMES" || return 0
    if hermes_installed; then
        CHECKS+=("hermes-app|Hermes One|ok|installed|")
    else
        CHECKS+=("hermes-app|Hermes One|missing|not installed|a second AI assistant, on this Mac")
    fi
}

# Says what is being looked at right now. Checking takes several seconds -
# Homebrew is slow, and asking Zo is a network round trip - and a screen that
# says "Checking..." then sits still looks like it has hung. Wiped by the
# status screen afterwards.
checking() { printf '        %s·%s %s%s%s\n' "$C_PURPLE" "$C_RESET" "$C_GREY" "$1" "$C_RESET"; }

collect_checks() {
    CHECKS=()
    load_homebrew_env

    local version

    checking 'Node.js'
    version="$(command_version node --version)"
    if [ -z "$version" ]; then
        CHECKS+=("node|Node.js|missing|not installed|runs the Zo connection for both AI apps")
    elif node_too_old; then
        # Present and useless is worse than absent. Everything this setup does
        # with Zo runs through zo-verify.js, which calls fetch - built in from
        # Node 18 and missing before it. On an older Node the row said "ok,
        # version 16" in green, every Zo row then read "could not reach Zo to
        # check", and every Zo step failed in turn with no reason given.
        CHECKS+=("node|Node.js|needs-you|version $version is too old|Zo needs $NODE_MIN_MAJOR or newer")
    else
        CHECKS+=("node|Node.js|ok|version $version|")
    fi

    checking 'Git'
    version="$(command_version git --version)"
    if [ -n "$version" ]; then
        CHECKS+=("git|Git|ok|version $version|")
    else
        CHECKS+=("git|Git|missing|not installed|lets the AI apps read and write code projects")
    fi

    checking 'Python'
    version="$(command_version python3 --version)"
    if [ -n "$version" ]; then
        CHECKS+=("python|Python|ok|version $version|")
    else
        CHECKS+=("python|Python|missing|not installed|runs data and automation tools")
    fi

    # One of the two is enough.
    #
    # A customer who pays for ChatGPT and not Claude is a finished setup, not a
    # half-finished one - and treated as half-finished, their Claude rows stay
    # red for ever, the checklist never says done, and what they report is "a
    # problem with the Zo connection". So whichever they already have decides
    # it: the other is shown, and never chased.
    #
    # Only when neither is here does the setup offer both, because then there
    # is nothing to prefer.
    HAS_CLAUDE='no'; HAS_CHATGPT='no'; HAS_EITHER_APP='no'
    app_installed "Claude" && HAS_CLAUDE='yes'
    app_installed "ChatGPT" && HAS_CHATGPT='yes'
    if [ "$HAS_CLAUDE" = 'yes' ] || [ "$HAS_CHATGPT" = 'yes' ]; then
        HAS_EITHER_APP='yes'
    fi

    # What the owner said wins over what happens to be lying on the machine.
    #
    # Guessing from what is installed is only ever a fallback: somebody who
    # pays for ChatGPT and has an old Claude they never opened would otherwise
    # be marched through setting Claude up. Asked once, remembered, and the
    # unwanted one is never mentioned again.
    local chosen because
    chosen="$(profile_get aiApps)"
    case "$chosen" in
        claude)  WANT_CLAUDE='yes'; WANT_CHATGPT='no' ;;
        chatgpt) WANT_CLAUDE='no';  WANT_CHATGPT='yes' ;;
        both)    WANT_CLAUDE='yes'; WANT_CHATGPT='yes' ;;
        *)
            if [ "$HAS_EITHER_APP" = 'yes' ]; then
                WANT_CLAUDE="$HAS_CLAUDE"; WANT_CHATGPT="$HAS_CHATGPT"
            else
                WANT_CLAUDE='yes'; WANT_CHATGPT='yes'
            fi ;;
    esac
    # "you chose" when they said so, "you have" when it was worked out. Being
    # told a step is unnecessary "because you have ChatGPT" reads as a mistake
    # to somebody who has just said they want Claude.
    if [ -n "$chosen" ]; then because='you chose'; else because='you have'; fi

    checking 'Claude Desktop'
    if [ "$WANT_CLAUDE" = 'no' ]; then
        CHECKS+=("claude-app|Claude Desktop|skipped|not needed - $because ChatGPT|")
    elif [ "$HAS_CLAUDE" = 'yes' ]; then
        CHECKS+=("claude-app|Claude Desktop|ok|installed|")
    else
        CHECKS+=("claude-app|Claude Desktop|missing|not installed|")
    fi

    checking 'ChatGPT Desktop'
    if [ "$WANT_CHATGPT" = 'no' ]; then
        CHECKS+=("chatgpt-app|ChatGPT Desktop|skipped|not needed - $because Claude|")
    elif [ "$HAS_CHATGPT" = 'yes' ]; then
        CHECKS+=("chatgpt-app|ChatGPT Desktop|ok|installed|")
    else
        CHECKS+=("chatgpt-app|ChatGPT Desktop|missing|not installed|")
    fi

    if token_looks_valid "$(get_zo_token)"; then
        CHECKS+=("zo-token|Zo account key|ok|saved in your keychain|")
    else
        CHECKS+=("zo-token|Zo account key|needs-you|not entered yet|everything below needs this first")
    fi

    # Connecting Zo to an app that is not installed is work nobody can finish.
    # These follow the same rule as the apps above them.
    checking 'the Zo connection inside each app'
    if claude_mcp_configured; then
        CHECKS+=("claude-mcp|Zo inside Claude Desktop|ok|connected|")
    elif [ "$WANT_CLAUDE" = 'no' ]; then
        CHECKS+=("claude-mcp|Zo inside Claude Desktop|skipped|not needed - $because ChatGPT|")
    else
        CHECKS+=("claude-mcp|Zo inside Claude Desktop|missing|not connected|")
    fi

    if codex_mcp_configured; then
        CHECKS+=("chatgpt-mcp|Zo inside ChatGPT|ok|connected|")
    elif [ "$WANT_CHATGPT" = 'no' ]; then
        CHECKS+=("chatgpt-mcp|Zo inside ChatGPT|skipped|not needed - $because Claude|")
    else
        CHECKS+=("chatgpt-mcp|Zo inside ChatGPT|missing|not connected|")
    fi

    # Only shown on a machine that has one. On a clean Mac this is not a task
    # the owner should have to read past.
    #
    # It also goes with the assistant. The whole row says "put WhatsApp on Zo
    # instead of here" - advice that is simply wrong on a build that does not
    # put WhatsApp on Zo, and it would be the only mention of WhatsApp left.
    if feature_on "$FEATURE_AI_ASSISTANT" && [ -n "$(find_local_whatsapp)" ]; then
        CHECKS+=("local-whatsapp|WhatsApp on this Mac|needs-you|should be on Zo instead|set it up on Zo first, then remove the copy here")
    fi

    # These two live on Zo, so Zo is asked directly. One call answers both.
    checking 'your Zo (this one needs the internet)'
    zo_verify "$(get_zo_token)"

    if [ -z "$ZO_ANSWER" ]; then
        # Everything living on Zo is unknowable from here without a key. The
        # rows still appear so the owner can see what is coming, and each says
        # why it cannot be checked rather than guessing at an answer.
        local why='could not reach Zo to check'
        case "$(get_zo_token)" in zo_sk_*) ;; *) why='needs your Zo key first' ;; esac
        # Same order, and the same names, as when a key is present. A list that
        # rearranges itself once the key is pasted looks like a different
        # program.
        CHECKS+=("zo-claude-code|Claude plan on Zo|skipped|$why|")
        CHECKS+=("zo-codex|ChatGPT plan on Zo|skipped|$why|")
        if feature_on "$FEATURE_ZO_SKILLS"; then
            CHECKS+=("zo-skills|Basic skills for your Zo|needs-you|$why|")
        fi
        if feature_on "$FEATURE_SECOND_BRAIN"; then
            CHECKS+=("zo-brain|Your company second brain|needs-you|$why|")
        fi
        if feature_on "$FEATURE_GOOGLE"; then
            CHECKS+=("zo-google|Basic integrations for your Zo|needs-you|$why|")
        fi
        if feature_on "$FEATURE_AI_ASSISTANT"; then
            CHECKS+=("talk-to-zo|Your AI Personal Assistant|needs-you|$why|")
        fi
        if feature_on "$FEATURE_AI_EMPLOYEES"; then
            CHECKS+=("zo-employees|Hire AI employees|needs-you|$why|")
        fi
        # Nothing above this line could be answered without Zo. This one can:
        # it is an app on this Mac, so it is checked and offered exactly as it
        # would be on a machine whose key works.
        add_hermes_check
        return 0
    fi

    # Remember the workspace address as soon as Zo names it, so later links go
    # to the owner's own pages.
    save_workspace_url "$(zo_field 'data.workspaceUrl || ""')"

    # Signing Zo in to an existing plan means it uses one the owner already
    # pays for, instead of billing per use.
    local claude_state codex_state
    claude_state="$(zo_field 'data.aiProviders?.claude?.loggedIn === true')"
    codex_state="$(zo_field 'data.aiProviders?.codex?.loggedIn === true')"
    #
    # Optional in the note and compulsory in the arithmetic, until now. These
    # two rows are the only ones an owner cannot clear by doing anything on
    # this computer - they need a paid plan - so counting them as outstanding
    # meant anyone paying for neither, or for only one, never saw the setup
    # finish. Skipped, they are still on the list saying what they would save.
    if [ "$claude_state" = "true" ]; then
        CHECKS+=("zo-claude-code|Claude plan on Zo|ok|signed in|")
    else
        CHECKS+=("zo-claude-code|Claude plan on Zo|skipped|not signed in|optional, but saves paying per use")
    fi
    if [ "$codex_state" = "true" ]; then
        CHECKS+=("zo-codex|ChatGPT plan on Zo|ok|signed in|")
    else
        CHECKS+=("zo-codex|ChatGPT plan on Zo|skipped|not signed in|optional, but saves paying per use")
    fi

    # Order from here on follows how a business actually gets going: teach it
    # skills, give it access, decide where you talk to it, then hire. Anything
    # that needs the one before it comes after it.

    # Read off Zo's own folders, never from a note of what the owner said. An
    # owner who removed a skill last week has to show as not having it.
    local skills_known skills_missing skills_have skills_wanted
    if feature_on "$FEATURE_ZO_SKILLS"; then
        skills_wanted="${#ZO_SKILL_KEYS[@]}"
        skills_known="$(zo_field 'data.skills ? "yes" : "no"')"
        skills_missing="$(zo_field 'data.skills ? data.skills.missing.length : 0')"
        skills_have="$(zo_field 'data.skills ? data.skills.installed.length : 0')"
        if [ "$skills_known" != "yes" ]; then
            CHECKS+=("zo-skills|Basic skills for your Zo|needs-you|could not tell|briefings, PDFs, reading photos, and more")
        elif [ "$skills_missing" = "0" ]; then
            CHECKS+=("zo-skills|Basic skills for your Zo|ok|all $skills_wanted installed|")
        else
            # Counted, not ticked. "2 of 9" tells an owner something a single
            # cross does not, and it is the same reason Google is reported that
            # way.
            CHECKS+=("zo-skills|Basic skills for your Zo|needs-you|$skills_have of $skills_wanted installed|briefings, PDFs, reading photos, and more")
        fi
    fi

    # Straight after skills, because it is the same kind of thing: something the
    # Zo gains rather than something the owner has to do. Read from the same
    # reply, so checking costs no extra round trip and - the part that matters -
    # asking whether the company second brain exists never creates it.
    #
    # Zo is asked about it either way - the answer rides along in the same reply
    # as everything else, so a switched-off second brain costs nothing to stay
    # informed about. Only the row is withheld.
    local brain_folders brain_notes
    if feature_on "$FEATURE_SECOND_BRAIN"; then
        brain_folders="$(zo_field 'data.secondBrain ? data.secondBrain.folders : -1')"
        brain_notes="$(zo_field 'data.secondBrain ? data.secondBrain.notes : 0')"
        if [ "${brain_folders:--1}" -gt 0 ] 2>/dev/null; then
            if [ "${brain_notes:-0}" -gt 0 ] 2>/dev/null; then
                CHECKS+=("zo-brain|Your company second brain|ok|$brain_notes notes kept|")
            else
                CHECKS+=("zo-brain|Your company second brain|ok|ready and empty|")
            fi
        else
            CHECKS+=("zo-brain|Your company second brain|needs-you|not set up yet|somewhere to keep what your Zo learns")
        fi
    fi

    # Google is several apps, each authorised separately. They are listed one by
    # one under a single row: a lone tick would hide that Calendar was never
    # authorised, and four top-level rows would crowd the screen for what is
    # really one decision. Children ride in field 6 as "Name:ok" pairs.
    local total connected children
    total="$(zo_field 'Object.keys(data.integrations).length')"
    connected="$(zo_field 'Object.values(data.integrations).filter(v => v.connected === true).length')"
    children="$(zo_field '
        Object.entries(data.integrations)
            .map(([k, v]) => {
                const name = ({gmail:"Gmail", google_calendar:"Calendar",
                               google_drive:"Drive", google_sheets:"Sheets"})[k] || k;
                return name + ":" + (v.connected === true ? "ok" : "no");
            }).join(",")')"

    if feature_on "$FEATURE_GOOGLE"; then
        if [ -n "$total" ] && [ "$connected" = "$total" ]; then
            CHECKS+=("zo-google|Basic integrations for your Zo|ok|$connected of $total connected||$children")
        else
            CHECKS+=("zo-google|Basic integrations for your Zo|needs-you|$connected of $total connected||$children")
        fi
    fi

    # The row that decides whether any of the rest gets used. A fully set up Mac
    # with no answer here is a customer who never opens it again. It comes after
    # skills and access on purpose: the first thing they do is talk to it, and
    # by then it should already be able to do something.
    #
    # One row, not two. "WhatsApp on Zo" sat separately and said the same thing
    # twice: for anyone on WhatsApp - nearly everyone - their assistant IS the
    # WhatsApp number, so a linked number and a set-up assistant were the same
    # fact reported in two places, able to disagree with each other.
    #
    # Switched off, the owner reaches their Zo through Claude Desktop and
    # ChatGPT instead. Those are connected earlier on this same list and are not
    # switchable, so the setup still finishes with somewhere to type - which is
    # the one thing that must stay true whatever else is turned off.
    #
    # Wrapped rather than returned from: the employees row is built below this
    # one, and returning here would take that with it, so switching the
    # assistant off would silently switch employees off too.
    local talk_channel channel_label wa_connected wa_detail wa_answering
    if feature_on "$FEATURE_AI_ASSISTANT"; then
    talk_channel="$(profile_get talkChannel)"
    case "$talk_channel" in
        whatsapp)      channel_label='WhatsApp' ;;
        whatsapp-self) channel_label='WhatsApp, your own chat' ;;
        telegram)      channel_label='Telegram' ;;
        web)           channel_label='on the web' ;;
        *)             channel_label='' ;;
    esac

    wa_connected="$(zo_field 'data.whatsapp.connected')"
    wa_detail="$(zo_field 'data.whatsapp.detail || "not linked yet"')"
    wa_answering="$(zo_field 'data.whatsapp.answering === true')"

    if [ -z "$channel_label" ]; then
        CHECKS+=("talk-to-zo|Your AI Personal Assistant|needs-you|not set up yet|without this there is nowhere to type")
    elif [ "$talk_channel" != "whatsapp" ] && [ "$talk_channel" != "whatsapp-self" ]; then
        # Telegram and the web are finished the moment they are chosen; there is
        # nothing on Zo to link or switch on.
        CHECKS+=("talk-to-zo|Your AI Personal Assistant|ok|$channel_label|")
    elif [ "$wa_connected" = "true" ] && [ "$wa_answering" = "true" ]; then
        CHECKS+=("talk-to-zo|Your AI Personal Assistant|ok|$channel_label, answering|")
    elif [ "$wa_connected" = "true" ]; then
        # Linked is not finished. Every install before the responder existed sat
        # exactly here: connected, collecting messages, replying to nobody, and
        # reported as done.
        CHECKS+=("talk-to-zo|Your AI Personal Assistant|needs-you|linked, but it does not reply yet|one more step and it answers")
    elif [ "$wa_connected" = "null" ]; then
        CHECKS+=("talk-to-zo|Your AI Personal Assistant|needs-you|could not tell|")
    else
        CHECKS+=("talk-to-zo|Your AI Personal Assistant|needs-you|$wa_detail|without this there is nowhere to type")
    fi
    fi

    # Last, because an employee is only worth hiring once the Zo they work for
    # can actually do something. Read from Zo, so somebody removed on the
    # website disappears from here too.
    #
    # Switched off, the row goes and the employees do not. Anybody hired on a
    # build that offered it, or made on the Zo website, keeps working exactly as
    # before - this setup simply stops reporting on them, which is why nothing
    # here removes anything.
    # Wrapped rather than returned from. This used to end the function, and
    # anything added below it would have been silently dropped on every build
    # with AI employees switched off - which is every build that ships.
    if feature_on "$FEATURE_AI_EMPLOYEES"; then

    local employees_known employees_count
    employees_known="$(zo_field 'data.employees ? "yes" : "no"')"
    employees_count="$(zo_field 'data.employees ? data.employees.length : 0')"
    if [ "$employees_known" != "yes" ]; then
        CHECKS+=("zo-employees|Hire AI employees|needs-you|could not tell|sales, admin, accounts, and more")
    elif [ "$employees_count" != "0" ]; then
        CHECKS+=("zo-employees|Hire AI employees|ok|$employees_count hired|")
    else
        CHECKS+=("zo-employees|Hire AI employees|needs-you|nobody hired yet|sales, admin, accounts, and more")
    fi

    fi

    # Genuinely last, and deliberately so. Everything before it either is the
    # way the owner reaches their Zo or is something their Zo gains; this is a
    # separate app that stands on its own, so it goes after the setup's own
    # promise has been kept rather than in front of it.
    add_hermes_check
}

clear_screen() { [ -t 1 ] && clear 2>/dev/null; return 0; }

show_banner() {
    printf '\n    %s╭────────────────────────────────────────────────╮%s\n' "$C_PURPLE" "$C_RESET"
    printf '    %s│%s         %sV I M I G O   A I   S E T U P%s          %s│%s\n' \
        "$C_PURPLE" "$C_RESET" "$C_TEAL" "$C_RESET" "$C_PURPLE" "$C_RESET"
    printf '    %s╰────────────────────────────────────────────────╯%s\n\n' "$C_PURPLE" "$C_RESET"
}

show_logo() {
    # The Vimigo mark, four cascading bands, at the size the owner supplied.
    # The full artwork is 100 columns by 35 rows, which fills an 80-column
    # window entirely and leaves no room for the setup itself.
    #
    # The art is stored in plain ASCII and the circle is drawn as a bullet at
    # render time. Storing the bullet directly breaks the slicing below:
    # ${row:index:1} counts bytes rather than characters unless the locale says
    # otherwise, and a bullet is three bytes in UTF-8, so the row comes out
    # shredded on any machine that is not already in a UTF-8 locale.
    local rows=(
        '                         --         ==  '
        '              ...       -----     ======'
        'oooooo      .......   --------   ======='
        'ooooooo   ........   -------   =======  '
        'ooooooo  .......   -------   ========   '
        ' oooo  ........  --------  ========     '
        '     ........   -------   =======       '
        '     ......   -------   ========        '
        '       ...  --------  ========          '
        '           -------   =======            '
        '           -----   ========             '
        '             --   =======               '
        '                =======                 '
        '                 =====                  '
        '                   =                    '
    )

    printf '\n'
    local row index character colour
    for row in "${rows[@]}"; do
        printf '    '
        for (( index = 0; index < ${#row}; index++ )); do
            character="${row:index:1}"
            # The circle prints as a bullet even though it is stored as 'o':
            # a letter reads as text sitting beside the mark rather than as
            # part of it, and the point of the circle is that it is a shape.
            case "$character" in
                o) printf '%s•%s' "$C_TEAL" "$C_RESET"; continue ;;
                .) colour="$C_YELLOW" ;;
                -) colour="$C_CORAL" ;;
                =) colour="$C_PURPLE" ;;
                *) printf ' '; continue ;;
            esac
            printf '%s%s%s' "$colour" "$character" "$C_RESET"
        done
        printf '\n'
    done
    printf '\n              %sV I M I G O   A I   S E T U P%s\n\n' "$C_WHITE" "$C_RESET"
}

show_progress_bar() {
    # $1 = done, $2 = total
    local done="$1" total="$2" width=26 filled i bar='' colour
    [ "$total" -gt 0 ] || return 0
    filled=$(( (done * width + total / 2) / total ))
    for ((i = 0; i < width; i++)); do
        # Braced, and that is not style.
        #
        # "$bar█" put the block character straight after the name, and the
        # block's first byte is 0xE2. macOS ships bash 3.2, and in a non-UTF-8
        # locale its parser accepts a high byte as part of an identifier - so
        # it looked up a variable called bar-block-character, found nothing,
        # and under set -u killed the whole setup with "bar?: unbound
        # variable" the moment the first progress bar was drawn. On a
        # customer's MacBook, at the end of the very first screen.
        if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
    done
    if [ "$done" -eq "$total" ]; then colour="$C_GREEN"; else colour="$C_TEAL"; fi
    printf '     %s%s%s  %s%d of %d done%s\n' "$colour" "$bar" "$C_RESET" "$C_GREY" "$done" "$total" "$C_RESET"
}

show_step_header() {
    # $1 = number, $2 = total, $3 = title
    printf '\n    %s── Step %d of %d ───────────────────%s\n' "$C_PURPLE" "$1" "$2" "$C_RESET"
    printf '       %s%s%s\n\n' "$C_TEAL" "$3" "$C_RESET"
}

show_all_done() {
    clear_screen
    printf '\n'
    printf '    %s╭────────────────────────────────────────────────╮%s\n' "$C_GREEN" "$C_RESET"
    printf '    %s│                                                │%s\n' "$C_GREEN" "$C_RESET"
    printf '    %s│              ✓   A L L   D O N E                │%s\n' "$C_GREEN" "$C_RESET"
    printf '    %s│                                                │%s\n' "$C_GREEN" "$C_RESET"
    printf '    %s╰────────────────────────────────────────────────╯%s\n\n' "$C_GREEN" "$C_RESET"
    info '  This Mac is ready.'
    printf '\n'
    warn '  One last thing: quit Claude Desktop and ChatGPT completely,'
    warn '  then open them again. They only read their settings on start.'
    printf '\n'

    # Finishing the checklist is not the end of the job. The next real step is
    # building the team, and a screen that says "all done" and stops is a screen
    # the owner closes without ever finding it.
    #
    # The same options as the unfinished screen, from one place. When this
    # screen kept its own shorter copy, finishing the setup quietly took away
    # "see your AI employees" and "set up your assistant again" - so the only
    # route back into a finished setup was Start over, which deletes things.
    show_main_options finished
}

show_checks() {
    clear_screen
    show_logo

    local done=0 total=0
    for entry in "${CHECKS[@]}"; do
        total=$((total + 1))
        local title status detail mark colour
        title="$(printf '%s' "$entry" | cut -d'|' -f2)"
        status="$(printf '%s' "$entry" | cut -d'|' -f3)"
        detail="$(printf '%s' "$entry" | cut -d'|' -f4)"

        if [ "$status" = "ok" ]; then
            mark='✓'; colour="$C_GREEN"; done=$((done + 1))
        elif [ "$status" = "skipped" ]; then
            # Asked, answered, and not asked again. Counted as finished
            # business so a decline does not hold the whole list open.
            mark='·'; colour="$C_GREY"; done=$((done + 1))
        else
            mark='●'; colour="$C_YELLOW"
        fi

        # Padded to 32, and a space guaranteed after it. "Basic integrations
        # for your Zo" is 30 characters, and at 28 the detail was welded onto
        # the end of it: "...for your Zo4 of 4 connected".
        printf '      %s%s%s  %-32s %s%s%s\n' \
            "$colour" "$mark" "$C_RESET" "$title" "$C_GREY" "$detail" "$C_RESET"

        # Sub-items, for a step that is really several separate permissions.
        local children child child_name child_state child_mark child_colour
        children="$(printf '%s' "$entry" | cut -d'|' -f6)"
        if [ -n "$children" ]; then
            local IFS_SAVE="$IFS"; IFS=','
            for child in $children; do
                IFS="$IFS_SAVE"
                child_name="${child%%:*}"; child_state="${child##*:}"
                if [ "$child_state" = "ok" ]; then
                    child_mark='✓'; child_colour="$C_GREEN"
                else
                    child_mark='·'; child_colour="$C_GREY"
                fi
                printf '           %s%s%s  %s%s%s\n' \
                    "$child_colour" "$child_mark" "$C_RESET" "$C_GREY" "$child_name" "$C_RESET"
                IFS=','
            done
            IFS="$IFS_SAVE"
        fi
    done

    printf '\n'
    show_progress_bar "$done" "$total"
    printf '\n'
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

install_node_directly() {
    # Node from Apple's own installer format, not through Homebrew.
    #
    # Homebrew is not on a Mac out of the box, and installing it drags in
    # Xcode's command line tools: one to two gigabytes, a window the owner has
    # to click through, and a long wait on a phone hotspot. Node is about
    # thirty megabytes and everything on the Zo side needs it, so it must not
    # sit behind that.
    #
    # Homebrew stays for Git and Python, which are useful rather than
    # necessary, and which the owner can decline without losing anything here.
    title 'Installing Node.js'
    info 'This is what lets your computer talk to your Zo.'
    printf '\n'

    # Asked of nodejs.org rather than pinned, so this does not go stale, and
    # with grep alone because a Mac without the command line tools has no
    # working python3 to parse JSON with.
    local version
    version="$(curl -fsSL --max-time 30 https://nodejs.org/dist/index.json 2>/dev/null |
        tr '}' '\n' | grep '"lts":"[A-Za-z]' | head -1 |
        grep -oE '"version":"v[0-9.]+' | cut -d'"' -f4)"

    if [ -z "$version" ]; then
        warn 'Could not reach nodejs.org just now.'
        return 1
    fi

    local pkg="/tmp/vimigo-node-$version.pkg"
    # info, not say. This script never defined a say function - every other
    # zo-*.sh does - so on a Mac this called /usr/bin/say, and the laptop read
    # the line out loud through the speakers instead of printing it. A clean
    # Mac always takes this path, so every first install announced itself.
    info "Downloading Node.js $version..."
    if ! curl -fsSL --max-time 300 -o "$pkg" \
        "https://nodejs.org/dist/$version/node-$version.pkg"; then
        rm -f "$pkg"
        warn 'The download did not finish.'
        return 1
    fi

    printf '\n'
    info 'Your Mac will now ask for your password. That is normal - it is'
    info 'how a Mac checks it is really you before installing anything.'
    printf '\n'
    sudo installer -pkg "$pkg" -target / >/dev/null 2>&1
    rm -f "$pkg"

    # Fresh install lands in /usr/local/bin, which a running shell may not have
    # picked up yet.
    export PATH="/usr/local/bin:$PATH"
    if [ -n "$(command_version node --version)" ]; then
        good "Node.js $(command_version node --version) installed."
        return 0
    fi
    warn 'Node.js did not finish installing.'
    return 1
}

install_python_directly() {
    # Python the same way as Node, and for the same reason: python.org ships an
    # ordinary Apple installer, so it does not have to wait behind Homebrew and
    # Xcode's command line tools.
    title 'Installing Python'
    info 'This is what runs data and automation jobs for you.'
    printf '\n'

    # The current release, read off python.org's own downloads page rather than
    # pinned, with grep alone - there is no python here yet to parse anything
    # with, which is rather the point.
    local version
    version="$(curl -fsSL --max-time 30 https://www.python.org/downloads/macos/ 2>/dev/null |
        grep -oE 'python-3\.[0-9]+\.[0-9]+-macos11\.pkg' | head -1 |
        sed -E 's/^python-//; s/-macos11\.pkg$//')"
    [ -n "$version" ] || {
        warn 'Could not reach python.org just now.'
        return 1
    }

    local pkg="/tmp/vimigo-python-$version.pkg"
    info "Downloading Python $version..."
    curl -fsSL --max-time 300 -o "$pkg" \
        "https://www.python.org/ftp/python/$version/python-$version-macos11.pkg" || {
        rm -f "$pkg"
        warn 'The download did not finish.'
        return 1
    }

    printf '\n'
    info 'Your Mac will ask for your password. That is normal.'
    printf '\n'
    sudo installer -pkg "$pkg" -target / >/dev/null 2>&1
    rm -f "$pkg"

    export PATH="/usr/local/bin:$PATH"
    if [ -n "$(command_version python3 --version)" ]; then
        good "Python $(command_version python3 --version) installed."
        return 0
    fi
    warn 'Python did not finish installing.'
    return 1
}

install_git_directly() {
    # Git comes with Apple's command line tools, and there is no maintained
    # standalone installer for macOS worth pointing an owner at. So this asks
    # macOS itself, which shows its own window and does the work - the same
    # download Homebrew would have triggered, without also installing Homebrew.
    title 'Installing Git'

    if xcode-select -p >/dev/null 2>&1 && [ -n "$(command_version git --version)" ]; then
        good "Git $(command_version git --version) is already installed."
        return 0
    fi

    info 'Git comes as part of a free Apple download called the command line'
    info 'tools. Your Mac will show its own window to install it.'
    printf '\n'
    warn 'It is around a gigabyte, so it is worth being on wifi.'
    printf '\n'
    ask_yes_no 'Ask your Mac to install it now?' || {
        warn 'Skipped for now. You can come back to this any time.'
        return 1
    }

    xcode-select --install >/dev/null 2>&1

    printf '\n'
    info 'A window should have appeared. Click Install and agree to the'
    info 'licence, then come back here.'
    printf '\n'
    info 'Waiting for it to finish...'

    # Watched rather than guessed at, and with a way out: this is a GUI window
    # on somebody else's timetable, and it can be declined entirely.
    local waited=0
    while [ "$waited" -lt 1800 ]; do
        sleep 10
        waited=$((waited + 10))
        if [ -n "$(command_version git --version)" ]; then
            printf '\r%*s\r' 60 ''
            good "Git $(command_version git --version) installed."
            return 0
        fi
        printf '\r      %s  still installing... %s   ' "$C_GREY" "$(printf '%dm' $((waited / 60)))"
    done

    printf '\r%*s\r' 60 ''
    warn 'That is taking a while. It may still be going in the background.'
    info 'Run this setup again later and it will pick Git up.'
    return 1
}

install_homebrew() {
    title 'Installing Homebrew'
    if have_homebrew; then
        good 'Homebrew is already installed. Nothing to do.'
        return 0
    fi

    info 'Homebrew is the tool macOS uses to install developer software.'
    printf '\n'
    warn 'This one is big: a gigabyte or more, and it will ask for your Mac'
    warn 'password. On a phone connection it can take a long while.'
    printf '\n'
    # Said plainly, because it is true and because somebody who thinks this is
    # compulsory will sit through a gigabyte on a hotspot for nothing.
    # Honest about the cost and about the order, without calling these
    # optional. They are needed - just not before the assistant works, and
    # somebody on a phone hotspot should be told they can do this later rather
    # than sit through a gigabyte now.
    info 'Your assistant already works without this. The two tools it brings'
    info 'are for the bigger jobs later - code and spreadsheets - so you can'
    info 'do this now, or come back to it on better wifi.'
    printf '\n'
    if ! ask_yes_no 'Install Homebrew now?'; then
        warn 'Skipped for now. Everything else carries on, and you can come'
        warn 'back to this whenever you like.'
        return 1
    fi

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_homebrew_env

    if have_homebrew; then
        good 'Homebrew is installed.'
        return 0
    fi
    bad 'Homebrew did not finish installing.'
    return 1
}

install_brew_formula() {
    # $1 = formula, $2 = friendly title, $3 = command to verify, rest = version args
    local formula="$1" friendly="$2" verify="$3"; shift 3

    title "Installing $friendly"

    # Detect first. Never reinstall something that is already working.
    local existing; existing="$(command_version "$verify" "$@")"
    if [ -n "$existing" ]; then
        good "$friendly $existing is already installed. Nothing to do."
        return 0
    fi

    if ! have_homebrew; then
        install_homebrew || return 1
    fi

    # Noted before the attempt, so a later "start over" knows this one was not
    # already on the Mac. Removing something the owner installed themselves is
    # not this setup's to do.
    add_installed_by_us "$formula"

    info "Installing $friendly. This can take a few minutes."
    brew install "$formula" 2>&1 | sed 's/^/    /'

    # Homebrew's exit code proves nothing. Re-detect.
    load_homebrew_env
    local version; version="$(command_version "$verify" "$@")"
    if [ -n "$version" ]; then
        good "$friendly $version is installed."
        return 0
    fi

    warn "$friendly did not answer after installing."
    warn 'Close this window, open it again, and re-run this setup.'
    return 1
}

open_app_to_sign_in() {
    # $1 = the .app name. Opens an app so the owner can do the one thing nobody
    # else can: signing in is a password and often a second factor.
    local appname="$1"

    title "Signing in to $appname"
    info "$appname is installed, but nobody has signed in on this Mac yet."
    info 'Until you do, it cannot reach your Zo.'
    printf '\n'
    numbered 1 "Sign in with your" "$appname account"
    numbered 2 'Leave it open and come back here' ''
    printf '\n'

    # Opened, not offered. "Open Claude now? Y/N" is a question with one
    # sensible answer, asked of somebody who just asked for Claude to be set
    # up. Opening an app changes nothing and closing it undoes it.
    if open -a "$appname" 2>/dev/null; then
        good "$appname is opening now."
    else
        info "Could not open it from here. Please open $appname yourself."
    fi
    return 0
}

install_desktop_app() {
    # $1 = cask, $2 = .app name, $3 = friendly title, $4 = download page
    local cask="$1" appname="$2" friendly="$3" download="$4"

    title "Installing $friendly"
    if app_installed "$appname"; then
        good "$friendly is already installed. Nothing to do."
        return 0
    fi

    if ! have_homebrew; then
        install_homebrew || return 1
    fi

    brew install --cask "$cask" 2>&1 | sed 's/^/    /'

    if app_installed "$appname"; then
        good "$friendly is installed."
        return 0
    fi

    warn "$friendly did not appear."
    if ask_yes_no "Open the $friendly download page in your browser instead?"; then
        open "$download"
        info 'Install it from that page, then come back and press R to re-check.'
    fi
    return 1
}

hermes_mac_asset() {
    # Prints "<filename> <checksum>" for this Mac's processor, read from the
    # project's own update feed. Prints nothing at all if it cannot be read.
    local want
    case "$(uname -m)" in
        arm64) want='-arm64-mac.zip' ;;
        *)     want='-x64-mac.zip' ;;
    esac

    # The feed lists both processors, each followed by its checksum. Taking the
    # first checksum after the filename we want is what pairs them correctly;
    # taking the last line of the file would pick up the release-level checksum
    # instead, which belongs to whichever build happens to be listed first.
    curl -fsSL --max-time 30 "$HERMES_MAC_FEED" 2>/dev/null | awk -v want="$want" '
        $1 == "-" && $2 == "url:" { file = $3 }
        $1 == "sha512:" && file != "" && index(file, want) > 0 { print file " " $2; exit }
    '
}

install_hermes_one() {
    title "Installing $HERMES_APP_NAME"

    if hermes_installed; then
        good "$HERMES_APP_NAME is already installed. Nothing to do."
        return 0
    fi

    info 'This one is a big download - about 190 megabytes - so give it a few'
    info 'minutes. You will see it counting up.'
    printf '\n'

    local asset file want_sum url archtag
    file=''; want_sum=''; url=''
    asset="$(hermes_mac_asset)"
    if [ -n "$asset" ]; then
        file="$(printf '%s' "$asset" | cut -d' ' -f1)"
        want_sum="$(printf '%s' "$asset" | cut -d' ' -f2)"
        url="$HERMES_RELEASES/latest/download/$file"
    else
        archtag='x64'
        if [ "$(uname -m)" = 'arm64' ]; then archtag='arm64'; fi
        file="hermes-desktop-$HERMES_PINNED_VERSION-$archtag-mac.zip"
        url="$HERMES_RELEASES/download/v$HERMES_PINNED_VERSION/$file"
        info 'Could not check the current version, so installing a known good one.'
    fi

    local tmp
    tmp="$(mktemp -d /tmp/vimigo-hermes.XXXXXX 2>/dev/null)" || tmp=''
    if [ -z "$tmp" ]; then
        warn 'Could not make a temporary folder to download into.'
        return 1
    fi

    # A visible bar, unlike everything else this script downloads. Two hundred
    # megabytes of silence on a hotel connection is indistinguishable from a
    # hung setup, and somebody who thinks it has hung closes the window.
    if ! curl -fL --progress-bar --max-time 1800 -o "$tmp/$file" "$url"; then
        rm -rf "$tmp"
        warn 'The download did not finish.'
        if ask_yes_no "Open the $HERMES_APP_NAME download page in your browser instead?"; then
            open "$HERMES_DOWNLOAD_PAGE"
            info 'Install it from that page, then come back and press R to re-check.'
        fi
        return 1
    fi

    # Checked against the figure published beside the download. A file that
    # arrived short unpacks into an app that opens once and crashes, and the
    # owner has no way to tell that from a bad app - so it is caught here,
    # where the answer is simply "run it again".
    if [ -n "$want_sum" ]; then
        local got_sum
        got_sum="$(shasum -a 512 "$tmp/$file" 2>/dev/null | cut -d' ' -f1 |
            xxd -r -p 2>/dev/null | base64 2>/dev/null | tr -d '\n')"
        # Only when it could actually be worked out. A Mac missing xxd should
        # not be a Mac that cannot install anything.
        if [ -n "$got_sum" ] && [ "$got_sum" != "$want_sum" ]; then
            rm -rf "$tmp"
            warn 'The download arrived damaged, so nothing was installed.'
            info 'That is nearly always the connection rather than anything'
            info 'wrong. Choose this step again to retry it.'
            return 1
        fi
    fi

    info 'Unpacking...'
    # ditto, not unzip. It is the only one that keeps a signed app's insides
    # intact; unzip flattens the symbolic links inside the bundle and macOS
    # then refuses to open what comes out.
    if ! ditto -x -k "$tmp/$file" "$tmp/unpacked" 2>/dev/null; then
        rm -rf "$tmp"
        warn 'The download could not be opened.'
        return 1
    fi

    local src="$tmp/unpacked/$HERMES_APP_NAME.app"
    if [ ! -d "$src" ]; then
        # The name comes from the project's own build settings, but if they
        # ever rename it, take whatever single app came out rather than fail.
        src="$(find "$tmp/unpacked" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
    fi
    if [ -z "$src" ] || [ ! -d "$src" ]; then
        rm -rf "$tmp"
        warn 'The download did not contain the app.'
        return 1
    fi

    # An owner without an administrator account still gets the app, in their
    # own Applications folder. app_installed looks in both, so everything after
    # this point reads the same either way.
    local dest='/Applications'
    if [ ! -w "$dest" ]; then dest="$HOME/Applications"; fi
    mkdir -p "$dest" 2>/dev/null

    # Guarded on the name being non-empty. It is a constant and cannot be
    # blank, but this line is one empty variable away from erasing the whole
    # Applications folder, and that is not a risk worth carrying for brevity.
    if [ -n "$HERMES_APP_NAME" ] && [ -d "$dest/$HERMES_APP_NAME.app" ]; then
        rm -rf "$dest/$HERMES_APP_NAME.app"
    fi

    if ! ditto "$src" "$dest/$HERMES_APP_NAME.app" 2>/dev/null; then
        rm -rf "$tmp"
        warn "Could not put $HERMES_APP_NAME into $dest."
        return 1
    fi
    rm -rf "$tmp"

    if hermes_installed; then
        good "$HERMES_APP_NAME is installed."
        # Worth knowing, because it is the problem that stopped people opening
        # this setup at all: macOS only asks "are you sure, it is from the
        # internet" about files a browser downloaded. This one came through
        # curl, which marks nothing, so the app just opens.
        return 0
    fi

    warn "$HERMES_APP_NAME did not appear."
    if ask_yes_no "Open the $HERMES_APP_NAME download page in your browser instead?"; then
        open "$HERMES_DOWNLOAD_PAGE"
        info 'Install it from that page, then come back and press R to re-check.'
    fi
    return 1
}

open_hermes_to_finish() {
    title "Opening $HERMES_APP_NAME"
    info "$HERMES_APP_NAME is installed. It asks you for one thing before it can"
    info 'answer anything, and it is the same thing for everybody:'
    printf '\n'
    numbered 1 'Pick an AI provider' 'when it asks'
    numbered 2 'Paste that provider key' ''
    printf '\n'
    # Said plainly and early, because it is the one thing about this step that
    # will otherwise be discovered halfway through, on a payment page.
    warn 'That key is not your ChatGPT or Claude subscription.'
    info 'Paying for ChatGPT or Claude does not include one, and there is'
    info 'nothing to paste unless you have signed up for one separately.'
    printf '\n'
    info 'If you have not got one, just close it. Everything else in this'
    info 'setup is already finished and none of it depends on this.'
    printf '\n'

    # By name first, then by path. An app copied into place seconds ago may not
    # have been noticed by macOS yet, and "open -a" only knows apps it has been
    # told about - so on the one run where this matters most, the fresh install,
    # the name alone can fail while the app sits right there.
    if open -a "$HERMES_APP_NAME" 2>/dev/null; then
        good "$HERMES_APP_NAME is opening now."
        return 0
    fi

    local where
    for where in "/Applications/$HERMES_APP_NAME.app" "$HOME/Applications/$HERMES_APP_NAME.app"; do
        if [ -d "$where" ] && open "$where" 2>/dev/null; then
            good "$HERMES_APP_NAME is opening now."
            return 0
        fi
    done

    info "Could not open it from here. Open $HERMES_APP_NAME yourself whenever you like."
    return 0
}

confirm_zo_key_works() {
    # Uses the key straight away rather than waiting for the next check.
    #
    # It tells the owner immediately whether the key works, while the Zo page is
    # still open and copying it again costs seconds. And it learns their Zo
    # address there and then, so every link for the rest of the run opens their
    # own workspace instead of a generic page.
    printf '\n'
    info 'Checking the key with Zo...'

    zo_verify "$(get_zo_token)"
    if [ -z "$ZO_ANSWER" ]; then
        warn 'Saved, but Zo did not answer just now.'
        info 'That is usually the internet rather than the key itself.'
        return 0
    fi

    local url; url="$(zo_field 'data.workspaceUrl || ""')"
    if [ -n "$url" ]; then
        save_workspace_url "$url"
        good 'Your key works.'
        printf '        %s%s%s\n' "$C_TEAL" "$url" "$C_RESET"
        info 'Everything from here will open your own Zo pages.'
    else
        good 'Your key works.'
    fi
    return 0
}

set_zo_token_interactive() {
    title 'Your Zo account key'
    info 'This is what lets Claude and ChatGPT talk to your Zo.'

    # Asked before anything else: somebody without an account cannot get a key
    # and would otherwise sit on the settings page hunting for one.
    if ! ask_yes_no 'Do you already have a Zo account?'; then
        printf '\n'
        info 'No problem. Let us make one first.'
        if ask_yes_no 'Open the Zo sign-up page now?'; then
            open "$ZO_SIGNUP_URL"
        fi
        printf '\n'
        info 'Sign up, then come back here and choose this step again.'
        return 1
    fi

    printf '\n'
    info 'On the Zo website:'
    printf '\n'
    numbered 1 'Click' 'Settings, then Advanced'
    numbered 2 'Find the' 'Access Key'
    numbered 3 'Type any name, for example' 'my computer'
    numbered 4 'Click Add, then copy the key it shows you'
    printf '\n'

    # Opened, not offered. The key can only be copied from that page.
    open "$(zo_settings_url)" 2>/dev/null ||
        info 'Could not open your browser. The address is above.'

    printf '\n'
    info 'Paste the key below. It will not appear on screen as you type.'
    printf '      %sZo key > %s' "$C_PURPLE" "$C_RESET"
    local token
    read -rs token
    printf '\n'

    if ! token_looks_valid "$token"; then
        bad 'That does not look like a Zo key. It should start with zo_sk_'
        return 1
    fi

    save_zo_token "$token"
    good 'Saved to your login keychain.'
    confirm_zo_key_works
    return 0
}

backup_config() {
    # $1 = path. Prints the backup path, or nothing when there was no file.
    local path="$1"
    [ -f "$path" ] || return 0
    local dir; dir="$(dirname "$path")/vimigo-backups"
    mkdir -p "$dir"
    local stamp; stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    local backup="$dir/$(basename "$path").$stamp.bak"
    cp "$path" "$backup" && printf '%s' "$backup"
}

connect_zo_to_claude() {
    title 'Connecting Zo to Claude Desktop'

    local token; token="$(get_zo_token)"
    if ! token_looks_valid "$token"; then
        bad 'Enter your Zo account key first.'
        return 1
    fi

    if ! node_bin >/dev/null; then
        bad 'Node.js is needed to save this connection.'
        info 'Press Enter on the main screen and the setup will install it.'
        return 1
    fi

    mkdir -p "$(dirname "$CLAUDE_CONFIG")"

    local backup; backup="$(backup_config "$CLAUDE_CONFIG")"
    [ -n "$backup" ] && info 'Saved a backup of your existing Claude settings.'

    # Everything in this file that is not our own entry survives untouched.
    if ! "$(node_bin)" -e '
        const fs = require("fs");
        const [path, entry, pkg, url, token, npx] = process.argv.slice(1);
        let data = {};
        if (fs.existsSync(path)) {
            const raw = fs.readFileSync(path, "utf8").trim();
            if (raw) {
                try { data = JSON.parse(raw); } catch { process.exit(2); }
            }
        }
        if (typeof data !== "object" || data === null || Array.isArray(data)) process.exit(2);
        const servers = data.mcpServers ?? {};
        if (typeof servers !== "object" || servers === null || Array.isArray(servers)) process.exit(2);
        servers[entry] = {
            command: npx,
            args: [pkg, url, "--header", "Authorization: Bearer " + token],
        };
        data.mcpServers = servers;
        fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 });
    ' "$CLAUDE_CONFIG" "$ZO_MCP_ENTRY" "$MCP_REMOTE_PACKAGE" "$ZO_MCP_URL" "$token" "$(npx_bin)"
    then
        bad "Claude's settings file is not readable, so it was left alone."
        info 'Nothing was changed. Contact Vimigo support and they'
        info 'will sort it out.'
        return 1
    fi

    if ! claude_mcp_configured; then
        bad 'The connection did not save correctly. Restoring your previous settings.'
        [ -n "$backup" ] && cp "$backup" "$CLAUDE_CONFIG"
        return 1
    fi

    good 'Zo is connected to Claude Desktop.'
    warn 'Quit Claude Desktop completely and open it again for this to take effect.'
    return 0
}

connect_zo_to_chatgpt() {
    title 'Connecting Zo to ChatGPT'

    local token; token="$(get_zo_token)"
    if ! token_looks_valid "$token"; then
        bad 'Enter your Zo account key first.'
        return 1
    fi

    if ! node_bin >/dev/null; then
        bad 'Node.js is needed to save this connection.'
        info 'Press Enter on the main screen and the setup will install it.'
        return 1
    fi

    mkdir -p "$(dirname "$CODEX_CONFIG")"
    touch "$CODEX_CONFIG"

    local backup; backup="$(backup_config "$CODEX_CONFIG")"
    [ -n "$backup" ] && info 'Saved a backup of your existing ChatGPT settings.'

    # Drop our own section and re-add it, so a second run replaces rather than
    # stacks. Every other section is left byte-identical.
    "$(node_bin)" -e '
        const fs = require("fs");
        const [path, entry, pkg, url, token, npx] = process.argv.slice(1);
        const header = "[mcp_servers." + entry + "]";
        const lines = fs.readFileSync(path, "utf8").split("\n");

        const kept = [];
        let inTarget = false;
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed === header) { inTarget = true; continue; }
            if (inTarget && trimmed.startsWith("[") && trimmed.endsWith("]")) inTarget = false;
            if (!inTarget) kept.push(line);
        }

        const body = kept.join("\n").replace(/\s+$/, "");
        const block = header + "\ncommand = \"npx\"\n"
            + "args = [\"" + pkg + "\", \"" + url + "\", \"--header\", "
            + "\"Authorization: Bearer " + token + "\"]\n";
        fs.writeFileSync(path, (body ? body + "\n\n" : "") + block, { mode: 0o600 });
    ' "$CODEX_CONFIG" "$ZO_MCP_ENTRY" "$MCP_REMOTE_PACKAGE" "$ZO_MCP_URL" "$token" "$(npx_bin)"

    if ! codex_mcp_configured; then
        bad 'The connection did not save correctly. Restoring your previous settings.'
        [ -n "$backup" ] && cp "$backup" "$CODEX_CONFIG"
        return 1
    fi

    good 'Zo is connected to ChatGPT.'
    warn 'Quit ChatGPT completely and open it again for this to take effect.'
    printf '\n'

    # Where it actually appears. The Mac never said, and Windows said the wrong
    # place - a customer who looks and finds nothing concludes the setup failed.
    info 'If you open ChatGPT and cannot find Zo there:'
    printf '\n'
    numbered 1 'In ChatGPT open' 'Settings'
    numbered 2 'Click' 'Plugins'
    numbered 3 'Choose the tab called' 'MCPs'
    printf '\n'
    info 'Zo is in that list, already switched on. Nothing to set up -'
    info 'it is only somewhere to look if you want to see it.'
    return 0
}

zo_helper() {
    # Runs zo-verify.js with the owner's key and prints the raw JSON reply.
    # Every conversation with Zo goes through here.
    local token; token="$(get_zo_token)"
    case "$token" in zo_sk_*) ;; *) return 1 ;; esac
    local helper="$SCRIPT_DIR/zo-verify.js"
    [ -f "$helper" ] || return 1
    node_bin >/dev/null || return 1

    # The reason is kept, not thrown away.
    #
    # This sent stderr to /dev/null, so a Mac with a Node too old for fetch
    # failed three steps in a row and told nobody anything beyond "could not
    # start the sign-in". The owner sees the same short sentence as before -
    # they cannot act on a stack trace - but the setup now knows why, and
    # zo_helper_reason prints one plain line when there is something worth
    # saying.
    ZO_HELPER_REASON=''
    local errors; errors="$(mktemp 2>/dev/null || printf '/tmp/vimigo-zo-err')"
    "$(node_bin)" "$helper" "$token" "$@" 2>"$errors"
    local status=$?
    if [ "$status" -ne 0 ]; then
        ZO_HELPER_REASON="$(head -n 3 "$errors" | tr '\n' ' ' | cut -c1-200)"
    fi
    rm -f "$errors" 2>/dev/null
    return "$status"
}

ZO_HELPER_REASON=''
ZO_SCRIPTS_PUSHED='no'
WANT_CLAUDE='yes'
WANT_CHATGPT='yes'

ensure_zo_scripts() {
    # Puts this setup's own scripts on the owner's Zo. Once per run, because
    # several steps need them and none of them should have to care whether
    # another got there first.
    [ "$ZO_SCRIPTS_PUSHED" = 'yes' ] && return 0
    ZO_SCRIPTS_PUSHED='yes'
    zo_helper --install-zo-scripts >/dev/null 2>&1 || true
    return 0
}

zo_helper_reason() {
    # One plain line about the last failure, when there is one worth printing.
    # Written for somebody who has to read it out to support down a phone.
    [ -n "$ZO_HELPER_REASON" ] || return 0
    case "$ZO_HELPER_REASON" in
        *'fetch is not defined'*|*'ReferenceError'*)
            info 'Your Node.js is too old for this. Run the setup again and it'
            info 'will offer to update it.' ;;
        *ENOTFOUND*|*ETIMEDOUT*|*ECONNREFUSED*|*ENETUNREACH*|*EAI_AGAIN*)
            info 'This Mac could not reach Zo. Check the wifi and try again.' ;;
        *)
            info "Zo said: $ZO_HELPER_REASON" ;;
    esac
    ZO_HELPER_REASON=''
}

json_field() {
    # $1 = JSON text, $2 = a JavaScript expression over `data`.
    printf '%s' "$1" | "$(node_bin)" -e "
        let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{
            try { const data = JSON.parse(s); process.stdout.write(String($2)); }
            catch { process.stdout.write(''); }
        });" 2>/dev/null
}

install_zo_skills() {
    # Puts the recommended skills on the owner's Zo, without the owner going
    # anywhere near the Skills page.
    #
    # A skill is a folder holding a SKILL.md, so installing one is copying that
    # folder across - which the setup does over Zo's own connection. The folders
    # are what Zo's catalogue installs, in the same folder names, so this is not
    # an imitation of installing them; it is the same result.
    #
    # Anything already there is left alone, and the answer at the end is read
    # back off Zo rather than assumed from the commands having been sent.
    title 'Give your Zo more skills'
    info 'Skills teach your Zo to do bigger jobs. These nine come with the'
    info 'setup, and it puts them on for you now.'
    printf '\n'

    local index=0
    while [ "$index" -lt "${#ZO_SKILL_KEYS[@]}" ]; do
        printf '     %s %d %s  %s%-26s%s%s%s%s\n' \
            "$C_YELLOW" "$((index + 1))" "$C_RESET" \
            "$C_WHITE" "${ZO_SKILL_KEYS[$index]}" "$C_RESET" \
            "$C_GREY" "${ZO_SKILL_NOTES[$index]}" "$C_RESET"
        index=$((index + 1))
    done
    printf '\n'
    info 'Putting the skills on your Zo. This takes a moment.'

    local answer; answer="$(zo_helper --install-skills "$(skills_folder)")"
    if [ -z "$answer" ]; then
        bad 'Could not reach your Zo just now, so nothing was installed.'
        info 'Run the setup again in a moment and it will pick this up.'
        return 1
    fi

    local added missing
    # zo-verify.js prints {"ok":false,...} and still exits, so the reply is
    # never empty on failure. With only the emptiness test above, a Zo that
    # refused everything left added=0 and missing empty - and the owner was
    # told it "already had all nine".
    case "$answer" in
        *'"ok":false'*)
            bad 'Your Zo could not take the skills just now.'
            info 'Run the setup again in a moment and it will pick this up.'
            return 1 ;;
    esac

    added="$(json_field "$answer" '(data.added || []).length')"
    missing="$(json_field "$answer" '(data.missing || []).join(",")')"

    printf '\n'
    if [ -n "$added" ] && [ "$added" != "0" ]; then
        good "Installed $added of them."
    elif [ -z "$missing" ]; then
        good 'Your Zo already had all nine.'
    fi

    if [ -n "$missing" ]; then
        printf '\n'
        warn 'These did not go on:'
        local IFS_SAVE="$IFS"; IFS=','
        local name
        for name in $missing; do
            IFS="$IFS_SAVE"
            printf '         %s• %s%s\n' "$C_YELLOW" "$name" "$C_RESET"
            IFS=','
        done
        IFS="$IFS_SAVE"
        info 'Everything else is on. Run the setup again to retry these.'
        return 1
    fi

    printf '\n'
    info 'These nine are a starting point, not the whole list. There are'
    info 'hundreds more on that same page, and new ones appear all the'
    info 'time. Have a browse whenever you want your Zo to do something'
    info 'it cannot do yet:'
    printf '        %s%s%s\n' "$C_TEAL" "$(zo_skills_url)" "$C_RESET"
    return 0
}

show_pairing_code() {
    printf '\n'
    printf '        %s┌───────────────────────┐%s\n' "$C_TEAL" "$C_RESET"
    printf '        %s│  Your code:  %s%-9s%s│%s\n' "$C_TEAL" "$C_YELLOW" "$1" "$C_TEAL" "$C_RESET"
    printf '        %s└───────────────────────┘%s\n\n' "$C_TEAL" "$C_RESET"
}

install_whatsapp_on_zo() {
    # Builds the WhatsApp assistant on the owner's Zo, the first time.
    #
    # Minutes, not seconds. Zo ships an older Go than the assistant needs, so a
    # new Zo fetches a toolchain and around 300MB of parts and then builds for a
    # little over a minute. All of that happens on Zo, so it does not touch the
    # connection on this Mac.
    #
    # Watched rather than waited on. Several minutes of a still screen is
    # indistinguishable from a hang, and the owner will close the window.
    info 'Checking your Zo.'
    local started; started="$(zo_helper --install-whatsapp)"

    if [ -z "$started" ]; then
        bad 'Could not reach your Zo to set this up.'
        info 'Check the internet connection and try again.'
        return 1
    fi
    case "$started" in
        *'"ok":false'*)
            bad 'Could not reach your Zo to set this up.'
            info 'Check the internet connection and try again.'
            return 1 ;;
        *'"alreadyBuilt":true'*)
            return 0 ;;
    esac

    printf '\n'
    info 'Building your assistant on Zo. This happens once, and takes a'
    info 'few minutes. It is all on Zo, so it does not use your data.'
    printf '\n'

    local deadline; deadline=$(( $(date +%s) + 900 ))
    local frame=0 last_asked=0 stage='getting your Zo ready'
    local now progress new_stage

    while [ "$(date +%s)" -lt "$deadline" ]; do
        printf '\r      %s%s%s  %s%-60s%s' \
            "$C_TEAL" "$(wait_marker "$frame")" "$C_RESET" "$C_GREY" "$stage" "$C_RESET"
        frame=$((frame + 1))
        sleep 0.25

        # Asked every ten seconds, drawn four times a second. Tying the two
        # together would leave the marker frozen between questions, which is the
        # thing it exists to disprove.
        now="$(date +%s)"
        if [ $((now - last_asked)) -lt 10 ]; then continue; fi
        last_asked="$now"

        progress="$(zo_helper --install-whatsapp-progress)"
        [ -n "$progress" ] || continue

        new_stage="$(json_field "$progress" 'data.stage || ""')"
        [ -n "$new_stage" ] && stage="$new_stage"

        case "$progress" in
            *'"built":true'*)
                clear_wait_line
                good 'Your assistant is built.'
                return 0 ;;
            *'"failed":true'*)
                clear_wait_line
                bad 'Your assistant could not be built just now.'
                info 'Try this step again. If it happens twice, contact Vimigo'
                info 'support and they will sort it out.'
                return 1 ;;
        esac
    done

    clear_wait_line
    warn 'That is taking longer than expected.'
    info 'It may still finish on its own. Try this step again in a few'
    info 'minutes and it will pick up where it got to.'
    return 1
}

connect_whatsapp() {
    # Links a phone by driving Zo from here. The owner never opens Zo, never
    # explains what they want to an assistant, and never sees a command.
    #
    # One number only. The bridge holds a single linked device and refuses a
    # second pair attempt with "already paired", so running this again with a
    # different number adds nothing. Supporting more would mean a second bridge
    # with its own store, port, Zo service and MCP entry.
    title 'Connecting WhatsApp'

    case "$(get_zo_token)" in
        zo_sk_*) ;;
        *) bad 'Enter your Zo account key first.'; return 1 ;;
    esac

    # Built before anything is asked of it. Without this the first thing a new
    # customer sees is "the bridge is not installed on Zo yet", which was true
    # of every Zo except the one this was developed against.
    install_whatsapp_on_zo || return 1

    printf '\n'
    info 'Which WhatsApp number should your assistant use?'
    info 'Include the country code, digits only. For Malaysia that looks'
    info 'like 60123456789.'

    # Offered back, never assumed. Re-pairing the same number is the common case
    # after a phone unlinks the device, and retyping it is the sort of small
    # friction that makes someone give up.
    local phone=""
    local remembered; remembered="$(profile_get whatsappPhone)"
    if [ -n "$remembered" ]; then
        printf '\n'
        info "Last time you used $remembered."
        if ask_yes_no 'Use that number again?'; then phone="$remembered"; fi
    fi

    if [ -z "$phone" ]; then
        printf '\n      %sPhone number > %s' "$C_PURPLE" "$C_RESET"
        read -r phone || return 1
    fi
    [ -n "$phone" ] || { info 'Nothing entered, so nothing was changed.'; return 1; }

    # Named as well as numbered. "Which one is 60123456789" is a question nobody
    # should have to answer six months later, and once a business runs more than
    # one line the name is the only thing that tells them apart.
    local label; label="$(profile_get whatsappLabel)"
    if [ -z "$label" ]; then
        printf '\n'
        info 'What should we call this number? Something you will recognise,'
        info 'like Sales, Support, or My phone.'
        printf '\n      %sName for this number > %s' "$C_PURPLE" "$C_RESET"
        read -r label || label=''
        [ -n "$label" ] || label='My phone'
        profile_set whatsappLabel "$label"
    fi
    printf '\n'
    info "Setting up $label ($phone)."

    printf '\n'
    info 'Asking Zo to connect it.'
    info 'The first time on a new Zo this takes a few minutes, because'
    info 'your assistant is being built. After that it is seconds.'
    local answer; answer="$(zo_helper --pair "$phone")"

    if [ -z "$answer" ]; then
        bad 'Could not reach Zo to set this up.'
        info 'Check the internet connection and try again.'
        return 1
    fi

    case "$answer" in
        *'"ok":false'*)
            bad "$(json_field "$answer" 'data.error || "Zo refused that."')"; return 1 ;;
    esac

    # Remembered so that hiring an employee can refuse this number later. Two
    # bridges on one number both answer the same message, and the owner sees
    # their assistant reply twice and concludes it is broken.
    profile_set ownerPhone "$phone"

    case "$answer" in
        *'"alreadyPaired":true'*)
            good 'That number is already connected.'
            # Not "nothing to do". A number linked before this setup could make
            # one answer is linked and silent, and pairing it again would change
            # nothing at all.
            enable_whatsapp_replies
            return $? ;;
    esac

    local code; code="$(json_field "$answer" 'data.code || ""')"
    if [ -z "$code" ]; then
        warn 'Zo did not give a code back this time. Try this step again.'
        return 1
    fi

    # Remembered only once Zo accepted it, so a typo is never offered back.
    profile_set whatsappPhone "$phone"

    show_pairing_code "$code"
    info 'Now on your phone:'
    printf '\n'
    numbered 1 'Open' 'WhatsApp'
    numbered 2 'Tap Settings, then' 'Linked Devices'
    numbered 3 'Tap' 'Link a device'
    numbered 4 'Choose' 'Link with phone number instead'
    numbered 5 'Type in the code above'

    wait_for_whatsapp_pairing "$phone" || return 1

    # Linking is only half of it. Until this runs, the number collects messages
    # and answers nobody.
    enable_whatsapp_replies
}

wait_for_whatsapp_pairing() {
    # Watches for the phone to accept the code, and fetches a new one when the
    # old expires.
    #
    # A pairing code is short-lived. Printing one and leaving is how somebody
    # who took a moment to find Linked Devices ends up typing a dead code and
    # being told, with no explanation, that it did not work. So the setup counts
    # the code down, asks Zo whether the phone has linked, and issues a fresh
    # code when the clock runs out.
    local phone="$1"
    local started code_issued last_asked now remaining again state code

    started="$(date +%s)"; code_issued="$started"; last_asked="$started"

    while true; do
        now="$(date +%s)"
        if [ $((now - started)) -gt 600 ]; then
            printf '\n'
            warn 'Giving the phone a rest. Choose WhatsApp again when you are ready.'
            return 1
        fi

        remaining=$(( 120 - (now - code_issued) ))
        if [ "$remaining" -le 0 ]; then
            printf '\n'
            info 'That code has expired. Getting you a fresh one...'
            again="$(zo_helper --pair "$phone")"
            case "$again" in
                *'"alreadyPaired":true'*)
                    printf '\n'; good 'WhatsApp is linked.'; return 0 ;;
            esac
            code="$(json_field "$again" 'data.code || ""')"
            if [ -z "$code" ]; then
                printf '\n'
                warn 'Could not get a new code. Choose WhatsApp again to retry.'
                return 1
            fi
            code_issued="$(date +%s)"
            show_pairing_code "$code"
            continue
        fi

        # Redrawn every couple of seconds so the clock moves, but Zo is only
        # asked every fifteen. The lookup itself takes several seconds, and
        # tying the countdown to it would make the clock lurch.
        printf '\r      %swaiting for your phone... code valid for %d:%02d   %s' \
            "$C_GREY" $((remaining / 60)) $((remaining % 60)) "$C_RESET"

        sleep 2
        now="$(date +%s)"
        if [ $((now - last_asked)) -lt 15 ]; then continue; fi
        last_asked="$now"

        # The WhatsApp-only lookup, not the full check. The full one asks Zo six
        # questions and takes about twenty seconds, which cannot be run inside a
        # loop counting down a two-minute code.
        state="$(zo_helper --whatsapp-only)"
        case "$state" in
            *'"linked":true'*)
                clear_wait_line
                good 'WhatsApp is linked. That is it done.'
                return 0 ;;
        esac
    done
}

# The numbers collected so far, one per line. A function cannot hand a list back
# in bash, and this one has to print to the screen as it goes, so the answer
# comes out here instead.
ALLOWED_COLLECTED=""

add_allowed_number() {
    # Judges one entry and adds it if it is a usable phone number.
    #
    # Everything a real person types has to survive this: +60 12-345 6789, a
    # number pasted with a space, the same one twice, and the local form
    # starting with 0 - which is the one that matters, because 0123456789 looks
    # perfectly fine and is not a number WhatsApp knows.
    local entry="$1" digits
    digits="$(printf '%s' "$entry" | tr -cd '0-9')"

    if [ -z "$digits" ]; then
        bad "  \"$entry\" has no numbers in it."
        return 0
    fi

    # A leading 0 is the local way of writing it. Never silently corrected: the
    # country cannot be guessed from the digits, and guessing wrong puts a
    # stranger on the list.
    case "$digits" in
        0*)
            bad "  $entry looks like a local number."
            info '     Swap the first 0 for your country code, so 012 345 6789'
            info '     becomes 60123456789.'
            return 0 ;;
    esac
    if [ "${#digits}" -lt 8 ]; then
        bad "  $entry is too short to be a full number."
        return 0
    fi
    # Fifteen digits is the most any phone number in the world has.
    if [ "${#digits}" -gt 15 ]; then
        bad "  $entry is too long to be a phone number."
        return 0
    fi
    case ",$ALLOWED_COLLECTED," in
        *",$digits,"*)
            info "  $digits is already on the list."
            return 0 ;;
    esac

    if [ -n "$ALLOWED_COLLECTED" ]; then
        ALLOWED_COLLECTED="$ALLOWED_COLLECTED,$digits"
    else
        ALLOWED_COLLECTED="$digits"
    fi
    good "  Added $digits"
    return 0
}

read_allowed_numbers() {
    # Who is allowed to talk to the assistant.
    #
    # Required, not optional. This assistant can read the owner's mail, their
    # calendar and their files, so anyone who has the number could otherwise ask
    # it anything - and a number handed out to customers, or reused from an old
    # SIM, is a number strangers already have.
    #
    # Leaves the answer in ALLOWED_COLLECTED as a comma separated list, or empty
    # if the owner backs out - in which case nothing is switched on at all.
    ALLOWED_COLLECTED=""

    local known; known="$(profile_get allowedNumbers)"

    printf '\n'
    title 'Who can talk to your assistant'
    # The reason first, in two lines. Someone who does not understand why they
    # are being asked types one number to get past the screen, and the whole
    # protection is gone.
    warn 'This assistant can read your email, your calendar and your files.'
    warn 'So it answers only the numbers below. Everyone else is ignored.'
    printf '\n'
    info 'Your own phone first. Add staff if they should use it too.'
    info 'One at a time, or several separated by commas.'
    info 'With the country code, like 60123456789.'
    info 'Blank line when you are done.'

    if [ -n "$known" ]; then
        printf '\n'
        info 'Already allowed:'
        local IFS_SAVE="$IFS"; IFS=','
        local number
        for number in $known; do
            IFS="$IFS_SAVE"
            printf '         %s• %s%s\n' "$C_GREY" "$number" "$C_RESET"
            IFS=','
        done
        IFS="$IFS_SAVE"
        printf '\n'
        if ask_yes_no 'Keep this list as it is?'; then
            ALLOWED_COLLECTED="$known"
            return 0
        fi
    fi

    local entry piece
    while true; do
        printf '\n'
        if [ -z "$ALLOWED_COLLECTED" ]; then
            printf '      %sYour own number > %s' "$C_PURPLE" "$C_RESET"
        else
            printf '      %sAnother number (or Enter to finish) > %s' "$C_PURPLE" "$C_RESET"
        fi
        read -r entry || entry=''

        if [ -z "$entry" ]; then
            [ -n "$ALLOWED_COLLECTED" ] && break
            printf '\n'
            warn 'At least one number is needed, or your assistant cannot be'
            warn 'reached by anybody at all.'
            if ! ask_yes_no 'Try again?'; then
                ALLOWED_COLLECTED=""
                return 1
            fi
            continue
        fi

        # Split on anything somebody might reasonably type between numbers -
        # commas, semicolons, slashes, spaces, or a line pasted in from a
        # message. Each piece is then judged on its own, so one bad entry in a
        # pasted list does not throw away the good ones.
        for piece in $(printf '%s' "$entry" | tr ',;/|' '    '); do
            add_allowed_number "$piece"
        done
    done
    return 0
}

enable_whatsapp_replies() {
    # Makes a linked number answer.
    #
    # Pairing alone only makes Zo collect messages. Nothing reads them, so
    # nothing replies - which left an assistant looking connected and silent.
    # This turns on the part that answers, and proves it did rather than
    # reporting that a command was sent.
    printf '\n'
    title 'Making it answer'
    info 'Your number is linked. Now it needs to reply.'

    # The try-it-on-one-phone path. The number that was linked is the owner's
    # own, so it is the number that must be allowed - asking them to type it
    # again would be asking a question we already know the answer to.
    local self_chat='no' own allowed
    [ "$(profile_get talkChannel)" = "whatsapp-self" ] && self_chat='yes'

    allowed=""
    if [ "$self_chat" = "yes" ]; then
        own="$(profile_get whatsappPhone)"
        if [ -n "$own" ]; then
            printf '\n'
            info "Set up for your own chat, so only you ($own) can talk to it."
            allowed="$own"
        fi
    fi

    if [ -z "$allowed" ]; then
        read_allowed_numbers || true
        allowed="$ALLOWED_COLLECTED"
    fi

    if [ -z "$allowed" ]; then
        printf '\n'
        warn 'Left switched off, so nobody can talk to it yet.'
        info 'Choose WhatsApp again whenever you are ready.'
        return 1
    fi

    # Sent every time. A Zo set up last week has last week's scripts, and this
    # is what carries a fix to it.
    printf '\n'
    info 'Updating your Zo...'
    zo_helper --install-zo-scripts >/dev/null 2>&1 || true

    info 'Switching on replies...'
    # The brief goes with it, the same one an AI employee is hired on.
    #
    # set_active_persona binds to whichever channel called it, so the responder
    # has to carry the identity itself. Without this the owner's assistant
    # answered on WhatsApp as plain Zo - correct, but not theirs. It is the one
    # entry in the list that is never hireable, precisely because it belongs
    # here instead.
    local brief; brief="$(employee_prompt assistant)"
    local answer
    if [ "$self_chat" = "yes" ]; then
        answer="$(zo_helper --responder main --pa --owner "$allowed" \
            --assistant-name 'your assistant' --brief "$brief" --self)"
    else
        answer="$(zo_helper --responder main --pa --owner "$allowed" \
            --assistant-name 'your assistant' --brief "$brief")"
    fi

    case "$answer" in
        *'"ok":true'*) ;;
        *)
            bad 'It is linked, but it is not answering yet.'
            local why; why="$(json_field "$answer" 'data.error || ""')"
            [ -n "$why" ] && info "  $why"
            info 'Run this step again in a moment. Nothing was lost.'
            return 1 ;;
    esac

    profile_set allowedNumbers "$allowed"
    printf '\n'
    good 'Your assistant is answering.'
    local count; count="$(json_field "$answer" 'data.allowed || 0')"
    info "It replies to $count number(s) and ignores everyone else."
    printf '\n'
    if [ "$self_chat" = "yes" ]; then
        info 'Open WhatsApp, search for your own name, and type in that'
        info 'chat. It answers there, the same as it does on the web.'
    else
        info 'Message it from your phone and it will answer, the same as it'
        info 'does on the web. Ask it anything.'
    fi
    printf '\n'

    # Offered rather than assumed, and it is the only way to be sure. Everything
    # up to here proves the pieces are in place; this proves a message actually
    # comes back, which is the only thing the owner cares about.
    if ask_yes_no 'Send yourself a test message now?'; then
        local first; first="${allowed%%,*}"
        printf '\n'
        info 'Sending a test message...'
        local test_answer; test_answer="$(zo_helper --responder-test main "$first")"
        case "$test_answer" in
            *'"ok":true'*)
                good "Sent. Watch $first - a reply should arrive within a minute."
                info 'It will be signed so you know it came from your assistant.' ;;
            *)
                warn 'Could not send the test just now. That does not mean it is'
                warn 'broken - message it from your phone and see.' ;;
        esac
    fi
    return 0
}

main_setup_unfinished() {
    # Prints the title of every step the main setup has not finished, one per
    # line, and nothing at all when it is done.
    #
    # Its own function so it can be tested. Inline in the --assistant block it
    # could only be exercised by breaking the machine running it, which meant
    # the one path whose entire job is refusing was the one path never tried.
    #
    # The assistant is counted out: its own row must not be what stops it being
    # set up.
    local was="$FEATURE_AI_ASSISTANT" entry
    FEATURE_AI_ASSISTANT='off'
    collect_checks >/dev/null 2>&1
    FEATURE_AI_ASSISTANT="$was"
    for entry in "${CHECKS[@]}"; do
        case "$(printf '%s' "$entry" | cut -d'|' -f3)" in
            ok|skipped) ;;
            *) printf '%s
' "$(printf '%s' "$entry" | cut -d'|' -f2)" ;;
        esac
    done
}

set_talk_to_zo() {
    # How the owner actually reaches Zo day to day.
    #
    # This is the step everything else is for. A Mac can have every tool
    # installed, both apps connected and WhatsApp linked, and still be useless on
    # the Monday morning because nobody ever established where the owner types.
    # Claude Desktop and ChatGPT only work sitting at the computer, and a
    # business owner is not at their computer.
    #
    # Their own everyday number is never the first answer here: the bridge acts
    # AS the number it links, so linking their own leaves nobody for them to
    # message.
    title 'How you talk to Zo - your AI Personal Assistant'
    info 'Everything else is set up. This is where you actually talk to it.'
    printf '\n'
    numbered 1 'WhatsApp     -' 'needs a spare number, not your own'
    numbered 2 'Telegram     -' 'free, on your phone in two minutes'
    numbered 3 'On the web   -' 'nothing to set up, opens in your browser'
    printf '\n'
    # Last, and marked, because it is not how anyone should run their business.
    # It exists so the reply path can be tried on one phone.
    printf '     %s 4 %s  %s🧪 Your own number - testing only, not for daily use%s\n' \
        "$C_YELLOW" "$C_RESET" "$C_GREY" "$C_RESET"
    printf '\n      %sChoose 1, 2, 3 or 4 > %s' "$C_PURPLE" "$C_RESET"

    local choice; read -r choice || return 1
    choice="$(printf '%s' "$choice" | tr -cd '0-9')"

    case "$choice" in
        1)
            printf '\n'
            warn 'It must be a different number from your own.'
            printf '\n'
            info 'Your assistant becomes whatever number you give it. Use the'
            info 'number you carry every day and there is nobody left for you'
            info 'to message - you would be texting yourself.'
            if ! ask_yes_no 'Do you have a spare number?'; then
                printf '\n'
                info 'Then use Telegram for now. It costs nothing and takes two'
                info 'minutes, and you can move to WhatsApp when you have a SIM.'
                printf '\n'
                set_talk_to_zo_telegram
                return $?
            fi
            profile_set talkChannel 'whatsapp'
            printf '\n'
            connect_whatsapp
            return $? ;;
        2)
            set_talk_to_zo_telegram
            return $? ;;
        3)
            profile_set talkChannel 'web'
            printf '\n'
            info 'Your assistant lives here:'
            local home; home="${ZO_WORKSPACE_URL:-https://zo.computer}"
            [ -n "$home" ] || home='https://zo.computer'
            printf '        %s%s%s\n' "$C_TEAL" "$home" "$C_RESET"
            printf '\n'
            info 'Bookmark that page. It is the same assistant either way, so'
            info 'you can add WhatsApp or Telegram later without losing anything.'
            if ask_yes_no 'Open it now?'; then open "$home"; fi
            return 0 ;;
        4)
            set_talk_to_zo_self_test
            return $? ;;
        *)
            printf '\n'
            info 'Nothing chosen. You can come back to this any time.'
            return 1 ;;
    esac
}

set_talk_to_zo_self_test() {
    # Your assistant in your own "Message yourself" chat.
    #
    # For the person who turns up without a spare SIM and still wants to see this
    # working today. WhatsApp gives everybody a chat with themselves - the one
    # people use for notes - and that becomes a private line to Zo with nothing
    # to buy.
    #
    # Not how a business should run it, and the screen says so: the number is
    # also the owner's real number, so the assistant is sharing a line with their
    # customers. It is safe, because only messages the owner sends in that one
    # chat are ever answered - a customer messaging this number is not in it, and
    # gets nothing. But a spare SIM is still the right answer once they have one,
    # and moving to it loses nothing.
    printf '\n'
    title 'Your own number, to try it out'
    info 'Your assistant answers in your own chat - the one you use for'
    info 'notes to yourself.'
    printf '\n'
    good 'Only you can talk to it.'
    # "Customers" was too narrow. It is anyone at all - friends, family, a
    # supplier, a wrong number - and someone reading the narrower version could
    # reasonably think a friend would get an answer.
    info 'Other people and customers who message your number get nothing back.'
    printf '\n'
    warn 'Get a spare SIM later so your staff can use it too.'

    if ! ask_yes_no 'Set that up?'; then
        info 'No problem. Come back to this any time.'
        return 1
    fi

    profile_set talkChannel 'whatsapp-self'
    # Straight on with it. Sending someone back to the main screen to pick a
    # second thing, right after they picked the first, reads as "nothing
    # happened" - which is exactly how it was reported.
    connect_whatsapp
}

set_talk_to_zo_telegram() {
    # Connects Telegram without the owner opening Zo at all. Zo issues the
    # pairing code and the deep link, and the link is drawn as a QR so they can
    # point their phone at the screen - Telegram is on the phone, and a link on a
    # monitor would have to be typed out by hand.
    printf '\n'
    info 'Setting this up for you. One moment.'

    # "Is a phone connected?", not "has a new one arrived since I looked?".
    #
    # The old question compared a count before and after, which stuck fast for
    # anybody who already had Telegram connected: their number never went up, so
    # a setup that was finished before it started waited twelve minutes and then
    # gave up. Asking whether the step is done answers every case - nobody
    # connected yet, somebody connected already, or the same phone paired twice.
    local state linked link
    state="$(zo_helper --telegram-status)"
    linked="$(json_field "$state" 'data.linked || 0')"
    if [ "${linked:-0}" -gt 0 ] 2>/dev/null; then
        profile_set talkChannel 'telegram'
        printf '\n'
        good 'Telegram is already connected. Message your assistant there any time.'
        info 'To use a different phone instead, change it on the Zo website.'
        return 0
    fi

    link="$(zo_helper --telegram)"
    case "$link" in
        *'"ok":true'*) ;;
        *)
            bad 'Could not set up Telegram just now.'
            info 'Try this step again in a moment.'
            return 1 ;;
    esac
    [ -n "$(json_field "$link" 'data.url || ""')" ] || {
        bad 'Could not set up Telegram just now.'
        info 'Try this step again in a moment.'
        return 1
    }

    # Remembered only once it has actually worked. The channel used to be
    # written before the wait, so an owner who walked away from the QR came back
    # to a checklist claiming their assistant was set up on Telegram - the row
    # reads the remembered channel, not the link.
    wait_for_telegram_pairing "$link" || return 1
    profile_set talkChannel 'telegram'
}

show_telegram_invite() {
    # $1 = the raw JSON reply from --telegram
    local link="$1" rows row
    rows="$(json_field "$link" '(data.qr || []).join("\n")')"

    if [ -n "$rows" ]; then
        printf '\n'
        info 'Point your phone camera at this:'
        printf '\n'
        # Fed from a heredoc rather than a pipe, and that is load-bearing twice
        # over. A pipe would drop the last row - `read` returns non-zero on a
        # final line with no newline after it, and the loop body never runs for
        # it - and a QR code missing its bottom row does not scan. The heredoc
        # also keeps the loop in this shell, so nothing has to survive a
        # subshell.
        while IFS= read -r row; do
            printf '     %s%s%s\n' "$C_TEAL" "$row" "$C_RESET"
        done <<EOF
$rows
EOF
    fi
    printf '\n'
    info 'Or open this on your phone:'
    printf '        %s%s%s\n' "$C_TEAL" "$(json_field "$link" 'data.url || ""')" "$C_RESET"

    local code; code="$(json_field "$link" 'data.code || ""')"
    if [ -n "$code" ]; then
        printf '\n'
        info 'Or message @zo_computer_bot on Telegram with this code:'
        show_pairing_code "$code"
    fi
    return 0
}

wait_for_telegram_pairing() {
    # Same shape as the WhatsApp wait: the invite is good for a few minutes, so
    # it is counted down, a fresh one is fetched when it runs out, and Zo is
    # asked whether the phone has actually appeared rather than the owner being
    # asked whether it worked.
    local link="$1"
    local started issued last_asked now remaining state linked again

    started="$(date +%s)"; issued="$started"; last_asked="$started"
    show_telegram_invite "$link"

    while true; do
        now="$(date +%s)"
        if [ $((now - started)) -gt 720 ]; then
            printf '\n'
            warn 'Leaving it there for now. Choose this step again when ready.'
            return 1
        fi

        remaining=$(( 180 - (now - issued) ))
        if [ "$remaining" -le 0 ]; then
            printf '\n'
            info 'That link has expired. Getting you a fresh one...'
            again="$(zo_helper --telegram)"
            if [ -z "$(json_field "$again" 'data.url || ""')" ]; then
                printf '\n'
                warn 'Could not get a new link. Choose this step again to retry.'
                return 1
            fi
            link="$again"
            issued="$(date +%s)"
            show_telegram_invite "$link"
            continue
        fi

        printf '\r      %swaiting for your phone... link valid for %d:%02d   %s' \
            "$C_GREY" $((remaining / 60)) $((remaining % 60)) "$C_RESET"

        sleep 2
        now="$(date +%s)"
        if [ $((now - last_asked)) -lt 15 ]; then continue; fi
        last_asked="$now"

        # Connected at all, not connected more than before. See the note in
        # set_talk_to_zo_telegram: the same phone pairing twice adds no account,
        # and counting made that look like nothing had happened.
        state="$(zo_helper --telegram-status)"
        linked="$(json_field "$state" 'data.linked || 0')"
        [ -n "$linked" ] || linked=0
        if [ "$linked" -gt 0 ] 2>/dev/null; then
            clear_wait_line
            good 'Telegram is connected. Message your assistant there any time.'
            return 0
        fi
    done
}

show_hired_team() {
    # The team so far, from this Mac's own note. Zo stays the authority on who
    # exists, but keeping the names locally is what lets the hire screen open on
    # the team rather than on a blank list the owner has to remember.
    #
    # $1 = 'quiet' to leave off the heading, for a screen that has already said
    # who these people are. Without it the team screen read "1 working for you:"
    # and then "Working for you already:" directly underneath.
    local stored; stored="$(profile_get employees)"
    [ -n "$stored" ] || return 0

    [ "${1:-}" = 'quiet' ] || info 'Working for you already:'
    local IFS_SAVE="$IFS"; IFS=';'
    local member name role_title channel where
    for member in $stored; do
        IFS="$IFS_SAVE"
        [ -n "$member" ] || { IFS=';'; continue; }
        # Four fields now: name, job title, channel, number. Cut rather than
        # ${member#*|}, which used to take everything after the first bar and
        # would print "Sales|telegram|" as the job title.
        name="$(printf '%s' "$member" | cut -d'|' -f1)"
        role_title="$(printf '%s' "$member" | cut -d'|' -f2)"
        channel="$(printf '%s' "$member" | cut -d'|' -f3)"
        case "$channel" in
            ''|none) where='no way to reach them yet' ;;
            *) where="on $channel" ;;
        esac
        printf '         %s• %s%s%-16s%s %s%-24s%s %s%s%s\n' \
            "$C_GREY" "$C_RESET" "$C_WHITE" "$name" "$C_RESET" \
            "$C_GREY" "$role_title" "$C_RESET" "$C_GREY" "$where" "$C_RESET"
        IFS=';'
    done
    IFS="$IFS_SAVE"
    printf '\n'
    return 0
}

employee_field() {
    # $1 = the stored record, $2 = which field. Kept in one place so the layout
    # of a record is described once rather than in five loops.
    printf '%s' "$1" | cut -d'|' -f"$2"
}

update_hired_employee_channel() {
    # $1 = name, $2 = channel, $3 = number.
    #
    # Written against the existing entry rather than as a list of its own, so
    # that letting an employee go takes the number with them and there is never
    # a spare number sitting against somebody who no longer works here.
    local name="$1" channel="$2" phone="${3:-}"
    local stored; stored="$(profile_get employees)"
    local kept="" member record
    local IFS_SAVE="$IFS"; IFS=';'
    for member in $stored; do
        IFS="$IFS_SAVE"
        [ -n "$member" ] || { IFS=';'; continue; }
        if [ "$(employee_field "$member" 1)" = "$name" ]; then
            record="$name|$(employee_field "$member" 2)|$channel|$phone"
        else
            record="$member"
        fi
        if [ -n "$kept" ]; then kept="$kept;$record"; else kept="$record"; fi
        IFS=';'
    done
    IFS="$IFS_SAVE"
    profile_set employees "$kept"
}

add_hired_employee() {
    # $1 = name, $2 = job title. Kept so "the sales one" still means something
    # six months later when the only thing on Zo is a persona called Zoe.
    # A bar or a semicolon in a name would split one employee into two records
    # and the team list would show staff who do not exist. The name is typed by
    # the owner, so it is not hostile - just possible.
    local name; name="$(printf '%s' "$1" | tr '|;' '  ')"
    local role_title; role_title="$(printf '%s' "$2" | tr '|;' '  ')"
    local stored; stored="$(profile_get employees)"
    local kept="" member
    local IFS_SAVE="$IFS"; IFS=';'
    for member in $stored; do
        IFS="$IFS_SAVE"
        [ -n "$member" ] || { IFS=';'; continue; }
        if [ "$(employee_field "$member" 1)" != "$name" ]; then
            if [ -n "$kept" ]; then kept="$kept;$member"; else kept="$member"; fi
        fi
        IFS=';'
    done
    IFS="$IFS_SAVE"
    # Channel and number are left empty here and filled in by the question that
    # comes next, so the record has its full shape from the moment it exists.
    if [ -n "$kept" ]; then kept="$kept;$name|$role_title||"; else kept="$name|$role_title||"; fi
    profile_set employees "$kept"
}

remove_hired_employee() {
    # $1 = name. The local note goes when Zo's copy does, or the team list keeps
    # showing somebody who no longer exists.
    local name="$1"
    local stored; stored="$(profile_get employees)"
    local kept="" member
    local IFS_SAVE="$IFS"; IFS=';'
    for member in $stored; do
        IFS="$IFS_SAVE"
        [ -n "$member" ] || { IFS=';'; continue; }
        if [ "${member%%|*}" != "$name" ]; then
            if [ -n "$kept" ]; then kept="$kept;$member"; else kept="$member"; fi
        fi
        IFS=';'
    done
    IFS="$IFS_SAVE"
    profile_set employees "$kept"
}

sync_hired_employees() {
    # Reconciles this Mac's note against Zo, and leaves the note matching Zo.
    #
    # Zo decides who exists. The note only remembers what Zo does not keep -
    # which job somebody was hired for - so it is a convenience and never the
    # authority. Three things can have happened since it was written: somebody
    # was deleted on the website, somebody was created there, or nothing
    # changed. All three end with the note matching Zo.
    #
    # Left untouched when Zo cannot be reached, rather than emptying the team
    # over a dropped connection. An AI employee nobody can account for is worse
    # than none, and these are answering real people.
    local listed; listed="$(zo_helper --employees)" || return 1
    [ -n "$listed" ] || return 1
    case "$(json_field "$listed" 'data.ok === true')" in true) ;; *) return 1 ;; esac

    local names; names="$(json_field "$listed" '(data.employees || []).join("\n")')"

    local stored; stored="$(profile_get employees)"
    local rebuilt="" name member found record
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        # Keep the whole record already held for this name - job title, channel
        # and number - rather than just the title. Rebuilding from the name
        # alone would quietly forget which employees were on Telegram.
        found=''
        local IFS_SAVE="$IFS"; IFS=';'
        for member in $stored; do
            IFS="$IFS_SAVE"
            [ -n "$member" ] || { IFS=';'; continue; }
            if [ "$(employee_field "$member" 1)" = "$name" ]; then found="$member"; fi
            IFS=';'
        done
        IFS="$IFS_SAVE"
        # Made on the Zo website, or by asking Zo directly. It exists and it
        # answers, so it belongs on the list even though the only thing known
        # about it is the name.
        record="${found:-$name|made on the Zo website||}"
        if [ -n "$rebuilt" ]; then
            rebuilt="$rebuilt;$record"
        else
            rebuilt="$record"
        fi
    done <<EOF
$names
EOF

    profile_set employees "$rebuilt"
    return 0
}

show_team_screen() {
    # Who works for the business, read from Zo.
    #
    # Its own screen because "do I still have that sales one" is a question
    # people actually ask, and hunting for it inside the hiring flow means
    # risking hiring another one by mistake.
    title 'Your AI employees'

    sync_hired_employees || true

    local stored; stored="$(profile_get employees)"
    if [ -z "$stored" ]; then
        info 'Nobody works for you yet.'
        printf '\n'
        info 'Press E on the main screen to hire your first one. They take'
        info 'about a minute each.'
        return 0
    fi

    local count=0 member
    local IFS_SAVE="$IFS"; IFS=';'
    for member in $stored; do
        IFS="$IFS_SAVE"; [ -n "$member" ] && count=$((count + 1)); IFS=';'
    done
    IFS="$IFS_SAVE"

    info "$count working for you:"
    printf '\n'
    show_hired_team quiet
    info 'To change what one of them does, just tell your Zo. Say'
    info '"Joe should also handle refunds" and it will sort it out.'
    printf '\n'
    info 'Their pages, to edit or remove them:'
    printf '        %s%s%s\n' "$C_TEAL" "$(zo_personas_url '')" "$C_RESET"
    return 0
}

setup_second_brain() {
    # Sets up somewhere for the business to keep what it learns.
    #
    # Nothing is asked. It makes plain folders of Markdown - the kind that open
    # on a phone, in Obsidian, or in anything else, now and in ten years - and
    # an index over them so a phrase can be found across all of it at once.
    # Empty and labelled, so that when the assistant is told to remember
    # something there is somewhere for it to go.
    #
    # What it deliberately does not do is decide how this business works. Nine
    # folders is a guess, and a good guess is still a guess: a workshop needs
    # jobs and parts, a clinic needs patients and appointments. That part is a
    # conversation with their Zo, not a question on a setup screen, and the
    # screen says so rather than implying this is finished.
    title 'Your company second brain'
    info 'This is where your Zo keeps what it learns about your business,'
    info 'so it stops asking you the same things twice.'
    printf '\n'

    local result; result="$(zo_helper --second-brain)"
    if [ -z "$result" ] || [ "$(json_field "$result" 'data.ok === true')" != 'true' ]; then
        bad 'Could not set that up just now.'
        info 'Run the setup again in a moment and it will pick this up.'
        return 1
    fi

    local folders indexed
    folders="$(json_field "$result" 'data.folders || 0')"
    indexed="$(json_field "$result" 'data.indexed === true')"

    good "Ready. $folders drawers, labelled and empty."
    printf '\n'
    printf '         %sPeople             who works here, and what they do%s\n' "$C_GREY" "$C_RESET"
    printf '         %sCustomers          who they are, what they bought, what they asked%s\n' "$C_GREY" "$C_RESET"
    printf '         %sSuppliers          what they supply, what it costs, who to call%s\n' "$C_GREY" "$C_RESET"
    printf '         %sProducts           what you sell, and what people ask about it%s\n' "$C_GREY" "$C_RESET"
    printf '         %sMoney              prices, terms, who pays late%s\n' "$C_GREY" "$C_RESET"
    printf '         %sDecisions          what was decided, and why%s\n' "$C_GREY" "$C_RESET"
    printf '         %sMeetings           what was said and what was agreed%s\n' "$C_GREY" "$C_RESET"
    printf '         %sHow we do things   hours, refunds, complaints, deliveries%s\n' "$C_GREY" "$C_RESET"
    printf '         %sInbox              anything not sorted out yet%s\n' "$C_GREY" "$C_RESET"
    printf '\n'
    if [ "$indexed" = 'true' ]; then
        info 'Everything in there can be searched instantly, however much'
        info 'of it there is.'
        printf '\n'
    fi

    # The honest part. Nine folders is a guess at what a business looks like,
    # and saying "done" here would leave someone expecting it to be right for
    # them out of the box.
    warn 'This is a starting point, not a finished filing system.'
    printf '\n'
    info 'Every business keeps different things. A workshop wants jobs and'
    info 'parts; a clinic wants patients and appointments; a shop wants'
    info 'stock and suppliers.'
    printf '\n'
    info 'So tell your Zo about your business and let it shape this around'
    info 'you. Just talk to it, the way you would tell a new employee how'
    info 'things work here:'
    printf '\n'
    printf '         %s"We are a car workshop. Keep a file for every job."%s\n' "$C_WHITE" "$C_RESET"
    printf '         %s"Remember that Ali Trading always pays late."%s\n' "$C_WHITE" "$C_RESET"
    printf '         %s"Every time I send you a receipt, file it under Money."%s\n' "$C_WHITE" "$C_RESET"
    printf '\n'
    info 'The more you tell it, the more useful it gets.'
    return 0
}

menu_has_options() {
    # Whether the finished screen offers anything besides Close. Its own
    # function so the header and the acceptance suite ask the same question,
    # rather than each keeping a list of switches that has to be updated twice.
    feature_on "$FEATURE_AI_EMPLOYEES" && return 0
    feature_on "$FEATURE_AI_ASSISTANT" && return 0
    feature_on "$FEATURE_SECOND_BRAIN" && return 0
    feature_on "$FEATURE_FINISHED_MENU" && return 0
    return 1
}

show_main_options() {
    # Everything the owner can do, in one place. $1 = 'finished' to leave out
    # the big Enter box.
    #
    # The same list whether the setup has finished or not, because "what can I
    # do here" should not depend on how much is ticked - somebody who finished
    # yesterday and came back to hire a second employee met a different,
    # shorter menu than the one they used the first time.
    # The header only when there is something under it. With every switch off
    # the finished screen offers Close and nothing else, and "What you can do:"
    # above a single Close reads like the rest failed to load.
    if [ "${1:-}" = 'finished' ] && menu_has_options; then
        info 'What you can do:'
    fi
    printf '\n'

    if [ "${1:-}" != 'finished' ]; then
        printf '        %s┌──────────────────────────────────────┐%s\n' "$C_GREEN" "$C_RESET"
        printf '        %s│%s   %sPress ENTER to set everything up%s   %s│%s\n' \
            "$C_GREEN" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_GREEN" "$C_RESET"
        printf '        %s└──────────────────────────────────────┘%s\n\n' "$C_GREEN" "$C_RESET"
    fi

    # Until the setup has finished there is exactly one key: Enter.
    #
    # Everything else manages something that does not exist yet, on a screen
    # that already says how much is left. The whole list comes back the moment
    # it is done. See the Windows note for the reasoning.
    #
    # A switched-off feature takes its key with it. A menu that lists something
    # this build will not do is worse than one that never mentioned it: the
    # owner presses the key, nothing happens, and now they doubt the rest of the
    # screen too.
    if [ "${1:-}" = 'finished' ]; then
        if feature_on "$FEATURE_AI_EMPLOYEES"; then
            printf '        %s E %s  %sHire an AI employee         %s%ssales, admin, accounts, and more%s\n' \
                "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_GREY" "$C_RESET"
            printf '        %s T %s  %sSee your AI employees       %s%swho works for you, and where they answer%s\n' \
                "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_GREY" "$C_RESET"
        fi
        if feature_on "$FEATURE_AI_ASSISTANT"; then
            printf '        %s A %s  %sSet up your assistant again %s%schange the number, or how you reach it%s\n' \
                "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_GREY" "$C_RESET"
        fi
        if feature_on "$FEATURE_SECOND_BRAIN"; then
            printf '        %s M %s  %sYour company second brain   %s%swhat your Zo remembers about the business%s\n' \
                "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_GREY" "$C_RESET"
        fi
        if feature_on "$FEATURE_FINISHED_MENU"; then
        printf '        %s Z %s  %sOpen your Zo                %s%sthe website, for anything not here%s\n' \
            "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_GREY" "$C_RESET"
        # Named for what it does, not for what it is useful for. "To test it as a
        # new customer would" reads like a harmless preview to someone who is not
        # testing anything.
        printf '        %s S %s  %sStart over                  %s%sWARNING! Removes what this setup%s\n' \
            "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_YELLOW" "$C_RESET"
        # Lined up under "WARNING!", which starts at column 41: eight spaces, the
        # three-character key, two more, then the twenty-eight the label occupies.
        printf '                                         %sinstalled, then sets it up again%s\n' \
            "$C_YELLOW" "$C_RESET"
        fi
    fi

    printf '        %s Q %s  %sClose%s\n' "$C_YELLOW" "$C_RESET" "$C_WHITE" "$C_RESET"
    printf '\n'
}

handle_main_choice() {
    # Runs the action for a main-menu key. $1 = the key already lowercased.
    #
    # Shared by both menus - the finished one and the unfinished one - because
    # when they each had their own copy the finished one quietly offered fewer
    # options, and the way back from a finished setup was the destructive one.
    #
    # Prints nothing and returns 1 for a key it does not know, so the caller can
    # treat that as "do the whole checklist".
    #
    # Each key is gated on its feature, not only hidden from the menu. A key
    # that still works while nothing offers it is worse than a missing one: the
    # owner presses E by accident and this build hires somebody it was never
    # meant to be able to hire.
    case "$1" in
        e*)
            feature_on "$FEATURE_AI_EMPLOYEES" || return 1
            clear_screen; show_banner
            hire_employee || true
            printf '      Press Enter to go back '; read -r _ || true
            return 0 ;;
        t*)
            feature_on "$FEATURE_AI_EMPLOYEES" || return 1
            clear_screen; show_banner
            show_team_screen || true
            printf '\n      Press Enter to go back '; read -r _ || true
            return 0 ;;
        a*)
            feature_on "$FEATURE_AI_ASSISTANT" || return 1
            clear_screen; show_banner
            reset_whatsapp_assistant || true
            printf '      Press Enter to go back '; read -r _ || true
            return 0 ;;
        m*)
            feature_on "$FEATURE_SECOND_BRAIN" || return 1
            clear_screen; show_banner
            setup_second_brain || true
            printf '\n      Press Enter to go back '; read -r _ || true
            return 0 ;;
        z*)
            feature_on "$FEATURE_FINISHED_MENU" || return 1
            clear_screen; show_banner
            local home; home="${ZO_WORKSPACE_URL:-https://zo.computer}"
            [ -n "$home" ] || home='https://zo.computer'
            info 'Your Zo:'
            printf '        %s%s%s\n\n' "$C_TEAL" "$home" "$C_RESET"
            if ask_yes_no 'Open it now?'; then open "$home" 2>/dev/null || true; fi
            printf '      Press Enter to go back '; read -r _ || true
            return 0 ;;
        s*)
            # Gated even though nothing offers it, because this one removes
            # what the setup installed. An owner tapping at a finished screen
            # must not be able to reach it by accident, and --reset is how
            # support and testing get to it now.
            feature_on "$FEATURE_FINISHED_MENU" || return 1
            clear_screen; show_banner
            reset_vimigo_setup || true
            printf '      Press Enter to check again '; read -r _ || true
            return 0 ;;
    esac
    return 1
}

LAST_EMPLOYEE_PHONE=''

wait_for_employee_number() {
    # $1 = employee name. Waits while the owner types the pairing code into
    # their phone.
    #
    # It waits rather than asking whether they did it. The setup once marched
    # past a step the owner was still working on and reported nine failures for
    # a man who had not finished signing up; this is the same shape of step, on
    # a phone, and gets the same treatment.
    local name="$1" waited=0 state paired

    while [ "$waited" -lt 300 ]; do
        printf '\r      %s...waiting for %s'"'"'s number to link%s   ' \
            "$C_GREY" "$name" "$C_RESET"
        sleep 8
        waited=$((waited + 8))

        state="$(zo_helper --employee-number-status "$name")"
        paired="$(json_field "$state" 'data.paired === true')"
        if [ "$paired" = 'true' ]; then
            printf '\r%*s\r' 72 ''
            return 0
        fi
    done

    printf '\r%*s\r' 72 ''
    return 1
}

set_employee_whatsapp() {
    # $1 = name, $2 = the job description Zo was given for them.
    #
    # Gives one AI employee a WhatsApp number of their own, and links it.
    #
    # A number used to be written on a note here and joined up never. That was
    # honest about itself and still wrong: the owner picked WhatsApp, answered
    # the question, and ended up with an employee nobody could message.
    #
    # One bridge holds one linked device, so this is a whole second WhatsApp
    # connection on their Zo - its own store, its own port, its own service.
    local name="$1" brief="$2"
    LAST_EMPLOYEE_PHONE=''

    printf '\n'
    info "$name needs a WhatsApp number of their own."
    printf '\n'
    info 'It has to be a spare number - not the one you use yourself, and'
    info 'a different one again for each employee. A number can only be'
    info 'joined to one of these at a time.'
    printf '\n'
    info 'Have the phone with that SIM in front of you. You will type a'
    info 'short code into it in a moment.'
    printf '\n'

    # Asked until it is answered or they back out. Required means required, but
    # a required question with no way out is a trap - somebody without a spare
    # SIM has to be able to leave without closing the window.
    local phone='' typed digits own_number
    while [ -z "$phone" ]; do
        info 'What is the number? With the 60 in front, like 60123456789.'
        printf '\n'
        printf '      %sNumber, or Enter to go back > %s' "$C_PURPLE" "$C_RESET"
        read -r typed || typed=''
        if [ -z "$typed" ]; then
            printf '\n'
            info "No number, so $name has no WhatsApp yet."
            info 'Telegram needs no SIM card at all, if that suits you better.'
            return 1
        fi

        # Everything that is not a digit goes, so "+60 12-345 6789" is accepted
        # from somebody reading it off the back of a SIM pack.
        digits="$(printf '%s' "$typed" | tr -cd '0-9')"
        if [ "${#digits}" -lt 8 ]; then
            printf '\n'
            bad 'That does not look like a full phone number.'
            info 'It needs the country code in front, like 60123456789.'
            printf '\n'
            continue
        fi
        # Their own number, the one their assistant answers on. WhatsApp would
        # allow it as a second linked device and then both would reply to the
        # same message, which reads as the product being broken.
        own_number="$(profile_get ownerPhone)"
        if [ -n "$own_number" ] && [ "$digits" = "$own_number" ]; then
            printf '\n'
            bad 'That is your own number, the one your assistant uses.'
            info 'An employee on it would be answering you instead of your'
            info 'customers, and both would reply to the same message.'
            printf '\n'
            continue
        fi
        phone="$digits"
    done

    printf '\n'
    info "Giving $name their own number..."
    local result; result="$(zo_helper --employee-number "$name" "$phone")"

    if [ -z "$result" ] || [ "$(json_field "$result" 'data.ok === true')" != 'true' ]; then
        printf '\n'
        case "$(json_field "$result" 'data.code || ""')" in
            bridge_missing)
                bad 'Your own WhatsApp assistant has to be working first.'
                info 'Finish that step, then come back and hire again.' ;;
            name_taken)
                bad "$name already has a number set up."
                info 'Let them go first if you want to give them a different one.' ;;
            no_port)
                bad 'This Zo has no room for another number just now.' ;;
            *)
                bad 'Could not set that number up just now.'
                local why; why="$(json_field "$result" 'data.error || ""')"
                [ -n "$why" ] && info "  $why"
                info 'Nothing is lost. Try this step again in a moment.' ;;
        esac
        return 1
    fi

    LAST_EMPLOYEE_PHONE="$phone"

    local linked=no
    if [ "$(json_field "$result" 'data.alreadyPaired === true')" = 'true' ]; then
        good "$name is on $phone."
        linked=yes
    fi

    # Codes expire, so this loops rather than saying it once.
    #
    # It used to end with "nothing expires", which is not true: a WhatsApp
    # pairing code is short-lived, and a bridge left unpaired long enough loses
    # its connection in a way that only a fresh one clears. Somebody who went
    # looking for Linked Devices and came back to a dead code was told to run
    # the setup again, which landed them on the same dead bridge.
    local attempt=0 pair_code
    while [ "$linked" = 'no' ] && [ "$attempt" -lt 4 ]; do
        attempt=$((attempt + 1))
        pair_code="$(json_field "$result" 'data.pairCode || ""')"
        if [ -z "$pair_code" ]; then
            printf '\n'
            bad 'WhatsApp did not send a code just now.'
            info 'Try this step again in a moment.'
            return 0
        fi

        printf '\n'
        info "On the phone with $phone in it, open WhatsApp and go to:"
        printf '\n'
        numbered 1 'Settings, then' 'Linked Devices'
        numbered 2 'Tap' 'Link a device'
        numbered 3 'Tap' 'Link with phone number instead'
        numbered 4 'Type this code:'
        show_pairing_code "$pair_code"
        info 'Type it soon - codes only last a few minutes.'
        printf '\n'

        if wait_for_employee_number "$name"; then
            good "$name is on $phone."
            linked=yes
            break
        fi

        printf '\n'
        warn 'That code has run out.'
        printf '\n'
        if ! ask_yes_no 'Send a new one?'; then
            printf '\n'
            info "$name is saved. Run the setup again when the phone is in"
            info 'front of you and it will offer a new code.'
            return 0
        fi

        # The same call again. It knows the number is half-made, so it issues a
        # fresh code - and rebuilds the bridge first if that is what it takes.
        info 'Getting a new code...'
        result="$(zo_helper --employee-number "$name" "$phone")"
        if [ -z "$result" ] || [ "$(json_field "$result" 'data.ok === true')" != 'true' ]; then
            printf '\n'
            bad 'Could not get a new code just now.'
            info 'Run the setup again in a moment and it will offer one.'
            return 0
        fi
        if [ "$(json_field "$result" 'data.alreadyPaired === true')" = 'true' ]; then
            good "$name is on $phone."
            linked=yes
        fi
    done

    if [ "$linked" = 'no' ]; then
        printf '\n'
        info "$name is saved, and their number is waiting for a code."
        info 'Run the setup again whenever the phone is in front of you.'
        return 0
    fi

    # The responder, so the number answers as this employee rather than as the
    # owner's assistant. Never enabled here: an employee knows a job title and
    # nothing about the business yet, and this number is one customers can
    # reach.
    printf '\n'
    info "Teaching $name who they are..."
    zo_helper --responder "$name" --assistant-name "$name" --brief "$brief" >/dev/null 2>&1 || true

    printf '\n'
    warn "$name is not answering anybody yet, and that is deliberate."
    printf '\n'
    info 'They know their job title and nothing about your business. Teach'
    info "them first - tell your Zo about $name, what you sell, your"
    info 'prices, your hours. Then let them start answering.'
    return 0
}

wait_for_employee_telegram() {
    # $1 = name, $2 = bot username. Waits for the owner to say hello to their
    # new employee, so the setup can say it worked rather than asking whether
    # it did.
    local name="$1" username="$2"
    local waited=0 state paired

    while [ "$waited" -lt 300 ]; do
        printf '\r      %s...waiting for you to say hello to %s%s   ' \
            "$C_GREY" "$name" "$C_RESET"
        sleep 8
        waited=$((waited + 8))

        state="$(zo_helper --telegram-employee-status "$name")"
        paired="$(json_field "$state" 'data.paired === true')"
        if [ "$paired" = 'true' ]; then
            printf '\r%*s\r' 72 ''
            good "$name has said hello. They are yours to teach."
            printf '\n'
            info 'When you are happy they know the job, tell your Zo to let'
            info "$name answer your customers - or come back here and hire"
            info 'the next one.'
            return 0
        fi
    done

    printf '\r%*s\r' 72 ''
    info "$name is set up and waiting for you in Telegram."
    info "Say hello to @$username whenever you like - nothing expires."
    return 0
}

set_employee_telegram() {
    # $1 = name, $2 = the job description Zo was given for them.
    #
    # Gives one employee its own Telegram, and proves it answers.
    #
    # Zo's own Telegram connects the owner's account, so an employee sitting on
    # it answers as the boss. A bot is a separate identity - and it needs no SIM
    # card, which is why this is the practical choice for employees where
    # WhatsApp wants a spare number each.
    #
    # The owner makes the bot themselves, in Telegram, by messaging @BotFather.
    # That is five taps on a phone, which is squarely inside what they already
    # do, and it means the bot belongs to them rather than to us.
    local name="$1" brief="$2"

    printf '\n'
    info "$name needs their own Telegram. It is free, it takes a minute,"
    info 'and you do not need another phone number.'
    printf '\n'
    info 'On your phone, in Telegram:'
    printf '\n'
    numbered 1 'Search for' '@BotFather'
    numbered 2 'Send it' '/newbot'
    numbered 3 "Give it a name -" "$name works well"
    numbered 4 'Give it a username ending in' 'bot'
    numbered 5 'It replies with a long line. Copy it.'
    printf '\n'
    info 'That long line is what tells your Zo it may answer as this bot.'
    info 'It looks like 8123456789:AAH-abc123...'
    printf '\n'

    printf '      %sPaste it here (or Enter to skip) > %s' "$C_PURPLE" "$C_RESET"
    local bot_token; read -r bot_token || bot_token=''
    bot_token="$(printf '%s' "$bot_token" | tr -d '[:space:]')"
    if [ -z "$bot_token" ]; then
        printf '\n'
        info "No problem. $name is saved, and you can do this any time."
        return 1
    fi

    # Sent every time, so a Zo set up before this existed gets the new files.
    zo_helper --install-zo-scripts >/dev/null 2>&1 || true

    local result
    result="$(zo_helper --telegram-employee "$name" --bot-token "$bot_token" --brief "$brief")"

    if [ -z "$result" ] || [ "$(json_field "$result" 'data.ok === true')" != 'true' ]; then
        printf '\n'
        # A bot already wired to something else is the common mistake, not a
        # fault, so it gets its own answer rather than "something went wrong".
        if [ "$(json_field "$result" 'data.code || ""')" = 'bot_in_use' ]; then
            bad 'That one is already doing another job.'
            printf '\n'
            info 'A Telegram bot can only work for one thing at a time, and'
            info 'that one is already connected to something else. Taking it'
            info 'over would stop whatever is using it.'
            printf '\n'
            info "Make a new one for $name - send /newbot to @BotFather"
            info 'again. It is free, and you can have as many as you like.'
            printf '\n'
            if ask_yes_no 'Try again with a new bot?'; then
                set_employee_telegram "$name" "$brief"
                return $?
            fi
            return 1
        fi

        bad "Could not set $name up on Telegram just now."
        local why; why="$(json_field "$result" 'data.error || ""')"
        [ -n "$why" ] && info "  $why"
        info 'Nothing was lost. Try this step again in a moment.'
        return 1
    fi

    local username pair_code join_url
    username="$(json_field "$result" 'data.username || ""')"
    pair_code="$(json_field "$result" 'data.pairCode || ""')"

    printf '\n'
    good "$name is live on Telegram."
    printf '        %s@%s%s\n' "$C_TEAL" "$username" "$C_RESET"
    printf '\n'
    info "Right now $name answers only you, nobody else. That is on"
    info 'purpose: they know their job title and nothing about your'
    info 'business yet, and a customer would believe whatever they say.'
    printf '\n'

    # A deep link, and a QR of it, rather than a code to copy out. The code has
    # to be long enough to be unguessable - whoever says it first owns this
    # employee - and nobody types thirty-two characters into a phone by hand.
    # The screen is on a laptop and the thing that must act on it is a phone, so
    # a camera is the shortest path between them.
    join_url="https://t.me/$username?start=$pair_code"

    info 'So teach them first. Point your phone camera at this and it'
    info 'says hello for you - nothing to type:'
    printf '\n'
    local picture; picture="$(zo_helper --qr "$join_url")"
    local rows; rows="$(json_field "$picture" '(data.qr || []).join("\n")')"
    if [ -n "$rows" ]; then
        while IFS= read -r line; do
            printf '     %s%s%s\n' "$C_TEAL" "$line" "$C_RESET"
        done <<EOF
$rows
EOF
        printf '\n'
        info 'Or open this on your phone:'
    fi
    printf '        %s%s%s\n' "$C_TEAL" "$join_url" "$C_RESET"
    printf '\n'
    info 'Then just talk to them. Tell them what you sell, your prices,'
    info 'your hours, anything. They will remember it.'
    printf '\n'

    wait_for_employee_telegram "$name" "$username"
    return 0
}

set_employee_channel() {
    # $1 = name, $2 = the job description Zo was given for them.
    #
    # Asks how staff and customers are meant to reach one employee, and writes
    # the answer down.
    #
    # Two ways offered, not four. The web chat and the owner's own number belong
    # to the owner's own assistant: the owner's number is the one they type into
    # themselves, so an employee sitting on it would be answering the boss
    # instead of the customer. Saying so in one line is cheaper than letting
    # them pick it and find out.
    #
    # Nothing here half-connects anything. A second WhatsApp number is its own
    # job - its own bridge, its own linked device - so this records what they
    # want and says plainly that nobody can reach the employee yet. An employee
    # that looks reachable is a customer messaging a number nobody is on.
    local name="$1" brief="$2"

    printf '\n'
    info "How will people reach $name?"
    printf '\n'
    info 'An employee talks to your staff and your customers, so they need'
    info 'somewhere to be messaged.'
    printf '\n'
    numbered 1 'WhatsApp -' 'needs its own number, not the one you use'
    numbered 2 'Telegram -' 'free, and no extra phone number needed'
    numbered 3 'Not yet  -' 'I will sort this out later'
    printf '\n'
    info 'The web chat and your own number are not on this list. Those two'
    info 'are yours, for the assistant you talk to yourself.'
    printf '\n'

    printf '      %sChoose 1, 2 or 3 > %s' "$C_PURPLE" "$C_RESET"
    local pick; read -r pick || pick=''
    pick="$(menu_number "$pick")"

    # What gets written down. Only WhatsApp is ever recorded as a channel:
    # writing "telegram" against an employee before it exists would be recording
    # a wish as a setting, and a later run would try to honour it.
    local channel='none' phone=''

    case "$pick" in
        1)
            if set_employee_whatsapp "$name" "$brief"; then
                channel='whatsapp'
                phone="$LAST_EMPLOYEE_PHONE"
            fi
            ;;
        2)
            if set_employee_telegram "$name" "$brief"; then channel='telegram'; fi
            ;;
        *)
            printf '\n'
            good 'That is a perfectly good answer.'
            info "$name is saved either way, and you can give them a way to"
            info 'be reached whenever you want. There is no rush: they have'
            info 'plenty to learn from you first.'
            ;;
    esac

    update_hired_employee_channel "$name" "$channel" "$phone"
    return 0
}

hire_employee() {
    # Hires an AI employee: pick a role, name them, and Zo creates the persona.
    # Deliberately shaped like hiring a person rather than editing settings,
    # because that is what it is - and the owner will manage them the same way
    # afterwards.
    title 'Hire an AI employee'

    case "$(get_zo_token)" in
        zo_sk_*) ;;
        *) bad 'Enter your Zo account key first.'; return 1 ;;
    esac

    show_hired_team

    info 'Who do you need? Think of it like hiring someone for a job.'
    printf '\n'

    # The owner's own assistant is not on this list.
    #
    # It is the required one, set up earlier on the checklist, and it already
    # has this same brief. Offering it here invites hiring a second assistant
    # that nobody can reach - it would have no channel, because the ways of
    # reaching an assistant belong to the first. Windows has excluded it since
    # the list existed; the Mac was offering it as row 1, the likeliest thing
    # for somebody to pick.
    local hire_keys=() hire_titles=() hire_for=()
    local index=0
    while [ "$index" -lt "${#EMPLOYEE_KEYS[@]}" ]; do
        if [ "${EMPLOYEE_KEYS[$index]}" != 'assistant' ]; then
            hire_keys+=("${EMPLOYEE_KEYS[$index]}")
            hire_titles+=("${EMPLOYEE_TITLES[$index]}")
            hire_for+=("${EMPLOYEE_FOR[$index]}")
        fi
        index=$((index + 1))
    done

    local count="${#hire_keys[@]}"
    index=0
    while [ "$index" -lt "$count" ]; do
        printf '     %s %d %s  %s%-24s%s%s%s%s\n' \
            "$C_YELLOW" "$((index + 1))" "$C_RESET" \
            "$C_WHITE" "${hire_titles[$index]}" "$C_RESET" \
            "$C_GREY" "${hire_for[$index]}" "$C_RESET"
        index=$((index + 1))
    done
    printf '     %s %d %s  %s%-24s%s%s%s%s\n' \
        "$C_YELLOW" "$((count + 1))" "$C_RESET" \
        "$C_WHITE" 'Someone else' "$C_RESET" \
        "$C_GREY" 'describe the job yourself' "$C_RESET"
    # Skipping is a numbered choice like any other, rather than something the
    # owner has to work out by pressing nothing. See the Windows note.
    printf '     %s %d %s  %s%-24s%s%s%s%s\n' \
        "$C_YELLOW" "$((count + 2))" "$C_RESET" \
        "$C_WHITE" 'Not now' "$C_RESET" \
        "$C_GREY" 'skip this - you can hire any time later' "$C_RESET"
    printf '\n'

    printf '      %sChoose 1 to %d > %s' "$C_PURPLE" "$((count + 2))" "$C_RESET"
    local choice; read -r choice || return 1
    choice="$(menu_number "$choice")"
    # Enter, and anything unexpected, mean the same as the skip row.
    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$((count + 2))" ]; then
        printf '\n'
        info 'Nobody hired. You can do this whenever you like.'
        return 1
    fi
    if [ "$choice" -eq "$((count + 2))" ]; then
        printf '\n'
        good 'No problem - that is a perfectly good answer.'
        info 'Your assistant is already working. Hire your first employee'
        info 'whenever you are ready: press E on the main screen.'
        return 1
    fi

    local role role_title prompt
    if [ "$choice" -eq "$((count + 1))" ]; then
        role='custom'
        role_title='AI employee'
        printf '\n'
        info 'What is the job? One or two sentences is plenty.'
        printf '\n      %sThe job > %s' "$C_PURPLE" "$C_RESET"
        read -r prompt || prompt=''
        if [ -z "$prompt" ]; then
            info 'Nothing described, so nobody was hired.'
            return 1
        fi
    else
        role="${hire_keys[$((choice - 1))]}"
        role_title="${hire_titles[$((choice - 1))]}"
        prompt="$(employee_prompt "$role")"
    fi

    printf '\n'
    info "What shall we call your $role_title? A first name works well."
    printf '\n      %sName > %s' "$C_PURPLE" "$C_RESET"
    local name; read -r name || name=''
    [ -n "$name" ] || name="$role_title"

    # Customers are on the other end of this one, and Zo starts an employee with
    # every permission. Worth one sentence before it happens rather than a
    # surprise afterwards.
    if [ "$role" = "customer-service" ]; then
        printf '\n'
        warn 'A word about this one.'
        info 'Your customers will be talking to it directly, and it starts'
        info 'with permission to use everything your Zo can reach. You can'
        info 'narrow that afterwards on your own AI settings page.'
        if ! ask_yes_no "Hire $name anyway?"; then
            info 'No problem. Nobody was hired.'
            return 1
        fi
    fi

    printf '\n'
    info "Hiring $name..."
    local answer; answer="$(zo_helper --hire "$name" "$prompt")"

    case "$answer" in
        *'"ok":true'*) ;;
        *)
            bad 'Could not hire them just now.'
            local why; why="$(json_field "$answer" 'data.error || ""')"
            [ -n "$why" ] && info "  $why"
            return 1 ;;
    esac

    printf '\n'
    good "$name is hired."
    printf '\n'

    # Money, so it is said out loud either way. On the owner's own plan there is
    # nothing more to pay; without one, Zo charges by use and they should hear
    # that from us rather than from a bill.
    local own_plan model
    own_plan="$(json_field "$answer" 'data.ownPlan === true')"
    model="$(json_field "$answer" 'data.model || ""')"
    if [ "$own_plan" = "true" ]; then
        good 'Running on the AI plan you already pay for. No extra cost.'
        [ -n "$model" ] && printf '         %s%s%s\n' "$C_GREY" "$model" "$C_RESET"
    else
        warn 'This one runs on Zo credit, which is charged by use.'
        printf '\n'
        info 'To put it on the Claude or ChatGPT plan you already pay for,'
        info 'do this once on the Zo website:'
        printf '\n'
        numbered 1 'Open' 'your Zo settings, AI page'
        numbered 2 'Under Providers, click' 'Connect for Claude and ChatGPT'
        numbered 3 'Turn on the models' 'you want to use'
        numbered 4 'Set your default' 'for every channel'
        printf '\n'
        printf '        %s%s%s\n' "$C_TEAL" "$(zo_ai_settings_url)" "$C_RESET"
        printf '\n'
        info 'Then hire again and they will use your plan instead.'
    fi
    printf '\n'

    # Straight to this employee's own page, using the id Zo just handed back.
    local persona_id persona_url
    persona_id="$(json_field "$answer" 'data.id || ""')"
    persona_url="$(zo_personas_url "$persona_id")"

    add_hired_employee "$name" "$role_title"

    # Where they can be reached, asked now rather than left for later. Hiring
    # somebody and never being asked how to contact them is how a Mac owner
    # reached the end of this screen, went looking for the Telegram step, and
    # found the setup had gone back to the beginning.
    set_employee_channel "$name" "$prompt"

    # The part that saves building a settings screen for any of this: the owner
    # already has four ways to talk to Zo, and Zo can edit its own employees.
    info "To change what $name does, just tell your assistant. Say"
    info "\"$name should also handle refunds\" - in the web chat, on"
    info 'WhatsApp, or in Claude on this Mac. No settings needed.'
    printf '\n'
    info 'Or open their page and edit it yourself:'
    printf '        %s%s%s\n' "$C_TEAL" "$persona_url" "$C_RESET"

    if ask_yes_no 'Open that page now?'; then open "$persona_url"; fi
    return 0
}

show_zo_model_step() {
    # $1 = the friendly provider name, e.g. Claude or ChatGPT.
    #
    # Signing in is only half of it. Zo still needs the provider switched on in
    # its own settings, its models ticked, and one chosen as the default, and
    # none of that can be done from here: Zo's web settings live on its servers,
    # and the API that would change them rejects the key this setup holds.
    #
    # So it is spelled out instead. Saying "connected" and stopping - which is
    # what the Mac did - leaves the owner with a plan they pay for and an
    # assistant that never uses it.
    local friendly="$1"

    printf '\n'
    warn 'One more part, and it has to be done on the Zo website.'
    printf '\n'
    numbered 1 'Scroll down to' 'Providers'
    numbered 2 "Click Connect next to" "$friendly"
    numbered 3 'Click every model to' 'turn them all on'
    numbered 4 'Scroll back up to' 'Models'
    numbered 5 'Change the selected models to the ones below'
    printf '\n'
    info 'Signing in only tells Zo who you are. Until the provider is'
    info 'switched on there, Zo will not actually use the plan you pay for.'
    printf '\n'
    info 'What we suggest setting as the default, in this order:'
    printf '\n'
    numbered 1 'Opus 5 on' 'low'
    numbered 2 'ChatGPT Luna on' 'xhigh'
    printf '\n'
    info 'Opus 5 on low is quick and covered by a Claude plan, so it suits'
    info 'everyday work. Luna on xhigh thinks harder and is the one to fall'
    info 'back to. You can change either whenever you like, on this page:'
    printf '        %s%s%s\n' "$C_TEAL" "$(zo_ai_settings_url)" "$C_RESET"

    if ask_yes_no 'Open that page now?'; then
        open "$(zo_ai_settings_url)" 2>/dev/null || true
    fi
    return 0
}

connect_zo_ai_provider() {
    # Signs the owner's Zo in to a Claude or ChatGPT plan they already pay for,
    # so Zo stops billing per use.
    local which="$1" friendly
    if [ "$which" = "claude" ]; then friendly="Claude"; else friendly="ChatGPT"; fi

    title "Using your $friendly plan on Zo"
    info "If you already pay for $friendly, your Zo can use that plan"
    info 'instead of charging you separately each time.'

    if ! ask_yes_no "Do you have a paid $friendly plan?"; then
        info 'That is fine. Zo will just bill per use. Skipping this.'
        return 1
    fi

    # The scripts have to be on the Zo before one of them can answer.
    #
    # zo-ai-signin.sh is what reports whether a plan is linked, and it used to
    # be put on the Zo only by the WhatsApp assistant and the employee Telegram
    # steps. Switch those off - as v1 does - and it never arrives at all, so
    # this step could not start and the two plan rows stayed red for ever, no
    # matter how many times the owner linked their plan on the Zo website.
    # Cheap, and it also carries any fix shipped since their last run.
    ensure_zo_scripts

    info 'Starting the sign-in. This takes a moment.'
    local answer; answer="$(zo_helper --signin "$which")" || {
        bad 'Could not start the sign-in.'; zo_helper_reason; return 1; }

    case "$answer" in
        *'"alreadySignedIn":true'*)
            good "Your $friendly plan is already connected."
            show_zo_model_step "$friendly"
            return 0 ;;
        *'"ok":false'*)
            bad "$(json_field "$answer" 'data.error || "Zo refused that."')"; return 1 ;;
    esac

    local url code; url="$(json_field "$answer" 'data.url || ""')"
    code="$(json_field "$answer" 'data.code || ""')"
    [ -n "$url" ] || { bad 'Zo did not give a sign-in link.'; return 1; }

    printf '\n'
    info 'Open this page and sign in:'
    printf '        %s%s%s\n' "$C_TEAL" "$url" "$C_RESET"
    if [ -n "$code" ]; then
        printf '\n        %sYour code:  %s%s%s\n' "$C_GREY" "$C_YELLOW" "$code" "$C_RESET"
        info '        Type that into the page when it asks.'
    fi

    if ask_yes_no 'Open that page in your browser now?'; then open "$url"; fi

    if [ "$(json_field "$answer" 'data.needsCodeBack === true')" = "true" ]; then
        # Claude hands a code back through the browser, which has to reach the
        # sign-in still waiting on Zo.
        printf '\n'
        info 'When the page gives you a code, paste it here.'
        printf '      %sCode > %s' "$C_PURPLE" "$C_RESET"
        local given; read -r given || return 1
        [ -n "$given" ] || { info 'Nothing entered. You can run this step again.'; return 1; }

        local finish; finish="$(zo_helper --signin-code "$given")"
        case "$finish" in
            *'"signedIn":true'*)
            good "Your $friendly plan is connected."
            show_zo_model_step "$friendly"
            return 0 ;;
        esac
        warn 'That did not go through. You can try this step again.'
        return 1
    fi

    printf '\n'
    info 'Finish signing in on that page, then come back here.'
    return 0
}

open_zo_google() {
    title 'Connecting your Google apps'
    info 'This one happens on the Zo website, where Google asks your'
    info 'permission. Nobody can do that part for you.'
    printf '\n'
    numbered 1 'Find the' 'Integrations'
    numbered 2 'Click Connect next to' 'Gmail'
    numbered 3 'Sign in, then' 'tick every box Google shows'
    numbered 4 'Click' 'Allow'
    numbered 5 'Repeat for' 'Calendar, Drive and Sheets'
    printf '\n'

    # The single most common way this goes wrong. Google presents the
    # permissions as individually tickable, people tick only what sounds
    # necessary, and the connection then half-works in ways that surface much
    # later as "the assistant cannot see my calendar".
    warn '   Please tick every box Google offers.'
    info '   Leaving one out looks fine at the time, and then your'
    info '   assistant quietly cannot do that one thing later.'
    printf '\n'
    info 'Each app is asked for separately, so four apps means doing this'
    info 'four times. Connecting one does not connect the others.'
    printf '\n'
    info 'You can add more than one Google account. Most people connect'
    info 'their work one and their personal one, so the assistant can see'
    info 'both calendars and both drives.'
    printf '\n'
    info 'Not a Gmail user? Zo connects Outlook, Outlook Calendar and'
    info 'OneDrive in exactly the same way. Connect those instead.'
    printf '\n'
    info 'While you are there, have a look at the rest of the list. Zo'
    info 'connects Notion, Dropbox, Airtable, Linear and many more.'
    info 'Anything you use every day is worth connecting.'
    printf '\n'

    # Opened, not offered. This step cannot be done anywhere but that page, so
    # asking whether to go there is a question with one sensible answer.
    open "$(zo_integrations_url)" 2>/dev/null ||
        info 'Could not open your browser. The address is above.'

    printf '\n'
    # Nothing is recorded on the owner's say-so. The next check asks Zo itself,
    # so a sign-in abandoned halfway still shows up as unfinished.
    info 'When you have finished, come back here. This setup will ask Zo'
    info 'directly which ones worked.'
    return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

fix_one() {
    case "$1" in
        # Node comes from nodejs.org first. Everything on the Zo side needs it,
        # and putting it behind Homebrew puts it behind Xcode's command line
        # tools - a gigabyte or more, on a phone hotspot, before the owner has
        # seen anything work. Homebrew is still the fallback.
        node)
            if [ -n "$(command_version node --version)" ]; then
                good "Node.js $(command_version node --version) is already installed."
            elif install_node_directly; then
                : # done
            else
                warn 'Trying the longer way instead.'
                install_brew_formula node "Node.js" node --version
            fi ;;
        git)
            if [ -n "$(command_version git --version)" ]; then
                good "Git $(command_version git --version) is already installed."
            elif install_git_directly; then
                : # done
            else
                install_brew_formula git "Git" git --version
            fi ;;
        python)
            if [ -n "$(command_version python3 --version)" ]; then
                good "Python $(command_version python3 --version) is already installed."
            elif install_python_directly; then
                : # done
            else
                warn 'Trying the longer way instead.'
                install_brew_formula python@3.13 "Python" python3 --version
            fi ;;
        # Installed is not signed in, and only signed in is any use: the Zo
        # entry goes into a config the app writes for a logged-in user, so an
        # app nobody has opened looks perfectly installed and has no Zo in it.
        # So the install is followed straight away by opening it.
        claude-app)
            install_desktop_app claude "Claude" "Claude Desktop" "$CLAUDE_DOWNLOAD_URL" || return 1
            open_app_to_sign_in "Claude" ;;
        chatgpt-app)
            install_desktop_app chatgpt "ChatGPT" "ChatGPT Desktop" "$CHATGPT_DOWNLOAD_URL" || return 1
            open_app_to_sign_in "ChatGPT" ;;
        zo-token)    set_zo_token_interactive ;;
        claude-mcp)  connect_zo_to_claude ;;
        chatgpt-mcp) connect_zo_to_chatgpt ;;
        local-whatsapp) show_local_whatsapp ;;
        zo-claude-code) connect_zo_ai_provider claude ;;
        zo-codex)       connect_zo_ai_provider codex ;;
        zo-skills)   install_zo_skills ;;
        zo-brain)    setup_second_brain ;;
        zo-google)   open_zo_google ;;
        talk-to-zo)
            # Somebody who already chose WhatsApp and stopped halfway wants to
            # carry on, not to be asked which channel they wanted again.
            case "$(profile_get talkChannel)" in
                whatsapp|whatsapp-self) connect_whatsapp ;;
                *)                      set_talk_to_zo ;;
            esac ;;
        zo-employees) hire_employee ;;
        # Installed, then opened, and that is where this step ends. It is
        # deliberately not on OWNER_COMPLETES: everything the setup can verify
        # here - that the app is on the Mac - it has just done itself, and the
        # part it cannot verify is a provider key it should not be holding.
        # Asking "have you finished that step?" would be asking a question the
        # setup already knows the answer to, which is what Tengku had taken out
        # everywhere else.
        hermes-app)
            install_hermes_one || return 1
            open_hermes_to_finish ;;
        *)           bad "Nothing to do for '$1'."; return 1 ;;
    esac
}

# Names of the things that did not finish, one per line. The closing screen
# reads this so it can be honest rather than claiming success for all of it.
UNFINISHED=""

# Steps the setup can start but cannot finish: the owner has to restart an app,
# sign in on a website, or type a code into their phone. Running straight on to
# the next one while they are still doing it is how a setup ends up reporting
# that nothing worked.
# claude-mcp and chatgpt-mcp used to be on this list and are not any more.
# They were here because connecting Zo needs the app restarted, and a restart
# was the owner's job. It is not any more - the setup restarts the app itself -
# and the check for these two reads the config file the setup has just written
# and verified. So "Have you finished that step?" was asking the owner to
# confirm something already known, about work they had not done.
OWNER_COMPLETES="claude-app chatgpt-app zo-claude-code zo-codex zo-google"

# The steps that cannot do anything without the owner's Zo key. Kept in step
# with the Windows list of the same name.
NEEDS_ZO_KEY="claude-mcp chatgpt-mcp zo-claude-code zo-codex zo-skills zo-brain zo-google talk-to-zo zo-employees"

check_now() {
    # Re-detects a single step, so the owner gets an answer about the thing they
    # just did rather than a whole re-scan. Prints true, false, or nothing when
    # it cannot be determined.
    case "$1" in
        claude-mcp)  claude_mcp_configured && printf 'true' || printf 'false'; return 0 ;;
        chatgpt-mcp) codex_mcp_configured  && printf 'true' || printf 'false'; return 0 ;;
        # Answered on this Mac, so neither needs Zo and neither should fall
        # through to the ask below.
        claude-app)  app_installed "Claude"  && printf 'true' || printf 'false'; return 0 ;;
        chatgpt-app) app_installed "ChatGPT" && printf 'true' || printf 'false'; return 0 ;;
        # Answered here too, though nothing calls it today - hermes-app is not
        # a step the owner finishes elsewhere. Listed so that if it ever joins
        # that list, it cannot fall through to the Zo questions below and come
        # back "could not tell" on a machine with no key.
        hermes-app)  hermes_installed && printf 'true' || printf 'false'; return 0 ;;
    esac

    zo_verify "$(get_zo_token)"
    [ -n "$ZO_ANSWER" ] || return 0

    case "$1" in
        # Answering, not merely linked. A number that collects messages and
        # replies to nobody is not a working assistant.
        talk-to-zo)     zo_field 'data.whatsapp.connected === true && data.whatsapp.answering === true' ;;
        zo-claude-code) zo_field 'data.aiProviders?.claude?.loggedIn === true' ;;
        zo-codex)       zo_field 'data.aiProviders?.codex?.loggedIn === true' ;;
        zo-google)      zo_field 'Object.values(data.integrations).every(v => v.connected === true)' ;;
    esac
}

wait_for_owner_step() {
    # $1 = key, $2 = friendly title.
    # Holds until the owner says they are finished, then checks whether they
    # really are. Their word alone never marks anything done.
    printf '\n'
    info 'Take your time. Nothing else will happen until you are ready.'

    while true; do
        if ! ask_yes_no 'Have you finished that step?'; then
            printf '\n'; info 'Skipped for now. You can come back to it any time.'
            return 1
        fi

        printf '\n'; info 'Checking...'
        local result; result="$(check_now "$1")"

        case "$result" in
            true)  good "$2 is done."; return 0 ;;
            false) ;;
            *)     warn 'Could not check that just now, so it has been left as it is.'; return 1 ;;
        esac

        printf '\n'
        # Which parts are done, not just that it is not.
        #
        # A step made of four separate sign-ins fails as one line - "that does
        # not look finished yet" - and the owner has no idea which of the four
        # they missed, so they redo all of them or give up. check_now has just
        # refreshed the answer, so this costs nothing.
        local breakdown
        breakdown=''
        case "$1" in
            zo-google)
                breakdown="$(zo_field '
                    Object.entries(data.integrations)
                        .map(([k, v]) => {
                            const name = ({gmail:"Gmail", google_calendar:"Calendar",
                                           google_drive:"Drive", google_sheets:"Sheets"})[k] || k;
                            return (v.connected === true ? "ok|" : "no|") + name;
                        }).join("\n")')" ;;
        esac

        if [ -n "$breakdown" ]; then
            warn 'Not quite finished. Here is where it stands:'
            printf '\n'
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                case "$line" in
                    ok\|*) printf '           %s✓%s  %s\n' \
                        "$C_TEAL" "$C_RESET" "${line#ok|}" ;;
                    no\|*) printf '           %s·%s  %-14s %sstill to connect%s\n' \
                        "$C_GREY" "$C_RESET" "${line#no|}" "$C_YELLOW" "$C_RESET" ;;
                esac
            done <<EOF
$breakdown
EOF
            printf '\n'
        else
            warn 'That does not look finished yet.'
        fi

        case "$1" in
            claude-mcp|chatgpt-mcp)
                info 'The app only reads its settings when it starts, so it has'
                info 'to be closed completely and opened again.' ;;
        esac
        # Said plainly, because it is true and because someone who thinks they
        # are stuck will close the window rather than say no.
        info 'These are recommendations, not requirements. Skipping is'
        info 'fine and you can finish them whenever you like.'
        if ! ask_yes_no 'Try checking again?'; then
            info 'Left as it is. You can come back to it any time.'
            return 1
        fi
    done
}

read_ai_app_choice() {
    # Which AI app the owner wants, asked once and remembered.
    #
    # Asked rather than inferred because inference gets it wrong in the case
    # that matters: somebody who pays for ChatGPT, with an old Claude on the
    # Mac they have never opened, would be walked through setting Claude up and
    # signing into it. One of the two is enough, and they know which.
    local stored; stored="$(profile_get aiApps)"
    [ -n "$stored" ] && { printf '%s' "$stored"; return 0; }

    title 'Claude or ChatGPT'
    info 'Your Zo works with both, and you only need one.'
    info 'Pick the one you already pay for, if you pay for either.'
    printf '\n'
    numbered 1 'Claude    -' 'from Anthropic'
    numbered 2 'ChatGPT   -' 'from OpenAI'
    numbered 3 'Both      -' 'set up both, if you use both'
    printf '\n'
    printf '        %sEnter  both, if you are not sure%s\n\n' "$C_GREY" "$C_RESET"
    printf '      %sChoose 1, 2 or 3, or Enter > %s' "$C_PURPLE" "$C_RESET"

    local answer choice
    read -r answer || answer=''
    answer="$(printf '%s' "$answer" | tr -cd '0-9')"
    # Anything unrecognised means both, which is what this did before anybody
    # was asked. A wrong keypress must never quietly drop an app they wanted.
    case "$answer" in
        1) choice='claude' ;;
        2) choice='chatgpt' ;;
        *) choice='both' ;;
    esac
    profile_set aiApps "$choice"
    printf '\n'
    case "$choice" in
        claude)  good 'Claude it is. ChatGPT will be left alone.' ;;
        chatgpt) good 'ChatGPT it is. Claude will be left alone.' ;;
        *)       good 'Both, then.' ;;
    esac
    printf '%s' "$choice"
}

fix_everything() {
    # Before anything else, and only when there is a key to do it with. Several
    # steps below read their answer from a script that lives on the Zo, and
    # until this ran they were reading nothing.
    if token_looks_valid "$(get_zo_token)"; then ensure_zo_scripts; fi

    # Asked before the first app step, not on the opening screen: the very
    # first thing an owner sees should be what they already have, not a
    # question. Skipped entirely once answered.
    local entry key
    for entry in "${CHECKS[@]}"; do
        key="${entry%%|*}"
        case "$key" in claude-app|chatgpt-app|claude-mcp|chatgpt-mcp) ;; *) continue ;; esac
        case "$(printf '%s' "$entry" | cut -d'|' -f3)" in ok|skipped) continue ;; esac
        read_ai_app_choice >/dev/null
        break
    done

    UNFINISHED=""
    local total=0 number=0 announced_no_key=no

    for entry in "${CHECKS[@]}"; do
        local status; status="$(printf '%s' "$entry" | cut -d'|' -f3)"
        case "$status" in ok|skipped) ;; *) total=$((total + 1)) ;; esac
    done
    [ "$total" -gt 0 ] || return 0

    for entry in "${CHECKS[@]}"; do
        local key status friendly
        key="$(printf '%s' "$entry" | cut -d'|' -f1)"
        friendly="$(printf '%s' "$entry" | cut -d'|' -f2)"
        status="$(printf '%s' "$entry" | cut -d'|' -f3)"
        case "$status" in ok|skipped) continue ;; esac

        number=$((number + 1))

        # Everything on this list needs the Zo key. Without one they cannot
        # work, and running them anyway produced what Tengku saw on Windows:
        # step after step failing with "could not reach your Zo" while the setup
        # marched on, for a man who had just been told to go and sign up.
        #
        # Said once, not ten times. Ten identical failures read as ten separate
        # faults, and the owner concludes the product is broken rather than that
        # it is waiting for them.
        case " $NEEDS_ZO_KEY " in
            *" $key "*)
                case "$(get_zo_token)" in
                    zo_sk_*) ;;
                    *)
                        if [ "$announced_no_key" = 'no' ]; then
                            printf '\n'
                            warn 'Everything from here needs your Zo account key, so the'
                            warn 'rest is waiting for you.'
                            printf '\n'
                            info 'Run this setup again once you have signed up and it will'
                            info 'carry straight on from here.'
                            printf '\n'
                            announced_no_key=yes
                        fi
                        UNFINISHED="$UNFINISHED$friendly"$'\n'
                        continue ;;
                esac ;;
        esac

        show_step_header "$number" "$total" "$friendly"

        # One failure must not abandon the rest of the list.
        if fix_one "$key"; then
            # A step the owner has to finish elsewhere waits here. Charging on
            # to the next one while they are still on their phone is how a
            # setup ends up reporting that nothing worked.
            case " $OWNER_COMPLETES " in
                *" $key "*)
                    wait_for_owner_step "$key" "$friendly" \
                        || UNFINISHED="$UNFINISHED$friendly"$'\n' ;;
            esac
        else
            UNFINISHED="$UNFINISHED$friendly"$'\n'
        fi

        printf '\n'
        show_progress_bar "$number" "$total"
    done
}

# ---------------------------------------------------------------------------
# Start over
# ---------------------------------------------------------------------------

reset_whatsapp_assistant() {
    # Puts the WhatsApp assistant back to before it was set up, so the whole
    # flow can be run again.
    #
    # Two depths, because they cost very different things. Switching replies off
    # and forgetting the answers is instant and free. Unlinking the phone means
    # finding a pairing code again, and is asked for separately.
    #
    # The message history is never touched. It lives in the bridge's own store
    # and can be months of a business's conversations; nothing here deletes it,
    # and nothing here ever should.
    printf '\n'
    title 'Set up how you talk to Zo again'

    # Someone on Telegram or the web has no WhatsApp assistant to undo, and
    # offering to switch off replies they never turned on is a question with no
    # meaning. Forget the choice and let them make it again.
    local channel; channel="$(profile_get talkChannel)"
    case "$channel" in
        ""|whatsapp|whatsapp-self) ;;
        *)
            profile_set talkChannel ''
            info 'Forgotten. Choose "Your AI Personal Assistant" to set it up again.'
            printf '\n'
            info 'Nothing on Zo was changed - your Telegram is still linked.'
            return 0 ;;
    esac

    info 'This switches replies off and forgets who was allowed to talk'
    info 'to it, so you can go through the setup from the top.'
    printf '\n'
    good 'Your messages are kept. Nothing in WhatsApp is deleted.'

    if ! ask_yes_no 'Do that?'; then
        info 'Nothing was changed.'
        return 0
    fi

    printf '\n'
    local unlink='no' remove='no'
    if ask_yes_no 'Also unlink the phone, to test the linking too?'; then
        unlink='yes'
    fi

    # The deepest option, and the slowest, so it is asked for last and only when
    # the one above was already accepted. Unlinking is the common case; tearing
    # the whole thing down and building it again is not.
    if [ "$unlink" = "yes" ]; then
        printf '\n'
        warn 'Or remove it completely and build it fresh next time?'
        info 'That takes a few extra minutes to set up again. Your messages'
        info 'are still kept - nothing is deleted, only set aside.'
        if ask_yes_no 'Remove it completely?'; then remove='yes'; fi
    fi

    printf '\n'
    info 'Putting it back...'
    local answer
    if [ "$remove" = "yes" ]; then
        answer="$(zo_helper --reset-zo --replies --whatsapp-remove)"
    elif [ "$unlink" = "yes" ]; then
        answer="$(zo_helper --reset-zo --replies --whatsapp)"
    else
        answer="$(zo_helper --reset-zo --replies)"
    fi

    case "$answer" in
        *'"ok":true'*) ;;
        *)
            printf '\n'
            bad 'Could not reach your Zo, so nothing on it was changed.'
            return 1 ;;
    esac

    # Only after Zo confirmed. Clearing these first would leave the setup
    # thinking there is nothing to do while the assistant is still answering.
    profile_set talkChannel ''
    profile_set allowedNumbers ''
    [ "$unlink" = "yes" ] && profile_set whatsappPhone ''

    printf '\n'
    good 'Done. Your assistant has stopped replying.'
    if [ "$remove" = "yes" ]; then
        info 'It was removed completely. Setting it up again takes a few'
        info 'minutes longer, because it gets built fresh.'
    elif [ "$unlink" = "yes" ]; then
        info 'The phone is unlinked too, so you will get a fresh pairing code.'
    else
        info 'The phone is still linked, so you can skip straight past that.'
    fi
    printf '\n'
    info 'Choose "Your AI Personal Assistant" on the main screen to start again.'
    return 0
}

reset_ai_employees() {
    # Lets the owner take an AI employee off the books so the hiring can be run
    # again.
    #
    # Each one is named individually rather than offering "delete them all",
    # because a persona may be doing real work by then and a list of names is the
    # only thing that tells the owner which is which.
    title 'Your AI employees'

    info 'Asking Zo who works here...'
    local listed; listed="$(zo_helper --employees)"
    case "$listed" in
        *'"ok":true'*) ;;
        *) bad 'Could not reach Zo to check.'; return 1 ;;
    esac

    local names; names="$(json_field "$listed" '(data.employees || []).join("\n")')"
    if [ -z "$names" ]; then
        info 'Nobody is hired yet, so there is nothing to undo.'
        return 0
    fi

    printf '\n'
    info 'Currently hired:'
    printf '\n'
    local index=0 name
    # A here-string would be simpler and bash 3.2 has one, but a plain loop over
    # the lines keeps this readable and needs no temporary file.
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        index=$((index + 1))
        printf '     %s %d %s  %s%s%s\n' "$C_YELLOW" "$index" "$C_RESET" "$C_WHITE" "$name" "$C_RESET"
    done <<EOF
$names
EOF

    printf '\n'
    info 'Letting one go removes them from Zo. Their work is not deleted.'
    printf '\n      %sWhich one? 1 to %d, or Enter to keep them all > %s' \
        "$C_PURPLE" "$index" "$C_RESET"

    local choice; read -r choice || choice=''
    choice="$(menu_number "$choice")"
    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$index" ]; then
        printf '\n'
        info 'Nobody was let go.'
        return 0
    fi

    local target; target="$(printf '%s\n' "$names" | sed -n "${choice}p")"
    [ -n "$target" ] || { info 'Nobody was let go.'; return 0; }

    printf '\n'
    if ! ask_yes_no "Let $target go?"; then
        info 'Kept.'
        return 0
    fi

    # Their number goes back first, while the note still says they had one.
    #
    # Left behind, the bridge keeps a phone linked to an employee who no longer
    # exists, holds its port, and restarts with the Zo forever. The number is
    # archived rather than deleted, so a mistake here is recoverable.
    local stored member
    stored="$(profile_get employees)"
    local IFS_SAVE="$IFS"; IFS=';'
    for member in $stored; do
        IFS="$IFS_SAVE"
        if [ "$(employee_field "$member" 1)" = "$target" ] &&
           [ "$(employee_field "$member" 3)" = 'whatsapp' ]; then
            info "Taking back $target's number..."
            zo_helper --employee-number-remove "$target" >/dev/null 2>&1 || true
        fi
        IFS=';'
    done
    IFS="$IFS_SAVE"

    info "Removing $target..."
    local answer; answer="$(zo_helper --fire "$target")"
    case "$answer" in
        *'"ok":true'*)
            remove_hired_employee "$target"
            printf '\n'
            good "$target has been removed."
            info 'Choose "Hire AI employees" on the main screen to hire again.'
            return 0 ;;
    esac
    bad 'Could not remove them just now.'
    return 1
}

tool_title_for_formula() {
    # $1 = a Homebrew formula this setup installed.
    case "$1" in
        node)       printf 'Node.js' ;;
        git)        printf 'Git' ;;
        python@*)   printf 'Python' ;;
        *)          printf '%s' "$1" ;;
    esac
}

reset_vimigo_setup() {
    # Puts the Mac back to how it was, at one of three depths.
    #
    # Forget: the Zo key, the remembered answers, and this setup's own entry in
    # each AI app's config. Everything else is left alone. This is what "test it
    # as a new customer would see it" actually needs, and it is quick and
    # harmless.
    #
    # Remove: the above, plus uninstalling the tools THIS SETUP installed. Never
    # anything that was already on the Mac - a computer that had Node before any
    # of this ran is one where removing Node breaks whatever was using it.
    # Nothing here touches Claude Desktop or ChatGPT either, since the owner may
    # well have been using those already.
    title 'Start over'
    info 'This undoes what the setup did, so you can run it again from'
    info 'the beginning. Useful for testing what a new customer sees.'
    printf '\n'
    # Three, not four. "Forget the channel" and "set the WhatsApp assistant up
    # again" were separate options that did the same thing to anyone on
    # WhatsApp, which is nearly everyone - choosing the channel now runs the
    # linking itself, so undoing one is undoing the other.
    #
    # The numbers are worked out, not written down, because two of these options
    # are switchable. A hard-coded list with the middle one hidden offers "1" and
    # "3" and no 2, and - the part that actually bites - leaves 2 still wired to
    # the employee reset, so a key nothing on screen mentions quietly lets an AI
    # employee go.
    #
    # Built before anything is printed, so the sentence above the list can tell
    # the truth about how long the list is.
    #
    # Declared apart from the scalars. macOS ships bash 3.2 and nothing here has
    # ever run on it, so the arrays get the form that is unambiguous everywhere
    # rather than the tidy one-liner.
    local n=0 spoken i
    local actions labels whys
    actions=(); labels=(); whys=()
    if feature_on "$FEATURE_AI_ASSISTANT"; then
        n=$((n + 1))
        actions+=('assistant')
        labels+=('How you talk to Zo -')
        whys+=('your AI Personal Assistant, from the top')
    fi
    if feature_on "$FEATURE_AI_EMPLOYEES"; then
        n=$((n + 1))
        actions+=('employees')
        labels+=('Your AI employees  -')
        whys+=('let one go, so you can hire again')
    fi
    n=$((n + 1))
    actions+=('everything')
    labels+=('Everything         -')
    whys+=('the above, plus the programs this setup')

    # "You can undo just one part, or the whole thing" is a lie on a build where
    # the whole thing is the only part left.
    if [ "$n" -gt 1 ]; then
        info 'You can undo just one part, or the whole thing:'
    else
        info 'There is one thing to undo:'
    fi
    printf '\n'

    i=0
    while [ "$i" -lt "$n" ]; do
        numbered $((i + 1)) "${labels[$i]}" "${whys[$i]}"
        i=$((i + 1))
    done
    printf '                                %sinstalled and your saved Zo key%s\n' "$C_GREY" "$C_RESET"
    printf '\n'
    # The way out, written down.
    #
    # Pressing Enter already left this screen without changing anything, and it
    # never said so. Somebody who opens the menu and wants none of it has no
    # visible way back, and the only exit they can see is closing the window -
    # which loses the whole run.
    printf '        %sEnter  go back, changing nothing%s\n\n' "$C_GREY" "$C_RESET"
    # Read off the list, so the prompt can never name a number the screen above
    # does not show. Three give "1, 2 or 3", two give "1 or 2", one gives "1".
    #
    # The single case is not hypothetical: switch the assistant and employees
    # both off and "Everything" is all that is left. Without it the prompt would
    # read "Choose  or 1".
    if [ "$n" -le 1 ]; then
        spoken='1'
    else
        spoken=''
        i=1
        while [ "$i" -lt "$n" ]; do
            [ -z "$spoken" ] || spoken="$spoken, "
            spoken="$spoken$i"
            i=$((i + 1))
        done
        spoken="$spoken or $n"
    fi
    printf '      %sChoose %s, or Enter to go back > %s' "$C_PURPLE" "$spoken" "$C_RESET"

    local scope chosen
    read -r scope || scope=''
    scope="$(printf '%s' "$scope" | tr -cd '0-9')"

    # Matched as text, never as a number. Bash reads a leading zero as octal, so
    # "08" in an arithmetic test is not 8 but an error message on a screen whose
    # whole job is being calm about mistakes.
    chosen=''
    i=1
    while [ "$i" -le "$n" ]; do
        [ "$scope" = "$i" ] && chosen="${actions[$((i - 1))]}"
        i=$((i + 1))
    done

    case "$chosen" in
        assistant) reset_whatsapp_assistant; return 0 ;;
        employees) reset_ai_employees; return 0 ;;
        everything) ;;
        *) printf '\n'; info 'Nothing was changed.'; return 0 ;;
    esac

    printf '\n'

    # Git is never uninstalled, even when this setup installed it. Too much else
    # reaches for it - other tools, other installers, anything the owner sets up
    # later - and taking it away to tidy up our own work is a poor trade for the
    # few hundred megabytes it saves.
    local ours; ours="$(get_installed_by_us | grep -v '^git$' || true)"

    info 'It will always:'
    printf '\n'
    numbered 1 'Forget your' 'Zo account key'
    numbered 2 'Forget your remembered' 'phone number and Zo address'
    numbered 3 'Remove the Zo entry from' 'Claude Desktop and ChatGPT'
    printf '\n'
    info 'Your own settings in those apps are kept. Only the entry this'
    info 'setup added is taken out.'
    printf '\n'

    local formula
    if [ -n "$ours" ]; then
        info 'It can also uninstall what this setup installed for you:'
        printf '\n'
        printf '%s\n' "$ours" | while IFS= read -r formula; do
            [ -n "$formula" ] && printf '           %s- %s%s\n' \
                "$C_GREY" "$(tool_title_for_formula "$formula")" "$C_RESET"
        done
        printf '\n'
        info 'Anything that was already on this Mac before the setup ran is'
        info 'never touched, and Git is always kept because other programs'
        info 'rely on it.'
    else
        info 'This setup has not installed anything on this Mac, so there'
        info 'is nothing to uninstall.'
    fi
    printf '\n'

    if ! ask_yes_no 'Start over?'; then
        info 'Nothing was changed.'
        return 0
    fi

    local also_uninstall='no'
    if [ -n "$ours" ]; then
        if ask_yes_no 'Also uninstall the tools listed above?'; then
            also_uninstall='yes'
        fi
    fi

    printf '\n'
    info 'Forgetting your Zo account key...'
    remove_zo_token

    info 'Forgetting your remembered answers...'
    [ -f "$PROFILE_FILE" ] && rm -f "$PROFILE_FILE"
    ZO_WORKSPACE_URL=""

    remove_zo_from_configs

    if [ "$also_uninstall" = "yes" ]; then
        load_homebrew_env
        printf '%s\n' "$ours" | while IFS= read -r formula; do
            [ -n "$formula" ] || continue
            info "Uninstalling $(tool_title_for_formula "$formula")..."
            brew uninstall "$formula" >/dev/null 2>&1 || true
        done
    fi

    printf '\n'
    good 'Done. This Mac is back to how it started.'
    info 'Nothing on your Zo was changed: WhatsApp, Google and your plans'
    info 'are all still connected there.'
    printf '\n'
    return 0
}

remove_zo_from_configs() {
    # Takes this setup's own entry out of each AI app's config and leaves every
    # other setting exactly as it was. Backed up first, because the file being
    # edited belongs to the owner and not to us.
    if [ -f "$CLAUDE_CONFIG" ] && node_bin >/dev/null; then
        info 'Removing the Zo entry from Claude Desktop...'
        backup_config "$CLAUDE_CONFIG" >/dev/null
        "$(node_bin)" -e '
            const fs = require("fs");
            const [path, entry] = process.argv.slice(1);
            try {
                const data = JSON.parse(fs.readFileSync(path, "utf8") || "{}");
                if (data && data.mcpServers) {
                    delete data.mcpServers[entry];
                    fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 });
                }
            } catch { process.exit(1); }
        ' "$CLAUDE_CONFIG" "$ZO_MCP_ENTRY" 2>/dev/null \
            || warn 'Could not tidy Claude Desktop, so it was left as it is.'
    fi

    if [ -f "$CODEX_CONFIG" ] && node_bin >/dev/null; then
        info 'Removing the Zo entry from ChatGPT...'
        backup_config "$CODEX_CONFIG" >/dev/null
        "$(node_bin)" -e '
            const fs = require("fs");
            const [path, entry] = process.argv.slice(1);
            const header = "[mcp_servers." + entry + "]";
            const kept = [];
            let inTarget = false;
            for (const line of fs.readFileSync(path, "utf8").split("\n")) {
                const trimmed = line.trim();
                if (trimmed === header) { inTarget = true; continue; }
                if (inTarget && trimmed.startsWith("[") && trimmed.endsWith("]")) inTarget = false;
                if (!inTarget) kept.push(line);
            }
            fs.writeFileSync(path, kept.join("\n").replace(/\s+$/, "") + "\n", { mode: 0o600 });
        ' "$CODEX_CONFIG" "$ZO_MCP_ENTRY" 2>/dev/null \
            || warn 'Could not tidy ChatGPT, so it was left as it is.'
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Sourcing this file loads the functions without starting the menu, which is
# how the acceptance test drives the config writes against throwaway paths.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
fi

if [ "$(uname -s)" != "Darwin" ]; then
    bad 'This script is for macOS. On Windows, run vimigo-setup.ps1 instead.'
    exit 2
fi

# Remembered from an earlier run, so the very first screen can already link to
# the owner's own Zo rather than waiting for a check to rediscover it.
restore_workspace_url

# The console is handed back its own colours on every way out, including a
# ctrl-C, so no later command inherits ours.
trap reset_theme EXIT
apply_theme

if [ "${1:-}" = "--check" ]; then
    collect_checks
    show_checks
    info 'Nothing was changed. Run without --check to fix anything.'
    printf '\n'
    exit 0
fi

if [ "${1:-}" = "--reset" ]; then
    # Start over, which used to be a key on the finished screen and is not any
    # more. It removes what this setup installed, and a destructive action one
    # keypress from "ALL DONE" is a destructive action somebody will reach by
    # accident - on the screen they are most likely to be idly tapping at.
    #
    # Here instead, where it has to be asked for on purpose. The screens it
    # shows are the ones it always showed, including its own confirmations.
    show_logo
    reset_vimigo_setup || true
    printf '\n'
    exit 0
fi

if [ "${1:-}" = "--assistant" ]; then
    # The AI Personal Assistant on its own, for somebody who has already run
    # the setup and wants the thing v1 leaves out.
    #
    # It forces the feature on for this run only. Nothing is written to say so,
    # so the ordinary setup is unchanged the next time they open it - this is a
    # side door, not a switch they have flipped by accident.
    FEATURE_AI_ASSISTANT='on'

    show_logo

    if ! node_bin >/dev/null; then
        bad 'Node.js is missing, and the assistant needs it.'
        info 'Run the main setup first, then come back to this.'
        printf '\n'
        exit 1
    fi
    if node_too_old; then
        bad "Your Node.js is older than $NODE_MIN_MAJOR, and the assistant needs $NODE_MIN_MAJOR or newer."
        info 'Run the main setup first - it will offer to update it.'
        printf '\n'
        exit 1
    fi
    if ! token_looks_valid "$(get_zo_token)"; then
        bad 'No Zo key on this Mac yet.'
        info 'Run the main setup first. It asks for the key, and everything'
        info 'here needs it.'
        printf '\n'
        exit 1
    fi

    # The main setup finishes first. That is the rule, and this checks it
    # rather than trusting it.
    #
    # The assistant is the last thing built and the first thing blamed. It
    # needs the Zo key, the scripts this setup puts on the Zo, and a Zo that
    # answers - so started on a half-finished machine it fails somewhere in the
    # middle, having already asked for a phone number, and what the owner
    # remembers is that the assistant broke.
    #
    # Counted with the assistant switched off, so its own row is not what holds
    # it back.
    info 'Checking the main setup is finished...'
    unfinished="$(main_setup_unfinished)"

    if [ -n "$unfinished" ]; then
        clear_screen
        show_logo
        warn 'The main setup is not finished yet, so this cannot run.'
        printf '\n'
        info 'Still to do:'
        printf '%s' "$unfinished" | while IFS= read -r line; do
            [ -n "$line" ] && printf '         %s• %s%s\n' "$C_YELLOW" "$line" "$C_RESET"
        done
        printf '\n'
        info 'Finish the main setup first, then run this line again.'
        printf '\n'
        exit 1
    fi

    # The scripts that answer for the assistant live on the Zo, and on a Zo
    # that has never had one they are not there yet.
    ensure_zo_scripts

    set_talk_to_zo || true
    printf '\n'
    info 'Run this again any time to change how you reach your assistant.'
    printf '\n'
    exit 0
fi

# The setup checks first, every time, and picks up wherever the Mac actually
# is. Status is never remembered between runs, so it can never be remembered
# wrongly; only what the owner typed is kept.

clear_screen
show_logo
info 'Checking what you already have...'
printf '\n'

while true; do
    collect_checks
    show_checks

    # Hiring is optional, so not hiring is not an unfinished setup.
    #
    # Counted here, "Hire AI employees" is a row that can only be cleared by
    # hiring somebody - so an owner who wants an assistant and no employees
    # never reaches the finished screen, and the menu they need in order to
    # manage what they built never appears. The row stays on the checklist,
    # because it is worth knowing it is there.
    remaining=0
    for entry in "${CHECKS[@]}"; do
        [ "$(printf '%s' "$entry" | cut -d'|' -f1)" = 'zo-employees' ] && continue
        case "$(printf '%s' "$entry" | cut -d'|' -f3)" in
            ok|skipped) ;;
            *) remaining=$((remaining + 1)) ;;
        esac
    done

    if [ "$remaining" -eq 0 ]; then
        show_all_done
        printf '      %s> %s' "$C_PURPLE" "$C_RESET"
        read -r done_choice || break
        done_choice="$(printf '%s' "$done_choice" | tr '[:upper:]' '[:lower:]')"
        case "$done_choice" in
            q|quit|'') break ;;
        esac
        if handle_main_choice "$done_choice"; then
            clear_screen; show_banner
            info '  Checking again...'; printf '\n'
            continue
        fi
        # Anything else on a finished setup is not a request to redo the lot -
        # it is a mistyped key, and quietly reinstalling everything is not what
        # somebody who pressed the wrong letter meant.
        continue
    fi

    printf '      %s%d thing(s) left. This setup can do them for you.%s\n\n' \
        "$C_GREY" "$remaining" "$C_RESET"
    # Picking single rows out of order used to be offered and is not any more.
    # The list is in the order it is for a reason - skills, then access, then
    # where you talk to it, then hiring - and someone choosing row 14 first gets
    # an assistant with nothing behind it and concludes the product does not
    # work. Enter does the lot, in order.
    #
    # The letters are for afterwards: changing something already set up, not
    # building it in a different sequence.
    show_main_options

    printf '      %s> %s' "$C_PURPLE" "$C_RESET"
    read -r choice || break
    choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"

    case "$choice" in
        q|quit) printf '\n'; info 'Nothing was changed. Bye.'; printf '\n'; break ;;
    esac

    if handle_main_choice "$choice"; then
        clear_screen; show_banner
        info '  Checking again...'; printf '\n'
        continue
    fi

    clear_screen
    show_banner

    # Anything else means "do it all", in order.
    fix_everything

    printf '\n'
    if [ -n "$UNFINISHED" ]; then
        warn '      Some things still need you:'
        printf '%s' "$UNFINISHED" | while IFS= read -r line; do
            [ -n "$line" ] && printf '         %s• %s%s\n' "$C_YELLOW" "$line" "$C_RESET"
        done
        printf '\n'
        info '      Several of these finish on a website. Run this setup again'
        info '      afterwards and it will pick up exactly where it left off.'
        printf '\n'
    fi

    printf '      Press Enter to check again '; read -r _ || true
    clear_screen
    show_banner
    info '  Checking again...'
    printf '\n'
done
