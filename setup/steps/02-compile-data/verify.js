#!/usr/bin/env node
'use strict';
// The same file installs into Claude and into Codex, and Codex needs a second
// copy under prompts/ so the owner can type /compile-data rather than hoping
// the model chooses it.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const home = process.env.VIMIGO_FAKE_HOME || os.homedir();
const targets = [
  { label: 'Claude',  file: path.join(home, '.claude', 'skills', 'compile-data', 'SKILL.md') },
  { label: 'ChatGPT', file: path.join(home, '.codex', 'skills', 'compile-data', 'SKILL.md') },
  { label: 'the /compile-data command', file: path.join(home, '.codex', 'prompts', 'compile-data.md') },
];

const missing = targets.filter((t) => !fs.existsSync(t.file)).map((t) => t.label);
const ok = missing.length === 0;
const evidence = ok
  ? 'installed for Claude and ChatGPT'
  : `not installed for ${missing.join(', ')}`;

// A passing check leaves a receipt. state.js will not mark this row done
// without one, which is what stops a row being marked by assertion.
if (ok) require('../../lib/receipt.js').write('compile-data', { ok, evidence });

process.stdout.write(JSON.stringify({ ok, evidence, missing }) + '\n');
process.exit(ok ? 0 : 1);
