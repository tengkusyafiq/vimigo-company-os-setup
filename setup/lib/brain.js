#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { home, brain } = require('./paths.js');
const hooks = require('./hooks.js');

const START = '<!-- second-brain:start -->';
const END = '<!-- second-brain:end -->';
const BLOCK = [
  START,
  '## Your Second Brain',
  '',
  'This person keeps a Second Brain: a folder called "Second Brain" in their home folder.',
  'Before your first reply in every conversation, use the `second-brain` skill — read their',
  '"About me" page and today\'s daily page, and run its start-up check. As you work, save what',
  'matters there, the way the skill describes, and after any reply where you did real work',
  'for them, add a line or two to today\'s page. Never write keys or passwords into it.',
  END,
].join('\n');

const today = () => new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD, local
function writeIfMissing(file, body) { if (!fs.existsSync(file)) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, body); } }

function init({ name, company, role }) {
  const root = brain();
  for (const d of ['Projects', 'Ideas', 'Decisions', 'Learnings', 'Daily']) fs.mkdirSync(path.join(root, d), { recursive: true });
  writeIfMissing(path.join(root, 'README.md'), [
    '# Second Brain', '',
    'Your AI keeps notes here as you work — your projects, ideas, decisions, and what you learn.',
    'It reads them back next time, so it remembers. They are ordinary files, and they are yours.', '',
  ].join('\n'));
  writeIfMissing(path.join(root, 'About me.md'), [
    '# About me', '', `- **Name:** ${name}`, `- **Company:** ${company}`, `- **Role:** ${role}`, '',
    '## What I want AI to help with', '', '', '## How I like to work', '', '',
  ].join('\n'));
  writeIfMissing(path.join(root, 'Daily', `${today()}.md`), `# ${today()}\n\n`);
  const instructions = mergeInstructions();
  // Claude Code: load the Second Brain into every chat, and nudge a line onto
  // today's page after real work - done by the app, not left to the AI.
  let claudeHooks; try { claudeHooks = hooks.install(); } catch { claudeHooks = { ok: false }; }
  return { ok: true, instructions, hooks: claudeHooks };
}

const targets = () => ({ claude: path.join(home(), '.claude', 'CLAUDE.md'), codex: path.join(home(), '.codex', 'AGENTS.md') });
function mergeInto(file) {
  let text = ''; try { text = fs.readFileSync(file, 'utf8'); } catch { /* new file */ }
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const block = BLOCK.replace(/\n/g, eol);
  // Anchor on the LAST end marker, then the start nearest to it. An orphan
  // start earlier in the file (no end of its own) is never a valid boundary,
  // so it is never mistaken for one on a later merge and its content is
  // never swallowed.
  const e = text.lastIndexOf(END);
  const s = e === -1 ? -1 : text.lastIndexOf(START, e);
  let next;
  if (s !== -1 && e > s) next = text.slice(0, s) + block + text.slice(e + END.length);
  else next = (text && !text.endsWith(eol) ? text + eol : text) + (text.trim() ? eol : '') + block + eol;
  if (next === text) return true;
  const tmp = file + '.tmp';
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    if (text && !fs.existsSync(file + '.before-second-brain')) fs.writeFileSync(file + '.before-second-brain', text);
    fs.writeFileSync(tmp, next);
    fs.renameSync(tmp, file);
    return true;
  } catch {
    // Locked, read-only, or permission-denied: leave the target exactly as
    // it was rather than aborting the whole init(), and never leave a
    // half-written .tmp file behind.
    try { fs.unlinkSync(tmp); } catch { /* nothing to clean up */ }
    return false;
  }
}
function mergeInstructions() { const t = targets(); return { claude: mergeInto(t.claude), codex: mergeInto(t.codex) }; }
function has(file) { try { const x = fs.readFileSync(file, 'utf8'); return x.includes(START) && x.includes(END); } catch { return false; } }
function status() {
  const t = targets();
  return { brain: fs.existsSync(brain()), aboutMe: fs.existsSync(path.join(brain(), 'About me.md')),
    instructions: { claude: has(t.claude), codex: has(t.codex) }, hooks: hooks.status() };
}

if (require.main === module) {
  const a = process.argv.slice(2);
  const f = (n) => { const i = a.indexOf(n); return i > -1 ? a[i + 1] : null; };
  let r;
  if (a[0] === 'init' && f('--name') && f('--company') && f('--role')) r = init({ name: f('--name'), company: f('--company'), role: f('--role') });
  else if (a[0] === 'status') r = status();
  else { process.stderr.write('usage: brain.js init --name N --company C --role R | status\n'); process.exit(2); }
  process.stdout.write(JSON.stringify(r) + '\n');
}
module.exports = { init, mergeInstructions, status, BLOCK, START, END };
