#!/usr/bin/env node
'use strict';
// Claude Code hooks that keep the Second Brain in use without relying on the
// AI remembering to. The app itself runs them, whatever the AI decides:
//
//   node lib/hooks.js session-start   as each chat starts: prints the person's
//                                     "About me" and today's page, which the
//                                     app puts in front of the AI
//   node lib/hooks.js stop            when the AI finishes a reply: after real
//                                     work with no line on today's page, it
//                                     sends the AI back once to add one
//   node lib/hooks.js install|remove|status
//                                     the two entries in ~/.claude/settings.json
//
// Codex has no hooks; there the standing instruction in ~/.codex/AGENTS.md is
// all there is. Every hook path exits 0 and never throws: a broken hook must
// never get in the way of the person's chat.
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { home, brain, setupDir } = require('./paths.js');

const today = () => new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD, local
const dailyFile = () => path.join(brain(), 'Daily', `${today()}.md`);
const settingsFile = () => path.join(home(), '.claude', 'settings.json');
const read = (f) => { try { return fs.readFileSync(f, 'utf8'); } catch { return null; } };
const clip = (s, n) => (s.length > n ? `${s.slice(0, n)}\n…` : s);
// Ours, whatever home or node path it was installed with.
const OURS = /[\\/]\.vimigo[\\/]setup[\\/]lib[\\/]hooks\.js/;

// ---- the hooks ----

function sessionStart() {
  const root = brain();
  if (!fs.existsSync(root)) return '';
  let daily = read(dailyFile());
  if (daily === null) {
    daily = `# ${today()}\n\n`;
    try { fs.mkdirSync(path.dirname(dailyFile()), { recursive: true }); fs.writeFileSync(dailyFile(), daily); } catch { /* read-only: still load the rest */ }
  }
  const about = read(path.join(root, 'About me.md')) || '(no About me page yet)';
  // The start-up check (skill updates, keeping the saving job healthy) runs
  // in the background, so the chat never waits for it. Never under a test's
  // fake home: it would reach the network.
  if (!process.env.VIMIGO_FAKE_HOME) {
    try {
      const doctor = path.join(setupDir(), 'lib', 'doctor.js');
      if (fs.existsSync(doctor)) spawn(process.execPath, [doctor], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    } catch { /* next chat */ }
  }
  return [
    `Their Second Brain (the folder "${root}"), loaded for you at the start of this conversation.`,
    '',
    '--- About me.md ---',
    clip(about.trim(), 4000),
    '',
    `--- Daily/${today()}.md (today's page) ---`,
    clip(daily.trim(), 4000),
    '',
    'Use the `second-brain` skill as you work: save ideas, decisions, projects and learnings the way it describes, '
      + 'and after any reply where you did real work for them, add one or two lines to today\'s page. '
      + 'Never write keys or passwords there. Do not announce each save.',
  ].join('\n');
}

// The last ~2 MB is plenty to find the current turn; a transcript can be 30 MB.
function readTail(file, bytes = 2 * 1024 * 1024) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
    const size = fs.fstatSync(fd).size;
    const start = Math.max(0, size - bytes);
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const text = buf.toString('utf8');
    return start ? text.slice(text.indexOf('\n') + 1) : text;
  } catch { return ''; } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch { /* closed */ } }
}
const isPersonTurn = (m) => {
  if (!m || m.type !== 'user' || !m.message || m.isMeta || m.toolUseResult) return false;
  const c = m.message.content;
  const text = typeof c === 'string' ? c : Array.isArray(c) && !c.some((x) => x && x.type === 'tool_result')
    ? c.filter((x) => x && x.type === 'text').map((x) => x.text).join(' ') : '';
  return !!text.trim() && !/^(Base directory for this skill|<command-|Caveat:)/.test(text.trim());
};
// Tools that are bookkeeping, not work done for the person.
const NOT_WORK = new Set(['ToolSearch', 'TodoWrite', 'Skill', 'AskUserQuestion', 'ExitPlanMode', 'EnterPlanMode']);

function stop(input) {
  if (!input || input.stop_hook_active || !input.transcript_path) return null;
  if (!fs.existsSync(brain())) return null;
  const entries = readTail(input.transcript_path).split('\n').filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
  let last = -1;
  entries.forEach((m, i) => { if (isPersonTurn(m)) last = i; });
  if (last === -1) return null;
  const turnStart = Date.parse(entries[last].timestamp);
  const tools = entries.slice(last + 1).filter((m) => m.type === 'assistant' && m.message && Array.isArray(m.message.content))
    .flatMap((m) => m.message.content.filter((c) => c && c.type === 'tool_use'));
  const touches = (t, re) => re.test(JSON.stringify(t.input || {}));
  const work = tools.filter((t) => !NOT_WORK.has(t.name) && !touches(t, /Second Brain|\.vimigo/));
  if (!work.length) return null;                                   // small talk, or only their notes
  if (tools.some((t) => touches(t, /Second Brain/) && touches(t, /Daily/))) return null;
  let m = 0; try { m = fs.statSync(dailyFile()).mtimeMs; } catch { /* no page yet */ }
  if (Number.isFinite(turnStart) && m >= turnStart - 1000) return null; // already logged this turn
  return {
    decision: 'block',
    reason: `Before you finish: add one or two lines to today's page in their Second Brain (${dailyFile()}) — `
      + 'what they asked and what came out of it — as the second-brain skill describes. '
      + 'Then finish your reply. No need to mention the note to them.',
  };
}

// ---- install / remove / status ----

const command = (sub) => `node "${path.join(setupDir(), 'lib', 'hooks.js').replace(/\\/g, '/')}" ${sub}`;
const WANT = { SessionStart: 'session-start', Stop: 'stop' };

function load() {
  const raw = read(settingsFile());
  if (raw === null || !raw.trim()) return { raw: '', s: {} };
  try {
    const s = JSON.parse(raw);
    return s && typeof s === 'object' && !Array.isArray(s) ? { raw, s } : { invalid: true };
  } catch { return { invalid: true }; }
}
const strip = (groups) => (Array.isArray(groups) ? groups : [])
  .map((g) => (g && Array.isArray(g.hooks) ? { ...g, hooks: g.hooks.filter((h) => !(h && OURS.test(String(h.command || '')))) } : g))
  .filter((g) => !(g && Array.isArray(g.hooks) && g.hooks.length === 0));
function save(raw, s) {
  const eol = raw.includes('\r\n') ? '\r\n' : '\n';
  const next = JSON.stringify(s, null, 2).replace(/\n/g, eol) + eol;
  if (next === raw) return true;
  const file = settingsFile(); const tmp = `${file}.tmp`;
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    if (raw && !fs.existsSync(`${file}.before-second-brain`)) fs.writeFileSync(`${file}.before-second-brain`, raw);
    fs.writeFileSync(tmp, next);
    fs.renameSync(tmp, file);
    return true;
  } catch { try { fs.unlinkSync(tmp); } catch { /* none */ } return false; }
}
function install() {
  const { raw, s, invalid } = load();
  // Never rewrite a settings file we cannot read: that would destroy whatever
  // the person, or another tool, put there.
  if (invalid) return { ok: false, reason: 'settings-invalid' };
  const hooks = s.hooks && typeof s.hooks === 'object' && !Array.isArray(s.hooks) ? s.hooks : {};
  for (const [ev, sub] of Object.entries(WANT)) {
    hooks[ev] = [...strip(hooks[ev]), { hooks: [{ type: 'command', command: command(sub), timeout: 30 }] }];
  }
  s.hooks = hooks;
  return save(raw, s) ? { ok: true } : { ok: false, reason: 'unwritable' };
}
function remove() {
  const { raw, s, invalid } = load();
  if (invalid || !s.hooks) return { ok: !invalid };
  for (const ev of Object.keys(WANT)) {
    if (!(ev in s.hooks)) continue;
    const kept = strip(s.hooks[ev]);
    if (kept.length) s.hooks[ev] = kept; else delete s.hooks[ev];
  }
  if (!Object.keys(s.hooks).length) delete s.hooks;
  return { ok: save(raw, s) };
}
function status() {
  const { s, invalid } = load();
  if (invalid) return { installed: false, invalid: true };
  const has = (ev, sub) => ((s.hooks || {})[ev] || []).some((g) => g && Array.isArray(g.hooks)
    && g.hooks.some((h) => h && OURS.test(String(h.command || '')) && String(h.command).trim().endsWith(` ${sub}`)));
  return { installed: Object.entries(WANT).every(([ev, sub]) => has(ev, sub)), invalid: false };
}

if (require.main === module) {
  const cmd = process.argv[2];
  if (cmd === 'session-start') {
    try { process.stdout.write(`${sessionStart()}\n`); } catch { /* never block a chat */ }
    process.exit(0);
  } else if (cmd === 'stop') {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { data += c; });
    process.stdin.on('end', () => {
      try { const r = stop(JSON.parse(data)); if (r) process.stdout.write(`${JSON.stringify(r)}\n`); } catch { /* never block a chat */ }
      process.exit(0);
    });
  } else if (cmd === 'install' || cmd === 'remove' || cmd === 'status') {
    const r = cmd === 'install' ? install() : cmd === 'remove' ? remove() : status();
    process.stdout.write(`${JSON.stringify(r)}\n`);
  } else {
    process.stderr.write('usage: hooks.js session-start | stop | install | remove | status\n');
    process.exit(2);
  }
}
module.exports = { sessionStart, stop, install, remove, status, command, dailyFile };
