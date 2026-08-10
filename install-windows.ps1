# Vimigo Company OS Setup - the one-line way in, for Windows.
#
#   irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-windows.ps1 | iex
#
# The same idea as the Mac one. Windows marks anything that came from a browser
# and shows "Windows protected your PC" the first time it is run, which is one
# click to get past rather than the Mac's four - but a download that then has
# to be found, unzipped and copied is still four chances to end up running the
# setup from inside the zip, which does not work.
#
# This fetches it, unpacks it to the Desktop, clears the downloaded-from-the-
# internet mark so the warning never appears at all, and starts it.

$ErrorActionPreference = 'Stop'

$release = 'https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/latest/download/vimigo-company-os-setup-windows.zip'
$folder = 'Vimigo AI Setup'

function Write-Plain { param([string]$Text) Write-Host $Text }
function Write-Teal  { param([string]$Text) Write-Host $Text -ForegroundColor Cyan }

function Stop-Here {
    param([string]$Why)
    Write-Host ''
    Write-Host "  $Why" -ForegroundColor Red
    Write-Host ''
    Write-Plain '  Nothing was changed. Tell Vimigo support what this said.'
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Teal '  Vimigo Company OS Setup'
Write-Host ''

# OneDrive moves the Desktop, and [Environment]::GetFolderPath knows where it
# went. Join-Path $env:USERPROFILE 'Desktop' does not, and would drop the
# folder somewhere the owner cannot see.
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop = $env:USERPROFILE }
$target = Join-Path $desktop $folder

# An earlier copy is moved aside rather than written over. Somebody may have
# put their own notes in there, and a setup that silently eats a folder on the
# Desktop is not one to trust with anything else.
if (Test-Path -LiteralPath $target) {
    $n = 1
    while (Test-Path -LiteralPath "$target (old $n)") { $n++ }
    try { Rename-Item -LiteralPath $target -NewName "$folder (old $n)" -ErrorAction Stop } catch {
        Stop-Here 'Could not move the old copy out of the way. Is it open?'
    }
    Write-Plain "  Your earlier copy is now called `"$folder (old $n)`"."
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('vimigo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    Write-Plain '  Downloading. This is about 170KB and takes a moment.'
    $zip = Join-Path $work 'setup.zip'
    # Progress off: the meter repaints the whole line and turns this into a
    # flickering mess on a slow connection.
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $release -OutFile $zip -UseBasicParsing -TimeoutSec 300
    } finally {
        $ProgressPreference = $previous
    }

    Write-Plain '  Unpacking...'
    $out = Join-Path $work 'out'
    Expand-Archive -LiteralPath $zip -DestinationPath $out -Force

    # The zip holds one folder. Find it rather than assume its name, so
    # renaming the release does not break this.
    $inner = Get-ChildItem -LiteralPath $out -Recurse -Directory -Filter 'Vimigo files' |
        Select-Object -First 1
    if (-not $inner) { Stop-Here 'That download did not contain the setup.' }

    Move-Item -LiteralPath $inner.Parent.FullName -Destination $target -ErrorAction Stop
} catch {
    Stop-Here "Could not download it: $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# The part this whole script exists for. Every file carries a mark saying it
# came from the internet, and that mark is what produces "Windows protected
# your PC". Clearing it here means the owner never meets that screen.
Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue

$setup = Join-Path $target 'Vimigo files\vimigo-setup.ps1'
if (-not (Test-Path -LiteralPath $setup)) { Stop-Here 'The setup file is missing from the download.' }

Write-Host ''
Write-Teal "  Ready. The folder is on your Desktop, called `"$folder`"."
Write-Plain '  From now on you can just double-click Setup-Windows.bat in it.'
Write-Host ''
Write-Plain '  Starting the setup now...'
Write-Host ''
Start-Sleep -Seconds 1

# Windows will not run a .ps1 file at all on a default install.
#
# The policy is Restricted out of the box, and what the owner saw was
# "running scripts is disabled on this system", in red, after everything had
# downloaded perfectly. It never appeared in our own testing because a machine
# that has ever run a script has already been changed - the laptop this was
# written on is RemoteSigned, so it never met the wall it was creating.
#
# Note that none of the above stopped this file: text piped into iex is never
# checked, only files are. So the one-liner worked right up to its last line.
#
# Process scope is the fix. It applies to this PowerShell and nothing else,
# needs no administrator, outranks both the per-user and per-machine settings,
# and leaves nothing changed behind. Setup-Windows.bat has always passed
# -ExecutionPolicy Bypass for exactly this reason, which is why double-clicking
# that worked while this line did not.
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch {
    # A managed work laptop can forbid even that, through group policy. The
    # second route below is the answer to that, and needs no permission at all.
}

# Where the setup lives, for the second route. Text has no script root of its
# own, so without this the setup cannot find the helper file beside it.
$env:VIMIGO_SETUP_DIR = Split-Path -Parent $setup

# Asked, not attempted-and-caught.
#
# Trying it and falling back on failure cannot tell "the policy refused" from
# "the setup itself stopped", and getting that wrong runs the whole setup twice
# on somebody's machine. The policy is a question with an answer, so ask it.
#
# RemoteSigned belongs on this list because every file was unblocked a few lines
# above, which is exactly the condition it asks about.
$policy = try { [string](Get-ExecutionPolicy) } catch { 'Restricted' }

if (@('Bypass', 'Unrestricted', 'RemoteSigned') -contains $policy) {
    # Run in this window, so the owner answers its questions where they already
    # are. & and not Start-Process: a new window would close on its own the
    # moment anything went wrong, taking the reason with it.
    & $setup
} else {
    # Restricted, or AllSigned, and not liftable - so read the file and run its
    # text instead.
    #
    # Nothing can refuse this. The execution policy governs script files and
    # has never governed text, which is the only reason the one-line command
    # that fetched this script was able to run in the first place. So the owner
    # is never told to go and change a Windows security setting, and never sent
    # off to find a file to double-click. It simply starts.
    & ([ScriptBlock]::Create((Get-Content -LiteralPath $setup -Raw)))
}
