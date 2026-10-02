#!/usr/bin/env node
'use strict';
// Does this laptop still need the local setup rows (Node/Git/Python, Second Brain)?
// Nothing here talks to Vimigo: there is no background sync, and nothing is shared
// except by the owner's own choice in the last-day prompt.
//
//   node lib/session1.js
const state = require('./state.js');

function status() {
  const s = state.read();
  const row = (id) => (s.rows || []).find((r) => r.id === id);
  const runtimesDone = row('runtimes')?.status === 'done';
  const secondBrainDone = row('second-brain')?.status === 'done';
  return { handoff: !runtimesDone || !secondBrainDone, runtimesDone, secondBrainDone, session1: !!s.session1 };
}

if (require.main === module) process.stdout.write(JSON.stringify(status()) + String.fromCharCode(10));
module.exports = { status };
