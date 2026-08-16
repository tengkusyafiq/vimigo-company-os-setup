#!/usr/bin/env node
'use strict';
// Owns ~/.vimigo/state.json. The only writer. Everything else reads through it,
// so a row cannot be marked done by anyone who did not actually run its check.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const receipt = require('./receipt.js');

const ROWS = [
  { id: 'runtimes',     title: 'Node, Git and Python',     waiting: 'not started yet',    optional: false },
  { id: 'compile-data', title: 'Your /compile-data skill', waiting: 'not started yet',    optional: false },
  { id: 'zo',           title: 'Your Zo account',          waiting: 'not started yet',    optional: false },
  { id: 'whatsapp',     title: 'WhatsApp',                 waiting: 'only if you want it', optional: true },
  { id: 'hcs-fix',      title: 'The Cowork fix',           waiting: 'only if you need it', optional: true },
];
const STATUSES = ['done', 'doing', 'todo', 'blocked', 'not_asked'];
const GLYPH = { done: '✓', doing: '◐', todo: '●', blocked: '✗', not_asked: '·' };

const homeDir = () => process.env.VIMIGO_HOME || path.join(os.homedir(), '.vimigo');
const statePath = () => path.join(homeDir(), 'state.json');

function die(code, message) {
  process.stderr.write(message + '\n');
  process.exit(code);
}

// Everything here is read aloud to somebody who has never opened a terminal, so
// a path or an error message reaching this file is a defect wherever it came
// from. Refuse it at the boundary rather than stripping it later - a value that
// gets quietly rewritten is one nobody fixes upstream.
// Only signals that cannot appear in a legitimate sentence. A first attempt
// also rejected anything containing "node " or "python3 " as a command, which
// refused the real evidence string - "all three ready - Node 24.18.0, Git
// 2.55.0, Python 3.13.3" - and would have made that row impossible to mark.
// A guard that blocks the happy path is worse than no guard.
const UNSAFE = [
  /[/\\](Users|home)[/\\]/i,          // a home directory, either separator
  /^[A-Za-z]:[/\\]/,                  // a Windows drive path
  /\b(Error|Exception|Traceback|ENOENT|EACCES)\b/i,
  /\s--\w/,                           // a command-line flag; an em dash is not
];
function refuseUnsafe(what, value) {
  const v = String(value).trim();
  if (!v) die(2, `${what} cannot be blank`);
  if (v.startsWith('--')) die(2, `${what} looks like a missing value, not a value`);
  for (const re of UNSAFE) {
    if (re.test(v)) die(2, `${what} contains something an owner must never be shown`);
  }
  return v;
}

function fresh() {
  return {
    version: null,
    machine: { os: process.platform, release: os.release() },
    rows: ROWS.map((r) => ({
      id: r.id,
      status: r.optional ? 'not_asked' : 'todo',
      evidence: null,
    })),
    blocked: [],
  };
}

function read({ createIfMissing = false } = {}) {
  const p = statePath();
  if (!fs.existsSync(p)) {
    if (!createIfMissing) return fresh();
    fs.mkdirSync(homeDir(), { recursive: true });
    const s = fresh();
    write(s);
    return s;
  }
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    // Never overwrite. A corrupt file is somebody's progress, and guessing at
    // it is worse than stopping.
    die(3, 'state file is not readable');
  }
  if (!raw || !Array.isArray(raw.rows)) die(3, 'state file is not readable');
  // A file that parses is not a file that is shaped right. A half-written row
  // is null, and reaching into it throws a stack trace carrying an absolute
  // path - the one thing this program exists to keep off an owner's screen.
  for (const r of raw.rows) {
    if (!r || typeof r !== 'object' || typeof r.id !== 'string'
        || !STATUSES.includes(r.status)) {
      die(3, 'state file is not readable');
    }
    // done without evidence is the invariant this whole program exists to hold.
    // Enforcing it only on the way in left a hand-edited or half-written file
    // rendering a green tick beside the word "ready", which is exactly the lie
    // the evidence rule is meant to make impossible.
    if (r.status === 'done' && (typeof r.evidence !== 'string' || !r.evidence.trim())) {
      die(3, 'state file is not readable');
    }
  }
  // Add rows introduced since the file was written.
  for (const r of ROWS) {
    if (!raw.rows.some((x) => x.id === r.id)) {
      raw.rows.push({ id: r.id, status: r.optional ? 'not_asked' : 'todo', evidence: null });
    }
  }
  // And drop rows that have since been withdrawn. This used to only add, which
  // left a machine showing a row nothing could do any more - and the sort below
  // uses findIndex, which answers -1 for a row the code does not know, so the
  // withdrawn one would have sorted to the very top of the owner's checklist.
  raw.rows = raw.rows.filter((x) => ROWS.some((r) => r.id === x.id));
  raw.blocked = Array.isArray(raw.blocked)
    ? raw.blocked.filter((b) => b && ROWS.some((r) => r.id === b.id))
    : [];
  raw.rows.sort((a, b) => ROWS.findIndex((r) => r.id === a.id) - ROWS.findIndex((r) => r.id === b.id));
  return raw;
}

// Write to a sibling and rename. A truncating write that loses power halfway
// leaves a file that parses as nothing, and restarts are not an edge case here
// - the setup asks for them.
function write(state) {
  fs.mkdirSync(homeDir(), { recursive: true });
  const tmp = statePath() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + '\n');
  fs.renameSync(tmp, statePath());
}

// Does not consume a following token that is itself a flag: `--evidence
// --reason x` should be a missing value, not the literal string "--reason".
function flag(args, name) {
  const i = args.indexOf(name);
  if (i === -1) return null;
  const v = args[i + 1];
  return v === undefined || v.startsWith('--') ? null : v;
}

function render(state) {
  return ROWS.map((row) => {
    const r = state.rows.find((x) => x.id === row.id);
    const note = r.status === 'done' ? (r.evidence || 'ready')
      : r.status === 'doing' ? 'working on it now'
      : r.status === 'blocked' ? (state.blocked.find((b) => b.id === row.id)?.reason || 'not possible on this computer')
      : row.waiting;
    return `   ${GLYPH[r.status] || '·'}  ${row.title.padEnd(30)}${note}`;
  }).join('\n');
}

function main() {
  const [cmd, ...args] = process.argv.slice(2);

  if (cmd === 'init') {
    const s = read({ createIfMissing: true });
    const v = flag(args, '--version');
    if (v) s.version = v;
    write(s);
    process.stdout.write(render(s) + '\n');
    return;
  }
  if (cmd === 'show') {
    process.stdout.write(render(read()) + '\n');
    return;
  }
  if (cmd === 'json') {
    process.stdout.write(JSON.stringify(read(), null, 2) + '\n');
    return;
  }
  if (cmd === 'set') {
    const [id, status] = args;
    if (!ROWS.some((r) => r.id === id)) die(2, 'unknown row');
    if (!STATUSES.includes(status)) die(2, 'unknown status');
    let evidence = flag(args, '--evidence');
    if (status === 'done') {
      // The whole point of this program. A row is green because a check said
      // so, not because somebody typed a convincing sentence.
      if (!evidence) die(2, 'done needs --evidence');
      evidence = refuseUnsafe('evidence', evidence);
      const rec = receipt.read(id);
      if (!rec || rec.ok !== true) {
        die(2, 'no passing check for this row - run its verify.js first');
      }
      if (rec.evidence !== evidence) {
        die(2, 'evidence does not match what the check reported');
      }
      // A receipt from a previous session is not evidence about this one. The
      // owner shuts the laptop, something stops working overnight, and the
      // resumed run would otherwise mark the row green off yesterday's answer
      // - which is precisely the day-two failure this setup keeps meeting.
      const age = Date.now() - Date.parse(rec.at || '');
      if (!Number.isFinite(age) || age < 0 || age > 30 * 60 * 1000) {
        die(2, 'that check is too old to trust - run its verify.js again');
      }
    } else if (evidence) {
      evidence = refuseUnsafe('evidence', evidence);
    }
    const s = read({ createIfMissing: true });
    const row = s.rows.find((r) => r.id === id);
    row.status = status;
    if (evidence) row.evidence = evidence;
    if (status !== 'blocked') s.blocked = s.blocked.filter((b) => b.id !== id);
    write(s);
    process.stdout.write(render(s) + '\n');
    return;
  }
  if (cmd === 'block') {
    const [id] = args;
    const reason = flag(args, '--reason');
    if (!ROWS.some((r) => r.id === id)) die(2, 'unknown row');
    if (!reason) die(2, 'block needs --reason');
    const safe = refuseUnsafe('reason', reason);
    const s = read({ createIfMissing: true });
    s.rows.find((r) => r.id === id).status = 'blocked';
    s.blocked = s.blocked.filter((b) => b.id !== id).concat([{ id, reason: safe }]);
    write(s);
    process.stdout.write(render(s) + '\n');
    return;
  }
  die(2, 'usage: state.js init [--version V]|show|json|set <id> <status> [--evidence T]|block <id> --reason T');
}

if (require.main === module) main();
module.exports = { ROWS, STATUSES, render, read };
