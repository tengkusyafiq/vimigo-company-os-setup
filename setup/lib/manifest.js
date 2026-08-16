#!/usr/bin/env node
'use strict';
// Reads the manifest and returns one decision. Fails open, and fails quiet:
// event wifi drops, and an alarming message about a version check is the last
// thing a nervous owner needs to read.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// What this machine last downloaded. Read here rather than passed in, because
// the caller is an AI reading a markdown file, and every value it has to thread
// from one command into another is a value it can get wrong.
function installedVersion() {
  try {
    const p = path.join(
      process.env.VIMIGO_HOME || path.join(os.homedir(), '.vimigo'), 'state.json');
    const s = JSON.parse(fs.readFileSync(p, 'utf8'));
    return typeof s.version === 'string' && s.version ? s.version : null;
  } catch {
    return null;
  }
}

async function main() {
  const url = process.argv[2];
  const installed = installedVersion();
  const out = {
    action: 'proceed', version: null, installed, notice: '', offline: false, reason: '',
  };
  if (!url) { print(out); return; }

  let m;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(5000), cache: 'no-store' });
    if (!res.ok) throw new Error('status ' + res.status);
    m = await res.json();
  } catch {
    out.offline = true;
    print(out);
    return;
  }
  if (!m || typeof m !== 'object') { out.offline = true; print(out); return; }

  out.version = typeof m.version === 'string' ? m.version : null;
  out.notice = typeof m.notice === 'string' ? m.notice : '';

  if (m.halt === true) {
    out.action = 'halt';
    out.reason = 'halted';
  } else if (m.force_refetch === true) {
    out.action = 'refetch';
    out.reason = 'forced';
  } else if (installed && out.version && installed !== out.version) {
    // The ordinary case, and the reason this check exists at all. A machine set
    // up yesterday runs yesterday's instructions until something tells it not
    // to, and nobody is going to repaste a command they used once. Updating is
    // the default; force_refetch is only for pushing the same version again.
    out.action = 'refetch';
    out.reason = 'newer version published';
  }
  print(out);
}

function print(o) { process.stdout.write(JSON.stringify(o) + '\n'); }
main();
