#!/usr/bin/env node
'use strict';
// Which Vimigo event is open right now? Asked of the server itself
// (GET /v1/current), which decides from the events on its dashboard and the
// clock - so a new event needs nothing but creating it there. When windows
// overlap, the server answers with the most recently opened one.
//
// currentEvent() answers one of:
//   { state: 'open', id, opensAt, closesAt }
//   { state: 'none' }     nothing open - also when the manifest's event block
//                         says `enroll: false` (the global kill switch) or has
//                         no address `e` to ask
//   { state: 'offline' }  no answer: a network error, 10 s without a reply, a
//                         non-200, or an answer that is not the expected JSON
//
// The manifest's own `event.id`, `opens` and `closes` are never used for a
// decision any more (Task 12 owns manifest.json; they stay in it). Only its
// `e` (where the server is) and its `enroll` kill switch are read.
//
//   node lib/event.js      prints the answer as one line of JSON
const fs = require('node:fs');
const path = require('node:path');
const { setupDir } = require('./paths.js');
const { decode } = require('./endpoint.js');

const TIMEOUT = 10_000;
const EVENT_ID = /^[A-Za-z0-9-]{2,32}$/;
const OFFLINE = Object.freeze({ state: 'offline' });
const NONE = Object.freeze({ state: 'none' });

// The copy step 0 downloaded to <home>/.vimigo/setup (refreshed every session).
function localManifest() {
  try { return JSON.parse(fs.readFileSync(path.join(setupDir(), 'manifest.json'), 'utf8')); } catch { return null; }
}

// Asks one server directly which event is open now. currentEvent() uses it
// once the manifest has said where the server is and that joining is on.
// (Since fix round 5 the job and doctor never ask this: an enrolment follows
// its own event's answer - ownEvent() below.)
// `timeout` (ms, default TIMEOUT): Task 14 fix round 1 - a wrap-up's final
// send passes what is left of its own time limit.
async function ask(base, timeout = TIMEOUT) {
  let res;
  try { res = await fetch(`${base}/v1/current`, { cache: 'no-store', signal: AbortSignal.timeout(timeout) }); }
  catch { return { ...OFFLINE }; }
  if (res.status !== 200) return { ...OFFLINE };
  let body;
  try { body = await res.json(); } catch { return { ...OFFLINE }; }
  if (!body || body.ok !== true || !('event' in body)) return { ...OFFLINE };
  if (body.event === null) return { ...NONE };
  const ev = body.event;
  if (!ev || typeof ev !== 'object' || typeof ev.id !== 'string' || !EVENT_ID.test(ev.id)) return { ...OFFLINE };
  return { state: 'open', id: ev.id, opensAt: ev.opensAt || null, closesAt: ev.closesAt || null };
}

// Fix round 5 - the enrolment principle: an existing enrolment keeps running
// for ITS OWN event until the server says that event is closed. Asked of the
// server it enrolled against, ignoring the manifest's kill switch (that
// governs joining, not an enrolment that is already running).
//
// /v1/current answers it when it names this event (open) or nothing at all
// (then nothing is open, this event included). Only when it names ANOTHER
// event - windows overlap, and it names the newest - is the event itself
// asked, the way the job asks it: a hello with the identity's own id and
// token. That hello sends no profile and no progress, so it changes nothing
// on the dashboard but the last-seen time.
//
//   { state: 'open' }     the event is open
//   { state: 'closed' }   the event is over (`open: false`, or nothing open)
//   { state: 'offline' }  no usable answer - nothing can be decided
async function ownEvent(id, timeout = TIMEOUT) {
  if (!id || !id.token || !id.event || !id.id) return { state: 'closed' };
  let base;
  try { base = decode(id.e); } catch { return { ...OFFLINE }; }
  const now = await ask(base, timeout);
  if (now.state === 'offline') return { ...OFFLINE };
  if (now.state === 'none') return { state: 'closed' };
  if (now.id === id.event) return { state: 'open' };
  let res;
  try {
    res = await fetch(`${base}/v1/hello`, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: id.id, event: id.event, token: id.token }), signal: AbortSignal.timeout(timeout) });
  } catch { return { ...OFFLINE }; }
  let body = {};
  try { body = await res.json(); } catch { /* not JSON */ }
  if (body && body.open === false && (res.status === 200 || res.status === 403)) return { state: 'closed' };
  if (res.status === 200 && body && body.ok === true && body.open === true) return { state: 'open' };
  return { ...OFFLINE };
}

// `manifest`: an already-parsed manifest (enrol.js fetches the live one), or
// omitted to read the local copy.
async function currentEvent(manifest, timeout = TIMEOUT) {
  const m = manifest === undefined ? localManifest() : manifest;
  const ev = m && typeof m === 'object' ? m.event : null;
  if (!ev || typeof ev !== 'object' || ev.enroll === false || !ev.e) return { ...NONE };
  let base;
  try { base = decode(ev.e); } catch { return { ...NONE }; }
  return ask(base, timeout);
}

if (require.main === module) {
  currentEvent().then((r) => process.stdout.write(JSON.stringify(r) + '\n'));
}
module.exports = { currentEvent, ask, ownEvent, TIMEOUT };
