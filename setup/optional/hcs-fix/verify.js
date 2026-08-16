#!/usr/bin/env node
'use strict';
// Answers which of the three faults this machine has, so the caller never has
// to guess between the repair that is safe and the one that left two laptops
// unbootable.
//
// All three services, running - not two of them, and not merely present.
// Claude names HNS, vmcompute and vfpext; a check that asked for two reported a
// machine as fixed while Claude went on showing the identical error. A check
// that asked only whether they existed did the same for a machine where they
// were installed and stopped, and then the repair said "nothing to do".
const { execFileSync } = require('node:child_process');

const SERVICES = ['vmcompute', 'hns', 'vfpext'];

// A seam for the decision logic, like VIMIGO_ZO_VERIFY in the Zo check.
//
// Four of the five answers this file can give need a machine in a state no
// developer's laptop is in, so without this they ship having never run - and
// the one branch a healthy laptop does reach is the one where nothing is wrong.
// The bug found in the Hermes check lived in its success path for exactly that
// reason.
//
// The injected value is what Windows would have said, not a fake program:
// execFileSync refuses to launch a .cmd at all on current Node, so a stand-in
// binary cannot be run, and a test written around one passes while never
// executing the code it claims to cover.
//
//   VIMIGO_FAKE_HCS={"firmware":true,"services":{"vmcompute":"Running",...}}
const FAKE = (() => {
  try {
    return process.env.VIMIGO_FAKE_HCS ? JSON.parse(process.env.VIMIGO_FAKE_HCS) : null;
  } catch {
    return null;
  }
})();

function ps(script) {
  return execFileSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', script],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}

function out(o) {
  // Withdraw any earlier pass, or a machine whose services stopped since it was
  // marked stays markable from the receipt taken when they were running.
  if (!o.ok) require('../../lib/receipt.js').clear('hcs-fix');
  process.stdout.write(JSON.stringify(o) + '\n');
  process.exit(o.ok ? 0 : 1);
}

const platform = process.env.VIMIGO_FAKE_PLATFORM || process.platform;

if (platform !== 'win32') {
  out({ ok: true, fix: 'none', evidence: 'not a Windows computer, so Cowork needs nothing here' });
}

// Firmware first. Everything else is pointless when this is off, and a machine
// that cannot answer counts as yes - this decides whether to offer a repair,
// and one that cannot say should not be refused one.
let firmware = true;
if (FAKE) {
  firmware = FAKE.firmware !== false;
} else {
  try {
    const answer = ps(
      '$c = Get-CimInstance Win32_Processor | Select-Object -First 1;'
      + ' if ($null -eq $c.VirtualizationFirmwareEnabled) { "unknown" }'
      + ' else { [string]$c.VirtualizationFirmwareEnabled }');
    if (/^false$/i.test(answer)) firmware = false;
  } catch { /* unknown counts as yes */ }
}

let states;
if (FAKE) {
  states = SERVICES.map((name) => ({ name, state: (FAKE.services || {})[name] || 'absent' }));
} else {
  try {
    states = SERVICES.map((name) => {
      const s = ps(`(Get-Service -Name '${name}' -ErrorAction SilentlyContinue).Status`);
      return { name, state: s || 'absent' };
    });
  } catch {
    out({ ok: false, fix: 'unknown', evidence: 'could not ask Windows about those services' });
  }
}

const running = states.filter((s) => /^Running$/i.test(s.state));
const absent = states.filter((s) => s.state === 'absent');

if (running.length === SERVICES.length) {
  const evidence = 'Cowork services all running';
  require('../../lib/receipt.js').write('hcs-fix', { ok: true, evidence });
  out({ ok: true, fix: 'none', evidence });
}

if (!firmware) {
  out({ ok: false, fix: 'firmware',
    evidence: 'this laptop has virtualization switched off in its firmware' });
}

// Absent means installing Windows features and restarting, which is the path
// that did not come back. Present-but-stopped is a service start: no restart,
// no boot change, undone by a restart if it goes wrong.
out(absent.length
  ? { ok: false, fix: 'features', evidence: 'those Windows features are not installed' }
  : { ok: false, fix: 'start', evidence: 'those services are installed but not running' });
