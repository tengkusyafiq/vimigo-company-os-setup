#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { home } = require('../../lib/paths.js');
const brain = require('../../lib/brain.js');
const receipt = require('../../lib/receipt.js');
const MARK = 'name: second-brain'; const FLOOR = 500;
const skill = (dir) => { try { const b = fs.readFileSync(path.join(dir, 'second-brain', 'SKILL.md'), 'utf8'); return b.length >= FLOOR && b.includes(MARK); } catch { return false; } };
const st = brain.status();
const missing = [];
if (!st.brain || !st.aboutMe) missing.push('the folder');
if (!skill(path.join(home(), '.claude', 'skills'))) missing.push('Claude');
if (!skill(path.join(home(), '.agents', 'skills'))) missing.push('ChatGPT');
if (fs.existsSync(path.join(home(), '.codex', 'skills', 'second-brain'))) missing.push('a duplicate to remove');
if (!st.instructions.claude || !st.instructions.codex) missing.push('the standing instruction');
// A settings file that isn't valid JSON is never rewritten (it may hold the
// person's own settings), so it cannot hold this row back either.
if (!st.hooks.installed && !st.hooks.invalid) missing.push('the automatic start in Claude Code');
const ok = missing.length === 0;
const evidence = ok ? 'ready for Claude and ChatGPT' : `not finished - ${missing.join(', ')}`;
if (ok) receipt.write('second-brain', { ok, evidence }); else receipt.clear('second-brain');
process.stdout.write(JSON.stringify({ ok, evidence, missing }) + '\n');
process.exit(ok ? 0 : 1);
