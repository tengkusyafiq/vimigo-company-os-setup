#!/usr/bin/env node
'use strict';
// Answers one question - does this laptop need START.md's §5-§7 run (again)
// right now? - for ZO.md, WRAP-UP.md, MASTER.md and START.md's own §5, so the
// rule lives in one place instead of four slightly different copies of it.
//
// Never from steps/03-sync/verify.js's liveness check: that only proves the
// last two-minute job ran recently, which flakes on ordinary event wifi or a
// lunch break with the lid closed (fix round 2).
//
// Fix round 5 - the owner's enrolment principle:
//   - An existing enrolment keeps running for its own event until the server
//     says that event is closed (or the owner said no, or wrap-up finished).
//     Another event opening - an overlap - changes nothing for it.
//   - A NEW enrolment happens only through START.md, run at an event, while
//     the server's /v1/current is open. A laptop whose last event is over
//     joins the new one when START is run there.
//   - ZO.md, WRAP-UP.md and MASTER.md hand off to START's sync row only for a
//     laptop that has never joined or said no to ANY event (a session 1 that
//     could not reach Vimigo, retried once online). A laptop that took part in
//     one event is never moved into another by a prompt run at home.
//
//   node lib/session1.js           the rule for ZO.md, WRAP-UP.md, MASTER.md
//   node lib/session1.js --start   the rule for START.md §5
//
// handoff = runtimes or second-brain not done  OR  joinSync, where
//   joinSync (default) = an event is open AND this laptop has never joined or
//                        said no to any event
//   joinSync (--start) = an event is open AND this laptop has neither joined
//                        nor said no to THAT event AND it is not still saving
//                        to an earlier event that has not closed yet
// Nothing hands off for sync on `none` or `offline`.
const identity = require('./identity.js');
const state = require('./state.js');
const { currentEvent, ownEvent } = require('./event.js');

async function status({ start = false } = {}) {
  const s = state.read();
  const row = (id) => (s.rows || []).find((r) => r.id === id);
  const runtimesDone = row('runtimes')?.status === 'done';
  const secondBrainDone = row('second-brain')?.status === 'done';
  const now = await currentEvent();
  const open = now.state === 'open';
  const eventId = open ? now.id : null;
  const id = identity.read();
  const f = identity.factsFor(id, eventId);
  const joinedBefore = identity.joinedBefore(id);
  // Still saving to an EARLIER event (another event than the open one) that
  // the server says has not closed: that enrolment keeps running, and START
  // leaves it alone. Asked only when it can matter. With no answer, it is
  // treated as still running - an enrolment is never abandoned on a guess.
  let stillSaving = false;
  if (open && !f.enrolled && identity.mayBeSaving(id)) {
    stillSaving = (await ownEvent(id)).state !== 'closed';
  }
  const joinSync = open && !f.enrolled && !f.declined && (start ? !stillSaving : !joinedBefore);
  return {
    handoff: !runtimesDone || !secondBrainDone || joinSync,
    joinSync,
    event: now.state,
    eventId,
    opensAt: open ? now.opensAt : null,
    runtimesDone,
    secondBrainDone,
    enrolled: f.enrolled,
    declined: f.declined,
    finished: f.finished,
    closed: f.closed,
    announced: f.announced,
    joinedBefore,
    stillSaving,
    session1: !!s.session1,
  };
}

if (require.main === module) {
  status({ start: process.argv.includes('--start') }).then((r) => process.stdout.write(JSON.stringify(r) + '\n'));
}
module.exports = { status };
