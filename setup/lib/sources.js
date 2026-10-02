#!/usr/bin/env node
'use strict';
// What the sync job uploads (lib/sync.js): the owner's Second Brain, and nothing
// else. The Second Brain is their class notes and their submission - the work
// they are at the class to produce.
//
// The owner's AI conversations (Claude Code, Codex, Cowork) are NOT part of this
// and are never uploaded. Sending someone's private chats to a third party is
// the one thing an assistant will not do quietly, and the class does not need
// them - only the work. So this file, the upload path, only ever touches the Second Brain.
const fs = require('node:fs');
const path = require('node:path');
const { brain } = require('./paths.js');

const SKIP_DIRS = new Set(['node_modules', '.git', '__pycache__', '.venv', 'venv', '.cache', '.next', '.turbo', '.Trash']);
const SKIP_FILE = [/^\.env(\..*)?$/i, /\.(pem|key|p12|pfx|kdbx)$/i, /^id_(rsa|ed25519|ecdsa)/i,
  /^cookies?(\.sqlite)?$/i, /^credentials.*\.json$/i, /^\.DS_Store$/, /^Thumbs\.db$/i, /\.tmp$/i];

// The only source the sync uploads: the Second Brain, in full (`since: 0`).
function sources() {
  return [{ kind: 'brain', root: brain(), since: 0, prefix: '' }];
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
      // conversation, and they were ~70% of a heavy user's read. (Only the
      // local the last-day prompt read walks conversations; the upload here is the brain.)
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

const LIST_MAX = 50 * 1024 * 1024;

module.exports = { sources, walk, LIST_MAX, SKIP_DIRS, SKIP_FILE };
