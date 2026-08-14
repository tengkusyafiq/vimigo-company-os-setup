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

# Kept here, before anything below replaces it.
#
# Stubs in this suite overwrite a function rather than shadowing it, so once the
# fixtures further down have installed their own Test-HcsServicesPresent the
# real one is simply gone. Captured after that point it returns whatever the
# fixture returns, and the tests that check its actual logic then pass or fail
# for reasons that have nothing to do with the code - which is exactly what
# happened before this line existed.
$script:RealTestHcsServicesPresent = ${function:Test-HcsServicesPresent}
$script:RealTestEventSkillInstalled = ${function:Test-EventSkillInstalled}
$script:RealInstallEventSkill = ${function:Install-EventSkill}
$script:RealGetEventSkillDest = ${function:Get-EventSkillDest}
$script:RealGetEventChatgptDest = ${function:Get-EventChatgptDest}
$script:RealGetEventCodexDest = ${function:Get-EventCodexDest}
$script:RealGetEventCodexPromptDest = ${function:Get-EventCodexPromptDest}
# Captured for the same reason as the rest: the sign-in section below points
# Get-ClaudeConfigPath at a sandbox, and everything after it needs the real one
# back. A stub left in place would have later tests reading a folder that only
# exists for this run.
$script:RealGetClaudeConfigPath = ${function:Get-ClaudeConfigPath}

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
    # Not the bare word, and not npx.cmd either.
    #
    # "npx" fails under a packaged Claude Desktop, which does not inherit the
    # user's PATH. npx.cmd then fails on the default Node install, because that
    # batch file invokes its own location unquoted and Windows cuts
    # C:\Program Files\nodejs at the space - the log line customers actually
    # saw was 'C:\Program' is not recognized. Both of those pass a test that
    # only checks the word "npx" appears somewhere.
    #
    # So the check is what makes it work: a real executable, spawned directly,
    # with the script as an argument rather than through any shell.
    $claudeCommand = [string]$after.mcpServers.zo.command
    Assert-True ($claudeCommand -match '(^|\\)node(\.exe)?$') `
        'the entry runs node itself, not a shim that re-parses its own path'
    Assert-True (Test-Path -LiteralPath $claudeCommand) `
        'and that node exists on this machine'
    Assert-True ([string]$after.mcpServers.zo.args[0] -match 'npx-cli\.js$') `
        'with npm own npx script as the first argument'
    Assert-True (Test-Path -LiteralPath ([string]$after.mcpServers.zo.args[0])) `
        'and that script exists too'
    Assert-True (@($after.mcpServers.zo.args) -contains '-y') `
        'and -y, because an MCP server has no terminal to answer a prompt on'
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
    Assert-True ($toml -match 'command = "[^"]*node(\.exe)?"') `
        'the entry runs node itself, not a shim that re-parses its own path'

    # The path has to survive TOML, and "matches npx" does not prove that. A
    # Windows path needs each separator doubled: written raw, \U and \n become
    # escape sequences and Codex cannot parse its own config; doubled twice by
    # mistake, the path points nowhere. So the value is unescaped and checked
    # against the real one.
    $tomlCommand = ([regex]::Match($toml, '(?m)^command = "([^"]*)"')).Groups[1].Value
    Assert-True ($tomlCommand -notmatch '\\\\\\\\') 'the path is not over-escaped'
    Assert-True (Test-Path -LiteralPath $tomlCommand.Replace('\\', '\')) `
        'and unescapes back to a node that exists on this machine'
    # The arguments have to survive TOML too, and one of them is a path.
    $tomlArgs = ([regex]::Match($toml, '(?m)^args = \[(.*)\]$')).Groups[1].Value
    Assert-True ($tomlArgs -match 'npx-cli\.js') 'the arguments carry npm own npx script'
    Assert-True ($tomlArgs -match '"-y"') 'and -y'

    $null = Connect-ZoToChatGpt 6>$null
    $tomlTwice = Get-Content -LiteralPath $script:CodexConfigPath -Raw
    $sectionCount = ([regex]::Matches($tomlTwice, '(?m)^\s*\[mcp_servers\.zo\]')).Count
    Assert-True ($sectionCount -eq 1) 'a second run leaves exactly one Zo section'

    # The header count alone is not enough: dropping the header but leaving its
    # body would orphan `command = "npx"` into whichever section came before,
    # silently corrupting a setting the owner never touched.
    $bodyCount = ([regex]::Matches($tomlTwice, '(?m)^\s*command = "[^"]*node(\.exe)?"')).Count
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
    Assert-True (([string]$fresh.mcpServers.zo.command -match '(^|\\)node(\.exe)?$') -or
                 ([string]$fresh.mcpServers.zo.command -eq 'npx')) `
        'the entry it created is the right shape'

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
        # The JSON goes via a file rather than the command line.
        #
        # Windows PowerShell 5.1 passes arguments to a native program without
        # escaping the quotes inside them, so [{"id":"byok:a"}] arrived at node
        # as [{id:byok:a}] and JSON.parse threw. PowerShell 7.3 escapes them,
        # which is exactly why this passed everywhere it was run and failed on
        # the version the customers have. The suite then stopped, taking the
        # forty checks after it along with it.
        #
        # The product does not have this bug - everything it sends goes through
        # ConvertTo-CommandLineArgument - but a suite that only runs on 7 is not
        # checking the thing that ships.
        $jsonFile = Join-Path ([IO.Path]::GetTempPath()) ("vimigo-model-" + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($jsonFile, $Json, (New-Object Text.UTF8Encoding($false)))
        try {
            $script = "const fs = require('fs');" +
                      "const {chooseOwnPlanModel} = require(process.argv[1]);" +
                      "const got = chooseOwnPlanModel(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));" +
                      "process.stdout.write(got ? got.label : 'NONE');"
            # Joined, because node writing a stack trace would otherwise return
            # an array and Assert-True would fail to bind rather than report.
            return ((& node -e $script $chooser $jsonFile 2>&1) -join '')
        } finally {
            Remove-Item -LiteralPath $jsonFile -Force -ErrorAction SilentlyContinue
        }
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

    Write-Host ''
    Write-Host 'What this build offers' -ForegroundColor Cyan

    # Two parts of the setup can be switched off. What follows drives the real
    # Get-AllChecks, the real menu and the real "start over" screen, because the
    # fault worth catching is not "the flag is read" - it is a checklist that
    # quietly comes out in a different order, or a key that still works while
    # nothing on screen offers it.

    # The reply a finished Zo gives, so the rows can be built without a network.
    # Everything answers "done" on purpose: a row missing because it is complete
    # proves nothing about a row missing because it was switched off.
    $zoFixture = @'
{ "ok": true, "workspaceUrl": "https://example.zo.computer",
  "aiProviders": { "claude": { "loggedIn": true }, "codex": { "loggedIn": true } },
  "whatsapp": { "connected": true, "answering": true },
  "integrations": { "gmail": { "connected": true }, "google_calendar": { "connected": true },
                     "google_drive": { "connected": true }, "google_sheets": { "connected": true } },
  "skills": { "installed": ["morning-briefing"], "missing": [] },
  "secondBrain": { "folders": 3, "notes": 7 },
  "employees": ["Joe"] }
'@ | ConvertFrom-Json

    # Kept off the network and off this machine's real state, so the rows under
    # test are the only thing that can vary.
    function Get-ZoVerification { param($Token) if ($script:FixtureHasKey) { return $zoFixture } return $null }
    function Test-ClaudeDesktopInstalled { return $true }
    function Test-ChatGptDesktopInstalled { return $true }
    function Test-HcsServicesPresent { return $true }
    # Treated as present for the same reason as the two apps above it: these
    # tests are about which rows appear and in what order, and a row that is
    # outstanding only because the machine running the suite happens not to
    # have the app would fail every "nothing left to do" check below.
    function Test-HermesInstalled { return $true }
    # And the /compile-data command, for the same reason. Stubbed rather than
    # really installed: the real one writes into ~/.claude/skills and onto the
    # Desktop, and a suite that leaves files in either place has changed the
    # machine it was only supposed to measure.
    function Test-EventSkillInstalled { return $true }
    function Find-LocalWhatsAppInstall { return @() }
    function Get-Profile { return @{ talkChannel = 'whatsapp'; employees = @() } }
    function Get-HiredEmployees { return @() }
    function Write-Checking { param([string]$What) }

    $script:FixtureHasKey = $true

    function Set-Features {
        param([string]$All)
        $script:FeatureAiAssistant = $All
        $script:FeatureZoSkills = $All
        $script:FeatureSecondBrain = $All
        $script:FeatureAiEmployees = $All
        $script:FeatureGoogle = $All
    }

    function Get-ZoRowKeys {
        # The rows that live on Zo, in the order the owner reads them.
        param([string]$Assistant, [string]$Skills, [string]$Brain,
              [string]$Employees, [switch]$NoKey)
        $script:FeatureAiAssistant = $Assistant
        $script:FeatureZoSkills = $Skills
        $script:FeatureSecondBrain = $Brain
        $script:FeatureAiEmployees = $Employees
        # Google held on, because these checks are about the order of the rows
        # around it. Its own switch is covered on its own, below.
        $script:FeatureGoogle = 'on'
        $script:FixtureHasKey = -not $NoKey
        $onZo = @('zo-claude-code', 'zo-codex', 'zo-skills', 'zo-brain',
                  'zo-google', 'talk-to-zo', 'zo-employees')
        $keys = @(Get-AllChecks 6>$null | Where-Object { $onZo -contains $_.Key } |
            ForEach-Object { $_.Key })
        return ($keys -join ' ')
    }

    function Get-AllRowKeys {
        param([string]$All, [switch]$NoKey)
        Set-Features $All
        $script:FixtureHasKey = -not $NoKey
        return (@(Get-AllChecks 6>$null | ForEach-Object { $_.Key }) -join ' ')
    }

    $allOn = 'zo-skills zo-brain zo-google talk-to-zo zo-employees zo-claude-code zo-codex'
    $allOff = 'zo-google zo-claude-code zo-codex'

    Assert-True ((Get-ZoRowKeys -Assistant 'on' -Skills 'on' -Brain 'on' -Employees 'on') -eq $allOn) `
        'everything on, the plan rows are last and the rest keep their order'
    Assert-True ((Get-ZoRowKeys -Assistant 'off' -Skills 'off' -Brain 'off' -Employees 'off') -eq $allOff) `
        'everything off, only the rows that always ship are left'
    Assert-True ((Get-ZoRowKeys -Assistant 'on' -Skills 'off' -Brain 'off' -Employees 'off') -eq `
        'zo-google talk-to-zo zo-claude-code zo-codex') `
        'the assistant alone brings back only its own row'
    Assert-True ((Get-ZoRowKeys -Assistant 'off' -Skills 'on' -Brain 'off' -Employees 'off') -eq `
        'zo-skills zo-google zo-claude-code zo-codex') `
        'skills alone come back above the plan rows'
    Assert-True ((Get-ZoRowKeys -Assistant 'off' -Skills 'off' -Brain 'on' -Employees 'off') -eq `
        'zo-brain zo-google zo-claude-code zo-codex') `
        'the second brain alone sits above the plan rows'
    Assert-True ((Get-ZoRowKeys -Assistant 'off' -Skills 'off' -Brain 'off' -Employees 'on') -eq `
        'zo-google zo-employees zo-claude-code zo-codex') `
        'employees alone come last of the rows this setup can finish itself'

    # The fault this guards is a real one that shipped: the list shown before
    # the key is pasted was kept by hand and had lost the second brain, so
    # pasting the key silently rearranged the screen - the exact thing the note
    # above that list forbids.
    Assert-True ((Get-ZoRowKeys -Assistant 'on' -Skills 'on' -Brain 'on' -Employees 'on' -NoKey) -eq `
                 (Get-ZoRowKeys -Assistant 'on' -Skills 'on' -Brain 'on' -Employees 'on')) `
        'everything on, pasting the key does not rearrange the list'
    Assert-True ((Get-ZoRowKeys -Assistant 'off' -Skills 'off' -Brain 'off' -Employees 'off' -NoKey) -eq `
                 (Get-ZoRowKeys -Assistant 'off' -Skills 'off' -Brain 'off' -Employees 'off')) `
        'everything off, pasting the key does not rearrange the list either'

    # Whatever else is switched off, the owner must finish with a way to reach
    # their Zo. Claude Desktop and ChatGPT are that way and are never
    # switchable.
    Assert-True ((Get-AllRowKeys -All 'off') -match 'claude-mcp') `
        'Zo inside Claude Desktop survives every switch being off'
    Assert-True ((Get-AllRowKeys -All 'off') -match 'chatgpt-mcp') `
        'Zo inside ChatGPT survives every switch being off'
    Assert-True ((Get-AllRowKeys -All 'off' -NoKey) -match 'chatgpt-mcp') `
        'and survives with no key either, so there is always somewhere to type'

    Write-Host ''
    Write-Host 'Telegram: is a phone connected' -ForegroundColor Cyan

    # The question used to be answered by counting entries in a file on Zo's
    # disk. That file is not written when a phone pairs through Zo's hosted bot
    # - it was a month stale on the Zo that found this - so the count never
    # moved and the setup waited for ever on a link that had already worked. The
    # answer now comes from the only place Zo states it: the reply to a message
    # it cannot route.
    #
    # It reads prose, so it is tested like prose: on the exact wording seen
    # live, on the shapes a reworded Zo might send, and on the ones that must
    # never be read as a connected phone.
    $verifyPath = (Join-Path $PSScriptRoot 'zo-verify.js') -replace '\\', '/'
    function Get-TelegramAccounts {
        param([string]$Text)
        # The sample goes through a file, never on the command line. PowerShell
        # 5.1 does not escape quotes in native arguments, and these samples are
        # nothing but quotes and apostrophes - the same trap that once silenced
        # forty of these checks without a word.
        $textFile = Join-Path $sandbox ('tg-' + [guid]::NewGuid().ToString('N') + '.txt')
        Set-Content -LiteralPath $textFile -Value $Text -Encoding UTF8 -NoNewline
        $reader = "const t = require('fs').readFileSync(process.argv[1], 'utf8');" +
            "const { readConnectedTelegram } = require('$verifyPath');" +
            "process.stdout.write(JSON.stringify(readConnectedTelegram(t)));"
        return (& node -e $reader $textFile)
    }

    $liveWording = "Error: Failed to send Telegram message: ValueError: No Telegram binding found for recipient 'vimigo-setup-status-probe'. Connected accounts: heartsmith. Do not retry - inform the user that delivery failed."

    Assert-True ((Get-TelegramAccounts $liveWording) -eq '["heartsmith"]') `
        'the wording Zo actually sends names the connected phone'
    Assert-True ((Get-TelegramAccounts 'Connected accounts: alice, bob, carol.') -eq '["alice","bob","carol"]') `
        'several phones are all read, and trimmed'
    Assert-True ((Get-TelegramAccounts 'Connected accounts: none.') -eq '[]') `
        '"none" is not a phone'
    Assert-True ((Get-TelegramAccounts 'Connected accounts: .') -eq '[]') `
        'and neither is an empty list'
    Assert-True ((Get-TelegramAccounts 'Telegram message sent successfully') -eq '[]') `
        'a send that worked is not proof on its own'
    Assert-True ((Get-TelegramAccounts '') -eq '[]') `
        'nothing back is not proof either'
    Assert-True ((Get-TelegramAccounts 'connected accounts: Heartsmith.') -eq '["Heartsmith"]') `
        'the wording is matched whatever its case'

    # The wait asks whether a phone is connected, never whether more are
    # connected than before. Checked by parsing, because the loop it lives in
    # cannot be entered without a QR on screen and twelve minutes to spare.
    Assert-True ($setupText -match '\$state\.linked -gt 0') `
        'the wait asks whether a phone is connected at all'
    Assert-True ($setupText -notmatch 'linked -gt \$LinkedBefore') `
        'and never compares against a count taken beforehand'

    Write-Host ''
    Write-Host 'One AI app is enough' -ForegroundColor Cyan

    # A customer who pays for ChatGPT and not Claude is a finished setup, not a
    # half-finished one. Counted as half-finished their Claude rows stayed red
    # for ever, the checklist never said done, and what they reported was "a
    # problem with the Zo connection".
    function Get-AppRows {
        param([bool]$Claude, [bool]$ChatGpt)
        $script:WantClaude = $Claude
        $script:WantChatGpt = $ChatGpt
        Set-Features 'off'
        $script:FixtureHasKey = $true
        $wanted = @('claude-app', 'chatgpt-app', 'claude-mcp', 'chatgpt-mcp')
        return ((@(Get-AllChecks 6>$null | Where-Object { $wanted -contains $_.Key } |
            ForEach-Object { "$($_.Key):$($_.Status)" })) -join ' ')
    }

    function Test-ClaudeDesktopInstalled { return $script:WantClaude }
    function Test-ChatGptDesktopInstalled { return $script:WantChatGpt }
    function Test-ClaudeDesktopOpened { return $script:WantClaude }
    function Test-ChatGptSignedIn { return $script:WantChatGpt }
    function Test-ClaudeMcpConfigured { return $script:WantClaude }
    function Test-CodexMcpConfigured { return $script:WantChatGpt }

    Assert-True ((Get-AppRows -Claude $true -ChatGpt $false) -eq `
        'claude-app:ok chatgpt-app:skipped claude-mcp:ok chatgpt-mcp:skipped') `
        'with only Claude, the ChatGPT rows are settled and not chased'
    Assert-True ((Get-AppRows -Claude $false -ChatGpt $true) -eq `
        'claude-app:skipped chatgpt-app:ok claude-mcp:skipped chatgpt-mcp:ok') `
        'with only ChatGPT, the Claude rows are settled and not chased'
    Assert-True ((Get-AppRows -Claude $true -ChatGpt $true) -eq `
        'claude-app:ok chatgpt-app:ok claude-mcp:ok chatgpt-mcp:ok') `
        'with both, both are used'
    # Nothing to prefer, so both are offered - a blank machine still gets set up.
    Assert-True ((Get-AppRows -Claude $false -ChatGpt $false) -eq `
        'claude-app:missing chatgpt-app:missing claude-mcp:missing chatgpt-mcp:missing') `
        'with neither, both are still offered'

    # The part that decides whether they ever see "all done".
    $script:WantClaude = $false; $script:WantChatGpt = $true
    Set-Features 'off'
    $script:FixtureHasKey = $true
    $settledStates = @('ok', 'skipped')
    $left = @(Get-AllChecks 6>$null | Where-Object { $settledStates -notcontains $_.Status })
    Assert-True ($left.Count -eq 0) `
        'a ChatGPT-only machine can reach a finished setup'

    # The two plan rows need a paid subscription, so no amount of pressing
    # Enter clears them. Counted as outstanding they held the setup open for
    # anyone paying for neither, which is most people trying it.
    $planRows = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'zo-claude-code' -or $_.Key -eq 'zo-codex' })
    Assert-True (@($planRows | Where-Object { $_.Status -eq 'ok' }).Count -eq 2) `
        'a signed-in plan still shows as done'

    $zoNoPlans = @'
{ "ok": true, "workspaceUrl": "https://example.zo.computer",
  "aiProviders": { "claude": { "loggedIn": false }, "codex": { "loggedIn": false } },
  "whatsapp": { "connected": true, "answering": true },
  "integrations": { "gmail": { "connected": true }, "google_calendar": { "connected": true },
                     "google_drive": { "connected": true }, "google_sheets": { "connected": true } },
  "skills": { "installed": ["morning-briefing"], "missing": [] },
  "secondBrain": { "folders": 3, "notes": 7 }, "employees": ["Joe"] }
'@ | ConvertFrom-Json
    $script:FixturePlans = $false
    # Declared here as well as further down, because this block runs before the
    # step-trail section that used to be the only place it was set - and a
    # StrictMode read of an unset script variable stops the whole suite dead.
    $script:FixtureUndone = $false
    function Get-ZoVerification {
        param($Token)
        if (-not $script:FixtureHasKey) { return $null }
        if (-not $script:FixturePlans) { return $zoNoPlans }
        if ($script:FixtureUndone) { return $zoUndone }
        return $zoFixture
    }
    # These two rows were settled whatever happened, on the reasoning that a
    # paid subscription is not something pressing Enter can produce. v1 reverses
    # that: participants are told to register and to pay before they arrive, so
    # an unlinked plan is an unfinished step rather than somebody declining to
    # buy something - and settled meant the setup never even offered the row, so
    # an owner who HAD paid and simply not linked it was never asked.
    $noPlanRows = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'zo-claude-code' -or $_.Key -eq 'zo-codex' })
    Assert-True (@($noPlanRows | Where-Object { $_.Status -eq 'missing' }).Count -eq 2) `
        'an unsigned plan is outstanding, not quietly settled'
    $leftNoPlans = @(Get-AllChecks 6>$null | Where-Object { $settledStates -notcontains $_.Status })
    Assert-True ($leftNoPlans.Count -gt 0) `
        'so a setup with neither plan linked does not report itself finished'
    $script:FixturePlans = $true

    # And the other way, so the row is reachable by doing the thing rather than
    # being a wall.
    $withPlans = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'zo-claude-code' -or $_.Key -eq 'zo-codex' })
    Assert-True (@($withPlans | Where-Object { $_.Status -eq 'ok' }).Count -eq 2) `
        'and signing the plans in clears both rows'

    Write-Host ''
    Write-Host 'The progress bar counts a settled row as done' -ForegroundColor Cyan

    # A bar that never fills because the owner does not pay for a second AI
    # plan reads as a setup that failed.
    $barText = (@(Show-Checks -Checks @(Get-AllChecks 6>$null) 6>&1 |
        ForEach-Object { [regex]::Replace([string]$_, "$([char]27)\[[0-9;]*m", '') }) -join ' ')
    Assert-True ($barText -notmatch '\b0 of ') 'the bar is not stuck at zero'

    Write-Host ''
    Write-Host 'No step goes missing from the run' -ForegroundColor Cyan

    # "Step 3 of 7" is worked out from what is still outstanding, so a
    # switched-off feature has to take its step with it. A total that still
    # counts a step nothing will ever run strands the owner on "Step 5 of 7" at
    # the end, certain something failed - and a sequence with a hole in it says
    # the same thing louder.
    $zoUndone = @'
{ "ok": true, "workspaceUrl": "https://example.zo.computer",
  "aiProviders": { "claude": { "loggedIn": false }, "codex": { "loggedIn": false } },
  "whatsapp": { "connected": false, "detail": "not linked yet" },
  "integrations": { "gmail": { "connected": false } },
  "skills": { "installed": [], "missing": ["morning-briefing"] },
  "secondBrain": null, "employees": [] }
'@ | ConvertFrom-Json

    function Invoke-Fix { param([string]$Key) Write-Host "WOULD_DO $Key"; return $false }

    function Get-StepTrail {
        # "1/7", "2/7", ... as the owner sees it, driving the real
        # Invoke-FixEverything rather than counting rows by hand.
        param([string]$All)
        Set-Features $All
        $script:FixtureUndone = $true
        $written = @(Invoke-FixEverything -Checks (Get-AllChecks) 6>&1 |
            ForEach-Object { [regex]::Replace([string]$_, "$([char]27)\[[0-9;]*m", '') })
        $script:FixtureUndone = $false
        return @($written | ForEach-Object {
            $hit = [regex]::Match($_, 'Step (\d+) of (\d+)')
            if ($hit.Success) { "$($hit.Groups[1].Value)/$($hit.Groups[2].Value)" }
        })
    }

    # The fixture swaps to the unfinished reply only while a trail is measured,
    # so the row tests above keep the finished one they were written against.
    $script:FixtureUndone = $false
    function Get-ZoVerification {
        param($Token)
        if (-not $script:FixtureHasKey) { return $null }
        if ($script:FixtureUndone) { return $zoUndone }
        return $zoFixture
    }

    function Test-TrailWhole {
        # True when the numbers run 1..N with no gaps and N is the total claimed.
        param([string[]]$Trail)
        # No steps at all is whole, and on this build it is the point: with
        # every feature switched off and one AI app already set up, there is
        # genuinely nothing left to run. Calling that a gap failed the suite
        # for doing exactly what it was asked to do.
        if ($Trail.Count -eq 0) { return $true }
        for ($i = 0; $i -lt $Trail.Count; $i++) {
            $parts = $Trail[$i].Split('/')
            if ([int]$parts[0] -ne ($i + 1)) { return $false }
            if ([int]$parts[1] -ne $Trail.Count) { return $false }
        }
        return $true
    }

    $trailOff = @(Get-StepTrail -All 'off')
    $trailOn = @(Get-StepTrail -All 'on')

    Assert-True (Test-TrailWhole $trailOff) `
        'switched off, the steps run 1..N with no gaps and end on the total'
    Assert-True (Test-TrailWhole $trailOn) `
        'switched on, the steps run 1..N with no gaps and end on the total'
    # Counted as a difference, not as an absolute: how many local rows are
    # outstanding depends on the machine this suite runs on, but switching two
    # features off must remove exactly two steps anywhere.
    Assert-True (($trailOn.Count - $trailOff.Count) -eq 5) `
        'switching all five off removes exactly five steps, no more and no fewer'

    Write-Host ''
    Write-Host 'The assistant refuses to start on a half-finished setup' -ForegroundColor Cyan

    # The rule: the main setup finishes first. The assistant needs the Zo key,
    # the scripts this setup puts on the Zo, and a Zo that answers - so started
    # early it fails somewhere in the middle, having already asked for a phone
    # number, and what the owner remembers is that the assistant broke.
    function Get-GateResult {
        param([switch]$Halfway)
        Set-Features 'off'
        $script:FixtureHasKey = $true
        if ($Halfway) {
            # Nothing installed and nothing connected: the state a customer is
            # in before they have run anything.
            $script:WantClaude = $false; $script:WantChatGpt = $false
        } else {
            $script:WantClaude = $false; $script:WantChatGpt = $true
        }
        return @(Get-MainSetupUnfinished | ForEach-Object { [string]$_.Title })
    }

    # Captured once each and read from the variable: every call runs a whole
    # checklist, and re-running one per assertion is slow and lets three
    # assertions disagree about the same machine.
    $gateDone = @(Get-GateResult)
    $gateHalf = @(Get-GateResult -Halfway)

    Assert-True ($gateDone.Count -eq 0) 'a finished setup lets the assistant through'
    Assert-True ($gateHalf.Count -gt 0) 'a half-finished one does not'
    Assert-True ($gateHalf -contains 'ChatGPT Desktop') `
        'and it names what is still missing, rather than just refusing'

    # Its own row must never be the thing that blocks it, and the switch has to
    # come back exactly as it was found.
    $script:FeatureAiAssistant = 'on'
    $script:WantClaude = $false; $script:WantChatGpt = $true
    $script:FixtureHasKey = $true
    Assert-True (@(Get-MainSetupUnfinished).Count -eq 0) `
        'the assistant is not counted against itself'
    Assert-True ($script:FeatureAiAssistant -eq 'on') `
        'and the switch is left as it was found'

    Write-Host ''
    Write-Host 'Google is a switch like the rest' -ForegroundColor Cyan

    # The last row that could hold a v1 setup open. Tengku believed it was
    # already off and it was not: the four switches were the assistant, skills,
    # the second brain and employees, and Google was never among them - so on a
    # finished setup it sat there as the one outstanding thing.
    function Get-GoogleRowCount {
        param([string]$Google, [switch]$NoKey)
        Set-Features 'off'
        $script:FeatureGoogle = $Google
        $script:FixtureHasKey = -not $NoKey
        return @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'zo-google' }).Count
    }

    Assert-True ((Get-GoogleRowCount -Google 'on') -eq 1) 'switched on, Google is on the list'
    Assert-True ((Get-GoogleRowCount -Google 'off') -eq 0) 'switched off, Google is gone'
    Assert-True ((Get-GoogleRowCount -Google 'on' -NoKey) -eq 1) `
        'and with no key it still appears when switched on'
    Assert-True ((Get-GoogleRowCount -Google 'off' -NoKey) -eq 0) `
        'and still does not when switched off, so the list never rearranges'

    # The whole point of switching it off: nothing is left for the owner to do.
    $script:WantClaude = $false; $script:WantChatGpt = $true
    Set-Features 'off'
    $script:FixtureHasKey = $true
    $nothingLeft = @(Get-AllChecks 6>$null | Where-Object { @('ok','skipped') -notcontains $_.Status })
    Assert-True ($nothingLeft.Count -eq 0) `
        'with everything off, a ChatGPT-only machine has nothing left to do'

    Write-Host ''
    Write-Host 'A switched-off feature takes its key with it' -ForegroundColor Cyan

    function Get-MenuKeys {
        # The letters the finished menu offers, in order. Read off the records
        # Write-Host emits rather than off the screen, so no colour handling or
        # console width can change the answer.
        param([string]$Assistant, [string]$Brain, [string]$Employees)
        $script:FeatureAiAssistant = $Assistant
        $script:FeatureSecondBrain = $Brain
        $script:FeatureAiEmployees = $Employees
        # Held on, and said here rather than inherited. These checks are about
        # each feature taking its own key with it, and Z and S are not features
        # - they are the finished menu itself, which has its own switch and its
        # own section. Left to inherit, all five turned red the day that switch
        # went off, for a reason none of them is about.
        $script:FeatureFinishedMenu = 'on'
        # Colours stripped first. Write-Brand wraps the key in 24-bit escapes on
        # a capable console, so a pattern that expected a bare letter found none
        # of them and every row read as absent.
        $written = @(Show-MainOptions -Finished 6>&1 |
            ForEach-Object { [regex]::Replace([string]$_, "$([char]27)\[[0-9;]*m", '') })
        return (($written | Where-Object { $_ -match '^\s[A-Z]\s$' } |
            ForEach-Object { $_.Trim() }) -join ' ')
    }

    Assert-True ((Get-MenuKeys -Assistant 'on' -Brain 'on' -Employees 'on') -eq 'E T A M Z S Q') `
        'everything on, the finished menu offers every key it always did'
    Assert-True ((Get-MenuKeys -Assistant 'off' -Brain 'off' -Employees 'off') -eq 'Z S Q') `
        'everything off, only Zo, start over and close are left'
    Assert-True ((Get-MenuKeys -Assistant 'on' -Brain 'off' -Employees 'off') -eq 'A Z S Q') `
        'the assistant alone leaves A'
    Assert-True ((Get-MenuKeys -Assistant 'off' -Brain 'on' -Employees 'off') -eq 'M Z S Q') `
        'the second brain alone leaves M'
    Assert-True ((Get-MenuKeys -Assistant 'off' -Brain 'off' -Employees 'on') -eq 'E T Z S Q') `
        'employees alone leave E and T'

    # Hidden is not enough. A key that still fires while nothing on screen
    # mentions it is worse than a missing one, so the main loop gates each
    # letter on its feature as well as leaving it off the menu.
    foreach ($case in @(
        @{ Key = 'E'; Feature = 'FeatureAiEmployees'; What = 'hiring' },
        @{ Key = 'T'; Feature = 'FeatureAiEmployees'; What = 'the team list' },
        @{ Key = 'M'; Feature = 'FeatureSecondBrain'; What = 'the second brain' },
        @{ Key = 'A'; Feature = 'FeatureAiAssistant'; What = 'the assistant setup' }
    )) {
        $guard = "\`$choice -match '\^\[$($case.Key)$($case.Key.ToLower())\]' -and \(Test-FeatureOn \`$script:$($case.Feature)\)"
        Assert-True ($setupText -match $guard) `
            "pressing $($case.Key) cannot reach $($case.What) when it is switched off"
    }

    Write-Host ''
    Write-Host 'Start over renumbers itself' -ForegroundColor Cyan

    function Read-Host { param([string]$Prompt) return $script:Typed }
    function Reset-WhatsAppAssistant { Write-Host 'RAN_ASSISTANT' }
    function Reset-AiEmployees { Write-Host 'RAN_EMPLOYEES' }
    function Get-InstalledByUs { return @() }
    function Read-YesNo { param($Question, $YesLabel, $NoLabel) return $false }

    function Get-ResetScreen {
        param([string]$Assistant, [string]$Employees, [string]$Typed)
        $script:FeatureAiAssistant = $Assistant
        $script:FeatureAiEmployees = $Employees
        $script:Typed = $Typed
        return (@(Reset-VimigoSetup 6>&1 | ForEach-Object { [string]$_ }) -join "`n")
    }

    $three = Get-ResetScreen -Assistant 'on' -Employees 'on' -Typed ''
    $two = Get-ResetScreen -Assistant 'on' -Employees 'off' -Typed ''
    $one = Get-ResetScreen -Assistant 'off' -Employees 'off' -Typed ''
    Assert-True ($three -match 'Choose 1, 2 or 3, or Enter to go back') `
        'everything on, start over still offers three'
    Assert-True ($two -match 'Choose 1 or 2, or Enter to go back') `
        'employees off, it offers two and says so'
    # One option left is not hypothetical: switch both off and "Everything" is
    # all there is. Counting backwards from one would print "Choose 0, 1 or 1".
    Assert-True ($one -match 'Choose 1, or Enter to go back') `
        'both off, it offers one and still reads as a sentence'
    Assert-True ($one -match 'There is one thing to undo') `
        'and stops claiming you can undo just one part of it'
    Assert-True ($two -notmatch 'Your AI employees') `
        'the employee line is gone from the list'
    Assert-True ($one -notmatch 'How you talk to Zo') `
        'and so is the assistant line'
    Assert-True ($two -match 'Enter  go back, changing nothing') `
        'the way out is still written down'

    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'on' -Typed '1') -match 'RAN_ASSISTANT') `
        'everything on, 1 is the assistant'
    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'on' -Typed '2') -match 'RAN_EMPLOYEES') `
        'everything on, 2 lets an employee go'
    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'off' -Typed '1') -match 'RAN_ASSISTANT') `
        'employees off, 1 is still the assistant'
    # The one that bites. Hiding an option without renumbering leaves its old
    # number wired to it - a key nothing on screen mentions, quietly letting an
    # AI employee go, or wiping the assistant.
    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'off' -Typed '2') -notmatch 'RAN_EMPLOYEES') `
        'employees off, 2 never reaches the employee reset'
    Assert-True ((Get-ResetScreen -Assistant 'off' -Employees 'on' -Typed '1') -notmatch 'RAN_ASSISTANT') `
        'assistant off, 1 never reaches the assistant reset'
    Assert-True ((Get-ResetScreen -Assistant 'off' -Employees 'on' -Typed '1') -match 'RAN_EMPLOYEES') `
        'assistant off, 1 is the employee reset instead, as the screen says'
    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'off' -Typed '3') -match 'Nothing was changed') `
        'employees off, the old number 3 does nothing at all'
    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'on' -Typed '') -match 'Nothing was changed') `
        'Enter goes back without changing anything'
    Assert-True ((Get-ResetScreen -Assistant 'on' -Employees 'on' -Typed '08') -match 'Nothing was changed') `
        'a leading zero is read as text, not as a number'

    Write-Host ''
    Write-Host 'The /compile-data command' -ForegroundColor Cyan

    # Both halves, as shipped. A row that goes green while the zip is missing
    # the file it copies is the one failure nobody would find until the event.
    $eventDir = Join-Path $PSScriptRoot 'event'
    $skillFile = Join-Path (Join-Path $eventDir 'compile-data') 'SKILL.md'
    $chatgptFile = Join-Path $eventDir 'Submit my AI workflow - ChatGPT.txt'
    Assert-True (Test-Path -LiteralPath $skillFile) 'the command ships beside the setup'
    Assert-True (Test-Path -LiteralPath $chatgptFile) `
        'and so does the ChatGPT copy of it, for owners with no slash commands'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $eventDir 'codex-prompts') 'compile-data.md')) `
        'and the Codex prompt that makes it typable rather than merely available'

    $skillText = Get-Content -LiteralPath $skillFile -Raw
    Assert-True ($skillText -match '(?m)^name: compile-data$') `
        'the skill is named for the command the owner is told to type'

    # The address the whole thing exists to reach. Both halves carry it, because
    # a submission that lands in the owner's own Drive and is never shared with
    # anybody is indistinguishable from one that was never made.
    Assert-True ($skillText -like '*vimigoai@vimigoapp.com*') `
        'it knows the address to share the folder with'
    Assert-True ((Get-Content -LiteralPath $chatgptFile -Raw) -like '*vimigoai@vimigoapp.com*') `
        'and so does the ChatGPT copy'
    Assert-True ($skillText -like '*AI Workflow Submission*') `
        'it knows what the document is called'

    # The instruction most easily lost in an edit, and the one with a real cost:
    # an invented time saving in a document a CEO will consult on.
    Assert-True ($skillText -match '(?i)never invent a number') `
        'it is told not to invent results'

    # Where the owner's real work is. They are told to run this in Claude Code,
    # and Cowork - where most of the event happens - keeps its transcripts
    # somewhere Claude Code would never think to look. Losing this line in an
    # edit would not break anything visibly; it would just quietly return a
    # thinner review.
    # The way a correction reaches a machine set up weeks ago. The installed
    # copy is frozen; this URL is not, so the command checks it before doing
    # anything. If the address here and the file the publisher puts at that
    # address ever part company, late fixes reach nobody and nothing looks
    # wrong.
    Assert-True ($skillText -like '*raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/compile-data.md*') `
        'it knows where to find a newer copy of itself'
    Assert-True ($skillText -match '(?i)not a gate') `
        'and is told never to make the owner wait on that check'

    Assert-True ($skillText -like '*local-agent-mode-sessions*') `
        'it knows where Cowork keeps the conversations it must review'
    Assert-True ($skillText -like '*Library/Application Support/Claude*') `
        'and where to find them on a Mac'
    Assert-True ($skillText -like '*LOCALAPPDATA*') 'and on Windows'

    # The batch and the dates, pinned in both halves and checked against each
    # other.
    #
    # Step 1 of the skill filters the owner's files by the programme dates, so a
    # stale window matches nothing and the review comes back empty - which reads
    # as a broken command rather than a wrong date. This has been wrong twice:
    # shipped as V001 / July, corrected to V002 / August. Pinned here so the
    # third time is a failing test rather than a hundred and twenty empty
    # submissions.
    $chatgptText = Get-Content -LiteralPath $chatgptFile -Raw
    foreach ($half in @(@{ Name = 'the skill'; Text = $skillText },
                        @{ Name = 'the ChatGPT copy'; Text = $chatgptText })) {
        Assert-True ($half.Text -like '*V002*') "$($half.Name) names the batch it is for"
        Assert-True ($half.Text -like '*August 2026*') "$($half.Name) names the month it is for"
        Assert-True ($half.Text -notlike '*V001*') `
            "$($half.Name) does not still name the batch before it"
        # Second batch, so some owners already have a company folder holding a
        # submission with exactly the name this one is about to write. Both
        # halves reuse the folder by instruction, so without this they
        # overwrite it.
        Assert-True ($half.Text -like '*(V002)*') `
            "$($half.Name) keeps an earlier batch's submission rather than replacing it"
    }

    # The real functions, run against a sandbox rather than the tester's own
    # home, so nothing here lands in ~/.claude or on anybody's Desktop.
    ${function:Test-EventSkillInstalled} = $script:RealTestEventSkillInstalled
    ${function:Install-EventSkill} = $script:RealInstallEventSkill
    $fakeHome = Join-Path $sandbox 'home'
    $fakeDesktop = Join-Path $fakeHome 'Desktop'
    New-Item -ItemType Directory -Path $fakeDesktop -Force | Out-Null
    ${function:Get-EventCodexDest} = $script:RealGetEventCodexDest
    function Get-EventSkillDest { return (Join-Path $fakeHome '.claude\skills\compile-data') }
    function Get-EventCodexDest { return (Join-Path $fakeHome '.codex\skills\compile-data') }
    function Get-EventCodexPromptDest { return (Join-Path $fakeHome '.codex\prompts\compile-data.md') }
    function Get-EventChatgptDest { return (Join-Path $fakeDesktop 'Submit my AI workflow - ChatGPT.txt') }

    $script:FeatureEventSkill = 'on'
    $script:WantClaudeApp = $true
    $script:WantChatGptApp = $true
    Assert-True (-not (Test-EventSkillInstalled)) 'with neither half in place it is not done'

    Assert-True (Install-EventSkill 6>$null) 'installing it works with nothing to sign into'
    $claudeCopy = Join-Path (Get-EventSkillDest) 'SKILL.md'
    $codexCopy = Join-Path (Get-EventCodexDest) 'SKILL.md'
    Assert-True (Test-Path -LiteralPath $claudeCopy) `
        'the command lands where Claude looks for a personal skill'
    Assert-True (Test-Path -LiteralPath $codexCopy) `
        'and where ChatGPT looks, so both apps get the same command'
    # Verified on a real Codex: ~/.codex/skills makes it a skill the model can
    # pick, and ~/.codex/prompts makes /compile-data a command the owner can
    # type. Shane says the command out loud, so the typed one is not optional.
    Assert-True (Test-Path -LiteralPath (Get-EventCodexPromptDest)) `
        'and ChatGPT gets the typed command too, not just a skill it may choose'
    Assert-True ((Get-FileHash -LiteralPath $claudeCopy).Hash -eq (Get-FileHash -LiteralPath $codexCopy).Hash) `
        'and it is the same file in both, so the two cannot drift apart'
    Assert-True (Test-Path -LiteralPath (Get-EventChatgptDest)) `
        'the Desktop fallback is there too, for a Codex too old for skills'
    Assert-True (Test-EventSkillInstalled) 'and afterwards it reads as done'

    # An owner who chose one app must not be held back by the other one's half.
    # This is the mistake the Zo plan rows made: a row that can never go green
    # on a machine that answered the first question honestly.
    Remove-Item -LiteralPath (Get-EventCodexDest) -Recurse -Force
    Remove-Item -LiteralPath (Get-EventChatgptDest) -Force
    $script:WantChatGptApp = $false
    Assert-True (Test-EventSkillInstalled) `
        'a Claude owner is finished without the ChatGPT half they cannot use'

    Remove-Item -LiteralPath (Join-Path $fakeHome '.claude') -Recurse -Force
    $script:WantClaudeApp = $false
    $script:WantChatGptApp = $true
    $null = Install-EventSkill 6>$null
    Assert-True (-not (Test-Path -LiteralPath (Get-EventSkillDest))) `
        'a ChatGPT owner is not given a Claude skill they will never type'
    Assert-True (Test-EventSkillInstalled) 'and the Codex command alone finishes them'

    # The card is a spare, not a requirement. Held to that here, because a row
    # that stays red over an unused copy of some instructions is a row nobody
    # can fix.
    Remove-Item -LiteralPath (Get-EventChatgptDest) -Force
    Assert-True (Test-EventSkillInstalled) `
        'losing the Desktop fallback does not hold the row open'

    $script:WantClaudeApp = $true
    function Test-EventSkillInstalled { return $true }
    function Get-EventSkillDest { return (Join-Path $fakeHome '.claude\skills\compile-data') }
    function Get-EventCodexDest { return (Join-Path $fakeHome '.codex\skills\compile-data') }
    function Get-EventCodexPromptDest { return (Join-Path $fakeHome '.codex\prompts\compile-data.md') }

    # The row, in the list. Same two ends as Hermes One below it.
    Set-Features 'off'
    $script:FeatureEventSkill = 'on'
    $script:FixtureHasKey = $true
    $row = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'event-skill' })[0]
    Assert-True ($row.Status -eq 'ok' -and $row.Title -eq 'Your /compile-data command') `
        'an installed command reads as done'
    function Test-EventSkillInstalled { return $false }
    $row = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'event-skill' })[0]
    Assert-True ($row.Status -eq 'missing') 'a missing one reads as missing'
    function Test-EventSkillInstalled { return $true }

    # With no Zo key it must still appear: Get-AllChecks gives up early there,
    # and this row is built after that point.
    $script:FixtureHasKey = $false
    Assert-True (@(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'event-skill' }).Count -eq 1) `
        'with no Zo key at all it is still offered'
    Assert-True ((Test-CheckNow -Key 'event-skill').Done -eq $true) `
        'its own check answers here, without asking Zo'
    $script:FixtureHasKey = $true

    $script:FeatureEventSkill = 'off'
    Assert-True (@(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'event-skill' }).Count -eq 0) `
        'switched off, the row disappears completely'
    $script:FeatureEventSkill = 'on'

    Assert-True ($script:OwnerCompletes -notcontains 'event-skill') `
        'it never asks "have you finished that step?" about a file it copied'
    # Read out of the source rather than out of a variable: on this side the
    # list is local to the function that walks the outstanding rows, so there is
    # nothing to inspect at runtime. The Mac keeps the same list as a global and
    # its suite asserts on that.
    $setupText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vimigo-setup.ps1') -Raw
    $needsZoBlock = [regex]::Match($setupText, '\$needsZo = @\(([^)]*)\)').Groups[1].Value
    Assert-True ($needsZoBlock -notlike '*event-skill*') `
        'and it does not wait for a Zo key it has no use for'
    Assert-True ($needsZoBlock -like '*claude-mcp*') `
        'and that list was actually found, rather than read as empty'

    # It goes before Hermes One, which the CEO asked for as the final step.
    Set-Features 'off'
    $script:FeatureEventSkill = 'on'
    $script:FeatureHermes = 'on'
    $keys = @(Get-AllChecks 6>$null | ForEach-Object { $_.Key })
    Assert-True ([Array]::IndexOf($keys, 'event-skill') -lt [Array]::IndexOf($keys, 'hermes-app')) `
        'and it sits above Hermes One rather than after it'

    Write-Host ''
    Write-Host 'Hermes One, the last step' -ForegroundColor Cyan

    function Get-LastRowKey {
        param([string]$Hermes, [string]$Employees, [switch]$NoKey)
        Set-Features 'off'
        $script:FeatureHermes = $Hermes
        $script:FeatureAiEmployees = $Employees
        $script:FixtureHasKey = -not $NoKey
        $keys = @(Get-AllChecks 6>$null | ForEach-Object { $_.Key })
        if ($keys.Count -eq 0) { return '' }
        return $keys[-1]
    }

    Assert-True ((Get-LastRowKey -Hermes 'on' -Employees 'off') -eq 'zo-codex') `
        'it is the last row this setup can finish by itself'

    # The one that matters most. Get-AllChecks gives up early when Zo cannot be
    # reached, and this row is built after that point - so written in the
    # obvious place it would be missing from every machine without a key, which
    # is every machine the first time it is opened.
    Assert-True ((Get-LastRowKey -Hermes 'on' -Employees 'off' -NoKey) -eq 'zo-codex') `
        'with no Zo key at all it is still offered, and still above the plan rows'

    # The other early exit. Employees used to end the function outright, so
    # anything after it vanished on every build that ships with them off.
    Assert-True ((Get-LastRowKey -Hermes 'on' -Employees 'on') -eq 'zo-codex') `
        'switching AI employees back on does not push it above the rest'
    Assert-True ((Get-LastRowKey -Hermes 'on' -Employees 'off') -eq 'zo-codex') `
        'and switching them off again does not take it with them'

    Set-Features 'off'
    $script:FeatureHermes = 'off'
    $script:FixtureHasKey = $true
    Assert-True (@(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'hermes-app' }).Count -eq 0) `
        'switched off, the row disappears completely'

    $script:FeatureHermes = 'on'
    function Test-HermesInstalled { return $true }
    $row = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'hermes-app' })[0]
    Assert-True ($row.Status -eq 'ok' -and $row.Title -eq 'Hermes One') `
        'an installed Hermes One reads as done'
    function Test-HermesInstalled { return $false }
    $row = @(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'hermes-app' })[0]
    Assert-True ($row.Status -eq 'missing') 'a missing one reads as missing'

    # Answered on this computer. If it ever falls through to the Zo questions
    # it comes back "could not tell" on exactly the machines with no key.
    function Test-HermesInstalled { return $true }
    $script:FixtureHasKey = $false
    Assert-True ((Test-CheckNow -Key 'hermes-app').Done -eq $true) `
        'its own check answers here, without asking Zo'
    $script:FixtureHasKey = $true

    Assert-True ($script:OwnerCompletes -notcontains 'hermes-app') `
        'it never asks "have you finished that step?" about work it just did'

    Write-Host ''
    Write-Host 'Which Hermes build this computer gets' -ForegroundColor Cyan

    # A real install of this app writes no InstallLocation - checked against a
    # machine that has it - so the registry route has to read the executable
    # out of DisplayIcon instead, icon index and all. Asking for
    # InstallLocation first meant the whole registry route never fired once,
    # and what actually found the app was a guessed folder name.
    $exePath = Join-Path $sandbox 'hermes-agent.exe'
    Assert-True ((Get-HermesIconPath -Value "$exePath,0") -eq $exePath) `
        'the icon index is stripped off the end of the recorded path'
    Assert-True ((Get-HermesIconPath -Value "`"$exePath`"") -eq $exePath) `
        'and so are quotes around it'
    Assert-True ((Get-HermesIconPath -Value '') -eq '') `
        'an empty entry yields nothing rather than a stray path'

    # Two spellings of the same number. Compared as text without converting,
    # the published checksum never matches and every download looks damaged.
    $emptyHex = (Get-FileHash -InputStream ([IO.MemoryStream]::new()) -Algorithm SHA512).Hash
    $emptyB64 = [Convert]::ToBase64String(
        [Security.Cryptography.SHA512]::Create().ComputeHash([byte[]]@()))
    Assert-True ((ConvertFrom-HexHash -Hex $emptyHex) -eq $emptyB64) `
        'a hex checksum converts to the base64 form the project publishes'
    Assert-True ((ConvertFrom-HexHash -Hex 'abc') -eq '') `
        'a malformed checksum yields nothing rather than a wrong answer'
    Assert-True ((ConvertFrom-HexHash -Hex '') -eq '') `
        'and so does an empty one'

    # GitHub serves the version feed as application/octet-stream. Windows
    # PowerShell 5.1 hands Content back as a string and PowerShell 7 hands back
    # raw bytes - so matched as-is this found nothing on 7, and quietly
    # installed the pinned version every time on the newer of the two, which is
    # the one the launcher prefers.
    $feed = @"
version: 0.7.6
files:
  - url: hermes-desktop-0.7.6-setup.exe
    sha512: SUM_INDENTED
    size: 154543361
path: hermes-desktop-0.7.6-setup.exe
sha512: SUM_TOP_LEVEL
releaseDate: '2026-07-22T11:44:41.451Z'
"@
    foreach ($shape in @(
        @{ What = 'a string, as Windows PowerShell 5.1 returns it'; Body = $feed },
        @{ What = 'raw bytes, as PowerShell 7 returns them'
           Body = [Text.Encoding]::UTF8.GetBytes($feed) }
    )) {
        $captured = $shape.Body
        function Invoke-WebRequest { param($Uri, [switch]$UseBasicParsing, $TimeoutSec, $OutFile)
            return [pscustomobject]@{ Content = $captured } }
        $asset = Get-HermesWindowsAsset
        Assert-True ($null -ne $asset -and $asset.File -eq 'hermes-desktop-0.7.6-setup.exe') `
            "the current build is read when the feed arrives as $($shape.What)"
        # The top-level checksum, not the indented one. They describe the same
        # file here, but on the Mac feed the indented ones belong to each
        # processor and the top-level one belongs to whichever is listed first.
        Assert-True ($null -ne $asset -and $asset.Sha512 -eq 'SUM_TOP_LEVEL') `
            "and paired with the checksum beside it, not the one above"
    }

    function Invoke-WebRequest { param($Uri, [switch]$UseBasicParsing, $TimeoutSec, $OutFile)
        throw 'no network' }
    Assert-True ($null -eq (Get-HermesWindowsAsset)) `
        'an unreachable feed says nothing, so the pinned version is used'
    Remove-Item -LiteralPath 'function:Invoke-WebRequest' -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'Installed is not signed in' -ForegroundColor Cyan

    # An owner can open Claude, look at the login screen, and press Yes. Asking
    # only whether the app had ever been opened believed them. The Zo connection
    # is then written into a config the app only keeps for a logged-in user, so
    # the whole thing looks perfect and has no Zo in it.
    $signinDir = Join-Path $sandbox 'signin-claude'
    New-Item -ItemType Directory -Path $signinDir -Force | Out-Null
    function Get-ClaudeConfigPath { return (Join-Path $signinDir 'claude_desktop_config.json') }

    Assert-True (-not (Test-ClaudeSignedIn)) 'a Claude with no account attached is not signed in'

    # Signing in registers the device against an account id. Nothing writes
    # this before that happens.
    Set-Content -LiteralPath (Join-Path $signinDir 'ant-device-registry.json') `
        -Value '{"0838b294-3b8f-4907-b58c-7e4c1c117bca":{"x":1}}' -Encoding ASCII
    Assert-True (Test-ClaudeSignedIn) 'a registered device means an account has signed in'

    Remove-Item -LiteralPath (Join-Path $signinDir 'ant-device-registry.json') -Force
    Set-Content -LiteralPath (Join-Path $signinDir 'cowork-enabled-cli-ops.json') `
        -Value '{"ownerAccountId":"0838b294-3b8f-4907-b58c-7e4c1c117bca"}' -Encoding ASCII
    Assert-True (Test-ClaudeSignedIn) 'and so does an owner account recorded for Cowork'

    # A registry with no account id in it is not an account. It is what an app
    # that has been opened and not signed into leaves behind.
    Set-Content -LiteralPath (Join-Path $signinDir 'cowork-enabled-cli-ops.json') `
        -Value '{}' -Encoding ASCII
    Assert-True (-not (Test-ClaudeSignedIn)) 'an empty record is not mistaken for an account'

    ${function:Get-ClaudeConfigPath} = $script:RealGetClaudeConfigPath

    Write-Host ''
    Write-Host 'Nothing can be skipped' -ForegroundColor Cyan

    # Every step that reaches Wait-ForOwnerStep is required, so none of them is
    # offered with a key that moves on. The old wording said the opposite in as
    # many words, on the screen where it was least true.
    $setupSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vimigo-setup.ps1') -Raw
    # The printed line, not the phrase. Matching the phrase anywhere in the file
    # matches the comment that explains why the line was taken out, which is a
    # test that can only pass by deleting its own explanation.
    Assert-True ($setupSource -notlike "*Write-Info 'These are recommendations*") `
        'it no longer tells the owner that skipping is fine'
    Assert-True ($setupSource -notlike '*Skip and move on*') `
        'and offers no key that leaves a required step unfinished'
    Assert-True ($setupSource -like '*cannot be skipped*') `
        'it says plainly that the step has to be done'
    Assert-True ($setupSource -like "*'Have you signed in?'*") `
        'the sign-in steps ask whether they have signed in'
    Assert-True ($setupSource -like "*-NoLabel 'No, I will wait'*") `
        'and No means waiting, not moving on'

    Write-Host ''
    Write-Host 'Questions with only one answer are not asked' -ForegroundColor Cyan

    # A question the owner can only answer one way is not a choice, it is a
    # keypress - and several of these were worse than that, because the wrong
    # answer printed a reassurance that was no longer true.
    #
    # Matched on the call, never on the phrase. Every one of these removals left
    # a comment behind saying what used to be there and why it went, so matching
    # the wording alone would fail against the explanation - a test that can only
    # pass by deleting its own reasoning. That mistake has been made twice here
    # already.
    Assert-True ($setupSource -notlike '*Read-YesNo -Question "Do you have a paid*') `
        'the plan step stops asking whether they pay for a plan'
    Assert-True ($setupSource -like "*Write-Info 'Starting the sign-in*") `
        'and starts the sign-in on its own instead'

    # Pages the owner cannot get past without: opened, not offered.
    Assert-True ($setupSource -notlike '*-Question "Open the*download page*') `
        'a failed install opens the download page rather than offering to'
    Assert-True ($setupSource -notlike "*-Question 'Open the Zo sign-up page now*") `
        'and no account means the sign-up page opens'
    # Asserted on what the models step now does, not on the absence of its old
    # question: an optional offer to open an employee's page is worded
    # identically, so the wording alone cannot tell a removal from a survivor.
    Assert-True ($setupSource -like "*Write-Info 'Opening that page for you now.'*") `
        'and the models page opens, since five instructions were just given for it'

    # The other side of it, so this stays a sweep of pointless questions rather
    # than of questions. Anything that genuinely forks is still asked, and so is
    # the one step that wants administrator permission and a restart.
    Assert-True ($setupSource -like "*-Question 'Do you already have a Zo account?'*") `
        'a real choice - account or no account - is still put to the owner'
    Assert-True ($setupSource -like "*-Question 'Turn those Windows features on now?'*") `
        'and permission for an admin prompt and a restart is still asked for'

    Write-Host ''
    Write-Host 'A signed-in plan is not yet a plan Zo uses' -ForegroundColor Cyan

    # Zo reports whether a plan is signed in and nothing about whether the
    # provider is switched on, and it is the switching on that stops the per-use
    # charging. So the sign-in alone turns the row green, and an owner can finish
    # this setup paying for a plan and paying again per use.
    Assert-True ($setupSource -like "*Write-Warn 'Signing in only tells Zo who you are*") `
        'the half that cannot be checked is warned about, not mentioned in passing'
    Assert-True ($setupSource -like '*Zo keeps charging you per use*') `
        'in money, which is what an owner will act on'
    Assert-True ($setupSource -like "*'Have you signed in and switched it on?'*") `
        'and the plan step asks about both halves, not only the one it can check'

    Write-Host ''
    Write-Host 'A Zo trial that has ended' -ForegroundColor Cyan

    # Measured on the owner's own machine: Zo answers the sign-in with
    # "Lifecycle operation start denied for <account>: trial_ended", the setup
    # printed that at him word for word under "Could not start the sign-in", and
    # both plan rows were then listed as unfinished with "Press Enter to check
    # again" underneath - which checked again, for ever, and could never have
    # finished. Nothing on that screen said a trial had ended.
    $trialResult = [pscustomobject]@{
        ok = $false
        error = 'Lifecycle operation start denied for vimigotengku: trial_ended'
    }
    Assert-True (Test-ZoTrialEnded -Result $trialResult) 'an ended trial is told apart from every other refusal'
    Assert-True (-not (Test-ZoTrialEnded -Result ([pscustomobject]@{ ok = $false; error = 'Zo could not be reached' }))) `
        'and a refusal that is not the trial is left alone'
    Assert-True (-not (Test-ZoTrialEnded -Result $null)) 'no answer at all is not an ended trial'

    # The words, checked in the file, because this is the whole point of the
    # branch: an owner who reads "trial_ended" learns nothing they can act on.
    Assert-True ($setupSource -like '*Your Zo trial has ended.*') 'the owner is told the trial ended, in those words'
    Assert-True ($setupSource -like '*Add a plan to this Zo account?*') 'and asked which of the two ways on they want'
    Assert-True ($setupSource -like '*use a different*Zo account*') 'the second way being a different Zo account'

    # Both ways have to actually do something. Adding a plan opens the Zo;
    # switching accounts throws the expired key away first, because it is read
    # in a dozen places and any one of them would go on asking about the wrong
    # Zo.
    $resolveBody = [regex]::Match($setupSource,
        '(?s)function Resolve-ZoTrialEnded \{.*?\n\}').Value
    Assert-True ([bool]$resolveBody) 'the branch was found to check'
    Assert-True ($resolveBody -match 'Start-Process') 'adding a plan opens the page it is bought on'
    Assert-True ($resolveBody -match 'Remove-ZoToken') 'switching accounts removes the expired key first'
    Assert-True ($resolveBody -match 'Set-ZoTokenInteractive') 'and then asks for the new one'
    Assert-True ($resolveBody -match "workspaceUrl") 'and clears the address that belonged to the old account'

    # Once, not in a loop: the retry happens after the owner has dealt with it,
    # and a trial still dead after that is reported plainly rather than asked
    # about again on a screen they have already answered.
    $providerBody = [regex]::Match($setupSource,
        '(?s)function Connect-ZoAiProvider \{.*?\n\}').Value
    Assert-True (([regex]::Matches($providerBody, 'Resolve-ZoTrialEnded')).Count -eq 1) `
        'the owner is asked about the trial once, not in a loop'
    Assert-True ($providerBody -match 'still has no plan on it') `
        'and a trial still dead after that is said plainly, not as an error code'

    Write-Host ''
    Write-Host 'The setup starts without being asked to' -ForegroundColor Cyan

    # The first screen no longer asks permission to do the thing it was opened
    # to do. It still says what it is doing, because a screen that starts
    # installing in silence reads as a fault.
    $starting = (Show-MainOptions -Starting 6>&1 | Out-String)
    Assert-True ($starting -like '*Setting everything up for you*') `
        'the first pass says it is starting, rather than asking'
    Assert-True ($starting -notlike '*Press ENTER*') `
        'and does not ask for a keypress it no longer needs'

    # But only the first. A step that cannot succeed - an owner who has not
    # signed in, a website still open - brings the loop back here, and a screen
    # that began again unasked would retry it forever with nothing able to stop
    # it.
    $again = (Show-MainOptions 6>&1 | Out-String)
    Assert-True ($again -like '*Press ENTER*') `
        'a later pass asks again, so a failing step cannot spin unattended'

    # The finished screen has never had the box and still must not.
    $done = (Show-MainOptions -Finished 6>&1 | Out-String)
    Assert-True ($done -notlike '*Press ENTER*') `
        'and a finished setup offers no such box at all'
    Assert-True ($done -notlike '*Setting everything up*') `
        'nor claims to be starting something'

    Write-Host ''
    Write-Host 'The finished screen ends the setup, it does not open a menu' -ForegroundColor Cyan

    # "ALL DONE" is the screen an owner is most likely to be tapping at idly,
    # having just been told everything worked - so a key that removes what the
    # setup installed must not be sitting on it.
    function Get-FinishedMenuText {
        param([string]$FinishedMenu)
        $script:FeatureFinishedMenu = $FinishedMenu
        return ((@(Show-MainOptions -Finished 6>&1 |
            ForEach-Object { [regex]::Replace([string]$_, "$([char]27)\[[0-9;]*m", '') }) -join "`n"))
    }

    # The one case the deleted "quit both apps" warning was right about: a
    # restart the setup could not do. Said once mid-run to somebody who is not
    # reading closely, and without this never said again - so they finish on a
    # screen saying everything works, beside an app that cannot see Zo.
    $script:RestartPending = @('ChatGPT')
    $pending = ((@(Show-AllDone -RestartNeeded $false 6>&1 |
        ForEach-Object { [regex]::Replace([string]$_, "$([char]27)\[[0-9;]*m", '') }) -join "`n"))
    Assert-True ($pending -match 'close ChatGPT completely') `
        'a restart that failed is said again at the end, and names the app'
    Assert-True ($pending -match 'not just the window') `
        'and says what closing an app actually means'
    Assert-True ($pending -notmatch 'Claude') `
        'and never names an app that restarted perfectly well'
    $script:RestartPending = @()
    $clean = ((@(Show-AllDone -RestartNeeded $false 6>&1 |
        ForEach-Object { [regex]::Replace([string]$_, "$([char]27)\[[0-9;]*m", '') }) -join "`n"))
    Assert-True ($clean -notmatch 'One last thing') `
        'and says nothing at all when both apps restarted'

    Set-Features 'off'
    $plain = Get-FinishedMenuText -FinishedMenu 'off'
    Assert-True ($plain -notmatch 'Start over') 'Start over is gone from the finished screen'
    Assert-True ($plain -notmatch 'Open your Zo') 'and so is Open your Zo'
    Assert-True ($plain -notmatch 'WARNING') 'and the warning that went with it'
    Assert-True ($plain -match 'Close') 'Close is still offered, so there is a way out'
    Assert-True ($plain -notmatch 'What you can do') `
        'and the header goes too, rather than sitting above a lone Close'

    $full = Get-FinishedMenuText -FinishedMenu 'on'
    Assert-True ($full -match 'Start over' -and $full -match 'Open your Zo') `
        'switched on, both come back exactly as they were'
    Assert-True ($full -match 'What you can do') 'and the header with them'
    $script:FeatureFinishedMenu = 'off'

    # Hidden is not enough on its own. This suite's own rule, written when the
    # other switches went in: a key that still works while nothing offers it is
    # worse than a missing one, because it fires by accident and nothing on
    # screen explains what just happened.
    $dispatch = [regex]::Matches($setupText, "\`$choice -match '\^\[Ss\]'[^\r\n]*")
    Assert-True ($dispatch.Count -eq 1 -and $dispatch[0].Value -match 'FeatureFinishedMenu') `
        'and the S key itself is gated, not merely hidden'
    $dispatchZ = [regex]::Matches($setupText, "\`$choice -match '\^\[Zz\]'[^\r\n]*")
    Assert-True ($dispatchZ.Count -eq 1 -and $dispatchZ[0].Value -match 'FeatureFinishedMenu') `
        'as is the Z key'

    # Taken off the screen, not taken away.
    Assert-True ($setupText -match '\[switch\]\$Reset') `
        'starting over is still reachable, by asking for it on purpose'

    Write-Host ''
    Write-Host 'Claude Desktop features: on, and honest about what it can fix' -ForegroundColor Cyan

    # On, because the training uses Cowork and Claude Code rather than Chat - an
    # owner who arrives with a greyed-out Cowork button cannot take part. It is
    # still the most invasive thing here, so it has to be right about whether it
    # can work before asking for permission, the hypervisor and a restart.
    Assert-True (Test-FeatureOn $script:FeatureClaudeFeatures) `
        'it ships on, because Cowork is what the event actually uses'
    # Claude present, said here rather than inherited. An earlier block left
    # $script:WantClaude false, and Test-ClaudeDesktopInstalled follows it - so
    # this measured "no Claude, therefore no row" and read as the switch
    # working. A test that passes for the wrong reason is worse than one that
    # fails.
    $script:WantClaude = $true
    Set-Features 'off'
    $script:FixtureHasKey = $true
    function Test-HcsServicesPresent { return $false }

    $script:FeatureClaudeFeatures = 'off'
    Assert-True (@(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'claude-hcs' }).Count -eq 0) `
        'switched off, the row is gone even with Claude installed and the features missing'

    $script:FeatureClaudeFeatures = 'on'
    Assert-True (@(Get-AllChecks 6>$null | Where-Object { $_.Key -eq 'claude-hcs' }).Count -eq 1) `
        'switched on, it comes back exactly as it was'
    $script:FeatureClaudeFeatures = 'off'

    # All three names Claude prints, not two of them. With vfpext missing and
    # the other two present this reported "working" while Claude went on showing
    # "Missing HCS services: HNS, vmcompute, vfpext" - a green row and an
    # unchanged error, which is worse than a red one.
    $hcsCheck = [regex]::Match($setupText, "foreach \(\`$service in @\(([^)]*)\)\) \{")
    Assert-True ($hcsCheck.Success -and $hcsCheck.Groups[1].Value -match 'vfpext') `
        'the check asks for vfpext, which Claude names and this used to ignore'
    foreach ($name in @('vmcompute', 'hns')) {
        Assert-True ($hcsCheck.Success -and $hcsCheck.Groups[1].Value -match $name) `
            "and still asks for $name"
    }

    # Installed-and-stopped is a real state, and it looks exactly like
    # not-installed to the owner: Claude prints the same "Missing HCS services"
    # either way. Asking only whether they exist reported that machine as fixed,
    # and the repair then said "already fixed, nothing to do" without starting
    # anything - a green row above a greyed-out Cowork button.
    ${function:Test-HcsServicesPresent} = $script:RealTestHcsServicesPresent
    $script:FakeServices = @{}
    function Get-Service {
        param([string]$Name, $ErrorAction)
        if ($script:FakeServices.ContainsKey($Name)) {
            return [pscustomobject]@{ Name = $Name; Status = $script:FakeServices[$Name] }
        }
        return $null
    }

    $script:FakeServices = @{ vmcompute = 'Running'; hns = 'Running'; vfpext = 'Running' }
    Assert-True (Test-HcsServicesPresent) 'all three running counts as working'

    $script:FakeServices = @{ vmcompute = 'Running'; hns = 'Stopped'; vfpext = 'Running' }
    Assert-True (-not (Test-HcsServicesPresent)) `
        'installed but stopped does not, because Claude says the same thing either way'

    $script:FakeServices = @{ vmcompute = 'Running'; hns = 'Running' }
    Assert-True (-not (Test-HcsServicesPresent)) `
        'and neither does two of the three, however healthy they look'

    # Nothing to start when one is absent - that needs the features installing,
    # which is a different and far more expensive answer.
    $script:FakeServices = @{ vmcompute = 'Running'; hns = 'Running' }
    Assert-True (-not (Start-HcsServices)) `
        'starting services is not attempted when one is missing altogether'

    $script:FakeServices = @{ vmcompute = 'Running'; hns = 'Running'; vfpext = 'Running' }
    Assert-True (Start-HcsServices) `
        'and three already running needs no permission at all'

    Remove-Item -LiteralPath 'function:Get-Service' -ErrorAction SilentlyContinue

    # The cheap answer is tried before the expensive one.
    $repairOrder = [regex]::Match($setupText, '(?s)function Repair-HcsServices \{(.*?)\n\}')
    if ($repairOrder.Success) {
        $b = $repairOrder.Groups[1].Value
        Assert-True (($b.IndexOf('Start-HcsServices') -ge 0) -and
                     ($b.IndexOf('Start-HcsServices') -lt $b.IndexOf('dism.exe'))) `
            'starting the services is tried before switching on the hypervisor'
    }

    # Firmware is asked about before any of it is offered.
    Assert-True ($setupText -match 'function Test-VirtualisationInFirmware') `
        'it can tell whether virtualisation is on in the firmware'
    $repair = [regex]::Match($setupText,
        '(?s)function Repair-HcsServices \{(.*?)\n\}')
    Assert-True ($repair.Success) 'the repair step was found to check'
    if ($repair.Success) {
        $body = $repair.Groups[1].Value
        $firmwareAt = $body.IndexOf('Test-VirtualisationInFirmware')
        $elevateAt = $body.IndexOf('RunAs')
        Assert-True ($firmwareAt -ge 0 -and $elevateAt -ge 0 -and $firmwareAt -lt $elevateAt) `
            'and asks the firmware before asking the owner for permission'
        Assert-True ($body -match 'Cowork') `
            'and says out loud that this only affects Cowork'
    }
    # Unknown must count as yes: a machine that cannot answer should not be
    # refused a fix it might well need.
    Assert-True ($setupText -match '(?s)Test-VirtualisationInFirmware.*?catch \{\s*return \$true') `
        'a machine that cannot answer is given the benefit of the doubt'

    # The bug these guard shipped, and it made the whole step a no-op.
    #
    # The dism calls were joined into one string with ; - the separator
    # PowerShell has and cmd.exe does not. cmd read it as an ordinary argument,
    # started the first dism.exe and handed it everything after it, including a
    # second program name, and dism refused the malformed call. Nothing was
    # enabled. The owner was still told the features had been asked for and still
    # restarted into the identical greyed-out Cowork button.
    #
    # Every assertion above this one passed while that was true. They check which
    # services are asked about, in what order, and whether the firmware is
    # consulted first - and not one of them ever looked at what was handed to
    # cmd.exe at all. So that is what is checked here.
    #
    # The separator is gone rather than corrected: the calls go into a batch file
    # one to a line. This asserts it stays gone, because reintroducing a joined
    # string is the one edit that would bring the whole bug back.
    Assert-True ($setupText -notmatch "dism\.exe[^`n]*`"\s*\}\s*\)\s*-join") `
        'the dism calls are not joined into one string for cmd.exe to mis-read'

    # Scoped to the sc.exe calls rather than the whole file. "No -join with ;
    # anywhere" was the first version of this and it failed on Update-SessionPath,
    # which joins PATH with ; and is completely correct to do so. The thing worth
    # asserting is narrower: the two places in this file that build a command
    # line for cmd.exe must use cmd.exe's separator.
    $startHcs = [regex]::Match($setupText, '(?s)function Start-HcsServices \{(.*?)\n\}')
    Assert-True ($startHcs.Success) 'the service-starting step was found to check'
    if ($startHcs.Success) {
        $scJoin = [regex]::Match($startHcs.Groups[1].Value, "(?s)sc\.exe.*?-join\s*'([^']*)'")
        Assert-True ($scJoin.Success -and $scJoin.Groups[1].Value -match '&') `
            'and its sc.exe calls are joined with & rather than a PowerShell ;'
    }
    if ($repair.Success) {
        $body = $repair.Groups[1].Value
        Assert-True ($body -match '(?s)foreach \(\$feature in \$features\).*?dism\.exe /online /enable-feature') `
            'each feature gets a dism call of its own, written a line at a time'

        # The other half of the same bug: the step announced success and sent the
        # owner off to restart whatever had actually happened. A run in which
        # dism refused every call ended in a restart and an unchanged error.
        Assert-True ($body -match '%errorlevel%') `
            'and each call records what it returned'
        Assert-True ($body -match "@\('0', '3010'\)") `
            'which is then read back, counting only 0 and 3010 as done'
        $goodAt = $body.IndexOf("Write-Good 'All of those features are now switched on.'")
        $failAt = $body.IndexOf('$failed.Count -eq 0')
        Assert-True ($goodAt -ge 0 -and $failAt -ge 0 -and $failAt -lt $goodAt) `
            'so success is claimed only after checking, never before'
        Assert-True ($body -match 'Windows would not switch all of them on') `
            'and a partial failure names the features that refused, for support'
    }

    # Three services, three different features. Containers brings vmcompute and
    # neither of the other two, and /all does not reach them: it enables what a
    # feature depends on, upward, and has never switched on a child. Asking for
    # Containers alone could only ever have fixed one of the three.
    foreach ($feature in @('VirtualMachinePlatform', 'HypervisorPlatform',
                           'Containers', 'Containers-HNS', 'Containers-SDN')) {
        Assert-True ($setupText -match [regex]::Escape("'$feature'")) `
            "the features asked for include $feature"
    }

    Write-Host ''
    Write-Host 'A default Windows blocks scripts, and the way in must survive it' -ForegroundColor Cyan

    # The bug this guards shipped, and a customer found it.
    #
    # Windows is Restricted out of the box: it refuses to run a .ps1 FILE at
    # all. Text piped into iex is never checked, so the one-line installer ran
    # perfectly right up to its last line, then died on "running scripts is
    # disabled on this system" - in red, after everything had downloaded.
    #
    # It could not have been caught here by running it: the machine this was
    # written on is RemoteSigned, so it never met the wall it was creating.
    # What is checkable is that the instruction is present at all.
    function Get-InstallerText {
        param([string]$Published, [string]$Development)
        foreach ($candidate in @(
            (Join-Path (Split-Path -Parent $PSScriptRoot) $Published),
            (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) $Development)
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return (Get-Content -LiteralPath $candidate -Raw)
            }
        }
        return ''
    }

    foreach ($installer in @(
        @{ Published = 'install-windows.ps1'
           Development = 'public-install-windows.ps1'
           What = 'the one-line installer' },
        @{ Published = 'install-assistant-windows.ps1'
           Development = 'public-install-assistant-windows.ps1'
           What = 'the assistant one-liner' }
    )) {
        $text = Get-InstallerText -Published $installer.Published -Development $installer.Development
        Assert-True ($text -ne '') "$($installer.What) was found to check"
        # Process scope and no other. CurrentUser or LocalMachine would change
        # the owner's machine permanently to install one program, which is not
        # ours to do; Process lasts as long as the window and outranks both.
        Assert-True ($text -match "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass") `
            "$($installer.What) lifts the block for its own window only"
        Assert-True ($text -notmatch "Set-ExecutionPolicy -Scope (CurrentUser|LocalMachine)") `
            "$($installer.What) never changes the machine's own setting"
        # And the second way through, for a managed laptop where group policy
        # refuses even that: read the file and run its text, which no policy
        # governs. The owner is never told to change a Windows security setting
        # and never sent to find a file to double-click.
        Assert-True ($text -match "ScriptBlock\]::Create") `
            "$($installer.What) still starts where the block cannot be lifted"
        Assert-True ($text -match "VIMIGO_SETUP_DIR") `
            "$($installer.What) says where the setup lives, since text has no script root"
        # Decided by asking the policy, not by catching a failure. Catching
        # cannot tell "refused" from "the setup stopped", and guessing wrong
        # runs the whole setup twice on somebody's machine.
        Assert-True ($text -match "Get-ExecutionPolicy") `
            "$($installer.What) chooses its route by asking, not by failing first"

        # Pinned to a version, the command printed on the README fetches that
        # version for ever - so a fix ships and nobody who follows the
        # instructions receives it. releases/latest/download is a plain
        # redirect onto the newest release, and finds its asset by name, which
        # is why the name it asks for carries no version.
        Assert-True ($text -match "releases/latest/download/") `
            "$($installer.What) always fetches the newest release"
        Assert-True ($text -notmatch "releases/download/v[0-9]") `
            "$($installer.What) is not pinned to one version"
        # Not the API, which answers the same question and allows sixty calls
        # an hour per address. A room of a hundred and twenty people shares one
        # address, so it would serve the first few laptops and refuse the rest.
        Assert-True ($text -notmatch "api\.github\.com") `
            "$($installer.What) does not ask an API that a full room would exhaust"
    }

    # The fallback the setup script needs for that route to work at all.
    Assert-True ($setupText -match 'function Get-SetupRoot') `
        'the setup can find its own folder when it is run as text'
    Assert-True ($setupText -notmatch 'Join-Path \$PSScriptRoot') `
        'and nothing still builds a path from $PSScriptRoot directly'
    # Run as text, $PSScriptRoot is empty and every path built from it pointed
    # at the drive root, so the Zo helper beside the script was never found.
    $realRoot = $env:VIMIGO_SETUP_DIR
    try {
        $env:VIMIGO_SETUP_DIR = $PSScriptRoot
        Assert-True ((Get-SetupRoot) -eq $PSScriptRoot) `
            'and it resolves to the real folder either way'
    } finally { $env:VIMIGO_SETUP_DIR = $realRoot }

    # The double-click path has always had this right, and is the fallback the
    # installer points people at when both attempts fail.
    $batPath = @(
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'Setup-Windows.bat'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'setup\Setup-Windows.bat')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    Assert-True ($null -ne $batPath) 'Setup-Windows.bat was found to check'
    if ($batPath) {
        $bat = Get-Content -LiteralPath $batPath -Raw
        Assert-True (([regex]::Matches($bat, '-ExecutionPolicy Bypass')).Count -ge 2) `
            'and it still passes the same flag for both PowerShell 7 and 5.1'
    }

    Write-Host ''
    Write-Host 'The two setups agree on what they offer' -ForegroundColor Cyan

    # A Mac and a Windows machine offering different setups is worse than either
    # answer on its own, and nothing else would notice: the two scripts share no
    # code, only a promise to stay in step.
    $macText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vimigo-setup.sh') -Raw
    foreach ($pair in @(
        @{ Win = 'AiAssistant'; Mac = 'AI_ASSISTANT'; What = 'the AI Personal Assistant' },
        @{ Win = 'ZoSkills';    Mac = 'ZO_SKILLS';    What = 'the Zo skills' },
        @{ Win = 'SecondBrain'; Mac = 'SECOND_BRAIN'; What = 'the second brain' },
        @{ Win = 'AiEmployees'; Mac = 'AI_EMPLOYEES'; What = 'AI employees' },
        @{ Win = 'Hermes';      Mac = 'HERMES';       What = 'Hermes One' }
    )) {
        # ' +=' and not ' =': the declarations are column-aligned, so some carry
        # several spaces before the equals. Insisting on exactly one read those
        # as absent, and an absent default passes half a drift check silently.
        $winMatch = [regex]::Match($setupText, "\`$script:Feature$($pair.Win) += '([a-z]+)'")
        $macMatch = [regex]::Match($macText, "(?m)^FEATURE_$($pair.Mac)='([a-z]+)'")
        Assert-True ($winMatch.Success -and $macMatch.Success -and
            $winMatch.Groups[1].Value -eq $macMatch.Groups[1].Value) `
            "both scripts ship the same answer for $($pair.What)"
    }

    Write-Host ''
    Write-Host 'The switch is generous about what counts as yes' -ForegroundColor Cyan

    foreach ($word in @('on', 'ON', 'On', 'yes', 'true', '1', ' on ')) {
        Assert-True (Test-FeatureOn $word) "'$word' turns a feature on"
    }
    foreach ($word in @('off', 'OFF', 'no', 'false', '0', '', 'maybe', 'onn')) {
        Assert-True (-not (Test-FeatureOn $word)) "'$word' leaves it off"
    }

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
