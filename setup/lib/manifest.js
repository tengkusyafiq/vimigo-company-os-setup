#!/usr/bin/env node
'use strict';
// Reads the manifest and returns one decision. Fails open, and fails quiet:
// event wifi drops, and an alarming message about a version check is the last
// thing a nervous owner needs to read.
async function main() {
  const url = process.argv[2];
  const out = { action: 'proceed', version: null, notice: '', offline: false };
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
  if (m.halt === true) out.action = 'halt';
  else if (m.force_refetch === true) out.action = 'refetch';
  print(out);
}
function print(o) { process.stdout.write(JSON.stringify(o) + '\n'); }
main();
