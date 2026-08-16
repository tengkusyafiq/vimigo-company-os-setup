#!/usr/bin/env node
'use strict';
// Asks Zo, rather than remembering what the owner said. The token is passed
// through and never echoed - not into stdout, not into an error.
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const token = process.argv[2];
const zoVerify = process.env.VIMIGO_ZO_VERIFY
  || path.join(__dirname, '..', '..', 'lib', 'zo-verify.js');

function fail(missing, evidence) {
  process.stdout.write(JSON.stringify({ ok: false, evidence, missing }) + '\n');
  process.exit(1);
}

if (!token) fail(['the key'], 'no key entered yet');

// Every Zo key starts with zo_sk_. What arrives instead is almost always their
// email, their password, or the workspace address - three things an owner who
// has never seen a key reasonably reaches for when asked for "the key".
// Naming the mistake here is the difference between "that did not work", which
// tells them nothing and sends them back to a page they cannot read, and being
// told what to look for. Checked before the network so a wrong paste answers at
// once and costs nobody a round trip.
if (!token.startsWith('zo_sk_')) {
  fail(['the key'], 'that is not a Zo key - a key starts with zo_sk_');
}

let answer;
try {
  const out = execFileSync(process.execPath, [zoVerify, token], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
  });
  answer = JSON.parse(out);
} catch {
  fail(['Zo'], 'could not reach Zo');
}

if (!answer || answer.ok !== true || !answer.workspaceUrl) {
  fail(['Zo'], 'the key did not work');
}

const evidence = 'connected to your Zo';
// A passing check leaves a receipt. state.js will not mark this row done
// without one, which is what stops a row being marked by assertion.
require('../../lib/receipt.js').write('zo', { ok: true, evidence });

process.stdout.write(JSON.stringify({ ok: true, evidence, missing: [] }) + '\n');
