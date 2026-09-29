#!/usr/bin/env node
'use strict';
// Registers the sync with the computer's own scheduler. No admin, ever.
//
// Windows: the shape the WhatsApp installer proved on real Windows 11 —
// a -Once trigger repeating forever (an AtLogOn trigger needs an ELEVATED
// caller to register, so it is not usable), wscript.exe //B running a .vbs
// that runs a .cmd hidden and waits (WSH cannot wait on cmd.exe itself), and
// paths derived from the shim's own folder so a non-Latin profile name never
// lands in an ASCII file.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { home, syncDir, setupDir, schedulerOff } = require('./paths.js');

const TASK = 'Second Brain Sync';
const LABEL = 'com.vimigo.second-brain-sync';

function windowsCmd(nodePath) {
  const node = /^[\x20-\x7e]+$/.test(nodePath) && !/["%]/.test(nodePath) ? `"${nodePath}"` : 'node';
  return ['@echo off', `${node} "%~dp0..\\setup\\lib\\sync.js" --quiet >> "%~dp0sync.log" 2>&1`, ''].join('\r\n');
}
function windowsVbs() {
  return [
    "' Runs the Second Brain sync with no window. See scheduler.js.",
    'Set shell = CreateObject("WScript.Shell")',
    'Set fso = CreateObject("Scripting.FileSystemObject")',
    'here = fso.GetParentFolderName(WScript.ScriptFullName)',
    'q = Chr(34)',
    'shell.Run q & here & "\\run-hidden.cmd" & q, 0, True', '',
  ].join('\r\n');
}
function windowsRegisterPs() {
  return [
    "$ErrorActionPreference = 'Stop'",
    "$shim = Join-Path $env:USERPROFILE '.vimigo\\sync\\run-hidden.vbs'",
    "$action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\\wscript.exe') -Argument ('//B //Nologo \"{0}\"' -f $shim)",
    '$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2)',
    '$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable',
    '$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value',
    '$principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited',
    '$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal',
    `Register-ScheduledTask -TaskName '${TASK}' -InputObject $task -Force | Out-Null`,
  ].join('\n');
}
function ps(script) {
  const r = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], { encoding: 'utf8', windowsHide: true, timeout: 60000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
function macPlist({ nodePath, syncPath, logPath }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>${xml(nodePath)}</string><string>${xml(syncPath)}</string><string>--quiet</string></array>
  <key>StartInterval</key>
  <integer>120</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>${xml(logPath)}</string>
  <key>StandardErrorPath</key><string>${xml(logPath)}</string>
</dict></plist>
`;
}
// A stable path, not process.execPath: Homebrew's real path moves on every upgrade.
function macNode() {
  for (const p of ['/opt/homebrew/bin/node', '/usr/local/bin/node']) if (fs.existsSync(p)) return p;
  return process.execPath;
}
const plistPath = () => path.join(home(), 'Library', 'LaunchAgents', `${LABEL}.plist`);
const uid = () => (process.getuid ? process.getuid() : 0);
const lc = (...args) => spawnSync('launchctl', args, { encoding: 'utf8', timeout: 30000 });

function install() {
  fs.mkdirSync(syncDir(), { recursive: true });
  if (process.platform === 'win32') {
    fs.writeFileSync(path.join(syncDir(), 'run-hidden.cmd'), windowsCmd(process.execPath), 'ascii');
    fs.writeFileSync(path.join(syncDir(), 'run-hidden.vbs'), windowsVbs(), 'ascii');
    const r = ps(windowsRegisterPs());
    return r.ok ? { ok: true } : { ok: false, reason: 'register-failed', detail: r.err.slice(0, 300) };
  }
  if (process.platform === 'darwin') {
    fs.mkdirSync(path.dirname(plistPath()), { recursive: true });
    fs.writeFileSync(plistPath(), macPlist({ nodePath: macNode(),
      syncPath: path.join(setupDir(), 'lib', 'sync.js'), logPath: path.join(syncDir(), 'sync.log') }));
    lc('bootout', `gui/${uid()}/${LABEL}`);
    let r = lc('bootstrap', `gui/${uid()}`, plistPath());
    if (r.status !== 0) r = lc('load', '-w', plistPath());
    return r.status === 0 ? { ok: true } : { ok: false, reason: 'register-failed', detail: (r.stderr || '').slice(0, 300) };
  }
  return { ok: false, reason: 'unsupported' };
}
function status() {
  if (process.platform === 'win32') {
    const r = ps(`$t = Get-ScheduledTask -TaskName '${TASK}' -ErrorAction SilentlyContinue; if ($t -and $t.State -ne 'Disabled') { 'yes' } else { 'no' }`);
    return { supported: true, registered: r.out === 'yes' };
  }
  if (process.platform === 'darwin') return { supported: true, registered: lc('print', `gui/${uid()}/${LABEL}`).status === 0 };
  return { supported: false, registered: false };
}
function kick() {
  if (process.platform === 'win32') return { ok: ps(`Start-ScheduledTask -TaskName '${TASK}'`).ok };
  if (process.platform === 'darwin') return { ok: lc('kickstart', `gui/${uid()}/${LABEL}`).status === 0 };
  return { ok: false };
}
function remove() {
  if (process.platform === 'win32') {
    ps(`Unregister-ScheduledTask -TaskName '${TASK}' -Confirm:$false -ErrorAction SilentlyContinue`);
    for (const f of ['run-hidden.cmd', 'run-hidden.vbs']) { try { fs.unlinkSync(path.join(syncDir(), f)); } catch { /* gone */ } }
  } else if (process.platform === 'darwin') {
    lc('bootout', `gui/${uid()}/${LABEL}`);
    try { fs.unlinkSync(plistPath()); } catch { /* gone */ }
  }
  return { ok: true };
}

// A fake home (VIMIGO_FAKE_HOME, unless VIMIGO_TEST_REAL_SCHEDULER opts in) or
// VIMIGO_NO_SCHEDULER: every call is a no-op that says so, and never reaches
// the computer's real Task Scheduler or launchd - the task it would touch is
// the owner's real one, whatever home the rest of this run is pointed at.
// `status` answers "registered" so a caller that did not check schedulerOff()
// itself treats the job as present rather than trying to repair it.
function guarded(fn, off) {
  return (...args) => (schedulerOff() ? { ...off, off: true } : fn(...args));
}
const api = {
  install: guarded(install, { ok: true }),
  remove: guarded(remove, { ok: true }),
  status: guarded(status, { supported: true, registered: true }),
  kick: guarded(kick, { ok: true }),
};

if (require.main === module) {
  const cmd = process.argv[2];
  const fn = api[cmd];
  if (!fn) { process.stderr.write('usage: scheduler.js install|remove|status|kick\n'); process.exit(2); }
  const r = fn();
  process.stdout.write(JSON.stringify(r) + '\n');
  process.exit(r.ok === false ? 1 : 0);
}
module.exports = { ...api, windowsCmd, windowsVbs, windowsRegisterPs, macPlist, macNode, TASK, LABEL };
