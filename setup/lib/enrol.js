#!/usr/bin/env node
'use strict';
// Session 1 only. The one place a laptop starts syncing to Vimigo, and only
// into the event Vimigo's server says is open right now (lib/event.js).
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const identity = require('./identity.js');
const { decode } = require('./endpoint.js');
const { home, claudeApp, isSandboxed } = require('./paths.js');
const { currentEvent, ownEvent } = require('./event.js');
const MANIFEST = 'https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/manifest.json';

const flag = (n) => { const a = process.argv; const i = a.indexOf(n); return i > -1 && a[i + 1] && !a[i + 1].startsWith('--') ? a[i + 1] : null; };
const out = (o) => { process.stdout.write(JSON.stringify(o) + '\n'); process.exit(o.ok ? 0 : 1); };

// Task 14 (H minor): the Codex app counts only when it has really been used
// here - signed in (auth.json) or holding a conversation (sessions/). A bare
// ~/.codex is not evidence: the Second Brain row prepares ~/.codex/AGENTS.md
// on every laptop, Codex or not. On a Mac, the app itself in /Applications
// counts too (never looked at under a test's fake home).
function codexInstalled() {
  const d = path.join(home(), '.codex');
  try { if (fs.statSync(path.join(d, 'auth.json')).size > 2) return true; } catch { /* not signed in */ }
  try { if (fs.statSync(path.join(d, 'sessions')).isDirectory()) return true; } catch { /* no sessions */ }
  if (process.platform === 'darwin' && !process.env.VIMIGO_FAKE_HOME && fs.existsSync('/Applications/Codex.app')) return true;
  return false;
}

function apps() {
  const list = [];
  if (fs.existsSync(claudeApp())) list.push('claude');
  if (codexInstalled()) list.push('codex');
  // Which app is actually running this enrolment, best-effort - never the
  // reason enrolment fails. CLAUDECODE is Claude Code's own documented
  // marker. Codex detection is deliberately left out: the only CODEX_*
  // variables found on a machine with the Codex app installed
  // (CODEX_COMPANION_SESSION_ID, CODEX_MANAGED_BY_NPM,
  // CODEX_SANDBOX_NETWORK_DISABLED, CODEX_THREAD_ID, ...) all name a
  // companion/wrapper layer, not confirmed to be what a participant's own
  // Codex app session sets - so nothing is guessed here.
  try {
    if (process.env.CLAUDECODE === '1') {
      const entry = process.env.CLAUDE_CODE_ENTRYPOINT;
      list.push(entry ? `Claude Code (${entry})` : 'Claude Code');
    }
  } catch { /* never fails enrolment over this */ }
  return list;
}

async function main() {
  // Participants' computers are only Windows or macOS. Refusing here rather
  // than proceeding means an AI running inside a Linux sandbox (Claude
  // Cowork, a container) can never enrol a laptop it is not actually on.
  if (isSandboxed()) out({ ok: false, reason: 'sandbox' });
  const name = flag('--name'); const company = flag('--company'); const role = flag('--role');
  if (!name || !company || !role) out({ ok: false, reason: 'usage' });
  // A decline is permanent until the owner themselves asks to start saving
  // again - never cleared by this running again on its own. `--resume` is
  // the one explicit way past it, and only ever typed because the owner
  // asked; a normal call refuses instead of quietly re-enrolling somebody
  // who said no.
  const resume = process.argv.includes('--resume');
  const src = flag('--manifest') || MANIFEST;
  let m;
  try {
    m = /^https?:/.test(src)
      ? await (await fetch(src, { cache: 'no-store', signal: AbortSignal.timeout(10000) })).json()
      : JSON.parse(fs.readFileSync(src, 'utf8'));
  } catch { out({ ok: false, reason: 'offline' }); }
  // Fix round 4: WHICH event, and whether one is open at all, is the server's
  // answer (GET /v1/current) - the manifest supplies only where the server is
  // and the `enroll:false` kill switch. `not-open` is the ordinary, expected
  // case: nothing open right now, or the kill switch is on.
  const now = await currentEvent(m);
  if (now.state === 'offline') out({ ok: false, reason: 'offline' });
  if (now.state !== 'open') out({ ok: false, reason: 'not-open' });
  const e = m.event.e;
  let base; try { base = decode(e); } catch { out({ ok: false, reason: 'no-event' }); }

  // A decline is permanent for the event it answered - until the owner
  // themselves asks to start again (`--resume`). A decline recorded for an
  // earlier event says nothing about this one (lib/identity.js factsFor).
  const prev = identity.read();
  if (identity.factsFor(prev, now.id).declined && !resume) out({ ok: false, reason: 'declined' });
  // Fix round 5 - the enrolment principle: an enrolment keeps running for its
  // own event until that event closes. A laptop still saving to an earlier
  // event (windows overlap) is never moved into the newer one - by the
  // server's own answer for that earlier event, and with no answer it is left
  // exactly as it is.
  if (prev && prev.event !== now.id && identity.mayBeSaving(prev)
      && (await ownEvent(prev)).state !== 'closed') out({ ok: false, reason: 'still-saving' });
  // The same principle for `--resume`: an owner who said no to the earlier
  // event they were saving to, while it is still open, resumes THAT one.
  if (resume && prev && prev.declined && prev.event !== now.id && identity.mayBeSaving({ ...prev, declined: false })
      && (await ownEvent(prev)).state !== 'closed') {
    const { declined, ...rest } = prev;
    identity.write(rest);
    out({ ok: true, event: prev.event });
  }

  const t = Date.now();
  const same = prev && prev.event === now.id && prev.token;
  const id = same ? prev.id : identity.newId();
  const profile = { name, company, role, platform: `${process.platform} ${os.release()}`, apps: apps() };
  let res;
  try {
    res = await fetch(base + '/v1/hello', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id, event: now.id, token: same ? prev.token : undefined, share: true, ...profile }),
      signal: AbortSignal.timeout(15000) });
  } catch { out({ ok: false, reason: 'offline' }); }
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.ok) out({ ok: false, reason: 'refused' });
  const enrolledAt = same ? prev.enrolledAt : new Date(t).toISOString();
  // Task 14: the event's own opening, from the server's answer - the sync job
  // sends conversations from then on, so the days before a late enrolment
  // count too. Kept from an earlier enrolment into the same event.
  const opens = same && Number.isFinite(prev.eventOpensAtMs) ? prev.eventOpensAtMs : Date.parse(now.opensAt || '');
  identity.write({ id, token: same ? prev.token : body.token, event: now.id, e, ...profile,
    enrolledAt, enrolledAtMs: Date.parse(enrolledAt), ...(Number.isFinite(opens) ? { eventOpensAtMs: opens } : {}),
    finished: false, closed: false,
    // Carried forward, never reset here: the disclosure may have already
    // been said (steps/03-sync/README.md says it, then runs `--announce`,
    // then this) - enrolling must not make it look unsaid to a later
    // session. `announced` holds the event id it was said for, so it only
    // ever counts for THIS event - carrying an old one forward as a bare
    // `true` would silently skip the line at the next event too.
    // `declined` is deliberately NOT carried forward - reaching this line at
    // all means either it was never set, or `--resume` was passed
    // specifically to clear it.
    ...(prev && prev.announced ? { announced: prev.announced } : {}) });
  // No lastHelloAt on purpose: the first scheduled run must check in itself, so
  // session 1's verifier is proving the JOB ran, not that enrolment did.
  out({ ok: true, event: now.id });
}
main();
