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
// There is no background sync any more: nothing is sent unless the owner shares on the
// last day, so there is nothing to repair here. An old two-minute job from day 1 removes
// itself the first time the server tells it the event is closed to it.
async function syncHealth() { return 'off'; }
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
