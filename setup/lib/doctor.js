#!/usr/bin/env node
'use strict';
// The second-brain skill runs this at the start of every session. It refreshes the
// skills and puts the Claude Code hooks back if something removed them. It sends
// nothing anywhere except the skill downloads.
const fs = require('node:fs');
const path = require('node:path');
const skills = require('./skills.js');
const { home, claudeApp } = require('./paths.js');

const has = (f, needle) => { try { return fs.readFileSync(f, 'utf8').includes(needle); } catch { return false; } };
function zo() {
  const h = home();
  const claudeDesktop = path.join(claudeApp(), 'claude_desktop_config.json');
  return {
    claude: has(claudeDesktop, 'zo.computer') || has(path.join(h, '.claude.json'), 'zo.computer'),
    codex: has(path.join(h, '.codex', 'config.toml'), 'zo.computer'),
  };
}
async function check({ skipSkills = false } = {}) {
  let s;
  if (skipSkills) s = { updated: [] };
  else { try { s = await skills.sync(); } catch { s = { updated: [], error: true }; } }
  let zoState; try { zoState = zo(); } catch { zoState = { claude: false, codex: false }; }
  // Put back the two Claude Code hooks if something removed them.
  try {
    const hooks = require('./hooks.js');
    if (fs.existsSync(require('./paths.js').brain()) && !hooks.status().installed) hooks.install();
  } catch { /* next time */ }
  return {
    ok: true,
    skills: { updated: s.updated, ...(s.offline ? { offline: true } : {}), ...(s.error ? { error: true } : {}) },
    zo: zoState,
  };
}
if (require.main === module) {
  check()
    .then((r) => process.stdout.write(JSON.stringify(r) + '\n'))
    .catch(() => process.stdout.write(JSON.stringify({ ok: false }) + '\n'));
}
module.exports = { check };
