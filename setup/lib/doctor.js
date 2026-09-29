#!/usr/bin/env node
'use strict';
// The second-brain skill runs this at the start of every session. It never
// enrols anybody: a laptop that was not enrolled in session 1 stays that way.
const fs = require('node:fs');
const path = require('node:path');
const identity = require('./identity.js');
const skills = require('./skills.js');
const { ownEvent } = require('./event.js');
const { home, syncDir, claudeApp, schedulerOff } = require('./paths.js');
const STALE = 15 * 60_000;

const has = (f, needle) => { try { return fs.readFileSync(f, 'utf8').includes(needle); } catch { return false; } };
function zo() {
  const h = home();
  const claudeDesktop = path.join(claudeApp(), 'claude_desktop_config.json');
  return {
    claude: has(claudeDesktop, 'zo.computer') || has(path.join(h, '.claude.json'), 'zo.computer'),
    codex: has(path.join(h, '.codex', 'config.toml'), 'zo.computer'),
  };
}
async function syncHealth() {
  const id = identity.read();
  if (!id || !id.token) return 'not-enrolled';
  // Checked first: a decline made after enrolling still carries a token, and
  // `--stop` already removed the scheduler for it - reinstalling it here
  // would undo the one thing the owner asked for.
  if (id.declined) return 'declined';
  if (id.finished || id.closed) return 'finished';
  // Fix round 5 - the enrolment principle: repair for as long as THIS
  // laptop's own event is open, by that event's own answer (the hello the job
  // itself sends, lib/event.js ownEvent) - never stand down because another
  // event is the newest open one. A closed event's job is not ours to bring
  // back, and offline there is nothing a repair could send.
  const own = await ownEvent(id);
  if (own.state === 'offline') return 'offline';
  if (own.state === 'closed') return 'closed';
  if (schedulerOff()) return 'ok';
  const sched = require('./scheduler.js');
  const st = sched.status();
  if (!st.supported) return 'unsupported';
  if (!st.registered) { const r = sched.install(); if (r.ok) sched.kick(); return r.ok ? 'repaired' : 'unsupported'; }
  let last = 0; try { last = Date.parse(JSON.parse(fs.readFileSync(path.join(syncDir(), 'last-ok.json'), 'utf8')).at); } catch { /* never */ }
  if (!Number.isFinite(last) || Date.now() - last > STALE) { sched.kick(); return 'kicked'; }
  return 'ok';
}
async function check({ skipSkills = false } = {}) {
  let s;
  if (skipSkills) s = { updated: [] };
  else { try { s = await skills.sync(); } catch { s = { updated: [], error: true }; } }
  let sync; try { sync = await syncHealth(); } catch { sync = 'error'; }
  let zoState; try { zoState = zo(); } catch { zoState = { claude: false, codex: false }; }
  // Put back the two Claude Code hooks if something removed them.
  try {
    const hooks = require('./hooks.js');
    if (fs.existsSync(require('./paths.js').brain()) && !hooks.status().installed) hooks.install();
  } catch { /* next time */ }
  return {
    ok: true,
    skills: { updated: s.updated, ...(s.offline ? { offline: true } : {}), ...(s.error ? { error: true } : {}) },
    sync,
    zo: zoState,
  };
}
if (require.main === module) {
  check()
    .then((r) => process.stdout.write(JSON.stringify(r) + '\n'))
    .catch(() => process.stdout.write(JSON.stringify({ ok: false }) + '\n'));
}
module.exports = { check };
