'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { vimigo } = require('./paths.js');
const file = () => path.join(vimigo(), 'identity.json');
function read() { try { const o = JSON.parse(fs.readFileSync(file(), 'utf8')); return o && typeof o === 'object' ? o : null; } catch { return null; } }
function write(obj) {
  fs.mkdirSync(vimigo(), { recursive: true });
  const tmp = file() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
  fs.renameSync(tmp, file());
}
const newId = () => crypto.randomBytes(16).toString('hex');

// Every fact on this file belongs to ONE event. An identity written before
// fix round 4 may carry no `event` at all (a decline or an announcement
// recorded before ever enrolling), or a bare `announced: true` (round 2).
// Every one of those was written at V003 - V002 used the old setup, which had
// no identity.json - so that is the event they belong to, never "any event".
//
// This id is hard-coded on purpose, and must never become "the current
// event": it names the one event whose declines were written without an
// event id. A later event's decline always carries its own `event`.
const LEGACY_EVENT = 'V003';
function eventOf(id) {
  if (!id) return null;
  if (id.event) return id.event;
  // Fix round 5 (N-1): an old-format decline answered V003, whatever
  // `announced` says. `announced` is rewritten by `sync.js --announce` at every
  // later event, so reading it here turned a V003 "no" into a "no" to V004 the
  // moment the line was said there.
  if (id.declined) return LEGACY_EVENT;
  if (typeof id.announced === 'string' && id.announced) return id.announced;
  return LEGACY_EVENT;
}
// Has this laptop already answered the saving question at SOME event -
// enrolled in one (it still holds that event's token, finished or not), or
// said no to one? Fix round 5: ZO.md, the last-day prompt and MASTER.md hand a laptop
// to START's sync row only when this is false, so nobody who took part in one
// event is ever moved into a different event by a prompt they ran at home.
// Every write that drops a token writes `declined` instead (sync.js --stop),
// so this stays true once it is true.
function joinedBefore(id) {
  return !!(id && (id.token || id.declined));
}
// An enrolment that can still be running for its own event: a token, and
// nothing recorded that has stopped it. Whether that event is still open is
// the server's answer (lib/event.js ownEvent), never guessed here.
function mayBeSaving(id) {
  return !!(id && id.token && !id.declined && !id.finished && !id.closed);
}
// Task 14: which conversations belong to this enrolment - everything changed
// since its event OPENED, so a late joiner's first days count too. An
// identity written before Task 14 has no opening on it, and keeps starting
// from its own enrolment.
function sinceMs(id) {
  if (!id) return null;
  if (Number.isFinite(id.eventOpensAtMs)) return id.eventOpensAtMs;
  if (Number.isFinite(id.enrolledAtMs)) return id.enrolledAtMs;
  return null;
}
function announcedOf(id) {
  if (!id || !id.announced) return null;
  return typeof id.announced === 'string' ? id.announced : LEGACY_EVENT;
}
// The facts that count for `eventId` - the event the server says is open
// right now. Anything recorded for another event (or with no event open, or
// the server unreachable: eventId null) counts for nothing.
function factsFor(id, eventId) {
  const mine = !!(id && eventId && eventOf(id) === eventId);
  return {
    enrolled: mine && !!id.token,
    declined: mine && !!id.declined,
    finished: mine && !!id.finished,
    closed: mine && !!id.closed,
    announced: !!eventId && announcedOf(id) === eventId,
  };
}
module.exports = { read, write, newId, file, eventOf, announcedOf, factsFor, joinedBefore, mayBeSaving, sinceMs, LEGACY_EVENT };
