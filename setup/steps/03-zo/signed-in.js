#!/usr/bin/env node
'use strict';
// Does this computer have an account in at least one of the apps the Zo key was
// written into?
//
// Only one of Claude or ChatGPT is needed, so any single signal is a pass.
//
// Three answers, not two. Claude Desktop keeps its signed-in state in an
// Electron cookie store, and this setup does not read anybody's credential
// storage - so an owner who uses only Claude Desktop is fully set up and
// produces no signal at all. Reporting that as failed would be the same
// confident wrongness as the check that found Hermes One on a machine that
// never had it. It reports "unknown" and the AI asks, which is something the
// owner can answer by looking.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const home = process.env.VIMIGO_FAKE_HOME || os.homedir();

function out(o) {
  process.stdout.write(JSON.stringify(o) + '\n');
  process.exit(o.ok ? 0 : 1);
}

// Existence of a named key, never its value. Nothing here reads an email
// address, a token or an account id, and nothing here prints one.
function claudeCode() {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(home, '.claude.json'), 'utf8'));
    const a = j && j.oauthAccount;
    return !!(a && typeof a === 'object' && Object.keys(a).length > 0);
  } catch {
    return false;
  }
}

function codex() {
  try {
    // Present and not empty. A zero-byte auth.json is what an interrupted
    // sign-in leaves behind, and it means the opposite of signed in.
    return fs.statSync(path.join(home, '.codex', 'auth.json')).size > 2;
  } catch {
    return false;
  }
}

const found = [];
if (claudeCode()) found.push('Claude');
if (codex()) found.push('ChatGPT');

if (found.length) {
  // "An account is set up", not "signed in and working" - a stored account
  // does not prove the session is still valid, the same way an installed
  // service does not prove a running one.
  const evidence = `an account is set up in ${found.join(' and ')}`;
  require('../../lib/receipt.js').write('signed-in', { ok: true, evidence });
  out({ ok: true, state: 'found', apps: found, evidence });
}

require('../../lib/receipt.js').clear('signed-in');
out({
  ok: false,
  state: 'unknown',
  apps: [],
  evidence: 'could not tell from this computer - ask them',
});
