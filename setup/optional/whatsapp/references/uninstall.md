# Clean slate: removing a previous installation

Run this in full before any install, repair, or migration, whether the previous
attempt finished, failed, or stopped halfway. Work top to bottom — the order is
what makes it hold.

**None of this is shown to the owner.** Every command, path and service name
below is yours to run and theirs never to see — see "Who you are talking to" in
SKILL.md. While this runs, they get one sentence: *"I'm clearing out the old
setup first."* Then work in silence until there is something on their phone to
do, or it is finished.

**Why the order:** a scheduled task, LaunchAgent, or service will restart the
bridge while you are deleting it. Kill the process first and it comes back
mid-delete, re-creating its store in a folder you have already emptied and
leaving a machine that is neither the old install nor the new one. Remove the
things that restart it, *then* the processes, *then* the files.

## Never remove these

- The copy of this skill you are currently reading from. It may be **replaced**
  in place — see "Replace the old skill" below — but never deleted and left
  absent mid-run, which removes the instructions being followed.
- Anything under `mcpServers` or `[mcp_servers.*]` that is not named
  `whatsapp`, `whatsapp-mcp`, or `whatsapp-mcp-go`. Other servers belong to the
  owner and must survive untouched.
- The dated archive folder created in "Remove the trees". Once that step
  finishes deleting, the archive is the only copy of the session left.

Never use a wildcard that could match more than the three known names. Never
delete a whole client config file to remove one entry — parse, remove the key,
serialize, and re-parse to confirm.

---

## Windows

### 1. Remove the restarters

```powershell
# Packaged-installer scheduled task
$task = Get-ScheduledTask -TaskName 'VimigoWhatsApp' -ErrorAction SilentlyContinue
if ($task) {
    Disable-ScheduledTask -TaskName 'VimigoWhatsApp' -ErrorAction SilentlyContinue | Out-Null
    Stop-ScheduledTask    -TaskName 'VimigoWhatsApp' -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'VimigoWhatsApp' -Confirm:$false
}

# Packaged-installer Startup shortcut
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'VimigoWhatsApp.lnk'
if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
```

Disable before Stop before Unregister. A task stopped but still registered is
re-triggered by its own repeat interval seconds later.

Older from-source installs used an NSSM service instead:

```powershell
if (Get-Service -Name 'WhatsAppBridge' -ErrorAction SilentlyContinue) {
    Stop-Service -Name 'WhatsAppBridge' -Force -ErrorAction SilentlyContinue
    # Service deletion requires elevation. Explain the UAC prompt before invoking it.
    Start-Process -Verb RunAs -Wait -FilePath 'sc.exe' -ArgumentList 'delete','WhatsAppBridge'
}
```

Deleting a service is the one step in this whole teardown that needs a UAC
prompt. If the service does not exist — the common case, since the packaged
installer used a scheduled task instead — nothing elevated runs at all.

When it is needed, warn the owner in plain words *before* the box appears, or a
blue permission dialog arrives unannounced and they cancel it:

> *"Windows will ask permission to remove the old background program. Please
> click Yes."*

Do not name the service, show the command, or mention administrator rights. This
needs no password.

### 2. Stop the processes

```powershell
Get-Process -Name 'whatsapp-bridge' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
@(Get-Process -Name 'whatsapp-bridge' -ErrorAction SilentlyContinue).Count   # expect 0
```

If the count is not 0, a restarter survived step 1. Go back — do not loop on
killing the process.

### 3. Free the ports

```powershell
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -eq 8080 -or ($_.LocalPort -ge 8765 -and $_.LocalPort -le 8865) } |
    Select-Object LocalPort, OwningProcess,
        @{n='Process';e={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }}
```

Expect no rows. 8080 is what this install will use; 8765–8865 is the band the
packaged installer chose from. A row owned by something that is not a WhatsApp
bridge is not yours to kill — pick it up in Preflight instead.

### 4. Remove the trees

Archive the session first, then delete:

```powershell
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$archive = Join-Path $env:USERPROFILE "whatsapp-archive-$stamp"
New-Item -ItemType Directory -Path $archive -Force | Out-Null

$root = Join-Path $env:LOCALAPPDATA 'Vimigo\whatsapp'
foreach ($sub in @('run\store','bin\store')) {
    $store = Join-Path $root $sub
    if (Test-Path -LiteralPath $store) {
        Copy-Item -LiteralPath $store -Destination (Join-Path $archive 'store') -Recurse -Force
        break
    }
}

foreach ($p in @(
    $root,
    (Join-Path $env:USERPROFILE 'Dev\whatsapp-mcp-go'),
    (Join-Path $env:USERPROFILE 'whatsapp-mcp-go'),
    (Join-Path $env:USERPROFILE 'Documents\whatsapp-mcp-go'),
    (Join-Path $env:USERPROFILE 'whatsapp-mcp'),
    'C:\Dev\whatsapp-mcp-go',
    'D:\Dev\whatsapp-mcp-go'
)) {
    if (Test-Path -LiteralPath $p) {
        $s = Join-Path $p 'whatsapp-bridge\store'
        if ((Test-Path -LiteralPath $s) -and -not (Test-Path -LiteralPath (Join-Path $archive 'store'))) {
            Copy-Item -LiteralPath $s -Destination (Join-Path $archive 'store') -Recurse -Force
        }
        Remove-Item -LiteralPath $p -Recurse -Force
    }
}
```

Report the archive path in the completion summary. Do not delete it.

---

## macOS

### 1. Remove the restarters

```bash
for label in com.vimigo.whatsapp com.user.whatsapp-bridge; do
    plist="$HOME/Library/LaunchAgents/$label.plist"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl disable "gui/$(id -u)/$label" 2>/dev/null || true
    [ -f "$plist" ] && rm -f "$plist"
done
launchctl list 2>/dev/null | grep -i whatsapp    # expect no output
```

`bootout` before removing the plist. Removing the plist first leaves the agent
loaded in memory until logout, still restarting the bridge.

### 2. Stop the processes

```bash
pkill -f 'whatsapp-bridge' 2>/dev/null || true
sleep 2
pgrep -fl 'whatsapp-bridge' || echo "none running"
```

### 3. Free the ports

```bash
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || $9 ~ /:(8080|87[6-9][0-9]|88[0-6][0-9])$/'
```

Expect the header only.

### 4. Remove the trees

```bash
stamp="$(date +%Y%m%d-%H%M%S)"
archive="$HOME/whatsapp-archive-$stamp"
mkdir -p "$archive"

root="$HOME/Library/Application Support/Vimigo/whatsapp"
for sub in run/store bin/store; do
    if [ -d "$root/$sub" ]; then
        cp -R "$root/$sub" "$archive/store"
        break
    fi
done

for p in "$root" \
         "$HOME/Dev/whatsapp-mcp-go" \
         "$HOME/whatsapp-mcp-go" \
         "$HOME/Documents/whatsapp-mcp-go" \
         "$HOME/whatsapp-mcp"; do
    [ -d "$p" ] || continue
    if [ -d "$p/whatsapp-bridge/store" ] && [ ! -d "$archive/store" ]; then
        cp -R "$p/whatsapp-bridge/store" "$archive/store"
    fi
    rm -rf "$p"
done
```

Quote every path. `Application Support` contains a space, and an unquoted
`rm -rf` on it deletes `~/Library/Application` instead.

---

## Linux

Same as macOS, with systemd in place of launchd:

```bash
systemctl --user stop whatsapp-bridge.service 2>/dev/null || true
systemctl --user disable whatsapp-bridge.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/whatsapp-bridge.service"
systemctl --user daemon-reload
systemctl --user reset-failed 2>/dev/null || true
```

Then steps 2–4 from macOS unchanged, minus the `Application Support` path.

---

## Every platform: remove the MCP registrations

Do this for **every** client present, not just the one in use. A dead
registration in Claude Desktop shows the owner a failed server, or a duplicate
set of WhatsApp tools whose calls go to a binary that no longer exists.

Remove all three names each time: `whatsapp`, `whatsapp-mcp`, `whatsapp-mcp-go`.

### Claude Code

```bash
for name in whatsapp whatsapp-mcp whatsapp-mcp-go; do
    claude mcp remove --scope user "$name" 2>/dev/null || true
done
claude mcp list      # expect no whatsapp entry
```

Also check project scope if the owner has one: `claude mcp list` shows the
scope of each entry.

### Claude Desktop

Config file:

- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`

Parse it, delete the three keys from `mcpServers` if present, serialize, and
parse the result again before moving on. Back up the file first. Leave every
other server in place.

On Windows, a Microsoft Store install of Claude Desktop keeps its config under
`%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\Claude\` instead.
Check both; register nothing to whichever one does not exist.

If a Claude Desktop MCPB extension named `whatsapp-mcp` is installed, remove it
through the Desktop extensions UI. A JSON entry and an MCPB extension for the
same server will both load.

### OpenAI Codex

```bash
for name in whatsapp whatsapp-mcp whatsapp-mcp-go; do
    codex mcp remove "$name" 2>/dev/null || true
done
codex mcp list
```

If the CLI is unavailable, edit `~/.codex/config.toml` by hand and drop the
`[mcp_servers.<name>]` table **and its sub-tables** — `[mcp_servers.whatsapp.env]`
is a separate table and is orphaned if you remove only the parent. Stop dropping
lines at the next header that is not a sub-table of the one you are removing.

The packaged installer also wrote a `fix-whatsapp` prompt that calls verbs this
install does not have. Remove it so it cannot be invoked against a bridge that
no longer answers to it:

```bash
rm -f "$HOME/.codex/prompts/fix-whatsapp.md"
```

### Restart the clients

A client holds its MCP registration in memory. Until Claude Desktop, Claude
Code, or Codex is restarted, removed servers still appear and still fail. Ask
for the restart at the end of the whole clean slate, once — not after each
client.

Ask for it in plain words, by the name the owner knows the app by: *"Please
close Claude completely and open it again."* Do not name the client's config,
its MCP list, or what is being reloaded.

Use the wording in "Telling them to restart the app" in SKILL.md — it covers the
two things that quietly waste a restart: closing a window is not quitting on a
Mac, and a restart of the app you are talking to them inside will end the
conversation unless you warn them first.

If the install is going to ask for a restart anyway a few minutes from now, it
is kinder to skip it here and ask once at the end, rather than twice.

---

## Replace the old skill

The packaged installer wrote its own `whatsapp-mcp-setup` skill into every
client it found. That older skill instructs an AI to repair WhatsApp by running
four verbs — `-Doctor`, `-Fix`, `-Reconnect`, `-Reinstall` — against
`vimigo-whatsapp.ps1` or `vimigo-whatsapp.sh`. **Step 4 deleted those scripts.**

Leaving a stale copy behind is worse than leaving a stale binary: the next time
the owner says WhatsApp is broken, an AI reads it, runs a verb whose script no
longer exists, gets a file-not-found, and reports the fault to the owner as a
support case. Nothing is actually wrong except the instructions.

Identify a stale copy by content, not by date — it names the four verbs above.
The current skill names none of them.

Known locations:

- `~/.claude/skills/whatsapp-mcp-setup/`
- `~/.codex/skills/whatsapp-mcp-setup/`
- `~/.agents/skills/whatsapp-mcp-setup/`
- macOS Claude Desktop: `~/Library/Application Support/Claude/skills/whatsapp-mcp-setup/`
- Windows Claude Desktop: `%APPDATA%\Claude\skills\whatsapp-mcp-setup\`

For each location that exists and holds a stale copy:

- **The copy you are reading from:** overwrite its files in place with the
  current version. Do not remove the directory first.
- **Every other copy:** remove the directory outright, or overwrite it with the
  current version if that client is also in use.

Also remove the packaged installer's companion prompt if present, for the same
reason — it calls the same deleted verbs:

```bash
rm -f "$HOME/.codex/prompts/fix-whatsapp.md"
```

End with exactly one version of this skill per client, and that version the
current one. Two clients disagreeing about how to fix WhatsApp is the failure
this prevents.

---

## Remove the injected AI rules block

The packaged installer also appends a block of WhatsApp rules to the owner's
global instruction files, on both Windows and macOS:

- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`

The block is fenced by exact marker lines:

```text
<!-- vimigo:whatsapp:start -->
...rules...
<!-- vimigo:whatsapp:end -->
```

These files are loaded into **every** session, not just WhatsApp ones. Left
behind, the block keeps teaching each new AI the old four-verb repair flow long
after the scripts are gone — the stale-skill problem again, in the one file that
is always read.

Remove the markers and everything between them. Change nothing else: the rest of
these files is the owner's own writing.

```bash
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
    [ -f "$f" ] || continue
    starts=$(grep -cF '<!-- vimigo:whatsapp:start -->' "$f")
    ends=$(grep -cF '<!-- vimigo:whatsapp:end -->' "$f")
    if [ "$starts" -eq 1 ] && [ "$ends" -eq 1 ]; then
        cp "$f" "$f.bak"
        awk '/<!-- vimigo:whatsapp:start -->/{d=1} !d{print} /<!-- vimigo:whatsapp:end -->/{d=0}' \
            "$f.bak" > "$f"
    fi
done
```

On Windows these are `$env:USERPROFILE\.claude\CLAUDE.md` and
`$env:USERPROFILE\.codex\AGENTS.md`; use the same one-pair-only test.

**If the counts are not exactly one start and one end, leave the file alone**
and say so in the completion summary. A file with mismatched or duplicated
markers usually means the owner quoted the marker in their own prose, and a
greedy delete there destroys their writing to remove a paragraph of ours.

---

## Verify before continuing

All of these must hold before Preflight:

| Check | Expected |
|---|---|
| `whatsapp-bridge` processes | none |
| Listener on 8080 | none |
| Listener on 8765–8865 | none |
| Scheduled task `VimigoWhatsApp` / LaunchAgent `com.vimigo.whatsapp` / service `WhatsAppBridge` | absent |
| `claude mcp list`, `codex mcp list`, Desktop `mcpServers` | no whatsapp entry under any of the three names |
| Install trees and repositories | absent |
| Copies of this skill | one per client, all the current version, none naming the four verbs |
| `~/.codex/prompts/fix-whatsapp.md` | absent |
| `vimigo:whatsapp` block in `CLAUDE.md` / `AGENTS.md` | gone, or reported as left alone for mismatched markers |
| Archive folder | exists, and contains the store if one was found |

If any row fails, fix that row before installing. An install onto a machine that
failed one of these will fail in a way that looks like a new bug and is not.
