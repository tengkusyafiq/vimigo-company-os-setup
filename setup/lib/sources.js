#!/usr/bin/env node
'use strict';
// Where this laptop's AI conversations and Second Brain live - what the sync
// job sends (lib/sync.js), and what WRAP-UP.md's catch-up reads.
//
//   node lib/sources.js list --since <ISO date>
//
// lists the Claude Code, Codex and Cowork conversation files on this computer
// changed since that moment, oldest first, as one line of JSON:
//   { ok, since, files: [{ kind, path, size, modified }], tooBig }
// Files over 50 MB are left out (and counted in `tooBig`) - the same rule the
// second-brain skill keeps for its own folder. Read-only: nothing is sent.
const fs = require('node:fs');
const path = require('node:path');
const { home, brain, claudeApp, localAppData } = require('./paths.js');

const SKIP_DIRS = new Set(['node_modules', '.git', '__pycache__', '.venv', 'venv', '.cache', '.next', '.turbo', '.Trash']);
const SKIP_FILE = [/^\.env(\..*)?$/i, /\.(pem|key|p12|pfx|kdbx)$/i, /^id_(rsa|ed25519|ecdsa)/i,
  /^cookies?(\.sqlite)?$/i, /^credentials.*\.json$/i, /^\.DS_Store$/, /^Thumbs\.db$/i, /\.tmp$/i];
const CONVERSATION = /\.(jsonl|json|md)$/i;

function sources(enrolledAtMs) {
  const h = home();
  const conv = (kind, root, prefix = '') => ({ kind, root, since: enrolledAtMs, only: CONVERSATION, prefix });
  const list = [
    { kind: 'brain', root: brain(), since: 0, prefix: '' },
    conv('claude', path.join(h, '.claude', 'projects')),
    conv('codex', path.join(h, '.codex', 'sessions')),
  ];
  // Every folder here comes through paths.js, so a fake home (tests) can never
  // read - and upload - the real Cowork sessions.
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

function walk(src, perFileMax, onTooBig) {
  const out = [];
  const visit = (dir, rel) => {
    let entries; try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const abs = path.join(dir, e.name); const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isSymbolicLink()) continue;
      // A conversation's `subagents/` folder holds the AI's own helper runs -
      // what each was asked and what it reported is already in the main
      // conversation, and they were ~70% of a heavy user's upload.
      if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name) && !(src.kind !== 'brain' && e.name === 'subagents')) visit(abs, r); continue; }
      if (!e.isFile() || SKIP_FILE.some((re) => re.test(e.name))) continue;
      if (src.only && !src.only.test(e.name)) continue;
      let st; try { st = fs.statSync(abs); } catch { continue; }
      if (st.mtimeMs < src.since) continue;
      if (st.size > perFileMax) { if (onTooBig) onTooBig(abs); continue; }
      out.push({ abs, key: `${src.kind}/${src.prefix}${r}`, size: st.size, mtimeMs: st.mtimeMs });
    }
  };
  visit(src.root, '');
  return out;
}
// What the sync job actually uploads: the Second Brain only - the notes and the
// class submission the owner is here to produce. Their raw AI conversations
// (Claude Code, Codex, Cowork) are deliberately NOT uploaded. They stay on the
// owner's own computer; WRAP-UP still reads them locally to write the submission,
// but the conversations themselves never leave the machine. Sending someone's
// private AI chats to a third party is the one thing an assistant will not do
// quietly, and it is not needed - the class only needs the work, not the chatter.
const uploadSources = (sinceMs) => sources(sinceMs).filter((s) => s.kind === 'brain');

const LIST_MAX = 50 * 1024 * 1024;
// The conversations (never the Second Brain itself) changed at or after
// `sinceMs`, oldest first.
function conversations(sinceMs, maxBytes = LIST_MAX) {
  let tooBig = 0;
  const files = sources(sinceMs)
    .filter((s) => s.kind !== 'brain')
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
  // Task 14 (H minor): an AI that copied `"opensAt": null` from session1.js
  // passes `--since null` (or an empty string). That is not a usage error: it
  // reads from this laptop's own enrolment - its event's opening - and with
  // no enrolment it lists nothing, rather than every conversation ever.
  const blank = raw !== undefined && (raw === '' || raw === 'null' || raw === 'undefined');
  let since = raw !== undefined && !blank ? Date.parse(raw) : NaN;
  if (blank) since = require('./identity.js').sinceMs(require('./identity.js').read());
  if (a[0] !== 'list' || raw === undefined || (!blank && !Number.isFinite(since))) {
    print({ ok: false, reason: 'usage: sources.js list --since <ISO date>' });
    process.exitCode = 2;
  } else if (!Number.isFinite(since)) {
    print({ ok: true, since: null, files: [], tooBig: 0 });
  } else {
    print({ ok: true, since: new Date(since).toISOString(), ...conversations(since) });
  }
}
module.exports = { sources, uploadSources, walk, conversations, LIST_MAX, SKIP_DIRS, SKIP_FILE };
