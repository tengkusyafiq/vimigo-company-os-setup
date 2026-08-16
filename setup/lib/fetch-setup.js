#!/usr/bin/env node
'use strict';
// Downloads the whole setup tree over itself.
//
// This exists because the alternative was a paragraph of prose asking an AI to
// write its own downloader, and a real run produced two failures from one
// paragraph: `curl` was intercepted by a plugin on that machine, and the
// hand-written Node fallback assumed files.json was an array and crashed on
// line 6. Neither is the AI being careless - the prose never said the shape,
// and never said which tool to reach for.
//
// A machine that is updating already has Node and already has this folder, so
// the update path has no reason to improvise anything. START.md still fetches
// by hand on a first run, because on a first run none of this is here yet.
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');   // <home>/.vimigo/setup

function die(msg) {
  process.stdout.write(JSON.stringify({ ok: false, error: msg }) + '\n');
  process.exit(1);
}

// Accepts both shapes. The published tree uses {"files": [...]}, but a machine
// running an older copy may meet either, and a downloader that refuses the tree
// it is meant to replace can never replace it.
function listOf(doc) {
  if (Array.isArray(doc)) return doc;
  if (doc && Array.isArray(doc.files)) return doc.files;
  return null;
}

// Every path comes off the network, and this writes to disk.
//
// Two layers, because the containment check alone is a rule about where a file
// may land and says nothing about what it may be called. Attacked with fourteen
// traversal payloads, containment refused twelve and contained the other two -
// '~/evil.txt' and a percent-encoded '../..' - as literal filenames inside the
// setup folder. Neither escaped, but neither is a file this setup has any
// business creating, and the list they would arrive in comes over the network.
//
// The allowlist is what the published tree already looks like: all 39 real
// paths pass it unchanged.
const SEGMENT = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

function safe(rel) {
  if (typeof rel !== 'string' || !rel) return null;
  if (path.isAbsolute(rel) || /^[A-Za-z]:/.test(rel)) return null;

  const parts = rel.split('/');
  if (!parts.every((s) => s !== '..' && SEGMENT.test(s))) return null;

  // Kept as well as, not instead of. An allowlist is only as good as the
  // characters somebody thought of; this one answers the actual question.
  const full = path.resolve(ROOT, rel);
  const inside = path.relative(ROOT, full);
  if (inside.startsWith('..') || path.isAbsolute(inside)) return null;
  return full;
}

async function get(url) {
  const res = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(30000) });
  if (!res.ok) throw new Error('status ' + res.status);
  return res.text();
}

async function main() {
  let base = process.argv[2];
  if (!base) die('no address given');
  if (!base.endsWith('/')) base += '/';

  // An optional part names its own list, and every path inside is still
  // relative to the setup root - so optional/hcs-fix/files.json holds
  // "optional/hcs-fix/README.md", not "README.md". A list of bare names would
  // land those files on top of the main tree's README.
  const listPath = process.argv[3] || 'files.json';
  if (!safe(listPath)) die('that file list is not inside the setup');

  let list;
  try {
    list = listOf(JSON.parse(await get(base + listPath)));
  } catch (e) {
    die('could not read the file list (' + e.message + ')');
  }
  if (!list || !list.length) die('the file list was empty');

  const failed = [];
  let wrote = 0;
  for (const rel of list) {
    const full = safe(rel);
    if (!full) { failed.push(String(rel)); continue; }
    try {
      const body = await get(base + rel.split('/').map(encodeURIComponent).join('/'));
      fs.mkdirSync(path.dirname(full), { recursive: true });
      fs.writeFileSync(full, body);
      wrote++;
    } catch {
      failed.push(rel);
    }
  }

  // A partial tree is the dangerous outcome: half the instructions new, half
  // old, and nothing on screen saying so. Report it rather than letting the
  // caller read a count and assume.
  const ok = failed.length === 0;
  process.stdout.write(JSON.stringify({ ok, wrote, failed }) + '\n');
  process.exit(ok ? 0 : 1);
}

main();
