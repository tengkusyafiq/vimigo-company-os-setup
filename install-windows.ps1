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

$release = 'https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/v1.0/vimigo-company-os-setup-windows-v1.0.zip'
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

# Run in this window, so the owner answers its questions where they already
# are. & and not Start-Process: a new window would close on its own the moment
# anything went wrong, taking the reason with it.
& $setup
