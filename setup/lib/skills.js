#!/usr/bin/env node
'use strict';
// Keeps the participant's skills current: starter skills for everyone,
// optional ones once asked for, updates by content hash — into both apps.
const fs = require('node:fs');
const path = require('node:path');
const { home, vimigo, setupDir } = require('./paths.js');
const BASE = 'https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/';
const SAFE = /^skills\/[A-Za-z0-9][A-Za-z0-9._-]*(\/[A-Za-z0-9][A-Za-z0-9 ._-]*)+$/;

const dirs = (name) => [path.join(home(), '.claude', 'skills', name), path.join(home(), '.agents', 'skills', name)];
const recordFile = () => path.join(vimigo(), 'skills.json');
const record = () => { try { return JSON.parse(fs.readFileSync(recordFile(), 'utf8')); } catch { return { installed: {} }; } };
const save = (r) => { fs.mkdirSync(vimigo(), { recursive: true }); fs.writeFileSync(recordFile(), JSON.stringify(r, null, 2)); };

async function fetchText(rel, { base, local }) {
  if (local) return fs.readFileSync(path.join(local, rel), 'utf8');
  const res = await fetch((base || BASE) + rel.split('/').map(encodeURIComponent).join('/'), { cache: 'no-store', signal: AbortSignal.timeout(10000) });
  if (!res.ok) throw new Error('status ' + res.status);
  return res.text();
}
async function catalog(opts) {
  try { return JSON.parse(await fetchText('skills/catalog.json', opts)); }
  catch {
    if (opts.local) throw new Error('no catalog');
    return JSON.parse(await fetchText('skills/catalog.json', { local: setupDir() }));  // offline: the copy on disk
  }
}
function removeCodexDuplicate(name) {
  const d = path.join(home(), '.codex', 'skills', name);
  try {
    const text = fs.readFileSync(path.join(d, 'SKILL.md'), 'utf8').replace(/\r\n/g, '\n');
    // Match the frontmatter `name:` field exactly, not as a substring — a
    // skill named "web" must never match (and delete) an unrelated
    // "web-scraper" that merely starts with the same letters.
    let front = text;
    if (text.startsWith('---\n')) { const close = text.indexOf('\n---', 4); if (close !== -1) front = text.slice(4, close); }
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp(`^name:[ \\t]*${escaped}[ \\t]*$`, 'm');
    if (re.test(front)) fs.rmSync(d, { recursive: true, force: true });
  } catch { /* none */ }
}
async function put(skill, opts) {
  const bodies = [];
  for (const rel of skill.files) {
    if (!SAFE.test(rel) || !rel.startsWith(`skills/${skill.name}/`)) throw new Error('unsafe path');
    bodies.push([rel.slice(`skills/${skill.name}/`.length), await fetchText(rel, opts)]);
  }
  for (const d of dirs(skill.name)) {
    for (const [sub, body] of bodies) { const f = path.join(d, sub); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body); }
  }
  removeCodexDuplicate(skill.name);
}
const present = (name) => dirs(name).every((d) => fs.existsSync(path.join(d, 'SKILL.md')));

async function sync(opts = {}) {
  let cat; try { cat = await catalog(opts); } catch { return { ok: true, offline: true, updated: [] }; }
  const rec = record(); const updated = [];
  for (const s of cat.skills || []) {
    const want = s.tier === 'starter' || rec.installed[s.name];
    if (!want) continue;
    if (rec.installed[s.name] === s.hash && present(s.name)) { removeCodexDuplicate(s.name); continue; }
    try { await put(s, opts); rec.installed[s.name] = s.hash; updated.push(s.name); } catch { /* next time */ }
  }
  save(rec);
  return { ok: true, updated };
}
async function install(name, opts = {}) {
  let cat; try { cat = await catalog(opts); } catch { return { ok: false, reason: 'offline' }; }
  const s = (cat.skills || []).find((x) => x.name === name);
  if (!s) return { ok: false, reason: 'unknown' };
  await put(s, opts);
  const rec = record(); rec.installed[name] = s.hash; save(rec);
  return { ok: true };
}
async function list(opts = {}) {
  let cat; try { cat = await catalog(opts); } catch { return []; }
  const rec = record();
  return (cat.skills || []).map((s) => ({ name: s.name, description: s.description, tier: s.tier, installed: !!rec.installed[s.name] }));
}

if (require.main === module) {
  const [cmd, arg] = process.argv.slice(2);
  const local = process.argv.includes('--local') ? setupDir() : undefined;
  const run = cmd === 'sync' ? sync({ local }) : cmd === 'install' && arg ? install(arg, { local }) : cmd === 'list' ? list({ local }) : null;
  if (!run) { process.stderr.write('usage: skills.js sync|list|install <name> [--local]\n'); process.exit(2); }
  run.then((r) => process.stdout.write(JSON.stringify(r) + '\n'), () => { process.stdout.write('{"ok":false}\n'); process.exit(1); });
}
module.exports = { sync, install, list };
