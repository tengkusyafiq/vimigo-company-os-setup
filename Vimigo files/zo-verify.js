#!/usr/bin/env node
//
// Asks the owner's Zo which integrations are actually connected.
//
// This replaces "you told me you linked it" with a real answer. Zo is the only
// thing that knows, so the laptop asks Zo rather than keeping a note of what
// the owner said.
//
// Usage:
//   node zo-verify.js <token>                     check everything
//   node zo-verify.js <token> --pair 60123456789  link a WhatsApp number
//
// --pair drives Zo from here rather than asking the owner to open Zo and
// explain what they want in their own words. It is repeatable: run it again
// with a different number to add another phone.
//
// Prints one JSON object to stdout:
//   {"ok":true,"integrations":{"gmail":{"connected":false},...}}
//   {"ok":false,"error":"...","code":"..."}
//
// Exit code is 0 whenever Zo answered, whatever the answer was. A non-zero exit
// means the question could not be asked at all, which is a different problem
// from an integration being unconnected and must not be reported as one.

const ENDPOINT = 'https://api.zo.computer/mcp';

// The integrations worth putting on a customer's checklist. Zo exposes many
// more through its catalog; these are the curated ones with first-class tools.
const DEFAULT_APPS = [
  'gmail',
  'google_calendar',
  'google_drive',
  'google_sheets',
];

// Where zo-whatsapp-setup.sh is installed on the customer's Zo.
const WHATSAPP_STATUS = '/home/workspace/Services/vimigo-setup/zo-whatsapp-setup.sh';
const AI_SIGNIN = '/home/workspace/Services/vimigo-setup/zo-ai-signin.sh';
const RESPONDER = '/home/workspace/Services/vimigo-setup/zo-whatsapp-responder.sh';

const TIMEOUT_MS = 30000;

function fail(code, error) {
  process.stdout.write(JSON.stringify({ ok: false, code, error }) + '\n');
  process.exit(1);
}

async function rpc(method, params, session, token) {
  const headers = {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
    // The endpoint negotiates streamable HTTP; it answers plain JSON when the
    // client will take either, which keeps this helper free of an SSE parser.
    'Accept': 'application/json, text/event-stream',
  };
  if (session) headers['Mcp-Session-Id'] = session;

  const body = { jsonrpc: '2.0', method };
  if (params !== undefined) body.params = params;
  // A notification has no id and expects no reply.
  if (!method.startsWith('notifications/')) body.id = Math.floor(Math.random() * 1e6) + 1;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }

  if (response.status === 401 || response.status === 403) {
    fail('token_rejected', 'Zo did not accept this account key.');
  }
  if (!response.ok) {
    fail('zo_unreachable', 'Zo could not be reached just now. Try again in a moment.');
  }

  const text = await response.text();
  // A notification legitimately returns an empty body.
  const json = text.trim() ? JSON.parse(text) : null;

  // Zo answers a rejected key with HTTP 200 and a JSON-RPC error, so the status
  // code alone never reveals it. Without this, a mistyped key surfaces as
  // "Zo did not open a session", which sends the owner looking for a fault that
  // is not there.
  if (json && json.error) {
    const message = json.error.message || 'Zo refused the request.';
    if (/authentication|unauthori[sz]ed|invalid api key|\b401\b/i.test(message)) {
      fail('token_rejected', 'Zo did not accept this account key. Check it and paste it again.');
    }
    fail('zo_refused', message);
  }

  return {
    session: response.headers.get('mcp-session-id') || session,
    json,
  };
}

// Zo reports an unconnected app in prose rather than a status field, so the
// verdict is read from the text. Only an explicit "no connected account" counts
// as disconnected: anything unrecognised is reported as unknown rather than
// guessed, because telling an owner their working integration is broken is
// worse than admitting we could not tell.
function readVerdict(text) {
  const lowered = (text || '').toLowerCase();
  if (lowered.includes('no connected account')) return { connected: false };
  if (lowered.includes('please encourage them to connect')) return { connected: false };
  if (!lowered.trim()) return { connected: null, detail: 'Zo returned nothing' };
  return { connected: true };
}

// Runs one command on the owner's Zo and returns its output as text.
//
// Zo answers with a Python repr of its result object, so newlines arrive as a
// literal backslash followed by 'n' rather than as real line breaks. Left
// as-is, any pattern that stops at whitespace runs straight through them: a
// URL match swallowed "\nCODE ABCD-1234" and handed the owner a broken link.
// Unescaped once here rather than in each caller.
async function runOnZo(command, description, session, token) {
  const { json } = await rpc('tools/call', {
    name: 'bash',
    arguments: { cmd: command, description },
  }, session, token);

  const content = json?.result?.content;
  let raw = Array.isArray(content) ? content.map((part) => part.text || '').join('\n') : '';

  // Zo wraps the result in a Python repr: CmdResult(stdout='...', stderr='...',
  // returncode=0). Substring matching survives that, but anything that cares
  // about whole lines does not - the first line of a QR code came back with
  // "CmdResult(stdout='" welded to the front of it.
  const wrapped = /CmdResult\(stdout='([\s\S]*?)',\s*stderr='([\s\S]*?)',\s*returncode=/.exec(raw);
  if (wrapped) raw = wrapped[1];

  return raw
    .replace(/\\r\\n/g, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\\t/g, '\t')
    .replace(/\\'/g, "'");
}

// Zo names the workspace in its initialize instructions, e.g.
// "This is **someone**'s Zo (https://someone.zo.computer)". The settings page
// lives on that subdomain, so the setup can send the owner straight to their
// own page instead of a generic one they then have to navigate.
function readWorkspaceUrl(instructions) {
  const match = /https:\/\/([a-z0-9-]+)\.zo\.computer/i.exec(instructions || '');
  return match ? `https://${match[1]}.zo.computer` : null;
}

function normalisePhone(phone) {
  return String(phone || '').replace(/[^0-9]/g, '');
}

async function pairWhatsApp(digits, session, token) {
  const text = await runOnZo(
    `if [ -x ${WHATSAPP_STATUS} ]; then ${WHATSAPP_STATUS} pair ${digits} 2>&1; else echo VIMIGO_NOT_INSTALLED; fi`,
    'Link a WhatsApp number to the bridge',
    session, token);

  if (text.includes('VIMIGO_NOT_INSTALLED')) {
    fail('whatsapp_not_installed',
      'The WhatsApp bridge is not installed on Zo yet.');
  }
  if (/already paired/i.test(text)) {
    process.stdout.write(JSON.stringify({ ok: true, alreadyPaired: true }) + '\n');
    return;
  }

  // The bridge prints the code in its JSON reply. Pull it out so the setup can
  // show it on its own, rather than making the owner read raw output.
  const code = (/"code"\s*:\s*"([^"]+)"/.exec(text) || [])[1]
    || (/\b([A-Z0-9]{4}-?[A-Z0-9]{4})\b/.exec(text) || [])[1]
    || null;

  process.stdout.write(JSON.stringify({
    ok: true,
    alreadyPaired: false,
    code,
    raw: code ? undefined : text.slice(0, 500),
  }) + '\n');
}

// Starts a Claude or Codex sign-in on Zo and returns what the owner must open.
// Codex prints a URL and a code and finishes by itself; Claude prints a URL and
// then waits for a code to be handed back, which is what --signin-code does.
async function startSignIn(which, session, token) {
  const text = await runOnZo(
    `if [ -x ${AI_SIGNIN} ]; then ${AI_SIGNIN} start ${which} 2>&1; else echo MISSING; fi`,
    `Start the ${which} sign-in`, session, token);

  if (text.includes('MISSING')) fail('signin_unavailable', 'Zo is not set up for this yet.');
  if (text.includes('ALREADY_SIGNED_IN')) {
    process.stdout.write(JSON.stringify({ ok: true, alreadySignedIn: true }) + '\n');
    return;
  }

  const url = (/URL (\S+)/.exec(text) || [])[1] || null;
  const code = (/CODE (\S+)/.exec(text) || [])[1] || null;
  if (!url) fail('signin_failed', 'Zo could not start the sign-in.');

  process.stdout.write(JSON.stringify(
    { ok: true, alreadySignedIn: false, which, url, code, needsCodeBack: which === 'claude' }) + '\n');
}

// Hands the code from the browser to the Claude sign-in still waiting on Zo.
async function submitSignInCode(code, session, token) {
  const text = await runOnZo(
    `${AI_SIGNIN} code claude '${String(code).replace(/'/g, "")}' 2>&1`,
    'Finish the Claude sign-in', session, token);

  process.stdout.write(JSON.stringify({
    ok: true,
    signedIn: text.includes('SIGNED_IN'),
    detail: text.includes('SIGNED_IN') ? undefined : text.slice(0, 300),
  }) + '\n');
}

// ---------------------------------------------------------------------------
// Skills
//
// A Zo skill is a folder under /home/workspace/Skills holding a SKILL.md, and
// nothing more: deleting one through the web page moves that folder to the
// Trash, which is what gave the game away. So the setup installs a skill by
// copying the folder across, and checks one is installed by looking for it.
//
// Zo has no catalogue API - every plausible endpoint answers 404 - so the
// folders travel with this setup. They are byte-for-byte what Zo's own
// catalogue installs, into the same folder names, so an owner who later
// installs one by hand gets the same thing rather than a second copy.
//
// The skill's real name comes from the "name:" line inside SKILL.md, not from
// the folder, because the two disagree: the catalogue puts "research-topic"
// into a folder called "zo-research-topic".
// ---------------------------------------------------------------------------

const fs = require('fs');
const path = require('path');

const SKILLS_ROOT = '/home/workspace/Skills';

// Base64 travels through a shell untouched - no quotes, no backslashes, no
// dollar signs - which is why the files go across encoded rather than as text.
// Chunks are a multiple of 4 so each one decodes on its own and can simply be
// appended to the file, with no temporary file to clean up afterwards.
const CHUNK_CHARS = 12000;
const BATCH_CHARS = 18000;

function readSkillName(skillMdPath) {
  const head = fs.readFileSync(skillMdPath, 'utf8').slice(0, 4000);
  const match = /^name:[ \t]*(.+)$/m.exec(head);
  return match ? match[1].trim() : null;
}

function listFiles(root, prefix) {
  const out = [];
  for (const entry of fs.readdirSync(path.join(root, prefix), { withFileTypes: true })) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...listFiles(root, relative));
    else if (entry.isFile()) out.push(relative);
  }
  return out;
}

function readLocalSkills(directory) {
  // The folders sit beside this file, so the common case needs no argument.
  directory = directory || path.join(__dirname, 'skills');
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const folder = path.join(directory, entry.name);
      const skillMd = path.join(folder, 'SKILL.md');
      if (!fs.existsSync(skillMd)) return null;
      return { folder: entry.name, name: readSkillName(skillMd) || entry.name, path: folder };
    })
    .filter(Boolean);
}

// Quoted in single quotes, so a folder name can never break out into the shell.
function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

// Turns one local file into the commands that recreate it on Zo. Base64 in
// pieces of a length divisible by four, so each piece decodes on its own and
// simply appends - no temporary file, and nothing for a shell to mangle.
function commandsForFile(localPath, remotePath, { executable = false } = {}) {
  const commands = [`mkdir -p ${shellQuote(path.posix.dirname(remotePath))}`];
  const encoded = fs.readFileSync(localPath).toString('base64');

  for (let at = 0; at < encoded.length; at += CHUNK_CHARS) {
    const piece = encoded.slice(at, at + CHUNK_CHARS);
    const redirect = at === 0 ? '>' : '>>';
    commands.push(`printf %s ${shellQuote(piece)} | base64 -d ${redirect} ${shellQuote(remotePath)}`);
  }
  if (executable) commands.push(`chmod +x ${shellQuote(remotePath)}`);
  return commands;
}

// Sent in batches rather than one command per file: Zo answers each call in a
// couple of seconds and serialises them within a session, so a file at a time
// is a minute of the owner watching a spinner.
async function runBatched(commands, description, session, token) {
  let batch = [];
  let size = 0;
  const flush = async () => {
    if (batch.length === 0) return;
    await runOnZo(batch.join(' && '), description, session, token);
    batch = [];
    size = 0;
  };
  for (const command of commands) {
    if (size + command.length > BATCH_CHARS) await flush();
    batch.push(command);
    size += command.length + 4;
  }
  await flush();
}

function commandsForSkill(skill) {
  const commands = [];
  const files = listFiles(skill.path, '');
  const directories = new Set();
  for (const file of files) {
    const parent = path.posix.dirname(`${SKILLS_ROOT}/${skill.folder}/${file.replace(/\\/g, '/')}`);
    directories.add(parent);
  }
  commands.push(`mkdir -p ${[...directories].map(shellQuote).join(' ')}`);

  for (const file of files) {
    const remote = `${SKILLS_ROOT}/${skill.folder}/${file.replace(/\\/g, '/')}`;
    const encoded = fs.readFileSync(path.join(skill.path, file)).toString('base64');
    for (let at = 0; at < encoded.length; at += CHUNK_CHARS) {
      const piece = encoded.slice(at, at + CHUNK_CHARS);
      const redirect = at === 0 ? '>' : '>>';
      commands.push(`printf %s ${shellQuote(piece)} | base64 -d ${redirect} ${shellQuote(remote)}`);
    }
  }
  return commands;
}

// ---------------------------------------------------------------------------
// The scripts that live on the customer's Zo
//
// These used to be copied across by hand, which is fine for the one Zo a
// developer is looking at and no use at all for a customer. The setup puts
// them there itself, from the copies beside this file, every run - so a fix
// shipped today reaches a Zo set up last week the next time the owner runs it.
// ---------------------------------------------------------------------------

const ZO_SCRIPTS_DIR = '/home/workspace/Services/vimigo-setup';
const ZO_SCRIPTS = [
  'zo-whatsapp-setup.sh',
  'zo-whatsapp-watchdog.sh',
  'zo-ai-signin.sh',
  'zo-whatsapp-multi.sh',
  'zo-whatsapp-responder.sh',
  'zo-whatsapp-responder.py',
  'zo-telegram-responder.sh',
  'zo-telegram-responder.py',
  'zo-second-brain.sh',
];

const SECOND_BRAIN = `${'/home/workspace/Services/vimigo-setup'}/zo-second-brain.sh`;

// Somewhere for the business to keep what it learns: plain Markdown folders,
// and an index over them so a phrase can be found across everything at once.
// Nothing is asked of the owner - it is a filing cabinet with the drawers
// labelled, empty and ready.
async function readSecondBrain(session, token) {
  const text = await runOnZo(
    `if [ -x ${SECOND_BRAIN} ]; then ${SECOND_BRAIN} status 2>/dev/null; fi`,
    'Check the company second brain', session, token).catch(() => '');

  const found = /VIMIGO_BRAIN folders=(\d+) notes=(\d+) indexed=(\w+)/.exec(text);
  if (!found) return null;
  return {
    folders: Number(found[1]),
    notes: Number(found[2]),
    indexed: found[3] === 'yes',
  };
}

const WHATSAPP_MULTI = `${'/home/workspace/Services/vimigo-setup'}/zo-whatsapp-multi.sh`;
const WHATSAPP_INSTANCES = '/home/workspace/Services/whatsapp-instances';

function employeeSlug(name) {
  return String(name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

// Gives one AI employee a WhatsApp number of their own.
//
// One bridge holds one linked device, so a second number means a second
// bridge: its own store, its own port, its own secrets, its own Zo service.
// zo-whatsapp-multi.sh has done that part since it was written; nothing ever
// called it, so every employee who chose WhatsApp got their number written on
// a note and nothing else.
//
// Returns the pairing code. It does not wait for the owner to type it in -
// that is the setup's job, because only the setup can keep them company while
// they do it.
async function addEmployeeNumber(options, session, token) {
  const name = String(options.name || '').trim();
  const slug = employeeSlug(name);
  const phone = String(options.phone || '').replace(/\D/g, '');

  if (!slug) fail('employee_invalid', 'The employee needs a name.');
  if (phone.length < 8) {
    fail('phone_invalid',
      'A full international phone number is required, digits only, e.g. 60123456789.');
  }
  if (slug === 'main') {
    fail('name_reserved',
      'That name belongs to your own assistant. Give this employee a different name.');
  }

  const dir = `${WHATSAPP_INSTANCES}/${slug}`;
  const text = await runOnZo(
    `if [ -x ${shellQuote(WHATSAPP_MULTI)} ]; then ` +
    `${shellQuote(WHATSAPP_MULTI)} add ${shellQuote(slug)} ${shellQuote(phone)} 2>&1; ` +
    `else echo VIMIGO_NOT_INSTALLED; fi`,
    `Give ${name} a WhatsApp number`, session, token);

  if (text.includes('VIMIGO_NOT_INSTALLED')) {
    fail('multi_missing', 'The setup files are not on Zo yet. Run the setup again.');
  }
  if (/bridge is not built yet/i.test(text)) {
    fail('bridge_missing',
      'Your own WhatsApp assistant has to be working before an employee can have a number.');
  }
  if (/already a number called/i.test(text)) {
    fail('name_taken',
      `There is already a number set up for ${name}. Let them go first, or use another name.`);
  }
  if (/No free port/i.test(text)) {
    fail('no_port', 'This Zo has no room for another number just now.');
  }

  const port = (/VIMIGO_WA_PORT\s+(\d+)/.exec(text) || [])[1] || null;
  if (!port || !text.includes('VIMIGO_WA_READY')) {
    fail('bridge_failed', `${name}'s number could not be started just now.`);
  }

  // Registered so Zo keeps it running. cmd_add only prints these instructions,
  // which is fine for somebody at a terminal and useless here - without this
  // the number works until the next restart and then quietly stops, which is
  // the worst of both: it looked set up, and a customer messaging it gets
  // nothing.
  try {
    await rpc('tools/call', {
      name: 'register_user_service',
      arguments: {
        label: `whatsapp-${slug}`,
        mode: 'process',
        entrypoint: `${dir}/run.sh`,
        workdir: dir,
      },
    }, session, token);
  } catch {
    // Already registered under that label.
  }

  const pairCode = (/VIMIGO_WA_CODE\s+(\S+)/.exec(text) || [])[1] || null;
  const alreadyPaired = text.includes('VIMIGO_WA_PAIRED');

  process.stdout.write(JSON.stringify({
    ok: true, slug, port: Number(port), pairCode, alreadyPaired,
  }) + '\n');
}

// Is that employee's number linked to a phone yet? Polled while the owner is
// typing the code in, so the setup can say it worked rather than ask.
async function readEmployeeNumber(name, session, token) {
  const slug = employeeSlug(name);
  const text = await runOnZo(
    `if [ -x ${shellQuote(WHATSAPP_MULTI)} ]; then ` +
    `${shellQuote(WHATSAPP_MULTI)} state ${shellQuote(slug)} 2>/dev/null; fi`,
    'Check that number', session, token).catch(() => '');

  const found = /VIMIGO_WA_STATE name=(\S*) port=(\S*) running=(\S+) paired=(\S+)/.exec(text);
  process.stdout.write(JSON.stringify({
    ok: true,
    slug,
    running: Boolean(found && found[3] === 'yes'),
    paired: Boolean(found && found[4] === 'yes'),
    port: found && found[2] ? Number(found[2]) : null,
  }) + '\n');
}

// Takes the number away again when an employee is let go. Without this the
// number stays linked to a bridge nobody owns and its port stays taken.
async function removeEmployeeNumber(name, session, token) {
  const slug = employeeSlug(name);
  if (!slug || slug === 'main') {
    process.stdout.write(JSON.stringify({ ok: false, error: 'not that one' }) + '\n');
    return;
  }

  await runOnZo(
    `if [ -x ${shellQuote(WHATSAPP_MULTI)} ]; then ` +
    `${shellQuote(WHATSAPP_MULTI)} remove ${shellQuote(slug)} 2>&1; fi`,
    'Take that number back', session, token).catch(() => '');

  // The responder for that number goes too. It is harmless once the bridge is
  // gone, but it would sit there answering nothing and holding a port.
  await runOnZo(
    `if [ -x ${shellQuote(RESPONDER)} ]; then ` +
    `${shellQuote(RESPONDER)} remove ${shellQuote(slug)} 2>&1; fi`,
    'Stop that number answering', session, token).catch(() => '');

  try {
    await rpc('tools/call', {
      name: 'delete_user_service',
      arguments: { label: `whatsapp-${slug}` },
    }, session, token);
  } catch {
    // Never registered, or already gone.
  }

  process.stdout.write(JSON.stringify({ ok: true, slug }) + '\n');
}

const TELEGRAM_RESPONDER = `${'/home/workspace/Services/vimigo-setup'}/zo-telegram-responder.sh`;

// Gives one AI employee its own Telegram bot.
//
// Zo's own connect_telegram links the OWNER'S account, so an employee sitting
// on it would answer as the boss. A bot is a separate identity, it costs
// nothing, and it needs no SIM card - which is what makes it the practical
// channel for employees, where WhatsApp needs a spare number each.
async function setUpTelegramEmployee(options, session, token) {
  const name = String(options.name || '').trim();
  const botToken = String(options.botToken || '').trim();

  // Written but not started. Zo starts it, when it is registered below, and
  // two copies polling one bot means Telegram refuses both with a 409 -
  // exactly once, permanently, with no way back. Whichever copy loses the race
  // dies, and which one that is comes down to timing.
  const parts = [shellQuote(TELEGRAM_RESPONDER), 'install', shellQuote(name),
    '--token', shellQuote(botToken), '--name', shellQuote(name), '--no-start'];
  if (options.brief) parts.push('--brief', shellQuote(options.brief));
  if (options.enable) parts.push('--enable');

  const text = await runOnZo(
    `if [ -x ${shellQuote(TELEGRAM_RESPONDER)} ]; then ${parts.join(' ')} 2>&1; else echo VIMIGO_NOT_INSTALLED; fi`,
    'Set up the employee on Telegram', session, token);

  if (text.includes('VIMIGO_NOT_INSTALLED')) {
    fail('responder_missing', 'The setup files are not on Zo yet. Run the setup again.');
  }
  if (/did not accept that token/i.test(text)) {
    fail('token_rejected', 'Telegram did not accept that token. Check it and paste it again.');
  }
  if (text.includes('VIMIGO_BOT_IN_USE')) {
    fail('bot_in_use',
      'That bot is already being used by something else, so it cannot also be an employee.');
  }

  const username = (/USERNAME\s+(\S+)/.exec(text) || [])[1] || null;
  const pairCode = (/PAIRCODE\s+(\S+)/.exec(text) || [])[1] || null;

  if (!username || !/ready on Telegram/.test(text)) {
    fail('telegram_failed', 'That employee could not be set up on Telegram just now.');
  }

  // Registered so Zo runs it and keeps running it. This is now the only thing
  // that starts it, so it is also what has to be waited on: a plain background
  // process would not survive a restart anyway, and an employee that stops
  // answering overnight is worse than one that never started.
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  try {
    await rpc('tools/call', {
      name: 'register_user_service',
      arguments: {
        label: `telegram-${slug}`,
        mode: 'process',
        entrypoint: `${ZO_SCRIPTS_DIR}/telegram/${slug}/run.sh`,
        workdir: `${ZO_SCRIPTS_DIR}/telegram/${slug}`,
      },
    }, session, token);
  } catch {
    // Already registered under that label, which is fine - the check below is
    // what decides whether this worked.
  }

  // Nothing is claimed until the employee's own log says it is listening.
  let listening = false;
  for (let attempt = 0; attempt < 12 && !listening; attempt++) {
    const seen = await runOnZo(
      `tail -5 ${shellQuote(`${ZO_SCRIPTS_DIR}/telegram/${slug}/logs/responder.log`)} 2>/dev/null || true`,
      'Wait for the employee to wake up', session, token).catch(() => '');
    if (/answering as @/.test(seen)) listening = true;
    else if (/already being used by something else/.test(seen)) {
      fail('bot_in_use',
        'That bot is already being used by something else, so it cannot also be an employee.');
    }
  }

  process.stdout.write(JSON.stringify({ ok: true, username, pairCode, listening }) + '\n');
}

async function installZoScripts(session, token) {
  const commands = [];
  const sent = [];
  for (const name of ZO_SCRIPTS) {
    const local = path.join(__dirname, name);
    if (!fs.existsSync(local)) continue;
    commands.push(...commandsForFile(local, `${ZO_SCRIPTS_DIR}/${name}`, { executable: true }));
    sent.push(name);
  }
  if (sent.length === 0) fail('scripts_missing', 'The Zo scripts that ship with this setup could not be found.');

  await runBatched(commands, 'Install the Vimigo scripts on Zo', session, token);

  // Read back rather than trust. A batch can be accepted and still not land.
  const listed = await runOnZo(
    `ls -1 ${ZO_SCRIPTS_DIR} 2>/dev/null || true`,
    'Check the scripts arrived', session, token);
  const there = listed.split('\n').map((line) => line.trim());
  return { sent, missing: sent.filter((name) => !there.includes(name)) };
}

// ---------------------------------------------------------------------------
// Building the WhatsApp assistant on a Zo that has never had one
//
// This is the step that was missing entirely. Pairing assumed the bridge was
// already built, which was true of exactly one Zo - the one it was developed
// against, where it had been built by hand. Every genuinely new customer would
// have been told "the bridge is not installed on Zo yet" with nothing offering
// to install it.
//
// It takes minutes, not seconds: Zo ships Go 1.19 and the bridge needs 1.25,
// so a fresh Zo downloads a toolchain and about 300MB of modules, then builds
// for a little over a minute. That is far too long to hold one call open, so
// it is started detached and watched.
// ---------------------------------------------------------------------------

const BRIDGE_BINARY =
  '/home/workspace/Services/whatsapp-mcp-go/whatsapp-bridge/whatsapp-bridge';
const INSTALL_LOG = '/tmp/vimigo-whatsapp-install.log';

async function startWhatsAppInstall(session, token) {
  const built = await runOnZo(
    `[ -x ${BRIDGE_BINARY} ] && echo VIMIGO_BUILT || echo VIMIGO_ABSENT`,
    'Check whether the assistant is built', session, token);

  if (built.includes('VIMIGO_BUILT')) {
    // Built is not the same as running, and the pairing that comes next talks
    // to a running bridge or fails with something that reads like a fault.
    const running = await ensureBridgeRunning(session, token);
    process.stdout.write(JSON.stringify({ ok: true, alreadyBuilt: true, running }) + '\n');
    return;
  }

  // The scripts have to be there before one of them can be run.
  const scripts = await installZoScripts(session, token);
  if (scripts.missing.length > 0) {
    fail('scripts_missing', 'Could not put the setup files on your Zo.');
  }

  // Detached, with its own log. setsid so it survives the shell that Zo used
  // to launch it, which otherwise takes the build down with it.
  await runOnZo(
    `rm -f ${INSTALL_LOG}; cd ${ZO_SCRIPTS_DIR} && ` +
    `setsid nohup ./zo-whatsapp-setup.sh install > ${INSTALL_LOG} 2>&1 < /dev/null & ` +
    'echo VIMIGO_STARTED',
    'Start building the assistant', session, token);

  process.stdout.write(JSON.stringify({ ok: true, alreadyBuilt: false, started: true }) + '\n');
}

// Makes sure the bridge is registered with Zo and actually running.
//
// Two separate failures, and both were seen for real. A service Zo does not
// know about dies with the next restart and never comes back. And a service Zo
// does know about can still be stopped: supervision gives up after a process
// fails enough times, which is exactly what happens while the code it points
// at is half-installed - so the thing that finally fixes the install finds a
// registered service that supervision has washed its hands of.
async function ensureBridgeRunning(session, token) {
    // Registering an existing label is harmless; Zo refuses and nothing here
    // depends on which of the two happened.
  try {
    await rpc('tools/call', {
      name: 'register_user_service',
      arguments: {
        label: 'whatsapp-bridge',
        mode: 'process',
        entrypoint: '/home/workspace/Services/whatsapp-mcp-go/run-bridge.sh',
        workdir: '/home/workspace/Services/whatsapp-mcp-go/whatsapp-bridge',
      },
    }, session, token);
  } catch {
    // Already registered.
  }

  // Started here regardless, because a registered service that supervision
  // has stopped retrying will not come back on its own. setsid so it outlives
  // the shell Zo used to launch it.
  const text = await runOnZo(
    'if curl -s --max-time 4 http://127.0.0.1:8080/ >/dev/null 2>&1; then echo VIMIGO_RUNNING; else ' +
    'cd /home/workspace/Services/whatsapp-mcp-go 2>/dev/null && ' +
    'setsid nohup ./run-bridge.sh >> /tmp/vimigo-bridge.log 2>&1 < /dev/null & ' +
    'sleep 12; ' +
    'if curl -s --max-time 4 http://127.0.0.1:8080/ >/dev/null 2>&1; then echo VIMIGO_STARTED; else echo VIMIGO_DEAD; fi; fi',
    'Make sure your assistant is running', session, token).catch(() => '');

  return !text.includes('VIMIGO_DEAD');
}

// Where the build has got to, in words the owner can read. Asked repeatedly by
// the setup so the screen can say something true while several minutes pass.
async function readWhatsAppInstallProgress(session, token) {
  const text = await runOnZo(
    `if [ -x ${BRIDGE_BINARY} ]; then echo VIMIGO_BUILT; fi; ` +
    `tail -40 ${INSTALL_LOG} 2>/dev/null || true`,
    'Check on the build', session, token).catch(() => '');

  const done = text.includes('VIMIGO_BUILT');

  // Registered and started the moment it exists, so it survives a Zo restart
  // and so the pairing that follows has something to talk to.
  if (done) await ensureBridgeRunning(session, token);

  // Read from the last stage reached, not the first, so it moves forward.
  let stage = 'getting your Zo ready';
  if (/Go toolchain/.test(text)) stage = 'getting the tools it needs';
  if (/Source code/.test(text)) stage = 'downloading your assistant';
  if (/Building/.test(text)) stage = 'building your assistant';
  if (/Both binaries built|4\./.test(text)) stage = 'nearly there';

  // A failure has to be reported as one. Left to the timeout, a build that
  // died in ten seconds would keep the owner watching a spinner for a quarter
  // of an hour before saying so.
  const failed = !done && /Build failed|Could not (download|clone)|did not install correctly|Could not install the build tools/.test(text);

  process.stdout.write(JSON.stringify({
    ok: true,
    built: done,
    failed,
    stage,
  }) + '\n');
}

// ---------------------------------------------------------------------------
// Making a WhatsApp number answer
// ---------------------------------------------------------------------------

// Everything below is interpolated into a shell command, so it is checked here
// rather than quoted and hoped for. A name is a slug; numbers are digits and
// commas; a brief is passed through single quoting, which the helper escapes.
function safeInstanceName(value) {
  const name = String(value || 'main').toLowerCase().replace(/[^a-z0-9-]/g, '');
  return name || 'main';
}

function safeNumberList(value) {
  return String(value || '')
    .split(',')
    .map((part) => part.replace(/\D/g, ''))
    .filter((part) => part.length >= 8)
    .join(',');
}

async function setUpResponder(options, session, token) {
  const script = `${ZO_SCRIPTS_DIR}/zo-whatsapp-responder.sh`;
  const instance = safeInstanceName(options.instance);
  const owners = safeNumberList(options.owners);

  // Written but not started, for the same reason as the Telegram one: Zo
  // starts it when it is registered below, and two copies fight over the port
  // - the loser dies on bind, and the settings just written are not the ones
  // in force. That produced "something else is already using that port" on a
  // machine where the something else was us.
  const parts = [shellQuote(script), 'install', shellQuote(instance), '--no-start'];
  if (options.personal) parts.push('--pa');
  if (options.selfChat) parts.push('--self');
  if (owners) parts.push('--owner', shellQuote(owners));
  if (options.name) parts.push('--name', shellQuote(options.name));
  if (options.brief) parts.push('--brief', shellQuote(options.brief));

  const text = await runOnZo(
    `if [ -x ${shellQuote(script)} ]; then ${parts.join(' ')} 2>&1; else echo VIMIGO_NOT_INSTALLED; fi`,
    'Make the number answer', session, token);

  if (text.includes('VIMIGO_NOT_INSTALLED')) {
    fail('responder_missing', 'The reply service is not on Zo yet. Run the setup again.');
  }

  // Registered so Zo keeps it running. A plain background process does not
  // survive a restart, and an assistant that stops answering overnight is
  // worse than one that never started.
  let registered = false;
  try {
    await rpc('tools/call', {
      name: 'register_user_service',
      arguments: {
        label: `whatsapp-responder-${instance}`,
        mode: 'process',
        entrypoint: `${ZO_SCRIPTS_DIR}/responders/${instance}/run.sh`,
        workdir: `${ZO_SCRIPTS_DIR}/responders/${instance}`,
      },
    }, session, token);
    registered = true;
  } catch {
    // Already registered, or Zo refused. It is running either way, and the
    // status below is what decides whether this worked.
  }

  // Given time to come up, since registering is now the only thing that
  // starts it, and asked what it actually did rather than assumed.
  let status = '';
  for (let attempt = 0; attempt < 10; attempt++) {
    status = await runOnZo(
      `sleep 3; ${shellQuote(script)} status ${shellQuote(instance)} 2>&1`,
      'Check the number is answering', session, token).catch(() => '');
    if (/is answering/.test(status)) break;
  }

  const answering = /is answering/.test(status);
  process.stdout.write(JSON.stringify({
    ok: answering,
    answering,
    registered,
    instance,
    allowed: owners ? owners.split(',').length : 0,
    detail: answering ? undefined : status.replace(/\x1b\[[0-9;]*m/g, '').trim().slice(0, 300),
  }) + '\n');
}

// What Zo actually has, read from the folders rather than from any note this
// setup kept. An owner who removed a skill last week must show as not having
// it, not as "you confirmed these once".
async function readInstalledSkills(session, token) {
  const text = await runOnZo(
    'for d in ' + SKILLS_ROOT + '/*/; do [ -f "$d/SKILL.md" ] || continue; ' +
    'n=$(sed -n \'s/^name:[[:space:]]*//p\' "$d/SKILL.md" | head -1); ' +
    'printf "%s\\n" "${n:-$(basename "$d")}"; done',
    'List the skills installed on Zo', session, token);

  return text.split('\n').map((line) => line.trim()).filter(Boolean);
}

async function installSkills(directory, session, token) {
  const local = readLocalSkills(directory);
  if (local.length === 0) {
    fail('skills_missing', 'The skills that ship with this setup could not be found.');
  }

  let installed = await readInstalledSkills(session, token);
  const missing = local.filter((skill) => !installed.includes(skill.name));

  // Already there is already done. Copying over an existing skill would throw
  // away any change the owner made to it, and there is no reason to.
  const added = [];
  for (const skill of missing) {
    await runBatched(commandsForSkill(skill), `Install the ${skill.name} skill`, session, token);
    added.push(skill.name);
  }

  // Re-read rather than assume. A batch can be accepted and still not land, and
  // "installed" has to mean Zo has it, not that a command was sent.
  installed = await readInstalledSkills(session, token);
  const wanted = local.map((skill) => skill.name);
  const stillMissing = wanted.filter((name) => !installed.includes(name));

  process.stdout.write(JSON.stringify({
    ok: stillMissing.length === 0,
    added: added.filter((name) => installed.includes(name)),
    installed: wanted.filter((name) => installed.includes(name)),
    missing: stillMissing,
  }) + '\n');
}

// ---------------------------------------------------------------------------
// Which model an AI employee runs on
//
// Only ever one the owner already pays for. Zo's own models (the "zo:" ones)
// are billed by use, and quietly putting eight employees on a metered model is
// a bill somebody did not agree to. The "byok:" ones run on the Claude or
// ChatGPT plan they signed in to earlier in this setup, which they have
// already paid for and which is the whole reason that step exists.
//
// The ids are per-owner, so they cannot be hard-coded - they are read back
// from Zo. If none are found the model is simply left unset rather than a
// paid one being chosen on the owner's behalf.
// ---------------------------------------------------------------------------

async function pickOwnPlanModel(session, token) {
  let text = '';
  try {
    const { json } = await rpc('tools/call', {
      name: 'tool_docs', arguments: { tool_name: 'create_persona' },
    }, session, token);
    const content = json?.result?.content;
    text = Array.isArray(content) ? content.map((p) => p.text || '').join('\n') : '';
  } catch {
    return null;
  }

  // Lines look like: byok:<uuid> (Claude Code - Opus -> opus)
  const found = [...text.matchAll(/(byok:[0-9a-f-]{36})\s*\(([^)]*)\)/gi)]
    .map((m) => ({ id: m[1], label: m[2].trim() }));

  return chooseOwnPlanModel(found);
}

// Kept separate from the network so it can be tested. The interesting cases
// are the ones nobody has in front of them: an owner who linked ChatGPT and
// not Claude, or Claude on a plan without Opus.
function chooseOwnPlanModel(available) {
  // The "byok:" test is here, not only in the caller that reads the list.
  // This function is the one that decides what an owner gets billed for, so
  // it is the one that has to refuse a metered model - a guarantee that lives
  // in the caller is a guarantee the next caller will not have.
  const found = (available || []).filter(
    (entry) => entry && entry.label && typeof entry.id === 'string' && entry.id.startsWith('byok:'));
  if (found.length === 0) return null;

  // Claude Opus first, then ChatGPT Luna - the order Tengku set. Anything else
  // on a plan they already pay for still beats a metered model, so an
  // unrecognised entry is preferred over nothing.
  const preferences = [
    (entry) => /claude/i.test(entry.label) && /opus/i.test(entry.label),
    (entry) => /luna/i.test(entry.label),
    (entry) => /claude/i.test(entry.label),
    (entry) => /gpt|codex|chatgpt/i.test(entry.label),
    () => true,
  ];
  for (const matches of preferences) {
    const hit = found.find(matches);
    if (hit) return hit;
  }
  return null;
}

// Drawn on Zo, which already has uv, rather than depending on anything being
// installed on the owner's computer. Half blocks so one character is two rows,
// which is the only way a QR fits in a terminal window and still scans.
async function drawQrCode(url, session, token) {
  try {
    const script = String.raw`import sys, segno
qr = segno.make(sys.argv[1], error='m')
m = [list(r) for r in qr.matrix]
for _ in range(2): m.insert(0, [0]*len(m[0]))
for _ in range(2): m.append([0]*len(m[0]))
m = [[0,0] + r + [0,0] for r in m]
if len(m) % 2: m.append([0]*len(m[0]))
for y in range(0, len(m), 2):
    line = ''
    for x in range(len(m[0])):
        top, bot = m[y][x], m[y+1][x]
        line += ' ' if (top and bot) else ('▄' if top else ('▀' if bot else '█'))
    print(line)`;
    const rendered = await runOnZo(
      `cat > /tmp/vimigo-qr.py <<'PYEOF'\n${script}\nPYEOF\n` +
      `uvx --from segno python /tmp/vimigo-qr.py ${shellQuote(url)} 2>/dev/null`,
      'Draw a QR code', session, token);
    return rendered.split('\n').filter((line) => /[▀▄█ ]{10,}/.test(line));
  } catch {
    // A missing QR is a smaller problem than no link at all.
    return [];
  }
}

async function main() {
  const token = process.argv[2];
  if (!token || !token.startsWith('zo_sk_')) {
    fail('token_missing', 'A Zo account key starting with zo_sk_ is required.');
  }

  const rest = process.argv.slice(3);
  const pairIndex = rest.indexOf('--pair');
  const apps = rest.length && pairIndex === -1 ? rest : DEFAULT_APPS;

  // Validated before any network handle exists. Calling process.exit while a
  // fetch is in flight trips a libuv assertion on Windows, which turns a clear
  // "that is not a phone number" into a crash dump.
  let phoneDigits = null;
  if (pairIndex !== -1) {
    phoneDigits = normalisePhone(rest[pairIndex + 1]);
    if (phoneDigits.length < 8) {
      fail('phone_invalid',
        'A full international phone number is required, digits only, e.g. 60123456789.');
    }
  }

  // Same reason again, and again not theoretical: these three checks started
  // life inside addEmployeeNumber, after the session was open. The refusal
  // printed correctly and then the process died on
  // "Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)", so the setup saw
  // a crash instead of "that is not a phone number".
  const numberAt = rest.indexOf('--employee-number');
  if (numberAt !== -1) {
    if (!employeeSlug(rest[numberAt + 1])) {
      fail('employee_invalid', 'The employee needs a name.');
    }
    if (employeeSlug(rest[numberAt + 1]) === 'main') {
      fail('name_reserved',
        'That name belongs to your own assistant. Give this employee a different name.');
    }
    if (normalisePhone(rest[numberAt + 2]).length < 8) {
      fail('phone_invalid',
        'A full international phone number is required, digits only, e.g. 60123456789.');
    }
  }

  // Checked here for the same reason, and it is not a theoretical concern:
  // done inside the responder step, after the session was open, this exact
  // refusal printed its answer and then crashed the process on a libuv
  // assertion.
  // A bot token looks like 123456789:AA... Checked before the session exists,
  // for the same reason as the two above: refusing after a fetch is in flight
  // crashes the process on a libuv assertion instead of printing the refusal.
  const telegramAt = rest.indexOf('--telegram-employee');
  if (telegramAt !== -1) {
    if (!String(rest[telegramAt + 1] || '').trim()) {
      fail('employee_invalid', 'The employee needs a name.');
    }
    const tokenAt = rest.indexOf('--bot-token');
    const supplied = tokenAt === -1 ? '' : String(rest[tokenAt + 1] || '').trim();
    if (!/^\d{6,}:[A-Za-z0-9_-]{30,}$/.test(supplied)) {
      fail('token_invalid',
        'That does not look like the token BotFather gives you. It is a long line with a colon in it.');
    }
  }

  if (rest.includes('--responder') && rest.includes('--pa')) {
    const ownerAt = rest.indexOf('--owner');
    if (!safeNumberList(ownerAt === -1 ? '' : rest[ownerAt + 1])) {
      fail('allowlist_required',
        'A personal assistant needs at least one phone number allowed to talk to it.');
    }
  }

  let session;
  let workspaceUrl = null;
  try {
    const initialized = await rpc('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'vimigo-setup', version: '1.0' },
    }, undefined, token);
    session = initialized.session;
    if (!session) fail('zo_no_session', 'Zo did not open a session.');
    workspaceUrl = readWorkspaceUrl(initialized.json?.result?.instructions);

    await rpc('notifications/initialized', undefined, session, token);
  } catch (error) {
    if (error.name === 'AbortError') fail('zo_timeout', 'Zo did not answer in time.');
    // The message is a plain sentence, not the network library's words. Every
    // screen that reports a refusal prints this text straight to the owner, and
    // "Could not reach Zo: fetch failed" is not something they can act on - it
    // reads as the product being broken rather than the wifi being off.
    fail('zo_unreachable', 'Could not reach Zo. Check the internet connection and try again.');
  }

  if (phoneDigits) {
    await pairWhatsApp(phoneDigits, session, token);
    return;
  }

  // Just the WhatsApp state, for polling while a pairing code is live. The
  // full check asks Zo six questions and takes about twenty seconds, which is
  // useless inside a loop counting down a two-minute code.
  if (rest.includes('--whatsapp-only')) {
    const text = await runOnZo(
      `if [ -x ${WHATSAPP_STATUS} ]; then ${WHATSAPP_STATUS} status 2>&1; else echo VIMIGO_NOT_INSTALLED; fi`,
      'Read the WhatsApp bridge status', session, token).catch(() => '');

    const linked = /linked and logged in|"logged_in":\s*true/i.test(text);
    process.stdout.write(JSON.stringify({ ok: true, linked }) + '\n');
    return;
  }

  // Hires an AI employee: a Zo persona with a name and a job description.
  // Permissions are left as Zo's default, which is everything, because a new
  // employee that cannot do anything is a worse first impression than one that
  // can do too much - and the owner can narrow it on their personas page.
  const hireIndex = rest.indexOf('--hire');
  if (hireIndex !== -1) {
    const name = rest[hireIndex + 1];
    const prompt = rest[hireIndex + 2];
    if (!name || !prompt) fail('hire_invalid', 'A name and a job description are required.');

    const model = await pickOwnPlanModel(session, token);

    const personaArguments = { name, prompt };
    if (model) personaArguments.model = model.id;

    const { json } = await rpc('tools/call', {
      name: 'create_persona',
      arguments: personaArguments,
    }, session, token);

    const content = json?.result?.content;
    const text = Array.isArray(content) ? content.map((p) => p.text || '').join('\n') : '';
    const id = (/id='([^']+)'/.exec(text) || /"id"\s*:\s*"([^"]+)"/.exec(text) || [])[1] || null;

    if (!id) fail('hire_failed', 'Zo did not create the employee.');
    process.stdout.write(JSON.stringify({
      ok: true, id, name,
      model: model ? model.label : null,
      ownPlan: Boolean(model),
    }) + '\n');
    return;
  }

  // Removes an employee by name, so the hiring can be tested again. Zo wants
  // an id, so the name is looked up first.
  const fireIndex = rest.indexOf('--fire');
  if (fireIndex !== -1) {
    const wanted = rest[fireIndex + 1];
    if (!wanted) fail('fire_invalid', 'A name is required.');

    const listed = await rpc('tools/call', { name: 'list_personas', arguments: {} }, session, token);
    const listContent = listed.json?.result?.content;
    const listText = Array.isArray(listContent)
      ? listContent.map((p) => p.text || '').join('\n') : '';

    // Paired up in order, so the right id goes with the right name.
    const ids = [...listText.matchAll(/id='([^']+)'/g)].map((m) => m[1]);
    const names = [...listText.matchAll(/name='([^']+)'/g)].map((m) => m[1]);
    const at = names.indexOf(wanted);
    if (at === -1 || !ids[at]) fail('fire_not_found', `No employee called ${wanted}.`);

    await rpc('tools/call', {
      name: 'delete_persona', arguments: { persona_id: ids[at] },
    }, session, token);

    process.stdout.write(JSON.stringify({ ok: true, removed: wanted }) + '\n');
    return;
  }

  // Who has already been hired, so the setup never creates a duplicate.
  if (rest.includes('--employees')) {
    const { json } = await rpc('tools/call', {
      name: 'list_personas', arguments: {},
    }, session, token);

    const content = json?.result?.content;
    const text = Array.isArray(content) ? content.map((p) => p.text || '').join('\n') : '';
    const names = [...text.matchAll(/name='([^']+)'/g)].map((m) => m[1]);
    process.stdout.write(JSON.stringify({ ok: true, employees: names }) + '\n');
    return;
  }

  // Puts this setup's own scripts on the customer's Zo. Runs every time, so a
  // fix shipped today reaches a Zo that was set up last week.
  if (rest.includes('--install-zo-scripts')) {
    const result = await installZoScripts(session, token);
    process.stdout.write(JSON.stringify({
      ok: result.missing.length === 0,
      installed: result.sent.filter((name) => !result.missing.includes(name)),
      missing: result.missing,
    }) + '\n');
    return;
  }

  // Sets up the company second brain: folders, an index, and Obsidian settings.
  if (rest.includes('--second-brain')) {
    await runOnZo(
      `if [ -x ${SECOND_BRAIN} ]; then ${SECOND_BRAIN} install 2>&1; else echo VIMIGO_NOT_INSTALLED; fi`,
      'Set up the company second brain', session, token);

    // Read back rather than trusted, as everywhere else.
    const state = await readSecondBrain(session, token);
    process.stdout.write(JSON.stringify({
      ok: Boolean(state && state.folders > 0),
      folders: state ? state.folders : 0,
      notes: state ? state.notes : 0,
      indexed: Boolean(state && state.indexed),
    }) + '\n');
    return;
  }

  // Gives one AI employee a WhatsApp number of their own.
  const employeeNumberIndex = rest.indexOf('--employee-number');
  if (employeeNumberIndex !== -1) {
    await addEmployeeNumber({
      name: rest[employeeNumberIndex + 1],
      phone: rest[employeeNumberIndex + 2],
    }, session, token);
    return;
  }

  const employeeNumberStateIndex = rest.indexOf('--employee-number-status');
  if (employeeNumberStateIndex !== -1) {
    await readEmployeeNumber(rest[employeeNumberStateIndex + 1], session, token);
    return;
  }

  const employeeNumberRemoveIndex = rest.indexOf('--employee-number-remove');
  if (employeeNumberRemoveIndex !== -1) {
    await removeEmployeeNumber(rest[employeeNumberRemoveIndex + 1], session, token);
    return;
  }

  // Gives one AI employee its own Telegram bot.
  const telegramEmployeeIndex = rest.indexOf('--telegram-employee');
  if (telegramEmployeeIndex !== -1) {
    const at = (flag) => {
      const found = rest.indexOf(flag);
      return found === -1 ? '' : (rest[found + 1] || '');
    };
    await setUpTelegramEmployee({
      name: rest[telegramEmployeeIndex + 1],
      botToken: at('--bot-token'),
      brief: at('--brief'),
      enable: rest.includes('--enable'),
    }, session, token);
    return;
  }

  // Whether that employee has said hello to its owner yet, and whether it is
  // answering everyone.
  const telegramStatusIndex = rest.indexOf('--telegram-employee-status');
  if (telegramStatusIndex !== -1) {
    const who = safeInstanceName(rest[telegramStatusIndex + 1]);
    const text = await runOnZo(
      `if [ -x ${shellQuote(TELEGRAM_RESPONDER)} ]; then ${shellQuote(TELEGRAM_RESPONDER)} status ${shellQuote(who)} 2>&1; fi`,
      'Check on that employee', session, token).catch(() => '');
    process.stdout.write(JSON.stringify({
      ok: true,
      running: /is answering/.test(text) || /waiting for you to say hello/.test(text),
      paired: /answering you only|answering everyone/.test(text),
      everyone: /answering everyone/.test(text),
    }) + '\n');
    return;
  }

  // Makes a linked number actually answer.
  const responderIndex = rest.indexOf('--responder');
  if (responderIndex !== -1) {
    const at = (flag) => {
      const found = rest.indexOf(flag);
      return found === -1 ? '' : (rest[found + 1] || '');
    };
    await setUpResponder({
      instance: rest[responderIndex + 1],
      owners: at('--owner'),
      name: at('--assistant-name'),
      brief: at('--brief'),
      personal: rest.includes('--pa'),
      selfChat: rest.includes('--self'),
    }, session, token);
    return;
  }

  // Builds the WhatsApp assistant on a Zo that has never had one.
  if (rest.includes('--install-whatsapp')) {
    await startWhatsAppInstall(session, token);
    return;
  }
  if (rest.includes('--install-whatsapp-progress')) {
    await readWhatsAppInstallProgress(session, token);
    return;
  }

  // Undoes what this setup did on Zo, one part at a time.
  //
  // Nothing here is all-or-nothing and nothing here is implied: each part is
  // asked for by name, because "start over" on a laptop costs an afternoon and
  // "start over" on Zo can cost a WhatsApp session somebody has been using for
  // months. The owner's own files, notes and account are never touched.
  if (rest.includes('--reset-zo')) {
    const undone = [];

    if (rest.includes('--replies')) {
      await runOnZo(
        `if [ -x ${RESPONDER} ]; then ${RESPONDER} remove main >/dev/null 2>&1; fi; echo done`,
        'Stop the assistant replying', session, token).catch(() => '');
      undone.push('replies');
    }

    if (rest.includes('--employees')) {
      const listed = await rpc('tools/call', { name: 'list_personas', arguments: {} }, session, token);
      const listContent = listed.json?.result?.content;
      const listText = Array.isArray(listContent) ? listContent.map((p) => p.text || '').join('\n') : '';
      const ids = [...listText.matchAll(/id='([^']+)'/g)].map((m) => m[1]);
      for (const id of ids) {
        await rpc('tools/call', {
          name: 'delete_persona', arguments: { persona_id: id },
        }, session, token).catch(() => null);
      }
      undone.push(`employees (${ids.length})`);
    }

    if (rest.includes('--skills')) {
      // Moved to Trash, the same place the website puts a deleted skill, so a
      // change of mind costs nothing.
      await runOnZo(
        'mkdir -p /home/workspace/Trash && ' +
        `for d in ${SKILLS_ROOT}/*/; do [ -d "$d" ] && mv -f "$d" /home/workspace/Trash/ 2>/dev/null; done; echo done`,
        'Move the skills to Trash', session, token).catch(() => '');
      undone.push('skills');
    }

    // The deep clean: the assistant's whole WhatsApp installation goes, and
    // the next setup builds it again from nothing.
    //
    // Moved to Trash, never deleted. That folder holds the linked session and
    // every message the business has exchanged - months of it - and a reset
    // that destroys those is not a reset, it is a loss. Rebuilding costs a few
    // minutes, so this is offered rather than assumed.
    if (rest.includes('--whatsapp-remove')) {
      for (const label of ['whatsapp-responder-main', 'whatsapp-bridge']) {
        await rpc('tools/call', {
          name: 'delete_user_service', arguments: { label },
        }, session, token).catch(() => null);
      }

      await runOnZo(
        'mkdir -p /home/workspace/Trash && ' +
        `if [ -x ${RESPONDER} ]; then ${RESPONDER} remove main >/dev/null 2>&1; fi; ` +
        'pkill -x whatsapp-bridge 2>/dev/null; sleep 2; ' +
        'if [ -d /home/workspace/Services/whatsapp-mcp-go ]; then ' +
        'mv -f /home/workspace/Services/whatsapp-mcp-go ' +
        '"/home/workspace/Trash/whatsapp-mcp-go.$(date -u +%Y%m%dT%H%M%SZ)"; fi; ' +
        'rm -rf /home/workspace/Services/vimigo-setup/responders/main; echo done',
        'Remove the WhatsApp assistant', session, token).catch(() => '');
      undone.push('whatsapp-removed');
    } else if (rest.includes('--whatsapp')) {
      // Signed out, not deleted. The store folder holds months of history and
      // is never removed by this setup - only the linked device goes.
      await runOnZo(
        'cd /home/workspace/Services/whatsapp-mcp-go/whatsapp-bridge 2>/dev/null || exit 0; ' +
        'k=$(grep -m1 "^WHATSAPP_API_KEY=" .env | cut -d= -f2-); ' +
        't=$(curl -s --max-time 10 -X POST http://127.0.0.1:8080/auth/login ' +
        '-H "Authorization: Bearer $k" | grep -oE \'"token":"[^"]+"\' | cut -d\'"\' -f4); ' +
        '[ -n "$t" ] && curl -s --max-time 15 -X POST http://127.0.0.1:8080/api/logout ' +
        '-H "Authorization: Bearer $t" >/dev/null; echo done',
        'Sign WhatsApp out', session, token).catch(() => '');
      undone.push('whatsapp');
    }

    process.stdout.write(JSON.stringify({ ok: true, undone }) + '\n');
    return;
  }

  // Proves the whole reply path without needing a second phone: hands the
  // responder a message that looks exactly like a real one, and the answer
  // comes back over WhatsApp to the number given.
  const testIndex = rest.indexOf('--responder-test');
  if (testIndex !== -1) {
    const instance = safeInstanceName(rest[testIndex + 1]);
    const to = safeNumberList(rest[testIndex + 2]);
    if (!to) fail('phone_invalid', 'A full phone number is needed to send the test to.');

    const text = await runOnZo(
      `if [ -x ${RESPONDER} ]; then ${RESPONDER} test ${shellQuote(instance)} ${shellQuote(to)} 2>&1; ` +
      `else echo VIMIGO_NOT_INSTALLED; fi`,
      'Send a test message', session, token);

    if (text.includes('VIMIGO_NOT_INSTALLED')) {
      fail('responder_missing', 'The reply service is not on Zo yet.');
    }
    process.stdout.write(JSON.stringify({ ok: /Sent\./.test(text) }) + '\n');
    return;
  }

  // Copies any missing skill folders onto Zo, then reads the folders back.
  const installSkillsIndex = rest.indexOf('--install-skills');
  if (installSkillsIndex !== -1) {
    await installSkills(rest[installSkillsIndex + 1], session, token);
    return;
  }

  // Read-only: which of the skills that ship with this setup are on Zo.
  const skillsIndex = rest.indexOf('--skills');
  if (skillsIndex !== -1) {
    const local = readLocalSkills(rest[skillsIndex + 1]).map((skill) => skill.name);
    const installed = await readInstalledSkills(session, token);
    process.stdout.write(JSON.stringify({
      ok: true,
      installed: local.filter((name) => installed.includes(name)),
      missing: local.filter((name) => !installed.includes(name)),
    }) + '\n');
    return;
  }

  // Connects Telegram: Zo issues a pairing code and a deep link, and the link
  // is rendered as a QR so the owner can point their phone at the screen.
  // Telegram lives on the phone, not the computer, so a link on a monitor is
  // the wrong shape - they would have to type it out by hand.
  if (rest.includes('--telegram')) {
    const { json } = await rpc('tools/call', {
      name: 'connect_telegram', arguments: {},
    }, session, token);

    const content = json?.result?.content;
    const text = Array.isArray(content) ? content.map((p) => p.text || '').join('\n') : '';

    const url = (/https:\/\/telegram\.me\/\S+/.exec(text) || [])[0]?.replace(/[)\].,]+$/, '') || null;
    const code = (/`([A-Z0-9]{6,})`/.exec(text) || /code:\**\s*`?([A-Z0-9]{6,})`?/i.exec(text) || [])[1] || null;
    if (!url) fail('telegram_failed', 'Zo did not give a Telegram link.');

    const qr = await drawQrCode(url, session, token);
    process.stdout.write(JSON.stringify({ ok: true, url, code, qr }) + '\n');
    return;
  }

  // A QR for anything. The screen is on a laptop and the thing that has to act
  // on the link is a phone, so the shortest path between them is a camera -
  // and it is the only one that involves no typing at all.
  const qrIndex = rest.indexOf('--qr');
  if (qrIndex !== -1) {
    const wanted = String(rest[qrIndex + 1] || '');
    if (!/^https:\/\/[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+$/.test(wanted)) {
      fail('qr_invalid', 'That is not a link this can draw.');
    }
    process.stdout.write(JSON.stringify({
      ok: true, qr: await drawQrCode(wanted, session, token),
    }) + '\n');
    return;
  }

  // How many Telegram accounts are linked, so the setup can tell when one more
  // has arrived rather than asking the owner whether it worked.
  if (rest.includes('--telegram-status')) {
    const text = await runOnZo(
      `cat /root/.hermes/channel_directory.json 2>/dev/null || echo '{}'`,
      'Check linked Telegram accounts', session, token).catch(() => '{}');
    let linked = 0;
    try {
      const parsed = JSON.parse((/\{[\s\S]*\}/.exec(text) || ['{}'])[0]);
      linked = (parsed.platforms?.telegram || []).length;
    } catch { }
    process.stdout.write(JSON.stringify({ ok: true, linked }) + '\n');
    return;
  }

  const signInIndex = rest.indexOf('--signin');
  if (signInIndex !== -1) {
    const which = rest[signInIndex + 1];
    if (which !== 'claude' && which !== 'codex') {
      fail('signin_invalid', 'Say which one: claude or codex.');
    }
    await startSignIn(which, session, token);
    return;
  }

  const codeIndex = rest.indexOf('--signin-code');
  if (codeIndex !== -1) {
    await submitSignInCode(rest[codeIndex + 1], session, token);
    return;
  }

  // WhatsApp is not a Zo integration: it is a bridge running on the Zo server,
  // so its state is read by asking Zo to run the bridge's own status command
  // rather than by inspecting anything on this laptop.
  let whatsapp = { connected: null, answering: false, detail: 'not checked' };

  // Both shell out on Zo and neither depends on the other, so they go out
  // together rather than back to back.
  const [whatsappText, aiText, installedSkills, secondBrain, hiredEmployees] = await Promise.all([
    // An explicit if, not `test -x ... && ... || echo`. The status command
    // exits non-zero whenever WhatsApp is not yet paired, which is a normal
    // answer rather than a failure, and with `||` that exit code would report
    // a perfectly good install as missing.
    // Both halves in one command: linked, and answering. They are separate
    // things - a number can be perfectly linked and still reply to nobody,
    // which is exactly what every install did before the responder existed.
    runOnZo(
      `if [ -x ${WHATSAPP_STATUS} ]; then ${WHATSAPP_STATUS} status 2>&1; else echo VIMIGO_NOT_INSTALLED; fi; ` +
      `if [ -x ${RESPONDER} ]; then ${RESPONDER} status main 2>&1; fi`,
      'Read the WhatsApp bridge status', session, token).catch(() => ''),
    runOnZo(
      `if [ -x ${AI_SIGNIN} ]; then ${AI_SIGNIN} status 2>/dev/null; else echo '{}'; fi`,
      'Check which AI subscriptions Zo is signed in to', session, token).catch(() => ''),
    // Folded into the same session as the other two rather than costing a
    // separate run of this helper, because the opening check already takes
    // about twenty seconds and every extra question is felt.
    readInstalledSkills(session, token).catch(() => null),
    readSecondBrain(session, token).catch(() => null),
    // Who has been hired, read from Zo rather than from a note this setup
    // kept - somebody removed on the website has to disappear from here too.
    rpc('tools/call', { name: 'list_personas', arguments: {} }, session, token)
      .then(({ json }) => {
        const content = json?.result?.content;
        const text = Array.isArray(content) ? content.map((p) => p.text || '').join('\n') : '';
        return [...text.matchAll(/name='([^']+)'/g)].map((m) => m[1]);
      })
      .catch(() => null),
  ]);

  try {
    const text = whatsappText;
    const answering = /is answering/.test(text);
    if (text.includes('VIMIGO_NOT_INSTALLED')) {
      whatsapp = { connected: false, answering, detail: 'the bridge is not installed on Zo yet' };
    } else if (/linked and logged in|"logged_in":\s*true/i.test(text)) {
      whatsapp = { connected: true, answering };
    } else if (/not linked yet|pairing_required/i.test(text)) {
      whatsapp = { connected: false, detail: 'installed, waiting to be paired' };
    } else if (/not running/i.test(text)) {
      whatsapp = { connected: false, detail: 'the bridge is stopped' };
    } else {
      whatsapp = { connected: null, detail: 'Zo answered but the state was unclear' };
    }
  } catch (error) {
    whatsapp = { connected: null, detail: error.message };
  }

  // Whether Zo is signed in to an existing Claude or ChatGPT subscription. Zo
  // otherwise bills per use, so this is money rather than capability.
  let aiProviders = { claude: { loggedIn: null }, codex: { loggedIn: null } };
  try {
    const parsed = JSON.parse((/\{.*\}/s.exec(aiText) || ['{}'])[0]);
    aiProviders = {
      claude: { loggedIn: parsed.claude?.loggedIn ?? null },
      codex: { loggedIn: parsed.codex?.loggedIn ?? null },
    };
  } catch {
    // Left as null, which the screen reports as unknown rather than guessing.
  }

  // Issued together rather than one after another. Measured, this does NOT
  // currently make it faster - the whole check takes about the same either way,
  // so Zo appears to serialise requests within a session. Kept because it is
  // the correct shape for six independent questions and costs nothing, and it
  // will pick up any future concurrency for free. The waiting animation is what
  // actually makes the delay bearable, not this.
  const integrations = {};
  const answers = await Promise.all(apps.map(async (app) => {
    try {
      const { json } = await rpc('tools/call', {
        name: 'list_app_tools',
        arguments: { app_slug: app },
      }, session, token);

      const content = json?.result?.content;
      const text = Array.isArray(content)
        ? content.map((part) => part.text || '').join('\n')
        : '';
      return [app, readVerdict(text)];
    } catch (error) {
      // One integration failing must not lose the answers for the others.
      return [app, { connected: null, detail: error.message }];
    }
  }));
  for (const [app, verdict] of answers) integrations[app] = verdict;

  // null, not an empty list, when Zo could not be asked. "No skills installed"
  // and "could not tell" look identical on a checklist otherwise, and the first
  // one sends the setup off installing things that are already there.
  let skills = null;
  if (installedSkills) {
    const wanted = readLocalSkills().map((skill) => skill.name);
    skills = {
      installed: wanted.filter((name) => installedSkills.includes(name)),
      missing: wanted.filter((name) => !installedSkills.includes(name)),
    };
  }

  process.stdout.write(JSON.stringify(
    { ok: true, workspaceUrl, aiProviders, whatsapp, integrations, skills,
      secondBrain, employees: hiredEmployees }) + '\n');
}

// Run normally, but importable so the model choice can be tested without a
// network or a Zo.
if (require.main === module) {
  main().catch((error) => fail('unexpected', error.message));
} else {
  module.exports = { chooseOwnPlanModel };
}
