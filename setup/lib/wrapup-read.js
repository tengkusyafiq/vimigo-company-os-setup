#!/usr/bin/env node
'use strict';
// Reads the owner's AI conversations on THIS computer so WRAP-UP.md can write
// their submission from what they actually did this week.
//
//   node lib/wrapup-read.js list --since <ISO date>
//
// lists the Claude Code, Codex and Cowork conversation files changed since that
// moment, oldest first, as one line of JSON:
//   { ok, since, files: [{ kind, path, size, modified }], tooBig }
//
// READ-ONLY, AND LOCAL. Nothing here is uploaded. The sync job (lib/sync.js and
// lib/sources.js) sends only the Second Brain; the owner's conversations never
// leave this machine. This file only helps WRAP-UP read them in place to write
// the submission. Files over 50 MB are left out and counted in `tooBig`.
const fs = require('node:fs');
const path = require('node:path');
const { home, claudeApp, localAppData } = require('./paths.js');
const { walk, LIST_MAX } = require('./sources.js');

const CONVERSATION = /\.(jsonl|json|md)$/i;

// The conversation folders on this computer, read only, never uploaded.
function convSources(sinceMs) {
  const h = home();
  const conv = (kind, root, prefix = '') => ({ kind, root, since: sinceMs, only: CONVERSATION, prefix });
  const list = [
    conv('claude', path.join(h, '.claude', 'projects')),
    conv('codex', path.join(h, '.codex', 'sessions')),
  ];
  // Every folder here comes through paths.js, so a fake home (tests) can never
  // read the real Cowork sessions.
  const cowork = [];
  if (process.platform === 'win32') {
    const local = localAppData();
    cowork.push(path.join(claudeApp(), 'local-agent-mode-sessions'));
    try {
      for (const d of fs.readdirSync(path.join(local, 'Packages'))) {
        if (/^Claude_/.test(d)) cowork.push(path.join(local, 'Packages', d, 'LocalCache', 'Roaming', 'Claude', 'local-agent-mode-sessions'));
      }
    } catch { /* no Store install */ }
  } else if (process.platform === 'darwin') {
    cowork.push(path.join(claudeApp(), 'local-agent-mode-sessions'));
  }
  cowork.forEach((root, i) => list.push(conv('cowork', root, i ? `store${i}/` : '')));
  return list;
}

// The conversations changed at or after `sinceMs`, oldest first. Read-only.
function conversations(sinceMs, maxBytes = LIST_MAX) {
  let tooBig = 0;
  const files = convSources(sinceMs)
    .flatMap((s) => walk(s, maxBytes, () => { tooBig++; }).map((f) => ({ kind: s.kind, path: f.abs, size: f.size, mtimeMs: f.mtimeMs })))
    .sort((a, b) => a.mtimeMs - b.mtimeMs)
    .map(({ mtimeMs, ...f }) => ({ ...f, modified: new Date(mtimeMs).toISOString() }));
  return { files, tooBig };
}

if (require.main === module) {
  const a = process.argv.slice(2);
  const i = a.indexOf('--since');
  const raw = i > -1 ? a[i + 1] : undefined;
  const print = (o) => process.stdout.write(`${JSON.stringify(o)}\n`);
  // An AI that copied `"opensAt": null` passes `--since null` (or an empty
  // string). That is not a usage error: it reads from this laptop's own
  // enrolment - its event's opening - and with no enrolment lists nothing,
  // rather than every conversation ever.
  const blank = raw !== undefined && (raw === '' || raw === 'null' || raw === 'undefined');
  let since = raw !== undefined && !blank ? Date.parse(raw) : NaN;
  if (blank) since = require('./identity.js').sinceMs(require('./identity.js').read());
  if (a[0] !== 'list' || raw === undefined || (!blank && !Number.isFinite(since))) {
    print({ ok: false, reason: 'usage: wrapup-read.js list --since <ISO date>' });
    process.exitCode = 2;
  } else if (!Number.isFinite(since)) {
    print({ ok: true, since: null, files: [], tooBig: 0 });
  } else {
    print({ ok: true, since: new Date(since).toISOString(), ...conversations(since) });
  }
}
module.exports = { convSources, conversations };
