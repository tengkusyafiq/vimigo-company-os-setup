# Vimigo - connect your WhatsApp.
#
#   irm https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/install-whatsapp-windows.ps1 | iex

$ErrorActionPreference = 'Stop'
# Its own release tag, deliberately not the repository's v1.0.
#
# v1.0 is the company-os setup's own release, six days old and already
# superseded by v1.11. Hanging the WhatsApp asset off it would mean any tidy-up
# of old releases silently breaks every WhatsApp install, and that the two
# artefacts - which version independently - share a tag that describes only one
# of them. The pin below makes this URL exact, so it must point somewhere that
# changes only when this artefact does.
$release = 'https://github.com/tengkusyafiq/vimigo-company-os-setup/releases/download/whatsapp-v1.12/vimigo-whatsapp-windows-v1.12.zip'

# The trust anchor for everything that follows.
#
# Install-Binaries verifies each binary against manifest.json - which lives
# INSIDE the zip it is verifying, so it catches a truncated download and
# nothing else: anyone who can substitute the asset ships a matching manifest.
# This line is fetched separately over TLS and is the only thing outside the
# archive that says anything about it. Task 13 regenerates it from the asset
# it is about to upload, in the same step, so the two cannot diverge.
$ZipSha256 = '8744c2fe4cc29ca111428611e4e3799a62166c20d97b5cd7f187244dcfbcd976'
$root      = Join-Path $env:LOCALAPPDATA 'Vimigo\whatsapp'

function Stop-Here {
    param([string]$Why)
    Write-Host ''
    Write-Host "  $Why" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Nothing was changed. Tell Vimigo support what this said.'
    Write-Host ''
    exit 1
}

# For after the doer has been handed control, and only for that.
#
# Every Stop-Here above it is a genuine no-change path: the install root does
# not exist yet, so "Nothing was changed" is simply true. Once the doer is
# running that stops being true - it may have written its bin\, registered its
# scheduled task and edited a client config before falling over - and telling
# the owner nothing was changed sends them to support with the wrong story and
# support to the wrong place. Same wording as the Mac one-liner, line for line.
function Stop-Partway {
    param([string]$Why)
    Write-Host ''
    Write-Host "  $Why" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Tell them what you saw on this screen.'
    Write-Host ''
    exit 1
}

# ASCII only, on purpose. The main setup draws its banner in box-drawing
# characters, but it controls the console encoding before it does; this runs
# through `irm | iex` in whatever window the owner happened to open, and a
# banner that arrives as mojibake is worse than no banner at all. Same three
# lines as the mac one-liner, character for character.
Write-Host ''
Write-Host '  ==============================================' -ForegroundColor Cyan
Write-Host '     V I M I G O   W H A T S A P P   S E T U P' -ForegroundColor Cyan
Write-Host '  ==============================================' -ForegroundColor Cyan
Write-Host ''

# Everything happens here until it is known good. The install root is not
# created, and nothing is written into it, until there is something verified
# to put there - so the failure path really does leave nothing behind, and
# 28 MB of unverified binaries never sit in the root pretending to be an
# install.
$work = Join-Path ([IO.Path]::GetTempPath()) ('vimigo-wa-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    $zip = Join-Path $work 'download.zip'

    try {
        Write-Host '  Downloading. This takes a moment.'
        $previous = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -Uri $release -OutFile $zip -UseBasicParsing -TimeoutSec 600 }
        finally { $ProgressPreference = $previous }
    } catch {
        Stop-Here 'Could not download it. Check you are online and try again.'
    }

    # Checked BEFORE anything is extracted. A truncated download otherwise
    # reaches Expand-Archive, which throws a raw runtime error at the owner
    # instead of one plain sentence.
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ZipSha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Stop-Here 'That download did not arrive properly. Please try again.'
    }

    $extracted = Join-Path $work 'extracted'
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $extracted -Force
    } catch {
        Stop-Here 'That download could not be opened. Please try again.'
    }

    Get-ChildItem -LiteralPath $extracted -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    $staged = Join-Path $extracted 'vimigo-whatsapp.ps1'
    if (-not (Test-Path -LiteralPath $staged)) { Stop-Here 'That download did not contain the setup.' }

    # Only now does the install root come into existence, and only the doer
    # goes into it. The binaries stay in the zip: Install-Binaries is the one
    # thing that ever writes <root>\bin, so a half-extracted tree can never
    # be mistaken for a healthy install.
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $setup = Join-Path $root 'vimigo-whatsapp.ps1'
    Copy-Item -LiteralPath $staged -Destination $setup -Force

    # irm | iex runs in memory and is not policy-checked; loading a .ps1 from
    # disk is, and Windows client SKUs default to Restricted. Without this a
    # stock Windows 11 Home laptop shows red text with a file path and an
    # about_Execution_Policies URL instead of Stop-Here. Process scope needs
    # no admin and lasts only for this window.
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

    # Cleared before the call, not read on trust afterwards. $LASTEXITCODE is
    # NOT reset by a script that returns normally - it keeps whatever the last
    # native command left in it - and `irm | iex` runs all of this inside the
    # owner's own session, where that could be anything. Unset, it is $null,
    # and `$null -ne 0` is true. Either way a perfectly good install would be
    # reported as a failure. Proven: set it to 99, call a .ps1 that just
    # returns, and it is still 99 afterwards.
    $global:LASTEXITCODE = 0

    try {
        # $actual is the exact 64-character lowercase hex SHA256 already
        # verified above. The doer persists it into installed.json's
        # zip_sha256 field, and every later repair (-Fix, -Reinstall) reads
        # it back from there - it has no one-liner in front of it any more to
        # hand it a fresh pin. Leaving this out silently strands every repair
        # behind a placeholder that can never validate. See
        # .superpowers/sdd/2026-08-10-whatsapp-one-click/pin-interface.md.
        & $setup -ZipPath $zip -ZipSha256 $actual
    } catch {
        Stop-Partway 'Something went wrong setting this up. Please tell Vimigo support.'
    }

    # A doer that ends on `exit 7` does not throw, so the catch above never
    # sees it. Without this the one-liner exits 0 having printed nothing at
    # all, and the owner walks away believing WhatsApp is connected when it is
    # not. Latent while the doer always exits 0, but that is a property of the
    # other file, not of this one.
    if ($LASTEXITCODE -ne 0) {
        Stop-Partway 'Something went wrong setting this up. Please tell Vimigo support.'
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
