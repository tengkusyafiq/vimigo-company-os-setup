#requires -Version 5.1
<#
.SYNOPSIS
    Acceptance tests for vimigo-setup.ps1.

.DESCRIPTION
    Drives the two config writes against throwaway files in a temporary
    directory. Nothing here touches the real Claude or ChatGPT configuration,
    Credential Manager, or the network.

    The guarantees under test are the ones that break somebody's machine when
    they fail: an unrelated setting must survive, a second run must not stack a
    duplicate, and a rejected write must put the original file back.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'vimigo-setup.ps1')

$script:Failures = 0
$script:Ran = 0

function Assert-True {
    param([bool]$Condition, [string]$What)
    $script:Ran++
    if ($Condition) {
        Write-Host "  PASS  $What" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $What" -ForegroundColor Red
        $script:Failures++
    }
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("vimigo-setup-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

try {
    # Point every path at the sandbox and stub the token read so no real
    # credential is needed and none is written.
    $script:ClaudeConfigPath = Join-Path $sandbox 'Claude\claude_desktop_config.json'
    $script:CodexConfigPath = Join-Path $sandbox 'codex\config.toml'
    $script:StatePath = Join-Path $sandbox 'state\setup-state.json'

    $fakeToken = 'zo_sk_TESTONLY_not_a_real_key'
    function Get-ZoToken { return $fakeToken }

    Write-Host ''
    Write-Host 'Claude Desktop config' -ForegroundColor Cyan

    # A config the owner already has, with a server we must not disturb.
    New-Item -ItemType Directory -Path (Split-Path -Parent $script:ClaudeConfigPath) -Force | Out-Null
    @'
{
  "mcpServers": {
    "somebody-elses-server": {
      "command": "node",
      "args": ["server.js"]
    }
  },
  "someUnrelatedSetting": 42
}
'@ | Set-Content -LiteralPath $script:ClaudeConfigPath -Encoding UTF8

    Assert-True (-not (Test-ClaudeMcpConfigured)) 'starts out not connected'

    $null = Connect-ZoToClaude 6>$null
    Assert-True (Test-ClaudeMcpConfigured) 'reports connected after the write'

    $after = Get-Content -LiteralPath $script:ClaudeConfigPath -Raw | ConvertFrom-Json
    Assert-True ($after.mcpServers.PSObject.Properties.Name -contains 'somebody-elses-server') `
        "the owner's other MCP server survived"
    Assert-True ($after.someUnrelatedSetting -eq 42) 'an unrelated setting survived'
    Assert-True ($after.mcpServers.zo.command -eq 'npx') 'the entry launches npx'
    Assert-True ($after.mcpServers.zo.args -contains 'https://api.zo.computer/mcp') `
        'the entry points at the Zo endpoint'

    $backupDir = Join-Path (Split-Path -Parent $script:ClaudeConfigPath) 'vimigo-backups'
    Assert-True ((Test-Path $backupDir) -and (@(Get-ChildItem $backupDir).Count -ge 1)) `
        'a backup of the original was kept'

    # Running it twice must leave exactly one entry, not two.
    $null = Connect-ZoToClaude 6>$null
    $twice = Get-Content -LiteralPath $script:ClaudeConfigPath -Raw | ConvertFrom-Json
    $zoCount = @($twice.mcpServers.PSObject.Properties.Name | Where-Object { $_ -eq 'zo' }).Count
    Assert-True ($zoCount -eq 1) 'a second run leaves exactly one Zo entry'
    Assert-True ($twice.mcpServers.PSObject.Properties.Name -contains 'somebody-elses-server') `
        "a second run still keeps the owner's other server"

    Write-Host ''
    Write-Host 'ChatGPT (Codex) config' -ForegroundColor Cyan

    New-Item -ItemType Directory -Path (Split-Path -Parent $script:CodexConfigPath) -Force | Out-Null
    @'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"

[plugins."github@openai-curated"]
enabled = true
'@ | Set-Content -LiteralPath $script:CodexConfigPath -Encoding UTF8

    Assert-True (-not (Test-CodexMcpConfigured)) 'starts out not connected'

    $null = Connect-ZoToChatGpt 6>$null
    Assert-True (Test-CodexMcpConfigured) 'reports connected after the write'

    $toml = Get-Content -LiteralPath $script:CodexConfigPath -Raw
    Assert-True ($toml -match 'model = "gpt-5\.6-sol"') 'the existing model setting survived'
    Assert-True ($toml -match [regex]::Escape('[plugins."github@openai-curated"]')) `
        "the owner's existing plugin section survived"
    Assert-True ($toml -match 'command = "npx"') 'the entry launches npx'

    $null = Connect-ZoToChatGpt 6>$null
    $tomlTwice = Get-Content -LiteralPath $script:CodexConfigPath -Raw
    $sectionCount = ([regex]::Matches($tomlTwice, '(?m)^\s*\[mcp_servers\.zo\]')).Count
    Assert-True ($sectionCount -eq 1) 'a second run leaves exactly one Zo section'

    # The header count alone is not enough: dropping the header but leaving its
    # body would orphan `command = "npx"` into whichever section came before,
    # silently corrupting a setting the owner never touched.
    $bodyCount = ([regex]::Matches($tomlTwice, '(?m)^\s*command = "npx"')).Count
    Assert-True ($bodyCount -eq 1) 'a second run leaves no orphaned settings behind'
    Assert-True ($tomlTwice -match 'model = "gpt-5\.6-sol"') 'a second run keeps the model setting'

    Write-Host ''
    Write-Host 'Refusing to write without a key' -ForegroundColor Cyan

    function Get-ZoToken { return $null }
    Remove-Item -LiteralPath $script:ClaudeConfigPath -Force
    $refused = Connect-ZoToClaude 6>$null
    Assert-True ($refused -eq $false) 'the Claude write is refused with no key'
    Assert-True (-not (Test-Path -LiteralPath $script:ClaudeConfigPath)) `
        'no config file is created when the write is refused'

    Write-Host ''
    Write-Host 'A machine that has never had an MCP config' -ForegroundColor Cyan

    # The ordinary first run, and the case every other test here skipped by
    # writing a config first. An empty document has no properties, so
    # .PSObject.Properties.Name is null and .Contains() on it throws. Found by
    # running the real thing on a machine where Claude Desktop had never been
    # configured, which is most machines.
    # The section above stubbed the key away to prove the refusal path. Put it
    # back, or this block only re-tests that refusal.
    function Get-ZoToken { return $fakeToken }

    Remove-Item -LiteralPath $script:ClaudeConfigPath -Force -ErrorAction SilentlyContinue
    Assert-True (-not (Test-Path -LiteralPath $script:ClaudeConfigPath)) 'starts with no config file at all'

    $freshResult = Connect-ZoToClaude 6>$null
    Assert-True ($freshResult -eq $true) 'the write succeeds with no config file present'
    Assert-True (Test-ClaudeMcpConfigured) 'and reports connected afterwards'

    $fresh = Get-Content -LiteralPath $script:ClaudeConfigPath -Raw | ConvertFrom-Json
    Assert-True ($fresh.mcpServers.zo.command -eq 'npx') 'the entry it created is the right shape'

    # Same again for a file that exists but holds nothing but an empty object.
    '{}' | Set-Content -LiteralPath $script:ClaudeConfigPath -Encoding UTF8
    $emptyResult = Connect-ZoToClaude 6>$null
    Assert-True ($emptyResult -eq $true) 'an empty {} config is handled too'

    Write-Host ''
    Write-Host 'The Zo key survives being written and read back' -ForegroundColor Cyan

    # A real run caught this and no unit test would have: Set-Content appends a
    # newline, Get-Content -Raw keeps it, and ConvertTo-SecureString rejects the
    # result. The key never read back, so every step below it said "needs your
    # Zo key first" forever - straight after the owner pasted a good one.
    #
    # Exercised against a throwaway file rather than the real Credential
    # Manager, so running the suite never touches the owner's stored key.
    $keyFile = Join-Path $sandbox 'zo-token.bin'
    $sampleKey = 'zo_sk_TESTONLY_round_trip_check'
    (ConvertTo-SecureString -String $sampleKey -AsPlainText -Force |
        ConvertFrom-SecureString) | Set-Content -LiteralPath $keyFile -Encoding ASCII

    $rawFile = Get-Content -LiteralPath $keyFile -Raw
    Assert-True ($rawFile -ne $rawFile.Trim()) 'the written file really does carry a trailing newline'

    $recovered = $null
    try {
        $secure = $rawFile.Trim() | ConvertTo-SecureString -ErrorAction Stop
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $recovered = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch { $recovered = "failed: $($_.Exception.Message)" }
    Assert-True ($recovered -eq $sampleKey) 'the key reads back exactly as written'

    $untrimmed = $null
    try { $untrimmed = $rawFile | ConvertTo-SecureString -ErrorAction Stop } catch { $untrimmed = $null }
    Assert-True ($null -eq $untrimmed) 'and without trimming it would still fail, which is why the trim is there'

    Write-Host ''
    Write-Host 'Corrupt config is left alone' -ForegroundColor Cyan

    function Get-ZoToken { return $fakeToken }
    'this is not json at all {{{' | Set-Content -LiteralPath $script:ClaudeConfigPath -Encoding UTF8
    $refusedCorrupt = Connect-ZoToClaude 6>$null
    Assert-True ($refusedCorrupt -eq $false) 'a corrupt Claude config is refused'
    Assert-True ((Get-Content -LiteralPath $script:ClaudeConfigPath -Raw).Trim() -eq 'this is not json at all {{{') `
        'the corrupt file was not modified'

    Write-Host ''
    Write-Host 'No message can crash on a variable that was never set' -ForegroundColor Cyan

    # Twice now a live run has died mid-step on this, and both times it was a
    # variable inside a message rather than in any logic:
    #
    #   "...$phone..."        never assigned on a first run
    #   "your $roleTitle?"    PowerShell reads "?" as part of the name, so this
    #                         looks up a variable called "roleTitle?"
    #
    # Under Set-StrictMode both throw, and a throw in a step used to end the
    # whole setup. Nothing exercised these lines because they only run on the
    # paths a new customer takes - which is the only run that matters.
    #
    # So: parse the script, find every variable used inside a message, and
    # insist each one is assigned somewhere or is a PowerShell built-in.

    $automatic = @(
        '_', 'PSItem', 'null', 'true', 'false', 'args', 'input', 'this',
        'PSScriptRoot', 'PSCommandPath', 'MyInvocation', 'Host', 'Error',
        'LASTEXITCODE', 'PID', 'HOME', 'PWD', 'PSVersionTable', 'PSCulture',
        'ExecutionContext', 'StackTrace', 'PSBoundParameters', 'Matches',
        'OFS', 'ErrorActionPreference', 'ProgressPreference'
    )

    function Get-UnsetMessageVariables {
        param([string]$Text, [string]$Path)

        $tokens = $null
        $errors = $null
        $tree = if ($Path) {
            [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        } else {
            [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        }

        $assigned = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

        # Everything the script gives a value to: plain assignments, function
        # and script parameters, and the loop variable in a foreach.
        foreach ($node in $tree.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            $left = $node.Left
            if ($left -is [System.Management.Automation.Language.ConvertExpressionAst]) { $left = $left.Child }
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                [void]$assigned.Add($left.VariablePath.UserPath)
            }
        }
        foreach ($node in $tree.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
            [void]$assigned.Add($node.Name.VariablePath.UserPath)
        }
        foreach ($node in $tree.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
            [void]$assigned.Add($node.Variable.VariablePath.UserPath)
        }

        $unknown = New-Object System.Collections.Generic.List[string]
        foreach ($string in $tree.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)) {

            foreach ($use in $string.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {

                $name = $use.VariablePath.UserPath
                # env: and global: come from outside the script, so there is
                # nothing here to check them against.
                if ($name -match '^(env|global|using|local|private):') { continue }
                $bare = $name -replace '^[A-Za-z]+:', ''
                if ($assigned.Contains($name) -or $assigned.Contains($bare)) { continue }
                if ($automatic -contains $bare) { continue }
                $unknown.Add("line $($use.Extent.StartLineNumber): `$$name")
            }
        }
        return $unknown
    }

    $setupScript = Join-Path $PSScriptRoot 'vimigo-setup.ps1'
    $unset = @(Get-UnsetMessageVariables -Path $setupScript)
    if ($unset.Count -gt 0) { $unset | ForEach-Object { Write-Host "      $_" -ForegroundColor Red } }
    Assert-True ($unset.Count -eq 0) 'every variable used in a message is set somewhere'

    # And prove the check can actually fail, because a detector that never
    # fires is worse than none: it reads as a guarantee.
    $bait = @'
$roleTitle = 'AI Sales'
Write-Host "What shall we call your $roleTitle? A first name works well."
'@
    $caught = @(Get-UnsetMessageVariables -Text $bait)
    Assert-True ($caught.Count -eq 1 -and $caught[0] -match 'roleTitle\?') `
        'and it catches the "$name?" trap that broke the hire screen'

    $clean = @'
$roleTitle = 'AI Sales'
Write-Host "What shall we call your ${roleTitle}? A first name works well."
'@
    Assert-True (@(Get-UnsetMessageVariables -Text $clean).Count -eq 0) `
        'while the ${name} form it was fixed to passes'

    Write-Host ''
    Write-Host 'The skills that ship are the ones Zo gets' -ForegroundColor Cyan

    # These folders are copied to a Linux server byte for byte. Git on Windows
    # rewrites line endings by default, and a checkout that did so would hand
    # every customer subtly different files - including Python with a stray \r
    # on every line. .gitattributes marks them binary; this is what notices when
    # that stops being true.
    $skillsRoot = Join-Path $PSScriptRoot 'skills'
    Assert-True (Test-Path -LiteralPath $skillsRoot) 'the skill folders ship with the setup'

    $skillFolders = @(Get-ChildItem -Directory -LiteralPath $skillsRoot)
    Assert-True ($skillFolders.Count -eq 9) "all nine are present (found $($skillFolders.Count))"

    $withoutSkillMd = @($skillFolders | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) })
    Assert-True ($withoutSkillMd.Count -eq 0) 'each one has the SKILL.md that makes it a skill'

    $crlf = @(Get-ChildItem -Recurse -File -LiteralPath $skillsRoot | Where-Object {
        [IO.File]::ReadAllBytes($_.FullName) -contains 13 })
    if ($crlf.Count -gt 0) { $crlf | ForEach-Object { Write-Host "      $($_.Name)" -ForegroundColor Red } }
    Assert-True ($crlf.Count -eq 0) 'none of them were rewritten to Windows line endings'

    # The name inside SKILL.md is what Zo lists, and what the setup matches on.
    # The folder name disagrees on six of the nine, which is the whole reason
    # the check reads the file rather than the folder.
    $named = @($skillFolders | Where-Object {
        (Get-Content -LiteralPath (Join-Path $_.FullName 'SKILL.md') -TotalCount 20) -match '^name:\s*\S' })
    Assert-True ($named.Count -eq 9) 'every one declares its name, which is what Zo lists it under'

    Write-Host ''
    Write-Host 'Restarting an AI app closes that app and nothing else' -ForegroundColor Cyan

    # Claude Code ships an executable also called claude.exe, so "close
    # everything named claude" closes the terminal session the owner may be
    # sitting in. That happened, mid-run, on the machine this was written on:
    # 13 processes answer to the name here and only 11 of them are the app.
    Assert-True (Test-DesktopAppPath -Which 'Claude' `
        -Path 'C:\Program Files\WindowsApps\Claude_1.20186.1.0_x64__pzs8sxrjxfjjc\app\Claude.exe') `
        'the packaged Claude Desktop is restarted'
    Assert-True (Test-DesktopAppPath -Which 'Claude' `
        -Path 'C:\Users\someone\AppData\Local\AnthropicClaude\claude.exe') `
        'and so is a normally installed one'

    Assert-True (-not (Test-DesktopAppPath -Which 'Claude' `
        -Path 'c:\Users\someone\.vscode\extensions\anthropic.claude-code-2.1.222-win32-x64\resources\native-binary\claude.exe')) `
        'Claude Code is left alone, whatever its executable is called'
    Assert-True (-not (Test-DesktopAppPath -Which 'Claude' -Path 'C:\Users\someone\claude.exe')) `
        'and so is any other claude.exe we cannot account for'
    Assert-True (-not (Test-DesktopAppPath -Which 'Claude' -Path '')) `
        'a process whose path cannot be read is never touched'

    Assert-True (Test-DesktopAppPath -Which 'ChatGPT' `
        -Path 'C:\Program Files\WindowsApps\OpenAI.Codex_26.730.8199.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe') `
        'ChatGPT is matched despite shipping as OpenAI.Codex'
    Assert-True (-not (Test-DesktopAppPath -Which 'ChatGPT' `
        -Path 'C:\Program Files\WindowsApps\Claude_1.20186.1.0_x64__pzs8sxrjxfjjc\app\Claude.exe')) `
        'and restarting one app never closes the other'

    Write-Host ''
    Write-Host 'The config files we write are what the apps expect' -ForegroundColor Cyan

    # Set-Content -Encoding UTF8 writes a byte order mark in the PowerShell that
    # ships with Windows, and none in PowerShell 7 - so the same line produced
    # different bytes depending on which one ran, and these are other programs'
    # files. Invisible from here: Get-Content strips a BOM on the way back in,
    # so the setup's own verification passed either way.
    $bomProbe = Join-Path $sandbox 'bom-probe.json'
    Write-TextFile -Path $bomProbe -Text '{"a":1}'
    $bomBytes = [IO.File]::ReadAllBytes($bomProbe)
    Assert-True (-not ($bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF)) `
        'a config file is written with no byte order mark'
    Assert-True ([Text.Encoding]::UTF8.GetString($bomBytes) -eq '{"a":1}') 'and the content is exactly what was asked for'

    # Node is what actually has to read Claude's file, and JSON.parse rejects a
    # leading BOM outright - so this is the check that matters, not ours.
    $nodeReads = & node -e "const fs=require('fs');try{JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write('ok')}catch(e){process.stdout.write('FAILED')}" $bomProbe
    Assert-True ($nodeReads -eq 'ok') 'and a JSON parser accepts it without complaint'

    Write-Host ''
    Write-Host 'The setup survives a machine with none of its tools' -ForegroundColor Cyan

    # Git is one of the three tools this setup exists to install, so a new
    # laptop has none - and the greeting reached for it before the checklist was
    # ever drawn. Calling a program that is not on PATH raises a terminating
    # error, and 2>$null cannot suppress it: the process never starts, so there
    # is no stderr to redirect. Every run died at the splash screen.
    # The path comes from $PSScriptRoot, not from a machine somebody once ran
    # this on. Hardcoding it meant the suite tested a file that was no longer
    # there the moment the folder was reorganised, and reported it as a fault
    # in the setup rather than in itself.
    $withoutTools = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
`$env:PATH = (`$env:PATH -split ';' | Where-Object { `$_ -notmatch 'Git|nodejs|Python' }) -join ';'
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
try {
    . '$setupScript' -Check 6>`$null 5>`$null 4>`$null 3>`$null
    'SURVIVED'
} catch {
    "DIED: `$(`$_.Exception.Message.Split([char]10)[0])"
}
"@ 2>&1 | Select-Object -Last 1

    Assert-True ("$withoutTools" -notmatch 'not recognized|CommandNotFound') `
        'no missing tool takes the whole setup down'

    Write-Host ''
    Write-Host 'What the setup sends to Zo arrives as what it sent' -ForegroundColor Cyan

    # Every AI employee was created with a job description of "You" - the first
    # word of "You are the owner's personal assistant" - because Start-Process
    # joins its argument array with spaces and quotes nothing, so the rest of
    # the sentence arrived as separate arguments and was thrown away. The
    # employees looked hired and knew nothing about their job.
    #
    # Nothing on screen showed it. It is only visible by asking the other end
    # what it actually received, which is what this does.
    $echo = Join-Path $sandbox 'echo-args.js'
    'process.stdout.write(JSON.stringify(process.argv.slice(2)));' |
        Set-Content -LiteralPath $echo -Encoding UTF8

    function Get-RoundTrippedArguments {
        param([string[]]$Arguments)
        $out = Join-Path $sandbox ('args-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $null = Invoke-WithSpinner -Message 'testing' -FilePath 'node' `
                -Arguments (@($echo) + $Arguments) -OutputFile $out
            return (Get-Content -LiteralPath $out -Raw | ConvertFrom-Json)
        } finally {
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        }
    }

    $sentence = "You are the owner's personal assistant. You help with their calendar."
    $got = @(Get-RoundTrippedArguments -Arguments @('--hire', 'Zoe', $sentence))
    Assert-True ($got.Count -eq 3) "a sentence stays one argument (got $($got.Count))"
    Assert-True ($got[2] -eq $sentence) 'and arrives word for word'

    $awkward = 'Say "hello" then C:\path\ and 60% off'
    $tricky = @(Get-RoundTrippedArguments -Arguments @('--brief', $awkward))
    Assert-True ($tricky[1] -eq $awkward) 'quotes, backslashes and symbols survive too'

    $multiline = "First line.`nSecond line."
    $lines = @(Get-RoundTrippedArguments -Arguments @('--brief', $multiline))
    Assert-True ($lines[1] -eq $multiline) 'and so does a job description with line breaks'

    $spaced = @(Get-RoundTrippedArguments -Arguments @('--hire', 'Ah Meng', 'Sells things.'))
    Assert-True ($spaced[1] -eq 'Ah Meng') 'a name with a space is one name, not two'

    Write-Host ''
    Write-Host 'An AI employee never lands on a model the owner pays per use for' -ForegroundColor Cyan

    # Zo's own models are billed by use. Quietly putting eight employees on one
    # is a bill nobody agreed to, so only "byok:" models - the owner's own
    # Claude or ChatGPT plan - are ever chosen, and no model at all is better
    # than a metered one.
    #
    # The cases worth testing are the ones nobody has in front of them: someone
    # who linked ChatGPT and not Claude, or Claude without Opus.
    $chooser = Join-Path $PSScriptRoot 'zo-verify.js'
    function Get-ChosenModel {
        param([string]$Json)
        $script = "const {chooseOwnPlanModel} = require(process.argv[1]);" +
                  "const got = chooseOwnPlanModel(JSON.parse(process.argv[2]));" +
                  "process.stdout.write(got ? got.label : 'NONE');"
        return (& node -e $script $chooser $Json)
    }

    $both = '[{"id":"byok:a","label":"Claude Code - Opus -> opus"},{"id":"byok:b","label":"Codex - GPT 5.6 Luna -> gpt-5.6-luna"}]'
    Assert-True ((Get-ChosenModel $both) -match 'Opus') 'with both linked, Claude Opus wins'

    $gptOnly = '[{"id":"byok:b","label":"Codex - GPT 5.6 Luna -> gpt-5.6-luna"},{"id":"byok:c","label":"Codex - GPT 5.3 Codex -> gpt-5.3-codex"}]'
    Assert-True ((Get-ChosenModel $gptOnly) -match 'Luna') 'with only ChatGPT linked, it falls to Luna'

    $claudeNoOpus = '[{"id":"byok:d","label":"Claude Code - Sonnet -> sonnet"}]'
    Assert-True ((Get-ChosenModel $claudeNoOpus) -match 'Sonnet') 'Claude without Opus still uses their own plan'

    $gptNoLuna = '[{"id":"byok:e","label":"Codex - GPT 5.3 Codex -> gpt-5.3-codex"}]'
    Assert-True ((Get-ChosenModel $gptNoLuna) -match 'Codex') 'ChatGPT without Luna still uses their own plan'

    Assert-True ((Get-ChosenModel '[]') -eq 'NONE') 'with no plan linked, no model is chosen at all'

    # The one that costs money if it is wrong.
    $metered = '[{"id":"zo:anthropic/claude-opus-5","label":"Zo Opus"}]'
    $meteredChoice = Get-ChosenModel $metered
    Assert-True ($meteredChoice -eq 'NONE' -or $meteredChoice -notmatch 'Zo Opus') `
        'a pay-per-use model is never chosen on the owner''s behalf'

    Write-Host ''
    Write-Host 'A failing step never ends the setup' -ForegroundColor Cyan

    # Every action reachable from a menu goes through Invoke-Guarded, so a bug
    # in one screen returns to the menu instead of closing the window on a red
    # error. Checked by parsing rather than by running, because the whole point
    # is the paths nobody thought to run.
    $setupText = Get-Content -LiteralPath $setupScript -Raw
    foreach ($risky in @('Invoke-HireEmployee', 'Reset-VimigoSetup')) {
        $calls = [regex]::Matches($setupText, "(?m)^\s*(?:\`$null = )?$risky\s*$")
        Assert-True ($calls.Count -eq 0) "$risky is never called unguarded"
    }
    Assert-True ($setupText -match '(?m)^trap \{') 'and a last-resort trap covers whatever that misses'

} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host "$script:Failures of $script:Ran checks FAILED." -ForegroundColor Red
    exit 1
}
Write-Host "All $script:Ran checks passed." -ForegroundColor Green
exit 0
