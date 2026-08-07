# Vimigo - the AI Personal Assistant, on its own.
#
#   irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-assistant-windows.ps1 | iex
#
# The main setup connects Claude and ChatGPT on the laptop to the owner's Zo.
# This is the other half: a WhatsApp or Telegram number the owner can message
# from their phone, answered by their Zo.
#
# It is deliberately not on the front page. v1 ships without it, and this is
# for somebody who has asked for it - not something a first-time customer
# stumbles into.

$ErrorActionPreference = 'Stop'

$release = 'https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/v1.0/vimigo-company-os-setup-windows-v1.0.zip'
$folder = 'Vimigo AI Setup'

function Stop-Here {
    param([string]$Why)
    Write-Host ''
    Write-Host "  $Why" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Nothing was changed. Tell Vimigo support what this said.'
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host '  Vimigo - AI Personal Assistant' -ForegroundColor Cyan
Write-Host ''

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop = $env:USERPROFILE }
$target = Join-Path $desktop $folder
$setup = Join-Path $target 'Vimigo files\vimigo-setup.ps1'

# Reuse the folder the main setup left, when it is there. Downloading a second
# copy would leave two on the Desktop and the owner guessing which is current.
if (Test-Path -LiteralPath $setup) {
    Write-Host '  Using the setup already on your Desktop.'
} else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('vimigo-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        Write-Host '  Downloading. This takes a moment.'
        $zip = Join-Path $work 'setup.zip'
        $previous = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $release -OutFile $zip -UseBasicParsing -TimeoutSec 300
        } finally {
            $ProgressPreference = $previous
        }

        Write-Host '  Unpacking...'
        $out = Join-Path $work 'out'
        Expand-Archive -LiteralPath $zip -DestinationPath $out -Force

        $inner = Get-ChildItem -LiteralPath $out -Recurse -Directory -Filter 'Vimigo files' |
            Select-Object -First 1
        if (-not $inner) { Stop-Here 'That download did not contain the setup.' }

        if (Test-Path -LiteralPath $target) {
            $n = 1
            while (Test-Path -LiteralPath "$target (old $n)") { $n++ }
            Rename-Item -LiteralPath $target -NewName "$folder (old $n)" -ErrorAction Stop
        }
        Move-Item -LiteralPath $inner.Parent.FullName -Destination $target -ErrorAction Stop
    } catch {
        Stop-Here "Could not download it: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $setup)) { Stop-Here 'The setup file is missing.' }

Write-Host ''
Write-Host '  Setting up your assistant...'
Write-Host ''
Start-Sleep -Seconds 1

# Run in this window, so the owner answers its questions where they already are.
& $setup -Assistant
