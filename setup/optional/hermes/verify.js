#!/usr/bin/env node
'use strict';
// Is Hermes One installed? Nothing about keys - the row is done the moment the
// app is on the computer, and an owner who never adds a provider key has a
// finished setup, not a broken one.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const APP = 'Hermes One';
const home = process.env.VIMIGO_FAKE_HOME || os.homedir();

function out(o) {
  // Withdraw any earlier pass. This verifier itself once wrote a receipt saying
  // Hermes One was installed on a machine that had never had it - a leaking
  // PowerShell pipeline, fixed within the minute. The receipt outlived the bug.
  if (!o.ok) require('../../lib/receipt.js').clear('hermes');
  process.stdout.write(JSON.stringify(o) + '\n');
  process.exit(o.ok ? 0 : 1);
}

function pass(where) {
  const evidence = 'Hermes One is installed';
  require('../../lib/receipt.js').write('hermes', { ok: true, evidence });
  out({ ok: true, evidence, where });
}

// Seams, matching the Zo check's VIMIGO_ZO_VERIFY. Without them the Mac path
// ships never having run at all, and the Windows success path only runs on a
// machine that already has Hermes One - which is not the machine this gets
// written on, and is where the leaking-pipeline bug lived.
const platform = process.env.VIMIGO_FAKE_PLATFORM || process.platform;

if (platform === 'darwin') {
  for (const dir of [path.join(home, 'Applications'), '/Applications']) {
    const app = path.join(dir, APP + '.app');
    if (fs.existsSync(app)) pass(app);
  }
  out({ ok: false, evidence: 'Hermes One is not installed yet', where: '' });
}

if (platform !== 'win32') {
  out({ ok: false, evidence: 'Hermes One is not installed yet', where: '' });
}

// Windows records installed programs in two places - per-machine and per-user -
// and this installer writes to the user's own. Asking only the machine-wide one
// reports a perfectly good install as missing.
const KEYS = [
  'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
  'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
  'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
];

try {
  // One statement, one pipeline. Joining the three lookups with ';' made this
  // three statements, so only the last reached Where-Object and the first two
  // printed every installed program on the machine straight to stdout. The
  // result was 400kb of other people's software, a non-empty answer, and this
  // row reporting Hermes One installed on a computer that had never had it.
  const script = 'Get-ItemProperty -Path '
    + KEYS.map((k) => `'${k}'`).join(',')
    + ' -ErrorAction SilentlyContinue'
    + ` | Where-Object { $_.DisplayName -eq '${APP}' }`
    + ' | Select-Object -First 1 -ExpandProperty InstallLocation';
  // VIMIGO_FAKE_REGISTRY injects what Windows would have answered, so the
  // success path can be exercised on a machine that has never had this app -
  // which is the only kind of machine this gets written on, and is why the
  // leaking pipeline below shipped. Data, not a stand-in program: current Node
  // refuses to launch a .cmd, so a fake binary silently never runs.
  const where = (process.env.VIMIGO_FAKE_REGISTRY !== undefined
    ? process.env.VIMIGO_FAKE_REGISTRY
    : execFileSync('powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })).trim();
  // One install location, or nothing. Anything with a line break in it is not a
  // path - it is a pipeline that leaked, and trusting it marks the row on
  // whatever happened to be printed.
  if (where && !where.includes('\n') && where.length < 260) {
    const exe = path.join(where, 'hermes-agent.exe');
    pass(fs.existsSync(exe) ? exe : where);
  }
} catch { /* fall through to not installed */ }

out({ ok: false, evidence: 'Hermes One is not installed yet', where: '' });
