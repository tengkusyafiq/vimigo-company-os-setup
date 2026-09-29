#!/usr/bin/env node
'use strict';
// The job. Wakes every two minutes, sends what changed, exits. Nothing
// long-running to die: a crashed run is simply replaced by the next one.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const identity = require('./identity.js');
const { decode } = require('./endpoint.js');
const { scrubBuffer } = require('./scrub.js');
const { sources, walk } = require('./sources.js');
const { syncDir, isSandboxed, schedulerOff } = require('./paths.js');
const event = require('./event.js');

const zlib = require('node:zlib');

const PER_FILE = 100 * 1024 * 1024;
const HELLO_EVERY = 10 * 60_000;
const LOCK_STALE = 10 * 60_000;
// Task 14 (M-A): a final send waits at most 45 s for a scheduled run's lock -
// well inside Claude Code's 2-minute command limit, so the AI is never killed
// mid-wait (which used to leave the lock behind for 10 minutes). After that it
// answers `busy-retry`, and WRAP-UP simply runs it once more. The test
// override exists only so a test need not sit through the real 45 s.
const LOCK_WAIT = 45_000;
const lockWait = () => Number(process.env.VIMIGO_TEST_LOCK_WAIT_MS) || LOCK_WAIT;
// For the same reason the final send as a whole has a hard time limit: every
// request in it - the lock wait, the hello, each upload in flight, the final
// check - is cut off by what is left of it, and a request cut off that way is
// `busy-retry`, never a failure. The next run carries on from the ledger, and
// `finalWanted` (below) lets the scheduled job finish the wrap-up by itself.
//
// Fix round 1: 8 s. Codex runs a command for 10 s unless the AI asks for more
// (codex-rs core/src/exec.rs: DEFAULT_EXEC_COMMAND_TIMEOUT_MS = 10_000);
// Claude Code's default is 2 minutes. 8 s leaves room for Node's start-up and
// the outcome itself; WRAP-UP.md simply runs it again while it says
// `busy-retry`.
const FINAL_BUDGET = 8_000;
const finalBudget = () => Number(process.env.VIMIGO_TEST_FINAL_BUDGET_MS) || FINAL_BUDGET;
// The final's hard deadline (Infinity for the scheduled job, which has its own
// per-request limits and a 100 s budget for starting uploads).
let hardDeadline = Infinity;
class Cut extends Error { constructor() { super('cut off by the time limit'); this.cut = true; } }
// Runs one request with its own limit, never past the hard deadline. A request
// stopped by the deadline (not by its own limit, not by the network) throws Cut.
async function limited(limit, fn) {
  const left = hardDeadline - Date.now();
  if (left <= 0) throw new Cut();
  const capped = left < limit;
  const signal = AbortSignal.timeout(Math.min(limit, left));
  try { return await fn(signal); } catch (e) {
    if (capped && signal.aborted) throw new Cut();
    throw e;
  }
}
const json = (res, signal) => res.json().catch((e) => { if (signal.aborted) throw e; return {}; });
// Merged into what is on disk now, never a copy read earlier: the job and a
// wrap-up can each be writing the identity (fix round 1, m-2).
const patch = (fields) => identity.write({ ...(identity.read() || {}), ...fields });
// Task 14: 150 laptops share one venue wifi. Text-like files over 32 KB go up
// gzipped (conversations shrink 5-8x); the server stores - and hashes - the
// original bytes (server/src/api.js, /v1/file).
const GZIP_OVER = 32 * 1024;
const GZIP_EXT = /\.(md|txt|json|jsonl|csv|html|js|ts|py|yaml|yml)$/i;
const gzipWanted = (key, size) => size > GZIP_OVER && GZIP_EXT.test(key);
// And a conversation that keeps growing is not re-sent every two minutes: over
// 1 MB at most every 10 minutes, over 10 MB at most every 30. The Second Brain
// itself is never paced, and a final send ignores pacing altogether.
const MB = 1024 * 1024;
function paceMs(key, size) {
  if (!/^(claude|codex|cowork)\//.test(key)) return 0;
  if (size > 10 * MB) return 30 * 60_000;
  if (size > MB) return 10 * 60_000;
  return 0;
}
// A final that meets a busy server (503) tries again a couple of times, briefly,
// before answering `busy-retry`.
const FINAL_BUSY_TRIES = 3;
const FINAL_BUSY_PAUSE = 3_000;
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const readJson = (f, d) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return d; } };
function writeJson(f, o) { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f + '.tmp', JSON.stringify(o)); fs.renameSync(f + '.tmp', f); }
const F = { ledger: () => path.join(syncDir(), 'ledger.json'), lastOk: () => path.join(syncDir(), 'last-ok.json'),
  lock: () => path.join(syncDir(), 'run.lock'), log: () => path.join(syncDir(), 'sync.log') };

// Is the process that wrote this lock still running? Only a definite "no such
// process" says it is gone; anything else (EPERM: running as someone else, an
// unreadable pid) is treated as alive, and the 10-minute staleness decides.
function holderGone(text) {
  const pid = Number(String(text).trim());
  if (!Number.isInteger(pid) || pid <= 0) return false;
  if (pid === process.pid) return false;
  try { process.kill(pid, 0); return false; } catch (e) { return !!(e && e.code === 'ESRCH'); }
}
function tryLock() {
  fs.mkdirSync(syncDir(), { recursive: true });
  try {
    const st = fs.statSync(F.lock());
    // Task 14 (M-A): a lock whose process is gone (an AI's command killed at
    // its time limit, a laptop put to sleep mid-run) is taken over at once,
    // not after 10 minutes.
    const gone = holderGone(fs.readFileSync(F.lock(), 'utf8'));
    if (!gone && Date.now() - st.mtimeMs < LOCK_STALE) return false;
    fs.unlinkSync(F.lock());
  } catch { /* none */ }
  try { fs.writeFileSync(F.lock(), String(process.pid), { flag: 'wx' }); return true; } catch { return false; }
}
// The scheduled job simply skips a run while another holds the lock. A
// wrap-up's final send waits for it instead (a scheduled run finishes within
// its ~100 s budget) - skipping would leave the last files unsent - but never
// longer than lockWait(); then it answers `busy-retry`.
async function lock(wait) {
  const until = Math.min(Date.now() + (wait ? lockWait() : 0), hardDeadline);
  for (;;) {
    if (tryLock()) return true;
    if (Date.now() >= until) return false;
    await new Promise((r) => setTimeout(r, 1000));
  }
}
const unlock = () => { try { fs.unlinkSync(F.lock()); } catch { /* gone */ } };
function removeScheduler() {
  if (schedulerOff()) return;
  try { require('./scheduler.js').remove(); } catch { /* best effort */ }
}

// The ledger (what was sent, and its hash) belongs to one event: a file sent
// to V003 has not been sent to V004. Tagged with the event under a key no
// file key can have (every file key starts with its kind, "brain/" etc). An
// untagged ledger was written before fix round 4, at V003.
const LEDGER_EVENT = '#event';
function readLedger(eventId) {
  const l = readJson(F.ledger(), {});
  const owner = typeof l[LEDGER_EVENT] === 'string' ? l[LEDGER_EVENT] : identity.LEGACY_EVENT;
  return owner === eventId ? { ...l, [LEDGER_EVENT]: eventId } : { [LEDGER_EVENT]: eventId };
}

async function call(base, id, pathname, { method = 'POST', body, headers = {} } = {}) {
  return limited(60000, async (signal) => {
    const res = await fetch(base + pathname, { method, body, signal,
      headers: { 'x-event': id.event, 'x-id': id.id, 'x-token': id.token, ...headers } });
    return { status: res.status, body: await json(res, signal) };
  });
}

// The server cannot see session 2 (Zo) on its own - only this laptop's own
// state.json knows. Read through lib/state.js's own validation, but its
// readSafe(), never read(): read() exits the process on an unreadable file,
// and this job must never die over a file it only glances at (m-2). A
// missing file reads as the all-todo shape; an unreadable one as null, which
// the caller treats as "unchanged", never as a regression to zo:false.
function zoProgress() {
  try {
    const s = require('./state.js').readSafe();
    if (!s) return null;
    const row = (s.rows || []).find((r) => r.id === 'zo');
    return { zo: row?.status === 'done' };
  } catch {
    return null;
  }
}

async function hello(base, id, progress) {
  return limited(15000, async (signal) => {
    const r = await fetch(base + '/v1/hello', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: id.id, event: id.event, token: id.token, progress }), signal });
    return { status: r.status, body: await json(r, signal) };
  });
}

// `paced`: changed conversations held back by pacing (sent on a later run).
// `deferred`: the server said it was busy (503) - not a failure; the rest
// waits for the next run, and the loop stops at once so a full server is not
// asked again for every remaining file.
async function upload(base, id, ledger, files, deadline, { final = false } = {}) {
  let uploaded = 0, skipped = 0, failed = 0, paced = 0, deferred = 0, unfinished = false, open = true, dirty = 0;
  for (const f of files) {
    if (Date.now() > deadline) { unfinished = true; break; }
    const prev = ledger[f.key];
    if (prev && prev.skipped && prev.size === f.size) { skipped++; continue; }
    if (prev && prev.mtimeMs === f.mtimeMs && prev.size === f.size) { skipped++; continue; }
    const pace = final ? 0 : paceMs(f.key, f.size);
    if (pace && prev && prev.sha && Number.isFinite(prev.sentAt) && Date.now() - prev.sentAt < pace) { paced++; continue; }
    let buf; try { buf = scrubBuffer(fs.readFileSync(f.abs)); } catch { failed++; continue; }
    const digest = sha(buf);
    if (prev && prev.sha === digest) { ledger[f.key] = { ...prev, mtimeMs: f.mtimeMs, size: f.size }; skipped++; continue; }
    const gz = gzipWanted(f.key, buf.length);
    let r;
    try {
      r = await call(base, id, '/v1/file', { method: 'PUT', body: gz ? zlib.gzipSync(buf) : buf,
        headers: { 'x-key': encodeURIComponent(f.key), 'x-sha256': digest, 'content-type': 'application/octet-stream',
          ...(gz ? { 'content-encoding': 'gzip' } : {}) } });
    } catch (e) {
      if (e && e.cut) { unfinished = true; break; }        // out of time: the next run carries on
      failed++; break;                                      // offline: stop, keep the rest for next time
    }
    if (r.status === 200) { ledger[f.key] = { sha: digest, size: f.size, mtimeMs: f.mtimeMs, sentAt: Date.now() }; uploaded++; dirty++; }
    else if (r.status === 413) { ledger[f.key] = { skipped: 'too-big', size: f.size }; skipped++; }
    else if (r.status === 403 && r.body.open === false) { open = false; break; }
    else if (r.status === 503) { deferred++; break; }
    else failed++;
    if (dirty >= 20) { writeJson(F.ledger(), ledger); dirty = 0; }
  }
  writeJson(F.ledger(), ledger);
  return { uploaded, skipped, failed, paced, deferred, unfinished, open };
}

// Fix round 5 (N-2): WRAP-UP.md picks its one closing line from `outcome`,
// never from `ok` or `reason` - each run of `--final` ends in exactly one:
//   sent          the final send worked for this laptop's own event (now, or
//                 in an earlier wrap-up)
//   declined      the owner said no; nothing is sent
//   closed        this laptop's own event has already ended
//   offline       enrolled, but nothing more could be sent now: no answer
//                 from Vimigo, a refusal, or files the server still lacks.
//                 The job is still installed and sends the rest by itself.
//   busy-retry    Task 14: Vimigo is busy (503), or a scheduled run held the
//                 lock for longer than lockWait() - run the final once more
//   nothing-sent  Task 14: never enrolled, while an event is open or Vimigo
//                 cannot be reached - its work exists, and none of it got there
//   not-enrolled  never enrolled, and no event is open to send to
// The questions finalOutcome asks come only after a run that returned at once
// (finished, never enrolled); they still keep inside the final's time limit,
// with a floor so a real answer has a chance.
const askLimit = () => Math.min(event.TIMEOUT, Math.max(1000, hardDeadline - Date.now()));
async function finalOutcome(r) {
  if (r.reason === 'declined') return 'declined';
  if (r.reason === 'closed') return 'closed';
  if (r.reason === 'finished') {
    // Task 14 (I-B): `finished` belongs to the laptop's own event. An alumnus
    // running wrap-up at a later event finished an event that is over - that
    // is `closed`, never "your work is with Vimigo". With no answer, it is
    // still the finish it recorded (a wrap-up re-run offline).
    return (await event.ownEvent(identity.read(), askLimit())).state === 'closed' ? 'closed' : 'sent';
  }
  if (r.reason === 'busy') return 'busy-retry';
  if (r.reason === 'not-enrolled') {
    const now = await event.currentEvent(undefined, askLimit());
    return now.state === 'none' ? 'not-enrolled' : 'nothing-sent';
  }
  if (r.ok === true && Array.isArray(r.missing) && r.missing.length === 0) return 'sent';
  return 'offline';
}

// The answers that need no network: a decline, never enrolled, or already
// stopped for its own event. Null when there is work to do.
function settled(id) {
  // A decline is checked before anything else, token or not: a decline made
  // after enrolling still carries a token, one made before never had one, and
  // either way nothing is ever sent and nothing reads as "finished" (which the
  // owner reasonably takes to mean their work went up).
  if (id && id.declined) return { ok: true, reason: 'declined' };
  if (!id || !id.token) return { ok: false, reason: 'not-enrolled' };
  // Already stopped for its own event: answered from the identity alone, with
  // no network - a wrap-up run again later, even offline, still hears that
  // everything went up (round-4 re-review m-2).
  if (id.finished) return { ok: true, reason: 'finished' };
  if (id.closed) return { ok: true, open: false, reason: 'closed' };
  return null;
}

async function runSync({ final = false, finish = false, scheduled = false, budgetMs = 100_000 } = {}) {
  const started = Date.now();
  hardDeadline = final ? started + finalBudget() : Infinity;
  let id = identity.read();
  // A wrap-up run again after an earlier one finished: WRAP-UP updates the
  // submission, and they may have made more since - so this sends what is new
  // or changed, instead of answering "all sent" from the old finish. It is a
  // wrap-up in progress again until it finishes, with the job back on, so
  // anything that cannot go right now still goes by itself. (If the laptop's
  // own event has closed, the hello below says so and switches it off again.)
  // With nothing new or changed since, it stays finished and says so, even
  // offline (round-4 re-review m-2).
  if (final && finish && id && id.token && id.finished && !id.declined && !id.closed) {
    const led = readLedger(id.event);
    const changed = sources(identity.sinceMs(id) || 0).flatMap((s) => walk(s, PER_FILE))
      .some((f) => !led[f.key] || led[f.key].mtimeMs !== f.mtimeMs);
    if (changed) {
      patch({ finished: false, finalWanted: true });
      id = identity.read();
      if (!schedulerOff()) { try { require('./scheduler.js').install(); } catch { /* the final itself still runs */ } }
    }
  }
  const early = settled(id);
  if (early) return early;
  // Task 14: a wrap-up's `--final --finish` is recorded before it sends
  // anything - before it even waits for the lock (fix round 1, m-1). If it
  // cannot finish now - Vimigo busy, the wifi gone, more to send than fits in
  // one run, a scheduled run holding the lock, or the AI's command stopped -
  // the scheduled job carries on and finishes it by itself once everything is
  // up (below), so "the rest will send by itself" is true to the end, the
  // dashboard's "Finished" included.
  if (final && finish && !id.finalWanted) { patch({ finalWanted: true }); id = identity.read(); }
  let base;
  try { base = decode(id.e); } catch { return { ok: false, reason: 'error' }; }
  // Fix round 5 - the enrolment principle: this job works for the identity's
  // OWN event for as long as that event's own hello says it is open. It never
  // asks /v1/current (which names only the newest open event, so another
  // event opening - an overlap - would have stood it down), and it never
  // reads the manifest's kill switch (that governs joining, not a job that is
  // already running). It stops when the hello or an upload says `open:false`,
  // when the owner says no, or when wrap-up finishes.
  if (!(await lock(final))) return { ok: !final, reason: 'busy' };
  try {
    // Fix round 1 (m-2): read again now that the lock is ours - a scheduled
    // run may have changed it while this one waited.
    id = identity.read();
    const changed = settled(id);
    if (changed) return changed;
    const wrapUp = final || !!id.finalWanted;
    const ledger = readLedger(id.event);
    // Task 14: conversations from the event's opening (the identity's
    // `eventOpensAtMs`), else - an identity from before Task 14 - its enrolment.
    const files = sources(identity.sinceMs(id) || 0).flatMap((s) => walk(s, PER_FILE));
    const pending = files.some((f) => !ledger[f.key] || ledger[f.key].mtimeMs !== f.mtimeMs);
    // Dashboard visibility for session 2: send hello whenever Zo's own
    // done/not-done flips too, not only on the ordinary 10-minute timer -
    // otherwise a laptop that never touches its brain files again after
    // finishing Zo would never tell the dashboard that happened.
    const progress = zoProgress() || id.lastProgress || { zo: false };
    const progressChanged = JSON.stringify(progress) !== JSON.stringify(id.lastProgress || null);
    if (final || pending || progressChanged || !id.lastHelloAt || Date.now() - id.lastHelloAt > HELLO_EVERY) {
      let h;
      try { h = await hello(base, id, progress); } catch (e) { return { ok: false, reason: e && e.cut ? 'busy' : 'offline' }; }
      if (h.body && h.body.open === false && (h.status === 200 || h.status === 403)) {
        patch({ closed: true }); removeScheduler();
        return { ok: true, open: false, reason: 'closed' };
      }
      if (h.status !== 200) return { ok: false, reason: 'refused' };
      // lastProgress is only ever updated once the server has actually
      // acknowledged it (status 200) - a refusal or timeout must leave the
      // old value in place, so the very next run tries to send it again
      // instead of quietly believing the dashboard already has it.
      id.lastHelloAt = Date.now(); id.lastProgress = progress;
      patch({ lastHelloAt: id.lastHelloAt, lastProgress: progress });
    }
    const deadline = final ? started + finalBudget() : Date.now() + budgetMs;
    // Pacing is for the ordinary days: a wrap-up (now, or one the job is
    // finishing by itself) sends everything.
    let r = await upload(base, id, ledger, files, deadline, { final: wrapUp });
    // A final that meets a busy server tries again, briefly, before giving
    // the AI `busy-retry` (the scheduled job just leaves it for its next run).
    for (let i = 1; final && r.open && r.deferred && i < FINAL_BUSY_TRIES && Date.now() + FINAL_BUSY_PAUSE < deadline; i++) {
      await new Promise((ok) => setTimeout(ok, FINAL_BUSY_PAUSE));
      const again = await upload(base, id, ledger, files, deadline, { final: wrapUp });
      r = { uploaded: r.uploaded + again.uploaded, skipped: again.skipped, failed: r.failed + again.failed,
        paced: again.paced, deferred: again.deferred, unfinished: again.unfinished, open: again.open };
    }
    if (!r.open) { patch({ closed: true }); removeScheduler(); return { ok: true, ...r, reason: 'closed' }; }
    // A busy server (deferred) is not a failure: last-ok is still written, so
    // neither the checklist nor doctor.js turns red over it (Task 14).
    if (r.failed === 0) writeJson(F.lastOk(), { at: new Date().toISOString(), uploaded: r.uploaded, scheduled });
    if (!final) {
      // The scheduled job finishes a wrap-up that could not, once nothing is
      // left to send; until then it is an ordinary, successful run.
      const everythingUp = r.failed === 0 && !r.deferred && !r.unfinished;
      if (!id.finalWanted || !everythingUp) return { ok: r.failed === 0, ...r };
      const c = await confirm(base, id, ledger, files, deadline, r, true);
      return c.ok ? c : { ok: true, ...r, finalPending: true };
    }
    // Fix round 1 (I-1): never ask for the finish while anything failed - the
    // ledger still holds the old hash of a file whose new version failed, and
    // no hash at all for a new one, so /v1/final would find nothing missing
    // and the job would stand down with files unsent. `busy-retry` instead;
    // `finalWanted` keeps the job going until it can finish for real.
    if (r.deferred || r.unfinished || r.failed) return { ok: false, ...r, reason: 'busy' };
    return await confirm(base, id, ledger, files, deadline, r, finish);
  } finally { unlock(); }
}

// Asks Vimigo whether it has every file the ledger says was sent, re-sends
// what it lacks (once), and - with `finish` - stands the job down for good.
async function confirm(base, id, ledger, files, deadline, r, finish) {
  const present = () => Object.fromEntries(files.filter((f) => ledger[f.key] && ledger[f.key].sha).map((f) => [f.key, ledger[f.key].sha]));
  let fin;
  try {
    fin = await call(base, id, '/v1/final', { body: JSON.stringify({ files: present() }), headers: { 'content-type': 'application/json' } });
    if (fin.status === 200 && fin.body.missing.length) {
      for (const k of fin.body.missing) delete ledger[k];
      const re = await upload(base, id, ledger, files.filter((f) => fin.body.missing.includes(f.key)), deadline, { final: true });
      if (re.deferred || re.unfinished || re.failed) return { ok: false, ...r, reason: 'busy' };
      fin = await call(base, id, '/v1/final', { body: JSON.stringify({ files: present() }), headers: { 'content-type': 'application/json' } });
    }
  } catch (e) { return { ok: false, ...r, reason: e && e.cut ? 'busy' : 'offline' }; }
  const missing = fin.status === 200 ? fin.body.missing : null;
  const ok = Array.isArray(missing) && missing.length === 0;
  // A final check that is not a clean answer (a refusal, or a body without a
  // `missing` list) is not a finish either.
  if (ok && finish) {
    removeScheduler();
    const { finalWanted, ...rest } = identity.read() || id;
    identity.write({ ...rest, finished: true });
    require('./receipt.js').write('sync', { ok: true, evidence: 'all sent - finished' });
  }
  return { ok, ...r, missing: missing || [] };
}

function log(line) {
  try {
    fs.mkdirSync(syncDir(), { recursive: true });
    fs.appendFileSync(F.log(), `${new Date().toISOString()} ${line}\n`);
    const st = fs.statSync(F.log());
    if (st.size > 400_000) fs.writeFileSync(F.log(), fs.readFileSync(F.log()).subarray(-200_000));
  } catch { /* logging never fails a run */ }
}

async function main() {
  const a = process.argv.slice(2);
  const quiet = a.includes('--quiet');
  if (isSandboxed()) {
    const r = { ok: false, reason: 'sandbox' };
    if (!quiet) process.stdout.write(JSON.stringify(r) + '\n');
    process.exitCode = 1;
    return;
  }
  let r;
  if (a.includes('--stop')) {
    removeScheduler();
    const id = identity.read();
    // `declined` either way, enrolled or not - fix round 2. Writing
    // `finished` for an already-enrolled laptop (the fix round 1 behaviour)
    // read back as "all sent", which is exactly what the owner said no to.
    // `declined` stays its own fact, distinct from `finished` (a wrap-up
    // final) and `closed` (the event's window ending) - both of which mean
    // the work *did* go up.
    //
    // Fix round 4: a decline answers ONE event - the one open now (the owner
    // was just told about it), or, when that cannot be asked, the last event
    // the line was said for, else this identity's own. It is stamped as
    // `event`, which is what makes it count (lib/identity.js factsFor).
    //
    // Fix round 5: a laptop still saving to an earlier event whose window is
    // still open (another event opened on top of it) is saying no to THAT
    // enrolment - the one actually running - not to the newer event it was
    // never told about.
    const now = await event.currentEvent();
    const stillSaving = identity.mayBeSaving(id) && !(now.state === 'open' && now.id === id.event)
      && (await event.ownEvent(id)).state !== 'closed';
    const ev = stillSaving ? id.event
      : now.state === 'open' ? now.id : (identity.announcedOf(id) || (id && id.event) || null);
    if (!ev) {
      // Never enrolled, and no event to say no to: nothing is running, and
      // nothing needs recording.
      if (id) identity.write({ ...id, declined: true });
    } else if (id && id.token && id.event !== ev) {
      // Still holding a past event's identity: the no is for the new event,
      // and the old token has nothing to do with it.
      identity.write({ event: ev, declined: true, ...(id.announced ? { announced: id.announced } : {}) });
    } else {
      identity.write({ ...(id || {}), event: ev, declined: true });
    }
    r = { ok: true, stopped: true };
  } else if (a.includes('--announce')) {
    // Persists that the session-1 disclosure line has been said on this
    // laptop, for this event specifically - so a later re-entry into
    // steps/03-sync (an app restart mid-row, say) never says it twice, and a
    // later, different event is never silently skipped by an old laptop's
    // stamp. Written right after saying the line and before `enrol.js` runs.
    // The line is only ever said while an event is open; with none open
    // (or no answer) there is nothing to record against.
    const now = await event.currentEvent();
    if (now.state !== 'open') {
      r = { ok: false, reason: now.state };
    } else {
      const id = identity.read();
      identity.write(id ? { ...id, announced: now.id } : { announced: now.id });
      r = { ok: true, announced: now.id };
    }
  } else {
    const final = a.includes('--final');
    try { r = await runSync({ final, finish: a.includes('--finish'), scheduled: quiet }); }
    catch (e) { r = { ok: false, reason: 'error' }; log('error ' + (e && e.message)); }
    // Fix round 5 (N-2): a final run carries exactly one outcome, and `ok`
    // agrees with it - true only when the work actually went up - so no two
    // of WRAP-UP.md's closing lines can match the same result.
    if (final) { const outcome = await finalOutcome(r); r = { ...r, ok: outcome === 'sent', outcome }; }
  }
  log(JSON.stringify(r));
  const text = quiet ? '' : JSON.stringify(r) + '\n';
  // A final exits as soon as its answer is out: nothing left behind (a
  // keep-alive socket, a timer) may hold the AI's command open past its limit.
  if (a.includes('--final')) process.stdout.write(text, () => process.exit());
  else if (text) process.stdout.write(text);
}
if (require.main === module) main();
module.exports = { runSync, finalOutcome, gzipWanted, paceMs, LOCK_WAIT, FINAL_BUDGET };
