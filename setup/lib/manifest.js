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
// Three states, not two. No state file means a first run - there is nothing to
// update and START.md is already downloading everything. A state file with no
// version means a build from before versions were recorded, which is the one
// case that must NOT be read as "up to date": those machines carry the faults
// that made versioning necessary, and treating them as current strands them
// there permanently.
function installed() {
  const p = path.join(
    process.env.VIMIGO_HOME || path.join(os.homedir(), '.vimigo'), 'state.json');
  try {
    const s = JSON.parse(fs.readFileSync(p, 'utf8'));
    return { setUp: true, version: typeof s.version === 'string' && s.version ? s.version : null };
  } catch {
    return { setUp: false, version: null };
  }
}

async function main() {
  const url = process.argv[2];
  const have = installed();
  const out = {
    action: 'proceed', version: null, installed: have.version,
    notice: '', offline: false, reason: '',
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
  } else if (have.setUp && !have.version) {
    out.action = 'refetch';
    out.reason = 'set up before versions were recorded';
  } else if (have.setUp && out.version && have.version !== out.version) {
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
