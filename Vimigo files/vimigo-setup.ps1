#requires -Version 5.1
<#
.SYNOPSIS
    Vimigo AI Setup - Windows.

.DESCRIPTION
    Gets this computer ready to use Zo with Claude Desktop and ChatGPT.

    Nothing is installed until you ask for it. The script opens on a status
    screen showing what is already here and what is missing, and every action
    re-checks afterwards instead of trusting an installer's exit code.

    Safe to run as many times as you like. Anything already installed is left
    exactly as it is, and existing app configuration is backed up before it is
    changed and never overwritten wholesale.

.EXAMPLE
    pwsh -File vimigo-setup.ps1
    Opens the status menu.

.EXAMPLE
    pwsh -File vimigo-setup.ps1 -Check
    Prints the status once and exits. Changes nothing. Good for a support call.
#>
[CmdletBinding()]
param(
    # Print status and exit without offering to change anything.
    [switch]$Check,

    # Leave the console's own colours alone instead of applying the Vimigo
    # theme. Useful if a terminal renders it badly.
    [switch]$NoTheme
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The screen draws box and block characters. Without this the console renders
# them as mojibake on a machine whose code page is not UTF-8, which is most of
# them.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# The logo uses the real brand colours, which need 24-bit ANSI. Windows 10 and
# later support it once virtual terminal processing is on; where it is not, the
# escapes would print as literal noise, so the logo falls back to named colours.
$script:UseTrueColour = $false
try {
    $script:UseTrueColour = $Host.UI.SupportsVirtualTerminal -or
        ($null -ne $env:WT_SESSION) -or
        ($PSVersionTable.PSVersion.Major -ge 6)
} catch {
    $script:UseTrueColour = $false
}

# A soft dark blue-grey page rather than pure black. Black with bright text is
# high-contrast and glaring to sit in front of; a lifted, slightly blue
# background is calmer without losing the legibility of light-on-dark.
#
# Only attempted where 24-bit colour already works, since a terminal that
# ignores the request keeps whatever it had, and the text colours below suit
# any dark background rather than one exact shade.
#
# Also gated on stdout actually being a terminal. Redirected to a file or a
# pipe - a support call capturing the screen, for instance - the escapes are
# not interpreted and appear as literal ]111]110 rubbish in the transcript.
$script:ThemedConsole = $script:UseTrueColour -and -not $NoTheme -and
    -not [Console]::IsOutputRedirected

# Semantic names, so a call site says what the text IS rather than picking a
# colour that only happens to suit one background.
$script:Ink = @{
    Body = 'Gray'; Muted = 'DarkGray'; Strong = 'White'
    Good = 'Green'; Warn = 'Yellow'; Bad = 'Red'
}

function Set-VimigoTheme {
    if (-not $script:ThemedConsole) { return }
    # OSC 11 sets the window background, OSC 10 the default text colour.
    # Windows Terminal and other VT-capable consoles honour both; anything that
    # does not simply ignores them, which is why this is gated above.
    $bell = [char]7
    Write-Host "$([char]27)]11;#1E232C$bell" -NoNewline
    Write-Host "$([char]27)]10;#DCE2EC$bell" -NoNewline
}

function Reset-Theme {
    if (-not $script:ThemedConsole) { return }
    # Hand the console back the way it was found, rather than leaving every
    # later command sitting on our colours.
    $bell = [char]7
    Write-Host "$([char]27)]111$bell" -NoNewline
    Write-Host "$([char]27)]110$bell" -NoNewline
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:ZoMcpUrl = 'https://api.zo.computer/mcp'
$script:ZoMcpEntryName = 'zo'
$script:McpRemotePackage = 'mcp-remote@latest'

# Where the two AI apps keep their MCP configuration.
#
# Claude Desktop ships two ways and they do not share a path. Installed
# normally it uses %APPDATA%\Claude. Installed as a packaged app - which is what
# winget's Anthropic.Claude actually delivers - Windows gives it a private
# AppData underneath its package folder, and the copy in the real %APPDATA% is
# invisible to it.
#
# Writing to the wrong one is silent: the file is created, the entry is there,
# every check passes, and the app carries on knowing nothing about Zo. This
# machine had exactly that until it was caught.
function Get-ClaudeConfigPath {
    $package = Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($package) {
        $packaged = Join-Path $env:LOCALAPPDATA `
            "Packages\$($package.PackageFamilyName)\LocalCache\Roaming\Claude\claude_desktop_config.json"
        # Only once the app has run and made its folder. Before that there is
        # nothing to merge with and the plain path is the safer guess.
        if (Test-Path -LiteralPath (Split-Path -Parent $packaged)) { return $packaged }
    }
    return (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
}

# Deliberately empty, and resolved fresh at every use instead.
#
# Resolving once here happened before Claude Desktop was installed, so it always
# took the "app has not run yet" branch above and froze on the %APPDATA% guess.
# Later in the same run the setup installs Claude, opens it, waits for a
# sign-in - and then writes Zo into the path it decided on minutes earlier,
# which by then is the wrong one. Silently: the write succeeds, the check reads
# back its own file, the row goes green, and the app never sees Zo.
#
# That is the exact fault the comment above describes, reintroduced by caching
# the answer. The acceptance suite sets this variable to point at a sandbox, so
# it stays as the override.
$script:ClaudeConfigPath = ''
$script:CodexConfigPath = Join-Path $env:USERPROFILE '.codex\config.toml'

function Resolve-ClaudeConfigPath {
    if ($script:ClaudeConfigPath) { return $script:ClaudeConfigPath }
    return (Get-ClaudeConfigPath)
}

function Write-TextFile {
    <#
        Writes a file as plain UTF-8, with no byte order mark.

        Set-Content -Encoding UTF8 means "UTF-8 with a BOM" in the PowerShell
        that ships with Windows, and "without" in PowerShell 7 - so the same
        line produced different bytes depending on which one happened to run,
        and the shipped one is the common case.

        These are other programs' files: Claude's settings and ChatGPT's TOML.
        A leading BOM is invisible here - Get-Content strips it on the way back
        in, so the setup's own verification passes either way - and whether the
        far end tolerates it is not something this setup gets to decide. So it
        writes exactly what those programs expect and leaves nothing to chance.
    #>
    param([string]$Path, [string]$Text)

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

# Our own notes: which browser-based steps the owner has confirmed finishing.
# These live on Zo's side and cannot be proven from this computer, so we record
# them as "you confirmed" and label them that way on screen.
$script:StatePath = Join-Path $env:LOCALAPPDATA 'Vimigo\setup-state.json'

# Pages the owner is sent to. A browser opens only when they pick an action.
$script:ZoHomeUrl = 'https://zo.computer'
$script:ChatGptDownloadUrl = 'https://openai.com/chatgpt/download/'

# Vimigo's Zo referral link. Anyone signing up as part of this setup goes
# through it, so new accounts are attributed correctly.
$script:ZoSignUpUrl = 'https://zo-computer.cello.so/0qDXmlEF6Hn'

# The settings page lives on the owner's own subdomain, which is discovered from
# Zo during verification. Until a key exists there is nothing to discover from,
# so the generic host is the honest fallback.
function Get-ZoSettingsUrl {
    param([string]$WorkspaceUrl)
    if ($WorkspaceUrl) { return "$WorkspaceUrl/?t=settings&s=advanced" }
    return 'https://zo.computer'
}

function Get-ZoIntegrationsUrl {
    param([string]$WorkspaceUrl)
    if ($WorkspaceUrl) { return "$WorkspaceUrl/?t=settings&s=integrations" }
    return 'https://zo.computer'
}

function Get-ZoAiSettingsUrl {
    # The AI page, where providers are connected and default models chosen.
    # None of that can be done from here - Zo exposes no way to change it - so
    # the setup shows the page and the steps instead of pretending otherwise.
    param([string]$WorkspaceUrl)
    if ($WorkspaceUrl) { return "$WorkspaceUrl/?t=settings&s=ai" }
    return 'https://zo.computer'
}

function Get-ZoPersonasUrl {
    <#
        The personas page, where employees are reviewed and edited.

        Given an id, the link opens that one employee rather than the list.
        Landing on a list of eight and having to work out which one was just
        created is a small puzzle, and the owner did not ask for a puzzle.
    #>
    param([string]$WorkspaceUrl, [string]$PersonaId)

    if (-not $WorkspaceUrl) { return 'https://zo.computer' }
    $page = "$WorkspaceUrl/?t=settings&s=ai&d=personas"
    if ($PersonaId) { return "${page}:$PersonaId" }
    return $page
}

function Get-ZoAiSettingsUrl {
    # The AI page, which is a different tab from the Access Key page. Sending
    # the owner to the wrong one and asking them to find Providers is the sort
    # of small wrongness that makes a setup feel unreliable.
    param([string]$WorkspaceUrl)
    if ($WorkspaceUrl) { return "$WorkspaceUrl/?t=settings&s=ai" }
    return 'https://zo.computer'
}

# The owner's own Zo address, e.g. https://acme.zo.computer. Discovered from
# Zo's handshake the first time a key works, then remembered, so every later
# run links straight to their workspace instead of a generic page they have to
# navigate. Declared here because some paths read it before the first check
# runs, and StrictMode throws on a variable that was never assigned.
$script:ZoWorkspaceUrl = ''

# Whether a WhatsApp number is linked. Drives the "add another" option, which
# only makes sense once there is a first one.
$script:WhatsAppLinked = $false

# ---------------------------------------------------------------------------
# Remembered answers
# ---------------------------------------------------------------------------
# Only what the owner TYPED is remembered - their Zo address, the WhatsApp
# number - so a second run does not ask for it again.
#
# What is remembered is never what is DONE. Status is re-detected every run,
# always. A file saying "WhatsApp: connected" keeps saying it after the phone
# unlinks the device, and the owner then stares at a green tick wondering why
# nothing works. Detection cannot go stale; a note can.
#
# The Zo key is deliberately NOT kept here. It stays in Windows Credential
# Manager with a copy encrypted to this Windows account, so another user of the
# same computer cannot read it. Moving it into a plain text file next to this
# one would undo that.

function Get-ProfilePath { Join-Path (Split-Path -Parent $script:StatePath) 'profile.json' }

function Get-Profile {
    $path = Get-ProfilePath
    if (-not (Test-Path -LiteralPath $path)) { return @{} }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        $table = @{}
        foreach ($property in $parsed.PSObject.Properties) { $table[$property.Name] = $property.Value }
        return $table
    } catch {
        # A damaged file just means asking again, which is a small cost.
        return @{}
    }
}

function Set-ProfileValue {
    param([string]$Name, $Value)
    $profileData = Get-Profile
    $profileData[$Name] = $Value
    $directory = Split-Path -Parent $script:StatePath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    ($profileData | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Get-ProfilePath) -Encoding UTF8
}

function Write-SetupLog {
    <#
        A one-line note for a support call. Never shown on screen.

        Redacted on the way in rather than on the way out: an error message can
        carry the account key in it, and a log file is exactly the thing that
        gets emailed to support. Failing to write the log is not worth an error
        of its own.
    #>
    param([string]$Message)

    try {
        $safe = [regex]::Replace($Message, 'zo_sk_[A-Za-z0-9_\-]+', '<account key removed>')
        $directory = Split-Path -Parent $script:StatePath
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -LiteralPath (Join-Path $directory 'setup.log') -Value "$stamp  $safe" -Encoding UTF8
    } catch { }
}

function Invoke-Guarded {
    <#
        Runs a step and refuses to let it end the setup.

        Anything reached from a menu goes through here. A bug in one screen -
        and there have been several - used to close the window on a red
        PowerShell error, which to the owner is indistinguishable from the
        setup being broken beyond repair. Now the screen says one plain
        sentence and the menu comes back, so everything else still works.
    #>
    param([scriptblock]$Action, [string]$Whats = 'that')

    try { return (& $Action) }
    catch {
        Write-Host ''
        Write-Bad "Something went wrong with $Whats, so it was left alone."
        Write-Info 'Nothing on your computer was changed by that. You can try'
        Write-Info 'again, carry on with the rest, or contact Vimigo support.'
        # Kept for a support call, never shown: the owner has no use for it and
        # a stack trace on screen reads as a broken product.
        #
        # With the line and the statement, because "Argument types do not
        # match" on its own is a needle in four thousand lines - which is
        # exactly how long the first one took to find.
        $where = ''
        try {
            $where = " [line $($_.InvocationInfo.ScriptLineNumber): $(($_.InvocationInfo.Line).Trim())]"
        } catch { }
        Write-SetupLog "guarded failure in $Whats : $($_.Exception.Message)$where"
        return $false
    }
}

function Get-OwnerName {
    <#
        The owner's first name, for the greeting. Remembered once known.

        Guessed rather than demanded, because being asked your own name by a
        program you just installed feels like paperwork. Windows is a poor
        source - the account here is "offic" with a display name of
        "vimigoTech Use" - so git's configured name is tried first, then the
        account name, and anything that reads like a company or a machine is
        rejected rather than used.

        Returns an empty string when nothing believable turns up, and the
        greeting simply leaves the name out.
    #>
    $known = (Get-Profile)['ownerName']
    if ($known) { return $known }

    # Claude first, then ChatGPT, then git. Claude records the name the owner
    # gave when they signed up, which is the one they would recognise; ChatGPT
    # often holds a company login instead; git is whatever they typed when they
    # set it up, if they ever did. Nothing found means no name, and the
    # greeting simply does without.
    $candidates = @()

    # Claude keeps a display name against the signed-in account.
    #
    # Read with a regular expression rather than a JSON parser, and that is not
    # laziness. The file legitimately holds keys differing only by case, which
    # the built-in parser refuses outright; -AsHashtable copes, and does not
    # exist in the PowerShell that ships with Windows. Since the whole prize
    # here is a first name for a greeting, a narrow match beats a parser that
    # works on some machines and not others.
    try {
        $claudePath = Join-Path $env:USERPROFILE '.claude.json'
        if (Test-Path -LiteralPath $claudePath) {
            $raw = Get-Content -LiteralPath $claudePath -Raw -ErrorAction Stop
            $match = [regex]::Match($raw, '"oauthAccount"\s*:\s*\{[^}]*?"displayName"\s*:\s*"([^"]+)"')
            if ($match.Success) { $candidates += [string]$match.Groups[1].Value }
        }
    } catch { }

    # The ChatGPT account, which carries a name claim. Often a company account
    # rather than a person, so it sits below Claude.
    try {
        $authPath = Join-Path $env:USERPROFILE '.codex\auth.json'
        if (Test-Path -LiteralPath $authPath) {
            $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $jwt = $auth.tokens.id_token
            if ($jwt) {
                $segment = ($jwt -split '\.')[1].Replace('-', '+').Replace('_', '/')
                while ($segment.Length % 4) { $segment += '=' }
                $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($segment)) |
                    ConvertFrom-Json -ErrorAction Stop
                foreach ($claim in @('given_name', 'name')) {
                    if (Test-ObjectHasProperty -Object $payload -Name $claim) {
                        $candidates += [string]$payload.$claim
                    }
                }
            }
        }
    } catch { }

    # Git last, and only if the owner ever configured it.
    #
    # Wrapped, and that is not belt and braces. Calling a program that is not on
    # PATH raises a terminating error, and `2>$null` cannot suppress it because
    # the process never starts, so there is no stderr to redirect. Git is one of
    # the three tools this setup exists to install, so a new laptop has none -
    # and this runs from Show-Logo, before the checklist is drawn. The result
    # was the splash screen, then the failure message, then nothing, every
    # single run, for exactly the people the setup is for.
    try {
        if (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue) {
            $gitName = (& git config --global user.name 2>$null | Out-String).Trim()
            if ($gitName) { $candidates += $gitName }
        }
    } catch { }

    foreach ($candidate in $candidates) {
        # Just the first word: "Tengku Syafiq - Legion Laptop" is a person plus
        # the machine they set git up on, and only the first part is a name.
        #
        # Forced to a string first. A source can hand back an array, and then
        # the split returns arrays too and .Length is not what it appears.
        $text = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $first = [string](@($text -split '[\s\-_,.]+' | Where-Object { $_ })[0])
        if ([string]::IsNullOrWhiteSpace($first)) { continue }
        if ($first.Length -lt 2 -or $first.Length -gt 20) { continue }
        if ($first -notmatch '^[\p{L}]+$') { continue }
        # Words that are obviously not somebody's first name.
        if ($first -match '^(user|admin|owner|test|vimigo|vimigotech|pc|desktop|laptop|home|office|offic)$') { continue }
        return (Get-Culture).TextInfo.ToTitleCase($first.ToLower())
    }
    return ''
}

function Get-Greeting {
    # Never asked for. Three places are looked at and, if none of them knows,
    # the greeting simply carries no name rather than making the owner supply
    # one for the sake of a nicety.
    $name = (Get-Profile)['ownerName']
    if (-not $name) {
        $name = Get-OwnerName
        if ($name) { Set-ProfileValue -Name 'ownerName' -Value $name }
    }
    if (-not $name -or $name -eq '-') { return 'Welcome back' }
    return "Welcome back, $name"
}

function Add-InstalledByUs {
    <#
        Records that this setup installed something, so a later reset can undo
        its own work and nothing else.

        The distinction is the whole point. A machine that already had Node
        before any of this ran is a machine where removing Node breaks whatever
        was using it. Uninstalling on the basis of "the setup manages this" and
        not "the setup installed this" is how a reset takes somebody's work
        with it.
    #>
    param([string]$Name)

    $existing = @((Get-Profile)['installedByUs'] -split ',' | Where-Object { $_ })
    if ($existing -contains $Name) { return }
    Set-ProfileValue -Name 'installedByUs' -Value (($existing + $Name) -join ',')
}

function Get-InstalledByUs {
    return @((Get-Profile)['installedByUs'] -split ',' | Where-Object { $_ })
}

function Restore-ZoWorkspaceUrl {
    $saved = (Get-Profile)['workspaceUrl']
    # Validated on the way in: a tampered file must not become a link the setup
    # opens in the owner's browser.
    if ($saved -and $saved -match '^https://[a-z0-9-]+\.zo\.computer$') {
        $script:ZoWorkspaceUrl = $saved
    }
}

function Save-ZoWorkspaceUrl {
    param([string]$Url)
    if ($Url -eq $script:ZoWorkspaceUrl) { return }
    $script:ZoWorkspaceUrl = $Url
    Set-ProfileValue -Name 'workspaceUrl' -Value $Url
}

# The Zo skills worth having on every customer's Zo, with the names exactly as
# they appear in Zo's own Skills catalogue.
#
# Note the absence of a "zo-" prefix. That prefix is the publisher tag shown
# beside a skill, not part of its name, and searching for it finds nothing -
# which is how six of these were briefly written off as non-existent.
$script:ZoSkills = [ordered]@{
    'morning-briefing'        = 'a daily briefing, at a time you choose'
    'important-email-digest'  = 'the emails that actually matter, summarised'
    'research-topic'          = 'research anything properly and write it up'
    'automate-something'      = 'turn a repeated job into an automation'
    'generate-pdf'            = 'turn notes into a proper PDF'
    'extract-text-from-image' = 'read text out of photos, scans and PDFs'
    'organize-workspace'      = 'tidy scattered files into sensible folders'
    'web-scraper'             = 'pull information off websites'
    'skill-creator'           = 'teach your Zo something new'
}

# The AI employees a business can hire, one per department, in roughly the
# order a small Malaysian business needs them.
#
# Each is a Zo persona: a name and a prompt describing the job. Permissions are
# left wide open on purpose - the owner can narrow any of them later on their
# own personas page, and a new employee that cannot do anything is a worse
# first impression than one that can do too much.
#
# Every prompt names the exact things this one must never decide on its own: a
# price in RM, a date, a discount, someone's pay. A hired employee knows a job
# title and nothing about the business, and the staff and customers on the
# other end believe whatever it tells them - so the damage is not a wrong
# answer, it is a wrong answer nobody knew was given. "Let me check with the
# boss" is in all of them for the same reason: asking costs a minute, guessing
# costs a customer.
#
# The last sentence of each is there because the owner has never opened a
# terminal. An employee that answers "check the log" has ended the
# conversation.
$script:AiEmployees = [ordered]@{
    'assistant' = @{
        Title  = 'AI Personal Assistant'
        For    = 'your diary, mail, reminders, anything'
        Prompt = @'
You are the owner's own assistant. You help with their diary, their email,
their files, reminders, and anything else they ask. Keep answers short and
plain. Reply in the language they write in, English, Malay or a mix. Only
people the owner has approved can reach you; tell nobody else anything about
the owner or the business. Never send a message, book anything or spend money
for them until they have seen it and said yes. If you are not sure, ask the
owner rather than guess. If someone else asks, say let me check with the boss.
The owner has no technical background, so never ask them to run a command,
open a file or read a log.
'@
    }
    'admin' = @{
        Title  = 'AI Admin'
        For    = 'forms, filing, appointments, renewals'
        Prompt = @'
You keep the business paperwork in order. Forms, filing, appointments, staff
records and licence renewals. When something is missing, say what is missing.
Never invent a name, a date, a reference number or an amount to fill a gap.
Never sign anything, submit a form, move or cancel an appointment, or give out
someone's personal details until the owner has read it and said yes. If a
letter or bill looks important, pass it to the owner rather than act on it. If
the owner has not told you, say let me check with the boss. The owner has no
technical background, so never ask them to run a command, open a file or read
a log.
'@
    }
    'sales' = @{
        Title  = 'AI Sales'
        For    = 'quotes, follow-ups, people who went quiet'
        Prompt = @'
You help the business sell. You answer people asking about buying, mostly on
WhatsApp, follow up with the ones who went quiet, and track who is still
waiting. Be warm, never pushy, and reply in the language they used. Customers
believe what you tell them, so never quote a price in RM, offer a discount,
promise a delivery date, or say something is in stock unless the owner has
given you that exact figure or date. Never take payment or agree terms for the
business. When you do not know, say let me check with the boss. The owner has
no technical background, so never ask them to run a command, open a file or
read a log.
'@
    }
    'customer-service' = @{
        Title  = 'AI Customer Service'
        For    = 'customer questions, orders, complaints'
        Prompt = @'
You answer the business's customers, mostly on WhatsApp. Be patient and
polite, keep replies short, and answer in the language they wrote in, Malay,
English or a mix. You only know what the owner has taught you. Never promise a
refund, a replacement, a discount, a delivery date or any amount in RM, and
never give out a staff member's name or number. If a customer is angry or
asking about money, stay kind and pass them to the owner. Saying you do not
know is better than guessing, so say let me check with the boss. The owner has
no technical background, so never ask them to run a command, open a file or
read a log.
'@
    }
    'accountant' = @{
        Title  = 'AI Accountant'
        For    = 'invoices, receipts, spending, who owes money'
        Prompt = @'
You keep the money side in order. Invoices, receipts, spending, and who still
owes what. Every figure is in RM and must be exact. Never round, never
estimate, and never fill in a number you cannot see on a document; if
something is missing or does not add up, say so. Never send an invoice or
payment reminder, share a bank account number, agree to a discount or
instalment plan, or tell anyone what a customer or staff member owes or earns,
until the owner says yes. If you are unsure, say let me check with the boss.
The owner has no technical background, so never ask them to run a command,
open a file or read a log.
'@
    }
    'marketing' = @{
        Title  = 'AI Marketing'
        For    = 'posts, captions, promotions'
        Prompt = @'
You help the business get noticed. Write WhatsApp broadcasts, Facebook and
Instagram captions, and promotion ideas in the owner's own voice. Sound like a
real person, not a brochure. Everything you write is a draft: never post, send
or publish anything anywhere yourself. Never invent a price in RM, a discount,
a free gift, a halal or health claim, an award or a review, and never use a
customer's name, photo or words without the owner confirming they agreed. If
you are unsure whether something is true, leave it out and say let me check
with the boss. The owner has no technical background, so never ask them to run
a command, open a file or read a log.
'@
    }
    'hr' = @{
        Title  = 'AI HR'
        For    = 'leave, shifts, new joiners, staff questions'
        Prompt = @'
You help with the staff. Leave, shifts, new joiners, EPF and SOCSO questions,
and the small things people ask every day. Reply in Malay when staff write in
Malay. Be fair, be kind, and treat every message as private. Never approve or
reject leave, never confirm a shift change, and never discuss anyone's pay,
warning, complaint, medical certificate or job being at risk; all of that goes
to the owner. Never repeat what one person told you to another. If you do not
know the rule, say let me check with the boss. The owner has no technical
background, so never ask them to run a command, open a file or read a log.
'@
    }
    'operations' = @{
        Title  = 'AI Operations'
        For    = 'stock, suppliers, deliveries, schedules'
        Prompt = @'
You keep the day running. Stock, suppliers, deliveries and who is doing what.
Tell the owner early when something is running low, running late or about to
clash. Never place an order, agree a supplier's price in RM, confirm a
delivery time to a customer, change someone's shift, or tell one supplier
anything about another, without the owner saying yes first. Write to suppliers
and drivers in the language they use, usually short Malay or English. If you
do not know what is in stock or when something arrives, say let me check with
the boss. The owner has no technical background, so never ask them to run a
command, open a file or read a log.
'@
    }
}

# The rules for "Someone else" - the last option on the hire screen, where the
# owner types the job in their own words.
#
# Left to itself, a job typed as "answer my customers about tuition fees" is a
# persona with no limits at all: nothing stops it quoting a fee, promising a
# slot or naming a child. These are the same limits the eight above carry,
# joined to whatever the owner typed, so choosing "Someone else" is not the one
# way to end up with an employee that can say anything.
#
# It reads as "the job described above", so it goes AFTER their words, not
# before - otherwise it points at an empty space.
$script:AiEmployeeCustomRules = @'
The job the owner described above is your job. Do that job and nothing else.
You are talking to real staff and customers who believe what you say. Keep
replies short and answer in the language they used, Malay, English or a mix.
You only know what the owner has taught you. Never quote or accept money in
RM, promise a date or a discount, send or post anything outside the business,
or say anything about a named person, unless the owner has agreed first. When
you do not know, say let me check with the boss. The owner has no technical
background, so never ask them to run a command, open a file or read a log.
'@

# The Google apps worth putting on a customer's checklist, in the order they
# matter. Keys match the app_slug Zo uses.
$script:GoogleApps = [ordered]@{
    'gmail'           = 'Gmail'
    'google_calendar' = 'Calendar'
    'google_drive'    = 'Drive'
    'google_sheets'   = 'Sheets'
}

# Tools we manage, in install order. Node is first because the Zo MCP bridge
# runs through npx: without Node, nothing downstream can work.
$script:ManagedTools = @(
    [pscustomobject]@{
        Key       = 'node'
        Title     = 'Node.js'
        WingetId  = 'OpenJS.NodeJS.LTS'
        Command   = 'node'
        VersionArgs = @('--version')
        Why       = 'runs the Zo connection for both AI apps'
    }
    [pscustomobject]@{
        Key       = 'git'
        Title     = 'Git'
        WingetId  = 'Git.Git'
        Command   = 'git'
        VersionArgs = @('--version')
        Why       = 'lets the AI apps read and write code projects'
    }
    [pscustomobject]@{
        Key       = 'python'
        Title     = 'Python'
        WingetId  = 'Python.Python.3.13'
        Command   = 'python'
        VersionArgs = @('--version')
        Why       = 'runs data and automation tools'
    }
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# The brand palette, reused everywhere so the screen reads as one thing. A
# terminal full of undifferentiated grey text is what makes people nervous of
# it; colour is doing real work here, not decoration.
# The brand colours, straight from the logo. The purple is lifted a little from
# the mark's #6A5BA6, which is too close to the background to read as text.
$script:Palette = @{
    Teal   = "$([char]27)[38;2;108;197;217m"
    Yellow = "$([char]27)[38;2;252;211;74m"
    Coral  = "$([char]27)[38;2;236;97;82m"
    Purple = "$([char]27)[38;2;150;135;210m"
    Reset  = "$([char]27)[0m"
}

function Write-Brand {
    <#
        Writes text in a brand colour, falling back to the nearest named
        console colour where 24-bit is unavailable.
    #>
    param(
        [string]$Text,
        [ValidateSet('Teal', 'Yellow', 'Coral', 'Purple')][string]$Colour,
        [switch]$NoNewline
    )
    if ($script:UseTrueColour) {
        $rendered = "$($script:Palette[$Colour])$Text$($script:Palette.Reset)"
        if ($NoNewline) { Write-Host $rendered -NoNewline } else { Write-Host $rendered }
        return
    }
    $fallback = @{ Teal = 'Cyan'; Yellow = 'Yellow'; Coral = 'Red'; Purple = 'Magenta' }[$Colour]
    if ($NoNewline) { Write-Host $Text -ForegroundColor $fallback -NoNewline }
    else { Write-Host $Text -ForegroundColor $fallback }
}

# Everything indents to the same column as the checklist, so a step does not
# look like a different program from the screen that launched it.
function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Brand -Text '    ┏━ ' -Colour Purple -NoNewline
    Write-Brand -Text $Text -Colour Teal -NoNewline
    Write-Brand -Text (' ' + ('━' * [Math]::Max(4, 42 - $Text.Length))) -Colour Purple
    Write-Host ''
}

function Write-NumberedStep {
    <#
        One instruction, with the number in its own colour so a list of them
        scans as a list rather than a paragraph.
    #>
    param([int]$Number, [string]$Text, [string]$Highlight)

    Write-Host '        ' -NoNewline
    Write-Brand -Text " $Number " -Colour Yellow -NoNewline
    Write-Host '  ' -NoNewline
    Write-Host $Text -ForegroundColor $script:Ink.Strong -NoNewline
    if ($Highlight) {
        Write-Host ' ' -NoNewline
        Write-Brand -Text $Highlight -Colour Teal
    } else {
        Write-Host ''
    }
}

function Write-Info { param([string]$Text) Write-Host "      $Text" -ForegroundColor $script:Ink.Body }
function Write-Good { param([string]$Text) Write-Host "      $Text" -ForegroundColor $script:Ink.Good }
function Write-Warn { param([string]$Text) Write-Host "      $Text" -ForegroundColor $script:Ink.Warn }
function Write-Bad  { param([string]$Text) Write-Host "      $Text" -ForegroundColor $script:Ink.Bad }

# ---------------------------------------------------------------------------
# Small state file for the steps that happen on Zo's website
# ---------------------------------------------------------------------------

function Get-ZoVerification {
    <#
        Asks the owner's Zo what is actually connected, rather than keeping a
        note of what they said. Zo is the only thing that knows, so WhatsApp and
        the Google apps are reported from Zo's own answer.

        Returns $null when the question could not be asked at all. That is a
        different situation from "not connected" and the screen says so, because
        telling somebody their working integration is broken is worse than
        admitting the check could not run.
    #>
    param([string]$Token)

    if (-not (Test-ZoTokenShape -Token $Token)) { return $null }

    $helper = Join-Path $PSScriptRoot 'zo-verify.js'
    if (-not (Test-Path -LiteralPath $helper)) { return $null }

    $node = Get-Command -Name 'node' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $node) { return $null }

    # The longest wait in the whole check, and the one with nothing of its own
    # to show. The spinner overwrites the progress bar line, which is fine:
    # both are wiped by the status screen a moment later.
    $outputFile = Join-Path ([IO.Path]::GetTempPath()) ("vimigo-zo-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $null = Invoke-WithSpinner -Message 'asking your Zo...' `
            -FilePath $node.Source -Arguments @($helper, $Token) -OutputFile $outputFile

        if (-not (Test-Path -LiteralPath $outputFile)) { return $null }
        $raw = Get-Content -LiteralPath $outputFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $parsed.ok) { return $null }
        return $parsed
    } catch {
        return $null
    } finally {
        Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# The Zo token
# ---------------------------------------------------------------------------
# The token is stored in Windows Credential Manager, not in a file of ours.
# It does still end up inside each AI app's own config file, because that is
# the only shape those apps accept today. The status screen says so plainly.

$script:CredentialTarget = 'VimigoSetup:ZoToken'

function Get-ZoToken {
    $output = & cmdkey.exe /list:$script:CredentialTarget 2>&1 | Out-String
    if ($output -notmatch [regex]::Escape($script:CredentialTarget)) { return $null }

    # cmdkey cannot read a password back. Keep our own protected copy, encrypted
    # to this Windows user account so no other account on the machine can read it.
    $tokenPath = Join-Path (Split-Path -Parent $script:StatePath) 'zo-token.bin'
    if (-not (Test-Path -LiteralPath $tokenPath)) { return $null }
    try {
        # Trimmed, and that is load-bearing. Set-Content appends a newline,
        # Get-Content -Raw keeps it, and ConvertTo-SecureString rejects the
        # result outright. Without this the key never reads back, so every step
        # below it reports "needs your Zo key first" forever - including on the
        # screen straight after the owner pasted a perfectly good key.
        $encrypted = (Get-Content -LiteralPath $tokenPath -Raw -ErrorAction Stop).Trim()
        $secure = $encrypted | ConvertTo-SecureString -ErrorAction Stop
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch {
        return $null
    }
}

function Save-ZoToken {
    param([Parameter(Mandatory)][string]$Token)

    $directory = Split-Path -Parent $script:StatePath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $tokenPath = Join-Path $directory 'zo-token.bin'

    $secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
    $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $tokenPath -Encoding ASCII

    # A marker in Credential Manager so the token is discoverable and removable
    # through the normal Windows UI.
    & cmdkey.exe /generic:$script:CredentialTarget /user:zo /pass:$Token | Out-Null
}

function Remove-ZoToken {
    & cmdkey.exe /delete:$script:CredentialTarget 2>&1 | Out-Null
    $tokenPath = Join-Path (Split-Path -Parent $script:StatePath) 'zo-token.bin'
    if (Test-Path -LiteralPath $tokenPath) { Remove-Item -LiteralPath $tokenPath -Force }
}

function Test-ZoTokenShape {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    return $Token.Trim().StartsWith('zo_sk_')
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

function Get-CommandVersion {
    param([string]$Command, [string[]]$VersionArgs)

    $resolved = Get-Command -Name $Command -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $resolved) { return $null }

    try {
        $raw = & $resolved.Source @VersionArgs 2>&1 | Out-String
    } catch {
        # Present on PATH but not runnable. Treat as missing so the fix action
        # can reinstall it, rather than reporting a broken tool as healthy.
        return $null
    }
    $match = [regex]::Match($raw, '(\d+\.\d+(\.\d+)?)')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)
    $output = & winget.exe list --id $PackageId --exact --accept-source-agreements 2>&1 | Out-String
    return $output -match [regex]::Escape($PackageId)
}

function Test-ClaudeDesktopInstalled {
    if (Test-WingetPackageInstalled -PackageId 'Anthropic.Claude') { return $true }
    # Fall back to the install location, in case it arrived outside winget.
    $direct = Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'
    return (Test-Path -LiteralPath $direct)
}

function Test-ChatGptDesktopInstalled {
    # The Windows ChatGPT desktop app ships as the OpenAI.Codex Store package.
    if (Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue) { return $true }

    # Deliberately NOT the presence of ~/.codex/config.toml, which was the
    # earlier test. That file belongs to the Codex command-line tool and exists
    # on plenty of machines with no desktop app at all, so it reported the app
    # as installed and then wrote a Zo connection into something the owner
    # could not open.
    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\ChatGPT\ChatGPT.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\@openaichatgpt-desktop\ChatGPT.exe')
    )) {
        if (Test-Path -LiteralPath $candidate) { return $true }
    }
    return $false
}

function Find-LocalWhatsAppInstall {
    <#
        The WhatsApp bridge belongs on Zo and never on this computer: a laptop
        that sleeps drops the WhatsApp connection, and a local build drags in a
        C compiler and a service manager for no benefit.

        An earlier setup guide installed it locally, so machines set up that way
        still have one. This reports what it finds. It never deletes anything:
        the store folder holds the linked WhatsApp session, and throwing that
        away costs a re-pair.
    #>
    $found = New-Object System.Collections.Generic.List[string]

    foreach ($path in @(
        (Join-Path $env:USERPROFILE 'Dev\whatsapp-mcp-go'),
        (Join-Path $env:USERPROFILE 'whatsapp-mcp-go'),
        (Join-Path $env:USERPROFILE 'Documents\whatsapp-mcp-go'),
        (Join-Path $env:USERPROFILE 'whatsapp-mcp'),
        'C:\Dev\whatsapp-mcp-go',
        'D:\Dev\whatsapp-mcp-go'
    )) {
        if (Test-Path -LiteralPath $path) { $found.Add($path) }
    }

    if (Get-Service -Name 'WhatsAppBridge' -ErrorAction SilentlyContinue) {
        $found.Add('the WhatsAppBridge Windows service')
    }

    return $found
}

function Show-LocalWhatsAppInstall {
    Write-Title 'WhatsApp is installed on this computer'

    $found = @(Find-LocalWhatsAppInstall)
    if ($found.Count -eq 0) {
        Write-Good 'Nothing found. WhatsApp belongs on Zo, and that is where it is.'
        return $true
    }

    Write-Info 'WhatsApp should run on your Zo, not on this computer. A laptop'
    Write-Info 'that sleeps or shuts down drops the WhatsApp connection.'
    Write-Host ''
    Write-Info 'Found here:'
    foreach ($item in $found) { Write-Host "      $item" -ForegroundColor $script:Ink.Warn }
    Write-Host ''
    Write-Warn 'Nothing has been deleted.'
    Write-Info 'The store folder holds your linked WhatsApp session, and deleting'
    Write-Info 'it means pairing your phone again. Set WhatsApp up on Zo first,'
    Write-Info 'confirm it works, and only then remove the copy here.'
    return $false
}

function Test-HcsServicesPresent {
    <#
        Claude Desktop's shell sandbox needs the Windows Host Compute Services.
        They ship with the container/virtualization features, which are off by
        default, and their absence shows up as "Missing HCS services: HNS,
        vmcompute, vfpext" with no hint about what to do next.
    #>
    foreach ($service in @('vmcompute', 'hns')) {
        if (-not (Get-Service -Name $service -ErrorAction SilentlyContinue)) { return $false }
    }
    return $true
}

function Repair-HcsServices {
    Write-Title 'Fixing Claude Desktop background features'

    if (Test-HcsServicesPresent) {
        Write-Good 'Already fixed. Nothing to do.'
        return $true
    }

    Write-Info 'Claude Desktop needs two Windows features that are switched off'
    Write-Info 'on this computer. Without them its tools cannot run.'
    Write-Host ''
    Write-Warn 'Windows will ask for permission, and the computer must restart afterwards.'
    Write-Host ''

    if (-not (Read-YesNo -Question 'Turn those Windows features on now?' -YesLabel 'Yes, turn them on' -NoLabel 'Skip this for now')) {
        Write-Info 'Skipped. Claude Desktop will keep showing the sandbox error.'
        return $false
    }

    # One elevated run for all three, so the owner sees a single prompt rather
    # than three. Each feature is independent: Containers is unavailable on
    # Windows Home, and the first two alone usually resolve it there.
    $features = @('VirtualMachinePlatform', 'HypervisorPlatform', 'Containers')
    $commands = ($features | ForEach-Object {
        "dism.exe /online /enable-feature /featurename:$_ /all /norestart"
    }) -join '; '

    Write-Info 'Asking Windows for permission. This takes a few minutes.'
    try {
        $process = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList '/c', $commands `
            -Verb RunAs -Wait -PassThru -ErrorAction Stop
    } catch {
        Write-Bad 'Permission was refused, so nothing was changed.'
        return $false
    }

    # DISM reports 3010 for "worked, restart required", and Containers returns a
    # failure on Windows Home which is expected rather than fatal. The features
    # only actually appear after the restart, so neither code proves anything.
    Write-Host ''
    Write-Good 'Windows has been asked to turn the features on.'
    Write-Warn 'You must restart this computer for it to take effect.'
    Write-Info "(installer reported code $($process.ExitCode))"
    Write-Host ''

    if (Read-YesNo -Question 'Restart now?' -YesLabel 'Restart now' -NoLabel 'I will restart later') {
        Write-Info 'Restarting in 10 seconds. Save anything open.'
        Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '10', '/c', `
            '"Vimigo setup: finishing Claude Desktop setup"' -WindowStyle Hidden
        return $true
    }

    Write-Info 'No problem. Restart when you are ready, then run this setup again.'
    return $false
}

function Test-ChatGptSignedIn {
    <#
        ChatGPT writes its tokens to ~/.codex/auth.json once signed in, so this
        is a real answer rather than an inference.

        Installing an app and signing into it are different things, and the
        difference matters here: the Zo connection is written into a config the
        app only reads for a signed-in user, so an unsigned app looks perfectly
        installed and has no Zo in it.
    #>
    $authPath = Join-Path $env:USERPROFILE '.codex\auth.json'
    if (-not (Test-Path -LiteralPath $authPath)) { return $false }
    try {
        $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json -ErrorAction Stop
        # Either a signed-in session or an API key counts as usable.
        return ((Test-ObjectHasProperty -Object $auth -Name 'tokens') -or
                (Test-ObjectHasProperty -Object $auth -Name 'OPENAI_API_KEY'))
    } catch {
        return $false
    }
}

function Test-ClaudeDesktopOpened {
    <#
        Whether Claude Desktop has ever been run, which is not the same as
        whether it is signed in - the session itself is encrypted and cannot be
        read from here. An app that has never been opened has no session
        storage beside its config, and that is worth saying, because the owner
        has to open it anyway before any of this works.
    #>
    # Beside whichever config the app really uses, not a fixed guess. Looking
    # in %APPDATA% on a packaged install reports "never opened" for an app in
    # daily use, because its data lives under its package folder instead.
    $dataDir = Split-Path -Parent (Get-ClaudeConfigPath)
    if (-not (Test-Path -LiteralPath $dataDir)) { return $false }

    foreach ($marker in @('Local Storage', 'Session Storage', 'Cookies', 'Preferences', 'Local State')) {
        if (Test-Path -LiteralPath (Join-Path $dataDir $marker)) { return $true }
    }
    return $false
}

function Test-ObjectHasProperty {
    <#
        Whether a parsed-JSON object carries a named property.

        Indexing PSObject.Properties, never reading .Name off it. On an object
        with no properties at all - a config file holding {}, or a machine where
        Claude Desktop has never been configured - the collection is empty, and
        under Set-StrictMode -Version Latest merely reading .Name off it throws
        "The property 'Name' cannot be found on this object".

        Wrapping the result in @() does not help: the throw happens while
        evaluating .Name, before anything can wrap it. That is the ordinary
        first-run path, not an edge case.
    #>
    param($Object, [string]$Name)

    if ($null -eq $Object) { return $false }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Test-ClaudeMcpConfigured {
    if (-not (Test-Path -LiteralPath (Resolve-ClaudeConfigPath))) { return $false }
    try {
        $raw = Get-Content -LiteralPath (Resolve-ClaudeConfigPath) -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $false }
        $document = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-ObjectHasProperty -Object $document -Name 'mcpServers')) { return $false }
        return (Test-ObjectHasProperty -Object $document.mcpServers -Name $script:ZoMcpEntryName)
    } catch {
        return $false
    }
}

function Test-CodexMcpConfigured {
    if (-not (Test-Path -LiteralPath $script:CodexConfigPath)) { return $false }
    $raw = Get-Content -LiteralPath $script:CodexConfigPath -Raw -ErrorAction SilentlyContinue
    if (-not $raw) { return $false }
    return $raw -match "(?m)^\s*\[mcp_servers\.$([regex]::Escape($script:ZoMcpEntryName))\]"
}

# ---------------------------------------------------------------------------
# The status screen
# ---------------------------------------------------------------------------

function New-Check {
    param(
        [string]$Key,
        [string]$Title,
        [ValidateSet('ok', 'missing', 'needs-you')][string]$Status,
        [string]$Detail,
        [string]$Note,
        # Sub-items shown indented beneath the row, for a step that is really
        # several separate permissions, such as the Google apps.
        [object[]]$Children
    )
    [pscustomobject]@{
        Key      = $Key
        Title    = $Title
        Status   = $Status
        Detail   = $Detail
        Note     = $Note
        Children = $Children
    }
}

# One line that fills as the machine is checked, redrawn in place. Checking
# takes several seconds - winget is slow and asking Zo is a network round trip -
# and a screen that says "Checking..." then sits still reads as hung. A bar that
# visibly grows says the opposite. Wiped by the status screen afterwards.
$script:CheckStage = 0
$script:CheckSpinner = @('|', '/', '-', '\')

function Get-CheckStageCount {
    # The three tools, plus the key, both apps, the app configs, and Zo.
    return ($script:ManagedTools.Count + 5)
}

function Write-Checking {
    param([string]$What)

    $script:CheckStage++
    $total = Get-CheckStageCount
    $width = 22
    $filled = [Math]::Min($width, [int][Math]::Round(($script:CheckStage / $total) * $width))
    $bar = ('█' * $filled) + ('░' * ($width - $filled))
    $spin = $script:CheckSpinner[($script:CheckStage - 1) % $script:CheckSpinner.Count]

    if ([Console]::IsOutputRedirected) {
        # No cursor to move, so carriage returns would pile the whole thing onto
        # one unreadable line in a captured transcript.
        Write-Host "        $What"
        return
    }

    # Padded to the same width the spinner uses, so whichever wrote the line
    # last leaves nothing of the other behind.
    Write-Host "`r      " -NoNewline
    Write-Brand -Text $spin -Colour Yellow -NoNewline
    Write-Host ' ' -NoNewline
    Write-Brand -Text $bar -Colour Teal -NoNewline
    Write-Host ("  " + $What.PadRight(45)) -ForegroundColor $script:Ink.Muted -NoNewline
}

function ConvertTo-CommandLineArgument {
    <#
        Wraps one argument so it survives the trip to another program intact.

        Windows hands a program a single command line and lets its runtime
        split it again, following rules that are easy to get subtly wrong: a
        quote has to be escaped, and a backslash only means "escape" when it
        precedes a quote, so runs of backslashes double only in that position.
        Node follows those rules exactly, so this has to as well.
    #>
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    # Nothing that needs protecting, and not empty, goes as-is.
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }

    # Any backslashes immediately before a quote are doubled, then the quote is
    # escaped. Backslashes anywhere else are literal and left alone.
    $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
    # And a run at the very end, because the closing quote follows it.
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
    return '"' + $escaped + '"'
}

function Invoke-WithSpinner {
    <#
        Runs an external command while a marker turns beside a message, so a
        wait that has no output of its own - winget downloading, a network call
        to Zo - still looks alive.

        Animating needs something to animate against, so the work runs as a
        separate process and the spin happens while waiting for it to exit.
        Returns the exit code; output goes to the file given.
    #>
    param(
        [string]$Message,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$OutputFile
    )

    $frames = @('◐', '◓', '◑', '◒')
    $errorFile = "$OutputFile.err"

    # Quoted here, one argument at a time.
    #
    # Start-Process joins an array with spaces and quotes nothing, so any
    # argument containing a space arrives at the far end as several arguments.
    # That is not theoretical: every AI employee was created with a job
    # description of "You" - the first word of "You are the owner's personal
    # assistant" - because the rest of the sentence became separate arguments
    # and was dropped. The employees looked hired and knew nothing.
    $quoted = @($Arguments | ForEach-Object { ConvertTo-CommandLineArgument -Value $_ })

    $process = Start-Process -FilePath $FilePath -ArgumentList $quoted `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $OutputFile -RedirectStandardError $errorFile

    if ([Console]::IsOutputRedirected) {
        $process.WaitForExit()
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
        return $process.ExitCode
    }

    # Padded to a fixed width, because this shares a line with the progress bar
    # written just before it. A shorter message leaves the tail of the bar
    # sitting on the right and the two read as one broken line.
    $lineWidth = 78
    $frame = 0
    while (-not $process.HasExited) {
        Write-Host "`r      " -NoNewline
        Write-Brand -Text $frames[$frame % $frames.Count] -Colour Teal -NoNewline
        Write-Host ("  " + $Message.PadRight($lineWidth - 9)) -ForegroundColor $script:Ink.Muted -NoNewline
        $frame++
        Start-Sleep -Milliseconds 120
    }

    # Wipe the whole line so the result prints on a clean row.
    Write-Host ("`r" + (' ' * $lineWidth) + "`r") -NoNewline
    Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    return $process.ExitCode
}

function Complete-Checking {
    # Leaves the bar full rather than stopped partway, then moves off the line
    # so whatever prints next does not land on top of it.
    if (-not [Console]::IsOutputRedirected) {
        Write-Host "`r      " -NoNewline
        Write-Brand -Text ' ' -Colour Yellow -NoNewline
        Write-Host ' ' -NoNewline
        Write-Brand -Text ('█' * 22) -Colour Teal -NoNewline
        Write-Host ('  ' + 'done'.PadRight(42)) -ForegroundColor $script:Ink.Muted
    }
    $script:CheckStage = 0
}

function Get-AllChecks {
    $checks = New-Object System.Collections.Generic.List[object]
    $script:CheckStage = 0
    Write-Checking 'your Zo account key'
    $token = Get-ZoToken

    foreach ($tool in $script:ManagedTools) {
        Write-Checking $tool.Title
        $version = Get-CommandVersion -Command $tool.Command -VersionArgs $tool.VersionArgs
        if ($version) {
            $checks.Add((New-Check -Key $tool.Key -Title $tool.Title -Status 'ok' -Detail "version $version"))
        } else {
            $checks.Add((New-Check -Key $tool.Key -Title $tool.Title -Status 'missing' -Detail 'not installed' -Note $tool.Why))
        }
    }

    # Installed and signed in are different things, and only the second one is
    # any use: the Zo connection goes into a config the app reads for a
    # signed-in user, so an app nobody has opened looks perfectly installed and
    # has no Zo in it.
    Write-Checking 'Claude Desktop'
    if (-not (Test-ClaudeDesktopInstalled)) {
        $checks.Add((New-Check -Key 'claude-app' -Title 'Claude Desktop' -Status 'missing' -Detail 'not installed'))
    } elseif (Test-ClaudeDesktopOpened) {
        $checks.Add((New-Check -Key 'claude-app' -Title 'Claude Desktop' -Status 'ok' -Detail 'installed'))
    } else {
        $checks.Add((New-Check -Key 'claude-app' -Title 'Claude Desktop' -Status 'needs-you' `
            -Detail 'never opened yet' -Note 'open it once and sign in'))
    }

    Write-Checking 'ChatGPT Desktop'
    if (-not (Test-ChatGptDesktopInstalled)) {
        $checks.Add((New-Check -Key 'chatgpt-app' -Title 'ChatGPT Desktop' -Status 'missing' -Detail 'not installed'))
    } elseif (Test-ChatGptSignedIn) {
        $checks.Add((New-Check -Key 'chatgpt-app' -Title 'ChatGPT Desktop' -Status 'ok' -Detail 'signed in'))
    } else {
        $checks.Add((New-Check -Key 'chatgpt-app' -Title 'ChatGPT Desktop' -Status 'needs-you' `
            -Detail 'installed, not signed in' -Note 'open it and sign in'))
    }

    # Only worth showing once Claude Desktop is actually here: on a machine
    # without it, the missing features are not a problem to solve.
    if (Test-ClaudeDesktopInstalled) {
        if (Test-HcsServicesPresent) {
            $checks.Add((New-Check -Key 'claude-hcs' -Title 'Claude Desktop features' -Status 'ok' -Detail 'working'))
        } else {
            $checks.Add((New-Check -Key 'claude-hcs' -Title 'Claude Desktop features' -Status 'missing' -Detail 'switched off in Windows' -Note 'fixing this needs permission and a restart'))
        }
    }

    if (Test-ZoTokenShape -Token $token) {
        $checks.Add((New-Check -Key 'zo-token' -Title 'Zo account key' -Status 'ok' -Detail 'saved on this computer'))
    } else {
        $checks.Add((New-Check -Key 'zo-token' -Title 'Zo account key' -Status 'needs-you' -Detail 'not entered yet' -Note 'everything below needs this first'))
    }

    Write-Checking 'the Zo connection inside each app'
    if (Test-ClaudeMcpConfigured) {
        $checks.Add((New-Check -Key 'claude-mcp' -Title 'Zo inside Claude Desktop' -Status 'ok' -Detail 'connected'))
    } else {
        $checks.Add((New-Check -Key 'claude-mcp' -Title 'Zo inside Claude Desktop' -Status 'missing' -Detail 'not connected'))
    }

    if (Test-CodexMcpConfigured) {
        $checks.Add((New-Check -Key 'chatgpt-mcp' -Title 'Zo inside ChatGPT' -Status 'ok' -Detail 'connected'))
    } else {
        $checks.Add((New-Check -Key 'chatgpt-mcp' -Title 'Zo inside ChatGPT' -Status 'missing' -Detail 'not connected'))
    }

    # Only shown on a machine that has one. On a clean machine this is not a
    # task the owner should have to read past.
    # @() is load-bearing: PowerShell unrolls an empty collection returned from
    # a function into $null, and .Count on $null throws under StrictMode.
    $strayWhatsApp = @(Find-LocalWhatsAppInstall)
    if ($strayWhatsApp.Count -gt 0) {
        $checks.Add((New-Check -Key 'local-whatsapp' -Title 'WhatsApp on this computer' -Status 'needs-you' `
            -Detail 'should be on Zo instead' `
            -Note 'set it up on Zo first, then remove the copy here'))
    }

    # These live on Zo, so Zo is asked directly. One call answers all of them.
    Write-Checking 'your Zo (this one needs the internet)'
    $zo = Get-ZoVerification -Token $token
    if ($zo -and $zo.workspaceUrl) { Save-ZoWorkspaceUrl -Url $zo.workspaceUrl }

    if (-not $zo) {
        # Everything that lives on Zo is unknowable from here without a key.
        # The rows still appear so the owner can see what is coming, and each
        # says why it cannot be checked rather than guessing at an answer.
        $why = if (Test-ZoTokenShape -Token $token) { 'could not reach Zo to check' } else { 'needs your Zo key first' }
        # Same order, and the same names, as when a key is present. A list that
        # rearranges itself once the key is pasted looks like a different
        # program.
        foreach ($row in @(
            @{ Key = 'zo-claude-code'; Title = 'Claude plan on Zo' },
            @{ Key = 'zo-codex';       Title = 'ChatGPT plan on Zo' },
            @{ Key = 'zo-skills';      Title = 'Basic skills for your Zo' },
            @{ Key = 'zo-google';      Title = 'Basic integrations for your Zo' },
            @{ Key = 'talk-to-zo';     Title = 'Your AI Personal Assistant' },
            @{ Key = 'zo-employees';   Title = 'Hire AI employees' }
        )) {
            $checks.Add((New-Check -Key $row.Key -Title $row.Title -Status 'needs-you' -Detail $why))
        }
        return $checks
    }

    # Signing Zo in to an existing Claude or ChatGPT subscription means the
    # owner's Zo uses a plan they already pay for, instead of billing per use.
    foreach ($provider in @(
        @{ Key = 'zo-claude-code'; Title = 'Claude plan on Zo'; Field = 'claude' },
        @{ Key = 'zo-codex';       Title = 'ChatGPT plan on Zo'; Field = 'codex' }
    )) {
        $signedIn = $zo.aiProviders -and $zo.aiProviders.($provider.Field) -and
            $zo.aiProviders.($provider.Field).loggedIn -eq $true
        # "signed in" is all this can honestly say. Whether Zo has the provider
        # switched on and set as a default lives in Zo's web settings, which
        # are held on its servers and are not readable from here. Calling that
        # "done" would hide a plan being paid for and never used.
        if ($signedIn) {
            $checks.Add((New-Check -Key $provider.Key -Title $provider.Title -Status 'ok' `
                -Detail 'signed in - finish on the Zo website'))
        } else {
            $checks.Add((New-Check -Key $provider.Key -Title $provider.Title -Status 'needs-you' `
                -Detail 'not signed in' -Note 'optional, but saves paying per use'))
        }
    }

    # Order from here on follows how a business actually gets going: teach it
    # skills, give it access, decide where you talk to it, then hire. Anything
    # that needs the one before it comes after it.

    # Read off Zo's own folders, never from a note of what the owner said. An
    # owner who removed a skill last week has to show as not having it.
    $skills = if (Test-ObjectHasProperty $zo 'skills') { $zo.skills } else { $null }
    $wanted = $script:ZoSkills.Keys.Count
    if ($null -eq $skills) {
        $checks.Add((New-Check -Key 'zo-skills' -Title 'Basic skills for your Zo' -Status 'needs-you' `
            -Detail 'could not tell' -Note 'briefings, PDFs, reading photos, and more'))
    } elseif (@($skills.missing).Count -eq 0) {
        $checks.Add((New-Check -Key 'zo-skills' -Title 'Basic skills for your Zo' -Status 'ok' `
            -Detail "all $wanted installed"))
    } else {
        # Counted, not ticked. "2 of 9" tells an owner something a single cross
        # does not, and it is the same reason Google is reported that way.
        $have = @($skills.installed).Count
        $checks.Add((New-Check -Key 'zo-skills' -Title 'Basic skills for your Zo' -Status 'needs-you' `
            -Detail "$have of $wanted installed" -Note 'briefings, PDFs, reading photos, and more'))
    }

    $script:WhatsAppLinked = ($zo.whatsapp.connected -eq $true)

    # Straight after skills, because it is the same kind of thing: something the
    # Zo gains rather than something the owner has to do.
    $brain = if (Test-ObjectHasProperty $zo 'secondBrain') { $zo.secondBrain } else { $null }
    if ($null -eq $brain) {
        $checks.Add((New-Check -Key 'zo-brain' -Title 'Your company second brain' -Status 'needs-you' `
            -Detail 'not set up yet' -Note 'somewhere to keep what your Zo learns'))
    } elseif ($brain.folders -gt 0) {
        $detail = if ($brain.notes -gt 0) { "$($brain.notes) notes kept" } else { 'ready and empty' }
        $checks.Add((New-Check -Key 'zo-brain' -Title 'Your company second brain' -Status 'ok' -Detail $detail))
    } else {
        $checks.Add((New-Check -Key 'zo-brain' -Title 'Your company second brain' -Status 'needs-you' `
            -Detail 'not set up yet' -Note 'somewhere to keep what your Zo learns'))
    }

    # Google is several apps, each authorised separately. They are listed one by
    # one under a single row: a lone tick would hide that Calendar was never
    # authorised, and four top-level rows would crowd the screen for what is
    # really one decision.
    $connected = 0
    $children = New-Object System.Collections.Generic.List[object]
    foreach ($slug in $script:GoogleApps.Keys) {
        $entry = $zo.integrations.PSObject.Properties |
            Where-Object { $_.Name -eq $slug } | Select-Object -First 1
        $isOn = $entry -and $entry.Value.connected -eq $true
        if ($isOn) { $connected++ }
        $children.Add([pscustomobject]@{
            Title  = $script:GoogleApps[$slug]
            Status = if ($isOn) { 'ok' } else { 'needs-you' }
        })
    }

    $total = $script:GoogleApps.Count
    $checks.Add((New-Check -Key 'zo-google' -Title 'Basic integrations for your Zo' `
        -Status $(if ($connected -eq $total) { 'ok' } else { 'needs-you' }) `
        -Detail "$connected of $total connected" `
        -Children $children))

    # The row that decides whether any of the rest gets used. A fully set up
    # machine with no answer here is a customer who never opens it again. It
    # comes after skills and access on purpose: the first thing they do is talk
    # to it, and by then it should already be able to do something.
    $talkChannel = (Get-Profile)['talkChannel']
    $channelLabel = switch ($talkChannel) {
        'whatsapp'      { 'WhatsApp' }
        'whatsapp-self' { 'WhatsApp, your own chat' }
        'telegram'      { 'Telegram' }
        'web'           { 'on the web' }
        default         { '' }
    }
    # Named for what it is, not for what it does. With AI employees on the same
    # screen, "how you talk to it" left people working out which assistant was
    # meant. The full phrase is "How you talk to Zo - your AI Personal
    # Assistant"; the title column has room for the short one, and the whole
    # one lives on the screens that can hold it.
    #
    # One row, not two. "WhatsApp on Zo" sat separately and said the same thing
    # twice: for anyone on WhatsApp - nearly everyone - their assistant IS the
    # WhatsApp number, so a linked number and a set-up assistant were the same
    # fact reported in two places, able to disagree with each other.
    $answering = (Test-ObjectHasProperty $zo.whatsapp 'answering') -and ($zo.whatsapp.answering -eq $true)
    $onWhatsApp = $talkChannel -like 'whatsapp*'

    if (-not $channelLabel) {
        $checks.Add((New-Check -Key 'talk-to-zo' -Title 'Your AI Personal Assistant' -Status 'needs-you' `
            -Detail 'not set up yet' -Note 'without this there is nowhere to type'))
    } elseif (-not $onWhatsApp) {
        # Telegram and the web are finished the moment they are chosen; there
        # is nothing on Zo to link or switch on.
        $checks.Add((New-Check -Key 'talk-to-zo' -Title 'Your AI Personal Assistant' -Status 'ok' -Detail $channelLabel))
    } elseif ($zo.whatsapp.connected -eq $true -and $answering) {
        $checks.Add((New-Check -Key 'talk-to-zo' -Title 'Your AI Personal Assistant' -Status 'ok' `
            -Detail "$channelLabel, answering"))
    } elseif ($zo.whatsapp.connected -eq $true) {
        # Linked is not finished. Every install before the responder existed
        # sat exactly here: connected, collecting messages, replying to nobody,
        # and reported as done.
        $checks.Add((New-Check -Key 'talk-to-zo' -Title 'Your AI Personal Assistant' -Status 'needs-you' `
            -Detail 'linked, but it does not reply yet' -Note 'one more step and it answers'))
    } elseif ($null -eq $zo.whatsapp.connected) {
        $checks.Add((New-Check -Key 'talk-to-zo' -Title 'Your AI Personal Assistant' -Status 'needs-you' `
            -Detail 'could not tell'))
    } else {
        $detail = if ($zo.whatsapp.detail) { $zo.whatsapp.detail } else { 'not linked yet' }
        $checks.Add((New-Check -Key 'talk-to-zo' -Title 'Your AI Personal Assistant' -Status 'needs-you' `
            -Detail $detail -Note 'without this there is nowhere to type'))
    }

    # Last, because an employee is only worth hiring once the Zo they work for
    # can actually do something. Read from Zo, so somebody removed on the
    # website disappears from here too.
    $employees = if (Test-ObjectHasProperty $zo 'employees') { $zo.employees } else { $null }
    if ($null -eq $employees) {
        $checks.Add((New-Check -Key 'zo-employees' -Title 'Hire AI employees' -Status 'needs-you' `
            -Detail 'could not tell' -Note 'sales, admin, accounts, and more'))
    } elseif (@($employees).Count -gt 0) {
        # Named, not counted. "1 hired" is no use to somebody trying to work
        # out whether the one they made last week is still there - and an AI
        # employee nobody can account for is worse than none, because it is
        # answering somebody.
        $count = @($employees).Count
        # Plain array, for the same reason as Sync-HiredEmployees: 5.1 refuses
        # @() around a generic List and this list is passed straight into one.
        $team = @()
        $known = @(Get-HiredEmployees)
        foreach ($who in @($employees)) {
            $note = $known | Where-Object { $_.name -eq $who } | Select-Object -First 1
            $label = if ($note -and $note.title) { "$who  -  $($note.title)" } else { [string]$who }
            $team += [pscustomobject]@{ Title = $label; Status = 'ok' }
        }
        $checks.Add((New-Check -Key 'zo-employees' -Title 'Hire AI employees' -Status 'ok' `
            -Detail "$count working for you" -Children $team))
    } else {
        $checks.Add((New-Check -Key 'zo-employees' -Title 'Hire AI employees' -Status 'needs-you' `
            -Detail 'nobody hired yet' -Note 'sales, admin, accounts, and more'))
    }

    return $checks
}

function Clear-Screen {
    # Clearing fails when there is no real console (a support call capturing
    # output to a file, for example). A cluttered screen is not worth an error.
    try { Clear-Host } catch { Write-Host '' }
}

function Show-Logo {
    <#
        The Vimigo mark, four cascading bands, cut down from the full artwork.
        The original is 100 columns by 35 rows: it overflows an 80-column
        console and fills the whole window, which is the crowding this screen
        was redesigned to remove. This keeps the shape at a size that leaves
        room for the actual setup.

        Shown on the opening splash and on completion only. The working
        checklist stays plain so the owner reads the rows, not the decoration.
    #>
    # The circle uses a bullet rather than a letter. 'o' reads as text sitting
    # beside the mark instead of as part of it, and the whole point of the
    # circle is that it is a shape.
    $bands = @(
        '                         --         ==  ',
        '              ...       -----     ======',
        '••••••      .......   --------   =======',
        '•••••••   ........   -------   =======  ',
        '•••••••  .......   -------   ========   ',
        ' ••••  ........  --------  ========     ',
        '     ........   -------   =======       ',
        '     ......   -------   ========        ',
        '       ...  --------  ========          ',
        '           -------   =======            ',
        '           -----   ========             ',
        '             --   =======               ',
        '                =======                 ',
        '                 =====                  ',
        '                   =                    '
    )

    # The real brand colours, as 24-bit ANSI. The console's sixteen named
    # colours have nothing close to the teal or the coral, so the logo would
    # come out looking like a different mark entirely.
    $escape = [char]27
    $rgb = @{
        '•' = "$escape[38;2;108;197;217m"   # circle, teal
        '.' = "$escape[38;2;252;211;74m"    # yellow band
        '-' = "$escape[38;2;236;97;82m"     # coral band
        '=' = "$escape[38;2;106;91;166m"    # purple band
    }
    # Named colours for a console without VT processing, where the escapes
    # would otherwise print as literal garbage across the screen.
    $named = @{ '•' = 'Cyan'; '.' = 'Yellow'; '-' = 'Red'; '=' = 'DarkMagenta' }
    $reset = "$escape[0m"

    Write-Host ''
    foreach ($line in $bands) {
        Write-Host '    ' -NoNewline
        foreach ($character in $line.ToCharArray()) {
            $key = [string]$character
            if (-not $rgb.ContainsKey($key)) { Write-Host ' ' -NoNewline; continue }
            if ($script:UseTrueColour) {
                Write-Host "$($rgb[$key])$character$reset" -NoNewline
            } else {
                Write-Host $character -ForegroundColor $named[$key] -NoNewline
            }
        }
        Write-Host ''
    }
    Write-Host ''
    Write-Host '              V I M I G O   A I   S E T U P' -ForegroundColor $script:Ink.Strong
    Write-Host ''
    Write-Host "              $(Get-Greeting)" -ForegroundColor $script:Ink.Body
    Write-Host ''
}

function Show-Banner {
    Write-Host ''
    Write-Brand -Text '    ╭────────────────────────────────────────────────╮' -Colour Purple
    Write-Brand -Text '    │                                                │' -Colour Purple
    Write-Brand -Text '    │' -Colour Purple -NoNewline
    Write-Brand -Text '         V I M I G O   A I   S E T U P          ' -Colour Teal -NoNewline
    Write-Brand -Text '│' -Colour Purple
    Write-Brand -Text '    │                                                │' -Colour Purple
    Write-Brand -Text '    │' -Colour Purple -NoNewline
    Write-Host '    Zo, Claude and ChatGPT on this computer     ' -ForegroundColor $script:Ink.Body -NoNewline
    Write-Brand -Text '│' -Colour Purple
    Write-Brand -Text '    │                                                │' -Colour Purple
    Write-Brand -Text '    ╰────────────────────────────────────────────────╯' -Colour Purple
    Write-Host ''
}

function Show-ProgressBar {
    param([int]$Done, [int]$Total, [int]$Width = 26)

    if ($Total -le 0) { return }
    $filled = [int][Math]::Round(($Done / $Total) * $Width)
    $bar = ('█' * $filled) + ('░' * ($Width - $filled))
    $colour = if ($Done -eq $Total) { 'Green' } else { 'Cyan' }

    Write-Host '     ' -NoNewline
    Write-Host $bar -ForegroundColor $colour -NoNewline
    Write-Host ("  {0} of {1} done" -f $Done, $Total) -ForegroundColor $script:Ink.Muted
}

function Show-Checks {
    param([object[]]$Checks)

    Clear-Screen
    Show-Logo

    foreach ($check in $Checks) {
        switch ($check.Status) {
            'ok'        { $mark = '✓'; $colour = 'Green' }
            'needs-you' { $mark = '●'; $colour = 'Yellow' }
            default     { $mark = '●'; $colour = 'Yellow' }
        }

        # Padded to 32, and a space guaranteed after it. "Basic integrations
        # for your Zo" is 30 characters, and at 28 the detail was welded onto
        # the end of it: "...for your Zo4 of 4 connected".
        Write-Host "      $mark  " -ForegroundColor $colour -NoNewline
        Write-Host ($check.Title.PadRight(32) + ' ') -ForegroundColor $(if ($check.Status -eq 'ok') { 'Gray' } else { 'White' }) -NoNewline
        Write-Host $check.Detail -ForegroundColor $script:Ink.Muted

        foreach ($child in @($check.Children)) {
            if (-not $child) { continue }
            $childMark = if ($child.Status -eq 'ok') { '✓' } else { '·' }
            $childColour = if ($child.Status -eq 'ok') { 'DarkGreen' } else { 'DarkGray' }
            Write-Host "           $childMark  " -ForegroundColor $childColour -NoNewline
            Write-Host $child.Title -ForegroundColor $script:Ink.Muted
        }
    }

    $done = @($Checks | Where-Object { $_.Status -eq 'ok' }).Count
    Write-Host ''
    Show-ProgressBar -Done $done -Total $Checks.Count
    Write-Host ''
}

function Show-StepHeader {
    param([int]$Number, [int]$Total, [string]$Title)

    Write-Host ''
    Write-Brand -Text ('    ── Step {0} of {1} ' -f $Number, $Total) -Colour Purple -NoNewline
    Write-Brand -Text ('─' * [Math]::Max(4, 30 - $Title.Length)) -Colour Purple
    Write-Brand -Text "       $Title" -Colour Teal
    Write-Host ''
}

function Show-AllDone {
    <#
        The finished state, printed under the checklist rather than replacing
        it.

        It used to clear the screen and show a page of its own, which threw
        away the one thing the owner actually wants to see - the list of what
        is set up - and replaced it with three options where the main screen
        has more. Now the list stays and this is a footer on it.

        The "quit both apps and open them again" warning is gone because it is
        no longer true: the setup restarts them itself once Zo is connected.
    #>
    param([bool]$RestartNeeded)

    Write-Host ''
    Write-Host '      ✓   A L L   D O N E' -ForegroundColor $script:Ink.Good
    Write-Host '      Everything above is set up and working.' -ForegroundColor $script:Ink.Body
    if ($RestartNeeded) {
        Write-Host ''
        Write-Warn '      Windows needs a restart to finish one of these.'
    }
    Write-Host ''
    Show-MainOptions -Finished
}

function Show-MainOptions {
    <#
        Everything the owner can do, in one place.

        The same list whether the setup has finished or not, because "what can
        I do here" should not depend on how much is ticked - somebody who
        finished yesterday and came back to hire a second employee met a
        different, shorter menu than the one they used the first time.
    #>
    param([switch]$Finished)

    if ($Finished) {
        Write-Host '      What you can do:' -ForegroundColor $script:Ink.Body
        Write-Host ''
    }

    if (-not $Finished) {
        Write-Host '        ┌──────────────────────────────────────┐' -ForegroundColor $script:Ink.Good
        Write-Host '        │' -ForegroundColor $script:Ink.Good -NoNewline
        Write-Host '   Press ENTER to set everything up   ' -ForegroundColor $script:Ink.Strong -NoNewline
        Write-Host '│' -ForegroundColor $script:Ink.Good
        Write-Host '        └──────────────────────────────────────┘' -ForegroundColor $script:Ink.Good
        Write-Host ''
    }

    # Until the setup has finished there is exactly one key: Enter.
    #
    # Everything else manages something that does not exist yet. "Set up your
    # assistant again" before there is an assistant, or "your company second
    # brain" before it has been made, is a menu of ways to be confused - and
    # this screen already says six things are left. One instruction, one key,
    # and the whole list comes back the moment it is done.
    $rows = @()
    if ($Finished) {
        $rows += @{ Key = 'E'; What = 'Hire an AI employee'; Why = 'sales, admin, accounts, and more' }
        $rows += @{ Key = 'T'; What = 'See your AI employees'; Why = 'who works for you, and where they answer' }
        $rows += @{ Key = 'A'; What = 'Set up your assistant again'; Why = 'change the number, or how you reach it' }
        $rows += @{ Key = 'M'; What = 'Your company second brain'; Why = 'what your Zo remembers about the business' }
        $rows += @{ Key = 'Z'; What = 'Open your Zo'; Why = 'the website, for anything not here' }
    }
    foreach ($row in $rows) {
        Write-Host '        ' -NoNewline
        Write-Brand -Text " $($row.Key) " -Colour Yellow -NoNewline
        Write-Host "  $($row.What.PadRight(28))" -ForegroundColor $script:Ink.Strong -NoNewline
        Write-Host $row.Why -ForegroundColor $script:Ink.Muted
    }

    if ($Finished) {
        Write-Host '        ' -NoNewline
        Write-Brand -Text ' S ' -Colour Yellow -NoNewline
        Write-Host "  $('Start over'.PadRight(28))" -ForegroundColor $script:Ink.Strong -NoNewline
        Write-Host 'WARNING! Removes what this setup' -ForegroundColor $script:Ink.Warn
        Write-Host ('                                        installed, then sets it up again') -ForegroundColor $script:Ink.Warn
    }

    Write-Host '        ' -NoNewline
    Write-Brand -Text ' Q ' -Colour Yellow -NoNewline
    Write-Host '  Close' -ForegroundColor $script:Ink.Strong
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Install-ManagedTool {
    param([object]$Tool)

    Write-Title "Installing $($Tool.Title)"

    # Detect first. Never reinstall something that is already working.
    $existing = Get-CommandVersion -Command $Tool.Command -VersionArgs $Tool.VersionArgs
    if ($existing) {
        Write-Good "$($Tool.Title) $existing is already installed. Nothing to do."
        return $true
    }

    # Noted before the attempt, so a later "start over" knows this one was not
    # already on the machine. Removing something the owner installed themselves
    # is not this setup's to do.
    Add-InstalledByUs -Name $Tool.Key

    Write-Info "Asking Windows to install $($Tool.Title). This can take a few minutes."
    & winget.exe install --id $Tool.WingetId --exact --silent `
        --accept-package-agreements --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Host "    $_" -ForegroundColor $script:Ink.Muted }

    # winget's exit code proves nothing. Re-detect, and pick up the PATH that
    # the installer just added without needing a new terminal.
    Update-SessionPath
    $version = Get-CommandVersion -Command $Tool.Command -VersionArgs $Tool.VersionArgs
    if ($version) {
        Write-Good "$($Tool.Title) $version is installed."
        return $true
    }

    Write-Warn "$($Tool.Title) did not answer after installing."
    Write-Warn 'Close this window, open it again, and re-run this setup.'
    return $false
}

function Update-SessionPath {
    # A fresh install writes PATH to the registry; this process still holds the
    # old copy. Re-read both scopes so the verify step sees the new tool.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machine, $user | Where-Object { $_ }) -join ';'
}

function Install-ClaudeDesktop {
    Write-Title 'Installing Claude Desktop'
    if (Test-ClaudeDesktopInstalled) {
        Write-Good 'Claude Desktop is already installed. Nothing to do.'
        return $true
    }
    & winget.exe install --id 'Anthropic.Claude' --exact --silent `
        --accept-package-agreements --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Host "    $_" -ForegroundColor $script:Ink.Muted }

    if (Test-ClaudeDesktopInstalled) {
        Write-Good 'Claude Desktop is installed.'
        return $true
    }
    Write-Warn 'Claude Desktop did not appear. Try installing it by hand from claude.ai/download.'
    return $false
}

function Install-ChatGptDesktop {
    Write-Title 'Installing ChatGPT Desktop'
    if (Test-ChatGptDesktopInstalled) {
        Write-Good 'ChatGPT Desktop is already installed. Nothing to do.'
        return $true
    }

    Write-Info 'Installing ChatGPT from the Microsoft Store.'
    & winget.exe install --id '9PLM9XGG6VKS' --source msstore --accept-package-agreements `
        --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Host "    $_" -ForegroundColor $script:Ink.Muted }

    if (Test-ChatGptDesktopInstalled) {
        Write-Good 'ChatGPT Desktop is installed.'
        return $true
    }

    Write-Warn 'The Store install did not finish.'
    if (Read-YesNo -Question 'Open the ChatGPT download page in your browser instead?') {
        Start-Process $script:ChatGptDownloadUrl
        Write-Info 'Install it from that page, then come back and press R to re-check.'
    }
    return $false
}

function Open-DesktopAppToSignIn {
    <#
        Opens an app that is installed but not signed in, so the owner can do
        the one thing nobody else can. Signing in is a password and possibly a
        second factor: there is no version of this the setup performs for them.
    #>
    param([ValidateSet('Claude', 'ChatGPT')][string]$Which)

    Write-Title "Signing in to $Which"
    Write-Info "$Which is installed, but nobody has signed in on this computer yet."
    Write-Info 'Until you do, it cannot reach your Zo.'
    Write-Host ''
    Write-NumberedStep 1 "Open $Which"
    Write-NumberedStep 2 'Sign in with your' "$Which account"
    Write-NumberedStep 3 'Leave it open and come back here'
    Write-Host ''

    if (Read-YesNo -Question "Open $Which now?" -YesLabel 'Open it' -NoLabel 'I will open it myself') {
        if (Start-DesktopApp -Which $Which) {
            Write-Good "$Which is opening."
        } else {
            Write-Info "Could not open it from here. Please open $Which from the Start menu."
        }
    }
    return $true
}

function Start-DesktopApp {
    <#
        Launches a desktop app whichever way it happens to be installed.

        Both of these ship as packaged apps, which have no fixed .exe to run:
        the executable sits under Program Files\WindowsApps where it cannot be
        launched directly. They start through the shell by package identity
        instead, which is looked up rather than hard-coded, since the family
        name differs per build.
    #>
    param([ValidateSet('Claude', 'ChatGPT')][string]$Which)

    $packageName = if ($Which -eq 'Claude') { 'Claude' } else { 'OpenAI.Codex' }
    $package = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($package) {
        try {
            $appId = (Get-AppxPackageManifest $package).Package.Applications.Application.Id |
                Select-Object -First 1
            Start-Process -FilePath "shell:AppsFolder\$($package.PackageFamilyName)!$appId" -ErrorAction Stop
            return $true
        } catch { }
    }

    # Not packaged, so fall back to the ordinary install locations.
    $candidates = if ($Which -eq 'Claude') {
        @((Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'),
          (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'))
    } else {
        @((Join-Path $env:LOCALAPPDATA 'Programs\ChatGPT\ChatGPT.exe'))
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            Start-Process -FilePath $candidate -ErrorAction SilentlyContinue
            return $true
        }
    }
    return $false
}

function Set-ZoTokenInteractive {
    Write-Title 'Your Zo account key'
    Write-Info 'This is what lets Claude and ChatGPT talk to your Zo.'
    Write-Host ''

    # Asked before anything else, because someone without an account cannot get
    # a key and would otherwise sit on the settings page hunting for one.
    if (-not (Read-YesNo -Question 'Do you already have a Zo account?' -YesLabel 'Yes, I have one' -NoLabel 'No, make one')) {
        Write-Host ''
        Write-Info 'No problem. Let us make one first.'
        if (Read-YesNo -Question 'Open the Zo sign-up page now?') {
            Start-Process $script:ZoSignUpUrl
        }
        Write-Host ''
        # Waited for, not sent away.
        #
        # This used to say "come back here and choose this step again" and
        # return - which was a dead end twice over: signing up takes a few
        # minutes and this carried straight on to the next step without them,
        # and choosing a single step is not something the menu offers any more.
        Write-Info 'Take your time. Sign up on the page that just opened, and'
        Write-Info 'come back here when you have an account.'
        Write-Host ''
        Read-Host -Prompt '      Press Enter once you have signed up' | Out-Null
        Write-Host ''
    }

    Write-Host ''
    Write-Info 'On the Zo website:'
    Write-Host ''
    Write-NumberedStep 1 'Click' 'Settings, then Advanced'
    Write-NumberedStep 2 'Find the' 'Access Key'
    Write-NumberedStep 3 'Type any name, for example' 'my computer'
    Write-NumberedStep 4 'Click Add, then copy the key it shows you'
    Write-Host ''

    # Their own workspace once a key has ever worked on this computer; the
    # generic host only on a machine that has never seen one.
    if (Read-YesNo -Question 'Open the Zo settings page now?') {
        Start-Process (Get-ZoSettingsUrl -WorkspaceUrl $script:ZoWorkspaceUrl)
    }

    # Asked until it is right, or until they say stop. Everything below this
    # step needs the key, so failing out on a mistyped paste means the rest of
    # the run has nothing to work with - which is what it did.
    $token = ''
    while ($true) {
        Write-Host ''
        Write-Info 'Paste the key below. It will not appear on screen as you type.'
        $secure = Read-Host -Prompt '  Zo key' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

        if (Test-ZoTokenShape -Token $token) { break }

        Write-Host ''
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Warn 'Nothing was pasted.'
        } else {
            Write-Bad 'That does not look like a Zo key. It should start with zo_sk_'
        }
        Write-Info 'It is a long line starting with zo_sk_ - copy the whole thing.'
        Write-Host ''
        if (-not (Read-YesNo -Question 'Try again?' -YesLabel 'Yes, paste it again' -NoLabel 'Stop for now')) {
            Write-Host ''
            Write-Info 'No problem. Nothing below this can be set up without the key,'
            Write-Info 'so run the setup again when you have it.'
            return $false
        }
    }

    Save-ZoToken -Token $token.Trim()
    Write-Good 'Saved. Windows keeps it under your account only.'
    Confirm-ZoKeyWorks
    return $true
}

function Confirm-ZoKeyWorks {
    <#
        Uses the key straight away rather than waiting for the next check.

        Two reasons. It tells the owner immediately whether the key actually
        works, while they still have the Zo page open and can copy it again -
        far better than a silent save followed by four failed steps. And it
        learns their Zo address now, so every link for the rest of this run
        goes to their own workspace instead of a generic page.
    #>
    Write-Host ''
    Write-Info 'Checking the key with Zo...'

    $zo = Get-ZoVerification -Token (Get-ZoToken)
    if (-not $zo) {
        Write-Warn 'Saved, but Zo did not answer just now.'
        Write-Info 'That is usually the internet rather than the key itself.'
        return
    }

    if ($zo.workspaceUrl) {
        Save-ZoWorkspaceUrl -Url $zo.workspaceUrl
        Write-Good 'Your key works.'
        Write-Host '        ' -NoNewline
        Write-Brand -Text $zo.workspaceUrl -Colour Teal
        Write-Info 'Everything from here will open your own Zo pages.'
    } else {
        Write-Good 'Your key works.'
    }
}

function Backup-ConfigFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $backupDir = Join-Path (Split-Path -Parent $Path) 'vimigo-backups'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $backupPath = Join-Path $backupDir ("{0}.{1}.bak" -f (Split-Path -Leaf $Path), $stamp)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
}

function Connect-ZoToClaude {
    Write-Title 'Connecting Zo to Claude Desktop'

    $token = Get-ZoToken
    if (-not (Test-ZoTokenShape -Token $token)) {
        Write-Bad 'Enter your Zo account key first.'
        return $false
    }

    $directory = Split-Path -Parent (Resolve-ClaudeConfigPath)
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # Read whatever Claude already has. Everything in this file that is not our
    # own entry survives untouched.
    $document = $null
    if (Test-Path -LiteralPath (Resolve-ClaudeConfigPath)) {
        $raw = Get-Content -LiteralPath (Resolve-ClaudeConfigPath) -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $document = $raw | ConvertFrom-Json -ErrorAction Stop
            } catch {
                # The path used to be printed here. It is exactly what a
                # non-technical owner cannot act on, and it went to the screen
                # rather than the support log where it belongs.
                Write-Bad "Claude's settings file is not readable, so it was left alone."
                Write-Info 'Nothing was changed. Contact Vimigo support and they'
                Write-Info 'will sort it out.'
                Write-SetupLog "unreadable Claude config at $(Resolve-ClaudeConfigPath)"
                return $false
            }
        }
    }
    if (-not $document) { $document = [pscustomobject]@{} }

    $backup = Backup-ConfigFile -Path (Resolve-ClaudeConfigPath)
    if ($backup) { Write-Info "Saved a backup of your existing Claude settings." }

    if (-not (Test-ObjectHasProperty -Object $document -Name 'mcpServers')) {
        $document | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{})
    }

    $entry = [pscustomobject]@{
        command = 'npx'
        args    = @(
            $script:McpRemotePackage
            $script:ZoMcpUrl
            '--header'
            "Authorization: Bearer $token"
        )
    }

    if (Test-ObjectHasProperty -Object $document.mcpServers -Name $script:ZoMcpEntryName) {
        $document.mcpServers.PSObject.Properties.Remove($script:ZoMcpEntryName)
    }
    $document.mcpServers | Add-Member -NotePropertyName $script:ZoMcpEntryName -NotePropertyValue $entry

    Write-TextFile -Path (Resolve-ClaudeConfigPath) -Text ($document | ConvertTo-Json -Depth 12)

    if (-not (Test-ClaudeMcpConfigured)) {
        Write-Bad 'The connection did not save correctly. Restoring your previous settings.'
        if ($backup) { Copy-Item -LiteralPath $backup -Destination (Resolve-ClaudeConfigPath) -Force }
        return $false
    }

    Write-Good 'Zo is connected to Claude Desktop.'
    Restart-DesktopApp -Which 'Claude'
    return $true
}

function Test-DesktopAppPath {
    <#
        True only for the desktop app itself, judged by where it runs from.

        Separate from the restart so it can be tested without closing anything,
        because the only honest test of "does this leave Claude Code alone" is
        one that does not have to kill a process to find out.
    #>
    param([ValidateSet('Claude', 'ChatGPT')][string]$Which, [string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # Claude Code's executable is also called claude.exe. Excluded first, so no
    # later rule can let it back in.
    if ($Path -like '*claude-code*') { return $false }

    $markers = if ($Which -eq 'Claude') {
        @('\WindowsApps\Claude_', '\AnthropicClaude\', '\Programs\Claude\')
    } else {
        @('\WindowsApps\OpenAI.Codex_', '\Programs\ChatGPT\')
    }
    foreach ($marker in $markers) { if ($Path -like "*$marker*") { return $true } }
    return $false
}

function Restart-DesktopApp {
    <#
        Closes the app and opens it again, so the new connection takes effect
        without the owner having to do anything.

        These apps read their settings once, at startup. "Quit it completely
        and open it again" is a small instruction that a good number of people
        will not carry out - some will minimise it and call that closed - and
        the result is a green tick beside an app that cannot see Zo.

        Said out loud before it happens, because windows disappearing off the
        screen with no warning is alarming. And if it does not work, the owner
        is told plainly what to do instead: closing and opening an app is
        squarely inside what they already know how to do.
    #>
    param([ValidateSet('Claude', 'ChatGPT')][string]$Which)

    # Matched on the program that is running, never on its name.
    #
    # "claude.exe" is not just Claude Desktop. Claude Code ships an executable
    # with the same name, and on a developer's machine both are running at once
    # - so closing everything called claude closes the terminal session the
    # owner may be sitting in. That is not a hypothetical: it happened, mid-run,
    # on this machine.
    #
    # ChatGPT's desktop app ships under OpenAI.Codex and its process is named
    # ChatGPT, so the name is no guide there either.
    $processNames = if ($Which -eq 'Claude') { @('Claude') } else { @('ChatGPT', 'Codex') }

    $running = {
        @($processNames |
            ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue } |
            Where-Object {
                # A process whose path cannot be read is left alone. Guessing
                # would mean killing something on no evidence at all.
                $path = ''
                try { $path = [string]$_.Path } catch { $path = '' }
                Test-DesktopAppPath -Which $Which -Path $path
            })
    }

    $wasRunning = @(& $running)
    if ($wasRunning.Count -eq 0) {
        Write-Info "Open $Which when you like - Zo will be waiting inside it."
        return
    }

    Write-Host ''
    Write-Info "Closing $Which and opening it again, so it picks this up."

    foreach ($process in $wasRunning) {
        # Asked to close first, the way the owner would, so it saves whatever
        # it was doing. Killed only if it refuses.
        try { $null = $process.CloseMainWindow() } catch { }
    }
    Start-Sleep -Seconds 3
    foreach ($process in @(& $running)) {
        try { $process.Kill() } catch { }
    }
    Start-Sleep -Seconds 2

    $opened = $false
    try { $opened = Start-DesktopApp -Which $Which } catch { $opened = $false }

    if ($opened) {
        Write-Good "$Which is open again with Zo connected."
        return
    }

    # Never left as "it worked" when it did not. This is the one fallback the
    # owner can act on without help.
    Write-Host ''
    Write-Warn "Could not open $Which again by itself."
    Write-Info "Open $Which yourself and Zo will be there. If it was already"
    Write-Info 'open, close it completely first - not just the window.'
}

function Connect-ZoToChatGpt {
    Write-Title 'Connecting Zo to ChatGPT'

    $token = Get-ZoToken
    if (-not (Test-ZoTokenShape -Token $token)) {
        Write-Bad 'Enter your Zo account key first.'
        return $false
    }

    $directory = Split-Path -Parent $script:CodexConfigPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $existing = ''
    if (Test-Path -LiteralPath $script:CodexConfigPath) {
        $existing = Get-Content -LiteralPath $script:CodexConfigPath -Raw
        if ($null -eq $existing) { $existing = '' }
    }

    $backup = Backup-ConfigFile -Path $script:CodexConfigPath
    if ($backup) { Write-Info 'Saved a backup of your existing ChatGPT settings.' }

    $sectionHeader = "[mcp_servers.$script:ZoMcpEntryName]"
    $block = @(
        $sectionHeader
        'command = "npx"'
        ('args = ["{0}", "{1}", "--header", "Authorization: Bearer {2}"]' -f `
            $script:McpRemotePackage, $script:ZoMcpUrl, $token)
    ) -join "`n"

    $updated = Remove-TomlSection -Content $existing -Header $sectionHeader
    if ($updated.Length -gt 0 -and -not $updated.EndsWith("`n")) { $updated += "`n" }
    $updated = $updated + "`n" + $block + "`n"

    Write-TextFile -Path $script:CodexConfigPath -Text $updated

    if (-not (Test-CodexMcpConfigured)) {
        Write-Bad 'The connection did not save correctly. Restoring your previous settings.'
        if ($backup) { Copy-Item -LiteralPath $backup -Destination $script:CodexConfigPath -Force }
        return $false
    }

    Write-Good 'Zo is connected to ChatGPT.'
    Restart-DesktopApp -Which 'ChatGPT'
    Write-Warn 'Quit ChatGPT completely and open it again for this to take effect.'
    Write-Host ''

    # Where it actually appears, checked against the app rather than guessed.
    #
    # This said "Connectors, then Advanced, then turn on Developer mode" and all
    # three were wrong: there is no Connectors page, nothing has to be switched
    # on, and Developer mode is a different feature. Tengku's team hit it on the
    # morning of the training and went hunting through settings that do not
    # exist. A customer who looks in the wrong place sees nothing and concludes
    # the setup failed, which is exactly what these lines are here to prevent.
    Write-Info 'If you open ChatGPT and cannot find Zo there:'
    Write-Host ''
    Write-NumberedStep 1 'In ChatGPT open' 'Settings'
    Write-NumberedStep 2 'Click' 'Plugins'
    Write-NumberedStep 3 'Choose the tab called' 'MCPs'
    Write-Host ''
    Write-Info 'Zo is in that list, already switched on. Nothing to set up -'
    Write-Info 'it is only somewhere to look if you want to see it.'
    return $true
}

function Remove-TomlSection {
    <#
        Drops one [section] and the lines under it, leaving every other section
        byte-identical. Re-running the setup therefore replaces our own entry
        instead of stacking duplicates.
    #>
    param([string]$Content, [string]$Header)

    if ([string]::IsNullOrEmpty($Content)) { return '' }

    $lines = $Content -split "`r?`n"
    $kept = New-Object System.Collections.Generic.List[string]
    $inTarget = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq $Header) { $inTarget = $true; continue }
        # Any following section header ends ours.
        if ($inTarget -and $trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) { $inTarget = $false }
        if (-not $inTarget) { $kept.Add($line) }
    }

    return (($kept -join "`n").TrimEnd() )
}

function Invoke-ZoHelper {
    <#
        Runs zo-verify.js and returns the parsed reply, or $null when it could
        not be asked. Every conversation with Zo goes through here.
    #>
    param(
        [string[]]$Arguments,
        # Shown beside the turning marker while Zo is being waited on.
        [string]$Waiting = 'talking to your Zo...'
    )

    $token = Get-ZoToken
    if (-not (Test-ZoTokenShape -Token $token)) { return $null }

    # Every way this can fail looks the same on screen - "could not reach Zo" -
    # because the screen is right to keep it simple. But then a machine with no
    # Node, a missing helper file and a dropped wifi are one symptom with three
    # causes, and on a support call there is nothing to go on. So the reason
    # goes to the log, where it costs the owner nothing.
    $helper = Join-Path $PSScriptRoot 'zo-verify.js'
    $node = Get-Command -Name 'node' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not (Test-Path -LiteralPath $helper)) {
        Write-SetupLog "zo helper missing at $helper"
        return $null
    }
    if (-not $node) {
        Write-SetupLog 'zo helper not run: node is not installed yet'
        return $null
    }

    # Run as a separate process so a marker can turn while it waits. Talking to
    # Zo is a network round trip and can sit for several seconds with nothing
    # to show for it.
    $outputFile = Join-Path ([IO.Path]::GetTempPath()) ("vimigo-zo-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $null = Invoke-WithSpinner -Message $Waiting `
            -FilePath $node.Source -Arguments (@($helper, $token) + $Arguments) `
            -OutputFile $outputFile

        if (-not (Test-Path -LiteralPath $outputFile)) {
            Write-SetupLog "zo helper wrote nothing ($($Arguments -join ' '))"
            return $null
        }
        $raw = Get-Content -LiteralPath $outputFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            # Whatever it complained about, minus anything that looks like a key.
            $why = ''
            if (Test-Path -LiteralPath "$outputFile.err") {
                $why = (Get-Content -LiteralPath "$outputFile.err" -Raw -ErrorAction SilentlyContinue)
            }
            Write-SetupLog "zo helper gave an empty answer: $(($why -replace '\s+', ' ').Trim())"
            return $null
        }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-SetupLog "zo helper failed: $($_.Exception.Message)"
        return $null
    } finally {
        Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$outputFile.err" -Force -ErrorAction SilentlyContinue
    }
}

function Get-ZoSkillsUrl {
    param([string]$WorkspaceUrl)
    if ($WorkspaceUrl) { return "$WorkspaceUrl/?t=skills" }
    return 'https://zo.computer'
}

function Install-SecondBrain {
    <#
        Sets up somewhere for the business to keep what it learns.

        Nothing is asked. It makes plain folders of Markdown - the kind that
        open on a phone, in Obsidian, or in anything else, now and in ten years
        - and an index over them so a phrase can be found across all of it at
        once. Empty and labelled, so that when the assistant is told to
        remember something there is somewhere for it to go.

        What it deliberately does not do is decide how this business works.
        Nine folders is a guess, and a good guess is still a guess: a workshop
        needs jobs and parts, a clinic needs patients and appointments. That
        part is a conversation with their Zo, not a question on a setup screen,
        and the screen says so rather than implying this is finished.
    #>
    Write-Title 'Your company second brain'
    Write-Info 'This is where your Zo keeps what it learns about your business,'
    Write-Info 'so it stops asking you the same things twice.'
    Write-Host ''

    $result = Invoke-ZoHelper -Arguments @('--second-brain') -Waiting 'making room on your Zo...'

    if (-not $result -or -not $result.ok) {
        Write-Bad 'Could not set that up just now.'
        Write-Info 'Run the setup again in a moment and it will pick this up.'
        return $false
    }

    $folders = if (Test-ObjectHasProperty $result 'folders') { [int]$result.folders } else { 0 }
    $indexed = (Test-ObjectHasProperty $result 'indexed') -and $result.indexed

    Write-Good "Ready. $folders drawers, labelled and empty."
    Write-Host ''
    foreach ($row in @(
        'People             who works here, and what they do',
        'Customers          who they are, what they bought, what they asked',
        'Suppliers          what they supply, what it costs, who to call',
        'Products           what you sell, and what people ask about it',
        'Money              prices, terms, who pays late',
        'Decisions          what was decided, and why',
        'Meetings           what was said and what was agreed',
        'How we do things   hours, refunds, complaints, deliveries',
        'Inbox              anything not sorted out yet'
    )) {
        Write-Host '         ' -NoNewline
        Write-Host $row -ForegroundColor $script:Ink.Muted
    }
    Write-Host ''
    if ($indexed) {
        Write-Info 'Everything in there can be searched instantly, however much'
        Write-Info 'of it there is.'
        Write-Host ''
    }

    # The honest part. Nine folders is a guess at what a business looks like,
    # and saying "done" here would leave someone expecting it to be right for
    # them out of the box.
    Write-Warn 'This is a starting point, not a finished filing system.'
    Write-Host ''
    Write-Info 'Every business keeps different things. A workshop wants jobs and'
    Write-Info 'parts; a clinic wants patients and appointments; a shop wants'
    Write-Info 'stock and suppliers.'
    Write-Host ''
    Write-Info 'So tell your Zo about your business and let it shape this around'
    Write-Info 'you. Just talk to it, the way you would tell a new employee how'
    Write-Info 'things work here:'
    Write-Host ''
    Write-Host '         ' -NoNewline
    Write-Host '"We are a car workshop. Keep a file for every job."' -ForegroundColor $script:Ink.Strong
    Write-Host '         ' -NoNewline
    Write-Host '"Remember that Ali Trading always pays late."' -ForegroundColor $script:Ink.Strong
    Write-Host '         ' -NoNewline
    Write-Host '"Every time I send you a receipt, file it under Money."' -ForegroundColor $script:Ink.Strong
    Write-Host ''
    Write-Info 'The more you tell it, the more useful it gets.'
    return $true
}

function Get-SkillsFolder {
    # The skill folders travel with the setup, beside this script.
    return (Join-Path $PSScriptRoot 'skills')
}

function Get-ZoSkills {
    <#
        Asks Zo which of the shipped skills it actually has.

        Returns a hashtable of Installed and Missing names, or $null when Zo
        could not be reached - which is not the same as "none installed" and
        must never be reported as it.
    #>
    param([string]$Token)

    if (-not $Token) { return $null }
    $result = Invoke-ZoHelper -Arguments @('--skills', (Get-SkillsFolder)) -Waiting 'checking your skills...'
    if (-not $result -or -not $result.ok) { return $null }

    return @{
        Installed = @($result.installed)
        Missing   = @($result.missing)
    }
}

function Install-ZoSkills {
    <#
        Puts the recommended skills on the owner's Zo, without the owner going
        anywhere near the Skills page.

        A skill is a folder holding a SKILL.md, so installing one is copying
        that folder across - which the setup does over Zo's own connection. The
        folders are what Zo's catalogue installs, in the same folder names, so
        this is not an imitation of installing them; it is the same result.

        Anything already there is left alone, and the answer at the end is read
        back off Zo rather than assumed from the commands having been sent.
    #>
    Write-Title 'Give your Zo more skills'
    Write-Info 'Skills teach your Zo to do bigger jobs. These nine come with the'
    Write-Info 'setup, and it puts them on for you now.'
    Write-Host ''

    $number = 0
    foreach ($skill in $script:ZoSkills.Keys) {
        $number++
        Write-Host '     ' -NoNewline
        Write-Brand -Text " $number " -Colour Yellow -NoNewline
        Write-Host "  $($skill.PadRight(26))" -ForegroundColor $script:Ink.Strong -NoNewline
        Write-Host $script:ZoSkills[$skill] -ForegroundColor $script:Ink.Muted
    }
    Write-Host ''

    $result = Invoke-ZoHelper -Arguments @('--install-skills', (Get-SkillsFolder)) `
        -Waiting 'putting the skills on your Zo...'

    if (-not $result) {
        Write-Bad 'Could not reach your Zo just now, so nothing was installed.'
        Write-Info 'Run the setup again in a moment and it will pick this up.'
        return $false
    }

    $added = @(if (Test-ObjectHasProperty $result 'added') { $result.added } else { @() })
    $missing = @(if (Test-ObjectHasProperty $result 'missing') { $result.missing } else { @() })

    if ($added.Count -gt 0) {
        Write-Good "Installed $($added.Count) of them."
    } elseif ($missing.Count -eq 0) {
        Write-Good 'Your Zo already had all nine.'
    }

    if ($missing.Count -gt 0) {
        Write-Host ''
        Write-Warn 'These did not go on:'
        foreach ($name in $missing) {
            Write-Host "         • $name" -ForegroundColor $script:Ink.Warn
        }
        Write-Info 'Everything else is on. Run the setup again to retry these.'
        return $false
    }

    Write-Host ''
    Write-Info 'These nine are a starting point, not the whole list. There are'
    Write-Info 'hundreds more on that same page, and new ones appear all the'
    Write-Info 'time. Have a browse whenever you want your Zo to do something'
    Write-Info 'it cannot do yet:'
    Write-Host '        ' -NoNewline
    Write-Brand -Text (Get-ZoSkillsUrl -WorkspaceUrl $script:ZoWorkspaceUrl) -Colour Teal
    return $true
}

function Invoke-HireEmployee {
    <#
        Hires an AI employee: pick a role, name them, and Zo creates the
        persona. Deliberately shaped like hiring a person rather than editing
        settings, because that is what it is - and the owner will manage them
        the same way afterwards.
    #>
    Write-Title 'Hire an AI employee'

    if (-not (Test-ZoTokenShape -Token (Get-ZoToken))) {
        Write-Bad 'Enter your Zo account key first.'
        return $false
    }

    # The team so far, asked of Zo rather than read from our own note.
    #
    # The note is only ever a convenience - it remembers which job somebody was
    # hired for, which Zo does not record. Zo is what decides who exists, so an
    # employee made on the website appears here, and one deleted there stops
    # appearing. A list that can drift from the truth is worse than no list,
    # because these are answering people.
    $team = @(Sync-HiredEmployees)
    if ($team.Count -gt 0) {
        Write-Info 'Working for you already:'
        foreach ($member in $team) {
            Write-Host '         • ' -ForegroundColor $script:Ink.Muted -NoNewline
            Write-Host "$($member.name)" -ForegroundColor $script:Ink.Strong -NoNewline
            $extra = @()
            if ($member.title) { $extra += [string]$member.title }
            if ($member.channel -and $member.channel -ne 'none') { $extra += "on $($member.channel)" }
            if ($extra.Count -gt 0) {
                Write-Host "  $($extra -join ', ')" -ForegroundColor $script:Ink.Muted
            } else {
                Write-Host '  (made on the Zo website)' -ForegroundColor $script:Ink.Muted
            }
        }
        Write-Host ''
    }

    Write-Info 'Who do you need? Think of it like hiring someone for a job.'
    Write-Host ''

    # The owner's own assistant is not on this list.
    #
    # It is the required one, set up two rows above this on the checklist, and
    # it already has this same prompt. Offering it here invites hiring a second
    # one that nobody can reach - it would have no channel, because the four
    # ways of reaching an assistant belong to the first.
    $roles = @($script:AiEmployees.Keys | Where-Object { $_ -ne 'assistant' })
    $number = 0
    foreach ($role in $roles) {
        $number++
        $entry = $script:AiEmployees[$role]
        Write-Host '     ' -NoNewline
        Write-Brand -Text " $number " -Colour Yellow -NoNewline
        Write-Host "  $($entry.Title.PadRight(24))" -ForegroundColor $script:Ink.Strong -NoNewline
        Write-Host $entry.For -ForegroundColor $script:Ink.Muted
    }
    Write-Host '     ' -NoNewline
    Write-Brand -Text " $($number + 1) " -Colour Yellow -NoNewline
    Write-Host "  $('Someone else'.PadRight(24))" -ForegroundColor $script:Ink.Strong -NoNewline
    Write-Host 'describe the job in your own words' -ForegroundColor $script:Ink.Muted

    # Skipping is a numbered choice like any other.
    #
    # It used to be a grey line saying "Enter - go back, hiring nobody", which
    # reads as what happens when you get it wrong rather than as something you
    # are allowed to pick. Somebody who does not want an employee yet should not
    # have to work out that pressing nothing is the way to say so.
    Write-Host '     ' -NoNewline
    Write-Brand -Text " $($number + 2) " -Colour Yellow -NoNewline
    Write-Host "  $('Not now'.PadRight(24))" -ForegroundColor $script:Ink.Strong -NoNewline
    Write-Host 'skip this - you can hire any time later' -ForegroundColor $script:Ink.Muted
    Write-Host ''

    Write-Brand -Text "      Choose 1 to $($number + 2) > " -Colour Purple -NoNewline
    $choice = 0
    if (-not [int]::TryParse(([string](Read-Host)).Trim(), [ref]$choice)) { $choice = 0 }
    # Enter still works, and so does anything unexpected. Both mean the same
    # thing as the skip row, so neither can strand somebody on this screen.
    if ($choice -lt 1 -or $choice -gt ($number + 2)) {
        Write-Host ''
        Write-Info 'Nobody hired. You can do this whenever you like.'
        return $false
    }
    if ($choice -eq ($number + 2)) {
        Write-Host ''
        Write-Good 'No problem - that is a perfectly good answer.'
        Write-Info 'Your assistant is already working. Hire your first employee'
        Write-Info 'whenever you are ready: press E on the main screen.'
        return $false
    }

    if ($choice -eq ($number + 1)) {
        $role = 'custom'
        Write-Host ''
        Write-Info 'What is the job? One or two sentences is plenty.'
        Write-Host ''
        Write-Brand -Text '      The job > ' -Colour Purple -NoNewline
        $described = ([string](Read-Host)).Trim()
        if (-not $described) { Write-Info 'Nothing described, so nobody was hired.'; return $false }
        # Their words, then the limits. An employee described in one sentence
        # talks to the same customers as the eight on the list, so it gets the
        # same rules about money, dates and names - otherwise "Someone else" is
        # the one door out of every safeguard on this screen.
        $prompt = $described + "`n`n" + $script:AiEmployeeCustomRules
        $roleTitle = 'AI employee'
    } else {
        $role = $roles[$choice - 1]
        $entry = $script:AiEmployees[$role]
        $prompt = $entry.Prompt
        $roleTitle = $entry.Title
    }

    Write-Host ''
    # ${roleTitle}, not $roleTitle. PowerShell treats "?" as part of a variable
    # name inside a string, so "$roleTitle?" looks up a variable called
    # "roleTitle?", finds nothing, and throws under StrictMode - which is
    # exactly how this line took out the whole hire screen.
    Write-Info "What shall we call your ${roleTitle}? A first name works well."
    Write-Host ''
    Write-Brand -Text '      Name > ' -Colour Purple -NoNewline
    $name = ([string](Read-Host)).Trim()
    if (-not $name) { $name = $roleTitle }

    # Customers are on the other end of this one, and Zo starts an employee
    # with every permission. Worth one sentence before it happens rather than
    # a surprise afterwards.
    if ($role -eq 'customer-service') {
        Write-Host ''
        Write-Warn 'A word about this one.'
        Write-Info 'Your customers will be talking to it directly, and it starts'
        Write-Info 'with permission to use everything your Zo can reach. You can'
        Write-Info 'narrow that afterwards on your own AI settings page.'
        Write-Host ''
        if (-not (Read-YesNo -Question "Hire $name anyway?" -YesLabel 'Yes, hire them' -NoLabel 'Not now')) {
            Write-Info 'No problem. Nobody was hired.'
            return $false
        }
    }

    Write-Host ''
    Write-Info "Hiring $name..."
    $result = Invoke-ZoHelper -Arguments @('--hire', $name, $prompt) -Waiting "telling Zo about $name..."

    if (-not $result -or -not $result.ok) {
        Write-Bad 'Could not hire them just now.'
        if ($result -and $result.error) { Write-Info "  $($result.error)" }
        return $false
    }

    Write-Host ''
    Write-Good "$name is hired."
    Write-Host ''

    # Money, so it is said out loud either way. On the owner's own plan there
    # is nothing more to pay; without one, Zo charges by use and they should
    # hear that from us rather than from a bill.
    $onOwnPlan = (Test-ObjectHasProperty $result 'ownPlan') -and $result.ownPlan
    if ($onOwnPlan) {
        $modelLabel = if (Test-ObjectHasProperty $result 'model') { [string]$result.model } else { '' }
        Write-Good "Running on the AI plan you already pay for. No extra cost."
        if ($modelLabel) { Write-Host "         $modelLabel" -ForegroundColor $script:Ink.Muted }
    } else {
        Write-Warn 'This one runs on Zo credit, which is charged by use.'
        Write-Host ''
        Write-Info 'To put it on the Claude or ChatGPT plan you already pay for,'
        Write-Info 'do this once on the Zo website:'
        Write-Host ''
        Write-NumberedStep 1 'Open' 'your Zo settings, AI page'
        Write-NumberedStep 2 'Under Providers, click' 'Connect for Claude and ChatGPT'
        Write-NumberedStep 3 'Turn on the models' 'you want to use'
        Write-NumberedStep 4 'Set your default' 'for every channel'
        Write-Host ''
        Write-Host '        ' -NoNewline
        Write-Brand -Text (Get-ZoAiSettingsUrl -WorkspaceUrl $script:ZoWorkspaceUrl) -Colour Teal
        Write-Host ''
        Write-Info 'Then hire again and they will use your plan instead.'
    }
    Write-Host ''
    # Straight to this employee's own page, using the id Zo just handed back.
    $personaId = if (Test-ObjectHasProperty $result 'id') { [string]$result.id } else { '' }
    $personaUrl = Get-ZoPersonasUrl -WorkspaceUrl $script:ZoWorkspaceUrl -PersonaId $personaId

    # Remembered here as well as on Zo. Zo stays the authority on who exists -
    # an employee removed on the website must not reappear here - but keeping
    # the role and the page link locally is what lets the setup show the team
    # and go straight to one of them without asking Zo first.
    Add-HiredEmployee -Name $name -Role $role -Title $roleTitle -PersonaId $personaId

    # Hiring someone nobody can message is half a job. Asked here, while the
    # owner is still thinking about this one person, rather than left to a
    # settings screen they will never find.
    Set-EmployeeChannel -Name $name -Brief $prompt

    # The part that saves building a settings screen for any of this: the owner
    # already has four ways to talk to Zo, and Zo can edit its own employees.
    Write-Info "To change what $name does, just tell your assistant. Say"
    Write-Info "`"$name should also handle refunds`" - in the web chat, on"
    Write-Info 'WhatsApp, or in Claude on this computer. No settings needed.'
    Write-Host ''
    Write-Info 'Or open their page and edit it yourself:'
    Write-Host '        ' -NoNewline
    Write-Brand -Text $personaUrl -Colour Teal
    Write-Host ''

    if (Read-YesNo -Question 'Open that page now?' -YesLabel 'Open it' -NoLabel 'Not now') {
        Start-Process $personaUrl
    }

    # The last thing on the screen, because it is the thing that matters most.
    # A new employee knows a job title and nothing else, and the person on the
    # other end of a WhatsApp cannot tell the difference between an employee
    # that knows the business and one that is making it up.
    Write-Host ''
    Write-Warn "$name is hired, but not answering anyone yet."
    Write-Host ''
    Write-Info 'That is on purpose. Right now they know their job and nothing'
    Write-Info 'about your business - not what you sell, not your prices, not'
    Write-Info 'your rules - and a customer would believe whatever they say.'
    Write-Host ''
    Write-Info "Teach them first. Tell your own Zo what $name needs to know,"
    Write-Info 'in your own words, the way you would tell someone on their'
    Write-Info 'first morning. Then switch them on when you are happy.'
    Write-Host ''
    return $true
}

function Set-EmployeeChannel {
    <#
        Asks how staff and customers are meant to reach one employee, and
        writes the answer down.

        Two ways offered, not four. The web chat and the owner's own number
        belong to the owner's own assistant: the owner's number is the one they
        type into themselves, so an employee sitting on it would be answering
        the boss instead of the customer. Saying so in one line is cheaper than
        letting them pick it and find out.

        Nothing here connects anything. A second WhatsApp number is its own job
        - its own bridge, its own linked device - and the owner has put that
        off. So this records what they want and says plainly that nobody can
        reach the employee yet. Half-linking would be worse than not linking:
        an employee that looks reachable is a customer messaging a number
        nobody is on.
    #>
    param([string]$Name, [string]$Brief)

    Write-Host ''
    Write-Info "How will people reach ${Name}?"
    Write-Host ''
    Write-Info 'An employee talks to your staff and your customers, so they need'
    Write-Info 'somewhere to be messaged.'
    Write-Host ''

    Write-Host '     ' -NoNewline
    Write-Brand -Text ' 1 ' -Colour Yellow -NoNewline
    Write-Host "  $('WhatsApp'.PadRight(14))" -ForegroundColor $script:Ink.Strong -NoNewline
    Write-Host 'needs its own number, not the one you use' -ForegroundColor $script:Ink.Muted
    Write-Host '     ' -NoNewline
    Write-Brand -Text ' 2 ' -Colour Yellow -NoNewline
    Write-Host "  $('Telegram'.PadRight(14))" -ForegroundColor $script:Ink.Strong -NoNewline
    Write-Host 'free, and no extra phone number needed' -ForegroundColor $script:Ink.Muted
    Write-Host '     ' -NoNewline
    Write-Brand -Text ' 3 ' -Colour Yellow -NoNewline
    Write-Host "  $('Not yet'.PadRight(14))" -ForegroundColor $script:Ink.Strong -NoNewline
    Write-Host 'I will sort this out later' -ForegroundColor $script:Ink.Muted
    Write-Host ''
    Write-Info 'The web chat and your own number are not on this list. Those two'
    Write-Info 'are yours, for the assistant you talk to yourself.'
    Write-Host ''

    Write-Brand -Text '      Choose 1, 2 or 3 > ' -Colour Purple -NoNewline
    $pick = 0
    if (-not [int]::TryParse(([string](Read-Host)).Trim(), [ref]$pick)) { $pick = 3 }

    # What gets written down. Only WhatsApp is ever recorded as a channel:
    # writing "telegram" against an employee would be recording a wish as a
    # setting, and a later run would try to honour something that does not
    # exist.
    $channel = 'none'
    $phone = ''

    switch ($pick) {
        1 {
            if (Set-EmployeeWhatsApp -Name $Name -Brief $Brief) {
                $channel = 'whatsapp'
                $phone = $script:LastEmployeePhone
            }
        }
        2 {
            if (Set-EmployeeTelegram -Name $Name -Brief $Brief) { $channel = 'telegram' }
        }
        default {
            Write-Host ''
            Write-Good 'That is a perfectly good answer.'
            Write-Info "$Name is saved either way, and you can give them a way to"
            Write-Info 'be reached whenever you want. There is no rush: they have'
            Write-Info 'plenty to learn from you first.'
        }
    }

    Update-HiredEmployeeChannel -Name $Name -Channel $channel -Phone $phone
}

$script:LastEmployeePhone = ''

function Wait-ForEmployeeNumber {
    <#
        Waits while the owner types the pairing code into their phone.

        It waits rather than asking whether they did it. The setup once marched
        past a step the owner was still working on and reported nine failures
        for a man who had not finished signing up; this is the same shape of
        step, on a phone, and gets the same treatment.

        Five minutes, then it stops waiting and says the code is still good -
        because a code that expires while somebody hunts for Linked Devices is
        not a fault they caused, and running the setup again picks it up.
    #>
    param([string]$Name)

    $deadline = (Get-Date).AddMinutes(5)
    $frames = @('◐', '◓', '◑', '◒')
    $frame = 0
    $lastAsked = [datetime]::MinValue

    while ((Get-Date) -lt $deadline) {
        Write-Host "`r      " -NoNewline
        Write-Brand -Text $frames[$frame % $frames.Count] -Colour Teal -NoNewline
        Write-Host ("  waiting for $Name's number to link...".PadRight(60)) `
            -ForegroundColor $script:Ink.Muted -NoNewline
        $frame++
        Start-Sleep -Milliseconds 250

        if (((Get-Date) - $lastAsked).TotalSeconds -lt 8) { continue }
        $lastAsked = Get-Date

        $state = Invoke-ZoHelper -Arguments @('--employee-number-status', $Name)
        if ($state -and (Test-ObjectHasProperty $state 'paired') -and $state.paired) {
            Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
            return $true
        }
    }

    Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
    return $false
}

function Set-EmployeeWhatsApp {
    <#
        Gives one AI employee a WhatsApp number of their own, and links it.

        A number used to be written on a note here and joined up never. That
        was honest about itself and still wrong: the owner picked WhatsApp,
        answered the question, and ended up with an employee nobody could
        message.

        One bridge holds one linked device, so this is a whole second WhatsApp
        connection on their Zo - its own store, its own port, its own service.
        That machinery already existed and had never been called.
    #>
    param([string]$Name, [string]$Brief)

    $script:LastEmployeePhone = ''

    Write-Host ''
    Write-Info "$Name needs a WhatsApp number of their own."
    Write-Host ''
    Write-Info 'It has to be a spare number - not the one you use yourself, and'
    Write-Info 'a different one again for each employee. A number can only be'
    Write-Info 'joined to one of these at a time.'
    Write-Host ''
    Write-Info 'Have the phone with that SIM in front of you. You will type a'
    Write-Info 'short code into it in a moment.'
    Write-Host ''

    # Asked until it is answered or they back out. Required means required, but
    # a required question with no way out is a trap - somebody without a spare
    # SIM has to be able to leave without closing the window.
    $phone = ''
    while (-not $phone) {
        Write-Info 'What is the number? With the 60 in front, like 60123456789.'
        Write-Host ''
        Write-Brand -Text '      Number, or Enter to go back > ' -Colour Purple -NoNewline
        $typed = ([string](Read-Host)).Trim()
        if (-not $typed) {
            Write-Host ''
            Write-Info "No number, so $Name has no WhatsApp yet."
            Write-Info 'Telegram needs no SIM card at all, if that suits you better.'
            return $false
        }

        # Everything that is not a digit goes, so "+60 12-345 6789" is accepted
        # from somebody reading it off the back of a SIM pack.
        $digits = ($typed -replace '\D', '')
        if ($digits.Length -lt 8) {
            Write-Host ''
            Write-Bad 'That does not look like a full phone number.'
            Write-Info 'It needs the country code in front, like 60123456789.'
            Write-Host ''
            continue
        }
        # Their own number, the one their assistant answers on. WhatsApp would
        # allow it as a second linked device and then both would reply to the
        # same message, which reads as the product being broken.
        $ownNumber = [string](Get-Profile)['ownerPhone']
        if ($ownNumber -and $digits -eq $ownNumber) {
            Write-Host ''
            Write-Bad 'That is your own number, the one your assistant uses.'
            Write-Info 'An employee on it would be answering you instead of your'
            Write-Info 'customers, and both would reply to the same message.'
            Write-Host ''
            continue
        }
        $phone = $digits
    }

    Write-Host ''
    $result = Invoke-ZoHelper -Arguments @('--employee-number', $Name, $phone) `
        -Waiting "giving $Name their own number..."

    if (-not $result -or -not $result.ok) {
        Write-Host ''
        $code = if ($result -and (Test-ObjectHasProperty $result 'code')) { [string]$result.code } else { '' }
        switch ($code) {
            'bridge_missing' {
                Write-Bad 'Your own WhatsApp assistant has to be working first.'
                Write-Info 'Finish that step, then come back and hire again.'
            }
            'name_taken' {
                Write-Bad "$Name already has a number set up."
                Write-Info 'Let them go first if you want to give them a different one.'
            }
            'no_port' {
                Write-Bad 'This Zo has no room for another number just now.'
            }
            default {
                Write-Bad "Could not set that number up just now."
                if ($result -and (Test-ObjectHasProperty $result 'error') -and $result.error) {
                    Write-Info "  $($result.error)"
                }
                Write-Info 'Nothing is lost. Try this step again in a moment.'
            }
        }
        return $false
    }

    $script:LastEmployeePhone = $phone

    if ((Test-ObjectHasProperty $result 'alreadyPaired') -and $result.alreadyPaired) {
        Write-Good "$Name is on $phone."
    } else {
        $pairCode = if (Test-ObjectHasProperty $result 'pairCode') { [string]$result.pairCode } else { '' }
        if (-not $pairCode) {
            Write-Host ''
            Write-Bad 'That number was set up, but WhatsApp did not send a code.'
            Write-Info 'Run the setup again in a moment and it will ask for one.'
            return $true
        }

        Write-Host ''
        Write-Info "On the phone with $phone in it, open WhatsApp and go to:"
        Write-Host ''
        Write-NumberedStep 1 'Settings, then' 'Linked Devices'
        Write-NumberedStep 2 'Tap' 'Link a device'
        Write-NumberedStep 3 'Tap' 'Link with phone number instead'
        Write-NumberedStep 4 'Type this code:'
        Show-PairingCode -Code $pairCode
        Write-Info 'Take your time. This waits for you.'
        Write-Host ''

        if (-not (Wait-ForEmployeeNumber -Name $Name)) {
            Write-Info "$Name's number is set up and still waiting for that code."
            Write-Info 'Nothing expires. Run the setup again when you have typed'
            Write-Info 'it in and it will carry straight on.'
            return $true
        }
        Write-Good "$Name is on $phone."
    }

    # The responder, so the number answers as this employee rather than as the
    # owner's assistant. Never enabled here: an employee knows a job title and
    # nothing about the business yet, and this number is one customers can
    # reach.
    Write-Host ''
    $null = Invoke-ZoHelper -Arguments @(
        '--responder', $Name, '--assistant-name', $Name, '--brief', $Brief
    ) -Waiting "teaching $Name who they are..."

    Write-Host ''
    Write-Warn "$Name is not answering anybody yet, and that is deliberate."
    Write-Host ''
    Write-Info 'They know their job title and nothing about your business. Teach'
    Write-Info "them first - tell your Zo about $Name, what you sell, your"
    Write-Info 'prices, your hours. Then let them start answering.'
    return $true
}

function Set-EmployeeTelegram {
    <#
        Gives one employee its own Telegram, and proves it answers.

        Zo's own Telegram connects the owner's account, so an employee sitting
        on it answers as the boss. A bot is a separate identity - and it needs
        no SIM card, which is why this is the practical choice for employees
        where WhatsApp wants a spare number each.

        The owner makes the bot themselves, in Telegram, by messaging
        @BotFather. That is five taps on a phone, which is squarely inside what
        they already do, and it means the bot belongs to them rather than to us.
    #>
    param([string]$Name, [string]$Brief)

    Write-Host ''
    Write-Info "$Name needs their own Telegram. It is free, it takes a minute,"
    Write-Info 'and you do not need another phone number.'
    Write-Host ''
    Write-Info 'On your phone, in Telegram:'
    Write-Host ''
    Write-NumberedStep 1 'Search for' '@BotFather'
    Write-NumberedStep 2 'Send it' '/newbot'
    Write-NumberedStep 3 "Give it a name -" "$Name works well"
    Write-NumberedStep 4 'Give it a username ending in' 'bot'
    Write-NumberedStep 5 'It replies with a long line. Copy it.'
    Write-Host ''
    Write-Info 'That long line is what tells your Zo it may answer as this bot.'
    Write-Info 'It looks like 8123456789:AAH-abc123...'
    Write-Host ''

    Write-Brand -Text '      Paste it here (or Enter to skip) > ' -Colour Purple -NoNewline
    $botToken = ([string](Read-Host)).Trim()
    if (-not $botToken) {
        Write-Host ''
        Write-Info "No problem. $Name is saved, and you can do this any time."
        return $false
    }

    # Sent every time, so a Zo set up before this existed gets the new files.
    $null = Invoke-ZoHelper -Arguments @('--install-zo-scripts') -Waiting 'updating your Zo...'

    $result = Invoke-ZoHelper -Arguments @(
        '--telegram-employee', $Name, '--bot-token', $botToken, '--brief', $Brief
    ) -Waiting "putting $Name on Telegram..."

    if (-not $result -or -not $result.ok) {
        Write-Host ''
        # A bot already wired to something else is the common mistake, not a
        # fault, so it gets its own answer rather than "something went wrong".
        $code = if (Test-ObjectHasProperty $result 'code') { [string]$result.code } else { '' }
        if ($code -eq 'bot_in_use') {
            Write-Bad 'That one is already doing another job.'
            Write-Host ''
            Write-Info 'A Telegram bot can only work for one thing at a time, and'
            Write-Info 'that one is already connected to something else. Taking it'
            Write-Info 'over would stop whatever is using it.'
            Write-Host ''
            Write-Info "Make a new one for $Name - send /newbot to @BotFather"
            Write-Info 'again. It is free, and you can have as many as you like.'
            Write-Host ''
            if (Read-YesNo -Question 'Try again with a new bot?' -YesLabel 'Yes' -NoLabel 'Later') {
                return (Set-EmployeeTelegram -Name $Name -Brief $Brief)
            }
            return $false
        }

        Write-Bad "Could not set $Name up on Telegram just now."
        if ($result -and (Test-ObjectHasProperty $result 'error') -and $result.error) {
            Write-Info "  $($result.error)"
        }
        Write-Info 'Nothing was lost. Try this step again in a moment.'
        return $false
    }

    $username = if (Test-ObjectHasProperty $result 'username') { [string]$result.username } else { '' }
    $pairCode = if (Test-ObjectHasProperty $result 'pairCode') { [string]$result.pairCode } else { '' }

    Write-Host ''
    Write-Good "$Name is live on Telegram."
    Write-Host '        ' -NoNewline
    Write-Brand -Text "@$username" -Colour Teal
    Write-Host ''
    Write-Info "Right now $Name answers only you, nobody else. That is on"
    Write-Info 'purpose: they know their job title and nothing about your'
    Write-Info 'business yet, and a customer would believe whatever they say.'
    Write-Host ''
    # A deep link, and a QR of it, rather than a code to copy out. The code has
    # to be long enough to be unguessable - whoever says it first owns this
    # employee - and nobody types thirty-two characters into a phone by hand.
    # The screen is on a laptop and the thing that must act on it is a phone,
    # so a camera is the shortest path between them.
    $joinUrl = "https://t.me/$username`?start=$pairCode"

    Write-Info 'So teach them first. Point your phone camera at this and it'
    Write-Info 'says hello for you - nothing to type:'
    Write-Host ''
    $picture = Invoke-ZoHelper -Arguments @('--qr', $joinUrl) -Waiting 'drawing the code...'
    if ($picture -and (Test-ObjectHasProperty $picture 'qr') -and @($picture.qr).Count -gt 0) {
        foreach ($row in @($picture.qr)) {
            Write-Host '     ' -NoNewline
            Write-Brand -Text $row -Colour Teal
        }
        Write-Host ''
        Write-Info 'Or open this on your phone:'
    }
    Write-Host '        ' -NoNewline
    Write-Brand -Text $joinUrl -Colour Teal
    Write-Host ''
    Write-Info 'Then just talk to them. Tell them what you sell, your prices,'
    Write-Info 'your hours, anything. They will remember it.'
    Write-Host ''

    return (Wait-ForEmployeeTelegram -Name $Name -Username $username)
}

function Wait-ForEmployeeTelegram {
    <#
        Waits for the owner to say hello to their new employee, so the setup can
        say it worked rather than asking whether it did.
    #>
    param([string]$Name, [string]$Username)

    $deadline = (Get-Date).AddMinutes(5)
    $frames = @('◐', '◓', '◑', '◒')
    $frame = 0
    $lastAsked = [datetime]::MinValue

    while ((Get-Date) -lt $deadline) {
        Write-Host "`r      " -NoNewline
        Write-Brand -Text $frames[$frame % $frames.Count] -Colour Teal -NoNewline
        Write-Host ("  waiting for you to say hello to $Name...".PadRight(60)) -ForegroundColor $script:Ink.Muted -NoNewline
        $frame++
        Start-Sleep -Milliseconds 250

        if (((Get-Date) - $lastAsked).TotalSeconds -lt 8) { continue }
        $lastAsked = Get-Date

        $state = Invoke-ZoHelper -Arguments @('--telegram-employee-status', $Name)
        if ($state -and (Test-ObjectHasProperty $state 'paired') -and $state.paired) {
            Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
            Write-Good "$Name has said hello. They are yours to teach."
            Write-Host ''
            Write-Info 'When you are happy they know the job, tell your Zo to let'
            Write-Info "$Name answer your customers - or come back here and hire"
            Write-Info 'the next one.'
            return $true
        }
    }

    Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
    Write-Info "$Name is set up and waiting for you in Telegram."
    Write-Info "Say hello to @$Username whenever you like - nothing expires."
    return $true
}

function Update-HiredEmployeeChannel {
    <#
        Adds how one employee is meant to be reached to the note already kept
        for them.

        Written against the existing entry rather than as a list of its own, so
        that letting an employee go takes the number with them and there is
        never a spare number sitting against somebody who no longer works here.
    #>
    param([string]$Name, [string]$Channel, [string]$Phone)

    $team = @(Get-HiredEmployees)
    if ($team.Count -eq 0) { return }

    $updated = @()
    foreach ($member in $team) {
        if ($member.name -eq $Name) {
            # -Force so a second answer replaces the first, and so an employee
            # hired before this question existed gains the fields rather than
            # throwing.
            $member | Add-Member -NotePropertyName 'channel' -NotePropertyValue $Channel -Force
            $member | Add-Member -NotePropertyName 'phone' -NotePropertyValue $Phone -Force
        }
        $updated += $member
    }
    Set-ProfileValue -Name 'employees' -Value ($updated | ConvertTo-Json -Compress -Depth 4)
}

function Add-HiredEmployee {
    <#
        Keeps a local note of who has been hired: their name, the job they were
        hired for, and the link to their own page.

        Zo remains the authority on who exists. This is so the setup can show
        the team straight away, and so "the sales one" still means something
        six months later when the only thing on Zo is a persona called Zoe.
    #>
    param([string]$Name, [string]$Role, [string]$Title, [string]$PersonaId)

    $team = @(Get-HiredEmployees | Where-Object { $_.name -ne $Name })
    $team += [pscustomobject]@{
        name      = $Name
        role      = $Role
        title     = $Title
        personaId = $PersonaId
        hired     = (Get-Date).ToString('yyyy-MM-dd')
    }
    Set-ProfileValue -Name 'employees' -Value ($team | ConvertTo-Json -Compress -Depth 4)
}

function Get-HiredEmployees {
    <#
        The team, one object per person.

        ForEach-Object is not decoration. Windows PowerShell 5.1 hands the whole
        array back from ConvertFrom-Json as ONE object rather than as its
        members, so @(...) around it wraps the array instead of unrolling it: a
        team of three arrives as a single item, .Count says 1, and reading .name
        off it gives "Zoe Ah Meng Siti" as though that were somebody's name.
        PowerShell 7 unrolls it and the same code is fine, which is exactly how
        this survives testing and fails on a customer's machine. Unrolling it
        here means every caller gets a real list on both.
    #>
    $stored = (Get-Profile)['employees']
    if (-not $stored) { return @() }
    try { return @($stored | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return @() }
}

function Sync-HiredEmployees {
    <#
        Reconciles the local note against Zo, and returns the true team.

        Zo decides who exists. The note only remembers what Zo does not keep -
        which job somebody was hired for, and how they are meant to be reached
        - so it is a convenience and never the authority.

        Three things can have happened since it was written: somebody was
        deleted on the website, somebody was created there, or nothing changed.
        All three end with the note matching Zo. Anything else leaves the owner
        holding a list of staff that is not the staff, and these are answering
        real people - an AI employee nobody can account for is worse than none.

        Returns the note untouched when Zo cannot be reached, rather than
        emptying the team over a dropped connection.
    #>
    $known = @(Get-HiredEmployees)

    $listed = Invoke-ZoHelper -Arguments @('--employees') -Waiting 'checking who works for you...'
    if (-not $listed -or -not $listed.ok -or -not (Test-ObjectHasProperty $listed 'employees')) {
        return $known
    }

    # A plain array, not a generic List.
    #
    # Windows PowerShell 5.1 throws "Argument types do not match" on @() around
    # a List[object] - PowerShell 7 does not, so the hire screen worked here
    # and died on the machine it shipped to. Same shape as the ConvertFrom-Json
    # trap above: a collection that behaves differently on the version
    # customers actually have.
    $team = @()
    foreach ($name in @($listed.employees)) {
        $note = $known | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($note) {
            $team += $note
        } else {
            # Made on the Zo website, or by asking Zo directly. It exists and it
            # answers, so it belongs on the list even though the only thing
            # known about it is the name.
            $team += [pscustomobject]@{
                name = [string]$name; role = ''; title = ''
                personaId = ''; channel = 'none'; phone = ''; hired = ''
            }
        }
    }

    Set-ProfileValue -Name 'employees' -Value ($team | ConvertTo-Json -Compress -Depth 4)
    return $team
}

function Set-TalkToZo {
    <#
        How the owner actually reaches Zo day to day.

        This is the step everything else is for. A machine can have every tool
        installed, both apps connected and WhatsApp linked, and still be useless
        on the Monday morning because nobody ever established where the owner
        types. Claude Desktop and ChatGPT only work sitting at the computer, and
        a business owner is not at their computer.

        Three ways, and the right one depends on whether they have a spare
        number. Their own everyday number is never an option here: the bridge
        acts AS the number it links, so linking their own leaves nobody for them
        to message.
    #>
    Write-Title 'How you talk to Zo - your AI Personal Assistant'
    Write-Info 'Everything else is set up. This is where you actually talk to it.'
    Write-Host ''

    # What they picked last time, if anything, shown rather than acted on.
    #
    # This step used to skip straight past the question whenever a choice was
    # remembered, on the grounds that somebody halfway through wants to carry
    # on rather than answer again. It reads as the setup ignoring them: they
    # pick "Your AI Personal Assistant" expecting a choice and land in the
    # middle of linking WhatsApp with no idea why. Now the choice is always
    # offered, with the previous one named, and carrying on is one keypress.
    $remembered = (Get-Profile)['talkChannel']
    if ($remembered) {
        $rememberedLabel = switch ($remembered) {
            'whatsapp'      { 'WhatsApp, on a spare number' }
            'whatsapp-self' { 'WhatsApp, on your own number' }
            'telegram'      { 'Telegram' }
            'web'           { 'on the web' }
            default         { $remembered }
        }
        Write-Info "Last time you chose $rememberedLabel."
        Write-Host '        ' -NoNewline
        Write-Brand -Text ' C ' -Colour Teal -NoNewline
        Write-Host '  Carry on with that' -ForegroundColor $script:Ink.Strong
        Write-Host ''
    }
    Write-NumberedStep 1 'WhatsApp     -' 'needs a spare number, not your own'
    Write-NumberedStep 2 'Telegram     -' 'free, on your phone in two minutes'
    Write-NumberedStep 3 'On the web   -' 'nothing to set up, opens in your browser'
    Write-Host ''
    # Last, and marked, because it is not how anyone should run their business.
    # It exists so the reply path can be tried on one phone.
    Write-Host '     ' -NoNewline
    Write-Brand -Text ' 4 ' -Colour Yellow -NoNewline
    Write-Host '  🧪 Your own number ' -ForegroundColor $script:Ink.Muted -NoNewline
    Write-Host '- testing only, not for daily use' -ForegroundColor $script:Ink.Muted
    Write-Host ''
    Write-Host '        Enter  go back, changing nothing' -ForegroundColor $script:Ink.Muted
    Write-Host ''
    $prompt = if ($remembered) {
        '      Choose 1, 2, 3, 4, C, or Enter to go back > '
    } else {
        '      Choose 1, 2, 3 or 4, or Enter to go back > '
    }
    Write-Brand -Text $prompt -Colour Purple -NoNewline
    $choice = ([string](Read-Host)).Trim()

    # Carrying on with what they had. Resumes at the right place rather than
    # starting the chosen channel from the beginning.
    if ($remembered -and $choice -match '^[Cc]') {
        switch ($remembered) {
            'whatsapp'      { return (Connect-WhatsApp) }
            'whatsapp-self' { return (Connect-WhatsApp) }
            'telegram'      { return (Set-TalkToZoTelegram) }
            default {
                Write-Host ''
                Write-Info 'Your assistant lives here:'
                Write-Host '        ' -NoNewline
                Write-Brand -Text ($(if ($script:ZoWorkspaceUrl) { $script:ZoWorkspaceUrl } else { 'https://zo.computer' })) -Colour Teal
                return $true
            }
        }
    }

    switch ($choice) {
        '1' {
            Write-Host ''
            Write-Warn 'It must be a different number from your own.'
            Write-Host ''
            Write-Info 'Your assistant becomes whatever number you give it. Use the'
            Write-Info 'number you carry every day and there is nobody left for you'
            Write-Info 'to message - you would be texting yourself.'
            Write-Host ''
            if (-not (Read-YesNo -Question 'Do you have a spare number?' `
                -YesLabel 'Yes, a spare one' -NoLabel 'No, only my own')) {
                Write-Host ''
                Write-Info 'Then use Telegram for now. It costs nothing and takes two'
                Write-Info 'minutes, and you can move to WhatsApp when you have a SIM.'
                Write-Host ''
                return (Set-TalkToZoTelegram)
            }
            Set-ProfileValue -Name 'talkChannel' -Value 'whatsapp'
            Write-Host ''
            return (Connect-WhatsApp)
        }
        '2' { return (Set-TalkToZoTelegram) }
        '3' {
            Set-ProfileValue -Name 'talkChannel' -Value 'web'
            Write-Host ''
            Write-Info 'Your assistant lives here:'
            Write-Host '        ' -NoNewline
            Write-Brand -Text ($(if ($script:ZoWorkspaceUrl) { $script:ZoWorkspaceUrl } else { 'https://zo.computer' })) -Colour Teal
            Write-Host ''
            Write-Info 'Bookmark that page. It is the same assistant either way, so'
            Write-Info 'you can add WhatsApp or Telegram later without losing anything.'
            Write-Host ''
            if (Read-YesNo -Question 'Open it now?' -YesLabel 'Open it' -NoLabel 'Not now') {
                Start-Process $(if ($script:ZoWorkspaceUrl) { $script:ZoWorkspaceUrl } else { 'https://zo.computer' })
            }
            return $true
        }
        '4' { return (Set-TalkToZoSelfTest) }
        default {
            Write-Host ''
            Write-Info 'Nothing chosen. You can come back to this any time.'
            return $false
        }
    }
}

function Set-TalkToZoSelfTest {
    <#
        Your assistant in your own "Message yourself" chat.

        For the person who turns up without a spare SIM and still wants to see
        this working today. WhatsApp gives everybody a chat with themselves -
        the one people use for notes - and that becomes a private line to Zo
        with nothing to buy.

        Not how a business should run it, and the screen says so: the number is
        also the owner's real number, so the assistant is sharing a line with
        their customers. It is safe, because only messages the owner sends in
        that one chat are ever answered - a customer messaging this number is
        not in it, and gets nothing. But a spare SIM is still the right answer
        once they have one, and moving to it loses nothing.
    #>
    Write-Host ''
    Write-Title 'Your own number, to try it out'
    Write-Info 'Your assistant answers in your own chat - the one you use for'
    Write-Info 'notes to yourself.'
    Write-Host ''
    Write-Good 'Only you can talk to it.'
    # "Customers" was too narrow. It is anyone at all - friends, family, a
    # supplier, a wrong number - and someone reading the narrower version could
    # reasonably think a friend would get an answer.
    Write-Info 'Other people and customers who message your number get nothing back.'
    Write-Host ''
    Write-Warn 'Get a spare SIM later so your staff can use it too.'
    Write-Host ''

    if (-not (Read-YesNo -Question 'Set that up?' -YesLabel 'Yes, set it up' -NoLabel 'Not now')) {
        Write-Info 'No problem. Come back to this any time.'
        return $false
    }

    Set-ProfileValue -Name 'talkChannel' -Value 'whatsapp-self'
    # Straight on with it. Sending someone back to the main screen to pick a
    # second thing, right after they picked the first, reads as "nothing
    # happened" - which is exactly how it was reported.
    return (Connect-WhatsApp)
}

function Set-TalkToZoTelegram {
    <#
        Connects Telegram without the owner opening Zo at all. Zo issues the
        pairing code and the deep link, and the link is drawn as a QR so they
        can point their phone at the screen - Telegram is on the phone, and a
        link on a monitor would have to be typed out by hand.
    #>
    Write-Host ''
    Write-Info 'Setting this up for you. One moment.'

    $before = Invoke-ZoHelper -Arguments @('--telegram-status') -Waiting 'asking Zo...'
    $linkedBefore = if ($before -and $before.ok) { [int]$before.linked } else { 0 }

    $link = Invoke-ZoHelper -Arguments @('--telegram') -Waiting 'making your Telegram link...'
    if (-not $link -or -not $link.ok -or -not $link.url) {
        Write-Bad 'Could not set up Telegram just now.'
        Write-Info 'Try this step again in a moment.'
        return $false
    }

    Set-ProfileValue -Name 'talkChannel' -Value 'telegram'
    return (Wait-ForTelegramPairing -Link $link -LinkedBefore $linkedBefore)
}

function Show-TelegramInvite {
    param([object]$Link)

    Write-Host ''
    Write-Info 'Point your phone camera at this:'
    Write-Host ''
    foreach ($row in @($Link.qr)) {
        Write-Host '     ' -NoNewline
        Write-Brand -Text $row -Colour Teal
    }
    Write-Host ''
    Write-Info 'Or open this on your phone:'
    Write-Host '        ' -NoNewline
    Write-Brand -Text $Link.url -Colour Teal
    if ($Link.code) {
        Write-Host ''
        Write-Info 'Or message @zo_computer_bot on Telegram with this code:'
        Show-PairingCode -Code $Link.code
    }
}

function Wait-ForTelegramPairing {
    <#
        Same shape as the WhatsApp wait: the invite is good for a few minutes,
        so it is counted down, a fresh one is fetched when it runs out, and Zo
        is asked whether the phone has actually appeared rather than the owner
        being asked whether it worked.
    #>
    param([object]$Link, [int]$LinkedBefore)

    $inviteLifetime = [TimeSpan]::FromMinutes(3)
    $overallLimit = [TimeSpan]::FromMinutes(12)
    $started = Get-Date
    $issued = Get-Date
    $lastAsked = Get-Date
    $current = $Link

    Show-TelegramInvite -Link $current

    while ($true) {
        $now = Get-Date
        if (($now - $started) -gt $overallLimit) {
            Write-Host ''
            Write-Warn 'Leaving it there for now. Choose this step again when ready.'
            return $false
        }

        $remaining = $inviteLifetime - ($now - $issued)
        if ($remaining -le [TimeSpan]::Zero) {
            Write-Host ''
            Write-Info 'That link has expired. Getting you a fresh one...'
            $again = Invoke-ZoHelper -Arguments @('--telegram') -Waiting 'making a new link...'
            if (-not ($again -and $again.ok -and $again.url)) {
                Write-Host ''
                Write-Warn 'Could not get a new link. Choose this step again to retry.'
                return $false
            }
            $current = $again
            $issued = Get-Date
            Show-TelegramInvite -Link $current
            continue
        }

        $seconds = [int]$remaining.TotalSeconds
        Write-Host ("`r      waiting for your phone... link valid for {0}:{1:d2}   " -f `
            [int]($seconds / 60), ($seconds % 60)) -ForegroundColor $script:Ink.Muted -NoNewline

        Start-Sleep -Seconds 2
        if (((Get-Date) - $lastAsked).TotalSeconds -lt 15) { continue }
        $lastAsked = Get-Date

        $state = Invoke-ZoHelper -Arguments @('--telegram-status') -Waiting 'checking your phone...'
        if ($state -and $state.ok -and [int]$state.linked -gt $LinkedBefore) {
            Write-Host ("`r" + (' ' * 70) + "`r") -NoNewline
            Write-Good 'Telegram is connected. Message your assistant there any time.'
            return $true
        }
    }
}

function Install-WhatsAppOnZo {
    <#
        Builds the WhatsApp assistant on the owner's Zo, the first time.

        Minutes, not seconds. Zo ships an older Go than the assistant needs, so
        a new Zo fetches a toolchain and around 300MB of parts and then builds
        for a little over a minute. All of that happens on Zo, so it does not
        touch the connection on this computer.

        Watched rather than waited on. Several minutes of a still screen is
        indistinguishable from a hang, and the owner will close the window.
    #>
    $started = Invoke-ZoHelper -Arguments @('--install-whatsapp') -Waiting 'checking your Zo...'

    if (-not $started -or -not $started.ok) {
        Write-Bad 'Could not reach your Zo to set this up.'
        Write-Info 'Check the internet connection and try again.'
        return $false
    }
    if ((Test-ObjectHasProperty $started 'alreadyBuilt') -and $started.alreadyBuilt) {
        return $true
    }

    Write-Host ''
    Write-Info 'Building your assistant on Zo. This happens once, and takes a'
    Write-Info 'few minutes. It is all on Zo, so it does not use your data.'
    Write-Host ''

    $deadline = (Get-Date).AddMinutes(15)
    $frames = @('◐', '◓', '◑', '◒')
    $frame = 0
    $stage = 'getting your Zo ready'
    $lastAsked = [datetime]::MinValue

    while ((Get-Date) -lt $deadline) {
        Write-Host "`r      " -NoNewline
        Write-Brand -Text $frames[$frame % $frames.Count] -Colour Teal -NoNewline
        Write-Host ("  " + $stage.PadRight(60)) -ForegroundColor $script:Ink.Muted -NoNewline
        $frame++
        Start-Sleep -Milliseconds 250

        # Asked every ten seconds, drawn four times a second. Tying the two
        # together would leave the marker frozen between questions, which is
        # the thing it exists to disprove.
        if (((Get-Date) - $lastAsked).TotalSeconds -lt 10) { continue }
        $lastAsked = Get-Date

        $progress = Invoke-ZoHelper -Arguments @('--install-whatsapp-progress')
        if (-not $progress) { continue }
        if ((Test-ObjectHasProperty $progress 'stage') -and $progress.stage) { $stage = $progress.stage }

        if ((Test-ObjectHasProperty $progress 'built') -and $progress.built) {
            Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
            Write-Good 'Your assistant is built.'
            return $true
        }
        if ((Test-ObjectHasProperty $progress 'failed') -and $progress.failed) {
            Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
            Write-Bad 'Your assistant could not be built just now.'
            Write-Info 'Try this step again. If it happens twice, contact Vimigo'
            Write-Info 'support and they will sort it out.'
            return $false
        }
    }

    Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline
    Write-Warn 'That is taking longer than expected.'
    Write-Info 'It may still finish on its own. Try this step again in a few'
    Write-Info 'minutes and it will pick up where it got to.'
    return $false
}

function Connect-WhatsApp {
    <#
        Links a phone by driving Zo from here. The owner never opens Zo, never
        explains what they want to an assistant, and never sees a command.

        One number only. The bridge holds a single linked device and refuses a
        second pair attempt with "already paired", so running this again with a
        different number adds nothing. Supporting more would mean a second
        bridge with its own store, port, Zo service and MCP entry.
    #>
    Write-Title 'Connecting WhatsApp'

    if (-not (Test-ZoTokenShape -Token (Get-ZoToken))) {
        Write-Bad 'Enter your Zo account key first.'
        return $false
    }

    # "What is this number for?" used to be asked here, offering assistant, feed
    # or employee. It made sense when WhatsApp was a row of its own; now this is
    # only ever reached from the assistant step, so the answer is always the
    # same one - and asking a question whose answer you already have makes an
    # owner wonder whether the previous screen counted.
    #
    # The spare-number warning it carried lives on the channel screen, which is
    # where the choice is actually made.

    # Built before anything is asked of it. Without this the first thing a new
    # customer sees is "the bridge is not installed on Zo yet", which was true
    # of every Zo except the one this was developed against.
    if (-not (Install-WhatsAppOnZo)) { return $false }

    Write-Host ''
    Write-Info 'Which WhatsApp number should your assistant use?'
    Write-Info 'Include the country code, digits only. For Malaysia that looks'
    Write-Info 'like 60123456789.'

    # Offered back, never assumed. Re-pairing the same number is the common
    # case after a phone unlinks the device, and retyping it is the sort of
    # small friction that makes someone give up.
    # Initialised before the branch below. Assigning it only inside the
    # remembered-number branch leaves it unset on a first run, and reading an
    # unset variable throws under Set-StrictMode - which took out the whole
    # step for exactly the people who had never used it.
    $phone = ''

    $remembered = (Get-Profile)['whatsappPhone']
    if ($remembered) {
        Write-Host ''
        Write-Info "Last time you used $remembered."
        if (Read-YesNo -Question 'Use that number again?' -YesLabel 'Yes, use it' -NoLabel 'Use a different one') {
            $phone = $remembered
        }
    }

    if (-not $phone) {
        Write-Host ''
        Write-Brand -Text '      Phone number (or Enter to go back) > ' -Colour Purple -NoNewline
        $phone = ([string](Read-Host)).Trim()
    }
    if (-not $phone) { Write-Info 'Nothing entered, so nothing was changed.'; return $false }

    # Named as well as numbered. "Which one is 60123456789" is a question
    # nobody should have to answer six months later, and once a business runs
    # more than one line the name is the only thing that tells them apart.
    $label = (Get-Profile)['whatsappLabel']
    if (-not $label) {
        Write-Host ''
        Write-Info 'What should we call this number? Something you will recognise,'
        Write-Info 'like Sales, Support, or My phone.'
        Write-Host ''
        Write-Brand -Text '      Name for this number > ' -Colour Purple -NoNewline
        $label = ([string](Read-Host)).Trim()
        if (-not $label) { $label = 'My phone' }
        Set-ProfileValue -Name 'whatsappLabel' -Value $label
    }
    Write-Host ''
    Write-Info "Setting up $label ($phone)."

    Write-Host ''
    # Honest about the wait. The first time on a new Zo this builds the
    # assistant from source - measured at just over a minute for the build
    # alone, plus around 300MB of downloads, because Zo ships an older Go than
    # the assistant needs. It happens on Zo, not on this computer, so it does
    # not depend on the wifi in the room.
    Write-Info 'Asking Zo to connect it.'
    Write-Info 'The first time on a new Zo this takes a few minutes, because'
    Write-Info 'your assistant is being built. After that it is seconds.'
    $result = Invoke-ZoHelper -Arguments @('--pair', $phone)

    if (-not $result) {
        Write-Bad 'Could not reach Zo to set this up.'
        Write-Info 'Check the internet connection and try again.'
        return $false
    }
    if (-not $result.ok) {
        Write-Bad $result.error
        return $false
    }

    # Remembered so that hiring an employee can refuse this number later. Two
    # bridges on one number both answer the same message, and the owner sees
    # their assistant reply twice and concludes it is broken.
    Set-ProfileValue -Name 'ownerPhone' -Value $phone

    if ($result.alreadyPaired) {
        Write-Good 'That number is already connected.'
        # Not "nothing to do". A number linked before this setup could make one
        # answer is linked and silent, and pairing it again would change
        # nothing at all.
        return (Enable-WhatsAppReplies)
    }
    if (-not $result.code) {
        Write-Warn 'Zo did not give a code back this time. Try this step again.'
        return $false
    }

    # Remembered only once Zo accepted it, so a typo never gets offered back.
    Set-ProfileValue -Name 'whatsappPhone' -Value $phone

    Show-PairingCode -Code $result.code
    Write-Info 'Now on your phone:'
    Write-Host ''
    Write-NumberedStep 1 'Open' 'WhatsApp'
    Write-NumberedStep 2 'Tap Settings, then' 'Linked Devices'
    Write-NumberedStep 3 'Tap' 'Link a device'
    Write-NumberedStep 4 'Choose' 'Link with phone number instead'
    Write-NumberedStep 5 'Type in the code above'

    if (-not (Wait-ForWhatsAppPairing -Phone $phone)) { return $false }

    # Linking is only half of it. Until this runs, the number collects messages
    # and answers nobody.
    return (Enable-WhatsAppReplies)
}

function Read-AllowedNumbers {
    <#
        Who is allowed to talk to the assistant.

        Required, not optional. This assistant can read the owner's mail, their
        calendar and their files, so anyone who has the number could otherwise
        ask it anything - and a number handed out to customers, or reused from
        an old SIM, is a number strangers already have.

        Returns a comma separated list, or an empty string if the owner backs
        out - in which case nothing is switched on at all.
    #>
    $known = @()
    $remembered = (Get-Profile)['allowedNumbers']
    if ($remembered) { $known = @($remembered -split ',' | Where-Object { $_ }) }

    Write-Host ''
    Write-Title 'Who can talk to your assistant'
    # The reason first, in two lines. Someone who does not understand why they
    # are being asked types one number to get past the screen, and the whole
    # protection is gone.
    Write-Warn 'This assistant can read your email, your calendar and your files.'
    Write-Warn 'So it answers only the numbers below. Everyone else is ignored.'
    Write-Host ''
    Write-Info 'Your own phone first. Add staff if they should use it too.'
    Write-Info 'One at a time, or several separated by commas.'
    Write-Info 'With the country code, like 60123456789.'
    Write-Info 'Blank line when you are done.'

    if ($known.Count -gt 0) {
        Write-Host ''
        Write-Info 'Already allowed:'
        foreach ($number in $known) {
            Write-Host "         • $number" -ForegroundColor $script:Ink.Muted
        }
        Write-Host ''
        if (Read-YesNo -Question 'Keep this list as it is?' -YesLabel 'Yes, keep it' -NoLabel 'Change it') {
            return ($known -join ',')
        }
        $known = @()
    }

    $collected = New-Object System.Collections.Generic.List[string]
    while ($true) {
        Write-Host ''
        $label = if ($collected.Count -eq 0) { 'Your own number > ' } else { 'Another number (or Enter to finish) > ' }
        Write-Brand -Text "      $label" -Colour Purple -NoNewline
        $entry = ([string](Read-Host)).Trim()

        if (-not $entry) {
            if ($collected.Count -gt 0) { break }
            Write-Host ''
            Write-Warn 'At least one number is needed, or your assistant cannot be'
            Write-Warn 'reached by anybody at all.'
            if (-not (Read-YesNo -Question 'Try again?' -YesLabel 'Yes' -NoLabel 'Skip this for now')) {
                return ''
            }
            continue
        }

        # Split on anything somebody might reasonably type between numbers -
        # commas, semicolons, slashes, spaces, or a new line pasted in from a
        # message. Each piece is then judged on its own, so one bad entry in a
        # pasted list does not throw away the good ones.
        foreach ($piece in ($entry -split '[,;/|\s]+')) {
            if (-not $piece) { continue }
            Add-AllowedNumber -Entry $piece -Collected $collected
        }
    }

    return ($collected -join ',')
}

function Add-AllowedNumber {
    <#
        Judges one entry and adds it if it is a usable phone number.

        Everything a real person types has to survive this: +60 12-345 6789,
        a number pasted with a space, the same one twice, and the local form
        starting with 0 - which is the one that matters, because 0123456789
        looks perfectly fine and is not a number WhatsApp knows.
    #>
    param([string]$Entry, [System.Collections.Generic.List[string]]$Collected)

    $digits = ($Entry -replace '\D', '')

    if (-not $digits) {
        Write-Bad "  `"$Entry`" has no numbers in it."
        return
    }

    # A leading 0 is the local way of writing it. Never silently corrected: the
    # country cannot be guessed from the digits, and guessing wrong puts a
    # stranger on the list.
    if ($digits.StartsWith('0')) {
        Write-Bad "  $Entry looks like a local number."
        Write-Info '     Swap the first 0 for your country code, so 012 345 6789'
        Write-Info '     becomes 60123456789.'
        return
    }
    if ($digits.Length -lt 8) {
        Write-Bad "  $Entry is too short to be a full number."
        return
    }
    if ($digits.Length -gt 15) {
        # Fifteen digits is the most any phone number in the world has.
        Write-Bad "  $Entry is too long to be a phone number."
        return
    }
    if ($Collected -contains $digits) {
        Write-Info "  $digits is already on the list."
        return
    }

    $Collected.Add($digits)
    Write-Good "  Added $digits"
}

function Enable-WhatsAppReplies {
    <#
        Makes a linked number answer.

        Pairing alone only makes Zo collect messages. Nothing reads them, so
        nothing replies - which left an assistant looking connected and silent.
        This turns on the part that answers, and proves it did rather than
        reporting that a command was sent.
    #>
    Write-Host ''
    Write-Title 'Making it answer'
    Write-Info 'Your number is linked. Now it needs to reply.'

    # The try-it-on-one-phone path. The number that was linked is the owner's
    # own, so it is the number that must be allowed - asking them to type it
    # again would be asking a question we already know the answer to.
    $selfChat = ((Get-Profile)['talkChannel'] -eq 'whatsapp-self')
    if ($selfChat) {
        $own = (Get-Profile)['whatsappPhone']
        if ($own) {
            Write-Host ''
            Write-Info "Set up for your own chat, so only you ($own) can talk to it."
            $allowed = $own
        } else {
            $allowed = Read-AllowedNumbers
        }
    } else {
        $allowed = Read-AllowedNumbers
    }

    if (-not $allowed) {
        Write-Host ''
        Write-Warn 'Left switched off, so nobody can talk to it yet.'
        Write-Info 'Choose WhatsApp again whenever you are ready.'
        return $false
    }

    # Sent every time. A Zo set up last week has last week's scripts, and this
    # is what carries a fix to it.
    $null = Invoke-ZoHelper -Arguments @('--install-zo-scripts') -Waiting 'updating your Zo...'

    # The assistant gets the same job description an AI employee would.
    #
    # Without it the owner's assistant answered as plain Zo - correct, but not
    # theirs. It is the one persona on the list that is not hireable, precisely
    # because it belongs here instead.
    $assistant = $script:AiEmployees['assistant']
    $arguments = @('--responder', 'main', '--pa', '--owner', $allowed,
        '--assistant-name', 'your assistant', '--brief', $assistant.Prompt)
    if ($selfChat) { $arguments += '--self' }
    $result = Invoke-ZoHelper -Arguments $arguments -Waiting 'switching on replies...'

    if (-not $result -or -not $result.ok) {
        Write-Bad 'It is linked, but it is not answering yet.'
        if ($result -and (Test-ObjectHasProperty $result 'error') -and $result.error) {
            Write-Info "  $($result.error)"
        }
        Write-Info 'Run this step again in a moment. Nothing was lost.'
        return $false
    }

    Set-ProfileValue -Name 'allowedNumbers' -Value $allowed
    Write-Host ''
    Write-Good 'Your assistant is answering.'
    $count = if (Test-ObjectHasProperty $result 'allowed') { [int]$result.allowed } else { 0 }
    Write-Info "It replies to $count number(s) and ignores everyone else."
    Write-Host ''
    if ($selfChat) {
        Write-Info 'Open WhatsApp, search for your own name, and type in that'
        Write-Info 'chat. It answers there, the same as it does on the web.'
    } else {
        Write-Info 'Message it from your phone and it will answer, the same as it'
        Write-Info 'does on the web. Ask it anything.'
    }
    Write-Host ''

    # Offered rather than assumed, and it is the only way to be sure. Everything
    # up to here proves the pieces are in place; this proves a message actually
    # comes back, which is the only thing the owner cares about.
    if (Read-YesNo -Question 'Send yourself a test message now?' `
        -YesLabel 'Yes, test it' -NoLabel 'No, I trust it') {
        $first = @($allowed -split ',')[0]
        Write-Host ''
        $test = Invoke-ZoHelper -Arguments @('--responder-test', 'main', $first) `
            -Waiting 'sending a test message...'
        if ($test -and $test.ok) {
            Write-Good "Sent. Watch $first - a reply should arrive within a minute."
            Write-Info 'It will be signed so you know it came from your assistant.'
        } else {
            Write-Warn 'Could not send the test just now. That does not mean it is'
            Write-Warn 'broken - message it from your phone and see.'
        }
    }
    return $true
}

function Wait-ForWhatsAppPairing {
    <#
        Watches for the phone to accept the code, and fetches a new one when the
        old expires.

        A pairing code is short-lived. Printing one and leaving is how somebody
        who took a moment to find Linked Devices ends up typing a dead code and
        being told, with no explanation, that it did not work. So the setup
        counts the code down, asks Zo whether the phone has linked, and issues a
        fresh code when the clock runs out.
    #>
    param([string]$Phone)

    $codeLifetime = [TimeSpan]::FromMinutes(2)
    $overallLimit = [TimeSpan]::FromMinutes(10)
    $started = Get-Date
    $codeIssued = Get-Date
    $lastAsked = Get-Date

    while ($true) {
        $now = Get-Date
        if (($now - $started) -gt $overallLimit) {
            Write-Host ''
            Write-Warn 'Giving the phone a rest. Choose WhatsApp again when you are ready.'
            return $false
        }

        $remaining = $codeLifetime - ($now - $codeIssued)
        if ($remaining -le [TimeSpan]::Zero) {
            Write-Host ''
            Write-Info 'That code has expired. Getting you a fresh one...'
            $again = Invoke-ZoHelper -Arguments @('--pair', $Phone) -Waiting 'asking Zo for a new code...'
            if ($again -and $again.ok -and $again.alreadyPaired) {
                Write-Host ''
                Write-Good 'WhatsApp is linked.'
                return $true
            }
            if (-not ($again -and $again.ok -and $again.code)) {
                Write-Host ''
                Write-Warn 'Could not get a new code. Choose WhatsApp again to retry.'
                return $false
            }
            $codeIssued = Get-Date
            Show-PairingCode -Code $again.code
            continue
        }

        # Redrawn every couple of seconds so the clock moves, but Zo is only
        # asked every fifteen. The lookup itself takes several seconds, and
        # tying the countdown to it would make the clock lurch.
        $seconds = [int]$remaining.TotalSeconds
        Write-Host ("`r      waiting for your phone... code valid for {0}:{1:d2}   " -f `
            [int]($seconds / 60), ($seconds % 60)) -ForegroundColor $script:Ink.Muted -NoNewline

        Start-Sleep -Seconds 2
        if (((Get-Date) - $lastAsked).TotalSeconds -lt 15) { continue }
        $lastAsked = Get-Date

        # The WhatsApp-only lookup, not the full check. The full one asks Zo
        # six questions and takes about twenty seconds, which cannot be run
        # inside a loop counting down a two-minute code.
        $state = Invoke-ZoHelper -Arguments @('--whatsapp-only') -Waiting 'checking your phone...'
        if ($state -and $state.ok -and $state.linked -eq $true) {
            Write-Host ("`r" + (' ' * 70) + "`r") -NoNewline
            Write-Good 'WhatsApp is linked. That is it done.'
            return $true
        }
    }
}

function Show-PairingCode {
    param([string]$Code)
    Write-Host ''
    Write-Brand -Text '        ┌───────────────────────┐' -Colour Teal
    Write-Brand -Text '        │  Your code:  ' -Colour Teal -NoNewline
    Write-Brand -Text $Code.PadRight(9) -Colour Yellow -NoNewline
    Write-Brand -Text '│' -Colour Teal
    Write-Brand -Text '        └───────────────────────┘' -Colour Teal
    Write-Host ''
}

function Connect-ZoAiProvider {
    <#
        Signs the owner's Zo in to a Claude or ChatGPT plan they already pay
        for, so Zo stops billing per use. Both flows need a browser, so the
        setup starts it, shows what to open, and confirms afterwards.
    #>
    param([ValidateSet('claude', 'codex')][string]$Which)

    $friendly = if ($Which -eq 'claude') { 'Claude' } else { 'ChatGPT' }
    Write-Title "Using your $friendly plan on Zo"
    Write-Info "If you already pay for $friendly, your Zo can use that plan"
    Write-Info 'instead of charging you separately each time.'
    Write-Host ''

    if (-not (Read-YesNo -Question "Do you have a paid $friendly plan?")) {
        Write-Info 'That is fine. Zo will just bill per use. Skipping this.'
        return $false
    }

    Write-Info 'Starting the sign-in. This takes a moment.'
    $result = Invoke-ZoHelper -Arguments @('--signin', $Which)

    if (-not $result -or -not $result.ok) {
        Write-Bad 'Could not start the sign-in.'
        if ($result -and $result.error) { Write-Info "  $($result.error)" }
        return $false
    }
    if ($result.alreadySignedIn) {
        Write-Good "You are already signed in to $friendly on Zo."
        Show-ZoModelStep -Friendly $friendly
        return $true
    }

    Write-Host ''
    Write-Info 'Open this page and sign in:'
    Write-Brand -Text "        $($result.url)" -Colour Teal
    if ($result.code) {
        Write-Host ''
        Write-Host '        Your code:  ' -ForegroundColor $script:Ink.Body -NoNewline
        Write-Host $result.code -ForegroundColor $script:Ink.Good
        Write-Info '        Type that into the page when it asks.'
    }
    Write-Host ''

    if (Read-YesNo -Question 'Open that page in your browser now?') {
        Start-Process $result.url
    }

    if ($result.needsCodeBack) {
        # Claude hands a code back through the browser, which has to reach the
        # sign-in still waiting on Zo.
        Write-Host ''
        Write-Info 'When the page gives you a code, paste it here.'
        $code = (Read-Host -Prompt '  Code from the page').Trim()
        if (-not $code) { Write-Info 'Nothing entered. You can run this step again.'; return $false }

        $finish = Invoke-ZoHelper -Arguments @('--signin-code', $code)
        if ($finish -and $finish.ok -and $finish.signedIn) {
            Write-Good "Your $friendly plan is connected."
            return $true
        }
        Write-Warn 'That did not go through. You can try this step again.'
        return $false
    }

    Write-Host ''
    Write-Info 'Finish signing in on that page, then come back here.'
    Show-ZoModelStep -Friendly $friendly
    return $true
}

function Show-ZoModelStep {
    <#
        Signing in is only half of it. Zo still needs the provider switched on
        in its own settings, its models ticked, and one chosen as the default,
        and none of that can be done from here: Zo's web settings are held on
        its servers, not on the machine, and the API that would change them
        rejects the key this setup holds.

        So it is spelled out instead. Reporting "signed in" and stopping would
        leave the owner with a plan they are paying for and an assistant that
        never uses it.
    #>
    param([string]$Friendly)

    Write-Host ''
    Write-Warn 'One more part, and it has to be done on the Zo website.'
    Write-Host ''
    Write-NumberedStep 1 'Scroll down to' 'Providers'
    Write-NumberedStep 2 "Click Connect next to" $Friendly
    Write-NumberedStep 3 'Click every model to' 'turn them all on'
    Write-NumberedStep 4 'Scroll back up to' 'Models'
    Write-NumberedStep 5 'Change the selected models to the ones below'
    Write-Host ''
    Write-Info 'Signing in only tells Zo who you are. Until the provider is'
    Write-Info 'switched on there, Zo will not actually use the plan you pay for.'
    Write-Host ''
    Write-Info 'What we suggest setting as the default, in this order:'
    Write-Host ''
    Write-NumberedStep 1 'Opus 5 on' 'low'
    Write-NumberedStep 2 'ChatGPT Luna on' 'xhigh'
    Write-Host ''
    Write-Info 'Opus 5 on low is quick and covered by a Claude plan, so it suits'
    Write-Info 'everyday work. Luna on xhigh thinks harder and is the one to fall'
    Write-Info 'back to. You can change either whenever you like, on this page:'
    Write-Host '        ' -NoNewline
    Write-Brand -Text (Get-ZoAiSettingsUrl -WorkspaceUrl $script:ZoWorkspaceUrl) -Colour Teal

    if (Read-YesNo -Question 'Open that page now?' -YesLabel 'Open it' -NoLabel 'Not now') {
        Start-Process (Get-ZoAiSettingsUrl -WorkspaceUrl $script:ZoWorkspaceUrl)
    }
}

function Open-ZoGoogle {
    Write-Title 'Connecting your Google apps'
    Write-Info 'This one happens on the Zo website, where Google asks your'
    Write-Info 'permission. Nobody can do that part for you.'
    Write-Host ''
    Write-Host ''
    Write-NumberedStep 1 'Find the' 'Integrations'
    Write-NumberedStep 2 'Click Connect next to' 'Gmail'
    Write-NumberedStep 3 'Sign in, then' 'tick every box Google shows'
    Write-NumberedStep 4 'Click' 'Allow'
    Write-NumberedStep 5 'Repeat for' 'Calendar, Drive and Sheets'
    Write-Host ''

    # The single most common way this goes wrong. Google presents the
    # permissions as individually tickable, people tick only what sounds
    # necessary, and the connection then half-works in ways that surface much
    # later as "the assistant cannot see my calendar".
    Write-Warn '   Please tick every box Google offers.'
    Write-Info '   Leaving one out looks fine at the time, and then your'
    Write-Info '   assistant quietly cannot do that one thing later.'
    Write-Host ''
    Write-Info 'Each app is asked for separately, so four apps means doing this'
    Write-Info 'four times. Connecting one does not connect the others.'
    Write-Host ''
    Write-Info 'You can add more than one Google account. Most people connect'
    Write-Info 'their work one and their personal one, so the assistant can see'
    Write-Info 'both calendars and both drives.'
    Write-Host ''
    Write-Info 'Not a Gmail user? Zo connects Outlook, Outlook Calendar and'
    Write-Info 'OneDrive in exactly the same way. Connect those instead.'
    Write-Host ''
    Write-Info 'While you are there, have a look at the rest of the list. Zo'
    Write-Info 'connects Notion, Dropbox, Airtable, Linear and many more.'
    Write-Info 'Anything you use every day is worth connecting.'
    Write-Host ''

    if (Read-YesNo -Question 'Open Zo in your browser now?') {
        Start-Process (Get-ZoIntegrationsUrl -WorkspaceUrl $script:ZoWorkspaceUrl)
    }

    Write-Host ''
    # Nothing is recorded on the owner's say-so. The next check asks Zo itself,
    # so a sign-in abandoned halfway still shows up as unfinished.
    Write-Info 'When you have finished, come back here. This setup will ask Zo'
    Write-Info 'directly which ones worked.'
    return $true
}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

function Read-YesNo {
    param(
        [string]$Question,
        # What each choice actually does. Bare "Yes / No" leaves the owner
        # guessing what N means, and someone who cannot see a way out closes
        # the window rather than pressing it.
        [string]$YesLabel = 'Yes',
        [string]$NoLabel = 'No'
    )
    while ($true) {
        Write-Host ''
        Write-Host "      $Question" -ForegroundColor $script:Ink.Strong
        Write-Host '         ' -NoNewline
        Write-Brand -Text ' Y ' -Colour Teal -NoNewline
        Write-Host (' ' + $YesLabel.PadRight(18)) -ForegroundColor $script:Ink.Body -NoNewline
        Write-Brand -Text ' N ' -Colour Coral -NoNewline
        Write-Host " $NoLabel" -ForegroundColor $script:Ink.Body
        Write-Brand -Text '      > ' -Colour Purple -NoNewline

        $answer = ([string](Read-Host)).Trim().ToLowerInvariant()
        switch ($answer) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            'skip' { return $false }
            default {
                Write-Host '      Please press Y or N.' -ForegroundColor $script:Ink.Muted
            }
        }
    }
}

function Wait-ForOwner {
    Write-Host ''
    Read-Host -Prompt '  Press Enter to go back to the list' | Out-Null
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

function Invoke-Fix {
    param([string]$Key)

    switch ($Key) {
        'node'        { return (Install-ManagedTool -Tool ($script:ManagedTools | Where-Object Key -eq 'node')) }
        'git'         { return (Install-ManagedTool -Tool ($script:ManagedTools | Where-Object Key -eq 'git')) }
        'python'      { return (Install-ManagedTool -Tool ($script:ManagedTools | Where-Object Key -eq 'python')) }
        'claude-app'  {
            if (Test-ClaudeDesktopInstalled) { return (Open-DesktopAppToSignIn -Which 'Claude') }
            return (Install-ClaudeDesktop)
        }
        'chatgpt-app' {
            if (Test-ChatGptDesktopInstalled) { return (Open-DesktopAppToSignIn -Which 'ChatGPT') }
            return (Install-ChatGptDesktop)
        }
        'claude-hcs'  { return (Repair-HcsServices) }
        'local-whatsapp' { return (Show-LocalWhatsAppInstall) }
        'zo-token'    { return (Set-ZoTokenInteractive) }
        'claude-mcp'  { return (Connect-ZoToClaude) }
        'chatgpt-mcp' { return (Connect-ZoToChatGpt) }
        # Always the choice screen. It offers carrying on as one keypress, which
        # is better than deciding for them - somebody picking this row expects
        # to be asked, and landing halfway through linking WhatsApp with no
        # explanation reads as the setup ignoring them.
        'talk-to-zo'  { return (Set-TalkToZo) }
        'zo-skills'   { return (Install-ZoSkills) }
        'zo-brain'    { return (Install-SecondBrain) }
        'zo-claude-code' { return (Connect-ZoAiProvider -Which 'claude') }
        'zo-codex'       { return (Connect-ZoAiProvider -Which 'codex') }
        'zo-google'   { return (Open-ZoGoogle) }
        'zo-employees' { return (Invoke-HireEmployee) }
        default       { Write-Bad "Nothing to do for '$Key'."; return $false }
    }
}

# Steps the setup can start but cannot finish: the owner has to restart an app,
# sign in on a website, or type a code into their phone. Running straight on to
# the next one while they are still doing it is how a setup ends up reporting
# that nothing worked.
$script:OwnerCompletes = @(
    'claude-mcp', 'chatgpt-mcp',
    'zo-claude-code', 'zo-codex',
    'zo-google'
)

function Test-CheckNow {
    <#
        Re-detects a single step and says what it found.

        Returns Done ($true, $false, or $null when undeterminable) plus lines
        naming what is finished and what is not. "That does not look finished
        yet" on its own tells the owner nothing: with four Google apps they
        cannot tell which two worked, and are left to guess.
    #>
    param([string]$Key)

    $result = @{ Done = $null; Lines = @() }

    switch ($Key) {
        'claude-mcp'  { $result.Done = (Test-ClaudeMcpConfigured); return $result }
        'chatgpt-mcp' { $result.Done = (Test-CodexMcpConfigured); return $result }
    }

    $zo = Get-ZoVerification -Token (Get-ZoToken)
    if (-not $zo) { return $result }

    switch ($Key) {
        'talk-to-zo' {
            # Answering, not merely linked. A number that collects messages and
            # replies to nobody is not a working assistant.
            $answering = (Test-ObjectHasProperty $zo.whatsapp 'answering') -and ($zo.whatsapp.answering -eq $true)
            $result.Done = (($zo.whatsapp.connected -eq $true) -and $answering)
            if (-not $result.Done -and $zo.whatsapp.detail) {
                $result.Lines = @("Zo says: $($zo.whatsapp.detail)")
            }
        }
        'zo-claude-code' {
            if ($zo.aiProviders) { $result.Done = ($zo.aiProviders.claude.loggedIn -eq $true) }
        }
        'zo-codex' {
            if ($zo.aiProviders) { $result.Done = ($zo.aiProviders.codex.loggedIn -eq $true) }
        }
        'zo-google' {
            $apps = @($zo.integrations.PSObject.Properties)
            if ($apps.Count -gt 0) {
                $done = @($apps | Where-Object { $_.Value.connected -eq $true })
                $result.Done = ($done.Count -eq $apps.Count)
                $result.Lines = @($apps | ForEach-Object {
                    $label = if ($script:GoogleApps.Contains($_.Name)) { $script:GoogleApps[$_.Name] } else { $_.Name }
                    if ($_.Value.connected -eq $true) { "ok|$label" } else { "no|$label" }
                })
            }
        }
    }
    return $result
}

function Wait-ForOwnerStep {
    <#
        Holds until the owner says they are finished, then checks whether they
        really are. Their word alone never marks anything done - the answer
        comes from looking again.
    #>
    param([object]$Check)

    Write-Host ''
    Write-Info 'Take your time. Nothing else will happen until you are ready.'

    while ($true) {
        if (-not (Read-YesNo -Question 'Have you finished that step?' -YesLabel 'Yes, check it' -NoLabel 'Skip this for now')) {
            Write-Host ''
            Write-Info 'Skipped. You can come back to it any time.'
            return $false
        }

        Write-Host ''
        $result = Test-CheckNow -Key $Check.Key

        if ($result.Done -eq $true) {
            Write-Good "$($Check.Title) is done."
            return $true
        }
        if ($null -eq $result.Done) {
            Write-Warn 'Could not check that just now, so it has been left as it is.'
            return $false
        }

        Write-Host ''
        Write-Warn 'Not quite finished. Here is where it stands:'
        Write-Host ''
        foreach ($line in $result.Lines) {
            if ($line -match '^(ok|no)\|(.+)$') {
                if ($Matches[1] -eq 'ok') {
                    Write-Host '           ' -NoNewline
                    Write-Brand -Text '✓' -Colour Teal -NoNewline
                    Write-Host "  $($Matches[2])" -ForegroundColor $script:Ink.Body
                } else {
                    Write-Host '           ·  ' -ForegroundColor $script:Ink.Muted -NoNewline
                    Write-Host $Matches[2].PadRight(14) -ForegroundColor $script:Ink.Body -NoNewline
                    Write-Host 'still to connect' -ForegroundColor $script:Ink.Warn
                }
            } else {
                Write-Info "   $line"
            }
        }
        Write-Host ''

        if ($Check.Key -eq 'claude-mcp' -or $Check.Key -eq 'chatgpt-mcp') {
            Write-Info 'The app only reads its settings when it starts, so it has'
            Write-Info 'to be closed completely and opened again.'
            Write-Host ''
        }

        # Said plainly, because it is true and because someone who thinks they
        # are stuck will close the window rather than press N.
        Write-Info 'These are recommendations, not requirements. Skipping is'
        Write-Info 'fine and you can finish them whenever you like.'

        if (-not (Read-YesNo -Question 'What would you like to do?' -YesLabel 'Check again' -NoLabel 'Skip and move on')) {
            Write-Host ''
            Write-Info 'Left as it is. Moving on.'
            return $false
        }
    }
}

function Reset-AiEmployees {
    <#
        Lets the owner take an AI employee off the books so the hiring can be
        run again.

        Each one is named individually rather than offering "delete them all",
        because a persona may be doing real work by then and a list of names is
        the only thing that tells the owner which is which.
    #>
    Write-Title 'Your AI employees'

    $listed = Invoke-ZoHelper -Arguments @('--employees') -Waiting 'asking Zo who works here...'
    if (-not $listed -or -not $listed.ok) {
        Write-Bad 'Could not reach Zo to check.'
        return
    }

    $employees = @($listed.employees)
    if ($employees.Count -eq 0) {
        Write-Info 'Nobody is hired yet, so there is nothing to undo.'
        return
    }

    Write-Info 'Currently hired:'
    Write-Host ''
    $index = 0
    foreach ($name in $employees) {
        $index++
        Write-Host '     ' -NoNewline
        Write-Brand -Text " $index " -Colour Yellow -NoNewline
        Write-Host "  $name" -ForegroundColor $script:Ink.Strong
    }
    Write-Host ''
    Write-Info 'Letting one go removes them from Zo. Their work is not deleted.'
    Write-Host ''
    Write-Brand -Text "      Which one? 1 to $($employees.Count), or Enter to keep them all > " -Colour Purple -NoNewline
    $choice = 0
    if (-not [int]::TryParse(([string](Read-Host)).Trim(), [ref]$choice)) {
        Write-Host ''
        Write-Info 'Nobody was let go.'
        return
    }
    if ($choice -lt 1 -or $choice -gt $employees.Count) {
        Write-Host ''
        Write-Info 'Nobody was let go.'
        return
    }

    $target = $employees[$choice - 1]
    Write-Host ''
    if (-not (Read-YesNo -Question "Let $target go?" -YesLabel 'Yes, remove them' -NoLabel 'No, keep them')) {
        Write-Info 'Kept.'
        return
    }

    # Their number goes back first, while the note still says they had one.
    #
    # Left behind, the bridge keeps a phone linked to an employee who no longer
    # exists, holds its port, and restarts with the Zo forever. The number is
    # archived rather than deleted, so a mistake here is recoverable.
    $note = @(Get-HiredEmployees | Where-Object { $_.name -eq $target }) | Select-Object -First 1
    if ($note -and (Test-ObjectHasProperty $note 'channel') -and $note.channel -eq 'whatsapp') {
        $null = Invoke-ZoHelper -Arguments @('--employee-number-remove', $target) `
            -Waiting "taking back $target's number..."
    }

    $result = Invoke-ZoHelper -Arguments @('--fire', $target) -Waiting "removing $target..."
    if ($result -and $result.ok) {
        # The local note goes too, or the team list keeps showing somebody who
        # no longer exists on Zo.
        $remaining = @(Get-HiredEmployees | Where-Object { $_.name -ne $target })
        Set-ProfileValue -Name 'employees' -Value ($remaining | ConvertTo-Json -Compress -Depth 4)
        Write-Host ''
        Write-Good "$target has been removed."
        Write-Info 'Choose "Hire AI employees" on the main screen to hire again.'
    } else {
        Write-Bad 'Could not remove them just now.'
    }
}

function Reset-WhatsAppAssistant {
    <#
        Puts the WhatsApp assistant back to before it was set up, so the whole
        flow can be run again.

        Two depths, because they cost very different things. Switching replies
        off and forgetting the answers is instant and free. Unlinking the phone
        means finding a pairing code again, and is asked for separately.

        The message history is never touched. It lives in the bridge's own
        store and can be months of a business's conversations; nothing here
        deletes it, and nothing here ever should.
    #>
    Write-Host ''
    Write-Title 'Set up how you talk to Zo again'

    # Someone on Telegram or the web has no WhatsApp assistant to undo, and
    # offering to switch off replies they never turned on is a question with no
    # meaning. Forget the choice and let them make it again.
    $channel = (Get-Profile)['talkChannel']
    if ($channel -and $channel -notlike 'whatsapp*') {
        Set-ProfileValue -Name 'talkChannel' -Value ''
        Write-Info 'Forgotten. Choose "Your AI Personal Assistant" to set it up again.'
        Write-Host ''
        Write-Info 'Nothing on Zo was changed - your Telegram is still linked.'
        return
    }

    Write-Info 'This switches replies off and forgets who was allowed to talk'
    Write-Info 'to it, so you can go through the setup from the top.'
    Write-Host ''
    Write-Good 'Your messages are kept. Nothing in WhatsApp is deleted.'
    Write-Host ''

    if (-not (Read-YesNo -Question 'Do that?' -YesLabel 'Yes, do it' -NoLabel 'No, leave it')) {
        Write-Info 'Nothing was changed.'
        return
    }

    Write-Host ''
    $unlink = Read-YesNo -Question 'Also unlink the phone, to test the linking too?' `
        -YesLabel 'Yes, unlink it' -NoLabel 'No, keep it linked'

    # The deepest option, and the slowest, so it is asked for last and only
    # when the one above was already accepted. Unlinking is the common case;
    # tearing the whole thing down and building it again is not.
    $remove = $false
    if ($unlink) {
        Write-Host ''
        Write-Warn 'Or remove it completely and build it fresh next time?'
        Write-Info 'That takes a few extra minutes to set up again. Your messages'
        Write-Info 'are still kept - nothing is deleted, only set aside.'
        Write-Host ''
        $remove = Read-YesNo -Question 'Remove it completely?' `
            -YesLabel 'Yes, remove it all' -NoLabel 'No, just unlink'
    }

    $arguments = @('--reset-zo', '--replies')
    if ($remove) { $arguments += '--whatsapp-remove' }
    elseif ($unlink) { $arguments += '--whatsapp' }

    $result = Invoke-ZoHelper -Arguments $arguments -Waiting 'putting it back...'
    if (-not $result -or -not $result.ok) {
        Write-Host ''
        Write-Bad 'Could not reach your Zo, so nothing on it was changed.'
        return
    }

    # Only after Zo confirmed. Clearing these first would leave the setup
    # thinking there is nothing to do while the assistant is still answering.
    Set-ProfileValue -Name 'talkChannel' -Value ''
    Set-ProfileValue -Name 'allowedNumbers' -Value ''
    if ($unlink) { Set-ProfileValue -Name 'whatsappPhone' -Value '' }

    Write-Host ''
    Write-Good 'Done. Your assistant has stopped replying.'
    if ($remove) {
        Write-Info 'It was removed completely. Setting it up again takes a few'
        Write-Info 'minutes longer, because it gets built fresh.'
    } elseif ($unlink) {
        Write-Info 'The phone is unlinked too, so you will get a fresh pairing code.'
    } else {
        Write-Info 'The phone is still linked, so you can skip straight past that.'
    }
    Write-Host ''
    Write-Info 'Choose "Your AI Personal Assistant" on the main screen to start again.'
}

function Reset-VimigoSetup {
    <#
        Puts the machine back to how it was, at one of two depths.

        Forget: the Zo key, the remembered answers, and this setup's own entry
        in each AI app's config. Everything else is left alone. This is what
        "test it as a new customer would see it" actually needs, and it is
        quick and harmless.

        Remove: the above, plus uninstalling the tools THIS SETUP installed.
        Never anything that was already on the machine - a computer that had
        Node before any of this ran is one where removing Node breaks whatever
        was using it. Nothing here touches Claude Desktop or ChatGPT either,
        since the owner may well have been using those already.
    #>
    Write-Title 'Start over'
    Write-Info 'This undoes what the setup did, so you can run it again from'
    Write-Info 'the beginning. Useful for testing what a new customer sees.'
    Write-Host ''
    Write-Info 'You can undo just one part, or the whole thing:'
    Write-Host ''
    # Three, not four. "Forget the channel" and "set the WhatsApp assistant up
    # again" were separate options that did the same thing to anyone on
    # WhatsApp, which is nearly everyone - choosing the channel now runs the
    # linking itself, so undoing one is undoing the other.
    Write-NumberedStep 1 'How you talk to Zo -' 'your AI Personal Assistant, from the top'
    Write-NumberedStep 2 'Your AI employees  -' 'let one go, so you can hire again'
    Write-NumberedStep 3 'Everything         -' 'the above, plus the programs this setup'
    Write-Host '                                installed and your saved Zo key' -ForegroundColor $script:Ink.Muted
    Write-Host ''
    # The way out, written down.
    #
    # Pressing Enter already left every one of these screens without changing
    # anything, and not one of them said so. Somebody who opens this menu and
    # does not want any of it has no visible way back, and the only exit they
    # can see is closing the window - which loses the whole run.
    Write-Host '        Enter  go back, changing nothing' -ForegroundColor $script:Ink.Muted
    Write-Host ''
    Write-Brand -Text '      Choose 1, 2 or 3, or Enter to go back > ' -Colour Purple -NoNewline
    $scope = ([string](Read-Host)).Trim()

    if ($scope -eq '1') { Reset-WhatsAppAssistant; return }

    if ($scope -eq '2') {
        Reset-AiEmployees
        return
    }

    if ($scope -ne '3') {
        Write-Host ''
        Write-Info 'Nothing was changed.'
        return
    }

    Write-Host ''

    # Git is never uninstalled, even when this setup installed it. Too much
    # else reaches for it - other tools, other installers, anything the owner
    # sets up later - and taking it away to tidy up our own work is a poor
    # trade for the few hundred megabytes it saves.
    $neverRemove = @('git')
    $ours = @(Get-InstalledByUs | Where-Object { $neverRemove -notcontains $_ })

    Write-Info 'It will always:'
    Write-Host ''
    Write-NumberedStep 1 'Forget your' 'Zo account key'
    Write-NumberedStep 2 'Forget your remembered' 'phone number and Zo address'
    Write-NumberedStep 3 'Remove the Zo entry from' 'Claude Desktop and ChatGPT'
    Write-Host ''
    Write-Info 'Your own settings in those apps are kept. Only the entry this'
    Write-Info 'setup added is taken out.'
    Write-Host ''

    if ($ours.Count -gt 0) {
        Write-Info 'It can also uninstall what this setup installed for you:'
        Write-Host ''
        foreach ($key in $ours) {
            $tool = $script:ManagedTools | Where-Object Key -eq $key | Select-Object -First 1
            if ($tool) { Write-Host "           - $($tool.Title)" -ForegroundColor $script:Ink.Body }
        }
        Write-Host ''
        Write-Info 'Anything that was already on this computer before the setup'
        Write-Info 'ran is never touched, and Git is always kept because other'
        Write-Info 'programs rely on it.'
    } else {
        Write-Info 'This setup has not installed anything on this computer, so'
        Write-Info 'there is nothing to uninstall.'
    }
    Write-Host ''

    if (-not (Read-YesNo -Question 'Start over?' -YesLabel 'Yes, start over' -NoLabel 'No, leave everything')) {
        Write-Info 'Nothing was changed.'
        return
    }

    $alsoUninstall = $false
    if ($ours.Count -gt 0) {
        $alsoUninstall = Read-YesNo `
            -Question 'Also uninstall the tools listed above?' `
            -YesLabel 'Yes, uninstall them' -NoLabel 'No, keep them'
    }

    Write-Host ''
    Write-Info 'Forgetting your Zo account key...'
    Remove-ZoToken

    Write-Info 'Forgetting your remembered answers...'
    $profilePath = Get-ProfilePath
    if (Test-Path -LiteralPath $profilePath) { Remove-Item -LiteralPath $profilePath -Force }
    $script:ZoWorkspaceUrl = ''

    foreach ($client in @(
        @{ Name = 'Claude Desktop'; Path = (Resolve-ClaudeConfigPath); Kind = 'json' },
        @{ Name = 'ChatGPT';        Path = $script:CodexConfigPath;  Kind = 'toml' }
    )) {
        if (-not (Test-Path -LiteralPath $client.Path)) { continue }
        Write-Info "Removing the Zo entry from $($client.Name)..."
        try {
            $null = Backup-ConfigFile -Path $client.Path
            if ($client.Kind -eq 'json') {
                $document = Get-Content -LiteralPath $client.Path -Raw | ConvertFrom-Json -ErrorAction Stop
                if (Test-ObjectHasProperty -Object $document -Name 'mcpServers') {
                    $document.mcpServers.PSObject.Properties.Remove($script:ZoMcpEntryName)
                    Write-TextFile -Path $client.Path -Text ($document | ConvertTo-Json -Depth 12)
                }
            } else {
                $existing = Get-Content -LiteralPath $client.Path -Raw
                $trimmed = Remove-TomlSection -Content $existing -Header "[mcp_servers.$script:ZoMcpEntryName]"
                Write-TextFile -Path $client.Path -Text ($trimmed + "`n")
            }
        } catch {
            Write-Warn "Could not tidy $($client.Name), so it was left as it is."
        }
    }

    if ($alsoUninstall) {
        foreach ($key in $ours) {
            $tool = $script:ManagedTools | Where-Object Key -eq $key | Select-Object -First 1
            if (-not $tool) { continue }
            Write-Info "Uninstalling $($tool.Title)..."
            & winget.exe uninstall --id $tool.WingetId --exact --silent `
                --accept-source-agreements 2>&1 | Out-Null
        }
        Update-SessionPath
    }

    Write-Host ''
    Write-Good 'Done. This computer is back to how it started.'
    Write-Info 'Nothing on your Zo was changed: WhatsApp, Google and your plans'
    Write-Info 'are all still connected there.'
    Write-Host ''
}

function Invoke-FixEverything {
    <#
        Works through everything outstanding in one pass, numbering the steps so
        the owner can see how far along they are. One failure never abandons the
        rest: a machine where Python will not install should still end up with a
        working Zo connection.

        Returns the keys that did not finish, so the closing screen can be
        honest about what is left rather than claiming success for all of it.
    #>
    param([object[]]$Checks)

    $outstanding = @($Checks | Where-Object { $_.Status -ne 'ok' })
    if ($outstanding.Count -eq 0) { return @() }

    $unfinished = New-Object System.Collections.Generic.List[object]
    $total = $outstanding.Count
    $number = 0

    # Everything on this list needs the Zo key. Without one they cannot work,
    # and running them anyway produced what Tengku saw: step after step
    # failing with "could not reach your Zo" while the setup marched on, for a
    # man who had just been told to go and sign up.
    $needsZo = @(
        'claude-mcp', 'chatgpt-mcp', 'zo-claude-code', 'zo-codex',
        'zo-skills', 'zo-brain', 'zo-google', 'talk-to-zo', 'zo-employees'
    )
    $announcedNoKey = $false

    foreach ($check in $outstanding) {
        $number++

        if ($needsZo -contains $check.Key -and -not (Test-ZoTokenShape -Token (Get-ZoToken))) {
            # Said once, not nine times. Nine identical failures read as nine
            # separate faults.
            if (-not $announcedNoKey) {
                Write-Host ''
                Write-Warn 'Everything from here needs your Zo account key, so the'
                Write-Warn 'rest is waiting for you.'
                Write-Host ''
                Write-Info 'Run this setup again once you have signed up and it will'
                Write-Info 'carry straight on from here.'
                Write-Host ''
                $announcedNoKey = $true
            }
            $unfinished.Add($check)
            continue
        }

        Show-StepHeader -Number $number -Total $total -Title $check.Title

        $succeeded = $false
        try {
            $succeeded = [bool](Invoke-Fix -Key $check.Key)
        } catch {
            Write-Bad "Could not finish this: $($_.Exception.Message)"
            $succeeded = $false
        }

        # A step the owner has to finish elsewhere - restarting an app, signing
        # in on a website, typing a code into a phone - waits here. Charging on
        # to the next one while they are still on their phone is how a setup
        # ends up reporting that nothing worked.
        if ($succeeded -and $script:OwnerCompletes -contains $check.Key) {
            $succeeded = Wait-ForOwnerStep -Check $check
        }

        if (-not $succeeded) { $unfinished.Add($check) }

        Write-Host ''
        Show-ProgressBar -Done $number -Total $total
    }

    return $unfinished
}

function Show-TeamList {
    <#
        Who works for the business, read from Zo.

        Its own screen because "do I still have that sales one" is a question
        people actually ask, and hunting for it inside the hiring flow means
        risking hiring another by mistake.
    #>
    Write-Title 'Your AI employees'

    $team = @(Sync-HiredEmployees)
    if ($team.Count -eq 0) {
        Write-Info 'Nobody works for you yet.'
        Write-Host ''
        Write-Info 'Press E on the main screen to hire your first one. They take'
        Write-Info 'about a minute each.'
        return
    }

    Write-Info "$($team.Count) working for you:"
    Write-Host ''
    foreach ($member in $team) {
        Write-Host '        ' -NoNewline
        Write-Brand -Text ' • ' -Colour Teal -NoNewline
        Write-Host "  $(([string]$member.name).PadRight(16))" -ForegroundColor $script:Ink.Strong -NoNewline
        $what = if ($member.title) { [string]$member.title } else { 'made on the Zo website' }
        Write-Host $what.PadRight(24) -ForegroundColor $script:Ink.Muted -NoNewline
        $where = if ($member.channel -and $member.channel -ne 'none') {
            "on $($member.channel)"
        } else {
            'no way to reach them yet'
        }
        Write-Host $where -ForegroundColor $script:Ink.Muted
    }
    Write-Host ''
    Write-Info 'To change what one of them does, just tell your Zo. Say'
    Write-Info '"Joe should also handle refunds" and it will sort it out.'
    Write-Host ''
    Write-Info 'Their pages, to edit or remove them:'
    Write-Host '        ' -NoNewline
    Write-Brand -Text (Get-ZoPersonasUrl -WorkspaceUrl $script:ZoWorkspaceUrl) -Colour Teal
}

function Read-StartChoice {
    <#
        The whole setup is one keypress.

        Picking single rows out of order used to be offered and is not any
        more. The list is in the order it is for a reason - skills, then
        access, then where you talk to it, then hiring - and someone choosing
        row 14 first gets an assistant with nothing behind it and concludes the
        product does not work. Enter does the lot, in order.

        The letters are for afterwards: changing something already set up, not
        for building it in a different sequence.
    #>
    param([int]$RowCount)

    Show-MainOptions
    return (Read-Host -Prompt '     ').Trim()
}

function Test-Prerequisites {
    if (-not (Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue)) {
        Write-Bad 'This computer does not have the Windows package installer (winget).'
        Write-Info 'Open the Microsoft Store, search for "App Installer", and install it.'
        Write-Info 'Then run this setup again.'
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Dot-sourcing this file loads the functions without starting the menu, which is
# how the acceptance test drives the config writes against throwaway paths.
if ($MyInvocation.InvocationName -eq '.') { return }

if (-not (Test-Prerequisites)) { exit 2 }

# Remembered from an earlier run, so the very first screen can already link to
# the owner's own Zo rather than waiting for a check to rediscover it.
Restore-ZoWorkspaceUrl

Set-VimigoTheme

if ($Check) {
    Show-Checks -Checks (Get-AllChecks)
    Write-Info 'Nothing was changed. Run without -Check to fix anything.'
    Write-Host ''
    Reset-Theme
    exit 0
}

# The setup checks first, every time, and picks up wherever the machine
# actually is. That is what makes a half-finished setup safe to re-run after a
# restart: nothing is remembered between runs, so nothing can be remembered
# wrongly. Anything already done is simply detected as done.

# The last resort, below every try/catch in the script.
#
# Individual steps are wrapped so a failure returns to the menu. This catches
# whatever those miss, so the very worst case is one plain sentence rather than
# a red PowerShell error, which to a non-technical owner reads as "this product
# is broken" - and, with the window closing behind it, leaves them with nowhere
# to go.
trap {
    Write-SetupLog "unexpected stop: $($_.Exception.Message)"
    Write-Host ''
    Write-Bad '      Something unexpected happened, so the setup stopped here.'
    Write-Info '      Nothing was left in a state a second run cannot pick up.'
    Write-Info '      Start it again, and it carries on from where it got to.'
    Write-Info '      If it stops here again, contact Vimigo support.'
    Write-Host ''
    exit 1
}

Clear-Screen
Show-Logo
Write-Host '      Checking what you already have...' -ForegroundColor $script:Ink.Body
Write-Host ''

while ($true) {
    $checks = @(Get-AllChecks)
    Show-Checks -Checks $checks

    $outstanding = @($checks | Where-Object { $_.Status -ne 'ok' })

    # Hiring is optional, so not hiring is not an unfinished setup.
    #
    # Counted as outstanding, "Hire AI employees" is a row that can only be
    # cleared by hiring somebody - so an owner who wants an assistant and no
    # employees never reaches the finished screen, and the menu they need in
    # order to manage what they built never appears. The row stays on the
    # checklist, because it is worth knowing it is there.
    $finished = -not ($outstanding | Where-Object { $_.Key -ne 'zo-employees' })

    # One menu, whether the checklist is finished or not. It used to be two,
    # and the finished one was the shorter - so somebody who came back the next
    # day to hire a second employee met fewer options than they had the first
    # time, on a screen that had thrown the checklist away to say "all done".
    if ($finished) {
        Show-AllDone -RestartNeeded $false
        Write-Brand -Text '      > ' -Colour Purple -NoNewline
        $choice = ([string](Read-Host)).Trim()
    } else {
        # The optional row is not counted, or the number disagrees with the
        # screen: it would say one thing is left on a setup that has already
        # decided it is finished.
        $needed = @($outstanding | Where-Object { $_.Key -ne 'zo-employees' }).Count
        Write-Host ("      {0} thing(s) left. This setup can do them for you." -f $needed) -ForegroundColor $script:Ink.Body
        Write-Host ''
        $choice = Read-StartChoice -RowCount $checks.Count
    }

    if ($choice -match '^[Qq]') { Write-Host ''; Write-Info 'Nothing was changed. Bye.'; Write-Host ''; break }

    if ($choice -match '^[Ee]') {
        Clear-Screen
        Show-Banner
        $null = Invoke-Guarded -Whats 'hiring an AI employee' -Action { Invoke-HireEmployee }
        Read-Host -Prompt '      Press Enter to go back' | Out-Null
        Clear-Screen
        Show-Banner
        Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
        Write-Host ''
        continue
    }

    if ($choice -match '^[Tt]') {
        Clear-Screen
        Show-Banner
        $null = Invoke-Guarded -Whats 'listing your AI employees' -Action { Show-TeamList }
        Read-Host -Prompt '      Press Enter to go back' | Out-Null
        Clear-Screen
        Show-Banner
        Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
        Write-Host ''
        continue
    }

    if ($choice -match '^[Mm]') {
        Clear-Screen
        Show-Banner
        $null = Invoke-Guarded -Whats 'your company second brain' -Action { Install-SecondBrain }
        Read-Host -Prompt '      Press Enter to go back' | Out-Null
        Clear-Screen
        Show-Banner
        Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
        Write-Host ''
        continue
    }

    if ($choice -match '^[Zz]') {
        $where = if ($script:ZoWorkspaceUrl) { $script:ZoWorkspaceUrl } else { 'https://zo.computer' }
        Write-Host ''
        Write-Info 'Opening your Zo...'
        try { Start-Process $where } catch {
            Write-Info 'Could not open it. Type this into your browser:'
            Write-Host '        ' -NoNewline
            Write-Brand -Text $where -Colour Teal
        }
        Start-Sleep -Seconds 2
        Clear-Screen
        Show-Banner
        Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
        Write-Host ''
        continue
    }

    if ($choice -match '^[Aa]') {
        Clear-Screen
        Show-Banner
        $null = Invoke-Guarded -Whats 'setting up your assistant' -Action { Reset-WhatsAppAssistant }
        Read-Host -Prompt '      Press Enter to check again' | Out-Null
        Clear-Screen
        Show-Banner
        Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
        Write-Host ''
        continue
    }

    if ($choice -match '^[Ss]') {
        Clear-Screen
        Show-Banner
        $null = Invoke-Guarded -Whats 'starting over' -Action { Reset-VimigoSetup }
        Read-Host -Prompt '      Press Enter to check again' | Out-Null
        Clear-Screen
        Show-Banner
        Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
        Write-Host ''
        continue
    }

    # Enter on a finished checklist means "I am done here", not "do it all
    # again" - there is nothing left to do.
    if ($finished) { Write-Host ''; Write-Info 'All set. Bye.'; Write-Host ''; break }

    # Anything else means "do it all", in order. Picking one row out of the
    # middle is no longer offered.
    Clear-Screen
    Show-Banner

    $unfinished = @(Invoke-FixEverything -Checks $checks)

    Write-Host ''
    if ($unfinished.Count -gt 0) {
        Write-Warn '      Some things still need you:'
        foreach ($item in $unfinished) {
            Write-Host "         • $($item.Title)" -ForegroundColor $script:Ink.Warn
        }
        Write-Host ''
        Write-Info '      Several of these finish on a website or need a restart.'
        Write-Info '      Run this setup again afterwards and it will pick up'
        Write-Info '      exactly where it left off.'
        Write-Host ''
    }

    Read-Host -Prompt '      Press Enter to check again' | Out-Null
    Clear-Screen
    Show-Banner
    Write-Host '      Checking again...' -ForegroundColor $script:Ink.Body
    Write-Host ''
}

Reset-Theme
