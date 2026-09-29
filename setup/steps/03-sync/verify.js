#!/usr/bin/env node
'use strict';
const identity = require('../../lib/identity.js');
const { decode } = require('../../lib/endpoint.js');
const { currentEvent, ownEvent } = require('../../lib/event.js');
const { schedulerOff } = require('../../lib/paths.js');
const receipt = require('../../lib/receipt.js');
(async () => {
  const id = identity.read();
  const fail = (why) => { receipt.clear('sync'); process.stdout.write(JSON.stringify({ ok: false, evidence: why }) + '\n'); process.exit(1); };
  const pass = (evidence) => { receipt.write('sync', { ok: true, evidence }); process.stdout.write(JSON.stringify({ ok: true, evidence }) + '\n'); };

  // Proof the SCHEDULED job is running for this identity's own event: it is
  // registered, it ran recently by itself (last-ok.json written by a --quiet
  // run - not the AI running sync.js by hand, and not enrolment's own
  // check-in), and Vimigo's server saw it. Answers the failure's evidence,
  // or null when it is saving. Read-only: it writes nothing on the server.
  async function notSaving() {
    if (!schedulerOff() && !require('../../lib/scheduler.js').status().registered) return 'not scheduled';
    let last = null;
    try { last = JSON.parse(require('node:fs').readFileSync(require('node:path').join(require('../../lib/paths.js').syncDir(), 'last-ok.json'), 'utf8')); } catch { /* none */ }
    if (!last || last.scheduled !== true || Date.now() - Date.parse(last.at) > 10 * 60_000) return 'no check-in yet';
    let r;
    try {
      r = await (await fetch(`${decode(id.e)}/v1/seen?event=${encodeURIComponent(id.event)}&id=${id.id}`,
        { headers: { 'x-token': id.token }, signal: AbortSignal.timeout(15000) })).json();
    } catch { return 'could not reach Vimigo'; }
    if (!r.ok || !r.recent) return 'no check-in yet';
    return null;
  }
  const saving = async () => { const why = await notSaving(); return why ? fail(why) : pass('saving to Vimigo'); };

  // The same rules lib/session1.js --start, lib/sync.js and lib/doctor.js use.
  //
  // 1. The event Vimigo's server says is open right now: a decline, a finish
  //    or a close recorded for THAT event settles this row; an enrolment in it
  //    must actually be saving.
  const now = await currentEvent();
  if (now.state === 'open') {
    const f = identity.factsFor(id, now.id);
    // Declined - before OR after enrolling (`sync.js --stop`, either way) -
    // is finished for this row, not a failure: the owner already said no, and
    // a later session must never ask again or enrol behind their back.
    // Checked before the token: a post-enrolment decline still carries one.
    if (f.declined) return pass('stopped at your request');
    if (f.enrolled) {
      if (f.closed) return pass('event closed');
      if (f.finished) return pass('all sent - finished');
      return saving();
    }
  }
  // 2. Fix round 5 - the enrolment principle: an enrolment in an EARLIER
  //    event keeps running for that event until the server says it has
  //    closed - windows can overlap, and /v1/current names only the newest.
  //    Asked of that event itself, never through the manifest's kill switch.
  //    A finished, closed or declined enrolment has stopped, and counts for
  //    nothing at a new event: START joins that one instead.
  //    The proof is read first: asking that event may itself be a hello,
  //    which would count as the check-in it is meant to prove.
  if (identity.mayBeSaving(id)) {
    const why = await notSaving();
    const own = await ownEvent(id);
    if (own.state === 'open') return why ? fail(why) : pass('saving to Vimigo');
    if (own.state === 'offline') return fail('could not reach Vimigo');
  }
  if (now.state === 'offline') return fail('could not reach Vimigo');
  return fail('not enrolled');
})();
