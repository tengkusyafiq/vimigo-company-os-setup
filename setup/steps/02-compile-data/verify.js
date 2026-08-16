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

// Existence is not installation. Three empty files passed this check happily -
// the row went green, the receipt was written, and the owner would have found
// out at the end of the event, typing the one command the whole row exists for.
// A half-written copy is the realistic shape: a previous run interrupted by a
// restart, or a download that ended early.
const MARKER = 'name: compile-data';   // the skill's own identity, in its frontmatter
const FLOOR = 1000;                    // the real file is ~13k; this only catches truncation

function installed(file) {
  let body;
  try {
    body = fs.readFileSync(file, 'utf8');
  } catch {
    return false;
  }
  return body.length >= FLOOR && body.includes(MARKER);
}

const missing = targets.filter((t) => !installed(t.file)).map((t) => t.label);
const ok = missing.length === 0;
const evidence = ok
  ? 'installed for Claude and ChatGPT'
  : `not installed for ${missing.join(', ')}`;

// A passing check leaves a receipt. state.js will not mark this row done
// without one, which is what stops a row being marked by assertion.
// A failing check withdraws any earlier passing one, or a row that broke since
// it was marked stays markable from the stale receipt.
if (ok) require('../../lib/receipt.js').write('compile-data', { ok, evidence });
else require('../../lib/receipt.js').clear('compile-data');

process.stdout.write(JSON.stringify({ ok, evidence, missing }) + '\n');
process.exit(ok ? 0 : 1);
